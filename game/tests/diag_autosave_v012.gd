extends RefCounted
## Fresh-world native autosave costs; same diagnostic runs against the frozen release.
var failures := 0
var checks := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL autosave measurement: ", why)

func run(tree: SceneTree) -> int:
	var report := ""
	var compare := ""
	var world_size := "normal"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=").replace("\\", "/").simplify_path()
		elif arg.begins_with("--compare="): compare = arg.trim_prefix("--compare=").replace("\\", "/").simplify_path()
		elif arg.begins_with("--size="): world_size = arg.trim_prefix("--size=")
	check(report.begins_with("C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"), "private report")
	check(world_size in ["normal", "large"], "bounded native world")
	if failures: return failures
	if DisplayServer.get_name() != "headless":
		tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
		tree.root.position = Vector2i(-20000, -20000)
		tree.root.size = Vector2i(2560, 1440)
		tree.root.visible = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 60
	WorldGen.gen_size = world_size
	CampaignWorld.presim_span_days = 1
	var generated := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	while not Game.new_game_slice(generation, 4000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 4000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	if Game.has_method("new_game_finalize"): Game.new_game_finalize()
	var choices := Dynasty.choices(Game)
	check(Game.day == 1.0 and not choices.is_empty(), "fresh one history day")
	if not choices.is_empty(): check(Dynasty.select_city(Game, choices[0]["town_id"]), "native house selection")
	Game.goto("map")
	var host = load("res://main.gd").new()
	tree.root.add_child(host)
	Game.goto("map")
	for settling in 8: await tree.process_frame
	var generation_ms := float(Time.get_ticks_usec() - generated) / 1000.0
	var original_rng := Game.rng.state
	var original_unit := Unit._next_uid
	var original_item := Item._next_uid
	var times := []
	var ordered_sha := ""
	var disk_sha := ""
	var bytes := 0
	for repetition in 3:
		var start := Time.get_ticks_usec()
		var snapshot := Game._save_tree()
		times.append(float(Time.get_ticks_usec()-start)/1000.0)
		var encoded := JSON.stringify(snapshot, "", false, true)
		var digest := encoded.sha256_text()
		if repetition == 0:
			ordered_sha = digest; bytes = encoded.to_utf8_buffer().size()
			disk_sha = JSON.stringify(snapshot).sha256_text()
		else: check(digest == ordered_sha, "same ordered complete snapshot each capture")
		snapshot.clear()
		encoded = ""
		await tree.process_frame
	var begin := Time.get_ticks_usec()
	Game.save_game_async()
	var request_ms := float(Time.get_ticks_usec() - begin)/1000.0
	var frame_ms := []
	var sample_start := begin
	var previous := sample_start
	var camera_checked := false
	var capture_frames := 0
	while Time.get_ticks_usec() - sample_start < 3000000 or Game._save_task != -1 or Game._save_pending or (Game.has_method("save_stats") and Game.save_stats().get("capturing",false)):
		await tree.process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous)/1000.0)
		previous = now
		if Game.has_method("save_stats") and Game.save_stats().get("capturing",false):
			capture_frames += 1
			if not camera_checked:
				var map: Node = host.current
				var position: Vector2 = map.cam.position
				var gesture := InputEventPanGesture.new()
				gesture.delta = Vector2(3,0)
				map._unhandled_input(gesture)
				check(map.cam.position != position,"native camera responds during capture")
				var time := Game.day
				var target: Vector2 = Game.world["party"]["target"]
				map._tap(Game.world["party"]["pos"] + Vector2(100,100))
				Game.advance_time(0.1,false,0,4000)
				check(Game.day == time and Game.world["party"]["target"] == target,"time and travel mutations held during capture")
				camera_checked = true
		# A default Large plain save is about132MB. Bound capture + encoding +
		# worker-side release separately from the150ms rendered-frame gate.
		if Time.get_ticks_usec()-sample_start >= 25000000:
			check(false,"writer settles within bounded window")
			break
	Game.wait_save()
	var saved := FileAccess.get_file_as_string(Game.SAVE_PATH)
	var parsed = JSON.parse_string(saved)
	check(parsed is Dictionary, "complete JSON on disk")
	if parsed is Dictionary: check(saved.sha256_text() == disk_sha, "exact complete native JSON bytes on disk")
	check(Game.rng.state == original_rng and Unit._next_uid == original_unit and Item._next_uid == original_item, "capture and worker preserve RNG and identity counters")
	check(Game._save_task == -1 and not Game._save_pending, "snapshot and dirty request drained")
	if Game.has_method("save_stats"):
		check(camera_checked and capture_frames > 1,"real world uses visible multi-frame consistent capture")
		check(frame_ms.max() < 150.0,"no autosave frame exceeds150ms recovery probe")
	frame_ms.sort()
	var out := {"size":world_size,"history_days":1,"seed":777,"generation_ms":generation_ms,
		"capture_ms":times,"request_ms":request_ms,"ordered_sha256":ordered_sha,"snapshot_utf8_bytes":bytes,"disk_sha256":disk_sha,
		"writer_window_frames":frame_ms.size(),"frame_p95_ms":frame_ms[int(frame_ms.size()*0.95)],"frame_worst_ms":frame_ms[-1],
		"capture_rendered_frames":capture_frames,"camera_during_capture":camera_checked,
		"engine_tracked_bytes":OS.get_static_memory_usage(),"engine_peak_bytes":OS.get_static_memory_peak_usage(),
		"next_unit_uid":Unit._next_uid,"next_item_uid":Item._next_uid,"rng_state":str(Game.rng.state)}
	if Game.has_method("save_stats"): out["save_stats"] = Game.save_stats()
	if compare != "":
		var old = JSON.parse_string(FileAccess.get_file_as_string(compare))
		check(old is Dictionary and old.get("failures",-1) == 0, "frozen baseline report")
		if old is Dictionary:
			for key in ["ordered_sha256","snapshot_utf8_bytes","next_unit_uid","next_item_uid","rng_state"]:
				check(old[key] == out[key], "complete fresh native state matches v011 " + key)
	out["checks"] = checks; out["failures"] = failures
	var file := FileAccess.open(report, FileAccess.WRITE)
	check(file != null, "report writable")
	if file != null: file.store_string(JSON.stringify(out,"  ",true,true)); file.close()
	print("autosave ", JSON.stringify(out))
	host.queue_free()
	Game.main = null
	await tree.process_frame
	return failures
