extends Node2D
## Static campaign-map layer, drawn once in code: terrain (GPU shader over a one-texel-per-cell
## index texture, domain-warped so cell edges become crisp organic coastlines and borders),
## territory borders, roads, terrain decorations (trees, peaks, hills, mesas), towns and labels.

const SHADE_PX := 2   # shading texture pixels per cell (relief, water depth; linear filtered)
const T_INDEX := {"g": 0, "f": 1, "h": 2, "m": 3, "w": 4, "b": 5, "s": 6}

const TERRAIN_COLORS := ["#7cc24a", "#3f8c3a", "#aea45c", "#8d8680", "#2a74c0", "#d48a4a", "#a2c8bc"]
## per region (WorldGen.REGIONS: middle, north, south, east, west, southeast (the dry steppe), holds (the dwarves))
const GRASS := ["#7cc84a", "#69ad62", "#b0bd4a", "#b9b456", "#76c886", "#c9bd6a", "#8fa860"]
const FOREST_FLOOR := ["#3f8c3a", "#2c6e4a", "#5f822e", "#4f7f30", "#4a9a6a", "#6a7a34", "#3f6a40"]
const WATER_DEEP := "#1b5fae"
const WATER_SHALLOW := "#4db0e2"

const SHADER := """
shader_type canvas_item;
uniform sampler2D shade_tex : filter_linear;
uniform sampler2D pal_tex : filter_nearest;
uniform sampler2D map_tex : filter_nearest;
uniform vec2 grid = vec2(100.0, 64.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.5 + vnoise(p * 2.03 + 5.1) * 0.3 + vnoise(p * 4.07 + 9.7) * 0.2; }
ivec2 cell_i(vec2 c) { return clamp(ivec2(floor(c)), ivec2(0), ivec2(grid) - 1); }
vec4 cell(vec2 c) { return texelFetch(map_tex, cell_i(c), 0); }
int idx(float v) { return int(v * 255.0 + 0.5); }
vec3 pal(int x, int y) { return texelFetch(pal_tex, ivec2(x, y), 0).rgb; }

void fragment() {
	vec2 c = UV * grid;
	vec2 warp = vec2(fbm(c * 0.9), fbm(c * 0.9 + 17.3)) - 0.5;
	vec2 wc = c + warp * 1.3;
	vec4 d = cell(wc);
	int t = idx(d.r); int r = idx(d.g);
	vec4 sh = texture(shade_tex, UV);
	vec3 col;
	if (t == 0) col = pal(r, 1);
	else if (t == 1) col = pal(r, 2);
	else if (t == 4) col = mix(pal(0, 4), pal(1, 4), sh.g);
	else col = pal(t, 0);
	if (t != 4) col *= 0.8 + sh.r * 0.4;
	col *= 0.93 + fbm(c * 3.1) * 0.14;
	float e = 0.16;
	if (t == 4) {
		// surf where water meets land
		bool coast = idx(cell(wc + vec2(e, 0.0)).r) != 4 || idx(cell(wc - vec2(e, 0.0)).r) != 4
			|| idx(cell(wc + vec2(0.0, e)).r) != 4 || idx(cell(wc - vec2(0.0, e)).r) != 4;
		if (coast) col = mix(col, vec3(0.92, 0.97, 1.0), 0.55);
	} else {
		// faction territory border
		bool border = idx(cell(wc + vec2(e, 0.0)).g) != r || idx(cell(wc - vec2(e, 0.0)).g) != r
			|| idx(cell(wc + vec2(0.0, e)).g) != r || idx(cell(wc - vec2(0.0, e)).g) != r;
		if (border) col = mix(col, pal(r, 3), 0.7);
		// sandy shore just inside the coast
		float e2 = 0.3;
		bool shore = idx(cell(wc + vec2(e2, 0.0)).r) == 4 || idx(cell(wc - vec2(e2, 0.0)).r) == 4
			|| idx(cell(wc + vec2(0.0, e2)).r) == 4 || idx(cell(wc - vec2(0.0, e2)).r) == 4;
		if (shore) col = mix(col, vec3(0.93, 0.85, 0.6), 0.6);
	}
	COLOR = vec4(col, 1.0);
}
"""

