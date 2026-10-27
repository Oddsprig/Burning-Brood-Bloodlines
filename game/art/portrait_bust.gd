extends RefCounted
## 96×96 portrait busts drawn in pixel space. Battle paperdolls stay on paint_bust.
## No class_name: FigurePainter loads this at runtime so the two scripts cannot cycle.

const SIZE := 96
const LIGHT := Vector3(-0.46, -0.64, 0.61)
const IVORY := Color(0.953, 0.918, 0.816, 1.0)
const IVORY_DARK := Color(0.718, 0.639, 0.478, 1.0)
const SCLERA := Color(0.973, 0.957, 0.925, 1.0)
const PUPIL := Color(0.078, 0.047, 0.063, 1.0)
const OUTLINE := Color(0.086, 0.055, 0.071, 1.0)

const EYES := {
	"human": Color("#4a3422"),
	"dwarf": Color("#3a2818"),
	"high_elf": Color("#2f7ed6"),
	"moon_elf": Color("#8fd4f2"),
	"dark_elf": Color("#d64545"),
	"orc": Color("#e2b423"),
	"goblin": Color("#e6c83a"),
	"troll": Color("#e09428"),
}

const AGE_GATE := {
	"human": [16, 55],
	"dwarf": [25, 120],
	"high_elf": [40, 300],
	"moon_elf": [40, 300],
	"dark_elf": [40, 300],
	"orc": [12, 35],
	"goblin": [8, 25],
	"troll": [20, 80],
}

const METRICS := {
	"human": {"rx": 18.0, "ry": 21.5, "cy": 39.0, "jaw": 0.96, "neck": 7.2, "sh": 33.0, "brow": 1.0, "eye": 1.0, "nose": "human", "ear": "round"},
	"dwarf": {"rx": 22.0, "ry": 18.5, "cy": 42.0, "jaw": 1.12, "neck": 10.0, "sh": 40.0, "brow": 1.35, "eye": 0.92, "nose": "bulb", "ear": "small"},
	"high_elf": {"rx": 16.2, "ry": 23.0, "cy": 37.0, "jaw": 0.84, "neck": 6.2, "sh": 29.0, "brow": 0.72, "eye": 1.05, "nose": "fine", "ear": "high"},
	"moon_elf": {"rx": 15.4, "ry": 22.5, "cy": 37.5, "jaw": 0.82, "neck": 5.8, "sh": 28.0, "brow": 0.66, "eye": 1.08, "nose": "fine", "ear": "moon"},
	"dark_elf": {"rx": 16.0, "ry": 22.6, "cy": 37.5, "jaw": 0.86, "neck": 6.0, "sh": 29.0, "brow": 0.78, "eye": 1.04, "nose": "fine", "ear": "dark"},
	"orc": {"rx": 20.0, "ry": 21.0, "cy": 39.0, "jaw": 1.08, "neck": 9.0, "sh": 36.0, "brow": 1.5, "eye": 0.96, "nose": "flat", "ear": "point"},
	"goblin": {"rx": 14.0, "ry": 16.0, "cy": 43.0, "jaw": 0.90, "neck": 5.6, "sh": 26.0, "brow": 0.9, "eye": 1.28, "nose": "hook", "ear": "fan"},
	"troll": {"rx": 24.0, "ry": 22.0, "cy": 39.0, "jaw": 1.18, "neck": 11.5, "sh": 42.0, "brow": 1.85, "eye": 0.62, "nose": "flat", "ear": "heavy"},
}

const ARMOR := ["cuirass", "mail", "scale", "lamellar", "scrap", "byrnie", "plate", "brigandine", "hauberk", "breastplate"]

static func paint(spec: Dictionary) -> Image:
	return load("res://art/portrait_bust.gd").new()._render(spec)

var cv: PixelCanvas
var spec: Dictionary = {}
var race := "human"
var sex_f := false
var stage := "adult"
var seed := 1
var skin := Color.WHITE
var hair := Color.WHITE
var beard_col := Color.WHITE
var prim := Color.WHITE
var sec := Color.WHITE
var beard_on := false
var beard_i := 0
var dead := false
var eyes_open := true
var lost := {}
var rx := 18.0
var ry := 21.0
var cx := 48.0
var cy := 39.0
var jaw := 1.0
var neck_w := 7.0
var sh_w := 32.0
var brow_k := 1.0
var eye_k := 1.0
var nose_k := "human"
var ear_k := "round"
var hstyle := "short"
var eye_y := 36.0
var nose_y := 46.0
var mouth_y := 50.0
var chin_y := 58.0
var torso_y := 64.0
var eye_shift := 0
var nose_extra := 0
var eye_near := Vector2.ZERO
var eye_far := Vector2.ZERO
var scl := 3.0
var skin_ramp: Array[Color] = []
var hair_ramp: Array[Color] = []
var beard_ramp: Array[Color] = []
var helm := {}
var body := {}
var helm_kind := "none"
var part_left := true
var braid_x := 60.0
var light_n := Vector3.UP
var nu := 0.0
var nv := 0.0
var nn := Vector3.ZERO

func _render(sp: Dictionary) -> Image:
	spec = sp
	cv = PixelCanvas.new(SIZE, SIZE)
	cv.set_frame(Vector2.ZERO, 1.0, 0.0)
	_read()
	if _lost("head"):
		_draw_torso()
		_blob(int(cx), int(cy), 11, FigurePainter.BLOOD)
		_outline()
		return cv.to_image()
	if helm_kind == "closed":
		_draw_torso()
		_draw_neck()
		_draw_collar()
		_draw_closed_helm()
		_draw_lost_blood()
		_outline()
		return cv.to_image()
	if helm_kind == "coif":
		_draw_hood()
	else:
		_draw_hair_back()
	_draw_torso()
	_draw_neck()
	_draw_collar()
	_draw_skull()
	_blush()
	if helm_kind != "coif":
		_draw_hair_front()
	_draw_ear(true)
	_draw_ear(false)
	_draw_brows_and_eyes()
	_draw_nose()
	_draw_mouth()
	_draw_wrinkles()
	_draw_beard()
	_draw_tusks()
	_draw_open_helm()
	_draw_lost_blood()
	_outline()
	return cv.to_image()

