class_name GoblinArt
extends RefCounted
## Goblin surfaces use the original FigurePainter rig and the supplied look palette.
## Equipped items retain their material and quality; wounds are FigurePainter's final pass.

static var _force_legacy_v064: bool = false

static func _poly(cv: PixelCanvas, origin: Vector2, points: Array, color: Color) -> void:
	var vertices: PackedVector2Array = PackedVector2Array()
	for point in points:
		vertices.append(origin + Vector2(float(point[0]), float(point[1])))
	cv.poly(vertices, color)

static func head(f) -> void:
	if f._lost("head"):
		return
	if _force_legacy_v064:
		_legacy_head(f)
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = absi(int(f.spec.get("seed", 0)))
	var female: bool = _female(f)
	var fvar: int = FigurePainter.female_variant(f.spec) if female else 0
	var style: int = seed % 5
	var nose_length: float = (0.06 if female else 0.13) * float((seed / 5) % 3)
	var ear_lift: float = (0.10 if female else 0.17) * float((seed / 7) % 3)
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead", false))
	var coif: bool = String(f._it("helm").get("sprite", "")) == "coif"
	var helm_open: bool = f._it("helm").is_empty() or String(f._it("helm").get("sprite", "")) in ["crown", "circlet"]
	var jaw_lost: bool = f._lost("jaw")

	var sh := cv.shaded()
	var c_skin: int = sh.add_color(skin, 0.14, 1.08)
	var c_skin_d: int = c_skin
	var c_skin_l: int = c_skin
	var c_ear_in: int = c_skin
	var c_hair: int = sh.add_color(hair, 0.18, 1.12, hair.lightened(0.35))
	var c_hair_d: int = c_hair
	var c_hair_l: int = c_hair

	# Female back hair behind neck & ears
	if female and not coif:
		sh.capsule(hc + Vector2(-1.65, -0.85), hc + Vector2(-2.45, 2.85 if style in [0, 4] else 4.15), 1.05, 0.72, c_hair_d, -1.8, 0.95)
		if style in [1, 2, 3]:
			sh.capsule(hc + Vector2(-2.35, -0.45), hc + Vector2(-3.15, 3.85), 0.85, 0.52, c_hair, -1.4, 0.95)

	# Signature huge sweeping bat-like pointed goblin ears (ear_l far, ear_r near)
	if not coif:
		if not f._lost("ear_l"):
			var el_pts := PackedVector2Array([
				hc + Vector2(1.25, -1.65), hc + Vector2(4.45, -2.95 - ear_lift),
				hc + Vector2(3.55, -1.15), hc + Vector2(2.20, 0.25), hc + Vector2(1.25, -0.25)
			])
			sh.poly(el_pts, c_skin_d, -0.8, 1.4)
		if not f._lost("ear_r"):
			var er_pts := PackedVector2Array([
				hc + Vector2(-1.55, -1.35), hc + Vector2(-2.95, -1.68),
				hc + Vector2(-5.95, -2.65 - ear_lift), hc + Vector2(-4.45, -0.68),
				hc + Vector2(-2.60, 0.65), hc + Vector2(-1.65, 0.10)
			])
			sh.poly(er_pts, c_skin, 1.8, 1.6)
			sh.capsule(hc + Vector2(-1.85, -1.25), hc + Vector2(-5.45, -2.35 - ear_lift), 0.36, 0.14, c_skin_l, 2.2, 0.9)
			sh.capsule(hc + Vector2(-2.05, -0.65), hc + Vector2(-4.45, -1.45 - ear_lift * 0.7), 0.38, 0.16, c_ear_in, 2.1, 0.7)

	# Angular wedge cranium & small pointed goblin jaw
	var chin_y: float = (2.25 if female else 2.52) if not jaw_lost else 1.15
	var skull_pts := PackedVector2Array([
		hc + Vector2(-1.98, -1.82), hc + Vector2(-1.38, -2.75), hc + Vector2(-0.05, -2.98),
		hc + Vector2(1.38, -2.62), hc + Vector2(2.02, -1.88), hc + Vector2(2.08, -0.85),
		hc + Vector2(2.15, 0.45),
		hc + Vector2(1.68 if not jaw_lost else 1.55, 1.55 if not jaw_lost else 0.95),
		hc + Vector2(0.68, chin_y),
		hc + Vector2(-0.35, (chin_y - 0.25) if not jaw_lost else 0.95),
		hc + Vector2(-1.68, 0.32), hc + Vector2(-2.12, -0.75)
	])
	sh.poly(skull_pts, c_skin, 0.0, 1.95)
	sh.ellipsoid(hc + Vector2(-0.05, -1.05), 1.98, 1.85, c_skin, 0.3, 1.1)
	if not jaw_lost:
		sh.capsule(hc + Vector2(-0.35, 1.15), hc + Vector2(0.75, chin_y - 0.32), 0.95 if not female else 0.85, 0.62 if not female else 0.55, c_skin, 0.5, 0.95)
	sh.ellipsoid(hc + Vector2(0.75, 0.15), 0.95, 0.68, c_skin_l, 1.0, 0.85)

	# Long down-curving hooked goblin nose
	if not f._lost("nose"):
		var n_reach: float = (2.85 if female else 3.75) + nose_length
		var n_pts := PackedVector2Array([
			hc + Vector2(1.35, -1.45), hc + Vector2(1.95, -1.42),
			hc + Vector2(n_reach - 0.25, -0.02), hc + Vector2(n_reach + 0.15, 0.55),
			hc + Vector2(n_reach - 0.18, 0.92), hc + Vector2(2.35, 0.45), hc + Vector2(1.45, -0.05)
		])
		sh.poly(n_pts, c_skin_l, 2.1, 1.6)
		sh.capsule(hc + Vector2(1.65, -1.15), hc + Vector2(n_reach, 0.52), 0.38, 0.28, c_skin_l, 2.5, 0.95)

	# Goblin hair (female styles 0..4, male jagged top-tuft when seed % 3 == 1)
	if not coif and helm_open:
		if female:
			sh.ellipsoid(hc + Vector2(-0.25, -2.25), 1.95, 1.08, c_hair, 1.6, 1.0)
			sh.capsule(hc + Vector2(-1.75, -1.65), hc + Vector2(1.55, -2.25), 0.68, 0.52, c_hair_l, 2.1, 0.95)
		elif seed % 3 == 1:
			sh.capsule(hc + Vector2(-1.35, -2.55), hc + Vector2(-0.95, -3.95), 0.58, 0.28, c_hair, 1.9, 0.95)
			sh.capsule(hc + Vector2(-0.45, -2.65), hc + Vector2(-0.15, -4.15), 0.62, 0.30, c_hair_l, 2.1, 1.0)
			sh.capsule(hc + Vector2(0.35, -2.55), hc + Vector2(0.85, -3.75), 0.55, 0.26, c_hair, 2.0, 0.95)

	sh.composite(FigurePainter.ol(skin), true)

	# Oblique amber slit eyes, arched brows & sharp grin
	var deep: Color = skin.darkened(0.55).lerp(Color("#27301b"), 0.18)
	var brow: Color = hair.darkened(0.20).lerp(deep, 0.50)
	if female:
		if fvar == 0:
			_retained_female_eye(f, hc + Vector2(0.48, -0.85), 0.79, skin, deep, brow, dead, "eye_r")
			_retained_female_eye(f, hc + Vector2(1.78, -1.01), 0.33, skin, deep, brow, dead, "eye_l")
		else:
			_female_eye(f, hc + Vector2(-0.18, -0.88), 0.92, skin, deep, brow, dead, "eye_r")
			_female_eye(f, hc + Vector2(1.43, -1.00), 0.38, skin, deep, brow, dead, "eye_l")
	else:
		_eye(f, hc + Vector2(0.65, -0.82), 0.82, skin, deep, dead, "eye_r")
		_eye(f, hc + Vector2(1.91, -1.00), 0.38, skin, deep, dead, "eye_l")
		cv.capsule(hc + Vector2(-0.16, -1.48), hc + Vector2(1.27, -1.22), 0.16, brow)
		cv.capsule(hc + Vector2(1.68, -1.48), hc + Vector2(2.20, -1.62), 0.13, brow)

	if not f._lost("mouth") and not jaw_lost:
		var lip_c: Color = skin.darkened(0.22).lerp(Color("#9e5868"), 0.32) if female else deep
		cv.capsule(hc + Vector2(0.55, 1.32), hc + Vector2(1.85, 1.18), 0.13, lip_c)

	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5, -float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _legacy_head(f) -> void:
	if _female(f):
		_female_head(f)
		return
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = absi(int(f.spec.get("seed", 0)))
	var shadow: Color = skin.darkened(0.25)
	var deep: Color = skin.darkened(0.57).lerp(Color("#27301b"), 0.18)
	var light: Color = skin.lightened(0.21)
	var nose_length: float = 0.13 * float((seed / 5) % 3)
	var ear_lift: float = 0.17 * float((seed / 7) % 3)
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead", false))
	var coif: bool = String(f._it("helm").get("sprite", "")) == "coif"
	# A thin, forward neck meets the unchanged collar and head centers.
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc + Vector2(-0.8,1.4),hc + Vector2(1.0,1.9),
			sc + Vector2(1.25,0.6),sc + Vector2(-1.0,0.5)]),shadow)
		cv.capsule(hc + Vector2(0.1,2.0),sc + Vector2(0.7,0.45),0.23,skin)
		cv.end(FigurePainter.ol(skin),0.06)
	# Both ears are wide at the roots, then sweep to sharp, thin tips.
	if not coif:
		cv.begin()
		if not f._lost("ear_l"):
			_poly(cv,hc,[[1.25,-1.7],[4.65,-3.0-ear_lift],[3.75,-1.2],[2.3,0.35],[1.25,-0.2]],shadow)
		if not f._lost("ear_r"):
			_poly(cv,hc,[[-1.6,-1.35],[-3.0,-1.7],[-6.15,-2.65-ear_lift],[-4.6,-0.65],[-2.7,0.75],[-1.7,0.15]],skin)
		cv.end(FigurePainter.ol(skin),0.04)
		if not f._lost("ear_r"):
			_poly(cv,hc,[[-2.0,-0.95],[-5.4,-2.11-ear_lift],[-3.4,-0.75],[-2.65,0.27]],shadow)
			cv.capsule(hc + Vector2(-2.65,-1.4),hc + Vector2(-5.28,-2.12-ear_lift),0.12,light)
			cv.capsule(hc + Vector2(-2.25,-0.72),hc + Vector2(-2.55,0.1),0.17,deep)
		if not f._lost("ear_l"):
			_poly(cv,hc,[[2.1,-1.25],[4.0,-2.5-ear_lift],[3.15,-0.95],[2.25,-0.12]],skin.darkened(0.39))
	# High narrow cranium, hollow temples, small angled jaw: no human box-head.
	cv.begin()
	_poly(cv,hc,[[-2.0,-1.85],[-1.4,-2.68],[-0.05,-2.94],[1.45,-2.6],[2.08,-1.9],
		[2.15,-0.9],[1.94,-0.15],[2.28,0.57],[1.8,1.2],[0.3,1.58],[-0.9,1.16],[-1.8,0.22],[-2.2,-0.8]],skin)
	_poly(cv,hc,[[-2.0,-1.85],[-1.4,-2.68],[-1.05,-1.35],[-1.25,0.14],[-0.35,1.18],
		[-0.9,1.16],[-1.8,0.22],[-2.2,-0.8]],shadow)
	_poly(cv,hc,[[-1.05,-2.53],[0.0,-2.78],[1.4,-2.45],[1.68,-1.9],[0.55,-1.48],[-0.8,-1.8]],light)
	_poly(cv,hc,[[-0.48,-0.1],[0.62,0.25],[1.52,0.04],[1.75,0.61],[0.22,1.0],[-0.6,0.54]],light)
	_poly(cv,hc,[[-1.18,-0.17],[-0.42,0.25],[-0.67,0.75],[-1.25,0.43]],skin.darkened(0.34))
	if not f._lost("jaw"):
		_poly(cv,hc,[[-1.0,0.88],[0.23,1.12],[2.12,0.89],[1.77,1.8],[0.8,2.58],[-0.22,2.31],[-1.15,1.56]],skin)
		_poly(cv,hc,[[-1.0,0.88],[-0.35,1.15],[-0.16,1.85],[0.8,2.58],[-0.22,2.31],[-1.15,1.56]],shadow)
		_poly(cv,hc,[[0.55,1.72],[1.67,1.51],[1.45,2.05],[0.87,2.29],[0.35,2.08]],skin.lightened(0.11))
	# A long down-curving bridge narrows to a hooked tip above the tiny mouth.
	if not f._lost("nose"):
		_poly(cv,hc,[[1.43,-1.55],[2.05,-1.55],[2.38,-0.89],[3.63+nose_length,-0.03],
			[4.05+nose_length,0.61],[3.7+nose_length,1.0],[2.97,0.9],[2.46,0.44],[1.55,0.04]],skin)
		_poly(cv,hc,[[1.75,-1.35],[2.03,-1.28],[2.26,-0.69],[3.45+nose_length,0.02],
			[3.7+nose_length,0.37],[3.05,0.31],[2.35,-0.02],[1.82,-0.22]],light)
		_poly(cv,hc,[[2.5,0.43],[3.38,0.58],[4.02+nose_length,0.61],[3.7+nose_length,1.0],[2.97,0.9]],shadow)
	cv.end(FigurePainter.ol(skin),0.06)
	# Narrow amber slits and oblique lids give a watchful expression, with closed dead eyes.
	_eye(f,hc + Vector2(0.65,-0.82),0.82,skin,deep,dead,"eye_r")
	_eye(f,hc + Vector2(1.91,-1.0),0.38,skin,deep,dead,"eye_l")
	cv.capsule(hc + Vector2(-0.16,-1.52),hc + Vector2(1.27,-1.24),0.19,skin.darkened(0.36))
	cv.capsule(hc + Vector2(1.68,-1.5),hc + Vector2(2.23,-1.65),0.15,shadow)
	if not f._lost("nose"):
		cv.capsule(hc + Vector2(3.0,0.7),hc + Vector2(3.45+nose_length,0.76),0.13,deep)
	if not f._lost("mouth") and not f._lost("jaw"):
		cv.capsule(hc + Vector2(0.73,1.35),hc + Vector2(2.1,1.15),0.14,deep)
		cv.capsule(hc + Vector2(0.89,1.64),hc + Vector2(1.64,1.51),0.12,light)
	# The original seeded bald/tuft choice and the real hair palette remain visible.
	if seed % 3 == 1 and f._it("helm").is_empty():
		cv.begin()
		_poly(cv,hc,[[-1.75,-2.4],[-2.15,-3.38],[-1.72,-3.05],[-1.2,-4.2],[-0.66,-3.64],
			[-0.21,-4.35],[0.22,-3.6],[1.01,-3.95],[0.9,-3.16],[1.51,-2.69],[0.5,-2.7],[-0.35,-2.5]],hair)
		_poly(cv,hc,[[-1.35,-3.14],[-1.16,-3.76],[-0.83,-3.35],[-0.24,-3.77],[-0.02,-3.11],[0.54,-3.35],[0.45,-2.9],[-0.5,-2.78]],hair.lightened(0.24))
		cv.end(FigurePainter.ol(hair),0.06)
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _eye(f, center: Vector2, width: float, skin: Color, deep: Color, dead: bool, part: String) -> void:
	if f._lost(part):
		return
	var cv: PixelCanvas = f.cv
	_poly(cv,center,[[-width,-0.15],[width,-0.32],[width*0.84,0.26],[-width*0.68,0.2]],deep)
	if dead:
		cv.capsule(center + Vector2(-width*0.7,0.0),center + Vector2(width*0.8,-0.08),0.14,skin.darkened(0.3))
		return
	_poly(cv,center,[[-width*0.76,0.0],[width*0.72,-0.12],[width*0.68,0.11],[-width*0.43,0.14]],Color("#e5cf4e"))
	cv.ellipse(center + Vector2(width*0.35,0.0),0.12,0.17,deep)
	cv.capsule(center + Vector2(-width,-0.17),center + Vector2(width*0.8,-0.26),0.12,deep)

