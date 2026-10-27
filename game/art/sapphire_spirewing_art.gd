class_name SapphireSpirewingArt
extends RefCounted
## GDScript port of previews/code_dragon_v2/draw_dragon.py.
## Six 128x96 sources, painted once in memory; no imported bitmap or RNG.
const SIZE := Vector2i(128, 96)
const FRAME_COUNT := 6
const OUTLINE := Color("0a1028")
const SKIN := [Color("13214f"), Color("1c3480"), Color("2850b0"), Color("3a72d4"), Color("5d97ea"), Color("a2cdf7")]
const SKIN_FAR := [Color("0e1838"), Color("142659"), Color("1c3a80"), Color("2a56a8"), Color("3f72c4"), Color("6d9ad8")]
const BELLY := [Color("3d5d96"), Color("6d93c8"), Color("a4c6ea"), Color("d8ecff")]
const BELLY_FAR := [Color("2c4674"), Color("4f72a6"), Color("7a9ccc"), Color("a8c4e4")]
const MEMBRANE := [Color("161a44"), Color("232a68"), Color("323f92"), Color("4558b4"), Color("6a80d4")]
const MEMBRANE_FAR := [Color("0f1232"), Color("181d4c"), Color("222c6a"), Color("30408c"), Color("4a5ca8")]
const GEM := [Color("0b1660"), Color("1838b8"), Color("3274f0"), Color("8cc8ff"), Color.WHITE]
const WING_POSES := [
	[Vector2(-2, -14), Vector2(4, -30), Vector2(-10, -45), Vector2(-34, -40), Vector2(-46, -18)],
	[Vector2(-4, -12), Vector2(-2, -27), Vector2(-22, -44), Vector2(-44, -32), Vector2(-48, -10)],
	[Vector2(-6, -8), Vector2(-12, -16), Vector2(-46, -26), Vector2(-56, -8), Vector2(-44, 4)],
	[Vector2(-4, 4), Vector2(-6, 13), Vector2(-24, 34), Vector2(-40, 30), Vector2(-42, 14)],
	[Vector2(-6, -2), Vector2(-12, 0), Vector2(-42, 6), Vector2(-50, 18), Vector2(-40, 12)],
	[Vector2(-3, -10), Vector2(-2, -22), Vector2(-20, -38), Vector2(-42, -28), Vector2(-46, -8)]
]
const BOB := [-1, 0, 2, 4, 2, 0]
const SEAT_PITCH := [0.04, 0.0, -0.05, -0.08, -0.035, 0.02]
static var _frames: Dictionary = {}

class Layer extends RefCounted:
	var height := PackedFloat32Array()
	var normal := PackedVector3Array()
	var material := PackedByteArray()
	var extra := PackedFloat32Array()
	var far := false
	var is_wing := false

	func _init(distant: bool = false) -> void:
		far = distant
		height.resize(128 * 96); height.fill(-1.0)
		normal.resize(128 * 96); normal.fill(Vector3(0, 0, 1))
		material.resize(128 * 96)
		extra.resize(128 * 96)

	func capsule(a: Vector2, b: Vector2, ra: float, rb: float, mat: int = 1) -> void:
		var radius := maxf(ra, rb)
		var low := Vector2i((a.min(b) - Vector2.ONE * radius).floor()).max(Vector2i.ZERO)
		var high := Vector2i((a.max(b) + Vector2.ONE * radius).ceil()).min(Vector2i(128, 96))
		var axis := b - a
		for y in range(low.y, high.y):
			for x in range(low.x, high.x):
				var point := Vector2(x + 0.5, y + 0.5)
				var t := clampf((point - a).dot(axis) / maxf(axis.length_squared(), 0.000001), 0, 1)
				var delta := point - a.lerp(b, t)
				var r := lerpf(ra, rb, t)
				if delta.length_squared() >= r * r: continue
				var h := sqrt(maxf(0, 1 - delta.length_squared() / (r * r)))
				var index := y * 128 + x
				if h * r <= height[index]: continue
				height[index] = h * r
				normal[index] = Vector3(delta.x / r, delta.y / r, h).normalized()
				material[index] = mat

	func chain(points: PackedVector2Array, first: float, last: float, mat: int = 1, exponent: float = 1.0) -> void:
		var count := points.size() - 1
		for i in count:
			capsule(points[i], points[i + 1], lerpf(first, last, pow(float(i) / count, exponent)), lerpf(first, last, pow(float(i + 1) / count, exponent)), mat)

	func polygon(points: PackedVector2Array, mat: int) -> void:
		# Use the game's pixel-centre polygon rasterizer for deterministic ownership.
		var cv := PixelCanvas.new(128, 96)
		cv.poly(points, Color.WHITE)
		for i in material.size():
			if cv.buf[i].a == 0 or height[i] >= 0: continue
			height[i] = 0.01; material[i] = mat