## World size: the decor (trees, peaks, hills...) is drawn by CHUNK x CHUNK cell children, each its own canvas item,
## so the renderer culls the chunks off screen (one item for the whole map drew every piece every frame), and the
## chunks hide when zoomed out past DECOR_MIN_ZOOM (the terrain shader still shows the land). The ground textures and
## the decor lists are built once per world and kept (static cache): coming back from a town does not rebuild them.
const CHUNK := 24   # cells a side
const DECOR_MIN_ZOOM := 0.28   # below this zoom the decor hides (the normal map's furthest zoom is 0.30: never there)

## v0.014 (Douglas: "long loading screen ... map screen to town screen"): the chunks are RenderingServer canvas items
## kept with the cache, drawn ONCE per world and re-parented under each new map screen. As nodes they were freed with
## the screen and every piece was redrawn in code on each return from a town (~220 ms on a Large map, more on a phone).
## The ground shader is kept too (compiled once).
static var _cache_key := ""
static var _cache := {}   # {idx_tex, shade_tex, pal_tex, chunks: {Vector2i: Array}, rids: [RID], shader}
## Diagnostic comparison switch. Both paths use the same generated decor and painter order.
## Included in the cache key so switching paths cannot reuse the previous retained commands.
static var decor_batch_enabled := true

var world: Dictionary
var ground: Sprite2D
var decor: Array = []   # [y, kind, pos, variant, scale] (the chunks hold it; kept empty)
var font: Font
var _decor_n := 0
var _decor_on := true

func setup(w: Dictionary) -> void:
	world = w
	font = ThemeDB.fallback_font
	var key := "%s|%d|%d|%d|batch:%d" % [str(w.get("seed", 0)), (w["terrain"] as String).hash(), WorldGen.W, (w["road"] as String).hash(), int(decor_batch_enabled)]
	if key != _cache_key:
		for r in _cache.get("rids", []):
			RenderingServer.free_rid(r)
		_cache_key = key
		_cache = {}
		_build_textures()
		_build_decor()
	_build_ground()
	_mount_chunks()
	queue_redraw()

## Decor pieces on the map (diagnostics).
func decor_count() -> int:
	return _decor_n

## Decor chunks (canvas items) on the map (diagnostics).
func chunk_count() -> int:
	return (_cache.get("rids", []) as Array).size()

## Counts of retained commands, not a claim about measured GPU draw calls.
## Packed payload counts exclude RenderingServer overhead and the unchanged terrain textures.
func decor_render_stats() -> Dictionary:
	var result: Dictionary = (_cache.get("decor_render_stats", {}) as Dictionary).duplicate()
	result["batched"] = decor_batch_enabled
	result["decor"] = _decor_n
	result["chunks"] = chunk_count()
	result["mounted"] = _mounted_on != 0
	var source_arrays: Dictionary = _cache.get("chunks", {})
	result["source_arrays"] = source_arrays.size()
	result["source_rows"] = _decor_n
	var texture_bytes: int = 0
	for key: String in ["idx_tex", "shade_tex", "pal_tex"]:
		var texture: Texture2D = _cache.get(key)
		if texture != null: texture_bytes += texture.get_width() * texture.get_height() * 4
	result["texture_rgba_estimate_bytes"] = texture_bytes
	return result

## The map screen calls this when the zoom changes: decor shows only from DECOR_MIN_ZOOM in.
func set_zoom(z: float) -> void:
	var on := z >= DECOR_MIN_ZOOM
	if on == _decor_on:
		return
	_decor_on = on
	for r in _cache.get("rids", []):
		RenderingServer.canvas_item_set_visible(r, on)

