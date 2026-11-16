class_name SaveSnapshot
extends RefCounted
## One consistent plain snapshot. The caller holds campaign mutation while slicing.
## Jobs and native references are released before the writer receives the plain tree.
var data: Dictionary = {}
var _jobs: Array = []
var _records: Dictionary = {}
var slices := 0
var total_us := 0
var worst_us := 0
var unit_records := 0
var item_records := 0
var reused_records := 0
var begin_us := 0

func begin(game) -> void:
	var started := Time.get_ticks_usec()
	# v0.100: schema 2 carries exact native types and runtime state; schema 1 still migrates.
	data = {"version":game.SAVE_VERSION,"militia_cap":1,"seed":game.seed_value,"day":game.day,"gold":game.gold,"next_unit_uid":Unit._next_uid,
		"company":[],"stash":[],"squads":game._keys_to_str(game.squads).duplicate(true),
		"rep":game.rep.duplicate(true),"location":game.location,"provisions":Food.stock_to_save(game),
		"rations":game.rations.duplicate(true),"food_clock":game.food_clock.duplicate(true),
		"rng_state":str(game.rng.state),   # v0.074: a reload continues the same musters and battle seeds
		"next_item_uid":Item._next_uid}   # v0.074: new pieces after a reload get the uids they would have had
	# Preserve top-level field and native iteration order, including untagged roster records.
	# v0.100: crop indices and their validity bit are simulation state. Clearing can
	# leave stale indices with unchanged crop_count; keep them until the usual rebuild.
	data["world"] = _container(game.world)
	data["contract"] = _container(game.contract)
	# v0.100: live off-screen battles and conservation totals belong to this same capture.
	data["raid_state"] = HerdRaids.save_state()
	data["gold_gone"] = TownEcon.gold_gone
	data["goods_lost"] = _container(TownEcon.goods_lost)
	data["war_runtime"] = WarAI.save_runtime(game.world) # v0.100: preserve the aged hunt grid too.
	_jobs.append({"input":game.stash,"output":data["stash"],"index":0,"roster":true,"n":-1})
	_jobs.append({"input":game.company,"output":data["company"],"index":0,"roster":true,"n":-1})
	begin_us = Time.get_ticks_usec()-started
	total_us = begin_us
	worst_us = begin_us

func _record(object: Object) -> Dictionary:
	var id := object.get_instance_id()
	if _records.has(id):
		reused_records += 1
		return _records[id]
	# to_dict() already returns a detached tree. A second duplicate(true) walked every body again.
	var record: Dictionary = object.to_dict()
	_records[id] = record
	if object is Unit: unit_records += 1
	else: item_records += 1
	return record

func _container(value):
	if value is Dictionary:
		var copy: Dictionary = {} if value.is_typed() else value.duplicate()
		var keys: Array = value.keys()
		_jobs.append({"input":value,"output":copy,"keys":keys,"index":0,"n":keys.size()})
		return copy
	var copy: Array = []
	if value.is_typed() and value.get_typed_builtin() <= TYPE_STRING:
		copy.assign(value)
		return copy
	if not value.is_typed(): copy = value.duplicate()
	else: copy.resize(value.size())
	_jobs.append({"input":value,"output":copy,"index":0,"n":copy.size()})
	return copy

func _value(value):
	match typeof(value):
		TYPE_DICTIONARY, TYPE_ARRAY: return _container(value)
		TYPE_OBJECT:
			if value is Unit: return {"__unit":_record(value)}
			if value is Item: return {"__item":_record(value)}
		TYPE_VECTOR2: return {"__v2":[value.x,value.y]}
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return value.duplicate()
	return value

