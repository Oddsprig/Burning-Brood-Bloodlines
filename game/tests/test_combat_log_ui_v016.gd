extends RefCounted
## Actual native strikes plus bounded journal stress; optional private desktop captures.
const SimUtil = preload("res://tests/sim_util.gd")
const SummaryFixture = preload("res://tests/test_battle_result_summary_v014.gd")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440)]
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0
var report_dir: String = ""
var captures: Array = []
var timings: Array = []

class PausedCapture extends "res://battle/battle.gd":
	func _ready() -> void:
		# Reuse actual native presentation and overlay; no new setup/step/result/accounting.
		_journal_transferred = true
		Paperdoll.begin_background()
		_build_world(16016)
		_build_ui()
		_fit_camera()
		_update_status()
		paused = true
		set_process(false)
	func finish() -> void:
		push_error("Paused capture must never settle a campaign result")

class RouteProbe extends Node:
	var path: String = ""
	func show_screen(value: String) -> void: path = value

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL combat log UI: ", why)

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

static func result_fingerprint(value: Dictionary) -> String:
	var plain: Dictionary = value.duplicate()
	plain.erase("combat_journal")
	return JSON.stringify(Game._serialize(plain), "", true, true).sha256_text()

static func native_fingerprint(sim: BattleSim) -> String:
	var units: Array = []
	for fighter: Fighter in sim.fighters:
		units.append({"unit": fighter.unit.to_dict(), "parts": fighter.unit.body.parts.duplicate(true),
			"state": fighter.state, "log": fighter.log.duplicate(true)})
	return JSON.stringify(Game._serialize({"units": units, "events": sim.events, "tick": sim.tick,
		"rng": sim.rng.state}), "", true, true).sha256_text()

static func journal_fingerprint(journal: CombatJournal) -> String:
	var rows: Array = []
	for index: int in range(ceili(float(journal.count()) / 18)):
		rows.append_array(journal.page(index, -1, 18))
	return JSON.stringify(rows, "", true, true).sha256_text()

func fit_check(fit: RefCounted, viewport: SubViewport, size: Vector2i, label: String) -> void:
	fit_cases += 1
	fit._check(viewport, Vector2(size), label)

func width_check(browser: CombatLogBrowser, context: String) -> void:
	var rows: Control = browser.find_child("CombatLogRows", true, false)
	var bar: VScrollBar = browser.rows_scroll.get_v_scroll_bar()
	var available: float = browser.rows_scroll.size.x - (bar.size.x if bar.visible else 0.0)
	check(rows.size.x >= available - 4.0, context + " row column fills real scroll content width")
	var stories_fit: bool = true
	var buttons_fit: bool = true
	var count: int = 0
	for card: Node in rows.get_children():
		if not card.get_meta("combat_log_row", false): continue
		count += 1
		var line: Label = card.find_child("CombatLogLine", true, false)
		var seq: int = int(card.get_meta("sequence", -1))
		var button: Button = card.find_child("CombatLogDetails%d" % seq, true, false)
		var surface: StyleBox = (card as PanelContainer).get_theme_stylebox("panel")
		var expected: float = (card as Control).size.x - surface.get_minimum_size().x - button.size.x - 8.0
		stories_fit = stories_fit and line.size.x >= expected - 2.0 and line.size.x >= 300.0
		buttons_fit = buttons_fit and button.size.y <= button.get_combined_minimum_size().y + 1.0
	check(count > 0 and stories_fit, context + " stories use available readable width instead of narrow strips")
	check(count > 0 and buttons_fit, context + " Details buttons retain their natural height")

func capture(viewport: SubViewport, size: Vector2i, state: String, browser: CombatLogBrowser = null) -> void:
	if report_dir == "": return
	# Polling is deliberately2Hz; capture the actual current tracker immediately.
	for panel: Node in viewport.find_children("*", "", true, false):
		if panel is PerformancePanel: (panel as PerformancePanel)._refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var started: int = Time.get_ticks_usec()
	var path: String = report_dir.path_join("combat_log_%dx%d_%s.png" % [size.x, size.y, state])
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == size, "native rendered viewport size: " + state)
	var saved: bool = image != null and image.save_png(path) == OK
	check(saved, "private native PNG saved: " + state)
	captures.append({"path": path, "sha256": FileAccess.get_sha256(path) if saved else "", "size": [size.x, size.y],
		"state": state, "capture_us": Time.get_ticks_usec() - started,
		"page": browser.page_index if browser != null else -1,
		"participant": browser.participant if browser != null else -1,
		"rows": int(browser.detail_stats()["rows"]) if browser != null else 0})

