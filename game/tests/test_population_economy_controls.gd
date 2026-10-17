extends RefCounted
## Three bounded native fixtures. No world generation or battle engine needed.
var checks := 0
var fails := 0

class FixtureGame:
	extends RefCounted
	var world: Dictionary = {}
	var company: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func pool(id: int, households: int) -> Dictionary:
	var f := Families._blank(id)
	f.merge({"cohort": true, "households": households, "race": "human", "cul": "middle", "name": "Workforce",
		"m": households * 2, "f": households * 2, "homes": households, "pp": [], "kp": [],
		"age_bins": {"0:-20": households * 2, "1:-20": households * 2}, "cls": 0,
		"purse": float(Barge.B()["household"]["class_line"][0]) * 0.25 * households}, true)
	f["store"]["food"] = 2.0
	return f

func fixture(parts: Array) -> Dictionary:
	var estate := Families._blank(0); estate["estate"] = true
	var owner := Families._blank(1); owner["name"] = "Operator"; owner["m"] = 1; owner["f"] = 1; owner["cls"] = 2; owner["purse"] = 1000.0
	var buyer := Families._blank(2); buyer["name"] = "Buyer"; buyer["m"] = 1; buyer["f"] = 1; buyer["cls"] = 2; buyer["purse"] = 1000.0
	var e := {"identity_scope": "population-economy-fixture", "culture": "middle", "climate": "temperate", "next_pid": 1,
		"fams": [estate, owner, buyer], "biz": [], "day": 0, "treasury": 1000000.0,
		"price": {"grain": 2.0, "fruit": 4.0, "meat": 6.0, "fresh_meat": 6.0},
		"stock": {"grain": 400000, "fruit": 400000}, "barn": {}, "hh": {}, "req": {}, "stats": {"sales": 0.0},
		"tax": {"leak": 0.1}, "ruler": {"tribute": 0.05}, "head": {"person_uid": ""}}
	for n in parts: e["fams"].append(pool(e["fams"].size(), int(n)))
	var market := Businesses._row(e, "market", 1, 0, TownEcon.data())
	market["till"] = 100000.0; e["mkt"] = int(market["id"])
	return e

func coin(e: Dictionary) -> float:
	var total := float(e["treasury"]) + float(e.get("farm_till", 0.0))
	for f in e["fams"]: total += float(f["purse"])
	for b in e["biz"]: total += float(b["till"])
	return total

func common_purse(e: Dictionary) -> float:
	var total := 0.0
	for f in e["fams"]:
		if Population.is_cohort(f): total += float(f["purse"])
	return total

