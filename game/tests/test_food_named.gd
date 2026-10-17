extends RefCounted
## Named food uses the existing lot ledger; physical food and coins are conserved.
var fails := 0

func check(ok: bool, why: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", why)
	else:
		print("ok: ", why)

func run(_tree: SceneTree) -> int:
	Game.new_game(127)
	Game.company.clear()
	Game.provisions = Food.new_stock()
	Game.gold = 10000
	var town := {"goods": {"grain": 30, "fruit": 20, "meat": 10}, "size": 1}
	for good in Goods.FOODS:
		var old := int(Goods.supply(town, good))
		var coins := Food.food_cost(town, good, 5)
		var purse := Game.gold
		check(Food.buy_food(Game, town, good, 5) == "", "specific food can be bought")
		check(Goods.supply(town, good) == old - 5 and Food.food_stock(Game, good) == 5, "same good leaves the market and enters existing food lots")
		check(Game.gold == purse - coins, "specific food uses its actual price")
	check(Food.stock(Game, "meal") == 15 and Game.provisions.keys().size() == 3, "named food feeds existing ration queries without a second inventory")
	var before := Food.stock_to_save(Game)
	Game.gold = 0
	var stock: Dictionary = town["goods"].duplicate(true)
	check(Food.buy_food(Game, town, "grain", 5) != "" and Food.stock_to_save(Game) == before and town["goods"] == stock, "broke purchase does not change food")
	Game.gold = 10000
	check(Food.buy_food(Game, town, "meat", 50) == "" and Food.food_stock(Game, "meat") == 10 and Goods.supply(town, "meat") == 0, "purchase is capped to actual stock")
	check(Food.buy_food(Game, town, "meat", 1) != "" and Food.buy_food(Game, town, "grain", -1) != "" and Food.buy_food(Game, town, "iron", 1) != "", "no empty, negative or unsupported food purchase")
	Game.provisions = Food.new_stock()
	Food.add_stock(Game, "meal", 4, 5)
	Food.add_stock(Game, "meal", 3, 3, "fruit", "Pears")
	Food.add_stock(Game, "meal", 2, 0, "grain", "Oats")
	Food.add_stock(Game, "meal", 2, 0, "meat", "Mutton")
	check(Game.provisions["meal"].size() == 4, "same age does not merge different ingredients")
	var saved := Food.stock_to_save(Game)
	Game.provisions = Food.stock_from_save(JSON.parse_string(JSON.stringify(saved)))
	check(Food.stock_to_save(Game) == saved and Food.food_stock(Game, "fruit") == 3, "save/load retains actual names, ingredients, ages and counts")
	var many := Food.new_stock()
	for i in 30:
		many["meal"].append([i + 1, 0, "grain", "Recorded grain %d" % i])
	check(Food.stock_from_save(JSON.parse_string(JSON.stringify(many))) == many, "many same-age named lots keep their exact consumption order through save/load")
	check(Food.take(Game, "meal", 5) == 5 and Food.food_stock(Game, "fruit") == 2 and Food.food_stock(Game, "grain") == 2, "eating consumes oldest lots across foods and legacy supplies")
	Game.provisions = Food.stock_from_save({"meal": [[2, 20], [3, 0]], "beer": [[1, 0]], "wine": []})
	Food.add_stock(Game, "meal", 4, 20, "grain", "Oats")
	var spoiled := Food.age_stock(Game)
	check(int(spoiled.get("meal", 0)) == 6 and Food.stock(Game, "meal") == 3, "named and legacy lots share existing spoilage")
	check(Food.packed_food(Game)[0]["name"] == "Mixed rations", "old unidentified stock is honestly labelled")
	for seed_value in [19, 61]:
		Game.new_game(seed_value)
		Game.company.clear()
		Game.provisions = Food.new_stock()
		Game.gold = 10000
		var checked := 0
		for market in Game.world["towns"].values():
			for good in Goods.FOODS:
				if Goods.supply(market, good) < 1:
					continue
				var supply := Goods.supply(market, good)
				var till := Goods.market_gold(market)
				var cost := Food.food_cost(market, good, 1)
				var purse := Game.gold
				check(Food.buy_food(Game, market, good, 1) == "", "generated market sells real food")
				check(Goods.supply(market, good) == supply - 1 and absf(Goods.market_gold(market) - till - cost) < 0.0001 and Game.gold == purse - cost, "generated market keeps matching goods and payment ledgers")
				checked += 1
			if checked >= 3:
				break
		check(checked >= 3, "several real stock transfers checked per world")
	var person := Unit.create("human", "player")
	Game.company = [person]
	person.belly = 0
	Game.provisions = Food.new_stock()
	Game.rations = {"food": "normal", "drink": "dry"}
	Game.food_clock = {"last": Game.day, "next": Food.next_tick_after(Game.day), "march": 0.0}
	var source := {"goods": {"grain": 10}, "size": 1}
	check(Food.buy_food(Game, source, "grain", 3) == "" and person.belly >= Food.FED and Food.stock(Game, "meal") == 1, "hungry people actually eat purchased named food")
	person.belly = 100
	Game.provisions = Food.new_stock()
	Game.gold = 1000
	var quote := TownProvisionsTab.pack_plan(Game, source)
	check(int(quote["needed"]) == 14 and int(quote["missing"]) == 7 and int(quote["lines"][0]["qty"]) == 7, "7-day packing quote is bounded by actual stocks and ration need")
	check(Goods.supply(source, "grain") == 7 and Food.stock(Game, "meal") == 0, "packing preview is read-only")
	person.belly = 0
	source["goods"]["grain"] = 16
	quote = TownProvisionsTab.pack_plan(Game, source)
	check(int(quote["needed"]) == 16 and int(quote["hunger"]) == 2 and int(quote["missing"]) == 0, "7-day quote includes the existing immediate hunger feeding")
	check(Food.buy_food(Game, source, "grain", int(quote["lines"][0]["qty"])) == "" and Food.stock(Game, "meal") == 14 and is_equal_approx(Food.food_days(Game), 7.0), "packing quote leaves a full seven days after hungry people eat")
	_check_seven_day_reserve(person, source)
	return fails

func _check_seven_day_reserve(person: Unit, source: Dictionary) -> void:
	Game.gold = 10000
	source["goods"]["grain"] = 100
	var last_day := int(Food.SPOIL_DAYS["meal"]) - 1
	var boundary := int(Food.SPOIL_DAYS["meal"]) - 7
	var cases := [
		{"name": "food spoiling tonight is not a seven-day reserve", "belly": 100, "lots": [[14, last_day, "fruit", "Pears"]], "needed": 14, "older": 14, "safe": 0, "unfilled": 0},
		{"name": "fourteen fresh portions already fill the reserve", "belly": 100, "lots": [[14, 0]], "needed": 0, "older": 0, "safe": 14, "unfilled": 0},
		{"name": "old supplies feed hunger before fresh reserve", "belly": 0, "lots": [[2, last_day], [14, 0]], "needed": 0, "older": 0, "safe": 14, "unfilled": 0},
		{"name": "only uneaten older food is excluded", "belly": 0, "lots": [[14, last_day]], "needed": 14, "older": 12, "safe": 0, "unfilled": 0},
		{"name": "fresh food eaten now reduces safe reserve", "belly": 0, "lots": [[14, 0]], "needed": 2, "older": 0, "safe": 12, "unfilled": 0},
		{"name": "FIFO hunger uses old food then safe food", "belly": 0, "lots": [[1, last_day], [14, 0]], "needed": 1, "older": 0, "safe": 13, "unfilled": 0},
		{"name": "unfilled hunger is added to reserve purchases", "belly": 0, "lots": [[1, last_day]], "needed": 15, "older": 0, "safe": 0, "unfilled": 1},
		{"name": "expiry at seven days is excluded", "belly": 100, "lots": [[14, boundary]], "needed": 14, "older": 14, "safe": 0, "unfilled": 0},
		{"name": "food keeping beyond seven days counts", "belly": 100, "lots": [[14, boundary - 1]], "needed": 0, "older": 0, "safe": 14, "unfilled": 0}
	]
	for fixture in cases:
		person.belly = float(fixture["belly"])
		Game.provisions = Food.stock_from_save({"meal": fixture["lots"]})
		var stored := Food.stock_to_save(Game)
		var market := source.duplicate(true)
		var clock := Game.food_clock.duplicate(true)
		var purse := Game.gold
		var belly := person.belly
		var quote := TownProvisionsTab.pack_plan(Game, source)
		check(int(quote["needed"]) == int(fixture["needed"]) and int(quote["older"]) == int(fixture["older"]) and int(quote["safe"]) == int(fixture["safe"]) and int(quote["hunger_unfilled"]) == int(fixture["unfilled"]), fixture["name"])
		var listed := 0
		for line in quote["lines"]:
			listed += int(line["qty"])
		check(listed == int(fixture["needed"]) and int(quote["missing"]) == 0, "reserve quote lists the actual shortage")
		check(Food.stock_to_save(Game) == stored and source == market and Game.gold == purse and Game.food_clock == clock and person.belly == belly, "reserve preview is read-only")
	var empty_market := {}
	TownProvisionsTab.pack_plan(Game, empty_market)
	check(empty_market.is_empty(), "empty stand-in market stays unchanged during quote")
