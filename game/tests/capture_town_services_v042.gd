extends RefCounted
## Real seeded town services rendered only on the explicitly isolated private desktop.
## Native Control signals and scrolling; no input injection or personal-save access.
const Services = preload("res://tests/test_town_services_v042.gd")
const SCREENSHOTS := [
	"town-v042-healer-wounded.png", "town-v042-healer-wound-details.png",
	"town-v042-healer-low-funds.png", "town-v042-contracts-offers.png",
	"town-v042-contracts-offer-details.png", "town-v042-contracts-active.png"
]

func run(tree: SceneTree) -> int:
	await tree.process_frame
	if OS.get_environment("COPPER_PRIVATE_DESKTOP") != "1" or DisplayServer.get_name() == "headless":
		printerr("Private rendering desktop required")
		return 2
	var output := OS.get_environment("TOWN_SERVICES_UI_CAPTURE")
	if output == "" or not DirAccess.dir_exists_absolute(output):
		printerr("Existing services capture directory required")
		return 3
	var town: Dictionary = Services.fixture(40042, true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child.call_deferred(viewport)
	await tree.process_frame
	var scene: PackedScene = load("res://ui/town.tscn")
	if scene == null:
		viewport.queue_free()
		return 15
	var screen: Control = scene.instantiate()
	if not screen.has_method("show_tab") or not screen.has_method("_treat_queue"):
		printerr("Town service dependencies failed to compile")
		screen.free()
		viewport.queue_free()
		return 16
	viewport.add_child(screen)
	await _settle(tree)
	if not screen.is_node_ready() or screen.find_child("HealerView", true, false) == null or Game.company.size() != 3:
		printerr("Town service capture fixture failed to build")
		viewport.queue_free()
		return 17
	if not await _capture(tree, viewport, output, "town-v042-healer-wounded.png"):
		viewport.queue_free()
		return 4
	# Open the severe patient's actual report and scroll it into the visible canvas.
	var patient: Unit = Game.company[2]
	var disclosure := screen.find_child("WoundDetails_%d" % patient.uid, true, false)
	if disclosure == null:
		viewport.queue_free()
		return 5
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	(disclosure.get_child(0) as Button).pressed.emit()
	await _settle(tree)
	var scroll := screen.find_child("HealerView", true, false) as ScrollContainer
	_scroll_to(scroll, screen.find_child("Patient_%d" % patient.uid, true, false) as Control)
	if not await _capture(tree, viewport, output, "town-v042-healer-wound-details.png", before, random_state):
		viewport.queue_free()
		return 6
	Game.gold = 0
	screen.refresh()
	if not await _capture(tree, viewport, output, "town-v042-healer-low-funds.png"):
		viewport.queue_free()
		return 7
	Game.gold = 100000
	screen.show_tab("Contracts")
	if not await _capture(tree, viewport, output, "town-v042-contracts-offers.png"):
		viewport.queue_free()
		return 8
	# Show a real offer description without changing contract state.
	var offer: Node = null
	for node in _nodes(screen):
		if node.has_meta("contract_offer"):
			offer = node
			break
	if offer == null:
		viewport.queue_free()
		return 9
	before = Game._save_tree()
	random_state = Game.rng.state
	(offer.find_child("ContractDetails", true, false) as Button).pressed.emit()
	await _settle(tree)
	_scroll_to(screen.find_child("ContractsScroll", true, false) as ScrollContainer, offer as Control)
	if not await _capture(tree, viewport, output, "town-v042-contracts-offer-details.png", before, random_state):
		viewport.queue_free()
		return 10
	# Actual acceptance is an intentional fixture transition; capture itself must stay pure.
	var selected: Dictionary = {}
	for contract: Dictionary in Contracts.offers_for(Game, town):
		if contract["kind"] == "battle" and Contracts.refusal(Game, contract) == "":
			selected = contract
			break
	if selected.is_empty():
		viewport.queue_free()
		return 11
	var accept: Button = null
	for node in _nodes(screen):
		if node is Button and node.has_meta("contract_id") and node.get_meta("contract_id") == selected["id"]:
			accept = node
	if accept == null:
		viewport.queue_free()
		return 12
	accept.pressed.emit()
	await _settle(tree)
	if Game.contract.get("state", "") != "active" or Game.contract.get("id", "") != selected["id"]:
		viewport.queue_free()
		return 13
	before = Game._save_tree()
	random_state = Game.rng.state
	for node in _nodes(screen):
		if node.has_meta("rec_disclosure") and node.get_meta("rec_disclosure") == "Contract details":
			(node.get_child(0) as Button).pressed.emit()
	if not await _capture(tree, viewport, output, "town-v042-contracts-active.png", before, random_state):
		viewport.queue_free()
		return 14
	print("Captured actual town services seed=40042 town=", town["name"], " day=", Game.day,
		" patients=", Game.company.size(), " active=", Game.contract.get("id", ""))
	viewport.queue_free()
	await tree.process_frame
	return 0

func _settle(tree: SceneTree) -> void:
	for i in 4: await tree.process_frame

func _capture(tree: SceneTree, viewport: SubViewport, output: String, filename: String,
		before: Dictionary = {}, random_state: int = -1) -> bool:
	if before.is_empty():
		before = Game._save_tree()
		random_state = Game.rng.state
	for i in 10: await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty(): return false
	if image.save_png(output.path_join(filename)) != OK: return false
	if Game._save_tree() != before or Game.rng.state != random_state:
		printerr("Services capture changed saved campaign state: ", filename)
		return false
	print("Captured ", filename)
	return true

func _scroll_to(scroll: ScrollContainer, control: Control) -> void:
	if scroll == null or control == null: return
	var offset := control.get_global_rect().position.y - scroll.get_global_rect().position.y - 24.0
	scroll.scroll_vertical = maxi(0, scroll.scroll_vertical + int(round(offset)))

func _nodes(node: Node) -> Array:
	var out := []
	if node == null or node.is_queued_for_deletion(): return out
	out.append(node)
	for child in node.get_children(): out.append_array(_nodes(child))
	return out
