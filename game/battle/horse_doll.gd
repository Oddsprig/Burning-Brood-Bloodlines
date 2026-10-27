class_name HorseDoll
extends Node2D
## Read-only rider/horse composite. Shared horse frames; native rider layers only
## rebuild on equipment/wound invalidation, never once per gait frame.
const HORSE_SCALE := 1.12
const RIDER_PPU := FigurePainter.PX
var unit: Unit
var facing := 1
var team_color := Color.WHITE
var bow_hand := false
var mounted := true
var gait_animation := "trot"
var _pose := "idle"
var _progress := 0.0
var _dirty := true
var _layers: Dictionary = {}
var _textures: Dictionary = {}
var _foot: Paperdoll
var _background := false

func set_unit(u: Unit) -> void:
	unit = u
	invalidate()

func set_background_rendering(on: bool) -> void:
	_background = on
	if _foot != null: _foot.set_background_rendering(on)

func invalidate() -> void:
	_dirty = true
	if _foot != null: _foot.invalidate()
	queue_redraw()

func visual_bounds() -> Rect2:
	return Rect2(-48, -82, 106, 88)

func body_center_offset() -> Vector2:
	return Vector2(0, -30)

func set_pose(pose: String, progress: float, render_frame: bool = true) -> void:
	_pose = pose
	_progress = progress
	var on_foot := unit.race != "horse" and (not mounted or pose in ["prone", "dead"])
	if on_foot and render_frame and _foot == null:
		_foot = Paperdoll.new()
		_foot.team_color = team_color
		add_child(_foot)
		_foot.set_background_rendering(_background)
		_foot.set_unit(unit)
	if _foot != null:
		_foot.visible = on_foot
		_foot.facing = facing
		_foot.bow_hand = bow_hand
		if on_foot: _foot.set_pose(pose, progress, render_frame)
	if render_frame: queue_redraw()

func _rider_layer(key: String, seat: Vector2, pitch: float = 0.0) -> void:
	var mirror := Transform2D(0, Vector2(float(facing), 1), 0, Vector2.ZERO)
	draw_set_transform_matrix(mirror * MountedRiderArt.placement(_layers, seat, RIDER_PPU, pitch))
	draw_texture(_textures[key], Vector2.ZERO)

func _draw() -> void:
	if unit == null: return
	var riding := unit.race != "horse"
	if riding and (not mounted or _pose in ["prone", "dead"]): return
	var horse: Unit = unit.horse if riding else unit
	if horse == null: return
	var animation := gait_animation if _pose == "walk" else "idle"
	if _pose in ["dead", "prone"]: animation = "fall"
	var index := mini(int(_progress * int(HorseArt.ANIMATIONS[animation])), int(HorseArt.ANIMATIONS[animation]) - 1)
	var at := HorseArt.seat(animation, index) * HORSE_SCALE
	var pitch := 0.0
	if animation == "gallop":
		pitch = [-0.05, -0.08, 0.035, -0.025][index % 4]
	elif animation in ["walk", "trot"]:
		pitch = [-0.025, -0.04, 0.02, -0.015][index % 4]
	if riding and _dirty:
		var spec := MountedRiderArt.spec_for_unit(unit)
		spec["team"] = team_color
		_layers = MountedRiderArt.render_layers(spec)
		_textures.clear()
		if bool(_layers.get("ok", false)):
			for key: String in ["far", "saddle", "near"]:
				_textures[key] = ImageTexture.create_from_image(_layers[key])
		_dirty = false
	if riding and not _textures.is_empty(): _rider_layer("far", at, pitch)
	draw_set_transform(Vector2.ZERO, 0, Vector2(float(facing) * HORSE_SCALE, HORSE_SCALE))
	draw_texture(HorseArt.frame(str(horse.look.get("coat", "bay")), animation, index), -HorseArt.ANCHOR)
	if riding and not _textures.is_empty():
		_rider_layer("saddle", at, pitch)
		_rider_layer("near", at, pitch)
	draw_set_transform(Vector2.ZERO)
