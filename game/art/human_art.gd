class_name HumanArt
extends RefCounted
## Human illustration on FigurePainter's original joint graph. No animation state lives here.

const HEAD_SCALE: float = 0.65
static var _force_legacy_v062: bool = false

static func _poly(cv: PixelCanvas, o: Vector2, points: Array, c: Color) -> void:
	var p: PackedVector2Array = PackedVector2Array()
	for q in points:
		p.append(o + Vector2(float(q[0]), float(q[1])))
	cv.poly(p, c)

## Renders the pre-v0.063 flat-polygon human for before/after lineup comparisons.
static func render_legacy_v062(sp: Dictionary) -> Image:
	_force_legacy_v062 = true
	var fp := FigurePainter.new(sp)
	var dm := FigurePainter.frame_dims(sp, "idle")
	var sz: Vector2i = dm["size"]
	var anchor: Vector2 = dm["anchor"]
	fp.cv = PixelCanvas.new(sz.x, sz.y)
	var raster := FigurePainter.raster_scale("human")
	fp._ring(anchor, false)
	fp.cv.set_frame(anchor, raster, 0.0)
	fp.pose = "idle"
	fp.t = 0.0
	var A := fp.arm_a + fp.arm_b
	var hip := Vector2(0.0, -fp.leg_len)
	var sc := hip + Vector2(0.0, -fp.torso_len)
	fp.j = {
		"hip": hip, "sc": sc, "hc": sc + Vector2(0.5, -fp.head_h * 0.5),
		"sr": sc + Vector2(-1.0, 1.0), "sl": sc + Vector2(1.5, 1.0),
	}
	var wk := fp._wkind()
	var hr_off := Vector2(1.5, 0.85 * A) if wk == "none" else Vector2(3.0, 0.6 * A)
	var hl_off := Vector2(fp.tw * 0.5 + 1.5, 0.42 * A) if not fp._it("shield").is_empty() else Vector2(2.5, 0.8 * A)
	fp.j["hr"] = FigurePainter._reach(fp.j["sr"], sc + hr_off, A - 0.05)
	fp.j["er"] = FigurePainter._ik(fp.j["sr"], fp.j["hr"], fp.arm_a, fp.arm_b, 1.0)
	fp.j["grip"] = fp.j["hr"]
	fp.j["wdir"] = Vector2.from_angle(deg_to_rad(60.0 if wk == "none" else -62.0))
	fp.j["hl"] = FigurePainter._reach(fp.j["sl"], sc + hl_off, A - 0.05)
	fp.j["el"] = FigurePainter._ik(fp.j["sl"], fp.j["hl"], fp.arm_a, fp.arm_b, 1.0)
	fp.j["pr"] = hip + Vector2(-1.0, 0.0)
	fp.j["pl"] = hip + Vector2(1.0, 0.0)
	fp.j["fr"] = Vector2(-1.0, -1.5)
	fp.j["fl"] = Vector2(1.0, -1.5)
	fp.j["kr"] = FigurePainter._ik(fp.j["pr"], fp.j["fr"], fp.leg_len * 0.5, fp.leg_len * 0.5 - 1.0, -1.0)
	fp.j["kl"] = FigurePainter._ik(fp.j["pl"], fp.j["fl"], fp.leg_len * 0.5, fp.leg_len * 0.5 - 1.0, -1.0)
	fp._draw_figure(true)
	_force_legacy_v062 = false
	return fp.cv.to_image()

static func head(f) -> void:
	if f._lost("head"):
		return
	if _force_legacy_v062:
		_legacy_head(f)
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var sc: Vector2 = f.j["sc"]
	var female: bool = _female(f)
	var age: int = int(f.spec.get("age", 28))
	var seed: int = absi(int(f.spec.get("seed", 0)))
	var style: int = seed % 6
	if female and style in [2, 3]:
		style = 1 if (seed % 2 == 0) else 4
	var skin: Color = f.skin
	var hair_col: Color = f.hair
	if age >= 52:
		hair_col = hair_col.lerp(Color("#bfc4cc"), clampf(float(age - 46) / 28.0, 0.25, 0.78))
	# Scale head, hair, beard and fitted helm around hc to ~1/7th total figure height
	var before: Transform2D = cv.xf
	var before_k: float = cv.k
	var eff_scale: float = 0.74 if before_k > 10.0 else HEAD_SCALE
	var pivot: Vector2 = hc + Vector2(0.0, 0.44 if before_k > 10.0 else 0.22)
	cv.xf = before * Transform2D(0.0, Vector2(eff_scale, eff_scale), 0.0, pivot * (1.0 - eff_scale))
	cv.k = before_k * eff_scale
	_shaded_head_inner(f, hc, skin, hair_col, female, age, seed, style)
	cv.xf = before
	cv.k = before_k

