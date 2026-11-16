extends RefCounted
## Native reviewed settlement order; current body/relationship reads remain pure.
const RunplanArgs: GDScript = preload("res://tests/fixtures/older_runplan_args_v100.gd")
const SpeedParts: GDScript = preload("res://tests/fixtures/older_speed_parts_v100.gd")
const WINDOWS := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
const UI_PARTS: Array[String] = ["w720", "w1080", "w1440", "autosave"]
const PART_WINDOW: Dictionary = {"w720": 0, "w1080": 1, "w1440": 2}
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
# v0.084 weekly/coalesced autosaves: older_tests_unfixed_diagnosis.md entries 24/31.
# Receipt keys and drained-worker contract: test_save_ownership_v012.gd:120-126.
func save_receipt(before: Dictionary, writes: int, context: String) -> void:
	var after: Dictionary = Game.save_stats()
	for counter: String in ["started", "completed"]:
		check(int(after[counter]) == int(before[counter]) + writes, context + ": exact " + counter + " count")
	check(int(after["failed"]) == int(before["failed"]), context + ": zero failed writes")
	check(not bool(after["pending"]) and int(after["active_snapshots"]) == 0, context + ": save worker fully drained")
	if writes > 0:
		check(bool(after["last_ok"]) and str(after["last_stage"]) == "complete" and int(after["last_error"]) == OK,
			context + ": successful completed native write")

func saved_payload() -> Dictionary:
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	check(decoded is Dictionary, "isolated native save contains a complete JSON object")
	return decoded if decoded is Dictionary else {}

func _ws_id() -> String:
	return ProjectSettings.globalize_path("res://").sha256_text().substr(0, 12)

func _receipt_path() -> String:
	return "user://dragon_combat_ui_v022_state_%s.var" % _ws_id()

