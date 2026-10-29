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
	face_width = (22.0 if female else (20.5 if young else 23.0)) + float(seed % 3 - 1) * 0.35
	eye_y = 34 if young else 36
	mouth_y = 51 if young else 54
	if female:
		eye_y = 35 if young else 36
		mouth_y = 52 if young else 53
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
	# Each clump swells around its bend; its broken highlight follows that bend.
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
			var radius := lerpf(root, tip, along) * (1.0 + sin(along * PI) * 0.12)
			if distance > radius * radius:
				continue
			var normal := Vector2(tangent.y, -tangent.x)
			if normal.x < 0.0:
				normal = -normal
			var cross := clampf((p - nearest).dot(normal) / maxf(0.5, radius), -1.0, 1.0)
			var shine := 2.9 + sqrt(maxf(0.0, 1.0 - cross * cross)) * 1.4 - cross * 1.5 - along * 0.6 + bias
			var ridge := -0.38 + sin(along * 4.2 + a.x * 0.13) * 0.15
			if absf(cross - ridge) < 0.15 and along > 0.13 and along < 0.73:
				shine += 0.55
			var groove := 0.28 + sin(along * 5.0 + a.y * 0.28) * 0.16
			if absf(cross - groove) < 0.09 and along > 0.18 and along < 0.86:
				shine -= 0.55
			if cross > 0.25 and along > 0.40 and along < 0.82:
				shine -= 0.35
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
		left_y -= 2
		right_y -= 3
		edge -= 1
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
		var chest := PackedVector2Array([Vector2(26,96), Vector2(29,78), Vector2(39,70), Vector2(59,70), Vector2(73,80), Vector2(78,96)])
		for y in range(71, 96):
			for x in range(27, 78):
				if not Geometry2D.is_point_in_polygon(Vector2(x, y), chest):
					continue
				var u := float(x - 46) / 29.0
				var light := 3.65 - absf(u) * 1.7 - u * 0.75 - float(y - 76) * 0.05
				_px(x, y, metal[clampi(int(round(light)), 1, 5)])
		var kind := String(body.get("sprite", ""))
		if kind in ["mail", "byrnie", "hauberk", "scale", "lamellar"]:
			for row in range(76, 97, 3):
				for x in range(28 + (int(row / 3.0) % 2) * 2, 77, 4):
					var u := float(x - 46) / 29.0
					var y := row + int(u * u * 3.0)
					if y > 94 or not Geometry2D.is_point_in_polygon(Vector2(x + 1, y + 1), chest):
						continue
					var band := clampi(int(round(3.7 - absf(u) * 1.7 - u * 0.75 - float(y - 76) * 0.05)), 2, 4)
					_px(x, y, metal[band - 2])
					_px(x + 1, y + 1, metal[band - 1])
					_px(x + 1, y, metal[mini(5, band + 1)])
					_px(x + 2, y + 1, metal[band])
		_ellipse(Vector2(22,77 + ld), Vector2(13,5.5), metal, -0.1)
		_ellipse(Vector2(77,80 + rd), Vector2(12,5.0), metal, -0.8)
		_line(Vector2(13,76 + ld), Vector2(20,73 + ld), metal[5])
		_line(Vector2(21,73 + ld), Vector2(28,73 + ld), metal[5])
		_line(Vector2(14,81 + ld), Vector2(23,82 + ld), metal[2])
		_line(Vector2(72,83 + rd), Vector2(81,84 + rd), metal[1])
		_px(29, 77 + ld, metal[5])
		_px(71, 80 + rd, metal[4])
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
	if female:
		_polygon([36,57, 60,57, 60,64, 64,67, 56,72, 42,71, 33,67, 36,63], skin_ramp, -0.25)
		_ellipse(Vector2(49,64), Vector2(13,4), skin_ramp, -1.1)
		_line(Vector2(41,68), Vector2(45,69), skin_ramp[4])
		_polygon([29,66, 34,61, 39,64, 45,70, 42,75, 32,71], cloth, 0.7)
		_polygon([59,63, 65,63, 69,69, 58,75, 54,71], cloth, -0.2)
		_line(Vector2(34,64), Vector2(42,71), gold[4])
		_line(Vector2(62,65), Vector2(57,71), gold[3])
	else:
		_polygon([36,57, 59,57, 60,65, 63,68, 54,72, 42,71, 34,68, 37,63], skin_ramp, -0.7)
		_line(Vector2(56,63), Vector2(55,68), skin_ramp[2], 1.0)
		_polygon([30,67, 36,63, 42,69, 45,73, 39,77, 31,72], cloth, 0.6)
		_polygon([59,64, 65,67, 66,73, 58,77, 54,73], cloth, -0.1)
		_line(Vector2(33,67), Vector2(40,73), gold[4])

