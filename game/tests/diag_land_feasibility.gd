extends RefCounted

# Observational short town-only history, matching test_barge's seed901 scenario.
# Marginal projections and upper bounds are evidence; they never change assignments.
var snapshots := []

func run(_tree: SceneTree) -> int:
	Game.new_game(901)
	var w: Dictionary = Game.world
	# Preserve the registered units while running only economic jobs. Explicitly
	# removing forces is available solely to reproduce the historical bad fixture.
	var keep_forces := OS.get_environment("LAND_REMOVE_FORCES") != "1"
	if not keep_forces:
		for wid in w["warbands"].keys(): CampaignWorld.remove_warband(Game, wid)
	w["work"] = []
	capture(w)
	var days := 60 if OS.get_environment("LAND_DAYS") == "" else int(OS.get_environment("LAND_DAYS"))
	for i in days:
		var day := int(w.get("last_day", 0)) + 1
		w["last_day"] = day; Game.day = float(day); w["work"] = []
		TownEcon.queue_day(w, day)
		while not (w["work"] as Array).is_empty():
			TownEcon.do_job(Game, w["work"].pop_front())
		if day in [1, 7, 14] or day % 30 in [0, 7, 29] or day == days: capture(w)
	var path := OS.get_environment("LAND_DIAG")
	if path == "": path = "user://land_feasibility.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed": 901, "town_only": true, "days_requested": days, "kept_forces": keep_forces, "snapshots": snapshots})); file.close()
	print("LAND FEASIBILITY wrote ", path)
	return 0

