extends RefCounted
var fails := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func fixture(kind: String) -> Array:
	var estate := Families._blank(0); estate["estate"] = true
	var owner := Families._blank(1); owner["m"] = 1
	var worker := Families._blank(2); worker["m"] = 2
	var e := {"biz": [], "fams": [estate, owner, worker], "day": 0, "treasury": 0.0}
	var b := Businesses._row(e, kind, -1, 2, TownEcon.data())
	b["wage"] = 100.0; b["till"] = 0.0
	return [e, b, owner, worker]

func producer(kind: String) -> void:
	var rows := fixture(kind)
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]; var f: Dictionary = rows[3]
	Families.set_job(e, f, int(b["id"]), 2)
	var c := []; c.resize(Sickness.C_SHED + 1); c.fill(0)
	c[Sickness.C_ON] = 0.5; c[Sickness.C_END] = 1.0; c[Sickness.C_DIE] = -1.0
	c[Sickness.C_BED] = 1; c[Sickness.C_BIZ] = int(b["id"])
	f["sk"] = {"worker": c}
	e["day"] = 1; WageClaims.accrue_day(e, 1)
	check(float(b["owed"]) == 150.0, kind + ": actual sickness leaves one and a half earned worker-days")
	b["t_prev"] = 0.0
	var market := {"till": 0.0}
	# Changing tomorrow's offer cannot rewrite yesterday's earned expense.
	b["wage"] = 200.0
	Businesses._books(b, 2, market, 0.0, 0.0, 12, 0.4)
	check(absf(float(b["p1"]) + 150.0) < 0.00001, kind + ": profit uses earned wages, including sickness and original rate")
	Families.set_job(e, f, int(b["id"]), 0)
	e["day"] = 2; WageClaims.accrue_day(e, 2)
	# A transfer of existing funding, followed by paying the previous day's debt.
	e["treasury"] = 150.0; e["treasury"] -= 150.0; b["till"] += 150.0; b["t_paid"] = -150.0
	var purse_before := float(f["purse"])
	WageClaims.pay_former(e)
	Businesses._books(b, 0, market, 0.0, 0.0, 12, 0.4)
	check(absf(float(b["p1"])) < 0.00001 and float(b["owed"]) == 0.0, kind + ": later repayment does not charge the wage expense twice")
	check(float(f["purse"]) - purse_before == 150.0 and float(b["till"]) == 0.0, kind + ": paying the bill is an exact cash transfer")

func farm_period() -> void:
	var rows := fixture("farm")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]; var owner: Dictionary = rows[2]; var f: Dictionary = rows[3]
	Families.set_job(e, f, int(b["id"]), 1)
	for day in range(1, 8):
		if day == 3:
			Families.set_job(e, f, int(b["id"]), 2); b["wage"] = 50.0
		if day == 6: Families.set_job(e, f, int(b["id"]), 0)
		e["day"] = day; WageClaims.accrue_day(e, day)
	owner["lpay"] = 700.0
	check(float(b["owed"]) == 500.0, "farm employees earned 500 over five actually staffed days")
	Businesses._farm_books(owner, b)
	check(absf(float(b["p1"]) - (100.0 - 500.0 / 7.0)) < 0.00001, "farm weekly books retain the cost of workers who left midweek")
	check(float(b["owed"]) == 500.0, "recording payroll expense leaves unpaid claims due")
	for day in range(8, 15): e["day"] = day; WageClaims.accrue_day(e, day)
	owner["lpay"] = 350.0
	Businesses._farm_books(owner, b)
	check(absf(float(b["p1"]) - 50.0) < 0.00001 and float(b["owed"]) == 500.0, "next unstaffed week carries the debt without charging its expense again")

func run(_tree: SceneTree) -> int:
	for kind in ["carpenter", "builder", "mine", "quarry", "weaponsmith"]: producer(kind)
	farm_period()
	print("WAGE BOOKS checks=", checks, " failures=", fails)
	return fails
