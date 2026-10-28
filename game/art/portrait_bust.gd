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
	"dwarf": {"rx": 28.0, "ry": 18.2, "cy": 42.0, "jaw": 1.34, "neck": 10.6, "sh": 41.0, "brow": 1.42, "eye": 0.90, "nose": "bulb", "ear": "small"},
	"high_elf": {"rx": 16.2, "ry": 23.0, "cy": 37.0, "jaw": 0.84, "neck": 6.2, "sh": 29.0, "brow": 0.72, "eye": 1.05, "nose": "fine", "ear": "high"},
	"moon_elf": {"rx": 15.4, "ry": 22.5, "cy": 37.5, "jaw": 0.82, "neck": 5.8, "sh": 28.0, "brow": 0.66, "eye": 1.08, "nose": "fine", "ear": "moon"},
	"dark_elf": {"rx": 16.0, "ry": 22.6, "cy": 37.5, "jaw": 0.86, "neck": 6.0, "sh": 29.0, "brow": 0.78, "eye": 1.04, "nose": "fine", "ear": "dark"},
	"orc": {"rx": 20.0, "ry": 21.0, "cy": 39.0, "jaw": 1.08, "neck": 9.0, "sh": 36.0, "brow": 1.5, "eye": 0.96, "nose": "flat", "ear": "point"},
	"goblin": {"rx": 14.0, "ry": 16.0, "cy": 43.0, "jaw": 0.90, "neck": 5.6, "sh": 26.0, "brow": 0.9, "eye": 1.28, "nose": "hook", "ear": "fan"},
	"troll": {"rx": 25.0, "ry": 21.0, "cy": 40.0, "jaw": 1.48, "neck": 12.0, "sh": 42.0, "brow": 2.15, "eye": 1.10, "nose": "flat", "ear": "heavy"},
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
	_stage_marks()
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
	jaw = float(m["jaw"])
	if sex_f:
		if race == "dwarf":
			jaw *= 0.96
			rx += 1.5
		elif race == "goblin":
			jaw *= 0.72
			rx *= 0.90
		elif race == "troll":
			jaw *= 0.82
		elif race == "dark_elf":
			jaw *= 0.80
		elif race == "moon_elf":
			jaw *= 0.78
		else:
			jaw *= 0.86
	if stage == "young":
		var pull: float = 0.40
		if race == "dwarf":
			pull = 0.20
		elif race == "goblin" or race == "troll":
			pull = 0.16
		jaw = lerpf(jaw, jaw * 0.86, pull)
	elif stage == "elder" and not sex_f:
		jaw *= 1.06
	neck_w = float(m["neck"])
	sh_w = float(m["sh"])
	brow_k = float(m["brow"]) * (0.74 if sex_f else 1.0)
	if race == "troll" and not sex_f:
		if stage == "adult":
			brow_k *= 1.15
		elif stage == "elder":
			brow_k *= 1.08
		else:
			brow_k *= 0.82
	elif race == "troll" and sex_f:
		brow_k *= 0.70
	eye_k = float(m["eye"])
	if stage == "young":
		eye_k *= 1.06 if race == "troll" else 1.14
	elif stage == "elder":
		eye_k *= 0.96 if race == "troll" else 0.88
	if sex_f and race != "troll":
		eye_k *= 1.05
	if race == "dark_elf":
		if stage == "young":
			jaw *= 1.14
			brow_k *= 0.62
			eye_k *= 1.10
		elif not sex_f and stage == "adult":
			jaw *= 1.24
			brow_k *= 1.55
		elif not sex_f and stage == "elder":
			jaw *= 0.78
			brow_k *= 1.15
			eye_k *= 0.90
		elif sex_f and stage == "elder":
			jaw *= 0.72
			brow_k *= 0.78
			eye_k *= 0.94
		elif sex_f:
			jaw *= 0.76
			brow_k *= 0.66
	elif race == "moon_elf":
		if stage == "young" and not sex_f:
			jaw *= 1.08
			brow_k *= 0.80
			eye_k *= 1.08
		elif stage == "young" and sex_f:
			jaw *= 0.88
			brow_k *= 0.66
			eye_k *= 1.12
		elif not sex_f and stage == "adult":
			brow_k *= 1.55
		elif not sex_f and stage == "elder":
			jaw *= 0.94
			brow_k *= 1.20
			eye_k *= 0.86
		if sex_f:
			jaw *= 0.72
			brow_k *= 0.64
			if stage == "elder":
				eye_k *= 0.92
	elif race == "goblin":
		if stage == "young":
			jaw *= 0.86
			brow_k *= 0.68
			eye_k *= 1.10
		elif stage == "elder":
			jaw *= 1.10
			brow_k *= 1.28
			eye_k *= 0.78
		elif not sex_f:
			jaw *= 1.12
			brow_k *= 1.22
	elif race == "troll":
		if stage == "young":
			jaw *= 0.88
		elif stage == "elder" and not sex_f:
			jaw *= 1.10
			brow_k *= 1.08
	nose_k = String(m["nose"])
	ear_k = String(m["ear"])
	cx = 48.0
	eye_y = cy - ry * 0.06
	mouth_y = cy + ry * 0.52
	chin_y = cy + ry * 0.92
	if race == "moon_elf":
		if sex_f:
			eye_y -= 1.2
			mouth_y -= 1.0
		elif stage == "elder":
			eye_y += 1.0
			mouth_y += 0.8
		elif stage == "young":
			eye_y -= 0.6
	elif race == "dark_elf":
		if stage == "young":
			eye_y -= 1.0
			mouth_y += 1.2
		elif stage == "elder":
			eye_y += 1.2
			mouth_y += 1.4
		if sex_f:
			mouth_y -= 0.8
			eye_y -= 0.4
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
	if race == "moon_elf":
		hair = _op(hair.lerp(Color(0.40, 0.50, 0.74), 0.82))
	if stage == "elder":
		if race == "dark_elf":
			hair = _op(hair.lerp(Color(0.92, 0.92, 0.95), 0.70))
		elif race == "moon_elf":
			if sex_f:
				hair = _op(hair.lerp(Color(0.76, 0.82, 0.92), 0.76))
			else:
				hair = _op(hair.lerp(Color(0.94, 0.95, 0.98), 0.88))
		else:
			hair = _op(hair.lerp(Color("#d8d8dc"), 0.55))
	_read_beard()
	if stage == "elder":
		if race == "moon_elf":
			beard_col = _op(beard_col.lerp(Color(0.62, 0.70, 0.84), 0.45))
		elif race == "dark_elf":
			beard_col = _op(beard_col.lerp(Color(0.55, 0.56, 0.60), 0.50))
		else:
			beard_col = _op(beard_col.lerp(Color("#d8d8dc"), 0.55))
	elif race == "dwarf":
		beard_col = _op(beard_col.lerp(Color("#5c3318"), 0.55))
	var skin_depth: float = 0.52
	if skin.get_luminance() > 0.70 or race == "moon_elf":
		skin_depth = 0.66
	var hair_depth: float = 0.52
	if race == "dark_elf":
		hair_depth = 0.55 if stage == "elder" else 0.30
	elif race == "moon_elf":
		hair_depth = 0.34 if stage == "elder" else 0.48
	skin_ramp = _ramp(skin, skin_depth)
	if race == "moon_elf":
		var pale := skin
		skin_ramp = [
			_op(pale.lerp(Color(0.14, 0.20, 0.34), 0.90)),
			_op(pale.lerp(Color(0.26, 0.34, 0.50), 0.82)),
			_op(pale.lerp(Color(0.38, 0.48, 0.66), 0.70)),
			_op(pale.lerp(Color(0.52, 0.62, 0.78), 0.58)),
			_op(pale.lerp(Color(0.70, 0.78, 0.90), 0.48)),
		]
	elif race == "dark_elf":
		var dusk := skin
		skin_ramp = [
			_op(dusk.lerp(Color(0.12, 0.08, 0.16), 0.62)),
			_op(dusk.darkened(0.36)),
			_op(dusk.darkened(0.16)),
			_op(dusk),
			_op(dusk.lightened(0.20)),
		]
	hair_ramp = _ramp(hair, hair_depth)
	if race == "moon_elf":
		var hcol := hair
		var hmix := 0.40 if stage == "elder" else 0.78
		var hshadow := hcol.lerp(Color(0.16, 0.22, 0.40), hmix)
		var hdark := 0.10 if stage == "elder" else 0.24
		hair_ramp = [
			_op(hshadow),
			_op(hcol.lerp(hshadow, 0.55)),
			_op(hcol.darkened(hdark)),
			_op(hcol.darkened(0.06)),
			_op(hcol.lightened(0.08)),
		]
	elif race == "dark_elf":
		var dh := hair
		var dshadow := dh.lerp(Color(0.16, 0.14, 0.22), 0.64)
		hair_ramp = [
			_op(dshadow),
			_op(dh.lerp(dshadow, 0.48)),
			_op(dh.darkened(0.22)),
			_op(dh.darkened(0.08)),
			_op(dh.lightened(0.05)),
		]
	if race == "dwarf" and stage != "elder":
		beard_ramp = [
			_op(Color("#3a2412")),
			_op(Color("#6a3e20")),
			_op(Color("#8f5a30")),
			_op(Color("#c08448")),
			_op(Color("#e0b070")),
		]
	else:
		beard_ramp = _ramp(beard_col, 0.50)
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
	if sex_f:
		match race:
			"troll":
				if stage == "elder":
					return "receding"
				return "side"
			"goblin":
				if stage == "elder":
					return "braid"
				if stage == "adult":
					return "half"
				return "long"
			"dwarf":
				return "braid"
			"orc":
				if stage == "elder":
					return "receding"
				if stage == "young":
					return "long"
				return "braid"
			"high_elf":
				return "braid" if stage == "elder" else "long"
			"moon_elf":
				if stage == "young":
					return "braid"
				if stage == "elder":
					return "long"
				return "half"
			"dark_elf":
				if stage == "young":
					return "long"
				if stage == "elder":
					return "braid"
				return "half"
			_:
				if stage == "young":
					return "long"
				if stage == "elder":
					return "braid"
				return "half"
	match race:
		"troll":
			if stage == "elder":
				return "bald"
			if stage == "adult":
				return "mohawk"
			return "tuft"
		"goblin":
			if stage == "elder":
				return "bald"
			if stage == "adult":
				return "tuft"
			return "short"
		"orc":
			if stage == "elder":
				return "receding"
			if stage == "adult":
				return "short"
			return "tuft"
		"high_elf":
			if stage == "young":
				return "long"
			if stage == "adult":
				return "braid"
			return "half"
		"moon_elf":
			if stage == "elder":
				return "receding"
			return "long"
		"dark_elf":
			if stage == "young":
				return "side"
			if stage == "adult":
				return "half"
			return "receding"
		"dwarf":
			if stage == "elder":
				return "receding"
			if stage == "adult":
				return "long"
			return "short"
		_:
			if stage == "elder":
				return "receding"
			if stage == "adult":
				return "half"
			return "short"

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
	var lum := base.get_luminance()
	var use_depth := depth
	var lift := 0.10
	var hi_mix := 0.28
	if lum > 0.72:
		use_depth = maxf(depth, 0.62)
		lift = 0.03
		hi_mix = 0.06
	if lum < 0.15:
		return [
			_op(base),
			_op(base.lightened(0.08)),
			_op(base.lightened(0.16)),
			_op(base.lightened(0.28)),
			_op(base.lightened(0.40)),
		]
	var hi := Color(1.0, 0.96, 0.90, 1.0)
	return [
		_op(base.darkened(use_depth)),
		_op(base.darkened(use_depth * 0.58)),
		_op(base.darkened(use_depth * 0.26)),
		_op(base),
		_op(base.lightened(lift).lerp(hi, hi_mix)),
	]

