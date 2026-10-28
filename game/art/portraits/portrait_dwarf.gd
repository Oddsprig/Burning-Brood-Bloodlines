extends RefCounted
## Dwarf portraits: sculpted faces, swept locks and interwoven beard braids.
## Everything is painted on the native pixel grid; no filtering or dithering.

const SIZE := 96
const EDGE := Color("#211b22")
const LIGHT := Vector3(-0.48, -0.60, 0.64)
const WHITE := Color("#f4eee0")
const INK := Color("#211923")
const ARMOR := ["cuirass", "mail", "scale", "lamellar", "scrap", "byrnie", "plate", "brigandine", "hauberk", "breastplate"]

var image: Image
var spec: Dictionary
var female := false
var young := false
var elder := false
var dead := false
var seed := 1
var skin := Color.WHITE
var hair := Color.WHITE
var primary := Color.WHITE
var secondary := Color.WHITE
var skin_ramp: Array[Color]
var hair_ramp: Array[Color]
var beard_ramp: Array[Color]
var cloth: Array[Color]
var gold: Array[Color]
var body: Dictionary
var helm: Dictionary
var lost := {}
var beard_on := false
var beard_style := 0
var eye_y := 35
var mouth_y := 53
var face_width := 21.0
var hair_part := 54.0

static func paint(spec: Dictionary) -> Image:
	return load("res://art/portraits/portrait_dwarf.gd").new()._render(spec)

func _render(sp: Dictionary) -> Image:
	spec = sp
	_read()
	image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_shoulders()
	if _missing("head"):
		_ellipse(Vector2(48, 66), Vector2(9, 4), _ramp(Color("#852f35")))
	else:
		_hair_back()
		_neck()
		_face()
		_ears()
		_hair_front()
		_eye(39, true)
		_eye(58, false)
		_nose()
		_mouth()
		_age_lines()
		if beard_on:
			_beard()
		elif female:
			_hair_braids()
		_headgear()
		_wounds()
	_outline()
	return image

func _read() -> void:
	female = String(spec.get("sex", "male")) == "female"
	var age := int(spec.get("age", 70))
	young = age < 42
	elder = age >= 120
	dead = bool(spec.get("dead", false))
	seed = absi(int(spec.get("seed", 1)))
	beard_style = clampi(int(spec.get("beard_style", 0)), 0, 7)
	skin = _color(spec.get("skin"), Color("#d4a17f"))
	hair = _color(spec.get("hair"), Color("#77452c"))
	primary = _color(spec.get("prim"), Color("#8f2c24"))
	secondary = _color(spec.get("sec"), Color("#e0a838"))
	body = spec.get("body", {}) if spec.get("body", {}) is Dictionary else {}
	helm = spec.get("helm", {}) if spec.get("helm", {}) is Dictionary else {}
	var raw = spec.get("lost", [])
	if raw is Array:
		for id in raw:
			lost[String(id)] = true
	var blood := clampf(float(spec.get("blood", 1.0)), 0.0, 1.0)
	skin = skin.lerp(Color("#cec7be"), (1.0 - blood) * 0.45)
	if dead:
		skin = skin.lerp(Color("#929492"), 0.45)
	if elder:
		hair = hair.lerp(Color("#dedad2"), 0.60)
	var beard = spec.get("beard", false)
	var beard_color := hair
	if beard is bool:
		beard_on = beard
	elif beard is Color:
		beard_on = true
		beard_color = beard
		if elder:
			beard_color = beard_color.lerp(Color("#dedad2"), 0.60)
	elif beard is String:
		beard_on = beard != "" and beard != "false"
		beard_color = _color(beard, hair)
		if elder:
			beard_color = beard_color.lerp(Color("#dedad2"), 0.60)
	skin_ramp = _ramp(skin)
	hair_ramp = _ramp(hair, true)
	beard_ramp = _ramp(beard_color, true)
	cloth = _ramp(primary)
	gold = _ramp(secondary)
	face_width = (19.0 if female else 21.0) + float(seed % 3 - 1) * 0.4
	if young:
		face_width -= 0.8
	if elder:
		eye_y += 1
		mouth_y += 1
	if female:
		mouth_y -= 1
	hair_part = 43.0 if int(spec.get("female_set", seed % 2)) % 2 == 1 else 54.0

