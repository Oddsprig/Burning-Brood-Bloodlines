extends "res://tests/test_army_split_equiv.gd"
## Reuse r11 NativeFixture, complete restore, deadline and deferred-action helper.
## One native warmup, then all real headers of one day in their native order.
const GROUPS: Dictionary = {
	"sickness": {"day": 11, "kinds": ["sick", "sick_w"], "keys": ["sick/1", "sick/2", "sick/3", "sick_w"]},
	"family_town": {"day": 13, "kinds": ["fam", "fam2", "tturn"], "keys": ["fam", "fam2", "tturn"]},
	"econ_bday_realm": {"day": 10, "kinds": ["econ", "bday", "fturn"], "keys": ["econ", "bday", "fturn"]}
}
const PHASES: Array = ["generation", "warmup", "advance_to_snapshot", "fork",
	"native_run", "synchronous_run", "split_run", "post_hold_save", "compare", "codec", "cleanup"]
const GUARDS: Array = ["full_depth_fixture", "native_warmup", "snapshot_day_and_headers",
	"fork_exact", "native_queue_complete", "synchronous_equivalence", "header_child_order",
	"ordered_full_state", "batch_cases_and_local_rng", "codec_round_trip",
	"post_hold_cleanup", "internal_deadline"]
const KEY_GUARDS: Array = ["native_header", "native_due_and_completed", "prepared_fresh_frame_admission", "root_entered",
	"inner_loop_suspended", "same_owner_progress_across_frames", "original_day_header_tail",
	"dispatch_reentry_blocked", "held_contract_boundary", "mid_hold_save_deferred",
	"mid_hold_load_refused", "redraw_and_actions_deferred", "fresh_post_hold_receipt"]
var diagnostic_only: bool = false
var harness_error: bool = false
var paths: Dictionary = {}
var key_paths: Dictionary = {}
var counters: Dictionary = {}
var details: Dictionary = {}
var phase_usec: Dictionary = {}
var phase_calls: Dictionary = {}
var _group: String = ""
var _spec: Dictionary = {}
var _phase_name: String = ""
var _phase_started: int = 0
var _started_usec: int = 0
var _forced_keys: Dictionary = {}
var _sync_rng: Array = []
var _split_rng: Array = []

## Scheduling instrumentation only: inherited bodies and RNG stay unchanged.
class HeldTurn:
	extends "res://campaign/campaign_turn_job.gd"
	var targets: Dictionary = {}
	var forced: Dictionary = {}

	func _init(job: Array) -> void:
		super(job)

	func _checkpoint(label: String) -> void:
		if budgeted and targets.has(label) and not forced.has(label) and int(visits.get(label, 0)) + 1 >= int(targets[label]):
			forced[label] = true
			_deadline_usec = 0
		await super._checkpoint(label)

class HeldSick:
	extends "res://campaign/sickness_day_job.gd"
	var visits: Dictionary = {}
	var yielded_labels: Dictionary = {}
	var targets: Dictionary = {}
	var forced: Dictionary = {}

	func _init(tid: String, day: int, part: int) -> void:
		super(tid, day, part)

	func _checkpoint(label: String) -> void:
		visits[label] = int(visits.get(label, 0)) + 1
		if budgeted and targets.has(label) and not forced.has(label) and int(visits[label]) >= int(targets[label]):
			forced[label] = true
			_deadline_usec = 0
		var before: int = yields
		await super._checkpoint(label)
		if yields > before:
			yielded_labels[label] = int(yielded_labels.get(label, 0)) + 1

