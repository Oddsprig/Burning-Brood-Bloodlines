extends RefCounted
## Read-only observations. No economic update, grants, or inferred sales ledger.

static func equal_json(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		if not is_finite(float(a)) or not is_finite(float(b)): return false
		if a is int and b is int: return a == b
		if a is int: return float(b) == floor(float(b)) and int(b) == a
		if b is int: return float(a) == floor(float(a)) and int(a) == b
		return a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for k in a:
			if not b.has(k) or not equal_json(a[k], b[k]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equal_json(a[i], b[i]): return false
		return true
	return typeof(a) == typeof(b) and a == b


static func difference_json(a, b, path: String = "") -> String:
	if equal_json(a, b): return ""
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k): return path + "/" + str(k) + ":missing"
			var bad: String = difference_json(a[k], b[k], path + "/" + str(k))
			if bad != "": return bad
		for k in b:
			if not a.has(k): return path + "/" + str(k) + ":extra"
	return path + ":expected=" + JSON.stringify(a, "", true, true) + ",actual=" + JSON.stringify(b, "", true, true)


static func equal_partition(a, b) -> bool:
	# Seven nonnegative group totals and JSON decimal round trips can differ by a
	# few double rounding steps. This applies only to additive observed metrics,
	# never to counts, save metadata, semantic hashes or native audit gates.
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for k in a:
			if not b.has(k) or not equal_partition(a[k], b[k]): return false
		return true
	if not (a is int or a is float) or not (b is int or b is float): return false
	if not is_finite(float(a)) or not is_finite(float(b)): return false
	if a == b: return true
	return absf(float(a) - float(b)) <= maxf(absf(float(a)), absf(float(b))) * (8.0 * 2.220446049250313e-16)


static func plain(value):
	# Native serializer handles Unit/Item/typed values; JSON makes Packed values plain.
	return JSON.parse_string(JSON.stringify(Game._serialize(value), "", true, true))


static func canonical(value):
	if value is Dictionary:
		var out: Dictionary = {}
		for k in value: out[str(k)] = canonical(value[k])
		return out
	if value is Array:
		var out: Array = []
		for x in value: out.append(canonical(x))
		return out
	if value is float and is_finite(value) and absf(value) <= 9007199254740991.0 and value == floor(value): return int(value)
	return value


static func digest(value) -> String:
	return JSON.stringify(canonical(value), "", true, true).sha256_text()


static func finite(value, path: String = "") -> String:
	if value is float and not is_finite(value): return path + ":nonfinite"
	if value is Dictionary:
		for k in value:
			var bad: String = finite(value[k], path + "/" + str(k))
			if bad != "": return bad
	elif value is Array:
		for i in value.size():
			var bad: String = finite(value[i], path + "/" + str(i))
			if bad != "": return bad
	return ""


static func physical(value, path: String) -> String:
	if value is int or value is float:
		if not is_finite(float(value)): return path + ":nonfinite"
		if value < 0: return path + ":negative_physical"
		return ""
	if value is Dictionary:
		for k in value:
			var bad: String = physical(value[k], path + "/" + str(k))
			if bad != "": return bad
		return ""
	return path + ":physical_field_not_numeric"


static func numeric(value, path: String = "") -> String:
	if value is int or value is float: return "" if is_finite(float(value)) else path + ":nonfinite"
	if value is Dictionary:
		for k in value:
			var bad: String = numeric(value[k], path + "/" + str(k))
			if bad != "": return bad
		return ""
	return path + ":not_numeric"


static func _holders(d: Dictionary, keys: Array, path: String) -> String:
	for k in keys:
		if not d.has(k): continue
		var bad: String = physical(d[k], path + "/" + str(k))
		if bad != "": return bad
	return ""


static func _treasure_rows(rows: Array, path: String) -> String:
	for row in rows:
		if not row is Dictionary: return path + ":bad_treasure_row"
		if not row.has("quantity"): continue
		var bad: String = physical(row["quantity"], path + "/quantity")
		if bad != "": return bad
		if float(row["quantity"]) != floor(float(row["quantity"])): return path + ":fractional_piece_count"
	return ""


static func validate_physical() -> String:
	var bad: String = physical(Game.gold, "company/gold")
	if bad != "": return bad
	for tid in Game.world.get("towns", {}):
		var t: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var path: String = "town/" + str(tid)
		bad = _holders(e, ["treasury", "farm_till", "land_fund", "stock", "barn", "hh", "gh", "granary"], path)
		if bad != "": return bad
		for b in e.get("biz", []):
			bad = physical(b.get("till", NAN), path + "/biz/" + str(b.get("id", "?")) + "/till")
			if bad != "": return bad
			bad = _treasure_rows(b.get("court_stock", []), path + "/business/court_stock")
			if bad != "": return bad
		for f in e.get("fams", []):
			bad = physical(f.get("purse", NAN), path + "/family/" + str(f.get("id", "?")) + "/purse")
			if bad != "": return bad
			bad = _holders(f, ["store", "gems"], path + "/family/" + str(f.get("id", "?")))
			if bad != "": return bad
			bad = _treasure_rows(f.get("hoard", []), path + "/family/" + str(f.get("id", "?")) + "/hoard")
			if bad != "": return bad
		for row in e.get("supply_orders", []):
			bad = _holders(row, ["reserved"], path + "/supply_order")
			if bad != "": return bad
	for key in ["factions", "lairs", "warbands"]:
		for id in Game.world.get(key, {}):
			var row: Dictionary = Game.world[key][id]
			bad = _holders(row, ["treasury", "loot", "gold", "stores"], key + "/" + str(id))
			if bad != "": return bad
			bad = _treasure_rows(row.get("loot_hoard", []), key + "/" + str(id) + "/loot_hoard")
			if bad != "": return bad
			bad = physical(row.get("cargo", {}).get("goods", {}), key + "/" + str(id) + "/cargo/goods")
			if bad != "": return bad
	bad = physical(Game.world.get("company_goods", {}), "company_goods")
	if bad != "": return bad
	for kind in Game.provisions:
		for lot in Game.provisions[kind]:
			if not lot is Array or lot.is_empty(): return "company/provisions:bad_lot"
			bad = physical(lot[0], "company/provisions/" + str(kind))
			if bad != "": return bad
	return ""


static func races() -> Array:
	var found: Dictionary = {}
	for t in Game.world.get("towns", {}).values():
		if TownEcon.has_econ(t): found[str(TownEcon.culture_of(t["econ"]).get("race", ""))] = true
	var out: Array = found.keys()
	out.sort()
	return out


static func maker_types() -> Dictionary:
	var out: Dictionary = {}
	var table = TownEcon.data().get("businesses", {})
	if not table is Dictionary: return out
	for type in table:
		var definition = table[type]
		if not definition is Dictionary or not definition.has("arms"): continue
		var arms = definition["arms"]
		if arms == null or (arms is Dictionary and arms.is_empty()) or (arms is Array and arms.is_empty()): continue
		if (arms is String and arms.is_empty()) or (arms is bool and not arms) or ((arms is int or arms is float) and arms == 0): continue
		out[str(type)] = plain(definition)
	return out


static func _sum(d: Dictionary) -> float:
	var n: float = 0.0
	for x in d.values(): n += float(x)
	return n


static func _add(to: Dictionary, from: Dictionary) -> void:
	for k in from:
		if from[k] is Dictionary:
			if not to.has(k): to[k] = {}
			_add(to[k], from[k])
		else: to[k] = to.get(k, 0) + from[k]


static func delta(now: Dictionary, before: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in now:
		if now[k] is Dictionary: out[k] = delta(now[k], before.get(k, {}))
		else: out[k] = now[k] - before.get(k, 0)
	for k in before:
		if now.has(k): continue
		if before[k] is Dictionary: out[k] = delta({}, before[k])
		else: out[k] = -before[k]
	return out


static func _census(e: Dictionary) -> Dictionary:
	var out: Dictionary = {"births": 0, "deaths": {}, "away": {}, "left": {}, "arrived": {}, "to": {}}
	var parts: Array = Census.rows(e).slice(1)
	parts.append(Census.current(e))
	for row in parts:
		out["births"] += int(row["births"])
		for k in ["deaths", "away", "left", "arrived", "to"]: _add(out[k], row.get(k, {}))
	return out


static func _empty_group() -> Dictionary:
	return {"towns": 0, "population": 0, "population_counter": 0, "households": 0, "hungry_households": 0,
		"hungry_people": 0, "famine_towns": 0, "hunger_stages": {}, "worked_acres": 0.0, "arable_acres": 0,
		"owned_acres": 0, "estate_acres": 0, "wage_population_sum": 0.0, "food_price_population_sum": {},
		"food_stocks": {}, "cash": {"treasury": 0.0, "farm_till": 0.0, "land_fund": 0.0, "business_tills": 0.0, "household_purses": 0.0},
		"debt_snapshot": 0.0, "wage_receipts_snapshot": 0.0, "census": {"births": 0, "deaths": {}, "away": {}, "left": {}, "arrived": {}, "to": {}},
		"family_store_native_snapshot": {"food": 0.0, "drink": 0.0, "wood": 0.0}, "native_made_cumulative": {}}


static func capture(race_keys: Array, types: Dictionary) -> Dictionary:
	var out: Dictionary = {"day": Game.day, "groups": {"WORLD": _empty_group()}, "towns": {}, "makers": {}}
	for race in race_keys: out["groups"][race] = _empty_group()
	for tid in Game.world.get("towns", {}):
		var t: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var race: String = str(TownEcon.culture_of(e).get("race", ""))
		if not out["groups"].has(race): return {"error": "unknown_native_town_race:" + race}
		var r: Dictionary = _empty_group()
		r["towns"] = 1
		r["population"] = Census.people(e)
		r["population_counter"] = int(e.get("pop", 0))
		r["census"] = _census(e)
		r["native_made_cumulative"] = e.get("led", {}).get("made", {}).duplicate()
		r["worked_acres"] = _sum(e.get("wacres", {}))
		var plots: Dictionary = Plots.totals(e)
		var owned: Dictionary = {}
		for fid in plots.get("own_crop", {}): owned[str(fid)] = Plots.acres_of(e, int(fid))
		r["arable_acres"] = int(plots.get("land", 0))
		r["owned_acres"] = int(_sum(owned))
		r["estate_acres"] = Plots.acres_of(e, 0)
		r["wage_population_sum"] = Barge.day_wage(e) * float(r["population"])
		for food in Supplies.FOOD:
			r["food_price_population_sum"][food] = float(e.get("price", {}).get(food, 0.0)) * float(r["population"])
			var stocks: Dictionary = {}
			for holder in ["stock", "barn", "hh", "gh"]: stocks[holder] = e.get(holder, {}).get(food, 0)
			stocks["granary"] = e.get("granary", 0) if str(food) == "grain" else 0
			r["food_stocks"][food] = stocks
		for k in ["treasury", "farm_till", "land_fund"]: r["cash"][k] = float(e.get(k, 0.0))
		for f in e.get("fams", []):
			r["cash"]["household_purses"] += float(f.get("purse", 0.0))
			r["debt_snapshot"] += float(f.get("debt", 0.0))
			r["wage_receipts_snapshot"] += float(f.get("wage_receipts", 0.0))
			for good in ["food", "drink", "wood"]: r["family_store_native_snapshot"][good] += float(f.get("store", {}).get(good, 0.0))
			if f.get("gone", false) or f.get("estate", false): continue
			r["households"] += 1
			var stage: int = int(f.get("hungry", 0))
			r["hunger_stages"][str(stage)] = int(r["hunger_stages"].get(str(stage), 0)) + 1
			if stage > 0:
				r["hungry_households"] += 1
				r["hungry_people"] += int(f["m"]) + int(f["f"]) + int(f["kids"]) + int(f["old"])
		r["famine_towns"] = 1 if int(e.get("fstage", 0)) >= 3 else 0
		for b in e.get("biz", []):
			r["cash"]["business_tills"] += float(b.get("till", 0.0))
			if not types.has(str(b.get("type", ""))): continue
			var key: String = str(tid) + ":" + str(b["id"])
			var active: bool = not bool(b.get("closed", false)) and int(b["id"]) in e.get("prod", [])
			var row: Dictionary = {"town": str(tid), "race": race, "id": b["id"], "type": b["type"], "till": b["till"],
				"closed": bool(b.get("closed", false)), "state": b.get("state", ""), "workers": b.get("workers", 0), "keeper_working": b.get("kw", 0),
				"wage": b.get("wage", 0.0), "owed": b.get("owed", 0.0), "claims": b.get("wage_claims", {}).duplicate(),
				"earned_wage_obligations_snapshot": b.get("wage_cost_day", 0.0), "native_wage_day": e.get("wage_day", null),
				"earned_wage_obligations_for_current_day": b.get("wage_cost_day", 0.0) if int(e.get("wage_day", -1)) == int(floor(Game.day)) else null,
				"p1_active_bookprofit_snapshot": b.get("p1", null) if active else null, "p14_snapshot": b.get("p14", null),
				"t_paid_adjustment_snapshot": b.get("t_paid", null), "net_receipts_rolling14_per_worker": b.get("net_receipts", []).duplicate(),
				"smoothed_input_spend_snapshot": b.get("spend", null), "kind_paid_snapshot": b.get("kind_paid", null),
				"stock_snapshot": b.get("stock", "UNAVAILABLE"), "individual_throughput": "UNAVAILABLE",
				"gross_sales": "UNAVAILABLE", "exact_input_expense": "UNAVAILABLE"}
			out["makers"][key] = row
		_add(out["groups"][race], r)
		out["towns"][str(tid)] = {"race": race, "metrics": r, "day_wage": Barge.day_wage(e), "prices": e.get("price", {}).duplicate(),
			"worked_by_crop": e.get("wacres", {}).duplicate(), "plots_totals": plots.duplicate(true), "owned_acres_by_fid": owned,
			"census_balance": Census.balance(e), "census_causes": Census.causes_of(Game.world, [tid]),
			"native_econ_day": e.get("day", null), "native_famine_stage": e.get("fstage", 0)}
	# Identical addition order makes WORLD exactly the partition into seven race groups.
	for race in race_keys: _add(out["groups"]["WORLD"], out["groups"][race])
	for group in out["groups"].values():
		var pop: float = float(group["population"])
		group["day_wage_population_mean"] = float(group["wage_population_sum"]) / pop if pop > 0 else null
		group["food_price_population_mean"] = {}
		for food in group["food_price_population_sum"]:
			group["food_price_population_mean"][food] = float(group["food_price_population_sum"][food]) / pop if pop > 0 else null
	return out


static func maker_changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Dictionary = {}
	for k in before: keys[k] = true
	for k in after: keys[k] = true
	for k in keys:
		var a: Dictionary = before.get(k, {})
		var b: Dictionary = after.get(k, {})
		out[k] = {"opening_till": a.get("till", null), "closing": b,
			"cash_delta": float(b["till"]) - float(a["till"]) if not a.is_empty() and not b.is_empty() else null,
			"opening_owed": a.get("owed", null), "opening_claims": a.get("claims", {}),
			"opened_or_disappeared": a.is_empty() or b.is_empty(), "closure_transition": a.get("closed", null) != b.get("closed", null)}
	return out


static func census_residual(before: Dictionary, after: Dictionary) -> int:
	var d: Dictionary = delta(after["census"], before["census"])
	return int(after["population"]) - int(before["population"]) - int(d["births"]) + int(_sum(d["deaths"])) - int(_sum(d["arrived"])) + int(_sum(d["left"]))


static func physical_signature(audit: Dictionary) -> Dictionary:
	# Holdings and identities only: never persist process-local audit counter indices as a resume gate.
	return {"day": Game.day, "coin": audit["coin"], "goods": audit["goods"], "treasure": audit["treasure"],
		"rations": audit["rations"], "items_held": audit["items"]["held"], "next_item_uid": audit["items"]["next"],
		"arms_held": {"armoury": audit["arms"]["armoury"], "shop": audit["arms"]["shop"], "cargo": audit["arms"]["cargo"]},
		"game_seed": Game.seed_value, "game_rng_state": str(Game.rng.state), "world_rng_state": str(Game.world.get("rng_state", ""))}
