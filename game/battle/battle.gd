extends Node2D
## Battle screen. Builds the sim from Game.pending_battle, animates its ticks (it never drives game logic),
## and hands the result to Game.finish_battle when the sim is over.
##
## Reads only the BattleSim/Fighter contract (sim/battle_sim.gd, sim/fighter.gd): setup/step/is_over,
## tick, grid_w/h, tile_at, fighters, new_events, events, winner, event_text/render_entry; Fighter idx, unit,
## side, cell, prev_cell, facing, target, state, action_ticks, action_total, current_attack, log, prone,
## waiting, speed, wielded, weapon_dropped, bleeding. HealthReport.describe. Paperdoll (set_unit, set_pose,
## facing, team_color, invalidate, make_severed_piece). Viewport gating defers raster only;
## every actor still interpolates its position, flash, highlight and flee state.
## Event convention (as the sim emits it): actor = attacker, target = defender for attack/miss/dodge/block/
## parry/hit/wound/artery/sever/death; single-unit events have target -1.

const MapView := preload("res://battle/map_view.gd")
const UnitView := preload("res://battle/unit_view.gd")
const FxLayer := preload("res://battle/fx_layer.gd")
const Inspector := preload("res://battle/inspector.gd")
const LogBrowser := preload("res://battle/combat_log.gd")
const GoreLayer := preload("res://battle/gore_layer.gd")
const ReadabilityFx := preload("res://battle/readability_fx.gd")
const ReadabilityLegend := preload("res://battle/readability_legend.gd")
const MobilePerf := preload("res://core/mobile_perf.gd")

const TICKS_PER_SEC := 20.0           # sim ticks per real second at 1x (1 tick = 0.05 s: 1x is real time)
const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const SMALL_GRID := Vector2i(32, 18)  # one screen at 40 px
const LARGE_GRID := Vector2i(64, 36)  # 2x2 screens
const ARMY_MAX_PER_SIDE := 200        # v0.002 supported formation target; never truncates actual Units
const SMALL_MAX_PER_SIDE := 20
const TILE := 40.0
const MAP_MARGIN := 60.0
const MAX_ZOOM := 2.5
const SLOWMO_FACTOR := 0.22
const SLOWMO_TIME := 1.4              # real seconds
const SLOWMO_COOLDOWN := 2.5
const DRAG_THRESHOLD := 12.0
const FEED_MAX := 4
const FEED_LIFE := 10.0
const RESULT_DELAY := 1.2
## World-map terrain name -> sim terrain (movement multiplier key in Formulas.TERRAIN_MOVE) and map look.
const SIM_TERRAIN := {"grassland": "plains", "silverwood": "forest", "badlands": "plains", "mountains": "hills"}
## Share of the middle ground that is rough / blocked, per terrain (battle map dressing via the sim's "tiles" option).
const TERRAIN_DRESS := {"forest": [0.10, 0.05], "silverwood": [0.08, 0.05], "hills": [0.14, 0.03],
	"mountains": [0.14, 0.05], "badlands": [0.12, 0.02], "marsh": [0.18, 0.02], "grassland": [0.03, 0.0], "plains": [0.03, 0.0]}

var sim: BattleSim
var speed := 1.0
var paused := false
var views: Array = []                  # UnitView per fighter idx
var selected := -1
var side_names := ["Company", "Enemy"]
var terrain := "plains"
var finished := false
var result_shown := false
var _acc := 0.0
var _slowmo := 0.0
var _slowmo_cd := 0.0
var _over_timer := 0.0
var _skipping := false
var _settings_overlay: Node = null
var settings_open := false
var _paused_before_settings := false
var _log_overlay: Control
var _paused_before_log := false
var _journal_transferred := false
var _journal_stats_left := 0.0

# camera
var camera: Camera2D
var cam_pos := Vector2.ZERO
var cam_zoom := 1.0
var _nudge_target := Vector2.ZERO
var _nudge_amount := 0.0
var _nudge := 0.0
var touch_input: TouchInput
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragging := false

# nodes
var shadow_layer: Node2D
var map_view: Node2D
var units_layer: Node2D
var gore_layer: Node2D
var gore_pieces: Array = []          # {node, fighter, part} severed parts on the ground
var blood: Node2D                    # v0.014 GoreLayer: sprays, pools, trails (under the severed pieces and the units)
var fx: Node2D
var readability: Node2D
var readability_legend: Control
var readability_enabled := true # Developer/test switch, set before building this battle.
var arrows_layer: ArrowLayer   # bows
var ui: Control
var _playback_bar: HBoxContainer
var speed_buttons: Array = []
var status_label: Label
var strength_bar: Control   # both sides' fighters still standing, as one tug-of-war bar
var _strength := [0, 0]
var _strength0 := [0, 0]
var feed_box: VBoxContainer
var inspector: PanelContainer
var result_panel: Control
var _dirty_actors: Dictionary = {}  # coalesced presentation only; never a sim cache
var visual_raster_count := 0        # unsaved diagnostics: actors offered a frame

func _ready() -> void:
	var pb: Dictionary = Game.pending_battle
	if pb.is_empty():
		pb = _demo_battle()
	var side0: Array = Game.deployed_units() + pb.get("allies", [])
	for dragon in pb.get("dragon_units", []):
		if DragonCombat.is_dragon_unit(Game, dragon) and not side0.has(dragon): side0.append(dragon)
	if pb.has("round_side0"): side0 = (pb["round_side0"] as Array).duplicate()   # this round's unit (battle_rounds.gd)
	var side1: Array = pb.get("enemy", [])
	var bseed: int = int(pb.get("seed", 1))
	terrain = str(pb.get("terrain", "plains"))
	if side1.size() > 0 and side1[0].faction != "":
		side_names[1] = str(DB.factions.get(side1[0].faction, {}).get("name", "Enemy"))
	sim = BattleSim.new()
	sim.setup(side0, side1, bseed, battle_opts(pb, side0.size(), side1.size()))
	Paperdoll.begin_background()
	speed = float(Game.setting("battle_speed")) if Game.setting("battle_speed") != null else 1.0
	if not speed in SPEEDS or speed <= 0.0:
		speed = 1.0
	_build_world(bseed)
	_build_ui()
	touch_input = TouchInput.attach(self, tap_screen, _on_pan_screen, zoom_at, inspect_screen, 20.0)
	_fit_camera()
	_update_status()
	Game.setting_changed.connect(_on_setting_changed)
	var kind := str(pb.get("assault", {}).get("kind", ""))
	var town_name := str(Game.world.get("towns", {}).get(str(pb.get("assault", {}).get("town_id", "")), {}).get("name", ""))
	var head := ("The Siege of %s" % town_name) if kind == "siege" else (("The Raid on %s" % town_name) if kind == "raid" else "Battle is joined")
	if pb.has("rounds"): head = "Round %d" % int(pb["rounds"].get("round", 1))
	_banner(head, "%s %d  against  %s %d" % [side_names[0], int(sim.side_total[0]), side_names[1], int(sim.side_total[1])], 3.2)
	Sound.sfx("event_fanfare", 0.5, 0.0, 0)

