extends "res://tests/frame_world_split_equiv_common.gd"
## Day 10 groups due market/books headers with the due weekly realm turn.
func run_part(tree: SceneTree, part: String) -> int:
	if part in ["econ", "bday"]:
		return await run_group(tree, "econ_bday_realm")
	harness_error = true
	_failure = "Unknown rest group: " + part
	return 1
