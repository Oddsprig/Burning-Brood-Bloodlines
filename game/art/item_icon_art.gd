class_name ItemIconArt
extends RefCounted
## Item silhouettes in the existing 32px local frame. ItemIcon owns caching,
## quality pips and real legendary stones; this module draws the physical item.

const INK: Color = Color("#211b22")
const WOOD: Color = Color("#8f613b")
const WOOD_DARK: Color = Color("#4c3025")
const WOOD_LIGHT: Color = Color("#c0945c")
const LEATHER: Color = Color("#684335")
const THREAD: Color = Color("#bea078")
const CLEAR: Color = Color(0, 0, 0, 0)

static func draw(cv: PixelCanvas, shape: String, key: String, q: int) -> bool:
	var c: Color = ItemIcon.color_of(key)
	var hi: Color = _metal_light(c, key)
	var low: Color = c.darkened(0.32)
	match shape:
		"sword", "sabre", "knife", "dirk", "cleaver":
			_blade(cv, shape, c, hi, low, q)
		"axe", "dwarf_axe", "greataxe", "sickle", "mace", "hammer", "maul", "mattock", "club", "spear", "spear_short", "spear_boar", "spear_winged", "lance", "glaive":
			_haft_weapon(cv, shape, c, hi, low, q)
		"bow", "longbow", "recurve":
			_bow(cv, shape, c, q)
		"shield_round", "shield_buckler", "shield_kite", "shield_slab":
			_shield(cv, shape, c, hi, low)
		"helm_nasal", "helm_cap", "helm_spangen", "helm_pot", "helm_closed", "helm_crescent", "helm_coif":
			_helm(cv, shape, c, hi, low)
		"mail", "scale", "lamellar", "scrap", "tunic", "gambeson":
			_body(cv, shape, c, hi, low)
		"greaves", "bracers", "shoes", "trousers":
			_clothes(cv, shape, c, hi, low)
		"loaf", "mug", "jug", "coins", "ham", "apple", "ingot", "ore", "scrap_pile", "heads", "arrow", "logs", "bolt", "hide", "gem", "sack", "bundle":
			_goods(cv, shape, key, c, hi, low)
		_:
			return false
	return true

static func _metal_light(c: Color, key: String) -> Color:
	match key.trim_prefix("#"):
		"steel": return c.lerp(Color("#f0f6fa"), 0.65)
		"bronze": return c.lerp(Color("#ffe2a4"), 0.55)
		"copper": return c.lerp(Color("#ffc294"), 0.50)
		"iron": return c.lerp(Color("#bec4c5"), 0.48)
		"tin": return c.lightened(0.14)
	return c.lightened(0.25)

static func _poly(cv: PixelCanvas, points: Array, c: Color, outlined: bool = true) -> void:
	cv.begin()
	cv.poly(PackedVector2Array(points), c)
	cv.end(INK if outlined else CLEAR, 0.0)

static func _oval(cv: PixelCanvas, center: Vector2, rx: float, ry: float, c: Color, outlined: bool = true) -> void:
	cv.begin()
	cv.ellipse(center, rx, ry, c)
	cv.end(INK if outlined else CLEAR, 0.0)

static func _bar(cv: PixelCanvas, a: Vector2, b: Vector2, radius: float, c: Color, outlined: bool = true) -> void:
	cv.begin()
	cv.capsule(a, b, radius, c)
	cv.end(INK if outlined else CLEAR, 0.0)

static func _line(cv: PixelCanvas, a: Vector2, b: Vector2, c: Color) -> void:
	cv.line1(a, b, c)

static func _shaft(cv: PixelCanvas, a: Vector2, b: Vector2, q: int = 0) -> void:
	_bar(cv, a, b, 1.15, WOOD)
	_line(cv, a + Vector2(-0.6, -0.6), b + Vector2(-0.6, -0.6), WOOD_LIGHT)
	_line(cv, a + Vector2(0.6, 0.6), b + Vector2(0.6, 0.6), WOOD_DARK)
	var n: Vector2 = (b - a).normalized()
	var cross: Vector2 = Vector2(-n.y, n.x)
	for i: int in range(4 if q < 3 else 5):
		var p: Vector2 = a + n * (2.0 + i * 1.55)
		_line(cv, p - cross * 1.0, p + cross * 1.0, LEATHER)

static func _hilt(cv: PixelCanvas, c: Color, hi: Color, q: int, guard: bool = true) -> void:
	_poly(cv, [Vector2(4, 26), Vector2(8, 21), Vector2(11, 24), Vector2(6, 29)], LEATHER)
	for i: int in range(3):
		_line(cv, Vector2(5 + i, 26 - i), Vector2(7 + i, 27 - i), THREAD if q >= 3 else WOOD_DARK)
	if guard:
		_poly(cv, [Vector2(6, 19), Vector2(8, 19), Vector2(14, 25), Vector2(14, 27), Vector2(12, 26), Vector2(7, 21)], c)
		_line(cv, Vector2(7, 19), Vector2(13, 25), hi)
	_oval(cv, Vector2(5, 27), 1.9, 1.9, c)
	cv.dot(Vector2(4, 26), hi)

static func _blade(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color, q: int) -> void:
	match shape:
		"sword":
			# Five-point, symmetric taper: two edges, a central fuller, square forte.
			_poly(cv, [Vector2(9, 19), Vector2(23, 5), Vector2(29, 3), Vector2(27, 9), Vector2(13, 23)], c)
			_poly(cv, [Vector2(10, 19), Vector2(24, 5), Vector2(28, 4), Vector2(12, 21)], hi, false)
			_poly(cv, [Vector2(12, 21), Vector2(28, 4), Vector2(26, 9), Vector2(13, 22)], low, false)
			_line(cv, Vector2(13, 18), Vector2(24, 7), c.darkened(0.48))
			_hilt(cv, c, hi, q)
		"sabre":
			# Single edge bows away from the spine; enclosed knuckle guard.
			_poly(cv, [Vector2(9, 21), Vector2(13, 16), Vector2(19, 9), Vector2(25, 5), Vector2(29, 5), Vector2(25, 9), Vector2(21, 14), Vector2(16, 21), Vector2(12, 24)], c)
			_line(cv, Vector2(11, 21), Vector2(20, 10), low)
			_line(cv, Vector2(20, 10), Vector2(26, 6), low)
			_line(cv, Vector2(15, 21), Vector2(21, 14), hi)
			_line(cv, Vector2(21, 14), Vector2(27, 7), hi)
			_hilt(cv, c, hi, q, false)
			_poly(cv, [Vector2(8, 19), Vector2(11, 21), Vector2(14, 26), Vector2(12, 29), Vector2(7, 30), Vector2(5, 28), Vector2(10, 28), Vector2(12, 26), Vector2(10, 23), Vector2(6, 21)], c)
			_line(cv, Vector2(12, 27), Vector2(8, 29), hi)
		"knife":
			# Broken-back seax: long straight edge, clipped spine and broad heel.
			_poly(cv, [Vector2(9, 20), Vector2(17, 11), Vector2(23, 9), Vector2(27, 9), Vector2(24, 15), Vector2(13, 24)], c)
			_poly(cv, [Vector2(12, 22), Vector2(25, 10), Vector2(23, 15), Vector2(13, 23)], hi, false)
			_line(cv, Vector2(11, 20), Vector2(19, 12), low)
			_hilt(cv, c, hi, q, false)
			_bar(cv, Vector2(8, 20), Vector2(12, 24), 0.7, c)
		"dirk":
			# Leaf dirk: pinched waist expands into a double-edged leaf and point.
			_poly(cv, [Vector2(9, 20), Vector2(13, 15), Vector2(16, 9), Vector2(21, 6), Vector2(27, 5), Vector2(26, 11), Vector2(23, 16), Vector2(17, 19), Vector2(12, 23)], c)
			_poly(cv, [Vector2(10, 20), Vector2(14, 15), Vector2(17, 10), Vector2(22, 7), Vector2(26, 6), Vector2(12, 22)], hi, false)
			_poly(cv, [Vector2(13, 21), Vector2(26, 6), Vector2(25, 11), Vector2(22, 15), Vector2(17, 18)], low, false)
			_line(cv, Vector2(13, 20), Vector2(23, 9), c.darkened(0.43))
			_hilt(cv, c, hi, q, false)
			_bar(cv, Vector2(8, 20), Vector2(12, 24), 0.7, c)
			_line(cv, Vector2(8, 20), Vector2(12, 24), hi)
		"cleaver":
			# Heavy chopping blade with a square back and sloping cutting edge.
			_poly(cv, [Vector2(9, 19), Vector2(20, 5), Vector2(27, 5), Vector2(29, 8), Vector2(23, 17), Vector2(14, 24)], c)
			_poly(cv, [Vector2(13, 21), Vector2(25, 9), Vector2(28, 7), Vector2(22, 17), Vector2(14, 23)], hi, false)
			_line(cv, Vector2(11, 19), Vector2(21, 7), low)
			cv.dot(Vector2(24, 7), low)
			_hilt(cv, c, hi, q, false)
			_bar(cv, Vector2(9, 20), Vector2(13, 24), 0.7, c)

