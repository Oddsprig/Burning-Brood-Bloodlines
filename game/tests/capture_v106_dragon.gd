extends RefCounted
## v0.106: Compare the real DragonRoost UI and battle MapView/UnitView/
## DragonView adapters with the OFF-by-default prototype. One tiny native
## person/dragon fixture, no generated world, combat steps or save IO.
## The prototype roost only overrides its yard's dragon painter; inspectors,
## layout and standing attendants still come from the real roost.
## Battle actors borrow the same registered Unit and use frozen strike
## presentation on the real battle map. This is not a live battle/HUD proof.
## v0.106: captions disclose provisional scale; battle uses the bound rider,
## while the prototype roost still draws only the rig and standing attendants.
##
## Headless validates ALL contexts and returns 2 (no PNGs), never a capture
## PASS. ONE later authorized rendered run writes the two comparison PNGs
## under test-results/v0.106 AND five review PNGs under
## test-results/v0.106/renders: rig_side_rest.png, rig_wings_spread.png,
## rig_flying.png, rig_rider_neck_saddle.png, old_vs_rig.png. Review poses
## are fixed samples (autoplay off, pose_at at a stated time; wing_beat is
## scanned for its most-open sample). No recording or user approval is
## produced here.
## Return codes: 0 PNGs saved, 2 headless/context checks only, 3 missing old
## or prototype context/fixture, 4 no image, 5 output/save failure.
##
## Run (rendered, authorized):
## Godot_v4.7.2-stable_win64_console.exe --path <repo>/game --rendering-driver opengl3 res://tests/runner.tscn -- --tests=res://tests/capture_v106_dragon.gd --watchdog=150
##
## Future test brief (do not run as part of this static edit task):
## "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."
## Future engine/GPU work also needs the shared process detector/lane lease.
## This capture is deliberately absent from headless test blocks.

const RigScript := preload("res://art/dragon_bone_rig.gd")
const RoostScript := preload("res://ui/dragon_roost.gd")
const MapScript := preload("res://battle/map_view.gd")
const ActorScript := preload("res://battle/unit_view.gd")
const BondFixture := preload("res://tests/test_dragon_bond_v021.gd")

const VIEW_W := 1800
const VIEW_H := 900
const TILE := 40.0
const STRIKE_PROGRESS := 0.53
# v0.106: review PNG stage (renders/), one bone-rig subject per image.
const REVIEW_W := 1200
const REVIEW_H := 800
const REVIEW_BG := Color(0.07, 0.06, 0.09)
# Authored rig extent the prototype roost already fits to (280x200 units).
const RIG_FIT_BOX := Vector2(280.0, 200.0)
# Fixed deterministic pose samples (autoplay off; see pose_at call sites).
const STANDING_T := 0.6  # same sample as the prototype roost yard
const FLYING_T := 0.25 / 1.1  # quarter cycle of the rig's 1.1 Hz flap: wings up
const WING_SCAN_STEPS := 120  # over animation_length("wing_beat") = 2.0 s
const RIDER_ZOOM := 3.2
const RIDER_POSE_PROGRESS := 0.3  # DragonView "idle" -> rig standing at 0.6 s
# v0.106: authored fixture appearance, applied to a registered native row.
const OLD_ROW := {"stage": "adult", "alive": true, "gem_id": "sapphire",
	"morph_id": "spirewing", "size_class": "medium", "appearance_seed": 27,
	"sprite_id": "sapphire_spirewing"}


