extends RefCounted
## Native campaign save performance: loads a copied player save (--save=<path>), or builds an exercised native save,
## through main.tscn and measures
## load, memory, objects, screen opens (incl. Dragons > All holdings), frame times while idle in menus and scrolling,
## and autosave cost/size.
var main: Node = null
var _deadline_msec: int = 0
var _budget_failed: bool = false

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	if not _budget_failed:
		printerr("FAIL: claude_realsave exceeded 150 seconds; incomplete measurement is a failure")
		_budget_failed = true
	return false

func _receipt_keys(receipt: Dictionary, label: String) -> bool:
	if receipt.has("completed") and receipt.has("failed") and receipt.has("last_ok"): return true
	printerr("FAIL: ", label, ": save_stats lacks a completed/failed receipt: ", receipt)
	return false

func frames(tree: SceneTree, n: int = 3) -> void:
	for i: int in n:
		if not _within_budget(): return
		await tree.process_frame
func mem() -> float: return snappedf(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0, 0.1)
func objs() -> int: return int(Performance.get_monitor(Performance.OBJECT_COUNT))
func measure(tree: SceneTree, secs: float) -> Dictionary:
	var times: Array = []
	var last := Time.get_ticks_usec(); var start := last
	while float(Time.get_ticks_usec() - start) / 1e6 < secs:
		if not _within_budget(): return {}
		await tree.process_frame
		var now := Time.get_ticks_usec(); times.append(float(now - last) / 1000.0); last = now
	times.sort()
	var tot := 0.0
	for x in times: tot += x
	return {"fps": snappedf(1000.0 * times.size() / tot, 0.1), "p50": snappedf(times[times.size() / 2], 0.1), "p95": snappedf(times[int(times.size() * 0.95)], 0.1), "worst": snappedf(times[-1], 0.1)}
func run(tree: SceneTree) -> int:
	_deadline_msec = Time.get_ticks_msec() + 150000
	_budget_failed = false
	var output_path: String = Game.SAVE_PATH
	var previous_main: Node = Game.main
	var previous_fps: int = Engine.max_fps
	var previous_window_size: Vector2i = tree.root.size
	var previous_window_position: Vector2i = tree.root.position
	var previous_no_focus: bool = tree.root.get_flag(Window.FLAG_NO_FOCUS)
	var had_guide_setting: bool = Game.settings.has("guide_seen")
	var guide_setting: Variant = Game.settings.get("guide_seen", null)
	var generation_size: String = WorldGen.gen_size
	var history_days: int = CampaignWorld.presim_span_days
	var next_creatures: bool = Monsters.new_world_creatures
	var result: int = await _run(tree)
	Game.wait_save()
	Game.SAVE_PATH = output_path
	if is_instance_valid(main):
		main.queue_free()
		main = null
		for frame: int in 2: await tree.process_frame
	Game.main = previous_main if is_instance_valid(previous_main) else null
	Engine.max_fps = previous_fps
	tree.root.size = previous_window_size
	tree.root.position = previous_window_position
	tree.root.set_flag(Window.FLAG_NO_FOCUS, previous_no_focus)
	WorldGen.gen_size = generation_size
	CampaignWorld.presim_span_days = history_days
	Monsters.new_world_creatures = next_creatures
	if had_guide_setting: Game.settings["guide_seen"] = guide_setting
	else: Game.settings.erase("guide_seen")
	if not _within_budget(): result += 1
	return result

