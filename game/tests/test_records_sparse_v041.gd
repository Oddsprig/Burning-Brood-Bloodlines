extends RefCounted
## Fast sparse-save read contract; reuses the full Records suite's real fixtures.
const RECORDS := preload("res://tests/test_ui_records_v041.gd")

func run(tree: SceneTree) -> int:
	var records = RECORDS.new()
	return await records.run_sparse(tree)
