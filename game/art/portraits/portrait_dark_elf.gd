extends RefCounted
## Dark elf 96px bust painter. Faces and overlapping locks use contiguous shaded planes.
## Equipment and injury support remain local to this race's paint(spec) API.

const RACE := "dark_elf"
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
	"moon_elf": {"rx": 16.2, "ry": 23.0, "cy": 37.0, "jaw": 0.84, "neck": 6.2, "sh": 29.0, "brow": 0.72, "eye": 1.05, "nose": "fine", "ear": "moon"},
	"dark_elf": {"rx": 16.0, "ry": 22.6, "cy": 37.5, "jaw": 0.86, "neck": 6.0, "sh": 29.0, "brow": 0.78, "eye": 1.04, "nose": "fine", "ear": "dark"},
	"orc": {"rx": 20.0, "ry": 21.0, "cy": 39.0, "jaw": 1.08, "neck": 9.0, "sh": 36.0, "brow": 1.5, "eye": 0.96, "nose": "flat", "ear": "point"},
	"goblin": {"rx": 14.0, "ry": 16.0, "cy": 43.0, "jaw": 0.90, "neck": 5.6, "sh": 26.0, "brow": 0.9, "eye": 1.28, "nose": "hook", "ear": "fan"},
	"troll": {"rx": 25.0, "ry": 21.0, "cy": 40.0, "jaw": 1.48, "neck": 12.0, "sh": 42.0, "brow": 2.15, "eye": 1.10, "nose": "flat", "ear": "heavy"},
}

const ARMOR := ["cuirass", "mail", "scale", "lamellar", "scrap", "byrnie", "plate", "brigandine", "hauberk", "breastplate"]

static func paint(spec: Dictionary) -> Image:
	return load("res://art/portraits/portrait_dark_elf.gd").new()._render(spec)

var cv: PixelCanvas
var spec: Dictionary = {}
var race := RACE
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
	_dark_setup()
	if _lost("head"):
		_dark_torso()
		_blob(int(cx), int(torso_y), 7, FigurePainter.BLOOD)
		_outline()
		return cv.to_image()
	if helm_kind == "closed":
		_dark_torso()
		_dark_neck()
		_dark_collar()
		_draw_closed_helm()
		_draw_lost_blood()
		_outline()
		return cv.to_image()
	if helm_kind == "coif":
		_draw_hood()
	else:
		_dark_hair_volume(false)
	_dark_torso()
	_dark_neck()
	_dark_collar()
	_dark_ear(-1)
	_dark_ear(1)
	_dark_face()
	_dark_age()
	_dark_eye(true)
	_dark_eye(false)
	_dark_nose()
	_dark_mouth()
	if helm_kind != "coif":
		_dark_hair_volume(true)
	_dark_beard_volume()
	_draw_open_helm()
	_draw_lost_blood()
	_outline()
	return cv.to_image()

func _dark_setup() -> void:
	# The same anatomical scale as the accepted human sheet, with a longer elf taper.
	rx = (17.0 if sex_f else (18.1 if stage == "adult" else 17.5))
	rx += float(int(seed / 7.0) % 3 - 1) * 0.25
	cy = 40.0
	ry = 23.0
	chin_y = (65.0 if stage == "elder" else 64.0) if sex_f else 65.0
	eye_y = 39.0 if stage == "young" else 40.0
	mouth_y = (54.0 if sex_f else 55.0) + (1.0 if stage == "elder" else 0.0)
	nose_y = mouth_y - 5.0
	eye_near = Vector2(cx - 7.0, eye_y)
	eye_far = Vector2(cx + 7.0, eye_y + (0.0 if stage == "young" else 1.0))
	neck_w = 6.0 if sex_f else 7.0
	sh_w = 32.0 if sex_f else 35.0
	torso_y = 72.0 + (1.0 if stage == "elder" else 0.0)
	# Violet stays in the shadows; the lit planes remain readable on dark skin.
	skin_ramp = [skin.lerp(Color("#241a31"), 0.72), skin.darkened(0.28), skin,
		skin.lightened(0.18).lerp(Color("#a994b1"), 0.08),
		skin.lightened(0.35).lerp(Color("#d6bbce"), 0.06)]
	hair_ramp = _dark_fiber_ramp(hair)
	beard_ramp = _dark_fiber_ramp(beard_col)

func _dark_fiber_ramp(base: Color) -> Array[Color]:
	return [base.darkened(0.64).lerp(Color("#353044"), 0.22),
		base.darkened(0.40).lerp(Color("#77718b"), 0.12), base.darkened(0.18),
		base.darkened(0.02), base.lightened(0.10).lerp(Color("#f3e9e5"), 0.08)]

func _dark_tone(ramp: Array[Color], light: float) -> Color:
	# Half steps soften a plane's edge without checkerboards or alternating pixels.
	var step := clampf(floorf(light * 24.0) / 6.0, 0.0, 4.0)
	var lo := int(step)
	return ramp[lo].lerp(ramp[mini(4, lo + 1)], step - float(lo))

func _dark_soft(x: float, y: float, ax: float, ay: float, sx: float, sy: float) -> float:
	var d := Vector2((x - ax) / sx, (y - ay) / sy).length_squared()
	return pow(maxf(0.0, 1.0 - d), 2.0)

func _dark_line(a: Vector2, b: Vector2, col: Color, rad: float = 0.55) -> void:
	var lo := a.min(b) - Vector2.ONE * rad
	var hi := a.max(b) + Vector2.ONE * rad
	for y in range(maxi(0, int(floor(lo.y))), mini(SIZE, int(ceil(hi.y)) + 1)):
		for x in range(maxi(0, int(floor(lo.x))), mini(SIZE, int(ceil(hi.x)) + 1)):
			var p := Vector2(x, y)
			if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= rad * rad:
				_px(x, y, col)

func _dark_poly(coords: Array, ramp: Array[Color], bias: float = 0.0) -> void:
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
				var light := 0.70 - (float(x) - 30.0) * 0.005 - (float(y) - 72.0) * 0.003 + bias
				_px(x, y, _dark_tone(ramp, light))

func _dark_half(y: float) -> float:
	var cheek := (0.88 if sex_f else 0.86) if stage == "young" else (0.75 if stage == "elder" else 0.84)
	var jaw_width := (0.70 if stage == "elder" else 0.64) if sex_f else (0.85 if stage == "adult" else 0.75)
	var profile := [Vector2(17, 0.31), Vector2(24, 0.78), Vector2(34, 0.97),
		Vector2(43, 1.0), Vector2(48, 0.94), Vector2(53, cheek),
		Vector2(58, jaw_width), Vector2(chin_y - 2, (0.38 if stage == "elder" else 0.34) if sex_f else 0.45), Vector2(chin_y + 1, 0.13)]
	for i in range(1, profile.size()):
		var a: Vector2 = profile[i - 1]
		var b: Vector2 = profile[i]
		if y <= b.x:
			return lerpf(a.y, b.y, clampf((y - a.x) / (b.x - a.x), 0.0, 1.0)) * rx
	return 0.0

func _dark_face() -> void:
	var near_bone := PackedVector2Array([Vector2(cx-15, 45), Vector2(cx-10, 44),
		Vector2(cx-4, 47), Vector2(cx-10, 49), Vector2(cx-14, 48)])
	var far_bone := PackedVector2Array([Vector2(cx+5, 48), Vector2(cx+11, 45),
		Vector2(cx+15, 47), Vector2(cx+12, 50), Vector2(cx+8, 50)])
	for y in range(17, int(chin_y) + 1):
		if _lost("jaw") and y > int(mouth_y) + 1:
			continue
		var half := _dark_half(y + 0.5)
		var center := cx + smoothstep(38.0, chin_y, float(y)) * 0.8
		for x in range(int(center - half) - 1, int(center + half) + 1):
			var fx := float(x) + 0.5
			var fy := float(y) + 0.5
			var u := (fx - center) / half
			if absf(u) > 1.0:
				continue
			var light := 0.64 - u * 0.16 + sqrt(maxf(0.0, 1.0 - u * u)) * 0.075
			light += _dark_soft(fx, fy, cx - 5, 28, 11, 10) * 0.09
			# The cheekbone slopes into the nose; its underside turns into a broad hollow.
			var cheek_y := 47.0 if sex_f and stage == "young" else 46.0
			var ridge_y := fy + (absf(fx - cx) - 10.0) * 0.35
			var cheek_width := 6.0 if sex_f else 7.0
			light += _dark_soft(fx, ridge_y, cx - 10, cheek_y, cheek_width, 2.8) * ((0.16 if stage == "elder" else 0.20) if sex_f else 0.17)
			light += _dark_soft(fx, ridge_y, cx + 10, cheek_y + 1, 5.5, 2.7) * (0.17 if sex_f else 0.12)
			if not sex_f:
				# Broad polygonal planes keep the male malar ridge from reading as a soft oval.
				if Geometry2D.is_point_in_polygon(Vector2(fx, fy), near_bone):
					light += 0.11
				if Geometry2D.is_point_in_polygon(Vector2(fx, fy), far_bone):
					light += 0.08
			light -= _dark_soft(fx, fy, cx - 7, eye_y, 6, 3) * 0.13
			light -= _dark_soft(fx, fy, cx + 7, eye_y + 1, 5, 3) * 0.14
			light -= _dark_soft(fx, fy, cx + 4, 48, 3, 6) * 0.12
			var hollow := (0.22 if sex_f else 0.29) if stage == "elder" else (0.14 if sex_f and stage == "young" else 0.21)
			light -= _dark_soft(fx, ridge_y, cx - 11, 52, 6.5, 6.5 if sex_f and stage == "elder" else 5.5) * hollow
			light -= _dark_soft(fx, ridge_y, cx + 11, 53, 6.5, 6) * (hollow + 0.02)
			light += _dark_soft(fx, fy, cx - 9, 58, 5, 2.5) * (0.10 if sex_f else 0.16)
			light -= _dark_soft(fx, fy, cx + 10, 59, 4, 3) * 0.10
			light -= _dark_soft(fx, fy, cx + 1, mouth_y + 3, 6, 2) * 0.10
			light += _dark_soft(fx, fy, cx, chin_y - 3, 6, 2.3) * 0.16
			light -= smoothstep(chin_y - 3.5, chin_y + 0.5, fy) * 0.27
			light -= maxf(0.0, absf(u) - 0.80) * 0.48
			if stage == "adult" and not sex_f:
				# A projecting brow, nasal sidewall and angular mandibular plane.
				light += _dark_soft(fx, fy, cx - 7, eye_y - 5, 6, 2.2) * 0.16
				light += _dark_soft(fx, fy, cx + 7, eye_y - 4, 5, 2) * 0.10
				light -= _dark_soft(fx, fy, cx - 7, eye_y - 2, 6, 2) * 0.12
				light -= _dark_soft(fx, fy, cx + 4, nose_y - 3, 2.5, 5) * 0.16
				light += _dark_soft(fx, fy, cx - 10, 58, 5, 2) * 0.10
			if stage == "elder":
				light -= _dark_soft(fx, fy, cx - 7, eye_y + 3, 5.5, 3.5) * 0.16
				light -= _dark_soft(fx, fy, cx + 7, eye_y + 4, 5, 3.5) * 0.16
				light += _dark_soft(fx, fy, cx - 7, eye_y + 6, 4, 1.7) * 0.10
				light -= _dark_soft(fx, fy, cx - 5, mouth_y - 1, 2.5, 4.5) * 0.12
				light -= _dark_soft(fx, fy, cx + 6, mouth_y, 3, 5) * 0.14
				if sex_f:
					# Soft jowls below the sunken cheek, with a longer, less taut chin.
					light += _dark_soft(fx, fy, cx - 8, 59, 4, 3) * 0.08
					light -= _dark_soft(fx, fy, cx + 6, 61, 4, 3) * 0.12
			var col := _dark_tone(skin_ramp, light)
			if not dead:
				var warmth := _dark_soft(fx, fy, cx - 9, 47, 6, 5)
				col = col.lerp(Color("#a17b98"), warmth * (0.08 if stage == "young" else 0.035))
			_px(x, y, col)

func _dark_neck() -> void:
	if _lost("neck"):
		_blob(int(cx), 69, 5, FigurePainter.BLOOD)
		return
	for y in range(59, int(torso_y) + 8):
		var t := clampf((float(y) - 62.0) / 17.0, 0.0, 1.0)
		var half := neck_w + t * 1.5
		for x in range(int(cx + 1 - half), int(cx + 1 + half) + 1):
			var u := (float(x) - cx - 1.0) / half
			var light := 0.67 - u * 0.18 - t * 0.04
			light -= 0.21 if float(y) < chin_y + 3 else 0.0
			light -= _dark_soft(x, y, cx + 3, 73, 2.0, 6.0) * 0.07
			_px(x, y, _dark_tone(skin_ramp, light))

func _dark_torso() -> void:
	var cloth := _ramp(prim, 0.48)
	var s := torso_y - 72.0
	_dark_poly([cx-11, 70+s, cx, 75+s, cx+11, 70+s, cx+23, 77+s,
		cx+sh_w, 89+s, cx+sh_w+2, 95, cx-sh_w-2, 95, cx-sh_w, 89+s, cx-23, 77+s], cloth)
	_dark_poly([cx-11, 71+s, cx-24, 78+s, cx-32, 91, cx-25, 84+s, cx-16, 80+s, cx-5, 78+s], cloth, 0.13)
	_dark_poly([cx+10, 75+s, cx+22, 79+s, cx+30, 92, cx+22, 87, cx+16, 83], cloth, -0.15)
	_dark_poly([cx-18, 84, cx-6, 79+s, cx+7, 90, cx+21, 95, cx+8, 95, cx-5, 86], cloth, -0.10)
	if _armored():
		var metal := _metal_ramp(_metal_of(body))
		_dark_poly([cx-10, 76+s, cx, 80+s, cx+11, 76+s, cx+19, 84+s,
			cx+23, 95, cx-23, 95, cx-18, 84+s], metal, 0.10)
		_dark_poly([cx-23, 77+s, cx-13, 75+s, cx-9, 80+s, cx-17, 84+s, cx-29, 83+s], metal, 0.28)
		_dark_poly([cx+13, 76+s, cx+23, 80+s, cx+29, 85+s, cx+18, 85+s, cx+10, 81+s], metal, -0.02)
		_dark_line(Vector2(cx-10, 84+s), Vector2(cx-5, 87+s), metal[1])
		_dark_line(Vector2(cx-5, 87+s), Vector2(cx+4, 87+s), metal[1])
		_dark_line(Vector2(cx-23, 79+s), Vector2(cx-17, 77+s), metal[4])
		_dark_line(Vector2(cx+21, 83+s), Vector2(cx+25, 85+s), metal[3])

func _dark_collar() -> void:
	var cloth := _ramp(prim, 0.48)
	var s := torso_y - 72.0
	_dark_poly([cx-11, 69+s, cx-7, 70+s, cx-4, 76+s, cx+1, 79+s,
		cx-2, 82+s, cx-11, 77+s, cx-14, 73+s], cloth, 0.08)
	_dark_poly([cx+10, 70+s, cx+14, 73+s, cx+8, 79+s, cx+2, 82+s,
		cx, 79+s, cx+7, 75+s], cloth, -0.13)
	_dark_line(Vector2(cx-10, 70+s), Vector2(cx-7, 76+s), cloth[4])
	var jewel := _dark_fiber_ramp(sec)
	_dark_poly([cx-11, 75+s, cx-9, 73+s, cx-7, 75+s, cx-9, 78+s], jewel, 0.20)
	_px(int(cx)-9, int(74+s), jewel[4])

func _dark_ear(side: int) -> void:
	var d := float(side)
	var root := Vector2(cx + d * (rx - 1), eye_y + 3)
	if _lost("ear_r" if side < 0 else "ear_l"):
		_blob(int(root.x), int(root.y), 2, FigurePainter.BLOOD)
		return
	var tip := root + Vector2(d * (13.0 if side < 0 else 11.0), -11.0)
	_dark_poly([root.x-d*2, root.y-5, root.x+d*4, root.y-3, tip.x, tip.y,
		root.x+d*9, root.y+1, root.x+d*2, root.y+6, root.x-d*2, root.y+3], skin_ramp,
		0.04 if side < 0 else -0.10)
	_dark_poly([root.x+d, root.y-2, tip.x-d*3, tip.y+4, root.x+d*4, root.y+2,
		root.x+d, root.y+4], skin_ramp, -0.22)
	_dark_line(tip + Vector2(-d*2, 3), root + Vector2(d*3, 0), skin_ramp[3] if side < 0 else skin_ramp[2])
	if sex_f and stage == "elder" and side < 0:
		_dark_line(root + Vector2(-3, 5), root + Vector2(-3, 8), sec.darkened(0.10), 0.8)
		_px(int(root.x)-3, int(root.y)+6, sec.lightened(0.25))

func _dark_age() -> void:
	if stage != "elder":
		return
	# Broken folds follow the socket and mouth volumes, never parallel forehead bars.
	var crease := skin_ramp[2].lerp(skin_ramp[3], 0.68)
	_dark_line(Vector2(cx-10, 32), Vector2(cx-7, 30), crease, 0.45)
	_dark_line(Vector2(cx-7, 30), Vector2(cx-4, 31), crease, 0.45)
	_dark_line(Vector2(cx+9, 31), Vector2(cx+12, 33), crease, 0.45)
	var fold := skin_ramp[1].lerp(skin_ramp[2], 0.58)
	for center in [eye_near, eye_far]:
		_dark_line(center + Vector2(-3, 3), center + Vector2(-1, 4), fold)
		_dark_line(center + Vector2(-1, 4), center + Vector2(2, 4), fold)
		_dark_line(center + Vector2(-1, 5), center + Vector2(1, 5), skin_ramp[2].lerp(skin_ramp[3], 0.30))
	_dark_line(Vector2(cx-12, eye_y+2), Vector2(cx-14, eye_y+4), fold)
	_dark_line(Vector2(cx+12, eye_y+3), Vector2(cx+14, eye_y+4), fold)
	if sex_f:
		_dark_line(Vector2(cx-4, nose_y+2), Vector2(cx-6, mouth_y-1), fold)
		_dark_line(Vector2(cx-6, mouth_y-1), Vector2(cx-5, mouth_y+2), fold)
		_dark_line(Vector2(cx+5, nose_y+3), Vector2(cx+7, mouth_y), fold)
		_dark_line(Vector2(cx+7, mouth_y), Vector2(cx+6, mouth_y+3), fold)