func _exit_tree() -> void:
	if readability != null: readability.end_battle()
	if Game.setting_changed.is_connected(_on_setting_changed):
		Game.setting_changed.disconnect(_on_setting_changed)
	# Finish the bounded native image tasks before their scene/definitions leave.
	if not _handing_over: Paperdoll.end_background()   # the next round's field keeps the shared raster workers
	if not _handing_over and MobilePerf.active(): Paperdoll.trim_cache(MobilePerf.SPRITE_CACHE_IDLE_BYTES)   # v0.072: free battle frames on phones
	if sim != null and sim.combat_journal != null and not _journal_transferred and not is_same(Game.last_result.get("combat_journal"), sim.combat_journal):
		sim.combat_journal.dispose()
		Perf.record_combat_history()

## sim.setup options from a pending battle: grid size from unit counts (or "map": "small"/"large"), terrain,
## chokepoint ("choke": "corridor1"|"corridor2", or explicit "tiles" rows), "stream" arrival, and light
## terrain dressing (rough/blocked tiles in the middle ground; deploy columns stay open).
func battle_opts(pb: Dictionary, n0: int, n1: int) -> Dictionary:
	var per_side := maxi(n0, n1)
	var map_kind: String = str(pb.get("map", ""))
	var grid := SMALL_GRID
	if map_kind == "large" or per_side > SMALL_MAX_PER_SIDE:
		grid = LARGE_GRID
	grid = BattleSim.formation_grid(n0, n1, grid)
	var t := str(pb.get("terrain", "plains"))
	var opts := {"w": grid.x, "h": grid.y, "terrain": SIM_TERRAIN.get(t, t),
		"history_events": 8192, "history_log": 512} # Presentation tails; the complete journal owns history.
	for k in ["stream", "stream_gap", "max_ticks", "corridor_len", "hold0", "hold1"]:
		if pb.has(k):
			opts[k] = pb[k]
	if pb.has("tiles"):
		opts["tiles"] = BattleSim.padded_tiles(pb["tiles"], grid) if per_side > 64 else pb["tiles"]
	elif str(pb.get("choke", "")) != "":
		opts["map"] = str(pb["choke"])
	elif map_kind in ["corridor1", "corridor2"]:
		opts["map"] = map_kind
	else:
		opts["tiles"] = _dress_tiles(grid, t, int(pb.get("seed", 1)))
	return opts

func _dress_tiles(grid: Vector2i, t: String, s: int) -> Array:
	var d: Array = TERRAIN_DRESS.get(t, [0.05, 0.01])
	var rng := RandomNumberGenerator.new()
	rng.seed = s * 7919 + 13
	var cells := []
	for y in grid.y:
		var row := []
		row.resize(grid.x)
		row.fill(".")
		cells.append(row)
	# clumps: a seed tile plus a few neighbours, kept out of the deploy columns
	var keep := 9
	var area := (grid.x - keep * 2) * grid.y
	for kind in 2:
		var clumps := int(area * float(d[kind]) / 4.0)
		for i in clumps:
			var c := Vector2i(rng.randi_range(keep, grid.x - keep - 1), rng.randi_range(1, grid.y - 2))
			for j in rng.randi_range(2, 6):
				if c.x >= keep and c.x < grid.x - keep and c.y >= 0 and c.y < grid.y:
					if kind == 0 or cells[c.y][c.x] == ".":
						cells[c.y][c.x] = "," if kind == 0 else "#"
				c += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
	var rows := []
	for row in cells:
		rows.append("".join(row))
	return rows

func _demo_battle() -> Dictionary:
	if Game.company.is_empty():
		Game.new_game(1234)
	var rng := RandomNumberGenerator.new(); rng.seed = 99
	return {"enemy": Factory.make_warband(rng, "orc_horde", 10), "allies": [], "seed": 5, "terrain": "grassland"}

# ------------------------------------------------------------------ world
func _build_world(map_seed: int) -> void:
	map_view = MapView.new()
	map_view.margin = MAP_MARGIN * 2.0
	map_view.patterns_enabled = readability_enabled
	map_view.settlement = str(Game.pending_battle.get("assault", {}).get("kind", ""))
	map_view.configure(sim, TILE, terrain, map_seed)
	add_child(map_view)
	blood = GoreLayer.new()   # v0.014: sprays, pools, trails from the real wounds and bleeding
	blood.setup(TILE, Game.gore_full(), map_seed)
	add_child(blood)
	gore_layer = Node2D.new()
	add_child(gore_layer)
	shadow_layer = ShadowLayer.new()
	shadow_layer.host = self
	add_child(shadow_layer)
	units_layer = Node2D.new()
	units_layer.y_sort_enabled = true
	add_child(units_layer)
	for f in sim.fighters:
		var v := UnitView.new()
		v.setup(f, TILE)
		v.doll.set_background_rendering(true)
		units_layer.add_child(v)
		views.append(v)
	arrows_layer = ArrowLayer.new()   # bows: arrows in flight
	arrows_layer.z_index = 5
	arrows_layer.setup(sim, TILE)
	add_child(arrows_layer)
	readability = ReadabilityFx.new()
	readability.z_index = 8
	readability.setup(sim, TILE, readability_enabled, Game.pending_battle.get("rounds", {}).get("tactics", []))
	add_child(readability)
	fx = FxLayer.new()
	fx.z_index = 10
	add_child(fx)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()


func map_size() -> Vector2:
	return Vector2(sim.grid_w * TILE, sim.grid_h * TILE)

