extends RefCounted
## Ordinary campaign evidence; the same script is usable on delivered v045.
## No fixed raids, force removal, injected resources, or new production APIs.
## Builders receive copied economies. Simulation timing excludes all collection.

const HarvestAudit = preload("res://tests/diag_economy_audit.gd")
const FOOD := ["grain", "fruit", "meat", "fresh_meat", "milk", "beer", "wine"]
const CHECKPOINTS := [0, 1, 7, 14, 29, 30, 37, 59, 60, 67, 89, 90, 97, 119, 120, 127, 149, 150, 157, 179, 180, 187, 209, 210, 217, 239, 240]
const ABS_TOL := 0.000001
const REL_TOL := 0.0000000001
const COIN_TOL := 1.0 # Existing test_barge worst daily global ledger gate (<1).
var failures := 0
var checks := 0
var first_failures := []
var output := ""
var samples := []
var daily := []
var audit = HarvestAudit.new()
var day120_target := {"applicable": false, "evaluated": false, "minimum": 0.90, "passed": null}

func check(ok: bool, rule: String, detail: Dictionary = {}) -> void:
	checks += 1
	if ok: return
	failures += 1
	if first_failures.size() < 40:
		var row := {"day": Game.day, "rule": rule}
		row.merge(detail)
		first_failures.append(row)
		printerr("FAIL: ", rule, " ", JSON.stringify(detail, "", true, true))

func near(a: float, b: float) -> bool:
	return absf(a - b) <= ABS_TOL + REL_TOL * maxf(absf(a), absf(b))

func sum_values(d: Dictionary) -> float:
	var total := 0.0
	for value in d.values(): total += float(value)
	return total

func food_values(d: Dictionary) -> Dictionary:
	var out := {}
	for good in FOOD: out[good] = d.get(good, 0)
	return out

func add_values(to: Dictionary, from: Dictionary) -> void:
	for key in from: to[key] = float(to.get(key, 0)) + float(from[key])

## Independent ages and row shares, without Barge's weekly age cache.
## The existing away-food classification is army/bandit/deserter; company
## records have already left row counts. Broth excludes home shares once.
func meals(e: Dictionary, f: Dictionary) -> Dictionary:
	var kids := int(f.get("kids", 0))
	var older := 0
	var threshold := float(People.ages(Persons.race_of(e))["adult"]) / 16.0 * 10.0 * People.year_days()
	for p in f.get("kp", []):
		if Game.day - float(p[3]) >= threshold: older += 1
	older = mini(older, kids)
	var total := float(Families.adults(f) + int(f.get("old", 0))) + float(kids - older) * 0.6 + float(older) * 0.8
	var away := 0.0
	for role in ["army", "bandit", "deserter"]: away += float(f.get("serve", {}).get(role, 0))
	away = minf(total, away)
	var home := maxf(0.0, total - away)
	var broth := home if f.get("shel", false) and f.get("broth", false) else 0.0
	return {"total": total, "away": away, "home": home, "broth": broth, "pooled": home - broth, "older_children": older, "small_children": kids - older}

func coin_sample() -> Dictionary:
	var ledger: Dictionary = Game.world.get("coin", {})
	check(not ledger.is_empty(), "global coin ledger exists")
	var held := Barge.holdings(Game)
	var expected := float(ledger.get("cast", 0)) - float(ledger.get("melted", 0)) - float(ledger.get("drained", 0))
	check(absf(held - expected) < COIN_TOL, "global coin ledger", {"held": held, "expected": expected, "gap": held - expected})
	return {"held": held, "cast": ledger.get("cast", 0), "melted": ledger.get("melted", 0), "drained": ledger.get("drained", 0), "gap": held - expected, "tolerance": COIN_TOL}

func daily_totals() -> Dictionary:
	var out := {"population": 0, "nominal": 0.0, "actual_worked": 0.0, "market": {}, "barn": {}, "household": {}, "made": {}, "used": {}, "spoil": {}, "granary": 0}
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		out["population"] += int(e.get("pop", 0))
		out["nominal"] += sum_values(e.get("land", {}))
		out["actual_worked"] += sum_values(e.get("wacres", {}))
		out["granary"] += int(e.get("granary", 0))
		for pool in ["market", "barn", "household"]:
			var key := "stock" if pool == "market" else ("hh" if pool == "household" else "barn")
			add_values(out[pool], food_values(e.get(key, {})))
		for pool in ["made", "used", "spoil"]: add_values(out[pool], food_values(e.get("led", {}).get(pool, {})))
	return out

