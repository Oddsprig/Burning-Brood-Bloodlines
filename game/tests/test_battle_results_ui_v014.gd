extends RefCounted
## Native result fixture, desktop controls, optional private rendered evidence.
const SummaryFixture = preload("res://tests/test_battle_result_summary_v014.gd")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0
var captures: Array = []
var timings: Array = []
var report_dir: String = ""

class RouteProbe extends Node:
	var path: String = ""
	func show_screen(next: String) -> void: path = next

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL battle results UI: ", why)

func settle() -> void:
	for _i in 5: await tree.process_frame

static func labels(node: Node) -> String:
	var text: String = (node as Label).text + "\n" if node is Label else ""
	for child: Node in node.get_children(): text += labels(child)
	return text

static func descendants(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children(): count += 1 + descendants(child)
	return count

static func fingerprint(result: Dictionary) -> String:
	# Include all original fields and concrete gear; no result generation/growth.
	return JSON.stringify(Game._serialize(result), "", true, true).sha256_text()

func fit_check(fit: RefCounted, viewport: SubViewport, size: Vector2i, label: String) -> void:
	fit_cases += 1
	fit._check(viewport, Vector2(size), label)

func capture(viewport: SubViewport, size: Vector2i, state: String) -> void:
	if report_dir == "" or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path: String = report_dir.path_join("results_%dx%d_%s.png" % [size.x, size.y, state])
	var start: int = Time.get_ticks_usec()
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == size, "native rendered result viewport size " + state)
	if image != null:
		check(image.save_png(path) == OK, "private rendered PNG saved " + state)
		captures.append({"path": path, "size": [size.x, size.y], "state": state, "capture_us": Time.get_ticks_usec() - start})

