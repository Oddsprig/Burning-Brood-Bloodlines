class_name DragonRigArt
extends RefCounted
## One coherent source, three exact ownership masks. Rest never fits a part;
## only hierarchical animation deltas alter the observed source positions.
const ORDER := ["body", "head", "jaw"]
const TEXTURE_CACHE_LIMIT := 96
const IMAGE_CACHE_LIMIT := 6
static var _sources: Dictionary = {}
static var _images: Dictionary = {}
static var _image_order: Array[String] = []
static var _textures: Dictionary = {}
static var _texture_order: Array[int] = []

static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func _rectangle(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))

static func transformed_bounds(area: Rect2, xf: Transform2D) -> Rect2:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for point: Vector2 in [area.position, area.position + Vector2(area.size.x, 0), area.end, area.position + Vector2(0, area.size.y)]:
		var at: Vector2 = xf * point
		low = low.min(at); high = high.max(at)
	return Rect2(low, high - low)

static func _polygon_bounds(polygons: Array, size: Vector2i) -> Rect2i:
	var low: Vector2 = Vector2(size)
	var high: Vector2 = Vector2.ZERO
	for polygon: Array in polygons:
		for value: Array in polygon:
			var point: Vector2 = _point(value)
			low = low.min(point); high = high.max(point)
	var a: Vector2i = Vector2i(floori(low.x), floori(low.y)).max(Vector2i.ZERO)
	var b: Vector2i = Vector2i(ceili(high.x), ceili(high.y)).min(size)
	return Rect2i(a, (b - a).max(Vector2i.ZERO))

## Pixel-centre scanlines produce non-feathered deterministic ownership.
static func _fill(mask: PackedByteArray, width: int, crop: Rect2i, polygons: Array, value: int) -> void:
	for polygon: Array in polygons:
		if polygon.size() < 3: continue
		for local_y: int in crop.size.y:
			var y: float = crop.position.y + local_y + 0.5
			var crossings: Array[float] = []
			for index: int in polygon.size():
				var a: Vector2 = _point(polygon[index])
				var b: Vector2 = _point(polygon[(index + 1) % polygon.size()])
				if (a.y <= y and b.y > y) or (b.y <= y and a.y > y):
					crossings.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
			crossings.sort()
			for pair: int in range(0, crossings.size() - 1, 2):
				var first: int = maxi(0, ceili(crossings[pair] - 0.5) - crop.position.x)
				var last: int = mini(crop.size.x, ceili(crossings[pair + 1] - 0.5) - crop.position.x)
				for x: int in range(first, last): mask[local_y * width + x] = value

static func _extract(bytes: PackedByteArray, size: Vector2i, crop: Rect2i, mask: PackedByteArray) -> Image:
	var output: PackedByteArray = PackedByteArray()
	output.resize(crop.size.x * crop.size.y * 4)
	for y: int in crop.size.y:
		for x: int in crop.size.x:
			var pixel: int = y * crop.size.x + x
			if mask[pixel] == 0: continue
			var source_index: int = ((y + crop.position.y) * size.x + x + crop.position.x) * 4
			output.encode_u32(pixel * 4, bytes.decode_u32(source_index))
	return Image.create_from_data(crop.size.x, crop.size.y, false, Image.FORMAT_RGBA8, output)

