extends RefCounted
## Native households, physical transfers, actual shift reservations and conserved coin.
## The estate is an existing holder, never an invented funding source.
static func money(e: Dictionary) -> float:
	return TownEcon.town_gold(e)

static func move(source: Dictionary, from_key: String, target: Dictionary, to_key: String, amount: float) -> bool:
	if amount < 0.0 or float(source.get(from_key, 0.0)) + 0.000001 < amount: return false
	if is_same(source, target) and from_key == to_key: return true
	var before: float = float(source.get(from_key, 0.0)) + float(target.get(to_key, 0.0))
	source[from_key] = float(source.get(from_key, 0.0)) - amount
	target[to_key] = float(target.get(to_key, 0.0)) + amount
	return absf(float(source[from_key]) + float(target[to_key]) - before) < 0.000001

static func pool(e: Dictionary) -> Dictionary:
	var families: Array = e.get("fams", [])
	if families.is_empty() or not bool(families[0].get("estate", false)):
		return {"ok": false, "reason": "native economy has no actual estate coin holder"}
	var vault: Dictionary = families[0]
	var before: float = money(e)
	for key: String in ["treasury", "farm_till", "land_fund"]:
		if e.has(key) and not move(e, key, vault, "purse", maxf(0.0, float(e[key]))):
			return {"ok": false, "reason": "cannot transfer actual " + key}
	for family: Dictionary in families:
		if is_same(family, vault): continue
		if not move(family, "purse", vault, "purse", maxf(0.0, float(family["purse"]))):
			return {"ok": false, "reason": "cannot transfer actual household purse"}
	for business: Dictionary in e["biz"]:
		if not move(business, "till", vault, "purse", maxf(0.0, float(business["till"]))):
			return {"ok": false, "reason": "cannot transfer actual business till"}
	return {"ok": absf(money(e) - before) < 0.00001, "reason": "native escrow must conserve every coin", "vault": vault}

static func no_shop(e: Dictionary, family: Dictionary) -> bool:
	for bid: int in family.get("owns", []):
		var business: Dictionary = e["biz"][bid]
		if str(business["type"]) != "farm" and not bool(business.get("closed", false)): return false
	return true

static func vacate(e: Dictionary, family: Dictionary) -> void:
	for key: String in family["jobs"].keys(): Families.set_job(e, family, int(key), 0)
	Shelter.release_casual(e, family)
	Families.reassign(e, family)

static func transfer_holding(e: Dictionary, family: Dictionary) -> void:
	var estate: Dictionary = e["fams"][0]
	for crop: String in family["land"].keys():
		Families.move_land(e, family, estate, crop, int(family["land"][crop]))
	for kind: String in family["herd"].keys():
		Families.move_herd(e, family, estate, kind, int(family["herd"][kind]))
	HarvestClaims.transfer(e, "f:%d" % int(family["id"]), "f:0")
	Families.reassign(e, family)

static func reservations(e: Dictionary, job: String) -> float:
	var count: float = 0.0
	for family: Dictionary in e["fams"]:
		count += float(family.get("cj", {}).get(job, 0))
		for person_id: String in family.get("child_cj", {}):
			if str(family["child_cj"][person_id]) == job:
				count += float(Barge.B()["labour"]["kid_share"])
	return count

## Populate all native casual places with actual other households. No cap/usage writes.
static func reserve_casual(town: Dictionary, e: Dictionary, excluded: Array[int], deadline: int, rotation: int = 0) -> Dictionary:
	var pooled: Dictionary = pool(e)
	if not bool(pooled["ok"]): return pooled
	# Reassess existing child reservations through the native weekly path while payers are empty.
	Shelter.weekly(Game, town, e)
	var vault: Dictionary = pooled["vault"]
	var budgets: Dictionary = {"treasury": 0.0, "customers": 0.0, "market": 0.0}
	for job: String in e["cjcap"]:
		var payer: String = str(TownEcon.data()["casual_jobs"][job]["payer"])
		budgets[payer] = float(budgets[payer]) + 7.0 * Barge.casual_wage(e, job) * float(e["cjcap"][job])
	var payer_family: Dictionary = {}
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false) or excluded.has(int(family["id"])): continue
		payer_family = family
		break
	if payer_family.is_empty(): return {"ok": false, "reason": "native casual reservations need a real customer payer"}
	var reserve: float = float(Families.daily_rates(e, payer_family)["food"]) * float(e["price"].get("grain", 1.0)) * 7.0
	var market: Dictionary = e["biz"][int(e["mkt"])]
	if not move(vault, "purse", e, "treasury", float(budgets["treasury"])) or not move(vault, "purse", market, "till", float(budgets["market"])) or not move(vault, "purse", payer_family, "purse", float(budgets["customers"]) + reserve):
		return {"ok": false, "reason": "native holders cannot fund the actual casual reservation bill"}
	Businesses.rebuild_open(e)
	var ordered: Array[Dictionary] = []
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false) or excluded.has(int(family["id"])): continue
		ordered.append(family)
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["idle"]) < int(b["idle"]) if int(a["idle"]) != int(b["idle"]) else int(a["id"]) < int(b["id"]))
	for index: int in ordered.size():
		if Time.get_ticks_msec() >= deadline: return {"ok": false, "reason": "native reservation setup reached its supplied deadline"}
		Families.reassign(e, ordered[(index + rotation) % ordered.size()])
	for job: String in e["cjcap"]:
		if absf(reservations(e, job) - float(e["cjused"].get(job, 0))) > 0.000001:
			return {"ok": false, "reason": "actual people do not own the native " + job + " reservations"}
		if not is_equal_approx(float(e["cjused"].get(job, 0)), float(e["cjcap"][job])):
			return {"ok": false, "reason": "native other workers could not fill every actual " + job + " place"}
	return pool(e)