func _read() -> void:
	race = String(spec.get("race", "human"))
	sex_f = String(spec.get("sex", "male")) == "female"
	seed = absi(int(spec.get("seed", 1)))
	eye_shift = (seed % 3) - 1
	nose_extra = int(float(seed) / 3.0) % 3
	dead = bool(spec.get("dead", false))
	stage = _stage_for(race, int(spec.get("age", 30)))
	var m: Dictionary = METRICS.get(race, METRICS["human"])
	rx = float(m["rx"])
	ry = float(m["ry"])
	cy = float(m["cy"])
	jaw = float(m["jaw"]) * (0.86 if sex_f else 1.0)
	if stage == "young":
		jaw = lerpf(jaw, 0.90, 0.35)
	elif stage == "elder" and not sex_f:
		jaw *= 1.04
	neck_w = float(m["neck"])
	sh_w = float(m["sh"])
	brow_k = float(m["brow"]) * (0.72 if sex_f else 1.0)
	eye_k = float(m["eye"])
	if stage == "young":
		eye_k *= 1.16
	elif stage == "elder":
		eye_k *= 0.88
	if sex_f:
		eye_k *= 1.05
	nose_k = String(m["nose"])
	ear_k = String(m["ear"])
	cx = 48.0
	eye_y = cy - ry * 0.06
	mouth_y = cy + ry * 0.52
	chin_y = cy + ry * 0.92
	nose_y = minf(cy + ry * 0.30 + float(nose_extra) * 0.45, mouth_y - 4.0)
	torso_y = chin_y + 5.0
	scl = 3.15 * eye_k
	eye_near = Vector2(cx - (scl + 2.6) + float(eye_shift), eye_y)
	eye_far = Vector2(cx + (scl + 1.3) + float(eye_shift), eye_y)
	skin = _color_of("skin", Color("#e0b090"))
	hair = _color_of("hair", Color("#3a2a1a"))
	prim = _color_of("prim", Color("#2458a8"))
	sec = _color_of("sec", Color("#e8b840"))
	var remain := clampf(float(spec.get("blood", 1.0)), 0.0, 1.0)
	skin = _op(skin.lerp(Color("#d8d8d0"), clampf((1.0 - remain) * 0.6, 0.0, 0.45)))
	if dead:
		skin = _op(skin.lerp(Color("#9a9690"), 0.45))
		eyes_open = false
	else:
		eyes_open = true
	if stage == "elder":
		hair = _op(hair.lerp(Color("#d8d8dc"), 0.55))
	_read_beard()
	if stage == "elder":
		beard_col = _op(beard_col.lerp(Color("#d8d8dc"), 0.55))
	skin_ramp = _ramp(skin, 0.48)
	hair_ramp = _ramp(hair, 0.42)
	beard_ramp = _ramp(beard_col, 0.46)
	hstyle = _pick_style()
	part_left = int(spec.get("female_set", seed % 2)) % 2 == 0
	braid_x = cx + (12.0 if part_left else -14.0)
	helm = spec.get("helm", {}) if spec.get("helm", {}) is Dictionary else {}
	body = spec.get("body", {}) if spec.get("body", {}) is Dictionary else {}
	helm_kind = _classify_helm()
	light_n = LIGHT.normalized()
	lost = {}
	var raw = spec.get("lost", [])
	if raw is Array:
		for id in raw:
			lost[String(id)] = true

func _read_beard() -> void:
	beard_on = false
	beard_col = hair
	beard_i = 0
	var b = spec.get("beard", false)
	if b is bool:
		beard_on = b
	elif b is Color:
		beard_on = true
		beard_col = _op(b)
	elif b is String and String(b) != "" and String(b) != "false":
		beard_on = true
		if String(b).begins_with("#") or String(b).length() >= 6:
			beard_col = _op(Color(String(b)))
	if spec.has("beard_style"):
		beard_i = clampi(int(spec.get("beard_style", 0)), 0, 7)

func _stage_for(race_name: String, age: int) -> String:
	var gates: Array = AGE_GATE.get(race_name, [16, 55])
	var adult := int(gates[0])
	var elder := int(gates[1])
	var young_cut := adult + maxi(6, int(float(elder - adult) * 0.18))
	if age >= elder:
		return "elder"
	if age < young_cut:
		return "young"
	return "adult"

func _pick_style() -> String:
	var n := absi(seed)
	if stage == "elder" and not sex_f and race in ["human", "dwarf", "orc"]:
		return "receding"
	if sex_f:
		if race == "troll":
			return "bald" if n % 5 == 0 else "tuft"
		if race == "goblin":
			return ["tuft", "short", "bald"][n % 3]
		if race == "dwarf":
			return "braid"
		return "long" if int(spec.get("female_set", 0)) % 2 == 0 else "braid"
	match race:
		"troll":
			return "bald" if n % 5 == 0 else "tuft"
		"goblin":
			return ["bald", "tuft", "short"][n % 3]
		"orc":
			return ["bald", "mohawk", "topknot", "short"][n % 4]
		"high_elf", "moon_elf", "dark_elf":
			return ["long", "half", "braid"][n % 3]
		"dwarf":
			return ["short", "long", "receding"][n % 3]
		_:
			return ["short", "side", "long", "half"][n % 4]

func _color_of(key: String, fallback: Color) -> Color:
	var v = spec.get(key, fallback)
	var c := fallback
	if v is Color:
		c = v
	elif v is String and String(v) != "":
		c = Color(String(v))
	return _op(c)

func _op(c: Color) -> Color:
	c.a = 1.0
	return c

func _ramp(base: Color, depth: float) -> Array[Color]:
	var hi := Color(1.0, 0.96, 0.90, 1.0)
	return [
		_op(base.darkened(depth)),
		_op(base.darkened(depth * 0.62)),
		_op(base.darkened(depth * 0.28)),
		_op(base),
		_op(base.lightened(0.10).lerp(hi, 0.28)),
	]

func _px(x: int, y: int, c: Color) -> void:
	if c.a < 1.0:
		c.a = 1.0
	cv.set_px(x, y, c)

func _lost(id: String) -> bool:
	return bool(lost.get(id, false))

func _lambert(n: Vector3) -> int:
	var nd := clampf(n.dot(light_n) * 0.5 + 0.5, 0.0, 1.0)
	return clampi(int(nd * 4.999), 0, 4)