# ------------------------------------------------------------------ UI
func _build_ui() -> void:
	# Soft vignette: darker edges pull the eye to the fight and give the field depth.
	var vig_layer := CanvasLayer.new(); vig_layer.layer = 4; add_child(vig_layer)
	var vig := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.0)); grad.set_color(1, Color(0.04, 0.02, 0.0, 0.55))
	grad.add_point(0.55, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new(); tex.gradient = grad; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(1.05, 1.05); tex.width = 256; tex.height = 256
	vig.texture = tex; vig.stretch_mode = TextureRect.STRETCH_SCALE; vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT); vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig_layer.add_child(vig)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	th.default_font = UiTheme.get_theme().default_font
	th.default_font_size = UiTheme.base_font_size()
	ui.theme = th
	layer.add_child(ui)
	# top bar: playback controls + status
	var bar := HBoxContainer.new()
	_playback_bar = bar
	bar.position = Vector2(10, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", 6)
	if UiTheme.is_mobile():
		# A wide playback row scrolls sideways instead of leaving the screen.
		var bar_scroll := ScrollContainer.new()
		bar_scroll.name = "PlaybackScroll"
		bar_scroll.position = Vector2(10, 8)
		bar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		bar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		bar_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.position = Vector2.ZERO
		ui.add_child(bar_scroll)
		bar_scroll.add_child(bar)
	else:
		ui.add_child(bar)
	var labels := ["||", "1x", "2x", "4x"]
	for i in labels.size():
		var b := _big_button(labels[i], Vector2(68, 56))
		b.toggle_mode = true
		var s: float = SPEEDS[i]
		b.pressed.connect(func(): set_speed(s))
		bar.add_child(b)
		speed_buttons.append(b)
	var sk := _big_button("Skip >>|", Vector2(120, 56))
	sk.pressed.connect(skip_to_end)
	bar.add_child(sk)
	# settings (gear) as an overlay; playback pauses while it is open
	var gear: Button = UiKit.settings_button(ui, "", true)
	gear.custom_minimum_size = Vector2(maxf(120.0, UiKit.touch_min(56)), UiKit.touch_min(56))
	gear.pressed.connect(_on_settings_opened)   # connected after UiKit's, so the overlay already exists
	bar.add_child(gear)
	var history := _big_button("Combat log", Vector2(116, 56))
	history.name = "BattleCombatLog"
	history.pressed.connect(func(): open_combat_log(selected))
	bar.add_child(history)
	var sp := PanelContainer.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.55), 8))
	bar.add_child(sp)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.custom_minimum_size = Vector2(0, 40)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 14)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(sh)
	sh.add_child(status_label)
	strength_bar = Control.new()
	strength_bar.custom_minimum_size = Vector2(120, 26)
	strength_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strength_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strength_bar.draw.connect(_draw_strength)
	sh.add_child(strength_bar)
	# decisive-moment feed
	feed_box = VBoxContainer.new()
	feed_box.position = Vector2(10, 74)
	feed_box.custom_minimum_size = Vector2(500, 0)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_box.add_theme_constant_override("separation", 4)
	ui.add_child(feed_box)
	# inspector
	inspector = Inspector.new()
	inspector.anchor_left = 1.0; inspector.anchor_right = 1.0
	inspector.anchor_top = 0.0; inspector.anchor_bottom = 1.0
	inspector.offset_left = -Inspector.WIDTH; inspector.offset_right = 0
	inspector.offset_top = 0; inspector.offset_bottom = 0
	inspector.visible = false
	inspector.closed.connect(func(): select(-1))
	inspector.history_requested.connect(func(idx: int): open_combat_log(idx))
	ui.add_child(inspector)
	readability_legend = ReadabilityLegend.new()
	ui.add_child(readability_legend)
	get_viewport().size_changed.connect(_layout_diagnostics)
	_layout_diagnostics()
	_refresh_speed_buttons()

func _layout_diagnostics() -> void:
	if ui == null: return
	var safe := UiKit.safe_area_margins(get_viewport())
	var lane: float = UiKit.diagnostics_lane(get_viewport_rect().size.x)
	ui.offset_left = safe["left"]
	ui.offset_top = safe["top"]
	ui.offset_right = -(lane + safe["right"])
	ui.offset_bottom = -safe["bottom"]
	if _playback_bar != null:
		var span := maxf(0.0, get_viewport_rect().size.x - lane - float(safe["left"] + safe["right"]) - 20.0)
		var sc := _playback_bar.get_parent()
		if UiTheme.is_mobile() and sc is ScrollContainer:
			var bar_h := _playback_bar.get_combined_minimum_size().y
			(sc as ScrollContainer).size = Vector2(span, bar_h)
			_playback_bar.size.x = maxf(span, _playback_bar.get_combined_minimum_size().x)
			if feed_box != null:
				feed_box.position.y = (sc as Control).position.y + bar_h + 8.0
		else:
			_playback_bar.size.x = span

func _big_button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if UiTheme.is_mobile():   # v0.072: phone tap targets; desktop keeps the sizes it asked for
		var min_h := float(UiKit.MOBILE_TAP)
		b.custom_minimum_size = Vector2(maxf(min_size.x, min_h), maxf(min_size.y, min_h))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _box(Color(0.12, 0.1, 0.09, 0.85), 6))
	b.add_theme_stylebox_override("hover", _box(Color(0.2, 0.17, 0.14, 0.9), 6))
	b.add_theme_stylebox_override("pressed", _box(Color(0.85, 0.6, 0.2, 0.95), 6))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(0.92, 0.68, 0.25, 0.95), 6))
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.06, 0.02))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.1, 0.06, 0.02))
	return b

func _box(c: Color, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(margin)
	return sb

func _on_settings_opened() -> void:
	if settings_open: return
	var last := ui.get_child(ui.get_child_count() - 1)
	if last == inspector or last == feed_box:
		return
	_settings_overlay = last
	settings_open = true
	_paused_before_settings = paused
	paused = true
	_refresh_speed_buttons()
	_pressing = false
	_dragging = false
	if touch_input != null: touch_input.reset()

func _toggle_settings() -> void:
	if is_instance_valid(_log_overlay): return
	_check_settings_closed()
	if settings_open:
		_settings_overlay.queue_free()
	else:
		UiKit.open_settings(ui, "", true)
		_on_settings_opened()

## A detached page reader; the live battle is held until it closes.
func open_combat_log(participant: int = -1) -> void:
	if sim == null or settings_open or is_instance_valid(_log_overlay): return
	sim.flush_combat_journal()
	_paused_before_log = paused
	paused = true
	Perf.set_stage("Battle · paused")
	_refresh_speed_buttons()
	_pressing = false; _dragging = false
	if touch_input != null: touch_input.reset()
	_log_overlay = Control.new()
	_log_overlay.name = "BattleLogOverlay"
	_log_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_log_overlay.theme = UiTheme.get_theme()
	ui.add_child(_log_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.03, 0.97)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_log_overlay.add_child(shade)
	var content := UiKit.vbox(10)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 18; content.offset_right = -18
	content.offset_top = 16; content.offset_bottom = -16
	_log_overlay.add_child(content)
	var header := UiKit.hbox(12)
	content.add_child(header)
	var title := UiKit.label("Combat log · battle paused", "Title", true)
	title.add_theme_font_size_override("font_size", 28)
	header.add_child(title)
	var back := UiKit.button("Back to battle", close_combat_log, "", 170)
	back.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 18)
	back.name = "BattleLogClose"
	header.add_child(back)
	var browser := LogBrowser.new()
	browser.name = "BattleLogBrowser"
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(browser)
	browser.begin(sim.combat_journal, side_names)
	browser.set_participant(participant)
	Perf.record_combat_history(sim.combat_journal.stats() if sim.combat_journal != null else {})

func close_combat_log() -> void:
	if not is_instance_valid(_log_overlay): return
	ui.remove_child(_log_overlay)
	_log_overlay.queue_free()
	_log_overlay = null
	paused = _paused_before_log
	_refresh_speed_buttons()
	_pressing = false; _dragging = false
	if touch_input != null: touch_input.reset()

func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "battle_event_slowmo" and not bool(value):
		_cancel_event_slowmo()

func _cancel_event_slowmo() -> void:
	_slowmo = 0.0
	_slowmo_cd = 0.0
	_nudge_amount = 0.0
	_nudge = 0.0
	_nudge_target = cam_pos
	if camera != null: _update_camera(0.0)
	if sim != null and status_label != null: _update_status()

func _check_settings_closed() -> void:
	if settings_open and not is_instance_valid(_settings_overlay):
		settings_open = false
		paused = _paused_before_settings
		_refresh_speed_buttons()

func set_speed(s: float) -> void:
	if s <= 0.0:
		paused = not paused
	else:
		speed = s
		paused = false
	_refresh_speed_buttons()

func _refresh_speed_buttons() -> void:
	for i in speed_buttons.size():
		var b: Button = speed_buttons[i]
		b.set_pressed_no_signal((i == 0 and paused) or (not paused and SPEEDS[i] == speed))

