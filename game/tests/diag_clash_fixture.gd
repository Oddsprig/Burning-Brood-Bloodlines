extends RefCounted
func run(_tree: SceneTree) -> int:
	var suite = load("res://tests/test_arms_trade.gd").new()
	Game.new_game(5150)
	suite._quiet(Game.world)
	suite._test_generation(Game.world)
	var ledger := ArmsTrade.ledger.duplicate()
	suite._test_clash_loot(Game.world)
	for k in ArmsTrade.ledger:
		var n := int(ArmsTrade.ledger[k]) - int(ledger.get(k, 0))
		if n != 0: print("CLASH_LEDGER ", k, " ", n)
	return suite.fails
