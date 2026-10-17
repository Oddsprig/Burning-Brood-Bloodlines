class_name TrollArt
extends RefCounted
## Troll surfaces on the original FigurePainter joints. The long skull, low jaw,
## hanging chest and weighty forearms distinguish the troll without changing its rig.
## Actual look colors, hair seed and equipment are retained; wounds belong to the caller.

static func _poly(cv: PixelCanvas, origin: Vector2, points: Array, color: Color) -> void:
	var vertices: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		vertices.append(origin + point)
	cv.poly(vertices, color)

static func head(f) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var dark: Color = skin.darkened(0.34)
	var deep: Color = skin.darkened(0.66).lerp(Color("#20251b"), 0.18)
	var light: Color = skin.lightened(0.22)
	var seed: int = absi(int(f.spec.get("seed", 0)))
	var dead: bool = String(f.pose) == "dead" or bool(f.spec.get("dead", false))
	var chin: float = 0.08 * float(seed % 3)
	var has_nose: bool = not f._lost("nose")
	# Wide neck sinks behind the chin. Its endpoints never move the shoulder/head centers.
	cv.begin()
	_poly(cv, hc, [Vector2(-3.25, 1.15), Vector2(-0.2, 2.0), Vector2(2.0, 3.1),
		Vector2(2.0, 4.4), Vector2(-3.4, 4.05), Vector2(-4.2, 2.5)], dark)
	_poly(cv, hc, [Vector2(-1.35, 2.45), Vector2(0.9, 3.05), Vector2(1.4, 4.05),
		Vector2(-0.9, 3.7)], skin)
	f._skin_end()
	# Narrow high rear crown slopes all the way to a low brow; the muzzle hangs below it.
	cv.begin()
	_poly(cv, hc, [Vector2(-4.0, -1.65), Vector2(-3.45, -3.45), Vector2(-2.15, -4.1),
		Vector2(-0.3, -3.9), Vector2(1.0, -3.15), Vector2(2.0, -2.0),
		Vector2(2.8, -1.4), Vector2(3.4 if has_nose else 3.05, -0.8), Vector2(4.75 if has_nose else 3.05, -0.1),
		Vector2(4.95 if has_nose else 3.1, 0.75), Vector2(4.4, 1.25), Vector2(4.95, 2.15),
		Vector2(4.85 + chin, 3.2), Vector2(3.45, 3.85), Vector2(0.6, 3.55),
		Vector2(-2.5, 2.1), Vector2(-4.15, 0.3)], skin)
	_poly(cv, hc, [Vector2(-4.0, -1.65), Vector2(-3.45, -3.45), Vector2(-2.25, -2.45),
		Vector2(-1.9, -0.55), Vector2(-2.45, 0.7), Vector2(-0.35, 2.65),
		Vector2(0.6, 3.55), Vector2(-2.5, 2.1), Vector2(-4.15, 0.3)], dark)
	_poly(cv, hc, [Vector2(-3.45, -3.45), Vector2(-2.15, -4.1), Vector2(-0.3, -3.9),
		Vector2(1.0, -3.15), Vector2(1.65, -2.25), Vector2(0.4, -2.45),
		Vector2(-1.2, -3.2), Vector2(-2.65, -3.1)], light)
	_poly(cv, hc, [Vector2(-1.95, -2.4), Vector2(-0.6, -2.7), Vector2(0.7, -2.0),
		Vector2(1.65, -1.6), Vector2(-0.1, -1.4), Vector2(-1.7, -1.2)], skin.lightened(0.1))
	# Dense, overhanging brow shields small sockets instead of a human eyebrow.
	_poly(cv, hc, [Vector2(-1.45, -1.4), Vector2(-0.4, -1.95), Vector2(1.2, -1.8),
		Vector2(2.8, -1.4), Vector2(3.25, -0.9), Vector2(1.3, -0.75),
		Vector2(-0.6, -0.95)], skin.darkened(0.23))
	_poly(cv, hc, [Vector2(-1.45, -1.4), Vector2(-0.4, -1.95), Vector2(1.2, -1.8),
		Vector2(2.65, -1.4), Vector2(1.6, -1.25), Vector2(-0.25, -1.35)], light)
	# Broad flattened nose has two nostril wings and a low nasal bridge.
	if has_nose:
		_poly(cv, hc, [Vector2(2.25, -1.1), Vector2(3.2, -0.85), Vector2(3.65, -0.5),
			Vector2(4.75, -0.1), Vector2(4.95, 0.75), Vector2(4.05, 1.0),
			Vector2(2.7, 0.65), Vector2(2.1, 0.15)], skin.lightened(0.11))
		_poly(cv, hc, [Vector2(2.7, 0.65), Vector2(4.05, 1.0), Vector2(4.95, 0.75),
			Vector2(4.4, 1.25), Vector2(3.1, 1.15), Vector2(2.5, 0.95)], dark)
	# Hollow cheek meets a very low protruding mandible with a fleshy chin plane.
	_poly(cv, hc, [Vector2(-1.3, 0.15), Vector2(0.8, 0.35), Vector2(2.1, 0.15),
		Vector2(2.2, 1.0), Vector2(0.3, 1.7), Vector2(-1.3, 1.15)], skin.lightened(0.12))
	_poly(cv, hc, [Vector2(-1.3, 1.15), Vector2(0.3, 1.7), Vector2(2.45, 1.45),
		Vector2(4.4, 1.25), Vector2(4.95, 2.15), Vector2(4.85 + chin, 3.2),
		Vector2(3.45, 3.85), Vector2(0.6, 3.55), Vector2(-0.6, 2.7)], skin.darkened(0.14))
	_poly(cv, hc, [Vector2(0.6, 2.55), Vector2(2.6, 2.7), Vector2(4.65, 2.35),
		Vector2(4.5, 3.05), Vector2(3.4, 3.45), Vector2(1.3, 3.2)], skin.lightened(0.1))
	f._skin_end()
	if not f._lost("ear_l") and String(f._it("helm").get("sprite", "")) != "coif":
		cv.begin()
		_poly(cv, hc, [Vector2(-3.0, -0.7), Vector2(-4.65, -1.05), Vector2(-4.5, 0.4),
			Vector2(-3.5, 1.15), Vector2(-2.8, 0.4)], skin)
		_poly(cv, hc, [Vector2(-3.5, -0.3), Vector2(-4.15, -0.55), Vector2(-4.0, 0.25),
			Vector2(-3.55, 0.5)], dark)
		f._skin_end()
	_hair(f, hc, seed)
	_eye(cv, hc + Vector2(-0.65, -0.5), 0.8, skin, deep, dead, f._lost("eye_l"))
	_eye(cv, hc + Vector2(1.1, -0.38), 1.18, skin, deep, dead, f._lost("eye_r"))
	if has_nose:
		_poly(cv, hc, [Vector2(2.9, 0.47), Vector2(3.45, 0.46), Vector2(3.35, 0.75),
			Vector2(2.95, 0.75)], deep)
		_poly(cv, hc, [Vector2(4.1, 0.48), Vector2(4.65, 0.36), Vector2(4.6, 0.67),
			Vector2(4.15, 0.78)], deep)
	_poly(cv, hc, [Vector2(0.8, 1.55), Vector2(2.8, 1.7), Vector2(4.65, 1.45),
		Vector2(4.5, 1.9), Vector2(2.75, 2.1), Vector2(1.0, 1.95)], deep)
	_poly(cv, hc, [Vector2(1.1, 2.08), Vector2(2.85, 2.2), Vector2(4.35, 1.95),
		Vector2(4.2, 2.2), Vector2(2.75, 2.48), Vector2(1.3, 2.3)], skin.lightened(0.14))
	if bool(f.spec.get("beard", false)):
		var hair: Color = f.hair
		cv.begin()
		_poly(cv, hc, [Vector2(-1.5, 1.5), Vector2(-0.75, 2.0), Vector2(0.3, 3.15),
			Vector2(3.5, 3.55), Vector2(3.8, 3.85), Vector2(2.45, 4.25),
			Vector2(1.55, 3.85), Vector2(0.75, 4.0), Vector2(-0.65, 3.1)], hair)
		_poly(cv, hc, [Vector2(-0.9, 2.0), Vector2(0.5, 3.15), Vector2(2.65, 3.7),
			Vector2(1.7, 3.8), Vector2(0.2, 3.4)], hair.lightened(0.18))
		cv.end(FigurePainter.ol(hair), 0.05)
	_tusk(cv, hc + Vector2(1.2, 2.55), 0.7, 2.45, false)
	_tusk(cv, hc + Vector2(4.2, 2.55), 0.98, 3.05, true)
	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5,
		-float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _eye(cv: PixelCanvas, o: Vector2, width: float, skin: Color, deep: Color,
		dead: bool, lost: bool) -> void:
	_poly(cv, o, [Vector2(-0.2, -0.25), Vector2(width, -0.12), Vector2(width + 0.15, 0.42),
		Vector2(0.05, 0.55), Vector2(-0.35, 0.2)], deep)
	if lost:
		return
	if dead:
		cv.capsule(o + Vector2(0.05, 0.12), o + Vector2(width, 0.18), 0.1, skin.darkened(0.35))
		return
	cv.rect(Rect2(o + Vector2(0.18, 0.08), Vector2(width * 0.6, 0.32)), Color("#d9761d"))
	cv.rect(Rect2(o + Vector2(width * 0.47, 0.08), Vector2(0.26, 0.18)), Color("#ffba46"))
	cv.rect(Rect2(o + Vector2(width * 0.64, 0.11), Vector2(0.14, 0.25)), deep)

