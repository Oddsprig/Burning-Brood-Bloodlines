extends RefCounted
## Goblin-only 96px bust painter. All anatomy, hair and equipment drawing lives here.
## Deliberate pixel clusters, curved tapered locks, and seven-step lighting; no dithering.

const SIZE := 96
const INK := Color("#18251e")
const EYE_WHITE := Color("#ecf0d5")
const TOOTH := Color("#eee4bd")
const ARMOR := ["cuirass", "mail", "scale", "lamellar", "scrap", "byrnie", "plate", "brigandine", "hauberk", "breastplate"]

var image: Image
var face_mask := PackedByteArray()
var spec: Dictionary
var female := false
var young := false
var elder := false
var dead := false
var seed := 1
var cx := 48.0
var ey := 41.0
var chin := 68.0
var shoulder := 25.0
var lean := 0.0
var skin: Color
var hair: Color
var prim: Color
var sec: Color
var skin_ramp: Array[Color] = []
var hair_ramp: Array[Color] = []
var cloth_ramp: Array[Color] = []
var body: Dictionary = {}
var helm: Dictionary = {}
var helm_kind := "none"
var lost: Dictionary = {}

static func paint(spec: Dictionary) -> Image:
	return load("res://art/portraits/portrait_goblin.gd").new()._render(spec)

func _render(sp: Dictionary) -> Image:
	spec = sp
	_read()
	image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	face_mask.resize(SIZE * SIZE)
	face_mask.fill(0)
	_back_hair()
	_torso()
	_neck()
	_collar()
	if _lost("head"):
		_wound(_p(0, 20), 4)
		_outline()
		return image
	if helm_kind == "hood":
		_hood()
	_ear(-1)
	_ear(1)
	_skull()
	_face_planes()
	if helm_kind != "hood" and helm_kind != "closed":
		_front_hair()
	_eye(-1)
	_eye(1)
	_mouth()
	_nose()
	_age_lines()
	_beard()
	_helmet()
	_outline()
	return image

func _read() -> void:
	female = String(spec.get("sex", "male")) == "female"
	var age := int(spec.get("age", 16))
	young = age < 14
	elder = age >= 25
	seed = absi(int(spec.get("seed", 1)))
	dead = bool(spec.get("dead", false))
	lean = (-1.5 if young else (1.5 if elder else 0.5)) + float(seed % 3 - 1) * 0.5
	cx = 48.0 + lean
	ey = 43.0 if young else (42.0 if elder else 40.0)
	chin = ey + (24.0 if young else (27.0 if elder else 26.0))
	shoulder = (22.0 if young else (24.0 if elder else 26.0)) - (1.0 if female else 0.0)
	skin = _color("skin", Color("#82a84e"))
	hair = _color("hair", Color("#2d3525"))
	prim = _color("prim", Color("#6c5820"))
	sec = _color("sec", Color("#c89830"))
	var blood := clampf(float(spec.get("blood", 1.0)), 0.0, 1.0)
	skin = skin.lerp(Color("#bbc1a1"), (1.0 - blood) * 0.45)
	if dead:
		skin = skin.lerp(Color("#8a9384"), 0.55)
	if elder:
		skin = skin.lerp(Color("#8e9871"), 0.12)
		hair = hair.lerp(Color("#c8cdc0"), 0.38)
	skin_ramp = [
		skin.lerp(Color("#172c2d"), 0.72),
		skin.lerp(Color("#2b4440"), 0.49),
		skin.darkened(0.25),
		skin.darkened(0.10),
		skin,
		skin.lightened(0.13).lerp(Color("#d5d9a0"), 0.15),
		skin.lightened(0.27).lerp(Color("#f1e5ac"), 0.20),
	]
	hair_ramp = _ramp(hair, 0.70)
	if hair.get_luminance() < 0.12:
		# Black hair still needs readable reflected light inside each lock.
		hair_ramp = [hair.lerp(Color("#101b19"), 0.45), hair.lightened(0.035), hair.lightened(0.075), hair.lightened(0.14), hair.lightened(0.22), hair.lightened(0.33), hair.lightened(0.46)]
	cloth_ramp = _ramp(prim, 0.60)
	body = spec.get("body", {}) if spec.get("body", {}) is Dictionary else {}
	helm = spec.get("helm", {}) if spec.get("helm", {}) is Dictionary else {}
	var label := (String(helm.get("sprite", "")) + " " + String(helm.get("tid", ""))).to_lower().strip_edges()
	if label == "":
		helm_kind = "none"
	elif "hood" in label or "coif" in label:
		helm_kind = "hood"
	elif "closed" in label or "great" in label or "barrel" in label or "frog" in label:
		helm_kind = "closed"
	elif "circlet" in label or "crown" in label:
		helm_kind = "crown"
	elif "kettle" in label:
		helm_kind = "kettle"
	elif "nasal" in label:
		helm_kind = "nasal"
	else:
		helm_kind = "cap"
	var raw = spec.get("lost", [])
	if raw is Array:
		for part in raw:
			lost[String(part)] = true

func _color(key: String, fallback: Color) -> Color:
	var value = spec.get(key, fallback)
	var col := fallback
	if value is Color:
		col = value
	elif value is String and not String(value).is_empty():
		col = Color(String(value))
	col.a = 1.0
	return col

func _ramp(base: Color, depth: float) -> Array[Color]:
	var shadow := base.lerp(Color("#171d23"), depth)
	return [shadow, shadow.lerp(base, 0.22), shadow.lerp(base, 0.48), shadow.lerp(base, 0.74), base, base.lightened(0.16), base.lightened(0.31)]

