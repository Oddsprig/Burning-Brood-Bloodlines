extends RefCounted
## Diagnostic only: strict fixture misses return zero; inspect every receipt.
const PROBE: GDScript = preload("res://tests/turn_fixture_probe_common.gd")

func run(tree: SceneTree) -> int:
	var fixture: Variant = PROBE.new()
	return await fixture.probe_fixture(tree, "realm")
