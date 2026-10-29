extends RefCounted
## Moon elf busts: native 96px colour clusters, sculpted faces and silver hair.
## Equipment, wounds and the paint(spec) entry point remain local to this race.

const SIZE := 96
const INK := Color("#242b40")
const WHITE := Color("#eff6ff")
const BLOOD := Color("#a72e48")
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
var top := 18.0
var chin := 65.0
var width := 17.0
var ey := 39
var my := 54
var slope := 0.0
var skin := Color.WHITE
var prim := Color.WHITE
var sec := Color.WHITE
var sr: Array[Color] = []
var hr: Array[Color] = []
var br: Array[Color] = []
var cr: Array[Color] = []
var trim: Array[Color] = []
var beard := false
var beard_style := 0
var body: Dictionary = {}
var helm: Dictionary = {}
var helm_kind := "none"

static func paint(spec: Dictionary) -> Image:
	return load("res://art/portraits/portrait_moon_elf.gd").new()._render(spec)

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
	_shoulders()
	_neck()
	_collar()
	if _lost("head"):
		_wound(int(cx), 65, 7)
	elif helm_kind == "closed":
		_headgear()
	else:
		_face()
		if helm_kind != "coif":
			_hair_front()
		_ear(-1)
		_ear(1)
		_age_lines()
		_eye(int(cx)-7, ey, true)
		_eye(int(cx)+7, ey+(1 if elder else 0), false)
		_nose()
		_mouth()
		_beard()
		_headgear()
		if _lost("nose"):
			_wound(int(cx)+1, ey+11, 3)
		if _lost("jaw"):
			_wound(int(cx), int(chin)-2, 5)
	_outline()
	return image

func _read() -> void:
	seed = absi(int(spec.get("seed", 1)))
	female = String(spec.get("sex", "male")) == "female"
	var age := int(spec.get("age", 30))
	young = age < 86
	elder = age >= 300
	dead = bool(spec.get("dead", false))
	cx = 48.0 + float(seed % 3-1)*0.4
	width = (16.2 if female else (17.0 if young else (17.4 if elder else 18.8)))
	width += float(int(seed / 7.0) % 3-1)*0.25
	top = 18.0
	chin = (63.0 if young else 65.0) if female else (64.0 if young else 66.0)
	ey = 38 if young else 40
	my = (53 if young else 55) if female else (54 if young else 56)
	slope = (2.0 if female else 0.0) + (2.0 if elder else 0.0)
	var base := _color(spec.get("skin"), Color("#b7c6e3"))
	skin = base.lerp(Color("#acbddc"), 0.44)
	if elder:
		skin = skin.lerp(Color("#99aac7"), 0.15)
	var remain := clampf(float(spec.get("blood", 1.0)), 0.0, 1.0)
	skin = skin.lerp(Color("#c9cbd7"), (1.0-remain)*0.45)
	if dead:
		skin = skin.lerp(Color("#8e94aa"), 0.48)
	sr = [skin.lerp(Color("#29364f"), 0.76), skin.lerp(Color("#48597b"), 0.64),
		skin.darkened(0.27).lerp(Color("#7483a6"), 0.15), skin.darkened(0.12),
		skin, skin.lightened(0.12), skin.lightened(0.27).lerp(WHITE, 0.16)]
	hr = [Color("#354460"), Color("#506584"), Color("#7289aa"),
		Color("#9db2ce"), Color("#bfcee2"), Color("#dce7f4"), Color("#f2f7ff")]
	if elder:
		hr = [Color("#4c5873"), Color("#6a7c98"), Color("#8d9fb9"),
			Color("#b6c5da"), Color("#d5e0ed"), Color("#e9f0fa"), Color("#fbfcff")]
	prim = _color(spec.get("prim"), Color("#246a8c"))
	sec = _color(spec.get("sec"), Color("#a4c8e4"))
	cr = _ramp(prim)
	trim = _ramp(sec)
	beard_style = clampi(int(spec.get("beard_style", 0)), 0, 8)
	var b = spec.get("beard", false)
	var beard_color := Color("#b8cbe0") if elder else Color("#697f9e")
	if b is bool:
		beard = b
	elif b is Color:
		beard = true
		beard_color = b
	elif b is String:
		beard = b != "" and b != "false"
		beard_color = _color(b, beard_color)
	# Retain the adult moon elf's short jaw beard from the previous painter.
	if not female and not young and not elder and not beard and not dead:
		beard = true
		beard_style = 8
	if elder:
		beard_color = beard_color.lerp(Color("#d9e4f1"), 0.40)
	br = _ramp(beard_color)
	body = spec.get("body", {}) if spec.get("body", {}) is Dictionary else {}
	helm = spec.get("helm", {}) if spec.get("helm", {}) is Dictionary else {}
	lost = spec.get("lost", []) if spec.get("lost", []) is Array else []
	var name := (String(helm.get("sprite", ""))+" "+String(helm.get("tid", ""))).to_lower().strip_edges()
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

