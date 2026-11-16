extends RefCounted
## Diagnostic only: inherited assertions remain strict; a diagnostic exit 0 is not a test pass.
## One selected case per process, runner --watchdog=55 and external 59-second wall cap.
## Farm seeds generate worlds; gore claims runs ten synchronous battles. Required wall time is UNMEASURED.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief. A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.

class Trace:
	extends RefCounted
	var rows: Array = []
	var phases: Array = []
	var misses: int = 0
	var failures: int = 0
	var active: String = "run"
	var count_errors: Callable = Callable()
	var started: int = Time.get_ticks_msec()
	func error_total() -> int:
		return int(count_errors.call()) if count_errors.is_valid() else 0
	func observe(ok: bool, message: String) -> void:
		rows.append({"ok": ok, "message": message, "phase": active, "at_ms": Time.get_ticks_msec() - started})
		if not ok: failures += 1
	func begin(name: String) -> Dictionary:
		var token: Dictionary = {"name": name, "at": Time.get_ticks_msec(), "fails": failures, "errors": error_total(), "checks": rows.size(), "previous": active}
		active = name
		print("READINESS_PHASE_BEGIN ", JSON.stringify({"phase": name, "at_ms": Time.get_ticks_msec() - started}))
		return token
	func finish(token: Dictionary) -> void:
		var script_errors: int = error_total() - int(token["errors"])
		var row: Dictionary = {"phase": token["name"], "ms": Time.get_ticks_msec() - int(token["at"]),
			"strict_failures": failures - int(token["fails"]), "harness_errors": script_errors,
			"assertions": rows.size() - int(token["checks"]),
			"stop_reason": "harness_or_script_error" if script_errors > 0 else ("strict_failure" if failures > int(token["fails"]) else "returned")}
		phases.append(row)
		print("READINESS_PHASE ", JSON.stringify(row))
		active = str(token["previous"])
	func matching(prefix: String) -> Dictionary:
		var count: int = 0
		var passed: bool = true
		for row: Dictionary in rows:
			if str(row["message"]).begins_with(prefix):
				count += 1
				passed = passed and bool(row["ok"])
		return {"count": count, "passed": passed and count > 0}
	func guard(name: String, endpoint: String, prerequisites: Array = [], minimum: int = 1, require_pass: bool = false) -> void:
		var result: Dictionary = matching(endpoint)
		var ready: bool = int(result["count"]) >= minimum
		for prefix: String in prerequisites:
			ready = ready and bool(matching(prefix)["passed"])
		if require_pass: ready = ready and bool(result["passed"])
		if not ready: misses += 1
		print("READINESS_PATH ", JSON.stringify({"path": name, "reach": "HIT" if ready else "MISS",
			"evidence": "assertion_endpoint_and_prerequisites", "endpoint": endpoint, "observed": result["count"], "minimum": minimum, "prerequisites": prerequisites,
			"strict": ("PASS" if bool(result["passed"]) else "FAIL") if int(result["count"]) > 0 else "NOT_RUN",
			"stop_reason": "endpoint_observed" if ready else "missing_endpoint_or_unsatisfied_prerequisite"}))
	func observed_path(name: String, count: int, detail: String) -> void:
		if count <= 0: misses += 1
		print("READINESS_PATH ", JSON.stringify({"path": name, "reach": "HIT" if count > 0 else "MISS",
			"evidence": detail, "observed": count, "strict": "see_strict_result",
			"stop_reason": "native_observation" if count > 0 else "native_observation_absent"}))

