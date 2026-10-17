class_name MemoryOwners
extends RefCounted
## Explicit, bounded checkpoints. Only plain counters survive a scan.
## Containers count traversal occurrences, not unique allocations or RAM bytes.
const ROOTS := ["company", "world", "pending_battle", "last_result", "_deploy_cache"]
const UNIT_FIELDS := ["attrs", "attr_xp", "attr_base", "attr_cap", "talent", "personality", "skills", "skill_xp", "equip", "quiver", "overrides", "body", "look", "notable", "mind", "values", "needs", "kill_list", "skill_idle", "food_attr_mult", "_food_attrs"]
const BODY_FIELDS := ["parts", "permanent"]
const ITEM_FIELDS := ["mark", "legend"]
const MAX_DEPTH := 48

static func _counts() -> Dictionary:
	return {"unit_unique": 0, "unit_refs": 0, "body_unique": 0, "body_refs": 0, "item_unique": 0, "item_refs": 0,
		"dictionaries": 0, "arrays": 0, "container_entries": 0, "packed_arrays": 0, "packed_elements": 0, "packed_numeric_bytes": 0,
		"string_characters": 0, "wound_parts": 0, "wound_layers": 0, "other_objects": 0}

static func capture(game: Object, label: String = "Manual checkpoint", max_values: int = 250000, max_us: int = 20000) -> Dictionary:
	var started: int = Time.get_ticks_usec()
	var totals: Dictionary = _counts()
	var context: Dictionary = {"start": started, "max_values": clampi(max_values, 1, 2000000), "max_us": clampi(max_us, 100, 200000),
		"visited": 0, "truncated": false, "depth_limited": false, "global_ids": {}, "root_ids": {}, "total": totals}
	var roots: Dictionary = {}
	for root: String in ROOTS:
		var counts: Dictionary = _counts()
		context["root_ids"] = {}
		roots[root.trim_prefix("_")] = counts
		if game != null and not bool(context["truncated"]): _walk(game.get(root), counts, context, 0)
	var result: Dictionary = {"available": game != null, "label": label.left(64), "captured_us": Time.get_ticks_usec(),
		"elapsed_us": Time.get_ticks_usec() - started, "visited": context["visited"], "truncated": context["truncated"],
		"depth_limited": context["depth_limited"], "limits": {"values": context["max_values"], "us": context["max_us"], "depth": MAX_DEPTH},
		"totals": totals, "by_root": roots, "scope": "Native IDs unique; containers and numeric packed bytes are traversal occurrences across roots and listed native fields. Partial scans are lower bounds; no allocator/object overhead or total RAM estimate."}
	result["caches"] = cache_payloads()
	result["elapsed_us"] = Time.get_ticks_usec() - started
	# Do not retain context, objects, containers, native instances or their references.
	return result

static func _add(counts: Dictionary, context: Dictionary, key: String, amount: int = 1) -> void:
	counts[key] = int(counts[key]) + amount
	var totals: Dictionary = context["total"]
	totals[key] = int(totals[key]) + amount

