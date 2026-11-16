extends RefCounted
## One strict #80 case on the complete native world. Lead/Test Bridge only.
## Lead/Test Bridge entry: --tests=tests/test_matchidle_sliced_equiv_v100.gd --watchdog=29
const Matching: GDScript = preload("res://tests/test_casual_matching.gd")
const NativeEconomy: GDScript = preload("res://tests/class_d_native_economy.gd")
const Fork: GDScript = preload("res://tests/turn_split_equiv_common.gd")
const WALL_MSEC: int = 24000
const JOB: String = "street_sweeper"
const HOUSEHOLDS: String = "Families.match_idle:loop:1135"
var _deadline_msec: int = 0
var _failure: String = ""
var _current: MatcherJob = null
var _requested_save: bool = false
var _receipt: Dictionary = {}

class MatcherJob extends "res://campaign/campaign_turn_job.gd":
	var atomic: bool = false

	func _init(job: Array) -> void:
		super(job)

	func _run(game: Variant) -> void:
		var e: Dictionary = game.world["towns"][header[1]]["econ"]
		if atomic:
			Families.match_idle(e)
		else:
			await _families_match_idle(e)
		_finished = true

func _require(ok: bool, reason: String) -> bool:
	if not ok and _failure.is_empty():
		_failure = reason
	return ok

func _within_budget() -> bool:
	return _require(Time.get_ticks_msec() < _deadline_msec, "24-second internal budget exceeded; incomplete case fails")

## The first funded one-place #80 case, using its actual donor/reservation helpers.
func _fixture(town: Dictionary, fixture: Variant) -> Dictionary:
	var prepared: Dictionary = fixture._prepare(town)
	if not _within_budget() or not _require(bool(prepared.get("ok", false)), str(prepared.get("reason", "prepare failed"))): return {}
	var original: Dictionary = prepared["econ"]
	var target: int = int(prepared["target"])
	var excluded: Array[int] = []
	excluded.assign(prepared["excluded"])
	var window: Dictionary = {}
	var last_reason: String = "no exact native donor"
	for rotation: int in (original["fams"] as Array).size():
		if not _within_budget(): return {}
		var e: Dictionary = original.duplicate(true)
		var local_town: Dictionary = town.duplicate(false)
		local_town["econ"] = e
		var reserved: Dictionary = NativeEconomy.reserve_casual(local_town, e, excluded, _deadline_msec, rotation)
		if not _require(bool(reserved.get("ok", false)), str(reserved.get("reason", "reservation failed"))): return {}
		var donors: Array[int] = []
		donors.assign(fixture._donors(e, JOB, 1, target))
		if not donors.is_empty():
			window = {"econ": e, "target": target, "donors": donors,
				"cleanup_family": prepared["cleanup_family"], "cleanup_pid": prepared["cleanup_pid"]}
		else:
			var constructed: Dictionary = fixture._construct_window(town, prepared, e, JOB, 1)
			if bool(constructed.get("ok", false)):
				window = constructed
			else:
				last_reason = str(constructed.get("reason", "native donor construction failed"))
		if not _within_budget(): return {}
		if not window.is_empty(): break
	if not _require(not window.is_empty(), "native donor search failed: " + last_reason): return {}
	var scenario: Dictionary = fixture._scenario(window, JOB, 1, 0.0)
	if not _require(bool(scenario.get("ok", false)), str(scenario.get("reason", "scenario failed"))): return {}
	var e: Dictionary = scenario["econ"]
	if not _require(bool(fixture._fund(e, JOB, float(e["cjcap"][JOB]))), "existing coin cannot fund the native sweeper bill"): return {}
	if not _require(int(fixture.fails) == 0 and bool(fixture._reservations(e)), "#80 preparation failed or reservations are unbalanced"): return {}
	return scenario

func _rows(e: Dictionary) -> Array[PackedByteArray]:
	var rows: Array[PackedByteArray] = []
	for family: Dictionary in e["fams"]:
		rows.append(var_to_bytes(Game._serialize(family)))
	return rows

