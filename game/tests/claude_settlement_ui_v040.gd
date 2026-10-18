extends RefCounted
## Buildings tab: a ruled town can start a granary, and another town stays read-only.

var checks: int = 0
var fails: int = 0
var previous_save_path: String = ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL settlement_ui_v040: ", what)

func _finish() -> int:
	Game.wait_save()
	if previous_save_path != "":
		Game.SAVE_PATH = previous_save_path
	print("settlement_ui_v040: %d checks, %d failures" % [checks, fails])
	return fails

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	if not await DevTools.start_world(tree, "user://settlement-ui-v040.json"):
		check(false, "the shared test world loads")
		return _finish()
	var seat := DevTools.choose_house(Game)
	check(seat != "", "selected a player ruling house")
	if seat == "":
		return _finish()
	var towns: Dictionary = Game.world["towns"]
	var town: Dictionary = towns[seat]
	var payer: Dictionary = Feudal._payer(Game)
	check(not payer.is_empty(), "ruling house has a purse")
	if payer.is_empty():
		return _finish()
	payer["purse"] = 5000.0
	var ai_tid := ""
	for tid_key in towns.keys():
		var cand := str(tid_key)
		if cand != seat and not Settlement.is_player_town(Game, cand):
			ai_tid = cand
			break
	check(ai_tid != "", "found a town the player does not rule")
	if ai_tid == "":
		return _finish()
	Game.location = seat
	Game.screen_params = {}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var scene: Control = load("res://ui/town.tscn").instantiate()
	viewport.add_child(scene)
	await tree.process_frame
	var tab_btn := _button(scene, "Buildings")
	check(tab_btn != null, "town screen has a Buildings tab")
	if tab_btn != null:
		tab_btn.pressed.emit()
	await tree.process_frame
	check(str(scene.tab) == "Buildings", "Buildings tab opened")
	var e: Dictionary = Settlement.ensure_town(town)
	var food: Dictionary = e.get("food", {})
	var stock := int(food.get("stock", 0))
	var cap := int(food.get("capacity", 0))
	var body := _text(scene)
	check(body.contains("%d / %d" % [stock, cap]), "food store shows stock / capacity")
	var use := Settlement.daily_consumption(e)
	var days := 0 if use <= 0 else int(floor(float(stock) / float(use)))
	check(body.contains("%d days of food left" % days), "food store shows days of food left")
	for key in Settlement.KEYS:
		var k := String(key)
		var level := Settlement.building_level(town, k)
		check(scene.find_child("Building_" + k, true, false) != null, "lists " + k)
		check(body.contains("Level %d / %d" % [level, Settlement.MAX_LEVEL]), "level line for " + k)
		check(body.contains(String(Settlement.CATALOG[k]["desc"])), "effect line for " + k)
		check(scene.find_child("BuildButton_" + k, true, false) != null, "ruled town has BuildButton_" + k)
	check(body.contains("No project under way."), "no project yet")
	var preview: Dictionary = Settlement.start_preview(Game, seat, "granary")
	var cost := int(preview.get("cost", 0))
	check(bool(preview.get("ok", false)) and cost > 0, "granary preview is affordable")
	var build := scene.find_child("BuildButton_granary", true, false) as Button
	check(build != null, "BuildButton_granary is on the ruled town")
	if build != null:
		build.pressed.emit()
	await tree.process_frame
	var modal := _last_modal(scene)
	check(modal != null, "Build opens the confirm modal")
	if modal != null:
		var modal_text := _text(modal)
		check(modal_text.contains(str(cost)) and modal_text.contains(str(int(preview.get("days", 0)))), "modal shows start_preview cost and days")
		var yes := _button(modal, "Confirm")
		check(yes != null, "modal has Confirm")
		if yes != null:
			yes.pressed.emit()
	await tree.process_frame
	var projects: Array = e.get("projects", [])
	check(projects.size() == 1 and str(projects[0].get("key", "")) == "granary", "granary project started")
	var charged := 5000.0 - float(payer.get("purse", 0.0))
	var paid := float(projects[0].get("cost", -1)) if projects.size() == 1 else -1.0
	check(is_equal_approx(charged, float(cost)) and is_equal_approx(paid, float(cost)), "purse was charged the granary cost")
	check(_text(scene).contains("days left"), "project shows days left")
	food["stock"] = 0
	scene.show_tab("Buildings")
	await tree.process_frame
	var famine := scene.find_child("FamineWarning", true, false)
	check(famine != null and _text(famine).contains("Famine"), "empty food store warns Famine")
	Game.location = ai_tid
	scene.show_tab("Buildings")
	await tree.process_frame
	check(_build_buttons(scene) == 0, "another town shows no Build buttons")
	check(scene.find_child("FoodStore", true, false) != null, "other town still shows the food store")
	check(scene.find_child("Building_walls", true, false) != null, "other town still lists buildings")
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	return _finish()

func _build_buttons(node: Node) -> int:
	var n := 0
	if str(node.name).begins_with("BuildButton_"):
		n += 1
	for child in node.get_children():
		n += _build_buttons(child)
	return n

func _last_modal(host: Node) -> Node:
	var result: Node = null
	for child in host.get_children():
		if child.has_meta("ui_modal"):
			result = child
	return result

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null:
			return found
	return null

func _text(node: Node) -> String:
	var out := ""
	if node is Label:
		out = (node as Label).text + "\n"
	for child in node.get_children():
		out += _text(child)
	return out
