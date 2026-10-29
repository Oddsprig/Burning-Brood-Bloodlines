extends RefCounted
## Rider fit for every dragon form and every horse coat. No campaign writes.
var checks := 0
var fails := 0
const MORPHS := ["spirewing", "broadmantle", "reedrunner", "ironcrest", "stormkeel", "duskfin"]

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL rider fit: " + why)

func snapshot() -> PackedByteArray:
	return var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company, "squads": Game.squads, "gold": Game.gold, "day": Game.day}))

func vec2_of(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

func opaque(image: Image) -> int:
	var pixels := 0
	var bytes := image.get_data()
	for i in range(3, bytes.size(), 4):
		if bytes[i] > 127:
			pixels += 1
	return pixels

func anchor_matches(entry: Dictionary, morph: String, label: String) -> void:
	var shift: Vector2 = RiderFit.FORM_ANCHOR[morph]
	var size: Array = entry.get("image_size", [128, 96])
	var canvas := float(size[0]) / 128.0
	var dorsal := RiderFit.dorsal_wing(entry)
	var neck := vec2_of(entry.get("neck_root_px", [0, 0]))
	var head := 1.0 if neck.x >= dorsal.x else -1.0
	var expected := Vector2(dorsal.x - head * shift.x * canvas, dorsal.y + shift.y * canvas)
	var anchor := RiderFit.anchor_px(entry, morph)
	check(anchor.is_equal_approx(expected), label + " anchor is the per-form step off the higher wing root")
	check(anchor.y > dorsal.y, label + " anchor sits below the higher wing root")
	if head > 0.0:
		check(anchor.x < dorsal.x, label + " anchor is tailward of the higher wing root")
	else:
		check(anchor.x > dorsal.x, label + " anchor is tailward of the higher wing root")
	check(anchor.distance_to(vec2_of(entry.get("seat_px", [0, 0]))) > 1.0, label + " anchor is not the neck seat")

func saddle_under(layers: Dictionary) -> bool:
	var saddle: Image = layers["saddle"]
	var near: Image = layers["near"]
	var combined: Image = layers["image"]
	var clear := false
	var covered := false
	var size := combined.get_size()
	for y in size.y:
		for x in size.x:
			var s := saddle.get_pixel(x, y)
			var n := near.get_pixel(x, y)
			var c := combined.get_pixel(x, y)
			if s.a > 0.5 and n.a < 0.05 and c.a > 0.5:
				clear = true
			if n.a > 0.95 and s.a > 0.5 and absf(c.r - n.r) < 0.02 and absf(c.g - n.g) < 0.02 and absf(c.b - n.b) < 0.02 and absf(c.a - n.a) < 0.02:
				covered = true
			if clear and covered:
				return true
	return false

func row_for(morph: String, size: String) -> Dictionary:
	return {"id": "dragon:fit:" + morph + ":" + size, "name": "Fit", "gem_id": "emerald", "morph_id": morph,
		"size_class": size, "appearance_seed": 27, "stage": "adult", "alive": true,
		"rider_person_uid": "", "owner_person_uid": "", "history": []}

func run(_tree: SceneTree) -> int:
	var before := snapshot()
	var rs := Game.rng.state
	var next_unit := Unit._next_uid
	var next_item := Item._next_uid
	var spec := FigurePainter.spec_generic("human", Color("#397e92"), Color("#d9bd71"), 27)
	spec["weapon"] = {}
	var copied := spec.duplicate(true)
	var layers := MountedRiderArt.render_layers(spec)
	check(bool(layers.get("ok", false)) and spec == copied, "unarmed human rider renders without mutating the spec")
	check(str(layers.get("pose", "")) == "straddle", "rider pose is straddle")
	var joints: Dictionary = layers["joints"]
	check((joints["kr"] - joints["pr"]).x > 0.0 and (joints["kl"] - joints["pl"]).x < 0.0, "near and far thighs have opposite x")
	var order: Array = layers["layer_order"]
	check(order.find("saddle") >= 0 and order.find("near") > order.find("saddle"), "saddle layer is before the near rider")
	var fit_order: Array = RiderFit.LAYER_ORDER
	check(fit_order.find("saddle") > fit_order.find("mount") and fit_order.find("near") > fit_order.find("saddle"), "draw order is far, mount, saddle, near")
	check(opaque(layers["saddle"]) > 40, "saddle layer has ink")
	check(saddle_under(layers), "saddle shows where the near body is clear, and the near body covers the saddle")
	check(not layers.has("rein_hands"), "no head rope")
	for hand: String in ["hand_r", "hand_l"]:
		check(layers["mount_grip_hands"].has(hand) and (layers[hand] as Vector2).is_equal_approx(layers["mount_handles"][hand]), "unarmed " + hand + " is on a saddle handle")
	var small_scale := 0.0
	var colossal_scale := 0.0
	for morph: String in MORPHS:
		var meta := SapphireSpirewingArt.metadata_for("emerald", morph, 1)
		anchor_matches(meta, morph, morph + " code")
		var classic := DragonSpriteCatalog.entry(morph)
		anchor_matches(classic, morph, morph + " classic")
		var model := DragonArt.model(row_for(morph, "medium"), "rest", 0.0)
		check(bool(model.get("valid", false)), morph + " rest model")
		if not bool(model.get("valid", false)):
			continue
		var neck_seat: Vector2 = model["seat"]
		RiderFit.decorate(model, row_for(morph, "medium"))
		var expected: Vector2 = (model["whole_xf"] as Transform2D) * RiderFit.anchor_px(meta, morph)
		check((model["back_anchor"] as Vector2).distance_to(expected) <= 0.05, morph + " back anchor follows the body transform")
		check((model["seat"] as Vector2).is_equal_approx(neck_seat), morph + " neck seat stays put")
		check(float(model["withers_height"]) > 0.0, morph + " withers height")
		var scale := RiderFit.dragon_logical_scale(model, layers)
		check(RiderFit.in_band("dragon", float(model["withers_height"]), float(layers["standing_height"]), scale), morph + " rider ratio is in the dragon band")
		var hip: Vector2 = MountedRiderArt.placement(layers, model["back_anchor"], scale, float(model.get("seat_angle", 0.0))) * layers["image_anchor"]
		check(hip.distance_to(model["back_anchor"]) <= RiderFit.ANCHOR_TOLERANCE, morph + " hip lies on the back anchor")
		check(opaque(layers["saddle"]) > 40 and str(layers["pose"]) == "straddle", morph + " uses the straddling rider and its saddle layer")
	var small_model := DragonArt.model(row_for("spirewing", "small"), "rest", 0.0)
	var huge_model := DragonArt.model(row_for("spirewing", "colossal"), "rest", 0.0)
	RiderFit.decorate(small_model, row_for("spirewing", "small"))
	RiderFit.decorate(huge_model, row_for("spirewing", "colossal"))
	small_scale = RiderFit.dragon_logical_scale(small_model, layers)
	colossal_scale = RiderFit.dragon_logical_scale(huge_model, layers)
	check(RiderFit.in_band("dragon", float(small_model["withers_height"]), float(layers["standing_height"]), small_scale), "small spirewing ratio is in band")
	check(RiderFit.in_band("dragon", float(huge_model["withers_height"]), float(layers["standing_height"]), colossal_scale), "colossal spirewing ratio is in band")
	check(colossal_scale > small_scale, "a larger dragon increases the seated scale")
	for coat: String in HorseArt.COATS:
		var frame := HorseArt.frame(coat, "idle", 0)
		check(frame != null, coat + " horse frame paints")
		var image_pt := HorseArt.back_anchor("idle", 0) + HorseArt.ANCHOR
		check(image_pt.x > 32.0 and image_pt.x < 43.0, coat + " saddle hollow is behind the withers")
		var withers := HorseArt.withers_px("idle", 0) * HorseDoll.HORSE_SCALE
		check(withers > 0.0, coat + " withers height")
		var scale := RiderFit.logical_scale("horse", withers, float(layers["standing_height"]))
		check(RiderFit.in_band("horse", withers, float(layers["standing_height"]), scale), coat + " rider ratio is in the horse band")
		var seat := HorseArt.back_anchor("idle", 0) * HorseDoll.HORSE_SCALE
		var placed := RiderFit.horse_placement(layers, seat, withers, 1, 0.0)
		var hip: Vector2 = placed * layers["image_anchor"]
		check(hip.distance_to(seat) <= RiderFit.ANCHOR_TOLERANCE, coat + " hip lies on the horse back anchor")
		check(str(layers["pose"]) == "straddle" and (joints["kr"] - joints["pr"]).x > 0.0 and (joints["kl"] - joints["pl"]).x < 0.0, coat + " rider straddles")
		check(order.find("saddle") < order.find("near") and opaque(layers["saddle"]) > 40, coat + " saddle layer is under the rider")
	check(snapshot() == before and Game.rng.state == rs and Unit._next_uid == next_unit and Item._next_uid == next_item, "fit checks do not write the campaign")
	print("rider fit v072: %d checks, %d failures" % [checks, fails])
	return fails