static func _tp(f, x: float, y: float) -> Vector2:
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var length: float = float(f.torso_len)
	return sc.lerp(hip,clampf(y / length,0.0,1.0)) + Vector2(x,maxf(y-length,0.0))

static func _body(f, skirt: float) -> PackedVector2Array:
	var w: float = float(f.tw)*0.5
	var h: float = float(f.hipw)*0.38
	var length: float = float(f.torso_len)
	var hem: float = h + (0.42 if skirt > 0.0 else 0.0)
	return PackedVector2Array([_tp(f,-w+0.35,0.45),_tp(f,-1.05,-0.1),_tp(f,1.03,0.15),_tp(f,w-0.35,0.6),
		_tp(f,w-0.7,length*0.38),_tp(f,h-0.27,length*0.83),_tp(f,hem,length+skirt),
		_tp(f,0.12,length+skirt+0.15),_tp(f,-hem,length+skirt-0.2),_tp(f,-h+0.2,length*0.75),_tp(f,-w+0.5,length*0.37)])

static func torso(f) -> bool:
	if _force_legacy_v064:
		return _legacy_torso(f)
	var cv: PixelCanvas = f.cv
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var female: bool = _female(f)
	var mounted: bool = f.pose == "mounted"
	var w: float = float(f.tw) * 0.5
	var h: float = float(f.hipw) * (0.42 if female else 0.38)
	var clothing: Dictionary = f._it("clothing")
	var body: Dictionary = f._it("body")
	var has_cloth: bool = not clothing.is_empty()
	var has_armor: bool = not body.is_empty()

	var sh := cv.shaded()
	var c_skin: int = sh.add_color(f.skin, 0.14, 1.08)
	var c_leath: int = sh.add_color(FigurePainter.LEATHER, 0.20, 1.12)
	var c_brass: int = sh.add_color(FigurePainter.metal("copper", 1)["light"], 0.34, 1.18, FigurePainter.metal("copper", 1)["shine"])

	if not f._lost("neck"):
		sh.capsule(f.j["hc"] + Vector2(0.05, 1.25), sc + Vector2(0.10, 0.45), 0.52 if female else 0.58, 0.62 if female else 0.68, c_skin, -0.8, 0.95)

	# Wiry lean goblin ribcage & waist
	var bare_pts: PackedVector2Array = _female_body(f, 0.24) if female else _body(f, 0.25)
	sh.poly(bare_pts, c_skin, 0.0, 1.9)
	sh.ellipsoid(sc + Vector2(0.0, 1.25), w * 0.72, 1.35, c_skin, 0.5, 1.0)

	if has_cloth:
		var padded: bool = String(clothing.get("tid", "")) == "gambeson"
		var cloth_c: Color = _wardrobe_cloth(f, clothing)
		var c_cloth: int = sh.add_color(cloth_c, 0.09 if padded else 0.11, 1.08)
		var c_sec: int = sh.add_color(f.sec, 0.16, 1.10)
		var c_skirt: float = 0.65 if mounted else (float(f.leg_len) * (0.30 if padded else 0.28))
		var c_pts: PackedVector2Array = _female_body(f, c_skirt) if female else _wardrobe_shape(f, c_skirt, padded)
		sh.poly(c_pts, c_cloth, 0.5, 2.0)
		sh.ellipsoid(sc + Vector2(0.0, 1.30), w * 0.76, 1.45, c_cloth, 0.9, 1.0)
		sh.capsule(_tp(f, -0.85, 0.05), _tp(f, 0.05, 0.95), 0.18, 0.18, c_sec, 1.3, 0.9)
		sh.capsule(_tp(f, 0.05, 0.95), _tp(f, 0.95, 0.12), 0.18, 0.18, c_sec, 1.3, 0.9)

	if has_armor:
		var kind: String = String(body.get("sprite", ""))
		var m: Dictionary = FigurePainter.metal(String(body.get("mat", "copper")), int(body.get("q", 0)))
		var mail: bool = kind in ["mail", "byrnie"]
		var scale_a: bool = kind == "scale"
		var lamellar: bool = kind == "lamellar"
		var scrap: bool = kind == "scrap"
		var c_arm: int = sh.add_color(m["base"], 0.28 if mail else 0.34, 1.18, m["shine"], 0.12 if mail else (0.10 if scale_a or lamellar else 0.05))
		var c_arm_d: int = sh.add_color(m["dark"], 0.24, 1.14, m["shine"])
		var c_trim: int = sh.add_color(m["trim"], 0.36, 1.18, m["shine"])
		var a_skirt: float = 0.62 if mounted else (float(f.leg_len) * (0.38 if kind == "mail" else (0.32 if lamellar else 0.15)))
		var a_pts: PackedVector2Array = _female_body(f, a_skirt, true) if female else _wardrobe_shape(f, a_skirt, false)
		sh.poly(a_pts, c_leath if scrap else c_arm, 1.1, 2.2)
		sh.ellipsoid(sc + Vector2(0.05, 1.30), w * 0.80, 1.52, c_arm, 1.5, 1.1)
		if scrap:
			for ri in 3:
				var ry: float = sc.y + 0.85 + float(ri) * 1.15
				sh.capsule(Vector2(-w * 0.72, ry), Vector2(w * 0.72, ry - 0.12), 0.38, 0.36, c_arm if ri % 2 == 0 else c_arm_d, 2.0, 0.95)
		var belt_p: Vector2 = hip.lerp(sc, 0.20)
		sh.capsule(belt_p + Vector2(-h - 0.12, 0.0), belt_p + Vector2(h + 0.12, 0.0), 0.30, 0.30, c_leath, 2.4, 1.0)
		sh.ellipsoid(belt_p + Vector2(0.45, 0.0), 0.38, 0.30, c_trim, 2.7, 1.0)
	elif has_cloth:
		var belt_p: Vector2 = hip.lerp(sc, 0.20)
		sh.capsule(belt_p + Vector2(-h - 0.10, 0.0), belt_p + Vector2(h + 0.10, 0.0), 0.28, 0.28, c_leath, 2.0, 0.95)
		sh.ellipsoid(belt_p + Vector2(0.45, 0.0), 0.36, 0.28, c_brass, 2.3, 0.95)

	sh.composite(FigurePainter.ol(f.skin), true)
	return true

static func _legacy_torso(f) -> bool:
	if not f._it("body").is_empty() or not f._it("clothing").is_empty():
		return _wardrobe_torso(f)
	if _female(f):
		return _female_torso(f)
	if not f._it("body").is_empty():
		return false
	var cv: PixelCanvas = f.cv
	var skin: Color = f.skin
	var length: float = float(f.torso_len)
	cv.begin()
	cv.poly(_body(f,0.25),skin)
	cv.poly(PackedVector2Array([_tp(f,-2.25,0.55),_tp(f,-1.0,0.4),_tp(f,-0.75,length*0.5),
		_tp(f,-0.8,length),_tp(f,-1.8,length+0.2),_tp(f,-1.95,length*0.4)]),skin.darkened(0.25))
	cv.capsule(_tp(f,-0.7,0.45),_tp(f,1.8,1.0),0.17,skin.lightened(0.19))
	cv.end(FigurePainter.ol(skin),0.06)
	var clothing: Dictionary = f._it("clothing")
	if clothing.is_empty():
		return true
	var cloth: Color = f._cloth_col()
	var trim: Color = f.sec
	var skirt: float = float(f.leg_len)*0.3
	cv.begin()
	cv.poly(_body(f,skirt),cloth)
	cv.poly(PackedVector2Array([_tp(f,-2.4,0.55),_tp(f,-1.1,0.05),_tp(f,-0.75,1.45),
		_tp(f,-0.87,length),_tp(f,-1.86,length+skirt-0.15),_tp(f,-2.03,length*0.45)]),cloth.darkened(0.27))
	cv.poly(PackedVector2Array([_tp(f,0.1,1.5),_tp(f,2.0,1.2),_tp(f,1.5,length-0.4),_tp(f,0.45,length-0.35)]),cloth.lightened(0.15))
	cv.poly(PackedVector2Array([_tp(f,-1.05,-0.05),_tp(f,0.05,1.05),_tp(f,1.08,0.15),_tp(f,0.75,0.02),_tp(f,0.05,0.6),_tp(f,-0.65,-0.12)]),trim)
	cv.capsule(_tp(f,0.04,1.0),_tp(f,0.16,1.88),0.12,cloth.darkened(0.4))
	cv.capsule(_tp(f,-1.1,length+0.15),_tp(f,-0.62,length+skirt-0.28),0.1,cloth.lightened(0.22))
	cv.capsule(_tp(f,0.25,length+0.13),_tp(f,0.63,length+skirt-0.15),0.13,cloth.darkened(0.28))
	if String(clothing.get("tid","")) == "gambeson":
		for i in 4:
			var x: float = -1.5 + float(i)*0.8
			cv.capsule(_tp(f,x,1.8),_tp(f,x*0.82,length+skirt-0.3),0.08,cloth.darkened(0.16))
	cv.capsule(_tp(f,-1.85,length+skirt-0.38),_tp(f,1.87,length+skirt-0.18),0.18,trim.darkened(0.12))
	cv.end(FigurePainter.ol(cloth),0.06)
	# This is the native tunic belt, shaped to the narrower waist.
	var belt_y: float = length*0.88
	cv.begin()
	cv.poly(PackedVector2Array([_tp(f,-1.85,belt_y-0.25),_tp(f,1.85,belt_y-0.2),
		_tp(f,1.85,belt_y+0.4),_tp(f,-1.85,belt_y+0.32)]),FigurePainter.LEATHER)
	cv.rect(Rect2(_tp(f,0.9,belt_y-0.18),Vector2(0.6,0.53)),FigurePainter.metal("copper")["light"])
	cv.end(FigurePainter.ol(FigurePainter.LEATHER),0.03)
	return true