static func _hair(f, hc: Vector2, seed: int) -> void:
	# Troll appearance has only bald/tuft choices. Preserve that sparse silhouette.
	if seed % 2 == 0 or not f._it("helm").is_empty():
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	cv.begin()
	_poly(cv, hc, [Vector2(-3.15, -3.5), Vector2(-3.5, -4.35), Vector2(-2.85, -4.0),
		Vector2(-2.65, -4.9), Vector2(-2.1, -4.2), Vector2(-1.6, -4.6),
		Vector2(-1.2, -3.9), Vector2(-0.6, -3.6), Vector2(-1.85, -3.65)], hair)
	_poly(cv, hc, [Vector2(-2.65, -4.5), Vector2(-2.2, -4.0), Vector2(-1.2, -3.9),
		Vector2(-1.7, -3.75), Vector2(-2.6, -3.85)], hair.lightened(0.2))
	cv.end(FigurePainter.ol(hair), 0.04)

static func _tusk(cv: PixelCanvas, o: Vector2, width: float, height: float, near: bool) -> void:
	# An uneven inward elbow and outward hooked tip read as tusks rather than horns.
	var ivory: Color = Color("#eee0b6") if near else Color("#cdbf96")
	cv.begin()
	_poly(cv, o, [Vector2(-width * 0.5, 0.0), Vector2(width * 0.5, 0.05),
		Vector2(width * 0.35, -height * 0.48), Vector2(width * 0.05, -height * 0.73),
		Vector2(width * 0.4, -height), Vector2(-width * 0.14, -height * 0.84),
		Vector2(-width * 0.5, -height * 0.55)], Color("#a59a76"))
	_poly(cv, o, [Vector2(-width * 0.15, -0.15), Vector2(width * 0.27, -0.18),
		Vector2(width * 0.12, -height * 0.49), Vector2(-width * 0.03, -height * 0.7),
		Vector2(width * 0.4, -height), Vector2(-width * 0.17, -height * 0.79),
		Vector2(-width * 0.28, -height * 0.5)], ivory)
	cv.end(Color("#514d37"), 0.02)

