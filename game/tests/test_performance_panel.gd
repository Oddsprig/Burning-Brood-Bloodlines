extends RefCounted
## Desktop diagnostics only: no campaign generation, instrumentation or art.
const DESKTOP := Vector2i(1280, 720)
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0

class HudOnlyBattle:
	extends "res://battle/battle.gd"
	func _ready() -> void:
		_build_ui()
		set_process(false)

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL performance panel: ", why)

func settle() -> void:
	for _i in 5: await tree.process_frame

static func descendants(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children(): count += 1 + descendants(child)
	return count

static func job(data: Dictionary, label: String) -> Dictionary:
	for row: Dictionary in data["jobs"]:
		if String(row["label"]) == label: return row
	return {}

func fit_check(fit: RefCounted, viewport: SubViewport, why: String) -> void:
	fit_cases += 1
	fit._check(viewport, Vector2(DESKTOP), why)

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var original_overlay := bool(Game.setting("show_performance"))
	Game.settings["show_performance"] = false
	check(UiKit.diagnostics_lane(DESKTOP.x) == 0, "hidden diagnostics reserve no desktop lane")
	Game.settings["show_performance"] = true
	var orphan_baseline: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var tracker := PerformanceTracker.new()
	tree.root.add_child(tracker)
	tracker.set_process(false)
	tracker.record_us("Market", 1000)
	tracker.record_us("Market", 3000)
	tracker.record_us("Whole slice", 7000, true)
	tracker.record_queue(4, 2.5); tracker.set_stage("Paused")
	var data: Dictionary = tracker.snapshot()
	var market: Dictionary = job(data, "Market")
	check(int(market["calls"]) == 2 and int(market["session_latest_us"]) == 3000, "per-call count and latest timing")
	check(float(market["session_mean_us"]) == 2000 and int(market["session_peak_us"]) == 3000, "actual mean and session spike")
	check(int(data["overall"]["calls"]) == 1 and int(data["overall"]["session_peak_us"]) == 7000, "overall work is recorded independently of nested jobs")
	check(data["jobs"].size() == 1, "inclusive overall timing does not enter job list")
	check(int(data["queue_size"]) == 4 and float(data["oldest_days"]) == 2.5 and String(data["stage"]) == "Paused", "actual queue and paused stage")
	check(float(data["recent_window_s"]) >= 0.5 and float(data["recent_window_s"]) < 1.0, "bounded rolling sample span is stated")
	market["calls"] = 999; data["overall"]["calls"] = 999; data["engine"]["nodes"] = -999
	check(int(job(tracker.snapshot(), "Market")["calls"]) == 2 and int(tracker.snapshot()["overall"]["calls"]) == 1, "timing snapshots own their dictionaries")
	check(int(tracker.snapshot()["engine"]["nodes"]) >= 0, "engine snapshot does not alias cached counters")
	tracker.record_us("Market", -1)
	check(int(tracker.snapshot()["invalid_samples"]) == 1 and int(job(tracker.snapshot(), "Market")["calls"]) == 2, "negative durations rejected")
	tracker.record_queue(-4, 5.0)
	check(int(tracker.snapshot()["queue_size"]) == 0 and float(tracker.snapshot()["oldest_days"]) == 0, "empty queue cannot retain a backlog age")
	tracker.record_queue(3, NAN)
	check(float(tracker.snapshot()["oldest_days"]) == 0, "nonfinite backlog age rejected")
	tracker.set_stage("res://campaign/private_path.gd")
	check(String(tracker.snapshot()["stage"]) == "Private Path", "technical paths do not appear in panel stages")
	for i in PerformanceTracker.LABEL_LIMIT + 12: tracker.record_us("Task %02d" % i, i * 100)
	data = tracker.snapshot()
	check(data["jobs"].size() == PerformanceTracker.LABEL_LIMIT and int(data["dropped_labels"]) == 13, "label slots remain bounded without growing logs")
	check(float(job(data, "Market")["session_mean_us"]) == 2000, "label overflow leaves existing statistics intact")
	tracker.record_us("Market", 5000)
	check(int(job(tracker.snapshot(), "Market")["calls"]) == 3, "existing labels remain usable after capacity reached")
	# Expiry uses the monotonic wall clock, not engine delta/time scaling.
	var expires_at := Time.get_ticks_msec() + 1100
	while Time.get_ticks_msec() < expires_at: await tree.process_frame
	data = tracker.snapshot(); market = job(data, "Market")
	check(int(market["recent_calls"]) == 0 and float(market["total_us"]) == 0 and int(market["latest_us"]) == 0, "old current timings expire after idle")
	check(int(market["session_peak_us"]) == 5000 and int(market["calls"]) == 3, "idle expiry retains session spike and calls")
	check(int(data["overall"]["recent_calls"]) == 0 and int(data["overall"]["session_peak_us"]) == 7000, "overall current work expires separately from peak")
	tracker.record_us("Market", 2000)
	data = tracker.snapshot()
	check(int(job(data, "Market")["recent_calls"]) == 1 and float(job(data, "Market")["mean_us"]) == 2000, "new work starts a fresh recent window")
	if not OS.is_debug_build():
		check(data["engine"]["memory_bytes"] == null and data["engine"]["orphans"] == null, "release-only unsupported counters remain unavailable")
	if DisplayServer.get_name() == "headless":
		check(data["engine"]["draw_calls"] == null and data["engine"]["texture_bytes"] == null, "headless renderer counters remain unavailable")
	check(PerformancePanel._memory_text(null) == "unavailable" and PerformancePanel._count(null) == "unavailable", "unavailable counters never masquerade as zero")
	var viewport := SubViewport.new()
	viewport.size = DESKTOP; viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var panel := PerformancePanel.new(); panel.setup(tracker); viewport.add_child(panel)
	panel.set_process(false)
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	await settle(); fit_check(fit, viewport, "performance expanded desktop")
	check(panel.get_rect().size.x == 240 and panel.get_rect().end.x <= DESKTOP.x - 7, "moderate panel stays on desktop right edge")
	check(panel._toggle.size.y >= 48, "collapse control keeps native usable height")
	check("Main-thread" in panel._work.text and "not GPU time" in panel._source.text, "instrumented main-thread work and GPU time are distinguished")
	check("Sprite cache:" in panel._sprite_cache.text and "overhead are extra" in panel._sprite_cache.text, "cache payload is visible without being described as whole-process memory")
	check("queue" in panel._queue.text or "Campaign jobs" in panel._queue.text, "campaign backlog is visible")
	var before: int = descendants(panel)
	for _i in 30: panel._refresh()
	check(descendants(panel) == before, "text refresh never allocates replacement controls")
	panel.toggle(); await settle(); fit_check(fit, viewport, "performance collapsed desktop")
	check(not panel._details.visible and panel.size.y <= 65, "collapsed panel releases most screen space")
	panel.toggle(); await settle(); fit_check(fit, viewport, "performance reopened desktop")
	check(panel._details.visible and float(tracker.snapshot()["opened_s"]) < 1, "reopening resets memory-change baseline")
	var count: int = int(tracker.snapshot()["sample_count"])
	panel._process(0.1)
	check(int(tracker.snapshot()["sample_count"]) == count, "panel reads cached monitors without forcing engine sampling")
	check(UiKit.diagnostics_lane(1280) == 256 and UiKit.diagnostics_lane(844) == 0, "desktop lane guard preserves narrow layout foundation")
	var host := Control.new(); viewport.add_child(host)
	var frame: Dictionary = UiKit.screen_frame(host, "Riverhold")
	var company: Button = UiKit.button("Company", func(): pass, "", 150)
	var leave: Button = UiKit.button("Leave", func(): pass, "Danger", 120)
	frame["bar"].add_child(UiKit.spacer()); frame["bar"].add_child(company); frame["bar"].add_child(leave)
	await settle(); fit_check(fit, viewport, "shared desktop navigation beside diagnostics")
	check(leave.get_global_rect().end.x <= 1024 and company.get_global_rect().end.x <= 1024, "shared Company and Leave controls clear diagnostics lane")
	check(not leave.get_global_rect().intersects(panel.get_global_rect()), "shared navigation does not sit underneath persistent panel")
	host.queue_free(); host = null; await settle()
	var battle := HudOnlyBattle.new(); viewport.add_child(battle)
	battle.status_label.text = "Tick 100 · Copper Marches 100 vs Silverwood Alliance 100"
	battle.inspector.visible = true
	await settle(); fit_check(fit, viewport, "battle desktop inspector beside diagnostics")
	check(battle.inspector.get_global_rect().end.x <= 1024 and battle.inspector.size.x >= 470, "native battle inspector keeps width and clears lane")
	check(not battle.inspector.get_global_rect().intersects(panel.get_global_rect()), "battle inspector never overlaps performance panel")
	check(battle._playback_bar.get_global_rect().end.x <= 1015, "battle playback/status bar remains inside available desktop width")
	battle.queue_free(); battle = null; await settle()
	var settings: Control = (load("res://ui/settings.tscn") as PackedScene).instantiate()
	viewport.add_child(settings)
	await settle(); fit_check(fit, viewport, "settings desktop navigation beside diagnostics")
	var margin: MarginContainer = null
	for child: Node in settings.get_children():
		if child is MarginContainer: margin = child
	check(margin != null and margin.get_global_rect().end.x <= 1024, "Settings Back and choices clear diagnostics lane")
	settings.queue_free(); settings = null; await settle()
	var startup: Control = (load("res://ui/presim.tscn") as PackedScene).instantiate()
	viewport.add_child(startup); startup.set_process(false)
	startup.skip_btn.visible = true
	await settle(); fit_check(fit, viewport, "fresh startup controls beside diagnostics")
	check(startup.content_margin.get_global_rect().end.x <= 1024, "world creation content clears diagnostics lane")
	check(startup.skip_btn.get_global_rect().end.x <= 1024 and not startup.skip_btn.get_global_rect().intersects(panel.get_global_rect()), "Skip control remains reachable beside diagnostics")
	startup.queue_free(); startup = null; await settle()
	fails += fit.fails
	viewport.queue_free(); tracker.queue_free()
	panel = null; viewport = null; tracker = null; fit.tree = null; fit = null
	await settle()
	if OS.is_debug_build(): check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_baseline, "persistent panel and tracker leave no orphan nodes")
	print("Performance panel UI: ", checks, " assertions, ", fit_cases, " desktop fit cases; failures=", fails)
	Game.settings["show_performance"] = original_overlay
	tree = null
	return fails
