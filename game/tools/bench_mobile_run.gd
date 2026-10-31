extends Node
## Headless phone benchmark body (launcher and options: tools/bench_mobile.gd). Two benchmarks, N frames each:
##   battle: native Factory forces, 100 a side on the large field, real battle screen (sim, actors, gore, fx, HUD)
##   map:    the saved DevTools start world (Normal, one-day history), a house chosen, the party travelling far
## Each frame advances game time by a FIXED 1/60 s (the screen's own _process is driven with that delta), and the
## engine runs uncapped, so the frame time is the CPU work for one 60 FPS frame: the same game work before and after
## a change. Headless has no GPU: draw-command building (_draw) is measured, GPU raster time is not.
## Prints one line per benchmark and a final "BENCH_MOBILE {json}" line. Nothing is saved over the player's game.

const FIXED_DT := 1.0 / 60.0

var frames := 600
var warmup := 30
var battle_speed := 1.0
var map_speed := 1
var per_side := 100
var only := ""

func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--frames="): frames = maxi(1, int(a.trim_prefix("--frames=")))
		elif a.begins_with("--warmup="): warmup = maxi(0, int(a.trim_prefix("--warmup=")))
		elif a.begins_with("--speed="): battle_speed = float(a.trim_prefix("--speed="))
		elif a.begins_with("--map-speed="): map_speed = int(a.trim_prefix("--map-speed="))
		elif a.begins_with("--per-side="): per_side = clampi(int(a.trim_prefix("--per-side=")), 2, 200)
		elif a.begins_with("--only="): only = a.trim_prefix("--only=")
	_run.call_deferred()

func _uncap() -> void:
	# Benchmark frames run as fast as the work allows (a phone frame cap would hide the cost being measured).
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false

func _run() -> void:
	_uncap()
	Game.SAVE_PATH = "user://bench_save_%d.json" % OS.get_process_id()
	Game.SETTINGS_PATH = "user://bench_settings_%d.json" % OS.get_process_id()
	Game.load_settings()
	Game.settings["guide_seen"] = true
	var report := {"version": str(ProjectSettings.get_setting("application/config/version", "?")),
		"engine": Engine.get_version_info().get("string", ""), "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "debug_build": OS.is_debug_build(),
		"mobile_profile": OS.has_feature("mobile") or "--mobile-profile" in OS.get_cmdline_user_args(),
		"frames": frames, "warmup": warmup, "fixed_dt_ms": snappedf(FIXED_DT * 1000.0, 0.001),
		"cpu": OS.get_processor_name(), "cores": OS.get_processor_count()}
	if only != "map":
		report["battle"] = await _bench_battle()
	if only != "battle":
		report["map"] = await _bench_map()
	report["static_memory_peak_process_mib"] = _mib(Performance.get_monitor(Performance.MEMORY_STATIC_MAX))
	print("BENCH_MOBILE ", JSON.stringify(report))
	for p in [Game.SAVE_PATH, Game.SETTINGS_PATH]:
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	get_tree().quit(0)

# ------------------------------------------------------------------ measurement
static func _mib(bytes: float) -> float:
	return snappedf(bytes / 1048576.0, 0.1)

static func _pct(sorted: PackedFloat32Array, f: float) -> float:
	if sorted.is_empty(): return 0.0
	return float(sorted[mini(sorted.size() - 1, maxi(0, ceili(sorted.size() * f) - 1))])

