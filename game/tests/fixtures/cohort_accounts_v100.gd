extends RefCounted
## Independent test accounts: real anonymous birth/sex bins, never f.m/f counters.
static func bins(e: Dictionary, f: Dictionary) -> Array[int]:
	var out: Array[int] = [0, 0, 0, 0]
	if not Population.is_cohort(f):
		return out
	var year_days: float = People.year_days()
	var year: int = int(f.get("population_year", int(floor(float(e.get("day", 0)) / year_days))))
	var ages: Dictionary = People.ages(Persons.family_race(e, f))
	for key: Variant in f.get("age_bins", {}):
		var parts: PackedStringArray = String(key).split(":")
		var age: int = year - int(parts[1])
		var category: int = 3 if age < int(ages["adult"]) else (2 if age >= int(ages["elder"]) else int(parts[0]))
		out[category] += int(f["age_bins"][key])
	return out

## population.gd:227-279 documents anonymous-first paid/casual places followed by
## keepers/own work, with named responsibility swaps and reserved academy places.
## Expand that contract independently; never call the native staffing/work oracle.
static func work_accounts(e: Dictionary, f: Dictionary, anonymous_adults: int) -> Dictionary:
	var result: Dictionary = {"valid": false, "named": {}, "anonymous": {}}
	var slots: Array[String] = []
	var targets: Dictionary = {}
	var academies: Dictionary = {}
	var kept: Dictionary = {}
	for bid: Variant in f.get("keeps", []):
		kept[int(bid)] = true
	for group: String in ["jobs", "cj"]:
		var blocks: Dictionary = f.get(group, {})
		for key: Variant in blocks:
			var count: int = int(blocks[key])
			if count < 0:
				return result
			var slot: String = ("job:" + str(int(key))) if group == "jobs" else ("casual:" + String(key))
			if group == "jobs" and count > 0:
				var business: Dictionary = e["biz"][int(key)]
				if String(business["type"]) == "academy":
					academies[slot] = true
				elif not kept.has(int(key)):
					targets[slot] = true
			for i: int in count:
				slots.append(slot)
	for bid: Variant in f.get("keeps", []):
		var slot: String = "keep:" + str(int(bid))
		slots.append(slot)
		targets[slot] = true
		if String(e["biz"][int(bid)]["type"]) == "academy":
			academies[slot] = true
	if int(f.get("hands", 0)) < 0 or int(f.get("idle", 0)) < 0 or anonymous_adults < 0:
		return result
	for i: int in int(f.get("hands", 0)):
		slots.append("own")
	for i: int in int(f.get("idle", 0)):
		slots.append("idle")
	var home: Array[Array] = []
	for person: Array in f.get("pp", []):
		if int(person[6]) == 0 and String(person[4]) in ["", "hire", "reserve"]:
			home.append(person)
	home.sort_custom(func(a: Array, b: Array) -> bool: return float(a[3]) < float(b[3]) if float(a[3]) != float(b[3]) else int(a[0]) < int(b[0]))
	if slots.size() != anonymous_adults + home.size():
		return result
	var anonymous: Dictionary = {}
	for i: int in anonymous_adults:
		anonymous[slots[i]] = int(anonymous.get(slots[i], 0)) + 1
	var named: Dictionary = {}
	var reserved: Dictionary = {}
	var covered: Dictionary = {}
	for i: int in home.size():
		var pid: int = int(home[i][0])
		var slot: String = slots[anonymous_adults + i]
		named[pid] = slot
		if academies.has(slot):
			reserved[pid] = true
		if targets.has(slot) and not covered.has(slot):
			reserved[pid] = true
			covered[slot] = true
	# A responsible named worker displaces one real anonymous occupant into
	# his old place. Count that exchange per token, never as a residual sum.
	for target: String in targets:
		if covered.has(target):
			continue
		for person: Array in home:
			var pid: int = int(person[0])
			if reserved.has(pid):
				continue
			if int(anonymous.get(target, 0)) <= 0:
				return result
			var previous: String = String(named[pid])
			anonymous[target] = int(anonymous[target]) - 1
			anonymous[previous] = int(anonymous.get(previous, 0)) + 1
			named[pid] = target
			reserved[pid] = true
			covered[target] = true
			break
		if not covered.has(target):
			return result
	_academy_places(e, f, home, named, academies)
	result["valid"] = named.size() == home.size()
	result["named"] = named
	result["anonymous"] = anonymous
	return result

# Model Academy exchanges using the independent string-token ledger. Never
# ask the production work/staff mapper for the expected holder or its place.
static func _academy_places(e: Dictionary, f: Dictionary, home: Array[Array], named: Dictionary, academies: Dictionary) -> void:
	var paid: Array[String] = []
	for slot: String in named.values():
		if slot.begins_with("job:") and academies.has(slot) and not paid.has(slot):
			paid.append(slot)
	for slot: String in paid:
		var holders: Array = home.filter(func(person: Array) -> bool: return String(named[int(person[0])]) == slot)
		if holders.any(func(person: Array) -> bool: return String(person[4]) in ["", "hire"]):
			continue
		var candidates: Array = home.filter(func(person: Array) -> bool:
			return String(person[4]) in ["", "hire"] and not academies.has(String(named[int(person[0])])))
		if candidates.is_empty():
			continue
		var displaced: int = int(holders[0][0])
		var eligible: int = int(candidates[0][0])
		var previous: String = String(named[eligible])
		named[eligible] = slot
		named[displaced] = previous
	# A valid appointed head retains his place when positional work moves.
	# Exchange one existing named place; never create a paid slot.
	var bid: int = int(e.get("academy", -1))
	if bid < 0 or bid >= (e.get("biz", []) as Array).size() or not f.get("jobs", {}).has(str(bid)):
		return
	var business: Dictionary = e["biz"][bid]
	var lead: Array = business.get("lead", [])
	if bool(business.get("research_idle", false)) or lead.size() < 2 or int(lead[0]) != int(f["id"]):
		return
	var pid: int = int(lead[1])
	var people: Array = home.filter(func(person: Array) -> bool: return int(person[0]) == pid)
	if people.is_empty() or not String(people[0][4]) in ["", "hire"]:
		return
	var lead_uid: String = String(business.get("lead_uid", ""))
	if lead_uid != "" and String(Persons.g(people[0], Persons.PERSON_UID, "")) != lead_uid:
		return
	var previous: String = String(named[pid])
	var post: String = "job:" + str(bid)
	if previous.begins_with("keep:") or previous == post:
		return
	var holders: Array = home.filter(func(person: Array) -> bool: return String(named[int(person[0])]) == post)
	if holders.is_empty():
		return
	named[pid] = post
	named[int(holders[0][0])] = previous

static func token(place: Dictionary) -> String:
	var kind: String = String(place.get("kind", "missing"))
	if kind in ["land", "herd"]:
		return "own"
	if kind == "job":
		return ("keep:" if bool(place.get("keeper", false)) else "job:") + str(int(place.get("biz", -1)))
	if kind == "casual":
		return "casual:" + String(place.get("cj", ""))
	return "idle" if kind == "none" else "invalid:" + kind

static func add(actual: Dictionary, slot: String, count: int) -> void:
	if count == 0:
		return
	if slot in ["own", "idle"]:
		actual[slot] = int(actual[slot]) + count
	elif slot.begins_with("keep:"):
		actual["keepers"] = int(actual["keepers"]) + count
	else:
		var group: String = "jobs" if slot.begins_with("job:") else "casual"
		var key: String = slot.trim_prefix("job:" if group == "jobs" else "casual:")
		actual[group][key] = int(actual[group].get(key, 0)) + count
