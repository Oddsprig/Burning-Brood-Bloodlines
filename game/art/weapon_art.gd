class_name WeaponArt
extends RefCounted
## Battle weapons in the existing FigurePainter grip frame. Artwork alone: the rig,
## reach formula, two-hand placement and bow release threshold belong to FigurePainter.

const SPRITES: Array[String] = ["sword", "sabre", "knife", "axe", "greataxe", "cleaver",
	"mace", "club", "maul", "spear", "glaive", "sickle", "bow", "longbow", "recurve"]
const WOOD := Color("#8a5a30")
const WOOD_LIGHT := Color("#b47b45")
const WOOD_DARK := Color("#50321e")
const WRAP := Color("#65412c")
const WRAP_LIGHT := Color("#997051")
const STRING := Color("#e8e2cf")

static func draw(f, grip: Vector2, dir: Vector2) -> bool:
	var w: Dictionary = f._it("weapon")
	if w.is_empty():
		return false
	var sprite: String = String(w.get("sprite", "sword"))
	if sprite not in SPRITES:
		return false
	f._g = grip
	f._d = dir.normalized()
	f._n = Vector2(f._d.y, -f._d.x)
	var m: Dictionary = FigurePainter.metal(String(w.get("mat", "copper")), int(w.get("q", 0)))
	var cv: PixelCanvas = f.cv
	cv.begin()
	match sprite:
		"sword": _sword(f, m)
		"sabre": _sabre(f, m)
		"knife": _knife(f, m, String(w.get("tid", "")))
		"axe": _axe(f, m, false, String(w.get("tid", "")))
		"greataxe": _axe(f, m, true, String(w.get("tid", "")))
		"cleaver": _cleaver(f, m)
		"mace": _mace(f, m, String(w.get("tid", "")))
		"club": _club(f, m)
		"maul": _maul(f, m, String(w.get("tid", "")))
		"spear": _spear(f, m, float(w.get("reach", 100.0)), String(w.get("tid", "")))
		"glaive": _glaive(f, m)
		"sickle": _sickle(f, m)
		"bow", "longbow", "recurve": _bow(f, sprite)
	cv.end(m["outline"], float(m["shade"]), m["shine"])
	return true

static func _poly(f, pts: Array, c: Color) -> void:
	f._wpoly(pts, c)

static func _line(f, u0: float, v0: float, u1: float, v1: float, r: float, c: Color) -> void:
	var cv: PixelCanvas = f.cv
	cv.capsule(f._wp(u0, v0), f._wp(u1, v1), r * float(f.gs), c)

static func _haft(f, lo: float, hi: float, radius: float = 0.5) -> void:
	_line(f, lo, 0.0, hi, 0.0, radius, WOOD)
	_line(f, lo + 0.2, -radius * 0.42, hi - 0.2, -radius * 0.42, 0.13, WOOD_LIGHT)
	_line(f, lo + 0.3, radius * 0.45, hi - 0.5, radius * 0.45, 0.11, WOOD_DARK)

static func _wrap(f, lo: float, hi: float, radius: float = 0.52) -> void:
	_line(f, lo, 0.0, hi, 0.0, radius, WRAP)
	var u: float = lo + 0.25
	while u < hi:
		_line(f, u - 0.16, -radius * 0.7, u + 0.16, radius * 0.7, 0.11, WRAP_LIGHT)
		u += 0.55

static func _collar(f, u: float, width: float, radius: float, c: Color) -> void:
	_poly(f, [[u - width * 0.5, -radius], [u + width * 0.5, -radius],
		[u + width * 0.5, radius], [u - width * 0.5, radius]], c)

