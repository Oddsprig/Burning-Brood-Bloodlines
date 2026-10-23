extends "res://tests/diag_release_perf.gd"
## Separate-process complete native state comparison, fresh world only.
## Every fixed advance fully settles its real ordered queue before the next.
var assertions := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	super.check(ok,message)
func run(tree: SceneTree) -> int:
	output = ""
	var reference := ""
	var size := "normal"
	var advances := 300
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): output = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
		elif arg.begins_with("--compare-dir="): reference = arg.trim_prefix("--compare-dir=").replace("\\", "/").simplify_path()
		elif arg.begins_with("--size="): size = arg.trim_prefix("--size=")
		elif arg.begins_with("--advances="): advances = int(arg.trim_prefix("--advances="))
	check(output.begins_with("C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"), "private evidence directory")
	check(not FileAccess.file_exists(output.path_join("campaign-state.json")), "new evidence output")
	check(size in ["normal", "large"] and advances in [200,300], "bounded native campaign comparison")
	if failures > 0: return failures
	DirAccess.make_dir_recursive_absolute(output)
	WorldGen.gen_size = size
	CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(777)
	while not Game.new_game_slice(generation, 4000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 4000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	var choices := Dynasty.choices(Game)
	check(Game.day == 1.0 and not choices.is_empty(), "fresh exactly one-day world")
	if not choices.is_empty(): check(Dynasty.select_city(Game, choices[0]["town_id"]), "native house selected")
	Game.world["party"]["safe_until"] = Game.day + 100.0
	Game.goto("map")
	# Offscreen herd battles have a diagnostic fixed native tick allowance so
	# faster CPUs cannot change which battle ticks the comparison requests.
	HerdRaids.benchmark_fixed_steps = true
	TownEcon.prof_on = true
	TownEcon.prof.clear()
	Perf._labels.clear()
	CampaignWorld.job_total.clear()
	CampaignWorld.job_worst.clear()
	var states := {"initial":snapshot("initial")}
	var begin := Time.get_ticks_usec()
	var settling := 0
	var frame_worst := 0
	for step in advances:
		var started := Time.get_ticks_usec()
		var requested := 1.0 + float(step + 1) / 100.0
		Game.advance_time(requested - Game.day, false, 0, 4000)
		while not Game.world.get("work", []).is_empty():
			CampaignWorld.work_slice(Game, 4000)
			settling += 1
		frame_worst = maxi(frame_worst, Time.get_ticks_usec() - started)
	var end_day := 1.0 + float(advances) / 100.0
	check(Game.day == end_day and Game.world.get("work", []).is_empty(), "all requested native midnights settled")
	var end_label := "day%d" % int(end_day)
	states[end_label] = snapshot(end_label)
	var counts := {}
	for kind in CampaignWorld.job_total: counts[kind] = CampaignWorld.job_total[kind][1]
	var report := {"seed":777,"size":size,"history_days":1,"checkpoints":states,
		"job_counts":counts,"job_worst_us":CampaignWorld.job_worst,"town_phase_us":TownEcon.prof,
		"diagnostics":Perf.snapshot(),"fixed_advance_count":advances,"end_day":Game.day,
		"settle_calls":settling,"fixed_advance_plus_settle_worst_us":frame_worst,
		"cpu_plus_snapshot_ms":float(Time.get_ticks_usec()-begin)/1000.0,"failures":failures}
	if reference != "":
		var old = JSON.parse_string(FileAccess.get_file_as_string(reference.path_join("campaign-state.json")))
		check(old is Dictionary and int(old.get("failures", -1)) == 0, "baseline report valid")
		if old is Dictionary:
			for label in states:
				for field in ["sha256","ordered_sha256","next_unit_uid","next_item_uid"]:
					check(old["checkpoints"][label][field] == states[label][field], "complete native state " + label + "/" + field)
			# JSON numbers read back as floats. Compare numeric counts explicitly,
			# retaining exact key coverage instead of Dictionary's Variant types.
			var native_counts := counts.duplicate()
			native_counts.erase("dragon_care_pay")
			native_counts.erase("ownership_finish")
			check(old["job_counts"].size() == native_counts.size(), "same original native job kinds")
			for kind in native_counts:
				check(old["job_counts"].has(kind) and float(old["job_counts"].get(kind, -1)) == float(native_counts[kind]), "native execution count " + kind)
			check(float(counts.get("dragon_care_pay",0)) == float(old["job_counts"].get("dragon_care",0)), "one payment continuation per original care job")
			var prior_finishes := 0
			for stat in old["diagnostics"]["jobs"]:
				if stat["label"] == "Ownership reconciliation": prior_finishes = int(stat["calls"])
			check(int(counts.get("ownership_finish",0)) == prior_finishes, "exact original final reconciliation count")
	var report_file := FileAccess.open(output.path_join("campaign-state.json"), FileAccess.WRITE)
	check(report_file != null, "comparison report writable")
	report["failures"] = failures
	report["assertions"] = assertions
	if report_file != null:
		report_file.store_string(JSON.stringify(report,"  ",true,true))
		report_file.close()
	print("campaign state day%.1f counts%s checks%d failures%d" % [Game.day,JSON.stringify(counts),assertions,failures])
	Game.world.clear()
	Dynasty.note_households_changed()
	Game.company.clear()
	TownEcon.prof_on = false
	HerdRaids.benchmark_fixed_steps = false
	return failures
