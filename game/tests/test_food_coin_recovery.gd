extends RefCounted
## Small native fixtures only: no world generation or campaign daily ticks.
var fails: int = 0

class FixtureGame:
	extends RefCounted
	var world: Dictionary = {}
	var gold: float = 0.0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func farm_and_barn() -> void:
	var f: Dictionary = Families._blank(1)
	f["m"] = 1; f["land"] = {"grain": 800}; f["purse"] = 100000.0
	var e: Dictionary = {"culture": "middle", "day": 241, "fams": [Families.make_estate({}), f],
		"price": {"grain": 3.6, "fruit": 5.0, "meat": 20.0, "fresh_meat": 20.0},
		"stock": {}, "barn": {}, "hh": {}, "req": {}, "stats": {"sales": 0.0},
		"biz": [{"till": 100000.0, "spend": 0.0}], "mkt": 0, "farm_till": 0.0,
		"need": {"grain": 1000.0}}
	var b: Dictionary = {"type": "farm", "closed": false, "cap": 100, "workers": 100,
		"wage": 100.0, "till": 0.0, "owed": 10000.0}
	var before: float = float(f["purse"])
	var paid: float = Businesses.fund_farm(f, b, e)
	check(paid == 90000.0, "farm can fund earned wages and eight days of existing capacity beyond the investment cap")
	check(float(b["owed"]) == 10000.0 and float(f["purse"]) + float(b["till"]) == before, "payroll funding conserves coins and preserves earned claims")
	check(Businesses.fund_farm(f, b, e) == 0.0, "same payroll reserve cannot be funded twice")
	check(absf(Businesses.owner_fund_room(f) - 990.0) < 0.001, "discretionary trades retain their ten-percent cap")
	HarvestClaims.add(e, "grain", 200, {"f:1": 200.0}, 241)
	check(HarvestClaims.food_reserve_days(e, f) == 29.0, "year-three spring protects food until the next summer")
	check(HarvestClaims.available(e, "grain") == 142, "only next-harvest food is withheld from the broker")
	TownEcon._barn_sales(e, TownEcon.data())
	check(int(e["stock"]["grain"]) == 142 and int(e["barn"]["grain"]) == 58, "physical surplus actually reaches the market")
	check(absf(float(e["biz"][0]["till"]) + float(e["farm_till"]) - 100000.0) < 0.001, "broker payment conserves coins")
	check(float(e["harvest_book"]["cash"]["f:1"]) > 0.0, "sale proceeds retain the actual producer")
	for day in [151, 181, 211]:
		e["day"] = day
		check(HarvestClaims.food_reserve_days(e, f) == float(270 - day), "harvest and winter protect food through the next spring")
	f["purse"] = 100000.0; f["store"]["food"] = 0.0
	e["stock"] = {}; e["barn"] = {}; e.erase("harvest_book"); e["req"] = {}
	EconomyRules.cover_food(e, f, 7.0, 241.0)
	check(float(e["req"].get("grain", 0.0)) == 14.0, "empty market retains the affordable unfilled essential order once")
	check(float(f["purse"]) == 100000.0 and float(f["store"]["food"]) == 0.0, "unfilled demand creates neither food nor money")