static func frame_index(pose: String, progress: float) -> int:
	if pose in ["rest", "dead", "prone"]: return 1
	return clampi(floori(clampf(progress, 0, 1) * FRAME_COUNT), 0, FRAME_COUNT - 1)

static func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / steps
		points.append(a * pow(1 - t, 3) + b * 3 * pow(1 - t, 2) * t + c * 3 * (1 - t) * t * t + d * t * t * t)
	return points

static func _scallop(a: Vector2, b: Vector2, wrist: Vector2, k: float = 0.28) -> PackedVector2Array:
	var points := PackedVector2Array()
	var control := ((a + b) * 0.5).lerp(wrist, k)
	for i in 9:
		var t := float(i) / 8
		points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return points

static func _wing_points(shoulder: Vector2, pose: Array) -> PackedVector2Array:
	var wrist: Vector2 = shoulder + pose[1]
	var first: Vector2 = shoulder + pose[2]
	var middle: Vector2 = shoulder + pose[3]
	var last: Vector2 = shoulder + pose[4]
	var flank := shoulder + Vector2(-18, 8)
	var points := PackedVector2Array([shoulder, shoulder + pose[0], wrist, first])
	points.append_array(_scallop(first, middle, wrist).slice(1))
	points.append_array(_scallop(middle, last, wrist).slice(1))
	points.append_array(_scallop(last, flank, wrist, 0.18).slice(1))
	return points

static func _far_pose(pose: Array) -> Array:
	var out: Array = []
	for point: Vector2 in pose: out.append(point * Vector2(0.86, 0.9) - Vector2(2, 2))
	return out

static func _wing(layer: Layer, shoulder: Vector2, pose: Array) -> void:
	layer.is_wing = true
	var elbow: Vector2 = shoulder + pose[0]
	var wrist: Vector2 = shoulder + pose[1]
	var fingers := [shoulder + pose[2], shoulder + pose[3], shoulder + pose[4]]
	layer.polygon(_wing_points(shoulder, pose), 4)
	var bones := [[wrist, fingers[0]], [wrist, fingers[1]], [wrist, fingers[2]], [shoulder, elbow], [elbow, wrist]]
	for y in SIZE.y:
		for x in SIZE.x:
			var index := y * SIZE.x + x
			if layer.material[index] != 4: continue
			var point := Vector2(x + 0.5, y + 0.5)
			var distance := 99.0
			for bone: Array in bones:
				distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, bone[0], bone[1])))
			layer.extra[index] = clampf(distance / 7, 0, 1) * 0.55 + clampf(point.distance_to(wrist) / 40, 0, 1) * 0.35 + (0.08 if point.y < shoulder.y else 0.0)
	var edge := _scallop(fingers[0], fingers[1], wrist)
	edge.append_array(_scallop(fingers[1], fingers[2], wrist))
	edge.append_array(_scallop(fingers[2], shoulder + Vector2(-18, 8), wrist, 0.18))
	for point: Vector2 in edge:
		var at := Vector2i(point)
		if Rect2i(Vector2i.ZERO, SIZE).has_point(at) and layer.material[at.y * SIZE.x + at.x] == 4:
			layer.material[at.y * SIZE.x + at.x] = 5
	layer.capsule(shoulder, elbow, 3.2, 2.4)
	layer.capsule(elbow, wrist, 2.4, 1.7)
	for i in 3: layer.capsule(wrist, fingers[i], 1.1, [0.54, 0.48, 0.42][i])
	layer.capsule(wrist, wrist + Vector2(2.5, -2.5), 1.3, 0.5, 3)

