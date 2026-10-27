extends RefCounted
## v0.064 verification & image capture: all 16 dragon colours and 6 breeds drawn
## in 2.5D code art with dorsal between-shoulders rider seat, across all 5 sizes.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL dragon colours v064: " + why)

static func _rider_spec(seed_val: int = 63) -> Dictionary:
	var spec := FigurePainter.spec_generic("human", Color("#2f6880"), Color("#d9bd71"), seed_val)
	spec["sex"] = "male"
	spec["age"] = 29
	spec["clothing"] = {"tid": "tunic", "mat": "linen", "q": 1}
	spec["body"] = {"tid": "cuirass", "sprite": "cuirass", "mat": "steel", "q": 2}
	spec["head"] = {"tid": "nasal_helm", "sprite": "nasal_helm", "mat": "steel", "q": 2}
	spec["feet"] = {"tid": "boots", "sprite": "boots", "mat": "leather", "q": 1}
	spec["weapon"] = {"tid": "arming_sword", "sprite": "arming_sword", "mat": "steel", "q": 2, "reach": 95.0, "two": false}
	return spec

static func _composite_pair(whole: Image, close: Image) -> Image:
	var out := Image.create(960, 360, false, Image.FORMAT_RGBA8)
	out.fill(Color("121116"))
	var w_scaled := whole.duplicate()
	w_scaled.resize(540, 315, Image.INTERPOLATE_BILINEAR)
	var c_scaled := close.duplicate()
	c_scaled.resize(390, 228, Image.INTERPOLATE_BILINEAR)
	out.blit_rect(w_scaled, Rect2i(0, 0, 540, 315), Vector2i(10, 22))
	out.blit_rect(c_scaled, Rect2i(0, 0, 390, 228), Vector2i(560, 66))
	return out

static func _render_sapphire_v063_before(spec: Dictionary, closeup: bool) -> Image:
	# Reconstruct the exact pre-v0.064 Sapphire Spirewing seat (seat_px = [70, 46+d] at neck base).
	var row := {"id": "dragon:v063:sapphire", "name": "Sapphire", "gem_id": "sapphire", "morph_id": "spirewing",
		"size_class": "medium", "appearance_seed": 27, "stage": "adult", "alive": true}
	DragonRigArt._sources.erase("sapphire_spirewing/frame0")
	DragonRigArt._sources.erase("sapphire_spirewing/frame1")
	var entry := SapphireSpirewingArt.metadata(0)
	var d: int = 3 - SapphireSpirewingArt.BOB[0]
	entry["source_origin_px"] = [70, 49]
	entry["seat_px"] = [70, 46 + d]
	entry["wing_roots_px"] = {"left": [64, 45 + d], "right": [68, 47 + d]}
	entry["parts"]["body"]["pivot_px"] = [70, 46 + d]
	var img := SapphireSpirewingArt.frame(0)
	var size := img.get_size()
	var definitions: Dictionary = entry["parts"]
	var ownership := PackedByteArray()
	ownership.resize(size.x * size.y); ownership.fill(0)
	for id: String in ["head", "jaw"]:
		DragonRigArt._fill(ownership, size.x, Rect2i(Vector2i.ZERO, size), definitions[id]["polygons"], DragonRigArt.ORDER.find(id))
	var raw := img.get_data()
	var layers := {}
	for id: String in DragonRigArt.ORDER:
		var def: Dictionary = definitions[id]
		var crop: Rect2i = Rect2i(Vector2i.ZERO, size) if id == "body" else DragonRigArt._polygon_bounds(def["polygons"], size)
		var mask := PackedByteArray()
		mask.resize(crop.size.x * crop.size.y)
		for y in crop.size.y:
			for x in crop.size.x:
				mask[y * crop.size.x + x] = 1 if ownership[(y + crop.position.y) * size.x + x + crop.position.x] == DragonRigArt.ORDER.find(id) else 0
		layers[id] = {"id": id, "label": def.get("label", id), "parent": String(def.get("parent", "")),
			"source_rect": crop, "mask": mask, "pivot_px": DragonRigArt._point(def["pivot_px"]),
			"painter_order": DragonRigArt.ORDER.find(id), "image": DragonRigArt._extract(raw, size, crop, mask)}
	var regions := {}
	for id: String in entry["anatomical_regions"]:
		var def: Dictionary = entry["anatomical_regions"][id]
		var crop := DragonRigArt._polygon_bounds(def.get("polygons", []), size)
		var mask := PackedByteArray()
		mask.resize(crop.size.x * crop.size.y)
		DragonRigArt._fill(mask, crop.size.x, crop, def.get("polygons", []), 1)
		var owner := String(def.get("owner_part_id", "body"))
		for y in crop.size.y:
			for x in crop.size.x:
				if ownership[(y + crop.position.y) * size.x + x + crop.position.x] != DragonRigArt.ORDER.find(owner):
					mask[y * crop.size.x + x] = 0
		regions[id] = {"id": id, "owner_part_id": owner, "source_rect": crop, "mask": mask, "definition": def}
	var source := {"key": "sapphire_v063_before/frame0/coherent", "entry": entry, "size": Vector2(size), "bytes": raw,
		"image": img, "ownership": ownership, "parts": layers, "regions": regions, "preserve": [], "gems": []}
	source["neck_contacts"] = DragonRigArt._neck_contacts(entry, raw, ownership, size)
	DragonRigArt._sources["sapphire_spirewing/frame0"] = source
	var out := DragonMountPreviewArt.image_for(row, spec, "ground", closeup, 0.0)
	DragonRigArt._sources.erase("sapphire_spirewing/frame0")
	DragonRigArt._images.clear()
	DragonRigArt._image_order.clear()
	return out

