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
	Vector3(40, 44, 24), Vector3(46, 45, 23), Vector3(51, 47, 25),
	Vector3(57, 49, 28), Vector3(62, 50, 28), Vector3(67, 51, 25),
	Vector3(71, 51, 19), Vector3(74, 51, 11), Vector3(75, 51, 0.4),
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
	sx = (0.93 if female else 1.0) * (0.94 if young else 1.0)
	sy = 0.95 if young else (1.02 if elder else 1.0)
	dy = 4.0 if young else (1.0 if elder else 0.0)
	tilt = 0.055 if elder else (-0.025 if female else 0.015)
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
		var lower := smoothstep(45.0, 65.0, y)
		row.y *= 1.0 - lower * (0.09 if female else (0.06 if young else 0.0))
		if female:
			row.x -= lower * 0.7
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
	z += 4.0 * _bump(q, Vector2(42, 25), Vector2(19, 13))
	z += 4.5 * _bump(q, Vector2(30, 47), Vector2(10, 8))
	z += 3.0 * _bump(q, Vector2(64, 47), Vector2(8, 8))
	z -= (2.8 if elder else 1.8) * _bump(q, Vector2(33, 54), Vector2(8, 5))
	z -= 2.0 * _bump(q, Vector2(65, 54), Vector2(6, 5))
	z += 3.0 * _bump(q, Vector2(48, 55), Vector2(15, 6))
	z += 7.5 * _bump(q, Vector2(52, 66), Vector2(21, 10))
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
			lit -= smoothstep(65.0, 77.0, q.y) * 0.13
			_px(x, y, skin[clampi(int(lit * 7.0), 0, 6)])
	if _missing("jaw"):
		_wound(_p(50, 58), 7)

func _shoulders() -> void:
	var hunch := -4.0 if elder else (2.0 if young else 0.0)
	var pts := PackedVector2Array([Vector2(0, 96), Vector2(0, 80),
		Vector2(5, 71+hunch), Vector2(12, 64+hunch), Vector2(23, 59+hunch),
		Vector2(33, 63+hunch), Vector2(46, 72), Vector2(58, 72),
		Vector2(68, 65), Vector2(77, 65), Vector2(87, 71),
		Vector2(93, 81), Vector2(96, 88), Vector2(96, 96)])
	if female:
		for i in pts.size():
			pts[i].x = 48 + (pts[i].x - 48) * 0.94
			pts[i].y += 1
	_poly_ramp(pts, cloth, 0.0)
	# Broad curved folds follow the raised shoulder and sag across the chest.
	_curve(Vector2(5, 78+hunch), Vector2(12, 72+hunch), Vector2(23, 67+hunch), Vector2(34, 78), 1.4, cloth[4])
	_curve(Vector2(6, 81+hunch), Vector2(19, 73+hunch), Vector2(24, 76), Vector2(36, 84), 1.2, cloth[1])
	_curve(Vector2(12, 94), Vector2(26, 79), Vector2(36, 79), Vector2(51, 86), 1.0, cloth[4])
	_curve(Vector2(18, 96), Vector2(33, 84), Vector2(43, 83), Vector2(61, 91), 1.6, cloth[1])
	_curve(Vector2(70, 75), Vector2(77, 77), Vector2(86, 84), Vector2(87, 94), 1.5, cloth[1])
	_curve(Vector2(74, 75), Vector2(82, 80), Vector2(87, 86), Vector2(89, 92), 0.7, cloth[4])
	if female:
		_curve(Vector2(72, 73), Vector2(61, 83), Vector2(38, 84), Vector2(28, 96), 3.2, cloth[2])
		_curve(Vector2(72, 72), Vector2(60, 82), Vector2(39, 83), Vector2(28, 95), 1.0, cloth[5])
	# Ragged hide edge: clumps, with no checkerboard texture.
	var hide := _ramp(cloth[5], Color("#332b22"), Color("#d5c59b"))
	_curve(Vector2(11, 70+hunch), Vector2(21, 63+hunch), Vector2(29, 67), Vector2(38, 76), 3.5, hide[2])
	for i in range(7):
		var a := Vector2(13+i*3, 68+hunch+absf(float(i-2))*1.0)
		_curve(a, a+Vector2(1, -1), a+Vector2(3, 3), a+Vector2(4, 5), 1.5, hide[4 if i < 4 else 2])
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
	_oval(_p(49, 70), Vector2(18*sx, 10), skin, -0.19)
	_curve(_p(34, 71), _p(42, 77), _p(54, 79), _p(64, 72), 1.5, skin[1])
	_curve(_p(39, 76), _p(45, 79), _p(54, 80), _p(60, 77), 0.6, skin[4])

