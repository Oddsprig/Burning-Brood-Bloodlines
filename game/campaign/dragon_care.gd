class_name DragonCare
extends RefCounted
## Daily upkeep of the existing records. All goods and coin come from native
## location markets and the actual owning household; there is no dragon wallet.
const FEED_MASS_SHARE := 0.008
const FOOD_UNIT_KG := 0.4
const FAMILY_RESERVE_DAYS := 7.0
const TOWN_RESERVE_DAYS := 3.0
const MEAT := ["fresh_meat", "meat"]
const HUMAN_FOOD := ["grain", "fruit", "meat", "fresh_meat"]

static func initialize(row: Dictionary, day: int) -> void:
	if not row.has("growth_points"): row["growth_points"] = DragonGrowth.initial_points(row)
	if not row.has("care"): row["care"] = {"last_day": day, "health": 1.0, "last": {}}

static func after_load(game) -> void:
	for row: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		# Missing older data is never turned into retrospective food/coin charges.
		initialize(row, int(floor(game.day)))
		var care: Dictionary = row["care"]
		care["last_day"] = int(care.get("last_day", floor(game.day)))
		care["health"] = clampf(float(care.get("health", 1.0)), 0.0, 1.0)
		if care.get("last") is Dictionary and not care["last"].is_empty():
			care["last"]["day"] = int(care["last"].get("day", care["last_day"]))

static func _market_ready(e: Dictionary) -> bool:
	for key in ["stock", "price", "stats", "req", "led"]:
		if not e.get(key) is Dictionary: return false
	var businesses: Array = e.get("biz", [])
	var market := int(e.get("mkt", -1))
	return market >= 0 and market < businesses.size() and businesses[market] is Dictionary and e["led"].get("used") is Dictionary

static func _context(game, row: Dictionary) -> Dictionary:
	var owner := Dynasty._person(game, str(row.get("owner_person_uid", "")))
	var loc: Dictionary = game.world.get("towns", {}).get(str(row.get("location_town_id", "")), {})
	var e: Dictionary = loc.get("econ", {})
	var out := {"family": {}, "owner_econ": {}, "econ": e, "keeper": {}, "ok": false, "reason": ""}
	if not row.get("alive", false): out["reason"] = "Deceased; no further care charges."; return out
	if str(row.get("owner_status", "claimed")) != "claimed" or owner.is_empty():
		out["reason"] = "No living claimed owner can fund care."; return out
	var family: Dictionary = owner["family"]
	if family.get("gone", false) or family.get("estate", false) or family.get("cohort", false):
		out["reason"] = "The owning household is unavailable."; return out
	if str(family.get("household_uid", "")) != str(row.get("owner_household_uid", "")) or str(Persons.g(owner["person"], Persons.HOUSE_UID, "")) != str(row.get("owner_house_uid", "")):
		out["reason"] = "Ownership references need reconciliation."; return out
	out["family"] = family; out["owner_econ"] = owner["econ"]
	if not _market_ready(e): out["reason"] = "No working market at the dragon's location."; return out
	var keeper := Dragons._person(game, str(row.get("custodian_person_uid", "")))
	if keeper.is_empty() or not Dragons._present(keeper, str(row.get("location_town_id", ""))):
		out["reason"] = "Choose a living custodian present at this location."; return out
	out["keeper"] = keeper; out["ok"] = true
	return out

static func _unit_price(e: Dictionary, good: String) -> float:
	var price := float(e.get("price", {}).get(good, 0.0)) * TownEcon.markup()
	return price if is_finite(price) and price > 0.0 else 0.0

static func _reserve(e: Dictionary, f: Dictionary, day: int) -> float:
	# Family larders are settled weekly. Quote their remaining days at this
	# explicit care midnight without decrementing another subsystem's stores.
	var elapsed := maxf(0.0, float(day) - float(f.get("last", day)))
	var available_days := maxf(0.0, float(f.get("store", {}).get("food", 0.0)) - elapsed)
	var own_day := e.duplicate(false); own_day["day"] = float(day)
	var meals := float(Families.daily_rates(own_day, f)["food"]) * maxf(0.0, FAMILY_RESERVE_DAYS - available_days)
	return maxf(1.0, EconomyRules.essential_food_cost(e, meals))

static func _food_headroom(e: Dictionary, day: int) -> int:
	var stock := 0; var household := 0
	for good in HUMAN_FOOD:
		stock += maxi(0, int(e.get("stock", {}).get(good, 0)))
		household += maxi(0, int(e.get("hh", {}).get(good, 0)))
	var daily_meals := Barge.household_eaters(e, float(day), false) * float(TownEcon.data()["needs"]["food"])
	return maxi(0, int(floor(float(stock) - maxf(0.0, daily_meals * TOWN_RESERVE_DAYS - household))))