func _color(value: Variant, fallback: Color) -> Color:
	var col := fallback
	if value is Color:
		col = value
	elif value is String and Color.html_is_valid(String(value)):
		col = Color(String(value))
	col.a = 1.0
	return col

func _ramp(base: Color) -> Array[Color]:
	return [base.darkened(0.63).lerp(INK, 0.18), base.darkened(0.43),
		base.darkened(0.24), base.darkened(0.08), base,
		base.lightened(0.18).lerp(WHITE, 0.06), base.lightened(0.37).lerp(WHITE, 0.10)]

func _lost(id: String) -> bool:
	return id in lost

func _px(x: int, y: int, col: Color) -> void:
	if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
		image.set_pixel(x, y, Color(col.r, col.g, col.b, 1.0))

func _tone(ramp: Array[Color], light: float) -> Color:
	# Contiguous half-tones: no checkerboard, hatching or repeated strand marks.
	var value := clampf(floorf(light*12.0)*0.5, 0.0, 6.0)
	var low := int(value)
	return ramp[low].lerp(ramp[mini(low+1, 6)], value-float(low))

func _soft(x: float, y: float, ax: float, ay: float, rx: float, ry: float) -> float:
	var d := Vector2((x-ax)/rx, (y-ay)/ry).length_squared()
	return pow(maxf(0.0, 1.0-d), 2.0)

func _poly(coords: Array, col: Color, ramp: Array[Color] = [], bias: float = 0.0) -> void:
	var pts := PackedVector2Array()
	var lo := Vector2(SIZE, SIZE)
	var hi := Vector2.ZERO
	for i in range(0, coords.size(), 2):
		var p := Vector2(float(coords[i]), float(coords[i+1]))
		pts.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y))+1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x))+1)):
			if Geometry2D.is_point_in_polygon(Vector2(x+0.5, y+0.5), pts):
				var fill := col
				if not ramp.is_empty():
					fill = _tone(ramp, 0.81-float(x-22)*0.004-float(y-68)*0.006+bias)
				_px(x, y, fill)

func _oval(c: Vector2, rx: float, ry: float, col: Color, ramp: Array[Color] = [], bias: float = 0.0) -> void:
	for y in range(maxi(0, int(c.y-ry)), mini(SIZE, int(c.y+ry)+1)):
		for x in range(maxi(0, int(c.x-rx)), mini(SIZE, int(c.x+rx)+1)):
			var u := (float(x)+0.5-c.x)/rx
			var v := (float(y)+0.5-c.y)/ry
			if u*u+v*v > 1.0:
				continue
			var fill := col
			if not ramp.is_empty():
				fill = _tone(ramp, 0.56-u*0.20-v*0.15+sqrt(maxf(0.0, 1.0-u*u-v*v))*0.15+bias)
			_px(x, y, fill)

func _line(a: Vector2, b: Vector2, col: Color, radius: float = 0.45) -> void:
	var steps := maxi(1, int(ceil(a.distance_to(b)*2.0)))
	for i in range(steps+1):
		var p := a.lerp(b, float(i)/float(steps))
		if radius <= 0.5:
			_px(int(round(p.x)), int(round(p.y)), col)
		else:
			_oval(p, radius, radius, col)

func _curve(a: Vector2, control: Vector2, b: Vector2, col: Color, radius: float = 0.45) -> void:
	var previous := a
	for i in range(1, 21):
		var t := float(i)/20.0
		var p := a*(1.0-t)*(1.0-t)+control*2.0*t*(1.0-t)+b*t*t
		_line(previous, p, col, radius)
		previous = p

func _lock(a: Vector2, control: Vector2, b: Vector2, root: float, tip: float, ramp: Array[Color], bias: float = 0.0) -> void:
	# One convex clump with a broad light shoulder and a turned, dark underside.
	# Highlights swell at the bend; there are no periodic lines across its length.
	const STEPS := 18
	var pts := PackedVector2Array()
	var bounds := Rect2(a, Vector2.ZERO)
	for i in range(STEPS+1):
		var t := float(i)/float(STEPS)
		var p := a*(1.0-t)*(1.0-t)+control*2.0*t*(1.0-t)+b*t*t
		pts.append(p)
		bounds = bounds.expand(p)
	bounds = bounds.grow(maxf(root, tip)+2.0)
	for y in range(maxi(0, int(floor(bounds.position.y))), mini(SIZE, int(ceil(bounds.end.y))+1)):
		for x in range(maxi(0, int(floor(bounds.position.x))), mini(SIZE, int(ceil(bounds.end.x))+1)):
			var p := Vector2(x+0.5, y+0.5)
			var distance := INF
			var along := 0.0
			var center := Vector2.ZERO
			var tangent := Vector2.DOWN
			for i in range(STEPS):
				var seg := pts[i+1]-pts[i]
				var t := clampf((p-pts[i]).dot(seg)/maxf(0.001, seg.length_squared()), 0.0, 1.0)
				var q := pts[i]+seg*t
				var d := p.distance_squared_to(q)
				if d < distance:
					distance = d
					along = (float(i)+t)/float(STEPS)
					center = q
					tangent = seg.normalized()
			var radius := lerpf(root*0.88, tip, pow(along, 1.5))+sin(along*PI)*root*0.20
			if distance > radius*radius:
				continue
			var normal := Vector2(tangent.y, -tangent.x)
			if normal.x < 0.0:
				normal = -normal
			var across := clampf((p-center).dot(normal)/maxf(0.25, radius), -1.0, 1.0)
			var light := 0.57+bias-along*0.07-(float(x)-42.0)*0.002
			light += sqrt(maxf(0.0, 1.0-across*across))*0.14-across*0.16
			var shoulder := _soft(across, along, -0.30, 0.43, 0.64, 0.47)
			light += shoulder*0.13
			light -= smoothstep(0.42, 0.96, across)*0.14
			light -= smoothstep(0.84, 1.0, along)*0.06
			_px(x, y, _tone(ramp, light))