static func _limb(cv: PixelCanvas, a: Vector2, b: Vector2, ra: float, rb: float, color: Color) -> void:
	var d: Vector2 = (b-a).normalized()
	var n: Vector2 = Vector2(-d.y,d.x)
	var mid: Vector2 = a.lerp(b,0.4)
	cv.poly(PackedVector2Array([a-d*ra*0.3,a+n*ra,mid+n*ra*0.82,b+n*rb,
		b+d*rb*0.35,b-n*rb,mid-n*ra*0.86,a-n*ra]),color)
	cv.capsule(a+n*ra*0.25,b+n*rb*0.2,maxf(0.1,rb*0.22),color.lightened(0.18))
	cv.capsule(a-n*ra*0.62,b-n*rb*0.53,0.11,color.darkened(0.23))

static func arm(f, side: String) -> bool:
	if _force_legacy_v064:
		return _legacy_arm(f, side)
	var cv: PixelCanvas = f.cv
	var sh_pt: Vector2 = f.j["s" + side]
	var el: Vector2 = f.j["e" + side]
	var hd: Vector2 = f.j["h" + side]
	if f._lost("arm_upper_" + side):
		cv.dot(sh_pt, FigurePainter.BLOOD)
		return true
	var r: float = float(f.arm_r)
	var skin_c: Color = f.skin.darkened(0.12) if side == "l" else f.skin
	var lower_lost: bool = f._lost("arm_lower_" + side)
	var hand_lost: bool = f._lost("hand_" + side)
	var clothing: Dictionary = f._it("clothing")
	var body: Dictionary = f._it("body")
	var hands_it: Dictionary = f._it("hands")

	var sh := cv.shaded()
	var c_skin: int = sh.add_color(skin_c, 0.14, 1.08)
	sh.capsule(sh_pt, el, r * 0.94, r * 0.70, c_skin, 0.0, 1.0)
	if not lower_lost:
		sh.capsule(el, hd, r * 0.78, r * 0.54, c_skin, 0.2, 1.0)

	if not clothing.is_empty():
		var padded: bool = String(clothing.get("tid", "")) == "gambeson"
		var c_cloth: int = sh.add_color(_wardrobe_cloth(f, clothing).darkened(0.08 if side == "l" else 0.0), 0.09, 1.08)
		sh.capsule(sh_pt, sh_pt.lerp(el, 0.78 if padded else 0.67), r * (1.16 if padded else 1.06), r * (0.94 if padded else 0.82), c_cloth, 0.5, 1.0)

	if not body.is_empty():
		var b_kind: String = String(body.get("sprite", ""))
		var m: Dictionary = FigurePainter.metal(String(body.get("mat", "copper")), int(body.get("q", 0)))
		var mail: bool = b_kind in ["mail", "byrnie"]
		var c_arm: int = sh.add_color(m["base"].darkened(0.08 if side == "l" else 0.0), 0.28 if mail else 0.34, 1.16, m["shine"], 0.12 if mail else 0.05)
		sh.capsule(sh_pt, sh_pt.lerp(el, 0.85 if b_kind == "mail" else 0.52), r * 1.14, r * 0.88, c_arm, 1.1, 1.05)
		if b_kind in ["scrap", "lamellar", "scale", "plate"]:
			sh.ellipsoid(sh_pt + Vector2(0.0, 0.08), r * 1.26, r * 1.08, c_arm, 1.5, 1.1)

	if not lower_lost:
		if not hands_it.is_empty():
			var hm: Dictionary = FigurePainter.metal(String(hands_it.get("mat", "copper")), int(hands_it.get("q", 0)))
			var h_tid: String = String(hands_it.get("tid", ""))
			var c_hnd: int = sh.add_color(hm["base"].darkened(0.08 if side == "l" else 0.0), 0.32, 1.16, hm["shine"])
			sh.capsule(el.lerp(hd, 0.22), el.lerp(hd, 0.82), r * 0.94, r * 0.72, c_hnd, 1.3, 1.0)
			if h_tid.contains("gauntlet") and not hand_lost:
				sh.ellipsoid(hd, r * 0.86, r * 0.94, c_hnd, 1.6, 1.0)
			elif not hand_lost:
				sh.ellipsoid(hd, r * 0.82, r * 0.92, c_skin, 0.8, 1.0)
		elif not hand_lost:
			sh.ellipsoid(hd, r * 0.82, r * 0.92, c_skin, 0.8, 1.0)

	sh.composite(FigurePainter.ol(skin_c), true)
	if lower_lost:
		cv.dot(el, FigurePainter.BLOOD)
	elif hand_lost:
		cv.dot(hd, FigurePainter.BLOOD)
	return true

