extends RefCounted
const SpeedParts = preload("res://tests/fixtures/older_speed_parts_v100.gd")
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
	var speed_cases: Array = ["capture-setup", "colours", "assemble"]
	for breed: String in BREED_CANONICAL_GEMS:
		speed_cases.append("compare:" + breed)
		for gem: String in BREED_COLOUR_SETS[breed]: speed_cases.append("lineup:" + breed + ":" + gem)
	var speed_part: String = SpeedParts.select(speed_cases)
	if speed_part == "": return 1
	var gems: Array = Dragons.catalogs().get("gems", [])
	var morphs: Array = Dragons.catalogs().get("morphs", [])
	var sizes: Array = Dragons.catalogs().get("sizes", [])
	check(gems.size() == 16 and morphs.size() == 6 and sizes.size() == 5, "16 gems, 6 breeds, 5 sizes in catalog")
	var spec := _rider_spec(63)
	var out_dir := ProjectSettings.globalize_path("res://../test-results")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var source_stamp: String = SpeedParts.source_stamp()
	if speed_part == "assemble": return _speed_assemble(out_dir)
	var capture: Dictionary = {}
	var image_handoffs: Array = []
	if speed_part != "colours":
		capture = _speed_capture(out_dir, source_stamp, speed_part == "all" or speed_part == "capture-setup")
		check(not capture.is_empty(), "current capture setup binds code, reference inputs and every image case")
		if capture.is_empty(): return fails
		print("SPEED_CAPTURE id=", capture["capture_id"], " part=", speed_part)
	if speed_part == "capture-setup":
		print("Dragon colours v064 capture setup: %d checks, %d failures" % [checks, fails])
		return fails

	# 1. Verify all 16 colours resolve to their 2.5D code-drawn breed & have neck-base seats forward of wing roots.
	for gem: Dictionary in gems:
		if not SpeedParts.includes(speed_part, "colours"): continue
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
		if not SpeedParts.includes(speed_part, "compare:" + mid): continue
		var close_path: String = out_dir.path_join("older_speed_v064_close_%s.png" % mid)
		var comparison_path: String = out_dir.path_join("v0066_dragon_before_after_%s.png" % mid)
		check(SpeedParts.begin_image_case(close_path, capture, "compare:" + mid), "comparison marker starts incomplete: " + mid)
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
		check(close_cell.save_png(close_path) == OK, "saved lossless closeup handoff " + mid)
		image_handoffs.append({"path": close_path, "case": "compare:" + mid, "outputs": [close_path, comparison_path]})
		closeup_cells.append(close_cell)
	check(spec_sigs.size() == 6, "all 6 breeds have distinct silhouette parameter sets")

	if speed_part == "all":
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
			if not SpeedParts.includes(speed_part, "lineup:" + mid + ":" + gid): continue
			var cell_path: String = out_dir.path_join("older_speed_v064_lineup_%s_%s.png" % [mid, gid])
			check(SpeedParts.begin_image_case(cell_path, capture, "lineup:" + mid + ":" + gid), "lineup marker starts incomplete: " + mid + "/" + gid)
			var d_row := {"id": "dragon:breed_lineup:%s:%s" % [mid, gid], "name": "%s %s" % [gid.capitalize(), mid.capitalize()],
				"gem_id": gid, "morph_id": mid, "size_class": "medium", "appearance_seed": 27, "stage": "adult", "alive": true}
			var img := DragonMountPreviewArt.image_for(d_row, spec, "ground", false, 0.0)
			var cell := img.duplicate()
			cell.resize(cell_w, cell_h, Image.INTERPOLATE_BILINEAR)
			check(cell.save_png(cell_path) == OK, "saved lossless lineup handoff " + mid + "/" + gid)
			image_handoffs.append({"path": cell_path, "case": "lineup:" + mid + ":" + gid, "outputs": [cell_path]})
			lineup_sheet.blit_rect(cell, Rect2i(0, 0, cell_w, cell_h), Vector2i(b_idx * cell_w, c_idx * cell_h))
	var lineup_path := out_dir.path_join("v0066_dragon_breed_lineup.png")
	if speed_part == "all":
		check(lineup_sheet.save_png(lineup_path) == OK, "saved " + lineup_path)

	DragonRigArt.clear_texture_cache()
	# Publish only after ALL selected checks, including six-breed distinctness.
	if fails == 0:
		for handoff: Dictionary in image_handoffs:
			check(SpeedParts.complete_image_case(str(handoff["path"]), capture, str(handoff["case"]), handoff["outputs"]), "capture-pinned case complete: " + str(handoff["case"]))
	print("Dragon colours v064: %d checks, %d failures" % [checks, fails])
	return fails

