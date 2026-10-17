extends RefCounted
## Bounded exact-read/procurement tests; no generated history or rendered FPS claim.
func run(tree: SceneTree) -> int:
	var fails := 0
	for path in ["test_dynasty_read_performance.gd", "test_forge_procurement_v011.gd",
		"test_arms_performance.gd", "test_dynasty_card_performance.gd",
		"test_dragon_care.gd", "test_dragon_growth.gd", "test_militia_tick_v011.gd"]:
		var module = load("res://tests/" + path)
		if module == null or not module.can_instantiate():
			printerr("FAIL focus: cannot instantiate ", path)
			fails += 1
			continue
		fails += await module.new().run(tree)
		await tree.process_frame
	return fails
