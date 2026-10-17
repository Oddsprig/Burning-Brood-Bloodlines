class_name CreaturePainter
extends RefCounted
## Monsters wave 1: code-drawn quadrupeds (wolf, bear, wild boar) in the same pixel style as FigurePainter
## (PixelCanvas parts with shading + dark outlines), plus campaign-map icons for creature packs and map sites
## (wolf den, bear den, boar wallow, bandit camp). FigurePainter delegates here for creature races, so Paperdoll,
## Portrait, PartyIcon and severed-part decals all work unchanged.
## Body pieces follow the body plan: a severed leg (upper / lower / paw), the tail or the head is simply not
## drawn (a blood stump instead) and lies on the ground as its own decal (render_piece).
## Local frame: 1 unit = 1 logical px, origin at the feet, +x = facing, y down.

const SHAPES := {
	# L body length, legs leg length, br torso half-height, hr head radius, snout length, lr leg radius,
	# neck: head offset from the shoulder (x, y), tail: [length, droop, thickness]
	"wolf": {"L": 19.0, "legs": 7.5, "br": 3.2, "hr": 2.5, "snout": 4.4, "lr": 0.75, "neck": Vector2(4.2, -2.6), "tail": [7.5, 4.0, 1.5], "ears": "point", "snout_r": 0.38},
	"bear": {"L": 22.0, "legs": 7.5, "br": 6.2, "hr": 3.8, "snout": 2.6, "lr": 2.0, "neck": Vector2(4.0, -1.5), "tail": [2.0, 1.0, 1.2], "ears": "round", "hump": true},
	"boar": {"L": 17.0, "legs": 5.0, "br": 4.8, "hr": 3.2, "snout": 4.0, "lr": 0.9, "neck": Vector2(3.0, 1.0), "tail": [3.5, 2.5, 0.5], "ears": "small", "tusks": true, "ridge": true, "disc": true},
}
const BLOOD := Color("#c0141c")
const BLOOD_DARK := Color("#6a0a10")
const LEGS := [["leg_front", "foot_front", 1.0], ["leg_rear", "foot_rear", -1.0]]

var spec: Dictionary
var sh: Dictionary
var cv: PixelCanvas
var pose := "idle"
var t := 0.0
var coat: Color
var belly: Color
var j := {}    # joints

static func is_creature_spec(sp: Dictionary) -> bool:
	return DB.is_creature(String(sp.get("race", "")))

static func shape_of(race: String) -> Dictionary:
	var key := String(DB.races.get(race, {}).get("art", {}).get("shape", "wolf"))
	return SHAPES.get(key, SHAPES["wolf"])

static func dims(race: String) -> Dictionary:
	var s := maxf(1.0, float(DB.races.get(race, {}).get("height", 1.0)))
	var cw := int(ceil(56.0 * s / 2.0)) * 2
	var ch := int(ceil(40.0 * s / 2.0)) * 2
	return {"size": Vector2i(cw, ch), "anchor": Vector2(cw / 2, ch - int(8 * s))}

static func render(sp: Dictionary, p: String, prog: float) -> Image:
	return CreaturePainter.new(sp).paint(p, prog).to_image()

static func render_canvas(sp: Dictionary, p: String, prog: float) -> PixelCanvas:
	return CreaturePainter.new(sp).paint(p, prog)

static func render_bust(sp: Dictionary) -> Image:
	return CreaturePainter.new(sp).paint_bust().to_image()

static func render_piece(sp: Dictionary, pid: String) -> Image:
	return CreaturePainter.new(sp).paint_piece(pid).to_image()

func _init(sp: Dictionary) -> void:
	spec = sp
	sh = shape_of(String(sp.get("race", "wolf")))
	coat = sp.get("skin", Color("#888888"))
	belly = sp.get("hair", coat.lightened(0.3))
	var lost_blood := 1.0 - float(sp.get("blood", 1.0))
	coat = coat.lerp(Color("#c8c4bc"), clampf(lost_blood * 0.4, 0.0, 0.3))

func _lost(pid: String) -> bool:
	return pid in spec.get("lost", [])

static func ol(c: Color) -> Color:
	return FigurePainter.ol(c)

