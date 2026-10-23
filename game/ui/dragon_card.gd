class_name DragonCard
extends Control
## Source-matched body/head/jaw, bloody injuries, actual-unit saddle fit and portraits.
## Preview state is a copied value; no bond, wound, Unit or Item is created.
const IMAGE_SIZE := Vector2i(360, 230)
var record: Dictionary = {}
var mode: String = "model"
var pose: String = "idle"
var progress: float = 0.0
var playing: bool = false
var injury: Dictionary = {}
var rider_spec: Dictionary = {}
var closeup: bool = false
var _texture: Texture2D
var _rider: Dictionary = {}
var _rider_textures: Dictionary = {}
var _bounds: Rect2 = Rect2()
var _model_cache: Dictionary = {}
## Rigs shared by every card: reopening the dragons screen reuses them instead of rebuilding 27 rigs.
static var _shared: Dictionary = {}

func _model(p: String, t: float, inj: Dictionary) -> Dictionary:
	return cached_model(record, p, t, inj)

static func cached_model(row: Dictionary, p: String = "rest", t: float = 0.0, inj: Dictionary = {}) -> Dictionary:
	# Care, bonds, identity and fractional growth do not change the source rig.
	# Physical growth is applied by DragonView.physical_ppu at the drawing boundary.
	var look := [row.get("gem_id", ""), row.get("morph_id", ""), row.get("size_class", ""), row.get("appearance_seed", 0)]
	var key := "model:%d:%s:%.3f:%d" % [hash(look), p, t, inj.hash()]
	if not _shared.has(key):
		if _shared.size() > 96: _shared.clear()
		_shared[key] = DragonArt.model(row, p, t, inj)
	return _shared[key]

static func egg_visual(row: Dictionary) -> Dictionary:
	var key := "egg:%s:%d" % [str(row.get("gem_id", "ruby")), int(row.get("appearance_seed", 0))]
	if not _shared.has(key):
		if _shared.size() > 96: _shared.clear()
		var image := image_for(row)
		_shared[key] = {"texture": ImageTexture.create_from_image(image), "source": Rect2(image.get_used_rect())}
	return _shared[key]

func _init() -> void:
	custom_minimum_size = Vector2(220, 150)
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(false)

func set_record(value: Dictionary) -> void:
	record = value.duplicate(true)
	pose = "idle" if bool(record.get("alive", true)) else "dead"
	_prepare()

func set_mode(value: String) -> void:
	mode = value if value in ["model", "portrait", "concept"] else "model"
	_prepare()

func set_preview(value: String, state: Dictionary = {}, spec: Dictionary = {}, zoom: bool = false, animate: bool = false) -> void:
	pose = value if value in DragonArt.SUPPORTED_POSES else "idle"
	progress = 0.0; injury = state.duplicate(true); rider_spec = spec.duplicate(true)
	closeup = zoom; playing = animate
	_prepare()

func _prepare() -> void:
	_texture = null; _rider.clear(); _rider_textures.clear(); _model_cache.clear()
	if record.is_empty(): set_process(false); queue_redraw(); return
	if String(record.get("stage", "egg")) == "egg":
		_texture = egg_visual(record)["texture"]
	elif mode == "concept":
		_texture = DragonConcepts.texture_for_record(record)
	elif mode == "portrait":
		_texture = ImageTexture.create_from_image(DragonArt.portrait_for(record, pose, progress, injury))
	else:
		if not rider_spec.is_empty():
			_rider = MountedRiderArt.render_layers(rider_spec)
			if bool(_rider.get("ok", false)):
				for layer: String in ["far", "saddle", "near"]:
					_rider_textures[layer] = ImageTexture.create_from_image(_rider[layer])
		_prepare_frame()
	set_process(playing and mode == "model" and String(record.get("stage", "egg")) != "egg" and not pose in ["dead", "prone"])
	queue_redraw()

func _prepare_frame() -> void:
	var ready: bool = false
	var frames: int = int(FigurePainter.FRAMES.get("idle" if pose == "ground" else pose, 4))
	# Bounds from the first and middle frames (the animation sways a little; a margin covers the rest).
	for i: int in ([0, frames / 2] if frames > 1 else [0]):
		var model: Dictionary = _model(pose, float(i) / maxf(1, frames), injury)
		if not bool(model.get("valid", false)): continue
		# Injury previews keep the intact frame so removing a head cannot enlarge
		# or recenter the surviving source body between the comparison images.
		var intact: Dictionary = model if injury.is_empty() else _model(pose, float(i) / maxf(1, frames), {})
		var bounds: Rect2 = intact["bounds"] if bool(intact.get("valid", false)) else model["bounds"]
		if bool(_rider.get("ok", false)) and bool(model.get("mountable", false)):
			var seat: Vector2 = model["seat"]
			var placement: Transform2D = Transform2D(float(model["seat_angle"]), Vector2.ONE, 0, seat)
			var human: Rect2 = DragonMountPreviewArt._transformed_bounds(_rider["bounds"], placement)
			if closeup: bounds = Rect2(seat + Vector2(-20, -12), Vector2(52, 36)).merge(human.grow(4))
			else: bounds = bounds.merge(human)
		_bounds = _bounds.merge(bounds) if ready else bounds
		ready = true
	if not ready: _bounds = Rect2(-1, -1, 2, 2)
	else: _bounds = _bounds.grow(_bounds.size.length() * 0.03)

