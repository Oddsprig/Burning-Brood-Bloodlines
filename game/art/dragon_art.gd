class_name DragonArt
extends RefCounted
## Coherent source textures in native logical units. Human height remains24.
## Host catalog scale never enlarges the rider. Missing assets fail visibly in logs.
const IMAGE_SIZE := Vector2i(720, 420)
const SUPPORTED_POSES := ["rest", "ground", "idle", "walk", "prepare", "strike", "recover", "hit", "block", "dodge", "prone", "dead"]
static var _assets: Dictionary = {}
static var _tints: Dictionary = {}
static var _tint_order: Array[String] = []
const TINT_CACHE_LIMIT := 18

static func _entry(group: String, id: String) -> Dictionary:
	for row: Dictionary in Dragons.catalogs().get(group, []):
		if String(row.get("id", "")) == id: return row
	return {}

static func _point(entry: Dictionary, key: String, size: Vector2) -> Vector2:
	var value: Array = entry[key]
	return Vector2(float(value[0]), float(value[1])) * size

static func _rect(value: Array, size: Vector2) -> Rect2:
	return Rect2(Vector2(float(value[0]), float(value[1])) * size, Vector2(float(value[2]), float(value[3])) * size)

static func _empty_model(pose: String) -> Dictionary:
	return {"valid": false, "pose": pose, "supported_poses": SUPPORTED_POSES.duplicate(), "linear_scale": 1.0, "seat": Vector2.ZERO,
		"seat_angle": 0.0, "saddle": Rect2(), "seat_width": 0.0, "rider_height": 24.0,
		"rider_scale": 1.0, "neck_root": Vector2.ZERO, "left_wing_root": Vector2.ZERO,
		"right_wing_root": Vector2.ZERO, "ground_y": 0.0, "bounds": Rect2(),
		"head_crop": Rect2(), "seat_clearance": Rect2(), "geometry": {"neck_mid": Vector2.ZERO, "head": Vector2.ZERO},
		"parts": [], "all_parts": [], "regions": [], "fragments": [], "state": {}, "mountable": false,
		"hind_legs": 2, "wing_forelimbs": 2, "front_legs": 0}

## Original RGBA proof bypasses gem pigmentation and all animation.
static func source_image(row: Dictionary) -> Image:
	return DragonRigArt.source_image(row)

static func reconstruct_source(row: Dictionary) -> Image:
	return DragonRigArt.reconstruct_source(row)

static func labelled_source_layers(row: Dictionary) -> Array:
	return DragonRigArt.labelled_source_layers(row)

static func model(row: Dictionary, pose: String = "idle", progress: float = 0.0, state: Dictionary = {}) -> Dictionary:
	return DragonRigArt.model(row, pose, progress, state)

static func draw(cv: PixelCanvas, row: Dictionary, pose: String = "idle", origin: Vector2 = Vector2.ZERO, pixels_per_unit: float = 1.0, progress: float = 0.0, state: Dictionary = {}) -> Dictionary:
	var result: Dictionary = model(row, pose, progress, state)
	if not bool(result["valid"]) or pixels_per_unit <= 0: return result
	DragonRigArt.draw_model(cv, result, origin, pixels_per_unit, int(row.get("appearance_seed", 0)))
	return _canvas_model(result, origin, pixels_per_unit)

## Live CanvasItem rendering: cached part textures, no per-frame software image.
## Returned sockets match draw(), in this item's canvas pixel coordinates.
static func draw_canvas(item: CanvasItem, row: Dictionary, pose: String = "idle", origin: Vector2 = Vector2.ZERO, pixels_per_unit: float = 1.0, progress: float = 0.0, state: Dictionary = {}, restore_transform: Transform2D = Transform2D.IDENTITY) -> Dictionary:
	var result: Dictionary = model(row, pose, progress, state)
	if not bool(result["valid"]) or pixels_per_unit <= 0: return result
	DragonRigArt.draw_canvas_model(item, result, origin, pixels_per_unit, int(row.get("appearance_seed", 0)), restore_transform)
	return _canvas_model(result, origin, pixels_per_unit)

