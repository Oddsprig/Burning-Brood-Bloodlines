extends Control
## Independent Bloodlines entry screen; all controls remain reachable on phones.

var _title: Label
var _subtitle: Label
var _column: VBoxContainer
var _margin: MarginContainer
var _buttons: Array[Button] = []

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := TitleBackdrop.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	_margin = margin
	margin.set_anchors_preset(PRESET_FULL_RECT)
	UiKit.apply_safe_area(margin, 16, 16, 16, 16)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.add_child(center)
	_column = UiKit.vbox(10)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_column)
	_title = UiKit.label("BURNING BROOD", "Title")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(_title)
	_subtitle = UiKit.label("B L O O D L I N E S", "Header")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", UiTheme.PURPLE_TEXT)
	_column.add_child(_subtitle)
	var vow := UiKit.label("A house. A city. A bloodline.   ·   Claude Edition", "Muted")
	vow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vow.add_theme_font_size_override("font_size", 18)
	_column.add_child(vow)
	var gap := Control.new()
	gap.custom_minimum_size.y = 8
	_column.add_child(gap)
	var cont := _button("Continue", _continue)
	cont.disabled = not Game.has_save()
	if Game.has_save(): _column.add_child(cont)
	_column.add_child(_button("New Campaign", func(): Game.goto("newgame", {"back": "title"})))
	if not Game.has_save(): _column.add_child(cont)
	_column.add_child(_button("How to play", func(): GuideView.open(self), "Row"))
	_column.add_child(_button("Settings", func(): Game.goto("settings", {"back": "title"}), "Row"))
	if not (OS.has_feature("mobile") or OS.has_feature("web")):
		_column.add_child(_button("Quit", func(): get_tree().quit(), "Row"))
	resized.connect(_layout)
	_layout()

func _button(text: String, action: Callable, style: String = "") -> Button:
	var b := UiKit.button(text, action, style, 0)
	b.custom_minimum_size.y = UiKit.MOBILE_TAP if UiTheme.is_mobile() else 48   # phones keep the touch target
	_buttons.append(b)
	return b

func _layout() -> void:
	if _title == null: return
	UiKit.apply_safe_area(_margin, 16, 16, 16, 16)
	var compact := size.y < 500 or size.x < 500
	_title.add_theme_font_size_override("font_size", 36 if compact else 54)
	_subtitle.add_theme_font_size_override("font_size", 22 if compact else 28)
	_column.add_theme_constant_override("separation", 6 if size.y < 500 else 10)
	for b in _buttons:
		b.custom_minimum_size.x = clampf(size.x - 48, 272, 360)

func _continue() -> void:
	if not Game.load_game(): return
	if Dynasty.selected(Game).is_empty():
		Dynasty.prepare_world(Game)
		Game.goto("house_select")
	else:
		Game.goto("town" if Game.location != "" else "map")

class TitleBackdrop extends Control:
	## Purple night, emerald moon and a distant keep. Static code-native artwork.
	var _crest: Texture2D

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		_crest = load("res://ui/title_dragon.png") as Texture2D
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in 24:
			var t := float(i) / 24.0
			draw_rect(Rect2(0, h * t, w, h / 24.0 + 1), Color("0e0a09").lerp(Color("3a1a14"), t))
		for i in 36:
			var point := Vector2(fmod(i * 173.0 + 71.0, maxf(w, 1)), fmod(i * 97.0 + 31.0, maxf(h * 0.62, 1)))
			draw_circle(point, 1.0 if i % 3 else 1.8, Color("b9cbbd", 0.27))
		var moon := Vector2(w * 0.78, h * 0.23)
		for r in 6:
			draw_circle(moon, minf(w, h) * (0.30 - r * 0.04), Color("c2552a", 0.05 + r * 0.025))
		var base := h * 0.86
		for i in 13:
			var x := w * float(i) / 12.0
			var tower := h * (0.09 + 0.035 * (i % 4))
			draw_rect(Rect2(x - w / 26.0, base - tower, w / 13.0, tower), Color("140c0a"))
			for tooth in 3:
				draw_rect(Rect2(x - w / 26.0 + tooth * w / 39.0, base - tower - 7, w / 70.0, 9), Color("140c0a"))
		if _crest != null:
			# The ruby dragon looms over the keep, lit by the ember sky.
			var edge := minf(w * 0.62, h * 0.95)
			draw_texture_rect(_crest, Rect2(Vector2(w * 0.74, h * 0.47) - Vector2.ONE * edge * 0.5, Vector2.ONE * edge), false, Color(1, 0.9, 0.85, 0.85))
		draw_rect(Rect2(0, base, w, h - base), Color("0b0807"))
