extends RefCounted
## v0.064 / v0.066 verification & image capture: all 16 dragon colours and 6 distinct breed
## silhouettes drawn in 2.5D code art with rider and saddle at the base of the neck,
## clearly in front of the wing roots.
var checks := 0
var fails := 0

const BREED_CANONICAL_GEMS := {
	"spirewing": "sapphire",
	"broadmantle": "ruby",
	"reedrunner": "emerald",
	"ironcrest": "black_diamond",
	"stormkeel": "opal",
	"duskfin": "amethyst",
}

const BREED_COLOUR_SETS := {
	"spirewing": ["sapphire", "moonstone", "diamond"],
	"broadmantle": ["ruby", "topaz", "citrine"],
	"reedrunner": ["emerald", "tourmaline", "citrine"],
	"ironcrest": ["black_diamond", "garnet", "onyx"],
	"stormkeel": ["opal", "jade", "moonstone"],
	"duskfin": ["amethyst", "aquamarine", "pearl"],
}

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

static func _composite_before_after(before_sheet: Image, after_sheet: Image) -> Image:
	var out := Image.create(968, 740, false, Image.FORMAT_RGBA8)
	out.fill(Color("0d0c10"))
	out.fill_rect(Rect2i(2, 2, 964, 364), Color("3c1d24"))
	out.blit_rect(before_sheet, Rect2i(0, 0, 960, 360), Vector2i(4, 4))
	out.fill_rect(Rect2i(2, 374, 964, 364), Color("1e3d2b"))
	out.blit_rect(after_sheet, Rect2i(0, 0, 960, 360), Vector2i(4, 376))
	return out