func _update_status() -> void:
	var n := [0, 0]
	for f in sim.fighters:
		if f.active():
			n[f.side] += 1
	var slow := "  SLOW" if _slowmo > 0.0 else ""
	status_label.text = "%s %d   vs   %s %d%s" % [side_names[0], n[0], side_names[1], n[1], slow]
	for i in 2: _strength0[i] = maxi(_strength0[i], n[i])
	if n != _strength:
		_strength = n.duplicate()
		if strength_bar != null: strength_bar.queue_redraw()

func _draw_strength() -> void:
	var r := Rect2(Vector2.ZERO, strength_bar.size)
	strength_bar.draw_rect(r, Color(0, 0, 0, 0.6))
	var total := float(maxi(1, _strength[0] + _strength[1]))
	var w0 := r.size.x * float(_strength[0]) / total
	strength_bar.draw_rect(Rect2(r.position, Vector2(w0, r.size.y)), Color("c58b2a"))
	strength_bar.draw_rect(Rect2(r.position + Vector2(w0, 0), Vector2(r.size.x - w0, r.size.y)), Color("5f7ea6"))
	strength_bar.draw_line(Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y), Color(1, 1, 1, 0.5), 2.0)
	strength_bar.draw_rect(r, Color("f2dfb0"), false, 2.0)

# ------------------------------------------------------------------ playback
func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_process_battle(delta)
	Perf.record_us("Battle frame", Time.get_ticks_usec() - started, true)
	Perf.set_stage("Battle · paused" if paused else "Battle simulation")

func _process_battle(delta: float) -> void:
	if sim == null: return
	_journal_stats_left -= delta
	if _journal_stats_left <= 0.0:
		_journal_stats_left = 0.5
		Perf.record_combat_history(sim.combat_journal.stats() if sim.combat_journal != null else {})
	var part_started: int = Time.get_ticks_usec()
	Paperdoll.pump_background()
	Perf.record_us("Battle sprite completion", Time.get_ticks_usec() - part_started)
	part_started = Time.get_ticks_usec()
	_check_settings_closed()
	if not settings_open and not is_instance_valid(_log_overlay):
		_camera_keys(delta)
	_slowmo = maxf(0.0, _slowmo - delta)
	_slowmo_cd = maxf(0.0, _slowmo_cd - delta)
	Perf.record_us("Battle controls", Time.get_ticks_usec() - part_started)
	if _skipping and not paused and not sim.is_over():
		var until := Time.get_ticks_usec() + 4000
		var ticks := 0
		while not sim.is_over() and ticks < 16 and Time.get_ticks_usec() < until:
			_do_tick(); ticks += 1
		if sim.is_over(): _finish_skip()
	elif not sim.is_over() and not paused:
		var until := Time.get_ticks_usec() + 4000
		var rate := TICKS_PER_SEC * speed * (SLOWMO_FACTOR if _slowmo > 0.0 else 1.0)
		_acc += delta * rate
		var guard := 0
		while _acc >= 1.0 and guard < 16 and not sim.is_over() and \
				(maxi(int(sim.side_total[0]), int(sim.side_total[1])) <= 64 or Time.get_ticks_usec() < until):
			_acc -= 1.0
			_do_tick()
			guard += 1
		if guard >= 16:
			_acc = 0.0
	var frac := clampf(_acc, 0.0, 1.0) if not sim.is_over() else 1.0
	part_started = Time.get_ticks_usec()
	_update_camera(delta)
	var view_rect: Rect2 = _raster_view_rect()
	Perf.record_us("Battle camera", Time.get_ticks_usec() - part_started)
	part_started = Time.get_ticks_usec()
	visual_raster_count = 0
	for v in views:
		if v.update_visual(frac, delta, view_rect): visual_raster_count += 1
	Perf.record_us("Battle actor visuals", Time.get_ticks_usec() - part_started)
	shadow_layer.queue_redraw()
	part_started = Time.get_ticks_usec()
	arrows_layer.frac = frac
	_update_feed(delta)
	if sim.is_over() and not result_shown:
		_over_timer += delta
		if _over_timer >= RESULT_DELAY:
			if _after_step < AFTER_STEPS: _aftermath(delta)
			else: show_result()
	Perf.record_us("Battle frame UI", Time.get_ticks_usec() - part_started)

func _raster_view_rect() -> Rect2:
	var size_world: Vector2 = get_viewport_rect().size / camera.zoom
	return Rect2(camera.position - size_world * 0.5, size_world).grow(TILE)

## Advance one sim tick and present its events.
func _do_tick() -> void:
	var started := Time.get_ticks_usec()
	sim.step()
	Perf.record_us("Battle calculations", Time.get_ticks_usec() - started)
	if readability != null and not _skipping: readability.observe(sim)
	started = Time.get_ticks_usec()
	var part_started: int = started
	var touched := {}
	for e in sim.new_events:
		_present_event(e, touched)
	Perf.record_us("Battle events and effects", Time.get_ticks_usec() - part_started)
	part_started = Time.get_ticks_usec()
	_invalidate_actor_visuals()
	Perf.record_us("Battle sprite invalidation", Time.get_ticks_usec() - part_started)
	part_started = Time.get_ticks_usec()
	blood.tick(sim, views)
	Perf.record_us("Battle blood tick", Time.get_ticks_usec() - part_started)
	part_started = Time.get_ticks_usec()
	if selected >= 0:
		inspector.refresh(touched.has(selected))
	_update_status()
	Perf.record_us("Battle tick UI", Time.get_ticks_usec() - part_started)
	Perf.record_us("Battle presentation", Time.get_ticks_usec() - started)

func _invalidate_actor_visuals() -> void:
	for idx in _dirty_actors:
		var v = _view(int(idx))
		if v != null: v.doll.invalidate()
	_dirty_actors.clear()

## Test/debug: advance n ticks synchronously with full presentation.
func step_ticks(n: int) -> void:
	for i in n:
		if sim.is_over():
			return
		_do_tick()
		for v in views:
			v.update_visual(1.0, 1.0 / TICKS_PER_SEC)

func skip_to_end() -> void:
	if sim.is_over():
		return
	_skipping = true
	if readability != null: readability.end_battle()
	if maxi(int(sim.side_total[0]), int(sim.side_total[1])) > 64:
		return   # The same sim advances over bounded frames; large skips do not block input.
	var guard := 0
	while not sim.is_over() and guard < 50000:
		_do_tick()
		guard += 1
	_finish_skip()

func _finish_skip() -> void:
	_skipping = false
	_slowmo = 0.0
	fx.clear_all()
	blood.clear_all()
	var view_rect: Rect2 = _raster_view_rect()
	for v in views:
		v.settle(view_rect)
	_over_timer = RESULT_DELAY
	_update_status()

func _view(i: int):
	return views[i] if i >= 0 and i < views.size() else null