func _dark_eye(near: bool) -> void:
	var center := eye_near if near else eye_far
	var x := int(center.x)
	var y := int(center.y)
	var outer := -1 if near else 1
	var adult := stage == "adult"
	var worried := adult and not sex_f
	var elder := stage == "elder"
	var young_f := sex_f and stage == "young"
	var brow := hair_ramp[1].lerp(skin_ramp[2], 0.28)
	if stage == "elder":
		brow = hair_ramp[2].lerp(skin_ramp[2], 0.27)
	for dx in range(-4, 5):
		var by := y - 5 - (1 if absi(dx) < 3 else 0)
		if worried:
			by += -1 if dx * outer < 0 else 1
		elif adult:
			by += 1 if dx * outer < 0 else -1
		elif stage == "young" and (not near if sex_f else near):
			by -= 1
		elif stage == "elder":
			by += 1 if dx * outer > 2 else 0
			by -= 1 if near and dx < 0 else 0
		_px(x+dx, by, brow)
		if not sex_f and adult and absi(dx) < 4:
			_px(x+dx, by+1, brow.darkened(0.14))
	if _lost("eye_r" if near else "eye_l"):
		_blob(x, y, 3, FigurePainter.BLOOD)
		return
	var lid := skin_ramp[0].lerp(Color("#201b2c"), 0.35)
	if dead:
		_dark_line(Vector2(x-3, y), Vector2(x, y+1), lid)
		_dark_line(Vector2(x, y+1), Vector2(x+3, y), lid)
		return
	var iris := _color_of("eyes", Color("#c43b50"))
	var gaze := 1 if sex_f and stage == "young" else 0
	for dx in range(-4, 5):
		var corner := absi(dx) >= 3
		var upper := 0 if corner else -1
		if worried:
			upper = -1 if dx * outer < -1 else (1 if dx * outer >= 3 else 0)
		elif adult and dx * outer < -1:
			upper += 1
		elif elder:
			upper = 1 if corner else 0
		elif young_f:
			upper = -1 if absi(dx) < 2 else 0
			upper -= 1 if dx * outer >= 3 else 0
		var bottom := 1 if corner or adult or elder or young_f else 2
		if worried and dx * outer > 0:
			bottom = maxi(upper, 0 if dx * outer < 3 else 1)
		if absi(dx) == 4:
			_px(x+dx, y+upper, lid.lerp(skin_ramp[2], 0.18))
			continue
		for dy in range(upper, bottom+1):
			var col := SCLERA.lerp(skin, 0.16 if near else 0.23).darkened(0.04 * (dy+1))
			if dx == gaze or dx == gaze+1:
				col = iris.lightened(0.14) if dy == bottom else iris.darkened(0.16)
				if dx == gaze+1 and dy < bottom:
					col = PUPIL
			_px(x+dx, y+dy, col)
		_px(x+dx, y+upper-1, lid)
		if elder:
			_px(x+dx, y+upper-2, skin_ramp[2].lerp(skin_ramp[3], 0.20 if near else 0.0))
			_px(x+dx, y+upper-1, lid.lerp(skin_ramp[2], 0.32))
		elif worried and absi(dx) < 3:
			_px(x+dx, y+upper-2, skin_ramp[2].lerp(skin_ramp[3], 0.35))
	_px(x+gaze, y if adult or elder else y-1, SCLERA)
	if worried:
		_dark_line(Vector2(x-2, y+2), Vector2(x+1, y+2), skin_ramp[1].lerp(skin_ramp[2], 0.55))
	elif not elder:
		_dark_line(Vector2(x-2, y+3), Vector2(x+1, y+3), skin_ramp[2].lerp(skin_ramp[3], 0.25))
	if sex_f:
		_px(x+outer*4, y-1, lid)

func _dark_nose() -> void:
	if _lost("nose"):
		return
	var nx := cx + 1.0
	var mature_m := not sex_f and stage != "young"
	for y in range(int(eye_y)-1, int(nose_y)+1):
		var t := clampf((float(y)-eye_y+1) / (nose_y-eye_y+1), 0.0, 1.0)
		var center := nx - 0.7 + t * 0.7
		for x in range(int(nx)-3, int(nx)+4):
			var u := (float(x)+0.5-center) / (2.5 if sex_f else 2.8)
			if absf(u) >= 1.0:
				continue
			var light := 0.77 - u*(0.27 if mature_m else 0.17) - t*0.035
			if mature_m:
				light += _dark_soft(u, t, -0.35, 0.65, 0.5, 0.7) * 0.09
			var blend := minf(0.92, (1.0-absf(u))*2.0) * minf(1.0, t*3.0)
			_px(x, y, cv.get_px(x, y).lerp(_dark_tone(skin_ramp, light), blend))
	_dark_line(Vector2(nx-1, nose_y), Vector2(nx+1, nose_y), skin_ramp[3].lerp(skin_ramp[4], 0.35))
	_px(int(nx)-2, int(nose_y)+1, skin_ramp[1].lerp(skin_ramp[2], 0.30))
	_px(int(nx)+2, int(nose_y)+1, skin_ramp[1])
	_px(int(nx), int(nose_y)+2, skin_ramp[2])
	if mature_m:
		_dark_line(Vector2(nx+2, nose_y-3), Vector2(nx+3, nose_y), skin_ramp[1].lerp(skin_ramp[2], 0.35))
		_px(int(nx)+1, int(nose_y)+2, skin_ramp[1])

func _dark_mouth() -> void:
	if _lost("mouth") or _lost("jaw"):
		return
	var x := int(cx)+1
	var y := int(mouth_y)
	var lip := skin.lerp(Color("#9a657f"), 0.35 if sex_f else 0.20)
	var seam := skin_ramp[0].lerp(lip, 0.22)
	var span := 4 if stage == "elder" or sex_f and stage == "young" else 5
	for dx in range(-span, span+1):
		var bend := 0
		if stage == "young" and sex_f:
			bend = -1 if dx < -1 else (1 if dx > 2 else 0)
		elif stage == "young" and dx > 2:
			bend = -1
		elif stage == "adult" and absi(dx) > 3:
			bend = 1
		elif stage == "elder" and absi(dx) > 2:
			bend = 1
		if absi(dx) < span-1:
			_px(x+dx, y+bend-1, lip.darkened(0.18 if stage == "elder" else 0.10))
		_px(x+dx, y+bend, seam.lerp(skin, 0.26 if absi(dx) == span else 0.0))
		if absi(dx) < span-1:
			_px(x+dx, y+bend+1, lip.lerp(skin_ramp[3], 0.18 if stage == "elder" else 0.24))
	_dark_line(Vector2(x-2, y+2), Vector2(x, y+2), lip.lerp(skin_ramp[4], 0.18 if stage == "elder" else 0.24))
	if stage == "adult" and not sex_f:
		# Compressed lower lip and dropped corners carry the worry below the eyes.
		_dark_line(Vector2(x-5, y+1), Vector2(x-5, y+2), seam.lerp(skin, 0.35))
		_dark_line(Vector2(x+5, y+1), Vector2(x+6, y+2), seam.lerp(skin, 0.35))
		_dark_line(Vector2(x-2, y+3), Vector2(x+2, y+3), skin_ramp[1].lerp(skin_ramp[2], 0.60))
	elif stage == "elder" and sex_f:
		_dark_line(Vector2(x-5, y+1), Vector2(x-5, y+3), seam.lerp(skin, 0.55))
		_dark_line(Vector2(x+5, y+1), Vector2(x+5, y+4), seam.lerp(skin, 0.55))

func _dark_lock(a: Vector2, b: Vector2, c: Vector2, r0: float, r1: float,
		ramp: Array[Color], bias: float = 0.0) -> void:
	# A tapered curved solid with a shared light source, never parallel strand strokes.
	const STEPS := 18
	var points := PackedVector2Array()
	var bounds := Rect2(a, Vector2.ZERO)
	for i in range(STEPS+1):
		var t := float(i)/STEPS
		var p := (1.0-t)*(1.0-t)*a + 2.0*(1.0-t)*t*b + t*t*c
		points.append(p)
		bounds = bounds.expand(p)
	bounds = bounds.grow(maxf(r0, r1)+1.0)
	for y in range(maxi(0, int(floor(bounds.position.y))), mini(SIZE, int(ceil(bounds.end.y))+1)):
		for x in range(maxi(0, int(floor(bounds.position.x))), mini(SIZE, int(ceil(bounds.end.x))+1)):
			var p := Vector2(x+0.5, y+0.5)
			var nearest := INF
			var along := 0.0
			var center := a
			var tangent := Vector2.DOWN
			for i in range(STEPS):
				var segment := points[i+1]-points[i]
				var t := clampf((p-points[i]).dot(segment)/maxf(0.001, segment.length_squared()), 0.0, 1.0)
				var q := points[i]+segment*t
				var dist := p.distance_squared_to(q)
				if dist < nearest:
					nearest = dist
					along = (float(i)+t)/STEPS
					center = q
					tangent = segment.normalized()
			var rad := lerpf(r0*0.88, r1, pow(along, 1.25)) + sin(along*PI)*r0*0.18
			rad *= 1.0 + sin(along*7.0+a.x*0.19+c.y*0.11)*0.055
			if nearest > rad*rad:
				continue
			var normal := Vector2(-tangent.y, tangent.x)
			var across := (p-center).dot(normal)/maxf(0.1, rad)
			var light := 0.43 + sqrt(maxf(0.0, 1.0-across*across))*0.19
			light += across*normal.dot(Vector2(-0.7, -0.7))*0.13
			light += bias - along*0.065 - (float(x)-cx)*0.0025
			# The reflection stops at bends; both edges and the root turn into shadow.
			light += _dark_soft(across, along, -0.20, 0.36, 0.52, 0.25)*0.07
			light += sin(along*9.0+a.x*0.23+c.x*0.10)*0.045
			light -= smoothstep(0.62, 1.0, absf(across))*0.12
			light -= (1.0-smoothstep(0.0, 0.20, along))*0.075
			light -= smoothstep(0.87, 1.0, along)*0.055
			_px(x, y, _dark_tone(ramp, light))

func _dark_hlock(a: Vector2, b: Vector2, c: Vector2, r0: float, r1: float, bias: float = 0.0) -> void:
	_dark_lock(a, b, c, r0, r1, hair_ramp, bias)

func _dark_hair_volume(front: bool) -> void:
	if not front:
		if sex_f and stage == "elder":
			_dark_hlock(Vector2(cx+14, 19), Vector2(cx+28, 18), Vector2(cx+22, 30), 4.8, 0.3, -0.19)
			_dark_hlock(Vector2(cx+21, 22), Vector2(cx+27, 30), Vector2(cx+17, 37), 3.0, 0.15, -0.10)
			_dark_hlock(Vector2(cx-15, 31), Vector2(cx-24, 43), Vector2(cx-21, 55), 3.7, 0.2, -0.21)
			_dark_hlock(Vector2(cx-22, 49), Vector2(cx-25, 60), Vector2(cx-16, 69), 2.8, 0.15, -0.13)
			_dark_hlock(Vector2(cx-18, 59), Vector2(cx-10, 73), Vector2(cx-20, 84), 3.1, 0.15, -0.15)
		elif sex_f and stage == "young":
			_dark_hlock(Vector2(cx-15, 28), Vector2(cx-27, 42), Vector2(cx-23, 55), 3.8, 0.2, -0.20)
			_dark_hlock(Vector2(cx-23, 49), Vector2(cx-26, 62), Vector2(cx-19, 73), 3.3, 0.15, -0.14)
			_dark_hlock(Vector2(cx-21, 61), Vector2(cx-15, 80), Vector2(cx-24, 88), 3.0, 0.15, -0.06)
			_dark_hlock(Vector2(cx-18, 52), Vector2(cx-20, 67), Vector2(cx-16, 75), 2.4, 0.1, -0.04)
			_dark_hlock(Vector2(cx+15, 28), Vector2(cx+26, 42), Vector2(cx+23, 54), 3.5, 0.2, -0.26)
			_dark_hlock(Vector2(cx+23, 48), Vector2(cx+27, 61), Vector2(cx+23, 74), 2.2, 0.1, -0.22)
			_dark_hlock(Vector2(cx+20, 57), Vector2(cx+16, 77), Vector2(cx+24, 85), 2.7, 0.15, -0.16)
		elif sex_f:
			_dark_hlock(Vector2(cx-14, 27), Vector2(cx-29, 48), Vector2(cx-20, 72), 7.0, 3.8, -0.16)
			_dark_hlock(Vector2(cx-21, 57), Vector2(cx-13, 77), Vector2(cx-23, 89), 4.8, 0.4, -0.10)
			_dark_hlock(Vector2(cx+14, 27), Vector2(cx+28, 48), Vector2(cx+19, 76), 6.5, 2.7, -0.28)
			_dark_hlock(Vector2(cx+21, 61), Vector2(cx+15, 80), Vector2(cx+24, 86), 3.8, 0.3, -0.21)
		elif stage == "adult":
			_dark_hlock(Vector2(cx+15, 33), Vector2(cx+28, 57), Vector2(cx+21, 79), 4.2, 0.2, -0.29)
			_dark_hlock(Vector2(cx+22, 54), Vector2(cx+27, 67), Vector2(cx+18, 83), 2.5, 0.15, -0.17)
			_dark_hlock(Vector2(cx-14, 29), Vector2(cx-24, 42), Vector2(cx-16, 58), 5.0, 0.3, -0.13)
		elif stage == "elder":
			_dark_hlock(Vector2(cx-13, 24), Vector2(cx-24, 39), Vector2(cx-17, 55), 4.5, 0.5, -0.12)
			_dark_hlock(Vector2(cx+13, 26), Vector2(cx+23, 41), Vector2(cx+17, 53), 4.0, 0.3, -0.22)
		else:
			_dark_hlock(Vector2(cx-15, 25), Vector2(cx-25, 37), Vector2(cx-17, 49), 4.8, 0.4, -0.08)
			_dark_hlock(Vector2(cx+14, 26), Vector2(cx+22, 39), Vector2(cx+17, 49), 4.0, 0.3, -0.21)
		return
	if not sex_f and stage == "elder":
		# A high, open forehead and two receding wings replace the old solid cap.
		_dark_hlock(Vector2(cx-8, 21), Vector2(cx-21, 18), Vector2(cx-20, 35), 4.2, 1.0, 0.04)
		_dark_hlock(Vector2(cx-17, 28), Vector2(cx-23, 37), Vector2(cx-17, 46), 3.2, 0.2, -0.05)
		_dark_hlock(Vector2(cx+7, 22), Vector2(cx+23, 24), Vector2(cx+18, 42), 4.0, 0.3, -0.16)
		_dark_hlock(Vector2(cx-7, 20), Vector2(cx-1, 10), Vector2(cx+8, 19), 3.7, 0.2, 0.12)
		return
	if not sex_f and stage == "adult":
		_dark_poly([cx-19, 34, cx-19, 24, cx-9, 17, cx-3, 13, cx+4, 14, cx+17, 21,
			cx+20, 31, cx+17, 39, cx+12, 29, cx+3, 25, cx-9, 28], hair_ramp, -0.43)
		_dark_hlock(Vector2(cx+6, 17), Vector2(cx+20, 20), Vector2(cx+19, 36), 3.3, 0.15, -0.20)
		_dark_hlock(Vector2(cx-14, 25), Vector2(cx-17, 18), Vector2(cx-7, 17), 2.9, 0.1, -0.03)
		_dark_hlock(Vector2(cx-7, 20), Vector2(cx-5, 9), Vector2(cx+4, 13), 3.2, 0.1, 0.07)
		_dark_hlock(Vector2(cx+1, 17), Vector2(cx+7, 17), Vector2(cx+12, 22), 2.8, 0.1, 0.01)
		_dark_hlock(Vector2(cx-4, 18), Vector2(cx-9, 25), Vector2(cx-16, 31), 3.1, 0.1, -0.03)
		_dark_hlock(Vector2(cx+6, 22), Vector2(cx-2, 25), Vector2(cx-6, 32), 2.6, 0.1, 0.00)
		_dark_hlock(Vector2(cx+9, 21), Vector2(cx+14, 25), Vector2(cx+13, 33), 2.5, 0.1, -0.09)
		_dark_hlock(Vector2(cx-18, 30), Vector2(cx-21, 39), Vector2(cx-17, 45), 2.5, 0.1, -0.13)
		_dark_hlock(Vector2(cx+20, 52), Vector2(cx+26, 64), Vector2(cx+20, 76), 2.8, 0.15, -0.08)
		_dark_hlock(Vector2(cx+23, 63), Vector2(cx+21, 76), Vector2(cx+17, 81), 1.8, 0.1, -0.12)
		_dark_line(Vector2(cx+18, 58), Vector2(cx+23, 59), sec.darkened(0.25), 0.7)
		return
	if sex_f and stage == "elder":
		_dark_poly([cx-19, 34, cx-19, 24, cx-10, 18, cx+2, 15, cx+15, 20,
			cx+19, 30, cx+16, 39, cx+10, 29, cx+2, 26, cx-11, 31], hair_ramp, -0.43)
		_dark_hlock(Vector2(cx+5, 18), Vector2(cx+21, 19), Vector2(cx+19, 33), 3.6, 0.15, -0.16)
		_dark_hlock(Vector2(cx+12, 24), Vector2(cx+19, 29), Vector2(cx+16, 38), 2.4, 0.1, -0.10)
		_dark_hlock(Vector2(cx-2, 16), Vector2(cx-9, 13), Vector2(cx-16, 24), 2.6, 0.15, 0.06)
		_dark_hlock(Vector2(cx+5, 16), Vector2(cx-2, 17), Vector2(cx-6, 24), 2.6, 0.1, 0.01)
		_dark_hlock(Vector2(cx-8, 21), Vector2(cx-16, 25), Vector2(cx-19, 32), 2.7, 0.1, -0.02)
		_dark_hlock(Vector2(cx+5, 22), Vector2(cx-4, 25), Vector2(cx-11, 35), 2.7, 0.1, -0.03)
		_dark_hlock(Vector2(cx-7, 28), Vector2(cx-13, 32), Vector2(cx-15, 38), 1.8, 0.1, -0.04)
		_dark_hlock(Vector2(cx-18, 42), Vector2(cx-23, 53), Vector2(cx-17, 63), 3.0, 0.15, -0.06)
		_dark_hlock(Vector2(cx-19, 57), Vector2(cx-13, 66), Vector2(cx-15, 74), 2.5, 0.1, 0.00)
		_dark_hlock(Vector2(cx-15, 68), Vector2(cx-12, 76), Vector2(cx-19, 82), 2.2, 0.1, -0.06)
		_dark_hlock(Vector2(cx-20, 68), Vector2(cx-20, 77), Vector2(cx-22, 80), 1.6, 0.1, -0.13)
		_dark_line(Vector2(cx-19, 81), Vector2(cx-16, 82), sec.darkened(0.05), 0.9)
		return
	if not sex_f:
		# Different roots, bends and lengths break the crown into overlapping locks.
		_dark_poly([cx-20, 34, cx-18, 23, cx-10, 16, cx+2, 13, cx+15, 18,
			cx+20, 28, cx+18, 39, cx+12, 28, cx+4, 26, cx-7, 30, cx-16, 38], hair_ramp, -0.43)
		_dark_hlock(Vector2(cx+7, 16), Vector2(cx+20, 20), Vector2(cx+20, 33), 3.3, 0.15, -0.16)
		_dark_hlock(Vector2(cx+10, 23), Vector2(cx+17, 30), Vector2(cx+15, 40), 2.3, 0.1, -0.08)
		_dark_hlock(Vector2(cx-7, 17), Vector2(cx-18, 17), Vector2(cx-20, 30), 2.8, 0.1, -0.09)
		_dark_hlock(Vector2(cx-3, 17), Vector2(cx+2, 8), Vector2(cx+8, 15), 3.0, 0.1, 0.08)
		_dark_hlock(Vector2(cx+4, 17), Vector2(cx-2, 20), Vector2(cx-9, 27), 3.1, 0.1, 0.01)
		_dark_hlock(Vector2(cx-5, 22), Vector2(cx-14, 27), Vector2(cx-15, 38), 2.5, 0.1, 0.04)
		_dark_hlock(Vector2(cx+7, 22), Vector2(cx+7, 28), Vector2(cx+2, 33), 2.0, 0.1, -0.03)
		_dark_hlock(Vector2(cx, 22), Vector2(cx-2, 29), Vector2(cx-6, 34), 2.1, 0.1, -0.02)
		_dark_hlock(Vector2(cx-19, 31), Vector2(cx-22, 38), Vector2(cx-17, 46), 2.6, 0.1, -0.06)
		return
	if stage == "young":
		_dark_poly([cx-20, 34, cx-18, 23, cx-10, 16, cx+2, 13, cx+15, 18,
			cx+20, 28, cx+18, 39, cx+12, 28, cx+4, 26, cx-7, 30, cx-16, 38], hair_ramp, -0.43)
		_dark_hlock(Vector2(cx+6, 18), Vector2(cx+24, 20), Vector2(cx+19, 35), 3.8, 0.15, -0.17)
		_dark_hlock(Vector2(cx+13, 24), Vector2(cx+20, 31), Vector2(cx+17, 40), 2.6, 0.1, -0.08)
		_dark_hlock(Vector2(cx-2, 16), Vector2(cx-9, 12), Vector2(cx-16, 22), 2.6, 0.15, 0.07)
		_dark_hlock(Vector2(cx+5, 15), Vector2(cx-2, 17), Vector2(cx-6, 23), 2.6, 0.1, 0.02)
		_dark_hlock(Vector2(cx-8, 20), Vector2(cx-16, 23), Vector2(cx-19, 31), 2.8, 0.1, 0.01)
		_dark_hlock(Vector2(cx+5, 21), Vector2(cx-4, 24), Vector2(cx-11, 34), 2.8, 0.1, 0.00)
		_dark_hlock(Vector2(cx-7, 27), Vector2(cx-13, 31), Vector2(cx-15, 38), 1.9, 0.1, -0.02)
		_dark_hlock(Vector2(cx+8, 23), Vector2(cx+1, 25), Vector2(cx-3, 31), 2.1, 0.1, -0.03)
		_dark_hlock(Vector2(cx-18, 41), Vector2(cx-23, 51), Vector2(cx-17, 62), 3.0, 0.15, -0.02)
		_dark_hlock(Vector2(cx-18, 57), Vector2(cx-13, 72), Vector2(cx-19, 82), 2.6, 0.1, 0.00)
		_dark_hlock(Vector2(cx-20, 65), Vector2(cx-20, 77), Vector2(cx-23, 83), 1.8, 0.1, -0.08)
		_dark_hlock(Vector2(cx+18, 44), Vector2(cx+16, 58), Vector2(cx+22, 68), 2.8, 0.1, -0.15)
		return
	# The adult woman's established silhouette remains intact.
	_dark_poly([cx-20, 34, cx-18, 23, cx-10, 16, cx+2, 13, cx+15, 18,
		cx+20, 28, cx+18, 39, cx+12, 28, cx+4, 26, cx-7, 30, cx-16, 38], hair_ramp, -0.12)
	_dark_hlock(Vector2(cx+6, 18), Vector2(cx+25, 19), Vector2(cx+18, 40), 6.0, 0.3, -0.16)
	_dark_hlock(Vector2(cx+2, 14), Vector2(cx-12, 7), Vector2(cx-20, 29), 6.6, 0.5, 0.12)
	_dark_hlock(Vector2(cx+8, 21), Vector2(cx-7, 15), Vector2(cx-16, 37), 5.4, 0.2, 0.035)
	if sex_f:
		_dark_hlock(Vector2(cx-18, 43), Vector2(cx-23, 55), Vector2(cx-15, 65), 4.0, 0.3, -0.04)
		_dark_hlock(Vector2(cx-16, 63), Vector2(cx-12, 76), Vector2(cx-21, 85), 3.8, 0.2, -0.04)
		_dark_hlock(Vector2(cx+18, 45), Vector2(cx+15, 60), Vector2(cx+22, 68), 3.6, 0.2, -0.19)
	else:
		_dark_hlock(Vector2(cx-19, 31), Vector2(cx-22, 38), Vector2(cx-17, 46), 2.6, 0.1, -0.06)