static func _shaded_head_inner(f, hc: Vector2, skin: Color, hair: Color, female: bool, age: int, seed: int, style: int) -> void:
	var cv: PixelCanvas = f.cv
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead", false))
	var bearded: bool = bool(f.spec.get("beard", false)) and not female and not f._lost("jaw")
	var coif: bool = String(f._it("helm").get("sprite", "")) == "coif"
	var jaw_lost: bool = f._lost("jaw")
	var refined: bool = female and FigurePainter.female_variant(f.spec) == 1
	var jaw_w: float = (1.62 if refined else 1.72) if female else (1.92 + 0.08 * float(seed % 4))
	var nose_ext: float = (0.04 if female else 0.11) * float((seed / 4) % 4)
	var sh := cv.shaded()
	var m_skin := sh.add_color(skin, 0.12 if female else 0.09, 1.06)
	var m_hair := sh.add_color(hair, 0.18, 1.12, hair.lightened(0.35))
	# Back hair mass for long / braided styles
	if style in [1, 4] or (female and style in [0, 1, 4, 5]):
		sh.capsule(hc + Vector2(-1.85, -1.4), hc + Vector2(-2.55, 2.8), 1.35, 1.05, m_hair, -1.5)
		if style == 4:
			sh.capsule(hc + Vector2(-2.4, 0.2), hc + Vector2(-3.5, 4.3), 0.72, 0.48, m_hair, -1.2)
	# Unified full-head 2.5D volume (avoids mid-face shadow crease) + jaw/chin taper
	var chin_y: float = (2.25 if female else 2.45) if not jaw_lost else 0.95
	var skull_pts := PackedVector2Array([
		hc + Vector2(-2.15, -1.55), hc + Vector2(-1.45, -2.70), hc + Vector2(0.25, -2.82),
		hc + Vector2(1.65, -2.25), hc + Vector2(2.08, -0.85), hc + Vector2(2.05, 0.35),
		hc + Vector2(1.65 if not jaw_lost else 1.45, 1.55 if not jaw_lost else 0.85),
		hc + Vector2(0.65, chin_y),
		hc + Vector2(-0.55, chin_y - 0.18),
		hc + Vector2(-1.68, 1.25 if not jaw_lost else 0.75), hc + Vector2(-2.12, 0.10)
	])
	sh.poly(skull_pts, m_skin, 1.8, 2.1)
	sh.ellipsoid(hc + Vector2(0.02, -0.22 if not jaw_lost else -0.65), 2.12 if female else 2.24, (2.45 if female else 2.60) if not jaw_lost else 1.85, m_skin, 2.0, 0.90)
	if not jaw_lost:
		sh.capsule(hc + Vector2(-0.45, 1.18), hc + Vector2(0.72, chin_y - 0.35), jaw_w * 0.56, 0.78 if female else 0.92, m_skin, 2.15, 0.75)
	# Brow & cheekbone volumes on the front face plane
	sh.capsule(hc + Vector2(-0.68, -0.76), hc + Vector2(1.52, -0.74), 0.38 if female else 0.46, 0.36 if female else 0.42, m_skin, 2.45, 0.65)
	sh.ellipsoid(hc + Vector2(-0.28, 0.32), 0.78, 0.58, m_skin, 2.35, 0.55)
	sh.ellipsoid(hc + Vector2(1.18, 0.30), 0.68, 0.54, m_skin, 2.35, 0.55)
	# Nose bridge & tip centered between the two eyes on the front plane
	var n_tip := hc + Vector2((0.78 if female else 0.88) + nose_ext, 0.52 if female else 0.58)
	if not f._lost("nose"):
		sh.capsule(hc + Vector2(0.55, -0.24), n_tip, 0.32 if female else 0.38, 0.38 if female else 0.46, m_skin, 2.9, 0.85)
		sh.ellipsoid(n_tip, 0.42 if female else 0.50, 0.34 if female else 0.40, m_skin, 3.05, 0.85)
	# Ear
	if not coif and not f._lost("ear_r"):
		sh.ellipsoid(hc + Vector2(-1.88, -0.05), 0.56, 0.82, m_skin, 2.3, 0.80)
	# Top & temple hair volume
	if style != 3:
		sh.ellipsoid(hc + Vector2(-0.22, -2.18), 2.35, 1.28, m_hair, 3.2)
		if style != 2:
			sh.capsule(hc + Vector2(-2.05, -1.75), hc + Vector2(-1.82, 0.15), 0.78, 0.55, m_hair, 3.1)
			sh.capsule(hc + Vector2(-1.2, -2.55), hc + Vector2(1.65, -2.15), 0.82, 0.58, m_hair, 3.3)
		if style == 5:
			sh.capsule(hc + Vector2(-1.1, -3.1), hc + Vector2(0.55, -2.95), 0.72, 0.55, m_hair, 3.5)
	# Beard volume (for bearded men: lower beard starts below mouth y=1.22 so mouth remains visible)
	var bstyle: int = FigurePainter.beard_style(f.spec) if bearded else -1
	if bearded and bstyle != 6 and bstyle != 7:
		var blen: float = 0.7 + 0.35 * float((seed / 5) % 3)
		sh.capsule(hc + Vector2(-1.35, 0.65), hc + Vector2(-0.35, 1.95), 0.62, 0.78, m_hair, 3.15)
		sh.capsule(hc + Vector2(1.65, 0.75), hc + Vector2(1.15, 1.95), 0.58, 0.72, m_hair, 3.15)
		if bstyle == 1:
			sh.capsule(hc + Vector2(-0.75, 1.78), hc + Vector2(0.85, 2.45), 0.82, 0.92, m_hair, 3.25)
			sh.capsule(hc + Vector2(0.35, 2.38), hc + Vector2(1.45, 1.75), 0.88, 0.72, m_hair, 3.25)
		elif bstyle == 2:
			sh.ellipsoid(hc + Vector2(0.45, 2.45), 1.78, 1.25, m_hair, 3.3)
		elif bstyle == 3:
			sh.capsule(hc + Vector2(-0.75, 1.72), hc + Vector2(0.68, 4.15), 1.05, 0.48, m_hair, 3.3)
			sh.capsule(hc + Vector2(1.45, 1.75), hc + Vector2(0.68, 4.15), 0.95, 0.45, m_hair, 3.3)
		elif bstyle == 4:
			sh.capsule(hc + Vector2(-0.65, 1.72), hc + Vector2(-0.15, 3.95), 0.92, 0.48, m_hair, 3.3)
			sh.capsule(hc + Vector2(1.35, 1.72), hc + Vector2(1.12, 3.95), 0.92, 0.48, m_hair, 3.3)
		elif bstyle == 5:
			sh.ellipsoid(hc + Vector2(0.45, 2.32), 1.55, 1.02, m_hair, 3.3)
			sh.capsule(hc + Vector2(0.65, 2.65), hc + Vector2(0.75, 4.35), 0.58, 0.42, m_hair, 3.4)
		else:
			sh.ellipsoid(hc + Vector2(0.45, 2.35 + blen * 0.35), 1.65, 1.05 + blen * 0.38, m_hair, 3.3)
	sh.composite(FigurePainter.ol(skin), true)
	# Facial features: both eyes on the front plane at mid-head height, straddling nose, mouth below
	var shadow: Color = skin.darkened(0.26).lerp(Color("#693d37"), 0.14)
	var deep: Color = skin.darkened(0.48).lerp(Color("#49302b"), 0.22)
	var lip: Color = skin.darkened(0.24 if female else 0.34).lerp(Color("#944642" if female else "#7a3836"), 0.34)
	var iris: Color = [Color("#574632"), Color("#45534b"), Color("#4e5966"), Color("#634e39")][(seed / 7) % 4]
	var eye_y: float = -0.20 if female else -0.18
	for eye_side in ["r", "l"]:
		if f._lost("eye_" + eye_side):
			continue
		var near: bool = eye_side == "r"
		var ex: float = (-0.18 if female else -0.15) if near else (1.15 if female else 1.22)
		var ey: float = eye_y
		var ew: float = (0.54 if female else 0.52) if near else (0.36 if female else 0.35)
		var brow_c: Color = hair.darkened(0.22).lerp(deep, 0.35)
		cv.capsule(hc + Vector2(ex - ew, ey - 0.44), hc + Vector2(ex + ew * 0.85, ey - 0.48), 0.12 if female else 0.16, brow_c)
		if dead:
			cv.capsule(hc + Vector2(ex - ew * 0.8, ey + 0.02), hc + Vector2(ex + ew * 0.8, ey + 0.04), 0.14, deep)
		else:
			cv.ellipse(hc + Vector2(ex, ey), ew, 0.27, Color("#eee6d8"))
			cv.ellipse(hc + Vector2(ex + ew * 0.22, ey + 0.01), 0.23 if near else 0.15, 0.23, iris)
			cv.ellipse(hc + Vector2(ex + ew * 0.28, ey + 0.01), 0.11, 0.17, Color("#1c1817"))
			cv.capsule(hc + Vector2(ex - ew, ey - 0.14), hc + Vector2(ex + ew * 0.82, ey - 0.16), 0.11, deep)
	if not f._lost("nose"):
		cv.capsule(n_tip + Vector2(-0.22, 0.12), n_tip + Vector2(0.12, 0.10), 0.10, deep)
	if age >= 42:
		var w_col := shadow.darkened(clampf(float(age - 38) * 0.012, 0.05, 0.32))
		cv.capsule(hc + Vector2(-0.35, -1.15), hc + Vector2(1.05, -1.12), 0.10, w_col)
		cv.capsule(hc + Vector2(-0.45, 0.42), hc + Vector2(-0.15, 0.85), 0.10, w_col)
		cv.capsule(hc + Vector2(1.35, 0.45), hc + Vector2(1.18, 0.88), 0.10, w_col)
	elif age <= 20:
		cv.ellipse(hc + Vector2(-0.32, 0.36), 0.45, 0.28, skin.lightened(0.12).lerp(Color("#e88a7d"), 0.18))
	if bearded and bstyle in [6, 7]:
		_male_beard(f, hc, bstyle)
	elif bearded and not f._lost("mouth"):
		_male_moustache(cv, hc, hair, false)
	if not jaw_lost and not f._lost("mouth"):
		var my: float = 1.16 if female else 1.22
		cv.capsule(hc + Vector2(0.16 if female else 0.18, my), hc + Vector2(1.14 if female else 1.22, my - 0.02), 0.15, lip)
		if female:
			cv.capsule(hc + Vector2(0.32, my + 0.12), hc + Vector2(0.98, my + 0.11), 0.11, lip.lightened(0.18))
	if String(f.spec.get("role", "")) == "ruler" and f._it("helm").is_empty():
		var gold := FigurePainter.metal("copper", 3)
		cv.begin()
		cv.capsule(hc + Vector2(-2.05, -2.05), hc + Vector2(2.05, -1.95), 0.28, Color("#e8bd48"))
		cv.poly(PackedVector2Array([hc + Vector2(-0.3, -2.0), hc + Vector2(0.2, -2.95), hc + Vector2(0.7, -2.0)]), Color("#ffd966"))
		cv.poly(PackedVector2Array([hc + Vector2(1.1, -1.98), hc + Vector2(1.55, -2.75), hc + Vector2(1.9, -1.95)]), Color("#ffd966"))
		cv.ellipse(hc + Vector2(0.2, -2.2), 0.22, 0.22, Color("#d42c38"))
		cv.end(gold["outline"], 0.10, Color("#fff4c2"))
	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5, -float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _legacy_head(f) -> void:
	if _female(f):
		_female_head(f)
		return
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var seed: int = absi(int(f.spec.get("seed", 0)))
	var skin: Color = f.skin
	var hair: Color = f.hair
	var shadow: Color = skin.darkened(0.23).lerp(Color("#693d37"), 0.13)
	var deep: Color = skin.darkened(0.46).lerp(Color("#49302b"), 0.22)
	var light: Color = skin.lightened(0.18)
	var lip: Color = skin.darkened(0.34).lerp(Color("#7a3836"), 0.22)
	var female: bool = String(f.spec.get("sex", "")).to_lower() in ["female", "f", "woman"]
	var age: int = int(f.spec.get("age", 28))
	var jaw: float = 0.12 * float(seed % 4) - (0.28 if female else 0.0)
	var nose: float = 0.13 * float((seed / 4) % 4)
	var brow_y: float = -0.9 + 0.06 * float((seed / 11) % 3)
	var style: int = seed % 6
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead", false))
	var bearded: bool = bool(f.spec.get("beard", false)) and not female
	var coif: bool = String(f._it("helm").get("sprite", "")) == "coif"
	# Long hair and the tied braid sit behind the skull, never in front of the eyes.
	if style in [1, 4]:
		cv.begin()
		_poly(cv, hc, [[-2.7,-2.6],[-1.5,-2.8],[-1.7,1.6],[-1.2,3.9],[-2.3,4.4],[-3.3,2.9],[-3.4,0.0]], hair.darkened(0.16))
		if style == 4:
			cv.capsule(hc + Vector2(-2.8,-0.7), hc + Vector2(-4.1,3.1), 0.55, hair)
			cv.capsule(hc + Vector2(-4.1,3.1), hc + Vector2(-3.7,4.9), 0.46, hair)
		cv.end(FigurePainter.ol(hair), 0.06)
		cv.capsule(hc + Vector2(-2.6,0.0), hc + Vector2(-2.4,3.2), 0.14, hair.lightened(0.21))
		if style == 4:
			for i in 5:
				var p: Vector2 = hc + Vector2(-3.1 - 0.18 * float(i), 0.15 + 0.7 * float(i))
				cv.capsule(p + Vector2(-0.22,-0.14), p + Vector2(0.28,0.2), 0.12, hair.lightened(0.23))
	# Neck remains on the original shoulder anchor; its taper gives the jaw a clear break.
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc + Vector2(-0.9,1.8), hc + Vector2(1.5,2.2), sc + Vector2(1.5,0.8), sc + Vector2(-1.25,0.5)]), shadow)
		cv.end(FigurePainter.ol(skin), 0.04)
	# Unequal temples, a recessed eye bridge and an angled jaw replace the old chamfered box.
	cv.begin()
	_poly(cv, hc, [[-2.35,-2.1],[-1.65,-2.9],[0.05,-3.07],[1.75,-2.64],[2.45,-1.75],
		[2.42,-0.88],[2.17,-0.5],[2.32,0.18],[2.59,0.87],[2.37,1.38],
		[2.06,2.18],[1.0+jaw,2.83],[-0.23,2.72],[-1.53-jaw,1.85],[-2.1,0.35]], skin)
	_poly(cv, hc, [[-2.3,-1.8],[-1.2,-2.6],[-1.05,0.1],[-0.5,1.53],[0.95,2.74],[-0.28,2.72],[-1.65,1.65],[-2.12,0.15]], shadow)
	_poly(cv, hc, [[-0.9,-2.55],[0.45,-2.88],[1.74,-2.43],[1.97,-1.63],[0.7,-1.3],[-0.93,-1.6]], light)
	_poly(cv, hc, [[0.1,0.16],[1.5,-0.01],[2.33,0.55],[1.91,1.04],[0.55,1.1]], light)
	_poly(cv, hc, [[0.37,1.17],[1.9,1.13],[2.04,1.83],[1.02+jaw,2.63],[0.11,2.44]], skin.darkened(0.08))
	# The nose has a bridge, tip and underside rather than one square at the edge.
	if not f._lost("nose"):
		_poly(cv, hc, [[1.96,-1.33],[2.4,-1.22],[2.58,-0.28],[3.08+nose,0.32],[2.91+nose,0.67],[2.1,0.67],[1.98,0.27]], skin)
		_poly(cv, hc, [[2.25,-1.1],[2.43,-0.25],[2.94+nose,0.28],[2.55,0.35],[2.2,0.13]], light)
		cv.capsule(hc + Vector2(2.5,0.55), hc + Vector2(2.91+nose,0.48), 0.13, deep)
	cv.end(FigurePainter.ol(skin), 0.06)
	# Ear cartilage is an actual curved side feature and respects anatomical loss.
	if not coif and not f._lost("ear_r"):
		cv.begin()
		cv.ellipse(hc + Vector2(-1.83,-0.06), 0.61, 0.86, skin)
		cv.end(FigurePainter.ol(skin), 0.04)
		cv.capsule(hc + Vector2(-1.93,-0.42), hc + Vector2(-1.72,0.24), 0.15, shadow)
		cv.ellipse(hc + Vector2(-1.71,0.04), 0.2, 0.29, deep)
	# Restrained eye whites and iris keep an adult face readable at battle size.
	var iris: Color = [Color("#574632"), Color("#45534b"), Color("#4e5966"), Color("#634e39")][(seed / 7) % 4]
	for eye_side in ["r", "l"]:
		if f._lost("eye_" + eye_side):
			continue
		var near: bool = eye_side == "r"
		var ex: float = 0.9 if near else 2.19
		var ey: float = brow_y + (0.04 if near else -0.04)
		var ew: float = 0.67 if near else 0.3
		var brow: Color = hair.darkened(0.25).lerp(deep, 0.36)
		var brow_r: float = 0.12 if female else 0.16
		cv.capsule(hc + Vector2(ex-ew,ey-0.46), hc + Vector2(ex+ew*0.72,ey-0.57), brow_r, brow)
		cv.capsule(hc + Vector2(ex-ew,ey+0.38), hc + Vector2(ex+ew*0.85,ey+0.3), 0.1, shadow)
		if dead:
			cv.capsule(hc + Vector2(ex-ew*0.8,ey+0.06), hc + Vector2(ex+ew*0.7,ey+0.15), 0.14, deep)
		else:
			cv.ellipse(hc + Vector2(ex,ey+0.04), ew, 0.29, skin.lightened(0.65).lerp(Color("#e5d9c2"),0.4))
			cv.ellipse(hc + Vector2(ex+ew*0.37,ey+0.07), 0.23 if near else 0.14, 0.24, iris)
			cv.ellipse(hc + Vector2(ex+ew*0.48,ey+0.04), 0.1, 0.19, Color("#201c1a"))
			cv.capsule(hc + Vector2(ex-ew,ey-0.1), hc + Vector2(ex+ew*0.75,ey-0.2), 0.12, deep)
	if age >= 45:
		cv.capsule(hc+Vector2(-0.1,0.37),hc+Vector2(0.42,0.56),0.08,shadow)
		cv.capsule(hc+Vector2(1.62,0.86),hc+Vector2(1.49,1.2),0.08,shadow)
	# Organic hairline: swept crop, waves, receding crown, long part and tied braid.
	if style != 3:
		cv.begin()
		if style == 2:
			_poly(cv,hc,[[-2.55,-2.2],[-1.6,-3.08],[-0.55,-3.22],[-0.7,-2.5],[-1.38,-2.01],[-1.61,-0.47],[-2.4,-0.08]],hair)
			_poly(cv,hc,[[0.98,-2.96],[1.8,-2.75],[2.16,-2.15],[1.37,-2.34]],hair)
		else:
			_poly(cv,hc,[[-2.6,-1.99],[-2.22,-3.02],[-1.02,-3.47],[0.5,-3.45],[1.79,-3.04],[2.28,-2.4],
				[1.85,-1.83],[1.25,-2.07],[0.73,-1.79],[0.25,-2.12],[-0.64,-1.55],[-1.18,-1.64],[-1.43,-0.38],[-2.15,0.0]],hair)
			if style == 5:
				_poly(cv,hc,[[-1.72,-3.05],[-0.9,-3.78],[0.53,-3.57],[1.02,-3.16],[0.02,-2.75]],hair)
		cv.end(FigurePainter.ol(hair),0.08)
		cv.capsule(hc+Vector2(-1.85,-2.72),hc+Vector2(-0.5,-2.95),0.18,hair.lightened(0.28))
		cv.capsule(hc+Vector2(-0.3,-3.06),hc+Vector2(1.38,-2.62),0.12,hair.lightened(0.21))
		cv.capsule(hc+Vector2(-1.75,-1.85),hc+Vector2(-1.99,-0.58),0.12,hair.lightened(0.17))
	if bearded and not f._lost("jaw"):
		var beard_style: int = FigurePainter.beard_style(f.spec)
		if beard_style > 0:
			_male_beard(f,hc,beard_style)
		else:
			var length: float = 0.65 + 0.33 * float((seed / 5) % 3)
			cv.begin()
			_poly(cv,hc,[[-1.45,0.42],[-0.94,0.73],[-0.37,1.57],[0.73,1.81],[1.82,1.66],[2.38,1.02],[2.42,1.8],
				[1.46,2.7+length],[0.42,3.04+length],[-0.66,2.43+length],[-1.5,1.33]],hair.darkened(0.07))
			cv.end(FigurePainter.ol(hair),0.04)
			for i in 4:
				var bx: float = -0.63 + float(i)*0.57
				cv.capsule(hc+Vector2(bx,2.0),hc+Vector2(bx+0.17,2.8+length*0.65),0.1,hair.lightened(0.19))
			# Split moustache preserves the lips instead of replacing the lower face with a rectangle.
			cv.capsule(hc+Vector2(1.12,0.96),hc+Vector2(2.21,1.03),0.26,hair)
	if not f._lost("mouth"):
		cv.capsule(hc+Vector2(1.13,1.47),hc+Vector2(2.22,1.38),0.13,lip)
		if not bearded:
			cv.capsule(hc+Vector2(1.4,1.72),hc+Vector2(1.98,1.67),0.12,light)
	# Equipment is still the real FigurePainter item layer, drawn over the new anatomy.
	f._helm(hc, -float(f.head_w)*0.5, float(f.head_w)*0.5, -float(f.head_h)*0.5, float(f.head_h)*0.5)

static func _tp(f, x: float, y: float) -> Vector2:
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var len: float = float(f.torso_len)
	return sc.lerp(hip, minf(y / len, 1.0)) + Vector2(x, maxf(y-len,0.0))

static func _body_shape(f, skirt: float, spread: float) -> PackedVector2Array:
	var w: float = float(f.tw)*0.5
	var h: float = float(f.hipw)*0.5
	var l: float = float(f.torso_len)
	return PackedVector2Array([_tp(f,-w+0.7,0.05),_tp(f,-1.38,-0.16),_tp(f,1.25,-0.16),_tp(f,w-0.45,0.35),
		_tp(f,w+0.02,l*0.29),_tp(f,h-0.3,l*0.83),_tp(f,h+0.25+spread,l+skirt-0.42),
		_tp(f,h-0.2+spread,l+skirt),_tp(f,0.8,l+skirt-0.17),_tp(f,0.3,l+skirt-0.55),
		_tp(f,-0.4,l+skirt-0.08),_tp(f,-h-0.2-spread,l+skirt),_tp(f,-h-0.57-spread,l+skirt-0.44),
		_tp(f,-h+0.32,l*0.83),_tp(f,-w-0.25,l*0.3)])