static func _legacy_arm(f, side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var sh: Vector2 = f.j["s"+side]
	var el: Vector2 = f.j["e"+side]
	var hd: Vector2 = f.j["h"+side]
	if f._lost("arm_upper_"+side):
		cv.dot(sh,FigurePainter.BLOOD)
		return true
	var r: float = float(f.arm_r)
	var skin: Color = f.skin
	if side == "l": skin = skin.darkened(0.12)
	var lower_lost: bool = f._lost("arm_lower_"+side)
	var hand_lost: bool = f._lost("hand_"+side)
	cv.begin()
	_limb(cv,sh,el,r*0.92,r*0.67,skin)
	cv.ellipse(el,r*0.75,r*0.68,skin)
	if not lower_lost:
		_limb(cv,el,hd,r*0.77,r*0.46,skin)
		if not hand_lost:
			cv.ellipse(hd,r*0.8,r*0.92,skin)
			cv.capsule(hd+Vector2(-0.28,-0.34),hd+Vector2(0.45,-0.21),0.16,skin.lightened(0.18))
	cv.end(FigurePainter.ol(skin),0.05)
	_wardrobe_sleeve(f,side,sh,el,r)
	_wardrobe_bracer(f,side,el,hd,r)
	if lower_lost: cv.dot(el,FigurePainter.BLOOD)
	elif hand_lost: cv.dot(hd,FigurePainter.BLOOD)
	return true

static func leg(f, side: String) -> bool:
	if _force_legacy_v064:
		return _legacy_leg(f, side)
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p" + side]
	var kn: Vector2 = f.j["k" + side]
	var ft: Vector2 = f.j["f" + side]
	if f._lost("leg_upper_" + side):
		cv.dot(hp, FigurePainter.BLOOD)
		return true
	var trousers: bool = not f._it("legs_under").is_empty()
	var color: Color = f._trouser_col() if trousers else f.skin
	if side == "l":
		color = color.darkened(0.10)
	var radius: float = float(f.leg_r)
	var lower_lost: bool = f._lost("leg_lower_" + side)
	var foot_lost: bool = f._lost("foot_" + side)
	var greaves: Dictionary = f._it("legs")
	var shoes: Dictionary = f._it("feet")

	var sh := cv.shaded()
	var c_leg: int = sh.add_color(color, 0.10 if trousers else 0.14, 1.08)
	sh.capsule(hp, kn, radius * 0.96, radius * 0.68, c_leg, 0.0, 1.05)
	if not lower_lost:
		sh.capsule(kn, ft, radius * 0.76, radius * 0.52, c_leg, 0.2, 1.0)
		if not greaves.is_empty():
			var gm: Dictionary = FigurePainter.metal(String(greaves.get("mat", "copper")), int(greaves.get("q", 0)))
			var c_grv: int = sh.add_color(gm["base"].darkened(0.08 if side == "l" else 0.0), 0.32, 1.18, gm["shine"])
			sh.ellipsoid(kn, radius * 0.85, radius * 0.72, c_grv, 1.2, 1.0)
			sh.capsule(kn.lerp(ft, 0.10), kn.lerp(ft, 0.88), radius * 0.86, radius * 0.60, c_grv, 1.0, 1.05)
		if not foot_lost:
			var boot_c: Color = f.skin if shoes.is_empty() else FigurePainter.LEATHER.darkened(0.20)
			if not shoes.is_empty() and String(shoes.get("mat", "")) in ["copper", "tin", "iron", "steel", "bronze", "silver", "gold"]:
				boot_c = FigurePainter.metal(String(shoes.get("mat", "iron")), int(shoes.get("q", 0)))["base"]
			if side == "l":
				boot_c = boot_c.darkened(0.10)
			var c_boot: int = sh.add_color(boot_c, 0.18 if not shoes.is_empty() else 0.14, 1.12)
			sh.capsule(ft + Vector2(-0.50, -0.25), ft + Vector2(1.55, 0.65), radius * 0.68, radius * 0.56, c_boot, 1.3, 1.0)

	sh.composite(FigurePainter.ol(color), true)
	if lower_lost:
		cv.dot(kn, FigurePainter.BLOOD)
	elif foot_lost:
		cv.dot(ft, FigurePainter.BLOOD)
	return true

static func _legacy_leg(f, side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p"+side]
	var kn: Vector2 = f.j["k"+side]
	var ft: Vector2 = f.j["f"+side]
	if f._lost("leg_upper_"+side):
		cv.dot(hp,FigurePainter.BLOOD)
		return true
	var trousers: bool = not f._it("legs_under").is_empty()
	var color: Color = f._trouser_col() if trousers else f.skin
	if side == "l": color = color.darkened(0.1)
	var radius: float = float(f.leg_r)
	var lower_lost: bool = f._lost("leg_lower_"+side)
	var foot_lost: bool = f._lost("foot_"+side)
	cv.begin()
	_limb(cv,hp,kn,radius*0.94,radius*0.66,color)
	cv.ellipse(kn,radius*0.75,radius*0.69,color)
	if not lower_lost:
		_limb(cv,kn,ft,radius*0.72,radius*0.48,color)
	cv.end(FigurePainter.ol(color),0.06)
	if trousers and not lower_lost:
		cv.capsule(kn+Vector2(-0.45,-0.36),kn+Vector2(0.5,-0.1),0.13,color.lightened(0.18))
	if lower_lost:
		cv.dot(kn,FigurePainter.BLOOD)
	elif foot_lost:
		cv.dot(ft,FigurePainter.BLOOD)
	else:
		var skin: Color = f.skin
		if side == "l": skin = skin.darkened(0.1)
		cv.begin()
		_poly(cv,ft,[[-0.8,-0.45],[0.45,-0.58],[0.9,0.0],[2.1,0.56],[2.25,1.3],[0.45,1.45],[-1.0,1.07]],skin)
		cv.capsule(ft+Vector2(-0.15,0.02),ft+Vector2(1.6,0.82),0.15,skin.lightened(0.18))
		cv.end(FigurePainter.ol(skin),0.04)
	_wardrobe_leg_layers(f,side,hp,kn,ft,radius)
	if lower_lost:
		cv.dot(kn,FigurePainter.BLOOD)
	elif foot_lost:
		cv.dot(ft,FigurePainter.BLOOD)
	return true

static func _female(f) -> bool:
	return String(f.spec.get("sex", "")).to_lower() in ["female", "f", "woman"]

static func _retained_female_head(f) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = absi(int(f.spec.get("seed",0)))
	var style: int = seed % 5
	var shadow: Color = skin.darkened(0.22)
	var deep: Color = skin.darkened(0.5).lerp(Color("#26301d"),0.12)
	var light: Color = skin.lightened(0.19)
	var brow: Color = hair.darkened(0.23).lerp(deep,0.6)
	var nose: float = 0.09 * float((seed / 5) % 3)
	var chin: float = 0.04 * float((seed / 11) % 3)
	var lift: float = 0.1 * float((seed / 7) % 3)
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead",false))
	var coif: bool = String(f._it("helm").get("sprite","")) == "coif"
	# Hair sits behind the ears, skull and real helmet; no invented ties or ornaments.
	_retained_female_hair_back(f,hc,style,coif)
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-0.5,1.6),hc+Vector2(0.96,1.92),sc+Vector2(1.02,0.6),sc+Vector2(-0.76,0.5)]),shadow)
		cv.capsule(hc+Vector2(0.26,2.15),sc+Vector2(0.6,0.5),0.16,skin)
		cv.end(FigurePainter.ol(skin),0.05)
	if not coif:
		cv.begin()
		if not f._lost("ear_l"):
			_poly(cv,hc,[[1.24,-1.7],[4.4,-3.03-lift],[3.46,-1.15],[2.15,0.18],[1.28,-0.28]],shadow)
		if not f._lost("ear_r"):
			_poly(cv,hc,[[-1.58,-1.35],[-2.85,-1.7],[-5.87,-2.95-lift],[-4.49,-0.82],[-2.57,0.58],[-1.63,0.06]],skin)
		cv.end(FigurePainter.ol(skin),0.04)
		if not f._lost("ear_r"):
			_poly(cv,hc,[[-2.0,-0.98],[-5.18,-2.43-lift],[-3.34,-0.85],[-2.5,0.14]],shadow)
			cv.capsule(hc+Vector2(-2.57,-1.42),hc+Vector2(-5.06,-2.41-lift),0.1,light)
			cv.capsule(hc+Vector2(-2.08,-0.72),hc+Vector2(-2.43,0.08),0.13,deep)
		if not f._lost("ear_l"):
			_poly(cv,hc,[[2.04,-1.27],[3.82,-2.52-lift],[2.99,-0.94],[2.19,-0.15]],skin.darkened(0.34))
	# The adult high cheekbones and long temple taper to a small angular chin.
	cv.begin()
	if f._lost("jaw"):
		_poly(cv,hc,[[-1.96,-1.77],[-1.38,-2.68],[-0.12,-2.99],[1.2,-2.67],[1.88,-1.91],
			[2.0,-1.06],[1.84,-0.25],[2.14,0.35],[1.76,1.02],[0.45,1.02],[-0.79,0.94],[-1.76,0.34],[-2.15,-0.73]],skin)
		_poly(cv,hc,[[-1.96,-1.77],[-1.38,-2.68],[-0.92,-1.76],[-1.17,-0.19],[-0.5,0.85],
			[-0.79,0.94],[-1.76,0.34],[-2.15,-0.73]],shadow)
	else:
		_poly(cv,hc,[[-1.96,-1.77],[-1.38,-2.68],[-0.12,-2.99],[1.2,-2.67],[1.88,-1.91],
			[2.0,-1.06],[1.84,-0.25],[2.14,0.35],[1.76,1.02],[0.45,1.58],[-0.79,1.3],[-1.76,0.34],[-2.15,-0.73]],skin)
		_poly(cv,hc,[[-1.96,-1.77],[-1.38,-2.68],[-0.92,-1.76],[-1.17,-0.19],[-0.5,0.85],
			[-0.79,1.3],[-1.76,0.34],[-2.15,-0.73]],shadow)
	_poly(cv,hc,[[-1.05,-2.54],[-0.09,-2.83],[1.14,-2.5],[1.54,-1.85],[0.66,-1.61],[-0.85,-1.78]],light)
	_poly(cv,hc,[[-0.93,-0.24],[-0.36,-0.37],[0.7,-0.06],[1.29,0.23],[0.88,0.66],[-0.36,0.77],[-0.97,0.34]],light)
	_poly(cv,hc,[[-1.44,0.23],[-0.82,0.5],[-0.36,1.12],[-0.7,1.27],[-1.27,0.83]],skin.darkened(0.26))
	if not f._lost("jaw"):
		_poly(cv,hc,[[-0.85,0.98],[0.42,1.14],[1.88,0.85],[1.48,1.65],[0.84+chin,2.5],[0.37,2.57],[-0.31,2.14],[-0.88,1.42]],skin)
		_poly(cv,hc,[[-0.85,0.98],[-0.31,1.12],[-0.1,1.93],[0.37,2.57],[-0.31,2.14],[-0.88,1.42]],shadow)
		_poly(cv,hc,[[0.4,1.78],[1.23,1.63],[1.0,2.08],[0.59,2.3],[0.18,2.08]],skin.lightened(0.1))
	# A slim but unmistakably hooked goblin bridge and downturned tip.
	if not f._lost("nose"):
		_poly(cv,hc,[[1.35,-1.52],[1.86,-1.5],[2.18,-0.86],[3.2+nose,-0.08],[3.63+nose,0.5],
			[3.33+nose,0.91],[2.81,0.79],[2.37,0.32],[1.48,-0.07]],skin)
		_poly(cv,hc,[[1.61,-1.3],[1.8,-1.28],[2.02,-0.66],[3.09+nose,-0.03],[3.37+nose,0.29],
			[2.87,0.28],[2.18,-0.08],[1.68,-0.31]],light)
		_poly(cv,hc,[[2.47,0.36],[3.1,0.5],[3.6+nose,0.53],[3.33+nose,0.91],[2.81,0.79]],shadow)
	cv.end(FigurePainter.ol(skin),0.055)
	_retained_female_eye(f,hc+Vector2(0.48,-0.85),0.79,skin,deep,brow,dead,"eye_r")
	_retained_female_eye(f,hc+Vector2(1.78,-1.01),0.33,skin,deep,brow,dead,"eye_l")
	cv.capsule(hc+Vector2(-0.36,-1.44),hc+Vector2(0.13,-1.65),0.1,brow)
	cv.capsule(hc+Vector2(0.13,-1.65),hc+Vector2(1.14,-1.44),0.1,brow)
	cv.capsule(hc+Vector2(1.49,-1.53),hc+Vector2(1.82,-1.7),0.085,brow)
	cv.capsule(hc+Vector2(1.82,-1.7),hc+Vector2(2.15,-1.63),0.085,brow)
	if not f._lost("nose"):
		cv.capsule(hc+Vector2(2.85,0.62),hc+Vector2(3.22+nose,0.71),0.1,deep)
	if not f._lost("mouth") and not f._lost("jaw"):
		var lip: Color = skin.darkened(0.23).lerp(Color("#766044"),0.18)
		_poly(cv,hc,[[0.49,1.32],[0.84,1.2],[1.12,1.29],[1.43,1.17],[1.87,1.22],[1.37,1.48],[0.83,1.49]],lip)
		cv.capsule(hc+Vector2(0.56,1.34),hc+Vector2(1.79,1.27),0.08,deep)
		cv.capsule(hc+Vector2(0.92,1.52),hc+Vector2(1.4,1.48),0.08,skin.lightened(0.16))
	_retained_female_hair_front(f,hc,style,coif)
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _retained_female_eye(f, p: Vector2, width: float, skin: Color, deep: Color, brow: Color, dead: bool, part: String) -> void:
	if f._lost(part):
		return
	var cv: PixelCanvas = f.cv
	if dead:
		cv.capsule(p+Vector2(-width*0.8,0.02),p+Vector2(width*0.7,-0.09),0.11,brow)
		return
	_poly(cv,p,[[-width,-0.1],[-width*0.25,-0.29],[width,-0.19],[width*0.45,0.21],[-width*0.45,0.19]],deep)
	_poly(cv,p,[[-width*0.78,-0.06],[-width*0.15,-0.17],[width*0.79,-0.13],[width*0.33,0.1],[-width*0.4,0.1]],Color("#ded05b"))
	cv.ellipse(p+Vector2(width*0.33,-0.03),0.18 if width>0.5 else 0.12,0.19,Color("#efca42"))
	cv.ellipse(p+Vector2(width*0.38,-0.02),0.085,0.15,deep)
	cv.capsule(p+Vector2(-width,-0.1),p+Vector2(-width*0.17,-0.28),0.1,brow)
	cv.capsule(p+Vector2(-width*0.17,-0.28),p+Vector2(width,-0.19),0.1,brow)
	cv.capsule(p+Vector2(-width*0.58,0.27),p+Vector2(width*0.48,0.23),0.065,skin.darkened(0.27))

static func _retained_female_hair_back(f, hc: Vector2, style: int, coif: bool) -> void:
	if coif:
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	cv.begin()
	match style:
		0:
			_poly(cv,hc,[[-1.48,-2.57],[-2.37,-2.03],[-2.46,-0.72],[-2.1,0.44],[-1.63,0.25],[-1.61,-1.34]],hair)
		1:
			_poly(cv,hc,[[-1.52,-2.52],[-2.44,-2.01],[-2.67,-0.67],[-2.43,0.47],[-1.57,0.38],[-1.55,-1.2]],hair)
			_poly(cv,hc,[[-2.3,-1.57],[-3.12,-1.36],[-3.97,-0.52],[-4.27,1.03],[-3.81,2.46],[-3.14,3.68],[-2.62,4.18],[-2.97,2.3],[-3.3,0.7],[-2.9,-0.28],[-2.35,-0.64]],hair)
		2:
			_poly(cv,hc,[[-1.52,-2.48],[-2.33,-2.0],[-2.64,-0.61],[-2.29,0.66],[-1.73,0.31],[-1.67,-1.24]],hair)
			cv.capsule(hc+Vector2(-2.51,0.12),hc+Vector2(-2.89,2.4),0.49,hair)
			cv.capsule(hc+Vector2(-2.89,2.4),hc+Vector2(-2.52,4.39),0.4,hair)
		3:
			_poly(cv,hc,[[-1.38,-2.54],[-2.48,-2.1],[-2.88,-0.73],[-2.59,1.03],[-2.92,2.47],[-2.74,4.1],[-2.05,4.8],[-1.5,3.55],[-1.57,1.32],[-1.36,-0.8]],hair)
			_poly(cv,hc,[[1.36,-2.05],[2.11,-1.35],[2.29,0.44],[2.15,2.03],[1.59,3.33],[1.35,2.8],[1.56,0.5]],hair.darkened(0.09))
		4:
			_poly(cv,hc,[[-1.42,-2.63],[-2.57,-2.12],[-2.73,-0.92],[-2.38,0.85],[-1.93,1.08],[-1.66,0.02],[-1.69,-1.53]],hair)
	cv.end(FigurePainter.ol(hair),0.05)
	if style == 2:
		for i in 5:
			var p: Vector2 = hc+Vector2(-2.59-0.05*float(mini(i,2)),0.78+float(i)*0.69)
			cv.capsule(p+Vector2(-0.29,-0.14),p+Vector2(0.25,0.19),0.13,hair.lightened(0.22))
	elif style in [1,3]:
		cv.capsule(hc+Vector2(-2.67,0.5),hc+Vector2(-2.57,3.35),0.13,hair.lightened(0.2))

static func _retained_female_hair_front(f, hc: Vector2, style: int, coif: bool) -> void:
	if coif:
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var helmed: bool = not f._it("helm").is_empty()
	cv.begin()
	if not helmed:
		if style == 0:
			_poly(cv,hc,[[-2.06,-1.65],[-2.15,-2.55],[-1.11,-3.31],[0.17,-3.25],[1.16,-3.59],[1.68,-2.96],
				[1.58,-2.19],[0.91,-2.54],[0.25,-2.2],[-0.34,-2.46],[-1.13,-1.73],[-1.61,-1.03]],hair)
		elif style == 4:
			_poly(cv,hc,[[-2.17,-1.57],[-2.32,-2.44],[-1.48,-3.25],[-0.27,-3.47],[1.0,-3.1],[1.78,-2.3],
				[0.85,-2.55],[-0.04,-2.04],[-1.12,-1.26],[-1.66,-0.78]],hair)
		else:
			_poly(cv,hc,[[-2.07,-1.32],[-2.28,-2.44],[-1.5,-3.14],[-0.27,-3.34],[0.83,-3.15],[1.65,-2.64],
				[1.77,-2.15],[0.67,-2.55],[0.06,-2.24],[-0.69,-2.33],[-1.35,-1.42],[-1.61,-0.47]],hair)
	else:
		_poly(cv,hc,[[-2.08,-1.04],[-1.67,-1.33],[-1.66,-0.39],[-2.13,-0.15]],hair)
	cv.end(FigurePainter.ol(hair),0.05)
	if not helmed:
		cv.capsule(hc+Vector2(-1.58,-2.8),hc+Vector2(-0.48,-2.98),0.12,hair.lightened(0.23))
		cv.capsule(hc+Vector2(0.1,-2.99),hc+Vector2(1.23,-2.55),0.1,hair.lightened(0.18))

