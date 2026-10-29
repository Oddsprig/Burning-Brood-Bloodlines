extends RefCounted
## Troll-only 96px bust painter. All forms and strands are drawn at native resolution.
## The exposed scalp, fleshy brow and upward lower tusks are deliberately separate.

const SIZE := 96
const INK := Color("#202922")
const BLOOD := Color("#733331")
const LIGHT := Vector3(-0.48, -0.61, 0.63)
const PROFILE := [
	Vector3(12, 43, 0.4), Vector3(13, 43, 8), Vector3(15, 43, 15),
	Vector3(19, 43, 21), Vector3(25, 44, 24), Vector3(33, 44, 25),
	Vector3(40, 44, 22), Vector3(46, 44, 21), Vector3(51, 44, 18),
	Vector3(56, 46, 19), Vector3(60, 52, 22), Vector3(64, 52, 19),
	Vector3(68, 51, 17), Vector3(72, 51, 11), Vector3(75, 50, 0.4),
]
const ARMOUR := ["cuirass", "mail", "scale", "lamellar", "scrap", "byrnie",
	"plate", "brigandine", "hauberk", "breastplate"]

var im: Image
var spec: Dictionary
var rng := RandomNumberGenerator.new()
var female := false
var young := false
var elder := false
var dead := false
var seed := 1
var set_id := 0
var sx := 1.0
var sy := 1.0
var dy := 0.0
var tilt := 0.0
var skin: Array[Color] = []
var hair: Array[Color] = []
var beard: Array[Color] = []
var cloth: Array[Color] = []
var trim := Color("#a87838")
var body: Dictionary = {}
var helm: Dictionary = {}
var lost: Array = []
var beard_on := false
var beard_style := 0

static func paint(sp: Dictionary) -> Image:
	return load("res://art/portraits/portrait_troll.gd").new()._paint(sp)

func _paint(sp: Dictionary) -> Image:
	spec = sp
	_read_spec()
	im = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	im.fill(Color.TRANSPARENT)
	_shoulders()
	if _missing("head"):
		_wound(Vector2(47, 68), 7)
		_outline()
		return im
	_back_hair()
	_neck()
	_ear(true)
	_ear(false)
	_face()
	_mottles()
	_cheeks()
	_eye(true)
	_eye(false)
	_brows()
	_nose()
	_mouth()
	_age_marks()
	_warts()
	_front_hair()
	_beard()
	_tusks()
	_headwear()
	_outline()
	return im

func _read_spec() -> void:
	female = String(spec.get("sex", "male")) == "female"
	var age := int(spec.get("age", 48))
	young = age < 30
	elder = age >= 80
	dead = bool(spec.get("dead", false))
	seed = int(spec.get("seed", 1))
	rng.seed = seed
	set_id = posmod(int(spec.get("female_set", seed)), 2)
	sx = (0.94 if female else 1.0) * (0.94 if young else (0.97 if elder else 1.0))
	sy = (1.0 if female else 0.95) if young else ((1.045 if female else 1.02) if elder else 1.0)
	dy = (1.0 if female else 4.0) if young else (1.0 if elder else 0.0)
	tilt = (0.085 if female else 0.055) if elder else (-0.055 if female else 0.015)
	tilt += float(posmod(seed, 3) - 1) * 0.014
	var base := _color("skin", Color("#7c8973")).lerp(Color("#7b8979"), 0.32)
	if elder:
		base = base.lerp(Color("#889080"), 0.20)
	base = base.lerp(Color("#c4bfb0"), (1.0 - clampf(float(spec.get("blood", 1.0)), 0.0, 1.0)) * 0.45)
	if dead:
		base = base.lerp(Color("#888881"), 0.5)
	skin = _ramp(base, Color("#273e37"), Color("#d3d0a1"))
	var hc := _color("hair", Color("#343b2c"))
	if elder:
		hc = hc.lerp(Color("#c6ccba"), 0.38)
	hair = _ramp(hc, Color("#1c2b28"), Color("#d6d8b8"))
	var bc := hc
	var b = spec.get("beard", false)
	if b is bool:
		beard_on = b
	elif b is Color:
		beard_on = true
		bc = b
	elif b is String:
		beard_on = b != "" and b != "false"
		if Color.html_is_valid(String(b)):
			bc = Color(String(b))
	beard_style = clampi(int(spec.get("beard_style", 0)), 0, 7)
	beard = _ramp(bc.lerp(Color("#857d59"), 0.10), Color("#23312a"), Color("#d4d6b8"))
	cloth = _ramp(_color("prim", Color("#584228")), Color("#211f1d"), Color("#c1a976"))
	trim = _color("sec", Color("#a87838"))
	body = spec.get("body", {}) if spec.get("body", {}) is Dictionary else {}
	helm = spec.get("helm", {}) if spec.get("helm", {}) is Dictionary else {}
	lost = spec.get("lost", []) if spec.get("lost", []) is Array else []

func _color(key: String, fallback: Color) -> Color:
	var raw = spec.get(key, fallback)
	var result := fallback
	if raw is Color:
		result = raw
	elif raw is String and Color.html_is_valid(String(raw)):
		result = Color(String(raw))
	result.a = 1.0
	return result

func _ramp(base: Color, shadow: Color, highlight: Color) -> Array[Color]:
	base.a = 1.0
	return [base.lerp(shadow, 0.83).darkened(0.13), base.lerp(shadow, 0.64),
		base.lerp(shadow, 0.36), base.darkened(0.06), base,
		base.lerp(highlight, 0.25), base.lerp(highlight, 0.48)]

func _missing(part: String) -> bool:
	return part in lost

func _p(x: float, y: float) -> Vector2:
	return Vector2(47.0 + (x - 47.0) * sx + (y - 40.0) * tilt, y * sy + dy)

func _local(p: Vector2) -> Vector2:
	var y := (p.y - dy) / sy
	return Vector2((p.x - 47.0 - (y - 40.0) * tilt) / sx + 47.0, y)

