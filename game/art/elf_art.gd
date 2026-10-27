class_name ElfArt
extends RefCounted
## Sculpted elf paperdoll surfaces. All geometry follows FigurePainter's existing joints.
## Gear is drawn from the supplied spec; wounds remain FigurePainter's final layer.

static var _force_legacy_v064: bool = false

static func _poly(cv: PixelCanvas, origin: Vector2, points: Array, c: Color, pat: Callable = Callable()) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for p in points:
		pts.append(origin + Vector2(float(p[0]), float(p[1])))
	cv.poly(pts, c, pat)

static func _stroke(cv: PixelCanvas, origin: Vector2, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	cv.capsule(origin + a, origin + b, width, c)

# Rounded contours are sampled once per outline, then rasterized on the shared pixel grid.
static func _contour(cv: PixelCanvas, origin: Vector2, points: Array, c: Color, pat: Callable = Callable()) -> void:
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
	cv.poly(pts,c,pat)

static func _path(cv: PixelCanvas, origin: Vector2, points: Array, r: float, c: Color) -> void:
	for i in points.size()-1:
		_stroke(cv,origin,Vector2(float(points[i][0]),float(points[i][1])),Vector2(float(points[i+1][0]),float(points[i+1][1])),r,c)

static func _hair_pat(f, hc: Vector2) -> Callable:
	var inverse: Transform2D = f.cv.xf.affine_inverse()
	return func(x: int, y: int, c: Color) -> Color:
		var q: Vector2 = inverse * Vector2(x + 0.5, y + 0.5) - hc
		if q.x < -2.7: return c.darkened(0.13)
		if q.y < -3.1 and q.x < 0.0: return c.lightened(0.08)
		return c

static func _face_pat(f, hc: Vector2, _race: String) -> Callable:
	var inverse: Transform2D = f.cv.xf.affine_inverse()
	return func(x: int, y: int, c: Color) -> Color:
		var q: Vector2 = inverse * Vector2(x + 0.5, y + 0.5) - hc
		# Broad quiet planes, avoiding the old triangular cheek patches.
		var shade: float = clampf((-q.x-0.45)*0.065,0.0,0.15)
		shade += clampf((q.y-1.6)*0.065,0.0,0.09)
		if q.x>1.65: shade+=0.06
		if q.y>-0.1 and q.y<0.8 and q.x>-0.3 and q.x<0.45:
			return c.lightened(0.09)
		if q.y < -1.6 and q.x < 0.8: return c.lightened(0.05)
		return c.darkened(shade)

static func head(f) -> void:
	if f._lost("head"):
		return
	if _force_legacy_v064:
		_legacy_head(f)
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var race: String = String(f.spec.get("race", "moon_elf"))
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = absi(int(f.spec.get("seed", 0)))
	var style: int = seed % 6
	var female: bool = String(f.spec.get("sex", "")).to_lower() in ["female", "f", "woman"]
	var fvar: int = FigurePainter.female_variant(f.spec) if female else 0
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead", false))
	var jaw_lost: bool = f._lost("jaw")
	var coif: bool = String(f._it("helm").get("sprite", "")) == "coif"
	var helm_open: bool = f._it("helm").is_empty() or String(f._it("helm").get("sprite", "")) in ["crown", "circlet"]

	var sh := cv.shaded()
	var c_skin: int = sh.add_color(skin, 0.14, 1.06)
	var c_skin_d: int = c_skin
	var c_skin_l: int = c_skin
	var c_hair: int = sh.add_color(hair, 0.22, 1.12, hair.lightened(0.35))
	var c_hair_d: int = c_hair
	var c_hair_l: int = c_hair
	var clasp_col: Color = Color("#e8c860") if race == "high_elf" else (Color("#a8d4f0") if race == "moon_elf" else Color("#9e78c8"))
	var c_clasp: int = sh.add_color(clasp_col, 0.36, 1.18, clasp_col.lightened(0.35))

	# Flowing elven back hair behind neck & shoulders
	if not coif:
		if female:
			sh.capsule(hc + Vector2(-1.45, -0.55), hc + Vector2(-2.25, 4.35), 1.25, 0.92, c_hair_d, -1.8, 0.95)
			sh.capsule(hc + Vector2(-0.65, 0.35), hc + Vector2(-1.35, 4.75), 0.95, 0.65, c_hair, -1.4, 0.95)
			if fvar == 1 or style in [2, 3]:
				sh.capsule(hc + Vector2(-2.15, -1.15), hc + Vector2(-3.15, 3.85), 0.95, 0.55, c_hair_l, -1.2, 0.95)
		elif style in [1, 2, 3, 4]:
			sh.capsule(hc + Vector2(-1.55, -0.55), hc + Vector2(-2.35, 4.15), 1.12, 0.78, c_hair_d, -1.8, 0.95)
			if style == 3:
				sh.capsule(hc + Vector2(-2.25, -1.05), hc + Vector2(-3.25, 3.95), 0.88, 0.52, c_hair, -1.4, 0.95)
			elif style == 4:
				for bi in 4:
					sh.ellipsoid(hc + Vector2(1.85, 0.25 + float(bi) * 0.75), 0.44, 0.38, c_hair, -1.2, 0.9)

	# Sculpted angular V-tapered elven cranium & jaw
	var jaw_y: float = 2.25 if not female else 2.12
	var skull_pts := PackedVector2Array([
		hc + Vector2(-2.15, -1.65), hc + Vector2(-1.35, -2.95), hc + Vector2(0.45, -3.02),
		hc + Vector2(1.75, -2.25), hc + Vector2(2.02, -0.85), hc + Vector2(1.98, 0.35),
		hc + Vector2(1.42 if not jaw_lost else 1.35, jaw_y if not jaw_lost else 0.75),
		hc + Vector2(0.55, (jaw_y + 0.18) if not jaw_lost else 0.85),
		hc + Vector2(-0.85, 1.75 if not jaw_lost else 0.75),
		hc + Vector2(-1.95, 0.75), hc + Vector2(-2.22, -0.35)
	])
	sh.poly(skull_pts, c_skin, 0.0, 1.95)
	sh.ellipsoid(hc + Vector2(-0.12, -0.85), 2.12, 2.08, c_skin, 0.3, 1.1)
	if not jaw_lost:
		sh.capsule(hc + Vector2(-0.45, 1.15), hc + Vector2(0.95, jaw_y - 0.22), 1.12 if not female else 0.98, 0.78 if not female else 0.68, c_skin, 0.5, 0.95)
	# High elven cheekbone & fine straight aristocratic nose bridge
	sh.ellipsoid(hc + Vector2(0.88, -0.05), 0.96, 0.72, c_skin_l, 1.1, 0.85)
	if not f._lost("nose"):
		var n_tip := hc + Vector2(2.22 if not female else 2.08, 0.12)
		sh.capsule(hc + Vector2(1.58, -0.92), n_tip, 0.34, 0.38, c_skin_l, 2.0, 0.95)

	# Signature long swept pointed elven ears (subrace cant & length)
	var ear_tip: Vector2 = Vector2(-4.45, -1.35)
	var far_tip: Vector2 = Vector2(2.85, -1.65)
	if race == "high_elf":
		ear_tip = Vector2(-4.15, -1.95)
		far_tip = Vector2(2.65, -2.05)
	elif race == "dark_elf":
		ear_tip = Vector2(-4.35, -1.65)
		far_tip = Vector2(2.75, -1.85)
	if not coif and not f._lost("ear_l"):
		sh.capsule(hc + Vector2(1.55, -0.65), hc + far_tip, 0.34, 0.12, c_skin_d, -0.8, 0.75)
	if not coif and not f._lost("ear_r"):
		sh.capsule(hc + Vector2(-1.35, -0.10), hc + ear_tip, 0.56, 0.14, c_skin_l, 2.2, 0.95)
		sh.capsule(hc + Vector2(-1.55, -0.05), hc + ear_tip * 0.78, 0.24, 0.08, c_skin_d, 2.3, 0.65)

	# Silken crown hair, braids & temple locks
	if not coif and helm_open:
		var peak_y: float = -3.35 if race == "high_elf" else (-3.50 if race == "dark_elf" else -3.42)
		sh.ellipsoid(hc + Vector2(-0.35, -2.25), 2.25, 1.18, c_hair, 1.6, 1.0)
		sh.capsule(hc + Vector2(-2.05, -1.65), hc + Vector2(0.15, peak_y + 0.55), 0.78, 0.68, c_hair_l, 2.1, 0.95)
		sh.capsule(hc + Vector2(0.15, peak_y + 0.55), hc + Vector2(1.85, -2.15), 0.68, 0.52, c_hair, 2.0, 0.95)
		if female or style in [1, 2, 4]:
			sh.capsule(hc + Vector2(-2.05, -1.05), hc + Vector2(-2.25, 2.65 if style != 4 else 3.85), 0.58, 0.42, c_hair_l, 1.9, 0.95)
			if style == 4 or (female and fvar == 1):
				sh.capsule(hc + Vector2(-2.45, 2.55), hc + Vector2(-1.95, 2.55), 0.20, 0.20, c_clasp, 2.3, 0.9)
		elif style == 5:
			sh.capsule(hc + Vector2(-1.35, -2.75), hc + Vector2(1.25, -3.25), 0.85, 0.65, c_hair_l, 2.3, 1.0)

	sh.composite(FigurePainter.ol(skin), true)

	# Luminous slanted elven eyes & fine lips
	var eye_c: Color = Color("#3aa0ff") if race == "high_elf" else (Color("#ff4040") if race == "dark_elf" else Color("#7fe0ff"))
	var brow_c: Color = hair.darkened(0.32).lerp(Color("#1e1624"), 0.35)
	_eye(f, hc, Vector2(0.05, -0.58), 1.05, eye_c, brow_c, dead, "eye_r")
	_eye(f, hc, Vector2(1.48, -0.68), 0.56, eye_c, brow_c, dead, "eye_l")
	if not jaw_lost and not f._lost("mouth"):
		var lip_c: Color = skin.darkened(0.24).lerp(Color("#944258" if race != "dark_elf" else "#5e344e"), 0.45 if female else 0.28)
		cv.capsule(hc + Vector2(0.42, 1.24), hc + Vector2(1.45, 1.20), 0.13, lip_c)

	f._helm(hc, -float(f.head_w) * 0.5, float(f.head_w) * 0.5, -float(f.head_h) * 0.5, float(f.head_h) * 0.5)

static func _legacy_head(f) -> void:
	if String(f.spec.get("sex", "")).to_lower() in ["female","f","woman"]:
		_female_head(f)
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var race: String = String(f.spec.get("race", "moon_elf"))
	var seed: int = posmod(int(f.spec.get("seed", 0)), 12)
	var female: bool = String(f.spec.get("sex", "")).to_lower() in ["female","f","woman"]
	var male: bool = String(f.spec.get("sex", "")).to_lower() in ["male","m","man"]
	var age: int = int(f.spec.get("age", 40))
	var skin: Color = f.skin
	var hair: Color = f.hair
	var plane: Color = skin.darkened(0.20)
	var deep: Color = skin.darkened(0.45)
	var brow: Color = hair.darkened(0.32).lerp(deep, 0.56)
	var eye: Color = Color(f.ra.get("eye", "#7fe0ff"))
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead", false))
	var hairstyle: int = posmod(int(f.spec.get("seed",0)),6)
	var jaw: float = (0.10 if male else (-0.10 if female else 0.0)) + float(seed%3-1)*0.055
	var moon: bool = race == "moon_elf"
	_hair_back(f,hc,race,hairstyle)
	# The neck is attached to the original shoulder joint, with a visible jaw break.
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-0.75,1.8),hc+Vector2(1.2,1.85),sc+Vector2(1.2,0.9),sc+Vector2(-1.05,0.55)]),plane)
		cv.end(FigurePainter.ol(skin),0.06)
	# Only the back edge of the far ear is exposed in this three-quarter angle.
	cv.begin()
	if not f._lost("ear_l"):
		_contour(cv,hc,[[1.6,-1.0],[2.45,-1.45],[2.2,-0.25],[1.8,0.1]],plane)
	var tip: Vector2 = Vector2(-3.8,-1.95)
	if race == "high_elf": tip=Vector2(-3.6,-2.2)
	elif race == "dark_elf": tip=Vector2(-3.65,-2.35)
	if not f._lost("ear_r"):
		_poly(cv,hc,[[-1.85,-0.9],[-2.3,-1.1],[tip.x,tip.y],[-3.05,-0.2],[-2.45,0.48],[-1.8,0.2]],skin)
	cv.end(FigurePainter.ol(skin),0.06)
	if not f._lost("ear_r"):
		_contour(cv,hc,[[-2.05,-0.6],[tip.x+0.45,tip.y+0.38],[-2.9,-0.2],[-2.35,0.18]],plane)
		_path(cv,hc,[[-2.1,-0.63],[-2.6,-0.85],[-3.12,-1.22]],0.10,skin.lightened(0.15))
	# Adult oval: full temples and cheek transitions, rounded chin instead of a point.
	var cheek: float = 2.05 if moon else 2.0
	cv.begin()
	_contour(cv,hc,[[-2.05,-1.75],[-1.6,-2.8],[-0.3,-3.1],[1.0,-2.95],[1.9,-2.2],[2.15,-1.05],[2.08,0.15],[cheek,0.9],[1.66,1.9],[1.0+jaw,2.65],[0.1-jaw,2.7],[-0.95-jaw,2.3],[-1.75,1.25],[-2.08,0.1]],skin,_face_pat(f,hc,race))
	cv.end(FigurePainter.ol(skin),0.06)
	# Rounded cheek lighting and quiet jaw shadow keep the face dimensional.
	_contour(cv,hc,[[-1.3,-0.12],[-0.25,-0.05],[0.25,0.5],[-0.15,0.92],[-1.0,0.82],[-1.48,0.35]],skin.lightened(0.10))
	_contour(cv,hc,[[-1.5,0.7],[-0.9,1.3],[-0.2,1.95],[0.8,2.45],[-0.1,2.45],[-0.95,2.1]],skin.darkened(0.09))
	if not f._lost("nose"):
		_contour(cv,hc,[[0.65,-1.17],[0.92,-0.95],[1.0,-0.25],[1.52,0.12],[1.5,0.43],[1.1,0.62],[0.68,0.42],[0.61,0.0]],skin.lightened(0.07))
		_path(cv,hc,[[0.73,-0.83],[0.85,-0.18],[1.16,0.12]],0.11,skin.lightened(0.20))
		_path(cv,hc,[[0.76,0.43],[1.05,0.53],[1.37,0.39]],0.10,plane)
	# Unequal almond eyes agree with the nose bridge and the face angle.
	_eye(f,hc,Vector2(-0.42,-0.88),1.16,eye,brow,dead,"eye_r")
	_eye(f,hc,Vector2(1.33,-0.94),0.68,eye.darkened(0.10),brow,dead,"eye_l")
	var brow_r: float = 0.11 if female else 0.14
	var arch: float = -0.10 if race=="high_elf" else 0.0
	_path(cv,hc,[[-1.08,-1.43],[-0.62,-1.61+arch],[-0.05,-1.62],[0.15,-1.5]],brow_r,brow)
	_path(cv,hc,[[1.04,-1.55],[1.35,-1.65+arch],[1.65,-1.58]],brow_r*0.82,brow)
	if not f._lost("mouth"):
		var lip: Color = skin.darkened(0.31).lerp(Color("#763b52"),0.13)
		_path(cv,hc,[[0.14,1.44],[0.54,1.37],[0.80,1.43],[1.38,1.39]],0.12,lip)
		_contour(cv,hc,[[0.35,1.62],[0.74,1.73],[1.12,1.62],[0.77,1.57]],skin.lightened(0.14))
		_path(cv,hc,[[0.30,1.97],[0.8,2.06],[1.15,1.97]],0.08,plane)
	if age>=240:
		_path(cv,hc,[[-1.0,-0.31],[-0.85,-0.12],[-0.5,-0.05]],0.07,plane)
		_path(cv,hc,[[1.35,0.68],[1.45,0.98],[1.37,1.17]],0.07,plane)
	_hair_front(f,hc,race,hairstyle)
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