func _present_event(e: Dictionary, touched: Dictionary) -> void:
	var type: String = e.get("type", "")
	var a: int = int(e.get("actor", -1))
	var t: int = int(e.get("target", -1))
	var def_i := t if t >= 0 else a
	touched[a] = true
	touched[t] = true
	if bool(e.get("decisive", false)):
		_add_feed(e)
		if not _skipping and _wants_slowmo(e):
			_trigger_slowmo(def_i)
	if type == "sever":
		_drop_piece(def_i, str(e.get("part", "")))
	if type in ["hit", "wound", "artery", "sever", "drop", "freed", "lodged", "death", "breath_hit"]:
		if def_i >= 0: _dirty_actors[def_i] = true
		if a >= 0: _dirty_actors[a] = true
	elif type == "snap" and a >= 0:
		_dirty_actors[a] = true
	if _skipping:
		return
	var av = _view(a)
	var dv = _view(def_i)
	if dv != null and (type == "hit" or type == "sever"):
		_spray(e, av, dv)
	_sound(type, e, av, dv)
	# Routine floating text (dodge/block/hit location) only around the inspected unit, so a 50-a-side melee
	# stays readable; the log carries the detail. Decisive text (SEVERED, slain) always shows.
	var near_sel := selected >= 0 and (a == selected or t == selected)
	match type:
		"attack", "shoot":   # bows: the loose shows as the strike pose (the draw is the prepare pose)
			if av: av.flash("strike")
		"dodge":
			if dv:
				dv.flash("dodge")
				if near_sel: fx.add(dv.body_center() + Vector2(0, -26), "dodge", Color(0.85, 0.95, 1.0))
		"block", "parry":
			if dv:
				dv.flash("block")
				if near_sel: fx.add(dv.body_center() + Vector2(0, -26), type, Color(0.75, 0.85, 1.0))
		"hit", "wound", "artery":
			if dv:
				dv.flash("hit")
				var part := _part_name(dv.fighter, str(e.get("part", "")))
				if near_sel or type == "artery":
					fx.add(dv.body_center() + Vector2(0, -26), part if part != "" else "hit", Color(1.0, 0.7, 0.3) if type == "hit" else Color(1.0, 0.35, 0.3))
		"sever":
			if dv: dv.flash("hit"); fx.add(dv.body_center() + Vector2(0, -30), "SEVERED", Color(1.0, 0.25, 0.2), 18)
		"death":
			if dv: fx.add(dv.body_center() + Vector2(0, -30), "slain", Color(1.0, 0.3, 0.25), 17)
		"snap":   # v0.014: the attacker's weapon broke on the blow
			if av:
				fx.add(av.body_center() + Vector2(0, -30), "SNAP!", Color(0.95, 0.85, 0.6), 17)
		"unconscious":
			if av: fx.add(av.body_center() + Vector2(0, -26), "out cold", Color(0.8, 0.7, 1.0))
		"learn":
			if av and av.fighter.side == 0: fx.add(av.body_center() + Vector2(0, -40), "+skill", Color(0.5, 1.0, 0.5))
		"breath":
			if av: av.flash("strike") # Cone and element cue share the capped readability layer.
		"breath_hit":
			if dv: dv.flash("hit")

## v0.014: blood droplets sized by the strike's REAL damage (the sum of its tissue layers' damage, the artery's rate);
## a sever throws a big burst. Nothing for a blow that drew no blood (no layers).
func _spray(e: Dictionary, av, dv) -> void:
	var n := 0
	if e["type"] == "sever":
		n = 30
	elif e.has("entry"):
		var D: Dictionary = e["entry"].get("d", {})
		var s := 0.0
		for l in D.get("layers", []):
			if String(l[1]) != "bone" or float(l[3]) > 0.3:   # a bruised or broken bone under intact skin does not bleed out
				s += float(l[3])
		n = clampi(int(s * 14.0 + float(D.get("art", 0.0)) * 150.0), 0, 40)
		if D.get("layers", []).is_empty():
			n = 0
	if n <= 0:
		return
	var dir := Vector2(1, 0)
	if av != null:
		dir = (dv.position - av.position)
	blood.spray(dv.body_center(), dir, n, dv.position.y)

## A severed part lies on the ground at the unit's tile: a static decal from Paperdoll.make_severed_piece.
## (Flying-off animation would sit behind Game.setting("anim_limb_flyoff"); not built.)
func _drop_piece(idx: int, pid: String) -> void:
	var v = _view(idx)
	if v == null or pid == "":
		return
	var piece: Node2D = DragonView.source_cut_piece(v.fighter.unit, pid, v.fighter.facing) if DragonCombat.is_dragon_unit(Game, v.fighter.unit) else Paperdoll.make_severed_piece(v.fighter.unit, pid)
	if piece == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(sim.tick) + pid + str(idx))
	var dir := -1.0 if v.fighter.facing > 0 else 1.0   # lands behind the unit, away from the blow
	piece.position = v.cell_pos(v.fighter.cell) + Vector2(dir * rng.randf_range(8, 18), rng.randf_range(-8, 6))
	piece.rotation = rng.randf_range(-0.6, 0.6)
	if not Game.gore_full():   # v0.014 Gore: Reduced: the piece is smaller and dimmed
		piece.scale *= 0.6
		piece.modulate = Color(0.55, 0.5, 0.5, 0.8)
	gore_layer.add_child(piece)
	gore_pieces.append({"node": piece, "fighter": idx, "part": pid})

func _part_name(f, pid: String) -> String:
	if pid == "" or f == null:
		return ""
	var d: Dictionary = f.unit.body.part_def(pid)
	return str(d.get("name", pid))

func _wants_slowmo(e: Dictionary) -> bool:
	if not bool(Game.setting("battle_event_slowmo")): return false
	var type: String = e.get("type", "")
	var txt := BattleSim.event_text(e).to_lower()
	if type == "sever" or type == "artery":
		return true
	if type == "death" and (str(e.get("part", "")) == "head" or "head" in txt):
		return true
	return false

func _trigger_slowmo(idx: int) -> void:
	if not bool(Game.setting("battle_event_slowmo")): return
	var v = _view(idx)
	if v == null or _slowmo_cd > 0.0 or paused:
		return
	_slowmo = SLOWMO_TIME
	_slowmo_cd = SLOWMO_COOLDOWN + SLOWMO_TIME
	v.highlight = SLOWMO_TIME
	# zoom-nudge only when the blow is on screen, so we never yank the camera across the map
	var view_rect := Rect2(cam_pos - _view_size() * 0.5, _view_size())
	if view_rect.has_point(v.body_center()):
		_nudge_target = v.body_center()
		_nudge_amount = 1.0

# ------------------------------------------------------------------ feed
func _add_feed(e: Dictionary) -> void:
	var b := Button.new()
	b.text = BattleSim.event_text(e)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(440, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	if UiTheme.is_mobile():
		b.custom_minimum_size.y = float(UiKit.MOBILE_TAP)
		b.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE)
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
	if b.text.length() > 150: b.text = b.text.substr(0, 147) + "..."   # the Combat log keeps the full line
	var a: int = int(e.get("actor", -1))
	var col := Color(1.0, 0.92, 0.6)
	if a >= 0 and a < sim.fighters.size():
		col = Color(0.65, 0.85, 1.0) if sim.fighters[a].side == 0 else Color(1.0, 0.6, 0.55)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", col)
	b.add_theme_stylebox_override("normal", _box(Color(0, 0, 0, 0.6), 8))
	b.add_theme_stylebox_override("hover", _box(Color(0.1, 0.1, 0.1, 0.7), 8))
	b.add_theme_stylebox_override("pressed", _box(Color(0.2, 0.2, 0.2, 0.7), 8))
	b.set_meta("age", 0.0)
	var t: int = int(e.get("target", -1))
	var focus_i := t if t >= 0 else a
	b.pressed.connect(func():
		if focus_i >= 0:
			select(focus_i)
			center_on(focus_i))
	feed_box.add_child(b)
	while feed_box.get_child_count() > FEED_MAX:
		var old := feed_box.get_child(0)
		feed_box.remove_child(old)
		old.queue_free()