static func _leg(layer: Layer, hip: Vector2, bend: float, lift: float) -> void:
	var knee := hip + Vector2(8, 9 + bend)
	var ankle := hip + Vector2(2, 20 + lift)
	var toe := hip + Vector2(10, 23.5 + lift)
	layer.capsule(hip, knee, 7, 4.2)
	layer.capsule(knee, ankle, 3.6, 2.4)
	layer.capsule(ankle, toe, 2.4, 1.8)
	layer.capsule(ankle + Vector2(-1, 1), ankle + Vector2(-4, 3.5), 1.6, 0.8)
	for tx: float in [0.0, -3.0]:
		var tip := toe + Vector2(1 + tx, -0.5)
		layer.capsule(tip, tip + Vector2(2.4, 1.6), 1.1, 0.4, 3)
	layer.capsule(ankle + Vector2(-4, 3.5), ankle + Vector2(-6, 4.5), 0.9, 0.3, 3)

static func _shade(layer: Layer) -> PackedColorArray:
	var output := PackedColorArray()
	output.resize(SIZE.x * SIZE.y)
	var light := Vector3(-0.60, -0.75, 0.35).normalized()
	var skin: Array = SKIN_FAR if layer.far else SKIN
	var belly: Array = BELLY_FAR if layer.far else BELLY
	var membrane: Array = MEMBRANE_FAR if layer.far else MEMBRANE
	for y in SIZE.y:
		for x in SIZE.x:
			var i := y * SIZE.x + x
			var mat := layer.material[i]
			if mat == 0: continue
			var lambert := layer.normal[i].dot(light)
			var dither := (0.06 if (x + y) % 2 else -0.06) if (floori(float(x) / 2) + y) % 3 == 0 else 0.0
			match mat:
				1, 2:
					if mat == 2 and layer.normal[i].y > 0.30:
						var index := clampi(int((lambert + dither + 0.20) * 3), 0, 3)
						if y % 3 == 0: index = maxi(0, index - 1)
						output[i] = belly[index]
					else: output[i] = skin[clampi(int((lambert + dither + 0.12) * 4.4), 0, 5)]
				3: output[i] = GEM[clampi(int((lambert + 0.1) * 3.4), 0, 3)]
				4: output[i] = membrane[clampi(int(layer.extra[i] * 4.2), 0, 3)]
				5: output[i] = membrane[4]
	return output

static func _composite(layers: Array) -> Image:
	var cv := PixelCanvas.new(SIZE.x, SIZE.y)
	for layer: Layer in layers:
		var colors := _shade(layer)
		for y in SIZE.y:
			for x in SIZE.x:
				var i := y * SIZE.x + x
				if layer.material[i] == 0: continue
				var rim := false
				for step: Vector2i in PixelCanvas.N4:
					var at := Vector2i(x, y) + step
					if not Rect2i(Vector2i.ZERO, SIZE).has_point(at) or layer.material[at.y * SIZE.x + at.x] == 0: rim = true
				var dark: Color = SKIN_FAR[0] if layer.far else SKIN[0]
				cv.buf[i] = (OUTLINE if layer.is_wing else dark) if rim and cv.buf[i].a > 0 else colors[i]
	var solid := cv.buf.duplicate()
	for y in SIZE.y:
		for x in SIZE.x:
			if solid[y * SIZE.x + x].a > 0: continue
			for step: Vector2i in PixelCanvas.N4:
				var at := Vector2i(x, y) + step
				if Rect2i(Vector2i.ZERO, SIZE).has_point(at) and solid[at.y * SIZE.x + at.x].a > 0:
					cv.buf[y * SIZE.x + x] = OUTLINE
	return cv.to_image()

