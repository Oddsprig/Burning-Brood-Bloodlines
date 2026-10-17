extends RefCounted
## Town operations: buying moves gold and items, selling, buy-to-fill, hiring into a squad,
## promote / move / dismiss.

var fails := 0

func check(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)

func run(_tree: SceneTree) -> int:
	Game.new_game(7)
	var town := DevTown.make("t1", 3)
	# buy
	var it: Item = town["shop"][0]
	var p := Market.price(town, it)
	var g0 := Game.gold
	check(Market.buy(Game, town, it) == "", "buy succeeds")
	check(Game.gold == g0 - p and Game.stash.has(it) and not town["shop"].has(it), "buy moves gold and item")
	Game.gold = 0
	check(Market.buy(Game, town, town["shop"][0]) != "", "cannot buy broke")
	# sell
	Game.gold = 100
	var sp := Market.sell_price(town, it)
	check(Market.sell(Game, town, it) == "" and Game.gold == 100 + sp and town["shop"].has(it), "sell returns gold")
	# buy to fill
	Game.gold = 5000 * Item.COIN   # coinage x20
	var off: Unit = Roster.leaders(Game)[1]
	for t in Roster.troops_of(Game, off.uid):
		Outfit.strip(t, Game.stash)
	Game.stash.clear()
	Game.squads[off.uid] = {"uniform": {"body": "mail_shirt"}, "material": "any"}
	var r := Market.buy_to_fill(Game, town)
	print("buy_to_fill: ", r)
	var shirts := Roster.troops_of(Game, off.uid).filter(func(t): return t.equip.has("body") and t.equip["body"].tid == "mail_shirt").size()
	check(r["bought"].size() >= 2 and shirts >= 2, "buy to fill bought and equipped shirts (%d)" % shirts)
	# hire
	Game.gold = 1000
	var rec: Unit = town["recruits"][0]
	var cost := int(Roster.offer(Game, rec)["hire_cost"])
	var n := Game.company.size()
	check(Roster.hire(Game, town, rec, off.uid) == "", "hire succeeds")
	check(Game.company.size() == n + 1 and rec.squad == off.uid and rec.faction == "player", "recruit joins the squad")
	check(Game.gold == 1000 - cost and not town["recruits"].has(rec), "hire costs gold and leaves the town")
	Game.gold = 0
	check(Roster.hire(Game, town, town["recruits"][0], off.uid) != "", "cannot hire broke")
	# full squad
	Game.gold = 100000
	while Roster.troops_of(Game, off.uid).size() < Roster.MAX_TROOPS and not town["recruits"].is_empty():
		Roster.hire(Game, town, town["recruits"][0], off.uid)
	var extra := Factory.make_troop(RandomNumberGenerator.new(), "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 1)
	extra.squad = -1
	Game.company.append(extra)
	if Roster.troops_of(Game, off.uid).size() >= Roster.MAX_TROOPS:
		check(Roster.move_troop(Game, extra, off.uid) != "", "full squad refuses")
	check(Roster.move_troop(Game, extra, Game.lead_officer().uid) == "" and extra.squad == Game.lead_officer().uid, "move to captain's squad")
	# promote and dismiss
	check(Roster.promote(Game, extra) == "" and extra.is_officer() and Game.squads.has(extra.uid), "promote")
	var t0: Unit = Roster.troops_of(Game, off.uid)[0]
	Roster.move_troop(Game, t0, extra.uid)
	var stash_n := Game.stash.size()
	var gear_n := extra.equip.size()
	check(Roster.dismiss(Game, extra) == "" and not Game.company.has(extra), "dismiss officer")
	check(t0.squad == -1 and Roster.unassigned(Game).has(t0), "their troop is unassigned")
	check(Game.stash.size() == stash_n + gear_n, "dismissed gear goes to stash")
	for i in 10:
		if Roster.officer_count(Game) >= Roster.MAX_OFFICERS:
			break
		var e := Roster.promote(Game, Roster.troops_of(Game, off.uid)[0])
		if e != "":
			printerr("promote failed: ", e)
	check(Roster.promote(Game, Roster.troops_of(Game, off.uid)[0]) != "", "officer cap enforced")
	# words
	check(UiWords.skill_level(0) == "Dabbling" and UiWords.skill_level(15) == "Legendary" and UiWords.skill_level(17) == "Legendary+2", "skill level names")
	var med := UiWords.race_median("orc", "STR")
	# Words follow the race score (40-60 typical): word, colour and number agree (playtest fix).
	check(UiWords.attr_word("STR", 1000 + 500, "human") == "very strong" and UiWords.attr_word("AGI", 700, "human") == "quite clumsy", "attribute words: %s / %s" % [UiWords.attr_word("STR", 1500, "human"), UiWords.attr_word("AGI", 700, "human")])
	check(UiWords.attr_word("STR", med, "orc") == "typical" and UiWords.attr_phrase("STR", med + 120, "orc") == "strong for an orc", "race-relative words: " + UiWords.attr_phrase("STR", med + 120, "orc"))
	for v in [250, 600, 900, 1000, 1100, 1400, 2200]:
		var pc := Factory.attr_percentile("human", "AGI", v) * 100.0
		check((UiWords.attr_tone("human", "AGI", v) < 0) == (pc < 40.0), "word tone matches score at %d" % v)
	return fails
