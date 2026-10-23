extends Node2D
## Campaign map screen ("map"). Tap/click to travel, tap a town to go there (enter when adjacent),
## tap a warband to scout it. Time passes while the party travels (or while waiting).
## Camera: WASD/arrows (cam_*), drag to pan, wheel / pinch to zoom.

const SEC_PER_DAY := 5.0
const WORK_BUDGET_USEC := 4000
const ZOOM_MIN := 0.45
const ZOOM_MAX := 2.6
const DRAG_THRESHOLD := 12.0
const TOWN_ENTER_DIST := 56.0
const TRADE_OVERLAY := preload("res://campaign/trade_overlay.gd")

var terrain: Node2D
var tracks_layer: Node2D   # tracks: noticed tracks + last-seen circle (campaign/map_tracks.gd), static, redraws on change
var overlay: Node2D
var sites: Node2D
var bands_root: Node2D
var party_icon: MapToken   # map tokens
var cam: Camera2D
var icons := {}          # wid -> MapToken (map tokens)
var follow := true
var speed_mult := 1
var pursue_wid := ""
var selected := {}       # {"kind": "warband"|"party"|"town", "id": ...}

var trade_good := "off"
var trade_overlay := TRADE_OVERLAY.new()

# input state
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragging := false

# HUD
var hud: CanvasLayer
var lbl_day: Label
var daylight: CanvasModulate   # one cheap full-map tint for night/dawn/dusk and season
var lbl_gold: Label
var lbl_wages: Label
var lbl_contract: Label
var lbl_log: Label
var lbl_news: Label   # diplomacy ticker
var lbl_toast: Label
var btn_wait: Button
var btn_speed: Button
var btn_trade: Button
var lbl_trade: Label
var info_panel: PanelContainer
var info_title: Label
var info_body: Label
var info_buttons: HFlowContainer
var enc_fight: Button
var enc_panel: PanelContainer
var enc_body: Label
var enc_title: Label
var modal_host: Control   # economy spec 2: themed layer for the rank-tree panel (ui/army_panel.gd)
var _toast_t := 0.0
var _hud_t := 0.0
var hud_root: Control
var top_panel: PanelContainer
var bottom_nav: PanelContainer
var ruler_card: DynastyCard
var _accounts_key := ""
var _accounts_snapshot: Dictionary = {}
var _hud_troops := 0
var _hud_wages := 0
var _hud_unpaid := 0
var _hud_layout_queued := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # camera stays responsive during consistent save capture
	if Game.world.is_empty() or not Game.world.has("towns"):
		Game.new_game()
	daylight = CanvasModulate.new()   # tints the map only; the HUD lives on a CanvasLayer
	add_child(daylight)
	daylight.color = Calendar.tint(Game.day)
	var w: Dictionary = Game.world
	trade_good = String(Game.screen_params.get("trade_good", "off"))
	if not TRADE_OVERLAY.MODES.has(trade_good): trade_good = "off"
	# back from a town: the party stands at the gate
	if Game.location != "":
		var t: Dictionary = w["towns"].get(Game.location, {})
		Game.location = ""
		if not t.is_empty():
			w["party"]["pos"] = CampaignWorld.nearest_passable(w, t["pos"] + Vector2(0, 30))
	w["party"]["arrived"] = ""
	terrain = Node2D.new()
	terrain.set_script(load("res://campaign/map_terrain.gd"))
	add_child(terrain)
	terrain.setup(w)
	Perf.record_terrain_owners(terrain.decor_render_stats())
	tracks_layer = load("res://campaign/map_tracks.gd").new()   # tracks
	add_child(tracks_layer)
	overlay = Node2D.new()
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	sites = load("res://campaign/map_sites.gd").new()   # monsters wave 1: known lairs and bandit camps
	add_child(sites)
	sites.sync(Game)
	bands_root = Node2D.new()
	bands_root.y_sort_enabled = true
	add_child(bands_root)
	# map tokens: the company is one banner token, always drawn on top (art/map_tokens.gd)
	party_icon = MapToken.new()
	party_icon.set_texture("player", MapTokens.texture("player"))
	party_icon.z_index = 1
	bands_root.add_child(party_icon)
	# Saved personal heraldry belongs to this party, never the realm's colours.
	# One small static draw replaces its default banner; no per-frame repaint.
	var house_style: Dictionary = w.get("player_house", {}).get("customization", {})
	if not house_style.is_empty():
		party_icon.set_texture("house|" + str(house_style.hash()), null)
		var standard := HouseBanner.new()
		standard.name = "PlayerHouseStandard"
		standard.show_behind_parent = true   # keep the headcount badge above personal heraldry
		standard.position = Vector2(-28, -55)
		standard.size = Vector2(56, 64)
		standard.set_style(house_style)
		party_icon.add_child(standard)
	cam = Camera2D.new()
	cam.limit_left = -200; cam.limit_top = -200
	cam.limit_right = WorldGen.W * WorldGen.CELL + 200
	cam.limit_bottom = WorldGen.H * WorldGen.CELL + 200
	add_child(cam)
	cam.make_current()
	cam.position = w["party"]["pos"]
	trade_overlay.name = "TradeOverlay"
	trade_overlay.z_index = 2
	add_child(trade_overlay)
	_build_hud()
	_refresh_trade_overlay()
	Game.changed.connect(func(): _accounts_key = "")
	tracks_layer.setup(self)   # tracks: tapping the contract line centres the map on the target / last-seen spot
	_sync_icons()
	_refresh_hud()

