extends RefCounted
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", why)

func cash(e: Dictionary) -> float:
	var result := float(e["treasury"])
	for f in e["fams"]: result += float(f["purse"])
	for b in e["biz"]: result += float(b["till"])
	return result

func adult(e: Dictionary, day: int) -> Dictionary:
	var f := Families._blank(e["fams"].size())
	f["m"] = 1; f["seed"] = 829431; f["name"] = "Batch fixture"; f["homes"] = 1; f["ox"] = 0
	f["purse"] = 1000.0; f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}
	f["tax_season"] = e["tax"]["season"]; f["last"] = float(day - 1); f["idle"] = 1
	e["fams"].append(f); Persons.generate(e, f, 0.0)
	var age := float(People.ages(Persons.race_of(e))["adult"]) + 2.0
	f["pp"][0][3] = float(day) - age * People.year_days(); f["nxa"] = 1000.0
	return f

func fixture(town: Dictionary, original: Dictionary, mode: String, owner_late: bool, half: int) -> void:
	var e: Dictionary = original.duplicate(true); town["econ"] = e
	var day := 60
	e["day"] = day; Game.day = float(day)
	# Keep generated physical ownership/animal ledgers. Only original household
	# turns/jobs are out of this bounded controlled employment fixture.
	for f in e["fams"]:
		for k in f["jobs"].keys(): Families.set_job(e, f, int(k), 0)
		Shelter.release_casual(e, f)
		f["gone"] = not f.get("estate", false); f["idle"] = 0; f["purse"] = 0.0
	for b in e["biz"]: b["closed"] = true; b["for_sale"] = false
	e["cjcap"] = {}; e["cjused"] = {}; e["idle_n"] = 0; e["treasury"] = 0.0
	for g in e["stock"]: e["stock"][g] = 0
	var remainder := day % 7 + half * 7
	while e["fams"].size() % 14 != remainder:
		var padding := Families._blank(e["fams"].size()); padding["gone"] = true; e["fams"].append(padding)
	var earlier := adult(e, day)
	for i in 13:
		var padding := Families._blank(e["fams"].size()); padding["gone"] = true; e["fams"].append(padding)
	var later := adult(e, day)
	var owner: Dictionary = later if owner_late else earlier
	var worker: Dictionary = earlier if owner_late else later
	owner["purse"] = 10000.0 if mode != "unfunded" else 100.0
	var physical = load("res://tests/farm_fixture_tools.gd").new()
	check(physical.grain(e, owner, 8), "real productive cereal fields transferred")
	check(Families.acres(owner) == 8 and physical.base_need(e, owner) > 1.0, "actual transferred holding needs hired work")
	TownEcon.recount(e)
	var farm := Businesses._row(e, "farm", int(owner["id"]), 0, TownEcon.data())
	owner["farm"] = int(farm["id"]); owner["hands"] = 1; owner["farm_harvest"] = false
	farm["wage"] = 40.0; farm["till"] = 700.0; farm["owed"] = 700.0
	farm["owed_unattributed"] = 700.0; farm["wage_claims"] = {}; farm["t_paid"] = 0.0
	farm["closed"] = mode == "no_offer"
	Businesses.rebuild_open(e)
	Families.refresh_worked(e, owner)
	check(Businesses.takeable(farm) == 0, "earned debt makes old farm cash unavailable for hiring")
	var before := cash(e)
	var drain := (float(owner["purse"]) + float(worker["purse"])) * float(Barge.B()["coin"]["drain"])
	TownEcon.family_batch(Game, town, day, half)
	check(absf(cash(e) - before + drain) < 0.00001, "batch moves existing cash only after ordinary one-day purse drain")
	check(float(owner["last"]) == day and float(worker["last"]) == day, "households have exactly their ordinary batch payday")
	check(float(farm["owed"]) == 700.0 and farm["wage_claims"].is_empty(), "matching preserves retained earned debt and adds no prior wages")
	check(float(worker.get("wage_receipts", 0.0)) == 0.0, "new farm hand receives no backdated wages")
	if mode == "funded":
		check(int(farm["cap"]) > 0, "ordinary owner harvest turn opens real farm capacity")
		check(int(farm["workers"]) == 1 and int(worker["idle"]) == 0, "completed batch fills genuinely funded private offer after civilian's earlier turn")
		check(float(farm["till"]) >= float(farm["owed"]) + 2.0 * float(farm["wage"]), "actual new hire remains backed after earned obligations")
	else:
		check(int(farm["workers"]) == 0 and int(worker["idle"]) == 1, "unfunded or closed farm never manufactures employment")
		check(Businesses.takeable(farm) == 0, "unfunded or closed batch has no genuine offer")
	check(not Families.assignments_stale(owner) and not Families.assignments_stale(worker), "batch preserves real adult assignment counts")
	var purse := cash(e); var last := float(worker["last"]); var debt := float(farm["owed"])
	Families.match_idle(e)
	check(cash(e) == purse and float(worker["last"]) == last and float(farm["owed"]) == debt, "repeated matching cannot transfer coins, advance payday or alter earned debt")
	if mode == "funded":
		WageClaims.accrue_day(e, day + 1)
		var paid := float(WageClaims.pay_family(e, worker)[0])
		check(absf(paid - float(farm["wage"])) < 0.00001, "next actual worked day earns exactly one hand's wage")
		check(absf(cash(e) - purse) < 0.00001 and float(farm["owed"]) == debt, "real wage payout preserves total cash and older debt")

func run(_tree: SceneTree) -> int:
	Game.new_game(901)
	var seen := {}
	for town in Game.world["towns"].values():
		var culture := String(town["econ"]["culture"])
		if seen.has(culture): continue
		seen[culture] = true
		var original: Dictionary = town["econ"].duplicate(true)
		for mode in ["funded", "unfunded", "no_offer"]:
			for half in [0, 1]: fixture(town, original, mode, true, half)
		fixture(town, original, "funded", false, 0)
	check(seen.size() == TownEcon.data()["cultures"].size(), "private batch regression covers every culture")
	print("PRIVATE FARM BATCH HIRING checks=", checks, " failures=", fails)
	return fails