func capture_results_log(page: Control, viewport: SubViewport, size: Vector2i, journal: CombatJournal) -> void:
	if report_dir == "": return
	var browser: CombatLogBrowser = page.find_child("ResultCombatLog", true, false)
	await capture(viewport, size, "results_log_first", browser)
	browser.set_participant(3)
	await settle()
	check((browser.find_child("CombatLogParticipant", true, false) as OptionButton).text.contains("Bryn · fallen"), "rendered filter displays the frozen fallen name")
	await capture(viewport, size, "results_log_fallen", browser)
	browser.set_participant(-1)
	var found: bool = false
	var target_page: int = 0
	var seq: int = -1
	# Bounded fixture probe, not UI searching the whole fight.
	for index in 3:
		for row: Dictionary in journal.page(index, -1, 18):
			if String(row["entry"].get("k", "")) != "strike": continue
			var text: Dictionary = CombatText.render((row["entry"] as Dictionary).duplicate(true))
			if (text.get("detail", []) as Array).is_empty() or String(text.get("calc", "")) == "": continue
			found = true; target_page = index; seq = int(row["seq"])
			break
		if found: break
	check(found, "native capture has an actual tissue/calculation strike near the first page")
	if found:
		browser.turn_page(target_page)
		(browser.find_child("CombatLogDetails%d" % seq, true, false) as Button).pressed.emit()
		await settle()
		var card: Control = browser.find_child("CombatLogRow%d" % seq, true, false)
		browser.rows_scroll.scroll_vertical += int(card.get_global_rect().position.y - browser.rows_scroll.get_global_rect().position.y)
		await settle()
		check(browser.detail_stats()["expanded_rows"] == 1 and "Calculations:" in labels(card), "native rendered details expose actual calculation text")
	await capture(viewport, size, "results_log_tissue", browser)
	browser.set_participant(-1)
	await settle()

func capture_paused(sim: BattleSim, size: Vector2i, fit: RefCounted) -> void:
	if report_dir == "": return
	var viewport := SubViewport.new(); viewport.size = size; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var battle := PausedCapture.new(); battle.sim = sim
	viewport.add_child(battle)
	var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
	var performance := PerformancePanel.new(); performance.setup(Perf); layer.add_child(performance)
	var before: String = native_fingerprint(sim)
	battle.open_combat_log(3)
	await settle()
	var browser: CombatLogBrowser = battle.find_child("BattleLogBrowser", true, false)
	check(battle.paused and browser != null and browser.participant == 3, "actual battle overlay pauses and selects native Fighter.idx")
	fit_check(fit, viewport, size, "v016 actual paused battle log")
	width_check(browser, "paused battle")
	check((battle.find_child("BattleLogClose", true, false) as Button).get_global_rect().end.x <= size.x - UiKit.diagnostics_lane(size.x) + 1, "paused overlay leaves diagnostics lane clear")
	await capture(viewport, size, "battle_paused_log", browser)
	(battle.find_child("BattleLogClose", true, false) as Button).pressed.emit()
	check(battle.paused and not is_instance_valid(battle._log_overlay), "Back to battle restores prior pause")
	check(native_fingerprint(sim) == before, "native paused render and overlay preserve actual fight state")
	viewport.queue_free(); viewport = null; battle = null; browser = null; layer = null; performance = null
	await settle()
	check(not bool(sim.combat_journal.stats()["disposed"]), "borrowed capture journal remains owned by native fixture")

func _native_sim() -> BattleSim:
	var a: Array = [SimUtil.soldier("bronze", "arming_sword", "", "", ""), SimUtil.soldier("bronze", "arming_sword", "", "", "")]
	var b: Array = [SimUtil.soldier("bronze", "arming_sword", "", "", ""), SimUtil.soldier("bronze", "arming_sword", "", "", "")]
	a[0].name = "Rowan"; a[1].name = "Rowan"; b[0].name = "Edda"; b[1].name = "Bryn"
	var sim := BattleSim.new()
	sim.setup(a, b, 16016, {"w": 8, "h": 6, "log_moves": true, "max_ticks": 180, "verbose": true})
	# Native inspection hook performs real coverage, tissue/gear and blood calculations.
	for i in 4: sim.debug_strike(i % 2, 2 + i % 2, "arm_upper_l", 0, true)
	for _i in 120:
		if sim.is_over(): break
		sim.step()
	sim.flush_combat_journal()
	return sim