func _color(value: Variant, fallback: Color) -> Color:
	var result := fallback
	if value is Color:
		result = value
	elif value is String and Color.html_is_valid(value):
		result = Color(value)
	result.a = 1.0
	return result

func _ramp(base: Color, fiber: bool = false) -> Array[Color]:
	var shadow := base.darkened(0.66).lerp(Color("#252033"), 0.22)
	var top := base.lightened(0.35).lerp(Color("#fff0cf"), 0.18)
	if fiber:
		top = base.lightened(0.44).lerp(Color("#fbe5bf"), 0.17)
	return [shadow, shadow.lerp(base, 0.28), shadow.lerp(base, 0.53), shadow.lerp(base, 0.78), base, base.lerp(top, 0.48), top]

func _px(x: int, y: int, color: Color) -> void:
	if x >= 0 and y >= 0 and x < SIZE and y < SIZE:
		image.set_pixel(x, y, color)

func _missing(id: String) -> bool:
	return bool(lost.get(id, false))

func _line(a: Vector2, b: Vector2, color: Color, width: float = 0.6) -> void:
	var lo := a.min(b) - Vector2.ONE * width
	var hi := a.max(b) + Vector2.ONE * width
	for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y)) + 1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x)) + 1)):
			var p := Vector2(x, y)
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= width * width:
				_px(x, y, color)

func _polygon(coords: Array, ramp: Array[Color], bias: float = 0.0) -> void:
	var points := PackedVector2Array()
	var lo := Vector2(SIZE, SIZE)
	var hi := Vector2.ZERO
	for i in range(0, coords.size(), 2):
		var p := Vector2(float(coords[i]), float(coords[i + 1]))
		points.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(maxi(0, int(lo.y)), mini(SIZE, int(hi.y) + 1)):
		for x in range(maxi(0, int(lo.x)), mini(SIZE, int(hi.x) + 1)):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				var light := 4.8 - float(x - 20) * 0.035 - float(y - 66) * 0.042 + bias
				_px(x, y, ramp[clampi(int(round(light)), 0, 6)])

func _ellipse(center: Vector2, radius: Vector2, ramp: Array[Color], bias: float = 0.0) -> void:
	for y in range(maxi(0, int(center.y - radius.y)), mini(SIZE, int(center.y + radius.y) + 1)):
		for x in range(maxi(0, int(center.x - radius.x)), mini(SIZE, int(center.x + radius.x) + 1)):
			var uv := (Vector2(x, y) - center) / radius
			var d := uv.length_squared()
			if d <= 1.0:
				var normal := Vector3(uv.x, uv.y, sqrt(1.0 - d))
				var light := 2.0 + normal.dot(LIGHT) * 4.4 + bias
				_px(x, y, ramp[clampi(int(round(light)), 0, 6)])

func _lock(a: Vector2, control: Vector2, b: Vector2, root: float, tip: float, ramp: Array[Color], bias: float = 0.0) -> void:
	# Tapered Bezier locks, shaded across the strand, with long highlight ribbons.
	var points: Array[Vector2] = []
	var lo := a.min(b).min(control) - Vector2.ONE * (root + 1.0)
	var hi := a.max(b).max(control) + Vector2.ONE * (root + 1.0)
	for i in 17:
		var t := float(i) / 16.0
		points.append(a * (1.0 - t) * (1.0 - t) + 2.0 * control * t * (1.0 - t) + b * t * t)
	for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y)) + 1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x)) + 1)):
			var p := Vector2(x, y)
			var distance := INF
			var nearest := Vector2.ZERO
			var tangent := Vector2.DOWN
			var along := 0.0
			for i in 16:
				var q := Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1])
				var d := p.distance_squared_to(q)
				if d < distance:
					distance = d
					nearest = q
					tangent = (points[i + 1] - points[i]).normalized()
					along = (float(i) + points[i].distance_to(q) / maxf(0.001, points[i].distance_to(points[i + 1]))) / 16.0
			var radius := lerpf(root, tip, along)
			if distance > radius * radius:
				continue
			var normal := Vector2(tangent.y, -tangent.x)
			if normal.x < 0.0:
				normal = -normal
			var cross := clampf((p - nearest).dot(normal) / maxf(0.5, radius), -1.0, 1.0)
			var shine := 3.1 + sqrt(maxf(0.0, 1.0 - cross * cross)) * 1.3 - cross * 1.6 - along * 0.65 + bias
			# Fine grooves follow the whole curve; they never alternate by pixel.
			if absf(cross - 0.22) < 0.10 or absf(cross + 0.70) < 0.08:
				shine -= 0.7
			if cross > 0.85:
				shine = 1.0 + bias
			_px(x, y, ramp[clampi(int(round(shine)), 0, 6)])

