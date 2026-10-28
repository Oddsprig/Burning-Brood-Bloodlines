extends RefCounted
## Orc-only 96px busts with curved silhouettes and swept, shaded hair locks.
## All drawing is local; the frozen elf/shared renderer is never called.

const SIZE := 96
const INK := Color("#18231e")
const WHITE := Color("#eee9d5")
const ARMOR := ["cuirass", "mail", "scale", "lamellar", "scrap", "byrnie", "plate", "brigandine", "hauberk", "breastplate"]

var image: Image
var spec: Dictionary
var female := false
var young := false
var elder := false
var dead := false
var seed := 1
var mirror_hair := false
var skin: Color
var hair: Color
var primary: Color
var secondary: Color
var skin_ramp: Array[Color] = []
var hair_ramp: Array[Color] = []
var beard_ramp: Array[Color] = []
var cloth_ramp: Array[Color] = []
var body: Dictionary = {}
var helm: Dictionary = {}
var helm_kind := "none"
var lost: Dictionary = {}
var bearded := false
var beard_style := 0
var center := 48.0
var top := 17.0
var chin := 66.0
var half := 20.5
var eye_y := 38.0
var mouth_y := 55.0
var neck := 11.5
var shoulder := 41.0

static func paint(spec: Dictionary) -> Image:
	return load("res://art/portraits/portrait_orc.gd").new()._render(spec)

func _render(sp: Dictionary) -> Image:
	spec = sp
	image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_read()
	if not _lost("head"):
		_hair_back()
	_torso()
	_neck()
	_collar()
	if _lost("head"):
		_wound(Vector2(center, 63), 6.0)
	elif helm_kind == "closed":
		_closed_helmet()
	else:
		_ears()
		_face()
		_hair_front()
		_eye(-1)
		_eye(1)
		_nose()
		_mouth()
		_age_marks()
		_beard()
		_tusks()
		_helmet()
	_outline()
	return image

func _read() -> void:
	seed = absi(int(spec.get("seed", 1)))
	female = String(spec.get("sex", "male")) == "female"
	var age := int(spec.get("age", 24))
	young = age < 18
	elder = age >= 35
	dead = bool(spec.get("dead", false))
	mirror_hair = female and int(spec.get("female_set", seed % 2)) % 2 == 1
	center += float(seed % 3 - 1) * 0.5
	if female:
		half = 18.4 if young else 18.0
		neck = 9.5 if young else 10.0
		shoulder = 35.0 if young else 38.0
		chin = 65.0 if young else 66.0
	elif young:
		half = 19.0
		neck = 10.2
		shoulder = 38.0
		top = 18.0
		chin = 64.0
	elif elder:
		half = 20.0
		chin = 67.0
		top = 18.0
		eye_y += 1.0
		mouth_y += 1.0
	if young:
		eye_y += 1.0
		mouth_y -= 1.0
	skin = _color("skin", Color("#71934b"))
	hair = _color("hair", Color("#34302a"))
	primary = _color("prim", Color("#973c2c"))
	secondary = _color("sec", Color("#d2ac66"))
	var blood := clampf(float(spec.get("blood", 1.0)), 0.0, 1.0)
	skin = skin.lerp(Color("#b5b5a1"), (1.0 - blood) * 0.42)
	if dead:
		skin = skin.lerp(Color("#999e8b"), 0.48)
	if elder:
		hair = hair.lerp(Color("#c7cec2"), 0.57)
	skin_ramp = _palette(skin, Color("#1c3935"), Color("#d7dd9b"))
	hair_ramp = _hair_palette(hair)
	cloth_ramp = _palette(primary, Color("#29232a"), primary.lightened(0.48))
	bearded = false
	var beard_color := hair
	var beard_value = spec.get("beard", false)
	if beard_value is bool:
		bearded = beard_value
	elif beard_value is Color:
		bearded = true
		beard_color = beard_value
	elif beard_value is String and beard_value != "" and beard_value != "false":
		bearded = true
		if Color.html_is_valid(beard_value):
			beard_color = Color(beard_value)
	if elder:
		beard_color = beard_color.lerp(Color("#ccd0bd"), 0.25)
	beard_style = clampi(int(spec.get("beard_style", 0)), 0, 7)
	beard_ramp = _hair_palette(beard_color)
	if spec.get("body", {}) is Dictionary:
		body = spec.get("body", {})
	if spec.get("helm", {}) is Dictionary:
		helm = spec.get("helm", {})
	var helmet_name := (String(helm.get("sprite", "")) + " " + String(helm.get("tid", ""))).to_lower().strip_edges()
	if helmet_name != "":
		if "coif" in helmet_name or "hood" in helmet_name:
			helm_kind = "coif"
		elif "great" in helmet_name or "closed" in helmet_name or "barrel" in helmet_name or "frog" in helmet_name:
			helm_kind = "closed"
		elif "crown" in helmet_name or "circlet" in helmet_name:
			helm_kind = "crown"
		elif "kettle" in helmet_name:
			helm_kind = "kettle"
		elif "nasal" in helmet_name:
			helm_kind = "nasal"
		else:
			helm_kind = "cap"
	var lost_value = spec.get("lost", [])
	if lost_value is Array:
		for id in lost_value:
			lost[String(id)] = true

