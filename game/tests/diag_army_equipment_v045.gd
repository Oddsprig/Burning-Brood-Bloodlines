extends RefCounted
## Independent full-v044/current paired actual rekit_town calls.
## ARMY_SAVE optionally loads an authentic checkpoint through isolated user:// storage.
## ARMY_DAYS defaults to 30 for fresh and 0 for saved, ARMY_SEED defaults to 5159.
## ARMY_OUTPUT optionally names a structured JSON report file; its parent must exist.
## Every job is reported, including regressions; timings never replace existing gates.
const Equivalence = preload("res://tests/test_army_equipment_v045.gd")

func run(_tree: SceneTree) -> int:
	var oracle = Equivalence.new()
	var source := OS.get_environment("ARMY_SAVE")
	var days := 30 if source.is_empty() else 0
	if not OS.get_environment("ARMY_DAYS").is_empty(): days = int(OS.get_environment("ARMY_DAYS"))
	var seed_value := 5159
	if not OS.get_environment("ARMY_SEED").is_empty(): seed_value = int(OS.get_environment("ARMY_SEED"))
	oracle.check(days >= 0, "nonnegative actual simulation duration")
	if source.is_empty():
		WorldGen.gen_size = "large"
		CampaignWorld.presim_years = 5
		Game.new_game(seed_value)
	else:
		oracle.check(FileAccess.file_exists(source), "authentic saved checkpoint supplied")
		if oracle.fails > 0: return oracle.fails
		var isolated := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		oracle.check(isolated != null, "isolated checkpoint copy writable")
		if oracle.fails > 0: return oracle.fails
		isolated.store_string(FileAccess.get_file_as_string(source)); isolated.close()
		oracle.check(Game.load_game(), "authentic checkpoint loads")
	if oracle.fails > 0: return oracle.fails
	var label: String = "fresh seed%d" % seed_value if source.is_empty() else "authentic checkpoint"
	var reports := [oracle.compare_real_jobs(label + " day%.0f" % Game.day, 7)]
	for i in days:
		if source.is_empty(): CampaignWorld.presim_step(Game, 1)
		else: Game.advance_time(1.0, true)
		if (i + 1) % 10 == 0 or i + 1 == days:
			reports.append(oracle.compare_real_jobs(label + " day%.0f" % Game.day, 7))
	var output := OS.get_environment("ARMY_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		oracle.check(file != null, "structured paired diagnostic report writable")
		if file != null:
			file.store_string(JSON.stringify({"seed": seed_value, "source": source, "days": days,
				"recorded_pairs": 7, "discarded_warmup_pairs": 1, "reports": reports,
				"checks": oracle.checks, "failures": oracle.fails}, "\t", false, true))
			file.close()
	print("ARMY EQUIPMENT DIAGNOSTIC checks=%d failures=%d" % [oracle.checks, oracle.fails])
	return oracle.fails