func _lost(part: String) -> bool:
	return bool(lost.get(part, false))

func _p(x: float, y: float) -> Vector2:
	return Vector2(cx + x, ey + y)

func _px(x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		image.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))

func _face_pixel(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < SIZE and y < SIZE and face_mask[y * SIZE + x] == 1

func _shape(coords: Array, col: Color, origin := Vector2.ZERO, clip_face := false) -> void:
	var pts := PackedVector2Array()
	var lo := Vector2(999, 999)
	var hi := Vector2(-999, -999)
	for i in range(0, coords.size(), 2):
		var p := origin + Vector2(float(coords[i]), float(coords[i + 1]))
		pts.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y)) + 1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x)) + 1)):
			if clip_face and not _face_pixel(x, y):
				continue
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_px(x, y, col)

func _face_shape(coords: Array, band: int) -> void:
	_shape(coords, skin_ramp[band], _p(0, 0), true)

func _line(a: Vector2, b: Vector2, col: Color, width := 1.0) -> void:
	var count := maxi(1, int(ceil(a.distance_to(b) * 1.8)))
	for i in range(count + 1):
		var p := a.lerp(b, float(i) / float(count))
		for dy in range(-int(width / 2.0), int(width / 2.0) + 1):
			for dx in range(-int(width / 2.0), int(width / 2.0) + 1):
				_px(int(round(p.x)) + dx, int(round(p.y)) + dy, col)

func _ellipse(c: Vector2, rx: float, ry: float, ramp: Array[Color], bias := 0.0) -> void:
	for y in range(maxi(0, int(c.y - ry)), mini(SIZE, int(c.y + ry) + 1)):
		for x in range(maxi(0, int(c.x - rx)), mini(SIZE, int(c.x + rx) + 1)):
			var u := (float(x) + 0.5 - c.x) / rx
			var v := (float(y) + 0.5 - c.y) / ry
			if u * u + v * v > 1.0:
				continue
			var z := sqrt(maxf(0.0, 1.0 - u * u - v * v))
			var lit := 0.43 + z * 0.30 - u * 0.25 - v * 0.22 + bias
			_px(x, y, ramp[clampi(int(lit * 7.0), 0, 6)])

func _torso() -> void:
	var left_top := 78.0 + (2.0 if elder else -1.0)
	var right_top := 80.0 + (1.0 if young else -2.0)
	var bc := 48.0 - lean * 0.6
	var pts := PackedVector2Array([
		Vector2(bc - 6, 74), Vector2(bc - 15, left_top),
		Vector2(bc - shoulder + 2, left_top + 5), Vector2(bc - shoulder - 1, 94),
		Vector2(bc - shoulder + 1, 96), Vector2(bc + shoulder, 96),
		Vector2(bc + shoulder - 1, right_top + 8), Vector2(bc + shoulder - 5, right_top + 3),
		Vector2(bc + 10, 76), Vector2(bc + 4, 74),
	])
	for y in range(74, SIZE):
		for x in range(16, 81):
			if not Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				continue
			var u := (float(x) - bc) / shoulder
			var t := float(y - 75) / 23.0
			var fold := sin((float(x) - bc) * 0.44 + t * 2.5) * 0.055
			var lit := 0.68 - u * 0.26 - t * 0.23 + fold
			_px(x, y, cloth_ramp[clampi(int(lit * 7), 0, 6)])
	# A raised left shoulder and dropped right shoulder, with diagonal cloth folds.
	_line(Vector2(bc - 17, left_top + 3), Vector2(bc - 10, 91), cloth_ramp[5])
	_line(Vector2(bc - 15, left_top + 5), Vector2(bc - 9, 94), cloth_ramp[2])
	_line(Vector2(bc + 14, right_top + 4), Vector2(bc + 9, 95), cloth_ramp[1])
	_line(Vector2(bc + 19, right_top + 7), Vector2(bc + 16, 95), cloth_ramp[3])
	if _armored():
		_armor(bc, left_top, right_top)
	else:
		# Worn cross-body leather strap, with a brass buckle.
		_shape([-14, 78, -10, 77, 10, 96, 4, 96], Color("#473624"), Vector2(bc, 0))
		_line(Vector2(bc - 13, 79), Vector2(bc + 5, 95), Color("#98754a"))
		_shape([-2, 87, 2, 90, 0, 93, -4, 90], sec.darkened(0.28), Vector2(bc, 0))
		_line(Vector2(bc - 2, 88), Vector2(bc + 1, 90), sec.lightened(0.22))

func _armored() -> bool:
	var label := (String(body.get("sprite", "")) + " " + String(body.get("tid", ""))).to_lower()
	for kind in ARMOR:
		if kind in label:
			return true
	return false

func _metal_ramp(item: Dictionary) -> Array[Color]:
	var material := String(item.get("mat", "iron"))
	if material.is_empty():
		material = "iron"
	var metal: Dictionary = FigurePainter.metal(material, int(item.get("q", 0)))
	var base: Color = metal["base"]
	var dark: Color = metal["dark"]
	var light: Color = metal["light"]
	return [dark.darkened(0.25), dark, dark.lerp(base, 0.5), base, base.lerp(light, 0.55), light, metal["shine"]]

