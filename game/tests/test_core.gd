extends RefCounted
## Core data model smoke test: data loads, every faction can field a warband, a new game
## generates a company, and save/load round-trips.

func run(_tree: SceneTree) -> int:
	var fails := 0
	print("weapons: ", DB.weapons.size(), " armor: ", DB.armor.size(), " factions: ", DB.factions.size())
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for fid in DB.factions:
		var band: Array = Factory.make_warband(rng, fid, 3)
		if band.size() != 3:
			fails += 1
		for u in band:
			var gear := []
			for s in u.equip: gear.append(u.equip[s].display_name())
			print("%s | %s %s | STR %d AGI %d | %.1f kg gear, %d gold | %s" % [fid, u.title, u.name, u.attr("STR"), u.attr("AGI"), u.gear_mass(), u.gear_value(), ", ".join(gear)])
	# DF-style race rolls: orcs sit high on STR, goblins low; every unit has a ceiling = 2x base.
	var sums := {"orc": 0, "goblin": 0}
	for i in 200:
		for race in sums:
			var v := Factory.roll_attr(rng, race, "STR")
			sums[race] += v
	print("mean STR orc %d goblin %d" % [sums["orc"] / 200, sums["goblin"] / 200])
	if sums["orc"] <= sums["goblin"]:
		fails += 1
	var t: Unit = Factory.make_warband(rng, "orc_horde", 1)[0]
	for a in DB.ATTRS:
		if t.attr_cap[a] != DB.attr_ceiling(t.attr_base[a], int(Factory.att_range(t.race, a)[3]), DB.TALENT_LEVELS[t.talent[a]]) or t.attrs[a] > DB.ATTR_HARD_CAP:
			fails += 1
	print("percentile of 1000 STR for orc: %.2f, goblin: %.2f" % [Factory.attr_percentile("orc", "STR", 1000), Factory.attr_percentile("goblin", "STR", 1000)])
	var o: Unit = Factory.make_warband(rng, "orc_horde", 1)[0]
	print("orc mind: ambition=%s LIN=%d age=%d values=%s" % [o.ambition, o.mind["LIN"], o.age, o.values])
	print("orc personality: ", o.personality, " size h%d b%d mass %.1f" % [o.size_h, o.size_b, o.mass()])
	if o.personality.size() != DB.TRAITS.size():
		fails += 1
	Game.new_game(42)
	var n: int = Game.company.size()
	print("company: ", n, " gold ", Game.gold)
	Game.save_game()
	if not Game.load_game() or Game.company.size() != n:
		fails += 1
	return fails