func _color(key: String, fallback: Color) -> Color:
	var value = spec.get(key, fallback)
	var result := fallback
	if value is Color:
		result = value
	elif value is String and value != "":
		result = Color(value)
	result.a = 1.0
	return result

func _palette(base: Color, shade: Color, light: Color) -> Array[Color]:
	base.a = 1.0
	return [base.lerp(shade, 0.78).darkened(0.12), base.lerp(shade, 0.58),
		base.lerp(shade, 0.32), base.darkened(0.06), base,
		base.lerp(light, 0.27), base.lerp(light, 0.52)]

func _hair_palette(base: Color) -> Array[Color]:
	# Black hair needs a rising ramp too: a green shadow mix can otherwise be
	# brighter than the source black and erase the shape of every lock.
	if base.get_luminance() < 0.09:
		return [base.darkened(0.45), base, base.lightened(0.055),
			base.lightened(0.11), base.lightened(0.18),
			base.lightened(0.28).lerp(Color("#83958d"),0.12), base.lightened(0.42)]
	return _palette(base, Color("#1b2425"), Color("#dedbc4"))

func _lost(id: String) -> bool:
	return bool(lost.get(id, false))

func _px(x: int, y: int, color: Color) -> void:
	if x >= 0 and x < SIZE and y >= 0 and y < SIZE:
		image.set_pixel(x, y, color)

func _poly(coords: Array, color: Color) -> void:
	var points := PackedVector2Array()
	var lo := Vector2(SIZE, SIZE)
	var hi := Vector2.ZERO
	for i in range(0, coords.size(), 2):
		var point := Vector2(float(coords[i]), float(coords[i + 1]))
		points.append(point)
		lo = lo.min(point)
		hi = hi.max(point)
	for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y)) + 1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x)) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				_px(x, y, color)

func _stroke(coords: Array, radius: float, color: Color) -> void:
	for i in range(0, coords.size() - 2, 2):
		var a := Vector2(float(coords[i]), float(coords[i + 1]))
		var b := Vector2(float(coords[i + 2]), float(coords[i + 3]))
		var lo := a.min(b) - Vector2.ONE * radius
		var hi := a.max(b) + Vector2.ONE * radius
		for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y)) + 1)):
			for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x)) + 1)):
				var point := Vector2(x + 0.5, y + 0.5)
				if Geometry2D.get_closest_point_to_segment(point, a, b).distance_squared_to(point) <= radius * radius:
					_px(x, y, color)

func _ellipse(c: Vector2, radii: Vector2, palette: Array[Color], bias: float = 0.0) -> void:
	for y in range(maxi(0, int(floor(c.y - radii.y))), mini(SIZE, int(ceil(c.y + radii.y)) + 1)):
		for x in range(maxi(0, int(floor(c.x - radii.x))), mini(SIZE, int(ceil(c.x + radii.x)) + 1)):
			var u := (float(x) + 0.5 - c.x) / radii.x
			var v := (float(y) + 0.5 - c.y) / radii.y
			if u * u + v * v > 1.0:
				continue
			var z := sqrt(maxf(0.0, 1.0 - u * u - v * v))
			var light := 0.43 + z * 0.29 - u * 0.24 - v * 0.19 + bias
			_px(x, y, palette[clampi(int(light * 7.0), 0, 6)])

func _head_half(y: float) -> float:
	var t := (y - top) / (chin - top)
	var rows := [Vector2(0.0, 0.15), Vector2(0.05, 0.52), Vector2(0.15, 0.83),
		Vector2(0.28, 0.97), Vector2(0.44, 1.0), Vector2(0.58, 0.96),
		Vector2(0.70, 0.98 if not female else 0.91), Vector2(0.83, 0.91 if not female else 0.79),
		Vector2(0.94, 0.67 if not female else 0.56), Vector2(1.0, 0.32 if not female else 0.23)]
	for i in range(rows.size() - 1):
		var a: Vector2 = rows[i]
		var b: Vector2 = rows[i + 1]
		if t <= b.x:
			return half * lerpf(a.y, b.y, smoothstep(a.x, b.x, t))
	return 0.0