static func _haft_weapon(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color, q: int) -> void:
	if shape in ["axe", "dwarf_axe", "greataxe"]:
		_axe_icon(cv, shape, c, hi, low, q)
		return
	if shape in ["spear", "spear_short", "spear_boar", "spear_winged", "lance"]:
		_spear_icon(cv, shape, c, hi, low, q)
		return
	if shape == "glaive":
		_moon_glaive(cv, c, hi, low, q)
		return
	if shape == "club":
		_poly(cv, [Vector2(5, 27), Vector2(13, 17), Vector2(17, 9), Vector2(20, 5), Vector2(24, 6), Vector2(27, 10), Vector2(25, 15), Vector2(17, 22), Vector2(8, 29)], WOOD)
		_line(cv, Vector2(9, 25), Vector2(21, 10), WOOD_LIGHT)
		_line(cv, Vector2(16, 18), Vector2(23, 9), WOOD_DARK)
		_line(cv, Vector2(19, 17), Vector2(24, 12), WOOD_DARK)
		for p: Vector2 in [Vector2(16, 10), Vector2(22, 5), Vector2(27, 10), Vector2(24, 17)]:
			_poly(cv, [p + Vector2(-1, 1), p + Vector2(0, -2), p + Vector2(2, 1)], c)
			cv.dot(p, hi)
		_bar(cv, Vector2(6, 26), Vector2(10, 22), 1.0, LEATHER, false)
		_line(cv, Vector2(6, 26), Vector2(9, 26), THREAD)
		_line(cv, Vector2(8, 23), Vector2(10, 24), THREAD)
		return
	var end: Vector2 = Vector2(21, 9)
	var start: Vector2 = Vector2(6, 28)
	if shape == "sickle":
		end = Vector2(20, 10)
	_shaft(cv, start, end, q)
	match shape:
		"sickle":
			# One continuous open crescent, leaving visible negative space.
			_poly(cv, [Vector2(19, 13), Vector2(17, 9), Vector2(18, 6), Vector2(21, 4), Vector2(25, 4), Vector2(29, 7), Vector2(30, 11), Vector2(29, 15), Vector2(26, 19), Vector2(23, 20), Vector2(26, 15), Vector2(27, 11), Vector2(25, 8), Vector2(22, 7), Vector2(20, 9), Vector2(21, 12)], c)
			_line(cv, Vector2(22, 7), Vector2(25, 8), hi)
			_line(cv, Vector2(25, 8), Vector2(27, 11), hi)
			_line(cv, Vector2(27, 11), Vector2(26, 15), hi)
			_line(cv, Vector2(20, 5), Vector2(24, 5), low)
		"mace":
			# Three long flanges around a visible central socket.
			_poly(cv, [Vector2(16, 9), Vector2(18, 4), Vector2(21, 4), Vector2(21, 13), Vector2(18, 16)], low)
			_poly(cv, [Vector2(23, 4), Vector2(26, 4), Vector2(29, 8), Vector2(27, 13), Vector2(23, 15)], c)
			_poly(cv, [Vector2(20, 3), Vector2(23, 2), Vector2(25, 5), Vector2(24, 14), Vector2(22, 17), Vector2(20, 14)], c)
			_line(cv, Vector2(22, 4), Vector2(22, 14), hi)
			_line(cv, Vector2(25, 5), Vector2(27, 8), hi)
			_line(cv, Vector2(18, 5), Vector2(17, 9), hi)
		"hammer":
			# War hammer: compact square striking face opposite a narrow rear pick.
			_poly(cv, [Vector2(13, 4), Vector2(19, 5), Vector2(22, 8), Vector2(27, 8), Vector2(30, 11), Vector2(27, 15), Vector2(24, 15), Vector2(20, 11), Vector2(17, 8)], c)
			_poly(cv, [Vector2(24, 9), Vector2(27, 9), Vector2(29, 11), Vector2(26, 14), Vector2(24, 13)], low, false)
			_poly(cv, [Vector2(14, 5), Vector2(19, 6), Vector2(22, 9), Vector2(21, 10), Vector2(17, 7)], hi, false)
			_line(cv, Vector2(23, 9), Vector2(26, 12), hi)
			_line(cv, Vector2(25, 9), Vector2(28, 11), hi)
			_poly(cv, [Vector2(19, 9), Vector2(21, 7), Vector2(24, 10), Vector2(22, 13)], c.darkened(0.15))
			_line(cv, Vector2(20, 9), Vector2(22, 11), hi)
		"maul":
			# Octagonal rectangle in perspective, with distinct face and side wall.
			_poly(cv, [Vector2(14, 8), Vector2(20, 3), Vector2(24, 3), Vector2(30, 9), Vector2(30, 12), Vector2(24, 17), Vector2(21, 17), Vector2(14, 11)], c)
			_poly(cv, [Vector2(15, 8), Vector2(20, 4), Vector2(24, 4), Vector2(28, 8), Vector2(22, 13), Vector2(19, 12)], hi, false)
			_poly(cv, [Vector2(22, 13), Vector2(29, 8), Vector2(29, 12), Vector2(24, 16), Vector2(22, 16)], low, false)
			_line(cv, Vector2(16, 8), Vector2(21, 12), c)
			_line(cv, Vector2(24, 5), Vector2(27, 8), c)
		"mattock":
			# Heavy dwarf mattock: chamfered hammer face and long downturned pick.
			_poly(cv, [Vector2(12, 5), Vector2(17, 3), Vector2(21, 7), Vector2(24, 8), Vector2(28, 12), Vector2(29, 18), Vector2(26, 16), Vector2(23, 13), Vector2(19, 11), Vector2(15, 11), Vector2(11, 7)], c)
			_poly(cv, [Vector2(12, 5), Vector2(17, 4), Vector2(20, 7), Vector2(16, 10), Vector2(12, 7)], hi, false)
			_poly(cv, [Vector2(20, 8), Vector2(24, 9), Vector2(27, 13), Vector2(28, 17), Vector2(25, 14), Vector2(22, 12), Vector2(19, 11)], low, false)
			_line(cv, Vector2(22, 10), Vector2(26, 13), hi)
			_poly(cv, [Vector2(19, 8), Vector2(22, 8), Vector2(24, 11), Vector2(21, 13), Vector2(18, 11)], c)
			_line(cv, Vector2(19, 9), Vector2(21, 11), hi)

static func _weapon_point(p: Vector2, origin: Vector2, axis: Vector2) -> Vector2:
	return origin + axis * p.x + Vector2(-axis.y, axis.x) * p.y

static func _weapon_poly(cv: PixelCanvas, points: Array, origin: Vector2, axis: Vector2, c: Color, outlined: bool = true) -> void:
	var transformed: Array[Vector2] = []
	for point: Array in points:
		transformed.append(_weapon_point(Vector2(float(point[0]), float(point[1])), origin, axis))
	_poly(cv, transformed, c, outlined)

static func _weapon_line(cv: PixelCanvas, a: Vector2, b: Vector2, origin: Vector2, axis: Vector2, c: Color) -> void:
	_line(cv, _weapon_point(a, origin, axis), _weapon_point(b, origin, axis), c)

