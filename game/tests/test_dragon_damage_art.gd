extends RefCounted
## Coherent source layers; anatomical masks place blood, never sever limbs.
var checks := 0
var fails := 0
const BASE := Color("#528876")

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon damage art: " + why)

func part(id: String, parent: String, area: Rect2) -> Dictionary:
	var image := Image.create(int(area.size.x), int(area.size.y), false, Image.FORMAT_RGBA8); image.fill(BASE)
	return {"id": id, "parent": parent, "image": image, "xf": Transform2D(0.0, area.position), "source_rect": Rect2(Vector2.ZERO, area.size),
		"bounds": area, "anchor_start": area.position + area.size * 0.3, "anchor_end": area.position + area.size * 0.7, "visible": true}

func fixture() -> Dictionary:
	var parts := [part("body", "", Rect2(10, 10, 32, 24)), part("head", "body", Rect2(44, 10, 12, 12)), part("jaw", "head", Rect2(44, 22, 10, 6))]
	var regions: Array = []
	var boxes := {"torso": Rect2(14, 14, 20, 16), "neck": Rect2(34, 14, 8, 8), "tail": Rect2(10, 10, 8, 8),
		"wing_upper_r": Rect2(18, 10, 10, 8), "wing_lower_r": Rect2(26, 14, 8, 10), "wing_upper_l": Rect2(12, 12, 10, 8), "wing_lower_l": Rect2(14, 18, 8, 10),
		"leg_upper_r": Rect2(20, 22, 10, 8), "leg_lower_r": Rect2(26, 26, 8, 8), "foot_r": Rect2(34, 30, 6, 4),
		"leg_upper_l": Rect2(10, 22, 10, 8), "leg_lower_l": Rect2(16, 26, 8, 8), "foot_l": Rect2(22, 30, 6, 4), "head": Rect2(44, 10, 12, 12), "jaw": Rect2(44, 22, 10, 6)}
	for id: String in boxes:
		var region := part(id, "", boxes[id]); region["owner_part_id"] = id if id in ["head", "jaw"] else "body"
		if id == "neck":
			region["cut_point"] = Vector2(40, 18)
			region["cut_line"] = PackedVector2Array([Vector2(35, 15), Vector2(37, 18), Vector2(41, 18)])
		regions.append(region)
	return {"parts": parts, "regions": regions}

func named(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row["id"] == id: return row
	return {}

func canvas() -> PixelCanvas:
	var cv := PixelCanvas.new(120, 90); cv.buf.fill(BASE)
	return cv

func changed(cv: PixelCanvas) -> int:
	var count := 0
	for color: Color in cv.buf:
		if color != BASE: count += 1
	return count

func snapshot() -> PackedByteArray:
	return var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold, "day": Game.day}))