# ================================================================== loop
func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_process_map(delta)
	Perf.record_us("Map frame", Time.get_ticks_usec() - started, true)
	Perf.set_stage("Settling campaign jobs" if not Game.world.get("work", []).is_empty() else "Map · travelling" if CampaignWorld.is_travelling(Game) or Game.world.get("party", {}).get("waiting", false) else "Map · paused")

func _process_map(delta: float) -> void:
	var frame_started := Time.get_ticks_usec()
	var w: Dictionary = Game.world
	var party: Dictionary = w["party"]
	# camera keys
	var pan := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if pan != Vector2.ZERO:
		cam.position += pan * 900.0 * delta / cam.zoom.x
		follow = false
	if get_tree().paused: return   # pan/zoom only; no campaign work or mutable HUD reads
	# time
	var enc: String = w.get("encounter", "")
	if enc != "" and (not w["warbands"].has(enc) or Monsters.suspended_band(w["warbands"].get(enc, {}))):
		w["encounter"] = ""; enc = ""
	if enc == "":
		var worked := CampaignWorld.work_slice(Game, WORK_BUDGET_USEC)
		if worked > 0:
			Game.changed.emit()
		if pursue_wid != "":
			_update_pursuit()
		var moving := CampaignWorld.is_travelling(Game)
		if (moving or party.get("waiting", false)) and w.get("work", []).is_empty() and worked == 0:
			# Real time cannot make another midnight outrun unfinished jobs.
			# A stalled frame never requests a huge synchronous catch-up.
			Game.advance_time(minf(delta, 0.1) / SEC_PER_DAY * speed_mult, false, 0, WORK_BUDGET_USEC)
		var arrived: String = party.get("arrived", "")
		if arrived != "" and w.get("work", []).is_empty():
			party["arrived"] = ""
			_try_enter(arrived)
			return
	_show_encounter(w.get("encounter", ""))
	if follow:
		cam.position = cam.position.lerp(party["pos"], minf(1.0, delta * 6.0))
	cam.position = cam.position.clamp(Vector2.ZERO, Vector2(WorldGen.W, WorldGen.H) * WorldGen.CELL)
	party_icon.position = party["pos"]
	_sync_icons()
	_refresh_trade_overlay()
	overlay.queue_redraw()
	_hud_t -= delta
	# A midnight invalidates native health/account reads. Let the next lighter
	# frame refresh them instead of stacking that read onto an expensive job.
	if _hud_t <= 0.0 and (Time.get_ticks_usec() - frame_started < 18000 or _hud_t <= -1.0):
		_hud_t = 0.2
		_refresh_hud()
		_ambition_tick()
	if _toast_t > 0.0:
		_toast_t -= delta
		lbl_toast.visible = _toast_t > 0.0

## map tokens: one cached-texture MapToken per visible force (type / faction / pips / stance re-checked a few
## times a second), drawn in map-y order with the company on top, sized by zoom, night darkening capped at 30%.
func _sync_icons() -> void:
	var started := Time.get_ticks_usec()
	var vis := CampaignWorld.visible_warbands(Game)
	# visible_warbands already rejects suspended rosters synchronously. No
	# world mutation occurs between that query and this native token update.
	MapTokens.sync(bands_root, icons, Game, vis, cam.zoom.x, Engine.get_process_frames() % 12 == 0, party_icon)
	bands_root.modulate = MapTokens.night_comp(daylight.color)
	Perf.record_us("Map force icons", Time.get_ticks_usec() - started)

func _update_pursuit() -> void:
	var w: Dictionary = Game.world
	var wb: Dictionary = w["warbands"].get(pursue_wid, {})
	if wb.is_empty() or not CampaignWorld.visible_warbands(Game).has(pursue_wid):
		pursue_wid = ""
		return
	var party: Dictionary = w["party"]
	if (wb["pos"] as Vector2).distance_to(party["pos"]) < 40.0:
		pursue_wid = ""
		CampaignWorld.stop_travel(Game)
		_select({"kind": "warband", "id": wb["id"]})
		return
	if (party["target"] as Vector2).distance_to(wb["pos"]) > 24.0 or not CampaignWorld.is_travelling(Game):
		CampaignWorld.set_travel(Game, wb["pos"])