func _armored() -> bool:
	var name := (String(body.get("sprite", ""))+" "+String(body.get("tid", ""))).to_lower()
	for kind in ARMOR:
		if kind in name:
			return true
	return false

func _metal(item: Dictionary) -> Array[Color]:
	var mat := String(item.get("mat", "iron"))
	if mat == "":
		mat = "iron"
	var colors: Dictionary = FigurePainter.metal(mat, int(item.get("q", 0)))
	var base: Color = colors["base"]
	var dark: Color = colors["dark"]
	var light: Color = colors["light"]
	var shine: Color = colors["shine"]
	return [dark.darkened(0.22), dark, dark.lerp(base, 0.52), base,
		base.lerp(light, 0.5), light, shine]

func _shoulders() -> void:
	var s := slope
	_poly([12,96, 14,86+s, 24,78+s, 37,72+s, 43,70+s, 55,70+s,
		65,75+s, 76,81+s, 84,90+s, 85,96], cr[3], cr)
	_poly([14,89+s, 26,79+s, 38,74+s, 45,79+s, 32,85+s, 25,96, 12,96], cr[4], cr, 0.05)
	_poly([53,77+s, 64,76+s, 77,83+s, 80,91+s, 71,88+s, 65,85+s, 69,96, 56,96], cr[1], cr, -0.15)
	_curve(Vector2(22,87+s), Vector2(29,81+s), Vector2(37,81+s), cr[5])
	_poly([21,96, 27,87+s, 39,83+s, 32,90+s, 30,96], cr[2])
	_curve(Vector2(31,86+s), Vector2(42,81+s), Vector2(50,84+s), cr[2])
	if elder and not _armored():
		_lock(Vector2(36,73+s), Vector2(42,82+s), Vector2(60,84+s), 4.0, 2.4, cr)
		_curve(Vector2(39,76+s), Vector2(48,81+s), Vector2(56,81+s), cr[5])
	if _armored():
		_armor()

func _armor() -> void:
	var mr := _metal(body)
	var s := slope
	_poly([36,75+s, 48,79+s, 61,76+s, 68,86+s, 70,96, 27,96, 30,85+s], mr[3], mr)
	_poly([36,78+s, 47,82+s, 47,96, 29,96, 31,86+s], mr[4], mr, 0.08)
	_poly([49,81+s, 59,79+s, 64,86+s, 67,96, 52,96], mr[2], mr, -0.06)
	_poly([19,81+s, 26,77+s, 36,78+s, 36,82+s, 30,87+s, 19,87+s, 16,85+s], mr[3], mr, 0.10)
	_poly([60,78+s, 66,78+s, 76,84+s, 77,88+s, 67,87+s, 60,84+s], mr[2], mr)
	_line(Vector2(20,81+s), Vector2(30,79+s), mr[6])
	_curve(Vector2(32,90+s), Vector2(40,93+s), Vector2(44,90+s), mr[2])
	_line(Vector2(64,85+s), Vector2(72,86+s), mr[5])
	var kind := String(body.get("sprite", ""))
	if kind in ["mail", "byrnie", "hauberk", "scale", "lamellar"]:
		# Small staggered links, confined to the armour; no horizontal ladders.
		for y in range(int(84+s), 96, 4):
			for x in range(33+(y % 3), 64, 5):
				_px(x, y, mr[1])
				_px(x+1, y+1, mr[5])
				_px(x+2, y+2, mr[2])
	elif kind in ["scrap", "brigandine"]:
		_poly([35,84+s, 44,85+s, 43,93+s, 33,92+s], mr[3], mr)
		_poly([52,88+s, 61,85+s, 65,95, 54,96], mr[2], mr)
		_px(36, int(86+s), mr[6])
		_px(58, int(89+s), mr[5])

