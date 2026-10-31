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
	if animation == "idle": return 0.5 * float(index % 2)
	if animation == "gallop": return [-1.5, -2.5, 0.5, -1.0][index % 4]
	return [-0.5, -1.5, 0.0, -1.0][index % 4]

static func seat(animation: String, index: int) -> Vector2:
	# Mid-back saddle hollow just behind the withers (x=44.5), over the front legs.
	return Vector2(37.5, 25.5 + bob(animation, index)) - ANCHOR

static func dorsal_y(animation: String, index: int) -> float:
	return 25.5 + bob(animation, index)

static func withers_px(animation: String, index: int) -> float:
	return ANCHOR.y - dorsal_y(animation, index)

static func back_anchor(animation: String, index: int) -> Vector2:
	return seat(animation, index)

static func _draw_foreleg(sh: PixelCanvas.ShadedLayer, cv: PixelCanvas, m_coat: int, m_hoof: int, origin: Vector2, k_off: Vector2, f_off: Vector2, fall: bool) -> void:
	var knee := origin + Vector2(k_off.x, 11.5 + k_off.y)
	var fetlock := origin + Vector2(f_off.x, 19.5 + f_off.y)
	var hoof := fetlock + Vector2(1.1 if f_off.y >= -0.5 else -0.8, 3.2 if f_off.y >= -0.5 else 2.2)
	if fall:
		knee = origin + Vector2(6.5, 2.0)
		fetlock = origin + Vector2(11.5, 5.5)
		hoof = fetlock + Vector2(2.2, 1.0)
	sh.capsule(origin, knee, 2.5, 1.65, m_coat, 1.0)
	sh.ellipsoid(knee, 1.75, 1.55, m_coat, 1.15)
	sh.capsule(knee, fetlock, 1.35, 1.05, m_coat, 1.1)
	sh.capsule(fetlock, hoof, 1.15, 1.45, m_hoof, 1.25)
	cv.rect(Rect2(hoof + Vector2(-1.6, -0.8), Vector2(3.6, 1.8)), Color("#1e1b24"))

static func _draw_hindleg(sh: PixelCanvas.ShadedLayer, cv: PixelCanvas, m_coat: int, m_hoof: int, stifle: Vector2, h_off: Vector2, f_off: Vector2, fall: bool) -> void:
	var hock := stifle + Vector2(-3.8 + h_off.x, 10.5 + h_off.y)
	var fetlock := stifle + Vector2(-2.5 + f_off.x, 18.8 + f_off.y)
	var hoof := fetlock + Vector2(1.1 if f_off.y >= -0.5 else -0.6, 3.2 if f_off.y >= -0.5 else 2.2)
	if fall:
		hock = stifle + Vector2(-5.5, 2.5)
		fetlock = stifle + Vector2(-10.5, 5.5)
		hoof = fetlock + Vector2(-2.0, 1.0)
	sh.capsule(stifle, hock, 2.9, 1.75, m_coat, 1.0)
	sh.ellipsoid(hock, 1.85, 1.65, m_coat, 1.15)
	sh.capsule(hock, fetlock, 1.40, 1.08, m_coat, 1.1)
	sh.capsule(fetlock, hoof, 1.15, 1.45, m_hoof, 1.25)
	cv.rect(Rect2(hoof + Vector2(-1.6, -0.8), Vector2(3.6, 1.8)), Color("#1e1b24"))

