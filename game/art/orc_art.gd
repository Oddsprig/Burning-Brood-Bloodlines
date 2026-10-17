class_name OrcArt
extends RefCounted
## Orc anatomy and clothing on FigurePainter's existing rig. Equipment and wounds remain
## FigurePainter layers. No look data is synthesized; the seed only varies anatomy/hair.

static func _poly(cv: PixelCanvas, origin: Vector2, points: Array, color: Color) -> void:
	var vertices: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		vertices.append(origin + point)
	cv.poly(vertices, color)

## Quadratic contours give flesh connected volumes instead of a collection of boxes.
static func _contour(cv: PixelCanvas, origin: Vector2, arcs: Array, color: Color) -> void:
	var vertices: PackedVector2Array = PackedVector2Array()
	var steps: int = 7 if cv.k >= 4.0 else 4
	for arc: Array in arcs:
		var a: Vector2 = arc[0]
		var control: Vector2 = arc[1]
		var b: Vector2 = arc[2]
		for index: int in steps:
			var t: float = float(index) / float(steps)
			var point: Vector2 = a * (1.0 - t) * (1.0 - t) + control * 2.0 * t * (1.0 - t) + b * t * t
			vertices.append(origin + point)
	cv.poly(vertices, color)

const HAIRSTYLES: Array[String] = ["Swept crest", "High mohawk", "Topknot", "Short crop", "Side sweep",
	"Ponytail", "Single braid", "Twin braids", "Shoulder length", "Loose curls"]

static func hairstyle_name(seed: int) -> String:
	return HAIRSTYLES[posmod(seed, 10)]

static func face_variant(seed: int) -> int:
	return posmod(int(seed / 10), 2)

static func _female(f) -> bool:
	return String(f.spec.get("sex", "")).to_lower() in ["female", "f", "woman", "1"]

static func head(f) -> void:
	if f._lost("head"):
		return
	var seed: int = int(f.spec.get("seed", 0))
	var compact: bool = face_variant(seed) == 1
	if _female(f):
		_female_head(f, compact)
	elif compact:
		_compact_head(f)
	else:
		_heavy_head(f)

static func _female_head(f, compact: bool) -> void:
	if FigurePainter.female_variant(f.spec) == 0:
		_female_head_retained(f, compact)
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var seed: int = int(f.spec.get("seed", 0))
	var anatomy_seed: int = int(seed / 20)
	var maturity: float = clampf(float(int(f.spec.get("age", 28)) - 28) / 45.0, 0.0, 1.0)
	var front: float = 2.6 if compact else 2.4
	var chin: float = (2.7 if compact else 2.95) + 0.045 * float(posmod(anatomy_seed, 3))
	var dark: Color = skin.darkened(0.21 + maturity * 0.035)
	var deep: Color = skin.darkened(0.63).lerp(Color("#28291f"), 0.08)
	var light: Color = skin.lightened(0.15)
	var brow_color: Color = skin.darkened(0.4).lerp(f.hair, 0.25)
	var lip: Color = skin.darkened(0.23).lerp(Color("#976958"), 0.12)
	var has_nose: bool = not f._lost("nose")
	var has_mouth: bool = not f._lost("mouth")
	var has_jaw: bool = not f._lost("jaw")
	var dead: bool = String(f.pose) == "dead" or bool(f.spec.get("dead", false))
	var lower_y: float = chin if has_jaw else 1.75
	var lower_x: float = front - 0.3 if has_jaw else front - 0.6
	if not f._lost("neck"):
		cv.begin()
		_contour(cv, hc, [
			[Vector2(-2.15, 1.55), Vector2(-2.25, 2.6), Vector2(-2.8, 3.65)],
			[Vector2(-2.8, 3.65), Vector2(-0.25, 4.2), Vector2(1.35, 3.85)],
			[Vector2(1.35, 3.85), Vector2(0.65, 2.65), Vector2(0.3, 2.0)],
			[Vector2(0.3, 2.0), Vector2(-1.15, 1.8), Vector2(-2.15, 1.55)]], skin.darkened(0.1))
		cv.capsule(hc + Vector2(-1.6, 2.7), hc + Vector2(-1.0, 3.6), 0.32, skin)
		cv.capsule(hc + Vector2(-1.95, 2.55), hc + Vector2(-2.0, 3.4), 0.13, dark)
		f._skin_end()
	cv.begin()
	# Smooth adult cheek volume descends to a tapered lower face and small firm
	# chin. The heavy archetype keeps more chin depth; compact keeps more width.
	_contour(cv, hc, [
		[Vector2(-2.95, -1.3), Vector2(-2.9, -3.0), Vector2(-1.15, -3.45)],
		[Vector2(-1.15, -3.45), Vector2(0.6, -3.5), Vector2(1.65, -2.35)],
		[Vector2(1.65, -2.35), Vector2(2.2, -1.65), Vector2(2.15, -0.35)],
		[Vector2(2.15, -0.35), Vector2(2.2, 0.6), Vector2(front - 0.15, 1.3)],
		[Vector2(front - 0.15, 1.3), Vector2(front + 0.04, 2.0), Vector2(lower_x, lower_y - 0.5)],
		[Vector2(lower_x, lower_y - 0.5), Vector2(1.25, lower_y + 0.2), Vector2(0.15, lower_y - 0.15)],
		[Vector2(0.15, lower_y - 0.15), Vector2(-1.7, 2.0), Vector2(-2.75, 0.65)],
		[Vector2(-2.75, 0.65), Vector2(-3.25, -0.2), Vector2(-2.95, -1.3)]], skin)
	_contour(cv, hc, [
		[Vector2(-2.95, -1.3), Vector2(-2.9, -2.9), Vector2(-2.0, -3.2)],
		[Vector2(-2.0, -3.2), Vector2(-2.25, -1.0), Vector2(-1.65, 0.8)],
		[Vector2(-1.65, 0.8), Vector2(-0.9, 2.0), Vector2(0.15, lower_y - 0.15)],
		[Vector2(0.15, lower_y - 0.15), Vector2(-1.7, 2.0), Vector2(-2.75, 0.65)],
		[Vector2(-2.75, 0.65), Vector2(-3.25, -0.2), Vector2(-2.95, -1.3)]], dark)
	_contour(cv, hc, [
		[Vector2(-1.6, -2.7), Vector2(-0.45, -3.15), Vector2(0.75, -2.6)],
		[Vector2(0.75, -2.6), Vector2(1.3, -2.0), Vector2(1.25, -1.5)],
		[Vector2(1.25, -1.5), Vector2(-0.2, -1.6), Vector2(-1.5, -1.6)],
		[Vector2(-1.5, -1.6), Vector2(-1.85, -2.0), Vector2(-1.6, -2.7)]], skin.lightened(0.085))
	# Soft connected cheek light replaces the blocky high-contrast lower plane.
	_contour(cv, hc, [
		[Vector2(-1.7, 0.0), Vector2(-0.65, -0.05), Vector2(0.25, 0.42)],
		[Vector2(0.25, 0.42), Vector2(0.85, 1.0), Vector2(0.55, 1.4)],
		[Vector2(0.55, 1.4), Vector2(-0.6, 1.25), Vector2(-1.35, 0.72)],
		[Vector2(-1.35, 0.72), Vector2(-1.85, 0.35), Vector2(-1.7, 0.0)]], light)
	cv.ellipse(hc + Vector2(-0.65, 0.68), 0.75, 0.43, skin.lightened(0.1))
	if has_jaw:
		_contour(cv, hc, [
			[Vector2(-0.35, 1.75), Vector2(0.9, 1.95), Vector2(front - 0.12, 1.65)],
			[Vector2(front - 0.12, 1.65), Vector2(front + 0.03, 2.0), Vector2(front - 0.35, chin - 0.45)],
			[Vector2(front - 0.35, chin - 0.45), Vector2(1.2, chin + 0.17), Vector2(0.15, chin - 0.18)],
			[Vector2(0.15, chin - 0.18), Vector2(-0.45, 2.18), Vector2(-0.35, 1.75)]], skin.darkened(0.045))
		cv.ellipse(hc + Vector2(1.35, chin - 0.47), 0.69, 0.35, skin.lightened(0.12))
		cv.capsule(hc + Vector2(0.4, chin - 0.05), hc + Vector2(1.4, chin + 0.08), 0.08, dark)
	# Shallow orbital ridge and gently arched natural brow leave the upper lid open.
	cv.capsule(hc + Vector2(-1.4, -1.72), hc + Vector2(-0.4, -1.6), 0.11, skin.darkened(0.11))
	cv.capsule(hc + Vector2(0.5, -1.66), hc + Vector2(1.75, -1.48), 0.13, skin.darkened(0.12))
	_contour(cv, hc, [
		[Vector2(-1.52, -1.72), Vector2(-0.96, -1.93), Vector2(-0.28, -1.65)],
		[Vector2(-0.28, -1.65), Vector2(-0.63, -1.59), Vector2(-1.43, -1.59)],
		[Vector2(-1.43, -1.59), Vector2(-1.52, -1.66), Vector2(-1.52, -1.72)]], brow_color)
	_contour(cv, hc, [
		[Vector2(0.42, -1.74), Vector2(1.12, -1.98), Vector2(1.95, -1.49)],
		[Vector2(1.95, -1.49), Vector2(1.32, -1.51), Vector2(0.53, -1.58)],
		[Vector2(0.53, -1.58), Vector2(0.43, -1.68), Vector2(0.42, -1.74)]], brow_color)
	if has_nose:
		# A short broad nasal tip keeps orc identity while balancing the eyes/lips.
		_contour(cv, hc, [
			[Vector2(1.15, -1.25), Vector2(1.65, -1.3), Vector2(1.75, -0.48)],
			[Vector2(1.75, -0.48), Vector2(1.92, 0.16), Vector2(front - 0.08, 0.28)],
			[Vector2(front - 0.08, 0.28), Vector2(front + 0.17, 0.68), Vector2(front - 0.35, 0.84)],
			[Vector2(front - 0.35, 0.84), Vector2(1.3, 0.83), Vector2(1.2, 0.47)],
			[Vector2(1.2, 0.47), Vector2(1.28, -0.3), Vector2(1.15, -1.25)]], skin.lightened(0.065))
		cv.capsule(hc + Vector2(1.43, -0.85), hc + Vector2(1.63, 0.1), 0.12, light)
		cv.ellipse(hc + Vector2(front - 0.42, 0.48), 0.43, 0.21, skin.lightened(0.12))
		cv.ellipse(hc + Vector2(front - 0.56, 0.74), 0.47, 0.11, skin.darkened(0.23))
	f._skin_end()
	if not f._lost("ear_l") and String(f._it("helm").get("sprite", "")) != "coif":
		cv.begin()
		cv.ellipse(hc + Vector2(-2.9, -0.05), 0.57, 0.81, skin)
		cv.ellipse(hc + Vector2(-3.05, -0.05), 0.24, 0.48, dark)
		f._skin_end()
	_hair(f, hc, seed)
	_female_eye(cv, hc + Vector2(-1.32, -1.15), 1.17, skin, deep, dead, f._lost("eye_l"), false)
	_female_eye(cv, hc + Vector2(0.3, -1.03), 1.6, skin, deep, dead, f._lost("eye_r"), true)
	if has_nose:
		cv.ellipse(hc + Vector2(1.65, 0.68), 0.145, 0.085, deep)
		cv.ellipse(hc + Vector2(front - 0.22, 0.67), 0.16, 0.09, deep)
	if maturity > 0.25:
		cv.capsule(hc + Vector2(-0.95, 0.77), hc + Vector2(-1.2, 0.58), 0.05, dark)
		cv.capsule(hc + Vector2(0.48, 1.3), hc + Vector2(0.4, 1.6), 0.05, dark)
	if has_mouth:
		# Cupid's bow and full lower lip use the actual skin ramp with a quiet warm
		# natural tissue tone; they are anatomy, with no cosmetic marking or item.
		_contour(cv, hc, [
			[Vector2(0.52, 1.41), Vector2(0.9, 1.1), Vector2(1.26, 1.31)],
			[Vector2(1.26, 1.31), Vector2(1.55, 1.07), Vector2(front - 0.3, 1.35)],
			[Vector2(front - 0.3, 1.35), Vector2(1.55, 1.59), Vector2(0.63, 1.57)],
			[Vector2(0.63, 1.57), Vector2(0.49, 1.51), Vector2(0.52, 1.41)]], lip)
		cv.capsule(hc + Vector2(0.56, 1.55), hc + Vector2(front - 0.32, 1.46), 0.07, deep)
		if has_jaw:
			_contour(cv, hc, [
				[Vector2(0.65, 1.63), Vector2(1.32, 1.63), Vector2(front - 0.36, 1.56)],
				[Vector2(front - 0.36, 1.56), Vector2(1.8, 1.96), Vector2(1.14, 1.97)],
				[Vector2(1.14, 1.97), Vector2(0.7, 1.91), Vector2(0.65, 1.63)]], skin.lightened(0.075).lerp(Color("#bb917b"), 0.08))
			cv.capsule(hc + Vector2(0.98, 1.78), hc + Vector2(1.6, 1.76), 0.07, skin.lightened(0.24))
	if has_mouth and has_jaw:
		# Smaller curved lower-jaw teeth frame the visible lips rather than masking them.
		_tusk(cv, hc + Vector2(0.52, 2.05), 0.42, 0.9 if compact else 1.0, false)
		_tusk(cv, hc + Vector2(front - 0.35, 2.12), 0.55, 1.2 if compact else 1.4, true)
		cv.capsule(hc + Vector2(0.35, 2.09), hc + Vector2(0.74, 2.1), 0.08, skin)
	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5,
		-float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _female_eye(cv: PixelCanvas, center: Vector2, width: float, skin: Color,
		deep: Color, dead: bool, lost: bool, near: bool) -> void:
	_contour(cv, center, [
		[Vector2(-0.12, 0.1), Vector2(width * 0.46, -0.24), Vector2(width + 0.05, 0.08)],
		[Vector2(width + 0.05, 0.08), Vector2(width * 0.9, 0.88), Vector2(width * 0.45, 0.87)],
		[Vector2(width * 0.45, 0.87), Vector2(-0.23, 0.7), Vector2(-0.12, 0.1)]], skin.darkened(0.2))
	if lost:
		return
	if dead:
		cv.capsule(center + Vector2(0.02, 0.42), center + Vector2(width - 0.02, 0.35), 0.09, deep)
		return
	_contour(cv, center, [
		[Vector2(0.01, 0.32), Vector2(width * 0.46, -0.12), Vector2(width - 0.02, 0.25)],
		[Vector2(width - 0.02, 0.25), Vector2(width * 0.77, 0.88), Vector2(width * 0.35, 0.77)],
		[Vector2(width * 0.35, 0.77), Vector2(0.07, 0.65), Vector2(0.01, 0.32)]], Color("#e1d7ab"))
	var iris: Vector2 = center + Vector2(width * 0.62, 0.43)
	cv.ellipse(iris, 0.3 if near else 0.23, 0.31, Color("#b68d30"))
	cv.ellipse(iris + Vector2(-0.015, -0.015), 0.25 if near else 0.185, 0.265, Color("#edc854"))
	cv.ellipse(iris + Vector2(0.025, 0.015), 0.105 if near else 0.08, 0.22, deep)
	if cv.k >= 3.0:
		cv.ellipse(iris + Vector2(-0.11, -0.14), 0.075 if near else 0.06, 0.065, Color("#fff1c6"))
	# A graceful upper lash line follows the open almond rather than a heavy dark brow.
	cv.capsule(center + Vector2(0.0, 0.26), center + Vector2(width * 0.37, 0.03), 0.08, deep)
	cv.capsule(center + Vector2(width * 0.37, 0.03), center + Vector2(width - 0.03, 0.19), 0.085, deep)
	cv.capsule(center + Vector2(-0.07, 0.2), center + Vector2(-0.2, 0.04), 0.065, deep)
	cv.capsule(center + Vector2(width - 0.08, 0.18), center + Vector2(width + 0.08, 0.04), 0.065, deep)
	cv.capsule(center + Vector2(0.17, 0.8), center + Vector2(width * 0.76, 0.74), 0.065, skin.lightened(0.1))

