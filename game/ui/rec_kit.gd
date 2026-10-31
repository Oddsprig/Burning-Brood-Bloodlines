class_name RecKit
extends RefCounted
## Builders for the town / faction / world records screen (ui/records.gd): cards, two-line tappable rows (min 56 px),
## "not tracked" lines, small charts with min / max / now / span. Phone first: everything wraps to 720 px wide,
## nothing scrolls sideways (only the screen's tab bar does). Sortable lists: ui/rec_table.gd.

const ROW_H := 56
const NT := "not tracked"
const GREY := UiTheme.INK_SOFT

## A card: titled panel added to `parent`; returns its content box.
static func card(parent: Control, title: String, note: String = "") -> VBoxContainer:
	var p := UiKit.panel("Card")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := UiKit.vbox(4)
	p.add_child(v)
	if title != "":
		v.add_child(UiKit.label(title, "H2", true))
	if note != "":
		v.add_child(UiKit.label(note, "Small", true))
	return v

## A plain wrapped text line.
static func line(parent: Control, text: String, variation: String = "") -> Label:
	var l := UiKit.label(text, variation, true)
	l.custom_minimum_size.x = 40
	parent.add_child(l)
	return l

## Standalone notes need parchment behind their ink when the body shows wood.
static func notice(parent: Control, text: String, variation: String = "Small") -> Label:
	return line(card(parent, ""), text, variation)

## "Label: value" on one wrapped line, the value from a real field (or "not tracked").
static func kv(parent: Control, key: String, value: String) -> Label:
	var l := line(parent, "%s: %s" % [key, value])
	if value == NT:
		l.theme_type_variation = "Muted"
	return l

## A line for a field the sim does not keep yet: "Food share: not tracked".
static func nt(parent: Control, what: String) -> Label:
	var l := UiKit.label("%s: %s" % [what, NT], "Muted", true)
	l.custom_minimum_size.x = 40
	parent.add_child(l)
	return l

## A whole-row tap target, two lines: name and main number on the first, grey details on the second.
static func row(left: String, right: String, details: String, cb: Callable, col: Variant = null) -> Button:
	var b := RecRow.new()
	b.theme_type_variation = "Row"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiKit.touch_min(ROW_H))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.set_content(left, right, details, col)
	if cb.is_valid():
		b.pressed.connect(cb)
	else:
		b.disabled = false
	b.set_meta("rec_row", [left, right, details])
	return b

## A button that sits in a flow of chips (min 48 px tall).
static func chip_button(text: String, on: bool, cb: Callable, min_w: int = 96) -> Button:
	var b := UiKit.button(text, cb, "TabOn" if on else "Tab", min_w)
	var h := UiKit.touch_min(48)
	var w := float(min_w)
	if UiTheme.is_mobile():
		w = maxf(w, h)
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 18)
	return b

## A small line chart of real samples with "min / max / now over N days" under it. xs = days (or season index).
static func chart(parent: Control, title: String, xs: Array, ys: Array, unit: String = "", span_word: String = "days") -> void:
	var v := UiKit.vbox(2)
	parent.add_child(v)
	v.add_child(UiKit.label(title, "Small", true))
	if ys.size() < 2:
		v.add_child(UiKit.label("Too few samples yet (%d)." % ys.size(), "Muted", true))
		return
	var c := RecChart.new()
	c.ys = ys.map(func(x): return float(x))
	c.custom_minimum_size = Vector2(120, 90)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(c)
	var lo := INF; var hi := -INF
	for y in c.ys:
		lo = minf(lo, y); hi = maxf(hi, y)
	var span := float(xs[-1]) - float(xs[0]) if xs.size() >= 2 else float(ys.size())
	v.add_child(UiKit.label("min %s, max %s, now %s%s, over %s %s" % [num(lo), num(hi), num(float(c.ys[-1])), unit,
		num(span), span_word], "Muted", true))

## 12 -> "12", 3.456 -> "3.46", 1234.5 -> "1235".
static func num(v: float) -> String:
	if is_inf(v) or is_nan(v):
		return "-"
	if absf(v) >= 100.0 or is_equal_approx(v, round(v)):
		return str(int(round(v)))
	if absf(v) >= 10.0:
		return "%.1f" % v
	return "%.2f" % v