class PrototypeRoost extends DragonRoost:
	var rig: RigScript

	func _paint(canvas: Control) -> void:
		# v0.106: the real yard/inspector/attendants, replacing only dragon ink.
		canvas.draw_style_box(UiTheme.sb(UiTheme.WOOD_3, UiTheme.PURPLE, 1),
			Rect2(Vector2.ZERO, canvas.size))
		if _entries.is_empty():
			return
		canvas.draw_line(Vector2(12, _origin.y),
			Vector2(canvas.size.x - 12, _origin.y), UiTheme.PURPLE)

	func install_prototype() -> bool:
		if _entries.size() != 1:
			return false
		var area: Rect2 = _entries[0]["dragon_rect"]
		if area.size.x <= 0.0 or area.size.y <= 0.0:
			return false
		rig = RigScript.new()
		rig.name = "NewBoneRigDragon"
		rig.autoplay = false
		# v0.106: fit prototype to this real yard's dragon slot; disclosed on PNG.
		var fit_scale: float = minf(area.size.x / 280.0, area.size.y / 200.0)
		rig.position = Vector2(area.get_center().x, area.end.y)
		rig.scale = Vector2.ONE * fit_scale
		_yard.add_child(rig)
		rig.pose_at("standing", 0.6)
		return rig.get_seat_point() != null


func _out_dir(subdir: String = "") -> String:
	var dir: String = ProjectSettings.globalize_path("res://").path_join("..")
	dir = dir.path_join("test-results").path_join("v0.106")
	if subdir != "":
		dir = dir.path_join(subdir)
	dir = dir.simplify_path()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		printerr("v0.106: cannot create capture output directory: ", dir)
		return ""
	return dir


func _label(text: String, pos: Vector2) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	return label


func _native_model_present(row: Dictionary, pose: String, t: float) -> bool:
	# v0.106: check EACH requested old pose; no fallback image or silent skip.
	var model: Dictionary = DragonArt.model(row, pose, t)
	if not bool(model.get("valid", false)):
		return false
	var image: Image = model.get("whole_image", null)
	return image != null and not image.is_empty()


func _native_view_present(view: DragonView) -> bool:
	if view == null or not bool(view._current.get("valid", false)):
		return false
	var body: DragonView.SourceLayer = view._part_nodes.get("body", null)
	return body != null and body.visible and body.texture != null and body.draw_base


func _old_context_present(stage: Control, roost: bool) -> bool:
	if roost:
		var old: DragonRoost = stage.get_node_or_null("OldRoost") as DragonRoost
		if old == null or old._entries.size() != 1:
			return false
		var model: Dictionary = old._entries[0]["model"]
		var image: Image = model.get("whole_image", null)
		return bool(model.get("valid", false)) and image != null and not image.is_empty()
	var actor: ActorScript = stage.get_node_or_null("OldActor") as ActorScript
	return actor != null and _native_view_present(actor.doll as DragonView)