func _armor(bc: float, left_top: float, right_top: float) -> void:
	var ramp := _metal_ramp(body)
	_shape([-10, 79, 7, 78, 15, 88, 17, 96, -17, 96, -16, 88], ramp[2], Vector2(bc, 0))
	_shape([-10, 80, -2, 80, 1, 96, -16, 96, -15, 87], ramp[4], Vector2(bc, 0))
	_shape([7, 80, 14, 88, 16, 96, 6, 96], ramp[1], Vector2(bc, 0))
	var kind := String(body.get("sprite", ""))
	if kind in ["mail", "byrnie", "hauberk", "scale", "lamellar"]:
		for y in range(83, 96, 3):
			var half := mini(14, 8 + (y - 82))
			for x in range(int(bc) - half, int(bc) + half, 4):
				var xx := x + (1 if y % 2 == 0 else 0)
				_px(xx, y, ramp[1])
				_px(xx + 1, y + 1, ramp[5 if x < bc else 3])
				_px(xx + 2, y + 1, ramp[2])
	else:
		_line(Vector2(bc - 11, 87), Vector2(bc + 10, 85), ramp[5])
		_line(Vector2(bc + 2, 82), Vector2(bc + 4, 94), ramp[1])
	# Overlapping angular lames, with a top plane, a bevel and a dark underside.
	var lp := Vector2(bc, left_top)
	_shape([-23, 7, -15, 7, -12, 10, -20, 13, -25, 10], ramp[1], lp)
	_shape([-23, 8, -17, 8, -14, 10, -21, 11, -24, 10], ramp[3], lp)
	_shape([-25, 6, -22, 2, -16, 1, -10, 4, -11, 8, -17, 10, -24, 9], ramp[2], lp)
	_shape([-24, 5, -21, 2, -16, 2, -11, 4, -17, 6, -23, 6], ramp[5], lp)
	_shape([-24, 6, -17, 6, -11, 4, -12, 7, -18, 9, -24, 8], ramp[3], lp)
	_line(lp + Vector2(-24, 8), lp + Vector2(-18, 10), ramp[0])
	_line(lp + Vector2(-18, 10), lp + Vector2(-11, 7), ramp[1])
	_line(lp + Vector2(-22, 3), lp + Vector2(-17, 2), ramp[6])
	_px(int(bc) - 21, int(left_top) + 5, ramp[6])
	var rp := Vector2(bc, right_top)
	_shape([13, 8, 21, 8, 24, 11, 18, 14, 13, 12], ramp[0], rp)
	_shape([14, 9, 21, 9, 22, 11, 18, 12, 14, 11], ramp[2], rp)
	_shape([12, 6, 17, 3, 22, 5, 24, 9, 18, 12, 12, 9], ramp[1], rp)
	_shape([12, 6, 17, 3, 21, 5, 18, 7, 13, 8], ramp[4], rp)
	_shape([13, 8, 18, 7, 22, 5, 23, 9, 18, 11], ramp[2], rp)
	_line(rp + Vector2(14, 10), rp + Vector2(18, 12), ramp[0])

func _neck() -> void:
	if _lost("neck"):
		_wound(Vector2(cx, 74), 3)
		return
	var half := 3.8 if young or female else 4.4
	for y in range(int(chin) - 4, 83):
		var t := clampf(float(y - int(chin)) / 15.0, 0.0, 1.0)
		var center := lerpf(cx + 1.0, 48.0 - lean * 0.3, t)
		var width := half + t * 1.8
		for x in range(int(center - width), int(center + width) + 1):
			var u := (float(x) - center) / width
			var lit := 0.57 - u * 0.32 + t * 0.05
			if y < chin + 3:
				lit -= 0.23
			_px(x, y, skin_ramp[clampi(int(lit * 7), 0, 6)])
	_line(Vector2(cx - 2, chin + 4), Vector2(46, 79), skin_ramp[5])
	_line(Vector2(cx + 3, chin + 3), Vector2(50, 78), skin_ramp[1])
	if elder:
		_line(Vector2(cx - 1, 74), Vector2(cx + 2, 75), skin_ramp[2])

func _collar() -> void:
	var bc := 48.0 - lean * 0.6
	_shape([-10, 76, -5, 79, 0, 83, -7, 86, -14, 80], cloth_ramp[5], Vector2(bc, 0))
	_shape([5, 78, 10, 77, 13, 81, 5, 85, 0, 83], cloth_ramp[2], Vector2(bc, 0))
	_line(Vector2(bc - 9, 78), Vector2(bc - 3, 83), cloth_ramp[6])
	_line(Vector2(bc + 9, 79), Vector2(bc + 3, 83), cloth_ramp[0])
	_ellipse(Vector2(bc - 4, 83), 2, 2, _ramp(sec, 0.52))

