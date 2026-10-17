extends RefCounted
## v0.034 Population screen through main.tscn: the "Health, homes and movement" card for a town at war with sick
## common folk. Needs a display (screenshot with --out=<dir>).
## -- --test=res://tests/claude_population_ui_v034.gd [--out=<dir>] [--size=WxH]
var fails := 0
var checks := 0
var out := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL population_ui034: ", what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func text_of(root: Node) -> String:
	var s := ""
	if root is Label: s += (root as Label).text + "\n"
	for child in root.get_children(): s += text_of(child)
	return s

func run(tree: SceneTree) -> int:
	var size := Vector2i(1600, 900)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
		if a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x"); size = Vector2i(int(p[0]), int(p[1]))
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 6)
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(4242)
	while not Game.new_game_slice(generation, 8000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	var seat := ""
	for choice: Dictionary in Dynasty.choices(Game):
		if bool(HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false)):
			seat = str(choice["town_id"]); break
	check(seat != "", "a ruling house was chosen")
	if seat == "": return fails
	Game.settings["guide_seen"] = true
	var e: Dictionary = Game.world["towns"][seat]["econ"]
	Migration.note_attack(Game.world, seat, Game.day)
	var row: Dictionary = {}
	for f in e["fams"]:
		if Population.is_cohort(f) and not f.get("gone", false): row = f; break
	check(not row.is_empty(), "the seat has common folk")
	if row.is_empty(): return fails
	row["psk"] = [["flux", "adult", 12, 0, int(Game.day) + 5, int(Game.day) + 9, false]]
	Sickness.book(e)["act"]["flux"] = int(Sickness.book(e)["act"].get("flux", 0)) + 12
	Game.goto("population", {"town_id": seat, "back": "map"})
	await frames(tree, 8)
	var card: Node = main.current.find_child("HealthHomesMovement", true, false)
	check(card != null, "the Population screen has a health, homes and movement card")
	if card == null: return fails
	var words := text_of(card)
	check(words.contains("leaving for other towns, driven by fear of war"), "it says people are leaving, and why")
	check(words.contains("Sick now:") and words.contains("the flux"), "it lists the sick by disease")
	check(words.contains("households in") and words.contains("empty town houses"), "it shows homes and households")
	check(words.contains("This season: left"), "it shows who came and went")
	if out != "":
		await frames(tree, 4)
		tree.root.get_texture().get_image().save_png(out.path_join("population_health.png"))
	Game.wait_save()
	print("population_ui034: %d checks, %d failures" % [checks, fails])
	return fails
