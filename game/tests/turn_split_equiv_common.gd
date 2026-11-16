extends "res://tests/frame_world_split_equiv_common.gd"
## Existing strict entry points share one real day's native queue per invocation.
func run_part(tree: SceneTree, part: String) -> int:
	if part in ["town", "family"]:
		return await run_group(tree, "family_town")
	if part == "realm":
		return await run_group(tree, "econ_bday_realm")
	harness_error = true
	_failure = "Unknown turn group: " + part
	return 1