func _profile(y: float) -> Vector2:
	if y < 12.0 or y > 75.0:
		return Vector2.ZERO
	for i in range(PROFILE.size() - 1):
		var a: Vector3 = PROFILE[i]
		var b: Vector3 = PROFILE[i + 1]
		if y > b.x:
			continue
		var t := (y - a.x) / (b.x - a.x)
		var prev: Vector3 = PROFILE[maxi(0, i - 1)]
		var next: Vector3 = PROFILE[mini(PROFILE.size() - 1, i + 2)]
		# Cubic Hermite contour has continuous slopes at the cheek and jaw.
		var m0 := (Vector2(b.y, b.z) - Vector2(prev.y, prev.z)) / maxf(1.0, b.x - prev.x)
		var m1 := (Vector2(next.y, next.z) - Vector2(a.y, a.z)) / maxf(1.0, next.x - a.x)
		var row := Vector2(a.y, a.z) * (2*t*t*t - 3*t*t + 1) + m0 * (b.x-a.x) * (t*t*t - 2*t*t + t) + Vector2(b.y, b.z) * (-2*t*t*t + 3*t*t) + m1 * (b.x-a.x) * (t*t*t - t*t)
		var lower := smoothstep(51.0, 62.0, y)
		# The jaw advances after the hollow, then turns under a compact chin.
		row.x += (2.2 if female else 4.0) * lower
		if young and female:
			row.y += 1.0 * _bump(Vector2(0, y), Vector2(0, 25), Vector2(1, 10))
			row.y -= 2.4 * _bump(Vector2(0, y), Vector2(0, 35), Vector2(1, 6))
			row.y += 1.0 * _bump(Vector2(0, y), Vector2(0, 44), Vector2(1, 4))
			row.y -= 3.0 * lower
			row.x -= 0.8 * _bump(Vector2(0, y), Vector2(0, 69), Vector2(1, 6))
		elif female:
			row.y -= 1.3 + 0.7 * lower
		elif young:
			row.y -= 0.7 * lower
		if elder:
			row.y -= 1.3 * _bump(Vector2(0, y), Vector2(0, 53), Vector2(1, 5))
		return row
	return Vector2.ZERO

func _inside(q: Vector2) -> bool:
	var row := _profile(q.y)
	return row.y > 0.0 and absf(q.x - row.x) <= row.y

func _bump(q: Vector2, center: Vector2, radius: Vector2) -> float:
	var v := (q - center) / radius
	return exp(-v.length_squared() * 1.8)

func _height(q: Vector2) -> float:
	var row := _profile(clampf(q.y, 12.0, 75.0))
	var u := (q.x - row.x) / maxf(1.0, row.y)
	var v := (q.y-43.0)/35.0
	var z := 11.0 * sqrt(maxf(0.02, 1.0-u*u)) * sqrt(maxf(0.16, 1.0-v*v))
	z += 3.1 * _bump(q, Vector2(41, 25), Vector2(15, 14))
	var cheek_y := (44.5 if female and young else 46.0) + (q.x-30.0)*0.20
	z += 3.5 * maxf(0.0, 1.0-absf(q.x-31.0)/9.0) * maxf(0.0, 1.0-absf(q.y-cheek_y)/3.0)
	z += 2.2 * maxf(0.0, 1.0-absf(q.x-63.0)/6.0) * maxf(0.0, 1.0-absf(q.y-46.0)/3.0)
	z -= (2.7 if elder else 2.1) * _bump(q, Vector2(32, 53), Vector2(7, 6))
	z -= 1.8 * _bump(q, Vector2(64, 53), Vector2(5, 5))
	z += 0.8 * _bump(q, Vector2(48, 55), Vector2(12, 4))
	var muzzle_y := 60.0 if female and young else 61.5
	z += (8.5 if female else 11.5) * _bump(q, Vector2(57, muzzle_y), Vector2(15 if female else 17, 5.2))
	z -= 0.65 * _bump(q, Vector2(55, 65.7), Vector2(8, 2.0))
	z += (3.5 if female else 4.5) * _bump(q, Vector2(56, 68.5), Vector2(13, 6.0))
	return z

func _face() -> void:
	for y in range(10, 82):
		for x in range(15, 83):
			var q := _local(Vector2(x + 0.5, y + 0.5))
			if not _inside(q) or (_missing("jaw") and q.y > 57.0):
				continue
			var nx := (_height(q + Vector2(-0.7, 0)) - _height(q + Vector2(0.7, 0))) / 1.4
			var ny := (_height(q + Vector2(0, -0.7)) - _height(q + Vector2(0, 0.7))) / 1.4
			var n := Vector3(nx, ny, 1.0).normalized()
			var lit := 0.28 + maxf(0.0, n.dot(LIGHT)) * 0.65
			lit -= smoothstep(68.0, 75.0, q.y) * 0.21
			lit -= 0.06 * _bump(q, Vector2(31, 53), Vector2(6, 5))
			lit -= 0.04 * _bump(q, Vector2(64, 53), Vector2(5, 5))
			if q.y > 49.0 and q.y < 57.0:
				lit = maxf(lit, 0.30)
			if q.y < 35.0:
				lit -= 0.055 * smoothstep(43.0, 56.0, q.x)
			_px(x, y, skin[clampi(int(lit * 7.0), 0, 6)])
	# Small curved light planes keep the crown from reading as one flat stripe.
	_curve(_p(30, 24), _p(31, 18), _p(37, 17), _p(42, 19), 1.1, skin[5])
	_curve(_p(31, 26), _p(32, 22), _p(35, 20), _p(38, 20), 0.5, skin[6])
	if _missing("jaw"):
		_wound(_p(50, 58), 7)