func aggregation_cycle() -> void:
	var one := fixture([20])
	var split := fixture([10, 10])
	for e in [one, split]:
		for f in e["fams"]:
			if Population.is_cohort(f): check(Barge.klass(f) == 0, "many poor households do not become rich merely by sharing a purse")
	var h := Population.household_stats(one)
	check(int(h["households"]) == 22 and int(h["poor"]) == 20, "collector workload and poor counts use actual represented households")
	var hungry := one.duplicate(true); hungry["fams"][3]["hungry"] = 1
	check(int(Population.household_stats(hungry)["poor_hungry"]) == 20, "a hungry pool represents all its actual hungry households")
	# A cheap staple shortage must not change the reserve when a pool splits.
	one["stock"]["grain"] = 30; split["stock"]["grain"] = 30
	var original := one.duplicate(true)
	var q1 := Barge.common_tax_budget(one); var q2 := Barge.common_tax_budget(split)
	check(one == original, "tax quote leaves private stores, inventory and harvest books unchanged")
	for key in ["wealth", "food_reserve", "taxable_wealth", "monthly_due"]:
		check(near(float(q1[key]), float(q2[key])), "split pools preserve aggregate " + key)
	var reserved := one.duplicate(true); reserved["stock"]["grain"] = 0
	reserved["barn"] = {"grain": 2000}
	reserved["harvest_book"] = {"balances": {"f:1": {"grain": [2000.0, 2000.0]}}}
	var no_barn := reserved.duplicate(true); no_barn["barn"] = {}
	check(near(float(Barge.common_tax_budget(reserved)["food_reserve"]), float(Barge.common_tax_budget(no_barn)["food_reserve"])), "another owner's reserved grain cannot discount the pool's essential purchase reserve")
	var full_larder := one.duplicate(true)
	full_larder["fams"][3]["store"]["food"] = 7.0
	check(near(float(Barge.common_tax_budget(full_larder)["food_reserve"]), 0.0), "owned seven-day food store satisfies the reserve without spending it")
	for e in [one, split]:
		e["stock"]["grain"] = 400000
		var b := Businesses._row(e, "carpenter", 1, 40, TownEcon.data())
		b["till"] = 200000.0; b["wage"] = 10.0
		for f in e["fams"]:
			if Population.is_cohort(f): Families.set_job(e, f, int(b["id"]), Population.households(f) * 2)
	var opening_one := coin(one); var opening_split := coin(split)
	for week in 4:
		for e in [one, split]:
			for d in range(week * 7 + 1, week * 7 + 8):
				e["day"] = d; WageClaims.accrue_day(e, d)
			for f in e["fams"]:
				if not Population.is_cohort(f): continue
				WageClaims.pay_family(e, f)
				EconomyRules.cover_food(e, f, 7.0, float(e["day"]))
				check(float(f["store"]["food"]) >= 7.0, "real wage-funded pool buys its actual week's meals")
				f["store"]["food"] = maxf(0.0, float(f["store"]["food"]) - 7.0)
				Barge.klass(f)
		var h1 := Population.household_stats(one); var h2 := Population.household_stats(split)
		check(h1 == h2, "split pools preserve represented classes, rich/poor proportions and collector workload")
		check(int(one["fams"][3]["cls"]) == int(split["fams"][3]["cls"]), "class follows household savings during the wage/food cycle")
		check(near(common_purse(one), common_purse(split)) and one["stock"] == split["stock"], "equivalent pools earn and consume the same real coin and goods")
		check(near(coin(one), opening_one) and near(coin(split), opening_split), "four-week wage and consumption cycle conserves all owned coin")

func public_contract() -> void:
	var e := fixture([20])
	var workers: Dictionary = e["fams"][3]
	var collector := Businesses._row(e, "collector", -1, 3, TownEcon.data())
	var buyer: Dictionary = e["fams"][1 if int(collector["owner"]) == 2 else 2]
	check(int(collector["owner"]) >= 1 and not Population.is_cohort(e["fams"][int(collector["owner"])]), "dynamic public service selects an existing tracked operator")
	check(String(collector["public_funding"]) == "town", "collector contract retains explicit municipal payer")
	collector["wage"] = 10.0; collector["till"] = 0.0
	Families.set_job(e, workers, int(collector["id"]), 3)
	for d in range(1, 6): WageClaims.accrue_day(e, d)
	check(near(float(collector["owed"]), 150.0), "real workforce earns five days of retained wages")
	var old_owner: Dictionary = e["fams"][int(collector["owner"])]
	old_owner["owns"].erase(int(collector["id"])); buyer["owns"].append(int(collector["id"])); collector["owner"] = int(buyer["id"])
	var before := coin(e); var buyer_cash := float(buyer["purse"])
	var paid := TownEcon.fund_public_services(e)
	check(near(paid, 150.0 + 3 * 10.0 * 14.0) and near(coin(e), before), "actual appropriation protects old wages and funds native two-week places")
	check(near(TownEcon.fund_public_services(e), 0.0), "replaying public funding cannot transfer the same reserve twice")
	Businesses.owner_turn(e, buyer, collector)
	check(near(float(buyer["purse"]), buyer_cash), "private operator neither skims nor replaces protected public capital")
	var wage_paid := WageClaims.pay_family(e, workers)
	check(near(float(wage_paid[0]), 150.0) and near(float(collector["owed"]), 0.0) and near(coin(e), before), "ownership change preserves original workforce claim and payment conservation")
	var estate := Businesses._row(e, "estate", -1, 0, TownEcon.data())
	e["fams"][0]["land"] = {"grain": 100}
	check(int(estate["public_property"]) == 0 and int(estate["owner"]) > 0, "estate operator and actual land owner remain distinct")
	check(near(EconomyRules.wage_limit(e, estate, 1000000.0), EconomyRules.farm_hand_value(e, e["fams"][0])), "public estate wage valuation reads its real productive property")
	var academy := Businesses._row(e, "academy", -1, 1, TownEcon.data()); academy["till"] = 0.0
	var academy_before := float(academy["till"])
	TownEcon.fund_public_services(e)
	check(String(academy["public_funding"]) == "realm" and near(float(academy["till"]), academy_before), "academy retains its sole native realm/capital funding pass")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(e))
	check(restored["biz"][int(collector["id"])]["public_funding"] == "town" and int(restored["biz"][int(estate["id"])]["public_property"]) == 0, "current save preserves payer/property flags independently of tracked operator")

