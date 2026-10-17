extends "res://tests/diag_release_perf.gd"
## Fresh-process paired startup measurement. No player screens, map transition or autosave.
## STARTUP_MODE=atomic|sliced; STARTUP_DAYS=30; STARTUP_SIZE=normal; STARTUP_SEED=777.
## STARTUP_OUTPUT is required. STARTUP_COMPARE_DIR optionally checks a prior atomic run.
## STARTUP_BUDGET_USEC=12000 (0 requests one atomic part); STARTUP_FRAMES=1 yields after each slice for frame gaps.
## STARTUP_FIXED_RAIDS=1 is an exact-work diagnostic only; ordinary speed uses 0.
## STARTUP_TIMEOUT_SEC=300 bounds the loop; the external runner must also have a timeout.
## STARTUP_MAX_SLICE_MS / STARTUP_MAX_FRAME_MS optionally set explicit measured gates.
## Snapshots and dated-ownership audits happen only at completed-day boundaries and
## are excluded from simulation CPU/frame-gap timing. Frame gaps include frame pacing.

func _setting(name: String, fallback: String) -> String:
	var value := OS.get_environment(name)
	return fallback if value.is_empty() else value

func _job_counts() -> Dictionary:
	var counts := {}
	for kind in CampaignWorld.job_total:
		counts[kind] = int(CampaignWorld.job_total[kind][1])
	return counts

func _slice(pending: Dictionary, budget: int) -> int:
	# Dynamic dispatch lets this same atomic diagnostic compile on the untouched
	# release, where presim_slice does not exist yet.
	var world_script = load("res://campaign/world.gd")
	return int(world_script.call("presim_slice", Game, pending, budget))

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[clampi(int(ceil(sorted.size() * fraction)) - 1, 0, sorted.size() - 1)]) / 1000.0

func _whole_count(value) -> bool:
	if not (value is int or value is float): return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number == floor(number)

func _compare_counts(previous, current: Dictionary, label: String) -> void:
	check(previous is Dictionary, label + ": reference is a count dictionary")
	if not previous is Dictionary: return
	check(previous.size() == current.size(), label + ": exact key count")
	for kind in current:
		check(previous.has(kind), label + ": matching job key " + str(kind))
		if not previous.has(kind): continue
		var old_value = previous[kind]
		var new_value = current[kind]
		check(_whole_count(old_value) and _whole_count(new_value), label + ": finite nonnegative whole count " + str(kind))
		if not (_whole_count(old_value) and _whole_count(new_value)): continue
		# JSON numbers are floats. Compare validated whole values without truncating
		# fractional data or using type-sensitive Dictionary equality.
		check(float(old_value) == float(new_value), label + ": identical count " + str(kind))

func _compare(report: Dictionary, directory: String) -> void:
	if directory.is_empty(): return
	var reference = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("startup-timings.json")))
	check(reference is Dictionary, "paired reference report exists and parses")
	if not reference is Dictionary: return
	for key in ["seed", "size", "requested_days", "fixed_raids"]:
		check(reference.get(key) == report[key], "paired configuration agrees: " + key)
	check(reference.get("failures", -1) == 0, "paired reference passed its checks")
	_compare_counts(reference.get("job_counts"), report["job_counts"], "identical jobs executed by kind")
	var previous: Dictionary = reference.get("checkpoints", {})
	for label in report["checkpoints"]:
		check(previous.has(label), "paired checkpoint exists: " + label)
		if not previous.has(label): continue
		for key in ["sha256", "ordered_sha256", "next_unit_uid", "next_item_uid"]:
			check(previous[label].get(key) == report["checkpoints"][label][key], "complete paired state agrees: " + label + "/" + key)