func _shoulders() -> void:
	var left_y := (69.0 if young else 61.0) if female else (65.0 if young else (58.0 if elder else 60.0))
	var right_y := left_y + (-4.0 if female and young else (4.0 if elder or young else 5.0))
	var pts := PackedVector2Array([Vector2(0, 96), Vector2(0, 80),
		Vector2(5, left_y+12), Vector2(12, left_y+5), Vector2(22, left_y),
		Vector2(32, left_y+4), Vector2(46, 75), Vector2(58, 75),
		Vector2(69, right_y+2), Vector2(77, right_y), Vector2(87, right_y+8),
		Vector2(93, 81), Vector2(96, 88), Vector2(96, 96)])
	if female:
		for i in pts.size():
			pts[i].x = 48 + (pts[i].x - 48) * (0.86 if young else 0.91)
	_poly_ramp(pts, cloth, 0.0)
	# Unequal broad folds turn around the shoulder, then disappear into shadow.
	_poly_ramp(PackedVector2Array([Vector2(7, left_y+17), Vector2(18, left_y+9),
		Vector2(27, left_y+10), Vector2(38, 82), Vector2(24, 79), Vector2(10, 88)]), cloth, -0.17)
	_curve(Vector2(9, left_y+15), Vector2(14, left_y+10), Vector2(21, left_y+8), Vector2(27, left_y+11), 1.2, cloth[4])
	_curve(Vector2(12, 94), Vector2(20, 83), Vector2(32, 81), Vector2(39, 84), 2.0, cloth[2])
	_curve(Vector2(15, 93), Vector2(24, 85), Vector2(30, 84), Vector2(34, 85), 0.7, cloth[4])
	_curve(Vector2(42, 88), Vector2(49, 88), Vector2(54, 92), Vector2(59, 96), 1.1, cloth[1])
	_curve(Vector2(77, right_y+8), Vector2(86, right_y+14), Vector2(86, 83), Vector2(88, 91), 2.4, cloth[2])
	_curve(Vector2(77, right_y+7), Vector2(81, right_y+9), Vector2(84, 80), Vector2(84, 84), 0.9, cloth[4])
	if female:
		_curve(Vector2(72, right_y+7), Vector2(65, 82), Vector2(43, 82), Vector2(33, 92), 2.2, cloth[2])
		_curve(Vector2(69, right_y+10), Vector2(63, 81), Vector2(53, 83), Vector2(48, 85), 0.8, cloth[5])
	# Ragged hide edge: clumps, with no checkerboard texture.
	var hide := _ramp(cloth[5], Color("#332b22"), Color("#d5c59b"))
	_curve(Vector2(11, left_y+9), Vector2(19, left_y+2), Vector2(27, left_y+4), Vector2(35, left_y+13), 3.0, hide[2])
	for i in range(5):
		var a := Vector2(13+i*4, left_y+7+absf(float(i-2))*0.7)
		_lock(a, a+Vector2(1, -1), a+Vector2(3, 2), a+Vector2(3+posmod(i, 2), 4), 2.0, hide)
	if _armoured():
		_armour()
	else:
		_curve(Vector2(64, 76), Vector2(59, 81), Vector2(57, 88), Vector2(52, 96), 2.8, cloth[0])
		_curve(Vector2(63, 76), Vector2(58, 81), Vector2(56, 88), Vector2(51, 96), 1.4, trim.darkened(0.38))
		for i in range(3):
			_line(Vector2(55-i*2, 83+i*4), Vector2(59-i*2, 84+i*4), 0.7, trim.lightened(0.12))

func _neck() -> void:
	if _missing("neck"):
		_wound(Vector2(48, 73), 5)
		return
	_oval(_p(49, 71), Vector2(15*sx, 9), skin, -0.28)
	_curve(_p(37, 68), _p(37, 72), _p(41, 76), _p(44, 78), 1.2, skin[2])
	_curve(_p(61, 71), _p(60, 74), _p(60, 76), _p(58, 78), 0.7, skin[1])

func _ear(near: bool) -> void:
	var id := "ear_r" if near else "ear_l"
	var x := 22.0 if near else 67.5
	var c := _p(x, 40)
	if _missing(id):
		_wound(c, 2)
		return
	var s := -1.0 if near else 1.0
	var drop := 2.0 if elder else 0.0
	_poly_ramp(PackedVector2Array([_p(x-s, 38), _p(x+s*5, 35),
		_p(x+s*7, 37), _p(x+s*6, 43), _p(x+s*3, 47+drop),
		_p(x, 45+drop)]), skin, -0.12 if near else -0.30)
	_curve(_p(x+s, 39), _p(x+s*5, 36), _p(x+s*6, 40), _p(x+s*3, 44+drop), 0.85, skin[1])
	_line(_p(x+s*4, 38), _p(x+s*5, 40), 0.65, skin[4 if near else 3])

func _cheeks() -> void:
	# The ear ends behind this crease; the cheekbone runs towards the nose.
	_curve(_p(23, 38), _p(22, 42), _p(23, 45), _p(25, 46), 0.65, skin[1])
	_curve(_p(67, 39), _p(68, 42), _p(67, 44), _p(66, 45), 0.7, skin[0])
	var lift := -1.5 if female and young else 0.0
	_line(_p(26, 46+lift), _p(31, 45+lift), 0.6, skin[5])
	_line(_p(31, 45+lift), _p(36, 48+lift), 0.6, skin[4])
	_curve(_p(27, 49+lift), _p(28, 51), _p(31, 54), _p(35, 55), 0.7, skin[2])
	_line(_p(61, 46), _p(65, 47), 0.6, skin[4])
	_curve(_p(66, 49), _p(64, 51), _p(63, 53), _p(64, 55), 0.6, skin[2])