func _ear(near: bool) -> void:
	var id := "ear_r" if near else "ear_l"
	var x := 21.0 if near else 71.0
	var c := _p(x, 44)
	if _missing(id):
		_wound(c, 2)
		return
	var sign_x := -1.0 if near else 1.0
	_oval(c, Vector2(6, 10 if elder else 8), skin, -0.14 if near else -0.30)
	_curve(c+Vector2(-sign_x*2, -5), c+Vector2(sign_x*6, -9), c+Vector2(sign_x*5, 3), c+Vector2(sign_x, 7), 1.2, skin[1])
	_curve(c+Vector2(-sign_x, -4), c+Vector2(sign_x*3, -6), c+Vector2(sign_x*2, 0), c+Vector2(0, 3), 0.8, skin[4 if near else 2])

func _cheeks() -> void:
	# Small plane accents, rather than lines boxing in the entire face.
	_curve(_p(25, 45), _p(28, 43), _p(32, 44), _p(35, 46), 1.0, skin[5])
	_curve(_p(60, 46), _p(64, 44), _p(67, 46), _p(68, 49), 0.8, skin[3])
	if not young and not _missing("jaw"):
		_curve(_p(32, 51), _p(30, 54), _p(33, 57), _p(35, 59), 0.7, skin[2])
		_curve(_p(65, 51), _p(68, 54), _p(68, 57), _p(66, 59), 0.8, skin[1])

func _eye(near: bool) -> void:
	var eye_x := (35.0 if near else 58.0) if female else (34.0 if near else 59.0)
	var c := _p(eye_x, 39 if near else 40)
	var id := "eye_r" if near else "eye_l"
	var ex := 5.6 if near else 4.8
	_oval(c+Vector2(0, 0.5), Vector2(ex+1.6, 4.1 if elder else 3.6), skin, -0.32)
	_curve(c+Vector2(-ex, 3), c+Vector2(-1, 6), c+Vector2(3, 5), c+Vector2(ex+1, 2), 0.8, skin[3 if near else 2])
	if _missing(id):
		_wound(c, 2)
		return
	if dead:
		_line(c-Vector2(ex-1, 0), c+Vector2(ex-1, 1), 0.7, skin[0])
		return
	var x := int(round(c.x))
	var y := int(round(c.y))
	var wide := 5 if near else 4
	var whites := Color("#efe9d5") if near else Color("#c9d0ba")
	var upper := -2 if young or female else -1
	for yy in range(upper, 2):
		for xx in range(-wide, wide+1):
			if absi(xx) == wide and yy != 0:
				continue
			if yy == -2 and absi(xx) > wide-2:
				continue
			if yy == -1 and xx < -wide+2:
				continue
			_px(x+xx, y+yy, whites.darkened(0.12 if yy == -1 else 0.0))
	var ix := x + (0 if young else 1) + (posmod(seed, 3)-1)
	for yy in range(upper, 2):
		_px(ix-2, y+yy, Color("#a16a25"))
		_px(ix-1, y+yy, Color("#d8aa43"))
		_px(ix, y+yy, Color("#edbf60") if yy != upper else Color("#99772e"))
		_px(ix+1, y+yy, Color("#6f602d"))
	_px(ix, y, Color("#263026"))
	_px(ix, y+1, Color("#263026"))
	_px(ix, y-1, Color("#fff6d7"))
	_curve(c+Vector2(-ex, -0.4), c+Vector2(-2, -2), c+Vector2(2, -2.2), c+Vector2(ex, -0.2), 0.65, skin[0])
	_line(c+Vector2(-ex+1, 2), c+Vector2(ex-1, 2), 0.5, skin[4 if near else 2])