static func _axe_icon(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color, q: int) -> void:
	# These forged profiles follow the battle art: a transverse curved bit,
	# deep working heel, open neck and a steel eye around a real wooden haft.
	var origin: Vector2 = Vector2(7.8, 24.15)
	var axis: Vector2 = Vector2(1.6, -1.5)
	var eye: float = 7.55
	var bottom: float = -1.8
	var top: float = 8.5
	if shape == "greataxe":
		origin = Vector2(7.35, 25.64)
		axis = Vector2(1.15, -1.24)
		eye = 11.0
		bottom = -2.0
		top = 12.5
	elif shape == "dwarf_axe":
		origin = Vector2(10, 23)
		axis = Vector2(1.38, -1.5)
	_shaft(cv, _weapon_point(Vector2(bottom, 0), origin, axis), _weapon_point(Vector2(top, 0), origin, axis), q)
	if shape == "greataxe":
		_weapon_poly(cv, [[10.1, 0.75], [11.8, 0.75], [11.8, -1.0], [13.8, -4.5], [12.65, -6.05], [10.6, -7.0], [8.3, -6.85], [6.1, -5.8], [6.65, -3.8], [7.9, -2.65], [9.5, -3.15], [10.1, -1.05]], origin, axis, c)
		_weapon_poly(cv, [[13.8, -4.5], [12.65, -6.05], [10.6, -7.0], [8.3, -6.85], [6.1, -5.8], [6.4, -4.95], [8.4, -6.05], [10.45, -6.2], [12.0, -5.5], [13.05, -4.0]], origin, axis, hi, false)
		_weapon_poly(cv, [[7.9, -2.65], [9.5, -3.15], [10.1, -1.05], [10.1, 0.75], [10.65, 0.75], [10.65, -1.25], [9.8, -3.95], [7.6, -3.5]], origin, axis, low, false)
	elif shape == "dwarf_axe":
		_weapon_poly(cv, [[6.75, 0.65], [8.3, 0.65], [8.3, -1.0], [9.25, -3.4], [8.2, -4.5], [6.65, -4.8], [4.75, -4.15], [4.9, -2.75], [6.3, -2.25], [6.75, -0.9]], origin, axis, c)
		_weapon_poly(cv, [[9.25, -3.4], [8.2, -4.5], [6.65, -4.8], [4.75, -4.15], [4.85, -3.5], [6.65, -4.15], [7.9, -3.9], [8.75, -2.85]], origin, axis, hi, false)
		_weapon_line(cv, Vector2(6.3, -2.25), Vector2(7.0, -0.8), origin, axis, low)
	else:
		_weapon_poly(cv, [[6.9, 0.6], [8.2, 0.6], [8.2, -0.85], [9.3, -3.3], [8.55, -4.6], [7.2, -5.2], [5.65, -5.05], [4.2, -4.4], [4.5, -2.8], [5.4, -1.7], [6.45, -2.2], [6.9, -0.9]], origin, axis, c)
		_weapon_poly(cv, [[9.3, -3.3], [8.55, -4.6], [7.2, -5.2], [5.65, -5.05], [4.2, -4.4], [4.35, -3.65], [5.8, -4.35], [7.1, -4.5], [8.05, -4.0], [8.75, -2.7]], origin, axis, hi, false)
		_weapon_poly(cv, [[4.5, -2.8], [5.4, -1.7], [6.45, -2.2], [6.9, -0.9], [7.35, -1.0], [6.7, -2.9], [5.35, -2.35]], origin, axis, low, false)
	_weapon_poly(cv, [[eye - 0.65, -0.85], [eye + 0.65, -0.85], [eye + 0.65, 0.85], [eye - 0.65, 0.85]], origin, axis, low)
	_weapon_poly(cv, [[eye - 0.25, -0.78], [eye + 0.3, -0.78], [eye + 0.3, 0.78], [eye - 0.25, 0.78]], origin, axis, c, false)
	_weapon_line(cv, Vector2(eye - 0.4, -0.65), Vector2(eye - 0.4, 0.65), origin, axis, hi)

static func _spear_icon(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color, q: int) -> void:
	var origin: Vector2 = Vector2(21, 12)
	var axis: Vector2 = Vector2(1.6, -1.55)
	var start: Vector2 = Vector2(4.5, 28.5)
	var width: float = 1.4
	var shoulder: float = 1.1
	if shape == "spear_short":
		origin = Vector2(20, 14)
		start = Vector2(8, 26)
		width = 1.15
		shoulder = 0.75
	elif shape == "spear_boar":
		width = 1.65
	elif shape == "spear_winged":
		width = 1.5
	elif shape == "lance":
		origin = Vector2(22, 11)
		axis = Vector2(1.7, -1.9)
		width = 0.85
		shoulder = 0.55
	_shaft(cv, start, _weapon_point(Vector2(0.35, 0), origin, axis), q)
	var butt_direction: Vector2 = axis.normalized()
	_bar(cv, start - butt_direction * 0.6, start + butt_direction * 1.2, 1.15, low)
	_line(cv, start - Vector2(0.5, 0.5), start + butt_direction * 0.9 - Vector2(0.5, 0.5), hi)
	if shape in ["spear_short", "lance"]:
		_weapon_poly(cv, [[0.1, -0.4], [shoulder, -width], [4.0, 0.0], [shoulder, width], [0.1, 0.4]], origin, axis, c)
		_weapon_poly(cv, [[0.1, -0.4], [shoulder, -width], [4.0, 0.0], [0.2, 0.0]], origin, axis, hi, false)
	else:
		_weapon_poly(cv, [[0.1, -0.4], [shoulder, -width], [2.2, -width * 0.82], [4.0, 0.0], [2.2, width * 0.82], [shoulder, width], [0.1, 0.4]], origin, axis, c)
		_weapon_poly(cv, [[0.1, -0.4], [shoulder, -width], [2.2, -width * 0.82], [4.0, 0.0], [0.2, 0.0]], origin, axis, hi, false)
	_weapon_line(cv, Vector2(0.3, 0), Vector2(3.4, 0), origin, axis, low)
	if shape == "spear_boar":
		_weapon_poly(cv, [[-0.75, -1.8], [-0.15, -1.8], [-0.15, 1.8], [-0.75, 1.8]], origin, axis, c)
		_weapon_line(cv, Vector2(-0.6, -1.55), Vector2(-0.6, 1.55), origin, axis, hi)
	elif shape == "spear_winged":
		_weapon_poly(cv, [[-0.9, -2.05], [-0.2, -2.05], [0.2, -0.75], [0.2, 0.75], [-0.2, 2.05], [-0.9, 2.05], [-0.65, 0.55], [-0.65, -0.55]], origin, axis, c)
		_weapon_line(cv, Vector2(-0.75, -1.8), Vector2(-0.2, -1.0), origin, axis, hi)
		_weapon_line(cv, Vector2(-0.75, 1.8), Vector2(-0.2, 1.0), origin, axis, hi)
	_weapon_poly(cv, [[-1.15, -0.42], [0.25, -0.62], [0.25, 0.62], [-1.15, 0.42]], origin, axis, low)
	_weapon_line(cv, Vector2(-1.0, -0.22), Vector2(0.1, -0.37), origin, axis, hi)