func _armored() -> bool:
	var name := (String(body.get("sprite", "")) + " " + String(body.get("tid", ""))).to_lower()
	for kind in ARMOR:
		if kind in name:
			return true
	return false

func _metal(item: Dictionary) -> Array[Color]:
	var material := String(item.get("mat", "iron"))
	var metal: Dictionary = FigurePainter.metal(material if material != "" else "iron", int(item.get("q", 0)))
	var base: Color = metal["base"]
	var dark: Color = metal["dark"]
	var light: Color = metal["light"]
	var shine: Color = metal["shine"]
	return [dark.darkened(0.30), dark, dark.lerp(base, 0.5), base, base.lerp(light, 0.5), light, shine]

func _shoulders() -> void:
	var left_y := 75 if young else (78 if elder else 72)
	var right_y := 78 if young else (77 if elder else 75)
	var edge := 8 if young or elder else 4
	if female:
		left_y += 1
		edge += 1
	var ld := left_y - 74
	var rd := right_y - 76
	_polygon([edge,96, edge + 2,left_y + 8, 14,left_y, 32,65, 38,64, 58,64, 66,67, 83,right_y, 94 - edge,right_y + 9, 96 - edge,96], cloth)
	_polygon([edge,96, edge + 3,82 + ld, 16,75 + ld, 33,69, 40,75, 28,85 + ld, 25,96], cloth, 0.6)
	_polygon([69,96, 61,77, 65,68, 82,77 + rd, 93 - edge,86 + rd, 95 - edge,96], cloth, -0.5)
	# Fold valleys and their narrow lit edges follow the slope of each shoulder.
	_line(Vector2(15,80 + ld), Vector2(31,75), cloth[2], 1.0)
	_line(Vector2(15,79 + ld), Vector2(29,75), cloth[5])
	_line(Vector2(13,90 + ld), Vector2(28,82), cloth[2], 1.1)
	_line(Vector2(16,88 + ld), Vector2(27,81), cloth[4])
	_line(Vector2(79,82 + rd), Vector2(69,77), cloth[1], 1.0)
	_line(Vector2(84,94), Vector2(76,84 + rd), cloth[1], 1.1)
	if _armored():
		var metal := _metal(body)
		_polygon([26,96, 29,78, 39,70, 59,70, 73,80, 78,96], metal, -0.2)
		var kind := String(body.get("sprite", ""))
		if kind in ["mail", "byrnie", "hauberk", "scale", "lamellar"]:
			for y in range(78, 96, 3):
				for x in range(29 + (int(y / 3.0) % 2) * 2, 75, 4):
					if image.get_pixel(x, y).a < 0.5:
						continue
					_px(x, y, metal[1])
					_px(x + 1, y + 1, metal[1])
					_px(x + 2, y, metal[4 if x < 49 else 3])
		_polygon([9,81 + ld, 14,74 + ld, 28,69, 35,73, 30,81, 17,85 + ld], metal, 0.7)
		_polygon([65,73, 72,72 + rd, 84,79 + rd, 88,86 + rd, 76,86 + rd, 68,81], metal, -0.4)
		_line(Vector2(14,76 + ld), Vector2(28,71), metal[6])
		_line(Vector2(11,82 + ld), Vector2(29,79), metal[1], 1.0)
		_line(Vector2(69,77), Vector2(84,83 + rd), metal[1], 1.0)
		for x in [17, 25, 74, 82]:
			_px(x, 79 if x < 49 else 81, metal[6])
	elif female:
		_polygon([29,76, 35,72, 67,92, 69,96, 56,96], cloth, 0.5)
		_line(Vector2(32,77), Vector2(59,95), gold[3])
		_line(Vector2(39,82), Vector2(62,94), cloth[2])
	elif elder:
		_polygon([18,80, 28,73, 61,94, 64,96, 47,96], cloth, 0.4)
		_line(Vector2(22,80), Vector2(49,95), gold[2])
		_line(Vector2(19,86), Vector2(35,91), cloth[2])
	else:
		# Broad folded mantle and an oblique leather fastening.
		_polygon([26,75, 31,73, 61,96, 51,96], _ramp(Color("#624332")), -0.1)
		_line(Vector2(29,76), Vector2(55,95), gold[2])
	_polygon([30,66, 37,63, 47,74, 39,80, 30,73], cloth, 0.8)
	_polygon([58,64, 66,68, 67,76, 59,79, 50,74], cloth, 0.1)
	_line(Vector2(31,67), Vector2(40,76), gold[4])
	_line(Vector2(59,66), Vector2(64,72), gold[3])
	_ellipse(Vector2(24, 77), Vector2(3.5, 3.5), gold)
	_ellipse(Vector2(24, 77), Vector2(1.5, 1.5), cloth, 0.5)