static func _sword(f, m: Dictionary) -> void:
	var base: Color = m["base"]
	var light: Color = m["light"]
	var dark: Color = m["dark"]
	var trim: Color = m["trim"]
	_wrap(f, -1.5, 0.5)
	_poly(f, [[-2.8, -0.4], [-2.4, -0.8], [-1.8, -0.8], [-1.5, -0.3],
		[-1.5, 0.3], [-1.8, 0.8], [-2.4, 0.8], [-2.8, 0.4]], trim)
	_poly(f, [[0.55, -1.9], [0.95, -2.2], [1.45, -1.85], [1.28, -0.7],
		[1.28, 0.7], [1.45, 1.85], [0.95, 2.2], [0.55, 1.9]], dark)
	_line(f, 0.95, -1.8, 0.95, 1.8, 0.22, trim)
	_poly(f, [[1.5, -0.9], [5.2, -0.85], [9.7, -0.58], [11.6, 0.0],
		[9.7, 0.58], [5.2, 0.85], [1.5, 0.9]], base)
	_poly(f, [[1.6, -0.9], [5.2, -0.85], [9.7, -0.58], [11.6, 0.0],
		[9.5, -0.2], [5.1, -0.42], [1.6, -0.5]], light)
	_poly(f, [[1.6, 0.9], [5.2, 0.85], [9.7, 0.58], [11.6, 0.0],
		[9.3, 0.18], [5.1, 0.42], [1.6, 0.5]], dark)
	_line(f, 2.3, 0.0, 8.8, 0.0, 0.16, dark)
	_line(f, 2.4, -0.22, 8.7, -0.22, 0.1, m["shine"])

static func _sabre(f, m: Dictionary) -> void:
	_wrap(f, -1.5, 0.5)
	_poly(f, [[-2.5, -0.5], [-1.6, -0.5], [-1.5, 0.4], [-2.0, 0.7], [-2.6, 0.2]], m["trim"])
	_line(f, 1.0, -1.6, 1.0, 1.6, 0.3, m["trim"])
	_line(f, 1.0, 1.6, -1.6, 1.4, 0.2, m["dark"])
	_line(f, -1.6, 1.4, -2.0, 0.5, 0.2, m["trim"])
	var edge: Array = []
	var back: Array = []
	var bevel: Array = []
	var bevel_back: Array = []
	for i in 9:
		var u: float = 1.5 + float(i) * 1.1875
		var bend: float = 0.035 * pow(u - 1.5, 2.0)
		edge.append([u, -0.9 + bend])
		back.push_front([u, 0.9 + bend * 1.05])
		bevel.append([u, -0.9 + bend])
		bevel_back.push_front([u, -0.4 + bend])
	edge.append([12.4, 0.7 + 0.035 * pow(10.9, 2.0)])
	_poly(f, edge + back, m["base"])
	_poly(f, bevel + bevel_back, m["light"])
	for i in 7:
		var u0: float = 2.0 + float(i) * 1.18
		var u1: float = u0 + 1.18
		_line(f, u0, 0.15 + 0.035 * pow(u0 - 1.5, 2.0),
			u1, 0.15 + 0.035 * pow(u1 - 1.5, 2.0), 0.12, m["dark"])

static func _knife(f, m: Dictionary, tid: String) -> void:
	_wrap(f, -1.5, 0.5, 0.45)
	_collar(f, -1.6, 0.3, 0.5, m["dark"])
	_line(f, 0.8, -1.2, 0.8, 1.2, 0.28, m["trim"])
	if tid == "leaf_dirk":
		_poly(f, [[1.2, -0.55], [3.5, -0.8], [4.7, -0.5], [6.0, 0.3],
			[4.0, 0.8], [1.2, 0.55]], m["base"])
		_poly(f, [[1.2, -0.55], [3.5, -0.8], [4.7, -0.5], [6.0, 0.3],
			[3.8, -0.12], [1.2, -0.15]], m["light"])
	else:
		_poly(f, [[1.2, -0.8], [4.5, -0.8], [6.0, 0.3], [1.2, 0.8]], m["base"])
		_poly(f, [[1.2, 0.8], [6.0, 0.3], [4.7, 0.02], [1.2, 0.32]], m["light"])
	_line(f, 1.5, -0.34, 4.15, -0.34, 0.13, m["dark"])

