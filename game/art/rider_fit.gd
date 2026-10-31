class_name RiderFit
extends RefCounted
## Seated-composite fit. Dragon source pixels and the neck source-origin stay as
## authored. On-foot humanoid heights stay at the released v0.053 figures.
## Only the mounted drawing is scaled, and the hip sits on the back.

## Standing height divided by ground-to-saddle height.
const DRAGON_RATIO := 1.0
const DRAGON_RATIO_MIN := 0.90
const DRAGON_RATIO_MAX := 1.10
const HORSE_RATIO := 1.12
const HORSE_RATIO_MIN := 1.02
const HORSE_RATIO_MAX := 1.22
const ANCHOR_TOLERANCE := 1.25
## Far rider, mount, saddle, near rider. The saddle is under the rider.
const LAYER_ORDER := ["far", "mount", "saddle", "near"]
## Pixels tailward (x) and down (y) from the higher wing root, on a 128-wide canvas.
## Wider classic sources scale by image width / 128. Each breed has its own step.
const FORM_ANCHOR := {
	"spirewing": Vector2(6, 5),
	"broadmantle": Vector2(7, 6),
	"reedrunner": Vector2(8, 4),
	"ironcrest": Vector2(5, 5),
	"stormkeel": Vector2(6, 5),
	"duskfin": Vector2(6, 4),
}

static func ratio_target(kind: String) -> float:
	return HORSE_RATIO if kind == "horse" else DRAGON_RATIO

static func ratio_band(kind: String) -> Vector2:
	if kind == "horse":
		return Vector2(HORSE_RATIO_MIN, HORSE_RATIO_MAX)
	return Vector2(DRAGON_RATIO_MIN, DRAGON_RATIO_MAX)

static func height_ratio(withers: float, standing_height: float, logical_scale: float) -> float:
	return standing_height * logical_scale / maxf(withers, 0.001)

static func logical_scale(kind: String, withers: float, standing_height: float) -> float:
	return ratio_target(kind) * maxf(withers, 0.001) / maxf(standing_height, 0.001)

static func in_band(kind: String, withers: float, standing_height: float, logical_scale: float) -> bool:
	var ratio := height_ratio(withers, standing_height, logical_scale)
	var band := ratio_band(kind)
	return ratio >= band.x - 0.001 and ratio <= band.y + 0.001

static func _xy(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

## Source-pixel saddle point for one dragon form. Just tailward of the higher
## wing root, and a little below it, so the hip meets the back.
static func anchor_px(entry: Dictionary, morph_id: String = "") -> Vector2:
	if entry.is_empty():
		return Vector2.ZERO
	var morph := morph_id if morph_id != "" else str(entry.get("morph_id", ""))
	var shift: Vector2 = FORM_ANCHOR.get(morph, Vector2(6, 5))
	var wings: Dictionary = entry.get("wing_roots_px", {})
	if wings.is_empty():
		return _xy(entry.get("seat_px", [0, 0]))
	var left := _xy(wings.get("left", [0, 0]))
	var right := _xy(wings.get("right", [0, 0]))
	var neck := _xy(entry.get("neck_root_px", [0, 0]))
	var dorsal := left if left.y <= right.y else right
	var head := 1.0 if neck.x >= dorsal.x else -1.0
	var size: Variant = entry.get("image_size", [128, 96])
	var width := 128.0
	if size is Array and (size as Array).size() >= 1:
		width = float(size[0])
	elif size is Vector2i:
		width = float((size as Vector2i).x)
	var canvas := width / 128.0
	return Vector2(dorsal.x - head * shift.x * canvas, dorsal.y + shift.y * canvas)

static func dorsal_wing(entry: Dictionary) -> Vector2:
	var wings: Dictionary = entry.get("wing_roots_px", {})
	var left := _xy(wings.get("left", [0, 0]))
	var right := _xy(wings.get("right", [0, 0]))
	return left if left.y <= right.y else right

## Writes back_anchor and withers_height on a logical dragon model. Does not
## move seat, which remains the neck source-origin.
static func decorate(model: Dictionary, row: Dictionary) -> Dictionary:
	if not bool(model.get("valid", false)) or not model.has("whole_xf"):
		return model
	var pose := str(model.get("pose", "rest"))
	var progress := float(model.get("progress", 0.0))
	var entry := DragonSpriteCatalog.source_entry(row, pose, progress)
	var morph := str(row.get("morph_id", entry.get("morph_id", "")))
	var anchor: Vector2 = (model["whole_xf"] as Transform2D) * anchor_px(entry, morph)
	var withers := float(model.get("ground_y", anchor.y)) - anchor.y
	model["back_anchor"] = anchor
	model["withers_height"] = maxf(withers, 0.001)
	return model

static func dragon_contact(model: Dictionary) -> Vector2:
	if model.has("back_anchor"):
		return model["back_anchor"]
	return model.get("seat", Vector2.ZERO)

static func dragon_logical_scale(model: Dictionary, layers: Dictionary) -> float:
	return logical_scale("dragon", float(model.get("withers_height", 1.0)), float(layers.get("standing_height", 24.0)))

## scene_ppu is the mount's pixels per logical unit. The hip lands on the back anchor.
static func dragon_placement(model: Dictionary, layers: Dictionary, origin: Vector2, scene_ppu: float) -> Transform2D:
	var anchor := dragon_contact(model)
	var seat := origin + anchor * scene_ppu
	var fit := dragon_logical_scale(model, layers) * scene_ppu
	return MountedRiderArt.placement(layers, seat, fit, float(model.get("seat_angle", 0.0)))

static func horse_placement(layers: Dictionary, seat: Vector2, withers_px: float, facing: int, pitch: float) -> Transform2D:
	var fit := logical_scale("horse", withers_px, float(layers.get("standing_height", 24.0)))
	var mirror := Transform2D(0, Vector2(float(facing), 1), 0, Vector2.ZERO)
	return mirror * MountedRiderArt.placement(layers, seat, fit, pitch)
