class_name TownSweep
extends RefCounted
## Derived indexes for one synchronous register sweep. Never stored in an economy,
## never continued across frames, and discarded before the sweep returns.
static var _scope: Dictionary = {}

static func begin(e: Dictionary) -> Dictionary:
	var previous: Dictionary = _scope
	_scope = {"econ": e, "rows": {}, "surnames": {}, "surnames_ready": false,
		"names_version": 0, "names_at": -1, "names": {}, "hiring_version": 0, "hiring_at": -1}
	return previous

## A synchronous UI read shares names/counts but needs no mutation-tracking head heaps.
static func begin_read(e: Dictionary) -> Dictionary:
	var previous: Dictionary = begin(e)
	_scope["read_only"] = true
	return previous

static func finish(previous: Dictionary) -> void:
	_scope = previous

static func head_row(f: Dictionary) -> Dictionary:
	if bool(_scope.get("read_only", false)): return {}
	return row(f)

static func active(e: Dictionary) -> bool:
	return not _scope.is_empty() and is_same(_scope["econ"], e)

# Shallow prospective households share the same register, but not their proposed
# jobs. Only register-derived data belongs here; all assignment inputs stay live.
static func row(f: Dictionary) -> Dictionary:
	if _scope.is_empty(): return {}
	var fid: int = int(f.get("id", -1))
	var fams: Array = _scope["econ"].get("fams", [])
	if fid < 0 or fid >= fams.size(): return {}
	var source: Dictionary = fams[fid]
	if not f.has("pp") or not is_same(f.get("pp"), source.get("pp")): return {}
	var rows: Dictionary = _scope["rows"]
	var cached: Dictionary = rows.get(fid, {})
	if not cached.is_empty() and is_same(cached["pp"], f["pp"]) and is_same(cached["kp"], f.get("kp")):
		return cached
	var resident: Array[int] = [0, 0, 0, 0]
	var serving: int = 0
	for role: Variant in f.get("serve", {}): serving += int(f["serve"][role])
	cached = {"pp": f["pp"], "kp": f.get("kp"), "resident": resident, "home_n": 0,
		"home": [], "home_ready": false, "home_cats": [0, 0, 0], "known": {}, "trades": {},
		"known_ready": false, "head_ready": false, "serving": serving,
		"present": {}, "spouses": {}, "records": [], "order": [], "heaps": [[], [], []]}
	rows[fid] = cached
	for roster: Array in [Persons.pp_read(f), Persons.kp_read(f)]:
		for p: Array in roster:
			if not Persons.AWAY.has(String(p[4])): resident[Population.category(p)] += 1
	for p: Array in Persons.pp_read(f):
		if _home(p): cached["home_n"] = int(cached["home_n"]) + 1
		if String(p[4]) == "": cached["home_cats"][2 if int(p[6]) == 1 else int(p[2])] += 1
	return cached

static func _home(p: Array) -> bool:
	return int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]

static func _trade_delta(cached: Dictionary, p: Array, delta: int) -> void:
	var titles: Array = []
	if p.size() > Persons.JOB and String(p[Persons.JOB]) != "":
		titles.append(String(p[Persons.JOB]).get_slice("@", 0))
	if p.size() > Persons.HIST:
		for event: Array in p[Persons.HIST]:
			if String(event[1]) == "job": titles.append(String(event[2]).get_slice("@", 0))
	for title: String in titles:
		var count: int = int(cached["trades"].get(title, 0)) + delta
		if count > 0:
			cached["trades"][title] = count
			cached["known"][title] = true
		else:
			cached["trades"].erase(title)
			cached["known"].erase(title)

static func known(cached: Dictionary) -> Dictionary:
	if not bool(cached["known_ready"]):
		for p: Array in cached["pp"]: _trade_delta(cached, p, 1)
		cached["known_ready"] = true
	return cached["known"]

static func _ensure_head(cached: Dictionary) -> void:
	if bool(cached["head_ready"]): return
	var children: Array = cached["kp"] if cached["kp"] is Array else []
	for roster: Array in [cached["pp"], children]:
		for p: Array in roster:
			var pid: int = int(p[0])
			if pid >= 0: cached["present"][pid] = int(cached["present"].get(pid, 0)) + 1
	for p: Array in cached["pp"]: _add_head_record(cached, p)
	cached["head_ready"] = true