func promotion_and_held_levy() -> void:
	var e := fixture([20]); var f: Dictionary = e["fams"][3]
	f["purse"] = 100000.0; f["pool_condition"] = {"workers": 0.35, "elders": 0.5, "children": 0.4}
	var count := Families.people(f); var anonymous := Population.anonymous(f, 0) + Population.anonymous(f, 1)
	var rng := RandomNumberGenerator.new(); rng.seed = 31003
	var p := Population.promote(e, f, 0.0, rng, true)
	check(not p.is_empty() and near(float(f.get("bc", {}).get(str(int(p[0])), 1.0)), 0.35), "one promoted resident inherits actual native body condition")
	check(Families.people(f) == count and Population.anonymous(f, 0) + Population.anonymous(f, 1) == anonymous - 1, "weak promotion consumes one actual slot with unchanged resident count")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(e))
	var saved: Dictionary = restored["fams"][3]
	check(near(float(saved["bc"][str(int(p[0]))]), 0.35) and Persons.by_pid(saved, int(p[0]))[Persons.PERSON_UID] == p[Persons.PERSON_UID], "current save retains the same named condition and stable identity")
	var game := FixtureGame.new(); var town := {"id": "fixture", "econ": e}
	game.world = {"feudal": {}, "towns": {"fixture": town}}
	var before := coin(e); var purse := float(f["purse"]); var municipal := float(e["treasury"])
	check(near(Barge.common_tax_month(game, town, e, 30.0), 0.0) and near(float(f["purse"]), purse) and near(float(e["treasury"]), municipal), "vacant lord holds private levy without municipal diversion or arrears")
	check(int(f.get("lord_tax_held_month", -1)) == 1 and int(f.get("lord_tax_month", -1)) == -1, "vacancy leaves actual month unpaid and allows same-month settlement")
	var lord: Dictionary = e["fams"][1]
	var ruler := Persons._new(e, lord, "human", 0, -30 * People.year_days(), 0, rng); Persons.pp(lord).append(ruler)
	e["head"]["person_uid"] = ruler[Persons.PERSON_UID]
	e["lord_tax_rate"] = 0.10
	var quote := Barge.common_tax_budget(e); var transfer := Barge.common_tax_month(game, town, e, 30.0)
	check(near(transfer, float(quote["monthly_due"])) and transfer > 0.0 and near(coin(e), before), "actual living lord receives the quoted private levy from existing owned coin")
	check(near(float(f["lord_tax_last"]), transfer) and near(float(f["lord_tax_reserve"]), float(quote["food_reserve"])), "burden bookkeeping records actual paid amount and protected reserve")
	check(String(f["lord_tax_town_id"]) == "fixture", "actual monthly burden retains the town receiving that payment")
	check(near(Barge.common_tax_month(game, town, e, 30.0), 0.0) and near(coin(e), before), "same-month levy replay cannot debit twice")

func run(_tree: SceneTree) -> int:
	aggregation_cycle()
	public_contract()
	promotion_and_held_levy()
	print("Population economy controls: %d checks, %d failures" % [checks, fails])
	return fails