# --- rig ------------------------------------------------------------------------------------------
func _rig() -> void:
	var L: float = sh["L"]
	var legs: float = sh["legs"]
	var br: float = sh["br"]
	var lunge := 0.0
	var crouch := 0.0
	var head_dy := 0.0
	var mouth := 0.0
	match pose:
		"prepare":
			lunge = -1.5 * t; crouch = 1.2 * t; head_dy = 1.0 * t
		"strike":
			lunge = 3.0 * sin(t * PI) + 1.0 * (1.0 - t); crouch = -0.5 * sin(t * PI); mouth = sin(t * PI); head_dy = -0.5
		"recover":
			lunge = 1.0 * (1.0 - t)
		"hit":
			lunge = -1.5 * sin(t * PI); crouch = 0.5
		"block", "dodge":
			lunge = -2.5 * sin(t * PI); crouch = -1.0 * sin(t * PI)
	var cy := -(legs + br * 0.85) + crouch
	j["lunge"] = lunge
	j["cy"] = cy
	j["mouth"] = mouth
	j["torso"] = Vector2(lunge, cy)
	j["sh_f"] = Vector2(lunge + L * 0.5 - br * 0.6, cy + br * 0.25)
	j["sh_r"] = Vector2(lunge - L * 0.5 + br * 0.6, cy + br * 0.25)
	var nk: Vector2 = sh["neck"]
	j["neck0"] = Vector2(lunge + L * 0.5 - br * 0.4, cy - br * 0.35)
	j["hc"] = (j["neck0"] as Vector2) + nk + Vector2(lunge * 0.3, head_dy + crouch * 0.5)
	j["tail0"] = Vector2(lunge - L * 0.5 + 0.5, cy - br * 0.4)
	# legs: trotting gait (diagonal pairs), idle = planted
	var stride := 2.6 if pose == "walk" else 0.0
	for leg in [["f", "r", 0.0], ["f", "l", 0.5], ["r", "r", 0.5], ["r", "l", 0.0]]:
		var key: String = "%s%s" % [leg[0], leg[1]]
		var top: Vector2 = j["sh_f"] if leg[0] == "f" else j["sh_r"]
		top += Vector2(0.8 if leg[1] == "l" else -0.4, 0.0)
		var ph := TAU * (t + float(leg[2]))
		var fx := top.x + sin(ph) * stride + (0.6 if leg[0] == "f" else -0.4)
		var lift := maxf(0.0, cos(ph)) * 1.4 if stride > 0.0 else 0.0
		var foot := Vector2(fx, -lift)
		var knee := top.lerp(foot, 0.5) + Vector2(-0.8 if leg[0] == "f" else 1.0, 0.0)
		j[key] = [top, knee, foot]

# --- painting -------------------------------------------------------------------------------------
func paint(p: String, prog: float) -> PixelCanvas:
	pose = p
	t = prog
	var dm := dims(String(spec.get("race", "wolf")))
	var sz: Vector2i = dm["size"]
	var anchor: Vector2 = dm["anchor"]
	cv = PixelCanvas.new(sz.x, sz.y)
	var lying := pose == "prone" or pose == "dead"
	_ring(anchor, lying)
	if pose == "dead":
		_pool(anchor)
		# on its back, legs in the air
		cv.set_frame(anchor + Vector2(0.0, -float(sh["br"]) * 1.6 - float(sh["legs"])), 1.0, PI)
		pose = "idle"
		_rig()
		pose = "dead"
	elif pose == "prone":
		cv.set_frame(anchor, 1.0, 0.0)
		_rig()
		_lie_down()
	else:
		cv.set_frame(anchor, 1.0, 0.0)
		_rig()
	_draw_body()
	_ground_blood(anchor, lying)
	return cv

## Lying on the belly: legs folded forward under the body, torso on the ground, head low.
func _lie_down() -> void:
	var br: float = sh["br"]
	var drop := -br * 0.9 - float(j["cy"])
	for k in ["torso", "sh_f", "sh_r", "neck0", "hc", "tail0"]:
		j[k] = (j[k] as Vector2) + Vector2(0.0, drop)
	j["hc"] = (j["hc"] as Vector2) + Vector2(0.5, 1.5)
	for key in ["fr", "fl", "rr", "rl"]:
		var top: Vector2 = j["sh_f"] if key.begins_with("f") else j["sh_r"]
		var foot := Vector2(top.x + 3.5, -0.5)
		j[key] = [top, top.lerp(foot, 0.5) + Vector2(0, 0.5), foot]

