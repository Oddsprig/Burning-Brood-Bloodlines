class_name UiTheme
extends RefCounted
## Shared Bloodlines theme. Historical token names retain the native UI API.
## Large type and >= 48 px controls for phones. Type variations:
##   Label: "Header" (light, bold, on wood), "Title", "H2" (bold ink on parchment), "Muted", "Good", "Bad", "Small"
##   Button: "Row" (parchment list row), "RowOn" (selected row), "Danger", "Tab", "TabOn"
##   PanelContainer: "Card" (lighter parchment), "Bar" (wood strip), "Inset" (sunken parchment)

const WOOD := Color("15100d")
const WOOD_2 := Color("231912")
const WOOD_3 := Color("2c2119")
const PARCH := Color("261c15")
const PARCH_2 := Color("36281d")
const PARCH_3 := Color("6e5638")
const INK := Color("f3e6cc")
const INK_SOFT := Color("c9b592")
const LIGHT := Color("f7ecd6")
const COPPER := Color("7c2b22")
const COPPER_HI := Color("a23c2c")
const COPPER_LO := Color("4c1913")
const BRASS := Color("e6bb5e")
const BORDER := Color("7a5f3c")
const GOOD := Color("b7dc8f")
const BAD := Color("ffa0a0")
const WARN := Color("f0be73")
const BLUE := Color("b8d9ed")
const PURPLE := Color("6a2c38")
const PURPLE_TEXT := Color("f0c98a")

const FONT_SIZE := 20
const MOBILE_FONT_SIZE := 22

static var _theme: Theme
static var _bold: Font
static var _regular: Font
static var _mobile_override: Variant = null

static func is_mobile() -> bool:
	if _mobile_override != null:
		return bool(_mobile_override)
	return OS.has_feature("mobile")

static func set_mobile_override(v: Variant) -> void:
	_mobile_override = v
	_theme = null

static func base_font_size() -> int:
	return MOBILE_FONT_SIZE if is_mobile() else FONT_SIZE

static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme

## Claude Edition type: Cinzel (inscriptional capitals) for headings and buttons, Alegreya (a calligraphic
## book serif) for reading text. Both SIL OFL, bundled in ui/fonts with their licences.
static var _display: Font
static func bold() -> Font:
	if _bold == null:
		var v := FontVariation.new()
		v.base_font = load("res://ui/fonts/Cinzel.ttf") as Font
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		_bold = v
	return _bold

static func display() -> Font:
	if _display == null:
		var v := FontVariation.new()
		v.base_font = load("res://ui/fonts/Cinzel.ttf") as Font
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 900}
		_display = v
	return _display

static func regular_font() -> Font:
	if _regular == null:
		var v := FontVariation.new()
		v.base_font = load("res://ui/fonts/Alegreya.ttf") as Font
		v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
		_regular = v
	return _regular

static func contrast(foreground: Color, background: Color) -> float:
	var a: float = foreground.srgb_to_linear().get_luminance()
	var b: float = background.srgb_to_linear().get_luminance()
	return (maxf(a,b)+0.05)/(minf(a,b)+0.05)

## Keep semantic colours, lifting only dark legacy ink against dark surfaces.
static func readable(tone: Color, surface: Color = PARCH_2) -> Color:
	if contrast(tone,surface) >= 4.5: return tone
	for step in 10:
		var lifted: Color = tone.lerp(INK,float(step+1)/10.0)
		if contrast(lifted,surface) >= 4.5: return lifted
	return INK

static func button_surface(button: BaseButton) -> Color:
	var style_name: String = "normal"
	match button.get_draw_mode():
		BaseButton.DRAW_PRESSED: style_name = "pressed"
		BaseButton.DRAW_HOVER: style_name = "hover"
		BaseButton.DRAW_DISABLED: style_name = "disabled"
		BaseButton.DRAW_HOVER_PRESSED: style_name = "hover_pressed"
	var style: StyleBoxFlat = button.get_theme_stylebox(style_name) as StyleBoxFlat
	return style.bg_color if style != null else PARCH_2

