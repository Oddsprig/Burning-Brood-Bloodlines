extends "res://tests/test_campaign_monsters.gd"
## Standalone diagnostic only; never a perf acceptance test or a block member.
## Reuses the exact seed-777 setup, native map entry and 600-frame sampler.
## mean_ms/worst_ms are whole-frame observations; monster_mean_ms/monster_worst_ms cover the v0.100 gate.
## All timing fields are -1 when no frame was measured.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.

func run(tree: SceneTree) -> int:
	_part = "perf"
	_deadline_msec = Time.get_ticks_msec() + 55000
	var previous_next_world: bool = Monsters.new_world_creatures
	var had_setting: bool = Game.settings.has("creatures_enabled")
	var previous_setting: Variant = Game.settings.get("creatures_enabled", null)
	Monsters.new_world_creatures = true
	Game.settings["creatures_enabled"] = true
	await _run_enabled()
	Monsters.new_world_creatures = previous_next_world
	if had_setting: Game.settings["creatures_enabled"] = previous_setting
	else: Game.settings.erase("creatures_enabled")
	print("reached_native_map: ", "true" if bool(_perf_observation.get("reached_native_map", false)) else "false")
	print("frames_measured: ", int(_perf_observation.get("frames_measured", 0)))
	print("midnight_seen: ", "true" if bool(_perf_observation.get("midnight_seen", false)) else "false")
	print("live_native_bands: ", int(_perf_observation.get("live_native_bands", 0)))
	print("mean_ms: %.6f" % float(_perf_observation.get("mean_ms", -1.0)))
	print("worst_ms: %.6f" % float(_perf_observation.get("worst_ms", -1.0)))
	print("monster_mean_ms: %.6f" % float(_perf_observation.get("monster_mean_ms", -1.0)))
	print("monster_worst_ms: %.6f" % float(_perf_observation.get("monster_worst_ms", -1.0)))
	print("day_work_mean_ms: %.6f" % float(_perf_observation.get("day_work_mean_ms", -1.0)))
	print("day_work_worst_ms: %.6f" % float(_perf_observation.get("day_work_worst_ms", -1.0)))
	print("autosave_mean_ms: %.6f" % float(_perf_observation.get("autosave_mean_ms", -1.0)))
	print("autosave_worst_ms: %.6f" % float(_perf_observation.get("autosave_worst_ms", -1.0)))
	# No acceptance receipt or runner PASS: end this standalone probe with zero.
	tree.quit(0)
	await tree.process_frame
	return 0

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	if not _budget_failed:
		check(false, "monster perf probe reached its 55 second budget; measurements may be incomplete")
		_budget_failed = true
	return false