func _stage(viewport: SubViewport, roost: bool, holder: Unit,
		row: Dictionary) -> Control:
	var old_pose: String = "rest" if roost else "strike"
	var old_t: float = 0.0 if roost else STRIKE_PROGRESS
	if holder == null or not _native_model_present(row, old_pose, old_t):
		printerr("v0.106: old side missing in requested ", old_pose, " context")
		return null
	var stage: Control = Control.new()
	stage.name = "ComparisonStage"
	stage.size = Vector2(VIEW_W, VIEW_H)
	stage.theme = UiTheme.get_theme()
	viewport.add_child(stage)
	if roost:
		var old: RoostScript = RoostScript.new()
		old.name = "OldRoost"
		old.position = Vector2(8, 48)
		old.size = Vector2(VIEW_W * 0.5 - 16, VIEW_H - 120)
		stage.add_child(old)
		old.set_records([row], String(row["id"]))
		var prototype: PrototypeRoost = PrototypeRoost.new()
		prototype.name = "PrototypeRoost"
		prototype.position = Vector2(VIEW_W * 0.5 + 8, 48)
		prototype.size = old.size
		stage.add_child(prototype)
		prototype.set_records([row], String(row["id"]))
		if not prototype.install_prototype():
			printerr("v0.106: prototype missing in real roost yard")
			stage.queue_free()
			return null
	else:
		# v0.106: real terrain adapter, bounded empty sim only to supply tiles.
		var sim: BattleSim = BattleSim.new()
		sim.setup([], [], 106, {"w": 45, "h": 20, "terrain": "plains", "verbose": false})
		var map: MapScript = MapScript.new()
		map.position.y = 48
		stage.add_child(map)
		map.configure(sim, TILE, "plains", 106)
		for side: int in 2:
			var fighter: Fighter = Fighter.new()
			fighter.unit = holder
			fighter.facing = 1
			fighter.cell = Vector2i(11 if side == 0 else 33, 16)
			fighter.prev_cell = fighter.cell
			var actor: ActorScript = ActorScript.new()
			actor.name = "OldActor" if side == 0 else "PrototypeActor"
			stage.add_child(actor)
			actor.setup(fighter, TILE)
			var view: DragonView = actor.doll as DragonView
			if view == null:
				printerr("v0.106: real battle adapter did not create DragonView")
				stage.queue_free()
				return null
			view.use_bone_rig_v106 = side == 1
			# Real flash/interpolation/culling presentation, without a sim tick.
			actor.flash("strike")
			if not actor.update_visual(0.0, ActorScript.FLASH_TIME * STRIKE_PROGRESS,
					Rect2(0, 0, VIEW_W, VIEW_H)):
				printerr("v0.106: battle comparison actor was culled")
				stage.queue_free()
				return null
			actor.position.y += 48
			if side == 1 and view.get_bone_rig_seat_point_v106() == null:
				printerr("v0.106: prototype seat missing in battle adapter")
				stage.queue_free()
				return null
	stage.add_child(_label("TODAY | shipped renderer", Vector2(24, 12)))
	stage.add_child(_label("v0.106 | bone-rig prototype", Vector2(VIEW_W * 0.5 + 24, 12)))
	stage.add_child(_label(
		"ROOST UI | prototype fitted independently to yard | rider UNBOUND" if roost else
		"BATTLE MAP + ACTOR ADAPTERS | frozen strike | provisional rig size | actual rider on NeckBase seat",
		Vector2(24, VIEW_H - 60)))
	stage.add_child(_label("Fixture presentation only | live battle, rendered draw order and recording remain delivery gates",
		Vector2(24, VIEW_H - 32)))
	if not _old_context_present(stage, roost):
		printerr("v0.106: old side missing after constructing ", old_pose, " context")
		stage.queue_free()
		return null
	return stage


func _shoot(tree: SceneTree, viewport: SubViewport, roost: bool, holder: Unit,
		row: Dictionary, file_name: String, capture_pixels: bool) -> int:
	var stage: Control = _stage(viewport, roost, holder, row)
	if stage == null:
		await tree.process_frame
		return 3
	for _i: int in 5:
		await tree.process_frame
	# v0.106: validate the actual old side again after READY/layout settles.
	if not _old_context_present(stage, roost):
		printerr("v0.106: old side disappeared before capture: ", file_name)
		stage.queue_free()
		await tree.process_frame
		return 3
	if not capture_pixels:
		print("v0.106: context checked only (no PNG): ", file_name)
		stage.queue_free()
		await tree.process_frame
		return 0
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("v0.106: no viewport image for ", file_name)
		stage.queue_free()
		await tree.process_frame
		return 4
	var dir: String = _out_dir()
	var rc: int = 0
	if dir == "" or image.save_png(dir.path_join(file_name)) != OK:
		printerr("v0.106: save_png failed for ", file_name)
		rc = 5
	else:
		print("v0.106: wrote ", dir.path_join(file_name))
	stage.queue_free()
	await tree.process_frame
	return rc


# ---------------------------------------------------------- review PNGs ---

func _review_stage(viewport: SubViewport, stage_name: String) -> Control:
	var stage: Control = Control.new()
	stage.name = stage_name
	stage.size = Vector2(REVIEW_W, REVIEW_H)
	stage.theme = UiTheme.get_theme()
	viewport.add_child(stage)
	var bg: ColorRect = ColorRect.new()
	bg.name = "PlainDarkBackground"
	bg.color = REVIEW_BG
	bg.size = stage.size
	stage.add_child(bg)
	return stage