static func _source(row: Dictionary, pose: String = "rest", progress: float = 0.0) -> Dictionary:
	var morph: String = DragonSpriteCatalog.source_id(row)
	var generated: bool = not DragonSpriteCatalog.variant_for(row).is_empty()
	var source_key := "%s/frame%d" % [morph, SapphireSpirewingArt.frame_index(pose, progress)] if generated else morph
	if _sources.has(source_key): return _sources[source_key]
	var entry: Dictionary = DragonSpriteCatalog.source_entry(row, pose, progress)
	if entry.is_empty(): return {}
	var path: String = String(entry.get("source_path", ""))
	var image: Image
	if generated:
		image = SapphireSpirewingArt.frame(int(entry["frame"]))
	else:
		if not ResourceLoader.exists(path, "Texture2D"):
			push_error("Dragon coherent source is missing: " + path); return {}
		var texture: Texture2D = ResourceLoader.load(path, "Texture2D") as Texture2D
		image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		push_error("Dragon coherent source cannot be decoded: " + path); return {}
	if image.is_compressed() and image.decompress() != OK:
		push_error("Dragon coherent source cannot be decompressed: " + path); return {}
	image.convert(Image.FORMAT_RGBA8)
	var size: Vector2i = image.get_size()
	if Vector2(size) != _point(entry.get("image_size", [0, 0])):
		push_error("Dragon coherent source dimensions disagree with metadata: " + path); return {}
	var definitions: Dictionary = entry.get("parts", {})
	for id: String in ORDER:
		if not definitions.has(id) or not definitions[id].has("polygons") or not definitions[id].has("pivot_px"):
			push_error("Dragon coherent source part metadata missing: " + morph + "/" + id); return {}
	var ownership: PackedByteArray = PackedByteArray()
	ownership.resize(size.x * size.y); ownership.fill(0)
	# Body also owns invisible pixels, preserving their original RGB for proof.
	var priorities: Array[String] = ["head", "jaw"]
	priorities.sort_custom(func(a: String, b: String) -> bool: return int(definitions[a].get("ownership_priority", 0)) < int(definitions[b].get("ownership_priority", 0)))
	for id: String in priorities:
		_fill(ownership, size.x, Rect2i(Vector2i.ZERO, size), definitions[id]["polygons"], ORDER.find(id))
	var raw: PackedByteArray = image.get_data()
	var layers: Dictionary = {}
	for id: String in ORDER:
		var definition: Dictionary = definitions[id]
		var crop: Rect2i = Rect2i(Vector2i.ZERO, size) if id == "body" else _polygon_bounds(definition["polygons"], size)
		var mask: PackedByteArray = PackedByteArray()
		mask.resize(crop.size.x * crop.size.y)
		for y: int in crop.size.y:
			for x: int in crop.size.x:
				mask[y * crop.size.x + x] = 1 if ownership[(y + crop.position.y) * size.x + x + crop.position.x] == ORDER.find(id) else 0
		layers[id] = {"id": id, "label": definition.get("label", id), "parent": String(definition.get("parent", "")),
			"source_rect": crop, "mask": mask, "pivot_px": _point(definition["pivot_px"]),
			"painter_order": int(definition.get("painter_order", ORDER.find(id))), "image": _extract(raw, size, crop, mask)}
	var regions: Dictionary = {}
	for id: String in entry.get("anatomical_regions", {}):
		var definition: Dictionary = entry["anatomical_regions"][id]
		var crop: Rect2i = _polygon_bounds(definition.get("polygons", []), size)
		var mask: PackedByteArray = PackedByteArray()
		mask.resize(crop.size.x * crop.size.y)
		_fill(mask, crop.size.x, crop, definition.get("polygons", []), 1)
		var owner: String = String(definition.get("owner_part_id", "body"))
		for y: int in crop.size.y:
			for x: int in crop.size.x:
				if ownership[(y + crop.position.y) * size.x + x + crop.position.x] != ORDER.find(owner): mask[y * crop.size.x + x] = 0
		regions[id] = {"id": id, "owner_part_id": owner, "source_rect": crop, "mask": mask, "definition": definition}
	var preserve: Array[Rect2] = []
	var gems: Array[Rect2] = []
	for area: Array in entry.get("preserve_regions", []): preserve.append(_rectangle(area))
	for area: Array in entry.get("gem_regions", []): gems.append(_rectangle(area))
	var source: Dictionary = {"key": source_key + "/coherent", "entry": entry, "size": Vector2(size), "bytes": raw,
		"image": image, "ownership": ownership, "parts": layers, "regions": regions, "preserve": preserve, "gems": gems}
	source["neck_contacts"] = _neck_contacts(entry, raw, ownership, size)
	_sources[source_key] = source
	return source

