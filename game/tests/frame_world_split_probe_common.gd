extends "res://tests/frame_world_split_equiv_common.gd"
## Honest diagnostic: the identical strict group; exit zero means receipts printed.
func probe_group(tree: SceneTree, group: String) -> int:
	diagnostic_only = true
	var strict_result: Variant = await run_group(tree, group)
	var tag: String = group.to_upper() + " FRAME WORLD PROBE"
	if harness_error or not (strict_result is int) or int(strict_result) not in [0, 1] or (int(strict_result) != 0 and _failure.is_empty()):
		printerr("%s HARNESS ERROR: %s" % [tag, _failure])
		return 1
	var complete: bool = int(strict_result) == 0
	var native_counts: String = JSON.stringify(counters)
	print("%s: snapshot_day=%d jobs=%s" % [tag, int(_spec["day"]), JSON.stringify(_spec["kinds"])])
	print("%s: native_counters=%s" % [tag, native_counts])
	print("%s: full_depth_receipt=%s" % [tag, JSON.stringify(_fixture_receipt)])
	for guard: String in GUARDS:
		var hit: bool = bool(paths.get(guard, false))
		complete = complete and hit
		print("%s: %s=%s%s" % [tag, guard, "HIT" if hit else "MISS", "" if hit else " native_counters=" + native_counts])
	if group == "sickness":
		var hit: bool = bool(paths.get("prepared_hold_before_admission", false))
		complete = complete and hit
		print("%s: prepared_hold_before_admission=%s" % [tag, "HIT" if hit else "MISS"])
	for key: String in _spec["keys"]:
		var names: Array = KEY_GUARDS.duplicate()
		names.append("forced_boundaries_reached")
		if group == "sickness": names.append("clock_rng_fence")
		for guard: String in names:
			var hit: bool = bool(key_paths[key].get(guard, false))
			complete = complete and hit
			print("%s: header=%s %s=%s%s" % [tag, key, guard, "HIT" if hit else "MISS", "" if hit else " native_counters=" + native_counts])
		print("%s: header=%s detail=%s" % [tag, key, JSON.stringify(details.get(key, {"stop_reason": "not reached"}))])
	# Availability receipts are deliberately separate from required loop guards.
	# No company, infections, recruits, forge work or militia wages are injected.
	for optional: String in ["TownDefence.daily:loop:147", "Persons.work", "Businesses._arms:loop:1312", "Army.pay_units:loop:638", "_company_day:loop"]:
		var visits: int = 0
		for receipt: Dictionary in details.values():
			visits += int(receipt.get("visits", {}).get(optional, 0))
		print("%s OPTIONAL PATH: %s=%s visits=%d" % [tag, optional, "HIT" if visits > 0 else "MISS", visits])
	for phase: String in PHASES:
		print("%s TIMING: phase=%s total_ms=%.3f calls=%d" % [tag, phase,
			float(phase_usec.get(phase, 0)) / 1000.0, int(phase_calls.get(phase, 0))])
	print("%s TIMING: harness_total_ms=%.3f deadline_ms=50000 import_ms=external" % [tag, float(Time.get_ticks_usec() - _started_usec) / 1000.0])
	print("%s: strict_equivalence_result=%d" % [tag, int(strict_result)])
	print("%s: stopped_reason=%s" % [tag, "none" if _failure.is_empty() else _failure])
	print("%s: all_guarded_paths=%s; diagnostic exit=0" % [tag, "HIT" if complete else "MISS"])
	return 0
