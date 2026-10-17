extends RefCounted
## Conserved native care purchases; no world generation, units or save-file writes.
const NativeFixture = preload("res://tests/test_dragon_identities.gd")
const PlotFixture = preload("res://tests/test_feudal_governance.gd")
var native: NativeFixture
var dragon_uid := ""
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon care: " + message)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001

func record() -> Dictionary:
	return Game.world["dragons"]["records"][dragon_uid]

func fixture() -> void:
	native = NativeFixture.new(); native.fixture()
	for town in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		e.merge({"mkt": 0, "biz": [{"id": 0, "type": "market", "owner": 0, "till": 5000.0,
			"cap": 0, "workers": 0, "wage": 10.0, "closed": false, "owed": 0.0}],
			"stock": {"grain": 100000, "meat": 10000, "fresh_meat": 0, "wood": 1000},
			"price": {"grain": 4.0, "fruit": 6.0, "meat": 12.0, "fresh_meat": 0.0, "wood": 5.0},
			"stats": {"sales": 0.0}, "req": {}, "led": {"made": {}, "used": {}, "spoil": {}},
			"hh": {"grain": 40}, "barn": {"meat": 17}, "granary": 500.0, "farm_till": 0.0,
			"plots": PlotFixture.new().empty_plots(), "crops": {}, "wacres": {}, "wherd": {},
			"open": [], "hands": 0, "idle_n": 0, "homes": 1, "food_short": 0.0, "unrest": 0.0, "fstage": 0}, true)
		for f in e["fams"]:
			f["purse"] = 100000.0; f["store"]["food"] = 14.0; f["last"] = 0.0
	Dragons.init_world(Game)
	dragon_uid = native.holding("a", "adult")
	var row: Dictionary = record()
	row["size_class"] = "small"; row["stage"] = "adult"
	row.erase("care"); row.erase("growth_points")
	DragonCare.initialize(row, 0)
	# Keep this one registered identity; other generated holdings are outside this fixture.
	Game.world["dragons"]["records"] = {dragon_uid: row}
	Dynasty.select_city(Game, "a")

func coins() -> float:
	var total: float = float(Game.gold)
	for town in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		total += float(e["treasury"]) + float(e["farm_till"])
		for f in e["fams"]: total += float(f["purse"])
		for b in e["biz"]: total += float(b["till"])
	for faction in Game.world["factions"].values(): total += float(faction["treasury"])
	return total

func protected_goods() -> String:
	var out: Dictionary = {}
	for tid in Game.world["towns"]:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		out[tid] = [e["hh"], e["barn"], e["granary"], e.get("hd", {}), e["pop"], e["adults"],
			e["fams"].map(func(f): return [f["store"], f["pp"], f["kp"], f.get("herd", {})])]
	return JSON.stringify(out)

func receipt_balances(e: Dictionary, payer: Dictionary, before_stock: Dictionary, before_purse: float, before_till: float) -> void:
	var last: Dictionary = record()["care"]["last"]
	var food: int = int(last["food_units"])
	var wood: int = int(last["upkeep_units"])
	var cost: float = float(last["food_cost"]) + float(last["upkeep_cost"])
	check(food > 0 and wood > 0 and near(float(last["food_ratio"]), 1.0) and near(float(last["care_ratio"]), 1.0), "available feed and shelter are actually supplied in full")
	check(int(before_stock["meat"]) - int(e["stock"]["meat"]) == food and int(before_stock["wood"]) - int(e["stock"]["wood"]) == wood,
		"receipt units equal exact native market meat/wood debits")
	check(near(float(last["food_cost"]), food * 12.0 * TownEcon.markup()) and near(float(last["upkeep_cost"]), wood * 5.0 * TownEcon.markup()), "actual costs use this location's posted retail prices")
	check(near(before_purse - float(payer["purse"]), cost) and near(float(e["biz"][0]["till"]) - before_till, cost) and near(float(e["stats"]["sales"]), cost), "private purse debit equals actual market till and sales credits")
	check(int(e["led"]["used"].get("meat", 0)) == food and int(e["led"]["used"].get("wood", 0)) == wood
		and near(float(e["req"].get("meat", 0.0)), food) and near(float(e["req"].get("wood", 0.0)), wood), "consumption ledger and full filled demand are recorded exactly once")