func _half_width(y: float) -> float:
	var profile := [Vector2(13, 0.28), Vector2(18, 0.73), Vector2(26, 0.96), Vector2(35, 0.99), Vector2(43, 1.02), Vector2(51, 0.96), Vector2(58, 0.85), Vector2(62, 0.65), Vector2(65, 0.36), Vector2(67, 0.08)]
	if female:
		profile[5] = Vector2(51, 1.0)
		profile[6] = Vector2(58, 0.91)
		profile[7] = Vector2(62, 0.77)
		profile[8] = Vector2(65, 0.52)
		profile[9] = Vector2(67, 0.22)
	elif young:
		profile[6] = Vector2(58, 0.83)
	for i in range(profile.size() - 1):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		if y >= a.x and y <= b.x:
			return lerpf(a.y, b.y, (y - a.x) / (b.x - a.x)) * face_width
	return 0.0

func _face() -> void:
	for y in range(13, 68):
		var half := _half_width(float(y))
		for x in range(int(48.0 - half), int(49.0 + half)):
			var u := (float(x) - 48.0) / maxf(half, 1.0)
			if absf(u) > 1.0:
				continue
			var v := (float(y) - 35.0) / 30.0
			var z := sqrt(maxf(0.0, 1.0 - u * u))
			var light := 2.65 + Vector3(u * 0.80, v * 0.65, z).normalized().dot(LIGHT) * 3.2
			# Full cheekbones turn into broad jaw planes, including on the elders.
			var cheek := exp(-pow((float(x) - 36.5) / 6.0, 2.0) - pow((float(y) - 45.0) / 5.0, 2.0))
			var far_cheek := exp(-pow((float(x) - 61.0) / 5.5, 2.0) - pow((float(y) - 45.0) / 4.5, 2.0))
			var jaw := exp(-pow((float(y) - 55.0) / 5.0, 2.0)) * (exp(-pow((float(x) - 36.0) / 5.0, 2.0)) + exp(-pow((float(x) - 60.0) / 5.0, 2.0)))
			var socket := exp(-pow((float(y) - float(eye_y)) / 3.3, 2.0)) * (exp(-pow((float(x) - 39.0) / 5.0, 2.0)) + exp(-pow((float(x) - 58.0) / 4.5, 2.0)))
			light += cheek * (0.55 if young else 0.75) + far_cheek * 0.45 + jaw * 0.45 - socket * 0.72
			if y > 54:
				light -= float(y - 54) * 0.055
			if not young:
				light -= exp(-pow((float(y) - 50.0) / 2.8, 2.0)) * absf(u) * 0.28
			var color := skin_ramp[clampi(int(round(light)), 0, 6)]
			if young and y > 40 and y < 49:
				var blush := cheek * 0.16
				color = color.lerp(skin.lerp(Color("#c96c61"), 0.38), blush)
			_px(x, y, color)
	if not beard_on:
		_line(Vector2(42,62), Vector2(48,63), skin_ramp[4])
		_line(Vector2(55,61), Vector2(58,60), skin_ramp[3])

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
	var y := eye_y + (1 if young and not female and not near else 0)
	var outer := -1 if near else 1
	var socket := skin_ramp[2].lerp(skin, 0.20)
	_line(Vector2(xc - 3, y - 1), Vector2(xc + 3, y - 1), socket, 1.0)
	if dead or _missing("eye_r" if near else "eye_l"):
		_line(Vector2(xc - 4, y), Vector2(xc + 4, y + 1), INK)
	else:
		var iris := _color(spec.get("eyes"), Color("#674728"))
		var sclera := WHITE.lerp(skin, 0.23 if young else 0.38)
		if not near:
			sclera = sclera.darkened(0.10)
		var gaze := -1 if young and not female else (1 if elder else 0)
		if seed % 3 == 0:
			gaze = 0
		for dx in range(-4, 5):
			var inner := -dx * outer
			var top := 1 if absi(dx) >= 3 else 0
			if not young and inner > 1:
				top += 1
			if elder and dx * outer > 1:
				top += 1
			var bottom := 3 if young and absi(dx) < 3 else 2
			if absi(dx) == 4:
				bottom = top
			for dy in range(top, bottom + 1):
				var color := sclera
				if absi(dx - gaze) <= 1:
					color = iris.lightened(0.22) if dy == bottom else iris.darkened(0.10)
					if dx == gaze and dy < bottom:
						color = INK
					if dx == gaze - 1 and dy == top and absi(dx) < 3:
						color = WHITE
				_px(xc + dx, y + dy, color)
			_px(xc + dx, y + top - 1, skin_ramp[0].lerp(hair_ramp[0], 0.22))
		_line(Vector2(xc - 2, y + 4), Vector2(xc + 1, y + 4), skin_ramp[3])
		_px(xc - 2, y + 5, skin_ramp[5] if near else skin_ramp[3])
	# Open, lifted young brows; low angled adult brows; uneven elder tufts.
	for dx in range(-5, 6):
		var inner := -dx * outer
		var by := y - 5 - (1 if absi(dx) < 3 else 0)
		if not young and not elder:
			by = y - 5 + int(floor(float(inner + 4) / 4.0))
		elif elder:
			by = y - 6 + (1 if absi(dx) > 2 else 0) + (1 if inner > 3 else 0)
		if female and not near:
			by -= 1
		var thickness := 2 if female or young or elder else 3
		for dy in thickness:
			_px(xc + dx, by + dy, hair_ramp[3 if elder and (dx + seed) % 4 == 0 else 1])
		if elder and dx in [-4, -1, 3]:
			_px(xc + dx, by - 1, hair_ramp[4])

