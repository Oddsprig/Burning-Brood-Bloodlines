extends RefCounted
## v0.096 readability tour: screenshots of every menu page, tab and common modal (no battle).
## Needs a display (xvfb-run in a Linux container); never run it on the owner's PC with a window.
##   -- --test=res://tests/ui_pages_v096.gd --out=<dir> [--size=1600x900] [--mobile] [--only=a,b]
## --only takes group names: start, map, house, dragons, town, records, army, end.
var out := ""
var main: Node = null
var only: Array = []
var shots := 0

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func shot(tree: SceneTree, name: String) -> void:
	await frames(tree, 3)
	var img: Image = tree.root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	shots += 1
	print("pages: shot ", name)

func find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree(): return node
	for c in node.get_children():
		var b := find_button(c, text)
		if b != null: return b
	return null

func want(group: String) -> bool:
	return only.is_empty() or group in only

func screen(tree: SceneTree, name: String, params: Dictionary = {}, file: String = "") -> void:
	Game.goto(name, params)
	await frames(tree, 2)
	await shot(tree, file if file != "" else name.get_file().get_basename())

func close_modals(node: Node) -> void:
	for c in node.get_children():
		if c.has_meta("ui_modal"): c.queue_free()
		else: close_modals(c)

func run(tree: SceneTree) -> int:
	var size := Vector2i(1600, 900)
	var mobile := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
		if a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x")
			size = Vector2i(int(p[0]), int(p[1]))
		if a == "--mobile": mobile = true
		if a.begins_with("--only="): only = Array(a.trim_prefix("--only=").split(",", false))
	if out == "": print("pages: pass --out=<dir>"); return 1
	DirAccess.make_dir_recursive_absolute(out)
	if mobile: UiTheme.set_mobile_override(true)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	if want("start"):
		await shot(tree, "title")
		GuideView.open(main.current)
		await shot(tree, "guide_page1")
		for i in range(1, GuideView.PAGES.size()):   # every guide page, not only the first
			var next := find_button(main, "Next")
			if next == null: break
			next.pressed.emit()
			await shot(tree, "guide_page%d" % (i + 1))
		close_modals(main); await frames(tree, 1)
		await screen(tree, "newgame")
		await screen(tree, "settings", {"back": "title"})
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(777)
	while not Game.new_game_slice(generation, 8000):
		await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	var tid := ""
	var hid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult" or not dragon.get("alive", false): continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]): continue
		tid = str(owner["town_id"]); hid = str(owner["household_uid"]); break
	if want("start"):
		Game.goto("house_select")
		await frames(tree, 2)
		var hs: Node = main.current
		if hs.has_method("select_settlement"):
			hs.select_settlement(tid); await frames(tree, 1)
			hs.next_stage(); await shot(tree, "house_select_2")
			hs.select_house(hid); await frames(tree, 1)
			hs.next_stage(); await shot(tree, "house_select_3")
			hs.next_stage(); await shot(tree, "house_select_4")
			hs.next_stage(); await shot(tree, "house_select_5")
	if not HouseOnboarding.begin(Game, tid, hid).get("ok", false):
		print("pages: begin failed"); return 1
	Game.settings["guide_seen"] = true
	if want("map"):
		await screen(tree, "map")
		if "modal_host" in main.current:
			GuideView.open(main.current.modal_host)
			await shot(tree, "map_guide")
			close_modals(main); await frames(tree, 1)
			AmbitionsView.open(main.current.modal_host)
			await shot(tree, "map_ambitions")
			close_modals(main); await frames(tree, 1)
	if want("house"):
		for s in ["house", "court", "laws", "treasure", "politics", "population"]:
			await screen(tree, s)
		if main.current.has_method("_select"): pass
	if want("dragons"):
		await screen(tree, "dragons")
		var dv: Node = main.current
		var first := ""
		for row: Dictionary in Dragons.records(Game):
			if str(row.get("owner_household_uid", "")) == hid: first = str(row["id"]); break
		if first != "":
			dv._open_dragon(first); await shot(tree, "dragons_detail")
			dv.detail_uid = ""; dv._refresh()
		dv._set_roost(true); await shot(tree, "dragons_roost")
		dv._set_roost(false); dv._toggle_catalog(); await shot(tree, "dragons_catalog")
	if want("army"):
		var funding := Mobilization.fund(Game, int(floor(float(Feudal._payer(Game).get("purse", 0.0)) * 0.5)))
		var quote := Mobilization.quote(Game, tid, 120)
		if quote.get("ok", false): Mobilization.muster(Game, tid, 120, quote["review"])
		if Game.company.is_empty():   # this world can raise no common troops: let a house member ride so the company tabs exist
			for row in Mobilization.household_candidates(Game).slice(0, 2):
				Mobilization.enlist_household(Game, str(row["person_uid"]))
		print("pages: fund ", funding.get("ok", false), " company ", Game.company.size())
		await screen(tree, "company")
		var cv: Node = main.current
		if not Game.company.is_empty():
			cv.selected_uid = Game.company[0].uid
			for t in ["Overview", "Mind", "Skills", "Gear", "Health"]:
				cv.show_tab(t); await shot(tree, "company_" + t.to_lower())
		await screen(tree, "muster")
		await screen(tree, "res://ui/relations.tscn", {}, "relations")
		await screen(tree, "res://ui/baggage.tscn", {}, "baggage")
	if want("town"):
		Game.location = tid
		await screen(tree, "town")
		var tv: Node = main.current
		for t in ["Provisions", "Recruits", "Healer", "Contracts", "Buildings"]:
			tv.show_tab(t); await shot(tree, "town_" + t.to_lower())
		tv.show_tab("Town")
		await frames(tree, 1)
		for s in TownEconTab.SECTIONS:
			tv.set_meta("town_econ_section", s); tv.show_tab("Town")
			await shot(tree, "town_econ_" + str(s).to_lower())
	if want("records"):
		for t in ["Overview", "Market", "Businesses", "Land & Homes", "Census", "Treasury", "Hardship", "Garrison", "Roads", "Sickness", "Books"]:
			await screen(tree, "res://ui/records.tscn", {"view": "town", "id": tid, "tab": t}, "records_town_" + t.to_lower().replace(" & ", "_").replace(" ", "_"))
		for t in ["Towns", "Factions", "Rulers", "On the move", "Goods", "Food flows", "Fights", "Mines & land", "Merchants", "Census"]:
			await screen(tree, "res://ui/records.tscn", {"view": "world", "tab": t}, "records_world_" + t.to_lower().replace(" & ", "_").replace(" ", "_"))
	if want("end"):
		await screen(tree, "gameover")
		await screen(tree, "victory")
	print("pages: %d shots" % shots)
	return 0