func _stress_journal(native: CombatJournal) -> CombatJournal:
	var result := CombatJournal.new()
	var people: Array = native.participants()
	# The UI must distinguish frozen Fighter.idx even when imported unit UIDs collide.
	people[1]["unit_uid"] = people[0]["unit_uid"]
	people[3]["name"] = "Bryn · fallen"
	result.setup(people)
	var source: Array = []
	for index: int in range(ceili(float(native.count()) / 18)): source.append_array(native.page(index, -1, 18))
	if source.is_empty(): return result
	# Replaying detached real outcomes is an indexed-page stress fixture, not a new fight.
	for i in 600:
		var row: Dictionary = source[i % source.size()]
		var entry: Dictionary = (row["entry"] as Dictionary).duplicate(true)
		entry["tick"] = i
		result.append(entry, int(row["actor"]), int(row["target"]), String(row["event_type"]))
	return result

func _browser(viewport: SubViewport, journal: CombatJournal) -> CombatLogBrowser:
	var browser := CombatLogBrowser.new()
	browser.begin(journal, ["Our force", "Their force"])
	viewport.add_child(browser)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser.offset_left = 16; browser.offset_top = 16; browser.offset_bottom = -16
	browser.offset_right = -16 - UiKit.diagnostics_lane(viewport.size.x)
	return browser

