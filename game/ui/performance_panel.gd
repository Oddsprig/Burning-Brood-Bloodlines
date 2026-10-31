class_name PerformancePanel
extends Control
## Persistent diagnostics overlay. Controls are created once; text refresh <=2Hz.
const WIDTH := 240.0
const INTERVAL := 0.5
const JOB_ROWS := PerformanceTracker.LABEL_LIMIT
const CLOSED_HEIGHT := 64.0
var tracker: PerformanceTracker
var expanded: bool = true
var _clock: float = 0.0
var _frame: PanelContainer
var _toggle: Button
var _details: ScrollContainer
var _state: Label
var _frame_cost: Label
var _work: Label
var _queue: Label
var _memory: Label
var _counts: Label
var _sprite_cache: Label
var _combat_history: Label
var _ownership: Label
var _scan: Button
var _source: Label
var _jobs: Array[Label] = []

func setup(value: PerformanceTracker) -> void:
	tracker = value
	if is_node_ready():
		if expanded and tracker != null: tracker.mark_open()
		_clock = 0.0
		_refresh()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_frame = PanelContainer.new(); _frame.mouse_filter = Control.MOUSE_FILTER_PASS
	_frame.add_theme_stylebox_override("panel", UiTheme.sb(Color("#14251f"), Color("#70568b"), 1, 5, 8, 8))
	add_child(_frame)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 5); _frame.add_child(box)
	_toggle = Button.new(); _toggle.custom_minimum_size = Vector2(0, UiKit.touch_min(48))
	_toggle.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 15)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.pressed.connect(toggle)
	box.add_child(_toggle)
	_details = UiKit.scroll(); box.add_child(_details)
	var contents := UiKit.vbox(6); contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_child(contents)
	_state = _label(contents); _frame_cost = _label(contents); _work = _label(contents)
	_queue = _label(contents); _memory = _label(contents); _counts = _label(contents)
	_sprite_cache = _label(contents)
	_combat_history = _label(contents)
	_ownership = _label(contents)
	_scan = UiKit.button("Refresh owner counts", _refresh_owners)
	_scan.add_theme_font_size_override("font_size", 13)
	contents.add_child(_scan)
	var heading: Label = _label(contents); heading.text = "Calculations · ms per call"
	for _i in JOB_ROWS: _jobs.append(_label(contents))
	_source = _label(contents); _source.add_theme_font_size_override("font_size", 12)
	get_viewport().size_changed.connect(_fit)
	if tracker == null: tracker = get_node_or_null("/root/Perf") as PerformanceTracker
	if tracker != null: tracker.mark_open()
	_fit(); _refresh()

static func _label(parent: Node) -> Label:
	var value := Label.new()
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", 13)
	value.add_theme_color_override("font_color", Color("#e8e7df"))
	parent.add_child(value)
	return value

func _fit() -> void:
	var height: float = get_viewport_rect().size.y
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -WIDTH - 8; offset_right = -8; offset_top = 8
	offset_bottom = maxf(8 + CLOSED_HEIGHT, height - 8) if expanded else 8 + CLOSED_HEIGHT
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_details.visible = expanded
	_toggle.text = "Performance  ▼" if expanded else "Performance  ▶"

func toggle() -> void:
	expanded = not expanded
	_clock = 0.0
	if expanded and tracker != null: tracker.mark_open()
	_fit()
	# Immediate display of current cached counters; no new nodes or sampling loop.
	if expanded: _refresh()

func _process(delta: float) -> void:
	if not expanded: return
	_clock += delta
	if _clock >= INTERVAL:
		_clock = 0.0
		_refresh()

static func _memory_text(value: Variant) -> String:
	return "unavailable" if value == null else "%.1f MiB" % (float(value) / 1048576.0)

static func _count(value: Variant) -> String:
	return "unavailable" if value == null else str(int(value))

func _refresh_owners() -> void:
	if tracker == null: return
	var game: Node = get_node_or_null("/root/Game")
	tracker.refresh_owners(game)
	_refresh()

