class_name Paperdoll
extends Node2D
## A layered unit sprite drawn in code: race base body + outer clothing/armor + helm + weapon
## (+ shield) + wound overlay. Bright, saturated faction colours; per-individual skin shade from unit.look.
## Origin is at the feet. Nominal height ~48 px for a human at scale 1 (24 logical pixels at 2x).
##
##   var d := Paperdoll.new(); d.set_unit(unit); add_child(d)
##   d.set_pose("idle"|"walk"|"prepare"|"strike"|"recover"|"hit"|"block"|"dodge"|"prone"|"dead", progress 0..1)
##   d.facing = 1 or -1
##   d.refresh()  # after equipment or wounds change
##   d.team_color = Color   # ring / banner tint so sides read at a glance
##
## Frames are rendered by FigurePainter into small ImageTextures and cached (shared by all dolls),
## keyed by the unit's look/gear/wound signature + pose + frame, so a battle of many units mostly
## reuses textures. idle and walk loop with progress (0..1 = one cycle); the other poses map
## progress 0..1 onto their few key frames.

## 400 native humans x (8 walk + one idle) frames ~=211 MiB.
## This is retained RGBA payload, not whole-process/GPU allocation. No preallocation.
const CACHE_LIMIT := 8192
const CACHE_BYTE_LIMIT := 256 * 1024 * 1024
const SIGNATURE_LIMIT := 8192
const BACKGROUND_JOB_LIMIT := 4
const BACKGROUND_REQUEST_LIMIT := 8192
const BACKGROUND_UPLOAD_LIMIT := 2
static var _background_active: bool = false
static var _background_requests: Dictionary = {} # Main-thread-only latest weak request per doll.
static var _background_jobs: Dictionary = {} # At most four detached snapshots/results.
static var _background_counters: Dictionary = {"dispatched": 0, "completed": 0, "retired": 0, "drained": 0,
	"coalesced": 0, "replaced": 0, "rejected": 0, "worker_elapsed_us": 0,
	"worker_latest_us": 0, "worker_peak_us": 0, "pending_peak": 0, "inflight_peak": 0}

class RasterWork extends RefCounted:
	var spec: Dictionary
	var pose_name: String
	var frame: int
	var image: Image
	var elapsed_us: int = 0
	func execute() -> void:
		# Only this worker owns the snapshot and result. Loaded DB art definitions
		# are read-only; no Unit, Item, scene tree, texture, cache or global RNG access.
		var started: int = Time.get_ticks_usec()
		image = FigurePainter.render(spec, pose_name, FigurePainter.frame_t(pose_name, frame))
		elapsed_us = Time.get_ticks_usec() - started
static var _cache: Dictionary = {}
static var _cache_meta: Dictionary = {}
static var _oldest: String = ""
static var _newest: String = ""
static var _cache_bytes: int = 0
static var _signature_buckets: Dictionary = {}
static var _signature_slots: Array[Dictionary] = []
static var _signature_cursor: int = 0
static var _signature_bytes: int = 0
static var _next_signature: int = 1 # Never reused while existing dolls may hold a token.
static var _stats: Dictionary = {"hits": 0, "misses": 0, "evictions": 0, "frame_reuses": 0,
	"spec_builds": 0, "raster_builds": 0, "uploads": 0, "redraw_requests": 0,
	"peak_entries": 0, "peak_bytes": 0, "oversize_frames": 0, "collision_checks": 0,
	"signature_hits": 0, "signature_misses": 0, "signature_evictions": 0}

var unit: Unit
var facing: int = 1:
	set(v):
		var sign_value: int = -1 if v < 0 else 1
		if sign_value != facing:
			facing = sign_value
			_request_redraw()
var pose: String = "idle"
var progress: float = 0.0
var team_color := Color.WHITE:
	set(v):
		if v != team_color:
			team_color = v
			invalidate()
			_request_redraw()

## bows: the unit has his bow in his hands (battle): the bow is drawn instead of the sidearm, the shield is slung.
var bow_hand := false:
	set(v):
		if v != bow_hand:
			bow_hand = v
			invalidate()
			_request_redraw()

var _spec: Dictionary = {}
var _sig: int = 0
var _dirty := true
var _tex: Texture2D
var _frame_key := ""
var _anchor := Vector2.ZERO
var _spec_bytes := PackedByteArray()
var _signature_id: int = 0
var _frame_pending: bool = true
var _render_frame_enabled: bool = true
var _background_rendering: bool = false
var _force_eager: bool = false
var _revision: int = 0
var _urgent_frame: bool = false

