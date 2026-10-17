extends RefCounted
## Actual native towns/houses, staged command purity, bounded rows and desktop pixels.
const WINDOWS := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0
var report_dir: String = ""
var captures: Array = []

class RouteProbe extends Node:
	var path: String = ""
	func show_screen(value: String) -> void: path = value

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL house selection UI: ",reason)

func settle() -> void:
	for _i in 5: await tree.process_frame

static func fingerprint() -> String:
	return JSON.stringify({"state":Game._save_tree(),"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid},"",true,true).sha256_text()

func fit_check(fit: RefCounted, viewport: SubViewport, page: HouseSelectView, dimensions: Vector2i, state: String) -> void:
	fit_cases += 1
	var context: String = "%dx%d %s" % [dimensions.x,dimensions.y,state]
	fit._check(viewport,Vector2(dimensions),"v019 "+context)
	check(page.size.is_equal_approx(Vector2(dimensions)),context+" actual native scene fills viewport")
	check(page.map_view.visible and page.map_view.size.x >= 400 and page.map_view.size.y >= 220,context+" persistent map has usable area")
	check(page.workspace.get_global_rect().end.x <= dimensions.x-UiKit.diagnostics_lane(dimensions.x),context+" workspace leaves diagnostics lane")
	check(page.next_button.get_global_rect().end.y <= dimensions.y and page.back_button.get_global_rect().end.y <= dimensions.y,context+" explicit footer actions reachable")
	var title: Label = page.find_child("Title",true,false)
	var width: float = title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size")).x
	check(title.size.x >= width,context+" complete header fits bundled font")
	var scroll: ScrollContainer = page.find_child("OnboardingListScroll",true,false)
	var available: float = scroll.size.x-(scroll.get_v_scroll_bar().size.x if scroll.get_v_scroll_bar().visible else 0.0)
	check(page.list.size.x >= available-2 and page.list.size.x >= 330,context+" list/editor fills real scroll width")
	var rows: Array = page.list.get_children().filter(func(row): return row.has_meta("onboarding_uid"))
	check(rows.size() <= HouseSelectView.PAGE_SIZE,context+" only one bounded native list page")
	for row: RecRow in rows:
		check(row.size.y >= 48 and row.lines[2].width >= 300,context+" native house/settlement story is readable")
		check(row.size.x >= page.list.size.x-2,context+" each native row uses full column")
	check(page.map_view.texture_builds == 1,context+" map texture is reused across selection/stages")
	check(not page.map_view.is_processing(),context+" geography preview starts no campaign process")

func capture(viewport: SubViewport, page: HouseSelectView, dimensions: Vector2i, state: String) -> void:
	if report_dir == "": return
	for node: Node in viewport.find_children("*","",true,false):
		if node is PerformancePanel: (node as PerformancePanel)._refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path: String = report_dir.path_join("onboarding_%dx%d_%s.png" % [dimensions.x,dimensions.y,state])
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == dimensions,"native onboarding image dimensions "+state)
	var saved: bool = image != null and image.save_png(path) == OK
	check(saved,"private native onboarding PNG "+state)
	captures.append({"path":path,"sha256":FileAccess.get_sha256(path) if saved else "","size":[dimensions.x,dimensions.y],"state":state,
		"map_size":[page.map_view.size.x,page.map_view.size.y],"list_width":page.list.size.x,"stage":page.stage,"selected_town":page.selected_town})

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree; await tree.process_frame; Game.wait_save()
	var started: int = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report-dir="): report_dir = argument.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	if report_dir != "":
		check(report_dir.is_absolute_path() and report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v019-ui-render/"),"private onboarding output directory")
		check(DisplayServer.get_name() != "headless","requested images use actual native renderer")
		if fails > 0: tree = null; return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("house-selection-ui.json")),"fresh private onboarding output")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.visible = true
	var original: Dictionary = {"world":Game.world,"company":Game.company,"stash":Game.stash,"squads":Game.squads,"gold":Game.gold,"day":Game.day,
		"location":Game.location,"contract":Game.contract,"pending":Game.pending_battle,"result":Game.last_result,"params":Game.screen_params,"main":Game.main,
		"screen":Game._active_screen,"provisions":Game.provisions,"rations":Game.rations,"clock":Game.food_clock,"rng":Game.rng.state,
		"unit":Unit._next_uid,"item":Item._next_uid,"size":tree.root.size,"deploy_rev":Game._deploy_rev,"deploy_key":Game._deploy_key,"deploy_cache":Game._deploy_cache,
		"wg":[WorldGen.W,WorldGen.H,WorldGen.K,WorldGen.TF,WorldGen.KD]}
	Game.world = {}; Game.company = []; Game.stash = []; Game.squads = {}; Game.contract = {}; Game.pending_battle = {}; Game.last_result = {}
	Game.provisions = {"meal":[],"beer":[],"wine":[]}; Game.food_clock = {}; Game.rations = {"food":"normal","drink":"ration"}; Game._deploy_key = []; Game._deploy_cache = []
	var probe := RouteProbe.new(); tree.root.add_child(probe); Game.main = probe
	var fixture: RefCounted = load("res://tests/test_dynasty_foundation.gd").new()
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for dimensions: Vector2i in WINDOWS:
		fixture.fixture(); Feudal.prepare_world(Game); Game.gold = 0; Game.world.erase("player_house")
		Game._active_screen = "house_select"; Game.screen_params = {}
		var before: String = fingerprint()
		if report_dir != "": tree.root.size = dimensions
		var viewport := SubViewport.new(); viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
		var performance := PerformancePanel.new(); performance.setup(Perf); layer.add_child(performance)
		var page: HouseSelectView = (load("res://ui/house_select.tscn") as PackedScene).instantiate(); viewport.add_child(page); await settle()
		check(page.stage == 0 and page.next_button.disabled and page.review.is_empty(),"settlement first; Begin has no automatic selection")
		check(fingerprint() == before,"opening chooser changes no native state/RNG/UIDs")
		check(page.settlement_rows == HouseOnboarding.settlements(Game),"settlement rows are exact current native API values")
		fit_check(fit,viewport,page,dimensions,"settlements"); await capture(viewport,page,dimensions,"settlements")
		var tid: String = String(page.settlement_rows[0]["town_id"])
		var town: Dictionary = Game.world["towns"][tid]
		check(page.map_view.world_extent == Vector2(Game.world["w"],Game.world["h"])*float(Game.world["cell"]),"map uses actual native extent")
		var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true; click.position = page.map_view.position_for(town["pos"])
		page.map_view._gui_input(click); await settle()
		check(page.selected_town == tid and page.map_view.selected_town == tid and String(town["name"]) in page.map_name.text,"click actual coordinate selects and visibly names settlement")
		check(page.map_view.marker_at(click.position) == tid,"actual marker hit target agrees with source location")
		check(fingerprint() == before,"map click only changes view selection")
		page.next_stage(); await settle()
		check(page.stage == 1 and page.house_rows == HouseOnboarding.houses(Game,tid),"local house stage lists exact actual candidates")
		var ordinary: Dictionary = {}; var ruling: Dictionary = {}
		for row: Dictionary in page.house_rows:
			if bool(row["is_ruling"]): ruling = row
			elif ordinary.is_empty(): ordinary = row
		check(not ordinary.is_empty() and not ruling.is_empty(),"native fixture offers both actual ordinary and office households")
		check(page.house_rows.all(func(row): return String(row["town_id"]) == tid),"no remote or anonymous common-folk pool is offered as local house")
		var first_page: Array = page.list.get_children().filter(func(row): return row.has_meta("onboarding_uid")).map(func(row): return row.get_meta("onboarding_uid"))
		if page.house_rows.size() > HouseSelectView.PAGE_SIZE:
			page.following_button.pressed.emit(); await settle()
			var second_page: Array = page.list.get_children().filter(func(row): return row.has_meta("onboarding_uid")).map(func(row): return row.get_meta("onboarding_uid"))
			check(page.page_index == 1 and second_page.all(func(uid): return not first_page.has(uid)),"next page exposes distinct real local identities")
			page.previous_button.pressed.emit(); await settle()
		page.search.text = "no_matching_house_v019"; page.search.text_changed.emit(page.search.text)
		check(page.filtered_rows.is_empty(),"name search has no fabricated matches")
		page.search.text = String(ordinary.get("native_house_name","")); page.search.text_changed.emit(page.search.text)
		check(not page.filtered_rows.is_empty() and page.filtered_rows.all(func(row): return String(row["house_name"]).to_lower().contains(page.search.text.to_lower())),"search filters native house names")
		page.search.text = ""; page.search.text_changed.emit("")
		page.select_house(String(ruling.get("household_uid",""))); await settle()
		check(bool(page.current_preview.get("holds_office",false)) and page.role_label.text.ends_with(String(ruling.get("title",""))),"actual office title appears only for office candidate")
		page.select_house(String(ordinary.get("household_uid",""))); await settle()
		check(not bool(page.current_preview.get("holds_office",true)) and "House leader" in page.role_label.text and "no town lordship" in page.rights_label.text,"ordinary household has honest actual role/rights")
		check(page.person_label.text == ordinary.get("leader_name","") and page.portrait._spec == page.current_preview.get("portrait_spec",{}),"portrait and displayed person match the actual candidate")
		check(page.purse_label.text == "House purse: %s coins" % RecKit.num(float(ordinary.get("house_purse",0))),"native household purse is shown without fictional money")
		fit_check(fit,viewport,page,dimensions,"local_houses"); await capture(viewport,page,dimensions,"local_houses")
		page.next_stage(); await settle()
		check(page.stage == 2 and page.name_input != null,"Customize House is a distinct stage")
		var input_instance: int = page.name_input.get_instance_id()
		page.name_input.text = "[invalid]"; page.name_input.text_changed.emit(page.name_input.text)
		check(page.next_button.disabled and page.review.is_empty(),"invalid customization cannot reach a valid review")
		page.name_input.text = "  River  Lantern  "; page.name_input.text_changed.emit(page.name_input.text)
		page.emblem_input.select(4); page.emblem_input.item_selected.emit(4)
		page.primary_input.select(3); page.primary_input.item_selected.emit(3)
		page.secondary_input.select(1); page.secondary_input.item_selected.emit(1); await settle()
		check(page.name_input.get_instance_id() == input_instance and not page.next_button.disabled,"typing keeps real input control and valid preview")
		check(page.banner.customization == page.custom and page.custom["emblem"] == "leaf" and page.custom["primary_color"] == "#294A76","visible banner follows the actual bounded selectors")
		check(fingerprint() == before,"all selection/search/page/customization previews preserve native world/body/funds/RNG/UIDs")
		fit_check(fit,viewport,page,dimensions,"customize"); await capture(viewport,page,dimensions,"customize")
		page.next_stage(); await settle()
		check(page.stage == 3 and page.next_button.text == "Begin" and page.custom["display_name"] == "River Lantern","explicit review normalizes display name and exposes Begin")
		check(page.review["house"]["leader_uid"] == ordinary["leader_uid"],"review freezes the actual stable person UID")
		check(fingerprint() == before and Game.world.get("player_house",{}).is_empty() and Game.company.is_empty(),"Review does not begin or raise a free army")
		fit_check(fit,viewport,page,dimensions,"review"); await capture(viewport,page,dimensions,"review")
		page.previous_stage(); await settle()
		check(page.stage == 2 and page.review.is_empty() and fingerprint() == before,"Back cancels review without committing native state")
		page.next_stage(); await settle()
		var family: Dictionary = RecData.fam(town["econ"],int(ordinary["family_id"]))
		var pp: Array = family["pp"]
		family["pp"] = pp.filter(func(person): return str(Persons.g(person,Persons.PERSON_UID,"")) != String(ordinary["leader_uid"]))
		var stale_before: String = fingerprint()
		var rejected: Dictionary = page.begin_review(); await settle()
		check(not bool(rejected["ok"]) and page.stage == 1 and not page.notice.is_empty(),"changed actual leader is rejected and visibly requires another review")
		check(fingerprint() == stale_before and Game.world.get("player_house",{}).is_empty(),"stale Begin creates no house/coins/people or extra mutation")
		family["pp"] = pp
		page.select_house(String(ordinary["household_uid"])); page.next_stage(); await settle()
		page.update_customization({"display_name":"River Lantern","emblem":"leaf","primary_color":"#294A76","secondary_color":"#E4C47D"})
		page.next_stage(); await settle()
		var native_econ: String = JSON.stringify(Game.world["towns"],"",true,true)
		var money: float = Barge.holdings(Game); var population: int = fixture.population(); var unit_counter: int = Unit._next_uid; var item_counter: int = Item._next_uid; var rng: int = Game.rng.state
		var begun: Dictionary = page.begin_review(); Game.wait_save(); await settle()
		check(bool(begun["ok"]) and Game._active_screen == "house","explicit Begin enters actual native House route")
		check(Game.world["player_house"]["household_uid"] == ordinary["household_uid"] and Game.world["player_house"]["ruler_uid"] == ordinary["leader_uid"],"Begin selects actual reviewed household/person")
		check(Game.world["player_house"]["customization"] == page.review["customization"] and family["name"] == ordinary["native_house_name"],"saved presentation never renames native property owner")
		check(Game.company.is_empty() and Game.gold == 0 and fixture.population() == population and is_equal_approx(Barge.holdings(Game),money),"Begin preserves unraised army and native people/accounts")
		check(JSON.stringify(Game.world["towns"],"",true,true) == native_econ and Unit._next_uid == unit_counter and Item._next_uid == item_counter and Game.rng.state == rng,"Begin preserves native town/item/body/model state and RNG/UIDs")
		check(Game.location == tid and Game.world["party"]["pos"] == town["pos"],"only explicit Begin puts existing party at actual chosen settlement")
		viewport.queue_free(); page = null; viewport = null; performance = null; layer = null; ordinary = {}; ruling = {}; town = {}; family = {}; pp = []; click = null; await settle()
	Game.wait_save()
	Game.world = original["world"]; Game.company = original["company"]; Game.stash = original["stash"]; Game.squads = original["squads"]
	Game.gold = original["gold"]; Game.day = original["day"]; Game.location = original["location"]; Game.contract = original["contract"]
	Game.pending_battle = original["pending"]; Game.last_result = original["result"]; Game.screen_params = original["params"]; Game.main = original["main"]; Game._active_screen = original["screen"]
	Game.provisions = original["provisions"]; Game.rations = original["rations"]; Game.food_clock = original["clock"]; Game.rng.state = original["rng"]
	Game._deploy_rev = original["deploy_rev"]; Game._deploy_key = original["deploy_key"]; Game._deploy_cache = original["deploy_cache"]
	Unit._next_uid = original["unit"]; Item._next_uid = original["item"]
	WorldGen.W = original["wg"][0]; WorldGen.H = original["wg"][1]; WorldGen.K = original["wg"][2]; WorldGen.TF = original["wg"][3]; WorldGen.KD = original["wg"][4]
	if report_dir != "": tree.root.size = original["size"]
	probe.queue_free(); probe = null; fixture = null; original = {}
	var fit_failures: int = int(fit.fails); fit.tree = null; fit = null; await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before,"chooser/map/banner release controls without new orphan nodes")
	if report_dir != "":
		check(captures.size() == 12,"all four stages captured at all three desktop sizes")
		var file: FileAccess = FileAccess.open(report_dir.path_join("house-selection-ui.json"),FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":fails+fit_failures,"desktop_fit_cases":fit_cases,"captures":captures,"duration_us":Time.get_ticks_usec()-started,
				"sizes":[[1280,720],[1920,1080],[2560,1440]],"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x<0,"no_phone_qa":true,"performance_panel":true,"native_fixture":true},"\t",true,true)); file.close()
		else: check(false,"private onboarding report writable")
	print("House selection UI v019: ",checks," assertions, ",fit_cases," desktop fit cases; failures=",fails+fit_failures)
	tree = null
	return fails+fit_failures