## Runs warmup + frames frames; step(dt) is called once per frame before the engine's own frame work.
func _measure(step: Callable) -> Dictionary:
	var times := PackedFloat32Array()
	var proc_ms := 0.0
	var phys_ms := 0.0
	var draws := 0.0
	var peak_static := 0.0
	var peak_objects := 0
	var peak_nodes := 0
	var tree := get_tree()
	await tree.process_frame
	var last := Time.get_ticks_usec()
	for i in warmup + frames:
		step.call(FIXED_DT)
		await tree.process_frame
		var now := Time.get_ticks_usec()
		if i >= warmup:
			times.append(float(now - last) / 1000.0)
			proc_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			phys_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			peak_static = maxf(peak_static, Performance.get_monitor(Performance.MEMORY_STATIC))
			peak_objects = maxi(peak_objects, int(Performance.get_monitor(Performance.OBJECT_COUNT)))
			peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		last = now
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	var over16 := 0
	var over33 := 0
	for t in sorted:
		total += t
		if t > 16.7: over16 += 1
		if t > 33.4: over33 += 1
	var n := maxf(1.0, float(sorted.size()))
	return {"frames": sorted.size(), "avg_ms": snappedf(total / n, 0.01), "p50_ms": snappedf(_pct(sorted, 0.5), 0.01),
		"p95_ms": snappedf(_pct(sorted, 0.95), 0.01), "p99_ms": snappedf(_pct(sorted, 0.99), 0.01),
		"max_ms": snappedf(_pct(sorted, 1.0), 0.01), "frames_over_16_7ms": over16, "frames_over_33_4ms": over33,
		"process_ms_avg": snappedf(proc_ms / n, 0.01), "physics_ms_avg": snappedf(phys_ms / n, 0.01),
		"draw_calls_avg": int(draws / n), "objects_peak": peak_objects, "nodes_peak": peak_nodes,
		"objects_end": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes_end": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"static_memory_peak_mib": _mib(peak_static)}

## The heaviest Perf labels since `Perf._labels` was cleared: [label, calls, mean ms, peak ms, total s].
func _labels(top: int = 10) -> Array:
	var rows: Array = []
	for k in Perf._labels:
		var st: Dictionary = Perf._labels[k]
		rows.append([str(k), int(st["calls"]), snappedf(float(st["mean"]) / 1000.0, 0.001), snappedf(float(st["peak"]) / 1000.0, 0.01), snappedf(float(st["mean"]) * int(st["calls"]) / 1e6, 0.001)])
	rows.sort_custom(func(a, b): return a[4] > b[4])
	return rows.slice(0, top)

static func _count_canvas_items(n: Node) -> int:
	var c := 1 if n is CanvasItem and (n as CanvasItem).is_visible_in_tree() else 0
	for child in n.get_children(): c += _count_canvas_items(child)
	return c

func _print_line(what: String, r: Dictionary) -> void:
	print("bench %s: avg %.2f ms  p95 %.2f ms  max %.2f ms  process %.2f ms  physics %.2f ms  objects %d  nodes %d  static peak %.1f MiB" % [
		what,float(r["avg_ms"]), float(r["p95_ms"]), float(r["max_ms"]), float(r["process_ms_avg"]), float(r["physics_ms_avg"]),
		int(r["objects_peak"]), int(r["nodes_peak"]), float(r["static_memory_peak_mib"])])

# ------------------------------------------------------------------ battle
func _bench_battle() -> Dictionary:
	_uncap()
	var started := Time.get_ticks_usec()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	Game.company = Factory.make_warband(rng, "middle_kingdom", per_side)
	Game.invalidate_deploy()
	Game.pending_battle = {"enemy": Factory.make_warband(rng, "orc_horde", per_side), "allies": [], "seed": 1010,
		"terrain": "grassland", "map": "large"}
	var battle: Node = (load("res://battle/battle.tscn") as PackedScene).instantiate()
	add_child(battle)
	var setup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	battle.set_speed(battle_speed)
	battle.set_process(false)   # driven below at a fixed delta
	Perf._labels.clear(); Perf._overall = {}
	var r: Dictionary = await _measure(func(dt: float): battle._process(dt))
	r["setup_ms"] = snappedf(setup_ms, 0.1)
	r["speed"] = battle_speed
	r["fighters"] = battle.sim.fighters.size()
	r["sim_ticks"] = battle.sim.tick
	r["over"] = battle.sim.is_over()
	r["canvas_items_visible"] = _count_canvas_items(battle)
	var cache: Dictionary = Paperdoll.cache_stats()
	r["sprite_cache_entries"] = int(cache.get("entries", 0))
	r["sprite_cache_mib"] = _mib(float(cache.get("payload_bytes", 0)))
	r["labels_name_calls_meanms_peakms_totals"] = _labels()
	_print_line("battle %dv%d" % [per_side, per_side], r)
	battle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Game.pending_battle = {}
	Game.company.clear()
	Game.invalidate_deploy()
	r["static_memory_after_exit_mib"] = _mib(Performance.get_monitor(Performance.MEMORY_STATIC))
	return r

# ------------------------------------------------------------------ campaign map
func _bench_map() -> Dictionary:
	_uncap()
	var started := Time.get_ticks_usec()
	var ok: bool = await DevTools.start_world(get_tree(), Game.SAVE_PATH)
	if not ok:
		printerr("bench_mobile: the start world did not load")
		return {"error": "start world did not load"}
	var tid := DevTools.choose_house(Game)
	Game.world["party"]["safe_until"] = Game.day + 100.0   # no encounter interrupts the measurement
	var origin: Vector2 = Game.world["party"]["pos"]
	var extent := Vector2(WorldGen.W, WorldGen.H) * WorldGen.CELL - Vector2(100, 100)
	var corners := [Vector2(100, 100), Vector2(extent.x, 100), Vector2(100, extent.y), extent]
	corners.sort_custom(func(a: Vector2, b: Vector2): return origin.distance_squared_to(a) > origin.distance_squared_to(b))
	var map: Node = (load("res://campaign/world_map.tscn") as PackedScene).instantiate()
	add_child(map)
	for corner: Vector2 in corners:
		if CampaignWorld.set_travel(Game, corner): break
	var setup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	map.speed_mult = map_speed
	map.set_process(false)   # driven below at a fixed delta
	_uncap()
	Perf._labels.clear(); Perf._overall = {}
	var day0 := float(Game.day)
	var r: Dictionary = await _measure(func(dt: float):
		OS.low_processor_usage_mode = false
		if str(Game.world.get("encounter", "")) != "": CampaignWorld.retreat(Game, Game.world["encounter"])
		if not CampaignWorld.is_travelling(Game): Game.world["party"]["waiting"] = true   # time keeps passing
		map._process(dt))
	r["setup_ms"] = snappedf(setup_ms, 0.1)
	r["house_town"] = tid
	r["speed_mult"] = map_speed
	r["days_passed"] = snappedf(float(Game.day) - day0, 0.01)
	r["towns"] = Game.world.get("towns", {}).size()
	r["warbands"] = Game.world.get("warbands", {}).size()
	r["canvas_items_visible"] = _count_canvas_items(map)
	r["labels_name_calls_meanms_peakms_totals"] = _labels()
	_print_line("campaign map", r)
	map.queue_free()
	await get_tree().process_frame
	return r