func _request_redraw() -> void:
	_stats["redraw_requests"] = int(_stats["redraw_requests"]) + 1
	queue_redraw()

func set_unit(u: Unit) -> void:
	unit = u
	refresh()

## Draw from a ready-made spec instead of a Unit (previews, party icons).
func set_spec(s: Dictionary) -> void:
	var started: int = Time.get_ticks_usec()
	unit = null
	_spec = s
	_spec["team"] = team_color
	_sig = _spec.hash()
	_spec_bytes = var_to_bytes(_spec)
	_signature_id = _signature_for(_sig, _spec_bytes)
	_dirty = false
	_frame_key = ""
	_frame_pending = true
	_render_frame_enabled = true
	_stats["spec_builds"] = int(_stats["spec_builds"]) + 1
	Perf.record_us("Sprite spec", Time.get_ticks_usec() - started)
	_revision += 1
	_cancel_background_request()
	_force_eager = true
	_update_tex()
	_force_eager = false
	_request_redraw()

func set_pose(p: String, t: float = 0.0, render_frame: bool = true) -> void:
	var old_pose: String = pose
	var old_frame: int = FigurePainter.frame_index(pose, progress)
	var old_hit_tint: bool = pose == "hit" and progress < 0.5
	var was_enabled: bool = _render_frame_enabled
	pose = p if FigurePainter.FRAMES.has(p) else "idle"
	progress = t
	_render_frame_enabled = render_frame
	if old_pose != pose or old_frame != FigurePainter.frame_index(pose, progress): _frame_pending = true
	# Track offscreen animation without rebuilding specs or software painting.
	# A queued facing redraw must not accidentally rasterize an offscreen actor.
	if not render_frame:
		_cancel_background_request()
		return
	var changed: bool = _update_tex()
	if changed or not was_enabled or old_hit_tint != (pose == "hit" and progress < 0.5): _request_redraw()

## Coalesced tick events call this once. No spec walk, raster, upload or redraw.
func invalidate() -> void:
	_revision += 1
	_urgent_frame = true
	_cancel_background_request()
	_dirty = true
	_frame_key = ""
	_frame_pending = true

func refresh() -> void:
	invalidate()
	_render_frame_enabled = true
	_rebuild_spec()
	_force_eager = true
	_update_tex()
	_force_eager = false
	_request_redraw()

## Opt-in only after the battle's initial eager set_unit(). Menu callers stay eager.
func set_background_rendering(enabled: bool) -> void:
	_background_rendering = enabled
	if not enabled: _cancel_background_request()

func _cancel_background_request() -> void:
	_background_requests.erase(get_instance_id())

func _exit_tree() -> void:
	_cancel_background_request()

func _rebuild_spec() -> void:
	var started: int = Time.get_ticks_usec()
	if unit != null:
		_spec = FigurePainter.spec_for_unit(unit, team_color)
		if bow_hand and unit.bow() != null:   # bows
			_spec["weapon"] = FigurePainter._item_spec(unit.bow())
			_spec["shield"] = {}
			_spec["bow_hand"] = true
	elif not _spec.is_empty():
		_spec["team"] = team_color
	_sig = _spec.hash()
	_spec_bytes = var_to_bytes(_spec)
	_signature_id = _signature_for(_sig, _spec_bytes)
	_dirty = false
	_stats["spec_builds"] = int(_stats["spec_builds"]) + 1
	Perf.record_us("Sprite spec", Time.get_ticks_usec() - started)

func current_spec() -> Dictionary:
	if _dirty:
		_rebuild_spec()
	return _spec

