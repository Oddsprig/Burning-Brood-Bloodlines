extends Node2D
## v0.014 battle gore (Douglas 22:51: "more gore-heavy when people are injured"), drawn from the REAL sim results:
##   spray(pos, dir, n)   blood droplets on a hit, n from the strike's real layer damage and artery (battle.gd)
##   tick(sim, views)     once per sim tick: trail drips behind bleeding fighters (their real Fighter.bleeding rate),
##                        arterial spurts from parts bleeding at artery rates, and a pool under every fighter who is
##                        down or dead that grows with the blood he has really lost (body.blood / blood_max).
## Cheap by construction: droplets live in a fixed pool of MAX_DROPS slots (packed arrays, no per-frame allocation);
## ground decals (drips, splats) are a ring buffer of MAX_DECALS that overwrites the oldest; pools are one per
## fighter. Retained contiguous slot chunks redraw only when their slots change; pools draw separately.
## The public decal root still accepts queue_redraw() to invalidate custom array/pool edits.
## Gore Reduced (Game "gore"): a third of the droplets, no spurts, half-size pools, sparse trails.
## v0.072 phones (MobilePerf.cheap_fx): half the droplets and drips; droplets in flight draw as rects (one batch)
## and each ground-decal chunk is one triangle array of 8-sided dots instead of 30 separate 64-segment circles.

const MobilePerf := preload("res://core/mobile_perf.gd")
const MAX_DROPS := 384
const MAX_DECALS := 900
const DECAL_CHUNK_SIZE := 30
const DECAL_CHUNK_COUNT := MAX_DECALS / DECAL_CHUNK_SIZE
const DROP_LIFE := 0.55
const GRAVITY := 520.0
const TRAIL_PER_RATE := 40.0      # drips per tick per unit of bleed rate (0.02/tick muscle cut -> a drip every ~1.2 ticks)
const SPURT_RATE := 0.03          # a part bleeding at least this much a tick spurts (Formulas.BLEED_WORDS[0]: an artery)
const SPURT_EVERY := 14           # ticks between spurts (a pulse)
const POOL_MAX := 30.0            # px radius at 45% blood lost (dead)
const BLOOD := Color("#b0101a")
const BLOOD_DARK := Color("#5e080e")

var full := true
var tile := 40.0
var cheap := false   # v0.072 phone drawing (MobilePerf.cheap_fx)
const CHEAP_SIDES := 8
var _dot_dirs := PackedVector2Array()   # unit 8-gon, y squashed like the decal ellipse
var _dot_idx := PackedInt32Array()      # fan indices for a full chunk
var _dot_pts := PackedVector2Array()
var _dot_cols := PackedColorArray()

# droplets in flight
var _dp := PackedVector2Array()
var _dv := PackedVector2Array()
var _dl := PackedFloat32Array()   # life left (<= 0 = free slot)
var _dground := PackedFloat32Array()   # y where the drop lands
var _ds := PackedFloat32Array()   # size
var _alive := 0
var _next := 0

# ground decals (ring buffer)
var _gp := PackedVector2Array()
var _gr := PackedFloat32Array()
var _gc := PackedColorArray()
var _gn := 0
var _gi := 0
var _pools := {}                  # fighter idx -> [Vector2 centre, float radius]
var _trail_acc := {}              # fighter idx -> drip accumulator
var _rng := RandomNumberGenerator.new()

var decals: Node2D
var drops: Node2D
var _pool_canvas: Node2D
var _decal_chunks: Array[Node2D] = []

func setup(tile_px: float, gore_full: bool, rseed: int) -> void:
	tile = tile_px
	full = gore_full
	cheap = MobilePerf.cheap_fx()
	if cheap and _dot_dirs.is_empty():
		for i in CHEAP_SIDES:
			var a := TAU * i / float(CHEAP_SIDES)
			_dot_dirs.append(Vector2(cos(a), sin(a) * 0.6))
		var per := CHEAP_SIDES + 1
		for k in DECAL_CHUNK_SIZE:
			for i in CHEAP_SIDES:
				_dot_idx.append(k * per); _dot_idx.append(k * per + 1 + i); _dot_idx.append(k * per + 1 + (i + 1) % CHEAP_SIDES)
		_dot_pts.resize(DECAL_CHUNK_SIZE * per); _dot_cols.resize(DECAL_CHUNK_SIZE * per)
	_rng.seed = rseed * 31 + 7
	_dp.resize(MAX_DROPS); _dv.resize(MAX_DROPS); _dl.resize(MAX_DROPS); _dground.resize(MAX_DROPS); _ds.resize(MAX_DROPS)
	_dl.fill(0.0)
	_gp.resize(MAX_DECALS); _gr.resize(MAX_DECALS); _gc.resize(MAX_DECALS)
	if decals == null:
		decals = Node2D.new()
		decals.draw.connect(_draw_decals)
		add_child(decals)
		# Native alpha order: every pool first, then ring slots 0..899.
		_pool_canvas = Node2D.new()
		_pool_canvas.name = "Pools"
		_pool_canvas.draw.connect(_draw_pools)
		decals.add_child(_pool_canvas)
		for chunk: int in DECAL_CHUNK_COUNT:
			var canvas := Node2D.new()
			canvas.name = "Slots%d" % chunk
			canvas.draw.connect(_draw_decal_chunk.bind(chunk))
			decals.add_child(canvas)
			_decal_chunks.append(canvas)
	if drops == null:
		drops = Node2D.new()
		drops.z_index = 6
		drops.draw.connect(_draw_drops)
		add_child(drops)
	decals.queue_redraw()
	drops.queue_redraw()