func _neck() -> void:
	if _lost("neck"):
		_wound(int(cx), 68, 5)
		return
	var nw := 5.7 if female else (6.3 if young or elder else 7.6)
	for y in range(56, int(80+slope)):
		var t := clampf(float(y-61)/17.0, 0.0, 1.0)
		var half := nw+t*0.7
		for x in range(int(cx+0.5-half), int(cx+0.5+half)+1):
			var u := (float(x)+0.5-cx)/half
			var light := 0.68-u*0.16+sqrt(maxf(0.0, 1.0-u*u))*0.04-t*0.035
			light -= _soft(x, y, cx+2, chin+1, 9, 5)*0.20
			light -= _soft(x, y, cx+4, 72, 2.5, 8)*0.07
			_px(x, y, _tone(sr, light))

func _collar() -> void:
	var s := slope
	_poly([37,71+s, 40,70+s, 44,76+s, 49,80+s, 45,82+s, 36,76+s], cr[2])
	_poly([38,71+s, 40,71+s, 43,76+s, 47,79+s, 44,79+s, 38,75+s], cr[5])
	_poly([57,71+s, 61,73+s, 58,79+s, 50,82+s, 49,79+s, 55,76+s], cr[1])
	_line(Vector2(58,73+s), Vector2(55,77+s), cr[4])
	_oval(Vector2(35,77+s), 2.8, 2.8, trim[3], trim)
	_oval(Vector2(34,76+s), 1.1, 1.1, trim[6])
	# A tiny crescent clasp recalls the moon without painting bars on the face.
	_curve(Vector2(49,80+s), Vector2(46,84+s), Vector2(51,85+s), trim[4], 0.6)
	_px(50, int(81+s), trim[6])

func _half(y: float) -> float:
	var cheek := 0.92
	var jaw := 0.65
	var tip := 0.29
	if female:
		cheek = 0.83 if elder else 0.90
		jaw = 0.53 if elder else 0.54
		tip = 0.23
	elif not young and not elder:
		cheek = 0.94
		jaw = 0.79
		tip = 0.42
	elif elder:
		cheek = 0.84
		jaw = 0.67
		tip = 0.32
	var profile := [Vector2(top,0.36), Vector2(25,0.78), Vector2(33,0.96),
		Vector2(42,1.0), Vector2(47,0.98), Vector2(52,cheek),
		Vector2(58,jaw), Vector2(chin-2,tip+0.10), Vector2(chin,tip)]
	for i in range(1, profile.size()):
		var a: Vector2 = profile[i-1]
		var b: Vector2 = profile[i]
		if y <= b.x:
			return lerpf(a.y, b.y, clampf((y-a.x)/(b.x-a.x), 0.0, 1.0))*width
	return 0.0

func _face() -> void:
	for y in range(int(top), int(chin)+1):
		if _lost("jaw") and y > my:
			continue
		var half := _half(y+0.5)
		var center := cx+smoothstep(37.0, chin, float(y))*0.7
		for x in range(int(center-half)-1, int(center+half)+1):
			var u := (float(x)+0.5-center)/maxf(0.5, half)
			if absf(u) > 1.0:
				continue
			var fx := float(x)+0.5
			var fy := float(y)+0.5
			var light := 0.64-u*0.20+sqrt(maxf(0.0, 1.0-u*u))*0.08
			light -= (fy-35.0)*0.002
			light += _soft(fx,fy,cx-5,29,10,9)*0.09
			light += _soft(fx,fy,cx-9,46,6.2,4.0)*(0.16 if elder else 0.12)
			light += _soft(fx,fy,cx+10,46,5,3.6)*0.12
			light -= _soft(fx,fy,cx-7,ey-1,5.8,3.5)*(0.14 if young else 0.19)
			light -= _soft(fx,fy,cx+7,ey,5.2,3.5)*(0.17 if young else 0.22)
			light -= _soft(fx,fy,cx-10,53,5.5,4.5)*(0.28 if elder else (0.08 if young else 0.19))
			light -= _soft(fx,fy,cx+11,52,5,5)*(0.31 if elder else (0.15 if young else 0.24))
			# The far cheek turns under the malar ridge into a separate jaw plane.
			light -= _soft(fx,fy,cx+10-(fy-48)*0.20,56,6,6)*0.08
			light += _soft(fx,fy,cx-8,58,4,3)*(0.05 if female else 0.10)
			light -= _soft(fx,fy,cx+4,48,3.5,5)*0.12
			light -= _soft(fx,fy,cx+1,my+3,6,2)*0.12
			light += _soft(fx,fy,cx,chin-3,5.5,2.5)*0.13
			light -= smoothstep(0.82,1.0,absf(u))*0.18
			var col := _tone(sr, light)
			if young and not dead:
				var blush := _soft(fx,fy,cx-9,47,5,3)+_soft(fx,fy,cx+10,47,4,3)
				col = col.lerp(Color("#c4a9c7"), blush*0.13)
			_px(x,y,col)

