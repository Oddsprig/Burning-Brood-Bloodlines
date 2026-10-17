extends RefCounted
## Small native mobilisation fixture, real commands, optional private desktop PNGs.
const WINDOWS := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
const HealthUtil = preload("res://tests/health_util.gd")
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
	if not ok: fails += 1; printerr("FAIL muster UI: ",why)

func settle() -> void:
	for _i in 5: await tree.process_frame

static func labels(node: Node) -> String:
	if node == null: return ""
	var text: String = (node as Label).text+"\n" if node is Label else ""
	for child: Node in node.get_children(): text += labels(child)
	return text

static func snapshot() -> String:
	return JSON.stringify({"state":Game._save_tree(),"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid},"",true,true).sha256_text()

func fit_check(fit: RefCounted, viewport: SubViewport, size: Vector2i, state: String) -> void:
	fit_cases += 1
	fit._check(viewport,Vector2(size),"v017 "+state)

static func width_metrics(page: MusterView) -> Dictionary:
	var scroll: ScrollContainer = page.find_child("MusterScroll",true,false)
	var scrollbar: VScrollBar = scroll.get_v_scroll_bar()
	var padding: Vector2 = scroll.get_theme_stylebox("panel").get_minimum_size()
	var available: float = scroll.size.x - padding.x - (scrollbar.size.x if scrollbar.visible else 0.0)
	var card: PanelContainer = page.find_child("MusterSettlementCard",true,false)
	return {"body_width":page.body.size.x,"scroll_width":scroll.size.x,"scroll_content_width":available,
		"story_width":page.cost_label.size.x,"story_available":card.size.x-card.get_theme_stylebox("panel").get_minimum_size().x}

func width_check(page: MusterView, size: Vector2i, state: String) -> void:
	var metric: Dictionary = width_metrics(page)
	var context: String = "%dx%d %s" % [size.x,size.y,state]
	check(float(metric["body_width"]) >= float(metric["scroll_content_width"])-2.0,"%s Army column fills actual scroll content: body %.1f, available %.1f" % [context,metric["body_width"],metric["scroll_content_width"]])
	check(float(metric["story_width"]) >= float(metric["story_available"])-2.0 and float(metric["story_width"]) >= 700.0,"%s Army quote has readable full card width: story %.1f, available %.1f" % [context,metric["story_width"],metric["story_available"]])

func capture(viewport: SubViewport, size: Vector2i, state: String) -> void:
	if report_dir == "": return
	for node: Node in viewport.find_children("*","",true,false):
		if node is PerformancePanel: (node as PerformancePanel)._refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path: String = report_dir.path_join("army_%dx%d_%s.png" % [size.x,size.y,state])
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == size,"native Army rendered dimensions "+state)
	var saved: bool = image != null and image.save_png(path) == OK
	check(saved,"private native Army PNG "+state)
	var page: MusterView = viewport.find_child("Muster",true,false)
	captures.append({"path":path,"sha256":FileAccess.get_sha256(path) if saved else "","size":[size.x,size.y],"state":state,"widths":width_metrics(page) if page != null else {}})

func cancel(page: Node) -> void:
	var button: Button = page.find_child("MusterCancel",true,false)
	check(button != null,"review provides reachable Cancel")
	if button != null: button.pressed.emit()
	await settle()

func confirm(page: Node) -> void:
	var button: Button = page.find_child("MusterConfirm",true,false)
	check(button != null,"review provides explicit Confirm")
	if button != null: button.pressed.emit()
	Game.wait_save()
	await settle()

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	Game.wait_save()
	var started: int = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	if report_dir != "":
		check(report_dir.is_absolute_path() and report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v017-ui-render/"),"private Army report path")
		check(DisplayServer.get_name() != "headless","native renderer required for requested PNGs")
		if fails > 0: tree = null; return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("muster-ui.json")),"fresh Army capture directory")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.visible = true
		check(tree.root.get_flag(Window.FLAG_NO_FOCUS) and tree.root.position.x < 0,"Army render stays no-focus/offscreen")
	check(ResourceLoader.exists("res://tests/test_mobilization_v017.gd"),"small native backend fixture saved")
	if fails > 0: tree = null; return fails
	var fixture: RefCounted = load("res://tests/test_mobilization_v017.gd").new()
	var original: Dictionary = {"world":Game.world,"company":Game.company,"stash":Game.stash,"squads":Game.squads,"gold":Game.gold,"day":Game.day,
		"location":Game.location,"contract":Game.contract,"pending":Game.pending_battle,"result":Game.last_result,"params":Game.screen_params,"main":Game.main,
		"screen":Game._active_screen,"provisions":Game.provisions,"rations":Game.rations,"clock":Game.food_clock,"rng":Game.rng.state,
		"unit":Unit._next_uid,"item":Item._next_uid,"size":tree.root.size,"deploy_rev":Game._deploy_rev,"deploy_key":Game._deploy_key,"deploy_cache":Game._deploy_cache,
		"wg":[WorldGen.W,WorldGen.H,WorldGen.K,WorldGen.TF,WorldGen.KD]}
	# Fixture clears some collections. Detach their owners before it runs.
	Game.world = {}; Game.company = []; Game.stash = []; Game.squads = {}; Game.contract = {}; Game.pending_battle = {}; Game.last_result = {}
	Game.provisions = {"meal":[],"beer":[],"wine":[]}; Game.food_clock = {}; Game.rations = {"food":"normal","drink":"ration"}
	Game._deploy_key = []; Game._deploy_cache = []
	var probe := RouteProbe.new(); tree.root.add_child(probe); Game.main = probe
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for size: Vector2i in WINDOWS:
		fixture.fixture(Game)
		var total_people: int = fixture.population()
		var total_coins: float = fixture.coins()
		Game._active_screen = "muster"
		Game.screen_params = {"back":"map","back_params":{"sentinel":true}}
		if report_dir != "": tree.root.size = size
		var viewport := SubViewport.new(); viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var panel_layer := CanvasLayer.new(); panel_layer.layer = 100; viewport.add_child(panel_layer)
		var performance := PerformancePanel.new(); performance.setup(Perf); panel_layer.add_child(performance)
		var before: String = snapshot()
		var page: MusterView = (load("res://ui/muster.tscn") as PackedScene).instantiate(); viewport.add_child(page)
		await settle()
		check(page.get_global_rect().position.is_equal_approx(Vector2.ZERO) and page.size.is_equal_approx(Vector2(size)),"%dx%d native Army scene fills actual viewport" % [size.x,size.y])
		var title: Label = page.find_child("Title",true,false)
		var title_width: float = title.get_theme_font("font").get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size")).x
		check(title.text == "Army" and title.size.x >= title_width,"%dx%d actual Army title fits resolved font: allocated %.1f, text %.1f" % [size.x,size.y,title.size.x,title_width])
		check(Game.company.is_empty() and snapshot() == before,"opening Army raises no free people/kit/coin")
		check("not raised" in page.state_label.text and "House purse" in labels(page) and "Army purse" in labels(page),"unraised state and actual separate account owners")
		check(page.current_status == Mobilization.status(Game) and page.current_quote == Mobilization.quote(Game,page.town_id,int(page.count_input.value)),"current native status and quote are displayed exactly")
		check("meals" in page.limits_label.text and "a day in pay" in page.cost_label.text and "Raising costs" in page.cost_label.text,"native kit/meal/pay costs are explained")
		width_check(page,size,"unraised")
		fit_check(fit,viewport,size,"unraised Army")
		await capture(viewport,size,"unraised")
		var empty_company: Control = (load("res://ui/company.tscn") as PackedScene).instantiate(); viewport.add_child(empty_company)
		await settle()
		check(empty_company.find_child("CompanyUnraised",true,false) != null and empty_company.find_child("CompanyRaiseArmy",true,false) != null and not Game.is_game_over(),"empty native company offers muster instead of defeat")
		empty_company._open_muster()
		check(Game._active_screen == "muster" and Game.screen_params["back"] == "company","empty company opens the actual Army route")
		Game.screen_params = {"back":"map","back_params":{"sentinel":true}}
		empty_company.queue_free(); empty_company = null; await settle()
		var count_control: SpinBox = page.count_input
		page.count_input.value = 2
		await settle()
		check(page.count_input == count_control and int(page.current_quote["requested"]) == 2 and snapshot() == before,"amount editing keeps control and all native data unchanged")
		# Explicit funding is a separate real private-to-army transfer.
		page.fund_input.value = 1000000
		await settle()
		var funds: Dictionary = Mobilization.status(Game)
		page.request_funding()
		await settle()
		check("house purse" in labels(page.find_child("Modal",true,false)) and "army purse" in labels(page.find_child("Modal",true,false)),"funding confirmation names both real owners")
		await cancel(page)
		check(snapshot() == before,"funding preview and Cancel preserve all native state")
		page.request_funding(); await settle(); await confirm(page)
		var funded: Dictionary = Mobilization.status(Game)
		check(int(funded["army_gold"]) == int(funds["army_gold"])+1000000 and is_equal_approx(float(funded["payer_purse"]),float(funds["payer_purse"])-1000000),"confirmed house-to-army funding conserves actual coins")
		# A vanished current house cannot redirect a reviewed funding command.
		page.request_funding(); await settle()
		var selection: Dictionary = Game.world["player_house"]
		Game.world["player_house"] = {}
		var stale_before: String = snapshot()
		await confirm(page)
		check(snapshot() == stale_before and "changed" in page.notice,"funding rejects stale household/ruler without native mutation")
		Game.world["player_house"] = selection; page._refresh()
		page.count_input.value = 200
		await settle()
		var quote: Dictionary = page.current_quote.duplicate(true)
		check(bool(quote["ok"]) and int(quote["planned"]) > 0 and int(quote["planned"]) < int(quote["requested"]),"native small fixture supplies a genuine partial muster")
		before = snapshot()
		page.request_raise(); await settle()
		check("army purse" in labels(page.find_child("Modal",true,false)) and "not charged by this order" in labels(page.find_child("Modal",true,false)),"raising review distinguishes army cost from private purse")
		fit_check(fit,viewport,size,"raise confirmation")
		width_check(page,size,"raise confirmation")
		await capture(viewport,size,"raise_confirmation")
		await cancel(page)
		check(snapshot() == before,"raising preview and Cancel are pure")
		page.request_raise(); await settle()
		var purse: int = Game.gold; Game.gold = 0
		stale_before = snapshot()
		await confirm(page)
		check(snapshot() == stale_before and Game.company.is_empty(),"raise confirmation rejects depleted army purse")
		Game.gold = purse; page._refresh()
		page.request_raise(); await settle(); await confirm(page)
		check(Game.company.size() == int(quote["planned"]) and "partial raising" in page.notice,"accepted partial count is actual, not requested quota")
		check(Game.gold == purse-int(quote["raise_cost"]),"actual raising cost is paid exactly once")
		check(int(page.count_input.max_value) == Mobilization.LIMIT-Game.company.size(),"additional selector respects total200 capacity")
		check(int(page.current_status["alive"]) == Game.company.size() and float(page.current_status["daily_pay"]) == Game.daily_wages(),"raised roster/pay state is authoritative")
		fit_check(fit,viewport,size,"raised Army")
		width_check(page,size,"raised")
		await capture(viewport,size,"raised")
		var raised: Array = Game.company.duplicate()
		HealthUtil.wound(raised[0],"arm_upper_l","skin","bruised",0.1)
		check(not (raised[0] as Unit).body.parts.is_empty(),"stand-down fixture includes an actual stored native wound")
		var units: Dictionary = {}
		for unit: Unit in raised: units[unit.uid] = {"instance":unit.get_instance_id(),"body":JSON.stringify(unit.body.to_dict(),"",true,true),"name":unit.name}
		page.request_stand_down(); await settle()
		fit_check(fit,viewport,size,"stand-down confirmation")
		width_check(page,size,"stand-down confirmation")
		await capture(viewport,size,"stand_down_confirmation")
		before = snapshot()
		await cancel(page)
		check(snapshot() == before,"stand-down review and Cancel preserve body/equipment/payroll")
		var location: String = Game.location
		var pos: Vector2 = Game.world["party"]["pos"]
		Game.location = ""; Game.world["party"]["pos"] = pos+Vector2(1000,0)
		stale_before = snapshot()
		var rejected: Dictionary = page.apply_stand_down(page.town_id,Mobilization.stand_down_quote(Game,page.town_id)["review"])
		check(not bool(rejected["ok"]) and snapshot() == stale_before,"away stand-down is rejected without teleport or discarded troops")
		Game.location = location; Game.world["party"]["pos"] = pos; page._refresh()
		page.request_stand_down(); await settle(); await confirm(page)
		check(Game.company.is_empty() and Game.daily_wages() == 0 and "not raised" in page.state_label.text,"living people stand down and field payroll stops")
		check(fixture.population() == total_people and is_equal_approx(fixture.coins(),total_coins),"UI raising/stand-down conserve actual people and all owner accounts")
		for unit: Unit in raised:
			check(Mobilization.reserves(Game).has(unit) and unit.get_instance_id() == units[unit.uid]["instance"] and unit.name == units[unit.uid]["name"] and JSON.stringify(unit.body.to_dict(),"",true,true) == units[unit.uid]["body"],"returned identity/body stays the actual person %d" % unit.uid)
		fit_check(fit,viewport,size,"stood-down Army")
		width_check(page,size,"stood-down")
		await capture(viewport,size,"stood_down")
		var reraised: Dictionary = Mobilization.quote(Game,page.town_id,raised.size())
		check(int(reraised["reserve_available"]) >= raised.size(),"actual home reserve remains available without duplicate population")
		var again: Dictionary = page.apply_raise(page.town_id,raised.size(),reraised["review"])
		Game.wait_save(); await settle()
		check(bool(again["ok"]) and Game.company.size() == raised.size(),"actual reserves can be reraised")
		check(fixture.population() == total_people and is_equal_approx(fixture.coins(),total_coins),"reraise does not duplicate native population or coin")
		for unit: Unit in raised: check(Game.company.has(unit),"reraise retains original Unit instance %d" % unit.uid)
		page._roster()
		check(Game._active_screen == "company" and Game.screen_params["back"] == "muster","real roster/gear link retains Army context")
		var company: Control = (load("res://ui/company.tscn") as PackedScene).instantiate(); viewport.add_child(company)
		await settle()
		check(company.find_child("CompanyArmy",true,false) != null and company.find_child("RosterName",true,false) != null,"native company roster remains usable after raising")
		var member: Unit = Game.company[0]
		check("owned kit" in company.dismissal_text(member) and "stash" not in company.dismissal_text(member),"registered dismissal explains actual home return rather than stripping kit")
		var selected: int = int(company.selected_uid)
		Game.location = ""; Game.world["party"]["pos"] = pos+Vector2(1000,0)
		stale_before = snapshot()
		var dismissal_error: String = company._dismiss(member)
		check(dismissal_error != "" and company.selected_uid == selected and snapshot() == stale_before,"remote dismissal reports error, retains selection/person/gear/body")
		check(company.get_node_or_null("Toast") != null,"native dismissal error is actually visible")
		Game.location = location; Game.world["party"]["pos"] = pos
		check(company._dismiss(member) == "" and not Game.company.has(member) and Mobilization.reserves(Game).has(member),"permitted UI dismissal returns actual person safely")
		Game.wait_save(); await settle()
		check(JSON.stringify(member.body.to_dict(),"",true,true) == units[member.uid]["body"] and fixture.population() == total_people and is_equal_approx(fixture.coins(),total_coins),"UI dismissal preserves native injury and all people/accounts")
		member = null
		company._back()
		check(Game._active_screen == "muster" and Game.screen_params["town_id"] == page.town_id,"company Back restores Army context")
		company.queue_free(); company = null; await settle()
		page._back()
		check(Game._active_screen == "map" and Game.screen_params.get("sentinel",false) and Game.location == location and Game.world["party"]["pos"] == pos,"Army Back preserves original route without travel")
		viewport.queue_free(); page = null; viewport = null; performance = null; panel_layer = null; count_control = null
		raised = []; units = {}; await settle()
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
	var fit_failures: int = int(fit.fails); fit.tree = null; fit = null
	await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before,"Army views/modals leave no new orphan controls")
	if report_dir != "":
		check(captures.size() == 15,"all five Army states at three desktop sizes captured")
		var file: FileAccess = FileAccess.open(report_dir.path_join("muster-ui.json"),FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":fails+fit_failures,"desktop_fit_cases":fit_cases,"captures":captures,
				"sizes":[[1280,720],[1920,1080],[2560,1440]],"duration_us":Time.get_ticks_usec()-started,"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x<0,"no_phone_qa":true,"performance_panel":true},"\t",true,true)); file.close()
		else: check(false,"private Army report writable")
	print("Muster UI v017: ",checks," assertions, ",fit_cases," desktop fit cases; failures=",fails+fit_failures)
	tree = null
	return fails+fit_failures