func _write_receipt(data: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(_receipt_path(), FileAccess.WRITE)
	if f == null:
		return false
	f.store_var(data, false)
	f.flush()
	var ok: bool = f.get_error() == OK
	f.close()
	return ok

func _read_receipt(expected_source: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(_receipt_path(), FileAccess.READ)
	if f == null:
		return {}
	var raw: Variant = f.get_var(false)
	var ok: bool = f.get_error() == OK
	f.close()
	if not ok or not raw is Dictionary:
		return {}
	var d: Dictionary = raw
	return d if str(d.get("source", "")) == expected_source else {}

func _prepare_autosave_baseline(fixture: RefCounted) -> void:
	fixture.fixture()
	DragonCombat.prepare_world(Game)
	var bonded_a: Dictionary = DragonBond.bind(Game, fixture.dragon_uid, fixture.adult_uid, DragonBond.bind_preview(Game, fixture.dragon_uid, fixture.adult_uid))
	check(bool(bonded_a["ok"]), "autosave baseline fixture has reviewed21bond")
	Game.screen_params = {"back": "house", "dragon_uid": fixture.dragon_uid}
	var vp_a: SubViewport = SubViewport.new()
	vp_a.size = WINDOWS[2]
	vp_a.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(vp_a)
	var page_a: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate()
	vp_a.add_child(page_a)
	await settle()
	page_a._request_combat(fixture.dragon_uid, true)
	await settle()
	(find(page_a, "DragonCombatConfirm") as Button).pressed.emit()
	Game.wait_save()
	await settle()
	Game.location = "b"
	Game.world["party"]["pos"] = Game.world["towns"]["b"]["pos"]
	page_a._refresh()
	await settle()
	page_a._request_combat(fixture.dragon_uid, false)
	await settle()
	(find(page_a, "DragonCombatConfirm") as Button).pressed.emit()
	Game.wait_save()
	await settle()
	vp_a.queue_free()
	await settle()

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree; await tree.process_frame; Game.wait_save()
	var start: int = Time.get_ticks_usec()
	var part: String = OS.get_environment("DRAGON_UI_PART")
	var seen_part: bool = not part.is_empty()
	for arg: String in RunplanArgs.arguments():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
		elif arg.begins_with("--part=") or arg.begins_with("--speed-part="):
			var pval: String = arg.trim_prefix("--part=") if arg.begins_with("--part=") else arg.trim_prefix("--speed-part=")
			if seen_part and pval != part:
				check(false, "non-conflicting dragon combat UI part selector")
				tree = null
				return fails
			seen_part = true
			part = pval
	if part == "" and report_dir != "":
		part = "all"
	check(part == "all" or part in UI_PARTS, "choose one --part=w720|w1080|w1440|autosave; every part is required in order")
	if fails > 0: tree = null; return fails
	if report_dir != "":
		check(report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v022-ui-render/") and DisplayServer.get_name() != "headless","private native renderer report path")
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("dragon-combat-ui.json")),"fresh capture directory")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.visible = true
	# Run as the sole --test in a fresh headless process; runner reset_between() keeps the autosave stamp.
	# In-memory fixture policy only; preserve the user's setting and all native stamps/counters.
	check(Game.SAVE_PATH.begins_with("user://test_"), "runner supplies an isolated native save path")
	if fails > 0: tree = null; return fails
	var had_autosave: bool = Game.settings.has("autosave")
	var old_autosave: Variant = Game.settings.get("autosave")
	Game.settings["autosave"] = "week"
	check(Game.autosave_interval_days() == 7, "v0.084 weekly policy is exactly seven native days")
	var first_save: Dictionary = {}
	var first_state: Dictionary = {}
	var first_save_path: String = "user://dragon_combat_ui_v022_first_order_%s.json" % _ws_id() if part != "all" else (Game.SAVE_PATH + ".first-order")
	var stamp: String = str(SpeedParts.call("source_stamp"))
	var prior_receipt: Dictionary = {}
	if part in ["w1080", "w1440", "autosave"]:
		prior_receipt = _read_receipt(stamp)
		var want_prev: Array = ["w720"] if part == "w1080" else (["w720", "w1080"] if part == "w1440" else ["w720", "w1080", "w1440"])
		check(prior_receipt.get("completed", []) == want_prev, "predecessor dragon combat UI parts completed in order before " + part)
		if fails > 0:
			if had_autosave: Game.settings["autosave"] = old_autosave
			else: Game.settings.erase("autosave")
			tree = null
			return fails
		first_save = prior_receipt.get("first_save", {})
		first_state = prior_receipt.get("first_state", {})
		first_save_path = str(prior_receipt.get("first_save_path", first_save_path))
	var old: Dictionary = {"world":Game.world,"company":Game.company,"squads":Game.squads,"stash":Game.stash,"day":Game.day,"gold":Game.gold,"location":Game.location,"params":Game.screen_params,"screen":Game._active_screen,"rng":Game.rng.state,"unit":Unit._next_uid,"item":Item._next_uid,"ready":Game._save_ready,"window":tree.root.size}
	Game.stash = []; Game._save_ready = true; Game._active_screen = "dragons"
	var fixture: RefCounted = load("res://tests/test_dragon_bond_v021.gd").new()
	var probe: Probe = Probe.new(); tree.root.add_child(probe); Game.changed.connect(probe.changed)
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var active_windows: Array = WINDOWS if part == "all" else ([WINDOWS[int(PART_WINDOW[part])]] if PART_WINDOW.has(part) else [])
	if part in ["w1080", "w1440"]:
		fixture.fixture()
		Game.request_autosave()
		Game.wait_save()
		await settle()
	for size: Vector2i in active_windows:
		if report_dir != "": tree.root.size = size
		fixture.fixture(); DragonCombat.prepare_world(Game)
		var bonded: Dictionary = DragonBond.bind(Game,fixture.dragon_uid,fixture.adult_uid,DragonBond.bind_preview(Game,fixture.dragon_uid,fixture.adult_uid))
		check(bool(bonded["ok"]),"actual native fixture has reviewed21bond")
		probe.changes = 0
		var unit: Unit = Game.world["dragons"]["combat_units"][fixture.dragon_uid]
		var relation: Array = [fixture.row()["rider_person_uid"],fixture.row()["owner_person_uid"],fixture.row()["custodian_person_uid"],fixture.row()["location_town_id"]]
		var before: String = fingerprint(); var saves: int = int(Game.save_stats()["started"])
		var save_before: Dictionary = Game.save_stats().duplicate(true)
		var expected_writes: int = 1 if size == WINDOWS[0] else 0
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
		save_receipt(save_before,0,"defence Cancel")
		page._request_combat(fixture.dragon_uid,true); await settle()
		var original_parts: Dictionary = unit.body.parts.duplicate(true)
		unit.body.wound_part("neck")["layers"][0]["dmg"] = 0.9
		before = fingerprint()
		(find(page,"DragonCombatConfirm") as Button).pressed.emit(); await settle()
		check(fingerprint() == before and probe.changes == 0 and int(Game.save_stats()["started"]) == saves,"actual injury invalidates displayed order with no extra mutation")
		save_receipt(save_before,0,"stale injury refusal")
		unit.body.parts = original_parts
		page._request_combat(fixture.dragon_uid,true); await settle()
		(find(page,"DragonCombatConfirm") as Button).pressed.emit(); Game.wait_save(); await settle()
		check(bool(DragonCombat.combat_status(Game,fixture.dragon_uid)["enabled"]) and probe.changes == 1,"successful explicit order changes exactly once")
		save_receipt(save_before,expected_writes,"successful defence follows weekly policy")
		if size == WINDOWS[0]:
			first_save = saved_payload()
			check(DirAccess.copy_absolute(
				ProjectSettings.globalize_path(Game.SAVE_PATH),
				ProjectSettings.globalize_path(first_save_path)) == OK,
				"preserve the first completed native save bytes")
			first_state = JSON.parse_string(fixture.snapshot())
		check(DragonCombat.battle_units(Game).has(unit) and Game.company.is_empty(),"admission borrows real native holder without raising/inventing people")
		check([fixture.row()["rider_person_uid"],fixture.row()["owner_person_uid"],fixture.row()["custodian_person_uid"],fixture.row()["location_town_id"]] == relation,"defence keeps actual bond/owner/care/location independent")
		fit_check(fit,viewport,page,size,"ordered"); await capture(viewport,size,"ordered")
		before = fingerprint(); page._request_combat(fixture.dragon_uid,false); await settle()
		fit_check(fit,viewport,page,size,"withdraw_review"); await capture(viewport,size,"withdraw_review")
		(find(page,"DragonCombatCancel") as Button).pressed.emit(); await settle()
		check(fingerprint() == before and probe.changes == 1,"withdraw Cancel retains recorded order and emits no change")
		save_receipt(save_before,expected_writes,"withdraw Cancel starts no write")
		Game.location = "b"; Game.world["party"]["pos"] = Game.world["towns"]["b"]["pos"]
		before = fingerprint(); page._refresh(); await settle()
		check(DragonCombat.battle_units(Game).is_empty() and fingerprint() == before,"recorded order never teleports/summons a remote holder")
		page._request_combat(fixture.dragon_uid,false); await settle()
		(find(page,"DragonCombatConfirm") as Button).pressed.emit(); Game.wait_save(); await settle()
		check(not bool(DragonCombat.combat_status(Game,fixture.dragon_uid)["enabled"]) and probe.changes == 2,"authorized remote withdrawal changes exactly once")
		save_receipt(save_before,expected_writes,"same-day remote withdrawal coalesces")
		check(String(fixture.row()["rider_person_uid"]) == fixture.adult_uid and (find(page,"DragonDefendSettlement") as Button).disabled,"withdrawal keeps bond but requires actual contact for new defence")
		fit_check(fit,viewport,page,size,"away"); await capture(viewport,size,"away")
		viewport.queue_free(); page = null; viewport = null; unit = null; panel = null; layer = null; await settle()
	if part in ["w720", "w1080", "w1440"]:
		Game.changed.disconnect(probe.changed)
		Game.wait_save(); probe.queue_free(); probe = null; await settle()
		check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphans, "defence reviews/refresh leave no orphan nodes")
		var done_list: Array = (prior_receipt.get("completed", []) as Array).duplicate()
		done_list.append(part)
		if fails == 0 and int(fit.fails) == 0:
			check(_write_receipt({"source": stamp, "completed": done_list, "first_save": first_save, "first_state": first_state, "first_save_path": first_save_path}), "window part receipt saved: " + part)
		Game.world = old["world"]; Game.company = old["company"]; Game.squads = old["squads"]; Game.stash = old["stash"]; Game.day = old["day"]; Game.gold = old["gold"]; Game.location = old["location"]
		Game.screen_params = old["params"]; Game._active_screen = old["screen"]; Game.rng.state = old["rng"]; Game._save_ready = old["ready"]; Unit._next_uid = old["unit"]; Item._next_uid = old["item"]
		if had_autosave: Game.settings["autosave"] = old_autosave
		else: Game.settings.erase("autosave")
		tree.root.size = old["window"]
		print("Dragon combat UI v022 [", part, "]: ", checks, " checks, ", fails, " failures; ", fit_cases, " desktop fit cases, ", int(fit.fails), " fit failures")
		var part_res: int = fails + int(fit.fails); fit.tree = null; fit = null; fixture = null; tree = null; return part_res
	if part == "autosave":
		await _prepare_autosave_baseline(fixture)
	# Elapse the controlled fixture clock by the literal documented interval.
	# No private autosave stamp/counter is assigned; the native request decides eligibility.
	check(Game.day == 0.0, "all three native UI fixtures exercised same-day coalescing")
	var interval_before: Dictionary = Game.save_stats().duplicate(true)
	var closed_sha: String = FileAccess.get_sha256(Game.SAVE_PATH)
	Game.day += 7.0 - 1.0 / 1024.0
	Game.request_autosave(); Game.wait_save(); await settle()
	save_receipt(interval_before,0,"request just before seven days stays coalesced")
	check(FileAccess.get_sha256(Game.SAVE_PATH) == closed_sha,
		"request before seven days preserves the completed save bytes")
	Game.day += 1.0 / 1024.0
	Game.request_autosave(); Game.wait_save(); await settle()
	save_receipt(interval_before,1,"first naturally eligible weekly request")
	var interval_state: Dictionary = JSON.parse_string(fixture.snapshot())
	var interval_sha: String = FileAccess.get_sha256(Game.SAVE_PATH)
	Game.request_autosave(); Game.wait_save(); await settle()
	save_receipt(interval_before,1,"repeat request on eligible day coalesces")
	check(FileAccess.get_sha256(Game.SAVE_PATH) == interval_sha, "same-day repeat preserves the completed save bytes")
	Game.changed.disconnect(probe.changed)
	var reload_before: Dictionary = Game.save_stats().duplicate(true)
	check(not first_save.is_empty() and not first_state.is_empty(), "first eligible order supplied an actual completed save")
	if not first_save.is_empty() and not first_state.is_empty():
		var interval_save_path: String = Game.SAVE_PATH
		Game.SAVE_PATH = first_save_path
		check(Game.load_game(), "isolated first completed native save loads")
		Game.SAVE_PATH = interval_save_path
		check(fixture.same_values(first_state,JSON.parse_string(fixture.snapshot())), "first saved state reloads exact native identities, bodies, holdings and RNG")
		check(bool(DragonCombat.combat_status(Game,fixture.dragon_uid)["enabled"]), "first completed save reloads the enabled defence")
	check(Game.load_game(), "isolated eligible-interval native save loads")
	check(fixture.same_values(interval_state,JSON.parse_string(fixture.snapshot())), "eligible-interval reload keeps exact native identities, bodies, holdings and RNG")
	check(not bool(DragonCombat.combat_status(Game,fixture.dragon_uid)["enabled"]), "eligible weekly save reloads the withdrawn defence")
	save_receipt(reload_before,0,"isolated reloads start no writes")
	check(FileAccess.get_sha256(Game.SAVE_PATH) == interval_sha, "native reload preserves the completed save bytes")
	Game.wait_save(); probe.queue_free(); probe = null; await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphans,"defence reviews/refresh leave no orphan nodes")
	Game.world = old["world"]; Game.company = old["company"]; Game.squads = old["squads"]; Game.stash = old["stash"]; Game.day = old["day"]; Game.gold = old["gold"]; Game.location = old["location"]
	Game.screen_params = old["params"]; Game._active_screen = old["screen"]; Game.rng.state = old["rng"]; Game._save_ready = old["ready"]; Unit._next_uid = old["unit"]; Item._next_uid = old["item"]
	if report_dir != "":
		check(captures.size() == 15,"five actual defence states captured at three desktop sizes")
		var file: FileAccess = FileAccess.open(report_dir.path_join("dragon-combat-ui.json"),FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":fails+int(fit.fails),"desktop_fit_cases":fit_cases,"fit_failures":int(fit.fails),"captures":captures,"duration_seconds":float(Time.get_ticks_usec()-start)/1000000.0,"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x < -10000,"no_phone_qa":true,"performance_panel":true},"\t")); file.close()
		else: check(false,"native UI report saved")
	if had_autosave: Game.settings["autosave"] = old_autosave
	else: Game.settings.erase("autosave")
	tree.root.size = old["window"]
	print("Dragon combat UI v022: ",checks," checks, ",fails," failures; ",fit_cases," desktop fit cases, ",int(fit.fails)," fit failures")
	var result: int = fails+int(fit.fails); fit.tree = null; fit = null; fixture = null; tree = null; return result