func capture(w: Dictionary) -> void:
	var snap := {"day": Game.day, "season": Calendar.season(Game.day), "towns": []}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		var town := {"id": tid, "name": t["name"], "culture": e["culture"], "climate": e["climate"], "specialty": t.get("specialty", ""), "population": e["pop"], "families": [], "businesses": [], "herd_records": [], "casual_capacity": e.get("cjcap", {}), "casual_used": e.get("cjused", {}), "child_casual_used": e.get("child_cjused", {}), "labour_demand": e.get("ldem", 0), "labour_supply": e.get("lsup", 0), "day_wage": e.get("dwage", 0), "land": e["land"], "worked": e["wacres"], "herd": e["herd"], "fit": e.get("fit", {})}
		var P: Dictionary = e.get("plots", {})
		CropRotation.ensure(e, P, Game.day)
		town["food_balance"] = food_balance(e)
		town["resources"] = {"barn": e.get("barn", {}), "stock": e.get("stock", {}), "granary": e.get("granary", 0), "household_stock": e.get("hh", {}), "farm_till": e.get("farm_till", 0), "treasury": e.get("treasury", 0), "demand": e.get("dem", {}), "business_input_demand": e.get("bdem", {}), "market_cover_target": e.get("need", {})}
		town["rotation"] = {"crop_mix": e.get("crop_mix", {}), "nominal": 0.0, "fallow": 0.0, "planted": 0.0, "worked_fallow": 0.0, "worked_planted": 0.0}
		for pi in Plots.count(P):
			if not int(P["use"][pi]) in Plots.LAND_USES: continue
			var fid := int(P["own"][pi]); var ac := float(P["ac"][pi])
			var wf := float(e["fams"][fid].get("worked", 0.0)) if fid >= 0 and fid < e["fams"].size() else 0.0
			var is_fallow := String(P["variety"][pi]) == "fallow"
			town["rotation"]["nominal"] += ac
			town["rotation"]["fallow" if is_fallow else "planted"] += ac
			town["rotation"]["worked_fallow" if is_fallow else "worked_planted"] += ac * wf
		town["births"] = e.get("stats", {}).get("births", 0)
		town["deaths"] = e.get("stats", {}).get("deaths", 0)
		town["deaths_by_cause"] = Census.deaths_by_cause(e)
		town["person_states"] = {}
		for f in e["fams"]:
			for p in f.get("pp", []):
				var state := String(p[4])
				town["person_states"][state] = int(town["person_states"].get(state, 0)) + 1
		for original in e["fams"]:
			if original.get("gone", false): continue
			var f: Dictionary = original.duplicate(true)
			var need := Families.need_hands(f, e)
			var helper := 0.0 if f.get("estate", false) else minf(need, Barge.helper_hands(e, f, Game.day))
			var acreage := Families.acres(f)
			var ox_acres := minf(acreage, float(f.get("ox", -1)) * 8.0) if int(f.get("ox", -1)) >= 0 else float(acreage)
			var crop_work := Families.crop_work(f, e)
			var crop_hands := float(crop_work["base"])
			var farm_id := int(f.get("farm", -1))
			var farm: Dictionary = e["biz"][farm_id] if farm_id >= 0 else {}
			var output := Barge.output_mult(int(f.get("hungry", 0))) if not f.get("estate", false) else 1.0
			var revenue := EconomyRules.farm_hand_value(e, f)
			var marginal := minf(1.0, 1.0 / need) * acreage * output if need > 0.0 else 0.0
			var crops := {}
			for crop in f["land"]:
				var yield_v := CropRotation.family_yield(e, f, String(crop))
				if crop in ["grain", "fruit"]: yield_v *= float(TownEcon.data()["climates"][e["climate"]][String(crop) + "_yield"])
				crops[crop] = {"acres": f["land"][crop], "hands_with_current_ox": float(f["land"][crop]) / maxf(1.0, acreage) * crop_hands, "annual_yield_per_acre": yield_v, "price": e.get("price", {}).get(crop, 0), "potential_daily_output": float(f["land"][crop]) * yield_v / EconGen.YEAR_DAYS}
			var row := {"id": f["id"], "estate": f.get("estate", false), "adults": Families.adults(f), "serving": Families.serving(f), "own_hands": f["hands"], "keepers": f.get("keeps", []), "jobs": f["jobs"], "casual": f.get("cj", {}), "child_casual": f.get("child_cj", {}), "idle": f.get("idle", 0), "helpers": helper, "acres": acreage, "crop_hands": crop_hands, "herd_hands": Families.herd_hands(f, e), "crop_work": crop_work, "seasonal_need": Families.seasonal_need_hands(f, Game.day, e), "need": need, "ox": f.get("ox", -1), "herd": f["herd"], "crops": crops, "worked": f["worked"], "output_mult": output, "farm_id": farm_id, "hired": farm.get("workers", 0), "farm_cap": farm.get("cap", 0), "farm_funded": Businesses.takeable(farm) if not farm.is_empty() else 0, "farm_wage": farm.get("wage", 0), "farm_hand_value": revenue, "own_land_worth": Families.land_worth(e, f, need), "marginal_acres_per_hand": marginal}
			row["farm_harvest"] = f.get("farm_harvest", null)
			row["cash_resources"] = {"purse": f.get("purse", 0), "income_week": f.get("inc", 0), "larder_days": f.get("store", {}).get("food", 0), "farm_till": farm.get("till", 0), "farm_owed": farm.get("owed", 0), "farm_tools": farm.get("tools", 0), "farm_owner": farm.get("owner", -1), "farm_actual_pay": farm.get("t_paid", 0)}
			town["families"].append(row)
		for b in e["biz"]:
			if b.get("closed", false): continue
			town["businesses"].append({"id": b["id"], "type": b["type"], "owner": b["owner"], "workers": b["workers"], "keeper": b.get("kw", 0), "cap": b["cap"], "funded": Businesses.takeable(b), "wage": b["wage"], "state": b["state"], "why": b.get("why", ""), "till": b["till"], "owed": b["owed"], "revenue_hand": b.get("revenue_hand", 0), "net_receipts": b.get("net_receipts", [])})
		for h in Herds.herds(e).values():
			town["herd_records"].append({"id": h["id"], "kind": h["k"], "owner_kind": h["ow"], "owner_id": h["oi"], "heads": Herds.head(h), "grown_equivalent": Herds.ge(h), "per_hand": Herds.kind(String(h["k"])).get("per_hand", 25)})
		snap["towns"].append(town)
	# Town maps and receipt histories originate in the live economy. Freeze this
	# checkpoint now so later ordinary turns cannot rewrite its evidence.
	snapshots.append(snap.duplicate(true))
	print("LAND SNAPSHOT day=", Game.day, " towns=", snap["towns"].size())