static func _female_head_retained(f, compact: bool) -> void:
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var seed: int = int(f.spec.get("seed", 0))
	var anatomy_seed: int = int(seed / 20)
	var maturity: float = clampf(float(int(f.spec.get("age", 28)) - 28) / 45.0, 0.0, 1.0)
	var front: float = 3.0 if compact else 2.65
	var chin: float = (2.8 if compact else 3.05) + 0.05 * float(posmod(anatomy_seed, 3))
	var dark: Color = skin.darkened(0.28 + maturity * 0.045)
	var deep: Color = skin.darkened(0.67).lerp(Color("#27271e"), 0.1)
	var light: Color = skin.lightened(0.16)
	var has_nose: bool = not f._lost("nose")
	var has_mouth: bool = not f._lost("mouth")
	var has_jaw: bool = not f._lost("jaw")
	var dead: bool = String(f.pose) == "dead" or bool(f.spec.get("dead", false))
	var lower_y: float = chin if has_jaw else 1.8
	var lower_x: float = front - 0.2 if has_jaw else front - 0.6
	if not f._lost("neck"):
		cv.begin()
		_contour(cv, hc, [
			[Vector2(-2.15, 1.55), Vector2(-2.25, 2.6), Vector2(-2.8, 3.65)],
			[Vector2(-2.8, 3.65), Vector2(-0.25, 4.2), Vector2(1.35, 3.85)],
			[Vector2(1.35, 3.85), Vector2(0.65, 2.65), Vector2(0.3, 2.0)],
			[Vector2(0.3, 2.0), Vector2(-1.15, 1.8), Vector2(-2.15, 1.55)]], skin.darkened(0.1))
		cv.capsule(hc + Vector2(-1.6, 2.7), hc + Vector2(-1.0, 3.6), 0.32, skin)
		cv.capsule(hc + Vector2(-1.95, 2.55), hc + Vector2(-2.0, 3.4), 0.13, dark)
		f._skin_end()
	cv.begin()
	# Adult orc cheek width, a tapered mandible, and a firm smaller chin. This is
	# shaped independently of the male face, without changing the head center.
	_contour(cv, hc, [
		[Vector2(-3.15, -1.3), Vector2(-3.0, -3.15), Vector2(-1.2, -3.45)],
		[Vector2(-1.2, -3.45), Vector2(0.55, -3.55), Vector2(1.7, -2.45)],
		[Vector2(1.7, -2.45), Vector2(2.4, -1.6), Vector2(2.35, -0.2)],
		[Vector2(2.35, -0.2), Vector2(front - 0.55, 0.6), Vector2(front - 0.15, 1.3)],
		[Vector2(front - 0.15, 1.3), Vector2(front + 0.1, 2.15), Vector2(lower_x, lower_y - 0.4)],
		[Vector2(lower_x, lower_y - 0.4), Vector2(1.2, lower_y + 0.35), Vector2(-0.15, lower_y - 0.15)],
		[Vector2(-0.15, lower_y - 0.15), Vector2(-2.2, 1.75), Vector2(-3.0, 0.55)],
		[Vector2(-3.0, 0.55), Vector2(-3.45, -0.3), Vector2(-3.15, -1.3)]], skin)
	_contour(cv, hc, [
		[Vector2(-3.15, -1.3), Vector2(-3.0, -3.0), Vector2(-2.0, -3.2)],
		[Vector2(-2.0, -3.2), Vector2(-2.5, -1.0), Vector2(-1.8, 0.65)],
		[Vector2(-1.8, 0.65), Vector2(-1.0, 2.0), Vector2(-0.15, lower_y - 0.15)],
		[Vector2(-0.15, lower_y - 0.15), Vector2(-2.2, 1.75), Vector2(-3.0, 0.55)],
		[Vector2(-3.0, 0.55), Vector2(-3.45, -0.3), Vector2(-3.15, -1.3)]], dark)
	cv.ellipse(hc + Vector2(-0.45, -2.6), 1.65, 0.58, skin.lightened(0.11))
	_contour(cv, hc, [
		[Vector2(-1.55, -0.15), Vector2(-0.4, -0.25), Vector2(0.7, 0.25)],
		[Vector2(0.7, 0.25), Vector2(1.0, 0.7), Vector2(0.4, 1.15)],
		[Vector2(0.4, 1.15), Vector2(-0.6, 1.0), Vector2(-1.4, 0.55)],
		[Vector2(-1.4, 0.55), Vector2(-1.75, 0.15), Vector2(-1.55, -0.15)]], light)
	cv.capsule(hc + Vector2(-1.3, 0.85), hc + Vector2(-0.6, 1.45), 0.18, skin.darkened(0.18))
	if has_jaw:
		_contour(cv, hc, [
			[Vector2(-0.3, 1.65), Vector2(1.0, 1.95), Vector2(front - 0.15, 1.55)],
			[Vector2(front - 0.15, 1.55), Vector2(front + 0.18, 2.15), Vector2(front - 0.3, chin - 0.35)],
			[Vector2(front - 0.3, chin - 0.35), Vector2(1.1, chin + 0.3), Vector2(0.0, chin - 0.15)],
			[Vector2(0.0, chin - 0.15), Vector2(-0.4, 2.1), Vector2(-0.3, 1.65)]], skin.darkened(0.075))
		cv.ellipse(hc + Vector2(1.5, chin - 0.42), 0.88, 0.42, skin.lightened(0.13))
		cv.capsule(hc + Vector2(0.35, chin - 0.02), hc + Vector2(1.5, chin + 0.12), 0.12, dark)
	# Reduced but still muscular orc brow ridges; raised lateral corners give an
	# almond opening instead of applying eyelashes or cosmetic markings.
	cv.capsule(hc + Vector2(-1.4, -1.3), hc + Vector2(-0.35, -1.17), 0.23, skin.darkened(0.15))
	cv.capsule(hc + Vector2(0.58, -1.25), hc + Vector2(1.85, -1.12), 0.25, skin.darkened(0.16))
	cv.capsule(hc + Vector2(-1.25, -1.39), hc + Vector2(-0.55, -1.31), 0.1, light)
	cv.capsule(hc + Vector2(0.78, -1.39), hc + Vector2(1.64, -1.26), 0.11, light)
	if has_nose:
		_contour(cv, hc, [
			[Vector2(1.12, -1.15), Vector2(1.75, -1.3), Vector2(1.95, -0.55)],
			[Vector2(1.95, -0.55), Vector2(2.12, 0.02), Vector2(front - 0.05, 0.2)],
			[Vector2(front - 0.05, 0.2), Vector2(front + 0.2, 0.67), Vector2(front - 0.4, 0.82)],
			[Vector2(front - 0.4, 0.82), Vector2(1.25, 0.85), Vector2(1.12, 0.42)],
			[Vector2(1.12, 0.42), Vector2(1.35, -0.2), Vector2(1.12, -1.15)]], skin.lightened(0.065))
		cv.capsule(hc + Vector2(1.42, -0.8), hc + Vector2(1.7, -0.05), 0.14, light)
		cv.ellipse(hc + Vector2(front - 0.57, 0.68), 0.58, 0.16, dark)
	f._skin_end()
	if not f._lost("ear_l") and String(f._it("helm").get("sprite", "")) != "coif":
		cv.begin()
		cv.ellipse(hc + Vector2(-3.1, -0.05), 0.62, 0.87, skin)
		cv.ellipse(hc + Vector2(-3.25, -0.05), 0.27, 0.53, dark)
		f._skin_end()
	_hair(f, hc, seed)
	_female_eye_retained(cv, hc + Vector2(-1.05, -0.82), 1.0, skin, deep, dead, f._lost("eye_l"), false)
	_female_eye_retained(cv, hc + Vector2(0.5, -0.72), 1.37, skin, deep, dead, f._lost("eye_r"), true)
	if has_nose:
		cv.ellipse(hc + Vector2(1.65, 0.63), 0.19, 0.1, deep)
		cv.ellipse(hc + Vector2(front - 0.32, 0.63), 0.2, 0.11, deep)
	if maturity > 0.25:
		cv.capsule(hc + Vector2(-0.85, 0.65), hc + Vector2(-1.2, 0.43), 0.07, dark)
		cv.capsule(hc + Vector2(0.58, 1.2), hc + Vector2(0.48, 1.6), 0.07, dark)
	if has_mouth:
		_contour(cv, hc, [
			[Vector2(0.6, 1.4), Vector2(1.12, 1.15), Vector2(1.45, 1.35)],
			[Vector2(1.45, 1.35), Vector2(1.85, 1.18), Vector2(front - 0.25, 1.3)],
			[Vector2(front - 0.25, 1.3), Vector2(1.72, 1.68), Vector2(0.8, 1.57)],
			[Vector2(0.8, 1.57), Vector2(0.58, 1.53), Vector2(0.6, 1.4)]], skin.darkened(0.33))
		cv.capsule(hc + Vector2(0.75, 1.53), hc + Vector2(front - 0.45, 1.47), 0.08, deep)
		if has_jaw:
			cv.ellipse(hc + Vector2(1.7, 1.75), 0.7, 0.17, skin.lightened(0.18))
	if has_mouth and has_jaw:
		if compact:
			_compact_tusk(cv, hc + Vector2(0.75, 2.02), 0.54, 1.12, false)
			_compact_tusk(cv, hc + Vector2(front - 0.55, 2.1), 0.7, 1.45, true)
		else:
			_tusk(cv, hc + Vector2(0.72, 2.22), 0.63, 1.5, false)
			_tusk(cv, hc + Vector2(front - 0.45, 2.32), 0.8, 1.85, true)
		cv.capsule(hc + Vector2(0.52, 2.15), hc + Vector2(0.98, 2.18), 0.11, skin)
	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5,
		-float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _female_eye_retained(cv: PixelCanvas, center: Vector2, width: float, skin: Color,
		deep: Color, dead: bool, lost: bool, near: bool) -> void:
	_contour(cv, center, [
		[Vector2(-0.13, 0.0), Vector2(width * 0.48, -0.22), Vector2(width + 0.04, 0.12)],
		[Vector2(width + 0.04, 0.12), Vector2(width * 0.8, 0.65), Vector2(width * 0.36, 0.65)],
		[Vector2(width * 0.36, 0.65), Vector2(-0.24, 0.43), Vector2(-0.13, 0.0)]], skin.darkened(0.32))
	if lost:
		return
	if dead:
		cv.capsule(center + Vector2(0.0, 0.3), center + Vector2(width - 0.03, 0.31), 0.09, deep)
		return
	_contour(cv, center, [
		[Vector2(0.02, 0.24), Vector2(width * 0.44, -0.02), Vector2(width - 0.03, 0.22)],
		[Vector2(width - 0.03, 0.22), Vector2(width * 0.55, 0.65), Vector2(0.12, 0.46)],
		[Vector2(0.12, 0.46), Vector2(0.0, 0.33), Vector2(0.02, 0.24)]], Color("#c8bb80"))
	cv.capsule(center + Vector2(0.03, 0.14), center + Vector2(width - 0.02, 0.19), 0.085, deep)
	cv.ellipse(center + Vector2(width * 0.63, 0.33), 0.23 if near else 0.16, 0.21, Color("#e4bb3d"))
	cv.ellipse(center + Vector2(width * 0.67, 0.34), 0.1 if near else 0.07, 0.15, deep)
	cv.capsule(center + Vector2(0.18, 0.56), center + Vector2(width * 0.76, 0.57), 0.07, skin.lightened(0.14))