func _skull() -> void:
	# Row widths describe a rounded cranium, angular cheekbones, hollow cheeks and a pointed chin.
	var knots := [Vector2(-21, 2), Vector2(-19, 9), Vector2(-15, 13.5), Vector2(-9, 16), Vector2(-2, 16.5), Vector2(5, 15.5), Vector2(9, 13), Vector2(14, 10.5), Vector2(19, 7.7), Vector2(24, 3.4), Vector2(27, 0)]
	if not young and not elder and not female:
		# A heavier brow and a wider jaw separate the adult from the boy.
		knots = [Vector2(-21, 2), Vector2(-19, 9), Vector2(-15, 13.5), Vector2(-9, 16), Vector2(-2, 17), Vector2(5, 16), Vector2(9, 14), Vector2(14, 12), Vector2(19, 10), Vector2(24, 5), Vector2(27, 0)]
	var bottom := chin - ey
	for y in range(int(ey - 21), int(chin) + 1):
		var dy := (float(y) + 0.5 - ey) * 27.0 / bottom
		var width := 0.0
		for i in range(knots.size() - 1):
			var a: Vector2 = knots[i]
			var b: Vector2 = knots[i + 1]
			if dy >= a.x and dy <= b.x:
				width = lerpf(a.y, b.y, (dy - a.x) / (b.x - a.x))
		if female:
			width *= lerpf(0.94, 0.80, smoothstep(7.0, 25.0, dy))
		if young:
			width += 0.35 * exp(-pow((dy - 5.0) / 8.0, 2))
		if elder and dy > 7 and dy < 19:
			width -= sin((dy - 7.0) / 12.0 * PI) * 1.6
		var center := cx + smoothstep(0.0, 24.0, dy) * 1.0
		for x in range(int(floor(center - width)), int(ceil(center + width))):
			var u := (float(x) + 0.5 - center) / maxf(0.5, width)
			if absf(u) > 1.0:
				continue
			var v := (dy + 1.0) / 27.0
			var z := sqrt(maxf(0, 1.0 - u * u))
			var lit := 0.48 + z * 0.28 - u * 0.26 - v * 0.13
			# Temple and cheek transitions break up the spherical light bands.
			lit -= 0.075 * exp(-pow((absf(u) - 0.78) / 0.18, 2)) * exp(-pow((dy + 1.0) / 13.0, 2))
			lit += 0.035 * exp(-pow((u + 0.33) / 0.36, 2)) * exp(-pow((dy - 6.0) / 4.0, 2))
			if elder:
				lit -= 0.035 * exp(-pow((absf(u) - 0.65) / 0.30, 2)) * exp(-pow((dy - 12.0) / 5.0, 2))
			if dy < -10:
				lit += 0.04
			_px(x, y, skin_ramp[clampi(int(lit * 7.0), 0, 6)])
			face_mask[y * SIZE + x] = 1

func _face_planes() -> void:
	# Broad midtones wrap the cheekbone before the small, recessed hollow.
	_face_shape([-14, 4, -10, 3, -5, 6, -7, 12, -10, 17, -13, 13], 4)
	_face_shape([-14, 5, -10, 4, -6, 6, -8, 8, -12, 8], 5)
	_face_shape([-13, 9, -10, 8, -7, 10, -7, 14, -9, 17, -12, 14], 3)
	_face_shape([-13, 8, -10, 7, -7, 9, -8, 11, -11, 10], 4)
	if elder:
		_face_shape([-10, 12, -8, 12, -7, 14, -9, 15, -10, 14], 2)
	_face_shape([6, 4, 13, 3, 14, 6, 12, 12, 9, 17, 6, 15], 3)
	_face_shape([9, 4, 13, 4, 13, 7, 10, 9, 7, 8], 4)
	_face_shape([11, 10, 13, 9, 11, 15, 9, 17, 8, 14, 9, 12], 2)
	_face_shape([-7, 17, -4, 19, 1, 21, 5, 21, 6, 23, 2, 26, -2, 24, -5, 21], 4)
	_face_shape([5, 18, 8, 16, 8, 20, 5, 25, 2, 27, 1, 25], 3)
	_face_shape([-3, 22, 1, 22, 4, 23, 2, 24, -1, 24], 5)
	_face_shape([6, 22, 5, 25, 2, 27, 3, 25], 2)
	if female and young:
		var blush := skin_ramp[4].lerp(Color("#b48067"), 0.28)
		_shape([-12, 6, -9, 6, -8, 7, -11, 8], blush, _p(0, 0), true)
		_shape([10, 6, 12, 5, 12, 7, 10, 8], blush.darkened(0.12), _p(0, 0), true)

func _ear(side: int) -> void:
	if _lost("ear_r" if side < 0 else "ear_l"):
		_wound(_p(side * 15, 2), 2)
		return
	var droop := 4.0 if elder else (-1.0 if young else 0.0)
	var far := -1.0 if side > 0 else 0.0
	var coords := [13.0, -5.0, 21.0, -7.0, 37.0, -15.0 + droop + far, 32.0, -2.0 + droop, 26.0, 6.0 + droop * 0.5, 19.0, 11.0, 14.0, 6.0]
	var outer: Array = []
	for i in range(0, coords.size(), 2):
		outer.append(float(coords[i]) * side)
		outer.append(coords[i + 1])
	_shape(outer, skin_ramp[2 if side < 0 else 1], _p(0, 0))
	var inner: Array = [side * 16, -3, side * 23, -6, side * 34, -12 + droop + far, side * 28, -1 + droop, side * 24, 5, side * 18, 7]
	var membrane := skin.lerp(Color("#9b8060"), 0.35).darkened(0.12 if side < 0 else 0.30)
	_shape(inner, membrane, _p(0, 0))
	_line(_p(side * 16, -5), _p(side * 34, -12 + droop + far), skin_ramp[5 if side < 0 else 4])
	_line(_p(side * 34, -12 + droop + far), _p(side * 27, 0 + droop), skin_ramp[3])
	_line(_p(side * 19, 7), _p(side * 26, -2 + droop), skin_ramp[1])
	_line(_p(side * 18, 5), _p(side * 21, 1), skin_ramp[5 if side < 0 else 3])
	if (female or not young) and side < 0:
		_ellipse(_p(-22, 8), 2.4, 3.0, _ramp(sec, 0.65))
		_ellipse(_p(-22, 8), 1.0, 1.5, [skin_ramp[1], skin_ramp[1], skin_ramp[1], skin_ramp[1], skin_ramp[1], skin_ramp[1], skin_ramp[1]])