## Counts for tests and the perf check.
func decal_count() -> int:
	return _gn
func drop_count() -> int:
	return _alive
func pool_count() -> int:
	return _pools.size()
func pool_radius(idx: int) -> float:
	return float(_pools[idx][1]) if _pools.has(idx) else 0.0

## Blood droplets from `pos` (a body centre) flying along `dir` (attacker -> defender), n of them.
func spray(pos: Vector2, dir: Vector2, n: int, ground_y: float) -> void:
	if not full:
		n = n / 3
	if cheap:
		n = n / 2
	if n <= 0:
		return
	var base := dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	for i in n:
		var s := _next
		_next = (_next + 1) % MAX_DROPS
		if _dl[s] <= 0.0:
			_alive += 1
		var a := base.rotated(_rng.randf_range(-0.9, 0.9))
		var sp := _rng.randf_range(60.0, 210.0)
		_dp[s] = pos + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-4, 4))
		_dv[s] = a * sp + Vector2(0, -_rng.randf_range(40.0, 140.0))
		_dl[s] = DROP_LIFE * _rng.randf_range(0.6, 1.0)
		_dground[s] = ground_y + _rng.randf_range(-6, 6)
		_ds[s] = _rng.randf_range(1.2, 2.6)
	set_process(true)

func _decal(p: Vector2, r: float, c: Color) -> void:
	var slot: int = _gi
	_gp[_gi] = p
	_gr[_gi] = r
	_gc[_gi] = c
	_gi = (_gi + 1) % MAX_DECALS
	_gn = mini(_gn + 1, MAX_DECALS)
	_decal_chunks[slot / DECAL_CHUNK_SIZE].queue_redraw()

## One sim tick: drips, spurts, pools (all from the fighters' real bleeding and blood).
func tick(sim, views: Array) -> void:
	var pools_changed := false
	for f in sim.fighters:
		if f.waiting or f.state == "fled":
			continue
		var v = views[f.idx]
		var rate := 0.0
		for pid in f.bleeding:
			rate += float(f.bleeding[pid])
		var down: bool = f.state == "dead" or f.state == "unconscious" or f.prone
		var feet: Vector2 = v.position
		if rate > 0.0 and f.state != "dead":
			var acc := float(_trail_acc.get(f.idx, 0.0)) + rate * TRAIL_PER_RATE * (1.0 if full else 0.35) * (0.5 if cheap else 1.0)
			while acc >= 1.0:
				acc -= 1.0
				_decal(feet + Vector2(_rng.randf_range(-9, 9), _rng.randf_range(-4, 3)), _rng.randf_range(1.0, 2.2) + minf(2.0, rate * 20.0),
					BLOOD if _rng.randf() < 0.6 else BLOOD_DARK)
			_trail_acc[f.idx] = acc
			if full and (sim.tick + f.idx) % SPURT_EVERY == 0:
				for pid in f.bleeding:
					if float(f.bleeding[pid]) >= SPURT_RATE:
						spray(v.body_center() + _part_offset(String(pid)), Vector2(float(f.facing) * -1.0, -0.6), 5 + int(float(f.bleeding[pid]) * 40.0), feet.y)
						break
		if down:
			var lost: float = 1.0 - clampf(f.unit.body.blood / maxf(f.unit.body.blood_max, 0.001), 0.0, 1.0)
			var r: float = (6.0 + POOL_MAX * sqrt(clampf(lost / 0.45, 0.0, 1.0))) * (1.0 if full else 0.5)
			var cur = _pools.get(f.idx)
			if cur == null:
				_pools[f.idx] = [feet + Vector2(0, -3), r]
				pools_changed = true
			elif r > float(cur[1]) + 0.25:
				cur[1] = r   # pools only grow
				pools_changed = true
	if pools_changed:
		_pool_canvas.queue_redraw()

