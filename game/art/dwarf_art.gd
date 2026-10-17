class_name DwarfArt
extends RefCounted

const HEAD_SCALE: float = 0.79
## Dwarven anatomy and cloth surfaces on FigurePainter's original moving joint graph.
## Seed chooses hair/grooming, never equipment. Native wounds and helm remain the final layers.

static func _poly(cv: PixelCanvas, o: Vector2, points: Array, c: Color, pat: Callable = Callable()) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for p in points:
		pts.append(o + Vector2(float(p[0]), float(p[1])))
	cv.poly(pts, c, pat)

static func _stroke(cv: PixelCanvas, o: Vector2, a: Vector2, b: Vector2, r: float, c: Color) -> void:
	cv.capsule(o+a, o+b, r, c)

static func _hair_surface(f, hc: Vector2, beard: bool) -> Callable:
	var inv: Transform2D = f.cv.xf.affine_inverse()
	var phase: float = float(posmod(int(f.spec.get("seed",0)),5))*0.13
	return func(x: int, y: int, c: Color) -> Color:
		var p: Vector2 = inv*Vector2(float(x)+0.5,float(y)+0.5)-hc
		var strand: float = fposmod(p.x+(0.12*p.y if beard else -0.37*p.y)+phase,0.72)
		var out: Color = c.darkened(0.15) if p.x < -1.4 else c
		if strand < 0.16: return out.lightened(0.13)
		if strand > 0.59: return out.darkened(0.13)
		return out.lightened(0.10) if p.y < -2.6 else out

static func head(f) -> void:
	if f._lost("head"): return
	var cv: PixelCanvas = f.cv
	var before: Transform2D = cv.xf
	var before_k: float = cv.k
	var hc: Vector2 = f.j["hc"]
	# Draw the accepted face, hair, beard and fitted helm together around the native head anchor.
	cv.xf = before*Transform2D(0.0,Vector2(HEAD_SCALE,HEAD_SCALE),0.0,hc*(1.0-HEAD_SCALE))
	cv.k = before_k*HEAD_SCALE
	_native_head(f)
	cv.xf = before
	cv.k = before_k

