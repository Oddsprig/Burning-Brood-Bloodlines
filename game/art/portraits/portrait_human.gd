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
	width = (16.5 if female else 18.5) + float(int(seed / 7.0) % 3 - 1) * 0.5
	top = 18.0 if elder else 20.0
	chin = 64.0 if young else 66.0
	if female:
		chin -= 1.0
	if elder:
		width -= 0.8
		top -= 1.0
	ey = 39 if young else 40
	my = 54 if young else 56
	shoulder = (3.0 if elder else 0.0) + (1.0 if female else 0.0)
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

func _torso() -> void:
	var s := shoulder
	var inset := 4.0 if female else (2.0 if elder else 0.0)
	_poly([39, 68+s, 31, 70+s, 22+inset, 74+s, 15+inset, 81+s, 11+inset, 95,
		87-inset, 95, 84-inset, 84+s, 77-inset, 78+s, 61, 71+s, 56, 68+s], prim, cr)
	# Rolled cloth has broad light-facing folds and narrow dark valleys.
	_poly([32, 72+s, 39, 70+s, 46, 77+s, 32, 86, 21, 95, 14+inset, 95, 22+inset, 81+s], cr[4])
	_poly([34, 75+s, 40, 74+s, 31, 84+s, 20+inset, 91, 25+inset, 80+s], cr[5])
	_poly([41, 77+s, 45, 78+s, 33, 95, 26, 95, 34, 85], cr[1])
	_poly([35, 84, 37, 84, 29, 95, 26, 95], cr[3])
	_poly([65, 75+s, 74-inset, 79+s, 82-inset, 91, 79-inset, 95, 73-inset, 86], cr[1])
	_poly([62, 78+s, 65, 78+s, 69, 94, 65, 95], cr[4])
	if _armored():
		_armor()
	else:
		# A linen inset and laced wool tunic, beneath an asymmetric travel cloak.
		_poly([43, 73+s, 56, 73+s, 61, 95, 39, 95, 44, 81+s], cr[2])
		_poly([44, 74+s, 55, 74+s, 51, 82+s, 48, 82+s], Color("#b7a78a"))
		_poly([44, 74+s, 53, 74+s, 49, 80+s], Color("#e3d2af"))
		_line(Vector2(49, 83+s), Vector2(48, 95), cr[0])
		for y in range(int(84+s), 95, 4):
			_line(Vector2(47, y), Vector2(51, y+1), sec.darkened(0.22))
	# Weight at the shoulder clasp, with a fold hanging from it.
	var bx := 36 if not female else 34
	var by := int(75+s)
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
	_poly([41, 73+s, 56, 73+s, 65, 79+s, 72, 95, 34, 95, 38, 81+s], mr[2], mr)
	# The chest ridge catches the window light; the far plane remains cool.
	_poly([48, 78+s, 53, 76+s, 57, 95, 50, 95], mr[4])
	_poly([53, 77+s, 58, 76+s, 63, 95, 57, 95], mr[2])
	_line(Vector2(41, 76+s), Vector2(51, 80+s), mr[0])
	_line(Vector2(51, 80+s), Vector2(60, 76+s), mr[0])
	_line(Vector2(41, 75+s), Vector2(51, 79+s), mr[6])
	_line(Vector2(51, 79+s), Vector2(60, 75+s), mr[4])
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
	# A smaller, turned far pauldron, articulated instead of spherical shoulders.
	_poly([65, 76+s, 72, 77+s, 78, 83+s, 77, 88+s, 67, 85+s, 63, 81+s], mr[2], mr)
	_line(Vector2(66, 77+s), Vector2(73, 80+s), mr[5])
	_line(Vector2(66, 83+s), Vector2(76, 86+s), mr[0])
	_poly([28, 75+s, 34, 73+s, 41, 77+s, 38, 83+s, 24, 85+s, 22, 81+s], mr[4], mr)
	_line(Vector2(25, 79+s), Vector2(35, 76+s), mr[6])
	_line(Vector2(25, 84+s), Vector2(37, 81+s), mr[1])
	_line(Vector2(27, 87+s), Vector2(36, 84+s), mr[4])
	for p in [Vector2(28, 79+s), Vector2(36, 78+s), Vector2(69, 81+s)]:
		_px(int(p.x), int(p.y), mr[6])
		_px(int(p.x)+1, int(p.y)+1, mr[0])

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
			var lit := 0.65 - u * 0.22 - t * 0.07
			if float(y) < chin + 3.0:
				lit -= 0.21
			if absf(u-0.46) < 0.13 and t > 0.35:
				lit -= 0.10
			_px(x, y, sr[_band(lit)])
	_line(Vector2(cx-4, chin+6), Vector2(cx-6, 75+shoulder), sr[5])
	if not female and not young:
		_oval(Vector2(cx+1, 72), 1.8, 2.0, sr[3])