# Original adult female anatomy uses the same joints, palettes and six hair choices.
# No costume or new equipment is introduced; the real item layers still draw over it.
static func _female_face_pat(f,hc: Vector2) -> Callable:
	var inverse: Transform2D = f.cv.xf.affine_inverse()
	return func(x: int,y: int,c: Color) -> Color:
		var q: Vector2 = inverse*Vector2(float(x)+0.5,float(y)+0.5)-hc
		var shadow: float = clampf((-q.x-0.5)*0.047,0.0,0.10)+clampf((q.y-1.75)*0.08,0.0,0.06)
		if q.x>1.65: shadow+=0.04
		if q.y<-1.55 and q.x<0.7: return c.lightened(0.055)
		return c.darkened(shadow)

static func _female_head(f) -> void:
	if FigurePainter.female_variant(f.spec) == 0:
		_female_head_retained(f)
		return
	if f._lost("head"): return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var sc: Vector2 = f.j["sc"]
	var race: String = String(f.spec.get("race","moon_elf"))
	var seed: int = posmod(int(f.spec.get("seed",0)),12)
	var style: int = posmod(int(f.spec.get("seed",0)),6)
	var age: int = int(f.spec.get("age",40))
	var skin: Color = f.skin
	var hair: Color = f.hair
	var light: Color = skin.lightened(0.15)
	var plane: Color = skin.darkened(0.15)
	var deep: Color = skin.darkened(0.56)
	var brow: Color = hair.darkened(0.35).lerp(deep,0.71)
	var eye: Color = Color(f.ra.get("eye","#7fe0ff"))
	var dead: bool = f.pose=="dead" or bool(f.spec.get("dead",false))
	var chin: float = float(seed%3-1)*0.025
	var has_jaw: bool = not f._lost("jaw")
	var moon: bool = race=="moon_elf"
	var dark: bool = race=="dark_elf"
	_hair_back(f,hc,race,style)
	if not f._lost("neck"):
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-0.55,1.65),hc+Vector2(1.02,1.78),sc+Vector2(1.04,0.75),sc+Vector2(-0.79,0.45)]),plane)
		cv.end(FigurePainter.ol(skin),0.04)
	cv.begin()
	if not f._lost("ear_l"):
		_contour(cv,hc,[[1.53,-1.08],[2.36,-1.48],[2.15,-0.32],[1.78,-0.05]],plane)
	var tip: Vector2 = Vector2(-3.70,-2.03)
	if race=="high_elf": tip=Vector2(-3.53,-2.27)
	elif dark: tip=Vector2(-3.59,-2.40)
	if not f._lost("ear_r"):
		_poly(cv,hc,[[-1.83,-0.99],[-2.25,-1.16],[tip.x,tip.y],[-3.0,-0.27],[-2.36,0.38],[-1.77,0.13]],skin)
	cv.end(FigurePainter.ol(skin),0.05)
	if not f._lost("ear_r"):
		_contour(cv,hc,[[-2.01,-0.65],[tip.x+0.43,tip.y+0.38],[-2.83,-0.27],[-2.28,0.12]],plane)
		_path(cv,hc,[[-2.07,-0.69],[-2.53,-0.93],[-3.04,-1.28]],0.09,light)
	# A shorter balanced adult oval, lifted cheek crest, and softly rounded chin.
	var cheek: float = 2.07 if moon else 2.00
	var lower: float = 1.51 if dark else 1.45
	cv.begin()
	if has_jaw:
		_contour(cv,hc,[[-2.04,-1.61],[-1.61,-2.68],[-0.35,-3.04],[0.92,-2.97],[1.79,-2.22],[2.00,-1.17],[1.99,-0.18],[cheek,0.32],[1.88,0.91],[lower,1.49],[1.00+chin,2.12],[0.34-chin,2.32],[-0.36,2.05],[-1.16,1.39],[-1.87,0.31]],skin,_female_face_pat(f,hc))
	else:
		_contour(cv,hc,[[-2.04,-1.61],[-1.61,-2.68],[-0.35,-3.04],[0.92,-2.97],[1.79,-2.22],[2.00,-1.17],[1.99,-0.18],[cheek,0.32],[1.88,0.91],[1.52,1.22],[0.89,1.32],[0.18,1.24],[-0.65,1.08],[-1.26,0.73],[-1.87,0.31]],skin,_female_face_pat(f,hc))
	cv.end(FigurePainter.ol(skin),0.045)
	_contour(cv,hc,[[-1.5,-0.18],[-0.85,-0.37],[-0.01,-0.06],[0.33,0.27],[-0.20,0.68],[-1.17,0.65],[-1.58,0.15]],light)
	if has_jaw:
		_contour(cv,hc,[[-1.50,0.61],[-0.90,0.95],[-0.41,1.42],[0.30,1.94],[-0.21,1.91],[-0.96,1.32]],skin.darkened(0.07 if moon else 0.10))
	_contour(cv,hc,[[1.48,-0.04],[1.89,0.08],[1.78,0.63],[1.40,0.61]],skin.lightened(0.09))
	if not f._lost("nose"):
		_contour(cv,hc,[[0.72,-1.10],[0.89,-0.90],[0.87,-0.28],[1.24,0.04],[1.25,0.26],[1.02,0.41],[0.77,0.29],[0.71,-0.03]],skin.lightened(0.07))
		_path(cv,hc,[[0.79,-0.78],[0.79,-0.29],[1.06,0.02]],0.075,skin.lightened(0.22))
		_path(cv,hc,[[0.85,0.29],[1.03,0.34],[1.20,0.25]],0.07,plane)
	_female_eye(f,hc,Vector2(-0.43,-0.88),1.52,eye,brow,dead,"eye_r")
	_female_eye(f,hc,Vector2(1.34,-0.95),0.83,eye.darkened(0.04),brow,dead,"eye_l")
	var arch: float = -0.06 if race=="high_elf" else 0.0
	_path(cv,hc,[[-1.24,-1.45],[-0.78,-1.72+arch],[-0.20,-1.70],[0.22,-1.48]],0.11,brow)
	_path(cv,hc,[[0.99,-1.52],[1.36,-1.72+arch],[1.74,-1.58]],0.09,brow)
	if not f._lost("mouth"):
		var lip: Color = skin.darkened(0.11).lerp(Color("#b26282"),0.34)
		var seam: Color = lip.darkened(0.30)
		# Explicit lip shapes survive the native grid instead of collapsing to a thin dash.
		_poly(cv,hc,[[0.12,1.22],[0.43,1.04],[0.69,1.13],[0.87,1.06],[1.36,1.19],[1.03,1.34],[0.50,1.32]],lip)
		if has_jaw:
			_contour(cv,hc,[[0.22,1.32],[0.44,1.52],[0.83,1.59],[1.21,1.42],[1.32,1.27],[0.76,1.29]],lip.lightened(0.16))
		_path(cv,hc,[[0.18,1.24],[0.63,1.29],[1.02,1.27],[1.32,1.20]],0.065,seam)
		if has_jaw:
			_path(cv,hc,[[0.48,1.48],[0.80,1.52],[1.04,1.43]],0.07,skin.lightened(0.28))
			_path(cv,hc,[[0.35,1.83],[0.77,1.88],[1.07,1.79]],0.055,plane)
	if age>=240:
		_path(cv,hc,[[-1.11,-0.26],[-0.93,-0.06],[-0.62,-0.02]],0.05,plane)
		_path(cv,hc,[[1.32,0.53],[1.43,0.82],[1.34,1.02]],0.05,plane)
	_female_hair_front(f,hc,race,style)
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _female_eye(f,hc: Vector2,p: Vector2,width: float,eye: Color,brow: Color,dead: bool,pid: String) -> void:
	var cv: PixelCanvas = f.cv
	var left: float = p.x-width*0.5
	var right: float = p.x+width*0.5
	var near: bool = width>1.0
	var h: float = 0.43 if near else 0.32
	if f._lost(pid):
		cv.ellipse(hc+p,width*0.42,h,FigurePainter.BLOOD_DARK)
		_stroke(cv,hc,p+Vector2(-0.18,-0.14),p+Vector2(0.21,0.23),0.10,FigurePainter.BLOOD)
		return
	if dead:
		_path(cv,hc,[[left,p.y-0.09],[p.x,p.y+0.12],[right,p.y]],0.11,brow)
		return
	_poly(cv,hc,[[left,p.y-0.07],[p.x-width*0.20,p.y-h*0.79],[p.x+width*0.13,p.y-h*0.83],[right,p.y+0.01],[p.x+width*0.15,p.y+h*0.74],[p.x-width*0.19,p.y+h*0.77]],f.skin.lightened(0.74))
	cv.ellipse(hc+p+Vector2(0.13,-0.01),0.31 if near else 0.205,h*0.79,eye)
	cv.ellipse(hc+p+Vector2(0.15,0.02),0.115 if near else 0.075,h*0.65,eye.darkened(0.69))
	_path(cv,hc,[[left-0.06,p.y-0.16],[p.x-width*0.16,p.y-h*0.83],[p.x+width*0.10,p.y-h*0.86],[right,p.y]],0.13 if near else 0.10,brow)
	# A few coherent lash strokes at the outer corner, never a round cartoon eye.
	_stroke(cv,hc,Vector2(left-0.05,p.y-0.15),Vector2(left-0.18,p.y-0.33),0.065,brow)
	_path(cv,hc,[[left+0.11,p.y+0.10],[p.x+0.08,p.y+h*0.84],[right-0.06,p.y+0.09]],0.065,f.skin.darkened(0.24))
	cv.ellipse(hc+p+Vector2(0.015,-0.15),0.080 if near else 0.055,0.085 if near else 0.06,eye.lightened(0.74))