func step(budget_us: int) -> bool:
	var started := Time.get_ticks_usec()
	var iterations := 0
	while not _jobs.is_empty():
		# v0.100: batch each container in local variables to avoid per-element job dictionary and is_typed lookups.
		var job: Dictionary = _jobs.pop_back()
		var source = job["input"]
		var index: int = job["index"]
		# v0.100: a container walks the size it had when its copy began (n), never past it. Rosters (n -1) are live.
		var size: int = job["n"]
		if size < 0: size = source.size()
		var paused := false
		if job.get("roster", false):
			var roster_out: Array = job["output"]
			while index < size:
				roster_out.append(_record(source[index]))
				index += 1
				iterations += 1
				if index < size and budget_us > 0 and iterations % 32 == 0 and Time.get_ticks_usec() - started >= budget_us:
					job["index"] = index
					_jobs.append(job)
					paused = true
					break
		elif source is Dictionary:
			var dict_src: Dictionary = source
			var dict_out: Dictionary = job["output"]
			var keys: Array = job["keys"]
			var is_typed: bool = dict_src.is_typed()
			while index < size:
				var key = keys[index]
				index += 1
				var value = dict_src.get(key, null)   # one lookup; a missing key reads as null
				# v0.100: inspect the type before treating a foreign/native value as missing.
				if typeof(value) == TYPE_NIL and not dict_src.has(key):   # removed after the copy began
					dict_out.erase(key)
					_note_changed(job)
					continue
				# Shallow-copy scalar values natively; replace only complex values.
				if typeof(value) > TYPE_STRING or is_typed: dict_out[key] = _value(value)
				iterations += 1
				if index < size and budget_us > 0 and iterations % 32 == 0 and Time.get_ticks_usec() - started >= budget_us:
					job["index"] = index
					job["sliced"] = true
					_jobs.append(job)
					paused = true
					break
		else:
			var arr_src: Array = source
			var arr_out: Array = job["output"]
			var is_typed: bool = arr_src.is_typed()
			while index < size:
				if index >= arr_src.size():   # the list shrank after its copy began: stop here, _finish_job trims it
					index = size
					break
				var value = arr_src[index]
				if typeof(value) > TYPE_STRING or is_typed: arr_out[index] = _value(value)
				index += 1
				iterations += 1
				if index < size and budget_us > 0 and iterations % 32 == 0 and Time.get_ticks_usec() - started >= budget_us:
					job["index"] = index
					job["sliced"] = true
					_jobs.append(job)
					paused = true
					break
		if paused: break
		_finish_job(job, size)
		if budget_us > 0 and iterations >= 32 and Time.get_ticks_usec() - started >= budget_us: break
	var elapsed := Time.get_ticks_usec()-started
	slices += 1; total_us += elapsed; worst_us = maxi(worst_us,elapsed)
	if _jobs.is_empty():
		_records.clear()
		return true
	return false

## Campaign code must not change the world while a capture is under way (Game holds time and input meanwhile).
## A change found here is a bug in its caller; the copy stays readable and the warning names the keys.
var changed_during_capture := 0

## End of one container's copy (v0.100 review). A list that shrank loses its removed tail; a key removed after it was
## copied is dropped even when another key was added and the size came out the same.
func _finish_job(job: Dictionary, size: int) -> void:
	if job.get("roster", false): return
	var source = job["input"]
	if not job.has("keys"):
		if source.size() < size:
			(job["output"] as Array).resize(source.size())
		if source.size() != size: _note_changed(job)
		return
	var changed: bool = source.size() != size
	if changed or job.get("sliced", false):   # v0.100: unsliced containers cannot lose keys after their own pass
		for key in job["keys"]:
			if not source.has(key) and (job["output"] as Dictionary).has(key):
				(job["output"] as Dictionary).erase(key)
				changed = true
	if changed: _note_changed(job)

func _note_changed(job: Dictionary) -> void:
	changed_during_capture += 1
	if not job.has("keys"):
		push_warning("Save snapshot: a list changed size while it was being copied (%d entries, now %d)." % [(job["output"] as Array).size(), (job["input"] as Array).size()])
		return
	var had: Array = job["keys"]
	var added := []
	for k in (job["input"] as Dictionary).keys():
		if not had.has(k): added.append(k)
	push_warning("Save snapshot: a dictionary changed while it was being copied (added %s, had %d keys, now %d)." % [str(added.slice(0, 8)), had.size(), (job["input"] as Dictionary).size()])

func take() -> Dictionary:
	assert(_jobs.is_empty())
	var result := data
	data = {}
	return result
