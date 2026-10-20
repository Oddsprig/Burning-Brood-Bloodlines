class_name HarvestClaims
extends RefCounted
## Ownership accounts for the existing integer barn inventory. Shares may be
## fractional, like joint ownership of a batch; goods themselves remain whole.
## Dated contributions, never today's acres, determine subsequent sale receipts.

const EPS := 0.00000001
const UNKNOWN := "?"
const FOOD := ["grain", "fruit"]
const ZERO_PAIR := [0.0, 0.0]

static func _family_id(key: String) -> int:
	if not key.begins_with("f:"): return -1
	var tail := key.trim_prefix("f:")
	if not tail.is_valid_int(): return -1
	var fid := int(tail)
	return fid if fid >= 0 else -1

static func _book(e: Dictionary) -> Dictionary:
	return e.get("harvest_book", {})

static func owner(h: Dictionary) -> String:
	match String(h.get("ow", "")):
		"f": return "f:%d" % int(h["oi"])
		"s": return "f:0"
		"b": return "b:%d" % int(h["oi"])
		"d": return "d:%s:%d" % [String(h.get("ot", "")), int(h["oi"])]
	return UNKNOWN

static func _sum(values: Dictionary) -> float:
	var total := 0.0
	for k in values: total += maxf(0.0, float(values[k]))
	return total

static func _scaled(weights: Dictionary, amount: float) -> Dictionary:
	var out := {}
	var total := _sum(weights)
	if amount <= EPS: return out
	if total <= EPS: return {UNKNOWN: amount}
	var keys: Array = weights.keys()
	keys.sort()
	var left := amount
	var remaining := total
	for key in keys:
		var weight := maxf(0.0, float(weights[key]))
		if weight <= 0.0: continue
		var q := left if remaining <= weight + EPS else amount * weight / total
		out[String(key)] = q
		left -= q; remaining -= weight
	return out

static func _adjust(e: Dictionary, key: String, good: String, qty: float, reserved: float) -> void:
	var balances: Dictionary = _book(e)["balances"]
	if not balances.has(key): balances[key] = {}
	var row: Array = balances[key].get(good, [0.0, 0.0])
	row[0] = maxf(0.0, float(row[0]) + qty)
	row[1] = clampf(float(row[1]) + reserved, 0.0, float(row[0]))
	balances[key][good] = row
	var fid := _family_id(key)
	if fid >= 0 and fid < e.get("fams", []).size():
		var kept := 0.0
		for g in FOOD: kept += float(balances[key].get(g, [0.0, 0.0])[1])
		e["fams"][fid]["hv"] = kept

static func _lot(e: Dictionary, good: String, shares: Dictionary, day: int, source: String, reserve: Dictionary = {}) -> void:
	if _sum(shares) <= EPS: return
	var lots: Dictionary = _book(e)["lots"]
	if not lots.has(good): lots[good] = []
	var row := {"day": day, "source": source, "shares": shares.duplicate(), "reserve": reserve.duplicate()}
	# Consecutive same-day deliveries have the same price priority and can share
	# one batch. This also keeps weekly herd products from making tiny lot rows.
	var rows: Array = lots[good]
	if not rows.is_empty() and int(rows[-1]["day"]) == day and String(rows[-1]["source"]) == source:
		row = rows[-1]
		for key in shares: row["shares"][key] = float(row["shares"].get(key, 0.0)) + float(shares[key])
		for key in reserve: row["reserve"][key] = float(row["reserve"].get(key, 0.0)) + float(reserve[key])
	else:
		rows.append(row)
		rows.sort_custom(func(a, b): return int(a["day"]) < int(b["day"]))
	for key in shares: _adjust(e, String(key), good, float(shares[key]), float(reserve.get(key, 0.0)))