static func _add_head_record(cached: Dictionary, p: Array) -> void:
	var ordinal: int = (cached["records"] as Array).size()
	cached["records"].append([p, true, 0])
	cached["order"].append(ordinal)
	var spouse: int = int(Persons.g(p, Persons.SP, -1))
	if not cached["spouses"].has(spouse): cached["spouses"][spouse] = []
	cached["spouses"][spouse].append(ordinal)
	_refresh_head(cached, ordinal)

# Original head selection is three ordered minimum searches, with the first
# register entry winning exact sex/birth ties. Ordinals survive removals.
static func _less(a: Array, b: Array) -> bool:
	if int(a[0]) != int(b[0]): return int(a[0]) < int(b[0])
	if float(a[1]) != float(b[1]): return float(a[1]) < float(b[1])
	return int(a[2]) < int(b[2])

static func _push(heap: Array, item: Array) -> void:
	var at: int = heap.size()
	heap.append(item)
	while at > 0:
		var parent: int = (at - 1) / 2
		if not _less(item, heap[parent]): break
		heap[at] = heap[parent]
		at = parent
	heap[at] = item

static func _pop(heap: Array) -> void:
	var tail: Array = heap.pop_back()
	if heap.is_empty(): return
	var at: int = 0
	while at * 2 + 1 < heap.size():
		var child: int = at * 2 + 1
		if child + 1 < heap.size() and _less(heap[child + 1], heap[child]): child += 1
		if not _less(heap[child], tail): break
		heap[at] = heap[child]
		at = child
	heap[at] = tail

static func _refresh_head(cached: Dictionary, ordinal: int) -> void:
	var record: Array = cached["records"][ordinal]
	record[2] = int(record[2]) + 1
	if not bool(record[1]): return
	var p: Array = record[0]
	var item: Array = [int(p[2]), float(p[3]), ordinal, int(record[2])]
	_push(cached["heaps"][2], item)
	if Persons.AWAY.has(String(p[4])) or int(p[6]) != 0: return
	_push(cached["heaps"][1], item)
	if cached["present"].has(int(Persons.g(p, Persons.SP, -1))):
		_push(cached["heaps"][0], item)

static func _winner(cached: Dictionary) -> int:
	for heap: Array in cached["heaps"]:
		while not heap.is_empty():
			var item: Array = heap[0]
			var record: Array = cached["records"][int(item[2])]
			if bool(record[1]) and int(record[2]) == int(item[3]): return int(item[2])
			_pop(heap)
	return -1

static func head(cached: Dictionary) -> Array:
	_ensure_head(cached)
	var ordinal: int = _winner(cached)
	return cached["records"][ordinal][0] if ordinal >= 0 else []

static func home_workers(cached: Dictionary) -> Array:
	if not bool(cached["home_ready"]):
		var home: Array = []
		for p: Array in cached["pp"]:
			if _home(p): home.append(p)
		home.sort_custom(func(x, y): return float(x[3]) < float(y[3]) if float(x[3]) != float(y[3]) else int(x[0]) < int(y[0]))
		cached["home"] = home
		cached["home_ready"] = true
	return (cached["home"] as Array).duplicate()

static func service_left(f: Dictionary) -> void:
	if _scope.is_empty(): return
	var cached: Dictionary = _scope["rows"].get(int(f.get("id", -1)), {})
	if not cached.is_empty() and is_same(cached["pp"], f.get("pp")):
		cached["serving"] = int(cached["serving"]) - 1