func _shade_band(lit: float, x: int, y: int) -> int:
	var dither := 0.07 if ((x + y) & 1) == 0 else -0.06
	return clampi(int(clampf(lit + dither, 0.0, 0.98) * 4.999), 0, 4)

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
	var mid := cx + lerpf(-0.6, 2.6, smoothstep(-0.15, 0.8, v))
	var dx := px - mid
	var side := 1.05 if dx < 0.0 else 0.91
	if race == "troll" and v > 0.46:
		var shelf := jaw * (0.70 if sex_f else 0.78)
		if stage == "young":
			shelf *= 0.92
		elif stage == "elder" and not sex_f:
			shelf *= 1.06
		var u_jaw := dx / (rx * shelf * side)
		var v_jaw := (v - 0.46) / 0.62
		var inside := absf(u_jaw) <= 1.0 and v_jaw <= 1.0
		if inside and v_jaw > 0.72:
			var chin_u := absf(u_jaw)
			var chin_v := (v_jaw - 0.72) / 0.40
			if chin_u * chin_u + chin_v * chin_v > 1.0:
				inside = false
		if not inside:
			return false
		nu = u_jaw
		nv = v
		nn = Vector3(u_jaw * 0.70, 0.42, 0.55).normalized()
		return true
	if v >= 0.0:
		xrad = lerpf(1.0, jaw * (0.84 if sex_f else 0.93), smoothstep(0.02, 0.92, v))
		if v > 0.76:
			var pinch: float = 0.58 if sex_f else 0.74
			if race == "dwarf":
				pinch = 0.90 if sex_f else 0.93
			elif race == "troll":
				pinch = 0.78 if sex_f else 0.96
			elif race == "goblin" and sex_f:
				pinch = 0.50
			elif race == "goblin" and stage == "elder":
				pinch = 0.70
			elif race == "moon_elf":
				if sex_f:
					pinch = 0.66
				elif stage == "elder":
					pinch = 0.58
				elif stage == "young":
					pinch = 0.80
				else:
					pinch = 0.72
			elif race == "dark_elf":
				if stage == "young":
					pinch = 0.82 if sex_f else 0.96
				elif sex_f:
					pinch = 0.64
				elif stage == "elder":
					pinch = 0.48
				else:
					pinch = 0.98
			xrad *= lerpf(1.0, pinch, smoothstep(0.76, 1.02, v))
		if race == "moon_elf" and sex_f and v > 0.10:
			xrad *= lerpf(0.94, 0.74, smoothstep(0.10, 0.70, v))
		elif race == "dark_elf" and sex_f and v > 0.12:
			xrad *= lerpf(0.94, 0.76, smoothstep(0.12, 0.72, v))
		elif race == "dark_elf" and not sex_f and stage == "adult" and v > 0.05:
			xrad *= 1.22
		elif race == "dark_elf" and not sex_f and stage == "elder" and v > 0.12:
			xrad *= lerpf(0.96, 0.78, smoothstep(0.12, 0.70, v))
	else:
		xrad = lerpf(0.88, 1.0, smoothstep(-1.05, -0.1, v))
	var u := dx / (rx * xrad * side)
	if u * u + v * v > 1.0:
		return false
	var z := sqrt(maxf(0.0, 1.0 - u * u - v * v))
	nu = u
	nv = v
	nn = Vector3(u * 0.92 - 0.16, v * 0.95 + 0.02, z + 0.08).normalized()
	return true

func _skin_at() -> Color:
	var lit := clampf(0.84 - nu * 0.46 - maxf(nv, -0.15) * 0.34, 0.06, 0.94)
	var px := int(cx + nu * rx)
	var py := int(cy + nv * ry)
	var band := _shade_band(lit, px, py)
	if Vector2(nu + 0.28, nv - 0.06).length() < 0.30:
		band = mini(4, band + 1)
	if brow_k > 1.20 and nv > -0.36 and nv < 0.02 and absf(nu) < 0.72:
		band = maxi(0, band - 1)
	if race == "troll":
		if nv > -0.42 and nv < 0.08 and absf(nu) < 0.88:
			band = maxi(1, band - 1)
		if nv > 0.22:
			band = maxi(0, band - 1)
		if absf(nu) > 0.55 and nv > 0.15:
			band = maxi(0, band - 1)
	elif race == "dwarf" and absf(nu) < 0.38 and nv > 0.02 and nv < 0.50:
		band = mini(4, band + 1)
	elif race == "goblin" or race == "orc":
		if nv < -0.32:
			band = mini(4, band + 1)
		elif nv > 0.40:
			band = maxi(0, band - 1)
		elif absf(nu) > 0.48 and nv > 0.0 and nv < 0.40:
			band = maxi(0, band - 1)
	elif race == "moon_elf":
		if absf(nu) > 0.16 and absf(nu) < 0.52 and nv > -0.06 and nv < 0.14:
			band = mini(4, band + 2)
		if absf(nu) > 0.26 and absf(nu) < 0.72 and nv > 0.14 and nv < 0.42:
			band = maxi(0, band - 2)
	elif race == "dark_elf":
		if stage == "young" and absf(nu) > 0.22 and absf(nu) < 0.68 and nv > 0.02 and nv < 0.40:
			band = mini(4, band + 1)
		if stage == "elder" and absf(nu) > 0.26 and absf(nu) < 0.78 and nv > 0.06 and nv < 0.52:
			band = maxi(0, band - 2)
		if not sex_f and stage == "adult" and absf(nu) < 0.55 and nv > 0.20:
			band = mini(4, band + 1)
		if sex_f and nv > 0.50 and absf(nu) < 0.35:
			band = mini(4, band + 1)
	return skin_ramp[clampi(band, 0, 4)]

