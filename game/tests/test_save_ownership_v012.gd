extends RefCounted
## Private, small native save fixture: no generation, load migration or campaign ticks.
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL save ownership: ", why)

static func _blocked_write(gate: Semaphore, path: String, snapshot: Dictionary) -> Variant:
	gate.wait()
	return Game._write_save(path, snapshot)

static func _json(value: Variant) -> String:
	return JSON.stringify(value)

func _read(path: String) -> Dictionary:
	check(FileAccess.file_exists(path), "private save exists")
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(parsed is Dictionary, "private save is complete JSON")
	return parsed if parsed is Dictionary else {}

static func _fixture() -> Dictionary:
	# Real native records, assigned test identities without allocating campaign UIDs.
	var u := Unit.new()
	u.uid = 401; u.name = "Registered save fixture"; u.home_town = "save_town"; u.family = 7
	u.body = BodyState.new()
	u.body.init_from_plan(DB.bodies["humanoid"], 70.0)
	var wound: Dictionary = u.body.wound_part("head")
	var layer: Dictionary = wound["layers"][0]
	layer["dmg"] = 0.25; layer["kind"] = "cut"; layer["bleed"] = 0.125
	u.body.blood = 88.5; u.body.permanent = ["native remembered injury"]
	u.notable = [["Remembered opponent", 3.5, 2.0]]
	u.look = {"seed": 731, "future_native": {"ordered": ["original", 7]}}
	var it := Item.new()
	it.uid = 901; it.tid = "arming_sword"; it.material = "copper"; it.quality = DB.LEGEND
	it.legend = {"nm": "Remembered blade", "gem": "ruby", "h": [[2.0, "original carrier"]]}
	it.mark = {"n": "Native smith", "future_native": {"owners": ["original"]}}
	u.equip = {"main_hand": it}
	var reserve := Item.new()
	reserve.uid = 902; reserve.tid = "nasal_helm"; reserve.material = "copper"
	reserve.mark = {"n": "Reserve smith", "future_native": ["original"]}
	var plots: Dictionary = {"own": PackedInt32Array([7, 8]), "st": PackedFloat32Array([0.5, 0.75]),
		"wide": PackedInt64Array([7000000001]), "money": PackedFloat64Array([12.125]),
		"flags": PackedByteArray([1, 2]), "names": PackedStringArray(["original"])}
	var typed: Dictionary[String, PackedInt32Array] = {"columns": PackedInt32Array([11, 12])}
	return {"unit": u, "item": it, "reserve": reserve, "plots": plots, "typed": typed}

func _mutate(f: Dictionary) -> void:
	f["plots"]["own"][0] = 99; f["plots"]["st"][0] = 0.25
	f["plots"]["wide"][0] = 8000000001; f["plots"]["money"][0] = 99.875
	f["plots"]["flags"][0] = 9; f["plots"]["names"][0] = "changed"
	f["typed"]["columns"][0] = 77
	var u: Unit = f["unit"]
	u.body.blood = 77.0; u.body.parts["head"]["layers"][0]["dmg"] = 0.75
	u.body.permanent[0] = "changed injury"; u.notable[0][0] = "changed opponent"
	u.look["future_native"]["ordered"][0] = "changed look"
	var it: Item = f["item"]
	it.wear = 2; it.legend["h"][0][1] = "changed carrier"
	it.mark["future_native"]["owners"][0] = "changed maker owner"
	f["reserve"].mark["future_native"][0] = "changed reserve"
	Game.squads[401]["uniform"]["main_hand"] = "changed uniform"
	Game.rep["fixture"]["history"][0] = "changed reputation"
	Game.contract["native"]["history"][0] = "changed contract"
	Game.provisions["meal"][0][0] = 2
	Game.food_clock["native"]["history"][0] = "changed clock"
	Game.gold = 1099; Game.day = 4.25