func _neck() -> void:
	_polygon([38,57, 57,57, 59,69, 64,73, 54,79, 42,77, 34,70, 38,65], skin_ramp, -0.4)
	_line(Vector2(56,61), Vector2(54,70), skin_ramp[1], 1.3)
	_line(Vector2(40,66), Vector2(43,72), skin_ramp[4], 1.0)

func _half_width(y: float) -> float:
	var profile := [Vector2(13, 0.28), Vector2(18, 0.73), Vector2(26, 0.96), Vector2(35, 0.97), Vector2(43, 1.0), Vector2(50, 0.88), Vector2(57, 0.67), Vector2(62, 0.36), Vector2(64, 0.06)]
	if young:
		profile[5] = Vector2(50, 0.86)
	if female:
		profile[6] = Vector2(57, 0.61)
	for i in range(profile.size() - 1):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		if y >= a.x and y <= b.x:
			return lerpf(a.y, b.y, (y - a.x) / (b.x - a.x)) * face_width
	return 0.0

func _face() -> void:
	for y in range(13, 65):
		var half := _half_width(float(y))
		for x in range(int(48.0 - half), int(49.0 + half)):
			var u := (float(x) - 48.0) / maxf(half, 1.0)
			if absf(u) > 1.0:
				continue
			var v := (float(y) - 35.0) / 30.0
			var z := sqrt(maxf(0.0, 1.0 - u * u))
			var light := 2.2 + Vector3(u * 0.80, v * 0.70, z).normalized().dot(LIGHT) * 3.8
			# Continuous cheek, temple, socket and muzzle planes underneath the features.
			var cheek := exp(-pow((float(x) - 36.0) / 7.0, 2.0) - pow((float(y) - 44.0) / 5.0, 2.0))
			var socket := exp(-pow((float(y) - float(eye_y)) / 3.3, 2.0)) * (exp(-pow((float(x) - 39.0) / 5.0, 2.0)) + exp(-pow((float(x) - 58.0) / 4.5, 2.0)))
			light += cheek * (0.4 if young else 0.7) - socket * 0.90
			if y > 49:
				light -= float(y - 49) * 0.075
			if elder and absf(u) > 0.46 and y > 43:
				light -= 0.35
			var color := skin_ramp[clampi(int(round(light)), 0, 6)]
			if young and y > 40 and y < 49:
				var blush := cheek * 0.16
				color = color.lerp(skin.lerp(Color("#c96c61"), 0.38), blush)
			_px(x, y, color)
	if not beard_on:
		_line(Vector2(42,59), Vector2(49,60), skin_ramp[4])
		_line(Vector2(54,49), Vector2(57,53), skin_ramp[2])

func _ears() -> void:
	for side in [-1, 1]:
		var x := 48.0 + float(side) * (face_width - 0.2)
		if _missing("ear_r" if side < 0 else "ear_l"):
			continue
		_ellipse(Vector2(x, 39), Vector2(3.5, 6), skin_ramp, 0.0 if side < 0 else -0.7)
		_line(Vector2(x + side, 35), Vector2(x + side, 40), skin_ramp[1])
		_line(Vector2(x, 38), Vector2(x - side, 42), skin_ramp[2])
		if female:
			_ellipse(Vector2(x + side, 44), Vector2(1.6, 2.0), gold)

