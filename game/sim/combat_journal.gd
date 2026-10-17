class_name CombatJournal
extends RefCounted
## Detached native outcomes for one battle. No Unit/Fighter/sim ownership.
## History and participant sequence links spill to a private transient folder.
const PRIVATE_ROOT := "user://combat_journal"
const CHUNK_SIZE := 256
const CACHE_CHUNKS := 3
const MAX_PAGE_SIZE := 64
static var _serial: int = 0

var _directory: String = ""
var _participants: Dictionary = {}
var _active: Array = []
var _cache: Dictionary = {}
var _cache_bytes: Dictionary = {}
var _lru: Array = []
var _index_handles: Dictionary = {}
var _index_dirty: Dictionary = {}
var _index_ids: Dictionary = {}
var _prefix_counts: Dictionary = {}
var _attempted: int = 0
var _stored_records: int = 0
var _chunk_count: int = 0
var _stored_bytes: int = 0
var _index_bytes: int = 0
var _reads: int = 0
var _writes: int = 0
var _index_flushes: int = 0
var _faulted: bool = false
var _disk_readable: bool = true
var _disposed: bool = false
var _setup: bool = false
var _errors: Array = []
var _disposed_dropped: int = 0

func _init() -> void:
	_serial += 1
	_directory = "%s/%d_%d_%d" % [PRIVATE_ROOT, OS.get_process_id(), Time.get_ticks_usec(), _serial]
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_directory)) or FileAccess.file_exists(_directory):
		_serial += 1
		_directory = "%s/%d_%d_%d" % [PRIVATE_ROOT, OS.get_process_id(), Time.get_ticks_usec(), _serial]

func setup(participants: Array) -> void:
	if _disposed or _setup:
		_fail("Participant registration attempted after setup/disposal.")
		return
	_setup = true
	for value in participants:
		if not value is Dictionary:
			_fail("Participant metadata is not plain registered data.")
			continue
		var idx: int = int(value.get("idx", -1))
		if idx < 0 or _participants.has(idx):
			_fail("Participant index is missing or repeated.")
			continue
		_participants[idx] = {"idx": idx, "name": str(value.get("name", "")),
			"side": int(value.get("side", -1)), "unit_uid": int(value.get("unit_uid", -1))}
		# Optional actual dragon identity is detached metadata, not a second journal.
		for field in ["dragon_uid", "rider_person_uid"]:
			if str(value.get(field, "")) != "": _participants[idx][field] = str(value[field])

func participants() -> Array:
	return _participants.values().duplicate(true)

func participant(idx: int) -> Dictionary:
	return (_participants.get(idx, {}) as Dictionary).duplicate(true)

func append(entry: Dictionary, actor: int, target: int, event_type: String = "") -> bool:
	if _disposed: return false
	var seq: int = _attempted
	_attempted += 1
	var validation: Dictionary = {"ok": true}
	var frozen: Variant = _freeze(entry, validation)
	if not validation["ok"]:
		_fail("Native history payload contains an Object, callable, signal or excessive nesting; that entry was not recorded.")
		return false
	if not _setup or (actor >= 0 and not _participants.has(actor)) or (target >= 0 and not _participants.has(target)):
		_fail("An outcome refers to an unregistered participant; only the bounded recent history is available.")
	var row: Dictionary = {"seq": seq, "tick": int(entry.get("tick", 0)), "actor": actor,
		"target": target, "event_type": event_type, "entry": frozen}
	# On failure retain recent actual outcomes, explicitly report every lost entry.
	if _active.size() >= CHUNK_SIZE: _active.pop_front()
	_active.append(row)
	if not _faulted and _active.size() >= CHUNK_SIZE: _spill()
	return true

func count(participant_idx: int = -1) -> int:
	if _disposed: return 0
	var prefix: int = _stored_records if participant_idx < 0 else int(_prefix_counts.get(participant_idx, 0))
	if not _disk_readable: prefix = 0
	if participant_idx < 0: return prefix + _active.size()
	for row: Dictionary in _active:
		if row["actor"] == participant_idx or row["target"] == participant_idx: prefix += 1
	return prefix