func _face() -> void:
	for y in range(int(top), int(chin) + 1):
		if _lost("jaw") and float(y) > mouth_y + 1.0:
			continue
		var t := (float(y) - top) / (chin - top)
		var row_half := _head_half(float(y) + 0.35)
		var mid := center + smoothstep(0.35, 1.0, t) * 0.8
		for x in range(int(mid - row_half), int(mid + row_half) + 1):
			var u := (float(x) + 0.5 - mid) / maxf(1.0, row_half)
			if absf(u) > 1.0:
				continue
			var z := sqrt(maxf(0.0, 1.0 - u * u))
			var light := 0.53 + z * 0.23 - u * 0.36 - t * 0.19
			# Malar planes, soft young cheeks, and the shelf of the lower jaw.
			var cheek := exp(-pow((absf(u) - 0.58) / 0.27, 2.0) - pow((t - 0.55) / 0.12, 2.0))
			light += cheek * (0.10 if young else 0.14)
			var hollow := exp(-pow((absf(u) - 0.66) / 0.19, 2.0) - pow((t - 0.72) / 0.12, 2.0))
			light -= hollow * (0.06 if young else (0.20 if elder else 0.13))
			if t > 0.89:
				light -= (t - 0.89) * 1.25
			if absf(u) > 0.90:
				light -= 0.11
			_px(x, y, skin_ramp[clampi(int(light * 7.0), 0, 6)])
	if not _lost("jaw"):
		_ellipse(Vector2(center + 0.5, chin - 4.0), Vector2(7.0 if not female else 5.0, 2.7), skin_ramp, -0.05)

func _ears() -> void:
	for side in [-1, 1]:
		var id := "ear_r" if side < 0 else "ear_l"
		var x: float = center + float(side) * (half - 1.0)
		if _lost(id):
			_wound(Vector2(x, 40), 2.0)
			continue
		var s := float(side)
		_poly([x,34, x+s*10,29, x+s*8,38, x+s*5,44, x,46], skin_ramp[3 if side < 0 else 2])
		_poly([x+s,36, x+s*7,32, x+s*5,39, x+s*2,42], skin_ramp[1])
		_stroke([x+s*8,32, x+s*6,37, x+s*3,41], 0.65, skin_ramp[5 if side < 0 else 3])
		_stroke([x+s,38, x+s*2,42, x,44], 0.8, skin_ramp[2])
		if female or seed % 3 == 0:
			_ellipse(Vector2(x+s*3,44), Vector2(1.7,2.2), _palette(secondary, Color("#53452d"), WHITE))
			_px(int(x+s*3),44,skin_ramp[1])

func _eye(side: int) -> void:
	var x := center + (-8.3 if side < 0 else 8.3)
	var y := eye_y + (0.6 if side > 0 else 0.0)
	var inward := 1.0 if side < 0 else -1.0
	_ellipse(Vector2(x,y), Vector2(6.4,4.4), skin_ramp, -0.25)
	_stroke([x-inward*5.7,y-4.0, x-inward*1.5,y-4.1, x+inward*4.8,y-1.9], 2.0 if not female else 1.55, skin_ramp[2])
	_stroke([x-inward*5.5,y-5.0, x-inward*1.5,y-5.0, x+inward*4.0,y-3.1], 0.9, skin_ramp[5 if side < 0 else 4])
	var brow_color := hair_ramp[1].lerp(skin_ramp[0], 0.42)
	_stroke([x-inward*5.3,y-4.0, x-inward*1.1,y-4.0, x+inward*3.7,y-2.1], 0.9 if female or young else 1.25, brow_color)
	if _lost("eye_r" if side < 0 else "eye_l"):
		_wound(Vector2(x,y),2.4)
		return
	if dead:
		_stroke([x-4,y, x,y+1, x+4,y],0.75,skin_ramp[0])
		return
	var height := 4 if young or female else 3
	var x0 := int(round(x))
	var y0 := int(round(y))
	for row in range(height):
		var reach := 3 if row == 0 or row == height-1 else 4
		for dx in range(-reach,reach+1):
			_px(x0+dx,y0+row-1,WHITE if side < 0 else Color("#cfd8bc"))
	var iris_x := x0 + (0 if seed % 2 == 0 else 1)
	for row in range(height):
		_px(iris_x-1,y0+row-1,Color("#ac7a22"))
		_px(iris_x,y0+row-1,Color("#e0b94b"))
		_px(iris_x+1,y0+row-1,Color("#a98228"))
		if row < height-1:
			_px(iris_x,y0+row-1,Color("#222a20"))
	_px(iris_x-1,y0-1,Color("#fff1bf"))
	_stroke([x-4.7,y-0.6, x-2,y-1.8, x+2,y-1.8, x+4.6,y-0.5],0.65,skin_ramp[0])
	_stroke([x-3.5,y+height-0.4, x+2.5,y+height-0.4, x+4,y+height-1.5],0.65,skin_ramp[2])
	_stroke([x-3,y+height+0.8, x+1,y+height+1.1],0.55,skin_ramp[5 if side < 0 else 3])