static func frame(index: int) -> Image:
	index = posmod(index, FRAME_COUNT)
	if _frames.has(index): return _frames[index]
	var pose: Array = WING_POSES[index]
	var shift := Vector2(0, -BOB[index])
	var shoulder := Vector2(68, 47) + shift
	var far_wing := Layer.new(true)
	var far_leg := Layer.new(true)
	var tail := Layer.new()
	var body := Layer.new()
	var near_leg := Layer.new()
	var near_wing := Layer.new()
	_wing(far_wing, shoulder + Vector2(-4, -2), _far_pose(pose))
	_leg(far_leg, Vector2(45, 59) + shift, 1, -shift.y)
	var sway := sin(float(index) / FRAME_COUNT * TAU) * 2
	var tail_points := _bezier(Vector2(46, 60) + shift, Vector2(30, 66) + shift, Vector2(12, 78 + sway), Vector2(6, 60 + sway), 30)
	tail.chain(tail_points, 8, 1.2, 2, 0.8)
	var tip := tail_points[-1]
	tail.polygon(PackedVector2Array([tip + Vector2(-1, 2), tip + Vector2(-4, -5), tip + Vector2(3, -3)]), 1)
	var torso := PackedVector2Array([Vector2(48, 58) + shift, Vector2(58, 55.5) + shift, Vector2(70, 51.5) + shift, Vector2(76, 49.5) + shift])
	var radii := [10.0, 10.4, 9.4, 8.2]
	for i in 3: body.capsule(torso[i], torso[i + 1], radii[i], radii[i + 1], 2)
	var neck := _bezier(Vector2(76, 50) + shift, Vector2(86, 46) + shift, Vector2(84, 30) + shift, Vector2(97, 24) + shift, 20)
	body.chain(neck, 8, 4.4, 2)
	var head := Vector2(100, 24) + shift
	body.capsule(head, head + Vector2(14, 3), 6, 2.6)
	body.capsule(head + Vector2(1, 4), head + Vector2(12, 6), 4, 1.7, 2)
	body.capsule(head + Vector2(-1, -2), head + Vector2(6, -3), 2.2, 1.6)
	for horn: Vector3 in [Vector3(0, 0, 1), Vector3(2, 1, 0.8)]:
		var points := _bezier(head + Vector2(-1 + horn.x, -4 + horn.y), head + Vector2(-6 + horn.x, -12 + horn.y), head + Vector2(-14 + horn.x * 2, -12 + horn.y), head + Vector2(-19 + horn.x * 3, -8 + horn.y), 14)
		body.chain(points, 2.4 * horn.z, 0.5, 3)
	body.polygon(PackedVector2Array([head + Vector2(-3, 2), head + Vector2(-9, 5), head + Vector2(-3, 5)]), 1)
	for t: float in [0.25, 0.45, 0.62, 0.78]:
		var i := int(t * 20)
		var angle := (neck[i + 1] - neck[i]).angle()
		var tangent := Vector2(cos(angle), sin(angle))
		var normal := Vector2(sin(angle), -cos(angle))
		var base := neck[i] + normal * lerpf(8, 4.4, float(i) / 20) * 0.8
		body.polygon(PackedVector2Array([base - tangent * 2, base + normal * 4 - tangent * 3, base + tangent * 1.5]), 1)
	for point: Vector2 in [Vector2(62, 45), Vector2(54, 47), Vector2(44, 52), Vector2(34, 58)]:
		body.polygon(PackedVector2Array([point + shift + Vector2(-2, 2), point + shift + Vector2(-3, -3), point + shift + Vector2(2, 1)]), 1)
	_leg(near_leg, Vector2(52, 61) + shift, 0, -shift.y)
	_wing(near_wing, shoulder, pose)
	var image := _composite([far_wing, far_leg, tail, body, near_leg, near_wing])
	var eye := Vector2i(head + Vector2(3, -1))
	image.set_pixelv(eye, Color("8ff6ff")); image.set_pixelv(eye + Vector2i(1, 0), Color("e8ffff"))
	for step: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]: image.set_pixelv(eye + step, OUTLINE)
	image.set_pixelv(Vector2i(head + Vector2(12, 1)), OUTLINE)
	for i in range(3, 12): image.set_pixelv(Vector2i(head + Vector2(i, 4)), OUTLINE)
	for x in [5, 8, 11]: image.set_pixelv(Vector2i(head + Vector2(x, 5)), Color("e4f2ff"))
	image.set_pixelv(Vector2i(head + Vector2(-8, -11)), GEM[4])
	image.set_pixelv(Vector2i(head + Vector2(-4, -9)), GEM[3])
	var output := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	output.blit_rect(image, Rect2i(0, 0, SIZE.x, SIZE.y - 3), Vector2i(0, 3))
	_frames[index] = output
	return output

static func _coordinates(points: PackedVector2Array) -> Array:
	var out: Array = []
	for point: Vector2 in points: out.append([point.x, point.y])
	return out

static func _region(owner: String, polygon: Array, start: Array, end: Array) -> Dictionary:
	return {"owner_part_id": owner, "polygons": [polygon], "anchor_start_px": start, "anchor_end_px": end}