static func torso(f) -> bool:
	var cv: PixelCanvas = f.cv
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var half: float = float(f.tw) * 0.5
	var waist: float = float(f.hipw) * 0.5
	var skin: Color = f.skin
	var middle: Vector2 = sc.lerp(hip, 0.48)
	cv.begin()
	cv.poly(PackedVector2Array([sc + Vector2(-half, 0.6), sc + Vector2(-half * 0.58, -0.55),
		sc + Vector2(half * 0.35, -0.5), sc + Vector2(half, 1.0),
		middle + Vector2(half + 0.25, 0.0), hip + Vector2(waist, 1.0),
		hip + Vector2(-waist, 1.0), middle + Vector2(-half - 0.25, 0.2)]), skin)
	cv.poly(PackedVector2Array([sc + Vector2(-half, 0.6), sc + Vector2(-half * 0.58, -0.55),
		middle + Vector2(-half * 0.4, 0.2), hip + Vector2(-0.65, 0.6),
		hip + Vector2(-waist, 1.0), middle + Vector2(-half - 0.25, 0.2)]), skin.darkened(0.28))
	cv.poly(PackedVector2Array([sc + Vector2(-0.65, 0.3), sc + Vector2(half * 0.35, -0.5),
		sc + Vector2(half, 1.0), middle + Vector2(half - 0.45, -0.1),
		middle + Vector2(0.2, 0.8), sc + Vector2(-0.85, 2.25)]), skin.lightened(0.17))
	cv.capsule(middle + Vector2(-0.35, 0.6), middle + Vector2(half - 0.7, 0.2), 0.16, skin.darkened(0.27))
	f._skin_end()
	if not f._it("body").is_empty() or not f._it("clothing").is_empty():
		return _wardrobe_torso(f)
	return true

static func _limb(cv: PixelCanvas, a: Vector2, b: Vector2, ra: float, rb: float, color: Color) -> void:
	var direction: Vector2 = (b - a).normalized()
	var normal: Vector2 = Vector2(direction.y, -direction.x)
	var middle: Vector2 = a.lerp(b, 0.48)
	cv.poly(PackedVector2Array([a - normal * ra, a + normal * ra,
		middle + normal * (ra * 1.08), b + normal * rb, b - normal * rb,
		middle - normal * (ra * 0.98)]), color)
	cv.ellipse(a, ra, ra, color)
	cv.ellipse(b, rb, rb, color)
	# Explicit light direction remains upper left when a limb rotates with its pose.
	cv.poly(PackedVector2Array([a + Vector2(-ra * 0.55, -ra * 0.3),
		a + Vector2(ra * 0.05, -ra * 0.75), middle + Vector2(ra * 0.1, -ra * 0.45),
		b + Vector2(-rb * 0.05, -rb * 0.4), b + Vector2(-rb * 0.35, -rb * 0.1),
		middle + Vector2(-ra * 0.4, -ra * 0.1)]), color.lightened(0.18))
	cv.capsule(a + Vector2(ra * 0.5, ra * 0.2), b + Vector2(rb * 0.45, rb * 0.15),
		minf(ra, rb) * 0.17, color.darkened(0.22))