func _run(tree: SceneTree) -> int:
	var path: String = ""
	var out: String = ""
	var seen: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		for option: String in ["--save=", "--out="]:
			if not argument.begins_with(option): continue
			if seen.has(option) or argument.trim_prefix(option) == "":
				printerr("FAIL: real-save options must be nonempty and supplied once: ", option)
				return 1
			seen[option] = true
			if option == "--save=": path = argument.trim_prefix(option)
			else: out = argument.trim_prefix(option)
	var save_target: String = Game.SAVE_PATH
	if not save_target.begins_with("user://test_"):
		printerr("FAIL: claude_realsave needs a runner-provided user://test_ output save")
		return 1
	var generated: bool = path == ""
	if generated:
		path = await _native_input(tree, save_target)
		if path == "": return 1
	if not FileAccess.file_exists(path):
		printerr("FAIL: claude_realsave copied campaign is missing or unreadable: ", path)
		return 1
	var input_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if input_bytes.is_empty():
		printerr("FAIL: claude_realsave copied campaign is empty or unreadable: ", path)
		return 1
	if ProjectSettings.globalize_path(save_target).simplify_path().to_lower() == ProjectSettings.globalize_path(path).simplify_path().to_lower():
		printerr("FAIL: claude_realsave needs distinct input and output saves")
		return 1
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	if not _within_budget(): return 1
	var r: Dictionary = {"save_bytes": input_bytes.size(), "input_sha256": FileAccess.get_sha256(path),
		"fixture_kind": "native_generated_exercised" if generated else "provided_copied_campaign", "mem_before": mem()}
	Game.wait_save()
	Game.SAVE_PATH = path
	var t: int = Time.get_ticks_usec()
	var ok: bool = Game.load_game()
	Game.SAVE_PATH = save_target
	r["load_ms"] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["loaded"] = ok
	if not ok:
		printerr("FAIL: native load rejected copied campaign: ", path)
		print("REALSAVE ", JSON.stringify(r))
		return 1
	var units := 0
	for wb in Game.world.get("warbands", {}).values(): units += (wb.get("units", []) as Array).size()
	r["warband_units"] = units
	r["towns"] = Game.world.get("towns", {}).size()
	r["dragons"] = Game.world.get("dragons", {}).get("records", {}).size()
	r["mem_after_load"] = mem(); r["objects_after_load"] = objs()
	if Dynasty.selected(Game).is_empty():
		var choices: Array = Dynasty.choices(Game)
		if choices.is_empty():
			printerr("FAIL: loaded real campaign has no selected house or native dynasty choices")
			return 1
		var pick: Dictionary = choices[0]
		var onboarding: Dictionary = HouseOnboarding.begin(Game, str(pick["town_id"]), str(pick["household_uid"]))
		if not bool(onboarding.get("ok", false)):
			printerr("FAIL: native house onboarding for copied campaign: ", onboarding.get("reason", ""))
			return 1
	Game.goto("map"); await frames(tree, 10)
	if not _within_budget(): return 1
	r["map_idle"] = await measure(tree, 6.0)
	if not _within_budget(): return 1
	var opens := {}
	for s in ["house", "court", "dragons", "muster", "politics", "population", "map"]:
		t = Time.get_ticks_usec(); Game.goto(s, {"back": "map"}); await frames(tree, 2)
		if not _within_budget(): return 1
		opens[s] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["open_ms"] = opens
	Game.goto("dragons", {"back": "map", "holdings": "all"}); 
	t = Time.get_ticks_usec(); await frames(tree, 2)
	if not _within_budget(): return 1
	r["dragons_all_open_ms"] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["dragons_all_idle"] = await measure(tree, 4.0)
	if not _within_budget(): return 1
	if out != "": tree.root.get_texture().get_image().save_png(out.path_join("dragons_all.png"))
	Game.goto("map"); await frames(tree, 5)
	if not _within_budget(): return 1
	t = Time.get_ticks_usec()
	var manual_before: Dictionary = Game.save_stats()
	if not _receipt_keys(manual_before, "before manual save"): return 1
	var saved_ok: bool = Game.save_game()
	Game.wait_save()
	var manual_receipt: Dictionary = Game.save_stats()
	r["manual_save_receipt"] = manual_receipt
	if not _receipt_keys(manual_receipt, "manual save"): return 1
	if not saved_ok or not bool(manual_receipt["last_ok"]) or int(manual_receipt["completed"]) <= int(manual_before["completed"]) or int(manual_receipt["failed"]) != int(manual_before["failed"]):
		printerr("FAIL: real campaign manual save has no successful completed receipt: ", manual_receipt)
		return 1
	r["save_ms"] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["new_save_bytes"] = FileAccess.get_file_as_bytes(Game.SAVE_PATH).size()
	if int(r["new_save_bytes"]) <= 0:
		printerr("FAIL: completed real campaign save contains no bytes")
		return 1
	var async_before: Dictionary = Game.save_stats()
	if not _receipt_keys(async_before, "before async save"): return 1
	t = Time.get_ticks_usec()
	Game.save_game_async(); 
	var worst := 0.0; var last := Time.get_ticks_usec()
	for i in 240:
		if not _within_budget(): return 1
		await tree.process_frame
		var now := Time.get_ticks_usec(); worst = maxf(worst, float(now - last) / 1000.0); last = now
	r["autosave_worst_frame_ms"] = snappedf(worst, 1)
	r["mem_end"] = mem(); r["objects_end"] = objs()
	Game.wait_save()
	var async_receipt: Dictionary = Game.save_stats()
	r["async_save_receipt"] = async_receipt
	if not _receipt_keys(async_receipt, "async save"): return 1
	var failures: int = 0
	if not bool(async_receipt["last_ok"]) or int(async_receipt["completed"]) <= int(async_before["completed"]) or int(async_receipt["failed"]) != int(async_before["failed"]):
		printerr("FAIL: real campaign async save has no successful completed receipt: ", async_receipt)
		failures += 1
	if FileAccess.get_file_as_bytes(Game.SAVE_PATH).is_empty():
		printerr("FAIL: completed real campaign async save contains no bytes")
		failures += 1
	if FileAccess.get_file_as_bytes(path) != input_bytes:
		printerr("FAIL: copied real-campaign input changed during measurement")
		failures += 1
	print("REALSAVE ", JSON.stringify(r))
	return failures