static func _moon_glaive(cv: PixelCanvas, c: Color, hi: Color, low: Color, q: int) -> void:
	# One original broad crescent, not a pair of blades or a polearm. The
	# sweeping tips frame an open moon, with a central bridge and radial brace.
	var origin: Vector2 = Vector2(16, 21)
	var axis: Vector2 = Vector2(1.43, 0)
	_weapon_poly(cv, [[-9, 2.3], [-9.4, -1.3], [-7.8, -4.3], [-4.2, -6.8], [-0.3, -7.6], [3.8, -6.65], [7.2, -4.25], [8.8, -1.1], [9, 2.4], [6, -0.75], [3.2, -2.9], [-0.4, -3.8], [-3.5, -3.2], [-6, -1.2]], origin, axis, c)
	_weapon_poly(cv, [[-9, 2.3], [-9.4, -1.3], [-7.8, -4.3], [-4.2, -6.8], [-0.3, -7.6], [3.8, -6.65], [7.2, -4.25], [8.8, -1.1], [9, 2.4], [8.1, -1.1], [6.7, -3.65], [3.5, -5.8], [-0.35, -6.7], [-4.0, -6.0], [-7.1, -3.85], [-8.5, -1.15]], origin, axis, hi, false)
	_weapon_poly(cv, [[-6, -1.2], [-3.5, -3.2], [-0.4, -3.8], [3.2, -2.9], [6, -0.75], [5.7, -1.6], [3.2, -3.55], [-0.4, -4.4], [-3.8, -3.8], [-6.5, -1.8]], origin, axis, low, false)
	_weapon_poly(cv, [[-2.65, -4.45], [-1.35, -4.45], [-1.35, 0.5], [-2.65, 0.5]], origin, axis, low)
	_weapon_line(cv, Vector2(-2.4, -4.1), Vector2(-2.4, 0), origin, axis, hi)
	_weapon_poly(cv, [[-4.8, -0.65], [0.9, -0.65], [0.9, 0.65], [-4.8, 0.65]], origin, axis, c)
	_weapon_poly(cv, [[-4.1, -0.5], [0.2, -0.5], [0.2, 0.5], [-4.1, 0.5]], origin, axis, LEATHER, false)
	for i: int in range(6):
		var x: float = -3.85 + i * 0.65
		_weapon_line(cv, Vector2(x, -0.4), Vector2(x + 0.25, 0.4), origin, axis, THREAD if q >= 3 else WOOD_DARK)

static func _bow(cv: PixelCanvas, shape: String, c: Color, q: int) -> void:
	var points: Array[Vector2]
	match shape:
		"longbow":
			points = [Vector2(14, 4), Vector2(19, 7), Vector2(22, 12), Vector2(23, 16), Vector2(22, 21), Vector2(19, 26), Vector2(14, 29)]
		"recurve":
			points = [Vector2(20, 5), Vector2(15, 6), Vector2(18, 9), Vector2(23, 13), Vector2(24, 16), Vector2(23, 20), Vector2(18, 24), Vector2(15, 27), Vector2(20, 28)]
		_:
			points = [Vector2(14, 6), Vector2(20, 9), Vector2(23, 13), Vector2(24, 17), Vector2(22, 22), Vector2(18, 26), Vector2(14, 27)]
	_line(cv, points[0], points[-1], Color("#d7ceb1"))
	for i: int in range(points.size() - 1):
		_bar(cv, points[i], points[i + 1], 0.9 if i == 0 or i == points.size() - 2 else 1.3, c)
		_line(cv, points[i] + Vector2(-0.6, 0), points[i + 1] + Vector2(-0.6, 0), c.lightened(0.22))
	# The belly grip includes the established legendary stone position.
	_poly(cv, [Vector2(20, 13), Vector2(23, 13), Vector2(24, 19), Vector2(21, 20)], LEATHER)
	for y: int in range(14, 20, 2):
		_line(cv, Vector2(21, y), Vector2(23, y + 1), THREAD if q >= 3 else WOOD_DARK)

static func _shield(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color) -> void:
	match shape:
		"shield_round":
			_oval(cv, Vector2(16, 17), 12.3, 12.3, low)
			_oval(cv, Vector2(16, 17), 10.3, 10.3, c, false)
			for x: int in [9, 13, 18, 22]:
				var half: float = sqrt(maxf(0.0, 100.0 - pow(x - 16.0, 2)))
				_line(cv, Vector2(x, 17 - half), Vector2(x, 17 + half), low)
			_line(cv, Vector2(8, 7), Vector2(15, 5), hi)
			for p: Vector2 in [Vector2(7, 11), Vector2(24, 10), Vector2(6, 22), Vector2(25, 23), Vector2(16, 28)]:
				cv.dot(p, hi)
			_oval(cv, Vector2(16, 16), 4, 4, low)
			_oval(cv, Vector2(15.5, 15.5), 2.8, 2.8, c.lightened(0.12), false)
			_line(cv, Vector2(14, 14), Vector2(16, 13), hi)
		"shield_buckler":
			# Compact dished metal face and four radial ribs, no timber planking.
			_poly(cv, [Vector2(12, 7), Vector2(20, 7), Vector2(25, 12), Vector2(25, 20), Vector2(20, 25), Vector2(12, 25), Vector2(7, 20), Vector2(7, 12)], low)
			_oval(cv, Vector2(16, 16), 7.8, 7.8, c, false)
			for p: Vector2 in [Vector2(11, 11), Vector2(21, 11), Vector2(11, 21), Vector2(21, 21)]:
				_line(cv, p, Vector2(16, 16), low)
				cv.dot(p, hi)
			_oval(cv, Vector2(16, 16), 4.2, 4.2, low)
			_oval(cv, Vector2(15, 15), 3.0, 3.0, c.lightened(0.12), false)
			_line(cv, Vector2(13, 14), Vector2(15, 12), hi)
		"shield_kite":
			_poly(cv, [Vector2(7, 5), Vector2(12, 3), Vector2(20, 3), Vector2(25, 5), Vector2(25, 12), Vector2(23, 19), Vector2(16, 30), Vector2(9, 19), Vector2(7, 12)], low)
			_poly(cv, [Vector2(9, 6), Vector2(13, 5), Vector2(19, 5), Vector2(23, 6), Vector2(23, 12), Vector2(21, 19), Vector2(16, 27), Vector2(11, 19), Vector2(9, 12)], c, false)
			_poly(cv, [Vector2(16, 5), Vector2(23, 6), Vector2(23, 12), Vector2(21, 19), Vector2(16, 27)], low.lightened(0.08), false)
			_line(cv, Vector2(16, 5), Vector2(16, 26), hi)
			_line(cv, Vector2(10, 13), Vector2(22, 13), low)
			_oval(cv, Vector2(16, 10), 2.4, 2.4, c.lightened(0.15))
			_line(cv, Vector2(9, 6), Vector2(13, 5), hi)
		"shield_slab":
			# Tall convex board shield with cut corners and central spine.
			_poly(cv, [Vector2(8, 4), Vector2(24, 4), Vector2(27, 7), Vector2(26, 27), Vector2(23, 29), Vector2(9, 29), Vector2(6, 27), Vector2(5, 7)], low)
			_poly(cv, [Vector2(9, 6), Vector2(23, 6), Vector2(25, 8), Vector2(24, 26), Vector2(22, 27), Vector2(10, 27), Vector2(8, 26), Vector2(7, 8)], c, false)
			for x: int in [11, 16, 21]:
				_line(cv, Vector2(x, 7), Vector2(x, 27), low)
			for y: int in [10, 23]:
				cv.rect(Rect2(7, y, 18, 2), low)
				for x: int in [9, 16, 23]:
					cv.dot(Vector2(x, y), hi)
			_poly(cv, [Vector2(15, 6), Vector2(17, 6), Vector2(18, 25), Vector2(16, 28), Vector2(14, 25)], c.lightened(0.10))
			_line(cv, Vector2(15, 7), Vector2(15, 24), hi)

