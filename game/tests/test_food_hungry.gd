extends RefCounted
## v0.014: the hungry count agrees with the food in stock. Douglas saw "18 men are hungry" beside "Food: 10 days
## on Normal" with 410 meals: after hungry days the men waited for the next fixed meal and ate one meal a tick.
## Now (Food.feed_hungry) a Hungry man eats as soon as there are meals (on buying, at every tick) under Normal
## and Feast; only Short rations leave men hungry with meals in stock, and the warning says so.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", what)

func hungry() -> int:
	return Food.eaters(Game).filter(func(u): return u.belly < Food.FED).size()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(5)
	Game.location = ""
	var town: Dictionary = {}
	for id in Game.world["towns"]:
		if TownEcon.has_econ(Game.world["towns"][id]):
			town = Game.world["towns"][id]
			break
	# the company ran out and went hungry (some starving)
	Game.provisions = Food.new_stock()
	Game.rations = {"food": "normal", "drink": "ration"}
	var i := 0
	for u in Food.eaters(Game):
		u.belly = [3.0, 12.0, 25.0, 38.0][i % 4]
		i += 1
	Game.food_clock = {"next": Food.next_tick_after(Game.day), "last": Game.day, "march": 0.0}
	check(hungry() == Food.eaters(Game).size() and Food.warning(Game).contains("hungry"), "no food: all hungry, warned")
	Game.gold = 1000000
	check(Food.buy(Game, town, "meal", 410) == "", "buy 410 meals")
	check(Food.stock(Game, "meal") > 0 and hungry() == 0, "after buying, nobody is hungry (%d hungry, %d meals)" % [hungry(), Food.stock(Game, "meal")])
	check(not Food.warning(Game).contains("hungry"), "no hungry warning beside a full larder: " + Food.warning(Game))
	# loot or a gift: stock arrives without buying; the next tick (even midday under Normal) feeds the hungry
	for u in Food.eaters(Game):
		u.belly = 10.0
	Food.add_stock(Game, "meal", 100)
	var t := float(Game.food_clock["next"])
	Game.day = t + 0.001
	Food.on_time(Game, 0.001, true)
	check(hungry() == 0, "one tick later the hungry have eaten (%d hungry)" % hungry())
	# over days of marching with meals in stock nobody goes hungry
	var worst := 0
	for k in 120:
		Game.day += 0.05
		Game.world["party"]["path"] = [Vector2(1, 1)]
		Food.on_time(Game, 0.05, false)
		if Food.stock(Game, "meal") > 0:
			worst = maxi(worst, hungry())
	Game.world["party"]["path"] = []
	check(worst == 0, "marching six days with meals in stock: never hungry (worst %d)" % worst)
	# Short rations: men go hungry by choice, and the warning names the rations
	Game.rations["food"] = "short"
	Food.add_stock(Game, "meal", 200)
	for u in Food.eaters(Game):
		u.belly = 20.0
	check(Food.feed_hungry(Game) == 0 and hungry() > 0, "Short rations: no extra meals")
	check(Food.warning(Game).contains("on Short rations"), "the warning names the rations: " + Food.warning(Game))
	# out of stock the count stands
	Game.rations["food"] = "normal"
	Game.provisions = Food.new_stock()
	check(Food.feed_hungry(Game) == 0 and hungry() > 0 and Food.warning(Game).to_lower().contains("food runs out"), "no meals: hungry and warned")
	return fails