func _draw_skull() -> void:
	var pad := 18.0 if race == "troll" else 4.0
	var x0 := int(cx - rx - pad)
	var x1 := int(cx + rx + pad)
	var y0 := int(cy - ry - 3.0)
	var y1 := int(cy + ry + (10.0 if race == "troll" else 3.0))
	for y in range(maxi(y0, 0), mini(y1, SIZE)):
		for x in range(maxi(x0, 0), mini(x1, SIZE)):
			if not _probe(float(x) + 0.5, float(y) + 0.5):
				continue
			if _lost("jaw") and nv > 0.40:
				continue
			_px(x, y, _skin_at())

func _blush() -> void:
	if race == "moon_elf" or not (stage == "young" and sex_f):
		return
	var blush := _op(skin.lerp(Color("#e09098"), 0.40))
	var dy := 4
	_px(int(eye_near.x) - 2, int(eye_near.y) + dy, blush)
	_px(int(eye_near.x) - 1, int(eye_near.y) + dy, blush)
	_px(int(eye_near.x) - 2, int(eye_near.y) + dy + 1, blush)
	_px(int(eye_near.x) - 1, int(eye_near.y) + dy + 1, blush)
	_px(int(eye_far.x) + 1, int(eye_far.y) + dy, blush)
	_px(int(eye_far.x) + 2, int(eye_far.y) + dy, blush)
	_px(int(eye_far.x) + 1, int(eye_far.y) + dy + 1, blush)
	_px(int(eye_far.x) + 2, int(eye_far.y) + dy + 1, blush)

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
			var lit := clampf(0.86 - ((float(x) - cx) / maxf(8.0, half)) * 0.70 - float(y - y0) / 24.0, 0.04, 0.96)
			_px(x, y, cloth[_shade_band(lit, x, y)])
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
			var lit := clampf(0.78 - u * 0.72 - t * 0.42, 0.04, 0.96)
			if y < y0 + 3:
				lit *= 0.70
			_px(x, y, skin_ramp[_shade_band(lit, x, y)])

func _draw_collar() -> void:
	var y := int(torso_y + 7.0)
	var half := int(neck_w + 3.0)
	var cloth_dark := _op(prim.darkened(0.30))
	for x in range(-half, half + 1):
		_px(int(cx) + x, y, cloth_dark)
	if race == "dark_elf":
		return
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
			var lit := clampf(0.82 - u * 0.64 - float(y - y0) / 22.0, 0.04, 0.96)
			_px(x, y, ramp[_shade_band(lit, x, y)])
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
			if ((x + y) & 1) == 0 and band > 0 and band < 4:
				band = mini(4, band + 1) if u < 0.0 else maxi(0, band - 1)
			_px(ccx + x, ccy + y, ramp[band])

func _hair_col(x: int, y: int) -> Color:
	var u := float(x - int(cx)) / maxf(10.0, rx)
	var v := float(y - int(cy - ry)) / maxf(12.0, ry * 1.4)
	var spread: float = 0.50
	if race == "dark_elf":
		spread = 0.48 if stage == "elder" else 0.30
	elif race == "moon_elf":
		spread = 0.60
	var lit := clampf(0.78 - u * spread - v * (spread + 0.08), 0.06, 0.94)
	var band := _shade_band(lit, x, y)
	if posmod(x + seed, 5) == 0 and posmod(y, 3) == 1:
		band = maxi(0, band - 1)
	elif posmod(x * 3 + y, 11) == 0:
		band = mini(4, band + 1)
	if hstyle == "braid" and absi(x - int(braid_x)) <= 3 and posmod(y, 4) == 0:
		band = mini(4, band + 1)
	elif hstyle == "braid" and absi(x - int(braid_x)) <= 3 and posmod(y, 4) == 2:
		band = maxi(0, band - 1)
	if race == "dwarf" and sex_f and hstyle == "braid":
		var left_col := int(cx - rx * 0.78)
		var right_col := int(cx + rx * 0.85)
		if absi(x - left_col) <= 4 or absi(x - right_col) <= 4:
			if posmod(y, 4) == 0:
				band = mini(4, band + 2)
			elif posmod(y, 4) == 2:
				band = maxi(0, band - 1)
			if posmod(x, 2) == 0:
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
	if race == "moon_elf":
		_moon_hair(false)
		return
	if race == "dark_elf":
		_dark_hair(false)
		return
	if race == "troll" and sex_f and stage == "young":
		_troll_young_hair(true)
		return
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
	var yb := int(y1)
	for x in range(int(cx - rx * 0.72), int(cx + rx * 0.55)):
		if posmod(x + seed, 3) == 0:
			continue
		if not _probe(float(x) + 0.5, float(yb) + 0.5):
			continue
		var hang: int = 2 + posmod(x + seed, 3)
		for k in range(hang):
			_px(x, yb + k, _hair_col(x, yb + k))

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
	if race == "moon_elf":
		_moon_hair(true)
		return
	if race == "dark_elf":
		_dark_hair(true)
		return
	if race == "troll" and sex_f and stage == "young":
		_troll_young_hair(false)
		return
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
			_fringe(3.0)
		"receding":
			_hair_ellipse(Vector2(cx - rx * 0.52, eye_y - 7.0), rx * 0.64, 12.0, eye_y - 2.0)
			_hair_ellipse(Vector2(cx + rx * 0.38, eye_y - 8.0), rx * 0.50, 10.0, eye_y - 2.0)
			_hair_ellipse(Vector2(cx - 1.0, cy - ry + 2.0), rx * 0.62, 7.0, cy - ry * 0.45)
		"short", "side":
			_hair_cap(line, 1.04)
			if race == "orc" or race == "goblin":
				_fringe(5.0)
			if hstyle == "side":
				var dir := -1.0 if part_left else 1.0
				_hair_ellipse(Vector2(cx + dir * rx * 0.34, eye_y - 8.0), rx * 0.52, 7.0, eye_y - 1.0)
		"half":
			_hair_cap(line + 2.0, 1.02)
			if race == "moon_elf" or (race == "dark_elf" and not sex_f and stage == "adult"):
				_side_locks(false)
		"long":
			_hair_cap(line, 1.06)
			if sex_f or race == "moon_elf":
				_side_locks(true)
		"braid":
			_hair_cap(line, 1.02)
			if race == "dwarf" and sex_f:
				var left_a := Vector2(cx - rx * 0.70, eye_y + 2.0)
				var left_b := Vector2(cx - rx * 0.86, 93.0)
				var right_a := Vector2(cx + rx * 0.76, eye_y + 2.0)
				var right_b := Vector2(cx + rx * 0.94, 93.0)
				_hair_capsule(left_a, left_b, 4.2)
				_hair_capsule(right_a, right_b, 4.2)
				_braid_strands(left_a, left_b)
				_braid_strands(right_a, right_b)
			else:
				if sex_f or race == "moon_elf":
					_side_locks(false)
				var lean := 2.0 if braid_x > cx else -2.0
				var rad: float = 4.2 if race == "dwarf" else 3.4
				_hair_capsule(Vector2(braid_x, mouth_y), Vector2(braid_x + lean, 93.0), rad)

func _moon_wave(dir: float, rad: float, y1: float) -> void:
	var x0 := cx + dir * rx * 0.82
	var y0 := cy - ry + 2.0
	_hair_capsule(Vector2(x0, y0), Vector2(x0 + dir * 3.2, y0 + 16.0), rad)
	_hair_capsule(Vector2(x0 + dir * 3.2, y0 + 16.0), Vector2(x0 - dir * 1.2, y0 + 32.0), rad * 0.85)
	_hair_capsule(Vector2(x0 - dir * 1.2, y0 + 32.0), Vector2(x0 + dir * 2.0, y1), rad * 0.75)

func _moon_circlet() -> void:
	var y := int(eye_y) - 8
	var metal := Color(0.74, 0.78, 0.88, 1.0)
	var shine := Color(0.94, 0.96, 0.99, 1.0)
	var x0 := int(cx - rx * 0.55)
	var x1 := int(cx + rx * 0.40)
	for x in range(x0, x1 + 1):
		var arch := 1 if (x < x0 + 2 or x > x1 - 2) else 0
		_px(x, y + arch, metal)
		_px(x, y + arch + 1, _op(metal.darkened(0.28)))
		if posmod(x, 3) == 0:
			_px(x, y + arch - 1, shine)
	_px(int(cx), y - 1, shine)
	_px(int(cx), y, Color(0.55, 0.62, 0.82, 1.0))