func _nose() -> void:
	var x := center + 1.0
	var y := mouth_y - 6.5
	if _lost("nose"):
		_wound(Vector2(x,y),3.5)
		return
	var spread := 3.4 if young else 4.0
	_ellipse(Vector2(x+0.5,y-4.5),Vector2(3.4,7.2),skin_ramp,-0.06)
	_ellipse(Vector2(x-spread,y),Vector2(3.5,2.8),skin_ramp,-0.04)
	_ellipse(Vector2(x+spread,y+0.2),Vector2(3.3,2.7),skin_ramp,-0.13)
	_ellipse(Vector2(x,y-0.7),Vector2(4.4,2.5),skin_ramp,0.06)
	_stroke([x-1,y-6.5, x-1.7,y-2.5],0.65,skin_ramp[6])
	_stroke([x-spread-1,y+1, x-spread+1,y+1.5],0.8,skin_ramp[0])
	_stroke([x+spread-1,y+1.5, x+spread+1,y+1.0],0.8,skin_ramp[0])
	_px(int(x),int(y+2),skin_ramp[2])

func _mouth() -> void:
	if _lost("mouth") or _lost("jaw"):
		_wound(Vector2(center+1,mouth_y),3.5)
		return
	var x := center+1.0
	var reach := 8.0 if young else 10.0
	var lip := skin_ramp[2].lerp(Color("#685143"),0.40)
	_ellipse(Vector2(x,mouth_y+1),Vector2(reach+0.8,3.0),skin_ramp,-0.11)
	for dx in range(-int(reach),int(reach)+1):
		var bend := int(round(pow(absf(float(dx))/reach,1.8)*1.7))
		var y := int(mouth_y)+bend
		_px(int(x)+dx,y-1,lip)
		_px(int(x)+dx,y,skin_ramp[0].darkened(0.18))
		_px(int(x)+dx,y+1,skin_ramp[2])
		if absi(dx) < int(reach)-2:
			_px(int(x)+dx,y+2,skin_ramp[4 if dx < 2 else 3])
	_stroke([x-3,mouth_y+4, x+3,mouth_y+4],0.6,skin_ramp[2])

func _age_marks() -> void:
	if young:
		return
	if elder:
		for i in range(2):
			var y := eye_y-10.0+float(i)*3.0
			_stroke([center-8,y+0.8, center-3,y, center+2,y+0.3, center+7,y+1.2],0.55,skin_ramp[2])
			_stroke([center-6,y-0.7, center-1,y-1, center+4,y-0.6],0.5,skin_ramp[5])
		for side in [-1,1]:
			var x: float = center+float(side)*9.0
			var s := float(side)
			_stroke([x+s*4,eye_y+1, x+s*7,eye_y+2],0.6,skin_ramp[1])
			_stroke([x+s*4,eye_y+3, x+s*6,eye_y+5],0.6,skin_ramp[2])
			_stroke([x-s*2,eye_y+6, x+s*2,eye_y+6.5],0.65,skin_ramp[2])
			_stroke([center+s*7,mouth_y-3, center+s*10,mouth_y+2, center+s*9,mouth_y+5],0.7,skin_ramp[1])
			_stroke([center+s*8,mouth_y-3, center+s*11,mouth_y+2],0.6,skin_ramp[4])
	elif not female:
		var x := center+14.0
		_stroke([x,eye_y+5, x-1,eye_y+9, x+float(seed%2),eye_y+12],0.75,skin_ramp[2])
		_stroke([x-1,eye_y+5, x-2,eye_y+9, x-1,eye_y+12],0.5,skin_ramp[5])

