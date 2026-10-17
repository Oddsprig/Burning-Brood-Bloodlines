class_name PerformanceTracker
extends Node
## Unsaved diagnostics only. Two fixed half-second buckets per label; no logs.
const LABEL_LIMIT := 64
const LABEL_LENGTH := 64
const BUCKET_US := 500000
const SAMPLE_SECONDS := 0.5
var _labels: Dictionary = {}
var _overall: Dictionary = {}
var _stage: String = "Idle"
var _queue_size: int = 0
var _queue_age: float = 0.0
var _dropped: int = 0
var _invalid: int = 0
var _started_us: int = Time.get_ticks_usec()
var _opened_us: int = _started_us
var _opened_memory: Variant = null
var _engine: Dictionary = {}
var _sample_clock: float = 0.0
var _samples: int = 0
var _process_peak_ms: float = 0.0
var _physics_peak_ms: float = 0.0
var _ownership: Dictionary = {"available": false}
var _terrain_ownership: Dictionary = {}
var _process_memory: Dictionary = {"private_bytes": null, "working_bytes": null}
var _combat_history: Dictionary = {}

## Cached plain counters only; never retain a simulation/journal in the tracker.
func record_combat_history(stats: Dictionary = {}) -> void:
	_combat_history.clear()
	for key: String in ["records", "attempted", "dropped", "active_records", "cached_records", "memory_record_limit", "disk_bytes", "index_bytes", "complete", "error", "disposed"]:
		if stats.has(key) and typeof(stats[key]) <= TYPE_STRING: _combat_history[key] = stats[key]

## Explicit checkpoints only. Panel/snapshot reads never traverse the live world.
func refresh_owners(game: Object, label: String = "Manual checkpoint", max_values: int = 250000, max_us: int = 20000) -> Dictionary:
	_ownership = MemoryOwners.capture(game, _name(label), max_values, max_us)
	record_us("Memory ownership checkpoint", int(_ownership["elapsed_us"]))
	return _ownership.duplicate(true)

## Called by the map once after mount, or by a diagnostic harness.
func record_terrain_owners(stats: Dictionary) -> void:
	_terrain_ownership = {}
	for key: String in ["chunks", "decor", "packed_bytes", "vertices", "triangles", "native_commands", "submitted_commands", "source_commands", "source_rows", "source_arrays", "texture_rgba_estimate_bytes", "mounted"]:
		if stats.has(key) and typeof(stats[key]) <= TYPE_STRING: _terrain_ownership[key] = stats[key]

## Optional measured OS input. No process-memory value is inferred from Godot RAM.
func record_process_memory(private_bytes: int, working_bytes: int) -> void:
	_process_memory = {"private_bytes": private_bytes if private_bytes >= 0 else null, "working_bytes": working_bytes if working_bytes >= 0 else null, "captured_us": Time.get_ticks_usec()}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sample_engine()
	mark_open()

func _process(delta: float) -> void:
	_sample_clock += delta
	if _sample_clock >= SAMPLE_SECONDS:
		_sample_clock = 0.0
		_sample_engine()

static func _name(label: String) -> String:
	var clean: String = label.strip_edges().replace("\n", " ").replace("\r", " ")
	if "/" in clean or "\\" in clean: clean = clean.replace("\\", "/").get_file().get_basename().replace("_", " ").capitalize()
	return clean.left(LABEL_LENGTH) if clean != "" else "Other work"

static func _stat(label: String) -> Dictionary:
	return {"label": label, "calls": 0, "mean": 0.0, "peak": 0, "latest": 0, "last_us": -1,
		"buckets": [{"id": -1, "calls": 0, "sum": 0.0, "peak": 0}, {"id": -1, "calls": 0, "sum": 0.0, "peak": 0}]}

static func _record(stat: Dictionary, elapsed_us: int, now: int) -> void:
	var calls: int = int(stat["calls"]) + 1
	stat["calls"] = calls
	stat["mean"] = float(stat["mean"]) + (float(elapsed_us) - float(stat["mean"])) / float(calls)
	stat["peak"] = maxi(int(stat["peak"]), elapsed_us)
	stat["latest"] = elapsed_us; stat["last_us"] = now
	var bucket_id: int = now / BUCKET_US
	var bucket: Dictionary = stat["buckets"][bucket_id % 2]
	if int(bucket["id"]) != bucket_id:
		bucket["id"] = bucket_id; bucket["calls"] = 0; bucket["sum"] = 0.0; bucket["peak"] = 0
	bucket["calls"] = int(bucket["calls"]) + 1
	bucket["sum"] = float(bucket["sum"]) + float(elapsed_us)
	bucket["peak"] = maxi(int(bucket["peak"]), elapsed_us)

func record_us(label: String, elapsed_us: int, overall: bool = false) -> void:
	if elapsed_us < 0: _invalid += 1; return
	var now: int = Time.get_ticks_usec()
	var clean: String = _name(label)
	if overall:
		# One inclusive source, recorded once per non-overlapping main work slice.
		# Never derive this total by adding inclusive nested label measurements.
		if _overall.is_empty(): _overall = _stat(clean)
		_record(_overall, elapsed_us, now)
		return
	if not _labels.has(clean):
		if _labels.size() >= LABEL_LIMIT: _dropped += 1; return
		_labels[clean] = _stat(clean)
	_record(_labels[clean], elapsed_us, now)