func _eye(xc: int, near: bool) -> void:
	var y := eye_y
	var outer := -1 if near else 1
	var socket := skin_ramp[1].lerp(skin, 0.28)
	_line(Vector2(xc - 4, y - 1), Vector2(xc + 4, y - 1), socket, 1.1)
	if dead or _missing("eye_r" if near else "eye_l"):
		_line(Vector2(xc - 4, y), Vector2(xc + 4, y + 1), INK)
	else:
		var iris := _color(spec.get("eyes"), Color("#674728"))
		for dx in range(-4, 5):
			var height := 0 if absi(dx) == 4 else (1 if elder or absi(dx) >= 3 else 2)
			for dy in range(0, height + 1):
				_px(xc + dx, y + dy, WHITE if near else WHITE.darkened(0.10))
			_px(xc + dx, y - 1 if absi(dx) < 3 else y, skin_ramp[0])
		var gaze := clampi(seed % 5 - 2, -1, 1)
		for dy in range(0, 3 if not elder else 2):
			_px(xc + gaze - 1, y + dy, iris)
			_px(xc + gaze, y + dy, INK)
		_px(xc + gaze - 1, y, WHITE)
		_line(Vector2(xc - 2, y + 3), Vector2(xc + 3, y + 3), skin_ramp[2])
		_px(xc - 2, y + 4, skin_ramp[5] if near else skin_ramp[3])
	# Independent arched brows; skin remains visible between brow and eyelid.
	for dx in range(-5, 6):
		var towards_nose := -float(dx * outer) / 5.0
		var arch := -1 if absi(dx) < 3 else 0
		var by := y - 5 + arch + (int(round(towards_nose)) if not young else 0)
		var thickness := 2 if female or young else 3
		for dy in thickness:
			_px(xc + dx, by + dy, hair_ramp[2 if dy == 0 and near else 1])
		if dx < 2:
			_px(xc + dx, by - 1, skin_ramp[5] if near else skin_ramp[3])
		if elder and dx % 3 == 0:
			_px(xc + dx, by, hair_ramp[5])

func _nose() -> void:
	if _missing("nose"):
		return
	var nx := 50 + int(seed % 2)
	var bottom := 47 if female or young else 48
	for y in range(eye_y - 1, bottom):
		var t := float(y - eye_y + 1) / float(bottom - eye_y + 1)
		var width := 3 + int(t * 1.8)
		for dx in range(-width, width + 1):
			var band := 5 if dx == -1 else (4 if dx < 1 else (3 if dx == 1 else 2))
			_px(nx + dx, y, skin_ramp[band])
	var radius := Vector2(5.5 if female else (6.0 if young else 7.0), 3.5)
	_ellipse(Vector2(nx - radius.x + 1.0, bottom), Vector2(2.4,2.5), skin_ramp, -0.2)
	_ellipse(Vector2(nx + radius.x - 1.0, bottom), Vector2(2.4,2.5), skin_ramp, -0.6)
	_ellipse(Vector2(nx, bottom - 1), radius, skin_ramp, 0.1)
	_line(Vector2(nx - 4, bottom + 1), Vector2(nx - 3, bottom + 1), skin_ramp[0])
	_line(Vector2(nx + 4, bottom + 1), Vector2(nx + 5, bottom), skin_ramp[0])
	_px(nx, bottom + 2, skin_ramp[2])
	_px(nx - 1, bottom - 2, skin_ramp[6])
	_px(nx - 2, bottom - 2, skin_ramp[5])

func _mouth() -> void:
	if _missing("mouth") or _missing("jaw"):
		return
	var lip := skin.lerp(Color("#9b5353"), 0.48 if female else 0.24)
	for dx in range(-5, 6):
		var bend := 1 if absi(dx) > 3 else 0
		if young:
			bend = -1 if absi(dx) > 3 else 0
		_px(50 + dx, mouth_y - 1 + bend, lip.darkened(0.14))
		_px(50 + dx, mouth_y + bend, skin_ramp[0].lerp(Color("#4c272c"), 0.35))
		if absi(dx) < 4:
			_px(50 + dx, mouth_y + 1, lip)
	_line(Vector2(47,mouth_y + 2), Vector2(51,mouth_y + 2), skin_ramp[5].lerp(lip, 0.24))
	_line(Vector2(47,mouth_y + 4), Vector2(52,mouth_y + 4), skin_ramp[2])