static func _axe(f, m: Dictionary, great: bool, tid: String) -> void:
	if great:
		_haft(f, -6.0, 12.5, 0.6)
		_wrap(f, -5.2, 1.2, 0.62)
		_collar(f, -5.8, 0.45, 0.68, m["dark"])
		# The cutting edge spans the haft direction, with a deep swept heel.
		_poly(f, [[10.1, 0.75], [11.8, 0.75], [11.8, -1.0], [13.8, -4.5],
			[12.65, -6.05], [10.6, -7.0], [8.3, -6.85], [6.1, -5.8],
			[6.65, -3.8], [7.9, -2.65], [9.5, -3.15], [10.1, -1.05]], m["base"])
		_poly(f, [[13.8, -4.5], [12.65, -6.05], [10.6, -7.0], [8.3, -6.85],
			[6.1, -5.8], [6.4, -4.95], [8.4, -6.05], [10.45, -6.2],
			[12.0, -5.5], [13.05, -4.0]], m["light"])
		_poly(f, [[7.9, -2.65], [9.5, -3.15], [10.1, -1.05], [10.1, 0.75],
			[10.65, 0.75], [10.65, -1.25], [9.8, -3.95], [7.6, -3.5]], m["dark"])
		_collar(f, 11.0, 1.5, 1.0, m["dark"])
		_collar(f, 10.9, 0.7, 0.94, m["base"])
		_line(f, 10.5, -0.75, 10.5, 0.72, 0.16, m["shine"])
	else:
		_haft(f, -2.0, 8.5, 0.55)
		_wrap(f, -1.7, 1.0)
		_collar(f, -1.9, 0.35, 0.62, m["dark"])
		if tid == "dwarf_war_axe":
			# Compact, wide bit with a heavier neck than the northern beard.
			_poly(f, [[6.75, 0.65], [8.3, 0.65], [8.3, -1.0], [9.25, -3.4],
				[8.2, -4.5], [6.65, -4.8], [4.75, -4.15], [4.9, -2.75],
				[6.3, -2.25], [6.75, -0.9]], m["base"])
			_poly(f, [[9.25, -3.4], [8.2, -4.5], [6.65, -4.8], [4.75, -4.15],
				[4.85, -3.5], [6.65, -4.15], [7.9, -3.9], [8.75, -2.85]], m["light"])
			_line(f, 6.3, -2.25, 7.0, -0.8, 0.28, m["dark"])
		else:
			_poly(f, [[6.9, 0.6], [8.2, 0.6], [8.2, -0.85], [9.3, -3.3],
				[8.55, -4.6], [7.2, -5.2], [5.65, -5.05], [4.2, -4.4],
				[4.5, -2.8], [5.4, -1.7], [6.45, -2.2], [6.9, -0.9]], m["base"])
			_poly(f, [[9.3, -3.3], [8.55, -4.6], [7.2, -5.2], [5.65, -5.05],
				[4.2, -4.4], [4.35, -3.65], [5.8, -4.35], [7.1, -4.5],
			[8.05, -4.0], [8.75, -2.7]], m["light"])
			_poly(f, [[4.5, -2.8], [5.4, -1.7], [6.45, -2.2], [6.9, -0.9],
				[7.35, -1.0], [6.7, -2.9], [5.35, -2.35]], m["dark"])
		_collar(f, 7.55, 1.3, 0.85, m["dark"])
		_collar(f, 7.6, 0.6, 0.8, m["base"])
		_line(f, 7.25, -0.62, 7.25, 0.62, 0.13, m["shine"])

static func _cleaver(f, m: Dictionary) -> void:
	_haft(f, -1.8, 1.0, 0.5)
	_wrap(f, -1.6, 0.5, 0.5)
	_collar(f, 0.6, 0.35, 0.7, m["dark"])
	_poly(f, [[0.8, 0.8], [7.4, 0.8], [7.4, -3.4], [6.6, -3.9], [0.8, -2.6]], m["base"])
	_poly(f, [[0.9, 0.8], [7.4, 0.8], [7.4, 0.12], [1.0, 0.18]], m["light"])
	_poly(f, [[0.8, -2.6], [6.6, -3.9], [7.4, -3.4], [6.4, -3.3], [0.8, -2.05]], m["dark"])
	_line(f, 2.0, -1.1, 5.7, -1.7, 0.16, m["dark"])
	var cv: PixelCanvas = f.cv
	cv.ellipse(f._wp(6.55, -2.65), 0.4, 0.4, m["outline"])