## Original alpha-visible contacts along the anatomical head/body boundary.
## They are cached once; no new tissue image, fitting or source mask is created.
static func _neck_contacts(entry: Dictionary, bytes: PackedByteArray, ownership: PackedByteArray, size: Vector2i) -> Array:
	var contacts: Array = []
	var cut: Array = entry["anatomical_regions"]["neck"].get("cut_line_px", [])
	for index: int in range(cut.size() - 1):
		var a: Vector2 = _point(cut[index])
		var b: Vector2 = _point(cut[index + 1])
		var tangent: Vector2 = b - a
		var normal: Vector2 = Vector2(-tangent.y, tangent.x).normalized()
		var samples: int = maxi(1, ceili(a.distance_to(b)))
		for step: int in range(samples + 1):
			var point: Vector2 = a.lerp(b, float(step) / samples)
			var above: Vector2 = point - normal * 1.5
			var below: Vector2 = point + normal * 1.5
			var head_pixel: Vector2i = Vector2i(floori(above.x), floori(above.y))
			var body_pixel: Vector2i = Vector2i(floori(below.x), floori(below.y))
			if not Rect2i(Vector2i.ZERO, size).has_point(head_pixel) or not Rect2i(Vector2i.ZERO, size).has_point(body_pixel): continue
			var head_index: int = head_pixel.y * size.x + head_pixel.x
			var body_index: int = body_pixel.y * size.x + body_pixel.x
			if ownership[head_index] != ORDER.find("head") or ownership[body_index] != ORDER.find("body"): continue
			if bytes[head_index * 4 + 3] < 220 or bytes[body_index * 4 + 3] < 220: continue
			contacts.append({"point": point, "normal": normal})
	return contacts

## Borrowed read-only raw layers: exact RGBA and source-global pixel offsets.
static func labelled_source_layers(row: Dictionary) -> Array:
	var source: Dictionary = _source(row)
	var result: Array = []
	if source.is_empty(): return result
	for id: String in ORDER:
		var layer: Dictionary = source["parts"][id].duplicate()
		var area: Rect2i = layer["source_rect"]
		layer["source_offset_px"] = Vector2(area.position)
		layer["xf"] = Transform2D(0, Vector2(area.position))
		result.append(layer)
	return result

static func source_image(row: Dictionary) -> Image:
	return _source(row).get("image", null)

## Assignment rather than blending preserves all bytes, even alpha-zero RGB.
static func reconstruct_source(row: Dictionary) -> Image:
	var source: Dictionary = _source(row)
	if source.is_empty(): return null
	var size: Vector2i = Vector2i(source["size"])
	var output: PackedByteArray = PackedByteArray()
	output.resize(size.x * size.y * 4)
	for layer: Dictionary in labelled_source_layers(row):
		var crop: Rect2i = layer["source_rect"]
		var pixels: PackedByteArray = layer["image"].get_data()
		var mask: PackedByteArray = layer["mask"]
		for y: int in crop.size.y:
			for x: int in crop.size.x:
				var pixel: int = y * crop.size.x + x
				if mask[pixel] == 0: continue
				var target: int = ((y + crop.position.y) * size.x + x + crop.position.x) * 4
				output.encode_u32(target, pixels.decode_u32(pixel * 4))
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, output)

## Full-size LA8 mask (alpha = this layer's pixels), built once per source layer per session.
static func _mask_image(layer: Dictionary, size: Vector2i) -> Image:
	if layer.has("mask_img"): return layer["mask_img"]
	var crop: Rect2i = layer["source_rect"]
	var mask: PackedByteArray = layer["mask"]
	var data := PackedByteArray()
	data.resize(size.x * size.y * 2)
	for y: int in crop.size.y:
		var row_start: int = ((y + crop.position.y) * size.x + crop.position.x) * 2
		for x: int in crop.size.x:
			if mask[y * crop.size.x + x] != 0:
				data[row_start + x * 2 + 1] = 255
	var img := Image.create_from_data(size.x, size.y, false, Image.FORMAT_LA8, data)
	layer["mask_img"] = img
	return img

