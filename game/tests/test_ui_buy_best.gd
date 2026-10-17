extends RefCounted
## "Buy best from local shops": buys only upgrades / rule items, within gold, gold goes down, gear goes on.
func run(_t) -> int:
	var fails := 0
	Game.new_game(31)
	var tid: String = Game.world["towns"].keys()[0]
	var town: Dictionary = Game.world["towns"][tid]
	Game.location = tid
	var u: Unit = Game.company[1]
	var cur: Item = u.equip.get("body", null)
	# Put a clearly better copy of his body armour (or a mail shirt) in the shop.
	var better := Item.make(cur.tid if cur != null else "mail_shirt", "copper", 5)
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
