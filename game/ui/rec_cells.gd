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
		var fs := UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else (17 if is_header else 18)
		# v0.096: body cells use lining, tabular figures so right-aligned numbers line up column by column.
		line.add_string(txt if is_header else UiKit.group_digits(txt), UiTheme.bold() if is_header else UiTheme.numeric_font(), fs)
		natural.append(line.get_line_width())
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
	custom_minimum_size = Vector2(0, UiKit.touch_min(48 if is_header else 56))
	add_theme_stylebox_override("normal", UiTheme.sb(UiTheme.PARCH_2, UiTheme.PARCH_3, 1, 3, 8, 4))
	add_theme_stylebox_override("hover", UiTheme.sb(UiTheme.PARCH_3 if is_header else UiTheme.PARCH, UiTheme.PARCH_3, 1, 3, 8, 4))
	add_theme_stylebox_override("pressed", UiTheme.sb(UiTheme.PURPLE, UiTheme.PURPLE_TEXT, 2, 3, 8, 4))
	resized.connect(_fit)
	_fit()

## v0.098: on a wide desktop a column is never wider than its widest text (header included) plus COL_PAD, so a
## three-column table no longer puts 500 px between each number; the spare width stays empty on the right.
## A column only ever shrinks to text that fits, so nothing is cut that was whole before. Phones keep the full spread.
const COL_PAD := 28.0
var natural: Array = []   # each cell's untrimmed text width
var caps: Array = []      # per column, set by fit_columns() for the whole table

## Give every row of one table (header row included) the same per-column caps: its widest text in that column.
static func fit_columns(rows: Array) -> void:
	var widest := []
	for r in rows:
		if not (r is RecCells): continue
		for i in (r as RecCells).natural.size():
			if i >= widest.size(): widest.append(0.0)
			widest[i] = maxf(float(widest[i]), float(r.natural[i]))
	var c := widest.map(func(w): return float(w) + COL_PAD)
	for r in rows:
		if r is RecCells:
			(r as RecCells).caps = c
			(r as RecCells)._fit()

func _fit() -> void:
	var total := 0.0
	for w in weights: total += float(w)
	if total <= 0.0: total = float(cells.size())
	var usable := maxf(0.0, size.x - 20.0 - 10.0 * maxi(0, cells.size() - 1))
	for i in cells.size():
		var share := float(weights[i]) if i < weights.size() else 1.0
		cells[i].width = usable * share / total
		if not UiTheme.is_mobile() and i < caps.size():
			cells[i].width = minf(cells[i].width, float(caps[i]))
		cells[i].alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	queue_redraw()

func _draw() -> void:
	var x := 10.0
	var surface: Color = UiTheme.button_surface(self)
	for i in cells.size():
		cells[i].draw(get_canvas_item(), Vector2(x, (size.y - cells[i].get_size().y) / 2.0), UiTheme.readable(colors[i],surface))
		x += cells[i].width + 10.0
