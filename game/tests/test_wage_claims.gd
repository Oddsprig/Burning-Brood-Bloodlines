extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func due(b: Dictionary, f: Dictionary) -> float:
	return float(b.get("wage_claims", {}).get(str(int(f["id"])), 0.0))

func ledger() -> GDScript:
	return load("res://campaign/wage_claims.gd") if ResourceLoader.exists("res://campaign/wage_claims.gd") else null

func synthetic(kind: String, legacy: float) -> void:
	var first := Families._blank(1); first["m"] = 1; first["purse"] = 0.0
	var second := Families._blank(2); second["f"] = 1; second["purse"] = 0.0
	var estate := Families._blank(0); estate["estate"] = true
	var e := {"biz": [], "fams": [estate, first, second], "day": 0, "treasury": 0.0, "estate_biz": -1}
	var b := Businesses._row(e, kind, -1, 2, TownEcon.data())
	b["wage"] = 100.0; b["till"] = 0.0; b["owed"] = legacy
	Families.set_job(e, first, int(b["id"]), 1)
	Families.set_job(e, second, int(b["id"]), 1)
	var api := ledger()
	if api == null:
		check(false, kind + ": old aggregate books cannot attribute or retain short-paid claims")
		return
	for day in [1, 2]:
		e["day"] = day; api.accrue_day(e, day)
	b["wage"] = 50.0
	e["day"] = 3; api.accrue_day(e, 3)
	check(due(b, first) == 250 and due(b, second) == 250, kind + ": each day's actual wage stays attached to its worker household")
	check(float(b["owed"]) == 500 + legacy, kind + ": total combines identified wages and unchanged old debt")
	Game.day = 9999.0
	api.accrue_day(e, 3)
	check(float(b["owed"]) == 500 + legacy, kind + ": same queued day replay does not accrue again when world clock is ahead")
	b["till"] = 80.0
	Families.set_job(e, first, int(b["id"]), 0)
	check(float(first["purse"]) == 80 and due(b, first) == 170, kind + ": departure pays only available cash and retains the exact unpaid worker claim")
	check(due(b, second) == 250 and float(second["purse"]) == 0, kind + ": another worker cannot take the departed worker's claim")
	e["day"] = 4; api.accrue_day(e, 4)
	check(due(b, first) == 170 and due(b, second) == 300, kind + ": departure stops future accrual only")
	b["closed"] = true; b["owner"] = 2; b["kw"] = 1
	e["day"] = 5; api.accrue_day(e, 5)
	check(due(b, second) == 300, kind + ": closing or a profit-taking keeper creates no new wage")
	var cash := 600.0
	e["treasury"] = cash; e["treasury"] -= 400.0; b["till"] += 400.0
	api.pay_former(e)
	check(float(first["purse"]) == 250 and due(b, first) == 0, kind + ": real later funds repay former employee even after closure and ownership change")
	api.pay_family(e, second)
	check(float(second["purse"]) == 230 and due(b, second) == 70, kind + ": second claimant keeps remaining short pay")
	check(float(first["purse"]) + float(second["purse"]) + float(b["till"]) + float(e["treasury"]) == cash + 80.0, kind + ": all repayment is a transfer of existing coins")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(e))
	api.after_load(restored); api.after_load(restored)
	var rb: Dictionary = restored["biz"][0]
	check(float(rb["owed"]) == legacy + 70 and float(rb["owed_unattributed"]) == legacy and float(rb["wage_claims"]["2"]) == 70, kind + ": repeated JSON migration preserves creditor and anonymous books")
	check(float(first.get("wage_receipts", 0.0)) == 250.0, kind + ": out-of-turn receipts remain available for one ordinary income report")
	var paid_job := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	Families.set_job(e, second, int(b["id"]), 0)
	Families.set_job(e, second, int(paid_job["id"]), 1)
	paid_job["wage"] = 20.0; paid_job["till"] = 20.0
	e["day"] = 6; api.accrue_day(e, 6)
	var result: Array = api.pay_family(e, second)
	check(not bool(result[1]) and due(b, second) == 70.0 and due(paid_job, second) == 0.0, kind + ": former-employer arrears cannot count a fully paid current job as unpaid")