func run(tree: SceneTree) -> int:
	output = OS.get_environment("STARTUP_OUTPUT")
	if output.is_empty():
		printerr("STARTUP_OUTPUT is required; use fresh isolated evidence directories")
		return 1
	check(not FileAccess.file_exists(output.path_join("startup-timings.json")), "evidence directory is fresh")
	if failures > 0: return failures
	check(DirAccess.make_dir_recursive_absolute(output) == OK, "output directory can be created")
	var mode := _setting("STARTUP_MODE", "sliced")
	var days := int(_setting("STARTUP_DAYS", "30"))
	var size_name := _setting("STARTUP_SIZE", "normal")
	var seed_number := int(_setting("STARTUP_SEED", "777"))
	var budget := int(_setting("STARTUP_BUDGET_USEC", "12000"))
	var with_frames := _setting("STARTUP_FRAMES", "0") == "1"
	var fixed := _setting("STARTUP_FIXED_RAIDS", "0") == "1"
	var timeout_us := int(float(_setting("STARTUP_TIMEOUT_SEC", "300")) * 1e6)
	check(mode in ["atomic", "sliced"], "valid startup mode")
	check(days > 0 and days <= 12000, "bounded positive day count")
	check(WorldGen.SIZES.has(size_name), "known world size")
	check(budget >= 0 and timeout_us > 0, "nonnegative scheduling budget and positive timeout")
	if mode == "sliced":
		check(load("res://campaign/world.gd").has_method("presim_slice"), "sliced history API exists")
	if failures > 0: return failures
	WorldGen.gen_size = size_name
	var start := Time.get_ticks_usec()
	Game.new_game(seed_number)
	var setup_us := Time.get_ticks_usec() - start
	Game.world["presim"] = {"total": days, "done": 0, "from": Game.day}
	HerdRaids.benchmark_fixed_steps = fixed
	var checkpoints := {"initial": snapshot("initial")}
	var company_ages := {}; var company_births := {}
	for unit in Game.company:
		company_ages[unit.uid] = unit.age
		company_births[unit.uid] = unit.born
	var initial_gold := Game.gold
	var audit = Audit.new()
	audit.harvest_report["available"] = true
	audit.harvest_sample(int(Game.day))
	CampaignWorld.job_total = {}; CampaignWorld.job_worst = {}
	CampaignWorld.steps_total = 0; CampaignWorld.step_parts = {}; CampaignWorld.daily_total = {}
	var pending := {}
	var slices := []; var frame_gaps := []; var completed := []
	var cpu_us := 0; var overshoots := 0; var iterations := 0
	var wall_start := Time.get_ticks_usec()
	while CampaignWorld.presim_left(Game) > 0 and failures == 0:
		check(Time.get_ticks_usec() - wall_start < timeout_us, "history completes within bounded diagnostic timeout")
		check(iterations < days * 20000, "bounded scheduling iteration count")
		if failures > 0: break
		var before := int(Game.world["presim"]["done"])
		var before_day := Game.day
		var slice_start := Time.get_ticks_usec()
		var left: int
		if mode == "atomic": left = CampaignWorld.presim_step(Game, 1)
		else: left = _slice(pending, budget)
		var elapsed := Time.get_ticks_usec() - slice_start
		cpu_us += elapsed; slices.append(elapsed); iterations += 1
		if elapsed > budget: overshoots += 1
		if with_frames:
			await tree.process_frame
			frame_gaps.append(Time.get_ticks_usec() - slice_start)
		var done := int(Game.world["presim"]["done"])
		check(left == days - done, "remaining-day counter agrees with completed-day counter")
		check(done >= before and done <= before + 1, "a slice completes at most one day")
		check(Game.day >= before_day and Game.day <= before_day + 1.0, "a slice advances the date at most once")
		check(Game.day == float(done) if pending.is_empty() else Game.day == float(done + 1), "date reflects exactly one in-progress day")
		if done > before:
			check(pending.is_empty(), "completed day leaves no partial scheduling state")
			check(Game.world.get("work", []).is_empty(), "completed day drains its entire work queue")
			completed.append({"day": done, "cpu_seconds": cpu_us / 1e6, "slices": iterations})
			audit.harvest_sample(done)
			if done == 1 or done % 30 == 0 or done == days:
				var label := "day_%04d" % done
				checkpoints[label] = snapshot(label)
				print("STARTUP completed=%d/%d cpu=%.3fs slices=%d" % [done, days, cpu_us / 1e6, iterations])
	var measured_wall_us := Time.get_ticks_usec() - wall_start
	check(CampaignWorld.presim_left(Game) == 0, "all requested days completed")
	check(Game.day == float(days), "final day matches requested history")
	check(pending.is_empty() and Game.world.get("work", []).is_empty(), "final state has no pending day or work")
	check(Game.gold == initial_gold, "company pays no wages during history")
	for unit in Game.company:
		# Existing People.tick_ages updates the displayed age on birthdays during
		# history. presim_finish shifts birth dates forward and restores arrival age.
		check(unit.born == company_births[unit.uid], "company birth date stays fixed until history finish")
		check(unit.age == People.age_on(unit, Game.day), "company interim age follows the existing calendar")
	check(Sickness.check_counts(Game.world).is_empty(), "valid sickness counts")
	check(int(audit.harvest_report["violation_count"]) == 0, "dated ownership, physical stock, reserve and cash backing remain reconciled")
	if failures == 0:
		var before_complete := snapshot("complete")
		var idle_start := Time.get_ticks_usec()
		var idle_left := CampaignWorld.presim_step(Game, 1) if mode == "atomic" else _slice(pending, budget)
		check(idle_left == 0 and pending.is_empty(), "slicing a completed history is a no-op")
		var after_complete := snapshot("complete_again")
		check(before_complete["ordered_sha256"] == after_complete["ordered_sha256"], "completed-history no-op preserves complete state")
		print("STARTUP completed-history no-op plus verification=%.3fms" % [(Time.get_ticks_usec() - idle_start) / 1000.0])
		CampaignWorld.presim_finish(Game, 0)
		check(Game.world["presim"].get("finished", false), "history finish is recorded")
		check(Game.food_clock["last"] == Game.day, "company food clock begins on arrival")
		check(Game.world["party"]["safe_until"] == Game.day + 0.5, "company receives the original arrival safety window")
		for unit in Game.company:
			check(unit.age == company_ages[unit.uid], "company preserves its starting age after finish")
		checkpoints["finished"] = snapshot("finished")
	var max_slice := _percentile(slices, 1.0)
	var max_frame := _percentile(frame_gaps, 1.0)
	var slice_gate := float(_setting("STARTUP_MAX_SLICE_MS", "0"))
	var frame_gate := float(_setting("STARTUP_MAX_FRAME_MS", "0"))
	if slice_gate > 0: check(max_slice <= slice_gate, "maximum slice fits explicitly requested responsiveness gate")
	if frame_gate > 0:
		check(with_frames, "frame gate requires STARTUP_FRAMES=1")
		check(max_frame <= frame_gate, "maximum measured frame gap fits requested responsiveness gate")
	var report := {"mode": mode, "seed": seed_number, "size": size_name, "requested_days": days,
		"fixed_raids": fixed, "frames_enabled": with_frames, "budget_usec": budget,
		"setup_seconds": setup_us / 1e6, "simulation_cpu_seconds": cpu_us / 1e6,
		"diagnostic_wall_seconds": measured_wall_us / 1e6, "slice_us": slices, "frame_gap_us": frame_gaps,
		"slice_count": iterations, "budget_overshoots": overshoots,
		"worst_slice_ms": max_slice, "p95_slice_ms": _percentile(slices, 0.95),
		"worst_frame_gap_ms": max_frame, "p95_frame_gap_ms": _percentile(frame_gaps, 0.95),
		"completed_boundaries": completed, "job_counts": _job_counts(), "job_worst_us": CampaignWorld.job_worst,
		"checkpoints": checkpoints, "end_day": Game.day,
		"ownership_checks": audit.harvest_report["checks"], "ownership_violations": audit.harvest_report["violation_count"],
		"measurement_note": "No production UI or rendering measured. Frame gaps exclude snapshot/audit overhead. Fixed raids are diagnostic-only."}
	_compare(report, OS.get_environment("STARTUP_COMPARE_DIR"))
	report["failures"] = failures
	write_json("startup-timings.json", report)
	write_json("startup-harvest-audit.json", audit.harvest_report)
	HerdRaids.benchmark_fixed_steps = false
	print("STARTUP mode=%s days=%d cpu=%.3fs worst_slice=%.3fms worst_gap=%.3fms failures=%d" % [mode, days, cpu_us / 1e6, max_slice, max_frame, failures])
	return failures