func run(_tree: SceneTree) -> int:
	var gems: Array = Dragons.catalogs().get("gems", [])
	var morphs: Array = Dragons.catalogs().get("morphs", [])
	var sizes: Array = Dragons.catalogs().get("sizes", [])
	check(gems.size() == 16 and morphs.size() == 6 and sizes.size() == 5, "16 gems, 6 breeds, 5 sizes in catalog")
	var spec := _rider_spec(63)
	var out_dir := ProjectSettings.globalize_path("res://../test-results")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 1. Verify all 16 colours x 6 breeds and capture before/after pairs per colour.
	for gem: Dictionary in gems:
		var gid := String(gem["id"])
		var mid := String(DragonConcepts.entry(gid).get("morph_id", "spirewing"))
		var before_whole: Image
		var before_close: Image
		if gid == "sapphire":
			before_whole = _render_sapphire_v063_before(spec, false)
			before_close = _render_sapphire_v063_before(spec, true)
		else:
			var classic_row := {"id": "dragon:before:" + gid, "name": String(gem["name"]), "gem_id": gid, "morph_id": mid,
				"size_class": "medium", "appearance_seed": 27, "stage": "adult", "alive": true, "sprite_id": "classic"}
			before_whole = DragonMountPreviewArt.image_for(classic_row, spec, "ground", false, 0.0)
			before_close = DragonMountPreviewArt.image_for(classic_row, spec, "ground", true, 0.0)
		var before_sheet := _composite_pair(before_whole, before_close)
		var before_path := out_dir.path_join("v0064_%s_before.png" % gid)
		check(before_sheet.save_png(before_path) == OK, "saved " + before_path)

		var after_row := {"id": "dragon:after:" + gid, "name": String(gem["name"]), "gem_id": gid, "morph_id": mid,
			"size_class": "medium", "appearance_seed": 27, "stage": "adult", "alive": true}
		var variant := DragonSpriteCatalog.variant_for(after_row)
		check(not variant.is_empty() and String(variant["gem_id"]) == gid and String(variant["morph_id"]) == mid, gid + " resolves to 2.5D code-drawn variant by default")
		var framing := DragonMountPreviewArt.framing(after_row, spec, "ground", false, 0.0)
		check(bool(framing.get("valid", false)) and bool(framing.get("mountable", false)), gid + " mount preview framing is valid")
		var meta := SapphireSpirewingArt.metadata_for(gid, mid, 1)
		var seat_x := float(meta["seat_px"][0])
		check(seat_x >= float(meta["wing_roots_px"]["left"][0]) and seat_x <= float(meta["wing_roots_px"]["right"][0]) and seat_x < float(meta["neck_root_px"][0]), gid + " rider seat is between the shoulders behind neck root")
		var after_whole := DragonMountPreviewArt.image_for(after_row, spec, "ground", false, 0.0)
		var after_close := DragonMountPreviewArt.image_for(after_row, spec, "ground", true, 0.0)
		check(after_whole.get_data() != before_whole.get_data() and after_close.get_data() != before_close.get_data(), gid + " after render differs from before render")
		var after_sheet := _composite_pair(after_whole, after_close)
		var after_path := out_dir.path_join("v0064_%s_after.png" % gid)
		check(after_sheet.save_png(after_path) == OK, "saved " + after_path)

	# 2. Capture lineup sheets of every dragon colour with a rider at each size (small, medium, large, huge, colossal).
	var cell_w := 360
	var cell_h := 210
	var cols := 4
	var rows_n := 4
	var size_strips: Array[Image] = []
	for size_def: Dictionary in sizes:
		var sid := String(size_def["id"])
		var sheet := Image.create(cols * cell_w, rows_n * cell_h, false, Image.FORMAT_RGBA8)
		sheet.fill(Color("121116"))
		for idx in gems.size():
			var gem: Dictionary = gems[idx]
			var gid := String(gem["id"])
			var mid := String(DragonConcepts.entry(gid).get("morph_id", "spirewing"))
			var d_row := {"id": "dragon:lineup:%s:%s" % [sid, gid], "name": String(gem["name"]),
				"gem_id": gid, "morph_id": mid, "size_class": sid, "appearance_seed": 27, "stage": "adult", "alive": true}
			var img := DragonMountPreviewArt.image_for(d_row, spec, "ground", false, 0.18)
			var cell := img.duplicate()
			cell.resize(cell_w, cell_h, Image.INTERPOLATE_BILINEAR)
			var gx := (idx % cols) * cell_w
			var gy := int(idx / cols) * cell_h
			sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i(gx, gy))
		var lineup_path := out_dir.path_join("v0064_lineup_%s.png" % sid)
		check(sheet.save_png(lineup_path) == OK, "saved lineup sheet " + lineup_path)
		var strip := sheet.duplicate()
		strip.resize(720, 420, Image.INTERPOLATE_BILINEAR)
		size_strips.append(strip)

	# Also save a combined master lineup sheet across all 5 sizes.
	var master := Image.create(720 * 5, 420, false, Image.FORMAT_RGBA8)
	master.fill(Color("121116"))
	for s_idx in size_strips.size():
		master.blit_rect(size_strips[s_idx], Rect2i(0, 0, 720, 420), Vector2i(s_idx * 720, 0))
	var master_path := out_dir.path_join("v0064_lineup_all_sizes.png")
	check(master.save_png(master_path) == OK, "saved master lineup sheet " + master_path)

	DragonRigArt.clear_texture_cache()
	print("Dragon colours v064: %d checks, %d failures" % [checks, fails])
	return fails
