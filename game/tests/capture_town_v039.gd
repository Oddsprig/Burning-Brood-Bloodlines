extends RefCounted
## Native render on the helper's never-activated private desktop; no input injection.
func run(tree: SceneTree) -> int:
	await tree.process_frame
	if OS.get_environment("COPPER_PRIVATE_DESKTOP") != "1" or DisplayServer.get_name() == "headless":
		printerr("Private rendering desktop required")
		return 2
	Game.new_game(39039)
	# Advance the real simulation so the view contains recorded study, not invented bars.
	CampaignWorld.presim_step(Game, 7)
	var report := Academy.report(Game.world, "middle_kingdom")
	var town: Dictionary = Game.world["towns"].get(String(report.get("tid", "")), {})
	if town.is_empty() or not bool(report.get("has", false)):
		return 3
	Game.location = town["id"]
	Game.screen_params = {}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var scene: Control = load("res://ui/town.tscn").instantiate()
	viewport.add_child(scene)
	for section in ["Work", "Research"]:
		scene.set_meta("town_econ_section", section)
		scene.show_tab("Town")
		if await _save(tree, viewport, "town-" + section.to_lower()) != OK:
			return 4
	TownResearchTab._history(scene, town, report)
	if await _save(tree, viewport, "research-history") != OK:
		return 5
	print("Captured real research: ", report)
	scene.queue_free()
	await tree.process_frame
	var options: Control = load("res://ui/newgame.tscn").instantiate()
	viewport.add_child(options)
	options._set_days(1)
	if await _save(tree, viewport, "new-campaign-one-day") != OK:
		return 6
	viewport.queue_free()
	await tree.process_frame
	return 0

func _save(tree: SceneTree, viewport: SubViewport, name: String) -> int:
	for i in 10:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return ERR_CANT_CREATE
	var result := image.save_png(OS.get_environment("TOWN_UI_CAPTURE").path_join(name + ".png"))
	print("Captured ", name)
	return result