func run_group(tree: SceneTree, group: String) -> int:
	_started_usec = Time.get_ticks_usec()
	_deadline = _started_usec + WALL_USEC
	_failure = ""
	_check_admission()
	if not _failure.is_empty():
		return 1
	_held = 0
	harness_error = false
	_group = group
	if tree == null or not GROUPS.has(group):
		harness_error = true
		_failure = "Missing SceneTree or unknown native frame-world group."
		return 1
	if Game._save_capture != null or Game._save_task != -1 or Game._save_pending:
		harness_error = true
		_failure = "Native frame-world test requires an idle isolated save writer."
		return 1
	_spec = GROUPS[group]
	paths.clear()
	key_paths.clear()
	counters = {"snapshot_day": int(_spec["day"]), "native_headers": {}, "split_headers": {},
		"due_headers": {}, "completed_headers": {}, "company_units": 0, "native_warbands": 0}
	details.clear()
	phase_usec.clear()
	phase_calls.clear()
	_forced_keys.clear()
	_sync_rng.clear()
	_split_rng.clear()
	for key: String in _spec["keys"]:
		key_paths[key] = {}
	var old_process: bool = Game.is_processing()
	var old_screen: String = String(Game._active_screen)
	var old_paused: bool = tree.paused
	var old_fps: int = Engine.max_fps
	var old_scale: float = Engine.time_scale
	var old_size: String = WorldGen.gen_size
	var old_span: int = CampaignWorld.presim_span_days
	var data: Dictionary = TownEcon.data()
	var old_families: Array = data["families_by_size"]
	var old_log: bool = Sickness.log_cases
	var old_prof: bool = Sickness.prof_on
	var old_parts: bool = Sickness.prof_parts
	var old_worst: Dictionary = CampaignWorld.job_worst.duplicate()
	var old_frame_worst: Dictionary = CampaignWorld.frame_job_worst.duplicate()
	Game.set_process(false)
	Game._active_screen = "map"
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	tree.paused = false
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Sickness.log_cases = true
	Sickness.prof_on = false
	Sickness.prof_parts = false
	_phase("generation")
	data["families_by_size"] = [150, 150, 150, 150, 150]
	var fixture: NativeFixture = NativeFixture.new()
	fixture.hard_deadline = _deadline
	fixture._started_us = _started_usec
	_fixture_ready = await fixture._setup_world(tree)
	_fixture_receipt = fixture._receipt.duplicate(true)
	data["families_by_size"] = old_families
	paths["full_depth_fixture"] = _fixture_ready
	if not _fixture_ready:
		_failure = fixture._reason
	if _ok():
		_phase("warmup")
		_warmup_ready = await fixture._warmup(tree)
		paths["native_warmup"] = _warmup_ready
		if not _warmup_ready:
			_failure = fixture._reason
	if _ok():
		_phase("advance_to_snapshot")
		for day: int in range(10, int(_spec["day"]) + 1):
			if not _ok(): break
			# Unmounted preparation follows r13's native warmup; retain the target queue.
			var work_budget_usec: int = 0 if day < int(_spec["day"]) else 1
			Game.advance_time(1.0, false, 0, work_budget_usec)
			if int(Game.world.get("last_day", -1)) != day or not is_equal_approx(Game.day, float(day)):
				_failure = "Native time advance missed exact day %d." % day
				break
			if day < int(_spec["day"]) and not await fixture.settle(tree):
				_failure = fixture._reason
				break
	if _ok():
		_cold_head()
		_observe_snapshot()
	if _ok():
		await _compare_world(tree)
	_phase("cleanup")
	# Cancel only this fixture's owner after a failed run; execute no later work.
	if Game._day_job_owner != null:
		var abandoned: CampaignDayJob = Game._day_job_owner
		abandoned.after.clear()
		abandoned.release(Game)
	# Teardown only: discard this isolated fixture after its verdict; never
	# let an abandoned continuation resume after the runner regains control.
	Game.world["work"] = []
	Game._save_pending = false
	Game._autosave_day_pending = false
	Game._day_job_owner = null
	Game._day_job_dispatching = false
	Game._day_job_actions.clear()
	Game._day_job_observers.clear()
	Game._day_job_changed_pending = false
	Game._day_job_slice_frame = -1
	Game._day_job_quit_generation = -1
	Game._day_job_budget_frame = -1
	Game._day_job_frame_started_usec = 0
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	CampaignWorld.job_worst = old_worst
	CampaignWorld.frame_job_worst = old_frame_worst
	Sickness.log_cases = old_log
	Sickness.prof_on = old_prof
	Sickness.prof_parts = old_parts
	Game._active_screen = old_screen
	Game.set_process(old_process)
	tree.paused = old_paused
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	paths["internal_deadline"] = _ok()
	if _failure.is_empty():
		for guard: String in GUARDS:
			if not bool(paths.get(guard, false)):
				_failure = "Required complete native-day guard missing: " + guard
				break
	_phase_end()
	var result: int = 0 if _failure.is_empty() else 1
	if not diagnostic_only:
		if result == 0:
			print("FRAME WORLD SPLIT EQUIV PASS %s: real day %d; full native queue, state, side state and strict holds exact." % [group, int(_spec["day"])])
		else:
			printerr("FRAME WORLD SPLIT EQUIV FAIL %s: %s" % [group, _failure])
	return result