func _ear(side: int) -> void:
	var root := Vector2(cx+float(side)*(width-1.0), ey+3)
	if _lost("ear_r" if side < 0 else "ear_l"):
		_wound(int(root.x), int(root.y), 2)
		return
	var tip := root+Vector2(side*(13.0 if side < 0 else 11.0), -9.0)
	var fold := root+Vector2(side*4, 1)
	_poly([root.x-side,root.y-3, tip.x,tip.y, fold.x,fold.y+2, root.x-side,root.y+5], sr[3], sr, -0.08 if side > 0 else 0.03)
	_poly([root.x+side,root.y-1, tip.x-side*3,tip.y+3, fold.x,fold.y], sr[2])
	_line(root+Vector2(0,-2), tip+Vector2(-side*2,1), sr[5] if side < 0 else sr[4])
	_line(root+Vector2(side,2), fold, sr[1].lerp(sr[3],0.3))
	_px(int(root.x), int(root.y+3), sr[4])

func _eye(x: int, y: int, near: bool) -> void:
	var w := 4
	var lid := sr[0].lerp(sr[2], 0.22 if female else 0.08)
	var brow := hr[0].lerp(sr[2], 0.22)
	if elder:
		brow = hr[2].lerp(sr[2], 0.28)
	var inner := 1 if near else -1
	for dx in range(-w,w+1):
		var arch := -1 if dx >= -2 and dx <= 1 else 0
		var by := y-5+arch
		if not young and not elder:
			by += 1 if dx*inner >= 2 else 0
		elif young and not female and near:
			by -= 1 if dx < 0 else 0
		elif elder and female:
			by -= 1 if dx*inner > 0 else 0
		_px(x+dx,by,brow)
		if not female and not young and absi(dx)<3:
			_px(x+dx,by+1,brow.lerp(sr[3],0.35))
	if _lost("eye_r" if near else "eye_l"):
		_wound(x,y,3)
		return
	if dead:
		_curve(Vector2(x-w,y), Vector2(x,y+2), Vector2(x+w,y), lid)
		return
	var height := 3 if young else 2
	for dx in range(-w,w+1):
		var corner := absi(dx)>=w-1
		var rise := -1 if (near and dx <= -3) or (not near and dx >= 3) else 0
		_px(x+dx,y-1+rise,lid.lerp(sr[3],0.22 if corner else 0.0))
		if absi(dx)<w:
			for dy in range(1 if corner else 0,height):
				_px(x+dx,y+dy,WHITE.darkened(0.04*dy+(0.04 if not near else 0.0)))
	var iris := Color("#72bddb")
	for dy in range(height):
		_px(x,y+dy,iris)
		_px(x+1,y+dy,Color("#304765"))
	_px(x+1,y,Color("#202b45"))
	_px(x,y,WHITE)
	if height > 2:
		_px(x,y+2,Color("#b0e5f1"))
	_line(Vector2(x-2,y+height),Vector2(x+2,y+height),sr[3].lerp(sr[4],0.25))
	_px(x-1,y+height+1,sr[5] if near else sr[4])
	if female:
		_px(x-w-1 if near else x+w+1,y-1,lid)
	if elder:
		_curve(Vector2(x-3,y+4),Vector2(x,y+5),Vector2(x+2,y+4),sr[3].lerp(sr[4],0.40))

func _nose() -> void:
	if _lost("nose"):
		return
	var nx := int(cx)+1
	var tip := my-5
	var base := 2.1 if female or young else 2.8
	for y in range(ey+1,tip+1):
		var t := float(y-ey)/float(tip-ey)
		var ridge := float(nx)-0.7+t*0.6
		for x in range(nx-2,nx+4):
			var u := (float(x)+0.5-ridge)/2.7
			if absf(u)<1.0:
				_px(x,y,_tone(sr,0.75-u*0.18+sin(t*PI)*0.03))
	_oval(Vector2(nx,tip),base,1.8,sr[4],sr,0.07)
	_line(Vector2(nx-1,tip-1),Vector2(nx,tip-1),sr[6].lerp(sr[5],0.30))
	_px(nx-1,tip+1,sr[1].lerp(sr[3],0.42))
	_px(nx+int(base),tip,sr[2])
	_px(nx+1,tip+2,sr[3])

func _mouth() -> void:
	if _lost("mouth") or _lost("jaw"):
		return
	var x := int(cx)+1
	var lip := skin.lerp(Color("#6d5d87"),0.40 if female else 0.29)
	var seam := skin.lerp(Color("#36405d"),0.66)
	var w := 4 if elder else 5
	_poly([x-w,my, x-2,my-1, x+2,my-1, x+w,my, x+2,my+1, x-2,my+1],lip)
	_poly([x-w+1,my+1, x+w-1,my+1, x+2,my+2, x-2,my+2],lip.lerp(sr[5],0.32))
	var far_y := my
	if young:
		far_y -= 1 if female else 0
	elif elder:
		far_y += 1
	_curve(Vector2(x-w,my),Vector2(x,my+(0 if young else -0.5)),Vector2(x+w,far_y),seam)
	_line(Vector2(x-2,my+1),Vector2(x+1,my+1),lip.lerp(sr[6],0.46))
	_px(x-w-1,my+1,sr[3].lerp(sr[4],0.45))
	if young and female:
		_px(x+w+1,my-1,sr[3])