func _wing_span(rig: RigScript) -> float:
	# Bone global transforms are synchronous after pose_at (rig guard test).
	var near_root: Bone2D = rig.get_bone("WingNearRoot")
	var near_tip: Bone2D = rig.get_bone("WingNearTip")
	var far_root: Bone2D = rig.get_bone("WingFarRoot")
	var far_tip: Bone2D = rig.get_bone("WingFarTip")
	if near_root == null or near_tip == null or far_root == null or far_tip == null:
		return -1.0
	return near_tip.global_position.distance_to(near_root.global_position) \
		+ far_tip.global_position.distance_to(far_root.global_position)


func _wing_open_time(rig: RigScript) -> float:
	# Most open = wing joints most extended (largest root-to-tip reach, both
	# wings). Scan one preview window, which spans several 1.8 Hz beats, and
	# leave the rig posed at the winning sample.
	var window: float = rig.animation_length("wing_beat")
	var best_t: float = 0.0
	var best_span: float = -1.0
	for i: int in WING_SCAN_STEPS + 1:
		var t: float = window * float(i) / float(WING_SCAN_STEPS)
		rig.pose_at("wing_beat", t)
		var span: float = _wing_span(rig)
		if span > best_span:
			best_span = span
			best_t = t
	rig.pose_at("wing_beat", best_t)
	print("v0.106: wing_beat most-open sample t=%.3f s (reach %.1f)" % [best_t, best_span])
	return best_t


func _rig_review_stage(viewport: SubViewport, anim: String, t: float,
		caption: String, ground: Vector2, rig_scale: float) -> Control:
	var stage: Control = _review_stage(viewport, "RigReviewStage")
	var ground_line: ColorRect = ColorRect.new()
	ground_line.color = REVIEW_BG.lightened(0.25)
	ground_line.position = Vector2(0, ground.y)
	ground_line.size = Vector2(REVIEW_W, 2)
	stage.add_child(ground_line)
	var rig: RigScript = RigScript.new()
	rig.name = "ReviewRig"
	rig.autoplay = false
	rig.position = ground
	rig.scale = Vector2.ONE * rig_scale
	stage.add_child(rig)
	var sampled_t: float = t
	if anim == "wing_beat":
		sampled_t = _wing_open_time(rig)
	else:
		rig.pose_at(anim, t)
	if rig.get_seat_point() == null:
		printerr("v0.106: review rig seat missing for ", anim)
		stage.queue_free()
		return null
	stage.add_child(_label(caption, Vector2(24, 14)))
	stage.add_child(_label(
		"bone-rig prototype | %s @ t=%.3f s | fixed sample, autoplay off" % [anim, sampled_t],
		Vector2(24, REVIEW_H - 40)))
	return stage


func _rider_review_stage(viewport: SubViewport, holder: Unit) -> Control:
	# Rig side of the battle comparison only, zoomed on the neck-base seat:
	# the real DragonView adapter, its bound rider and the rig's saddle.
	var stage: Control = _review_stage(viewport, "RiderReviewStage")
	var view: DragonView = DragonView.new()
	view.name = "RiderReviewView"
	stage.add_child(view)
	view.set_unit(holder)
	view.use_bone_rig_v106 = true
	view.set_pose("idle", RIDER_POSE_PROGRESS)
	var seat: Marker2D = view.get_bone_rig_seat_point_v106()
	if seat == null or not view.has_rider() or view._rider_far == null \
			or view._rider_front == null or view._rider_near == null \
			or view._rider_saddle == null or not view._rider_far.visible \
			or not view._rider_front.visible or view._rider_near.texture == null:
		printerr("v0.106: bound rider or neck-base seat missing in rider review")
		stage.queue_free()
		return null
	var seat_local: Vector2 = view.to_local(seat.global_position)
	view.scale = Vector2.ONE * RIDER_ZOOM
	view.position = Vector2(REVIEW_W * 0.5, REVIEW_H * 0.55) - seat_local * RIDER_ZOOM
	var seat_screen: Vector2 = view.position + seat_local * RIDER_ZOOM
	stage.add_child(_label("rig + bound rider | neck-base saddle", Vector2(24, 14)))
	stage.add_child(_label("SeatPoint on NeckBase bone | actual bonded rider, zoom x%.1f" % RIDER_ZOOM,
		Vector2(24, REVIEW_H - 40)))
	stage.add_child(_label("saddle / rider seat ->", seat_screen + Vector2(-300, -64)))
	return stage