func _moon_hair(front: bool) -> void:
	var top := cy - ry
	if sex_f and stage == "young":
		var side := 1.0 if part_left else -1.0
		var other := -side
		var braid_a := Vector2(cx + side * rx * 0.95, eye_y + 4.0)
		var braid_b := Vector2(braid_a.x + side * 2.0, 94.0)
		if front:
			_hair_ellipse(Vector2(cx, top + 1.0), rx * 1.05, 9.0, eye_y - 6.0)
			_hair_capsule(Vector2(cx + other * rx * 0.82, top + 4.0), Vector2(cx + other * rx * 0.95, 90.0), 4.2)
			_hair_capsule(braid_a, braid_b, 5.2)
			_braid_strands(braid_a, braid_b)
			for n in range(8):
				var by := int(braid_a.y + float(n) * 7.0)
				var bx := int(braid_a.x + side * float(n) * 0.35)
				_px(bx - 1, by, hair_ramp[0])
				_px(bx, by, hair_ramp[4])
				_px(bx + 1, by, hair_ramp[0])
		else:
			_hair_ellipse(Vector2(cx, top - 1.0), rx * 1.18, 12.0, eye_y - 1.0)
			_hair_capsule(Vector2(cx + other * rx * 1.05, top + 2.0), Vector2(cx + other * rx * 1.12, 94.0), 5.0)
			_hair_capsule(braid_a + Vector2(side * 2.0, 4.0), braid_b, 4.4)
	elif sex_f and stage == "elder":
		if front:
			_hair_ellipse(Vector2(cx + 1.0, top - 8.0), 8.0, 6.5)
			_hair_ellipse(Vector2(cx - 2.0, top - 4.0), 6.0, 4.5, eye_y - 8.0)
			_moon_wave(-1.0, 3.6, 86.0)
			_moon_wave(1.0, 3.2, 80.0)
		else:
			_hair_ellipse(Vector2(cx, top - 10.0), 9.5, 8.0)
			_hair_ellipse(Vector2(cx, top - 2.0), rx * 0.95, 7.0, eye_y - 6.0)
			_moon_wave(-1.0, 4.4, 94.0)
			_moon_wave(1.0, 4.0, 92.0)
	elif sex_f:
		if front:
			_hair_ellipse(Vector2(cx, top - 9.0), 7.5, 6.0)
			_hair_capsule(Vector2(cx - rx * 0.70, eye_y - 2.0), Vector2(cx - rx * 0.55, mouth_y + 6.0), 3.2)
		else:
			_hair_ellipse(Vector2(cx, top - 8.0), 9.0, 7.5)
			_hair_ellipse(Vector2(cx, top), rx * 0.90, 6.0, eye_y - 5.0)
	elif stage == "young":
		var y_end := mouth_y + 2.0
		if front:
			_hair_ellipse(Vector2(cx, top + 1.0), rx * 1.12, 11.0, eye_y - 5.0)
			_hair_capsule(Vector2(cx - rx * 0.95, top + 8.0), Vector2(cx - rx * 1.05, y_end), 5.4)
			_hair_capsule(Vector2(cx + rx * 0.85, top + 9.0), Vector2(cx + rx * 0.95, y_end - 1.0), 5.0)
		else:
			_hair_ellipse(Vector2(cx, top - 2.0), rx * 1.20, 12.5, eye_y)
			_hair_capsule(Vector2(cx - rx * 1.10, top + 4.0), Vector2(cx - rx * 1.15, y_end + 2.0), 5.6)
			_hair_capsule(Vector2(cx + rx * 1.00, top + 5.0), Vector2(cx + rx * 1.05, y_end), 5.2)
	elif stage == "elder":
		if front:
			_hair_capsule(Vector2(cx - rx * 0.92, eye_y - 1.0), Vector2(cx - rx * 1.02, 94.0), 2.3)
			_hair_capsule(Vector2(cx + rx * 0.82, eye_y), Vector2(cx + rx * 0.92, 92.0), 2.1)
			_hair_ellipse(Vector2(cx - rx * 0.70, eye_y - 5.0), rx * 0.42, 8.0, eye_y - 2.0)
			_hair_ellipse(Vector2(cx + rx * 0.52, eye_y - 6.0), rx * 0.36, 7.0, eye_y - 2.0)
		else:
			_hair_ellipse(Vector2(cx - 1.0, top + 4.0), rx * 0.72, 6.5, cy - ry * 0.35)
			_hair_capsule(Vector2(cx - rx * 1.08, eye_y - 4.0), Vector2(cx - rx * 1.15, 95.0), 2.6)
			_hair_capsule(Vector2(cx + rx * 0.98, eye_y - 3.0), Vector2(cx + rx * 1.05, 94.0), 2.4)
	elif front:
		_hair_ellipse(Vector2(cx, top + 1.0), rx * 1.02, 9.5, eye_y - 8.0)
		_hair_capsule(Vector2(cx - rx * 0.90, top + 5.0), Vector2(cx - rx * 1.00, 92.0), 4.8)
		_hair_capsule(Vector2(cx + rx * 0.80, top + 6.0), Vector2(cx + rx * 0.92, 90.0), 4.5)
		_moon_circlet()
	else:
		_hair_ellipse(Vector2(cx, top - 2.0), rx * 1.15, 12.0, eye_y - 2.0)
		_hair_capsule(Vector2(cx - rx * 1.08, top + 1.0), Vector2(cx - rx * 1.16, 95.0), 5.4)
		_hair_capsule(Vector2(cx + rx * 0.96, top + 2.0), Vector2(cx + rx * 1.06, 94.0), 5.0)

func _dark_hair(front: bool) -> void:
	var top := cy - ry
	if sex_f and stage == "elder":
		var side := 1.0 if part_left else -1.0
		var braid_a := Vector2(cx + side * rx * 0.55, top + 2.0)
		var braid_b := Vector2(cx + side * rx * 0.85, 94.0)
		if front:
			_hair_ellipse(Vector2(cx - side * 2.0, top - 9.0), 8.5, 6.5)
			_hair_ellipse(Vector2(cx, top - 3.0), rx * 0.72, 5.5, eye_y - 8.0)
			_hair_capsule(braid_a, braid_b, 5.0)
			_braid_strands(braid_a, braid_b)
			for n in range(8):
				var by := int(braid_a.y + float(n) * 8.0)
				var bx := int(braid_a.x + side * float(n) * 0.4)
				_px(bx - 1, by, hair_ramp[0])
				_px(bx, by, hair_ramp[4])
				_px(bx + 1, by, hair_ramp[0])
		else:
			_hair_ellipse(Vector2(cx, top - 11.0), 10.0, 8.0)
			_hair_ellipse(Vector2(cx + side * 3.0, top - 6.0), 6.5, 5.0)
			_hair_capsule(Vector2(cx - side * rx * 0.90, top + 4.0), Vector2(cx - side * rx * 1.00, 88.0), 4.0)
			_hair_capsule(braid_a + Vector2(side * 2.0, 6.0), braid_b, 3.2)
	elif sex_f and stage == "young":
		if front:
			_hair_ellipse(Vector2(cx, top + 1.0), rx * 1.08, 9.5, eye_y - 5.0)
			_hair_capsule(Vector2(cx - rx * 0.85, top + 5.0), Vector2(cx - rx * 0.95, 93.0), 4.6)
			_hair_capsule(Vector2(cx + rx * 0.75, top + 6.0), Vector2(cx + rx * 0.88, 91.0), 4.3)
		else:
			_hair_ellipse(Vector2(cx, top - 2.0), rx * 1.18, 12.0, eye_y)
			_hair_capsule(Vector2(cx - rx * 1.08, top + 2.0), Vector2(cx - rx * 1.15, 95.0), 5.2)
			_hair_capsule(Vector2(cx + rx * 0.98, top + 3.0), Vector2(cx + rx * 1.08, 94.0), 5.0)
	elif sex_f:
		if front:
			_hair_ellipse(Vector2(cx, top - 8.0), 7.0, 5.5)
			_hair_capsule(Vector2(cx - rx * 0.70, eye_y), Vector2(cx - rx * 0.80, 90.0), 3.6)
		else:
			_hair_ellipse(Vector2(cx, top - 9.0), 8.5, 7.0)
			_hair_ellipse(Vector2(cx, top), rx * 0.85, 6.0, eye_y - 4.0)
	elif stage == "young":
		if front:
			_hair_ellipse(Vector2(cx - 1.0, top + 2.0), rx * 0.92, 8.0, eye_y - 5.0)
			_fringe(6.0)
			_hair_capsule(Vector2(cx - rx * 0.95, eye_y - 4.0), Vector2(cx - rx * 1.02, eye_y + 8.0), 3.2)
			_hair_capsule(Vector2(cx + rx * 0.85, eye_y - 3.0), Vector2(cx + rx * 0.92, eye_y + 6.0), 2.8)
		else:
			_hair_ellipse(Vector2(cx, top - 1.0), rx * 1.05, 10.0, eye_y - 2.0)
			_hair_capsule(Vector2(cx - rx * 1.00, top + 4.0), Vector2(cx - rx * 1.05, mouth_y), 3.4)
			_hair_capsule(Vector2(cx + rx * 0.90, top + 5.0), Vector2(cx + rx * 0.95, mouth_y - 2.0), 3.1)
	elif stage == "elder":
		if front:
			_hair_ellipse(Vector2(cx - rx * 0.62, eye_y - 6.0), rx * 0.40, 7.5, eye_y - 2.0)
			_hair_ellipse(Vector2(cx + rx * 0.48, eye_y - 7.0), rx * 0.34, 6.5, eye_y - 2.0)
			_hair_capsule(Vector2(cx - rx * 0.95, eye_y), Vector2(cx - rx * 1.05, 92.0), 2.7)
			_hair_capsule(Vector2(cx + rx * 0.85, eye_y + 1.0), Vector2(cx + rx * 0.95, 90.0), 2.5)
		else:
			_hair_ellipse(Vector2(cx, top + 5.0), rx * 0.62, 5.5, cy - ry * 0.25)
			_hair_capsule(Vector2(cx - rx * 1.05, eye_y - 2.0), Vector2(cx - rx * 1.12, 95.0), 3.0)
			_hair_capsule(Vector2(cx + rx * 0.95, eye_y - 1.0), Vector2(cx + rx * 1.02, 94.0), 2.8)
	elif front:
		_hair_ellipse(Vector2(cx - 2.0, top + 1.0), rx * 1.00, 8.5, eye_y - 7.0)
		_hair_capsule(Vector2(cx - rx * 0.20, top - 1.0), Vector2(cx - rx * 0.85, mouth_y + 16.0), 4.4)
		_hair_capsule(Vector2(cx + rx * 0.55, top + 4.0), Vector2(cx + rx * 0.95, mouth_y + 8.0), 3.6)
	else:
		_hair_ellipse(Vector2(cx, top - 1.0), rx * 1.12, 11.0, eye_y - 1.0)
		_hair_capsule(Vector2(cx - rx * 1.05, top + 2.0), Vector2(cx - rx * 1.15, mouth_y + 22.0), 4.8)
		_hair_capsule(Vector2(cx + rx * 0.70, top + 3.0), Vector2(cx + rx * 1.00, mouth_y + 12.0), 4.0)

