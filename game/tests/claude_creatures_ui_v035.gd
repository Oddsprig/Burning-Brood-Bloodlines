extends RefCounted
## v0.035 creature review through main.tscn: with creatures on, the company engages a real beast pack on the map
## (CampaignWorld.engage: lair terrain, militia allies), the battle scene fights it to the end, the aftermath opens and
## the pack's losses stay with it. Needs a display. -- --test=res://tests/claude_creatures_ui_v035.gd [--out=<dir>]
var fails := 0
var checks := 0
var out := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL creatures_ui035: ", what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func run(tree: SceneTree) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = Vector2i(1600, 900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 6)
	if not await DevTools.start_world(tree, "user://creatures-ui035-test.json", true):
		printerr("FAIL: the start world did not load")
		return 1
	Game.settings["guide_seen"] = true
	var seat := DevTools.choose_house(Game)
	check(seat != "", "a house was chosen")
	if seat == "": return fails
	var raised := DevTools.raise_army(Game, seat, 30)
	check(raised >= 1, "an army was raised (%d)" % raised)
	# The beast pack nearest the seat.
	var w: Dictionary = Game.world
	var home: Vector2 = w["towns"][seat]["pos"]
	var wid := ""
	for k in w["warbands"]:
		var wb: Dictionary = w["warbands"][k]
		if String(wb.get("kind", "")) != "beasts" or (wb.get("units", []) as Array).is_empty(): continue
		if wid == "" or (wb["pos"] as Vector2).distance_to(home) < (w["warbands"][wid]["pos"] as Vector2).distance_to(home): wid = String(k)
	check(wid != "", "a beast pack roams the map")
	if wid == "": return fails
	var pack: Dictionary = w["warbands"][wid]
	var size0 := (pack["units"] as Array).size()
	print("creatures_ui035: engaging %s, %d creatures (%s)" % [wid, size0, String(pack["units"][0].race)])
	Game.location = ""
	w["party"]["pos"] = pack["pos"]
	Game.goto("map"); await frames(tree, 4)
	CampaignWorld.engage(Game, wid)
	await frames(tree, 6)
	var b: Node = main.current
	check(b != null and "sim" in b, "the battle with the creatures opens")
	if b == null or not ("sim" in b): return fails
	if out != "": tree.root.get_texture().get_image().save_png(out.path_join("creature_battle.png"))
	b.skip_to_end()
	var waited := 0
	while is_instance_valid(b) and main.current == b and waited < 6000:
		await tree.process_frame; waited += 1
		if b.result_shown and not b.finished: b.finish()
	await frames(tree, 6)
	check(main.current != null and str(main.current.scene_file_path).contains("aftermath"), "the aftermath opens")
	var r: Dictionary = Game.last_result
	var dead := (r.get("enemy_units", []) as Array).filter(func(u): return u is Unit and u.dead).size()
	print("creatures_ui035: winner %d, %d of %d creatures dead, pack now %s" % [int(r.get("winner", -1)), dead, size0, str(w["warbands"].get(wid, {}).get("units", []).size()) if w["warbands"].has(wid) else "gone"])
	check(int(r.get("winner", -1)) >= 0, "the fight ends with a winner")
	if w["warbands"].has(wid):
		check((w["warbands"][wid]["units"] as Array).all(func(u): return not u.dead), "the pack keeps only its living creatures")
	if out != "": tree.root.get_texture().get_image().save_png(out.path_join("creature_aftermath.png"))
	# The New Bloodline switch: on by default, and Create world takes the choice.
	Game.settings.erase("creatures_enabled")
	Game.goto("newgame", {"back": "map"})
	await frames(tree, 6)
	var cb: CheckButton = main.current.find_child("CreaturesEnabled", true, false)
	check(cb != null and cb.button_pressed, "New Bloodline has a creatures switch, on by default")
	if cb != null:
		cb.button_pressed = false
		main.current._apply()
		check(not Monsters.new_world_creatures and not bool(Game.settings["creatures_enabled"]), "turning it off applies to the next world")
	Monsters.new_world_creatures = true; Game.settings.erase("creatures_enabled")
	Game.wait_save()
	print("creatures_ui035: %d checks, %d failures" % [checks, fails])
	return fails