func _fixture() -> Dictionary:
	var result: Dictionary = SummaryFixture.fixture(200)
	result["loot_gold"] = 173
	result["loot_coin"] = 51; result["scrap_gold"] = 22
	result["trophy_gold"] = 9; result["camp_loot"] = 38; result["militia_bonus"] = 7
	result["fallen_gear"] = 11
	result["supplies_taken"] = {"meat": 6, "beer": 2}
	result["scrap_kg"] = {"bronze": 2.5}; result["own_scrap_kg"] = {"copper": 0.5}
	result["arrows_got"] = {"arrow": 8}
	result["trophies"] = [{"name": "Recorded trophy", "gold": 9}]
	result["receipt_marker"] = {"original": [1, {"retained": true}]}
	var template: String = String(DB.weapons.keys()[0])
	for i in 40:
		var item := Item.new()
		item.uid = 70000 + i; item.tid = template; item.material = "bronze"; item.wear = i % 4
		item.mark = {"n": "Recorded forge", "r": "human", "t": "fixture"}
		result["loot_items"].append(item)
	for i in 42: result["events"].append({"type": "learn", "actor": 2, "text": "Native 0-2 improves skill %d" % i})
	result["events"].append({"type": "learn", "actor": 202, "text": "Enemy lesson"})
	result["growth"] = {2: {"STR": 3}, 202: {"STR": 4}}
	return result

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
	if report_dir != "":
		check(report_dir.is_absolute_path() and report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v014-ui-render/"), "optional captures remain in private v014-ui-render")
		if fails > 0: tree = null; return fails
		check(DisplayServer.get_name() != "headless", "rendered report requires native renderer")
		if fails > 0: tree = null; return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK, "private capture directory exists")
		check(not FileAccess.file_exists(report_dir.path_join("battle-results-ui.json")), "render evidence uses a fresh report directory")
		if fails > 0: tree = null; return fails
	var original: Dictionary = {"result": Game.last_result, "main": Game.main, "screen": Game._active_screen, "params": Game.screen_params,
		"gold": Game.gold, "day": Game.day, "rng": Game.rng.state, "unit": Unit._next_uid, "item": Item._next_uid,
		"size": tree.root.size}
	if report_dir != "":
		tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
		tree.root.position = Vector2i(-20000, -20000)
		check(tree.root.get_flag(Window.FLAG_NO_FOCUS) and tree.root.position.x < 0, "native capture window stays no-focus/offscreen")
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var result: Dictionary = _fixture()
	var before: String = fingerprint(result)
	var fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	Game.last_result = result
	Game._active_screen = "aftermath"
	var probe := RouteProbe.new()
	tree.root.add_child(probe)
	Game.main = probe
	for size: Vector2i in SIZES:
		if report_dir != "": tree.root.size = size
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var start: int = Time.get_ticks_usec()
		var page: Control = (load("res://battle/aftermath.tscn") as PackedScene).instantiate()
		viewport.add_child(page)
		timings.append({"size": [size.x, size.y], "action": "build", "us": Time.get_ticks_usec() - start})
		var layer := CanvasLayer.new(); layer.layer = 100
		viewport.add_child(layer)
		var performance := PerformancePanel.new(); performance.setup(Perf)
		layer.add_child(performance)
		await settle()
		fit_check(fit, viewport, size, "v014 closed desktop results")
		check(page.frame.get_global_rect().end.x <= float(size.x) - UiKit.diagnostics_lane(size.x) + 1.0, "results reserve actual diagnostics lane")
		check(page.continue_button.get_global_rect().end.y <= size.y and page.continue_button.get_global_rect().position.y >= 0, "Continue visible outside scrolling details")
		for key: String in ["fallen", "wounded", "lessons", "loot"]:
			var header: Button = page.find_child(key.capitalize() + "Toggle", true, false)
			check(page.body_scroll.get_global_rect().encloses(header.get_global_rect()), "closed " + key + " toggle visible without scrolling")
		check(page.theme == UiTheme.get_theme(), "native shared dark theme applies")
		var style: StyleBoxFlat = (page.find_child("OutcomeCard", true, false) as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
		check(style != null and style.bg_color.get_luminance() < 0.25, "outcome surface is dark, not mismatched cream")
		var title: Label = page.find_child("ResultsOutcome", true, false)
		check(title.get_theme_color("font_color").get_luminance() > 0.4, "outcome text contrasts with dark surface")
		var stats: Dictionary = page.detail_stats()
		for key: String in ["fallen", "wounded", "lessons", "loot"]:
			check(not bool(stats["sections"][key]["open"]) and int(stats["sections"][key]["rows"]) == 0 and int(stats["sections"][key]["entries"]) == 0, "closed " + key + " has no hidden full list")
		check(descendants(page) < 100, "closed 200/200 result uses a compact control tree")
		var expected: Dictionary = BattleResultSummary.build(result)
		for side in 2:
			for metric: String in ["slain", "seriously_wounded", "other_wounded", "unhurt", "fled"]:
				var value: Label = page.find_child("Side%d_%s" % [side, metric], true, false)
				check(value != null and value.text == str(int(expected["sides"][side][metric])), "actual both-side " + metric + " total")
		check("overlaps" in labels(page.find_child("RetreatOverlap", true, false)), "retreat is explicitly overlapping survivors")
		check("173" in labels(page.find_child("ResultsLootTotal", true, false)) and "Returned gear: 11" in labels(page.find_child("ResultsLootTotal", true, false)), "settled loot and returned gear visible upfront")
		check("6 meals" in labels(page.find_child("ResultsSupplies", true, false)) and "2 mugs of beer" in labels(page.find_child("ResultsSupplies", true, false)), "actual native supplies visible upfront")
		check("Native 0-0" in labels(page.find_child("ResultsOfficerLosses", true, false)) and "Native 1-0" in labels(page.find_child("ResultsOfficerLosses", true, false)), "important officer losses on both sides visible upfront")
		await capture(viewport, size, "closed")
		for key: String in ["wounded", "lessons", "loot", "fallen"]:
			start = Time.get_ticks_usec()
			(page.find_child(key.capitalize()+"Toggle", true, false) as Button).pressed.emit()
			timings.append({"size": [size.x, size.y], "action": "open_"+key, "us": Time.get_ticks_usec() - start})
			await settle()
			stats = page.detail_stats()
			var current: Dictionary = stats["sections"][key]
			check(stats["active"] == key and int(current["rows"]) == 18 and int(current["entries"]) > 18, "opened " + key + " builds exactly one bounded page")
			check(descendants(page) < 240, "opened " + key + " never allocates all 200 rows")
			for other: String in ["fallen", "wounded", "lessons", "loot"]:
				if other != key: check(int(stats["sections"][other]["rows"]) == 0, "other sections remain unbuilt")
			fit_check(fit, viewport, size, "v014 open " + key)
			if key == "wounded":
				var wound_text: String = labels(page.find_child("WoundedRows", true, false))
				check("Recovery:" in wound_text, "native status/recovery details reachable")
				check("lasting injury" in wound_text and "lasting damage remains" in wound_text, "healed open wounds do not imply a lost limb recovered")
				check("Recovery: not yet assessed" in wound_text, "unconscious survivor without an estimate is not described as healed")
			if key == "lessons": check("Enemy lesson" not in labels(page.find_child("LessonsRows", true, false)), "enemy learning remains outside company lessons")
			if key == "loot": check("Scrap proceeds: 22" in labels(page.find_child("LootRows", true, false)) and "Camp hoard: 38" in labels(page.find_child("LootRows", true, false)) and "Militia bonus: 7" in labels(page.find_child("LootRows", true, false)), "actual ancillary receipts preserved")
			await capture(viewport, size, key)
			(page.find_child(key.capitalize()+"Next", true, false) as Button).pressed.emit()
			await settle()
			check(int(page.detail_stats()["sections"][key]["page"]) == 1 and int(page.detail_stats()["sections"][key]["rows"]) <= 18, "next page keeps bounded rows")
			page.turn_page(key, 100000)
			await settle()
			current = page.detail_stats()["sections"][key]
			check(int(current["page"]) == ceili(float(current["entries"]) / 18) - 1, "last page clamps to real record count")
			check((page.find_child(key.capitalize()+"Next", true, false) as Button).disabled, "last page disables next")
			page.turn_page(key, -100000)
			await settle()
			check(int(page.detail_stats()["sections"][key]["page"]) == 0, "previous page clamps at first")
			(page.find_child(key.capitalize()+"Toggle", true, false) as Button).pressed.emit()
			await settle()
			check(int(page.detail_stats()["sections"][key]["rows"]) == 0 and int(page.detail_stats()["sections"][key]["entries"]) == 0, "closing drops rows and derived source for " + key)
		page.toggle_section("wounded"); page.toggle_section("loot")
		await settle()
		check(int(page.detail_stats()["sections"]["wounded"]["rows"]) == 0 and page.active_section == "loot", "switching sections frees the previous page")
		check(fingerprint(result) == before, "details do not mutate any native result/gear/body fields")
		viewport.queue_free(); page = null; performance = null; layer = null; viewport = null
		await settle()
	for outcome: Array in [[1, "Defeat"], [-1, "The field is undecided"]]:
		result["winner"] = outcome[0]
		var alternative: Control = (load("res://battle/aftermath.tscn") as PackedScene).instantiate()
		tree.root.add_child(alternative)
		await settle()
		check((alternative.find_child("ResultsOutcome", true, false) as Label).text == outcome[1], "native alternate outcome title")
		alternative.queue_free(); alternative = null
		await settle()
	result["winner"] = 0
	check(fingerprint(result) == before, "all outcome presentation preserves original complete result")
	# Native Continue must clear the consumed result and route to map.
	var continue_view: Control = (load("res://battle/aftermath.tscn") as PackedScene).instantiate()
	tree.root.add_child(continue_view)
	await settle()
	continue_view.continue_button.pressed.emit()
	check(Game.last_result.is_empty() and Game._active_screen == "map" and probe.path == Game.SCREENS["map"], "Continue uses native result-release/map route")
	continue_view.queue_free(); continue_view = null
	probe.queue_free(); probe = null
	await settle()
	check(Game.gold == original["gold"] and Game.day == original["day"] and Game.rng.state == original["rng"] and Unit._next_uid == original["unit"] and Item._next_uid == original["item"], "results UI never allocates registered identities or changes coins/time/RNG")
	Game.last_result = original["result"]; Game.main = original["main"]; Game._active_screen = original["screen"]; Game.screen_params = original["params"]
	if report_dir != "":
		# This private rendered runner stays offscreen/no-focus until it exits.
		tree.root.size = original["size"]
	fit.tree = null
	var fit_failures: int = int(fit.fails)
	fit = null; result = {}; original = {}
	await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before, "freed result pages/controls leave no new orphan nodes")
	var total_failures: int = fails + fit_failures
	if report_dir != "":
		var report: Dictionary = {"checks": checks, "failures": total_failures, "desktop_fit_cases": fit_cases,
			"sizes": [[1280,720],[1920,1080],[2560,1440]], "captures": captures, "timings": timings, "page_size": 18,
			"no_focus": tree.root.get_flag(Window.FLAG_NO_FOCUS), "offscreen": tree.root.position.x < 0,
			"no_phone_qa": true, "native_fixture": "200/200 native persons and wounds", "no_full_combat_log": true}
		var file: FileAccess = FileAccess.open(report_dir.path_join("battle-results-ui.json"), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
		else: check(false, "private result report writable"); total_failures += 1
	print("Battle results UI v014: ", checks, " assertions, ", fit_cases, " desktop fit cases; failures=", total_failures)
	tree = null
	return total_failures