func _troll_young_hair(back: bool) -> void:
	var top := cy - ry
	if back:
		_hair_capsule(Vector2(cx - rx * 0.12, top - 2.0), Vector2(cx - rx * 0.58, eye_y + 6.0), 1.65)
		_hair_capsule(Vector2(cx + rx * 0.08, top - 5.0), Vector2(cx + rx * 0.36, eye_y - 1.0), 1.4)
	else:
		_hair_capsule(Vector2(cx - rx * 0.20, top - 1.0), Vector2(cx - rx * 0.70, mouth_y - 2.0), 1.45)
		_hair_capsule(Vector2(cx + rx * 0.06, top - 4.0), Vector2(cx - rx * 0.08, eye_y - 5.0), 1.2)

func _draw_ear(near: bool) -> void:
	var lost_id := "ear_r" if near else "ear_l"
	var dir := -1.0 if near else 1.0
	if _lost(lost_id):
		_blob(int(cx + dir * rx), int(eye_y), 2, FigurePainter.BLOOD)
		return
	var sc := 1.0 if near else 0.78
	match ear_k:
		"fan":
			var fan_sc := sc
			if stage == "young":
				fan_sc *= 1.12
			elif stage == "elder":
				fan_sc *= 0.84
			if sex_f:
				fan_sc *= 0.90
			_fan_ear(dir, near, fan_sc)
		"high":
			_leaf_ear(dir, near, 15.0 * sc, 9.0 * sc, 1.7 * sc)
		"moon":
			_leaf_ear(dir, near, 13.0 * sc, 6.0 * sc, 2.3 * sc)
		"dark":
			_leaf_ear(dir, near, 9.0 * sc, 5.0 * sc, 2.4 * sc)
		"point":
			_swept_ear(dir, near, 3.1 * sc, Vector2(dir * 4.0, -6.0), Vector2(dir * 8.0, -13.0))
		"small":
			_swept_ear(dir, near, 2.15 * sc, Vector2(dir * 1.0, -2.0), Vector2(dir * 1.2, -5.0))
		"heavy":
			_swept_ear(dir, near, 3.5 * sc, Vector2(dir * 2.0, -1.0), Vector2(dir * 3.0, -5.0))
		_:
			_swept_ear(dir, near, 2.7 * sc, Vector2(dir * 1.0, -4.0), Vector2(dir * 0.4, -8.0))

func _braid_strands(a: Vector2, b: Vector2) -> void:
	var steps := 36
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		var p := a.lerp(b, t)
		var x := int(round(p.x))
		var y := int(round(p.y))
		_px(x - 1, y, hair_ramp[0])
		_px(x, y, hair_ramp[4] if posmod(i, 4) == 0 else hair_ramp[2])
		_px(x + 1, y, hair_ramp[1])

func _leaf_ear(dir: float, near: bool, length: float, rise: float, thick: float) -> void:
	var root := 0.76
	if ear_k == "moon":
		root = 0.96
	elif ear_k == "dark":
		root = 0.90
	var base := Vector2(cx + dir * (rx * root), eye_y + (0.4 if ear_k == "dark" else 2.0))
	var mid := base + Vector2(dir * length * 0.55, -rise * 0.40)
	var tip := base + Vector2(dir * length, -rise)
	tip.x = clampf(tip.x, 1.0, 94.0)
	tip.y = clampf(tip.y, 2.0, 92.0)
	mid.x = clampf(mid.x, 1.0, 94.0)
	mid.y = clampf(mid.y, 2.0, 92.0)
	_ear_capsule(base, mid, thick, near, false)
	_ear_capsule(mid, tip, maxf(1.15, thick * 0.58), near, false)
	var inner_a := base + Vector2(dir * 1.6, 1.7)
	var inner_b := mid + Vector2(dir * 0.6, 1.0)
	var inner_rad := 1.05 if ear_k == "high" else 1.55
	_ear_capsule(inner_a, inner_b, inner_rad, near, true)
	_px(int(round(tip.x)), int(round(tip.y)), skin_ramp[4])

func _fan_ear(dir: float, near: bool, sc: float) -> void:
	var origin := Vector2(cx + dir * (rx - 0.5), eye_y + 1.0)
	var tip := Vector2(cx + dir * (rx + 22.0 * sc), eye_y - 18.0 * sc)
	var low := Vector2(cx + dir * (rx + 18.0 * sc), eye_y + 14.0 * sc)
	var hi := Vector2(cx + dir * (rx + 7.0 * sc), eye_y - 9.0 * sc)
	_tri(origin, hi, tip, near)
	_tri(origin, low, tip, near)
	_px(int(tip.x), int(tip.y), skin_ramp[4])
	_px(int(low.x), int(low.y), skin_ramp[3])
	var ix := int(origin.x + dir * 8.0 * sc)
	var iy := int(eye_y)
	_px(ix, iy, skin_ramp[0])
	_px(ix + int(dir * 2.0), iy - 3, skin_ramp[0])
	_px(ix + int(dir * 3.0), iy + 3, skin_ramp[1])

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
			var band := 3 if p.x < cx else 2
			if w0 > 0.58:
				band = 0
			elif w0 < 0.20:
				band = 4
			_px(x, y, skin_ramp[band])

