extends RefCounted
## The town screen's Provisions tab: the company buys remedies for its own sick (06-sickness.md section 6). The
## button shows what Sickness.company_quote says (how many, the cost), pressing it runs Sickness.company_treat:
## gold and the market's remedy stock go down by exactly that, the case is marked treated, and the button goes.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)
	else:
		print("ok: ", msg)

func run(tree: SceneTree) -> int:
	Game.new_game(4410)
	var w: Dictionary = Game.world
	for wid in w["warbands"].keys():
		CampaignWorld.remove_warband(Game, wid)
	w["work"] = []
	var u: Unit = null
	var pr := []
	for x in Game.company:
		pr = Sickness._person_of(w, x)
		if not pr.is_empty() and TownEcon.has_econ(pr[0]):
			u = x
			break
	check(u != null, "a company man with a register record in a town with an economy")
	if u == null:
		return fails
	var t: Dictionary = pr[0]
	var e: Dictionary = t["econ"]
	var day := float(Game.day)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	check(Sickness.infect(Game, t, pr[1], pr[2], "flux", day - 5.0, "camp:test", rng, u), "infect the company man")
	var c := Sickness.case_of(pr[1], int(pr[2][0]))
	c[Sickness.C_ON] = day - 1.0
	c[Sickness.C_END] = day + 4.0
	c[Sickness.C_DIE] = -1.0
	c[Sickness.C_REM] = 0
	Sickness.mirror(u, c)
	check(u.sick_now(day), "he is sick now")
	e["stock"]["remedy"] = 3
	Game.gold = 500
	var q := Sickness.company_quote(Game, t)
	var price := int(ceil(float(q["price"])))
	check(int(q["need"]) >= 1 and int(q["treat"]) == int(q["need"]) and int(q["cost"]) == price * int(q["treat"]),
		"the quote: %s" % str(q))
	# the Provisions tab shows the button with the count and the cost
	Game.location = String(t["id"])
	var s: Node = load("res://ui/town.tscn").instantiate()
	tree.root.add_child.call_deferred(s)
	await tree.process_frame
	await tree.process_frame
	s.show_tab("Provisions")
	await tree.process_frame
	var b := s.find_child("BuyRemedies", true, false) as Button
	check(b != null and not b.disabled, "the Provisions tab has an enabled Buy remedies button")
	if b != null:
		var want := "Buy remedies for %d (%d coins)" % [int(q["treat"]), int(q["cost"])]
		check(b.text == want, "button text '%s' (want '%s')" % [b.text, want])
		var g0 := Game.gold
		var st0 := int(e["stock"]["remedy"])
		b.pressed.emit()
		await tree.process_frame
		check(Game.gold == g0 - int(q["cost"]), "gold down by the cost (%d -> %d)" % [g0, Game.gold])
		check(int(e["stock"]["remedy"]) == st0 - int(q["treat"]), "market remedy stock down by the count treated")
		check(int(c[Sickness.C_REM]) == 1, "his case is marked treated")
		var b2 := s.find_child("BuyRemedies", true, false)
		check(b2 == null or (b2 as Node).is_queued_for_deletion(), "the button is gone once nobody needs a remedy")
		# nothing to buy: no stock, a sick man without a remedy -> disabled button
		c[Sickness.C_REM] = 0
		e["stock"]["remedy"] = 0
		s.refresh()
		await tree.process_frame
		var b3 := s.find_child("BuyRemedies", true, false) as Button
		check(b3 != null and b3.disabled and Sickness.company_quote(Game, t)["treat"] == 0, "no stock: the button is there but disabled")
	s.queue_free()
	await tree.process_frame
	Game.location = ""
	return fails