static func _surface(f, origin: Vector2, cloth: bool, kind: String = "", m: Dictionary = {}) -> Callable:
	var inverse: Transform2D = f.cv.xf.affine_inverse()
	var w: float = float(f.tw)
	var len: float = float(f.torso_len)
	var detail: bool = f.cv.k >= 2.0
	return func(x: int, y: int, c: Color) -> Color:
		var p: Vector2 = inverse * Vector2(float(x)+0.5,float(y)+0.5) - origin
		var shade: float = clampf((p.x+w*0.35)/w,0.0,1.0)
		var out: Color = c.lightened(0.12).lerp(c.darkened(0.24), shade)
		if cloth:
			if p.y > 1.4 and absf(p.x-0.75-0.08*p.y) < 0.2: out = out.darkened(0.14)
			if p.y > len*0.65 and absf(p.x+1.7+0.12*p.y) < 0.18: out = out.lightened(0.14)
			return out
		if not detail: return out
		if kind in ["mail","byrnie"]:
			var row: int = floori(p.y/0.69)
			var dx: float = fposmod(p.x+float(posmod(row,2))*0.4,0.8)-0.4
			var dy: float = fposmod(p.y,0.69)-0.33
			var ring: float = dx*dx/0.115+dy*dy/0.062
			if ring < 0.39: return out.darkened(0.19)
			if ring < 1.0 and dy < -0.05: return out.lightened(0.2)
			return out
		if kind == "scale":
			var row: int = floori(p.y/0.87)
			var dx: float = fposmod(p.x+float(posmod(row,2))*0.48,0.96)-0.48
			var dy: float = fposmod(p.y,0.87)
			if dy > 0.57+0.22*(1.0-absf(dx)/0.48): return out.darkened(0.25)
			if dy < 0.12 and absf(dx)<0.3: return out.lightened(0.21)
			return out
		if kind == "lamellar":
			var dx: float = fposmod(p.x,0.87)
			var dy: float = fposmod(p.y,1.4)
			if dx < 0.09 or dy > 1.2: return out.darkened(0.24)
			if dy < 0.15: return out.lightened(0.23)
			if dx > 0.26 and dx < 0.42 and dy > 0.66 and dy < 1.01: return (f.sec as Color).darkened(0.22)
		return out

static func torso(f) -> bool:
	if _force_legacy_v062:
		var cv_leg: PixelCanvas = f.cv
		var sc_leg: Vector2 = f.j["sc"]
		if f._it("clothing").is_empty() and f._it("body").is_empty():
			cv_leg.begin()
			cv_leg.poly(_female_body_shape(f,0.7,0.0) if _female(f) else _body_shape(f,0.7,0.0),f.skin,_surface(f,sc_leg,true))
			cv_leg.capsule(_tp(f,-1.7,1.35),_tp(f,0.1,1.85),0.17,f.skin.lightened(0.15))
			cv_leg.capsule(_tp(f,0.1,1.85),_tp(f,2.3,1.3),0.13,f.skin.darkened(0.2))
			cv_leg.end(FigurePainter.ol(f.skin),0.07)
		else:
			worn_chest(f,false)
		worn_torso(f,false)
		return true
	var cv: PixelCanvas = f.cv
	var l: float = float(f.torso_len)
	var female: bool = _female(f)
	var mounted: bool = f.pose == "mounted"
	var cl: Dictionary = f._it("clothing")
	var armor: Dictionary = f._it("body")
	var sh := cv.shaded()
	var m_skin := sh.add_color(f.skin, 0.10, 1.05)
	# Cylindrical 2.5D neck and collarbone triangle at top of chest (sits behind tunic collar)
	if not f._lost("neck"):
		sh.capsule(f.j["hc"] + Vector2(-0.08, 1.05), _tp(f, 0.04, 0.48), 0.54 if female else 0.64, 0.64 if female else 0.76, m_skin, 1.15)
	sh.capsule(_tp(f, -1.65 if not female else -1.45, 0.45), _tp(f, 1.55 if not female else 1.35, 0.45), 0.65, 0.65, m_skin, 1.0)
	sh.ellipsoid(_tp(f, 0.0, 0.65), 1.05, 0.65, m_skin, 1.2)
	var sh_w: float = 2.05 if female else 2.45
	var ch_w: float = 1.65 if female else 1.98
	var wa_w: float = 1.22 if female else 1.52
	var hp_w: float = 1.82 if female else 1.78
	if cl.is_empty() and armor.is_empty():
		sh.capsule(_tp(f, -sh_w + 0.4, 0.75), _tp(f, sh_w - 0.4, 0.75), 0.85, 0.85, m_skin, 1.5)
		sh.ellipsoid(_tp(f, 0.0, l * 0.28), ch_w, l * 0.24, m_skin, 1.8)
		sh.ellipsoid(_tp(f, 0.0, l * 0.62), wa_w, l * 0.22, m_skin, 1.6)
		sh.ellipsoid(_tp(f, 0.0, l * 0.92), hp_w, l * 0.20, m_skin, 1.7)
		if female:
			sh.ellipsoid(_tp(f, -0.52, l * 0.30), 0.78, 0.68, m_skin, 2.3)
			sh.ellipsoid(_tp(f, 0.68, l * 0.29), 0.78, 0.68, m_skin, 2.3)
		sh.composite(FigurePainter.ol(f.skin), true)
		return true
	var c_cloth: Color = _garment_color(f, cl) if not cl.is_empty() else (f.prim as Color)
	var c_trim: Color = f.sec as Color
	var tid_cl: String = String(cl.get("tid", "tunic"))
	var padded: bool = tid_cl in ["gambeson", "padded_jack"]
	var robe: bool = tid_cl == "robe"
	var m_cloth := sh.add_color(c_cloth, 0.07 if padded else 0.11, 1.08)
	var m_trim := sh.add_color(c_trim, 0.18, 1.10)
	var m_belt := sh.add_color(FigurePainter.LEATHER, 0.20, 1.12)
	var hem: float = (0.75 if mounted else (5.8 if robe else (1.85 if padded else 1.35)))
	var pad_add: float = 0.20 if padded else 0.0
	# Sculpted 2.5D torso: broad shoulders -> chest -> tapered waist -> flared hips/tunic skirt
	sh.capsule(_tp(f, -sh_w - pad_add + 0.45, 0.72), _tp(f, sh_w + pad_add - 0.45, 0.72), 0.88, 0.88, m_cloth, 1.6)
	var body_pts := PackedVector2Array([
		_tp(f, -sh_w - pad_add, 0.55),
		_tp(f, -1.05, 0.15),
		_tp(f, 0.05, 0.95),
		_tp(f, 1.02, 0.18),
		_tp(f, sh_w + pad_add - 0.15, 0.58),
		_tp(f, ch_w + pad_add, l * 0.30),
		_tp(f, wa_w + pad_add * 0.7, l * 0.62),
		_tp(f, hp_w + pad_add * 0.8, l * 0.94),
		_tp(f, hp_w + 0.28, l + hem - 0.15),
		_tp(f, 0.48, l + hem),
		_tp(f, 0.12, l + hem - (0.15 if robe else 0.55)),
		_tp(f, -0.25, l + hem),
		_tp(f, -hp_w - 0.28, l + hem - 0.15),
		_tp(f, -hp_w - pad_add * 0.8, l * 0.94),
		_tp(f, -wa_w - pad_add * 0.7, l * 0.62),
		_tp(f, -ch_w - pad_add, l * 0.30),
	])
	sh.poly(body_pts, m_cloth, 1.7, 2.4)
	# Chest & shoulder 3D muscle/bust volumes
	sh.ellipsoid(_tp(f, -0.65, l * 0.27), 0.95 if not female else 0.82, 0.78 if not female else 0.72, m_cloth, 2.2)
	sh.ellipsoid(_tp(f, 0.65, l * 0.27), 0.95 if not female else 0.82, 0.78 if not female else 0.72, m_cloth, 2.2)
	# Tunic skirt vertical drapery folds
	for fx in [-hp_w * 0.68, -hp_w * 0.22, hp_w * 0.28, hp_w * 0.72]:
		sh.capsule(_tp(f, fx * 0.82, l * 0.66), _tp(f, fx, l + hem - 0.22), 0.42, 0.52, m_cloth, 2.15)
	# V-neck collar & lower hem trim
	sh.capsule(_tp(f, -1.08, 0.22), _tp(f, 0.05, 1.05), 0.24, 0.22, m_trim, 2.5)
	sh.capsule(_tp(f, 0.05, 1.05), _tp(f, 1.02, 0.25), 0.22, 0.24, m_trim, 2.5)
	sh.capsule(_tp(f, -hp_w - 0.18, l + hem - 0.18), _tp(f, -0.22, l + hem - 0.12), 0.22, 0.22, m_trim, 2.5)
	sh.capsule(_tp(f, 0.25, l + hem - 0.12), _tp(f, hp_w + 0.18, l + hem - 0.18), 0.22, 0.22, m_trim, 2.5)
	# Cinch belt at natural waist (l * 0.62)
	var belt_y: float = l * 0.62
	var bw: float = wa_w + pad_add * 0.7 + 0.12
	sh.capsule(_tp(f, -bw, belt_y), _tp(f, bw, belt_y), 0.34, 0.34, m_belt, 2.8)
	sh.capsule(_tp(f, 0.35, belt_y + 0.15), _tp(f, 0.52, belt_y + 1.35), 0.24, 0.18, m_belt, 2.85)
	# Body armour layer if equipped
	if not armor.is_empty():
		var kind: String = String(armor.get("sprite", ""))
		var m_arm_dict: Dictionary = FigurePainter.metal(String(armor.get("mat", "copper")), int(armor.get("q", 0)))
		var m_metal := sh.add_color(m_arm_dict["base"], 0.32, 1.18, m_arm_dict["shine"])
		var a_hem: float = 0.45 if kind in ["scale", "byrnie"] else (0.75 if mounted else 1.15)
		var arm_pts := PackedVector2Array([
			_tp(f, -sh_w + 0.1, 0.58), _tp(f, 1.0, 0.35), _tp(f, sh_w - 0.15, 0.60),
			_tp(f, ch_w + 0.12, l * 0.32), _tp(f, wa_w + 0.15, l * 0.62),
			_tp(f, hp_w + 0.12, l + a_hem), _tp(f, -hp_w - 0.12, l + a_hem),
			_tp(f, -wa_w - 0.15, l * 0.62), _tp(f, -ch_w - 0.12, l * 0.32),
		])
		sh.poly(arm_pts, m_metal, 3.0, 2.6)
		sh.ellipsoid(_tp(f, -0.68, l * 0.28), 0.98, 0.82, m_metal, 3.3)
		sh.ellipsoid(_tp(f, 0.68, l * 0.28), 0.98, 0.82, m_metal, 3.3)
		sh.capsule(_tp(f, -bw - 0.08, belt_y), _tp(f, bw + 0.08, belt_y), 0.34, 0.34, m_belt, 3.6)
	sh.composite(FigurePainter.ol(c_cloth), true)
	# Fine specular buckle & armour course accents
	var buckle_col: Color = FigurePainter.metal("copper", 2)["shine"]
	cv.ellipse(_tp(f, 0.35, belt_y), 0.42, 0.34, buckle_col)
	cv.dot(_tp(f, 0.35, belt_y), FigurePainter.LEATHER.darkened(0.35))
	if padded and armor.is_empty():
		for i in 4:
			var qx: float = -wa_w * 0.65 + float(i) * wa_w * 0.44
			cv.capsule(_tp(f, qx, 1.2), _tp(f, qx * 0.85, belt_y - 0.3), 0.08, c_cloth.darkened(0.22))
	if not armor.is_empty():
		var kind: String = String(armor.get("sprite", ""))
		var m_arm_dict: Dictionary = FigurePainter.metal(String(armor.get("mat", "copper")), int(armor.get("q", 0)))
		if kind in ["lamellar", "scale"]:
			for r_idx in 3:
				var ry: float = 1.4 + float(r_idx) * 1.65
				cv.capsule(_tp(f, -wa_w, ry), _tp(f, wa_w, ry), 0.11, m_arm_dict["dark"])
		elif kind in ["mail", "byrnie"]:
			for r_idx in 3:
				var ry: float = 1.5 + float(r_idx) * 1.55
				cv.capsule(_tp(f, -wa_w * 0.8, ry), _tp(f, wa_w * 0.8, ry), 0.08, m_arm_dict["light"])
	return true

static func _belt(f, y: float, leather: Color, buckle: Color) -> void:
	var cv: PixelCanvas = f.cv
	var w: float = float(f.hipw)*0.5
	cv.begin()
	cv.poly(PackedVector2Array([_tp(f,-w-0.05,y-0.3),_tp(f,w+0.07,y-0.25),_tp(f,w,y+0.31),_tp(f,-w,y+0.4)]),leather)
	cv.ellipse(_tp(f,1.63,y+0.04),0.44,0.36,buckle)
	cv.ellipse(_tp(f,1.63,y+0.04),0.22,0.18,leather.darkened(0.35))
	cv.end(FigurePainter.ol(leather),0.03)

static func _limb(cv: PixelCanvas, a: Vector2, b: Vector2, r0: float, r1: float, c: Color) -> void:
	var d: Vector2 = (b-a).normalized()
	var n: Vector2 = Vector2(-d.y,d.x)
	var mid: Vector2 = a.lerp(b,0.37)
	cv.poly(PackedVector2Array([a-n*r0*0.75,a-d*r0*0.35,a+n*r0*0.8,mid+n*r0,
		b+n*r1,b+d*r1*0.4,b-n*r1,mid-n*r0*0.86]),c)
	cv.capsule(a+n*r0*0.2,b+n*r1*0.14,maxf(0.12,r1*0.2),c.lightened(0.12))