func _probe(px: float, py: float) -> bool:
	var v := (py - cy) / ry
	var xrad := 1.0
	if v >= 0.0:
		xrad = lerpf(1.0, jaw * (0.84 if sex_f else 0.93), smoothstep(0.02, 0.92, v))
		if v > 0.76:
			xrad *= lerpf(1.0, 0.58 if sex_f else 0.74, smoothstep(0.76, 1.02, v))
	else:
		xrad = lerpf(0.88, 1.0, smoothstep(-1.05, -0.1, v))
	var mid := cx + lerpf(-0.6, 2.6, smoothstep(-0.15, 0.8, v))
	var dx := px - mid
	var side := 1.05 if dx < 0.0 else 0.91
	var u := dx / (rx * xrad * side)
	if u * u + v * v > 1.0:
		return false
	var z := sqrt(maxf(0.0, 1.0 - u * u - v * v))
	nu = u
	nv = v
	nn = Vector3(u * 0.92 - 0.16, v * 0.95 + 0.02, z + 0.08).normalized()
	return true

func _skin_at() -> Color:
	var band := _lambert(nn)
	if nu > 0.42:
		band = maxi(0, band - 1)
	if nv > 0.70:
		band = maxi(0, band - 1)
	if Vector2(nu + 0.32, nv - 0.16).length() < 0.34:
		band = mini(4, band + 1)
	if brow_k > 1.25 and nv > -0.22 and nv < 0.02 and absf(nu) < 0.72:
		band = maxi(0, band - 1)
	return skin_ramp[band]

func _draw_skull() -> void:
	var x0 := int(cx - rx - 4.0)
	var x1 := int(cx + rx + 4.0)
	var y0 := int(cy - ry - 3.0)
	var y1 := int(cy + ry + 3.0)
	for y in range(maxi(y0, 0), mini(y1, SIZE)):
		for x in range(maxi(x0, 0), mini(x1, SIZE)):
			if not _probe(float(x) + 0.5, float(y) + 0.5):
				continue
			if _lost("jaw") and nv > 0.40:
				continue
			_px(x, y, _skin_at())

func _blush() -> void:
	if stage != "young" or not sex_f:
		return
	var blush := _op(skin.lerp(Color("#e09098"), 0.34))
	_px(int(eye_near.x) - 2, int(eye_near.y) + 5, blush)
	_px(int(eye_near.x) - 1, int(eye_near.y) + 6, blush)
	_px(int(eye_far.x) + 1, int(eye_far.y) + 5, blush)
	_px(int(eye_far.x) + 2, int(eye_far.y) + 6, blush)

func _draw_torso() -> void:
	var cloth := _ramp(prim, 0.42)
	var y0 := int(torso_y)
	for y in range(maxi(y0, 0), SIZE):
		var t := clampf(float(y - y0) / 16.0, 0.0, 1.0)
		var half := lerpf(neck_w + 4.0, sh_w, t)
		for x in range(int(cx - half), int(cx + half) + 1):
			if t < 0.9:
				var nx := (float(x) - cx) / half
				if nx * nx > 1.0:
					continue
				if absf(float(x) - cx) > neck_w + 2.0 and (1.0 - t) > 0.55 and absf(nx) > 0.72:
					continue
			var lit := clampf(0.64 - ((float(x) - cx) / sh_w) * 0.48 - float(y - y0) / 90.0, 0.0, 1.0)
			_px(x, y, cloth[clampi(int(lit * 4.999), 0, 4)])
	_disc_ramp(int(cx - sh_w * 0.52), y0 + 6, int(maxf(6.0, sh_w * 0.22)), 6, cloth)
	_disc_ramp(int(cx + sh_w * 0.46), y0 + 7, int(maxf(5.0, sh_w * 0.18)), 5, cloth)
	if _armored():
		_draw_armor()

func _draw_neck() -> void:
	if _lost("neck"):
		_blob(int(cx), int((chin_y + torso_y) * 0.5), 5, FigurePainter.BLOOD)
		return
	var y0 := int(chin_y - 1.0)
	var y1 := int(torso_y + 8.0)
	for y in range(maxi(y0, 0), mini(y1, SIZE)):
		var t := float(y - y0) / maxf(1.0, float(y1 - y0))
		var half := lerpf(neck_w * 0.76, neck_w * 1.05, t)
		for x in range(int(cx + 1.0 - half), int(cx + 1.0 + half) + 1):
			var u := (float(x) - (cx + 1.0)) / half
			var lit := clampf(0.58 - u * 0.64 - t * 0.14, 0.0, 1.0)
			if y < y0 + 3:
				lit *= 0.62
			_px(x, y, skin_ramp[clampi(int(lit * 4.999), 0, 4)])

func _draw_collar() -> void:
	var y := int(torso_y + 7.0)
	var half := int(neck_w + 3.0)
	var cloth_dark := _op(prim.darkened(0.30))
	for x in range(-half, half + 1):
		_px(int(cx) + x, y, cloth_dark)
	var bx := int(cx)
	var by := int(torso_y + 12.0)
	_px(bx, by, sec)
	_px(bx + 1, by, _op(sec.darkened(0.12)))
	_px(bx, by + 1, _op(sec.darkened(0.18)))
	_px(bx + 1, by + 1, _op(sec.lightened(0.14)))

func _armored() -> bool:
	var sprite := String(body.get("sprite", ""))
	var tid := String(body.get("tid", ""))
	for name in ARMOR:
		if sprite == name or (name.length() > 2 and name in tid):
			return true
	return false

func _draw_armor() -> void:
	var m := _metal_of(body)
	var ramp := _metal_ramp(m)
	var sprite := String(body.get("sprite", ""))
	var y0 := int(torso_y + 3.0)
	for y in range(y0, SIZE):
		var t := clampf(float(y - y0) / 18.0, 0.0, 1.0)
		var half := lerpf(neck_w, sh_w * 0.72, t)
		for x in range(int(cx - half), int(cx + half) + 1):
			var u := (float(x) - cx) / maxf(1.0, half)
			var lit := clampf(0.60 - u * 0.5 - float(y - y0) / 80.0, 0.0, 1.0)
			_px(x, y, ramp[clampi(int(lit * 4.999), 0, 4)])
	var rows := 4
	var step := 3
	if sprite in ["mail", "byrnie"]:
		rows = 6
		step = 2
	var dark: Color = m["dark"]
	var light: Color = m["light"]
	for i in rows:
		var y := y0 + 7 + i * step
		var rw := int(sh_w * 0.40)
		for x in range(int(cx) - rw, int(cx) + rw):
			if sprite == "scrap" and (x + seed + i * 2) % 5 == 0:
				continue
			_px(x, y, _op(dark))
			if sprite != "scrap" and (x + i) % 7 == 0:
				_px(x, y, _op(light))