func _mount_chunks() -> void:
	var cks: Dictionary = _cache["chunks"]
	_decor_n = 0
	for k in cks:
		_decor_n += (cks[k] as Array).size()
	if not _cache.has("rids"):
		var keys := cks.keys()
		keys.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))   # top rows first: y order holds across chunks
		var rids := []
		var pen := RSPen.new()
		pen.batching = decor_batch_enabled
		for k in keys:
			pen.rid = RenderingServer.canvas_item_create()
			for d in cks[k]:
				_draw_decor_on(pen, d[1], d[2], d[3], d[4])
			pen.flush()
			rids.append(pen.rid)
		_cache["rids"] = rids
		_cache["decor_render_stats"] = pen.stats()
	var i := 0
	for r in _cache["rids"]:
		RenderingServer.canvas_item_set_parent(r, get_canvas_item())
		RenderingServer.canvas_item_set_draw_behind_parent(r, true)   # under the roads, towns and labels the parent draws
		RenderingServer.canvas_item_set_draw_index(r, 1 + i)   # over the ground sprite (index 0), top rows first
		RenderingServer.canvas_item_set_visible(r, _decor_on)
		i += 1
	_mounted_on = get_instance_id()

static var _mounted_on := 0   # the map layer the cached chunks hang under now

## Frees the cached chunk canvas items (Game calls it on quit).
static func free_cache() -> void:
	for r in _cache.get("rids", []):
		RenderingServer.free_rid(r)
	_cache = {}
	_cache_key = ""
	_mounted_on = 0

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _mounted_on == get_instance_id() and _cache.has("rids"):
		_mounted_on = 0
		for r in _cache["rids"]:
			RenderingServer.canvas_item_set_parent(r, RID())   # kept for the next map screen, drawn by nobody meanwhile

