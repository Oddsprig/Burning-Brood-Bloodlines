class_name MountedRiderArt
extends RefCounted
## Additive seated native figure, for visual previews only. Hip/seat is logical
## (0,0), facing right, y down; native human standing height remains 24 units.
## Never scale this rider by the dragon's physical body scale. No live rider
## assignment, Units, Items, campaign RNG or battle state is created here.

static func spec_for_unit(unit: Unit) -> Dictionary:
	return FigurePainter.spec_for_unit(unit).duplicate(true)

static func _hand_present(fp: FigurePainter, side: String) -> bool:
	return not fp._lost("arm_upper_" + side) and not fp._lost("arm_lower_" + side) and not fp._lost("hand_" + side)

static func _foot_present(fp: FigurePainter, side: String) -> bool:
	return not fp._lost("leg_upper_" + side) and not fp._lost("leg_lower_" + side) and not fp._lost("foot_" + side)

static func _mount_handles(fp: FigurePainter) -> Dictionary:
	var reach := fp.arm_a + fp.arm_b - 0.05
	var fore := Vector2(maxf(3.4, fp.hipw * 0.52), -3.1)
	return {"hand_r": FigurePainter._reach(fp.j["sr"], fore, reach),
		"hand_l": FigurePainter._reach(fp.j["sl"], fore + Vector2(-0.5, -0.35), reach)}

static func _seated_rig(fp: FigurePainter) -> void:
	fp.pose = "idle"; fp.t = 0.0
	fp._rig()
	var hip := Vector2.ZERO
	var shoulder := Vector2(1.75 + fp.hunch * 0.35, -fp.torso_len * 0.96)
	fp.j["hip"] = hip; fp.j["sc"] = shoulder
	fp.j["hc"] = shoulder + Vector2(0.85 + fp.hunch, -fp.head_h * 0.5 + fp.hunch * 0.6)
	fp.j["sr"] = shoulder + Vector2(-0.85, 1.0)
	fp.j["sl"] = shoulder + Vector2(1.45, 0.95)
	# Straddling mount seat: thighs angle downward-forward along the flank and shins
	# drop down/slightly back into the stirrups. Segment lengths are native race metrics.
	var half_leg := fp.leg_len * 0.5
	for side: String in ["r", "l"]:
		var near: bool = side == "r"
		var thigh_dir := Vector2(0.55, 0.835).normalized() if near else Vector2(0.58, 0.815).normalized()
		var shin_dir := Vector2(-0.18, 0.984).normalized() if near else Vector2(-0.22, 0.976).normalized()
		var pelvis := hip + Vector2(-0.45, 0.1) if near else hip + Vector2(0.55, -0.35)
		var knee := pelvis + thigh_dir * half_leg
		fp.j["p" + side] = pelvis; fp.j["k" + side] = knee
		fp.j["f" + side] = knee + shin_dir * half_leg
	var reach := fp.arm_a + fp.arm_b - 0.05
	var weapon_kind := fp._wkind()
	var weapon_hand: bool = weapon_kind != "none" and _hand_present(fp, "r") and not bool(fp.spec.get("dead", false))
	var handles: Dictionary = _mount_handles(fp)
	var right_target: Vector2 = shoulder + Vector2(reach * 0.52, -0.5) if weapon_hand else handles["hand_r"]
	fp.j["hr"] = FigurePainter._reach(fp.j["sr"], right_target, reach)
	fp.j["wdir"] = Vector2(0.12, -1.0).normalized()
	fp.j["grip"] = fp.j["hr"]
	var left_target: Vector2 = handles["hand_l"]
	if not fp._it("shield").is_empty(): left_target = shoulder + Vector2(reach * 0.3, fp.torso_len * 0.45)
	if weapon_hand and weapon_kind in ["swing2", "thrust2"]:
		left_target = (fp.j["hr"] as Vector2) + (fp.j["wdir"] as Vector2) * (3.0 if weapon_kind == "swing2" else 4.0) * fp.gs
	fp.j["hl"] = FigurePainter._reach(fp.j["sl"], left_target, reach)
	fp.j["er"] = FigurePainter._ik(fp.j["sr"], fp.j["hr"], fp.arm_a, fp.arm_b, 1.0)
	fp.j["el"] = FigurePainter._ik(fp.j["sl"], fp.j["hl"], fp.arm_a, fp.arm_b, 1.0)

static func _left_limb(pid: String) -> bool:
	return pid.ends_with("_l") and (pid.begins_with("arm_") or pid.begins_with("hand") or pid.begins_with("finger") or pid.begins_with("leg_") or pid.begins_with("foot") or pid.begins_with("toe"))

