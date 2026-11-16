extends "res://tests/frame_measure_common.gd"
## Enforce the complete continuous window and whole-run coin/tturn merge gate.

func run(tree: SceneTree) -> int:
	return await measure(tree, true)