static func sb(bg: Color, border: Color = BORDER, bw: int = 2, radius: int = 6, mx: int = 12, my: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	s.anti_aliasing = true
	if bw >= 2 and bg.a > 0.9:
		s.shadow_color = Color(0, 0, 0, 0.45); s.shadow_size = 4; s.shadow_offset = Vector2(0, 2)
	return s

static func _btn(t: Theme, type: String, bg: Color, fg: Color, border: Color = BORDER) -> void:
	var mx := 14 if is_mobile() else 12
	var my := 11 if is_mobile() else 8
	t.set_stylebox("normal", type, sb(bg, border, 2, 6, mx, my))
	t.set_stylebox("hover", type, sb(bg.lightened(0.12), border, 2, 6, mx, my))
	t.set_stylebox("pressed", type, sb(bg.darkened(0.18), border, 2, 6, mx, my))
	t.set_stylebox("hover_pressed", type, sb(bg.darkened(0.12), border, 2, 6, mx, my))
	t.set_stylebox("disabled", type, sb(bg.lerp(Color("444b47"), 0.65), border.lerp(Color("444b47"), 0.5), 2, 6, mx, my))
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = BRASS
	f.set_border_width_all(2)
	f.set_corner_radius_all(6)
	t.set_stylebox("focus", type, f)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, type, fg)
	t.set_color("font_disabled_color", type, fg.lerp(INK_SOFT, 0.6))
	t.set_font_size("font_size", type, base_font_size())

