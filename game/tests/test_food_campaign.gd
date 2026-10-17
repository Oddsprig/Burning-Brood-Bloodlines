extends RefCounted
## Food and drink on the campaign side (core/food.gd, spec docs/specs/food-drink.md section 10):
##  - Normal rations keep a marching man Fed indefinitely (never Hungry, no mass lost)
##  - 3 days with no food => Starving, mass drops, the floor holds at 85%
##  - Ration drink: no drink-need penalty; Dry for 3 days: focus -10% and stress
##  - Free drink with Appetite 80 => Drunk at the evening tick and Hung over next day
##  - the focus total never goes past +-15%
## plus stock (oldest first, spoilage, out-of-stock sharing), market buying from town supply, the town feast,
## favourite drink rolls, and a save/load round trip of stock, rations and meters (and old-save migration).

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)

## A bare campaign with one or more plain men, no world (Game.advance_time still drives the food clock).
func _setup(n: int = 1, appetite: int = 50, meals: int = 1000, beer: int = 1000, wine: int = 0) -> Array:
	Game.new_game(321)
	Game.world = {"party": {"path": [Vector2(1, 1)]}}   # "travelling": the party marches
	Game.location = ""
	Game.company.clear()
	Game.squads.clear()
	Game.day = 0.0
	Game.gold = 100000
	var men := []
	for i in n:
		var u := Unit.create("human", "player")
		u.name = "Man %d" % i
		u.personality["appetite"] = appetite
		u.fav_drink = "beer"
		Game.company.append(u)
		men.append(u)
	Game.provisions = Food.new_stock()
	Food.add_stock(Game, "meal", meals)
	Food.add_stock(Game, "beer", beer)
	Food.add_stock(Game, "wine", wine)
	Game.rations = {"food": "normal", "drink": "ration"}
	Game.food_clock = {"next": Food.next_tick_after(0.0), "last": 0.0, "march": 0.0}
	Game.invalidate_deploy()
	return men

func _run_days(days: float, step: float = 0.05, watch: Callable = Callable()) -> void:
	var steps := int(round(days / step))
	for i in steps:
		Game.advance_time(step, false)
		if watch.is_valid():
			watch.call()

func run(_tree: SceneTree) -> int:
	_test_fed_march()
	_test_starving()
	_test_drink_need()
	_test_free_drink()
	_test_focus_cap()
	_test_stock()
	_test_market_and_feast()
	_test_fav_drink()
	_test_save_load()
	_test_ui_numbers()
	return fails

# ------------------------------------------------------------------ belly
func _test_fed_march() -> void:
	var u: Unit = _setup(1, 50, 12, 6)[0]
	var low := [100.0]
	var states := {}
	for chunk in 8:   # 40 days; fresh meals bought every 5 days (meals spoil at 21)
		_run_days(5.0, 0.05, func():
			low[0] = minf(low[0], u.belly)
			var s := Food.belly_state(u.belly)
			states[s] = int(states.get(s, 0)) + 1)
		Food.add_stock(Game, "meal", 12)
		Food.add_stock(Game, "beer", 6)
	print("  normal rations, 40 days marching: lowest belly %.1f, states sampled %s, mass x%.3f" % [low[0], str(states), u.mass_mult])
	check(low[0] >= Food.FED, "Normal rations keep a marching man Fed (never below %d; lowest %.1f)" % [int(Food.FED), low[0]])
	check(u.mass_mult >= 0.999 and u.stress < 1.0, "no mass lost and no hunger stress on Normal rations (stress %.1f, drink days %d)" % [u.stress, u.drink_days])
	check(Food.stock(Game, "meal") < 12 * 9, "meals were eaten from the stock (%d left)" % Food.stock(Game, "meal"))

