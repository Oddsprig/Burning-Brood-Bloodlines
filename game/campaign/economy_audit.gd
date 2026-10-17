class_name EconomyAudit
extends RefCounted
## Read-only world audit. IDs identify evidence; no rule depends on a name or ID.

## Context for the retained raw full-market/low-till observation. A state tag
## alone is not proof of missed employee pay or of demand at the closing prices.
static func producer_cash_context(town: Dictionary, b: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var D := TownEcon.data()
	var T: Dictionary = D["businesses"][b["type"]]
	var workers := maxi(0, int(b["workers"]))
	var owed := maxf(0.0, float(b.get("owed", 0)))
	var till := float(b["till"])
	var owner: Dictionary = e["fams"][int(b["owner"])] if int(b["owner"]) >= 0 else {}
	var recipes := []
	for r in T["recipes"]:
		var ins := Businesses._recipe_inputs(e, D, r)
		var inputs := {}
		for good in ins:
			inputs[good] = {"batch_units": ins[good], "stock": e["stock"].get(good, 0), "price": e["price"].get(good, 0)}
		var outputs := {}
		for good in r["out"]:
			var cap := 2.0 if good == "home" else Businesses.stock_cap(e, good)
			outputs[good] = {"batch_units": r["out"][good], "stock": e["stock"].get(good, 0), "stock_cap": cap,
				"need": e.get("need", {}).get(good, 0), "demand": e.get("dem", {}).get(good, 0), "price": e["price"].get(good, 0),
				"aim": e.get("_aimu", {}).get(good, null), "aim_rest": e.get("_aimrest", {}).has(good)}
		var cost := Businesses._batch_cost(e, ins)
		var receipt := Businesses._batch_quote(e, r, float(D["market"]["buy_share"]))
		recipes.append({"inputs": inputs, "outputs": outputs, "batch_cost": cost, "batch_receipt": receipt, "batch_net_before_payroll_upkeep": receipt - cost})
	var result := {"keeper_only": workers == 0 and int(b.get("kw", 0)) > 0, "employee_daily_wages": workers * float(b["wage"]),
		"earned_wage_liability": owed, "unfunded_earned_wages": maxf(0.0, owed - till), "cash_after_earned_wages": maxf(0.0, till - owed),
		"owner_purse": owner.get("purse", null), "owner_last_turn": owner.get("last", null),
		"daily_upkeep": float(Barge.B()["business"]["upkeep"][0]) + float(Barge.B()["business"]["upkeep"][1]) * workers,
		"market_till": e["biz"][int(e["mkt"])]["till"], "recipes": recipes,
		"carry": b.get("carry", 0), "arms_carry": b.get("arms_carry", null), "legacy_mixed_carry_untyped": b.get("legacy_mixed_carry_untyped", null)}
	if String(b["type"]) == "mine":
		var ore := String(b.get("ore", "copper_ore"))
		result["mine_output"] = {"good": ore, "stock": e["stock"].get(ore, 0), "stop_stock": Businesses.stock_cap(e, ore) * 2.0,
			"need": e.get("need", {}).get(ore, 0), "demand": e.get("dem", {}).get(ore, 0), "price": e["price"].get(ore, 0)}
	if T.has("arms"):
		result["gear_market"] = {"shop_items": town.get("shop", []).size(), "shop_cap": Businesses.arms_cap(town),
			"current_orders": ArmsTrade.has_orders(e, String(T["arms"])), "tips_wanted": BowsEcon.tips_wanted(e) if String(T["arms"]) == "weapon" else false}
	return result

static func town_report(game, town: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var issues := []
	var idle := 0
	var rich_short := 0
	var living := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		living += 1
		idle += int(f.get("idle", 0))
		if float(f.get("fshort", 0)) > 0.01 and float(f.get("food_at_hunger_check", f.get("store", {}).get("food", 0))) >= float(f.get("food_days_needed", 7)):
			rich_short += 1
			issues.append({"rule": "household_hunger_with_food", "family": f["id"], "short_days": f["fshort"]})
	var vacancies := 0
	var empty_mines := 0
	var broke_full := 0
	var trades := {}
	var wages := []
	var business_rows := []
	var closed_wages := []
	for b in e["biz"]:
		if b.get("closed", false):
			if float(b.get("owed", 0)) > 0.005:
				closed_wages.append({"business": b["id"], "type": b["type"], "till": b["till"], "owed": b["owed"], "wage_claims": b.get("wage_claims", {}).duplicate(), "owed_unattributed": b.get("owed_unattributed", b["owed"])})
			continue
		var typ := String(b["type"])
		trades[typ] = true
		business_rows.append({"business": b["id"], "type": typ, "owner": b["owner"], "workers": b["workers"], "keeper": b.get("kw", 0), "cap": b["cap"], "funded_openings": Businesses.takeable(b), "wage": b["wage"], "till": b["till"], "owed": b.get("owed", 0), "state": b.get("state", ""), "blocked_good": b.get("fg", ""), "receipts_per_hand": b.get("net_receipts", []).duplicate(), "revenue_hand": b.get("revenue_hand", 0)})
		var wage_claims: Dictionary = b.get("wage_claims", {})
		var claimed := 0.0
		for fid in wage_claims: claimed += float(wage_claims[fid])
		var unattributed := float(b.get("owed_unattributed", maxf(0.0, float(b.get("owed", 0)) - claimed)))
		business_rows[-1]["wage_claims"] = wage_claims.duplicate()
		business_rows[-1]["owed_unattributed"] = unattributed
		if b.has("wage_claims") and absf(float(b.get("owed", 0)) - claimed - unattributed) > 0.01:
			issues.append({"rule": "wage_claim_balance_mismatch", "business": b["id"], "owed": b.get("owed", 0), "claims": claimed, "unattributed": unattributed})
		vacancies += maxi(0, int(b["cap"]) - int(b["workers"]))
		if typ == "mine" and int(b["workers"]) + int(b.get("kw", 0)) == 0: empty_mines += 1
		if b.get("state", "") == "full" and float(b["till"]) < float(b["wage"]):
			broke_full += 1
			issues.append({"rule": "full_market_broke_producer", "business": b["id"]})
			business_rows[-1]["full_market_cash_context"] = producer_cash_context(town, b)
		if b.has("revenue_hand"):
			var rev := float(b["revenue_hand"])
			wages.append({"business": b["id"], "wage": b["wage"], "net_revenue_hand": rev})
			if float(b["wage"]) > rev + 0.01 and int(b["workers"]) > 0:
				issues.append({"rule": "unaffordable_staff_wage", "business": b["id"], "wage": b["wage"], "revenue": rev})
	var armour := {}
	var unclassed := 0
	for item in town.get("armory_items", []):
		var c := ArmsTrade.cls(item.tid)
		if c == "": unclassed += 1
		else: armour[c] = int(armour.get(c, 0)) + 1
	var units := TownDefence.garrison(game, String(town["id"]))
	var garrison := units.filter(func(u): return u is Unit and not u.dead).size()
	var target := ArmsTrade.targets(game, town)
	var have_role := ArmsTrade.role_counts(armour)
	var target_role := ArmsTrade.role_counts(target)
	var surplus := {}
	for role in have_role:
		var extra := int(have_role[role]) - int(target_role.get(role, 0))
		if extra > 0: surplus[role] = extra
	# Surplus is real inventory from recovered/returned gear, not automatically an
	# economy fault. Report it separately; no deletion to force the audit to zero.
	if unclassed > 0: issues.append({"rule": "unmanaged_armoury_goods", "pieces": unclassed})
	var beds := int(e.get("barracks_beds", Militia.target_size(town)))
	if beds < garrison: issues.append({"rule": "beds_below_garrison", "beds": beds, "men": garrison})
	var land := {}
	var worked := 0.0
	var total := 0.0
	var P: Dictionary = e.get("plots", {})
	if not P.is_empty():
		for i in Plots.count(P):
			if int(P["use"][i]) in Plots.LAND_USES:
				var crop := String(P["crops"][int(P["sub"][i])])
				if P.has("variety") and P["variety"].size() > i and String(P["variety"][i]) != "": crop = String(P["variety"][i])
				var ac := float(P["ac"][i])
				land[crop] = float(land.get(crop, 0)) + ac
				total += ac
		for crop in e.get("wacres", {}): worked += float(e["wacres"][crop])
	for crop in land:
		if float(land[crop]) / maxf(1, total) > 0.6:
			issues.append({"rule": "crop_concentration", "crop": crop, "share": float(land[crop]) / maxf(1, total)})
	if float(e.get("land", {}).get("wood", 0)) > 0 and not trades.has("woodcutter"):
		issues.append({"rule": "woods_without_woodcutter"})
	if not e.get("herd", {}).is_empty() and not trades.has("butcher"):
		issues.append({"rule": "herds_without_butcher"})
	var sanitation: Dictionary = e.get("sanitation", {})
	if not sanitation.is_empty():
		if int(sanitation.get("rats", 0)) > int(sanitation.get("food_capacity", 0)):
			issues.append({"rule": "rats_above_food_capacity"})
		if float(sanitation.get("change_kg", 0)) > 0 and int(sanitation.get("cleaners", 0)) == 0:
			issues.append({"rule": "filth_rising_no_remover"})
		if float(sanitation.get("filth_kg", 0)) <= float(e["pop"]) * 5 and int(sanitation.get("cleaners_required", 0)) > int(ceil(float(e["pop"]) / 300)):
			issues.append({"rule": "healthy_town_excess_cleaners"})
	return {"town": town["id"], "population": Census.people(e), "families": living, "households_short_with_food": rich_short,
		"idle_adults": idle, "vacancies": vacancies, "unworked_mines": empty_mines, "broke_full_producers": broke_full,
		"businesses": business_rows, "closed_wage_balances": closed_wages, "market_till": e["biz"][int(e["mkt"])]["till"], "wages": wages, "armoury": armour, "unclassed_armoury": unclassed, "targets": target.duplicate(), "production_targets": e.get("arms_tgt", {}).duplicate(),
		"reserve_multiplier": ArmsTrade.RESERVE_MULTIPLIER, "retained_surplus": surplus, "stored_arrows": ArmsTrade.arrow_stock(town), "arrow_target": ArmsTrade.arrow_target(game, town),
		"garrison": garrison, "beds": beds, "crop_acres": land, "worked_acres": worked, "farmland_acres": total,
		"sanitation": sanitation.duplicate(true), "issues": issues}

static func world_report(game) -> Dictionary:
	var towns := []
	var failures := 0
	for town in game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var row := town_report(game, town)
		failures += row["issues"].size()
		towns.append(row)
	return {"seed": game.world.get("seed", 0), "day": game.day, "towns": towns, "issue_count": failures,
		"coins": Barge.holdings(game), "deferred_systems": ["sanitation"] if towns.any(func(t): return t["sanitation"].is_empty()) else []}
