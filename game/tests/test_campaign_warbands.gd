extends RefCounted
## Warband simulation over days: bands move and stay on passable ground, factions respawn patrols,
## strong hostiles chase the party, weak ones flee, the party travels to a town and arrives,
## and a beaten faction fields fewer bands for a while.

func run(_tree: SceneTree) -> int:
	var fails := 0
	Game.new_game(555)
	var w: Dictionary = Game.world
	var start := {}
	for wid in w["warbands"]:
		start[wid] = w["warbands"][wid]["pos"]
	var t0 := Time.get_ticks_msec()
	for i in 100:   # 5 days
		Game.advance_time(0.05, false)
		w["encounter"] = ""
	print("5 days simulated in %d ms; %d warbands; log tail: %s" % [Time.get_ticks_msec() - t0, w["warbands"].size(), w["log"].slice(-3)])
	var moved := 0; var survived := 0
	for wid in start:
		if w["warbands"].has(wid):
			survived += 1
			if (w["warbands"][wid]["pos"] as Vector2).distance_to(start[wid]) > 30.0:
				moved += 1
	print("moved %d of %d survivors" % [moved, survived])
	if moved < survived / 2:
		print("FAIL: warbands are not roaming"); fails += 1
	for wid in w["warbands"]:
		var p: Vector2 = w["warbands"][wid]["pos"]
		if not CampaignWorld.passable(w, p):
			print("FAIL: warband %s on impassable ground at %s (%s)" % [wid, p, CampaignWorld.terrain_at(w, p)]); fails += 1
	# ---------------------------------------------------------------- chase and flee
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	# diplomacy: orcs and goblins start hostile to the company at -60 (Douglas); push them to -100 anyway
	# make the company hated by both so their bands hunt it, as the old fixed reputation did
	Diplomacy.add_earned(Game, "orc_horde", -100, "test")
	Diplomacy.add_earned(Game, "goblin_warren", -100, "test")
	if not CampaignWorld.is_hostile(Game, "orc_horde") or not CampaignWorld.is_hostile(Game, "goblin_warren"):
		print("FAIL: standing -100 is not hostile"); fails += 1
	var ppos: Vector2 = w["party"]["pos"]
	w["party"]["safe_until"] = 0.0
	var dir := Vector2.RIGHT
	# (staged: the scene's 40 orcs on the map whole. The draft takes only the home town's spare young men, and with the
	# barge economy working ~85% of the land the orc town has about a dozen to spare: 11 of 40 were raised, too few to
	# hunt the company. This tests the chase rule, not the draft: test_econ_army tests the draft.)
	var big := CampaignWorld.spawn_warband(Game, "orc_horde", ppos + dir * 180.0, 40, "raider", rng, {"staged": true})
	var small := CampaignWorld.spawn_warband(Game, "goblin_warren", ppos - dir * 160.0, 2, "raider", rng)
	var d_big0: float = (w["warbands"][big]["pos"] as Vector2).distance_to(ppos)
	var d_small0: float = (w["warbands"][small]["pos"] as Vector2).distance_to(ppos)
	var contact := false
	for i in 30:
		Game.advance_time(0.02, false)
		if w["encounter"] == big:
			contact = true
			break
	var d_big1: float = (w["warbands"][big]["pos"] as Vector2).distance_to(w["party"]["pos"])
	var d_small1: float = (w["warbands"][small]["pos"] as Vector2).distance_to(w["party"]["pos"]) if w["warbands"].has(small) else 999.0
	print("big orc band: %.0f -> %.0f px (contact %s); small goblin band: %.0f -> %.0f px" % [d_big0, d_big1, contact, d_small0, d_small1])
	if not contact and d_big1 >= d_big0:
		print("FAIL: strong hostile band did not chase"); fails += 1
	if d_small1 <= d_small0:
		print("FAIL: weak hostile band did not flee"); fails += 1
	var rep := CampaignWorld.scout_report(Game, big)
	print("scouting the orcs: ", rep["count_text"], "; ", rep["gear_text"], "; ", rep["strength_text"])
	# retreat clears the encounter and gives a safe window
	CampaignWorld.retreat(Game, big)
	if w["encounter"] != "" or float(w["party"]["safe_until"]) <= Game.day:
		print("FAIL: retreat"); fails += 1
	CampaignWorld.remove_warband(Game, big)
	CampaignWorld.remove_warband(Game, small)
	# ---------------------------------------------------------------- travel into a town
	var town: Dictionary = w["towns"][w["start_town"]]
	w["party"]["safe_until"] = Game.day + 100.0
	CampaignWorld.set_travel(Game, town["pos"], town["id"])
	var arrived := false
	for i in 200:
		Game.advance_time(0.05, false)
		if w["party"]["arrived"] == town["id"]:
			arrived = true
			break
	if not arrived:
		print("FAIL: party never arrived at ", town["name"]); fails += 1
	# ---------------------------------------------------------------- faction weakening
	var fid := "goblin_warren"
	var before := CampaignWorld.desired_bands(w, fid)
	for i in 4:
		CampaignWorld.weaken_faction(w, fid, 8)
	var after := CampaignWorld.desired_bands(w, fid)
	print("goblin bands wanted: %d -> %d after four defeats" % [before, after])
	if after >= before:
		print("FAIL: beaten faction not weaker"); fails += 1
	return fails
