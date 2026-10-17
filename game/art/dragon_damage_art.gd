class_name DragonDamageArt
extends RefCounted
## Native visual injury contract only. The coherent rig supplies source regions,
## read-only cropped images, image-pixel->logical xf and attachment anchors.
## No Unit, body damage, death, physics, random draw or campaign update is created.
const WOUND_CODES := ["b", "c", "f", "m"]
const BLOOD := Color("#7e1427")
const BLOOD_DARK := Color("#330913")
const BONE_WHITE := Color("#b9a391")
const BRUISE := Color("#49394d")
const DECAL_CACHE_LIMIT := 48
const GRAIN_CELL_CACHE_LIMIT := 4096
static var _decals: Dictionary = {}
static var _decal_order: Array[String] = []

static func normalize(state: Dictionary) -> Dictionary:
	var lost: Array[String] = []
	for value: Variant in state.get("lost", []):
		var id := str(value)
		if id != "" and not lost.has(id): lost.append(id)
	lost.sort()
	var dmg: Dictionary = {}; var wk: Dictionary = {}; var bleed: Dictionary = {}
	for key: Variant in state.get("dmg", {}):
		var id := str(key)
		if id != "": dmg[id] = clampf(float(state["dmg"][key]), 0.0, 1.0)
	for key: Variant in state.get("wk", {}):
		var id := str(key); var code := str(state["wk"][key])
		if code not in WOUND_CODES:
			var rank := int(FigurePainter.WOUND_SHOW_RANK.get(code, 0))
			code = str(FigurePainter.WOUND_SHOW[rank])
		if id != "" and code in WOUND_CODES: wk[id] = code
	for key: Variant in state.get("bleed", {}):
		if str(key) != "": bleed[str(key)] = bool(state["bleed"][key])
	return {"lost": lost, "dmg": dmg, "wk": wk, "bleed": bleed, "blood": clampf(float(state.get("blood", 1.0)), 0.0, 1.0)}

static func _by_id(parts: Array) -> Dictionary:
	var out: Dictionary = {}
	for part: Dictionary in parts:
		var id := str(part.get("id", ""))
		if id != "": out[id] = part
	return out

## Latest preview policy: coherent wings/legs/body stay visible and mangled.
## Only head separation at the neck removes the attached head and jaw image.
static func effective_lost(state: Dictionary, parts: Array) -> Array[String]:
	var native := normalize(state); var out: Array[String] = []
	var table := _by_id(parts)
	if native["lost"].has("head") or native["lost"].has("neck"):
		for id: String in ["head", "jaw"]:
			if table.has(id): out.append(id)
	return out

static func _radius(part: Dictionary) -> float:
	var bounds: Rect2 = part.get("bounds", Rect2())
	return maxf(0.5, minf(bounds.size.x, bounds.size.y) * 0.18)

## Anatomical regions are masks on the coherent source, not detachable limbs.
## Native lost limb fields become mangling/blood, while state stays untouched.
static func marks(state: Dictionary, parts: Array, regions: Array = []) -> Array:
	var native := normalize(state); var lost := effective_lost(native, parts)
	var table := _by_id(parts); var out: Array = []
	var masks: Array = regions if not regions.is_empty() else parts
	var region_table := _by_id(masks)
	if lost.has("head"):
		var neck: Dictionary = region_table.get("neck", {})
		var head: Dictionary = table.get("head", {})
		var owner := str(neck.get("owner_part_id", head.get("parent", "body")))
		if table.has(owner):
			var point: Vector2 = neck.get("cut_point", head.get("anchor_start", (table[owner]["bounds"] as Rect2).get_center()))
			out.append({"kind": "stump", "part_id": "head", "mask_part_id": owner, "mask_region_id": "neck" if not neck.is_empty() else owner,
				"point": point, "radius": _radius(neck if not neck.is_empty() else table[owner]),
				"cut_line": neck.get("cut_line", PackedVector2Array()).duplicate(),
				"damage": 1.0, "wound_kind": "m", "bleeding": float(native["blood"]) > 0.0, "blood": native["blood"]})
	for region: Dictionary in masks:
		var id := str(region.get("id", "")); var owner := str(region.get("owner_part_id", id))
		if not table.has(owner) or lost.has(owner) or (id == "neck" and lost.has("head")): continue
		var mangled: bool = native["lost"].has(id)
		var damage := 1.0 if mangled else float(native["dmg"].get(id, 0.0))
		if damage <= 0.02: continue
		var start: Vector2 = region.get("anchor_start", (region.get("bounds", Rect2()) as Rect2).get_center())
		var end: Vector2 = region.get("anchor_end", start)
		out.append({"kind": "mangle" if mangled else "wound", "part_id": id, "mask_part_id": owner, "mask_region_id": id,
			"point": start.lerp(end, 0.5), "radius": _radius(region), "damage": damage,
			"wound_kind": "m" if mangled else str(native["wk"].get(id, "c")),
			"bleeding": (mangled or bool(native["bleed"].get(id, false))) and float(native["blood"]) > 0.0, "blood": native["blood"]})
	return out