func _eye(near: bool) -> void:
	var eye_x := (36.0 if near else 58.5) if female and young else ((35.0 if near else 58.0) if female else (34.0 if near else 59.0))
	var eye_y := (38.0 if near else 39.0) if female and young else (39.0 if near else 40.0)
	var c := _p(eye_x, eye_y)
	var id := "eye_r" if near else "eye_l"
	var ex := 5.1 if near else 4.3
	_oval(c+Vector2(0, 0.5), Vector2(ex+1.1, 3.7 if elder else 3.1), skin, -0.29)
	_curve(c+Vector2(-ex, 3), c+Vector2(-1, 5), c+Vector2(3, 4), c+Vector2(ex, 2), 0.6, skin[3 if near else 2])
	if _missing(id):
		_wound(c, 2)
		return
	if dead:
		_line(c-Vector2(ex-1, 0), c+Vector2(ex-1, 1), 0.7, skin[0])
		return
	var x := int(round(c.x))
	var y := int(round(c.y))
	var wide := 4 if near else 3
	var whites := Color("#e3dfc5") if near else Color("#b9c2a8")
	var openness := 4 if female and young and near else 3
	var slope := (0.6 if near else -0.5) if young else (-0.35 if near else 0.4)
	if elder:
		slope = -0.5 if near else 0.7
	if female and young:
		slope = -0.65 if near else 0.25
	var ix := (-1 if young else (0 if elder else 1)) if not female else (-1 if young else 1)
	for xx in range(-wide, wide+1):
		var top := int(round(float(xx)*slope/float(wide))) - 1
		if absi(xx) == wide:
			top += 1
		var bottom := top + openness - (2 if absi(xx) == wide else 0)
		for yy in range(top, bottom):
			var col := whites.darkened(0.15 if yy == top else 0.0)
			if absi(xx-ix) <= 1:
				col = Color("#b18b3d") if yy == top else Color("#d8ad50")
			if xx == ix:
				col = Color("#263026")
			_px(x+xx, y+yy, col)
		_px(x+xx, y+top-1, skin[0])
		if absi(xx) < wide:
			_px(x+xx, y+bottom, skin[3 if near else 2])
	_px(x+ix, y-1, Color("#fff0c5"))

func _brows() -> void:
	var thickness := (2.3 if elder else 1.7) if female else (2.5 if young else 2.8)
	var lift := (-2.0 if young else 0.0) if female else (-0.5 if young else -0.6)
	var inner := (0.6 if young else -0.5) if female else (-1.5 if young else (-0.8 if elder else -0.3))
	var a := _p(25, 36+lift)
	var b := _p(29, 31+lift)
	var c := _p(38, 32+lift+inner)
	var d := _p(43, 36+lift+inner)
	_curve(a+Vector2(0, 1), b+Vector2(0, 1), c+Vector2(0, 1), d+Vector2(0, 1), thickness, skin[1])
	_curve(a, b, c, d, thickness*0.82, skin[4])
	_curve(a+Vector2(1, -0.5), b, c-Vector2(1, 1), d-Vector2(1, 1), 0.75, skin[5])
	var far_lift := 1.5 if young and female else (-1.0 if elder and female else 0.0)
	_curve(_p(53, 36+lift-inner+far_lift), _p(56, 32+lift+far_lift), _p(64, 33+lift), _p(67, 38+lift), thickness, skin[2])
	_curve(_p(54, 35+lift-inner+far_lift), _p(57, 32+lift+far_lift), _p(63, 33+lift), _p(66, 36+lift), thickness*0.63, skin[4])
	# Sparse coarse eyebrow hairs; the ridge remains unmistakably skin.
	_line(_p(28, 34+lift), _p(31, 33+lift), 0.45, hair[1])
	_line(_p(32, 33+lift), _p(35, 34+lift), 0.45, hair[2])
	_line(_p(62, 35+lift), _p(65, 36+lift), 0.45, hair[1])
	_curve(_p(45, 30), _p(44, 32), _p(45, 34), _p(44, 36), 0.55, skin[2])

func _nose() -> void:
	if _missing("nose"):
		_wound(_p(50, 51), 3)
		return
	if female and young:
		# A longer exposed philtrum and fine crooked bridge change the face itself.
		_poly_ramp(PackedVector2Array([_p(47, 34), _p(50, 35), _p(50, 42),
			_p(53, 49), _p(52, 52), _p(49, 53), _p(46, 51),
			_p(46, 47), _p(46, 40)]), skin, -0.12)
		_curve(_p(48, 36), _p(47, 41), _p(48, 46), _p(50, 49), 1.0, skin[5])
		_oval(_p(50, 50.5), Vector2(3.1*sx, 2.7), skin, 0.02)
		_line(_p(47, 52), _p(48, 52.5), 0.65, skin[0])
		_line(_p(52, 52), _p(53, 51), 0.65, skin[0])
		_pxv(_p(49, 49), skin[6])
		_line(_p(49, 54), _p(50, 56), 0.5, skin[2])
		return
	var drop := (3.5 if female else 3.0) if elder else (0.0 if young else 1.5)
	# Pear-shaped drooping nose, with a narrow bridge and a weighted soft tip.
	_curve(_p(51, 39), _p(53, 44), _p(58, 52+drop), _p(53, 56+drop), 2.0, skin[1])
	var poly := PackedVector2Array([_p(46, 34), _p(50, 35), _p(51, 42),
		_p(53, 48), _p(55, 52+drop), _p(54, 55+drop), _p(51, 57+drop),
		_p(47, 55+drop), _p(44, 52), _p(45, 46), _p(45, 39)])
	_poly_ramp(poly, skin, -0.16)
	_curve(_p(48, 36), _p(46, 41), _p(48, 48), _p(51, 53+drop), 1.7, skin[4])
	_curve(_p(47, 37), _p(46, 42), _p(47, 47), _p(49, 50+drop), 0.8, skin[5])
	_curve(_p(46, 39), _p(46, 42), _p(46, 44), _p(47, 46), 0.45, skin[6])
	_oval(_p(50, 53+drop), Vector2((3.7 if female else 4.2)*sx, 4.1), skin, -0.03)
	_line(_p(46, 54+drop), _p(48, 55+drop), 0.7, skin[0])
	_line(_p(53, 55+drop), _p(55, 53+drop), 0.7, skin[0])
	_line(_p(49, 51+drop), _p(50, 51+drop), 0.5, skin[6])