func _metal_of(item: Dictionary) -> Dictionary:
	var mat := String(item.get("mat", "iron"))
	if mat == "":
		mat = "iron"
	return FigurePainter.metal(mat, int(item.get("q", 0)))

func _metal_ramp(m: Dictionary) -> Array[Color]:
	var base: Color = m["base"]
	var light: Color = m["light"]
	var dark: Color = m["dark"]
	var shine: Color = m["shine"]
	return [_op(dark.darkened(0.18)), _op(dark), _op(base), _op(light), _op(shine)]

func _disc_ramp(ccx: int, ccy: int, erx: int, ery: int, ramp: Array[Color]) -> void:
	if erx < 1 or ery < 1:
		return
	for y in range(-ery, ery + 1):
		for x in range(-erx, erx + 1):
			var u := float(x) / float(erx)
			var v := float(y) / float(ery)
			if u * u + v * v > 1.0:
				continue
			var z := sqrt(maxf(0.0, 1.0 - u * u - v * v))
			var band := _lambert(Vector3(u - 0.12, v, z).normalized())
			_px(ccx + x, ccy + y, ramp[band])

func _hair_col(x: int, y: int) -> Color:
	var lit := clampf(0.62 - float(x - int(cx)) * 0.02 - float(y - int(cy - ry)) * 0.012, 0.0, 1.0)
	var band := clampi(int(lit * 4.999), 0, 4)
	if hstyle == "braid" and absi(x - int(braid_x)) <= 2 and posmod(y, 5) == 0:
		band = mini(4, band + 1)
	return hair_ramp[band]

func _hair_ellipse(c: Vector2, erx: float, ery: float, clip_below: float = 999.0) -> void:
	if erx < 0.5 or ery < 0.5:
		return
	for y in range(maxi(int(floor(c.y - ery)) - 1, 0), mini(int(ceil(c.y + ery)) + 2, SIZE)):
		if float(y) > clip_below:
			continue
		for x in range(maxi(int(floor(c.x - erx)) - 1, 0), mini(int(ceil(c.x + erx)) + 2, SIZE)):
			var dx := (float(x) + 0.5 - c.x) / erx
			var dy := (float(y) + 0.5 - c.y) / ery
			if dx * dx + dy * dy > 1.0:
				continue
			_px(x, y, _hair_col(x, y))

func _hair_capsule(a: Vector2, b: Vector2, rad: float) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(rad, rad)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(rad, rad)
	for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)) + 1, SIZE)):
		for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)) + 1, SIZE)):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_squared_to(p) > rad * rad:
				continue
			_px(x, y, _hair_col(x, y))

func _draw_hair_back() -> void:
	match hstyle:
		"bald", "tuft", "topknot", "mohawk":
			return
		"long", "braid":
			_hair_ellipse(Vector2(cx - 1.0, cy - ry * 0.15), rx * 1.16, ry * 0.82)
			_hair_ellipse(Vector2(cx, chin_y + 2.0), rx * 0.95, 18.0)
		"half":
			_hair_ellipse(Vector2(cx - 1.0, cy - ry * 0.42), rx * 1.05, ry * 0.46)
		"receding":
			return
		_:
			_hair_ellipse(Vector2(cx - 1.0, cy - ry * 0.22), rx * 1.08, ry * 0.70)

func _side_locks(long: bool) -> void:
	var y1 := 93.0 if long else mouth_y + 2.0
	for dir in [-1.0, 1.0]:
		var x: float = cx + float(dir) * (rx * 0.92)
		if dir < 0.0 and part_left:
			x -= 1.5
		if dir > 0.0 and not part_left:
			x += 1.5
		_hair_capsule(Vector2(x, eye_y - 6.0), Vector2(x + float(dir) * 1.2, y1), 3.1 if long else 2.4)

func _fringe(depth: float) -> void:
	var y1 := eye_y - 4.0
	var y0 := y1 - depth
	var part := int(cx + (-4.0 if part_left else 5.0))
	for y in range(int(y0), int(y1)):
		for x in range(int(cx - rx * 0.82), int(cx + rx * 0.62)):
			if x == part:
				continue
			if not _probe(float(x) + 0.5, float(y) + 0.5):
				continue
			_px(x, y, _hair_col(x, y))

func _hair_cap(line: float, width: float) -> void:
	var top := cy - ry - 2.0
	_hair_ellipse(Vector2(cx - 0.4, (top + line) * 0.5 - 1.0), rx * width, maxf(6.0, (line - top) * 0.62), line + 0.5)
	for y in range(maxi(int(top), 0), mini(int(line) + 1, SIZE)):
		var t := clampf((float(y) - top) / maxf(1.0, line - top), 0.0, 1.0)
		var half := lerpf(rx * 0.46, rx * width, t)
		for x in range(int(cx - half) - 1, int(cx + half * 0.82) + 1):
			if not _probe(float(x) + 0.5, float(y) + 0.5) and float(y) > cy - ry * 0.2:
				continue
			_px(x, y, _hair_col(x, y))

func _draw_hair_front() -> void:
	var line := eye_y - 5.0
	match hstyle:
		"bald":
			return
		"tuft":
			_hair_ellipse(Vector2(cx - 2.0, cy - ry - 3.0), 5.5, 6.5)
			_hair_ellipse(Vector2(cx + 3.5, cy - ry - 1.5), 3.6, 4.5)
		"topknot":
			_hair_cap(line, 0.78)
			_hair_ellipse(Vector2(cx, cy - ry - 7.0), 6.5, 6.5)
			_hair_capsule(Vector2(cx, cy - ry + 1.0), Vector2(cx, cy - ry - 7.0), 2.4)
		"mohawk":
			_hair_capsule(Vector2(cx, cy - ry - 11.0), Vector2(cx, line), 3.6)
		"receding":
			_hair_ellipse(Vector2(cx - rx * 0.52, eye_y - 7.0), rx * 0.64, 12.0, eye_y - 2.0)
			_hair_ellipse(Vector2(cx + rx * 0.38, eye_y - 8.0), rx * 0.50, 10.0, eye_y - 2.0)
			_hair_ellipse(Vector2(cx - 1.0, cy - ry + 2.0), rx * 0.62, 7.0, cy - ry * 0.45)
		"short", "side":
			_hair_cap(line, 1.04)
			if hstyle == "side":
				var dir := -1.0 if part_left else 1.0
				_hair_ellipse(Vector2(cx + dir * rx * 0.34, eye_y - 8.0), rx * 0.52, 7.0, eye_y - 1.0)
		"half":
			_hair_cap(line + 2.0, 1.02)
		"long":
			_hair_cap(line, 1.06)
			if sex_f:
				_side_locks(true)
		"braid":
			_hair_cap(line, 1.02)
			if sex_f:
				_side_locks(false)
			var lean := 2.0 if braid_x > cx else -2.0
			_hair_capsule(Vector2(braid_x, mouth_y), Vector2(braid_x + lean, 93.0), 3.4)