func full_care_and_guards() -> void:
	fixture()
	var row: Dictionary = record()
	var e: Dictionary = Game.world["towns"]["a"]["econ"]
	var payer: Dictionary = e["fams"][0]
	row["care"]["health"] = 0.8
	var physique: Dictionary = Dragons.physical_profile(Game, row)
	var goods: String = protected_goods()
	var total: float = coins()
	var rng_state: int = Game.rng.state
	var next_unit: int = Unit._next_uid
	Game.day = 0.99
	var before: String = native.snapshot()
	DragonCare.status(Game, row); DragonCare.status(Game, row); DragonCare.daily(Game, 0)
	check(native.snapshot() == before, "fractional-day quotes and already-initialized day cannot charge or mutate")
	Game.day = 7.75 # Queued care for day 1 must not use the final target time.
	before = native.snapshot()
	var quote: Dictionary = DragonCare.status(Game, row)
	check(quote["care_active"] and int(quote["food_possible_units"]) == int(quote["food_need_units"]) and native.snapshot() == before, "valid full-care quote is pure")
	var stock: Dictionary = e["stock"].duplicate(true)
	var purse: float = float(payer["purse"])
	var till: float = float(e["biz"][0]["till"])
	DragonCare.daily(Game, 1)
	receipt_balances(e, payer, stock, purse, till)
	var after_physique: Dictionary = Dragons.physical_profile(Game, row)
	check(float(row["care"]["health"]) > 0.8 and float(row["care"]["last"]["growth_after"]) > float(row["care"]["last"]["growth_before"]), "fed and supplied individual recovers health and earns bounded growth")
	check(float(after_physique["body_mass_kg"]) > float(physique["body_mass_kg"]) and after_physique["hardness_index"] == physique["hardness_index"]
		and after_physique["tooth_material"] == physique["tooth_material"], "earned physical growth increases mass without changing gem hardness/material")
	check(int(row["care"]["last_day"]) == 1 and int(row["care"]["last"]["day"]) == 1, "guard and receipt use the actual queued day, not final Game.day")
	check(protected_goods() == goods and near(coins(), total), "care consumes no household/barn/granary goods, people or net coin")
	check(Game.rng.state == rng_state and Unit._next_uid == next_unit, "care creates no native units or random draws")
	before = native.snapshot(); DragonCare.daily(Game, 1); DragonCare.daily(Game, 0)
	check(native.snapshot() == before, "repeated and older day calls preserve every book and receipt")

func remote_owner_and_unavailable() -> void:
	fixture()
	var remote_uid: String = native.uid("b", 10, 1)
	check(Dragons.transfer(Game, dragon_uid, remote_uid)["ok"], "real private remote owner receives the registered dragon")
	var local: Dictionary = Game.world["towns"]["a"]["econ"]
	var remote: Dictionary = Game.world["towns"]["b"]["econ"]
	var payer: Dictionary = remote["fams"][1]
	var stock: Dictionary = local["stock"].duplicate(true)
	var remote_stock: Dictionary = remote["stock"].duplicate(true)
	var purse: float = float(payer["purse"])
	var local_purse: float = float(local["fams"][0]["purse"])
	var remote_till: float = float(remote["biz"][0]["till"])
	var local_till: float = float(local["biz"][0]["till"])
	var total: float = coins()
	Game.day = 1.0; DragonCare.daily(Game, 1)
	receipt_balances(local, payer, stock, purse, local_till)
	check(remote["stock"] == remote_stock and near(float(remote["biz"][0]["till"]), remote_till)
		and near(float(local["fams"][0]["purse"]), local_purse), "remote owner's home market and local keeper household do not pay")
	check(record()["care"]["last"]["payer_household_uid"] == payer["household_uid"] and near(coins(), total), "actual remote household pays with conserved aggregate coin")
	for unavailable in ["keeper", "owner", "unclaimed", "market"]:
		fixture(); Game.day = 1.0
		var row: Dictionary = record()
		var e: Dictionary = Game.world["towns"]["a"]["econ"]
		match unavailable:
			"keeper": Dynasty._person(Game, str(row["custodian_person_uid"]))["person"][4] = "army"
			"owner": row["owner_person_uid"] = "missing-native-person"
			"unclaimed": row["owner_status"] = "unclaimed"
			"market": e["mkt"] = -1
		var physical: String = JSON.stringify(e["stock"])
		var cash: float = coins()
		var health: float = float(row["care"]["health"])
		var quote: Dictionary = DragonCare.status(Game, row)
		DragonCare.daily(Game, 1)
		var last: Dictionary = row["care"]["last"]
		check(not quote["care_active"] and str(quote["reason"]) != "" and int(last["food_units"]) == 0 and int(last["upkeep_units"]) == 0,
			"unavailable " + unavailable + " gives a reason and no free feed/shelter")
		check(JSON.stringify(e["stock"]) == physical and near(coins(), cash) and float(row["care"]["health"]) < health,
			"unavailable " + unavailable + " leaves goods/coin untouched and has a health consequence")

