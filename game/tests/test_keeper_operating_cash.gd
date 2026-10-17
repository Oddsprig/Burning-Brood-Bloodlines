extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func fixture(culture: String, typ: String) -> Array:
	var D := TownEcon.data()
	var estate := Families._blank(0); estate["estate"] = true
	var f := Families._blank(1); f["m"] = 1; f["purse"] = 20000.0
	var e := {"culture": culture, "biz": [], "fams": [estate, f], "stock": {}, "price": {}, "need": {}, "dem": {}, "knowhow": {}, "specialties": [],
		"stats": {"sales": 0.0}, "led": {"used": {}, "made": {}}, "day": 0, "pop": 1, "mkt": 0}
	for good in D["goods"]:
		e["stock"][good] = 0; e["price"][good] = float(D["goods"][good]["price"]); e["need"][good] = 100.0; e["dem"][good] = 100.0
	for key in D["knowhow"]: e["knowhow"][key] = 100.0
	var m := Businesses._row(e, "market", -1, 0, D); m["till"] = 100000.0
	var b := Businesses._row(e, typ, 1, 1, D)
	b["till"] = 0.0; b["workers"] = 0; b["kw"] = 1; b["sick"] = 0; b["tools"] = 1
	b["health"] = "steady"; b["p1"] = 0.0; b["state"] = "wages"; b["why"] = "money for materials"
	e["prod"] = [int(b["id"])]; e["makers"] = {}
	for recipe in D["businesses"][typ]["recipes"]:
		var ins: Dictionary = D["cultures"][culture]["home"]["materials"] if recipe.get("home", false) else recipe["in"]
		for good in ins: e["stock"][good] = 100000
		for good in recipe["out"]: e["makers"][good] = 1.0
	Businesses.prep_day(e)
	return [e, b, f, m]

func coins(rows: Array) -> float:
	return float(rows[2]["purse"]) + float(rows[1]["till"]) + float(rows[3]["till"])

func owner(rows: Array) -> void:
	Businesses.owner_turn(rows[0], rows[2], rows[1])

func produce(rows: Array, day: int) -> void:
	var e: Dictionary = rows[0]
	e["day"] = day
	var rng := RandomNumberGenerator.new(); rng.seed = 811 + day
	Businesses.daily(Game, {"id": "fixture", "econ": e, "shop": []}, e, TownEcon.data(), 0, rng)
	Businesses.books_day(e)

func positive(culture: String, typ: String, replace_tool: bool = false, worn_tool: bool = false) -> void:
	var rows := fixture(culture, typ)
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]; var f: Dictionary = rows[2]
	if replace_tool: b["tools"] = 0; e["stock"]["tools"] = 10
	if worn_tool: b["tools"] = 1; b["tw"] = 0.999; e["stock"]["tools"] = 10
	var start := coins(rows); var purse := float(f["purse"])
	check(not Businesses.hiring(e, b), culture + " " + typ + ": operating fixture requires no speculative hire")
	owner(rows)
	check(float(b["till"]) > 0.0, culture + " " + typ + ": real owner funds a viable working keeper's materials")
	check(absf(coins(rows) - start) < 0.001 and purse - float(f["purse"]) <= purse * 0.5 + 0.001,
		culture + " " + typ + ": funding conserves coins and obeys the existing purse share")
	var made := false
	for day in range(1, 71):
		produce(rows, day)
		if day % 7 == 0: owner(rows)
		if (e["led"]["made"] as Dictionary).values().any(func(n): return int(n) > 0): made = true; break
	check(made and float(b["till"]) > 0.0, culture + " " + typ + ": normal owner/production/books turns complete paid output")
	check(absf(coins(rows) - start) < 0.01 and float(b["owed"]) == 0.0 and int(b["workers"]) == 0,
		culture + " " + typ + ": recovery invents no coins, debt, staff or second payroll")
	if replace_tool or worn_tool: check(int(b["tools"]) == 1 and int(e["stock"]["tools"]) == 9,
		culture + ": ordinary missing/worn replacement tool is bought from real funding before production")

func negative(culture: String, typ: String, reason: String) -> void:
	var rows := fixture(culture, typ)
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]; var f: Dictionary = rows[2]
	var recipe: Dictionary = TownEcon.data()["businesses"][typ]["recipes"][0]
	var ins: Dictionary = TownEcon.data()["cultures"][culture]["home"]["materials"] if recipe.get("home", false) else recipe["in"]
	var good: String = recipe["out"].keys()[0]
	var cost := 0.0
	for g in ins: cost += float(ins[g]) * float(e["price"][g])
	match reason:
		"full": e["stock"][good] = 2 if good == "home" else int(Businesses.stock_cap(e, good))
		"aim-rest": e["_aimrest"][good] = true
		"zero-aim": e["_aimu"][good] = 0.0
		"inputs": e["stock"][ins.keys()[0]] = 0
		"buyer": rows[3]["till"] = 0.0
		"negative-net": e["price"][good] = cost * 0.5 / float(TownEcon.data()["market"]["buy_share"]) / float(recipe["out"][good])
		"below-upkeep": e["price"][good] = (cost + 0.289 / float(recipe["rate"])) / float(TownEcon.data()["market"]["buy_share"]) / float(recipe["out"][good])
		"poor": f["purse"] = 20.0 * TownEcon.COIN
		"no-worker": b["kw"] = 0
	var before := coins(rows); var purse := float(f["purse"])
	owner(rows)
	check(float(b["till"]) == 0.0 and float(f["purse"]) == purse and absf(coins(rows) - before) < 0.001,
		culture + " " + typ + ": " + reason + " cannot trigger an operating subsidy")