func sickness_boundaries() -> void:
	var api := ledger()
	if api == null: check(false, "daily accrued sickness accounting is unavailable on baseline"); return
	var f := Families._blank(1); f["m"] = 2
	var estate := Families._blank(0); estate["estate"] = true
	var e := {"biz": [], "fams": [estate, f], "day": 0}
	var b := Businesses._row(e, "carpenter", -1, 2, TownEcon.data()); b["wage"] = 100.0
	Families.set_job(e, f, int(b["id"]), 2)
	var c := []
	c.resize(Sickness.C_SHED + 1); c.fill(0)
	c[Sickness.C_ON] = 0.5; c[Sickness.C_END] = 2.5; c[Sickness.C_DIE] = -1.0
	c[Sickness.C_BED] = 1; c[Sickness.C_BIZ] = int(b["id"])
	f["sk"] = {"person": c}
	e["day"] = 1; api.accrue_day(e, 1)
	check(due(b, f) == 150, "half first-day bed absence deducts only that worker's half-day wage")
	e["day"] = 2; api.accrue_day(e, 2)
	check(due(b, f) == 250, "one sick employee cannot remove the other employee's earned wage")
	f.erase("sk"); f["wage_bed"] = [[int(b["id"]), 2.0, 2.5]]
	e["day"] = 3; api.accrue_day(e, 3)
	check(due(b, f) == 400 and not f.has("wage_bed"), "completed case retains final half-day absence until queued wages close, then ages out")

func actual_town(t: Dictionary) -> void:
	var e: Dictionary = t["econ"]
	var f := Families._blank((e["fams"] as Array).size())
	f["m"] = 1; f["purse"] = 0.0
	(e["fams"] as Array).append(f)
	var b := Businesses._row(e, "farm", -1, 1, TownEcon.data())
	b["wage"] = 100.0; b["till"] = 0.0
	Families.set_job(e, f, int(b["id"]), 1)
	var day := int(e["day"]) + 1
	TownEcon.daily_pass(Game, t, day, false)
	check(due(b, f) == 100.0, "actual daily town pass accrues exactly one farm employee day")
	var owed := float(b["owed"])
	TownEcon.daily_pass(Game, t, day, false)
	check(float(b["owed"]) == owed, "actual daily town replay preserves claims")
	var transfer := minf(200.0, float(e["treasury"]))
	e["treasury"] -= transfer; b["till"] += transfer
	var before := float(f["purse"])
	Families.set_job(e, f, int(b["id"]), 0)
	check(absf(float(f["purse"]) - before - minf(100, transfer)) < 0.001, "actual job removal pays accrued farm wage from existing funds")