static func pct(part: float, whole: float) -> String:
	return "%d%%" % int(round(100.0 * part / whole)) if whole > 0.0 else "-"

## Per 1,000 people.
static func per_k(n: float, people: float) -> String:
	return "%.1f" % (1000.0 * n / people) if people > 0.0 else "-"

static func sep(parent: Control) -> void:
	parent.add_child(HSeparator.new())

## Responsive summary cards; these expose only existing facts, never derived promises.
static func metrics(parent: Control, entries: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for entry: Dictionary in entries:
		var tone: Color = entry.get("color", UiTheme.BLUE)
		var p := UiKit.panel("Card")
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.PARCH, tone, 2, 5, 10, 6))
		p.set_meta("rec_metric", entry.duplicate())
		grid.add_child(p)
		var box := UiKit.vbox(2)
		p.add_child(box)
		var title := UiKit.label(String(entry.get("title", "")), "Small", true)
		title.custom_minimum_size.x = 40
		box.add_child(title)
		var value := UiKit.label(String(entry.get("value", "")), "H2", true)
		value.custom_minimum_size.x = 40
		value.add_theme_font_size_override("font_size", 26)
		value.add_theme_color_override("font_color", UiTheme.readable(tone,UiTheme.PARCH))
		box.add_child(value)
		if String(entry.get("note", "")) != "":
			box.add_child(UiKit.label(String(entry["note"]), "Small", true))
	grid.resized.connect(func():
		var n := clampi(int(grid.size.x / 210.0), 1, 3)
		if grid.columns != n: grid.columns = n)
	return grid

## One set of column weights across the header and all rows. Numbers stay in their lane.
static func grid(parent: Control, headers: Array, rows: Array, weights: Array = []) -> VBoxContainer:
	var box := UiKit.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var shares := weights if weights.size() == headers.size() else headers.map(func(_h): return 1.0)
	var head := RecCells.new()
	head.configure(headers, shares, headers, true, UiTheme.INK_SOFT)
	box.add_child(head)
	for row: Dictionary in rows:
		var b := RecCells.new()
		b.configure(row.get("values", []), shares, headers, false, row.get("color", UiTheme.INK))
		var tap: Callable = row.get("tap", Callable())
		if tap.is_valid():
			b.pressed.connect(tap)
			b.set_meta("rec_row", [str(row.get("values", [])), "", ""])
		else:
			# Desktop keeps the compact data row. Phones keep configure()'s finger height so 30 px type is not clipped.
			if not UiTheme.is_mobile():
				b.custom_minimum_size.y = 48
		box.add_child(b)
	return box

## Stock/target bars keep the exact text even above target; only the drawing saturates.
static func meter(parent: Control, title: String, value: float, target: float, note: String = "", tone: Color = UiTheme.COPPER) -> VBoxContainer:
	var box := UiKit.vbox(3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var labels := UiKit.hbox(8)
	box.add_child(labels)
	var label := UiKit.label(title, "Small", true)
	UiKit.expand(label)
	labels.add_child(label)
	labels.add_child(UiKit.label("%s / %s" % [num(value), num(target)], "Small"))
	var bar := ProgressBar.new()
	bar.max_value = maxf(target, 1.0)
	bar.step = 0.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.add_theme_stylebox_override("background", UiTheme.sb(UiTheme.PARCH_2, UiTheme.PARCH_3, 1, 3, 0, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.sb(tone, tone, 0, 3, 0, 0))
	bar.set_meta("rec_meter", {"title": title, "value": value, "target": target})
	box.add_child(bar)
	if note != "": box.add_child(UiKit.label(note, "Small", true))
	return box

## Detail sections build on first opening, so a dashboard doesn't eagerly shape long logs.
static func disclosure(parent: Control, title: String, fill: Callable) -> VBoxContainer:
	var box := UiKit.vbox(4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var body := UiKit.vbox(6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.visible = false
	var b := UiKit.button(title + "  +", func():
		if not body.has_meta("built"):
			fill.call(body)
			body.set_meta("built", true)
		body.visible = not body.visible
		var button := box.get_child(0) as Button
		button.text = title + ("  −" if body.visible else "  +"), "Row")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(b)
	box.add_child(body)
	box.set_meta("rec_disclosure", title)
	return box