static func _female_hair_front(f,hc: Vector2,race: String,style: int) -> void:
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var ink: Color = FigurePainter.ol(hair)
	var pat: Callable = _hair_pat(f,hc)
	var helmed: bool = not f._it("helm").is_empty()
	var wave: float = -3.55 if race=="moon_elf" else (-3.65 if race=="dark_elf" else -3.48)
	cv.begin()
	match style:
		0:
			_contour(cv,hc,[[-2.23,-0.76],[-2.60,-1.86],[-2.18,-2.99],[-1.06,-3.42],[0.08,-3.32],[0.31,-2.70],[-0.44,-2.36],[-1.21,-1.74],[-1.71,-0.70]],hair,pat)
			_contour(cv,hc,[[0.24,-3.27],[1.11,-3.17],[1.93,-2.56],[1.73,-2.04],[1.04,-2.27],[0.43,-2.63]],hair,pat)
		1:
			_contour(cv,hc,[[-2.15,0.18],[-2.73,-1.31],[-2.56,-2.52],[-1.56,-3.35],[-0.32,wave],[0.39,-3.18],[0.25,-2.55],[-0.52,-2.23],[-1.29,-1.53],[-1.77,-0.35]],hair,pat)
			_contour(cv,hc,[[0.34,-3.29],[1.32,-3.08],[1.93,-2.47],[1.89,-1.40],[1.63,-0.89],[1.48,-1.79],[0.94,-2.31],[0.43,-2.47]],hair,pat)
		2:
			_contour(cv,hc,[[-2.18,-0.54],[-2.63,-1.84],[-2.29,-2.94],[-1.07,wave],[-0.03,-3.36],[0.36,-2.85],[-0.16,-2.48],[-0.91,-2.04],[-1.63,-1.1]],hair,pat)
			_contour(cv,hc,[[0.34,-3.29],[1.23,-3.11],[1.89,-2.44],[1.70,-1.92],[1.07,-2.34],[0.44,-2.58]],hair,pat)
		3:
			_contour(cv,hc,[[-2.24,-0.53],[-2.66,-1.95],[-2.06,-3.01],[-0.66,wave],[0.68,-3.21],[1.62,-2.81],[1.85,-2.23],[1.18,-2.20],[0.46,-2.51],[-0.50,-2.26],[-1.31,-1.55],[-1.72,-0.57]],hair,pat)
		4:
			_contour(cv,hc,[[-2.33,-0.50],[-2.64,-1.99],[-2.16,-3.00],[-0.97,wave],[0.10,-3.36],[0.32,-2.80],[-0.36,-2.47],[-1.31,-1.79],[-1.72,-0.59]],hair,pat)
			_contour(cv,hc,[[0.29,-3.24],[1.18,-3.08],[1.89,-2.48],[1.73,-1.95],[1.01,-2.31],[0.41,-2.66]],hair,pat)
		5:
			var lift: float = -3.54 if helmed else -3.83
			_contour(cv,hc,[[-1.65,-1.73],[-1.69,-2.89],[-0.75,lift],[0.55,lift-0.02],[1.57,-3.16],[1.88,-2.45],[1.25,-2.17],[0.48,-2.51],[-0.24,-2.14],[-1.01,-1.57]],hair,pat)
	cv.end(ink,0.055)
	if style==5:
		_path(cv,hc,[[-1.19,-2.76],[-0.50,-3.22],[0.32,-3.33],[1.13,-2.88]],0.14,hair.lightened(0.26))
		_path(cv,hc,[[-0.74,-2.36],[-0.03,-2.77],[0.79,-2.77]],0.10,hair.lightened(0.18))
	else:
		_path(cv,hc,[[-2.23,-1.95],[-1.99,-2.57],[-1.32,-2.99],[-0.44,-3.12]],0.15,hair.lightened(0.25))
		_path(cv,hc,[[-2.01,-1.34],[-1.78,-2.00],[-1.09,-2.44],[-0.41,-2.64]],0.115,hair.lightened(0.19))
		_path(cv,hc,[[0.59,-3.00],[1.15,-2.75],[1.53,-2.28]],0.11,hair.lightened(0.20))
		if style in [1,2]:
			_path(cv,hc,[[-2.08,-0.50],[-1.96,0.21],[-2.12,0.84]],0.10,hair.lightened(0.15))
	if style==4:
		_braid(cv,hc,Vector2(-2.45,0.75),Vector2(-2.30,4.2),hair,ink)
		_path(cv,hc,[[-2.07,-2.21],[-2.32,-1.47],[-2.10,-0.64]],0.13,hair.lightened(0.20))

static func _female_head_retained(f) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var sc: Vector2 = f.j["sc"]
	var race: String = String(f.spec.get("race","moon_elf"))
	var seed: int = posmod(int(f.spec.get("seed",0)),12)
	var style: int = posmod(int(f.spec.get("seed",0)),6)
	var age: int = int(f.spec.get("age",40))
	var skin: Color = f.skin
	var hair: Color = f.hair
	var light: Color = skin.lightened(0.16)
	var plane: Color = skin.darkened(0.17)
	var deep: Color = skin.darkened(0.44)
	var brow: Color = hair.darkened(0.28).lerp(deep,0.60)
	var eye: Color = Color(f.ra.get("eye","#7fe0ff"))
	var dead: bool = f.pose=="dead" or bool(f.spec.get("dead",false))
	var chin: float = float(seed%3-1)*0.035
	var has_jaw: bool = not f._lost("jaw")
	var moon: bool = race=="moon_elf"
	var dark: bool = race=="dark_elf"
	_hair_back(f,hc,race,style)
	# Slender neck and the unchanged shoulder anchor give the jaw a clean transition.
	if not f._lost("neck"):
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-0.55,1.8),hc+Vector2(1.02,1.86),sc+Vector2(1.04,0.75),sc+Vector2(-0.79,0.45)]),plane)
		cv.end(FigurePainter.ol(skin),0.05)
	cv.begin()
	if not f._lost("ear_l"):
		_contour(cv,hc,[[1.53,-1.08],[2.36,-1.48],[2.15,-0.32],[1.78,-0.05]],plane)
	var tip: Vector2 = Vector2(-3.70,-2.03)
	if race=="high_elf": tip=Vector2(-3.53,-2.27)
	elif dark: tip=Vector2(-3.59,-2.40)
	if not f._lost("ear_r"):
		_poly(cv,hc,[[-1.83,-0.99],[-2.25,-1.16],[tip.x,tip.y],[-3.0,-0.27],[-2.36,0.38],[-1.77,0.13]],skin)
	cv.end(FigurePainter.ol(skin),0.05)
	if not f._lost("ear_r"):
		_contour(cv,hc,[[-2.01,-0.65],[tip.x+0.43,tip.y+0.38],[-2.83,-0.27],[-2.28,0.12]],plane)
		_path(cv,hc,[[-2.07,-0.69],[-2.53,-0.93],[-3.04,-1.28]],0.09,light)
	# Full adult temple and cheek structure tapers gently into a small rounded chin.
	var cheek: float = 2.03 if moon else 1.97
	var lower: float = 1.49 if dark else 1.43
	cv.begin()
	if has_jaw:
		_contour(cv,hc,[[-2.01,-1.68],[-1.60,-2.72],[-0.36,-3.08],[0.92,-2.99],[1.79,-2.29],[2.01,-1.2],[1.98,-0.1],[cheek,0.49],[1.84,1.03],[lower,1.76],[0.89+chin,2.48],[0.18-chin,2.57],[-0.63,2.19],[-1.30,1.51],[-1.87,0.48]],skin,_face_pat(f,hc,race))
	else:
		_contour(cv,hc,[[-2.01,-1.68],[-1.60,-2.72],[-0.36,-3.08],[0.92,-2.99],[1.79,-2.29],[2.01,-1.2],[1.98,-0.1],[cheek,0.49],[1.84,1.03],[1.51,1.38],[0.84,1.45],[0.15,1.37],[-0.68,1.16],[-1.30,0.84],[-1.87,0.48]],skin,_face_pat(f,hc,race))
	cv.end(FigurePainter.ol(skin),0.05)
	# Lifted cheekbones and a smooth lower cheek carry the feminine likeness at k2/k7.
	_contour(cv,hc,[[-1.43,-0.2],[-0.83,-0.38],[-0.06,-0.02],[0.26,0.33],[-0.29,0.74],[-1.16,0.70],[-1.54,0.22]],light)
	if has_jaw:
		_contour(cv,hc,[[-1.57,0.65],[-0.99,1.04],[-0.51,1.69],[0.28,2.25],[-0.3,2.12],[-1.01,1.53]],skin.darkened(0.10 if moon else 0.13))
	_contour(cv,hc,[[1.49,0.02],[1.87,0.13],[1.78,0.71],[1.37,0.66]],skin.lightened(0.10))
	if not f._lost("nose"):
		_contour(cv,hc,[[0.69,-1.18],[0.88,-0.96],[0.89,-0.25],[1.32,0.08],[1.34,0.36],[1.05,0.51],[0.74,0.34],[0.66,-0.06]],skin.lightened(0.08))
		_path(cv,hc,[[0.76,-0.86],[0.80,-0.30],[1.11,0.05]],0.085,skin.lightened(0.22))
		_path(cv,hc,[[0.81,0.34],[1.05,0.44],[1.27,0.33]],0.08,plane)
	# Adult almond eyes have thin lids, a slight outer lift and restrained lash corners.
	_female_eye_retained(f,hc,Vector2(-0.39,-0.92),1.30,eye,brow,dead,"eye_r")
	_female_eye_retained(f,hc,Vector2(1.31,-0.99),0.73,eye.darkened(0.08),brow,dead,"eye_l")
	var arch: float = -0.10 if race=="high_elf" else (-0.04 if dark else 0.0)
	_path(cv,hc,[[-1.13,-1.5],[-0.69,-1.72+arch],[-0.13,-1.69],[0.16,-1.49]],0.095,brow)
	_path(cv,hc,[[1.02,-1.54],[1.35,-1.71+arch],[1.65,-1.62]],0.08,brow)
	if not f._lost("mouth"):
		var lip: Color = skin.darkened(0.16).lerp(Color("#a45e78"),0.23)
		var lip_deep: Color = lip.darkened(0.26)
		_contour(cv,hc,[[0.18,1.31],[0.46,1.15],[0.70,1.24],[0.86,1.16],[1.31,1.29],[0.95,1.42],[0.46,1.42]],lip)
		if has_jaw:
			_contour(cv,hc,[[0.27,1.41],[0.73,1.60],[1.20,1.40],[0.77,1.36]],lip.lightened(0.12))
		_path(cv,hc,[[0.22,1.34],[0.61,1.38],[0.92,1.35],[1.27,1.31]],0.075,lip_deep)
		if has_jaw:
			_path(cv,hc,[[0.54,1.54],[0.81,1.56],[1.00,1.49]],0.06,skin.lightened(0.24))
			_path(cv,hc,[[0.38,1.91],[0.75,1.96],[1.03,1.89]],0.065,plane)
	if age>=240:
		_path(cv,hc,[[-1.02,-0.30],[-0.89,-0.10],[-0.62,-0.07]],0.055,plane)
		_path(cv,hc,[[1.31,0.62],[1.4,0.89],[1.31,1.09]],0.055,plane)
	# The accepted short/loose/half-tie/pony/braid/sweep silhouettes remain unchanged.
	_hair_front(f,hc,race,style)
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _female_eye_retained(f,hc: Vector2,p: Vector2,width: float,eye: Color,brow: Color,dead: bool,pid: String) -> void:
	var cv: PixelCanvas = f.cv
	var left: float = p.x-width*0.5
	var right: float = p.x+width*0.5
	var h: float = 0.33 if width>0.8 else 0.24
	if f._lost(pid):
		cv.ellipse(hc+p,width*0.42,h,FigurePainter.BLOOD_DARK)
		_stroke(cv,hc,p+Vector2(-0.18,-0.14),p+Vector2(0.21,0.23),0.10,FigurePainter.BLOOD)
		return
	if dead:
		_path(cv,hc,[[left,p.y-0.05],[p.x,p.y+0.13],[right,p.y+0.01]],0.10,brow)
		return
	_contour(cv,hc,[[left,p.y-0.10],[p.x-0.11,p.y-h],[right,p.y+0.01],[p.x+0.07,p.y+h]],f.skin.lightened(0.61))
	cv.ellipse(hc+p+Vector2(0.12,-0.01),0.24 if width>0.8 else 0.16,h*0.86,eye)
	cv.ellipse(hc+p+Vector2(0.14,0.01),0.085 if width>0.8 else 0.055,h*0.67,eye.darkened(0.57))
	_path(cv,hc,[[left-0.04,p.y-0.15],[p.x-0.17,p.y-h*0.81],[right,p.y+0.01]],0.11,brow)
	_path(cv,hc,[[left+0.07,p.y+0.09],[p.x+0.04,p.y+h],[right-0.03,p.y+0.05]],0.065,f.skin.darkened(0.24))

