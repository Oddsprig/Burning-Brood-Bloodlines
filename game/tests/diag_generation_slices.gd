extends "res://tests/diag_startup_slices.gd"
## Fresh-process staged world generation, no production scene/input/autosave.
## STARTUP_OUTPUT required; STARTUP_COMPARE_DIR optionally names an atomic startup
## reference whose initial checkpoint uses total=STARTUP_DAYS (default30).
## STARTUP_SIZE=normal STARTUP_SEED=777 STARTUP_BUDGET_USEC=12000 (0=one part).
## STARTUP_FRAMES=1 optionally yields between slices; STARTUP_TIMEOUT_SEC=120.
## Game.new_game_begin(seed)->Dictionary; new_game_slice(state,budget)->bool.
## World generation context/progress is temporary and excluded from game saves.

func run(tree: SceneTree) -> int:
	output = OS.get_environment("STARTUP_OUTPUT")
	check(not output.is_empty(), "STARTUP_OUTPUT is provided")
	if failures > 0: return failures
	check(not FileAccess.file_exists(output.path_join("generation-timings.json")), "generation evidence is fresh")
	check(DirAccess.make_dir_recursive_absolute(output) == OK, "generation output can be created")
	var size_name := _setting("STARTUP_SIZE", "normal")
	var seed_number := int(_setting("STARTUP_SEED", "777"))
	var days := int(_setting("STARTUP_DAYS", "30"))
	var budget := int(_setting("STARTUP_BUDGET_USEC", "12000"))
	var timeout_us := int(float(_setting("STARTUP_TIMEOUT_SEC", "120")) * 1e6)
	var with_frames := _setting("STARTUP_FRAMES", "0") == "1"
	check(WorldGen.SIZES.has(size_name) and days > 0, "valid generation configuration")
	check(budget >= 0 and timeout_us > 0, "nonnegative generation budget and positive timeout")
	check(Game.has_method("new_game_begin") and Game.has_method("new_game_slice"), "staged new-game API exists")
	if failures > 0: return failures
	WorldGen.gen_size = size_name
	var world_script = load("res://campaign/world.gd")
	var changed_count := [0]
	var on_changed: Callable = func(): changed_count[0] += 1
	Game.changed.connect(on_changed)
	var wall_start := Time.get_ticks_usec()
	var begin := wall_start
	var pending: Dictionary = Game.call("new_game_begin", seed_number)
	var begin_us := Time.get_ticks_usec() - begin
	check(Game.day == 0.0, "generation begin leaves date at zero")
	check(changed_count[0] == 0, "generation begin does not publish partial state")
	check(not pending.is_empty(), "generation begin returns retained context")
	var cpu_us := begin_us
	var slices := []; var frame_gaps := []; var stages := []
	var completed := false
	var previous_progress := 0.0
	while not completed and failures == 0:
		check(Time.get_ticks_usec() - wall_start < timeout_us, "generation finishes within bounded timeout")
		check(slices.size() < 100000, "bounded generation slice count")
		if failures > 0: break
		var stage := str(world_script.call("generation_stage_name", pending))
		begin = Time.get_ticks_usec()
		completed = bool(Game.call("new_game_slice", pending, budget))
		var elapsed := Time.get_ticks_usec() - begin
		cpu_us += elapsed; slices.append(elapsed)
		if with_frames:
			await tree.process_frame
			frame_gaps.append(Time.get_ticks_usec() - begin)
		var progress := float(world_script.call("generation_progress", pending))
		check(progress >= previous_progress and progress >= 0.0 and progress <= 1.0, "generation progress stays bounded and monotone")
		previous_progress = progress
		check(Game.day == 0.0, "generation does not advance campaign time")
		check(changed_count[0] == (1 if completed else 0), "changed signal publishes only completed generation")
		check(pending.is_empty() == completed, "caller context clears exactly at completion")
		stages.append({"stage": stage, "progress": progress, "cpu_us": elapsed})
	var wall_us := Time.get_ticks_usec() - wall_start
	check(completed and pending.is_empty(), "world generation completes with no caller state")
	check(not Game.world.is_empty() and Game.day == 0.0, "completed world is present on day zero")
	check(Game._save_task == -1, "staged generation starts no autosave")
	var generated := {}
	if completed:
		Game.world["presim"] = {"total": days, "done": 0, "from": Game.day}
		generated = snapshot("initial")
		check(bool(Game.call("new_game_slice", pending, 0)), "completed generation slice is a successful no-op")
		check(changed_count[0] == 1 and pending.is_empty(), "generation no-op neither republishes nor retains context")
		var generated_again: Dictionary = snapshot("initial_again")
		check(generated["ordered_sha256"] == generated_again["ordered_sha256"], "generation no-op preserves the complete generated world")
		var directory := OS.get_environment("STARTUP_COMPARE_DIR")
		if not directory.is_empty():
			var previous = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("startup-timings.json")))
			check(previous is Dictionary, "atomic generation reference exists")
			if previous is Dictionary:
				for key in ["seed", "size", "requested_days"]:
					var current = seed_number if key == "seed" else (size_name if key == "size" else days)
					check(previous.get(key) == current, "generation reference configuration agrees: " + key)
				var reference: Dictionary = previous.get("checkpoints", {}).get("initial", {})
				for key in ["sha256", "ordered_sha256", "next_unit_uid", "next_item_uid"]:
					check(reference.get(key) == generated[key], "complete generated world matches atomic reference: " + key)
				check(previous.get("failures", -1) == 0, "atomic generation reference passed its checks")
	Game.changed.disconnect(on_changed)
	var report := {"seed": seed_number, "size": size_name, "requested_days": days, "budget_usec": budget,
		"begin_usec": begin_us, "generation_cpu_seconds": cpu_us / 1e6, "generation_wall_seconds": wall_us / 1e6,
		"generation_parts_cpu_usec": int(world_script.generation_parts_total_usec),
		"worst_generation_part_ms": int(world_script.generation_part_worst_usec) / 1000.0,
		"generation_part_count": int(world_script.generation_part_count),
		"slice_us": slices, "slice_count": slices.size(), "worst_slice_ms": _percentile(slices, 1.0),
		"p95_slice_ms": _percentile(slices, 0.95), "frame_gap_us": frame_gaps,
		"worst_frame_gap_ms": _percentile(frame_gaps, 1.0), "stages": stages,
		"changed_signal_count": changed_count[0], "completed": completed,
		"caller_state_empty": pending.is_empty(), "initial": generated, "failures": failures,
		"measurement_note": "Begin plus generation slices timed; snapshots excluded. Budget0 measures one atomic part per slice; soft budgets allow atomic overruns."}
	write_json("generation-timings.json", report)
	print("GENERATION slices=%d cpu=%.3fs worst_slice=%.3fms changed=%d failures=%d" % [slices.size(), cpu_us / 1e6, _percentile(slices, 1.0), changed_count[0], failures])
	return failures
