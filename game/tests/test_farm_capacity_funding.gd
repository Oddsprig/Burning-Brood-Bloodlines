extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", why)
func add_real_grain(e: Dictionary, f: Dictionary, n: int) -> void:
	var physical = load("res://tests/farm_fixture_tools.gd").new()
	check(physical.grain(e, f, n), "generated real cereal fields and oxen back the funding fixture")
	check(CropRotation.family_yield(e, f, "grain") > 0.0, "physical transfer retains productive rotation acreage")
func scenario(seed_v: int) -> void:
	Game.new_game(seed_v)
	var town: Dictionary = {}
	for t in Game.world["towns"].values():
		if Persons.race_of(t["econ"]) == "human": town = t; break
	check(not town.is_empty(), "generated culture supports ordinary farm funding fixture")
	if town.is_empty(): return
	var e: Dictionary = town["econ"]
	for b in e["biz"]: b["cap"] = int(b["workers"])
	for existing in [false, true]:
		var f := Families._blank(e["fams"].size())
		f["m"] = 1; f["seed"] = 91245; f["name"] = "Funding fixture"; f["homes"] = 1
		f["hands"] = 1
		f["purse"] = 10000.0; f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}
		f["tax_season"] = e["tax"]["season"]; f["cond"] = 1.0; f["last"] = 59.0
		f["farm_harvest"] = false; f["nxa"] = 100.0
		e["fams"].append(f); Persons.generate(e, f, 0.0)
		f["pp"][0][3] = -24.0 * People.year_days(); f["nxa"] = 100.0
		TownEcon.recount(e)
		add_real_grain(e, f, 8)
		Families.refresh_worked(e, f)
		var debt := 500.0 if existing else 0.0
		if existing:
			var farm := Businesses._row(e, "farm", int(f["id"]), 0, TownEcon.data())
			f["farm"] = int(farm["id"]); farm["till"] = debt; farm["owed"] = debt
			farm["owed_unattributed"] = debt; farm["wage_claims"] = {}; farm["t_paid"] = 0.0
			farm["wage_cost_period"] = 70.0; farm["p14"] = 0.0
		Game.day = 60.0; e["day"] = 60.0
		var before_population := Families.people(f); var rng := RandomNumberGenerator.new(); rng.seed = 9912
		Families.turn(Game, town, e, f, 60.0, rng)
		check(int(f["farm"]) >= 0, "ordinary harvest turn creates or keeps farm (seed%d existing%s need%.3f land%s)" % [seed_v, existing, Families.need_hands(f, e), f["land"]])
		if int(f["farm"]) < 0: continue
		var b: Dictionary = e["biz"][int(f["farm"])]
		var future := float(b["cap"]) * float(b["wage"]) * 8.0
		check(int(b["cap"]) == 1 and int(b["workers"]) == 0, "harvest offers one extra actual place without inventing staff")
		check(absf(float(b["till"]) - debt - future) < 0.0001, "new or increased harvest cap funded on same ordinary turn")
		check(Businesses.takeable(b) == 1, "fundable seasonal opening available before owner's next week")
		check(float(b["owed"]) == debt and b.get("wage_claims", {}).is_empty(), "funding reserves existing unknown claim without fabricating creditor or payout")
		check(absf(float(b.get("t_paid", 0.0)) + future) < 0.0001, "actual injection excluded from business receipts")
		check(absf(float(f["income_parts"]["business funding"]) + future * 7.0) < 0.001, "late real injection disclosed once in weekly household funding")
		check(float(f["inc"]) == snappedf(-future * 7.0, 0.01), "late funding included once at the actual household income precision")
		check(not f.has("farm_funding_pending"), "normal turn consumes late funding receipt once")
		if existing:
			check(float(b["wage_cost_period"]) == 0.0 and float(b["p1"]) == -70.0, "ordinary farm books expense prior earned work exactly once")
		check(Families.people(f) == before_population, "seasonal funding never invents adults")
		var purse := float(f["purse"]); var till := float(b["till"]); var paid := float(b.get("t_paid", 0.0)); var p14 := float(b.get("p14", 0))
		Families.reassign(e, f)
		check(float(f["purse"]) == purse and float(b["till"]) == till and float(b.get("t_paid", 0.0)) == paid, "same-cap reassignment does not transfer another reserve")
		check(float(b.get("p14", 0)) == p14, "reassignment never runs extra weekly farm books")
		# External capacity increase is reported on the next ordinary turn and survives save/load.
		add_real_grain(e, f, 8)
		Families.reassign(e, f)
		var pending := float(f.get("farm_funding_pending", 0.0))
		check(pending > 0.0, "external capacity increase records actual pending funding")
		if pending > 0.0:
			var tid := String(town["id"]); var fid := int(f["id"])
			Game.save_game(); check(Game.load_game(), "pending capacity funding saves and loads")
			town = Game.world["towns"][tid]; e = town["econ"]; f = e["fams"][fid]; b = e["biz"][int(f["farm"])]
			check(absf(float(f.get("farm_funding_pending", 0.0)) - pending) < 0.000001, "load preserves real pending funding amount")
			Game.day = 61.0; e["day"] = 61.0; f["last"] = 60.0
			f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}; f["cond"] = 1.0
			Families.turn(Game, town, e, f, 61.0, rng)
			check(absf(float(f["income_parts"]["business funding"]) + pending * 7.0) < 0.001, "next ordinary turn reports previously transferred funding once")
			check(not f.has("farm_funding_pending"), "reported external funding is consumed")
			Game.day = 62.0; e["day"] = 62.0; f["last"] = 61.0
			f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}; f["cond"] = 1.0
			Families.turn(Game, town, e, f, 62.0, rng)
			check(absf(float(f["income_parts"]["business funding"])) < 0.000001, "subsequent turn never reports the same funding a second time")
func floor_contract() -> void:
	var gone := Families._blank(1); gone["gone"] = true; gone["farm_funding_pending"] = 25.0
	Families.turn(Game, {}, {}, gone, 1.0, RandomNumberGenerator.new())
	check(float(gone.get("farm_funding_pending", 0.0)) == 25.0, "early family exit retains unreported funding")
	if not Businesses.new().has_method("fund_farm"): return
	for purse in [80.0, 100.0, 150.0, 10000.0]:
		var f := Families._blank(1); f["purse"] = purse
		var b := {"type": "farm", "closed": false, "cap": 2, "workers": 3, "wage": 100.0, "till": 0.0, "owed": 700.0, "t_paid": 0.0}
		var expected := minf(3100.0, maxf(0.0, purse - 5.0 * TownEcon.COIN))
		var inj := float(Businesses.new().call("fund_farm", f, b))
		check(inj == expected and float(b["till"]) == expected and float(f["purse"]) == purse - expected, "bounded funding retains original five-coin floor and actual staff reserve")
		check(float(b["owed"]) == 700.0 and float(b.get("t_paid", 0.0)) == -expected, "limited savings preserve wage liability and funding offset")
		var repeat := float(Businesses.new().call("fund_farm", f, b))
		check(repeat == 0.0 and float(b["till"]) + float(f["purse"]) == purse, "repeat helper neither fabricates coin nor overfunds")
func run(_tree: SceneTree) -> int:
	for seed_v in [901, 2026, 8801]: scenario(seed_v)
	floor_contract()
	print("FARM CAPACITY FUNDING checks=", checks, " failures=", fails)
	return fails