func _brows() -> void:
	var thickness := 2.0 if female else (2.7 if young else 3.3)
	var lift := -1.0 if young or female else (0.7 if elder else 0.0)
	var a := _p(25, 36+lift)
	var b := _p(29, 31+lift)
	var c := _p(38, 32+lift)
	var d := _p(43, 36+lift)
	_curve(a+Vector2(0, 1), b+Vector2(0, 1), c+Vector2(0, 1), d+Vector2(0, 1), thickness, skin[1])
	_curve(a, b, c, d, thickness*0.82, skin[4])
	_curve(a+Vector2(1, -0.5), b, c-Vector2(1, 1), d-Vector2(1, 1), 0.75, skin[5])
	_curve(_p(53, 36+lift), _p(56, 32+lift), _p(64, 33+lift), _p(67, 38+lift), thickness, skin[2])
	_curve(_p(54, 35+lift), _p(57, 32+lift), _p(63, 33+lift), _p(66, 36+lift), thickness*0.63, skin[4])
	# Sparse coarse eyebrow hairs; the ridge remains unmistakably skin.
	_line(_p(28, 34+lift), _p(31, 33+lift), 0.45, hair[1])
	_line(_p(32, 33+lift), _p(35, 34+lift), 0.45, hair[2])
	_line(_p(62, 35+lift), _p(65, 36+lift), 0.45, hair[1])
	_curve(_p(45, 30), _p(44, 32), _p(45, 34), _p(44, 36), 0.55, skin[2])

func _nose() -> void:
	if _missing("nose"):
		_wound(_p(50, 51), 3)
		return
	var drop := 3.0 if elder else (0.0 if young else 1.5)
	# Pear-shaped drooping nose, with a narrow bridge and a weighted soft tip.
	_curve(_p(51, 39), _p(53, 44), _p(58, 52+drop), _p(53, 56+drop), 2.0, skin[1])
	var poly := PackedVector2Array([_p(46, 34), _p(50, 35), _p(51, 42),
		_p(53, 48), _p(55, 52+drop), _p(54, 55+drop), _p(51, 57+drop),
		_p(47, 55+drop), _p(44, 52), _p(45, 46), _p(45, 39)])
	_poly_ramp(poly, skin, 0.0)
	_curve(_p(47, 36), _p(46, 43), _p(48, 47), _p(49, 52+drop), 1.4, skin[5])
	_curve(_p(46, 38), _p(46, 43), _p(46, 46), _p(47, 48), 0.55, skin[6])
	_oval(_p(50, 53+drop), Vector2(4.2*sx, 4.1), skin, 0.01)
	_line(_p(46, 54+drop), _p(48, 55+drop), 0.7, skin[0])
	_line(_p(53, 55+drop), _p(55, 53+drop), 0.7, skin[0])
	_line(_p(49, 51+drop), _p(50, 51+drop), 0.5, skin[6])

func _mouth() -> void:
	if _missing("jaw"):
		return
	if _missing("mouth"):
		_wound(_p(51, 60), 4)
		return
	var y := 60.0 if not female else 59.5
	var lip := skin[3].lerp(Color("#8d7963") if female else Color("#84775d"), 0.45)
	var corner := -0.7 if young else (2.4 if elder else 1.0)
	_curve(_p(34, y+corner), _p(42, y), _p(56, y), _p(67, y+corner-0.4), 1.6, skin[1])
	_curve(_p(35, y+corner), _p(44, y+0.1), _p(58, y-0.2), _p(66, y+corner-0.4), 0.7, Color("#3b3a2c"))
	# The lip projects beyond the upper muzzle and catches the light.
	_curve(_p(39, y+3), _p(46, y+5), _p(56, y+4), _p(63, y+2), 1.4, lip)
	_curve(_p(41, y+2.4), _p(48, y+3.8), _p(55, y+3), _p(60, y+2), 0.7, skin[5])
	_curve(_p(42, y+7), _p(48, y+8), _p(57, y+8), _p(61, y+5), 0.65, skin[2])
	if young:
		_pxv(_p(63, y-2), skin[2])

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
				_px(x, y, old.lerp(tint, 0.23))