## Ordered triangles replace thousands of individual retained polygon commands.
## Circles, positive-width lines/polylines and rects follow RendererCanvasCull's native geometry.
## Translucent polylines keep their original triangle order; other translucent shapes and
## thin lines remain native barriers. No colour sorting, resampling or antialiasing change.
class RSPen:
	const MAX_BATCH_VERTICES := 8192
	const CIRCLE_SEGMENTS := 64
	static var _circle_directions := PackedVector2Array()
	static var _circle_indices := PackedInt32Array()
	var rid: RID
	var batching := true
	var _points := PackedVector2Array()
	var _colors := PackedColorArray()
	var _indices := PackedInt32Array()
	var _source_commands := 0
	var _submitted_commands := 0
	var _native_commands := 0
	var _triangle_batches := 0
	var _vertices := 0
	var _triangles := 0
	var _largest_batch_vertices := 0
	var _packed_bytes := 0
	var _batched_polylines := 0
	var _batched_rects := 0

	func stats() -> Dictionary:
		return {"source_commands": _source_commands, "submitted_commands": _submitted_commands,
			"native_commands": _native_commands, "triangle_batches": _triangle_batches,
			"vertices": _vertices, "triangles": _triangles,
			"largest_batch_vertices": _largest_batch_vertices, "packed_bytes": _packed_bytes,
			"batch_vertex_limit": MAX_BATCH_VERTICES, "batched_polylines": _batched_polylines,
			"batched_rects": _batched_rects}

	func flush() -> void:
		if _indices.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(rid, _indices, _points, _colors)
		_submitted_commands += 1
		_triangle_batches += 1
		_vertices += _points.size()
		_triangles += int(_indices.size() / 3)
		_largest_batch_vertices = maxi(_largest_batch_vertices, _points.size())
		_packed_bytes += _points.size() * 24 + _indices.size() * 4
		_points = PackedVector2Array()
		_colors = PackedColorArray()
		_indices = PackedInt32Array()

	func _native_barrier() -> void:
		flush()
		_submitted_commands += 1
		_native_commands += 1

	func _append(pts: PackedVector2Array, indices: PackedInt32Array, c: Color) -> void:
		if _points.size() + pts.size() > MAX_BATCH_VERTICES:
			flush()
		var offset: int = _points.size()
		_points.append_array(pts)
		var colors := PackedColorArray()
		colors.resize(pts.size())
		colors.fill(c)
		_colors.append_array(colors)
		for index in indices:
			_indices.append(offset + index)

	func draw_line(a: Vector2, b: Vector2, c: Color, w: float = -1.0) -> void:
		_source_commands += 1
		if not batching or w < 0.0 or c.a < 1.0:
			_native_barrier()
			RenderingServer.canvas_item_add_line(rid, a, b, c, w)
			return
		var side: Vector2 = (a - b).orthogonal().normalized() * w * 0.5
		_append(PackedVector2Array([a + side, a - side, b - side, b + side]),
			PackedInt32Array([0, 1, 2, 0, 2, 3]), c)

	func draw_circle(p: Vector2, r: float, c: Color) -> void:
		_source_commands += 1
		if not batching or c.a < 1.0:
			_native_barrier()
			RenderingServer.canvas_item_add_circle(rid, p, r, c)
			return
		if _circle_directions.is_empty():
			# The engine stores each angle as float32 before trigonometry. Vector2 packing
			# also retains the native float32 result before multiplying by the radius.
			var step: float = PackedFloat32Array([TAU / CIRCLE_SEGMENTS])[0]
			for i in CIRCLE_SEGMENTS + 1:
				var angle: float = PackedFloat32Array([i * step])[0]
				_circle_directions.append(Vector2(cos(angle), sin(angle)))
			for i in CIRCLE_SEGMENTS:
				_circle_indices.append(CIRCLE_SEGMENTS + 1)
				_circle_indices.append(i)
				_circle_indices.append(i + 1)
		var radius: float = PackedFloat32Array([r])[0]
		var pts := PackedVector2Array()
		for direction in _circle_directions:
			pts.append(direction * radius + p)
		pts.append(p)
		_append(pts, _circle_indices, c)

	func draw_colored_polygon(pts: PackedVector2Array, c: Color) -> void:
		_source_commands += 1
		if not batching or c.a < 1.0 or pts.size() > MAX_BATCH_VERTICES:
			_native_barrier()
			RenderingServer.canvas_item_add_polygon(rid, pts, PackedColorArray([c]))
			return
		# Identical triangulation entry point to canvas_item_add_polygon.
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(pts)
		if indices.is_empty():
			_native_barrier()
			RenderingServer.canvas_item_add_polygon(rid, pts, PackedColorArray([c]))
			return
		_append(pts, indices, c)

	func draw_polyline(pts: PackedVector2Array, c: Color, w: float = -1.0) -> void:
		_source_commands += 1
		if not batching or w < 0.0 or pts.size() < 2 or pts.size() * 2 > MAX_BATCH_VERTICES:
			_native_barrier()
			RenderingServer.canvas_item_add_polyline(rid, pts, PackedColorArray([c]), w)
			return
		var count: int = pts.size()
		var loop: bool = pts[0].is_equal_approx(pts[count - 1])
		var first_dir := Vector2.ZERO
		var last_dir := Vector2.ZERO
		for i in range(1, count):
			first_dir = (pts[i] - pts[i - 1]).normalized()
			if not first_dir.is_zero_approx():
				break
		for i in range(count - 1, 0, -1):
			last_dir = (pts[i] - pts[i - 1]).normalized()
			if not last_dir.is_zero_approx():
				break
		var strip := PackedVector2Array()
		var previous_dir := Vector2.ZERO
		var half_width: float = _float32(w) * 0.5
		for i in count:
			var first: bool = i == 0
			var last: bool = i == count - 1
			var direction: Vector2 = previous_dir if last else (pts[i + 1] - pts[i]).normalized()
			if direction.is_zero_approx():
				direction = previous_dir
			if first and loop:
				previous_dir = last_dir
			elif last and loop:
				previous_dir = first_dir
			var edge: Vector2
			if first and not loop:
				edge = first_dir.orthogonal()
			elif last and not loop:
				edge = last_dir.orthogonal()
			else:
				edge = _polyline_edge(direction, previous_dir)
			var offset: Vector2 = edge * half_width
			strip.append(pts[i] + offset)
			strip.append(pts[i] - offset)
			previous_dir = direction
		# Match the original triangle strip's alternating winding and primitive order,
		# including any degenerate/self-overlapping triangles of translucent waves.
		var indices := PackedInt32Array()
		for i in range(2, strip.size()):
			indices.append(i - 2 if i % 2 == 0 else i - 1)
			indices.append(i - 1 if i % 2 == 0 else i - 2)
			indices.append(i)
		_append(strip, indices, c)
		_batched_polylines += 1

	static func _float32(value: float) -> float:
		return PackedFloat32Array([value])[0]

	static func _polyline_edge(direction: Vector2, previous: Vector2) -> Vector2:
		var bisector: Vector2 = (previous * direction.length() - direction * previous.length()).normalized()
		var length: float = 1.0
		# RendererCanvasCull computes the angle/sine/reciprocal in float32.
		var angle: float = _float32(atan2(bisector.cross(previous), bisector.dot(previous)))
		var sine: float = _float32(sin(angle))
		if not is_zero_approx(sine) and not direction.is_equal_approx(previous):
			length = clampf(_float32(1.0 / sine), -3.0, 3.0)
		else:
			bisector = direction.orthogonal()
		if bisector.is_zero_approx():
			bisector = direction.orthogonal()
		return bisector * length

	func draw_rect(r: Rect2, c: Color) -> void:
		_source_commands += 1
		if not batching or r.size.x < 0.0 or r.size.y < 0.0 or c.a < 1.0:
			_native_barrier()
			RenderingServer.canvas_item_add_rect(rid, r, c)
			return
		_append(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0),
			r.end, r.position + Vector2(0, r.size.y)]), PackedInt32Array([0, 1, 2, 0, 2, 3]), c)
		_batched_rects += 1