static func _native_head(f) -> void:
	if f._lost("head"): return
	if String(f.spec.get("sex","")).to_lower() == "female":
		_female_head(f)
		return
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = absi(int(f.spec.get("seed",0)))
	var style: int = seed%5
	var female: bool = String(f.spec.get("sex","")).to_lower() == "female"
	var beard: bool = bool(f.spec.get("beard",false)) and not f._lost("jaw")
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead",false))
	var shadow: Color = skin.darkened(0.24).lerp(Color("#794333"),0.08)
	var deep: Color = skin.darkened(0.43).lerp(Color("#51322a"),0.17)
	var light: Color = skin.lightened(0.20)
	var cheek: float = 0.08*float((seed/5)%4)
	var nose: float = 0.08*float((seed/13)%4)
	var texture: Callable = _hair_surface(f,hc,false)
	# Heavy back hair is a rounded mass with separated ends, above the shoulder layer.
	if style in [1,3,4]:
		cv.begin()
		_poly(cv,hc,[[-2.8,-2.6],[-3.45,-1.3],[-3.64,0.55],[-3.32,2.1],[-3.57,3.43],[-2.75,4.15],
			[-2.22,3.61],[-1.53,3.93],[-1.55,1.4],[-1.8,-2.3]],hair.darkened(0.06),texture)
		cv.end(FigurePainter.ol(hair),0.07)
		_stroke(cv,hc,Vector2(-3.08,-0.9),Vector2(-2.81,2.92),0.13,hair.lightened(0.16))
	# A stout neck links to the native shoulders without moving either anchor.
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-1.7,1.9),hc+Vector2(1.7,2.35),sc+Vector2(1.7,0.75),sc+Vector2(-1.65,0.65)]),shadow)
		cv.end(FigurePainter.ol(skin),0.04)
	# Broad dome, compressed temples, fleshy cheeks and the hard turn of a mature jaw.
	cv.begin()
	_poly(cv,hc,[[-2.9,-1.82],[-2.25,-2.74],[-1.2,-3.18],[0.55,-3.16],[2.13,-2.61],[2.78,-1.66],
		[2.81,-0.73],[2.54,-0.23],[2.88,0.63],[2.7+cheek,1.58],[2.08,2.42],[0.85,3.0],
		[-0.88,2.88],[-2.34,1.96],[-2.85,0.72],[-3.0,-0.44]],skin)
	_poly(cv,hc,[[-2.79,-1.75],[-1.59,-2.85],[-1.42,-0.18],[-0.76,1.48],[0.47,2.78],[-0.93,2.77],[-2.26,1.85],[-2.84,0.42]],shadow)
	_poly(cv,hc,[[-1.2,-2.79],[0.49,-2.95],[1.95,-2.43],[2.44,-1.78],[1.12,-1.58],[-1.06,-1.75]],light)
	_poly(cv,hc,[[-0.21,0.09],[1.05,-0.14],[2.42,0.29],[2.57,0.77],[1.72,1.27],[0.09,0.96]],light)
	_poly(cv,hc,[[0.56,1.08],[2.65,0.87],[2.46,1.79],[1.28,2.55],[0.08,2.4],[-0.45,1.76]],skin.darkened(0.10))
	# A low thick nasal bridge ends in a broad tip and rounded nostril wing.
	if not f._lost("nose"):
		_poly(cv,hc,[[2.1,-1.36],[2.71,-1.23],[2.94,-0.49],[3.65+nose,0.09],[3.88+nose,0.59],
			[3.36+nose,0.94],[2.55,0.82],[2.04,0.39]],skin)
		cv.ellipse(hc+Vector2(3.03+nose,0.35),0.65,0.38,light)
		_stroke(cv,hc,Vector2(2.48,-1.05),Vector2(2.76,-0.34),0.19,light)
		_stroke(cv,hc,Vector2(3.04,0.79),Vector2(3.55+nose,0.65),0.16,deep)
	cv.end(FigurePainter.ol(skin),0.05)
	if String(f._it("helm").get("sprite","")) != "coif" and not f._lost("ear_r"):
		cv.begin()
		cv.ellipse(hc+Vector2(-2.33,-0.05),0.75,0.91,skin)
		cv.end(FigurePainter.ol(skin),0.04)
		_stroke(cv,hc,Vector2(-2.51,-0.47),Vector2(-2.05,0.43),0.16,shadow)
		cv.ellipse(hc+Vector2(-2.07,0.02),0.25,0.32,deep)
	# Deep eyes under a projecting brow: the near eye is wider than the distant eye.
	var brow: Color = hair.darkened(0.22).lerp(deep,0.31)
	var eye: Color = [Color("#584032"),Color("#635a43"),Color("#5b6663"),Color("#4b4437")][(seed/7)%4]
	_eye(f,hc,Vector2(1.0,-0.72),0.72,eye,brow,dead,"eye_r",female)
	_eye(f,hc,Vector2(2.43,-0.83),0.33,eye,brow,dead,"eye_l",female)
	_stroke(cv,hc,Vector2(-0.15,-1.34),Vector2(0.39,-1.4),0.16,shadow)
	_stroke(cv,hc,Vector2(1.87,-1.49),Vector2(2.06,-1.11),0.12,deep)
	_stroke(cv,hc,Vector2(0.31,-0.03),Vector2(0.81,0.16),0.10,shadow)
	_stroke(cv,hc,Vector2(1.84,0.95),Vector2(1.57,1.34),0.10,shadow)
	# Seeded grooming includes a receding crown; no hats or decorations are invented.
	if style != 2:
		cv.begin()
		if style == 3:
			_poly(cv,hc,[[-2.9,-1.4],[-2.91,-2.44],[-1.69,-3.2],[-0.85,-3.4],[-1.04,-2.82],[-1.56,-2.09],[-1.8,-0.62],[-2.69,0.17]],hair,texture)
			_poly(cv,hc,[[1.4,-2.87],[2.35,-2.51],[2.72,-1.92],[1.89,-2.13]],hair,texture)
		else:
			_poly(cv,hc,[[-3.04,-1.09],[-3.13,-2.32],[-2.43,-3.14],[-1.17,-3.57],[0.32,-3.5],[1.76,-3.08],
				[2.69,-2.39],[2.5,-1.78],[1.66,-2.09],[0.95,-1.92],[0.22,-2.23],[-0.58,-1.84],[-1.47,-1.95],[-1.77,-0.68],[-2.58,0.06]],hair,texture)
			if style == 4 and f._it("helm").is_empty():
				cv.ellipse(hc+Vector2(-1.65,-3.46),0.98,0.72,hair,texture)
		cv.end(FigurePainter.ol(hair),0.07)
		_stroke(cv,hc,Vector2(-2.26,-2.81),Vector2(-0.98,-3.12),0.15,hair.lightened(0.22))
		_stroke(cv,hc,Vector2(-0.39,-3.11),Vector2(1.3,-2.79),0.13,hair.lightened(0.18))
		_stroke(cv,hc,Vector2(-2.28,-1.68),Vector2(-2.46,-0.48),0.13,hair.lightened(0.17))
	if beard:
		_beard(f,hc,seed)
	if not f._lost("mouth"):
		var lip: Color = skin.darkened(0.39).lerp(Color("#7a3730"),0.19)
		_stroke(cv,hc,Vector2(1.38,1.57),Vector2(2.68,1.48),0.13,lip)
		if not beard:
			_stroke(cv,hc,Vector2(1.49,1.8),Vector2(2.41,1.78),0.13,light)
	# The existing item-aware helmet covers the hair and face at the original placement.
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _retained_female_head(f) -> void:
	var cv: PixelCanvas = f.cv
	var hc: Vector2 = f.j["hc"]
	var skin: Color = f.skin
	var hair: Color = f.hair
	var seed: int = absi(int(f.spec.get("seed",0)))
	var style: int = seed%5
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead",false))
	var jaw_lost: bool = f._lost("jaw")
	var shadow: Color = skin.darkened(0.20).lerp(Color("#794333"),0.06)
	var deep: Color = skin.darkened(0.41).lerp(Color("#51322a"),0.13)
	var light: Color = skin.lightened(0.17)
	var cheek: float = 0.06*float((seed/5)%4)
	var nose: float = 0.06*float((seed/13)%4)
	var texture: Callable = _hair_surface(f,hc,false)
	# Retain the seed's crop, long, bald, receding or tied grooming family.
	if style in [1,3,4]:
		cv.begin()
		_poly(cv,hc,[[-2.5,-2.65],[-3.28,-1.6],[-3.55,0.26],[-3.37,1.55],[-3.67,2.86],[-3.38,4.0],
			[-2.73,4.48],[-2.4,3.55],[-1.84,3.94],[-1.63,2.39],[-1.76,-1.97]],hair.darkened(0.07),texture)
		if style == 1:
			_poly(cv,hc,[[-3.12,0.7],[-3.93,1.78],[-3.83,3.15],[-4.05,3.92],[-3.22,3.53],[-2.63,2.05]],hair,texture)
		cv.end(FigurePainter.ol(hair),0.06)
		_stroke(cv,hc,Vector2(-3.01,-0.69),Vector2(-2.87,1.51),0.14,hair.lightened(0.18))
		_stroke(cv,hc,Vector2(-3.18,2.19),Vector2(-2.91,3.68),0.12,hair.lightened(0.2))
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-1.22,1.84),hc+Vector2(1.39,2.22),sc+Vector2(1.44,0.67),sc+Vector2(-1.43,0.63)]),shadow)
		cv.end(FigurePainter.ol(skin),0.04)
	# Broad dwarf forehead and compact full cheeks end in a softer, smaller adult chin.
	cv.begin()
	if jaw_lost:
		_poly(cv,hc,[[-2.72,-1.74],[-2.17,-2.67],[-1.18,-3.15],[0.49,-3.13],[1.97,-2.67],[2.58,-1.79],
			[2.67,-0.89],[2.39,-0.27],[2.74,0.47],[2.69+cheek,1.14],[1.7,1.08],[0.69,1.1],
			[-0.8,0.93],[-2.18,0.93],[-2.61,0.43],[-2.81,-0.5]],skin)
		_poly(cv,hc,[[-2.61,-1.55],[-1.48,-2.76],[-1.28,-0.35],[-0.95,0.88],[-2.2,0.91],[-2.64,0.11]],shadow)
	else:
		_poly(cv,hc,[[-2.72,-1.74],[-2.17,-2.67],[-1.18,-3.15],[0.49,-3.13],[1.97,-2.67],[2.58,-1.79],
			[2.67,-0.89],[2.39,-0.27],[2.74,0.47],[2.69+cheek,1.14],[2.29,1.96],[1.55,2.56],
			[0.7,2.8],[-0.26,2.67],[-1.36,2.12],[-2.18,1.41],[-2.61,0.43],[-2.81,-0.5]],skin)
		_poly(cv,hc,[[-2.61,-1.55],[-1.48,-2.76],[-1.28,-0.35],[-0.95,0.99],[-0.18,2.35],[0.69,2.77],
			[-0.24,2.62],[-1.3,2.1],[-2.2,1.27],[-2.64,0.11]],shadow)
	_poly(cv,hc,[[-1.04,-2.71],[0.42,-2.91],[1.92,-2.44],[2.25,-1.81],[0.94,-1.57],[-1.02,-1.68]],light)
	_poly(cv,hc,[[-0.02,0.23],[0.94,-0.04],[2.35,0.19],[2.57,0.55],[2.04,1.11],[0.69,1.1],[0.13,0.77]],light)
	if not jaw_lost:
		_poly(cv,hc,[[0.3,1.28],[1.29,1.03],[2.43,1.07],[2.19,1.81],[1.43,2.39],[0.45,2.48],[-0.23,1.96]],skin.darkened(0.05))
	# The female bridge/tip is narrower but remains sturdy and unmistakably dwarven.
	if not f._lost("nose"):
		_poly(cv,hc,[[2.12,-1.2],[2.5,-1.08],[2.65,-0.43],[3.19+nose,0.06],[3.42+nose,0.47],
			[3.12+nose,0.72],[2.53,0.68],[2.12,0.31]],skin)
		cv.ellipse(hc+Vector2(2.91+nose,0.29),0.44,0.26,light)
		_stroke(cv,hc,Vector2(2.34,-0.98),Vector2(2.52,-0.31),0.14,light)
		_stroke(cv,hc,Vector2(2.84,0.61),Vector2(3.2+nose,0.54),0.12,deep)
	cv.end(FigurePainter.ol(skin),0.05)
	if String(f._it("helm").get("sprite","")) != "coif" and not f._lost("ear_r"):
		cv.begin()
		cv.ellipse(hc+Vector2(-2.16,-0.04),0.62,0.79,skin)
		cv.end(FigurePainter.ol(skin),0.04)
		_stroke(cv,hc,Vector2(-2.31,-0.37),Vector2(-1.97,0.3),0.13,shadow)
		cv.ellipse(hc+Vector2(-1.94,0.02),0.2,0.25,deep)
	var brow: Color = hair.darkened(0.21).lerp(deep,0.27)
	var iris: Color = [Color("#584032"),Color("#635a43"),Color("#5b6663"),Color("#4b4437")][(seed/7)%4]
	_retained_female_eye(f,hc,Vector2(0.96,-0.67),0.72,iris,brow,dead,"eye_r")
	_retained_female_eye(f,hc,Vector2(2.31,-0.78),0.32,iris,brow,dead,"eye_l")
	# Natural lips and the rounded chin are visible; race-inherited beard is suppressed.
	if not jaw_lost and not f._lost("mouth"):
		var lip: Color = skin.darkened(0.27).lerp(Color("#9b5148"),0.22)
		_poly(cv,hc,[[1.22,1.46],[1.6,1.32],[1.85,1.38],[2.09,1.27],[2.55,1.39],[2.26,1.57],[1.74,1.62]],lip)
		_stroke(cv,hc,Vector2(1.35,1.49),Vector2(2.45,1.42),0.09,deep)
		_stroke(cv,hc,Vector2(1.69,1.66),Vector2(2.24,1.61),0.1,skin.lightened(0.22))
	if not jaw_lost:
		_stroke(cv,hc,Vector2(0.75,2.32),Vector2(1.52,2.31),0.12,light)
	if int(f.spec.get("age",28))>=50:
		_stroke(cv,hc,Vector2(0.04,-0.12),Vector2(0.39,0.05),0.08,shadow)
		_stroke(cv,hc,Vector2(2.23,0.87),Vector2(2.14,1.13),0.08,shadow)
	if style != 2:
		cv.begin()
		if style == 3:
			_poly(cv,hc,[[-2.76,-0.79],[-2.96,-2.29],[-2.02,-3.05],[-0.87,-3.38],[-1.09,-2.77],[-1.53,-2.24],[-1.71,-0.55],[-2.43,0.15]],hair,texture)
			_poly(cv,hc,[[1.19,-2.98],[2.16,-2.64],[2.58,-1.95],[1.85,-2.16]],hair,texture)
		else:
			_poly(cv,hc,[[-2.95,-0.75],[-3.03,-2.13],[-2.29,-3.11],[-1.02,-3.59],[0.42,-3.49],[1.82,-3.01],
				[2.57,-2.34],[2.42,-1.76],[1.69,-2.11],[0.99,-2.28],[0.24,-2.04],[-0.67,-1.46],[-1.45,-1.29],[-1.78,-0.43],[-2.52,0.06]],hair,texture)
			if style == 0:
				_poly(cv,hc,[[-1.81,-2.9],[-0.58,-3.74],[0.63,-3.57],[1.38,-2.96],[0.41,-2.96],[-0.69,-2.45]],hair,texture)
		cv.end(FigurePainter.ol(hair),0.06)
		_stroke(cv,hc,Vector2(-2.17,-2.72),Vector2(-0.91,-3.15),0.14,hair.lightened(0.22))
		_stroke(cv,hc,Vector2(-0.37,-3.04),Vector2(1.29,-2.8),0.12,hair.lightened(0.19))
		_stroke(cv,hc,Vector2(-1.15,-2.41),Vector2(-1.93,-1.51),0.13,hair.lightened(0.17))
	if style == 4:
		_braid(cv,hc,Vector2(-2.73,0.7),Vector2(-2.4,4.31),0.5,hair,FigurePainter.ol(hair))
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _retained_female_eye(f,hc: Vector2,p: Vector2,w: float,iris: Color,brow: Color,dead: bool,pid: String) -> void:
	if f._lost(pid): return
	var cv: PixelCanvas = f.cv
	var shadow: Color = f.skin.darkened(0.34)
	# An arched brow and lifted outer lid express an adult face without enlarging the iris.
	_stroke(cv,hc,p+Vector2(-w,-0.46),p+Vector2(-w*0.02,-0.65),0.16,brow)
	_stroke(cv,hc,p+Vector2(-w*0.02,-0.65),p+Vector2(w*0.87,-0.53),0.13,brow)
	if dead:
		_stroke(cv,hc,p+Vector2(-w*0.87,0.01),p+Vector2(w*0.85,-0.1),0.13,shadow)
		return
	_poly(cv,hc,[[p.x-w,p.y+0.01],[p.x-w*0.23,p.y-0.14],[p.x+w*0.88,p.y-0.12],
		[p.x+w*0.71,p.y+0.19],[p.x-w*0.24,p.y+0.31]],f.skin.lightened(0.47).lerp(Color("#e6d6bb"),0.25))
	cv.ellipse(hc+p+Vector2(w*0.29,0.09),0.23 if w>0.5 else 0.13,0.22,iris)
	cv.ellipse(hc+p+Vector2(w*0.35,0.07),0.09,0.18,Color("#261f1b"))
	_stroke(cv,hc,p+Vector2(-w,-0.02),p+Vector2(w*0.87,-0.15),0.13,shadow)
	_stroke(cv,hc,p+Vector2(-w*0.67,0.35),p+Vector2(w*0.7,0.27),0.08,f.skin.darkened(0.16))

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
	var style: int = seed%5
	var dead: bool = f.pose == "dead" or bool(f.spec.get("dead",false))
	var jaw_lost: bool = f._lost("jaw")
	var shadow: Color = skin.darkened(0.14).lerp(Color("#794333"),0.035)
	var deep: Color = skin.darkened(0.39).lerp(Color("#51322a"),0.09)
	var light: Color = skin.lightened(0.13)
	var nose: float = 0.035*float((seed/13)%4)
	var texture: Callable = _hair_surface(f,hc,false)
	# The original five seeded grooming families keep their lengths and bald/receding cases.
	if style in [1,3,4]:
		cv.begin()
		_beauty_contour(cv,hc,[[-2.42,-2.63],[-3.13,-1.63],[-3.48,0.23],[-3.23,1.6],[-3.55,2.87],[-3.26,4.06],
			[-2.66,4.43],[-2.35,3.57],[-1.83,3.86],[-1.57,2.38],[-1.76,-1.97]],hair.darkened(0.07),texture)
		if style == 1:
			_beauty_contour(cv,hc,[[-3.05,0.69],[-3.85,1.78],[-3.77,3.14],[-3.96,3.91],[-3.14,3.52],[-2.6,2.03]],hair,texture)
		cv.end(FigurePainter.ol(hair),0.06)
		_stroke(cv,hc,Vector2(-2.96,-0.65),Vector2(-2.87,1.5),0.14,hair.lightened(0.18))
		_stroke(cv,hc,Vector2(-3.13,2.18),Vector2(-2.86,3.65),0.12,hair.lightened(0.2))
	if not f._lost("neck"):
		var sc: Vector2 = f.j["sc"]
		cv.begin()
		cv.poly(PackedVector2Array([hc+Vector2(-1.22,1.84),hc+Vector2(1.39,2.22),sc+Vector2(1.44,0.67),sc+Vector2(-1.43,0.63)]),shadow)
		cv.end(FigurePainter.ol(skin),0.04)
	# Full dwarf cheeks and a broad adult forehead, with a rounded, compact feminine chin.
	cv.begin()
	if jaw_lost:
		_beauty_contour(cv,hc,[[-2.56,-1.8],[-2.12,-2.7],[-0.9,-3.1],[0.57,-3.06],[1.86,-2.57],
			[2.4,-1.67],[2.43,-0.65],[2.52,0.13],[2.38,0.99],[1.4,1.06],[0.26,0.98],
			[-1.31,0.93],[-2.18,0.89],[-2.52,-0.27]],skin)
		_beauty_contour(cv,hc,[[-2.43,-1.7],[-1.8,-2.53],[-1.61,-1.07],[-1.26,0.38],[-0.83,0.89],
			[-2.08,0.82],[-2.48,-0.23]],shadow)
	else:
		_beauty_contour(cv,hc,[[-2.56,-1.8],[-2.12,-2.7],[-0.9,-3.1],[0.57,-3.06],[1.86,-2.57],
			[2.4,-1.67],[2.43,-0.65],[2.52,0.13],[2.38,0.99],[1.96,1.83],[1.27,2.27],
			[0.53,2.42],[-0.22,2.32],[-1.31,1.9],[-2.14,0.98],[-2.52,-0.27]],skin)
		_beauty_contour(cv,hc,[[-2.43,-1.7],[-1.8,-2.53],[-1.61,-1.07],[-1.26,0.38],[-0.91,1.46],
			[-0.11,2.21],[-1.28,1.88],[-2.08,0.9],[-2.48,-0.23]],shadow)
	_beauty_contour(cv,hc,[[-1.31,-2.71],[0.15,-2.92],[1.46,-2.52],[1.92,-1.85],[0.59,-1.65],[-1.1,-1.79]],light)
	_beauty_contour(cv,hc,[[-0.75,-0.12],[0.14,-0.29],[0.97,-0.03],[1.36,0.43],[0.51,0.86],[-0.55,0.64]],skin.lightened(0.1))
	if not jaw_lost:
		_beauty_contour(cv,hc,[[0.21,1.52],[1.08,1.55],[1.53,1.85],[0.86,2.24],[0.01,2.06]],skin.lightened(0.08))
	# A rounded sturdy dwarf nose now sits inside the cheek contour instead of projecting in profile.
	if not f._lost("nose"):
		_beauty_contour(cv,hc,[[1.06,-1.2],[1.44,-1.15],[1.54,-0.39],[1.95+nose,0.13],
			[1.96+nose,0.48],[1.58,0.67],[1.03,0.58],[0.91,0.31]],skin.darkened(0.045))
		cv.ellipse(hc+Vector2(1.52+nose,0.29),0.4,0.23,skin.lightened(0.2))
		_stroke(cv,hc,Vector2(1.24,-0.91),Vector2(1.3,-0.2),0.12,light)
	cv.end(FigurePainter.ol(skin),0.045)
	if String(f._it("helm").get("sprite","")) != "coif" and not f._lost("ear_r"):
		cv.begin()
		cv.ellipse(hc+Vector2(-2.18,-0.05),0.58,0.77,skin)
		cv.end(FigurePainter.ol(skin),0.04)
		_stroke(cv,hc,Vector2(-2.31,-0.35),Vector2(-2.02,0.28),0.12,shadow)
		cv.ellipse(hc+Vector2(-1.99,0.01),0.18,0.23,deep)
	var brow: Color = hair.darkened(0.16).lerp(deep,0.24)
	var iris: Color = [Color("#665140"),Color("#71825b"),Color("#6a8790"),Color("#635442")][(seed/7)%4]
	_female_eye(f,hc,Vector2(-0.04,-0.76),0.92,iris,brow,dead,"eye_r")
	_female_eye(f,hc,Vector2(1.69,-0.87),0.4,iris,brow,dead,"eye_l")
	if not f._lost("nose"):
		_stroke(cv,hc,Vector2(1.52,0.57),Vector2(1.81+nose,0.5),0.09,deep)
	if not jaw_lost and not f._lost("mouth"):
		var lip: Color = skin.darkened(0.15).lerp(Color("#be6673"),0.33)
		_poly(cv,hc,[[0.03,1.24],[0.44,1.08],[0.74,1.16],[1.0,1.05],[1.62,1.2],
			[1.31,1.45],[0.82,1.54],[0.34,1.43]],lip)
		_stroke(cv,hc,Vector2(0.15,1.29),Vector2(1.5,1.23),0.075,deep.lerp(lip,0.37))
		_stroke(cv,hc,Vector2(0.56,1.46),Vector2(1.09,1.45),0.075,lip.lightened(0.28))
	if not jaw_lost:
		_stroke(cv,hc,Vector2(0.28,2.07),Vector2(1.09,2.08),0.10,light)
	if int(f.spec.get("age",28))>=50:
		_stroke(cv,hc,Vector2(-0.99,-0.08),Vector2(-0.71,0.11),0.065,shadow)
		if not jaw_lost: _stroke(cv,hc,Vector2(1.8,0.86),Vector2(1.74,1.1),0.065,shadow)
	if style != 2:
		cv.begin()
		if style == 3:
			_beauty_contour(cv,hc,[[-2.71,-0.72],[-2.85,-2.23],[-2.05,-2.97],[-1.16,-3.25],[-1.32,-2.76],
				[-1.71,-2.08],[-1.9,-0.48],[-2.41,0.08]],hair,texture)
			_beauty_contour(cv,hc,[[1.31,-2.91],[2.09,-2.59],[2.45,-1.97],[1.91,-2.11]],hair,texture)
		else:
			_beauty_contour(cv,hc,[[-2.84,-0.58],[-2.96,-2.08],[-2.27,-3.16],[-1.08,-3.67],[0.34,-3.56],[1.77,-3.02],
				[2.45,-2.4],[2.38,-1.84],[1.67,-2.12],[0.75,-2.42],[-0.02,-2.06],[-0.94,-1.34],
				[-1.58,-1.24],[-1.86,-0.37],[-2.44,0.04]],hair,texture)
			if style == 0:
				_beauty_contour(cv,hc,[[-2.02,-2.71],[-0.82,-3.81],[0.49,-3.66],[1.4,-3.05],
					[0.55,-2.96],[-0.61,-2.43]],hair,texture)
		cv.end(FigurePainter.ol(hair),0.055)
		_stroke(cv,hc,Vector2(-2.07,-2.74),Vector2(-0.96,-3.2),0.13,hair.lightened(0.23))
		_stroke(cv,hc,Vector2(-0.35,-3.14),Vector2(1.22,-2.79),0.12,hair.lightened(0.19))
		_stroke(cv,hc,Vector2(-1.17,-2.45),Vector2(-1.97,-1.51),0.12,hair.lightened(0.18))
	if style == 4:
		_braid(cv,hc,Vector2(-2.73,0.7),Vector2(-2.4,4.31),0.5,hair,FigurePainter.ol(hair))
	f._helm(hc,-float(f.head_w)*0.5,float(f.head_w)*0.5,-float(f.head_h)*0.5,float(f.head_h)*0.5)