func _nose() -> void:
	if _missing("nose"):
		return
	var nx := 50 + (1 if not young and not female else 0)
	var bottom := 46 if female else (44 if young else 48)
	for y in range(eye_y - 2, bottom):
		var t := float(y - eye_y + 2) / float(bottom - eye_y + 2)
		var center := float(nx) - 1.1 + t * 1.1
		var width := lerpf(1.8, 4.0 if young else 4.8, t)
		for x in range(int(center - width), int(center + width) + 1):
			var u := (float(x) - center) / width
			if absf(u) > 1.0:
				continue
			var light := 3.7 + sqrt(1.0 - u * u) * 1.35 - u * 0.85 - t * 0.25
			var blend := clampf((1.0 - absf(u)) * 2.0, 0.0, 0.90) * minf(1.0, t * 3.0)
			_px(x, y, image.get_pixel(x, y).lerp(skin_ramp[clampi(int(round(light)), 1, 6)], blend))
	var radius := Vector2(5.0 if female else (4.7 if young else 6.2), 2.8 if young else 3.0)
	_ellipse(Vector2(nx - radius.x + 0.6, bottom), Vector2(2.2,2.0), skin_ramp, -0.15)
	_ellipse(Vector2(nx + radius.x - 0.8, bottom), Vector2(2.0,2.0), skin_ramp, -0.55)
	_ellipse(Vector2(nx, bottom - 0.8), radius, skin_ramp, 0.2)
	var nostril := skin_ramp[1].lerp(skin, 0.22)
	_px(nx - int(radius.x) + 1, bottom + 1, nostril)
	_px(nx - int(radius.x) + 2, bottom + 2, skin_ramp[2])
	_px(nx + int(radius.x) - 1, bottom + 1, nostril)
	_px(nx + int(radius.x), bottom, skin_ramp[2])
	_px(nx, bottom + 2, skin_ramp[3])
	_px(nx - 2, bottom - 2, skin_ramp[6])