func _age_lines() -> void:
	if young:
		return
	var shade := skin_ramp[2]
	if elder:
		for y in [23, 26]:
			_line(Vector2(41,y), Vector2(48,y - 1), shade)
			_line(Vector2(49,y - 1), Vector2(57,y), shade)
			_line(Vector2(43,y + 1), Vector2(53,y + 1), skin_ramp[5])
		for side in [-1, 1]:
			var x := 39 if side < 0 else 58
			_line(Vector2(x + side * 5,eye_y + 1), Vector2(x + side * 8,eye_y + 3), shade)
			_line(Vector2(x - 3,eye_y + 5), Vector2(x + 3,eye_y + 5), shade)
			_line(Vector2(x + side * 3,44), Vector2(x + side * 2,48), shade)
		_line(Vector2(43,49), Vector2(41,54), shade)
		_line(Vector2(58,49), Vector2(60,55), skin_ramp[1])
		_line(Vector2(44,52), Vector2(43,55), skin_ramp[5])
	else:
		_line(Vector2(48,29), Vector2(48,31), shade)
		_line(Vector2(35,44), Vector2(37,46), skin_ramp[3])

func _hair_back() -> void:
	for side in [-1, 1]:
		var x: float = 48.0 + float(side) * 20.0
		var end_y := 73.0 if female else (56.0 if young else 68.0)
		_lock(Vector2(x,24), Vector2(x + side * 6,44), Vector2(x + side * 3,end_y), 6.5, 2.0, hair_ramp, -0.5)
		_lock(Vector2(x + side * 2,30), Vector2(x + side * 8,49), Vector2(x + side * 6,end_y - 3), 4.3, 0.6, hair_ramp, -0.7)

func _hair_front() -> void:
	if elder and not female:
		# Receding temples and a bare, lined forehead, with wisps swept backwards.
		for side in [-1, 1]:
			var x: float = 48.0 + float(side) * 17.0
			_lock(Vector2(x,21), Vector2(x + side * 7,25), Vector2(x + side * 4,45), 4.5, 2.0, hair_ramp)
			_lock(Vector2(x - side * 3,18), Vector2(x + side * 5,17), Vector2(x + side * 7,30), 3.2, 0.6, hair_ramp, 0.4)
		_lock(Vector2(40,16), Vector2(46,10), Vector2(54,15), 2.5, 0.5, hair_ramp, 0.5)
		_lock(Vector2(46,14), Vector2(54,12), Vector2(59,19), 2.0, 0.5, hair_ramp)
		return
	var part := hair_part
	# The crown consists of overlapping swept locks, never a filled cap.
	for i in range(5):
		var k := float(i)
		_lock(Vector2(part - 2 + k * 1.7,13 + k * 1.0), Vector2(36 - k * 1.5,7 + k * 1.9), Vector2(27 + k * 1.6,27 + k * 2.1), 5.2, 1.0, hair_ramp, 0.4 - k * 0.08)
	for i in range(4):
		var k := float(i)
		_lock(Vector2(part + k * 1.2,14 + k), Vector2(65 + k * 1.0,12 + k * 2), Vector2(68 - k * 0.6,29 + k * 3.0), 4.5, 0.9, hair_ramp, -0.3)
	if young and not female:
		_lock(Vector2(40,16), Vector2(36,9), Vector2(31,12), 3.3, 0.4, hair_ramp, 0.7)
		_lock(Vector2(50,16), Vector2(49,9), Vector2(44,9), 3.0, 0.4, hair_ramp, 0.5)
	for side in [-1, 1]:
		var x: float = 48.0 + float(side) * 19.0
		_lock(Vector2(x,28), Vector2(x + side * 2,34), Vector2(x + side,47 if not female else 43), 3.7, 1.1, hair_ramp, 0.1 if side < 0 else -0.5)