static func _beauty_contour(cv: PixelCanvas, origin: Vector2, points: Array, color: Color, pat: Callable = Callable()) -> void:
	# Female-only rounded outlines use the same native canvas and moving head anchor.
	var control: Array[Vector2] = []
	for p in points:
		control.append(Vector2(float(p[0]),float(p[1])))
	var pts: PackedVector2Array = PackedVector2Array()
	for i in control.size():
		var a: Vector2 = (control[posmod(i-1,control.size())]+control[i])*0.5
		var b: Vector2 = control[i]
		var d: Vector2 = (control[i]+control[(i+1)%control.size()])*0.5
		for step in 4:
			var t: float = float(step)/4.0
			pts.append(origin+a*(1.0-t)*(1.0-t)+b*2.0*t*(1.0-t)+d*t*t)
	cv.poly(pts,color,pat)

static func _female_head(f) -> void:
	if FigurePainter.female_variant(f.spec) == 0:
		_retained_female_head(f)
		return
	if f._lost("head"): return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = absi(int(f.spec.get("seed",0)))
	var style: int = seed % 5
	var shadow: Color = skin.darkened(0.15)
	var deep: Color = skin.darkened(0.44).lerp(Color("#26301d"),0.08)
	var light: Color = skin.lightened(0.14)
	var brow: Color = hair.darkened(0.17).lerp(deep,0.52)
	var nose: float = 0.045 * float((seed / 5) % 3)
	var chin: float = 0.025 * float((seed / 11) % 3)
	var lift: float = 0.1 * float((seed / 7) % 3)
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead",false))
	var coif: bool = String(f._it("helm").get("sprite","")) == "coif"
	_female_hair_back(f,hc,style,coif)
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-0.5,1.6),hc+Vector2(0.96,1.92),sc+Vector2(1.02,0.6),sc+Vector2(-0.76,0.5)]),shadow)
		cv.capsule(hc+Vector2(0.26,2.15),sc+Vector2(0.6,0.5),0.16,skin)
		cv.end(FigurePainter.ol(skin),0.05)
	# Keep the distinctive large pointed ears and native loss/coif masks.
	if not coif:
		cv.begin()
		if not f._lost("ear_l"):
			_poly(cv,hc,[[1.24,-1.7],[4.4,-3.03-lift],[3.46,-1.15],[2.15,0.18],[1.28,-0.28]],shadow)
		if not f._lost("ear_r"):
			_poly(cv,hc,[[-1.58,-1.35],[-2.85,-1.7],[-5.87,-2.95-lift],[-4.49,-0.82],[-2.57,0.58],[-1.63,0.06]],skin)
		cv.end(FigurePainter.ol(skin),0.04)
		if not f._lost("ear_r"):
			_poly(cv,hc,[[-2.0,-0.98],[-5.18,-2.43-lift],[-3.34,-0.85],[-2.5,0.14]],shadow)
			cv.capsule(hc+Vector2(-2.57,-1.42),hc+Vector2(-5.06,-2.41-lift),0.1,light)
			cv.capsule(hc+Vector2(-2.08,-0.72),hc+Vector2(-2.43,0.08),0.11,deep)
		if not f._lost("ear_l"):
			_poly(cv,hc,[[2.04,-1.27],[3.82,-2.52-lift],[2.99,-0.94],[2.19,-0.15]],skin.darkened(0.26))
	# Adult cheekbones retain the goblin taper, with smoother planes and a quieter jaw.
	cv.begin()
	if f._lost("jaw"):
		_beauty_contour(cv,hc,[[-1.98,-1.8],[-1.4,-2.78],[-0.12,-3.08],[1.2,-2.7],[1.91,-1.92],
			[2.0,-0.94],[1.87,-0.2],[2.08,0.43],[1.64,1.04],[0.34,1.08],
			[-0.84,0.95],[-1.67,0.35],[-2.03,-0.73]],skin)
		_beauty_contour(cv,hc,[[-1.86,-1.7],[-1.43,-2.48],[-1.07,-1.61],[-1.29,-0.12],[-0.74,0.81],
			[-0.88,0.94],[-1.68,0.29],[-1.99,-0.74]],shadow)
	else:
		_beauty_contour(cv,hc,[[-1.98,-1.8],[-1.4,-2.78],[-0.12,-3.08],[1.2,-2.7],[1.91,-1.92],
			[2.0,-0.94],[1.87,-0.2],[2.08,0.43],[1.64,1.19],[1.05,1.67],[0.25,1.78],
			[-0.74,1.26],[-1.67,0.35],[-2.03,-0.73]],skin)
		_beauty_contour(cv,hc,[[-1.86,-1.7],[-1.43,-2.48],[-1.07,-1.61],[-1.29,-0.12],[-0.74,0.81],
			[-0.25,1.58],[-0.77,1.21],[-1.68,0.29],[-1.99,-0.74]],shadow)
	_beauty_contour(cv,hc,[[-1.04,-2.49],[-0.07,-2.9],[1.1,-2.57],[1.51,-1.89],[0.6,-1.65],[-0.86,-1.81]],light)
	_beauty_contour(cv,hc,[[-0.99,-0.16],[-0.4,-0.34],[0.37,-0.09],[0.88,0.43],[0.31,0.78],[-0.69,0.62]],skin.lightened(0.10))
	if not f._lost("jaw"):
		_beauty_contour(cv,hc,[[-0.83,1.02],[0.36,1.18],[1.79,0.94],[1.51,1.68],[0.88+chin,2.2],
			[0.32,2.27],[-0.37,1.91],[-0.79,1.47]],skin)
		_beauty_contour(cv,hc,[[-0.81,1.07],[-0.26,1.23],[-0.13,1.89],[0.31,2.27],[-0.38,1.9],[-0.78,1.47]],shadow)
		_beauty_contour(cv,hc,[[0.34,1.77],[1.18,1.65],[1.02,1.96],[0.55,2.13],[0.17,1.96]],skin.lightened(0.08))
	# Refined hook and tip remain goblin anatomy, without overwhelming the face.
	if not f._lost("nose"):
		_beauty_contour(cv,hc,[[1.23,-1.38],[1.58,-1.31],[1.77,-0.64],[2.59+nose,0.04],[2.79+nose,0.44],
			[2.5+nose,0.77],[2.15,0.66],[1.82,0.23],[1.33,-0.14]],skin)
		_beauty_contour(cv,hc,[[1.39,-1.17],[1.56,-1.14],[1.69,-0.61],[2.43+nose,0.07],[2.6+nose,0.35],
			[2.18,0.26],[1.78,-0.09],[1.41,-0.32]],light)
		_beauty_contour(cv,hc,[[2.1,0.39],[2.58,0.44],[2.76+nose,0.49],[2.49+nose,0.77],[2.17,0.66]],shadow)
	cv.end(FigurePainter.ol(skin),0.045)
	_female_eye(f,hc+Vector2(-0.18,-0.88),0.97,skin,deep,brow,dead,"eye_r")
	_female_eye(f,hc+Vector2(1.43,-1.0),0.39,skin,deep,brow,dead,"eye_l")
	cv.capsule(hc+Vector2(-1.18,-1.36),hc+Vector2(-0.42,-1.66),0.10,brow)
	cv.capsule(hc+Vector2(-0.42,-1.66),hc+Vector2(0.71,-1.49),0.09,brow)
	cv.capsule(hc+Vector2(1.03,-1.52),hc+Vector2(1.43,-1.7),0.075,brow)
	cv.capsule(hc+Vector2(1.43,-1.7),hc+Vector2(1.8,-1.6),0.07,brow)
	if not f._lost("nose"):
		cv.capsule(hc+Vector2(2.2,0.58),hc+Vector2(2.51+nose,0.65),0.075,deep)
	if not f._lost("mouth") and not f._lost("jaw"):
		var lip: Color = skin.darkened(0.16).lerp(Color("#ae6576"),0.28)
		_poly(cv,hc,[[0.12,1.28],[0.48,1.09],[0.75,1.17],[1.03,1.07],[1.63,1.21],
			[1.29,1.48],[0.75,1.57],[0.34,1.43]],lip)
		cv.capsule(hc+Vector2(0.24,1.31),hc+Vector2(1.51,1.24),0.065,deep.lerp(lip,0.34))
		cv.capsule(hc+Vector2(0.55,1.47),hc+Vector2(1.06,1.46),0.065,lip.lightened(0.26))
	_female_hair_front(f,hc,style,coif)
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _female_eye(f, p: Vector2, width: float, skin: Color, deep: Color, brow: Color, dead: bool, part: String) -> void:
	if f._lost(part): return
	var cv: PixelCanvas = f.cv
	if dead:
		cv.capsule(p+Vector2(-width*0.86,0.04),p+Vector2(width*0.8,-0.02),0.11,brow)
		return
	_beauty_contour(cv,p,[[-width,0.04],[-width*0.24,-0.4],[width*0.6,-0.29],[width*0.98,0.05],
		[width*0.41,0.42],[-width*0.46,0.36]],Color("#dfdfa4").lerp(skin.lightened(0.6),0.18))
	var rx: float = 0.3 if width>0.5 else 0.16
	cv.ellipse(p+Vector2(width*0.25,0.04),rx,0.32,Color("#b28e25"))
	cv.ellipse(p+Vector2(width*0.24,0.1),rx*0.77,0.22,Color("#efca42"))
	cv.ellipse(p+Vector2(width*0.29,0.02),0.12 if width>0.5 else 0.075,0.27,deep.darkened(0.36))
	cv.ellipse(p+Vector2(width*0.1,-0.13),0.075 if width>0.5 else 0.055,0.07,Color("#fff3c5"))
	cv.capsule(p+Vector2(-width,0.02),p+Vector2(-width*0.2,-0.31),0.10,brow)
	cv.capsule(p+Vector2(-width*0.2,-0.31),p+Vector2(width*0.65,-0.27),0.09,brow)
	cv.capsule(p+Vector2(-width,0.02),p+Vector2(-width*1.18,-0.16),0.08,brow)
	cv.capsule(p+Vector2(-width*0.63,0.39),p+Vector2(width*0.67,0.32),0.055,skin.darkened(0.1))

static func _female_hair_back(f, hc: Vector2, style: int, coif: bool) -> void:
	if coif:
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	cv.begin()
	match style:
		0:
			_beauty_contour(cv,hc,[[-1.48,-2.57],[-2.37,-2.03],[-2.46,-0.72],[-2.1,0.44],[-1.63,0.25],[-1.61,-1.34]],hair)
		1:
			_beauty_contour(cv,hc,[[-1.52,-2.52],[-2.44,-2.01],[-2.67,-0.67],[-2.43,0.47],[-1.57,0.38],[-1.55,-1.2]],hair)
			_beauty_contour(cv,hc,[[-2.3,-1.57],[-3.12,-1.36],[-3.97,-0.52],[-4.27,1.03],[-3.81,2.46],[-3.14,3.68],[-2.62,4.18],[-2.97,2.3],[-3.3,0.7],[-2.9,-0.28],[-2.35,-0.64]],hair)
		2:
			_beauty_contour(cv,hc,[[-1.52,-2.48],[-2.33,-2.0],[-2.64,-0.61],[-2.29,0.66],[-1.73,0.31],[-1.67,-1.24]],hair)
			cv.capsule(hc+Vector2(-2.51,0.12),hc+Vector2(-2.89,2.4),0.49,hair)
			cv.capsule(hc+Vector2(-2.89,2.4),hc+Vector2(-2.52,4.39),0.4,hair)
		3:
			_beauty_contour(cv,hc,[[-1.38,-2.54],[-2.48,-2.1],[-2.88,-0.73],[-2.59,1.03],[-2.92,2.47],[-2.74,4.1],[-2.05,4.8],[-1.5,3.55],[-1.57,1.32],[-1.36,-0.8]],hair)
			_beauty_contour(cv,hc,[[1.36,-2.05],[2.11,-1.35],[2.29,0.44],[2.15,2.03],[1.59,3.33],[1.35,2.8],[1.56,0.5]],hair.darkened(0.09))
		4:
			_beauty_contour(cv,hc,[[-1.42,-2.63],[-2.57,-2.12],[-2.73,-0.92],[-2.38,0.85],[-1.93,1.08],[-1.66,0.02],[-1.69,-1.53]],hair)
	cv.end(FigurePainter.ol(hair),0.05)
	if style == 2:
		for i in 5:
			var p: Vector2 = hc+Vector2(-2.59-0.05*float(mini(i,2)),0.78+float(i)*0.69)
			cv.capsule(p+Vector2(-0.29,-0.14),p+Vector2(0.25,0.19),0.13,hair.lightened(0.22))
	elif style in [1,3]:
		cv.capsule(hc+Vector2(-2.67,0.5),hc+Vector2(-2.57,3.35),0.13,hair.lightened(0.2))