static func _heavy_head(f) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = int(f.spec.get("seed", 0))
	var anatomy_seed: int = int(seed / 20)
	var female: bool = _female(f)
	var age: int = int(f.spec.get("age", 28))
	var maturity: float = clampf(float(age - 28) / 45.0, 0.0, 1.0)
	var jaw: float = 0.08 * float(posmod(anatomy_seed, 3)) - (0.14 if female else 0.0)
	var brow: float = 0.04 * float(posmod(int(anatomy_seed / 3), 3)) - (0.05 if female else 0.0)
	var dark: Color = skin.darkened(0.34 + maturity * 0.04)
	var deep: Color = skin.darkened(0.7).lerp(Color("#202419"), 0.12)
	var light: Color = skin.lightened(0.18)
	var has_nose: bool = not f._lost("nose")
	var has_mouth: bool = not f._lost("mouth")
	var has_jaw: bool = not f._lost("jaw")
	var chin_y: float = 3.35 if has_jaw else 2.05
	var chin_x: float = 3.5 + jaw if has_jaw else 2.3
	var dead: bool = String(f.pose) == "dead" or bool(f.spec.get("dead", false))
	# Thick sternomastoid and trapezius under a separate overhanging chin.
	if not f._lost("neck"):
		cv.begin()
		_contour(cv, hc, [
			[Vector2(-2.8, 1.5), Vector2(-3.25, 2.3), Vector2(-3.6, 3.6)],
			[Vector2(-3.6, 3.6), Vector2(-0.9, 4.55), Vector2(1.95, 4.05)],
			[Vector2(1.95, 4.05), Vector2(1.4, 2.65), Vector2(0.45, 2.0)],
			[Vector2(0.45, 2.0), Vector2(-1.8, 1.75), Vector2(-2.8, 1.5)]], skin.darkened(0.18))
		cv.capsule(hc + Vector2(-1.8, 2.6), hc + Vector2(-1.2, 3.65), 0.55, skin)
		cv.capsule(hc + Vector2(-2.45, 2.3), hc + Vector2(-2.5, 3.5), 0.2, dark)
		cv.ellipse(hc + Vector2(0.4, 3.55), 0.8, 0.5, skin.darkened(0.08))
		f._skin_end()
	cv.begin()
	# Compact cranium turns into a broad cheek and deep lower jaw. Nose is never
	# baked into this contour: a missing nose cannot leave the old forward tip.
	_contour(cv, hc, [
		[Vector2(-3.6, -1.5), Vector2(-3.35, -3.25), Vector2(-1.55, -3.55)],
		[Vector2(-1.55, -3.55), Vector2(0.65, -3.6), Vector2(1.85, -2.45)],
		[Vector2(1.85, -2.45), Vector2(2.6, -1.65), Vector2(2.45, -0.3)],
		[Vector2(2.45, -0.3), Vector2(2.45, 0.65), Vector2(2.9, 1.25)],
		[Vector2(2.9, 1.25), Vector2(chin_x + 0.35, 2.2), Vector2(chin_x, chin_y - 0.55)],
		[Vector2(chin_x, chin_y - 0.55), Vector2(1.95, chin_y + 0.4), Vector2(-0.25, chin_y)],
		[Vector2(-0.25, chin_y), Vector2(-2.95, 2.4), Vector2(-3.5, 0.8)],
		[Vector2(-3.5, 0.8), Vector2(-3.85, -0.3), Vector2(-3.6, -1.5)]], skin.darkened(0.04))
	# Connected side plane, kept quieter than the old separated green stripes.
	_contour(cv, hc, [
		[Vector2(-3.6, -1.5), Vector2(-3.35, -3.0), Vector2(-2.1, -3.4)],
		[Vector2(-2.1, -3.4), Vector2(-2.6, -1.0), Vector2(-1.95, 0.45)],
		[Vector2(-1.95, 0.45), Vector2(-1.5, 2.4), Vector2(-0.25, chin_y)],
		[Vector2(-0.25, chin_y), Vector2(-2.95, 2.4), Vector2(-3.5, 0.8)],
		[Vector2(-3.5, 0.8), Vector2(-3.85, -0.3), Vector2(-3.6, -1.5)]], dark)
	_contour(cv, hc, [
		[Vector2(-2.0, -2.8), Vector2(-0.7, -3.25), Vector2(0.9, -2.7)],
		[Vector2(0.9, -2.7), Vector2(1.7, -2.35), Vector2(1.8, -1.85)],
		[Vector2(1.8, -1.85), Vector2(0.2, -2.0), Vector2(-1.4, -1.85)],
		[Vector2(-1.4, -1.85), Vector2(-1.95, -2.05), Vector2(-2.0, -2.8)]], skin.lightened(0.11))
	# A high cheekbone descends diagonally toward the mouth, showing a three-quarter
	# turn instead of the former horizontal reptilian muzzle.
	_contour(cv, hc, [
		[Vector2(-1.65, -0.15), Vector2(-0.8, -0.1), Vector2(0.2, 0.3)],
		[Vector2(0.2, 0.3), Vector2(1.1, 0.9), Vector2(0.75, 1.45)],
		[Vector2(0.75, 1.45), Vector2(-0.6, 1.1), Vector2(-1.3, 0.55)],
		[Vector2(-1.3, 0.55), Vector2(-1.85, 0.1), Vector2(-1.65, -0.15)]], light)
	cv.capsule(hc + Vector2(-1.35, 0.9), hc + Vector2(-0.6, 1.65), 0.27, skin.darkened(0.25))
	if has_jaw:
		_contour(cv, hc, [
			[Vector2(-0.65, 1.8), Vector2(1.0, 2.05), Vector2(2.8, 1.75)],
			[Vector2(2.8, 1.75), Vector2(3.85 + jaw, 2.1), Vector2(3.5 + jaw, 2.85)],
			[Vector2(3.5 + jaw, 2.85), Vector2(2.0, 3.7), Vector2(0.0, 3.2)],
			[Vector2(0.0, 3.2), Vector2(-0.8, 2.9), Vector2(-0.65, 1.8)]], skin.darkened(0.13))
		cv.ellipse(hc + Vector2(2.0, 2.8), 1.22, 0.62, skin.lightened(0.13))
		cv.capsule(hc + Vector2(0.25, 3.15), hc + Vector2(2.1, 3.4), 0.2, dark)
		cv.capsule(hc + Vector2(2.0, 2.55), hc + Vector2(2.25, 2.85), 0.09, skin.darkened(0.27))
	# Massive individual orbital ridges, sloping into a central glabella.
	_contour(cv, hc, [
		[Vector2(-1.55, -1.5), Vector2(-0.9, -2.0 - brow), Vector2(-0.05, -1.6)],
		[Vector2(-0.05, -1.6), Vector2(0.45, -1.15), Vector2(0.15, -0.95)],
		[Vector2(0.15, -0.95), Vector2(-0.85, -1.1), Vector2(-1.55, -1.15)],
		[Vector2(-1.55, -1.15), Vector2(-1.75, -1.4), Vector2(-1.55, -1.5)]], skin.darkened(0.14))
	_contour(cv, hc, [
		[Vector2(0.4, -1.65), Vector2(1.3, -2.1 - brow), Vector2(2.1, -1.5)],
		[Vector2(2.1, -1.5), Vector2(2.65, -1.1), Vector2(2.3, -0.9)],
		[Vector2(2.3, -0.9), Vector2(1.25, -0.95), Vector2(0.5, -1.12)],
		[Vector2(0.5, -1.12), Vector2(0.3, -1.45), Vector2(0.4, -1.65)]], skin.darkened(0.17))
	cv.capsule(hc + Vector2(-1.25, -1.55), hc + Vector2(-0.25, -1.5), 0.15, light)
	cv.capsule(hc + Vector2(0.7, -1.62), hc + Vector2(1.7, -1.45), 0.18, light)
	if has_nose:
		# Wide vertical bridge terminates in a short blunt tip, below the eyes.
		_contour(cv, hc, [
			[Vector2(1.15, -1.4), Vector2(1.95, -1.45), Vector2(2.15, -0.65)],
			[Vector2(2.15, -0.65), Vector2(2.35, -0.1), Vector2(2.9, 0.1)],
			[Vector2(2.9, 0.1), Vector2(3.3, 0.65), Vector2(2.7, 0.85)],
			[Vector2(2.7, 0.85), Vector2(1.25, 1.05), Vector2(1.0, 0.45)],
			[Vector2(1.0, 0.45), Vector2(1.3, -0.3), Vector2(1.15, -1.4)]], skin.lightened(0.06))
		cv.capsule(hc + Vector2(1.48, -0.95), hc + Vector2(1.85, -0.05), 0.19, light)
		cv.ellipse(hc + Vector2(2.35, 0.35), 0.6, 0.3, skin.lightened(0.15))
		cv.ellipse(hc + Vector2(2.05, 0.69), 0.72, 0.18, dark)
	f._skin_end()
	if not f._lost("ear_l") and String(f._it("helm").get("sprite", "")) != "coif":
		cv.begin()
		cv.ellipse(hc + Vector2(-3.4, -0.05), 0.72, 1.0, skin.darkened(0.05))
		cv.ellipse(hc + Vector2(-3.55, -0.02), 0.35, 0.63, dark)
		cv.capsule(hc + Vector2(-3.3, 0.15), hc + Vector2(-3.4, 0.55), 0.16, light)
		f._skin_end()
	_hair(f, hc, seed)
	_eye(cv, hc + Vector2(-1.0, -0.9), 1.02, skin, deep, dead, f._lost("eye_l"), false)
	_eye(cv, hc + Vector2(0.5, -0.78), 1.52, skin, deep, dead, f._lost("eye_r"), true)
	if has_nose:
		cv.ellipse(hc + Vector2(1.65, 0.63), 0.23, 0.12, deep)
		cv.ellipse(hc + Vector2(2.65, 0.62), 0.25, 0.14, deep)
	if maturity > 0.25:
		cv.capsule(hc + Vector2(-0.9, 0.55), hc + Vector2(-1.3, 0.33), 0.075, dark)
		cv.capsule(hc + Vector2(0.6, 1.2), hc + Vector2(0.5, 1.65), 0.08, dark)
	if has_mouth:
		cv.capsule(hc + Vector2(0.5, 1.52), hc + Vector2(2.6, 1.38), 0.17, deep)
		if has_jaw:
			cv.capsule(hc + Vector2(0.95, 1.95), hc + Vector2(2.5, 1.9), 0.2, skin.lightened(0.17))
	if bool(f.spec.get("beard", false)) and has_jaw and not female:
		var beard_style: int = FigurePainter.beard_style(f.spec)
		if beard_style > 0:
			_beard_variant(f, hc, beard_style)
		else:
			_beard(cv, hc, hair, seed)
	if has_mouth and has_jaw:
		# Visible roots lie below the lower lip; both teeth bend up in front of it.
		_tusk(cv, hc + Vector2(0.8, 2.45), 0.8, 1.95, false)
		_tusk(cv, hc + Vector2(2.85, 2.55), 1.05, 2.45, true)
		cv.capsule(hc + Vector2(0.52, 2.48), hc + Vector2(1.03, 2.49), 0.12, skin.darkened(0.08))
		cv.capsule(hc + Vector2(2.45, 2.56), hc + Vector2(3.19, 2.56), 0.15, skin)
	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5,
		-float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _compact_head(f) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = int(f.spec.get("seed", 0))
	var anatomy_seed: int = int(seed / 20)
	var female: bool = _female(f)
	var age: int = int(f.spec.get("age", 28))
	var maturity: float = clampf(float(age - 28) / 45.0, 0.0, 1.0)
	var jaw: float = 0.08 * float(posmod(anatomy_seed, 3)) - (0.13 if female else 0.0)
	var brow: float = 0.06 * float(posmod(int(anatomy_seed / 3), 3)) - (0.06 if female else 0.0)
	var dark: Color = skin.darkened(0.31 + maturity * 0.04)
	var deep: Color = skin.darkened(0.63).lerp(Color("#202519"), 0.14)
	var light: Color = skin.lightened(0.2)
	var has_nose: bool = not f._lost("nose")
	var has_mouth: bool = not f._lost("mouth")
	var has_jaw: bool = not f._lost("jaw")
	var chin_x: float = 3.65 + jaw if has_jaw else 2.65
	var chin_y: float = 3.2 if has_jaw else 1.85
	var dead: bool = String(f.pose) == "dead" or bool(f.spec.get("dead", false))
	# A rounded mass of neck and trapezius grows into the same shoulder anchors.
	if not f._lost("neck"):
		cv.begin()
		_contour(cv, hc, [
			[Vector2(-2.75, 1.45), Vector2(-3.3, 2.2), Vector2(-3.15, 3.65)],
			[Vector2(-3.15, 3.65), Vector2(-0.8, 4.2), Vector2(1.7, 3.95)],
			[Vector2(1.7, 3.95), Vector2(1.1, 2.65), Vector2(0.75, 2.15)],
			[Vector2(0.75, 2.15), Vector2(-1.2, 1.8), Vector2(-2.75, 1.45)]], skin.darkened(0.12))
		cv.ellipse(hc + Vector2(-1.25, 3.15), 1.05, 0.95, skin)
		_poly(cv, hc, [Vector2(-2.35, 2.2), Vector2(-1.75, 2.4), Vector2(-1.55, 3.6),
			Vector2(-2.1, 3.75)], dark)
		f._skin_end()
	cv.begin()
	# The skull carries the face. The short nasal tip is a separate, loss-aware mass.
	_contour(cv, hc, [
		[Vector2(-3.8, -1.1), Vector2(-3.6, -3.35), Vector2(-1.65, -3.55)],
		[Vector2(-1.65, -3.55), Vector2(0.35, -3.7), Vector2(1.9, -2.65)],
		[Vector2(1.9, -2.65), Vector2(2.9, -1.8), Vector2(2.85, -0.15)],
		[Vector2(2.85, -0.15), Vector2(2.85, 0.65), Vector2(3.55, 1.35)],
		[Vector2(3.55, 1.35), Vector2(4.25 + jaw if has_jaw else 3.0, 1.9), Vector2(chin_x, 2.95 if has_jaw else 1.85)],
		[Vector2(chin_x, 2.95 if has_jaw else 1.85), Vector2(2.15, 3.65 if has_jaw else 2.0), Vector2(0.1, chin_y)],
		[Vector2(0.1, chin_y), Vector2(-2.8, 2.8), Vector2(-3.65, 0.95)],
		[Vector2(-3.65, 0.95), Vector2(-4.0, 0.05), Vector2(-3.8, -1.1)]], skin)
	_contour(cv, hc, [
		[Vector2(-3.8, -1.1), Vector2(-3.6, -2.85), Vector2(-2.4, -3.2)],
		[Vector2(-2.4, -3.2), Vector2(-2.5, -0.8), Vector2(-1.9, 0.4)],
		[Vector2(-1.9, 0.4), Vector2(-1.6, 2.15), Vector2(0.1, chin_y)],
		[Vector2(0.1, chin_y), Vector2(-2.8, 2.8), Vector2(-3.65, 0.95)],
		[Vector2(-3.65, 0.95), Vector2(-4.0, 0.05), Vector2(-3.8, -1.1)]], dark)
	cv.ellipse(hc + Vector2(-0.85, -2.65), 2.0, 0.55, light)
	# Broad cheekbone above a shallow hollow; the lower face remains thick and blunt.
	_contour(cv, hc, [
		[Vector2(-1.8, -0.4), Vector2(-0.3, -0.15), Vector2(0.9, 0.4)],
		[Vector2(0.9, 0.4), Vector2(1.1, 0.85), Vector2(0.45, 1.05)],
		[Vector2(0.45, 1.05), Vector2(-0.45, 0.8), Vector2(-1.35, 0.5)],
		[Vector2(-1.35, 0.5), Vector2(-1.8, 0.1), Vector2(-1.8, -0.4)]], light)
	_poly(cv, hc, [Vector2(-1.35, 0.55), Vector2(0.45, 1.05), Vector2(0.3, 1.6),
		Vector2(-0.6, 1.5), Vector2(-1.5, 1.0)], skin.darkened(0.21 + maturity * 0.08))
	if has_jaw:
		_contour(cv, hc, [
			[Vector2(-0.6, 1.75), Vector2(1.8, 2.15), Vector2(3.8 + jaw, 1.65)],
			[Vector2(3.8 + jaw, 1.65), Vector2(4.2 + jaw, 2.55), Vector2(2.8, 3.05)],
			[Vector2(2.8, 3.05), Vector2(0.2, 3.55), Vector2(-0.8, 2.35)],
			[Vector2(-0.8, 2.35), Vector2(-0.8, 1.95), Vector2(-0.6, 1.75)]], skin.darkened(0.12))
		cv.ellipse(hc + Vector2(1.9, 2.75), 1.4, 0.38, skin.lightened(0.12))
	# Connected brow arches sit low over deeply inset sockets. No thin elf brows.
	_contour(cv, hc, [
		[Vector2(-1.45, -1.45), Vector2(-0.65, -2.0 - brow), Vector2(0.55, -1.65)],
		[Vector2(0.55, -1.65), Vector2(1.8, -2.2 - brow), Vector2(2.8, -1.45)],
		[Vector2(2.8, -1.45), Vector2(3.15, -1.0), Vector2(2.8, -0.8)],
		[Vector2(2.8, -0.8), Vector2(1.55, -0.7), Vector2(0.6, -1.05)],
		[Vector2(0.6, -1.05), Vector2(-0.6, -0.7), Vector2(-1.45, -1.0)],
		[Vector2(-1.45, -1.0), Vector2(-1.7, -1.25), Vector2(-1.45, -1.45)]], skin.darkened(0.17))
	cv.capsule(hc + Vector2(-1.1, -1.45), hc + Vector2(0.25, -1.4), 0.18, light)
	cv.capsule(hc + Vector2(0.9, -1.55), hc + Vector2(2.45, -1.25), 0.2, light)
	# Thick nasal bridge and rounded, compressed tip. The skull has no hidden tip.
	if has_nose:
		_contour(cv, hc, [
			[Vector2(1.35, -1.1), Vector2(2.0, -1.35), Vector2(2.55, -0.9)],
			[Vector2(2.55, -0.9), Vector2(2.8, -0.25), Vector2(3.45, -0.1)],
			[Vector2(3.45, -0.1), Vector2(3.85, 0.6), Vector2(3.3, 0.85)],
			[Vector2(3.3, 0.85), Vector2(2.0, 1.0), Vector2(1.55, 0.45)],
			[Vector2(1.55, 0.45), Vector2(1.25, -0.2), Vector2(1.35, -1.1)]], skin.lightened(0.09))
		cv.ellipse(hc + Vector2(2.85, 0.55), 0.9, 0.34, dark)
		cv.ellipse(hc + Vector2(2.65, 0.05), 0.6, 0.24, skin.lightened(0.15))
	f._skin_end()
	# Blunt folded ear, grown from the temple rather than a long pointed appendage.
	if not f._lost("ear_l") and String(f._it("helm").get("sprite", "")) != "coif":
		cv.begin()
		_contour(cv, hc, [
			[Vector2(-2.85, -0.7), Vector2(-4.4, -1.3), Vector2(-4.15, -0.1)],
			[Vector2(-4.15, -0.1), Vector2(-4.0, 0.9), Vector2(-3.3, 1.1)],
			[Vector2(-3.3, 1.1), Vector2(-2.55, 0.5), Vector2(-2.85, -0.7)]], skin)
		cv.capsule(hc + Vector2(-3.7, -0.3), hc + Vector2(-3.4, 0.45), 0.27, dark)
		cv.capsule(hc + Vector2(-3.25, 0.1), hc + Vector2(-3.3, 0.65), 0.14, light)
		f._skin_end()
	_hair(f, hc, seed)
	_compact_eye(cv, hc + Vector2(-0.9, -0.62), 1.02, skin, deep, dead, f._lost("eye_l"), false)
	_compact_eye(cv, hc + Vector2(0.82, -0.56), 1.45, skin, deep, dead, f._lost("eye_r"), true)
	if has_nose:
		cv.ellipse(hc + Vector2(2.35, 0.55), 0.26, 0.12, deep)
		cv.ellipse(hc + Vector2(3.2, 0.55), 0.29, 0.13, deep)
	# Age changes actual facial folds, with no invented injury or decoration.
	if maturity > 0.25:
		cv.capsule(hc + Vector2(-0.8, 0.35), hc + Vector2(-1.25, 0.15), 0.07, dark)
		cv.capsule(hc + Vector2(1.35, 1.0), hc + Vector2(1.1, 1.42), 0.08, dark)
	if has_mouth:
		_contour(cv, hc, [
			[Vector2(0.55, 1.4), Vector2(1.65, 1.7), Vector2(3.55, 1.3)],
			[Vector2(3.55, 1.3), Vector2(3.65, 1.55), Vector2(3.25, 1.72)],
			[Vector2(3.25, 1.72), Vector2(1.6, 2.0), Vector2(0.7, 1.7)],
			[Vector2(0.7, 1.7), Vector2(0.45, 1.55), Vector2(0.55, 1.4)]], deep)
		cv.capsule(hc + Vector2(1.25, 1.96), hc + Vector2(2.85, 1.92), 0.15, skin.lightened(0.16))
	if bool(f.spec.get("beard", false)) and has_jaw and not female:
		var beard_style: int = FigurePainter.beard_style(f.spec)
		if beard_style > 0:
			_beard_variant(f, hc, beard_style)
		else:
			_beard(cv, hc, hair, seed)
	if has_mouth and has_jaw:
		_compact_tusk(cv, hc + Vector2(1.05, 2.15), 0.68, 1.35, false)
		_compact_tusk(cv, hc + Vector2(3.25, 2.22), 0.86, 1.8, true)
	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5,
		-float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _compact_eye(cv: PixelCanvas, center: Vector2, width: float, skin: Color,
		deep: Color, dead: bool, lost: bool, near: bool) -> void:
	# Shadow forms a recessed socket, with the upper eyelid tucked under the brow.
	_contour(cv, center, [
		[Vector2(-0.18, -0.2), Vector2(width * 0.4, -0.43), Vector2(width, -0.06)],
		[Vector2(width, -0.06), Vector2(width + 0.1, 0.38), Vector2(width * 0.5, 0.5)],
		[Vector2(width * 0.5, 0.5), Vector2(-0.18, 0.35), Vector2(-0.18, -0.2)]], skin.darkened(0.4))
	cv.capsule(center + Vector2(-0.05, -0.12), center + Vector2(width, 0.03), 0.14, deep)
	if lost:
		return
	if dead:
		cv.capsule(center + Vector2(0.05, 0.17), center + Vector2(width - 0.1, 0.19), 0.1, deep)
		return
	_poly(cv, center, [Vector2(0.04, 0.07), Vector2(width * 0.48, 0.02),
		Vector2(width - 0.07, 0.15), Vector2(width * 0.62, 0.33), Vector2(0.16, 0.27)], Color("#a99e55"))
	if near:
		cv.ellipse(center + Vector2(width * 0.64, 0.18), 0.19, 0.15, Color("#f2c53e"))
		cv.ellipse(center + Vector2(width * 0.7, 0.19), 0.065, 0.12, deep)
	else:
		cv.ellipse(center + Vector2(width * 0.68, 0.18), 0.12, 0.12, Color("#d4b43a"))
	cv.capsule(center + Vector2(0.16, 0.4), center + Vector2(width * 0.77, 0.43), 0.08, skin.lightened(0.12))