func _collar() -> void:
	var s := shoulder
	_poly([38, 69+s, 41, 68+s, 44, 74+s, 49, 78+s, 45, 81+s, 37, 75+s], cr[2])
	_poly([38, 69+s, 41, 69+s, 43, 74+s, 47, 78+s, 45, 78+s, 39, 74+s], cr[5])
	_poly([57, 69+s, 60, 72+s, 57, 77+s, 51, 80+s, 50, 77+s, 55, 73+s], cr[1])
	_line(Vector2(57, 70+s), Vector2(54, 75+s), cr[4])

func _half(y: float) -> float:
	var t := (y - top) / (chin - top)
	var profile := [Vector2(0.0, 0.32), Vector2(0.10, 0.72), Vector2(0.25, 0.97),
		Vector2(0.43, 1.0), Vector2(0.59, 0.95), Vector2(0.73, 0.82 if female else 0.87),
		Vector2(0.85, 0.62 if female else 0.73), Vector2(0.95, 0.40 if female else 0.49), Vector2(1.01, 0.18)]
	for i in range(1, profile.size()):
		var a: Vector2 = profile[i-1]
		var b: Vector2 = profile[i]
		if t <= b.x:
			var w := lerpf(a.y, b.y, clampf((t-a.x)/(b.x-a.x), 0.0, 1.0))
			if young and t > 0.50 and t < 0.83:
				w += sin((t-0.50)/0.33*PI)*0.035
			elif not female and not elder and t > 0.70 and t < 0.94:
				w += sin((t-0.70)/0.24*PI)*0.035
			if elder and t > 0.52 and t < 0.80:
				w -= sin((t-0.52)/0.28*PI)*0.08
			return w * width
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
			var lit := 0.70 - u * 0.22 - (fy-35.0)*0.002
			lit += 0.07*sqrt(maxf(0.0, 1.0-u*u))
			lit += _soft(fx, fy, cx-6, 29, 10, 9)*0.10
			lit += _soft(fx, fy, cx-9, ey+7, 6, 4)*0.13
			lit += _soft(fx, fy, cx+9, ey+7, 5, 4)*0.06
			lit -= _soft(fx, fy, cx-8, ey, 6, 4)*0.17
			lit -= _soft(fx, fy, cx+7, ey+1, 5, 4)*0.20
			lit -= _soft(fx, fy, cx+4, ey+7, 3, 7)*0.16
			lit -= _soft(fx, fy, cx-12, ey+13, 5, 6)*(0.19 if elder else 0.08)
			lit -= _soft(fx, fy, cx+12, ey+13, 5, 6)*(0.23 if elder else 0.12)
			lit -= _soft(fx, fy, cx+1, my+3, 6, 2.5)*0.11
			lit += _soft(fx, fy, cx-1, chin-3, 7, 3)*0.09
			if absf(u) > 0.91:
				lit -= (absf(u)-0.91)*1.3
			var col := sr[_band(lit)]
			# Subtle living warmth on the cheeks, separate from light and shadow.
			var blush := _soft(fx, fy, cx-10, ey+8, 5, 4)+_soft(fx, fy, cx+10, ey+8, 4, 4)
			if not dead:
				col = col.lerp(skin.lerp(Color("#b65e54"), 0.32), blush*(0.22 if young else 0.10))
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
	var lid := skin.lerp(INK, 0.70)
	var brow := hr[1].lerp(sr[1], 0.24)
	if elder:
		brow = hr[2].lerp(sr[1], 0.30)
	# Two differently tilted brows avoid a rigid, identical expression.
	for dx in range(-w, w+1):
		var arch := -1 if absi(dx) < w-1 else 0
		var tilt := 1 if (dx > 1 and near and not young) else 0
		_px(x+dx, y-5+arch+tilt, brow)
		if not female:
			_px(x+dx, y-4+arch+tilt, hr[2].lerp(sr[2], 0.25))
	if _lost(id):
		_wound(x, y, 3)
		return
	if dead:
		_line(Vector2(x-w, y), Vector2(x, y+1), lid)
		_line(Vector2(x, y+1), Vector2(x+w, y), lid)
		return
	# Almond whites, a shadowed upper lid, three-pixel irises and a catchlight.
	var height := 2 if elder else 3
	for dx in range(-w, w+1):
		var edge := absi(dx) == w
		var corner := absi(dx) >= w-1
		_px(x+dx, y-1 if not corner else y, lid)
		if not edge:
			for dy in range(0 if not corner else 1, height):
				_px(x+dx, y+dy, WHITE.darkened(0.06*dy+(0.03 if near else 0.10)))
		if absi(dx) < w-1:
			_px(x+dx, y+height, sr[3] if near else sr[2])
	var iris := [Color("#526d6b"), Color("#8b633d"), Color("#46647d"), Color("#596c42"), Color("#6b4933")][seed % 5] as Color
	var ix := x
	for dy in range(0, height):
		_px(ix-1, y+dy, iris)
		_px(ix, y+dy, iris.darkened(0.38))
		_px(ix+1, y+dy, iris.darkened(0.16))
	_px(ix, y, INK)
	if not elder:
		_px(ix, y+1, INK)
	_px(ix-1, y, WHITE)
	_px(ix, y+height-1, iris.lightened(0.14))
	_px(x-w, y+1, sr[2])
	_px(x+w, y+1, sr[2])
	_line(Vector2(x-w+1, y+height+1), Vector2(x+1, y+height+1), sr[4] if not elder else sr[2])
	if female:
		_px(x-w-1 if near else x+w+1, y-1, lid)