func _draw_ear(near: bool) -> void:
	var lost_id := "ear_r" if near else "ear_l"
	var dir := -1.0 if near else 1.0
	if _lost(lost_id):
		_blob(int(cx + dir * rx), int(eye_y), 2, FigurePainter.BLOOD)
		return
	var sc := 1.0 if near else 0.78
	match ear_k:
		"fan":
			_fan_ear(dir, near, sc)
		"high":
			_swept_ear(dir, near, 3.1 * sc, Vector2(dir * 4.0, -9.0), Vector2(dir * 6.0, -18.0))
		"moon":
			_swept_ear(dir, near, 2.2 * sc, Vector2(dir * 9.0, -2.0), Vector2(dir * 15.0, -5.0))
		"dark":
			_swept_ear(dir, near, 2.6 * sc, Vector2(dir * 5.0, -7.0), Vector2(dir * 7.0, -14.0))
		"point":
			_swept_ear(dir, near, 3.1 * sc, Vector2(dir * 4.0, -6.0), Vector2(dir * 8.0, -13.0))
		"small":
			_swept_ear(dir, near, 2.15 * sc, Vector2(dir * 1.0, -2.0), Vector2(dir * 1.2, -5.0))
		"heavy":
			_swept_ear(dir, near, 3.5 * sc, Vector2(dir * 2.0, -1.0), Vector2(dir * 3.0, -5.0))
		_:
			_swept_ear(dir, near, 2.7 * sc, Vector2(dir * 1.0, -4.0), Vector2(dir * 0.4, -8.0))

func _fan_ear(dir: float, near: bool, sc: float) -> void:
	var origin := Vector2(cx + dir * (rx * 0.7), eye_y + 2.0)
	var tip := Vector2(cx + dir * (rx + 16.0 * sc), eye_y - 14.0 * sc)
	var low := Vector2(cx + dir * (rx + 5.0 * sc), eye_y + 6.0 * sc)
	var hi := Vector2(cx + dir * (rx + 9.0 * sc), eye_y - 3.0 * sc)
	_tri(origin, hi, tip, near)
	_tri(origin, tip, low, near)
	_px(int(tip.x), int(tip.y), skin_ramp[4])
	_px(int(low.x), int(low.y), skin_ramp[3])

func _tri(a: Vector2, b: Vector2, c: Vector2, near: bool) -> void:
	var min_x := int(floor(minf(a.x, minf(b.x, c.x))))
	var max_x := int(ceil(maxf(a.x, maxf(b.x, c.x))))
	var min_y := int(floor(minf(a.y, minf(b.y, c.y))))
	var max_y := int(ceil(maxf(a.y, maxf(b.y, c.y))))
	var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if absf(den) < 0.001:
		return
	for y in range(maxi(min_y, 0), mini(max_y + 1, SIZE)):
		for x in range(maxi(min_x, 0), mini(max_x + 1, SIZE)):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var w0 := ((b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)) / den
			var w1 := ((c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)) / den
			var w2 := 1.0 - w0 - w1
			if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
				continue
			if not near and _probe(p.x, p.y):
				continue
			var band := 4 if p.x < cx else 2
			if w0 < 0.18:
				band = 0
			_px(x, y, skin_ramp[band])

func _swept_ear(dir: float, near: bool, rad: float, mid_off: Vector2, tip_off: Vector2) -> void:
	var base := Vector2(cx + dir * rx * 0.70, eye_y + 3.0)
	var mid := base + mid_off
	var tip := base + tip_off
	tip.x = clampf(tip.x, 3.0, 92.0)
	tip.y = clampf(tip.y, 4.0, 90.0)
	mid.x = clampf(mid.x, 3.0, 92.0)
	mid.y = clampf(mid.y, 4.0, 90.0)
	_ear_capsule(base, mid, rad, near, false)
	_ear_capsule(mid, tip, maxf(1.4, rad * 0.7), near, false)
	_ear_disc(tip, maxf(1.6, rad * 0.85), maxf(1.6, rad * 0.85), near, false)
	_ear_capsule(base + Vector2(-dir * 0.3, 1.0), mid, maxf(0.8, rad * 0.36), near, true)

func _ear_capsule(a: Vector2, b: Vector2, rad: float, near: bool, inner: bool) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(rad, rad)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(rad, rad)
	var mid_x := (a.x + b.x) * 0.5
	for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)) + 1, SIZE)):
		for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)) + 1, SIZE)):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_squared_to(p) > rad * rad:
				continue
			if not near and _probe(p.x, p.y):
				continue
			if inner:
				_px(x, y, skin_ramp[0])
			else:
				var outer := p.x < mid_x if near else p.x > mid_x
				_px(x, y, skin_ramp[4 if outer else 2])

func _ear_disc(c: Vector2, erx: float, ery: float, near: bool, inner: bool) -> void:
	if erx < 0.4 or ery < 0.4:
		return
	for y in range(maxi(int(floor(c.y - ery)), 0), mini(int(ceil(c.y + ery)) + 1, SIZE)):
		for x in range(maxi(int(floor(c.x - erx)), 0), mini(int(ceil(c.x + erx)) + 1, SIZE)):
			var dx := (float(x) + 0.5 - c.x) / erx
			var dy := (float(y) + 0.5 - c.y) / ery
			if dx * dx + dy * dy > 1.0:
				continue
			if not near and _probe(float(x) + 0.5, float(y) + 0.5):
				continue
			_px(x, y, skin_ramp[0 if inner else (3 if dx < 0.0 else 2)])

func _draw_brows_and_eyes() -> void:
	_draw_eye(eye_near, true, "eye_r")
	_draw_eye(eye_far, false, "eye_l")