func _eye(side: int) -> void:
	var center := _p(-7.7 if side < 0 else 7.3, -0.4 if side < 0 else 0.4)
	if _lost("eye_r" if side < 0 else "eye_l"):
		_wound(center, 3)
		return
	var rx := 5.0 if young else 4.6
	var ry := 2.7 if young else (2.1 if elder else 2.4)
	var lid := -ry + (1.0 if side > 0 else 0.2)
	var socket := skin_ramp[0].lerp(Color("#3e4125"), 0.25)
	_ellipse(center + Vector2(0, 0.8), rx + 1.0, ry + 1.0, skin_ramp, -0.20)
	_shape([-rx - 1, -1, -rx + 1, -ry, 1, -ry - 1, rx, -1, rx, 1, 1, ry, -rx + 1, ry - 1], socket, center)
	if dead:
		_line(center + Vector2(-rx, 0), center + Vector2(0, 1), skin_ramp[0])
		_line(center + Vector2(0, 1), center + Vector2(rx, -1), skin_ramp[0])
		return
	_shape([-rx, -0.5, -rx + 2, lid + 0.4, 1, lid, rx - 0.3, -0.3, rx - 1, 1.4, 0, ry - 0.1, -rx + 1, 1.4], EYE_WHITE, center)
	var gaze := 0.7 + float(seed % 3) * 0.25
	var iris := center + Vector2(gaze, 0)
	_ellipse(iris, 2.0, ry - 0.3, [Color("#73501b"), Color("#927025"), Color("#be9731"), Color("#dfb63a"), Color("#ebc746"), Color("#f1d366"), Color("#f6df79")])
	_shape([-0.6, -ry + 0.9, 0.9, -ry + 1.2, 0.9, ry - 1.0, -0.4, ry - 0.6], INK, iris)
	# The lid overlaps the iris, especially the far eye, rather than exposing a round stare.
	_shape([-rx - 1, -ry - 2, rx + 1, -ry - 2, rx, -0.3, 1, lid, -rx + 2, lid + 0.4, -rx, -0.5], skin_ramp[4 if side < 0 else 3], center)
	_px(int(round(iris.x)) - 1, int(round(iris.y)), Color("#fff9d9"))
	_line(center + Vector2(-rx, -0.5), center + Vector2(1, lid), INK)
	_line(center + Vector2(1, lid), center + Vector2(rx, -0.3), INK)
	_line(center + Vector2(-rx + 1, ry), center + Vector2(1, ry + 1), skin_ramp[4 if side < 0 else 2])
	var brow_y := -5.8 if side < 0 else -4.7
	if female and young:
		brow_y = -4.9 if side < 0 else -6.0
	elif not young:
		brow_y = -4.6 if side < 0 else -4.0
	var brow_col := hair_ramp[1].lerp(skin_ramp[0], 0.30)
	var brow_depth := 1.0 if female or young else 2.0
	var brow_coords := [-rx - 1, brow_y + 2, -1, brow_y - 0.5, rx, brow_y + 1, rx - 0.5, brow_y + 2.0, -1, brow_y + brow_depth, -rx - 1, brow_y + 3]
	if not young and not female:
		_shape([-rx - 1, brow_y + 2, -1, brow_y - 1, rx, brow_y, rx, brow_y + 3, -1, brow_y + 2, -rx - 1, brow_y + 4], skin_ramp[5 if side < 0 else 3], center)
	_shape(brow_coords, brow_col, center)
	_line(center + Vector2(-rx + 1, brow_y + 1), center + Vector2(-1, brow_y), hair_ramp[4 if elder else 3])
	if female:
		_line(center + Vector2(side * rx, -1), center + Vector2(side * (rx + 1), -3), INK)

func _nose() -> void:
	if _lost("nose"):
		_wound(_p(3, 9), 3)
		return
	var length := -1.5 if young else (0.8 if elder else 0.0)
	if female:
		length -= 0.5
	# The tip projects past the bridge, then turns back into a shaded underside.
	_face_shape([4, 6, 7, 8 + length, 11, 12 + length, 10, 15 + length, 7, 17 + length, 5, 15 + length, 3, 12], 2)
	_face_shape([8, 11 + length, 10, 13 + length, 8, 16 + length, 6, 15 + length, 6, 13 + length], 1)
	_shape([0, -4, 3, -3, 3, 2, 5, 6, 8, 8 + length, 10, 9 + length, 10, 12 + length, 9, 14 + length, 7, 15 + length, 5, 14 + length, 5, 12 + length, 2, 12 + length, 0, 10 + length, -1, 6], skin_ramp[2], _p(0, 0))
	_shape([0, -3, 2, -2, 2, 3, 4, 7, 7, 9 + length, 8, 10 + length, 8, 12 + length, 7, 13 + length, 5, 12 + length, 2, 11 + length, 0, 9, -1, 6], skin_ramp[4], _p(0, 0))
	_shape([0, -2, 1, 1, 1, 5, 3, 8 + length, 3, 10 + length, 1, 9, 0, 6], skin_ramp[6], _p(0, 0))
	_shape([6, 8 + length, 9, 9 + length, 9, 12 + length, 8, 14 + length, 6, 14 + length, 7, 12 + length, 7, 10 + length], skin_ramp[5], _p(0, 0))
	_shape([3, 11 + length, 5, 10 + length, 7, 11 + length, 7, 12 + length, 6, 13 + length, 4, 12 + length], skin_ramp[0], _p(0, 0))
	_line(_p(9, 12 + length), _p(8, 14 + length), skin_ramp[1])
	_line(_p(8, 14 + length), _p(6, 14 + length), skin_ramp[1])
	_line(_p(6, 14 + length), _p(5, 13 + length), skin_ramp[2])
	_line(_p(-1, 10 + length), _p(1, 11 + length), skin_ramp[3])

