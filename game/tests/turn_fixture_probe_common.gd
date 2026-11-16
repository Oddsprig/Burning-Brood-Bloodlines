extends "res://tests/frame_world_split_probe_common.gd"
## Compatibility entries; output names the complete group actually compared.
func probe_fixture(tree: SceneTree, part: String) -> int:
	if part in ["town", "family"]:
		return await probe_group(tree, "family_town")
	if part == "realm":
		return await probe_group(tree, "econ_bday_realm")
	printerr("FRAME WORLD PROBE HARNESS ERROR: unknown turn group " + part)
	return 1