func _test_starving() -> void:
	var u: Unit = _setup(1, 50, 0)[0]
	var rolled := u.rolled_mass()
	var m0 := u.mass()
	_run_days(3.0)
	check(Food.belly_state(u.belly) == "starving", "3 days with no food -> Starving (belly %.1f)" % u.belly)
	check(u.mass_mult < 1.0 and u.mass() < m0, "body mass drops (x%.3f, %.1f -> %.1f kg)" % [u.mass_mult, m0, u.mass()])
	check(u.stress > 0.0, "starving adds stress (%.1f)" % u.stress)
	_run_days(25.0, 0.25)
	check(absf(u.mass_mult - Food.MASS_FLOOR) < 0.0001, "mass floor holds at 85%% of rolled mass (x%.3f)" % u.mass_mult)
	check(u.mass() >= rolled * Food.MASS_FLOOR - 0.001, "mass() never under 85%% of rolled (%.1f of %.1f)" % [u.mass(), rolled])
	# feeding again regains mass
	Food.add_stock(Game, "meal", 500)
	_run_days(10.0, 0.25)
	check(u.mass_mult > Food.MASS_FLOOR + 0.05, "eating again regains mass (x%.3f)" % u.mass_mult)

# ------------------------------------------------------------------ drink need
func _test_drink_need() -> void:
	var u: Unit = _setup()[0]
	_run_days(5.0)
	check(u.drink_days == 0 and absf(Food.focus(u)) < 0.0001 and u.stress < 0.5, "Ration drink: no drink-need penalty (days %d, focus %.2f, stress %.1f)" % [u.drink_days, Food.focus(u), u.stress])
	var b := Food.buzz_state(u.buzz)
	print("  ration drinker buzz now %.1f (%s), hung over %s" % [u.buzz, b, str(u.hungover)])
	check(not u.hungover, "one mug a day does not leave a hangover")
	# Dry for 3 days
	Game.rations["drink"] = "dry"
	var s0 := u.stress
	_run_days(3.0)
	check(u.drink_days >= 3, "Dry: 3 days without drink counted (%d)" % u.drink_days)
	check(absf(Food.focus(u) - (-0.10)) < 0.0001, "Dry for 3 days: focus -10%% (%.3f)" % Food.focus(u))
	check(u.stress >= s0 + 2.0 * Food.DRINK_STRESS - 0.01, "Dry: stress +3/day from day 2 (%.1f -> %.1f)" % [s0, u.stress])
	# an elf takes half
	var e := Unit.create("moon_elf", "player")
	e.drink_days = 3
	check(absf(Food.focus(e) - (-0.05)) < 0.0001, "elves take x0.5 of the drink-need focus (%.3f)" % Food.focus(e))
	# met again
	Game.rations["drink"] = "ration"
	_run_days(1.0)
	check(u.drink_days == 0, "drinking again resets the need")

func _test_free_drink() -> void:
	var u: Unit = _setup(1, 80)[0]
	Game.rations["drink"] = "free"
	check(Food.want(u) == 4, "Appetite 80 wants 4 mugs (%d); Appetite 50 wants %d" % [Food.want(u), Food.want(Unit.create("human", "x"))])
	Game.advance_time(0.51, false)   # through the midday and evening (19:00) ticks of the first day
	print("  after the evening tick: buzz %.1f (%s), hung over %s" % [u.buzz, Food.buzz_state(u.buzz), str(u.hungover)])
	check(Food.buzz_state(u.buzz) == "drunk", "Free drink, Appetite 80 -> Drunk at the evening tick (buzz %.1f)" % u.buzz)
	_run_days(0.55)   # past the next morning tick
	check(u.hungover and Food.buzz_state(u.buzz) != "drunk", "Hung over next day (buzz %.1f)" % u.buzz)
	check(absf(Food.focus(u) - Food.HANGOVER_FOCUS) < 0.0001 and absf(Food.fatigue_mult(u) / float(Food.BELLY_FX[Food.belly_state(u.belly)]["fatigue"]) - Food.HANGOVER_FATIGUE) < 0.0001, "hangover: focus -10%%, fatigue gain x1.10 (%.2f, %.2f, belly %.0f)" % [Food.focus(u), Food.fatigue_mult(u), u.belly])
	Game.rations["drink"] = "ration"
	_run_days(1.0)
	check(not u.hungover, "the hangover clears at the next evening tick when he drinks less")

