extends RefCounted
## Ingredient identity determines packed weight/value and salvage room. Old mixed
## rations keep their former weight/value, in the same feeding inventory.

var fails := 0

func check(ok: bool, why: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func run(_tree: SceneTree) -> int:
	Game.new_game(127)
	Game.company.clear()
	Game.stash.clear()
	Game.world["company_goods"] = {}
	Game.gold = 0
	_check_legacy()
	_check_named_rows()
	_check_salvage()
	return fails

func _food_rows() -> Array:
	return Baggage.view(Baggage.rows(Game), "food")

func _row_named(rows: Array, name: String) -> Dictionary:
	for row in rows:
		if row["name"] == name:
			return row
	return {}

func _check_legacy() -> void:
	Game.provisions = Food.stock_from_save({"meal": [[4, 10]], "beer": [[3, 0]], "wine": [[2, 0]]})
	var t := Goods.table()
	var expected_weight := 4 * float(t["grain"]["weight"]) + 3 * float(t["beer"]["weight"]) + 2 * float(t["wine"]["weight"])
	var expected_value := int(round(4 * float(Food.BASE_PRICE["meal"]))) + int(round(3 * float(Food.BASE_PRICE["beer"]))) + int(round(2 * float(Food.BASE_PRICE["wine"])))
	var rows := _food_rows()
	var totals := Baggage.totals(rows)
	check(rows.size() == 3 and int(totals["count"]) == 9, "legacy saves retain three food/drink rows and all portions")
	check(is_equal_approx(float(totals["kg"]), expected_weight) and is_equal_approx(Food.food_weight(Game), expected_weight), "legacy meals retain grain-weight baggage and capacity accounting")
	check(int(totals["value"]) == expected_value, "legacy aggregate provisions keep their base values")
	var mixed := _row_named(rows, "Mixed rations")
	check(not mixed.is_empty() and mixed["id"] == "meal" and int(mixed["qty"]) == 4, "unidentified food stays honestly mixed rations")

func _check_named_rows() -> void:
	Game.provisions = Food.new_stock()
	Food.add_stock(Game, "meal", 4, 10)
	Food.add_stock(Game, "meal", 2, 9, "fruit", "Pears")
	Food.add_stock(Game, "meal", 3, 0, "fruit", "Pears")
	Food.add_stock(Game, "meal", 6, 0, "fruit", "Apples")
	Food.add_stock(Game, "meal", 7, 0, "grain", "Oats")
	Food.add_stock(Game, "meal", 3, 0, "meat", "Mutton")
	Food.add_stock(Game, "beer", 3)
	Food.add_stock(Game, "wine", 2)
	var before := Food.stock_to_save(Game)
	var rows := _food_rows()
	var t := Goods.table()
	var weight := 11 * float(t["fruit"]["weight"]) + 11 * float(t["grain"]["weight"]) + 3 * float(t["meat"]["weight"]) + 3 * float(t["beer"]["weight"]) + 2 * float(t["wine"]["weight"])
	var pears := _row_named(rows, "Pears")
	var apples := _row_named(rows, "Apples")
	var mutton := _row_named(rows, "Mutton")
	check(rows.size() == 7 and not pears.is_empty() and not apples.is_empty() and not mutton.is_empty(), "baggage retains ingredient names and distinct local varieties")
	if not pears.is_empty():
		check(pears["id"] == "fruit" and int(pears["qty"]) == 5 and is_equal_approx(float(pears["kg"]), 5 * float(t["fruit"]["weight"])), "same-named lots aggregate with actual fruit weight")
	if not mutton.is_empty():
		check(mutton["id"] == "meat" and int(mutton["value"]) == int(round(3 * float(t["meat"]["price"]))), "named meat uses its own value instead of grain meal value")
	var total := Baggage.totals(rows)
	check(int(total["count"]) == 30 and is_equal_approx(float(total["kg"]), weight) and is_equal_approx(Food.food_weight(Game), weight), "baggage and capacity include each physical portion once")
	check(Food.stock_to_save(Game) == before, "baggage accounting leaves lots unchanged")
	Game.provisions = Food.stock_from_save(JSON.parse_string(JSON.stringify(before)))
	check(_food_rows() == rows, "save/load retains named baggage identity, count, weight and value")
	check(Food.take(Game, "meal", 6) == 6, "older mixed food and named fruit are eaten from the shared ledger")
	var remaining := Baggage.totals(_food_rows())
	var removed := 4 * float(t["grain"]["weight"]) + 2 * float(t["fruit"]["weight"])
	check(int(remaining["count"]) == 24 and is_equal_approx(float(remaining["kg"]), weight - removed), "consumption removes exactly the consumed ingredients' weight")

func _check_salvage() -> void:
	var living := Unit.create("human", "player")
	var dead := Unit.create("human", "player")
	dead.dead = true
	Game.company = [living, dead]
	Game.provisions = Food.new_stock()
	var t := Goods.table()
	var capacity := Supplies.capacity(1)
	var full_fruit := int(ceil(capacity / float(t["fruit"]["weight"])))
	Food.add_stock(Game, "meal", full_fruit, 0, "fruit", "Pears")
	var full := Food.stock_to_save(Game)
	var loser := {"stores": {"meat": 5, "beer": 5, "wine": 5, "fruit": 5, "grain": 5}}
	var got := Supplies.company_take(Game, loser)
	check(got.is_empty() and Food.stock_to_save(Game) == full, "a fruit-filled company has no false grain-weight room for salvage")
	check(loser["stores"].is_empty(), "uncarried beaten-force stores remain lost on the field")
	Game.provisions = Food.new_stock()
	Food.add_stock(Game, "meal", 2)
	var source := {"grain": 2, "fruit": 3, "meat": 4, "beer": 2, "wine": 1}
	loser = {"stores": source.duplicate()}
	var start_weight := Food.food_weight(Game)
	var source_weight := Supplies.weight(source)
	check(start_weight + source_weight <= capacity, "salvage conservation fixture fits living company capacity")
	got = Supplies.company_take(Game, loser)
	check(got == source and loser["stores"].is_empty(), "every available source good transfers once when it fits")
	for good in Goods.FOODS:
		check(Food.food_stock(Game, good) == int(source[good]), "salvaged " + good + " retains its ingredient count")
	check(Food.stock(Game, "meal") == 11 and Food.stock(Game, "beer") == 2 and Food.stock(Game, "wine") == 1, "salvage preserves the feeding/drink aggregates")
	check(is_equal_approx(Food.food_weight(Game), start_weight + source_weight) and Food.food_weight(Game) <= capacity, "salvage adds exact physical weight within capacity")
	var rows := _food_rows()
	check(not _row_named(rows, "Fruit").is_empty() and not _row_named(rows, "Meat").is_empty() and not _row_named(rows, "Grain").is_empty(), "salvage appears as its actual foods in baggage")
	var totals := Baggage.totals(rows)
	check(is_equal_approx(float(totals["kg"]), Food.food_weight(Game)) and int(totals["count"]) == 14, "baggage and salvage capacity agree after mixed/named transfers")