func run(_tree: SceneTree) -> int:
	var gems: Array = Dragons.catalogs().get("gems", [])
	var morphs: Array = Dragons.catalogs().get("morphs", [])
	var sizes: Array = Dragons.catalogs().get("sizes", [])
	check(gems.size() == 16 and morphs.size() == 6 and sizes.size() == 5, "16 gems, 6 breeds, 5 sizes in catalog")
	var spec := _rider_spec(63)
	var out_dir := ProjectSettings.globalize_path("res://../test-results")
	DirAccess.make_dir_recursive_absolute(out_dir)

	# 1. Verify all 16 colours resolve to their 2.5D code-drawn breed & have neck-base seats forward of wing roots.
	for gem: Dictionary in gems:
		var gid := String(gem["id"])
		var mid := String(DragonConcepts.entry(gid).get("morph_id", "spirewing"))
		var after_row := {"id": "dragon:after:" + gid, "name": String(gem["name"]), "gem_id": gid, "morph_id": mid,
			"size_class": "medium", "appearance_seed": 27, "stage": "adult", "alive": true}
		var variant := DragonSpriteCatalog.variant_for(after_row)
		check(not variant.is_empty() and String(variant["gem_id"]) == gid and String(variant["morph_id"]) == mid, gid + " resolves to 2.5D code-drawn variant by default")
		var framing := DragonMountPreviewArt.framing(after_row, spec, "ground", false, 0.0)
		check(bool(framing.get("valid", false)) and bool(framing.get("mountable", false)), gid + " mount preview framing is valid")
		var meta := SapphireSpirewingArt.metadata_for(gid, mid, 1)
		var seat_x := float(meta["seat_px"][0])
		var seat_y := float(meta["seat_px"][1])
		var wing_r_x := float(meta["wing_roots_px"]["right"][0])
		var wing_l_x := float(meta["wing_roots_px"]["left"][0])
		var neck_x := float(meta["neck_root_px"][0])
		var neck_y := float(meta["neck_root_px"][1])
		check(seat_x >= wing_r_x + 10.0 and wing_r_x > wing_l_x and absf(seat_x - neck_x) <= 4.0 and absf(seat_y - neck_y) <= 4.0, gid + "/" + mid + " rider seat is at the base of the neck and forward of wing roots")
		var model: Dictionary = framing["model"]
		var m_seat := model["seat"] as Vector2
		var m_wing_r := model["right_wing_root"] as Vector2
		var m_wing_l := model["left_wing_root"] as Vector2
		check(m_seat.x > m_wing_r.x and m_wing_r.x > m_wing_l.x, gid + "/" + mid + " logical seat point is forward of logical wing roots")

	# 2. Verify all 6 breeds have distinct silhouette parameters and generate v0066 before/after & closeup sheets.
	var breed_order := ["spirewing", "broadmantle", "reedrunner", "ironcrest", "stormkeel", "duskfin"]
	var spec_sigs := {}
	var closeup_cells: Array[Image] = []
	for mid: String in breed_order:
		var bspec := SapphireSpirewingArt.breed_spec(mid)
		var sig := JSON.stringify([
			bspec.get("torso_points"), bspec.get("torso_radii"),
			bspec.get("neck_points"), bspec.get("head_pos"),
			bspec.get("horn_style"), bspec.get("wing_scale"),
			bspec.get("tail_points"), bspec.get("tail_style"),
			bspec.get("seat_px"), bspec.get("wing_roots_px"),
		])
		spec_sigs[sig] = true
		var gid: String = BREED_CANONICAL_GEMS[mid]
		var a643bfa_path := out_dir.path_join("v0064_%s_after.png" % gid)
		var before_sheet := Image.load_from_file(a643bfa_path)
		check(before_sheet != null and before_sheet.get_size() == Vector2i(960, 360), "loaded a643bfa before sheet for " + mid)
		var row := {"id": "dragon:v066:" + mid, "name": mid.capitalize(), "gem_id": gid, "morph_id": mid,
			"size_class": "medium", "appearance_seed": 27, "stage": "adult", "alive": true}
		var after_whole := DragonMountPreviewArt.image_for(row, spec, "ground", false, 0.0)
		var after_close := DragonMountPreviewArt.image_for(row, spec, "ground", true, 0.0)
		var after_sheet := _composite_pair(after_whole, after_close)
		check(before_sheet == null or after_sheet.get_data() != before_sheet.get_data(), mid + " new render differs from a643bfa render")
		if before_sheet != null:
			var ba_img := _composite_before_after(before_sheet, after_sheet)
			var ba_path := out_dir.path_join("v0066_dragon_before_after_%s.png" % mid)
			check(ba_img.save_png(ba_path) == OK, "saved " + ba_path)
		var close_cell := after_close.duplicate()
		close_cell.resize(480, 280, Image.INTERPOLATE_BILINEAR)
		closeup_cells.append(close_cell)
	check(spec_sigs.size() == 6, "all 6 breeds have distinct silhouette parameter sets")

	# 3. Save v0066_dragon_seat_closeup.png (3x2 grid of neck-base seat closeups with wing roots behind).
	var closeup_sheet := Image.create(480 * 3, 280 * 2, false, Image.FORMAT_RGBA8)
	closeup_sheet.fill(Color("121116"))
	for i in closeup_cells.size():
		var cx := (i % 3) * 480
		var cy := int(i / 3) * 280
		closeup_sheet.blit_rect(closeup_cells[i], Rect2i(0, 0, 480, 280), Vector2i(cx, cy))
	var closeup_path := out_dir.path_join("v0066_dragon_seat_closeup.png")
	check(closeup_sheet.save_png(closeup_path) == OK, "saved " + closeup_path)

	# 4. Save v0066_dragon_breed_lineup.png (all 6 breeds in columns, 3 gem colours per breed in rows).
	var cell_w := 320
	var cell_h := 190
	var lineup_sheet := Image.create(cell_w * 6, cell_h * 3, false, Image.FORMAT_RGBA8)
	lineup_sheet.fill(Color("121116"))
	for b_idx in breed_order.size():
		var mid: String = breed_order[b_idx]
		var colours: Array = BREED_COLOUR_SETS[mid]
		for c_idx in colours.size():
			var gid: String = colours[c_idx]
			var d_row := {"id": "dragon:breed_lineup:%s:%s" % [mid, gid], "name": "%s %s" % [gid.capitalize(), mid.capitalize()],
				"gem_id": gid, "morph_id": mid, "size_class": "medium", "appearance_seed": 27, "stage": "adult", "alive": true}
			var img := DragonMountPreviewArt.image_for(d_row, spec, "ground", false, 0.0)
			var cell := img.duplicate()
			cell.resize(cell_w, cell_h, Image.INTERPOLATE_BILINEAR)
			lineup_sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i(b_idx * cell_w, c_idx * cell_h))
	var lineup_path := out_dir.path_join("v0066_dragon_breed_lineup.png")
	check(lineup_sheet.save_png(lineup_path) == OK, "saved " + lineup_path)

	DragonRigArt.clear_texture_cache()
	print("Dragon colours v064: %d checks, %d failures" % [checks, fails])
	return fails
