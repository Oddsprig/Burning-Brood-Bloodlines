extends RefCounted
## Four real native register policies, read-only navigation and three desktop fits.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
const EconomyFixture = preload("res://tests/test_dynasty_foundation.gd")
const WINDOWS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var tree: SceneTree
var checks := 0
var fails := 0
var fit_cases := 0
var report_dir := ""
var captures: Array = []
var native: NativeFixture

class RouteProbe extends Node:
	var path := ""
	func show_screen(value: String) -> void: path = value

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL house laws: ", text)

func settle() -> void:
	for i in 4: await tree.process_frame

static func labels(node: Node) -> String:
	var text := (node as Label).text + "\n" if node is Label else ""
	for child in node.get_children(): text += labels(child)
	return text

static func fingerprint() -> String:
	return JSON.stringify({"state": Game._save_tree(), "rng": str(Game.rng.state), "unit": Unit._next_uid, "item": Item._next_uid}, "", true, true).sha256_text()

func fixture() -> Dictionary:
	native = NativeFixture.new(); native.fixture()
	var expected: Dictionary = {}
	var races := ["human", "dwarf", "moon_elf", "orc"]
	var cultures := ["middle", "dwarf", "moon_elf", "orc"]
	for i in 4:
		var tid: String = str(["seat", "county", "village", "foreign"][i])
		var town: Dictionary = Game.world["towns"][tid]; var e: Dictionary = town["econ"]; var f: Dictionary = e["fams"][0]
		town["culture"] = cultures[i]; e["culture"] = cultures[i]
		var ages: Dictionary = People.ages(races[i]); var adult := int(ages["adult"])
		var ruler_age := mini(int(ages["lifespan"]) - 2, adult + 60)
		var ruler: Array = f["pp"][0]; ruler[3] = -int(ruler_age * People.year_days())
		if ruler_age >= int(ages["elder"]): ruler[6] = 1; f["m"] = 0; f["old"] = 1
		var elder: Array = native.child(e, f, int(e["next_pid"]), 1, 18 if i == 2 else adult + 20, ruler, races[i].capitalize() + " elder daughter")
		var younger: Array = native.child(e, f, int(e["next_pid"]), 0, 12 if i == 2 else adult + 10, ruler, races[i].capitalize() + " younger son")
		e["pop"] = Families.people(f); e["adults"] = Families.adults(f)
		expected[tid] = {"race": races[i], "law": ["male_preference", "male_preference", "absolute", "strength"][i],
			"heir_uid": "" if i == 3 else str(elder[Persons.PERSON_UID]) if i == 2 else str(younger[Persons.PERSON_UID]), "children": [elder, younger]}
	Dynasty.prepare_world(Game)
	Game.location = "seat"; Game.world["party"]["pos"] = Game.world["towns"]["seat"]["pos"]
	return expected

