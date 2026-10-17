extends RefCounted
## Native records, real font/surface/glyph checks; optional private desktop frames.
const WINDOWS := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
const REQUIRED := ["Overview","Register","Businesses","Census","Treasury","Garrison"]
const Records = preload("res://ui/records.gd")
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0
var report_dir: String = ""
var captures: Array = []

class RouteProbe extends Node:
	var path: String = ""
	func show_screen(value: String) -> void: path = value

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL records UI: ",why)

func settle() -> void:
	for _i in 5: await tree.process_frame

static func fingerprint() -> String:
	return JSON.stringify({"state":Game._save_tree(),"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid},"",true,true).sha256_text()

static func metrics(node: Node) -> Array:
	var found: Array = []
	if node.has_meta("rec_metric"): found.append(node.get_meta("rec_metric"))
	for child: Node in node.get_children(): found.append_array(metrics(child))
	return found

static func labels(node: Node) -> String:
	var text: String = (node as Label).text+"\n" if node is Label else ""
	for child: Node in node.get_children(): text += labels(child)
	return text

func fit_check(fit: RefCounted, viewport: SubViewport, page: Control, size: Vector2i, state: String) -> void:
	fit_cases += 1
	var context: String = "%dx%d %s" % [size.x,size.y,state]
	fit._check(viewport,Vector2(size),"v018 "+context)
	check(page.size.is_equal_approx(Vector2(size)),context+" real PackedScene fills viewport")
	var title: Label = page.title_l
	var glyph_width: float = title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size")).x
	check(title.size.x >= glyph_width,context+" full title fits actual bundled font")
	check(page.bar.get_global_rect().end.x <= size.x-UiKit.diagnostics_lane(size.x)+1.5,context+" navigation leaves diagnostics lane")
	check(page.groups_box.get_child_count() == 4 and page.tabs_box.get_child_count() <= 4,context+" four category groups and bounded subnavigation")
	var selected: int = 0
	for button: Button in page.groups_box.get_children():
		check(button.size.y >= 48,context+" category is a real touch target")
		if button.theme_type_variation == "TabOn": selected += 1
	check(selected == 1,context+" exactly one strong selected category")
	var sc: ScrollContainer = page.list_sc if page.list_sc.visible else page.page_sc
	var box: VBoxContainer = page.list_box if page.list_sc.visible else page.page_box
	var available: float = sc.size.x-sc.get_theme_stylebox("panel").get_minimum_size().x-(sc.get_v_scroll_bar().size.x if sc.get_v_scroll_bar().visible else 0.0)
	check(box.size.x >= available-2.0 and box.size.x >= 450.0,context+" record column uses actual scroll width")
	for table: RecTable in page._tables(box):
		var built: int = table._rows_box.get_children().filter(func(row): return row.has_meta("rec_row")).size()
		check(built == mini(table.limit,table.shown().size()) and table._rows_box.get_child_count() <= table.limit+1,context+" only visible native rows plus one paging/empty control are built")
		check(table.limit <= RecTable.LIMIT,context+" initial table page remains bounded")
		for row: Control in table._rows_box.get_children():
			check(row.size.x >= table._rows_box.size.x-2.0,context+" data row is full width")
	for node: Node in box.find_children("*","",true,false):
		if node is RecCells:
			var row: RecCells = node
			var normal: StyleBoxFlat = row.get_theme_stylebox("normal") as StyleBoxFlat
			check(normal != null and normal.bg_color.get_luminance() < 0.2,context+" cream values have dark row surface")
			check(row.custom_minimum_size.y == (56 if row.has_meta("rec_row") and not row.header else 48),context+" compact aligned data row height")
			for i in row.cells.size():
				check(row.cells[i].width >= 35.0,context+" actual cell has usable width")
				var value: String = String(row.get_meta("rec_values")[i])
				check(value == "" or row.cells[i].get_line_width() > 0.0,context+" actual nonempty value shapes glyphs")
				for style: String in ["normal","hover","pressed"]:
					var surface: Color = (row.get_theme_stylebox(style) as StyleBoxFlat).bg_color
					check(UiTheme.contrast(UiTheme.readable(row.colors[i],surface),surface) >= 4.5,context+" value contrast in "+style)
		elif node is RecRow:
			var row: RecRow = node
			check(row.lines[2].width >= 400.0,context+" native row details are not skinny")
			check(row.custom_minimum_size.y == 56,context+" two-line records remain compact")

func capture(viewport: SubViewport, size: Vector2i, state: String, page: Control) -> void:
	if report_dir == "": return
	for node: Node in viewport.find_children("*","",true,false):
		if node is PerformancePanel: (node as PerformancePanel)._refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path: String = report_dir.path_join("records_%dx%d_%s.png" % [size.x,size.y,state])
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == size,"native Records rendered dimensions "+state)
	var saved: bool = image != null and image.save_png(path) == OK
	check(saved,"private native Records PNG "+state)
	captures.append({"path":path,"sha256":FileAccess.get_sha256(path) if saved else "","size":[size.x,size.y],"state":state,
		"title_width":page.title_l.size.x,"list_width":page.list_box.size.x,"detail_width":page.page_box.size.x,"tab_build_ms":page.tab_ms})

func table_actions(page: Control, size: Vector2i, tab: String) -> void:
	var tables: Array = page._tables(page.list_box)
	check(not tables.is_empty(),tab+" has a real searchable native table")
	if tables.is_empty(): return
	var table: RecTable = tables[0]
	check(not table.rows.is_empty(),tab+" contains native rows")
	if table.rows.is_empty(): return
	var before: String = fingerprint()
	var name: String = String(table.rows[0].get("_s",table.rows[0]["_l"]))
	check(table._search_box != null,tab+" native search is available")
	if table._search_box != null:
		table._search_box.text = name; table._search_box.text_changed.emit(name)
		check(not table.shown().is_empty() and table.shown().all(func(row): return String(row.get("_s",row["_l"])).to_lower().contains(name.to_lower())),tab+" name search shows actual matching records")
		table._search_box.text = "no_such_record_v018"; table._search_box.text_changed.emit(table._search_box.text)
		check(table.shown().is_empty() and not table._rows_box.get_children().any(func(row): return row.has_meta("rec_row")),tab+" absent search produces no invented rows")
		table._search_box.text = ""; table._search_box.text_changed.emit("")
	var key: String = "purse" if tab == "Register" else "cash"
	table.sort_by(key)
	var descending: Array = table.shown()
	check(not table.asc and descending[0][key] >= descending[-1][key],tab+" actual numeric values sort descending")
	table.sort_by(key)
	var ascending: Array = table.shown()
	check(table.asc and ascending[0][key] <= ascending[-1][key],tab+" actual numeric values reverse ascending")
	check(fingerprint() == before,tab+" filtering/sorting preserve all native state and RNG")
	# Follow the exact original row callback, not a fabricated detail route.
	(table.rows[0]["_tap"] as Callable).call()
	await settle()
	check(page.stack.size() == 1 and page.page_sc.visible,tab+" real row opens linked native detail")
	check(("Purse:" if tab == "Register" else "Cash in the till:") in labels(page.page_box),tab+" detail contains actual account fields")
	check(fingerprint() == before,tab+" detail reads do not alter genealogy/people/coin/gear/RNG/UIDs")

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree; await tree.process_frame; Game.wait_save()
	var started: int = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	if report_dir != "":
		check(report_dir.is_absolute_path() and report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v018-ui-render/"),"private Records report path")
		check(DisplayServer.get_name() != "headless","native renderer required for requested PNGs")
		if fails > 0: tree = null; return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("records-ui.json")),"fresh private Records directory")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.visible = true
	check(UiTheme.regular_font() is FontFile and UiTheme.bold() is FontFile,"actual bundled regular and bold fonts")
	check(UiTheme.get_theme().default_font == UiTheme.regular_font() and UiTheme.get_theme().get_font("font","RowOn") == UiTheme.bold(),"default/body and selected rows resolve bundled font files")
	check(FileAccess.get_sha256("res://ui/fonts/LiberationSans-Regular.ttf") == "f8ace1f892b2bd9dc1792ba7f097fa7588f84fed48321480e04de5390828221f" and FileAccess.get_sha256("res://ui/fonts/LiberationSans-Bold.ttf") == "361c61b82d575c5c35fd9157fda8b0194bcfcd0d88ea8521a4fb5dd53d33dddc","bundled font bytes are source-exact")
	check(FileAccess.file_exists("res://ui/fonts/LICENSE_LIBERATION") and "SIL OPEN FONT LICENSE" in FileAccess.get_file_as_string("res://ui/fonts/LICENSE_LIBERATION"),"full font redistribution license retained")
	var original: Dictionary = {"world":Game.world,"company":Game.company,"stash":Game.stash,"squads":Game.squads,"gold":Game.gold,"day":Game.day,
		"location":Game.location,"contract":Game.contract,"pending":Game.pending_battle,"result":Game.last_result,"params":Game.screen_params,"main":Game.main,
		"screen":Game._active_screen,"provisions":Game.provisions,"rations":Game.rations,"clock":Game.food_clock,"rng":Game.rng.state,
		"unit":Unit._next_uid,"item":Item._next_uid,"size":tree.root.size,"deploy_rev":Game._deploy_rev,"deploy_key":Game._deploy_key,"deploy_cache":Game._deploy_cache,
		"tabs":Records.last_tab.duplicate(),"town":Records.last_town,"wg":[WorldGen.W,WorldGen.H,WorldGen.K,WorldGen.TF,WorldGen.KD]}
	Game.world = {}; Game.company = []; Game.stash = []; Game.squads = {}; Game.contract = {}; Game.pending_battle = {}; Game.last_result = {}
	Game.provisions = {"meal":[],"beer":[],"wine":[]}; Game.food_clock = {}; Game.rations = {"food":"normal","drink":"ration"}; Game._deploy_key = []; Game._deploy_cache = []
	var fixture: RefCounted = load("res://tests/test_mobilization_v017.gd").new()
	var native: Dictionary = fixture.fixture(Game)
	var public: Array = native["public_units"]
	var band: Dictionary = Game.world["warbands"]["public"].duplicate()
	Game.world["warbands"].erase("public")
	band["id"] = "records_militia"; band["units"] = [public[1]]
	Game.world["warbands"][band["id"]] = band
	var guards: Dictionary = band.duplicate(); guards["id"] = "records_guards"; guards["kind"] = "guards"; guards["units"] = [public[0]]
	Game.world["warbands"][guards["id"]] = guards
	Game.world["militia"] = {"city_a":band["id"]}; Game.world["town_guards"] = {"city_a":guards["id"]}
	var probe := RouteProbe.new(); tree.root.add_child(probe); Game.main = probe; Game._active_screen = "records"
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var baseline: String = fingerprint()
	for size: Vector2i in WINDOWS:
		Game.screen_params = {"view":"town","id":"city_a","tab":"Overview","back":"laws","back_params":{"town_id":"city_a","sentinel":true}}
		if report_dir != "": tree.root.size = size
		var viewport := SubViewport.new(); viewport.size = size; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
		var performance := PerformancePanel.new(); performance.setup(Perf); layer.add_child(performance)
		var page: Control = (load("res://ui/records.tscn") as PackedScene).instantiate(); viewport.add_child(page); await settle()
		var grouped: Array = []
		for group: Dictionary in page.categories(): grouped.append_array(group["tabs"])
		check(grouped.size() == Records.TOWN_TABS.size() and Records.TOWN_TABS.all(func(value): return grouped.has(value)),"all twelve original town tabs remain reachable")
		page.select_category("Economy"); await settle()
		check(page.tab == "Market","category button opens actual native first tab")
		for tab: String in REQUIRED:
			page.show_tab(tab); await settle()
			check(fingerprint() == baseline,"%dx%d %s opening is a pure native read" % [size.x,size.y,tab])
			var facts: Array = metrics(page.list_box)
			check(facts.size() >= 3,tab+" has compact actual summaries")
			var expected: String = ""
			match tab:
				"Overview": expected = UiKit.thousands(Census.people(native["econ"]))
				"Register": expected = str(People.census(RecCivic._read_town(native["town"],native["econ"])["econ"])["households"])
				"Businesses": expected = str(page._tables(page.list_box)[0].rows.size())
				"Census": expected = str(Census.people(native["econ"]))
				"Treasury": expected = RecData.money(RecData.treasury(native["econ"]))
				"Garrison": expected = str(public.size())
			check(not facts.is_empty() and String(facts[0]["value"]) == expected,tab+" first summary equals the authoritative native value")
			fit_check(fit,viewport,page,size,tab); await capture(viewport,size,tab.to_lower(),page)
			if tab in ["Register","Businesses"]:
				await table_actions(page,size,tab)
				fit_check(fit,viewport,page,size,tab+" detail")
				await capture(viewport,size,"family_detail" if tab == "Register" else "business_detail",page)
				page.go_back(); await settle()
				check(page.stack.is_empty() and fingerprint() == baseline,tab+" Back restores list without native mutation")
		# Inconsistent older counters must not cause native sync/forget on a view copy.
		var copied: Dictionary = native["town"].duplicate(); copied["econ"] = native["econ"].duplicate(true)
		var ruler: Dictionary = Dynasty.ruler(Game)
		var family_id: int = int(ruler["family_id"])
		var cf: Dictionary = RecData.fam(copied["econ"],family_id)
		cf["m"] = 0; cf["f"] = 0; cf["old"] = 0; cf["kids"] = 0
		page.open_family(copied,family_id); await settle()
		check(fingerprint() == baseline,"inconsistent copied counters never trigger global person forget/sync")
		page.queue_free(); page = null; await settle()
		Game.screen_params["person_uid"] = ruler["person_uid"]
		Game.screen_params["family_id"] = family_id; Game.screen_params["pid"] = ruler["pid"]
		page = (load("res://ui/records.tscn") as PackedScene).instantiate(); viewport.add_child(page); await settle()
		check(page.sel == ruler["town_id"] and page.stack.size() == 1 and String(ruler["name"]) in labels(page.page_box),"stable Laws person UID opens actual current native person")
		fit_check(fit,viewport,page,size,"Person detail"); await capture(viewport,size,"person_detail",page)
		var location: String = Game.location; var pos: Vector2 = Game.world["party"]["pos"]
		page.close()
		check(Game._active_screen == "laws" and Game.screen_params.get("sentinel",false) and Game.location == location and Game.world["party"]["pos"] == pos,"Close returns to Laws context without Back teleport")
		check(fingerprint() == baseline,"all native details/navigation preserve world/genealogy/body/items/coin/RNG/UIDs")
		Game._active_screen = "records"
		viewport.queue_free(); viewport = null; page = null; performance = null; layer = null; copied = {}; cf = {}; ruler = {}; await settle()
	Game.world = original["world"]; Game.company = original["company"]; Game.stash = original["stash"]; Game.squads = original["squads"]
	Game.gold = original["gold"]; Game.day = original["day"]; Game.location = original["location"]; Game.contract = original["contract"]
	Game.pending_battle = original["pending"]; Game.last_result = original["result"]; Game.screen_params = original["params"]; Game.main = original["main"]; Game._active_screen = original["screen"]
	Game.provisions = original["provisions"]; Game.rations = original["rations"]; Game.food_clock = original["clock"]; Game.rng.state = original["rng"]
	Game._deploy_rev = original["deploy_rev"]; Game._deploy_key = original["deploy_key"]; Game._deploy_cache = original["deploy_cache"]
	Unit._next_uid = original["unit"]; Item._next_uid = original["item"]
	Records.last_tab = original["tabs"]; Records.last_town = original["town"]
	WorldGen.W = original["wg"][0]; WorldGen.H = original["wg"][1]; WorldGen.K = original["wg"][2]; WorldGen.TF = original["wg"][3]; WorldGen.KD = original["wg"][4]
	if report_dir != "": tree.root.size = original["size"]
	native = {}; public = []; band = {}; guards = {}; fixture = null; original = {}; probe.queue_free(); probe = null
	var fit_failures: int = int(fit.fails); fit.tree = null; fit = null; await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before,"records controls leave no new orphan nodes")
	if report_dir != "":
		check(captures.size() == 27,"six native tabs plus three linked details captured at three desktop sizes")
		var file: FileAccess = FileAccess.open(report_dir.path_join("records-ui.json"),FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":fails+fit_failures,"desktop_fit_cases":fit_cases,"captures":captures,"duration_us":Time.get_ticks_usec()-started,
				"sizes":[[1280,720],[1920,1080],[2560,1440]],"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x<0,"no_phone_qa":true,"performance_panel":true,"native_fixture":true},"\t",true,true)); file.close()
		else: check(false,"private Records report writable")
	print("Records UI v018: ",checks," assertions, ",fit_cases," desktop fit cases; failures=",fails+fit_failures)
	tree = null
	return fails+fit_failures