static func _supply_limit(want: int, have: int) -> int:
	return mini(want, have if have <= 8 or want * 4 <= have else maxi(1, have / 4))

static func _quote(game, row: Dictionary, day: int, context: Dictionary) -> Dictionary:
	var care: Dictionary = row.get("care", {})
	var metrics := DragonGrowth.metrics(row)
	var health := clampf(float(care.get("health", 1.0)), 0.0, 1.0)
	var egg := str(row.get("stage", "")) == "egg"
	var profile := Dragons.physical_profile(game, row)
	var mass := float(profile.get("body_mass_kg", 0.0))
	var need := 0 if egg or not row.get("alive", false) else int(ceil(mass * FEED_MASS_SHARE / FOOD_UNIT_KG))
	var upkeep := 0 if not row.get("alive", false) else (1 if egg else 1 + int(floor(maxf(0, float(metrics.get("growth_points", 0))))))
	var f: Dictionary = context["family"]; var e: Dictionary = context["econ"]
	var valid := bool(context["ok"]) and bool(profile.get("valid", false)) and bool(metrics.get("valid", false))
	var purse := maxf(0.0, float(f.get("purse", 0.0)))
	var reserve := _reserve(context["owner_econ"], f, day) if not f.is_empty() else 0.0
	var budget := maxf(0.0, purse - reserve)
	var result := {"health": health, "growth_points": float(metrics.get("growth_points", 0)),
		"last_day": int(care.get("last_day", floor(game.day))), "payer_name": str(f.get("name", "Unavailable household")),
		"payer_household_uid": str(f.get("household_uid", "")), "payer_purse": purse, "spendable": budget,
		"keeper_name": str(context["keeper"].get("name", "None present")), "care_active": valid,
		"reason": str(context["reason"]), "food_need_kg": float(need) * FOOD_UNIT_KG,
		"food_need_units": need, "food_available_units": 0, "food_possible_units": 0,
		"food_unit_price": 0.0, "feed_cost_estimate": 0.0, "upkeep_need_units": upkeep,
		"upkeep_possible_units": 0, "upkeep_cost_estimate": 0.0, "last": care.get("last", {}).duplicate(true),
		"reserve": reserve, "orders": [], "day": day}
	for good in MEAT: result["food_available_units"] += maxi(0, int(e.get("stock", {}).get(good, 0)))
	if not valid:
		if context["ok"]: result["reason"] = "Unknown physical profile; care is unavailable."
		return result
	var headroom := _food_headroom(e, day)
	var remaining := need
	var supply_left := need; var supply_headroom := headroom
	for good in MEAT:
		if _unit_price(e, good) <= 0.0: continue
		var allowed := mini(supply_headroom, _supply_limit(supply_left, maxi(0, int(e["stock"].get(good, 0)))))
		supply_left -= allowed; supply_headroom -= allowed
	for good in MEAT:
		if remaining <= 0: break
		var price := _unit_price(e, good)
		if price <= 0.0: continue
		if float(result["food_unit_price"]) <= 0.0: result["food_unit_price"] = price
		var have := maxi(0, int(e["stock"].get(good, 0)))
		var allowed := mini(headroom, _supply_limit(remaining, have))
		var quantity := mini(allowed, int(floor(budget / price)))
		var cost := float(quantity) * price
		result["orders"].append({"good": good, "quantity": quantity, "cost": cost, "unmet": 0, "unaffordable": 0})
		result["food_possible_units"] += quantity; result["feed_cost_estimate"] += cost
		remaining -= quantity; headroom -= quantity; budget = maxf(0, budget - cost)
	# Fresh and preserved meat substitute for one meal. Attribute the residual
	# order once; asking both stalls for the full shortage doubles market demand.
	if remaining > 0 and not result["orders"].is_empty():
		var last_order: Dictionary = result["orders"][-1]
		last_order["unmet"] = mini(remaining, supply_left)
		last_order["unaffordable"] = remaining - int(last_order["unmet"])
	var wood_price := _unit_price(e, "wood")
	if wood_price > 0.0:
		var allowed := _supply_limit(upkeep, maxi(0, int(e["stock"].get("wood", 0))))
		var quantity := mini(allowed, int(floor(budget / wood_price)))
		result["upkeep_possible_units"] = quantity; result["upkeep_cost_estimate"] = float(quantity) * wood_price
		result["orders"].append({"good": "wood", "quantity": quantity, "cost": float(quantity) * wood_price, "unmet": upkeep - allowed, "unaffordable": allowed - quantity})
	var reasons := []
	if remaining > 0: reasons.append("Feed is short after market and household food reserves.")
	if int(result["upkeep_possible_units"]) < upkeep: reasons.append("Shelter supplies are short.")
	result["reason"] = "Daily care can be supplied." if reasons.is_empty() else " ".join(PackedStringArray(reasons))
	return result

