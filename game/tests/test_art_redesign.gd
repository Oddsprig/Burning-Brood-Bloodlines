extends RefCounted
## Small native smoke fixture; no world generation, campaign advance or file writes.
## Run through tests/runner.tscn: -- --test=res://tests/test_art_redesign.gd
var checks := 0
var fails := 0
var icons := 0
var figures := 0

# Observe the native arrow marker before part shading; still rasterize every call.
class ArrowCanvas:
	extends PixelCanvas
	var arrows := 0
	func dot(pos: Vector2, color: Color) -> void:
		if color == Color("#c87533"): arrows += 1
		super.dot(pos, color)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL art redesign: ", label)

func _bytes(value: Variant) -> PackedByteArray:
	return var_to_bytes(value)

func _visible(img: Image) -> bool:
	if img == null: return false
	var rgba := img.get_data(); var pixels := 0
	for i in range(3, rgba.size(), 4):
		if rgba[i] > 127: pixels += 1
	return pixels > 100

func _same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.01 and a.a > 0.99

func run(_tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	var paper_cache: Dictionary = Paperdoll._cache.duplicate()
	var item_cache: Dictionary = ItemIcon._cache.duplicate()
	var old_gore := CombatText.gore_full; CombatText.gore_full = true
	var rng := RandomNumberGenerator.new(); rng.seed = 490061
	var u := Unit.create("human", "middle_kingdom")
	Factory.roll_look(rng, u); u.sex = 1; u.age = 51
	u.equip["clothing"] = Item.make("tunic", "linen", 0)
	u.equip["main_hand"] = Item.make("arming_sword", "copper", 2)
	u.equip["off_hand"] = Item.make("round_shield", "bronze", 2)
	u.equip["ranged"] = Item.make("hunting_bow", "wood", 2)
	var mail := Item.make("mail_shirt", "tin", 3)
	var spec := FigurePainter.spec_for_unit(u)
	check(spec["sex"] == "female" and int(spec["age"]) == 51, "appearance reads actual Unit sex and age")
	_pure_figure(u, spec, rng, "equipped human")
	_nodes(u, mail, rng)
	# Native sparse wounds, not decoration or invented damage in an art spec.
	var head: Dictionary = u.body.wound_part("head")
	head["layers"][0]["dmg"] = 0.7; head["layers"][0]["kind"] = "cut"; head["layers"][0]["bleed"] = 0.2
	u.body.blood = u.body.blood_max * 0.45
	u.body.wound_part("arm_upper_l")["severed"] = true
	spec = FigurePainter.spec_for_unit(u)
	check(spec["wk"].get("head", "") == "c" and spec["bleed"].get("head", false), "actual cut and bleeding enter render spec")
	check("arm_lower_l" in spec["lost"] and "hand_l" in spec["lost"], "native loss descendants remain absent")
	_pure_figure(u, spec, rng, "wounded human")
	var wounded_saved := _bytes(u.to_dict()); var wounded_rng := rng.state
	var wounded_uid := Unit._next_uid; var wounded_item_uid := Item._next_uid
	var archer := Paperdoll.new(); archer.set_unit(u); archer.bow_hand = true
	var lost_bow: Dictionary = archer.current_spec()
	check("hand_l" in lost_bow["lost"] and _arrow_count(lost_bow) == 0, "actual missing draw arm leaves native bow resting without a phantom arrow")
	archer.free()
	check(wounded_saved == _bytes(u.to_dict()) and wounded_rng == rng.state and wounded_uid == Unit._next_uid and wounded_item_uid == Item._next_uid, "missing-hand bow probe preserves actual body and identities")
	var saved := _bytes(u.to_dict()); var uid := Unit._next_uid; var item_uid := Item._next_uid; var random_state := rng.state
	var piece := Paperdoll.make_severed_piece(u, "arm_upper_l") as Sprite2D
	check(piece != null and piece.texture != null and piece.texture.get_width() == 48 and piece.texture.get_height() == 48, "real humanoid severed piece uses current 48px native image")
	if piece != null:
		check(piece.scale == Vector2.ONE, "severed piece retains original physical display size")
		piece.free()
	check(saved == _bytes(u.to_dict()) and uid == Unit._next_uid and item_uid == Item._next_uid and random_state == rng.state, "severed piece reads preserve real state and identity")
	_races(rng)
	_items(u, rng)
	_fallen_frames()
	CombatText.gore_full = old_gore
	Paperdoll._cache = paper_cache; ItemIcon._cache = item_cache
	print("ART REDESIGN checks=%d failures=%d figures=%d icons=%d elapsed_ms=%d" % [checks, fails, figures, icons, Time.get_ticks_msec() - started])
	return fails

func _pure_figure(u: Unit, spec: Dictionary, rng: RandomNumberGenerator, label: String) -> void:
	# Warm the body's shared unhurt plan reader before taking the purity snapshot.
	var shared := _bytes(u.body.part("torso_upper"))
	var saved := _bytes(u.to_dict()); var given := _bytes(spec)
	var anatomy := _bytes(DB.bodies); var palettes := _bytes([DB.races, DB.materials])
	var random_state := rng.state; var uid := Unit._next_uid; var item_uid := Item._next_uid
	var image := FigurePainter.render(spec, "strike", 0.5)
	var repeated := FigurePainter.render(spec, "strike", 0.5)
	var bust := FigurePainter.render_bust(spec)
	figures += 3
	check(_visible(image) and _visible(bust), label + " native art is nonempty")
	check(image.get_data() == repeated.get_data(), label + " repeats deterministically")
	check(image.get_size() == FigurePainter.dims(u.race)["size"], label + " uses current native raster dimensions")
	check(bust.get_size() == Vector2i(FigurePainter.bust_size(u.race), FigurePainter.bust_size(u.race)), label + " uses race portrait size")
	check(saved == _bytes(u.to_dict()) and given == _bytes(spec), label + " render preserves Unit/body/equipment and input spec")
	check(anatomy == _bytes(DB.bodies) and palettes == _bytes([DB.races, DB.materials]) and shared == _bytes(u.body.part("torso_upper")), label + " render preserves shared anatomy and palettes")
	check(random_state == rng.state and uid == Unit._next_uid and item_uid == Item._next_uid, label + " render consumes no RNG or identities")

func _nodes(u: Unit, mail: Item, rng: RandomNumberGenerator) -> void:
	var saved := _bytes(u.to_dict()); var random_state := rng.state
	var uid := Unit._next_uid; var item_uid := Item._next_uid
	var doll := Paperdoll.new(); doll.set_unit(u); doll.set_pose("idle", 0.0)
	var key := doll._frame_key; var texture := doll._tex; var image := doll.build_image()
	doll.set_pose("idle", 0.0)
	check(doll._tex == texture and doll._frame_key == key and Paperdoll._cache.get(key) == texture, "actual native Paperdoll repeat hits same cached texture")
	doll.facing = -1
	check(doll.facing == -1 and doll._tex == texture and doll.build_image().get_data() == image.get_data(), "left-facing display keeps same unmirrored CPU frame and cache")
	check(FigurePainter.display_scale(u.race) == 1.0 and doll._anchor == FigurePainter.dims(u.race)["anchor"], "native display uses scaled raster anchor at unchanged physical footprint")
	doll.facing = 4; check(doll.facing == 1, "native display facing normalizes rightward sign")
	doll.bow_hand = true; doll.set_pose("prepare", 0.5)
	var bow: Dictionary = doll.current_spec()
	check(bow["weapon"]["tid"] == u.bow().tid and bow["shield"].is_empty() and bow.get("bow_hand", false), "real ranged bow replaces sidearm and slings actual shield")
	check(_arrow_count(bow) == 1, "native healthy draw hand carries exactly one prepared arrow")
	check(u.weapon().tid == "arming_sword" and u.shield().tid == "round_shield", "bow display leaves equipped sidearm and shield intact")
	doll.bow_hand = false; doll.set_pose("idle", 0.0)
	check(doll.current_spec()["weapon"]["tid"] == u.weapon().tid and doll.current_spec()["shield"]["tid"] == u.shield().tid, "return to sidearm restores actual native shield spec")
	u.equip["body"] = mail
	var dressed := _bytes(u.to_dict())
	doll.refresh()
	check(doll._frame_key != key and doll._tex != texture and doll.build_image().get_data() != image.get_data(), "native equipped-item refresh invalidates cache and changes visible art")
	check(dressed == _bytes(u.to_dict()), "equipment refresh reads actual Unit without writeback")
	u.equip.erase("body"); doll.refresh()
	var portrait := Portrait.new(); portrait.set_unit(u)
	check(portrait.build_image().get_size() == Vector2i(96, 96), "actual humanoid Portrait produces current native 96px bust")
	check(portrait.build_image().get_data() == FigurePainter.render_bust(FigurePainter.spec_for_unit(u)).get_data(), "actual Portrait shares native figure layers")
	var party := PartyIcon.new(); party.setup("human", Color("#237d77"), 9, u)
	var icon := party.build_image(0)
	check(icon.get_size() == Vector2i(80, 66), "native campaign PartyIcon keeps existing 80x66 physical raster footprint")
	check(icon.get_data() == party.build_image(0).get_data(), "actual PartyIcon repeats deterministically")
	check(saved == _bytes(u.to_dict()) and rng.state == random_state and Unit._next_uid == uid and Item._next_uid == item_uid, "all native node render/cache reads preserve actual Unit/body/RNG/identities")
	portrait.free(); doll.free(); party.free()

func _races(rng: RandomNumberGenerator) -> void:
	for race in FigurePainter.DETAILED_RACES:
		check(FigurePainter.raster_scale(race) == 2.0 and FigurePainter.display_scale(race) == 1.0 and FigurePainter.bust_size(race) == 96, "current humanoid detail/display contract for " + race)
		var u := Unit.create(race, "player"); Factory.roll_look(rng, u)
		var spec := FigurePainter.spec_for_unit(u)
		var saved := _bytes(u.to_dict()); var given := _bytes(spec); var random_state := rng.state; var uid := Unit._next_uid; var item_uid := Item._next_uid
		var portrait := Portrait.new(); portrait.set_unit(u)
		check(portrait.build_image().get_size() == Vector2i(96, 96) and _visible(portrait.build_image()), "race module renders actual 96px portrait " + race)
		check(saved == _bytes(u.to_dict()) and given == _bytes(spec) and random_state == rng.state and uid == Unit._next_uid and item_uid == Item._next_uid, "race portrait remains pure " + race)
		if race in ["orc", "troll"]:
			var healthy := portrait.build_image().get_data()
			u.body.wound_part("nose")["severed"] = true
			saved = _bytes(u.to_dict())
			portrait.refresh()
			check("nose" in portrait._spec["lost"] and healthy != portrait.build_image().get_data(), "actual missing nose changes native portrait " + race)
			check(saved == _bytes(u.to_dict()) and random_state == rng.state and uid == Unit._next_uid and item_uid == Item._next_uid, "missing-nose refresh preserves actual state " + race)
		portrait.free()
	var bear := Creatures.make(rng, "bear")
	check(FigurePainter.raster_scale("bear") == 1.0 and FigurePainter.display_scale("bear") == 2.0 and FigurePainter.bust_size("bear") == 40, "creature keeps native detail/display contract")
	_pure_figure(bear, FigurePainter.spec_for_unit(bear), rng, "native bear control")

func _items(u: Unit, rng: RandomNumberGenerator) -> void:
	check(ItemIcon.SIZE == 64 and ItemIcon.LOGICAL_SIZE == 32 and ItemIcon.RASTER_SCALE == 2, "current native item detail retains logical UI coordinate grid")
	var templates := {}
	var ids: Array = DB.weapons.keys() + DB.bows.keys(); ids.sort()
	for tid in ids:
		var sprite := String(DB.template(tid).get("sprite", ""))
		if sprite in WeaponArt.SPRITES and not templates.has(sprite): templates[sprite] = String(tid)
	check(templates.size() == 15 and WeaponArt.SPRITES.size() == 15, "all fifteen native weapon/bow shapes have real item templates")
	var special := {"war_hammer": "hammer", "leaf_dirk": "dirk", "dwarf_mattock": "mattock", "dwarf_war_axe": "dwarf_axe", "short_spear": "spear_short", "boar_spear": "spear_boar", "winged_spear": "spear_winged", "steppe_lance": "lance"}
	var seen := {}; var gear: Dictionary = u.equip.duplicate()
	for sprite in WeaponArt.SPRITES:
		if not templates.has(sprite): continue
		var tid := String(templates[sprite]); var mat := "wood" if DB.is_bow(tid) else "copper"
		var shape: String = special.get(tid, sprite)
		var it := Item.make(tid, mat, 0)
		var saved := _bytes(it.to_dict()); var random_state := rng.state; var uid := Unit._next_uid; var item_uid := Item._next_uid
		var texture := ItemIcon.for_item(it); var plain := texture.get_image()
		icons += 1
		check(ItemIcon.shape_of(tid) == shape and plain.get_size() == Vector2i(64, 64) and _visible(plain), "actual native icon shape/detail for " + sprite)
		check(ItemIcon.for_item(it) == texture and saved == _bytes(it.to_dict()), "actual icon cache hit preserves item " + sprite)
		var pixels := Marshalls.raw_to_base64(plain.get_data())
		check(not seen.has(pixels), "distinct native item shape for " + sprite); seen[pixels] = sprite
		it.quality = 3
		var quality := ItemIcon.for_item(it).get_image(); icons += 1
		check(quality.get_data() != plain.get_data() and _same_color(quality.get_pixel(4, 4), ItemIcon.GOLD), "quality pips scale into current native raster " + sprite)
		it.quality = DB.LEGEND; it.legend = {"nm": "Fixture piece", "gem": "ruby", "at": Item.gem_spot(tid)}
		saved = _bytes(it.to_dict())
		var legendary := ItemIcon.for_item(it).get_image(); icons += 1
		var spot: Vector2i = ItemIcon.GEM_SPOTS[shape] * ItemIcon.RASTER_SCALE
		check(legendary.get_data() != quality.get_data() and _same_color(legendary.get_pixelv(spot), Color(ItemIcon.THING_COLORS["ruby"])), "legend gem follows real shape's scaled setting " + sprite)
		check(_same_color(legendary.get_pixel(44, 2), Color(ItemIcon.THING_COLORS["ruby"])), "sixth legendary pip uses scaled native gem coordinate " + sprite)
		check(saved == _bytes(it.to_dict()) and random_state == rng.state and uid == Unit._next_uid and item_uid == Item._next_uid, "material/quality/legend icon reads consume no state or identities " + sprite)
		# One frame per key exercises shared weapon art with an actual equipped item.
		var spec: Dictionary
		if DB.is_bow(tid):
			u.equip["ranged"] = it
			var archer := Paperdoll.new(); archer.set_unit(u); archer.bow_hand = true
			spec = archer.current_spec().duplicate(true); archer.free()
		else:
			u.equip["main_hand"] = it; spec = FigurePainter.spec_for_unit(u)
		_pure_figure(u, spec, rng, "native weapon " + sprite)
	u.equip = gear
	# Dedicated template art must match the real hammer, leaf blade, pick and scales.
	var extra := {"war_hammer": "hammer", "leaf_dirk": "dirk", "dwarf_mattock": "mattock", "scale_vest": "scale"}
	for tid in extra:
		var it := Item.make(tid, "copper", 0)
		var saved := _bytes(it.to_dict()); var random_state := rng.state; var uid := Unit._next_uid; var item_uid := Item._next_uid
		var img := ItemIcon.for_item(it).get_image(); icons += 1
		var expected: String = extra[tid]
		check(ItemIcon.shape_of(tid) == expected and _visible(img), "actual dedicated template shape " + tid)
		var old_shape: String = "lamellar" if tid == "scale_vest" else String(DB.template(tid)["sprite"])
		check(img.get_data() != ItemIcon.image(old_shape, "copper", 0).get_data(), "dedicated template remains visibly distinct from generic shape " + tid)
		it.quality = DB.LEGEND; it.legend = {"nm": "Fixture piece", "gem": "ruby", "at": Item.gem_spot(tid)}
		saved = _bytes(it.to_dict())
		var legend := ItemIcon.for_item(it).get_image(); icons += 1
		var setting: Vector2i = ItemIcon.GEM_SPOTS[expected] * ItemIcon.RASTER_SCALE
		check(_same_color(legend.get_pixelv(setting), Color(ItemIcon.THING_COLORS["ruby"])), "real dedicated legend uses scaled setting " + tid)
		check(saved == _bytes(it.to_dict()) and random_state == rng.state and uid == Unit._next_uid and item_uid == Item._next_uid, "dedicated icon remains pure " + tid)
	var metals := {}
	for metal in ["copper", "tin", "bronze", "iron", "steel"]:
		var it := Item.make("arming_sword", metal, 0); var saved := _bytes(it.to_dict())
		var uid := Unit._next_uid; var item_uid := Item._next_uid; var random_state := rng.state
		var img := ItemIcon.for_item(it).get_image(); icons += 1
		var pixels := Marshalls.raw_to_base64(img.get_data())
		check(not metals.has(pixels), "actual material palette remains distinct " + metal); metals[pixels] = metal
		check(saved == _bytes(it.to_dict()) and uid == Unit._next_uid and item_uid == Item._next_uid and random_state == rng.state, "material palette read is pure " + metal)

func _arrow_count(spec: Dictionary) -> int:
	var given := _bytes(spec)
	var painter := FigurePainter.new(spec)
	painter.pose = "prepare"; painter.t = 0.5; painter._rig()
	var dm := FigurePainter.dims(String(spec["race"])); var size: Vector2i = dm["size"]
	var canvas := ArrowCanvas.new(size.x, size.y)
	canvas.set_frame(dm["anchor"], FigurePainter.raster_scale(String(spec["race"])))
	painter.cv = canvas
	check(WeaponArt.draw(painter, painter.j["grip"], painter.j["wdir"]) and canvas.opaque_count() > 0, "native actual bow command renders on CPU canvas")
	check(given == _bytes(spec), "native bow command keeps actual input spec pure")
	return canvas.arrows


func _fallen_frames() -> void:
	for race in FigurePainter.DETAILED_RACES:
		for tid in ["bearded_axe", "dane_axe", "dwarf_war_axe", "glaive"]:
			var spec := FigurePainter.spec_generic(race, Color("#30729c"), Color("#d5b368"), 11)
			spec["weapon"] = FigurePainter._item_spec(Item.make(tid, "steel", 3))
			for pose in ["prone", "dead"]:
				var img := FigurePainter.render(spec, pose, 1.0)
				figures += 1
				check(_visible(img), "fallen broad weapon remains visible " + race + " " + tid + " " + pose)
				check(_clear_edges(img), "fallen broad weapon fits native canvas " + race + " " + tid + " " + pose)

func _clear_edges(img: Image) -> bool:
	var bytes := img.get_data()
	var width := img.get_width()
	var height := img.get_height()
	for x in width:
		if bytes[x * 4 + 3] > 0 or bytes[((height - 1) * width + x) * 4 + 3] > 0: return false
	for y in height:
		if bytes[(y * width) * 4 + 3] > 0 or bytes[(y * width + width - 1) * 4 + 3] > 0: return false
	return true