func _process(delta: float) -> void:
	progress = fmod(progress + delta / 1.4, 1.0)
	queue_redraw()

func _draw() -> void:
	draw_style_box(UiTheme.sb(UiTheme.WOOD_3, UiTheme.PURPLE, 1), Rect2(Vector2.ZERO, size))
	if _texture != null:
		var dimensions: Vector2 = Vector2(_texture.get_size())
		var scale_by: float = minf((size.x - 12) / dimensions.x, (size.y - 12) / dimensions.y)
		var fitted: Vector2 = dimensions * scale_by
		draw_texture_rect(_texture, Rect2((size - fitted) * 0.5, fitted), false)
		return
	if record.is_empty() or mode != "model" or String(record.get("stage", "egg")) == "egg": return
	# One model per pose frame, cached: a still card never rebuilds its rig on a redraw (scroll, resize).
	var frames_n: int = maxi(1, int(FigurePainter.FRAMES.get("idle" if pose == "ground" else pose, 4)))
	var model_key := "%s:%d" % [pose, floori(progress * frames_n)]
	if not _model_cache.has(model_key):
		if _model_cache.size() > 16: _model_cache.clear()
		_model_cache[model_key] = _model(pose, float(floori(progress * frames_n)) / frames_n, injury)
	var model: Dictionary = _model_cache[model_key]
	if not bool(model.get("valid", false)): return
	var ppu: float = minf((size.x - 30) / maxf(1, _bounds.size.x), (size.y - 26) / maxf(1, _bounds.size.y))
	var origin: Vector2 = size * 0.5 - _bounds.get_center() * ppu
	var mounted: bool = bool(_rider.get("ok", false)) and bool(model.get("mountable", false))
	var placement: Transform2D = Transform2D.IDENTITY
	if mounted:
		placement = MountedRiderArt.placement(_rider, origin + model["seat"] * ppu, ppu, float(model["seat_angle"]))
		draw_set_transform_matrix(placement)
		draw_texture(_rider_textures["far"], Vector2.ZERO)
		draw_set_transform_matrix(Transform2D.IDENTITY)
	DragonRigArt.draw_canvas_model(self, model, origin, ppu, int(record.get("appearance_seed", 0)))
	if mounted:
		draw_set_transform_matrix(placement)
		draw_texture(_rider_textures["saddle"], Vector2.ZERO)
		draw_texture(_rider_textures["near"], Vector2.ZERO)
		draw_set_transform_matrix(Transform2D.IDENTITY)

static func catalog_entry(group: String, id: String) -> Dictionary:
	for entry: Dictionary in Dragons.catalogs().get(group, []):
		if String(entry.get("id", "")) == id: return entry
	return {}

static func image_for(row: Dictionary) -> Image:
	if String(row.get("stage", "egg")) != "egg": return DragonArt.image_for(row)
	var cv: PixelCanvas = PixelCanvas.new(IMAGE_SIZE.x, IMAGE_SIZE.y)
	var gem: Dictionary = catalog_entry("gems", String(row.get("gem_id", "ruby")))
	var base: Color = Color(String(gem.get("base", "#8c2846")))
	var accent: Color = Color(String(gem.get("accent", "#f1b782")))
	var seed_value: int = int(row.get("appearance_seed", 0)) & 0x7fffffff
	_egg(cv, base, accent, String(gem.get("pattern", "veined")), seed_value)
	return cv.to_image()

static func _egg(cv: PixelCanvas, base: Color, accent: Color, pattern: String, seed_value: int) -> void:
	# Tapered upper shell, full lower shell; all marks stay inside owned shell pixels.
	var points := PackedVector2Array()
	for i in 65:
		var angle := TAU * float(i) / 64.0
		var taper := 0.84 + 0.16 * sin(angle)
		points.append(Vector2(180 + cos(angle) * 64 * taper, 123 + sin(angle) * 84))
	cv.begin(); cv.poly(points, base); cv.end(base.darkened(0.7), 0.18)
	var motif := posmod(hash(pattern), 5)
	for y in range(38, 210):
		for x in range(110, 249):
			if cv.get_px(x, y).a < 0.5: continue
			var shine := clampf(0.35 - float(x - 132) / 180.0 - absf(float(y - 87)) / 460.0, -0.2, 0.22)
			var color := base.lightened(shine) if shine >= 0 else base.darkened(-shine)
			var mark := false
			match motif:
				0: mark = posmod(x * 3 + y + seed_value, 31) < 3
				1: mark = posmod(y + int(5 * sin(float(x) / 13)), 27) < 4
				2: mark = posmod(x + seed_value, 24) < 3 and posmod(y, 22) < 8
				3: mark = posmod(x + y * 2 + seed_value, 37) < 2 or posmod(x * 2 - y, 53) < 2
				4: mark = posmod(int(x / 14) + int(y / 17) + seed_value, 3) == 0
			if mark: color = color.lerp(accent, 0.72)
			cv.set_px(x, y, color)
	cv.ellipse(Vector2(154, 83), 9, 23, Color(accent, 0.35))

static func silhouette(row: Dictionary) -> Dictionary:
	return DragonArt.model(row)