func width_checks(page: HouseLaws, size: Vector2i, state: String) -> void:
	var bar: VScrollBar = page.scroll.get_v_scroll_bar()
	var width := page.scroll.size.x - page.scroll.get_theme_stylebox("panel").get_minimum_size().x - (bar.size.x if bar.visible else 0.0)
	check(page.body.size.x >= width - 2.0, "%dx%d %s law column fills the readable scroll width" % [size.x, size.y, state])
	var font: Font = page.heading.get_theme_font("font")
	var title_size := page.heading.get_theme_font_size("font_size")
	var text_width := font.get_string_size(page.heading.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	check(page.heading.size.x + 1.0 >= text_width and page.heading.text == "House Laws", "%dx%d %s actual resolved title font fits without truncation" % [size.x, size.y, state])
	var description: Label = page.find_child("LawsPolicy", true, false)
	check(description != null and description.size.x >= 700.0, "%dx%d %s policy card has actual readable desktop width" % [size.x, size.y, state])

func capture(viewport: SubViewport, size: Vector2i) -> void:
	if report_dir == "": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var path := report_dir.path_join("laws_%dx%d.png" % [size.x, size.y])
	check(image != null and image.get_size() == size and image.save_png(path) == OK, "actual private desktop Laws render %dx%d" % [size.x, size.y])
	captures.append({"path": path, "size": [size.x, size.y], "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""})

func policies_and_links(probe: RouteProbe) -> void:
	var expected: Dictionary = fixture()
	var before := fingerprint()
	for tid in expected:
		var row: Dictionary = HouseLaws.read_data(Game, tid)
		check(row["law"] == expected[tid]["law"] and row["race"] == expected[tid]["race"], "native race/law display " + str(tid))
		check(str(row["heir"].get("person_uid", "")) == expected[tid]["heir_uid"], "actual eligible successor under native policy " + str(tid))
	check(before == fingerprint(), "four-race law reads preserve exact native people, money, world/RNG and UID counters")
	check(HouseLaws.read_data(Game, "missing").is_empty(), "unknown settlement has no invented law/ruler/heir display")
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	for size: Vector2i in WINDOWS:
		var viewport := SubViewport.new(); viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		for tid in expected:
			Game.screen_params = {"town_id": tid, "back": "house", "back_params": {"back": "map", "sentinel": true}, "return_location": "seat"}
			Game._active_screen = "laws"
			var page: HouseLaws = (load("res://ui/house_laws.tscn") as PackedScene).instantiate()
			viewport.add_child(page); await settle()
			check(page.data["law"] == expected[tid]["law"] and labels(page).contains(HouseLaws.law_name(str(expected[tid]["law"]))), "visible native Laws content " + str(tid))
			check(not page.find_children("*", "SpinBox", true, false).size() and not page.find_children("*", "OptionButton", true, false).size(), "laws have no mutation/edit control " + str(tid))
			width_checks(page, size, str(tid)); fit._check(viewport, Vector2(size), "v018 Laws " + str(tid)); fit_cases += 1
			if tid == "village": check(labels(page).contains("Minor heir"), "rightful actual minor remains visible and eligible")
			if tid == "foreign": check(page.find_child("LawsHeirDetail", true, false) == null and labels(page).contains("strength contests decide"), "orc contest is not replaced by a fabricated hereditary successor")
			if tid == "seat": await capture(viewport, size)
			page.queue_free(); await settle()
		viewport.queue_free(); await settle()
	check(before == fingerprint(), "opening, rendering and closing all Laws policies preserves native state")
	fails += int(fit.fails)
	var viewport := SubViewport.new(); viewport.size = WINDOWS[0]; tree.root.add_child(viewport)
	Game.screen_params = {"town_id": "seat", "back": "house", "back_params": {"back": "map", "sentinel": true}, "return_location": "seat"}
	var page: HouseLaws = (load("res://ui/house_laws.tscn") as PackedScene).instantiate(); viewport.add_child(page); await settle()
	var heir: Dictionary = page.data["heir"]
	var actual: Dictionary = Dynasty.person(Game, str(heir["person_uid"]))
	var link: Button = page.find_child("LawsHeirDetail", true, false); check(link != null, "actual heir has reachable native detail button")
	if link != null: link.pressed.emit()
	check(probe.path == "res://ui/records.tscn" and Game.screen_params.get("person_uid", "") == actual["person_uid"] and int(Game.screen_params.get("family_id", -1)) == actual["family_id"] and int(Game.screen_params.get("pid", -1)) == actual["pid"], "detail navigation uses current real person/town/family/PID refs")
	check(Game.screen_params["back"] == "laws" and Game.screen_params["back_params"]["town_id"] == "seat" and Game.location == "seat", "records return context preserves Laws and actual party location")
	page._back()
	check(probe.path == "res://ui/house.tscn" and Game.screen_params == {"back": "map", "sentinel": true} and Game.location == "seat", "Laws Back restores actual House context without teleporting")
	check(before == fingerprint(), "native detail/back callbacks preserve accounts/people/RNG/UID counters")
	# Current successor may die between display and click; no stale identity link.
	var e: Dictionary = Game.world["towns"]["seat"]["econ"]; var f: Dictionary = e["fams"][0]
	var son: Array = expected["seat"]["children"][1]
	Persons.remove(f, son, e)
	page._refresh()
	check(page.data["heir"].get("person_uid", "") == str(expected["seat"]["children"][0][Persons.PERSON_UID]), "native human daughter fallback is visible after male branch is exhausted")
	for p in expected["seat"]["children"]:
		if p == son: continue
		if int(p[6]) == 2: Persons.forget(e, f, p); Persons.kp(f).erase(p)
		else: Persons.remove(f, p, e)
	var dead_state := fingerprint(); var old_path := probe.path
	page._person_record(str(heir["person_uid"]))
	check(probe.path == old_path and page.data["heir"].is_empty() and page.find_child("LawsHeirDetail", true, false) == null, "dead/exhausted successor is removed instead of opening stale heir")
	check(dead_state == fingerprint() and labels(page).contains("No eligible living heir recorded"), "stale-heir refresh is pure and explains actual absence")
	var dwarf_e: Dictionary = Game.world["towns"]["county"]["econ"]; var dwarf_f: Dictionary = dwarf_e["fams"][0]
	Persons.remove(dwarf_f, expected["county"]["children"][1], dwarf_e)
	var dwarf_state := fingerprint(); var dwarf: Dictionary = HouseLaws.read_data(Game, "county")
	check(dwarf["heir"].get("person_uid", "") == str(expected["county"]["children"][0][Persons.PERSON_UID]) and dwarf_state == fingerprint(), "native dwarf daughter fallback remains visible and read-only")
	page.queue_free(); viewport.queue_free(); await settle()

func house_entry(probe: RouteProbe) -> void:
	EconomyFixture.new().fixture(); Feudal.prepare_world(Game); Dynasty.select_city(Game, "city_a")
	Game.screen_params = {"back": "map"}; Game._active_screen = "house"
	var before := fingerprint()
	var viewport := SubViewport.new(); viewport.size = WINDOWS[0]; tree.root.add_child(viewport)
	var house: Control = (load("res://ui/house.tscn") as PackedScene).instantiate(); viewport.add_child(house); await settle()
	var laws: Button = house.find_child("HouseLawsButton", true, false)
	check(laws != null and not labels(house).contains("Succession:"), "actual House has a Laws entry without duplicated overview succession")
	if laws != null: laws.pressed.emit()
	check(probe.path == "res://ui/house_laws.tscn" and Game.screen_params["town_id"] == "city_a" and Game.screen_params["back"] == "house" and Game.screen_params["back_params"] == {"back": "map"}, "actual House Laws button carries real seat and House return context")
	house.queue_free(); await settle()
	Game.screen_params = {}; var chooser: Control = (load("res://ui/house_select.tscn") as PackedScene).instantiate(); viewport.add_child(chooser); await settle()
	check(not labels(chooser).contains("Succession:"), "existing chooser no longer duplicates the Laws view")
	check(before == fingerprint(), "root House/chooser Laws integration remains native-state pure")
	chooser.queue_free(); await settle()
	Game.screen_params = {"town_id": "city_a", "back": "house", "back_params": {"back": "map"}}
	var laws_page: HouseLaws = (load("res://ui/house_laws.tscn") as PackedScene).instantiate(); viewport.add_child(laws_page); await settle()
	var ruler: Dictionary = laws_page.data["ruler"]
	laws_page._person_record(str(ruler["person_uid"]))
	var records: Control = (load("res://ui/records.tscn") as PackedScene).instantiate(); viewport.add_child(records); await settle()
	var opened: Array = records.get("stack")
	check(not opened.is_empty() and str(opened[-1].get("title", "")) == str(ruler["name"]), "actual Records scene opens the real registered ruler detail from stable person parameters")
	records.call("close")
	check(probe.path == "res://ui/house_laws.tscn" and Game.screen_params["town_id"] == "city_a" and Game.screen_params["back"] == "house", "actual Records Close returns to the same Laws/House navigation context")
	check(before == fingerprint(), "actual Records person detail and Close are native-state pure")
	records.queue_free(); laws_page.queue_free(); viewport.queue_free(); await settle()

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree; await tree.process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
	if report_dir != "":
		var base := "c:/users/bligh/documents/codex/2026-10-10/you/work/v018-laws-ui"
		check(report_dir.is_absolute_path() and (report_dir.to_lower() == base or report_dir.to_lower().begins_with(base + "/")), "private Laws capture destination")
		check(DisplayServer.get_name() != "headless" and not DirAccess.dir_exists_absolute(report_dir), "native renderer and fresh report directory required")
		if fails > 0: return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK, "private capture directory created")
		tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000)
	var original := {"world": Game.world, "company": Game.company, "stash": Game.stash, "squads": Game.squads, "gold": Game.gold, "day": Game.day, "location": Game.location,
		"main": Game.main, "params": Game.screen_params, "screen": Game._active_screen, "rng": Game.rng.state, "unit": Unit._next_uid, "item": Item._next_uid,
		"wg": [WorldGen.W, WorldGen.H, WorldGen.K, WorldGen.TF, WorldGen.KD]}
	Game.world = {}; Game.company = []; Game.stash = []; Game.squads = {}
	var probe := RouteProbe.new(); tree.root.add_child(probe); Game.main = probe
	await policies_and_links(probe)
	await house_entry(probe)
	Game.world = original["world"]; Game.company = original["company"]; Game.stash = original["stash"]; Game.squads = original["squads"]; Game.gold = original["gold"]; Game.day = original["day"]
	Game.location = original["location"]; Game.main = original["main"]; Game.screen_params = original["params"]; Game._active_screen = original["screen"]
	Game.rng.state = original["rng"]; Unit._next_uid = original["unit"]; Item._next_uid = original["item"]
	WorldGen.W = original["wg"][0]; WorldGen.H = original["wg"][1]; WorldGen.K = original["wg"][2]; WorldGen.TF = original["wg"][3]; WorldGen.KD = original["wg"][4]
	probe.queue_free(); await settle()
	if report_dir != "":
		var file := FileAccess.open(report_dir.path_join("laws-ui.json"), FileAccess.WRITE)
		check(file != null, "private Laws report opens")
		if file != null:
			file.store_string(JSON.stringify({"checks": checks, "failures": fails, "fit_cases": fit_cases, "captures": captures,
				"scope": "Current native four-race laws/heirs, read purity, real registry/back context and three desktop sizes; no phone QA."}, "\t", true, true)); file.close()
	print("house laws v018: %d checks, %d failures, %d desktop fit cases" % [checks, fails, fit_cases])
	tree = null
	return fails
