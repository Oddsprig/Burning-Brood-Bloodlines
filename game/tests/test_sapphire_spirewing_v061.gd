extends RefCounted
## Bounded art-only checks: no world generation, simulation ticks or save IO.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL Sapphire Spirewing v061: " + why)

func run(tree: SceneTree) -> int:
	var before: String = JSON.stringify(Game._serialize(Game.world), "", true, true)
	var rng_state: int = Game.rng.state
	var next_unit: int = Unit._next_uid
	var next_item: int = Item._next_uid
	var row: Dictionary = {"stage": "adult", "alive": true, "gem_id": "sapphire", "morph_id": "spirewing", "size_class": "medium", "appearance_seed": 27, "sprite_id": "sapphire_spirewing"}
	var copied := row.duplicate(true)
	var default_row := row.duplicate(true)
	default_row.erase("sprite_id")
	var original := row.duplicate(true)
	original["sprite_id"] = "classic"
	check(DragonSpriteCatalog.variants_for(row).size() == 1 and DragonSpriteCatalog.variant_for(row).get("name") == "Sapphire Spirewing", "catalog registers an eligible, selectable variant")
	check(DragonSpriteCatalog.variant_for(default_row).get("id") == "sapphire_spirewing", "default sprite_id selects the v0.064 code-drawn variant")
	check(DragonSpriteCatalog.entry("sapphire_spirewing").get("generator") == "sapphire_spirewing", "catalog resolves the code-generated source")
	check(DragonSpriteCatalog.entries().size() == 6 and DragonSpriteCatalog.variant_for(original).is_empty(), "classic sprite_id retains the original six source forms")
	var wrong := row.duplicate(true)
	wrong["gem_id"] = "ruby"
	check(DragonSpriteCatalog.variant_for(wrong).is_empty(), "sapphire sprite cannot override a different gem")
	wrong["gem_id"] = "sapphire"; wrong["morph_id"] = "broadmantle"
	check(DragonSpriteCatalog.variant_for(wrong).is_empty(), "sapphire sprite cannot override another body form")
	check(Dragons.physical_profile(Game, row) == Dragons.physical_profile(Game, original), "sprite selection leaves native gem, growth and attack physics unchanged")
	var hashes := {}
	for i in SapphireSpirewingArt.FRAME_COUNT:
		var image := SapphireSpirewingArt.frame(i)
		check(image != null and image.get_size() == Vector2i(128, 96), "frame %d builds at native pixel dimensions" % i)
		if image == null: continue
		check(image.get_used_rect().size.x > 90 and image.get_used_rect().size.y > 50 and image.get_pixel(127, 95).a == 0, "frame %d contains a substantial transparent wyvern silhouette" % i)
		hashes[image.get_data().hex_encode().sha256_text()] = true
		check(SapphireSpirewingArt.frame(i) == image, "frame %d reuses its generated image" % i)
		var progress := float(i) / SapphireSpirewingArt.FRAME_COUNT
		var source := DragonRigArt._source(row, "idle", progress)
		check(int(source.get("entry", {}).get("frame", -1)) == i and source.get("image") == image, "frame %d is selected through the live source loader" % i)
		var model := DragonArt.model(row, "idle", progress)
		check(bool(model.get("valid", false)) and model.get("frames") == 6, "frame %d builds through the shared dragon model" % i)
		if not bool(model.get("valid", false)): continue
		check(model["parts"].size() == 3 and model["regions"].size() == 15, "frame %d retains head/jaw cuts and native injury regions" % i)
		check(model["hind_legs"] == 2 and model["wing_forelimbs"] == 2 and model["front_legs"] == 0, "frame %d keeps wyvern anatomy" % i)
		check(model["rider_height"] == 24.0 and model["rider_scale"] == 1.0 and model["mountable"], "frame %d keeps the native rider socket and scale" % i)
		check(DragonCard.cached_model(row, "idle", progress)["whole_image"].get_data() == image.get_data(), "card cache selects authored frame %d without repigmenting it" % i)
		check(DragonRigArt._texture_for(image) == DragonRigArt._texture_for(image), "frame %d shares its GPU texture" % i)
		await tree.process_frame
	check(hashes.size() == 6 and SapphireSpirewingArt._frames.size() == 6, "all six wingbeat sources are distinct and the image cache is bounded")
	var source_image := DragonArt.source_image(row)
	var reconstructed := DragonArt.reconstruct_source(row)
	check(source_image != null and reconstructed != null and source_image.get_data() == reconstructed.get_data(), "rest head/jaw/body cuts exactly reconstruct the generated source")
	var rest := DragonArt.model(row, "rest")
	check(rest.get("frames") == 1 and rest["seat"].is_equal_approx(Vector2.ZERO), "still rest uses the raised-wing source and original seat origin")
	var meta_rest := SapphireSpirewingArt.metadata(1)
	var seat_x := float(meta_rest["seat_px"][0])
	var seat_y := float(meta_rest["seat_px"][1])
	check(seat_x > float(meta_rest["wing_roots_px"]["right"][0]) and float(meta_rest["wing_roots_px"]["right"][0]) > float(meta_rest["wing_roots_px"]["left"][0]) and absf(seat_x - float(meta_rest["neck_root_px"][0])) <= 4.0 and absf(seat_y - float(meta_rest["neck_root_px"][1])) <= 4.0, "saddle seat sits at the base of the neck, clearly forward of the wing roots")
	var gem_hashes := {}
	for gem: Dictionary in Dragons.catalogs().get("gems", []):
		var gid := String(gem.get("id", ""))
		var mid := String(DragonConcepts.entry(gid).get("morph_id", "spirewing"))
		var f_img := SapphireSpirewingArt.frame_for(gid, mid, 1)
		check(f_img != null and f_img.get_size() == Vector2i(128, 96) and f_img.get_used_rect().size.x > 80, "v0.064 code-drawn gem/breed frame builds: " + gid + "/" + mid)
		if f_img != null: gem_hashes[f_img.get_data().hex_encode().sha256_text()] = true
	check(gem_hashes.size() == 16, "all 16 dragon gem colours produce distinct 2.5D code-drawn art")
	var morph_hashes := {}
	var morph_spec_hashes := {}
	var morph_opaque_counts := {}
	for morph: Dictionary in Dragons.catalogs().get("morphs", []):
		var mid := String(morph.get("id", ""))
		var bspec := SapphireSpirewingArt.breed_spec(mid)
		var spec_sig := JSON.stringify([bspec.get("torso_points"), bspec.get("torso_radii"), bspec.get("neck_points"), bspec.get("head_pos"), bspec.get("wing_scale"), bspec.get("tail_points"), bspec.get("seat_px"), bspec.get("wing_roots_px")])
		morph_spec_hashes[spec_sig] = true
		var bmeta := SapphireSpirewingArt.metadata_for("emerald", mid, 1)
		var b_seat_x := float(bmeta["seat_px"][0])
		var b_seat_y := float(bmeta["seat_px"][1])
		var b_wing_r_x := float(bmeta["wing_roots_px"]["right"][0])
		var b_wing_l_x := float(bmeta["wing_roots_px"]["left"][0])
		var b_neck_x := float(bmeta["neck_root_px"][0])
		var b_neck_y := float(bmeta["neck_root_px"][1])
		check(b_seat_x >= b_wing_r_x + 10.0 and b_wing_r_x > b_wing_l_x and absf(b_seat_x - b_neck_x) <= 4.0 and absf(b_seat_y - b_neck_y) <= 4.0, mid + " seat point is at neck base and clearly forward of wing roots")
		var m_img := SapphireSpirewingArt.frame_for("emerald", mid, 1)
		if m_img != null:
			morph_hashes[m_img.get_data().hex_encode().sha256_text()] = true
			var opaque := 0
			for py in m_img.get_height():
				for px in m_img.get_width():
					if m_img.get_pixel(px, py).a > 0.0:
						opaque += 1
			morph_opaque_counts[opaque] = true
	check(morph_hashes.size() == 6 and morph_spec_hashes.size() == 6 and morph_opaque_counts.size() >= 5, "all 6 dragon breeds have distinct silhouette parameters and distinct 2.5D silhouettes")
	var seat_ys := {}
	var seat_angles := {}
	for i in SapphireSpirewingArt.FRAME_COUNT:
		var m := DragonArt.model(row, "idle", float(i) / SapphireSpirewingArt.FRAME_COUNT)
		seat_ys[snappedf((m["seat"] as Vector2).y, 0.01)] = true
		seat_angles[snappedf(float(m["seat_angle"]), 0.001)] = true
	check(seat_ys.size() >= 3 and seat_angles.size() >= 4, "rider seat position and pitch move with the dragon across wingbeat frames")
	check(DragonArt.frame_count(row, "ground") == 6 and DragonArt.frame_count(row, "idle") == 6 and DragonArt.frame_count(row, "dead") == 1 and DragonArt.frame_count(row, "prone") == 1, "live adapters get six frames while fallen dragons remain still")
	check(DragonArt.frame_count(original, "idle") == int(FigurePainter.FRAMES["idle"]), "original source frame counts are unchanged")
	var dead_a := DragonRigArt._source(row, "dead", 0.0)
	var dead_b := DragonRigArt._source(row, "dead", 0.9)
	check(dead_a["key"] == dead_b["key"], "dead poses do not animate the wings")
	var cut := DragonArt.model(row, "idle", 0.5, {"lost": ["head"]})
	check(cut["parts"].size() == 1 and cut["parts"][0]["id"] == "body", "head loss retains the original generated body only")
	var mangled := DragonArt.model(row, "idle", 0.5, {"lost": ["wing_upper_r"], "blood": 0.9})
	check(mangled["parts"].size() == 3 and not DragonDamageArt.marks(mangled["state"], mangled["all_parts"], mangled["regions"]).is_empty(), "mangled wings stay attached with native damage marks")
	var cv := PixelCanvas.new(192, 144)
	var framing := DragonArt.framing(row, "rest", Vector2i(192, 144))
	var drawn := DragonArt.draw(cv, row, "rest", framing["origin"], framing["pixels_per_unit"])
	check(bool(drawn.get("valid", false)) and cv.opaque_count() > 500, "registered generated sprite renders through the software art route")
	check(row == copied and JSON.stringify(Game._serialize(Game.world), "", true, true) == before and Game.rng.state == rng_state and Unit._next_uid == next_unit and Item._next_uid == next_item, "art reads preserve the record, campaign, RNG and native counters")
	print("Sapphire Spirewing v061: %d checks, %d failures" % [checks, fails])
	return fails