func page(page_index: int, participant_idx: int = -1, page_size: int = 18) -> Array:
	var output: Array = []
	if _disposed or page_index < 0: return output
	var size: int = clampi(page_size, 1, MAX_PAGE_SIZE)
	var start: int = page_index * size
	var total: int = count(participant_idx)
	if start >= total: return output
	var prefix: int = _stored_records if participant_idx < 0 else int(_prefix_counts.get(participant_idx, 0))
	if not _disk_readable: prefix = 0
	var needed: int = mini(size, total - start)
	var sequence: PackedInt64Array = PackedInt64Array()
	var disk_n: int = mini(needed, maxi(0, prefix - start))
	if participant_idx < 0:
		for i in disk_n: sequence.append(start + i)
	elif disk_n > 0:
		if not _flush_index(participant_idx): return output
		var file: FileAccess = FileAccess.open(_index_path(participant_idx), FileAccess.READ)
		if file == null:
			_read_failed("Participant history index cannot be opened.")
			return output
		file.seek(start * 8)
		for i in disk_n: sequence.append(file.get_64())
		var error: int = file.get_error()
		file.close()
		if error != OK:
			_read_failed("Participant history index could not be read completely.")
			return output
	for seq in sequence:
		if seq < 0 or seq >= _stored_records:
			_read_failed("Participant history index contains an unavailable sequence.")
			return []
		var chunk: Array = _chunk(int(seq / CHUNK_SIZE))
		if chunk.is_empty(): return []
		var record: Dictionary = chunk[int(seq % CHUNK_SIZE)]
		var validation: Dictionary = {"ok": true}
		output.append(_freeze(record, validation))
	# Active/failure tail is at most256 records. No whole-history scan or read.
	var tail_start: int = maxi(0, start - prefix)
	var tail_index: int = 0
	for record: Dictionary in _active:
		if participant_idx >= 0 and record["actor"] != participant_idx and record["target"] != participant_idx: continue
		if tail_index >= tail_start and output.size() < needed:
			var validation: Dictionary = {"ok": true}
			output.append(_freeze(record, validation))
		tail_index += 1
		if output.size() >= needed: break
	return output

func stats() -> Dictionary:
	var cached_records: int = 0
	var cached_bytes: int = 0
	for id in _cache:
		cached_records += (_cache[id] as Array).size()
		cached_bytes += int(_cache_bytes.get(id, 0))
	var retained: int = count()
	return {"complete": _setup and not _faulted and not _disposed, "error": str(_errors[-1]) if not _errors.is_empty() else "",
		"errors": _errors.duplicate(), "attempted": _attempted, "records": retained,
		"dropped": _disposed_dropped if _disposed else maxi(0, _attempted - retained),
		"spilled_records": _stored_records, "active_records": _active.size(),
		"cached_chunks": _cache.size(), "cached_records": cached_records, "cached_payload_bytes": cached_bytes,
		"chunk_files": _chunk_count, "stored_bytes": _stored_bytes, "index_bytes": _index_bytes,
		"chunk_size": CHUNK_SIZE, "cache_limit": CACHE_CHUNKS, "disk_bytes": 0 if _disposed else _stored_bytes + _index_bytes,
		"index_links": int(_index_bytes / 8), "open_index_files": _index_handles.size(),
		"buffered_indexes": _index_dirty.size(), "index_flushes": _index_flushes,
		"memory_record_limit": (CACHE_CHUNKS + 1) * CHUNK_SIZE, "reads": _reads, "writes": _writes,
		"disposed": _disposed, "directory": _directory}