## Head-only detached source art. There is no fabricated severed wing/leg/jaw.
static func detached_parts(part_id: String, state: Dictionary, parts: Array) -> Array:
	var table := _by_id(parts)
	if part_id not in ["head", "neck"] or not table.has("head"): return []
	var out: Array = []
	for part: Dictionary in parts:
		var id := str(part.get("id", ""))
		if id not in ["head", "jaw"]: continue
		var copied: Dictionary = part.duplicate(true)
		copied["hidden"] = false; copied["visible"] = true; copied["detached_root"] = "head"
		out.append(copied)
	return out

static func _mask_at(part: Dictionary, world: Vector2) -> bool:
	var image: Image = part.get("image", null)
	if image == null or image.is_empty(): return false
	var xf: Transform2D = part.get("xf", Transform2D.IDENTITY)
	var pixel := xf.affine_inverse() * world
	var x := floori(pixel.x); var y := floori(pixel.y)
	return x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height() and image.get_pixel(x, y).a > 0.1

static func _exposed_at(parts: Array, part_id: String, world: Vector2, lost: Array[String]) -> bool:
	# Actual painter order prevents a rear-wing wound staining the near limb.
	for index: int in range(parts.size() - 1, -1, -1):
		var candidate: Dictionary = parts[index]
		if bool(candidate.get("hidden", false)) or not bool(candidate.get("visible", true)) or lost.has(str(candidate.get("id", ""))): continue
		if _mask_at(candidate, world): return str(candidate.get("id", "")) == part_id
	return false

static func _multiply32(value: int, multiplier: int) -> int:
	# Truncated multiplication using 16-bit halves keeps intermediates below the
	# signed 64-bit limit while preserving exact unsigned 32-bit avalanche math.
	return ((value & 65535) * multiplier + ((((value >> 16) & 65535) * multiplier & 65535) << 16)) & 0xffffffff

static func _cell_value(cell: Vector2i, seed_value: int) -> float:
	var mixed: int = _multiply32(cell.x & 0xffffffff, 0x9e3779b1) ^ _multiply32(cell.y & 0xffffffff, 0x85ebca77) ^ (seed_value & 0xffffffff)
	mixed = _multiply32(mixed ^ (mixed >> 16), 0x7feb352d)
	mixed = _multiply32(mixed ^ (mixed >> 15), 0x846ca68b)
	mixed = (mixed ^ (mixed >> 16)) & 0xffffffff
	return float(mixed & 0xffffff) / 16777215.0

static func _grain(point: Vector2, seed_value: int) -> float:
	# Coarse smooth pools, with independent avalanched corner values. A linear
	# coordinate hash formed visible horizontal stripes across the source skin.
	var at := point * 0.028; var cell := Vector2i(floori(at.x), floori(at.y))
	var blend := at - Vector2(cell); blend = blend * blend * (Vector2(3, 3) - blend * 2.0)
	var values: Array[float] = []
	for shift: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		values.append(_cell_value(cell + shift, seed_value))
	return lerpf(lerpf(values[0], values[1], blend.x), lerpf(values[2], values[3], blend.x), blend.y)

static func _cached_cell(cell: Vector2i, seed_value: int, cells: Dictionary) -> float:
	if cells.has(cell): return float(cells[cell])
	var value := _cell_value(cell, seed_value)
	if cells.size() < GRAIN_CELL_CACHE_LIMIT: cells[cell] = value
	return value

