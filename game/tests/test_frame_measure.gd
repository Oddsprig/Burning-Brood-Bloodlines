extends "res://tests/frame_measure_common.gd"
## Measure the complete continuous days 10-15 window; a valid NOT MET exits 0.

func run(tree: SceneTree) -> int:
	return await measure(tree, false)