static func _female_eye(f,hc: Vector2,p: Vector2,w: float,iris: Color,brow: Color,dead: bool,pid: String) -> void:
	if f._lost(pid): return
	var cv: PixelCanvas = f.cv
	var shadow: Color = f.skin.darkened(0.34)
	_stroke(cv,hc,p+Vector2(-w,-0.49),p+Vector2(-w*0.13,-0.74),0.12,brow)
	_stroke(cv,hc,p+Vector2(-w*0.13,-0.74),p+Vector2(w*0.87,-0.58),0.10,brow)
	if dead:
		_stroke(cv,hc,p+Vector2(-w*0.88,0.03),p+Vector2(w*0.86,-0.05),0.12,shadow)
		return
	_beauty_contour(cv,hc,[[p.x-w,p.y+0.04],[p.x-w*0.27,p.y-0.36],[p.x+w*0.6,p.y-0.3],
		[p.x+w*0.98,p.y+0.05],[p.x+w*0.47,p.y+0.38],[p.x-w*0.38,p.y+0.38]],f.skin.lightened(0.66).lerp(Color("#f4e6d5"),0.36))
	var iris_rx: float = 0.3 if w>0.5 else 0.16
	cv.ellipse(hc+p+Vector2(w*0.26,0.05),iris_rx,0.31,iris)
	cv.ellipse(hc+p+Vector2(w*0.29,0.05),0.12 if w>0.5 else 0.085,0.25,Color("#262520"))
	cv.ellipse(hc+p+Vector2(w*0.16,-0.11),0.085 if w>0.5 else 0.055,0.075,Color("#fff2df"))
	_stroke(cv,hc,p+Vector2(-w,0.01),p+Vector2(-w*0.23,-0.3),0.11,brow)
	_stroke(cv,hc,p+Vector2(-w*0.23,-0.3),p+Vector2(w*0.6,-0.28),0.1,brow)
	_stroke(cv,hc,p+Vector2(-w,0.01),p+Vector2(-w*1.17,-0.15),0.09,brow)
	_stroke(cv,hc,p+Vector2(-w*0.62,0.38),p+Vector2(w*0.72,0.29),0.065,f.skin.darkened(0.12))