# Called immediately before the native Array.erase; its first equal row, not an
# assumed unique PID, decides which record is removed. No effects interleave.
static func removing(f: Dictionary, p: Array) -> void:
	var cached: Dictionary = row(f)
	if cached.is_empty(): return
	var at: int = (f["pp"] as Array).find(p)
	if at < 0: return
	var removed: Array = f["pp"][at]
	if bool(cached["known_ready"]): _trade_delta(cached, removed, -1)
	if String(removed[4]) == "": cached["home_cats"][2 if int(removed[6]) == 1 else int(removed[2])] -= 1
	if _home(removed):
		cached["home_n"] = int(cached["home_n"]) - 1
		cached["home_ready"] = false
	if not Persons.AWAY.has(String(removed[4])):
		cached["resident"][Population.category(removed)] -= 1
	if bool(cached["head_ready"]):
		var previous_head: int = _winner(cached)
		var ordinal: int = int(cached["order"][at])
		var record: Array = cached["records"][ordinal]
		record[1] = false
		record[2] = int(record[2]) + 1
		cached["order"].remove_at(at)
		var pid: int = int(removed[0])
		if pid >= 0:
			var present: int = int(cached["present"][pid]) - 1
			if present > 0: cached["present"][pid] = present
			else:
				cached["present"].erase(pid)
				for spouse: Variant in cached["spouses"].get(pid, []): _refresh_head(cached, int(spouse))
		if previous_head != _winner(cached): _scope["names_version"] = int(_scope["names_version"]) + 1
	else:
		_scope["names_version"] = int(_scope["names_version"]) + 1
	_name_delta(f, removed, -1)

# The new native identity is already appended, with its cultural name and bin
# debit complete. Its RNG and all creation work remain in Population._from_bins.
static func appended(e: Dictionary, f: Dictionary, p: Array) -> void:
	if not active(e): return
	var cached: Dictionary = _scope["rows"].get(int(f["id"]), {})
	if not cached.is_empty() and is_same(cached["pp"], f.get("pp")):
		if not Persons.AWAY.has(String(p[4])): cached["resident"][Population.category(p)] += 1
		if _home(p):
			cached["home_n"] = int(cached["home_n"]) + 1
			cached["home_ready"] = false
		if String(p[4]) == "": cached["home_cats"][2 if int(p[6]) == 1 else int(p[2])] += 1
		if bool(cached["known_ready"]): _trade_delta(cached, p, 1)
		if bool(cached["head_ready"]):
			var previous_head: int = _winner(cached)
			var pid: int = int(p[0])
			if pid >= 0:
				var present: int = int(cached["present"].get(pid, 0))
				cached["present"][pid] = present + 1
				if present == 0:
					for spouse: Variant in cached["spouses"].get(pid, []): _refresh_head(cached, int(spouse))
			_add_head_record(cached, p)
			if previous_head != _winner(cached): _scope["names_version"] = int(_scope["names_version"]) + 1
		else:
			_scope["names_version"] = int(_scope["names_version"]) + 1
	_name_delta(f, p, 1)

static func returned(f: Dictionary, p: Array, previous_state: String) -> void:
	if _scope.is_empty() or previous_state != "hire": return
	var cached: Dictionary = _scope["rows"].get(int(f.get("id", -1)), {})
	if not cached.is_empty() and is_same(cached["pp"], f.get("pp")):
		cached["home_cats"][2 if int(p[6]) == 1 else int(p[2])] += 1

static func family_changed(f: Dictionary) -> void:
	if _scope.is_empty(): return
	_scope["rows"].erase(int(f.get("id", -1)))
	_scope["surnames_ready"] = false
	_scope["names_version"] = int(_scope["names_version"]) + 1

# Index all families by the exact surname/sex/first-name membership searched by
# Persons._new. Reference counts preserve duplicate names and away residents.
static func taken_names(e: Dictionary, f: Dictionary, sex: int) -> Dictionary:
	if not active(e): return {}
	if not bool(_scope["surnames_ready"]):
		_scope["surnames"] = {}
		for family: Dictionary in e["fams"]:
			for roster: Array in [Persons.pp_read(family), Persons.kp_read(family)]:
				for p: Array in roster: _name_delta(family, p, 1, true)
		_scope["surnames_ready"] = true
	var by_sex: Array = _scope["surnames"].get(String(f.get("name", "")), [{}, {}])
	return by_sex[sex]

static func _name_delta(f: Dictionary, p: Array, delta: int, building: bool = false) -> void:
	if not building and not bool(_scope["surnames_ready"]): return
	var name: String = String(f.get("name", ""))
	var groups: Dictionary = _scope["surnames"]
	if not groups.has(name): groups[name] = [{}, {}]
	var counts: Dictionary = groups[name][int(p[2])]
	var first: int = int(p[1])
	var count: int = int(counts.get(first, 0)) + delta
	if count > 0: counts[first] = count
	else: counts.erase(first)