func _swept_ear(dir: float, near: bool, rad: float, mid_off: Vector2, tip_off: Vector2) -> void:
	var base_x: float = rx * 0.70
	var base_y: float = eye_y + 3.0
	if ear_k == "high" or ear_k == "moon" or ear_k == "dark":
		base_x = rx + 2.2
		base_y = eye_y + 1.0
	var base := Vector2(cx + dir * base_x, base_y)
	var mid := base + mid_off
	var tip := base + tip_off
	tip.x = clampf(tip.x, 2.0, 93.0)
	tip.y = clampf(tip.y, 3.0, 90.0)
	mid.x = clampf(mid.x, 2.0, 93.0)
	mid.y = clampf(mid.y, 3.0, 90.0)
	var elf := ear_k == "high" or ear_k == "moon" or ear_k == "dark"
	_ear_capsule(base, mid, rad, near, false)
	_ear_capsule(mid, tip, maxf(2.1 if elf else 1.25, rad * (0.70 if elf else 0.48)), near, false)
	if elf:
		var tx := int(tip.x)
		var ty := int(tip.y)
		_px(tx, ty - 1, skin_ramp[4])
		_px(tx + int(dir), ty - 2, skin_ramp[3])
	else:
		var tip_rx: float = maxf(1.15, rad * 0.40)
		var tip_ry: float = maxf(1.7, rad * 0.72)
		_ear_disc(tip, tip_rx, tip_ry, near, false)
		_ear_capsule(base + Vector2(-dir * 0.3, 1.0), mid, maxf(0.8, rad * 0.32), near, true)

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
				var shade := skin_ramp[2] if ear_k == "high" else skin_ramp[0]
				_px(x, y, shade)
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
	if race == "troll":
		hw = 4 if not sex_f else 3
		hh = 2
		if stage == "young":
			hw = 3
			hh = 2
	elif race == "dark_elf":
		hw = 4
		hh = 2
		if stage == "young":
			hw = 5
			hh = 2
		elif stage == "elder":
			hw = 3
			hh = 1
		elif sex_f:
			hw = 4
			hh = 2
	elif race == "moon_elf":
		hw = 3
		hh = 2
		if stage == "young":
			hw = 5
			hh = 2
		elif stage == "elder":
			hw = 3
			hh = 1
		elif not sex_f and stage == "adult":
			hw = 3
			hh = 2
		elif sex_f:
			hw = 4
			hh = 2
	elif race == "goblin":
		hw = 3
		hh = 2
		if stage == "young":
			hw = 4
			hh = 3
		elif stage == "elder":
			hw = 2
			hh = 1
	if not eyes_open:
		for x in range(-hw, hw + 1):
			var arch := 1 if absi(x) >= hw - 1 else 0
			_px(x0 + x, y0 + arch, skin_ramp[0])
			_px(x0 + x, y0 + arch - 1, skin_ramp[1])
		_brow(x0, y0, hw, hh, near)
		return
	var lid := _op(skin.darkened(0.48))
	if race == "moon_elf":
		lid = Color(0.42, 0.48, 0.62, 1.0) if stage == "elder" else Color(0.55, 0.60, 0.74, 1.0)
	elif race == "dark_elf":
		lid = Color(0.45, 0.40, 0.55, 1.0)
	var iris := EYES.get(race, Color("#4a3422")) as Color
	if race == "moon_elf":
		if stage == "elder" and not sex_f:
			iris = Color(0.38, 0.36, 0.52, 1.0)
		elif stage == "elder":
			iris = Color(0.48, 0.40, 0.62, 1.0)
		elif sex_f:
			iris = Color(0.52, 0.34, 0.74, 1.0)
		elif stage == "adult":
			iris = Color(0.36, 0.28, 0.64, 1.0)
		else:
			iris = Color(0.40, 0.30, 0.70, 1.0)
	elif race == "dark_elf" and stage == "elder":
		iris = Color(0.55, 0.12, 0.16, 1.0)
	elif race == "dark_elf" and sex_f:
		iris = Color(0.78, 0.22, 0.30, 1.0)
	elif race == "human" and stage == "elder":
		iris = Color(0.10, 0.06, 0.05, 1.0)
	var elf_eye := race == "moon_elf" or race == "dark_elf"
	for y in range(-hh - 1, hh + 2):
		for x in range(-hw - 1, hw + 2):
			var nx := float(x) / float(hw + 1)
			var ny := float(y) / float(hh + 1)
			if nx * nx + ny * ny > 1.0:
				continue
			if elf_eye:
				continue
			if y <= -hh:
				_px(x0 + x, y0 + y, lid)
			elif nx * nx + ny * ny > 0.82:
				_px(x0 + x, y0 + y, _op(SCLERA.darkened(0.10)))
			else:
				_px(x0 + x, y0 + y, SCLERA)
	var ix := x0 + (0 if near else 1)
	var iy := y0
	if race == "moon_elf" or race == "dark_elf":
		var rim := 2 if race == "moon_elf" and hw >= 4 else 1
		for ex in range(-(hw - 1), hw):
			_px(x0 + ex, y0 - hh, lid)
		for exb in range(-hw, hw + 1):
			if race == "dark_elf":
				var dshade: float = 0.06
				if exb > 0:
					dshade = 0.20
				_px(x0 + exb, y0, _op(iris.darkened(dshade)))
			elif absi(exb) > hw - rim:
				_px(x0 + exb, y0, SCLERA)
			else:
				var mshade: float = 0.04
				if exb > 0:
					mshade = 0.24
				_px(x0 + exb, y0, _op(iris.darkened(mshade)))
		if hh > 1:
			for exc in range(-(hw - 2), hw - 1):
				if race == "dark_elf":
					_px(x0 + exc, y0 + 1, _op(iris.darkened(0.30)))
				elif absi(exc) > hw - rim - 1:
					_px(x0 + exc, y0 + 1, _op(SCLERA.darkened(0.08)))
				else:
					_px(x0 + exc, y0 + 1, _op(iris.darkened(0.22)))
		_px(ix, iy, PUPIL)
		_px(ix - 1, y0, Color(1, 0.995, 0.97, 1))
	else:
		var iris_rad := 1
		for dy2 in range(-iris_rad, iris_rad + 1):
			for dx2 in range(-iris_rad, iris_rad + 1):
				var shade2: float = 0.0
				if dx2 > 0 or dy2 > 0:
					shade2 = 0.22
				_px(ix + dx2, iy + dy2, _op(iris.darkened(shade2)))
		_px(ix, iy, PUPIL)
		if race == "human" and stage == "elder":
			_px(ix, iy + 1, PUPIL)
		_px(ix - 1, iy - 1, Color(1, 0.995, 0.97, 1))
	_brow(x0, y0, hw, hh, near)
	if race == "moon_elf" and sex_f:
		var lash := Color(0.34, 0.40, 0.58, 1.0)
		_px(x0 - hw, y0 - hh - 1, lash)
		_px(x0 + hw, y0 - hh - 1, lash)
		if stage != "elder":
			_px(x0 - hw + 1, y0 - hh - 1, lash)
			_px(x0 + hw - 1, y0 - hh - 1, lash)
	if race == "goblin" and sex_f:
		_px(x0 - hw, y0 - hh - 1, OUTLINE)
		_px(x0 - hw + 1, y0 - hh - 2, OUTLINE)
		_px(x0 + hw - 1, y0 - hh - 2, OUTLINE)
		_px(x0 + hw, y0 - hh - 1, OUTLINE)

