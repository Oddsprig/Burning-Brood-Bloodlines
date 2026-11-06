extends RefCounted
## Retained runner entry point. v0.086 replaces dog removal with owned guard dogs.
func run(tree: SceneTree) -> int:
	var regression = load("res://tests/test_domestic_animals_v086.gd").new()
	return await regression.run(tree)
