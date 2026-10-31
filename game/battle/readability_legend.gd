extends Control
## Small persistent toggle; samples share the exact ground/effect drawing helpers.
const Ground := preload("res://battle/map_view.gd")
const Cues := preload("res://battle/readability_fx.gd")
var button: Button
var panel: PanelContainer

class Sample extends Control:
	var id := ""
	var cue := false
	func _draw() -> void:
		if cue:
			Cues.symbol(self, id, Vector2(21,18), Cues.INFO[id][1])
		elif Ground.PATTERNS.has(id):
			draw_rect(Rect2(2,2,38,30), Ground.PALETTES[id]["base"])
			Ground.paint_pattern(self, Rect2(2,2,38,30), id, Color("#e8dfbb"))
		elif id in ["rough", "blocked"]:
			Ground.paint_cell_key(self, Rect2(2,2,38,30), id)
		elif id == "raid":
			draw_rect(Rect2(10,14,22,16), Color("#ae9873"))
			draw_colored_polygon(PackedVector2Array([Vector2(6,14),Vector2(21,4),Vector2(36,14)]), Color("#d6bc81"))
		elif id == "siege":
			draw_rect(Rect2(4,12,34,18), Color("#aeaa9f"))
			for x in 3: draw_rect(Rect2(4+x*13,5,8,9), Color("#aeaa9f"))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	button = Button.new()
	button.name = "BattleLegendToggle"
	button.text = "Legend"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Terrain and combat cues"
	button.toggled.connect(func(on: bool): panel.visible = on)
	add_child(button)
	panel = PanelContainer.new()
	panel.name = "BattleLegend"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05,0.07,0.06,0.96)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = "Terrain and combat cues"
	heading.add_theme_font_size_override("font_size", 18)
	content.add_child(heading)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(sc)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(rows)
	for id: String in Ground.TERRAIN_KEY:
		_add_row(rows, id, str(Ground.TERRAIN_KEY[id]), false)
	for id: String in Cues.INFO:
		_add_row(rows, id, str(Cues.INFO[id][0]), true)
	resized.connect(_layout)
	_layout()

func _add_row(rows: VBoxContainer, id: String, text: String, cue: bool) -> void:
	var row := HBoxContainer.new()
	rows.add_child(row)
	var sample := Sample.new()
	sample.id = id; sample.cue = cue
	sample.custom_minimum_size = Vector2(44,34)
	sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sample)
	var label := Label.new()
	label.name = ("Cue_" if cue else "Terrain_") + id
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	row.add_child(label)

func _layout() -> void:
	var tap := UiKit.touch_min(34)
	button.position = Vector2(10, maxf(0, size.y - tap - 10))
	button.size = Vector2(maxf(92.0, tap), tap)
	var height := minf(440, maxf(120, size.y - 120))
	panel.size = Vector2(minf(390, maxf(240, size.x - 20)), height)
	panel.position = Vector2(10, maxf(0, size.y - height - (tap + 18)))

func is_open() -> bool:
	return panel != null and panel.visible

func close() -> void:
	button.set_pressed_no_signal(false)
	panel.hide()
