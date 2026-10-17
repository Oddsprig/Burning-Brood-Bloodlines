extends "res://tests/diag_release_perf.gd"
## Separate-process baseline/candidate guard for synchronous Game.advance_time.
## STARTUP_OUTPUT required; STARTUP_COMPARE_DIR optionally names a prior report.
## STARTUP_SIZE=normal STARTUP_SEED=777 STARTUP_FIXED_RAIDS=1 by default.
## For both in_town=false and true, real time advances to just before midnight,
## then .01, .05, .249, .25, 1.0, 2.4 days exercise real queued work and its cutoff.
## No fake people, inventory, money, job rows, presim context or production screens.
## Fixed raid ticks provide exact-work comparison only. CPU times are observations.

const ADVANCES := [0.01, 0.05, 0.249, 0.25, 1.0, 2.4]

func _env(name: String, fallback: String) -> String:
	var value := OS.get_environment(name)
	return fallback if value.is_empty() else value

func _counts() -> Dictionary:
	var result := {}
	for kind in CampaignWorld.job_total:
		result[kind] = int(CampaignWorld.job_total[kind][1])
	return result

func _count_total(counts: Dictionary) -> int:
	var total := 0
	for amount in counts.values(): total += int(amount)
	return total

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
		check(float(old_value) == float(new_value), label + ": identical count " + str(kind))

func _checkpoint(label: String) -> Dictionary:
	var result := snapshot(label)
	# These live company/battle values are deliberately outside the normal save tree.
	var extra := {"healing_accumulator": Game._heal_acc,
		"pending_battle": _stable(Game.pending_battle), "last_result": _stable(Game.last_result)}
	var encoded := JSON.stringify(extra, "", false, true)
	result["transient_sha256"] = encoded.sha256_text()
	write_json(label + ".transient.json", extra)
	return result

func _compare_time(report: Dictionary) -> void:
	var directory := OS.get_environment("STARTUP_COMPARE_DIR")
	if directory.is_empty(): return
	var previous = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("time-equivalence.json")))
	check(previous is Dictionary, "reference time-equivalence report exists and parses")
	if not previous is Dictionary: return
	for key in ["seed", "size", "fixed_raids", "advance_days", "contexts"]:
		check(previous.get(key) == report[key], "paired time configuration agrees: " + key)
	check(previous.get("failures", -1) == 0, "reference time-equivalence checks passed")
	_compare_counts(previous.get("job_counts"), report["job_counts"], "all synchronous job counts agree")
	var old_checkpoints: Dictionary = previous.get("checkpoints", {})
	for label in report["checkpoints"]:
		check(old_checkpoints.has(label), "paired time checkpoint exists: " + label)
		if not old_checkpoints.has(label): continue
		for key in ["sha256", "ordered_sha256", "next_unit_uid", "next_item_uid", "transient_sha256"]:
			check(old_checkpoints[label].get(key) == report["checkpoints"][label][key], "complete synchronous state agrees: " + label + "/" + key)
	var old_calls: Array = previous.get("calls", [])
	check(old_calls.size() == report["calls"].size(), "paired synchronous call count agrees")
	for index in mini(old_calls.size(), report["calls"].size()):
		for key in ["label", "days", "in_town", "start_day", "end_day", "queue_before", "queue_after", "jobs_executed"]:
			check(old_calls[index].get(key) == report["calls"][index][key], "fractional cadence agrees: call %d/%s" % [index, key])
		_compare_counts(old_calls[index].get("job_counts"), report["calls"][index]["job_counts"], "fractional job counts call %d" % index)

func _advance(label: String, days: float, in_town: bool, calls: Array) -> void:
	var start_day := Game.day
	var queue_before: int = Game.world.get("work", []).size()
	var before := _count_total(_counts())
	var begin := Time.get_ticks_usec()
	Game.advance_time(days, in_town)
	var cpu_us := Time.get_ticks_usec() - begin
	var counts := _counts()
	var executed := _count_total(counts) - before
	var queue_after: int = Game.world.get("work", []).size()
	check(absf(Game.day - start_day - days) < 0.0000001, "requested time advances exactly once: " + label)
	check(int(Game.world.get("last_day", 0)) == int(floor(Game.day)), "all crossed midnights processed: " + label)
	check(not Game.world.has("presim"), "ordinary time creates no history state: " + label)
	if days >= 0.25: check(queue_after == 0, "quarter-day and longer calls drain all daily work: " + label)
	calls.append({"label": label, "days": days, "in_town": in_town,
		"start_day": start_day, "end_day": Game.day, "queue_before": queue_before,
		"queue_after": queue_after, "jobs_executed": executed, "job_counts": counts, "cpu_us": cpu_us})

