extends RefCounted
## Honest performance benchmark through main.tscn at a stated window size (default 2560x1440), vsync off, 60 FPS cap:
##   battle: 200 raised residents + bonded marching dragons vs ~200 real enemy troops, real-time 1x for --secs
##   map: travel across the map with real midnights for --map-secs
##   screens: repeated transitions (map/house/dragons/town/army/records) with static memory per cycle
## -- --test=res://tests/claude_bench.gd [--size=WxH] [--secs=60] [--map-secs=40] [--speed=1]
var main: Node = null

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n: await tree.process_frame

static func stats(times: Array) -> Dictionary:
	if times.is_empty(): return {}
	var s := times.duplicate(); s.sort()
	var total := 0.0
	var over33 := 0
	var over50 := 0
	for t in s:
		total += t
		if t > 33.4: over33 += 1
		if t > 50.0: over50 += 1
	return {"frames": s.size(), "avg_fps": snappedf(1000.0 * s.size() / total, 0.01), "avg_ms": snappedf(total / s.size(), 0.01),
		"p50_ms": snappedf(s[s.size() / 2], 0.01), "p95_ms": snappedf(s[int(s.size() * 0.95)], 0.01), "p99_ms": snappedf(s[int(s.size() * 0.99)], 0.01),
		"worst_ms": snappedf(s[-1], 0.01), "frames_over_33ms": over33, "frames_over_50ms": over50, "seconds": snappedf(total / 1000.0, 0.1)}

func labels(top: int = 14) -> Array:
	var rows: Array = []
	for k in Perf._labels:
		var st: Dictionary = Perf._labels[k]
		rows.append([str(k), int(st["calls"]), snappedf(float(st["mean"]) / 1000.0, 0.001), snappedf(float(st["peak"]) / 1000.0, 0.01), snappedf(float(st["mean"]) * int(st["calls"]) / 1e6, 0.001)])
	rows.sort_custom(func(a, b): return a[4] > b[4])
	return rows.slice(0, top)

func mem() -> float:
	return snappedf(float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0, 0.1)

