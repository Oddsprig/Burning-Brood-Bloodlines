extends "res://tests/diag_startup_slices.gd"
const Parts201 = preload("res://tests/fixtures/older_201_parts_v100.gd")

func run(tree: SceneTree) -> int:
	var cases: Array = ["setup", "finish", "verify"]
	for day_number: int in range(1, 31): cases.append("day%d" % day_number)
	var part: String = Parts201.select(cases)
	if part.is_empty(): return 1
	if part == "all": return await super.run(tree)
	if part == "verify": return _verify_pair()
	var mode: String = _setting("STARTUP_MODE", "sliced")
	var budget: int = int(_setting("STARTUP_BUDGET_USEC", "12000"))
	var frames: bool = _setting("STARTUP_FRAMES", "0") == "1"
	var fixed: bool = _setting("STARTUP_FIXED_RAIDS", "0") == "1"
	var timeout_us: int = int(float(_setting("STARTUP_TIMEOUT_SEC", "300")) * 1e6)
	check(mode in ["atomic", "sliced"] and budget >= 0 and timeout_us > 0, "original startup scheduling configuration is valid")
	if mode == "sliced": check(load("res://campaign/world.gd").has_method("presim_slice"), "sliced history API exists")
	check(_setting("STARTUP_DAYS", "30") == "30" and _setting("STARTUP_SIZE", "normal") == "normal" and _setting("STARTUP_SEED", "777") == "777", "split protocol retains thirty Normal days and seed777")
	check(fixed, "paired short startup protocol requires original fixed diagnostic raids")
	if failures > 0: return failures
	var io: RefCounted = Parts201.new("startup_" + mode)
	if io.fails > 0: return 1
	output = io.root
	var audit: RefCounted = Audit.new()
	var config: Dictionary = {"mode": mode, "budget": budget, "frames": frames, "fixed": fixed,
		"slice_gate": float(_setting("STARTUP_MAX_SLICE_MS", "0")), "frame_gate": float(_setting("STARTUP_MAX_FRAME_MS", "0")), "timeout_us": timeout_us}
	var state: Dictionary = {}
	if part == "setup":
		WorldGen.gen_size = "normal"
		var start: int = Time.get_ticks_usec()
		Game.new_game(777)
		# Native generation resets this diagnostic flag; capture the requested quota afterwards.
		HerdRaids.benchmark_fixed_steps = fixed
		Game.world["presim"] = {"total": 30, "done": 0, "from": Game.day}
		state = {"config": config, "setup_us": Time.get_ticks_usec() - start,
			"checkpoints": {"initial": snapshot("initial")}, "company_ages": {}, "company_births": {},
			"initial_gold": Game.gold, "slices": [], "frame_gaps": [], "completed": [], "cpu_us": 0,
			"overshoots": 0, "iterations": 0, "measured_wall_us": 0}
		for unit: Unit in Game.company:
			state["company_ages"][unit.uid] = unit.age
			state["company_births"][unit.uid] = unit.born
		audit.harvest_report["available"] = true
		audit.harvest_sample(int(Game.day))
		state["harvest"] = audit.harvest_report
		CampaignWorld.job_total = {}; CampaignWorld.job_worst = {}
		CampaignWorld.steps_total = 0; CampaignWorld.step_parts = {}; CampaignWorld.daily_total = {}
		io.context = state
		var saved: bool = failures == 0 and io.save_step(0)
		HerdRaids.benchmark_fixed_steps = false
		return 0 if saved else maxi(1, failures)
	var step: int = 31 if part == "finish" else int(part.trim_prefix("day"))
	if not io.load_step(step - 1): HerdRaids.benchmark_fixed_steps = false; return 1
	state = io.context
	check(HerdRaids.benchmark_fixed_steps == fixed, "native predecessor retains the requested fixed raid quota")
	check(state["config"] == config, "every process retains the original scheduling configuration and gates")
	check(int(Game.world["presim"]["total"]) == 30 and int(Game.world["presim"]["done"]) == mini(30, step - 1), "exact predecessor, total and completed history days")
	if failures > 0: HerdRaids.benchmark_fixed_steps = false; return failures
	audit.harvest_report = state["harvest"]
	var pending: Dictionary = {}
	if step <= 30:
		var wall_start: int = Time.get_ticks_usec()
		while int(Game.world["presim"]["done"]) < step and failures == 0:
			check(Time.get_ticks_usec() - wall_start < 55000000, "selected native day completes within short diagnostic bound")
			check(int(state["measured_wall_us"]) + Time.get_ticks_usec() - wall_start < timeout_us, "history completes within bounded diagnostic timeout")
			check(int(state["iterations"]) < 30 * 20000, "bounded scheduling iteration count")
			if failures > 0: break
			var before: int = int(Game.world["presim"]["done"])
			var before_day: float = Game.day
			var slice_start: int = Time.get_ticks_usec()
			var left: int = CampaignWorld.presim_step(Game, 1) if mode == "atomic" else _slice(pending, budget)
			var elapsed: int = Time.get_ticks_usec() - slice_start
			state["cpu_us"] += elapsed; state["slices"].append(elapsed); state["iterations"] += 1
			if elapsed > budget: state["overshoots"] += 1
			if frames:
				await tree.process_frame
				state["frame_gaps"].append(Time.get_ticks_usec() - slice_start)
			var done: int = int(Game.world["presim"]["done"])
			check(left == 30 - done, "remaining-day counter agrees with completed-day counter")
			check(done >= before and done <= before + 1, "a slice completes at most one day")
			check(Game.day >= before_day and Game.day <= before_day + 1.0, "a slice advances the date at most once")
			check(Game.day == float(done) if pending.is_empty() else Game.day == float(done + 1), "date reflects exactly one in-progress day")
			if done > before:
				check(pending.is_empty(), "completed day leaves no partial scheduling state")
				check(Game.world.get("work", []).is_empty(), "completed day drains its entire work queue")
				state["completed"].append({"day": done, "cpu_seconds": float(state["cpu_us"]) / 1e6, "slices": state["iterations"]})
				audit.harvest_sample(done)
				if done == 1 or done == 30:
					var label: String = "day_%04d" % done
					state["checkpoints"][label] = snapshot(label)
		var elapsed_wall_us: int = Time.get_ticks_usec() - wall_start
		state["measured_wall_us"] += elapsed_wall_us
		check(elapsed_wall_us < 55000000, "selected native day completes within short diagnostic bound")
		check(int(state["measured_wall_us"]) < timeout_us, "complete history retains the original cumulative timeout")
		check(int(Game.world["presim"]["done"]) == step and Game.day == float(step), "selected complete native history day executes exactly once")
		state["harvest"] = audit.harvest_report
		io.context = state
		var saved: bool = failures == 0 and io.save_step(step)
		HerdRaids.benchmark_fixed_steps = false
		return 0 if saved else maxi(1, failures)
	check(CampaignWorld.presim_left(Game) == 0, "all requested days completed")
	check(Game.day == 30.0, "final day matches requested history")
	check(pending.is_empty() and Game.world.get("work", []).is_empty(), "final state has no pending day or work")
	check(Game.gold == int(state["initial_gold"]), "company pays no wages during history")
	for unit: Unit in Game.company:
		check(unit.born == state["company_births"][unit.uid], "company birth date stays fixed until history finish")
		check(unit.age == People.age_on(unit, Game.day), "company interim age follows the existing calendar")
	check(Sickness.check_counts(Game.world).is_empty(), "valid sickness counts")
	check(int(audit.harvest_report["violation_count"]) == 0, "dated ownership, physical stock, reserve and cash backing remain reconciled")
	if failures == 0:
		var before_complete: Dictionary = snapshot("complete")
		var idle_left: int = CampaignWorld.presim_step(Game, 1) if mode == "atomic" else _slice(pending, budget)
		check(idle_left == 0 and pending.is_empty(), "slicing a completed history is a no-op")
		var after_complete: Dictionary = snapshot("complete_again")
		check(before_complete["ordered_sha256"] == after_complete["ordered_sha256"], "completed-history no-op preserves complete state")
		CampaignWorld.presim_finish(Game, 0)
		check(Game.world["presim"].get("finished", false), "history finish is recorded")
		check(Game.food_clock["last"] == Game.day, "company food clock begins on arrival")
		check(Game.world["party"]["safe_until"] == Game.day + 0.5, "company receives the original arrival safety window")
		for unit: Unit in Game.company: check(unit.age == state["company_ages"][unit.uid], "company preserves its starting age after finish")
		state["checkpoints"]["finished"] = snapshot("finished")
	var max_slice: float = _percentile(state["slices"], 1.0)
	var max_frame: float = _percentile(state["frame_gaps"], 1.0)
	if float(config["slice_gate"]) > 0: check(max_slice <= float(config["slice_gate"]), "maximum slice fits explicitly requested responsiveness gate")
	if float(config["frame_gate"]) > 0:
		check(frames, "frame gate requires STARTUP_FRAMES=1")
		check(max_frame <= float(config["frame_gate"]), "maximum measured frame gap fits requested responsiveness gate")
	var report: Dictionary = {"mode": mode, "seed": 777, "size": "normal", "requested_days": 30,
		"fixed_raids": fixed, "frames_enabled": frames, "budget_usec": budget, "timeout_us": timeout_us, "setup_seconds": float(state["setup_us"]) / 1e6,
		"simulation_cpu_seconds": float(state["cpu_us"]) / 1e6, "diagnostic_wall_seconds": float(state["measured_wall_us"]) / 1e6,
		"slice_us": state["slices"], "frame_gap_us": state["frame_gaps"], "slice_count": state["iterations"],
		"budget_overshoots": state["overshoots"], "worst_slice_ms": max_slice, "p95_slice_ms": _percentile(state["slices"], 0.95),
		"worst_frame_gap_ms": max_frame, "p95_frame_gap_ms": _percentile(state["frame_gaps"], 0.95),
		"completed_boundaries": state["completed"], "job_counts": _job_counts(), "job_worst_us": CampaignWorld.job_worst,
		"checkpoints": state["checkpoints"], "end_day": Game.day, "ownership_checks": audit.harvest_report["checks"],
		"ownership_violations": audit.harvest_report["violation_count"], "failures": failures}
	_compare(report, OS.get_environment("STARTUP_COMPARE_DIR"))
	report["failures"] = failures
	write_json("startup-timings.json", report); write_json("startup-harvest-audit.json", audit.harvest_report)
	state["report"] = report; io.context = state
	var saved: bool = failures == 0 and io.save_step(31)
	HerdRaids.benchmark_fixed_steps = false
	return 0 if saved else maxi(1, failures)

