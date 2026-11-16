extends "res://tests/frame_measure_common.gd"
## Attribution only: the unchanged full frame fixture, native days 1-3.
## Exit zero reports timing, including slow days; only harness errors fail.
const PROBE_WALL_USEC: int = 50000000
const COST_DAYS: int = 3
var _probe_deadline: int = 0

func _progress_ok(phase: String, budget_us: int, token: String) -> bool:
	if Time.get_ticks_usec() >= _probe_deadline:
		_reason = "50-second day timing probe deadline exceeded during " + phase
		return false
	return super._progress_ok(phase, budget_us, token)

func _progress_token() -> String:
	var capture: Object = Game.get("_save_capture") as Object
	var slices: int = -1 if capture == null else int(capture.get("slices"))
	return "%.9f|%d|%d|%d|%d|%d|%d" % [
		Game.day, int(Game.world.get("last_day", -1)),
		(Game.world.get("work", []) as Array).size(),
		(Game.world.get("fight_work", []) as Array).size(),
		_sum_counts(_job_counts()), slices, int(Game.get("_save_task"))]

func _probe_sim_settled() -> bool:
	if not (Game.world.get("work", []) as Array).is_empty() \
			or not (Game.world.get("fight_work", []) as Array).is_empty():
		return false
	# The unpatched game has no continuation owner/actions. If present, require
	# their exact committed boundary too, without depending on patched classes.
	if Game.has_method("_day_job_transaction_active"):
		var actions: Array = Game.get("_day_job_actions")
		return not bool(Game.call("_day_job_transaction_active")) and actions.is_empty()
	return true