func _brow(x0: int, y0: int, hw: int, hh: int, near: bool) -> void:
	var thick := 1
	if race == "troll":
		thick = 2
		if not sex_f and stage != "young":
			thick = 3
	elif not sex_f and brow_k >= 1.45:
		thick = 2
	var brow_col := hair_ramp[2]
	if race == "troll":
		brow_col = _op(skin.darkened(0.42))
	elif race == "moon_elf":
		brow_col = Color(0.40, 0.48, 0.64, 1.0)
		if stage == "elder":
			brow_col = Color(0.62, 0.66, 0.74, 1.0)
		elif not sex_f and stage == "adult":
			brow_col = Color(0.30, 0.36, 0.52, 1.0)
		elif sex_f:
			brow_col = Color(0.48, 0.42, 0.62, 1.0)
	elif race == "dark_elf":
		brow_col = Color(0.18, 0.12, 0.22, 1.0)
		if stage == "elder":
			brow_col = Color(0.32, 0.26, 0.38, 1.0)
	elif hair.get_luminance() > 0.72:
		brow_col = hair_ramp[1]
	var by := y0 - hh - thick - (2 if race == "troll" else 0)
	if race == "moon_elf" or race == "dark_elf":
		by -= 2
	if race == "troll":
		by += 3
	elif race == "dark_elf" and stage == "young":
		by -= 1
	elif race == "dark_elf" and sex_f:
		by -= 1
	elif race == "dark_elf" and stage == "elder":
		by -= 1
	elif race == "moon_elf" and sex_f:
		by -= 1
	elif race == "moon_elf" and stage == "elder":
		by -= 1
	elif race == "moon_elf" and not sex_f and stage == "adult":
		by += 1
	var toward := 1 if near else -1
	var x_lo := -hw - 1
	var x_hi := hw + 2
	if race == "moon_elf" or race == "dark_elf":
		x_lo = -hw
		x_hi = hw + 1
	for t in thick:
		for x in range(x_lo, x_hi):
			var drop := 0
			if not sex_f and brow_k >= 1.3 and x * toward > 1:
				drop = 1
			if race == "dark_elf" and not sex_f and stage == "adult" and x * toward > 0:
				drop = 1
			if race == "dark_elf" and not sex_f and stage == "elder" and x * toward > 0:
				drop = 1
			if race == "dark_elf" and stage == "young" and not sex_f:
				drop = 0
			if race == "moon_elf" and not sex_f and stage == "adult" and x * toward > 0:
				drop = 1
			if race == "moon_elf" and (sex_f or stage == "young"):
				drop = 0
			var arch := 0
			if absi(x) >= hw - 1:
				arch = -1
			if race == "dark_elf" and sex_f and absi(x) >= maxi(1, hw - 2):
				arch = -2
			if race == "dark_elf" and stage == "young" and not sex_f:
				arch = 0
			if race == "moon_elf" and sex_f and absi(x) >= maxi(1, hw - 2):
				arch = -2 if stage != "elder" else -1
			if race == "moon_elf" and not sex_f and stage == "young" and absi(x) < hw:
				arch = 0
			var col := brow_col
			if race == "troll":
				if t == 0:
					col = skin_ramp[3]
				elif t == thick - 1:
					col = skin_ramp[2]
				else:
					col = skin_ramp[3]
			_px(x0 + x, by + t + drop + arch, col)
			if t == 0 and (race == "moon_elf" or race == "dark_elf") and not sex_f and stage == "adult" and x * toward > 1:
				_px(x0 + x, by + 1 + drop + arch, col)
	if race == "troll":
		for x in range(-hw - 1, hw + 2):
			_px(x0 + x, by - 4, skin_ramp[4])
			_px(x0 + x, by - 3, skin_ramp[3])
			_px(x0 + x, by - 2, skin_ramp[4])
			_px(x0 + x, by - 1, skin_ramp[4])

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
			if race == "moon_elf":
				for ni in range(5):
					_px(x - 2, y - ni, skin_ramp[0])
					_px(x + 2, y - ni, skin_ramp[1])
				_px(x, y + 1, skin_ramp[4])
				_px(x + 1, y + 1, skin_ramp[0])
				_px(x - 2, y + 1, skin_ramp[0])
				_px(x + 2, y + 1, skin_ramp[0])
				_px(x - 1, y + 2, skin_ramp[1])
				_px(x, y + 2, skin_ramp[4])
				_px(x + 1, y + 2, skin_ramp[0])
			elif race == "dark_elf":
				_px(x - 2, y + 1, skin_ramp[0])
				_px(x + 2, y + 1, skin_ramp[0])
				_px(x - 1, y + 2, skin_ramp[1])
				_px(x, y + 2, skin_ramp[0])
				_px(x + 1, y + 2, skin_ramp[0])
		"hook":
			for i in range(7):
				_px(x - 1, y - 10 + i, skin_ramp[4])
				_px(x, y - 10 + i, skin_ramp[2])
				_px(x + 1, y - 10 + i, skin_ramp[1])
			_disc_ramp(x + 2, y - 1, 5, 4, skin_ramp)
			_px(x + 1, y - 2, skin_ramp[4])
			_px(x + 2, y - 3, skin_ramp[4])
			_px(x, y + 2, skin_ramp[0])
			_px(x + 1, y + 2, skin_ramp[0])
			_px(x + 4, y + 2, skin_ramp[0])
			_px(x + 5, y + 1, skin_ramp[0])
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
		hw = 4 if stage == "young" else 6
		if stage == "elder":
			hw = 5
	elif race == "goblin":
		hw = 4 if stage == "young" else 3
	elif race == "dark_elf":
		hw = 3
		if stage == "young":
			hw = 5
		elif stage == "elder" and not sex_f:
			hw = 2
		elif sex_f and stage == "elder":
			hw = 3
		elif not sex_f and stage == "adult":
			hw = 3
	elif race == "moon_elf":
		hw = 3
		if stage == "young":
			hw = 4
		elif stage == "elder" and not sex_f:
			hw = 2
		elif sex_f and stage == "elder":
			hw = 3
	elif race.ends_with("elf"):
		hw = 3
	if sex_f:
		hw = maxi(2, hw - 1)
	if race == "moon_elf" and sex_f:
		hw += 1 if stage == "elder" else 2
	var lip_dark := _op(skin.darkened(0.34).lerp(Color("#4a1822"), 0.28))
	var lip := _op(skin.lerp(Color("#a4545c"), 0.42 if sex_f else 0.18))
	if race == "moon_elf":
		if stage == "elder" and not sex_f:
			lip_dark = Color(0.46, 0.52, 0.64, 1.0)
			lip = Color(0.46, 0.52, 0.64, 1.0)
		elif sex_f and stage == "elder":
			lip_dark = Color(0.48, 0.30, 0.46, 1.0)
			lip = Color(0.70, 0.50, 0.64, 1.0)
		elif sex_f:
			lip_dark = Color(0.40, 0.22, 0.40, 1.0)
			lip = Color(0.88, 0.64, 0.76, 1.0)
		elif stage == "young":
			lip_dark = Color(0.58, 0.40, 0.56, 1.0)
			lip = Color(0.78, 0.58, 0.70, 1.0)
		else:
			lip_dark = Color(0.44, 0.32, 0.50, 1.0)
			lip = Color(0.44, 0.32, 0.50, 1.0)
	elif race == "dark_elf":
		lip_dark = Color(0.46, 0.14, 0.22, 1.0)
		lip = Color(0.68, 0.28, 0.36, 1.0)
		if stage == "elder" and not sex_f:
			lip_dark = _op(skin.darkened(0.28))
			lip = _op(skin.darkened(0.12))
	var thin_elder := race == "dark_elf" and stage == "elder" and not sex_f
	var thin_moon := race == "moon_elf" and not sex_f and stage != "young"
	for i in range(-hw, hw + 1):
		var dy := _mouth_bend(i, hw)
		_px(x + i, y + dy, lip_dark)
	if not thin_elder and not thin_moon:
		for i in range(-(hw - 1), hw):
			var dy2 := _mouth_bend(i, hw)
			_px(x + i, y + 1 + dy2, lip)
	if sex_f and not thin_elder and not (race == "moon_elf" and stage == "elder"):
		for i in range(-(hw - 2), hw - 1):
			_px(x + i, y + 2 + _mouth_bend(i, hw), _op(lip.lightened(0.08)))
	_px(x - hw, y + 1, skin_ramp[1])
	_px(x + hw, y + 1, skin_ramp[0])
	if race == "goblin":
		_goblin_nose()

func _mouth_bend(i: int, hw: int) -> int:
	var t := float(absi(i)) / float(maxi(1, hw))
	var steps := int(round(t * 2.0))
	if race == "dark_elf":
		if stage == "young":
			return -steps
		if sex_f and stage == "elder":
			return -int(round(t))
		if sex_f:
			return -steps
		if stage == "adult":
			return steps
		return 0
	if race == "moon_elf":
		if stage == "young":
			if absi(i) >= hw - 1:
				return -2
			return -steps
		if sex_f and stage == "elder":
			return -int(round(t))
		if stage == "elder":
			return int(round(t))
		return 0
	if race == "goblin":
		if stage == "young":
			return -steps
		if stage == "elder":
			return steps
		if sex_f:
			return -int(round(t))
		if i > 1:
			return 1
		return 0
	if race == "troll":
		if stage == "young":
			return -int(round(t))
		if stage == "elder":
			return steps
		if sex_f:
			return 0
		return int(round(t))
	return 0

func _goblin_nose() -> void:
	var x := int(round(cx + 2.0))
	var y := int(round(mouth_y)) - 4
	for i in range(6):
		_px(x - 1, y - 6 + i, skin_ramp[4])
		_px(x, y - 6 + i, skin_ramp[2])
		_px(x + 1, y - 6 + i, skin_ramp[1])
	for dy in range(-2, 3):
		for dx in range(-1, 5):
			var edge := dx == -1 or dx == 4 or dy == -2 or dy == 2
			if edge:
				_px(x + dx, y + dy, skin_ramp[0])
			elif dx < 2:
				_px(x + dx, y + dy, skin_ramp[4])
			else:
				_px(x + dx, y + dy, skin_ramp[2])
	_px(x, y + 1, Color(0.08, 0.12, 0.06, 1.0))
	_px(x + 3, y + 1, Color(0.08, 0.12, 0.06, 1.0))
	_px(x + 1, y - 1, skin_ramp[4])
	_px(x + 1, y, Color(0.95, 0.98, 0.82, 1.0))

func _draw_wrinkles() -> void:
	if stage != "elder":
		return
	var wr := _op(skin.darkened(0.18))
	if race == "dark_elf":
		wr = Color(0.78, 0.76, 0.84, 1.0)
	elif race == "moon_elf":
		wr = _op(skin.lerp(Color(0.26, 0.32, 0.48), 0.72))
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