func _draw_eye(center: Vector2, near: bool, lost_id: String) -> void:
	var x0 := int(round(center.x))
	var y0 := int(round(center.y))
	if _lost(lost_id):
		for i in range(-3, 4):
			_px(x0 + i, y0, skin_ramp[0])
		_blob(x0, y0, 2, FigurePainter.BLOOD)
		return
	var hw := 3 if eye_k >= 0.85 else 2
	var hh := 2 if eye_k >= 0.85 else 1
	if not eyes_open:
		for x in range(-hw, hw + 1):
			var arch := 1 if absi(x) >= hw - 1 else 0
			_px(x0 + x, y0 + arch, skin_ramp[0])
			_px(x0 + x, y0 + arch - 1, skin_ramp[1])
		_brow(x0, y0, hw, hh, near)
		return
	var lid := _op(skin.darkened(0.48))
	for y in range(-hh - 1, hh + 2):
		for x in range(-hw - 1, hw + 2):
			var nx := float(x) / float(hw + 1)
			var ny := float(y) / float(hh + 1)
			if nx * nx + ny * ny > 1.0:
				continue
			if y <= -hh:
				_px(x0 + x, y0 + y, lid)
			elif nx * nx + ny * ny > 0.82:
				_px(x0 + x, y0 + y, _op(SCLERA.darkened(0.10)))
			else:
				_px(x0 + x, y0 + y, SCLERA)
	var ix := x0 + (0 if near else 1)
	var iy := y0
	var iris := EYES.get(race, Color("#4a3422")) as Color
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var shade := 0.22 if dx > 0 or dy > 0 else 0.0
			_px(ix + dx, iy + dy, _op(iris.darkened(shade)))
	_px(ix, iy, PUPIL)
	_px(ix - 1, iy - 1, Color(1, 0.995, 0.97, 1))
	_brow(x0, y0, hw, hh, near)

func _brow(x0: int, y0: int, hw: int, hh: int, near: bool) -> void:
	var thick := 1
	if not sex_f and brow_k >= 1.45:
		thick = 2
	var brow_col := hair_ramp[2]
	if race == "troll":
		brow_col = _op(skin.darkened(0.42))
	elif hair.get_luminance() > 0.72:
		brow_col = hair_ramp[1]
	var by := y0 - hh - thick - (1 if race == "troll" else 0)
	var toward := 1 if near else -1
	for t in thick:
		for x in range(-hw - 1, hw + 2):
			var drop := 0
			if not sex_f and brow_k >= 1.3 and x * toward > 1:
				drop = 1
			var arch := 0
			if absi(x) >= hw - 1:
				arch = -1
			var col := brow_col
			if t == 0 and race == "troll":
				col = skin_ramp[3]
			_px(x0 + x, by + t + drop + arch, col)

func _draw_nose() -> void:
	if _lost("nose"):
		return
	var x := int(round(cx + 1.6 + float(eye_shift) * 0.25))
	var gap := 4 if nose_k == "fine" else 2
	var y := int(round(mouth_y)) - gap
	match nose_k:
		"bulb":
			_disc_ramp(x, y - 1, 4, 3, skin_ramp)
			_px(x - 3, y + 1, skin_ramp[0])
			_px(x + 2, y + 1, skin_ramp[0])
			_px(x - 2, y + 2, skin_ramp[0])
			_px(x + 1, y + 2, skin_ramp[0])
		"fine":
			for i in range(6):
				_px(x, y - i, skin_ramp[2])
				_px(x - 1, y - i, skin_ramp[4])
			_px(x, y + 1, skin_ramp[1])
			_px(x + 1, y + 1, skin_ramp[0])
		"hook":
			for i in range(6):
				_px(x - 1, y - 8 + i, skin_ramp[4])
				_px(x, y - 8 + i, skin_ramp[2])
				_px(x + 1, y - 8 + i, skin_ramp[3])
			for i in range(4):
				_px(x + i, y - 2 + i, skin_ramp[3])
				_px(x + i - 1, y - 2 + i, skin_ramp[4])
			_disc_ramp(x + 3, y + 2, 4, 3, skin_ramp)
			_px(x + 1, y + 3, skin_ramp[0])
			_px(x + 5, y + 3, skin_ramp[0])
		"flat":
			for i in range(3):
				for dx in range(-3, 4):
					_px(x + dx, y - 3 + i, skin_ramp[4 if dx < -1 else (2 if dx < 2 else 1)])
			for dx in range(-4, -1):
				_px(x + dx, y + 1, skin_ramp[0])
			for dx in range(2, 5):
				_px(x + dx, y + 1, skin_ramp[0])
		_:
			var bridge := 4 + nose_extra
			for i in range(bridge):
				_px(x, y - 1 - i, skin_ramp[2])
				_px(x - 1, y - 1 - i, skin_ramp[4])
			_px(x - 1, y, skin_ramp[4])
			_px(x, y, skin_ramp[3])
			_px(x + 1, y, skin_ramp[2])
			_px(x, y + 1, skin_ramp[1])
			_px(x - 2, y + 1, skin_ramp[0])
			_px(x + 2, y + 1, skin_ramp[0])

func _draw_mouth() -> void:
	if _lost("mouth"):
		_blob(int(cx + 1.0), int(mouth_y), 3, FigurePainter.BLOOD)
		return
	var x := int(round(cx + 1.2))
	var y := int(round(mouth_y))
	var hw := 4
	if race in ["dwarf", "orc"]:
		hw = 5
	elif race == "troll":
		hw = 6
	elif race == "goblin" or race.ends_with("elf"):
		hw = 3
	if sex_f:
		hw = maxi(2, hw - 1)
	var lip_dark := _op(skin.darkened(0.34).lerp(Color("#4a1822"), 0.28))
	var lip := _op(skin.lerp(Color("#a4545c"), 0.42 if sex_f else 0.18))
	for i in range(-hw, hw + 1):
		_px(x + i, y, lip_dark)
	for i in range(-(hw - 1), hw):
		_px(x + i, y + 1, lip)
	if sex_f:
		for i in range(-(hw - 2), hw - 1):
			_px(x + i, y + 2, _op(lip.lightened(0.08)))
	_px(x - hw, y + 1, skin_ramp[1])
	_px(x + hw, y + 1, skin_ramp[0])