func _mouth() -> void:
	if _missing("jaw"):
		return
	if _missing("mouth"):
		_wound(_p(51, 60), 4)
		return
	var y := (58.5 if young else 62.0) if female else 60.5
	var lip := skin[4].lerp(Color("#aa8a72") if female else Color("#958365"), 0.35)
	var left := (37.0 if young else 39.0) if female else 34.0
	var right := (63.0 if young else 61.0) if female else 66.0
	var tension := -0.8 if young and not female else (1.0 if elder else 0.0)
	# An inset upper lip meets the rising front of the lower muzzle.
	_curve(_p(left+2, y-1), _p(45, y-2), _p(55, y-1), _p(right-1, y), 1.1, skin[2])
	_curve(_p(left, y+1.5+tension), _p(44, y+1), _p(59, y+1), _p(right+2, y-0.6), 0.85, skin[0])
	# The lower lip rolls forward and up, beyond the upper lip at the far corner.
	_curve(_p(left+5, y+3), _p(49, y+4), _p(64, y+2.5), _p(right+5, y-0.3), 1.25 if not female else 0.95, lip)
	_curve(_p(49, y+2.5), _p(54, y+2.3), _p(61, y+1.4), _p(right+3, y-0.6), 0.6, skin[5])
	_curve(_p(right+5, y), _p(right+7, y+2), _p(right+5, y+4), _p(right+3, y+5), 0.8, skin[2])
	# A short central crease separates the chin; shadow turns under it into the neck.
	_curve(_p(51, 66.5), _p(53, 67.5), _p(57, 67.0), _p(59, 66), 0.5, skin[2])
	_curve(_p(46, 73), _p(53, 76), _p(62, 73), _p(65, 70), 1.2, skin[0])

func _mottles() -> void:
	for i in range(33 if elder else 26):
		var center := Vector2(rng.randf_range(23, 71), rng.randf_range(17, 69))
		if not _inside(center) or (_missing("jaw") and center.y > 56):
			continue
		var eye_near := ((center-Vector2(34, 39))/Vector2(8, 6)).length_squared() < 1
		var eye_far := ((center-Vector2(59, 40))/Vector2(7, 6)).length_squared() < 1
		var nose_area := center.x > 42 and center.x < 58 and center.y > 32 and center.y < 59
		var mouth_area := center.x > 32 and center.x < 69 and center.y > 57 and center.y < 65
		if eye_near or eye_far or nose_area or mouth_area:
			continue
		var c := _p(center.x, center.y)
		var radius := Vector2(rng.randf_range(1.4, 3.4), rng.randf_range(1.0, 2.6))
		for y in range(int(c.y-radius.y), int(c.y+radius.y)+1):
			for x in range(int(c.x-radius.x), int(c.x+radius.x)+1):
				var dist := ((Vector2(x, y)-c)/radius).length_squared()
				if dist > 1 or not _inside(_local(Vector2(x, y))) or not _opaque(x, y):
					continue
				var old := im.get_pixel(x, y)
				var tint := Color("#768966") if i % 2 == 0 else Color("#686e58")
				_px(x, y, old.lerp(tint, 0.12 if young else (0.18 if elder else 0.16)))

func _warts() -> void:
	var index := 0
	for q in [Vector2(25, 32), Vector2(25, 53), Vector2(67, 27),
		Vector2(71, 58), Vector2(37, 22), Vector2(60, 68)]:
		var local := Vector2(q.x+float(posmod(seed, 3)-1), q.y)
		var p := _p(local.x, local.y)
		if _missing("jaw") and q.y > 57:
			continue
		if not _inside(local):
			continue
		var radius := 1.7 if index == 2 else (1.15 if index in [1, 5] else 1.3)
		_oval(p, Vector2(radius, radius*0.85), skin, -0.05)
		_pxv(p+Vector2(-1, -1), skin[5])
		_pxv(p+Vector2(1, 1), skin[2])
		index += 1

func _age_marks() -> void:
	if not elder:
		if not young:
			_curve(_p(32, 26), _p(37, 24), _p(44, 26), _p(47, 27), 0.55, skin[3])
		return
	for k in range(2):
		var y := 24.0+k*4
		_curve(_p(31, y), _p(36, y-2), _p(44, y), _p(52, y+1), 0.55, skin[2])
		_curve(_p(32, y-1), _p(38, y-2), _p(44, y-1), _p(49, y), 0.45, skin[5])
	for side in [0, 1]:
		var x := 27.0 if side == 0 else 65.0
		var sign_x := -1.0 if side == 0 else 1.0
		_line(_p(x, 40), _p(x+sign_x*4, 38), 0.55, skin[1])
		_line(_p(x, 42), _p(x+sign_x*3, 44), 0.55, skin[2])
	if not _missing("jaw"):
		_curve(_p(42, 53), _p(38, 54), _p(38, 58), _p(36, 62), 0.55, skin[2])
		_curve(_p(59, 54), _p(63, 56), _p(64, 59), _p(66, 62), 0.55, skin[2])
		_curve(_p(39, 64), _p(40, 67), _p(42, 69), _p(44, 70), 0.55, skin[2])

func _back_hair() -> void:
	if not female:
		return
	var length := 70.0 if elder else 65.0
	# Thin unequal bundles leave gaps behind the ears and shoulders.
	_lock(_p(25, 28), _p(20, 34), _p(20, 44), _p(18, 52), 2.0, hair)
	_lock(_p(21, 42), _p(19, 47), _p(22, 55), _p(19, length-3), 1.6, hair)
	_lock(_p(24, 48), _p(21, 53), _p(23, 59), _p(22, length), 1.35, hair)
	_lock(_p(67, 28), _p(72, 34), _p(73, 43), _p(74, 49), 2.1, hair)
	_lock(_p(73, 43), _p(75, 48), _p(73, 56), _p(76, length-2), 1.8, hair)
	_lock(_p(71, 51), _p(73, 57), _p(72, 63), _p(74, length+3), 1.4, hair)

func _front_hair() -> void:
	# Short changes of direction replace a continuous hook around the scalp.
	if female:
		var top := 19.0 if elder else 15.0
		if set_id == 0 or elder:
			_lock(_p(26, 26), _p(25, 23), _p(26, top+5), _p(28, top+3), 1.5, hair)
			_lock(_p(33, top+4), _p(33, top+1), _p(35, top-1), _p(38, top-2), 1.5, hair)
		else:
			_lock(_p(65, 25), _p(65, 20), _p(60, 16), _p(57, 16), 1.8, hair)
		_lock(_p(23, 29), _p(20, 34), _p(22, 38), _p(20, 42), 1.7, hair)
		_lock(_p(22, 46), _p(21, 50), _p(24, 54), _p(22, 58), 1.4, hair)
		_lock(_p(67, 25), _p(71, 29), _p(70, 35), _p(73, 39), 1.8, hair)
		_lock(_p(71, 43), _p(70, 47), _p(73, 51), _p(72, 55), 1.4, hair)
	else:
		var top := 18.0 if elder else 13.0
		_lock(_p(25, 28), _p(24, 26), _p(24, 24), _p(25, 22), 1.25, hair)
		_lock(_p(29, top+6), _p(28, top+4), _p(29, top+1), _p(31, top-1), 1.5, hair)
		if young:
			_lock(_p(35, 16), _p(35, 13), _p(37, 11), _p(40, 10), 1.5, hair)
		_lock(_p(66, 23), _p(67, 24), _p(67, 27), _p(69, 29), 1.15, hair)
		_lock(_p(24, 32), _p(22, 34), _p(23, 36), _p(22, 38), 1.05, hair)

