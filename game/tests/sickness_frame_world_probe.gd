extends "res://tests/frame_world_split_probe_common.gd"
## One native warmup and the full real sickness day; inspect strict_result.
func run(tree: SceneTree) -> int:
	return await probe_group(tree, "sickness")