func _update_feed(delta: float) -> void:
	for c in feed_box.get_children():
		var age: float = c.get_meta("age", 0.0) + delta
		c.set_meta("age", age)
		c.modulate.a = clampf((FEED_LIFE - age) / 2.0, 0.0, 1.0)
		if age > FEED_LIFE:
			c.queue_free()

# ------------------------------------------------------------------ selection / inspector
func select(idx: int) -> void:
	if selected >= 0 and selected < views.size():
		views[selected].selected = false
	selected = idx
	if idx < 0:
		inspector.visible = false
		inspector.fighter = null
		return
	views[idx].selected = true
	inspector.show_fighter(sim.fighters[idx], sim)

## Public for tests/debug: a tap at a screen position.
func tap_screen(screen_pos: Vector2) -> void:
	var world := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	tap_world(world)

## Long-press (~0.5s) or right-click inspects the fighter at screen_pos.
func inspect_screen(screen_pos: Vector2) -> void:
	var world := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	var best := -1
	var bd := maxf(44.0, 52.0 / cam_zoom)
	for v in views:
		if v.gone or not v.visible:
			continue
		var d: float = v.body_center().distance_to(world)
		if v.fighter.state == "dead":
			d += 8.0
		if d < bd:
			bd = d
			best = v.fighter.idx
	select(best)
	if best >= 0:
		_keep_visible(best)

func _on_pan_screen(screen_delta: Vector2) -> void:
	cam_pos -= screen_delta / cam_zoom
	auto_cam = false

func tap_world(p: Vector2) -> void:
	var best := -1
	var bd := 34.0
	for v in views:
		if v.gone or not v.visible:
			continue
		var d: float = v.body_center().distance_to(p)
		if v.fighter.state == "dead":
			d += 8.0   # prefer the living when bodies overlap
		if d < bd:
			bd = d
			best = v.fighter.idx
	select(best)
	if best >= 0:
		_keep_visible(best)

func center_on(idx: int) -> void:
	var v = _view(idx)
	if v:
		cam_pos = v.body_center()
		var covered: float = UiKit.diagnostics_lane(get_viewport_rect().size.x)
		if inspector.visible: covered += Inspector.WIDTH
		cam_pos.x += covered * 0.5 / cam_zoom

## After a tap opens the inspector, pan just enough that the unit isn't hidden under the panel.
func _keep_visible(idx: int) -> void:
	var v = _view(idx)
	if v == null:
		return
	var sx: float = screen_pos_of(idx).x
	var free_w := get_viewport_rect().size.x - Inspector.WIDTH - UiKit.diagnostics_lane(get_viewport_rect().size.x)
	if sx > free_w - 60.0:
		cam_pos.x += (sx - free_w * 0.5) / cam_zoom

func screen_pos_of(idx: int) -> Vector2:
	return get_viewport().get_canvas_transform() * views[idx].body_center()

# ------------------------------------------------------------------ result
## A large centred title that fades in and out (battle start and end).
func _banner(title: String, sub: String, secs: float) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.position.y = 110
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new(); t.text = title
	t.add_theme_font_size_override("font_size", 46)
	t.add_theme_color_override("font_color", Color(0.98, 0.86, 0.55))
	t.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02))
	t.add_theme_constant_override("outline_size", 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := Label.new(); s.text = sub
	s.add_theme_font_size_override("font_size", 22)
	s.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.02))
	s.add_theme_constant_override("outline_size", 6)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t); box.add_child(s)
	ui.add_child(box)
	box.size.x = get_viewport_rect().size.x
	box.position.x = 0
	box.modulate.a = 0.0
	var tw := box.create_tween() # The title can leave while the battle screen stays alive.
	tw.tween_property(box, "modulate:a", 1.0, 0.5)
	tw.tween_interval(secs)
	tw.tween_property(box, "modulate:a", 0.0, 0.8)
	tw.tween_callback(box.queue_free)

## Aftermath: after the clash is decided, the side holding the field sends in its medics (one per two men down,
## 10 to 50) to bandage the downed, its own first and then the enemy's, whom it takes prisoner; the untended
## keep bleeding and some bleed out. AFTER_STEPS steps, one every AFTER_STEP_SECS of playback.
const AFTER_STEPS := 12
const AFTER_STEP_SECS := 0.35
var _after_step := 0
var _after_clock := 0.0
var _medics := 0
var _medic_units: Array = []
var aftermath := {"tended_own": 0, "tended_enemy": 0, "bled_out": [0, 0], "medics": 0}

func _aftermath(delta: float) -> void:
	if _after_step == 0 and _after_clock == 0.0:
		var down: Array = sim.downed_counts()
		_medics = clampi(int(ceil(float(down[0] + down[1]) / 2.0)), 10, 50) if sim.winner >= 0 else 0
		_medic_units = []
		if sim.winner == 0 and Game.world.has("towns"):
			# Your side: your assigned battle medics, at full pace; with none, the troops bandage each other slowly.
			_medic_units = Mobilization.medics(Game)
			_medics = _medic_units.size() * 2 if not _medic_units.is_empty() else 6
			var sk := 0
			for m in _medic_units: sk += m.skill("surgeon")
			sim.medic_skill = int(round(float(sk) / maxf(1.0, float(_medic_units.size()))))
		else:
			sim.medic_skill = 4
		aftermath["medics"] = _medics
		if _medics > 0: _banner("Aftermath", "%d medics come onto the field" % _medics, 2.0)
	_after_clock += delta * maxf(1.0, speed) * (8.0 if _skipping else 1.0)
	while _after_clock >= AFTER_STEP_SECS and _after_step < AFTER_STEPS:
		_after_clock -= AFTER_STEP_SECS
		_after_step += 1
		var o: Dictionary = sim.aftermath_step(sim.winner, _medics)
		aftermath["tended_own"] += int(o["tended_own"]); aftermath["tended_enemy"] += int(o["tended_enemy"])
		var tended := int(o["tended_own"]) + int(o["tended_enemy"])
		if tended > 0 and not _medic_units.is_empty():   # every man tended teaches the medics a little
			for m in _medic_units:
				m.skill_xp["surgeon"] = float(m.skill_xp.get("surgeon", 0.0)) + 25.0 * float(tended) / float(_medic_units.size())
				while float(m.skill_xp["surgeon"]) >= 500.0 + 100.0 * m.skill("surgeon"):
					m.skill_xp["surgeon"] = float(m.skill_xp["surgeon"]) - (500.0 + 100.0 * m.skill("surgeon"))
					m.skills["surgeon"] = m.skill("surgeon") + 1
		for i in 2: aftermath["bled_out"][i] += int(o["bled_out"][i])
	if status_label != null:
		status_label.text = "Aftermath: %d of ours bandaged · %d enemy wounded taken and tended · %d bled out" % [int(aftermath["tended_own"]), int(aftermath["tended_enemy"]), int(aftermath["bled_out"][0]) + int(aftermath["bled_out"][1])]