func _dark_beard_volume() -> void:
	if not beard_on or sex_f or _lost("jaw") or _lost("mouth"):
		return
	var x := cx+1.0
	var y := mouth_y
	var tip := chin_y + (7.0 if stage == "elder" else 5.0)
	if stage == "elder":
		# Recessed roots and diagonal, staggered clumps interrupt the beard's pale V.
		var beard_shadow: Array[Color] = []
		for col in beard_ramp:
			beard_shadow.append(col.darkened(0.23))
		_dark_poly([x-12, y-1, x-8, y+4, x-3, y+5, x+4, y+4, x+11, y-1,
			x+12, y+6, x+7, chin_y+4, x, tip+1, x-8, chin_y+3, x-13, y+5], beard_ramp, -0.53)
		_dark_lock(Vector2(x+11, y+1), Vector2(x+12, chin_y-1), Vector2(x+4, tip-3), 3.1, 0.15, beard_ramp, -0.22)
		_dark_lock(Vector2(x-11, y), Vector2(x-13, y+8), Vector2(x-5, chin_y+2), 3.5, 0.15, beard_ramp, -0.07)
		_dark_lock(Vector2(x+7, y+6), Vector2(x+6, chin_y+4), Vector2(x-2, tip+1), 3.6, 0.15, beard_shadow, -0.04)
		_dark_lock(Vector2(x-8, y+5), Vector2(x-4, chin_y+2), Vector2(x+2, tip-3), 3.2, 0.15, beard_ramp, 0.025)
		_dark_lock(Vector2(x+5, y+7), Vector2(x+2, chin_y+1), Vector2(x-4, tip-1), 2.8, 0.1, beard_ramp, -0.10)
		_dark_lock(Vector2(x-9, y+6), Vector2(x-10, chin_y+1), Vector2(x-6, tip-4), 2.2, 0.1, beard_ramp, -0.03)
		_dark_poly([x-4, y+2, x, y+3, x+3, y+2, x+3, y+4,
			x, y+5, x-4, y+4], beard_shadow, -0.30)
		_dark_lock(Vector2(x-2, y+7), Vector2(x+3, chin_y+3), Vector2(x+1, tip+1), 3.6, 0.1, beard_ramp, -0.015)
	elif beard_i not in [1, 6, 7]:
		_dark_poly([x-12, y-1, x-8, y+4, x-3, y+5, x+4, y+4, x+11, y-1,
			x+12, y+6, x+7, chin_y+4, x, tip, x-8, chin_y+3, x-13, y+5], beard_ramp, -0.19)
		_dark_lock(Vector2(x+10, y+1), Vector2(x+12, chin_y), Vector2(x+4, tip-2), 3.5, 0.3, beard_ramp, -0.17)
		_dark_lock(Vector2(x-10, y+1), Vector2(x-11, chin_y+1), Vector2(x-2, tip-1), 4.0, 0.4, beard_ramp, -0.02)
		_dark_lock(Vector2(x-2, y+6), Vector2(x+3, chin_y+3), Vector2(x, tip+1), 4.8, 0.3, beard_ramp, 0.025)
	elif beard_i == 1:
		_dark_lock(Vector2(x, y+5), Vector2(x+3, chin_y+1), Vector2(x, tip), 4.1, 0.25, beard_ramp)
	elif beard_i == 7:
		# A quiet shaded jaw for short stubble; no regular stipple or stroke grid.
		for yy in range(int(y)+3, int(chin_y)+1):
			var half := _dark_half(yy+0.5)*0.88
			for xx in range(int(x-half), int(x+half)+1):
				var strength := smoothstep(y+2, chin_y, float(yy))*0.33
				_px(xx, yy, cv.get_px(xx, yy).lerp(beard_ramp[1], strength))
	_dark_lock(Vector2(x-1, y-2), Vector2(x-5, y-3), Vector2(x-7, y+1), 1.9 if stage == "elder" else 1.7, 0.2, beard_ramp, 0.06)
	_dark_lock(Vector2(x+1, y-2), Vector2(x+5, y-2), Vector2(x+7, y+1), 1.7 if stage == "elder" else 1.6, 0.2, beard_ramp, -0.12)

