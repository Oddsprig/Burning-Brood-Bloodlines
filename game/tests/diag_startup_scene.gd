extends "res://tests/diag_startup_slices.gd"
## Bounded real presim-scene heartbeat, stopped before finish/save/map transition.
## STARTUP_OUTPUT required. STARTUP_UI_DAYS=3 (1..30), STARTUP_SIZE=normal,
## STARTUP_SEED=777, STARTUP_TIMEOUT_SEC=120, optional STARTUP_MAX_FRAME_MS gate.
## STARTUP_NEW_WORLD=1 measures loading UI then production staged generation via
## Game.screen_params. Default existing-world route stays compatible with baseline.
## Ordinary raid cadence. Headless process gaps do not measure GPU/rendering.

func run(tree: SceneTree) -> int:
	# The runner calls run from its own _ready. Wait for that root child-add pass
	# to finish before attaching a second scene, and exclude this wait from timings.
	await tree.process_frame
	output = OS.get_environment("STARTUP_OUTPUT")
	check(not output.is_empty(), "STARTUP_OUTPUT is provided")
	if failures > 0: return failures
	check(not FileAccess.file_exists(output.path_join("startup-scene-timings.json")), "scene evidence is fresh")
	check(DirAccess.make_dir_recursive_absolute(output) == OK, "scene output can be created")
	var requested: int = int(_setting("STARTUP_UI_DAYS", "3"))
	var timeout_us: int = int(float(_setting("STARTUP_TIMEOUT_SEC", "120")) * 1e6)
	var size_name: String = _setting("STARTUP_SIZE", "normal")
	var new_world: bool = _setting("STARTUP_NEW_WORLD", "0") == "1"
	var seed_number: int = int(_setting("STARTUP_SEED", "777"))
	check(requested >= 1 and requested <= 30, "bounded scene measurement days")
	check(timeout_us > 0 and WorldGen.SIZES.has(size_name), "valid scene timeout and world size")
	if failures > 0: return failures
	WorldGen.gen_size = size_name
	var previous_params: Dictionary = Game.screen_params
	var existing_generation_us: int = 0
	var whole_start: int = Time.get_ticks_usec()
	if new_world:
		check(Game.has_method("new_game_begin") and Game.has_method("new_game_slice"), "new-world scene route has staged generation APIs")
		if failures > 0: return failures
		Game.screen_params = {"new_world": true, "seed": seed_number}
	else:
		var generation_begin: int = Time.get_ticks_usec()
		Game.new_game(seed_number)
		existing_generation_us = Time.get_ticks_usec() - generation_begin
		Game.world["presim"] = {"total": 120, "done": 0, "from": Game.day}
		Game.screen_params = {}
	HerdRaids.benchmark_fixed_steps = false
	var scene: Control = (load("res://ui/presim.tscn") as PackedScene).instantiate()
	var begin: int = Time.get_ticks_usec()
	tree.root.add_child(scene)
	var scene_ready_us: int = Time.get_ticks_usec() - begin
	var scene_ready: bool = scene.is_inside_tree() and scene.is_node_ready() and scene.get("bar") is ProgressBar and scene.get("map_view") is Control
	check(scene_ready, "presim scene attaches and finishes constructing its controls")
	if not scene_ready:
		Game.screen_params = previous_params
		scene.free()
		return failures
	var generation_intervals: Array = []; var generation_progress: Array = []
	var loading_seen: bool = false
	var staged_generation_us: int = 0
	if new_world:
		check(str(scene.get("phase")) == "generate", "new-world scene initially displays generation phase")
		var placeholder = scene.get("generation_placeholder")
		var label = scene.get("generation_label")
		loading_seen = placeholder is Control and placeholder.visible and label is Label and label.visible and not label.text.is_empty()
		check(loading_seen, "loading placeholder and label are visibly populated before generation")
		check(not bool(scene.get("generation_started")), "scene shows loading UI before starting generation")
		var generation_start: int = Time.get_ticks_usec()
		var last_generation_frame: int = generation_start
		var previous_progress: float = 0.0
		while str(scene.get("phase")) == "generate" and failures == 0:
			await tree.process_frame
			var now: int = Time.get_ticks_usec()
			generation_intervals.append(now - last_generation_frame)
			last_generation_frame = now
			check(now - whole_start < timeout_us, "new-world scene generation stays within timeout")
			if str(scene.get("phase")) == "generate":
				var bar = scene.get("bar")
				var progress: float = float(bar.value)
				check(progress >= previous_progress and progress >= 0.0 and progress <= 1.0, "loading progress is bounded and monotone")
				previous_progress = progress
				generation_progress.append(progress)
				check(placeholder.visible and label.visible, "loading controls stay visible while generation runs")
				check(Game.day == 0.0, "scene generation keeps campaign at day zero")
		staged_generation_us = Time.get_ticks_usec() - generation_start
		check(str(scene.get("phase")) == "build", "scene reaches build reveal after generation")
		var generation_state = scene.get("generation_state")
		check(generation_state is Dictionary and generation_state.is_empty(), "scene clears caller generation state")
		check(not placeholder.visible, "loading placeholder hides after generation")
		check(not Game.world.is_empty(), "new-world scene produced a world")
		Game.world["presim"] = {"total": 120, "done": 0, "from": Game.day}
	if failures == 0: scene.call("_skip_build")
	var intervals: Array = []; var boundaries: Array = []
	var previous_done: int = 0
	var last_frame: int = Time.get_ticks_usec()
	var history_start: int = last_frame
	while failures == 0 and int(Game.world["presim"]["done"]) < requested:
		await tree.process_frame
		var now: int = Time.get_ticks_usec()
		intervals.append(now - last_frame)
		last_frame = now
		var done: int = int(Game.world["presim"]["done"])
		if done > previous_done:
			boundaries.append({"day": done, "wall_seconds": (now - history_start) / 1e6})
			previous_done = done
		check(now - whole_start < timeout_us, "real scene advances within bounded timeout")
		check(done < 120 and not Game.world["presim"].get("finished", false), "measurement stops before production completion")
	var elapsed_us: int = Time.get_ticks_usec() - history_start
	# Stop before another frame. A partial history day is never a state checkpoint.
	scene.set_process(false)
	check(Game._save_task == -1, "scene measurement did not start a player autosave")
	var completed_days: int = int(Game.world.get("presim", {}).get("done", 0))
	check(completed_days >= requested, "real presim scene completes measured days")
	var worst: float = maxf(_percentile(intervals, 1.0), _percentile(generation_intervals, 1.0))
	var gate: float = float(_setting("STARTUP_MAX_FRAME_MS", "0"))
	if gate > 0: check(worst <= gate, "real-scene frame gap fits explicit responsiveness gate")
	var generation_cpu_us: int = existing_generation_us
	var generation_worst_us: int = 0
	var generation_slice_count: int = 0
	if new_world:
		generation_cpu_us = int(scene.get("generation_slice_total_usec"))
		generation_worst_us = int(scene.get("generation_slice_worst_usec"))
		generation_slice_count = int(scene.get("generation_slice_count"))
	write_json("startup-scene-timings.json", {"seed": Game.seed_value, "size": size_name, "new_world": new_world,
		"requested_days": requested, "completed_days": completed_days,
		"generation_seconds": (existing_generation_us + staged_generation_us) / 1e6,
		"generation_cpu_seconds": generation_cpu_us / 1e6, "generation_worst_slice_ms": generation_worst_us / 1000.0,
		"generation_slice_count": generation_slice_count, "scene_ready_ms": scene_ready_us / 1000.0,
		"generation_frame_gap_us": generation_intervals, "generation_progress": generation_progress,
		"loading_seen_before_generation": loading_seen, "measurement_wall_seconds": elapsed_us / 1e6,
		"total_scene_wall_seconds": (Time.get_ticks_usec() - whole_start) / 1e6,
		"frame_gap_us": intervals, "worst_frame_gap_ms": worst,
		"p95_frame_gap_ms": _percentile(intervals, 0.95), "completed_boundaries": boundaries, "failures": failures,
		"measurement_note": "Actual presim scene, ordinary raids, build reveal skipped after generation, stopped before finish/save/map. Headless gaps do not measure GPU/rendering."})
	Game.screen_params = previous_params
	scene.queue_free()
	await tree.process_frame
	print("STARTUP SCENE new_world=%s days=%d frames=%d wall=%.3fs worst_gap=%.3fms failures=%d" % [str(new_world), requested, intervals.size(), elapsed_us / 1e6, worst, failures])
	return failures