static func _compact_tusk(cv: PixelCanvas, base: Vector2, width: float, height: float, near: bool) -> void:
	cv.begin()
	# Broad lower root bends inward, then the tip hooks forward. The exposed ivory
	# is a single curved tooth, not a straight triangular fang or decorative spike.
	_contour(cv, base, [
		[Vector2(-width * 0.5, 0.02), Vector2(-width * 0.6, -height * 0.4), Vector2(-width * 0.2, -height * 0.7)],
		[Vector2(-width * 0.2, -height * 0.7), Vector2(width * 0.22, -height * 0.91), Vector2(width * 0.14, -height)],
		[Vector2(width * 0.14, -height), Vector2(width * 0.58, -height * 0.8), Vector2(width * 0.46, -height * 0.5)],
		[Vector2(width * 0.46, -height * 0.5), Vector2(width * 0.35, -height * 0.18), Vector2(width * 0.5, 0.0)],
		[Vector2(width * 0.5, 0.0), Vector2(0.0, 0.1), Vector2(-width * 0.5, 0.02)]], Color("#b8a36f"))
	_contour(cv, base, [
		[Vector2(-width * 0.26, -0.2), Vector2(-width * 0.34, -height * 0.4), Vector2(-width * 0.05, -height * 0.67)],
		[Vector2(-width * 0.05, -height * 0.67), Vector2(width * 0.22, -height * 0.92), Vector2(width * 0.14, -height)],
		[Vector2(width * 0.14, -height), Vector2(width * 0.38, -height * 0.77), Vector2(width * 0.26, -height * 0.51)],
		[Vector2(width * 0.26, -height * 0.51), Vector2(width * 0.11, -height * 0.27), Vector2(width * 0.22, -0.17)],
		[Vector2(width * 0.22, -0.17), Vector2(0.0, -0.12), Vector2(-width * 0.26, -0.2)]], Color("#f1e4bb") if near else Color("#d9cba2"))
	cv.end(Color("#514833"), 0.025)