func _isolation(f: Dictionary) -> void:
	var rng_before: int = Game.rng.state
	var unit_before: int = Unit._next_uid
	var item_before: int = Item._next_uid
	var snapshot: Dictionary = Game._save_tree()
	var before: String = _json(snapshot)
	var gate := Semaphore.new()
	Game._save_receipt = {}
	Game._save_task = WorkerThreadPool.add_task(_blocked_write.bind(gate, Game.SAVE_PATH, snapshot), false, "test isolated save writer")
	_mutate(f)
	check(_json(snapshot) == before, "live packed/native nested edits cannot alter captured snapshot")
	check(int(snapshot["world"]["towns"]["save_town"]["econ"]["plots"]["own"][0]) == 7, "packed plot owner remains captured")
	check(int(snapshot["world"]["typed"]["columns"][0]) == 11, "typed dictionary packed value remains captured")
	check(snapshot["company"][0]["equip"]["main_hand"]["mk"]["future_native"]["owners"][0] == "original", "arbitrary nested maker mark remains captured")
	check(float(snapshot["company"][0]["body"]["parts"]["head"]["layers"][0]["dmg"]) == 0.25, "native wound layer remains captured")
	check(snapshot["squads"]["401"]["uniform"]["main_hand"] == "arming_sword", "nested squad rule remains captured")
	gate.post(); Game.wait_save()
	_read(Game.SAVE_PATH)
	check(FileAccess.get_file_as_string(Game.SAVE_PATH) == before, "blocked worker writes exactly its isolated pre-mutation tree")
	check(Game._save_task == -1 and not Game._save_pending, "blocked writer drains without retaining a queued snapshot")
	check(Game.rng.state == rng_before and Unit._next_uid == unit_before and Item._next_uid == item_before, "snapshot and writer preserve native RNG and UID counters")
	print("Save ownership checkpoint: native/packed isolation complete")

func _coalescing() -> void:
	var snapshot: Dictionary = Game._save_tree()
	var gate := Semaphore.new()
	var blocker: int = WorkerThreadPool.add_task(_blocked_write.bind(gate, Game.SAVE_PATH, snapshot), false, "test latest save writer")
	Game._save_receipt = {}
	Game._save_task = blocker
	var started_before: int = int(Game.save_stats()["started"])
	for i in 12:
		Game.gold = 2000 + i; Game.day = 5.5 + i
		Game.world["native_extra"]["ordered"][0] = "latest %d" % i
		Game.save_game_async()
		check(Game._save_task == blocker and Game._save_pending, "request %d stays one worker and one dirty flag" % i)
	var queued: Dictionary = Game.save_stats()
	check(int(queued["active_snapshots"]) == 1 and bool(queued["pending"]), "telemetry shows bounded active snapshot and latest request")
	check(int(queued["started"]) == started_before, "blocked requests create no additional snapshots")
	var latest: String = _json(Game._save_tree())
	gate.post(); Game.wait_save()
	_read(Game.SAVE_PATH)
	check(FileAccess.get_file_as_string(Game.SAVE_PATH) == latest, "dirty requests flush the entire latest native state")
	check(Game._save_task == -1 and not Game._save_pending, "latest flush drains all tasks/requests")
	var done: Dictionary = Game.save_stats()
	check(int(done["active_snapshots"]) == 0 and not bool(done["pending"]), "completed telemetry retains no active snapshot")
	check(bool(done["last_ok"]) and String(done["last_stage"]) == "complete" and int(done["last_error"]) == OK, "successful write is reported explicitly")
	check(int(done["serialized_bytes"]) == FileAccess.get_file_as_bytes(Game.SAVE_PATH).size(), "receipt reports actual serialized UTF-8 byte count")
	for key in ["last_snapshot_us", "last_encode_us", "last_write_us", "age_s"]:
		check(float(done[key]) >= 0.0, "bounded telemetry includes nonnegative " + key)
	print("Save ownership checkpoint: latest request coalescing complete")