var _round_result: Dictionary = {}
var _handing_over := false

## Rounds: the round's own summary first; then the next pair goes in, or the battle summary follows.
func _show_round_result() -> void:
	_round_result = build_result()
	var d: Dictionary = BattleRounds.after_round(Game, _round_result)
	d["aftermath"] = aftermath.duplicate(true)
	var over := bool(Game.pending_battle["rounds"].get("over", false))
	var w := int(d.get("winner", -1))
	_banner("Round %d %s" % [int(d["round"]), "won" if w == 0 else ("lost" if w == 1 else "drawn")], "", 1.2)
	_show_card(RoundSummary.round_panel(d, _after_round_panel.bind(over), over))

func _after_round_panel(over: bool) -> void:
	if is_instance_valid(result_panel): result_panel.queue_free()
	if not over:
		BattleRounds.next_round(Game)
		_handing_over = true
		Game.goto("battle")   # a fresh field for the next pair of units
		return
	var w := int(Game.pending_battle["rounds"].get("winner", -1))
	Sound.sfx("event_fanfare" if w == 0 else "fall", 0.8, 0.0, 0)
	_show_card(RoundSummary.battle_panel(BattleRounds.battle_summary(Game), finish))

## A summary card in the game's own theme (the battle HUD theme has no card or heading styles), centred.
func _show_card(card: Control) -> void:
	var holder := CenterContainer.new()
	holder.theme = UiTheme.get_theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	var sc := ScrollContainer.new()   # a long household list scrolls; the button stays reachable
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(card.get_combined_minimum_size().x + 24, minf(card.get_combined_minimum_size().y, get_viewport_rect().size.y * 0.9))
	sc.add_child(card)
	holder.add_child(sc)
	ui.add_child(holder)
	result_panel = holder

