class_name GameIcon
extends RefCounted
## Emerald dragon and gold crown on a purple shield, designed on a 32px grid.
## Static, code-native crest; no campaign/autoload dependencies.
const PixelCanvasScript := preload("res://art/pixel_canvas.gd")

static func make_icon_image(size: int) -> Image:
	if size % 32 == 0:
		var img := _draw(32, 1.0)
		if size != 32: img.resize(size, size, Image.INTERPOLATE_NEAREST)
		return img
	return _draw(size, size / 32.0)

static func _draw(px: int, k: float) -> Image:
	var cv = PixelCanvasScript.new(px, px)
	cv.set_frame(Vector2.ZERO, k, 0.0)
	var violet := Color("5b3d82")
	var green := Color("40865f")
	var light := Color("a8e0bd")
	var gold := Color("e4c47d")
	cv.begin()
	cv.poly(PackedVector2Array([Vector2(3, 1), Vector2(29, 1), Vector2(31, 3), Vector2(30, 21), Vector2(16, 31), Vector2(2, 21), Vector2(1, 3)]), violet)
	cv.end(Color("0b0c12"), 0.15)
	cv.begin()
	cv.poly(PackedVector2Array([Vector2(4, 4), Vector2(28, 4), Vector2(27, 20), Vector2(16, 28), Vector2(5, 20)]), Color("19211e"))
	cv.end(Color("29203d"), 0.0)
	# Folded wing, curled body, raised neck and horned profile.
	cv.begin()
	cv.poly(PackedVector2Array([Vector2(16, 20), Vector2(5, 7), Vector2(7, 16), Vector2(11, 15), Vector2(10, 20), Vector2(14, 18)]), green.darkened(0.15))
	cv.ellipse(Vector2(17, 21), 7, 4, green)
	cv.capsule(Vector2(19, 19), Vector2(18, 12), 2.4, green)
	cv.capsule(Vector2(18, 12), Vector2(22, 10), 1.7, green)
	cv.poly(PackedVector2Array([Vector2(21, 8), Vector2(23, 7), Vector2(23, 9), Vector2(28, 11), Vector2(24, 13), Vector2(21, 12)]), green)
	cv.poly(PackedVector2Array([Vector2(13, 22), Vector2(8, 23), Vector2(7, 19), Vector2(5, 17), Vector2(5, 23), Vector2(10, 27), Vector2(18, 24)]), green)
	cv.end(Color("0b2118"), 0.13, light)
	cv.begin()
	cv.line1(Vector2(9, 11), Vector2(15, 19), light.darkened(0.35))
	cv.line1(Vector2(14, 22), Vector2(20, 22), light.darkened(0.2))
	cv.ellipse(Vector2(23, 10), 0.6, 0.6, gold)
	cv.poly(PackedVector2Array([Vector2(11, 7), Vector2(10, 3), Vector2(13, 5), Vector2(16, 2), Vector2(19, 5), Vector2(22, 3), Vector2(21, 7)]), gold)
	cv.end(Color(0, 0, 0, 0), 0.0)
	return cv.to_image()