func _phase(label: String) -> void:
	_phase_end()
	_phase_name = label
	_phase_started = Time.get_ticks_usec()

func _phase_end() -> void:
	if _phase_name.is_empty(): return
	phase_usec[_phase_name] = int(phase_usec.get(_phase_name, 0)) + Time.get_ticks_usec() - _phase_started
	phase_calls[_phase_name] = int(phase_calls.get(_phase_name, 0)) + 1
	_phase_name = ""

func _key(header: Array) -> String:
	return "sick/%d" % int(header[3]) if header[0] == "sick" else String(header[0])

func _plain(header: Array) -> Array:
	return header.slice(0, header.size() - 1) if header[-1] is CampaignDayJob else header.duplicate()

func _cold_head() -> void:
	# Drop only an unstarted, unowned runtime preparation, never a game header.
	# SaveSnapshot cannot encode a CampaignDayJob object. The native body is idle.
	if (Game.world.get("work", []) as Array).is_empty(): return
	var head: Array = Game.world["work"][0]
	if head[-1] is CampaignDayJob:
		var prepared: CampaignDayJob = head[-1]
		if Game._day_job_owner != null or prepared.holds_tree or bool(prepared.get("_started")):
			_failure = "Attempted to snapshot or run atomically across a started continuation."
			return
		head.pop_back()

func _side() -> Array:
	return [Game._serialize(TownEcon.batch), TownEcon.batch_open, TownEcon.batch_half,
		TownEcon.batch_barn, Loans.last_buyers_checked.duplicate(true), Sickness.case_log.duplicate(true)]

func _restore_world(snapshot: Dictionary, side: Array) -> void:
	# r11's deserializer consumes its input; preserve the shared fork snapshot.
	_restore(snapshot)   # inherited restore detaches once before native decoding
	TownEcon.batch = Game._deserialize((side[0] as Array).duplicate(true))
	TownEcon.batch_open = bool(side[1])
	TownEcon.batch_half = int(side[2])
	TownEcon.batch_barn = bool(side[3])
	Loans.last_buyers_checked = side[4].duplicate(true)
	Sickness.case_log = side[5].duplicate(true)
	Game._day_job_budget_frame = -1
	Game._day_job_frame_started_usec = 0

func _native_one() -> void:
	var stream: RandomNumberGenerator = CampaignWorld._rng(Game.world)
	CampaignWorld._run_job(Game, stream, false)
	Game.world["rng_state"] = str(stream.state)

func _observe_snapshot() -> void:
	counters["company_units"] = Game.company.size()
	counters["native_warbands"] = (Game.world.get("warbands", {}) as Dictionary).size()
	counters["cohort_cases"] = 0
	counters["registered_cases"] = 0
	for town: Dictionary in Game.world["towns"].values():
		var econ: Dictionary = town.get("econ", {})
		counters["registered_cases"] = int(counters["registered_cases"]) + (econ.get("sk", {}).get("cases", {}) as Dictionary).size()
		for family: Dictionary in econ.get("fams", []):
			counters["cohort_cases"] = int(counters["cohort_cases"]) + (family.get("psk", []) as Array).size()
	for header: Array in Game.world.get("work", []):
		if header[0] in _spec["kinds"]:
			var key: String = _key(header)
			var counts: Dictionary = counters["native_headers"]
			counts[key] = int(counts.get(key, 0)) + 1
	for key: String in _spec["keys"]:
		key_paths[key]["native_header"] = int(counters["native_headers"].get(key, 0)) > 0
		if not bool(key_paths[key]["native_header"]):
			_failure = "Selected real midnight lacks a required native header: " + key
	paths["snapshot_day_and_headers"] = _ok() and int(Game.world.get("last_day", -1)) == int(_spec["day"]) and Game.day == float(_spec["day"])

