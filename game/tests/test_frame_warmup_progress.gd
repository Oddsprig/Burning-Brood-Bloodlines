extends "res://tests/test_army_split_equiv.gd"
## Quick liveness regression only: the unchanged frame fixture through day 10.
## No comparison forks, measured map window or manufactured economic inputs.
# Historical UNPATCHED full-settlement receipt, not a simulation-only duration.
# runs/v100_frame_measure_r7.log: 15447.824 - 6825.819 ms. No tolerance is added.
const UNPATCHED_DAY1_SETTLED_USEC: int = 8622005

func run(tree: SceneTree) -> int:
	var started_usec: int = Time.get_ticks_usec()
	_deadline = started_usec + WALL_USEC
	if tree == null or Game._save_capture != null or Game._save_task != -1 or Game._save_pending:
		printerr("FRAME WARMUP PROGRESS FAIL: an isolated idle-save runner is required.")
		return 1
	_check_admission()
	if not _failure.is_empty():
		printerr("FRAME WARMUP PROGRESS FAIL: " + _failure)
		return 1
	var old_size: String = WorldGen.gen_size
	var old_span: int = CampaignWorld.presim_span_days
	var old_prof_on: bool = TownEcon.prof_on
	var old_process: bool = Game.is_processing()
	var old_screen: String = String(Game._active_screen)
	var old_paused: bool = tree.paused
	var old_fps: int = Engine.max_fps
	var old_scale: float = Engine.time_scale
	Game.set_process(false)
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	tree.paused = false
	Game._active_screen = "map"
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	TownEcon.prof_on = false
	var fixture: NativeFixture = NativeFixture.new()
	fixture.hard_deadline = _deadline
	fixture._started_us = started_usec
	var ready: bool = await fixture._setup_world(tree)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	if not ready:
		_failure = fixture._reason if not fixture._reason.is_empty() else "Full frame fixture unavailable."
	var counts_before: Dictionary = fixture._job_counts()
	var warmup_started_usec: int = Time.get_ticks_usec()
	var day10_usec: int = 0
	var day10_settled_usec: int = 0
	if ready:
		Game._active_screen = "map"
		ready = await fixture._warmup(tree)
	if ready:
		# The existing warmup asserts every settled day 1-9. Reach day 10
		# through the same public API and drain it with the same guard.
		var day10_started_usec: int = Time.get_ticks_usec()
		Game.advance_time(1.0, false, 0, 0)
		var advance_usec: int = Time.get_ticks_usec() - day10_started_usec
		ready = await fixture.settle(tree)
		day10_usec = advance_usec + fixture.settle_sim_usec
		day10_settled_usec = Time.get_ticks_usec() - day10_started_usec
		print("FRAME DAY TIMING day 10; simulation_ms %.3f; settled_ms %.3f" % [float(day10_usec) / 1000.0, float(day10_settled_usec) / 1000.0])
	if not ready and _failure.is_empty():
		_failure = fixture._reason if not fixture._reason.is_empty() else "Native warmup did not settle."
	if ready and (not is_equal_approx(Game.day, 10.0) or int(Game.world.get("last_day", -1)) != 10 or not fixture._settled()):
		_failure = "The exact frame world did not advance and settle day 10."
	var warmup_usec: int = Time.get_ticks_usec() - warmup_started_usec
	var warmup_seconds_per_day: float = float(fixture.warmup_sim_usec + day10_usec) / 1000000.0 / 10.0
	var worst_day_seconds: float = float(maxi(fixture.warmup_day_worst_usec, day10_usec)) / 1000000.0
	if ready and _failure.is_empty() and (warmup_seconds_per_day > 5.0 or worst_day_seconds > 5.0):
		_failure = "Warmup simulation exceeded normal day throughput: average %.3f s/day; worst %.3f s/day." % [warmup_seconds_per_day, worst_day_seconds]
	if ready and fixture.warmup_day_receipts.size() != 9 and _failure.is_empty():
		_failure = "Missing per-day native simulation/settlement receipts."
	if ready and not fixture.warmup_day_receipts.is_empty():
		var first: Dictionary = fixture.warmup_day_receipts[0]
		var day1_settled_usec: int = int(first["settled_usec"])
		print("FRAME DAY1 BASELINE unpatched_settled_ms %.3f; patched_settled_ms %.3f; delta_ms %.3f; generation_excluded 0; historical_single_sample" % [float(UNPATCHED_DAY1_SETTLED_USEC) / 1000.0, float(day1_settled_usec) / 1000.0, float(day1_settled_usec - UNPATCHED_DAY1_SETTLED_USEC) / 1000.0])
		if day1_settled_usec > UNPATCHED_DAY1_SETTLED_USEC and _failure.is_empty():
			_failure = "First-day full settlement was slower than the unpatched receipt: %.3f ms > %.3f ms; investigate before acceptance." % [float(day1_settled_usec) / 1000.0, float(UNPATCHED_DAY1_SETTLED_USEC) / 1000.0]
	var counts_after: Dictionary = fixture._job_counts()
	for kind: String in ["coin", "tturn"]:
		if _failure.is_empty() and int(counts_after.get(kind, 0)) <= int(counts_before.get(kind, 0)):
			_failure = "No native warmup job progress for " + kind
	if Time.get_ticks_usec() >= _deadline and _failure.is_empty():
		_failure = "50-second internal deadline exceeded; incomplete, not passed."
	if not _failure.is_empty():
		_stopped_head(tree)
	# Abandon only this failed test's retained job after capturing the failure.
	# No queue or hold is bypassed while proving progress.
	if CampaignWorld.day_job_pending(Game):
		var abandoned: CampaignDayJob = Game.world["work"][0][-1]
		abandoned.after.clear()
		abandoned.release(Game)
		Game.world["work"] = []
	Game._save_pending = false
	Game._autosave_day_pending = false
	Game._day_job_owner = null
	Game._day_job_dispatching = false
	Game._day_job_actions.clear()
	Game._day_job_observers.clear()
	Game._day_job_changed_pending = false
	Game._day_job_slice_frame = -1
	Game._day_job_quit_generation = -1
	Game._active_screen = old_screen
	Game.set_process(old_process)
	tree.paused = old_paused
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	TownEcon.prof_on = old_prof_on
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	if elapsed_usec >= WALL_USEC and _failure.is_empty():
		_failure = "50-second internal deadline exceeded; incomplete, not passed."
	if not _failure.is_empty():
		printerr("FRAME WARMUP PROGRESS FAIL: %s; wall_ms %.3f" % [_failure, float(elapsed_usec) / 1000.0])
		return 1
	print("FRAME WARMUP PROGRESS PASS: exact frame fixture; settled days 1-10; native coin/tturn advanced; simulation_s_per_day %.3f; worst_simulation_day_s %.3f; settled_warmup_ms %.3f; wall_ms %.3f" % [warmup_seconds_per_day, worst_day_seconds, float(warmup_usec) / 1000.0, float(elapsed_usec) / 1000.0])
	return 0

