extends "res://tests/diag_producer_recovery.gd"
## A later comparison can reuse a real checkpoint rather than repeat generation/600 days.
## Both control and candidate must use this loader; a loaded run is not an exact VM/RNG replay.
func run(_tree: SceneTree) -> int:
	var source := OS.get_environment("PRODUCER_CHECKPOINT")
	var output := OS.get_environment("PRODUCER_OUTPUT")
	if source == "" or output == "" or not FileAccess.file_exists(source):
		printerr("PRODUCER_CHECKPOINT and PRODUCER_OUTPUT required"); return 1
	DirAccess.make_dir_recursive_absolute(output)
	var save := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	save.store_string(FileAccess.get_file_as_string(source)); save.close()
	if not Game.load_game(): return 1
	var report := EconomyAudit.world_report(Game)
	for town in report["towns"]:
		for issue in town["issues"]:
			if issue["rule"] != "full_market_broke_producer": continue
			if not selected.has(town["town"]): selected[town["town"]] = []
			selected[town["town"]].append(int(issue["business"]))
	write_json(output.path_join("audit.json"), report)
	var trace := [observations()]
	var days := 90 if OS.get_environment("PRODUCER_FOLLOW_DAYS") == "" else int(OS.get_environment("PRODUCER_FOLLOW_DAYS"))
	for d in days:
		if not advance_normal_day(): return 1
		trace.append(observations())
		if (d + 1) % 15 == 0: print("CHECKPOINT PRODUCER continuation day ", d + 1)
	write_json(output.path_join("follow90.json"), {"checkpoint": source, "loaded_not_exact_vm_replay": true, "selected": selected, "trace": trace})
	write_json(output.path_join("final_audit.json"), EconomyAudit.world_report(Game))
	Game._write_save(output.path_join("checkpoint_final.json"), Game._save_tree())
	return 0