func _region_char_to_name(ch: String) -> String:
	return WorldGen.REGIONS[int(ch)]

func _build_ground() -> void:
	var W := WorldGen.W; var H := WorldGen.H
	var mat := ShaderMaterial.new()
	if not _cache.has("shader"):
		var sh := Shader.new()
		sh.code = SHADER
		_cache["shader"] = sh
	mat.shader = _cache["shader"]
	mat.set_shader_parameter("shade_tex", _cache["shade_tex"])
	mat.set_shader_parameter("pal_tex", _cache["pal_tex"])
	mat.set_shader_parameter("grid", Vector2(W, H))
	ground = Sprite2D.new()
	ground.texture = _cache["idx_tex"]
	mat.set_shader_parameter("map_tex", ground.texture)
	ground.centered = false
	ground.scale = Vector2(WorldGen.CELL, WorldGen.CELL)
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground.material = mat
	ground.show_behind_parent = true
	add_child(ground)

## The ground's textures (cell index, relief and water depth, palette), once per world.
func _build_textures() -> void:
	var W := WorldGen.W; var H := WorldGen.H
	var terr: String = world["terrain"]
	var reg: String = world["region"]
	# one texel per cell: R = terrain index, G = region index
	var idx_img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var i := y * W + x
			idx_img.set_pixel(x, y, Color8(T_INDEX.get(terr[i], 0), int(reg[i]), 0, 255))
	# relief and water depth, two texels per cell
	var seed_v := int(world["seed"])
	var elev := WorldGen.noise(seed_v, 11, 0.05, 5)
	var sh_img := Image.create(W * SHADE_PX, H * SHADE_PX, false, Image.FORMAT_RGBA8)
	for py in H * SHADE_PX:
		for px in W * SHADE_PX:
			var fx := ((px + 0.5) / SHADE_PX - 0.5) / WorldGen.K   # in BASE cells, as WorldGen.gen_terrain samples
			var fy := ((py + 0.5) / SHADE_PX - 0.5) / WorldGen.K
			var e := elev.get_noise_2d(fx, fy)
			var e2 := elev.get_noise_2d(fx - 1.0, fy - 1.0)
			var shade := clampf(0.5 + (e - e2) * 3.0, 0.0, 1.0)
			var depth := clampf(((e + 1.0) * 0.5 - 0.1) / 0.18, 0.0, 1.0)
			sh_img.set_pixel(px, py, Color(shade, depth, 0.0, 1.0))
	# palette rows: 0 terrain, 1 grass per region, 2 forest floor per region, 3 region border, 4 water
	var pal := Image.create(8, 5, false, Image.FORMAT_RGBA8)
	for i in TERRAIN_COLORS.size():
		pal.set_pixel(i, 0, Color(TERRAIN_COLORS[i]))
	for i in mini(WorldGen.REGIONS.size(), 8):
		pal.set_pixel(i, 1, Color(GRASS[i]))
		pal.set_pixel(i, 2, Color(FOREST_FLOOR[i]))
		pal.set_pixel(i, 3, Color(DB.factions[WorldGen.region_faction(WorldGen.REGIONS[i])]["colors"]["primary"]).lightened(0.2))
	pal.set_pixel(0, 4, Color(WATER_DEEP))
	pal.set_pixel(1, 4, Color(WATER_SHALLOW))
	_cache["shade_tex"] = ImageTexture.create_from_image(sh_img)
	_cache["pal_tex"] = ImageTexture.create_from_image(pal)
	_cache["idx_tex"] = ImageTexture.create_from_image(idx_img)

