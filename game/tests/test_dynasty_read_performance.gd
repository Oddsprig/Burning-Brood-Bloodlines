extends RefCounted
## Frozen linear read comparison; no timing gate or generated campaign.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dynasty read: " + message)

func old_children(nodes: Dictionary, uid: String, house: String, policy: String) -> Array:
	var out := []
	for child in nodes:
		var n: Dictionary = nodes[child]
		if str(n["house_uid"]) == house and (str(n["mother_uid"]) == uid or str(n["father_uid"]) == uid): out.append(str(child))
	out.sort_custom(func(a, b):
		if policy == "male_preference" and int(nodes[a]["sex"]) != int(nodes[b]["sex"]): return int(nodes[a]["sex"]) < int(nodes[b]["sex"])
		return float(nodes[a]["born"]) < float(nodes[b]["born"]) if float(nodes[a]["born"]) != float(nodes[b]["born"]) else str(a) < str(b))
	return out

func old_branch(nodes: Dictionary, uid: String, house: String, policy: String, seen: Dictionary, out: Array) -> void:
	if uid == "" or seen.has(uid) or not nodes.has(uid) or str(nodes[uid]["house_uid"]) != house: return
	seen[uid] = true
	if nodes[uid].get("alive", false): out.append(uid)
	for child in old_children(nodes, uid, house, policy): old_branch(nodes, child, house, policy, seen, out)

func old_person(uid: String) -> Dictionary:
	var towns: Dictionary = Game.world["towns"]
	var ordered := []
	var parts := uid.split(":")
	var origin := str(parts[2]) if parts.size() == 4 else ""
	if towns.has(origin): ordered.append(towns[origin])
	for tid in towns:
		if str(tid) != origin: ordered.append(towns[tid])
	for town in ordered:
		var e: Dictionary = town.get("econ", {})
		for f in e.get("fams", []):
			for p in f.get("pp", []) + f.get("kp", []):
				if str(Persons.g(p, Persons.PERSON_UID, "")) == uid and Dynasty._living(Game, str(town.get("id", "")), f, p):
					return {"town": town, "econ": e, "family": f, "person": p, "alive": true}
	return {}

func old_heirs(uid: String, house: String, policy: String) -> Array:
	var nodes: Dictionary = Game.world["dynasty"]["kin"]
	var seen := {uid: true}; var ordered := []
	for child in old_children(nodes, uid, house, policy): old_branch(nodes, child, house, policy, seen, ordered)
	var ancestors := [uid]; var walked := {}
	while not ancestors.is_empty():
		var ancestor: String = ancestors.pop_front()
		if walked.has(ancestor) or not nodes.has(ancestor): continue
		walked[ancestor] = true
		for field in ["father_uid", "mother_uid"]:
			var parent := str(nodes[ancestor].get(field, ""))
			if parent == "" or not nodes.has(parent) or str(nodes[parent]["house_uid"]) != house: continue
			for child in old_children(nodes, parent, house, policy): old_branch(nodes, child, house, policy, seen, ordered)
			old_branch(nodes, parent, house, policy, seen, ordered)
			ancestors.append(parent)
	var out := []
	for person_uid in ordered:
		var loc: Dictionary = old_person(str(person_uid))
		if not loc.is_empty(): out.append(Dynasty._row(loc, float(Game.day)))
	return out

func compare(uid: String, house: String, label: String) -> void:
	var before: String = JSON.stringify(Game._serialize(Game.world))
	var rng_state: int = Game.rng.state; var next_unit: int = Unit._next_uid; var next_item: int = Item._next_uid
	for policy in ["male_preference", "absolute"]:
		var expected: Array = old_heirs(uid, house, policy)
		check(Dynasty._lineage_heirs(Game, uid, house, policy) == expected, label + ": exact " + policy + " rows/order match frozen linear reads")
	check(JSON.stringify(Game._serialize(Game.world)) == before and Game.rng.state == rng_state and Unit._next_uid == next_unit and Item._next_uid == next_item,
		label + ": reads preserve native world/RNG/person/item state")

func old_remember(e: Dictionary, f: Dictionary, p: Array, alive: bool) -> void:
	var uid := str(Persons.g(p, Persons.PERSON_UID, "")); var house := str(Persons.g(p, Persons.HOUSE_UID, ""))
	if uid == "" or house == "": return
	var b: Dictionary = Game.world["dynasty"]
	if f.get("cohort", false) and not b["houses"].has(house): return
	var old: Dictionary = b["kin"].get(uid, {})
	b["kin"][uid] = {"house_uid": house, "born": float(p[3]), "sex": int(p[2]), "race": Persons.race_of(e),
		"mother_uid": str(Persons.g(p, Persons.MOTHER_UID, old.get("mother_uid", ""))),
		"father_uid": str(Persons.g(p, Persons.FATHER_UID, old.get("father_uid", ""))), "alive": alive}

