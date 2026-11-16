extends RefCounted
## Diagnostic only: calls the inherited native-day-10/11 strict run and frozen oracle.
## A guard/deadline MISS returns zero; harness/script errors remain failures.
const PHASES: Array = ["generation", "warmup", "preparation", "fork", "atomic_run",
	"split_run", "post_hold_save_and_compare", "codec_round_trip", "cleanup"]
const PATHS: Array = ["full_depth_fixture", "initial_queue_drained",
	"mid_hold_save_deferred", "post_hold_new_successful_receipt",
	"two_days_each_schedule_week", "retained_continuation", "production_codec",
	"internal_deadline_met"]
const COMPARE_PATHS: Array = ["reference_raid_restore", "original_clock_day_campaign_rng",
	"ordered_world_exact", "global_rng_counters_uid_raids_exact", "native_save_exact"]
const HOLD_PATHS: Array = ["retained_tree_hold_original_day", "queue_tail_unchanged",
	"partial_observers_deferred", "committed_redraw_contract", "tree_release_action_order"]

class Fixture:
	extends "res://tests/test_herds_equiv.gd"
	var paths: Dictionary = {}
	var phase_usec: Dictionary = {}
	var phase_calls: Dictionary = {}
	var attempted_weeks: int = 0
	var completed_weeks: int = 0
	var completed_held_weeks: int = 0
	var phase: String = ""
	var phase_started: int = 0
	var in_compare: bool = false
	var atomic_returned: bool = false

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

	func _drain_atomic() -> void:
		paths["full_depth_fixture"] = _failure.is_empty()
		phase_begin("preparation")
		super._drain_atomic()
		paths["initial_queue_drained"] = _failure.is_empty() and Game.world.get("work", []).is_empty()

	func _compare_week(tree: SceneTree) -> void:
		in_compare = true
		atomic_returned = false
		attempted_weeks += 1
		var weeks_before: int = _weeks
		var held_before: int = _held
		var committed_before: int = _committed_holds
		var receipt_before: int = Game._save_last_receipt_generation
		phase_begin("fork")
		await super._compare_week(tree)
		if _failure.is_empty() and _weeks == weeks_before + 1:
			completed_weeks += 1
			if _held > held_before and _committed_holds > committed_before:
				completed_held_weeks += 1
			if Game._save_last_receipt_generation > receipt_before:
				paths["post_hold_new_successful_receipt"] = true
		in_compare = false
		phase_begin("preparation" if _failure.is_empty() else "cleanup")

	func _atomic_week(game: Variant, town: Dictionary, day_v: float) -> void:
		atomic_returned = false
		phase_begin("atomic_run")
		super._atomic_week(game, town, day_v)
		atomic_returned = true
		phase_begin("fork")

	func _record(label: String) -> void:
		if in_compare and label == "first":
			phase_begin("post_hold_save_and_compare")
		super._record(label)

	func _round_trip() -> void:
		# Entry follows the original per-day scheduling and final hold/week guards.
		paths["two_days_each_schedule_week"] = _failure.is_empty()
		paths["retained_continuation"] = _held > 0
		phase_begin("codec_round_trip")
		super._round_trip()
		paths["production_codec"] = _failure.is_empty()
		phase_begin("cleanup")

	func _ok() -> bool:
		var valid: bool = super._ok()
		if not valid:
			if phase != "cleanup":
				phase_begin("cleanup")
			return valid
		if in_compare and atomic_returned:
			if phase == "fork":
				phase_begin("split_run")
			# Called again only after the unchanged mid-hold guards complete.
			if _save_checked:
				paths["mid_hold_save_deferred"] = true
		return valid

func run(tree: SceneTree) -> int:
	if tree == null:
		printerr("HERDS FIXTURE PROBE HARNESS ERROR: no SceneTree.")
		return 1
	if Game._save_capture != null or Game._save_task != -1 or Game._save_pending:
		printerr("HERDS FIXTURE PROBE HARNESS ERROR: isolated fixture requires no in-flight save.")
		return 1
	var fixture: Variant = Fixture.new()
	var started_usec: int = Time.get_ticks_usec()
	fixture.phase_begin("generation")
	var strict_result: Variant = await fixture.run(tree)
	fixture.phase_end()
	var total_usec: int = Time.get_ticks_usec() - started_usec
	if not (strict_result is int) or int(strict_result) not in [0, 1]:
		printerr("HERDS FIXTURE PROBE HARNESS ERROR: invalid strict result.")
		return 1
	if int(strict_result) != 0 and String(fixture._failure).is_empty():
		printerr("HERDS FIXTURE PROBE HARNESS ERROR: strict failure has no stop reason.")
		return 1
	fixture.paths["full_depth_fixture"] = fixture._fixture_ready
	fixture.paths["initial_queue_drained"] = fixture._warmup_ready
	fixture.paths["internal_deadline_met"] = total_usec < int(fixture.WALL_USEC)
	var counters: String = JSON.stringify(fixture._native_counters)
	print("HERDS FIXTURE PROBE: native_counters=" + counters)
	print("HERDS FIXTURE PROBE: full_depth_receipt=" + JSON.stringify(fixture._fixture_receipt))
	var complete: bool = int(strict_result) == 0
	for name: String in PATHS:
		var hit: bool = bool(fixture.paths.get(name, false))
		complete = complete and hit
		print("HERDS FIXTURE PROBE: %s=%s%s" % [name, "HIT" if hit else "MISS", "" if hit else " native_counters=" + counters])
	for name: String in COMPARE_PATHS:
		# Conservatively certify these original guards only for completed weeks.
		var hit: bool = int(fixture.attempted_weeks) > 0 and int(fixture.completed_weeks) == int(fixture.attempted_weeks)
		complete = complete and hit
		print("HERDS FIXTURE PROBE: %s=%s weeks=%d/%d%s" % [name, "HIT" if hit else "MISS", int(fixture.completed_weeks), int(fixture.attempted_weeks), "" if hit else " native_counters=" + counters])
	for name: String in HOLD_PATHS:
		var hit: bool = int(fixture.completed_held_weeks) > 0
		complete = complete and hit
		print("HERDS FIXTURE PROBE: %s=%s completed_held_weeks=%d%s" % [name, "HIT" if hit else "MISS", int(fixture.completed_held_weeks), "" if hit else " native_counters=" + counters])
	print("HERDS FIXTURE PROBE: slices=%d retained_frames=%d" % [int(fixture._slices), int(fixture._held)])
	for phase: String in PHASES:
		print("HERDS FIXTURE PROBE TIMING: phase=%s total_ms=%.3f calls=%d" % [phase, float(fixture.phase_usec.get(phase, 0)) / 1000.0, int(fixture.phase_calls.get(phase, 0))])
	print("HERDS FIXTURE PROBE TIMING: harness_total_ms=%.3f deadline_ms=50000 import_ms=external" % (float(total_usec) / 1000.0))
	print("HERDS FIXTURE PROBE: strict_equivalence_result=%d" % int(strict_result))
	print("HERDS FIXTURE PROBE: stopped_reason=%s" % ["none" if String(fixture._failure).is_empty() else String(fixture._failure)])
	print("HERDS FIXTURE PROBE: all_guarded_paths=%s; diagnostic exit=0" % ["HIT" if complete else "MISS"])
	return 0