func _due(header: Array) -> bool:
	var kind: String = String(header[0])
	var day: int = int(_spec["day"])
	if kind == "fturn": return int(header[1]) == day and day % 7 == 3
	if kind == "sick_w": return int(header[1]) == day
	var town: Dictionary = Game.world["towns"].get(header[1], {})
	if not TownEcon.has_econ(town) or int(header[2]) != day: return false
	var econ: Dictionary = town["econ"]
	match kind:
		"econ": return int(econ.get("day", -1)) < day
		"bday": return int(econ.get("day", -1)) == day and int(econ.get("bday", -1)) < day
		"fam", "fam2":
			var families: Array = econ["fams"]
			for row: int in range(day % 7 + (7 if kind == "fam2" else 0), families.size(), 14):
				var family: Dictionary = families[row]
				if not family.get("gone", false) and not family.get("estate", false) and float(family.get("last", -1.0)) < float(day):
					return true
			return false
		"tturn":
			var ids: Array = Game.world["towns"].keys()
			ids.sort()
			return (day + ids.find(header[1])) % 7 == 0
		"sick":
			var book: Dictionary = econ.get("sk", {})
			return Sickness.town_due(String(header[1]), day) and (int(book.get("ld", -1)) < day if int(header[3]) == 1 else int(book.get("ld", -1)) == day)
	return false

func _completed(header: Array) -> bool:
	var kind: String = String(header[0])
	if kind in ["fturn", "sick_w", "tturn"]: return true
	var econ: Dictionary = Game.world["towns"][header[1]]["econ"]
	var day: int = int(_spec["day"])
	if kind in ["econ", "bday"]:
		return int(econ.get("day" if kind == "econ" else "bday", -1)) == day
	if kind == "sick": return int(econ.get("sk", {}).get("ld", -1)) == day
	var families: Array = econ["fams"]
	for row: int in range(day % 7 + (7 if kind == "fam2" else 0), families.size(), 14):
		var family: Dictionary = families[row]
		if not family.get("gone", false) and not family.get("estate", false) and float(family.get("last", -1.0)) == float(day):
			return true
	return false

func _new_worker(header: Array, directed: bool) -> CampaignDayJob:
	var kind: String = String(header[0])
	var loop_target: int = 2
	if kind in ["fam", "fam2"]:
		var families: Array = Game.world["towns"][header[1]]["econ"]["fams"]
		var iterations: int = range(int(header[2]) % 7 + (7 if kind == "fam2" else 0), families.size(), 14).size()
		loop_target = 1 if iterations == 1 else 2
	var targets: Dictionary = {_loop_label(header): loop_target, _contract_label(header): 1}
	# Coincident loop/contract labels retain visit 2 after first-iteration progress.
	# A singleton family half holds before its sole iteration; the distinct
	# post-loop contract still holds after genuine family progress.
	targets[_loop_label(header)] = loop_target
	if kind in ["sick", "sick_w"]:
		var disease: SicknessDayJob = HeldSick.new(String(header[1]) if kind == "sick" else "",
			int(header[2]) if kind == "sick" else int(header[1]), int(header[3]) if kind == "sick" else -1)
		if directed: (disease as HeldSick).targets = targets
		return disease
	if kind in ["econ", "bday"]:
		var rest: CampaignRestJob = CampaignRestJob.new(header)
		if directed: rest.test_force_labels = targets
		return rest
	var turn: HeldTurn = HeldTurn.new(header)
	if directed: turn.targets = targets
	return turn

func _loop_label(header: Array) -> String:
	match String(header[0]):
		"fam", "fam2": return "TownEcon.family_batch:loop:234"
		"tturn": return "Shelter.assign_child_cleanup:loop:424"
		"fturn": return "Academy.faction_turn:loop:726"
		"econ": return "Businesses.daily:loop:545"
		"bday": return "Barge.update_prices:loop:199"
		"sick_w": return "_world_day:loop"
		"sick": return "_pool_day:loop" if int(header[3]) == 1 else "_roll_town:loop"
	return ""

