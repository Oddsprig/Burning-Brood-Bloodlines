extends Control
## The years before (Douglas: "simulate 5 years on startup so there's actually backgrounds"; 12:55: the player
## picks one day to 100 years on the New Campaign screen, ui/newgame.gd, stored as presim.total): a new
## campaign runs the world's own sim forward (CampaignWorld.presim_slice: families, businesses, loans, caravans,
## armies, wars, weddings, births and deaths) in resumable slices behind a progress bar, then hands the
## player the map. The company sits outside it (no wages, food or travel). Deterministic per seed: each day
## retains the same daily work and movement steps, whatever the frame rate.
##
## v0.014 (Douglas: "when doing a world start we need to add something to entertain the player"; "any chance we
## can watch the map build too?"): the screen shows a small world map (ui/presim_map.gd) and a chronicle
## (ui/presim_feed.gd).
## 1. The making of the world: generation runs in resumable slices behind the visible stage label and progress.
##    Once the complete world is ready, the map reveals its real
##    output stage by stage in the generator's order (land and sea, mountains and hills, forests, climate and
##    realms, towns and holds, roads), about six seconds; Skip jumps to the end. The sim does not run yet.
## 2. The years before: the sim runs in its frame budget as before; a few times a second (UI_TICK) the map
##    redraws and the chronicle reads the new records since its last read. Notable lines wait in a short queue
##    (the least notable dropped when it is full) and come out one at a time (LINE_GAP) so they can be read;
##    each one flashes the map where it happened.

const FRAME_BUDGET_USEC := 12000   # soft slice budget: one complete job may take longer
const UI_TICK := 0.2      # seconds between map redraws and chronicle reads while the years run
const LINE_GAP := 0.8     # seconds between chronicle lines
const QUEUE_MAX := 6      # chronicle lines waiting their turn
const FEED_LINES := 9     # lines on screen

const MapView := preload("res://ui/presim_map.gd")
const Feed := preload("res://ui/presim_feed.gd")

var bar: ProgressBar
var info: Label
var title_lbl: Label
var skip_btn: Button
var map_view = null   # presim_map.gd (untyped: its own methods are called on it)
var generation_placeholder: Control
var generation_label: Label
var feed_box: VBoxContainer
var feed = null   # presim_feed.gd
var queue: Array = []
var phase := "build"   # "generate", "build" (the map reveal) or "years"
var generation_state: Dictionary = {}   # caller-owned, never saved
var generation_started := false
var generation_frame_shown := false
var generation_seed := 0
var generation_slice_total_usec := 0   # view diagnostics, never saved
var generation_slice_worst_usec := 0
var generation_slice_count := 0
var tick := 0.0
var feed_tick := 0.0
var feed_last_done := 0
var gap := 0.0
var t0 := 0
var sim_state: Dictionary = {}   # retained partial day; empty only between completed days
var sim_slice_total_usec := 0   # view diagnostics, never saved
var sim_slice_worst_usec := 0
var sim_slice_count := 0
var columns: BoxContainer
var chronicle_panel: PanelContainer
var content_margin: MarginContainer

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.WOOD
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	var needs_generation := bool(Game.screen_params.get("new_world", false)) or Game.world.is_empty()
	generation_seed = int(Game.screen_params.get("seed", 0))
	var margin := MarginContainer.new()
	content_margin = margin
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var v := UiKit.vbox(10)
	margin.add_child(v)
	title_lbl = UiKit.label("The Making of the World", "H2", true)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_lbl)
	var row := BoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	columns = row
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	# the map
	var mp := _dark_panel()
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_stretch_ratio = 1.6
	row.add_child(mp)
	map_view = MapView.new()
	map_view.custom_minimum_size = Vector2(280, 180)
	mp.add_child(map_view)
	map_view.visible = false
	generation_placeholder = CenterContainer.new()
	mp.add_child(generation_placeholder)
	generation_label = UiKit.label("Preparing the world...", "Header", true)
	generation_label.custom_minimum_size.x = 180
	generation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	generation_placeholder.add_child(generation_label)
	# the chronicle
	var fp := _dark_panel()
	fp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chronicle_panel = fp
	row.add_child(fp)
	var fv := UiKit.vbox(6)
	fp.add_child(fv)
	var fh := UiKit.label("Chronicle", "Header")
	fh.add_theme_color_override("font_color", UiTheme.BRASS)
	fv.add_child(fh)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fv.add_child(sc)
	feed_box = UiKit.vbox(8)
	feed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(feed_box)
	# the season line, the bar and Skip
	info = UiKit.label("", "Small", true)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	var brow := UiKit.hbox(12)
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(brow)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(100, 28)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.show_percentage = true
	brow.add_child(bar)
	skip_btn = UiKit.button("Skip", _skip_build, "Row", 120)
	brow.add_child(skip_btn)
	resized.connect(_fit_layout)
	_fit_layout()
	t0 = Time.get_ticks_msec()
	if needs_generation:
		phase = "generate"
		info.text = "Preparing the world..."
		skip_btn.visible = false
	else:
		_world_ready()

