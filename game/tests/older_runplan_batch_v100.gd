extends RefCounted
## One complete existing selected part per fresh process, including native handoffs.
## A successful subset is PARTIAL parent evidence until the complete run-plan union passes.
const Args = preload("res://tests/fixtures/older_runplan_args_v100.gd")
const SUPPORTED: Array = ["test_startup_slices","test_weekly_hiring","test_ui_load_times","test_econ_army","test_child_cleanup","test_campaign_contracts","test_ui_records_v040","test_town_services_v042","test_dragon_growth_v052","test_art_menus","test_builder_payments","test_sickness","test_campaign_diplomacy","test_food_battle","test_metal_tech","test_ui_records_v041","test_barge","test_campaign_world","test_dragon_colours_v064","test_backstory_story","test_casual_occupancy_save"]
const ENV_ONLY: Array = ["test_econ_sanity", "test_supply_lookups"]
const ENV_KEYS: Array = ["STARTUP_MODE", "STARTUP_FIXED_RAIDS", "STARTUP_COMPARE_DIR", "AUDIT_INPUT", "SUPPLY_CASE", "SUPPLY_SAVE"]
const MAX_PARTS: int = 1
const BODY_LIMIT_USEC: int = 45000000

func run(tree: SceneTree) -> int:
	var started: int = Time.get_ticks_usec()
	var target: String = ""
	var parts_text: String = ""
	var seen: Dictionary = {}
	var common: PackedStringArray = PackedStringArray()
	var environment: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--runplan-env="):
			var pair: PackedStringArray = argument.trim_prefix("--runplan-env=").split("=", true, 1)
			if pair.size() != 2 or not pair[0] in ENV_KEYS or environment.has(pair[0]) or pair[1].is_empty():
				printerr("RUNPLAN invalid process-local environment option: ", argument)
				return 1
			environment[pair[0]] = pair[1]
		elif argument.begins_with("--runplan-"):
			var option: PackedStringArray = argument.split("=", true, 1)
			if option.size() != 2 or seen.has(option[0]) or option[1].is_empty():
				printerr("RUNPLAN invalid or duplicate driver option: ", argument)
				return 1
			seen[option[0]] = true
			match option[0]:
				"--runplan-test": target = option[1]
				"--runplan-parts": parts_text = option[1]
				_:
					printerr("RUNPLAN unknown driver option: ", argument)
					return 1
		elif argument.begins_with("--speed-part"):
			printerr("RUNPLAN use only --runplan-parts; conflicting selector refused")
			return 1
		elif not argument.begins_with("--test="):
			common.append(argument)
	if not (target in SUPPORTED or target in ENV_ONLY) or parts_text.is_empty() or Args.active:
		printerr("RUNPLAN needs a supported original test and explicit part list")
		return 1
	var parts: PackedStringArray = parts_text.split(",", true)
	if parts.size() < 1 or parts.size() > MAX_PARTS:
		printerr("RUNPLAN requires one complete existing part per process; shared-state equivalence is unproved")
		return 1
	var unique: Dictionary = {}
	for part: String in parts:
		if part.is_empty() or part == "all" or unique.has(part):
			printerr("RUNPLAN empty, duplicate or all selector refused")
			return 1
		if (part == "default") != (target in ENV_ONLY):
			printerr("RUNPLAN default is reserved for the two environment-only tests")
			return 1
		unique[part] = true
	var runner: Node = tree.current_scene
	if runner == null or not runner.has_method("_run_one") or not runner.has_method("reset_between"):
		printerr("RUNPLAN requires the unchanged test runner scene")
		return 1
	var counter: Object = runner.get("script_errors")
	if counter == null or not counter.has_method("total"):
		printerr("RUNPLAN requires the runner's actual script-error counter")
		return 1
	var keep: Array = tree.root.get_children()
	var path: String = "res://tests/" + target + ".gd"
	var completed: int = 0
	var previous_environment: Dictionary = {}
	for name: String in environment:
		previous_environment[name] = OS.get_environment(name) if OS.has_environment(name) else null
		OS.set_environment(name, str(environment[name]))
	for part: String in parts:
		if Time.get_ticks_usec() - started >= BODY_LIMIT_USEC:
			printerr("RUNPLAN body deadline; incomplete selected batch FAILS")
			_restore_environment(previous_environment)
			return 1
		var errors_before: int = int(counter.call("total"))
		var part_started: int = Time.get_ticks_usec()
		var selected: PackedStringArray = common.duplicate()
		if part != "default": selected.append("--speed-part=" + part)
		Args.selected = selected
		Args.active = true
		print("RUNPLAN_BEGIN test=", target, " part=", part)
		var result: Variant = await runner.call("_run_one", path)
		Args.active = false
		Args.selected = PackedStringArray()
		# Exactly the existing runner's scene teardown, save wait and shared-state reset.
		Game.wait_save()
		await runner.call("reset_between", keep)
		var errors: int = int(counter.call("total")) - errors_before
		if typeof(result) != TYPE_INT:
			printerr("RUNPLAN missing integer result: ", target, "/", part)
			_restore_environment(previous_environment)
			return 1
		if int(result) != 0 or errors != 0:
			printerr("RUNPLAN stop at first failed part: ", target, "/", part, " result=", result, " script_errors=", errors)
			_restore_environment(previous_environment)
			return maxi(1, maxi(int(result), errors))
		if Time.get_ticks_usec() - started >= BODY_LIMIT_USEC:
			printerr("RUNPLAN body deadline; overdue selected batch FAILS")
			_restore_environment(previous_environment)
			return 1
		completed += 1
		print("RUNPLAN_PART test=", target, " part=", part, " result=0 script_errors=0 part_wall_usec=", Time.get_ticks_usec() - part_started, " parent=PARTIAL")
	print("RUNPLAN_BATCH test=", target, " complete_parts=", completed, " body_wall_usec=", Time.get_ticks_usec() - started, " parent=requires_complete_selector_union")
	_restore_environment(previous_environment)
	return 0

func _restore_environment(previous: Dictionary) -> void:
	for name: String in previous:
		if previous[name] == null: OS.unset_environment(name)
		else: OS.set_environment(name, str(previous[name]))