func selected_recipe_not_cheapest() -> void:
	var rows := fixture("middle", "carpenter")
	var e: Dictionary = rows[0]
	e["price"]["wood"] = 100.0
	e["price"]["furniture"] = float(TownEcon.data()["goods"]["furniture"]["price"]) * 1.1
	for g in ["copper_bars", "tin_bars", "bronze_bars"]: e["price"][g] = 1.0
	Businesses.prep_day(e)
	owner(rows)
	check(float(rows[1]["till"]) == 0.0, "funding uses production's selected loss recipe rather than choosing a different profitable recipe")

func retained_debt() -> void:
	var rows := fixture("middle", "builder")
	var b: Dictionary = rows[1]
	b["owed"] = 321.0; b["owed_unattributed"] = 321.0; b["wage_claims"] = {}
	var before := coins(rows)
	owner(rows)
	var cost := 0.0
	for g in TownEcon.data()["cultures"]["middle"]["home"]["materials"]:
		cost += float(TownEcon.data()["cultures"]["middle"]["home"]["materials"][g]) * float(rows[0]["price"][g])
	check(float(b["till"]) >= 321.0 + cost and float(b["owed"]) == 321.0 and float(b["owed_unattributed"]) == 321.0,
		"older wage liability remains separately reserved before the batch cash")
	check(absf(coins(rows) - before) < 0.001 and float(b["t_paid"]) < 0.0, "input funding is a real excluded owner transfer")

func quote_and_partial() -> void:
	var rows := fixture("middle", "builder")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]; var f: Dictionary = rows[2]
	b["owed"] = 321.0; b["owed_unattributed"] = 321.0; b["wage_claims"] = {}
	b["wage"] = 1000.0; b["carry"] = 0.9; f["purse"] = 800.0
	var before := JSON.stringify(e)
	var script = load("res://campaign/businesses.gd")
	if not script.has_method("operating_cash"):
		check(false, "shared read-only operating quote is available")
		return
	var target: float = script.operating_cash(e, b, 321.0)
	check(target > 0.0 and JSON.stringify(e) == before, "operating quote preserves prices, carry, state, demand, cash and claims")
	# A liability already in the till cannot become hypothetical operating cash.
	b["till"] = 321.0
	var reserved_target: float = script.operating_cash(e, b, 321.0)
	check(absf(target - reserved_target) < 0.001, "reserved old wages cannot increase the quoted operating throughput")
	b["till"] = 0.0
	var total := coins(rows)
	owner(rows)
	check(absf(float(b["till"]) - 400.0) < 0.001 and absf(float(f["purse"]) - 400.0) < 0.001 and absf(coins(rows) - total) < 0.001,
		"partial eligible owner transfers only the allowed real half purse")
	check(float(b["till"]) - float(b["owed"]) < target and Businesses.takeable(b) == 0 and float(b["owed"]) == 321.0,
		"partial capital is not an affordable complete batch, a debt reset or a speculative job")
	produce(rows, 1)
	check((e["led"]["made"] as Dictionary).is_empty() and int(b["workers"]) == 0 and float(b["owed"]) == 321.0,
		"partial funding cannot complete unpaid inputs or create staff")

func expensive_slow_batch() -> void:
	var rows := fixture("middle", "builder")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]; var f: Dictionary = rows[2]
	b["cap"] = 0; b["wage"] = 0.0; b["till"] = 5000.0; f["purse"] = 100000.0
	var cost := 0.0
	for g in TownEcon.data()["cultures"]["middle"]["home"]["materials"]:
		e["price"][g] *= 20.0
		cost += float(TownEcon.data()["cultures"]["middle"]["home"]["materials"][g]) * float(e["price"][g])
	e["price"]["home"] = cost * 2.0 / float(TownEcon.data()["market"]["buy_share"])
	Businesses.prep_day(e)
	var total := coins(rows); var old_purse := float(f["purse"])
	owner(rows)
	check(float(b["till"]) >= cost and float(f["purse"]) < old_purse, "expensive slow batch capital is funded before any old-reserve withdrawal")
	var made := false
	var protected := true
	for day in range(1, 36):
		produce(rows, day)
		if int(e["led"]["made"].get("home", 0)) > 0: made = true; break
		if day % 7 == 0:
			old_purse = float(f["purse"]); owner(rows)
			protected = protected and float(f["purse"]) <= old_purse + 0.001 and float(b["till"]) >= cost
	check(protected and made and absf(coins(rows) - total) < 0.01, "repeated normal weekly turns protect one expensive batch until real paid completion")

func sick_incumbent_payroll() -> void:
	var rows := fixture("middle", "builder")
	var e: Dictionary = rows[0]; var b: Dictionary = rows[1]
	b["workers"] = 1; b["sick"] = 1; b["wage"] = 10000.0
	var before := JSON.stringify(e)
	check(Businesses.operating_cash(e, b, 70000.0) == 0.0 and JSON.stringify(e) == before,
		"sick incumbent's ordinary wages remain a conservative viability cost without changing dated claims")

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		for typ in ["builder", "dairy"]:
			positive(culture, typ)
			for reason in ["full", "aim-rest", "zero-aim", "inputs", "buyer", "negative-net", "below-upkeep", "poor", "no-worker"]: negative(culture, typ, reason)
	positive("middle", "builder", true)
	positive("middle", "builder", false, true)
	selected_recipe_not_cheapest(); retained_debt(); quote_and_partial(); expensive_slow_batch(); sick_incumbent_payroll()
	print("KEEPER OPERATING CASH checks=", checks, " failures=", fails)
	return fails