func _torso() -> void:
	var c := center-1.5
	var start := 68.0 if not young else 69.0
	for y in range(int(start),SIZE):
		var t := clampf((float(y)-start)/23.0,0.0,1.0)
		var width := lerpf(neck+3.0,shoulder,sin(t*PI*0.5))
		for x in range(int(c-width),int(c+width)+1):
			var u := (float(x)-c)/maxf(1.0,width)
			var light := 0.66-u*0.22-t*0.25
			# Broad fold clusters converge on the neck and armholes.
			var fold := absf(float(x)-(c-12.0-(float(y)-74.0)*0.65))
			light += exp(-fold*fold/7.0)*0.18
			var crease := absf(float(x)-(c+11.0+(float(y)-74.0)*0.40))
			light -= exp(-crease*crease/5.0)*0.16
			if absf(u)>0.91:
				light-=0.13
			_px(x,y,cloth_ramp[clampi(int(light*7.0),0,6)])
	_stroke([20,85, 25,81, 31,79],1.1,cloth_ramp[5])
	_stroke([15,91, 21,86, 26,85],0.7,cloth_ramp[2])
	_stroke([70,82, 77,86, 81,94],1.0,cloth_ramp[2])
	_stroke([34,88, 30,93, 29,96],0.9,cloth_ramp[2])

func _neck() -> void:
	if _lost("neck"):
		_wound(Vector2(center,69),5)
		return
	for y in range(int(chin-7),81):
		var t := clampf((float(y)-chin+6.0)/20.0,0.0,1.0)
		var width := neck*(0.89+t*0.35)
		for x in range(int(center-width),int(center+width)+1):
			var u := (float(x)-center)/width
			var light := 0.66-u*0.25-t*0.08
			if float(y)<chin+2:
				light-=0.25
			var tendon := absf(absf(float(x)-center)-(neck*0.75-t*4.0))
			light+=exp(-tendon*tendon/2.0)*0.13
			_px(x,y,skin_ramp[clampi(int(light*7.0),0,6)])
	_stroke([center-3,chin+7, center-2,chin+12, center+2,chin+13],1.0,skin_ramp[3])
	_stroke([center-5,77, center,79, center+4,77],0.65,skin_ramp[2])

func _collar() -> void:
	_poly([29,72, 35,70, center,79, center-4,87, 31,80, 25,79],cloth_ramp[2])
	_poly([31,72, 35,72, center-1,80, center-4,83, 33,78],cloth_ramp[5])
	_poly([center,79, 61,71, 67,74, 63,80, center+4,86, center-4,88],cloth_ramp[1])
	_stroke([30,73, center-1,82, 62,73],0.8,secondary.darkened(0.25))
	var armored := false
	var name := (String(body.get("sprite",""))+" "+String(body.get("tid",""))).to_lower()
	for kind in ARMOR:
		if kind in name:
			armored=true
	if armored:
		_armor(name)
	else:
		_poly([62,76, 68,78, 43,96, 34,96],Color("#493627"))
		_stroke([65,78, 39,96],0.65,Color("#9a7750"))
		_ellipse(Vector2(58,83),Vector2(2.5,2.0),_palette(secondary,Color("#53452d"),WHITE))

func _metal(item: Dictionary) -> Array[Color]:
	var material := String(item.get("mat","iron"))
	if material == "":
		material = "iron"
	var colors: Dictionary = FigurePainter.metal(material,int(item.get("q",0)))
	var base: Color = colors["base"]
	var dark: Color = colors["dark"]
	var light: Color = colors["light"]
	var shine: Color = colors["shine"]
	return [dark.darkened(0.20),dark,base.lerp(dark,0.4),base,base.lerp(light,0.55),light,shine]

func _armor(name: String) -> void:
	var metal := _metal(body)
	_poly([32,79, 43,82, 53,82, 64,77, 75,91, 75,96, 21,96, 23,86],metal[2])
	_poly([32,80, 44,85, 48,96, 23,96, 25,87],metal[4])
	_poly([45,85, 62,80, 71,91, 69,96, 49,96],metal[3])
	_stroke([31,80, 44,84, 53,84, 64,79],0.8,metal[6])
	_stroke([45,86, 49,94],0.7,metal[1])
	# Articulated pauldrons sit on sloped shoulders at different heights.
	_poly([11,80, 19,74, 29,73, 35,78, 31,84, 19,88, 11,87],metal[1])
	_poly([13,80, 20,75, 28,75, 32,78, 28,82, 18,85, 12,84],metal[4])
	_stroke([14,80, 21,76, 28,76],0.9,metal[6])
	_stroke([12,86, 20,88, 30,84],0.8,metal[3])
	_poly([64,77, 74,77, 84,83, 87,90, 80,93, 69,87],metal[1])
	_poly([66,78, 74,79, 82,84, 82,88, 76,88, 69,84],metal[3])
	_stroke([67,78, 74,79, 82,84],0.75,metal[5])
	if "mail" in name or "byrnie" in name or "hauberk" in name:
		for row in range(3):
			for column in range(8):
				var x := 30.0+float(column)*4.0+float(row%2)*2.0
				var y := 86.0+float(row)*4.0
				_stroke([x,y, x,y+1, x+2,y+1, x+2,y],0.55,metal[1])
				_px(int(x),int(y-1),metal[5])
	elif "scale" in name or "lamellar" in name or "scrap" in name:
		for row in range(2):
			for column in range(5):
				var x := 27.0+float(column)*8.0+float(row)*2.0
				var y := 86.0+float(row)*6.0
				_poly([x,y, x+6,y-1, x+7,y+4, x+3,y+5, x,y+3],metal[3 if column<3 else 2])
				_stroke([x,y, x+5,y-1],0.6,metal[5])
	else:
		_stroke([25,91, 36,90, 44,92],0.6,metal[5])
		_stroke([53,92, 62,90, 69,91],0.6,metal[2])
	for point in [Vector2(20,80),Vector2(28,79),Vector2(73,83),Vector2(79,86)]:
		_px(int(point.x),int(point.y),secondary.lightened(0.18))
		_px(int(point.x)+1,int(point.y)+1,metal[0])

