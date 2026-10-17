extends RefCounted
## Real section actions, head access and research bars without native mouse or keyboard input.
var fails := 0

func check(ok: bool, why: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(39039)
	var report := Academy.report(Game.world, "middle_kingdom")
	check(bool(report.get("has", false)), "real realm has its capital house")
	if not bool(report.get("has", false)):
		return fails
	Game.location = String(report["tid"])
	Game.screen_params = {}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var scene: Control = load("res://ui/town.tscn").instantiate()
	viewport.add_child(scene)
	scene.set_meta("town_econ_section", "Work")
	scene.show_tab("Town")
	await tree.process_frame
	var research := scene.find_child("AcademyResearch", true, false) as Button
	check(research != null, "local state house has its direct Research action")
	var before := Game.world.duplicate(true)
	if research != null:
		research.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	check(String(scene.get_meta("town_econ_section", "")) == "Research", "Academy action selects real Research section")
	var dashboard := scene.find_child("TownDashboard", true, false)
	var scroll := dashboard.find_child("TownSectionScroll", true, false) as ScrollContainer
	for line: Dictionary in report["lines"]:
		var bar := dashboard.find_child("KnowHow_" + String(line["key"]), true, false) as ProgressBar
		if bool(line["open"]):
			check(bar != null and is_equal_approx(bar.value, float(line["kh"])), "native bar shows actual achieved know-how: " + String(line["key"]))
			if bar != null and scroll != null:
				check(bar.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1.0, "research progress is visible before scrolling at 1280x720: " + String(line["key"]))
		else:
			check(bar == null, "unavailable research has no learning bar")
	var history := _button(dashboard, "Details")
	check(history != null, "recorded research history is accessible")
	if history != null:
		history.pressed.emit()
		check(_text(scene).contains("Research details, history & log"), "history action opens its real dialog")
	check(Game.world == before, "view and details leave the live economy unchanged")
	if String(report["lead"]) != "":
		var household := _button(scene, String(report["lead"]) + "'s household")
		check(household != null, "designated head has household access")
		if household != null:
			var capital: Dictionary = Game.world["towns"][report["tid"]]
			var head: Array = Academy.biz_of(capital["econ"])["lead"]
			var family_name := String(capital["econ"]["fams"][int(head[0])]["name"])
			household.pressed.emit()
			var family := _last_modal(scene)
			check(family != null and _text(family).contains("The %s family" % family_name) and _text(family).contains(String(report["lead"])), "head action opens the exact designated person's family record")
			if family != null and _button(family, "OK") != null:
				_button(family, "OK").pressed.emit()
	await tree.process_frame
	var details := _last_modal(scene)
	if details != null and _button(details, "OK") != null:
		_button(details, "OK").pressed.emit()
	await tree.process_frame
	scene.refresh()
	check(String(scene.get_meta("town_econ_section", "")) == "Research", "refresh retains research section")
	# A non-capital settlement shows its realm's real capital research.
	for town: Dictionary in Game.world["towns"].values():
		if String(town.get("faction", "")) == "middle_kingdom" and String(town["id"]) != Game.location and TownEcon.has_econ(town):
			Game.location = String(town["id"])
			scene.refresh()
			check(_text(scene).contains(String(report["town"])), "ordinary town shows the actual realm capital location")
			break
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	return fails

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
	var out: String = (node as Label).text + "\n" if node is Label else ""
	for child in node.get_children():
		out += _text(child)
	return out