func _warts() -> void:
	var index := 0
	for q in [Vector2(25, 32), Vector2(28, 50), Vector2(67, 27),
		Vector2(71, 58), Vector2(37, 22), Vector2(60, 68)]:
		var p := _p(q.x+float(posmod(seed, 3)-1), q.y)
		if _missing("jaw") and q.y > 57:
			continue
		var radius := 1.9 if index in [1, 2] else 1.35
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
		_curve(_p(42, 53), _p(38, 54), _p(38, 58), _p(36, 62), 0.7, skin[1])
		_curve(_p(59, 54), _p(63, 56), _p(64, 59), _p(66, 62), 0.7, skin[1])
		_curve(_p(42, 68), _p(47, 71), _p(58, 70), _p(63, 66), 0.6, skin[2])

func _back_hair() -> void:
	if not female:
		return
	var length := 70.0 if elder else 64.0
	_lock(_p(27, 26), _p(17, 35), _p(22, 53), _p(18, length), 2.8, hair)
	_lock(_p(66, 25), _p(76, 33), _p(73, 56), _p(79, length+3), 3.3, hair)
	_lock(_p(68, 31), _p(80, 45), _p(72, 60), _p(75, length+7), 2.1, hair)

func _front_hair() -> void:
	# Isolated swept locks leave most of the crown and forehead bare.
	if female:
		if not elder:
			if set_id == 0:
				_lock(_p(42, 15), _p(29, 9), _p(20, 21), _p(22, 38), 2.6, hair)
				_lock(_p(38, 15), _p(24, 14), _p(24, 27), _p(20, 44), 2.0, hair)
			else:
				_lock(_p(53, 14), _p(67, 12), _p(71, 25), _p(73, 39), 2.5, hair)
		_lock(_p(26, 24), _p(19, 33), _p(24, 44), _p(20, 51), 2.1, hair)
		_lock(_p(66, 24), _p(74, 33), _p(68, 46), _p(75, 55), 2.2, hair)
		_lock(_p(68, 34), _p(72, 43), _p(70, 56), _p(75, 65), 1.3, hair)
		if elder:
			_lock(_p(31, 18), _p(24, 17), _p(19, 26), _p(23, 35), 1.5, hair)
			_lock(_p(63, 17), _p(69, 18), _p(72, 23), _p(71, 30), 1.2, hair)
	else:
		var tip := 17.0 if elder else 10.0
		_lock(_p(27, 25), _p(22, 20), _p(25, tip), _p(32, tip-1), 1.7, hair)
		_lock(_p(30, 22), _p(26, 17), _p(30, tip-3), _p(37, tip-1), 1.5, hair)
		if young:
			_lock(_p(35, 18), _p(33, 13), _p(38, 8), _p(44, 10), 1.5, hair)
		_lock(_p(66, 26), _p(69, 22), _p(69, 17), _p(65, 15), 1.3, hair)
		_lock(_p(24, 32), _p(20, 35), _p(23, 39), _p(21, 43), 1.3, hair)