static func _eye(cv: PixelCanvas, center: Vector2, width: float, skin: Color,
		deep: Color, dead: bool, lost: bool, near: bool) -> void:
	# Deep sockets surround a readable almond eye, yellow iris, and round dark pupil.
	_contour(cv, center, [
		[Vector2(-0.2, -0.16), Vector2(width * 0.5, -0.42), Vector2(width + 0.07, 0.03)],
		[Vector2(width + 0.07, 0.03), Vector2(width + 0.2, 0.8), Vector2(width * 0.5, 0.9)],
		[Vector2(width * 0.5, 0.9), Vector2(-0.35, 0.6), Vector2(-0.2, -0.16)]], skin.darkened(0.45))
	cv.capsule(center + Vector2(0.0, -0.03), center + Vector2(width, 0.1), 0.16, deep)
	if lost:
		return
	if dead:
		cv.capsule(center + Vector2(0.05, 0.38), center + Vector2(width - 0.05, 0.42), 0.13, deep)
		return
	_contour(cv, center, [
		[Vector2(0.03, 0.19), Vector2(width * 0.4, 0.05), Vector2(width - 0.05, 0.3)],
		[Vector2(width - 0.05, 0.3), Vector2(width * 0.65, 0.7), Vector2(0.13, 0.52)],
		[Vector2(0.13, 0.52), Vector2(0.0, 0.36), Vector2(0.03, 0.19)]], Color("#c2b477"))
	var iris_x: float = width * 0.64
	var iris_r: float = 0.25 if near else 0.18
	cv.ellipse(center + Vector2(iris_x, 0.38), iris_r, 0.24, Color("#e9bd37"))
	cv.ellipse(center + Vector2(iris_x + 0.05, 0.39), 0.11 if near else 0.08, 0.18, deep)
	if near and cv.k >= 4.0:
		cv.ellipse(center + Vector2(iris_x - 0.07, 0.26), 0.055, 0.055, Color("#f7e3a0"))
	cv.capsule(center + Vector2(0.14, 0.7), center + Vector2(width * 0.76, 0.73), 0.08, skin.lightened(0.1))