func relocation_and_inheritance() -> void:
	var api := ledger()
	if api == null: check(false, "relocated creditor ledger is unavailable on baseline"); return
	var towns := []
	for t in Game.world["towns"].values():
		if TownEcon.has_econ(t): towns.append(t)
	check(towns.size() >= 2, "two generated towns exist for actual household migration")
	if towns.size() < 2: return
	var t: Dictionary = towns[0]; var other: Dictionary = towns[1]; var e: Dictionary = t["econ"]
	var f: Dictionary = {}
	for candidate in e["fams"]:
		if not candidate.get("gone", false) and not candidate.get("estate", false) and Families.serving(candidate) == 0:
			f = candidate; break
	check(not f.is_empty(), "migrating household exists")
	if f.is_empty(): return
	for k in f["jobs"].keys(): Families.set_job(e, f, int(k), 0)
	var b := Businesses._row(e, "carpenter", -1, 1, TownEcon.data()); b["wage"] = 100.0; b["till"] = 0.0
	Families.set_job(e, f, int(b["id"]), 1)
	api.accrue_day(e, int(e.get("wage_day", e["day"])) + 1)
	var claim := due(b, f)
	var nf := Barge.move_family(Game, t, f, other, "wage test", float(e["day"]))
	check(claim == 100 and due(b, f) == claim, "actual migration retains old-town employer debt")
	var middle := nf
	nf = Barge.move_family(Game, other, middle, t, "wage test", float(e["day"]))
	check(due(b, f) == claim, "a second move preserves the original employer's exact claim")
	var tid := String(t["id"]); var bid := int(b["id"]); var old_fid := int(f["id"]); var new_fid := int(nf["id"])
	b["owed_unattributed"] = 321.5; api._refresh(b)
	var cash := Barge.holdings(Game)
	Game.day = float(e["day"])
	Game.save_game(); check(Game.load_game(), "actual campaign loader restores an unpaid redirected wage claim")
	t = Game.world["towns"][tid]; e = t["econ"]; b = e["biz"][bid]
	f = e["fams"][old_fid]; nf = e["fams"][new_fid]
	check(due(b, f) == claim and float(b["owed_unattributed"]) == 321.5 and float(b["owed"]) == claim + 321.5, "actual save/load preserves identified, anonymous and redirected debt without allocating legacy balances")
	check(absf(Barge.holdings(Game) - cash) < 0.001, "actual claim save/load makes no compensation money")
	var before := float(nf["purse"])
	b["till"] += claim; api.pay_former(e)
	check(float(nf["purse"]) == before + claim and float(f["purse"]) == 0 and due(b, f) == 0, "old employer repays exact relocated household once")
	check(float(nf.get("wage_receipts", 0.0)) >= claim, "redirected out-of-turn receipt belongs only to the destination household")
	# Keep this ordinary turn isolated from other employers and local income.
	for job in nf["jobs"].keys(): Families.set_job(e, nf, int(job), 0)
	nf["land"] = {}; nf["herd"] = {}; nf["owns"] = []; nf["keeps"] = []; nf["farm"] = -1; nf["hands"] = 0
	nf["store"] = {"food": 100.0, "drink": 100.0, "wood": 100.0}; nf["purse"] = maxf(100000.0, float(nf["purse"]))
	var received := float(nf.get("wage_receipts", 0.0))
	var turn_day := float(nf["last"]) + 7.0; var rng := RandomNumberGenerator.new(); rng.seed = 999
	e["day"] = int(turn_day); Game.day = turn_day
	Families.turn(Game, t, e, nf, turn_day, rng)
	check(float(nf["income_parts"]["staff wages"]) == received and not nf.has("wage_receipts"), "ordinary family turn reports prior wage receipts once")
	for job in nf["jobs"].keys(): Families.set_job(e, nf, int(job), 0)
	turn_day += 7.0; e["day"] = int(turn_day); Game.day = turn_day
	Families.turn(Game, t, e, nf, turn_day, rng)
	check(float(nf["income_parts"]["staff wages"]) == 0.0, "next ordinary family turn does not report or pay prior wage receipts again")
	api.prepare(b); b["wage_claims"][str(int(f["id"]))] = 40.0; api._refresh(b)
	nf["gone"] = true; nf["extinct"] = true
	var dest_e: Dictionary = e
	var fac: Dictionary = Game.world["factions"].get(String(dest_e["faction"]), {})
	var recipient: Dictionary = fac if not fac.is_empty() else dest_e
	before = float(recipient["treasury"])
	b["till"] += 40.0; api.pay_former(e)
	check(float(recipient["treasury"]) == before + 40.0 and due(b, f) == 0, "relocated extinct household's unpaid property follows existing coffer inheritance")

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(2026)
	for kind in ["farm", "estate", "carpenter", "builder", "mine", "quarry", "market", "works"]:
		for legacy in [0.0, 321.5]: synthetic(kind, legacy)
	sickness_boundaries()
	for t in Game.world["towns"].values():
		if TownEcon.has_econ(t): actual_town(t)
	relocation_and_inheritance()
	print("WAGE CLAIMS checks=", checks, " failures=", fails)
	return fails
