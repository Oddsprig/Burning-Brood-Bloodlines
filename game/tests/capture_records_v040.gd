extends RefCounted
## Real one-day records, rendered on the helper's never-activated private desktop.
## No native mouse/keyboard input; section changes use the screen's own methods.

func run(tree: SceneTree) -> int:
	await tree.process_frame
	if OS.get_environment("COPPER_PRIVATE_DESKTOP") != "1" or DisplayServer.get_name() == "headless":
		printerr("Private rendering desktop required")
		return 2
	var output := OS.get_environment("RECORDS_UI_CAPTURE")
	if output == "":
		output = OS.get_environment("TOWN_UI_CAPTURE")
	if output == "" or not DirAccess.dir_exists_absolute(output):
		printerr("Existing Records capture directory required")
		return 3
	Game.new_game(40040)
	CampaignWorld.presim_step(Game, 1)
	var tid := String(Game.world["factions"]["middle_kingdom"]["capital"])
	var town: Dictionary = Game.world["towns"].get(tid, {})
	if not TownEcon.has_econ(town):
		return 4
	Game.location = tid
	Game.screen_params = {"view": "town", "id": tid, "tab": "Overview", "back": "town"}
	var before := Game._save_tree()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var screen: Control = load("res://ui/records.tscn").instantiate()
	viewport.add_child(screen)
	for section in ["Overview", "Market", "Garrison", "Register", "Treasury"]:
		screen.show_tab(section)
		if await _save(tree, viewport, output.path_join("records-" + section.to_lower() + ".png")) != OK:
			return 5
		if Game._save_tree() != before:
			printerr("Records capture changed saved campaign state: ", section)
			return 6
	for target in [["Overview", "Condition", "records-overview-household-condition.png"],
			["Market", "Material", "records-market-material-quality.png"]]:
		screen.show_tab(String(target[0]))
		for i in 4:
			await tree.process_frame
		var header := _grid_header(screen.list_box, String(target[1]))
		if header == null:
			printerr("Actual Records table not found for capture: ", target[1])
			return 7
		# Scroll the existing body to its real aligned table; never inject input or
		# change the world's data to produce a screenshot.
		var scroll: ScrollContainer = screen.list_sc
		var offset: float = header.get_global_rect().position.y - scroll.get_global_rect().position.y - 100.0
		scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + int(round(offset)))
		if await _save(tree, viewport, output.path_join(String(target[2]))) != OK:
			return 8
		if Game._save_tree() != before:
			printerr("Records table capture changed saved campaign state: ", target[1])
			return 9
	print("Captured actual Records town=", town["name"], " day=", Game.day, " people=", Census.people(town["econ"]), " shop=", town.get("shop", []).size(), " defenders=", TownDefence.garrison(Game, tid).size())
	viewport.queue_free()
	await tree.process_frame
	return 0

func _save(tree: SceneTree, viewport: SubViewport, path: String) -> int:
	for i in 10:
		await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return ERR_CANT_CREATE
	var result := image.save_png(path)
	print("Captured ", path.get_file())
	return result

func _grid_header(node: Node, heading: String) -> Control:
	if node is RecCells and node.header:
		var values: Array = node.get_meta("rec_values", [])
		if not values.is_empty() and String(values[0]) == heading:
			return node
	for child in node.get_children():
		var found := _grid_header(child, heading)
		if found != null:
			return found
	return null