func _read() -> void:
	race = RACE
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
			jaw *= 0.76
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
		jaw *= 0.92 if race == "dark_elf" else 1.06
	elif stage == "elder" and sex_f and race == "dark_elf":
		jaw *= 0.90
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
		if not sex_f and stage == "adult":
			jaw = 1.06
			rx = 17.2
			brow_k = 1.38
			eye_k = 0.96
		elif not sex_f and stage == "young":
			jaw = 0.92
			rx = 16.4
			brow_k = 1.12
			eye_k = 1.02
		elif not sex_f and stage == "elder":
			jaw = 1.02
			rx = 16.8
			brow_k = 1.50
			eye_k = 0.92
		elif sex_f and stage == "elder":
			jaw = 0.62
			rx = 14.8
			brow_k = 0.78
			eye_k = 0.92
		else:
			jaw = 0.74
			rx = 15.6
			brow_k = 0.66
			eye_k = 1.12
	elif race == "moon_elf":
		if not sex_f and stage == "adult":
			jaw = 1.10
			rx = 17.6
			brow_k = 1.50
			eye_k = 0.94
		elif not sex_f and stage == "young":
			jaw = 0.98
			rx = 16.9
			brow_k = 1.32
			eye_k = 0.98
		elif not sex_f and stage == "elder":
			jaw = 0.92
			rx = 16.6
			brow_k = 1.40
			eye_k = 0.92
		elif sex_f and stage == "elder":
			jaw = 0.62
			rx = 14.8
			brow_k = 0.74
			eye_k = 0.92
		else:
			jaw = 0.68
			rx = 15.2
			brow_k = 0.64
			eye_k = 1.12
	elif race == "goblin":
		rx = 14.2 if sex_f else 15.0
		ry = 17.5
		cy = 42.0
		if stage == "young":
			jaw = 0.86 if sex_f else 0.92
			brow_k *= 0.85
			eye_k *= 1.08
		elif stage == "elder":
			jaw = 0.90 if sex_f else 1.02
			brow_k *= 1.25
			eye_k *= 0.92
		else:
			jaw = 0.88 if sex_f else 1.00
			brow_k *= 1.15
	elif race == "troll":
		if stage == "young":
			jaw *= 0.92
		elif stage == "elder" and not sex_f:
			jaw *= 1.06
			brow_k *= 1.08
	nose_k = String(m["nose"])
	ear_k = String(m["ear"])
	cx = 48.0
	eye_y = cy - ry * 0.06
	mouth_y = cy + ry * 0.52
	chin_y = cy + ry * 0.92
	if race == "dark_elf":
		if stage == "young":
			eye_y -= 1.0
			mouth_y += 1.0
		elif stage == "elder":
			eye_y += 1.0
			mouth_y += 1.4
		if sex_f:
			mouth_y -= 0.8
			eye_y -= 0.4
	elif race == "moon_elf":
		if stage == "young" and sex_f:
			eye_y -= 0.8
			mouth_y -= 0.6
		elif stage == "young":
			eye_y -= 0.4
		elif stage == "elder":
			eye_y += 0.8
			mouth_y += 1.0
	if race == "troll":
		eye_y = cy - ry * 0.08
		mouth_y = cy + ry * 0.52
		chin_y = cy + ry * 0.95
		if stage == "young":
			eye_y -= 0.5
		elif stage == "elder":
			eye_y += 0.5
	elif race == "goblin":
		eye_y = cy - ry * 0.14
		mouth_y = cy + ry * 0.60
		chin_y = cy + ry * 0.96
	nose_y = minf(cy + ry * 0.30 + float(nose_extra) * 0.45, mouth_y - 4.0)
	torso_y = chin_y + 5.0
	scl = 3.15 * eye_k
	if race == "moon_elf" or race == "dark_elf":
		var span_scl := maxf(scl, 3.25)
		eye_near = Vector2(cx - (span_scl + 2.7) + float(eye_shift) * 0.5, eye_y)
		eye_far = Vector2(cx + (span_scl + 1.5) + float(eye_shift) * 0.5, eye_y)
	elif race == "troll":
		eye_near = Vector2(cx - 7.2 + float(eye_shift) * 0.4, eye_y)
		eye_far = Vector2(cx + 7.2 + float(eye_shift) * 0.4, eye_y)
	elif race == "goblin":
		eye_near = Vector2(cx - 6.4 + float(eye_shift) * 0.4, eye_y)
		eye_far = Vector2(cx + 6.4 + float(eye_shift) * 0.4, eye_y)
	else:
		eye_near = Vector2(cx - (scl + 2.6) + float(eye_shift), eye_y)
		eye_far = Vector2(cx + (scl + 1.3) + float(eye_shift), eye_y)
	skin = _color_of("skin", Color("#555066"))
	hair = _color_of("hair", Color("#e0deeb"))
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
		hair = Color(0.78, 0.84, 0.92, 1.0)
	if stage == "elder":
		if race == "dark_elf":
			hair = Color(0.90, 0.90, 0.94, 1.0)
		elif race == "moon_elf":
			hair = Color(0.88, 0.90, 0.96, 1.0)
		else:
			hair = _op(hair.lerp(Color("#d8d8dc"), 0.55))
	_read_beard()
	if race == "moon_elf" and not sex_f and stage == "adult" and not beard_on and not dead:
		beard_on = true
		beard_i = 8
		beard_col = Color("#64789c")
	elif race == "dark_elf" and not sex_f and stage == "elder" and not dead:
		beard_on = true
		beard_i = 8
		beard_col = Color("#d8deec")
	if stage == "elder":
		if race == "moon_elf":
			beard_col = _op(beard_col.lerp(Color(0.68, 0.75, 0.88), 0.50))
		elif race == "dark_elf":
			beard_col = Color("#d8deec")
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
		var m_base := skin.lerp(Color("#889cc4"), 0.72)
		if stage == "elder":
			m_base = m_base.lerp(Color("#7686a8"), 0.36)
		skin_ramp = [
			Color("#344262"),
			Color("#54668c"),
			_op(m_base.darkened(0.18)),
			_op(m_base),
			_op(m_base.lightened(0.16)),
		]
	elif race == "dark_elf":
		var dusk := skin
		if stage == "elder":
			dusk = _op(dusk.lerp(Color("#4c4658"), 0.28))
		skin_ramp = [
			_op(dusk.lerp(Color(0.10, 0.07, 0.14), 0.70)),
			_op(dusk.darkened(0.38)),
			_op(dusk.darkened(0.18)),
			_op(dusk),
			_op(dusk.lightened(0.22)),
		]
	elif race == "troll":
		var t_base := skin.lerp(Color("#7a8676"), 0.36)
		if stage == "elder":
			t_base = t_base.lerp(Color("#768074"), 0.24)
		skin_ramp = [
			_op(t_base.darkened(0.34)),
			_op(t_base.darkened(0.20)),
			_op(t_base.darkened(0.08)),
			_op(t_base.lightened(0.04)),
			_op(t_base.lightened(0.16)),
		]
	hair_ramp = _ramp(hair, hair_depth)
	if race == "moon_elf" and stage == "elder":
		hair_ramp = [
			Color("#58647e"),
			Color("#7c8aa6"),
			Color("#a8b6ce"),
			Color("#d2dced"),
			Color("#f4f8ff"),
		]
	elif race == "moon_elf":
		hair_ramp = [
			Color("#3c4c70"),
			Color("#60749c"),
			Color("#8aa2cc"),
			Color("#bcd0ec"),
			Color("#eaf3fc"),
		]
	elif race == "dark_elf" and stage == "elder":
		hair_ramp = [
			Color(0.38, 0.39, 0.48, 1.0),
			Color(0.52, 0.54, 0.64, 1.0),
			Color(0.70, 0.71, 0.79, 1.0),
			Color(0.84, 0.85, 0.91, 1.0),
			Color(0.94, 0.95, 0.99, 1.0),
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
	elif race == "troll" and stage == "elder":
		hair_ramp = [
			Color("#38423a"),
			Color("#5a665c"),
			Color("#849086"),
			Color("#b2beb4"),
			Color("#e0ece2"),
		]
	elif race == "troll":
		var th := hair.lerp(Color("#4e5c4c"), 0.54)
		hair_ramp = [
			_op(th.darkened(0.46)),
			_op(th.darkened(0.22)),
			_op(th),
			_op(th.lightened(0.22)),
			_op(th.lightened(0.44)),
		]
	elif race == "goblin" and stage == "elder":
		hair_ramp = [
			Color("#303832"),
			Color("#546058"),
			Color("#829086"),
			Color("#b8c6bc"),
			Color("#eef6f0"),
		]
	elif race == "goblin":
		var gh := hair.lerp(Color("#4e5e46"), 0.56)
		hair_ramp = [
			_op(gh.darkened(0.55)),
			_op(gh.darkened(0.28)),
			_op(gh),
			_op(gh.lightened(0.22).lerp(Color("#8ca07e"), 0.35)),
			_op(gh.lightened(0.45).lerp(Color("#bed0ae"), 0.40)),
		]
	if race == "dwarf" and stage != "elder":
		beard_ramp = [
			_op(Color("#3a2412")),
			_op(Color("#6a3e20")),
			_op(Color("#8f5a30")),
			_op(Color("#c08448")),
			_op(Color("#e0b070")),
		]
	elif race == "troll" and stage == "elder":
		beard_ramp = [
			Color("#38403a"),
			Color("#5a645c"),
			Color("#828e84"),
			Color("#aeb8b0"),
			Color("#dce4de"),
		]
	elif race == "troll":
		var tb := beard_col.lerp(Color("#4a5446"), 0.50)
		beard_ramp = [
			_op(tb.darkened(0.46)),
			_op(tb.darkened(0.22)),
			_op(tb),
			_op(tb.lightened(0.18)),
			_op(tb.lightened(0.36)),
		]
	elif race == "dark_elf" and stage == "elder":
		beard_ramp = [
			Color("#484e64"),
			Color("#687088"),
			Color("#9098b2"),
			Color("#bac2da"),
			Color("#e4ecfc"),
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
				return "braid" if stage == "elder" else "long"
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
			if stage == "young":
				return "short"
			if stage == "adult":
				return "short"
			return "half"
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

func _shade_band(lit: float, _x: int, _y: int) -> int:
	return clampi(int(clampf(lit, 0.0, 0.98) * 4.999), 0, 4)

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
	if v >= 0.0:
		xrad = lerpf(1.0, jaw * (0.84 if sex_f else 0.93), smoothstep(0.02, 0.92, v))
		if race == "troll":
			var shelf := 1.04 if sex_f else 1.18
			if stage == "young":
				shelf *= 0.94
			elif stage == "elder" and not sex_f:
				shelf *= 1.06
			xrad = lerpf(0.98, shelf, smoothstep(0.04, 0.52, v))
		elif race == "goblin":
			var g_jaw := 0.88 if sex_f else 0.98
			if stage == "young":
				g_jaw *= 0.95
			elif stage == "elder" and not sex_f:
				g_jaw *= 1.04
			xrad = lerpf(1.0, g_jaw, smoothstep(0.04, 0.74, v))
		elif race == "dark_elf":
			if stage == "elder":
				var elder_jaw := 0.98 if not sex_f else 0.58
				xrad = lerpf(1.0, elder_jaw, smoothstep(0.06, 0.84, v))
				if v > 0.14 and v < 0.74:
					var hollow_t := sin(((v - 0.14) / 0.60) * PI)
					xrad -= (0.18 if sex_f else 0.04) * hollow_t
			elif not sex_f and stage == "adult":
				xrad = lerpf(1.0, 1.02, smoothstep(0.04, 0.68, v))
			elif not sex_f and stage == "young":
				xrad = lerpf(1.0, 0.88, smoothstep(0.04, 0.88, v))
			elif sex_f:
				xrad = lerpf(1.0, 0.72, smoothstep(0.02, 0.88, v))
		elif race == "moon_elf":
			if stage == "elder":
				var m_elder_jaw := 0.88 if not sex_f else 0.60
				xrad = lerpf(1.0, m_elder_jaw, smoothstep(0.08, 0.90, v))
				if v > 0.14 and v < 0.74:
					var m_hollow := sin(((v - 0.14) / 0.60) * PI)
					xrad -= (0.14 if sex_f else 0.07) * m_hollow
			elif not sex_f and stage == "adult":
				xrad = lerpf(1.0, 1.04, smoothstep(0.04, 0.68, v))
			elif not sex_f and stage == "young":
				xrad = lerpf(1.0, 0.95, smoothstep(0.04, 0.84, v))
			elif sex_f:
				xrad = lerpf(1.0, 0.66, smoothstep(0.02, 0.88, v))
		if v > 0.76:
			var pinch: float = 0.58 if sex_f else 0.74
			if race == "dwarf":
				pinch = 0.90 if sex_f else 0.93
			elif race == "troll":
				pinch = 0.88 if sex_f else 0.96
			elif race == "goblin":
				pinch = 0.72 if sex_f else 0.82
			elif race == "dark_elf":
				if not sex_f and stage == "adult":
					pinch = 0.90
				elif not sex_f and stage == "young":
					pinch = 0.78
				elif not sex_f and stage == "elder":
					pinch = 0.88
				elif sex_f and stage == "elder":
					pinch = 0.42
				else:
					pinch = 0.54
			elif race == "moon_elf":
				if not sex_f and stage == "adult":
					pinch = 0.92
				elif not sex_f and stage == "young":
					pinch = 0.84
				elif not sex_f and stage == "elder":
					pinch = 0.78
				elif sex_f and stage == "elder":
					pinch = 0.42
				else:
					pinch = 0.48
			xrad *= lerpf(1.0, pinch, smoothstep(0.76, 1.02, v))
	else:
		xrad = lerpf(0.88, 1.0, smoothstep(-1.05, -0.1, v))
	var vv := v
	if race == "troll" and v > 0.56 and v <= 0.99:
		vv = lerpf(v, 0.66, 0.48)
	elif race == "goblin" and v > 0.70 and v <= 0.96:
		vv = lerpf(v, 0.75, 0.30)
	elif race == "dark_elf" and not sex_f and (stage == "adult" or stage == "elder") and v > 0.70 and v <= 0.96:
		vv = lerpf(v, 0.74, 0.48 if stage == "adult" else 0.44)
	elif race == "moon_elf" and not sex_f and stage == "adult" and v > 0.68 and v <= 0.96:
		vv = lerpf(v, 0.72, 0.52)
	elif race == "moon_elf" and not sex_f and stage == "young" and v > 0.72 and v <= 0.96:
		vv = lerpf(v, 0.75, 0.36)
	var u := dx / (rx * xrad * side)
	if race == "troll" and v > 0.0:
		if pow(absf(u), 2.8) + pow(maxf(0.0, vv), 2.8) > 1.0:
			return false
	elif u * u + vv * vv > 1.0:
		return false
	var z := sqrt(maxf(0.0, 1.0 - u * u - v * v))
	nu = u
	nv = v
	nn = Vector3(u * 0.92 - 0.16, v * 0.95 + 0.02, z + 0.08).normalized()
	return true

func _skin_at() -> Color:
	var lit := clampf(0.84 - nu * 0.46 - maxf(nv, -0.15) * 0.34, 0.06, 0.94)
	if race == "troll":
		lit = clampf(0.80 - nu * 0.40 - maxf(nv, -0.18) * 0.30, 0.16, 0.90)
	elif race == "goblin":
		lit = clampf(0.82 - nu * 0.42 - maxf(nv, -0.18) * 0.32, 0.14, 0.92)
		if nv > 0.02 and nv < 0.28 and absf(nu) > 0.36 and absf(nu) < 0.74:
			lit += 0.06
		elif nv > 0.68 and nv < 0.90 and absf(nu) < 0.32:
			lit += 0.05
	var px := int(cx + nu * rx)
	var py := int(cy + nv * ry)
	var band := _shade_band(lit, px, py)
	if race != "troll" and race != "goblin":
		if Vector2(nu + 0.28, nv - 0.06).length() < 0.30:
			band = mini(4, band + 1)
		if brow_k > 1.20 and nv > -0.36 and nv < 0.02 and absf(nu) < 0.72:
			band = maxi(0, band - 1)
	if race == "dwarf" and absf(nu) < 0.38 and nv > 0.02 and nv < 0.50:
		band = mini(4, band + 1)
	elif race == "orc":
		if nv < -0.32:
			band = mini(4, band + 1)
		elif nv > 0.40:
			band = maxi(0, band - 1)
		elif absf(nu) > 0.48 and nv > 0.0 and nv < 0.40:
			band = maxi(0, band - 1)
	elif race == "dark_elf" or race == "moon_elf":
		if stage == "elder":
			var malar_line := 0.66 - (nv - 0.16) * 0.48
			var malar_d := absf(absf(nu) - malar_line)
			if nv > 0.0 and nv < 0.15 and absf(nu) > 0.40 and absf(nu) < 0.80:
				band = mini(4, band + 1)
			elif nv >= 0.18 and nv <= 0.54 and malar_d < 0.14:
				band = maxi(0, band - 1)
		elif not sex_f:
			if nv > 0.12 and nv < 0.44 and absf(nu) > 0.44 and absf(nu) < 0.76:
				band = mini(4, band + 1)
			elif nv >= 0.46 and absf(nu) > 0.52:
				band = maxi(0, band - 1)
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
	if not (stage == "young" and sex_f) or race == "troll" or race == "goblin":
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
			_px(ccx + x, ccy + y, ramp[band])

func _hair_col(x: int, y: int) -> Color:
	var u := float(x - int(cx)) / maxf(10.0, rx)
	var v := float(y - int(cy - ry)) / maxf(12.0, ry * 1.4)
	var spread: float = 0.50
	if race == "dark_elf":
		spread = 0.48 if stage == "elder" else 0.36
	elif race == "moon_elf":
		spread = 0.54
	var lit := clampf(0.78 - u * spread - v * (spread + 0.08), 0.06, 0.94)
	var band: int = _shade_band(lit, x, y)
	if race == "moon_elf" or race == "dark_elf":
		var strand_wave := sin(float(x) * 0.85 + float(y) * 0.22 + float(seed))
		if strand_wave > 0.62:
			band = mini(4, band + 1)
		elif strand_wave < -0.66:
			band = maxi(0, band - 1)
	else:
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
		_moon_bangs(false)
		return
	if race == "dark_elf":
		_dark_hair(false)
		return
	if race == "troll":
		_troll_hair(false)
		return
	if race == "goblin":
		_goblin_hair(false)
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
		_moon_bangs(true)
		return
	if race == "dark_elf":
		_dark_hair(true)
		return
	if race == "troll":
		_troll_hair(true)
		return
	if race == "goblin":
		_goblin_hair(true)
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
			if race == "orc":
				_fringe(5.0)
			if hstyle == "side":
				var dir := -1.0 if part_left else 1.0
				_hair_ellipse(Vector2(cx + dir * rx * 0.34, eye_y - 8.0), rx * 0.52, 7.0, eye_y - 1.0)
		"half":
			_hair_cap(line + 2.0, 1.02)
			if race == "dark_elf" and not sex_f and stage == "adult":
				_side_locks(false)
		"long":
			_hair_cap(line, 1.06)
			if sex_f:
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
				if sex_f:
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

func _moon_bangs(front: bool) -> void:
	_moon_hair(front)

func _elf_lock(p0: Vector2, p1: Vector2, p2: Vector2, r0: float, r1: float, _bias: int = 0) -> void:
	var steps := 18
	var pts: Array[Vector2] = []
	var lo := Vector2(999.0, 999.0)
	var hi := Vector2(-999.0, -999.0)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var omt := 1.0 - t
		var pt := omt * omt * p0 + 2.0 * omt * t * p1 + t * t * p2
		pts.append(pt)
		lo.x = minf(lo.x, pt.x)
		lo.y = minf(lo.y, pt.y)
		hi.x = maxf(hi.x, pt.x)
		hi.y = maxf(hi.y, pt.y)
	var pad := maxf(r0, r1) + 1.5
	var x0 := maxi(int(floor(lo.x - pad)), 0)
	var x1 := mini(int(ceil(hi.x + pad)), SIZE - 1)
	var y0 := maxi(int(floor(lo.y - pad)), 0)
	var y1 := mini(int(ceil(hi.y + pad)), SIZE - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var best_d2 := 99999.0
			var best_t := 0.0
			var best_c := Vector2.ZERO
			for i in range(steps):
				var a := pts[i]
				var b := pts[i + 1]
				var c := Geometry2D.get_closest_point_to_segment(p, a, b)
				var d2 := p.distance_squared_to(c)
				if d2 < best_d2:
					best_d2 = d2
					best_c = c
					var seg_len := a.distance_to(b)
					var seg_t := a.distance_to(c) / seg_len if seg_len > 0.001 else 0.0
					best_t = (float(i) + seg_t) / float(steps)
			var rad := lerpf(r0, r1, best_t)
			if best_d2 > rad * rad:
				continue
			var across := (p.x - best_c.x) / maxf(1.0, rad)
			var col := _hair_col(x, y)
			if across < -0.38:
				col = hair_ramp[4 if p.x < cx else 3]
			elif across > 0.45:
				col = hair_ramp[1]
			_px(x, y, col)

func _elf_crown_and_fringe(part_x: float, sweep_dir: float, open_center: bool, short_cut: bool) -> void:
	var top := cy - ry
	var is_adult_male := not sex_f and stage == "adult"
	var w_mult := (1.08 if is_adult_male else 1.12) if short_cut else 1.16
	var x0 := int(floor(cx - rx * w_mult))
	var x1 := int(ceil(cx + rx * (w_mult - 0.02)))
	var brow_top := eye_y - 4.0
	for x in range(maxi(x0, 0), mini(x1 + 1, SIZE)):
		var fx := float(x) + 0.5
		var u := (fx - (cx - 0.2)) / (rx * w_mult)
		if absf(u) > 1.0:
			continue
		var dx_part := (fx - part_x) * sweep_dir
		var part_d := absf(fx - part_x)
		# High asymmetric crown waves rising 4.5-6.0px off the skull with a natural side-part cleft
		var cleft := 2.5 * clampf(1.0 - part_d / 3.0, 0.0, 1.0)
		var puff := (4.8 if is_adult_male else 5.6) if dx_part >= 0.0 else (3.5 if is_adult_male else 4.2)
		var wave_bump := 1.2 * sin(clampf(absf(dx_part) / (rx * 0.88), 0.0, 1.0) * PI)
		var dome := (ry * 0.44) * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
		var y_hi := top - puff - wave_bump + dome + cleft
		# Lower hairline: broken by a deep side-part notch, swept fringe locks, and loose strands
		var y_lo: float
		if open_center:
			var c_span := absf(fx - part_x) / maxf(1.0, rx * 0.98)
			var elder_part_y := (eye_y - 12.8) if race == "dark_elf" else (eye_y - 11.8)
			var elder_base_y := (eye_y - 11.6) if race == "dark_elf" else (eye_y - 10.2)
			var exp_p := 1.85 if race == "dark_elf" else 1.45
			if part_d < 2.2:
				y_lo = lerpf(elder_part_y, elder_base_y, part_d / 2.2)
			else:
				y_lo = lerpf(elder_base_y, eye_y - 2.2, clampf(pow(c_span, exp_p), 0.0, 1.0))
			# Loose outer temple strand framing the upper cheek
			var temple_d := absf(absf(fx - cx) - rx * 0.78)
			if temple_d < 1.6:
				y_lo += (1.6 - temple_d) * 1.6
		else:
			var part_notch_y := eye_y - (11.6 if is_adult_male else 11.2)
			var fringe_base_y := eye_y - (9.6 if is_adult_male else 9.0)
			if part_d < 2.6:
				# Crisp triangular side-part opening exposing upper forehead skin
				y_lo = lerpf(part_notch_y, fringe_base_y, part_d / 2.6)
			elif dx_part >= 0.0:
				var s_t := clampf((dx_part - 2.6) / maxf(1.0, rx * 0.95), 0.0, 1.0)
				# Broad diagonal swept fringe wave across the forehead toward the outer brow
				var base_drop := lerpf(fringe_base_y, brow_top - (1.4 if is_adult_male else 0.8), pow(s_t, 0.78))
				var main_lock := 1.4 * sin(clampf((dx_part - 2.6) / 9.2, 0.0, 1.0) * PI)
				# Crisp V-notch separating the main swept fringe from a loose outer temple strand
				var notch_d := absf(dx_part - 11.8)
				var notch := (1.8 - notch_d) * 1.55 if notch_d < 1.8 else 0.0
				var strand_d := absf(dx_part - 14.8)
				var outer_strand := (2.4 - strand_d) * 1.15 if strand_d < 2.4 else 0.0
				y_lo = base_drop + main_lock - notch + outer_strand
			else:
				var m_t := clampf((-dx_part - 2.6) / maxf(1.0, rx * 0.72), 0.0, 1.0)
				var m_drop := lerpf(fringe_base_y - 0.3, brow_top - 0.8, pow(m_t, 0.80))
				var m_notch_d := absf(-dx_part - 6.0)
				var m_notch := (1.5 - m_notch_d) * 1.35 if m_notch_d < 1.5 else 0.0
				var m_strand_d := absf(-dx_part - 8.6)
				var m_strand := (2.0 - m_strand_d) * 1.05 if m_strand_d < 2.0 else 0.0
				y_lo = m_drop - m_notch + m_strand
		for y in range(maxi(int(floor(y_hi)), 0), mini(int(ceil(y_lo)) + 1, SIZE)):
			var fy := float(y) + 0.5
			var v_rel := (fy - (top - 5.2)) / maxf(13.0, ry * 1.15)
			var lit := clampf(0.86 - u * 0.42 - v_rel * 0.44, 0.12, 0.94)
			# Soft diagonal strand waves instead of a hard horizontal seam
			var flow := sin(dx_part * 0.58 - (fy - top) * 0.32)
			if flow > 0.58 and fy > y_hi + 1.5:
				lit += 0.08
			elif flow < -0.62 and fy > y_hi + 2.0:
				lit -= 0.08
			var band := _shade_band(lit, x, y)
			if fy < y_hi + 2.2 and u < 0.35 and part_d > 1.2:
				band = mini(4, band + 1)
			# Subtle short root shadow at the side part notch
			var part_root_d := absf(fx - (part_x - sweep_dir * (fy - y_hi) * 0.22))
			if part_root_d < 0.95 and fy < y_hi + 3.6:
				band = maxi(1, band - 1)
			# Keep lower fringe edge crisp against forehead skin
			if not open_center and fy > y_lo - 1.2 and u < 0.35:
				band = maxi(2, band)
			_px(x, y, hair_ramp[band])
	if short_cut:
		for dir in [-1.0, 1.0]:
			var tx := cx + float(dir) * (rx * 0.92)
			_hair_capsule(Vector2(tx, eye_y - 5.5), Vector2(tx, eye_y + 0.5), 1.9)

func _moon_strand_lock(a: Vector2, b: Vector2, rad: float) -> void:
	var dir := 1.0 if a.x > cx else -1.0
	var mid := a.lerp(b, 0.46) + Vector2(dir * 1.1, 0.0)
	_hair_capsule(a, mid, rad)
	_hair_capsule(mid, b, maxf(1.9, rad * 0.84))

func _moon_hair(front: bool) -> void:
	if not front:
		if not sex_f and (stage == "young" or stage == "adult"):
			_hair_ellipse(Vector2(cx - 0.4, cy - ry * 0.46), rx * 1.12, ry * 0.44)
		elif stage == "elder" and not sex_f:
			_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.34), rx * 1.10, ry * 0.50)
			_moon_strand_lock(Vector2(cx - rx * 0.94, eye_y + 3.0), Vector2(cx - rx * 1.02, torso_y + 9.0), 2.7)
			_moon_strand_lock(Vector2(cx + rx * 0.90, eye_y + 3.0), Vector2(cx + rx * 0.98, torso_y + 9.0), 2.5)
		elif stage == "elder" and sex_f:
			_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.22), rx * 1.16, ry * 0.70)
			_hair_ellipse(Vector2(cx, chin_y + 1.0), rx * 0.86, 13.0)
		else:
			_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.14), rx * 1.20, ry * 0.82)
			_hair_ellipse(Vector2(cx, chin_y + 2.0), rx * 0.98, 16.0)
		return
	if sex_f and stage == "young":
		_elf_crown_and_fringe(cx - 4.2, 1.0, false, false)
		_moon_strand_lock(Vector2(cx - rx * 0.94, eye_y - 3.0), Vector2(cx - rx * 1.02, 93.0), 3.1)
		_moon_strand_lock(Vector2(cx + rx * 0.90, eye_y - 3.0), Vector2(cx + rx * 0.98, 93.0), 2.9)
	elif sex_f and stage == "elder":
		_elf_crown_and_fringe(cx - 1.5, -1.0, true, false)
		var b_a := Vector2(cx - rx * 0.96, eye_y + 3.0)
		var b_b := Vector2(cx - rx * 1.08, 93.0)
		_hair_capsule(b_a, b_b, 3.4)
		_braid_strands(b_a, b_b)
		var other_x := cx + rx * 0.92
		_moon_strand_lock(Vector2(other_x, eye_y + 3.0), Vector2(other_x + 0.6, mouth_y + 5.0), 2.3)
	elif sex_f:
		_elf_crown_and_fringe(cx - 4.0, 1.0, false, false)
		_moon_strand_lock(Vector2(cx - rx * 0.94, eye_y - 2.0), Vector2(cx - rx * 1.00, 90.0), 3.0)
		_moon_strand_lock(Vector2(cx + rx * 0.90, eye_y - 2.0), Vector2(cx + rx * 0.96, 88.0), 2.8)
	elif stage == "young":
		_elf_crown_and_fringe(cx - 4.5, 1.0, false, true)
	elif stage == "elder":
		_elf_crown_and_fringe(cx - 1.0, 1.0, true, false)
	else:
		_elf_crown_and_fringe(cx + 4.0, -1.0, false, true)