static func _grain_cached(point: Vector2, seed_value: int, cells: Dictionary) -> float:
	# Same corner values/interpolation/order as _grain; only memoize expensive
	# avalanche math. Each cache belongs to one seed and one local decal build.
	var at := point * 0.028; var cell := Vector2i(floori(at.x), floori(at.y))
	var blend := at - Vector2(cell); blend = blend * blend * (Vector2(3, 3) - blend * 2.0)
	var a := _cached_cell(cell, seed_value, cells)
	var b := _cached_cell(cell + Vector2i.RIGHT, seed_value, cells)
	var c := _cached_cell(cell + Vector2i.DOWN, seed_value, cells)
	var d := _cached_cell(cell + Vector2i.ONE, seed_value, cells)
	return lerpf(lerpf(a, b, blend.x), lerpf(c, d, blend.x), blend.y)

static func _tone(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))

static func _bounds(area: Rect2, xf: Transform2D) -> Rect2:
	var low := Vector2(INF, INF); var high := Vector2(-INF, -INF)
	for point: Vector2 in [area.position, area.position + Vector2(area.size.x, 0), area.end, area.position + Vector2(0, area.size.y)]:
		var at := xf * point; low = low.min(at); high = high.max(at)
	return Rect2(low, high - low)

static func _injury_color(mark: Dictionary, offset: Vector2, noise: float, detail: float) -> Color:
	var damage := float(mark["damage"]); var code := str(mark["wound_kind"])
	var u := offset.x; var v := offset.y
	var seam := sin(u * 6.7 + noise * 3.0) * 0.035 + (noise - 0.5) * 0.07
	var taper := maxf(0.0, 1.0 - pow(absf(u), 1.3))
	var thickness := (0.055 + damage * 0.095) * taper * (0.65 + noise * 0.7)
	if code == "b":
		var edge := u * u + pow(v / 0.6, 2)
		return _tone(BRUISE, maxf(0.0, 1.0 - edge) * damage * (0.35 + noise * 0.25))
	var color := Color.TRANSPARENT
	# Diffuse pooled stain fades into the existing scale texture. The irregular
	# slit remains narrow, dark and tapered; there is no round red stump disk.
	var fringe := absf(v - seam) / maxf(0.01, thickness * 3.2)
	if absf(u) < 1.08 and fringe < 1.0:
		color = _tone(BLOOD, (1.0 - fringe) * taper * (0.15 + noise * 0.2) * damage)
	if absf(u) < 1.0 and absf(v - seam) < thickness:
		color = _tone(BLOOD_DARK.lerp(BLOOD, noise * 0.3), 0.7 + noise * 0.23)
		if code == "m" and absf(v - seam) < thickness * 0.5 and detail > 0.55:
			color = _tone(Color("#782536"), 0.78)
		elif code == "f" and absf(u) < 0.18 and absf(v - seam) < thickness * 0.32:
			color = _tone(BONE_WHITE, 0.65 + noise * 0.15)
	# Active blood is a restrained ragged smear on the tissue, not a capsule or
	# detached drop. Depleted blood preserves the wound but stops fresh smears.
	if bool(mark["bleeding"]) and v > thickness and v < 0.4 + float(mark["blood"]) * 0.7:
		var trail := absf(u - sin(v * 5.0 + detail) * 0.09) / (0.09 + noise * 0.07)
		if trail < 1.0:
			var smear := _tone(BLOOD_DARK, (1.0 - trail) * (0.35 + noise * 0.15) * maxf(0.0, 1.0 - v))
			color = color.blend(smear)
	return color

static func _region_blood(mark: Dictionary, uv: Vector2, noise: float, detail: float) -> Color:
	if str(mark["wound_kind"]) == "b": return Color.TRANSPARENT
	var damage := float(mark["damage"])
	var ragged := smoothstep(0.36, 0.72, noise * 0.78 + detail * 0.3)
	var edge := clampf(minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y)) * 8.0, 0.0, 1.0)
	var smear := ragged * 0.68 * (0.16 + edge * 0.84) * damage
	# Broad translucent blood follows the entire affected anatomical mask. The
	# underlying scale shading remains visible; ragged variations avoid a filled
	# red polygon or regular dots. A dry injury retains darker old blood stains.
	var tone := BLOOD_DARK.lerp(Color("#941329"), 0.3 + noise * 0.65)
	if not bool(mark["bleeding"]): tone = tone.darkened(0.18)
	return _tone(tone, smear)