static func _helm(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color) -> void:
	if shape == "helm_closed":
		_poly(cv, [Vector2(7, 24),Vector2(5, 13),Vector2(8, 7),Vector2(13, 3),Vector2(19, 3),Vector2(24, 7),Vector2(27, 14),Vector2(25, 25),Vector2(20, 29),Vector2(11, 28)],c)
		_poly(cv, [Vector2(19, 5),Vector2(24, 9),Vector2(26, 15),Vector2(24, 24),Vector2(20, 28),Vector2(18, 23)],low,false)
		_poly(cv, [Vector2(8, 13),Vector2(14, 14),Vector2(14, 16),Vector2(8, 15)],INK,false)
		_poly(cv, [Vector2(18, 14),Vector2(24, 13),Vector2(24, 15),Vector2(18, 16)],INK,false)
		_poly(cv, [Vector2(15, 5),Vector2(17, 5),Vector2(18, 23),Vector2(16, 26),Vector2(14, 23)],c.lightened(0.14),false)
		_line(cv,Vector2(15, 5),Vector2(15, 24),hi)
		_line(cv,Vector2(8, 11),Vector2(11, 6),hi)
		for x: int in [10,12,20,22]:
			_line(cv,Vector2(x,20),Vector2(x,22),low)
		_line(cv,Vector2(9, 25),Vector2(13, 27),hi)
		return
	if shape == "helm_coif":
		_poly(cv, [Vector2(11, 4), Vector2(21, 4), Vector2(26, 10), Vector2(26, 22), Vector2(29, 27), Vector2(23, 29), Vector2(9, 29), Vector2(3, 27), Vector2(6, 22), Vector2(6, 10)], low)
		_poly(cv, [Vector2(12, 5), Vector2(20, 5), Vector2(24, 10), Vector2(24, 24), Vector2(26, 26), Vector2(22, 27), Vector2(10, 27), Vector2(6, 26), Vector2(8, 23), Vector2(8, 10)], c, false)
		# The face is a deliberate open hole, with an outlined brow and jaw.
		_poly(cv, [Vector2(12, 11), Vector2(20, 11), Vector2(22, 14), Vector2(21, 21), Vector2(18, 24), Vector2(14, 24), Vector2(11, 21), Vector2(10, 14)], INK, false)
		_mail_links(cv, c, Rect2(7, 6, 18, 22), true)
		_line(cv, Vector2(12, 10), Vector2(20, 10), hi)
		return
	if shape == "helm_pot":
		_poly(cv, [Vector2(10, 5), Vector2(22, 5), Vector2(25, 9), Vector2(25, 24), Vector2(21, 28), Vector2(11, 28), Vector2(7, 24), Vector2(7, 9)], c)
		_poly(cv, [Vector2(19, 7), Vector2(24, 10), Vector2(24, 24), Vector2(20, 27), Vector2(19, 22)], low, false)
		_line(cv, Vector2(10, 7), Vector2(21, 7), hi)
		cv.rect(Rect2(9, 13, 6, 2), INK)
		cv.rect(Rect2(17, 13, 6, 2), INK)
		cv.rect(Rect2(15, 10, 2, 16), low)
		_line(cv, Vector2(15, 10), Vector2(15, 25), hi)
		for y: int in [20, 23]:
			for x: int in [10, 12, 20, 22]:
				cv.dot(Vector2(x, y), INK)
		return
	# Domes have angular crowns and a readable black face opening below the brow.
	var top: int = 6 if shape == "helm_cap" else 5
	_poly(cv, [Vector2(6, 18), Vector2(7, 11), Vector2(11, top + 1), Vector2(16, top), Vector2(21, top + 1), Vector2(25, 11), Vector2(26, 18), Vector2(23, 20), Vector2(9, 20)], c)
	_poly(cv, [Vector2(19, top + 2), Vector2(24, 12), Vector2(25, 18), Vector2(21, 19), Vector2(20, 11)], low, false)
	_line(cv, Vector2(8, 12), Vector2(12, top + 2), hi)
	_line(cv, Vector2(12, top + 2), Vector2(17, top + 1), hi)
	cv.rect(Rect2(8, 17, 16, 2), low)
	_line(cv, Vector2(8, 17), Vector2(23, 17), hi)
	if shape == "helm_cap":
		_poly(cv, [Vector2(7, 19), Vector2(11, 19), Vector2(10, 25), Vector2(7, 24)], c)
		_poly(cv, [Vector2(21, 19), Vector2(25, 19), Vector2(25, 24), Vector2(22, 25)], low)
	elif shape == "helm_nasal":
		_poly(cv, [Vector2(14, 17), Vector2(18, 17), Vector2(18, 26), Vector2(16, 28), Vector2(14, 26)], c)
		_line(cv, Vector2(15, 18), Vector2(15, 26), hi)
		_poly(cv, [Vector2(7, 19), Vector2(10, 19), Vector2(10, 24), Vector2(7, 23)], low)
		_poly(cv, [Vector2(22, 19), Vector2(25, 19), Vector2(25, 23), Vector2(22, 24)], low)
	elif shape == "helm_spangen":
		_poly(cv, [Vector2(15, 5), Vector2(17, 5), Vector2(18, 17), Vector2(14, 17)], low, false)
		_line(cv, Vector2(15, 6), Vector2(15, 16), hi)
		_line(cv, Vector2(10, 8), Vector2(9, 16), low)
		_line(cv, Vector2(22, 8), Vector2(23, 16), low)
		for p: Vector2 in [Vector2(9, 17), Vector2(15, 17), Vector2(22, 17)]:
			cv.dot(p, hi)
		_poly(cv, [Vector2(6, 19), Vector2(11, 19), Vector2(11, 26), Vector2(8, 28), Vector2(6, 25)], c)
		_poly(cv, [Vector2(21, 19), Vector2(26, 19), Vector2(26, 25), Vector2(24, 28), Vector2(21, 26)], low)
	elif shape == "helm_crescent":
		# Same tilted moon as the worn crest; the open upper-right bite sits
		# above the bowl so its negative space remains transparent and readable.
		var moon_origin: Vector2 = Vector2(15.5,3.9)
		var moon_scale: float = 2.6
		var moon_points: PackedVector2Array = PackedVector2Array()
		for p: Vector2 in [Vector2(0.48,-1.14),Vector2(-0.18,-1.17),
			Vector2(-0.82,-0.88),Vector2(-1.21,-0.33),Vector2(-1.24,0.34),
			Vector2(-0.80,0.90),Vector2(-0.19,1.12),Vector2(0.49,1.00),
			Vector2(1.00,0.55),Vector2(0.53,0.67),Vector2(0.09,0.57),
			Vector2(-0.26,0.24),Vector2(-0.34,-0.20),Vector2(-0.16,-0.67),
			Vector2(0.14,-1.00)]:
			moon_points.append(moon_origin+p*moon_scale)
		cv.begin()
		cv.poly(PackedVector2Array([Vector2(13.6,5.4),Vector2(14.9,5.5),
			Vector2(15.4,7.0),Vector2(13.9,7.15)]),c)
		cv.poly(moon_points,hi)
		cv.end(INK,0.0)
		cv.capsule(moon_origin+Vector2(0.43,0.66)*moon_scale,
			moon_origin+Vector2(0.09,0.55)*moon_scale,0.20,low)
		cv.capsule(moon_origin+Vector2(0.09,0.55)*moon_scale,
			moon_origin+Vector2(-0.24,0.22)*moon_scale,0.20,low)
		cv.capsule(moon_origin+Vector2(-0.24,0.22)*moon_scale,
			moon_origin+Vector2(-0.31,-0.18)*moon_scale,0.20,low)
		cv.capsule(moon_origin+Vector2(-1.05,-0.30)*moon_scale,
			moon_origin+Vector2(-0.73,-0.73)*moon_scale,0.18,hi.lightened(0.12))
		cv.capsule(moon_origin+Vector2(-0.73,-0.73)*moon_scale,
			moon_origin+Vector2(-0.19,-1.03)*moon_scale,0.18,hi.lightened(0.12))
		_poly(cv, [Vector2(7, 19), Vector2(11, 19), Vector2(12, 25), Vector2(9, 28), Vector2(6, 25)], c)
		_poly(cv, [Vector2(21, 19), Vector2(25, 19), Vector2(26, 25), Vector2(23, 28), Vector2(20, 25)], low)

static func _mail_links(cv: PixelCanvas, c: Color, area: Rect2, coif: bool = false) -> void:
	for y: int in range(int(area.position.y), int(area.end.y), 3):
		for x: int in range(int(area.position.x) + (1 if y % 2 == 0 else 0), int(area.end.x), 3):
			if coif and x > 9 and x < 22 and y > 10 and y < 24:
				continue
			# Clip the link pattern to the already occupied garment, not its backdrop.
			var p: Vector2i = cv.map_i(Vector2(x, y))
			if cv.get_px(p.x, p.y).a > 0.5 and cv.get_px(p.x, p.y) != INK:
				cv.dot(Vector2(x, y), c.lightened(0.25))
				p = cv.map_i(Vector2(x + 1, y + 1))
				if cv.get_px(p.x, p.y).a > 0.5 and cv.get_px(p.x, p.y) != INK:
					cv.dot(Vector2(x + 1, y + 1), c.darkened(0.40))