static func _gait_poses(animation: String, index: int) -> Dictionary:
	var f := index % 4
	match animation:
		"walk":
			# 4-beat lateral walk: stance legs sweep smoothly; lifted leg bends knee/hock and tucks hoof under.
			var ff_k: Vector2 = [Vector2(1.5, 0.0), Vector2(-1.2, 0.0), Vector2(-3.0, 0.0), Vector2(2.8, -3.2)][f]
			var ff_h: Vector2 = [Vector2(3.2, 0.0), Vector2(-2.2, 0.0), Vector2(-5.2, 0.0), Vector2(0.2, -4.8)][f]
			var nf_k: Vector2 = [Vector2(-2.8, 0.0), Vector2(2.8, -3.2), Vector2(1.5, 0.0), Vector2(-1.2, 0.0)][f]
			var nf_h: Vector2 = [Vector2(-5.0, 0.0), Vector2(0.2, -4.8), Vector2(3.2, 0.0), Vector2(-2.2, 0.0)][f]
			var fh_k: Vector2 = [Vector2(-2.0, 0.0), Vector2(1.8, -2.8), Vector2(2.2, 0.0), Vector2(-0.5, 0.0)][f]
			var fh_h: Vector2 = [Vector2(-4.2, 0.0), Vector2(-0.8, -4.5), Vector2(3.5, 0.0), Vector2(-1.0, 0.0)][f]
			var nh_k: Vector2 = [Vector2(2.2, 0.0), Vector2(-0.5, 0.0), Vector2(-2.0, 0.0), Vector2(1.8, -2.8)][f]
			var nh_h: Vector2 = [Vector2(3.5, 0.0), Vector2(-1.0, 0.0), Vector2(-4.2, 0.0), Vector2(-0.8, -4.5)][f]
			return {"ff": [ff_k, ff_h], "nf": [nf_k, nf_h], "fh": [fh_k, fh_h], "nh": [nh_k, nh_h]}
		"trot":
			# 2-beat diagonal gait: diagonal pair supports while opposite pair lifts with flexed knee/hock.
			var ff_k: Vector2 = [Vector2(2.2, 0.0), Vector2(-2.8, 0.0), Vector2(3.4, -3.8), Vector2(4.2, -1.5)][f]
			var ff_h: Vector2 = [Vector2(4.5, 0.0), Vector2(-5.2, 0.0), Vector2(0.0, -5.8), Vector2(5.2, -2.0)][f]
			var nf_k: Vector2 = [Vector2(3.4, -3.8), Vector2(4.2, -1.5), Vector2(2.2, 0.0), Vector2(-2.8, 0.0)][f]
			var nf_h: Vector2 = [Vector2(0.0, -5.8), Vector2(5.2, -2.0), Vector2(4.5, 0.0), Vector2(-5.2, 0.0)][f]
			var fh_k: Vector2 = [Vector2(2.2, -3.2), Vector2(3.2, -1.2), Vector2(2.2, 0.0), Vector2(-2.8, 0.0)][f]
			var fh_h: Vector2 = [Vector2(-1.2, -5.2), Vector2(4.0, -1.8), Vector2(3.8, 0.0), Vector2(-5.2, 0.0)][f]
			var nh_k: Vector2 = [Vector2(2.2, 0.0), Vector2(-2.8, 0.0), Vector2(2.2, -3.2), Vector2(3.2, -1.2)][f]
			var nh_h: Vector2 = [Vector2(3.8, 0.0), Vector2(-5.2, 0.0), Vector2(-1.2, -5.2), Vector2(4.0, -1.8)][f]
			return {"ff": [ff_k, ff_h], "nf": [nf_k, nf_h], "fh": [fh_k, fh_h], "nh": [nh_k, nh_h]}
		"gallop":
			# 3-beat canter/gallop with gathered suspension and extended reach (never scissoring into an X).
			var ff_k: Vector2 = [Vector2(3.8, -4.0), Vector2(5.0, -1.5), Vector2(1.5, 0.0), Vector2(-3.2, -2.2)][f]
			var ff_h: Vector2 = [Vector2(0.5, -6.2), Vector2(7.2, -1.8), Vector2(2.8, 0.0), Vector2(-6.5, -3.8)][f]
			var nf_k: Vector2 = [Vector2(2.4, -4.5), Vector2(4.2, -3.0), Vector2(4.5, 0.0), Vector2(-1.5, 0.0)][f]
			var nf_h: Vector2 = [Vector2(-1.2, -6.5), Vector2(2.5, -4.8), Vector2(6.5, 0.0), Vector2(-3.5, 0.0)][f]
			var fh_k: Vector2 = [Vector2(2.8, -3.5), Vector2(3.5, 0.0), Vector2(-1.5, 0.0), Vector2(-3.5, -2.5)][f]
			var fh_h: Vector2 = [Vector2(0.5, -5.5), Vector2(5.2, 0.0), Vector2(-3.0, 0.0), Vector2(-6.8, -4.2)][f]
			var nh_k: Vector2 = [Vector2(3.5, -2.8), Vector2(1.8, 0.0), Vector2(-2.8, 0.0), Vector2(-2.0, -3.2)][f]
			var nh_h: Vector2 = [Vector2(2.2, -4.8), Vector2(3.0, 0.0), Vector2(-5.5, 0.0), Vector2(-4.8, -5.2)][f]
			return {"ff": [ff_k, ff_h], "nf": [nf_k, nf_h], "fh": [fh_k, fh_h], "nh": [nh_k, nh_h]}
		_:
			return {
				"ff": [Vector2(0.8, 0.0), Vector2(1.2, 0.0)],
				"nf": [Vector2(-0.5, 0.0), Vector2(-0.8, 0.0)],
				"fh": [Vector2(0.8, 0.0), Vector2(1.0, 0.0)],
				"nh": [Vector2(-0.6, 0.0), Vector2(-1.0, 0.0)],
			}

