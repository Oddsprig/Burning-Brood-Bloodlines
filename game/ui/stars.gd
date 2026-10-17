class_name TalentStars
extends Control
## 1-3 small brass stars drawn in code (Unit.talent 0/1/2 -> count 1-3); 0 = empty (no talent data).

var count := 0

func _ready() -> void:
	custom_minimum_size = Vector2(50, 18)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = MOUSE_FILTER_IGNORE

func _draw() -> void:
	for i in 3:
		var c := Vector2(8 + i * 16, size.y * 0.5)
		var pts := PackedVector2Array()
		for k in 10:
			var r := 7.0 if k % 2 == 0 else 3.0
			var ang := -PI / 2 + k * PI / 5
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
		if i < count:
			draw_colored_polygon(pts, UiTheme.BRASS.darkened(0.15))
			pts.append(pts[0])
			draw_polyline(pts, UiTheme.COPPER_LO, 1.2)
		elif count > 0:
			pts.append(pts[0])
			draw_polyline(pts, UiTheme.PARCH_3.darkened(0.2), 1.2)
