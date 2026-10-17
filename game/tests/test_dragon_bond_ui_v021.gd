extends RefCounted
## Actual native identities, reviewed relationship orders and desktop-only UI.
const WINDOWS := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0
var report_dir: String = ""
var captures: Array = []

class RouteProbe extends Node:
	var path: String = ""
	var changes: int = 0
	func show_screen(value: String) -> void: path = value
	func changed() -> void: changes += 1

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon bond UI: ",why)

func settle() -> void:
	for _i in 5: await tree.process_frame

static func words(node: Node) -> String:
	var text: String = node.text+"\n" if node is Label or node is Button else ""
	for child: Node in node.get_children(): text += words(child)
	return text

static func find(node: Node, name: String) -> Control:
	return node.find_child(name,true,false) as Control

static func button_text(node: Node, text: String) -> Button:
	for child: Node in node.find_children("*","Button",true,false):
		if (child as Button).text == text: return child
	return null

static func source_fields(row: Dictionary) -> Dictionary:
	var copy: Dictionary = row.duplicate(true)
	for key: String in ["rider_person_uid","bond_day","history","last_rider_person_uid","last_separation_reason"]: copy.erase(key)
	return copy

static func rider_spec(unit: Unit) -> Dictionary:
	# Dynasty uses the actual saved model/equipment and adds only its portrait role.
	var spec: Dictionary = FigurePainter.spec_for_unit(unit)
	spec["role"] = "ruler"
	return spec

func fit_check(fit: RefCounted, viewport: SubViewport, page: DragonsView, size: Vector2i, state: String) -> void:
	fit_cases += 1
	var context: String = "%dx%d %s" % [size.x,size.y,state]
	fit._check(viewport,Vector2(size),"v021 "+context)
	check(page.size.is_equal_approx(Vector2(size)),context+" actual packed scene fills the viewport")
	check(page.body.size.x >= size.x-UiKit.diagnostics_lane(size.x)-100,context+" detail column has actual usable width")
	check(page.body.get_global_rect().end.x <= size.x-UiKit.diagnostics_lane(size.x)+1,context+" diagnostics lane stays free")
	var panel: Control = find(page,"DragonBondPanel")
	check(panel != null and panel.size.x >= page.body.size.x-2,context+" real bond panel fills the detail width")
	for name: String in ["DragonBindRider","DragonReleaseBond"]:
		var button: Button = find(page,name) as Button
		check(button != null and button.size.y >= 48 and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),context+" "+name+" is readable and reachable")
	var label: Label = find(page,"DragonRiderStatus") as Label
	check(label != null and label.get_theme_font("font") == UiTheme.regular_font(),context+" rider status uses the bundled font")
	if not page._bond_picker.is_empty():
		var rows: VBoxContainer = page._bond_picker["rows"]
		var scroll: ScrollContainer = find(page,"BondCandidatesScroll") as ScrollContainer
		check(rows.get_child_count() <= DragonsView.BOND_PAGE_SIZE+1,context+" candidate controls are bounded to one8-person page")
		check(rows.size.x >= scroll.size.x-20 and rows.size.x >= 500,context+" candidate rows expand to available scroll width")
		for row: Control in rows.get_children():
			check(row.size.x >= rows.size.x-2,context+" native candidate row uses full width")
		var modal: VBoxContainer = page._bond_picker["modal"]
		var outer: ScrollContainer = modal.get_parent().get_parent()
		for name: String in ["BondCandidatesPrevious","BondCandidatesNext","BondPickerCancel","BondReviewPerson"]:
			var action: Control = find(page,name)
			check(action != null and outer.get_global_rect().encloses(action.get_global_rect()),context+" complete "+name+" is visible outside the candidate scroll")
	for name: String in ["BondReviewContent"]:
		var review: Control = find(page,name)
		if review != null:
			var outer: ScrollContainer = review.get_parent().get_parent()
			for action: Control in review.find_children("Bond*","Button",true,false):
				check(outer.get_global_rect().encloses(action.get_global_rect()),context+" review action is wholly visible")