# ================================================================== drawing overlay
func _draw_overlay() -> void:
	var w: Dictionary = Game.world
	var party: Dictionary = w["party"]
	# Reuse the visible token set: one line per moving force, never inspect individual men here.
	for wid in icons:
		var token: MapToken = icons[wid]
		var wb: Dictionary = w["warbands"].get(wid, {})
		if not token.visible or wb.is_empty() or WarAI.speed_of(wb, float(Game.day)) <= 0.0:
			continue
		# Trade draws this consignment's full native road polyline instead.
		if trade_good != "off" and not trade_overlay._caravan(String(wid)).is_empty():
			continue
		var route: Array = wb["path"]
		overlay.draw_line(wb["pos"], route[-1], Color(token.badge_color, 0.65), 1.25 / cam.zoom.x, true)
	var path: Array = party["path"]
	if not path.is_empty():
		overlay.draw_line(party["pos"], path[-1], Color(party_icon.badge_color, 0.8), 1.25 / cam.zoom.x, true)
		var prev: Vector2 = party["pos"]
		var acc := 0.0
		for q in path:
			var seg: Vector2 = q - prev
			var L := seg.length()
			while acc < L:
				overlay.draw_circle(prev + seg * (acc / L), 2.6, Color(1, 0.95, 0.75, 0.9))
				acc += 14.0
			acc -= L
			prev = q
		var dst: Vector2 = path[-1]
		overlay.draw_arc(dst, 9.0, 0, TAU, 20, Color("#ffe08a"), 2.5)
		overlay.draw_line(dst + Vector2(-5, -5), dst + Vector2(5, 5), Color("#ffe08a"), 2.5)
		overlay.draw_line(dst + Vector2(-5, 5), dst + Vector2(5, -5), Color("#ffe08a"), 2.5)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0)
	var tgt: String = Game.contract.get("target_id", "")
	if Game.contract.get("kind", "") == "escort" and w["warbands"].has(tgt):
		# escort radius: stay inside it or the merchants halt (and eventually give up)
		var cp: Vector2 = w["warbands"][tgt]["pos"]
		var inside: bool = (w["party"]["pos"] as Vector2).distance_to(cp) <= Caravans.ESCORT_RADIUS
		var rc := Color(0.55, 1.0, 0.6, 0.55) if inside else Color(1.0, 0.4, 0.3, 0.75)
		overlay.draw_arc(cp, Caravans.ESCORT_RADIUS, 0, TAU, 64, rc, 2.5)
	if tgt != "" and icons.has(tgt):   # tracks: a hunted target out of sight is not marked (its last-seen circle is)
		var tp: Vector2 = w["warbands"][tgt]["pos"]
		overlay.draw_arc(MapTokens.center(tp, cam.zoom.x), (MapTokens.HIT_R + 2.0 + pulse * 4.0) / cam.zoom.x, 0, TAU, 32, Color(1, 0.8, 0.2, 0.9), 3.0)   # map tokens
	var ctown: String = Game.contract.get("town_id", "")
	if Game.contract.get("kind", "") == "defend" and w["towns"].has(ctown):
		overlay.draw_arc(w["towns"][ctown]["pos"], 46.0 + pulse * 4.0, 0, TAU, 40, Color(1, 0.8, 0.2, 0.8), 3.0)
	if selected.get("kind", "") == "warband" and w["warbands"].has(selected["id"]):
		overlay.draw_arc(MapTokens.center(w["warbands"][selected["id"]]["pos"], cam.zoom.x), MapTokens.HIT_R / cam.zoom.x, 0, TAU, 28, Color.WHITE, 2.0)   # map tokens
	elif selected.get("kind", "") == "party":
		overlay.draw_arc(MapTokens.center(party["pos"], cam.zoom.x), MapTokens.HIT_R / cam.zoom.x, 0, TAU, 28, Color.WHITE, 2.0)
	elif selected.get("kind", "") == "town" and w["towns"].has(selected["id"]):
		overlay.draw_arc(w["towns"][selected["id"]]["pos"], 40.0, 0, TAU, 36, Color.WHITE, 2.0)

# ================================================================== input
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressing = true; _dragging = false; _press_pos = mb.position
			elif _pressing:
				_pressing = false
				if not _dragging:
					_tap(get_global_mouse_position())
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.12, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.12, mb.position)
	elif event is InputEventMouseMotion and _pressing:
		var mm := event as InputEventMouseMotion
		if not _dragging and mm.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			cam.position -= mm.relative / cam.zoom.x
			follow = false
	elif event is InputEventMagnifyGesture:
		_zoom_at((event as InputEventMagnifyGesture).factor, (event as InputEventMagnifyGesture).position)
	elif event is InputEventPanGesture:
		cam.position += (event as InputEventPanGesture).delta * 8.0 / cam.zoom.x
		follow = false

func _zoom_at(f: float, screen_pos: Vector2) -> void:
	var before := get_global_mouse_position()
	var z := clampf(cam.zoom.x * f, ZOOM_MIN / WorldGen.K, ZOOM_MAX)   # war pick 5: zoom out as far over the 1.5x map
	cam.zoom = Vector2(z, z)
	terrain.set_zoom(z)   # world size: the decor hides when zoomed far out over a large map (the land still shows)
	# keep the point under the cursor fixed
	var vp := get_viewport_rect().size
	var after := cam.get_screen_center_position() + (screen_pos - vp * 0.5) / z
	cam.position += before - after

func _tap(p: Vector2) -> void:
	if get_tree().paused: return
	var w: Dictionary = Game.world
	if w.get("encounter", "") != "":
		return
	var z := cam.zoom.x
	if _trade_tap(p): return
	# warbands first (map tokens: hit circle r=30 screen px around each token)
	var best := MapTokens.pick(icons, w["warbands"], p, z)
	if best != "":
		_select({"kind": "warband", "id": best})
		return
	if MapTokens.center(w["party"]["pos"], z).distance_to(p) < MapTokens.HIT_R / z:
		_select({"kind": "party"})
		return
	var tbest := ""; var tbd := maxf(34.0, 40.0 / z)
	for tid in w["towns"]:
		var d: float = (w["towns"][tid]["pos"] as Vector2).distance_to(p)
		if d < tbd:
			tbd = d; tbest = tid
	if tbest != "":
		var t: Dictionary = w["towns"][tbest]
		pursue_wid = ""
		if (w["party"]["pos"] as Vector2).distance_to(t["pos"]) < TOWN_ENTER_DIST:
			_try_enter(tbest)
		elif CampaignWorld.set_travel(Game, t["pos"], tbest):
			follow = true
			_select({"kind": "town", "id": tbest})
		else:
			toast("No road leads there.")
		return
	if tracks_layer.tap(p, maxf(12.0, 16.0 / z)):   # tracks: read a noticed track (age, numbers, kind, heading)
		pursue_wid = ""
		_select({"kind": "track", "id": str(tracks_layer.track_sel[1])})
		return
	_close_info()
	pursue_wid = ""
	if CampaignWorld.set_travel(Game, p):
		follow = true
	else:
		toast("The company can't get there.")