static func arm(f, side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var sh_pt: Vector2 = f.j["s"+side]
	var el: Vector2 = f.j["e"+side]
	var hd: Vector2 = f.j["h"+side]
	if f._lost("arm_upper_"+side):
		cv.dot(sh_pt,FigurePainter.BLOOD)
		return true
	var r: float = float(f.arm_r) * (0.86 if _female(f) else 0.94)
	var skin: Color = f.skin
	if side == "l": skin = skin.darkened(0.10)
	var lower_lost: bool = f._lost("arm_lower_"+side)
	var hand_lost: bool = f._lost("hand_"+side)
	if _force_legacy_v062:
		cv.begin()
		_limb(cv,sh_pt,el,r*1.06,r*0.82,skin)
		if not lower_lost:
			_limb(cv,el,hd,r*0.86,r*0.57,skin)
			cv.ellipse(el,r*0.82,r*0.76,skin)
			if not hand_lost:
				cv.ellipse(hd,r*0.81,r*0.94,skin)
				cv.ellipse(hd+Vector2(0.4,-0.36),0.39,0.43,skin.lightened(0.08))
		cv.end(FigurePainter.ol(skin),0.07)
		worn_arm(f,side,false)
		if lower_lost: cv.dot(el,FigurePainter.BLOOD)
		elif hand_lost: cv.dot(hd,FigurePainter.BLOOD)
		return true
	var sh := cv.shaded()
	var m_skin := sh.add_color(skin, 0.09, 1.05)
	sh.capsule(sh_pt, el, r * 0.98, r * 0.78, m_skin, 1.0)
	if not lower_lost:
		sh.capsule(el, hd, r * 0.80, r * 0.56, m_skin, 1.2)
		if not hand_lost:
			sh.ellipsoid(hd, r * 0.72, r * 0.82, m_skin, 1.5)
	var cloth: Dictionary = f._it("clothing")
	if not cloth.is_empty():
		var padded: bool = String(cloth.get("tid", "")) in ["gambeson", "padded_jack"]
		var c_sl: Color = _garment_color(f, cloth)
		if side == "l": c_sl = c_sl.darkened(0.10)
		var m_sl := sh.add_color(c_sl, 0.09, 1.08)
		var m_trim := sh.add_color(f.sec as Color, 0.16, 1.08)
		sh.ellipsoid(sh_pt + Vector2(0.0, 0.15), r * 1.18, r * 1.12, m_sl, 2.0)
		sh.capsule(sh_pt, el, r * (1.18 if padded else 1.08), r * (0.96 if padded else 0.86), m_sl, 1.9)
		if not lower_lost:
			var sl_end: Vector2 = el.lerp(hd, 0.78 if padded else 0.58)
			sh.capsule(el, sl_end, r * 0.90, r * 0.72, m_sl, 2.0)
			sh.capsule(sl_end - Vector2(0.15, 0.0), sl_end + Vector2(0.15, 0.0), r * 0.76, r * 0.76, m_trim, 2.2)
	var body: Dictionary = f._it("body")
	var kind: String = String(body.get("sprite", ""))
	if kind in ["mail", "byrnie", "lamellar", "scrap"]:
		var m_dict: Dictionary = FigurePainter.metal(String(body.get("mat", "copper")), int(body.get("q", 0)))
		var m_arm := sh.add_color(m_dict["base"], 0.30, 1.16, m_dict["shine"])
		var frac: float = 0.75 if kind == "mail" else 0.45
		sh.ellipsoid(sh_pt + Vector2(0.0, 0.1), r * 1.25, r * 1.15, m_arm, 2.5)
		sh.capsule(sh_pt, sh_pt.lerp(el, frac), r * 1.20, r * 0.98, m_arm, 2.4)
	if not lower_lost and not f._it("hands").is_empty():
		var hands: Dictionary = f._it("hands")
		var m_hdict: Dictionary = FigurePainter.metal(String(hands.get("mat", "copper")), int(hands.get("q", 0)))
		var m_hand := sh.add_color(m_hdict["base"], 0.28, 1.15, m_hdict["shine"])
		sh.capsule(el.lerp(hd, 0.25), el.lerp(hd, 0.88), r * 0.92, r * 0.72, m_hand, 2.6)
	sh.composite(FigurePainter.ol(skin), true)
	if lower_lost: cv.dot(el, FigurePainter.BLOOD)
	elif hand_lost: cv.dot(hd, FigurePainter.BLOOD)
	return true

static func leg(f, side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p"+side]
	var kn: Vector2 = f.j["k"+side]
	var ft: Vector2 = f.j["f"+side]
	if f._lost("leg_upper_"+side):
		cv.dot(hp,FigurePainter.BLOOD)
		return true
	var trousers: bool = not f._it("legs_under").is_empty()
	var shoes: bool = not f._it("feet").is_empty()
	var c: Color = f._trouser_col() if trousers else f.skin
	if side == "l": c = c.darkened(0.12)
	var r: float = float(f.leg_r)
	var lower_lost: bool = f._lost("leg_lower_"+side)
	var foot_lost: bool = f._lost("foot_"+side)
	if _force_legacy_v062:
		if trousers:
			worn_pants(f,side,false)
		else:
			cv.begin()
			_limb(cv,hp,kn,r*1.08,r*0.78,c)
			if not lower_lost:
				_limb(cv,kn,ft,r*0.79,r*0.49,c)
				cv.ellipse(kn,r*0.74,r*0.76,c)
			cv.end(FigurePainter.ol(c),0.07)
		if lower_lost:
			cv.dot(kn,FigurePainter.BLOOD)
			return true
		worn_greaves(f,side,false)
		if foot_lost:
			cv.dot(ft,FigurePainter.BLOOD)
			return true
		if shoes:
			worn_shoe(f,side,false)
		else:
			var shoe: Color = f.skin
			cv.begin()
			_poly(cv,ft,[[-0.86,-0.6],[0.63,-0.6],[0.85,-0.08],[1.9,0.36],[2.17,0.92],[1.8,1.28],[-0.96,1.23],[-1.08,0.49]],shoe)
			cv.end(FigurePainter.ol(shoe),0.05)
		return true
	var r_leg: float = r * (0.86 if _female(f) else 0.92)
	var sh := cv.shaded()
	var hose_col: Color = _garment_color(f, f._it("legs_under"), true) if trousers else f.skin
	if side == "l": hose_col = hose_col.darkened(0.10)
	var m_hose := sh.add_color(hose_col, 0.09, 1.08)
	# Upper thigh starting high at hip/pelvis so legs read as ~half the figure's height
	var thigh_top: Vector2 = hp + Vector2(0.0, -0.75 if f.pose != "mounted" else 0.0)
	sh.capsule(thigh_top, kn, r_leg * 1.12, r_leg * 0.78, m_hose, 1.0)
	if not lower_lost:
		var calf_pt: Vector2 = kn.lerp(ft, 0.36) - Vector2(0.18, 0.0)
		sh.ellipsoid(kn, r_leg * 0.78, r_leg * 0.76, m_hose, 1.2)
		sh.capsule(kn, calf_pt, r_leg * 0.78, r_leg * 0.88, m_hose, 1.1)
		sh.capsule(calf_pt, ft, r_leg * 0.88, r_leg * 0.54, m_hose, 1.1)
		var greaves: Dictionary = f._it("legs")
		if not greaves.is_empty():
			var m_gdict: Dictionary = FigurePainter.metal(String(greaves.get("mat", "copper")), int(greaves.get("q", 0)))
			var m_grv := sh.add_color(m_gdict["base"], 0.30, 1.18, m_gdict["shine"])
			sh.ellipsoid(kn + Vector2(0.15, 0.0), r_leg * 0.85, r_leg * 0.78, m_grv, 2.1)
			sh.capsule(kn.lerp(ft, 0.08), kn.lerp(ft, 0.88), r_leg * 0.92, r_leg * 0.64, m_grv, 2.0)
		if not foot_lost:
			var clothed_boot: bool = shoes or trousers or not f._it("clothing").is_empty()
			var boot_col: Color = Color("#4d331e")
			if shoes:
				var fmat: String = String(f._it("feet").get("mat", "leather"))
				boot_col = Color(DB.materials.get(fmat, {}).get("color", "#593a22"))
			elif not clothed_boot:
				boot_col = f.skin
			if side == "l": boot_col = boot_col.darkened(0.10)
			var m_boot := sh.add_color(boot_col, 0.18 if clothed_boot else 0.08, 1.12)
			if clothed_boot:
				var boot_top: Vector2 = kn.lerp(ft, 0.56)
				sh.capsule(boot_top, ft, r_leg * 0.78, r_leg * 0.65, m_boot, 2.3)
				sh.capsule(boot_top + Vector2(-0.45, 0.0), boot_top + Vector2(0.55, 0.05), 0.32, 0.32, m_boot, 2.5)
			sh.capsule(ft + Vector2(-0.55, 0.18), ft + Vector2(1.45, 0.62), 0.68, 0.54, m_boot, 2.4)
			sh.capsule(ft + Vector2(-0.72, 0.75), ft + Vector2(1.62, 0.82), 0.36, 0.32, m_boot, 2.45)
	sh.composite(FigurePainter.ol(hose_col), true)
	if lower_lost:
		cv.dot(kn, FigurePainter.BLOOD)
	elif foot_lost:
		cv.dot(ft, FigurePainter.BLOOD)
	return true

static func _female(f) -> bool:
	return String(f.spec.get("sex", "")).to_lower() in ["female", "f", "woman"]

static func _female_round(cv: PixelCanvas, o: Vector2, points: Array, c: Color) -> void:
	# Two rounds of corner cutting produce graceful local contours on the same raster.
	var p: PackedVector2Array = PackedVector2Array()
	for q in points:
		p.append(Vector2(float(q[0]),float(q[1])))
	for pass_index in 2:
		var smooth: PackedVector2Array = PackedVector2Array()
		for i in p.size():
			var a: Vector2 = p[i]
			var b: Vector2 = p[(i+1)%p.size()]
			smooth.append(a.lerp(b,0.18))
			smooth.append(a.lerp(b,0.82))
		p = smooth
	for i in p.size():
		p[i] += o
	cv.poly(p,c)

static func _female_head(f) -> void:
	if FigurePainter.female_variant(f.spec) == 0:
		_retained_female_head(f)
		return
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var seed: int = absi(int(f.spec.get("seed",0)))
	var age: int = int(f.spec.get("age",28))
	var skin: Color = f.skin
	var hair: Color = f.hair
	var shadow: Color = skin.darkened(0.12).lerp(Color("#765047"),0.055)
	var deep: Color = skin.darkened(0.34).lerp(Color("#45302b"),0.11)
	var light: Color = skin.lightened(0.16)
	var lip: Color = skin.darkened(0.14).lerp(Color("#a55e57"),0.28)
	var style: int = seed%6
	var jaw: float = 0.04*float(seed%4)
	var jaw_lost: bool = f._lost("jaw")
	var nose: float = 0.04*float((seed/4)%4)
	var eye_y: float = -0.72+0.035*float((seed/11)%3)
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead",false))
	var coif: bool = String(f._it("helm").get("sprite","")) == "coif"
	# Seed styles retain their cropped/long/receding/bald/braided/wavy identities.
	if style in [1,4]:
		cv.begin()
		_female_round(cv,hc,[[-2.65,-2.45],[-1.42,-2.74],[-1.6,1.36],[-1.02,3.88],[-2.16,4.32],[-3.16,2.8],[-3.25,-0.03]],hair.darkened(0.13))
		if style == 4:
			cv.capsule(hc+Vector2(-2.72,-0.64),hc+Vector2(-3.92,2.95),0.52,hair)
			cv.capsule(hc+Vector2(-3.92,2.95),hc+Vector2(-3.58,4.67),0.43,hair)
		cv.end(FigurePainter.ol(hair),0.045)
		cv.capsule(hc+Vector2(-2.48,-0.05),hc+Vector2(-2.17,3.14),0.13,hair.lightened(0.22))
		cv.capsule(hc+Vector2(-2.97,0.34),hc+Vector2(-2.76,2.52),0.1,hair.lightened(0.14))
		if style == 4:
			for i in 5:
				var p: Vector2 = hc+Vector2(-3.01-0.17*float(i),0.1+0.67*float(i))
				cv.capsule(p+Vector2(-0.2,-0.12),p+Vector2(0.25,0.17),0.11,hair.lightened(0.23))
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-0.63,1.82),hc+Vector2(0.96,1.99),sc+Vector2(1.0,0.74),sc+Vector2(-0.95,0.54)]),shadow)
		cv.end(FigurePainter.ol(skin),0.025)
	# A rounded cheek and softly tapering jaw carry the head; the nose is inside this contour.
	cv.begin()
	if jaw_lost:
		_female_round(cv,hc,[[-2.23,-1.82],[-1.65,-2.84],[-0.08,-3.06],[1.5,-2.65],[2.12,-1.57],
			[2.22,-0.32],[2.15,0.73],[1.82,1.44],[0.33,1.43],[-0.81,1.18],[-1.88,0.37]],skin)
		_female_round(cv,hc,[[-2.13,-1.75],[-1.26,-2.5],[-1.25,-0.42],[-0.88,0.79],[-0.79,1.17],[-1.86,0.41]],shadow)
	else:
		_female_round(cv,hc,[[-2.23,-1.82],[-1.65,-2.84],[-0.08,-3.06],[1.5,-2.65],[2.12,-1.57],
			[2.22,-0.32],[2.15,0.73],[1.86,1.49],[1.35+jaw,2.16],[0.73,2.55],[0.16,2.57],
			[-0.49-jaw,2.31],[-1.15,1.76],[-1.87,0.46]],skin)
		_female_round(cv,hc,[[-2.13,-1.75],[-1.26,-2.5],[-1.25,-0.42],[-0.88,0.79],[-0.48,1.68],
			[0.25,2.46],[-0.44,2.24],[-1.12,1.73],[-1.87,0.44]],shadow)
	_female_round(cv,hc,[[-0.89,-2.45],[0.39,-2.82],[1.45,-2.36],[1.62,-1.45],[0.34,-1.38],[-0.97,-1.47]],light)
	# Softer cheekbone transitions preserve an adult face without hard triangular masks.
	_female_round(cv,hc,[[-0.61,-0.08],[0.24,-0.07],[0.94,0.18],[1.25,0.63],[0.64,0.98],[-0.45,0.82],[-0.88,0.42]],light)
	_female_round(cv,hc,[[0.15,1.02],[1.29,0.83],[1.56,1.03],[0.85,1.2],[0.25,1.24]],skin.darkened(0.055))
	if not jaw_lost:
		_female_round(cv,hc,[[0.02,1.94],[1.32,1.86],[1.05,2.29],[0.53,2.45],[0.06,2.37],[-0.21,2.16]],skin.lightened(0.08))
	if not f._lost("nose"):
		# Short, refined three-quarter bridge and round tip, without a projecting profile wedge.
		_female_round(cv,hc,[[1.03,-0.87],[1.35,-0.86],[1.44,-0.31],[1.83+nose,0.19],[1.77+nose,0.48],
			[1.26,0.57],[1.04,0.4],[1.18,0.05]],skin)
		_female_round(cv,hc,[[1.14,-0.73],[1.3,-0.61],[1.37,-0.2],[1.68+nose,0.21],[1.49,0.36],[1.28,0.22]],light)
		cv.ellipse(hc+Vector2(1.33,0.45),0.115,0.075,deep)
		cv.capsule(hc+Vector2(1.53,0.5),hc+Vector2(1.73+nose,0.42),0.07,shadow)
	cv.end(FigurePainter.ol(skin),0.04)
	if not coif and not f._lost("ear_r"):
		cv.begin()
		cv.ellipse(hc+Vector2(-1.8,-0.02),0.47,0.72,skin)
		cv.end(FigurePainter.ol(skin),0.025)
		cv.capsule(hc+Vector2(-1.87,-0.33),hc+Vector2(-1.7,0.19),0.11,shadow)
		cv.ellipse(hc+Vector2(-1.67,0.02),0.14,0.2,deep)
	var iris: Color = [Color("#705638"),Color("#506957"),Color("#5c7188"),Color("#806245")][(seed/7)%4]
	for eye_side in ["r","l"]:
		if f._lost("eye_"+eye_side):
			continue
		var near: bool = eye_side == "r"
		var ex: float = 0.04 if near else 1.6
		var ey: float = eye_y+(0.01 if near else -0.035)
		var ew: float = 0.77 if near else 0.43
		var eh: float = 0.39 if near else 0.32
		var brow: Color = hair.darkened(0.1).lerp(deep,0.4)
		cv.capsule(hc+Vector2(ex-ew,ey-0.64),hc+Vector2(ex-ew*0.02,ey-0.8),0.09,brow)
		cv.capsule(hc+Vector2(ex-ew*0.02,ey-0.8),hc+Vector2(ex+ew*0.83,ey-0.63),0.075,brow)
		if dead:
			cv.capsule(hc+Vector2(ex-ew*0.86,ey),hc+Vector2(ex,ey+0.12),0.11,deep)
			cv.capsule(hc+Vector2(ex,ey+0.12),hc+Vector2(ex+ew*0.84,ey-0.04),0.09,deep)
		else:
			_female_round(cv,hc,[[ex-ew,ey+0.03],[ex-ew*0.43,ey-eh*0.82],[ex+ew*0.29,ey-eh],
				[ex+ew,ey-0.03],[ex+ew*0.46,ey+eh*0.87],[ex-ew*0.32,ey+eh]],skin.lightened(0.76).lerp(Color("#f0e8d9"),0.29))
			var ix: float = ex+ew*0.23
			cv.ellipse(hc+Vector2(ix,ey+0.015),0.28 if near else 0.21,0.32 if near else 0.25,iris)
			cv.ellipse(hc+Vector2(ix+0.025,ey+0.02),0.125 if near else 0.09,0.25 if near else 0.19,Color("#26201e"))
			# Catchlight sits within the real iris. Natural upper lashes remain slender.
			cv.ellipse(hc+Vector2(ix-0.09,ey-0.1),0.105 if near else 0.075,0.105 if near else 0.075,Color("#fff5de"))
			cv.capsule(hc+Vector2(ex-ew,ey+0.02),hc+Vector2(ex-ew*0.35,ey-eh*0.83),0.095,deep)
			cv.capsule(hc+Vector2(ex-ew*0.35,ey-eh*0.83),hc+Vector2(ex+ew*0.3,ey-eh*0.91),0.085,deep)
			cv.capsule(hc+Vector2(ex+ew*0.3,ey-eh*0.91),hc+Vector2(ex+ew*0.92,ey-0.05),0.07,deep)
			cv.capsule(hc+Vector2(ex-ew*0.92,ey-0.02),hc+Vector2(ex-ew*1.13,ey-0.16),0.07,deep)
			cv.capsule(hc+Vector2(ex-ew*0.57,ey+eh*0.88),hc+Vector2(ex+ew*0.5,ey+eh*0.77),0.06,shadow)
	if age>=45:
		cv.capsule(hc+Vector2(-0.75,0.12),hc+Vector2(-0.35,0.27),0.055,shadow)
		cv.capsule(hc+Vector2(1.28,0.81),hc+Vector2(1.18,1.0),0.055,shadow)
	if not f._lost("mouth"):
		# Fuller, shaped natural lips and a short relaxed seam balance the shorter nose.
		_female_round(cv,hc,[[0.06,1.36],[0.45,1.17],[0.71,1.23],[0.94,1.14],[1.48,1.31],
			[1.18,1.47],[0.54,1.5]],lip)
		cv.capsule(hc+Vector2(0.2,1.44),hc+Vector2(0.79,1.43),0.065,deep)
		cv.capsule(hc+Vector2(0.79,1.43),hc+Vector2(1.37,1.36),0.06,deep)
		if not jaw_lost:
			_female_round(cv,hc,[[0.2,1.51],[1.36,1.45],[1.12,1.75],[0.66,1.85],[0.29,1.68]],lip.lerp(skin.lightened(0.08),0.3))
			cv.capsule(hc+Vector2(0.51,1.74),hc+Vector2(1.0,1.7),0.07,light)
	# Smooth sweeping hairlines frame the eye and cheek rather than cutting a zigzag fringe.
	if style!=3:
		cv.begin()
		if style==2:
			_female_round(cv,hc,[[-2.4,-1.91],[-2.03,-2.94],[-1.07,-3.25],[-0.71,-2.92],[-1.35,-2.09],[-1.51,-0.74],[-2.07,-0.18]],hair)
			_female_round(cv,hc,[[1.07,-2.92],[1.74,-2.73],[2.13,-2.07],[1.43,-2.33]],hair)
		else:
			_female_round(cv,hc,[[-2.43,-1.91],[-2.2,-2.99],[-1.05,-3.48],[0.47,-3.45],[1.74,-2.98],[2.18,-2.19],
				[1.55,-1.93],[0.63,-2.27],[-0.23,-2.13],[-0.99,-1.55],[-1.4,-0.68],[-1.64,0.16],[-2.1,0.2]],hair)
			if style==5:
				_female_round(cv,hc,[[-1.82,-2.89],[-1.11,-3.75],[0.21,-3.65],[0.8,-3.22],[-0.23,-2.95]],hair)
			if style==1:
				cv.capsule(hc+Vector2(-1.74,0.15),hc+Vector2(-1.38,1.83),0.27,hair)
		cv.end(FigurePainter.ol(hair),0.055)
		cv.capsule(hc+Vector2(-1.91,-2.56),hc+Vector2(-0.75,-2.98),0.14,hair.lightened(0.27))
		cv.capsule(hc+Vector2(-0.68,-3.0),hc+Vector2(0.59,-2.83),0.12,hair.lightened(0.23))
		cv.capsule(hc+Vector2(0.73,-2.78),hc+Vector2(1.52,-2.39),0.1,hair.lightened(0.18))
		cv.capsule(hc+Vector2(-1.72,-1.71),hc+Vector2(-1.88,-0.64),0.095,hair.lightened(0.17))
	# The real helmet remains above the new face. Female beard flags are still suppressed.
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)
static func _retained_female_head(f) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var seed: int = absi(int(f.spec.get("seed", 0)))
	var age: int = int(f.spec.get("age", 28))
	var skin: Color = f.skin
	var hair: Color = f.hair
	var shadow: Color = skin.darkened(0.18).lerp(Color("#6e493f"), 0.09)
	var deep: Color = skin.darkened(0.39).lerp(Color("#43312d"), 0.14)
	var light: Color = skin.lightened(0.18)
	# Lip tones remain a muted part of the skin ramp, without cosmetics.
	var lip: Color = skin.darkened(0.2).lerp(Color("#89524a"), 0.17)
	var style: int = seed % 6
	var jaw: float = 0.05 * float(seed % 4)
	var jaw_lost: bool = f._lost("jaw")
	var nose: float = 0.05 * float((seed / 4) % 4)
	var eye_y: float = -0.81 + 0.04 * float((seed / 11) % 3)
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead", false))
	var coif: bool = String(f._it("helm").get("sprite", "")) == "coif"
	# The existing seeded long and braided hairstyles still sit behind the skull.
	if style in [1,4]:
		cv.begin()
		_poly(cv,hc,[[-2.7,-2.6],[-1.5,-2.8],[-1.7,1.6],[-1.2,3.9],[-2.3,4.4],[-3.3,2.9],[-3.4,0.0]],hair.darkened(0.16))
		if style == 4:
			cv.capsule(hc+Vector2(-2.8,-0.7),hc+Vector2(-4.1,3.1),0.55,hair)
			cv.capsule(hc+Vector2(-4.1,3.1),hc+Vector2(-3.7,4.9),0.46,hair)
		cv.end(FigurePainter.ol(hair),0.06)
		cv.capsule(hc+Vector2(-2.6,0.0),hc+Vector2(-2.4,3.2),0.14,hair.lightened(0.21))
		if style == 4:
			for i in 5:
				var p: Vector2 = hc+Vector2(-3.1-0.18*float(i),0.15+0.7*float(i))
				cv.capsule(p+Vector2(-0.22,-0.14),p+Vector2(0.28,0.2),0.12,hair.lightened(0.23))
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-0.6,1.83),hc+Vector2(1.04,2.04),sc+Vector2(1.0,0.74),sc+Vector2(-0.95,0.54)]),shadow)
		cv.end(FigurePainter.ol(skin),0.04)
	# Adult cheekbone width transitions into a visibly narrower, rounded chin.
	cv.begin()
	if jaw_lost:
		_poly(cv,hc,[[-2.2,-1.91],[-1.58,-2.83],[0.06,-3.02],[1.6,-2.66],[2.21,-1.81],
			[2.23,-1.04],[2.02,-0.57],[2.21,0.03],[2.31,0.65],[2.02,1.22],
			[1.85,1.49],[0.4,1.45],[-0.63,1.17],[-1.88,0.41]],skin)
		_poly(cv,hc,[[-2.08,-1.75],[-1.11,-2.5],[-1.02,-0.4],[-0.63,0.9],
			[-0.63,1.17],[-1.88,0.42]],shadow)
	else:
		_poly(cv,hc,[[-2.2,-1.91],[-1.58,-2.83],[0.06,-3.02],[1.6,-2.66],[2.21,-1.81],
			[2.23,-1.04],[2.02,-0.57],[2.21,0.03],[2.31,0.65],[2.02,1.22],[1.76,1.86],
			[1.17+jaw,2.42],[0.61,2.71],[0.11,2.67],[-0.55-jaw,2.36],[-1.17,1.63],[-1.88,0.41]],skin)
		_poly(cv,hc,[[-2.08,-1.75],[-1.11,-2.5],[-1.02,-0.4],[-0.63,0.9],[-0.27,1.96],[0.27,2.57],
			[-0.52,2.35],[-1.18,1.57],[-1.88,0.42]],shadow)
	_poly(cv,hc,[[-0.82,-2.46],[0.44,-2.8],[1.58,-2.41],[1.77,-1.59],[0.52,-1.42],[-0.85,-1.55]],light)
	# The near cheek plane has a clear crest and soft falloff below the eye.
	_poly(cv,hc,[[-0.12,-0.04],[0.78,0.02],[1.58,0.27],[1.92,0.63],[1.51,0.88],[0.35,0.91],[-0.28,0.47]],light)
	_poly(cv,hc,[[0.13,0.98],[1.51,0.94],[1.64,1.19],[0.63,1.44],[0.17,1.28]],skin.darkened(0.09))
	if not jaw_lost:
		_poly(cv,hc,[[0.04,1.77],[1.61,1.72],[1.14,2.28],[0.61,2.54],[0.14,2.48],[-0.17,2.17]],skin.lightened(0.08))
	if not f._lost("nose"):
		_poly(cv,hc,[[1.77,-1.23],[2.1,-1.16],[2.31,-0.34],[2.74+nose,0.22],[2.69+nose,0.49],[2.0,0.56],[1.86,0.21]],skin)
		_poly(cv,hc,[[1.98,-1.01],[2.17,-0.31],[2.61+nose,0.21],[2.33,0.28],[2.06,0.05]],light)
		cv.capsule(hc+Vector2(2.27,0.47),hc+Vector2(2.6+nose,0.4),0.1,deep)
	cv.end(FigurePainter.ol(skin),0.055)
	if not coif and not f._lost("ear_r"):
		cv.begin()
		cv.ellipse(hc+Vector2(-1.69,-0.04),0.49,0.75,skin)
		cv.end(FigurePainter.ol(skin),0.035)
		cv.capsule(hc+Vector2(-1.78,-0.37),hc+Vector2(-1.59,0.21),0.12,shadow)
		cv.ellipse(hc+Vector2(-1.57,0.02),0.15,0.22,deep)
	var iris: Color = [Color("#574632"),Color("#45534b"),Color("#4e5966"),Color("#634e39")][(seed/7)%4]
	for eye_side in ["r","l"]:
		if f._lost("eye_"+eye_side):
			continue
		var near: bool = eye_side == "r"
		var ex: float = 0.79 if near else 2.01
		var ey: float = eye_y + (0.02 if near else -0.05)
		var ew: float = 0.69 if near else 0.28
		var brow: Color = hair.darkened(0.17).lerp(deep,0.44)
		# Natural arched brows and angular eyelids make almond eyes, not round enlarged eyes.
		cv.capsule(hc+Vector2(ex-ew,ey-0.5),hc+Vector2(ex+ew*0.1,ey-0.66),0.11,brow)
		cv.capsule(hc+Vector2(ex+ew*0.1,ey-0.66),hc+Vector2(ex+ew*0.87,ey-0.52),0.09,brow)
		if dead:
			cv.capsule(hc+Vector2(ex-ew*0.85,ey+0.02),hc+Vector2(ex,ey+0.13),0.12,deep)
			cv.capsule(hc+Vector2(ex,ey+0.13),hc+Vector2(ex+ew*0.86,ey-0.02),0.1,deep)
		else:
			_poly(cv,hc,[[ex-ew,ey+0.04],[ex-ew*0.26,ey-0.18],[ex+ew*0.4,ey-0.18],
				[ex+ew,ey-0.04],[ex+ew*0.43,ey+0.24],[ex-ew*0.29,ey+0.24]],skin.lightened(0.64).lerp(Color("#e5d9c2"),0.4))
			cv.ellipse(hc+Vector2(ex+ew*0.37,ey+0.04),0.22 if near else 0.13,0.21,iris)
			cv.ellipse(hc+Vector2(ex+ew*0.46,ey+0.02),0.09,0.17,Color("#201c1a"))
			cv.capsule(hc+Vector2(ex-ew,ey+0.01),hc+Vector2(ex-ew*0.16,ey-0.2),0.1,deep)
			cv.capsule(hc+Vector2(ex-ew*0.16,ey-0.2),hc+Vector2(ex+ew*0.86,ey-0.11),0.09,deep)
			cv.capsule(hc+Vector2(ex-ew*0.72,ey+0.21),hc+Vector2(ex+ew*0.57,ey+0.22),0.07,shadow)
	if age >= 45:
		cv.capsule(hc+Vector2(-0.2,0.32),hc+Vector2(0.29,0.47),0.075,shadow)
		cv.capsule(hc+Vector2(1.56,0.75),hc+Vector2(1.42,1.05),0.075,shadow)
	if not f._lost("mouth"):
		# Sculpted upper lip, relaxed mouth seam and lower lip use the natural skin palette.
		_poly(cv,hc,[[0.83,1.34],[1.22,1.21],[1.45,1.27],[1.63,1.2],[2.0,1.34],[1.75,1.47],[1.16,1.49]],lip)
		cv.capsule(hc+Vector2(0.98,1.46),hc+Vector2(1.87,1.41),0.075,deep)
		if not jaw_lost:
			_poly(cv,hc,[[1.05,1.52],[1.85,1.48],[1.66,1.69],[1.29,1.74]],skin.darkened(0.11).lerp(lip,0.25))
			cv.capsule(hc+Vector2(1.27,1.7),hc+Vector2(1.67,1.65),0.07,light)
	# Keep the six actual seeded hair structures, including cropped and bald women.
	if style != 3:
		cv.begin()
		if style == 2:
			_poly(cv,hc,[[-2.42,-2.13],[-1.54,-3.02],[-0.56,-3.15],[-0.71,-2.46],[-1.3,-1.98],[-1.46,-0.57],[-2.18,-0.11]],hair)
			_poly(cv,hc,[[0.98,-2.89],[1.63,-2.7],[2.0,-2.15],[1.27,-2.31]],hair)
		else:
			_poly(cv,hc,[[-2.43,-1.97],[-2.09,-2.98],[-1.02,-3.4],[0.5,-3.39],[1.63,-2.99],[2.12,-2.39],
				[1.72,-1.86],[1.16,-2.08],[0.68,-1.83],[0.22,-2.11],[-0.61,-1.61],[-1.08,-1.66],[-1.32,-0.48],[-1.98,-0.01]],hair)
			if style == 5:
				_poly(cv,hc,[[-1.64,-3.01],[-0.86,-3.69],[0.5,-3.5],[0.96,-3.11],[0.02,-2.76]],hair)
		cv.end(FigurePainter.ol(hair),0.075)
		cv.capsule(hc+Vector2(-1.76,-2.68),hc+Vector2(-0.48,-2.9),0.17,hair.lightened(0.28))
		cv.capsule(hc+Vector2(-0.28,-3.01),hc+Vector2(1.26,-2.61),0.11,hair.lightened(0.21))
		cv.capsule(hc+Vector2(-1.62,-1.84),hc+Vector2(-1.84,-0.6),0.11,hair.lightened(0.17))
	# No beard is drawn on this path, even if an older look seed carries a beard flag.
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _female_body_shape(f, skirt: float, spread: float) -> PackedVector2Array:
	var w: float = float(f.tw)*0.5
	var h: float = float(f.hipw)*0.5
	var l: float = float(f.torso_len)
	# Shoulder endpoints remain covered at their original locations. Cloth takes in at
	# the waist then releases over the hips, without changing any skeletal measurements.
	return PackedVector2Array([_tp(f,-w+0.75,0.07),_tp(f,-1.08,-0.12),_tp(f,1.03,-0.12),_tp(f,w-0.58,0.36),
		_tp(f,w-0.16,l*0.23),_tp(f,w*0.77,l*0.4),_tp(f,w*0.61,l*0.69),_tp(f,h*0.86,l*0.97),
		_tp(f,h+0.16+spread,l+skirt-0.4),_tp(f,h-0.23+spread,l+skirt),
		_tp(f,0.8,l+skirt-0.17),_tp(f,0.3,l+skirt-0.55),_tp(f,-0.4,l+skirt-0.08),
		_tp(f,-h-0.17-spread,l+skirt),_tp(f,-h-0.42-spread,l+skirt-0.44),
		_tp(f,-h*0.86,l*0.97),_tp(f,-w*0.62,l*0.69),_tp(f,-w*0.78,l*0.4),_tp(f,-w+0.06,l*0.23)])

