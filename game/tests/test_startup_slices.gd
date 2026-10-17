extends "res://tests/diag_startup_slices.gd"
## Focused scheduling gate: use separate fresh processes to avoid global UID-counter
## resets between worlds. First run STARTUP_MODE=atomic STARTUP_FIXED_RAIDS=1, then
## STARTUP_MODE=sliced STARTUP_FIXED_RAIDS=1 STARTUP_COMPARE_DIR=<atomic output>.
## STARTUP_OUTPUT chooses retained evidence; absent it, use isolated user:// storage.
## Default history is 30 normal-world days, seed777, fixed diagnostic raids enabled.
## Inherited checks cover exact day boundaries, complete snapshots, job counts, no-op
## completion, company invariants, sickness counts and dated-ownership conservation.

func _setting(name: String, fallback: String) -> String:
	return super._setting(name, "1" if name == "STARTUP_FIXED_RAIDS" else fallback)

func run(tree: SceneTree) -> int:
	if OS.get_environment("STARTUP_OUTPUT").is_empty():
		OS.set_environment("STARTUP_OUTPUT", ProjectSettings.globalize_path("user://test_startup_slices_%d" % OS.get_process_id()))
	return await super.run(tree)