static func _female_body_pts(f,hem: float,spread: float = 0.0) -> PackedVector2Array:
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var half: float = float(f.tw)*0.5
	var chest: Vector2 = sc.lerp(hip,0.29)
	var waist: Vector2 = sc.lerp(hip,0.65)
	var hw: float = float(f.hipw)*0.5
	var armored: bool = not f._it("body").is_empty()
	var taper: float = 0.79 if armored else 0.66
	var hip_scale: float = 1.02 if armored else 1.05
	# Fitted real cloth: rounded shoulders, athletic ribcage, waist and hip transition.
	# Armor retains its thickness and covers the same anatomy without invented cut-outs.
	return PackedVector2Array([sc+Vector2(-0.87,-0.10),sc+Vector2(1.03,-0.10),
		sc+Vector2(half-0.86,0.28),sc+Vector2(half-0.34,1.03),chest+Vector2(half-0.23,0.0),
		waist+Vector2(hw*taper,0.0),hip+Vector2(hw*hip_scale,0.15),
		hip+Vector2(hw+0.4+spread,hem-0.25),hip+Vector2(hw+0.18+spread,hem+0.03),
		hip+Vector2(0.7,hem+0.1),hip+Vector2(0.2,hem-0.1),hip+Vector2(-0.4,hem+0.13),
		hip+Vector2(-hw-0.2-spread,hem+0.03),hip+Vector2(-hw-0.45-spread,hem-0.23),
		hip+Vector2(-hw*hip_scale,0.15),waist+Vector2(-hw*taper,0.0),
		chest+Vector2(-half+0.27,0.0),sc+Vector2(-half+0.40,0.98),sc+Vector2(-half+0.91,0.28)])

# Seed modulo six is the style contract, independent of palette, sex, pose or equipment.
# 0 short part, 1 loose lengths, 2 half-tied, 3 ponytail, 4 twin braids, 5 side sweep.
static func _hair_back(f,hc: Vector2,race: String,style: int) -> void:
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var ink: Color = FigurePainter.ol(hair)
	var pat: Callable = _hair_pat(f,hc)
	cv.begin()
	match style:
		0:
			_contour(cv,hc,[[-1.75,-2.65],[-2.5,-2.25],[-2.62,-0.85],[-2.28,0.68],[-1.9,0.86],[-1.78,-0.9]],hair,pat)
		1:
			if race=="moon_elf":
				_contour(cv,hc,[[-1.6,-2.8],[-2.7,-2.45],[-3.05,-0.8],[-2.95,1.0],[-3.55,2.45],[-3.65,4.35],[-3.0,5.2],[-2.5,4.65],[-2.15,3.0],[-1.8,1.4]],hair,pat)
				_contour(cv,hc,[[-3.1,0.3],[-3.75,1.8],[-3.55,3.45],[-4.0,4.7],[-3.15,4.3],[-2.7,2.5]],hair.darkened(0.08),pat)
			else:
				_contour(cv,hc,[[-1.8,-2.95],[-2.9,-2.45],[-3.10,-0.5],[-2.9,1.4],[-3.13,3.5],[-2.65,5.0],[-1.95,4.65],[-1.78,2.0],[-1.55,0.1]],hair,pat)
				_contour(cv,hc,[[1.72,-1.8],[2.33,-1.15],[2.43,0.95],[2.19,2.85],[1.55,3.85],[1.76,1.0]],hair.darkened(0.09),pat)
		2:
			# Gathered upper hair, a visibly separate lower loose fall.
			_contour(cv,hc,[[-1.6,-2.9],[-2.8,-2.35],[-2.9,-0.65],[-2.15,0.9],[-1.7,0.6],[-1.8,-1.3]],hair,pat)
			_contour(cv,hc,[[-2.7,0.55],[-3.32,1.4],[-3.15,2.55],[-3.45,4.5],[-2.8,4.85],[-2.4,3.3],[-2.1,1.65]],hair,pat)
			_contour(cv,hc,[[-2.82,-0.65],[-3.65,-0.26],[-3.5,0.9],[-2.7,1.15],[-2.45,0.2]],hair.darkened(0.04),pat)
		3:
			_contour(cv,hc,[[-1.5,-2.8],[-2.63,-2.35],[-2.76,-0.95],[-2.3,0.75],[-1.8,0.5],[-1.65,-0.9]],hair,pat)
			# Hair folds form their own tie; no ribbon or invented accessory.
			_contour(cv,hc,[[-2.5,-1.25],[-3.18,-1.3],[-3.95,-0.35],[-4.15,1.45],[-3.48,3.28],[-3.4,4.58],[-2.86,3.98],[-2.90,2.52],[-3.24,1.15],[-2.85,0.03]],hair,pat)
		4:
			_contour(cv,hc,[[-1.5,-2.9],[-2.62,-2.55],[-2.85,-1.2],[-2.55,0.8],[-2.07,1.25],[-1.75,-0.2]],hair,pat)
		5:
			# Close-shaved rear and one short angled side lock expose the neck.
			_contour(cv,hc,[[-1.75,-2.7],[-2.2,-2.12],[-2.25,-0.72],[-1.88,0.48],[-1.61,0.1],[-1.6,-1.2]],hair.darkened(0.15),pat)
	cv.end(ink,0.07)
	if style==4:
		_braid(cv,hc,Vector2(1.91,-0.25),Vector2(2.12,3.4),hair.darkened(0.09),ink)
	elif style==3:
		_path(cv,hc,[[-3.24,-0.7],[-3.72,0.15],[-3.74,1.35],[-3.18,2.85],[-3.14,3.8]],0.13,hair.lightened(0.19))
	elif style==2:
		_path(cv,hc,[[-2.95,1.65],[-2.77,2.7],[-2.98,4.0]],0.13,hair.lightened(0.18))
	elif style==1:
		_path(cv,hc,[[-2.72,1.0],[-3.04,1.8],[-3.03,2.8],[-2.85,3.64],[-3.05,4.46]],0.13,hair.lightened(0.19))

static func _hair_front(f,hc: Vector2,race: String,style: int) -> void:
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var ink: Color = FigurePainter.ol(hair)
	var pat: Callable = _hair_pat(f,hc)
	var helmed: bool = not f._it("helm").is_empty()
	var peak: float = -3.48 if race=="high_elf" else (-3.62 if race=="dark_elf" else -3.55)
	cv.begin()
	match style:
		0:
			# Low cropped crown, exposed temple and short separate part.
			_contour(cv,hc,[[-2.3,-1.45],[-2.55,-2.3],[-1.76,-3.17],[-0.6,-3.35],[0.12,-3.16],[-0.05,-2.62],[-0.84,-2.14],[-1.75,-1.55]],hair,pat)
			_contour(cv,hc,[[0.22,-3.2],[1.25,-3.03],[1.95,-2.52],[1.8,-2.07],[1.15,-2.27],[0.48,-2.57]],hair,pat)
		1:
			# Broad loose part with long temple lock; waveform is a moon-elf accent.
			_contour(cv,hc,[[-2.38,-0.65],[-2.85,-1.95],[-2.35,-3.1],[-1.13,peak],[0.23,-3.46],[0.40,-2.83],[-0.35,-2.46],[-1.0,-1.85],[-1.45,-1.0],[-1.82,-0.1]],hair,pat)
			_contour(cv,hc,[[0.4,-3.35],[1.2,-3.12],[1.95,-2.6],[1.83,-1.93],[1.13,-2.37],[0.64,-2.5]],hair,pat)
		2:
			# Swept upper locks leave an open forehead above the half-tied fall.
			_contour(cv,hc,[[-2.42,-1.05],[-2.7,-2.55],[-1.72,-3.3],[-0.5,peak],[0.18,-3.07],[-0.26,-2.64],[-1.3,-2.01],[-1.95,-1.28]],hair,pat)
			_contour(cv,hc,[[0.2,-3.17],[1.14,-3.16],[1.99,-2.58],[1.86,-2.11],[1.24,-2.48],[0.64,-2.62]],hair,pat)
		3:
			# Slicked forehead with a pulled-back crown; tail is the dominant outline.
			_contour(cv,hc,[[-2.5,-0.92],[-2.76,-2.25],[-2.03,-3.12],[-0.65,peak],[0.53,-3.24],[1.49,-2.99],[1.96,-2.43],[1.53,-2.18],[0.6,-2.53],[-0.48,-2.3],[-1.49,-1.93],[-1.92,-1.1]],hair,pat)
		4:
			# Two woven sides and a smaller center part rather than the loose fringe.
			_contour(cv,hc,[[-2.43,-0.9],[-2.68,-2.45],[-1.95,-3.25],[-0.78,peak],[0.08,-3.20],[-0.25,-2.64],[-1.25,-2.15],[-1.83,-1.0]],hair,pat)
			_contour(cv,hc,[[0.17,-3.23],[1.13,-3.12],[1.94,-2.48],[1.89,-1.99],[1.21,-2.25],[0.38,-2.66]],hair,pat)
		5:
			# Offset high sweep leaves the near temple visible. Helm suppresses its lift.
			var lift: float = -3.58 if helmed else -4.0
			_contour(cv,hc,[[-1.85,-2.48],[-1.26,lift],[-0.18,lift-0.08],[1.14,-3.62],[1.88,-2.83],[1.8,-2.29],[0.91,-2.52],[0.22,-2.26],[-0.5,-1.82],[-1.16,-1.47]],hair,pat)
	cv.end(ink,0.06)
	if style==0:
		_path(cv,hc,[[-2.03,-2.32],[-1.39,-2.8],[-0.58,-3.0]],0.12,hair.lightened(0.22))
		_path(cv,hc,[[0.45,-2.91],[1.17,-2.7],[1.57,-2.41]],0.10,hair.lightened(0.18))
	elif style==5:
		_path(cv,hc,[[-1.38,-2.82],[-0.73,-3.3],[0.17,-3.39],[1.03,-3.02]],0.14,hair.lightened(0.24))
		_path(cv,hc,[[-0.75,-2.47],[0.03,-2.85],[0.87,-2.93]],0.10,hair.lightened(0.16))
	else:
		_path(cv,hc,[[-2.35,-2.1],[-1.9,-2.7],[-1.1,-3.06],[-0.28,-3.12]],0.13,hair.lightened(0.23))
		_path(cv,hc,[[-2.07,-1.7],[-1.57,-2.2],[-0.82,-2.61],[-0.28,-2.74]],0.10,hair.lightened(0.16))
		_path(cv,hc,[[0.54,-3.06],[1.13,-2.89],[1.59,-2.51]],0.11,hair.lightened(0.20))
	if style==4:
		_braid(cv,hc,Vector2(-2.45,0.75),Vector2(-2.30,4.2),hair,ink)
		_path(cv,hc,[[-1.9,-2.45],[-2.22,-1.67],[-2.1,-0.76]],0.15,hair.darkened(0.14))
	elif style==1 and race=="moon_elf":
		_path(cv,hc,[[-3.45,2.1],[-3.32,3.0],[-3.57,4.0]],0.10,hair.lightened(0.14))
	elif style==2 and race=="high_elf":
		# Gathered high-elf half-tie is woven from hair itself.
		_path(cv,hc,[[-2.46,-0.2],[-2.79,0.25],[-3.05,0.05],[-2.8,-0.28]],0.13,hair.lightened(0.17))

static func _eye(f,hc: Vector2,p: Vector2,width: float,eye: Color,brow: Color,dead: bool,pid: String) -> void:
	var cv: PixelCanvas = f.cv
	var left: float = p.x-width*0.5
	var right: float = p.x+width*0.5
	var h: float = 0.31 if width>0.8 else 0.23
	if f._lost(pid):
		cv.ellipse(hc+p,width*0.43,h,FigurePainter.BLOOD_DARK)
		_stroke(cv,hc,p+Vector2(-0.2,-0.15),p+Vector2(0.23,0.24),0.11,FigurePainter.BLOOD)
		return
	if dead:
		_path(cv,hc,[[left,p.y],[p.x,p.y+0.14],[right,p.y-0.04]],0.11,brow)
		return
	_contour(cv,hc,[[left,p.y],[p.x-0.13,p.y-h],[right,p.y-0.09],[p.x+0.10,p.y+h]],f.skin.lightened(0.60))
	cv.ellipse(hc+p+Vector2(0.12,0.0),0.24 if width>0.8 else 0.16,h*0.86,eye)
	cv.ellipse(hc+p+Vector2(0.15,0.02),0.085 if width>0.8 else 0.06,h*0.70,eye.darkened(0.56))
	_path(cv,hc,[[left,p.y],[p.x-0.16,p.y-h*0.8],[right,p.y-0.07]],0.10,brow)
	_path(cv,hc,[[left+0.12,p.y+0.16],[p.x+0.1,p.y+h],[right-0.05,p.y+0.03]],0.07,f.skin.darkened(0.24))