func _page_matches(browser: CombatLogBrowser, journal: CombatJournal) -> bool:
	var expected: Array = journal.page(browser.page_index, browser.participant, 18)
	var cards: Array = browser.find_child("CombatLogRows", true, false).get_children().filter(func(node: Node): return node.get_meta("combat_log_row", false))
	if cards.size() != expected.size(): return false
	for i in expected.size():
		if int(cards[i].get_meta("sequence", -1)) != int(expected[i]["seq"]): return false
		var detached: Dictionary = (expected[i]["entry"] as Dictionary).duplicate(true)
		var rendered: Dictionary = CombatText.render(detached)
		if String(rendered.get("text", "")) not in labels(cards[i]): return false
	return true

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var started: int = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
	if report_dir != "":
		check(report_dir.is_absolute_path() and report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v016-ui-render/"), "capture path stays in private v016 UI work directory")
		check(DisplayServer.get_name() != "headless", "optional report requires actual native renderer")
		if fails > 0: tree = null; return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("combat-log-ui.json")), "render evidence uses fresh writable report directory")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
		tree.root.position = Vector2i(-20000, -20000)
		# Window is revealed only after no-focus/offscreen guards are set.
		tree.root.visible = true
		check(tree.root.get_flag(Window.FLAG_NO_FOCUS) and tree.root.position.x < 0, "native capture remains no-focus/offscreen")
	var original: Dictionary = {"result": Game.last_result, "main": Game.main, "screen": Game._active_screen,
		"params": Game.screen_params, "gold": Game.gold, "day": Game.day, "rng": Game.rng.state,
		"unit": Unit._next_uid, "item": Item._next_uid, "size": tree.root.size}
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var sim: BattleSim = _native_sim()
	var native: CombatJournal = sim.combat_journal
	check(native != null and native.count() > 18 and bool(native.stats()["complete"]), "native small fight provides a complete paged journal")
	var sim_before: String = native_fingerprint(sim)
	var journal: CombatJournal = _stress_journal(native)
	check(journal.count() == 600 and int(journal.stats()["chunk_files"]) >= 2, "stress fixture uses actual indexed disk chunks")
	check(journal.participant(0)["unit_uid"] == journal.participant(1)["unit_uid"], "duplicate UID fixture remains separate frozen indexes")
	var journal_before: String = journal_fingerprint(journal)
	var native_detail: bool = false
	var native_calc: bool = false
	var native_weapon: bool = false
	for index: int in range(ceili(float(native.count()) / 18)):
		for row: Dictionary in native.page(index, -1, 18):
			var rendered: Dictionary = CombatText.render((row["entry"] as Dictionary).duplicate(true))
			if String(row["entry"].get("k", "")) == "strike":
				native_detail = native_detail or not (rendered.get("detail", []) as Array).is_empty()
				native_calc = native_calc or String(rendered.get("calc", "")) != ""
				native_weapon = native_weapon or "sword" in String(rendered.get("text", "")).to_lower()
	check(native_detail, "fixture records actual native tissue/armor detail")
	check(native_calc, "fixture records actual native strike calculations")
	check(native_weapon, "fixture describes its actual weapon")
	var counters: Dictionary = {"unit": Unit._next_uid, "item": Item._next_uid, "gold": Game.gold, "day": Game.day, "rng": Game.rng.state}
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	for size: Vector2i in SIZES:
		var viewport := SubViewport.new(); viewport.size = size; viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var browser: CombatLogBrowser = _browser(viewport, journal)
		var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
		var performance := PerformancePanel.new(); performance.setup(Perf); layer.add_child(performance)
		await settle()
		fit_check(fit, viewport, size, "v016 chronological desktop log")
		width_check(browser, "standalone log")
		check(browser.get_global_rect().end.x <= size.x - UiKit.diagnostics_lane(size.x) + 1, "browser leaves diagnostics lane clear")
		check(browser.detail_stats()["rows"] == 18 and browser.detail_stats()["formatted_total"] == 18, "only visible first page is formatted")
		check(browser.detail_stats()["expanded_rows"] == 0 and descendants(browser) < 220, "no hidden full history/detail tree")
		check(_page_matches(browser, journal), "first page renders actual native descriptions in exact sequence")
		var selector: OptionButton = browser.find_child("CombatLogParticipant", true, false)
		check(selector.get_item_metadata(1) == 0 and selector.get_item_metadata(2) == 1 and selector.get_item_text(1) != selector.get_item_text(2), "duplicate names and UIDs select independent fighter indexes")
		check("Bryn · fallen" in selector.get_item_text(4), "frozen fallen participant remains searchable")
		var seq: int = int(journal.page(0, -1, 18)[0]["seq"])
		(browser.find_child("CombatLogDetails%d" % seq, true, false) as Button).pressed.emit()
		await settle()
		check(browser.detail_stats()["expanded_rows"] == 1 and browser.detail_stats()["formatted_total"] == 18, "opening recorded details does not reformat entries")
		check(descendants(browser.find_child("CombatLogExpanded%d" % seq, true, false)) > 0, "details/calculations or honest absence are reachable")
		fit_check(fit, viewport, size, "v016 expanded native log row")
		var second: int = int(journal.page(0, -1, 18)[1]["seq"])
		(browser.find_child("CombatLogDetails%d" % second, true, false) as Button).pressed.emit()
		check(browser.detail_stats()["expanded_rows"] == 1 and not (browser.find_child("CombatLogExpanded%d" % seq, true, false) as Control).visible, "one row expanded at a time")
		browser.refresh()
		check(browser.detail_stats()["expanded_rows"] == 0, "refresh drops row expansion consistently")
		(browser.find_child("CombatLogLast", true, false) as Button).pressed.emit()
		await settle()
		check(browser.page_index == 33 and browser.detail_stats()["rows"] == 6 and _page_matches(browser, journal), "Last jumps directly to actual final outcomes")
		check((browser.find_child("CombatLogNext", true, false) as Button).disabled and (browser.find_child("CombatLogLast", true, false) as Button).disabled, "last-page controls clamp correctly")
		(browser.find_child("CombatLogFirst", true, false) as Button).pressed.emit()
		browser.turn_page(1)
		check(browser.page_index == 1 and browser.detail_stats()["rows"] == 18 and _page_matches(browser, journal), "Next keeps chronological page order")
		browser.turn_page(-100000)
		check(browser.page_index == 0 and (browser.find_child("CombatLogPrevious", true, false) as Button).disabled, "Previous clamps at first")
		for idx in 4:
			browser.set_participant(idx)
			check(browser.participant == idx and browser.detail_stats()["matched_count"] == journal.count(idx) and _page_matches(browser, journal), "exact indexed actor/target filter %d" % idx)
			check(browser.detail_stats()["rows"] <= 18, "filtered controls remain bounded %d" % idx)
		browser.set_participant(-1)
		var formatted_before: int = int(browser.detail_stats()["formatted_total"])
		var search: LineEdit = browser.find_child("CombatLogSearch", true, false)
		search.text = "Bryn"
		# Programmatic text assignment does not emit native typed-input signals.
		search.text_changed.emit(search.text)
		check(selector.item_count == 2 and selector.get_item_metadata(1) == 3, "name search narrows frozen choices without scanning outcome text")
		check(browser.detail_stats()["formatted_total"] == formatted_before and browser.participant == -1, "search alone neither formats history nor changes filter")
		browser.set_participant(3)
		check(browser.detail_stats()["matched_count"] == journal.count(3), "dead-name search retains full participant history")
		formatted_before = int(browser.detail_stats()["formatted_total"])
		search.text = "Edda"; search.text_changed.emit(search.text)
		check(browser.participant == 3 and selector.item_count == 3 and selector.get_item_text(selector.selected).begins_with("Current: "), "unmatched current history stays explicitly labelled beside search matches")
		check(selector.get_item_metadata(1) == 2 and selector.get_item_metadata(2) == 3 and browser.detail_stats()["formatted_total"] == formatted_before, "name search offers actual match without reformatting or changing history")
		search.text = ""; search.text_changed.emit(search.text)
		check(selector.item_count == 5 and selector.get_item_metadata(selector.selected) == 3 and not selector.get_item_text(selector.selected).begins_with("Current: "), "clearing name search restores full roster and current selection")
		browser.set_participant(99999)
		check(browser.participant == -1, "invalid participant cannot create a fictitious identity")
		check(journal_fingerprint(journal) == journal_before and native_fingerprint(sim) == sim_before, "all browsing leaves native journal/units/gear/bodies/ticks/RNG unchanged")
		var browser_ref: WeakRef = weakref(browser)
		viewport.queue_free(); browser = null; viewport = null; performance = null; layer = null; selector = null; search = null
		await settle()
		check(browser_ref.get_ref() == null and not bool(journal.stats()["disposed"]), "browser close frees its controls but not shared journal")
	# Honest absent and incomplete states use the same native reader, not outcome mocks.
	var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var missing: CombatLogBrowser = _browser(viewport, null)
	await settle()
	check("No combat log recorded" in labels(missing) and missing.detail_stats()["rows"] == 0, "missing history is explicit")
	var broken := CombatJournal.new(); broken.setup(native.participants())
	check(not broken.append({"tick": 0, "invalid": sim.fighters[0].unit}, 0, 2), "native reader rejects object ownership and reports incomplete")
	var actual: Dictionary = native.page(0, -1, 18)[0]
	broken.append(actual["entry"], int(actual["actor"]), int(actual["target"]), String(actual["event_type"]))
	missing.begin(broken, ["Our force", "Their force"])
	await settle()
	check("Incomplete log: 1 readable outcomes" in labels(missing) and not bool(missing.detail_stats()["complete"]) and missing.detail_stats()["rows"] == 1, "failed capture never claims complete fight")
	viewport.queue_free(); viewport = null; missing = null
	await settle()
	check(not bool(broken.stats()["disposed"]), "closing incomplete reader never disposes shared journal")
	broken.dispose(); broken = null
	# Results keep all five closed toggles reachable, one lazy section, and native Continue.
	var result: Dictionary = SummaryFixture.fixture(200); result["combat_journal"] = journal
	var result_before: String = result_fingerprint(result)
	var probe := RouteProbe.new(); tree.root.add_child(probe); Game.main = probe
	Game.last_result = result; Game._active_screen = "aftermath"
	for size: Vector2i in SIZES:
		if report_dir != "": tree.root.size = size
		viewport = SubViewport.new(); viewport.size = size; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED; tree.root.add_child(viewport)
		var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
		var performance := PerformancePanel.new(); performance.setup(Perf); layer.add_child(performance)
		var opening: int = Time.get_ticks_usec()
		var page: Control = (load("res://battle/aftermath.tscn") as PackedScene).instantiate(); viewport.add_child(page)
		timings.append({"size": [size.x, size.y], "state": "results_closed", "build_us": Time.get_ticks_usec() - opening})
		await settle()
		fit_check(fit, viewport, size, "v016 five closed desktop results")
		check(descendants(page) < 110 and page.find_child("ResultCombatLog", true, false) == null, "closed results do not build journal pages")
		check(page.continue_button.get_global_rect().end.y <= size.y and page.frame.get_global_rect().end.x <= size.x - UiKit.diagnostics_lane(size.x) + 1, "Continue and diagnostics lane remain clear")
		for key: String in ["fallen", "wounded", "lessons", "loot", "log"]:
			var toggle: Button = page.find_child(key.capitalize() + "Toggle", true, false)
			check(page.body_scroll.get_global_rect().encloses(toggle.get_global_rect()), "all five closed detail toggles visible: " + key)
			check(page.detail_stats()["sections"][key]["rows"] == 0, "closed section has no off-page rows: " + key)
		await capture(viewport, size, "results_closed")
		opening = Time.get_ticks_usec()
		page.toggle_section("log")
		timings.append({"size": [size.x, size.y], "state": "results_log_first", "open_us": Time.get_ticks_usec() - opening})
		await settle()
		fit_check(fit, viewport, size, "v016 results log page")
		var result_browser: CombatLogBrowser = page.find_child("ResultCombatLog", true, false)
		width_check(result_browser, "results log")
		check(result_browser != null and result_browser.detail_stats()["rows"] == 18 and page.active_section == "log", "results lazily opens same bounded browser")
		check(page.continue_button.get_global_rect().end.y <= size.y, "Continue remains fixed outside expanded log")
		await capture_results_log(page, viewport, size, journal)
		page.turn_page("log", 100000)
		check(result_browser.page_index == 33 and result_browser.detail_stats()["rows"] == 6, "results delegates direct long-history access")
		var weak_browser: WeakRef = weakref(result_browser)
		page.toggle_section("wounded"); result_browser = null
		await settle()
		check(weak_browser.get_ref() == null and page.detail_stats()["sections"]["log"]["rows"] == 0 and page.active_section == "wounded", "opening wounds discards log browser/page cache")
		check(not bool(journal.stats()["disposed"]) and result_fingerprint(result) == result_before, "section changes retain shared history and original settled result")
		page.toggle_section("wounded")
		check(page.active_section == "" and page.detail_stats()["sections"]["wounded"]["rows"] == 0, "closing clears current derived detail list")
		viewport.queue_free(); page = null; viewport = null; layer = null; performance = null
		await settle()
		await capture_paused(sim, size, fit)
	var continue_view: Control = (load("res://battle/aftermath.tscn") as PackedScene).instantiate(); tree.root.add_child(continue_view)
	await settle()
	continue_view.continue_button.pressed.emit()
	check(Game.last_result.is_empty() and Game._active_screen == "map" and probe.path == Game.SCREENS["map"], "Continue uses existing native result-release/map route")
	check(bool(journal.stats()["disposed"]), "native result owner releases journal on Continue")
	continue_view.queue_free(); continue_view = null; probe.queue_free(); probe = null
	await settle()
	check(native_fingerprint(sim) == sim_before, "presentation and Continue never tick or rerun combat/growth")
	check(Game.gold == counters["gold"] and Game.day == counters["day"] and Game.rng.state == counters["rng"] and Unit._next_uid == counters["unit"] and Item._next_uid == counters["item"], "UI allocates no native identities and changes no coin/time/RNG")
	# A journal may outlive every actual fighter without retaining Unit or sim.
	var unit_ref: WeakRef = weakref(sim.fighters[0].unit)
	var sim_ref: WeakRef = weakref(sim)
	sim = null
	check(sim_ref.get_ref() == null and unit_ref.get_ref() == null and native.count() > 0, "journal owns no Unit/Fighter/sim references")
	native.dispose(); native = null; journal = null; result = {}; actual = {}
	Game.last_result = original["result"]; Game.main = original["main"]; Game._active_screen = original["screen"]; Game.screen_params = original["params"]
	if report_dir != "": tree.root.size = original["size"]
	Unit._next_uid = original["unit"]; Item._next_uid = original["item"]
	var fit_failures: int = int(fit.fails)
	fit.tree = null; fit = null; original = {}; counters = {}
	await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before, "closed/freed log and result views leave no new orphan controls")
	if report_dir != "":
		check(captures.size() == 15, "all five requested states at three actual desktop sizes captured")
		var report: Dictionary = {"checks": checks, "failures": fails + fit_failures, "desktop_fit_cases": fit_cases,
			"sizes": [[1280,720],[1920,1080],[2560,1440]], "captures": captures, "timings": timings,
			"duration_us": Time.get_ticks_usec() - started, "no_focus": tree.root.get_flag(Window.FLAG_NO_FOCUS),
			"offscreen": tree.root.position.x < 0, "no_phone_qa": true, "performance_panel": true,
			"page_size": 18, "native_fixture": "Four real native fighters/strikes; 600 detached outcome indexed stress; native 200/200 results"}
		var file: FileAccess = FileAccess.open(report_dir.path_join("combat-log-ui.json"), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
		else: check(false, "private native UI report writable")
	print("Combat log UI v016: ", checks, " assertions, ", fit_cases, " desktop fit cases; failures=", fails + fit_failures)
	tree = null
	return fails + fit_failures