static func _paint(coat: String, animation: String, index: int) -> Image:
	var c := PixelCanvas.new(SIZE.x, SIZE.y)
	var skin: Color = COATS[coat]
	var mane := Color("#231f29") if coat != "chestnut" else Color("#5c3124")
	var sock_dark := skin.darkened(0.28) if coat == "bay" else skin.darkened(0.14)
	var dy := bob(animation, index)
	var fall := animation == "fall"
	var gp := _gait_poses(animation, index)
	var outline := Color("#16151d")

	# 1. Far legs & tail on back ShadedLayer
	var sh_back := c.shaded()
	var m_far_coat := sh_back.add_color(skin.darkened(0.24), 0.08, 1.05)
	var m_far_hoof := sh_back.add_color(sock_dark.darkened(0.28), 0.12, 1.05)
	var m_tail := sh_back.add_color(mane, 0.14, 1.12)
	var tail_sway := 2.5 if animation == "gallop" else (1.2 if animation in ["walk", "trot"] else 0.0)
	sh_back.capsule(Vector2(17.5, 27.5 + dy), Vector2(11.0 - tail_sway, 35.0 + dy), 2.4, 2.8, m_tail, 0.5)
	sh_back.capsule(Vector2(11.0 - tail_sway, 35.0 + dy), Vector2(7.5 - tail_sway * 1.3, 47.0 + dy), 2.7, 1.4, m_tail, 0.4)
	_draw_hindleg(sh_back, c, m_far_coat, m_far_hoof, Vector2(25.5, 36.5 + dy), gp["fh"][0], gp["fh"][1], fall)
	_draw_foreleg(sh_back, c, m_far_coat, m_far_hoof, Vector2(48.5, 36.5 + dy), gp["ff"][0], gp["ff"][1], fall)
	sh_back.composite(outline, true)

	# 2. Main horse body, hindquarters, barrel, chest, arched neck, head & near legs on front ShadedLayer
	var sh := c.shaded()
	var m_coat := sh.add_color(skin, 0.15, 1.12)
	var m_hoof := sh.add_color(sock_dark, 0.15, 1.10)
	var m_mane := sh.add_color(mane, 0.16, 1.15)
	var m_muzzle := sh.add_color(skin.darkened(0.22).lerp(Color("#3a3238"), 0.45), 0.10, 1.05)
	var m_pad := sh.add_color(Color("#324860"), 0.08, 1.08)
	var m_leather := sh.add_color(Color("#6b4228"), 0.22, 1.15)

	# Hindquarters / Croup (rounded muscular croup + stifle)
	sh.ellipsoid(Vector2(23.5, 31.2 + dy), 8.2, 8.4, m_coat, 2.2, 1.0, -0.15)
	sh.ellipsoid(Vector2(24.5, 36.2 + dy), 5.6, 5.2, m_coat, 2.3)
	# Rounded barrel with slight dorsal saddle dip behind withers
	sh.capsule(Vector2(25.0, 32.0 + dy), Vector2(45.0, 31.8 + dy), 8.2, 8.4, m_coat, 2.0)
	sh.ellipsoid(Vector2(35.5, 32.5 + dy), 11.8, 8.2, m_coat, 2.1)
	# Defined chest, shoulder & withers (withers at x=45, y=22.5 -> ~1.58m)
	sh.ellipsoid(Vector2(47.2, 31.5 + dy), 7.6, 8.8, m_coat, 2.3, 1.0, 0.18)
	sh.ellipsoid(Vector2(44.8, 25.5 + dy), 5.2, 3.8, m_coat, 2.25)

	# Arched muscular neck (crest from withers x=45,y=24 up to poll x=57.5,y=14)
	var head_nod := (1.2 if index % 2 == 1 else -0.5) if animation in ["walk", "gallop"] else 0.0
	sh.capsule(Vector2(45.5, 27.5 + dy), Vector2(52.0, 19.5 + dy + head_nod * 0.5), 6.5, 5.0, m_coat, 2.4)
	sh.capsule(Vector2(52.0, 19.5 + dy + head_nod * 0.5), Vector2(57.2, 14.5 + dy + head_nod), 4.9, 3.6, m_coat, 2.45)

	# Flowing mane along upper neck crest
	sh.capsule(Vector2(56.5, 12.2 + dy + head_nod), Vector2(50.0, 17.5 + dy + head_nod * 0.5), 2.0, 2.4, m_mane, 2.7)
	sh.capsule(Vector2(50.0, 17.5 + dy + head_nod * 0.5), Vector2(43.8, 23.5 + dy), 2.4, 1.8, m_mane, 2.7)

	# Equine head: round jowl/cheek (ganache) + tapering nasal bridge + soft muzzle + small horse ears
	var poll := Vector2(57.8, 14.2 + dy + head_nod)
	var muzzle := Vector2(67.2, 20.8 + dy + head_nod)
	sh.ellipsoid(poll + Vector2(1.0, 1.4), 3.6, 3.5, m_coat, 2.6)
	sh.capsule(poll + Vector2(1.2, -0.4), muzzle, 3.1, 2.0, m_coat, 2.65)
	sh.ellipsoid(muzzle + Vector2(0.6, 0.2), 2.1, 1.9, m_muzzle, 2.75)
	# Small pricked horse ears (3.5 px tall, never donkey ears)
	sh.capsule(poll + Vector2(-1.2, -1.8), poll + Vector2(-0.5, -5.0), 1.1, 0.55, m_coat, 2.5)
	sh.capsule(poll + Vector2(0.6, -1.6), poll + Vector2(1.4, -5.0), 1.15, 0.55, m_coat, 2.8)

	# Near legs (3-segment jointed gaskin/hock/cannon and forearm/knee/cannon)
	_draw_hindleg(sh, c, m_coat, m_hoof, Vector2(23.5, 36.8 + dy), gp["nh"][0], gp["nh"][1], fall)
	_draw_foreleg(sh, c, m_coat, m_hoof, Vector2(46.5, 36.8 + dy), gp["nf"][0], gp["nf"][1], fall)

	# Fitted base saddle pad, girth under belly, pommel & cantle on mid-back (x=31..44)
	sh.poly(PackedVector2Array([
		Vector2(30.5, 24.5 + dy), Vector2(43.8, 24.0 + dy),
		Vector2(44.5, 32.5 + dy), Vector2(30.0, 32.2 + dy)
	]), m_pad, 2.85, 2.0)
	sh.capsule(Vector2(38.2, 29.5 + dy), Vector2(39.2, 40.2 + dy), 1.35, 1.25, m_leather, 2.9)
	sh.capsule(Vector2(32.0, 23.2 + dy), Vector2(35.0, 25.5 + dy), 1.7, 1.4, m_leather, 3.0)
	sh.capsule(Vector2(40.2, 25.2 + dy), Vector2(42.8, 23.0 + dy), 1.4, 1.6, m_leather, 3.0)

	sh.composite(outline, true)

	# Crisp equine eye, nostril, bridle & saddle trim details
	var eye_p := poll + Vector2(3.2, 0.8)
	c.set_px(int(eye_p.x), int(eye_p.y), Color("#15131a"))
	c.set_px(int(eye_p.x) + 1, int(eye_p.y), Color("#15131a"))
	c.set_px(int(eye_p.x), int(eye_p.y) - 1, Color("#e8dfd0"))
	c.set_px(int(muzzle.x), int(muzzle.y) - 1, Color("#1c161c"))
	# Bridle headstall, noseband & rein to withers
	c.line1(poll + Vector2(0.8, -1.0), muzzle + Vector2(-1.8, -0.5), Color("#4a2d1b"))
	c.line1(muzzle + Vector2(-1.8, -1.6), muzzle + Vector2(-2.6, 1.2), Color("#4a2d1b"))
	c.line1(muzzle + Vector2(-2.0, 0.8), Vector2(43.0, 23.5 + dy), Color("#593722"))
	c.dot(muzzle + Vector2(-2.0, 0.8), Color("#e0b868"))
	# Saddle pad gold border & girth buckle
	c.line1(Vector2(30.5, 32.2 + dy), Vector2(44.2, 32.2 + dy), Color("#d9b25f"))
	c.line1(Vector2(30.5, 25.0 + dy), Vector2(30.2, 32.2 + dy), Color("#d9b25f"))
	c.dot(Vector2(38.8, 36.2 + dy), Color("#e6c373"))
	if coat == "grey":
		for p: Vector2 in [Vector2(24, 31), Vector2(31, 35), Vector2(39, 30), Vector2(22, 34)]:
			c.dot(p + Vector2(0, dy), skin.darkened(0.18))
	return c.to_image()