static func ensure(e: Dictionary) -> void:
	if not e.has("barn"): return
	var hb: Variant = e.get("harvest_book")
	if hb is Dictionary:
		var existing: Dictionary = hb
		if not (existing.get("lots") is Dictionary): existing["lots"] = {}
		if not (existing.get("carry") is Dictionary): existing["carry"] = {}
		if not (existing.get("balances") is Dictionary): existing["balances"] = {}
		if not (existing.get("cash") is Dictionary): existing["cash"] = {}
		if not (existing.get("legacy_food") is Dictionary): existing["legacy_food"] = {}
		if not existing.has("version"): existing["version"] = 1
		if not existing.has("unattributed_cash"): existing["unattributed_cash"] = 0.0
		return
	if e.has("harvest_book"): e["unreadable_harvest_book"] = e["harvest_book"]
	e["harvest_book"] = {"version": 1, "lots": {}, "carry": {}, "balances": {}, "cash": {}, "unattributed_cash": 0.0, "legacy_food": {}}
	var b := _book(e)
	var entitlements := {}
	for f in e.get("fams", []):
		var old := maxf(0.0, float(f.get("hv", 0.0)))
		if old > 0.0:
			f["legacy_hv"] = old
			b["legacy_food"]["f:%d" % int(f["id"])] = old
		if old > 0.0 and not f.get("gone", false) and not f.get("estate", false) and Families.acres(f) > 0:
			entitlements["f:%d" % int(f["id"])] = old
		f["hv"] = 0.0
	for good in e["barn"]:
		var have := maxf(0.0, float(e["barn"][good]))
		if have <= 0.0: continue
		var shares := {UNKNOWN: have}
		var reserve := {}
		# The saved hv grants an existing food entitlement, not provenance for
		# the rest of an old barn. Back it only with physical OLD food, pro rata.
		if good in FOOD and not entitlements.is_empty():
			reserve = _scaled(entitlements, minf(have, _sum(entitlements)))
			for key in reserve:
				shares[key] = reserve[key]
				shares[UNKNOWN] = float(shares[UNKNOWN]) - float(reserve[key])
				entitlements[key] = maxf(0.0, float(entitlements[key]) - float(reserve[key]))
		_lot(e, String(good), shares, int(e.get("day", 0)), "legacy", reserve)

## Generated starting stores are an explicit endowment. They are not a claim
## that the simulation observed historical work. Older saves never use this.
static func opening(e: Dictionary) -> void:
	if e.has("harvest_book"): return
	e["harvest_book"] = {"version": 1, "lots": {}, "carry": {}, "balances": {}, "cash": {}, "unattributed_cash": 0.0, "legacy_food": {}}
	for good in e["barn"]:
		var weights := {}
		for f in e["fams"]:
			if f.get("gone", false): continue
			var w := float(f["land"].get(good, 0.0))
			if good == "fodder":
				w = float(f["land"].get("fodder", 0.0)) * float(TownEcon.data()["land"]["yield"].get("fodder", 0.0)) + float(f["land"].get("grain", 0.0)) * float(Herds.A()["straw_acre"])
			elif not good in ["grain", "fruit", "flax"]: w = float(Families.heads(f))
			if w > 0.0: weights["f:%d" % int(f["id"])] = w
		_lot(e, String(good), _scaled(weights, float(e["barn"][good])), -1, "opening")
	reserve_all(e)

static func add(e: Dictionary, good: String, n: int, owners: Dictionary, day: int, source: String = "harvest") -> void:
	if n <= 0: return
	ensure(e)
	_lot(e, good, _scaled(owners, float(n)), day, source)
	e["barn"][good] = int(e["barn"].get(good, 0)) + n
	if good in FOOD:
		for key in owners:
			var fid := _family_id(String(key))
			if fid >= 0 and fid < e.get("fams", []).size(): reserve_food(e, e["fams"][fid])

