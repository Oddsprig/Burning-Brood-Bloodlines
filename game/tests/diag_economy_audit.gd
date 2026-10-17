extends RefCounted

const ABS_TOL := 0.000001
const REL_TOL := 0.0000000001
const CASE_LIMIT := 40
var harvest_report := {"schema": 1, "available": false, "sample_days": [], "town_observations": 0, "checks": 0, "violation_count": 0, "violations_by_rule": {}, "max_discrepancies": {}, "first_cases": [], "skipped_town_observations": 0}

func observe(rule: String, actual: float, expected: float, day: int, tid: String, detail: Dictionary = {}, one_sided: bool = false) -> void:
	harvest_report["checks"] = int(harvest_report["checks"]) + 1
	var discrepancy := maxf(0.0, actual - expected) if one_sided else absf(actual - expected)
	var maxima: Dictionary = harvest_report["max_discrepancies"]
	maxima[rule] = maxf(float(maxima.get(rule, 0)), discrepancy)
	var tolerance := ABS_TOL + REL_TOL * maxf(absf(actual), absf(expected))
	if discrepancy <= tolerance: return
	harvest_report["violation_count"] = int(harvest_report["violation_count"]) + 1
	var counts: Dictionary = harvest_report["violations_by_rule"]
	counts[rule] = int(counts.get(rule, 0)) + 1
	if (harvest_report["first_cases"] as Array).size() < CASE_LIMIT:
		var case := {"day": day, "town": tid, "rule": rule, "actual": actual, "expected": expected, "discrepancy": discrepancy, "tolerance": tolerance}
		case.merge(detail, false)
		(harvest_report["first_cases"] as Array).append(case)

func quantities(shares: Dictionary, day: int, tid: String, detail: Dictionary) -> float:
	var total := 0.0
	for key in shares:
		var value := float(shares[key])
		var where := detail.duplicate(); where["owner"] = String(key)
		observe("negative_quantity", 0, value, day, tid, where, true)
		total += value
	return total

func harvest_town(t: Dictionary, day: int) -> void:
	var e: Dictionary = t["econ"]
	var tid := String(t["id"])
	if not harvest_report["available"]:
		harvest_report["skipped_town_observations"] = int(harvest_report["skipped_town_observations"]) + 1
		return
	harvest_report["town_observations"] = int(harvest_report["town_observations"]) + 1
	if not e.get("harvest_book") is Dictionary:
		observe("missing_book", 1, 0, day, tid)
		return
	var b: Dictionary = e["harvest_book"]
	var lots: Dictionary = b.get("lots", {})
	var balances: Dictionary = b.get("balances", {})
	var goods := {}
	for g in e["barn"]: goods[g] = true
	for g in lots: goods[g] = true
	var expected_balances := {}
	for g in goods:
		var total := 0.0
		var rows: Array = lots.get(g, [])
		for index in rows.size():
			var row: Dictionary = rows[index]
			var shares: Dictionary = row.get("shares", {})
			var reserved: Dictionary = row.get("reserve", {})
			total += quantities(shares, day, tid, {"good": String(g), "lot": index})
			var owners := {}
			for key in shares: owners[key] = true
			for key in reserved: owners[key] = true
			for key in owners:
				var qty := float(shares.get(key, 0))
				var kept := float(reserved.get(key, 0))
				var detail := {"good": String(g), "lot": index, "owner": String(key)}
				observe("reserve_below_zero", 0, kept, day, tid, detail, true)
				observe("reserve_above_share", kept, qty, day, tid, detail, true)
				if not expected_balances.has(key): expected_balances[key] = {}
				var pair: Array = expected_balances[key].get(g, [0.0, 0.0])
				pair[0] = float(pair[0]) + qty; pair[1] = float(pair[1]) + kept
				expected_balances[key][g] = pair
		observe("physical_stock", total, float(e["barn"].get(g, 0)), day, tid, {"good": String(g)})
	var balance_owners := {}
	for key in balances: balance_owners[key] = true
	for key in expected_balances: balance_owners[key] = true
	for key in balance_owners:
		var actual_goods: Dictionary = balances.get(key, {})
		var expected_goods: Dictionary = expected_balances.get(key, {})
		var balance_goods := {}
		for g in actual_goods: balance_goods[g] = true
		for g in expected_goods: balance_goods[g] = true
		for g in balance_goods:
			var actual: Array = actual_goods.get(g, [0.0, 0.0])
			var expected: Array = expected_goods.get(g, [0.0, 0.0])
			var detail := {"good": String(g), "owner": String(key)}
			observe("derived_quantity", float(actual[0]), float(expected[0]), day, tid, detail)
			observe("derived_reserve", float(actual[1]), float(expected[1]), day, tid, detail)
	var carried: Dictionary = b.get("carry", {})
	var channels := {}
	for channel in carried: channels[channel] = true
	# Other e.carry channels belong to spoilage/consumption, not unmade barn output.
	for channel in e.get("carry", {}):
		if String(channel).begins_with("h_") or channel in ["straw", "bows_fowl"]: channels[channel] = true
	for channel in channels:
		var total := 0.0
		for row in carried.get(channel, []):
			total += quantities(row.get("shares", {}), day, tid, {"channel": String(channel)})
		observe("pending_carry", total, float(e.get("carry", {}).get(channel, 0)), day, tid, {"channel": String(channel)})
	var cash := quantities(b.get("cash", {}), day, tid, {"holder": "pending cash"})
	var unknown := float(b.get("unattributed_cash", 0))
	observe("unknown_cash_below_zero", 0, unknown, day, tid, {}, true)
	observe("cash_backing", cash + unknown, float(e.get("farm_till", 0)), day, tid, {"identified": cash, "unknown": unknown}, true)