static func _eye(f,hc: Vector2,p: Vector2,w: float,iris: Color,brow: Color,dead: bool,pid: String,female: bool) -> void:
	if f._lost(pid): return
	var cv: PixelCanvas = f.cv
	var shadow: Color = f.skin.darkened(0.36)
	_stroke(cv,hc,p+Vector2(-w,-0.42),p+Vector2(w*0.83,-0.51),0.19 if female else 0.27,brow)
	_stroke(cv,hc,p+Vector2(-w,0.34),p+Vector2(w*0.76,0.3),0.11,shadow)
	if dead:
		_stroke(cv,hc,p+Vector2(-w*0.87,0.04),p+Vector2(w*0.82,0.13),0.16,shadow)
		return
	cv.ellipse(hc+p+Vector2(0,0.05),w,0.27,f.skin.lightened(0.49).lerp(Color("#e6d6bb"),0.27))
	cv.ellipse(hc+p+Vector2(w*0.31,0.08),0.24 if w>0.5 else 0.14,0.23,iris)
	cv.ellipse(hc+p+Vector2(w*0.4,0.08),0.10,0.19,Color("#261f1b"))
	_stroke(cv,hc,p+Vector2(-w,-0.11),p+Vector2(w*0.8,-0.18),0.14,shadow)