static func _mace(f, m: Dictionary, tid: String) -> void:
	_haft(f, -1.5, 6.5, 0.55)
	_wrap(f, -1.3, 1.2)
	_collar(f, 5.6, 0.6, 0.72, m["trim"])
	if tid == "war_hammer":
		_poly(f, [[6.5, -2.4], [8.8, -2.4], [8.8, 0.7], [7.5, 0.9],
			[7.5, 1.45], [8.5, 2.4], [6.65, 1.55]], m["base"])
		_poly(f, [[6.5, -2.4], [8.8, -2.4], [8.8, -1.7], [6.5, -1.7]], m["light"])
		_line(f, 7.85, -1.55, 7.85, 0.45, 0.2, m["dark"])
	else:
		# Separate flange planes and stepped crown distinguish this from a maul.
		_poly(f, [[6.1, -0.7], [6.5, -1.5], [7.0, -2.4], [8.35, -2.4],
			[8.8, -1.5], [9.2, -0.7], [9.2, 0.7], [8.8, 1.5],
			[8.35, 2.4], [7.0, 2.4], [6.5, 1.5], [6.1, 0.7]], m["dark"])
		_poly(f, [[6.55, -1.5], [7.0, -2.4], [8.35, -2.4], [8.8, -1.5],
			[8.3, -0.9], [6.9, -0.9]], m["light"])
		_poly(f, [[6.2, -0.42], [9.4, -0.42], [9.4, 0.4], [6.2, 0.4]], m["base"])
		_poly(f, [[6.55, 1.5], [7.0, 2.4], [8.35, 2.4], [8.8, 1.5],
			[8.3, 0.95], [6.9, 0.95]], m["base"])
		_line(f, 6.6, -0.18, 9.15, -0.18, 0.15, m["shine"])

static func _club(f, m: Dictionary) -> void:
	_poly(f, [[-1.5, -0.7], [-1.5, 0.7], [4.2, 1.2], [7.0, 1.7],
		[9.2, 0.6], [9.2, -0.6], [7.0, -1.7], [4.2, -1.2]], WOOD)
	_poly(f, [[0.5, -0.4], [7.0, -1.3], [8.8, -0.4], [6.3, -0.7]], WOOD_LIGHT)
	_line(f, 2.0, 0.4, 7.7, 0.65, 0.16, WOOD_DARK)
	_wrap(f, -1.3, 1.6, 0.65)
	_collar(f, 5.6, 0.55, 1.38, m["dark"])
	_collar(f, 8.0, 0.55, 1.25, m["dark"])
	for p in [[5.5, -1.3, -2.2], [7.5, 1.4, 2.3], [8.4, -1.0, -2.2]]:
		var u: float = float(p[0])
		_poly(f, [[u - 0.45, float(p[1])], [u + 0.45, float(p[1])], [u, float(p[2])]], m["light"])
	_poly(f, [[8.85, -0.45], [9.8, 0.0], [8.85, 0.45]], m["base"])

static func _maul(f, m: Dictionary, tid: String) -> void:
	_haft(f, -5.0, 9.5, 0.6)
	_wrap(f, -4.5, 1.0, 0.62)
	_collar(f, 7.65, 0.8, 0.8, m["dark"])
	if tid == "dwarf_mattock":
		_poly(f, [[8.5, -2.4], [9.1, -3.0], [11.9, -3.0], [12.5, -2.4],
			[12.5, -0.9], [10.5, -0.9], [10.1, 0.55], [12.4, 3.0],
			[9.0, 2.2], [8.5, 0.8]], m["base"])
	else:
		_poly(f, [[8.5, -2.4], [9.1, -3.0], [11.9, -3.0], [12.5, -2.4],
			[12.5, 2.4], [11.9, 3.0], [9.1, 3.0], [8.5, 2.4]], m["base"])
	_poly(f, [[8.5, -2.4], [9.1, -3.0], [11.9, -3.0], [12.5, -2.4],
		[11.8, -1.85], [9.25, -1.85]], m["light"])
	if tid == "dwarf_mattock":
		_poly(f, [[11.8, -1.85], [12.5, -2.4], [12.5, -0.9], [11.8, -0.9]], m["dark"])
		_collar(f, 9.7, 0.65, 0.9, m["dark"])
	else:
		_poly(f, [[11.8, -1.85], [12.5, -2.4], [12.5, 2.4], [11.9, 3.0],
			[11.8, 1.9]], m["dark"])
		_poly(f, [[9.8, -2.5], [10.5, -2.5], [10.5, 2.6], [9.8, 2.6]], m["dark"])
		_line(f, 9.92, -2.2, 9.92, 2.2, 0.13, m["light"])
	if tid == "dwarf_mattock":
		_poly(f, [[8.5, 1.0], [9.2, 1.4], [12.4, 3.0], [9.0, 2.6]], m["light"])

