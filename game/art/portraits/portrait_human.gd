extends RefCounted
## Human portrait painter. All contours, locks and shading are native 96px pixels.
## Deliberately independent of the frozen elf/legacy portrait renderer.

const SIZE := 96
const INK := Color("#241e28")
const WHITE := Color("#f7eddb")
const BLOOD := Color("#a72e35")
const ARMOR := ["cuirass", "mail", "scale", "lamellar", "scrap", "byrnie", "plate", "brigandine", "hauberk", "breastplate"]

var image: Image
var spec: Dictionary
var seed := 1
var female := false
var young := false
var elder := false
var dead := false
var lost: Array = []
var cx := 48.0
var top := 19.0
var chin := 65.0
var width := 18.0
var ey := 39
var my := 55
var shoulder := 0.0
var skin := Color.WHITE
var hair := Color.WHITE
var prim := Color.WHITE
var sec := Color.WHITE
var sr: Array[Color] = []
var hr: Array[Color] = []
var br: Array[Color] = []
var cr: Array[Color] = []
var beard := false
var beard_style := 0
var body: Dictionary = {}
var helm: Dictionary = {}
var helm_kind := "none"
var part := 1.0

static func paint(spec: Dictionary) -> Image:
	return load("res://art/portraits/portrait_human.gd").new()._render(spec)

func _render(sp: Dictionary) -> Image:
	spec = sp
	_read()
	image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	if not _lost("head"):
		if helm_kind == "coif":
			_hood()
		elif helm_kind != "closed":
			_hair_back()
	_torso()
	_neck()
	_collar()
	if _lost("head"):
		_wound(int(cx), 64, 7)
	elif helm_kind == "closed":
		_headgear()
	else:
		_ear(-1)
		_ear(1)
		_face()
		_age_lines()
		_eye(int(cx) - 8, ey, true)
		_eye(int(cx) + 7, ey + (0 if young else 1), false)
		_nose()
		_mouth()
		if helm_kind != "coif":
			_hair_front()
		_beard()
		_headgear()
		if _lost("nose"):
			_wound(int(cx) + 2, ey + 11, 3)
		if _lost("jaw"):
			_wound(int(cx) + 1, int(chin) - 2, 5)
	_outline()
	return image

func _read() -> void:
	seed = absi(int(spec.get("seed", 1)))
	female = String(spec.get("sex", "male")) == "female"
	var age := int(spec.get("age", 30))
	young = age < 23
	elder = age >= 55
	dead = bool(spec.get("dead", false))
	cx = 48.0 + float(seed % 3 - 1) * 0.5
	width = (17.4 if female else (18.2 if young or elder else 20.0)) + float(int(seed / 7.0) % 3 - 1) * 0.35
	top = 18.0 if elder else (19.0 if not young else 20.0)
	chin = (64.0 if young else 66.0) if female else (65.0 if young else 67.0)
	ey = 39
	my = (55 if young else 56) if female else (55 if young else 56)
	shoulder = (3.0 if elder else 0.0) + (2.0 if female else 0.0)
	part = 1.0 if int(spec.get("female_set", seed % 2)) % 2 == 0 else -1.0
	skin = _color("skin", Color("#dfb08a"))
	hair = _color("hair", Color("#483025"))
	prim = _color("prim", Color("#2458a8"))
	sec = _color("sec", Color("#e8b840"))
	skin = skin.lerp(Color("#c0bab0"), clampf((1.0 - float(spec.get("blood", 1.0))) * 0.6, 0.0, 0.45))
	if dead:
		skin = skin.lerp(Color("#929397"), 0.48)
	if elder:
		hair = hair.lerp(Color("#d8d5ce"), 0.56)
	sr = _skin_ramp(skin)
	hr = _ramp(hair)
	cr = _ramp(prim)
	var beard_color := hair
	var b = spec.get("beard", false)
	if b is bool:
		beard = b
	elif b is Color:
		beard = true
		beard_color = b
	elif b is String and b != "" and b != "false":
		beard = true
		if Color.html_is_valid(String(b)):
			beard_color = Color(String(b))
	if elder:
		beard_color = beard_color.lerp(Color("#d8d5ce"), 0.28)
	br = _ramp(beard_color)
	beard_style = clampi(int(spec.get("beard_style", 0)), 0, 8)
	body = spec.get("body", {}) if spec.get("body", {}) is Dictionary else {}
	helm = spec.get("helm", {}) if spec.get("helm", {}) is Dictionary else {}
	lost = spec.get("lost", []) if spec.get("lost", []) is Array else []
	var name := (String(helm.get("sprite", "")) + " " + String(helm.get("tid", ""))).to_lower().strip_edges()
	if name == "":
		helm_kind = "none"
	elif "coif" in name or "hood" in name:
		helm_kind = "coif"
	elif "closed" in name or "great" in name or "barrel" in name or "frog" in name:
		helm_kind = "closed"
	elif "crown" in name or "circlet" in name:
		helm_kind = "crown"
	elif "kettle" in name:
		helm_kind = "kettle"
	elif "nasal" in name:
		helm_kind = "nasal"
	else:
		helm_kind = "cap"

func _color(key: String, fallback: Color) -> Color:
	var value = spec.get(key, fallback)
	var col := fallback
	if value is Color:
		col = value
	elif value is String and String(value) != "":
		col = Color(String(value))
	col.a = 1.0
	return col

func _skin_ramp(base: Color) -> Array[Color]:
	return [base.lerp(Color("#302536"), 0.72), base.lerp(Color("#613b42"), 0.58),
		base.darkened(0.27).lerp(Color("#956652"), 0.10), base.darkened(0.12), base,
		base.lightened(0.10).lerp(Color("#ffe1bd"), 0.08), base.lightened(0.22).lerp(Color("#fff0d5"), 0.10)]

func _ramp(base: Color) -> Array[Color]:
	return [base.darkened(0.60).lerp(Color("#272332"), 0.18), base.darkened(0.40),
		base.darkened(0.20), base, base.lightened(0.13).lerp(Color("#d8b89a"), 0.10),
		base.lightened(0.27).lerp(Color("#ead7b6"), 0.12), base.lightened(0.42).lerp(Color("#fff0d5"), 0.12)]

func _lost(id: String) -> bool:
	return id in lost

func _px(x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		image.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))

func _band(lit: float) -> int:
	# Contiguous colour clusters, never a checkerboard/dither.
	return clampi(int(lit * 7.0), 0, 6)

func _tone(ramp: Array[Color], lit: float) -> Color:
	# Half-steps keep dark complexions rounded without introducing dithering.
	var step := clampf(floorf(lit * 14.0) * 0.5, 0.0, 6.0)
	var low := int(step)
	return ramp[low].lerp(ramp[mini(low + 1, 6)], step - float(low))