static func _part_images(source: Dictionary, row: Dictionary) -> Dictionary:
	var key: String = "%s/%s/%d" % [source["key"], row.get("gem_id", ""), posmod(int(row.get("appearance_seed", 0)), 7)]
	if _images.has(key):
		_image_order.erase(key); _image_order.append(key); return _images[key]
	var gem: Dictionary = DragonArt._entry("gems", String(row.get("gem_id", "")))
	if gem.is_empty(): push_error("Dragon source gem palette is unknown."); return {}
	# Code sources already contain the authored sapphire ramps, eye and gem glints.
	var tinted: Dictionary = {"bytes": source["bytes"]} if bool(source["entry"].get("painted", false)) else DragonArt._tinted(source, row, Color(String(gem["base"])), Color(String(gem["accent"])))
	var source_size: Vector2i = Vector2i(source["size"])
	var result: Dictionary = {"parts": {}, "regions": {}, "whole": Image.create_from_data(source_size.x, source_size.y, false, Image.FORMAT_RGBA8, tinted["bytes"])}
	# Image blits with cached full-size masks: no per-pixel script loop on every new dragon.
	var whole: Image = result["whole"]
	for group: String in ["parts", "regions"]:
		for id: String in source[group]:
			var layer: Dictionary = source[group][id]
			var crop: Rect2i = layer["source_rect"]
			var out := Image.create_empty(maxi(1, crop.size.x), maxi(1, crop.size.y), false, Image.FORMAT_RGBA8)
			out.blit_rect_mask(whole, _mask_image(layer, source_size), crop, Vector2i.ZERO)
			result[group][id] = out
	_images[key] = result; _image_order.append(key)
	while _image_order.size() > IMAGE_CACHE_LIMIT: _images.erase(_image_order.pop_front())
	return result

static func _around(pivot: Vector2, angle: float, move: Vector2 = Vector2.ZERO) -> Transform2D:
	var xf: Transform2D = Transform2D(angle, Vector2.ZERO)
	xf.origin = pivot + move - xf * pivot
	return xf

## A rotated rigid cut can open on one side of its pivot. Seat the unchanged
## head minimally down the observed neck axis, so its cut overlaps real body
## tissue. Rest translation is exactly zero; no stretch or filler is used.
static func _seat_neck(source: Dictionary, rotation: Transform2D) -> Dictionary:
	var contacts: Array = source["neck_contacts"]
	var axis: Vector2 = (_point(source["entry"]["neck_root_px"]) - (source["parts"]["head"]["pivot_px"] as Vector2)).normalized()
	var amount: float = 0
	var active: bool = not rotation.is_equal_approx(Transform2D.IDENTITY)
	if active:
		for contact: Dictionary in contacts:
			var normal: Vector2 = contact["normal"]
			var denominator: float = normal.dot(axis)
			if denominator <= 0.05: continue
			var point: Vector2 = contact["point"]
			var separation: float = normal.dot(rotation * point - point)
			amount = maxf(amount, (0.65 - separation) / denominator)
	var seated: Transform2D = rotation
	seated.origin += axis * amount
	var overlap: float = INF
	for contact: Dictionary in contacts:
		var point: Vector2 = contact["point"]
		var normal: Vector2 = contact["normal"]
		overlap = minf(overlap, normal.dot(seated * point - point))
	return {"xf": seated, "translation_px": axis * amount, "contact_count": contacts.size(), "minimum_overlap_px": overlap if not contacts.is_empty() else 0.0}