func _dark_elder_male_hair() -> void:
	var top := cy - ry
	var w_mult := 1.08
	var part_x := cx - 5.2
	var sweep_dir := 1.0
	var x0 := int(floor(cx - rx * w_mult))
	var x1 := int(ceil(cx + rx * (w_mult - 0.02)))
	for x in range(maxi(x0, 0), mini(x1 + 1, SIZE)):
		var fx := float(x) + 0.5
		var u := (fx - (cx - 0.2)) / (rx * w_mult)
		if absf(u) > 1.0:
			continue
		var dx_part := (fx - part_x) * sweep_dir
		var part_d := absf(fx - part_x)
		# Asymmetric side-swept masculine crown (no centre part)
		var cleft := 2.0 * clampf(1.0 - part_d / 2.6, 0.0, 1.0)
		var puff := 4.4 if dx_part >= 0.0 else 3.2
		var wave_bump := 1.0 * sin(clampf(absf(dx_part) / (rx * 0.88), 0.0, 1.0) * PI)
		var dome := (ry * 0.43) * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
		var y_hi := top - puff - wave_bump + dome + cleft
		# Swept-back masculine hairline keeping forehead open for elder creases & heavy brows
		var y_lo := eye_y - 11.4
		if part_d < 2.2:
			y_lo = lerpf(eye_y - 12.4, eye_y - 11.2, part_d / 2.2)
		elif dx_part >= 0.0:
			var s_t := clampf((dx_part - 2.2) / maxf(1.0, rx * 1.15), 0.0, 1.0)
			y_lo = lerpf(eye_y - 11.2, eye_y - 4.5, pow(s_t, 1.65))
		else:
			var m_t := clampf((-dx_part - 2.2) / maxf(1.0, rx * 0.62), 0.0, 1.0)
			y_lo = lerpf(eye_y - 11.2, eye_y - 4.5, pow(m_t, 1.45))
		for y in range(maxi(int(floor(y_hi)), 0), mini(int(ceil(y_lo)) + 1, SIZE)):
			var fy := float(y) + 0.5
			var v_rel := (fy - (top - 4.8)) / maxf(12.0, ry * 1.10)
			var lit := clampf(0.86 - u * 0.42 - v_rel * 0.44, 0.12, 0.94)
			var flow := sin(dx_part * 0.58 - (fy - top) * 0.32)
			if flow > 0.58 and fy > y_hi + 1.5:
				lit += 0.08
			elif flow < -0.62 and fy > y_hi + 2.0:
				lit -= 0.08
			var band := _shade_band(lit, x, y)
			if fy < y_hi + 2.0 and u < 0.35 and part_d > 1.2:
				band = mini(4, band + 1)
			var part_root_d := absf(fx - (part_x - sweep_dir * (fy - y_hi) * 0.22))
			if part_root_d < 0.95 and fy < y_hi + 3.4:
				band = maxi(1, band - 1)
			_px(x, y, hair_ramp[band])
	for dir in [-1.0, 1.0]:
		var tx := cx + float(dir) * (rx * 0.92)
		_hair_capsule(Vector2(tx, eye_y - 5.5), Vector2(tx, eye_y + 0.5), 1.9)

func _dark_hair(front: bool) -> void:
	if not front:
		if stage == "elder" and not sex_f:
			_hair_ellipse(Vector2(cx - 0.4, cy - ry * 0.44), rx * 1.06, ry * 0.40)
		elif stage == "elder" and sex_f:
			_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.24), rx * 1.14, ry * 0.68)
			_hair_ellipse(Vector2(cx, chin_y), rx * 0.82, 12.0)
		elif not sex_f and stage == "adult":
			_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.34), rx * 1.14, ry * 0.52)
		elif stage == "young" and not sex_f:
			_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.42), rx * 1.12, ry * 0.46)
		else:
			_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.14), rx * 1.20, ry * 0.80)
			_hair_ellipse(Vector2(cx, chin_y + 2.0), rx * 0.96, 16.0)
		return
	if sex_f and stage == "elder":
		_elf_crown_and_fringe(cx + 1.5, -1.0, true, false)
		var braid_a := Vector2(cx - rx * 1.02, eye_y + 3.5)
		var braid_b := Vector2(cx - rx * 1.08, 93.0)
		_hair_capsule(braid_a, braid_b, 3.4)
		_braid_strands(braid_a, braid_b)
		var other_dx := cx + rx * 0.96
		_moon_strand_lock(Vector2(other_dx, eye_y + 3.5), Vector2(other_dx + 0.6, mouth_y + 4.0), 2.2)
	elif sex_f and stage == "young":
		_elf_crown_and_fringe(cx - 4.2, 1.0, false, false)
		_moon_strand_lock(Vector2(cx - rx * 0.94, eye_y - 2.0), Vector2(cx - rx * 1.02, 93.0), 3.1)
		_moon_strand_lock(Vector2(cx + rx * 0.90, eye_y - 2.0), Vector2(cx + rx * 0.98, 91.0), 2.9)
	elif sex_f:
		_elf_crown_and_fringe(cx - 4.0, 1.0, false, false)
		_moon_strand_lock(Vector2(cx - rx * 0.94, eye_y - 2.0), Vector2(cx - rx * 1.00, 89.0), 2.9)
	elif stage == "young":
		_elf_crown_and_fringe(cx - 4.2, 1.0, false, true)
	elif stage == "elder":
		_dark_elder_male_hair()
	else:
		_elf_crown_and_fringe(cx + 4.0, -1.0, false, false)
		_moon_strand_lock(Vector2(cx - rx * 0.94, eye_y - 2.0), Vector2(cx - rx * 0.98, mouth_y + 4.0), 2.2)
		var db_a := Vector2(cx + rx * 0.94, eye_y + 3.0)
		var db_b := Vector2(cx + rx * 1.04, 92.0)
		_hair_capsule(db_a, db_b, 3.2)
		_braid_strands(db_a, db_b)

func _troll_clump(a: Vector2, b: Vector2, r0: float, r1: float, tip_strands: bool = true) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(r0 + 2.0, r0 + 2.0)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(r0 + 2.0, r0 + 2.0)
	var seg := b - a
	var seg_len := maxf(0.001, seg.length())
	var tang := seg / seg_len
	var norm := Vector2(-tang.y, tang.x)
	if norm.y > 0.2 and absf(norm.x) < 0.5:
		norm = -norm
	for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)) + 1, SIZE)):
		for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)) + 1, SIZE)):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var c := Geometry2D.get_closest_point_to_segment(p, a, b)
			var t := clampf(a.distance_to(c) / seg_len, 0.0, 1.0)
			var rad := lerpf(r0, r1, t)
			var d := p.distance_to(c)
			if d > rad:
				continue
			var across := (p - c).dot(norm) / maxf(0.8, rad)
			var band := 2
			if across < -0.32:
				band = 4 if ((x + y) & 1) == 0 else 3
			elif across < 0.15:
				band = 3 if ((x + y) & 1) == 0 else 2
			elif across < 0.58:
				band = 2 if ((x + y) & 1) == 0 else 1
			else:
				band = 0
			if t > 0.82 and d > rad * 0.55:
				band = maxi(0, band - 1)
			_px(x, y, hair_ramp[band])
	if tip_strands:
		var tip := b + tang * 1.4
		_px(int(round(tip.x)), int(round(tip.y)), hair_ramp[3])
		_px(int(round(b.x + norm.x * 1.2)), int(round(b.y + norm.y * 1.2)), hair_ramp[4])

func _troll_hair(front: bool) -> void:
	var top := cy - ry
	if not sex_f:
		if not front or stage == "elder":
			return
		if stage == "adult":
			# Adult male mohawk: thick multi-tone spiky clumps with ragged scalp root line & loose strands
			for dx in range(-8, 9):
				var root_drop := posmod(absi(dx) * 3 + seed, 3)
				for dy in range(0, 3 + root_drop):
					if posmod(dx + dy, 4) == 0 and dy >= 2:
						continue
					var rx_p := int(round(cx)) + dx
					var ry_p := int(round(top)) + 1 + dy
					var r_band := 3 if dx < -1 else (2 if dx < 3 else 1)
					if dy == 2 + root_drop:
						r_band = 0
					_px(rx_p, ry_p, hair_ramp[r_band])
			_troll_clump(Vector2(cx - 5.2, top + 3.0), Vector2(cx - 8.2, top - 2.5), 2.6, 1.1)
			_troll_clump(Vector2(cx + 4.8, top + 3.0), Vector2(cx + 7.8, top - 2.0), 2.6, 1.1)
			_troll_clump(Vector2(cx - 2.6, top + 2.5), Vector2(cx - 5.0, top - 6.8), 2.9, 1.2)
			_troll_clump(Vector2(cx + 2.4, top + 2.5), Vector2(cx + 4.8, top - 6.2), 2.9, 1.2)
			_troll_clump(Vector2(cx - 0.2, top + 2.5), Vector2(cx - 0.6, top - 9.5), 3.1, 1.2)
			# Loose flyaway strands
			_px(int(cx) - 10, int(top) - 1, hair_ramp[3])
			_px(int(cx) - 9, int(top), hair_ramp[2])
			_px(int(cx) + 9, int(top) - 1, hair_ramp[2])
			_px(int(cx) + 10, int(top), hair_ramp[1])
		else:
			# Young male tuft: fuller ragged multi-tone clumps with loose strands
			for dx in range(-8, 9):
				var r_drop := posmod(absi(dx) * 2 + seed, 3)
				for dy in range(0, 2 + r_drop):
					if posmod(dx * 3, 5) == 0 and dy == 1 + r_drop:
						continue
					_px(int(cx) + dx, int(top) + 1 + dy, hair_ramp[3 if dx < 0 else 1])
			_troll_clump(Vector2(cx - 4.8, top + 2.5), Vector2(cx - 8.2, top - 2.5), 2.6, 1.1)
			_troll_clump(Vector2(cx + 4.4, top + 2.5), Vector2(cx + 7.8, top - 2.0), 2.6, 1.1)
			_troll_clump(Vector2(cx - 1.8, top + 2.0), Vector2(cx - 3.8, top - 6.2), 2.9, 1.2)
			_troll_clump(Vector2(cx + 1.6, top + 2.0), Vector2(cx + 3.6, top - 5.8), 2.8, 1.2)
		return
	# Female troll hair (young and elder): swept multi-tone clumps, ragged hairline, and loose strands
	var is_elder := stage == "elder"
	if not front:
		_troll_clump(Vector2(cx - rx * 0.78, eye_y - 2.0), Vector2(cx - rx * 0.94, chin_y + (3.0 if is_elder else 6.0)), 3.2, 1.8)
		_troll_clump(Vector2(cx + rx * 0.76, eye_y - 2.0), Vector2(cx + rx * 0.92, chin_y + (3.0 if is_elder else 6.0)), 3.1, 1.7)
		return
	var part_x := cx - 3.5 if not is_elder else cx - 2.0
	var w_span := int(rx * (0.76 if is_elder else 0.84))
	for dx in range(-w_span, w_span + 1):
		var x := int(round(cx)) + dx
		var fx := float(x)
		var u := float(dx) / float(maxi(1, w_span))
		var part_d := absf(fx - part_x)
		var clump_id := int(floor((fx - part_x + 24.0) / 5.0))
		var top_phase := fposmod(fx - part_x + 24.0, 5.0) / 5.0
		var clump_arch := 1.5 * sin(top_phase * PI)
		var dome := (ry * 0.36) * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
		var y_hi := top - (2.4 if is_elder else 3.4) + dome - clump_arch
		if part_d < 2.4:
			y_hi += 2.2 - part_d * 0.75
		var jag := 2.6 * sin(top_phase * PI) + float(posmod(clump_id * 3 + seed, 3)) * 0.7
		var base_lo := (eye_y - 11.0) if is_elder else (eye_y - 9.4)
		var y_lo := base_lo + jag + absf(u) * (3.0 if is_elder else 2.5)
		if part_d < 2.6:
			y_lo = base_lo - 1.4
		elif is_elder and absf(dx) <= 5:
			y_lo = minf(y_lo, eye_y - 10.0)
		for y in range(maxi(int(floor(y_hi)), 0), mini(int(ceil(y_lo)) + 1, SIZE)):
			if float(y) > cy - ry * 0.25 and not _probe(fx + 0.5, float(y) + 0.5):
				continue
			# Diagonal swept clump flow from the scalp part instead of vertical bars
			var sweep_s := 1.0 if fx >= part_x else -1.0
			var flow_coord := (fx - part_x) * sweep_s - (float(y) - top) * 0.65
			var c_phase := fposmod(flow_coord + 20.0, 5.2) / 5.2
			var v_rel := (float(y) - (top - 3.0)) / 14.0
			var lit := clampf(0.82 - u * 0.36 - v_rel * 0.34, 0.14, 0.92)
			if c_phase < 0.32:
				lit += 0.18
			elif c_phase > 0.76:
				lit -= 0.22
			var band := _shade_band(lit, x, y)
			if float(y) < y_hi + 1.5 and c_phase < 0.68 and dx < 4:
				band = 4
			elif c_phase > 0.84 or float(y) > y_lo - 1.0:
				band = 0 if c_phase > 0.75 else maxi(1, band - 1)
			_px(x, y, hair_ramp[band])
	# Swept multi-tone temple & shoulder clumps with loose strands
	_troll_clump(Vector2(part_x - 2.0, top + 0.5), Vector2(cx - rx * 0.72, eye_y - 5.0), 2.6, 1.5)
	_troll_clump(Vector2(part_x + 2.5, top + 0.5), Vector2(cx + rx * 0.70, eye_y - 5.0), 2.7, 1.5)
	_troll_clump(Vector2(cx - rx * 0.72, eye_y - 5.0), Vector2(cx - rx * 0.86, mouth_y + 1.0), 2.7, 1.8)
	_troll_clump(Vector2(cx - rx * 0.86, mouth_y + 1.0), Vector2(cx - rx * 0.80, chin_y + (2.0 if is_elder else 6.0)), 1.9, 1.0)
	_troll_clump(Vector2(cx + rx * 0.68, eye_y - 5.0), Vector2(cx + rx * 0.84, mouth_y + 2.0), 2.8, 1.9)
	_troll_clump(Vector2(cx + rx * 0.84, mouth_y + 2.0), Vector2(cx + rx * 0.78, chin_y + (3.0 if is_elder else 7.0)), 2.0, 1.0)
	# Loose cheek strands
	_troll_clump(Vector2(cx - rx * 0.58, eye_y - 6.0), Vector2(cx - rx * 0.68, eye_y + 3.0), 1.7, 0.8)
	_troll_clump(Vector2(cx + rx * 0.54, eye_y - 6.0), Vector2(cx + rx * 0.64, eye_y + 3.5), 1.7, 0.8)