func mixed_feed_demand() -> void:
	fixture(); Game.day = 1.0
	var e: Dictionary = Game.world["towns"]["a"]["econ"]
	e["stock"]["fresh_meat"] = 3; e["price"]["fresh_meat"] = 8.0
	var quote: Dictionary = DragonCare.status(Game, record())
	var total: float = coins()
	DragonCare.daily(Game, 1)
	var last: Dictionary = record()["care"]["last"]
	var need: int = int(quote["food_need_units"])
	check(int(e["stock"]["fresh_meat"]) == 0 and 10000 - int(e["stock"]["meat"]) == need - 3
		and int(last["food_units"]) == need and near(float(last["food_ratio"]), 1.0), "real fresh meat and stored meat substitute within one complete daily ration")
	check(near(float(last["food_cost"]), (3.0 * 8.0 + float(need - 3) * 12.0) * TownEcon.markup()) and near(coins(), total), "mixed ration uses each actual local price with conserved coin")
	check(near(float(e["req"].get("fresh_meat", 0.0)) + float(e["req"].get("meat", 0.0)), need), "a fully filled substitute ration records one total food demand, not missing preferred food plus its replacement")
	e["stock"]["fresh_meat"] = 3; e["fams"][0]["purse"] = 1.0
	var before: String = native.snapshot()
	var poor: Dictionary = DragonCare.status(Game, record())
	var accounted: int = 0
	for order: Dictionary in poor["orders"]:
		if str(order["good"]) in ["fresh_meat", "meat"]:
			accounted += int(order["quantity"]) + int(order["unmet"]) + int(order["unaffordable"])
	check(accounted == int(poor["food_need_units"]) and int(poor["food_possible_units"]) == 0 and native.snapshot() == before,
		"both-meat unaffordable quote partitions one food need and remains pure")

func reserves_shortage_and_death() -> void:
	fixture(); Game.day = 1.0
	var e: Dictionary = Game.world["towns"]["a"]["econ"]
	var payer: Dictionary = e["fams"][0]
	payer["store"]["food"] = 0.0; payer["purse"] = 1.0
	var quote: Dictionary = DragonCare.status(Game, record())
	var stocks: String = JSON.stringify(e["stock"])
	var total: float = coins()
	DragonCare.daily(Game, 1)
	check(near(float(quote["spendable"]), 0.0) and JSON.stringify(e["stock"]) == stocks and near(coins(), total), "payer's seven-day human food gap protects its last coin from dragon feed/upkeep")
	fixture(); Game.day = 1.0
	e = Game.world["towns"]["a"]["econ"]
	e["stock"] = {"grain": 0, "meat": 1, "fresh_meat": 0, "wood": 0}
	e["hh"] = {}; e["barn"] = {}; e["granary"] = 0.0
	quote = DragonCare.status(Game, record())
	stocks = JSON.stringify(e["stock"]); total = coins()
	var row: Dictionary = record()
	row["care"]["health"] = 0.000001
	DragonCare.daily(Game, 1)
	check(int(quote["food_possible_units"]) == 0 and JSON.stringify(e["stock"]) == stocks and near(coins(), total), "local three-day essential-food reserve is not fed to a dragon")
	check(not row["alive"] and near(float(row["care"]["health"]), 0.0), "actual deprivation reaches death on the original individual record")
	e["stock"]["meat"] = 10000; e["stock"]["wood"] = 1000
	stocks = JSON.stringify(e["stock"]); total = coins()
	DragonCare.daily(Game, 2)
	check(not row["alive"] and JSON.stringify(e["stock"]) == stocks and near(coins(), total), "dead identity never receives later purchases or respawns")