func _draw_body() -> void:
	var far := coat.darkened(0.25)
	_leg("f", "l", far)
	_leg("r", "l", far)
	_tail()
	_torso()
	_leg("r", "r", coat)
	_leg("f", "r", coat)
	_neck_head()
	_wounds()

func _ring(anchor: Vector2, lying: bool) -> void:
	var tc: Color = spec.get("team", Color(0, 0, 0, 0))
	var rx := float(sh["L"]) * 0.5 + 3.0
	var ry := 2.4
	for y in range(floori(anchor.y - ry - 1), ceili(anchor.y + ry + 1)):
		for x in range(floori(anchor.x - rx - 1), ceili(anchor.x + rx + 1)):
			var dx := (x + 0.5 - anchor.x) / rx
			var dy := (y + 0.5 - anchor.y + 0.5) / ry
			var d := dx * dx + dy * dy
			if d <= 1.0:
				cv.set_px(x, y, Color(0, 0, 0, 0.28))
			if tc.a > 0.0 and d <= 1.0 and d >= 0.6:
				var c := tc if y >= anchor.y else tc.darkened(0.35)
				if pose == "dead":
					c.a = 0.45
				cv.set_px(x, y, c)

func _pool(anchor: Vector2) -> void:
	var lostb := 1.0 - float(spec.get("blood", 1.0))
	cv.set_frame(Vector2.ZERO)
	cv.begin()
	cv.ellipse(anchor + Vector2(-1.0, -0.5), 5.0 + lostb * 10.0, 1.6 + lostb * 1.2, BLOOD_DARK.lerp(BLOOD, 0.35))
	cv.end(Color(0, 0, 0, 0), 0.0)

func _ground_blood(anchor: Vector2, lying: bool) -> void:
	var lostb := 1.0 - float(spec.get("blood", 1.0))
	var n: int = int(lostb * 10.0) + (spec.get("bleed", {}) as Dictionary).size() * 2
	if n <= 0 or lying:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0)) + 99
	var keep := cv.xf
	cv.set_frame(Vector2.ZERO)
	for i in n:
		var x := int(anchor.x + rng.randf_range(-float(sh["L"]) * 0.5, float(sh["L"]) * 0.5))
		var y := int(anchor.y + rng.randf_range(-1.5, 1.0))
		cv.set_px(x, y, BLOOD if i % 3 else BLOOD_DARK)
	cv.xf = keep

func _leg(fr: String, side: String, col: Color) -> void:
	var base := "leg_front" if fr == "f" else "leg_rear"
	var paw := "foot_front" if fr == "f" else "foot_rear"
	var up_id := "%s_upper_%s" % [base, side]
	var lo_id := "%s_lower_%s" % [base, side]
	var paw_id := "%s_%s" % [paw, side]
	var pts: Array = j["%s%s" % [fr, side]]
	var lr: float = sh["lr"]
	var thigh := lr * (2.2 if fr == "r" else 1.7)
	if _lost(up_id):
		cv.dot(pts[0], BLOOD)
		return
	cv.begin()
	cv.capsule(pts[0] + Vector2(0, -1.0), pts[1], thigh, col)
	if not _lost(lo_id):
		cv.capsule(pts[1], pts[2] + Vector2(0, -0.8), lr, col)
	cv.end(ol(col), 0.12)
	if _lost(lo_id):
		cv.dot(pts[1], BLOOD)
		return
	if _lost(paw_id):
		cv.dot(pts[2] + Vector2(0, -1.0), BLOOD)
		return
	cv.begin()
	cv.ellipse(pts[2] + Vector2(0.6, -0.6), lr + 0.6, 0.8, col.darkened(0.3))
	cv.end(ol(col), 0.0)