func _spill() -> void:
	if not _private_directory():
		_fail("Battle history storage path is outside its private folder.")
		return
	var error: int = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory))
	if error != OK:
		_fail("Battle history folder cannot be created (error %d)." % error)
		return
	var path: String = _chunk_path(_chunk_count)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Battle history chunk cannot be opened (error %d)." % FileAccess.get_open_error())
		return
	file.store_var(_active, false)
	file.flush()
	error = file.get_error()
	var bytes: int = file.get_position()
	file.close()
	if error != OK:
		_remove_file(path)
		_fail("Battle history chunk could not be written (error %d)." % error)
		return
	_chunk_count += 1; _stored_records += _active.size(); _stored_bytes += bytes; _writes += 1
	if not _write_links(): return
	_active.clear()

func _write_links() -> bool:
	# Fixed-width disk indexes keep RAM independent of battle duration.
	var pending: Dictionary = {}
	for row: Dictionary in _active:
		var links: Array = [row["actor"]]
		if row["target"] != row["actor"]: links.append(row["target"])
		for idx: int in links:
			if idx < 0: continue
			if not pending.has(idx): pending[idx] = PackedInt64Array()
			var sequences: PackedInt64Array = pending[idx]
			sequences.append(row["seq"])
			pending[idx] = sequences
	for idx: int in pending:
		var file: FileAccess = _index_handles.get(idx)
		if file == null:
			file = FileAccess.open(_index_path(idx), FileAccess.WRITE_READ)
			if file == null:
				_read_failed("Participant history index cannot be created (error %d)." % FileAccess.get_open_error())
				return false
			_index_ids[idx] = true
			_index_handles[idx] = file
		# This private writer is never read/repositioned; seeking here would also
		# force buffered output on every touched participant at every chunk.
		var before: int = file.get_position()
		for seq in pending[idx]: file.store_64(seq)
		_index_dirty[idx] = true
		_index_bytes += maxi(0, file.get_position() - before)
		var error: int = file.get_error()
		if error != OK:
			_read_failed("Participant history index could not be written (error %d)." % error)
			return false
		_prefix_counts[idx] = int(_prefix_counts.get(idx, 0)) + (pending[idx] as PackedInt64Array).size()
	return true

func _flush_index(idx: int) -> bool:
	if not _index_dirty.has(idx): return true
	var file: FileAccess = _index_handles.get(idx)
	if file == null:
		_read_failed("Participant history index lost its buffered writer.")
		return false
	file.flush()
	_index_flushes += 1
	var error: int = file.get_error()
	if error != OK:
		_read_failed("Participant history index could not be flushed (error %d)." % error)
		return false
	_index_dirty.erase(idx)
	return true

func _chunk(id: int) -> Array:
	if _cache.has(id):
		_lru.erase(id); _lru.append(id)
		return _cache[id]
	var file: FileAccess = FileAccess.open(_chunk_path(id), FileAccess.READ)
	if file == null:
		_read_failed("Battle history chunk is unavailable (error %d)." % FileAccess.get_open_error())
		return []
	var bytes: int = file.get_length()
	var value: Variant = file.get_var(false)
	var error: int = file.get_error()
	file.close()
	_reads += 1
	if error != OK or not value is Array or value.size() != CHUNK_SIZE:
		_read_failed("Battle history chunk could not be decoded completely.")
		return []
	for i in value.size():
		if not value[i] is Dictionary or int(value[i].get("seq", -1)) != id * CHUNK_SIZE + i or not value[i].get("entry") is Dictionary:
			_read_failed("Battle history chunk has an invalid record sequence.")
			return []
	while _lru.size() >= CACHE_CHUNKS:
		var oldest: int = _lru.pop_front()
		_cache.erase(oldest); _cache_bytes.erase(oldest)
	_cache[id] = value; _cache_bytes[id] = bytes; _lru.append(id)
	return value