func _nose() -> void:
	if _lost("nose"):
		return
	var nx := int(cx)+1
	var tip := ey + (10 if female else 11) + (1 if elder else 0)
	var broad := 3 if female or young else 4
	_poly([nx-1, ey+1, nx+1, ey+1, nx+2, tip-3, nx+broad, tip,
		nx+2, tip+2, nx-2, tip+1, nx-3, tip-1], sr[4])
	_line(Vector2(nx+2, ey+2), Vector2(nx+3, tip-2), sr[2])
	_line(Vector2(nx-1, ey+2), Vector2(nx-1, tip-3), sr[6])
	_oval(Vector2(nx, tip-1), 2.5, 1.9, sr[5])
	_px(nx-1, tip-2, sr[6])
	_line(Vector2(nx-3, tip+1), Vector2(nx-2, tip+1), sr[1])
	_line(Vector2(nx+2, tip+1), Vector2(nx+3, tip), sr[1])
	_px(nx, tip+2, sr[3])
	_px(nx+1, tip+3, sr[2])

func _mouth() -> void:
	if _lost("mouth") or _lost("jaw"):
		return
	var x := int(cx)+1
	var y := my
	var lip := skin.lerp(Color("#9a4e4b"), 0.54 if female else 0.38)
	var dark := skin.lerp(Color("#4a2832"), 0.66)
	var w := 4 if female or young else 5
	for dx in range(-w, w+1):
		var curve := 0
		if absi(dx) == w:
			curve = -1 if young and not dead else (1 if elder else 0)
		_px(x+dx, y+curve, dark)
		if absi(dx) < w-1:
			_px(x+dx, y-1, lip.darkened(0.14))
			_px(x+dx, y+1, lip)
			if female:
				_px(x+dx, y+2, lip.lerp(sr[5], 0.40))
	_px(x, y-1, sr[4])
	_px(x-2, y+2, lip.lerp(sr[6], 0.52))
	_px(x-1, y+2, lip.lerp(sr[6], 0.52))
	_line(Vector2(x-3, y+4), Vector2(x+2, y+4), sr[3])
	if young and not dead:
		_px(x-w, y, sr[3])
		_px(x+w, y, sr[3])