## Builds (or fetches) the texture for the current pose frame. Safe headless.
func _update_tex() -> bool:
	if _dirty:
		_rebuild_spec()
	if _spec.is_empty():
		var had_texture: bool = _tex != null
		_tex = null
		_frame_pending = false
		return had_texture
	var f := FigurePainter.frame_index(pose, progress)
	if not _frame_pending and _tex != null:
		_stats["frame_reuses"] = int(_stats["frame_reuses"]) + 1
		if _cache.get(_frame_key) == _tex: _touch(_frame_key)
		return false
	var previous: Texture2D = _tex
	var started: int = Time.get_ticks_usec()
	var key: String = "%d:%d|%s|%d" % [_sig, _signature_id, pose, f]
	if _cache.size() != _cache_meta.size(): _reconcile_external_cache()
	if _cache.has(key):
		var meta: Dictionary = _cache_meta.get(key, {})
		if meta.is_empty() or int(meta["texture_id"]) != (_cache[key] as Texture2D).get_instance_id():
			_remove_cached(key, false)
	_frame_key = key
	var dm := FigurePainter.dims(_spec.get("race", "human"))
	_anchor = dm["anchor"]
	if _cache.has(key):
		_tex = _cache[key]
		_cancel_background_request()
		_urgent_frame = false
		_touch(key)
		_stats["hits"] = int(_stats["hits"]) + 1
		Perf.record_us("Sprite cache hit", Time.get_ticks_usec() - started)
	else:
		if _background_rendering and _background_active and not _force_eager:
			var request: Dictionary = _background_requests.get(get_instance_id(), {})
			if String(request.get("key", "")) != key:
				_stats["misses"] = int(_stats["misses"]) + 1
				Perf.record_us("Sprite cache miss", Time.get_ticks_usec() - started)
				_enqueue_background(key, f)
			return false # Keep the last completed texture; never paint in this path.
		_stats["misses"] = int(_stats["misses"]) + 1
		Perf.record_us("Sprite cache miss", Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		var img: Image = build_image()
		_stats["raster_builds"] = int(_stats["raster_builds"]) + 1
		Perf.record_us("Sprite raster", Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		_tex = ImageTexture.create_from_image(img)
		_stats["uploads"] = int(_stats["uploads"]) + 1
		Perf.record_us("Sprite upload", Time.get_ticks_usec() - started)
		_store_cached(key, _tex, _signature_id, img.get_width() * img.get_height() * 4)
	_frame_pending = false
	_urgent_frame = false
	return _tex != previous

func _enqueue_background(key: String, frame: int) -> void:
	var id: int = get_instance_id()
	var request: Dictionary = _background_requests.get(id, {})
	if request.is_empty():
		if _background_requests.size() >= BACKGROUND_REQUEST_LIMIT:
			_background_counters["rejected"] = int(_background_counters["rejected"]) + 1
			return
		request = {"id": id, "doll": weakref(self), "queued_us": Time.get_ticks_usec()}
	else: _background_counters["replaced"] = int(_background_counters["replaced"]) + 1
	request["key"] = key; request["frame"] = frame; request["pose"] = pose
	request["signature"] = _signature_id; request["revision"] = _revision
	request["urgent"] = _urgent_frame
	_background_requests[id] = request
	if _background_jobs.has(key): _background_jobs[key]["participants"][id] = request["doll"]
	_background_counters["pending_peak"] = maxi(int(_background_counters["pending_peak"]), _background_requests.size())

## Lifecycle/pump calls are main-thread-only. End drains no more than four tasks
## before battle-owned data may go away or loaded definitions may change.
static func begin_background() -> void:
	end_background()
	for key: String in _background_counters: _background_counters[key] = 0
	_background_active = true

static func end_background() -> void:
	_background_active = false
	_background_requests.clear()
	for job: Dictionary in _background_jobs.values():
		WorkerThreadPool.wait_for_task_completion(int(job["task"]))
		var work: RasterWork = job["work"]
		_background_counters["drained"] = int(_background_counters["drained"]) + 1
		_background_counters["worker_elapsed_us"] = int(_background_counters["worker_elapsed_us"]) + work.elapsed_us
		_background_counters["worker_latest_us"] = work.elapsed_us
		_background_counters["worker_peak_us"] = maxi(int(_background_counters["worker_peak_us"]), work.elapsed_us)
	_background_jobs.clear()

static func pump_background() -> void:
	if not _background_active: return
	var uploads: int = 0
	for key: String in _background_jobs.keys():
		var job: Dictionary = _background_jobs[key]
		if not WorkerThreadPool.is_task_completed(int(job["task"])): continue
		if uploads >= BACKGROUND_UPLOAD_LIMIT: break
		WorkerThreadPool.wait_for_task_completion(int(job["task"])) # Synchronizes result publication.
		var work: RasterWork = job["work"]
		_background_jobs.erase(key)
		_rotate_completed_requests(job, key, Time.get_ticks_usec())
		_background_counters["completed"] = int(_background_counters["completed"]) + 1
		_background_counters["worker_elapsed_us"] = int(_background_counters["worker_elapsed_us"]) + work.elapsed_us
		_background_counters["worker_latest_us"] = work.elapsed_us
		_background_counters["worker_peak_us"] = maxi(int(_background_counters["worker_peak_us"]), work.elapsed_us)
		_stats["raster_builds"] = int(_stats["raster_builds"]) + 1
		Perf.record_us("Sprite worker raster", work.elapsed_us) # Worker wall time, not main-thread slice.
		var useful: bool = false
		for request: Dictionary in _background_requests.values():
			if int(request["signature"]) == int(job["signature"]): useful = true; break
		if not useful or work.image == null:
			_background_counters["retired"] = int(_background_counters["retired"]) + 1
			continue
		var started: int = Time.get_ticks_usec()
		var texture: Texture2D = _cache.get(key)
		if texture == null:
			texture = ImageTexture.create_from_image(work.image)
			_stats["uploads"] = int(_stats["uploads"]) + 1
			Perf.record_us("Sprite upload", Time.get_ticks_usec() - started)
			_store_cached(key, texture, int(job["signature"]), work.image.get_width() * work.image.get_height() * 4)
			uploads += 1
		for id: int in _background_requests.keys():
			var request: Dictionary = _background_requests[id]
			var doll: Paperdoll = (request["doll"] as WeakRef).get_ref() as Paperdoll
			if doll == null:
				_background_requests.erase(id)
				continue
			if doll._signature_id != int(job["signature"]) or doll._revision != int(request["revision"]): continue
			# A new wound/gear image can supersede stale healthy art immediately,
			# even if animation advanced during the job. Its latest frame remains queued.
			if String(request["key"]) == key or bool(request["urgent"]):
				doll._tex = texture; doll._urgent_frame = false
				doll._request_redraw()
				if String(request["key"]) == key:
					doll._frame_pending = false
					_background_requests.erase(id)
				else: request["urgent"] = false
	# Pick oldest dirty gear/wound request first; pending slots have no copied specs.
	while _background_jobs.size() < BACKGROUND_JOB_LIMIT:
		var chosen: Dictionary = {}
		for id: int in _background_requests.keys():
			var request: Dictionary = _background_requests[id]
			var doll: Paperdoll = (request["doll"] as WeakRef).get_ref() as Paperdoll
			if doll == null or not doll._render_frame_enabled:
				_background_requests.erase(id)
				continue
			if _background_jobs.has(request["key"]): continue
			var already_running: bool = false
			for running: Dictionary in _background_jobs.values():
				if (running["participants"] as Dictionary).has(id) and (not bool(request["urgent"]) or int(running["signature"]) == int(request["signature"])):
					already_running = true
					break
			if already_running: continue # One normal in-flight snapshot per doll; new wounds can preempt stale art.
			if chosen.is_empty() or (bool(request["urgent"]) and not bool(chosen["urgent"])) or (bool(request["urgent"]) == bool(chosen["urgent"]) and int(request["queued_us"]) < int(chosen["queued_us"])):
				chosen = request
		if chosen.is_empty(): break
		var doll: Paperdoll = (chosen["doll"] as WeakRef).get_ref() as Paperdoll
		var work := RasterWork.new()
		work.spec = doll._spec.duplicate(true) # Snapshot only four dispatched jobs, on main thread.
		work.pose_name = String(chosen["pose"]); work.frame = int(chosen["frame"])
		var key: String = chosen["key"]
		var participants: Dictionary = {}
		for request: Dictionary in _background_requests.values():
			if String(request["key"]) == key: participants[int(request["id"])] = request["doll"]
		var task: int = WorkerThreadPool.add_task(work.execute, false, "battle sprite")
		_background_jobs[key] = {"task": task, "work": work, "signature": chosen["signature"], "participants": participants}
		_background_counters["dispatched"] = int(_background_counters["dispatched"]) + 1
		for request: Dictionary in _background_requests.values():
			if int(request["id"]) != int(chosen["id"]) and String(request["key"]) == key: _background_counters["coalesced"] = int(_background_counters["coalesced"]) + 1
		_background_counters["inflight_peak"] = maxi(int(_background_counters["inflight_peak"]), _background_jobs.size())

## A serviced actor retaining a newer frame rejoins its priority group's tail.
## Do not penalize a different wound identity that this completed job never served.
static func _rotate_completed_requests(job: Dictionary, completed_key: String, completed_us: int) -> void:
	for id: int in job["participants"]:
		var request: Dictionary = _background_requests.get(id, {})
		if not request.is_empty() and int(request["signature"]) == int(job["signature"]) and String(request["key"]) != completed_key:
			request["queued_us"] = completed_us

static func background_stats() -> Dictionary:
	var out: Dictionary = _background_counters.duplicate()
	out["active"] = _background_active; out["pending"] = _background_requests.size()
	out["inflight"] = _background_jobs.size(); out["job_limit"] = BACKGROUND_JOB_LIMIT
	out["request_limit"] = BACKGROUND_REQUEST_LIMIT; out["upload_limit"] = BACKGROUND_UPLOAD_LIMIT
	out["queue_peak"] = out["pending_peak"]
	out["finished_discarded"] = out["retired"]
	out["finished"] = int(out["completed"]) + int(out["drained"])
	out["timing_scope"] = "Worker raster wall time; texture upload and pump execute on the main thread."
	return out

## Exact identity comparisons happen once per spec rebuild, never per pose frame.
## A bounded FIFO index interns signatures; retiring an index entry can cause an
## extra miss after a future rebuild, but cannot alias existing frame identities.
static func _signature_for(hash_value: int, spec_bytes: PackedByteArray) -> int:
	var bucket: Dictionary = _signature_buckets.get(hash_value, {})
	for token: int in bucket:
		if bucket[token] == spec_bytes:
			_stats["signature_hits"] = int(_stats["signature_hits"]) + 1
			return token
		_stats["collision_checks"] = int(_stats["collision_checks"]) + 1
	_stats["signature_misses"] = int(_stats["signature_misses"]) + 1
	if _signature_slots.size() == SIGNATURE_LIMIT:
		var retired: Dictionary = _signature_slots[_signature_cursor]
		var old_bucket: Dictionary = _signature_buckets[retired["hash"]]
		_signature_bytes -= int(retired["bytes"])
		old_bucket.erase(retired["id"])
		if old_bucket.is_empty(): _signature_buckets.erase(retired["hash"])
		_stats["signature_evictions"] = int(_stats["signature_evictions"]) + 1
	var new_token: int = _next_signature
	_next_signature += 1
	bucket = _signature_buckets.get(hash_value, {})
	bucket[new_token] = spec_bytes
	_signature_buckets[hash_value] = bucket
	var slot: Dictionary = {"hash": hash_value, "id": new_token, "bytes": spec_bytes.size()}
	if _signature_slots.size() < SIGNATURE_LIMIT: _signature_slots.append(slot)
	else: _signature_slots[_signature_cursor] = slot
	_signature_cursor = (_signature_cursor + 1) % SIGNATURE_LIMIT
	_signature_bytes += spec_bytes.size()
	return new_token

## Inherited diagnostic tests replace _cache directly. This rare reconciliation
## discards unverified restored entries; normal runtime keeps matching maps.
static func _reconcile_external_cache() -> void:
	for key: String in _cache_meta.keys():
		if not _cache.has(key) or int(_cache_meta[key]["texture_id"]) != (_cache[key] as Texture2D).get_instance_id():
			_remove_cached(key, false)
	for key: String in _cache.keys():
		if not _cache_meta.has(key): _cache.erase(key)

## Intrusive LRU links keep hits and single-entry eviction O(1), without queues
## that grow with accesses. Current doll references outlive cache eviction.
static func _unlink(key: String) -> void:
	var meta: Dictionary = _cache_meta[key]
	var before: String = meta["prev"]
	var after: String = meta["next"]
	if before != "": _cache_meta[before]["next"] = after
	else: _oldest = after
	if after != "": _cache_meta[after]["prev"] = before
	else: _newest = before

static func _touch(key: String) -> void:
	if not _cache_meta.has(key) or key == _newest: return
	_unlink(key)
	_cache_meta[key]["prev"] = _newest; _cache_meta[key]["next"] = ""
	if _newest != "": _cache_meta[_newest]["next"] = key
	else: _oldest = key
	_newest = key

static func _remove_cached(key: String, eviction: bool) -> void:
	if _cache_meta.has(key):
		_unlink(key)
		_cache_bytes -= int(_cache_meta[key]["bytes"])
		_cache_meta.erase(key)
	_cache.erase(key)
	if eviction: _stats["evictions"] = int(_stats["evictions"]) + 1

static func _store_cached(key: String, texture: Texture2D, signature_id: int, payload_bytes: int) -> void:
	if _cache.size() != _cache_meta.size(): _reconcile_external_cache()
	if payload_bytes > CACHE_BYTE_LIMIT:
		_stats["oversize_frames"] = int(_stats["oversize_frames"]) + 1
		return # The current doll still holds the frame; one oversize entry cannot purge peers.
	var started: int = Time.get_ticks_usec()
	var evicted: bool = false
	if _cache.has(key): _remove_cached(key, false)
	while _oldest != "" and (_cache.size() >= CACHE_LIMIT or _cache_bytes + payload_bytes > CACHE_BYTE_LIMIT):
		_remove_cached(_oldest, true)
		evicted = true
	if evicted: Perf.record_us("Sprite eviction", Time.get_ticks_usec() - started)
	_cache[key] = texture
	_cache_meta[key] = {"prev": _newest, "next": "", "bytes": payload_bytes,
		"signature_id": signature_id, "texture_id": texture.get_instance_id()}
	if _newest != "": _cache_meta[_newest]["next"] = key
	else: _oldest = key
	_newest = key
	_cache_bytes += payload_bytes
	_stats["peak_entries"] = maxi(int(_stats["peak_entries"]), _cache.size())
	_stats["peak_bytes"] = maxi(int(_stats["peak_bytes"]), _cache_bytes)

static func cache_stats() -> Dictionary:
	var out: Dictionary = _stats.duplicate()
	out["entries"] = _cache.size(); out["payload_bytes"] = _cache_bytes
	out["entry_limit"] = CACHE_LIMIT; out["byte_limit"] = CACHE_BYTE_LIMIT
	out["signature_entries"] = _signature_slots.size(); out["signature_limit"] = SIGNATURE_LIMIT
	out["signature_bytes"] = _signature_bytes
	out["background"] = background_stats()
	out["payload_scope"] = "Cached RGBA textures only; active dolls can retain evicted frames. Resource overhead is excluded."
	return out

## The current frame as an Image (logical pixels; feet at FigurePainter.dims(race).anchor).
func build_image() -> Image:
	var sp := current_spec()
	return FigurePainter.render(sp, pose, FigurePainter.frame_t(pose, FigurePainter.frame_index(pose, progress)))

## A static ground decal of a lost body part (head with hair + helm, arm, forearm, hand, leg,
## shin, foot) in the unit's own skin/clothes, lying in a small blood splat. Origin = centre of
## the piece; drawn at the same 2x pixel scale as the doll. Battle spawns it at the unit's tile on
## a "sever" event. Unknown part ids give just the splat.
static func make_severed_piece(u: Unit, part_id: String) -> Node2D:
	var s := Sprite2D.new()
	s.name = "Severed_" + part_id
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if u != null:
		var sp := FigurePainter.spec_for_unit(u)
		# draw the piece itself even though the unit has now lost it
		var lost: Array = (sp.get("lost", []) as Array).duplicate()
		lost.erase(part_id)
		sp["lost"] = lost
		sp["dmg"] = {}
		s.texture = ImageTexture.create_from_image(FigurePainter.render_piece(sp, part_id))
	var display := FigurePainter.display_scale(u.race if u != null else "human")
	s.scale = Vector2(display, display)
	return s

static func clear_cache() -> void:
	end_background()
	_cache.clear()
	_cache_meta.clear(); _cache_bytes = 0; _oldest = ""; _newest = ""
	_signature_buckets.clear(); _signature_slots.clear(); _signature_cursor = 0; _signature_bytes = 0
	for key: String in _stats: _stats[key] = 0

func _draw() -> void:
	if not _render_frame_enabled: return
	if _dirty or _frame_pending or _tex == null:
		_update_tex()
	if _tex == null:
		return
	var mod := Color.WHITE
	if pose == "hit" and progress < 0.5:
		mod = Color(1.0, 0.62, 0.62)
	var display := FigurePainter.display_scale(String(_spec.get("race", "human")))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(display * facing, display))
	draw_texture(_tex, -_anchor, mod)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
