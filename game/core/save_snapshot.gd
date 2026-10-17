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
	data = {"version":1,"seed":game.seed_value,"day":game.day,"gold":game.gold,"next_unit_uid":Unit._next_uid,
		"company":[],"stash":[],"squads":game._keys_to_str(game.squads).duplicate(true),
		"rep":game.rep.duplicate(true),"location":game.location,"provisions":Food.stock_to_save(game),
		"rations":game.rations.duplicate(true),"food_clock":game.food_clock.duplicate(true)}
	# Preserve top-level field and native iteration order, including untagged roster records.
	data["world"] = _container(game.world)
	data["contract"] = _container(game.contract)
	_jobs.append({"input":game.stash,"output":data["stash"],"index":0,"roster":true})
	_jobs.append({"input":game.company,"output":data["company"],"index":0,"roster":true})
	begin_us = Time.get_ticks_usec()-started
	total_us = begin_us
	worst_us = begin_us

func _record(object: Object) -> Dictionary:
	var id := object.get_instance_id()
	if _records.has(id):
		reused_records += 1
		return _records[id]
	var record: Dictionary = object.to_dict().duplicate(true)
	_records[id] = record
	if object is Unit: unit_records += 1
	else: item_records += 1
	return record

func _container(value):
	if value is Dictionary:
		var copy: Dictionary = {} if value.is_typed() else value.duplicate()
		_jobs.append({"input":value,"output":copy,"keys":value.keys(),"index":0})
		return copy
	var copy: Array = []
	if value.is_typed() and value.get_typed_builtin() <= TYPE_STRING:
		copy.assign(value)
		return copy
	if not value.is_typed(): copy = value.duplicate()
	else: copy.resize(value.size())
	_jobs.append({"input":value,"output":copy,"index":0})
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
		var job: Dictionary = _jobs[-1]
		var source = job["input"]
		var index: int = job["index"]
		if index >= source.size():
			_jobs.pop_back()
			continue
		job["index"] = index + 1
		if job.get("roster",false):
			job["output"].append(_record(source[index]))
		elif source is Dictionary:
			var key = job["keys"][index]
			var value = source[key]
			# Shallow-copy scalar values natively; replace only complex values.
			if source.is_typed() or typeof(value) > TYPE_STRING: job["output"][key] = _value(value)
		else:
			var value = source[index]
			if source.is_typed() or typeof(value) > TYPE_STRING: job["output"][index] = _value(value)
		iterations += 1
		if budget_us > 0 and iterations % 32 == 0 and Time.get_ticks_usec()-started >= budget_us: break
	var elapsed := Time.get_ticks_usec()-started
	slices += 1; total_us += elapsed; worst_us = maxi(worst_us,elapsed)
	if _jobs.is_empty():
		_records.clear()
		return true
	return false

func take() -> Dictionary:
	assert(_jobs.is_empty())
	var result := data
	data = {}
	return result