func run(_tree: SceneTree) -> int:
	output = OS.get_environment("STARTUP_OUTPUT")
	check(not output.is_empty(), "STARTUP_OUTPUT is provided")
	if failures > 0: return failures
	check(not FileAccess.file_exists(output.path_join("time-equivalence.json")), "time evidence directory is fresh")
	check(DirAccess.make_dir_recursive_absolute(output) == OK, "time output directory can be created")
	var size_name := _env("STARTUP_SIZE", "normal")
	var seed_number := int(_env("STARTUP_SEED", "777"))
	var fixed := _env("STARTUP_FIXED_RAIDS", "1") == "1"
	check(WorldGen.SIZES.has(size_name), "known time-equivalence world size")
	if failures > 0: return failures
	WorldGen.gen_size = size_name
	var begin := Time.get_ticks_usec()
	Game.new_game(seed_number)
	var setup_us := Time.get_ticks_usec() - begin
	HerdRaids.benchmark_fixed_steps = fixed
	CampaignWorld.job_total = {}; CampaignWorld.job_worst = {}
	CampaignWorld.steps_total = 0; CampaignWorld.step_parts = {}; CampaignWorld.daily_total = {}
	var checkpoints := {"initial": _checkpoint("initial")}
	var calls := []
	var audit = Audit.new()
	audit.harvest_report["available"] = true
	audit.harvest_sample(int(Game.day))
	for in_town in [false, true]:
		var context := "town" if in_town else "map"
		# Prime only by real simulation, leaving the clock .005 before midnight.
		# The following .01 call enqueues actual funded economy/person jobs and
		# drains only the ordinary fractional allowance; later fractions consume it.
		var prime: float = floor(Game.day) + 0.995 - Game.day
		if prime <= 0.0: prime += 1.0
		_advance(context + "_prime", prime, in_town, calls)
		for index in ADVANCES.size():
			var label := "%s_%02d" % [context, index]
			var delta := float(ADVANCES[index])
			_advance(label, delta, in_town, calls)
			checkpoints[label] = _checkpoint(label)
			if index == 0:
				check(not Game.world.get("work", []).is_empty(), "midnight fractional call leaves real queued work: " + context)
			if Game.world.get("work", []).is_empty(): audit.harvest_sample(int(Game.day))
	check(Sickness.check_counts(Game.world).is_empty(), "valid synchronous sickness counts")
	check(int(audit.harvest_report["violation_count"]) == 0, "synchronous drained boundaries conserve dated ownership")
	var cpu_total := 0; var worst := 0
	for observation in calls:
		cpu_total += int(observation["cpu_us"])
		worst = maxi(worst, int(observation["cpu_us"]))
	var report := {"seed": seed_number, "size": size_name, "fixed_raids": fixed,
		"advance_days": ADVANCES, "contexts": [false, true], "setup_seconds": setup_us / 1e6,
		"calls": calls, "checkpoints": checkpoints, "job_counts": _counts(),
		"simulation_cpu_seconds": cpu_total / 1e6, "mean_call_ms": float(cpu_total) / calls.size() / 1000.0,
		"worst_call_ms": worst / 1000.0, "end_day": Game.day,
		"ownership_checks": audit.harvest_report["checks"], "ownership_violations": audit.harvest_report["violation_count"],
		"measurement_note": "Fresh real world; synchronous advance_time including wages, healing and food. Snapshots/audits excluded from CPU. Fixed raid ticks are diagnostic-only."}
	_compare_time(report)
	report["failures"] = failures
	write_json("time-equivalence.json", report)
	write_json("time-equivalence-harvest-audit.json", audit.harvest_report)
	HerdRaids.benchmark_fixed_steps = false
	print("TIME EQUIVALENCE calls=%d end=%.3f cpu=%.3fs failures=%d" % [calls.size(), Game.day, cpu_total / 1e6, failures])
	return failures