static func _female_hair_front(f, hc: Vector2, style: int, coif: bool) -> void:
	if coif:
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var helmed: bool = not f._it("helm").is_empty()
	cv.begin()
	if not helmed:
		if style == 0:
			_beauty_contour(cv,hc,[[-2.06,-1.65],[-2.15,-2.55],[-1.11,-3.31],[0.17,-3.25],[1.16,-3.59],[1.68,-2.96],
				[1.58,-2.19],[0.91,-2.54],[0.25,-2.2],[-0.34,-2.46],[-1.13,-1.73],[-1.61,-1.03]],hair)
		elif style == 4:
			_beauty_contour(cv,hc,[[-2.17,-1.57],[-2.32,-2.44],[-1.48,-3.25],[-0.27,-3.47],[1.0,-3.1],[1.78,-2.3],
				[0.85,-2.55],[-0.04,-2.04],[-1.12,-1.26],[-1.66,-0.78]],hair)
		else:
			_beauty_contour(cv,hc,[[-2.07,-1.32],[-2.28,-2.44],[-1.5,-3.14],[-0.27,-3.34],[0.83,-3.15],[1.65,-2.64],
				[1.77,-2.15],[0.67,-2.55],[0.06,-2.24],[-0.69,-2.33],[-1.35,-1.42],[-1.61,-0.47]],hair)
	else:
		_beauty_contour(cv,hc,[[-2.08,-1.04],[-1.67,-1.33],[-1.66,-0.39],[-2.13,-0.15]],hair)
	cv.end(FigurePainter.ol(hair),0.05)
	if not helmed:
		cv.capsule(hc+Vector2(-1.58,-2.8),hc+Vector2(-0.48,-2.98),0.12,hair.lightened(0.23))
		cv.capsule(hc+Vector2(0.1,-2.99),hc+Vector2(1.23,-2.55),0.1,hair.lightened(0.18))

static func _female_body(f, skirt: float, armor: bool = false) -> PackedVector2Array:
	var w: float = float(f.tw)*0.5
	var h: float = float(f.hipw)*0.43
	var length: float = float(f.torso_len)
	var waist: float = h * (0.76 if armor else 0.62)
	var hem: float = h + (0.33 if skirt>0.0 else 0.0)
	return PackedVector2Array([_tp(f,-w+0.44,0.52),_tp(f,-0.82,0.02),_tp(f,0.97,0.12),_tp(f,w-0.5,0.61),
		_tp(f,w-0.46,length*0.32),_tp(f,waist,length*0.68),_tp(f,h,length*0.97),_tp(f,hem,length+skirt),
		_tp(f,0.3,length+skirt+0.1),_tp(f,-hem,length+skirt-0.04),_tp(f,-h,length*0.97),
		_tp(f,-waist,length*0.68),_tp(f,-w+0.61,length*0.31)])

static func _female_torso(f) -> bool:
	var body: Dictionary = f._it("body")
	var kind: String = String(body.get("sprite",""))
	if not body.is_empty() and kind not in ["mail","byrnie","scale","lamellar","scrap"]:
		return false
	var cv: PixelCanvas = f.cv
	var skin: Color = f.skin
	var length: float = float(f.torso_len)
	var h: float = float(f.hipw)*0.43
	cv.begin()
	cv.poly(_female_body(f,0.24),skin)
	cv.poly(PackedVector2Array([_tp(f,-2.13,0.7),_tp(f,-0.76,0.39),_tp(f,-0.52,length*0.58),
		_tp(f,-1.04,length*0.75),_tp(f,-h,length+0.15),_tp(f,-1.8,length*0.3)]),skin.darkened(0.2))
	cv.capsule(_tp(f,-0.65,0.47),_tp(f,1.47,0.9),0.12,skin.lightened(0.18))
	cv.end(FigurePainter.ol(skin),0.055)
	var clothing: Dictionary = f._it("clothing")
	if not clothing.is_empty():
		var cloth: Color = f._cloth_col()
		var trim: Color = f.sec
		var skirt: float = float(f.leg_len)*0.3
		cv.begin()
		cv.poly(_female_body(f,skirt),cloth)
		cv.poly(PackedVector2Array([_tp(f,-2.26,0.7),_tp(f,-0.8,0.34),_tp(f,-0.63,length*0.5),
			_tp(f,-1.13,length*0.75),_tp(f,-h-0.3,length+skirt-0.1),_tp(f,-h,length),_tp(f,-1.8,length*0.35)]),cloth.darkened(0.24))
		cv.poly(PackedVector2Array([_tp(f,0.17,1.35),_tp(f,2.06,1.13),_tp(f,h*0.63,length*0.66),
			_tp(f,0.44,length*0.75)]),cloth.lightened(0.16))
		cv.poly(PackedVector2Array([_tp(f,-0.82,0.01),_tp(f,0.16,0.94),_tp(f,0.98,0.15),
			_tp(f,0.68,0.06),_tp(f,0.16,0.51),_tp(f,-0.51,0.03)]),trim)
		cv.capsule(_tp(f,0.16,0.94),_tp(f,0.21,1.72),0.1,cloth.darkened(0.34))
		cv.capsule(_tp(f,-0.87,length+0.16),_tp(f,-1.27,length+skirt-0.17),0.1,cloth.lightened(0.2))
		cv.capsule(_tp(f,0.8,length+0.14),_tp(f,1.2,length+skirt-0.2),0.11,cloth.darkened(0.24))
		if String(clothing.get("tid","")) == "gambeson":
			for i in 4:
				var x: float = -1.4+float(i)*0.82
				cv.capsule(_tp(f,x,1.8),_tp(f,x*0.78,length+skirt-0.33),0.08,cloth.darkened(0.16))
		cv.capsule(_tp(f,-h-0.26,length+skirt-0.26),_tp(f,h+0.25,length+skirt-0.24),0.17,trim.darkened(0.1))
		cv.end(FigurePainter.ol(cloth),0.055)
		_female_belt(f,length*0.69,h*0.65,FigurePainter.LEATHER,FigurePainter.metal("copper")["light"])
	if body.is_empty():
		return true
	var m: Dictionary = FigurePainter.metal(String(body.get("mat","copper")),int(body.get("q",0)))
	var skirt: float = float(f.leg_len)*0.3
	match kind:
		"mail": skirt = float(f.leg_len)*0.5
		"byrnie": skirt = float(f.leg_len)*0.2
		"scale": skirt = float(f.leg_len)*0.16
		"lamellar": skirt = float(f.leg_len)*0.42
		"scrap": skirt = 1.5
	cv.begin()
	cv.poly(_female_body(f,skirt,true),m["base"],_female_armor_pat(f,kind,m))
	if kind == "scrap":
		var seed: int = absi(int(f.spec.get("seed",0)))
		for i in 6:
			var row: int = int(i / 2)
			var y: float = 0.65+float(row)*(length+0.4)/3.0
			var x: float = -1.88 if i%2==0 else -0.02
			var pw: float = 1.65 if row!=1 else 1.39
			var ph: float = (length+0.4)/3.0-0.1
			var tone: Color = (m["base"] as Color).lerp(m["light"] if (i+seed)%3==0 else m["dark"],0.35)
			cv.poly(PackedVector2Array([_tp(f,x,y),_tp(f,x+pw,y-0.14),_tp(f,x+pw-0.15,y+ph),_tp(f,x+0.1,y+ph+0.08)]),tone)
			cv.capsule(_tp(f,x+0.1,y),_tp(f,x+pw-0.06,y-0.12),0.085,m["light"])
			cv.ellipse(_tp(f,x+0.28,y+0.2),0.11,0.11,m["shine"])
	if int(body.get("q",0))>=1:
		cv.capsule(_tp(f,-h-0.27,length+skirt-0.3),_tp(f,h+0.26,length+skirt-0.3),0.18,m["trim"])
	cv.end(m["outline"],0.07)
	if kind in ["mail","byrnie","lamellar","scrap"]:
		_female_belt(f,length*0.69,h*0.77,FigurePainter.LEATHER,m["trim"])
	if int(body.get("q",0))>=2:
		f._sparkle(_tp(f,1.5,1.0),m)
	return true

static func _female_belt(f, y: float, half: float, leather: Color, buckle: Color) -> void:
	var cv: PixelCanvas = f.cv
	cv.begin()
	cv.poly(PackedVector2Array([_tp(f,-half-0.06,y-0.24),_tp(f,half+0.06,y-0.19),
		_tp(f,half+0.06,y+0.31),_tp(f,-half-0.06,y+0.29)]),leather)
	cv.rect(Rect2(_tp(f,half-0.61,y-0.17),Vector2(0.52,0.45)),buckle)
	cv.end(FigurePainter.ol(leather),0.03)

static func _female_armor_pat(f, kind: String, m: Dictionary) -> Callable:
	if kind == "mail":
		return f._mail_pat(m)
	var dark: Color = m["dark"]
	var light: Color = m["light"]
	var lace: Color = f.sec
	var hip: Vector2 = f.j["hip"]
	var hip_y: int = floori(f.cv.map(hip).y)
	return func(x: int,y: int,c: Color) -> Color:
		if kind == "byrnie":
			return dark.lerp(c,0.35) if y%2==0 and (x+int(y/2))%2==0 else c
		if kind == "scale":
			var shift: int = int(y/2)%2
			if y%2==1: return dark if (x+shift)%2==0 else c
			return light if (x+shift)%2==1 else c
		if kind == "lamellar":
			if (y-hip_y)%3==0: return lace
			return dark.lerp(c,0.5) if x%2==0 else c
		return c

static func _wardrobe_p(f, x: float, y: float) -> Vector2:
	var length: float = float(f.torso_len)
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	return sc.lerp(hip,clampf(y/length,0.0,1.0))+Vector2(x,maxf(y-length,0.0))

static func _wardrobe_fit(f) -> Dictionary:
	var female: bool = String(f.spec.get("sex","")).to_lower() in ["female","f","woman"]
	var race: String = String(f.spec.get("race",""))
	var shoulder: float = float(f.tw)*(0.45 if female else 0.5)
	var waist: float = float(f.hipw)*(0.35 if female else 0.44)
	var belly: float = shoulder*0.84
	if race == "goblin":
		shoulder -= 0.22
		waist = float(f.hipw)*(0.30 if female else 0.35)
		belly = shoulder*0.79
	elif race == "troll":
		waist = float(f.hipw)*0.5
		belly = shoulder+0.25
	return {"shoulder":shoulder,"waist":waist,"belly":belly}

static func _wardrobe_shape(f, skirt: float, padded: bool = false) -> PackedVector2Array:
	var fit: Dictionary = _wardrobe_fit(f)
	var w: float = float(fit["shoulder"])+(0.17 if padded else 0.05)
	var waist: float = float(fit["waist"])+(0.17 if padded else 0.06)
	var belly: float = float(fit["belly"])+(0.16 if padded else 0.04)
	var length: float = float(f.torso_len)
	var hem: float = float(f.hipw)*0.48+0.25+float(f._spread())*0.42
	var neck: float = minf(w*0.4,1.55)
	return PackedVector2Array([_wardrobe_p(f,-w,0.55),_wardrobe_p(f,-neck,0.1),
		_wardrobe_p(f,-0.1,1.6),_wardrobe_p(f,neck,0.18),_wardrobe_p(f,w,0.7),
		_wardrobe_p(f,w+0.12,length*0.2),_wardrobe_p(f,belly,length*0.42),
		_wardrobe_p(f,waist,length*0.78),_wardrobe_p(f,waist+0.16,length),
		_wardrobe_p(f,hem,length+skirt-0.1),_wardrobe_p(f,0.53,length+skirt),
		_wardrobe_p(f,0.04,length+skirt*0.58),_wardrobe_p(f,-0.48,length+skirt-0.05),
		_wardrobe_p(f,-hem,length+skirt-0.18),_wardrobe_p(f,-waist-0.16,length),
		_wardrobe_p(f,-waist,length*0.78),_wardrobe_p(f,-belly,length*0.42),
		_wardrobe_p(f,-w-0.08,length*0.2)])

static func _wardrobe_cloth(f, item: Dictionary) -> Color:
	var color: Color = f._cloth_col()
	if String(item.get("mat","linen")) == "leather":
		color = color.lerp(FigurePainter.LEATHER,0.48)
	return color

static func _wardrobe_band(f, y: float, half: float, width: float, color: Color) -> void:
	var cv: PixelCanvas = f.cv
	cv.poly(PackedVector2Array([_wardrobe_p(f,-half,y-width*0.5),
		_wardrobe_p(f,half,y-width*0.42),_wardrobe_p(f,half,y+width*0.48),
		_wardrobe_p(f,-half,y+width*0.5)]),color)

