extends RefCounted
## Fresh current-build Normal/one-day world. No save is imported or loaded.
func run(tree: SceneTree) -> int:
	await tree.process_frame
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	var frames := 600
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="): frames = clampi(int(argument.substr(9)), 1, 1200)
	var started := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	var slices := 0
	while not Game.new_game_slice(generation, 12000):
		slices += 1
		await tree.process_frame
	print("FRESH generation_ms=", (Time.get_ticks_usec() - started) / 1000.0, " slices=", slices)
	var history := {}
	started = Time.get_ticks_usec()
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 12000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	var chosen := false
	for tid in Game.world["towns"]:
		if Dynasty.select_city(Game, String(tid)): chosen = true; break
	if not chosen or Game.day != 1.0 or not Game.world.get("work", []).is_empty():
		printerr("FRESH one-day startup or real ruling-family selection failed")
		return 1
	print("FRESH history_ms=", (Time.get_ticks_usec() - started) / 1000.0, " day=", Game.day, " towns=", Game.world["towns"].size(), " bands=", Game.world["warbands"].size(), " company=", Game.company.size())
	Game.world["party"]["safe_until"] = Game.day + 100.0
	Game.world["party"]["waiting"] = true
	Game.goto("map")
	var map = load("res://campaign/world_map.tscn").instantiate()
	tree.root.add_child(map)
	map.set_process(false); map.speed_mult = 4
	if map.cam == null or map.enc_panel == null or map.ruler_card == null:
		printerr("FRESH actual map did not initialize")
		map.queue_free()
		return 2
	var tracker := tree.root.get_node_or_null("Perf")
	if tracker != null:
		var panel = load("res://ui/performance_panel.gd").new()
		panel.setup(tracker)
		var layer := CanvasLayer.new(); map.add_child(layer); layer.add_child(panel)
	await tree.process_frame
	var initial_memory := OS.get_static_memory_usage()
	var initial_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var initial_day := Game.day
	var total_us := 0
	var worst_us := 0
	var queue_peak := 0
	var times: Array[int] = []
	for frame in frames:
		started = Time.get_ticks_usec()
		map._process(1.0 / 60.0)
		var cost := Time.get_ticks_usec() - started
		total_us += cost; worst_us = maxi(worst_us, cost); times.append(cost)
		queue_peak = maxi(queue_peak, Game.world.get("work", []).size())
		if frame % 120 == 119:
			print("FRESH frame=", frame + 1, " day=", Game.day, " queue=", Game.world.get("work", []).size(), " memory_mib=", OS.get_static_memory_usage() / 1048576.0, " objects=", int(Performance.get_monitor(Performance.OBJECT_COUNT)))
		await tree.process_frame
	times.sort()
	print("FRESH frames=", frames, " mean_map_ms=", total_us / float(frames) / 1000.0, " p95_map_ms=", times[clampi(ceili(frames * 0.95) - 1, 0, frames - 1)] / 1000.0, " worst_map_ms=", worst_us / 1000.0, " calendar_days=", Game.day - initial_day, " queue_peak=", queue_peak, " pending=", Game.world.get("work", []).size(), " memory_change_mib=", (OS.get_static_memory_usage() - initial_memory) / 1048576.0, " object_change=", int(Performance.get_monitor(Performance.OBJECT_COUNT)) - initial_objects)
	if tracker != null: print("FRESH timings=", JSON.stringify(tracker.snapshot()["jobs"]))
	# A player stopping at midnight must let retained jobs settle without
	# another date/wage advance. A delayed callback must not request catch-up.
	var failures := 0
	Game.world["party"]["waiting"] = false
	var paused_day := Game.day
	var settle_frames := 0
	while not Game.world.get("work", []).is_empty() and settle_frames < 1000:
		map._process(1.0 / 60.0); settle_frames += 1
	if not Game.world.get("work", []).is_empty() or Game.day != paused_day:
		failures += 1; printerr("FAIL FRESH paused work/calendar backpressure")
	Game.world["party"]["waiting"] = true
	map._process(2.0)
	if Game.day > paused_day + 0.080001:
		failures += 1; printerr("FAIL FRESH stalled-frame catch-up cap")
	Game.world["party"]["waiting"] = false
	print("FRESH scheduling_checks=2 failures=", failures, " paused_settle_frames=", settle_frames, " delayed_callback_days=", Game.day - paused_day)
	map.queue_free()
	await tree.process_frame
	return failures