func _speed_capture(out_dir: String, source: String, create: bool) -> Dictionary:
	var references: Dictionary = {}
	var cases: Array = []
	for breed: String in BREED_CANONICAL_GEMS:
		var reference_path: String = out_dir.path_join("v0064_%s_after.png" % BREED_CANONICAL_GEMS[breed])
		references[reference_path] = FileAccess.get_sha256(reference_path)
		cases.append("compare:" + breed)
		for gem: String in BREED_COLOUR_SETS[breed]: cases.append("lineup:" + breed + ":" + gem)
	var manifest_path: String = out_dir.path_join("older_speed_v064_capture.speed_manifest")
	if create: return SpeedParts.capture_setup(manifest_path, source, references, cases)
	return SpeedParts.capture_load(manifest_path, source, references, cases)

func _speed_assemble(out_dir: String) -> int:
	var source_stamp: String = SpeedParts.source_stamp()
	var capture: Dictionary = _speed_capture(out_dir, source_stamp, false)
	check(not capture.is_empty(), "assemble requires the current code and reference-pinned capture manifest")
	if capture.is_empty(): return fails
	print("SPEED_CAPTURE id=", capture["capture_id"], " part=assemble")
	var breed_order: Array[String] = ["spirewing", "broadmantle", "reedrunner", "ironcrest", "stormkeel", "duskfin"]
	var closeup_sheet: Image = Image.create(480 * 3, 280 * 2, false, Image.FORMAT_RGBA8)
	closeup_sheet.fill(Color("121116"))
	var lineup_sheet: Image = Image.create(320 * 6, 190 * 3, false, Image.FORMAT_RGBA8)
	lineup_sheet.fill(Color("121116"))
	for index: int in breed_order.size():
		var breed: String = breed_order[index]
		var close_path: String = out_dir.path_join("older_speed_v064_close_%s.png" % breed)
		var comparison_path: String = out_dir.path_join("v0066_dragon_before_after_%s.png" % breed)
		check(SpeedParts.image_case_valid(close_path, capture, "compare:" + breed, [close_path, comparison_path]), "current capture, completed comparison and exact PNG bytes: " + breed)
		var closeup: Image = Image.load_from_file(close_path)
		check(closeup != null and closeup.get_size() == Vector2i(480, 280), "every complete original closeup cell exists: " + breed)
		if closeup != null and closeup.get_size() == Vector2i(480, 280):
			closeup_sheet.blit_rect(closeup, Rect2i(0, 0, 480, 280), Vector2i((index % 3) * 480, int(index / 3) * 280))
		var colours: Array = BREED_COLOUR_SETS[breed]
		for colour: int in colours.size():
			var gem: String = str(colours[colour])
			var cell_path: String = out_dir.path_join("older_speed_v064_lineup_%s_%s.png" % [breed, gem])
			check(SpeedParts.image_case_valid(cell_path, capture, "lineup:" + breed + ":" + gem, [cell_path]), "current capture, completed lineup and exact PNG bytes: " + breed + "/" + gem)
			var cell: Image = Image.load_from_file(cell_path)
			check(cell != null and cell.get_size() == Vector2i(320, 190), "every complete original lineup cell exists: " + breed + "/" + gem)
			if cell != null and cell.get_size() == Vector2i(320, 190):
				lineup_sheet.blit_rect(cell, Rect2i(0, 0, 320, 190), Vector2i(index * 320, colour * 190))
	check(_speed_capture(out_dir, SpeedParts.source_stamp(), false) == capture, "capture manifest and reference inputs remain current through assembly")
	if fails > 0: return fails
	check(closeup_sheet.save_png(out_dir.path_join("v0066_dragon_seat_closeup.png")) == OK, "saved every original breed closeup at original dimensions")
	check(lineup_sheet.save_png(out_dir.path_join("v0066_dragon_breed_lineup.png")) == OK, "saved every original breed/colour lineup cell at original dimensions")
	return fails
