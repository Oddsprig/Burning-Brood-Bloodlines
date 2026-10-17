class_name WoodBg
extends Control
## Dark wooden-plank backdrop drawn in code (no image assets).

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.WOOD)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var plank := 92.0
	var y := 0.0
	var i := 0
	while y < size.y:
		var shade := UiTheme.WOOD.lerp(UiTheme.WOOD_2, 0.25 + 0.2 * rng.randf())
		draw_rect(Rect2(0, y + 2, size.x, plank - 4), shade)
		for g in 7:
			var gy := y + 8 + rng.randf() * (plank - 16)
			var col := shade.darkened(0.12 + rng.randf() * 0.1)
			var pts := PackedVector2Array()
			var x := 0.0
			while x <= size.x + 40:
				pts.append(Vector2(x, gy + sin(x * 0.004 + g + i) * 3.0))
				x += 40.0
			draw_polyline(pts, col, 1.5)
		# plank seams and nails
		var seam_x := fmod(i * 337.0, 520.0) + 200.0
		while seam_x < size.x:
			draw_line(Vector2(seam_x, y), Vector2(seam_x, y + plank), Color(0, 0, 0, 0.45), 3)
			draw_circle(Vector2(seam_x - 12, y + 14), 3, Color("7a5a3a"))
			draw_circle(Vector2(seam_x - 12, y + plank - 14), 3, Color("7a5a3a"))
			seam_x += 640.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.6), 3)
		y += plank
		i += 1
	# vignette
	for k in 10:
		var a := 0.05 * (10 - k) / 10.0
		draw_rect(Rect2(Vector2(k * 8, k * 8), size - Vector2(k * 16, k * 16)), Color(0, 0, 0, a), false, 8)