func _goblin_braid_column(ax: float, ay: float, bx: float, by_end: float) -> void:
	var y0 := int(round(ay))
	var y1 := int(round(by_end))
	var span := float(maxi(1, y1 - y0))
	for y in range(maxi(y0, 0), mini(y1 + 1, SIZE)):
		var t := float(y - y0) / span
		var cx_b := lerpf(ax, bx, t) + sin(float(y) * 0.45) * 0.4
		var ix := int(round(cx_b))
		var seg := posmod(y - y0, 4)
		var knot_left := posmod(int((y - y0) / 4), 2) == 0
		if y >= y1 - 7:
			# Tapered multi-strand brush tip
			var tip_w := maxi(1, int(round(lerpf(2.5, 0.8, float(y - (y1 - 7)) / 7.0))))
			for dx in range(-tip_w, tip_w + 1):
				var b_tip := 4 if dx < 0 else (2 if dx == 0 else 0)
				_px(ix + dx, y, hair_ramp[b_tip])
			continue
		if y == y1 - 8 or y == y1 - 9:
			# Gold/sec braid clasp ring
			for dx in range(-2, 3):
				_px(ix + dx, y, _op(sec.lightened(0.18)) if dx <= 0 else _op(sec.darkened(0.22)))
			continue
		for dx in range(-3, 4):
			if absi(dx) == 3 and (seg == 0 or seg == 3):
				continue
			var band := 2
			if seg == 0:
				band = 0 if absi(dx) <= 1 else 1
			elif seg == 1:
				if knot_left:
					band = 4 if (dx == -1 or dx == 0) else (3 if dx == -2 else (2 if dx == 1 else 0))
				else:
					band = 4 if (dx == 0 or dx == 1) else (3 if dx == -1 else (2 if dx == 2 else 0))
			elif seg == 2:
				if knot_left:
					band = 4 if dx == -1 else (3 if (dx == 0 or dx == -2) else (1 if dx == 1 else 0))
				else:
					band = 4 if dx == 1 else (3 if (dx == 0 or dx == 2) else (1 if dx == -1 else 0))
			else:
				band = 3 if dx == 0 else (2 if absi(dx) == 1 else 0)
			_px(ix + dx, y, hair_ramp[band])

func _goblin_hair(front: bool) -> void:
	var top := cy - ry
	if not sex_f:
		if not front:
			if stage == "young":
				_hair_ellipse(Vector2(cx - 0.3, cy - ry * 0.44), rx * 1.16, ry * 0.54)
			elif stage == "elder":
				_hair_ellipse(Vector2(cx - 0.3, cy - ry * 0.48), rx * 1.12, ry * 0.46)
			return
		if stage == "elder":
			# Rounded silver-grey crown tuft rising above skull + bushy receding temple locks with ragged hairline
			var w_e := int(rx * 1.10)
			for dx in range(-w_e, w_e + 1):
				var x := int(round(cx)) + dx
				var fx := float(x)
				var u := float(dx) / float(maxi(1, w_e))
				var dome_e := (ry * 0.38) * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
				var tuft_wave := 1.8 * sin(fposmod(float(dx + 16), 5.0) / 5.0 * PI)
				var y_hi_e := top - 5.8 + dome_e - tuft_wave
				# Deep receding M-notches keeping center forehead open (y <= 26) for elder wrinkles, ragged side locks
				var lock_ph_e := fposmod(float(dx + 18), 4.0) / 4.0
				var jag_e := 3.2 * sin(lock_ph_e * PI) if lock_ph_e >= 0.25 else -1.5
				var y_lo_e: float
				if absi(dx) <= 6:
					if absi(dx) >= 3 and absi(dx) <= 5:
						y_lo_e = top + 0.2
					else:
						y_lo_e = (eye_y - 14.5) + maxf(-1.0, jag_e * 0.65)
				else:
					var side_t := clampf(( float(absi(dx)) - 6.0) / maxf(1.0, float(w_e - 6)), 0.0, 1.0)
					y_lo_e = lerpf(eye_y - 13.0, eye_y - 5.2, side_t) + jag_e
				for y in range(maxi(int(floor(y_hi_e)), 0), mini(int(ceil(y_lo_e)) + 1, SIZE)):
					if float(y) > cy - ry * 0.18 and not _probe(fx + 0.5, float(y) + 0.5):
						continue
					var h_e := maxf(3.0, y_lo_e - y_hi_e)
					var vn_e := clampf((float(y) - y_hi_e) / h_e, 0.0, 1.0)
					var sw_e := sin(float(dx) * 1.15 - (float(y) - y_hi_e) * 0.52)
					var band_e := 2
					if vn_e < 0.16:
						band_e = 3 if dx <= 2 else 2
					elif vn_e < 0.50:
						band_e = (4 if sw_e > -0.20 else 3) if dx <= 3 else (3 if sw_e > 0.10 else 2)
					elif vn_e < 0.78:
						band_e = 3 if sw_e > 0.30 else (1 if sw_e < -0.30 else 2)
					else:
						band_e = 2 if sw_e > 0.38 else (0 if (vn_e > 0.88 or sw_e < -0.15) else 1)
					_px(x, y, hair_ramp[band_e])
			_troll_clump(Vector2(cx - 2.0, top + 0.5), Vector2(cx - 5.2, top - 6.5), 2.5, 1.1)
			_troll_clump(Vector2(cx + 1.8, top + 0.5), Vector2(cx + 4.8, top - 6.0), 2.4, 1.1)
			_troll_clump(Vector2(cx - rx * 0.80, eye_y - 8.5), Vector2(cx - rx * 0.90, eye_y - 1.5), 2.2, 1.0)
			_troll_clump(Vector2(cx + rx * 0.78, eye_y - 8.5), Vector2(cx + rx * 0.88, eye_y - 1.5), 2.2, 1.0)
			return
		if stage == "adult":
			# Adult male topknot: visible scalp roots pulling up into tie + fuller highlighted plumes
			var knot_y := top - 0.5
			for dx in range(-8, 9):
				var u_r := float(dx) / 8.0
				var r_top := int(round(knot_y + absf(u_r) * 1.8))
				var r_bot := int(round(top + 4.5 - absf(u_r) * 1.2 + float(posmod(absi(dx) * 3, 2))))
				for y in range(r_top, r_bot + 1):
					if not _probe(cx + float(dx) + 0.5, float(y) + 0.5):
						continue
					var strand_mod := posmod(dx + y, 3)
					if y == r_bot and strand_mod == 0:
						continue
					var r_band := 3 if strand_mod == 0 else (2 if strand_mod == 1 else 1)
					if dx < -1 and strand_mod == 0:
						r_band = 4
					_px(int(cx) + dx, y, hair_ramp[r_band])
			# Fuller spiky highlighted topknot plumes fanning from the root tie
			_troll_clump(Vector2(cx - 2.2, knot_y), Vector2(cx - 6.8, top - 6.8), 2.7, 1.2)
			_troll_clump(Vector2(cx + 2.2, knot_y), Vector2(cx + 6.8, top - 6.2), 2.7, 1.2)
			_troll_clump(Vector2(cx, knot_y), Vector2(cx - 0.4, top - 9.2), 3.0, 1.2)
			_troll_clump(Vector2(cx + 2.8, knot_y + 0.5), Vector2(cx + 8.2, top - 3.2), 2.2, 1.0)
			# Crisp leather/gold root tie band at base of topknot
			var tie_y := int(round(knot_y))
			for dx in range(-3, 4):
				_px(int(cx) + dx, tie_y, _op(sec.lightened(0.12)) if dx <= 0 else _op(sec.darkened(0.25)))
				_px(int(cx) + dx, tie_y + 1, _op(sec.darkened(0.32)))
			return
		# Young male goblin: tall rounded crown volume, bold highlight/shadow bands, strand grooves, broken ragged hairline
		var part_m := cx - 4.0
		var w_lim := int(rx * 1.14)
		for dx in range(-w_lim, w_lim + 1):
			var x := int(round(cx)) + dx
			var fx := float(x)
			var u := float(dx) / float(maxi(1, w_lim))
			var part_dm := absf(fx - part_m)
			var cleft_m := 2.4 * clampf(1.0 - part_dm / 2.6, 0.0, 1.0)
			var lobe_m := 1.8 * sin(clampf(part_dm / (rx * 0.85), 0.0, 1.0) * PI)
			var lock_w := fposmod(float(dx + 18), 4.5) / 4.5
			var lock_id := int(floor(float(dx + 18) / 4.5))
			var crown_bump := 1.5 * sin(lock_w * PI)
			var dome := (ry * 0.38) * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
			var y_hi := top - 6.6 + dome + cleft_m - lobe_m - crown_bump
			# Broken ragged hairline: deep upward V-notches exposing forehead skin alternating with pointed hanging locks
			var y_lo: float
			if part_dm < 2.2:
				y_lo = lerpf(eye_y - 13.8, eye_y - 11.2, part_dm / 2.2)
			elif lock_w < 0.30:
				y_lo = (eye_y - 12.6) + absf(u) * 1.8
			else:
				var tooth := 5.2 * sin(((lock_w - 0.30) / 0.70) * PI) + float(posmod(lock_id * 3, 2)) * 1.1
				y_lo = (eye_y - 12.2) + tooth + absf(u) * 2.0
			for y in range(maxi(int(floor(y_hi)), 0), mini(int(ceil(y_lo)) + 1, SIZE)):
				if float(y) > cy - ry * 0.15 and not _probe(fx + 0.5, float(y) + 0.5):
					continue
				var h_col := maxf(3.0, y_lo - y_hi)
				var v_norm := clampf((float(y) - y_hi) / h_col, 0.0, 1.0)
				var sweep_m := 1.0 if fx >= part_m else -1.0
				var s_coord := (fx - part_m) * sweep_m * 0.85 - (float(y) - y_hi) * 0.48
				var sw := sin(s_coord * 1.45)
				var band := 2
				if v_norm < 0.14:
					band = 3 if u < 0.25 else 2
				elif v_norm < 0.48:
					if u < 0.35 and part_dm > 1.2:
						band = 4 if sw > -0.22 else 3
					else:
						band = 3 if sw > 0.08 else 2
				elif v_norm < 0.76:
					band = (4 if u < -0.15 else 3) if sw > 0.32 else (1 if sw < -0.32 else 2)
				else:
					band = 2 if sw > 0.38 else (0 if (v_norm > 0.88 or sw < -0.18) else 1)
				if part_dm < 1.2 and float(y) < y_hi + 4.5:
					band = 0 if float(y) > y_hi + 1.8 else 1
				_px(x, y, hair_ramp[band])
		# Sculpted rounded crown locks & distinct ragged sideburns
		_troll_clump(Vector2(part_m - 1.5, top - 3.5), Vector2(cx - rx * 0.78, eye_y - 9.0), 2.5, 1.3)
		_troll_clump(Vector2(part_m + 2.0, top - 4.2), Vector2(cx + rx * 0.74, eye_y - 9.0), 2.7, 1.4)
		for side in [-1, 1]:
			var iside := int(side)
			var sb_x := int(round(cx + float(iside) * (rx * 0.86)))
			var sb_top := int(round(eye_y - 5.0))
			for dy in range(0, 10):
				var w_sb := 2 if dy < 5 else (1 if dy < 8 else 0)
				for k in range(0, w_sb + 1):
					var sx: int = sb_x - iside * k
					var sy: int = sb_top + dy
					var sb_band := 3 if (iside < 0 and k == 0 and dy < 6) else (2 if k == 0 else 0)
					if dy >= 8:
						sb_band = 0
					_px(sx, sy, hair_ramp[sb_band])
		return
	# Female goblin (young & elder): tall rounded crown volume, strong highlight/shadow bands, strand texture, broken ragged hairline
	var is_elder_f := stage == "elder"
	if not front:
		_hair_ellipse(Vector2(cx - 0.3, cy - ry * 0.44), rx * 1.18, ry * 0.56)
		_hair_ellipse(Vector2(cx - 0.5, cy - ry * 0.22), rx * 1.15, ry * 0.66)
		return
	var part_x := cx - 3.5 if not is_elder_f else cx - 2.0
	var w_f := int(rx * 1.18)
	for dx in range(-w_f, w_f + 1):
		var x := int(round(cx)) + dx
		var fx := float(x)
		var u := float(dx) / float(maxi(1, w_f))
		var part_d := absf(fx - part_x)
		var dome := (ry * 0.38) * (1.0 - sqrt(maxf(0.0, 1.0 - u * u)))
		var cleft := 2.6 * clampf(1.0 - part_d / 2.8, 0.0, 1.0)
		var wave := 2.0 * sin(clampf(part_d / (rx * 0.88), 0.0, 1.0) * PI)
		var clump_f := 1.2 * sin(fposmod(fx - part_x + 20.0, 4.5) / 4.5 * PI)
		var y_hi := top - 6.8 + dome + cleft - wave - clump_f
		var lock_mod := fposmod(absf(fx - part_x) + 16.0, 4.4) / 4.4
		var lock_idx_f := int(floor((absf(fx - part_x) + 16.0) / 4.4))
		var y_lo: float
		if is_elder_f:
			# Broken ragged hairline staying above y=31 in center so elder forehead wrinkles read clearly
			if part_d < 2.2:
				y_lo = lerpf(eye_y - 14.5, eye_y - 12.2, part_d / 2.2)
			elif lock_mod < 0.32:
				y_lo = (eye_y - 13.8) + pow(absf(u), 1.3) * 3.8
			else:
				var jag_ef := 3.8 * sin(((lock_mod - 0.32) / 0.68) * PI) + float(posmod(lock_idx_f, 2)) * 0.8
				y_lo = (eye_y - 13.4) + jag_ef + pow(absf(u), 1.25) * 4.6
		else:
			if part_d < 2.4:
				y_lo = lerpf(eye_y - 13.8, eye_y - 11.0, part_d / 2.4)
			elif lock_mod < 0.30:
				y_lo = (eye_y - 12.4) + absf(u) * 2.2
			else:
				var jag_f := 4.8 * sin(((lock_mod - 0.30) / 0.70) * PI) + float(posmod(lock_idx_f * 3, 2)) * 1.0
				y_lo = (eye_y - 11.8) + jag_f + absf(u) * 2.4
		for y in range(maxi(int(floor(y_hi)), 0), mini(int(ceil(y_lo)) + 1, SIZE)):
			var h_f := maxf(3.0, y_lo - y_hi)
			var vn_f := clampf((float(y) - y_hi) / h_f, 0.0, 1.0)
			var sweep_f := 1.0 if fx >= part_x else -1.0
			var flow_f := (fx - part_x) * sweep_f * 0.82 - (float(y) - y_hi) * 0.46
			var sw_f := sin(flow_f * 1.45)
			var band := 2
			if vn_f < 0.14:
				band = 3 if u < 0.25 else 2
			elif vn_f < 0.48:
				if u < 0.38 and part_d > 1.2:
					band = 4 if sw_f > -0.25 else 3
				else:
					band = 3 if sw_f > 0.05 else 2
			elif vn_f < 0.76:
				band = (4 if u < -0.12 else 3) if sw_f > 0.30 else (1 if sw_f < -0.30 else 2)
			else:
				band = 2 if sw_f > 0.36 else (0 if (vn_f > 0.88 or sw_f < -0.18) else 1)
			if part_d < 1.3 and float(y) < y_hi + 4.8:
				band = 0 if float(y) > y_hi + 1.8 else 1
			_px(x, y, hair_ramp[band])
	# Sculpted crown waves, highlighted braids & loose cheek strands
	_troll_clump(Vector2(part_x - 1.8, top - 3.8), Vector2(cx - rx * 0.82, eye_y - 6.5), 2.6, 1.4)
	_troll_clump(Vector2(part_x + 2.2, top - 4.2), Vector2(cx + rx * 0.80, eye_y - 6.5), 2.7, 1.4)
	_goblin_braid_column(cx - rx * 0.86, eye_y - 5.0, cx - rx * 0.96, 92.0)
	if is_elder_f:
		_troll_clump(Vector2(cx + rx * 0.84, eye_y - 5.0), Vector2(cx + rx * 0.92, mouth_y + 4.0), 2.6, 1.3)
	else:
		_goblin_braid_column(cx + rx * 0.84, eye_y - 5.0, cx + rx * 0.94, 92.0)
	# Loose highlighted temple strands framing the face
	_troll_clump(Vector2(cx - rx * 0.70, eye_y - 5.0), Vector2(cx - rx * 0.76, eye_y + 4.0), 1.7, 0.9)
	_troll_clump(Vector2(cx + rx * 0.68, eye_y - 5.0), Vector2(cx + rx * 0.74, eye_y + 4.0), 1.7, 0.9)

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
			_leaf_ear(dir, near, 14.5 * sc, 5.0 * sc, 1.65 * sc)
		"dark":
			_leaf_ear(dir, near, 10.5 * sc, 6.0 * sc, 2.1 * sc)
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
	if ear_k == "dark":
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
	var inner_rad := 1.05 if ear_k == "high" or ear_k == "moon" else 1.55
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
				var shade := skin_ramp[2] if ear_k == "high" or ear_k == "moon" else skin_ramp[0]
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
	if race == "troll":
		_troll_eye(x0, y0, near)
		return
	if race == "goblin":
		_goblin_eye(x0, y0, near)
		return
	var hw := 3 if eye_k >= 0.85 else 2
	var hh := 2 if eye_k >= 0.85 else 1
	if race == "troll":
		hw = 4 if not sex_f else 3
		hh = 2
		if stage == "young":
			hw = 3
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
		lid = Color("#344260")
	elif race == "dark_elf":
		lid = Color("#241b30")
	var iris := EYES.get(race, Color("#4a3422")) as Color
	if race == "moon_elf":
		iris = Color("#3b64cc")
	elif race == "dark_elf" and stage == "elder":
		iris = Color("#b82834")
	elif race == "dark_elf" and sex_f:
		iris = Color("#dc3646")
	elif race == "human" and stage == "elder":
		iris = Color(0.10, 0.06, 0.05, 1.0)
	var lid_y := -hh
	for y in range(-hh - 1, hh + 2):
		for x in range(-hw - 1, hw + 2):
			var nx := float(x) / float(hw + 1)
			var ny := float(y) / float(hh + 1)
			if nx * nx + ny * ny > 1.0:
				continue
			if y <= lid_y:
				_px(x0 + x, y0 + y, lid)
			elif nx * nx + ny * ny > 0.82:
				_px(x0 + x, y0 + y, _op(SCLERA.darkened(0.10)))
			else:
				_px(x0 + x, y0 + y, SCLERA)
	var ix := x0 + (0 if near else 1)
	var iy := y0
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
	if race == "goblin" and sex_f:
		_px(x0 - hw, y0 - hh - 1, OUTLINE)
		_px(x0 - hw + 1, y0 - hh - 2, OUTLINE)
		_px(x0 + hw - 1, y0 - hh - 2, OUTLINE)
		_px(x0 + hw, y0 - hh - 1, OUTLINE)