static func _braid(cv: PixelCanvas,hc: Vector2,a: Vector2,b: Vector2,hair: Color,ink: Color) -> void:
	cv.begin()
	_stroke(cv,hc,a,b,0.37,hair.darkened(0.08))
	cv.end(ink,0.10)
	for i in 6:
		var p: Vector2 = a.lerp(b,float(i)/6.0)
		var braid_direction: float = -1.0 if i%2==0 else 1.0
		_stroke(cv,hc,p+Vector2(-0.25*braid_direction,-0.15),p+Vector2(0.25*braid_direction,0.32),0.12,hair.lightened(0.20))

static func _segment(cv: PixelCanvas,a: Vector2,b: Vector2,r0: float,r1: float,c: Color,pat: Callable = Callable()) -> void:
	var axis: Vector2 = (b-a).normalized()
	var n: Vector2 = Vector2(-axis.y,axis.x)
	cv.poly(PackedVector2Array([a-n*r0,b-n*r1,b+n*r1,a+n*r0]),c,pat)
	cv.ellipse(a,r0,r0,c,pat)
	cv.ellipse(b,r1,r1,c,pat)

static func _surface(f,origin: Vector2,kind: String,m: Dictionary = {}) -> Callable:
	var inverse: Transform2D = f.cv.xf.affine_inverse()
	var trim: Color = f.sec
	var dk: Color = m.get("dark",f.prim.darkened(0.25))
	var lt: Color = m.get("light",f.prim.lightened(0.15))
	return func(x: int,y: int,c: Color) -> Color:
		var q: Vector2 = inverse * Vector2(x+0.5,y+0.5)-origin
		var ix: int = floori(q.x/0.7)
		var iy: int = floori(q.y/0.65)
		if kind == "mail" or kind == "byrnie":
			var stagger: int = posmod(iy,2)
			if posmod(ix+stagger,3)==0: return dk.lerp(c,0.35)
			if posmod(iy,2)==0 and posmod(ix+stagger,3)==1: return lt.lerp(c,0.55)
		elif kind == "scale":
			if posmod(iy,2)==1: return dk.lerp(c,0.45)
			if posmod(ix+int(iy/2),3)==1: return lt.lerp(c,0.40)
		elif kind == "lamellar":
			if fposmod(q.y,1.7)>1.4: return trim.darkened(0.25)
			if fposmod(q.x,1.1)<0.2: return dk.lerp(c,0.35)
			if fposmod(q.y,1.7)<0.25: return lt.lerp(c,0.55)
		else:
			if q.x < -1.6: return c.darkened(0.17)
			if q.y>2.0 and absf(q.x-(0.65+(q.y-2.0)*0.10))<0.19: return c.darkened(0.13)
			if q.x>-1.1 and q.x<0.2: return c.lightened(0.09)
		return c

static func _body_pts(f,hem: float,spread: float = 0.0) -> PackedVector2Array:
	if String(f.spec.get("sex", "")).to_lower() in ["female","f","woman"]:
		return _female_body_pts(f,hem,spread)
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var half: float = float(f.tw)*0.5
	var chest: Vector2 = sc.lerp(hip,0.28)
	var waist: Vector2 = sc.lerp(hip,0.66)
	var hw: float = float(f.hipw)*0.5
	var female: bool = String(f.spec.get("sex", "")).to_lower() in ["female","f","woman"]
	var taper: float = 0.80 if female else 0.84
	# Collar, deltoid, ribcage and waist form a flowing athletic outline.
	# The tailoring retains the real garment's length and original rig positions.
	return PackedVector2Array([sc+Vector2(-1.1,-0.12),sc+Vector2(1.1,-0.12),
		sc+Vector2(half-0.65,0.25),sc+Vector2(half-0.12,0.95),chest+Vector2(half-0.18,0.0),
		waist+Vector2(hw*taper,0.0),hip+Vector2(hw*0.95,0.15),
		hip+Vector2(hw+0.4+spread,hem-0.25),hip+Vector2(hw+0.18+spread,hem+0.03),
		hip+Vector2(0.7,hem+0.1),hip+Vector2(0.2,hem-0.1),hip+Vector2(-0.4,hem+0.13),
		hip+Vector2(-hw-0.2-spread,hem+0.03),hip+Vector2(-hw-0.45-spread,hem-0.23),
		hip+Vector2(-hw*0.95,0.15),waist+Vector2(-hw*taper,0.0),
		chest+Vector2(-half+0.12,0.0),sc+Vector2(-half+0.13,0.9),sc+Vector2(-half+0.65,0.25)])

# Garment thickness is added around the accepted body, never to the rig or bare skin.
static func _garment_pts(f,hem: float,spread: float,kind: String) -> PackedVector2Array:
	var pts: PackedVector2Array = _body_pts(f,hem,spread)
	if kind == "gambeson":
		for i in [2,3,4,5,6,7,8]: pts[i] += Vector2(0.15,0.0)
		for i in [12,13,14,15,16,17,18]: pts[i] -= Vector2(0.15,0.0)
		pts[2].y -= 0.08; pts[18].y -= 0.08
	elif kind == "lamellar":
		pts[7].x += 0.22; pts[8].x += 0.22
		pts[12].x -= 0.22; pts[13].x -= 0.22
	# A shallow walking split separates front panels instead of a rectangular skirt.
	pts[10].y -= 0.55 if kind in ["mail","lamellar"] else 0.33
	pts[9].y -= 0.12; pts[11].y -= 0.12
	return pts

static func _wardrobe_surface(f,origin: Vector2,kind: String,m: Dictionary = {}) -> Callable:
	var inverse: Transform2D = f.cv.xf.affine_inverse()
	var trim: Color = f.sec.darkened(0.20)
	var dk: Color = m.get("dark",f.prim.darkened(0.24))
	var lt: Color = m.get("light",f.prim.lightened(0.17))
	return func(x: int,y: int,c: Color) -> Color:
		var q: Vector2 = inverse*Vector2(float(x)+0.5,float(y)+0.5)-origin
		var shade: float = clampf((-q.x-1.0)*0.055,0.0,0.15)
		if kind in ["mail","byrnie"]:
			var row: int = floori(q.y/0.62)
			var rx: float = fposmod(q.x+float(posmod(row,2))*0.34,0.68)/0.68-0.5
			var ry: float = fposmod(q.y,0.62)/0.62-0.5
			var ring: float = rx*rx+ry*ry*1.2
			if ring>0.15 and ring<0.30: return dk.lerp(c,0.25).darkened(shade)
			if rx<0.02 and ry<-0.08: return lt.lerp(c,0.42).darkened(shade)
		elif kind == "scale":
			var row: int = floori(q.y/0.94)
			var rx: float = fposmod(q.x+float(posmod(row,2))*0.44,0.88)/0.88-0.5
			var ry: float = fposmod(q.y,0.94)/0.94
			if ry>0.66+rx*rx*0.8: return dk.lerp(c,0.24).darkened(shade)
			if ry<0.19 and rx<0.1: return lt.lerp(c,0.36).darkened(shade)
		elif kind == "lamellar":
			var row: float = fposmod(q.y+q.x*q.x*0.055,1.38)
			var column: float = fposmod(q.x,0.96)
			if row>1.14: return trim.darkened(shade)
			if column<0.13: return dk.lerp(c,0.3).darkened(shade)
			if row<0.18: return lt.lerp(c,0.34).darkened(shade)
			if row>0.88 and column>0.34 and column<0.53: return trim
		elif kind == "gambeson":
			var seam: float = minf(fposmod(q.x+q.y*0.58,1.05),fposmod(q.x-q.y*0.58,1.05))
			if seam<0.16: return c.darkened(0.21+shade)
			if seam>0.40: return c.lightened(0.10).darkened(shade)
		else:
			var fold: float = absf(q.x-0.55-(q.y-2.0)*0.08)
			if q.y>1.5 and fold<0.16: return c.darkened(0.15+shade)
			if q.x>-1.35 and q.x<-0.50: return c.lightened(0.11).darkened(shade)
		return c.darkened(shade)

static func _garment_hem(cv: PixelCanvas,pts: PackedVector2Array,color: Color,width: float) -> void:
	for i in range(8,13):
		cv.capsule(pts[i]+Vector2(0.0,-0.15),pts[i+1]+Vector2(0.0,-0.15),width,color)

static func _plate_shell(f,a: Vector2,b: Vector2,r0: float,r1: float,m: Dictionary) -> void:
	var cv: PixelCanvas = f.cv
	var axis: Vector2 = (b-a).normalized()
	var n: Vector2 = Vector2(-axis.y,axis.x)
	var middle: Vector2 = a.lerp(b,0.43)
	cv.begin()
	cv.poly(PackedVector2Array([a-axis*0.16-n*r0*0.65,a-n*r0,
		middle-n*r0*0.93,b-n*r1,b+axis*0.13,b+n*r1,
		middle+n*r0*0.93,a+n*r0,a-axis*0.16+n*r0*0.65]),m["base"])
	cv.capsule(a+n*r0*0.25,b+n*r1*0.2,0.13,m["light"])
	cv.capsule(a-n*r0*0.78,b-n*r1*0.72,0.10,m["dark"])
	if int(m.get("q",0))>=1:
		cv.capsule(a-n*r0*0.75,a+n*r0*0.75,0.10,m["trim"])
		cv.capsule(b-n*r1*0.75,b+n*r1*0.75,0.09,m["trim"])
	f._metal_end(m)

static func _scrap_panels(f,sc: Vector2,hip: Vector2,m: Dictionary) -> void:
	var cv: PixelCanvas = f.cv
	var seed: int = int(f.spec.get("seed",0))
	var row_h: float = (hip-sc).length()*0.16
	var female: bool = String(f.spec.get("sex","")).to_lower() in ["female","f","woman"]
	for row in 3:
		var t: float = 0.18+float(row)*0.29
		var center: Vector2 = sc.lerp(hip,t)
		var half: float = lerpf(float(f.tw)*0.42,float(f.hipw)*0.40,t)
		if row == 1: half *= 0.82 if female else 0.93
		for side in [-1.0,1.0]:
			var p: Vector2 = center+Vector2(float(side)*half*0.48,0.0)
			var w: float = half*0.42
			var notch: float = 0.08*float(posmod(seed+row,3))
			var plate: Color = m["base"] if posmod(row+(1 if side>0.0 else 0),2)==0 else (m["base"] as Color).lerp(m["light"],0.22)
			_poly(cv,p,[[-w,-row_h],[w-0.14,-row_h-0.08],[w,row_h*0.58],[w-0.20,row_h],[-w+notch,row_h*0.81],[-w-0.05,-row_h*0.44]],m["dark"])
			_poly(cv,p,[[-w+0.13,-row_h+0.14],[w-0.25,-row_h+0.08],[w-0.15,row_h*0.55],[w-0.25,row_h-0.13],[-w+0.15+notch,row_h*0.68]],plate)
			cv.capsule(p+Vector2(-w+0.2,-row_h+0.18),p+Vector2(w-0.3,-row_h+0.12),0.10,m["light"])
			cv.ellipse(p+Vector2(-w+0.25,-row_h+0.29),0.12,0.12,m["shine"])
			cv.ellipse(p+Vector2(w-0.3,row_h*0.55),0.11,0.11,m["shine"])

