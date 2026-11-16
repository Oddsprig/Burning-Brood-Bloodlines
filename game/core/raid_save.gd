extends RefCounted
## v0.100: a raid is a live object graph, not another BattleSim.setup(). Preserve
## Fighter/Unit/Item identities, wound-layer aliases, RNG, packed grids and caches.
## Only plain Variant bytes are decoded; saves cannot instantiate arbitrary scripts.
var _values: Array = []
var _nodes: Array = []
var _buckets: Dictionary = {}
var _units: Dictionary = {}
var _items: Dictionary = {}
var _failed := false
const DB_TABLES := ["materials", "bodies", "races", "factions", "weapons", "armor", "bows", "arrows", "arrow_shapes"]
var _sources: Dictionary = {}

func capture(value: Dictionary) -> String:
	# v0.100: caches must reconnect to the shared definitions used by future cache
	# misses, or a resave would duplicate what used to be the same attack/material.
	var active: Variant = value.get("fights", {})
	# v0.100: a foreign fights value must refuse capture, never call through a failed cast.
	if typeof(active) != TYPE_DICTIONARY: return ""
	if not active.is_empty():
		for table in DB_TABLES: _source(DB.get(table), [table])
		_source(Formulas.NATURAL, ["$natural"])
		for race in NaturalAttacks._cache: _source(NaturalAttacks._cache[race], ["$creature", race])
	var root := _encode(value)
	if _failed: return ""
	return Marshalls.raw_to_base64(var_to_bytes({"root": root, "nodes": _nodes}))

func _encode(value: Variant) -> Array:
	if not (value is Object or value is Dictionary or value is Array): return [0, value]
	var code := hash(value)
	if value is Dictionary or value is Array:
		for source in _sources.get(code, []):
			if is_same(value, source[0]): return [2, source[1]]
	for prior in _buckets.get(code, []):
		if is_same(value, _values[int(prior)]): return [1, int(prior)]
	var index := _nodes.size()
	_values.append(value)
	_nodes.append({})
	if not _buckets.has(code): _buckets[code] = []
	_buckets[code].append(index)
	var node := {"kind": "", "rows": []}
	_nodes[index] = node
	var rows: Array = node["rows"]
	if value is Dictionary:
		node["kind"] = "dict"
		for key in value: rows.append([_encode(key), _encode(value[key])])
	elif value is Array:
		node["kind"] = "array"
		for child in value: rows.append(_encode(child))
	elif value is RandomNumberGenerator:
		node["kind"] = "rng"
		node["seed"] = value.seed
		node["state"] = value.state
	else:
		var kind := ""
		if value is BattleSim: kind = "sim"
		elif value is Fighter: kind = "fighter"
		elif value is Unit: kind = "unit"
		elif value is Item: kind = "item"
		elif value is BodyState: kind = "body"
		if kind == "":
			_failed = true
			push_error("v0.100: unsupported object in live raid save")
			return [0, null]
		node["kind"] = kind
		for property in value.get_property_list():
			if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
			var name := String(property["name"])
			# Process-wide statics are not instance state (UID counters live in the save root).
			if name in ["_next_uid", "_plans"]: continue
			rows.append([name, _encode(value.get(name))])
	return [1, index]

# v0.100: index definition containers by identity, checking native hash collisions.
func _source(value: Variant, path: Array) -> void:
	if not (value is Dictionary or value is Array): return
	var code := hash(value)
	for prior in _sources.get(code, []):
		if is_same(value, prior[0]): return
	if not _sources.has(code): _sources[code] = []
	_sources[code].append([value, path.duplicate()])
	var keys: Array = value.keys() if value is Dictionary else range(value.size())
	for key in keys:
		path.push_back(key)
		_source(value[key], path)
		path.pop_back()