func _verify_pair() -> int:
	var atomic: RefCounted = Parts201.new("startup_atomic")
	var sliced: RefCounted = Parts201.new("startup_sliced")
	if atomic.fails > 0 or sliced.fails > 0: return 1
	if not atomic.verify_chain(31) or not sliced.verify_chain(31): return 1
	var first: Dictionary = atomic.read_record("31")
	var second: Dictionary = sliced.read_record("31")
	if first.is_empty() or second.is_empty(): return 1
	var a: Dictionary = first["context"]["report"]
	var b: Dictionary = second["context"]["report"]
	check(int(a["failures"]) == 0 and int(b["failures"]) == 0, "both complete original startup modes passed")
	check(a["mode"] == "atomic" and b["mode"] == "sliced", "independent atomic and sliced receipts exist")
	for key: String in ["seed", "size", "requested_days", "fixed_raids"]: check(a[key] == b[key], "paired configuration agrees: " + key)
	check((a["completed_boundaries"] as Array).size() == 30 and (b["completed_boundaries"] as Array).size() == 30, "both modes completed every original day")
	_compare_counts(a["job_counts"], b["job_counts"], "identical jobs executed by kind")
	check(a["checkpoints"].keys() == b["checkpoints"].keys(), "identical complete checkpoint set and order")
	for label: String in a["checkpoints"]:
		for key: String in ["sha256", "ordered_sha256", "next_unit_uid", "next_item_uid"]:
			check(a["checkpoints"][label][key] == b["checkpoints"][label][key], "complete paired state agrees: " + label + "/" + key)
	return failures