## A partial world must never reach the map or chronicle initialization.
func _world_ready() -> void:
	map_view.setup(Game.world)
	map_view.visible = true
	generation_placeholder.visible = false
	skip_btn.visible = true
	phase = "build"
	info.text = "The making of the world: land and sea"
	bar.value = 0.0

func _dark_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.WOOD_2
	sb.border_color = UiTheme.BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _fit_layout() -> void:
	if columns == null:
		return
	var lane := UiKit.diagnostics_lane(size.x)
	content_margin.offset_right = -lane
	var narrow := size.x - lane < 700
	columns.vertical = narrow
	chronicle_panel.custom_minimum_size = Vector2(0 if narrow else 280, 120 if narrow else 0)
	map_view.custom_minimum_size = Vector2(180, 120 if size.y < 500 else 180)
	title_lbl.add_theme_font_size_override("font_size", 22 if size.y < 500 else 28)

func _skip_build() -> void:
	if phase == "build":
		map_view.skip_build()

func _start_years() -> void:
	if phase != "build":
		return
	phase = "years"
	map_view.finish_build()
	skip_btn.visible = false
	title_lbl.text = "The Days Before" if CampaignWorld.presim_total(Game) < CampaignWorld.PRESIM_YEAR_DAYS else "The Years Before"
	feed = Feed.new()
	feed.setup(Game)
	tick = 0.0
	feed_tick = 0.0
	feed_last_done = CampaignWorld.presim_total(Game) - CampaignWorld.presim_left(Game)
	sim_state.clear()
	sim_slice_total_usec = 0
	sim_slice_worst_usec = 0
	sim_slice_count = 0
	gap = 0.0

func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_process_startup(delta)
	Perf.record_us("Campaign startup", Time.get_ticks_usec() - started, true)
	Perf.set_stage("Creating world" if phase == "generate" else "Campaign history")
	CampaignWorld.performance_queue(Game)