# Snapshot forecasts freeze today's work, crops, tools, manure and weather for a
# year. They are explicitly distinct from the cumulative observed made/used
# ledger and the dated food already owned/reserved. No goods are created here.
func food_balance(e: Dictionary) -> Dictionary:
	var D := TownEcon.data()
	var climate: Dictionary = D["climates"][e["climate"]]
	var hf := float(e.get("hf_now", 1.0))
	var manure := Herds.manure_f(e)
	var toolf := 0.75 + 0.25 * minf(1.0, float(e.get("hh", {}).get("tools", 0)) / maxf(1.0, float(e.get("hands", 0)) + float(e["adults"]) * 0.3))
	var tax := float(D["tax"]["grain_share"])
	if e.get("ruler", {}).get("kind", "coin") == "kind": tax += float(e["ruler"].get("tribute", 0.0))
	var diet := Barge.diet(e)
	var bs := EconGen.beer_share_of(e)
	var drink_annual := float(e["adults"]) * float(D["needs"]["drink_adult"]) * EconGen.YEAR_DAYS
	var input_need := {"grain": drink_annual * bs * 0.5, "fruit": drink_annual * (1.0 - bs)}
	var forecast := {}
	for mode in ["full_staff", "current_work"]:
		forecast[mode] = {"gross_before_modifiers": {"grain": 0.0, "fruit": 0.0}, "net_after_modifiers_tax": {"grain": 0.0, "fruit": 0.0}, "predicted_owner_year_reserves": {"grain": 0.0, "fruit": 0.0}, "remaining_market_food_need": {"grain": 0.0, "fruit": 0.0}, "business_input_need": input_need.duplicate(), "market_surplus": {}, "market_shortfall": {}, "annual_food_budget": 0.0}
	var actual := {"owned": {"grain": 0.0, "fruit": 0.0}, "reserved": {"grain": 0.0, "fruit": 0.0}, "owner_reserve_budget_after_larder": 0.0, "owner_reserve_shortfall": 0.0}
	var eaters := 0.0
	for original in e["fams"]:
		if original.get("gone", false): continue
		# Barge's weekly age cache belongs to the live economy; diagnostics do not
		# alter it while reading the independent family's budget.
		var f: Dictionary = original.duplicate(true)
		var eq := float(Barge.eaters(e, f, float(e.get("day", 0)))[0])
		var budget := 0.0 if f.get("estate", false) else eq * float(D["needs"]["food"]) * EconGen.YEAR_DAYS
		if not f.get("estate", false): eaters += eq
		var reserve_budget := maxf(0.0, (EconGen.YEAR_DAYS - maxf(0.0, float(f.get("store", {}).get("food", 0)))) * eq * float(D["needs"]["food"])) if not f.get("estate", false) else 0.0
		var actual_reserved := 0.0
		for good in ["grain", "fruit"]:
			actual["owned"][good] += HarvestClaims.owned(e, "f:%d" % int(f["id"]), good)
			var reserved := HarvestClaims.owned(e, "f:%d" % int(f["id"]), good, true)
			actual["reserved"][good] += reserved
			actual_reserved += reserved
		actual["owner_reserve_budget_after_larder"] += reserve_budget
		actual["owner_reserve_shortfall"] += maxf(0.0, reserve_budget - actual_reserved)
		for mode in forecast:
			var row: Dictionary = forecast[mode]
			row["annual_food_budget"] += budget
			var available_budget := budget
			for good in ["grain", "fruit"]:
				var gross := float(f["land"].get(good, 0)) * CropRotation.family_yield(e, f, good) * float(climate[good + "_yield"])
				if mode == "current_work": gross *= float(f.get("worked", 0))
				var net := gross * toolf * hf * manure * (1.0 - tax if good == "grain" else 1.0)
				row["gross_before_modifiers"][good] += gross
				row["net_after_modifiers_tax"][good] += net
				var kept := minf(available_budget, maxf(0.0, net))
				row["predicted_owner_year_reserves"][good] += kept
				available_budget -= kept
			var uncovered_eq := available_budget / float(D["needs"]["food"])
			for good in ["grain", "fruit"]: row["remaining_market_food_need"][good] += uncovered_eq * float(diet[good])
	for mode in forecast:
		var row: Dictionary = forecast[mode]
		for good in ["grain", "fruit"]:
			var surplus := float(row["net_after_modifiers_tax"][good]) - float(row["predicted_owner_year_reserves"][good])
			var need := float(row["remaining_market_food_need"][good]) + float(row["business_input_need"][good])
			row["market_surplus"][good] = surplus
			row["market_shortfall"][good] = maxf(0.0, need - surplus)
	var policy := CropRotation.new()
	var mean := float(policy.call("mean_yield", e)) if policy.has_method("mean_yield") else float(D["land"]["yield"]["grain"])
	return {"basis": "annualized snapshot potential; no future work, weather, spoilage, population, price or trade assumed", "rotation_mean_before_climate": mean, "actual_meal_equivalents": eaters, "tool_factor": toolf, "weather_factor": hf, "manure_factor": manure, "grain_tax_share": tax, "forecast": forecast, "actual_owned_food": actual, "actual_cumulative_ledger": {"made": e.get("led", {}).get("made", {}), "used": e.get("led", {}).get("used", {}), "spoil": e.get("led", {}).get("spoil", {})}, "inventory_cover": e.get("need", {}), "limits": "food partition counts each household once; at-base annual drink inputs; supplemental orders share the food larder; actual market inventory/spoilage/trade are separately observed"}