static func _female_belt(f, y: float, leather: Color, buckle: Color) -> void:
	var cv: PixelCanvas = f.cv
	var w: float = float(f.tw)*0.64*0.5
	cv.begin()
	cv.poly(PackedVector2Array([_tp(f,-w-0.05,y-0.27),_tp(f,w+0.04,y-0.23),_tp(f,w,y+0.26),_tp(f,-w,y+0.32)]),leather)
	cv.ellipse(_tp(f,1.36,y+0.02),0.38,0.3,buckle)
	cv.ellipse(_tp(f,1.36,y+0.02),0.18,0.15,leather.darkened(0.35))
	cv.end(FigurePainter.ol(leather),0.03)






static func _male_beard(f, hc: Vector2, style: int) -> void:
	if _female(f) or not bool(f.spec.get("beard",false)) or f._lost("head") or f._lost("jaw"):
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var shade: Color = hair.darkened(0.16)
	var light: Color = hair.lightened(0.2)
	var ink: Color = FigurePainter.ol(hair)
	# Silhouettes remain within y4.8 of the original head anchor and need no new rig.
	if style == 6:
		if not f._lost("mouth"):
			_male_moustache(cv,hc,hair,true)
		return
	if style == 7:
		# Close stubble is a soft hair-coloured jaw shadow with short directional hairs.
		var skin: Color = f.skin
		cv.begin()
		_poly(cv,hc,[[-1.38,0.57],[-0.94,0.94],[-0.31,1.67],[0.78,1.92],[1.91,1.57],[2.29,1.08],
			[2.23,1.86],[1.59,2.55],[0.95,2.91],[-0.12,2.83],[-1.14,1.94]],hair.lerp(skin,0.63))
		cv.end(Color(0,0,0,0),0.0)
		for p in [Vector2(-1.04,1.47),Vector2(-0.62,2.01),Vector2(-0.11,2.36),Vector2(0.48,2.63),
			Vector2(1.08,2.5),Vector2(1.62,2.08),Vector2(1.94,1.75)]:
			cv.capsule(hc+p,hc+p+Vector2(0.04,0.18),0.045,hair.lerp(skin,0.42))
		if not f._lost("mouth"):
			cv.capsule(hc+Vector2(0.10,0.96),hc+Vector2(1.28,0.98),0.11,hair.lerp(skin,0.4))
		return
	cv.begin()
	match style:
		1: # Close trimmed: a neat jawline and short broad chin.
			_poly(cv,hc,[[-1.39,0.46],[-0.92,0.8],[-0.31,1.64],[0.72,1.83],[1.8,1.64],[2.32,1.01],
				[2.35,1.87],[1.81,2.57],[1.07,3.13],[0.17,3.13],[-0.89,2.33],[-1.45,1.37]],hair)
			_poly(cv,hc,[[-1.35,0.79],[-0.82,1.44],[-0.35,2.37],[0.21,3.08],[-0.82,2.31],[-1.43,1.38]],shade)
		2: # Round full: a generous curved lower lobe, with no rectangular bib.
			cv.ellipse(hc+Vector2(0.45,2.27),1.92,1.49,hair)
			_poly(cv,hc,[[-1.51,0.42],[-0.98,0.76],[-0.38,1.57],[0.79,1.83],[1.86,1.65],[2.37,1.0],
				[2.41,2.01],[1.98,3.13],[1.03,3.73],[-0.2,3.69],[-1.28,2.63],[-1.58,1.33]],hair)
			_poly(cv,hc,[[-1.51,0.77],[-0.84,1.54],[-0.57,2.75],[0.08,3.57],[-1.19,2.67],[-1.58,1.31]],shade)
		3: # Pointed: clean cheek lines draw into a long tapered central point.
			_poly(cv,hc,[[-1.39,0.43],[-0.94,0.78],[-0.38,1.62],[0.68,1.85],[1.85,1.67],[2.38,1.0],
				[2.34,2.01],[1.9,3.19],[1.01,4.57],[0.66,4.77],[-0.04,3.93],[-1.0,2.7],[-1.5,1.33]],hair)
			_poly(cv,hc,[[-1.45,0.96],[-0.78,1.68],[-0.29,3.04],[0.65,4.72],[-0.04,3.93],[-1.0,2.7]],shade)
		4: # Forked: two distinct lower points with a clear notch between them.
			_poly(cv,hc,[[-1.48,0.4],[-0.94,0.75],[-0.38,1.6],[0.75,1.85],[1.84,1.64],[2.37,1.0],
				[2.42,2.09],[1.85,3.55],[1.25,4.37],[0.89,4.25],[0.5,3.01],[0.16,4.29],
				[-0.32,4.44],[-0.78,3.44],[-1.5,1.47]],hair)
			_poly(cv,hc,[[-1.43,0.92],[-0.81,1.73],[-0.53,3.05],[-0.26,4.35],[-0.78,3.44],[-1.5,1.47]],shade)
		5: # Braided: cheeks join a compact chin and a single woven hair braid.
			_poly(cv,hc,[[-1.41,0.46],[-0.93,0.79],[-0.34,1.62],[0.74,1.83],[1.84,1.65],[2.36,1.01],
				[2.38,1.98],[1.67,2.88],[1.08,3.3],[0.31,3.34],[-0.72,2.63],[-1.49,1.34]],hair)
			cv.capsule(hc+Vector2(0.74,2.88),hc+Vector2(0.83,4.24),0.5,hair)
			_poly(cv,hc,[[0.34,4.3],[1.27,4.29],[1.13,4.6],[0.84,4.78],[0.45,4.58]],hair)
			_poly(cv,hc,[[-1.43,0.85],[-0.81,1.73],[-0.3,2.57],[0.35,3.22],[-0.72,2.63],[-1.49,1.34]],shade)
	cv.end(ink,0.035)
	# Broader highlights follow grooming direction rather than a checker or fake ornaments.
	match style:
		1:
			cv.capsule(hc+Vector2(-0.25,2.16),hc+Vector2(0.16,2.74),0.09,light)
			cv.capsule(hc+Vector2(1.53,2.0),hc+Vector2(1.1,2.76),0.1,light)
		2:
			cv.capsule(hc+Vector2(-0.55,2.0),hc+Vector2(-0.12,3.13),0.12,light)
			cv.capsule(hc+Vector2(0.42,2.21),hc+Vector2(0.51,3.45),0.13,light)
			cv.capsule(hc+Vector2(1.43,2.06),hc+Vector2(1.12,3.25),0.11,light)
		3:
			cv.capsule(hc+Vector2(1.51,2.05),hc+Vector2(0.94,4.12),0.11,light)
			cv.capsule(hc+Vector2(0.25,2.46),hc+Vector2(0.69,4.13),0.08,light)
		4:
			cv.capsule(hc+Vector2(-0.42,2.33),hc+Vector2(-0.15,3.92),0.1,light)
			cv.capsule(hc+Vector2(1.56,2.4),hc+Vector2(1.2,3.89),0.11,light)
		5:
			cv.capsule(hc+Vector2(-0.57,1.83),hc+Vector2(0.28,2.8),0.1,light)
			cv.capsule(hc+Vector2(1.64,1.92),hc+Vector2(1.11,2.92),0.1,light)
			for i in 4:
				var p: Vector2 = hc+Vector2(0.73+0.025*float(i),3.03+0.36*float(i))
				var turn: float = -1.0 if i%2==0 else 1.0
				cv.capsule(p+Vector2(-0.38*turn,-0.06),p+Vector2(0.39*turn,0.2),0.14,light)
				cv.capsule(p+Vector2(0.38*turn,0.03),p+Vector2(-0.38*turn,0.3),0.085,shade)
	if not f._lost("mouth"):
		_male_moustache(cv,hc,hair,false)