func _beard() -> void:
	if not beard_on or _missing("jaw") or _missing("mouth"):
		return
	if beard_style == 6:
		_lock(_p(47, 57), _p(41, 56), _p(39, 58), _p(36, 60), 1.3, beard)
		_lock(_p(53, 57), _p(57, 56), _p(61, 57), _p(64, 59), 1.2, beard)
		return
	var length := 11.0 if elder else 7.0
	if beard_style in [2, 3, 4, 5]:
		length += 5
	if beard_style == 7:
		length = 2
	if beard_style == 1:
		length += 2
	var roots := [Vector2(40, 64), Vector2(63, 65), Vector2(45, 66),
		Vector2(58, 66), Vector2(50, 67), Vector2(45, 71),
		Vector2(59, 72), Vector2(51, 74), Vector2(55, 76)]
	var tips := [Vector2(42, 70), Vector2(62, 71), Vector2(46, 73),
		Vector2(60, 74), Vector2(52, 74), Vector2(47, 78),
		Vector2(59, 79), Vector2(52, 81), Vector2(56, 80)]
	if beard_style == 1:
		roots = [Vector2(48, 64.5), Vector2(56, 65), Vector2(52, 67)]
		tips = [Vector2(49, 71), Vector2(57, 72), Vector2(54, 75)]
	for i in range(roots.size()):
		var root: Vector2 = roots[i]
		var factor := clampf(length/12.0, 0.15, 1.0)
		var reach: Vector2 = (tips[i]-root)*factor
		if beard_style != 1:
			root.y = 65.0+(root.y-65.0)*factor
		var tip := root+reach
		_beard_clump(_p(root.x, root.y), _p(tip.x, tip.y),
			(3.7 if elder else 2.4)-float(i%3)*0.25, i)
	# Unequal single hairs bridge skin and clumps without a solid top edge.
	for i in range(15):
		var x := (47.5+i*0.65) if beard_style == 1 else (39.0+i*1.8)
		var y := 65.0 + float(posmod(i*7+seed, 5))*0.55
		var p := _p(x, y)
		if _opaque(int(p.x), int(p.y)):
			var col := im.get_pixel(int(p.x), int(p.y)).lerp(beard[2+i%2], 0.42)
			_line(p, p+Vector2(0.3, 1.1), 0.45, col)
	if beard_style != 1:
		_beard_clump(_p(31, 58), _p(36, 65), 1.6, 1)
		_beard_clump(_p(68, 59), _p(66, 66), 1.5, 0)

func _beard_clump(root: Vector2, tip: Vector2, width: float, index: int) -> void:
	var segment := tip-root
	var along := segment.normalized()
	var side := Vector2(-along.y, along.x)
	var lo := root.min(tip)-Vector2.ONE*width
	var hi := root.max(tip)+Vector2.ONE*width
	for y in range(maxi(0, int(lo.y)), mini(SIZE, int(hi.y)+1)):
		for x in range(maxi(0, int(lo.x)), mini(SIZE, int(hi.x)+1)):
			var p := Vector2(x+0.5, y+0.5)
			var raw_t := (p-root).dot(segment)/maxf(0.1, segment.length_squared())
			var t := clampf(raw_t, 0.0, 1.0)
			var radius := width*(0.50+0.28*sin(t*PI))*(1.0-t*0.12)
			var center := root.lerp(tip, t)
			if p.distance_to(center) > radius:
				continue
			var across := (p-center).dot(side)/radius
			var v := t*0.85-0.2
			var normal := Vector3(side.x*across+along.x*v, side.y*across+along.y*v,
				sqrt(maxf(0.02, 1.0-across*across-v*v))).normalized()
			var lit := 0.18+maxf(0.0, normal.dot(LIGHT))*0.56-float(index%2)*0.05
			var col := beard[clampi(int(lit*7), 1, 5)]
			var blend := smoothstep(-0.08, 0.32, raw_t)
			if _opaque(x, y):
				col = im.get_pixel(x, y).lerp(col, blend)
			_px(x, y, col)
	var start := root.lerp(tip, 0.35)+side*width*0.15
	_line(start, start+along*1.1, 0.45, beard[4])

func _tusks() -> void:
	if _missing("jaw") or _missing("mouth"):
		return
	var length := (15.5 if young else (13.5 if elder else 16.0)) * (0.95 if female else 1.0)
	var root_y := 61.0 if young and female else 63.0
	_tusk(38 if female else 36, root_y, -1.0, length, false)
	_tusk(64 if female else 66, root_y-1, 1.0, length*(0.85 if elder else 0.94), elder)

func _tusk(x: float, y: float, side: float, length: float, chipped: bool) -> void:
	var a := _p(x, y)
	var b := _p(x+side*3.1, y-length)
	var ivory := _ramp(Color("#d9cca2"), Color("#796f4b"), Color("#fff6d5"))
	var pts := PackedVector2Array([_p(x-3.2, y), _p(x+3.2, y),
		_p(x+side*2.0+2.4, y-length*0.35), _p(x+side*4.1+1.2, y-length*0.72),
		b+Vector2(0.5, 0), b+Vector2(-0.4, 0.2),
		_p(x+side*3.2-1.3, y-length*0.68), _p(x+side*0.4-2.8, y-length*0.28)])
	_poly_ramp(pts, ivory, 0.10)
	_curve(a+Vector2(-1.2, -0.4), _p(x+side-1.2, y-length*0.4), _p(x+side*3-0.7, y-length*0.8), b, 0.65, ivory[6])
	# The fleshy socket overlaps the ivory root at the lower lip.
	_curve(_p(x-3.1, y-0.5), _p(x-2, y+1.1), _p(x+1, y+1.5), _p(x+3.1, y), 0.85, skin[2])
	_line(_p(x-1.5, y+0.4), _p(x+1.5, y+0.7), 0.5, skin[4])
	if chipped:
		_pxv(b, skin[2])
		_pxv(b+Vector2(0, 1), ivory[2])