static func torso(f) -> bool:
	if _force_legacy_v064:
		return _legacy_torso(f)
	var cv: PixelCanvas = f.cv
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var race: String = String(f.spec.get("race", "moon_elf"))
	var female: bool = String(f.spec.get("sex", "")).to_lower() in ["female", "f", "woman"]
	var mounted: bool = f.pose == "mounted"
	var spread: float = 0.0 if mounted else float(f._spread()) * 0.62
	var cl: Dictionary = f._it("clothing")
	var body: Dictionary = f._it("body")
	var has_cloth: bool = not cl.is_empty()
	var has_armor: bool = not body.is_empty()
	var c_tid: String = String(cl.get("tid", ""))
	var c_sp: String = String(cl.get("sprite", ""))
	var a_sp: String = String(body.get("sprite", ""))
	var a_tid: String = String(body.get("tid", ""))
	var padded: bool = c_tid == "gambeson" or c_sp == "gambeson" or a_sp in ["gambeson", "padded"]
	var robe: bool = c_sp == "robe"

	var sh := cv.shaded()
	var c_skin: int = sh.add_color(f.skin, 0.14, 1.06)
	var c_cloth: int = sh.add_color(f.prim, 0.09 if padded else 0.12, 1.08)
	var c_sec: int = sh.add_color(f.sec, 0.18, 1.10)
	var c_leath: int = sh.add_color(FigurePainter.LEATHER, 0.20, 1.12)
	var trim_metal: Dictionary = FigurePainter.metal("copper", 1)
	var c_trim: int = sh.add_color(trim_metal["light"], 0.36, 1.18, trim_metal["shine"])

	if not f._lost("neck"):
		sh.capsule(f.j["hc"] + Vector2(-0.10, 1.05), sc + Vector2(0.0, 0.45), 0.52 if female else 0.60, 0.62 if female else 0.70, c_skin, -0.8, 0.95)
	sh.capsule(sc + Vector2(-1.15, 0.35), sc + Vector2(1.15, 0.35), 0.58, 0.58, c_skin, -0.6, 0.9)

	if not has_cloth and not has_armor:
		sh.poly(_body_pts(f, 0.6, 0.0), c_skin, 0.0, 2.0)
		sh.ellipsoid(sc + Vector2(0.0, 1.45), float(f.tw) * 0.36, 1.55, c_skin, 0.5, 1.0)
		if female:
			sh.ellipsoid(sc + Vector2(-0.75, 1.55), 0.92, 0.85, c_skin, 0.9, 0.95)
			sh.ellipsoid(sc + Vector2(0.85, 1.55), 0.92, 0.85, c_skin, 1.0, 0.95)
		sh.composite(FigurePainter.ol(f.skin), true)
		return true

	# Slender athletic elven tunic / robe / gambeson
	var c_hem: float = 0.72 if mounted else (float(f.leg_len) * (0.44 if robe else (0.36 if padded else 0.32)))
	var c_pts: PackedVector2Array = _garment_pts(f, c_hem, spread, "gambeson" if padded else "cloth")
	sh.poly(c_pts, c_cloth, 0.0, 2.1)
	sh.ellipsoid(sc + Vector2(0.0, 1.45), float(f.tw) * 0.38, 1.65, c_cloth, 0.5, 1.05)
	if female and not has_armor:
		sh.ellipsoid(sc + Vector2(-0.72, 1.55), 0.95, 0.88, c_cloth, 0.9, 0.95)
		sh.ellipsoid(sc + Vector2(0.85, 1.55), 0.95, 0.88, c_cloth, 1.0, 0.95)
	# Subrace collar & tunic overlap
	sh.capsule(sc + Vector2(-1.05, 0.12), sc + Vector2(0.0, 0.85), 0.19, 0.19, c_sec, 1.1, 0.85)
	sh.capsule(sc + Vector2(1.05, 0.12), sc + Vector2(0.0, 0.85), 0.19, 0.19, c_sec, 1.1, 0.85)
	if race == "high_elf":
		sh.capsule(sc + Vector2(0.10, 0.85), hip + Vector2(0.10, c_hem - 0.35), 0.16, 0.16, c_sec, 1.2, 0.85)
	elif race == "moon_elf":
		sh.capsule(sc + Vector2(-0.85, 0.58), sc.lerp(hip, 0.58) + Vector2(0.65, 0.0), 0.18, 0.18, c_sec, 1.2, 0.85)
	else:
		sh.capsule(sc + Vector2(0.80, 0.52), hip + Vector2(-0.62, 0.05), 0.18, 0.18, c_sec, 1.2, 0.85)
	if not mounted:
		sh.capsule(hip + Vector2(-float(f.hipw) * 0.42 - spread, c_hem - 0.12), hip + Vector2(float(f.hipw) * 0.42 + spread, c_hem - 0.12), 0.18, 0.18, c_sec, 1.1, 0.85)

	# Elven body armour (lamellar, scale, mail, byrnie, plate, scrap)
	if has_armor and not a_sp in ["gambeson", "padded"]:
		var m: Dictionary = FigurePainter.metal(String(body.get("mat", "copper")), int(body.get("q", 0)))
		var mail: bool = a_sp in ["mail", "byrnie"] or a_tid == "dwarf_mail"
		var scale_a: bool = a_sp == "scale"
		var lamellar: bool = a_sp == "lamellar" or a_tid == "steppe_lamellar"
		var plate: bool = a_sp in ["plate", "cuirass"]
		var c_arm: int = sh.add_color(m["base"], 0.36 if plate else (0.28 if mail else 0.32), 1.18, m["shine"], 0.12 if mail else (0.10 if scale_a or lamellar else 0.04))
		var c_arm_d: int = sh.add_color(m["dark"], 0.26, 1.14, m["shine"], 0.06 if mail else 0.04)
		var c_arm_t: int = sh.add_color(m["trim"], 0.36, 1.18, m["shine"])
		var a_hem: float = 0.68 if mounted else (float(f.leg_len) * (0.45 if a_sp == "mail" or a_tid in ["dwarf_mail", "steppe_lamellar"] else (0.36 if lamellar else 0.20)))
		var a_pts: PackedVector2Array = _garment_pts(f, a_hem, spread * 0.7, a_sp)
		sh.poly(a_pts, c_arm_d if a_sp == "scrap" else c_arm, 1.0, 2.3)
		sh.ellipsoid(sc + Vector2(0.05, 1.45), float(f.tw) * 0.40, 1.68, c_arm, 1.5, 1.1)
		sh.capsule(sc + Vector2(-1.05, 0.16), sc + Vector2(0.10, 0.88), 0.20, 0.20, c_arm_t, 2.1, 0.9)
		sh.capsule(sc + Vector2(1.05, 0.16), sc + Vector2(0.10, 0.88), 0.20, 0.20, c_arm_t, 2.1, 0.9)
		if lamellar or scale_a:
			for ri in 3:
				var ry: float = sc.y + 1.15 + float(ri) * 1.25
				var rw: float = float(f.tw) * 0.38
				sh.capsule(Vector2(-rw, ry), Vector2(rw, ry), 0.22, 0.22, c_sec if ri == 1 else c_arm_t, 2.2, 0.9)
		elif plate:
			sh.capsule(sc + Vector2(0.10, 0.45), sc.lerp(hip, 0.68) + Vector2(0.10, 0.0), 0.32, 0.26, c_arm, 2.4, 1.1)
		if not mounted:
			sh.capsule(hip + Vector2(-float(f.hipw) * 0.42, a_hem - 0.10), hip + Vector2(float(f.hipw) * 0.42, a_hem - 0.10), 0.18, 0.18, c_arm_t, 2.1, 0.9)

	# Elven waist belt & clasp
	var belt: Vector2 = hip.lerp(sc, 0.16)
	var bw: float = float(f.hipw) * 0.42
	sh.capsule(belt + Vector2(-bw, 0.0), belt + Vector2(bw, 0.0), 0.28, 0.28, c_leath, 2.5, 1.0)
	sh.ellipsoid(belt + Vector2(0.65, 0.0), 0.38, 0.30, c_trim, 2.8, 1.0)

	sh.composite(FigurePainter.ol(f.prim), true)
	return true

static func _legacy_torso(f) -> bool:
	var cv: PixelCanvas = f.cv
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var spread: float = f._spread()*0.7
	cv.begin()
	cv.poly(_body_pts(f,0.6),f.skin,_surface(f,sc,"skin"))
	f._skin_end()
	var cl: Dictionary = f._it("clothing")
	var race: String = String(f.spec.get("race","moon_elf"))
	if not cl.is_empty():
		var padded: bool = String(cl.get("tid","")) == "gambeson"
		var kind: String = "gambeson" if padded else "cloth"
		var hem: float = float(f.leg_len)*(0.36 if padded else 0.32)
		var pts: PackedVector2Array = _garment_pts(f,hem,spread,kind)
		var cloth: Color = f.prim
		var edge: Color = f.sec.darkened(0.08)
		cv.begin()
		cv.poly(pts,cloth,_wardrobe_surface(f,sc,kind))
		# Bound neckline and real garment overlap vary by culture, in faction dyes.
		_path(cv,sc,[[-1.1,0.10],[-0.55,0.65],[0.0,0.85],[0.75,0.53],[1.10,0.10]],0.17,edge)
		if race == "high_elf":
			cv.capsule(sc+Vector2(0.10,0.9),hip+Vector2(0.10,hem-0.4),0.12,edge)
		elif race == "moon_elf":
			cv.capsule(sc+Vector2(-0.9,0.6),sc.lerp(hip,0.58)+Vector2(0.65,0.0),0.15,edge)
		else:
			cv.capsule(sc+Vector2(0.8,0.5),hip+Vector2(-0.65,0.05),0.14,edge)
		var belt: Vector2 = hip.lerp(sc,0.14)
		cv.capsule(belt+Vector2(-float(f.hipw)*0.41,0),belt+Vector2(float(f.hipw)*0.41,0),0.25,FigurePainter.LEATHER)
		cv.ellipse(belt+Vector2(0.75,0),0.26,0.22,FigurePainter.metal("copper")["light"])
		_garment_hem(cv,pts,edge,0.14)
		cv.end(FigurePainter.ol(cloth),0.10)
	var body: Dictionary = f._it("body")
	if body.is_empty(): return true
	var sp: String = String(body.get("sprite",""))
	var m: Dictionary = FigurePainter.metal(String(body.get("mat","copper")),int(body.get("q",0)))
	var hem: float = float(f.leg_len)*0.3
	match sp:
		"mail": hem = float(f.leg_len)*0.47
		"byrnie": hem = float(f.leg_len)*0.19
		"scale": hem = float(f.leg_len)*0.15
		"lamellar": hem = float(f.leg_len)*0.38
	var tid: String = String(body.get("tid",""))
	if tid == "dwarf_mail": hem = float(f.leg_len)*0.56
	elif tid == "steppe_lamellar": hem = float(f.leg_len)*0.54
	elif sp == "scrap": hem = float(f.leg_len)*0.16
	var pts: PackedVector2Array = _garment_pts(f,hem,spread,sp)
	cv.begin()
	cv.poly(pts,m["dark"] if sp == "scrap" else m["base"],_wardrobe_surface(f,sc,sp,m))
	if sp == "scrap": _scrap_panels(f,sc,hip,m)
	# A shaped neck opening and side binding give mail/scale thickness, without plate.
	_path(cv,sc,[[-1.12,0.15],[-0.58,0.75],[0.10,0.90],[0.88,0.55],[1.10,0.14]],0.16,m["dark"])
	if sp == "lamellar":
		if tid == "steppe_lamellar":
			cv.capsule(sc+Vector2(0.95,0.95),hip+Vector2(-0.35,hem-0.50),0.15,m["dark"])
		_path(cv,sc,[[-1.02,0.34],[-0.50,0.84],[0.15,0.96],[0.87,0.65]],0.12,m["light"])
		# Curved rows are laced; no monolithic decorative breastplate is substituted.
		var waist: Vector2 = sc.lerp(hip,0.67)
		cv.capsule(waist+Vector2(-float(f.hipw)*0.30,0.1),waist+Vector2(float(f.hipw)*0.30,0.1),0.15,f.sec.darkened(0.2))
		cv.capsule(hip+Vector2(0.2,0.4),hip+Vector2(0.2,hem-0.65),0.13,m["dark"])
	elif sp in ["mail","byrnie"]:
		var belt: Vector2 = hip.lerp(sc,0.13)
		cv.capsule(belt+Vector2(-float(f.hipw)*0.40,0),belt+Vector2(float(f.hipw)*0.40,0),0.25,FigurePainter.LEATHER)
		cv.ellipse(belt+Vector2(0.75,0),0.26,0.22,m["trim"])
	if int(m.get("q",0))>=1: _garment_hem(cv,pts,m["trim"],0.13)
	else: _garment_hem(cv,pts,m["dark"],0.09)
	f._metal_end(m)
	return true