func _contract_label(header: Array) -> String:
	match String(header[0]):
		"fam", "fam2": return "TownEcon.family_batch:237"
		"econ": return "TownEcon._market_day:day_written"
		"bday": return "TownEcon.barge_day:bday_written"
	return _loop_label(header)

func _roots(header: Array) -> Array:
	match String(header[0]):
		"fam", "fam2": return ["TownEcon.family_batch"]
		"tturn": return ["TownEcon.town_turn", "Shelter.assign_child_cleanup"]
		"fturn": return ["TownEcon.faction_turn", "Academy.faction_turn"]
		"econ": return ["TownEcon.daily_pass", "Shelter.accrue_sanitation", "Businesses.daily", "Army.pay_town", "TownDefence.daily"]
		"bday": return ["TownEcon.barge_day", "Barge.update_prices", "Businesses.books_day", "Businesses.prep_day", "Barge.labour_day", "Businesses.bid_day", "Barge.coin_town"]
		"sick_w": return ["_world_day:enter", "_company_day:enter"]
		"sick": return ["town_day:enter", "_pool_day:enter" if int(header[3]) == 1 else "_roll_town:enter"]
	return []

func _drain_reference(synchronous: bool) -> Array:
	var trace: Array = []
	while _ok() and not (Game.world.get("work", []) as Array).is_empty():
		_cold_head()
		if not _ok(): break
		var header: Array = _plain(Game.world["work"][0])
		trace.append(header)
		var selected: bool = header[0] in _spec["kinds"]
		if selected and not _due(header):
			_failure = "Native selected header is not due at its real queue boundary: " + str(header)
			break
		if selected and not synchronous:
			var due: Dictionary = counters["due_headers"]
			due[_key(header)] = int(due.get(_key(header), 0)) + 1
		var worker: CampaignDayJob = null
		if selected and synchronous:
			worker = _new_worker(header, false)
			Game.world["work"][0].append(worker)
		_native_one()
		if worker != null and not worker.done:
			_failure = "Unbudgeted split implementation retained an unfinished header."
			break
		if selected and not _completed(header):
			_failure = "Native/synchronous header completed without its original day effect: " + str(header)
			break
		if worker is SicknessDayJob:
			_sync_rng.append([header, (worker as SicknessDayJob).rng_states.duplicate(true)])
	return trace