static func _wounds_for(fp: FigurePainter, far: bool) -> void:
	var original: Dictionary = fp.spec
	var filtered: Dictionary = original.duplicate(true)
	for key: String in ["dmg", "wk", "bleed"]:
		var marks: Dictionary = {}
		for pid: String in original.get(key, {}):
			if _left_limb(str(pid)) == far: marks[pid] = original[key][pid]
		filtered[key] = marks
	fp.spec = filtered; fp._wounds(); fp.spec = original

static func _stirrup(fp: FigurePainter, side: String, foreground: bool = false) -> void:
	if not _foot_present(fp, side): return
	var foot: Vector2 = fp.j["f" + side]
	var hip: Vector2 = fp.j["p" + side]
	var leather := FigurePainter.LEATHER.darkened(0.18 if side == "r" else 0.32)
	var metal := FigurePainter.metal("bronze", 1)
	if not foreground:
		# Stirrup leather strap descending from the saddle bar down the flank.
		fp.cv.begin()
		fp.cv.capsule(hip + Vector2(0.35, 0.2), foot + Vector2(-0.35, 0.55), 0.24, leather)
		fp.cv.end(FigurePainter.ol(leather), 0.05)
	# Open metal stirrup iron cradling the boot sole.
	fp.cv.begin()
	fp.cv.capsule(foot + Vector2(-1.15, 0.35), foot + Vector2(-1.15, 1.45), 0.18, metal["dark"])
	fp.cv.capsule(foot + Vector2(-1.25, 1.45), foot + Vector2(1.95 * fp.gs, 1.45), 0.22, metal["light"])
	fp.cv.capsule(foot + Vector2(1.85 * fp.gs, 1.45), foot + Vector2(1.55 * fp.gs, 0.25), 0.18, metal["base"])
	fp.cv.capsule(foot + Vector2(-0.5, 0.15), foot + Vector2(1.55 * fp.gs, 0.25), 0.14, metal["shine"])
	fp.cv.end(FigurePainter.ol(metal["dark"]), 0.04)

static func _draw_saddle(fp: FigurePainter) -> void:
	var leather := FigurePainter.LEATHER
	var dark_leather := leather.darkened(0.28)
	var light_leather := leather.lightened(0.16)
	var pad_col := (fp.prim as Color).darkened(0.34)
	var trim_col := (fp.sec as Color).darkened(0.06)
	var metal := FigurePainter.metal("bronze", 1)
	var hw := fp.hipw * 0.5
	var foot_r: Vector2 = fp.j["fr"]
	var girth_y := maxf(4.8, foot_r.y - 0.45)

	# 1. Chest girth (cinch) strap wrapping down around the mount's ribcage + breastcollar.
	fp.cv.begin()
	fp.cv.capsule(Vector2(0.85, 0.2), Vector2(0.65, girth_y), 0.62, dark_leather)
	fp.cv.capsule(Vector2(0.85, 0.4), Vector2(0.65, girth_y - 0.2), 0.24, leather)
	fp.cv.capsule(Vector2(hw * 0.85, -0.35), Vector2(hw * 1.48, 2.35), 0.44, dark_leather)
	fp.cv.end(FigurePainter.ol(dark_leather), 0.08)
	var buckle_y := girth_y * 0.54
	fp.cv.begin()
	fp.cv.ellipse(Vector2(0.74, buckle_y), 0.58, 0.46, metal["light"])
	fp.cv.ellipse(Vector2(0.74, buckle_y), 0.26, 0.20, dark_leather.darkened(0.25))
	fp.cv.capsule(Vector2(0.55, buckle_y), Vector2(0.95, buckle_y), 0.11, metal["shine"])
	fp.cv.ellipse(Vector2(hw * 1.05, 0.55), 0.42, 0.42, metal["base"])
	fp.cv.end(FigurePainter.ol(metal["dark"]), 0.04)

	# 2. Quilted saddle pad / shabrack blanket along the back line.
	fp.cv.begin()
	fp.cv.poly(PackedVector2Array([
		Vector2(-hw * 1.42, -0.35), Vector2(-hw * 0.2, -0.75), Vector2(hw * 1.32, -0.55),
		Vector2(hw * 1.25, 1.65), Vector2(0.2, 2.05), Vector2(-hw * 1.35, 1.55)
	]), pad_col)
	fp.cv.capsule(Vector2(-hw * 1.28, 1.45), Vector2(0.2, 1.92), 0.16, trim_col)
	fp.cv.capsule(Vector2(0.2, 1.92), Vector2(hw * 1.18, 1.52), 0.16, trim_col)
	fp.cv.end(FigurePainter.ol(pad_col), 0.08)

	# 3. Molded leather saddle seat, thigh fender, raised cantle and high pommel.
	fp.cv.begin()
	fp.cv.capsule(Vector2(0.25, 0.35), Vector2(1.45, 2.55), 0.92, dark_leather)
	fp.cv.ellipse(Vector2(-0.1, 0.25), hw * 1.15, 1.05, leather)
	# Raised cantle cradling the rear of the pelvis.
	fp.cv.capsule(Vector2(-hw * 0.88, 0.25), Vector2(-hw * 1.28, -2.55), 0.78, leather)
	fp.cv.capsule(Vector2(-hw * 0.96, -0.1), Vector2(-hw * 1.24, -2.45), 0.36, light_leather)
	fp.cv.capsule(Vector2(-hw * 1.32, -2.6), Vector2(-hw * 0.95, -2.75), 0.22, metal["light"])
	# High pommel / horn rising in front of the groin.
	fp.cv.capsule(Vector2(hw * 0.82, 0.15), Vector2(hw * 1.16, -2.65), 0.74, leather)
	fp.cv.capsule(Vector2(hw * 0.88, -0.2), Vector2(hw * 1.12, -2.55), 0.34, light_leather)
	fp.cv.capsule(Vector2(hw * 0.92, -2.75), Vector2(hw * 1.22, -2.6), 0.22, metal["light"])
	fp.cv.end(FigurePainter.ol(leather), 0.09)

	# 4. Body-mounted saddle handles anchored to the pommel arch.
	var handles: Dictionary = _mount_handles(fp)
	for key: String in ["hand_l", "hand_r"]:
		var grip: Vector2 = handles[key]
		fp.cv.begin()
		fp.cv.capsule(Vector2(hw * 0.98, -1.9), grip, 0.28, dark_leather)
		fp.cv.capsule(grip + Vector2(-0.65, 0), grip + Vector2(0.65, 0), 0.34, metal["light"])
		fp.cv.end(FigurePainter.ol(leather), 0.05)

	# 5. Stirrup leather and iron on the saddle layer as well.
	_stirrup(fp, "r", false)