static func arm(f,side: String) -> bool:
	if _force_legacy_v064:
		return _legacy_arm(f, side)
	var body: String = String(f._it("body").get("sprite", ""))
	var body_tid: String = String(f._it("body").get("tid", ""))
	var cv: PixelCanvas = f.cv
	var sh_pt: Vector2 = f.j["s" + side]
	var el: Vector2 = f.j["e" + side]
	var hd: Vector2 = f.j["h" + side]
	var r: float = float(f.arm_r)
	if f._lost("arm_upper_" + side):
		cv.dot(sh_pt, FigurePainter.BLOOD)
		return true
	var lower_lost: bool = f._lost("arm_lower_" + side)
	var hand_lost: bool = f._lost("hand_" + side)
	var cl: Dictionary = f._it("clothing")
	var padded: bool = String(cl.get("tid", "")) == "gambeson"
	var skin_c: Color = f.skin.darkened(0.08) if side == "l" else f.skin

	var sh := cv.shaded()
	var c_skin: int = sh.add_color(skin_c, 0.14, 1.06)
	var c_cloth: int = sh.add_color(f.prim.darkened(0.08 if side == "l" else 0.0), 0.10, 1.08)
	var c_sec: int = sh.add_color(f.sec, 0.18, 1.10)

	sh.capsule(sh_pt, el, r * 1.02, r * 0.78, c_skin, 0.0, 1.0)
	if not lower_lost:
		sh.capsule(el, hd, r * 0.84, r * 0.66, c_skin, 0.2, 1.0)

	# Tunic / gambeson sleeve
	if not cl.is_empty():
		var sl_end: Vector2 = sh_pt.lerp(el, 0.92 if padded else 0.76)
		sh.capsule(sh_pt, sl_end, r * (1.18 if padded else 1.08), r * (0.94 if padded else 0.82), c_cloth, 0.5, 1.0)
		sh.capsule(sl_end + Vector2(-r * 0.6, 0.0), sl_end + Vector2(r * 0.6, 0.0), 0.16, 0.16, c_sec, 0.8, 0.9)

	# Armour sleeve / leaf pauldron
	if not f._it("body").is_empty() and body not in ["gambeson", "padded"]:
		var m: Dictionary = FigurePainter.metal(String(f._it("body").get("mat", "copper")), int(f._it("body").get("q", 0)))
		var mail: bool = body in ["mail", "byrnie"] or body_tid == "dwarf_mail"
		var c_arm: int = sh.add_color(m["base"].darkened(0.08 if side == "l" else 0.0), 0.34 if not mail else 0.28, 1.16, m["shine"], 0.12 if mail else 0.04)
		var c_trim: int = sh.add_color(m["trim"], 0.36, 1.18, m["shine"])
		var a_end: Vector2 = sh_pt.lerp(el, 0.52 if body == "byrnie" else 0.72)
		sh.capsule(sh_pt, a_end, r * 1.18, r * 0.92, c_arm, 1.1, 1.05)
		if body in ["lamellar", "scale", "plate", "scrap"] or body_tid == "steppe_lamellar":
			sh.ellipsoid(sh_pt + Vector2(0.0, 0.12), r * 1.32, r * 1.15, c_arm, 1.5, 1.1)
			sh.capsule(a_end + Vector2(-r * 0.65, 0.0), a_end + Vector2(r * 0.65, 0.0), 0.16, 0.16, c_trim, 1.6, 0.9)

	# Vambraces / arm rings / gauntlets & graceful elven hand
	if not lower_lost:
		var hands: Dictionary = f._it("hands")
		if not hands.is_empty():
			var hm: Dictionary = FigurePainter.metal(String(hands.get("mat", "copper")), int(hands.get("q", 0)))
			var c_hnd: int = sh.add_color(hm["base"].darkened(0.08 if side == "l" else 0.0), 0.32, 1.16, hm["shine"])
			if String(hands.get("tid", "")) == "arm_rings":
				sh.capsule(el.lerp(hd, 0.42), el.lerp(hd, 0.54), r * 0.92, r * 0.88, c_hnd, 1.3, 1.0)
				sh.capsule(el.lerp(hd, 0.72), el.lerp(hd, 0.82), r * 0.80, r * 0.76, c_hnd, 1.3, 1.0)
			else:
				sh.capsule(el.lerp(hd, 0.18), el.lerp(hd, 0.82), r * 0.95, r * 0.74, c_hnd, 1.3, 1.05)
			if String(hands.get("tid", "")) == "dwarf_gauntlets" and not hand_lost:
				sh.ellipsoid(hd, r * 0.86, r * 0.92, c_hnd, 1.6, 1.0)
			elif not hand_lost:
				sh.ellipsoid(hd, r * 0.82, r * 0.90, c_skin, 0.8, 1.0)
		elif not hand_lost:
			sh.ellipsoid(hd, r * 0.82, r * 0.90, c_skin, 0.8, 1.0)

	sh.composite(FigurePainter.ol(skin_c), true)
	if lower_lost:
		cv.dot(el, FigurePainter.BLOOD)
	elif hand_lost:
		cv.dot(hd, FigurePainter.BLOOD)
	return true

static func _legacy_arm(f,side: String) -> bool:
	var body: String = String(f._it("body").get("sprite",""))
	var body_tid: String = String(f._it("body").get("tid",""))
	var cv: PixelCanvas = f.cv
	var sh: Vector2 = f.j["s"+side]
	var el: Vector2 = f.j["e"+side]
	var hd: Vector2 = f.j["h"+side]
	var r: float = float(f.arm_r)
	if f._lost("arm_upper_"+side):
		cv.dot(sh,FigurePainter.BLOOD)
		return true
	var lower_lost: bool = f._lost("arm_lower_"+side)
	var hand_lost: bool = f._lost("hand_"+side)
	cv.begin()
	_segment(cv,sh,el,r*1.03,r*0.76,f.skin)
	if not lower_lost:
		_segment(cv,el,hd,r*0.84,r*0.66,f.skin)
		if not hand_lost: cv.ellipse(hd,r*0.82,r*0.95,f.skin)
	f._skin_end()
	var cl: Dictionary = f._it("clothing")
	var padded: bool = String(cl.get("tid","")) == "gambeson"
	var sleeve: Dictionary = f._sleeve_style()
	if body in ["mail","byrnie"] and not cl.is_empty():
		# The short byrnie must leave the actual undergarment sleeve visible below it.
		var under_end: Vector2 = sh.lerp(el,0.93 if padded else 0.70)
		cv.begin()
		_segment(cv,sh,under_end,r*(1.19 if padded else 1.08),r*(0.95 if padded else 0.79),f.prim,_wardrobe_surface(f,sh,"gambeson" if padded else "cloth"))
		cv.end(FigurePainter.ol(f.prim),0.10)
	if body == "byrnie":
		var byrnie: Dictionary = FigurePainter.metal(String(f._it("body").get("mat","copper")),int(f._it("body").get("q",0)))
		sleeve = {"c":byrnie["base"],"ol":byrnie["outline"],"len":0.50}
	if not sleeve.is_empty():
		var length: float = float(sleeve["len"])
		if padded and body not in ["mail","byrnie"]: length = 0.93
		var end: Vector2 = sh.lerp(el,length)
		var kind: String = "gambeson" if padded else "cloth"
		var m: Dictionary = {}
		if body in ["mail","byrnie"]:
			kind = body
			m = FigurePainter.metal(String(f._it("body").get("mat","copper")),int(f._it("body").get("q",0)))
		cv.begin()
		var heavy_mail: bool = body_tid == "dwarf_mail"
		_segment(cv,sh,end,r*(1.19 if padded else (1.17 if heavy_mail else 1.08)),r*(0.95 if padded else (0.89 if heavy_mail else 0.79)),sleeve["c"],_wardrobe_surface(f,sh,kind,m))
		var axis: Vector2 = (end-sh).normalized()
		var n: Vector2 = Vector2(-axis.y,axis.x)
		var cuff: Color = m["dark"] if not m.is_empty() else f.sec.darkened(0.12)
		cv.capsule(end-n*r*0.63,end+n*r*0.63,0.13,cuff)
		cv.end(sleeve["ol"],0.10)
	if lower_lost: cv.dot(el,FigurePainter.BLOOD)
	elif hand_lost: cv.dot(hd,FigurePainter.BLOOD)
	if not lower_lost:
		var hands: Dictionary = f._it("hands")
		if not hands.is_empty():
			var m: Dictionary = FigurePainter.metal(String(hands.get("mat","copper")),int(hands.get("q",0)))
			if String(hands.get("tid","")) == "arm_rings":
				cv.capsule(el.lerp(hd,0.45),el.lerp(hd,0.52),r*0.88,m["light"])
				cv.capsule(el.lerp(hd,0.74),el.lerp(hd,0.80),r*0.75,m["shine"])
			else:
				var crude: bool = String(hands.get("tid","")) == "crude_bracers"
				_plate_shell(f,el.lerp(hd,0.31 if crude else 0.14),el.lerp(hd,0.78),r*0.91,r*0.68,m)
				if String(hands.get("tid","")) == "dwarf_gauntlets" and not hand_lost:
					cv.begin()
					cv.ellipse(hd,r*0.84,r*0.95,m["base"])
					cv.capsule(hd+Vector2(-r*0.47,-0.25),hd+Vector2(r*0.42,-0.25),0.12,m["light"])
					cv.capsule(hd+Vector2(-r*0.37,0.23),hd+Vector2(r*0.40,0.23),0.09,m["dark"])
					f._metal_end(m)
	if body == "lamellar" and (side == "r" or body_tid == "steppe_lamellar"):
		var m: Dictionary = FigurePainter.metal(String(f._it("body").get("mat","copper")),int(f._it("body").get("q",0)))
		var end: Vector2 = sh.lerp(el,0.48 if body_tid == "steppe_lamellar" else 0.32)
		cv.begin()
		_segment(cv,sh+Vector2(-0.18,-0.25),end,r*1.26,r*1.04,m["base"],_wardrobe_surface(f,sh,"lamellar",m))
		f._metal_end(m)
	if body == "scrap" and side == "r":
		var m: Dictionary = FigurePainter.metal(String(f._it("body").get("mat","copper")),int(f._it("body").get("q",0)))
		_plate_shell(f,sh+Vector2(-0.18,-0.25),sh.lerp(el,0.30),r*1.27,r*1.00,m)
		cv.ellipse(sh+Vector2(-r*0.64,0.0),0.14,0.14,m["shine"])
		cv.ellipse(sh.lerp(el,0.25)+Vector2(r*0.54,0.0),0.12,0.12,m["shine"])
	return true

static func leg(f,side: String) -> bool:
	if _force_legacy_v064:
		return _legacy_leg(f, side)
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p" + side]
	var kn: Vector2 = f.j["k" + side]
	var ft: Vector2 = f.j["f" + side]
	var r: float = float(f.leg_r)
	if f._lost("leg_upper_" + side):
		cv.dot(hp, FigurePainter.BLOOD)
		return true
	var trousers: bool = not f._it("legs_under").is_empty()
	var col: Color = f._trouser_col() if trousers else f.skin
	if side == "l":
		col = col.darkened(0.08)
	var lower_lost: bool = f._lost("leg_lower_" + side)
	var foot_lost: bool = f._lost("foot_" + side)
	var greaves: Dictionary = f._it("legs")
	var shoe: Dictionary = f._it("feet")

	var sh := cv.shaded()
	var c_leg: int = sh.add_color(col, 0.10 if trousers else 0.14, 1.08)
	sh.capsule(hp, kn, r * 1.04, r * 0.74, c_leg, 0.0, 1.05)
	if not lower_lost:
		sh.capsule(kn, ft, r * 0.84, r * 0.56, c_leg, 0.2, 1.0)
		if not greaves.is_empty():
			var gm: Dictionary = FigurePainter.metal(String(greaves.get("mat", "copper")), int(greaves.get("q", 0)))
			var c_grv: int = sh.add_color(gm["base"].darkened(0.08 if side == "l" else 0.0), 0.34, 1.18, gm["shine"])
			var c_trim: int = sh.add_color(gm["trim"], 0.38, 1.18, gm["shine"])
			sh.ellipsoid(kn + Vector2(0.10, 0.0), r * 0.92, r * 0.78, c_grv, 1.2, 1.0)
			sh.capsule(kn.lerp(ft, 0.06), kn.lerp(ft, 0.90), r * 0.94, r * 0.62, c_grv, 1.0, 1.05)
			if String(greaves.get("tid", "")) == "moon_greaves":
				sh.capsule(kn + Vector2(-0.15, -0.35), kn + Vector2(0.45, 0.15), 0.18, 0.16, c_trim, 1.5, 0.95)
		if not foot_lost:
			var boot_c: Color = f.skin if shoe.is_empty() else Color(DB.materials.get(String(shoe.get("mat", "leather")), {}).get("color", "#4a3020"))
			if side == "l":
				boot_c = boot_c.darkened(0.08)
			var c_boot: int = sh.add_color(boot_c, 0.18 if not shoe.is_empty() else 0.12, 1.12)
			sh.capsule(ft + Vector2(-0.45, -0.30), ft + Vector2(1.55, 0.55), r * 0.68, r * 0.58, c_boot, 1.3, 1.0)

	sh.composite(FigurePainter.ol(col), true)
	if lower_lost:
		cv.dot(kn, FigurePainter.BLOOD)
	elif foot_lost:
		cv.dot(ft, FigurePainter.BLOOD)
	return true