## Preserve the caller's aggregate integer output/tax exactly. Unmade fractions
## retain their dated contributors when another producer completes a whole unit.
static func harvest(e: Dictionary, good: String, channel: String, weights: Dictionary, amount: float, gross: int, tax: int, previous_carry: float, day: int) -> void:
	ensure(e)
	var carries: Dictionary = _book(e)["carry"]
	if not carries.has(channel):
		carries[channel] = []
		if previous_carry > EPS: carries[channel].append({"day": day - 1, "shares": {UNKNOWN: previous_carry}})
	var pending: Array = carries[channel]
	if amount > EPS: pending.append({"day": day, "shares": _scaled(weights, amount)})
	var left := float(gross)
	var kept := float(maxi(0, gross - tax)) / maxf(1.0, float(gross))
	for row in pending:
		if left <= EPS: break
		var total := _sum(row["shares"])
		var q := minf(left, total)
		var parts := _scaled(row["shares"], q)
		for key in parts: row["shares"][key] = maxf(0.0, float(row["shares"][key]) - float(parts[key]))
		_lot(e, good, _scaled(parts, q * kept), int(row["day"]), "harvest")
		left -= q
	if left > EPS: _lot(e, good, {UNKNOWN: left * kept}, day, "unattributed")
	carries[channel] = pending.filter(func(row): return _sum(row["shares"]) > EPS)
	e["barn"][good] = int(e["barn"].get(good, 0)) + maxi(0, gross - tax)

static func owned(e: Dictionary, key: String, good: String, reserved_only: bool = false) -> float:
	ensure(e)
	return float(_book(e).get("balances", {}).get(key, {}).get(good, [0.0, 0.0])[1 if reserved_only else 0])

## Read both balance entries [total, reserved] in one lookup without fallback allocations.
static func owned_pair(e: Dictionary, key: String, good: String) -> Array:
	ensure(e)
	var book: Variant = e.get("harvest_book")
	if not (book is Dictionary): return ZERO_PAIR
	var balances: Variant = (book as Dictionary).get("balances")
	if not (balances is Dictionary): return ZERO_PAIR
	var goods: Variant = (balances as Dictionary).get(key)
	if not (goods is Dictionary): return ZERO_PAIR
	var row: Variant = (goods as Dictionary).get(good)
	if not (row is Array) or (row as Array).size() < 2: return ZERO_PAIR
	var pair: Array = row
	if pair[0] is float and pair[1] is float: return pair
	return [float(pair[0]), float(pair[1])]

static func available(e: Dictionary, good: String) -> int:
	ensure(e)
	var barn_have := maxi(0, int(e["barn"].get(good, 0)))
	if barn_have <= 0: return 0
	var total := 0.0
	var balances: Dictionary = _book(e).get("balances", {})
	for key in balances:
		var goods: Dictionary = balances[key]
		if goods.has(good):
			var row: Array = goods[good]
			total += maxf(0.0, float(row[0]) - float(row[1]))
	return mini(barn_have, maxi(0, int(floor(total + EPS))))

static func _remove(e: Dictionary, good: String, amount: float, respect_reserves: bool, owner_filter: String, reserved_only: bool = false) -> Dictionary:
	var out := {}
	var left := amount
	var rows: Array = _book(e)["lots"].get(good, [])
	for row in rows:
		if left <= EPS: break
		var weights := {}
		# An owner-filtered withdrawal has one eligible creditor; selecting that
		# key directly avoids visiting every other producer in joint dated lots.
		if owner_filter != "":
			if row["shares"].has(owner_filter):
				var qty := float(row["shares"][owner_filter])
				var held := float(row["reserve"].get(owner_filter, 0.0))
				var takeable := held if reserved_only else (maxf(0.0, qty - held) if respect_reserves else qty)
				if takeable > EPS: weights[owner_filter] = takeable
		else:
			for key in row["shares"]:
				var qty := float(row["shares"][key])
				var held := float(row["reserve"].get(key, 0.0))
				var takeable := held if reserved_only else (maxf(0.0, qty - held) if respect_reserves else qty)
				if takeable > EPS: weights[key] = takeable
		var q := minf(left, _sum(weights))
		var parts := _scaled(weights, q)
		for key in parts:
			var old := float(row["shares"][key])
			var old_r := float(row["reserve"].get(key, 0.0))
			var took := float(parts[key])
			var used_r := took if reserved_only else (0.0 if respect_reserves else minf(old_r, took * old_r / maxf(EPS, old)))
			row["shares"][key] = maxf(0.0, old - took)
			row["reserve"][key] = maxf(0.0, old_r - used_r)
			_adjust(e, String(key), good, -took, -used_r)
			out[key] = float(out.get(key, 0.0)) + took
		left -= q
	_book(e)["lots"][good] = rows.filter(func(row): return _sum(row["shares"]) > EPS)
	return out

