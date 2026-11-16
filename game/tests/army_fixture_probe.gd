extends RefCounted
## Diagnostic only: the inherited day-10 strict run and original economic/hold guards.
## Exit zero means the probe ran; require strict_result=0 and every HIT.
const PHASES: Array = ["generation", "warmup", "preparation", "fork", "atomic_run",
	"split_run", "post_hold_save", "compare", "codec_restore", "cleanup"]
const PATHS: Array = ["admission_fresh_slice", "admission_affordable_prefix",
	"admission_reservation", "full_depth_fixture", "initial_queue_drained",
	"payable_funded_bound_camp", "three_town_supply_fixture", "native_supply_moved",
	"atomic_camp_debit_home_credit", "continued_camp_debit_home_credit",
	"post_payment_payroll_held_and_resumed", "mid_hold_save_deferred",
	"post_hold_new_successful_receipt", "internal_deadline_met"]
const COMPARE_PATHS: Array = ["fork_snapshot_exact", "native_atomic_queue",
	"budgeted_fifo_and_dispatch_reentry", "original_effect_day", "completed_tree_release", "original_header_child_order",
	"ordered_native_snapshot", "codec_decoded", "codec_round_trip"]
const HOLD_PATHS: Array = ["retained_tree_hold", "queue_tail_unchanged",
	"partial_observers_deferred", "committed_redraw_contract", "deferred_action_order"]
const COMPARISONS: int = 1

class Fixture:
	extends "res://tests/test_army_split_equiv.gd"
	var paths: Dictionary = {}
	var phase_usec: Dictionary = {}
	var phase_calls: Dictionary = {}
	var details: Array = []
	var started_comparisons: int = 0
	var completed_comparisons: int = 0
	var completed_held_comparisons: int = 0
	var phase: String = ""
	var phase_started: int = 0
	var in_compare: bool = false
	var restore_calls: int = 0
	var has_supply: bool = false
	var receipt_before: int = -1

	func phase_begin(label: String) -> void:
		phase_end()
		phase = label
		phase_started = Time.get_ticks_usec()

	func phase_end() -> void:
		if phase.is_empty():
			return
		phase_usec[phase] = int(phase_usec.get(phase, 0)) + Time.get_ticks_usec() - phase_started
		phase_calls[phase] = int(phase_calls.get(phase, 0)) + 1
		phase = ""

	func _phase(label: String) -> void:
		phase_begin(label)

	func _check_admission() -> void:
		super._check_admission()
		paths["admission_fresh_slice"] = _failure.is_empty()
		paths["admission_affordable_prefix"] = _failure.is_empty()
		paths["admission_reservation"] = _failure.is_empty()

	func _drain_atomic() -> Array:
		if not in_compare:
			paths["full_depth_fixture"] = _failure.is_empty()
			phase_begin("preparation")
		else:
			has_supply = (Game.world["work"] as Array).any(func(job: Array) -> bool: return job[0] == "arms_supply")
			phase_begin("atomic_run")
		var trace: Array = super._drain_atomic()
		if not in_compare:
			paths["initial_queue_drained"] = _failure.is_empty() and Game.world.get("work", []).is_empty()
			phase_begin("preparation")
		else:
			phase_begin("fork")
		return trace

	func _prime_camp() -> void:
		phase_begin("preparation")
		super._prime_camp()
		paths["payable_funded_bound_camp"] = _failure.is_empty() and _camp_id != ""
		if in_compare: phase_begin("atomic_run")

	func _prime_supply() -> void:
		phase_begin("preparation")
		super._prime_supply()
		paths["three_town_supply_fixture"] = _failure.is_empty() and int(_native_counters.get("same_faction_towns", 0)) >= 3

	func _compare_day(tree: SceneTree) -> void:
		in_compare = true
		restore_calls = 0
		has_supply = false
		started_comparisons += 1
		var held_before: int = _held
		receipt_before = Game._save_last_receipt_generation
		phase_begin("fork")
		await super._compare_day(tree)
		if _failure.is_empty():
			completed_comparisons += 1
			if _held > held_before and _actions == ["first", "second"]:
				completed_held_comparisons += 1
			if Game._save_last_receipt_generation > receipt_before:
				paths["post_hold_new_successful_receipt"] = true
		details.append({"comparison": started_comparisons, "held_frames": _held - held_before,
			"complete": _failure.is_empty(), "stop_reason": "none" if _failure.is_empty() else _failure})
		in_compare = false
		phase_begin("cleanup" if not _failure.is_empty() or started_comparisons == COMPARISONS else "preparation")

	func _restore(d: Dictionary) -> void:
		if in_compare:
			restore_calls += 1
			if restore_calls == 2 and has_supply and _failure.is_empty() and int(_native_counters.get("supply_moved", 0)) > 0 and int(_native_counters.get("supply_towns_moved", 0)) >= 3:
				# Entry is after the unchanged native supply_moved guard.
				paths["native_supply_moved"] = true
		phase_begin("codec_restore" if restore_calls == 3 else "fork")
		super._restore(d)
		if in_compare and restore_calls == 2:
			phase_begin("split_run")
		elif in_compare and restore_calls == 3:
			phase_begin("compare")

	func _record(value: String) -> void:
		if in_compare and value == "first":
			phase_begin("post_hold_save")
		super._record(value)

	func _ok() -> bool:
		var valid: bool = super._ok()
		if not valid:
			if phase != "cleanup":
				phase_begin("cleanup")
			return valid
		if in_compare and restore_calls == 2:
			# The next original loop check follows all mid-hold save guards.
			if _save_checked:
				paths["mid_hold_save_deferred"] = true
			if Game.world.get("work", []).is_empty():
				if phase != "compare":
					phase_begin("compare")
			elif phase == "post_hold_save":
				phase_begin("split_run")
		return valid