static func _beard(f,hc: Vector2,seed: int) -> void:
	var selected: int = FigurePainter.beard_style(f.spec)
	if selected > 0:
		_beard_variant(f,hc,selected)
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var ink: Color = FigurePainter.ol(hair)
	var length: float = 5.85+0.3*float((seed/11)%4)
	var variant: int = (seed/3)%3
	var pat: Callable = _hair_surface(f,hc,true)
	# The upper beard grows along the jaw. Separate lobes avoid a rectangular bib.
	cv.begin()
	_poly(cv,hc,[[-2.11,0.45],[-1.29,0.82],[-0.69,1.57],[0.65,2.06],[2.27,1.98],[2.88,1.16],
		[2.96,2.11],[2.48,3.8],[2.03,5.04],[1.23,length],[0.35,length+0.13],[-0.55,length-0.69],
		[-1.37,4.72],[-2.17,3.08],[-2.48,1.54]],hair,pat)
	_poly(cv,hc,[[-2.17,1.11],[-1.46,2.34],[-1.01,4.22],[-0.36,length-0.53],[-1.25,4.82],[-2.16,3.06]],hair.darkened(0.21),pat)
	_poly(cv,hc,[[0.12,2.58],[0.88,2.36],[1.89,2.53],[1.76,4.28],[1.03,length-0.2],[0.46,5.48]],hair.lightened(0.08),pat)
	cv.end(ink,0.05)
	# Layered cheek locks feed into one or two braids; all highlights derive from hair.
	_stroke(cv,hc,Vector2(-1.81,1.48),Vector2(-1.01,3.78),0.17,hair.lightened(0.24))
	_stroke(cv,hc,Vector2(-1.27,2.04),Vector2(-0.34,4.27),0.15,hair.lightened(0.18))
	_stroke(cv,hc,Vector2(2.44,2.15),Vector2(1.81,4.12),0.16,hair.lightened(0.22))
	if variant == 0:
		_braid(cv,hc,Vector2(0.87,2.92),Vector2(0.89,length-0.09),0.72,hair,ink)
	elif variant == 1:
		_braid(cv,hc,Vector2(-0.27,2.87),Vector2(0.13,length-0.25),0.49,hair.darkened(0.05),ink)
		_braid(cv,hc,Vector2(1.82,2.76),Vector2(1.52,length-0.62),0.48,hair,ink)
	else:
		for i in 5:
			var x: float = -0.77+0.59*float(i)
			_stroke(cv,hc,Vector2(x,3.15),Vector2(0.89+(x-0.89)*0.54,length-0.46-absf(x-0.89)*0.26),0.15,hair.lightened(0.19))
	# Two arcing moustache halves frame the mouth, with curled ends made only of hair.
	cv.begin()
	_poly(cv,hc,[[1.77,0.82],[2.29,0.85],[2.69,1.04],[2.85,1.39],[2.67,1.77],[2.35,1.91],[2.4,1.51],[1.81,1.3],[1.01,1.42],[0.15,1.81],[0.41,1.21],[1.14,0.95]],hair,pat)
	cv.end(ink,0.04)
	_stroke(cv,hc,Vector2(0.52,1.27),Vector2(1.55,1.06),0.13,hair.lightened(0.22))
	_stroke(cv,hc,Vector2(2.11,1.04),Vector2(2.54,1.3),0.12,hair.lightened(0.2))