## Rough height of a part on the figure (spurts come from the right place).
func _part_offset(pid: String) -> Vector2:
	if pid in ["head", "neck", "throat"] or pid.begins_with("ear") or pid.begins_with("eye"):
		return Vector2(0, -16)
	if pid.begins_with("leg") or pid.begins_with("foot") or pid.begins_with("toe"):
		return Vector2(0, 14)
	if pid.begins_with("arm") or pid.begins_with("hand") or pid.begins_with("finger"):
		return Vector2(8, 0)
	return Vector2.ZERO

func _process(delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	_process_drops(delta)
	Perf.record_us("Battle gore process", Time.get_ticks_usec() - started)

func _process_drops(delta: float) -> void:
	if _alive <= 0:
		set_process(false)
		return
	for s in MAX_DROPS:
		if _dl[s] <= 0.0:
			continue
		_dl[s] -= delta
		_dv[s] = _dv[s] + Vector2(0, GRAVITY * delta)
		_dp[s] = _dp[s] + _dv[s] * delta
		if _dl[s] <= 0.0 or (_dv[s].y > 0.0 and _dp[s].y >= _dground[s]):
			_dl[s] = 0.0
			_alive -= 1
			if s % 2 == 0:   # every other droplet leaves a splat where it lands
				_decal(Vector2(_dp[s].x, minf(_dp[s].y, _dground[s])), _ds[s] * 1.3, BLOOD)
	drops.queue_redraw()

func _draw_decals() -> void:
	var started: int = Time.get_ticks_usec()
	_draw_decals_body()
	# All gore draw callbacks share a CPU label; each call is timed separately.
	Perf.record_us("Battle gore draw", Time.get_ticks_usec() - started)

func _draw_decals_body() -> void:
	# Explicit root invalidation also covers callers editing packed arrays/pools.
	# Normal tick/landing mutations queue their affected child directly.
	_pool_canvas.queue_redraw()
	for canvas: Node2D in _decal_chunks:
		canvas.queue_redraw()

func _draw_pools() -> void:
	var started: int = Time.get_ticks_usec()
	for idx in _pools:
		var pl: Array = _pools[idx]
		var c: Vector2 = pl[0]
		var r: float = pl[1]
		_pool_canvas.draw_set_transform(c, 0.0, Vector2(1.0, 0.45))
		_pool_canvas.draw_circle(Vector2.ZERO, r, BLOOD_DARK.lerp(BLOOD, 0.3))
		_pool_canvas.draw_circle(Vector2(-r * 0.2, -r * 0.15), r * 0.55, BLOOD.darkened(0.1))
	_pool_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	Perf.record_us("Battle gore draw", Time.get_ticks_usec() - started)

func _draw_decal_chunk(chunk: int) -> void:
	var started: int = Time.get_ticks_usec()
	var canvas: Node2D = _decal_chunks[chunk]
	var first: int = chunk * DECAL_CHUNK_SIZE
	if cheap:
		_draw_decal_chunk_cheap(canvas, first, mini(first + DECAL_CHUNK_SIZE, _gn))
		Perf.record_us("Battle gore draw", Time.get_ticks_usec() - started)
		return
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.6))
	for i: int in range(first, mini(first + DECAL_CHUNK_SIZE, _gn)):
		var p := _gp[i]
		canvas.draw_circle(Vector2(p.x, p.y / 0.6), _gr[i], _gc[i])
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	Perf.record_us("Battle gore draw", Time.get_ticks_usec() - started)

## Phones: one chunk's decals as a single triangle array (same ellipse centre/radii as the circle path).
func _draw_decal_chunk_cheap(canvas: Node2D, first: int, last: int) -> void:
	var n := last - first
	if n <= 0: return
	var per := CHEAP_SIDES + 1
	for k in n:
		var i := first + k
		var p := _gp[i]
		var r := _gr[i]
		var c := _gc[i]
		var base := k * per
		_dot_pts[base] = p; _dot_cols[base] = c
		for j in CHEAP_SIDES:
			_dot_pts[base + 1 + j] = p + _dot_dirs[j] * r
			_dot_cols[base + 1 + j] = c
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), _dot_idx.slice(0, n * CHEAP_SIDES * 3),
		_dot_pts.slice(0, n * per), _dot_cols.slice(0, n * per))

func _draw_drops() -> void:
	var started: int = Time.get_ticks_usec()
	_draw_drops_body()
	Perf.record_us("Battle gore draw", Time.get_ticks_usec() - started)

func _draw_drops_body() -> void:
	if cheap:   # phones: rects batch into one draw; a 1-3 px droplet in flight reads the same
		for s in MAX_DROPS:
			if _dl[s] > 0.0:
				var d := _ds[s]
				drops.draw_rect(Rect2(_dp[s] - Vector2(d, d), Vector2(d, d) * 2.0), BLOOD)
		return
	for s in MAX_DROPS:
		if _dl[s] > 0.0:
			drops.draw_circle(_dp[s], _ds[s], BLOOD)

func clear_all() -> void:
	_dl.fill(0.0)
	_alive = 0
	drops.queue_redraw()