func _brow(x0: int, y0: int, hw: int, hh: int, near: bool) -> void:
	if race == "troll":
		_troll_brow(x0, y0, hw, hh, near)
		return
	var toward := 1 if near else -1
	if race == "dark_elf" and not sex_f and stage == "elder":
		var by_e := y0 - hh - 2
		for x in range(-hw - 1, hw + 2):
			var s_e := x * toward
			var drop_e := 1 if s_e > 0 else 0
			var arch_e := -1 if absi(x) >= hw else 0
			_px(x0 + x, by_e + drop_e + arch_e, Color("#a8b2ca"))
			_px(x0 + x, by_e + 1 + drop_e + arch_e, Color("#dce4f6"))
		return
	var thick := 1
	if race == "troll":
		thick = 2
		if not sex_f and stage != "young":
			thick = 3
	elif not sex_f and (brow_k >= 1.45 or race == "moon_elf" or (race == "dark_elf" and stage != "young")):
		thick = 2
	var brow_col := hair_ramp[2]
	if race == "troll":
		brow_col = _op(skin.darkened(0.42))
	elif race == "moon_elf":
		if not sex_f:
			brow_col = Color("#263656") if stage != "elder" else Color("#3c4c6e")
		else:
			brow_col = Color("#384a6e") if stage != "elder" else Color("#4e5e80")
	elif race == "dark_elf":
		brow_col = Color("#c8d0e0") if stage == "elder" else Color("#d6dcec")
	elif hair.get_luminance() > 0.72:
		brow_col = hair_ramp[1]
	var by := y0 - hh - thick - (2 if race == "troll" else 0)
	if race == "troll":
		by += 3
	var x_lo := -hw - 1
	var x_hi := hw + 2
	if race == "dark_elf" or race == "moon_elf":
		x_lo = -hw - 1
		x_hi = hw + (1 if sex_f else 2)
	for t in thick:
		for x in range(x_lo, x_hi):
			if (race == "moon_elf" or race == "dark_elf") and thick == 2 and t == 0 and absi(x) >= hw:
				continue
			var drop := 0
			if not sex_f and brow_k >= 1.25 and x * toward > 0:
				drop = 1
			var arch := 0
			if absi(x) >= hw - 1:
				arch = -1
			if (race == "dark_elf" or race == "moon_elf") and sex_f and absi(x) >= maxi(1, hw - 1):
				arch = -1
			var col := brow_col
			if (race == "moon_elf" or race == "dark_elf") and thick == 2 and t == 0:
				col = _op(brow_col.lightened(0.10)) if race == "moon_elf" else Color("#9ea8be")
			elif race == "troll":
				if t == 0:
					col = skin_ramp[3]
				elif t == thick - 1:
					col = skin_ramp[2]
				else:
					col = skin_ramp[3]
			_px(x0 + x, by + t + drop + arch, col)
	if race == "troll":
		for x in range(-hw - 1, hw + 2):
			_px(x0 + x, by - 4, skin_ramp[4])
			_px(x0 + x, by - 3, skin_ramp[3])
			_px(x0 + x, by - 2, skin_ramp[4])
			_px(x0 + x, by - 1, skin_ramp[4])

func _draw_nose() -> void:
	if _lost("nose"):
		return
	if race == "goblin":
		_goblin_nose()
		return
	if race == "troll":
		_troll_nose()
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
			if race == "moon_elf" or race == "dark_elf":
				var br_sh := Color("#46587e") if race == "moon_elf" else skin_ramp[0]
				var nost := Color("#24304c") if race == "moon_elf" else _op(skin_ramp[0].darkened(0.32))
				for i in range(1, 7):
					_px(x - 1, y - i, skin_ramp[4])
					_px(x, y - i, skin_ramp[2])
					_px(x + 1, y - i, skin_ramp[1] if race == "moon_elf" else skin_ramp[0])
				_px(x - 2, y, skin_ramp[2])
				_px(x - 1, y, skin_ramp[4])
				_px(x, y, skin_ramp[3])
				_px(x + 1, y, br_sh)
				_px(x - 2, y + 1, nost)
				_px(x - 1, y + 1, skin_ramp[1])
				_px(x, y + 1, br_sh)
				_px(x + 1, y + 1, nost)
				_px(x + 2, y + 1, br_sh)
			else:
				for i in range(6):
					_px(x, y - i, skin_ramp[2])
					_px(x - 1, y - i, skin_ramp[4])
				_px(x, y + 1, skin_ramp[1])
				_px(x + 1, y + 1, skin_ramp[0])
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
	if race == "troll":
		_troll_mouth()
		return
	if race == "goblin":
		_goblin_mouth()
		return
	var x := int(round(cx + 1.2))
	var y := int(round(mouth_y))
	var hw := 4
	if race in ["dwarf", "orc"]:
		hw = 5
	elif race == "dark_elf":
		hw = 3
		if stage == "adult" and not sex_f:
			hw = 4
	elif race == "moon_elf":
		hw = 4 if not sex_f else 3
	elif race.ends_with("elf"):
		hw = 3
	if sex_f:
		hw = maxi(2, hw - 1)
	var lip_dark := _op(skin.darkened(0.34).lerp(Color("#4a1822"), 0.28))
	var lip := _op(skin.lerp(Color("#a4545c"), 0.42 if sex_f else 0.18))
	if race == "moon_elf":
		lip_dark = Color("#3a4264") if not sex_f else (Color("#464c6c") if stage == "elder" else Color("#48446c"))
		lip = Color("#5c6888") if not sex_f else (Color("#686888") if stage == "elder" else Color("#786894"))
	elif race == "dark_elf":
		lip_dark = Color(0.24, 0.14, 0.24, 1.0)
		lip = Color(0.46, 0.26, 0.36, 1.0) if sex_f else Color(0.38, 0.28, 0.38, 1.0)
		if stage == "elder" and not sex_f:
			lip_dark = _op(skin.darkened(0.32))
			lip = _op(skin.darkened(0.14))
		elif stage == "elder" and sex_f:
			lip_dark = _op(skin.darkened(0.36))
			lip = _op(skin.darkened(0.16).lerp(Color("#442838"), 0.32))
	var thin_elder := (race == "dark_elf" or race == "moon_elf") and stage == "elder" and not sex_f
	for i in range(-hw, hw + 1):
		var dy := _mouth_bend(i, hw)
		_px(x + i, y + dy, lip_dark)
	if not thin_elder:
		for i in range(-(hw - 1), hw):
			var dy2 := _mouth_bend(i, hw)
			_px(x + i, y + 1 + dy2, lip)
	if sex_f and stage != "elder" and not thin_elder:
		for i in range(-(hw - 2), hw - 1):
			_px(x + i, y + 2 + _mouth_bend(i, hw), _op(lip.lightened(0.08)))
	_px(x - hw, y + 1, skin_ramp[1])
	_px(x + hw, y + 1, skin_ramp[0])

func _mouth_bend(i: int, hw: int) -> int:
	var t := float(absi(i)) / float(maxi(1, hw))
	var steps := int(round(t * 2.0))
	if race == "dark_elf" or race == "moon_elf":
		if stage == "elder":
			return int(round(t))
		if stage == "adult" and not sex_f:
			return int(round(t)) if race == "dark_elf" else 0
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

func _goblin_eye(x0: int, y0: int, near: bool) -> void:
	var hw := 3
	var hh := 2
	var iris := Color("#f0a818")
	if stage == "young":
		iris = Color("#ffd438")
	elif stage == "elder":
		iris = Color("#d8921c")
	if sex_f and stage != "elder":
		iris = iris.lightened(0.08)
	if not eyes_open:
		for x in range(-hw, hw + 1):
			_px(x0 + x, y0, skin_ramp[1])
		_goblin_brow(x0, y0, hw, near)
		return
	var lid := _op(skin.darkened(0.50))
	var scl_edge := _op(SCLERA.darkened(0.08))
	for x in range(-hw, hw + 1):
		_px(x0 + x, y0 - 2, lid)
		if absi(x) < hw:
			_px(x0 + x, y0 + 2, skin_ramp[1])
	for y in range(-1, 2):
		for x in range(-hw, hw + 1):
			if absi(x) == hw and y != 0:
				_px(x0 + x, y0 + y, skin_ramp[2] if y > 0 else lid)
				continue
			_px(x0 + x, y0 + y, scl_edge if absi(x) == hw else SCLERA)
	var ix := x0 + (0 if near else 1)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var shade := 0.22 if (dx > 0 or dy > 0) else 0.0
			_px(ix + dx, y0 + dy, _op(iris.darkened(shade)))
	# Strong 2px dark pupil + bright catchlight
	_px(ix, y0, PUPIL)
	_px(ix, y0 + 1, PUPIL)
	_px(ix - 1, y0 - 1, Color(1.0, 0.99, 0.92, 1.0))
	_goblin_brow(x0, y0, hw, near)

func _goblin_brow(x0: int, y0: int, hw: int, near: bool) -> void:
	var toward := 1 if near else -1
	var by := y0 - 4
	var is_elder := stage == "elder"
	var brow_hi := Color("#d0dad2") if is_elder else Color("#2c3824")
	var brow_lo := Color("#7c887e") if is_elder else Color("#141c10")
	for dx in range(-hw - 1, hw + 1):
		var s := dx * toward
		var drop := 1 if s >= 1 else (0 if s >= -1 else (-1 if s == -2 else 0))
		var yy := by + drop
		_px(x0 + dx, yy, brow_lo)
		if is_elder or not sex_f or s >= -1:
			_px(x0 + dx, yy - 1, brow_hi)
		_px(x0 + dx, yy - 2, skin_ramp[4] if dx <= 0 else skin_ramp[3])
	if is_elder:
		# Bushy outer grey brow tuft
		var outer_x := x0 - toward * (hw + 1)
		_px(outer_x, by - 1, Color("#dce4de"))
		_px(outer_x - toward, by, Color("#96a298"))

func _troll_eye(x0: int, y0: int, near: bool) -> void:
	var hw := 3
	var hh := 2
	var iris := Color("#e89624")
	if stage == "young":
		iris = Color("#f6ae2d")
	elif stage == "elder":
		iris = Color("#d48422")
	if not eyes_open:
		for x in range(-hw, hw + 1):
			_px(x0 + x, y0, skin_ramp[1])
			_px(x0 + x, y0 - 1, skin_ramp[2])
		_troll_brow(x0, y0, hw, hh, near)
		return
	# Soft upper eyelid at y0 - 2 (leaving y0 - 3 as a clear skin gap below the separate brow)
	var lid := skin_ramp[1]
	var scl_dim := _op(SCLERA.darkened(0.08))
	for x in range(-hw, hw + 1):
		_px(x0 + x, y0 - 2, skin_ramp[2] if absi(x) == hw else lid)
		_px(x0 + x, y0 - 3, skin_ramp[3] if x <= 0 else skin_ramp[2])
		if absi(x) < hw:
			_px(x0 + x, y0 + 2, skin_ramp[1] if ((x0 + x + y0) & 1) == 0 else skin_ramp[2])
	# Full 3px-tall open eye with visible white sclera on both sides of the iris
	for y in range(-1, 2):
		for x in range(-hw, hw + 1):
			if absi(x) == hw and y != 0:
				_px(x0 + x, y0 + y, skin_ramp[2])
				continue
			_px(x0 + x, y0 + y, scl_dim if absi(x) == hw else SCLERA)
	var ix := x0 + (0 if near else 1)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var shade := 0.20 if (dx > 0 or dy > 0) else 0.0
			_px(ix + dx, y0 + dy, _op(iris.darkened(shade)))
	_px(ix, y0, PUPIL)
	_px(ix, y0 + 1, PUPIL)
	_px(ix - 1, y0 - 1, Color(1.0, 0.995, 0.95, 1.0))
	_troll_brow(x0, y0, hw, hh, near)

func _troll_brow(x0: int, y0: int, hw: int, _hh: int, near: bool) -> void:
	# Separate organic brow ridges per eye with a clear 2-3px dark hair-coloured brow line on top, wide skin gap over nose
	var toward := 1 if near else -1
	var bridge_x := int(round((eye_near.x + eye_far.x) * 0.5))
	var y_base := y0 - 4
	var ridge_hi := _op(skin_ramp[4].lightened(0.15))
	var brow_dk := Color("#222a24") if stage == "elder" else _op(hair_ramp[0].darkened(0.16))
	var brow_mid := Color("#364238") if stage == "elder" else hair_ramp[0]
	var brow_hi := Color("#505e52") if stage == "elder" else hair_ramp[1]
	var dx_lo := -(hw + 1) if near else -hw
	var dx_hi := hw if near else (hw + 1)
	for dx in range(dx_lo, dx_hi + 1):
		var wx := x0 + dx
		# Keep a clean skin gap over the nose bridge between the two separate brows
		if absi(wx - bridge_x) <= 2:
			continue
		var s := dx * toward
		var arch := 0
		if s == -1 or s == 0:
			arch = -1
		elif s <= -3 or s >= 2:
			arch = 1
		var ridge_bump := 1 if (s == -2 or s == 0 or (s == 2 and not sex_f)) else 0
		var yb := y_base + arch
		var b_thick := 3 if (not sex_f and stage != "young" and s > -4) else (3 if (not sex_f and (s == -1 or s == 0)) else 2)
		for t in range(b_thick):
			var py := yb - t
			var b_col := brow_dk
			if t == 1:
				b_col = brow_dk if (b_thick == 3 and dx > 0) else brow_mid
			elif t >= 2:
				b_col = brow_hi if dx <= 0 else brow_mid
			_px(wx, py, b_col)
		# Organic lit brow ridge crest above the 2-3px dark brow line
		var crest_y := yb - b_thick
		_px(wx, crest_y, ridge_hi if (ridge_bump > 0 and dx <= 0) else skin_ramp[4])
		if ridge_bump > 0:
			_px(wx, crest_y - 1, skin_ramp[3] if dx <= 0 else skin_ramp[2])
	if near:
		# Dithered skin-tone glabella gap over the nose bridge between the two brow bumps
		for gx in range(bridge_x - 2, bridge_x + 3):
			for gy in range(y_base - 3, y_base + 2):
				var g_band := 3 if gx < bridge_x else 2
				if absi(gx - bridge_x) == 2 and gy >= y_base - 2:
					g_band = 1 if ((gx + gy) & 1) == 0 else 2
				elif ((gx + gy) & 1) == 0 and gx <= bridge_x:
					g_band = mini(4, g_band + 1)
				_px(gx, gy, skin_ramp[g_band])

func _troll_nose() -> void:
	var nx := int(round(cx + 0.5))
	var y_top := int(round(eye_y)) + 1
	var y_tip := int(round(mouth_y)) - 5
	var nostril := _op(skin_ramp[0].darkened(0.32))
	# Sculpted nasal bridge from below brow gap to nose tip
	for y in range(y_top, y_tip - 1):
		_px(nx - 2, y, skin_ramp[1])
		_px(nx - 1, y, skin_ramp[4])
		_px(nx, y, skin_ramp[3] if ((nx + y) & 1) == 0 else skin_ramp[4])
		_px(nx + 1, y, skin_ramp[2])
		_px(nx + 2, y, skin_ramp[1])
	# Broad bulbous troll nose tip & wings
	for dx in range(-4, 5):
		var b_top := 3 if dx < -2 else (4 if dx <= 0 else (3 if dx <= 2 else 1))
		_px(nx + dx, y_tip - 1, skin_ramp[b_top])
	# Distinct nostrils framed by lit nostril wings
	_px(nx - 4, y_tip, skin_ramp[3])
	_px(nx - 3, y_tip, nostril)
	_px(nx - 2, y_tip, nostril)
	_px(nx - 1, y_tip, skin_ramp[4])
	_px(nx, y_tip, skin_ramp[3])
	_px(nx + 1, y_tip, skin_ramp[2])
	_px(nx + 2, y_tip, nostril)
	_px(nx + 3, y_tip, nostril)
	_px(nx + 4, y_tip, skin_ramp[1])
	for dx in range(-3, 4):
		_px(nx + dx, y_tip + 1, skin_ramp[0] if absi(dx) >= 2 else skin_ramp[1])

func _troll_mouth() -> void:
	var x := int(round(cx + 0.5))
	var y := int(round(mouth_y))
	var hw := 4 if sex_f else 5
	var lip_upper := _op(skin_ramp[1].darkened(0.14))
	var cleft := Color(0.14, 0.06, 0.06, 1.0)
	var lip_lower := _op(skin_ramp[3].lerp(Color("#8c6e68"), 0.24))
	for i in range(-hw, hw + 1):
		var dy := 0
		if stage == "elder" and absi(i) >= hw - 1:
			dy = 1
		_px(x + i, y - 1 + dy, lip_upper)
		_px(x + i, y + dy, cleft)
		if absi(i) < hw:
			_px(x + i, y + 1 + dy, lip_lower)
			_px(x + i, y + 2 + dy, skin_ramp[1])

func _goblin_mouth() -> void:
	var x := int(round(cx + 0.5))
	var y := int(round(mouth_y))
	var hw := 4 if sex_f else 5
	var cleft := Color("#221214")
	var lip_lower := _op(skin_ramp[3].lerp(Color("#945858"), 0.34 if sex_f else 0.18))
	var corner_sh := _op(skin.darkened(0.42))
	for i in range(-hw, hw + 1):
		var dy := 0
		if stage == "young" and absi(i) >= hw - 1:
			dy = -1
		elif stage == "elder" and absi(i) >= hw - 1:
			dy = 1
		elif stage == "adult" and not sex_f and i <= -hw + 1:
			dy = -1
		_px(x + i, y + dy, cleft)
		if absi(i) < hw:
			_px(x + i, y + 1 + dy, lip_lower)
	_px(x - hw - 1, y, corner_sh)
	_px(x + hw + 1, y, corner_sh)
	# Firm chin crease and highlight pad below lower lip
	for dx in range(-2, 3):
		_px(x + dx, y + 2, skin_ramp[1])
		_px(x + dx, y + 3, skin_ramp[4] if dx <= 0 else skin_ramp[3])