static func owner_names(e: Dictionary) -> Array:
	if active(e) and int(_scope["names_at"]) == int(_scope["names_version"]): return [_scope["names"]]
	return []

static func remember_owner_names(e: Dictionary, names: Dictionary) -> void:
	if not active(e): return
	_scope["names"] = names
	_scope["names_at"] = int(_scope["names_version"])

# Only sweep mutations use this fast path. Outside it, native value validation
# remains in force. Job settlements, farm capacity/funding and herder caps dirty
# the index at the mutation, before another refresh can observe the business.
static func hiring_changed(e: Dictionary) -> void:
	if active(e): _scope["hiring_version"] = int(_scope["hiring_version"]) + 1

static func hiring_ready(e: Dictionary) -> bool:
	if not active(e) or int(_scope["hiring_at"]) != int(_scope["hiring_version"]): return false
	return int(_scope.get("businesses", -1)) == (e["biz"] as Array).size() and is_same(_scope.get("open"), e.get("open")) and int(_scope.get("open_size", -1)) == (e.get("open", []) as Array).size()

static func hiring_refreshed(e: Dictionary) -> void:
	if not active(e): return
	_scope["hiring_at"] = int(_scope["hiring_version"])
	_scope["businesses"] = (e["biz"] as Array).size()
	_scope["open"] = e.get("open")
	_scope["open_size"] = (e.get("open", []) as Array).size()

# Non-field takeable offers do not inspect household population or farm claims.
# Keep their original open-list order, and apply the live own-hand cap per read.
static func trade_offers(e: Dictionary) -> Array:
	if not active(e): return []
	var current_open: Array = e.get("open", [])
	var version: int = int(_scope["hiring_version"])
	if int(_scope.get("trades_at", -1)) != version or not is_same(_scope.get("trades_open"), current_open) or int(_scope.get("trades_size", -1)) != current_open.size() or int(_scope.get("trades_biz", -1)) != (e["biz"] as Array).size():
		var offers: Array = []
		for bid: Variant in current_open:
			var business: Dictionary = e["biz"][int(bid)]
			if String(business["type"]) in ["farm", "estate", "works"] or business.get("closed", false): continue
			var count: int = Businesses.takeable(business, e)
			if count > 0: offers.append([float(business["wage"]), count])
		_scope["trade_offers"] = offers
		_scope["trades_at"] = version
		_scope["trades_open"] = current_open
		_scope["trades_size"] = current_open.size()
		_scope["trades_biz"] = (e["biz"] as Array).size()
	return [_scope["trade_offers"]]

# Store each native ordered business addition, never a regrouped total. The
# first prefix reaching a cap is exactly the native short-circuit result.
# Household terms remain live: a casualty changes food need before reassignment.
static func customer_funds(e: Dictionary, cap_funds: float) -> Array:
	if not active(e) or is_nan(cap_funds): return []
	var version: int = int(_scope["hiring_version"])
	if int(_scope.get("funds_at", -1)) != version or int(_scope.get("funds_biz", -1)) != (e["biz"] as Array).size():
		var prefix: PackedFloat64Array = PackedFloat64Array()
		var sum: float = 0.0
		for business: Dictionary in e["biz"]:
			if not business.get("closed", false):
				sum += maxf(0.0, float(business["till"]) - float(business["owed"]))
				if is_nan(sum): return []
				prefix.append(sum)
		_scope["funds_prefix"] = prefix
		_scope["funds_at"] = version
		_scope["funds_biz"] = (e["biz"] as Array).size()
	var prefix: PackedFloat64Array = _scope["funds_prefix"]
	var lo: int = 0
	var hi: int = prefix.size()
	while lo < hi:
		var mid: int = (lo + hi) / 2
		if prefix[mid] < cap_funds: lo = mid + 1
		else: hi = mid
	if lo < prefix.size(): return [prefix[lo]]
	var funds: float = prefix[-1] if not prefix.is_empty() else 0.0
	var grain_week: float = float(e["price"].get("grain", 1)) * 7.0
	for family: Dictionary in e["fams"]:
		if not family.get("gone", false) and not family.get("estate", false):
			var purse: float = float(family["purse"])
			if purse > 0.0:
				funds += maxf(0.0, purse - float(Families.daily_rates(e, family)["food"]) * grain_week)
				if funds >= cap_funds: return [funds]
	return [funds]