static func _walk(value: Variant, counts: Dictionary, context: Dictionary, depth: int) -> void:
	if bool(context["truncated"]): return
	var visited: int = int(context["visited"]) + 1
	context["visited"] = visited
	if visited > int(context["max_values"]) or Time.get_ticks_usec() - int(context["start"]) >= int(context["max_us"]):
		context["truncated"] = true
		return
	if depth >= MAX_DEPTH:
		context["depth_limited"] = true
		return
	match typeof(value):
		TYPE_DICTIONARY:
			_add(counts, context, "dictionaries")
			_add(counts, context, "container_entries", value.size())
			for key: Variant in value:
				_walk(value[key], counts, context, depth + 1)
				if bool(context["truncated"]): break
		TYPE_ARRAY:
			_add(counts, context, "arrays")
			_add(counts, context, "container_entries", value.size())
			for child: Variant in value:
				_walk(child, counts, context, depth + 1)
				if bool(context["truncated"]): break
		TYPE_STRING, TYPE_STRING_NAME:
			_add(counts, context, "string_characters", String(value).length())
		TYPE_OBJECT:
			if value == null or not is_instance_valid(value): return
			var type_name: String = "unit" if value is Unit else ("body" if value is BodyState else ("item" if value is Item else ""))
			if type_name == "":
				_add(counts, context, "other_objects")
				return
			_add(counts, context, type_name + "_refs")
			var instance_id: int = value.get_instance_id()
			var all_ids: Dictionary = context["global_ids"]
			if not all_ids.has(instance_id):
				all_ids[instance_id] = true
				var totals: Dictionary = context["total"]
				totals[type_name + "_unique"] = int(totals[type_name + "_unique"]) + 1
				if value is BodyState:
					totals["wound_parts"] = int(totals["wound_parts"]) + value.parts.size()
					for part_id: Variant in value.parts: totals["wound_layers"] = int(totals["wound_layers"]) + (value.parts[part_id].get("layers", []) as Array).size()
			var root_ids: Dictionary = context["root_ids"]
			if root_ids.has(instance_id): return
			root_ids[instance_id] = true
			counts[type_name + "_unique"] = int(counts[type_name + "_unique"]) + 1
			if value is BodyState:
				counts["wound_parts"] = int(counts["wound_parts"]) + value.parts.size()
				for part_id: Variant in value.parts: counts["wound_layers"] = int(counts["wound_layers"]) + (value.parts[part_id].get("layers", []) as Array).size()
			var fields: Array = UNIT_FIELDS if value is Unit else (BODY_FIELDS if value is BodyState else ITEM_FIELDS)
			for field: String in fields:
				_walk(value.get(field), counts, context, depth + 1)
				if bool(context["truncated"]): break
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_STRING_ARRAY:
			_add(counts, context, "packed_arrays")
			_add(counts, context, "packed_elements", value.size())
			var width: int = 0
			match typeof(value):
				TYPE_PACKED_BYTE_ARRAY: width = 1
				TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY: width = 4
				TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY: width = 8
				TYPE_PACKED_VECTOR3_ARRAY: width = 12
				TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY: width = 16
			_add(counts, context, "packed_numeric_bytes", value.size() * width)

static func cache_payloads() -> Dictionary:
	var context: Dictionary = {"seen": {}, "visited": 0, "truncated": false, "images": 0, "textures": 0,
		"image_rgba_equivalent_bytes": 0, "texture_rgba_equivalent_bytes": 0, "packed_byte_occurrences": 0}
	# Inspect existing bounded caches only; never render, load images or request a spec.
	for cache: Dictionary in [DragonRigArt._sources, DragonRigArt._images, DragonRigArt._textures, DragonArt._tints, DragonSpriteCatalog._material_masks, DragonDamageArt._decals]:
		_cache_walk(cache, context, 0)
	context.erase("seen")
	context["source_forms"] = DragonRigArt._sources.size()
	context["tinted_sources"] = DragonArt._tints.size()
	context["dragon_image_sets"] = DragonRigArt._images.size()
	context["dragon_textures"] = DragonRigArt._textures.size()
	context["item_icon_entries"] = ItemIcon.cache_size()
	context["map_token_textures"] = MapTokens._tex.size()
	context["map_token_bases"] = MapTokens._base.size()
	context["scope"] = "Dragon cache images/textures deduplicated by ID; RGBA equivalents exclude mipmaps/driver overhead. Packed bytes count references, not unique buffers. Icon/token entry counts only."
	return context

static func _cache_walk(value: Variant, context: Dictionary, depth: int) -> void:
	if depth > 12 or int(context["visited"]) >= 4096:
		context["truncated"] = true
		return
	context["visited"] = int(context["visited"]) + 1
	if value is Image or value is Texture2D:
		var id: int = value.get_instance_id()
		var seen: Dictionary = context["seen"]
		if seen.has(id): return
		seen[id] = true
		var category: String = "images" if value is Image else "textures"
		var payload: String = "image_rgba_equivalent_bytes" if value is Image else "texture_rgba_equivalent_bytes"
		context[category] = int(context[category]) + 1
		context[payload] = int(context[payload]) + value.get_width() * value.get_height() * 4
	elif value is Dictionary:
		for key: Variant in value:
			if key == "entry" or key == "definition": continue
			_cache_walk(value[key], context, depth + 1)
			if bool(context["truncated"]): break
	elif value is Array:
		for child: Variant in value:
			_cache_walk(child, context, depth + 1)
			if bool(context["truncated"]): break
	elif value is PackedByteArray:
		context["packed_byte_occurrences"] = int(context["packed_byte_occurrences"]) + value.size()
