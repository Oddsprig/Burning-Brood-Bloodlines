class_name HouseBanner
extends Control
## House heraldry: a heater shield with a shaded field, a gold bordure, and the house charge drawn with an ink
## outline and a highlight, so it reads at a glance at any size. Pure drawing; no records change.
const DEFAULT_STYLE := {"emblem":"crown","primary_color":"#2F6B4F","secondary_color":"#E4C47D"}
var customization: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(56,64)
	mouse_filter = MOUSE_FILTER_IGNORE

func set_style(value: Dictionary) -> void:
	set_customization(value)

func set_customization(value: Dictionary) -> void:
	customization = value.duplicate(true)
	queue_redraw()

const SHIELD := [Vector2(8,6),Vector2(92,6),Vector2(92,62),Vector2(84,84),Vector2(68,102),Vector2(50,114),Vector2(32,102),Vector2(16,84),Vector2(8,62)]

func _charge(kind: String) -> Array:
	# Each entry: [kind, data] with kind "poly" (points), "rect" (Rect2), "line" ([a, b, width]).
	match kind:
		"crown":
			return [["poly", [Vector2(22,44),Vector2(34,56),Vector2(50,30),Vector2(66,56),Vector2(78,44),Vector2(71,78),Vector2(29,78)]]]
		"tower":
			return [["rect", Rect2(31,36,38,46)], ["rect", Rect2(27,28,11,14)], ["rect", Rect2(44.5,28,11,14)], ["rect", Rect2(62,28,11,14)]]
		"wolf":
			return [["poly", [Vector2(25,28),Vector2(42,40),Vector2(58,40),Vector2(75,28),Vector2(69,66),Vector2(50,90),Vector2(31,66)]]]
		"stag":
			return [["poly", [Vector2(39,50),Vector2(61,50),Vector2(58,76),Vector2(50,90),Vector2(42,76)]],
				["line", [Vector2(41,54),Vector2(33,38),5.0]], ["line", [Vector2(33,38),Vector2(32,24),5.0]], ["line", [Vector2(35,42),Vector2(21,33),5.0]],
				["line", [Vector2(59,54),Vector2(67,38),5.0]], ["line", [Vector2(67,38),Vector2(68,24),5.0]], ["line", [Vector2(65,42),Vector2(79,33),5.0]]]
		"leaf":
			return [["poly", [Vector2(50,26),Vector2(73,42),Vector2(78,64),Vector2(64,81),Vector2(50,88),Vector2(36,81),Vector2(22,64),Vector2(27,42)]]]
		"hammer":
			return [["rect", Rect2(44,50,12,42)], ["rect", Rect2(25,30,50,22)]]
		"flame":
			return [["poly", [Vector2(49,22),Vector2(64,46),Vector2(70,35),Vector2(79,66),Vector2(68,84),Vector2(49,92),Vector2(29,84),Vector2(21,64),Vector2(37,40),Vector2(36,60),Vector2(47,47)]]]
	var points: Array = []
	for i in 10:
		var angle: float = -PI/2.0+float(i)*PI/5.0
		points.append(Vector2(50,60)+Vector2(cos(angle),sin(angle))*(31.0 if i%2 == 0 else 13.0))
	return [["poly", points]]

func _draw() -> void:
	var primary: Color = Color(String(customization.get("primary_color","#2f6b4f")))
	var secondary: Color = Color(String(customization.get("secondary_color","#e4c47d")))
	var scale: float = minf(size.x/100.0,size.y/120.0)
	var origin: Vector2 = (size-Vector2(100,120)*scale)*0.5
	draw_set_transform(origin,0,Vector2.ONE*scale)
	var shield := PackedVector2Array(SHIELD)
	var shadow := PackedVector2Array()
	for p in shield: shadow.append(p + Vector2(2.5, 3.5))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.45))
	var colors := PackedColorArray()
	for p in shield: colors.append(primary.lightened(0.22 * (1.0 - p.y / 114.0)).darkened(0.25 * (p.y / 114.0)))
	draw_polygon(shield, colors)
	var ink: Color = primary.darkened(0.7)
	for part: Array in _charge(String(customization.get("emblem","crown"))):
		match str(part[0]):
			"poly":
				var pts := PackedVector2Array(part[1])
				var ring := pts.duplicate(); ring.append(pts[0])
				draw_polyline(ring, ink, 5.0, true)
				draw_colored_polygon(pts, secondary)
				var hl := PackedVector2Array()
				for i in mini(3, pts.size()): hl.append(pts[i] + Vector2(1.2, 1.2))
				draw_polyline(hl, secondary.lightened(0.45), 1.6, true)
			"rect":
				var r: Rect2 = part[1]
				draw_rect(r.grow(2.0), ink)
				draw_rect(r, secondary)
				draw_line(r.position + Vector2(1, 1), Vector2(r.end.x - 1, r.position.y + 1), secondary.lightened(0.45), 1.5)
			"line":
				var d: Array = part[1]
				draw_line(d[0], d[1], ink, float(d[2]) + 3.0, true)
				draw_line(d[0], d[1], secondary, float(d[2]), true)
	if String(customization.get("emblem","crown")) == "tower": draw_rect(Rect2(45,62,10,20), primary.darkened(0.3))
	draw_colored_polygon(PackedVector2Array([Vector2(12,10),Vector2(46,10),Vector2(12,52)]), Color(1, 1, 1, 0.07))
	var ring := shield.duplicate(); ring.append(shield[0])
	draw_polyline(ring, Color("3a2810"), 8.0, true)
	draw_polyline(ring, Color("d9a441"), 5.0, true)
	draw_polyline(ring, Color("f6d98a"), 1.4, true)
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE)