static func _pose_transforms(source: Dictionary, pose: String, progress: float) -> Dictionary:
	var parts: Dictionary = source["parts"]
	var t: float = clampf(progress, 0, 1)
	if pose == "rest": return {"body": Transform2D.IDENTITY, "head": Transform2D.IDENTITY, "jaw": Transform2D.IDENTITY,
		"neck_join": {"translation_px": Vector2.ZERO, "contact_count": source["neck_contacts"].size(), "minimum_overlap_px": 0.0}}
	if int(FigurePainter.FRAMES[pose]) == 1: t = 0.0
	var wave: float = sin(TAU * t)
	var pulse: float = sin(PI * t)
	var body_angle: float = 0.003 * wave
	var body_move: Vector2 = Vector2(0, -2 * wave)
	var head_angle: float = 0.017 * wave
	var jaw_angle: float = maxf(0, wave) * 0.035
	match pose:
		"walk": body_move = Vector2(3 * wave, -3 * sin(TAU * t * 2)); head_angle = -0.012 * wave
		"prepare": body_angle = -0.009 * t; body_move = Vector2(-7, 3) * t; head_angle = -0.10 * t; jaw_angle = 0.14 * t
		"strike": body_angle = 0.012 * pulse; body_move = Vector2(12, -3) * pulse; head_angle = 0.14 * pulse; jaw_angle = 0.36 * pulse
		"recover": body_angle = 0.009 * (1 - t); body_move = Vector2(7, -2) * (1 - t); head_angle = 0.08 * (1 - t); jaw_angle = 0.16 * (1 - t)
		"hit": body_angle = -0.017 * pulse; body_move = Vector2(-11, 3) * pulse; head_angle = -0.11 * pulse; jaw_angle = 0.06 * pulse
		"block": body_angle = -0.01 * pulse; head_angle = -0.07 * pulse
		"dodge": body_angle = -0.012 * pulse; body_move = Vector2(-12, 2) * pulse; head_angle = -0.06 * pulse
		"prone", "dead": body_angle = 0.04; body_move = Vector2(0, 8); head_angle = 0.08; jaw_angle = 0.09
	body_move *= float(source["entry"].get("motion_scale", 1.0))
	var body: Transform2D = _around(parts["body"]["pivot_px"], body_angle, body_move)
	var join: Dictionary = _seat_neck(source, _around(parts["head"]["pivot_px"], head_angle))
	var head: Transform2D = body * join["xf"]
	var jaw: Transform2D = head * _around(parts["jaw"]["pivot_px"], jaw_angle)
	return {"body": body, "head": head, "jaw": jaw, "neck_join": join}

