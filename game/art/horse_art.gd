class_name HorseArt
extends RefCounted
## Small code-drawn pixel frames, using the same outlined rasterizer as the figures.
## Fixed coat/animation keys bound the cache to 72 small textures. No game RNG.
const SIZE := Vector2i(80, 64)
const ANCHOR := Vector2(38, 61)
const ANIMATIONS := {"idle": 2, "walk": 4, "trot": 4, "gallop": 4, "fall": 4}
const COATS := {"bay": Color("#895039"), "chestnut": Color("#af6840"),
	"black": Color("#353340"), "grey": Color("#acb6bc")}
static var _frames: Dictionary = {}

static func clear_cache() -> void:
	_frames.clear()

static func frame(coat: String, animation: String, index: int) -> Texture2D:
	if not COATS.has(coat): coat = "bay"
	if not ANIMATIONS.has(animation): animation = "idle"
	index = wrapi(index, 0, int(ANIMATIONS[animation]))
	var key := "%s:%s:%d" % [coat, animation, index]
	if not _frames.has(key):
		_frames[key] = ImageTexture.create_from_image(_paint(coat, animation, index))
	return _frames[key]

static func bob(animation: String, index: int) -> float:
	if animation == "fall": return [0.0, 5.0, 12.0, 18.0][clampi(index, 0, 3)]
	if animation == "idle": return float(index % 2)
	return [-1.0, -3.0, 0.0, -2.0][index % 4] * (1.5 if animation == "gallop" else 1.0)

static func seat(animation: String, index: int) -> Vector2:
	return Vector2(41, 27 + bob(animation, index)) - ANCHOR

static func _leg(c: PixelCanvas, x: float, phase: float, far: bool, coat: Color, drop: float, fall: bool) -> void:
	var hip := Vector2(x, 38 + drop)
	var knee := Vector2(x + sin(phase) * 5, 48 + minf(drop, 5))
	var hoof := Vector2(x - sin(phase) * 9, 60)
	if fall:
		knee = hip + Vector2(7, 1)
		hoof = Vector2(x + 12, 60)
	var ink := coat.darkened(0.32 if far else 0.08)
	c.begin()
	c.capsule(hip, knee, 2.2, ink)
	c.capsule(knee, hoof, 1.25, ink)
	c.rect(Rect2(hoof + Vector2(-2, -2), Vector2(5, 3)), Color("#2b2730"))
	c.end(Color("#1b1c25"), 0.12)

static func _paint(coat: String, animation: String, index: int) -> Image:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var skin: Color = COATS[coat]
	var mane := Color("#29252e") if coat != "chestnut" else Color("#693b30")
	var dy := bob(animation, index)
	var move := animation in ["walk", "trot", "gallop"]
	var phase := float(index) * PI * 0.5 if move else 0.0
	var fall := animation == "fall"
	# Four articulated legs: diagonal pairs trot; the gallop gathers both hind legs.
	for far: bool in [true, false]:
		if not far:
			c.begin()
			c.capsule(Vector2(20, 30 + dy), Vector2(11, 37 + dy), 2.5, mane)
			c.capsule(Vector2(11, 37 + dy), Vector2(8, 47 + dy), 2, mane)
			c.end(Color("#1b1c25"), 0.12)
			c.begin()
			c.ellipse(Vector2(36, 34 + dy), 19, 9, skin)
			c.ellipse(Vector2(24, 34 + dy), 8, 10, skin)
			c.ellipse(Vector2(49, 34 + dy), 8, 11, skin)
			c.poly(PackedVector2Array([Vector2(46,31+dy),Vector2(52,15+dy),Vector2(59,13+dy),
				Vector2(62,25+dy),Vector2(56,40+dy)]), skin)
			c.end(Color("#1b1c25"), 0.18)
			c.line1(Vector2(27, 28 + dy), Vector2(43, 28 + dy), skin.lightened(0.25))
		var hind_phase := phase + (PI if far else 0.0)
		var fore_phase := phase + (0.3 if animation == "gallop" else PI) + (PI if far else 0.0)
		_leg(c, 24 if far else 22, hind_phase, far, skin, dy, fall)
		_leg(c, 50 if far else 48, fore_phase, far, skin, dy, fall)
	# Long face, pricked ears and mane keep the silhouette equine at battle zoom.
	c.begin()
	c.poly(PackedVector2Array([Vector2(51,17+dy),Vector2(50,11+dy),Vector2(54,9+dy),
		Vector2(58,15+dy),Vector2(65,18+dy),Vector2(71,24+dy),Vector2(69,29+dy),
		Vector2(60,27+dy),Vector2(56,22+dy)]), skin)
	c.poly(PackedVector2Array([Vector2(56,14+dy),Vector2(57,5+dy),Vector2(60,7+dy),Vector2(60,17+dy)]), skin)
	c.end(Color("#1b1c25"), 0.14)
	c.capsule(Vector2(52,15+dy), Vector2(47,29+dy), 1.5, mane)
	c.line1(Vector2(55,16+dy), Vector2(58,17+dy), Color("#ede4cf"))
	c.dot(Vector2(59,18+dy), Color("#171921"))
	c.dot(Vector2(68,25+dy), Color("#332631"))
	c.line1(Vector2(64,28+dy), Vector2(69,28+dy), Color("#49312d"))
	if coat == "grey":
		for p: Vector2 in [Vector2(26,32),Vector2(32,37),Vector2(40,31)]:
			c.dot(p + Vector2(0,dy), skin.darkened(0.22))
	# Saddle cloth and girth are fitted to the withers/back. MountedRiderArt supplies the full saddle.
	c.rect(Rect2(34, 25 + dy, 13, 5), Color("#3e4355"))
	c.line1(Vector2(41, 29 + dy), Vector2(43, 42 + dy), Color("#684332"))
	c.rect(Rect2(35, 24 + dy, 11, 3), Color("#88593c"))
	c.line1(Vector2(36, 24 + dy), Vector2(44, 24 + dy), Color("#c69c6d"))
	return c.to_image()