func _armoured() -> bool:
	var name := (String(body.get("sprite", ""))+" "+String(body.get("tid", ""))).to_lower()
	for token in ARMOUR:
		if token in name:
			return true
	return false

func _metal(item: Dictionary) -> Array[Color]:
	var material: Dictionary = FigurePainter.metal(String(item.get("mat", "iron")), int(item.get("q", 0)))
	return [material["dark"].darkened(0.2), material["dark"],
		material["dark"].lerp(material["base"], 0.55), material["base"],
		material["base"].lerp(material["light"], 0.6), material["light"], material["shine"]]

func _armour() -> void:
	var metal := _metal(body)
	var shift := 4.0 if female else 0.0
	var drop := 2.0 if elder else 0.0
	var left := PackedVector2Array([Vector2(6+shift, 80+drop), Vector2(9+shift, 75+drop),
		Vector2(17+shift, 71+drop), Vector2(24+shift, 72+drop), Vector2(30+shift, 77+drop),
		Vector2(34+shift, 85+drop), Vector2(31+shift, 91+drop), Vector2(25+shift, 94+drop),
		Vector2(8+shift, 91+drop), Vector2(5+shift, 86+drop)])
	_plate(left, metal, Vector2(19+shift, 81+drop), Vector2(17, 16), -0.03)
	_curve(Vector2(8+shift, 79+drop), Vector2(13+shift, 73+drop), Vector2(23+shift, 72+drop), Vector2(29+shift, 78+drop), 0.7, metal[5])
	_curve(Vector2(8+shift, 87+drop), Vector2(16+shift, 93+drop), Vector2(27+shift, 94+drop), Vector2(31+shift, 87+drop), 0.9, metal[1])
	_curve(Vector2(10+shift, 87+drop), Vector2(16+shift, 91+drop), Vector2(22+shift, 92+drop), Vector2(26+shift, 90+drop), 0.55, metal[4])
	_plate(PackedVector2Array([Vector2(76, 73-drop), Vector2(84, 76-drop),
		Vector2(91, 84), Vector2(92, 91), Vector2(83, 90), Vector2(76, 83)]),
		metal, Vector2(80, 80), Vector2(14, 17), -0.17)
	_curve(Vector2(79, 75-drop), Vector2(85, 77), Vector2(87, 82), Vector2(88, 85), 0.6, metal[4])
	_plate(PackedVector2Array([Vector2(33, 83+drop), Vector2(45, 80+drop), Vector2(61, 79+drop),
		Vector2(74, 83+drop), Vector2(80, 90), Vector2(82, 96), Vector2(29, 96)]),
		metal, Vector2(53, 90+drop), Vector2(32, 19), -0.13)
	_curve(Vector2(35, 84+drop), Vector2(44, 80+drop), Vector2(57, 79+drop), Vector2(66, 82+drop), 0.7, metal[5])
	_curve(Vector2(55, 84+drop), Vector2(59, 86+drop), Vector2(62, 91), Vector2(63, 96), 0.8, metal[1])
	_curve(Vector2(54, 85+drop), Vector2(57, 88), Vector2(59, 92), Vector2(59, 94), 0.6, metal[4])
	var kind := String(body.get("sprite", ""))
	if kind in ["mail", "byrnie", "scale", "lamellar"]:
		for y in range(86, 96, 3):
			for x in range(35+posmod(y, 2), 73, 4):
				_line(Vector2(x, y), Vector2(x+2, y+1), 0.5, metal[1])
				_px(x, y-1, metal[4])
	else:
		_line(Vector2(39, 88), Vector2(43, 86), 0.6, metal[1])
		_line(Vector2(65, 91), Vector2(72, 89), 0.5, metal[2])
	_curve(Vector2(27, 75), Vector2(38, 81), Vector2(56, 90), Vector2(68, 96), 2.2, cloth[0])
	_curve(Vector2(26, 75), Vector2(37, 81), Vector2(55, 90), Vector2(67, 96), 1.1, cloth[3])
	for c in [Vector2(12+shift, 80+drop), Vector2(27+shift, 84+drop), Vector2(40, 86+drop), Vector2(70, 88+drop)]:
		_oval(c, Vector2(1.3, 1.3), metal, -0.05)
		_pxv(c-Vector2(0.5, 0.5), trim.lightened(0.2))

func _headwear() -> void:
	var name := (String(helm.get("sprite", ""))+" "+String(helm.get("tid", ""))).strip_edges().to_lower()
	if name == "":
		return
	var ramp := _metal(helm)
	if "crown" in name or "circlet" in name:
		_curve(_p(24, 26), _p(35, 28), _p(54, 29), _p(66, 25), 1.3, ramp[4])
		for i in range(5):
			var x := 28.0+i*8
			_line(_p(x, 27), _p(x, 21-(i%2)*3), 1.0, ramp[4])
			_pxv(_p(x, 20-(i%2)*3), trim)
		return
	var closed := "great" in name or "closed" in name or "barrel" in name or "frog" in name
	var hood := "hood" in name or "coif" in name
	if hood:
		_curve(_p(23, 41), _p(12, 3), _p(74, -1), _p(71, 43), 3.8, ramp[2])
		_curve(_p(24, 39), _p(17, 8), _p(70, 4), _p(70, 41), 0.8, ramp[5])
		return
	var bottom := 61.0 if closed else 30.0
	_poly_ramp(PackedVector2Array([_p(19, bottom), _p(19, 25), _p(24, 14),
		_p(36, 8), _p(53, 8), _p(66, 15), _p(71, 28), _p(73, bottom)]), ramp, -0.03)
	_curve(_p(22, 29), _p(35, 31), _p(56, 32), _p(70, 29), 1.0, ramp[1])
	_curve(_p(25, 28), _p(36, 29), _p(56, 30), _p(68, 28), 0.7, ramp[5])
	if closed:
		_line(_p(27, 39), _p(41, 40), 1.2, INK)
		_line(_p(54, 41), _p(65, 41), 1.1, INK)
		for x in range(41, 59, 4):
			_line(_p(x, 50), _p(x+1, 55), 0.6, ramp[0])
	elif "kettle" in name:
		_curve(_p(13, 31), _p(32, 34), _p(58, 35), _p(79, 30), 1.5, ramp[3])
	elif "nasal" in name:
		_line(_p(48, 29), _p(51, 50), 1.5, ramp[3])
		_line(_p(47, 29), _p(50, 49), 0.5, ramp[5])

