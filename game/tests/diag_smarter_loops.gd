extends RefCounted
## Exact-result and timing harness. PERF_OUTPUT is an absolute directory; PERF_DAYS defaults to 600.
## Checkpoints include the complete existing save tree, RNG state and next person ID at full float precision.
## No production rules, save format, timer-dependent steps or RNG calls are changed by this harness.

func run(_tree: SceneTree) -> int:
	var output := OS.get_environment("PERF_OUTPUT")
	if output.is_empty():
		printerr("PERF_OUTPUT must name a writable absolute directory")
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var days := 600 if OS.get_environment("PERF_DAYS").is_empty() else int(OS.get_environment("PERF_DAYS"))
	var seed_v := 2026 if OS.get_environment("PERF_SEED").is_empty() else int(OS.get_environment("PERF_SEED"))
	WorldGen.gen_size = "large"
	CampaignWorld.presim_years = 5
	var start := Time.get_ticks_usec()
	Game.new_game(seed_v)
	var gen_us := Time.get_ticks_usec() - start
	print("PERF baseline seed=%d towns=%d gen=%.3fs user_data=%s" % [seed_v, Game.world["towns"].size(), gen_us / 1e6, OS.get_user_data_dir()])
	CampaignWorld.job_total = {}; CampaignWorld.job_worst = {}
	CampaignWorld.steps_total = 0; CampaignWorld.step_parts = {}; CampaignWorld.daily_total = {}
	TownEcon.prof = {}; TownEcon.prof_on = true
	Sickness.prof = {}; Sickness.prof_parts = true; Sickness.prof_on = true
	var sim_us := 0
	var checkpoints := {}
	for d in days:
		start = Time.get_ticks_usec()
		CampaignWorld.presim_step(Game, 1)
		sim_us += Time.get_ticks_usec() - start
		if (d + 1) % 120 == 0 or d + 1 == days:
			print("PERF day=%d sim=%.3fs" % [d + 1, sim_us / 1e6])
		if d + 1 == 120 or d + 1 == days:
			var tree := Game._save_tree()
			tree["verification_rng_state"] = str(Game.rng.state)
			tree["verification_next_uid"] = Unit._next_uid
			var json := JSON.stringify(tree, "", true, true)
			var snapshot := output.path_join("day_%04d.snapshot.json" % (d + 1))
			var file := FileAccess.open(snapshot, FileAccess.WRITE)
			if file == null:
				printerr("Cannot write snapshot ", snapshot)
				return 1
			file.store_string(json)
			file.close()
			checkpoints[str(d + 1)] = {"sim_seconds": sim_us / 1e6, "sha256": json.sha256_text(),
				"summary": _summary(), "jobs_us": CampaignWorld.job_total.duplicate(true),
				"steps_us": CampaignWorld.step_parts.duplicate(true), "daily_us": CampaignWorld.daily_total.duplicate(true),
				"town_parts_us": TownEcon.prof.duplicate(true), "sickness_us": Sickness.prof.duplicate(true)}
			var report := FileAccess.open(output.path_join("timings.json"), FileAccess.WRITE)
			report.store_string(JSON.stringify({"seed": seed_v, "size": "large", "towns": Game.world["towns"].size(),
				"generation_seconds": gen_us / 1e6, "checkpoints": checkpoints}, "\t", true, true))
			report.close()
			print("PERF checkpoint %d sha256=%s" % [d + 1, json.sha256_text()])
	CampaignWorld.presim_finish(Game, 0)
	TownEcon.prof_on = false; Sickness.prof_parts = false; Sickness.prof_on = false
	return 0

func _summary() -> Dictionary:
	var out := {"population": 0, "families": 0, "family_rows": 0, "deaths_by_cause": {}, "goods": {},
		"coins": Barge.holdings(Game), "armies": Game.world["warbands"].size()}
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town):
			continue
		var e: Dictionary = town["econ"]
		out["population"] += Census.people(e)
		out["family_rows"] += e["fams"].size()
		for f in e["fams"]:
			if not f.get("gone", false): out["families"] += 1
		for g in e["stock"]:
			out["goods"][g] = float(out["goods"].get(g, 0.0)) + float(e["stock"][g])
		var rows: Array = Census.rows(e).duplicate()
		rows.append(Census.current(e))
		for row in rows:
			for cause in row["deaths"]:
				out["deaths_by_cause"][cause] = int(out["deaths_by_cause"].get(cause, 0)) + int(row["deaths"][cause])
	return out