static func _hair_cap(cv: PixelCanvas, hc: Vector2, hair: Color) -> void:
	_contour(cv, hc, [
		[Vector2(-3.1, -1.9), Vector2(-3.4, -3.4), Vector2(-1.55, -3.75)],
		[Vector2(-1.55, -3.75), Vector2(0.5, -3.85), Vector2(1.6, -2.65)],
		[Vector2(1.6, -2.65), Vector2(0.0, -2.9), Vector2(-1.35, -2.65)],
		[Vector2(-1.35, -2.65), Vector2(-2.55, -2.3), Vector2(-3.1, -1.9)]], hair)
	cv.capsule(hc + Vector2(-2.4, -3.0), hc + Vector2(-1.0, -3.35), 0.16, hair.lightened(0.19))

static func _braid(cv: PixelCanvas, start: Vector2, end: Vector2, radius: float, hair: Color) -> void:
	var axis: Vector2 = (end - start).normalized()
	var normal: Vector2 = Vector2(axis.y, -axis.x)
	var count: int = 6
	cv.capsule(start, end, radius * 0.7, hair.darkened(0.18))
	for index: int in count:
		var center: Vector2 = start.lerp(end, float(index) / float(count - 1))
		var offset: float = radius * (0.22 if index % 2 == 0 else -0.22)
		cv.ellipse(center + normal * offset, radius, radius * 0.8, hair)
		cv.capsule(center - normal * radius * 0.5 - axis * radius * 0.2,
			center + normal * radius * 0.3 + axis * radius * 0.28, radius * 0.12, hair.lightened(0.2))
	cv.capsule(end, end + axis * radius * 0.7, radius * 0.4, hair)

static func _hair(f, hc: Vector2, seed: int) -> void:
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var light: Color = hair.lightened(0.19)
	var dark: Color = hair.darkened(0.22)
	var helmed: bool = not f._it("helm").is_empty()
	var style: int = posmod(seed, 10)
	cv.begin()
	match style:
		0: # Swept crest: the accepted low ridge with swept tufts.
			if not helmed:
				_contour(cv, hc, [
					[Vector2(-3.0, -2.8), Vector2(-3.2, -3.5), Vector2(-2.55, -4.1)],
					[Vector2(-2.55, -4.1), Vector2(-1.5, -4.6), Vector2(-0.5, -4.0)],
					[Vector2(-0.5, -4.0), Vector2(0.25, -3.85), Vector2(0.7, -3.1)],
					[Vector2(0.7, -3.1), Vector2(-0.75, -3.0), Vector2(-1.55, -3.3)],
					[Vector2(-1.55, -3.3), Vector2(-2.5, -3.0), Vector2(-3.0, -2.8)]], hair)
				cv.capsule(hc + Vector2(-2.7, -3.15), hc + Vector2(-2.3, -3.9), 0.15, light)
				cv.capsule(hc + Vector2(-1.95, -3.5), hc + Vector2(-1.6, -4.1), 0.16, hair.lightened(0.21))
				cv.capsule(hc + Vector2(-1.3, -3.6), hc + Vector2(-0.7, -3.8), 0.12, hair.lightened(0.14))
		1: # High mohawk: a tall narrow crest over shaved temples.
			if not helmed:
				_contour(cv, hc, [
					[Vector2(-2.9, -2.85), Vector2(-3.1, -4.45), Vector2(-2.0, -5.0)],
					[Vector2(-2.0, -5.0), Vector2(-1.0, -5.35), Vector2(-0.45, -4.5)],
					[Vector2(-0.45, -4.5), Vector2(0.7, -4.0), Vector2(0.9, -3.05)],
					[Vector2(0.9, -3.05), Vector2(-1.2, -3.15), Vector2(-2.9, -2.85)]], hair)
				cv.capsule(hc + Vector2(-2.6, -3.45), hc + Vector2(-2.1, -4.75), 0.16, light)
				cv.capsule(hc + Vector2(-1.65, -3.6), hc + Vector2(-1.25, -4.7), 0.16, light)
				cv.capsule(hc + Vector2(-0.75, -3.55), hc + Vector2(-0.65, -4.1), 0.13, light)
		2: # Topknot: exposed scalp below a pulled root and round knot.
			if not helmed:
				cv.capsule(hc + Vector2(-2.55, -2.9), hc + Vector2(-0.75, -3.3), 0.4, hair)
				cv.ellipse(hc + Vector2(-1.55, -3.85), 1.05, 0.8, hair)
				cv.ellipse(hc + Vector2(-1.25, -4.03), 0.56, 0.44, hair.lightened(0.18))
				cv.capsule(hc + Vector2(-2.2, -3.75), hc + Vector2(-2.9, -2.55), 0.38, hair.darkened(0.12))
				cv.capsule(hc + Vector2(-1.8, -3.7), hc + Vector2(-1.25, -3.6), 0.1, hair.darkened(0.35))
		3: # Short crop: close scalp coverage with a squared temple edge.
			if not helmed:
				_hair_cap(cv, hc, hair)
				cv.capsule(hc + Vector2(-2.85, -2.0), hc + Vector2(-2.7, -0.7), 0.45, hair)
				cv.capsule(hc + Vector2(-2.7, -2.0), hc + Vector2(-2.65, -1.0), 0.12, light)
		4: # Side sweep: a full crown and a curved forelock over the lateral brow.
			if not helmed:
				_hair_cap(cv, hc, hair)
				_contour(cv, hc, [
					[Vector2(-1.8, -3.4), Vector2(0.55, -3.95), Vector2(1.65, -2.8)],
					[Vector2(1.65, -2.8), Vector2(2.45, -1.8), Vector2(1.8, -1.15)],
					[Vector2(1.8, -1.15), Vector2(1.65, -2.25), Vector2(0.0, -2.65)],
					[Vector2(0.0, -2.65), Vector2(-1.1, -2.7), Vector2(-1.8, -3.4)]], hair)
				cv.capsule(hc + Vector2(-0.85, -3.2), hc + Vector2(0.7, -3.0), 0.17, light)
				cv.capsule(hc + Vector2(0.8, -2.95), hc + Vector2(1.7, -2.1), 0.15, light)
		5: # Ponytail: swept scalp and one broad curved tail hanging behind the neck.
			if not helmed:
				_hair_cap(cv, hc, hair)
			_contour(cv, hc, [
				[Vector2(-3.15, -1.8), Vector2(-4.8, -0.4), Vector2(-4.1, 2.0)],
				[Vector2(-4.1, 2.0), Vector2(-4.0, 3.8), Vector2(-3.25, 4.45)],
				[Vector2(-3.25, 4.45), Vector2(-3.2, 2.3), Vector2(-3.4, 0.65)],
				[Vector2(-3.4, 0.65), Vector2(-3.0, -0.9), Vector2(-3.15, -1.8)]], hair)
			cv.capsule(hc + Vector2(-3.9, -0.4), hc + Vector2(-3.85, 2.5), 0.15, light)
		6: # Single braid: a thick alternating plait down the back.
			if not helmed:
				_hair_cap(cv, hc, hair)
			_braid(cv, hc + Vector2(-3.45, -0.9), hc + Vector2(-3.5, 4.3), 0.56, hair)
		7: # Twin braids: distinct back and temple plaits with exposed scalp between.
			if not helmed:
				_hair_cap(cv, hc, hair)
			_braid(cv, hc + Vector2(-3.5, -0.75), hc + Vector2(-4.05, 4.25), 0.43, hair)
			_braid(cv, hc + Vector2(-2.3, -0.85), hc + Vector2(-1.85, 4.0), 0.43, hair)
		8: # Shoulder length: loose full hair, broad back curtain, two soft strands.
			if not helmed:
				_hair_cap(cv, hc, hair)
			_contour(cv, hc, [
				[Vector2(-3.1, -2.0), Vector2(-4.35, -0.4), Vector2(-4.15, 2.7)],
				[Vector2(-4.15, 2.7), Vector2(-3.8, 4.2), Vector2(-2.55, 4.4)],
				[Vector2(-2.55, 4.4), Vector2(-2.9, 2.4), Vector2(-2.5, 0.25)],
				[Vector2(-2.5, 0.25), Vector2(-2.65, -1.45), Vector2(-3.1, -2.0)]], hair)
			cv.capsule(hc + Vector2(-3.55, -0.1), hc + Vector2(-3.3, 3.6), 0.17, light)
			cv.capsule(hc + Vector2(-2.6, 0.6), hc + Vector2(-2.5, 2.9), 0.22, hair.lightened(0.13))
			cv.capsule(hc + Vector2(-3.8, 1.0), hc + Vector2(-3.75, 2.7), 0.13, dark)
		9: # Loose curls: clustered crown and short rounded side locks.
			if not helmed:
				for center: Vector2 in [Vector2(-2.9, -2.55), Vector2(-2.3, -3.3), Vector2(-1.35, -3.65),
					Vector2(-0.35, -3.6), Vector2(0.6, -3.2), Vector2(1.25, -2.65)]:
					cv.ellipse(hc + center, 0.73, 0.68, hair)
					cv.ellipse(hc + center + Vector2(-0.1, -0.12), 0.34, 0.28, light)
			for center: Vector2 in [Vector2(-3.1, -1.6), Vector2(-3.5, -0.7), Vector2(-3.55, 0.25),
				Vector2(-3.45, 1.2), Vector2(-3.15, 2.0)]:
				cv.ellipse(hc + center, 0.61, 0.58, hair)
				cv.ellipse(hc + center + Vector2(-0.07, -0.08), 0.24, 0.22, light)
	cv.end(FigurePainter.ol(hair), 0.045)

static func _beard_contour(cv: PixelCanvas, hc: Vector2, arcs: Array, color: Color, limit_y: float) -> void:
	var clipped: Array = []
	for arc: Array in arcs:
		var clipped_arc: Array = []
		for point: Vector2 in arc:
			clipped_arc.append(Vector2(point.x, minf(point.y, limit_y)))
		clipped.append(clipped_arc)
	_contour(cv, hc, clipped, color)