func _age_lines() -> void:
	if not elder:
		return
	var crease := sr[3].lerp(sr[4],0.18)
	# One broken forehead fold and two shaped cheek creases, never stacked bars.
	_curve(Vector2(cx-6,29),Vector2(cx-3,27),Vector2(cx,29),crease)
	_line(Vector2(cx+3,30),Vector2(cx+5,30),crease.lerp(sr[4],0.25))
	_px(int(cx)-4,27,sr[5])
	_curve(Vector2(cx-8,my-5),Vector2(cx-10,my-2),Vector2(cx-8,my+1),crease)
	_curve(Vector2(cx+7,my-4),Vector2(cx+9,my),Vector2(cx+8,my+2),sr[2].lerp(sr[3],0.6))
	_line(Vector2(cx-13,ey+2),Vector2(cx-15,ey+3),crease)
	_px(int(cx)+13,ey+4,crease)
	_line(Vector2(cx-3,chin-2),Vector2(cx,chin-2),sr[3].lerp(sr[4],0.5))

func _hair_mass(coords: Array, bias: float = 0.0) -> void:
	_poly(coords,hr[2],hr,bias-0.19)

func _hlock(a: Vector2, control: Vector2, b: Vector2, root: float, tip: float, bias: float = 0.0) -> void:
	_lock(a,control,b,root,tip,hr,bias)

func _hair_back() -> void:
	if female and elder:
		_oval(Vector2(61,19),9.3,10.2,hr[2],hr,-0.06)
		_hlock(Vector2(60,12),Vector2(73,13),Vector2(66,25),4.7,1.2,0.04)
		_hlock(Vector2(67,26),Vector2(69,18),Vector2(61,15),3.8,0.7,0.02)
		_hlock(Vector2(32,31),Vector2(24,54),Vector2(31,73),5.4,1.5,-0.10)
	elif female:
		_hair_mass([31,23, 43,14, 60,19, 69,33, 72,54, 68,78, 72,88,
			61,90, 57,64, 37,63, 33,87, 24,85, 27,60, 25,40],-0.05)
		_hlock(Vector2(31,27),Vector2(20,51),Vector2(29,84),6.2,1.0,-0.04)
		_hlock(Vector2(64,27),Vector2(75,47),Vector2(65,79),6.4,1.4,-0.13)
		_hlock(Vector2(67,55),Vector2(61,73),Vector2(70,85),4.1,0.8,-0.09)
	elif elder:
		_hlock(Vector2(32,23),Vector2(24,39),Vector2(29,53),5.5,2.2,-0.12)
		_hlock(Vector2(29,47),Vector2(25,58),Vector2(33,70),3.7,0.7,-0.06)
		_hlock(Vector2(64,22),Vector2(72,40),Vector2(67,55),5.0,2.1,-0.21)
		_hlock(Vector2(67,49),Vector2(70,64),Vector2(63,73),3.7,0.6,-0.14)
	else:
		_hair_mass([29,40, 27,27, 34,14, 47,9, 62,14, 69,26, 68,43, 63,49, 32,47])
		_hlock(Vector2(31,24),Vector2(27,33),Vector2(31,47),3.7,0.8,-0.12)
		_hlock(Vector2(64,23),Vector2(69,33),Vector2(65,46),3.9,0.8,-0.20)