func restore(text: String) -> Variant:
	var graph = bytes_to_var(Marshalls.base64_to_raw(text))
	if not (graph is Dictionary) or not (graph.get("nodes") is Array) or not (graph.get("root") is Array): return null
	_nodes = graph["nodes"]
	for node in _nodes:
		if not (node is Dictionary) or not (node.get("rows") is Array) or not (node.get("kind") is String): return null
		match node["kind"]:
			"dict": _values.append({})
			"array": _values.append([])
			"rng": _values.append(RandomNumberGenerator.new())
			"sim": _values.append(BattleSim.new())
			"fighter": _values.append(Fighter.new())
			"unit": _values.append(Unit.new())
			"item": _values.append(Item.new())
			"body": _values.append(BodyState.new())
			_: return null
	# All seats exist before any reference is connected, including forward aliases.
	for i in _nodes.size():
		var node: Dictionary = _nodes[i]
		var value = _values[i]
		if value is Dictionary:
			for pair in node["rows"]:
				# v0.100: truncated/foreign rows are rejected before indexing or assigning.
				if not (pair is Array) or pair.size() != 2: return null
				var key = _decode(pair[0])
				var child = _decode(pair[1])
				if _failed: return null
				value[key] = child
		elif value is Array:
			for ref in node["rows"]:
				var child = _decode(ref)
				if _failed: return null
				value.append(child)
	for i in _nodes.size():
		var node: Dictionary = _nodes[i]
		var value = _values[i]
		if value is RandomNumberGenerator:
			# v0.100: the native writer stores integers; never cast null/containers.
			if not (node.get("seed") is int) or not (node.get("state") is int): return null
			value.seed = node["seed"]
			value.state = node["state"]
		elif value is Object:
			var fields := {}
			for property in value.get_property_list():
				if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
				var name := String(property["name"])
				if name not in ["_next_uid", "_plans"]: fields[name] = property
			for pair in node["rows"]:
				if not (pair is Array) or pair.size() != 2 or not (pair[0] is String) or not fields.has(pair[0]): return null
				var child = _decode(pair[1])
				if _failed or not _property_ok(fields[pair[0]], child): return null
				value.set(pair[0], child)
			if value is Unit: _units[value.uid] = value
			elif value is Item: _items[value.uid] = value
	return null if _failed else _decode(graph["root"])

func _decode(ref: Variant) -> Variant:
	# v0.100: graph tags/indexes are native integers, not values to coerce with int().
	if ref is Array and ref.size() == 2 and ref[0] is int:
		if ref[0] == 0 and not (ref[1] is Object or ref[1] is Dictionary or ref[1] is Array): return ref[1]
		if ref[0] == 2 and ref[1] is Array: return _definition(ref[1])
		if ref[0] == 1 and ref[1] is int and ref[1] >= 0 and ref[1] < _values.size(): return _values[ref[1]]
	_failed = true
	return null

# v0.100: Object.set must not cast corrupt values or write process-wide statics.
func _property_ok(property: Dictionary, value: Variant) -> bool:
	var expected: int = property["type"]
	if expected == TYPE_NIL: return true
	if expected == TYPE_OBJECT:
		if typeof(value) == TYPE_NIL: return true # v0.100: do not compare foreign types to null.
		match String(property.get("class_name", "")):
			"Unit": return value is Unit
			"Item": return value is Item
			"BodyState": return value is BodyState
			"BattleSim": return value is BattleSim
			"Fighter": return value is Fighter
			"RandomNumberGenerator": return value is RandomNumberGenerator
			"RefCounted": return value is RefCounted
			"", "Object": return value is Object
			_: return false
	return typeof(value) == expected or (expected == TYPE_FLOAT and value is int)

func _definition(path: Array) -> Variant:
	if path.is_empty() or not (path[0] is String):
		_failed = true
		return null
	var value: Variant = null
	var start := 1
	if path[0] in DB_TABLES: value = DB.get(path[0])
	elif path[0] == "$natural": value = Formulas.NATURAL
	elif path[0] == "$creature" and path.size() > 1 and path[1] is String and DB.races.has(path[1]):
		value = NaturalAttacks._table(path[1], DB.races[path[1]])
		start = 2
	for i in range(start, path.size()):
		if value is Dictionary and value.has(path[i]): value = value[path[i]]
		elif value is Array and path[i] is int and int(path[i]) >= 0 and int(path[i]) < value.size(): value = value[int(path[i])]
		else:
			_failed = true
			return null
	if typeof(value) == TYPE_NIL: _failed = true # v0.100: a failed definition has no native type.
	return value

## v0.100: campaign rosters and the raid must mutate the very same native bodies
## and equipment. Raw raid Units also retain battle-only food attribute caches.
func link_campaign(game) -> void:
	if _units.is_empty() and _items.is_empty(): return # v0.100: no extra world walk when no raid is live.
	_link(game.world)
	_link(game.company)
	_link(game.stash)
	_link(game.contract)

func _link(value: Variant) -> Variant:
	if value is Unit:
		if _units.has(value.uid): return _units[value.uid]
		value.horse = _link(value.horse)
		_link(value.equip)
	elif value is Item:
		return _items.get(value.uid, value)
	elif value is Dictionary:
		for key in value:
			var child = value[key]
			if child is Object or child is Array or child is Dictionary: value[key] = _link(child)
	elif value is Array:
		for i in value.size():
			var child = value[i]
			if child is Object or child is Array or child is Dictionary: value[i] = _link(child)
	return value
