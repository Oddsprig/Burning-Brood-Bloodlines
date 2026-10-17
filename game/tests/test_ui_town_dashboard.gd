extends RefCounted
## Real Town scene: section callbacks, native minimum sizes, price filtering/details,
## family modal and land callback compatibility. No simulation values are changed.
var fails := 0

func check(condition: bool, what: String) -> void:
	if condition:
		print("ok: ", what)
	else:
		fails += 1
		printerr("FAIL: ", what)

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _text(node: Node) -> String:
	var out: String = (node as Label).text + "\n" if node is Label else ""
	for child in node.get_children():
		out += _text(child)
	return out

func _named(node: Node, name: String) -> Node:
	if node.name == name: return node
	for child in node.get_children():
		var found := _named(child, name)
		if found != null: return found
	return null

func _select(scene: Control, name: String) -> void:
	var button := _button(scene, name)
	check(button != null, "section button: " + name)
	if button != null: button.pressed.emit()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(38038)
	var town: Dictionary = {}
	for candidate in Game.world["towns"].values():
		if TownEcon.has_econ(candidate):
			town = candidate
			break
	check(not town.is_empty(), "generated accounting town exists")
	if town.is_empty(): return fails
	var e: Dictionary = town["econ"]
	Game.location = String(town["id"])
	Game.screen_params = {}
	var scene: Control = load("res://ui/town.tscn").instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	scene.call("show_tab", "Town")
	scene.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var dashboard := _named(scene, "TownDashboard") as Control
	check(dashboard != null, "dashboard is built in the real Town scene")
	if dashboard == null:
		scene.queue_free()
		return fails
	for viewport in [Vector2(960, 640), Vector2(1280, 720), Vector2(1920, 1080)]:
		scene.size = viewport
		for section in TownEconTab.SECTIONS:
			_select(scene, section)
			await tree.process_frame
			await tree.process_frame
			check(dashboard.get_combined_minimum_size().x <= dashboard.size.x + 1.0, "%s fits its page at %dx%d" % [section, int(viewport.x), int(viewport.y)])
			var scroll := _named(dashboard, "TownSectionScroll") as ScrollContainer
			check(scroll != null and scroll.size.y > 20, "section has usable scroll area at %dx%d" % [int(viewport.x), int(viewport.y)])
	_select(scene, "People")
	var census := People.census(e)
	check(_text(dashboard).contains("%d people in %d households" % [int(census["population"]), int(census["households"])]), "People displays the actual census")
	var families := _button(dashboard, "Open family register (%d families)" % TownEconTab._live(e))
	check(families != null, "family picker remains accessible")
	if families != null:
		families.pressed.emit()
		check(_button(scene, "Cancel") != null, "family register callback opens a picker")
		_button(scene, "Cancel").pressed.emit()
		await tree.process_frame
	TownEconTab.family_modal(scene, town, int(e["head"]["fam"]))
	check(_button(scene, "OK") != null, "existing family record opens")
	if _button(scene, "OK") != null: _button(scene, "OK").pressed.emit()
	await tree.process_frame
	_select(scene, "Accounts")
	check(_text(dashboard).contains("%d coins" % int(e["treasury"])), "Accounts preserves actual treasury amount")
	_select(scene, "Stores")
	for good in Goods.ids():
		check(_text(dashboard).contains(TownEcon.label(e, good).capitalize()), "stock holder columns retain good: " + good)
	_select(scene, "Prices")
	var search := _named(dashboard, "PriceSearch") as LineEdit
	var rows := _named(dashboard, "PriceRows")
	check(search != null and rows != null, "Prices has functional search")
	if search != null and rows != null:
		var good := String(Goods.ids()[0])
		var label := TownEcon.label(e, good).capitalize()
		search.text = label
		search.text_changed.emit(search.text)
		check(_text(rows).contains(label), "search keeps matching actual price rows")
		search.text = "__no_such_good__"
		search.text_changed.emit(search.text)
		check(_text(rows).contains("No goods match"), "search excludes unmatched goods")
		search.text = ""
		search.text_changed.emit("")
		var detail := _button(rows, "Details")
		check(detail != null, "price reasons have a detail action")
		if detail != null:
			detail.pressed.emit()
			check(_text(scene).contains("Current price:") and _button(scene, "OK") != null, "price details open current/previous price and reason")
			if _button(scene, "OK") != null: _button(scene, "OK").pressed.emit()
			await tree.process_frame
		var category := _named(dashboard, "PriceCategory") as OptionButton
		if category != null and category.item_count > 1:
			category.select(1)
			category.item_selected.emit(1)
			var chosen := String(category.get_item_metadata(1))
			for id in Goods.ids():
				if String(Goods.table()[id].get("cat", "other")) == chosen:
					check(_text(rows).contains(TownEcon.label(e, id).capitalize()), "category retains member: " + String(id))
	_select(scene, "Land")
	check(_button(dashboard, "Open land map") != null, "Land section retains its map action")
	_select(scene, "Overview")
	check(_button(dashboard, "Land map") != null, "Overview retains the original Land map callback target")
	check(_text(dashboard).contains(String(e["head"]["name"])), "Overview preserves actual ruler")
	_select(scene, "Work")
	scene.call("refresh")
	check(String(scene.get_meta("town_econ_section", "")) == "Work" and _text(_named(scene, "TownDashboard")).contains("Paid places exclude keepers"), "refresh retains the selected data section")
	scene.queue_free()
	await tree.process_frame
	Game.location = ""
	return fails
