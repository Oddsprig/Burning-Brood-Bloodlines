extends RefCounted
## Native seated-joint and raster contract; no campaign generation or simulation.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL mounted rider: " + why)

func visible(image: Image) -> int:
	var pixels := 0; var bytes := image.get_data()
	for i in range(3, bytes.size(), 4):
		if bytes[i] > 127: pixels += 1
	return pixels

func snapshot() -> PackedByteArray:
	return var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "squads": Game.squads, "gold": Game.gold, "day": Game.day}))

func joint_contract(spec: Dictionary, layers: Dictionary, label: String) -> void:
	check(layers["ok"] and layers["visual_preview_only"], label + " native humanoid visual layers")
	var fp := FigurePainter.new(spec)
	check(layers["standing_height"] == fp.H and layers["raster_scale"] == FigurePainter.raster_scale(spec["race"]), label + " native height/detail scale unchanged")
	check(layers["seat"] == Vector2.ZERO and layers["hip"] == Vector2.ZERO and layers["shoulder"].y < 0 and layers["head"].y < layers["shoulder"].y, label + " hips sit on saddle, torso/head above")
	check(str(layers.get("pose", "")) == "straddle", label + " straddle pose")
	var joints: Dictionary = layers["joints"]
	for side: String in ["r", "l"]:
		var hip: Vector2 = joints["p" + side]; var knee: Vector2 = joints["k" + side]; var foot: Vector2 = joints["f" + side]
		var thigh := knee - hip
		var shin := foot - knee
		if side == "r":
			check(thigh.x > 0.0 and thigh.y > thigh.x and thigh.x > thigh.y * 0.2 and foot.y > knee.y, label + " near thigh down the flank " + side)
		else:
			check(thigh.x < 0.0 and thigh.y > absf(thigh.x) * 0.5 and foot.y > knee.y, label + " far thigh behind the body " + side)
		check(shin.y > absf(shin.x) * 3.0, label + " shin hangs " + side)
		check(is_equal_approx(hip.distance_to(knee), fp.leg_len * 0.5) and is_equal_approx(knee.distance_to(foot), fp.leg_len * 0.5), label + " original thigh/shin lengths " + side)
		var shoulder: Vector2 = joints["s" + side]; var elbow: Vector2 = joints["e" + side]; var hand: Vector2 = joints["h" + side]
		check(is_equal_approx(shoulder.distance_to(elbow), fp.arm_a) and is_equal_approx(elbow.distance_to(hand), fp.arm_b), label + " reachable native arm IK " + side)
	check((joints["kr"] - joints["pr"]).x * (joints["kl"] - joints["pl"]).x < 0.0, label + " legs are not on the same side")
	var pixel_to_local: Transform2D = layers["image_to_local"]
	var local_to_pixel: Transform2D = layers["local_to_image"]
	check((pixel_to_local * layers["image_anchor"]).is_equal_approx(Vector2.ZERO) and (pixel_to_local * (local_to_pixel * joints["hc"])).is_equal_approx(joints["hc"]), label + " cropped seat/head transform roundtrip")
	var seat := Vector2(120, 80); var far_seat := Vector2(640, 260)
	var small := MountedRiderArt.placement(layers, seat, 2.0)
	var giant := MountedRiderArt.placement(layers, far_seat, 2.0)
	check((small * layers["image_anchor"]).is_equal_approx(seat) and (giant * layers["image_anchor"]).is_equal_approx(far_seat), label + " exact saddle attachment at different mount positions")
	check(small.x == giant.x and small.y == giant.y and is_equal_approx(small.x.length(), 2.0 / layers["raster_scale"]), label + " dragon size never changes rider logical scale")
	var turned := MountedRiderArt.placement(layers, seat, 2.0, 0.17)
	check((turned * layers["image_anchor"]).is_equal_approx(seat) and is_equal_approx(turned.x.length(), small.x.length()), label + " seat angle rotates without stretching or detaching")
	var full: Image = layers["image"]; var size := full.get_size()
	for kind: String in ["far", "saddle", "near"]:
		var image: Image = layers[kind]
		check(image.get_size() == size and visible(image) > (40 if kind == "saddle" else 8), label + " visible common cropped " + kind + " layer")
	var used := full.get_used_rect()
	check(used.position.x > 0 and used.position.y > 0 and used.end.x < size.x and used.end.y < size.y, label + " gear/body crop has transparent safety margin")
	check(layers["bounds"].has_point(Vector2.ZERO) and layers["bounds"].has_point(joints["hc"]), label + " logical bounds contain seated anatomy")
	for hand: String in layers["mount_grip_hands"]:
		check(layers["socket_presence"][hand] and (layers[hand] as Vector2).is_equal_approx(layers["mount_handles"][hand]), label + " available hand grips actual saddle handle " + hand)
		check((layers["mount_handles"][hand] as Vector2).distance_to(Vector2.ZERO) < fp.torso_len + fp.hipw, label + " handle remains at body mount " + hand)
	check(not layers.has("rein_hands"), label + " no head-rope grip metadata")