func _hair_point(x: float,y: float) -> Vector2:
	return Vector2(96.0-x if mirror_hair else x,y)

func _hair(coords: Array, root: float, tip: float = 0.25, bias: float = 0.0) -> void:
	_lock(_hair_point(coords[0],coords[1]),_hair_point(coords[2],coords[3]),_hair_point(coords[4],coords[5]),root,tip,hair_ramp,bias)

func _lock(a: Vector2,b: Vector2,c: Vector2,r0: float,r1: float,palette: Array[Color],bias: float = 0.0) -> void:
	# A tapered Bezier lock carries its highlight and continuous strand grooves.
	var path := PackedVector2Array()
	var lo := a.min(b).min(c)-Vector2.ONE*(r0+1.0)
	var hi := a.max(b).max(c)+Vector2.ONE*(r0+1.0)
	for i in range(25):
		var t := float(i)/24.0
		path.append(a*(1.0-t)*(1.0-t)+b*2.0*t*(1.0-t)+c*t*t)
	for y in range(maxi(0,int(floor(lo.y))),mini(SIZE,int(ceil(hi.y))+1)):
		for x in range(maxi(0,int(floor(lo.x))),mini(SIZE,int(ceil(hi.x))+1)):
			var p := Vector2(x+0.5,y+0.5)
			var best := 1.0e10
			var along := 0.0
			var transverse := 0.0
			for i in range(24):
				var delta := path[i+1]-path[i]
				var f := clampf((p-path[i]).dot(delta)/maxf(0.0001,delta.length_squared()),0.0,1.0)
				var q := path[i]+delta*f
				var distance := q.distance_squared_to(p)
				if distance<best:
					best=distance
					along=(float(i)+f)/24.0
					transverse=(p-q).dot(Vector2(delta.y,-delta.x).normalized())
			var radius := lerpf(r0,r1,pow(along,1.30))
			if best>radius*radius:
				continue
			var u := transverse/maxf(0.2,radius)
			var light := 0.58-u*0.25-along*0.17+bias
			if absf(u+0.27+sin(along*3.0)*0.13)<0.16:
				light+=0.17
			if absf(u-0.42)<0.11:
				light-=0.18
			if absf(u)>0.87:
				light-=0.20
			_px(x,y,palette[clampi(int(light*7.0),0,6)])

func _hair_back() -> void:
	if helm_kind=="closed":
		return
	if helm_kind=="coif":
		var hood := _metal(helm)
		_ellipse(Vector2(center,36),Vector2(half+6,29),hood,-0.18)
		_poly([center-half-5,37, center+half+5,37, 77,77, 62,83, 31,82, 20,74],hood[1])
		return
	if female:
		if elder:
			_hair([28,29,19,51,29,71],5.5,0.6)
			_hair([67,25,79,47,73,70],7,2.0,-0.10)
			_hair([69,45,79,65,68,84],5.0,0.6)
		else:
			_hair([30,25,19,44,24,71],7.0,1.4)
			_hair([25,43,18,64,29,83],5.5,0.5)
			_hair([32,40,25,60,35,76],5.0,0.4)
			_hair([65,24,81,45,72,74],8.0,1.2,-0.12)
			_hair([73,44,82,68,70,86],5.6,0.4,-0.10)
			_hair([66,48,70,68,60,79],4.5,0.3,-0.08)
	elif elder:
		_hair([29,26,21,35,29,51],4.0,0.3)
		_hair([67,25,76,36,68,54],4.5,0.5,-0.08)
	elif not young:
		_hair([61,15,70,6,69,19],6.0,1.0)
		_hair([64,14,75,19,64,25],5.0,0.3,-0.10)