## The decor pieces, once per world, sorted by map y and split into CHUNK-cell chunks.
func _build_decor() -> void:
	decor.clear()
	var W := WorldGen.W; var H := WorldGen.H
	var C := float(WorldGen.CELL)
	var terr: String = world["terrain"]
	var reg: String = world["region"]
	var road: String = world["road"]
	var rng := RandomNumberGenerator.new()
	var town_cells := {}
	for tid in world["towns"]:
		var tc := WorldGen.cell_of(world["towns"][tid]["pos"])
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				town_cells[tc + Vector2i(dx, dy)] = true
	for y in H:
		for x in W:
			var i := y * W + x
			var t := terr[i]
			if road[i] == "1" or town_cells.has(Vector2i(x, y)):
				continue
			rng.seed = int(world["seed"]) * 7919 + i
			var base := Vector2(x * C, y * C)
			var rname := _region_char_to_name(reg[i])
			match t:
				"f", "s":
					var kind := "silver" if t == "s" else ("pine" if rname == "north" else "tree")
					for k in rng.randi_range(2, 3):
						var p := base + Vector2(rng.randf_range(2, C - 2), rng.randf_range(4, C))
						decor.append([p.y, kind, p, rng.randi() % 3, rng.randf_range(0.85, 1.15)])
				"m":
					var p := base + Vector2(C * 0.5 + rng.randf_range(-3, 3), C * 0.9)
					decor.append([p.y, "peak", p, int(rname == "north" or rng.randf() < 0.5), rng.randf_range(1.0, 1.35)])
				"h":
					if rng.randf() < 0.75:
						var p := base + Vector2(rng.randf_range(4, C - 4), rng.randf_range(C * 0.5, C))
						decor.append([p.y, "hill", p, 0, rng.randf_range(0.8, 1.2)])
				"b":
					if rng.randf() < 0.45:
						var p := base + Vector2(rng.randf_range(4, C - 4), rng.randf_range(C * 0.5, C))
						decor.append([p.y, "mesa" if rng.randf() < 0.5 else "crack", p, 0, rng.randf_range(0.8, 1.2)])
				"g":
					if rng.randf() < 0.18:
						var p := base + Vector2(rng.randf_range(2, C - 2), rng.randf_range(2, C - 2))
						var flower := rname in ["middle", "west"] and rng.randf() < 0.3
						decor.append([p.y, "flower" if flower else "tuft", p, rng.randi() % 3, 1.0])
				"w":
					if rng.randf() < 0.08:
						var p := base + Vector2(rng.randf_range(4, C - 4), rng.randf_range(4, C - 4))
						decor.append([p.y, "wave", p, 0, 1.0])
	decor.sort_custom(func(a, b): return a[0] < b[0])
	var chunks := {}
	var span := C * CHUNK
	for d in decor:
		var k := Vector2i(int((d[2] as Vector2).x / span), int((d[2] as Vector2).y / span))
		if not chunks.has(k):
			chunks[k] = []
		(chunks[k] as Array).append(d)
	_cache["chunks"] = chunks
	decor = []

func _draw() -> void:
	for r in world.get("roads", []):
		var pts := PackedVector2Array(r["pts"])
		draw_polyline(pts, Color("#5a3d22"), 7.0, true)
		draw_polyline(pts, Color("#e2c486"), 4.0, true)
	for tid in world["towns"]:
		_draw_town(world["towns"][tid])
	for tid in world["towns"]:
		_draw_label(world["towns"][tid])