static func _owner_text(data: Dictionary) -> String:
	var text: String = "Owners: refresh to inspect"
	if bool(data.get("available", false)):
		var totals: Dictionary = data["totals"]
		var partial: bool = bool(data.get("truncated", false)) or bool(data.get("depth_limited", false))
		text = "%s checkpoint · %.0fs ago\nUnique units / bodies / items: %d / %d / %d\nStored wound parts / layers: %d / %d" % ["Partial" if partial else "Owner", float(data.get("age_s", 0.0)), int(totals["unit_unique"]), int(totals["body_unique"]), int(totals["item_unique"]), int(totals["wound_parts"]), int(totals["wound_layers"])]
		text += "\nRoot references: units / bodies / items"
		var roots: Dictionary = data["by_root"]
		for pair: Array in [["company", "Company"], ["world", "World"], ["pending_battle", "Battle"], ["last_result", "Result"], ["deploy_cache", "Deploy"]]:
			var row: Dictionary = roots.get(pair[0], {})
			text += "\n%s: %d / %d / %d" % [pair[1], int(row.get("unit_refs", 0)), int(row.get("body_refs", 0)), int(row.get("item_refs", 0))]
		text += "\nContainers: %d · Packed refs: %s" % [int(totals["dictionaries"]) + int(totals["arrays"]), _memory_text(totals["packed_numeric_bytes"])]
		if partial: text += "\nNative counts are lower bounds."
		var caches: Dictionary = data.get("caches", {})
		text += "\nDragon cached image pixels: %s\nDragon cached texture pixels: %s" % [_memory_text(caches.get("image_rgba_equivalent_bytes")), _memory_text(caches.get("texture_rgba_equivalent_bytes"))]
		if bool(caches.get("truncated", false)): text += "\nCache payload sample is partial."
	var terrain: Dictionary = data.get("terrain", {})
	if not terrain.is_empty(): text += "\nTerrain geometry: %s · %d RIDs\nTerrain texture pixels: %s" % [_memory_text(terrain.get("packed_bytes")), int(terrain.get("chunks", 0)), _memory_text(terrain.get("texture_rgba_estimate_bytes"))]
	var save: Dictionary = data.get("save", {})
	if not save.is_empty():
		text += "\nSave snapshots: %d · Pending: %s" % [int(save.get("active_snapshots", 0)), "yes" if bool(save.get("pending", false)) else "no"]
		if save.has("serialized_bytes"): text += "\nSave text payload: %s" % _memory_text(save["serialized_bytes"])
	return text