func run(_tree: SceneTree) -> int:
	var native := snapshot(); var rs := Game.rng.state; var original_unit_uid := Unit._next_uid; var original_item_uid := Item._next_uid
	var images := {}
	for race: String in FigurePainter.DETAILED_RACES:
		if not MountedRiderArt.can_mount_race(race):
			check(not MountedRiderArt.render_layers({"race": race})["ok"], race + " fights on foot only and is rejected by MountedRiderArt")
			continue
		var spec := FigurePainter.spec_generic(race, Color("#397e92"), Color("#d9bd71"), 63)
		spec["sex"] = "female"; spec["age"] = 54
		var copied := spec.duplicate(true)
		var layers := MountedRiderArt.render_layers(spec)
		joint_contract(spec, layers, race)
		var repeated := MountedRiderArt.render_layers(spec)
		check(spec == copied and layers["image"].get_data() == repeated["image"].get_data(), race + " deterministic render and copied input")
		images[race] = layers["image"].get_data()
	check(not MountedRiderArt.can_mount_race("troll") and not MountedRiderArt.can_mount_race("giant"), "trolls and giants cannot mount horses")
	check(not MountedRiderArt.render_layers({"race": "troll"})["ok"] and not MountedRiderArt.render_layers({"race": "giant"})["ok"], "trolls and giants rejected by render_layers")
	check(images["human"] != images["orc"] and images["human"] != images["dwarf"] and images["moon_elf"] != images["goblin"] and images["orc"] != images["dwarf"], "native race silhouettes retained")
	# Actual native Unit and Item exist only in this test fixture. Runtime renderer
	# reads a copied native spec and never creates combat identities or equipment.
	var unit := Unit.create("human", "middle_kingdom")
	unit.look = {"skin": "#d4a27a", "hair": "#5a3a22", "beard": false, "seed": 63}; unit.sex = 1; unit.age = 54
	unit.equip["clothing"] = Item.make("tunic", "linen", 0)
	unit.equip["main_hand"] = Item.make("arming_sword", "steel", 2)
	unit.equip["off_hand"] = Item.make("round_shield", "bronze", 2)
	unit.equip["body"] = Item.make("lamellar_cuirass", "bronze", 2)
	unit.equip["feet"] = Item.make("shoes", "leather", 0)
	var before_unit := var_to_bytes(unit.to_dict()); var next_unit := Unit._next_uid; var next_item := Item._next_uid
	var actual := MountedRiderArt.spec_for_unit(unit)
	check(actual == FigurePainter.spec_for_unit(unit) and actual["sex"] == "female" and actual["age"] == 54 and actual["weapon"]["mat"] == "steel" and actual["body"]["tid"] == "lamellar_cuirass" and actual["feet"]["tid"] == "shoes", "actual Unit sex/age/real cuirass/shoes/equipment read through native spec")
	var equipped := MountedRiderArt.render_layers(actual)
	joint_contract(actual, equipped, "equipped actual human")
	check(equipped["mount_grip_hands"].is_empty(), "actual sword and shield occupy both hands; no forced saddle-handle grip")
	check(equipped["image"].get_data() != images["human"], "native equipped weapon/shield change seated appearance")
	check(var_to_bytes(unit.to_dict()) == before_unit and Unit._next_uid == next_unit and Item._next_uid == next_item, "native Unit/Item/body refs remain untouched by render/spec read")
	var healthy := FigurePainter.spec_generic("human", Color("#397e92"), Color("#d9bd71"), 63)
	healthy["sex"] = "male"; healthy["age"] = 25
	var young := MountedRiderArt.render_layers(healthy)
	var changed := healthy.duplicate(true); changed["sex"] = "female"; changed["age"] = 70
	check(MountedRiderArt.render_layers(changed)["image"].get_data() != young["image"].get_data(), "native sex/age face differences reach seated pose")
	var head := unit.body.wound_part("head")
	head["layers"][0]["dmg"] = 0.8; head["layers"][0]["kind"] = "cut"; head["layers"][0]["bleed"] = 0.3
	var wounded := MountedRiderArt.spec_for_unit(unit)
	check(wounded["wk"].get("head", "") == "c" and wounded["bleed"].get("head", false), "native body cut/bleed metadata preserved")
	check(MountedRiderArt.render_layers(wounded)["image"].get_data() != equipped["image"].get_data(), "native wound rendering changes seated head")
	unit.body.wound_part("arm_upper_r")["severed"] = true
	unit.body.wound_part("leg_upper_l")["severed"] = true
	var lost := MountedRiderArt.spec_for_unit(unit)
	var loss_layers := MountedRiderArt.render_layers(lost)
	check(not loss_layers["socket_presence"]["hand_r"] and not loss_layers["socket_presence"]["foot_l"], "native loss descendants remove hand/foot availability")
	check(loss_layers["image"].get_data() != MountedRiderArt.render_layers(wounded)["image"].get_data(), "lost native limbs/equipped sword are not redrawn")
	for weapon: String in ["spear", "greataxe", "longbow"]:
		changed = healthy.duplicate(true)
		changed["weapon"] = {"tid": weapon, "sprite": weapon, "mat": "steel", "q": 2, "reach": 220.0, "two": weapon != "longbow"}
		var armed := MountedRiderArt.render_layers(changed)
		joint_contract(changed, armed, "mounted " + weapon)
		if weapon != "longbow": check(armed["mount_grip_hands"].is_empty(), "two-hand weapon has no forced saddle-handle grip " + weapon)
		check(armed["image"].get_data() != young["image"].get_data(), "native " + weapon + " equipment retained")
	check(not MountedRiderArt.render_layers({"race": "wolf"})["ok"], "non-humanoid mount is not converted into a rider")
	check(snapshot() == native and Game.rng.state == rs and Unit._next_uid == next_unit and Item._next_uid == next_item, "all art operations conserve campaign/RNG/counters after explicit native test fixtures")
	Unit._next_uid = original_unit_uid; Item._next_uid = original_item_uid
	print("mounted rider art: %d checks, %d failures" % [checks, fails])
	return fails