func capture(viewport: SubViewport, size: Vector2i, state: String) -> void:
	if report_dir == "": return
	for node: Node in viewport.find_children("*","",true,false):
		if node is PerformancePanel: (node as PerformancePanel)._refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path: String = report_dir.path_join("bond_%dx%d_%s.png" % [size.x,size.y,state])
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == size,"native bond image dimensions "+state)
	var saved: bool = image != null and image.save_png(path) == OK
	check(saved,"private native bond PNG "+state)
	captures.append({"path":path,"sha256":FileAccess.get_sha256(path) if saved else "","size":[size.x,size.y],"state":state})

func search(page: DragonsView, query: String) -> void:
	var editor: LineEdit = page._bond_picker["search"]
	editor.text = query; editor.text_changed.emit(query)

func page_ids(page: DragonsView) -> Array:
	var ids: Array = []
	for node: Node in (page._bond_picker["rows"] as VBoxContainer).get_children():
		if node.has_meta("bond_person_uid"): ids.append(node.get_meta("bond_person_uid"))
	return ids

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree; await tree.process_frame; Game.wait_save()
	var started: int = Time.get_ticks_usec()
	var window_state: Dictionary = {"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"position":tree.root.position,"visible":tree.root.visible}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	if report_dir != "":
		check(report_dir.is_absolute_path() and report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v021-ui-render/"),"private bond report directory")
		check(DisplayServer.get_name() != "headless","captures require the actual native renderer")
		if fails > 0: tree = null; return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("dragon-bond-ui.json")),"fresh private bond report")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.visible = true
	var original: Dictionary = {"world":Game.world,"company":Game.company,"stash":Game.stash,"squads":Game.squads,"gold":Game.gold,"day":Game.day,
		"location":Game.location,"contract":Game.contract,"pending":Game.pending_battle,"result":Game.last_result,"params":Game.screen_params,"main":Game.main,
		"screen":Game._active_screen,"provisions":Game.provisions,"rations":Game.rations,"clock":Game.food_clock,"rng":Game.rng.state,
		"unit":Unit._next_uid,"item":Item._next_uid,"size":tree.root.size,"no_focus":window_state["no_focus"],"position":window_state["position"],"visible":window_state["visible"],
		"deploy_rev":Game._deploy_rev,"deploy_key":Game._deploy_key,"deploy_cache":Game._deploy_cache,"save_ready":Game._save_ready,
		"wg":[WorldGen.W,WorldGen.H,WorldGen.K,WorldGen.TF,WorldGen.KD]}
	Game.world = {}; Game.company = []; Game.stash = []; Game.squads = {}; Game.contract = {}; Game.pending_battle = {}; Game.last_result = {}
	Game.provisions = {"meal":[],"beer":[],"wine":[]}; Game.food_clock = {}; Game.rations = {"food":"normal","drink":"ration"}; Game._deploy_key = []; Game._deploy_cache = []
	Game._save_ready = true; Game._active_screen = "dragons"
	var probe := RouteProbe.new(); tree.root.add_child(probe); Game.main = probe; Game.changed.connect(probe.changed)
	var fixture: RefCounted = load("res://tests/test_dragon_bond_v021.gd").new()
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for size: Vector2i in WINDOWS:
		if report_dir != "": tree.root.size = size
		fixture.fixture()
		var e: Dictionary = Game.world["towns"]["a"]["econ"]; var family: Dictionary = e["fams"][0]
		for i: int in 15: fixture.native.person(e,family,100+i,i%2,30+i,"Bond candidate %02d" % i)
		var loc: Dictionary = Dynasty._person(Game,fixture.adult_uid)
		var unit: Unit = Unit.create(String(Persons.race_of(loc["econ"])),"player"); unit.home_town = "a"
		Persons.bind(loc["econ"],loc["family"],loc["person"],unit,"company",Game.day); Game.company.append(unit)
		var helmet: Item = Item.make("closed_helm","bronze",2); helmet.mark = {"n":"Actual fixture forge","r":"dwarf","t":"fixture"}; unit.equip["helm"] = helmet
		unit.look = {"beard":true,"beard_style":2,"female_set":1,"seed":721}
		Game.screen_params = {"back":"house","back_params":{"origin":"bond_ui"},"dragon_uid":fixture.dragon_uid}
		probe.changes = 0
		var viewport := SubViewport.new(); viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
		var perf := PerformancePanel.new(); perf.setup(Perf); layer.add_child(perf)
		var before: String = fixture.snapshot()
		var native_before: String = fixture.native_snapshot()
		var independent: Dictionary = source_fields(fixture.row())
		var page: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate(); viewport.add_child(page)
		await settle()
		check(fixture.snapshot() == before,"opening actual holdings/detail never reconciles bodies, funds, RNG or IDs")
		check(probe.changes == 0,"pure detail emits no changes")
		check("Unbonded · No rider" in words(page) and not (find(page,"DragonBindRider") as Button).disabled,"actual adult is unbonded and available at owner home")
		check(page.model_rider.is_empty() and page.model_card.rider_spec.is_empty() and "Saddle close-up" not in words(page),"no sampled Unit impersonates an actual rider")
		check("Owner:" in words(find(page,"DragonBondPanel")) and "Custodian:" in words(find(page,"DragonBondPanel")) and "Location:" in words(find(page,"DragonBondPanel")),"ownership, care and location are separate from bond")
		fit_check(fit,viewport,page,size,"unbonded"); await capture(viewport,size,"unbonded")
		page._open_bond_picker(fixture.dragon_uid); await settle()
		var people: Array = page._bond_picker["people"]
		var ids: Array = people.map(func(person: Dictionary): return String(person["person_uid"]))
		check(people == DragonBond.candidates(Game,fixture.dragon_uid) and ids.size() > 8,"picker reads actual eligible native candidates")
		check(ids.has(fixture.adult_uid) and ids.has(fixture.namesake_uid) and not ids.has(fixture.child_uid) and not ids.has(fixture.cohort_uid),"same-name identities remain distinct; minors and pools excluded")
		var first: Array = page_ids(page); page._turn_bond_page(1); await settle()
		check(first.size() == 8 and page_ids(page).size() <= 8 and not page_ids(page).any(func(id): return first.has(id)),"next page is distinct and bounded")
		search(page,"Shared name"); await settle()
		check(page_ids(page).size() == 2 and page_ids(page).has(fixture.adult_uid) and page_ids(page).has(fixture.namesake_uid),"name search selects actual duplicate-name native identities without conflation")
		page._pick_bond_candidate(fixture.adult_uid); await settle()
		var review: Dictionary = page._bond_picker["review"]
		check(review == DragonBond.bind_preview(Game,fixture.dragon_uid,fixture.adult_uid),"selected review is the entire actual authoritative preview")
		var portrait: Portrait = find(page,"BondCandidatePortrait") as Portrait
		check(portrait != null and portrait.visible and portrait.unit == null and portrait._spec == Dynasty.portrait_for(Game,review["recipient"]),"candidate portrait is pure actual registered identity")
		check(portrait._spec == rider_spec(unit),"bound native helmet, maker and saved appearance exactly match actual Unit portrait")
		search(page,"No actual name matches this"); await settle()
		check((page._bond_picker["matched"] as Array).is_empty() and (page._bond_picker["review"] as Dictionary).is_empty() and (find(page,"BondReviewPerson") as Button).disabled,"new search clears stale selection and review honestly")
		search(page,""); page._pick_bond_candidate(fixture.adult_uid); await settle()
		fit_check(fit,viewport,page,size,"picker"); await capture(viewport,size,"picker")
		check(fixture.snapshot() == before,"paging/search/portrait/native review never creates people, Units, gear or money")
		var save_count: int = int(Game.save_stats().get("started",0))
		page._review_bond_candidate(); await settle()
		check(page._bond_picker.is_empty(),"review discards candidate rows and cached people")
		var text: String = words(find(page,"BondReviewContent"))
		check("Shared name" in text and "Owner remains" in text and "Custodian remains" in text and "Location remains" in text,"review shows exact person and unchanged asset relationships")
		fit_check(fit,viewport,page,size,"bind_review"); await capture(viewport,size,"bind_review")
		(find(page,"BondReviewCancel") as Button).pressed.emit(); await settle()
		check(fixture.snapshot() == before and probe.changes == 0 and int(Game.save_stats().get("started",0)) == save_count,"Cancel is pure and makes no save or change event")
		page._request_bond(fixture.dragon_uid,"bind",fixture.adult_uid); await settle()
		var old_keeper: String = String(fixture.row()["custodian_person_uid"]); fixture.row()["custodian_person_uid"] = fixture.namesake_uid
		var stale: String = fixture.snapshot()
		(find(page,"BondConfirmBind") as Button).pressed.emit(); await settle()
		check(fixture.snapshot() == stale and probe.changes == 0 and int(Game.save_stats().get("started",0)) == save_count,"changed source invalidates displayed confirmation without signal/save/mutation")
		check(page.notice != "" and String(fixture.row()["rider_person_uid"]) == "","stale rejection is visible and does not fabricate a bond")
		fixture.row()["custodian_person_uid"] = old_keeper
		page._request_bond(fixture.dragon_uid,"bind",fixture.adult_uid); await settle()
		var unchanged_world: Dictionary = Game.world.duplicate(true)
		check(Dynasty.appoint(Game,"a",fixture.namesake_uid),"native fixture can appoint a different actual household leader")
		stale = fixture.snapshot()
		(find(page,"BondConfirmBind") as Button).pressed.emit(); await settle()
		check(fixture.snapshot() == stale and probe.changes == 0 and int(Game.save_stats().get("started",0)) == save_count,"changed actual leader rejects the reviewed order without new mutation or save")
		Game.world = unchanged_world
		page._request_bond(fixture.dragon_uid,"bind",fixture.adult_uid); await settle()
		(find(page,"BondConfirmBind") as Button).pressed.emit(); Game.wait_save(); await settle()
		check(String(fixture.row()["rider_person_uid"]) == fixture.adult_uid and bool(DragonBond.status(Game,fixture.dragon_uid)["active"]),"explicit actual confirmation binds selected native person")
		check(probe.changes == 1 and int(Game.save_stats().get("started",0)) == save_count+1,"success has exactly one UI signal and one async save")
		check(fixture.native_snapshot() == native_before and source_fields(fixture.row()) == independent,"bond preserves all native population/coin/Units/items/body and independent dragon appearance/owner/care")
		portrait = find(page,"BondedPersonPortrait") as Portrait
		check(portrait != null and portrait._spec == rider_spec(unit),"bonded status shows actual rider model/equipment, never a preview substitute")
		check((find(page,"DragonBindRider") as Button).disabled and not (find(page,"DragonReleaseBond") as Button).disabled,"active bond enables only real release order")
		check(page.model_rider.is_empty() and page.model_card.rider_spec.is_empty(),"relationship does not claim mounted presentation this pass")
		before = fixture.snapshot()
		check(not bool(DragonBond.bind_preview(Game,fixture.other_dragon_uid,fixture.adult_uid)["ok"]) and fixture.snapshot() == before,"one person cannot be offered a second active dragon")
		fit_check(fit,viewport,page,size,"bonded"); await capture(viewport,size,"bonded")
		page._request_bond(fixture.dragon_uid,"release",""); await settle()
		fit_check(fit,viewport,page,size,"release_review"); await capture(viewport,size,"release_review")
		(find(page,"BondReviewCancel") as Button).pressed.emit(); await settle()
		check(fixture.snapshot() == before and probe.changes == 1,"release Cancel preserves the actual relationship")
		Game.location = "b"; Game.world["party"]["pos"] = Game.world["towns"]["b"]["pos"]
		before = fixture.snapshot(); page._refresh(); await settle()
		check(fixture.snapshot() == before and bool(DragonBond.status(Game,fixture.dragon_uid)["active"]) and not (find(page,"DragonReleaseBond") as Button).disabled,"remote pure view retains surviving bond and real release")
		page._request_bond(fixture.dragon_uid,"release",""); await settle()
		(find(page,"BondConfirmRelease") as Button).pressed.emit(); Game.wait_save(); await settle()
		check(probe.changes == 2 and int(Game.save_stats().get("started",0)) == save_count+2,"reviewed remote release signals/saves once")
		check(String(fixture.row()["rider_person_uid"]) == "" and String(fixture.row()["last_rider_person_uid"]) == fixture.adult_uid,"release retains exact previous rider identity")
		check(unit.equip["helm"] == helmet and not unit.dead and Game.company.has(unit),"release leaves actual Unit/body/private gear untouched")
		before = fixture.snapshot(); page._open_bond_picker(fixture.dragon_uid); await settle()
		check(page._bond_picker.is_empty() and (find(page,"DragonBindRider") as Button).disabled and page.notice != "","remote initial bond is disabled with actual reason")
		check(fixture.snapshot() == before and Game.location == "b" and Game.world["party"]["pos"] == Game.world["towns"]["b"]["pos"],"browsing never teleports party to bypass contact")
		fit_check(fit,viewport,page,size,"away"); await capture(viewport,size,"away")
		page._person_record(fixture.adult_uid)
		check(Game.screen_params.get("person_uid","") == fixture.adult_uid and Game.screen_params.get("pid",-1) == int(loc["person"][0]) and Game.screen_params.get("back","") == "dragons","actual person detail uses stable native identity and return context")
		check(Game.location == "b","person link preserves actual location")
		page._open_dragon(String(fixture.native.holding("a"))); await settle()
		check((find(page,"DragonBindRider") as Button).disabled and "Egg" in words(page),"canonical egg remains unbindable without adult rider claims")
		check(fixture.snapshot() == before,"all final navigation/egg reads preserve native state and RNG")
		page._back(); check(Game.screen_params == {"origin":"bond_ui"} and Game.location == "b","Back restores caller context without teleport")
		var member_owned: Dictionary = fixture.row().duplicate(true)
		Dragons._set_owner(fixture.row(),Dragons._person(Game,fixture.adult_uid))
		before = fixture.snapshot(); page._open_dragon(fixture.dragon_uid); await settle()
		var gift: Button = button_text(page,"Gift ownership")
		check(Dragons.authority(Game,fixture.row())["ok"] and gift != null and not gift.disabled,"actual household head can manage a member-owned dragon without taking personal ownership")
		check(fixture.snapshot() == before,"household authority presentation is pure")
		Game.world["dragons"]["records"][fixture.dragon_uid] = member_owned
		viewport.queue_free(); page = null; viewport = null; unit = null; helmet = null; portrait = null
		await settle()
	Game.wait_save(); Game.changed.disconnect(probe.changed); probe.queue_free(); probe = null; await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before,"picker/review/refresh cleanup leaves no orphan controls")
	Game.world = original["world"]; Game.company = original["company"]; Game.stash = original["stash"]; Game.squads = original["squads"]
	Game.gold = float(original["gold"]); Game.day = float(original["day"]); Game.location = String(original["location"])
	Game.contract = original["contract"]; Game.pending_battle = original["pending"]; Game.last_result = original["result"]
	Game.screen_params = original["params"]; Game.main = original["main"]; Game._active_screen = String(original["screen"])
	Game.provisions = original["provisions"]; Game.rations = original["rations"]; Game.food_clock = original["clock"]; Game.rng.state = int(original["rng"])
	Unit._next_uid = int(original["unit"]); Item._next_uid = int(original["item"]); Game._save_ready = bool(original["save_ready"])
	Game._deploy_rev = int(original["deploy_rev"]); Game._deploy_key = original["deploy_key"]; Game._deploy_cache = original["deploy_cache"]
	WorldGen.W = int(original["wg"][0]); WorldGen.H = int(original["wg"][1]); WorldGen.K = int(original["wg"][2]); WorldGen.TF = original["wg"][3]; WorldGen.KD = original["wg"][4]
	if report_dir != "":
		check(captures.size() == 18,"six bond states captured at three desktop sizes")
		var file := FileAccess.open(report_dir.path_join("dragon-bond-ui.json"),FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"version":"0.021","checks":checks,"failures":fails+int(fit.fails),"fit_cases":fit_cases,"fit_failures":int(fit.fails),
				"captures":captures,"desktop_fit_cases":fit_cases,"sizes":[[1280,720],[1920,1080],[2560,1440]],"duration_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"no_phone_qa":true,"performance_panel":true,"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x < -10000},"\t")); file.close()
		else: check(false,"native report saved")
	tree.root.size = original["size"]; tree.root.set_flag(Window.FLAG_NO_FOCUS,bool(original["no_focus"])); tree.root.position = original["position"]; tree.root.visible = bool(original["visible"])
	print("Dragon bond UI v021: %d checks, %d failures; %d desktop fit cases, %d fit failures." % [checks,fails,fit_cases,int(fit.fails)])
	var result: int = fails+int(fit.fails)
	fit.tree = null; fit = null; fixture = null; tree = null
	return result