func _age_lines() -> void:
	if not elder:
		if not young:
			_line(Vector2(cx+7, my-4), Vector2(cx+9, my), sr[2])
		return
	# Broken creases follow the forehead, malar ridge and mouth; no all-over noise.
	for yy in [29, 33]:
		_line(Vector2(cx-8, yy), Vector2(cx-2, yy-1), sr[3])
		_line(Vector2(cx+1, yy-1), Vector2(cx+6, yy), sr[3])
		_line(Vector2(cx-7, yy-1), Vector2(cx-3, yy-2), sr[5])
	for side in [-1, 1]:
		var x: float = cx+side*8
		var sy := ey+(0 if side < 0 else 1)
		_line(Vector2(x+side*4, sy+1), Vector2(x+side*7, sy+3), sr[2])
		_line(Vector2(x+side*4, sy-1), Vector2(x+side*6, sy-2), sr[2])
		_line(Vector2(x-2, sy+4), Vector2(x+2, sy+4), sr[2])
		_line(Vector2(x-2, sy+3), Vector2(x+1, sy+3), sr[5] if side < 0 else sr[4])
		_line(Vector2(cx+side*6, my-4), Vector2(cx+side*8, my+1), sr[2])
		_line(Vector2(cx+side*7, my-4), Vector2(cx+side*9, my), sr[4])
		_line(Vector2(cx+side*12, ey+8), Vector2(cx+side*9, ey+12), sr[2])
		_line(Vector2(cx+side*11, ey+7), Vector2(cx+side*9, ey+9), sr[5] if side < 0 else sr[4])
	_line(Vector2(cx-4, chin-2), Vector2(cx+3, chin-2), sr[3])

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
			var lit := 0.20 + sqrt(maxf(0.0, 1.0-across*across))*0.45
			lit += across*normal.dot(Vector2(-0.70, -0.71))*0.20
			lit += bias - along*0.10 - (float(x)-40.0)*0.002
			# A continuous glint and a root-side groove, not periodic pixel speckles.
			if across > -0.45 and across < -0.18 and along > 0.12 and along < 0.72:
				lit += 0.08
			if along > 0.91:
				lit -= 0.07
			_px(x, y, ramp[_band(lit)])

func _hlock(a: Vector2, b: Vector2, c: Vector2, r0: float, r1: float, bias: float = 0.0) -> void:
	_lock(a, b, c, r0, r1, hr, bias)

func _hair_back() -> void:
	if female and not elder:
		for i in range(4):
			var f := float(i)
			_hlock(Vector2(cx-13+f*2, 25), Vector2(cx-29-f, 47+f*3), Vector2(cx-21+f*2, 78+f*2), 6.0-f*0.35, 0.8, 0.02-f*0.04)
			_hlock(Vector2(cx+12-f, 24), Vector2(cx+30-f, 48+f*3), Vector2(cx+20-f*2, 82-f*2), 6.5-f*0.4, 0.7, -0.12)
	elif female:
		# A pinned coil behind the far temple and loose hair at the nape.
		_oval(Vector2(cx+17, 26), 8, 11, hair, hr, -0.12)
		_hlock(Vector2(cx+16, 16), Vector2(cx+30, 26), Vector2(cx+17, 35), 3.2, 1.2, -0.07)
		_hlock(Vector2(cx+19, 19), Vector2(cx+11, 28), Vector2(cx+21, 30), 2.5, 0.5, -0.04)
		_hlock(Vector2(cx-14, 28), Vector2(cx-23, 46), Vector2(cx-13, 70), 5.0, 0.7)
		_hlock(Vector2(cx+15, 33), Vector2(cx+20, 49), Vector2(cx+13, 67), 4.0, 0.7, -0.15)
	elif elder:
		for side in [-1, 1]:
			var d := float(side)
			_hlock(Vector2(cx+d*13, 23), Vector2(cx+d*24, 40), Vector2(cx+d*17, 61), 4.5, 1.0, 0.02 if side < 0 else -0.12)
	elif not young:
		for side in [-1, 1]:
			var d := float(side)
			_hlock(Vector2(cx+d*14, 24), Vector2(cx+d*23, 44), Vector2(cx+d*16, 65), 5.0, 0.6, -0.04 if side < 0 else -0.14)
	else:
		_hlock(Vector2(cx-14, 24), Vector2(cx-24, 36), Vector2(cx-16, 52), 4.2, 0.5)
		_hlock(Vector2(cx+13, 24), Vector2(cx+23, 36), Vector2(cx+17, 49), 4.0, 0.4, -0.15)