static func model(row: Dictionary, pose: String = "idle", progress: float = 0.0, state: Dictionary = {}, detached_root: String = "") -> Dictionary:
	pose = "idle" if pose == "ground" else pose
	if pose != "rest" and not pose in FigurePainter.POSES:
		push_error("Dragon source pose is unsupported: " + pose); return DragonArt._empty_model(pose)
	var source: Dictionary = _source(row, pose, progress)
	if source.is_empty(): return DragonArt._empty_model(pose)
	var images: Dictionary = _part_images(source, row)
	if images.is_empty(): return DragonArt._empty_model(pose)
	var entry: Dictionary = source["entry"]
	var size: Dictionary = DragonArt._entry("sizes", String(row.get("size_class", "medium")))
	var linear_scale: float = float(size.get("physical", {}).get("linear_scale", 1.5))
	var source_scale: float = float(entry["units_per_pixel"]) * linear_scale
	var source_origin: Vector2 = _point(entry["source_origin_px"])
	var to_logical: Transform2D = Transform2D(0, Vector2(source_scale, source_scale), 0, -source_origin * source_scale)
	var posed: Dictionary = _pose_transforms(source, pose, progress)
	var clean_state: Dictionary = DragonDamageArt.normalize(state)
	if detached_root != "":
		clean_state["lost"].erase("head"); clean_state["lost"].erase("neck")
	var beheaded: bool = "head" in clean_state["lost"] or "neck" in clean_state["lost"]
	var parts: Array = []
	var all_parts: Array = []
	var bounds: Rect2 = Rect2()
	var has_bounds: bool = false
	for id: String in ORDER:
		var layer: Dictionary = source["parts"][id]
		var image: Image = images["parts"][id]
		var source_rect: Rect2i = layer["source_rect"]
		var offset: Vector2 = Vector2(source_rect.position)
		var owner_xf: Transform2D = to_logical * posed[id]
		var xf: Transform2D = owner_xf * Transform2D(0, offset)
		var area: Rect2 = transformed_bounds(Rect2(image.get_used_rect()), xf)
		var attached: Vector2 = owner_xf * layer["pivot_px"]
		var visible: bool = (id == "body" or not beheaded) and (detached_root == "" or id != "body")
		var part: Dictionary = {"id": id, "label": layer["label"], "parent": layer["parent"], "image": image,
			"source_rect": source_rect, "source_offset_px": offset, "pivot": layer["pivot_px"] - offset,
			"pivot_px": layer["pivot_px"], "xf": xf, "bounds": area, "attachment": attached,
			"anchor_start": attached, "anchor_end": attached, "visible": visible, "hidden": not visible}
		all_parts.append(part)
		if visible:
			parts.append(part)
			bounds = bounds.merge(area) if has_bounds else area; has_bounds = true
	var regions: Array = []
	for id: String in source["regions"]:
		var layer: Dictionary = source["regions"][id]
		var definition: Dictionary = layer["definition"]
		var owner: String = layer["owner_part_id"]
		var owner_xf: Transform2D = to_logical * posed[owner]
		var region_rect: Rect2i = layer["source_rect"]
		var xf: Transform2D = owner_xf * Transform2D(0, Vector2(region_rect.position))
		var image: Image = images["regions"][id]
		var region: Dictionary = {"id": id, "owner_part_id": owner, "image": image, "xf": xf, "source_rect": region_rect,
			"bounds": transformed_bounds(Rect2(image.get_used_rect()), xf),
			"anchor_start": owner_xf * _point(definition["anchor_start_px"]), "anchor_end": owner_xf * _point(definition["anchor_end_px"])}
		if definition.has("cut_point_px"): region["cut_point"] = owner_xf * _point(definition["cut_point_px"])
		if definition.has("cut_line_px"):
			var cut_line: PackedVector2Array = PackedVector2Array()
			for point: Array in definition["cut_line_px"]: cut_line.append(owner_xf * _point(point))
			region["cut_line"] = cut_line
		regions.append(region)
	var body_xf: Transform2D = to_logical * posed["body"]
	var head_xf: Transform2D = to_logical * posed["head"]
	var seat: Vector2 = body_xf * _point(entry["seat_px"])
	var neck: Vector2 = body_xf * _point(entry["neck_root_px"])
	var head: Vector2 = head_xf * source["parts"]["head"]["pivot_px"]
	var raw_state: Dictionary = state.duplicate(true)
	var fragments: Array = DragonDamageArt.fragment_layers(row, regions, raw_state, progress, int(row.get("appearance_seed", 0)))
	# When all deltas agree, sampling the coherent pixels once prevents seams
	# caused by independently filtering complementary alpha masks at rest.
	var seamless: bool = not beheaded and detached_root == "" and (posed["body"] as Transform2D).is_equal_approx(posed["head"]) and (posed["head"] as Transform2D).is_equal_approx(posed["jaw"])
	return {"valid": true, "mountable": detached_root == "" and not pose in ["prone", "dead"], "pose": pose, "progress": progress,
		"frames": DragonArt.frame_count(row, pose), "supported_poses": DragonArt.SUPPORTED_POSES.duplicate(),
		"linear_scale": linear_scale, "source_scale": source_scale, "source_to_logical": to_logical,
		"source_origin_px": source_origin, "source_size": Vector2i(source["size"]), "seat": seat,
		"seat_angle": body_xf.get_rotation() + float(entry.get("seat_angle", 0)), "seat_width": 4.4 * linear_scale,
		"saddle": Rect2(seat + Vector2(-2.2, -0.5) * linear_scale, Vector2(4.4, 1) * linear_scale),
		"seat_clearance": Rect2(seat + Vector2(-8, -26), Vector2(19, 30)), "rider_height": 24.0, "rider_scale": 1.0,
		"neck_root": neck, "left_wing_root": body_xf * _point(entry["wing_roots_px"]["left"]), "right_wing_root": body_xf * _point(entry["wing_roots_px"]["right"]),
		"ground_y": (body_xf * Vector2(source_origin.x, float(entry["ground_y_px"]))).y, "bounds": bounds,
		"head_crop": transformed_bounds(_rectangle(entry["head_crop_px"]), head_xf), "geometry": {"neck_mid": neck.lerp(head, 0.5), "head": head},
		"parts": parts, "all_parts": all_parts, "regions": regions, "state": clean_state, "original_state": raw_state, "fragments": fragments,
		"detached_root": detached_root, "seamless_rest": seamless, "whole_image": images["whole"], "whole_xf": body_xf, "neck_join": posed["neck_join"],
		"hind_legs": 2, "wing_forelimbs": 2, "front_legs": 0}