func run(tree: SceneTree) -> int:
	var size := Vector2i(2560, 1440)
	var secs := 60.0
	var map_secs := 40.0
	var speed := 1.0
	var pad := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x"); size = Vector2i(int(p[0]), int(p[1]))
		elif a.begins_with("--secs="): secs = float(a.trim_prefix("--secs="))
		elif a.begins_with("--map-secs="): map_secs = float(a.trim_prefix("--map-secs="))
		elif a.begins_with("--speed="): speed = float(a.trim_prefix("--speed="))
		elif a.begins_with("--pad-bands="): pad = int(a.trim_prefix("--pad-bands="))
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	var report := {"size": "%dx%d" % [size.x, size.y], "renderer": "gl_compatibility", "gpu": RenderingServer.get_video_adapter_name(), "mem_start_mib": mem()}
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var t0 := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	while not Game.new_game_slice(generation, 8000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	report["world_generation_s"] = snappedf(float(Time.get_ticks_usec() - t0) / 1e6, 0.01)
	var tid := "t21"
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult": continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]): continue
		if HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false):
			tid = str(owner["town_id"]); break
	Game.goto("map"); await frames(tree, 5)
	Game.location = tid
	Mobilization.fund(Game, int(floor(float(Feudal._payer(Game).get("purse", 0.0)) * 0.8)))
	var q := Mobilization.quote(Game, tid, 200)
	Mobilization.muster(Game, tid, 200, q.get("review", {}))
	for dragon: Dictionary in Dragons.records(Game):
		var uid := str(dragon["id"])
		if dragon.get("stage", "") != "adult" or str(dragon.get("location_town_id", "")) != tid: continue
		var c: Array = DragonBond.candidates(Game, uid)
		if c.is_empty(): continue
		DragonBond.bind(Game, uid, str(c[0]["person_uid"]), DragonBond.bind_preview(Game, uid, str(c[0]["person_uid"])))
		Warfare.set_march(Game, uid, true)
	report["player_troops"] = Game.deployed_units().size()
	report["dragons"] = DragonCombat.battle_units(Game).size()
	# ---- screens: open time and memory over repeated transitions
	var quick := "--battle-only" in OS.get_cmdline_user_args()
	var opens := {}
	var mem_cycle: Array = []
	for cycle in (0 if quick else 6):
		for s in ["house", "dragons", "muster", "politics", "population", "map"]:
			var ts := Time.get_ticks_usec()
			Game.goto(s, {"back": "map"}); await frames(tree, 2)
			var ms := float(Time.get_ticks_usec() - ts) / 1000.0
			opens[s] = maxf(float(opens.get(s, 0.0)), ms) if cycle > 0 else ms
		mem_cycle.append(mem())
	report["screen_open_ms_first"] = opens
	report["screen_cycle_static_mib"] = mem_cycle
	# ---- battle
	var mine := Warfare.player_faction(Game)
	var enemy: Array = []
	var keys: Array = Game.world["warbands"].keys(); keys.sort()
	for key in keys:
		var band: Dictionary = Game.world["warbands"][key]
		if str(band.get("faction", "")) == mine or not Army.is_people_band(band) or Monsters.suspended_band(band): continue
		for u in band.get("units", []):
			if u is Unit and not u.dead and enemy.size() < 200: enemy.append(u)
		if enemy.size() >= 200: break
	report["enemy_troops"] = enemy.size()
	Game.start_battle({"enemy": enemy, "allies": [], "seed": 4040, "terrain": "grassland", "map": "large"})
	await frames(tree, 20)
	Perf._labels.clear(); Perf._overall = {}
	var b: Node = main.current
	b.set_speed(speed)
	var times: Array = []
	var last := Time.get_ticks_usec()
	var start := last
	var proc := 0.0
	var draws := 0.0
	var objs := 0.0
	while float(Time.get_ticks_usec() - start) / 1e6 < secs and main.current == b:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0); last = now
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var breaths := 0
	for e in b.sim.events:
		if str(e.get("type", "")) == "breath": breaths += 1
	report["battle"] = stats(times)
	report["battle"]["speed"] = speed
	var counts := {}
	var stack: Array = [b]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			var parent_name := str(n.get_parent().get_script().get_global_name()) if n.get_parent() != null and n.get_parent().get_script() != null else "-"
			var k := "%s<%s" % [n.get_class() if n.get_script() == null else str(n.get_script().get_global_name()), parent_name]
			counts[k] = int(counts.get(k, 0)) + 1
		stack.append_array(n.get_children())
	var crow: Array = []
	for k in counts: crow.append([k, counts[k]])
	crow.sort_custom(func(x, y): return x[1] > y[1])
	report["battle_canvas_items"] = crow.slice(0, 12)
	report["battle"]["process_ms_avg"] = snappedf(proc / maxf(1, times.size()), 0.01)
	report["battle"]["draw_calls_avg"] = int(draws / maxf(1, times.size()))
	report["battle"]["objects_avg"] = int(objs / maxf(1, times.size()))
	report["battle"]["ticks"] = b.sim.tick
	report["battle"]["fighters"] = b.sim.fighters.size()
	report["battle"]["breaths"] = breaths
	report["battle"]["over"] = b.sim.is_over()
	report["battle_labels_name_calls_meanms_peakms_totals"] = labels()
	report["battle_frame_script_ms"] = [snappedf(float(Perf._overall.get("mean", 0)) / 1000.0, 0.01), snappedf(float(Perf._overall.get("peak", 0)) / 1000.0, 0.01)]
	report["mem_after_battle_mib"] = mem()
	# Leave without finishing (a benchmark must not alter the world); return to the map.
	b._journal_transferred = false
	Game.pending_battle = {}
	Game.goto("map"); await frames(tree, 10)
	report["mem_after_battle_exit_mib"] = mem()
	# ---- optional: every AI field army filled to --pad-bands (late-campaign sizes)
	if pad > 0:
		var prng := RandomNumberGenerator.new(); prng.seed = 991
		var bands := 0; var units := 0
		for wid in Game.world["warbands"]:
			var wb: Dictionary = Game.world["warbands"][wid]
			if not Army.is_field(wb) or not Army.is_people_band(wb): continue
			var need := pad - (wb["units"] as Array).size()
			if need <= 0: continue
			var extra: Array = Factory.make_warband(prng, str(wb["faction"]), need)
			for u in extra: u.home_town = str(wb.get("home", ""))
			(wb["units"] as Array).append_array(extra); bands += 1
		for wb2 in Game.world["warbands"].values(): units += (wb2["units"] as Array).size()
		report["padded_bands"] = bands; report["warband_units"] = units
		print("bench: padded ", bands, " field armies; ", units, " units on the map")
	# ---- map travel with real midnights
	var far := ""
	var bestd := 0.0
	for t2 in Game.world["towns"]:
		var d: float = (Game.world["towns"][t2]["pos"] as Vector2).distance_to(Game.world["party"]["pos"])
		if d > bestd and CampaignWorld.set_travel(Game, Game.world["towns"][t2]["pos"], str(t2)): bestd = d; far = str(t2)
	CampaignWorld.set_travel(Game, Game.world["towns"][far]["pos"], far)
	var map: Node = main.current
	if "speed_mult" in map: map.speed_mult = 4.0
	var day0 := Game.day
	Perf._labels.clear()
	times = []
	last = Time.get_ticks_usec(); start = last
	while float(Time.get_ticks_usec() - start) / 1e6 < (0.0 if quick else map_secs):
		await tree.process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0); last = now
		if Game.world.get("encounter", "") != "":
			CampaignWorld.retreat(Game, Game.world["encounter"])
			CampaignWorld.set_travel(Game, Game.world["towns"][far]["pos"], far)
	report["map"] = stats(times)
	report["map"]["days_passed"] = snappedf(Game.day - day0, 0.01)
	report["map"]["speed_mult"] = 4.0
	report["map_labels"] = labels()
	report["mem_end_mib"] = mem()
	var ts2 := Time.get_ticks_usec()
	Game.save_game(); Game.wait_save()
	report["save_ms"] = snappedf(float(Time.get_ticks_usec() - ts2) / 1000.0, 0.1)
	ts2 = Time.get_ticks_usec()
	Game.load_game()
	report["load_ms"] = snappedf(float(Time.get_ticks_usec() - ts2) / 1000.0, 0.1)
	print("BENCH ", JSON.stringify(report))
	return 0
