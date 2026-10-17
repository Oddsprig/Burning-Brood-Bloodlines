extends RefCounted
## Native reviewed settlement order; current body/relationship reads remain pure.
const WINDOWS := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0
var tree: SceneTree
var report_dir: String = ""
var captures: Array = []
class Probe extends Node:
	var changes: int = 0
	func changed() -> void: changes += 1
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon combat UI v022: ",why)
func settle() -> void:
	for _i in 5: await tree.process_frame
static func find(page: Node,name: String) -> Control: return page.find_child(name,true,false) as Control
static func fingerprint() -> String: return JSON.stringify(Game._serialize({"world":Game.world,"company":Game.company,"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid}),"",true,true).sha256_text()
func fit_check(fit: RefCounted, viewport: SubViewport, page: DragonsView, size: Vector2i, state: String) -> void:
	fit_cases += 1
	var context: String = "%dx%d %s" % [size.x,size.y,state]
	fit._check(viewport,Vector2(size),context)
	check(page.size.is_equal_approx(Vector2(size)) and page.body.size.x >= size.x-UiKit.diagnostics_lane(size.x)-100,context+" actual native detail has readable width")
	check(page.body.get_global_rect().end.x <= size.x-UiKit.diagnostics_lane(size.x)+1,context+" panel lane stays free")
	for name: String in ["DragonDefendSettlement","DragonWithdraw"]:
		var button: Control = find(page,name)
		check(button != null and button.size.y >= 48 and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()),context+" actual "+name+" visible at top")
	var modal: Control = find(page,"DragonCombatReview")
	if modal != null:
		var bounds: ScrollContainer = modal.get_parent().get_parent()
		for name: String in ["DragonCombatCancel","DragonCombatConfirm"]:
			check(bounds.get_global_rect().encloses(find(page,name).get_global_rect()),context+" complete reviewed action inside actual modal")
func capture(viewport: SubViewport, size: Vector2i, state: String) -> void:
	if report_dir == "": return
	for node: Node in viewport.find_children("*","",true,false):
		if node is PerformancePanel: (node as PerformancePanel)._refresh()
	await RenderingServer.frame_post_draw; await RenderingServer.frame_post_draw
	var path: String = report_dir.path_join("defence_%dx%d_%s.png" % [size.x,size.y,state])
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == size,"native defence capture dimensions")
	var saved: bool = image != null and image.save_png(path) == OK
	check(saved,"private native defence screenshot")
	captures.append({"path":path,"size":[size.x,size.y],"state":state,"sha256":FileAccess.get_sha256(path) if saved else ""})
func run(scene_tree: SceneTree) -> int:
	tree = scene_tree; await tree.process_frame; Game.wait_save()
	var start: int = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	if report_dir != "":
		check(report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v022-ui-render/") and DisplayServer.get_name() != "headless","private native renderer report path")
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("dragon-combat-ui.json")),"fresh capture directory")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.visible = true
	var old: Dictionary = {"world":Game.world,"company":Game.company,"squads":Game.squads,"stash":Game.stash,"day":Game.day,"gold":Game.gold,"location":Game.location,"params":Game.screen_params,"screen":Game._active_screen,"rng":Game.rng.state,"unit":Unit._next_uid,"item":Item._next_uid,"ready":Game._save_ready,"window":tree.root.size}
	Game.stash = []; Game._save_ready = true; Game._active_screen = "dragons"
	var fixture: RefCounted = load("res://tests/test_dragon_bond_v021.gd").new()
	var probe := Probe.new(); tree.root.add_child(probe); Game.changed.connect(probe.changed)
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for size: Vector2i in WINDOWS:
		if report_dir != "": tree.root.size = size
		fixture.fixture(); DragonCombat.prepare_world(Game)
		var bonded: Dictionary = DragonBond.bind(Game,fixture.dragon_uid,fixture.adult_uid,DragonBond.bind_preview(Game,fixture.dragon_uid,fixture.adult_uid))
		check(bool(bonded["ok"]),"actual native fixture has reviewed21bond")
		probe.changes = 0
		var unit: Unit = Game.world["dragons"]["combat_units"][fixture.dragon_uid]
		var relation: Array = [fixture.row()["rider_person_uid"],fixture.row()["owner_person_uid"],fixture.row()["custodian_person_uid"],fixture.row()["location_town_id"]]
		var before: String = fingerprint(); var saves: int = int(Game.save_stats()["started"])
		Game.screen_params = {"back":"house","dragon_uid":fixture.dragon_uid}
		var viewport := SubViewport.new(); viewport.size = size; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED; tree.root.add_child(viewport)
		var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
		var panel := PerformancePanel.new(); panel.setup(Perf); layer.add_child(panel)
		var page: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate(); viewport.add_child(page); await settle()
		check(not bool(DragonCombat.combat_status(Game,fixture.dragon_uid)["enabled"]) and not (find(page,"DragonDefendSettlement") as Button).disabled and (find(page,"DragonWithdraw") as Button).disabled,"defaultOFF explicit reviewed defence only")
		check(fingerprint() == before,"status/detail reads do not prepare actors, heal wounds or allocate Units")
		fit_check(fit,viewport,page,size,"off"); await capture(viewport,size,"off")
		page._request_combat(fixture.dragon_uid,true); await settle()
		fit_check(fit,viewport,page,size,"defend_review"); await capture(viewport,size,"defend_review")
		(find(page,"DragonCombatCancel") as Button).pressed.emit(); await settle()
		check(fingerprint() == before and probe.changes == 0 and int(Game.save_stats()["started"]) == saves,"defence Cancel pure/no save")
		page._request_combat(fixture.dragon_uid,true); await settle()
		var original_parts: Dictionary = unit.body.parts.duplicate(true)
		unit.body.wound_part("neck")["layers"][0]["dmg"] = 0.9
		before = fingerprint()
		(find(page,"DragonCombatConfirm") as Button).pressed.emit(); await settle()
		check(fingerprint() == before and probe.changes == 0 and int(Game.save_stats()["started"]) == saves,"actual injury invalidates displayed order with no extra mutation")
		unit.body.parts = original_parts
		page._request_combat(fixture.dragon_uid,true); await settle()
		(find(page,"DragonCombatConfirm") as Button).pressed.emit(); Game.wait_save(); await settle()
		check(bool(DragonCombat.combat_status(Game,fixture.dragon_uid)["enabled"]) and probe.changes == 1 and int(Game.save_stats()["started"]) == saves+1,"successful explicit order saved/changed once")
		check(DragonCombat.battle_units(Game).has(unit) and Game.company.is_empty(),"admission borrows real native holder without raising/inventing people")
		check([fixture.row()["rider_person_uid"],fixture.row()["owner_person_uid"],fixture.row()["custodian_person_uid"],fixture.row()["location_town_id"]] == relation,"defence keeps actual bond/owner/care/location independent")
		fit_check(fit,viewport,page,size,"ordered"); await capture(viewport,size,"ordered")
		before = fingerprint(); page._request_combat(fixture.dragon_uid,false); await settle()
		fit_check(fit,viewport,page,size,"withdraw_review"); await capture(viewport,size,"withdraw_review")
		(find(page,"DragonCombatCancel") as Button).pressed.emit(); await settle()
		check(fingerprint() == before,"withdraw Cancel retains recorded order")
		Game.location = "b"; Game.world["party"]["pos"] = Game.world["towns"]["b"]["pos"]
		before = fingerprint(); page._refresh(); await settle()
		check(DragonCombat.battle_units(Game).is_empty() and fingerprint() == before,"recorded order never teleports/summons a remote holder")
		page._request_combat(fixture.dragon_uid,false); await settle()
		(find(page,"DragonCombatConfirm") as Button).pressed.emit(); Game.wait_save(); await settle()
		check(not bool(DragonCombat.combat_status(Game,fixture.dragon_uid)["enabled"]) and probe.changes == 2 and int(Game.save_stats()["started"]) == saves+2,"authorized remote withdrawal saved/changed once")
		check(String(fixture.row()["rider_person_uid"]) == fixture.adult_uid and (find(page,"DragonDefendSettlement") as Button).disabled,"withdrawal keeps bond but requires actual contact for new defence")
		fit_check(fit,viewport,page,size,"away"); await capture(viewport,size,"away")
		viewport.queue_free(); page = null; viewport = null; unit = null; panel = null; layer = null; await settle()
	Game.wait_save(); Game.changed.disconnect(probe.changed); probe.queue_free(); probe = null; await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphans,"defence reviews/refresh leave no orphan nodes")
	Game.world = old["world"]; Game.company = old["company"]; Game.squads = old["squads"]; Game.stash = old["stash"]; Game.day = old["day"]; Game.gold = old["gold"]; Game.location = old["location"]
	Game.screen_params = old["params"]; Game._active_screen = old["screen"]; Game.rng.state = old["rng"]; Game._save_ready = old["ready"]; Unit._next_uid = old["unit"]; Item._next_uid = old["item"]
	if report_dir != "":
		check(captures.size() == 15,"five actual defence states captured at three desktop sizes")
		var file: FileAccess = FileAccess.open(report_dir.path_join("dragon-combat-ui.json"),FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":fails+int(fit.fails),"desktop_fit_cases":fit_cases,"fit_failures":int(fit.fails),"captures":captures,"duration_seconds":float(Time.get_ticks_usec()-start)/1000000.0,"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x < -10000,"no_phone_qa":true,"performance_panel":true},"\t")); file.close()
		else: check(false,"native UI report saved")
	tree.root.size = old["window"]
	print("Dragon combat UI v022: ",checks," checks, ",fails," failures; ",fit_cases," desktop fit cases, ",int(fit.fails)," fit failures")
	var result: int = fails+int(fit.fails); fit.tree = null; fit = null; fixture = null; tree = null; return result