static func _freeze(value: Variant, validation: Dictionary, depth: int = 0) -> Variant:
	# Native recursion copies Arrays/Dictionary structure once. Objects stay refs,
	# so validate them and explicitly detach packed leaves before retaining output.
	var kind: int = typeof(value)
	var copy: Variant = value.duplicate(true) if value is Dictionary or value is Array else value.duplicate() if kind >= TYPE_PACKED_BYTE_ARRAY else value
	_detach_plain(copy, validation, depth)
	return copy if validation["ok"] else null

static func _detach_plain(value: Variant, validation: Dictionary, depth: int) -> void:
	if depth > 128 or typeof(value) in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL]:
		validation["ok"] = false
		return
	if value is Dictionary:
		for key in value:
			# Native entries overwhelmingly use primitive keys; no copy or recursive
			# function call is needed for their scalar fields.
			if typeof(key) > TYPE_STRING:
				_detach_plain(key, validation, depth + 1)
				if not validation["ok"]: return
			var child: Variant = value[key]
			var kind: int = typeof(child)
			if kind <= TYPE_STRING: continue
			if kind >= TYPE_PACKED_BYTE_ARRAY: value[key] = child.duplicate()
			else:
				_detach_plain(child, validation, depth + 1)
				if not validation["ok"]: return
	elif value is Array:
		for i in value.size():
			var child: Variant = value[i]
			var kind: int = typeof(child)
			if kind <= TYPE_STRING: continue
			if kind >= TYPE_PACKED_BYTE_ARRAY: value[i] = child.duplicate()
			else:
				_detach_plain(child, validation, depth + 1)
				if not validation["ok"]: return

func _read_failed(message: String) -> void:
	# After an unreadable disk index/chunk, expose only the known in-memory tail.
	# No optimistic complete count, costly rescue scan or corrupt object decoding.
	_disk_readable = false
	_cache.clear(); _cache_bytes.clear(); _lru.clear()
	_fail(message + " Only retained recent records can be viewed.")

func _fail(message: String) -> void:
	_faulted = true
	if _errors.is_empty() or _errors[-1] != message:
		_errors.append(message)
		if _errors.size() > 8: _errors.pop_front()

func _private_directory() -> bool:
	return _directory.begins_with(PRIVATE_ROOT + "/") and not _directory.contains("..") and not _directory.contains("\\")

func _chunk_path(id: int) -> String:
	return "%s/chunk_%08d.bin" % [_directory, id]

func _index_path(idx: int) -> String:
	return "%s/participant_%d.idx" % [_directory, idx]

func _remove_file(path: String) -> void:
	if _private_directory() and path.begins_with(_directory + "/") and FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func dispose() -> void:
	if _disposed: return
	for idx: int in _index_dirty.keys(): _flush_index(idx)
	_disposed_dropped = maxi(0, _attempted - count())
	_disposed = true
	for file: FileAccess in _index_handles.values(): file.close()
	_index_handles.clear()
	_index_dirty.clear()
	_active.clear(); _cache.clear(); _cache_bytes.clear(); _lru.clear()
	if _private_directory():
		for id in _chunk_count: _remove_file(_chunk_path(id))
		for idx in _index_ids: _remove_file(_index_path(idx))
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_directory)):
			var error: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory))
			if error != OK: _fail("Private battle history folder could not be removed (error %d)." % error)
	_participants.clear(); _prefix_counts.clear(); _index_ids.clear()

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _disposed: return
	# At RefCounted's final notification, calling an instance method through self
	# is invalid. Release only known ownership inline; normal dispose reports IO.
	_disposed = true
	for file: FileAccess in _index_handles.values(): file.close()
	_index_handles.clear()
	_index_dirty.clear()
	_active.clear(); _cache.clear(); _cache_bytes.clear(); _lru.clear()
	if not _directory.begins_with(PRIVATE_ROOT + "/") or _directory.contains("..") or _directory.contains("\\"): return
	for id in _chunk_count:
		var path: String = "%s/chunk_%08d.bin" % [_directory, id]
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for idx in _index_ids:
		var path: String = "%s/participant_%d.idx" % [_directory, idx]
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_directory))
