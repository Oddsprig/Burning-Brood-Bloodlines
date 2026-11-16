extends RefCounted
## Loot (Douglas): gold is really paid; occasional items survive by condition; scrap becomes gold;
## coin on the bodies; fled enemies keep their kit; our dead's gear returns to the stash when we win.
const Fixture = preload("res://tests/fixtures/group_g_v100.gd")

func run(_t) -> int:
	var fails := 0
	var rng := RandomNumberGenerator.new(); rng.seed = 4
	# coinage: coin on a body comes out of his household's real purse (no household, no coin): the orcs belong to
	# families of an orc town
	Fixture.new_world(7)
	# v0.100: generate test Units after world generation, which resets the global UID floor.
	var enemies: Array = Factory.make_warband(rng, "orc_horde", 40)
	var otid := ""
	for tid in Game.world["towns"]:
		if Game.world["towns"][tid]["faction"] == "orc_horde":
			otid = tid
			break
	if otid == "" or enemies.size() != 40:
		printerr("FAIL: loot fixture has an orc town and 40 enemies"); return 1
	var ofams: Array = Game.world["towns"][otid]["econ"]["fams"]
	if ofams.size() < 2:
		printerr("FAIL: orc town supplies non-estate households"); return 1
	for i in enemies.size():
		var e: Unit = enemies[i]
		e.home_town = otid
		e.family = 1 + i % (ofams.size() - 1)
		if i % 2 == 0:   # half took a beating: cut through the upper body
			e.body.wound_part("torso_upper")["layers"][0]["kind"] = "cut"   # sparse bodies (v0.013): the writable part
			e.body.wound_part("torso_upper")["layers"][0]["dmg"] = 0.8
		e.dead = i < 30
	var fled: Array = enemies.slice(36, 40)
	var sp := Loot.spoils(enemies, fled, 99, 0.25)
	var n_items: int = sp["items"].size()
	print("40 orcs (4 fled): kept %d items, %d gold from scrap/rags, %d coin, scrap %s" % [n_items, int(sp["gold"]), int(sp["coin"]), str(sp["scrap_kg"])])
	if int(sp["gold"]) <= 0 or int(sp["coin"]) <= 0: fails += 1
	if n_items == 0 or n_items > 40: fails += 1   # occasional finds, not none, not a flood
	for f in fled:
		if (f as Unit).equip.is_empty(): print("fled orc lost his kit"); fails += 1
	var sp2 := Loot.spoils(Factory.make_warband(rng, "orc_horde", 5), [], 99, 0.25)
	# Through finish_battle: win returns our dead's gear; gold actually rises.
	# v0.100: reuse the real markets; only the detached company changes between battle fixtures.
	var leaders := Fixture.company(8, [2])
	if leaders.size() != 1 or Game.company.size() != 3:
		printerr("FAIL: win fixture has an officer and two troops"); return fails + 1
	Game.gold = 100000
	# v0.100: the original all-scrap-sold case needs a funded real buyer under v0.020's payment rules.
	var buyer := Salvage.nearest(Game.world, Game.world["party"]["pos"])
	var market := Salvage._market(buyer)
	if market.is_empty():
		printerr("FAIL: loot fixture has a real market payment ledger"); return fails + 1
	market["till"] = maxf(float(market["till"]), 1000000.0)
	var till0 := float(market["till"])
	var dead_man: Unit = Game.company[2]
	var gear_n := dead_man.equip.size()
	if gear_n == 0:
		printerr("FAIL: win casualty carries actual recoverable gear"); return fails + 1
	dead_man.dead = true
	var s0 := Game.stash.size(); var g0 := Game.gold
	var foes: Array = Factory.make_warband(rng, "goblin_warren", 6)
	for f in foes: f.dead = true
	Game.pending_battle = {"seed": 5}
	Game.finish_battle({"winner": 0, "player_units": Game.company.duplicate(), "enemy_units": foes, "enemy_fallen": foes, "enemy_fled": [], "events": []})
	var r: Dictionary = Game.last_result
	print("win: loot %d gold (%d coin), %d items kept, %d fallen pieces back; stash %d -> %d" % [int(r["loot_gold"]), int(r["loot_coin"]), r["loot_items"].size(), int(r["fallen_gear"]), s0, Game.stash.size()])
	if Game.gold <= g0 - Game.daily_wages(): fails += 1
	if Game.gold != g0 + int(r["loot_gold"]) or int(r["loot_gold"]) <= 0: fails += 1
	if absf(till0 - float(market["till"]) - float(int(r["loot_gold"]) - int(r["loot_coin"]))) > 0.001: fails += 1
	if int(r["fallen_gear"]) != gear_n or Game.stash.size() != s0 + gear_n + r["loot_items"].size(): fails += 1
	# Loss: dead man's gear does not come back, no loot.
	leaders = Fixture.company(9, [2])
	if leaders.size() != 1 or Game.company.size() != 3:
		printerr("FAIL: loss fixture has an officer and two troops"); return fails + 1
	if (Game.company[2] as Unit).equip.is_empty():
		printerr("FAIL: loss casualty carries gear that must not return"); return fails + 1
	var d2: Unit = Game.company[2]; d2.dead = true
	var s1 := Game.stash.size(); var g1 := Game.gold
	Game.pending_battle = {"seed": 6}
	Game.finish_battle({"winner": 1, "player_units": Game.company.duplicate(), "enemy_units": [], "enemy_fallen": [], "enemy_fled": [], "events": []})
	if Game.stash.size() != s1 or Game.gold != g1: fails += 1
	return fails
