extends RefCounted
## Native visual-fit composite contract. Body renderer may use observed raster
## anchors; no generated world, rider assignment, bond or combat is exercised.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon mount preview: " + why)

func row(size: String = "medium", morph: String = "spirewing") -> Dictionary:
	return {"id": "dragon:preview:1", "name": "Cinderwake", "gem_id": "sapphire", "morph_id": morph,
		"size_class": size, "appearance_seed": 614, "stage": "adult", "alive": true,
		"rider_person_uid": "", "owner_person_uid": "", "history": []}

func snapshot() -> PackedByteArray:
	return var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "squads": Game.squads, "gold": Game.gold, "day": Game.day}))

func visible(image: Image) -> int:
	var count := 0; var bytes := image.get_data()
	for i in range(3, bytes.size(), 4):
		if bytes[i] > 127: count += 1
	return count

func run(_tree: SceneTree) -> int:
	var before := snapshot(); var rs := Game.rng.state; var next_unit := Unit._next_uid; var next_item := Item._next_uid
	var spec := FigurePainter.spec_generic("human", Color("#397e92"), Color("#d9bd71"), 63)
	spec["sex"] = "female"; spec["age"] = 54
	spec["weapon"] = {"tid": "spear", "sprite": "spear", "mat": "steel", "q": 2, "reach": 220.0, "two": true}
	var original_spec := spec.duplicate(true)
	var original_row := row(); var saved_row := original_row.duplicate(true)
	var native := MountedRiderArt.render_layers(spec)
	var person_bounds: Rect2 = native["bounds"]
	for size: String in ["small", "medium", "large", "huge", "colossal"]:
		for pose: String in ["ground", "walk", "strike", "hit"]:
			var canonical := "idle" if pose == "ground" else pose
			var whole := DragonMountPreviewArt.framing(row(size), spec, pose, false, 0.37)
			var close := DragonMountPreviewArt.framing(row(size), spec, pose, true, 0.37)
			var whole_bounds: Rect2 = whole["bounds"]; var rider_bounds: Rect2 = whole["rider_bounds"]
			check(whole["pose"] == canonical and whole["model"]["pose"] == canonical and whole["progress"] == 0.37 and not whole["closeup"] and close["closeup"], size + " " + pose + " actual native pose/progress/camera metadata")
			check(whole_bounds.grow(0.001).encloses(whole["model"]["bounds"]) and whole_bounds.grow(0.001).encloses(rider_bounds), size + " " + pose + " whole frame contains model plus native carried equipment")
			var native_placement := Transform2D(float(whole["seat_angle"]), Vector2.ONE, 0.0, whole["seat"])
			var expected_bounds := DragonMountPreviewArt._transformed_bounds(person_bounds, native_placement)
			check(rider_bounds.size.is_equal_approx(expected_bounds.size) and whole["rider_layers"]["standing_height"] == 24.0, size + " " + pose + " person world height/weapon bounds rotate with saddle without host scaling")
			check(rider_bounds.position.is_equal_approx(expected_bounds.position), size + " " + pose + " seated image logical anchor contacts actual posed back socket")
			check(close["bounds"].grow(0.001).encloses(close["rider_bounds"]) and close["seat_width"] == whole["seat_width"], size + " " + pose + " close-up retains actual rider dimensions and gear")
			var pixel_seat: Vector2 = whole["origin"] + whole["seat"] * float(whole["pixels_per_unit"])
			var placement := MountedRiderArt.placement(whole["rider_layers"], pixel_seat, float(whole["pixels_per_unit"]), float(whole["seat_angle"]))
			check((placement * whole["rider_layers"]["image_anchor"]).is_equal_approx(pixel_seat), size + " " + pose + " crop transform maps hips exactly to drawn saddle")
			check(whole["model"]["hind_legs"] == 2 and whole["model"]["wing_forelimbs"] == 2 and whole["model"]["front_legs"] == 0, size + " " + pose + " wyvern anatomy retained")
			check(whole["valid"] and whole["supported_poses"].has("walk") and whole["supported_poses"].has("strike") and not whole["supported_poses"].has("flight"), size + " coherent grounded pose vocabulary, no articulated-leg or flight claim")
	var small := DragonMountPreviewArt.framing(row("small"), spec)
	var giant := DragonMountPreviewArt.framing(row("colossal"), spec)
	var giant_close := DragonMountPreviewArt.framing(row("colossal"), spec, "ground", true)
	check(giant["model"]["linear_scale"] > small["model"]["linear_scale"] and giant["rider_bounds"].size == small["rider_bounds"].size, "host alone changes physical scale")
	check(giant_close["pixels_per_unit"] > giant["pixels_per_unit"] and giant_close["bounds"].size.x < giant["bounds"].size.x, "close-up changes scene camera instead of relative mount/person proportions")
	var seat_widths := {}
	for race: String in FigurePainter.DETAILED_RACES:
		var given := FigurePainter.spec_generic(race, Color("#397e92"), Color("#d9bd71"), 63)
		var frame := DragonMountPreviewArt.framing(original_row, given, "ground", true)
		var fp := FigurePainter.new(given)
		check(frame["seat_width"] == fp.hipw + 2.0 and frame["rider_layers"]["race"] == race, race + " actual native race saddle width")
		seat_widths[race] = frame["seat_width"]
		check(frame["mount_grips"].size() == frame["rider_layers"]["mount_grip_hands"].size(), race + " only available native hands grip saddle handles")
		for grip: Dictionary in frame["mount_grips"]:
			check(frame["rider_layers"]["socket_presence"][grip["hand"]] and (grip["hand_point"] as Vector2).is_equal_approx(grip["handle_point"]), race + " native hand meets actual nearby saddle handle")
		check(not frame.has("reins") and not frame.has("bridle"), race + " no head or neck rope/bridle exists")
	check(seat_widths["troll"] != seat_widths["human"], "race saddle fit is not a normalized universal rider")
	check(DragonMountPreviewArt.framing(original_row, spec)["mount_grips"].is_empty(), "two-handed native weapon does not acquire forced mount-handle grip")
	var loss := spec.duplicate(true); loss["weapon"] = {}; loss["lost"] = ["arm_upper_r", "arm_lower_r", "hand_r", "leg_upper_l", "leg_lower_l", "foot_l", "head"]
	var lost := DragonMountPreviewArt.framing(original_row, loss, "ground", true)
	check(not lost["rider_layers"]["socket_presence"]["head"] and not lost["rider_layers"]["socket_presence"]["foot_l"] and not lost["rider_layers"]["socket_presence"]["hand_r"], "real head/limb losses persist into composite metadata")
	check(lost["mount_grips"].size() == 1 and lost["mount_grips"][0]["hand"] == "hand_l", "missing right hand never acquires phantom saddle grip")
	for root: String in ["wing_upper_r", "leg_upper_l", "jaw", "neck"]:
		var damage_state := {"lost": [root], "dmg": {"torso": 0.6}, "wk": {"torso": "cut"}, "bleed": {"torso": true}, "blood": 0.5}
		var saved_damage := damage_state.duplicate(true)
		var injured := DragonMountPreviewArt.framing(original_row, without_weapon(spec), "walk", true, 0.37, damage_state)
		var excluded := DragonDamageArt.effective_lost(damage_state, injured["model"]["all_parts"])
		var visible_ids: Array[String] = []
		for part: Dictionary in injured["model"]["parts"]:
			visible_ids.append(str(part["id"]))
			check(not excluded.has(part["id"]), root + " only actual head separation excludes source layers")
		visible_ids.sort()
		check(visible_ids == (["body"] if root == "neck" else ["body", "head", "jaw"]), root + " coherent body retained; only neck-cut removes head and jaw")
		var wound_marks := DragonDamageArt.marks(damage_state, injured["model"]["all_parts"], injured["model"]["regions"])
		check(not wound_marks.is_empty(), root + " authored anatomical regions receive native injury overlay")
		check(injured["mountable"] and injured["rider_layers"]["standing_height"] == 24.0 and damage_state == saved_damage, root + " attached torso keeps true rider scale and pure damage state")
		for grip: Dictionary in injured["mount_grips"]:
			check((grip["hand_point"] as Vector2).is_equal_approx(grip["handle_point"]), root + " native hands remain at posed saddle handles")
	var mangled_body := DragonMountPreviewArt.framing(original_row, spec, "idle", false, 0.0, {"lost": ["torso"]})
	check(mangled_body["mountable"] and mangled_body["rider_layers"]["standing_height"] == 24.0, "mangled coherent body keeps native saddle/person scale; no invented body separation")
	for collapsed: String in ["prone", "dead"]:
		check(not DragonMountPreviewArt.framing(original_row, spec, collapsed)["mountable"], collapsed + " has no upright preview rider")
	# Bounded whole/seat raster checks. Relative mounting geometry above is tested
	# in world units; close-up deliberately crops the host rather than the rider.
	var image := DragonMountPreviewArt.image_for(original_row, spec)
	var close_image := DragonMountPreviewArt.image_for(original_row, spec, "ground", true)
	check(image.get_size() == Vector2i(720, 420) and close_image.get_size() == Vector2i(720, 420) and visible(image) > 100 and visible(close_image) > 100, "whole and seat composites produce visible fixed-size images")
	check(image.get_data() != close_image.get_data(), "whole and close-up are distinct real scene framings")
	check(image.get_data() == DragonMountPreviewArt.image_for(original_row, spec).get_data(), "whole composite deterministic")
	var without := original_spec.duplicate(true); without["weapon"] = {}
	check(DragonMountPreviewArt.image_for(original_row, without, "ground", true).get_data() != close_image.get_data(), "actual carried weapon appears in seat composite")
	check(DragonMountPreviewArt.image_for(original_row, loss, "ground", true).get_data() != close_image.get_data(), "actual head/limb loss reaches grounded composite image")
	check(original_row == saved_row and spec == original_spec and original_row["rider_person_uid"] == "", "model preview does not assign a rider or mutate copied identity/spec")
	check(snapshot() == before and Game.rng.state == rs and Unit._next_uid == next_unit and Item._next_uid == next_item, "all preview/frame/image calls conserve world, native identities and campaign RNG")
	print("dragon mount preview: %d checks, %d failures" % [checks, fails])
	return fails

func without_weapon(spec: Dictionary) -> Dictionary:
	var out: Dictionary = spec.duplicate(true); out["weapon"] = {}
	return out