func _mouth() -> void:
	if _lost("jaw"):
		_wound(_p(1, 22), 4)
		return
	if _lost("mouth"):
		_wound(_p(1, 17), 3)
		return
	var my := 17.0 if young else (19.0 if elder else 18.5)
	if female and elder:
		my = 18.5
	var left := my - 1.0
	var right := my - 2.0
	var depth := 4.0
	if female and young:
		left = my - 3.0
		right = my
		depth = 3.6
	elif female and elder:
		left = my
		right = my - 3.0
	elif elder:
		left = my - 2.0
		right = my - 2.5
	elif not young:
		left = my - 3.0
		right = my - 0.5
		depth = 3.8
	var near_top := lerpf(left, my, 0.55)
	var far_top := lerpf(my, right, 0.50)
	var lip := skin.lerp(Color("#6b5636"), 0.55).darkened(0.30)
	_shape([-11, left - 1, -5, near_top - 1, 0, my - 0.5, 5, far_top - 1, 11, right - 1, 10, right + 2, 5, far_top + depth, 0, my + depth, -5, near_top + depth, -10, left + 1], lip, _p(0, 0), true)
	_shape([-10, left, -5, near_top, 0, my, 5, far_top, 10, right, 9, right + 1, 5, far_top + depth - 1, 0, my + depth - 1, -5, near_top + depth - 1], Color("#283025"), _p(0, 0), true)
	if not dead:
		var teeth: Array[float] = [-7.0, -1.0, 5.0]
		if elder:
			teeth = [-4.0, 4.0]
		elif not young:
			teeth = [-7.0, 2.0]
		elif female:
			teeth = [-6.0, 3.0]
		for i in range(teeth.size()):
			var x := teeth[i]
			var y := lerpf(left, my, (x + 10.0) / 10.0) if x < 0 else lerpf(my, right, x / 10.0)
			# Align the point to a pixel center so every variant retains a sharp tip.
			var root := Vector2(floor(cx + x) + 0.5, floor(ey + y))
			_shape([-1.5, 0, 1.5, 0, 0, 3.3 if i == 0 else 2.8], TOOTH if x < 0 else TOOTH.darkened(0.14), root, true)
	_line(_p(-4, my + depth), _p(1, my + depth), skin_ramp[5])
	_line(_p(-3, my + depth + 1), _p(3, my + depth + 1), skin_ramp[3])
	_line(_p(9, right - 1), _p(11, right - 3), skin_ramp[2])
	_line(_p(-11, left), _p(-12, left - 2), skin_ramp[3])
	_line(_p(-11, left - 2), _p(-10, left - 3), skin_ramp[5])

func _age_lines() -> void:
	if elder:
		# Unequal broken arcs turn around the forehead instead of parallel stamps.
		var lift := -1.0 if female else 0.0
		_line(_p(-8, -12 + lift), _p(-5, -14 + lift), skin_ramp[3])
		_line(_p(-5, -14 + lift), _p(-1, -14 + lift), skin_ramp[3])
		_line(_p(-1, -14 + lift), _p(2, -13 + lift), skin_ramp[2])
		_line(_p(-6, -12 + lift), _p(-3, -13 + lift), skin_ramp[5])
		_line(_p(-5, -8), _p(-2, -9), skin_ramp[3])
		_line(_p(-2, -9), _p(2, -9), skin_ramp[3])
		_line(_p(2, -9), _p(4, -8), skin_ramp[2])
		_line(_p(-3, -8), _p(0, -8), skin_ramp[5])
		for side in [-1, 1]:
			_line(_p(side * 12, 2), _p(side * 15, 4), skin_ramp[2 if side > 0 else 3])
			_line(_p(side * 12, 5), _p(side * 14, 7), skin_ramp[3])
		_line(_p(-5, 12), _p(-7, 15), skin_ramp[3])
		_line(_p(-7, 15), _p(-7, 17), skin_ramp[3])
		_line(_p(-12, 8), _p(-9, 9), skin_ramp[4])
	elif not young and not female:
		_line(_p(11, -8), _p(14, -3), skin_ramp[1])
		_line(_p(10, -8), _p(13, -3), skin_ramp[5])
	elif young:
		for x in [-11, -8, 9]:
			_px(int(cx) + x, int(ey) + 7, skin_ramp[3])

func _beard() -> void:
	var value = spec.get("beard", false)
	var on := false
	var color := hair
	if value is bool:
		on = value
	elif value is Color:
		on = true
		color = value
	elif value is String and String(value) != "" and String(value) != "false":
		on = true
		if String(value).begins_with("#"):
			color = Color(String(value))
	if not on or _lost("jaw") or _lost("mouth"):
		return
	var style := clampi(int(spec.get("beard_style", 0)), 0, 7)
	var ramp := _ramp(color, 0.6)
	for i in range(3 if style == 7 else 5):
		var start := _p(-2 + i, 23)
		_line(start, start + Vector2(1.0 - i * 0.35, 2 if style == 7 else 5 + i % 2), ramp[2 + i % 3])