func _draw_decor_on(ci, kind: String, p: Vector2, v: int, s: float) -> void:
	match kind:
		"tree":
			var greens := [Color("#2e8a36"), Color("#3d9c3a"), Color("#2a7a3e")]
			var g: Color = greens[v]
			ci.draw_line(p, p + Vector2(0, -5) * s, Color("#5b3a1e"), 2.0)
			ci.draw_circle(p + Vector2(0, -9) * s, 6.0 * s, g.darkened(0.3))
			ci.draw_circle(p + Vector2(-1, -10) * s, 5.0 * s, g)
			ci.draw_circle(p + Vector2(-2.5, -12) * s, 2.2 * s, g.lightened(0.3))
		"pine":
			var g := Color("#1f6a3c") if v != 1 else Color("#24764a")
			ci.draw_line(p, p + Vector2(0, -3) * s, Color("#4a2e18"), 2.0)
			for k in 3:
				var y0 := -3.0 - k * 5.0
				var wdt := 7.0 - k * 1.8
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-wdt, y0) * s, p + Vector2(wdt, y0) * s, p + Vector2(0, y0 - 8) * s]), g)
				ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, y0) * s, p + Vector2(wdt, y0) * s, p + Vector2(0, y0 - 8) * s]), g.darkened(0.25))
		"silver":
			ci.draw_line(p, p + Vector2(0, -7) * s, Color("#e8eef8"), 2.0)
			ci.draw_circle(p + Vector2(0, -11) * s, 6.0 * s, Color("#7f97cf"))
			ci.draw_circle(p + Vector2(-1, -12) * s, 5.0 * s, Color("#bccdee"))
			ci.draw_circle(p + Vector2(-2.5, -14) * s, 1.8 * s, Color("#ffffff"))
		"peak":
			var h := 26.0 * s; var wdt := 17.0 * s
			var top := p + Vector2(0, -h)
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-wdt, 0), top, p + Vector2(wdt, 0)]), Color("#9a948e"))
			ci.draw_colored_polygon(PackedVector2Array([top, p + Vector2(wdt, 0), p + Vector2(2, 0)]), Color("#6e6964"))
			if v == 1:
				ci.draw_colored_polygon(PackedVector2Array([top, top + Vector2(-wdt * 0.38, h * 0.36), top + Vector2(0, h * 0.28),
					top + Vector2(wdt * 0.38, h * 0.36)]), Color("#f6f8fc"))
		"hill":
			var pts := PackedVector2Array()
			for k in 9:
				var a := PI + PI * k / 8.0
				pts.append(p + Vector2(cos(a) * 11.0, sin(a) * 7.0) * s)
			ci.draw_colored_polygon(pts, Color("#b8ae64"))
			ci.draw_polyline(pts, Color("#7d7440"), 1.5)
		"mesa":
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 0) * s, p + Vector2(-5, -7) * s, p + Vector2(5, -7) * s, p + Vector2(8, 0) * s]), Color("#a85a30"))
			ci.draw_rect(Rect2(p + Vector2(-5, -8) * s, Vector2(10, 2) * s), Color("#e0a060"))
		"crack":
			ci.draw_polyline(PackedVector2Array([p + Vector2(-6, -1), p + Vector2(-2, 1), p + Vector2(1, -2), p + Vector2(6, 1)]), Color("#8e5430"), 1.2)
		"tuft":
			var g := Color("#4f9a34")
			ci.draw_line(p, p + Vector2(-2, -4), g, 1.2)
			ci.draw_line(p, p + Vector2(0, -5), g, 1.2)
			ci.draw_line(p, p + Vector2(2, -4), g, 1.2)
		"flower":
			var cols := [Color("#ffe14a"), Color("#ff7aa8"), Color("#ffffff")]
			ci.draw_circle(p, 1.6, cols[v])
			ci.draw_circle(p + Vector2(4, 2), 1.4, cols[(v + 1) % 3])
		"wave":
			ci.draw_polyline(PackedVector2Array([p + Vector2(-5, 0), p + Vector2(-2.5, -2), p, p + Vector2(2.5, -2), p + Vector2(5, 0)]), Color(1, 1, 1, 0.45), 1.2)