static func _canvas_model(result: Dictionary, origin: Vector2, pixels_per_unit: float) -> Dictionary:
	var world_to_canvas: Transform2D = Transform2D(0, Vector2(pixels_per_unit, pixels_per_unit), 0, origin)
	for key: String in ["seat", "neck_root", "left_wing_root", "right_wing_root"]: result[key] = origin + result[key] * pixels_per_unit
	for key: String in ["saddle", "bounds", "seat_clearance", "head_crop"]:
		var area: Rect2 = result[key]
		result[key] = Rect2(origin + area.position * pixels_per_unit, area.size * pixels_per_unit)
	for key: String in result["geometry"]: result["geometry"][key] = origin + result["geometry"][key] * pixels_per_unit
	for part: Dictionary in result["all_parts"]:
		part["xf"] = world_to_canvas * part["xf"]
		part["bounds"] = DragonRigArt.transformed_bounds(Rect2(part["image"].get_used_rect()), part["xf"])
		for key: String in ["attachment", "anchor_start", "anchor_end"]: part[key] = world_to_canvas * part[key]
	for region: Dictionary in result.get("regions", []):
		region["xf"] = world_to_canvas * region["xf"]
		region["bounds"] = DragonRigArt.transformed_bounds(Rect2(region["image"].get_used_rect()), region["xf"])
		for key: String in ["anchor_start", "anchor_end", "cut_point"]:
			if region.has(key): region[key] = world_to_canvas * region[key]
		if region.has("cut_line"):
			var line: PackedVector2Array = PackedVector2Array()
			for point: Vector2 in region["cut_line"]: line.append(world_to_canvas * point)
			region["cut_line"] = line
	if result.has("whole_xf"): result["whole_xf"] = world_to_canvas * result["whole_xf"]
	result["ground_y"] = origin.y + float(result["ground_y"]) * pixels_per_unit
	result["seat_width"] = float(result["seat_width"]) * pixels_per_unit
	result["rider_height"] = 24.0 * pixels_per_unit
	result["rider_scale"] = pixels_per_unit
	return result
## Source PNG pigmentation is prepared once per asset/type/subtle individual shade.
## Bound the byte cache; rendering never rescans source colours on a cache hit.
static func _tinted(asset: Dictionary, row: Dictionary, base: Color, accent: Color) -> Dictionary:
	var job := _tint_job(asset, row, base, accent)
	var key: String = job["key"]
	if _tints.has(key):
		_tint_order.erase(key); _tint_order.append(key)
		return _tints[key]
	var bytes: PackedByteArray = _load_tint(key, (job["original"] as PackedByteArray).size())
	if bytes.is_empty():
		bytes = _tint_compute(job)
		_save_tint(key, bytes)
	var tinted: Dictionary = {"bytes": bytes, "size": asset["size"]}
	_tints[key] = tinted; _tint_order.append(key)
	while _tint_order.size() > TINT_CACHE_LIMIT:
		_tints.erase(_tint_order.pop_front())
	return tinted

## Everything the pigment pass needs, as plain values (safe to hand to a worker thread).
static func _tint_job(asset: Dictionary, row: Dictionary, base: Color, accent: Color) -> Dictionary:
	var shade: int = posmod(int(row.get("appearance_seed", 0)), 7) - 3
	var gem_id: String = String(row.get("gem_id", ""))
	var material_mask: PackedByteArray = DragonSpriteCatalog.material_mask(String(row.get("morph_id", "")), Vector2i(asset["size"]))
	var key: String = "%s/%s/%d/%d" % [asset["key"], gem_id, shade, hash(material_mask)]
	return {"key": key, "original": asset["bytes"], "size": asset["size"], "gems": asset["gems"], "material_mask": material_mask,
		"base": base, "accent": accent, "gem_id": gem_id, "shade": shade}

## Pure per-pixel pigment pass (no statics touched).
static func _tint_compute(job: Dictionary) -> PackedByteArray:
	var original: PackedByteArray = job["original"]
	var bytes: PackedByteArray = original.duplicate()
	var size: Vector2 = job["size"]
	var width: int = int(size.x)
	var base: Color = job["base"]; var accent: Color = job["accent"]; var gem_id: String = job["gem_id"]
	var gain: float = 1.0 + float(int(job["shade"])) * 0.009
	var pigment_asset: Dictionary = {"size": size, "gems": job["gems"], "material_mask": job["material_mask"]}
	for y in int(size.y):
		for x in width:
			var i: int = (y * width + x) * 4
			if original[i + 3] == 0: continue
			var source: Color = Color(original[i] / 255.0, original[i + 1] / 255.0, original[i + 2] / 255.0, original[i + 3] / 255.0)
			var color: Color = _tint(source, Vector2(x + 0.5, y + 0.5), pigment_asset, base, accent, gem_id)
			# Keep native art light direction; individual variation is modest diffuse shade.
			bytes[i] = int(clampf(color.r * gain, 0, 1) * 255)
			bytes[i + 1] = int(clampf(color.g * gain, 0, 1) * 255)
			bytes[i + 2] = int(clampf(color.b * gain, 0, 1) * 255)
			bytes[i + 3] = original[i + 3]
	return bytes

