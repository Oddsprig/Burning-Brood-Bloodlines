class_name RecChart
extends Control
## A small line chart (records screen): real samples only, scaled to their own min and max.

var ys: Array = []

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color("efe2c0"))
	draw_rect(r, Color("b89a62"), false, 1.0)
	if ys.size() < 2:
		return
	var lo := INF; var hi := -INF
	for y in ys:
		lo = minf(lo, float(y)); hi = maxf(hi, float(y))
	if hi - lo < 0.0001:
		hi = lo + 1.0
	var pts := PackedVector2Array()
	for i in ys.size():
		var x := 4.0 + (size.x - 8.0) * float(i) / float(ys.size() - 1)
		var y := size.y - 4.0 - (size.y - 8.0) * (float(ys[i]) - lo) / (hi - lo)
		pts.append(Vector2(x, y))
	draw_polyline(pts, UiTheme.COPPER_LO, 2.0, true)