func _compare_world(tree: SceneTree) -> void:
	_phase("fork")
	var before: Dictionary = Game._save_tree()
	var side: Array = _side()
	var before_bytes: PackedByteArray = var_to_bytes(before)
	var side_bytes: PackedByteArray = var_to_bytes(side)
	_restore_world(before, side)
	if not _ok(): return
	if var_to_bytes(Game._save_tree()) != before_bytes or var_to_bytes(_side()) != side_bytes:
		_failure = "r11 native snapshot/side restore changed the original fork."
		return
	paths["fork_exact"] = true
	_phase("native_run")
	var native_trace: Array = _drain_reference(false)
	if not _ok(): return
	paths["native_queue_complete"] = Game.world.get("work", []).is_empty()
	_phase("compare")
	var expected: PackedByteArray = var_to_bytes(Game._save_tree())
	var expected_side: PackedByteArray = var_to_bytes(_side())
	_phase("fork")
	_restore_world(before, side)
	if not _ok(): return
	_phase("synchronous_run")
	var sync_trace: Array = _drain_reference(true)
	if not _ok(): return
	_phase("compare")
	if sync_trace != native_trace or var_to_bytes(Game._save_tree()) != expected or var_to_bytes(_side()) != expected_side:
		_failure = "Unbudgeted split queue differs from the full native day/side state/header order."
		return
	paths["synchronous_equivalence"] = true
	_phase("fork")
	_restore_world(before, side)
	if not _ok(): return
	_phase("split_run")
	var split_trace: Array = await _drain_split(tree)
	if not _ok(): return
	_phase("compare")
	if split_trace != native_trace:
		_failure = "Real original headers or generated children changed order/count."
		return
	paths["header_child_order"] = true
	if var_to_bytes(Game._save_tree()) != expected:
		_failure = "Complete ordered native save tree differs after retained continuation."
		return
	paths["ordered_full_state"] = true
	if var_to_bytes(_side()) != expected_side or _sync_rng != _split_rng:
		_failure = "Native batch/land diagnostics, ordered disease cases or split-local RNG streams differ."
		return
	paths["batch_cases_and_local_rng"] = true
	for key: String in _spec["keys"]:
		if int(counters["split_headers"].get(key, 0)) != int(counters["native_headers"].get(key, 0)):
			_failure = "Native/split selected header counts differ: " + key
			return
		for guard: String in KEY_GUARDS:
			if not bool(key_paths[key].get(guard, false)):
				_failure = "Required native path missing: %s/%s." % [key, guard]
				return
	if _group == "sickness" and not bool(paths.get("prepared_hold_before_admission", false)):
		_failure = "Prepared sickness head did not hold before exhausted-frame admission."
		return
	paths["post_hold_cleanup"] = not tree.paused and Game._day_job_owner == null and not Game._save_pending and Game._save_capture == null and Game._save_task == -1 and Game._day_job_actions.is_empty() and Game._day_job_observers.is_empty()
	if not bool(paths["post_hold_cleanup"]):
		_failure = "Completed real day left a hold, save writer or observer backlog before codec restore."
		return
	_phase("codec")
	var parsed: Variant = JSON.parse_string(Game.save_text(Game._save_tree()))
	if not parsed is Dictionary:
		_failure = "Completed production save codec returned no dictionary."
		return
	Game.restore_exact(parsed)
	var completed_side: Array = _side()
	_restore_world(parsed, completed_side)
	if not _ok(): return
	if var_to_bytes(Game._save_tree()) != expected or var_to_bytes(_side()) != expected_side:
		_failure = "Production exact codec round trip changed completed state/side diagnostics."
		return
	paths["codec_round_trip"] = true
	paths["post_hold_cleanup"] = not tree.paused and Game._day_job_owner == null and not Game._save_pending and Game._save_capture == null and Game._save_task == -1 and Game._day_job_actions.is_empty() and Game._day_job_observers.is_empty()
	if not bool(paths["post_hold_cleanup"]):
		_failure = "Completed real day left a hold, save writer or observer backlog."

