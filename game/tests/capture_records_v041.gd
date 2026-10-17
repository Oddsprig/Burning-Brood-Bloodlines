extends RefCounted
## Ten real seeded Records views on a never-activated private rendering desktop.
## Uses native Control methods/signals only; never reads a personal save or injects input.
const CAPTURES := [
	["town", "Land & Homes", "records-v041-town-land-homes.png"],
	["town", "Census", "records-v041-town-census.png"],
	["town", "Hardship", "records-v041-town-hardship.png"],
	["town", "Roads", "records-v041-town-roads.png"],
	["town", "Sickness", "records-v041-town-sickness.png"],
	["world", "Towns", "records-v041-world-towns.png"],
	["world", "Goods", "records-v041-world-goods.png"],
	["world", "On the move", "records-v041-world-on-the-move.png"],
	["faction", "Towns", "records-v041-faction-towns.png"],
	["faction", "Army", "records-v041-faction-army.png"]
]

func run(tree: SceneTree) -> int:
	await tree.process_frame
	if OS.get_environment("COPPER_PRIVATE_DESKTOP") != "1" or DisplayServer.get_name() == "headless":
		printerr("Private rendering desktop required")
		return 2
	var output := OS.get_environment("RECORDS_UI_CAPTURE")
	if output == "": output = OS.get_environment("TOWN_UI_CAPTURE")
	if output == "" or not DirAccess.dir_exists_absolute(output):
		printerr("Existing Records capture directory required")
		return 3
	Game.new_game(40041)
	CampaignWorld.presim_step(Game, 1)
	var fid := "middle_kingdom"
	var tid := String(Game.world["factions"][fid]["capital"])
	var town := RecData.town(tid)
	if not TownEcon.has_econ(town): return 4
	Game.location = tid
	Game.screen_params = {"view": "town", "id": tid, "tab": "Land & Homes", "back": "town"}
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	var screen: Control = load("res://ui/records.tscn").instantiate()
	viewport.add_child(screen)
	for target in CAPTURES:
		var view := String(target[0])
		screen.set_view(view, tid if view == "town" else (fid if view == "faction" else ""), String(target[1]))
		for i in 4: await tree.process_frame
		# Keep the default dashboard state in every capture. Programmatic scrolling
		# simply exposes its first real native aligned table after the summary.
		var table := _first_primary_table(screen.list_box)
		if table != null and table.get_global_rect().position.y > screen.list_sc.get_global_rect().end.y - 96.0:
			var scroll: ScrollContainer = screen.list_sc
			var offset: float = table.get_global_rect().position.y - scroll.get_global_rect().position.y - 180.0
			scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + int(round(offset)))
		if await _save(tree, viewport, output.path_join(String(target[2]))) != OK:
			viewport.queue_free()
			return 5
		if Game._save_tree() != before or Game.rng.state != random_state:
			printerr("Records capture changed saved campaign state: ", view, "/", target[1])
			viewport.queue_free()
			return 6
	print("Captured actual Records v041 seed=40041 town=", town["name"], " day=", Game.day, " towns=", Game.world["towns"].size(), " forces=", Game.world["warbands"].size())
	viewport.queue_free()
	await tree.process_frame
	return 0

func _save(tree: SceneTree, viewport: SubViewport, path: String) -> int:
	for i in 10: await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty(): return ERR_CANT_CREATE
	var result := image.save_png(path)
	print("Captured ", path.get_file())
	return result

func _first_primary_table(node: Node) -> Control:
	if node is CanvasItem and not node.visible: return null
	if node is RecTable and not node.display_columns.is_empty(): return node
	if node is RecCells and node.header: return node
	for child in node.get_children():
		var found := _first_primary_table(child)
		if found != null: return found
	return null