static func _beard_variant(f,hc: Vector2,style: int) -> void:
	if f._lost("head") or f._lost("neck") or f._lost("jaw") or not bool(f.spec.get("beard",false)):
		return
	if String(f.spec.get("sex","")).to_lower() in ["female","f","woman"]:
		return
	var cv: PixelCanvas = f.cv
	var hair: Color = f.hair
	var ink: Color = FigurePainter.ol(hair)
	var pat: Callable = _hair_surface(f,hc,true)
	if style == 7:
		# Close stubble is real supplied hair on the jaw, without inventing a scar or item.
		var inv: Transform2D = cv.xf.affine_inverse()
		var base: Color = f.skin.lerp(hair,0.25)
		var stipple: Callable = func(x: int,y: int,c: Color) -> Color:
			var local: Vector2 = inv*Vector2(float(x)+0.5,float(y)+0.5)-hc
			return c.lerp(hair,0.48) if fposmod(local.x+local.y*0.67,0.9)<0.23 else c
		_poly(cv,hc,[[-2.17,0.55],[-1.4,0.91],[-0.6,1.62],[0.64,1.91],[2.25,1.65],[2.63,1.12],
			[2.59,2.0],[1.61,2.77],[0.74,3.0],[-0.88,2.57],[-2.04,1.76]],base,stipple)
		_beard_moustache(f,hc,hair,pat,0.17)
		return
	if style == 6:
		_beard_moustache(f,hc,hair,pat,0.42)
		return
	cv.begin()
	match style:
		1: # Close trimmed: a neat, rounded jaw-length band.
			_poly(cv,hc,[[-2.15,0.51],[-1.4,0.95],[-0.55,1.72],[0.64,2.0],[2.22,1.72],[2.73,1.04],
				[2.79,2.1],[2.14,2.95],[1.07,3.73],[0.2,3.81],[-0.93,3.15],[-2.08,1.99]],hair,pat)
		2: # Round full: broad connected curls instead of a rectangular bib.
			_poly(cv,hc,[[-2.13,0.48],[-1.35,1.01],[-0.59,1.76],[0.68,2.06],[2.25,1.82],[2.88,1.12],
				[3.05,2.51],[2.77,3.91],[2.06,4.68],[0.72,5.11],[-0.75,4.88],[-1.8,4.01],[-2.42,2.6]],hair,pat)
		3: # Pointed: narrower tapered length, no decorative clasp.
			_poly(cv,hc,[[-2.07,0.54],[-1.3,1.0],[-0.51,1.8],[0.63,2.1],[2.18,1.81],[2.84,1.17],
				[2.85,2.44],[2.17,4.5],[1.0,6.95],[0.38,6.72],[-0.51,5.06],[-1.63,3.7],[-2.35,2.15]],hair,pat)
		4: # Forked: two flowing separated tails remain inside the old long-beard envelope.
			_poly(cv,hc,[[-2.06,0.5],[-1.23,0.94],[-0.46,1.76],[0.68,2.07],[2.22,1.81],[2.85,1.08],
				[2.83,2.49],[2.39,4.45],[1.87,6.84],[1.29,6.54],[0.69,4.71],
				[0.11,6.76],[-0.63,6.49],[-1.58,4.26],[-2.26,2.18]],hair,pat)
		5: # Braided: cheek growth feeds into one woven central braid.
			_poly(cv,hc,[[-2.11,0.51],[-1.27,0.94],[-0.51,1.78],[0.64,2.08],[2.22,1.82],[2.84,1.11],
				[2.89,2.39],[2.23,3.35],[1.14,4.13],[0.16,4.01],[-0.97,3.31],[-2.21,1.87]],hair,pat)
	_poly(cv,hc,[[-2.05,1.19],[-1.41,2.23],[-0.71,3.13],[-1.44,3.48],[-2.22,2.36]],hair.darkened(0.21),pat)
	cv.end(ink,0.045)
	var end_y: float = [0.0,3.43,4.79,6.2,5.96,3.57][style]
	for i in 5:
		var x: float = -0.96+0.64*float(i)
		_stroke(cv,hc,Vector2(x,2.28),Vector2(0.7+(x-0.7)*0.7,end_y-absf(x-0.6)*0.23),0.13,hair.lightened(0.21))
	if style == 4:
		_stroke(cv,hc,Vector2(0.71,3.17),Vector2(0.68,4.69),0.18,hair.darkened(0.36))
	elif style == 5:
		_braid(cv,hc,Vector2(0.72,3.25),Vector2(0.85,6.51),0.68,hair,ink)
	_beard_moustache(f,hc,hair,pat,0.3)

static func _beard_moustache(f,hc: Vector2,hair: Color,pat: Callable,r: float) -> void:
	if f._lost("mouth"): return
	var cv: PixelCanvas = f.cv
	cv.begin()
	_poly(cv,hc,[[1.52,0.89],[2.12,0.87],[2.55,1.03],[2.83,1.31],[2.57,1.75],[2.2,1.83],
		[2.31,1.41],[1.66,1.28],[1.05,1.4],[0.33,1.78],[-0.03,1.49],[0.39,1.17],[1.02,0.96]],hair,pat)
	if r>0.35:
		_stroke(cv,hc,Vector2(0.36,1.41),Vector2(-0.44,1.9),r,hair)
		_stroke(cv,hc,Vector2(2.51,1.43),Vector2(2.99,1.8),r*0.83,hair)
	cv.end(FigurePainter.ol(hair),0.03)
	_stroke(cv,hc,Vector2(0.54,1.26),Vector2(1.38,1.05),0.1,hair.lightened(0.2))
	_stroke(cv,hc,Vector2(1.93,1.07),Vector2(2.44,1.23),0.09,hair.lightened(0.18))

static func _braid(cv: PixelCanvas,hc: Vector2,a: Vector2,b: Vector2,r: float,hair: Color,ink: Color) -> void:
	cv.begin()
	_stroke(cv,hc,a,b,r,hair.darkened(0.08))
	cv.end(ink,0.04)
	var n: int = 5
	for i in n:
		var p: Vector2 = a.lerp(b,float(i)/float(n))
		var d: float = -1.0 if i%2==0 else 1.0
		_stroke(cv,hc,p+Vector2(-r*0.75*d,-0.15),p+Vector2(r*0.67*d,0.43),r*0.31,hair.lightened(0.23))
		_stroke(cv,hc,p+Vector2(r*0.74*d,-0.04),p+Vector2(-r*0.68*d,0.46),r*0.18,hair.darkened(0.24))
	# A small hair tuft closes the braid; no invented metal or gemstone fittings.
	_poly(cv,hc,[[b.x-r*0.32,b.y-0.05],[b.x+r*0.32,b.y-0.05],[b.x+r*0.48,b.y+0.6],[b.x,b.y+0.82],[b.x-r*0.38,b.y+0.59]],hair)

static func _body(f,hem: float,spread: float = 0.0) -> PackedVector2Array:
	if String(f.spec.get("sex","")).to_lower() == "female":
		return _female_body(f,hem,spread)
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var w: float = float(f.tw)*0.5
	var hw: float = float(f.hipw)*0.5
	var mid: Vector2 = sc.lerp(hip,0.5)
	return PackedVector2Array([sc+Vector2(-w+0.43,0.18),sc+Vector2(-1.55,-0.24),sc+Vector2(1.55,-0.24),
		sc+Vector2(w-0.35,0.16),mid+Vector2(w+0.16,0),hip+Vector2(hw+0.15,0.25),
		hip+Vector2(hw+0.7+spread,hem-0.3),hip+Vector2(hw+0.45+spread,hem),
		hip+Vector2(0.4,hem+0.12),hip+Vector2(-0.3,hem-0.18),hip+Vector2(-hw-0.5-spread,hem),
		hip+Vector2(-hw-0.7-spread,hem-0.35),hip+Vector2(-hw-0.17,0.15),mid+Vector2(-w-0.2,0)])

