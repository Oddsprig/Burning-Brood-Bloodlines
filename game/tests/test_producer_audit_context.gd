extends "res://tests/test_keeper_operating_cash.gd"

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		var rows := fixture(culture, "builder")
		var e: Dictionary = rows[0]; var b: Dictionary = rows[1]
		e["stock"]["home"] = 2; e["need"]["home"] = 1.0; e["dem"]["home"] = 0.0
		Businesses.prep_day(e)
		b["state"] = "full"
		var town := {"id": "fixture", "econ": e, "shop": [], "size": 0}
		var before := JSON.stringify(e)
		var context := EconomyAudit.producer_cash_context(town, b)
		check(JSON.stringify(e) == before, culture + ": audit context never changes cash, stock, output, claims, demand or work")
		check(context["keeper_only"] and context["employee_daily_wages"] == 0.0 and context["earned_wage_liability"] == 0.0,
			culture + ": a cash-poor keeper-only resting shop has no employee payroll exposure")
		check(context["recipes"][0]["outputs"]["home"]["aim_rest"] and context["recipes"][0]["inputs"].size() == TownEcon.data()["cultures"][culture]["home"]["materials"].size(),
			culture + ": current demand rest and actual culture home materials are retained as evidence")
		b["workers"] = 1; b["owed"] = 83.0; b["wage_claims"] = {"1": 83.0}; b["till"] = 7.0
		before = JSON.stringify(e)
		context = EconomyAudit.producer_cash_context(town, b)
		check(not context["keeper_only"] and float(context["employee_daily_wages"]) > 0.0 and float(context["unfunded_earned_wages"]) == 76.0,
			culture + ": real employee work and an earned underfunded claim remain visible")
		check(JSON.stringify(e) == before and b["wage_claims"] == {"1": 83.0}, culture + ": reporting neither settles nor removes the creditor")
	print("PRODUCER AUDIT CONTEXT checks=", checks, " failures=", fails)
	return fails
