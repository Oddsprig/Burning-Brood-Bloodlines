extends RefCounted
## One live save worker + one dirty flag. Native runner owns the private save path.
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL save queue: ", why)

static func snapshot_calls() -> int:
	for row: Dictionary in Perf.snapshot()["jobs"]:
		if String(row["label"]) == "Autosave snapshot": return int(row["calls"])
	return 0

func saved() -> Dictionary:
	check(FileAccess.file_exists(Game.SAVE_PATH), "private save was written")
	if not FileAccess.file_exists(Game.SAVE_PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	check(parsed is Dictionary, "private save is complete valid JSON")
	check(not FileAccess.file_exists(Game.SAVE_PATH + ".tmp"), "atomic save leaves no temporary side file")
	return parsed if parsed is Dictionary else {}

static func bytes_at(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	# Never run these commands against a player's save, even outside the runner.
	check(Game.SAVE_PATH.begins_with("user://test_"), "runner supplied a private user save path")
	if not Game.SAVE_PATH.begins_with("user://test_"): return fails
	Game.wait_save()
	var original: Dictionary = {"day": Game.day, "gold": Game.gold, "world": Game.world,
		"company": Game.company, "stash": Game.stash, "squads": Game.squads, "rep": Game.rep,
		"contract": Game.contract, "process": Game.is_processing()}
	var original_rng: int = Game.rng.state
	var original_unit: int = Unit._next_uid
	var original_item: int = Item._next_uid
	Game.set_process(false)
	Game.company = []; Game.stash = []; Game.squads = {}; Game.rep = {}; Game.contract = {}
	Game.world = {"marker": "initial", "nested": {"value": "initial"}, "point": Vector2(3, 7)}
	var before_file: PackedByteArray = bytes_at(Game.SAVE_PATH)
	var calls_before: int = snapshot_calls()
	var gate := Semaphore.new()
	var blocker: int = WorkerThreadPool.add_task(gate.wait, false, "test save queue gate")
	Game._save_task = blocker
	for i in 20:
		Game.gold = 1201 + i; Game.day = float(i) + 1.5
		Game.world["marker"] = "latest %d" % i
		Game.save_game_async()
		check(Game._save_task == blocker and Game._save_pending, "blocked request %d retains one worker and dirty flag" % i)
	check(not WorkerThreadPool.is_task_completed(blocker), "deterministic worker blocker remains active")
	check(snapshot_calls() == calls_before, "20 blocked requests build no new save snapshots")
	check(bytes_at(Game.SAVE_PATH) == before_file, "blocked requests cannot write a save")
	gate.post(); Game.wait_save()
	check(Game._save_task == -1 and not Game._save_pending, "wait_save clears active task and flushes dirty flag")
	var data: Dictionary = saved()
	check(int(data.get("gold", -1)) == 1220 and float(data.get("day", -1)) == 20.5, "wait_save flush contains latest gold and day")
	check(String(data.get("world", {}).get("marker", "")) == "latest 19", "wait_save copies the latest world rather than the first request")

	# A normal worker receives an isolated native snapshot, not borrowed live data.
	Game.gold = 2000; Game.day = 30.25; Game.world["nested"]["value"] = "captured"
	calls_before = snapshot_calls()
	Game.save_game_async()
	check(snapshot_calls() == calls_before + 1 and Game._save_task != -1, "normal async request creates one measured snapshot")
	Game.gold = 2001; Game.day = 31.25; Game.world["nested"]["value"] = "changed after snapshot"
	Game.wait_save(); data = saved()
	check(int(data.get("gold", -1)) == 2000 and float(data.get("day", -1)) == 30.25, "live scalar changes do not leak into the captured worker snapshot")
	check(String(data.get("world", {}).get("nested", {}).get("value", "")) == "captured", "nested world containers are copied before worker writes")
	Game.save_game_async()
	for i in 20:
		Game.gold = 3001 + i; Game.day = 40.5 + float(i)
		Game.world["marker"] = "normal latest %d" % i
		Game.save_game_async()
	Game.wait_save(); data = saved()
	check(int(data.get("gold", -1)) == 3020 and float(data.get("day", -1)) == 59.5, "normal repeated requests persist newest values regardless of worker completion timing")
	check(String(data.get("world", {}).get("marker", "")) == "normal latest 19", "normal coalescing preserves latest world state")
	check(Game._save_task == -1 and not Game._save_pending, "normal wait leaves no deferred write")

	# Completion polling starts the latest dirty save without an explicit wait.
	gate = Semaphore.new()
	blocker = WorkerThreadPool.add_task(gate.wait, false, "test poll save queue gate")
	Game._save_task = blocker; calls_before = snapshot_calls()
	for i in 20:
		Game.gold = 4001 + i; Game.day = 70.75 + float(i)
		Game.world["marker"] = "polled latest %d" % i
		Game.save_game_async()
	check(snapshot_calls() == calls_before and Game._save_task == blocker and Game._save_pending, "polling case remains coalesced before gate release")
	gate.post()
	var deadline: int = Time.get_ticks_msec() + 2000
	while not WorkerThreadPool.is_task_completed(blocker) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	check(WorkerThreadPool.is_task_completed(blocker), "released blocker completes within bounded poll wait")
	Game._process(0.0)
	check(Game._save_task != blocker and not Game._save_pending, "completion poll replaces finished blocker with latest write")
	check(snapshot_calls() == calls_before + 1, "completion poll builds exactly one current snapshot")
	Game.wait_save(); data = saved()
	check(int(data.get("gold", -1)) == 4020 and float(data.get("day", -1)) == 89.75, "completion-polled save persists latest scalars")
	check(String(data.get("world", {}).get("marker", "")) == "polled latest 19", "completion-polled save persists latest world")
	check(Game._save_task == -1 and not Game._save_pending, "all queued writes drained before restoration")
	Game.day = float(original["day"]); Game.gold = int(original["gold"]); Game.world = original["world"]
	Game.company = original["company"]; Game.stash = original["stash"]; Game.squads = original["squads"]
	Game.rep = original["rep"]; Game.contract = original["contract"]
	Game.set_process(bool(original["process"]))
	check(Game.rng.state == original_rng and Unit._next_uid == original_unit and Item._next_uid == original_item, "save queue tests generate no people/items and consume no campaign RNG")
	check(Game.world == original["world"] and Game.company == original["company"] and Game.gold == int(original["gold"]) and Game.day == float(original["day"]), "native in-memory campaign references and scalars restored")
	print("Save queue performance: ", checks, " assertions; failures=", fails)
	return fails
