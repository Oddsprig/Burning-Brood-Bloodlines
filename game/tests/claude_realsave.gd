extends RefCounted
## Real played-campaign performance: loads a copy of a player's save (--save=<path>) through main.tscn and measures
## load, memory, objects, screen opens (incl. Dragons > All holdings), frame times while idle in menus and scrolling,
## and autosave cost/size.
var main: Node = null
func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n: await tree.process_frame
func mem() -> float: return snappedf(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0, 0.1)
func objs() -> int: return int(Performance.get_monitor(Performance.OBJECT_COUNT))
func measure(tree: SceneTree, secs: float) -> Dictionary:
	var times: Array = []
	var last := Time.get_ticks_usec(); var start := last
	while float(Time.get_ticks_usec() - start) / 1e6 < secs:
		await tree.process_frame
		var now := Time.get_ticks_usec(); times.append(float(now - last) / 1000.0); last = now
	times.sort()
	var tot := 0.0
	for x in times: tot += x
	return {"fps": snappedf(1000.0 * times.size() / tot, 0.1), "p50": snappedf(times[times.size() / 2], 0.1), "p95": snappedf(times[int(times.size() * 0.95)], 0.1), "worst": snappedf(times[-1], 0.1)}
func run(tree: SceneTree) -> int:
	var path := ""
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--save="): path = a.trim_prefix("--save=")
		if a.begins_with("--out="): out = a.trim_prefix("--out=")
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	var r := {"save_bytes": FileAccess.get_file_as_bytes(path).size() if path != "" else 0, "mem_before": mem()}
	Game.SAVE_PATH = path
	var t := Time.get_ticks_usec()
	var ok := Game.load_game()
	r["load_ms"] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["loaded"] = ok
	var units := 0
	for wb in Game.world.get("warbands", {}).values(): units += (wb.get("units", []) as Array).size()
	r["warband_units"] = units
	r["towns"] = Game.world.get("towns", {}).size()
	r["dragons"] = Game.world.get("dragons", {}).get("records", {}).size()
	r["mem_after_load"] = mem(); r["objects_after_load"] = objs()
	if Dynasty.selected(Game).is_empty():
		var pick: Dictionary = Dynasty.choices(Game)[0]
		HouseOnboarding.begin(Game, str(pick["town_id"]), str(pick["household_uid"]))
	Game.goto("map"); await frames(tree, 10)
	r["map_idle"] = await measure(tree, 6.0)
	var opens := {}
	for s in ["house", "court", "dragons", "muster", "politics", "population", "map"]:
		t = Time.get_ticks_usec(); Game.goto(s, {"back": "map"}); await frames(tree, 2)
		opens[s] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["open_ms"] = opens
	Game.goto("dragons", {"back": "map", "holdings": "all"}); 
	t = Time.get_ticks_usec(); await frames(tree, 2)
	r["dragons_all_open_ms"] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["dragons_all_idle"] = await measure(tree, 4.0)
	if out != "": tree.root.get_texture().get_image().save_png(out.path_join("dragons_all.png"))
	Game.goto("map"); await frames(tree, 5)
	t = Time.get_ticks_usec()
	Game.SAVE_PATH = OS.get_user_data_dir().path_join("realsave_test.json")
	Game.save_game(); Game.wait_save()
	r["save_ms"] = snappedf(float(Time.get_ticks_usec() - t) / 1000.0, 1)
	r["new_save_bytes"] = FileAccess.get_file_as_bytes(Game.SAVE_PATH).size()
	t = Time.get_ticks_usec()
	Game.save_game_async(); 
	var worst := 0.0; var last := Time.get_ticks_usec()
	for i in 240:
		await tree.process_frame
		var now := Time.get_ticks_usec(); worst = maxf(worst, float(now - last) / 1000.0); last = now
	r["autosave_worst_frame_ms"] = snappedf(worst, 1)
	r["mem_end"] = mem(); r["objects_end"] = objs()
	DirAccess.remove_absolute(Game.SAVE_PATH)
	print("REALSAVE ", JSON.stringify(r))
	return 0