func inheritance_and_json_guard() -> void:
	fixture()
	var e: Dictionary = Game.world["towns"]["b"]["econ"]
	var source: Dictionary = e["fams"][1]
	var destination: Dictionary = e["fams"][0]
	var owner: Array = Persons.by_pid(source, 10)
	var owner_uid: String = str(owner[Persons.PERSON_UID])
	var daughter: Array = native.person(e, source, 12, 1, 30, "", owner)
	daughter[1] = 1
	var daughter_uid: String = str(daughter[Persons.PERSON_UID])
	native.person(e, destination, 20, 0, 33, "")
	check(Persons.marriages(e, 0.0, 1) == 1 and destination["pp"].has(daughter), "native marriage puts actual eldest daughter in a different household")
	Feudal.finish(Game)
	check(Dragons.transfer(Game, dragon_uid, owner_uid)["ok"], "care holding gifted to the actual non-ruling father")
	native.kill(owner_uid); Feudal.finish(Game)
	var row: Dictionary = record()
	check(row["owner_person_uid"] == daughter_uid and row["owner_household_uid"] == destination["household_uid"], "post-death asset owner resolves the rightful moved heir")
	var purse: float = float(destination["purse"])
	var prior: float = float(source["purse"])
	Game.day = 1.0; DragonCare.daily(Game, 1)
	var last: Dictionary = row["care"]["last"].duplicate(true)
	check(last["payer_household_uid"] == destination["household_uid"] and near(float(source["purse"]), prior)
		and near(purse - float(destination["purse"]), float(last["food_cost"]) + float(last["upkeep_cost"])), "inherited care charges the successor's actual new household, never the dead owner's estate")
	var saved: Dictionary = Game._save_tree()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	Game.world = Game._deserialize(parsed["world"])
	Game.day = float(parsed["day"]); Game.gold = int(parsed["gold"])
	Dragons.after_load(Game)
	row = record()
	check(row["owner_person_uid"] == daughter_uid and row["owner_household_uid"] == destination["household_uid"]
		and int(row["care"]["last_day"]) == 1 and near(float(row["care"]["health"]), float(saved["world"]["dragons"]["records"][dragon_uid]["care"]["health"])), "native current JSON load preserves exact owner refs, care guard and health")
	var before: String = native.snapshot()
	DragonCare.daily(Game, 1); Dragons.after_load(Game)
	check(native.snapshot() == before, "load normalization and same-day care cannot charge again or rewrite receipts")
	check(near(float(record()["care"]["last"]["food_cost"]), float(last["food_cost"])) and int(record()["care"]["last"]["food_units"]) == int(last["food_units"]), "current JSON keeps actual receipt amounts and units")

func run(_tree: SceneTree) -> int:
	var old_world: Dictionary = Game.world
	var old_company: Array = Game.company
	var old_squads: Dictionary = Game.squads
	var old_day: float = Game.day
	var old_gold: float = Game.gold
	var old_location: String = Game.location
	full_care_and_guards(); remote_owner_and_unavailable(); mixed_feed_demand(); reserves_shortage_and_death(); inheritance_and_json_guard()
	Game.world = old_world; Game.company = old_company; Game.squads = old_squads
	Game.day = old_day; Game.gold = old_gold; Game.location = old_location
	print("dragon care: %d checks, %d failures" % [checks, fails])
	return fails