static func _cut_edge_color(mark: Dictionary, point: Vector2, noise: float, detail: float) -> Color:
	var line: PackedVector2Array = mark.get("cut_line", PackedVector2Array())
	if line.size() < 2: return Color.TRANSPARENT
	var distance := INF
	for index: int in range(line.size() - 1):
		distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, line[index], line[index + 1])))
	var width := float(mark["lip_width"]) * (0.75 + noise * 0.5)
	if distance > width * 2.2: return Color.TRANSPARENT
	var color := _tone(BLOOD_DARK.lerp(BLOOD, noise * 0.6), maxf(0.0, 1.0 - distance / (width * 2.2)) * 0.72)
	if distance <= width:
		color = _tone(Color("#791326").lerp(Color("#962638"), detail * 0.4), 0.86)
	if distance <= width * (0.23 + detail * 0.16):
		color = _tone(Color("#b64c59").lerp(Color("#7d2537"), noise), 0.94)
	return color

static func _local_marks(part: Dictionary, injury_marks: Array, regions: Dictionary) -> Array:
	var xf: Transform2D = part["xf"]
	var inverse := xf.affine_inverse(); var out: Array = []
	for mark: Dictionary in injury_marks:
		var region: Dictionary = regions.get(str(mark.get("mask_region_id", "")), part)
		var region_image: Image = region["image"]; var region_xf: Transform2D = region["xf"]
		var mask_xf := inverse * region_xf
		var axis := (inverse * (region["anchor_end"] as Vector2) - inverse * (region["anchor_start"] as Vector2)).normalized()
		var local: Dictionary = mark.duplicate(true)
		local["point"] = inverse * (mark["point"] as Vector2)
		local["radius"] = maxf(1.6, minf(region_image.get_width(), region_image.get_height()) * mask_xf.get_scale().abs().length() / sqrt(2.0) * (0.55 if mark["kind"] == "stump" else 0.18))
		local["angle"] = axis.angle() + 0.37
		if mark["kind"] == "stump":
			local["angle"] = axis.angle() + PI * 0.5
		local["mask"] = {"image": region_image, "xf": mask_xf}
		local["mask_inverse"] = mask_xf.affine_inverse()
		local["mask_size"] = Vector2(region_image.get_size())
		local["lip_width"] = clampf(minf(region_image.get_width(), region_image.get_height()) * 0.04, 2.0, 12.0) * mask_xf.get_scale().abs().length() / sqrt(2.0)
		var cut_line := PackedVector2Array()
		for cut_point: Vector2 in mark.get("cut_line", PackedVector2Array()): cut_line.append(inverse * cut_point)
		local["cut_line"] = cut_line
		out.append(local)
	return out

static func _build_decal(part: Dictionary, local_marks: Array, seed_value: int) -> Dictionary:
	var source: Image = part["image"]; var area := Rect2(); var initialized := false
	for mark: Dictionary in local_marks:
		# Scratch caches never leave this build or touch native state/source art.
		mark["noise_seed"] = seed_value + int(hash(str(mark["part_id"])))
		mark["grain_cells"] = {}; mark["detail_cells"] = {}
		var radius := float(mark["radius"]) * 1.55
		var box := Rect2((mark["point"] as Vector2) - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))
		if str(mark["wound_kind"]) != "b":
			var mask: Dictionary = mark["mask"]
			box = box.merge(_bounds(Rect2(Vector2.ZERO, mark["mask_size"]), mask["xf"]))
		for cut_point: Vector2 in mark["cut_line"]:
			var lip := float(mark["lip_width"]) * 2.8
			box = box.merge(Rect2(cut_point - Vector2(lip, lip), Vector2(lip * 2, lip * 2)))
		area = area.merge(box) if initialized else box; initialized = true
	var low := Vector2i(floori(area.position.x), floori(area.position.y)).max(Vector2i.ZERO)
	var high := Vector2i(ceili(area.end.x), ceili(area.end.y)).min(source.get_size())
	if high.x <= low.x or high.y <= low.y: return {}
	var image := Image.create(high.x - low.x, high.y - low.y, false, Image.FORMAT_RGBA8)
	for y: int in range(low.y, high.y):
		for x: int in range(low.x, high.x):
			var source_alpha := source.get_pixel(x, y).a
			if source_alpha <= 0.1: continue
			var point := Vector2(x + 0.5, y + 0.5); var color := Color.TRANSPARENT
			for mark: Dictionary in local_marks:
				var mask_pixel: Vector2 = (mark["mask_inverse"] as Transform2D) * point
				var mask: Dictionary = mark["mask"]; var mask_image: Image = mask["image"]
				var mx := floori(mask_pixel.x); var my := floori(mask_pixel.y)
				if mx < 0 or my < 0 or mx >= mask_image.get_width() or my >= mask_image.get_height() or mask_image.get_pixel(mx, my).a <= 0.1: continue
				var offset := (point - (mark["point"] as Vector2)).rotated(-float(mark["angle"])) / float(mark["radius"])
				var salt: int = mark["noise_seed"]
				var noise := _grain_cached(point, salt, mark["grain_cells"])
				var detail := _grain_cached(point * 2.1, salt + 17, mark["detail_cells"])
				var uv: Vector2 = mask_pixel / (mark["mask_size"] as Vector2)
				var stain := _region_blood(mark, uv, noise, detail)
				var injury := _injury_color(mark, offset, noise, detail)
				if str(mark["kind"]) == "stump" and not (mark["cut_line"] as PackedVector2Array).is_empty(): injury = _cut_edge_color(mark, point, noise, detail)
				color = color.blend(stain.blend(injury))
			if color.a > 0.0:
				color.a *= source_alpha; image.set_pixel(x - low.x, y - low.y, color)
	return {"image": image, "source_rect": Rect2(Vector2(low), Vector2(high - low))}

