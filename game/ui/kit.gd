class_name UiKit
extends RefCounted
## Small builders for the menu screens (code-built Control trees) plus modal picker / confirm / toast.

const TAP := 52  # desktop control height
const MOBILE_TAP := 96  # phone tap target for primary buttons, list rows and HUD controls

static var _safe_area_override: Variant = null

static func tap_height() -> int:
	return MOBILE_TAP if UiTheme.is_mobile() else TAP

## Desktop keeps `desktop_px`. Phones use at least MOBILE_TAP so a later size write cannot shrink the finger target.
static func touch_min(desktop_px: float) -> float:
	if UiTheme.is_mobile():
		return maxf(desktop_px, float(MOBILE_TAP))
	return desktop_px

static func set_safe_area_override(rect: Variant) -> void:
	_safe_area_override = rect

## Safe-area insets (left, top, right, bottom) in viewport canvas coordinates from DisplayServer.get_display_safe_area().
## Zero on desktop; a test sets a fake safe area with set_safe_area_override.
static func safe_area_margins(viewport: Viewport = null) -> Dictionary:
	if not UiTheme.is_mobile() and _safe_area_override == null:
		return {"left": 0, "top": 0, "right": 0, "bottom": 0}
	var safe_rect := Rect2(_safe_area_override) if (_safe_area_override is Rect2i or _safe_area_override is Rect2) else Rect2(DisplayServer.get_display_safe_area())
	var win_size := Vector2(DisplayServer.window_get_size())
	if viewport != null and (win_size.x <= 0.0 or win_size.y <= 0.0):
		win_size = viewport.get_visible_rect().size
	if win_size.x <= 0.0 or win_size.y <= 0.0 or safe_rect.size.x <= 0.0 or safe_rect.size.y <= 0.0:
		return {"left": 0, "top": 0, "right": 0, "bottom": 0}
	if safe_rect.end.x > win_size.x or safe_rect.end.y > win_size.y:
		if _safe_area_override == null and not OS.has_feature("mobile"):
			return {"left": 0, "top": 0, "right": 0, "bottom": 0}
		win_size = win_size.max(safe_rect.end)
	var vp_size := viewport.get_visible_rect().size if viewport != null else win_size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		vp_size = win_size
	var sx := vp_size.x / win_size.x
	var sy := vp_size.y / win_size.y
	var left := maxi(0, roundi(maxf(0.0, safe_rect.position.x) * sx))
	var top := maxi(0, roundi(maxf(0.0, safe_rect.position.y) * sy))
	var right := maxi(0, roundi(maxf(0.0, win_size.x - safe_rect.end.x) * sx))
	var bottom := maxi(0, roundi(maxf(0.0, win_size.y - safe_rect.end.y) * sy))
	return {"left": left, "top": top, "right": right, "bottom": bottom}

static func apply_safe_area(margin: MarginContainer, base_left: int = 16, base_top: int = 16, base_right: int = 16, base_bottom: int = 16) -> Dictionary:
	var safe := safe_area_margins(margin.get_viewport() if margin != null and margin.is_inside_tree() else null)
	if margin != null:
		margin.add_theme_constant_override("margin_left", base_left + int(safe["left"]))
		margin.add_theme_constant_override("margin_top", base_top + int(safe["top"]))
		margin.add_theme_constant_override("margin_right", base_right + int(safe["right"]))
		margin.add_theme_constant_override("margin_bottom", base_bottom + int(safe["bottom"]))
	return safe

## 1,156,074 -> "1.16M", 52,375 -> "52.4K" (coins as the HUD shows them: Item.COIN units are already whole coins here).
static func compact_coins(v: float) -> String:
	var a := absf(v)
	if a >= 1000000.0: return "%.2fM" % (v / 1000000.0)
	if a >= 10000.0: return "%.1fK" % (v / 1000.0)
	return str(int(round(v)))