func _hair_front() -> void:
	if elder and not female:
		# Visible scalp and an irregular receding hairline, rather than a silver cap.
		_hlock(Vector2(cx-2, 17), Vector2(cx-20, 12), Vector2(cx-18, 38), 3.2, 0.7, 0.08)
		_hlock(Vector2(cx-4, 19), Vector2(cx-18, 18), Vector2(cx-16, 31), 2.6, 0.4, 0.12)
		_hlock(Vector2(cx+5, 17), Vector2(cx+21, 17), Vector2(cx+18, 41), 3.8, 0.5, -0.10)
		_hlock(Vector2(cx+3, 16), Vector2(cx+15, 15), Vector2(cx+18, 30), 2.0, 0.4, 0.10)
		_hlock(Vector2(cx-8, 17), Vector2(cx-3, 10), Vector2(cx+9, 17), 1.9, 0.3, 0.15)
		_hlock(Vector2(cx-10, 19), Vector2(cx-5, 13), Vector2(cx+5, 18), 1.3, 0.2, 0.09)
		return
	var p := cx+part*(3.0 if female else 7.0)
	var d := part
	# Deliberately unequal locks: roots follow the part, tips fall diagonally.
	# Broad sweeps carry the volume; only a few thin glints describe strands.
	_hlock(Vector2(p+d*2, 18), Vector2(cx+d*23, 15), Vector2(cx+d*18, 39), 5.1, 0.6, -0.10)
	_hlock(Vector2(p+d*5, 21), Vector2(cx+d*22, 24), Vector2(cx+d*17, 43), 3.4, 0.4, -0.09)
	_hlock(Vector2(cx-d*9, 18), Vector2(cx-d*25, 25), Vector2(cx-d*17, 42), 5.0, 0.4, -0.03)
	_hlock(Vector2(p+d*2, 17), Vector2(cx+d*2, 5), Vector2(cx-d*11, 17), 4.6, 1.3, 0.07)
	_hlock(Vector2(p-d*1, 14), Vector2(cx-d*13, 8), Vector2(cx-d*19, 29), 4.9, 0.45, 0.13)
	_hlock(Vector2(p, 18), Vector2(cx-d*10, 16), Vector2(cx-d*15, 35 if not female else 39), 4.3, 0.4, 0.07)
	_hlock(Vector2(p-d*1, 21), Vector2(cx-d*3, 21), Vector2(cx-d*9, 32), 3.4, 0.3, 0.02)
	_hlock(Vector2(p+d*2, 22), Vector2(cx+d*1, 24), Vector2(cx-d*2, 29), 2.4, 0.2, -0.02)
	_hlock(Vector2(p-d*2, 12), Vector2(cx-d*12, 9), Vector2(cx-d*18, 24), 0.9, 0.15, 0.21)
	_hlock(Vector2(p+d*1, 16), Vector2(cx+d*15, 13), Vector2(cx+d*19, 29), 1.0, 0.15, 0.06)
	if female and elder:
		# Tucked temple hair exposes an older forehead rather than a heavy fringe.
		_hlock(Vector2(cx-7, 16), Vector2(cx+8, 11), Vector2(cx+17, 29), 3.3, 0.4, 0.09)
	if female and elder:
		_braid(cx-16.5, 48, 84)
		_hlock(Vector2(cx-16, 28), Vector2(cx-19, 40), Vector2(cx-14, 53), 2.8, 0.3, 0.04)
		_hlock(Vector2(cx+15, 30), Vector2(cx+18, 40), Vector2(cx+15, 47), 1.8, 0.2, -0.04)
	elif female:
		_hlock(Vector2(cx-16, 30), Vector2(cx-23, 49), Vector2(cx-15, 69), 3.7, 0.35, 0.13)
		_hlock(Vector2(cx-20, 58), Vector2(cx-13, 69), Vector2(cx-20, 76), 2.0, 0.25, 0.07)
		_hlock(Vector2(cx+17, 29), Vector2(cx+20, 48), Vector2(cx+24, 58), 3.4, 0.5, -0.07)
		_hlock(Vector2(cx+23, 56), Vector2(cx+18, 68), Vector2(cx+17, 77), 2.9, 0.3, -0.08)
	else:
		_hlock(Vector2(cx-17, 28), Vector2(cx-19, 37), Vector2(cx-16, 45), 2.3, 0.3, 0.02)
		_hlock(Vector2(cx+17, 29), Vector2(cx+20, 37), Vector2(cx+17, 45), 2.2, 0.3, -0.15)
		if young:
			_hlock(Vector2(p-3, 19), Vector2(cx-8, 23), Vector2(cx-11, 35), 2.4, 0.25, 0.02)

