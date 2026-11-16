extends "res://tests/frame_world_split_equiv_common.gd"
## Day 11: all naturally scheduled sickness parts and the world header.
func run(tree: SceneTree) -> int:
	return await run_group(tree, "sickness")
