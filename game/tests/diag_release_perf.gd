extends RefCounted
## Paired release benchmark: unchanged daily simulation and complete save snapshots.
## PERF_SAVE optionally reads an existing checkpoint into isolated user:// storage.
## PERF_DAYS, PERF_SEED and PERF_OUTPUT define a repeatable fresh-process run.
## PERF_FIXED_RAIDS=1 fixes the diagnostic battle quota; ordinary play is unchanged.
## Timing excludes snapshots and ownership checks. No production cadence changes.

const Audit = preload("res://tests/diag_economy_audit.gd")
var failures := 0
var output := ""

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func snapshot(label: String) -> Dictionary:
	var state := Game._save_tree()
	state["verification_rng_state"] = str(Game.rng.state)
	state["verification_next_unit_uid"] = Unit._next_uid
	state["verification_next_item_uid"] = Item._next_uid
	state["verification_pasture_fights"] = _fight_state()
	var ordered_sha256 := JSON.stringify(state, "", false, true).sha256_text()
	var encoded := JSON.stringify(state, "", true, true)
	var file := FileAccess.open(output.path_join(label + ".snapshot.json"), FileAccess.WRITE)
	check(file != null, "snapshot file is writable")
	if file != null:
		file.store_string(encoded)
		file.close()
	return {"day": Game.day, "sha256": encoded.sha256_text(), "ordered_sha256": ordered_sha256, "bytes": encoded.length(),
		"next_unit_uid": Unit._next_uid, "next_item_uid": Item._next_uid}

func write_json(name: String, data: Dictionary) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	check(file != null, name + " is writable")
	if file != null:
		file.store_string(JSON.stringify(data, "\t", true, true))
		file.close()