## Pigmented sources are cached on disk (user://dragon_tints), so each dragon variety is painted once per install.
const TINT_DIR := "user://dragon_tints"
const TINT_VERSION := 1
static var _warm_tasks: Array = []

static func _tint_path(key: String) -> String:
	return TINT_DIR.path_join("%s_v%d.bin" % [key.sha256_text().substr(0, 24), TINT_VERSION])

static func _load_tint(key: String, length: int) -> PackedByteArray:
	var path := _tint_path(key)
	if not FileAccess.file_exists(path): return PackedByteArray()
	var packed := FileAccess.get_file_as_bytes(path)
	if packed.is_empty(): return PackedByteArray()
	var out := packed.decompress(length, FileAccess.COMPRESSION_ZSTD)
	return out if out.size() == length else PackedByteArray()

static func _save_tint(key: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(TINT_DIR)
	var path := _tint_path(key)
	var tmp := path + ".%d.tmp" % OS.get_thread_caller_id()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return
	f.store_buffer(bytes.compress(FileAccess.COMPRESSION_ZSTD))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))

## Paint the pigment of these dragons on worker threads (to disk), so screens and battles open without a stall.
static func warm(rows: Array) -> int:
	var started := 0
	var seen := {}
	for row: Dictionary in rows:
		if str(row.get("stage", "egg")) == "egg" or not bool(row.get("alive", true)): continue
		var source: Dictionary = DragonRigArt._source(row)
		if source.is_empty(): continue
		var gem: Dictionary = _entry("gems", String(row.get("gem_id", "")))
		if gem.is_empty(): continue
		var job := _tint_job(source, row, Color(String(gem["base"])), Color(String(gem["accent"])))
		var key: String = job["key"]
		if seen.has(key) or _tints.has(key) or FileAccess.file_exists(_tint_path(key)): continue
		seen[key] = true
		_warm_tasks.append(WorkerThreadPool.add_task(func(): _save_tint(key, _tint_compute(job)), true, "Dragon pigment"))
		started += 1
	return started

static func finish_warm() -> void:
	for id in _warm_tasks: WorkerThreadPool.wait_for_task_completion(int(id))
	_warm_tasks.clear()

static func _pixel(asset: Dictionary, x: int, y: int) -> Color:
	var size: Vector2 = asset["size"]
	if x < 0 or y < 0 or x >= int(size.x) or y >= int(size.y): return Color.TRANSPARENT
	var bytes: PackedByteArray = asset["bytes"]
	var i: int = (y * int(size.x) + x) * 4
	return Color(bytes[i] / 255.0, bytes[i + 1] / 255.0, bytes[i + 2] / 255.0, bytes[i + 3] / 255.0)

static func _sample(asset: Dictionary, at: Vector2) -> Color:
	var q: Vector2 = at - Vector2(0.5, 0.5)
	var x: int = floori(q.x); var y: int = floori(q.y)
	var fx: float = q.x - x; var fy: float = q.y - y
	# Premultiplied filtering avoids dark fringes at transparent PNG edges.
	var rgba: Vector4 = Vector4.ZERO
	for iy in 2:
		for ix in 2:
			var color: Color = _pixel(asset, x + ix, y + iy)
			var weight: float = (fx if ix == 1 else 1 - fx) * (fy if iy == 1 else 1 - fy)
			rgba += Vector4(color.r * color.a, color.g * color.a, color.b * color.a, color.a) * weight
	if rgba.w < 0.00001: return Color.TRANSPARENT
	return Color(rgba.x / rgba.w, rgba.y / rgba.w, rgba.z / rgba.w, rgba.w)

