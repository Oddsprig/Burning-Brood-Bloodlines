extends RefCounted
## v0.106 guard test: saddle neck-base anchor and near-wing rider draw order.
## For every dragon breed and pose, the saddle point lies between the neck root
## and the front edge of the wing root, never behind it; the rider is drawn in
## front of the near wing.
##
## Testing rules (verbatim):
## "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."

const MORPHS := ["spirewing", "broadmantle", "reedrunner", "ironcrest", "stormkeel", "duskfin"]
# v0.106: follow the rig's supported-pose contract instead of guessing poses.
const ALL_POSES = DragonArt.SUPPORTED_POSES
const PROGRESS_STEPS := [0.0, 0.25, 0.5, 0.75]
const RIDER_UID := "person:v106:saddle:106"

var checks: int = 0
var fails: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL saddle neck base v0.106: " + message)

func vec2_of(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array:
		var arr: Array = value
		if arr.size() >= 2:
			return Vector2(float(arr[0]), float(arr[1]))
	return Vector2.ZERO

func snapshot() -> PackedByteArray:
	return var_to_bytes(Game._serialize({
		"world": Game.world,
		"company": Game.company,
		"squads": Game.squads,
		"gold": Game.gold,
		"day": Game.day,
	}))

func row_for(morph: String, size_class: String = "medium", gem_id: String = "sapphire") -> Dictionary:
	return {
		"id": "dragon:v106:" + morph + ":" + size_class,
		"name": "Neckseat",
		"gem_id": gem_id,
		"morph_id": morph,
		"size_class": size_class,
		"appearance_seed": 106,
		"stage": "adult",
		"alive": true,
		"rider_person_uid": "",
		"owner_person_uid": "",
		"history": [],
	}

func rider_world() -> Dictionary:
	# v0.106: a single native household/person drives the real rider resolver;
	# no generated world, Unit, Item, bond or campaign tick is needed.
	var person: Array = [106, 0, 0, float(Game.day) - 30.0 * People.year_days(), "", -1, 0, "Neckseat Rider", -1, -1, -1, "", []]
	Persons._identity_pad(person)
	person[Persons.PERSON_UID] = RIDER_UID
	person[Persons.HOUSE_UID] = "house:v106:saddle"
	var family: Dictionary = {"id": 106, "name": "Neckseat", "race": "human",
		"household_uid": "household:v106:saddle", "pp": [person], "kp": []}
	return {"towns": {"saddle": {"id": "saddle", "name": "Saddle", "econ": {"fams": [family]}}}}

func check_source_entries() -> void:
	# v0.106: verify source-pixel saddle anchor for every breed and wingbeat frame.
	for morph: String in MORPHS:
		for variant: int in range(SapphireSpirewingArt.FRAME_COUNT):
			var meta: Dictionary = SapphireSpirewingArt.metadata_for("sapphire", morph, variant)
			var seat_px: Vector2 = vec2_of(meta.get("seat_px", [0, 0]))
			var neck_px: Vector2 = vec2_of(meta.get("neck_root_px", [0, 0]))
			var wings: Dictionary = meta.get("wing_roots_px", {})
			var left_wing_px: Vector2 = vec2_of(wings.get("left", [0, 0]))
			var right_wing_px: Vector2 = vec2_of(wings.get("right", [0, 0]))
			var wing_front_x: float = maxf(left_wing_px.x, right_wing_px.x)
			var anchor: Vector2 = RiderFit.anchor_px(meta, morph)
			var label: String = "%s frame %d" % [morph, variant]
			check(anchor.is_equal_approx(seat_px), label + " anchor_px equals neck-base seat_px")
			check(anchor.x > wing_front_x and anchor.x < neck_px.x, label + " saddle point lies between front edge of wing root and neck root")
			check(anchor.x > left_wing_px.x and anchor.x > right_wing_px.x, label + " saddle point is never behind the wing root")
		var classic: Dictionary = DragonSpriteCatalog.entry(morph)
		var classic_seat: Vector2 = vec2_of(classic.get("seat_px", [0, 0]))
		var classic_neck: Vector2 = vec2_of(classic.get("neck_root_px", [0, 0]))
		var classic_dorsal: Vector2 = RiderFit.dorsal_wing(classic)
		var classic_anchor: Vector2 = RiderFit.anchor_px(classic, morph)
		check(classic_anchor.is_equal_approx(classic_seat), morph + " classic anchor_px equals neck-base seat_px")
		check(classic_anchor.x > classic_dorsal.x and classic_anchor.x < classic_neck.x, morph + " classic saddle lies between dorsal wing root and neck root")

func check_poses_and_callers(spec: Dictionary, layers: Dictionary) -> void:
	# v0.106: for every breed and pose, the posed saddle point lies between the
	# neck root and the front edge of the wing root, never behind it.
	var img_anchor: Vector2 = layers["image_anchor"]
	for morph: String in MORPHS:
		var row: Dictionary = row_for(morph, "medium", "sapphire")
		for pose: String in ALL_POSES:
			for progress: float in PROGRESS_STEPS:
				var model: Dictionary = DragonArt.model(row, pose, progress)
				var label: String = "%s %s@%.2f" % [morph, pose, progress]
				var is_valid: bool = bool(model.get("valid", false))
				check(is_valid, label + " model is valid")
				if not is_valid:
					continue
				RiderFit.decorate(model, row)
				var seat: Vector2 = model["seat"]
				var back_anchor: Vector2 = model["back_anchor"]
				var contact: Vector2 = RiderFit.dragon_contact(model)
				var neck_root: Vector2 = model["neck_root"]
				var left_wing: Vector2 = model["left_wing_root"]
				var right_wing: Vector2 = model["right_wing_root"]
				var wing_front: Vector2 = right_wing if right_wing.x >= left_wing.x else left_wing
				var wing_front_x: float = maxf(left_wing.x, right_wing.x)
				check(back_anchor.distance_to(seat) <= 0.05 and contact.distance_to(seat) <= 0.05, label + " back_anchor and dragon_contact match neck-base seat")
				check(back_anchor.x > wing_front_x and back_anchor.x < neck_root.x, label + " posed saddle x lies between front wing root and neck root, never behind wing root")
				var axis: Vector2 = neck_root - wing_front
				var axis_len_sq: float = maxf(axis.length_squared(), 0.0001)
				var along: float = (back_anchor - wing_front).dot(axis) / axis_len_sq
				check(along > 0.0 and along < 1.0, label + " posed saddle projects strictly between front wing root and neck root along spine")
				if bool(model.get("mountable", false)):
					var origin: Vector2 = Vector2(180.0, 140.0)
					var ppu: float = 2.0
					var placed: Transform2D = RiderFit.dragon_placement(model, layers, origin, ppu)
					var hip_canvas: Vector2 = placed * img_anchor
					var seat_canvas: Vector2 = origin + seat * ppu
					var wing_canvas_x: float = origin.x + wing_front_x * ppu
					var neck_canvas_x: float = origin.x + neck_root.x * ppu
					check(hip_canvas.distance_to(seat_canvas) <= RiderFit.ANCHOR_TOLERANCE, label + " placed rider hip sits on neck-base seat")
					check(hip_canvas.x > wing_canvas_x and hip_canvas.x < neck_canvas_x, label + " placed rider hip lies between wing root and neck root")
		# Check DragonMountPreviewArt framing caller for each breed
		for preview_pose: String in ["ground", "walk", "strike", "hit"]:
			var frame: Dictionary = DragonMountPreviewArt.framing(row, spec, preview_pose, false, 0.25)
			var fmodel: Dictionary = frame["model"]
			var fseat: Vector2 = frame["seat"]
			var fmodel_seat: Vector2 = fmodel["seat"]
			var fleft_wing: Vector2 = fmodel["left_wing_root"]
			var fright_wing: Vector2 = fmodel["right_wing_root"]
			var fwing_front_x: float = maxf(fleft_wing.x, fright_wing.x)
			var fneck: Vector2 = fmodel["neck_root"]
			var flabel: String = "%s preview %s" % [morph, preview_pose]
			check(fseat.distance_to(fmodel_seat) <= 0.05, flabel + " preview seat uses neck-base seat")
			check(fseat.x > fwing_front_x and fseat.x < fneck.x, flabel + " preview seat lies between front wing root and neck root")
			# v0.106: framing names its rider layers separately from the dragon.
			var preview_order: Array = frame["layer_order"]
			check(preview_order == ["far_rider", "dragon", "saddle", "near_rider"], flabel + " preview layer order draws saddle and near rider after dragon")

func check_near_wing_draw_order(tree: SceneTree, spec: Dictionary, layers: Dictionary) -> void:
	# v0.106: verify the rider (and saddle) is drawn in front of the near wing
	# across RiderFit, DragonView (battle), and DragonMountPreviewArt (raster).
	var fit_order: Array = RiderFit.LAYER_ORDER
	check(fit_order == ["far", "mount", "saddle", "near"], "RiderFit.LAYER_ORDER draws saddle and near rider in front of mount")
	# v0.106: native rider layers exclude the mount; the actual battle nodes and
	# composited overlap pixels below prove that saddle/near draw over its wing.
	var rider_order: Array = layers["layer_order"]
	check(rider_order == ["far", "saddle", "near"], "MountedRiderArt layer_order orders far, saddle, near")

	var saddle_img: Image = layers["saddle"]
	var near_img: Image = layers["near"]
	var fixture: Dictionary = rider_world()

	for morph: String in MORPHS:
		var row: Dictionary = row_for(morph, "medium", "sapphire")
		# v0.106: exercise production node creation and z-ordering on an orphan view.
		row["rider_person_uid"] = RIDER_UID
		var view: DragonView = DragonView.new()
		view._record = row
		view._rest_model = DragonArt.model(row, "rest", 0.0)
		view._ppu = DragonView.physical_ppu(row, view._rest_model)
		view._origin = Vector2(-24.0, -float(view._rest_model["ground_y"]) * view._ppu)
		view._current = DragonArt.model(row, "walk", 0.25)
		DragonView._update_gpu_layers(view, view._part_nodes, view._wound_nodes, view._current, {}, view._origin, view._ppu, int(row["appearance_seed"]))
		var original_world: Dictionary = Game.world
		Game.world = fixture
		view._resolve_rider()
		Game.world = original_world

		tree.root.call_deferred("add_child", view)
		await tree.process_frame

		var body_node: Node2D = view._part_nodes.get("body", null)
		check(body_node != null, morph + " DragonView creates SourceBody node containing near wing")
		var battle_layers_ok: bool = bool(view._rider_layers.get("ok", false))
		check(battle_layers_ok, morph + " DragonView resolves native rider layers")
		check(view._rider_far != null and view._rider_front != null and view._rider_saddle != null and view._rider_near != null, morph + " DragonView creates rider layer nodes")
		if body_node == null or not battle_layers_ok or view._rider_far == null or view._rider_front == null or view._rider_saddle == null or view._rider_near == null:
			check(false, morph + " DragonView required child node missing")
		else:
			view._place_rider()
			check(view._rider_far.z_index == 0 and view._rider_far.get_index() < body_node.get_index(), morph + " DragonView draws far rider behind dragon body")
			check(view._rider_front.z_index > body_node.z_index, morph + " DragonView draws rider front container (z_index=1) in front of near wing on SourceBody (z_index=0)")
			check(view._rider_saddle.get_parent() == view._rider_front and view._rider_near.get_parent() == view._rider_front and view._rider_saddle.get_index() < view._rider_near.get_index(), morph + " DragonView draws saddle then near rider in front of near wing")
			var battle_anchor: Vector2 = view._rider_layers["image_anchor"]
			var hip_battle: Vector2 = view._rider_near.transform * battle_anchor
			var cur_left_wing: Vector2 = view._current["left_wing_root"]
			var cur_right_wing: Vector2 = view._current["right_wing_root"]
			var cur_neck: Vector2 = view._current["neck_root"]
			var wing_battle_x: float = view._origin.x + maxf(cur_left_wing.x, cur_right_wing.x) * view._ppu
			var neck_battle_x: float = view._origin.x + cur_neck.x * view._ppu
			check(hip_battle.x > wing_battle_x and hip_battle.x < neck_battle_x, morph + " DragonView battle rider hip lies between front wing root and neck root")

		view.queue_free()
		await tree.process_frame

		# 2. Software raster composite proof: where near rider/saddle overlaps the dragon/wing,
		# the composited pixel matches the front rider/saddle pixel (drawn over the near wing).
		var frame: Dictionary = DragonMountPreviewArt.framing(row, spec, "ground", false, 0.0)
		var origin: Vector2 = frame["origin"]
		var ppu: float = float(frame["pixels_per_unit"])
		var fmodel: Dictionary = frame["model"]
		var xf: Transform2D = RiderFit.dragon_placement(fmodel, layers, origin, ppu)
		var w: int = DragonMountPreviewArt.IMAGE_SIZE.x
		var h: int = DragonMountPreviewArt.IMAGE_SIZE.y

		var dragon_cv: PixelCanvas = PixelCanvas.new(w, h)
		DragonArt.draw(dragon_cv, row, String(frame["pose"]), origin, ppu, 0.0, {})
		var dragon_img: Image = dragon_cv.to_image()

		var front_cv: PixelCanvas = PixelCanvas.new(w, h)
		# v0.106: use the preview's real inverse-mapped raster compositor.
		DragonMountPreviewArt._blend(front_cv, saddle_img, xf)
		DragonMountPreviewArt._blend(front_cv, near_img, xf)
		var front_img: Image = front_cv.to_image()

		var comp_img: Image = DragonMountPreviewArt.image_for(row, spec, "ground", false, 0.0)
		# v0.106: every possible overlap lies inside the front image's used rect;
		# scan all of those pixels, without a full-canvas GDScript loop.
		var area: Rect2i = front_img.get_used_rect()
		var overlap_distinct: int = 0
		var front_wins: int = 0
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				var f_col: Color = front_img.get_pixel(x, y)
				if f_col.a <= 0.98:
					continue
				var d_col: Color = dragon_img.get_pixel(x, y)
				if d_col.a <= 0.90:
					continue
				var diff: float = absf(f_col.r - d_col.r) + absf(f_col.g - d_col.g) + absf(f_col.b - d_col.b)
				if diff <= 0.12:
					continue
				overlap_distinct += 1
				var c_col: Color = comp_img.get_pixel(x, y)
				if absf(c_col.r - f_col.r) < 0.03 and absf(c_col.g - f_col.g) < 0.03 and absf(c_col.b - f_col.b) < 0.03:
					front_wins += 1
		check(overlap_distinct > 10 and front_wins == overlap_distinct, "%s raster composite draws rider in front of dragon and near wing (%d/%d overlap pixels)" % [morph, front_wins, overlap_distinct])

func run(tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	var before: PackedByteArray = snapshot()
	var rs: int = Game.rng.state
	var next_unit: int = Unit._next_uid
	var next_item: int = Item._next_uid

	var spec: Dictionary = FigurePainter.spec_generic("human", Color("#397e92"), Color("#d9bd71"), 27)
	spec["weapon"] = {}
	var layers: Dictionary = MountedRiderArt.render_layers(spec)
	var layers_ok: bool = bool(layers.get("ok", false))
	check(layers_ok, "rider layers render for saddle neck-base test")
	if not layers_ok:
		check(false, "cannot run saddle neck-base checks without rendered rider layers")
	else:
		check_source_entries()
		check_poses_and_callers(spec, layers)
		await check_near_wing_draw_order(tree, spec, layers)

	check(snapshot() == before and Game.rng.state == rs and Unit._next_uid == next_unit and Item._next_uid == next_item, "saddle neck-base checks conserve campaign state, RNG, and UID counters")
	print("saddle neck base v0.106: %d checks, %d failures, %d ms" % [checks, fails, Time.get_ticks_msec() - started])
	return fails
