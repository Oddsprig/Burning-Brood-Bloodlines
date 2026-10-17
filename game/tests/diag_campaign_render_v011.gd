extends RefCounted
## Actual rendered map frames in a private fresh one-day campaign.
## The safe-until guard only prevents an encounter from interrupting measurement.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
var checks := 0
var fails := 0

class MeasuredMap:
	extends "res://campaign/world_map.gd"
	var frame_rows: Array = []
	var recording := false
	var started_us := 0
	func _process(delta: float) -> void:
		if not recording:
			super._process(delta)
			return
		var counts := {}
		for label in Perf._labels:
			counts[label] = Perf._labels[label]["calls"]
		var before := float(Game.day)
		var travelling := CampaignWorld.is_travelling(Game)
		var waiting := bool(Game.world.get("party", {}).get("waiting", false))
		var head: Array = Game.world.get("work", [])
		var kind := String(head[0][0]) if not head.is_empty() else ""
		var begin := Time.get_ticks_usec()
		super._process(delta)
		var cpu := Time.get_ticks_usec() - begin
		var changed := {}
		for label in Perf._labels:
			var stat: Dictionary = Perf._labels[label]
			if int(stat["calls"]) > int(counts.get(label, 0)):
				changed[label] = [int(stat["calls"]) - int(counts.get(label, 0)), int(stat["latest"])]
		frame_rows.append({"at_s":float(begin - started_us) / 1000000.0,
			"delta_s":delta,"map_us":cpu,"day_before":before,"day_after":Game.day,
			"travelling":travelling,"waiting":waiting,"settling":not kind.is_empty(),
			"job_head":kind,"pending":Game.world.get("work", []).size(),"labels":changed})

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL campaign render: ", message)

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, maxi(0, ceili(sorted.size() * fraction) - 1))])

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var seconds := 22.0
	var report_path := ""
	var enforce := false
	var travel := false
	var wide := false
	var interact := false
	var size := "normal"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--report="): report_path = arg.trim_prefix("--report=").replace("\\", "/").simplify_path()
		elif arg == "--enforce-gate": enforce = true
		elif arg == "--travel": travel = true
		elif arg == "--wide": wide = true
		elif arg == "--interact": interact = true
		elif arg.begins_with("--size="): size = arg.trim_prefix("--size=")
	check(seconds >= 18.0 and seconds <= 35.0, "bounded actual-frame window")
	check(size in ["normal", "large"], "supported native world size")
	check(report_path.to_lower().begins_with(PRIVATE_WORK.to_lower()), "private report path")
	check(DisplayServer.get_name() != "headless", "actual display server")
	if fails > 0: return fails
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = Vector2i(2560, 1440)
	tree.root.visible = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	var generated := Time.get_ticks_usec()
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
	check(Game.day == 1.0 and not choices.is_empty(), "fresh exactly one-day history")
	if not choices.is_empty(): check(Dynasty.select_city(Game, choices[0]["town_id"]), "native house selected")
	check(Game.world.get("work", []).is_empty(), "startup work settled")
	var world_ms := float(Time.get_ticks_usec() - generated) / 1000.0
	print("campaign fixture ready: %.1fms day%.2f towns%d bands%d" % [world_ms,Game.day,Game.world["towns"].size(),Game.world["warbands"].size()])
	Game.world["party"]["safe_until"] = Game.day + 100.0
	Game.goto("map")
	var map := MeasuredMap.new()
	tree.root.add_child(map)
	var layer := CanvasLayer.new()
	layer.layer = 100
	tree.root.add_child(layer)
	var panel := PerformancePanel.new()
	panel.setup(Perf)
	layer.add_child(panel)
	map.speed_mult = 1
	if wide:
		map.cam.zoom = Vector2(0.57,0.57)
		map.terrain.set_zoom(0.57)
	# Settle cold setup before the measured window; the campaign remains paused.
	var warm := Time.get_ticks_usec()
	while Time.get_ticks_usec() - warm < 2000000: await RenderingServer.frame_post_draw
	TownEcon.prof_on = true
	TownEcon.prof.clear()
	CampaignWorld.job_total.clear()
	CampaignWorld.job_worst.clear()
	CampaignWorld.daily_parts.clear()
	CampaignWorld.daily_total.clear()
	Perf._labels.clear()
	Perf._overall.clear()
	Perf.mark_open()
	var destination := Vector2.ZERO
	if travel:
		# Travel away from the selected town for the full measurement window.
		# Use an actual reachable map corner; native pathfinding snaps to land.
		var origin: Vector2 = Game.world["party"]["pos"]
		var extent := Vector2(WorldGen.W, WorldGen.H) * WorldGen.CELL - Vector2(100,100)
		var corners := [Vector2(100,100),Vector2(extent.x,100),Vector2(100,extent.y),extent]
		corners.sort_custom(func(a: Vector2, b: Vector2): return origin.distance_squared_to(a) > origin.distance_squared_to(b))
		for corner: Vector2 in corners:
			if CampaignWorld.set_travel(Game, corner):
				destination = Game.world["party"]["target"]
				break
		check(CampaignWorld.is_travelling(Game), "native long travel order accepted")
	else: Game.world["party"]["waiting"] = true
	var initial_day := float(Game.day)
	var initial_memory := OS.get_static_memory_usage()
	map.started_us = Time.get_ticks_usec()
	map.recording = true
	var previous := map.started_us
	var frame_ms := []
	var draw_peak := 0
	var samples := []
	var pan_events := 0
	while float(Time.get_ticks_usec() - map.started_us) / 1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - previous) / 1000.0)
		previous = now
		draw_peak = maxi(draw_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		var elapsed := float(now - map.started_us) / 1000000.0
		if interact and pan_events == 0 and elapsed >= 4.0:
			map.cam.position += Vector2(192,-64)
			map.follow = false
			pan_events += 1
		elif interact and pan_events == 1 and elapsed >= 12.0:
			map._on_center()
			pan_events += 1
		if samples.size() < 8 and elapsed >= float(samples.size() + 1) * 3.0:
			samples.append({"at_s":elapsed,"day":Game.day,"memory_bytes":OS.get_static_memory_usage(),
				"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"pending":Game.world.get("work", []).size()})
	map.recording = false
	map.set_process(false)
	var measured_s := float(Time.get_ticks_usec() - map.started_us) / 1000000.0
	var fps := float(frame_ms.size()) / measured_s
	var p95 := percentile(frame_ms, 0.95)
	var worst := percentile(frame_ms, 1.0)
	var midnights := floori(Game.day) - floori(initial_day)
	var active_s := 0.0
	var travel_s := 0.0
	var paused_s := 0.0
	for row: Dictionary in map.frame_rows:
		var duration := float(row["delta_s"])
		if row["travelling"]: travel_s += duration
		if row["travelling"] or row["waiting"] or row["settling"]: active_s += duration
		else: paused_s += duration
	var active_ratio := active_s / maxf(active_s + paused_s, 0.001)
	check(frame_ms.size() > 5 and draw_peak > 0, "rendered frames and draw calls recorded")
	check(midnights >= 2, "at least two actual midnight transitions")
	check(active_ratio >= 0.95, "campaign active throughout actual-frame window")
	var gate := fps >= 30.0 and p95 <= 50.0 and worst <= 150.0
	if enforce: check(gate, "rendered recovery floor30FPS/p95<=50ms/no frame>150ms")
	if interact: check(pan_events == 2, "rendered pan and native recenter during active travel")
	# Exercise the real menu without host input or a live player save. Its
	# separate pause/open cost is not counted as campaign-frame performance.
	var paused_day := Game.day
	var paused_rng := str(Game.rng.state)
	var account_text := map.lbl_gold.text
	map._layout_hud()
	map._layout_hud()
	check(map.lbl_gold.text == account_text, "repeated native layout keeps account text exact")
	var menu_begin := Time.get_ticks_usec()
	var settings = load("res://ui/settings.tscn").instantiate()
	settings.overlay = true
	layer.add_child(settings)
	var menu_open_us := Time.get_ticks_usec() - menu_begin
	await RenderingServer.frame_post_draw
	check(is_instance_valid(settings.list) and settings.list.get_child_count() > 0, "actual Settings rows rendered during pause")
	settings._back()
	await RenderingServer.frame_post_draw
	check(not is_instance_valid(settings), "actual Settings Back closes overlay")
	check(Game.day == paused_day and str(Game.rng.state) == paused_rng, "paused menu and layout preserve calendar and RNG")
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"seed":777,
		"fresh_world":true,"size":size,"history_days":1,"world_ms":world_ms,"resolution":[2560,1440],
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"max_fps":60,"performance_panel":true,
		"mode":"travel" if travel else "wait","zoom":map.cam.zoom.x,"speed":1,"measured_s":measured_s,
		"frames":frame_ms.size(),"fps":fps,"p50_ms":percentile(frame_ms,0.5),"p95_ms":p95,
		"p99_ms":percentile(frame_ms,0.99),"worst_ms":worst,"frame_ms":frame_ms,
		"initial_day":initial_day,"end_day":Game.day,"midnights":midnights,"pending":Game.world.get("work", []).size(),
		"destination":[destination.x,destination.y],"active_ratio":active_ratio,"active_s":active_s,
		"travel_s":travel_s,"paused_s":paused_s,"pan_events":pan_events,"settings_open_us":menu_open_us,
		"memory_change_bytes":OS.get_static_memory_usage()-initial_memory,"draw_calls_peak":draw_peak,
		"samples":samples,"map_frames":map.frame_rows,"job_worst_us":CampaignWorld.job_worst,
		"job_total_us_calls":CampaignWorld.job_total,"midnight_worst_us":CampaignWorld.daily_parts,
		"midnight_total_us":CampaignWorld.daily_total,"town_phase_us":TownEcon.prof,
		"diagnostics":Perf.snapshot(),"recovery_gate":gate}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	check(file != null, "report opens")
	report["checks"] = checks
	report["fails"] = fails
	if file != null:
		file.store_string(JSON.stringify(report,"  ",true,true))
		file.close()
	print("campaign %s: %.2fFPS p95 %.2fms worst %.2fms day%.3f midnights%d gate%s" % [report["mode"],fps,p95,worst,Game.day,midnights,str(gate)])
	map.queue_free()
	layer.queue_free()
	await tree.process_frame
	TownEcon.prof_on = false
	Game.company.clear()
	Game.world.clear()
	return fails