## A real serialized campaign built by native generation, onboarding, muster and time updates.
## This is labelled as generated evidence; it does not claim to be a human-played campaign.
func _native_input(tree: SceneTree, output_path: String) -> String:
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = false
	var generation: Dictionary = Game.new_game_begin(DevTools.WORLD_SEED)
	while not Game.new_game_slice(generation, 8000):
		if not _within_budget(): return ""
		await tree.process_frame
	var history: Dictionary = {}
	while CampaignWorld.presim_left(Game) > 0:
		if not _within_budget(): return ""
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	if not _within_budget(): return ""
	var seat: String = DevTools.choose_house(Game)
	if seat == "":
		printerr("FAIL: native save fixture has no eligible ruling household")
		return ""
	var raised: int = DevTools.raise_army(Game, seat, 2)
	if raised != 2 or Game.company.size() != 2:
		printerr("FAIL: native save fixture could not muster exactly two actual residents")
		return ""
	# Drain prior native save/work before asking for an elapsed quarter day.
	Game.wait_save()
	while not Game.world.get("work", []).is_empty():
		if not _within_budget(): return ""
		CampaignWorld.work_slice(Game, 8000)
		await tree.process_frame
	var exercised_from: float = Game.day
	Game.advance_time(0.25, false, 0, 8000)
	while not Game.world.get("work", []).is_empty():
		if not _within_budget(): return ""
		CampaignWorld.work_slice(Game, 8000)
		await tree.process_frame
	if not _within_budget(): return ""
	if not is_equal_approx(Game.day, exercised_from + 0.25):
		printerr("FAIL: native input did not actually advance the required quarter day")
		return ""
	if Game.company.size() != 2 or Dynasty.selected(Game).is_empty():
		printerr("FAIL: exercised native input lost its actual household or two-person company")
		return ""
	for unit: Unit in Game.company:
		var town: Dictionary = Game.world["towns"].get(unit.home_town, {})
		var family: Dictionary = People.fam_of(town, unit.family)
		var person: Array = Persons.by_uid(family, unit.uid) if not family.is_empty() else []
		if unit.dead or person.is_empty() or int(person[5]) != unit.uid:
			printerr("FAIL: native input company lost an actual living person's binding")
			return ""
	var input_path: String = output_path.get_basename() + "_native_input_%d.json" % Time.get_ticks_usec()
	if FileAccess.file_exists(input_path):
		printerr("FAIL: native save fixture input must be fresh: ", input_path)
		return ""
	Game.wait_save()
	Game.SAVE_PATH = input_path
	var before: Dictionary = Game.save_stats()
	var accepted: bool = Game.save_game()
	Game.wait_save()
	var receipt: Dictionary = Game.save_stats()
	Game.SAVE_PATH = output_path
	if not _receipt_keys(before, "native input before save") or not _receipt_keys(receipt, "native input save"): return ""
	if not accepted or not bool(receipt["last_ok"]) or int(receipt["completed"]) <= int(before["completed"]) or int(receipt["failed"]) != int(before["failed"]) or FileAccess.get_file_as_bytes(input_path).is_empty():
		printerr("FAIL: native exercised campaign has no completed input save: ", receipt)
		return ""
	return input_path
