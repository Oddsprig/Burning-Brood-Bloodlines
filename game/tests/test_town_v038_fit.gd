extends RefCounted
## Use the existing visibility/scroll-aware fit checker for every redesigned section.
func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(83)
	Game.screen_params = {}
	for town in Game.world["towns"].values():
		if town.get("faction") == "middle_kingdom":
			Game.location = town["id"]
			break
	var fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	var states := []
	for tab in ["Market", "Provisions", "Recruits", "Town"]:
		states.append(["town " + tab, func(scene): scene.show_tab(tab)])
	for section in TownEconTab.SECTIONS:
		states.append(["town data " + section, func(scene):
			scene.set_meta("town_econ_section", section)
			scene.show_tab("Town")])
	for section in ["Food & drink", "Arrows", "Care & tavern"]:
		states.append(["provisions " + section, func(scene):
			scene.set_meta("provisions_section", section)
			scene.show_tab("Provisions")])
	for size in [Vector2(960, 640), Vector2(1280, 720), Vector2(1920, 1080)]:
		await fit._screen(size, "res://ui/town.tscn", states)
	Game.location = ""
	return fit.fails