static func _wardrobe_surface(f, kind: String, m: Dictionary, origin: Vector2) -> Callable:
	var cv: PixelCanvas = f.cv
	var inverse: Transform2D = cv.xf.affine_inverse()
	var dark: Color = m["dark"]
	var light: Color = m["light"]
	var lace: Color = f.sec
	var size: float = clampf(float(f.gs),0.8,1.5)
	return func(x: int, y: int, color: Color) -> Color:
		var p: Vector2 = (inverse*Vector2(float(x)+0.5,float(y)+0.5)-origin)/size
		if kind == "lamellar":
			var row: int = floori(p.y/1.45)
			var u: float = fposmod(p.x+float(posmod(row,2))*0.36,0.88)
			var v: float = fposmod(p.y,1.45)
			if v > 1.16: return dark.lerp(color,0.34)
			if u < 0.13: return dark.lerp(color,0.35)
			if v < 0.17: return light.lerp(color,0.3)
			if v > 0.65 and v < 0.84 and u > 0.21 and u < 0.4:
				return lace.darkened(0.18)
		elif kind == "scale":
			var row: int = floori(p.y/1.0)
			var u: float = fposmod(p.x+float(posmod(row,2))*0.67,1.34)-0.67
			var v: float = fposmod(p.y,1.0)
			var edge: float = 0.77-absf(u)*0.46
			if absf(v-edge) < 0.13: return dark.lerp(color,0.25)
			if v < 0.16 and absf(u) < 0.39: return light.lerp(color,0.32)
		else:
			var row: int = floori(p.y/0.8)
			var u: float = fposmod(p.x+float(posmod(row,2))*0.42,0.84)-0.42
			var v: float = fposmod(p.y,0.8)-0.4
			var ring: float = Vector2(u,v).length()
			if ring < 0.16: return dark.lerp(color,0.3)
			if ring > 0.27 and ring < 0.39 and v < -0.05:
				return light.lerp(color,0.38)
		return color

static func _wardrobe_torso(f) -> bool:
	var cv: PixelCanvas = f.cv
	var fit: Dictionary = _wardrobe_fit(f)
	var w: float = float(fit["shoulder"])
	var waist: float = float(fit["waist"])
	var length: float = float(f.torso_len)
	var clothing: Dictionary = f._it("clothing")
	var body: Dictionary = f._it("body")
	var sc: Vector2 = f.j["sc"]
	# The opening stays below the existing native neck.
	cv.begin()
	cv.poly(PackedVector2Array([_wardrobe_p(f,-w*0.4,0.18),_wardrobe_p(f,w*0.4,0.18),
		_wardrobe_p(f,-0.1,1.8)]),f.skin)
	f._skin_end()
	if not clothing.is_empty():
		var padded: bool = String(clothing.get("tid","")) == "gambeson"
		var cloth: Color = _wardrobe_cloth(f,clothing)
		var trim: Color = f.sec
		var skirt: float = float(f.leg_len)*(0.31 if padded else 0.28)
		var hem: float = float(f.hipw)*0.48+0.25+float(f._spread())*0.42
		cv.begin()
		cv.poly(_wardrobe_shape(f,skirt,padded),cloth)
		cv.poly(PackedVector2Array([_wardrobe_p(f,-w,0.55),_wardrobe_p(f,-w*0.4,0.18),
			_wardrobe_p(f,-w*0.3,length*0.4),_wardrobe_p(f,-waist*0.25,length),
			_wardrobe_p(f,-hem,length+skirt-0.18),_wardrobe_p(f,-waist,length*0.78),
			_wardrobe_p(f,-float(fit["belly"]),length*0.42)]),cloth.darkened(0.24))
		cv.poly(PackedVector2Array([_wardrobe_p(f,0.15,1.85),_wardrobe_p(f,w*0.8,1.4),
			_wardrobe_p(f,waist*0.65,length*0.73),_wardrobe_p(f,0.35,length*0.75)]),cloth.lightened(0.16))
		if padded:
			for i: int in range(5):
				var t: float = (float(i)-2.0)/2.5
				var top: Vector2 = _wardrobe_p(f,w*t,length*0.27)
				var bottom: Vector2 = _wardrobe_p(f,waist*t,length*0.92)
				cv.capsule(top,bottom,0.11,cloth.darkened(0.28))
				cv.capsule(top+Vector2(0.17,0.0),bottom+Vector2(0.17,0.0),0.10,cloth.lightened(0.12))
			_wardrobe_band(f,length*0.49,float(fit["belly"])*0.9,0.15,cloth.darkened(0.16))
			for i: int in range(4):
				var x: float = (float(i)-1.5)*hem*0.45
				cv.capsule(_wardrobe_p(f,x*0.75,length+0.18),
					_wardrobe_p(f,x,length+skirt-0.35),0.1,cloth.darkened(0.25))
		else:
			cv.capsule(_wardrobe_p(f,-waist*0.55,length*0.85),
				_wardrobe_p(f,-hem*0.69,length+skirt-0.4),0.14,cloth.lightened(0.18))
			cv.capsule(_wardrobe_p(f,waist*0.42,length*0.91),
				_wardrobe_p(f,hem*0.6,length+skirt-0.32),0.17,cloth.darkened(0.29))
			cv.capsule(_wardrobe_p(f,0.0,1.7),_wardrobe_p(f,0.05,2.65),0.12,cloth.darkened(0.38))
		cv.capsule(_wardrobe_p(f,-minf(w*0.4,1.55),0.12),_wardrobe_p(f,-0.1,1.6),0.18,trim)
		cv.capsule(_wardrobe_p(f,-0.1,1.6),_wardrobe_p(f,minf(w*0.4,1.55),0.18),0.18,trim)
		cv.capsule(_wardrobe_p(f,-hem+0.1,length+skirt-0.37),
			_wardrobe_p(f,-0.48,length+skirt-0.23),0.17,trim.darkened(0.1))
		cv.capsule(_wardrobe_p(f,0.53,length+skirt-0.18),
			_wardrobe_p(f,hem-0.1,length+skirt-0.28),0.17,trim.darkened(0.1))
		_wardrobe_band(f,length*0.81,waist+0.08,0.48,trim.darkened(0.18))
		cv.end(FigurePainter.ol(cloth),0.06)
	if body.is_empty():
		return true
	var kind: String = String(body.get("sprite",""))
	var m: Dictionary = FigurePainter.metal(String(body.get("mat","copper")),int(body.get("q",0)))
	var skirt: float = float(f.leg_len)*0.13
	match kind:
		"mail": skirt = float(f.leg_len)*0.38
		"byrnie": skirt = float(f.leg_len)*0.17
		"lamellar": skirt = float(f.leg_len)*0.32
		"scrap": skirt = float(f.leg_len)*0.07
	var pat: Callable = _wardrobe_surface(f,kind,m,sc)
	var base: Color = m["base"]
	cv.begin()
	cv.poly(_wardrobe_shape(f,skirt),FigurePainter.LEATHER.darkened(0.15) if kind == "scrap" else base,
		Callable() if kind == "scrap" else pat)
	if kind == "scrap":
		var seed: int = absi(int(f.spec.get("seed",0)))
		var neck: float = minf(w*0.4,1.55)
		var edge: Color = (m["outline"] as Color).lerp(m["dark"],0.32)
		for row: int in range(3):
			var y: float = 0.55 if row == 0 else length*(0.39+float(row-1)*0.29)
			var bottom: float = length*0.4 if row == 0 else y+length*0.3+0.08
			var half: float = w*0.95 if row == 0 else lerpf(float(fit["belly"])*0.94,waist*0.99,float(row-1)*0.76)
			var lower_half: float = float(fit["belly"])*0.92 if row == 0 else lerpf(float(fit["belly"])*0.92,waist*0.98,clampf((bottom/length-0.42)/0.36,0.0,1.0))
			var seam: float = 0.04 if row == 0 else (-0.17 if row == 1 else 0.12)
			for column: int in range(2):
				var points: PackedVector2Array
				if row == 0 and column == 0:
					points = PackedVector2Array([_wardrobe_p(f,-half,0.73),
						_wardrobe_p(f,-neck-0.1,0.31),_wardrobe_p(f,-0.36,1.82),
						_wardrobe_p(f,seam,bottom-0.08),_wardrobe_p(f,-lower_half,bottom+0.04),
						_wardrobe_p(f,-half*0.98,length*0.22)])
				elif row == 0:
					points = PackedVector2Array([_wardrobe_p(f,neck-0.03,0.34),
						_wardrobe_p(f,half,0.84),_wardrobe_p(f,half*0.98,length*0.23),
						_wardrobe_p(f,lower_half,bottom+0.05),
						_wardrobe_p(f,seam+0.48,bottom-0.04),_wardrobe_p(f,0.08,1.87)])
				elif column == 0:
					points = PackedVector2Array([_wardrobe_p(f,-half,y+0.06),
						_wardrobe_p(f,seam-0.24,y-0.04),_wardrobe_p(f,seam+0.02,bottom-0.16),
						_wardrobe_p(f,-lower_half,bottom+0.02)])
				else:
					points = PackedVector2Array([_wardrobe_p(f,seam+0.19,y+0.1),
						_wardrobe_p(f,half,y-0.08),_wardrobe_p(f,lower_half,bottom-0.04),
						_wardrobe_p(f,seam+0.43,bottom-0.09)])
				# Side planes and the leather gaps make each fitted plate distinct.
				var variation: float = float(posmod(seed+row,3))*0.025
				var tone: Color = base.lerp(m["dark"],0.4+variation) if column == 0 else base.lerp(m["light"],0.08+variation)
				cv.poly(points,tone)
				for index: int in range(points.size()):
					cv.capsule(points[index],points[(index+1)%points.size()],0.125,edge)
				cv.capsule(points[0]+Vector2(0.08,0.1),points[1]+Vector2(-0.06,0.1),0.10,m["light"])
				if row == 0:
					var rivet: Vector2 = _wardrobe_p(f,-half+0.43,1.0) if column == 0 else _wardrobe_p(f,half-0.42,1.14)
					cv.ellipse(rivet,0.2,0.2,m["dark"])
					cv.ellipse(rivet+Vector2(-0.04,-0.04),0.12,0.12,m["shine"])
					var inner_rivet: Vector2 = _wardrobe_p(f,-0.52,2.15) if column == 0 else _wardrobe_p(f,0.42,2.19)
					cv.ellipse(inner_rivet,0.16,0.16,m["trim"])
				else:
					var rivet_x: float = -half+0.37 if column == 0 else half-0.35
					cv.ellipse(_wardrobe_p(f,rivet_x,y+0.35),0.16,0.16,m["shine"])
		# The chest strap holds the plate pair to its leather backing.
		cv.capsule(_wardrobe_p(f,-w*0.58,0.6),_wardrobe_p(f,waist*0.44,length*0.73),
			0.25,FigurePainter.LEATHER.darkened(0.18))
		cv.capsule(_wardrobe_p(f,-w*0.58+0.1,0.66),_wardrobe_p(f,waist*0.44+0.08,length*0.73),
			0.075,FigurePainter.LEATHER.lightened(0.12))
		cv.ellipse(_wardrobe_p(f,-w*0.45,1.2),0.16,0.16,m["trim"])

	elif kind == "lamellar":
		for row: int in range(1,4):
			var y: float = length*float(row)*0.26
			var half: float = lerpf(w,waist,minf(float(row)*0.29,1.0))*0.92
			_wardrobe_band(f,y,half,0.16,m["dark"])
	else:
		cv.poly(PackedVector2Array([_wardrobe_p(f,-w,0.65),_wardrobe_p(f,-w*0.55,1.1),
			_wardrobe_p(f,-waist*0.5,length*0.74),_wardrobe_p(f,-waist,length*0.8),
			_wardrobe_p(f,-float(fit["belly"]),length*0.42)]),base.darkened(0.17),pat)
	cv.capsule(_wardrobe_p(f,-minf(w*0.4,1.55),0.15),_wardrobe_p(f,-0.1,1.6),0.16,m["dark"])
	cv.capsule(_wardrobe_p(f,-0.1,1.6),_wardrobe_p(f,minf(w*0.4,1.55),0.2),0.16,m["light"])
	if int(body.get("q",0)) >= 1:
		var hem: float = float(f.hipw)*0.48+0.25+float(f._spread())*0.42
		cv.capsule(_wardrobe_p(f,-hem+0.1,length+skirt-0.36),
			_wardrobe_p(f,-0.48,length+skirt-0.22),0.14,m["trim"])
		cv.capsule(_wardrobe_p(f,0.53,length+skirt-0.17),
			_wardrobe_p(f,hem-0.1,length+skirt-0.26),0.14,m["trim"])
	cv.end(m["outline"],0.06,m["shine"])
	if kind in ["mail","byrnie","lamellar","scrap"]:
		cv.begin()
		_wardrobe_band(f,length*0.81,waist+0.12,0.54,FigurePainter.LEATHER)
		cv.poly(PackedVector2Array([_wardrobe_p(f,waist*0.46,length*0.81-0.21),
			_wardrobe_p(f,waist*0.46+0.57,length*0.81-0.21),
			_wardrobe_p(f,waist*0.46+0.57,length*0.81+0.21),
			_wardrobe_p(f,waist*0.46,length*0.81+0.21)]),m["trim"])
		cv.end(FigurePainter.ol(FigurePainter.LEATHER),0.025)
	if int(body.get("q",0)) >= 2:
		f._sparkle(_wardrobe_p(f,w*0.7,1.15),m)
	return true