func _torso() -> void:
	var L: float = sh["L"]
	var br: float = sh["br"]
	var c: Vector2 = j["torso"]
	var bl := belly
	var cy := c.y
	var inv := cv.xf.affine_inverse()
	var line := cy + br * 0.45
	cv.begin()
	cv.ellipse(c, L * 0.5, br, coat, func(x: int, y: int, col: Color) -> Color:
		return bl if (inv * Vector2(x + 0.5, y + 0.5)).y > line else col)
	if sh.get("hump", false):
		cv.ellipse(c + Vector2(L * 0.22, -br * 0.55), L * 0.22, br * 0.6, coat)
	cv.end(ol(coat), 0.14)
	if sh.get("ridge", false):
		var dark := coat.darkened(0.45)
		for i in int(L * 0.8):
			var x := c.x - L * 0.4 + i
			cv.dot(Vector2(x, cy - br + 0.2 + (0.0 if i % 2 else -0.6)), dark)

func _tail() -> void:
	if _lost("tail"):
		return
	var tl: Array = sh["tail"]
	var a: Vector2 = j["tail0"]
	var wag := sin(TAU * t) * 0.8 if pose == "idle" or pose == "walk" else 0.0
	var b := a + Vector2(-float(tl[0]), float(tl[1]) + wag)
	cv.begin()
	cv.capsule(a, a.lerp(b, 0.5) + Vector2(0, -0.5), float(tl[2]) * 0.8, coat)
	cv.capsule(a.lerp(b, 0.5) + Vector2(0, -0.5), b, float(tl[2]), coat)
	cv.end(ol(coat), 0.1)

func _neck_head() -> void:
	var hc: Vector2 = j["hc"]
	var hr: float = sh["hr"]
	var n0: Vector2 = j["neck0"]
	if _lost("neck") or _lost("head"):
		cv.begin()
		cv.capsule(n0, n0.lerp(hc, 0.4), hr * 0.8, coat)
		cv.end(ol(coat), 0.12)
		cv.dot(n0.lerp(hc, 0.45), BLOOD)
		cv.dot(n0.lerp(hc, 0.45) + Vector2(0, 1), BLOOD_DARK)
		return
	cv.begin()
	cv.capsule(n0, hc, hr * 0.85, coat)
	cv.end(ol(coat), 0.12)
	# ears behind the skull
	var ec := coat.darkened(0.15)
	cv.begin()
	match String(sh.get("ears", "point")):
		"point":
			cv.poly(PackedVector2Array([hc + Vector2(-2.2, -hr + 0.8), hc + Vector2(-1.6, -hr - 2.4), hc + Vector2(-0.6, -hr + 0.6)]), ec.darkened(0.15))
			cv.poly(PackedVector2Array([hc + Vector2(-1.0, -hr + 0.6), hc + Vector2(-0.2, -hr - 2.8), hc + Vector2(0.9, -hr + 0.4)]), ec)
		"round":
			cv.ellipse(hc + Vector2(-1.2, -hr + 0.2), 1.2, 1.2, ec)
		_:
			cv.poly(PackedVector2Array([hc + Vector2(-1.4, -hr + 0.8), hc + Vector2(-1.8, -hr - 1.2), hc + Vector2(0.2, -hr + 0.4)]), ec)
	cv.end(ol(ec), 0.1)
	# skull + snout (+ open jaw while biting)
	var sn: float = sh["snout"]
	var mo: float = j["mouth"]
	var tip := hc + Vector2(hr + sn - 0.5, 0.8)
	cv.begin()
	cv.ellipse(hc, hr, hr * 0.85, coat)
	cv.capsule(hc + Vector2(hr * 0.4, 0.2), tip, hr * float(sh.get("snout_r", 0.48)), coat)
	cv.end(ol(coat), 0.14)
	if sh.get("disc", false):   # boar snout disc
		var dc := coat.lightened(0.25).lerp(Color("#c89088"), 0.4)
		cv.begin()
		cv.ellipse(tip + Vector2(0.3, 0.0), 0.7, hr * 0.42, dc)
		cv.end(ol(dc), 0.0)
	if mo > 0.2:
		cv.begin()
		cv.capsule(hc + Vector2(hr * 0.3, hr * 0.5), tip + Vector2(-0.5, 1.2 + mo * 1.6), hr * 0.3, coat.darkened(0.1))
		cv.end(ol(coat), 0.1)
		cv.dot(tip + Vector2(-1.0, 1.0 + mo), Color("#7a1a20"))
		cv.dot(tip + Vector2(-0.5, 0.6), Color("#f4f0e6"))
	# nose, eye, tusks
	cv.dot(tip + Vector2(0.2, -0.4), Color("#1a1214") if not sh.get("tusks", false) else coat.darkened(0.5).lerp(Color("#d8a0a0"), 0.3))
	var dead := pose == "dead"
	cv.dot(hc + Vector2(hr * 0.35, -hr * 0.35), Color("#140a10") if not dead else coat.darkened(0.4))
	if sh.get("tusks", false):
		var tk := Color(DB.races.get(String(spec.get("race", "")), {}).get("art", {}).get("tusk", "#efe6cc"))
		cv.begin()
		cv.capsule(tip + Vector2(-1.8, 1.0), tip + Vector2(-0.9, -0.6), 0.6, tk)
		cv.capsule(tip + Vector2(-0.9, -0.6), tip + Vector2(-1.4, -2.2), 0.45, tk)
		cv.end(ol(tk), 0.0)