class ErrorLog:
	extends Logger
	var messages: Array = []
	var lock: Mutex = Mutex.new()
	func _log_error(_function: String, file: String, _line: int, _code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			lock.lock()
			messages.append(file + ": " + rationale)
			lock.unlock()
	func total() -> int:
		lock.lock()
		var count: int = messages.size()
		lock.unlock()
		return count

class V101:
	extends "res://tests/test_review_v101.gd"
	var trace: Trace = Trace.new()
	func check(ok: bool, what: String) -> void:
		trace.observe(ok, what)
		super.check(ok, what)
	func _fixture_validity() -> void:
		var token: Dictionary = trace.begin("fixture_keys")
		super._fixture_validity()
		trace.finish(token)
	func _test_f1_ai_age_gap() -> void:
		var token: Dictionary = trace.begin("f1")
		super._test_f1_ai_age_gap()
		trace.finish(token)
	func _test_f2_betrothal_window() -> void:
		var token: Dictionary = trace.begin("f2")
		super._test_f2_betrothal_window()
		trace.finish(token)
	func _test_f5_cross_race_spouse() -> void:
		var token: Dictionary = trace.begin("f5_spouse")
		super._test_f5_cross_race_spouse()
		trace.finish(token)
	func _test_f7_mortality_intervals() -> void:
		var token: Dictionary = trace.begin("f7_mortality")
		super._test_f7_mortality_intervals()
		trace.finish(token)
	func _native_roll_seed(low: float, high: float) -> int:
		var token: Dictionary = trace.begin("native_seed_%f_%f" % [low, high])
		var seed_value: int = super._native_roll_seed(low, high)
		trace.finish(token)
		return seed_value
	func _test_f3_mounted_pool_rider_accounting() -> void:
		var token: Dictionary = trace.begin("f3_company")
		super._test_f3_mounted_pool_rider_accounting()
		trace.finish(token)
	func _test_f3_army_rider_settlement() -> void:
		var token: Dictionary = trace.begin("f3_army")
		super._test_f3_army_rider_settlement()
		trace.finish(token)
	func _test_f4_landscape_ui_layouts(tree: SceneTree) -> void:
		var token: Dictionary = trace.begin("f4_f5_f6_ui")
		await super._test_f4_landscape_ui_layouts(tree)
		trace.finish(token)

class Farm:
	extends "res://tests/test_farm_capacity_funding.gd"
	var trace: Trace = Trace.new()
	func check(ok: bool, why: String) -> void:
		trace.observe(ok, why)
		super.check(ok, why)
	func scenario(seed_v: int) -> void:
		var token: Dictionary = trace.begin("farm_seed_%d" % seed_v)
		super.scenario(seed_v)
		trace.finish(token)
	func add_real_grain(e: Dictionary, f: Dictionary, n: int) -> void:
		var token: Dictionary = trace.begin("physical_grain_transfer")
		super.add_real_grain(e, f, n)
		trace.finish(token)
	func floor_contract() -> void:
		var token: Dictionary = trace.begin("farm_floor")
		super.floor_contract()
		trace.finish(token)

class History:
	extends "res://tests/test_presim_short_history.gd"
	var trace: Trace = Trace.new()
	var option_label_ids: Array = []
	var freed_before_drain: int = 0
	var hook_before_options: bool = false
	func check(ok: bool, message: String) -> void:
		trace.observe(ok, message)
		super.check(ok, message)
	func _test_span_config() -> void:
		var token: Dictionary = trace.begin("history_config")
		super._test_span_config()
		trace.finish(token)
	func _watch_option_label(node: Node) -> void:
		if node is Label or node is RichTextLabel: option_label_ids.append(node.get_instance_id())
	func _test_options(tree: SceneTree) -> void:
		var token: Dictionary = trace.begin("history_options")
		hook_before_options = tree.node_added.is_connected(Callable(Sound, "_on_node_added"))
		tree.node_added.connect(_watch_option_label)
		super._test_options(tree)
		tree.node_added.disconnect(_watch_option_label)
		for instance_id: int in option_label_ids:
			if instance_from_id(instance_id) == null: freed_before_drain += 1
		trace.finish(token)

class Gore:
	extends "res://tests/test_gore_text.gd"
	var trace: Trace = Trace.new()
	var boss: Dictionary = {"full": 0, "reduced": 0}
	var variant: Dictionary = {"full": 0, "reduced": 0}
	var stuck: Dictionary = {"full": 0, "reduced": 0}
	var stuck_claims: Dictionary = {"full": 0, "reduced": 0}
	func _check(cond: bool, what: String) -> void:
		trace.observe(cond, what)
		super._check(cond, what)
	func _battles() -> Array:
		var token: Dictionary = trace.begin("gore_native_battles")
		var sims: Array = super._battles()
		trace.finish(token)
		return sims
	func _strikes(sims: Array) -> Array:
		var token: Dictionary = trace.begin("gore_strikes")
		var entries: Array = super._strikes(sims)
		trace.finish(token)
		return entries
	func _claims(entries: Array, full: bool) -> void:
		var mode: String = "full" if full else "reduced"
		var token: Dictionary = trace.begin("gore_claims_" + mode)
		var table: Array = CombatText.templates()["arrow"]["shield_boss"]
		var stuck_words: RegEx = RegEx.create_from_string("lodged|sticks fast|stuck fast|buried")
		for entry: Dictionary in entries:
			var data: Dictionary = entry["d"]
			if not data.has("shot"): continue
			if str(data.get("out", "")) == "shield_boss":
				boss[mode] = int(boss[mode]) + 1
				var picked: String = CombatText._pick(table, int(data.get("vk", 0)), int(data.get("vc", 0)))
				if table.size() > 1 and picked == str(table[1]): variant[mode] = int(variant[mode]) + 1
			elif str(data.get("out", "")) == "shield_stuck":
				stuck[mode] = int(stuck[mode]) + 1
				if stuck_words.search(super._render(entry).to_lower()) != null: stuck_claims[mode] = int(stuck_claims[mode]) + 1
		super._claims(entries, full)
		trace.finish(token)
	func _samples(entries: Array) -> void:
		var token: Dictionary = trace.begin("gore_samples")
		super._samples(entries)
		trace.finish(token)
	func _decisive(sims: Array) -> void:
		var token: Dictionary = trace.begin("gore_decisive")
		super._decisive(sims)
		trace.finish(token)
	func _reduced_words(entries: Array) -> void:
		var token: Dictionary = trace.begin("gore_reduced_words")
		super._reduced_words(entries)
		trace.finish(token)

func _arg(key: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="): return arg.get_slice("=", 1)
	return ""

func run(tree: SceneTree) -> int:
	var selected: String = _arg("--readiness-case")
	var group: String = _arg("--v101-case")
	var farm_case: String = _arg("--farm-case")
	var tested: RefCounted = null
	if selected == "v101" and group in ["f1", "f2", "f3", "ui", "f5"]:
		tested = V101.new()
	elif selected == "farm" and farm_case in ["floor", "901", "2026", "8801"]:
		tested = Farm.new()
	elif selected == "sound" and _arg("--history-case") == "options":
		tested = History.new()
	elif selected == "gore" and _arg("--gore-case") == "claims":
		tested = Gore.new()
	else:
		printerr("readiness harness: choose v101 + --v101-case=f1|f2|f3|ui|f5; farm + --farm-case=floor|901|2026|8801; sound + --history-case=options; gore + --gore-case=claims")
		print("READINESS_ONLY ", JSON.stringify({"strict_result": -1, "strict": "NOT_RUN", "stop_reason": "invalid_selector_harness_error", "diagnostic_exit_is_not_test_pass": true}))
		return 1
	var trace: Trace = tested.get("trace") as Trace
	var errors: ErrorLog = ErrorLog.new()
	OS.add_logger(errors)
	trace.count_errors = Callable(errors, "total")
	var whole: Dictionary = trace.begin("selected_" + selected)
	var strict: Variant = await tested.call("run", tree)
	trace.finish(whole)
	var drain: Dictionary = trace.begin("deferred_drain")
	await tree.process_frame
	await tree.process_frame
	trace.finish(drain)
	if selected == "v101":
		_v101_paths(trace, group)
	elif selected == "farm":
		_farm_paths(trace, farm_case)
	elif selected == "sound":
		var history: History = tested as History
		trace.guard("options.freed_screen", "Begin passes the exact one-day span", [], 1, true)
		trace.observed_path("sound.native_node_added_hook", 1 if history.hook_before_options else 0,
			"native Sound node_added hook was connected before the real options screen added labels")
		trace.observed_path("sound.freed_label_deferred_setup", history.freed_before_drain if history.hook_before_options else 0,
			"only real options labels: freed synchronously before inherited frame drains; callback errors counted separately")
	elif selected == "gore":
		var gore: Gore = tested as Gore
		for mode: String in ["full", "reduced"]:
			trace.observed_path("arrow.shield_boss." + mode, int(gore.boss[mode]), "native arrow strike outcome")
			trace.observed_path("arrow.shield_boss.variant_1." + mode, int(gore.variant[mode]), "unchanged native vk/vc selects actual template index 1")
			trace.observed_path("arrow.shield_stuck." + mode, int(gore.stuck[mode]), "native shield lodgement outcome")
			trace.observed_path("arrow.shield_stuck.claim_guard." + mode, int(gore.stuck_claims[mode]),
				"unchanged native shield_stuck entry renders prose matching the real stuck-claim regex")
		trace.guard("gore.claims.both_modes", "every claim in a strike line maps to a real wound", [], 2)
	var error_count: int = errors.total()
	OS.remove_logger(errors)
	var integer_result: bool = typeof(strict) == TYPE_INT
	var result: int = int(strict) if integer_result else -1
	var valid_result: bool = integer_result and result >= 0 and result == trace.failures and result == int(tested.get("fails"))
	var elapsed: int = Time.get_ticks_msec() - trace.started
	var stop: String = "completed"
	if error_count > 0 or not valid_result: stop = "harness_or_script_error"
	elif result > 0: stop = "strict_failure_do_not_run_next_test"
	elif elapsed >= 55000: stop = "budget_exceeded_not_ready"
	elif trace.misses > 0: stop = "coverage_miss_not_ready"
	print("READINESS_ONLY ", JSON.stringify({"case": selected, "v101_case": group, "farm_case": farm_case,
		"strict_result": result, "strict": ("PASS" if result == 0 else "FAIL") if valid_result and error_count == 0 else "NOT_COMPLETED",
		"observed_strict_failures": trace.failures, "harness_errors": error_count, "valid_strict_result": valid_result,
		"path_misses": trace.misses, "probe_elapsed_ms": elapsed, "budget_exceeded": elapsed >= 55000, "excludes_engine_startup": true,
		"stop_reason": stop, "phases": trace.phases, "diagnostic_exit_is_not_test_pass": true}))
	for row: Dictionary in trace.rows:
		if not bool(row["ok"]): print("READINESS_STRICT_FAILURE ", JSON.stringify(row))
	return 1 if error_count > 0 or not valid_result else 0

func _v101_paths(trace: Trace, group: String) -> void:
	trace.guard("fixture.native_keys_and_ages", "human lifespan control is 75", ["fixture race/culture keys exist", "fixture culture matches", "high_elf fixture uses"], 1, true)
	if group == "f1":
		trace.guard("ai.human_age_rejection", "F1: two humans aged", [], 1, true)
		trace.guard("ai.normalized_score", "F1: AI score normalizes")
		trace.guard("ai.same_race_rejection", "F1: AI same-race policy", [], 1, true)
		trace.guard("ai.direct_elf_wedding", "F1: two elves aged")
		trace.guard("ai.scheduled_elf_wedding", "F1: arrange_ai weds", ["F1: two elves aged"])
	elif group == "f2":
		trace.guard("betrothal.elf_window", "F2: elf betrothal_window")
		trace.guard("betrothal.no_infants_human_window", "F2: no infant betrothals")
		trace.guard("betrothal.positive_child_search", "F2: elf child of 30")
		for age: int in [24, 25, 30, 32, 33]:
			trace.guard("betrothal.elf_age_%d" % age, "F2: high_elf advertisement and candidates agree at age %d" % age, ["F2: elf child of 30"])
		trace.guard("betrothal.upper_interior", "F2: scaled child candidate upper window")
		trace.guard("betrothal.upper_exclusive", "F2: scaled upper candidate boundary", ["F2: scaled child candidate upper window"])
		trace.guard("betrothal.native_child_recount", "F2: native recount matches", [], 1, true)
		trace.guard("betrothal.native_adult_promotion", "F2: native age_up")
		trace.guard("betrothal.adult_search", "F2: at elf adulthood", ["F2: native age_up"])
		for pair: Array in [[9, 10], [10, 10], [10, 19], [10, 20]]:
			trace.guard("betrothal.human_%d_%d" % pair, "F2: human member %d/candidate %d" % pair)
	elif group == "f3":
		trace.guard("company.native_departure", "F3: native company enlistment", [], 1, true)
		trace.guard("company.bound_identity", "F3: rider resolves", ["F3: native company enlistment"], 1, true)
		for pair: Array in [
			["round_accounting", "F3: seated pool rider is counted"],
			["commander_morale", "F3: seated pool commander/officer"],
			["household_once", "F3: seated pool rider appears"],
			["company_deferral", "F3: rostered company rider defers"],
			["company_casualty", "F3: production company settlement"],
			["repeat_company_casualty", "F3: repeated production settlement"],
			["input_arrays", "F3: merging seats"]]:
			trace.guard("company." + str(pair[0]), str(pair[1]), ["F3: rider resolves"])
		for mode: String in ["roster", "detached", "outside", "state_dead"]:
			trace.guard("seats." + mode, "F3: %s seat is counted" % mode)
		for side: int in [0, 1]:
			for death: String in ["dead flag", "state-only"]:
				var prefix: String = "F3 army side %d (%s): " % [side, death]
				trace.guard(prefix + "draft", prefix + "native draft", [], 1, true)
				trace.guard(prefix + "enlist", prefix + "actual army enlistment", [prefix + "native draft"], 1, true)
				trace.guard(prefix + "service_and_identity", prefix + "real service", [prefix + "actual army enlistment"], 1, true)
				for step: String in ["seat-only death", "dragon settlement", "production roster", "repeated native"]:
					trace.guard(prefix + step, prefix + step, [prefix + "real service"])
	elif group == "ui":
		trace.guard("ui.mobile_branch", "F4: UiTheme.set_mobile_override", [], 1, true)
		for size: String in ["844x390", "1280x720"]:
			trace.guard("map.card_and_nav." + size, "F4a (%s): ruler card fits" % size, ["F4: UiTheme.set_mobile_override"])
			trace.guard("toast.bounds." + size, "F4b (%s): wrapped mobile" % size, ["F4: UiTheme.set_mobile_override"])
			trace.guard("toast.readable." + size, "F4b (%s): newest event" % size)
		trace.guard("map.wrapped_contract", "F4a: wrapped contract")
		trace.guard("toast.actual_newest_suffix", "F4b: trimming preserves", [], 2)
		trace.guard("toast.resize", "F4b resized to 844x390: wrapped")
		trace.guard("toast.zero_band", "F4b: no toast is retained", [], 2)
		trace.guard("market.auto_scroll", "F4c: TownMarketTab stock scroll", [], 1, true)
		trace.guard("market.real_overflow_actions", "F4c: populated 844px", ["F4c: TownMarketTab stock scroll"], 1, true)
		trace.guard("market.actions_reachable", "F4c: scrolling to the end", ["F4c: populated 844px"])
	elif group == "f5":
		trace.guard("biology.native_seed_setup", "F5a: native RNG seed reaches", [], 1, true)
		for pair: Array in [
			["source_race", "F5: source spouse"],
			["native_wedding", "F5: cross-race wedding"],
			["personal_race", "F5: married-in elf"],
			["native_codec", "F5: mixed household encodes"],
			["genealogy", "F5: succession genealogy"],
			["identity_after_restore", "F5: save/load preserves"],
			["fertility_and_age", "F5: spouse stays an adult"],
			["later_age", "F5: elf spouse in human household ages"],
			["personal_adulthood", "F5: marriage eligibility"],
			["elf_hazard", "F5a: per-elder weekly mortality"],
			["human_hazard_control", "F5a: identical weekly mortality"],
			["null_research", "F5b: set_person_race"],
			["legacy_person", "F5c: legacy person array"]]:
			trace.guard("biology." + str(pair[0]), str(pair[1]), ["F5: source spouse"])
		for mode: String in ["mixed_human", "mixed_elf", "mixed_away", "homogeneous", "minority", "minority_rate"]:
			var prefix: String = "F7 %s: " % mode
			if mode.begins_with("minority"):
				trace.guard(prefix + "native_troll_fixture", prefix + "two native troll elders", [], 1, true)
			trace.guard(prefix + "native_seed_setup", prefix + "native RNG seed reaches", [], 1, true)
			trace.guard(prefix + "draw_precondition", prefix + "deterministic roll", [prefix + "native draw lies inside"], 1, true)
			trace.guard(prefix + "native_mortality_counters", prefix + "one existing weekly draw", [prefix + "deterministic roll"])
			var final_endpoint: String = "the correct elder"
			if mode == "mixed_away": final_endpoint = "an absent human elder"
			elif mode == "minority_rate": final_endpoint = "both trolls survive"
			trace.guard(prefix + "victim_or_exclusion", prefix + final_endpoint, [prefix + "one existing weekly draw"])

func _farm_paths(trace: Trace, selected: String) -> void:
	if selected == "floor":
		trace.guard("farm.native_funding_helper", "native farm funding helper exists", [], 1, true)
		trace.guard("farm.early_exit_pending_receipt", "early family exit")
		trace.guard("farm.four_actual_purse_inputs", "bounded funding retains", [], 4)
		trace.guard("farm.owed_and_offset", "limited savings preserve", [], 4)
		trace.guard("farm.repeat_conservation", "repeat helper neither", [], 4)
	else:
		trace.guard("farm.generated_human_town", "generated culture supports", [], 1, true)
		trace.guard("farm.physical_grain", "generated real cereal fields", [], 4, true)
		trace.guard("farm.native_capacity", "ordinary harvest turn creates", ["generated real cereal fields"], 2)
		trace.guard("farm.same_turn_funding", "new or increased harvest cap funded", ["ordinary harvest turn creates"], 2)
		trace.guard("farm.pending_capacity", "external capacity increase records", ["ordinary harvest turn creates"], 2)
		trace.guard("farm.native_save_load", "pending capacity funding saves and loads", ["external capacity increase records"], 2)
		trace.guard("farm.receipt_consumed_once", "subsequent turn never reports", ["pending capacity funding saves and loads"], 2)
