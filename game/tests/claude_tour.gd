extends RefCounted
## Screenshot tour of the real screens through main.tscn: title, map, house, dragons, town, army, battle, results.
## -- --test=res://tests/claude_tour.gd --out=<dir> [--size=1280x720] [--only=a,b]
var out := ""
var fails := 0
var main: Node = null
var timings := {}

func frames(tree: SceneTree, n: int = 4) -> void:
	for i in n:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func shot(tree: SceneTree, name: String) -> void:
	await frames(tree, 4)
	var img: Image = tree.root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	print("tour: shot ", name)

func screen(tree: SceneTree, name: String, params: Dictionary = {}) -> void:
	var t := Time.get_ticks_usec()
	Game.goto(name, params)
	await frames(tree, 2)
	timings[name] = float(Time.get_ticks_usec() - t) / 1000.0
	await shot(tree, name.get_file().get_basename())

func run(tree: SceneTree) -> int:
	var size := Vector2i(1280, 720)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
		if a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x")
			size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 10)
	if not main.is_inside_tree():
		print("tour: main not in tree"); return 1
	await shot(tree, "title")
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var start := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	while not Game.new_game_slice(generation, 8000):
		await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	timings["generate"] = float(Time.get_ticks_usec() - start) / 1000.0
	await screen(tree, "house_select")
	# Pick the first ruling house that owns an adult dragon at home, else any ruling house.
	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult" or not dragon.get("alive", false): continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]): continue
		if HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false):
			tid = str(owner["town_id"]); break
	print("tour: home town ", tid)
	var mk := {"monster_bands": 0, "active_monster_bands": 0, "lairs": Game.world.get("lairs", {}).size(), "active_lairs": 0}
	for k in Game.world["warbands"]:
		var wb: Dictionary = Game.world["warbands"][k]
		if Monsters.is_monster_band(wb) or Monsters.creature_units(wb.get("units", [])):
			mk["monster_bands"] += 1
			if not Monsters.suspended_band(wb): mk["active_monster_bands"] += 1
	for l in Game.world.get("lairs", {}).values():
		if not Monsters.suspended_lair(l): mk["active_lairs"] += 1
	print("tour: creatures ", mk)
	Game.settings["guide_seen"] = true
	await screen(tree, "map")
	if "cam" in main.current:
		var z: Vector2 = main.current.cam.zoom
		main.current.follow = false
		main.current.cam.zoom = z * 0.4
		main.current.cam.position = Vector2(WorldGen.W, WorldGen.H) * WorldGen.CELL * 0.5
		await shot(tree, "map_wide")
		main.current.cam.zoom = z; main.current.follow = true
		await frames(tree, 4)
	if main.current.has_method("_select"):
		var other := ""
		for t2 in Game.world["towns"]:
			if str(t2) != tid: other = str(t2); break
		main.current._select({"kind": "town", "id": other})
		await shot(tree, "map_info")
	var quick := "--battle-only" in OS.get_cmdline_user_args()
	for s in ([] if quick else ["house", "court", "laws", "dragons", "politics", "population", "company", "muster"]):
		await screen(tree, s)
	Game.location = tid
	await screen(tree, "town")
	for tab_name in ["Town", "Recruits", "Politics"]:
		if main.current.has_method("show_tab"):
			main.current.show_tab(tab_name); await shot(tree, "town_" + tab_name.to_lower())
	await screen(tree, "res://ui/records.tscn", {"view": "town", "id": tid, "tab": "Register"})
	Game.location = tid
	await screen(tree, "town")
	# Raise a force and fight an actual enemy band.
	var funding := Mobilization.fund(Game, int(floor(float(Feudal._payer(Game).get("purse", 0.0)) * 0.8)))
	var quote := Mobilization.quote(Game, tid, 200)
	print("tour: fund ", funding.get("ok", false), " quote ", quote.get("planned", 0))
	if quote.get("ok", false):
		Mobilization.muster(Game, tid, 200, quote["review"])
	print("tour: company ", Game.company.size())
	for dragon: Dictionary in Dragons.records(Game):
		var uid := str(dragon["id"])
		if dragon.get("stage", "") != "adult" or str(dragon.get("location_town_id", "")) != tid: continue
		var cands: Array = DragonBond.candidates(Game, uid)
		if cands.is_empty(): continue
		var pid := str(cands[0]["person_uid"])
		var bound: Dictionary = DragonBond.bind(Game, uid, pid, DragonBond.bind_preview(Game, uid, pid))
		var pv := DragonCombat.participation_preview(Game, uid, true)
		var ord := DragonCombat.participation_order(Game, uid, true, pv) if pv.get("ok", false) else pv
		print("tour: dragon ", uid, " bond ", bound.get("ok", false), " defend ", ord.get("ok", false), " ", ord.get("reason", ""))
	print("tour: dragons in battle ", DragonCombat.battle_units(Game).size())
	var enemy_id := ""
	for key in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][key]
		if band.get("faction", "") != Game.world["towns"][tid].get("faction", "") and Army.is_people_band(band) and not band.get("units", []).is_empty() and not Monsters.suspended_band(band):
			enemy_id = str(key); break
	if enemy_id == "":
		print("tour: no enemy band"); return 1
	var enemy: Array = Game.world["warbands"][enemy_id]["units"].duplicate()
	print("tour: enemy ", enemy.size())
	Game.start_battle({"enemy": enemy, "allies": [], "warband_id": enemy_id, "seed": 9022, "terrain": "grassland", "map": "large"})
	await frames(tree, 30)
	await shot(tree, "battle_start")
	var b: Node = main.current
	var t0 := Time.get_ticks_usec()
	var nframes := 0
	var worst := 0.0
	var breath_shots := 0
	var battle_secs := 45 if quick else 20
	var last := t0
	while Time.get_ticks_usec() - t0 < battle_secs * 1000000 and is_instance_valid(b) and main.current == b:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, float(now - last) / 1000.0); last = now
		nframes += 1
		if nframes == 300: await shot(tree, "battle_mid")
		if breath_shots < 2 and "sim" in b and b.sim != null:
			for e in b.sim.new_events:
				if str(e.get("type", "")) == "breath":
					for k in 8: await tree.process_frame
					await shot(tree, "battle_breath_%d" % breath_shots); breath_shots += 1
					break
		if nframes == 420 or nframes == 600:
			for v in b.views:
				if v.doll is DragonView and v.visible:
					b.auto_cam = false; b.cam_zoom = 2.0; b.cam_pos = v.position + Vector2(0, -40)
					await shot(tree, "battle_dragon_%d" % nframes)
					b.auto_cam = true
					break
	var secs := float(Time.get_ticks_usec() - t0) / 1e6
	if is_instance_valid(b) and "sim" in b and b.sim != null:
		var kinds := {}
		for e in b.sim.events:
			if str(e.get("type", "")) in ["breath", "breath_hit", "death"]: kinds[e["type"]] = int(kinds.get(e["type"], 0)) + 1
		print("tour: events ", kinds, " breath_state ", b.sim.breath_state, " dbg ", b.sim.breath_debug)
	print("tour: battle %d frames in %.1fs = %.1f fps, worst %.1f ms" % [nframes, secs, nframes / secs, worst])
	await shot(tree, "battle_late")
	print("tour: timings ", JSON.stringify(timings))
	return fails