## Borrowed READ-ONLY transparent decals for native CanvasItem rendering. Cache
## keys contain source image identity/native injury/seed, never posed transforms.
## Each mark stays fixed to its textured tissue. Returned xf follows current pose.
## Draw each matching decal immediately after its original body part, so later
## textured foreground parts occlude it naturally. Cache holds at most 48 crops.
static func overlay_layers(parts: Array, state: Dictionary, seed_value: int = 0, regions: Array = []) -> Array:
	var grouped: Dictionary = {}; var out: Array = []
	var region_table := _by_id(regions if not regions.is_empty() else parts)
	for mark: Dictionary in marks(state, parts, regions):
		var id := str(mark["mask_part_id"])
		if not grouped.has(id): grouped[id] = []
		grouped[id].append(mark)
	for part: Dictionary in parts:
		var id := str(part.get("id", ""))
		if not grouped.has(id) or bool(part.get("hidden", false)) or not bool(part.get("visible", true)): continue
		var source: Image = part.get("image", null)
		if source == null or source.is_empty(): continue
		var signature: Array = []
		for mark: Dictionary in grouped[id]:
			var region: Dictionary = region_table.get(str(mark["mask_region_id"]), part)
			var mask_image: Image = region["image"]
			signature.append([mark["kind"], mark["part_id"], mark["damage"], mark["wound_kind"], mark["bleeding"], mark["blood"], mask_image.get_instance_id()])
		var key := "%d/%s/%d/%d" % [source.get_instance_id(), id, seed_value, hash(var_to_bytes(signature))]
		var cached: Dictionary = _decals.get(key, {})
		if cached.is_empty():
			cached = _build_decal(part, _local_marks(part, grouped[id], region_table), seed_value)
			if cached.is_empty(): continue
			_decals[key] = cached
		_decal_order.erase(key); _decal_order.append(key)
		while _decal_order.size() > DECAL_CACHE_LIMIT: _decals.erase(_decal_order.pop_front())
		var area: Rect2 = cached["source_rect"]
		var xf: Transform2D = (part["xf"] as Transform2D) * Transform2D(0.0, area.position)
		out.append({"part_id": id, "image": cached["image"], "source_rect": area, "xf": xf,
			"bounds": _bounds(Rect2(Vector2.ZERO, area.size), xf)})
	return out