static func _spear(f, m: Dictionary, reach: float, tid: String) -> void:
	var length: float = 13.0 * clampf(reach / 200.0, 0.7, 1.2)
	_haft(f, -6.0, length, 0.45)
	_wrap(f, -1.2, 1.2, 0.5)
	# Metal shoe protects the same butt endpoint; no extra reach is introduced.
	_poly(f, [[-6.0, -0.45], [-4.85, -0.45], [-4.85, 0.45], [-6.0, 0.45]], m["dark"])
	_line(f, -5.8, -0.18, -5.0, -0.18, 0.12, m["light"])
	var width: float = 1.4
	var shoulder: float = 1.1
	if tid == "short_spear":
		width = 1.15
		shoulder = 0.75
	elif tid == "boar_spear":
		width = 1.65
	elif tid == "winged_spear":
		width = 1.5
	elif tid == "steppe_lance":
		width = 0.85
		shoulder = 0.55
	_collar(f, length - 0.45, 1.6, 0.62, m["dark"])
	_poly(f, [[length - 1.15, -0.42], [length + 0.25, -0.62],
		[length + 0.25, 0.62], [length - 1.15, 0.42]], m["base"])
	_line(f, length - 1.0, -0.22, length + 0.1, -0.37, 0.13, m["light"])
	if tid in ["short_spear", "steppe_lance"]:
		_poly(f, [[length + 0.1, -0.4], [length + shoulder, -width], [length + 4.0, 0.0],
			[length + shoulder, width], [length + 0.1, 0.4]], m["base"])
		_poly(f, [[length + 0.1, -0.4], [length + shoulder, -width], [length + 4.0, 0.0],
			[length + 0.2, 0.0]], m["light"])
	else:
		_poly(f, [[length + 0.1, -0.48], [length + 0.65, -width * 0.78],
			[length + shoulder, -width], [length + 2.1, -width * 0.75], [length + 4.0, 0.0],
			[length + 2.1, width * 0.75], [length + shoulder, width],
			[length + 0.65, width * 0.78], [length + 0.1, 0.48]], m["base"])
		_poly(f, [[length + 0.1, -0.48], [length + 0.65, -width * 0.78],
			[length + shoulder, -width], [length + 2.1, -width * 0.75], [length + 4.0, 0.0],
			[length + 0.2, 0.0]], m["light"])
	_line(f, length + 0.3, 0.0, length + 3.35, 0.0, 0.17, m["dark"])
	_line(f, length + 0.45, -0.15, length + 3.2, -0.1, 0.1, m["shine"])
	if tid == "boar_spear":
		_poly(f, [[length - 0.75, -1.8], [length - 0.15, -1.8], [length - 0.15, 1.8],
			[length - 0.75, 1.8]], m["base"])
		_line(f, length - 0.6, -1.55, length - 0.6, 1.55, 0.15, m["light"])
	elif tid == "winged_spear" or (reach > 205.0 and tid != "steppe_lance"):
		_poly(f, [[length - 0.9, -2.05], [length - 0.2, -2.05], [length + 0.2, -0.75],
			[length + 0.2, 0.75], [length - 0.2, 2.05], [length - 0.9, 2.05],
			[length - 0.65, 0.55], [length - 0.65, -0.55]], m["base"])
		_line(f, length - 0.65, -1.8, length - 0.4, -0.65, 0.15, m["light"])
		_line(f, length - 0.65, 1.8, length - 0.4, 0.65, 0.15, m["light"])

static func _glaive(f, m: Dictionary) -> void:
	# One continuous moon crescent with a short bridge inside its open centre.
	# Near hand remains u=0, far hand u=-4. The combat rig and reach stay unchanged.
	_poly(f, [[-9.0, 2.3], [-9.4, -1.3], [-7.8, -4.3], [-4.2, -6.8],
		[-0.3, -7.6], [3.8, -6.65], [7.2, -4.25], [8.8, -1.1], [9.0, 2.4],
		[6.0, -0.75], [3.2, -2.9], [-0.4, -3.8], [-3.5, -3.2], [-6.0, -1.2]], m["base"])
	# A broad outer bevel follows the chopping edge around both tapered tips.
	_poly(f, [[-9.0, 2.3], [-9.4, -1.3], [-7.8, -4.3], [-4.2, -6.8],
		[-0.3, -7.6], [3.8, -6.65], [7.2, -4.25], [8.8, -1.1], [9.0, 2.4],
		[7.9, -0.9], [6.55, -3.55], [3.4, -5.75], [-0.3, -6.6],
		[-3.8, -5.85], [-7.0, -3.7], [-8.5, -1.1]], m["light"])
	# The inset inner plane makes the open moon shape legible at battle scale.
	_poly(f, [[-9.0, 2.3], [-6.0, -1.2], [-3.5, -3.2], [-0.4, -3.8],
		[3.2, -2.9], [6.0, -0.75], [9.0, 2.4], [6.3, -1.45], [3.5, -3.65],
		[-0.35, -4.6], [-3.8, -4.0], [-6.5, -1.9]], m["dark"])
	_line(f, -3.55, -5.25, -0.4, -5.95, 0.12, m["shine"])
	_line(f, -0.4, -5.95, 2.75, -5.2, 0.12, m["shine"])
	# A short radial brace supports the handhold without filling the crescent mouth.
	_line(f, -2.0, -4.45, -2.0, 0.0, 0.46, m["dark"])
	_line(f, -2.13, -4.15, -2.13, -0.3, 0.16, m["light"])
	_haft(f, -4.8, 0.9, 0.62)
	_wrap(f, -4.6, 0.7, 0.65)
	_collar(f, -4.75, 0.55, 0.9, m["base"])
	_collar(f, 0.85, 0.55, 0.9, m["base"])
	_line(f, -4.9, -0.7, -4.9, 0.7, 0.12, m["shine"])
	_line(f, 0.7, -0.7, 0.7, 0.7, 0.12, m["shine"])