## Town icon by size (hamlet..city) with roofs and banner in the faction colours.
func _draw_town(t: Dictionary) -> void:
	var p: Vector2 = t["pos"]
	var size := int(t["size"])
	var f: Dictionary = DB.factions[t["faction"]]
	var prim := Color(f["colors"]["primary"])
	var sec := Color(f["colors"]["secondary"])
	var roof := prim.lightened(0.15)
	var wall := Color("#efe2c4") if f["race"] != "orc" and f["race"] != "goblin" else Color("#a88a62")
	if f["race"] == "dwarf":
		wall = Color("#b4aea4")   # v0.012: the holds' stone
	var r := 12.0 + size * 5.0
	# trodden ground
	draw_set_transform(p + Vector2(0, 4), 0, Vector2(1.0, 0.6))
	draw_circle(Vector2.ZERO, r + 6, Color(0, 0, 0, 0.18))
	draw_circle(Vector2.ZERO, r + 3, Color("#c9ad7a"))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	var houses: Array = [[Vector2(0, 0)], [Vector2(-7, 2), Vector2(6, -2)], [Vector2(-10, 4), Vector2(9, 3), Vector2(0, -5)],
		[Vector2(-14, 5), Vector2(13, 4), Vector2(-4, -6), Vector2(8, -8), Vector2(0, 8)],
		[Vector2(-16, 6), Vector2(15, 5), Vector2(-7, -7), Vector2(9, -9), Vector2(0, 9), Vector2(-17, -3), Vector2(17, -4)]][clampi(size, 0, 4)]
	if size >= 3:
		# wall ring
		var pts := PackedVector2Array()
		for k in 25:
			var a := TAU * k / 24.0
			pts.append(p + Vector2(cos(a) * (r + 2), sin(a) * (r + 2) * 0.62 + 3))
		draw_polyline(pts, Color("#55504a"), 6.0)
		draw_polyline(pts, Color("#b6b0a6") if size == 4 else Color("#9c7c52"), 4.0)
	for h in houses:
		_house(p + h, wall, roof)
	if size >= 2:
		# keep / hall
		var k := p + Vector2(0, -2)
		draw_rect(Rect2(k + Vector2(-5, -16), Vector2(10, 16)), wall.darkened(0.1))
		draw_colored_polygon(PackedVector2Array([k + Vector2(-7, -16), k + Vector2(7, -16), k + Vector2(0, -25)]), prim)
	if size >= 3:
		for a in [0.0, PI * 0.5, PI, PI * 1.5]:
			var tp: Vector2 = p + Vector2(cos(a) * (r + 2), sin(a) * (r + 2) * 0.62 + 3)
			draw_rect(Rect2(tp + Vector2(-4, -10), Vector2(8, 11)), Color("#a8a29a"))
			draw_rect(Rect2(tp + Vector2(-5, -12), Vector2(10, 3)), prim)
	# banner
	var bp := p + Vector2(r * 0.55, -r * 0.4 - 6)
	draw_line(bp, bp + Vector2(0, -22), Color("#3a2a1a"), 2.0)
	draw_colored_polygon(PackedVector2Array([bp + Vector2(1, -22), bp + Vector2(15, -19), bp + Vector2(1, -14)]), prim)
	draw_colored_polygon(PackedVector2Array([bp + Vector2(1, -19), bp + Vector2(9, -18), bp + Vector2(1, -16)]), sec)

func _house(p: Vector2, wall: Color, roof: Color) -> void:
	draw_rect(Rect2(p + Vector2(-5, -6), Vector2(10, 7)), wall)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-7, -6), p + Vector2(7, -6), p + Vector2(0, -13)]), roof)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(7, -6), p + Vector2(0, -13)]), roof.darkened(0.2))
	draw_rect(Rect2(p + Vector2(-1.5, -3), Vector2(3, 4)), Color("#4a3220"))

func _draw_label(t: Dictionary) -> void:
	var p: Vector2 = t["pos"]
	var fs := 15 + int(t["size"]) * 2
	var txt: String = t["name"]
	var width := 220.0
	var lp := p + Vector2(-width * 0.5, 28 + int(t["size"]) * 4)
	var hostile := Game.world == world and CampaignWorld.is_hostile(Game, t["faction"])
	draw_string_outline(font, lp, txt, HORIZONTAL_ALIGNMENT_CENTER, width, fs, 5, Color(0.08, 0.06, 0.04, 0.9))
	draw_string(font, lp, txt, HORIZONTAL_ALIGNMENT_CENTER, width, fs, Color("#ffb4a0") if hostile else Color("#fff6dc"))