static func _female_body(f,hem: float,spread: float) -> PackedVector2Array:
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var w: float = float(f.tw)*0.5
	var hw: float = float(f.hipw)*0.5
	var chest: Vector2 = sc.lerp(hip,0.29)
	var waist: Vector2 = sc.lerp(hip,0.69)
	# Strong shoulders, full chest, fitted waist and broad hips retain the short dwarf build.
	return PackedVector2Array([sc+Vector2(-w+0.72,0.16),sc+Vector2(-1.43,-0.19),sc+Vector2(1.43,-0.19),
		sc+Vector2(w-0.68,0.16),chest+Vector2(w-0.18,-0.05),chest+Vector2(w-0.25,0.49),
		waist+Vector2(w*0.76,0),hip+Vector2(hw+0.2,0.12),hip+Vector2(hw+0.56+spread,hem-0.28),
		hip+Vector2(hw+0.36+spread,hem),hip+Vector2(0.43,hem+0.1),hip+Vector2(-0.26,hem-0.14),
		hip+Vector2(-hw-0.4-spread,hem),hip+Vector2(-hw-0.59-spread,hem-0.32),
		hip+Vector2(-hw-0.22,0.1),waist+Vector2(-w*0.77,0),chest+Vector2(-w+0.16,0.36),chest+Vector2(-w+0.23,-0.14)])

static func _surface(f,origin: Vector2,kind: String,m: Dictionary = {}) -> Callable:
	var inv: Transform2D = f.cv.xf.affine_inverse()
	var width: float = float(f.tw)
	var length: float = float(f.torso_len)
	var lace: Color = f.sec
	return func(x: int,y: int,c: Color) -> Color:
		var p: Vector2 = inv*Vector2(float(x)+0.5,float(y)+0.5)-origin
		var out: Color = c.lightened(0.10).lerp(c.darkened(0.22),clampf((p.x+width*0.3)/width,0,1))
		if kind == "cloth":
			if p.y>length*0.32 and absf(p.x-1.4+p.y*0.11)<0.18: return out.darkened(0.15)
			if p.y>length*0.55 and absf(p.x+2.1-p.y*0.09)<0.2: return out.lightened(0.13)
		elif kind in ["mail","byrnie"]:
			var row: int = floori(p.y/0.67)
			var dx: float = fposmod(p.x+float(posmod(row,2))*0.4,0.8)-0.4
			var dy: float = fposmod(p.y,0.67)-0.33
			var ring: float = dx*dx/0.11+dy*dy/0.057
			if ring<0.34: return out.darkened(0.27)
			if ring<1.0 and dy<0: return out.lerp(m["light"],0.39)
		elif kind == "scale":
			var row: int = floori(p.y/0.82)
			var dx: float = fposmod(p.x+float(posmod(row,2))*0.49,0.98)-0.49
			var dy: float = fposmod(p.y,0.82)
			if dy>0.54+0.23*(1.0-absf(dx)/0.49): return out.darkened(0.26)
			if dy<0.13: return out.lerp(m["light"],0.28)
		elif kind == "lamellar":
			if fposmod(p.x,0.97)<0.1: return out.darkened(0.3)
			if fposmod(p.y,1.36)>1.14: return lace.darkened(0.23)
			if fposmod(p.y,1.36)<0.15: return out.lerp(m["light"],0.35)
		return out

static func torso(f) -> bool:
	var armor: Dictionary = f._it("body")
	var kind: String = String(armor.get("sprite",""))
	var cv: PixelCanvas = f.cv
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var w: float = float(f.tw)*0.5
	var spread: float = float(f._spread())*0.55
	if f._it("clothing").is_empty() and f._it("body").is_empty():
		cv.begin()
		cv.poly(_body(f,0.6),f.skin,_surface(f,sc,"skin"))
		if String(f.spec.get("sex","")).to_lower() == "female":
			_stroke(cv,sc,Vector2(-1.72,0.8),Vector2(-0.15,1.04),0.15,f.skin.lightened(0.12))
			_stroke(cv,sc,Vector2(0.19,1.04),Vector2(1.81,0.79),0.12,f.skin.darkened(0.12))
		else:
			_stroke(cv,sc,Vector2(-2.6,1.0),Vector2(-0.15,1.6),0.22,f.skin.lightened(0.12))
			_stroke(cv,sc,Vector2(0.0,1.6),Vector2(2.65,1.0),0.16,f.skin.darkened(0.17))
		f._skin_end()
	else:
		HumanArt.worn_chest(f,true)
	HumanArt.worn_torso(f,true)
	return true

static func _belt(f,t: float,c: Color,buckle: Color) -> void:
	var cv: PixelCanvas = f.cv
	var hip: Vector2 = f.j["hip"]
	var sc: Vector2 = f.j["sc"]
	var p: Vector2 = hip.lerp(sc,t)
	var w: float = lerpf(float(f.hipw),float(f.tw),t)*0.5+0.2
	cv.capsule(p+Vector2(-w,0),p+Vector2(w,0),0.36,c)
	cv.ellipse(p+Vector2(w-1.6,0),0.35,0.28,buckle)

static func _segment(cv: PixelCanvas,a: Vector2,b: Vector2,r0: float,r1: float,c: Color,pat: Callable = Callable()) -> void:
	var axis: Vector2 = (b-a).normalized()
	var n: Vector2 = Vector2(-axis.y,axis.x)
	cv.poly(PackedVector2Array([a-n*r0,b-n*r1,b+n*r1,a+n*r0]),c,pat)
	cv.ellipse(a,r0,r0,c,pat)
	cv.ellipse(b,r1,r1,c,pat)

static func arm(f,side: String) -> bool:
	var body: Dictionary = f._it("body")
	var kind: String = String(body.get("sprite",""))
	var cv: PixelCanvas = f.cv
	var sh: Vector2 = f.j["s"+side]
	var el: Vector2 = f.j["e"+side]
	var hd: Vector2 = f.j["h"+side]
	var r: float = float(f.arm_r)
	if String(f.spec.get("sex","")).to_lower() == "female": r *= 0.94
	if f._lost("arm_upper_"+side):
		cv.dot(sh,FigurePainter.BLOOD)
		return true
	var lower_lost: bool = f._lost("arm_lower_"+side)
	var hand_lost: bool = f._lost("hand_"+side)
	var skin: Color = f.skin.darkened(0.11) if side=="l" else f.skin
	cv.begin()
	_segment(cv,sh,sh.lerp(el,0.54),r*1.19,r*1.13,skin)
	_segment(cv,sh.lerp(el,0.54),el,r*1.13,r*0.79,skin)
	if not lower_lost:
		_segment(cv,el,el.lerp(hd,0.43),r*0.79,r*1.03,skin)
		_segment(cv,el.lerp(hd,0.43),hd,r*1.03,r*0.66,skin)
		if not hand_lost: cv.ellipse(hd,r*0.94,r*0.95,skin)
	cv.end(FigurePainter.ol(skin),0.07)
	HumanArt.worn_arm(f,side,true)
	if lower_lost:
		cv.dot(el,FigurePainter.BLOOD)
	elif hand_lost:
		cv.dot(hd,FigurePainter.BLOOD)
	return true

