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

# v0.100: reject missing/mismatched history rather than silently restarting accumulated observations.
func restore_harvest_report(path: String, checkpoint_day: int) -> bool:
	if not FileAccess.file_exists(path): return false
	var loaded = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (loaded is Dictionary): return false
	var d: Dictionary = loaded
	Game.restore_exact(d)
	for key in ["schema", "seed", "requested_days", "final_day", "available", "advancing", "town_observations", "checks", "violation_count", "skipped_town_observations"]:
		if not d.has(key): return false
	# v0.100: malformed numeric fields must not be coerced to zero or rounded into a valid history.
	for key in ["schema", "seed", "requested_days", "final_day", "town_observations", "checks", "violation_count", "skipped_town_observations"]:
		var value = d[key]
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) != floorf(float(value)): return false
	if int(d["schema"]) != int(harvest_report["schema"]) or int(d["seed"]) != int(harvest_report["seed"]) or int(d["requested_days"]) != int(harvest_report["requested_days"]): return false
	if int(d["final_day"]) != checkpoint_day or d["available"] != harvest_report["available"] or d["advancing"] != true: return false
	for key in ["sample_days", "first_cases"]:
		if not (d.get(key) is Array): return false
	for key in ["violations_by_rule", "max_discrepancies"]:
		if not (d.get(key) is Dictionary): return false
	var sample_days := []
	for sd in d["sample_days"]:
		if not (sd is int or sd is float) or not is_finite(float(sd)) or float(sd) != floorf(float(sd)): return false
		sample_days.append(int(sd))
	var expected_days := []
	for sample_day in range(0, checkpoint_day + 1, 10): expected_days.append(sample_day)
	if checkpoint_day == int(harvest_report["requested_days"]) and checkpoint_day % 10 != 0: expected_days.append(checkpoint_day)
	if sample_days != expected_days: return false
	harvest_report["sample_days"] = sample_days
	harvest_report["town_observations"] = int(d.get("town_observations", 0))
	harvest_report["checks"] = int(d.get("checks", 0))
	harvest_report["violation_count"] = int(d.get("violation_count", 0))
	harvest_report["skipped_town_observations"] = int(d.get("skipped_town_observations", 0))
	var vby := {}
	for r in d.get("violations_by_rule", {}): vby[String(r)] = int(d["violations_by_rule"][r])
	harvest_report["violations_by_rule"] = vby
	var maxima := {}
	for r in d.get("max_discrepancies", {}): maxima[String(r)] = float(d["max_discrepancies"][r])
	harvest_report["max_discrepancies"] = maxima
	var cases := []
	for c in d.get("first_cases", []):
		if not (c is Dictionary): return false
		var row: Dictionary = c.duplicate(true)
		if row.has("day"): row["day"] = int(row["day"])
		if row.has("lot"): row["lot"] = int(row["lot"])
		cases.append(row)
	harvest_report["first_cases"] = cases
	return true