func _braid(a: Vector2, b: Vector2, radius: float, ramp: Array[Color]) -> void:
	var length := a.distance_to(b)
	var tangent := (b - a).normalized()
	var across := Vector2(tangent.y, -tangent.x)
	var knots := maxi(2, int(length / 4.5))
	_lock(a, (a + b) * 0.5 + across, b, radius, radius * 0.7, ramp, -0.6)
	for i in knots:
		var t := float(i) / float(knots)
		var center := a.lerp(b, t)
		var width := lerpf(radius, radius * 0.65, t)
		var step := length / float(knots)
		# Two alternating diagonal lobes visibly weave across the central seam.
		_lock(center - across * width * 0.50, center + across * width * 0.30 + tangent * 1.5, center + across * width * 0.50 + tangent * step, width * 0.60, width * 0.34, ramp, 0.4)
		_lock(center + across * width * 0.52, center - across * width * 0.20 + tangent * 1.8, center - across * width * 0.50 + tangent * step, width * 0.50, width * 0.30, ramp, -0.3)
	var tie := b - tangent * 1.0
	_line(tie - across * radius * 0.70, tie + across * radius * 0.70, gold[1], 1.6)
	_line(tie - across * radius * 0.65 - tangent, tie + across * radius * 0.65 - tangent, gold[5], 0.6)
	_px(int(tie.x - 1), int(tie.y - 1), gold[6])
	_lock(b, b + tangent * 3, b + tangent * 5, radius * 0.65, 0.3, ramp)

func _hair_braids() -> void:
	var flipped := int(spec.get("female_set", 0)) % 2 == 1
	for side in [-1, 1]:
		var x: float = 48.0 + float(side) * 21.0
		var length := 32.0 if elder else (39.0 if side < 0 else 34.0)
		if flipped:
			length += 2.0 * side
		_braid(Vector2(x,45), Vector2(x + side * 5,45 + length), 4.7 if elder else 4.2, hair_ramp)

func _beard() -> void:
	var end_y := 79 if young else (89 if elder else 87)
	if beard_style == 7:
		_short_beard()
		return
	elif beard_style == 6:
		_moustache()
		return
	if female:
		end_y -= 8
	var half := 21.0 if young else 24.0
	for y in range(43, end_y + 1):
		var t := float(y - 43) / float(end_y - 43)
		var width := half * (0.91 + sin(t * PI) * 0.13)
		if t > 0.65:
			width *= lerpf(1.0, 0.10 if beard_style == 3 else 0.32, (t - 0.65) / 0.35)
		for x in range(int(49 - width), int(50 + width)):
			var dx := absf(float(x - 50))
			var top := 57 if dx < 8 else (52 if dx < 15 else 44)
			if y < top:
				continue
			if beard_style == 1 and dx > 16 and t > 0.85:
				continue
			if beard_style == 4 and t > 0.75 and dx < (t - 0.75) * 12.0:
				continue
			var across := float(x - 49) / width
			var wave := sin(float(x) * 0.85 + sin(float(y) * 0.14) * 1.5)
			var lit := 4.5 - across * 1.6 - t * 0.8 + wave * 0.5
			_px(x, y, beard_ramp[clampi(int(round(lit)), 0, 6)])
	for side in [-1, 1]:
		var x: float = 49.0 + float(side) * 17.0
		var taper := 0.5 if beard_style == 3 else 1.0
		_lock(Vector2(x,45), Vector2(x + side * 9,58), Vector2(49 + side * 15 * taper,end_y - 6), 5.0, 1.0, beard_ramp, 0.0 if side < 0 else -0.5)
		_lock(Vector2(49 + side * 13,54), Vector2(49 + side * 19,67), Vector2(49 + side * 9 * taper,end_y), 4.5, 0.5, beard_ramp, 0.1)
	if beard_style == 3:
		_braid(Vector2(49,61), Vector2(49,end_y), 4.5, beard_ramp)
	else:
		var spread := 9.0 if young else 12.0
		var braid_start := 62.0 if young else 61.0
		for side in [-1, 1]:
			_braid(Vector2(49 + side * spread,braid_start), Vector2(49 + side * (spread - 2),end_y - 2), 4.2 if young else 5.0, beard_ramp)
		if elder or beard_style == 5:
			_braid(Vector2(49,64), Vector2(48,end_y - 1), 4.0, beard_ramp)
		elif beard_style != 4:
			_lock(Vector2(49,59), Vector2(46,72), Vector2(48,end_y + 1), 4.2, 0.5, beard_ramp, 0.3)
	_moustache()

func _short_beard() -> void:
	# Close-cropped hair follows the existing jaw instead of replacing its shape.
	for y in range(48, 64):
		var half := _half_width(float(y))
		for x in range(int(48 - half), int(49 + half)):
			if absf(float(x - 50)) < 9.0 and y < mouth_y + 4:
				continue
			var original := image.get_pixel(x, y)
			if original.a > 0.5:
				var shade := beard_ramp[3 if x < 49 else 1]
				_px(x, y, original.lerp(shade, 0.48))
	for x in [35, 39, 44, 49, 54, 59]:
		var y := 55 if x < 42 or x > 57 else 59
		_line(Vector2(x,y), Vector2(x + 1,y + 2), beard_ramp[2].lerp(skin_ramp[3], 0.35))