func _process_startup(delta: float) -> void:
	if phase == "generate":
		# Let the completed loading layout draw before the first generation work.
		if not generation_frame_shown:
			generation_frame_shown = true
			return
		var generation_begin := Time.get_ticks_usec()
		if not generation_started:
			generation_state = Game.new_game_begin(generation_seed)
			generation_started = true
		var remaining_budget := FRAME_BUDGET_USEC - (Time.get_ticks_usec() - generation_begin)
		var complete := false
		if remaining_budget > 0:
			complete = Game.new_game_slice(generation_state, remaining_budget)
		var generation_usec := Time.get_ticks_usec() - generation_begin
		generation_slice_total_usec += generation_usec
		generation_slice_worst_usec = maxi(generation_slice_worst_usec, generation_usec)
		generation_slice_count += 1
		if complete:
			_world_ready()
		else:
			var stage := CampaignWorld.generation_stage_name(generation_state)
			info.text = "The making of the world: %s" % stage.to_lower()
			generation_label.text = stage
			bar.value = CampaignWorld.generation_progress(generation_state)
		return
	if phase == "build":
		if map_view.advance_build(delta):
			_start_years()
		else:
			info.text = "The making of the world: %s" % map_view.stage_name().to_lower()
			bar.value = map_view.build_t / map_view.build_total()
			return
	var start := Time.get_ticks_usec()
	var left := CampaignWorld.presim_slice(Game, sim_state, FRAME_BUDGET_USEC)
	var slice_usec := Time.get_ticks_usec() - start
	sim_slice_total_usec += slice_usec
	sim_slice_worst_usec = maxi(sim_slice_worst_usec, slice_usec)
	sim_slice_count += 1
	var total := CampaignWorld.presim_total(Game)
	bar.value = 1.0 - float(left) / float(maxi(1, total))
	var done := total - left
	info.text = history_progress_text(done, total, Calendar.season(Game.day).capitalize())
	# the map and the chronicle, a few times a second
	tick -= delta
	if tick <= 0.0:
		tick = UI_TICK
		map_view.queue_redraw()
	# Wait for a completed day before reading records. A partial day's work may span several frames.
	feed_tick -= delta
	if feed_tick <= 0.0 and sim_state.is_empty() and done > feed_last_done:
		feed_tick = UI_TICK
		feed_last_done = done
		for ev in feed.poll(Game):
			queue.append(ev)
		while queue.size() > QUEUE_MAX:
			_drop_least()
	gap -= delta
	if gap <= 0.0 and not queue.is_empty():
		gap = LINE_GAP
		_add_line(queue.pop_front())
	if left <= 0 and sim_state.is_empty():
		set_process(false)
		CampaignWorld.presim_finish(Game, Time.get_ticks_msec() - t0)
		Dynasty.prepare_world(Game)
		Game.new_game_finalize()
		Game.save_game_async()
		Game.goto("house_select")

static func history_progress_text(done: int, total: int, season: String) -> String:
	var progress := "%d / %d day%s" % [clampi(done, 0, total), total, "" if total == 1 else "s"]
	if total >= CampaignWorld.PRESIM_YEAR_DAYS:
		progress += " · %s of history" % CampaignWorld.presim_span_text(total)
	return "%s · %s" % [season, progress]

## The queue is full: the least notable line goes (the oldest of them).
func _drop_least() -> void:
	var worst := 0
	for i in queue.size():
		if int(queue[i]["pri"]) < int(queue[worst]["pri"]):
			worst = i
	queue.remove_at(worst)

## One chronicle line at the top (newest first; the oldest fall off the bottom and fade as they go down),
## and a flash on the map where it happened.
func _add_line(ev: Dictionary) -> void:
	var pri := int(ev["pri"])
	var box := UiKit.vbox(0)
	var dl := UiKit.label(feed.date_text(float(ev["day"])))
	dl.add_theme_font_size_override("font_size", 14)
	dl.add_theme_color_override("font_color", UiTheme.BRASS)
	box.add_child(dl)
	var tl := UiKit.label(String(ev["text"]), "", true)
	tl.add_theme_font_size_override("font_size", 16)
	tl.add_theme_color_override("font_color", Color("#ffb4a0") if pri >= 4 else UiTheme.LIGHT)
	box.add_child(tl)
	feed_box.add_child(box)
	feed_box.move_child(box, 0)
	while feed_box.get_child_count() > FEED_LINES:
		var old := feed_box.get_child(feed_box.get_child_count() - 1)
		feed_box.remove_child(old)
		old.queue_free()
	for i in feed_box.get_child_count():
		var c := feed_box.get_child(i) as Control
		c.modulate = Color(1, 1, 1, 1.0 - 0.08 * i)
	if ev.has("pos"):
		map_view.flash(ev["pos"], Color("#ff6a4a") if pri >= 3 else UiTheme.BRASS)