func _hair_front() -> void:
	if helm_kind=="coif":
		return
	if female:
		if elder:
			_hair([29,29,26,15,43,15],5.0,0.4,0.07)
			_hair([31,26,34,11,50,15],4.8,0.6,0.13)
			_hair([39,19,50,8,59,18],4.6,0.5,0.06)
			_hair([48,18,65,10,68,29],6.0,0.9)
			_hair([57,20,72,20,68,40],5.0,0.4,-0.05)
			_braid()
		else:
			_hair([34,26,25,17,42,13],5.0,0.4,0.08)
			_hair([31,30,29,12,48,13],6.0,0.7,0.14)
			_hair([36,23,41,7,53,15],6.0,0.3,0.10)
			_hair([47,17,62,8,67,24],6.0,0.5)
			_hair([55,18,73,22,67,41],6.0,0.5,-0.03)
			_hair([44,17,33,19,29,35],4.1,0.2,0.08)
			_hair([62,27,70,40,65,57],3.2,0.3,-0.12)
			_hair([27,43,22,57,30,75],3.6,0.2,0.02)
	elif young:
		_hair([39,24,34,12,46,9],4.3,0.2)
		_hair([43,22,43,3,54,10],5.0,0.4,0.12)
		_hair([48,22,52,5,62,13],5.0,0.5,0.04)
		_hair([52,24,66,13,64,29],4.2,0.3,-0.08)
		_hair([56,23,61,27,57,31],2.7,0.15,-0.10)
		_hair([44,18,46,24,42,29],2.8,0.15,0.04)
		_hair([31,30,29,34,31,38],1.6,0.1,-0.10)
	else:
		if elder:
			_hair([29,30,22,21,36,17],4.0,0.2)
			_hair([29,25,29,13,44,15],4.2,0.25,0.14)
			_hair([34,19,38,11,48,16],3.3,0.15,0.12)
			_hair([58,18,69,13,69,32],4.7,0.3,-0.03)
			_hair([64,27,73,31,67,48],3.8,0.2,-0.08)
		else:
			_hair([32,29,31,18,44,16],4.6,0.2,0.04)
			_hair([35,19,37,11,44,10],2.4,0.2,0.08)
			_hair([35,24,40,11,55,15],5.2,0.4,0.12)
			_hair([42,20,51,10,64,17],5.1,0.5,0.03)
			_hair([51,20,63,15,68,25],5.0,0.25,-0.08)
			_hair([64,24,70,26,67,35],2.8,0.1,-0.10)

func _braid() -> void:
	for i in range(7):
		var y := 43.0+float(i)*5.3
		var x := 70.0+sin(float(i)*0.5)*2.0
		_hair([x-1,y, x+6,y+3, x,y+7],2.8,0.5,-0.06)
		_hair([x+1,y, x-5,y+3, x,y+7],2.6,0.4,0.06)
	var cuff := _hair_point(70.5,81.0)
	_stroke([cuff.x-2,cuff.y, cuff.x+2,cuff.y],1.0,secondary)
	_hair([70,83,68,87,68,90],2.6,0.2)

func _beard() -> void:
	if not bearded or _lost("jaw"):
		return
	var y := mouth_y+5.0
	var length := 13.0 if not elder else 19.0
	if young:
		length*=0.6
	if female:
		length*=0.7
	if beard_style==6:
		_lock(Vector2(center-2,mouth_y-2),Vector2(center-8,mouth_y-3),Vector2(center-11,mouth_y+2),1.7,0.2,beard_ramp)
		_lock(Vector2(center+3,mouth_y-2),Vector2(center+8,mouth_y-3),Vector2(center+11,mouth_y+2),1.7,0.2,beard_ramp,-0.08)
		return
	if beard_style==7:
		length=4.0
	var goatee := beard_style==1 or beard_style==3
	var width := 6.5 if goatee else 13.0
	if not goatee:
		for side in [-1,1]:
			var s := float(side)
			_lock(Vector2(center+s*16,mouth_y-1),Vector2(center+s*17,mouth_y+6),Vector2(center+s*9,y+length-3),3.5,0.4,beard_ramp,-0.08 if side>0 else 0.03)
	for i in range(7):
		var u := float(i)/6.0*2.0-1.0
		var start := Vector2(center+u*width,y+absf(u)*1.5)
		var end := Vector2(center+u*width*0.55,y+length-absf(u)*4.0-float(i%2)*1.5)
		if beard_style==4:
			end.x+=signf(u)*3.0
		_lock(start,Vector2(start.x+u*2.5-1.0,y+length*0.65),end,3.1 if goatee else 3.9,0.25,beard_ramp,0.07 if i<3 else -0.06)
	if beard_style==5:
		_stroke([center-5,y+length-4, center-1,y+length-4],0.8,secondary)
		_stroke([center+3,y+length-5, center+7,y+length-5],0.8,secondary.darkened(0.16))