func _draw_wrinkles() -> void:
	if stage != "elder":
		return
	var wr := _op(skin.darkened(0.18))
	if hstyle in ["receding", "bald", "tuft", "half", "mohawk", "topknot"]:
		var yf := int(eye_y - scl - 7.0)
		for i in range(7):
			if (i + seed) % 4 == 0:
				continue
			_px(int(cx) - 5 + i, yf, wr)
			_px(int(cx) - 3 + i, yf + 3, wr)
	var lx := int(eye_near.x) - int(scl) - 1
	var ly := int(eye_near.y)
	_px(lx, ly - 1, wr)
	_px(lx - 1, ly, wr)
	_px(lx - 2, ly + 1, wr)
	var rx0 := int(eye_far.x) + int(scl) + 1
	var ry0 := int(eye_far.y)
	_px(rx0, ry0 - 1, wr)
	_px(rx0 + 1, ry0, wr)
	_px(rx0 + 2, ry0 + 1, wr)
	var nx := int(round(cx + 1.0))
	var ny := int(nose_y)
	_px(nx - 3, ny + 2, wr)
	_px(nx - 4, ny + 3, wr)
	_px(nx + 3, ny + 2, wr)
	_px(nx + 4, ny + 3, wr)

func _beard_scale() -> float:
	var s := 1.0
	if race == "dwarf":
		s *= 1.35
	if stage == "young":
		s *= 0.88 if race == "dwarf" else 0.72
	elif stage == "elder":
		s *= 1.25
	if sex_f:
		s *= 0.75
	return s

func _beard_at(x: int, y: int) -> Color:
	var lit := clampf(0.72 - float(x - int(cx)) * 0.03 - float(y - int(mouth_y)) * 0.012, 0.0, 1.0)
	var band := clampi(int(lit * 4.999), 0, 4)
	if posmod(x, 5) == 0 and band > 1:
		band -= 1
	return beard_ramp[band]

func _draw_beard() -> void:
	if not beard_on or _lost("head"):
		return
	var s := _beard_scale()
	var y0 := int(mouth_y) + (3 if sex_f else 2)
	var xc := int(round(cx + 1.0))
	var chin := int(chin_y)
	var half := minf(rx * (0.92 if race == "dwarf" else 0.62), rx * (0.5 if race.ends_with("elf") else 0.58) * s)
	var hang := 20 if race == "dwarf" else 12
	match beard_i:
		1:
			_beard_fill(xc, y0 - 1, chin + mini(int(4.0 * s), 6), half * 0.9, "short")
			_moustache(xc, int(mouth_y), int(maxf(4.0, half * 0.42)))
		2:
			_beard_fill(xc, y0, chin + hang, half, "round")
			_moustache(xc, int(mouth_y), int(half * 0.45))
		3:
			_beard_fill(xc, y0, chin + int(14.0 * s), half * 0.8, "point")
		4:
			_beard_fill(xc, y0, chin + int(13.0 * s), half * 0.9, "fork")
		5:
			_beard_braids(xc, y0, int(maxf(6.0, 11.0 * s)))
		6:
			_moustache(xc, int(mouth_y), int(maxf(5.0, half * 0.85)))
		7:
			_stubble(xc, y0, chin + 2, int(half))
		_:
			_beard_fill(xc, y0, chin + (14 if race == "dwarf" else 8), half * 0.95, "round")
			_moustache(xc, int(mouth_y), int(half * 0.36))

func _beard_fill(xc: int, y0: int, y1: int, half: float, kind: String) -> void:
	var span := maxi(1, y1 - y0)
	for y in range(y0, mini(y1, SIZE)):
		var t := float(y - y0) / float(span)
		var w := half
		if kind == "point" or kind == "fork":
			w = lerpf(half, 1.5, t)
		elif kind == "short":
			w = lerpf(half * 0.85, half * 0.55, t)
		else:
			w = lerpf(half * 0.72, half, minf(t * 1.6, 1.0))
			if t > 0.4:
				w = lerpf(w, half * 0.34, (t - 0.4) / 0.6)
		var reach := maxi(1, int(w))
		for x in range(xc - reach, xc + reach + 1):
			if kind == "fork" and t > 0.42 and absi(x - xc) <= 1 + int((t - 0.42) * 5.0):
				continue
			var edge := float(absi(x - xc)) / maxf(1.0, float(reach))
			if kind != "point" and kind != "fork" and t > 0.15 and edge > lerpf(0.98, 0.2, (t - 0.15) / 0.85):
				continue
			_px(x, y, _beard_at(x, y))

func _beard_ribbon(xc: int, y0: int, y1: int, half: float) -> void:
	for y in range(y0, mini(y1, SIZE)):
		var t := clampf(float(y - y0) / maxf(1.0, float(y1 - y0)), 0.0, 1.0)
		var w := int(lerpf(half, half * 0.45, t))
		for side in [-1, 1]:
			for k in range(3):
				_px(xc + side * w - side * k, y, _beard_at(xc, y))
		if y > int(chin_y) - 2:
			for x in range(-3, 4):
				_px(xc + x, y, _beard_at(xc + x, y))

func _beard_braids(xc: int, y0: int, length: int) -> void:
	for side in [-1, 1]:
		var bx: int = xc + int(side) * int(maxf(4.0, rx * 0.28))
		for i in range(length):
			var y := y0 + i
			var col := beard_ramp[4] if posmod(i, 4) == 3 else _beard_at(bx, y)
			_px(bx, y, col)
			_px(bx + side, y, beard_ramp[1])

func _moustache(xc: int, my: int, reach: int) -> void:
	for x in range(1, reach + 1):
		var droop := int(float(x) / float(maxi(reach, 1)) * 1.0)
		_px(xc - x, my - 1 + droop, _beard_at(xc - x, my))
		_px(xc + x, my - 1 + droop, _beard_at(xc + x, my))
		if x < reach:
			_px(xc - x, my - 2 + droop, _beard_at(xc - x, my))
			_px(xc + x, my - 2 + droop, _beard_at(xc + x, my))

func _stubble(xc: int, y0: int, y1: int, half: int) -> void:
	for y in range(y0, mini(y1, SIZE)):
		for x in range(xc - half, xc + half + 1):
			if not _probe(float(x) + 0.5, float(y) + 0.5):
				continue
			if posmod(x * 3 + y * 5 + seed, 4) != 0:
				continue
			_px(x, y, beard_ramp[1])

func _draw_tusks() -> void:
	if race != "orc" and race != "troll":
		return
	if _lost("mouth") or _lost("jaw") or _lost("head"):
		return
	var length := (12.0 if race == "troll" else 8.0) * (0.72 if sex_f else 1.0)
	var y := int(mouth_y) + 1
	var spread := 8 if race == "troll" else 6
	var xc := int(round(cx + 1.0))
	_tusk(xc - spread, y, -0.62, length)
	_tusk(xc + spread, y, 0.55, length * 0.92)

