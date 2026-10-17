extends RefCounted
## Existing native fit checker on short and long history choices; no input injection.
func run(tree: SceneTree) -> int:
	await tree.process_frame
	var fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	var states := []
	for days in [1, 7, 30, 120, 12000]:
		states.append(["history %d days" % days, func(screen): screen._set_days(days)])
	for size in [Vector2(960, 640), Vector2(1280, 720), Vector2(1920, 1080)]:
		await fit._screen(size, "res://ui/newgame.tscn", states)
	return fit.fails