static func leg(f,side: String) -> bool:
	var cv: PixelCanvas = f.cv
	var hp: Vector2 = f.j["p"+side]
	var kn: Vector2 = f.j["k"+side]
	var ft: Vector2 = f.j["f"+side]
	var r: float = float(f.leg_r)
	if f._lost("leg_upper_"+side):
		cv.dot(hp,FigurePainter.BLOOD)
		return true
	var trousers: bool = not f._it("legs_under").is_empty()
	var c: Color = f._trouser_col() if trousers else f.skin
	if side=="l": c = c.darkened(0.1)
	var lower_lost: bool = f._lost("leg_lower_"+side)
	var foot_lost: bool = f._lost("foot_"+side)
	if trousers:
		HumanArt.worn_pants(f,side,true)
	else:
		cv.begin()
		_segment(cv,hp,kn,r*1.43,r*1.03,c)
		if not lower_lost:
			_segment(cv,kn,kn.lerp(ft,0.42),r*1.03,r*1.19,c)
			_segment(cv,kn.lerp(ft,0.42),ft,r*1.19,r*0.7,c)
		cv.end(FigurePainter.ol(c),0.08)
	if lower_lost:
		cv.dot(kn,FigurePainter.BLOOD)
		return true
	HumanArt.worn_greaves(f,side,true)
	if foot_lost:
		cv.dot(ft,FigurePainter.BLOOD)
		return true
	var shoes: Dictionary = f._it("feet")
	if not shoes.is_empty():
		HumanArt.worn_shoe(f,side,true)
	else:
		var shoe: Color = f.skin
		cv.begin()
		_poly(cv,ft,[[-1.04,-0.64],[0.83,-0.6],[1.17,-0.03],[2.38,0.42],[2.57,1.04],[2.15,1.39],[-1.13,1.32],[-1.27,0.55]],shoe)
		cv.end(FigurePainter.ol(shoe),0.05)
	return true

static func worn_waist(f,kind: String) -> float:
	var female: bool = String(f.spec.get("sex","")).to_lower() == "female"
	var half: float = float(f.tw)*0.5*(0.52 if female else 0.55)
	if kind == "gambeson": half += 0.07
	if kind in ["scale","lamellar","scrap"]: half += 0.04
	return half

static func worn_body(f,hem: float,kind: String) -> PackedVector2Array:
	# A fitted layer follows the accepted chest/waist/hip stations; no body or joint is resized.
	var sc: Vector2 = f.j["sc"]
	var hip: Vector2 = f.j["hip"]
	var w: float = float(f.tw)*0.5
	var hw: float = float(f.hipw)*0.5
	var female: bool = String(f.spec.get("sex","")).to_lower() == "female"
	var padding: float = 0.1 if kind == "gambeson" else 0.025
	var chest: Vector2 = sc.lerp(hip,0.29)
	var waist: Vector2 = sc.lerp(hip,0.69)
	var shoulder: float = w*(0.7 if female else 0.73)+padding
	var chest_w: float = w*(0.72 if female else 0.75)+padding
	var waist_w: float = worn_waist(f,kind)
	var hip_w: float = hw*0.78+padding
	var skirt: float = hw*0.76+padding
	var rise: float = minf(0.72,hem*0.6+0.12)
	return _round_garment(PackedVector2Array([sc+Vector2(-shoulder+0.34,0.16),sc+Vector2(-1.12,0.05),
		sc+Vector2(0.09,0.81),sc+Vector2(1.11,0.09),sc+Vector2(shoulder-0.3,0.16),
		chest+Vector2(chest_w,-0.05),chest+Vector2(chest_w-0.12,0.49),waist+Vector2(waist_w,0),
		hip+Vector2(hip_w,0.12),hip+Vector2(skirt,hem-rise*0.72),hip+Vector2(skirt*0.84,hem-0.08),
		hip+Vector2(skirt*0.54,hem+0.07),hip+Vector2(0.8,hem-0.13),hip+Vector2(0.38,hem-rise),
		hip+Vector2(-0.28,hem-rise*0.9),hip+Vector2(-0.76,hem-0.12),hip+Vector2(-skirt*0.55,hem+0.06),
		hip+Vector2(-skirt*0.84,hem-0.06),hip+Vector2(-skirt,hem-rise*0.76),hip+Vector2(-hip_w,0.1),
		waist+Vector2(-waist_w-0.04,0),chest+Vector2(-chest_w+0.08,0.36),chest+Vector2(-chest_w+0.04,-0.14)]))

static func worn_sleeve(cv: PixelCanvas,a: Vector2,b: Vector2,r0: float,r1: float,c: Color,pat: Callable = Callable()) -> void:
	# Cloth and mail skim the native arm, with a shallow rounded shoulder instead of a wide cap.
	var d: Vector2 = (b-a).normalized()
	var n: Vector2 = Vector2(-d.y,d.x)
	var mid: Vector2 = a.lerp(b,0.43)
	cv.ellipse(a,r0,r0,c,pat)
	cv.poly(PackedVector2Array([a-d*r0*0.13-n*r0*0.6,a-n*r0*0.93,mid-n*r0*0.96,
		b-n*r1,b+d*r1*0.1,b+n*r1,mid+n*r0*0.9,a+n*r0*0.9,a-d*r0*0.13+n*r0*0.57]),c,pat)
	cv.capsule(a+n*r0*0.3,b+n*r1*0.18,maxf(0.1,r1*0.14),c.lightened(0.14))
static func _round_garment(points: PackedVector2Array) -> PackedVector2Array:
	# Small corner cuts give fitted cloth/metal edges a body contour instead of a squared panel.
	var rounded: PackedVector2Array = PackedVector2Array()
	for i in points.size():
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i+1)%points.size()]
		rounded.append(a.lerp(b,0.14))
		rounded.append(a.lerp(b,0.86))
	return rounded
static func worn_surface(f,origin: Vector2,kind: String,m: Dictionary = {}) -> Callable:
	var texture: Callable = _surface(f,origin,kind,m)
	var inv: Transform2D = f.cv.xf.affine_inverse()
	var length: float = float(f.torso_len)
	var w: float = float(f.tw)*0.5
	var hw: float = float(f.hipw)*0.5
	var female: bool = String(f.spec.get("sex","")).to_lower() == "female"
	var chest: float = w*(0.72 if female else 0.75)
	var waist: float = w*(0.52 if female else 0.55)
	return func(x: int,y: int,c: Color) -> Color:
		var p: Vector2 = inv*Vector2(float(x)+0.5,float(y)+0.5)-origin
		var t: float = p.y/length
		var half: float = chest
		if t>0.29 and t<=0.69: half = lerpf(chest,waist,(t-0.29)/0.4)
		elif t>0.69: half = lerpf(waist,hw*0.76,clampf((t-0.69)/0.31,0.0,1.0))
		var across: float = clampf(p.x/maxf(0.8,half),-1.0,1.0)
		var out: Color = texture.call(x,y,c)
		# Broad curved planes read as a chest and waist beneath the real construction pattern.
		if across>0.2: out = out.darkened((across-0.2)*0.2)
		if across < -0.7: out = out.darkened((-across-0.7)*0.17)
		if across > -0.55 and across < -0.12:
			out = out.lightened(0.065 if kind == "cloth" else 0.095)
		return out
static func worn_hem(f,hem: float,kind: String,c: Color,r: float) -> void:
	var cv: PixelCanvas = f.cv
	var hip: Vector2 = f.j["hip"]
	var skirt: float = float(f.hipw)*0.38+(0.1 if kind == "gambeson" else 0.025)
	var rise: float = minf(0.72,hem*0.6+0.12)
	for side in [-1.0,1.0]:
		var pts: PackedVector2Array = PackedVector2Array([hip+Vector2(float(side)*(skirt-0.21),hem-rise*0.72),
			hip+Vector2(float(side)*skirt*0.79,hem-0.25),hip+Vector2(float(side)*skirt*0.53,hem-0.14),
			hip+Vector2(float(side)*0.73,hem-0.29),hip+Vector2(float(side)*0.51,hem-rise+0.12)])
		for i in pts.size()-1:
			cv.capsule(pts[i],pts[i+1],r,c)