static func _beard_variant(f, hc: Vector2, style: int) -> void:
	if _female(f) or not bool(f.spec.get("beard", false)) or f._lost("head") or f._lost("jaw"):
		return
	if style == 6 and f._lost("mouth"):
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var light: Color = hair.lightened(0.18)
	var dark: Color = hair.darkened(0.23)
	var limit_y: float = 3.25 if f._lost("neck") else 4.65
	cv.begin()
	match style:
		1: # Close trimmed: thin, clean cheek edge and a narrow squared chin band.
			_beard_contour(cv, hc, [
				[Vector2(-1.55, 0.7), Vector2(-1.0, 1.1), Vector2(-0.8, 2.15)],
				[Vector2(-0.8, 2.15), Vector2(0.7, 2.85), Vector2(3.4, 2.35)],
				[Vector2(3.4, 2.35), Vector2(3.3, 3.12), Vector2(1.45, 3.3)],
				[Vector2(1.45, 3.3), Vector2(-0.45, 3.05), Vector2(-1.28, 2.1)],
				[Vector2(-1.28, 2.1), Vector2(-1.62, 1.25), Vector2(-1.55, 0.7)]], hair, limit_y)
			cv.capsule(hc + Vector2(-0.5, 2.56), hc + Vector2(1.2, 3.0), 0.12, light)
			cv.capsule(hc + Vector2(1.65, 3.0), hc + Vector2(2.95, 2.7), 0.11, light)
		2: # Round full: a broad rounded curtain with a convex bottom, no pointed tip.
			_beard_contour(cv, hc, [
				[Vector2(-1.65, 0.7), Vector2(-1.05, 1.1), Vector2(-0.7, 2.1)],
				[Vector2(-0.7, 2.1), Vector2(1.1, 2.75), Vector2(3.45, 2.15)],
				[Vector2(3.45, 2.15), Vector2(3.6, 3.5), Vector2(2.55, 4.0)],
				[Vector2(2.55, 4.0), Vector2(0.85, 4.65), Vector2(-0.45, 3.55)],
				[Vector2(-0.45, 3.55), Vector2(-1.7, 2.5), Vector2(-1.65, 0.7)]], hair, limit_y)
			_beard_contour(cv, hc, [
				[Vector2(-0.7, 2.35), Vector2(0.1, 2.85), Vector2(1.0, 3.05)],
				[Vector2(1.0, 3.05), Vector2(1.35, 3.7), Vector2(0.85, 3.95)],
				[Vector2(0.85, 3.95), Vector2(-0.35, 3.3), Vector2(-0.7, 2.35)]], light, limit_y)
			_beard_contour(cv, hc, [
				[Vector2(2.15, 2.7), Vector2(2.85, 2.55), Vector2(3.15, 2.4)],
				[Vector2(3.15, 2.4), Vector2(3.15, 3.55), Vector2(2.2, 3.95)],
				[Vector2(2.2, 3.95), Vector2(2.45, 3.15), Vector2(2.15, 2.7)]], dark, limit_y)
		3: # Pointed: tight cheek roots descend into one long central tapered tip.
			_beard_contour(cv, hc, [
				[Vector2(-1.45, 0.75), Vector2(-0.9, 1.2), Vector2(-0.65, 2.1)],
				[Vector2(-0.65, 2.1), Vector2(1.0, 2.8), Vector2(3.35, 2.2)],
				[Vector2(3.35, 2.2), Vector2(2.8, 3.7), Vector2(1.35, 4.62)],
				[Vector2(1.35, 4.62), Vector2(0.15, 3.7), Vector2(-0.8, 2.85)],
				[Vector2(-0.8, 2.85), Vector2(-1.55, 1.8), Vector2(-1.45, 0.75)]], hair, limit_y)
			_beard_contour(cv, hc, [
				[Vector2(-0.45, 2.45), Vector2(0.35, 2.85), Vector2(1.1, 3.0)],
				[Vector2(1.1, 3.0), Vector2(1.05, 3.7), Vector2(1.35, 4.45)],
				[Vector2(1.35, 4.45), Vector2(0.1, 3.35), Vector2(-0.45, 2.45)]], light, limit_y)
		4: # Forked: two separate lower points with a visible central notch.
			_beard_contour(cv, hc, [
				[Vector2(-1.5, 0.7), Vector2(-0.95, 1.1), Vector2(-0.65, 2.15)],
				[Vector2(-0.65, 2.15), Vector2(1.05, 2.8), Vector2(3.4, 2.15)],
				[Vector2(3.4, 2.15), Vector2(3.55, 3.55), Vector2(2.7, 4.5)],
				[Vector2(2.7, 4.5), Vector2(1.8, 3.8), Vector2(1.55, 3.45)],
				[Vector2(1.55, 3.45), Vector2(1.0, 4.05), Vector2(0.6, 4.5)],
				[Vector2(0.6, 4.5), Vector2(-0.5, 3.5), Vector2(-1.15, 2.3)],
				[Vector2(-1.15, 2.3), Vector2(-1.55, 1.4), Vector2(-1.5, 0.7)]], hair, limit_y)
			_beard_contour(cv, hc, [
				[Vector2(-0.5, 2.45), Vector2(0.2, 2.8), Vector2(0.9, 3.15)],
				[Vector2(0.9, 3.15), Vector2(0.45, 3.55), Vector2(0.6, 4.3)],
				[Vector2(0.6, 4.3), Vector2(-0.25, 3.4), Vector2(-0.5, 2.45)]], light, limit_y)
			_beard_contour(cv, hc, [
				[Vector2(2.3, 2.8), Vector2(3.0, 2.55), Vector2(3.2, 2.4)],
				[Vector2(3.2, 2.4), Vector2(3.1, 3.5), Vector2(2.7, 4.3)],
				[Vector2(2.7, 4.3), Vector2(2.8, 3.45), Vector2(2.3, 2.8)]], dark, limit_y)
		5: # Braided: a full jaw band gathered into one plait, tied only by its hair.
			_beard_contour(cv, hc, [
				[Vector2(-1.5, 0.7), Vector2(-0.95, 1.2), Vector2(-0.65, 2.15)],
				[Vector2(-0.65, 2.15), Vector2(1.2, 2.85), Vector2(3.4, 2.2)],
				[Vector2(3.4, 2.2), Vector2(2.8, 3.15), Vector2(1.55, 3.25)],
				[Vector2(1.55, 3.25), Vector2(-0.2, 3.25), Vector2(-1.1, 2.25)],
				[Vector2(-1.1, 2.25), Vector2(-1.55, 1.3), Vector2(-1.5, 0.7)]], hair, limit_y)
			_braid(cv, hc + Vector2(1.5, 2.95), hc + Vector2(1.65, minf(4.22, limit_y - 0.4)), 0.38, hair)
		6: # Moustache: only the upper-lip hair, with two rounded hanging corners.
			_contour(cv, hc, [
				[Vector2(0.35, 1.18), Vector2(0.9, 0.85), Vector2(1.75, 1.07)],
				[Vector2(1.75, 1.07), Vector2(2.7, 0.85), Vector2(3.4, 1.17)],
				[Vector2(3.4, 1.17), Vector2(3.65, 1.6), Vector2(3.3, 1.9)],
				[Vector2(3.3, 1.9), Vector2(3.15, 1.35), Vector2(1.75, 1.5)],
				[Vector2(1.75, 1.5), Vector2(0.75, 1.38), Vector2(0.15, 1.7)],
				[Vector2(0.15, 1.7), Vector2(0.12, 1.4), Vector2(0.35, 1.18)]], hair)
			cv.capsule(hc + Vector2(0.55, 1.23), hc + Vector2(1.35, 1.23), 0.1, light)
			cv.capsule(hc + Vector2(2.13, 1.22), hc + Vector2(3.08, 1.25), 0.1, light)
		7: # Stubble: low soft growth follows the skin without a protruding hair curtain.
			var stubble: Color = (f.skin as Color).lerp(hair, 0.38)
			_contour(cv, hc, [
				[Vector2(-1.35, 0.65), Vector2(-0.6, 1.15), Vector2(-0.4, 2.1)],
				[Vector2(-0.4, 2.1), Vector2(1.0, 2.7), Vector2(3.4, 2.35)],
				[Vector2(3.4, 2.35), Vector2(3.2, 3.03), Vector2(1.25, 3.08)],
				[Vector2(1.25, 3.08), Vector2(-0.2, 2.78), Vector2(-1.1, 1.95)],
				[Vector2(-1.1, 1.95), Vector2(-1.5, 1.25), Vector2(-1.35, 0.65)]], stubble)
			for point: Vector2 in [Vector2(-0.85, 1.7), Vector2(-0.45, 2.1), Vector2(0.1, 2.5),
				Vector2(0.8, 2.78), Vector2(1.65, 2.85), Vector2(2.4, 2.68), Vector2(2.95, 2.53)]:
				cv.ellipse(hc + point, 0.09, 0.13, stubble.lerp(hair, 0.27))
	if style == 7:
		cv.end(Color(0, 0, 0, 0), 0.0)
	else:
		cv.end(FigurePainter.ol(hair), 0.045)

static func _beard(cv: PixelCanvas, hc: Vector2, hair: Color, seed: int) -> void:
	var end_y: float = 4.1 if posmod(int(seed / 20), 2) == 0 else 3.45
	cv.begin()
	_poly(cv, hc, [Vector2(-1.85, 0.65), Vector2(-1.15, 1.15), Vector2(-0.7, 2.4),
		Vector2(1.25, 2.9), Vector2(3.55, 2.5), Vector2(3.2, 3.1),
		Vector2(1.7, end_y), Vector2(0.2, end_y - 0.4), Vector2(-1.25, 2.9)], hair)
	_poly(cv, hc, [Vector2(-1.4, 1.3), Vector2(-0.65, 2.55), Vector2(0.8, 3.25),
		Vector2(1.3, end_y - 0.25), Vector2(0.45, end_y - 0.35), Vector2(-0.9, 2.8)], hair.lightened(0.17))
	_poly(cv, hc, [Vector2(1.45, 3.1), Vector2(3.2, 2.85), Vector2(2.3, 3.6),
		Vector2(1.7, end_y)], hair.darkened(0.22))
	cv.end(FigurePainter.ol(hair), 0.05)

static func _tusk(cv: PixelCanvas, base: Vector2, width: float, height: float, near: bool) -> void:
	cv.begin()
	_contour(cv, base, [
		[Vector2(-width * 0.5, 0.02), Vector2(-width * 0.48, -height * 0.34), Vector2(-width * 0.05, -height * 0.58)],
		[Vector2(-width * 0.05, -height * 0.58), Vector2(width * 0.22, -height * 0.87), Vector2(width * 0.95, -height)],
		[Vector2(width * 0.95, -height), Vector2(width * 1.03, -height * 0.71), Vector2(width * 0.7, -height * 0.48)],
		[Vector2(width * 0.7, -height * 0.48), Vector2(width * 0.32, -height * 0.23), Vector2(width * 0.5, 0.0)],
		[Vector2(width * 0.5, 0.0), Vector2(0.0, 0.1), Vector2(-width * 0.5, 0.02)]], Color("#b8a36f"))
	_contour(cv, base, [
		[Vector2(-width * 0.26, -0.2), Vector2(-width * 0.25, -height * 0.35), Vector2(width * 0.1, -height * 0.57)],
		[Vector2(width * 0.1, -height * 0.57), Vector2(width * 0.35, -height * 0.88), Vector2(width * 0.95, -height)],
		[Vector2(width * 0.95, -height), Vector2(width * 0.82, -height * 0.74), Vector2(width * 0.48, -height * 0.5)],
		[Vector2(width * 0.48, -height * 0.5), Vector2(width * 0.13, -height * 0.28), Vector2(width * 0.22, -0.17)],
		[Vector2(width * 0.22, -0.17), Vector2(0.0, -0.12), Vector2(-width * 0.26, -0.2)]], Color("#f1e4bb") if near else Color("#d9cba2"))
	cv.end(Color("#514833"), 0.025)