static func _trim_standing_skirt(fp: FigurePainter, size: Vector2i, anchor: Vector2, raster: float) -> void:
	# Standing tunics/coats draw a vertical hem down to +0.4*leg_len below the hip, which
	# sticks out horizontally in mid-air when seated. Trim the standing hem below the pelvis
	# so the seated waist rests in the saddle and the straddling thigh is unoccluded.
	var outline := FigurePainter.ol(fp.prim)
	for y in size.y:
		var ly := (float(y) + 0.5 - anchor.y) / raster
		if ly <= 0.35: continue
		for x in size.x:
			var idx := y * size.x + x
			if fp.cv.buf[idx].a <= 0.0: continue
			var lx := (float(x) + 0.5 - anchor.x) / raster
			var limit := 0.55 if lx < 0.0 else (0.55 + lx * 0.52)
			if ly > limit + 0.32:
				fp.cv.buf[idx] = Color.TRANSPARENT
			elif ly > limit:
				fp.cv.buf[idx] = outline

static func _draw_pommel_cap(fp: FigurePainter) -> void:
	var leather := FigurePainter.LEATHER
	var metal := FigurePainter.metal("bronze", 1)
	var hw := fp.hipw * 0.5
	fp.cv.begin()
	fp.cv.capsule(Vector2(hw * 0.86, -0.35), Vector2(hw * 1.14, -2.55), 0.52, leather.lightened(0.08))
	fp.cv.capsule(Vector2(hw * 0.92, -2.65), Vector2(hw * 1.20, -2.50), 0.20, metal["light"])
	fp.cv.end(FigurePainter.ol(leather), 0.06)

static func _draw_layer(fp: FigurePainter, kind: String, size: Vector2i, anchor: Vector2, raster: float) -> Image:
	fp.cv = PixelCanvas.new(size.x, size.y); fp.cv.set_frame(anchor, raster)
	match kind:
		"far":
			_stirrup(fp, "l", false); fp._arm("l"); fp._leg("l"); _wounds_for(fp, true)
		"saddle":
			_draw_saddle(fp)
		"near":
			fp._torso()
			_trim_standing_skirt(fp, size, anchor, raster)
			_stirrup(fp, "r", false)
			fp._leg("r")
			_stirrup(fp, "r", true)
			_draw_pommel_cap(fp)
			if not fp._lost("head"): fp._head()
			else: fp.cv.dot((fp.j["sc"] as Vector2) + Vector2(0, -1), FigurePainter.BLOOD)
			fp._shield()
			var kind_weapon := fp._wkind()
			if kind_weapon != "none" and _hand_present(fp, "r") and not bool(fp.spec.get("dead", false)): fp._draw_weapon(fp.j["grip"], fp.j["wdir"])
			fp._arm("r")
			# Native two-hand grip overlay, without re-drawing an entire far arm.
			if kind_weapon in ["swing2", "thrust2"] and _hand_present(fp, "l"):
				fp.cv.begin(); fp.cv.ellipse(fp.j["hl"], fp.arm_r * 1.1 + 0.15, fp.arm_r * 1.1 + 0.15, fp.skin); fp._skin_end()
			_wounds_for(fp, false)
	return fp.cv.to_image()