func _part_spot(pid: String) -> Array:
	var L: float = sh["L"]
	var br: float = sh["br"]
	var c: Vector2 = j["torso"]
	if pid == "head" or pid.begins_with("eye"):
		return [j["hc"], float(sh["hr"]) * 0.6]
	if pid == "neck":
		return [(j["neck0"] as Vector2).lerp(j["hc"], 0.5), 1.2]
	if pid == "torso_upper":
		return [c + Vector2(L * 0.2, 0), br * 0.6]
	if pid == "torso_lower":
		return [c + Vector2(-L * 0.2, 0), br * 0.6]
	if pid == "tail":
		return [(j["tail0"] as Vector2) + Vector2(-1.5, 1.0), 0.8]
	for fr in ["f", "r"]:
		for side in ["l", "r"]:
			var pts: Array = j["%s%s" % [fr, side]]
			var base := "leg_front" if fr == "f" else "leg_rear"
			var paw := "foot_front" if fr == "f" else "foot_rear"
			if pid == "%s_upper_%s" % [base, side]:
				return [(pts[0] as Vector2).lerp(pts[1], 0.5), 1.0]
			if pid == "%s_lower_%s" % [base, side]:
				return [(pts[1] as Vector2).lerp(pts[2], 0.5), 0.8]
			if pid == "%s_%s" % [paw, side]:
				return [pts[2], 0.6]
	return []

func _wounds() -> void:
	var dmg: Dictionary = spec.get("dmg", {})
	var bleed: Dictionary = spec.get("bleed", {})
	var rng := RandomNumberGenerator.new()
	for pid in dmg:
		var spot := _part_spot(pid)
		if spot.is_empty():
			continue
		rng.seed = int(spec.get("seed", 0)) * 31 + hash(pid)
		var c: Vector2 = spot[0]
		var r: float = spot[1]
		var d: float = dmg[pid]
		for i in 1 + int(d * 6.0):
			var p := cv.map(c + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r)))
			cv.stain_px(int(p.x), int(p.y), BLOOD if d < 0.7 or i % 2 else BLOOD_DARK)
		if bleed.has(pid) and pose != "dead":
			var p0 := cv.map(c)
			for i in int(1 + d * 2.0):
				cv.stain_px(int(p0.x), int(p0.y) + i, BLOOD)