func _old_vs_rig_stage(viewport: SubViewport, row: Dictionary) -> Control:
	# Both dragons fitted to the SAME display box and ground line, so the
	# look (not the provisional in-game size) is what differs.
	var stage: Control = _review_stage(viewport, "OldVsRigStage")
	var box: Vector2 = Vector2(560.0, 420.0)
	var ground_y: float = 640.0
	var ground_line: ColorRect = ColorRect.new()
	ground_line.color = REVIEW_BG.lightened(0.25)
	ground_line.position = Vector2(0, ground_y)
	ground_line.size = Vector2(REVIEW_W, 2)
	stage.add_child(ground_line)
	var divider: ColorRect = ColorRect.new()
	divider.color = REVIEW_BG.lightened(0.25)
	divider.position = Vector2(REVIEW_W * 0.5 - 1.0, 0)
	divider.size = Vector2(2, REVIEW_H)
	stage.add_child(divider)
	var model: Dictionary = DragonArt.model(row, "rest", 0.0)
	var image: Image = model.get("whole_image", null)
	if not bool(model.get("valid", false)) or image == null or image.is_empty():
		printerr("v0.106: old sprite missing in old_vs_rig review")
		stage.queue_free()
		return null
	var image_size: Vector2 = Vector2(image.get_size())
	var old_fit: float = minf(box.x / image_size.x, box.y / image_size.y)
	var old_size: Vector2 = image_size * old_fit
	var old_rect: TextureRect = TextureRect.new()
	old_rect.name = "CurrentSpriteDragon"
	old_rect.texture = ImageTexture.create_from_image(image)
	old_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	old_rect.stretch_mode = TextureRect.STRETCH_SCALE
	old_rect.size = old_size
	old_rect.position = Vector2(REVIEW_W * 0.25 - old_size.x * 0.5, ground_y - old_size.y)
	stage.add_child(old_rect)
	var rig: RigScript = RigScript.new()
	rig.name = "PrototypeRigDragon"
	rig.autoplay = false
	var rig_fit: float = minf(box.x / RIG_FIT_BOX.x, box.y / RIG_FIT_BOX.y)
	rig.position = Vector2(REVIEW_W * 0.75, ground_y)
	rig.scale = Vector2.ONE * rig_fit
	stage.add_child(rig)
	rig.pose_at("standing", STANDING_T)
	if rig.get_seat_point() == null:
		printerr("v0.106: prototype seat missing in old_vs_rig review")
		stage.queue_free()
		return null
	stage.add_child(_label("current", Vector2(24, 14)))
	stage.add_child(_label("prototype", Vector2(REVIEW_W * 0.5 + 24, 14)))
	stage.add_child(_label("current shipped sprite dragon | prototype bone-rig dragon",
		Vector2(24, REVIEW_H - 68)))
	stage.add_child(_label("same display box (560x420) and ground line | rest / standing poses",
		Vector2(24, REVIEW_H - 40)))
	return stage


func _shoot_review(tree: SceneTree, viewport: SubViewport, stage: Control,
		file_name: String, capture_pixels: bool) -> int:
	if stage == null:
		await tree.process_frame
		return 3
	for _i: int in 5:
		await tree.process_frame
	if not capture_pixels:
		print("v0.106: review context checked only (no PNG): ", file_name)
		stage.queue_free()
		await tree.process_frame
		return 0
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("v0.106: no viewport image for ", file_name)
		stage.queue_free()
		await tree.process_frame
		return 4
	var dir: String = _out_dir("renders")
	var rc: int = 0
	if dir == "" or image.save_png(dir.path_join(file_name)) != OK:
		printerr("v0.106: save_png failed for ", file_name)
		rc = 5
	else:
		print("v0.106: wrote ", dir.path_join(file_name))
	stage.queue_free()
	await tree.process_frame
	return rc


