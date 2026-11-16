extends RefCounted
## "Buy best from local shops": buys only upgrades / rule items, within gold, gold goes down, gear goes on.
const Fixture = preload("res://tests/fixtures/group_g_v100.gd")

func run(_t) -> int:
	var fails := 0
	Fixture.new_world(31)
	# v0.100: explicit subject and a strictly better same-material shirt, independent of starter/stock rolls.
	var leaders := Fixture.company(31, [1])
	if leaders.size() != 1 or Game.company.size() != 2 or Game.world.get("towns", {}).is_empty():
		printerr("FAIL: buy-best fixture has a town, officer and troop"); return 1
	var tid: String = Game.world["towns"].keys()[0]
	var town: Dictionary = Game.world["towns"][tid]
	Game.location = tid
	var u: Unit = Game.company[1]
	u.equip["body"] = Item.make("mail_shirt", "copper", 0)
	var cur: Item = u.equip.get("body", null)
	# v0.100: keep generated non-body shop items while ensuring `better` is the top body upgrade and an equal-score shirt is rejected.
	var better := Item.make(cur.tid if cur != null else "mail_shirt", "copper", 5)
	# v0.100: use the planner's player price, including Appraiser and standing, for the affordability cap.
	town["shop"] = (town["shop"] as Array).filter(func(it: Item) -> bool:
		return it.slot() != "body" and Market.price(town, it) <= 10000)
	town["shop"].append(Item.make("mail_shirt", "copper", 0))
	town["shop"].append(better)
	Game.gold = 100000
	var plan := Market.plan_best_for_unit(Game, town, u)
	var has_better := false
	for b in plan["buys"]:
		if b["item"] == better: has_better = true
		var c: Item = u.equip.get(b["slot"], null)
		if c != null and c.tid == (b["item"] as Item).tid and Outfit.score(b["item"]) <= Outfit.score(c):
			print("planned a downgrade in ", b["slot"]); fails += 1
	if cur != null and not has_better:
		print("did not plan the better armour"); fails += 1
	var g0 := Game.gold
	var n := Market.buy_best_for_unit(Game, town, u, plan)
	print("bought %d pieces for %d gold" % [n, g0 - Game.gold])
	if n != plan["buys"].size() or Game.gold != g0 - int(plan["total"]): fails += 1
	if cur != null and u.equip.get("body") != better: fails += 1
	# No money: nothing planned.
	Game.gold = 0
	if not Market.plan_best_for_unit(Game, town, u)["buys"].is_empty(): fails += 1
	Game.location = ""
	return fails