# --- severed pieces, portrait ------------------------------------------------------------------
func paint_piece(pid: String) -> PixelCanvas:
	pose = "idle"
	t = 0.0
	var P := FigurePainter.PIECE
	cv = PixelCanvas.new(P, P)
	_rig()
	cv.set_frame(Vector2.ZERO)
	cv.begin()
	cv.ellipse(Vector2(P * 0.5, P * 0.5 + 2.0), 4.0, 1.6, BLOOD_DARK.lerp(BLOOD, 0.4))
	cv.end(Color(0, 0, 0, 0), 0.0)
	var mid := Vector2(P * 0.5, P * 0.5)
	if pid == "head":
		var hc: Vector2 = j["hc"]
		cv.set_frame(mid - hc + Vector2(-1.0, 1.0))
		var keep_lost: Array = spec.get("lost", [])
		spec["lost"] = []
		_neck_stub_head()
		spec["lost"] = keep_lost
		cv.dot(hc + Vector2(-float(sh["hr"]), 1.0), BLOOD)
		return cv
	if pid == "tail":
		var a: Vector2 = j["tail0"]
		cv.set_frame(mid - a + Vector2(3.0, 0.0))
		var tl: Array = sh["tail"]
		cv.begin()
		cv.capsule(a, a + Vector2(-float(tl[0]), 1.0), float(tl[2]), coat)
		cv.end(ol(coat), 0.1)
		cv.dot(a, BLOOD)
		return cv
	if pid.begins_with("leg_") or pid.begins_with("foot_"):
		var fr := "f" if pid.contains("front") else "r"
		var side := "r" if pid.ends_with("_r") else "l"
		var pts: Array = j["%s%s" % [fr, side]]
		var seg: Array = [pts[0], pts[1], pts[2]]
		if pid.contains("lower"):
			seg = [pts[1], pts[2]]
		elif pid.begins_with("foot_"):
			seg = [pts[2]]
		var m := Vector2.ZERO
		for q in seg:
			m += q
		m /= float(seg.size())
		cv.set_frame(mid, 1.0, PI * 0.5 if seg.size() > 1 else 0.0)
		cv.xf = cv.xf * Transform2D(0.0, -m)
		var lr: float = sh["lr"]
		cv.begin()
		for i in seg.size() - 1:
			cv.capsule(seg[i], seg[i + 1], lr * (1.8 if i == 0 and seg.size() == 3 else 1.0), coat)
		cv.ellipse(seg[seg.size() - 1], lr + 0.6, 0.9, coat.darkened(0.3))
		cv.end(ol(coat), 0.12)
		cv.dot(seg[0], BLOOD)
	return cv

func _neck_stub_head() -> void:
	var hc: Vector2 = j["hc"]
	j["neck0"] = hc + Vector2(-2.5, 1.0)
	_neck_head()

func paint_bust() -> PixelCanvas:
	pose = "idle"
	t = 0.0
	var B := FigurePainter.BUST
	cv = PixelCanvas.new(B, B)
	_rig()
	var hc: Vector2 = j["hc"]
	var k := 24.0 / (float(sh["hr"]) * 2.0 + float(sh["snout"]))
	cv.set_frame(Vector2(B * 0.38, B * 0.45) - hc * k, k, 0.0)
	_torso()
	_neck_head()
	_wounds()
	return cv

# --- campaign map ----------------------------------------------------------------------------------
## Creature pack icon: 1-3 animals (count hint), no banner. Returns {"image", "anchor"}.
static func icon(race: String, count: int, leader: Unit, frame: int) -> Dictionary:
	var dm := dims(race)
	var fsz: Vector2i = dm["size"]
	var fa: Vector2 = dm["anchor"]
	var cw := fsz.x + 16
	var ch := fsz.y + 6
	var anchor := Vector2(fa.x + 8, fa.y + 4)
	var cv2 := PixelCanvas.new(cw, ch)
	var p := "idle" if frame == 0 else "walk"
	var tt := 0.0 if frame == 0 else float(frame - 1) / 4.0
	var nf := PartyIcon.figures_for(count)
	var lead := FigurePainter.spec_for_unit(leader) if leader != null else _generic(race, 1)
	lead["team"] = Color(0, 0, 0, 0)
	var offs := [Vector2(-9, -3), Vector2(8, -2)]
	for i in nf - 1:
		var img := render(_generic(race, 7 + i * 5), p, fposmod(tt + 0.5 * (i + 1), 1.0))
		PartyIcon._paste(cv2, img, anchor + (offs[i] as Vector2) - fa, 0.82)
	PartyIcon._paste(cv2, render(lead, p, tt), anchor - fa, 1.0)
	return {"image": cv2.to_image(), "anchor": anchor}

static func _generic(race: String, seed: int) -> Dictionary:
	var rd: Dictionary = DB.races.get(race, {})
	var cols: Array = rd.get("art", {}).get("colors", ["#888888"])
	return {"race": race, "skin": Color(cols[seed % cols.size()]), "hair": Color(rd.get("art", {}).get("belly", "#cccccc")),
		"seed": seed, "team": Color(0, 0, 0, 0), "dead": false, "dmg": {}, "bleed": {}, "lost": [], "blood": 1.0}