func record_queue(size: int, oldest_days: float = 0.0) -> void:
	_queue_size = maxi(0, size)
	_queue_age = maxf(0.0, oldest_days) if is_finite(oldest_days) and _queue_size > 0 else 0.0

func set_stage(stage: String) -> void:
	_stage = _name(stage)

func mark_open() -> void:
	_opened_us = Time.get_ticks_usec()
	_opened_memory = int(Performance.get_monitor(Performance.MEMORY_STATIC)) if OS.is_debug_build() else null

static func _read_engine() -> Dictionary:
	var fps: float = float(Performance.get_monitor(Performance.TIME_FPS))
	var debug: bool = OS.is_debug_build()
	var renderer: bool = DisplayServer.get_name() != "headless"
	return {"fps": fps, "frame_ms": 1000.0 / fps if fps > 0 else 0.0,
		"process_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
		"physics_ms": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
		"memory_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)) if debug else null,
		"memory_peak_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) if debug else null,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) if debug else null,
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)) if renderer else null,
		"texture_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) if renderer else null,
		"debug_counters": debug, "renderer_counters": renderer}

func _sample_engine() -> void:
	_engine = _read_engine()
	_samples += 1
	_process_peak_ms = maxf(_process_peak_ms, float(_engine["process_ms"]))
	_physics_peak_ms = maxf(_physics_peak_ms, float(_engine["physics_ms"]))

static func _reduce(stat: Dictionary, now: int) -> Dictionary:
	var out: Dictionary = {"label": "", "calls": 0, "recent_calls": 0, "latest_us": 0, "mean_us": 0.0, "peak_us": 0,
		"total_us": 0.0, "session_latest_us": 0, "session_mean_us": 0.0, "session_peak_us": 0, "last_age_s": -1.0}
	if stat.is_empty(): return out
	out["label"] = stat["label"]; out["calls"] = stat["calls"]
	out["session_latest_us"] = stat["latest"]; out["session_mean_us"] = stat["mean"]; out["session_peak_us"] = stat["peak"]
	out["last_age_s"] = float(now - int(stat["last_us"])) / 1000000.0
	var current: int = now / BUCKET_US
	for bucket: Dictionary in stat["buckets"]:
		if int(bucket["id"]) < current - 1 or int(bucket["id"]) > current: continue
		out["recent_calls"] = int(out["recent_calls"]) + int(bucket["calls"])
		out["total_us"] = float(out["total_us"]) + float(bucket["sum"])
		out["peak_us"] = maxi(int(out["peak_us"]), int(bucket["peak"]))
	if int(out["recent_calls"]) > 0:
		out["latest_us"] = stat["latest"]
		out["mean_us"] = float(out["total_us"]) / float(out["recent_calls"])
	return out

func snapshot() -> Dictionary:
	var now: int = Time.get_ticks_usec()
	var engine: Dictionary = _engine.duplicate(true) if not _engine.is_empty() else _read_engine()
	var rows: Array[Dictionary] = []
	for stat: Dictionary in _labels.values(): rows.append(_reduce(stat, now))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["mean_us"]) == float(b["mean_us"]): return String(a["label"]) < String(b["label"])
		return float(a["mean_us"]) > float(b["mean_us"]))
	engine["memory_change_bytes"] = int(engine["memory_bytes"]) - int(_opened_memory) if engine["memory_bytes"] != null and _opened_memory != null else null
	var ownership: Dictionary = _ownership.duplicate(true)
	ownership["age_s"] = float(now - int(ownership.get("captured_us", now))) / 1000000.0
	ownership["terrain"] = _terrain_ownership.duplicate()
	ownership["sprites"] = Paperdoll.cache_stats()
	ownership["combat_history"] = _combat_history.duplicate()
	var game: Node = get_node_or_null("/root/Game") if is_inside_tree() else null
	ownership["save"] = game.call("save_stats") if game != null and game.has_method("save_stats") else {}
	var process_memory: Dictionary = _process_memory.duplicate()
	process_memory["age_s"] = float(now - int(process_memory.get("captured_us", now))) / 1000000.0
	return {"stage": _stage, "queue_size": _queue_size, "oldest_days": _queue_age, "engine": engine,
		"ownership": ownership, "process_memory": process_memory,
		"overall": _reduce(_overall, now), "jobs": rows, "label_limit": LABEL_LIMIT, "dropped_labels": _dropped,
		"invalid_samples": _invalid, "sample_count": _samples, "sample_seconds": SAMPLE_SECONDS,
		"recent_window_s": 0.5 + float(now % BUCKET_US) / 1000000.0,
		"session_s": float(now - _started_us) / 1000000.0, "opened_s": float(now - _opened_us) / 1000000.0,
		"process_sampled_peak_ms": _process_peak_ms, "physics_sampled_peak_ms": _physics_peak_ms}
