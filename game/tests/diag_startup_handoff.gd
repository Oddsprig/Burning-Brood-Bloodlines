extends "res://tests/diag_startup_slices.gd"
## Production presim finish/autosave/map-request branch with a diagnostic one-day
## history. Normal world, seed777; STARTUP_OUTPUT required, timeout default120sec.
## Uses real staged generation and existing company/economy, with no input/window.
## Game.main stays null: test_ui_load_times separately exercises the actual map.

func run(tree: SceneTree) -> int:
	await tree.process_frame   # runner root must finish its own child-add/_ready pass
	output = OS.get_environment("STARTUP_OUTPUT")
	check(not output.is_empty(), "STARTUP_OUTPUT is provided")
	if failures > 0: return failures
	check(not FileAccess.file_exists(output.path_join("startup-handoff.json")), "handoff evidence directory is fresh")
	check(DirAccess.make_dir_recursive_absolute(output) == OK, "handoff output can be created")
	check(Game.main == null, "handoff diagnostic has no visible root/map host")
	check(Game.has_method("new_game_begin") and Game.has_method("new_game_slice"), "staged generation APIs exist")
	var timeout_us: int = int(float(_setting("STARTUP_TIMEOUT_SEC", "120")) * 1e6)
	check(timeout_us > 0, "positive handoff diagnostic timeout")
	if failures > 0: return failures
	WorldGen.gen_size = "normal"
	var previous_params: Dictionary = Game.screen_params
	Game.screen_params = {"new_world": true, "seed": 777}
	var map_requests: Array = [0]
	var on_screen: Callable = func(screen: String) -> void:
		if screen == "map": map_requests[0] += 1
	Game.screen_changed.connect(on_screen)
	var whole_start: int = Time.get_ticks_usec()
	var scene: Control = (load("res://ui/presim.tscn") as PackedScene).instantiate()
	tree.root.add_child(scene)
	var ready: bool = scene.is_inside_tree() and scene.is_node_ready() and scene.get("map_view") is Control
	check(ready, "production presim scene attaches and initializes")
	if ready:
		while str(scene.get("phase")) == "generate" and failures == 0:
			await tree.process_frame
			check(Time.get_ticks_usec() - whole_start < timeout_us, "generation completes within handoff timeout")
		check(str(scene.get("phase")) == "build", "production generation reaches build reveal")
		var generation_state = scene.get("generation_state")
		check(generation_state is Dictionary and generation_state.is_empty(), "generation caller state is cleared")
		check(Game.day == 0.0 and Game.seed_value == 777, "generated world is seed777 on day zero")
	var initial_ages: Dictionary = {}; var initial_births: Dictionary = {}
	for unit in Game.company:
		initial_ages[unit.uid] = unit.age
		initial_births[unit.uid] = unit.born
	var initial_gold: int = Game.gold
	var history_start: int = Time.get_ticks_usec()
	var gaps: Array = []
	var last_frame: int = history_start
	if failures == 0:
		# Test-only short length exercises the last-day branch. Normal player options
		# retain their one-year minimum, tested by the separate 120-day diagnostic.
		Game.world["presim"] = {"total": 1, "done": 0, "from": Game.day}
		scene.call("_skip_build")
		while not Game.world["presim"].get("finished", false) and failures == 0:
			await tree.process_frame
			var now: int = Time.get_ticks_usec()
			gaps.append(now - last_frame)
			last_frame = now
			check(now - whole_start < timeout_us, "history handoff completes within timeout")
	var history_us: int = Time.get_ticks_usec() - history_start
	if failures == 0:
		check(not scene.is_processing(), "completed production scene disables processing")
		var sim_state = scene.get("sim_state")
		check(sim_state is Dictionary and sim_state.is_empty(), "production finish has no partial simulation state")
		check(Game.world.get("work", []).is_empty(), "production finish drains daily work")
		check(Game.world["presim"].get("finished", false) and Game.world["presim"]["done"] == 1 and Game.day == 1.0, "production finish records the one diagnostic day")
		check(Game.gold == initial_gold and Game.company.size() == initial_ages.size(), "company roster and gold remain unchanged through startup")
		for unit in Game.company:
			check(initial_ages.has(unit.uid), "company member remains from the initial roster")
			if initial_ages.has(unit.uid):
				check(unit.age == initial_ages[unit.uid], "arrival age is restored")
				check(unit.born == float(initial_births[unit.uid]) + 1.0, "arrival birth date shifts by the completed history")
		check(Game.food_clock["last"] == Game.day, "company food clock begins at arrival")
		check(Game.world["party"]["safe_until"] == Game.day + 0.5, "original arrival safety window is retained")
		check(map_requests[0] == 1 and Game.screen_params.is_empty(), "production completion requests map once and clears new-world parameters")
		check(Game._save_task != -1, "production completion actually schedules async save")
	var save_begin: int = Time.get_ticks_usec()
	Game.wait_save()   # exact existing core API; joins the real isolated async writer
	var save_wait_us: int = Time.get_ticks_usec() - save_begin
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH)) if FileAccess.file_exists(Game.SAVE_PATH) else null
	check(saved is Dictionary and not FileAccess.file_exists(Game.SAVE_PATH + ".tmp"), "async save lands as complete parseable JSON with no temporary file")
	if saved is Dictionary:
		check(saved.get("day") == 1.0 and saved.get("gold") == initial_gold, "async save contains arrival day and unchanged gold")
		var presim: Dictionary = saved.get("world", {}).get("presim", {})
		check(presim.get("finished", false) and presim.get("total") == 1 and presim.get("done") == 1, "async save contains completed diagnostic history")
		check(saved.get("food_clock", {}).get("last") == 1.0, "async save contains arrival food clock")
		check(saved.get("company", []).size() == initial_ages.size(), "async save contains the complete company roster")
		check(saved.get("world", {}).get("work", []).is_empty(), "async save contains no pending daily work")
		check(saved.get("world", {}).get("party", {}).get("safe_until") == 1.5, "async save retains the arrival safety window")
		for unit in saved.get("company", []):
			var uid: int = int(unit.get("uid", -1))
			check(initial_ages.has(uid), "saved company belongs to the original roster")
			if initial_ages.has(uid): check(unit.get("age") == initial_ages[uid], "saved company retains its arrival age")
	await tree.process_frame
	check(map_requests[0] == 1 and Game.day == 1.0, "extra frame neither repeats map handoff nor advances history")
	check(Game._save_task == -1, "async save writer is fully joined")
	check(Time.get_ticks_usec() - whole_start < timeout_us, "complete handoff and save remain within timeout")
	write_json("startup-handoff.json", {"seed": 777, "size": "normal", "diagnostic_history_days": 1,
		"map_request_count": map_requests[0], "history_handoff_seconds": history_us / 1e6,
		"async_save_wait_seconds": save_wait_us / 1e6, "total_seconds": (Time.get_ticks_usec() - whole_start) / 1e6,
		"frame_gap_us": gaps, "worst_history_frame_gap_ms": _percentile(gaps, 1.0),
		"save_bytes": FileAccess.get_file_as_string(Game.SAVE_PATH).length() if saved is Dictionary else 0,
		"failures": failures, "measurement_note": "Test-only one-day history; real production generation/finish/async writer/map request. No map host; actual map covered by test_ui_load_times."})
	Game.screen_changed.disconnect(on_screen)
	Game.screen_params = previous_params
	scene.set_process(false)
	scene.queue_free()
	await tree.process_frame
	print("STARTUP HANDOFF map_requests=%d day=%.0f save_wait=%.3fs failures=%d" % [map_requests[0], Game.day, save_wait_us / 1e6, failures])
	return failures