func _beard() -> void:
	if not beard_on or _missing("jaw") or _missing("mouth"):
		return
	if beard_style == 6:
		_lock(_p(47, 57), _p(41, 56), _p(39, 58), _p(36, 60), 1.3, beard)
		_lock(_p(53, 57), _p(57, 56), _p(61, 57), _p(64, 59), 1.2, beard)
		return
	var length := 8.0 if elder else 5.0
	if beard_style in [2, 3, 4, 5]:
		length += 5
	if beard_style == 7:
		length = 2
	if beard_style == 1:
		length += 3
		_poly_ramp(PackedVector2Array([_p(44, 68), _p(53, 68), _p(58, 71),
			_p(57, 76), _p(52, 80), _p(46, 76)]), beard, -0.05)
	if beard_style != 1 and beard_style != 7:
		_poly_ramp(PackedVector2Array([_p(37, 67), _p(45, 70), _p(60, 68),
			_p(64, 72), _p(62, 76+length*0.45), _p(57, 78+length*0.5),
			_p(50, 77+length*0.5), _p(43, 77+length*0.3), _p(39, 73)]), beard, -0.10)
	for i in range(5 if beard_style != 1 else 3):
		var x := 43.0+i*4 if beard_style != 1 else 47.0+i*3
		var root := 68.0-absf(x-51)*0.12
		var end_x := x+sin(float(i)*1.8+float(seed))*3.0
		var hang := length-absf(x-51)*0.23
		_lock(_p(x, root), _p(x-3, root+5), _p(end_x+3, root+hang-2), _p(end_x, root+hang+2), 3.4 if elder else 2.4, beard)
	if beard_style != 1:
		_lock(_p(30, 59), _p(29, 64), _p(33, 68), _p(36, 70), 1.7, beard)
		_lock(_p(71, 60), _p(72, 65), _p(67, 70), _p(65, 72), 1.6, beard)

func _tusks() -> void:
	if _missing("jaw") or _missing("mouth"):
		return
	var length := (8.0 if young else (13.0 if elder else 11.0)) * (0.83 if female else 1.0)
	_tusk(36, 62, -1.0, length, false)
	_tusk(65, 61, 1.0, length*(0.85 if elder else 0.94), elder)

func _tusk(x: float, y: float, side: float, length: float, chipped: bool) -> void:
	var a := _p(x, y)
	var b := _p(x+side*3.0, y-length)
	var ivory := _ramp(Color("#d9cca2"), Color("#796f4b"), Color("#fff6d5"))
	var pts := PackedVector2Array([a+Vector2(-2.5, 0), a+Vector2(2.5, 0),
		_p(x+side*2.7+1.2, y-length*0.58), b+Vector2(0.5, 0),
		b+Vector2(-0.4, 0.2), _p(x+side*1.3-1.5, y-length*0.55)])
	_poly_ramp(pts, ivory, 0.10)
	_curve(a+Vector2(-1.1, -0.4), _p(x+side-1, y-length*0.4), _p(x+side*2-0.6, y-length*0.8), b, 0.55, ivory[6])
	_line(a+Vector2(-2, 1), a+Vector2(2, 1), 0.6, skin[2])
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
	var shift := 3.0 if female and set_id == 1 else 0.0
	var left := PackedVector2Array([Vector2(6+shift, 78), Vector2(17+shift, 72),
		Vector2(31+shift, 77), Vector2(34+shift, 88), Vector2(26+shift, 95),
		Vector2(5+shift, 92)])
	_poly_ramp(left, metal, -0.06)
	_line(Vector2(8+shift, 78), Vector2(18+shift, 74), 0.7, metal[6])
	_line(Vector2(18+shift, 74), Vector2(30+shift, 78), 0.7, metal[5])
	_poly_ramp(PackedVector2Array([Vector2(33, 82), Vector2(61, 79),
		Vector2(78, 86), Vector2(82, 96), Vector2(29, 96)]), metal, -0.20)
	_line(Vector2(35, 83), Vector2(60, 81), 0.7, metal[5])
	_line(Vector2(55, 83), Vector2(62, 96), 0.8, metal[1])
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
	for c in [Vector2(12+shift, 80), Vector2(27+shift, 84), Vector2(40, 86), Vector2(70, 88)]:
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
	# Tapered curved ribbons, with a continuous lit strand and a dark underside.
	for pass_i in range(3):
		var offset := Vector2(-0.35*pass_i, -0.2*pass_i)
		var prev := a+offset
		for i in range(1, 23):
			var t := float(i)/22.0
			var p := a.bezier_interpolate(b, c, d, t)+offset
			var radius := maxf(0.32, width*(1.0-t*0.85)*(1.0-pass_i*0.37))
			if pass_i != 2 or (t > 0.18 and t < 0.76):
				_line(prev, p, radius, ramp[1 if pass_i == 0 else (3 if pass_i == 1 else 5)])
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