static func arm(f, side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var shoulder: Vector2 = f.j["s" + side]
	var elbow: Vector2 = f.j["e" + side]
	var hand: Vector2 = f.j["h" + side]
	var radius: float = float(f.arm_r)
	var skin: Color = f.skin
	if f._lost("arm_upper_" + side):
		cv.dot(shoulder, FigurePainter.BLOOD)
		return true
	var lower_lost: bool = f._lost("arm_lower_" + side)
	var hand_lost: bool = f._lost("hand_" + side)
	cv.begin()
	_limb(cv, shoulder, elbow, radius * 1.1, radius * 0.78, skin)
	if not lower_lost:
		_limb(cv, elbow, hand, radius * 1.0, radius * 0.71, skin)
		if not hand_lost:
			_poly(cv, hand, [Vector2(-radius * 0.9, -radius * 0.6), Vector2(radius * 0.4, -radius * 0.75),
				Vector2(radius * 1.15, -radius * 0.2), Vector2(radius * 1.28, radius * 0.5),
				Vector2(radius * 0.7, radius * 1.02), Vector2(-radius * 0.7, radius * 0.85),
				Vector2(-radius, radius * 0.3)], skin)
			cv.ellipse(hand + Vector2(-radius * 0.6, -radius * 0.2), radius * 0.42, radius * 0.6, skin)
	f._skin_end()
	if not lower_lost and not hand_lost:
		for index: int in range(3):
			var knuckle: Vector2 = hand + Vector2(radius * (-0.25 + float(index) * 0.4), radius * 0.28)
			cv.capsule(knuckle, knuckle + Vector2(0.25, 0.25), 0.15, skin.lightened(0.18))
			cv.capsule(knuckle + Vector2(0.1, 0.42), knuckle + Vector2(0.25, 0.5), 0.1, skin.darkened(0.35))
	_wardrobe_sleeve(f,side,shoulder,elbow,radius)
	_wardrobe_bracer(f,side,elbow,hand,radius)
	if lower_lost:
		cv.dot(elbow, FigurePainter.BLOOD)
	elif hand_lost:
		cv.dot(hand, FigurePainter.BLOOD)
	return true

static func leg(f, side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var hip: Vector2 = f.j["p" + side]
	var knee: Vector2 = f.j["k" + side]
	var foot: Vector2 = f.j["f" + side]
	var radius: float = float(f.leg_r)
	var skin: Color = f.skin
	var trousers: bool = not f._it("legs_under").is_empty()
	var color: Color = f._trouser_col() if trousers else skin
	if f._lost("leg_upper_" + side):
		cv.dot(hip, FigurePainter.BLOOD)
		return true
	var lower_lost: bool = f._lost("leg_lower_" + side)
	var foot_lost: bool = f._lost("foot_" + side)
	cv.begin()
	_limb(cv, hip, knee, radius * 1.05, radius * 0.83, color)
	if not lower_lost:
		_limb(cv, knee, foot, radius * 0.87, radius * 0.62, color)
	if trousers:
		cv.end(FigurePainter.ol(color), 0.06)
	else:
		f._skin_end()
	if not lower_lost and not foot_lost:
		var length: float = 3.4 * float(f.gs)
		cv.begin()
		_poly(cv, foot, [Vector2(-1.35, -0.65), Vector2(0.6, -0.65), Vector2(length - 1.0, 0.05),
			Vector2(length - 0.55, 0.7), Vector2(length - 0.9, 1.35), Vector2(-1.45, 1.25)], skin)
		cv.ellipse(foot + Vector2(-0.3, -0.25), radius * 0.63, radius * 0.45, skin.lightened(0.12))
		f._skin_end()
		for index: int in range(3):
			cv.capsule(foot + Vector2(length - 1.65 + float(index) * 0.4, 0.55),
				foot + Vector2(length - 1.55 + float(index) * 0.4, 0.95), 0.1, skin.darkened(0.35))
	_wardrobe_leg_layers(f,side,hip,knee,foot,radius)
	if lower_lost:
		cv.dot(knee, FigurePainter.BLOOD)
	elif foot_lost:
		cv.dot(foot, FigurePainter.BLOOD)
	return true


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