func _ids(e: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for family: Dictionary in e["fams"]:
		ids.append(int(family["id"]))
	return ids

func _changes(before: Array[PackedByteArray], e: Dictionary) -> Array[int]:
	var ids: Array[int] = []
	for index: int in (e["fams"] as Array).size():
		if before[index] != var_to_bytes(Game._serialize(e["fams"][index])):
			ids.append(int(e["fams"][index]["id"]))
	return ids

func _idle_sum(e: Dictionary) -> int:
	var count: int = 0
	for family: Dictionary in e["fams"]:
		if not family.get("gone", false) and not family.get("estate", false):
			count += int(family["idle"])
	return count

func _rng_bytes() -> PackedByteArray:
	var stream: RandomNumberGenerator = CampaignWorld._rng(Game.world)
	return var_to_bytes([Game.rng.seed, Game.rng.state, stream.seed, stream.state, Game.world.get("rng_state", "")])

func _restore(fork: Variant, snapshot: Dictionary, side: Array) -> bool:
	# Native deserialization mutates its argument; keep the frozen master detached.
	var input: Dictionary = snapshot.duplicate(true)
	var input_side: Array = side.duplicate(true)
	fork._restore(input)
	fork._side_restore(input_side)
	if not _require(str(fork._failure).is_empty(), str(fork._failure)): return false
	return _require(var_to_bytes(Game._save_tree()) == var_to_bytes(snapshot) and var_to_bytes(fork._side()) == var_to_bytes(side),
		"independent fork changed the complete ordered input or side state")

func _install(job: Array, atomic: bool) -> bool:
	CampaignTurnJob.prepare_frame_head(Game.world)
	var head: Array = Game.world["work"][0]
	if not _require(head.size() == job.size() + 1 and head[-1] is CampaignTurnJob, "native prepared owner slot is missing"): return false
	_current = MatcherJob.new(job)
	_current.atomic = atomic
	_current.force_every = 0 if atomic else 1
	head[-1] = _current
	return true

func _dispatch(fork: Variant, budgeted: bool) -> void:
	Game._day_job_begin_frame(Time.get_ticks_usec())
	fork._native_one(budgeted)

func _outcome(e: Dictionary, before: Dictionary, target: int, later: int, fixture: Variant) -> bool:
	var family: Dictionary = e["fams"][target]
	var old_family: Dictionary = before["fams"][target]
	if not _require(int(family.get("cj", {}).get(JOB, 0)) == 1 and int(family["idle"]) == int(old_family["idle"]) - 1,
		"target did not take exactly one shift from its real idle adults"): return false
	if not _require(int(e["idle_n"]) == int(before["idle_n"]) - 1 and _idle_sum(e) == _idle_sum(before) - 1,
		"household or town idle counts changed by more or less than one"): return false
	if not _require(absf(float(e["cjused"].get(JOB, 0)) - float(before["cjused"].get(JOB, 0)) - 1.0) < 0.000001 and bool(fixture._reservations(e)),
		"actual adult/child reservations or named assignments are unbalanced"): return false
	if not _require(var_to_bytes(Game._serialize(e["cjcap"])) == var_to_bytes(Game._serialize(before["cjcap"])) and absf(NativeEconomy.money(e) - NativeEconomy.money(before)) < 0.000001,
		"native capacity or total coin changed"): return false
	if not _require(str(fixture._unchanged(e)) == str(fixture._unchanged(before)),
		"holder money, goods, paydays, wages, debts or sanitation service changed"): return false
	if not _require(var_to_bytes(Game._serialize(e["fams"][later])) == var_to_bytes(Game._serialize(before["fams"][later])),
		"later idle household lost its original casual holdings or other state"): return false
	for business: Dictionary in e["biz"]:
		if not _require(Businesses.takeable(business, e) == 0, "a regular funded offer remains after matching"): return false
	for job: String in e["cjcap"]:
		if not _require(Shelter.available_casual(e, job) == 0, "a funded casual offer remains after exhaustion: " + job): return false
	return true

func _save_guard() -> bool:
	var started: int = int(Game.save_stats()["started"])
	var generation: int = Game._save_generation
	var receipt_generation: int = Game._save_last_receipt_generation
	_requested_save = true
	Game.save_game_async()
	if not _require(not Game.save_game(), "held synchronous save reported a successful write"): return false
	Game.wait_save()
	if not _require(not Game.load_game(), "held production load was not refused"): return false
	return _require(int(Game.save_stats()["started"]) == started and Game._save_generation == generation
		and Game._save_last_receipt_generation == receipt_generation and Game._save_capture == null
		and Game._save_task == -1 and Game._save_pending, "held save started a capture/writer, advanced a receipt or lost its pending request")

func _case(tree: SceneTree, fixture: Variant, fork: Variant) -> bool:
	if not _require((Game.world["towns"] as Dictionary).size() >= 27, "complete native Normal world is missing"): return false
	var town_id: String = ""
	var town_ids: Array = Game.world["towns"].keys()
	town_ids.sort()
	for id: String in town_ids:
		var town: Dictionary = Game.world["towns"][id]
		if TownEcon.has_econ(town) and str(town["econ"]["culture"]) == "middle":
			town_id = id
			break
	if not _require(not town_id.is_empty(), "seed 2026 has no native middle-culture town"): return false
	var scenario: Dictionary = _fixture(Game.world["towns"][town_id], fixture)
	if not _within_budget() or scenario.is_empty(): return false
	var e: Dictionary = scenario["econ"]
	var target: int = int(scenario["target"])
	var ids: Array[int] = _ids(e)
	var target_index: int = ids.find(target)
	var later: int = -1
	if not _require(target_index > 0 and target_index == target, "native target index/order is missing"): return false
	var family: Dictionary = e["fams"][target]
	if not _require(int(family["idle"]) >= 2 and family.get("cj", {}).is_empty(), "native target lacks its two idle adults"): return false
	for index: int in (e["fams"] as Array).size():
		var holder: Dictionary = e["fams"][index]
		if holder.get("gone", false) or holder.get("estate", false): continue
		if index < target_index and not _require(int(holder["idle"]) == 0, "earlier household competes with the native target"): return false
		if index > target_index and int(holder["idle"]) > 0 and not holder.get("cj", {}).is_empty() and later < 0:
			later = index
	if not _require(later > target_index, "required later idle household with actual casual holdings is missing"): return false
	for business: Dictionary in e["biz"]:
		if not _require(Businesses.takeable(business, e) == 0, "a funded regular offer competes with this #80 case"): return false
	for job: String in e["cjcap"]:
		if not _require(Shelter.available_casual(e, job) == (1 if job == JOB else 0), "native single funded vacancy prerequisite failed: " + job): return false
	Game.world["towns"][town_id]["econ"] = e
	var before: Dictionary = e.duplicate(true)
	var rows: Array[PackedByteArray] = _rows(e)
	var job: Array = ["fam", town_id, int(Game.day)]
	var queue: Array = [job.duplicate(), ["matchidle_tail_a", int(Game.day)], ["matchidle_tail_b", int(Game.day)]]
	queue.append_array((Game.world.get("work", []) as Array).duplicate(true))
	Game.world["work"] = queue
	var tail: PackedByteArray = var_to_bytes(Game._serialize(queue.slice(1)))
	var snapshot: Dictionary = Game._save_tree()
	var side: Array = fork._side()
	var rng_before: PackedByteArray = _rng_bytes()
	if not _within_budget() or not _restore(fork, snapshot, side) or not _install(job, true): return false
	_dispatch(fork, false)
	if not _require(_current.done and _current.yields == 0 and Game._day_job_owner == null and not tree.paused, "atomic matcher did not finish/release synchronously"): return false
	var atomic_world: Dictionary = Game.world
	var atomic_e: Dictionary = Game.world["towns"][town_id]["econ"]
	if not _outcome(atomic_e, before, target, later, fixture): return false
	var changed: Array[int] = _changes(rows, atomic_e)
	if not _require(changed.size() == 1 and changed[0] == target and _ids(atomic_e) == ids, "atomic changed-household set or native family order is wrong"): return false
	if not _require(_rng_bytes() == rng_before and var_to_bytes(Game._serialize(Game.world["work"])) == tail, "atomic RNG or original queue tail changed"): return false
	var expected: PackedByteArray = var_to_bytes(Game._save_tree())
	var expected_world: PackedByteArray = var_to_bytes(Game._serialize(atomic_world))
	var expected_side: PackedByteArray = var_to_bytes(fork._side())
	if not _within_budget() or not _restore(fork, snapshot, side) or not _install(job, false): return false
	var sliced_e: Dictionary = Game.world["towns"][town_id]["econ"]
	if not _require(not is_same(Game.world, atomic_world) and not is_same(sliced_e, atomic_e)
		and not is_same(sliced_e["fams"][target], atomic_e["fams"][target]), "atomic and sliced worlds share mutable fixture state"): return false
	var first_frame: int = Engine.get_process_frames()
	var visited: Array[int] = []
	var observed_order: Array[int] = []
	var observed_rows: Array[PackedByteArray] = _rows(sliced_e)
	while not _current.done:
		if not _within_budget(): return false
		await tree.process_frame
		if not _within_budget(): return false
		_dispatch(fork, true)
		if not _current.done:
			var work: Array = Game.world["work"]
			if not _require(tree.paused and _current.holds_tree and Game._day_job_owner == _current
				and not work.is_empty() and work[0][-1] == _current, "suspended matcher lost its real owner/head/tree hold"): return false
			if not _require(work[0].slice(0, job.size()) == job and var_to_bytes(Game._serialize(work.slice(1))) == tail
				and Game.day == float(snapshot["day"]) and int(Game.world["last_day"]) == int(snapshot["world"]["last_day"]), "held effect day, header or original tail changed"): return false
			if _current.boundary == HOUSEHOLDS:
				var count: int = int(_current.visits.get(HOUSEHOLDS, 0))
				if not _require(count == visited.size() + 1 and count <= target_index + 1, "matcher restarted, skipped or visited a later household"): return false
				visited.append(int(sliced_e["fams"][count - 1]["id"]))
				if count == target_index + 1 and not _save_guard(): return false
			if _requested_save and not _require(Game._save_pending, "held save request disappeared before completion"): return false
		if _current.done or _current.boundary == HOUSEHOLDS:
			var current_rows: Array[PackedByteArray] = _rows(sliced_e)
			for index: int in current_rows.size():
				if current_rows[index] != observed_rows[index]:
					observed_order.append(int(sliced_e["fams"][index]["id"]))
			observed_rows = current_rows
	if not _within_budget(): return false
	if not _require(_current.yields > 0 and Engine.get_process_frames() > first_frame
		and int(_current.yielded_labels.get("Families.match_idle:loop:1125", 0)) > 0
		and int(_current.yielded_labels.get("Families.match_idle:loop:1131", 0)) > 0
		and int(_current.yielded_labels.get(HOUSEHOLDS, 0)) == target_index + 1, "required real business/casual/mid-household suspensions were not resumed"): return false
	if not _require(visited == ids.slice(0, target_index + 1) and int(_current.visits.get(HOUSEHOLDS, 0)) == target_index + 1,
		"household visitation order or early stop differs from the atomic exhaustion case"): return false
	if not _require(not tree.paused and Game._day_job_owner == null and not _current.holds_tree
		and _requested_save and Game._save_pending, "completion lost its pending save or failed to release its owner/tree"): return false
	if not _outcome(sliced_e, before, target, later, fixture): return false
	if not _require(_changes(rows, sliced_e) == changed and observed_order == changed and _ids(sliced_e) == ids,
		"changed households, change order or retained native family order differs"): return false
	if not _require(_rng_bytes() == rng_before and var_to_bytes(Game._serialize(Game.world["work"])) == tail, "sliced RNG or original queue tail changed"): return false
	if not _require(var_to_bytes(Game._save_tree()) == expected and var_to_bytes(fork._side()) == expected_side,
		"complete ordered native state, assignments, reservations, RNG, UIDs, records or side state differs"): return false
	if not _require(var_to_bytes(Game._serialize(atomic_world)) == expected_world, "sliced run mutated the retained independent atomic world"): return false
	_receipt = {"town": town_id, "target": target, "later": int(sliced_e["fams"][later]["id"]),
		"changed": changed, "household_visits": visited.size(), "yields": _current.yields,
		"business_yields": _current.yielded_labels.get("Families.match_idle:loop:1125", 0),
		"casual_yields": _current.yielded_labels.get("Families.match_idle:loop:1131", 0),
		"household_yields": _current.yielded_labels.get(HOUSEHOLDS, 0)}
	return _within_budget()

func run(tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	_deadline_msec = started + WALL_MSEC
	if not _require(Game._save_capture == null and Game._save_task == -1 and not Game._save_pending
		and Game._day_job_owner == null and not Game._day_job_dispatching
		and Game._day_job_actions.is_empty() and Game._day_job_observers.is_empty(), "isolated test requires no active save or campaign transaction"):
		printerr("MATCHIDLE SLICED EQUIV FAIL: ", _failure)
		return 1
	var old_process: bool = Game.is_processing()
	var old_screen: String = String(Game._active_screen)
	var old_paused: bool = tree.paused
	var old_fps: int = Engine.max_fps
	var old_size: String = WorldGen.gen_size
	var old_span: int = CampaignWorld.presim_span_days
	var old_worst: Dictionary = CampaignWorld.job_worst.duplicate()
	Game.set_process(false)
	Engine.max_fps = 0
	tree.paused = false
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.new_game(2026)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	Game._active_screen = "map"
	var fixture: Variant = Matching.new()
	fixture._deadline_msec = _deadline_msec
	var fork: Variant = Fork.new()
	var passed: bool = false
	if _within_budget():
		passed = await _case(tree, fixture, fork)
	# Release only this test's in-memory owner. Never dispatch a tail job or write a save.
	if _current != null:
		if Game._day_job_owner == _current:
			_current.after.clear()
			_current.release(Game)
			Game._day_job_owner = null
		var work: Array = Game.world.get("work", [])
		if not work.is_empty() and work[0][-1] == _current:
			work[0].pop_back()
	Game._day_job_dispatching = false
	Game._day_job_changed_pending = false
	Game._day_job_slice_frame = -1
	Game._day_job_budget_frame = -1
	Game._day_job_frame_started_usec = 0
	if _requested_save:
		Game._save_pending = false
	CampaignWorld.job_worst = old_worst
	Game._active_screen = old_screen
	Game.set_process(old_process)
	tree.paused = old_paused
	Engine.max_fps = old_fps
	if not passed or not _within_budget():
		printerr("MATCHIDLE SLICED EQUIV FAIL: ", _failure)
		return 1
	print("MATCHIDLE SLICED EQUIV CASE ", JSON.stringify(_receipt))
	print("MATCHIDLE SLICED EQUIV PASS: complete ordered native state and side state equal; later holdings retained; real suspensions; elapsed_ms=", Time.get_ticks_msec() - started)
	return 0