static func _body(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color) -> void:
	if shape == "scale":
		# Rounded hanging scales overlap on a short-sleeved leather-backed coat.
		_poly(cv, [Vector2(9, 5), Vector2(13, 7), Vector2(19, 7), Vector2(23, 5), Vector2(28, 10), Vector2(27, 16), Vector2(23, 14), Vector2(24, 28), Vector2(20, 30), Vector2(12, 30), Vector2(8, 28), Vector2(9, 14), Vector2(5, 16), Vector2(4, 10)], LEATHER)
		for row: int in range(6):
			var y: float = 8.5 + row * 3.25
			var start_x: float = 9.0 if row % 2 == 0 else 7.25
			for col: int in range(5 if row % 2 != 0 else 4):
				var x: float = start_x + col * 3.6
				_poly(cv, [Vector2(x, y), Vector2(x + 3.2, y), Vector2(x + 3.2, y + 2), Vector2(x + 2.4, y + 3.3), Vector2(x + 1.6, y + 3.8), Vector2(x + 0.8, y + 3.3), Vector2(x, y + 2)], c, false)
				_line(cv, Vector2(x + 0.5, y + 1), Vector2(x + 0.5, y + 2), hi)
				_line(cv, Vector2(x + 1, y + 3), Vector2(x + 2.5, y + 3), low)
		_poly(cv, [Vector2(5, 9), Vector2(9, 7), Vector2(10, 10), Vector2(9, 14), Vector2(5, 13)], c)
		_poly(cv, [Vector2(22, 10), Vector2(23, 7), Vector2(27, 9), Vector2(27, 13), Vector2(23, 14)], low)
		_line(cv, Vector2(5, 10), Vector2(8, 8), hi)
		_poly(cv, [Vector2(12, 6), Vector2(20, 6), Vector2(19, 9), Vector2(16, 10), Vector2(13, 9)], INK, false)
		cv.rect(Rect2(9, 23, 14, 2), LEATHER)
		cv.rect(Rect2(15, 23, 3, 2), c.lightened(0.18))
	elif shape == "lamellar":
		# Sleeveless overlapping plate vest and separate shoulder lames.
		_poly(cv, [Vector2(9, 5), Vector2(13, 6), Vector2(19, 6), Vector2(23, 5), Vector2(25, 11), Vector2(23, 15), Vector2(24, 29), Vector2(8, 29), Vector2(9, 15), Vector2(7, 11)], LEATHER)
		for row: int in range(5):
			var y: int = 9 + row * 4
			for col: int in range(4):
				var x: int = 9 + col * 4
				_poly(cv, [Vector2(x, y), Vector2(x + 3, y), Vector2(x + 3, y + 3), Vector2(x + 1, y + 4), Vector2(x, y + 3)], low, false)
				_line(cv, Vector2(x, y), Vector2(x + 2, y), hi)
				cv.dot(Vector2(x + 1, y + 1), c)
		_poly(cv, [Vector2(8, 5), Vector2(11, 6), Vector2(10, 12), Vector2(4, 12), Vector2(5, 8)], c)
		_poly(cv, [Vector2(21, 6), Vector2(24, 5), Vector2(27, 8), Vector2(28, 12), Vector2(22, 12)], low)
		_line(cv, Vector2(5, 9), Vector2(9, 7), hi)
		cv.rect(Rect2(10, 24, 12, 2), LEATHER)
		cv.rect(Rect2(14, 24, 3, 2), c)
	elif shape == "scrap":
		_poly(cv, [Vector2(9, 5), Vector2(14, 7), Vector2(19, 6), Vector2(23, 4), Vector2(28, 9), Vector2(26, 15), Vector2(23, 13), Vector2(25, 28), Vector2(18, 30), Vector2(7, 28), Vector2(9, 13), Vector2(5, 16), Vector2(3, 11)], LEATHER)
		for tile: Array in [[Vector2(9, 10), Vector2(15, 9), Vector2(16, 15), Vector2(8, 16)], [Vector2(17, 9), Vector2(23, 8), Vector2(23, 16), Vector2(18, 17)], [Vector2(8, 19), Vector2(14, 17), Vector2(15, 25), Vector2(8, 27)], [Vector2(17, 19), Vector2(23, 18), Vector2(24, 27), Vector2(17, 28)]]:
			_poly(cv, tile, c)
			_line(cv, tile[0] + Vector2(1, 0), tile[1] - Vector2(1, 0), hi)
			cv.dot(tile[0] + Vector2(1, 1), low)
		_bar(cv, Vector2(9, 8), Vector2(22, 25), 0.6, WOOD_DARK, false)
	elif shape == "mail":
		_poly(cv, [Vector2(9, 5), Vector2(13, 7), Vector2(19, 7), Vector2(23, 5), Vector2(29, 10), Vector2(27, 17), Vector2(23, 15), Vector2(24, 28), Vector2(20, 30), Vector2(12, 30), Vector2(8, 28), Vector2(9, 15), Vector2(5, 17), Vector2(3, 10)], c)
		_poly(cv, [Vector2(22, 9), Vector2(27, 11), Vector2(26, 15), Vector2(22, 13), Vector2(23, 27), Vector2(20, 29), Vector2(20, 12)], low, false)
		_mail_links(cv, c, Rect2(4, 8, 24, 22))
		_poly(cv, [Vector2(12, 5), Vector2(20, 5), Vector2(19, 9), Vector2(16, 11), Vector2(13, 9)], INK, false)
		_line(cv, Vector2(12, 6), Vector2(14, 9), hi)
		cv.rect(Rect2(9, 22, 14, 2), LEATHER)
		cv.rect(Rect2(15, 22, 3, 2), c.lightened(0.18))
	else:
		var padded: bool = shape == "gambeson"
		_poly(cv, [Vector2(9, 5), Vector2(13, 6), Vector2(19, 6), Vector2(23, 5), Vector2(29, 10), Vector2(27, 17 if padded else 14), Vector2(23, 14), Vector2(25, 29), Vector2(18, 29), Vector2(16, 27), Vector2(14, 29), Vector2(7, 29), Vector2(9, 14), Vector2(5, 17 if padded else 14), Vector2(3, 10)], c)
		_poly(cv, [Vector2(20, 8), Vector2(24, 11), Vector2(22, 14), Vector2(24, 28), Vector2(20, 28), Vector2(18, 12)], low, false)
		_poly(cv, [Vector2(13, 5), Vector2(19, 5), Vector2(18, 9), Vector2(16, 11), Vector2(14, 9)], INK, false)
		_line(cv, Vector2(12, 6), Vector2(15, 11), hi)
		_line(cv, Vector2(15, 11), Vector2(19, 6), hi)
		if padded:
			for x: int in [10, 14, 18, 22]:
				_line(cv, Vector2(x, 12), Vector2(x, 27), low)
			for y: int in [15, 20, 25]:
				_line(cv, Vector2(10, y), Vector2(22, y), c.darkened(0.18))
			_line(cv, Vector2(6, 11), Vector2(5, 15), hi)
		else:
			_line(cv, Vector2(11, 14), Vector2(10, 27), hi)
			_line(cv, Vector2(16, 15), Vector2(16, 25), low)
		cv.rect(Rect2(9, 21, 14, 2), LEATHER)
		cv.rect(Rect2(15, 21, 3, 2), THREAD)