func _braid(x: float, y0: int, y1: int) -> void:
	for y in range(y0, y1, 5):
		var t := float(y-y0)/float(y1-y0)
		var bx := x+sin(t*PI)*2.2
		var rad := lerpf(3.2, 1.7, t)
		_hlock(Vector2(bx-rad*0.5, y), Vector2(bx+rad, y+2), Vector2(bx+0.5, y+5), rad*0.65, 0.7, 0.07)
		_hlock(Vector2(bx+rad*0.6, y), Vector2(bx-rad, y+2), Vector2(bx-0.5, y+5), rad*0.65, 0.6, -0.05)
	_line(Vector2(x-1, y1-1), Vector2(x+2, y1-1), sec.darkened(0.25))
	_hlock(Vector2(x+0.5, y1), Vector2(x+1.5, y1+3), Vector2(x, y1+5), 1.7, 0.2)

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
			# Tapered goatee rooted under the lower lip, with three curled clumps.
			for i in range(3):
				var dx := float(i-1)*3.2
				_lock(Vector2(x+dx, my+4), Vector2(x+dx*1.5, chin+3), Vector2(x+dx*0.5, chin+hang-absf(dx)*0.4), 3.0, 0.3, br, 0.07-float(i)*0.05)
		else:
			var half := 12.5 if not young else 10.0
			for i in range(7):
				var u := float(i-3)/3.0
				var root_y := my+3-absf(u)*5.0
				var end_x := x+u*half*0.55
				var end_y := chin+hang-absf(u)*6.0+float((i*3+seed)%5-2)
				if beard_style == 3:
					end_x = x+u*3.0
				elif beard_style == 4:
					end_x = x+signf(u)*5.0+u*2.0
					end_y -= (1.0-absf(u))*4.0
				elif beard_style == 8:
					end_y = chin+2.0-absf(u)*2.0
				_lock(Vector2(x+u*half, root_y), Vector2(x+u*(half+1)+sin(float(i)*2.1)*2.0, chin+3), Vector2(end_x, end_y), 3.4, 0.35, br, 0.04-u*0.10)
			if beard_style == 5:
				for side in [-1, 1]:
					_line(Vector2(x+side*5-1, chin+8), Vector2(x+side*5+1, chin+8), sec)
	if beard_style != 7:
		# Leave a real mouth opening between the two moustache wings.
		_lock(Vector2(x-1, my-3), Vector2(x-5, my-3), Vector2(x-7, my+1), 1.9, 0.35, br, 0.11)
		_lock(Vector2(x+1, my-3), Vector2(x+5, my-3), Vector2(x+7, my+2), 1.9, 0.35, br, -0.04)
		_mouth()

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