func old_index() -> void:
	var b: Dictionary = Game.world["dynasty"]
	b["rulers"] = {}
	for town in Game.world["towns"].values():
		var h: Dictionary = town.get("econ", {}).get("head", {})
		if str(h.get("house_uid", "")) != "": b["houses"][str(h["house_uid"])] = true
		if str(h.get("person_uid", "")) != "": b["rulers"][str(h["person_uid"])] = str(h.get("house_uid", ""))
	for node in b["kin"].values(): node["alive"] = false
	for memory in [true, false]:
		for town in Game.world["towns"].values():
			var e: Dictionary = town.get("econ", {})
			for f in e.get("fams", []):
				var rows: Array = f.get("dp", []) if memory else f.get("pp", []) + f.get("kp", [])
				for p in rows:
					var live: bool = not bool(memory) and Dynasty._living(Game, str(town.get("id", "")), f, p)
					var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
					if not live and b["kin"].get(uid, {}).get("alive", false): continue
					old_remember(e, f, p, live)

func compare_index(label: String) -> void:
	var initial: Dictionary = Game.world.duplicate(true)
	var rng_state: int = Game.rng.state; var next_unit: int = Unit._next_uid; var next_item: int = Item._next_uid
	old_index()
	var expected: String = JSON.stringify(Game._serialize(Game.world))
	Game.world = initial
	Dynasty._index_world(Game)
	check(JSON.stringify(Game._serialize(Game.world)) == expected, label + ": full ordered world exactly matches frozen native indexing")
	check(Game.rng.state == rng_state and Unit._next_uid == next_unit and Item._next_uid == next_item,
		label + ": indexing preserves RNG/Unit/Item counters")

func indexing(native) -> void:
	native.fixture()
	var e: Dictionary = Game.world["towns"]["seat"]["econ"]; var f: Dictionary = e["fams"][0]
	var root: Array = f["pp"][0]; var house := str(root[Persons.HOUSE_UID])
	var memory: Array = root.duplicate(true); memory[4] = "gone"; memory[3] -= 100
	f["dp"] = [memory]
	var pool := Families._blank(1); pool["cohort"] = true; pool["pp"] = []; e["fams"].append(pool); Families.identity(e, pool)
	for i in 24:
		var p: Array = native.person(e, pool, 300 + i, i % 2, 30, "Registered pool serviceman " + str(i))
		p[4] = "reserve"; p[5] = 1000 + i; pool["pp"].append(p)
	var retained: Array = pool["pp"][0]; retained[Persons.HOUSE_UID] = house
	retained[Persons.FATHER_UID] = root[Persons.PERSON_UID]
	var legacy: Array = pool["pp"][1]; legacy[Persons.HOUSE_UID] = house; legacy.resize(Persons.HOUSE_UID + 1)
	Game.world["dynasty"]["kin"][str(legacy[Persons.PERSON_UID])] = {"house_uid": house, "born": float(legacy[3]), "sex": int(legacy[2]),
		"race": "human", "mother_uid": "remembered-mother", "father_uid": "remembered-father", "alive": true, "obsolete": true}
	var unnamed: Array = pool["pp"][2]; unnamed[Persons.PERSON_UID] = ""
	var excluded: Array = pool["pp"][3]
	Game.world["dynasty"]["kin"][str(excluded[Persons.PERSON_UID])] = {"house_uid": str(excluded[Persons.HOUSE_UID]),
		"born": 1.0, "sex": 1, "race": "human", "mother_uid": "old", "father_uid": "old", "alive": true}
	var gone := Families._blank(2); gone["gone"] = true; gone["pp"] = []; e["fams"].append(gone); Families.identity(e, gone)
	var gone_person: Array = native.person(e, gone, 400, 0, 40, "Gone family person")
	gone_person[Persons.HOUSE_UID] = house; gone["pp"].append(gone_person)
	var estate := Families._blank(3); estate["pp"] = []; e["fams"].append(estate); Families.identity(e, estate)
	var estate_person: Array = native.person(e, estate, 401, 1, 40, "Estate person")
	estate_person[Persons.HOUSE_UID] = house; estate["pp"].append(estate_person); estate["estate"] = true
	compare_index("pool exclusions, retained ruling lineage, legacy links, estate/gone and live-over-memory precedence")
	var kin: Dictionary = Game.world["dynasty"]["kin"]
	check(kin[str(retained[Persons.PERSON_UID])]["alive"] and not kin[str(excluded[Persons.PERSON_UID])]["alive"],
		"ruling-house person inside pool is indexed while excluded retained ancestry is marked dead")
	check(kin[str(legacy[Persons.PERSON_UID])]["mother_uid"] == "remembered-mother" and not kin[str(legacy[Persons.PERSON_UID])].has("obsolete"),
		"absent native parent slots use retained fallback and obsolete node fields are removed")
	e = Game.world["towns"]["seat"]["econ"]; f = e["fams"][0]
	f["pp"][0][4] = "dead"; f["pp"][0][Persons.MOTHER_UID] = "same-day-parent"
	compare_index("same-day death and explicit parent edit")