static func take(e: Dictionary, good: String, n: int, respect_reserves: bool = true, owner_filter: String = "") -> Dictionary:
	ensure(e)
	var have := float(available(e, good)) if respect_reserves else float(e["barn"].get(good, 0))
	if owner_filter != "":
		have = owned(e, owner_filter, good) - (owned(e, owner_filter, good, true) if respect_reserves else 0.0)
	var q := mini(maxi(0, n), mini(maxi(0, int(e["barn"].get(good, 0))), maxi(0, int(floor(have + EPS)))))
	var shares := _remove(e, good, float(q), respect_reserves, owner_filter)
	e["barn"][good] = int(e["barn"].get(good, 0)) - q
	return {"n": q, "shares": shares}

static func lose(e: Dictionary, good: String, n: int) -> int:
	return int(take(e, good, n, false)["n"])

## Keep food until the next harvest window, not a rolling extra year. Summer
## and autumn form one continuous window; while it is in progress, protect the
## coming winter/spring too. Former landowners keep their existing food rights.
static func food_reserve_days(e: Dictionary, f: Dictionary) -> float:
	var seasons: Array = [false, false, false, false]
	var cuts: Dictionary = TownEcon.data()["land"]["harvest_seasons"]
	var land: Dictionary = f.get("land", {})
	for good in FOOD:
		if float(land.get(good, 0.0)) <= 0.0: continue
		var gcuts: Array = cuts.get(good, [])
		var need_check := false
		for cut in gcuts:
			if float(cut[1]) > 0.0 and not seasons[int(cut[0])]:
				need_check = true
				break
		if not need_check: continue
		if CropRotation.family_yield(e, f, String(good)) <= 0.0: continue
		for cut in gcuts:
			if float(cut[1]) > 0.0: seasons[int(cut[0])] = true
	var day: float = float(e.get("day", 0))
	var si: int = Calendar.season_index(day)
	var remaining: int = Calendar.DAYS_PER_SEASON - Calendar.day_of_season(day) + 1
	for offset in range(1, 5):
		var next: int = (si + offset) % 4
		if seasons[next] and not seasons[(next + 3) % 4]:
			return maxf(7.0, float(remaining + (offset - 1) * Calendar.DAYS_PER_SEASON))
	return float(EconGen.YEAR_DAYS)

static func reserve_food(e: Dictionary, f: Dictionary) -> void:
	ensure(e)
	if not e.has("harvest_book"): return
	var b: Dictionary = e["harvest_book"]
	var balances: Dictionary = b["balances"]
	if balances.is_empty(): return
	var key := "f:%d" % int(f["id"])
	if not balances.has(key): return
	var fbal: Dictionary = balances[key]
	var g_pair: Array = fbal.get("grain", ZERO_PAIR)
	var fr_pair: Array = fbal.get("fruit", ZERO_PAIR)
	var g_own := float(g_pair[0])
	var g_res := float(g_pair[1])
	var fr_own := float(fr_pair[0])
	var fr_res := float(fr_pair[1])
	if g_own <= EPS and g_res <= EPS and fr_own <= EPS and fr_res <= EPS: return
	var budget: float = 0.0
	if not f.get("gone", false) and not f.get("estate", false) and (g_own > EPS or fr_own > EPS):
		var rate := float(Barge.eaters(e, f, float(e.get("day", 0)))[0]) * float(TownEcon.data()["needs"]["food"])
		budget = maxf(0.0, (food_reserve_days(e, f) - maxf(0.0, float(f["store"]["food"]))) * rate)
	var lots: Dictionary = b["lots"]
	for i in 2:
		var good: String = FOOD[i]
		var own_v := g_own if i == 0 else fr_own
		var res_v := g_res if i == 0 else fr_res
		var target := minf(budget, own_v)
		var delta := target - res_v
		budget -= target
		if absf(delta) <= EPS: continue
		var rows: Array = lots.get(good, [])
		for row in rows:
			var r_res: Dictionary = row["reserve"]
			var r_sh: Dictionary = row["shares"]
			var old := float(r_res.get(key, 0.0))
			var qty := float(r_sh.get(key, 0.0))
			var change := minf(delta, maxf(0.0, qty - old)) if delta > 0.0 else -minf(-delta, old)
			if absf(change) > EPS:
				r_res[key] = old + change
				_adjust(e, key, good, 0.0, change)
				delta -= change
			if absf(delta) <= EPS: break