func _readiness() -> void:
	var previous: PackedByteArray = FileAccess.get_file_as_bytes(Game.SAVE_PATH)
	var before: Dictionary = Game.save_stats()
	Game._save_ready = false
	for i in 3:
		Game.gold = 3000 + i
		Game.world["native_extra"]["ordered"][0] = "ready latest %d" % i
		Game.save_game_async()
	Game.wait_save()
	var deferred: Dictionary = Game.save_stats()
	check(not bool(deferred["ready"]) and bool(deferred["pending"]), "unfinished generation/history keeps only deferred request")
	check(int(deferred["active_snapshots"]) == 0 and int(deferred["started"]) == int(before["started"]), "unready requests and wait_save capture no partial world")
	check(FileAccess.get_file_as_bytes(Game.SAVE_PATH) == previous, "unready wait preserves previous complete save")
	check(int(deferred["epoch"]) == int(before["epoch"]), "readiness check itself does not replace campaign epoch")
	var latest: String = _json(Game._save_tree())
	Game.new_game_finalize(); Game.wait_save()
	check(bool(Game.save_stats()["ready"]) and not Game._save_pending, "finalization releases deferred save")
	_read(Game.SAVE_PATH)
	check(FileAccess.get_file_as_string(Game.SAVE_PATH) == latest, "finalization saves latest complete fixture rather than earlier partial request")
	print("Save ownership checkpoint: generation readiness barrier complete")

static func _linear_tree() -> Dictionary:
	# Frozen pre-slicing field layout; independent linear walker is still public.
	var data: Dictionary = {"version": 1, "seed": Game.seed_value, "day": Game.day, "gold": Game.gold,
		"next_unit_uid": Unit._next_uid, "company": Game.company.map(func(u): return u.to_dict()),
		"stash": Game.stash.map(func(it): return it.to_dict()), "squads": Game._keys_to_str(Game.squads),
		"rep": Game.rep, "location": Game.location, "provisions": Food.stock_to_save(Game),
		"rations": Game.rations, "food_clock": Game.food_clock}.duplicate(true)
	data["world"] = Game._serialize(Game.world)
	data["contract"] = Game._serialize(Game.contract)
	return data

