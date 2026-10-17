class_name DragonMountPreviewArt
extends RefCounted
## Pure mounting-fit illustration. These previews do not assign an actual rider,
## create a bond/Unit/Item or change any dragon, person, inventory or campaign.
## Dragon model and native seated person share world units; camera zoom scales
## the complete scene equally. No enlarged person on a huge dragon is substituted.
const IMAGE_SIZE := Vector2i(720, 420)

static func _transformed_bounds(area: Rect2, transform: Transform2D) -> Rect2:
	var corners := [area.position, area.position + Vector2(area.size.x, 0), area.end, area.position + Vector2(0, area.size.y)]
	var low := Vector2(INF, INF); var high := Vector2(-INF, -INF)
	for corner: Vector2 in corners:
		var point := transform * corner
		low = low.min(point); high = high.max(point)
	return Rect2(low, high - low)

## Bounds come from the actual native seated raster, including carried equipment
## and missing limbs. Close-up uses a local back/neck patch at unchanged world
## scale, rather than shrinking the mount or enlarging the person independently.
static func framing(row: Dictionary, spec: Dictionary, pose: String = "ground", closeup: bool = false, progress: float = 0.0, state: Dictionary = {}) -> Dictionary:
	var model: Dictionary = DragonArt.model(row, pose, progress, state)
	if not bool(model.get("valid", false)):
		return {"valid": false, "reason": "The observed dragon sprite or requested pose is unavailable.",
			"model": model, "pose": pose, "closeup": closeup, "supported_poses": model.get("supported_poses", []).duplicate(),
			"rider_layers": {}, "mount_grips": [], "origin": Vector2.ZERO, "pixels_per_unit": 1.0, "bounds": Rect2(), "visual_preview_only": true}
	var mountable: bool = bool(model.get("mountable", true))
	var rider: Dictionary = MountedRiderArt.render_layers(spec.duplicate(true)) if mountable else {"ok": false, "reason": "No attached upright body mount is available."}
	var bounds: Rect2 = model["bounds"]
	var rider_bounds := Rect2()
	var seat: Vector2 = model["seat"]
	var seat_width := 0.0
	if bool(rider.get("ok", false)):
		var placement := Transform2D(float(model["seat_angle"]), Vector2.ONE, 0.0, seat)
		rider_bounds = _transformed_bounds(rider["bounds"], placement)
		seat_width = float(rider["seat_width"])
		if closeup:
			# Enough nearby host skin to show contact, without requiring the entire
			# colossal neck in this human-readable saddle inspection.
			var half_width := maxf(18.0, seat_width * 1.7)
			var patch := Rect2(seat + Vector2(-half_width, -12), Vector2(half_width * 2.0 + 12, 34))
			bounds = patch.merge(rider_bounds.grow(3.0))
		else: bounds = bounds.merge(rider_bounds)
	var pixels := minf((IMAGE_SIZE.x - 54.0) / maxf(1.0, bounds.size.x), (IMAGE_SIZE.y - 52.0) / maxf(1.0, bounds.size.y))
	var origin := Vector2(IMAGE_SIZE) * 0.5 - bounds.get_center() * pixels
	var mount_grips: Array = []
	if bool(rider.get("ok", false)):
		var local_to_world := Transform2D(float(model["seat_angle"]), Vector2.ONE, 0.0, seat)
		for key: String in rider["mount_grip_hands"]:
			if bool(rider["socket_presence"].get(key, false)): mount_grips.append({"hand": key, "hand_point": local_to_world * rider[key], "handle_point": local_to_world * rider["mount_handles"][key]})
	return {"valid": true, "supported_poses": model["supported_poses"].duplicate(), "origin": origin, "pixels_per_unit": pixels, "bounds": bounds, "model": model,
		"pose": str(model["pose"]), "progress": progress, "mountable": mountable, "closeup": closeup, "rider_layers": rider,
		"rider_bounds": rider_bounds, "seat_width": seat_width, "host_seat_width": float(model["seat_width"]),
		"seat": seat, "seat_angle": float(model["seat_angle"]), "mount_grips": mount_grips,
		"visual_preview_only": true, "layer_order": ["far_rider", "dragon", "saddle", "near_rider"]}

## Software raster composition, with inverse mapping from destination pixel
## centres. Native transparent pixels preserve the already-painted host layer.
static func _blend(cv: PixelCanvas, image: Image, image_to_canvas: Transform2D) -> void:
	var area := _transformed_bounds(Rect2(Vector2.ZERO, Vector2(image.get_size())), image_to_canvas)
	var low := Vector2i(floori(area.position.x), floori(area.position.y)).max(Vector2i.ZERO)
	var high := Vector2i(ceili(area.end.x), ceili(area.end.y)).min(Vector2i(cv.w, cv.h))
	var inverse := image_to_canvas.affine_inverse()
	for y in range(low.y, high.y):
		for x in range(low.x, high.x):
			var source := inverse * Vector2(x + 0.5, y + 0.5)
			var sx := floori(source.x); var sy := floori(source.y)
			if sx < 0 or sy < 0 or sx >= image.get_width() or sy >= image.get_height(): continue
			var color := image.get_pixel(sx, sy)
			if color.a > 0: cv.set_px(x, y, color)

static func image_for(row: Dictionary, spec: Dictionary, pose: String = "ground", closeup: bool = false, progress: float = 0.0, state: Dictionary = {}) -> Image:
	var frame: Dictionary = framing(row, spec, pose, closeup, progress, state)
	var cv := PixelCanvas.new(IMAGE_SIZE.x, IMAGE_SIZE.y)
	if not bool(frame.get("valid", false)): return cv.to_image()
	var rider: Dictionary = frame["rider_layers"]
	var seat: Vector2 = frame["origin"] + frame["seat"] * float(frame["pixels_per_unit"])
	var transform := Transform2D.IDENTITY
	if bool(rider.get("ok", false)):
		transform = MountedRiderArt.placement(rider, seat, float(frame["pixels_per_unit"]), float(frame["seat_angle"]))
		_blend(cv, rider["far"], transform)
	var drawn: Dictionary = DragonArt.draw(cv, row, str(frame["pose"]), frame["origin"], float(frame["pixels_per_unit"]), progress, state)
	if not bool(drawn.get("valid", false)): return PixelCanvas.new(IMAGE_SIZE.x, IMAGE_SIZE.y).to_image()
	if bool(rider.get("ok", false)):
		_blend(cv, rider["saddle"], transform)
		_blend(cv, rider["near"], transform)
	return cv.to_image()