func run(_tree: SceneTree) -> int:
	var before := snapshot(); var rng := Game.rng.state; var unit_uid := Unit._next_uid; var item_uid := Item._next_uid
	var data := fixture(); var parts: Array = data["parts"]; var regions: Array = data["regions"]
	var saved_parts := parts.duplicate(true); var saved_regions := regions.duplicate(true); var bytes: Array[PackedByteArray] = []
	for row: Dictionary in parts + regions: bytes.append((row["image"] as Image).get_data())
	var state := {"lost": ["wing_upper_r", "wing_upper_r", ""], "dmg": {"head": 1.6, "tail": -1.0}, "wk": {"head": "fractured", "tail": "bruised", "unknown": "unknown"}, "blood": 0.4}
	var saved_state := state.duplicate(true); var native := DragonDamageArt.normalize(state)
	check(native["lost"] == ["wing_upper_r"] and native["dmg"]["head"] == 1.0 and native["dmg"]["tail"] == 0.0, "native display fields bounded/copied")
	check(native["wk"]["head"] == "f" and native["wk"]["tail"] == "b" and not native["wk"].has("unknown"), "native wound ranks retained")
	check(DragonDamageArt.normalize({"blood": -1})["blood"] == 0.0 and DragonDamageArt.normalize({"blood": 2})["blood"] == 1.0, "native blood fraction clamped")
	for row_index: int in range(4):
		var differences: Dictionary = {}
		for column: int in range(12):
			var delta := DragonDamageArt._cell_value(Vector2i(column + 1, row_index), 67) - DragonDamageArt._cell_value(Vector2i(column, row_index), 67)
			differences[roundi(delta * 100000.0)] = true
		check(differences.size() > 8, "cell avalanche eliminates repeated linear-hash stripe increments")
	check(is_equal_approx(DragonDamageArt._grain(Vector2(144, 92), 67), DragonDamageArt._grain(Vector2(144, 92), 67)) and absf(DragonDamageArt._grain(Vector2(144, 92), 67) - DragonDamageArt._grain(Vector2(144.1, 92.1), 67)) < 0.02, "pooled cell noise remains deterministic and spatially smooth")
	for noise_seed: int in [-2147483648, 0, 67, 2147483647]:
		var noise_cells: Dictionary = {}
		for at: Vector2 in [Vector2(-200.25, -71.5), Vector2.ZERO, Vector2(35.7142857, 71.4285714), Vector2(144, 92), Vector2(1535.5, 1023.5), Vector2(3224.55, 2149.35)]:
			check(DragonDamageArt._grain_cached(at, noise_seed, noise_cells) == DragonDamageArt._grain(at, noise_seed), "cached noise retains exact original interpolation across seeds/boundaries")
	var bounded_noise: Dictionary = {}
	for cell_index: int in 4200: DragonDamageArt._cached_cell(Vector2i(cell_index, 0), 67, bounded_noise)
	check(bounded_noise.size() <= 4096, "first-decal scratch noise cache stays bounded")
	for id: String in ["torso", "tail", "wing_upper_r", "wing_lower_r", "wing_upper_l", "wing_lower_l", "leg_upper_r", "leg_lower_r", "foot_r", "leg_upper_l", "leg_lower_l", "foot_l", "jaw"]:
		var injury := {"lost": [id], "blood": 0.6}; var marks := DragonDamageArt.marks(injury, parts, regions)
		check(DragonDamageArt.effective_lost(injury, parts).is_empty(), id + " mangled region does not remove coherent body/jaw")
		check(marks.size() == 1 and marks[0]["kind"] == "mangle" and marks[0]["mask_region_id"] == id and marks[0]["wound_kind"] == "m", id + " exact blood/mangle region")
		check(DragonDamageArt.detached_parts(id, injury, parts).is_empty(), id + " no fake severed whole-limb/jaw art")
	for id: String in ["head", "neck"]:
		var injury := {"lost": [id], "dmg": {"head": 0.8, "jaw": 0.8}, "blood": 0.5}; var marks := DragonDamageArt.marks(injury, parts, regions)
		check(DragonDamageArt.effective_lost(injury, parts) == ["head", "jaw"], id + " separates only head and attached jaw")
		check(marks.size() == 1 and marks[0]["kind"] == "stump" and marks[0]["mask_part_id"] == "body" and marks[0]["mask_region_id"] == "neck" and marks[0]["cut_line"] == named(regions, "neck")["cut_line"], id + " one complete observed neck-cut line; no floating wounds")
		var detached := DragonDamageArt.detached_parts(id, injury, parts)
		check(detached.size() == 2 and detached[0]["image"] == parts[1]["image"] and detached[1]["image"] == parts[2]["image"], id + " detached head retains true source pixels")
	check(DragonDamageArt.effective_lost({"lost": ["unknown"]}, parts).is_empty() and DragonDamageArt.marks({"lost": ["unknown"]}, parts, regions).is_empty(), "unknown id does not affect another source region")
	for mark: Dictionary in DragonDamageArt.marks({"lost": ["wing_upper_l", "neck"], "blood": 0.0}, parts, regions): check(not mark["bleeding"], "blood depletion stops fresh flow")
	for code: String in ["b", "c", "f", "m"]:
		var injury := {"dmg": {"head": 0.95}, "wk": {"head": code}, "bleed": {"head": true}, "blood": 0.8}; var cv := canvas(); var repeat := canvas()
		DragonDamageArt.draw_overlay(cv, parts, injury, Vector2.ZERO, 1.0, 67, regions); DragonDamageArt.draw_overlay(repeat, parts, injury, Vector2.ZERO, 1.0, 67, regions)
		check(changed(cv) > 0 and cv.buf == repeat.buf and cv.get_px(0, 0) == BASE, code + " local deterministic rank overlay")
	var injury := {"dmg": {"torso": 0.95}, "wk": {"torso": "m"}, "blood": 0.7}; var layers := DragonDamageArt.overlay_layers(parts, injury, 67, regions)
	check(layers.size() == 1 and layers[0]["part_id"] == "body" and layers[0]["image"] == DragonDamageArt.overlay_layers(parts, injury, 67, regions)[0]["image"], "region decal maps into real owner image and reuses cached pixels")
	var bloody := canvas(); DragonDamageArt.draw_overlay(bloody, parts, injury, Vector2.ZERO, 1.0, 67, regions)
	check(changed(bloody) > 0 and (layers[0]["source_rect"] as Rect2).encloses(Rect2(4, 4, 20, 16)) and bloody.get_px(0, 0) == BASE, "ragged pooled blood covers the full affected-region work area, clipped to real tissue")
	var decal: Image = layers[0]["image"]; var translucent := 0
	for y: int in decal.get_height():
		for x: int in decal.get_width():
			var alpha := decal.get_pixel(x, y).a
			if alpha > 0.0 and alpha < 1.0: translucent += 1
	check(translucent > 0, "living scale shading remains visible under translucent regional blood smears")
	var crimson_pixels: int = 0
	for y: int in decal.get_height():
		for x: int in decal.get_width():
			var blood_color: Color = decal.get_pixel(x, y)
			if blood_color.a > 0.1 and blood_color.r > blood_color.g * 3.0 and blood_color.r > blood_color.b * 2.0: crimson_pixels += 1
	check(crimson_pixels > 0, "actual tissue decal contains deep red blood rather than an orange-brown colour wash")
	var neck_cut := canvas(); DragonDamageArt.draw_overlay(neck_cut, parts, {"lost": ["neck"], "blood": 0.8}, Vector2.ZERO, 1.0, 73, regions)
	check(neck_cut.get_px(35, 15) != BASE and neck_cut.get_px(40, 18) != BASE and neck_cut.get_px(45, 15) == BASE, "bloody flesh lip spans angled and horizontal observed cut segments; no detached-head marks in empty source")
	var motion := Transform2D(0.2, Vector2(2, 2), 0.0, Vector2(18, 9)); var moved_parts := parts.duplicate(true); var moved_regions := regions.duplicate(true)
	for row: Dictionary in moved_parts + moved_regions:
		row["xf"] = motion * (row["xf"] as Transform2D)
		for key: String in ["anchor_start", "anchor_end"]: row[key] = motion * (row[key] as Vector2)
	var moved := DragonDamageArt.overlay_layers(moved_parts, injury, 67, moved_regions)
	check(moved[0]["image"] == layers[0]["image"] and (moved[0]["xf"] as Transform2D).is_equal_approx(motion * (layers[0]["xf"] as Transform2D)), "cached decal follows shared source scale/pose once")
	var masked_regions := regions.duplicate(true); var mask_region := named(masked_regions, "torso"); var mask: Image = (mask_region["image"] as Image).duplicate() as Image
	for y: int in range(6, 10):
		for x: int in range(8, 12): mask.set_pixel(x, y, Color.TRANSPARENT)
	mask_region["image"] = mask; var masked := canvas(); DragonDamageArt.draw_overlay(masked, parts, injury, Vector2.ZERO, 1.0, 92, masked_regions)
	check(changed(masked) > 0 and masked.get_px(24, 22) == BASE, "region and owner alpha both bound blood pixels")
	var covered: Dictionary = parts[1].duplicate(true); covered["id"] = "foreground"; var occluded := canvas()
	DragonDamageArt.draw_overlay(occluded, [parts[1], covered], {"dmg": {"head": 0.95}, "wk": {"head": "m"}}, Vector2.ZERO, 1.0, 41, [named(regions, "head")])
	check(changed(occluded) == 0, "foreground source pixels occlude rear wounds")
	for seed_value: int in range(90, 141): DragonDamageArt.overlay_layers(parts, injury, seed_value, regions)
	check(DragonDamageArt._decals.size() <= DragonDamageArt.DECAL_CACHE_LIMIT and DragonDamageArt._decal_order.size() <= DragonDamageArt.DECAL_CACHE_LIMIT, "decal cache bounded")
	var requests := {"fragments": [{"region_id": "jaw", "kind": "tooth", "count": 3}, {"region_id": "foot_r", "kind": "claw", "count": 4}]}; var saved_requests := requests.duplicate(true)
	var dragon := {"gem_id": "sapphire", "appearance_seed": 67}; var fragments := DragonDamageArt.fragment_layers(dragon, regions, requests, 0.2)
	check(fragments.size() == 7 and fragments == DragonDamageArt.fragment_layers(dragon, regions, requests, 0.2), "tooth/claw-tip slivers deterministic")
	check(fragments[0]["points"] != DragonDamageArt.fragment_layers(dragon, regions, requests, 0.6)[0]["points"] and DragonDamageArt.fragment_layers(dragon, regions, requests, 1.0).is_empty(), "explicit progress moves/fades fragments; no scheduled tick")
	for fragment: Dictionary in fragments: check(fragment["tip_size"] <= 0.7 and fragment["points"].size() == 3 and fragment["kind"] in ["tooth", "claw"], "only tiny tinted tissue tips, never whole limb/giant gem")
	check(DragonDamageArt.fragment_layers({"gem_id": "unknown"}, regions, requests, 0.2).is_empty(), "unknown gem fails closed")
	check(DragonDamageArt.fragment_layers({"gem_id": "sapphire", "stage": "egg"}, regions, requests, 0.2).is_empty(), "egg has no tooth/claw fragments")
	check(DragonDamageArt.fragment_layers(dragon, regions, {"fragments": [{"region_id": "torso", "kind": "claw"}]}, 0.2).is_empty(), "no invented tooth/claw location")
	var index := 0
	for row: Dictionary in parts + regions:
		check((row["image"] as Image).get_data() == bytes[index], "coherent source/region mask pixels unchanged"); index += 1
	check(parts == saved_parts and regions == saved_regions and state == saved_state and requests == saved_requests, "source metadata/native injury/fragment requests remain pure")
	check(snapshot() == before and Game.rng.state == rng and Unit._next_uid == unit_uid and Item._next_uid == item_uid, "world/RNG/native identity counters conserved")
	print("dragon damage art: %d checks, %d failures" % [checks, fails])
	return fails