func _test_focus_cap() -> void:
	var u := Unit.create("human", "x")
	var worst := 0.0
	for belly in [0.0, 10.0, 20.0, 30.0, 50.0, 90.0]:
		for dd in 6:
			for hung in [false, true]:
				u.belly = belly; u.drink_days = dd; u.hungover = hung
				worst = maxf(worst, absf(Food.focus(u)))
	check(worst <= Food.FOCUS_CAP + 0.000001, "focus total never past +-15%% (worst %.3f)" % worst)
	u.belly = 30.0; u.drink_days = 5; u.hungover = true   # -5 -10 -10 = -25 raw
	check(absf(Food.focus(u) + Food.FOCUS_CAP) < 0.000001, "stacked penalties clamp at -15%% (%.3f)" % Food.focus(u))

# ------------------------------------------------------------------ stock
func _test_stock() -> void:
	var men := _setup(4, 50, 0, 0)
	Food.add_stock(Game, "meal", 3, 15)   # old lot
	Food.add_stock(Game, "meal", 5, 0)    # fresh lot
	check(Food.stock(Game, "meal") == 8, "stock counts every lot")
	check(Food.take(Game, "meal", 4) == 4 and Food.stock(Game, "meal") == 4 and int(Game.provisions["meal"][0][1]) == 0, "eat oldest first")
	Game.provisions = Food.new_stock()
	Food.add_stock(Game, "meal", 10, 20)
	Food.add_stock(Game, "beer", 10, 29)
	Food.add_stock(Game, "wine", 10, 400)
	var sp := Food.age_stock(Game)
	check(int(sp.get("meal", 0)) == 10 and int(sp.get("beer", 0)) == 10 and Food.stock(Game, "wine") == 10, "food spoils at 21 days, beer at 30, wine never (%s)" % str(sp))
	# out of stock: 4 men, 2 meals at a tick -> 2 eat, the rest go without; the next tick starts with the others
	for u in men:
		u.belly = 50.0
	Food.add_stock(Game, "meal", 2)
	Food._serve_meals(Game, men, 0)
	var fed := men.filter(func(u): return u.belly > 50.0)
	check(fed.size() == 2 and Food.stock(Game, "meal") == 0, "short stock: what's left is shared, the rest go without")
	Food.add_stock(Game, "meal", 2)
	Food._serve_meals(Game, men, 2)
	check(men.filter(func(u): return u.belly > 50.0).size() == 4, "the next tick feeds the ones who went without")
	# wine counts 1.5 mugs; favourite served when stocked
	var w: Unit = men[0]
	w.fav_drink = "wine"
	Food.add_stock(Game, "wine", 5)
	Food.add_stock(Game, "beer", 5)
	var z0 := w.buzz
	Food._serve_drinks(Game, [w], 0, true)
	check(Food.stock(Game, "wine") == 14 and w.fav_today and w.buzz > z0, "the favourite (wine) is served when stocked")
	check(absf(Food.buzz_per_drink(w, "wine") - 1.5 * Food.buzz_per_drink(w, "beer")) < 0.001, "wine adds 1.5x a mug's buzz")
	Game.rations["drink"] = "ration"
	var dd := Food.drink_days(Game)
	check(absf(dd - (5.0 + 1.5 * 14.0) / 4.0) < 0.001, "drink days count wine as 1.5 mugs (%.2f)" % dd)