func _lock(p0: Vector2, p1: Vector2, p2: Vector2, r0: float, r1: float, bias := 0.0) -> void:
	# Tapered quadratic lock; light follows its cross-section instead of a checker pattern.
	const STEPS := 16
	var points: Array[Vector2] = []
	var lo := p0
	var hi := p0
	for i in range(STEPS + 1):
		var t := float(i) / float(STEPS)
		var p := p0 * (1.0 - t) * (1.0 - t) + p1 * (2.0 * t * (1.0 - t)) + p2 * t * t
		points.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	var pad := maxf(r0, r1) + 1.0
	for y in range(maxi(0, int(floor(lo.y - pad))), mini(SIZE, int(ceil(hi.y + pad)) + 1)):
		for x in range(maxi(0, int(floor(lo.x - pad))), mini(SIZE, int(ceil(hi.x + pad)) + 1)):
			var p := Vector2(x + 0.5, y + 0.5)
			var best := 99999.0
			var along := 0.0
			var offset := 0.0
			for i in range(STEPS):
				var a := points[i]
				var b := points[i + 1]
				var segment := b - a
				var f := clampf((p - a).dot(segment) / maxf(0.001, segment.length_squared()), 0.0, 1.0)
				var close := a + segment * f
				var distance := p.distance_squared_to(close)
				if distance < best:
					best = distance
					along = (float(i) + f) / float(STEPS)
					var normal := Vector2(-segment.y, segment.x).normalized()
					if normal.dot(Vector2(-0.7, -0.7)) > 0:
						normal = -normal
					offset = (p - close).dot(normal)
			var radius := lerpf(r0, r1, along)
			if best > radius * radius:
				continue
			var cross := offset / maxf(0.6, radius)
			var lit := 0.65 - cross * 0.31 - along * 0.16 - (float(x) - cx) * 0.006 + bias
			if cross > 0.76:
				lit -= 0.10
			_px(x, y, hair_ramp[clampi(int(lit * 7), 0, 6)])

func _back_hair() -> void:
	if _lost("head") or helm_kind == "closed" or helm_kind == "hood":
		return
	if female:
		if elder:
			# Loose off-center knot made of overlapping curved locks, not a solid cap.
			_lock(_p(9, -20), _p(22, -29), _p(17, -9), 4, 2, -0.10)
			_lock(_p(12, -22), _p(24, -16), _p(15, -7), 3.5, 0.6)
		else:
			_lock(_p(-11, -14), _p(-27, 4), _p(-20, 29), 4.8, 0.15, -0.12)
			_lock(_p(-15, -2), _p(-21, 22), _p(-25, 24), 2.4, 0.10)
			_lock(_p(12, -15), _p(24, 2), _p(21, 19), 3.8, 0.15, -0.22)
			_lock(_p(18, 3), _p(23, 14), _p(16, 23), 2.4, 0.10, -0.12)
	elif elder:
		_lock(_p(-12, -11), _p(-20, 3), _p(-14, 14), 2.5, 0.5)
		_lock(_p(12, -12), _p(20, 2), _p(15, 12), 2.5, 0.4, -0.15)

func _front_hair() -> void:
	if elder and not female:
		# Receded scalp remains visible between wisps, with longer silver temple locks.
		_lock(_p(-13, -9), _p(-18, -25), _p(-4, -23), 2.4, 0.3, 0.04)
		_lock(_p(-12, -13), _p(-10, -24), _p(1, -22), 2.4, 0.3)
		_lock(_p(12, -8), _p(18, -20), _p(8, -20), 2.7, 0.3, -0.10)
		_lock(_p(-15, -7), _p(-18, 0), _p(-14, 8), 2.5, 0.3)
		_lock(_p(15, -7), _p(18, 1), _p(14, 8), 2.0, 0.3, -0.15)
	elif female and elder:
		_lock(_p(7, -20), _p(-7, -28), _p(-16, -8), 4.0, 1.0, 0.02)
		_lock(_p(6, -20), _p(-8, -22), _p(-14, -3), 3.2, 0.5)
		_lock(_p(8, -20), _p(18, -20), _p(16, -4), 3.5, 0.5, -0.05)
		_lock(_p(9, -18), _p(14, -15), _p(16, -1), 2.5, 0.4, -0.10)
		var side := -1.0 if int(spec.get("female_set", seed % 2)) % 2 == 0 else 1.0
		_lock(_p(side * 15, -1), _p(side * 18, 5), _p(side * 17, 10), 2.5, 1.2, -0.05)
		# Each crossing has its own scalloped silhouette and overlap shadow.
		for i in range(7):
			var t := float(i) / 6.0
			var y := ey + 10 + i * 4.5
			var bx := cx + side * (17.0 + sin(t * PI) * 1.2 + t)
			var r := 3.5 - t * 1.2
			var at := Vector2(bx, y)
			_shape([-r, -1, 0, -3, r, -1, r, 2, 0, 5, -r, 2], hair_ramp[1], at)
			if i % 2 == 0:
				_shape([r, -1, r - 1, -2, -1, 0, -r, 2, -r + 1, 3, 1, 1], hair_ramp[3], at)
				_shape([-r, -1, -r + 1, -2, 0, -1, r, 2, r - 1, 3, -1, 1], hair_ramp[4], at)
				_line(at + Vector2(-r + 1, -1), at + Vector2(1, 1), hair_ramp[5])
			else:
				_shape([-r, -1, -r + 1, -2, 0, -1, r, 2, r - 1, 3, -1, 1], hair_ramp[3], at)
				_shape([r, -1, r - 1, -2, 1, -1, -r, 2, -r + 1, 3, 1, 1], hair_ramp[4], at)
				_line(at + Vector2(-r + 1, 2), at + Vector2(0, 0), hair_ramp[5])
		var tie := Vector2(cx + side * 18, 85)
		_lock(tie + Vector2(0, 1), tie + Vector2(side, 4), tie + Vector2(-side, 7), 1.7, 0.10)
		_line(tie + Vector2(-2, 0), tie + Vector2(2, 0), sec)
	elif female:
		_lock(_p(4, -19), _p(-8, -30), _p(-18, -11), 5.0, 0.6, 0.03)
		_lock(_p(3, -19), _p(-8, -20), _p(-13, -7), 4.0, 0.5, 0.02)
		_lock(_p(5, -20), _p(-2, -22), _p(-13, -3), 4.0, 0.4, 0.02)
		_lock(_p(6, -22), _p(14, -28), _p(18, -9), 4.2, 0.3, -0.10)
		_lock(_p(6, -21), _p(17, -17), _p(14, 1), 3.2, 0.4, -0.12)
		_lock(_p(-15, -4), _p(-23, 7), _p(-14, 22), 3.0, 0.10, 0.02)
		_lock(_p(-18, 11), _p(-15, 21), _p(-20, 27), 1.6, 0.05)
		_lock(_p(15, -2), _p(20, 8), _p(14, 15), 2.4, 0.10, -0.12)
		_lock(_p(18, 4), _p(22, 12), _p(20, 20), 1.8, 0.10, -0.12)
		_lock(_p(-10, -20), _p(-16, -11), _p(-11, -5), 2.2, 0.2, 0.05)
	elif young:
		_lock(_p(8, -17), _p(-2, -28), _p(-18, -14), 4.8, 0.3)
		_lock(_p(5, -18), _p(-7, -21), _p(-14, -9), 4.2, 0.4)
		_lock(_p(5, -19), _p(-4, -29), _p(-10, -25), 3.8, 0.2, 0.02)
		_lock(_p(9, -19), _p(3, -26), _p(0, -29), 3.4, 0.2)
		_lock(_p(9, -19), _p(16, -26), _p(17, -13), 3.8, 0.3, -0.12)
		_lock(_p(4, -17), _p(-3, -15), _p(-12, -6), 4.3, 0.4)
		_lock(_p(8, -18), _p(14, -13), _p(14, -5), 3.2, 0.2, -0.12)
		_lock(_p(-13, -14), _p(-18, -7), _p(-15, -1), 2.4, 0.2)
	else:
		# Adult's swept, wiry forelock leaves shaved temples and a high forehead.
		_lock(_p(5, -18), _p(-2, -30), _p(-12, -24), 4.1, 0.3, 0.03)
		_lock(_p(5, -20), _p(0, -30), _p(-4, -30), 3.5, 0.2)
		_lock(_p(7, -17), _p(12, -29), _p(8, -27), 3.6, 0.2, -0.08)
		_lock(_p(3, -19), _p(-7, -22), _p(-14, -9), 3.4, 0.3)
		_lock(_p(7, -20), _p(16, -17), _p(15, -8), 3.0, 0.3, -0.15)
		_lock(_p(0, -19), _p(-3, -11), _p(-8, -7), 2.7, 0.2)