static func _tint(source: Color, at: Vector2, asset: Dictionary, base: Color, accent: Color, gem_id: String) -> Color:
	var material_mask: PackedByteArray = asset.get("material_mask", PackedByteArray())
	var source_size: Vector2 = asset["size"]
	var index: int = floori(at.y) * int(source_size.x) + floori(at.x)
	var flags: int = material_mask[index] if index >= 0 and index < material_mask.size() else 0
	if (flags & DragonSpriteCatalog.EYE_MASK) != 0: return source
	var luminance: float = source.r * 0.2126 + source.g * 0.7152 + source.b * 0.0722
	if (flags & DragonSpriteCatalog.HORN_MASK) != 0:
		# Gem hue throughout the horn, including dark/neutral source edges.
		# Original luminance keeps its curved planes, grooves and highlights.
		var horn_saturation: float = clampf(base.s * 0.95 + 0.1, 0.12, 0.94)
		var horn_brightness: float = clampf(luminance * 1.04, 0, 1)
		if gem_id in ["black_diamond", "onyx"]: horn_brightness = luminance * 0.38; horn_saturation = 0.14
		elif gem_id in ["opal", "pearl", "diamond", "moonstone"]: horn_saturation = clampf(base.s * 0.65, 0.03, 0.28)
		var horn: Color = Color.from_hsv(base.h, horn_saturation, horn_brightness, source.a)
		horn = horn.lerp(accent, maxf(0, luminance - 0.64) * 0.42)
		horn.a = source.a
		return horn
	for area: Rect2 in asset["gems"]:
		if area.has_point(at) and luminance > 0.63 and source.s < 0.24:
			var weapon: Color = base.lerp(accent, clampf(luminance * luminance, 0, 1))
			weapon = weapon.lightened(maxf(0, luminance - 0.72) * 0.55)
			weapon.a = source.a
			return weapon
	# Bronze/desaturated skin gets pigment, preserving diffuse shade and texture.
	# Non-neutral coloured eyes and pale highlights survive unless region-tagged.
	if source.s > 0.24 and source.h > 0.21 and source.h < 0.85: return source
	if source.s < 0.09 and luminance > 0.86: return source
	var saturation: float = clampf(base.s * 0.75, 0.16, 0.72)
	var brightness: float = luminance * 0.86
	if gem_id in ["black_diamond", "onyx"]: brightness = luminance * 0.34; saturation = 0.13
	elif gem_id in ["opal", "pearl", "diamond", "moonstone"]: brightness = luminance * 0.96; saturation = clampf(base.s * 0.55, 0.05, 0.23)
	var color: Color = Color.from_hsv(base.h, saturation, clampf(brightness, 0, 1), source.a)
	return color

static func framing(row: Dictionary, pose: String = "idle", image_size: Vector2i = IMAGE_SIZE, progress: float = 0.0, state: Dictionary = {}) -> Dictionary:
	var info: Dictionary = model(row, pose, progress, state)
	if not bool(info["valid"]): return {"origin": Vector2.ZERO, "pixels_per_unit": 1.0, "bounds": Rect2(), "valid": false}
	var bounds: Rect2 = info["bounds"]
	bounds = bounds.merge(Rect2(info["seat"] + Vector2(-12, -28), Vector2(29, 43)))
	var raster: float = minf((image_size.x - 54.0) / maxf(1, bounds.size.x), (image_size.y - 52.0) / maxf(1, bounds.size.y))
	return {"origin": Vector2(image_size) * 0.5 - bounds.get_center() * raster, "pixels_per_unit": raster, "bounds": bounds, "valid": true}

static func image_for(row: Dictionary, pose: String = "idle", progress: float = 0.0, state: Dictionary = {}) -> Image:
	var cv: PixelCanvas = PixelCanvas.new(IMAGE_SIZE.x, IMAGE_SIZE.y)
	var frame: Dictionary = framing(row, pose, IMAGE_SIZE, progress, state)
	if bool(frame["valid"]): draw(cv, row, pose, frame["origin"], float(frame["pixels_per_unit"]), progress, state)
	return cv.to_image()

static func portrait_for(row: Dictionary, pose: String = "idle", progress: float = 0.0, state: Dictionary = {}) -> Image:
	const SIDE := 384
	var cv: PixelCanvas = PixelCanvas.new(SIDE, SIDE)
	var info: Dictionary = model(row, pose, progress, state)
	if not bool(info["valid"]): return cv.to_image()
	var bounds: Rect2 = info["head_crop"]
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		push_error("Dragon rig portrait crop is empty for " + String(row.get("morph_id", ""))); return cv.to_image()
	var raster: float = minf((SIDE - 24.0) / bounds.size.x, (SIDE - 24.0) / bounds.size.y)
	var origin: Vector2 = Vector2(SIDE, SIDE) * 0.5 - bounds.get_center() * raster
	draw(cv, row, pose, origin, raster, progress, state)
	return cv.to_image()

static func piece_for(row: Dictionary, part_id: String, pose: String = "idle", progress: float = 0.0, state: Dictionary = {}) -> Image:
	var cv: PixelCanvas = PixelCanvas.new(384, 384)
	var piece: Dictionary = DragonRigArt.detached(row, part_id, pose, progress, state)
	if not bool(piece.get("valid", false)): return cv.to_image()
	var bounds: Rect2 = piece["bounds"]
	var raster: float = minf(340 / maxf(1, bounds.size.x), 340 / maxf(1, bounds.size.y))
	DragonRigArt.draw_model(cv, piece, Vector2(192, 192) - bounds.get_center() * raster, raster, int(row.get("appearance_seed", 0)))
	return cv.to_image()