func run(_tree: SceneTree) -> int:
	var world: Dictionary = Game.world; var company: Array = Game.company; var squads: Dictionary = Game.squads
	var day: float = Game.day; var gold: float = Game.gold; var location: String = Game.location
	Game.company = []; Game.squads = {}
	var native = NativeFixture.new(); native.fixture()
	var e: Dictionary = Game.world["towns"]["seat"]["econ"]; var f: Dictionary = e["fams"][0]
	var root: Array = f["pp"][0]; var uid := str(root[Persons.PERSON_UID]); var house := str(root[Persons.HOUSE_UID])
	var branch: Array = [root]
	for i in 96:
		# Several generations, equal ages, mixed sexes and both native person books.
		var parent: Array = branch[int(i / 4)]
		branch.append(native.child(e, f, i + 1, i % 2, 8 + (i % 29), parent, "Registered kin " + str(i)))
	Dynasty.prepare_world(Game)
	compare(uid, house, "dense native branches with minor and UID ties")
	var nodes: Dictionary = Game.world["dynasty"]["kin"]
	var first: Array = branch[1]; var first_uid := str(first[Persons.PERSON_UID])
	nodes[first_uid]["mother_uid"] = uid # Same mother/father must not duplicate a branch.
	nodes[uid]["father_uid"] = first_uid # Malformed cycle remains bounded by native seen/walked sets.
	compare(uid, house, "duplicate parent links and retained ancestry cycle")
	nodes[uid]["father_uid"] = ""
	# Move a true person to a non-origin native household; leave a departed copy.
	var moved: Array = branch[2]; var moved_uid := str(moved[Persons.PERSON_UID])
	var destination: Dictionary = Game.world["towns"]["foreign"]["econ"]["fams"][0]
	var departed: Array = moved.duplicate(true); departed[4] = "gone"
	f["pp"].erase(moved); f["kp"].erase(moved); f["pp"].append(departed); destination["pp"].append(moved)
	compare(uid, house, "moved live identity beats departed origin")
	var query := {}; var loc: Dictionary = Dynasty._query_person(Game, moved_uid, query)
	check(loc.get("person", []) == moved and loc.get("family", {}) == destination and loc.get("town", {}).get("id", "") == "foreign",
		"query address resolves actual moved person and receiving household")
	# An invalid duplicate fixture verifies origin-first and pp-before-kp precedence.
	var copy: Array = moved.duplicate(true); copy[7] = "Origin duplicate"
	f["kp"].append(copy)
	compare(uid, house, "origin live precedence over earlier fallback index")
	f["kp"].erase(copy)
	var expected: Array = old_heirs(uid, house, "male_preference")
	check(Dynasty.asset_heirs(Game, uid, house) == expected, "asset query shares actual address checks without changing lineage rows")
	moved[7] = "Same-day renamed heir"
	compare(uid, house, "same-day rename visible without persisted row cache")
	moved[4] = "dead"
	check(loc["person"][7] == moved[7] and loc["person"][4] == "dead", "address cache retains actual native person array references")
	compare(uid, house, "same-day rename/death visible without persisted address cache")
	var newborn: Array = native.child(e, f, 200, 1, 0, root, "Same-day child")
	Dynasty.prepare_world(Game)
	compare(uid, house, "same-day newborn and regenerated kin visible")
	check(Dynasty._lineage_heirs(Game, uid, house, "absolute").any(func(row): return row["person_uid"] == newborn[Persons.PERSON_UID]),
		"actual new minor appears on next pure query")
	check(Dynasty._lineage_heirs(Game, uid, house, "strength").is_empty(), "unconfigured civil traversal does not invent an orc strength heir")
	indexing(native)
	Game.world = world; Game.company = company; Game.squads = squads; Game.day = day; Game.gold = gold; Game.location = location
	print("dynasty read performance: %d checks, %d failures" % [checks, fails])
	return fails
