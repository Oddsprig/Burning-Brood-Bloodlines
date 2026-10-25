class_name DragonSpriteCatalog
extends RefCounted
## Observed source-image anchors and explicitly selected code-drawn variants.
## Original JSON sources retain their authored pixel cuts and rider sockets.
const PATH := "res://art/dragon_source/source_catalog_v006.json"
static var _catalog: Dictionary = {}
static var _material_masks: Dictionary = {}
const HORN_MASK := 1
const EYE_MASK := 2

static func entries() -> Dictionary:
	if _catalog.is_empty():
		if not FileAccess.file_exists(PATH):
			push_error("Dragon sprite anchor catalog is missing: " + PATH)
			return {}
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not decoded is Dictionary or not decoded.get("entries", {}) is Dictionary:
			push_error("Dragon sprite anchor catalog must contain an entries dictionary.")
			return {}
		_catalog = decoded["entries"].duplicate(true)
	return _catalog.duplicate(true)

## Appearance variants retain the existing gem, body form and physical profile.
static func variants() -> Array:
	return [{"id": "sapphire_spirewing", "name": "Sapphire Spirewing", "gem_id": "sapphire", "morph_id": "spirewing", "frames": SapphireSpirewingArt.FRAME_COUNT}]

static func variants_for(row: Dictionary) -> Array:
	return variants().filter(func(value: Dictionary): return value["gem_id"] == row.get("gem_id", "") and value["morph_id"] == row.get("morph_id", ""))

static func variant_for(row: Dictionary) -> Dictionary:
	if row.get("sprite_id", "") != "sapphire_spirewing": return {}
	for value: Dictionary in variants_for(row):
		if value["id"] == row.get("sprite_id", ""): return value
	return {}

static func source_id(row: Dictionary) -> String:
	var variant := variant_for(row)
	return String(variant["id"]) if not variant.is_empty() else String(row.get("morph_id", ""))

static func source_entry(row: Dictionary, pose: String = "rest", progress: float = 0.0) -> Dictionary:
	if not variant_for(row).is_empty(): return SapphireSpirewingArt.metadata(SapphireSpirewingArt.frame_index(pose, progress))
	return entry(String(row.get("morph_id", "")), pose)

static func frame_count(row: Dictionary, pose: String) -> int:
	if pose == "rest": return 1
	pose = "idle" if pose == "ground" else pose
	if not variant_for(row).is_empty() and pose not in ["prone", "dead"]: return SapphireSpirewingArt.FRAME_COUNT
	return maxi(1, int(FigurePainter.FRAMES.get(pose, 1)))

static func entry(morph_id: String, _pose: String = "rest") -> Dictionary:
	if morph_id == "sapphire_spirewing": return SapphireSpirewingArt.metadata(1)
	var data: Dictionary = entries().get(morph_id, {})
	if data.is_empty(): push_error("Dragon coherent source or observed anchors are missing for " + morph_id)
	return data.duplicate(true)

## Source-shaped material flags: bit1 gem horn, bit2 original eye. Prepared
## once per form, never by scanning polygons for each live animation pixel.
static func material_mask(morph_id: String, image_size: Vector2i) -> PackedByteArray:
	var data: Dictionary = entry(morph_id)
	var materials: Dictionary = data.get("material_masks_px", {})
	var key: String = "%s/%dx%d/%d" % [morph_id, image_size.x, image_size.y, hash(var_to_bytes(materials))]
	if _material_masks.has(key): return _material_masks[key]
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(image_size.x * image_size.y)
	if materials.is_empty():
		push_error("Dragon horn/eye material polygons missing: " + morph_id)
		return mask
	for kind: String in ["horns", "eyes"]:
		var flag: int = HORN_MASK if kind == "horns" else EYE_MASK
		for polygon: Array in materials.get(kind, []):
			if polygon.size() < 3: continue
			var low: float = image_size.y
			var high: float = 0
			for value: Array in polygon:
				low = minf(low, float(value[1])); high = maxf(high, float(value[1]))
			for y: int in range(maxi(0, floori(low)), mini(image_size.y, ceili(high))):
				var centre: float = y + 0.5
				var crossings: Array[float] = []
				for index: int in polygon.size():
					var av: Array = polygon[index]
					var bv: Array = polygon[(index + 1) % polygon.size()]
					var a: Vector2 = Vector2(float(av[0]), float(av[1]))
					var b: Vector2 = Vector2(float(bv[0]), float(bv[1]))
					if (a.y <= centre and b.y > centre) or (b.y <= centre and a.y > centre):
						crossings.append(a.x + (centre - a.y) * (b.x - a.x) / (b.y - a.y))
				crossings.sort()
				for pair: int in range(0, crossings.size() - 1, 2):
					for x: int in range(maxi(0, ceili(crossings[pair] - 0.5)), mini(image_size.x, ceili(crossings[pair + 1] - 0.5))): mask[y * image_size.x + x] |= flag
	_material_masks[key] = mask
	while _material_masks.size() > 6: _material_masks.erase(_material_masks.keys()[0])
	return mask
