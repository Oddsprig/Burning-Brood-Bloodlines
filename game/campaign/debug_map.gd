extends Node
## Debug/preview scene for the campaign map: new game from a seed, then the map screen.
##   godot --path game res://campaign/debug_map.tscn -- --seed=1234 --view=overview|travel|encounter
## (used with --write-movie to check the map visually)

func _ready() -> void:
	var seed_v := 1234
	var view := "travel"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="): seed_v = int(a.substr(7))
		if a.begins_with("--view="): view = a.substr(7)
		if a.begins_with("--size="): WorldGen.gen_size = a.substr(7)   # world size: normal | large | huge
	Game.new_game(seed_v)
	var w: Dictionary = Game.world
	if view == "encounter":
		# a strong orc band right next to the party: it chases and makes contact
		var rng := RandomNumberGenerator.new(); rng.seed = 5
		CampaignWorld.spawn_warband(Game, "orc_horde", w["party"]["pos"] + Vector2(70, 0), 24, "raider", rng, {"staged": true})
		w["party"]["waiting"] = true
	elif view == "travel":
		# head for the nearest other town
		var best := ""; var bd := INF
		for tid in w["towns"]:
			if tid == w["start_town"]: continue
			var d: float = w["towns"][tid]["pos"].distance_to(w["party"]["pos"])
			if d < bd: bd = d; best = tid
		CampaignWorld.set_travel(Game, w["towns"][best]["pos"], best)
	var map: Node = load("res://campaign/world_map.tscn").instantiate()
	add_child(map)
	if view == "overview":
		map.cam.zoom = Vector2(0.53, 0.53) / WorldGen.K   # the whole map (1.5x since war pick 5)
		map.terrain.set_zoom(map.cam.zoom.x)   # world size: no decor that far out on a large map
		map.follow = false
		map.cam.position = Vector2(WorldGen.W, WorldGen.H) * WorldGen.CELL * 0.5
