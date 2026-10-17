extends RefCounted
## v0.034 diagnostic (not a pass/fail check): a fresh Normal world (seed 4242) after house selection, advanced
## --days=N campaign days through Game.advance_time. Prints population, the common folk, sickness cases and deaths
## (whole book and common-folk rows), moves by reason and the run time, so a version can be compared with the last.
## -- --test=res://tests/diag_population_v034.gd [--days=180]
func run(tree: SceneTree) -> int:
	var days := 180
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--days="): days = int(a.trim_prefix("--days="))
	await tree.process_frame
	Game.wait_save()
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(4242)
	while not Game.new_game_slice(generation, 8000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game); Game.new_game_finalize()
	for choice: Dictionary in Dynasty.choices(Game):
		if bool(HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false)): break
	_print("start", 0)
	Sickness.prof_on = true; Sickness.job_worst = 0; Migration.worst_us = 0
	var t0 := Time.get_ticks_usec()
	var worst := 0
	for i in days:
		var d0 := Time.get_ticks_usec()
		Game.advance_time(1.0, false, 0, 0)
		worst = maxi(worst, Time.get_ticks_usec() - d0)
		if (i + 1) % 60 == 0: _print("day %d" % (i + 1), 0)
	print("diag034: %d days in %.1f s, worst day %.0f ms; worst sickness job %.1f ms, sickness total %.1f s; worst migration week %.1f ms" % [days, float(Time.get_ticks_usec() - t0) / 1e6, float(worst) / 1000.0,
		float(Sickness.job_worst) / 1000.0, float(Sickness.us) / 1e6, float(Migration.worst_us) / 1000.0])
	Game.wait_save()
	return 0

func _print(label: String, _x: int) -> void:
	var pop := 0; var anon := 0; var cases := 0; var deaths := 0; var pool_open := 0; var moved := {}
	var census_sick := 0
	for tid in Game.world["towns"]:
		var t: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		pop += int(e["pop"])
		var b: Dictionary = e.get("sk", {})
		for dis in b.get("cases", {}): cases += int(b["cases"][dis])
		for dis in b.get("deaths", {}): deaths += int(b["deaths"][dis])
		for f in e["fams"]:
			if Population.is_cohort(f) and not f.get("gone", false):
				anon += Population.anonymous(f, 0) + Population.anonymous(f, 1) + Population.anonymous(f, 2) + Population.anonymous(f, 3)
				for c in f.get("psk", []): pool_open += int(c[2])
		for k in e["stats"]:
			if String(k).begins_with("left_") and String(k) != "left_to": moved[k] = int(moved.get(k, 0)) + int(e["stats"][k])
		for row in Census._book(e)["deaths"]:
			if String(row[5]) == "sickness": census_sick += int(row[10]) if row.size() > 10 else 1
	print("diag034 %s: day %d people %d common %d | sickness cases %d deaths %d (census %d) common open %d | left %s" % [label, int(Game.day), pop, anon, cases, deaths, census_sick, pool_open, str(moved)])
