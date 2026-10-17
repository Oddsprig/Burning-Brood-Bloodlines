extends RefCounted
## Observe the real midnight queue, attendance, family pay and staggered town closes.
## No service placements, money, demand or debts are injected into the integration run.
var checks := 0
var fails := 0
var closes := 0
var fractional_closes := 0
var zero_closes := 0
var keeper_debt_days := 0
var rows := []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", message)

func snapshot() -> Dictionary:
	var out := {}
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var families := []
		for f in e["fams"]:
			families.append([f.get("cj", {}).duplicate(true), f.get("child_cj", {}).duplicate(true), f.get("cjearned", {}).duplicate(true)])
		var businesses := []
		for b in e["biz"]:
			businesses.append([b["id"], b.get("owed", 0), b.get("net_receipts", []).duplicate(true)])
		out[t["id"]] = [TownSanitation.book(e).duplicate(true), families, businesses, e.get("cjcap", {}).duplicate(), e.get("cjused", {}).duplicate()]
	return out

func equivalent(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return absf(float(a) - float(b)) < 0.00000001
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for k in a:
			if not b.has(k) or not equivalent(a[k], b[k]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equivalent(a[i], b[i]): return false
		return true
	return a == b

func round_trip() -> void:
	var before := snapshot()
	var money := Barge.holdings(Game)
	Game.save_game()
	check(Game.load_game(), "midweek service campaign loads")
	var after := snapshot()
	check(equivalent(after, before), "assignments, earned pay, fractional paid days, completed books and producer debts/receipts survive load")
	if not equivalent(after, before):
		for tid in before:
			if not equivalent(before[tid], after[tid]):
				print("SERVICE SAVE DIFFERENCE ", tid, " before=", JSON.stringify(before[tid]), " after=", JSON.stringify(after[tid])); break
	check(absf(Barge.holdings(Game) - money) < 0.01, "save/load conserves existing money")

func close_job(job: Array, rng: RandomNumberGenerator) -> void:
	var t: Dictionary = Game.world["towns"][job[1]]
	var e: Dictionary = t["econ"]
	var s := TownSanitation.book(e)
	var start := float(s["filth_kg"])
	var urine := float(s["urine_litres"])
	var pop := maxf(0, float(e["pop"]) - float(e.get("away_n", 0)))
	var sweeper := TownSanitation.paid_days(e, "street_sweeper")
	var night := TownSanitation.paid_days(e, "night_soil_man")
	var rat_days := TownSanitation.paid_days(e, "rat_catcher")
	var paid: Dictionary = s["paid_days"].duplicate()
	var rats := int(s["rats"])
	CampaignWorld._do_work(Game, rng)
	closes += 1
	if sweeper > 0 and absf(sweeper - roundf(sweeper)) > 0.000001: fractional_closes += 1
	if sweeper == 0: zero_closes += 1
	var expect_swept := minf(start + float(s["incoming_kg"]), sweeper * float(TownSanitation.D()["sweep_kg_day"]))
	check(absf(float(s["swept_kg"]) - expect_swept) < 0.00001, "weekly sweeping uses the actual paid fractional days")
	check(absf(float(s["filth_kg"]) - start - float(s["incoming_kg"]) + float(s["swept_kg"]) + float(s["decayed_kg"])) < 0.00001, "weekly solids mass balances")
	check(absf(float(s["change_kg"]) - float(s["filth_kg"]) + start) < 0.00001, "completed change is relative to prior book")
	var expect_night := minf(urine + pop * float(TownSanitation.D()["urine_l_day"]) * 7, night * float(TownSanitation.D()["night_soil_l_day"]))
	check(absf(float(s["night_soil_l"]) - expect_night) < 0.00001, "weekly night soil uses actual fractional paid days")
	check(absf(float(s["urine_litres"]) + float(s["river_l"]) + float(s["night_soil_l"]) - urine - float(s["urine_in_l"])) < 0.00001, "weekly liquid mass balances")
	check(int(s["caught"]) == mini(rats, int(floor(rat_days * float(TownSanitation.D()["rats_caught_day"])))), "existing paid rat catchers supply actual removals")
	check(s["paid_days"].is_empty(), "completed close consumes paid days once")
	check(equivalent(s.get("completed_paid_days", {}), paid), "completed book retains exactly the consumed service shifts")
	check(float(s.get("closed_day", -1)) == float(job[2]), "completed book reports the effective queued close day")
	rows.append({"town": t["id"], "day": job[2], "paid_sweeper_days": sweeper, "paid_night_days": night, "swept_kg": s["swept_kg"], "filth_kg": s["filth_kg"], "change_kg": s["change_kg"], "completed_paid_days": s["completed_paid_days"].duplicate(), "closed_day": s["closed_day"]})

func observed_day() -> void:
	Game.day += 1
	Game.world["last_day"] = int(Game.day)
	var rng := CampaignWorld._rng(Game.world)
	CampaignWorld._daily(Game, int(Game.day), rng)
	while not Game.world["work"].is_empty():
		var job: Array = Game.world["work"][0]
		if job[0] == "tturn": close_job(job, rng)
		elif job[0] == "econ":
			var e: Dictionary = Game.world["towns"][job[1]]["econ"]
			var debt := {}
			for b in e["biz"]:
				if not b.get("closed", false) and int(b.get("kw", 0)) > 0 and int(b["workers"]) == 0 and float(b.get("owed", 0)) > 0:
					debt[int(b["id"])] = [float(b["owed"]), float(b.get("t_paid", 0.0)), float(b.get("owed_unattributed", b["owed"]))]
			CampaignWorld._do_work(Game, rng)
			for bid in debt:
				keeper_debt_days += 1
				var b: Dictionary = e["biz"][bid]
				var paid := float(b.get("t_paid", 0.0)) - float(debt[bid][1])
				check(absf(float(b["owed"]) + paid - float(debt[bid][0])) < 0.00001 and float(b.get("owed_unattributed", 0.0)) == float(debt[bid][2]), "keeper-only production adds no keeper wage; past employee debt decreases only by actual repayment and anonymous debt remains")
		else: CampaignWorld._do_work(Game, rng)
	Game.world["rng_state"] = str(rng.state)

func run(_tree: SceneTree) -> int:
	var legacy := OS.get_environment("SERVICES_LEGACY_SAVE")
	if legacy != "":
		var original := Game.SAVE_PATH
		Game.SAVE_PATH = legacy
		check(Game.load_game(), "prior v026 generated campaign loads on this code")
		Game.SAVE_PATH = original
	else:
		WorldGen.gen_size = "normal"
		var seed_text := OS.get_environment("SERVICES_SEED")
		Game.new_game(2026 if seed_text == "" else int(seed_text))
	var start_day := Game.day
	for d in 21:
		observed_day()
		if d in [2, 10]: round_trip()
	check(closes > 30, "ordinary schedule completes weekly books across every town")
	check(fractional_closes > 0, "actual generated fractional payment reaches weekly service")
	check(zero_closes > 0, "unfunded or unassigned completed periods remain observable")
	# A healthy run can repay all former staff and observe no keeper-only debt.
	# Every observed case is still checked above; test_wage_claims supplies
	# deterministic unpaid/former/legacy cases without requiring this symptom.
	var export_path := OS.get_environment("SERVICES_EXPORT_SAVE")
	if export_path != "": Game._write_save(export_path, Game._save_tree())
	# Exercise the ordinary full campaign time API after the observed economy queue.
	for d in 7: Game.advance_time(1.0, true)
	check(absf(Game.day - start_day - 28) < 0.00001, "loaded campaign continues through normal daily gameplay time")
	round_trip()
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		check(equivalent(EconomyAudit.town_report(Game, t)["sanitation"], TownSanitation.book(t["econ"])), "audit preserves completed and current service books separately")
	var output := OS.get_environment("SERVICES_OUTPUT")
	if output != "":
		DirAccess.make_dir_recursive_absolute(output)
		var f := FileAccess.open(output.path_join("service-closes.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify({"start_day": start_day, "end_day": Game.day, "closes": closes, "fractional_closes": fractional_closes, "zero_closes": zero_closes, "keeper_debt_days": keeper_debt_days, "checks": checks, "failures": fails, "rows": rows}, "\t", true, true))
	print("SERVICES FLOW checks=%d closes=%d fractional=%d zero=%d keeper_debt_days=%d failures=%d" % [checks, closes, fractional_closes, zero_closes, keeper_debt_days, fails])
	return fails