func _tusk(x0: int, y0: int, dir: float, length: float) -> void:
	var steps := int(length)
	var side := 1 if dir > 0.0 else -1
	for i in steps:
		var x := x0 + int(round(dir * float(i)))
		var y := y0 + i
		_px(x, y, IVORY)
		_px(x + side, y, IVORY)
		_px(x + side * 2, y, IVORY_DARK)
		if i == steps - 1:
			_px(x + side, y + 1, IVORY_DARK)

func _classify_helm() -> String:
	var blob := (String(helm.get("sprite", "")) + " " + String(helm.get("tid", ""))).to_lower()
	if blob.strip_edges() == "":
		return "none"
	if "coif" in blob or "hood" in blob:
		return "coif"
	if "great" in blob or "closed" in blob or "barrel" in blob or "frog" in blob:
		return "closed"
	if "crown" in blob or "circlet" in blob:
		return "crown"
	if "kettle" in blob:
		return "kettle"
	if "nasal" in blob:
		return "nasal"
	return "cap"

func _draw_hood() -> void:
	var ramp := _metal_ramp(_metal_of(helm))
	_disc_ramp(int(cx), int(cy - 2.0), int(rx + 7.0), int(ry + 8.0), ramp)
	_disc_ramp(int(cx), int(chin_y + 8.0), int(rx + 12.0), 14, ramp)

func _draw_closed_helm() -> void:
	var ramp := _metal_ramp(_metal_of(helm))
	var x0 := int(cx - rx - 8.0)
	var x1 := int(cx + rx + 8.0)
	var y0 := int(cy - ry - 8.0)
	var y1 := int(cy + ry + 4.0)
	for y in range(maxi(y0, 0), mini(y1, SIZE)):
		for x in range(maxi(x0, 0), mini(x1, SIZE)):
			var sx := cx + (float(x) + 0.5 - cx) * 0.88
			var sy := cy + (float(y) + 0.5 - cy) * 0.88
			if not _probe(sx, sy):
				continue
			_px(x, y, ramp[_lambert(nn)])
	for center in [eye_near, eye_far]:
		var x := int(round(center.x))
		var y := int(round(center.y))
		for dx in range(-3, 4):
			_px(x + dx, y, Color(0.055, 0.047, 0.063, 1.0))
			_px(x + dx, y - 1, ramp[4])

func _draw_open_helm() -> void:
	match helm_kind:
		"crown":
			_draw_crown()
		"kettle":
			_draw_dome(true)
		"nasal":
			_draw_dome(false)
			_nasal_strip()
		"cap":
			_draw_dome(false)
			if "spangen" in String(helm.get("sprite", "")).to_lower():
				_spangen_cross()
		_:
			return

func _draw_dome(brim: bool) -> void:
	var ramp := _metal_ramp(_metal_of(helm))
	var limit := eye_y - 6.0
	var x0 := int(cx - rx - 5.0)
	var x1 := int(cx + rx + 5.0)
	var y0 := int(cy - ry - 7.0)
	for y in range(maxi(y0, 0), mini(int(limit) + 1, SIZE)):
		for x in range(maxi(x0, 0), mini(x1, SIZE)):
			var sx := cx + (float(x) + 0.5 - cx) * 0.92
			var sy := cy + (float(y) + 0.5 - cy) * 0.92
			if not _probe(sx, sy) and float(y) > cy - ry:
				continue
			if float(y) > limit:
				continue
			if _probe(sx, sy) or float(y) < cy - ry + 2.0:
				var u := (float(x) - cx) / rx
				var v := (float(y) - (cy - ry * 0.4)) / ry
				var band := clampi(int(clampf(0.7 - u * 0.35 - v * 0.2, 0.0, 1.0) * 4.999), 0, 4)
				_px(x, y, ramp[band])
	if brim:
		for x in range(int(cx - rx - 12.0), int(cx + rx + 10.0)):
			_px(x, int(limit), ramp[4])
			_px(x, int(limit) + 1, ramp[2])
			_px(x, int(limit) + 2, ramp[1])

func _nasal_strip() -> void:
	var m := _metal_of(helm)
	var x := int(round(cx + 1.0))
	for y in range(int(eye_y - 6.0), int(nose_y)):
		_px(x, y, _op(m["light"]))
		_px(x + 1, y, _op(m["dark"]))

func _spangen_cross() -> void:
	var m := _metal_of(helm)
	var light := _op(m["light"])
	_hair_like_metal(Vector2(cx, cy - ry - 4.0), Vector2(cx, eye_y - 6.0), 1.15, light)
	_hair_like_metal(Vector2(cx - rx * 0.65, cy - ry * 0.35), Vector2(cx + rx * 0.55, cy - ry * 0.35), 1.05, light)

func _draw_crown() -> void:
	var m := _metal_of(helm)
	var y := int(cy - ry * 0.62)
	for i in 5:
		var x := int(cx - 10.0 + float(i) * 5.0)
		var tip := y - 8 - (i % 2) * 3
		_hair_like_metal(Vector2(x, y), Vector2(x, tip), 1.25, _op(m["base"]))
		_px(x, tip, _op(m["shine"]))
	_hair_like_metal(Vector2(cx - 12.0, y), Vector2(cx + 12.0, y), 1.5, _op(m["light"]))

func _hair_like_metal(a: Vector2, b: Vector2, rad: float, col: Color) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(rad, rad)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(rad, rad)
	for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)) + 1, SIZE)):
		for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)) + 1, SIZE)):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_squared_to(p) > rad * rad:
				continue
			_px(x, y, col)

func _draw_lost_blood() -> void:
	if _lost("nose"):
		_blob(int(round(cx + 1.5)), int(round(nose_y)), 3, FigurePainter.BLOOD)
	if _lost("jaw"):
		_blob(int(cx), int(chin_y), 4, FigurePainter.BLOOD)

func _blob(x0: int, y0: int, r: int, col: Color) -> void:
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y > r * r:
				continue
			_px(x0 + x, y0 + y, FigurePainter.BLOOD_DARK if x * x + y * y <= 1 else col)

func _outline() -> void:
	var add: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			if cv.get_px(x, y).a < 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + (d as Vector2i)
				if q.x < 0 or q.y < 0 or q.x >= SIZE or q.y >= SIZE:
					continue
				if cv.get_px(q.x, q.y).a < 0.2:
					add.append(q)
	for q in add:
		cv.set_px(q.x, q.y, OUTLINE)