func _px(x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	color.a = 1.0
	im.set_pixel(x, y, color)

func _pxv(p: Vector2, color: Color) -> void:
	_px(int(round(p.x)), int(round(p.y)), color)

func _opaque(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE and im.get_pixel(x, y).a > 0.5

func _oval(center: Vector2, radius: Vector2, ramp: Array[Color], bias: float = 0.0) -> void:
	for y in range(maxi(0, int(center.y-radius.y)), mini(SIZE, int(center.y+radius.y)+1)):
		for x in range(maxi(0, int(center.x-radius.x)), mini(SIZE, int(center.x+radius.x)+1)):
			var p := (Vector2(x+0.5, y+0.5)-center)/radius
			if p.length_squared() > 1:
				continue
			var normal := Vector3(p.x, p.y, sqrt(maxf(0.0, 1-p.length_squared())))
			var lit := 0.24+bias+maxf(0.0, normal.dot(LIGHT))*0.68
			_px(x, y, ramp[clampi(int(lit*7), 0, 6)])

func _poly_ramp(points: PackedVector2Array, ramp: Array[Color], bias: float) -> void:
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	var size := (hi-lo).max(Vector2.ONE)
	for y in range(maxi(0, int(lo.y)), mini(SIZE, int(hi.y)+1)):
		for x in range(maxi(0, int(lo.x)), mini(SIZE, int(hi.x)+1)):
			if not Geometry2D.is_point_in_polygon(Vector2(x+0.5, y+0.5), points):
				continue
			var uv := (Vector2(x, y)-lo)/size
			var lit := 0.93-uv.x*0.42-uv.y*0.29+bias
			_px(x, y, ramp[clampi(int(lit*7), 0, 6)])

func _plate(points: PackedVector2Array, ramp: Array[Color], center: Vector2, radius: Vector2, bias: float) -> void:
	# Domed normals bend the light around each plate, including its rolled edge.
	var lo := points[0]
	var hi := points[0]
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(0, int(lo.y)), mini(SIZE, int(hi.y)+1)):
		for x in range(maxi(0, int(lo.x)), mini(SIZE, int(hi.x)+1)):
			var p := Vector2(x+0.5, y+0.5)
			if not Geometry2D.is_point_in_polygon(p, points):
				continue
			var uv := (p-center)/radius
			var normal := Vector3(uv.x, uv.y, sqrt(maxf(0.08, 1.0-uv.length_squared()))).normalized()
			var lit := 0.22+bias+maxf(0.0, normal.dot(LIGHT))*0.72
			_px(x, y, ramp[clampi(int(lit*7), 0, 6)])

func _line(a: Vector2, b: Vector2, radius: float, color: Color) -> void:
	var lo := a.min(b)-Vector2.ONE*radius
	var hi := a.max(b)+Vector2.ONE*radius
	var segment := b-a
	var len2 := maxf(0.01, segment.length_squared())
	for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y))+1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x))+1)):
			var p := Vector2(x+0.5, y+0.5)
			var t := clampf((p-a).dot(segment)/len2, 0.0, 1.0)
			if p.distance_squared_to(a+segment*t) <= radius*radius:
				_px(x, y, color)

func _curve(a: Vector2, b: Vector2, c: Vector2, d: Vector2, radius: float, color: Color) -> void:
	var prev := a
	for i in range(1, 25):
		var p := a.bezier_interpolate(b, c, d, float(i)/24.0)
		_line(prev, p, radius, color)
		prev = p

func _lock(a: Vector2, b: Vector2, c: Vector2, d: Vector2, width: float, ramp: Array[Color]) -> void:
	# A narrow root swells once, then tapers to a ragged directional tip.
	var phase := fposmod(a.x*0.19+a.y*0.31+d.x*0.07, 1.0)
	for pass_i in range(3):
		var prev := a
		for i in range(1, 23):
			var t := float(i)/22.0
			var p := a.bezier_interpolate(b, c, d, t)
			var direction := (p-prev).normalized()
			var side := Vector2(-direction.y, direction.x)
			if side.dot(Vector2(LIGHT.x, LIGHT.y)) < 0.0:
				side = -side
			var taper := (0.62+0.38*sin(minf(1.0, t*2.0)*PI)) * pow(1.0-t, 0.8)
			var radius := maxf(0.42, width*taper)
			if pass_i == 0:
				_line(prev, p, radius, ramp[1])
			elif pass_i == 1 and t > 0.10 and t < 0.88:
				_line(prev+side*radius*0.25, p+side*radius*0.25, radius*0.58, ramp[3])
			elif pass_i == 2 and t > 0.18+phase*0.12 and t < 0.46+phase*0.25:
				_line(prev+side*radius*0.45, p+side*radius*0.45, minf(0.5, radius*0.28), ramp[5])
			prev = p

func _wound(center: Vector2, radius: float) -> void:
	_oval(center, Vector2.ONE*radius, _ramp(BLOOD, Color("#362923"), Color("#af6c4e")), -0.22)

func _outline() -> void:
	var pixels: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if not _opaque(x, y):
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q := Vector2i(x, y)+Vector2i(d)
				if q.x < 0 or q.y < 0 or q.x >= SIZE or q.y >= SIZE:
					continue
				if not _opaque(q.x, q.y):
					pixels.append(q)
	for q in pixels:
		_px(q.x, q.y, INK)