func _stage_marks() -> void:
	if race == "high_elf" and not sex_f and stage == "adult":
		var col := hair_ramp[1]
		var ex := int(cx - rx * 0.72)
		for i in range(7):
			_px(ex, int(eye_y) + 1 + i, col)
			_px(ex + 1, int(eye_y) + 2 + i, hair_ramp[3])
		var line := _op(skin.darkened(0.22))
		_px(int(eye_near.x) - 4, int(eye_near.y) + 2, line)
		_px(int(eye_near.x) - 5, int(eye_near.y) + 3, line)
		_px(int(eye_far.x) + 3, int(eye_far.y) + 2, line)
	elif race == "dark_elf" and not sex_f and stage == "adult":
		var col2 := hair_ramp[2]
		var sx := int(cx + rx * 0.78)
		for i in range(8):
			_px(sx, int(eye_y) + i, col2)
			_px(sx + 1, int(eye_y) + 1 + i, hair_ramp[4])
		var line2 := _op(skin.darkened(0.20))
		_px(int(cx) - 6, int(nose_y) + 2, line2)
		_px(int(cx) - 7, int(nose_y) + 3, line2)
	if race == "dark_elf" and stage == "elder":
		var aged := Color(0.78, 0.76, 0.84, 1.0)
		var hollow := Color(0.16, 0.14, 0.22, 1.0)
		for i in range(9):
			_px(int(cx) - 5 + i, int(eye_y) - 10, aged)
			_px(int(cx) - 4 + i, int(eye_y) - 7, aged)
		for i in range(4):
			_px(int(eye_near.x) - 4 - i, int(eye_near.y) + i, aged)
			_px(int(eye_far.x) + 4 + i, int(eye_far.y) + i, aged)
		for dy in range(3):
			for dx in range(4):
				_px(int(eye_near.x) - 7 + dx, int(eye_near.y) + 5 + dy, hollow)
				_px(int(eye_far.x) + 3 + dx, int(eye_far.y) + 5 + dy, hollow)
		var nxl := int(round(cx))
		var nyl := int(nose_y)
		for i in range(5):
			_px(nxl - 3 - i, nyl + 2 + i, aged)
			_px(nxl + 3 + i, nyl + 2 + i, aged)
		for i in range(-3, 4):
			_px(int(cx) + i, int(mouth_y) + 3, aged)
		if sex_f:
			for i in range(-2, 3):
				_px(int(cx) + i, int(mouth_y) + 5, aged)
	elif race == "dark_elf" and stage == "young":
		var apple := skin_ramp[4]
		var midc := skin_ramp[3]
		var ox := -2 if sex_f else -1
		for dy in range(2):
			for dx in range(3):
				_px(int(eye_near.x) + ox + dx, int(eye_near.y) + 4 + dy, apple if dy == 0 else midc)
				_px(int(eye_far.x) - ox - dx, int(eye_far.y) + 4 + dy, apple if dy == 0 else midc)
	elif race == "moon_elf" and stage == "elder":
		var line_m := _op(skin.lerp(Color(0.24, 0.30, 0.46), 0.75))
		for i in range(8):
			_px(int(cx) - 4 + i, int(eye_y) - 11, line_m)
			_px(int(cx) - 3 + i, int(eye_y) - 8, line_m)
		if not sex_f:
			_px(int(eye_near.x) - 3, int(eye_near.y) + 2, line_m)
			_px(int(eye_far.x) + 3, int(eye_far.y) + 2, line_m)
	elif race == "goblin" and stage == "adult" and not sex_f:
		var scar := _op(skin.darkened(0.34))
		_px(int(eye_far.x) + 3, int(eye_far.y) - 2, scar)
		_px(int(eye_far.x) + 4, int(eye_far.y) - 1, scar)
		_px(int(eye_far.x) + 5, int(eye_far.y), scar)
	elif race == "goblin" and stage == "elder":
		var crease := _op(skin.darkened(0.26))
		for i in range(-4, 5):
			_px(int(cx) + i, int(mouth_y) + 4, crease)
	elif race == "troll" and stage == "elder":
		var fold := _op(skin.darkened(0.38))
		for i in range(-5, 6):
			_px(int(cx) + 1 + i, int(mouth_y) - 3, fold)
	if race != "troll" or stage == "young":
		return
	var wart := _op(skin.darkened(0.32))
	var wart_hi := skin_ramp[3]
	_px(int(cx) + 8, int(nose_y) - 1, wart)
	_px(int(cx) + 9, int(nose_y) - 1, wart)
	_px(int(cx) + 8, int(nose_y), wart)
	_px(int(cx) + 9, int(nose_y), wart_hi)
	if not sex_f:
		_px(int(cx) - 8, int(mouth_y) - 4, wart)
		_px(int(cx) - 7, int(mouth_y) - 4, wart)
		_px(int(cx) - 8, int(mouth_y) - 3, wart)
		_px(int(cx) - 7, int(mouth_y) - 3, wart_hi)
	if stage == "elder":
		_px(int(cx) + 4, int(chin_y) - 5, wart)
		_px(int(cx) + 5, int(chin_y) - 5, wart)
		_px(int(cx) + 4, int(chin_y) - 4, wart_hi)
		_px(int(cx) - 10, int(eye_y) + 5, wart)
		_px(int(cx) - 9, int(eye_y) + 5, wart)
		if sex_f:
			_px(int(cx) + 2, int(mouth_y) - 5, wart)
			_px(int(cx) + 3, int(mouth_y) - 5, wart_hi)

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
	var u := float(x - int(cx)) / maxf(8.0, rx * 0.55)
	var v := float(y - int(mouth_y)) / 18.0
	var lit := clampf(0.80 - u * 0.46 - v * 0.50, 0.0, 1.0)
	var band := _shade_band(lit, x, y)
	if race == "dwarf":
		if v < 0.28:
			band = 4
		elif v < 0.58:
			band = 2
		else:
			band = 1
		if posmod(x * 2 + y, 7) == 0:
			band = mini(4, band + 1)
		elif posmod(x + y * 3, 11) == 0:
			band = maxi(0, band - 1)
	elif posmod(x, 4) == 0:
		band = maxi(0, band - 1)
	return beard_ramp[band]

func _draw_beard() -> void:
	if race == "moon_elf":
		return
	if not beard_on or _lost("head"):
		return
	var s := _beard_scale()
	var y0 := int(mouth_y) + (5 if race == "dwarf" else (3 if sex_f else 2))
	var xc := int(round(cx + 1.0))
	var chin := int(chin_y)
	var half := rx * 0.60 * s
	if race == "dwarf":
		half = rx * (0.58 if stage == "young" else 0.66)
	elif race.ends_with("elf"):
		half = rx * 0.46 * s
	var hang := 18 if race == "dwarf" else 12
	match beard_i:
		1:
			var ghalf: float = maxf(8.0, half * (0.85 if race == "dwarf" else 1.25))
			var gend := chin + (6 if race == "dwarf" else 8)
			_beard_fill(xc, int(mouth_y) + 2, gend, ghalf, "goatee")
			_moustache(xc, int(mouth_y), int(maxf(8.0, ghalf * 0.62)))
		2:
			_beard_fill(xc, y0, chin + hang, half, "round")
			_moustache(xc, int(mouth_y), int(half * 0.55))
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
			var dy1 := chin + (16 if race == "dwarf" else 8)
			_beard_fill(xc, y0, dy1, half, "full" if race == "dwarf" else "round")
			_moustache(xc, int(mouth_y), int(maxf(6.0, half * (0.62 if race == "dwarf" else 0.40))))

func _beard_fill(xc: int, y0: int, y1: int, half: float, kind: String) -> void:
	var span := maxi(1, y1 - y0)
	for y in range(y0, mini(y1, SIZE)):
		var t := float(y - y0) / float(span)
		var w := half
		if kind == "point" or kind == "fork":
			w = lerpf(half, 1.5, t)
		elif kind == "goatee":
			w = lerpf(half, half * 0.86, t)
		elif kind == "short":
			w = lerpf(half, half * 0.74, t)
		elif kind == "full":
			w = lerpf(half * 0.72, half, minf(t * 1.3, 1.0))
			if t > 0.50:
				w = lerpf(half, half * 0.58, (t - 0.50) / 0.50)
		else:
			w = lerpf(half * 0.82, half, minf(t * 1.3, 1.0))
			if t > 0.70:
				w = lerpf(w, half * 0.70, (t - 0.70) / 0.30)
		var reach := maxi(2, int(round(w)))
		for x in range(xc - reach, xc + reach + 1):
			if kind == "fork" and t > 0.42 and absi(x - xc) <= 1 + int((t - 0.42) * 5.0):
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
	var length := 8.0 if race == "orc" else 10.0
	if stage == "young":
		length *= 0.40 if race == "troll" else 0.45
	elif stage == "elder":
		length *= 1.35
	if sex_f:
		length *= 0.48 if race == "troll" else 0.65
	if stage == "adult" and not sex_f and race == "troll":
		length *= 1.10
	var y := int(mouth_y)
	var spread := 6 if race == "troll" else 5
	var xc := int(round(cx + 1.0))
	_tusk(xc - spread, y, -0.90, length)
	_tusk(xc + spread, y, 0.82, length * 0.92)

func _tusk(x0: int, y0: int, dir: float, length: float) -> void:
	var steps := maxi(3, int(length))
	var thick := 2
	if race == "troll" and not sex_f and stage != "young":
		thick = 3
	var side := 1 if dir > 0.0 else -1
	var gum := Color(0.32, 0.12, 0.14, 1.0)
	_px(x0, y0 - 1, gum)
	_px(x0 + side, y0 - 1, gum)
	_px(x0 - side, y0, gum)
	for i in range(steps):
		var along := float(i)
		var drift := 0.0
		if along > 1.0:
			drift = dir * (along - 1.0) * 0.36
		var x := x0 + int(round(drift))
		var y := y0 + i
		_px(x - side, y, IVORY_DARK)
		_px(x + side * thick, y, IVORY_DARK)
		for t in range(thick):
			var col := IVORY
			if i == 0:
				col = IVORY.lerp(gum, 0.50)
			elif t == 0:
				col = IVORY.darkened(0.10)
			_px(x + side * t, y, col)
		if i == steps - 1:
			_px(x + side, y + 1, IVORY)

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