static func _clothes(cv: PixelCanvas, shape: String, c: Color, hi: Color, low: Color) -> void:
	match shape:
		"greaves":
			for offset: int in [0, 14]:
				_poly(cv, [Vector2(5 + offset, 5), Vector2(12 + offset, 5), Vector2(14 + offset, 9), Vector2(12 + offset, 16), Vector2(13 + offset, 25), Vector2(9 + offset, 29), Vector2(5 + offset, 25), Vector2(6 + offset, 16), Vector2(4 + offset, 9)], c)
				_poly(cv, [Vector2(9 + offset, 7), Vector2(12 + offset, 10), Vector2(10 + offset, 16), Vector2(12 + offset, 24), Vector2(9 + offset, 27)], low, false)
				_line(cv, Vector2(8 + offset, 8), Vector2(8 + offset, 25), hi)
				_line(cv, Vector2(5 + offset, 12), Vector2(12 + offset, 12), low)
				_line(cv, Vector2(6 + offset, 22), Vector2(11 + offset, 22), low)
		"bracers":
			for offset: int in [0, 14]:
				_poly(cv, [Vector2(7 + offset, 7), Vector2(14 + offset, 9), Vector2(10 + offset, 27), Vector2(3 + offset, 25)], c)
				_poly(cv, [Vector2(11 + offset, 10), Vector2(13 + offset, 10), Vector2(9 + offset, 26), Vector2(7 + offset, 25)], low, false)
				_line(cv, Vector2(7 + offset, 9), Vector2(4 + offset, 24), hi)
				for y: int in [12, 22]:
					_line(cv, Vector2(6 + offset - (2 if y == 22 else 0), y), Vector2(12 + offset - (2 if y == 22 else 0), y + 1), LEATHER)
					cv.dot(Vector2(9 + offset - (2 if y == 22 else 0), y), THREAD)
		"shoes":
			# Two boots in side view, with cuff, heel and a longer toe.
			_poly(cv, [Vector2(15, 5), Vector2(22, 5), Vector2(22, 17), Vector2(28, 20), Vector2(28, 23), Vector2(14, 23), Vector2(13, 20)], low)
			_poly(cv, [Vector2(6, 10), Vector2(14, 10), Vector2(14, 21), Vector2(22, 25), Vector2(23, 28), Vector2(5, 28), Vector2(4, 24)], c)
			cv.rect(Rect2(5, 27, 18, 2), low)
			cv.rect(Rect2(6, 11, 8, 2), low)
			_line(cv, Vector2(7, 14), Vector2(6, 23), hi)
			_line(cv, Vector2(15, 24), Vector2(20, 26), hi)
			for y: int in [15, 18, 21]:
				_line(cv, Vector2(11, y), Vector2(14, y + 1), THREAD)
		"trousers":
			_poly(cv, [Vector2(8, 4), Vector2(24, 4), Vector2(25, 12), Vector2(24, 28), Vector2(18, 28), Vector2(16, 14), Vector2(14, 28), Vector2(8, 28), Vector2(7, 12)], c)
			_poly(cv, [Vector2(19, 8), Vector2(24, 8), Vector2(23, 27), Vector2(21, 27)], low, false)
			cv.rect(Rect2(8, 5, 16, 2), low)
			_line(cv, Vector2(10, 9), Vector2(10, 26), hi)
			_line(cv, Vector2(16, 8), Vector2(16, 12), low)
			_line(cv, Vector2(8, 26), Vector2(13, 26), low)
			_line(cv, Vector2(19, 26), Vector2(23, 26), low)

