extends RefCounted
## Loot (Douglas): gold is really paid; occasional items survive by condition; scrap becomes gold;
## coin on the bodies; fled enemies keep their kit; our dead's gear returns to the stash when we win.
func run(_t) -> int:
	var fails := 0
	var rng := RandomNumberGenerator.new(); rng.seed = 4
	var enemies: Array = Factory.make_warband(rng, "orc_horde", 40)
	# coinage: coin on a body comes out of his household's real purse (no household, no coin): the orcs belong to
	# families of an orc town
	Game.new_game(7)
	var otid := ""
	for tid in Game.world["towns"]:
		if Game.world["towns"][tid]["faction"] == "orc_horde":
			otid = tid
			break
	var ofams: Array = Game.world["towns"][otid]["econ"]["fams"]
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
	Game.new_game(8)
	var dead_man: Unit = Game.company[2]
	var gear_n := dead_man.equip.size()
	dead_man.dead = true
	var s0 := Game.stash.size(); var g0 := Game.gold
	var foes: Array = Factory.make_warband(rng, "goblin_warren", 6)
	for f in foes: f.dead = true
	Game.pending_battle = {"seed": 5}
	Game.finish_battle({"winner": 0, "player_units": Game.company.duplicate(), "enemy_units": foes, "enemy_fallen": foes, "enemy_fled": [], "events": []})
	var r: Dictionary = Game.last_result
	print("win: loot %d gold (%d coin), %d items kept, %d fallen pieces back; stash %d -> %d" % [int(r["loot_gold"]), int(r["loot_coin"]), r["loot_items"].size(), int(r["fallen_gear"]), s0, Game.stash.size()])
	if Game.gold <= g0 - Game.daily_wages(): fails += 1
	if int(r["fallen_gear"]) != gear_n or Game.stash.size() != s0 + gear_n + r["loot_items"].size(): fails += 1
	# Loss: dead man's gear does not come back, no loot.
	Game.new_game(9)
	var d2: Unit = Game.company[2]; d2.dead = true
	var s1 := Game.stash.size(); var g1 := Game.gold
	Game.pending_battle = {"seed": 6}
	Game.finish_battle({"winner": 1, "player_units": Game.company.duplicate(), "enemy_units": [], "enemy_fallen": [], "enemy_fled": [], "events": []})
	if Game.stash.size() != s1 or Game.gold != g1: fails += 1
	return fails
