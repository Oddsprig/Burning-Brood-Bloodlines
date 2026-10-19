class_name WageClaims
extends RefCounted
## Earned wages stay attached to the household that did the work. Existing
## anonymous books are retained separately; current workers cannot claim them.

static func prepare(b: Dictionary) -> void:
	if not b.has("wage_claims"):
		b["wage_claims"] = {}
		b["owed_unattributed"] = maxf(0.0, float(b.get("owed", 0.0)))
	elif not b.has("owed_unattributed"):
		b["owed_unattributed"] = 0.0
	_refresh(b)

static func _refresh(b: Dictionary) -> void:
	var total := float(b.get("owed_unattributed", 0.0))
	for due in b.get("wage_claims", {}).values(): total += float(due)
	b["owed"] = total

static func after_load(e: Dictionary) -> void:
	for b in e["biz"]:
		prepare(b)
	if not e.has("wage_day"): e["wage_day"] = int(e.get("day", 0))

## Close exactly one queued town day, before production/pay changes. A job
## taken after this close first earns on the next day. Never use Game.day:
## campaign work may still be draining older queued town days.
static func accrue_day(e: Dictionary, day: int) -> void:
	if int(e.get("wage_day", day - 1)) >= day: return
	for b in e["biz"]:
		prepare(b)
		b["wage_cost_day"] = 0.0
		if b["type"] == "farm" and not b.has("wage_cost_period"): b["wage_cost_period"] = 0.0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var bed := {}
		for c in f.get("sk", {}).values():
			if int(c[Sickness.C_BED]) == 1 and int(c[Sickness.C_BIZ]) >= 0:
				var k := str(int(c[Sickness.C_BIZ]))
				var overlap := maxf(0.0, minf(float(day), Sickness._stop(c)) - maxf(float(day - 1), float(c[Sickness.C_ON])))
				bed[k] = float(bed.get(k, 0.0)) + overlap
		# Cases may recover before this older queued town day closes. Retain
		# their dated absence until its actual wage interval has been accounted.
		for interval in f.get("wage_bed", []):
			var k := str(int(interval[0]))
			var overlap := maxf(0.0, minf(float(day), float(interval[2])) - maxf(float(day - 1), float(interval[1])))
			bed[k] = float(bed.get(k, 0.0)) + overlap
		for k in f["jobs"]:
			var b: Dictionary = e["biz"][int(k)]
			if b.get("closed", false): continue
			var days := maxf(0.0, float(f["jobs"][k]) - float(bed.get(str(k), 0.0)))
			var due := days * maxf(0.0, float(b["wage"]))
			if due <= 0.0: continue
			var fk := str(int(f["id"]))
			b["wage_claims"][fk] = float(b["wage_claims"].get(fk, 0.0)) + due
			b["owed"] = float(b["owed"]) + due
			b["wage_cost_day"] = float(b["wage_cost_day"]) + due
			if b["type"] == "farm": b["wage_cost_period"] = float(b["wage_cost_period"]) + due
		if f.has("wage_bed"):
			f["wage_bed"] = (f["wage_bed"] as Array).filter(func(v): return float(v[2]) > float(day))
			if f["wage_bed"].is_empty(): f.erase("wage_bed")
	e["wage_day"] = day

## Recipient follows the existing household property rules, including repeated
## moves. Unknown legacy destinations leave the claim unpaid rather than
## allocating it to a different person or deleting the liability.
static func _recipient(e: Dictionary, f: Dictionary) -> Array:
	var seen := {}
	while f.get("gone", false):
		if f.has("wage_destination"):
			var dest: Array = f["wage_destination"]
			var key := str(dest)
			if seen.has(key): return []
			seen[key] = true
			var t: Dictionary = Game.world.get("towns", {}).get(String(dest[0]), {})
			if not TownEcon.has_econ(t): return []
			e = t["econ"]
			if int(dest[1]) < 0 or int(dest[1]) >= (e["fams"] as Array).size(): return []
			f = e["fams"][int(dest[1])]
		elif f.get("moved", "") != "":
			return []
		elif f.get("extinct", false):
			var fac: Dictionary = Game.world.get("factions", {}).get(String(e.get("faction", "")), {})
			return [fac, "treasury"] if not fac.is_empty() else [e, "treasury"]
		else: return [e, "treasury"]
	return [f, "purse"]

static func pay_business(e: Dictionary, f: Dictionary, b: Dictionary) -> Array:
	prepare(b)
	var key := str(int(f["id"]))
	var due := float(b["wage_claims"].get(key, 0.0))
	if due <= 0.0: return [0.0, 0.0]
	var target := _recipient(e, f)
	if target.is_empty(): return [0.0, due]
	var paid := minf(due, maxf(0.0, float(b["till"])))
	b["till"] = float(b["till"]) - paid
	b["t_paid"] = float(b.get("t_paid", 0.0)) + paid
	target[0][target[1]] = float(target[0].get(target[1], 0.0)) + paid
	if String(target[1]) == "purse":
		target[0]["wage_receipts"] = float(target[0].get("wage_receipts", 0.0)) + paid
	# Kind pay transfers real dated grain rights; no coin or food is created.
	var kind: float = 0.0
	if paid < due and b.get("type", "") == "farm" and not b.get("closed", false) and not f.get("gone", false) and int(b.get("owner", -1)) >= 0 and int(b["owner"]) < e.get("fams", []).size():
		var price: float = maxf(0.0, float(e.get("price", {}).get("grain", 0.0)))
		if price > 0.0:
			HarvestClaims.reserve_food(e, e["fams"][int(b["owner"])])
			var value: float = minf(due - paid, Businesses.farm_kind_value(e, b))
			if value > 0.0:
				kind = HarvestClaims.transfer_units(e, "grain", "f:%d" % int(b["owner"]), {"f:%d" % int(f["id"]): 1.0}, value / price) * price
				HarvestClaims.reserve_food(e, e["fams"][int(b["owner"])])
				HarvestClaims.reserve_food(e, f)
				var rate: float = float(Families.daily_rates(e, f)["food"])
				HarvestClaims.keep_food(e, f, int(ceil(maxf(0.0, 14.0 - float(f["store"]["food"])) * rate)), rate)
				b["kind_paid"] = float(b.get("kind_paid", 0.0)) + kind
	if paid + kind >= due: b["wage_claims"].erase(key)
	else: b["wage_claims"][key] = due - paid - kind
	_refresh(b)
	return [paid + kind, due]

static func pay_family(e: Dictionary, f: Dictionary) -> Array:
	var paid := 0.0; var short := false; var short_b := {}
	for b in e["biz"]:
		if not b.get("wage_claims", {}).has(str(int(f["id"]))): continue
		var result := pay_business(e, f, b)
		paid += float(result[0])
		if float(result[0]) < float(result[1]) * 0.95:
			b["unpaid_d"] = float(e.get("day", 0))
			# Arrears from a previous employer do not make a fully paying
			# current job count as an unpaid week in the departure rules.
			if int(f["jobs"].get(str(int(b["id"])), 0)) > 0:
				short = true; short_b = b
	return [paid, short, short_b]

## Former employees have no active payday at that employer. Retry their
## preserved claims after ordinary production, from money actually in its till.
static func pay_former(e: Dictionary) -> void:
	for b in e["biz"]:
		for key in b.get("wage_claims", {}).keys():
			var id := int(key)
			if id < 0 or id >= (e["fams"] as Array).size(): continue
			var f: Dictionary = e["fams"][id]
			if f.get("gone", false) or int(f["jobs"].get(str(int(b["id"])), 0)) <= 0:
				pay_business(e, f, b)