static func metadata(index: int) -> Dictionary:
	index = posmod(index, FRAME_COUNT)
	var d: int = 3 - BOB[index]
	var head: Array = [[78, 0], [128, 0], [128, 37 + d], [90, 37 + d], [81, 39 + d]]
	var jaw: Array = [[99, 28 + d], [104, 28 + d], [117, 30 + d], [116, 35 + d], [98, 33 + d]]
	var neck: Array = [[70, 45 + d], [81, 39 + d], [90, 37 + d], [94, 48 + d], [80, 60 + d]]
	var regions := {
		"torso": _region("body", [[37, 44 + d], [78, 38 + d], [84, 62 + d], [42, 73 + d]], [48, 58 + d], [76, 50 + d]),
		"neck": _region("body", neck, [76, 50 + d], [86, 38 + d]),
		"head": _region("head", head, [86, 38 + d], [105, 24 + d]),
		"jaw": _region("jaw", jaw, [100, 29 + d], [114, 31 + d]),
		"tail": _region("body", [[0, 48], [44, 50 + d], [54, 70 + d], [10, 86], [0, 74]], [46, 60 + d], [6, 60 + d])
	}
	regions["neck"]["cut_line_px"] = [[81, 39 + d], [90, 37 + d], [128, 37 + d]]
	regions["neck"]["cut_point_px"] = [86, 38 + d]
	for side: String in ["l", "r"]:
		var distant := side == "l"
		var shoulder := Vector2(64, 45 + d) if distant else Vector2(68, 47 + d)
		var pose: Array = _far_pose(WING_POSES[index]) if distant else WING_POSES[index]
		var elbow: Vector2 = shoulder + pose[0]
		var wrist: Vector2 = shoulder + pose[1]
		var upper := PackedVector2Array([shoulder + Vector2(-5, -4), elbow + Vector2(-4, -4), wrist + Vector2(4, -3), wrist + Vector2(5, 4), shoulder + Vector2(4, 5)])
		regions["wing_upper_" + side] = _region("body", _coordinates(upper), [shoulder.x, shoulder.y], [wrist.x, wrist.y])
		regions["wing_lower_" + side] = _region("body", _coordinates(_wing_points(shoulder, pose)), [wrist.x, wrist.y], [shoulder.x + pose[2].x, shoulder.y + pose[2].y])
		var hip := Vector2(45, 59 + d) if distant else Vector2(52, 61 + d)
		var knee := hip + Vector2(8, 10 if distant else 9)
		var ankle := Vector2(hip.x + 2, 79 if distant else 81) + Vector2(0, 3)
		regions["leg_upper_" + side] = _region("body", [[hip.x - 7, hip.y - 7], [knee.x + 5, knee.y - 4], [knee.x + 5, knee.y + 6], [hip.x - 5, hip.y + 8]], [hip.x, hip.y], [knee.x, knee.y])
		regions["leg_lower_" + side] = _region("body", [[knee.x - 5, knee.y - 3], [knee.x + 5, knee.y], [ankle.x + 4, ankle.y + 2], [ankle.x - 4, ankle.y + 2]], [knee.x, knee.y], [ankle.x, ankle.y])
		regions["foot_" + side] = _region("body", [[ankle.x - 9, ankle.y - 3], [ankle.x + 13, ankle.y - 2], [ankle.x + 14, ankle.y + 9], [ankle.x - 9, ankle.y + 9]], [ankle.x, ankle.y], [ankle.x + 10, ankle.y + 4])
	return {"generator": "sapphire_spirewing", "frame": index, "painted": true, "source_path": "code:sapphire_spirewing/%d" % index,
		"image_size": [128, 96], "source_origin_px": [70, 49], "units_per_pixel": 0.48, "motion_scale": 1.0 / 12.0,
		"seat_px": [70, 46 + d], "seat_angle": SEAT_PITCH[index] * 0.5, "ground_y_px": 88, "neck_root_px": [78, 49 + d],
		"wing_roots_px": {"left": [64, 45 + d], "right": [68, 47 + d]}, "head_crop_px": [78, 10 + d, 42, 35],
		"parts": {
			"body": {"label": "Body, wingbeat, hind legs and tail", "parent": "", "polygons": [[[0, 0], [128, 0], [128, 96], [0, 96]]], "pivot_px": [70, 46 + d]},
			"head": {"label": "Head and upper neck", "parent": "body", "polygons": [head], "pivot_px": [86, 38 + d], "ownership_priority": 1},
			"jaw": {"label": "Lower jaw", "parent": "head", "polygons": [jaw], "pivot_px": [100, 29 + d], "ownership_priority": 2}},
		"anatomical_regions": regions, "gem_regions": [], "preserve_regions": [],
		"material_masks_px": {"horns": [[[79, 10 + d], [98, 10 + d], [102, 22 + d], [90, 23 + d]]], "eyes": [[[102, 22 + d], [105, 22 + d], [105, 25 + d], [102, 25 + d]]]}}