static func _male_moustache(cv: PixelCanvas, hc: Vector2, hair: Color, curled: bool) -> void:
	cv.begin()
	if curled:
		# Moustache-only keeps the whole jaw visible; its curved ends are real hair.
		_poly(cv,hc,[[-0.85,0.92],[-0.62,1.28],[-0.22,1.38],[0.18,1.05],[0.55,0.82],[0.88,0.80],
			[1.35,0.96],[1.68,1.25],[1.82,0.92],[1.68,0.58],[1.88,0.68],[2.02,0.96],
			[1.92,1.36],[1.62,1.52],[1.28,1.35],[0.88,1.06],[0.48,1.08],[0.12,1.38],
			[-0.32,1.58],[-0.75,1.38],[-0.95,1.12]],hair)
	else:
		_poly(cv,hc,[[-0.08,1.04],[0.38,0.82],[0.82,0.80],[1.32,0.92],[1.58,1.12],[1.38,1.24],
			[0.95,1.04],[0.45,1.05],[0.06,1.22]],hair)
	cv.end(FigurePainter.ol(hair),0.025)
	cv.capsule(hc+Vector2(0.18,0.95),hc+Vector2(0.62,0.88),0.08,hair.lightened(0.22))
	cv.capsule(hc+Vector2(0.85,0.88),hc+Vector2(1.26,0.98),0.07,hair.lightened(0.17))