func _moustache() -> void:
	if _missing("mouth") or _missing("jaw"):
		return
	for side in [-1, 1]:
		_lock(Vector2(50 + side * 2,mouth_y - 3), Vector2(50 + side * 8,mouth_y - 4), Vector2(50 + side * 12,mouth_y + 3), 2.8, 0.6, beard_ramp, 0.4 if side < 0 else -0.2)
	# Preserve the mouth opening and lower lip between both moustache lobes.
	_mouth()

func _headgear() -> void:
	var kind := (String(helm.get("sprite", "")) + " " + String(helm.get("tid", ""))).to_lower().strip_edges()
	if kind == "":
		return
	var metal := _metal(helm)
	if "crown" in kind or "circlet" in kind:
		_line(Vector2(29,25), Vector2(67,25), gold[2], 1.6)
		_line(Vector2(30,24), Vector2(66,24), gold[5])
		for x in [34, 42, 50, 58, 64]:
			_polygon([x - 2,24, x,17 if x == 50 else 20, x + 2,24], gold, 0.8)
		return
	if "hood" in kind or "coif" in kind:
		for side in [-1, 1]:
			_lock(Vector2(48 + side * 17,17), Vector2(48 + side * 31,36), Vector2(48 + side * 25,66), 5.2, 6.0, metal, -0.6)
		_ellipse(Vector2(48,17), Vector2(20,7), metal)
		return
	# Domed open helmets share the head contour; their forehead edge is curved.
	for y in range(9, 31):
		for x in range(24, 73):
			var u := (float(x) - 48) / 24.0
			var v := (float(y) - 31) / 23.0
			if u * u + v * v <= 1.0:
				var band := clampi(int(round(4.8 - u * 2.3 - float(y - 10) * 0.075)), 0, 6)
				_px(x, y, metal[band])
	_line(Vector2(26,30), Vector2(70,30), metal[1], 1.2)
	_line(Vector2(27,29), Vector2(69,29), metal[5])
	_line(Vector2(47,10), Vector2(47,28), metal[6])
	if "kettle" in kind:
		_line(Vector2(19,31), Vector2(77,31), metal[4], 1.5)
	if "nasal" in kind:
		_line(Vector2(50,29), Vector2(51,46), metal[1], 1.5)
		_line(Vector2(49,29), Vector2(50,46), metal[5])
	if "closed" in kind or "great" in kind or "barrel" in kind or "frog" in kind:
		_polygon([27,29, 69,29, 67,58, 51,65, 30,57], metal)
		_line(Vector2(33,36), Vector2(43,36), INK, 1.2)
		_line(Vector2(54,36), Vector2(64,36), INK, 1.2)
		_line(Vector2(49,30), Vector2(50,61), metal[5])
		for x in range(39, 62, 4):
			_line(Vector2(x,49), Vector2(x,53), metal[0])

func _wounds() -> void:
	for id in ["nose", "mouth", "jaw", "neck", "eye_r", "eye_l", "ear_r", "ear_l"]:
		if not _missing(id):
			continue
		var pos := Vector2(51,47)
		match id:
			"mouth": pos = Vector2(50,mouth_y)
			"jaw": pos = Vector2(49,60)
			"neck": pos = Vector2(48,68)
			"eye_r": pos = Vector2(39,eye_y)
			"eye_l": pos = Vector2(58,eye_y)
			"ear_r": pos = Vector2(27,39)
			"ear_l": pos = Vector2(69,39)
		_ellipse(pos, Vector2(2.5, 2.5), _ramp(Color("#8b3037")))

func _outline() -> void:
	var points: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if image.get_pixel(x, y).a < 0.5:
				continue
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q: Vector2i = Vector2i(x, y) + dir
				if q.x >= 0 and q.y >= 0 and q.x < SIZE and q.y < SIZE and image.get_pixel(q.x, q.y).a < 0.5:
					points.append(q)
	for p in points:
		_px(p.x, p.y, EDGE)