func run(tree: SceneTree) -> int:
	if tree == null:
		printerr("ARMY FIXTURE PROBE HARNESS ERROR: no SceneTree.")
		return 1
	if Game._save_capture != null or Game._save_task != -1 or Game._save_pending:
		printerr("ARMY FIXTURE PROBE HARNESS ERROR: isolated fixture requires no in-flight save.")
		return 1
	var fixture: Variant = Fixture.new()
	var started_usec: int = Time.get_ticks_usec()
	fixture.phase_begin("generation")
	var strict_result: Variant = await fixture.run(tree)
	fixture.phase_end()
	var total_usec: int = Time.get_ticks_usec() - started_usec
	if not (strict_result is int) or int(strict_result) not in [0, 1]:
		printerr("ARMY FIXTURE PROBE HARNESS ERROR: invalid strict result.")
		return 1
	if int(strict_result) != 0 and String(fixture._failure).is_empty():
		printerr("ARMY FIXTURE PROBE HARNESS ERROR: strict failure has no stop reason.")
		return 1
	fixture.paths["full_depth_fixture"] = fixture._fixture_ready
	fixture.paths["initial_queue_drained"] = fixture._warmup_ready
	fixture.paths["atomic_camp_debit_home_credit"] = fixture._camp_atomic_paid
	fixture.paths["continued_camp_debit_home_credit"] = fixture._camp_continued_paid
	fixture.paths["post_payment_payroll_held_and_resumed"] = fixture._camp_payroll_held
	fixture.paths["internal_deadline_met"] = total_usec < int(fixture.WALL_USEC)
	var counters: String = JSON.stringify(fixture._native_counters)
	print("ARMY FIXTURE PROBE: native_counters=" + counters)
	print("ARMY FIXTURE PROBE: full_depth_receipt=" + JSON.stringify(fixture._fixture_receipt))
	var complete: bool = int(strict_result) == 0
	for name: String in PATHS:
		var hit: bool = bool(fixture.paths.get(name, false))
		complete = complete and hit
		print("ARMY FIXTURE PROBE: %s=%s%s" % [name, "HIT" if hit else "MISS", "" if hit else " native_counters=" + counters])
	for kind: String in fixture.KINDS:
		var covered: bool = fixture._coverage.has(kind)
		var held: bool = fixture._held_by_kind.has(kind)
		complete = complete and covered and held
		print("ARMY FIXTURE PROBE: kind=%s native_header=%s progressed_same_owner_across_frames=%s%s" % [kind, "HIT" if covered else "MISS", "HIT" if held else "MISS", "" if covered and held else " native_counters=" + counters])
	for name: String in COMPARE_PATHS:
		# A complete enclosing comparison certifies every original guard.
		# A MISS means not certified for the complete day-10 queue, even after an earlier HIT.
		var hit: bool = int(fixture.completed_comparisons) == COMPARISONS
		complete = complete and hit
		print("ARMY FIXTURE PROBE: %s=%s comparisons=%d/%d%s" % [name, "HIT" if hit else "MISS", int(fixture.completed_comparisons), COMPARISONS, "" if hit else " native_counters=" + counters])
	for name: String in HOLD_PATHS:
		var hit: bool = int(fixture.completed_held_comparisons) > 0
		complete = complete and hit
		print("ARMY FIXTURE PROBE: %s=%s completed_held_comparisons=%d%s" % [name, "HIT" if hit else "MISS", int(fixture.completed_held_comparisons), "" if hit else " native_counters=" + counters])
	print("ARMY FIXTURE PROBE: comparison_details=" + JSON.stringify(fixture.details))
	for phase: String in PHASES:
		print("ARMY FIXTURE PROBE TIMING: phase=%s total_ms=%.3f calls=%d" % [phase, float(fixture.phase_usec.get(phase, 0)) / 1000.0, int(fixture.phase_calls.get(phase, 0))])
	print("ARMY FIXTURE PROBE TIMING: harness_total_ms=%.3f deadline_ms=50000 import_ms=external" % (float(total_usec) / 1000.0))
	print("ARMY FIXTURE PROBE: strict_equivalence_result=%d" % int(strict_result))
	print("ARMY FIXTURE PROBE: stopped_reason=%s" % ["none" if String(fixture._failure).is_empty() else String(fixture._failure)])
	print("ARMY FIXTURE PROBE: all_guarded_paths=%s; diagnostic exit=0" % ["HIT" if complete else "MISS"])
	return 0