## Software captures consume the same organic decals as the live GPU renderer.
## Only the requested output is changed; source pixels/state/campaign stay pure.
static func draw_overlay(cv: PixelCanvas, parts: Array, state: Dictionary, origin: Vector2, pixels_per_unit: float, seed_value: int = 0, regions: Array = []) -> void:
	if pixels_per_unit <= 0: return
	var lost := effective_lost(state, parts)
	var camera := Transform2D(0.0, Vector2(pixels_per_unit, pixels_per_unit), 0.0, origin)
	for layer: Dictionary in overlay_layers(parts, state, seed_value, regions):
		var image: Image = layer["image"]; var xf: Transform2D = camera * layer["xf"]
		var area := _bounds(Rect2(Vector2.ZERO, Vector2(image.get_size())), xf)
		var low := Vector2i(floori(area.position.x), floori(area.position.y)).max(Vector2i.ZERO)
		var high := Vector2i(ceili(area.end.x), ceili(area.end.y)).min(Vector2i(cv.w, cv.h))
		var inverse := xf.affine_inverse()
		for y: int in range(low.y, high.y):
			for x: int in range(low.x, high.x):
				var point := Vector2(x + 0.5, y + 0.5); var local := inverse * point
				var sx := floori(local.x); var sy := floori(local.y)
				if sx < 0 or sy < 0 or sx >= image.get_width() or sy >= image.get_height(): continue
				var color := image.get_pixel(sx, sy)
				if color.a > 0.0 and _exposed_at(parts, str(layer["part_id"]), (point - origin) / pixels_per_unit, lost): cv.stain_px(x, y, color)

## Optional visual-only tooth/claw-tip fragments. Caller explicitly requests
## state.fragments=[{region_id:'jaw',kind:'tooth',count:3},...]. These tiny tinted
## tissue slivers are not detached limb sprites, Items, Units or physical bodies.
## Logical tip size is capped below one unit, independent of host body size.
static func fragment_layers(row: Dictionary, regions: Array, state: Dictionary, progress: float, seed_value: int = 0) -> Array:
	var t := clampf(progress, 0.0, 1.0)
	if t >= 1.0 or str(row.get("stage", "adult")) == "egg": return []
	var palette: Dictionary = {}
	for gem: Dictionary in Dragons.catalogs().get("gems", []):
		if str(gem["id"]) == str(row.get("gem_id", "")): palette = gem; break
	if palette.is_empty(): return []
	var base := Color(str(palette["base"])); var accent := Color(str(palette["accent"]))
	var table := _by_id(regions); var out: Array = []
	for request: Dictionary in state.get("fragments", []):
		var id := str(request.get("region_id", "")); var kind := str(request.get("kind", ""))
		if not table.has(id): continue
		if kind == "tooth" and id not in ["head", "jaw"]: continue
		if kind == "claw" and not (id.begins_with("foot_") or id.begins_with("wing_lower_")): continue
		if kind not in ["tooth", "claw"]: continue
		var region: Dictionary = table[id]; var start: Vector2 = region["anchor_end"]
		var area: Rect2 = region["bounds"]
		var size := clampf(minf(area.size.x, area.size.y) * 0.025, 0.16, 0.7)
		for index: int in clampi(int(request.get("count", 3)), 1, 4):
			if out.size() >= 12: return out
			var salt := seed_value + int(row.get("appearance_seed", 0)) + int(hash(id)) + index * 71
			var turn := _grain(Vector2(index * 7, 3), salt)
			var direction := Vector2(2.2 + turn * 1.3, -2.1 + turn * 1.2)
			if index % 2: direction.x *= -0.65
			var point := start + direction * t + Vector2(0, 3.0 * t * t)
			var angle := turn * TAU + t * (1.8 + index * 0.5)
			var shape := PackedVector2Array([Vector2(-size * 0.7, -size * 0.15), Vector2(size * 0.6, 0), Vector2(-size * 0.1, size * 0.32)])
			var points := PackedVector2Array()
			for vertex: Vector2 in shape: points.append(point + vertex.rotated(angle))
			var color := base.lerp(accent, turn * 0.5).darkened(0.12)
			color.a = (1.0 - t) * 0.9
			out.append({"kind": kind, "region_id": id, "points": points, "color": color, "origin": start,
				"tip_size": size, "bounds": _bounds(Rect2(Vector2(-size, -size), Vector2(size * 2, size * 2)), Transform2D(angle, point)), "visual_preview_only": true})
	return out

static func draw_fragments(cv: PixelCanvas, layers: Array, origin: Vector2, pixels_per_unit: float) -> void:
	if pixels_per_unit <= 0: return
	var old_xf := cv.xf; var old_scale := cv.k
	cv.set_frame(origin, pixels_per_unit)
	for layer: Dictionary in layers: cv.poly(layer["points"], layer["color"])
	cv.xf = old_xf; cv.k = old_scale