func _mouth() -> void:
	if _missing("mouth") or _missing("jaw"):
		return
	var lip := skin.lerp(Color("#a45e5a"), 0.55 if female else 0.28)
	var seam := skin_ramp[1].lerp(Color("#683b3a"), 0.38)
	for dx in range(-5, 6):
		var bend := 1 if elder and dx > 3 else (-1 if young and absi(dx) > 3 else 0)
		if absi(dx) < 4:
			_px(50 + dx, mouth_y - 1 + (1 if dx == 0 else 0), lip.darkened(0.12))
		_px(50 + dx, mouth_y + bend, seam.lerp(skin, 0.24 if absi(dx) == 5 else 0.0))
		if absi(dx) < 4:
			_px(50 + dx, mouth_y + 1, lip)
	_line(Vector2(48,mouth_y + 2), Vector2(51,mouth_y + 2), lip.lightened(0.20))
	_px(48, mouth_y + 4, skin_ramp[3])
	_px(49, mouth_y + 4, skin_ramp[3])

func _age_lines() -> void:
	if young:
		return
	var shade := skin_ramp[2].lerp(skin_ramp[3], 0.55)
	if elder:
		_line(Vector2(41,24), Vector2(45,23), shade)
		_line(Vector2(48,23), Vector2(52,24), shade)
		_line(Vector2(46,27), Vector2(51,26), shade)
		_line(Vector2(55,27), Vector2(58,28), shade)
		_px(43, 25, skin_ramp[5])
		_px(49, 28, skin_ramp[4])
		_line(Vector2(32,37), Vector2(30,38), shade)
		_line(Vector2(33,40), Vector2(31,41), shade)
		_line(Vector2(64,38), Vector2(67,39), shade)
		_line(Vector2(36,42), Vector2(39,43), shade)
		_line(Vector2(57,42), Vector2(60,42), shade)
		_px(37, 44, skin_ramp[5])
		_line(Vector2(43,50), Vector2(42,52), shade)
		_line(Vector2(58,51), Vector2(59,53), shade)
		_px(59, 55, shade)
		_px(43, 54, skin_ramp[4])
	else:
		_line(Vector2(48,30), Vector2(48,32), shade)
		_line(Vector2(34,42), Vector2(36,43), skin_ramp[3])

func _hair_back() -> void:
	for side in [-1, 1]:
		var x: float = 48.0 + float(side) * 20.0
		var end_y := 70.0 if female else (46.0 if young else 66.0)
		_lock(Vector2(x,24), Vector2(x + side * 6,42), Vector2(x + side * 3,end_y), 5.0 if young and not female else 6.5, 1.5, hair_ramp, -0.7)
		_lock(Vector2(x + side * 2,30), Vector2(x + side * 8,45), Vector2(x + side * 6,end_y - 3), 3.8, 0.5, hair_ramp, -0.9)

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
		var end_y := 42 if young and not female else (46 if not female else 42)
		_lock(Vector2(x,28), Vector2(x + side * 2,34), Vector2(x + side,end_y), 2.5 if young and not female else 3.7, 0.7, hair_ramp, 0.1 if side < 0 else -0.5)

func _curve(a: Vector2, control: Vector2, b: Vector2, t: float) -> Vector2:
	return a * (1.0 - t) * (1.0 - t) + 2.0 * control * t * (1.0 - t) + b * t * t