func run(_tree: SceneTree) -> int:
	farm_and_barn()
	var f: Dictionary = Families._blank(1)
	f["m"] = 1
	var rate: float = 2.0
	f["purse"] = 7.0 * rate * TownEcon.markup()
	var e: Dictionary = {"culture": "middle", "day": 0, "fams": [f],
		"price": {"grain": 100.0, "fruit": 1.0}, "stock": {"grain": 1000, "fruit": 1000},
		"barn": {}, "hh": {}, "req": {}, "stats": {"sales": 0.0},
		"biz": [{"till": 0.0}], "mkt": 0, "farm_till": 0.0}
	var before: float = float(f["purse"])
	check(absf(EconomyRules.essential_food_cost(e, 14.0) - before) < 0.00001, "reserve quotes affordable fruit before dear grain")
	EconomyRules.cover_food(e, f, 7.0, 0.0)
	check(float(f["store"]["food"]) >= 7.0, "available cheap food covers the full week")
	check(int(e["stock"]["grain"]) == 1000 and int(e["stock"]["fruit"]) == 986, "real substitute stock was used")
	check(absf(float(f["purse"]) + float(e["biz"][0]["till"]) - before) < 0.00001, "food purchase conserves coin")

	f = Families._blank(1)
	f.merge({"cohort": true, "race": "human", "households": 5, "m": 10,
		"kids": 10, "homes": 5, "hungry": 1, "pp": [], "kp": [],
		"age_bins": {"0:-20": 10, "1:-5": 10}, "population_year": 0,
		"fshort": 1.0, "pool_condition": {"workers": 0.5, "children": 0.5}}, true)
	var residents: int = Families.people(f)
	Population.turn({"culture": "middle"}, f, 7.0, 7.0)
	check(float(f["pool_condition"]["workers"]) > 0.5, "fully fed workers recover during another group's short ration")
	check(float(f["pool_condition"]["children"]) < 0.5, "actual child hunger still reduces condition")
	check(Families.people(f) == residents, "condition recovery does not create people")

	var game: FixtureGame = FixtureGame.new()
	e = {"pop0": 8000, "treasury": 1000000.0, "farm_till": 0.0, "fams": [],
		"mint_biz": 0, "mkt": 1, "req": {}, "stats": {}, "led": {"used": {}},
		"stock": {"copper_bars": 1000000, "tin_bars": 1000000, "bronze_bars": 0, "wood": 1000000},
		"price": {"copper_bars": 1.0, "tin_bars": 1.0, "bronze_bars": 1.0, "wood": 1.0},
		"biz": [{"workers": 9, "cap": 9, "wage": 1.0, "till": 0.0, "closed": false}, {"till": 0.0}]}
	var town: Dictionary = {"id": "mint", "econ": e}
	game.world = {"towns": {"mint": town}, "factions": {}}
	Barge.init_world(game)
	var target: float = float(game.world["coin"]["target"])
	# Twelve years of the coin pass only; no population/economy simulation.
	for day in 12 * int(EconGen.YEAR_DAYS):
		Barge.coin_town(game, town, e)
		var held: float = Barge.holdings(game)
		var L: Dictionary = game.world["coin"]
		check(absf(held - (float(L["cast"]) - float(L["melted"]) - float(L["drained"]))) < 0.001, "coin ledger balances")
		check(held <= target + 0.001 and held > target - 100.001, "replacement stays within one mint lot of opening holdings")
	check(float(game.world["coin"]["cast"]) > target, "a full treasury still replaces drained world coin")
	game.world["coin"]["target"] = float(game.world["coin"]["cast"]) - float(game.world["coin"]["melted"]) - float(game.world["coin"]["drained"])
	var cast: float = float(game.world["coin"]["cast"])
	Barge.mint_day(game, town, e)
	check(float(game.world["coin"]["cast"]) == cast, "no world deficit means no extra casting")
	# A vacant mint must request inputs without pretending anyone worked.
	game.world["coin"]["target"] = float(game.world["coin"]["target"]) + 20000.0
	e["biz"][0]["workers"] = 0
	e["stock"] = {}; e["req"] = {}
	Barge.mint_day(game, town, e)
	check(float(game.world["coin"]["cast"]) == cast and e["biz"][0]["state"] == "hands", "vacant mint creates no coins")
	check(float(e["req"].get("copper_bars", 0.0)) > 0.0 and float(e["req"].get("wood", 0.0)) > 0.0, "vacant mint still orders missing inputs")
	e["biz"][0]["workers"] = 9
	e["stock"] = {"copper_bars": 1000, "tin_bars": 1000, "wood": 1000}
	Barge.coin_town(game, town, e)
	check(float(game.world["coin"]["cast"]) > cast, "native coin-town path resumes minting with actual crew and inputs")
	cast = float(game.world["coin"]["cast"])
	e["biz"][0]["workers"] = 0; e["biz"][0]["kw"] = 1
	Barge.coin_town(game, town, e)
	check(float(game.world["coin"]["cast"]) > cast, "working keeper still mints after paid minters leave")
	f = Families._blank(1); f["land"] = {"grain": 8}; f["ox"] = -1
	e = {"culture": "middle", "day": 0, "climate": "temperate", "price": {"grain": 1.0}}
	var annual: float = 0.0
	for season in 4:
		annual += Families.seasonal_need_hands(f, float(season * Calendar.DAYS_PER_SEASON), e) / 4.0
	var net: float = 8.0 * 200.0 * float(TownEcon.data()["market"]["broker_share"]) * (1.0 - float(TownEcon.data()["tax"]["grain_share"])) / EconGen.YEAR_DAYS
	check(absf(EconomyRules.farm_hand_value(e, f) * annual - net) < 0.00001, "annual seasonal payroll fits actual net farm sales")
	return fails
