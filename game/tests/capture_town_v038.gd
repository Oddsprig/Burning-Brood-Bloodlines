extends RefCounted
## Only run by the private-desktop capture helper. Never sends native input.
func run(tree: SceneTree) -> int:
	await tree.process_frame
	if OS.get_environment("COPPER_PRIVATE_DESKTOP") != "1" or DisplayServer.get_name() == "headless":
		printerr("Private rendering desktop required")
		return 2
	Game.new_game(38038)
	var town: Dictionary = {}
	for candidate in Game.world["towns"].values():
		if candidate.get("faction") == "middle_kingdom" and TownEcon.has_econ(candidate):
			town = candidate
			break
	if town.is_empty():
		return 3
	Game.location = town["id"]
	Game.screen_params = {}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var scene: Control = load("res://ui/town.tscn").instantiate()
	viewport.add_child(scene)
	for sample in [["Market", "", "market"], ["Provisions", "", "provisions"], ["Recruits", "", "recruits"],
		["Town", "Overview", "town-overview"], ["Town", "Work", "town-work"], ["Town", "Stores", "town-stores"], ["Town", "Prices", "town-prices"]]:
		if sample[1] != "":
			scene.set_meta("town_econ_section", sample[1])
		scene.show_tab(sample[0])
		for i in 10:
			await tree.process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			return 4
		var path := OS.get_environment("TOWN_UI_CAPTURE").path_join(sample[2] + ".png")
		if image.save_png(path) != OK:
			return 5
		print("Captured ", sample[2])
	viewport.queue_free()
	await tree.process_frame
	return 0
