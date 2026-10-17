extends RefCounted
func run(_tree: SceneTree) -> int:
	Game.new_game(71)
	Game.provisions = Food.new_stock()
	Food.add_stock(Game, "meal", 7, 10)
	Food.add_stock(Game, "meal", 13, 4, "fruit", "Pears")
	Food.add_stock(Game, "meal", 23, 0, "grain", "Oats")
	Food.add_stock(Game, "meal", 17, 0, "meat", "Mutton")
	Food.add_stock(Game, "beer", 9)
	Food.add_stock(Game, "wine", 3)
	var saved := Food.stock_to_save(Game)
	var weight := Food.food_weight(Game)
	var money := Game.gold
	Game.save_game()
	Game.provisions = Food.new_stock()
	if not Game.load_game():
		printerr("FAIL: actual campaign save did not load")
		return 1
	if Food.stock_to_save(Game) != saved or not is_equal_approx(Food.food_weight(Game), weight) or Game.gold != money:
		printerr("FAIL: campaign save changed food identity, order, count, mass or coins")
		return 1
	if Food.take(Game, "meal", 8) != 8 or Food.food_stock(Game, "fruit") != 12 or Food.food_stock(Game, "grain") != 23:
		printerr("FAIL: loaded campaign consumed a different ingredient/order")
		return 1
	print("ok: actual campaign save/load preserves named food and subsequent feeding")
	return 0