func _drain_split(tree: SceneTree) -> Array:
	var trace: Array = []
	while _ok() and not (Game.world.get("work", []) as Array).is_empty():
		_cold_head()
		if not _ok(): break
		var header: Array = _plain(Game.world["work"][0])
		trace.append(header)
		if header[0] not in _spec["kinds"]:
			_native_one()
			continue
		if not _due(header):
			_failure = "Split header is not natively due at its real queue boundary: " + str(header)
			break
		var key: String = _key(header)
		var directed: bool = not _forced_keys.has(key)
		_forced_keys[key] = true
		CampaignWorld.performance_queue(Game)
		var head: Array = Game.world["work"][0]
		if not head[-1] is CampaignDayJob:
			_failure = "Production head preparation did not produce a continuation."
			break
		if directed:
			head.pop_back()
			head.append(_new_worker(header, true))
		var worker: CampaignDayJob = head[-1]
		# Per-header observation fences retain the exact native trace.
		worker.after.append(_queue_boundary)
		if directed:
			# Retain the old historical-cost/fresh-frame admission negative controls.
			# These diagnostics affect scheduling only; no campaign value changes.
			var kind: String = String(header[0])
			var old_atomic_cost: int = int(CampaignWorld.job_worst.get(kind, 0))
			var old_slice_cost: int = int(CampaignWorld.frame_job_worst.get(kind, 0))
			var had_atomic_cost: bool = CampaignWorld.job_worst.has(kind)
			var had_slice_cost: bool = CampaignWorld.frame_job_worst.has(kind)
			CampaignWorld.job_worst[kind] = CampaignWorld.WORK_FRAME_LIMIT_USEC + 1
			CampaignWorld.frame_job_worst[kind] = CampaignWorld.WORK_FRAME_LIMIT_USEC + 1
			var admitted: bool = CampaignWorld.job_admitted(head, 16000, 4000, false) and CampaignWorld.job_admitted(head, 16000, 4000, true) and not CampaignWorld.job_admitted(head, 3999, 4000, false)
			if had_atomic_cost: CampaignWorld.job_worst[kind] = old_atomic_cost
			else: CampaignWorld.job_worst.erase(kind)
			if had_slice_cost: CampaignWorld.frame_job_worst[kind] = old_slice_cost
			else: CampaignWorld.frame_job_worst.erase(kind)
			key_paths[key]["prepared_fresh_frame_admission"] = admitted
			if not admitted:
				_failure = "Native continuation failed historical-cost/reservation/prefix admission guards: " + key
				break
		var tail_size: int = (Game.world["work"] as Array).size() - 1
		var tail: PackedByteArray = var_to_bytes(Game._serialize((Game.world["work"] as Array).slice(1)))
		var original_day: float = Game.day
		var campaign_rng: String = str(Game.world.get("rng_state", ""))
		var game_rng: int = Game.rng.state
		var previous_frame: int = -1
		var previous_yields: int = -1
		var progressed: bool = false
		var observed: bool = false
		var probe: Variant = CONTRACT_PROBE.new()
		_actions.clear()
		var receipt_before: int = Game._save_last_receipt_generation
		while _ok() and not worker.done:
			await tree.process_frame
			if directed and _group == "sickness" and not bool(paths.get("prepared_hold_before_admission", false)):
				# Keep the existing exhausted-frame prepared-head negative control.
				Game._day_job_begin_frame(Time.get_ticks_usec())
				Game._day_job_frame_started_usec = Time.get_ticks_usec() - CampaignWorld.WORK_FRAME_LIMIT_USEC + CampaignDayJob.NATIVE_RESERVE_USEC - 1
				CampaignWorld.work_slice(Game, 1)
				if Game._day_job_owner != worker or not tree.paused or not worker.holds_tree or bool(worker.get("_started")):
					_failure = "Prepared sickness failed to hold before exhausted-frame admission."
					break
				paths["prepared_hold_before_admission"] = true
			else:
				Game._process(1.0 / 60.0)
			var yields_now: int = int(worker.get("yields"))
			if previous_frame >= 0 and Engine.get_process_frames() > previous_frame and (worker.done or yields_now > previous_yields):
				progressed = true
			# _check_admission exercised true call-stack reentry and same-frame
			# sequential resumption through the production dispatcher.
			if directed: key_paths[key]["dispatch_reentry_blocked"] = true
			if Game.day != original_day or int(Game.world.get("last_day", -1)) != int(original_day):
				_failure = "Retained native job crossed its original effect day."
				break
			if header[0] in ["sick", "sick_w"]:
				if str(Game.world.get("rng_state", "")) != campaign_rng or Game.rng.state != game_rng:
					_failure = "Retained sickness changed the campaign/global RNG fence."
					break
				key_paths[key]["clock_rng_fence"] = true
			if worker.done: break
			_held += 1
			var work: Array = Game.world["work"]
			if not tree.paused or not worker.holds_tree or worker.was_paused or Game._day_job_owner != worker or work.is_empty() or work[0][-1] != worker or _plain(work[0]) != header:
				_failure = "Retained job lost its original owner/head/tree hold."
				break
			# Native children may append after the original tail; preserve its
			# complete prefix and certify every child in the final native trace.
			if work.size() < tail_size + 1 or var_to_bytes(Game._serialize(work.slice(1, tail_size + 1))) != tail:
				_failure = "Retained job consumed/reordered the original native queue tail."
				break
			if directed: key_paths[key]["original_day_header_tail"] = true
			if observed and not _actions.is_empty():
				_failure = "Deferred actions ran while their native owner was still held."
				break
			if yields_now > 0:
				previous_frame = Engine.get_process_frames()
				previous_yields = yields_now
			if not directed or observed or String(worker.get("boundary")) != _contract_label(header) or yields_now <= 0:
				continue
			observed = true
			key_paths[key]["held_contract_boundary"] = true
			if header[0] in ["econ", "bday"]:
				var econ: Dictionary = Game.world["towns"][header[1]]["econ"]
				if int(econ.get("day" if header[0] == "econ" else "bday", -1)) != int(_spec["day"]):
					_failure = "Required partial-state day marker was not written before its hold."
					break
			var started: int = int(Game.save_stats()["started"])
			var generation: int = Game._save_generation
			var accepted: int = Game._save_last_receipt_generation
			var epoch: int = Game._save_epoch
			CampaignWorld.defer_day_job_action(Game, _record.bind("first"))
			CampaignWorld.defer_day_job_action(Game, _record.bind("second"))
			Game.save_game_async()
			if Game.save_game():
				_failure = "Mid-hold synchronous save reported a completed write."
				break
			Game.wait_save(true)
			if Game.load_game() or Game._save_epoch != epoch:
				_failure = "Mid-hold production load escaped its barrier."
				break
			if int(Game.save_stats()["started"]) != started or Game._save_generation != generation or Game._save_last_receipt_generation != accepted or Game._save_capture != null or Game._save_task != -1 or not Game._save_pending:
				_failure = "Mid-hold save captured partial state, accepted an old receipt, or lost its request."
				break
			key_paths[key]["mid_hold_save_deferred"] = true
			key_paths[key]["mid_hold_load_refused"] = true
			var problem: String = await probe.observe_hold(tree, _deadline)
			if problem != "" or not _actions.is_empty():
				_failure = problem if problem != "" else "Deferred actions observed partial native state."
				break
			key_paths[key]["redraw_and_actions_deferred"] = true
		if not _ok():
			probe.dispose()
			break
		_cold_head()
		if not _ok():
			probe.dispose()
			break
		if tree.paused or Game._day_job_owner != null or not worker.done:
			_failure = "Completed continuation failed to release its original hold."
			probe.dispose()
			break
		if not _completed(header):
			_failure = "Continued header completed without its original day effect: " + str(header)
			probe.dispose()
			break
		var split_counts: Dictionary = counters["split_headers"]
		split_counts[key] = int(split_counts.get(key, 0)) + 1
		var completed_counts: Dictionary = counters["completed_headers"]
		completed_counts[key] = int(completed_counts.get(key, 0)) + 1
		key_paths[key]["native_due_and_completed"] = int(counters["due_headers"].get(key, 0)) > 0
		if worker is SicknessDayJob:
			_split_rng.append([header, (worker as SicknessDayJob).rng_states.duplicate(true)])
		if directed:
			key_paths[key]["same_owner_progress_across_frames"] = progressed
			_certify_worker(header, worker)
			if not observed and _failure.is_empty():
				_failure = "Native representative missed its exact save/load/redraw hold: " + key
			if _ok():
				_phase("post_hold_save")
				var mode: String = "sync_save" if header[0] in ["econ", "tturn"] else ("async" if header[0] in ["bday", "fturn"] else "sync_wait")
				var problem: String = await probe.finish(tree, _deadline, mode)
				if problem != "" or _actions != ["first", "second"]:
					_failure = problem if problem != "" else "Committed actions did not replay exactly once in order."
				else:
					key_paths[key]["fresh_post_hold_receipt"] = Game._save_last_receipt_generation > receipt_before and not Game._save_pending and Game._save_capture == null and Game._save_task == -1
				_phase("split_run")
				_cold_head()
		probe.dispose()
	return trace

func _certify_worker(header: Array, worker: CampaignDayJob) -> void:
	var key: String = _key(header)
	var visits: Dictionary = worker.get("visits")
	var yielded: Dictionary = worker.get("yielded_labels")
	var roots_hit: bool = true
	for root: String in _roots(header):
		roots_hit = roots_hit and int(visits.get(root, 0)) > 0
	key_paths[key]["root_entered"] = roots_hit
	key_paths[key]["inner_loop_suspended"] = int(yielded.get(_loop_label(header), 0)) > 0
	var forced: Dictionary = (worker as CampaignRestJob).test_forced_labels if worker is CampaignRestJob else worker.get("forced")
	var force_hit: bool = forced.has(_loop_label(header)) and forced.has(_contract_label(header))
	key_paths[key]["forced_boundaries_reached"] = force_hit
	details[key] = {"header": header, "yields": int(worker.get("yields")), "visits": visits.duplicate(),
		"yielded_labels": yielded.duplicate(), "forced": forced.duplicate(),
		"required_loop": _loop_label(header), "required_contract": _contract_label(header)}
	if not force_hit or not roots_hit:
		_failure = "Native representative missed a required inherited root or scheduling boundary: " + key