func _hair_front() -> void:
	if elder and not female:
		# A high, receding forehead and quiet swept wings expose the elder's planes.
		_hlock(Vector2(43,17),Vector2(31,12),Vector2(28,36),5.0,1.1,0.01)
		_hlock(Vector2(49,15),Vector2(59,9),Vector2(67,30),4.8,1.6,-0.03)
		_hlock(Vector2(59,19),Vector2(68,22),Vector2(65,40),3.4,1.0,-0.08)
		_hlock(Vector2(39,17),Vector2(45,10),Vector2(52,15),3.3,0.5,0.09)
		return
	if elder:
		_hair_mass([28,35, 28,25, 36,14, 49,9, 61,13, 67,26, 64,35, 58,25, 48,23, 38,28, 33,39],0.03)
		_hlock(Vector2(55,14),Vector2(37,12),Vector2(29,34),6.5,1.0,0.08)
		_hlock(Vector2(60,19),Vector2(48,16),Vector2(35,29),5.0,0.7,0.04)
		_hlock(Vector2(56,15),Vector2(67,19),Vector2(64,34),4.7,1.0,-0.08)
		_hlock(Vector2(33,29),Vector2(27,36),Vector2(31,47),3.4,0.6,0.01)
		# Three interwoven, unequal twists; no ladder texture along the braid.
		_hlock(Vector2(30,47),Vector2(24,53),Vector2(32,61),4.2,2.4,0.04)
		_hlock(Vector2(33,57),Vector2(36,65),Vector2(29,72),3.7,1.8,-0.02)
		_hlock(Vector2(29,68),Vector2(24,75),Vector2(30,82),3.0,1.2,0.03)
		_oval(Vector2(30,81),2.0,2.4,trim[3],trim)
		_hlock(Vector2(30,83),Vector2(33,86),Vector2(29,91),2.2,0.3,-0.03)
		return
	if female:
		_hair_mass([28,33, 28,24, 36,13, 49,9, 60,13, 66,22, 66,35, 60,30, 53,22, 43,25, 33,36])
		_hlock(Vector2(53,14),Vector2(34,10),Vector2(28,31),6.5,1.0,0.10)
		_hlock(Vector2(53,20),Vector2(40,18),Vector2(32,35),4.2,0.6,0.02)
		_hlock(Vector2(55,16),Vector2(67,20),Vector2(65,37),5.5,1.2,-0.06)
		_hlock(Vector2(29,44),Vector2(35,56),Vector2(27,68),4.9,2.3,0.01)
		_hlock(Vector2(27,63),Vector2(22,73),Vector2(30,85),4.4,0.7,0.03)
		_hlock(Vector2(65,44),Vector2(60,58),Vector2(66,68),4.3,1.5,-0.09)
		_hlock(Vector2(65,63),Vector2(71,73),Vector2(64,86),4.1,0.6,-0.05)
		_oval(Vector2(64,31),1.6,2.4,trim[3],trim)
		return
	if young:
		_hair_mass([27,36, 27,26, 33,15, 47,9, 60,12, 68,24, 65,38, 59,27, 51,23, 43,28, 32,39])
		_hlock(Vector2(50,14),Vector2(34,6),Vector2(27,28),6.4,1.0,0.08)
		_hlock(Vector2(53,20),Vector2(39,16),Vector2(31,36),5.2,0.8,-0.01)
		_hlock(Vector2(58,23),Vector2(50,20),Vector2(42,29),3.8,0.5,-0.07)
		_hlock(Vector2(57,15),Vector2(69,18),Vector2(65,35),4.9,1.0,-0.10)
		_hlock(Vector2(40,13),Vector2(40,6),Vector2(45,8),2.5,0.4,0.05)
	else:
		_hair_mass([28,35, 28,24, 36,13, 49,9, 62,15, 68,27, 65,40, 62,32, 56,25, 45,23, 34,32])
		_hlock(Vector2(42,16),Vector2(54,8),Vector2(65,27),6.8,1.2,0.02)
		_hlock(Vector2(39,23),Vector2(53,17),Vector2(62,36),4.7,0.8,-0.06)
		_hlock(Vector2(42,16),Vector2(31,15),Vector2(29,35),4.5,0.9,0.08)
		_hlock(Vector2(32,28),Vector2(30,34),Vector2(32,44),2.3,0.5,-0.06)