func write_json(name: String, data: Variant) -> void:
	var file := FileAccess.open(output.path_join(name), FileAccess.WRITE)
	check(file != null, "output writable", {"file": name})
	if file != null:
		file.store_string(JSON.stringify(data, "\t", true, true))
		file.close()

func capture(step: int) -> Dictionary:
	var whole := {"nominal": 0.0, "actual_worked": 0.0, "planted": 0.0, "fallow": 0.0, "worked_planted": 0.0, "worked_fallow": 0.0, "population": 0, "register_people": 0, "assignment_discrepancies": 0, "worker_discrepancies": 0, "idle_adults": 0, "funded_places": 0, "hungry_households": 0, "short_food_days": 0.0, "warnings": 0}
	var world_meals := {"total": 0.0, "away": 0.0, "home": 0.0, "broth": 0.0, "pooled": 0.0, "older_children": 0, "small_children": 0}
	var world_food := {"market": {}, "barn": {}, "household": {}, "made": {}, "used": {}, "spoil": {}, "granary": 0}
	var warning_counts := {}
	var towns := []
	var world_balance := {"births": 0, "deaths": 0, "arrived": 0, "left": 0, "people": 0, "last": 0, "change": 0}
	var tids: Array = Game.world["towns"].keys(); tids.sort()
	(audit.harvest_report["sample_days"] as Array).append(int(Game.day))
	for tid in tids:
		var original: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(original): continue
		var live_e: Dictionary = original["econ"]
		var before := JSON.stringify(live_e, "", false, true).sha256_text()
		var town: Dictionary = original.duplicate()
		var e: Dictionary = live_e.duplicate(true); town["econ"] = e
		var P: Dictionary = e.get("plots", {})
		CropRotation.ensure(e, P, Game.day)
		var land := {"nominal": sum_values(e.get("land", {})), "actual_worked": sum_values(e.get("wacres", {})), "planted": 0.0, "fallow": 0.0, "worked_planted": 0.0, "worked_fallow": 0.0, "plot_nominal": 0.0, "plot_worked": 0.0}
		var owner_crops := {}
		var plot_rows := []
		for pi in Plots.count(P):
			if not int(P["use"][pi]) in Plots.LAND_USES: continue
			var fid := int(P["own"][pi]); var acres := float(P["ac"][pi])
			var crop := String(P["crops"][int(P["sub"][pi])])
			var variety := String(P["variety"][pi])
			var worked := float(e["fams"][fid].get("worked", 0)) if fid >= 0 and fid < e["fams"].size() else 0.0
			check(fid >= 0 and fid < e["fams"].size(), "plot owner exists", {"town": tid, "plot": pi, "owner": fid})
			if not owner_crops.has(fid): owner_crops[fid] = {}
			owner_crops[fid][crop] = float(owner_crops[fid].get(crop, 0)) + acres
			land["plot_nominal"] += acres; land["plot_worked"] += acres * worked
			land["fallow" if variety == "fallow" else "planted"] += acres
			land["worked_fallow" if variety == "fallow" else "worked_planted"] += acres * worked
			plot_rows.append({"plot": pi, "owner": fid, "crop": crop, "variety": variety, "acres": acres, "worked_fraction": worked, "soil": P["soil"][pi], "rotation_phase": P["rotation_phase"][pi]})
		check(near(float(land["nominal"]), float(land["plot_nominal"])), "nominal plot/books equality", {"town": tid, "land": land})
		check(near(float(land["actual_worked"]), float(land["plot_worked"])), "worked plot/books equality", {"town": tid, "land": land})
		var families := []; var workers := {}; var local_meals := world_meals.duplicate()
		for key in local_meals: local_meals[key] = 0
		var local := {"population": 0, "register_people": 0, "assignment_discrepancies": 0, "worker_discrepancies": 0, "idle_adults": 0, "funded_places": 0, "hungry_households": 0, "short_food_days": 0.0}
		for f in e["fams"]:
			var fid := int(f["id"])
			var crops: Dictionary = owner_crops.get(fid, {})
			var keys := crops.duplicate()
			for crop in f.get("land", {}): keys[crop] = true
			for crop in keys:
				check(near(float(f.get("land", {}).get(crop, 0)), float(crops.get(crop, 0))), "holder plot/books equality", {"town": tid, "family": fid, "crop": crop})
			if f.get("gone", false) or f.get("estate", false): continue
			var registered: int = f.get("kp", []).size()
			var home_adults := 0
			for p in f.get("pp", []):
				if not String(p[4]) in Persons.AWAY: registered += 1
				if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]: home_adults += 1
			var assigned: int = int(f.get("hands", 0)) + f.get("keeps", []).size() + int(f.get("idle", 0))
			for bid in f.get("jobs", {}):
				var n := int(f["jobs"][bid]); assigned += n
				workers[int(bid)] = int(workers.get(int(bid), 0)) + n
			for n in f.get("cj", {}).values(): assigned += int(n)
			var available := maxi(0, Families.adults(f) - Families.serving(f))
			var delta := assigned - available
			if delta != 0: local["assignment_discrepancies"] += 1
			check(delta == 0, "individual adult assignment", {"town": tid, "family": fid, "assigned": assigned, "available": available, "register_home_adults": home_adults})
			check(home_adults == available, "civilian register availability", {"town": tid, "family": fid, "register_home_adults": home_adults, "available": available})
			check(registered == Families.people(f), "individual register population", {"town": tid, "family": fid, "registered": registered, "people": Families.people(f)})
			var shares := meals(e, f); add_values(local_meals, shares)
			local["population"] += Families.people(f); local["register_people"] += registered
			local["idle_adults"] += int(f.get("idle", 0))
			local["hungry_households"] += 1 if int(f.get("hungry", 0)) > 0 else 0
			local["short_food_days"] += float(f.get("fshort", 0))
			families.append({"id": fid, "people": Families.people(f), "registered": registered, "adults": Families.adults(f), "serving": f.get("serve", {}).duplicate(), "home_adults": home_adults, "keepers": f.get("keeps", []).duplicate(), "own_hands": f.get("hands", 0), "jobs": f.get("jobs", {}).duplicate(), "casual": f.get("cj", {}).duplicate(), "child_casual": f.get("child_cj", {}).duplicate(), "idle": f.get("idle", 0), "assignment_delta": delta, "land": f.get("land", {}).duplicate(), "herd": f.get("herd", {}).duplicate(), "ox": f.get("ox", -1), "need_hands": Families.need_hands(f, e), "seasonal_need": Families.seasonal_need_hands(f, Game.day, e), "worked": f.get("worked", 0), "meal_shares": shares, "food_days": f.get("store", {}).get("food", 0), "hungry": f.get("hungry", 0), "short_days": f.get("fshort", 0), "broth": f.get("broth", false), "purse": f.get("purse", 0), "debt": f.get("debt", 0), "farm": f.get("farm", -1), "last": f.get("last", 0), "income_parts": f.get("income_parts", {}).duplicate(), "harvest_receipts": f.get("harvest_receipts", 0), "land_pay": f.get("lpay", 0), "farm_funding_pending": f.get("farm_funding_pending", 0)})
		var farms := []
		for b in e["biz"]:
			var bid := int(b["id"]); var staff := int(workers.get(bid, 0))
			if staff != int(b["workers"]): local["worker_discrepancies"] += 1
			check(staff == int(b["workers"]), "employer worker count", {"town": tid, "business": bid, "type": b["type"], "registered_jobs": staff, "workers": b["workers"]})
			local["funded_places"] += Businesses.takeable(b)
			if String(b["type"]) in ["farm", "estate"]:
				farms.append({"id": bid, "type": b["type"], "owner": b["owner"], "closed": b.get("closed", false), "cap": b["cap"], "workers": b["workers"], "keeper": b.get("kw", 0), "funded": Businesses.takeable(b), "wage": b["wage"], "till": b["till"], "owed": b.get("owed", 0), "claims": b.get("wage_claims", {}).duplicate(), "owed_unattributed": b.get("owed_unattributed", 0), "actual_pay_offset": b.get("t_paid", 0), "receipts": b.get("net_receipts", []).duplicate(), "wage_cost_period": b.get("wage_cost_period", 0), "revenue_hand": b.get("revenue_hand", 0)})
		var census := Census.balance(e); var rows := Census.rows(e)
		check(Census.adds_up(census), "current census balance", {"town": tid, "balance": census})
		for i in range(1, rows.size()): check(Census.adds_up(Census.row_balance(rows, i)), "season census balance", {"town": tid, "row": i})
		check(int(e["pop"]) == int(local["population"]), "town population recount", {"town": tid, "econ": e["pop"], "families": local["population"]})
		add_values(world_balance, census)
		var food := {"market": food_values(e.get("stock", {})), "barn": food_values(e.get("barn", {})), "household": food_values(e.get("hh", {})), "made": food_values(e.get("led", {}).get("made", {})), "used": food_values(e.get("led", {}).get("used", {})), "spoil": food_values(e.get("led", {}).get("spoil", {})), "granary": e.get("granary", 0), "carry": e.get("carry", {}).duplicate(true), "prices": food_values(e.get("price", {})), "meal_shares": local_meals, "recorded_broth_people": e.get("broth_n", 0), "recorded_away_people": e.get("away_n", 0), "food_short": e.get("food_short", 0), "owned_balances": e.get("harvest_book", {}).get("balances", {}).duplicate(true)}
		for pool in ["market", "barn", "household", "made", "used", "spoil"]: add_values(world_food[pool], food[pool])
		world_food["granary"] += int(food["granary"])
		var economy := EconomyAudit.town_report(Game, town)
		for issue in economy["issues"]:
			var rule := String(issue["rule"]); warning_counts[rule] = int(warning_counts.get(rule, 0)) + 1
		whole["warnings"] += economy["issues"].size()
		audit.harvest_town(town, int(Game.day))
		check(before == JSON.stringify(live_e, "", false, true).sha256_text(), "checkpoint readers preserve live economy", {"town": tid})
		for key in local: whole[key] += local[key]
		for key in ["nominal", "actual_worked", "planted", "fallow", "worked_planted", "worked_fallow"]: whole[key] += land[key]
		add_values(world_meals, local_meals)
		local["idle_funded_overlap"] = mini(int(local["idle_adults"]), int(local["funded_places"]))
		towns.append({"id": tid, "name": town["name"], "culture": e["culture"], "climate": e["climate"], "specialty": town.get("specialty", ""), "land": land, "land_by_crop": e.get("land", {}).duplicate(), "worked_by_crop": e.get("wacres", {}).duplicate(), "plots": plot_rows, "labour": local, "families": families, "farms": farms, "food": food, "census": census, "census_rows": rows.duplicate(true), "deaths_by_cause": Census.deaths_by_cause(e), "treasury": e.get("treasury", 0), "farm_till": e.get("farm_till", 0), "economy_audit": economy})
	check(Census.adds_up(world_balance), "whole-world census balance")
	check(int(audit.harvest_report["violation_count"]) == 0, "harvest physical ownership reconciliation", {"violations": audit.harvest_report["violation_count"]})
	whole["worked_fraction"] = float(whole["actual_worked"]) / maxf(1.0, float(whole["nominal"]))
	var cargo := []
	for wid in Game.world.get("warbands", {}):
		var band: Dictionary = Game.world["warbands"][wid]
		if String(band.get("kind", "")) == "caravan": cargo.append({"id": wid, "origin": band.get("origin", ""), "goods": food_values(band.get("cargo", {}).get("goods", {}))})
	var snap := {"day": Game.day, "elapsed_days": step, "season": Calendar.season(Game.day), "year": Calendar.year(Game.day), "whole_world": whole, "meal_shares": world_meals, "food_totals": world_food, "census": world_balance, "warnings_by_rule": warning_counts, "coin": coin_sample(), "company_provisions": Game.provisions.duplicate(true), "caravan_food": cargo, "towns": towns}
	var filename := "checkpoint-%03d.json" % step
	write_json(filename, snap)
	samples.append({"elapsed_days": step, "day": Game.day, "file": filename, "whole_world": whole, "meal_shares": world_meals, "food_totals": world_food, "census": world_balance, "warnings_by_rule": warning_counts})
	print("V046 CHECKPOINT day=", Game.day, " towns=", towns.size(), " worked=", whole["worked_fraction"], " warnings=", whole["warnings"], " functional_failures=", failures)
	return whole

