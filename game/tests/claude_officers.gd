extends RefCounted
## Per realm: field-army men, how many are house-born (can hold rank), and officer posts filled.
func run(tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var g := Game.new_game_begin(777)
	while not Game.new_game_slice(g, 8000): await tree.process_frame
	var h := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, h, 8000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Game.new_game_finalize()
	for fid in DB.factions:
		var units: Array = Army.members(Game, str(fid))
		if units.is_empty(): continue
		var noble := units.filter(func(u): return Army.house_born(u)).size()
		for k in 4: Army.update_tree(Game, str(fid), Army.members(Game, str(fid)), false, int(Game.day))
		var posts: Array = Army.rec(Game.world, str(fid))["posts"]
		var filled := posts.filter(func(x): return int(x) >= 0).size()
		print("officers: %s men %d house-born %d posts %d filled %d" % [fid, units.size(), noble, posts.size(), filled])
	return 0
