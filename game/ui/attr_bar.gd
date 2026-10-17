class_name AttrBar
extends Control
## Where an attribute lands within its race's range (Factory.attr_percentile, 0.5 = race median):
## solid fill to the current value, a hatched "ghost" to the trainable ceiling (Unit.attr_cap),
## and a tick at the race median.

var pct := 0.5
var cap_pct := 0.5

func setup(race: String, attr: String, value: int, cap: int) -> AttrBar:
	pct = Factory.attr_percentile(race, attr, value)
	cap_pct = Factory.attr_percentile(race, attr, maxi(cap, value))
	custom_minimum_size = Vector2(150, 22)
	mouse_filter = MOUSE_FILTER_IGNORE
	return self

## Race-relative word for a percentile.
static func race_word(p: float) -> String:
	if p >= 0.9: return "exceptional"
	if p >= 0.7: return "above most"
	if p > 0.35: return "typical"
	if p > 0.15: return "below most"
	return "poor"

func _draw() -> void:
	var r := Rect2(Vector2(0, 3), Vector2(size.x, size.y - 6))
	draw_rect(r, UiTheme.PARCH_3)
	var ghost := Rect2(r.position, Vector2(r.size.x * cap_pct, r.size.y))
	draw_rect(ghost, Color(UiTheme.COPPER, 0.28))
	var x := r.size.x * pct
	while x < ghost.size.x:
		draw_line(Vector2(x, r.end.y), Vector2(minf(x + r.size.y, ghost.size.x), r.position.y), Color(UiTheme.COPPER, 0.45), 1.5)
		x += 7.0
	var col := UiTheme.GOOD if pct >= 0.7 else (UiTheme.BAD if pct <= 0.15 else UiTheme.COPPER)
	draw_rect(Rect2(r.position, Vector2(r.size.x * pct, r.size.y)), col)
	draw_rect(r, UiTheme.BORDER, false, 1.5)
	var mx := r.size.x * 0.5
	draw_line(Vector2(mx, 0), Vector2(mx, size.y), UiTheme.INK, 2)
