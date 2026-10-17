class_name RecCells
extends Button
## Cheap aligned records cells. Full text remains in tooltips and accessibility.

var cells: Array[TextLine] = []
var colors: Array[Color] = []
var weights: Array = []
var headings: Array = []
var header := false

func configure(values: Array, shares: Array, titles: Array, is_header: bool = false, tone: Color = UiTheme.INK) -> void:
	header = is_header
	weights = shares.duplicate()
	headings = titles.duplicate()
	var plain := []
	for value in values:
		var txt := String(value.get("text", "")) if value is Dictionary else str(value)
		plain.append(txt)
		colors.append(UiTheme.readable(value.get("color",tone) if value is Dictionary else tone))
		var line := TextLine.new()
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_string(txt, UiTheme.bold() if is_header else UiTheme.regular_font(), 17 if is_header else 18)
		cells.append(line)
	set_meta("rec_values", plain)
	var descriptions := []
	for i in plain.size():
		descriptions.append("%s: %s" % [String(titles[i]) if i < titles.size() else str(i + 1), plain[i]])
	tooltip_text = "\n".join(PackedStringArray(descriptions))
	accessibility_name = " · ".join(PackedStringArray(plain))
	accessibility_description = tooltip_text
	focus_mode = Control.FOCUS_NONE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 48 if is_header else 56)
	add_theme_stylebox_override("normal", UiTheme.sb(UiTheme.PARCH_2, UiTheme.PARCH_3, 1, 3, 8, 4))
	add_theme_stylebox_override("hover", UiTheme.sb(UiTheme.PARCH_3 if is_header else UiTheme.PARCH, UiTheme.PARCH_3, 1, 3, 8, 4))
	add_theme_stylebox_override("pressed", UiTheme.sb(UiTheme.PURPLE, UiTheme.PURPLE_TEXT, 2, 3, 8, 4))
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var total := 0.0
	for w in weights: total += float(w)
	if total <= 0.0: total = float(cells.size())
	var usable := maxf(0.0, size.x - 20.0 - 10.0 * maxi(0, cells.size() - 1))
	for i in cells.size():
		cells[i].width = usable * (float(weights[i]) if i < weights.size() else 1.0) / total
		cells[i].alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	queue_redraw()

func _draw() -> void:
	var x := 10.0
	var surface: Color = UiTheme.button_surface(self)
	for i in cells.size():
		cells[i].draw(get_canvas_item(), Vector2(x, (size.y - cells[i].get_size().y) / 2.0), UiTheme.readable(colors[i],surface))
		x += cells[i].width + 10.0