func _stopped_head(tree: SceneTree) -> void:
	var work: Array = Game.world.get("work", [])
	var head: Array = [] if work.is_empty() else work[0]
	var kind: String = "<none>" if head.is_empty() else String(head[0])
	var continued: bool = not head.is_empty() and CampaignWorld.frame_job(head)
	var owner: CampaignDayJob = Game._day_job_owner
	var head_owner: CampaignDayJob = null
	if not head.is_empty() and head[-1] is CampaignDayJob:
		head_owner = head[-1]
	var receipt: Dictionary = {"day": Game.day, "last_day": Game.world.get("last_day", -1),
		"header": str(head), "kind": kind, "work": work.size(),
		"job_worst": CampaignWorld.job_worst.get(kind, 0),
		"frame_job_worst": CampaignWorld.frame_job_worst.get(kind, 0),
		"frame_job": continued, "remaining_usec": Game._day_job_frame_remaining_usec(),
		"allowance_usec": 4000, "reserve_usec": 4000 if continued else 0,
		"owner": str(owner), "owner_done": owner != null and owner.done,
		"owner_holds_tree": owner != null and owner.holds_tree,
		"head_owner_done": head_owner != null and head_owner.done,
		"head_owner_holds_tree": head_owner != null and head_owner.holds_tree,
		"tree_paused": tree.paused, "capture": Game._save_capture != null,
		"writer": Game._save_task, "save_pending": Game._save_pending,
		"autosave_pending": Game._autosave_day_pending,
		"slice_frame": Game._day_job_slice_frame,
		"actions": Game._day_job_actions.size(), "observers": Game._day_job_observers.size()}
	print("FRAME WARMUP STOPPED HEAD: " + JSON.stringify(receipt))