func _trade_tap(p: Vector2) -> bool:
	if trade_good == "off": return false
	# A newly selected good waits for settled books; it must not issue travel orders.
	if trade_overlay.day < 0:
		toast("Updating trade records.")
		return true
	var hit: Dictionary = trade_overlay.pick(p)
	if hit.is_empty(): return false
	var params := {"back": "map", "back_params": {"trade_good": trade_good}}
	if hit["kind"] == "town":
		if not TownEcon.has_econ(Game.world["towns"].get(hit["id"], {})):
			toast("This town has no market records.")
			return true
		params.merge({"view": "town", "id": hit["id"], "tab": "Market"})
	else:
		params.merge({"view": "world", "tab": "Goods" if trade_good == "metal" else "Food flows",
			"force_id": hit["id"]})
	Game.goto("res://ui/records.tscn", params)
	return true

func _try_enter(tid: String) -> void:
	var t: Dictionary = Game.world["towns"].get(tid, {})
	if t.is_empty():
		return
	if CampaignWorld.is_hostile(Game, t["faction"]):
		toast("The gates of %s are barred to you." % t["name"])
		return
	CampaignWorld.stop_travel(Game)
	Game.world["party"]["waiting"] = false
	if not Game.world.get("work", []).is_empty():
		Game.world["party"]["arrived"] = tid
		return   # finish this midnight before town arrival can autosave or rest
	Game.location = tid
	Game.goto("town", {"arrive": true})   # the town autosaves on arrival (not on coming back from its sub-screens)