static func _garment_shape(f, hem: float, kind: String, dwarf: bool) -> PackedVector2Array:
	# Item-aware garment layers share the existing joints with DwarfArt.
	if dwarf: return DwarfArt.worn_body(f,hem,kind)
	var w: float = float(f.tw)*0.5
	var h: float = float(f.hipw)*0.5
	var l: float = float(f.torso_len)
	var female: bool = _female(f)
	var padded: bool = kind == "gambeson"
	var rigid: bool = kind in ["scale","lamellar","scrap"]
	var shoulder: float = w + (0.23 if padded else 0.04)
	var chest: float = w*(0.96 if dwarf else 0.9)+(0.25 if padded else 0.0)
	var waist: float = w*(0.76 if dwarf else 0.72)
	if female: waist = w*(0.7 if dwarf else 0.62)
	if rigid: waist += 0.17
	if padded: waist += 0.15
	var skirt: float = h+0.25+float(f._spread())*0.3
	var split: float = 0.75 if kind in ["mail","dwarf_mail","lamellar","gambeson"] else 0.42
	return PackedVector2Array([_tp(f,-shoulder+0.45,0.15),_tp(f,-1.12,0.05),_tp(f,0.09,0.81),_tp(f,1.11,0.09),
		_tp(f,shoulder-0.42,0.22),_tp(f,chest,l*0.29),_tp(f,waist,l*0.7),_tp(f,h*0.98,l),
		_tp(f,skirt,l+hem-0.25),_tp(f,skirt-0.17,l+hem),_tp(f,0.55,l+hem-0.06),
		_tp(f,0.29,l+hem-split),_tp(f,-0.1,l+hem-split*0.75),_tp(f,-0.39,l+hem-0.01),
		_tp(f,-skirt+0.13,l+hem),_tp(f,-skirt,l+hem-0.28),_tp(f,-h*0.98,l),_tp(f,-waist,l*0.7),_tp(f,-chest,l*0.29)])

static func _garment_color(f, item: Dictionary, trousers: bool = false) -> Color:
	var c: Color = f._trouser_col() if trousers else f._cloth_col()
	var mat: String = String(item.get("mat","linen"))
	if mat == "leather":
		c = c.lerp(Color("#785239"),0.64)
	elif mat != "linen" and DB.materials.has(mat):
		c = c.lerp(Color(DB.materials[mat].get("color","#a49b82")),0.36)
	return c

static func _garment_belt(f, dwarf: bool, c: Color, buckle: Color, kind: String) -> void:
	var cv: PixelCanvas = f.cv
	var w: float = float(f.tw)*0.5
	var female: bool = _female(f)
	var half: float = w*(0.76 if dwarf else 0.72)
	if female: half = w*(0.7 if dwarf else 0.62)
	if kind in ["scale","lamellar","scrap"]: half += 0.17
	if kind == "gambeson": half += 0.15
	half = lerpf(half,float(f.hipw)*0.49,0.067)+0.04
	if dwarf: half = DwarfArt.worn_waist(f,kind)+0.04
	var y: float = float(f.torso_len)*0.72
	cv.begin()
	cv.poly(PackedVector2Array([_tp(f,-half,y-0.26),_tp(f,half,y-0.21),_tp(f,half,y+0.29),_tp(f,-half,y+0.36)]),c)
	cv.poly(PackedVector2Array([_tp(f,half*0.49,y-0.31),_tp(f,half*0.49+0.68,y-0.3),_tp(f,half*0.49+0.64,y+0.4),_tp(f,half*0.49,y+0.39)]),buckle)
	cv.poly(PackedVector2Array([_tp(f,half*0.49+0.17,y-0.13),_tp(f,half*0.49+0.51,y-0.13),_tp(f,half*0.49+0.48,y+0.21),_tp(f,half*0.49+0.17,y+0.21)]),c.darkened(0.3))
	cv.end(FigurePainter.ol(c),0.03)

static func worn_torso(f, dwarf: bool) -> void:
	var cv: PixelCanvas = f.cv
	var sc: Vector2 = f.j["sc"]
	var l: float = float(f.torso_len)
	var w: float = float(f.tw)*0.5
	if dwarf: w *= 0.72
	var cl: Dictionary = f._it("clothing")
	if not cl.is_empty():
		var padded: bool = String(cl.get("tid","")) == "gambeson"
		var kind: String = "gambeson" if padded else "tunic"
		var hem: float = float(f.leg_len)*(0.4 if padded else 0.3)
		if dwarf: hem = float(f.leg_len)*(0.23 if padded else 0.16)
		var c: Color = _garment_color(f,cl)
		var trim: Color = (f.sec as Color).darkened(0.1 if padded else 0.02)
		cv.begin()
		cv.poly(_garment_shape(f,hem,kind,dwarf),c,DwarfArt.worn_surface(f,sc,"cloth") if dwarf else _surface(f,sc,true))
		if padded:
			# Padded coat has a standing textile collar, overlap closure, broad quilted panels.
			cv.poly(PackedVector2Array([_tp(f,-1.05,-0.28),_tp(f,-0.68,0.79),_tp(f,0.08,1.05),_tp(f,0.93,0.53),_tp(f,1.07,-0.19),_tp(f,0.75,-0.24),_tp(f,0.09,0.52),_tp(f,-0.7,-0.24)]),c.lightened(0.1))
			cv.capsule(_tp(f,0.58,1.17),_tp(f,0.63,l+hem-0.77),0.21,c.darkened(0.22))
			for i in 6:
				var x: float = -w*0.73+float(i)*w*0.28
				cv.capsule(_tp(f,x,1.75),_tp(f,x*0.75,l*0.7),0.09,c.darkened(0.18))
				cv.capsule(_tp(f,x*0.75,l*0.79),_tp(f,x,l+hem-0.44),0.1,c.darkened(0.17))
			for y in [l*0.37,l*0.54]:
				cv.capsule(_tp(f,0.34,float(y)),_tp(f,0.91,float(y)),0.12,trim)
		else:
			# Light tunic: folded neck facing, shoulder seam, softer skirt with a walking slit.
			cv.poly(PackedVector2Array([_tp(f,-1.14,0.04),_tp(f,0.1,0.91),_tp(f,1.13,0.09),_tp(f,0.77,0.1),_tp(f,0.1,0.58),_tp(f,-0.8,0.07)]),trim)
			cv.capsule(_tp(f,0.1,0.88),_tp(f,0.14,1.88),0.12,c.darkened(0.3))
			cv.capsule(_tp(f,-w+0.72,0.5),_tp(f,-w*0.59,1.24),0.08,c.darkened(0.17))
			cv.capsule(_tp(f,-w*0.46,l*0.81),_tp(f,-w*0.57,l+hem-0.43),0.13,c.lightened(0.19))
			cv.capsule(_tp(f,w*0.42,l*0.83),_tp(f,w*0.61,l+hem-0.44),0.15,c.darkened(0.2))
		var trim_w: float = w
		if dwarf: trim_w = minf(w,(float(f.hipw)*0.38-0.3)/0.83)
		if dwarf:
			DwarfArt.worn_hem(f,hem,kind,trim,0.13)
		else:
			cv.capsule(_tp(f,-trim_w*0.83,l+hem-0.27),_tp(f,-0.45,l+hem-0.24),0.16,trim)
			cv.capsule(_tp(f,0.64,l+hem-0.29),_tp(f,trim_w*0.82,l+hem-0.28),0.16,trim)
		if int(cl.get("q",0))>=2:
			cv.capsule(_tp(f,-trim_w*0.79,l+hem-0.55),_tp(f,-0.49,l+hem-0.53),0.07,trim.lightened(0.14))
		cv.end(FigurePainter.ol(c),0.075 if padded else 0.05)
		_garment_belt(f,dwarf,FigurePainter.LEATHER,FigurePainter.metal("copper",int(cl.get("q",0)))["light"],kind)
	var armor: Dictionary = f._it("body")
	if armor.is_empty(): return
	var kind: String = String(armor.get("sprite",""))
	var dwarf_mail: bool = String(armor.get("tid","")) == "dwarf_mail"
	var shape_kind: String = "dwarf_mail" if dwarf_mail else kind
	var m: Dictionary = FigurePainter.metal(String(armor.get("mat","copper")),int(armor.get("q",0)))
	var hem: float = float(f.leg_len)*0.25
	match kind:
		"mail": hem = float(f.leg_len)*(0.59 if dwarf_mail else 0.46)
		"byrnie": hem = float(f.leg_len)*0.13
		"scale": hem = float(f.leg_len)*0.1
		"lamellar": hem = float(f.leg_len)*(0.5 if String(armor.get("tid","")) == "steppe_lamellar" else 0.39)
		"scrap": hem = float(f.leg_len)*0.16
	if dwarf:
		match kind:
			"mail": hem = float(f.leg_len)*(0.3 if dwarf_mail else 0.23)
			"byrnie": hem = float(f.leg_len)*0.08
			"scale": hem = float(f.leg_len)*0.06
			"lamellar": hem = float(f.leg_len)*(0.28 if String(armor.get("tid","")) == "steppe_lamellar" else 0.22)
			"scrap": hem = float(f.leg_len)*0.1
	cv.begin()
	cv.poly(_garment_shape(f,hem,shape_kind,dwarf),m["base"],DwarfArt.worn_surface(f,sc,kind,m) if dwarf else _surface(f,sc,false,kind,m))
	# Real armor constructions have distinct edges and panels, independent of palette.
	if kind in ["mail","byrnie"]:
		cv.capsule(_tp(f,-1.13,0.14),_tp(f,0.08,0.83),0.14,m["dark"])
		cv.capsule(_tp(f,0.08,0.83),_tp(f,1.07,0.16),0.14,m["light"])
		if dwarf_mail:
			cv.capsule(_tp(f,-w+0.64,0.58),_tp(f,-w*0.78,l*0.44),0.18,m["dark"])
			cv.capsule(_tp(f,w-0.6,0.58),_tp(f,w*0.78,l*0.44),0.15,m["light"])
	elif kind == "scale":
		# The vest terminates above the tunic skirt; overlapping scalloped scale rows curve around it.
		for i in 3:
			var y: float = 1.6+float(i)*l*0.26
			var half: float = w*(0.84-0.07*float(i))
			cv.capsule(_tp(f,-half,y),_tp(f,half,y-0.11),0.14,m["dark"])
		cv.capsule(_tp(f,-w+0.67,0.61),_tp(f,-w*0.64,l*0.68),0.2,m["dark"])
	elif kind == "lamellar":
		# Horizontal overlapping courses and an open lower coat keep lamellar visibly segmented.
		for i in 4:
			var y: float = 1.35+float(i)*(l+hem-1.8)/4.0
			var half: float = w*0.77 if y<l else float(f.hipw)*0.48
			if dwarf and y>=l: half = maxf(0.7,float(f.hipw)*0.38-0.38)
			cv.capsule(_tp(f,-half,y),_tp(f,half,y),0.15,m["dark"])
			cv.capsule(_tp(f,-half,y+0.23),_tp(f,half,y+0.23),0.085,f.sec)
	elif kind == "scrap":
		var seed: int = absi(int(f.spec.get("seed",0)))
		for i in 6:
			var row: int = int(i/2)
			var y: float = 0.8+float(row)*l*0.29
			var half: float = w*(0.88-0.085*float(row))
			var x: float = -half+0.08 if i%2==0 else 0.18
			var pw: float = half-0.21
			var ph: float = l*0.28
			var c: Color = (m["base"] as Color).lerp(m["light"] if (i+seed)%3==0 else m["dark"],0.32)
			cv.poly(PackedVector2Array([_tp(f,x,y+0.1),_tp(f,x+pw-0.23,y-0.08),_tp(f,x+pw,y+0.22),_tp(f,x+pw-0.12,y+ph),_tp(f,x+0.2,y+ph+0.07)]),c)
			cv.capsule(_tp(f,x+0.19,y+0.07),_tp(f,x+pw-0.27,y+0.02),0.1,m["light"])
			cv.ellipse(_tp(f,x+0.28,y+0.37),0.13,0.13,m["shine"])
	var edging: Color = m["trim"] if int(armor.get("q",0))>=1 else m["dark"]
	var edging_w: float = w
	if dwarf: edging_w = minf(w,(float(f.hipw)*0.38-0.3)/0.82)
	if dwarf:
		DwarfArt.worn_hem(f,hem,shape_kind,edging,0.12)
	else:
		cv.capsule(_tp(f,-edging_w*0.82,l+hem-0.3),_tp(f,-0.43,l+hem-0.25),0.15,edging)
		cv.capsule(_tp(f,0.6,l+hem-0.3),_tp(f,edging_w*0.82,l+hem-0.3),0.15,edging)
	cv.end(m["outline"],0.065)
	if kind in ["mail","byrnie","lamellar","scrap"] or (dwarf and kind == "scale"):
		_garment_belt(f,dwarf,FigurePainter.LEATHER,m["trim"],shape_kind)
	if int(armor.get("q",0))>=4:
		cv.ellipse(_tp(f,w*0.52,1.1),0.12,0.12,m["shine"])