static func _sickle(f, m: Dictionary) -> void:
	_haft(f, -1.8, 1.2, 0.5)
	_wrap(f, -1.6, 0.5, 0.52)
	_collar(f, 1.0, 0.6, 0.6, m["dark"])
	_poly(f, [[1.2, 0.5], [4.15, 0.1], [6.15, -1.55], [6.4, -3.7],
		[5.3, -5.2], [3.4, -5.4], [4.6, -4.3], [5.15, -3.3],
		[4.8, -2.1], [3.65, -1.05], [1.2, -0.45]], m["base"])
	_poly(f, [[3.4, -5.4], [4.6, -4.3], [5.15, -3.3], [4.8, -2.1],
		[3.65, -1.05], [1.2, -0.45], [3.85, -0.7], [5.25, -1.9],
		[5.55, -3.4], [4.85, -4.7]], m["light"])

static func _bow(f, sprite: String) -> void:
	var length: float = float(FigurePainter.BOW_SPRITES[sprite])
	var half: float = length * 0.5
	var draw_arm_present: bool = not f._lost("hand_l") and not f._lost("arm_lower_l") and not f._lost("arm_upper_l")
	var drawn: bool = draw_arm_present and (f.pose == "prepare" or (f.pose == "strike" and float(f.t) < 0.2))
	var bend: float = 2.2 if drawn else 1.2
	var recurve: bool = sprite == "recurve"
	var pts: Array[Vector2] = []
	var wood: Color = Color("#5a3a20") if recurve else WOOD.darkened(0.1)
	var cv: PixelCanvas = f.cv
	# Same nine stave points as the legacy bow, including the recurve's curled tips.
	for i in 9:
		var u: float = -half + length * float(i) / 8.0
		var q: float = u / half
		var v: float = bend * q * q
		if recurve and absf(q) > 0.75:
			v -= (absf(q) - 0.75) * 4.0
		pts.append(f._wp(u, v))
	for i in 8:
		var taper: float = 0.48 if i == 0 or i == 7 else 0.55
		cv.capsule(pts[i], pts[i + 1], taper, wood)
		var offset: Vector2 = f._n * -0.19 * float(f.gs)
		cv.capsule(pts[i] + offset, pts[i + 1] + offset, 0.12, WOOD_LIGHT)
	if recurve:
		# Nocks attach to the actual curled endpoints, so string and horn remain joined.
		cv.capsule(pts[0], pts[0].lerp(pts[1], 0.5), 0.36, Color("#e8dcc0"))
		cv.capsule(pts[8], pts[8].lerp(pts[7], 0.5), 0.36, Color("#e8dcc0"))
	_wrap(f, -1.0, 1.0, 0.7)
	var nock: Vector2 = f.j.get("hl", f._wp(0.0, bend)) if drawn else (pts[0] + pts[8]) * 0.5
	# Keep the exact draw-hand attachment, resting string and arrow release condition.
	cv.line1(pts[0], nock, STRING)
	cv.line1(nock, pts[8], STRING)
	if drawn:
		var forward: Vector2 = (f._g - nock).normalized()
		cv.line1(nock, f._g + forward * 2.5, WOOD.lightened(0.2))
		cv.dot(f._g + forward * 3.0, Color("#c87533"))