func _refresh() -> void:
	if not is_node_ready() or _state == null: return
	if tracker == null:
		_state.text = "Tracker unavailable"
		_source.text = "No instrumented work samples."
		for value: Label in [_frame_cost, _work, _queue, _memory, _counts, _sprite_cache, _combat_history, _ownership]: value.text = ""
		for value: Label in _jobs: value.visible = false
		return
	var data: Dictionary = tracker.snapshot()
	var engine: Dictionary = data["engine"]
	var overall: Dictionary = data["overall"]
	_state.text = String(data["stage"])
	if data["ownership"].get("save",{}).get("capturing",false): _state.text = "Saving world…"
	_frame_cost.text = "FPS: %.0f  ·  Frame: %.2f ms\nEngine process: %.2f ms\nPhysics: %.2f ms\nSampled peaks: %.2f / %.2f ms" % [float(engine["fps"]), float(engine["frame_ms"]), float(engine["process_ms"]), float(engine["physics_ms"]), float(data["process_sampled_peak_ms"]), float(data["physics_sampled_peak_ms"])]
	if float(engine["fps"]) <= 0:
		_frame_cost.text = "FPS / frame: waiting for sample\nEngine process: %.2f ms\nPhysics: %.2f ms" % [float(engine["process_ms"]), float(engine["physics_ms"])]
	var span: float = float(data["recent_window_s"])
	_work.text = "Main-thread work: %.2f ms / %.2fs\nCall mean / max: %.2f / %.2f ms\nSession max call: %.2f ms" % [float(overall["total_us"]) / 1000.0, span, float(overall["mean_us"]) / 1000.0, float(overall["peak_us"]) / 1000.0, float(overall["session_peak_us"]) / 1000.0]
	if int(overall["recent_calls"]) == 0: _work.text = "Main-thread work: idle\nSession max call: %.2f ms" % (float(overall["session_peak_us"]) / 1000.0)
	_queue.text = "Campaign jobs: %d" % int(data["queue_size"])
	_queue.text += " · oldest %.2f days" % float(data["oldest_days"]) if int(data["queue_size"]) > 0 else " · queue empty"
	var change: Variant = engine["memory_change_bytes"]
	var delta_text: String = "unavailable" if change == null else "%+.1f MiB" % (float(change) / 1048576.0)
	_memory.text = "Engine tracked RAM: %s\nChange since opening: %s\nEngine RAM peak: %s\nRenderer textures: %s" % [_memory_text(engine["memory_bytes"]), delta_text, _memory_text(engine["memory_peak_bytes"]), _memory_text(engine["texture_bytes"])]
	var process_memory: Dictionary = data["process_memory"]
	_memory.text += "\nOS private / working: %s / %s" % [_memory_text(process_memory["private_bytes"]), _memory_text(process_memory["working_bytes"])]
	var ownership: Dictionary = data["ownership"]
	_ownership.text = _owner_text(ownership)
	_counts.text = "Nodes: %s · Objects: %s\nResources: %s · Orphans: %s\nDraw calls: %s" % [_count(engine["nodes"]), _count(engine["objects"]), _count(engine["resources"]), _count(engine["orphans"]), _count(engine["draw_calls"])]
	var cache: Dictionary = ownership["sprites"]
	_sprite_cache.text = "Sprite cache: %d / %d frames\nCached pixels: %s / %s\nHits / misses: %d / %d\nEvicted: %d · Frame reuse: %d\nActive sprites and resource overhead are extra." % [int(cache["entries"]), int(cache["entry_limit"]), _memory_text(cache["payload_bytes"]), _memory_text(cache["byte_limit"]), int(cache["hits"]), int(cache["misses"]), int(cache["evictions"]), int(cache["frame_reuses"])]
	var background: Dictionary = cache["background"]
	_sprite_cache.text += "\nSprite workers: %d / %d\nWaiting sprites: %d" % [int(background["inflight"]), int(background["job_limit"]), int(background["pending"])]
	var history: Dictionary = ownership.get("combat_history", {})
	_combat_history.visible = not history.is_empty()
	if not history.is_empty():
		_combat_history.text = "Combat log: %d outcomes · %s\nResident records: %d / %d\nDisk payload / indexes: %s / %s" % [int(history.get("records",0)), "complete" if bool(history.get("complete",false)) else "INCOMPLETE", int(history.get("active_records",0))+int(history.get("cached_records",0)), int(history.get("memory_record_limit",1024)), _memory_text(history.get("disk_bytes",0)), _memory_text(history.get("index_bytes",0))]
		if String(history.get("error","")) != "": _combat_history.text += "\n" + String(history["error"])
	var jobs: Array = data["jobs"]
	for i in JOB_ROWS:
		_jobs[i].visible = i < jobs.size() or i == 0
		if i >= jobs.size(): _jobs[i].text = "No job timings yet." if i == 0 else ""; continue
		var job: Dictionary = jobs[i]
		_jobs[i].text = "%s\nLatest / mean / max: %.2f / %.2f / %.2f\nWindow total: %.2f ms\nSession peak: %.2f ms · %d calls" % [String(job["label"]), float(job["latest_us"]) / 1000.0, float(job["mean_us"]) / 1000.0, float(job["peak_us"]) / 1000.0, float(job["total_us"]) / 1000.0, float(job["session_peak_us"]) / 1000.0, int(job["calls"])]
	_source.text = "Work: recent %.2fs; session %.0fs. Engine sampled 2Hz; FPS updates 1Hz. Main-thread elapsed work is not GPU time. Sprite worker raster is background CPU elapsed time. Engine RAM/orphans require debug. Owner counts are manual/checkpoint reads. Pixel/packed payloads exclude overhead and are not total RAM. OS memory requires an external measurement." % [span, float(data["session_s"])]
	if int(data["dropped_labels"]) > 0: _source.text += " Extra work labels omitted."
