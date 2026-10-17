class_name PartyIcon
extends Node2D
## One sprite standing for a whole force on the campaign map (Battle Brothers style): the leader
## figure, 0-2 followers behind it as a size hint (1-3 / 4-8 / 9+ units), and a banner in the
## faction colour. Bobs and steps while walking. Origin is at the leader's feet.
##   var p := PartyIcon.new(); p.setup(race_id, faction_color, unit_count, leader_unit_or_null)
##   p.walking = true/false   (bob animation while moving)
##   p.facing = 1 / -1        (optional)

var race: String = "human"
var color := Color.WHITE
var count: int = 1
var leader: Unit
var walking := false:
	set(v):
		if v != walking:
			walking = v
			queue_redraw()
var facing: int = 1:
	set(v):
		var f := -1 if v < 0 else 1
		if f != facing:
			facing = f
			queue_redraw()
var secondary := Color("#e8dcc0")

var _frames: Array[Texture2D] = []   # 0 = standing, 1..4 = walk cycle
var _anchor := Vector2.ZERO
var _t := 0.0

func setup(race_id: String, faction_color: Color, unit_count: int, leader_unit: Unit = null) -> void:
	race = race_id
	color = faction_color
	count = unit_count
	leader = leader_unit
	if leader != null:
		var cols := FigurePainter.faction_colors(leader.faction)
		secondary = cols[1]
	_frames.clear()
	for i in 5:
		_frames.append(ImageTexture.create_from_image(build_image(i)))
	queue_redraw()

static func figures_for(n: int) -> int:
	# One figure per force, Battle Brothers style (Douglas, v0.006): size and make-up show when tapped.
	return 1

func _leader_spec() -> Dictionary:
	var sp: Dictionary
	if leader != null:
		sp = FigurePainter.spec_for_unit(leader)
	else:
		sp = FigurePainter.spec_generic(race, color, secondary, 3)
		sp["weapon"] = {"tid": "x", "sprite": "sword", "mat": "copper", "q": 1, "two": false, "reach": 90.0}
		sp["shield"] = {"tid": "x", "sprite": "round", "mat": "copper", "q": 0}
	sp["team"] = Color(0, 0, 0, 0)
	sp["role"] = "troop"
	sp["prim"] = FigurePainter._vivid(color)
	return sp

## Frame 0 = standing, 1..4 = walk cycle. Image anchor (feet of the leader) = `_anchor`.
func build_image(frame: int) -> Image:
	if DB.is_creature(race):   # monsters wave 1: animals, no banner (art/creature_painter.gd)
		var ci := CreaturePainter.icon(race, count, leader, frame)
		_anchor = ci["anchor"]
		return ci["image"]
	var lead := _leader_spec()
	var dm := FigurePainter.dims(lead.get("race", race))
	var raster := FigurePainter.raster_scale(String(lead.get("race", race)))
	var fsz: Vector2i = Vector2i(Vector2(dm["size"]) / raster)
	var fa: Vector2 = dm["anchor"] / raster
	var cw := fsz.x + 16
	var ch := fsz.y + 6
	_anchor = Vector2(fa.x + 8, fa.y + 4)
	var cv := PixelCanvas.new(cw, ch)
	var p := "idle" if frame == 0 else "walk"
	var tt := 0.0 if frame == 0 else float(frame - 1) / 4.0
	var nf := figures_for(count)
	var offs := [Vector2(-7, -3), Vector2(7, -2)]
	for i in nf - 1:
		var fs := FigurePainter.spec_generic(lead.get("race", race), color, secondary, 11 + i * 5)
		fs["weapon"] = {"tid": "x", "sprite": "spear" if i == 0 else "axe", "mat": "tin", "q": 0, "two": false, "reach": 200.0}
		var img := FigurePainter.render(fs, p, fposmod(tt + 0.5 * (i + 1), 1.0))
		if raster > 1.0: img.resize(fsz.x, fsz.y, Image.INTERPOLATE_NEAREST)
		_paste(cv, img, _anchor + (offs[i] as Vector2) - fa, 0.82)
	# banner behind the leader
	var c := FigurePainter._vivid(color)
	var pole_x := _anchor.x - 4.0
	var top := _anchor.y - 24.0 * FigurePainter.race_scale(lead.get("race", race)) - 13.0
	cv.set_frame(Vector2.ZERO)
	cv.begin()
	cv.line1(Vector2(pole_x, _anchor.y - 1.0), Vector2(pole_x, top), Color("#7a5230"))
	cv.end(FigurePainter.ol(Color("#7a5230")), 0.0)
	var wave := 0.0 if frame == 0 else (1.0 if frame % 2 == 0 else 0.0)
	var fl := 11.0
	var s2 := secondary
	var tb := int(top)
	cv.begin()
	cv.poly(PackedVector2Array([Vector2(pole_x, top), Vector2(pole_x - fl, top + wave), Vector2(pole_x - fl + 3.0, top + 3.5),
		Vector2(pole_x - fl, top + 7.0 - wave), Vector2(pole_x, top + 7.0)]), c, func(_x: int, y: int, col: Color) -> Color:
		return s2 if y == tb + 1 or y == tb + 5 else col)
	cv.end(FigurePainter.ol(c), 0.12)
	var m := FigurePainter.metal("copper", 3)
	cv.begin()
	cv.ellipse(Vector2(pole_x + 0.5, top - 0.5), 1.3, 1.3, m["base"])
	cv.end(m["outline"], 0.16, m["shine"])
	var limg := FigurePainter.render(lead, p, tt)
	if raster > 1.0: limg.resize(fsz.x, fsz.y, Image.INTERPOLATE_NEAREST)
	_paste(cv, limg, _anchor - fa, 1.0)
	return cv.to_image()

static func _paste(cv: PixelCanvas, img: Image, off: Vector2, shade: float) -> void:
	var ox := int(off.x)
	var oy := int(off.y)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			if shade < 1.0:
				c = Color(c.r * shade, c.g * shade, c.b * shade, c.a)
			cv.set_px(ox + x, oy + y, c)

## Campaign-map icons are static (Douglas: animation there was needless rendering work). Set true to bring
## the walk cycle back.
const ANIMATE := false

func _ready() -> void:
	set_process(ANIMATE)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # glide smoothly at sub-pixel positions

func _process(delta: float) -> void:
	if walking:
		_t += delta
		queue_redraw()

func _draw() -> void:
	if _frames.is_empty():
		return
	var idx := 0
	var bob := 0.0
	if walking and ANIMATE:
		idx = 1 + int(_t * 6.0) % 4
		bob = -absf(sin(_t * PI * 3.0)) * 2.0
	draw_set_transform(Vector2(0, bob), 0.0, Vector2(FigurePainter.PX * facing, FigurePainter.PX))
	draw_texture(_frames[idx], -_anchor)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