static func _wardrobe_segment(cv: PixelCanvas, a: Vector2, b: Vector2, ra: float, rb: float, c: Color, pat: Callable = Callable()) -> void:
	var axis: Vector2 = (b-a).normalized()
	var n: Vector2 = Vector2(-axis.y,axis.x)
	var mid: Vector2 = a.lerp(b,0.42)
	cv.poly(PackedVector2Array([a-axis*ra*0.31,a-n*ra,mid-n*ra*0.99,b-n*rb,b+axis*rb*0.2,
		b+n*rb,mid+n*ra*0.94,a+n*ra]),c,pat)
	cv.capsule(a+n*ra*0.31,b+n*rb*0.2,maxf(0.1,rb*0.16),c.lightened(0.14))

static func worn_arm(f, side: String, dwarf: bool) -> void:
	if f._lost("arm_upper_"+side): return
	var cv: PixelCanvas = f.cv
	var sh: Vector2 = f.j["s"+side]
	var el: Vector2 = f.j["e"+side]
	var hd: Vector2 = f.j["h"+side]
	var r: float = float(f.arm_r)*(1.09 if dwarf else 1.0)
	if dwarf and _female(f): r *= 0.94
	var upper_axis: Vector2 = (el-sh).normalized()
	var un: Vector2 = Vector2(-upper_axis.y,upper_axis.x)
	var lower_lost: bool = f._lost("arm_lower_"+side)
	var hand_lost: bool = f._lost("hand_"+side)
	var cloth: Dictionary = f._it("clothing")
	if not cloth.is_empty():
		var padded: bool = String(cloth.get("tid","")) == "gambeson"
		var c: Color = _garment_color(f,cloth)
		if side=="l": c = c.darkened(0.11)
		var end: Vector2 = sh.lerp(el,1.0 if padded else 0.86)
		cv.begin()
		if dwarf:
			DwarfArt.worn_sleeve(cv,sh,end,r*(1.22 if padded else 1.2)/1.09,r*(0.96 if padded else 0.84)/1.09,c)
		else:
			_wardrobe_segment(cv,sh,end,r*(1.37 if padded else 1.18),r*(1.19 if padded else 0.96),c)
		var cuff_r: float = r*(0.86/1.09 if dwarf else 1.0)
		cv.capsule(end-un*cuff_r,end+un*cuff_r,0.19,c.darkened(0.25))
		if padded:
			for i in 3:
				var p: Vector2 = sh.lerp(end,0.25+float(i)*0.24)
				cv.capsule(p-un*r*0.83,p+un*r*0.8,0.09,c.darkened(0.17))
		else:
			var trim_r: float = r*(0.8/1.09 if dwarf else 1.0)
			cv.capsule(end-un*trim_r*0.91,end+un*trim_r*0.89,0.09,f.sec)
		cv.end(FigurePainter.ol(c),0.05)
	var body: Dictionary = f._it("body")
	var kind: String = String(body.get("sprite",""))
	if kind in ["mail","byrnie"]:
		var m: Dictionary = FigurePainter.metal(String(body.get("mat","copper")),int(body.get("q",0)))
		var fraction: float = 0.96 if String(body.get("tid",""))=="dwarf_mail" else 0.78
		if kind=="byrnie": fraction = 0.5
		var end: Vector2 = sh.lerp(el,fraction)
		cv.begin()
		if dwarf:
			DwarfArt.worn_sleeve(cv,sh,end,r*1.2/1.09,r*0.87/1.09,m["base"],_surface(f,sh,false,"mail",m))
		else:
			_wardrobe_segment(cv,sh,end,r*1.24,r*1.04,m["base"],_surface(f,sh,false,"mail",m))
		var cuff_r: float = r*(0.84/1.09 if dwarf else 1.01)
		cv.capsule(end-un*cuff_r,end+un*cuff_r,0.15,m["dark"])
		cv.end(m["outline"],0.06)
	if kind in ["lamellar","scrap"]:
		var m: Dictionary = FigurePainter.metal(String(body.get("mat","copper")),int(body.get("q",0)))
		var a: Vector2 = sh-upper_axis*0.2
		var b: Vector2 = sh.lerp(el,0.36 if kind=="lamellar" else 0.28)
		cv.begin()
		if dwarf:
			DwarfArt.worn_sleeve(cv,a,b,r*1.21/1.09,r*1.01/1.09,m["base"])
		else:
			_wardrobe_segment(cv,a,b,r*1.36,r*1.21,m["base"])
		var edge_r: float = r*(0.94/1.09 if dwarf else 1.0)
		cv.capsule(b-un*edge_r*1.07,b+un*edge_r*1.1,0.16,m["light"])
		if kind=="lamellar":
			var p: Vector2 = a.lerp(b,0.52)
			cv.capsule(p-un*edge_r*1.19,p+un*edge_r*1.2,0.1,m["dark"])
			cv.ellipse(p+un*r*0.72,0.11,0.11,f.sec)
		else:
			cv.ellipse(a.lerp(b,0.6)-un*r*0.75,0.14,0.14,m["shine"])
		cv.end(m["outline"],0.05)
	if lower_lost: return
	var hands: Dictionary = f._it("hands")
	if hands.is_empty(): return
	var m: Dictionary = FigurePainter.metal(String(hands.get("mat","copper")),int(hands.get("q",0)))
	var tid: String = String(hands.get("tid",""))
	var axis: Vector2 = (hd-el).normalized()
	var n: Vector2 = Vector2(-axis.y,axis.x)
	cv.begin()
	if tid=="arm_rings":
		for t in [0.43,0.74]:
			var p: Vector2 = el.lerp(hd,float(t))
			cv.capsule(p-n*r*0.92,p+n*r*0.94,0.25,m["base"])
			cv.capsule(p-n*r*0.78-axis*0.08,p+n*r*0.57-axis*0.08,0.09,m["light"])
	else:
		var gauntlet: bool = tid.contains("gauntlet")
		var crude: bool = tid=="crude_bracers"
		var a: Vector2 = el.lerp(hd,0.35 if crude else 0.17)
		var b: Vector2 = el.lerp(hd,0.95 if gauntlet else 0.84)
		_wardrobe_segment(cv,a,b,r*(1.1 if gauntlet else 1.01),r*(0.87 if gauntlet else 0.74),m["base"])
		cv.capsule(a+n*r*0.31,b+n*r*0.19,0.16,m["light"])
		cv.capsule(a-n*r*0.91,a+n*r*0.9,0.16,m["dark"])
		if int(hands.get("q",0))>=2:
			cv.capsule(a-n*r*0.89-axis*0.07,a+n*r*0.86-axis*0.07,0.085,m["trim"])
		if gauntlet and not hand_lost:
			cv.ellipse(hd,r*0.94,r*0.99,m["base"])
			cv.ellipse(hd+n*0.49-axis*0.23,0.38,0.39,m["base"])
			cv.capsule(hd-n*r*0.56-axis*0.28,hd+n*r*0.55-axis*0.28,0.13,m["light"])
	cv.end(m["outline"],0.05)

static func worn_pants(f, side: String, dwarf: bool) -> void:
	if f._lost("leg_upper_"+side): return
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p"+side]
	var kn: Vector2 = f.j["k"+side]
	var ft: Vector2 = f.j["f"+side]
	var r: float = float(f.leg_r)
	var c: Color = _garment_color(f,f._it("legs_under"),true)
	if side=="l": c = c.darkened(0.1 if dwarf else 0.12)
	var d: Vector2 = (kn-hp).normalized()
	var n: Vector2 = Vector2(-d.y,d.x)
	var lower_lost: bool = f._lost("leg_lower_"+side)
	cv.begin()
	_wardrobe_segment(cv,hp,kn,r*(1.3 if dwarf else 1.21),r*(0.92 if dwarf else 0.79),c)
	cv.capsule(hp+n*r*0.7,kn+n*r*0.62,0.08,c.darkened(0.25))
	if not lower_lost:
		var calf: Vector2 = kn.lerp(ft,0.41)
		_wardrobe_segment(cv,kn,calf,r*(0.92 if dwarf else 0.8),r*(1.05 if dwarf else 0.9),c)
		_wardrobe_segment(cv,calf,ft,r*(1.05 if dwarf else 0.9),r*(0.62 if dwarf else 0.53),c)
		var ld: Vector2 = (ft-kn).normalized()
		var ln: Vector2 = Vector2(-ld.y,ld.x)
		var cuff: Vector2 = kn.lerp(ft,0.94)
		cv.capsule(cuff-ln*r*0.71,cuff+ln*r*0.71,0.15,c.darkened(0.26))
		cv.capsule(kn+ln*r*0.51,ft+ln*r*0.39,0.075,c.lightened(0.14))
	cv.end(FigurePainter.ol(c),0.06)

static func worn_greaves(f, side: String, dwarf: bool) -> void:
	var greaves: Dictionary = f._it("legs")
	if greaves.is_empty() or f._lost("leg_upper_"+side) or f._lost("leg_lower_"+side): return
	var cv: PixelCanvas = f.cv
	var kn: Vector2 = f.j["k"+side]
	var ft: Vector2 = f.j["f"+side]
	var axis: Vector2 = (ft-kn).normalized()
	var n: Vector2 = Vector2(-axis.y,axis.x)
	var r: float = float(f.leg_r)*(1.06 if dwarf else 0.89)
	var m: Dictionary = FigurePainter.metal(String(greaves.get("mat","copper")),int(greaves.get("q",0)))
	var a: Vector2 = kn.lerp(ft,0.07)
	var b: Vector2 = kn.lerp(ft,0.93)
	cv.begin()
	_wardrobe_segment(cv,a,a.lerp(b,0.4),r*0.9,r,m["base"])
	_wardrobe_segment(cv,a.lerp(b,0.4),b,r,r*0.58,m["base"])
	if String(greaves.get("tid","")) == "splint_greaves":
		for t in [-0.5,0.0,0.5]:
			cv.capsule(a+n*r*float(t),b+n*r*float(t)*0.58,0.13,m["light"])
	else:
		cv.capsule(a+n*r*0.25,b+n*r*0.18,0.2,m["light"])
		cv.ellipse(a-axis*0.15,r*0.88,r*0.52,m["base"])
	cv.capsule(a-n*r*0.83,a+n*r*0.81,0.14,m["dark"])
	if int(greaves.get("q",0))>=2:
		cv.capsule(a-n*r*0.79-axis*0.09,a+n*r*0.78-axis*0.09,0.08,m["trim"])
	cv.end(m["outline"],0.05)

static func worn_shoe(f, side: String, dwarf: bool) -> void:
	var item: Dictionary = f._it("feet")
	if item.is_empty() or f._lost("leg_upper_"+side) or f._lost("leg_lower_"+side) or f._lost("foot_"+side): return
	var cv: PixelCanvas = f.cv
	var ft: Vector2 = f.j["f"+side]
	var tid: String = String(item.get("tid",""))
	var mat: String = String(item.get("mat","leather"))
	var c: Color = Color(DB.materials.get(mat,{}).get("color","#6b4a2b"))
	if side=="l": c = c.darkened(0.1)
	var width: float = 1.16 if dwarf else 1.0
	var toe: float = 2.39 if dwarf else 2.04
	cv.begin()
	_poly(cv,ft,[[-width,-0.74],[0.74,-0.7],[1.02,-0.09],[toe-0.16,0.26],[toe+0.12,0.79],
		[toe,1.27],[0.08,1.36],[-width-0.16,1.21],[-width-0.23,0.51]],c)
	if tid.contains("boot"):
		cv.capsule(ft+Vector2(-0.19,-1.78),ft+Vector2(-0.04,-0.2),float(f.leg_r)*0.66,c)
		cv.capsule(ft+Vector2(-0.75,-1.71),ft+Vector2(0.6,-1.71),0.19,c.lightened(0.08))
	cv.capsule(ft+Vector2(-width,1.23),ft+Vector2(toe-0.04,1.27),0.18,c.darkened(0.42))
	cv.capsule(ft+Vector2(0.06,-0.41),ft+Vector2(1.38,0.31),0.13,c.lightened(0.23))
	cv.capsule(ft+Vector2(0.62,-0.08),ft+Vector2(0.2,0.31),0.11,c.darkened(0.26))
	if int(item.get("q",0))>=2:
		cv.capsule(ft+Vector2(-0.64,0.94),ft+Vector2(1.49,1.06),0.06,c.lightened(0.29))
	cv.end(FigurePainter.ol(c),0.05)

static func worn_chest(f, dwarf: bool) -> void:
	# Only the neck-opening underlay is needed beneath fitted garments. The original
	# whole bare torso still draws unchanged when no torso garment is equipped.
	var cv: PixelCanvas = f.cv
	var skin: Color = f.skin
	var w: float = 1.1 if dwarf else 1.05
	cv.begin()
	cv.poly(PackedVector2Array([_tp(f,-w,0.03),_tp(f,w,0.04),_tp(f,0.09,0.96)]),skin)
	cv.end(FigurePainter.ol(skin),0.04)
