extends RefCounted
## End-to-end flow, headless: title -> new campaign -> map -> town -> company -> battle (real sim,
## skipped to the end) -> aftermath -> map, through the real Main scene and Game.goto.

func run(tree: SceneTree) -> int:
	var fails := 0
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child.call_deferred(main)
	await tree.process_frame
	await tree.process_frame
	if main.current == null or not main.current.scene_file_path.ends_with("title.tscn"):
		print("flow: title screen missing"); fails += 1
	Game.new_game(1234)
	for screen in ["map", "company", "settings"]:
		Game.goto(screen, {"back": "map"})
		await tree.process_frame
		await tree.process_frame
		if main.current == null or main.current is Label:
			print("flow: screen failed: ", screen); fails += 1
	var tid: String = Game.world.get("towns", {}).keys()[0]
	Game.location = tid
	Game.goto("town")
	await tree.process_frame
	if main.current == null or main.current is Label:
		print("flow: town failed"); fails += 1
	Game.location = ""
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	Game.start_battle({"enemy": Factory.make_warband(rng, "goblin_warren", 8), "allies": [], "contract": {}, "map": "small", "terrain": "plains"})
	await tree.process_frame
	var b: Node = main.current
	if b == null or not b.has_method("_process"):
		print("flow: battle failed"); fails += 1
		return fails
	b.skip_to_end()
	print("flow: battle ended after %d ticks, winner %d" % [b.sim.tick, b.sim.winner])
	b.finish()
	await tree.process_frame
	var on: String = main.current.scene_file_path if main.current else ""
	print("flow: after battle on ", on)
	if not on.ends_with("aftermath.tscn") and not on.ends_with("world_map.tscn"):
		fails += 1
	Game.goto("map")
	await tree.process_frame
	main.queue_free()
	return fails