## Images share one cropped pixel frame. Sockets/joints are in native logical
## units relative to seat, while image_anchor is the seat in cropped image pixels.
## Composite far behind mount, saddle on back, near over saddle/flank. No stretch.
static func render_layers(spec: Dictionary) -> Dictionary:
	var race := str(spec.get("race", "human"))
	if race not in FigurePainter.DETAILED_RACES: return {"ok": false, "reason": "A native humanoid figure is required."}
	var copied: Dictionary = spec.duplicate(true)
	var fp := FigurePainter.new(copied); _seated_rig(fp)
	var raster := FigurePainter.raster_scale(race)
	# Bounded room for native weapons, ears, head, boots and all race heights.
	var radius := maxf(40.0, fp.H * 1.6)
	var size := Vector2i(ceili(radius * 2.0 * raster), ceili(radius * 2.0 * raster))
	var anchor := Vector2(size) * 0.5
	var full: Dictionary = {}; var used := Rect2i()
	for kind: String in ["far", "saddle", "near"]:
		var image := _draw_layer(fp, kind, size, anchor, raster)
		full[kind] = image
		var occupied := image.get_used_rect()
		used = occupied if used.size == Vector2i.ZERO else used.merge(occupied)
	var crop := used.grow(2).intersection(Rect2i(Vector2i.ZERO, size))
	var images: Dictionary = {}; var combined := Image.create(crop.size.x, crop.size.y, false, Image.FORMAT_RGBA8); combined.fill(Color.TRANSPARENT)
	for kind: String in ["far", "saddle", "near"]:
		var image: Image = full[kind].get_region(crop)
		images[kind] = image
		combined.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	var local_to_image := Transform2D(0.0, Vector2(raster, raster), 0.0, anchor - Vector2(crop.position))
	var image_to_local := local_to_image.affine_inverse()
	var present: Dictionary = {"hand_r": _hand_present(fp, "r"), "hand_l": _hand_present(fp, "l"), "foot_r": _foot_present(fp, "r"), "foot_l": _foot_present(fp, "l"), "head": not fp._lost("head")}
	var mount_grip_hands: Array[String] = []
	var weapon_kind := fp._wkind()
	if present["hand_r"] and weapon_kind == "none" and not bool(copied.get("dead", false)): mount_grip_hands.append("hand_r")
	if present["hand_l"] and fp._it("shield").is_empty() and weapon_kind not in ["swing2", "thrust2"] and not bool(copied.get("dead", false)): mount_grip_hands.append("hand_l")
	return {"ok": true, "race": race, "far": images["far"], "saddle": images["saddle"], "near": images["near"], "image": combined,
		"seat": Vector2.ZERO, "hip": fp.j["hip"], "shoulder": fp.j["sc"], "head": fp.j["hc"],
		"hand_r": fp.j["hr"], "hand_l": fp.j["hl"], "knee_r": fp.j["kr"], "knee_l": fp.j["kl"], "foot_r": fp.j["fr"], "foot_l": fp.j["fl"],
		"joints": fp.j.duplicate(true), "socket_presence": present, "mount_grip_hands": mount_grip_hands, "mount_handles": _mount_handles(fp),
		"standing_height": fp.H, "seat_width": fp.hipw + 2.0, "raster_scale": raster,
		"metrics": {"torso": fp.torso_len, "head": fp.head_h, "leg": fp.leg_len, "upper_arm": fp.arm_a, "forearm": fp.arm_b},
		"local_to_image": local_to_image, "image_to_local": image_to_local, "image_anchor": local_to_image * Vector2.ZERO,
		"crop_rect": crop, "bounds": Rect2(image_to_local * Vector2.ZERO, Vector2(crop.size) / raster),
		"layer_order": ["far", "saddle", "near"], "visual_preview_only": true}

## Image-pixel to composite-pixel transform. Only scene pixels-per-unit enters;
## the host dragon's size multiplier must never be supplied as rider scaling.
static func placement(layers: Dictionary, seat: Vector2, pixels_per_unit: float = 1.0, seat_angle: float = 0.0) -> Transform2D:
	var world := Transform2D(seat_angle, Vector2.ONE * pixels_per_unit, 0.0, seat)
	return world * (layers["image_to_local"] as Transform2D)