func _goblin_nose() -> void:
	var x0 := int(round(cx))
	var y_top := int(round(eye_y)) - 2
	var y_tip := int(round(mouth_y)) - 1
	var hi_crest := Color(0.99, 1.0, 0.78, 1.0)
	var lit_ridge := _op(skin_ramp[4].lightened(0.20))
	var mid_body := skin_ramp[3]
	var flank_sh := _op(skin.darkened(0.40))
	var deep_sh := _op(skin.darkened(0.56))
	var nostril := Color(0.04, 0.06, 0.02, 1.0)
	var wing_y := y_tip - 5
	# Prominent high-contrast arched bridge jutting outward into a hooked beak
	for y in range(y_top, wing_y):
		var dy := y - y_top
		var curve := 0
		if dy >= 4:
			curve = 2
		elif dy >= 2:
			curve = 1
		var bx := x0 + curve
		_px(bx - 3, y, flank_sh)
		_px(bx - 2, y, mid_body)
		_px(bx - 1, y, lit_ridge)
		_px(bx, y, hi_crest)
		_px(bx + 1, y, hi_crest if dy >= 2 else lit_ridge)
		_px(bx + 2, y, deep_sh)
	# Wide flared nostril wings + big long hooked beak overhanging downward
	_px(x0 - 4, wing_y, flank_sh)
	_px(x0 - 3, wing_y, lit_ridge)
	_px(x0 - 2, wing_y, mid_body)
	_px(x0 - 1, wing_y, lit_ridge)
	_px(x0, wing_y, hi_crest)
	_px(x0 + 1, wing_y, hi_crest)
	_px(x0 + 2, wing_y, lit_ridge)
	_px(x0 + 3, wing_y, mid_body)
	_px(x0 + 4, wing_y, deep_sh)

	_px(x0 - 4, wing_y + 1, flank_sh)
	_px(x0 - 3, wing_y + 1, lit_ridge)
	_px(x0 - 2, wing_y + 1, nostril)
	_px(x0 - 1, wing_y + 1, nostril)
	_px(x0, wing_y + 1, lit_ridge)
	_px(x0 + 1, wing_y + 1, hi_crest)
	_px(x0 + 2, wing_y + 1, hi_crest)
	_px(x0 + 3, wing_y + 1, nostril)
	_px(x0 + 4, wing_y + 1, deep_sh)

	_px(x0 - 4, wing_y + 2, deep_sh)
	_px(x0 - 3, wing_y + 2, flank_sh)
	_px(x0 - 2, wing_y + 2, nostril)
	_px(x0 - 1, wing_y + 2, deep_sh)
	_px(x0, wing_y + 2, lit_ridge)
	_px(x0 + 1, wing_y + 2, hi_crest)
	_px(x0 + 2, wing_y + 2, hi_crest)
	_px(x0 + 3, wing_y + 2, lit_ridge)
	_px(x0 + 4, wing_y + 2, deep_sh)

	# Long hooked beak tip projecting down and curving inward past the nostrils
	_px(x0 - 2, wing_y + 3, flank_sh)
	_px(x0 - 1, wing_y + 3, lit_ridge)
	_px(x0, wing_y + 3, hi_crest)
	_px(x0 + 1, wing_y + 3, hi_crest)
	_px(x0 + 2, wing_y + 3, lit_ridge)
	_px(x0 + 3, wing_y + 3, deep_sh)

	_px(x0 - 2, wing_y + 4, deep_sh)
	_px(x0 - 1, wing_y + 4, lit_ridge)
	_px(x0, wing_y + 4, hi_crest)
	_px(x0 + 1, wing_y + 4, lit_ridge)
	_px(x0 + 2, wing_y + 4, deep_sh)

	_px(x0 - 1, y_tip, deep_sh)
	_px(x0, y_tip, hi_crest)
	_px(x0 + 1, y_tip, deep_sh)

func _draw_wrinkles() -> void:
	if stage != "elder":
		return
	var wr := _op(skin.darkened(0.28))
	if race == "moon_elf":
		wr = Color("#3c4c70")
	elif race == "dark_elf":
		wr = _op(skin.darkened(0.48))
	elif race == "goblin":
		wr = _op(skin.darkened(0.38))
	elif race == "troll":
		wr = skin_ramp[0]
	if race == "dark_elf":
		var yf_d := int(round(eye_y)) - 8
		var wr_hi := Color("#bab2ce")
		var wr_hi_r := Color("#a8a0bc")
		var wr_dk := Color("#1e162a")
		# Two horizontal forehead creases: 1px light lilac-grey (~164-182 lum) with 1px dark beneath
		for i in range(-4, 5):
			_px(int(cx) + i, yf_d - 1, wr_hi if i <= 1 else wr_hi_r)
			_px(int(cx) + i, yf_d, wr_dk)
		for i in range(-4, 5):
			_px(int(cx) + i, yf_d + 1, wr_hi if i <= 1 else wr_hi_r)
			if i != 0:
				_px(int(cx) + i, yf_d + 2, wr_dk)
		return
	if race == "moon_elf":
		var yf := int(round(eye_y)) - 8
		for i in range(-4, 5):
			if i == 0:
				continue
			_px(int(cx) + i, yf, wr)
		for i in range(-3, 5):
			_px(int(cx) + i, yf + 2, wr)
		return
	if race == "goblin":
		var gyf := int(round(eye_y)) - 8
		for i in range(-5, 6):
			if i == 0:
				continue
			_px(int(cx) + i, gyf, wr)
			_px(int(cx) + i, gyf + 1, skin_ramp[4])
		for i in range(-4, 5):
			_px(int(cx) + i, gyf + 2, wr)
		# Crow's feet & under-eye creases
		var glx := int(round(eye_near.x)) - 4
		var gly := int(round(eye_near.y))
		var grx := int(round(eye_far.x)) + 4
		var gry := int(round(eye_far.y))
		for k in range(3):
			_px(glx - k, gly - 1 - int(k / 2), wr)
			_px(glx - k, gly + 1 + int(k / 2), wr)
			_px(grx + k, gry - 1 - int(k / 2), wr)
			_px(grx + k, gry + 1 + int(k / 2), wr)
		# Deep nasolabial folds flanking the hooked nose & mouth
		var gmy := int(round(mouth_y))
		for k in range(5):
			var ox := 5 + int(k / 2)
			_px(int(cx) - ox, gmy - 4 + k, wr)
			_px(int(cx) + ox, gmy - 4 + k, wr)
		return
	if hstyle in ["receding", "bald", "tuft", "half", "mohawk", "topknot"]:
		var yf := int(eye_y - scl - 6.0)
		for i in range(9):
			if i == 4 and (seed % 2 == 0):
				continue
			_px(int(cx) - 4 + i, yf, wr)
			_px(int(cx) - 3 + i, yf + 2, wr)
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
	elif (race == "moon_elf" or race == "dark_elf") and not sex_f and stage == "adult":
		var ch_dark := Color("#4e6088") if race == "moon_elf" else _op(skin.darkened(0.36))
		var j_top := int(eye_y) + 6
		for i in range(4):
			var ox := 11 - int(i / 2)
			_px(int(cx) - ox, j_top + i, ch_dark)
			_px(int(cx) + ox, j_top + i, ch_dark)
	if race == "dark_elf" and stage == "elder":
		var wr_hi := Color("#bab2ce")
		var wr_hi_r := Color("#a8a0bc")
		var wr_dk := Color("#1e162a")
		# Crow's feet at outer eye corners: 1px light lilac-grey above 1px dark crease
		var elx := int(round(eye_near.x)) - 4
		var ely := int(round(eye_near.y))
		for k in range(3):
			_px(elx - k, ely - 2, wr_hi)
			_px(elx - k, ely - 1, wr_dk)
			_px(elx - k, ely + 1, wr_hi)
			_px(elx - k, ely + 2, wr_dk)
		var erx := int(round(eye_far.x)) + 4
		var ery := int(round(eye_far.y))
		for k in range(2):
			_px(erx + k, ery - 2, wr_hi_r)
			_px(erx + k, ery - 1, wr_dk)
			_px(erx + k, ery + 1, wr_hi_r)
			_px(erx + k, ery + 2, wr_dk)
		# Under-eye bags: 1px light lilac-grey crease with 1px dark pixel beneath
		for dx in range(-2, 3):
			_px(int(round(eye_near.x)) + dx, ely + 3, wr_hi if dx <= 1 else wr_hi_r)
			_px(int(round(eye_near.x)) + dx, ely + 4, wr_dk)
			_px(int(round(eye_far.x)) + dx, ery + 3, wr_hi if dx < 0 else wr_hi_r)
			_px(int(round(eye_far.x)) + dx, ery + 4, wr_dk)
		# Nasolabial & mouth-corner folds: diagonal 1px light lilac-grey crease with 1px dark pixel beneath
		var nxa := int(round(cx + 1.0))
		var nya := (int(round(mouth_y)) - 3) if sex_f else (int(round(eye_y)) + 8)
		var n_steps := 3 if sex_f else 4
		for i in range(n_steps):
			var ox := 3 + i
			var fy := nya + i
			_px(nxa - ox, fy, wr_hi)
			_px(nxa - ox, fy + 1, wr_dk)
			_px(nxa + ox, fy, wr_hi_r)
			_px(nxa + ox, fy + 1, wr_dk)
		# Gaunt cheek hollow crease under outer cheekbones: 1px light ridge above 1px dark crease
		var hx_l := int(cx) - (9 if not sex_f else 7)
		var hx_r := int(cx) + (9 if not sex_f else 8)
		var hy0 := int(round(eye_y)) + 5
		for dy in range(2):
			_px(hx_l + dy, hy0 + dy, wr_hi)
			_px(hx_l + dy, hy0 + dy + 1, wr_dk)
			_px(hx_r - dy, hy0 + dy, wr_hi_r)
			_px(hx_r - dy, hy0 + dy + 1, wr_dk)
	elif race == "moon_elf" and stage == "elder":
		var aged := Color("#3a4a6e")
		var soft := skin_ramp[1]
		# Crow's feet at outer eye corners
		var elx := int(round(eye_near.x)) - 4
		var ely := int(round(eye_near.y))
		for k in range(3):
			_px(elx - k, ely - 1 - int(k / 2), aged)
			_px(elx - k, ely + 1 + int(k / 2), aged)
		var erx := int(round(eye_far.x)) + 4
		var ery := int(round(eye_far.y))
		for k in range(3):
			_px(erx + k, ery - 1 - int(k / 2), aged)
			_px(erx + k, ery + 1 + int(k / 2), aged)
		# Under-eye bag shadow creases
		for dx in range(-2, 3):
			_px(int(round(eye_near.x)) + dx, ely + 3, soft)
			_px(int(round(eye_far.x)) + dx, ery + 3, soft)
		# Nasolabial lines from beside nostrils toward mouth corners
		var nxa := int(round(cx + 1.0))
		var nya := int(round(nose_y))
		for i in range(4):
			var ox := 3 + int((i + 1) / 2)
			var fy := nya + 1 + i
			_px(nxa - ox, fy, aged)
			_px(nxa + ox, fy, aged)
		# Gaunt cheek hollow crease under outer cheekbones
		var hx_l := int(cx) - (10 if not sex_f else 9)
		var hx_r := int(cx) + (10 if not sex_f else 9)
		var hy0 := int(round(eye_y)) + 5
		for dy in range(3):
			var d_in := int((dy + 1) / 2)
			_px(hx_l + d_in, hy0 + dy, aged if dy == 1 else soft)
			_px(hx_r - d_in, hy0 + dy, aged if dy == 1 else soft)
	elif race == "dark_elf" and stage == "young":
		var apple := skin_ramp[4]
		var midc := skin_ramp[3]
		var ox := -2 if sex_f else -1
		for dy in range(2):
			for dx in range(3):
				_px(int(eye_near.x) + ox + dx, int(eye_near.y) + 4 + dy, apple if dy == 0 else midc)
				_px(int(eye_far.x) - ox - dx, int(eye_far.y) + 4 + dy, apple if dy == 0 else midc)
	elif race == "goblin" and stage == "adult" and not sex_f:
		var scar := _op(skin.darkened(0.32))
		_px(int(eye_far.x) + 3, int(eye_far.y) - 2, scar)
		_px(int(eye_far.x) + 4, int(eye_far.y) - 1, scar)
		_px(int(eye_far.x) + 5, int(eye_far.y), scar)
	elif race == "troll" and stage == "elder":
		for i in range(-5, 6):
			if absi(i) <= 1:
				continue
			_px(int(cx) + i, int(eye_y) - 10, skin_ramp[1])
		for k in range(3):
			_px(int(cx) - 6 - int(k / 2), int(mouth_y) - 3 + k, skin_ramp[1])
			_px(int(cx) + 7 + int(k / 2), int(mouth_y) - 3 + k, skin_ramp[1])

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

func _troll_beard() -> void:
	# Textured, multi-tone clumped beard starting below the visible mouth line & lower lip, keeping heavy jaw visible
	var xc := int(round(cx + 0.5))
	var y0 := int(round(mouth_y)) + 3
	var is_elder := stage == "elder"
	var y1 := int(round(chin_y)) + (8 if is_elder else 5)
	var half := 11.5 if is_elder else 9.5
	var span := float(maxi(1, y1 - y0))
	for y in range(y0, mini(y1 + 3, SIZE)):
		var dy := y - y0
		var t := clampf(float(dy) / span, 0.0, 1.0)
		var row_half := lerpf(half * 0.82, half, minf(1.0, t * 2.2))
		if t > 0.52:
			row_half = lerpf(half, half * 0.62, (t - 0.52) / 0.48)
		var reach := int(round(row_half))
		for dx in range(-reach, reach + 1):
			var x := xc + dx
			# Organic 2D tuft waves rather than vertical stripes
			var radial_drift := float(dx) - signf(float(dx)) * float(dy) * 0.28
			var wave_a := sin(radial_drift * 1.15 + float(dy) * 0.55)
			var wave_b := cos(float(dx) * 0.72 - float(dy) * 0.85)
			var root_skip := posmod(absi(dx) * 3 + seed, 2)
			if y == y0 and root_skip == 0:
				continue
			# Jagged lower beard tips (3 distinct pointed tufts)
			var prong_wave := cos(float(dx) * 0.78)
			var tuft_len := int(round(1.8 * prong_wave + 0.8 * sin(float(dx) * 1.55)))
			if y > y1 - 1 + tuft_len:
				continue
			var u := float(dx) / maxf(1.0, half)
			var lit := clampf(0.76 - u * 0.34 - t * 0.30 + wave_a * 0.16 + wave_b * 0.10, 0.08, 0.96)
			var band := _shade_band(lit, x, y)
			if wave_a > 0.52 and dx <= 3 and t < 0.78 and y > y0:
				band = 4
			elif (wave_a < -0.58 and wave_b < -0.15) or y >= y1 + tuft_len:
				band = 0 if ((x + y) & 1) == 0 else 1
			_px(x, y, beard_ramp[band])
	# Sparse dithered jaw scruff blending into the heavy outer jaw
	for side in [-1, 1]:
		var iside := int(side)
		for dy in range(0, 5):
			var sx: int = xc + iside * (int(round(half)) + 1 + (dy & 1))
			var sy: int = y0 + 1 + dy
			if _probe(float(sx) + 0.5, float(sy) + 0.5):
				_px(sx, sy, beard_ramp[2 if iside < 0 else 1])

func _dark_elf_elder_beard() -> void:
	var xc := int(round(cx + 1.0))
	var my := int(round(mouth_y))
	var chin := int(round(chin_y))
	# Full-jaw short bright/silver beard mirroring moon_elf boxed jaw beard construction
	var by0 := my - 1
	var by1 := chin + 3
	for y in range(by0, mini(by1 + 1, SIZE)):
		for x in range(int(cx) - 14, int(cx) + 15):
			var probe_y := minf(float(y) + 0.5, chin_y - 1.2)
			if not _probe(float(x) + 0.5, probe_y):
				continue
			var dx_m := absi(x - xc)
			if y == my - 1 and dx_m < 6:
				continue
			elif y == my and dx_m <= 3:
				continue
			elif y == my + 1 and dx_m >= 1 and dx_m <= 3:
				continue
			_px(x, y, _beard_at(x, y))
	# Silver moustache across upper lip connecting into beard corners
	_moustache(xc, my, 5)
	_px(xc, my - 1, beard_ramp[3])
	_px(xc, my - 2, beard_ramp[2])

func _draw_beard() -> void:
	if not beard_on or _lost("head"):
		return
	if race == "troll":
		_troll_beard()
		return
	if race == "dark_elf" and stage == "elder" and not sex_f:
		_dark_elf_elder_beard()
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
			if race != "troll":
				_moustache(xc, int(mouth_y), int(maxf(8.0, ghalf * 0.62)))
		2:
			_beard_fill(xc, y0, chin + hang, half, "round")
			if race != "troll":
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
		8:
			var by0 := int(mouth_y) - 1
			var by1 := chin + 2
			for y in range(by0, mini(by1, SIZE)):
				for x in range(int(cx) - 13, int(cx) + 14):
					var probe_y := minf(float(y) + 0.5, chin_y - 0.5)
					if not _probe(float(x) + 0.5, probe_y):
						continue
					var dx_m := absi(x - xc)
					if y < int(mouth_y) + 2:
						if dx_m < 6:
							continue
					elif y == int(mouth_y) + 2:
						if dx_m > 1 and dx_m < 5:
							continue
					_px(x, y, _beard_at(x, y))
			_moustache(xc, int(mouth_y), 6)
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
	var length := 8.0 if race == "orc" else 6.0
	if stage == "young":
		length *= 0.55 if race == "troll" else 0.45
	elif stage == "elder":
		length *= 1.15 if race == "troll" else 1.35
	if sex_f:
		length *= 0.65
	var y := int(mouth_y) + (1 if race == "troll" else 0)
	var spread := 6 if race == "troll" else 5
	var xc := int(round(cx + (0.5 if race == "troll" else 1.0)))
	_tusk(xc - spread, y, -0.85, length)
	_tusk(xc + spread, y, 0.80, length * 0.95)

func _tusk(x0: int, y0: int, dir: float, length: float) -> void:
	var steps := maxi(3, int(round(length)))
	var thick := 2
	var side := 1 if dir > 0.0 else -1
	var gum := Color(0.32, 0.12, 0.14, 1.0)
	_px(x0, y0 - 1, gum)
	_px(x0 + side, y0 - 1, gum)
	for i in range(steps):
		var along := float(i)
		var drift := 0.0
		if along > 1.0:
			drift = dir * (along - 1.0) * 0.32
		var x := x0 + int(round(drift))
		var y := y0 + i
		_px(x - side, y, IVORY_DARK)
		_px(x + side * thick, y, IVORY_DARK)
		for t in range(thick):
			var col := IVORY
			if i == 0:
				col = IVORY.lerp(gum, 0.42)
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