static func torso(f) -> bool:
	var cv: PixelCanvas = f.cv
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var female: bool = _female(f)
	var half: float = float(f.tw) * (0.45 if female else 0.5)
	var waist: float = float(f.hipw) * (0.34 if female else 0.44)
	var skin: Color = f.skin
	var lower: Vector2 = hip - sc
	cv.begin()
	_contour(cv, sc, [
		[Vector2(-half - 0.25, 1.45), Vector2(-half - 0.7, 0.1), Vector2(-2.1, -0.4)],
		[Vector2(-2.1, -0.4), Vector2(-1.1, -1.0), Vector2(0.1, -0.7)],
		[Vector2(0.1, -0.7), Vector2(1.1, -0.8), Vector2(2.0, -0.25)],
		[Vector2(2.0, -0.25), Vector2(half + 0.75, 0.15), Vector2(half + 0.2, 1.65)],
		[Vector2(half + 0.2, 1.65), Vector2(half - 0.5, 3.7), lower + Vector2(waist, 0.8)],
		[lower + Vector2(waist, 0.8), lower + Vector2(0.0, 1.1), lower + Vector2(-waist, 0.8)],
		[lower + Vector2(-waist, 0.8), Vector2(-half + 0.2, 3.75), Vector2(-half - 0.25, 1.45)]], skin)
	_contour(cv, sc, [
		[Vector2(-half - 0.25, 1.45), Vector2(-half - 0.7, 0.1), Vector2(-2.1, -0.4)],
		[Vector2(-2.1, -0.4), Vector2(-1.4, 1.3), Vector2(-1.2, 2.5)],
		[Vector2(-1.2, 2.5), lower + Vector2(-0.8, -1.0), lower + Vector2(-waist, 0.8)],
		[lower + Vector2(-waist, 0.8), Vector2(-half + 0.2, 3.75), Vector2(-half - 0.25, 1.45)]], skin.darkened(0.23))
	# Pectoral bellies and a short clavicle turn into the rounded deltoid/trapezius.
	_contour(cv, sc, [
		[Vector2(-0.85, 0.35), Vector2(0.55, -0.1), Vector2(half - 0.1, 0.9)],
		[Vector2(half - 0.1, 0.9), Vector2(half + 0.1, 1.8), Vector2(1.25, 2.25)],
		[Vector2(1.25, 2.25), Vector2(0.15, 2.55), Vector2(-0.8, 1.65)],
		[Vector2(-0.8, 1.65), Vector2(-1.1, 0.7), Vector2(-0.85, 0.35)]], skin.lightened(0.16))
	cv.capsule(sc + Vector2(0.05, 0.25), sc + Vector2(2.5, 0.55), 0.16, skin.lightened(0.21))
	cv.capsule(sc + Vector2(-1.35, 0.7), sc + Vector2(-1.1, 2.0), 0.15, skin.darkened(0.19))
	_contour(cv, sc, [
		[Vector2(0.1, 2.2), Vector2(1.75, 2.65), Vector2(half - 0.1, 1.75)],
		[Vector2(half - 0.1, 1.75), Vector2(half - 0.25, 2.8), Vector2(1.6, 2.8)],
		[Vector2(1.6, 2.8), Vector2(0.4, 2.75), Vector2(0.1, 2.2)]], skin.darkened(0.13))
	f._skin_end()
	if not f._it("body").is_empty() or not f._it("clothing").is_empty():
		return _wardrobe_torso(f)
	return true

static func _limb(cv: PixelCanvas, a: Vector2, b: Vector2, ra: float, rb: float, color: Color) -> void:
	var direction: Vector2 = (b - a).normalized()
	var normal: Vector2 = Vector2(direction.y, -direction.x)
	var bulge: Vector2 = a.lerp(b, 0.34)
	var narrow: Vector2 = a.lerp(b, 0.8)
	# Rounded deltoid/proximal forearm bellies taper smoothly into the joint or wrist.
	_contour(cv, Vector2.ZERO, [
		[a - normal * ra, a - direction * ra, a + normal * ra],
		[a + normal * ra, bulge + normal * (ra * 1.17), narrow + normal * rb],
		[narrow + normal * rb, b + direction * (rb * 0.6) + normal * rb, b + direction * (rb * 0.65)],
		[b + direction * (rb * 0.65), b - normal * rb, narrow - normal * rb],
		[narrow - normal * rb, bulge - normal * (ra * 1.06), a - normal * ra]], color)
	_contour(cv, Vector2.ZERO, [
		[a + normal * (ra * 0.2), bulge + normal * (ra * 0.75), narrow + normal * (rb * 0.25)],
		[narrow + normal * (rb * 0.25), b + normal * (rb * 0.08), narrow - normal * (rb * 0.08)],
		[narrow - normal * (rb * 0.08), bulge + normal * (ra * 0.12), a + normal * (ra * 0.2)]], color.lightened(0.17))
	_contour(cv, Vector2.ZERO, [
		[a - normal * (ra * 0.85), bulge - normal * ra, narrow - normal * rb],
		[narrow - normal * rb, b - normal * (rb * 0.5), narrow - normal * (rb * 0.42)],
		[narrow - normal * (rb * 0.42), bulge - normal * (ra * 0.35), a - normal * (ra * 0.85)]], color.darkened(0.2))

static func arm(f, side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var shoulder: Vector2 = f.j["s" + side]
	var elbow: Vector2 = f.j["e" + side]
	var hand: Vector2 = f.j["h" + side]
	var radius: float = float(f.arm_r) * (0.9 if _female(f) else 1.0)
	var skin: Color = f.skin
	if f._lost("arm_upper_" + side):
		cv.dot(shoulder, FigurePainter.BLOOD)
		return true
	var lower_lost: bool = f._lost("arm_lower_" + side)
	var hand_lost: bool = f._lost("hand_" + side)
	cv.begin()
	_limb(cv, shoulder, elbow, radius * 1.12, radius * 0.8, skin)
	if not lower_lost:
		_limb(cv, elbow, hand, radius * 0.96, radius * 0.66, skin)
		if not hand_lost:
			cv.ellipse(hand, radius + 0.25, radius + 0.25, skin)
			cv.ellipse(hand + Vector2(-0.15, -0.25), radius * 0.7, radius * 0.55, skin.lightened(0.16))
	f._skin_end()
	_wardrobe_sleeve(f,side,shoulder,elbow,radius)
	_wardrobe_bracer(f,side,elbow,hand,radius)
	if lower_lost:
		cv.dot(elbow, FigurePainter.BLOOD)
	elif hand_lost:
		cv.dot(hand, FigurePainter.BLOOD)
	return true

static func leg(f, side: String) -> bool:
	if f._it("legs_under").is_empty() and f._it("legs").is_empty() and f._it("feet").is_empty():
		return false
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p"+side]
	var kn: Vector2 = f.j["k"+side]
	var ft: Vector2 = f.j["f"+side]
	var r: float = float(f.leg_r)
	if f._lost("leg_upper_"+side):
		cv.dot(hp,FigurePainter.BLOOD)
		return true
	var trousers: bool = not f._it("legs_under").is_empty()
	var color: Color = f._trouser_col() if trousers else f.skin
	var lower_lost: bool = f._lost("leg_lower_"+side)
	var foot_lost: bool = f._lost("foot_"+side)
	cv.begin()
	cv.capsule(hp,kn,r,color)
	if not lower_lost:
		cv.capsule(kn,ft,r*0.9,color)
		if not foot_lost:
			cv.rect(Rect2(ft+Vector2(-1.2,-0.5),Vector2(3.4*float(f.gs),2.0)),f.skin)
	if trousers:
		cv.end(FigurePainter.ol(color),0.12)
	else:
		f._skin_end()
	_wardrobe_leg_layers(f,side,hp,kn,ft,r)
	if lower_lost:
		cv.dot(kn,FigurePainter.BLOOD)
	elif foot_lost:
		cv.dot(ft,FigurePainter.BLOOD)
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


static func helm_horns(f, hc: Vector2, top: float, m: Dictionary) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var span: float = float(f.head_w)*0.46
	# The caller selects the actual maker culture; the wearer does not select the horns.
	for index: int in range(2):
		var near: bool = index == 1
		var direction: float = 1.0 if near else -1.0
		var size: float = 1.0 if near else 0.72
		var root: Vector2 = hc+Vector2(span*direction,top+(0.22 if near else 0.3))
		var metal_base: Color = m["base"]
		var metal_dark: Color = m["dark"]
		var metal_light: Color = m["light"]
		var metal_outline: Color = m["outline"]
		cv.begin()
		# A rounded riveted socket sits on the side shell, beneath the broad horn root.
		cv.ellipse(root,0.57*size,0.64*size,metal_dark)
		cv.ellipse(root+Vector2(-0.08,-0.07)*size,0.44*size,0.48*size,metal_base)
		cv.capsule(root+Vector2(-0.27,-0.34)*size,root+Vector2(0.15,-0.37)*size,
			0.095*size,metal_light)
		cv.ellipse(root+Vector2(-direction*0.36,0.3)*size,0.11*size,0.11*size,m["trim"])
		cv.end(metal_outline,0.035)
		var arcs: Array = [
			[Vector2(-0.1,0.38),Vector2(0.95,0.48),Vector2(1.54,-0.25)],
			[Vector2(1.54,-0.25),Vector2(2.03,-0.85),Vector2(1.72,-1.65)],
			[Vector2(1.72,-1.65),Vector2(1.67,-0.95),Vector2(1.03,-0.6)],
			[Vector2(1.03,-0.6),Vector2(0.53,-0.28),Vector2(-0.09,-0.43)],
			[Vector2(-0.09,-0.43),Vector2(-0.2,0.0),Vector2(-0.1,0.38)]]
		for arc: Array in arcs:
			for point_index: int in range(3):
				var point: Vector2 = arc[point_index]
				arc[point_index] = Vector2(point.x*direction,point.y)*size
		cv.begin()
		_contour(cv,root,arcs,Color("#c5b084") if near else Color("#ad9870"))
		var light_arcs: Array = [
			[Vector2(0.08,0.25),Vector2(0.92,0.27),Vector2(1.4,-0.28)],
			[Vector2(1.4,-0.28),Vector2(1.83,-0.89),Vector2(1.72,-1.65)],
			[Vector2(1.72,-1.65),Vector2(1.58,-1.1),Vector2(1.14,-0.7)],
			[Vector2(1.14,-0.7),Vector2(0.6,-0.39),Vector2(0.08,-0.3)],
			[Vector2(0.08,-0.3),Vector2(0.13,-0.07),Vector2(0.08,0.25)]]
		for arc: Array in light_arcs:
			for point_index: int in range(3):
				var point: Vector2 = arc[point_index]
				arc[point_index] = Vector2(point.x*direction,point.y)*size
		_contour(cv,root,light_arcs,Color("#eee1bd") if near else Color("#d4c59f"))
		cv.capsule(root+Vector2(0.2*direction,0.25)*size,
			root+Vector2(0.77*direction,-0.03)*size,0.1*size,Color("#9a845b"))
		cv.end(Color("#514831"),0.035)
		# A short metal collar closes the socket over the attached ivory root.
		cv.begin()
		cv.poly(PackedVector2Array([root+Vector2(-0.12*direction,-0.4)*size,
			root+Vector2(0.15*direction,-0.36)*size,root+Vector2(0.24*direction,0.33)*size,
			root+Vector2(-0.08*direction,0.39)*size]),metal_base)
		cv.capsule(root+Vector2(-0.04*direction,-0.33)*size,
			root+Vector2(0.02*direction,0.29)*size,0.085*size,metal_light)
		cv.end(metal_outline,0.025)