func _review_shots(tree: SceneTree, holder: Unit, row: Dictionary,
		capture_pixels: bool) -> int:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(REVIEW_W, REVIEW_H)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if capture_pixels else SubViewport.UPDATE_DISABLED
	tree.root.add_child.call_deferred(viewport) # runner may still be setting up root children
	await tree.process_frame
	var rc: int = await _shoot_review(tree, viewport,
		_rig_review_stage(viewport, "standing", STANDING_T, "rig | side rest",
			Vector2(REVIEW_W * 0.5, 640), 3.0),
		"rig_side_rest.png", capture_pixels)
	if rc == 0:
		rc = await _shoot_review(tree, viewport,
			_rig_review_stage(viewport, "wing_beat", 0.0, "rig | wings spread (most open)",
				Vector2(REVIEW_W * 0.5, 660), 2.7),
			"rig_wings_spread.png", capture_pixels)
	if rc == 0:
		rc = await _shoot_review(tree, viewport,
			_rig_review_stage(viewport, "flying", FLYING_T, "rig | flying",
				Vector2(REVIEW_W * 0.5, 640), 2.6),
			"rig_flying.png", capture_pixels)
	if rc == 0:
		rc = await _shoot_review(tree, viewport,
			_rider_review_stage(viewport, holder),
			"rig_rider_neck_saddle.png", capture_pixels)
	if rc == 0:
		rc = await _shoot_review(tree, viewport,
			_old_vs_rig_stage(viewport, row),
			"old_vs_rig.png", capture_pixels)
	viewport.queue_free()
	await tree.process_frame
	return rc


func run(tree: SceneTree) -> int:
	var old: Dictionary = {"world": Game.world, "company": Game.company,
		"squads": Game.squads, "day": Game.day, "gold": Game.gold,
		"location": Game.location, "rng": Game.rng.state,
		"unit": Unit._next_uid, "item": Item._next_uid}
	var fixture: BondFixture = BondFixture.new()
	fixture.fixture()
	var rc: int = 3
	var capture_pixels: bool = DisplayServer.get_name() != "headless"
	if fixture.fails == 0:
		var row: Dictionary = fixture.row()
		row.merge(OLD_ROW, true)
		row["growth_points"] = 2.0
		var bond: Dictionary = fixture.bind_current(fixture.dragon_uid, fixture.adult_uid)
		if bool(bond.get("ok", false)):
			DragonCombat.prepare_world(Game)
			var holder: Unit = Game.world["dragons"]["combat_units"].get(fixture.dragon_uid)
			if holder != null:
				var viewport: SubViewport = SubViewport.new()
				viewport.size = Vector2i(VIEW_W, VIEW_H)
				viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if capture_pixels else SubViewport.UPDATE_DISABLED
				tree.root.add_child.call_deferred(viewport) # runner may still be setting up root children
				await tree.process_frame
				rc = await _shoot(tree, viewport, true, holder, row,
					"capture_roost_old_vs_bone_rig.png", capture_pixels)
				if rc == 0:
					rc = await _shoot(tree, viewport, false, holder, row,
						"capture_battle_old_vs_bone_rig.png", capture_pixels)
				viewport.queue_free()
				await tree.process_frame
				if rc == 0:
					rc = await _review_shots(tree, holder, row, capture_pixels)
			else:
				printerr("v0.106: registered old dragon holder missing")
		else:
			printerr("v0.106: actual rider fixture bind failed: ", bond.get("reason", "unknown"))
	else:
		printerr("v0.106: native fixture onboarding failed")
	Game.world = old["world"]
	Game.company = old["company"]
	Game.squads = old["squads"]
	Game.day = old["day"]
	Game.gold = old["gold"]
	Game.location = old["location"]
	Game.rng.state = old["rng"]
	Unit._next_uid = old["unit"]
	Item._next_uid = old["item"]
	if rc == 0 and not capture_pixels:
		printerr("v0.106: all contexts checked headless; PNGs require an authorized rendered run")
		return 2
	if rc == 0:
		print("v0.106: two fixture comparisons + five review PNGs saved; recording and user OK still required")
	return rc