static func _goods(cv: PixelCanvas, shape: String, key: String, c: Color, hi: Color, low: Color) -> void:
	match shape:
		"loaf":
			if key == "#grain":
				_sack(cv, c)
				for p: Vector2 in [Vector2(12, 17), Vector2(17, 16), Vector2(21, 19), Vector2(15, 21), Vector2(18, 24)]:
					_bar(cv, p, p + Vector2(1, 1), 0.7, c.lightened(0.28), false)
			else:
				_poly(cv, [Vector2(4, 17), Vector2(7, 12), Vector2(12, 10), Vector2(23, 10), Vector2(27, 13), Vector2(29, 19), Vector2(26, 25), Vector2(7, 25), Vector2(3, 21)], c)
				_poly(cv, [Vector2(4, 21), Vector2(28, 21), Vector2(26, 24), Vector2(7, 24)], low, false)
				for x: int in [10, 16, 22]:
					_line(cv, Vector2(x, 13), Vector2(x - 3, 18), low)
					_line(cv, Vector2(x + 1, 13), Vector2(x - 2, 18), hi)
		"mug":
			_poly(cv, [Vector2(22, 11), Vector2(28, 11), Vector2(30, 14), Vector2(29, 22), Vector2(24, 25), Vector2(22, 22), Vector2(26, 21), Vector2(27, 15), Vector2(23, 15)], WOOD)
			_poly(cv, [Vector2(7, 8), Vector2(23, 8), Vector2(24, 27), Vector2(20, 29), Vector2(10, 29), Vector2(7, 27)], WOOD)
			for x: int in [10, 14, 19]:
				_line(cv, Vector2(x, 12), Vector2(x + 1, 27), WOOD_DARK)
			cv.rect(Rect2(8, 14, 15, 2), c.darkened(0.35))
			cv.rect(Rect2(8, 24, 15, 2), c.darkened(0.35))
			_oval(cv, Vector2(15, 9), 8, 2.8, Color("#e7dec6"))
			_oval(cv, Vector2(16, 9), 5, 1.2, c, false)
			cv.dot(Vector2(10, 8), Color("#fff6df"))
		"jug":
			_poly(cv, [Vector2(20, 9), Vector2(26, 10), Vector2(28, 14), Vector2(27, 19), Vector2(23, 21), Vector2(23, 18), Vector2(25, 16), Vector2(24, 13), Vector2(20, 12)], low)
			_poly(cv, [Vector2(12, 5), Vector2(19, 5), Vector2(19, 11), Vector2(24, 16), Vector2(25, 23), Vector2(22, 28), Vector2(10, 28), Vector2(6, 24), Vector2(7, 17), Vector2(12, 11)], c)
			_poly(cv, [Vector2(20, 15), Vector2(23, 18), Vector2(24, 23), Vector2(21, 27), Vector2(17, 27), Vector2(20, 23)], low, false)
			_line(cv, Vector2(10, 17), Vector2(9, 23), hi)
			cv.rect(Rect2(12, 4, 7, 2), WOOD)
			_line(cv, Vector2(12, 7), Vector2(18, 7), low)
			if key == "#remedy":
				_poly(cv, [Vector2(12, 17), Vector2(18, 17), Vector2(20, 20), Vector2(18, 24), Vector2(12, 24), Vector2(11, 20)], Color("#e4d4ad"), false)
				_line(cv, Vector2(13, 22), Vector2(17, 18), c.darkened(0.25))
		"coins":
			for layer: int in range(3):
				var y: int = 25 - layer * 4
				_oval(cv, Vector2(12, y), 8.0, 3.0, low)
				_oval(cv, Vector2(12, y - 1), 8.0, 2.6, c)
				_line(cv, Vector2(7, y - 2), Vector2(12, y - 3), hi)
			_oval(cv, Vector2(23, 21), 5.2, 6.2, low)
			_oval(cv, Vector2(22, 20), 4.3, 5.0, c)
			_poly(cv, [Vector2(22, 16), Vector2(24, 19), Vector2(22, 23), Vector2(20, 20)], hi, false)
		"ham":
			_bar(cv, Vector2(21, 12), Vector2(27, 6), 1.7, Color("#e5d9bd"))
			_oval(cv, Vector2(27, 5), 2, 2, Color("#f1e7cc"))
			_oval(cv, Vector2(29, 7), 1.7, 1.7, Color("#f1e7cc"))
			_poly(cv, [Vector2(11, 9), Vector2(19, 10), Vector2(23, 15), Vector2(23, 21), Vector2(18, 27), Vector2(10, 28), Vector2(5, 24), Vector2(4, 16)], low)
			_oval(cv, Vector2(12, 19), 7.4, 8.5, c)
			_oval(cv, Vector2(12, 19), 5.8, 6.7, c.lightened(0.12), false)
			_oval(cv, Vector2(12, 19), 2, 2, Color("#e8c5aa"), false)
			_line(cv, Vector2(7, 17), Vector2(9, 13), hi)
		"apple":
			_poly(cv, [Vector2(8, 11), Vector2(12, 10), Vector2(16, 12), Vector2(20, 10), Vector2(25, 12), Vector2(27, 18), Vector2(24, 25), Vector2(20, 28), Vector2(16, 27), Vector2(12, 28), Vector2(7, 24), Vector2(5, 18)], c)
			_poly(cv, [Vector2(23, 13), Vector2(26, 18), Vector2(23, 24), Vector2(20, 27), Vector2(16, 26), Vector2(20, 23)], low, false)
			_line(cv, Vector2(8, 17), Vector2(10, 13), hi)
			_bar(cv, Vector2(16, 11), Vector2(17, 6), 0.65, WOOD)
			_poly(cv, [Vector2(17, 7), Vector2(22, 4), Vector2(25, 5), Vector2(22, 8)], Color("#57764b"))
		"ingot":
			_poly(cv, [Vector2(5, 20), Vector2(8, 11), Vector2(24, 8), Vector2(29, 17), Vector2(27, 24), Vector2(8, 27)], low)
			_poly(cv, [Vector2(8, 11), Vector2(24, 8), Vector2(27, 16), Vector2(10, 19), Vector2(5, 20)], hi, false)
			_poly(cv, [Vector2(10, 19), Vector2(27, 16), Vector2(26, 23), Vector2(9, 26)], c, false)
			_line(cv, Vector2(11, 20), Vector2(25, 18), c.lightened(0.25))
			_line(cv, Vector2(8, 12), Vector2(22, 10), c)
		"ore":
			_poly(cv, [Vector2(4, 20), Vector2(7, 13), Vector2(12, 11), Vector2(18, 15), Vector2(18, 24), Vector2(9, 28)], Color("#766d68"))
			_poly(cv, [Vector2(14, 14), Vector2(15, 7), Vector2(21, 5), Vector2(26, 10), Vector2(24, 19)], Color("#8b8276"))
			_poly(cv, [Vector2(16, 22), Vector2(20, 16), Vector2(27, 17), Vector2(29, 25), Vector2(24, 28)], Color("#655e5e"))
			for p: Vector2 in [Vector2(8, 17), Vector2(12, 20), Vector2(20, 9), Vector2(23, 12), Vector2(22, 23), Vector2(25, 20)]:
				_poly(cv, [p, p + Vector2(2, -1), p + Vector2(3, 1), p + Vector2(1, 2)], c, false)
				cv.dot(p, hi)
		"scrap_pile":
			_poly(cv, [Vector2(5, 19), Vector2(13, 16), Vector2(18, 23), Vector2(9, 27)], low)
			_poly(cv, [Vector2(14, 10), Vector2(24, 7), Vector2(25, 13), Vector2(20, 13), Vector2(19, 18), Vector2(12, 17)], c)
			_poly(cv, [Vector2(17, 24), Vector2(23, 17), Vector2(29, 22), Vector2(26, 27)], c)
			_line(cv, Vector2(15, 11), Vector2(23, 8), hi)
			_line(cv, Vector2(19, 24), Vector2(23, 19), hi)
		"heads":
			for i: int in range(3):
				var x: int = 5 + i * 8
				_poly(cv, [Vector2(x, 23), Vector2(x + 2, 12 - i), Vector2(x + 6, 6 - i), Vector2(x + 7, 17), Vector2(x + 4, 24), Vector2(x + 4, 28), Vector2(x + 1, 28)], c)
				_line(cv, Vector2(x + 2, 22), Vector2(x + 5, 9 - i), hi)
		"arrow":
			_shaft(cv, Vector2(5, 27), Vector2(25, 7))
			_poly(cv, [Vector2(3, 23), Vector2(8, 20), Vector2(8, 24), Vector2(4, 28)], Color("#d9d5c8"))
			_poly(cv, [Vector2(6, 28), Vector2(10, 24), Vector2(12, 24), Vector2(9, 29)], Color("#b8b6ad"))
			_poly(cv, [Vector2(21, 8), Vector2(29, 3), Vector2(26, 11), Vector2(24, 9)], c)
			_line(cv, Vector2(23, 8), Vector2(28, 4), hi)
		"logs":
			for i: int in range(3):
				var y: int = 24 - i * 7
				_bar(cv, Vector2(7, y), Vector2(25, y - 4), 3.0, c)
				_line(cv, Vector2(9, y - 2), Vector2(24, y - 5), low)
				_oval(cv, Vector2(7, y), 3.2, 3.0, c.lightened(0.20))
				_oval(cv, Vector2(7, y), 1.7, 1.6, c.darkened(0.15), false)
				cv.dot(Vector2(7, y), c.lightened(0.15))
			_bar(cv, Vector2(15, 8), Vector2(19, 25), 0.6, LEATHER, false)
		"bolt":
			_poly(cv, [Vector2(8, 7), Vector2(24, 7), Vector2(27, 11), Vector2(25, 28), Vector2(5, 28), Vector2(7, 13)], c)
			_poly(cv, [Vector2(21, 12), Vector2(26, 11), Vector2(24, 27), Vector2(19, 27)], low, false)
			_oval(cv, Vector2(16, 9), 9.3, 4.0, hi)
			_oval(cv, Vector2(16, 9), 6.4, 2.3, low, false)
			_oval(cv, Vector2(16, 9), 3.7, 1.2, c, false)
			_line(cv, Vector2(9, 14), Vector2(8, 25), hi)
			_line(cv, Vector2(16, 14), Vector2(15, 26), low)
			cv.rect(Rect2(6, 22, 19, 2), c.darkened(0.24))
		"hide":
			_poly(cv, [Vector2(4, 7), Vector2(8, 5), Vector2(12, 10), Vector2(20, 10), Vector2(24, 5), Vector2(28, 7), Vector2(25, 15), Vector2(26, 22), Vector2(29, 27), Vector2(23, 29), Vector2(20, 25), Vector2(12, 25), Vector2(9, 29), Vector2(3, 27), Vector2(6, 21), Vector2(7, 15)], c)
			_poly(cv, [Vector2(13, 12), Vector2(20, 12), Vector2(23, 18), Vector2(20, 23), Vector2(12, 23), Vector2(9, 18)], c.lightened(0.12), false)
			_line(cv, Vector2(8, 8), Vector2(10, 11), hi)
			_line(cv, Vector2(21, 23), Vector2(24, 27), low)
		"gem":
			_poly(cv, [Vector2(10, 7), Vector2(22, 7), Vector2(28, 14), Vector2(16, 29), Vector2(4, 14)], c)
			_poly(cv, [Vector2(10, 8), Vector2(14, 13), Vector2(5, 14)], hi, false)
			_poly(cv, [Vector2(10, 8), Vector2(22, 8), Vector2(19, 13), Vector2(14, 13)], c.lightened(0.35), false)
			_poly(cv, [Vector2(22, 8), Vector2(27, 14), Vector2(19, 13)], c.darkened(0.15), false)
			_poly(cv, [Vector2(5, 15), Vector2(14, 14), Vector2(16, 28)], c.lightened(0.13), false)
			_poly(cv, [Vector2(19, 14), Vector2(27, 15), Vector2(16, 28)], low, false)
			_line(cv, Vector2(14, 14), Vector2(16, 26), hi)
		_:
			_sack(cv, c)

static func _sack(cv: PixelCanvas, c: Color) -> void:
	_poly(cv, [Vector2(10, 5), Vector2(13, 6), Vector2(16, 5), Vector2(19, 6), Vector2(22, 5), Vector2(20, 11), Vector2(25, 17), Vector2(27, 24), Vector2(24, 28), Vector2(8, 28), Vector2(5, 24), Vector2(7, 17), Vector2(12, 11)], c)
	_poly(cv, [Vector2(19, 13), Vector2(24, 18), Vector2(26, 24), Vector2(23, 27), Vector2(19, 27), Vector2(21, 22)], c.darkened(0.25), false)
	_line(cv, Vector2(10, 18), Vector2(8, 24), c.lightened(0.23))
	_line(cv, Vector2(13, 15), Vector2(13, 23), c.darkened(0.17))
	_bar(cv, Vector2(11, 11), Vector2(21, 11), 0.7, WOOD_DARK, false)
	_line(cv, Vector2(16, 12), Vector2(19, 16), THREAD)
