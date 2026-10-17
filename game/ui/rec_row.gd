class_name RecRow
extends Button
## A records row uses one native tap target and three shaped text lines. Avoid three Label nodes per
## row and their tree/theme notifications; preserve the same fonts, offsets, clipping and full text.

var lines: Array[TextLine] = []
var right_width := 0.0
var right_color := UiTheme.INK

func set_content(left: String, right: String, details: String, col: Variant) -> void:
	set_meta("rec_row", [left, right, details])
	tooltip_text = "\n".join(PackedStringArray([left, right, details]))
	accessibility_name = (left + " " + right).strip_edges()
	accessibility_description = details
	right_color = UiTheme.readable(col if col is Color else UiTheme.INK)
	for value in [left, right, details]:
		var line := TextLine.new()
		line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_string(value, UiTheme.bold() if lines.size() < 2 else UiTheme.regular_font(),
			UiTheme.FONT_SIZE if lines.size() < 2 else 18)
		lines.append(line)
	right_width = lines[1].get_line_width() + 6.0 if right != "" else 0.0
	resized.connect(_fit_lines)
	_fit_lines()

func _fit_lines() -> void:
	if lines.is_empty(): return
	var available := maxf(0.0, size.x - 24.0)
	var rw := minf(right_width, available)
	lines[0].width = maxf(0.0, available - rw - (8.0 if rw > 0.0 else 0.0))
	lines[1].width = rw
	lines[1].alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lines[2].width = available
	queue_redraw()

func _draw() -> void:
	if lines.is_empty(): return
	var canvas := get_canvas_item()
	lines[0].draw(canvas, Vector2(12.0, 4.0 + (24.0 - lines[0].get_size().y) / 2.0), UiTheme.INK)
	lines[1].draw(canvas, Vector2(size.x - 12.0 - lines[1].width, 4.0 + (24.0 - lines[1].get_size().y) / 2.0), UiTheme.readable(right_color,UiTheme.button_surface(self)))
	lines[2].draw(canvas, Vector2(12.0, 28.0 + (24.0 - lines[2].get_size().y) / 2.0), UiTheme.INK_SOFT)