func _test_market_and_feast() -> void:
	var men := _setup(3, 50, 0, 0, 0)
	var town := {"id": "tt", "name": "Testford", "size": 2, "wealth": 3, "specialty": "farming"}
	Goods.init_town(town)
	var sup0 := Goods.supply(town, "food")
	var c10 := Food.cost(town, "meal", 10)
	var g0 := Game.gold
	check(Food.buy(Game, town, "meal", 10) == "", "buy 10 meals")
	check(Food.stock(Game, "meal") == 10 and Game.gold == g0 - c10, "meals in stock, gold paid (%d)" % c10)
	check(absf(Goods.supply(town, "food") - (sup0 - 10.0)) < 0.01, "buying takes real supply out of the town (%.0f -> %.0f meals' worth)" % [sup0, Goods.supply(town, "food")])
	town["goods"]["beer"] = 12
	town["goods"]["wine"] = 4
	check(Food.available(town, "wine") == 4 and Food.available(town, "beer") == 12, "available follows town supply (economy units: mugs and cups)")
	Food.buy(Game, town, "wine", 50)
	check(Food.stock(Game, "wine") == 4 and Goods.supply(town, "wine") < 0.01, "buying is capped by the town's supply")
	town["goods"]["beer"] = 0
	check(Food.buy(Game, town, "beer", 5) != "", "none left to buy")
	# a real generated town: the gold goes to its market and the meals come out of its stock
	Game.new_game(17)
	var rt: Dictionary = Game.world["towns"].values()[0]
	var till0 := Goods.market_gold(rt)
	var food0 := Goods.supply(rt, "food")
	Game.gold = 1000
	var c20 := Food.cost(rt, "meal", 20)
	check(Food.buy(Game, rt, "meal", 20) == "", "buy meals in a generated town")
	check(absf(Goods.market_gold(rt) - till0 - float(c20)) < 0.01 and absf(Goods.supply(rt, "food") - (food0 - 20.0)) < 0.01,
		"meals bought from the real town market (gold to the market, food out of the stock)")
	men = _setup(3, 50, 0, 0, 0)
	var bare := {"id": "b", "name": "Nowhere", "size": 0}
	check(Food.cost(bare, "meal", 10) == 36 and Food.cost(bare, "beer", 10) == 60 and Food.cost(bare, "wine", 10) == 200, "fixed base prices where a town has no supply (coins: a grain meal 3.6, a mug 6, a cup 20)")
	check(Food.available(bare, "meal") == -1, "no supply = no limit")
	check(not Food.has_tavern(bare) and Food.has_tavern(town), "towns of size >= 1 have a tavern")
	# feast
	for u in men:
		u.belly = 30.0; u.stress = 40.0; u.buzz = 0.0
	Goods.init_town(town)
	var fc := Food.feast_cost(Game, town)
	g0 = Game.gold
	check(Food.feast(Game, town) == "", "feast the company")
	var u0: Unit = men[0]
	check(Game.gold == g0 - fc and fc > 0, "feast costs %d gold" % fc)
	check(u0.belly == 100.0 and absf(u0.stress - 25.0) < 0.01 and u0.merry_day == Game.day, "feast: belly 100, stress -15, make merry met")
	check(u0.buzz > Food.TIPSY and u0.drank_today, "feast: everyone gets the night's buzz (%.1f)" % u0.buzz)
	check(Food.feast(Game, bare) != "", "no feast without a tavern")