func _braid(a: Vector2, b: Vector2, radius: float, ramp: Array[Color], control: Vector2 = Vector2.ZERO, phase: int = 0) -> void:
	if control == Vector2.ZERO:
		control = (a + b) * 0.5 + Vector2(-3, 0)
	var length := a.distance_to(control) + control.distance_to(b)
	var knots := maxi(2, int(length / 6.0))
	# Dark contact edge separates neighboring plaits from the beard or collar.
	_lock(a + Vector2(1,1), control + Vector2(1,1), b + Vector2(1,1), radius + 1.2, radius * 0.65, ramp, -2.2)
	_lock(a, control, b, radius, radius * 0.57, ramp, -0.9)
	var previous := 0.0
	for i in knots:
		var next := 1.0 if i == knots - 1 else float(i + 1) / float(knots) + sin(float(i + phase) * 1.9) * 0.035
		var t := (previous + next) * 0.5
		var start := _curve(a, control, b, previous)
		var finish := _curve(a, control, b, next)
		var center := _curve(a, control, b, t)
		var tangent := (finish - start).normalized()
		var across := Vector2(tangent.y, -tangent.x)
		var width := lerpf(radius, radius * 0.57, t) * (1.0 + sin(float(i + phase) * 1.7) * 0.12)
		var flip := -1.0 if (i + phase) % 2 == 0 else 1.0
		_lock(start - across * width * 0.5 * flip, center + across * width * 0.65 * flip, finish + across * width * 0.32 * flip, width * 0.48, width * 0.34, ramp, -0.65)
		_lock(start + across * width * 0.55 * flip, center - across * width * 0.7 * flip, finish - across * width * 0.38 * flip, width * 0.64, width * 0.38, ramp, 0.25 if flip < 0.0 else -0.05)
		previous = next
	var tangent := (b - _curve(a, control, b, 0.92)).normalized()
	var across := Vector2(tangent.y, -tangent.x)
	var tie := b - tangent
	_line(tie - across * radius * 0.54, tie + across * radius * 0.54, gold[1], 1.3)
	_line(tie - across * radius * 0.48 - tangent, tie + across * radius * 0.48 - tangent, gold[5])
	_px(int(tie.x - 1), int(tie.y - 1), gold[6])
	_lock(b, b + tangent * 2.5 + across, b + tangent * 4 + across * 0.5, radius * 0.48, 0.3, ramp)

func _hair_braids() -> void:
	var flipped := int(spec.get("female_set", 0)) % 2 == 1
	var left_end := Vector2(25,78) if flipped else Vector2(29,82)
	var right_end := Vector2(68,83) if flipped else Vector2(71,76)
	_braid(Vector2(27,43), left_end, 5.0 if elder else 4.6, hair_ramp, Vector2(18 if flipped else 20,61), 1)
	_braid(Vector2(70,42), right_end, 4.6 if elder else 4.0, hair_ramp, Vector2(81 if flipped else 78,59), 3)
	_lock(Vector2(25,45), Vector2(20,48), Vector2(23,54), 1.7, 0.4, hair_ramp, 0.1)
	_lock(Vector2(73,44), Vector2(78,49), Vector2(76,56), 1.5, 0.3, hair_ramp, -0.5)