func _sliced(tree: SceneTree) -> void:
	Game.wait_save()
	var screen: String = Game._active_screen
	var paused: bool = tree.paused
	var u: Unit = Game.company[0]
	var it: Item = u.equip["main_hand"]
	# A different real object can share a test UID; memoization must use object identity.
	var distinct := Item.new()
	distinct.uid = it.uid; distinct.tid = "nasal_helm"; distinct.material = "tin"
	distinct.mark = {"n": "Distinct native object with same test UID"}
	var distinct_person := Unit.new()
	distinct_person.uid = u.uid; distinct_person.name = "Distinct person with same test UID"
	distinct_person.body = BodyState.new()
	distinct_person.body.init_from_plan(DB.bodies["humanoid"], 70.0)
	Game.world["towns"]["save_town"]["shop"].append(distinct)
	Game.world["native_records"] = [u, u, it, it, distinct, distinct_person, distinct_person]
	var rows: Array = []
	for i in 4096: rows.append([i, {"native": "ordered", "value": i}])
	Game.world["native_bulk"] = rows
	for i in 8: Game.world["towns"]["empty_%d" % i] = {}
	Game.world["work"] = [["ownership_finish"]]
	Game._active_screen = "settings"
	for previously_paused: bool in [false, true]:
		tree.paused = previously_paused
		var before: Dictionary = Game.save_stats()
		Game.save_game_async()
		check(Game._save_capture == null and Game._save_task == -1 and Game._save_pending, "real-world request schedules after caller, pause=%s" % previously_paused)
		check(tree.paused == previously_paused and int(Game.save_stats()["started"]) == int(before["started"]), "scheduled request has not acquired hold or copied records")
		Game.gold += 1
		Game.world["native_extra"]["ordered"][0] = "caller finished %s" % previously_paused
		var expected: String = _json(_linear_tree())
		Game._process(0.0)
		var capture: SaveSnapshot = Game._save_capture
		check(capture != null and tree.paused and Game._save_task == -1, "process acquires consistent hold before worker starts")
		var held: Dictionary = Game.save_stats()
		check(bool(held["capturing"]) and int(held["active_snapshots"]) == 1 and int(held["started"]) == int(before["started"]) + 1, "active capture counts exactly one owned snapshot")
		if capture == null:
			Game.wait_save()
			continue
		check(not capture.step(1) and not capture._jobs.is_empty(), "positive tiny budget yields a genuinely incomplete native snapshot")
		var frozen: String = _json(_linear_tree())
		Game.advance_time(0.125, false, 0, 1) # Capture guard must return before native economy/movement.
		check(_json(_linear_tree()) == frozen, "capture guard prevents calendar/population/coin/RNG work")
		await tree.process_frame
		check(Game._save_capture == capture and tree.paused and _json(_linear_tree()) == frozen, "interframe hold preserves graph and queued native work")
		Game.save_game_async(); Game.save_game_async()
		check(Game._save_pending and int(Game.save_stats()["started"]) == int(held["started"]), "requests during capture coalesce without creating another tree")
		var slices: int = 0
		while Game._save_capture != null and slices < 120:
			Game._process(0.0)
			slices += 1
		check(Game._save_capture == null and tree.paused == previously_paused, "bounded completion releases capture and restores prior pause state")
		check(capture._jobs.is_empty() and capture._records.is_empty() and capture.data.is_empty(), "finished capture releases graph jobs, memo and output ownership")
		var finished: Dictionary = Game.save_stats()
		check(int(finished["capture_slices"]) >= 2 and int(finished["capture_worst_us"]) > 0 and int(finished["last_snapshot_us"]) >= int(finished["capture_worst_us"]), "slice telemetry records cooperative budget work without fabricated timing gates")
		check(int(finished["unit_records"]) == 2 and int(finished["item_records"]) == 3 and int(finished["reused_records"]) >= 5, "query-local memo reuses actual instances while retaining same-UID distinct records")
		check(_json(_linear_tree()) == frozen, "all capture slices leave native graph unchanged")
		# Read the first writer separately, then prove the coalesced follow-up is latest.
		if Game._save_task != -1: Game._retire_save()
		_read(Game.SAVE_PATH)
		check(FileAccess.get_file_as_string(Game.SAVE_PATH) == expected, "sliced save exactly matches frozen linear native output")
		Game.gold += 1
		Game.world["native_extra"]["ordered"][0] = "latest after capture %s" % previously_paused
		var latest: String = _json(_linear_tree())
		Game.wait_save()
		check(FileAccess.get_file_as_string(Game.SAVE_PATH) == latest and not Game._save_pending, "coalesced follow-up flushes latest complete state")
		check(int(Game.save_stats()["active_snapshots"]) == 0 and tree.paused == previously_paused, "all sliced save ownership drains without changing prior pause")
	Game.world.erase("work")
	Game._active_screen = screen
	tree.paused = paused
	print("Save ownership checkpoint: sliced native capture/identity/pause complete")

func _put(path: String, value: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "create private failure sentinel")
	if file == null: return false
	file.store_string(value); file.close()
	return true

