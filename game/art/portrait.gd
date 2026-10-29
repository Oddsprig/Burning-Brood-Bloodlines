class_name Portrait
extends Control
## Head-and-shoulders portrait of a unit for menus, drawn with the same layers as Paperdoll
## (FigurePainter at ~3x detail: skin, eyes, hair/beard, helm, outer armor, sleeves).
##   var p := Portrait.new(); p.custom_minimum_size = Vector2(96, 96); p.set_unit(unit)
## The picture scales to the control (integer steps when it fits), on a faction-tinted backdrop.

var unit: Unit
var show_frame := true
var _spec: Dictionary = {}
var _tex: Texture2D

func _init() -> void:
	clip_contents = true

func set_unit(u: Unit) -> void:
	unit = u
	_spec = FigurePainter.spec_for_unit(u) if u != null else {}
	_rebuild()

func set_spec(s: Dictionary) -> void:
	unit = null
	_spec = s.duplicate(true)
	_rebuild()

func refresh() -> void:
	if unit != null:
		set_unit(unit)
	else:
		_rebuild()

func build_image() -> Image:
	if _spec.is_empty():
		return null
	return FigurePainter.render_bust(_spec)

func _rebuild() -> void:
	var img := build_image()
	_tex = ImageTexture.create_from_image(img) if img != null else null
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var prim: Color = _spec.get("prim", Color(0.25, 0.25, 0.3))
	# House-tinted backdrop with a soft light behind the head and darker corners.
	var bg := prim.darkened(0.6).lerp(Color("#1a120d"), 0.45)
	draw_rect(r, bg.darkened(0.25))
	var glow := bg.lightened(0.28)
	for i in 6:
		var k := 1.0 - float(i) / 6.0
		var c := glow; c.a = 0.16
		draw_circle(Vector2(size.x * 0.5, size.y * 0.42), minf(size.x, size.y) * (0.22 + 0.42 * k), Color(c, 0.08 + 0.03 * (6 - i)))
	if _tex != null:
		var side := minf(size.x, size.y)
		var native_side := float(_tex.get_width())
		var s := side / native_side
		if s >= 1.0:
			s = floorf(s) if side - floorf(s) * native_side < native_side * 0.35 else s
		var dim := Vector2.ONE * native_side * s
		var off := Vector2((size.x - dim.x) * 0.5, size.y - dim.y)
		draw_texture_rect(_tex, Rect2(off, dim), false)
	# Vignette edges.
	var edge := Color(0, 0, 0, 0.35)
	draw_rect(Rect2(0, size.y * 0.82, size.x, size.y * 0.18), Color(0, 0, 0, 0.18))
	if show_frame:
		draw_rect(r, Color("#2a1a0c"), false, 4.0)
		draw_rect(r.grow(-2.0), Color("#d9a441"), false, 2.0)
		draw_rect(r.grow(-4.0), edge, false, 1.0)