# v0.100: surface output failures instead of reporting an unwritten checkpoint as a successful chunk.
func write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: could not open audit output ", path)
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: printerr("FAIL: could not write audit output ", path, " error ", error)
	return error == OK

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "large"
	CampaignWorld.presim_years = 5
	var seed_v := 2026 if OS.get_environment("AUDIT_SEED") == "" else int(OS.get_environment("AUDIT_SEED"))
	var days := 600 if OS.get_environment("AUDIT_DAYS") == "" else int(OS.get_environment("AUDIT_DAYS"))
	# v0.100: support resumable chunks via AUDIT_RESUME=1 and AUDIT_STEP_DAYS so the 600-day Large
	# audit + checkpoint can be generated in short invocations through the ordinary exact save loader.
	var step_env := OS.get_environment("AUDIT_STEP_DAYS")
	# v0.100: a typo must not become a successful zero-day chunk or an unbounded resumed run.
	if step_env != "" and (not step_env.is_valid_int() or int(step_env) < 0):
		printerr("FAIL: AUDIT_STEP_DAYS must be a nonnegative integer")
		return 1
	var step_days := -1 if step_env == "" else int(step_env)
	var output := OS.get_environment("AUDIT_OUTPUT")
	var resume := OS.get_environment("AUDIT_RESUME") == "1"
	var chunked := resume or step_days >= 0
	if chunked and (output == "" or (resume and step_days < 0)):
		printerr("FAIL: chunked audits require AUDIT_OUTPUT and resumes require explicit AUDIT_STEP_DAYS (planned: 60)")
		return 1
	harvest_report["available"] = ResourceLoader.exists("res://campaign/harvest_claims.gd")
	harvest_report["seed"] = seed_v
	harvest_report["requested_days"] = days
	harvest_report["tolerance_absolute"] = ABS_TOL
	harvest_report["tolerance_relative"] = REL_TOL
	if resume:
		var ckpt_path := output.path_join("checkpoint-save.json") if output != "" else ""
		if ckpt_path == "" or not FileAccess.file_exists(ckpt_path):
			printerr("FAIL: AUDIT_RESUME=1 requires existing checkpoint-save.json in AUDIT_OUTPUT")
			return 1
		# v0.100: validate the checkpoint/history pair before replacing the runner's private save.
		var checkpoint_text := FileAccess.get_file_as_string(ckpt_path)
		var parsed = JSON.parse_string(checkpoint_text)
		if not (parsed is Dictionary):
			printerr("FAIL: invalid checkpoint-save.json")
			return 1
		var checkpoint: Dictionary = parsed
		# v0.100: old checkpoints cannot contain the omitted live fights/caches. Start a new
		# audit rather than silently claiming exact equivalence after a lossy legacy migration.
		if int(checkpoint.get("version", 0)) != Game.SAVE_VERSION or not checkpoint.has("__types") or not checkpoint.has("raid_state") or not checkpoint.has("war_runtime"):
			printerr("FAIL: exact audit resume requires a current-schema checkpoint; regenerate day 0")
			return 1
		for key in ["seed", "day", "rng_state", "next_unit_uid", "next_item_uid", "world"]:
			if not checkpoint.has(key):
				printerr("FAIL: incomplete checkpoint-save.json: ", key)
				return 1
		var checkpoint_day := int(checkpoint["day"])
		if int(checkpoint["seed"]) != seed_v or checkpoint_day < 0 or checkpoint_day > days or float(checkpoint["day"]) != float(checkpoint_day) or not str(checkpoint["rng_state"]).is_valid_int() or not (checkpoint["world"] is Dictionary):
			printerr("FAIL: checkpoint seed/day/RNG/world does not match this audit")
			return 1
		if not restore_harvest_report(output.path_join("harvest-audit.json"), checkpoint_day):
			printerr("FAIL: missing, invalid or mismatched harvest-audit.json; accumulated history is required")
			return 1
		# v0.100: restore live fights, native plot caches and counters with no current-save migrations.
		if not write_text(Game.SAVE_PATH, checkpoint_text): return 1
		if not Game.load_game():
			printerr("FAIL: Game.load_game() failed on checkpoint-save.json")
			return 1
		WorldGen.gen_size = "large"
		CampaignWorld.presim_years = 5
		if Game.world.has("presim") and Game.world["presim"] is Dictionary:
			var p: Dictionary = Game.world["presim"]
			if p.has("total"): p["total"] = int(p["total"])
			if p.has("done"): p["done"] = int(p["done"])
	else:
		Game.new_game(seed_v)
		harvest_sample(int(Game.day))
	# v0.100: both single-shot AND chunked audits do 200 raid ticks per substep.
	# A wall-clock combat budget cannot yield identical simulations across processes.
	HerdRaids.benchmark_fixed_steps = true
	var advancing := true
	var start_day := int(round(Game.day))
	var target_day := days if step_days < 0 else mini(days, start_day + step_days)
	for d in range(start_day, target_day):
		CampaignWorld.presim_step(Game, 1)
		if int(Game.day) != d + 1:
			printerr("FAIL: audit day did not advance: expected ", d + 1, " got ", Game.day)
			advancing = false
			break
		if (d + 1) % 10 == 0: harvest_sample(d + 1)
		if (d + 1) % 120 == 0: print("AUDIT simulated day ", d + 1)
	if (int(Game.day) >= days or not advancing) and ((harvest_report["sample_days"] as Array).is_empty() or int(harvest_report["sample_days"][-1]) != int(Game.day)):
		harvest_sample(int(Game.day))
	harvest_report["final_day"] = int(Game.day)
	harvest_report["advancing"] = advancing
	harvest_report["passed"] = advancing and int(harvest_report["violation_count"]) == 0
	# v0.100: publish the requested audit only when complete; partial chunks carry history and a checkpoint.
	var complete := advancing and int(Game.day) == days
	var report: Dictionary = {}
	if not chunked or complete: report = EconomyAudit.world_report(Game)
	if output != "":
		# v0.100: do not fall back to lossy JSON if the exact writer fails.
		var htext := ""
		if step_days >= 0 and int(Game.day) < days and advancing:
			htext = Game.save_text(harvest_report)
			if htext == "":
				printerr("FAIL: exact harvest history serialization failed")
				return 1
		else:
			htext = JSON.stringify(harvest_report, "\t", true, true)
		var save_requested := OS.get_environment("AUDIT_SAVE") == "1" or chunked
		var text := ""
		if save_requested:
			var tree := Game._save_tree()
			text = Game.save_text(tree)
			if text == "":
				printerr("FAIL: exact checkpoint serialization failed")
				return 1
		if DirAccess.make_dir_recursive_absolute(output) != OK:
			printerr("FAIL: could not create AUDIT_OUTPUT: ", output)
			return 1
		if not write_text(output.path_join("harvest-audit.json"), htext): return 1
		if save_requested and not write_text(output.path_join("checkpoint-save.json"), text): return 1
		if not report.is_empty() and not write_text(output.path_join("audit.json"), JSON.stringify(report, "\t", true, true)): return 1
	if not report.is_empty(): print("AUDIT towns=%d issues=%d" % [report["towns"].size(), report["issue_count"]])
	else: print("AUDIT checkpoint day=%d requested=%d" % [int(Game.day), days])
	print("HARVEST AUDIT samples=%d towns=%d checks=%d violations=%d" % [harvest_report["sample_days"].size(), harvest_report["town_observations"], harvest_report["checks"], harvest_report["violation_count"]])
	return 0 if harvest_report["passed"] else 1