static func _build() -> Theme:
	var t := Theme.new()
	var fs := base_font_size()
	var bonus := fs - FONT_SIZE
	t.default_font = regular_font()
	t.default_font_size = fs
	# Labels
	t.set_color("font_color", "Label", INK)
	t.set_font_size("font_size", "Label", fs)
	_variation(t, "Header", "Label")
	t.set_color("font_color", "Header", LIGHT)
	t.set_font("font", "Header", bold())
	t.set_font_size("font_size", "Header", 28 + bonus)
	t.set_color("font_shadow_color", "Header", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Header", 2)
	t.set_constant("shadow_offset_y", "Header", 2)
	_variation(t, "Title", "Label")
	t.set_color("font_color", "Title", BRASS)
	t.set_font("font", "Title", display())
	t.set_font_size("font_size", "Title", 84)
	t.set_color("font_outline_color", "Title", WOOD)
	t.set_constant("outline_size", "Title", 14)
	t.set_color("font_shadow_color", "Title", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Title", 4)
	t.set_constant("shadow_offset_y", "Title", 5)
	_variation(t, "H2", "Label")
	t.set_font("font", "H2", bold())
	t.set_font_size("font_size", "H2", 24 + bonus)
	t.set_color("font_color", "H2", BRASS)
	_variation(t, "Muted", "Label")
	t.set_color("font_color", "Muted", INK_SOFT)
	t.set_font_size("font_size", "Muted", 18 + bonus)
	_variation(t, "Small", "Label")
	t.set_color("font_color", "Small", INK)
	t.set_font_size("font_size", "Small", 17 + bonus)
	_variation(t, "Good", "Label")
	t.set_color("font_color", "Good", GOOD)
	_variation(t, "Bad", "Label")
	t.set_color("font_color", "Bad", BAD)
	# Buttons
	_btn(t, "Button", COPPER, LIGHT)
	t.set_font("font", "Button", bold())
	_variation(t, "Row", "Button")
	_btn(t, "Row", PARCH_2, INK, PARCH_3.darkened(0.2))
	t.set_font("font", "Row", bold())
	_variation(t, "RowOn", "Button")
	_btn(t, "RowOn", PURPLE, INK, COPPER_LO)
	t.set_stylebox("normal", "RowOn", sb(PURPLE, COPPER_LO, 3, 6, 14 if is_mobile() else 12, 11 if is_mobile() else 8))
	t.set_font("font", "RowOn", bold())
	_variation(t, "Danger", "Button")
	_btn(t, "Danger", Color("783f48"), LIGHT)
	_variation(t, "Tab", "Button")
	_btn(t, "Tab", WOOD_3, LIGHT, BORDER)
	t.set_font_size("font_size", "Tab", 22 + bonus)
	_variation(t, "TabOn", "Button")
	_btn(t, "TabOn", PURPLE, LIGHT, BORDER)
	t.set_font_size("font_size", "TabOn", 22 + bonus)
	t.set_font("font", "TabOn", bold())
	t.set_constant("h_separation", "Button", 8)
	# OptionButton / MenuButton follow Button
	_btn(t, "OptionButton", PARCH_2, INK, BORDER)
	t.set_constant("arrow_margin", "OptionButton", 10)
	# Popup menus: parchment, tall rows for fingers
	t.set_stylebox("panel", "PopupMenu", sb(PARCH, BORDER, 3, 6, 6, 6))
	t.set_stylebox("hover", "PopupMenu", sb(PURPLE, COPPER_LO, 0, 4, 6, 6))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", INK_SOFT)
	t.set_font_size("font_size", "PopupMenu", 22 + bonus)
	t.set_constant("v_separation", "PopupMenu", 22 + bonus)
	t.set_constant("item_start_padding", "PopupMenu", 14)
	# Panels
	t.set_stylebox("panel", "PanelContainer", sb(PARCH, BORDER, 3, 8, 14, 12))
	t.set_stylebox("panel", "Panel", sb(PARCH, BORDER, 3, 8))
	_variation(t, "Card", "PanelContainer")
	t.set_stylebox("panel", "Card", sb(WOOD_3, PARCH_3.darkened(0.25), 2, 8, 12, 10))
	_variation(t, "Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset", sb(PARCH_2, PARCH_3.darkened(0.15), 2, 6, 10, 8))
	_variation(t, "Bar", "PanelContainer")
	t.set_stylebox("panel", "Bar", sb(WOOD_2, WOOD, 0, 0, 16, 8))
	# Scrollbars: thick for thumbs
	var sb_pad := 9 if is_mobile() else 7
	for sbt in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sbt, sb(Color(0, 0, 0, 0.12), Color(0, 0, 0, 0), 0, 6, sb_pad, sb_pad))
		t.set_stylebox("grabber", sbt, sb(COPPER, COPPER_LO, 1, 6, sb_pad, sb_pad))
		t.set_stylebox("grabber_highlight", sbt, sb(COPPER_HI, COPPER_LO, 1, 6, sb_pad, sb_pad))
		t.set_stylebox("grabber_pressed", sbt, sb(COPPER_LO, COPPER_LO, 1, 6, sb_pad, sb_pad))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	# Progress bars (skill XP)
	t.set_stylebox("background", "ProgressBar", sb(PARCH_3, BORDER, 1, 4, 0, 0))
	t.set_stylebox("fill", "ProgressBar", sb(COPPER, COPPER_LO, 1, 4, 0, 0))
	t.set_color("font_color", "ProgressBar", INK)
	t.set_font_size("font_size", "ProgressBar", 14 + bonus)
	# Rich text
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_font_size("normal_font_size", "RichTextLabel", fs)
	t.set_font("normal_font", "RichTextLabel", regular_font())
	t.set_font_size("bold_font_size", "RichTextLabel", fs)
	t.set_font("bold_font", "RichTextLabel", bold())
	# Separators
	var line := StyleBoxLine.new()
	line.color = PARCH_3.darkened(0.2)
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 10)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t

static func _variation(t: Theme, name: String, base: String) -> void:
	t.set_type_variation(name, base)