func run(tree: SceneTree) -> int:
	_started_us = Time.get_ticks_usec()
	_probe_deadline = _started_us + PROBE_WALL_USEC
	_reason = ""
	_guard_phase = ""
	if tree == null or _save_inflight() or bool(Game.get("_save_pending")):
		printerr("DAY TIMING PROBE HARNESS FAIL: isolated idle-save runner required.")
		return 1
	var old_size: String = WorldGen.gen_size
	var old_span: int = CampaignWorld.presim_span_days
	var old_prof_on: bool = TownEcon.prof_on
	var old_process: bool = Game.is_processing()
	var old_screen: String = String(Game.get("_active_screen"))
	var old_paused: bool = tree.paused
	var old_fps: int = Engine.max_fps
	var old_scale: float = Engine.time_scale
	Game.set_process(false)
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	tree.paused = false
	Game.set("_active_screen", "map")
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	TownEcon.prof_on = false
	# Inherit the original seed-9001, 27-town, full-depth world verbatim.
	var ready: bool = await _setup_world(tree)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	if not ready and _reason.is_empty():
		_reason = "Full frame fixture unavailable."
	print("DAY TIMING PROBE fixture %s; world_load_ms %.3f; unmounted warmup 1-3; attribution only" % [str(_receipt), _wall_ms()])
	var completed: int = 0
	if ready:
		Game.world["party"]["waiting"] = false
		var yielded_us: int = Time.get_ticks_usec()
		for day: int in range(1, COST_DAYS + 1):
			var jobs_before: Dictionary = CampaignWorld.job_total.duplicate(true)
			var daily_before: Dictionary = CampaignWorld.daily_total.duplicate()
			var steps_before: int = CampaignWorld.steps_total
			var roll_before: int = (Game.world.get("army", {}).get("roll", {}) as Dictionary).size()
			var forces_before: int = (Game.world.get("warbands", {}) as Dictionary).size()
			var day_started_usec: int = Time.get_ticks_usec()
			if not _progress_ok("warmup", WARMUP_USEC, _progress_token()):
				break
			# Same unmounted warmup decision and public API as r14/r15.
			Game.advance_time(1.0, false, 0, 0)
			var sim_done_usec: int = Time.get_ticks_usec() if _probe_sim_settled() else 0
			while not _settled() or not _probe_sim_settled():
				if sim_done_usec == 0 and _probe_sim_settled():
					sim_done_usec = Time.get_ticks_usec()
				Game._process(FRAME_DELTA)
				if not tree.paused:
					if CampaignWorld.work_slice(Game, 0) > 0:
						Game.changed.emit()
				var writer_only: bool = not (Game.get("_save_capture") is Object) \
					and int(Game.get("_save_task")) != -1 \
					and (Game.world.get("work", []) as Array).is_empty() \
					and (Game.world.get("fight_work", []) as Array).is_empty()
				if writer_only or Time.get_ticks_usec() - yielded_us >= WARMUP_YIELD_USEC:
					await tree.process_frame
					yielded_us = Time.get_ticks_usec()
				if not _progress_ok("warmup", WARMUP_USEC, _progress_token()):
					break
			if not _reason.is_empty():
				break
			if int(Game.world.get("last_day", -1)) != day or not is_equal_approx(Game.day, float(day)):
				_reason = "Native warmup calendar did not advance exactly to day %d." % day
				break
			var settled_usec: int = Time.get_ticks_usec()
			if sim_done_usec == 0:
				sim_done_usec = settled_usec
			print("FRAME DAY TIMING day %d; simulation_ms %.3f; settled_ms %.3f; post_sim_save_ms %.3f" % [day, float(sim_done_usec - day_started_usec) / 1000.0, float(settled_usec - day_started_usec) / 1000.0, float(settled_usec - sim_done_usec) / 1000.0])
			_cost_receipt(day, jobs_before, daily_before, steps_before, roll_before, forces_before)
			completed += 1
	if completed != COST_DAYS and _reason.is_empty():
		_reason = "Incomplete day cost probe: %d/%d days." % [completed, COST_DAYS]
	if Time.get_ticks_usec() >= _probe_deadline and _reason.is_empty():
		_reason = "50-second day timing probe deadline exceeded."
	Game.set("_active_screen", old_screen)
	Game.set_process(old_process)
	tree.paused = old_paused
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	TownEcon.prof_on = old_prof_on
	if not _reason.is_empty():
		printerr("DAY TIMING PROBE HARNESS FAIL: %s; wall_ms %.3f" % [_reason, _wall_ms()])
		return 1
	print("DAY1 COST PROBE COMPLETE: days 1-3; measurement only; wall_ms %.3f" % _wall_ms())
	return 0

## Existing unsaved aggregate counters, sampled outside each timed interval.
## Jobs are non-overlapping native dispatch boundaries. Daily parts and movement
## are separate annotations; never sum inclusive Perf labels into a day total.
func _cost_receipt(day: int, jobs_before: Dictionary, daily_before: Dictionary, steps_before: int, roll_before: int, forces_before: int) -> void:
	var jobs: Dictionary = {}
	var dispatch_usec: int = 0
	var kinds: Array = CampaignWorld.job_total.keys()
	kinds.sort()
	for kind: Variant in kinds:
		var after: Array = CampaignWorld.job_total[kind]
		var before: Array = jobs_before.get(kind, [0, 0])
		var calls: int = int(after[1]) - int(before[1])
		if calls == 0: continue
		var elapsed_usec: int = int(after[0]) - int(before[0])
		dispatch_usec += elapsed_usec
		jobs[kind] = {"ms": float(elapsed_usec) / 1000.0, "calls": calls}
	var daily: Dictionary = {}
	for part: Variant in CampaignWorld.daily_total:
		daily[part] = float(int(CampaignWorld.daily_total[part]) - int(daily_before.get(part, 0))) / 1000.0
	print("DAY1 COST day %d; %s" % [day, JSON.stringify({"jobs": jobs,
		"dispatch_ms": float(dispatch_usec) / 1000.0, "daily_parts_ms": daily,
		"movement_and_creatures_ms": float(CampaignWorld.steps_total - steps_before) / 1000.0,
		"roll_entries_before": roll_before, "forces_before": forces_before})])