func _beard() -> void:
	if not beard or _lost("jaw") or _lost("head"):
		return
	var x := cx+1
	if beard_style == 6:
		_lock(Vector2(x-1,my-1),Vector2(x-5,my-2),Vector2(x-7,my+1),1.6,0.5,br)
		_lock(Vector2(x+1,my-1),Vector2(x+5,my-2),Vector2(x+6,my+1),1.5,0.5,br,-0.08)
		return
	if beard_style in [7,8]:
		# Short beard follows the jaw volume; its edge breaks into a few soft points.
		for y in range(my-4,int(chin)+2):
			var half := _half(minf(y+0.5,chin-0.5))
			for px in range(int(cx-half),int(cx+half)+1):
				var dx := absf(float(px)-x)
				var hairline := float(my+4)-smoothstep(4.0,13.0,dx)*7.0
				if float(y)<hairline:
					continue
				if y < my+3 and dx < 5.0:
					continue
				if y == my+3 and dx > 1.5 and dx < 4.0:
					continue
				var u := (float(px)+0.5-x)/maxf(1.0,half)
				var light := 0.60-u*0.19+sqrt(maxf(0.0,1.0-u*u))*0.10-float(y-my)*0.008
				var root := smoothstep(hairline,hairline+2.5,float(y))
				_px(px,y,image.get_pixel(px,y).lerp(_tone(br,light),root))
		_lock(Vector2(x-10,my+2),Vector2(x-12,chin-3),Vector2(x-5,chin+1),2.9,0.5,br,0.00)
		_lock(Vector2(x+10,my+2),Vector2(x+11,chin-2),Vector2(x+6,chin+1),2.7,0.5,br,-0.18)
		_lock(Vector2(x-1,my+6),Vector2(x-3,chin-1),Vector2(x,chin+3),3.0,0.4,br,-0.01)
		_lock(Vector2(x-1,my-1),Vector2(x-5,my-2),Vector2(x-7,my+1),1.3,0.4,br,0.03)
		_lock(Vector2(x+1,my-1),Vector2(x+5,my-1),Vector2(x+6,my+1),1.2,0.4,br,-0.10)
		return
	var bottom := chin+(14.0 if elder else 7.0)
	if beard_style == 3:
		bottom += 3.0
	var half := 8.5 if elder else 6.0
	_poly([x-half,my+2, x-4,my+3, x+3,my+3, x+half,my+1,
		x+half+1,chin-2, x+5,bottom-3, x,bottom, x-6,bottom-4, x-half-1,chin],br[2],br,-0.10)
	_lock(Vector2(x-7,my+3),Vector2(x-11,chin),Vector2(x-6,bottom-6),4.2,0.7,br,-0.03)
	_lock(Vector2(x+6,my+3),Vector2(x+10,chin+3),Vector2(x+3,bottom-2),4.5,0.6,br,-0.20)
	_lock(Vector2(x+2,my+7),Vector2(x+5,chin+4),Vector2(x-1,bottom),3.8,0.4,br,-0.10)
	_lock(Vector2(x-2,my+6),Vector2(x-7,chin+2),Vector2(x-3,bottom-1),3.4,0.5,br,0.03)
	if beard_style == 4 or beard_style == 5:
		_lock(Vector2(x-3,chin),Vector2(x-7,bottom-1),Vector2(x-5,bottom+2),2.9,0.4,br)
		_lock(Vector2(x+3,chin),Vector2(x+8,bottom),Vector2(x+6,bottom+1),2.7,0.4,br,-0.12)
	_lock(Vector2(x-1,my-1),Vector2(x-5,my-2),Vector2(x-8,my+2),1.8,0.5,br,0.06)
	_lock(Vector2(x+1,my-1),Vector2(x+5,my-1),Vector2(x+7,my+2),1.6,0.5,br,-0.08)

func _hood() -> void:
	var mr := _metal(helm)
	_poly([26,28, 32,16, 48,10, 63,15, 70,28, 69,57, 76,77,
		64,82, 28,81, 21,74, 27,53],mr[2],mr)
	_line(Vector2(28,31),Vector2(27,61),mr[5])
	_line(Vector2(67,31),Vector2(69,62),mr[1])

func _headgear() -> void:
	if helm_kind in ["none","coif"]:
		return
	var mr := _metal(helm)
	if helm_kind == "closed":
		_poly([28,24, 34,15, 48,11, 62,15, 69,25, 67,53, 61,65,
			49,69, 35,63, 29,51],mr[3],mr)
		_poly([47,16, 51,26, 52,64, 49,67, 47,42],mr[5])
		_line(Vector2(33,39),Vector2(45,40),mr[0],1.0)
		_line(Vector2(53,40),Vector2(64,38),mr[0],1.0)
		_line(Vector2(34,37),Vector2(45,38),mr[6])
		_poly([55,51, 61,48, 61,56, 55,59],mr[1])
		return
	if helm_kind == "crown":
		_poly([31,28, 32,20, 39,24, 47,16, 54,23, 63,19, 65,29],mr[3],mr)
		_curve(Vector2(31,28),Vector2(48,32),Vector2(65,28),mr[6],0.7)
		_oval(Vector2(cx,27),2.0,2.5,trim[4],trim)
		return
	_poly([26,31, 29,21, 36,14, 48,10, 61,15, 68,23, 70,32,
		65,35, 30,35],mr[3],mr)
	_curve(Vector2(29,32),Vector2(49,35),Vector2(67,32),mr[1],0.8)
	_line(Vector2(47,13),Vector2(49,30),mr[6])
	if helm_kind == "kettle":
		_poly([26,30, 67,30, 77,36, 71,39, 23,37, 19,34],mr[2],mr)
		_line(Vector2(24,34),Vector2(73,36),mr[5])
	elif helm_kind == "nasal":
		_poly([47,32, 51,32, 52,49, 49,52, 47,49],mr[2])
		_line(Vector2(48,33),Vector2(49,49),mr[6])

func _wound(x: int, y: int, radius: int) -> void:
	_oval(Vector2(x,y),radius,radius*0.75,BLOOD)
	_oval(Vector2(x+1,y),maxf(1.0,radius*0.5),maxf(1.0,radius*0.35),BLOOD.darkened(0.50))
	_line(Vector2(x,y+1),Vector2(x+1,y+radius+2),BLOOD)

func _outline() -> void:
	var edge: Array[Vector2i] = []
	for y in range(1,SIZE-1):
		for x in range(1,SIZE-1):
			if image.get_pixel(x,y).a > 0.1:
				continue
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var p := Vector2i(x,y)+(offset as Vector2i)
				if image.get_pixel(p.x,p.y).a > 0.5:
					edge.append(Vector2i(x,y))
					break
	for p in edge:
		_px(p.x,p.y,INK)