func _points(coords: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(0, coords.size(), 2):
		pts.append(Vector2(float(coords[i]), float(coords[i + 1])))
	return pts

func _poly(coords: Array, col: Color, ramp: Array[Color] = []) -> void:
	var pts := _points(coords)
	var bounds := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bounds = bounds.expand(p)
	for y in range(maxi(0, int(floor(bounds.position.y))), mini(SIZE, int(ceil(bounds.end.y)) + 1)):
		for x in range(maxi(0, int(floor(bounds.position.x))), mini(SIZE, int(ceil(bounds.end.x)) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				var c := col
				if not ramp.is_empty():
					c = ramp[_band(0.83 - (float(x) - 22.0) / 120.0 - (float(y) - 70.0) * 0.007)]
				_px(x, y, c)

func _oval(c: Vector2, rx: float, ry: float, col: Color, ramp: Array[Color] = [], bias: float = 0.0) -> void:
	for y in range(maxi(0, int(c.y - ry)), mini(SIZE, int(c.y + ry) + 1)):
		for x in range(maxi(0, int(c.x - rx)), mini(SIZE, int(c.x + rx) + 1)):
			var u := (float(x) + 0.5 - c.x) / rx
			var v := (float(y) + 0.5 - c.y) / ry
			if u * u + v * v > 1.0:
				continue
			var fill := col
			if not ramp.is_empty():
				fill = ramp[_band(0.53 - u * 0.25 - v * 0.17 + 0.16 * sqrt(maxf(0.0, 1.0 - u * u - v * v)) + bias)]
			_px(x, y, fill)

func _line(a: Vector2, b: Vector2, col: Color, radius: float = 0.45) -> void:
	var steps := maxi(1, int(ceil(a.distance_to(b) * 2.0)))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if radius <= 0.5:
			_px(int(round(p.x)), int(round(p.y)), col)
		else:
			_oval(p, radius, radius, col)

func _curve(a: Vector2, b: Vector2, c: Vector2, col: Color, radius: float = 0.45) -> void:
	var previous := a
	for i in range(1, 25):
		var t := float(i) / 24.0
		var p := a * (1.0-t) * (1.0-t) + b * 2.0 * (1.0-t) * t + c * t * t
		_line(previous, p, col, radius)
		previous = p

func _torso() -> void:
	var s := shoulder
	var bx := 35
	var by := int(75+s)
	if female:
		_poly([40, 70+s, 32, 73+s, 24, 79+s, 20, 87+s, 18, 95, 83, 95,
			79, 86+s, 71, 79+s, 59, 72+s, 55, 70+s], prim, cr)
		bx = 33 if elder else 62
		_lock(Vector2(34, 77+s), Vector2(25, 83+s), Vector2(23, 95), 4.8, 2.0, cr, 0.07)
		_curve(Vector2(38, 78+s), Vector2(31, 84+s), Vector2(29, 95), cr[2])
		_curve(Vector2(64, 79+s), Vector2(74, 85+s), Vector2(76, 95), cr[1])
		if not elder:
			_lock(Vector2(60, 78), Vector2(45, 83), Vector2(33, 89), 3.0, 1.3, cr, -0.02)
			_curve(Vector2(60, 81), Vector2(47, 88), Vector2(35, 90), cr[1])
	elif elder:
		_poly([40, 71, 33, 72, 23, 79, 17, 86, 13, 95, 87, 95,
			82, 86, 75, 81, 64, 77, 56, 71], prim, cr)
		bx = 32
		by = 79
		_lock(Vector2(35, 77), Vector2(22, 82), Vector2(20, 95), 5.5, 3.0, cr, 0.08)
		_curve(Vector2(35, 81), Vector2(28, 89), Vector2(36, 95), cr[1])
		_lock(Vector2(61, 80), Vector2(71, 83), Vector2(80, 95), 4.0, 1.0, cr, -0.12)
		_curve(Vector2(62, 84), Vector2(64, 91), Vector2(68, 95), cr[1])
	else:
		_poly([39, 68, 30, 71, 21, 76, 15, 83, 10, 95, 88, 95,
			84, 84, 77, 78, 61, 71, 56, 68], prim, cr)
		_lock(Vector2(34, 74), Vector2(22, 80), Vector2(16, 95), 5.3, 2.7, cr, 0.08)
		_curve(Vector2(36, 78), Vector2(28, 86), Vector2(25, 95), cr[1])
		_lock(Vector2(36, 79), Vector2(34, 88), Vector2(40, 95), 3.2, 1.0, cr, -0.04)
		_curve(Vector2(66, 78), Vector2(73, 84), Vector2(78, 95), cr[1])
		_curve(Vector2(66, 80), Vector2(68, 87), Vector2(71, 91), cr[4])
	if _armored():
		_armor()
	else:
		_poly([44, 75+s, 55, 75+s, 62, 95, 38, 95, 45, 83+s], cr[2])
		if elder:
			_poly([44, 78, 55, 79, 58, 95, 40, 95], cr[3])
			_curve(Vector2(45, 82), Vector2(50, 87), Vector2(57, 88), cr[5])
			_curve(Vector2(43, 86), Vector2(47, 91), Vector2(55, 93), cr[1])
		elif female:
			_poly([44, 78, 56, 78, 54, 84, 47, 85], Color("#c9b38c"))
			_curve(Vector2(42, 85), Vector2(51, 89), Vector2(59, 85), cr[4])
		else:
			_poly([44, 74, 55, 74, 52, 82, 48, 83], Color("#c9b38c"))
			_line(Vector2(49, 84), Vector2(50, 95), cr[0])
			for y in range(85, 95, 4):
				_line(Vector2(48, y), Vector2(52, y+1), sec.darkened(0.28))
	# Cloth gathers at a differently placed clasp on each costume.
	_oval(Vector2(bx, by), 3.2, 2.7, sec.darkened(0.52))
	_oval(Vector2(bx-0.4, by-0.5), 2.3, 1.8, sec)
	_px(bx-1, by-1, sec.lightened(0.35))
	_px(bx+1, by, sec.darkened(0.28))

func _armored() -> bool:
	var name := (String(body.get("sprite", "")) + " " + String(body.get("tid", ""))).to_lower()
	for kind in ARMOR:
		if kind in name:
			return true
	return false

func _metal(item: Dictionary) -> Array[Color]:
	var name := String(item.get("mat", "iron"))
	var m: Dictionary = FigurePainter.metal(name if name != "" else "iron", int(item.get("q", 0)))
	var dark: Color = m["dark"]
	var base: Color = m["base"]
	var light: Color = m["light"]
	var shine: Color = m["shine"]
	return [dark.darkened(0.36).lerp(INK, 0.20), dark, dark.lerp(base, 0.5), base,
		base.lerp(light, 0.65), light, shine]

func _armor() -> void:
	var s := shoulder
	var mr := _metal(body)
	var name := (String(body.get("sprite", "")) + " " + String(body.get("tid", ""))).to_lower()
	# A broad cuirass: bevel, lit front, turned side and dark underarm joints.
	_poly([36, 74+s, 43, 73+s, 50, 77+s, 58, 73+s, 65, 77+s,
		68, 85+s, 71, 95, 29, 95, 32, 83+s], mr[1])
	_poly([36, 78+s, 43, 76+s, 50, 80+s, 52, 88+s, 49, 95,
		33, 95, 33, 86+s], mr[3])
	_poly([38, 79+s, 44, 78+s, 48, 81+s, 49, 88+s, 45, 95,
		35, 95, 35, 87+s], mr[4].lerp(mr[3], 0.40))
	_poly([52, 80+s, 59, 76+s, 64, 80+s, 65, 87+s, 69, 95,
		54, 95, 55, 88+s], mr[2])
	_poly([49, 81+s, 52, 80+s, 55, 89+s, 53, 95, 49, 95, 51, 88+s], mr[4])
	_curve(Vector2(38, 76+s), Vector2(49, 83+s), Vector2(61, 76+s), mr[0], 0.8)
	_curve(Vector2(38, 75+s), Vector2(49, 82+s), Vector2(61, 75+s), mr[5])
	_curve(Vector2(34, 88+s), Vector2(40, 90+s), Vector2(47, 88+s), mr[2])
	if "mail" in name or "byrnie" in name or "hauberk" in name:
		for y in range(int(81+s), SIZE, 3):
			for x in range(40 + (y % 2), 65, 4):
				_line(Vector2(x, y), Vector2(x+1, y+1), mr[0])
				_px(x+2, y, mr[5] if x < 51 else mr[3])
	elif "scale" in name or "lamellar" in name or "brigandine" in name:
		for y in range(int(83+s), SIZE, 5):
			_line(Vector2(39, y), Vector2(66, y+1), mr[1])
			for x in range(40 + (y % 2)*2, 65, 5):
				_px(x, y-1, mr[5])
	var turn := 2.0 if female else 0.0
	_poly([64, 76+s, 71, 77+s, 78-turn, 83+s, 78-turn, 87+s,
		68, 86+s, 62, 81+s], mr[1])
	_poly([65, 77+s, 71, 78+s, 76-turn, 82+s, 70, 82+s, 64, 80+s], mr[3])
	_curve(Vector2(65, 77+s), Vector2(73, 78+s), Vector2(76-turn, 82+s), mr[5])
	_curve(Vector2(66, 82+s), Vector2(71, 85+s), Vector2(77-turn, 85+s), mr[0])
	_poly([27+turn, 75+s, 34, 73+s, 40, 76+s, 41, 81+s, 35, 85+s,
		23+turn, 85+s, 21+turn, 81+s], mr[2])
	_poly([24+turn, 79+s, 31, 75+s, 35, 75+s, 39, 78+s, 34, 81+s,
		24+turn, 83+s], mr[4])
	_curve(Vector2(24+turn, 79+s), Vector2(31, 75+s), Vector2(37, 77+s), mr[5])
	_curve(Vector2(24+turn, 84+s), Vector2(33, 85+s), Vector2(40, 80+s), mr[0])
	_curve(Vector2(25+turn, 87+s), Vector2(32, 88+s), Vector2(37, 84+s), mr[3])
	for p in [Vector2(28+turn, 80+s), Vector2(36, 79+s), Vector2(70, 81+s)]:
		_px(int(p.x), int(p.y), mr[5])
		_px(int(p.x), int(p.y)+1, mr[0])
	if female:
		# A raised gorget and diagonal fastening distinguish this older officer's kit.
		_poly([40, 76+s, 45, 79+s, 52, 80+s, 58, 77+s, 59, 80+s,
			52, 83+s, 45, 82+s, 40, 79+s], mr[2])
		_curve(Vector2(41, 76+s), Vector2(50, 83+s), Vector2(58, 77+s), mr[5])
		_poly([58, 82+s, 61, 81+s, 68, 95, 64, 95], Color("#66503e"))
		_line(Vector2(60, 84+s), Vector2(65, 94), Color("#a0835a"))
		_line(Vector2(61, 87+s), Vector2(64, 86+s), sec.darkened(0.25))

func _neck() -> void:
	if _lost("neck"):
		_wound(int(cx), 68, 5)
		return
	var nw := 6.2 if female else (6.8 if young or elder else 8.0)
	for y in range(56, int(79+shoulder)):
		var t := clampf((float(y) - 61.0) / 16.0, 0.0, 1.0)
		var hw := nw + t * 2.0
		for x in range(int(cx+1.0-hw), int(cx+1.0+hw)+1):
			var u := (float(x) - cx) / hw
			var lit := 0.61 - u * 0.14 - t * 0.035 + sqrt(maxf(0.0, 1.0-u*u))*0.07
			if float(y) < chin + 3.0:
				lit -= 0.21
			if absf(u-0.46) < 0.13 and t > 0.35:
				lit -= 0.045
			_px(x, y, _tone(sr, lit))
	_line(Vector2(cx-4, chin+5), Vector2(cx-5, chin+7), sr[4].lerp(sr[5], 0.35))
	if not female and not young:
		_oval(Vector2(cx+1, 72), 1.8, 2.0, sr[3])

func _collar() -> void:
	var s := shoulder
	if elder and not _armored():
		_lock(Vector2(38, 73), Vector2(41, 81), Vector2(54, 83), 3.7, 2.2, cr, -0.02)
		_curve(Vector2(40, 76), Vector2(45, 81), Vector2(53, 81), cr[4])
		_curve(Vector2(42, 81), Vector2(47, 85), Vector2(57, 83), cr[1])
		return
	if female and young:
		_curve(Vector2(40, 73+s), Vector2(47, 85+s), Vector2(58, 73+s), cr[1], 1.6)
		_curve(Vector2(40, 72+s), Vector2(47, 84+s), Vector2(58, 72+s), cr[4])
		return
	_poly([38, 69+s, 41, 68+s, 44, 74+s, 49, 78+s, 45, 81+s, 37, 75+s], cr[2])
	_poly([38, 69+s, 41, 69+s, 43, 74+s, 47, 78+s, 45, 78+s, 39, 74+s], cr[5])
	_poly([57, 69+s, 60, 72+s, 57, 77+s, 51, 80+s, 50, 77+s, 55, 73+s], cr[1])
	_line(Vector2(57, 70+s), Vector2(54, 75+s), cr[4])

func _half(y: float) -> float:
	# Independent malar, jaw and chin widths, measured in native portrait pixels.
	var cheeks := Vector2(0.94, 0.84)
	var jaw := Vector2(0.72, 0.56)
	var tip := 0.29
	if not female and not young and not elder:
		cheeks = Vector2(0.95, 0.86)
		jaw = Vector2(0.81, 0.67)
		tip = 0.38
	elif elder and not female:
		cheeks = Vector2(0.90, 0.77)
		jaw = Vector2(0.80, 0.61)
		tip = 0.32
	elif female and young:
		cheeks = Vector2(0.98, 0.83)
		jaw = Vector2(0.65, 0.43)
		tip = 0.23
	elif female:
		cheeks = Vector2(0.96, 0.79)
		jaw = Vector2(0.76, 0.56)
		tip = 0.30
	var profile := [Vector2(top, 0.34), Vector2(top+6, 0.79), Vector2(34, 0.97),
		Vector2(43, 1.0), Vector2(48, cheeks.x), Vector2(53, cheeks.y),
		Vector2(57, jaw.x), Vector2(61, jaw.y), Vector2(chin-1, tip), Vector2(chin+1, 0.09)]
	for i in range(1, profile.size()):
		var a: Vector2 = profile[i-1]
		var b: Vector2 = profile[i]
		if y <= b.x:
			return lerpf(a.y, b.y, clampf((y-a.x)/(b.x-a.x), 0.0, 1.0)) * width
	return 0.0

func _soft(x: float, y: float, ax: float, ay: float, rx: float, ry: float) -> float:
	var d := Vector2((x-ax)/rx, (y-ay)/ry).length_squared()
	return maxf(0.0, 1.0-d) * maxf(0.0, 1.0-d)

func _face() -> void:
	for y in range(int(top), int(chin)+1):
		var hw := _half(float(y)+0.5)
		var center := cx + smoothstep(36.0, chin, float(y)) * 0.9
		for x in range(int(center-hw)-1, int(center+hw)+1):
			var u := (float(x)+0.5-center) / hw
			if absf(u) > 1.0:
				continue
			var fx := float(x)+0.5
			var fy := float(y)+0.5
			var lit := 0.64 - u * 0.14 - (fy-35.0)*0.001
			lit += 0.10*sqrt(maxf(0.0, 1.0-u*u))
			lit += _soft(fx, fy, cx-5, 29, 10, 9)*0.08
			lit += _soft(fx, fy, cx-9, 46, 7, 4)*0.10
			lit += _soft(fx, fy, cx+10, 46, 5, 3)*0.10
			lit -= _soft(fx, fy, cx-8, ey-1, 6, 3)*0.12
			lit -= _soft(fx, fy, cx+7, ey, 5, 3)*0.14
			lit -= _soft(fx, fy, cx+4, 47, 3.5, 5)*0.08
			lit -= _soft(fx, fy, cx-11, 53, 5, 4)*(0.21 if elder else (0.05 if young else 0.13))
			lit -= _soft(fx, fy, cx+12, 52, 5, 5)*(0.20 if elder else (0.08 if young else 0.15))
			lit += _soft(fx, fy, cx-9, 57, 4, 3)*(0.06 if elder else 0.0)
			lit -= _soft(fx, fy, cx+1, my+3, 6, 2)*0.09
			lit += _soft(fx, fy, cx-1, chin-3, 6, 2.5)*0.10
			lit -= _soft(fx, fy, cx-1, 51, 4, 2)*0.045
			if absf(u) > 0.85:
				lit -= (absf(u)-0.85)*0.70
			var col := _tone(sr, lit)
			# Subtle living warmth on the cheeks, separate from light and shadow.
			var blush := _soft(fx, fy, cx-10, ey+8, 5, 4)+_soft(fx, fy, cx+10, ey+8, 4, 4)
			if not dead:
				col = col.lerp(col.lerp(Color("#bd7463"), 0.30), blush*(0.32 if young else 0.16))
			_px(x, y, col)

func _ear(side: int) -> void:
	var x := cx+float(side)*(width-0.3)
	if _lost("ear_r" if side < 0 else "ear_l"):
		_wound(int(x), ey+3, 2)
		return
	var c := Vector2(x, ey+3)
	_oval(c, 3.4 if side < 0 else 2.8, 6.3 if elder else 5.7, skin, sr, 0.0 if side < 0 else -0.15)
	_line(c+Vector2(side, -3), c+Vector2(side*1.6, 1), sr[2])
	_line(c+Vector2(0, -2), c+Vector2(side, -3), sr[5] if side < 0 else sr[3])
	_line(c+Vector2(0, 0), c+Vector2(side, 2), sr[1])
	_px(int(x), ey+6, sr[4])

func _eye(x: int, y: int, near: bool) -> void:
	var id := "eye_r" if near else "eye_l"
	var w := 4 if near else 3
	var lid := skin.lerp(INK, 0.60 if female else 0.67)
	var brow := hr[1].lerp(sr[2], 0.25)
	if elder:
		brow = hr[2].lerp(sr[2], 0.48)
	# A relaxed youth, a heavier adult brow and a lifted, open elder gaze.
	for dx in range(-w, w+1):
		var arch := -1 if dx >= -2 and dx <= 1 else 0
		var tilt := 1 if not young and not elder and dx > 1 and near else 0
		var by := y-4+arch+tilt-(1 if elder and near else 0)
		_px(x+dx, by, brow)
		if not female and not young and not elder and absi(dx) < w:
			_px(x+dx, by+1, brow.lerp(sr[3], 0.35))
	if _lost(id):
		_wound(x, y, 3)
		return
	if dead:
		_line(Vector2(x-w, y), Vector2(x, y+1), lid)
		_line(Vector2(x, y+1), Vector2(x+w, y), lid)
		return
	# Two-pixel irises leave lit sclera visible on both sides, including elders.
	var height := 3
	for dx in range(-w, w+1):
		var edge := absi(dx) == w
		var corner := absi(dx) >= w-1
		_px(x+dx, y-1 if not corner else y, lid.lerp(sr[3], 0.16 if corner else 0.0))
		if not edge:
			for dy in range(1 if corner else 0, 2 if corner else height):
				_px(x+dx, y+dy, WHITE.darkened(0.055*dy+(0.02 if near else 0.07)))
	var iris := [Color("#526d6b"), Color("#8b633d"), Color("#46647d"), Color("#596c42"), Color("#6b4933")][seed % 5] as Color
	var ix := x
	for dy in range(0, height):
		_px(ix, y+dy, iris)
		_px(ix+1, y+dy, iris.darkened(0.26))
	_px(ix+1, y, INK)
	_px(ix+1, y+1, INK)
	_px(ix, y, WHITE)
	_px(ix, y+2, iris.lightened(0.20))
	_px(x-w, y+1, sr[3])
	_px(x+w, y+1, sr[3])
	_line(Vector2(x-2, y+3), Vector2(x+1, y+3), sr[4].lerp(sr[3], 0.25))
	_px(x-2, y+4, sr[5] if near else sr[4])
	_px(x-1, y+4, sr[5] if near else sr[4])
	if female:
		_px(x-w-1 if near else x+w+1, y-1, lid)

func _nose() -> void:
	if _lost("nose"):
		return
	var nx := int(cx)+1
	var tip := ey + (10 if female or young else 12)
	var broad := 2.5 if female or young else 3.3
	for y in range(ey+1, tip+1):
		var t := float(y-ey)/float(tip-ey)
		var ridge := float(nx)-0.6+t*0.4
		for x in range(nx-2, nx+4):
			var u := (float(x)+0.5-ridge)/3.0
			if absf(u) < 1.0:
				var light := 0.72-u*0.12+sin(t*PI)*0.025
				_px(x, y, _tone(sr, light))
	_oval(Vector2(nx, tip), broad, 1.8, sr[4], sr, 0.06)
	_line(Vector2(nx-1, tip-1), Vector2(nx, tip-1), sr[6].lerp(sr[5], 0.4))
	_px(nx-int(broad)+1, tip+1, sr[1].lerp(sr[3], 0.35))
	_px(nx+int(broad), tip, sr[2])
	_px(nx+1, tip+2, sr[3])
	_px(nx, tip+3, sr[4])

func _mouth() -> void:
	if _lost("mouth") or _lost("jaw"):
		return
	var x := int(cx)+1
	var y := my
	var lip := skin.lerp(Color("#a25755"), 0.48 if female else 0.31)
	var dark := skin.lerp(Color("#503039"), 0.58)
	var w := (4 if elder else 5) if female else (5 if young else 6)
	# A broad, shallow cupid's bow and a rounded lower lip; corners stay relaxed.
	_poly([x-w, y, x-2, y-2, x, y-1, x+2, y-2, x+w, y,
		x+2, y+1, x-2, y+1], lip.darkened(0.10))
	_poly([x-w+1, y+1, x+w-1, y+1, x+2, y+3, x-2, y+3], lip.lerp(sr[5], 0.18))
	_curve(Vector2(x-w, y), Vector2(x, y+0.5), Vector2(x+w, y-(1 if young and not female else 0)), dark)
	_line(Vector2(x-2, y+2), Vector2(x+1, y+2), lip.lerp(sr[6], 0.45))
	_px(x-w, y+1, sr[3])
	_px(x+w, y+1, sr[3])
	if young and not female:
		_px(x-w-1, y-1, sr[3].lerp(sr[4], 0.5))
	if elder:
		_px(x+w+1, y+2, sr[3])

func _age_lines() -> void:
	if not elder:
		if not young:
			_line(Vector2(cx+8, my-3), Vector2(cx+9, my-1), sr[3])
		return
	var crease := sr[3].lerp(sr[4], 0.35)
	# Short creases sit in the cheek hollows already shaded by _face.
	for yy in [28, 32]:
		_line(Vector2(cx-7, yy), Vector2(cx-4, yy-1), crease)
		_line(Vector2(cx, yy-1), Vector2(cx+3, yy-1), crease)
		_px(int(cx)+5, yy, crease)
		_line(Vector2(cx-6, yy-1), Vector2(cx-4, yy-2), sr[5])
	for side in [-1, 1]:
		var x: float = cx+side*8
		var sy := ey+(0 if side < 0 else 1)
		_line(Vector2(x+side*5, sy+1), Vector2(x+side*6, sy+2), crease)
		_px(int(x+side*6), sy-2, crease)
		_line(Vector2(x-2, sy+5), Vector2(x, sy+5), crease)
		_px(int(x)+2, sy+4, crease)
		_line(Vector2(cx+side*7, my-4), Vector2(cx+side*8, my-2), crease)
		_px(int(cx+side*9), my+1, crease)
		_line(Vector2(cx+side*12, 49), Vector2(cx+side*11, 50), crease)
		_px(int(cx+side*10), 53, crease)
	_line(Vector2(cx-3, chin-2), Vector2(cx, chin-2), sr[3].lerp(sr[4], 0.5))

func _lock(a: Vector2, b: Vector2, c: Vector2, r0: float, r1: float, ramp: Array[Color], bias: float = 0.0) -> void:
	# A tapered Bezier ribbon. Its local cylindrical lighting follows the bend.
	const STEPS := 20
	var pts := PackedVector2Array()
	var bounds := Rect2(a, Vector2.ZERO)
	for i in range(STEPS+1):
		var t := float(i)/STEPS
		var p := (1.0-t)*(1.0-t)*a + 2.0*(1.0-t)*t*b + t*t*c
		pts.append(p)
		bounds = bounds.expand(p)
	bounds = bounds.grow(maxf(r0, r1)+2.0)
	for y in range(maxi(0, int(floor(bounds.position.y))), mini(SIZE, int(ceil(bounds.end.y))+1)):
		for x in range(maxi(0, int(floor(bounds.position.x))), mini(SIZE, int(ceil(bounds.end.x))+1)):
			var p := Vector2(float(x)+0.5, float(y)+0.5)
			var d2 := INF
			var along := 0.0
			var center := Vector2.ZERO
			var tangent := Vector2.DOWN
			for i in range(STEPS):
				var seg := pts[i+1]-pts[i]
				var t := clampf((p-pts[i]).dot(seg)/maxf(0.001, seg.length_squared()), 0.0, 1.0)
				var closest := pts[i]+seg*t
				var dist := p.distance_squared_to(closest)
				if dist < d2:
					d2 = dist
					along = (float(i)+t)/STEPS
					center = closest
					tangent = seg.normalized()
			var rad := lerpf(r0, r1, pow(along, 1.35)) + sin(along*PI)*r0*0.12
			if d2 > rad*rad:
				continue
			var normal := Vector2(-tangent.y, tangent.x)
			var across := clampf((p-center).dot(normal)/maxf(rad, 0.25), -1.0, 1.0)
			var lit := 0.54 + sqrt(maxf(0.0, 1.0-across*across))*0.10 - absf(across)*0.08
			lit += across*normal.dot(Vector2(-0.70, -0.71))*0.10
			lit += bias - along*0.045 - (float(x)-40.0)*0.002
			# Flattened locks share one mass of light. Glints stop at bends.
			if across > -0.55 and across < -0.10 and ((along > 0.17 and along < 0.34) or (along > 0.57 and along < 0.64)):
				lit += 0.055
			if across > 0.76:
				lit -= 0.08
			if along > 0.94:
				lit -= 0.04
			_px(x, y, _tone(ramp, lit))

func _hlock(a: Vector2, b: Vector2, c: Vector2, r0: float, r1: float, bias: float = 0.0) -> void:
	_lock(a, b, c, r0, r1, hr, bias)

func _hair_mass(coords: Array, bias: float = 0.0) -> void:
	var pts := _points(coords)
	for y in range(7, 86):
		for x in range(21, 77):
			if not Geometry2D.is_point_in_polygon(Vector2(x+0.5, y+0.5), pts):
				continue
			var lit := 0.65 - (float(x)-cx)*0.007 - maxf(0.0, float(y)-26.0)*0.0025 + bias
			lit += _soft(x, y, cx-7, 17, 14, 8)*0.10
			lit -= _soft(x, y, cx+17, 31, 7, 14)*0.10
			_px(x, y, _tone(hr, lit))

func _hair_back() -> void:
	if female and not elder:
		_hair_mass([cx-16, 22, cx-22, 33, cx-24, 48, cx-22, 59, cx-24, 69,
			cx-21, 78, cx-16, 81, cx-12, 73, cx-14, 58, cx-12, 43, cx-9, 28], -0.13)
		_hair_mass([cx+12, 22, cx+20, 30, cx+23, 44, cx+22, 54, cx+25, 64,
			cx+22, 76, cx+16, 80, cx+12, 72, cx+15, 58, cx+12, 42], -0.22)
		_hlock(Vector2(cx-18, 32), Vector2(cx-22, 51), Vector2(cx-18, 70), 4.8, 1.8, -0.03)
		_hlock(Vector2(cx+19, 34), Vector2(cx+16, 53), Vector2(cx+21, 70), 4.0, 1.3, -0.14)
	elif female:
		_oval(Vector2(cx+17, 25), 7.5, 9, hair, hr, -0.22)
		_curve(Vector2(cx+16, 18), Vector2(cx+26, 25), Vector2(cx+16, 31), hr[2])
		_hair_mass([cx-15, 26, cx-20, 35, cx-19, 50, cx-14, 65, cx-10, 66, cx-12, 42], -0.17)
		_hair_mass([cx+14, 27, cx+19, 33, cx+18, 50, cx+13, 60, cx+12, 44], -0.23)
	elif elder:
		for side in [-1, 1]:
			var d := float(side)
			_hlock(Vector2(cx+d*15, 25), Vector2(cx+d*21, 39), Vector2(cx+d*16, 57), 4.0, 1.4, -0.08 if side < 0 else -0.19)
	elif not young:
		for side in [-1, 1]:
			var d := float(side)
			_hlock(Vector2(cx+d*17, 24), Vector2(cx+d*23, 37), Vector2(cx+d*18, 52), 3.8, 1.0, -0.08 if side < 0 else -0.18)
	else:
		_hlock(Vector2(cx-14, 24), Vector2(cx-24, 36), Vector2(cx-16, 52), 4.2, 0.5)
		_hlock(Vector2(cx+13, 24), Vector2(cx+23, 36), Vector2(cx+17, 49), 4.0, 0.4, -0.15)

func _hair_front() -> void:
	if elder and not female:
		_hair_mass([cx-18, 42, cx-21, 31, cx-19, 23, cx-13, 17, cx-6, 16,
			cx-3, 19, cx-12, 22, cx-16, 29, cx-16, 37], -0.02)
		_hair_mass([cx+6, 18, cx+13, 19, cx+19, 25, cx+21, 35, cx+18, 43,
			cx+16, 32, cx+13, 25, cx+9, 23], -0.12)
		_hlock(Vector2(cx-7, 18), Vector2(cx-3, 11), Vector2(cx+7, 17), 2.5, 0.4, 0.05)
		_curve(Vector2(cx-18, 29), Vector2(cx-17, 23), Vector2(cx-11, 21), hr[5])
		_line(Vector2(cx+15, 25), Vector2(cx+17, 29), hr[4])
		return
	if not female:
		if young:
			_hair_mass([cx-21, 33, cx-21, 26, cx-17, 18, cx-8, 12, cx+1, 8,
				cx+10, 11, cx+17, 17, cx+20, 24, cx+19, 34, cx+16, 37, cx+13, 27,
				cx+8, 25, cx+2, 26, cx-5, 30, cx-11, 34, cx-16, 41, cx-19, 39])
			_hlock(Vector2(cx+9, 20), Vector2(cx-8, 21), Vector2(cx-17, 36), 5.0, 0.6, -0.015)
			_curve(Vector2(cx+8, 18), Vector2(cx+4, 17), Vector2(cx-2, 21), hr[1])
			_curve(Vector2(cx-9, 26), Vector2(cx-13, 30), Vector2(cx-16, 34), hr[2])
			_curve(Vector2(cx-16, 24), Vector2(cx-13, 20), Vector2(cx-9, 18), hr[4])
			_curve(Vector2(cx-5, 16), Vector2(cx, 13), Vector2(cx+4, 14), hr[4])
			_line(Vector2(cx-10, 17), Vector2(cx-7, 16), hr[5])
			_curve(Vector2(cx-6, 25), Vector2(cx-2, 22), Vector2(cx+2, 22), hr[4])
		else:
			_hair_mass([cx-22, 32, cx-21, 24, cx-17, 18, cx-10, 14, cx-2, 15,
				cx+6, 12, cx+13, 15, cx+20, 22, cx+22, 32, cx+19, 39, cx+16, 34,
				cx+14, 27, cx+7, 25, cx, 28, cx-8, 28, cx-14, 31, cx-18, 38], -0.05)
			_poly([cx-17, 24, cx-12, 19, cx-3, 19, cx+5, 16, cx+12, 18,
				cx+4, 20, cx-5, 23, cx-13, 25], hr[4])
			_curve(Vector2(cx+14, 23), Vector2(cx+4, 21), Vector2(cx-6, 25), hr[1])
			_line(Vector2(cx-16, 27), Vector2(cx-12, 25), hr[2])
			_curve(Vector2(cx-13, 21), Vector2(cx-9, 17), Vector2(cx-5, 17), hr[3])
			_line(Vector2(cx+5, 15), Vector2(cx+8, 16), hr[5])
		_hlock(Vector2(cx-19, 29), Vector2(cx-21, 37), Vector2(cx-18, 47), 2.5, 0.5, -0.08)
		_hlock(Vector2(cx+18, 29), Vector2(cx+20, 38), Vector2(cx+18, 47), 2.5, 0.4, -0.18)
	elif elder:
		var d := -part
		_hair_mass([cx-d*20, 34, cx-d*19, 24, cx-d*14, 17, cx-d*5, 11,
			cx+d*5, 10, cx+d*14, 15, cx+d*19, 24, cx+d*18, 36, cx+d*15, 39,
			cx+d*13, 28, cx+d*5, 24, cx-d*3, 23, cx-d*10, 28, cx-d*15, 37], -0.10)
		_poly([cx-d*15, 24, cx-d*9, 17, cx, 13, cx+d*8, 14, cx+d*2, 17,
			cx-d*5, 20, cx-d*12, 27], hr[4].lerp(hr[5], 0.5))
		_curve(Vector2(cx+d*11, 18), Vector2(cx-d*3, 18), Vector2(cx-d*15, 31), hr[2])
		_curve(Vector2(cx+d*14, 23), Vector2(cx+d*8, 20), Vector2(cx+d*5, 21), hr[3])
		_poly([cx+d*13, 25, cx+d*17, 28, cx+d*16, 36, cx+d*13, 32], hr[2].lerp(hr[3], 0.5))
		_line(Vector2(cx-d*8, 18), Vector2(cx-d*5, 16), hr[5])
		_curve(Vector2(cx-d*10, 23), Vector2(cx-d*7, 20), Vector2(cx-d*3, 19), hr[3])
		_braid(cx-16.5, 48, 83)
		_hlock(Vector2(cx-16, 29), Vector2(cx-21, 41), Vector2(cx-16, 54), 3.6, 1.4, -0.17)
		_hlock(Vector2(cx+16, 29), Vector2(cx+18, 39), Vector2(cx+16, 47), 2.0, 0.5, -0.16)
	else:
		var d := part
		_hair_mass([cx-d*21, 34, cx-d*20, 25, cx-d*15, 17, cx-d*7, 12, cx+d*2, 9,
			cx+d*11, 11, cx+d*18, 18, cx+d*21, 28, cx+d*20, 40, cx+d*16, 42,
			cx+d*13, 31, cx+d*7, 25, cx+d*3, 24, cx-d*4, 27, cx-d*12, 34, cx-d*18, 41])
		_poly([cx-d*17, 26, cx-d*10, 18, cx, 13, cx+d*8, 13, cx+d*2, 17,
			cx-d*6, 22, cx-d*14, 30], hr[5])
		_curve(Vector2(cx+d*5, 17), Vector2(cx-d*2, 19), Vector2(cx-d*8, 25), hr[2])
		_curve(Vector2(cx-d*11, 28), Vector2(cx-d*14, 31), Vector2(cx-d*16, 34), hr[3])
		_curve(Vector2(cx+d*7, 16), Vector2(cx+d*18, 20), Vector2(cx+d*18, 31), hr[2])
		_poly([cx+d*6, 21, cx+d*10, 22, cx+d*14, 27, cx+d*13, 32,
			cx+d*9, 26, cx+d*5, 24], hr[3])
		_line(Vector2(cx-d*11, 22), Vector2(cx-d*7, 19), hr[6].lerp(hr[5], 0.5))
		_hair_mass([cx-18, 33, cx-22, 44, cx-21, 53, cx-18, 62, cx-19, 72,
			cx-16, 76, cx-13, 67, cx-15, 56, cx-15, 46, cx-12, 33], -0.03)
		_curve(Vector2(cx-19, 39), Vector2(cx-21, 44), Vector2(cx-20, 48), hr[3])
		_hlock(Vector2(cx-18, 49), Vector2(cx-19, 55), Vector2(cx-15, 60), 2.7, 0.7, 0.0)
		_curve(Vector2(cx-18, 58), Vector2(cx-14, 64), Vector2(cx-17, 70), hr[4])
		_hlock(Vector2(cx-19, 63), Vector2(cx-14, 69), Vector2(cx-23, 73), 2.6, 0.6, -0.02)
		_hlock(Vector2(cx+17, 33), Vector2(cx+15, 47), Vector2(cx+21, 58), 4.2, 1.8, -0.12)
		_curve(Vector2(cx+19, 39), Vector2(cx+17, 47), Vector2(cx+20, 52), hr[2])

func _braid(x: float, y0: int, y1: int) -> void:
	_hlock(Vector2(x, y0), Vector2(x+3, (y0+y1)*0.5), Vector2(x, y1), 3.5, 1.7, -0.17)
	for y in range(y0+2, y1-2, 7):
		var t := float(y-y0)/float(y1-y0)
		var bx := x+sin(t*PI)*1.5
		var rad := lerpf(3.0, 1.6, t)
		_poly([bx-rad, y-2, bx, y-1, bx+rad, y+2, bx+rad-1, y+4, bx-1, y+2, bx-rad, y], hr[4])
		_line(Vector2(bx, y+2), Vector2(bx+rad-1, y+3), hr[2])
		if y < y0+12 or y > y1-10:
			_line(Vector2(bx-rad+1, y-1), Vector2(bx-1, y), hr[5])
	_line(Vector2(x-1, y1-1), Vector2(x+2, y1-1), sec.darkened(0.25))
	_hlock(Vector2(x+0.5, y1), Vector2(x+1.5, y1+3), Vector2(x, y1+5), 1.7, 0.2)

func _beard_mass(coords: Array, x: float, y0: float, bottom: float, half: float) -> void:
	var pts := _points(coords)
	for y in range(int(y0)-1, mini(89, int(bottom)+2)):
		for xx in range(int(x-half)-2, int(x+half)+3):
			if not Geometry2D.is_point_in_polygon(Vector2(xx+0.5, y+0.5), pts):
				continue
			var u := (float(xx)+0.5-x)/half
			var v := (float(y)-y0)/maxf(1.0, bottom-y0)
			var lit := 0.52-u*0.30-v*0.10+sqrt(maxf(0.0, 1.0-u*u))*0.12
			lit -= _soft(xx, y, x, my+3, 7, 4)*0.19
			lit -= _soft(xx, y, x+half-1, my+7, 4, 7)*0.10
			_px(xx, y, _tone(br, lit))

func _beard() -> void:
	if not beard or _lost("jaw") or _lost("mouth"):
		return
	var x := cx+1
	if beard_style == 7:
		# Short scruff remains skin-coloured between sparse, directional strokes.
		for side in [-1, 1]:
			for i in range(6):
				var sx: float = x+side*(5+i)
				var sy := my+2+int(i/2.0)
				_line(Vector2(sx, sy), Vector2(sx-side, sy+1), br[2].lerp(sr[3], 0.50))
		_line(Vector2(x-3, chin-3), Vector2(x+3, chin-3), br[2].lerp(sr[3], 0.5))
	elif beard_style != 6:
		var hang := 13.0 if elder else 8.0
		if female:
			hang *= 0.65
		if beard_style == 1:
			var bottom := chin+hang-1
			_beard_mass([x-4, my+3, x-6, my+6, x-6, chin, x-4, bottom-2,
				x-1, bottom, x+3, bottom-1, x+6, chin+1, x+5, my+4], x, my+3, bottom, 6.0)
			_curve(Vector2(x-4, my+7), Vector2(x-5, chin), Vector2(x-2, chin+3), br[4])
			_curve(Vector2(x+3, chin), Vector2(x+4, chin+3), Vector2(x+1, bottom-2), br[2])
			_line(Vector2(x-1, bottom-3), Vector2(x, bottom-1), br[4])
		else:
			var half := 13.5 if not young else 10.0
			var bottom := chin+(2.0 if beard_style == 8 else hang)
			var end_half := 3.0 if beard_style == 3 else 6.0
			_beard_mass([x-half, my-4, x-half+4, my+2, x-5, my+4, x+4, my+4,
				x+half-3, my+1, x+half, my-4, x+half+0.5, chin-5,
				x+half-3, chin+3, x+end_half, bottom-1, x+4, bottom+1,
				x+1, bottom, x-2, bottom+1, x-6, bottom-1, x-end_half-3, bottom-4,
				x-half+1, chin], x, my-4, bottom, half)
			# Short curved clumps interrupt a rounded base instead of scoring it vertically.
			_curve(Vector2(x-half+2, my+5), Vector2(x-half+3, chin), Vector2(x-7, chin+2), br[3])
			_curve(Vector2(x-half+4, my+8), Vector2(x-8, chin+1), Vector2(x-5, chin+3), br[5])
			_curve(Vector2(x+9, chin-2), Vector2(x+10, chin+2), Vector2(x+6, chin+6), br[1].lerp(br[2], 0.6))
			_curve(Vector2(x+5, chin-3), Vector2(x+7, chin+1), Vector2(x+4, chin+4), br[2])
			_curve(Vector2(x-5, chin-3), Vector2(x-6, chin), Vector2(x-4, chin+2), br[3])
			_curve(Vector2(x-4, bottom-6), Vector2(x-4, bottom-2), Vector2(x-1, bottom-1), br[4])
			_line(Vector2(x+2, bottom-4), Vector2(x+3, bottom-2), br[3])
			if beard_style == 4:
				_poly([x-1, bottom-4, x+2, bottom-4, x+2, bottom+1, x-1, bottom+1], cr[1])
			if beard_style == 5:
				for side in [-1, 1]:
					_line(Vector2(x+side*5-1, chin+8), Vector2(x+side*5+1, chin+8), sec)
	if beard_style != 7:
		_curve(Vector2(x-8, my+1), Vector2(x-3, my-1), Vector2(x, my), br[0], 0.8)
		_curve(Vector2(x+1, my), Vector2(x+6, my), Vector2(x+8, my+2), br[0], 0.8)
		_lock(Vector2(x-1, my-1), Vector2(x-6, my-3), Vector2(x-9, my+1), 2.1, 0.8, br, 0.04)
		_lock(Vector2(x+1, my-1), Vector2(x+6, my-3), Vector2(x+9, my+2), 2.0, 0.7, br, -0.12)
		# The moustache covers the upper lip; only the opening and lower plane show.
		_line(Vector2(x-4, my+1), Vector2(x+4, my+1), skin.lerp(Color("#503039"), 0.66))
		_line(Vector2(x-2, my+2), Vector2(x+2, my+2), skin.lerp(Color("#b16c61"), 0.35))
		_line(Vector2(x-1, my+3), Vector2(x+1, my+3), skin.lerp(sr[5], 0.5))

func _hood() -> void:
	var mr := _metal(helm)
	_poly([28, 22, 35, 13, 48, 10, 62, 15, 71, 29, 70, 60, 77, 76, 63, 81, 32, 80, 22, 73, 28, 54], mr[2], mr)
	_line(Vector2(29, 29), Vector2(28, 62), mr[5])
	_line(Vector2(66, 29), Vector2(68, 63), mr[1])

func _headgear() -> void:
	if helm_kind in ["none", "coif"]:
		return
	var mr := _metal(helm)
	if helm_kind == "crown":
		for i in range(5):
			var x := int(cx)-14+i*7
			var y := 23-absi(i-2)
			_poly([x-3, 28, x-2, y-5, x+1, y, x+3, y-4, x+4, 28], mr[3])
			_px(x-2, y-5, mr[6])
		_line(Vector2(cx-16, 28), Vector2(cx+17, 28), mr[6], 1.0)
		_line(Vector2(cx-16, 30), Vector2(cx+17, 30), mr[1])
		_oval(Vector2(cx+1, 28), 2, 2, sec)
		return
	if helm_kind == "closed":
		_poly([29, 24, 34, 15, 48, 11, 62, 15, 69, 25, 67, 53, 61, 64, 49, 68, 36, 62, 30, 51], mr[3], mr)
		_poly([48, 16, 51, 26, 52, 63, 49, 66, 47, 42], mr[5])
		_line(Vector2(34, 38), Vector2(46, 39), mr[0], 1.0)
		_line(Vector2(53, 39), Vector2(64, 37), mr[0], 1.0)
		_line(Vector2(34, 36), Vector2(46, 37), mr[6])
		for i in range(3):
			_line(Vector2(55+i*3, 49), Vector2(55+i*3, 55), mr[0])
		return
	_poly([26, 30, 28, 22, 34, 14, 47, 10, 59, 13, 66, 19, 70, 31, 66, 34, 29, 34], mr[3], mr)
	_line(Vector2(30, 31), Vector2(65, 32), mr[0], 1.0)
	_line(Vector2(30, 30), Vector2(65, 31), mr[5])
	_line(Vector2(47, 12), Vector2(49, 29), mr[6])
	if helm_kind == "kettle":
		_poly([26, 29, 66, 29, 78, 35, 73, 38, 23, 36, 20, 33], mr[2], mr)
		_line(Vector2(24, 33), Vector2(74, 35), mr[5])
	if helm_kind == "nasal":
		_poly([47, 30, 51, 30, 52, 49, 49, 51, 47, 49], mr[2])
		_line(Vector2(48, 31), Vector2(49, 49), mr[6])

func _wound(x: int, y: int, r: int) -> void:
	_oval(Vector2(x, y), r, r*0.7, BLOOD)
	_oval(Vector2(x+1, y), maxf(1.0, r*0.5), maxf(1.0, r*0.35), BLOOD.darkened(0.5))
	_line(Vector2(x, y+1), Vector2(x+1, y+r+2), BLOOD)

func _outline() -> void:
	var outline: Array[Vector2i] = []
	for y in range(1, SIZE-1):
		for x in range(1, SIZE-1):
			if image.get_pixel(x, y).a > 0.1:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q := Vector2i(x, y)+(d as Vector2i)
				if image.get_pixel(q.x, q.y).a > 0.5:
					outline.append(Vector2i(x, y))
					break
	for q in outline:
		_px(q.x, q.y, INK)