func run(_tree: SceneTree) -> int:
	output = OS.get_environment("V046_OUTPUT")
	if output.is_empty(): printerr("V046_OUTPUT is required"); return 1
	check(DirAccess.make_dir_recursive_absolute(output) == OK, "output directory writable")
	if failures > 0: return failures
	var source := OS.get_environment("V046_SAVE")
	var size := OS.get_environment("V046_SIZE").to_lower()
	if size.is_empty(): size = "normal"
	check(size in ["normal", "large", "huge"], "supported declared world size", {"size": size})
	var seed_text := OS.get_environment("V046_SEED")
	var seed := 901 if seed_text.is_empty() else int(seed_text)
	var days := 120 if source.is_empty() else 28
	if not OS.get_environment("V046_DAYS").is_empty(): days = int(OS.get_environment("V046_DAYS"))
	check(days > 0 and days <= 600, "bounded positive duration", {"days": days})
	if failures > 0: return failures
	var begin := Time.get_ticks_usec()
	if source.is_empty():
		WorldGen.gen_size = size
		Game.new_game(seed)
	else:
		check(FileAccess.file_exists(source), "authentic input checkpoint exists")
		if failures > 0: return failures
		var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		check(file != null, "isolated save writable")
		if file == null: return failures
		file.store_string(FileAccess.get_file_as_string(source)); file.close()
		check(Game.load_game(), "actual checkpoint loader succeeds")
		if failures > 0: return failures
	var setup_us := Time.get_ticks_usec() - begin
	var start_day := Game.day
	audit.harvest_report["available"] = true
	day120_target["applicable"] = source.is_empty() and start_day <= 120.0 and start_day + float(days) >= 120.0
	CampaignWorld.job_total = {}; CampaignWorld.job_worst = {}
	CampaignWorld.daily_total = {}; CampaignWorld.steps_total = 0; CampaignWorld.step_parts = {}
	capture(0)
	for step in range(1, days + 1):
		begin = Time.get_ticks_usec()
		Game.advance_time(1.0, true)
		var elapsed := Time.get_ticks_usec() - begin
		check(near(Game.day, start_day + float(step)), "ordinary campaign advances exactly one day", {"elapsed_days": step})
		var coins := coin_sample()
		daily.append({"day": Game.day, "elapsed_days": step, "simulation_us": elapsed, "coin": coins, "whole_world": daily_totals()})
		if CHECKPOINTS.has(int(Game.day)) or step == days or (not source.is_empty() and step % 7 == 0):
			var whole := capture(step)
			if day120_target["applicable"] and near(Game.day, 120.0):
				day120_target["evaluated"] = true
				day120_target["nominal"] = whole["nominal"]
				day120_target["actual_worked"] = whole["actual_worked"]
				day120_target["fraction"] = whole["worked_fraction"]
				day120_target["passed"] = float(whole["worked_fraction"]) >= 0.90
		if not near(Game.day, start_day + float(step)): break
	check(near(Game.day, start_day + float(days)), "all requested ordinary campaign days completed")
	var functional := {"passed": failures == 0, "checks": checks, "failures": failures, "first_failures": first_failures, "ownership_checks": audit.harvest_report["checks"], "ownership_violations": audit.harvest_report["violation_count"]}
	var target_failed := bool(day120_target["applicable"]) and (not bool(day120_target["evaluated"]) or not bool(day120_target["passed"]))
	var elapsed_us := 0
	for row in daily: elapsed_us += int(row["simulation_us"])
	write_json("harvest-audit.json", audit.harvest_report)
	write_json("report.json", {"schema": 1, "mode": "fresh_campaign" if source.is_empty() else "authentic_saved_campaign", "declared_size": size, "declared_seed": seed, "actual_seed": Game.seed_value, "source_save": source, "start_day": start_day, "end_day": Game.day, "requested_days": days, "towns": Game.world["towns"].size(), "ordinary_full_campaign": true, "fixed_raids": false, "setup_us": setup_us, "simulation_us": elapsed_us, "timing_excludes_collection": true, "daily": daily, "job_total_us": CampaignWorld.job_total.duplicate(true), "job_worst_us": CampaignWorld.job_worst.duplicate(true), "daily_parts_us": CampaignWorld.daily_total.duplicate(true), "checkpoints": samples, "functional_conservation": functional, "day120_target": day120_target, "overall_passed": failures == 0 and not target_failed, "food_basis": "Actual quantities and cumulative ledgers. Independent meal shares are instantaneous; no annualized forecasts or local-surplus cancellation. Production/event divergence is permitted across versions."})
	if target_failed: printerr("FAIL: strict day120 90% worked/full nominal target ", JSON.stringify(day120_target, "", true, true))
	print("V046 COMPLETE functional_failures=", failures, " day120_target=", day120_target, " output=", output)
	return failures + (1 if target_failed else 0)