func show_result() -> void:
	if result_shown:
		return
	result_shown = true
	if readability != null: readability.end_battle()
	if readability_legend != null: readability_legend.close()
	if BattleRounds.active(Game):
		_show_round_result()
		return
	var w: int = sim.winner
	_banner("Victory" if w == 0 else ("Defeat" if w == 1 else "The field is held by none"), "", 1.4)
	Sound.sfx("event_fanfare" if w == 0 else "fall", 0.8, 0.0, 0)
	var dead := [0, 0]; var fled := [0, 0]; var down := [0, 0]
	for f in sim.fighters:
		match f.state:
			"dead": dead[f.side] += 1
			"fled": fled[f.side] += 1
			"unconscious", "prone": down[f.side] += 1
	result_panel = PanelContainer.new()
	result_panel.add_theme_stylebox_override("panel", _box(Color(0.08, 0.07, 0.06, 0.94), 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	result_panel.add_child(v)
	var title := Label.new()
	title.text = "VICTORY" if w == 0 else ("DEFEAT" if w == 1 else "STALEMATE")
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if w == 0 else Color(1, 0.35, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var info := Label.new()
	info.text = "%s: %d dead, %d fled, %d down\n%s: %d dead, %d fled, %d down\n%d ticks" % [side_names[0], dead[0], fled[0], down[0], side_names[1], dead[1], fled[1], down[1], sim.tick]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	var cont := _big_button("Continue", Vector2(280, 72))
	cont.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 26)
	cont.pressed.connect(finish)
	v.add_child(cont)
	ui.add_child(result_panel)
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)

func build_result() -> Dictionary:
	var p := []; var en := []; var fallen := []; var all := []; var fled := []
	var player_fled: Array = []; var states: Array = []
	for f in sim.fighters:
		if f.mount_rider_idx >= 0: continue # Mount events/bodies stay in the journal; no phantom people or loot.
		all.append(f.unit)
		states.append(f.state)
		if f.side == 0:
			p.append(f.unit)
			if f.state == "fled": player_fled.append(f.unit)
		else:
			en.append(f.unit)
			if f.state == "dead" or f.state == "fled":
				fallen.append(f.unit)
			if f.state == "fled":
				fled.append(f.unit)
	if sim._bows_on:   # bows: lodged arrows pulled on the field; what lies on the field for whoever holds it
		Archery.pull_lodged(sim)
	var growth: Dictionary = sim.apply_battle_growth()
	sim.flush_combat_journal()
	return {"winner": sim.winner, "player_units": p, "enemy_units": en, "enemy_fallen": fallen, "enemy_fled": fled,
		"player_fled": player_fled, "side_names": side_names.duplicate(), "fighter_states": states,
		"events": sim.result_events(), "fighter_units": all, "ticks": sim.tick, "growth": growth,
		"combat_journal": sim.combat_journal, "kill_pairs": sim.kill_pairs, "dragon_downs": sim.dragon_downs.duplicate(),
		"history_events_omitted": sim.events_dropped,
		"arrow_field": sim.arrow_field.duplicate(true)}

func finish() -> void:
	if finished:
		return
	finished = true
	_journal_transferred = true
	if BattleRounds.active(Game) and not _round_result.is_empty():
		Game.finish_battle(BattleRounds.final_result(Game, _round_result))
		return
	Game.finish_battle(build_result())

# ------------------------------------------------------------------ camera
func _view_size() -> Vector2:
	return get_viewport_rect().size / (cam_zoom * (1.0 + 0.18 * _nudge))

func _min_zoom() -> float:
	var vp := get_viewport_rect().size
	var ms := map_size() + Vector2(MAP_MARGIN, MAP_MARGIN) * 2.0
	return minf(maxf(vp.x / ms.x, vp.y / ms.y), 1.0)

func _fit_camera() -> void:
	cam_pos = map_size() * 0.5
	cam_zoom = _min_zoom() if sim.grid_w <= SMALL_GRID.x else maxf(_min_zoom(), 0.7)
	if auto_cam:
		_follow_clock = 0.0
		_follow(0.0)
		cam_pos = _follow_pos; cam_zoom = _follow_zoom
	_update_camera(0.0)

func _camera_keys(delta: float) -> void:
	var d := Vector2(Input.get_axis("cam_left", "cam_right"), Input.get_axis("cam_up", "cam_down"))
	if d != Vector2.ZERO:
		cam_pos += d * 700.0 * delta / cam_zoom
		auto_cam = false
	elif auto_cam and sim != null and _slowmo <= 0.0:
		_follow(delta)

func _update_camera(delta: float) -> void:
	if _nudge_amount > 0.0 and _slowmo <= 0.0:
		_nudge_amount = 0.0
	_nudge = move_toward(_nudge, _nudge_amount, delta * (4.0 if _nudge_amount > _nudge else 1.5))
	var z := cam_zoom * (1.0 + 0.18 * _nudge)
	var p := cam_pos.lerp(_nudge_target, 0.35 * _nudge)
	cam_pos = _clamp_pos(cam_pos, cam_zoom)
	p = _clamp_pos(p, z)
	camera.zoom = Vector2(z, z)
	_shake = move_toward(_shake, 0.0, delta * 30.0)
	camera.position = p + (Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake / z if _shake > 0.1 else Vector2.ZERO)

func _clamp_pos(p: Vector2, z: float) -> Vector2:
	var view := get_viewport_rect().size / z
	var r := Rect2(-Vector2(MAP_MARGIN, MAP_MARGIN), map_size() + Vector2(MAP_MARGIN, MAP_MARGIN) * 2.0)
	r.size.x += UiKit.diagnostics_lane(get_viewport_rect().size.x) / z
	if inspector != null and inspector.visible:
		# the panel covers the right edge: let the camera pan far enough to show the map's right side beside it
		r.size.x += Inspector.WIDTH / z
	var o := p
	for ax in 2:
		if view[ax] >= r.size[ax]:
			o[ax] = r.position[ax] + r.size[ax] * 0.5
		else:
			o[ax] = clampf(p[ax], r.position[ax] + view[ax] * 0.5, r.end[ax] - view[ax] * 0.5)
	return o

func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	cam_zoom = clampf(cam_zoom * factor, _min_zoom(), MAX_ZOOM)
	# keep the point under the finger fixed
	var vp := get_viewport_rect().size
	cam_pos = before - (screen_pos - vp * 0.5) / cam_zoom
	auto_cam = false

## v0.072: mouse, touch (tap, one-finger pan, pinch) and long-press / right-click inspect go through TouchInput.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		if readability_legend != null and readability_legend.is_open(): readability_legend.close()
		elif is_instance_valid(_log_overlay): close_combat_log()
		else: _toggle_settings()
		get_viewport().set_input_as_handled()
		return
	if settings_open or is_instance_valid(_log_overlay): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		auto_cam = not auto_cam
		_follow_clock = 0.0
		return
	if touch_input != null and touch_input.handle_input(event):
		_pressing = touch_input.pressing
		_dragging = touch_input.dragging
		_press_pos = touch_input.press_pos
		if _dragging or event is InputEventMagnifyGesture or (event is InputEventMouseButton and (event as InputEventMouseButton).button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
			auto_cam = false

## Battle sounds: only what happens on screen is heard, louder when zoomed in; rate-limited per kind.
func _sound(type: String, e: Dictionary, av, dv) -> void:
	if not is_inside_tree() or camera == null: return
	var v = dv if dv != null else av
	if v == null: return
	var view := _raster_view_rect()
	if not view.has_point(v.position): return
	var loud := clampf(0.35 + cam_zoom * 0.4, 0.3, 1.0)
	match type:
		"block", "parry": Sound.sfx(Sound.pick("clash", 4), 0.55 * loud, 0.1, 35)
		"hit", "wound": Sound.sfx(Sound.pick("hit", 3), 0.6 * loud, 0.12, 35)
		"artery", "sever": Sound.sfx(Sound.pick("hit", 3), 0.9 * loud, 0.05, 60)
		"death": Sound.sfx("fall", 0.55 * loud, 0.1, 120)
		"shoot": Sound.sfx("bow", 0.4 * loud, 0.1, 50)
		"breath":
			Sound.sfx("breath_" + str(e.get("element", "fire")), 1.0, 0.04, 400)
			Sound.sfx(Sound.pick("roar", 2), 0.8, 0.05, 1500)
			_shake = maxf(_shake, 14.0)
		"attack":
			if av != null and av.doll is DragonView:
				Sound.sfx(Sound.pick("roar", 2), 0.55 * loud, 0.08, 3500)
				_shake = maxf(_shake, 4.0)

## Follow camera: frames the living, unrouted fighters of both sides until the player pans or zooms (C re-enables).
var auto_cam := true
var _shake := 0.0
var _follow_clock := 0.0
var _follow_pos := Vector2.ZERO
var _follow_zoom := 1.0

func _follow(delta: float) -> void:
	_follow_clock -= delta
	if _follow_clock <= 0.0:
		_follow_clock = 0.25
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var n := 0
		for f in sim.fighters:
			if f.waiting or f.routed or not f.alive(): continue
			var p := Vector2(f.cell) * TILE
			lo = lo.min(p); hi = hi.max(p); n += 1
		if n == 0: return
		var box := Rect2(lo, hi - lo).grow(TILE * 3.0)
		var vp := get_viewport_rect().size
		vp.x -= UiKit.diagnostics_lane(vp.x)
		vp.y -= 140.0
		_follow_pos = box.get_center()
		_follow_zoom = clampf(minf(vp.x / box.size.x, vp.y / box.size.y), _min_zoom(), 1.4)
	var k := 1.0 - exp(-delta * 2.5)
	cam_pos = cam_pos.lerp(_follow_pos, k)
	cam_zoom = lerpf(cam_zoom, _follow_zoom, k)


## Every living fighter's ground shadow in one canvas item (dragons get a larger one).
## v0.072: all shadows go out as ONE triangle-array draw (was one polygon draw per fighter, with a copied
## polygon each); the vertex/colour/index buffers are kept and reused between frames.
class ShadowLayer:
	extends Node2D
	var host
	var _unit_poly := PackedVector2Array()
	var _pts := PackedVector2Array()
	var _cols := PackedColorArray()
	var _idx := PackedInt32Array()
	func _ready() -> void:
		for i in 14:
			var a := TAU * i / 14.0
			_unit_poly.append(Vector2(cos(a) * 15.0, sin(a) * 6.0))
	## Fan indices (centre + rim) for `cap` shadows.
	func _reserve(cap: int) -> void:
		var rim := _unit_poly.size()
		var per := rim + 1
		if _pts.size() >= cap * per: return
		_pts.resize(cap * per); _cols.resize(cap * per)
		_idx.resize(cap * rim * 3)
		for k in cap:
			var base := k * per
			for i in rim:
				var j := (k * rim + i) * 3
				_idx[j] = base; _idx[j + 1] = base + 1 + i; _idx[j + 2] = base + 1 + (i + 1) % rim
	func _draw() -> void:
		var col := Color(0, 0, 0, 0.28)
		var dragon_col := Color(0, 0, 0, 0.22)
		var rect: Rect2 = host._raster_view_rect()
		var rim := _unit_poly.size()
		var per := rim + 1
		var count: int = host.views.size()
		_reserve(count)
		var n := 0
		for v in host.views:
			if not v.visible or v.gone or v.fighter.state in ["dead", "fled"]: continue
			var p: Vector2 = v.position
			if not rect.has_point(p): continue
			var o := p
			var sc := Vector2.ONE
			var c := col
			if v.doll is DragonView:
				var b: Rect2 = v.doll.visual_bounds()
				o = p + Vector2(v.doll.body_center_offset().x * 0.3, 0)
				sc = Vector2(absf(b.size.x) / 110.0, absf(b.size.x) / 140.0)
				c = dragon_col
			var base := n * per
			_pts[base] = o; _cols[base] = c
			for i in rim:
				_pts[base + 1 + i] = o + _unit_poly[i] * sc
				_cols[base + 1 + i] = c
			n += 1
		if n == 0: return
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx.slice(0, n * rim * 3),
			_pts.slice(0, n * per), _cols.slice(0, n * per))