static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func button(text: String, cb: Callable, variation: String = "", min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	var th := tap_height()
	var tw := maxi(min_w, th) if UiTheme.is_mobile() and min_w > 0 else (th if UiTheme.is_mobile() else min_w)
	b.custom_minimum_size = Vector2(tw, th)
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func panel(variation: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	return p

static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

static func expand(c: Control, h: bool = true, v: bool = false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()

## Coloured badge with text (faction chips, status tags).
static func chip(text: String, bg: Color, fg: Color = UiTheme.LIGHT) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.sb(bg, bg.darkened(0.35), 2, 12, 10, 3))
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.WOOD if fg == UiTheme.LIGHT and bg.get_luminance() > 0.45 else fg)
	l.set_meta("keep_color", true)
	l.add_theme_font_override("font", UiTheme.bold())
	l.add_theme_font_size_override("font_size", 18)
	p.add_child(l)
	return p

## An item / goods icon (art/item_icon.gd) at px, crisp pixels, centred in its row.
static func icon(tex: Texture2D, px: int = 40) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## A label + value line, value right-aligned.
static func kv(key: String, value: String, value_color: Color = UiTheme.INK) -> HBoxContainer:
	var h := hbox()
	var k := label(key, "Muted")
	h.add_child(k)
	h.add_child(spacer())
	var v := label(value)
	v.add_theme_color_override("font_color", value_color)
	h.add_child(v)
	return h

## Tab strip of big buttons. Returns the HBox; cb(name) on tap.
## Tabs share the row and shrink (ellipsis) when the window is narrow; never wider than their parent.
## Tabs keep their full names (no "Ma / Pro" truncation); a narrow window scrolls the strip sideways.
static func tab_strip(names: Array, current: String, cb: Callable) -> HBoxContainer:
	var h := hbox(6)
	var th := tap_height()
	for n in names:
		var b := button(String(n), cb.bind(n), "TabOn" if n == current else "Tab", 0)
		b.custom_minimum_size = Vector2(th if UiTheme.is_mobile() else 0, th)
		h.add_child(b)
	return h

## A row that wraps onto the next line instead of growing past the window.
static func flow(sep: int = 8) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", 6)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f

## Wrapping label that fills its row and never forces its parent wider than min_w.
static func wrap(l: Label, min_w: float = 60.0) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = min_w
	return l

## Puts a side column in a vertical scroller (same width) so a tall column never pushes the screen taller.
static func scroll_column(col: Control) -> ScrollContainer:
	var sc := scroll()
	sc.size_flags_horizontal = Control.SIZE_FILL
	sc.custom_minimum_size.x = col.custom_minimum_size.x
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(col)
	return sc

## Make a label (or button) give up width gracefully: fills its row, trims with an ellipsis.
static func shrink(c: Control, min_w: float = 40.0) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size.x = min_w
	if c is Label:
		(c as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	elif c is Button:
		(c as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return c

## Full-screen modal layer with a dimmed backdrop and a centred parchment panel. Returns the content VBox.
static func modal(host: Control, title: String, width: int = 680) -> VBoxContainer:
	var layer := Control.new()
	layer.name = "Modal"
	layer.set_meta("ui_modal", true)
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.04, 0.05, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var bounds := ScrollContainer.new()
	bounds.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	bounds.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layer.add_child(bounds)
	var p := panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bounds.add_child(p)
	var v := vbox(10)
	p.add_child(v)
	v.add_child(label(title, "H2", true))
	v.add_child(HSeparator.new())
	layer.resized.connect(func(): _fit_modal(layer, bounds, p, width))
	v.minimum_size_changed.connect(func(): _fit_modal(layer, bounds, p, width))
	host.add_child(layer)
	_fit_modal(layer, bounds, p, width)
	return v

static func _fit_modal(layer: Control, bounds: ScrollContainer, p: PanelContainer, width: int) -> void:
	if not layer.is_inside_tree(): return
	var area := layer.get_viewport_rect().size
	var limit_width := minf(float(width), maxf(48, area.x - 32))
	p.custom_minimum_size.x = maxf(48, limit_width - 14)
	var content_height := p.get_combined_minimum_size().y
	var limit_height := minf(content_height + 14, maxf(48, area.y - 32))
	bounds.size = Vector2(limit_width, limit_height)
	bounds.position = (area - bounds.size) * 0.5

static func close_modal(from: Node) -> void:
	var n := from
	while n != null and not n.has_meta("ui_modal"):
		n = n.get_parent()
	if n != null:
		n.queue_free()

## Choice list. options = [{"text", "value", "disabled"?: bool, "detail"?: String, "icon"?: Texture2D}]. on_pick(value).
static func picker(host: Control, title: String, options: Array, on_pick: Callable, width: int = 680) -> void:
	var v := modal(host, title, width)
	var sc := scroll()
	sc.custom_minimum_size = Vector2(0, mini(70 * maxi(options.size(), 1), 470))
	v.add_child(sc)
	var list := vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if options.is_empty():
		list.add_child(label("Nothing to choose from.", "Muted"))
	for o in options:
		var txt: String = o["text"]
		if o.get("detail", "") != "":
			txt += "   -   " + String(o["detail"])
		var b := button(txt, func():
			close_modal(v)
			on_pick.call(o["value"]), "Row")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if o.get("icon") is Texture2D:   # item icons (art/item_icon.gd)
			b.icon = o["icon"]
			b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		b.disabled = bool(o.get("disabled", false))
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		list.add_child(b)
	var row := hbox()
	row.add_child(spacer())
	row.add_child(button("Cancel", func(): close_modal(v), "", 160))
	v.add_child(row)

static func confirm(host: Control, text: String, yes_text: String, on_yes: Callable) -> void:
	var v := modal(host, text, 560)
	var row := flow()
	row.add_child(button("Cancel", func(): close_modal(v), "Row", 120))
	row.add_child(button(yes_text, func():
		close_modal(v)
		on_yes.call(), "Danger", 120))
	v.add_child(row)

## Message panel for longer reports (e.g. missing uniform pieces).
static func message(host: Control, title: String, lines: Array) -> void:
	var v := modal(host, title, 640)
	var sc := scroll()
	var rows := 0
	for l in lines:
		rows += 1 + String(l).length() / 52
	sc.custom_minimum_size = Vector2(0, mini(32 * maxi(rows, 1) + 16, 440))
	v.add_child(sc)
	var list := vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for l in lines:
		list.add_child(label(String(l), "", true))
	var row := hbox()
	row.add_child(spacer())
	row.add_child(button("OK", func(): close_modal(v), "", 160))
	v.add_child(row)

## Short message that floats at the bottom of the host and fades.
static func toast(host: Control, text: String, good: bool = true) -> void:
	var old := host.get_node_or_null("Toast")
	if old != null:
		old.name = "ToastOld"
		old.queue_free()
	var p := PanelContainer.new()
	p.name = "Toast"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := UiTheme.COPPER if good else Color("783f48")
	p.add_theme_stylebox_override("panel", UiTheme.sb(bg.darkened(0.1), Color("1a0f08"), 2, 10, 18, 10))
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.LIGHT)
	l.add_theme_font_override("font", UiTheme.bold())
	p.add_child(l)
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_bottom = -24
	host.add_child(p)
	if host.is_inside_tree():
		var tw := p.create_tween()
		tw.tween_interval(2.2)
		tw.tween_property(p, "modulate:a", 0.0, 0.6)
		tw.tween_callback(p.queue_free)

## Settings button for any HUD. as_overlay = true opens settings.tscn as a child popup of `host` (use it in
## battle so the fight is not lost); otherwise switches to the "settings" screen and Back returns to `back`.
static func settings_button(host: Control, back: String = "", as_overlay: bool = false) -> Button:
	return button("Settings", func(): open_settings(host, back, as_overlay), "Row", 130)

static func open_settings(host: Node, back: String = "", as_overlay: bool = false) -> void:
	if as_overlay:
		var s = load("res://ui/settings.tscn").instantiate()
		s.overlay = true
		host.add_child(s)
	else:
		Game.goto("settings", {"back": back})

## Portrait in a framed box.
static func portrait(u: Unit, px: int) -> Control:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.WOOD_2, UiTheme.BRASS.darkened(0.3), 3, 6, 3, 3))
	var p := Portrait.new()
	p.custom_minimum_size = Vector2(px, px)
	p.set_unit(u)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(p)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame

