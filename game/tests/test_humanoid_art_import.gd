extends RefCounted
## Bounded v0.053 art contracts; no world generation or battle simulation.
var checks := 0
var fails := 0
const HEIGHTS := {"human": 24.0, "orc": 26.0, "high_elf": 26.0, "moon_elf": 25.0, "dark_elf": 24.0, "dwarf": 17.0, "goblin": 18.0, "troll": 38.0}
const FRAMES := {"idle": 4, "walk": 8, "prepare": 4, "strike": 5, "recover": 4, "hit": 3, "block": 3, "dodge": 4, "prone": 1, "dead": 1}

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL humanoid import: " + why)

func layer(spec: Dictionary, kind: String) -> Image:
	var fp := FigurePainter.new(spec)
	fp._rig()
	fp.cv = PixelCanvas.new(192, 192)
	fp.cv.set_frame(Vector2(96, 160), 2.0, 0.0)
	match kind:
		"head": fp._head()
		"torso": fp._torso()
		"arm_l": fp._arm("l")
	return fp.cv.to_image()

func snapshot() -> PackedByteArray:
	return var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "squads": Game.squads, "gold": Game.gold, "day": Game.day}))

func run(_tree: SceneTree) -> int:
	var campaign := snapshot(); var rng_state := Game.rng.state
	var old_unit_uid := Unit._next_uid; var old_item_uid := Item._next_uid
	check(FigurePainter.FRAMES == FRAMES, "released native pose frame counts")
	check((DB.races["orc"]["skin"] as Array).size() == 11 and (DB.races["orc"]["hair"] as Array).size() == 8, "released Orc skin and hair palette is complete")
	for culture in DB.armor_by_culture:
		var pool := Businesses._gear_pool(String(culture), "armor")
		check(pool.count("closed_helm") == 1, "native " + String(culture) + " smith pool includes closed helmet exactly once")
		check(not pool.has("tunic") and not pool.has("shoes"), "native metal pool excludes cloth/leather")
	check(FigurePainter.frame_index("walk", 1.0) == 0 and FigurePainter.frame_index("strike", 1.0) == 4 and FigurePainter.frame_index("dead", 0.2) == 0, "cyclic/noncyclic timing unchanged")
	for race: String in FigurePainter.DETAILED_RACES:
		var u := Unit.create(race, "middle_kingdom")
		u.look["seed"] = 63; u.look["beard"] = true; u.age = 54
		u.sex = 0
		var male := FigurePainter.spec_for_unit(u)
		check(male["sex"] == "male" and male["age"] == 54, race + " actual male/age read")
		if race in ["human", "orc", "dwarf"]:
			check(male["beard_style"] == FigurePainter.beard_style(u.look), race + " actual bearded selector")
		u.sex = 1; u.look["female_set"] = 1
		var spec := FigurePainter.spec_for_unit(u)
		check(spec["sex"] == "female" and spec["female_set"] == 1, race + " explicit actual female set")
		check(FigurePainter.female_variant({"seed": 3}) == 0 and FigurePainter.female_variant({"seed": 63}) == 1 and FigurePainter.female_variant({"seed": 63, "female_set": 0}) == 0, race + " independent deterministic female choice/override")
		check(FigurePainter.beard_style({"seed": 120}) == 1 and FigurePainter.beard_style({"seed": 120, "beard_style": 4}) == 4, race + " independent beard choice/override")
		check(spec["body"].is_empty() and spec["helm"].is_empty(), race + " absent native equipment stays absent")
		var copy := spec.duplicate(true); var before := var_to_bytes(u.to_dict())
		var fp := FigurePainter.new(spec); fp._rig()
		check(fp.H == HEIGHTS[race] and FigurePainter.raster_scale(race) == 2.0, race + " released native logical height/raster")
		check(fp.leg_len + fp.torso_len + fp.head_h == fp.H and fp.arm_a == fp.arm_b, race + " original segment dimensions")
		check((fp.j["sc"] as Vector2).is_equal_approx((fp.j["hip"] as Vector2) + Vector2(fp.hunch * 0.5, -fp.torso_len)), race + " unchanged idle shoulder joint")
		for side: String in ["r", "l"]:
			check(is_equal_approx((fp.j["s" + side] as Vector2).distance_to(fp.j["e" + side]), fp.arm_a) and is_equal_approx((fp.j["e" + side] as Vector2).distance_to(fp.j["h" + side]), fp.arm_b), race + " native arm IK " + side)
		var image := FigurePainter.render(spec, "idle", 0.0)
		check(image.get_size() == FigurePainter.dims(race)["size"] and image.get_used_rect().has_area(), race + " visible native body frame")
		var portrait := Portrait.new(); portrait.set_unit(u)
		var bust := portrait.build_image()
		check(bust.get_size() == Vector2i(96, 96) and bust.get_data() == FigurePainter.render_bust(spec).get_data(), race + " direct native portrait uses imported painter")
		portrait.free()
		var torso := layer(spec, "torso")
		var armored := spec.duplicate(true); armored["body"] = {"tid": "mail_shirt", "sprite": "mail", "mat": "bronze", "q": 2}
		check(layer(armored, "torso").get_data() != torso.get_data(), race + " actual armor changes body art")
		armored["body"] = {}
		check(layer(armored, "torso").get_data() == torso.get_data(), race + " removed body item leaves no phantom armor")
		check(spec == copy and var_to_bytes(u.to_dict()) == before, race + " native frame/portrait/layers do not mutate their spec or Unit")
		u.body.wound_part("head")["severed"] = true
		u.body.wound_part("arm_upper_l")["severed"] = true
		var lost := FigurePainter.spec_for_unit(u)
		var after_loss := var_to_bytes(u.to_dict())
		check("head" in lost["lost"] and "hand_l" in lost["lost"], race + " native lost descendants retained")
		var helmet_lost := lost.duplicate(true); helmet_lost["helm"] = {"tid": "closed_helm", "sprite": "closed", "mat": "steel", "q": 2, "maker_race": "orc"}
		check(not layer(helmet_lost, "head").get_used_rect().has_area(), race + " severed head never redraws face/closed helm")
		var geared_lost := lost.duplicate(true); geared_lost["body"] = {"tid": "mail_shirt", "sprite": "mail", "mat": "steel", "q": 2}; geared_lost["hands"] = {"tid": "bracers", "sprite": "bracer", "mat": "steel", "q": 2}
		check(layer(geared_lost, "arm_l").get_data() == layer(lost, "arm_l").get_data(), race + " missing arm does not regrow armored sleeve/bracer")
		check(spec == copy and var_to_bytes(u.to_dict()) == after_loss, race + " lost-part rendering does not modify actual native wounds")
	var unit := Unit.create("human", "middle_kingdom")
	unit.equip["main_hand"] = Item.make("glaive", "steel", 2)
	unit.equip["helm"] = Item.make("closed_helm", "bronze", 2)
	unit.equip["body"] = Item.make("mail_shirt", "bronze", 2)
	unit.equip["helm"].mark = {"r": "orc", "n": "Native forge"}
	var wound: Dictionary = unit.body.wound_part("arm_upper_r")
	wound["layers"][0]["dmg"] = 0.8; wound["layers"][0]["kind"] = "mangled"; wound["layers"][0]["bleed"] = 0.2
	var native_spec := FigurePainter.spec_for_unit(unit)
	var glaive: Dictionary = unit.weapon().tmpl()
	check(not bool(glaive.get("two_handed", true)) and glaive.get("skill", "") == "axe" and glaive.get("reach", 0) == 70, "requested released Moon glaive definition is one-handed axe/reach70")
	check(is_equal_approx(float(glaive.get("len", 0.0)), 0.45) and is_equal_approx(float(glaive.get("bal", 0.0)), 0.10) and is_equal_approx(float(glaive.get("gyr", 0.0)), 0.24), "requested released Moon glaive length/balance/gyration retained")
	check(native_spec["weapon"]["mat"] == "steel" and native_spec["helm"]["mat"] == "bronze" and native_spec["helm"]["q"] == 2 and native_spec["body"]["tid"] == "mail_shirt", "actual equipment material/quality/body item retained")
	check(native_spec["wk"].get("arm_upper_r", "") == "m" and native_spec["bleed"].get("arm_upper_r", false) and native_spec["dmg"]["arm_upper_r"] == 0.8, "actual native wound rank/damage/bleed still feed art")
	check(FigurePainter.helm_maker(native_spec["helm"]) == "orc" and native_spec["helm"]["maker_race"] == "orc", "foreign maker helm design survives human wearer")
	check(FigurePainter.helm_maker({"tid": "crescent_helm", "culture": "moon_elf"}) == "moon_elf" and FigurePainter.helm_maker({"tid": "closed_helm"}) == "", "known template culture fallback; unknown maker never borrowed from wearer")
	check(FigurePainter.new(native_spec)._wkind() == "swing1" and not native_spec["weapon"]["two"], "native glaive is released one-handed slash pose")
	var two := native_spec.duplicate(true); two["weapon"]["two"] = true
	check(FigurePainter.new(two)._wkind() == "swing2", "explicit two-handed spec retains released two-hand pose")
	var actual_before := var_to_bytes(unit.to_dict()); var next_unit := Unit._next_uid; var next_item := Item._next_uid
	var rider := MountedRiderArt.render_layers(native_spec)
	var native_fp := FigurePainter.new(native_spec)
	check(rider["ok"] and rider["hip"] == Vector2.ZERO and rider["standing_height"] == 24.0, "actual imported human sits on unchanged logical saddle")
	check(is_equal_approx((rider["joints"]["pr"] as Vector2).distance_to(rider["knee_r"]), native_fp.leg_len * 0.5) and rider["knee_r"].x > rider["foot_r"].x, "mounted native limb lengths and bent knee persist")
	check(rider["mount_grip_hands"] == ["hand_l"] and not rider.has("rein_hands"), "one-hand native glaive leaves saddle grip; no head rope")
	check(var_to_bytes(unit.to_dict()) == actual_before and Unit._next_uid == next_unit and Item._next_uid == next_item, "mounted read/render never mutates Unit/Item or creates identities")
	check(snapshot() == campaign and Game.rng.state == rng_state, "all art fixture work conserves campaign and native RNG")
	Unit._next_uid = old_unit_uid; Item._next_uid = old_item_uid
	print("humanoid art import: %d checks, %d failures" % [checks, fails])
	return fails