func harvest_sample(day: int) -> void:
	(harvest_report["sample_days"] as Array).append(day)
	for t in Game.world["towns"].values():
		if TownEcon.has_econ(t): harvest_town(t, day)

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "large"
	CampaignWorld.presim_years = 5
	var seed_v := 2026 if OS.get_environment("AUDIT_SEED") == "" else int(OS.get_environment("AUDIT_SEED"))
	var days := 600 if OS.get_environment("AUDIT_DAYS") == "" else int(OS.get_environment("AUDIT_DAYS"))
	harvest_report["available"] = ResourceLoader.exists("res://campaign/harvest_claims.gd")
	harvest_report["seed"] = seed_v
	harvest_report["requested_days"] = days
	harvest_report["tolerance_absolute"] = ABS_TOL
	harvest_report["tolerance_relative"] = REL_TOL
	Game.new_game(seed_v)
	harvest_sample(int(Game.day))
	var advancing := true
	for d in days:
		CampaignWorld.presim_step(Game, 1)
		if int(Game.day) != d + 1:
			printerr("FAIL: audit day did not advance: expected ", d + 1, " got ", Game.day)
			advancing = false
			break
		if (d + 1) % 10 == 0: harvest_sample(d + 1)
		if (d + 1) % 120 == 0: print("AUDIT simulated day ", d + 1)
	if int(harvest_report["sample_days"][-1]) != int(Game.day): harvest_sample(int(Game.day))
	harvest_report["final_day"] = int(Game.day)
	harvest_report["advancing"] = advancing
	harvest_report["passed"] = advancing and int(harvest_report["violation_count"]) == 0
	var report := EconomyAudit.world_report(Game)
	var output := OS.get_environment("AUDIT_OUTPUT")
	if output != "":
		DirAccess.make_dir_recursive_absolute(output)
		var f := FileAccess.open(output.path_join("audit.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(report, "\t", true, true))
		f.close()
		var ownership := FileAccess.open(output.path_join("harvest-audit.json"), FileAccess.WRITE)
		ownership.store_string(JSON.stringify(harvest_report, "\t", true, true))
		ownership.close()
		if OS.get_environment("AUDIT_SAVE") == "1":
			var save := FileAccess.open(output.path_join("checkpoint-save.json"), FileAccess.WRITE)
			save.store_string(JSON.stringify(Game._save_tree()))
			save.close()
	print("AUDIT towns=%d issues=%d" % [report["towns"].size(), report["issue_count"]])
	print("HARVEST AUDIT samples=%d towns=%d checks=%d violations=%d" % [harvest_report["sample_days"].size(), harvest_report["town_observations"], harvest_report["checks"], harvest_report["violation_count"]])
	return 0 if harvest_report["passed"] else 1