func _test_fav_drink() -> void:
	var counts := {}
	for race in ["human", "orc", "moon_elf", "troll"]:
		var wine := 0
		for i in 400:
			var u := Unit.create(race, "x")
			Food.roll_fav_drink(u, i * 7919 + race.hash())
			if u.fav_drink == "wine":
				wine += 1
		counts[race] = wine / 400.0
	print("  wine share: ", counts)
	check(absf(counts["human"] - 0.30) < 0.08 and absf(counts["orc"] - 0.15) < 0.07 and absf(counts["moon_elf"] - 0.75) < 0.08 and counts["troll"] < 0.2,
		"favourite drink odds follow race (human 30%, orc 15%, moon elf 75% wine)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var t := Factory.make_troop(rng, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0])
	check(t.fav_drink in ["beer", "wine"], "recruits roll a favourite drink (%s)" % t.fav_drink)
	check(UiWords.preference_line(t).contains(t.fav_drink), "shown next to favourite weapon/material: " + UiWords.preference_line(t))
	# the roll draws nothing from the recruitment rng
	var r1 := RandomNumberGenerator.new(); r1.seed = 99
	var r2 := RandomNumberGenerator.new(); r2.seed = 99
	var a := Unit.create("human", "x")
	Factory.roll_mind(r1, a)
	var b := Unit.create("human", "x")
	Factory.roll_mind(r2, b)
	check(r1.state == r2.state and a.fav_drink == b.fav_drink and r1.randi() == r2.randi(), "favourite drink roll is deterministic and leaves the rng alone")

# ------------------------------------------------------------------ save / load
func _test_save_load() -> void:
	Game.new_game(77)
	var u: Unit = Game.company[2]
	u.belly = 23.5; u.buzz = 41.25; u.hungover = true; u.drink_days = 2; u.mass_mult = 0.91; u.fav_drink = "wine"
	u.fav_bonus = true; u.drank_eq = 1.5; u.merry_day = 3.0
	Game.provisions = Food.new_stock()
	Food.add_stock(Game, "meal", 33, 4)
	Food.add_stock(Game, "meal", 7, 0)
	Food.add_stock(Game, "beer", 12, 9)
	Food.add_stock(Game, "wine", 3, 100)
	Game.rations = {"food": "feast", "drink": "free"}
	Game.food_clock = {"next": 2.2916, "last": 2.0, "march": 0.1, "rot": 7}
	Game.save_game()
	Game.provisions = Food.new_stock(); Game.rations = {}; Game.food_clock = {}
	check(Game.load_game(), "load")
	var v: Unit = Game.unit_by_uid(u.uid)
	check(v != null and absf(v.belly - 23.5) < 0.001 and absf(v.buzz - 41.25) < 0.001 and v.hungover and v.drink_days == 2
		and absf(v.mass_mult - 0.91) < 0.0001 and v.fav_drink == "wine" and v.fav_bonus and absf(v.drank_eq - 1.5) < 0.001 and v.merry_day == 3.0,
		"unit meters round-trip")
	check(Food.stock(Game, "meal") == 40 and Game.provisions["meal"].size() == 2 and int(Game.provisions["meal"][0][1]) == 4
		and typeof(Game.provisions["meal"][0][0]) == TYPE_INT and Food.stock(Game, "beer") == 12 and Food.stock(Game, "wine") == 3,
		"stock lots and ages round-trip")
	check(Game.rations == {"food": "feast", "drink": "free"} and absf(float(Game.food_clock["next"]) - 2.2916) < 0.0001 and int(Game.food_clock["rot"]) == 7,
		"rations and meal clock round-trip")
	# an old save (no food fields at all) gets a seeded favourite drink and a starting stock
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	d.erase("provisions"); d.erase("rations"); d.erase("food_clock")
	for ud in d["company"]:
		for k in ["belly", "buzz", "hungover", "drink_days", "drank_today", "drank_eq", "fav_drink", "fav_today", "fav_bonus", "mass_mult", "merry_day"]:
			ud.erase(k)
	var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f = null
	check(Game.load_game(), "load an old save")
	var favs := Game.company.map(func(x): return x.fav_drink)
	check(not favs.has("") and Food.stock(Game, "meal") > 0 and Game.rations.get("food") == "normal", "old save migrated: favourite drinks %s, stock given" % str(favs))
	check(Game.load_game() and Game.company.map(func(x): return x.fav_drink) == favs, "the migration roll is seeded (same drinks on reload)")
	var w := Game.company[0] as Unit
	check(w.belly == Food.START_BELLY and w.mass_mult == 1.0, "old save units start Fed at full mass")

func _test_ui_numbers() -> void:
	_setup(4, 50, 10, 0)
	Game.rations = {"food": "normal", "drink": "ration"}
	check(absf(Food.food_days(Game) - 10.0 / 8.0) < 0.001, "food days at normal rations (%.2f)" % Food.food_days(Game))
	var w := Food.warning(Game)
	check(w.to_lower().contains("food") and w.contains("drink"), "one warning banner: " + w)
	Game.rations["drink"] = "dry"
	check(not Food.warning(Game).contains("drink"), "no drink warning when nothing is served")
	(Game.company[0] as Unit).belly = 20.0
	check(Food.warning(Game).contains("hungry"), "warns when anyone is Hungry: " + Food.warning(Game))
	check(Food.belly_effects(Game.company[0]).size() >= 2 and Food.buzz_effects(Game.company[0]).size() >= 2, "tap texts list the state's effects")
