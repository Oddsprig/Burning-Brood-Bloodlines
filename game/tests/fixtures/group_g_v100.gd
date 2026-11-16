extends RefCounted
## v0.100: menu/food fixtures supply their own men; 6210641 deliberately starts unraised and penniless.

static func new_world(seed_value: int) -> void:
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.new_game(seed_value)

static func bare(seed_value: int) -> void:
	# v0.100: native state reset without terrain/history; generate_begin owns no running work.
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.new_game_begin(seed_value)
	Game.world = {}
	Game.new_game_finalize()

static func company(seed_value: int, troop_counts: Array) -> Array:
	# v0.100: only detached test Units, with exact squad sizes rather than legacy free starters.
	Game.company.clear()
	Game.squads.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for count in troop_counts:
		var officer := Factory.make_troop(rng, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 2)
		officer.role = "officer"
		officer.faction = "player"
		officer.wage = 12 * Item.COIN
		Game.company.append(officer)
		Game.squads[officer.uid] = {"uniform": {}, "material": "any"}
		for i in int(count):
			var troop := Factory.make_troop(rng, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 1)
			troop.role = "troop"
			troop.faction = "player"
			troop.squad = officer.uid
			troop.wage = 4 * Item.COIN
			Game.company.append(troop)
	Game.invalidate_deploy()
	return Roster.leaders(Game)