func _hood() -> void:
	var ramp := _metal_ramp(helm) if "coif" in String(helm.get("sprite", "")) else cloth_ramp
	_ellipse(_p(0, -1), 21, 27, ramp, -0.10)
	_lock(_p(-18, -4), _p(-25, 14), _p(-16, 28), 3.0, 1.0, -0.2)

func _helmet() -> void:
	if helm_kind in ["none", "hood"]:
		return
	var ramp := _metal_ramp(helm)
	if helm_kind == "crown":
		_line(_p(-14, -11), _p(14, -11), ramp[4], 2)
		for x in [-10, -5, 0, 5, 10]:
			_shape([x - 2, -11, x, -18 - (2 if x == 0 else 0), x + 2, -11], ramp[5], _p(0, 0))
		return
	for y in range(int(ey - 26), int(ey - 8)):
		for x in range(int(cx - 19), int(cx + 20)):
			var u := (float(x) + 0.5 - cx) / 19.0
			var v := (float(y) + 0.5 - ey + 7.0) / 19.0
			if u * u + v * v <= 1.0:
				_px(x, y, ramp[clampi(int((0.67 - u * 0.32 - v * 0.10) * 7), 0, 6)])
	_line(_p(-18, -9), _p(18, -9), ramp[1], 2)
	_line(_p(-16, -11), _p(8, -11), ramp[5])
	if helm_kind == "kettle":
		_line(_p(-24, -8), _p(24, -8), ramp[3], 2)
		_line(_p(-24, -9), _p(20, -9), ramp[5])
	elif helm_kind == "nasal":
		_line(_p(1, -17), _p(2, 9), ramp[4], 2)
		_line(_p(3, -15), _p(4, 9), ramp[1])
	elif helm_kind == "closed":
		_shape([-17, -8, 17, -8, 14, 17, 3, 26, -10, 20], ramp[2], _p(0, 0))
		_shape([-16, -7, -1, -7, 2, 24, -9, 19], ramp[4], _p(0, 0))
		_line(_p(-12, 0), _p(-3, -1), INK, 2)
		_line(_p(5, -1), _p(13, -1), INK, 2)
		for x in [-6, -2, 2, 6]:
			_line(_p(x, 12), _p(x, 17), ramp[0])

func _wound(c: Vector2, radius: float) -> void:
	_ellipse(c, radius, radius * 0.8, [Color("#381c1a"), Color("#542321"), Color("#742b27"), Color("#8c332b"), Color("#9e4033"), Color("#b75240"), Color("#cb6a50")])

func _outline() -> void:
	var border: Array[Vector2i] = []
	for y in range(SIZE):
		for x in range(SIZE):
			if image.get_pixel(x, y).a < 0.5:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q := Vector2i(x, y) + Vector2i(d)
				if q.x >= 0 and q.y >= 0 and q.x < SIZE and q.y < SIZE and image.get_pixel(q.x, q.y).a < 0.5:
					border.append(q)
	for p in border:
		_px(p.x, p.y, INK)