static func reserve_all(e: Dictionary) -> void:
	ensure(e)
	if not e.has("harvest_book"): return
	if (e["harvest_book"]["balances"] as Dictionary).is_empty(): return
	for f in e.get("fams", []): reserve_food(e, f)

static func keep_food(e: Dictionary, f: Dictionary, meals: int, rate: float) -> int:
	if meals <= 0 or rate <= 0.0: return 0
	reserve_food(e, f)
	var key := "f:%d" % int(f["id"])
	var kept := 0
	for good in FOOD:
		var q := mini(meals - kept, int(floor(owned(e, key, good, true) + EPS)))
		if q <= 0: continue
		_remove(e, good, float(q), false, key, true)
		e["barn"][good] = int(e["barn"].get(good, 0)) - q
		e["hh"][good] = int(e["hh"].get(good, 0)) + q
		f["store"]["food"] = float(f["store"]["food"]) + float(q) / rate
		kept += q
	return kept

## The payment has already left its payer. This book, backed by farm_till,
## records the recipients; it does not create a second pile of coins.
static func credit(e: Dictionary, shares: Dictionary, value: float) -> void:
	if value <= 0.0: return
	ensure(e)
	var b := _book(e)
	e["farm_till"] = float(e.get("farm_till", 0.0)) + value
	var payments := _scaled(shares, value)
	for key in payments:
		var money := float(payments[key])
		var fid: int = _family_id(String(key))
		if fid >= 0 and fid < e.get("fams", []).size():
			var f: Dictionary = e["fams"][fid]
			if not f.get("gone", false) and not Businesses.farm_of(e, f).is_empty():
				# Daily sale cash reaches payroll before the owner's weekly turn.
				e["farm_till"] = float(e["farm_till"]) - money
				var surplus: float = Families.receive_harvest(e, f, money)
				f["harvest_receipts"] = float(f.get("harvest_receipts", 0.0)) + surplus
				f["harvest_gross"] = float(f.get("harvest_gross", 0.0)) + money
				continue
		if key == UNKNOWN: b["unattributed_cash"] = float(b["unattributed_cash"]) + money
		else: b["cash"][key] = float(b["cash"].get(key, 0.0)) + money
	pay_departed(e)

## Called inside the existing family settlement; its caller debits farm_till
## and applies the existing tribute/purse/estate policy once to the returned sum.
static func reserved_cash(e: Dictionary) -> float:
	var b := _book(e)
	return _sum(b.get("cash", {})) + maxf(0.0, float(b.get("unattributed_cash", 0.0)))

static func collect(e: Dictionary, f: Dictionary, reserved: float = 0.0) -> float:
	var b := _book(e)
	if b.is_empty(): return 0.0
	var key := "f:%d" % int(f["id"])
	var due := float(b["cash"].get(key, 0.0))
	var paid := minf(due, maxf(0.0, float(e.get("farm_till", 0.0)) - reserved - float(b.get("unattributed_cash", 0.0))))
	if paid >= due - EPS: b["cash"].erase(key)
	else: b["cash"][key] = due - paid
	return paid