func _beard() -> void:
	var end_y := 70 if young else (90 if elder else 87)
	if beard_style == 7:
		_short_beard()
		return
	elif beard_style == 6:
		_moustache()
		return
	if female:
		end_y -= 8
	var half := 19.0 if young else 24.0
	for y in range(43, end_y + 1):
		var t := float(y - 43) / float(end_y - 43)
		var width := half * (0.91 + sin(t * PI) * 0.13)
		if t > 0.65:
			width *= lerpf(1.0, 0.10 if beard_style == 3 else 0.32, (t - 0.65) / 0.35)
		for x in range(int(49 - width), int(50 + width)):
			var dx := absf(float(x - 50))
			var top := 57 if dx < 8 else (54 if dx < 15 else (51 if young else 46))
			if y < top:
				continue
			if beard_style == 1 and dx > 16 and t > 0.85:
				continue
			if beard_style == 4 and t > 0.75 and dx < (t - 0.75) * 12.0:
				continue
			var across := float(x - 49) / width
			var lit := 2.8 - across * 0.8 - t * 0.5
			_px(x, y, beard_ramp[clampi(int(round(lit)), 0, 6)])
	if young:
		# A rounded, open-cheeked first beard, with one small off-center plait.
		_lock(Vector2(32,51), Vector2(29,59), Vector2(36,65), 3.2, 0.4, beard_ramp, 0.15)
		_lock(Vector2(37,55), Vector2(34,61), Vector2(40,67), 3.2, 0.5, beard_ramp, 0.2)
		_lock(Vector2(42,58), Vector2(39,63), Vector2(45,69), 3.1, 0.5, beard_ramp, 0.1)
		_lock(Vector2(48,58), Vector2(45,64), Vector2(49,70), 3.3, 0.5, beard_ramp, 0.15)
		_lock(Vector2(54,57), Vector2(56,63), Vector2(52,70), 3.2, 0.5, beard_ramp, -0.15)
		_lock(Vector2(60,54), Vector2(63,60), Vector2(57,67), 3.4, 0.5, beard_ramp, -0.25)
		_lock(Vector2(65,51), Vector2(67,57), Vector2(62,63), 3.0, 0.5, beard_ramp, -0.45)
		_lock(Vector2(49,55), Vector2(48,57), Vector2(50,59), 1.5, 0.5, beard_ramp, -0.15)
		_braid(Vector2(60,58), Vector2(60,66), 2.2, beard_ramp, Vector2(64,62), 2)
	else:
		_lock(Vector2(29,47), Vector2(23,65), Vector2(35,78), 5.5, 0.7, beard_ramp, -0.4)
		_lock(Vector2(34,51), Vector2(29,67), Vector2(42,83), 6.0, 0.5, beard_ramp, 0.1)
		_lock(Vector2(69,46), Vector2(77,63), Vector2(65,79), 5.3, 0.7, beard_ramp, -0.7)
		_lock(Vector2(63,52), Vector2(72,69), Vector2(56,84), 5.7, 0.6, beard_ramp, -0.25)
		_lock(Vector2(42,57), Vector2(34,70), Vector2(48,82), 5.2, 0.6, beard_ramp, 0.15)
		_lock(Vector2(55,58), Vector2(64,72), Vector2(50,end_y - 1), 5.1, 0.6, beard_ramp, -0.1)
		_lock(Vector2(47,65), Vector2(57,76), Vector2(46,end_y + 1), 4.6, 0.5, beard_ramp, 0.25)
		if beard_style == 3:
			_braid(Vector2(48,65), Vector2(51,end_y), 4.6, beard_ramp, Vector2(43,77), 2)
		else:
			_braid(Vector2(36,64), Vector2(39,end_y - 2), 4.7, beard_ramp, Vector2(29,75), 1)
			_braid(Vector2(63,62), Vector2(59,end_y - 7), 4.3, beard_ramp, Vector2(69,72), 4)
			if beard_style == 5:
				_braid(Vector2(49,70), Vector2(48,end_y), 3.5, beard_ramp, Vector2(54,80), 3)
		if elder:
			_lock(Vector2(44,61), Vector2(56,70), Vector2(56,89), 3.8, 0.4, beard_ramp, 0.1)
			_lock(Vector2(55,63), Vector2(45,77), Vector2(46,86), 3.1, 0.5, beard_ramp, -0.1)
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
		var reach := 9 if young else 13
		_lock(Vector2(50 + side * 2,mouth_y - 3), Vector2(50 + side * 7,mouth_y - 4), Vector2(50 + side * reach,mouth_y + (1 if young else 3)), 1.8 if young else 3.0, 0.4, beard_ramp, 0.3 if side < 0 else -0.3)
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