# ================================================================== HUD
func _style(bg: Color, border: Color = UiTheme.BORDER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 8; s.content_margin_bottom = 8
	return s

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(64, 48)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _label(fs: int = 20, col: Color = UiTheme.LIGHT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	return l

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE   # economy/navigation callbacks cannot mutate the capture
	add_child(hud)
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.theme = UiTheme.get_theme()
	hud.add_child(hud_root)
	top_panel = PanelContainer.new()
	top_panel.add_theme_stylebox_override("panel", _style(UiTheme.WOOD_2))
	hud_root.add_child(top_panel)
	var column := UiKit.vbox(4)
	top_panel.add_child(column)
	var controls := UiKit.hbox(8)
	column.add_child(controls)
	lbl_day = _label(24)
	lbl_day.add_theme_font_override("font", UiTheme.bold())
	lbl_day.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_day.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	controls.add_child(lbl_day)
	btn_wait = _button("Wait", _on_wait); controls.add_child(btn_wait)
	btn_speed = _button("x1", _on_speed); controls.add_child(btn_speed)
	controls.add_child(_button("Find", _on_center))
	lbl_gold = _label(20, UiTheme.BRASS)
	lbl_gold.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(lbl_gold)
	lbl_wages = _label(16, UiTheme.GOOD)
	lbl_wages.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(lbl_wages)
	lbl_contract = _label(15, UiTheme.BLUE)
	lbl_contract.custom_minimum_size.y = 48
	lbl_contract.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(lbl_contract)
	lbl_trade = _label(14, UiTheme.BLUE)
	lbl_trade.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_trade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_trade.visible = false
	column.add_child(lbl_trade)
	lbl_news = _label(15, UiTheme.WARN)
	lbl_news.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_news.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(lbl_news)
	lbl_log = _label(14, UiTheme.INK_SOFT)
	lbl_log.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl_log.clip_text = true
	lbl_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(lbl_log)
	lbl_toast = _label(18, UiTheme.BRASS)
	lbl_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_toast.visible = false
	hud_root.add_child(lbl_toast)
	bottom_nav = PanelContainer.new()
	bottom_nav.add_theme_stylebox_override("panel", _style(UiTheme.WOOD_2))
	hud_root.add_child(bottom_nav)
	var navigation := UiKit.flow(6)
	bottom_nav.add_child(navigation)
	navigation.add_child(_button("House", func(): Game.goto("house", {"back": "map"})))
	navigation.add_child(_button("Army", func(): Game.goto("muster", {"back": "map"})))
	navigation.add_child(_button("Court", func(): Game.goto("court", {"back": "map"})))
	navigation.add_child(_button("Dragons", func(): Game.goto("dragons", {"back": "map"})))
	navigation.add_child(_button("Ambitions", func(): AmbitionsView.open(modal_host)))
	navigation.add_child(_button("Help", func(): GuideView.open(modal_host, true)))
	navigation.add_child(_button("Records", func(): Game.goto("res://ui/records.tscn", {"view": "world", "back": "map"})))
	btn_trade = _button("Trade: " + trade_good.capitalize(), _cycle_trade)
	btn_trade.tooltip_text = "Grain; meat (fresh and preserved); metal (ore, bars and scrap). Stock more than 10% above/below the existing market target is surplus/shortage. Metal uses base-price weights for mixed units. Prices are shown relative to base. Figures refresh daily; tap marks for Records."
	navigation.add_child(btn_trade)
	navigation.add_child(_button("Save", _on_save))
	navigation.add_child(_button("Menu", func(): Game.goto("settings", {"back": "map"})))
	ruler_card = DynastyCard.new()
	ruler_card.pressed.connect(func(): Game.goto("house", {"back": "map"}))
	hud_root.add_child(ruler_card)
	info_panel = PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", _style(UiTheme.WOOD_2))
	info_panel.visible = false
	hud_root.add_child(info_panel)
	var report_scroll := UiKit.scroll()
	info_panel.add_child(report_scroll)
	var iv := UiKit.vbox(8)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.add_child(iv)
	info_title = _label(28, UiTheme.BRASS)
	info_title.add_theme_font_override("font", UiTheme.bold())
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(info_title)
	info_body = _label(20)
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(info_body)
	info_buttons = UiKit.flow(6)
	iv.add_child(info_buttons)
	enc_panel = PanelContainer.new()
	enc_panel.add_theme_stylebox_override("panel", _style(UiTheme.WOOD_3, UiTheme.PURPLE))
	enc_panel.visible = false
	hud_root.add_child(enc_panel)
	var encounter_scroll := UiKit.scroll()
	enc_panel.add_child(encounter_scroll)
	var ev := UiKit.vbox(8)
	ev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	encounter_scroll.add_child(ev)
	enc_title = _label(24, UiTheme.WARN)
	enc_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(enc_title)
	enc_body = _label(18)
	enc_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(enc_body)
	var eb := UiKit.flow(8)
	ev.add_child(eb)
	enc_fight = _button("Fight", _on_fight)
	enc_fight.custom_minimum_size = Vector2(110, 52)
	eb.add_child(enc_fight)
	var flee := _button("Retreat", _on_retreat)
	flee.custom_minimum_size = Vector2(110, 52)
	eb.add_child(flee)
	modal_host = Control.new()
	modal_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_host.theme = UiTheme.get_theme()
	hud_root.add_child(modal_host)
	hud_root.resized.connect(_layout_hud)
	top_panel.resized.connect(_queue_hud_layout)
	top_panel.minimum_size_changed.connect(_queue_hud_layout)
	bottom_nav.resized.connect(_queue_hud_layout)
	bottom_nav.minimum_size_changed.connect(_queue_hud_layout)
	_layout_hud()

func _queue_hud_layout() -> void:
	if _hud_layout_queued:
		return
	_hud_layout_queued = true
	call_deferred("_settle_hud_layout")

func _settle_hud_layout() -> void:
	_hud_layout_queued = false
	_layout_hud()

func _layout_hud() -> void:
	if hud_root == null or ruler_card == null:
		return
	var viewport := get_viewport().get_visible_rect().size
	var width := viewport.x
	if width >= 1100:
		width -= PerformancePanel.WIDTH + 16.0
	var height := viewport.y
	var narrow := width < 650
	_layout_accounts(width >= 650 and width > height)
	var nav_height := bottom_nav.get_combined_minimum_size().y
	top_panel.position = Vector2(8, 8)
	# Set width first; container sorting then recalculates wrapped label height.
	# Its minimum-size signal schedules a second layout even when time is paused.
	top_panel.size.x = width - 16
	top_panel.size.y = top_panel.get_combined_minimum_size().y
	bottom_nav.position = Vector2(8, height - nav_height - 8)
	bottom_nav.size = Vector2(width - 16, nav_height)
	var card_width := minf(340, width - 16)
	ruler_card.position = Vector2(8, bottom_nav.position.y - 146)
	ruler_card.size = Vector2(card_width, 138)
	if narrow:
		lbl_log.position = Vector2(14, ruler_card.position.y - 54)
		lbl_log.size = Vector2(width - 28, 48)
	else:
		lbl_log.position = Vector2(card_width + 20, bottom_nav.position.y - 62)
		lbl_log.size = Vector2(maxf(0, width - card_width - 38), 54)
	lbl_news.position = Vector2(14, top_panel.position.y + top_panel.size.y + 6)
	lbl_news.size.x = width - 28
	lbl_toast.position = Vector2(18, lbl_news.position.y + lbl_news.get_combined_minimum_size().y + 8)
	lbl_toast.size.x = width - 36
	var report_width := minf(470, width - 24)
	var want_h: float = (info_panel.get_child(0).get_child(0) as Control).get_combined_minimum_size().y + 28.0 if info_panel.get_child_count() > 0 else 330.0
	var report_height := minf(want_h, maxf(100, height - top_panel.size.y - nav_height - 48))
	info_panel.position = Vector2(width - report_width - 12, maxf(top_panel.size.y + 20, bottom_nav.position.y - report_height - (170 if narrow else 66)))
	info_panel.size = Vector2(report_width, report_height)
	var encounter_size := Vector2(minf(590, width - 24), minf(300, height - 24))
	enc_panel.position = (viewport - encounter_size) * 0.5
	enc_panel.size = encounter_size

func _layout_accounts(_compact: bool) -> void:
	# Lead with what the player acts on: their own purse and their army. City and realm books live in House.
	var accounts: Dictionary = _accounts_snapshot
	var house := UiKit.compact_coins(float(accounts.get("house_purse", 0)))
	var army := UiKit.compact_coins(float(accounts.get("company_wallet", Game.gold)))
	var army_status := "%d troops · wages %s a day%s" % [_hud_troops, UiKit.compact_coins(float(_hud_wages)), (" · %d unpaid" % _hud_unpaid) if _hud_unpaid > 0 else ""] if not Game.company.is_empty() else "not raised"
	var gold_text := "House purse %s     Army %s · %s" % [house, army, army_status]
	if lbl_gold.text != gold_text:
		lbl_gold.text = gold_text
		lbl_gold.mouse_filter = Control.MOUSE_FILTER_PASS
		lbl_gold.tooltip_text = "House purse %s coins (yours to spend)\nCity treasury %s coins\nFaction treasury %s coins\nArmy wallet %s coins · %d troops\nPay %d/day · %d unpaid" % [UiKit.thousands(int(accounts.get("house_purse", 0))), UiKit.thousands(int(accounts.get("city_treasury", 0))), UiKit.thousands(int(accounts.get("faction_treasury", 0))), UiKit.thousands(int(accounts.get("company_wallet", Game.gold))), _hud_troops, _hud_wages, _hud_unpaid]
	lbl_wages.visible = false

func _refresh_hud() -> void:
	var started := Time.get_ticks_usec()
	var d: float = Game.day
	lbl_day.text = Calendar.text(d)
	if daylight != null:
		daylight.color = Calendar.tint(d)
	var house: Dictionary = Game.world.get("player_house", {})
	var account_key := "%s|%d|%d" % [house.get("household_uid", ""), int(floor(Game.day)), int(Game.gold)]
	if account_key != _accounts_key:
		_accounts_key = account_key
		_accounts_snapshot = Dynasty.accounts(Game)
	_hud_troops = Game.deployed_units().size()
	_hud_wages = Game.daily_wages()
	_hud_unpaid = Game.unpaid_count()
	lbl_wages.tooltip_text = "Army wages %d/day; %d unpaid. Each purse has a separate owner." % [_hud_wages, _hud_unpaid]
	lbl_gold.tooltip_text = lbl_wages.tooltip_text
	if ruler_card != null:
		ruler_card.refresh()
	lbl_contract.text = Contracts.status_text(Game)
	lbl_contract.visible = not Game.contract.is_empty() and not Monsters.suspended_contract(Game.contract, Game.world)
	var lg: Array = Game.world.get("log", [])
	lbl_log.text = "\n".join(lg.slice(maxi(0, lg.size() - 4)))
	lbl_news.text = Diplomacy.ticker(Game)   # diplomacy: latest declaration for a few days, "" otherwise
	btn_wait.text = "Stop" if Game.world["party"].get("waiting", false) else "Wait"
	if sites != null:
		sites.sync(Game)
	if info_panel.visible:
		_fill_info()
	_layout_hud()
	Perf.record_us("Map interface", Time.get_ticks_usec() - started)

func toast(text: String) -> void:
	lbl_toast.text = text
	lbl_toast.visible = true
	_toast_t = 2.5

func _on_wait() -> void:
	var party: Dictionary = Game.world["party"]
	party["waiting"] = not party.get("waiting", false)
	_refresh_hud()

func _on_speed() -> void:
	speed_mult = {1: 2, 2: 4, 4: 1}[speed_mult]
	btn_speed.text = "x%d" % speed_mult

func _cycle_trade() -> void:
	trade_good = TRADE_OVERLAY.MODES[(TRADE_OVERLAY.MODES.find(trade_good) + 1) % TRADE_OVERLAY.MODES.size()]
	btn_trade.text = "Trade: " + trade_good.capitalize()
	_refresh_trade_overlay()

func _refresh_trade_overlay() -> void:
	if not trade_overlay.sync(Game.world, Game.day, trade_good, cam.zoom.x): return
	lbl_trade.visible = trade_good != "off"
	lbl_trade.text = "Trade: %s | + surplus  - shortage  = balanced  ? unrecorded | Prices x base | Snapshot day %d" % [
		trade_good.capitalize(), trade_overlay.day] if trade_overlay.day >= 0 else "Updating trade records."

func _on_center() -> void:
	follow = true

func _on_save() -> void:
	Game.save_game_async()   # written by a worker thread (core/game.gd): no freeze on a Large world
	toast("Game saved.")

## Ambition toasts and the one-time victory screen; the first-visit guide.
var _amb_t := 0.0
func _ambition_tick() -> void:
	_amb_t -= 0.2
	if _amb_t > 0.0: return
	_amb_t = 2.0
	Ambitions.check(Game)
	var toasts: Array = Ambitions.take_toasts(Game)
	if not toasts.is_empty():
		toast(str(toasts[-1]))
		Sound.sfx("event_fanfare", 0.7, 0.0, 0)
	var st: Dictionary = Warfare._state(Game)
	if bool(st.get("pending_victory", false)):
		st["pending_victory"] = false
		Game.goto("victory")
		return
	if not bool(Game.setting("guide_seen")) and not Dynasty.selected(Game).is_empty():
		Game.set_setting("guide_seen", true)
		GuideView.open(modal_host, false)

# ---------------------------------------------------------------- info panel
func _band_commander(wb: Dictionary) -> String:
	var top: Unit = null
	for u in wb["units"]:
		if not u.dead and u.is_officer() and (top == null or u.rank > top.rank):
			top = u
	if top != null:
		return top.name
	if Army.is_field(wb):
		var leader: Dictionary = Game.world.get("factions", {}).get(String(wb["faction"]), {}).get("war_leader", {})
		return String(leader.get("name", "Unappointed"))
	return "Unappointed"

func _set_party_objective(objective: String) -> void:
	if not WarAI.OBJECTIVES.has(objective):
		return
	var party: Dictionary = Game.world["party"]
	party["objective"] = objective
	if objective == "hold_capital":
		pursue_wid = ""
		CampaignWorld.stop_travel(Game)
		party["target"] = party["pos"]
		party["arrived"] = ""
		party["waiting"] = false
	Game.changed.emit()
	_fill_info()

func _select(sel: Dictionary) -> void:
	selected = sel
	if sel.get("kind", "") != "track":
		tracks_layer.clear_selection()   # tracks
	info_panel.visible = true
	_fill_info()

func _close_info() -> void:
	selected = {}
	_info_key = ""
	info_panel.visible = false
	tracks_layer.clear_selection()

var _info_key := ""

func _fill_info() -> void:
	var w: Dictionary = Game.world
	if selected.get("kind", "") == "warband" and Monsters.suspended_band(w.get("warbands", {}).get(selected.get("id", ""), {})):
		_close_info()
		return
	var near := false
	if selected.get("kind", "") == "warband" and w["warbands"].has(selected["id"]):
		near = (w["warbands"][selected["id"]]["pos"] as Vector2).distance_to(w["party"]["pos"]) < 60.0
	# rebuild buttons only when the selection (or attack range) changes, never under the finger
	var key := "%s|%s|%s" % [selected.get("kind", ""), selected.get("id", ""), near]
	var rebuild := key != _info_key
	_info_key = key
	if rebuild:
		for c in info_buttons.get_children():
			c.queue_free()
	if selected.get("kind", "") == "warband":
		var rep := CampaignWorld.scout_report(Game, selected["id"])
		if rep.is_empty() or not icons.has(selected["id"]):
			_close_info(); return
		info_title.text = rep["kind_text"].capitalize()
		var wb: Dictionary = w["warbands"][selected["id"]]
		var extra := ""
		if wb["kind"] == "caravan":
			extra = "\nCarrying: %s\nBound for: %s" % [rep["cargo_text"], w["towns"].get(wb["dest"], {}).get("name", "?")]
			if wb.get("escort", "") != "" and Game.contract.get("target_id", "") == wb["id"]:
				extra += "\nYou are escorting it."
		elif rep["is_contract_target"]:
			extra = "\nThis is your contract target."
		info_body.text = "Commander: %s\nTroops: %d\nObjective: %s\n%s\nGear: %s\nThey look %s.\nDisposition: %s%s" % [
			_band_commander(wb), (icons[selected["id"]] as MapToken).count, WarAI.mode_text(wb), rep["home_text"].capitalize(),
			rep["gear_text"], rep["strength_text"], rep["disposition"], extra]
		var bl := ArmyPanel.band_line(wb)   # economy spec 2: officers, stores, unpaid men
		if bl != "":
			info_body.text += "\n" + bl
		if float(wb.get("regroup_until", 0.0)) > float(Game.day):   # beaten: remustering at home (battle_rounds.gd)
			info_body.text += "\nRegrouping after a defeat: %d more days." % ceili(float(wb["regroup_until"]) - float(Game.day))
		var wid: String = selected["id"]
		if not rebuild:
			return
		if Army.is_field(wb):
			var fid0: String = wb["faction"]
			info_buttons.add_child(_button("Ranks", func(): ArmyPanel.open(modal_host, fid0)))
		if near and wb["kind"] == "caravan":
			if Caravans.can_raid(Game, wid):
				# raiding costs heavy reputation with the caravan's faction
				info_buttons.add_child(_button("Raid", func(): _close_info(); CampaignWorld.engage(Game, wid)))
		elif near:
			info_buttons.add_child(_button("Attack", func(): _close_info(); CampaignWorld.engage(Game, wid)))
		else:
			info_buttons.add_child(_button("Pursue", func(): pursue_wid = wid; follow = true))
		info_buttons.add_child(_button("Close", _close_info))
	elif selected.get("kind", "") == "party":
		var party: Dictionary = w["party"]
		var commander := Game.lead_officer()
		info_title.text = "Your army"
		info_body.text = "Commander: %s\nTroops: %d\nObjective: %s" % [
			commander.name if commander != null else "Unappointed", party_icon.count,
			WarAI.OBJECTIVES.get(String(party.get("objective", "hold_capital")), WarAI.OBJECTIVES["hold_capital"])]
		if rebuild:
			for objective in WarAI.OBJECTIVES:
				info_buttons.add_child(_button(String(WarAI.OBJECTIVES[objective]), _set_party_objective.bind(String(objective))))
			info_buttons.add_child(_button("Muster", func(): Game.goto("muster", {"back": "map"})))
			info_buttons.add_child(_button("Close", _close_info))
	elif selected.get("kind", "") == "town":
		var t: Dictionary = w["towns"].get(selected["id"], {})
		if t.is_empty():
			_close_info(); return
		info_title.text = t["name"]
		# Lead with who holds it and how they regard you; economy detail lives in Records.
		var st := Diplomacy.standing(Game, t["faction"])
		var politics: Dictionary = Feudal.summary(Game, String(selected["id"]))
		var office: Dictionary = politics.get("office", {})
		var lines: Array = []
		lines.append(CampaignWorld.faction_name(str(t["faction"])))
		lines.append("%s · %s" % [UiWords.size_word(int(t.get("size", 1))).capitalize(), UiWords.wealth_word(int(t.get("wealth", 1)))])
		if not office.is_empty():
			lines.append("%s %s · loyalty %d" % [office.get("title", "Lord"), office.get("name", "?"), int(float(politics.get("loyalty", 0)))])
		var dfear := DragonFear.fear(Game, String(selected["id"]))
		if dfear > 0.0: lines.append("Fear of dragons: %d" % int(dfear))
		lines.append("Your standing: %s" % Diplomacy.standing_word(st))
		var treaty := Diplomacy.treaty_text(Game, str(t["faction"]))
		if treaty != "": lines.append(treaty)
		if Marriage.has_claim(Game, String(selected["id"])): lines.append("Your house holds a claim here.")
		info_body.text = "\n".join(lines)
		var wtid: String = selected["id"]
		if str(t.get("faction", "")) != Warfare.player_faction(Game) and not Dynasty.selected(Game).is_empty():
			var raid := Warfare.preview(Game, wtid, "raid")
			var siege := Warfare.preview(Game, wtid, "siege")
			info_body.text += "\nGarrison: %d" % TownDefence.garrison(Game, wtid).filter(func(u): return not u.dead).size()
			if not siege.get("ok", false): info_body.text += "\n" + str(siege.get("reason", ""))
			if rebuild and (raid.get("ok", false) or siege.get("ok", false)):
				if raid.get("ok", false): info_buttons.add_child(_button("Raid", func(): _assault(wtid, "raid")))
				if siege.get("ok", false): info_buttons.add_child(_button("Besiege", func(): _assault(wtid, "siege")))
		if rebuild:
			var rtid: String = selected["id"]   # the records screen: this town, its faction, the world
			info_buttons.add_child(_button("Records", func(): Game.goto("res://ui/records.tscn", {"view": "town", "id": rtid, "back": "map"})))
			info_buttons.add_child(_button("Politics", func(): PoliticsView.open_view("politics", rtid, "map")))
			info_buttons.add_child(_button("Population", func(): PoliticsView.open_view("population", rtid, "map")))
			info_buttons.add_child(_button("Close", _close_info))
	elif selected.get("kind", "") == "track":
		tracks_layer.fill_info(self, rebuild)   # tracks

func _assault(tid: String, kind: String) -> void:
	var p := Warfare.preview(Game, tid, kind)
	if not p.get("ok", false): toast(str(p.get("reason", ""))); return
	var town: Dictionary = Game.world["towns"][tid]
	var modal := UiKit.modal(modal_host, ("Raid " if kind == "raid" else "Besiege ") + str(town["name"]), 620)
	modal.add_child(UiKit.label(str(p["reason"]), "", true))
	var meat: Dictionary = p.get("dragon_meat", {})
	if int(meat.get("dragons", 0)) > 0:
		var meat_label := UiKit.label(str(meat.get("line", "")), "", true)
		if bool(meat.get("short", false)): meat_label.add_theme_color_override("font_color", UiTheme.WARN)
		modal.add_child(meat_label)
	var note := "Raiding takes coin, burns grain and kills residents; the town's realm will remember." if kind == "raid" else "If your army wins, the settlement swears to your realm. Its defenders hold the walls and never break ranks to chase you."
	modal.add_child(UiKit.label(note, "Muted", true))
	var footer := UiKit.hbox(8); modal.add_child(footer)
	footer.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row", 110))
	footer.add_child(UiKit.spacer())
	footer.add_child(UiKit.button("Attack", func():
		UiKit.close_modal(modal); _close_info()
		var r := Warfare.start(Game, tid, kind)
		if not r.get("ok", false): toast(str(r.get("reason", "")))
		elif not r.get("battle", false): toast(str(r.get("reason", ""))); Game.changed.emit(), "", 130))

# ---------------------------------------------------------------- encounter
func _show_encounter(wid: String) -> void:
	if wid != "" and Monsters.suspended_band(Game.world.get("warbands", {}).get(wid, {})):
		if Game.world.get("encounter", "") == wid: Game.world["encounter"] = ""
		enc_panel.visible = false
		return
	if wid == "":
		enc_panel.visible = false
		return
	if enc_panel.visible:
		return
	_close_info()
	pursue_wid = ""
	var rep := CampaignWorld.scout_report(Game, wid)
	enc_title.text = rep.get("title", "%s %s!" % [rep["faction_name"], rep["kind_text"]])
	var wb: Dictionary = Game.world["warbands"][wid]
	var where := CampaignWorld.terrain_at(Game.world, Game.world["party"]["pos"])
	Game.world["party"]["waiting"] = false
	enc_body.text = "Enemy: %s, %s\nGear: %s\nThey look %s.\nGround: %s%s" % [
		String(DB.races[rep["race"]]["plural"]).capitalize(), rep["count_text"], rep["gear_text"], rep["strength_text"], where,
		"\nThis is your contract target." if rep["is_contract_target"] else
			("\nThey are falling on the caravan you escort; its guards will fight beside you." if wb.has("escort_fight") else "")]
	var fit: int = Game.deployed_units().size()
	enc_fight.disabled = fit == 0
	if fit == 0:
		enc_body.text += "\nYour field army is unraised. Raise troops at your settlement before fighting." if Game.company.is_empty() else "\nNo one in the army is fit to fight. You must retreat."
	else:
		enc_body.text += "\n%d fit to fight." % fit
	enc_panel.visible = true

func _on_fight() -> void:
	if Game.deployed_units().is_empty():
		return
	var wid: String = Game.world.get("encounter", "")
	enc_panel.visible = false
	if wid != "":
		CampaignWorld.engage(Game, wid)

func _on_retreat() -> void:
	var wid: String = Game.world.get("encounter", "")
	enc_panel.visible = false
	CampaignWorld.retreat(Game, wid)
	toast("The company falls back.")