static func pay_departed(e: Dictionary) -> void:
	var b := _book(e)
	if b.is_empty(): return
	for key in b["cash"].keys():
		var due := float(b["cash"][key])
		var recipient := []
		var family := false
		if String(key).begins_with("f:"):
			var fid := _family_id(String(key))
			if fid < 0 or fid >= e.get("fams", []).size(): continue
			var f: Dictionary = e["fams"][fid]
			if f.get("estate", false): recipient = [e, "treasury"]
			elif f.get("gone", false): recipient = WageClaims._recipient(e, f); family = true
			else: continue
		elif String(key).begins_with("b:"):
			var tail := String(key).trim_prefix("b:")
			if not tail.is_valid_int(): continue
			var bid := int(tail)
			if bid >= 0 and bid < e.get("biz", []).size(): recipient = [e["biz"][bid], "till"]
		elif String(key).begins_with("d:"):
			var parts := String(key).split(":")
			if parts.size() != 3 or not parts[2].is_valid_int(): continue
			var town: Dictionary = Game.world.get("towns", {}).get(parts[1], {})
			if TownEcon.has_econ(town):
				var bid := int(parts[2])
				if bid >= 0 and bid < town["econ"]["biz"].size(): recipient = [town["econ"]["biz"][bid], "till"]
		if recipient.is_empty(): continue
		var paid := minf(due, maxf(0.0, float(e["farm_till"]) - float(b["unattributed_cash"])))
		var tax := 0.0
		if family and String(recipient[1]) == "purse":
			var ruler: Dictionary = e.get("ruler", {})
			if ruler.get("kind", "") == "coin": tax = paid * float(ruler.get("tribute", 0.0))
			e["treasury"] = float(e["treasury"]) + tax
			if e.has("stats"): e["stats"]["tribute_coin"] = float(e["stats"].get("tribute_coin", 0.0)) + tax
			recipient[0]["harvest_receipts"] = float(recipient[0].get("harvest_receipts", 0.0)) + paid - tax
			recipient[0]["harvest_gross"] = float(recipient[0].get("harvest_gross", 0.0)) + paid
		recipient[0][recipient[1]] = float(recipient[0].get(recipient[1], 0.0)) + paid - tax
		e["farm_till"] = float(e["farm_till"]) - paid
		if paid >= due - EPS: b["cash"].erase(key)
		else: b["cash"][key] = due - paid

static func depart(e: Dictionary, f: Dictionary) -> void:
	ensure(e)
	var key := "f:%d" % int(f["id"])
	for good in _book(e)["lots"]:
		for row in _book(e)["lots"][good]:
			var held := float(row["reserve"].get(key, 0.0))
			row["reserve"].erase(key)
			_adjust(e, key, String(good), 0.0, -held)

static func transfer(e: Dictionary, from_owner: String, to_owner: String) -> void:
	ensure(e)
	if from_owner == to_owner: return
	var b := _book(e)
	for good in b["lots"]:
		for row in b["lots"][good]:
			var qty := float(row["shares"].get(from_owner, 0.0))
			var held := float(row["reserve"].get(from_owner, 0.0))
			if qty <= 0.0: continue
			row["shares"].erase(from_owner); row["reserve"].erase(from_owner)
			row["shares"][to_owner] = float(row["shares"].get(to_owner, 0.0)) + qty
			_adjust(e, from_owner, String(good), -qty, -held)
			_adjust(e, to_owner, String(good), qty, 0.0)
	for rows in b["carry"].values():
		for row in rows:
			var qty := float(row["shares"].get(from_owner, 0.0))
			row["shares"].erase(from_owner)
			if qty > 0.0: row["shares"][to_owner] = float(row["shares"].get(to_owner, 0.0)) + qty
	var cash := float(b["cash"].get(from_owner, 0.0))
	b["cash"].erase(from_owner)
	if cash > 0.0: b["cash"][to_owner] = float(b["cash"].get(to_owner, 0.0)) + cash

