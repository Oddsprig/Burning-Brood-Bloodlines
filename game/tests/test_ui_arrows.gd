extends RefCounted
## Arrows on the Provisions tab (Douglas): buying fills archers' quivers (50 max each), the rest goes to stores.
func run(tree: SceneTree) -> int:
	var fails := 0
	Game.new_game(41)
	Game.gold = 100000
	var tid := ""
	var ak := ""
	for id in Game.world["towns"]:
		for a in DB.arrows:
			if int(Goods.supply(Game.world["towns"][id], a)) >= 200:
				tid = id; ak = a; break
		if tid != "": break
	if tid == "":
		print("no town with 200 arrows of one kind"); return 1
	var t: Dictionary = Game.world["towns"][tid]
	# give two company men bows with empty quivers
	var bow_id: String = DB.bows.keys()[0]
	for i in 3:
		var bu: Unit = Game.company[i]
		bu.equip["ranged"] = Item.make(bow_id, "wood", 0)
	var archers := []
	for u in Game.company:
		if u.has_method("bow") and u.bow() != null:
			u.quiver.clear(); archers.append(u)
	print("archers in the company: ", archers.size())
	var got := BowsEcon.buy_for_company(Game, t, ak, 200)
	BowsEcon.fill_company_quivers(Game)
	var in_q := 0
	for u in archers:
		if u.arrows() > DB.QUIVER_MAX: fails += 1
		in_q += u.arrows()
	var left := int(floor(float(Goods.company_goods(Game).get(ak, 0.0))))
	print("bought %d, %d in quivers, %d in stores" % [got, in_q, left])
	if got != 200 or in_q + left != 200: fails += 1
	if archers.size() > 0 and in_q != mini(200, archers.size() * DB.QUIVER_MAX): fails += 1
	# the Provisions tab builds with the arrow rows
	Game.location = tid
	var s: Node = load("res://ui/town.tscn").instantiate()
	tree.root.add_child.call_deferred(s)
	await tree.process_frame
	s.show_tab("Provisions")
	await tree.process_frame
	s.queue_free()
	Game.location = ""
	return fails