func run(_tree: SceneTree) -> int:
	output = OS.get_environment("PERF_OUTPUT")
	if output.is_empty():
		printerr("PERF_OUTPUT is required")
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var source := OS.get_environment("PERF_SAVE")
	var days := 28 if not source.is_empty() else 120
	if not OS.get_environment("PERF_DAYS").is_empty(): days = int(OS.get_environment("PERF_DAYS"))
	check(days > 0, "positive requested duration")
	if failures > 0: return failures
	var seed_v := 2026 if OS.get_environment("PERF_SEED").is_empty() else int(OS.get_environment("PERF_SEED"))
	WorldGen.gen_size = "large"
	CampaignWorld.presim_years = 5
	var begin := Time.get_ticks_usec()
	if source.is_empty():
		Game.new_game(seed_v)
	else:
		check(FileAccess.file_exists(source), "original checkpoint exists")
		if failures > 0: return failures
		var copied := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		check(copied != null, "isolated checkpoint copy writable")
		if failures > 0: return failures
		copied.store_string(FileAccess.get_file_as_string(source))
		copied.close()
		check(Game.load_game(), "isolated existing campaign loads")
		if failures > 0: return failures
	var setup_us := Time.get_ticks_usec() - begin
	HerdRaids.benchmark_fixed_steps = OS.get_environment("PERF_FIXED_RAIDS") == "1"
	var start_day := Game.day
	var initial := snapshot("initial")
	var audit = Audit.new()
	audit.harvest_report["available"] = true
	audit.harvest_sample(int(Game.day))
	CampaignWorld.job_total = {}; CampaignWorld.job_worst = {}
	CampaignWorld.steps_total = 0; CampaignWorld.step_parts = {}; CampaignWorld.daily_total = {}
	var profile := OS.get_environment("PERF_PROFILE") == "1"
	TownEcon.prof = {}; TownEcon.prof_on = profile
	Sickness.prof = {}; Sickness.prof_parts = profile; Sickness.prof_on = profile
	var elapsed_us := 0
	var daily_us := []
	print("RELEASE PERF mode=%s start=%.0f days=%d towns=%d setup=%.3fs profile=%s fixed_raids=%s" % [
		"new history" if source.is_empty() else "saved campaign", start_day, days,
		Game.world["towns"].size(), setup_us / 1e6, str(profile), str(HerdRaids.benchmark_fixed_steps)])
	for day in days:
		begin = Time.get_ticks_usec()
		if source.is_empty(): CampaignWorld.presim_step(Game, 1)
		else: Game.advance_time(1.0, true)
		var elapsed := Time.get_ticks_usec() - begin
		elapsed_us += elapsed
		daily_us.append(elapsed)
		check(absf(Game.day - start_day - day - 1.0) < 0.000001, "each requested day advances exactly once")
		if failures > 0: break
		if (day + 1) % 10 == 0 or day + 1 == days:
			audit.harvest_sample(int(Game.day))
			print("RELEASE PERF day=%.0f simulation=%.3fs" % [Game.day, elapsed_us / 1e6])
	var final := snapshot("final")
	check(int(audit.harvest_report["violation_count"]) == 0, "physical stock, dated shares, reserves, pending carry and backed cash remain reconciled")
	var sorted_us := daily_us.duplicate(); sorted_us.sort()
	var report := {"mode": "new_history" if source.is_empty() else "saved_campaign",
		"source_save": source, "seed": Game.seed_value, "requested_days": days,
		"start_day": start_day, "end_day": Game.day, "towns": Game.world["towns"].size(),
		"setup_seconds": setup_us / 1e6, "simulation_seconds": elapsed_us / 1e6,
		"daily_us": daily_us, "median_day_ms": float(sorted_us[sorted_us.size() / 2]) / 1000.0,
		"worst_day_ms": float(sorted_us[-1]) / 1000.0, "profile_enabled": profile,
		"fixed_raid_steps": HerdRaids.benchmark_fixed_steps,
		"jobs_us": CampaignWorld.job_total.duplicate(true), "job_worst_us": CampaignWorld.job_worst.duplicate(true),
		"steps_us": CampaignWorld.step_parts.duplicate(true), "daily_parts_us": CampaignWorld.daily_total.duplicate(true),
		"town_parts_us": TownEcon.prof.duplicate(true), "sickness_us": Sickness.prof.duplicate(true),
		"initial": initial, "final": final, "failures": failures,
		"ownership_checks": audit.harvest_report["checks"], "ownership_violations": audit.harvest_report["violation_count"]}
	write_json("timings.json", report)
	write_json("harvest-audit.json", audit.harvest_report)
	TownEcon.prof_on = false; Sickness.prof_parts = false; Sickness.prof_on = false
	HerdRaids.benchmark_fixed_steps = false
	print("RELEASE PERF total=%.3fs worst_day=%.3fms ownership_checks=%d violations=%d failures=%d" % [
		elapsed_us / 1e6, float(sorted_us[-1]) / 1000.0, audit.harvest_report["checks"], audit.harvest_report["violation_count"], failures])
	return failures

## Include in-progress combat state, which the normal save tree does not serialize.
## Object references use gameplay IDs, never process-specific instance addresses.
func _fight_state() -> Array:
	var out := []
	for wid in HerdRaids.fights:
		var fight: Dictionary = HerdRaids.fights[wid]
		var sim: BattleSim = fight["sim"]
		var people := []
		for f in sim.fighters: people.append(_script_state(f))
		out.append([wid, _script_state(sim), people, _stable(fight["defenders"])])
	return out

func _script_state(obj: Object) -> Array:
	var out := []
	for property in obj.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append([String(property["name"]), _stable(obj.get(property["name"]))])
	return out

func _stable(value):
	if value is Unit: return ["unit", value.uid]
	if value is Item: return ["item", value.to_dict()]
	if value is Fighter: return ["fighter", value.idx]
	if value is RandomNumberGenerator: return ["rng", str(value.seed), str(value.state)]
	if value is Dictionary:
		var out := []
		for key in value: out.append([_stable(key), _stable(value[key])])
		return out
	if value is Array:
		var out := []
		for item in value: out.append(_stable(item))
		return out
	return Game._serialize(value)