## Standard screen backdrop + top bar. Returns {"root": VBox content area, "bar": HBox in the top bar}.
static func diagnostics_lane(width: float) -> float:
	# The diagnostics overlay is hidden unless the player turns it on (F3 or Settings).
	if not bool(Game.setting("show_performance")): return 0.0
	return PerformancePanel.WIDTH + 16.0 if width >= 1100.0 else 0.0

static func screen_frame(host: Control, title: String) -> Dictionary:
	host.theme = UiTheme.get_theme()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.WOOD
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)
	var outer := vbox(0)
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(outer)
	# Leave desktop navigation beside the persistent diagnostics overlay. The
	# backdrop and host still fill the viewport; narrow layouts retain their width.
	var fit_content: Callable = func():
		var safe := safe_area_margins(host.get_viewport() if host.is_inside_tree() else null)
		outer.offset_left = safe["left"]
		outer.offset_top = safe["top"]
		outer.offset_right = -(diagnostics_lane(host.size.x) + safe["right"])
		outer.offset_bottom = -safe["bottom"]
	host.resized.connect(fit_content)
	fit_content.call()
	var bar_p := panel("Bar")
	bar_p.custom_minimum_size = Vector2(0, 68)
	outer.add_child(bar_p)
	var bar := hbox(10)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var navigation := ScrollContainer.new()
	navigation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	navigation.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bar_p.add_child(navigation)
	navigation.add_child(bar)
	var t := label(title, "Header")
	t.name = "Title"
	t.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_stretch_ratio = 1.5
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(t)
	fit_title(t)
	t.theme_changed.connect(func(): fit_title(t))
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(m)
	var root := vbox(10)
	m.add_child(root)
	return {"root": root, "bar": bar, "title": t}

## Measure only after the actual themed parent exists. Call again for dynamic titles.
static func fit_title(title: Label) -> void:
	var font: Font = title.get_theme_font("font")
	var font_size: int = title.get_theme_font_size("font_size")
	var text_width: float = font.get_string_size(title.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	title.custom_minimum_size.x = ceilf(text_width)+2.0

## Gold and day readout for top bars.
static func purse_text(game) -> String:
	var unpaid: int = game.unpaid_count() if game.has_method("unpaid_count") else 0
	return "Day %d   %s coins   wages %s/day%s" % [int(game.day) + 1, thousands(int(game.gold)), thousands(int(game.daily_wages())),
		("   %d men unpaid" % unpaid) if unpaid > 0 else ""]

## 1234567 -> "1,234,567".
static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

static func purse(game) -> Label:
	var l := label(purse_text(game), "Header")
	l.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 22)
	l.add_theme_color_override("font_color", UiTheme.BRASS)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# never cut the coins off (Douglas: "we should be able to see at least a million coins"): the line wraps onto a
	# second row when the bar is narrow instead of ending in "..."
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 120
	l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
