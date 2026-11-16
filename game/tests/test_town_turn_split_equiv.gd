extends RefCounted
const CHECK: GDScript = preload("res://tests/turn_split_equiv_common.gd")

func run(tree: SceneTree) -> int:
	var check: Variant = CHECK.new()
	return await check.run_part(tree, "town")