static func status(game, row: Dictionary) -> Dictionary:
	return _quote(game, row, int(floor(game.day)), _context(game, row))

static func _event(row: Dictionary, day: int, kind: String, detail: Dictionary = {}) -> void:
	var entry := {"day": day, "kind": kind}; entry.merge(detail.duplicate(true))
	var history: Array = row.get("history", []); history.append(entry)
	if history.size() > Dragons.HISTORY_LIMIT: history = history.slice(-Dragons.HISTORY_LIMIT)
	row["history"] = history

static func daily(game, day: int) -> void:
	var registry: Dictionary = game.world.get("dragons", {}).get("records", {})
	var ids: Array = registry.keys(); ids.sort()
	var settled := false
	for uid in ids:
		var row: Dictionary = registry[uid]
		if not row.has("care"):
			initialize(row, int(floor(game.day)))
		var care: Dictionary = row["care"]
		if int(care["last_day"]) >= day or not row.get("alive", false): continue
		var context_started := Time.get_ticks_usec()
		var context := _context(game, row)
		Perf.record_us("Dragon care ownership reads", Time.get_ticks_usec() - context_started)
		var quote_started := Time.get_ticks_usec()
		var quote := _quote(game, row, day, context)
		Perf.record_us("Dragon care quotes", Time.get_ticks_usec() - quote_started)
		var food_units := 0; var food_cost := 0.0; var upkeep_units := 0; var upkeep_cost := 0.0
		var consumed := {}
		if quote["care_active"]:
			var e: Dictionary = context["econ"]; var f: Dictionary = context["family"]
			for order: Dictionary in quote["orders"]:
				var good := str(order["good"]); var quantity := int(order["quantity"]); var cost := float(order["cost"])
				Barge.add_demand(e, good, quantity, int(order["unmet"]), int(order["unaffordable"]))
				if quantity <= 0: continue
				TownEcon.pay_market(e, f, cost)
				e["stock"][good] = int(e["stock"][good]) - quantity
				TownEcon.led(e, "used", good, quantity)
				consumed[good] = quantity
				if good in MEAT: food_units += quantity; food_cost += cost
				else: upkeep_units += quantity; upkeep_cost += cost
		var egg := str(row.get("stage", "")) == "egg"
		var food_ratio := 1.0 if egg else clampf(float(food_units) / maxf(1, float(quote["food_need_units"])), 0, 1)
		var care_ratio := clampf(float(upkeep_units) / maxf(1, float(quote["upkeep_need_units"])), 0, 1)
		var health_before := float(quote["health"])
		var health := clampf(health_before + 0.005 * minf(food_ratio, care_ratio) - 0.018 * (1.0 - food_ratio) - 0.005 * (1.0 - care_ratio), 0, 1)
		var growth_before := float(quote["growth_points"])
		DragonGrowth.advance(row, 1.0, food_ratio, care_ratio, minf(health_before, health))
		care["last_day"] = day; care["health"] = health
		settled = true
		care["last"] = {"day": day, "payer_household_uid": quote["payer_household_uid"],
			"food_units": food_units, "food_cost": food_cost, "upkeep_units": upkeep_units, "upkeep_cost": upkeep_cost,
			"goods": consumed, "food_ratio": food_ratio, "care_ratio": care_ratio,
			"health_before": health_before, "health_after": health, "growth_before": growth_before,
			"growth_after": float(row.get("growth_points", growth_before)), "reason": quote["reason"]}
		var shortage := food_ratio < 0.8 or care_ratio < 0.8
		if shortage != bool(care.get("shortage", false)):
			_event(row, day, "care_shortage" if shortage else "care_restored", {"reason": quote["reason"]})
		care["shortage"] = shortage
		if not egg and str(row.get("stage", "")) == "juvenile" and (float(day) - float(row.get("birth_day", day))) >= DragonLife.MATURE_DAYS:
			row["stage"] = "adult"; _event(row, day, "matured")
		if health <= 0.0:
			row["alive"] = false; care["death_day"] = day
			_event(row, day, "care_death", {"reason": "Prolonged food or shelter shortage."})
			DragonBond.reconcile(game)
		# Existing native injuries rest once at this scheduled care boundary.
		# Readers/load never heal, rebuild bodies or advance dragon time.
		DragonCombat.on_care(game, str(uid), day)
	if settled: DragonLife.daily(game, day)   # hatching, maturing and breeding