func _failures() -> void:
	var base: String = Game.SAVE_PATH
	var target: String = base + ".ownership_open.json"
	var tmp: String = target + ".tmp"
	var marker: String = tmp + "/keep.txt"
	var prior: String = "{\"previous_complete\":true,\"coin\":17}"
	var made: bool = _put(target, prior)
	check(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(tmp)) == OK, "create nonempty temporary-path blocker")
	made = _put(marker, "keep open sentinel") and made
	if made:
		var before: Dictionary = Game.save_stats()
		Game.SAVE_PATH = target
		Game.save_game_async(); Game.wait_save()
		var after: Dictionary = Game.save_stats()
		check(int(after["failed"]) == int(before["failed"]) + 1, "open failure counted once")
		check(not bool(after["last_ok"]) and String(after["last_stage"]) == "open" and int(after["last_error"]) != OK, "open failure telemetry identifies stage/error")
		check(FileAccess.get_file_as_string(target) == prior, "open failure preserves previous complete save bytes")
		check(FileAccess.get_file_as_string(marker) == "keep open sentinel", "open failure does not remove unrelated blocking contents")
		check(int(after["active_snapshots"]) == 0 and not bool(after["pending"]), "failed worker drains its snapshot")
	Game.SAVE_PATH = base
	for path: String in [marker, tmp, target]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	target = base + ".ownership_rename.json"
	tmp = target + ".tmp"; marker = target + "/keep.txt"
	check(DirAccess.make_dir_absolute(ProjectSettings.globalize_path(target)) == OK, "create nonempty destination blocker")
	if _put(marker, "keep rename sentinel"):
		var before: Dictionary = Game.save_stats()
		Game.SAVE_PATH = target
		Game.save_game_async(); Game.wait_save()
		var after: Dictionary = Game.save_stats()
		check(int(after["failed"]) == int(before["failed"]) + 1, "rename failure counted once")
		check(not bool(after["last_ok"]) and String(after["last_stage"]) == "rename" and int(after["last_error"]) != OK, "rename failure telemetry identifies stage/error")
		check(FileAccess.get_file_as_string(marker) == "keep rename sentinel", "rename failure preserves existing destination contents")
		check(int(after["serialized_bytes"]) > 0, "rename failure retains encoded byte receipt")
		check(int(after["active_snapshots"]) == 0 and not bool(after["pending"]), "rename failure drains its snapshot")
	Game.SAVE_PATH = base
	for path: String in [tmp, marker, target]:
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Save ownership checkpoint: atomic failure preservation complete")

func run(tree: SceneTree) -> int:
	await tree.process_frame
	check(Game.SAVE_PATH.begins_with("user://test_"), "runner supplies a private save path")
	if not Game.SAVE_PATH.begins_with("user://test_"): return fails
	Game.wait_save()
	var fields: Array = ["seed_value", "day", "gold", "company", "stash", "squads", "rep", "world", "location", "contract", "provisions", "rations", "food_clock"]
	var original: Dictionary = {}
	for field: String in fields: original[field] = Game.get(field)
	var was_processing: bool = Game.is_processing()
	var original_rng: int = Game.rng.state
	var original_unit: int = Unit._next_uid
	var original_item: int = Item._next_uid
	var was_ready: bool = bool(Game.save_stats()["ready"])
	Game.set_process(false)
	Game._save_ready = true
	var f: Dictionary = _fixture()
	Game.company = [f["unit"]]; Game.stash = [f["reserve"]]
	Game.squads = {401: {"uniform": {"main_hand": "arming_sword"}}}
	Game.rep = {"fixture": {"history": ["original reputation"]}}
	Game.world = {"towns": {"save_town": {"econ": {"plots": f["plots"]}, "recruits": [f["unit"]], "shop": [f["item"]]}},
		"typed": f["typed"], "native_extra": {"ordered": ["original", {"value": 7}]}, "party": {"pos": Vector2(3, 7)}}
	Game.contract = {"native": {"history": ["original contract"]}}
	Game.provisions = {"meal": [[7, 0, "meat", "Mutton"]], "beer": [], "wine": []}
	Game.rations = {"food": "normal", "drink": "ration"}
	Game.food_clock = {"native": {"history": ["original clock"]}}
	Game.gold = 1001; Game.day = 3.25
	_isolation(f)
	_coalescing()
	_readiness()
	_failures()
	await _sliced(tree)
	Game.wait_save()
	for field: String in fields: Game.set(field, original[field])
	Game.set_process(was_processing)
	Game._save_ready = was_ready
	check(Game.rng.state == original_rng and Unit._next_uid == original_unit and Item._next_uid == original_item, "complete fixture creates no campaign identities or RNG draws")
	for field: String in fields:
		check(is_same(Game.get(field), original[field]) if original[field] is Dictionary or original[field] is Array else Game.get(field) == original[field], "restores original " + field)
	print("Save ownership v012: ", checks, " assertions; failures=", fails)
	return fails