## Static map-site picture for a lair kind (wolf_den, bear_den, boar_wallow, bandit_camp); `cleared` greys it.
## Returns {"image", "anchor"} (anchor = ground centre). Drawn once and cached by the map.
static func site(kind: String, cleared: bool = false) -> Dictionary:
	var W := 40
	var H := 30
	var c := PixelCanvas.new(W, H)
	var g := Vector2(W * 0.5, H - 6.0)
	c.set_frame(Vector2.ZERO)
	var rock := Color("#8d8680")
	var dark := Color("#2a2024")
	match kind:
		"wolf_den", "bear_den":
			var big := kind == "bear_den"
			var r := 11.0 if big else 9.0
			c.begin()
			c.ellipse(g + Vector2(0, -r * 0.45), r + 3.0, r * 0.75, rock)
			c.ellipse(g + Vector2(-r * 0.7, -2.0), r * 0.55, r * 0.45, rock.darkened(0.1))
			c.end(ol(rock), 0.16)
			c.begin()
			c.ellipse(g + Vector2(1.0, -r * 0.25), r * 0.5, r * 0.42, dark)
			c.rect(Rect2(g + Vector2(1.0 - r * 0.5, -r * 0.25), Vector2(r, r * 0.25 + 0.5)), dark)
			c.end(Color(0, 0, 0, 0), 0.0)
			# bones by the mouth
			for x in [-4.0, 5.0]:
				c.begin()
				c.capsule(g + Vector2(x, 1.0), g + Vector2(x + 2.5, 0.0), 0.5, Color("#efe6cc"))
				c.end(ol(Color("#efe6cc")), 0.0)
			if not big:
				c.begin()
				for k in 3:
					c.poly(PackedVector2Array([g + Vector2(-12 + k * 2.0, -r), g + Vector2(-11 + k * 2.0, -r - 6.0), g + Vector2(-10 + k * 2.0, -r)]), Color("#2f6e3a"))
				c.end(ol(Color("#2f6e3a")), 0.1)
		"boar_wallow":
			c.begin()
			c.ellipse(g + Vector2(0, -2.0), 13.0, 4.5, Color("#6a4a2a"))
			c.end(ol(Color("#6a4a2a")), 0.12)
			c.begin()
			c.ellipse(g + Vector2(1.0, -2.0), 8.0, 2.4, Color("#4a3420"))
			c.end(Color(0, 0, 0, 0), 0.08)
			c.begin()
			for k in 5:
				var x := -13.0 + k * 6.5
				c.capsule(g + Vector2(x, -3.0), g + Vector2(x + (k % 2) * 1.5 - 0.5, -12.0 - (k % 3) * 2.0), 0.6, Color("#7aa24a"))
			c.end(ol(Color("#7aa24a")), 0.1)
		"bandit_camp":
			# palisade, two tents, a fire
			var wood := Color("#7a5230")
			c.begin()
			for k in 9:
				var x := -16.0 + k * 4.0
				c.rect(Rect2(g + Vector2(x, -7.0), Vector2(2.0, 7.0)), wood)
				c.poly(PackedVector2Array([g + Vector2(x, -7.0), g + Vector2(x + 1.0, -9.0), g + Vector2(x + 2.0, -7.0)]), wood)
			c.end(ol(wood), 0.12)
			for tp in [[Vector2(-7, -8), Color("#a03030")], [Vector2(6, -9), Color("#c8b890")]]:
				var tc: Color = tp[1]
				var o: Vector2 = g + (tp[0] as Vector2)
				c.begin()
				c.poly(PackedVector2Array([o + Vector2(-6, 0), o + Vector2(0, -9), o + Vector2(6, 0)]), tc)
				c.end(ol(tc), 0.14)
				c.dot(o + Vector2(0, -2), dark)
			c.begin()
			c.ellipse(g + Vector2(0, -2.0), 1.8, 1.2, Color("#ffb020"))
			c.end(ol(Color("#c04010")), 0.0)
			c.dot(g + Vector2(0, -4.0), Color("#ffe080"))
	if cleared:
		for i in c.buf.size():
			var col: Color = c.buf[i]
			if col.a > 0.0:
				var v := col.get_luminance() * 0.7
				c.buf[i] = Color(v, v, v, col.a * 0.8)
	return {"image": c.to_image(), "anchor": g}