## In-kind repayment changes the creditor of goods already in the barn.
## Their production dates and total physical quantity do not change.
static func transfer_units(e: Dictionary, good: String, from_owner: String, to_weights: Dictionary, amount: float) -> float:
	ensure(e)
	var left := minf(maxf(0.0, amount), owned(e, from_owner, good))
	var total := left
	for row in _book(e)["lots"].get(good, []):
		if left <= EPS: break
		var old := float(row["shares"].get(from_owner, 0.0))
		var q := minf(left, old)
		if q <= EPS: continue
		var old_r := float(row["reserve"].get(from_owner, 0.0))
		var used_r := minf(old_r, q)
		row["shares"][from_owner] = old - q
		row["reserve"][from_owner] = old_r - used_r
		_adjust(e, from_owner, good, -q, -used_r)
		var shares := _scaled(to_weights, q)
		for key in shares:
			row["shares"][key] = float(row["shares"].get(key, 0.0)) + float(shares[key])
			_adjust(e, String(key), good, float(shares[key]), 0.0)
		left -= q
	return total - left

## Saved caches are derived. Missing physical provenance is preserved as
## unknown; excess claims lose backing proportionally, never inventing goods.
static func after_load(e: Dictionary) -> void:
	ensure(e)
	var b := _book(e)
	b["balances"] = {}
	for f in e.get("fams", []): f["hv"] = 0.0
	for good in b["lots"].keys():
		var rows: Array = b["lots"][good] if b["lots"][good] is Array else []
		rows = rows.filter(func(row): return row is Dictionary and row.get("shares") is Dictionary)
		var total := 0.0
		for row in rows: total += _sum(row["shares"])
		var physical := maxf(0.0, float(e["barn"].get(good, 0)))
		var scale := minf(1.0, physical / maxf(EPS, total))
		for row in rows:
			row["day"] = int(row.get("day", e.get("day", 0)))
			if not row.get("reserve") is Dictionary: row["reserve"] = {}
			if not row.has("source"): row["source"] = "unattributed"
			for key in row["shares"]:
				var qty := maxf(0.0, float(row["shares"][key])) * scale
				var kept := clampf(float(row["reserve"].get(key, 0.0)) * scale, 0.0, qty)
				row["shares"][key] = qty; row["reserve"][key] = kept
				_adjust(e, String(key), String(good), qty, kept)
		b["lots"][good] = rows.filter(func(row): return _sum(row["shares"]) > EPS)
		b["lots"][good].sort_custom(func(a, c): return int(a["day"]) < int(c["day"]))
	for good in e["barn"]:
		var total := 0.0
		for goods in b["balances"].values(): total += float(goods.get(good, [0.0, 0.0])[0])
		var gap := float(e["barn"][good]) - total
		if gap > EPS: _lot(e, String(good), {UNKNOWN: gap}, int(e.get("day", 0)), "unattributed")
	for channel in b["carry"].keys():
		var rows: Array = b["carry"][channel] if b["carry"][channel] is Array else []
		rows = rows.filter(func(row): return row is Dictionary and row.get("shares") is Dictionary)
		var total := 0.0
		for row in rows: total += _sum(row["shares"])
		var real_carry := maxf(0.0, float(e.get("carry", {}).get(channel, 0.0)))
		var scale := minf(1.0, real_carry / maxf(EPS, total))
		for row in rows:
			row["day"] = int(row.get("day", e.get("day", 0)))
			for key in row["shares"]: row["shares"][key] = maxf(0.0, float(row["shares"][key])) * scale
		if real_carry - total > EPS: rows.append({"day": int(e.get("day", 0)), "shares": {UNKNOWN: real_carry - total}})
		rows.sort_custom(func(a, c): return int(a["day"]) < int(c["day"]))
		b["carry"][channel] = rows.filter(func(row): return _sum(row["shares"]) > EPS)
	b["version"] = int(b["version"])
	b["unattributed_cash"] = maxf(0.0, float(b["unattributed_cash"]))
	for key in b["cash"]: b["cash"][key] = maxf(0.0, float(b["cash"][key]))
	reserve_all(e)