static func _legacy_leg(f,side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p"+side]
	var kn: Vector2 = f.j["k"+side]
	var ft: Vector2 = f.j["f"+side]
	var r: float = float(f.leg_r)
	if f._lost("leg_upper_"+side):
		cv.dot(hp,FigurePainter.BLOOD)
		return true
	var trousers: bool = not f._it("legs_under").is_empty()
	var col: Color = f._trouser_col() if trousers else f.skin
	if side == "l": col = col.darkened(0.08)
	var lower_lost: bool = f._lost("leg_lower_"+side)
	var foot_lost: bool = f._lost("foot_"+side)
	cv.begin()
	_segment(cv,hp,kn,r*(1.02 if trousers else 0.99),r*(0.65 if trousers else 0.72),col)
	if not lower_lost:
		_segment(cv,kn,kn.lerp(ft,0.42),r*(0.65 if trousers else 0.72),r*(0.79 if trousers else 0.85),col)
		_segment(cv,kn.lerp(ft,0.42),ft,r*(0.79 if trousers else 0.85),r*(0.50 if trousers else 0.54),col)
		if not foot_lost:
			var shoe: Dictionary = f._it("feet")
			if shoe.is_empty():
				_poly(cv,ft,[[-0.9,-0.45],[0.65,-0.6],[2.3,0.4],[2.45,1.3],[-1.05,1.25]],f.skin)
			else:
				var leather: Color = Color(DB.materials.get(String(shoe.get("mat","leather")),{}).get("color","#4a3020"))
				_poly(cv,ft,[[-0.84,-0.51],[0.55,-0.62],[1.53,-0.04],[2.28,0.55],[2.30,1.04],[-0.91,1.03]],leather.darkened(0.08))
	if trousers: cv.end(FigurePainter.ol(col),0.12)
	else: f._skin_end()
	if trousers:
		cv.capsule(hp.lerp(kn,0.15)+Vector2(-r*0.31,0),kn+Vector2(-r*0.18,0),0.09,col.lightened(0.17))
		if not lower_lost:
			cv.capsule(kn.lerp(ft,0.28)+Vector2(-r*0.17,0),kn.lerp(ft,0.84)+Vector2(-r*0.10,0),0.08,col.lightened(0.13))
	if lower_lost: cv.dot(kn,FigurePainter.BLOOD)
	elif foot_lost: cv.dot(ft,FigurePainter.BLOOD)
	else:
		var shoe: Dictionary = f._it("feet")
		if not shoe.is_empty():
			var leather: Color = Color(DB.materials.get(String(shoe.get("mat","leather")),{}).get("color","#4a3020"))
			cv.capsule(ft+Vector2(-0.76,0.97),ft+Vector2(2.22,0.97),0.12,leather.darkened(0.40))
			cv.capsule(ft+Vector2(-0.40,-0.30),ft+Vector2(0.96,0.06),0.11,leather.lightened(0.19))
	if not lower_lost:
		var greaves: Dictionary = f._it("legs")
		if not greaves.is_empty():
			var m: Dictionary = FigurePainter.metal(String(greaves.get("mat","copper")),int(greaves.get("q",0)))
			var moon: bool = String(greaves.get("tid","")) == "moon_greaves"
			_plate_shell(f,kn.lerp(ft,0.06)+Vector2(0.12,0.0),kn.lerp(ft,0.91)+Vector2(0.12,0.0),r*(0.91 if moon else 0.95),r*0.57,m)
	return true

# The actual crescent_helm item, independent of the wearer's culture or sex.
# This owns complete metal parts and its shaped opening; the caller returns afterwards.
static func worn_crescent_helm(f,hc: Vector2,m: Dictionary) -> void:
	if f._lost("head"):
		return
	if _force_legacy_v064:
		_legacy_worn_crescent_helm(f, hc, m)
		return
	var cv: PixelCanvas = f.cv
	var half: float = float(f.head_w) * 0.5
	var rise: float = (float(f.head_h) - 6.0) * -0.5
	var origin: Vector2 = hc + Vector2(0.0, rise)
	var rear: float = -half - 0.64
	var temple: float = -maxf(2.30, half * 0.72)
	var jaw_tip: float = (rear + temple) * 0.5
	var front: float = half + 0.34

	var sh := cv.shaded()
	var c_base: int = sh.add_color(m["base"], 0.36, 1.18, m["shine"])
	var c_trim: int = sh.add_color((m["light"] as Color).lerp(m["trim"], 0.35), 0.38, 1.18, m["shine"])
	var bowl := PackedVector2Array([
		origin + Vector2(rear + 0.08, 0.42), origin + Vector2(rear - 0.18, -0.60),
		origin + Vector2(rear - 0.22, -1.70), origin + Vector2(rear + 0.05, -3.12),
		origin + Vector2(-half * 0.68, -4.16), origin + Vector2(-half * 0.10, -4.70),
		origin + Vector2(half * 0.49, -4.54), origin + Vector2(half * 0.91, -3.93),
		origin + Vector2(front, -3.12), origin + Vector2(front, -2.43),
		origin + Vector2(half + 0.20, -2.02), origin + Vector2(half - 0.14, -2.08),
		origin + Vector2(half * 0.42, -2.11), origin + Vector2(-0.10, -2.18),
		origin + Vector2(temple, -2.20), origin + Vector2(temple - 0.08, 0.05),
		origin + Vector2(temple - 0.14, 0.87), origin + Vector2(jaw_tip, 1.61),
		origin + Vector2(rear + 0.36, 1.12)
	])
	sh.poly(bowl, c_base, 2.4, 2.2)
	sh.capsule(origin + Vector2(temple + 0.04, -2.25), origin + Vector2(half + 0.15, -2.15), 0.18, 0.18, c_trim, 3.4, 0.95)
	sh.capsule(origin + Vector2(temple - 0.18, -2.15), origin + Vector2(jaw_tip, 1.45), 0.22, 0.18, c_trim, 3.2, 0.95)
	sh.composite(m["outline"], true)
	helm_crescent(f, hc, -4.70 + rise, m)

static func _legacy_worn_crescent_helm(f,hc: Vector2,m: Dictionary) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var half: float = float(f.head_w)*0.5
	var rise: float = (float(f.head_h)-6.0)*-0.5
	var origin: Vector2 = hc+Vector2(0.0,rise)
	var rear: float = -half-0.64
	var temple: float = -maxf(2.30,half*0.72)
	var jaw_tip: float = (rear+temple)*0.5
	var front: float = half+0.34
	var base: Color = m["base"]
	var light: Color = m["light"]
	var dark: Color = m["dark"]
	var shine: Color = m["shine"]
	var rim: Color = light.lerp(m["trim"],0.30)
	var pat: Callable = f._helm_surface(hc,-float(f.head_h)*0.5,m)
	# The bowl wraps the back of the skull, rounding inward to a tapered jaw tip.
	# Its face opening follows the forged contour, with no rectangular cutout.
	cv.begin()
	_contour(cv,origin,[[rear+0.08,0.42],[rear-0.18,-0.60],[rear-0.22,-1.70],
		[rear+0.05,-3.12],[-half*0.68,-4.16],[-half*0.10,-4.70],
		[half*0.49,-4.54],[half*0.91,-3.93],[front,-3.12],[front,-2.43],
		[half+0.20,-2.02],[half-0.14,-2.08],[half*0.42,-2.11],[-0.10,-2.18],
		[temple,-2.20],[temple-0.03,-1.18],[temple-0.08,0.05],
		[temple-0.14,0.87],[jaw_tip,1.61],[rear+0.36,1.12]],base,pat)
	# Unequal planes retain the three-quarter volume, down to the lower forehead.
	_contour(cv,origin,[[rear+0.34,-2.80],[-half*0.65,-3.94],[-0.28,-4.49],
		[half*0.37,-4.25],[half*0.22,-3.19],[-0.28,-2.52],[temple+0.11,-2.64]],light)
	_poly(cv,origin,[[half*0.46,-4.34],[half*0.87,-3.85],[front-0.09,-3.10],
		[half+0.08,-2.20],[half*0.42,-2.28],[half*0.24,-3.20]],base.lerp(dark,0.42))
	_contour(cv,origin,[[rear+0.13,-2.66],[temple-0.20,-2.40],
		[temple-0.24,-0.20],[temple-0.31,0.85],[jaw_tip,1.35],
		[rear+0.27,0.58],[rear+0.03,-0.57]],base.lerp(dark,0.25))
	# Rolled edge sits just above the eyes, preserving the real eye/lash opening.
	_path(cv,origin,[[temple+0.04,-2.39],[-0.22,-2.35],[half*0.45,-2.29],
		[half-0.11,-2.25],[half+0.15,-2.20]],0.105,rim)
	_path(cv,origin,[[rear+0.20,-2.58],[rear+0.04,-1.35],[rear+0.18,-0.20],
		[rear+0.43,0.77],[jaw_tip,1.38],[temple-0.27,1.03]],0.10,rim)
	# A curved strengthening fold follows the taper, rather than a straight panel.
	_path(cv,origin,[[temple-0.28,-2.31],[temple-0.44,-1.36],
		[temple-0.31,-0.43],[temple-0.24,0.50],[jaw_tip,0.98]],0.09,dark)
	_path(cv,origin,[[-half*0.54,-3.97],[-half*0.38,-3.55],[-half*0.24,-3.08]],0.10,shine)
	for p: Vector2 in [Vector2(temple-0.42,-2.05),Vector2(temple-0.45,0.84),
		Vector2(half*0.82,-3.44)]:
		cv.ellipse(origin+p,0.085,0.10,shine)
	f._metal_end(m)
	helm_crescent(f,hc,-4.70+rise,m)

# Overlay for an actual moon-elf-made helmet. top is the bowl's local crown Y
# relative to hc; caller retains its own nasal/coif/kettle/spangen construction.
static func helm_crescent(f,hc: Vector2,top: float,m: Dictionary) -> void:
	if f._lost("head"):
		return
	if _force_legacy_v064:
		_legacy_helm_crescent(f, hc, top, m)
		return
	var cv: PixelCanvas = f.cv
	var half: float = float(f.head_w) * 0.5
	var origin: Vector2 = hc + Vector2(-0.12, top - 0.02)
	var crest_width: float = clampf(half / 2.5, 0.92, 1.35)
	var sh := cv.shaded()
	var c_crest: int = sh.add_color((m["light"] as Color).lerp(m["trim"], 0.35), 0.38, 1.18, m["shine"])
	var crest := PackedVector2Array()
	for p: Array in [[0.48, -1.14], [-0.18, -1.17], [-0.82, -0.88], [-1.21, -0.33],
		[-1.24, 0.34], [-0.80, 0.90], [-0.19, 1.12], [0.49, 1.00], [1.00, 0.55],
		[0.53, 0.67], [0.09, 0.57], [-0.26, 0.24], [-0.34, -0.20],
		[-0.16, -0.67], [0.14, -1.00]]:
		crest.append(origin + Vector2(float(p[0]) * crest_width, float(p[1])))
	sh.poly(crest, c_crest, 3.2, 1.6)
	sh.capsule(origin + Vector2(-0.55 * crest_width, 0.85), origin + Vector2(-0.12 * crest_width, 1.18), 0.28, 0.28, c_crest, 3.0, 0.95)
	sh.composite(m["outline"], true)

static func _legacy_helm_crescent(f,hc: Vector2,top: float,m: Dictionary) -> void:
	if f._lost("head"):
		return
	var cv: PixelCanvas = f.cv
	var half: float = float(f.head_w)*0.5
	var origin: Vector2 = hc+Vector2(-0.12,top-0.02)
	var base: Color = m["base"]
	var light: Color = m["light"]
	var dark: Color = m["dark"]
	var shine: Color = m["shine"]
	var rim: Color = light.lerp(m["trim"],0.30)
	var pat: Callable = f._helm_surface(hc,-float(f.head_h)*0.5,m)
	var crest_width: float = clampf(half/2.5,0.92,1.35)
	# A full curved crescent with unequal pointed tips opens toward the upper
	# right. Its thick left/lower arc reads at battle scale; the inward bite is
	# part of the silhouette, rather than a downward-facing arch on the bowl.
	var crest: PackedVector2Array = PackedVector2Array()
	for p: Array in [[0.48,-1.14],[-0.18,-1.17],[-0.82,-0.88],[-1.21,-0.33],
		[-1.24,0.34],[-0.80,0.90],[-0.19,1.12],[0.49,1.00],[1.00,0.55],
		[0.53,0.67],[0.09,0.57],[-0.26,0.24],[-0.34,-0.20],
		[-0.16,-0.67],[0.14,-1.00]]:
		crest.append(origin+Vector2(float(p[0])*crest_width,float(p[1])))
	cv.begin()
	# Short forged saddle seats the moon's lower arc against the actual crown.
	_poly(cv,origin,[[-0.69*crest_width,0.67],[-0.22*crest_width,0.72],
		[-0.04*crest_width,1.23],[-0.60*crest_width,1.25]],base,pat)
	cv.poly(crest,light,pat)
	# Shade the inward curve and catch light on the upper-left outer metal.
	_path(cv,origin,[[0.46*crest_width,0.68],[0.08*crest_width,0.55],
		[-0.26*crest_width,0.23],[-0.34*crest_width,-0.19],
		[-0.17*crest_width,-0.64]],0.075,dark)
	_path(cv,origin,[[-1.05*crest_width,-0.31],[-0.76*crest_width,-0.75],
		[-0.19*crest_width,-1.05],[0.22*crest_width,-1.07]],0.075,shine)
	_path(cv,origin,[[-1.07*crest_width,0.30],[-0.70*crest_width,0.78],
		[-0.19*crest_width,0.99],[0.40*crest_width,0.88]],0.065,rim)
	_stroke(cv,origin,Vector2(-0.52*crest_width,1.10),
		Vector2(-0.18*crest_width,1.12),0.07,dark)
	f._metal_end(m)