func _tusks() -> void:
	if _lost("mouth") or _lost("jaw"):
		return
	var length := 6.5 if young else (13.0 if elder else 10.5)
	if female:
		length*=0.90
	var spread := 8.0 if young else 9.8
	for side in [-1,1]:
		var x: float = center+1.0+float(side)*spread
		var base := mouth_y+4.0
		_ellipse(Vector2(x,base),Vector2(2.8,1.7),skin_ramp,-0.25)
		# LOWER tusks: root at lower lip, point above upper lip.
		for step in range(int(ceil(length))+1):
			var t := minf(1.0,float(step)/length)
			var mid: float = x+float(side)*sin(t*PI*0.5)*2.0
			var width := maxf(0.25,2.25*pow(1.0-t,0.70))
			var y := int(base)-step
			_px(int(round(mid-width-0.7)),y,skin_ramp[1])
			_px(int(round(mid+width+0.7)),y,skin_ramp[1])
			for tx in range(int(ceil(mid-width)),int(floor(mid+width))+1):
				var col := Color("#e7d7ab")
				if float(tx)<mid-0.25:
					col=Color("#fff0cc")
				elif float(tx)>mid+0.60:
					col=Color("#ae9669")
				if step==0:
					col=col.darkened(0.15)
				_px(tx,y,col)
			if t>=0.95:
				_px(int(round(mid)),y,Color("#fff0cc"))

func _closed_helmet() -> void:
	var metal := _metal(helm)
	_ellipse(Vector2(center,35),Vector2(24,25),metal,0.01)
	_poly([center-22,30, center+22,30, center+21,58, center+13,66, center-14,65, center-22,55],metal[2])
	_poly([center-20,32, center-2,32, center-2,63, center-13,62, center-20,53],metal[4])
	_stroke([center,16, center,62],1.1,metal[5])
	_stroke([center-17,38, center-3,39],1.1,metal[0])
	_stroke([center+4,39, center+17,38],1.1,metal[0])
	_stroke([center-17,36, center-3,37],0.7,metal[6])
	for i in range(4):
		_stroke([center+6+float(i)*3,49, center+6+float(i)*3,55],0.6,metal[0])

func _helmet() -> void:
	if helm_kind=="none" or helm_kind=="coif":
		return
	var metal := _metal(helm)
	if helm_kind=="crown":
		_stroke([center-18,29, center,31, center+18,29],1.7,metal[4])
		for i in range(5):
			var x := center-14+float(i)*7
			_poly([x-2,29, x,21-float(i%2)*3, x+2,29],metal[5])
		return
	for y in range(10,33):
		for x in range(int(center-25),int(center+25)):
			var u := (float(x)+0.5-center)/24.0
			var v := (float(y)+0.5-31.0)/21.0
			if u*u+v*v<=1.0:
				var light := 0.69-u*0.28-v*0.18
				_px(x,y,metal[clampi(int(light*7.0),0,6)])
	_stroke([center-23,32, center,34, center+23,32],1.3,metal[1])
	_stroke([center-21,31, center,32, center+20,31],0.6,metal[5])
	if helm_kind=="kettle":
		_stroke([center-30,33, center,35, center+29,33],1.0,metal[3])
	if helm_kind=="nasal":
		_stroke([center+1,31, center+1,49],1.4,metal[2])
		_stroke([center,31, center,48],0.65,metal[6])
	if "spangen" in String(helm.get("sprite","")):
		_stroke([center,12, center,31],1.0,metal[5])

func _wound(c: Vector2, radius: float) -> void:
	_ellipse(c,Vector2(radius,radius*0.8),[Color("#401b20"),Color("#542024"),Color("#6e2927"),Color("#8b342d"),Color("#a74434"),Color("#b95039"),Color("#c45c40")])

func _outline() -> void:
	var source := image.duplicate()
	for y in range(SIZE):
		for x in range(SIZE):
			if source.get_pixel(x,y).a>0.5:
				continue
			for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var q: Vector2i = Vector2i(x,y)+delta
				if q.x>=0 and q.x<SIZE and q.y>=0 and q.y<SIZE and source.get_pixel(q.x,q.y).a>0.5:
					_px(x,y,INK)
					break