static func _wardrobe_sleeve(f, side: String, sh: Vector2, el: Vector2, r: float) -> void:
	var cv: PixelCanvas = f.cv
	var clothing: Dictionary = f._it("clothing")
	var body: Dictionary = f._it("body")
	var direction: Vector2 = (el-sh).normalized()
	var normal: Vector2 = Vector2(direction.y,-direction.x)
	if not clothing.is_empty():
		var padded: bool = String(clothing.get("tid","")) == "gambeson"
		var color: Color = _wardrobe_cloth(f,clothing)
		var endp: Vector2 = sh.lerp(el,0.78 if padded else 0.67)
		var radius: float = r*(1.19 if padded else 1.1)
		cv.begin()
		_limb(cv,sh,endp,radius,r*(1.01 if padded else 0.87),color)
		cv.capsule(endp-normal*r*0.85,endp+normal*r*0.85,0.17,f.sec.darkened(0.08))
		if padded:
			for index: int in range(3):
				var offset: float = float(index-1)*r*0.5
				cv.capsule(sh.lerp(el,0.15)+normal*offset,endp+normal*offset*0.85,0.095,color.darkened(0.25))
		else:
			cv.capsule(sh.lerp(el,0.4)-normal*r*0.55,sh.lerp(el,0.55)+normal*r*0.5,0.13,color.darkened(0.2))
		cv.end(FigurePainter.ol(color),0.05)
	if body.is_empty():
		return
	var kind: String = String(body.get("sprite",""))
	var m: Dictionary = FigurePainter.metal(String(body.get("mat","copper")),int(body.get("q",0)))
	var base: Color = m["base"]
	if side == "l": base = base.darkened(0.1)
	if kind in ["mail","byrnie"]:
		var endp: Vector2 = el if kind == "mail" else sh.lerp(el,0.57)
		cv.begin()
		cv.capsule(sh,endp,r*1.12,base,_wardrobe_surface(f,"mail",m,sh))
		cv.capsule(endp-normal*r,endp+normal*r,0.14,m["dark"])
		cv.end(m["outline"],0.055,m["shine"])
	elif kind == "scrap" or (kind == "lamellar" and String(body.get("tid","")) == "steppe_lamellar"):
		var cap_end: Vector2 = sh.lerp(el,0.36 if side == "r" else 0.23)
		cv.begin()
		cv.poly(PackedVector2Array([sh-direction*r*0.5-normal*r*1.03,sh-direction*r*0.4+normal*r*1.04,
			sh.lerp(cap_end,0.65)+normal*r*1.2,cap_end+normal*r*0.9,
			cap_end-normal*r*0.88,sh.lerp(cap_end,0.65)-normal*r*1.14]),base,
			_wardrobe_surface(f,kind,m,sh) if kind == "lamellar" else Callable())
		cv.capsule(sh-normal*r*0.85,sh+normal*r*0.83,0.14,m["light"])
		cv.capsule(cap_end-normal*r*0.8,cap_end+normal*r*0.8,0.16,m["dark"])
		cv.ellipse(sh+normal*r*0.65+direction*0.15,0.13,0.13,m["shine"])
		cv.end(m["outline"],0.06,m["shine"])

static func _wardrobe_bracer(f, side: String, el: Vector2, hand: Vector2, r: float) -> void:
	var item: Dictionary = f._it("hands")
	if item.is_empty() or f._lost("arm_lower_"+side):
		return
	var cv: PixelCanvas = f.cv
	var m: Dictionary = FigurePainter.metal(String(item.get("mat","copper")),int(item.get("q",0)))
	var kind: String = String(item.get("tid",""))
	var direction: Vector2 = (hand-el).normalized()
	var normal: Vector2 = Vector2(direction.y,-direction.x)
	if kind == "arm_rings":
		cv.begin()
		for t: float in [0.46,0.74]:
			var center: Vector2 = el.lerp(hand,t)
			cv.capsule(center-normal*r*0.87,center+normal*r*0.87,0.23,m["base"])
			cv.capsule(center-normal*r*0.6-direction*0.08,center+normal*r*0.35-direction*0.08,0.1,m["light"])
		cv.end(m["outline"],0.03)
		return
	var start: Vector2 = el.lerp(hand,0.27 if kind == "crude_bracers" else 0.14)
	var endp: Vector2 = el.lerp(hand,0.81)
	var base: Color = m["base"]
	cv.begin()
	cv.poly(PackedVector2Array([start-normal*r,start-direction*r*0.15,
		start+normal*r*1.02,endp+normal*r*0.73,endp+direction*r*0.13,endp-normal*r*0.75]),base)
	cv.poly(PackedVector2Array([start-normal*r*0.2,start+normal*r*0.34,
		endp+normal*r*0.25,endp-normal*r*0.12]),m["light"].lerp(base,0.4))
	cv.capsule(start-normal*r*0.92,endp-normal*r*0.67,0.12,m["dark"])
	for t: float in [0.23,0.78]:
		var center: Vector2 = start.lerp(endp,t)
		cv.capsule(center-normal*r*0.86,center+normal*r*0.87,0.17,FigurePainter.LEATHER.darkened(0.08))
		cv.ellipse(center+normal*r*0.58,0.12,0.12,m["trim"])
	if kind == "crude_bracers":
		cv.capsule(start+normal*r*0.3,endp+normal*r*0.16,0.14,m["dark"])
	if kind.contains("gauntlet") and not f._lost("hand_"+side):
		cv.ellipse(hand,r+0.25,r+0.25,base)
		cv.capsule(hand+Vector2(-r*0.45,-r*0.35),hand+Vector2(r*0.45,-r*0.3),0.17,m["light"])
	cv.end(m["outline"],0.055,m["shine"])

static func _wardrobe_leg_layers(f, side: String, hp: Vector2, kn: Vector2, ft: Vector2, r: float) -> void:
	var cv: PixelCanvas = f.cv
	var trousers: Dictionary = f._it("legs_under")
	var greaves: Dictionary = f._it("legs")
	var shoes: Dictionary = f._it("feet")
	var lower_lost: bool = f._lost("leg_lower_"+side)
	var foot_lost: bool = f._lost("foot_"+side)
	var direction: Vector2 = (kn-hp).normalized()
	var normal: Vector2 = Vector2(direction.y,-direction.x)
	if not trousers.is_empty():
		var color: Color = f._trouser_col()
		if side == "l": color = color.darkened(0.1)
		cv.begin()
		cv.capsule(hp+normal*r*0.5,kn+normal*r*0.36,0.10,color.darkened(0.24))
		cv.capsule(kn-direction*r*0.48-normal*r*0.55,kn-direction*r*0.18+normal*r*0.43,0.13,color.lightened(0.2))
		if not lower_lost:
			var shin_dir: Vector2 = (ft-kn).normalized()
			var shin_normal: Vector2 = Vector2(shin_dir.y,-shin_dir.x)
			cv.capsule(kn+shin_normal*r*0.3,ft+shin_normal*r*0.22,0.1,color.darkened(0.24))
			var cuff: Vector2 = kn.lerp(ft,0.91)
			cv.capsule(cuff-shin_normal*r*0.48,cuff+shin_normal*r*0.5,0.18,color.darkened(0.2))
		cv.end(Color(0,0,0,0),0.0)
	if lower_lost:
		return
	if not shoes.is_empty() and not foot_lost:
		var tid: String = String(shoes.get("tid",""))
		var mat: String = String(shoes.get("mat","leather"))
		var leather: Color = FigurePainter.LEATHER.darkened(0.2)
		var q: int = int(shoes.get("q",0))
		var m: Dictionary = FigurePainter.metal(mat,q)
		var metallic: bool = mat in ["copper","tin","iron","steel","bronze","silver","gold"]
		var color: Color = m["base"] if metallic else leather
		var length: float = 3.4*float(f.gs)
		var ankle: Vector2 = kn.lerp(ft,0.64 if tid.contains("boot") else 0.91)
		var shin_dir: Vector2 = (ft-kn).normalized()
		var shin_normal: Vector2 = Vector2(shin_dir.y,-shin_dir.x)
		cv.begin()
		# Footwear covers the complete native foot, including its heel and sole corners.
		var race: String = String(f.spec.get("race",""))
		if race == "orc":
			cv.rect(Rect2(ft+Vector2(-1.2,-0.5),Vector2(3.4*float(f.gs),2.0)),color)
		elif race == "goblin":
			cv.poly(PackedVector2Array([ft+Vector2(-0.8,-0.45),ft+Vector2(0.45,-0.58),
				ft+Vector2(0.9,0.0),ft+Vector2(2.1,0.56),ft+Vector2(2.25,1.3),
				ft+Vector2(0.45,1.45),ft+Vector2(-1.0,1.07)]),color)
		elif race == "troll":
			cv.poly(PackedVector2Array([ft+Vector2(-1.35,-0.65),ft+Vector2(0.6,-0.65),
				ft+Vector2(length-1.0,0.05),ft+Vector2(length-0.55,0.7),
				ft+Vector2(length-0.9,1.35),ft+Vector2(-1.45,1.25)]),color)
			cv.ellipse(ft+Vector2(-0.3,-0.25),r*0.63,r*0.45,color)
		cv.poly(PackedVector2Array([ankle-shin_normal*r*0.65,ankle+shin_normal*r*0.66,
			ft+Vector2(0.9,-0.55),ft+Vector2(length-0.5,0.22),
			ft+Vector2(length-0.35,1.08),ft+Vector2(length-0.72,1.48),
			ft+Vector2(-1.43,1.4),ft+Vector2(-1.48,0.1)]),color)
		cv.capsule(ft+Vector2(-0.3,-0.24),ft+Vector2(length-1.13,0.44),0.18,color.lightened(0.2 if q>0 else 0.13))
		cv.capsule(ft+Vector2(-1.22,1.17),ft+Vector2(length-0.63,1.22),0.19,color.darkened(0.34))
		cv.capsule(ankle-shin_normal*r*0.58,ankle+shin_normal*r*0.6,0.13,color.darkened(0.28))
		cv.capsule(ft+Vector2(0.32,-0.28),ft+Vector2(0.85,0.44),0.1,color.darkened(0.3))
		cv.end(m["outline"] if metallic else FigurePainter.ol(color),0.04)
	if not greaves.is_empty():
		var m: Dictionary = FigurePainter.metal(String(greaves.get("mat","copper")),int(greaves.get("q",0)))
		var tid: String = String(greaves.get("tid",""))
		var direction2: Vector2 = (ft-kn).normalized()
		var normal2: Vector2 = Vector2(direction2.y,-direction2.x)
		var start: Vector2 = kn.lerp(ft,0.11)
		var endp: Vector2 = kn.lerp(ft,0.89)
		cv.begin()
		cv.poly(PackedVector2Array([start-normal2*r*0.9,start-direction2*r*0.22,
			start+normal2*r*0.91,endp+normal2*r*0.59,endp+direction2*r*0.18,endp-normal2*r*0.6]),m["base"])
		cv.poly(PackedVector2Array([start-normal2*r*0.15,start+normal2*r*0.25,
			endp+normal2*r*0.17,endp-normal2*r*0.08]),m["light"].lerp(m["base"],0.35))
		if tid == "splint_greaves":
			for i: int in range(3):
				var offset: float = float(i-1)*r*0.44
				cv.capsule(start+normal2*offset,endp+normal2*offset*0.65,0.1,m["dark"])
		for t: float in [0.18,0.79]:
			var center: Vector2 = start.lerp(endp,t)
			var width: float = lerpf(r*0.85,r*0.62,t)
			cv.capsule(center-normal2*width,center+normal2*width,0.16,FigurePainter.LEATHER.darkened(0.1))
			cv.ellipse(center+normal2*width*0.67,0.11,0.11,m["trim"])
		cv.end(m["outline"],0.055,m["shine"])