static func detached(row: Dictionary, part_id: String, pose: String = "idle", progress: float = 0.0, state: Dictionary = {}) -> Dictionary:
	if part_id not in ["head", "neck"]: return DragonArt._empty_model(pose)
	return model(row, pose, progress, state, "head")

static func _texture_for(image: Image) -> Texture2D:
	var key: int = image.get_instance_id()
	if _textures.has(key):
		_texture_order.erase(key); _texture_order.append(key); return _textures[key]
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_textures[key] = texture; _texture_order.append(key)
	while _texture_order.size() > TEXTURE_CACHE_LIMIT: _textures.erase(_texture_order.pop_front())
	return texture

static func clear_texture_cache() -> void:
	_textures.clear(); _texture_order.clear()

static func draw_canvas_model(item: CanvasItem, model_data: Dictionary, origin: Vector2, pixels_per_unit: float, seed: int = 0, restore_transform: Transform2D = Transform2D.IDENTITY) -> void:
	if not bool(model_data.get("valid", false)) or pixels_per_unit <= 0: return
	var to_canvas: Transform2D = Transform2D(0, Vector2(pixels_per_unit, pixels_per_unit), 0, origin)
	var overlays: Array = DragonDamageArt.overlay_layers(model_data["all_parts"], model_data["state"], seed, model_data["regions"])
	if bool(model_data.get("seamless_rest", false)):
		item.draw_set_transform_matrix(to_canvas * model_data["whole_xf"])
		item.draw_texture(_texture_for(model_data["whole_image"]), Vector2.ZERO)
	for part: Dictionary in model_data["parts"]:
		if not bool(model_data.get("seamless_rest", false)):
			item.draw_set_transform_matrix(to_canvas * part["xf"])
			item.draw_texture(_texture_for(part["image"]), Vector2.ZERO)
		for overlay: Dictionary in overlays:
			if String(overlay["part_id"]) != String(part["id"]): continue
			item.draw_set_transform_matrix(to_canvas * overlay["xf"])
			item.draw_texture(_texture_for(overlay["image"]), Vector2.ZERO)
	item.draw_set_transform_matrix(to_canvas)
	for fragment: Dictionary in model_data.get("fragments", []): item.draw_colored_polygon(fragment["points"], fragment["color"])
	item.draw_set_transform_matrix(restore_transform)

static func draw_model(cv: PixelCanvas, model_data: Dictionary, origin: Vector2, pixels_per_unit: float, seed: int = 0) -> void:
	if not bool(model_data.get("valid", false)): return
	var to_canvas: Transform2D = Transform2D(0, Vector2(pixels_per_unit, pixels_per_unit), 0, origin)
	var drawn: Array = model_data["parts"]
	if bool(model_data.get("seamless_rest", false)): drawn = [{"image": model_data["whole_image"], "xf": model_data["whole_xf"]}]
	for part: Dictionary in drawn:
		var image: Image = part["image"]
		var xf: Transform2D = to_canvas * part["xf"]
		var output: Rect2 = transformed_bounds(Rect2(image.get_used_rect()), xf)
		var inverse: Transform2D = xf.affine_inverse()
		var low: Vector2i = Vector2i(floori(output.position.x), floori(output.position.y)).max(Vector2i.ZERO)
		var high: Vector2i = Vector2i(ceili(output.end.x), ceili(output.end.y)).min(Vector2i(cv.w, cv.h))
		var pixels: Dictionary = {"size": Vector2(image.get_size()), "bytes": image.get_data()}
		for y: int in range(low.y, high.y):
			for x: int in range(low.x, high.x):
				var color: Color = DragonArt._sample(pixels, inverse * Vector2(x + 0.5, y + 0.5))
				if color.a > 0.003: cv.set_px(x, y, color)
	DragonDamageArt.draw_overlay(cv, model_data["all_parts"], model_data["state"], origin, pixels_per_unit, seed, model_data["regions"])
	DragonDamageArt.draw_fragments(cv, model_data.get("fragments", []), origin, pixels_per_unit)
