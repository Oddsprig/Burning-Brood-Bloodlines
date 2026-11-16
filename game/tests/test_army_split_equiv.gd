extends RefCounted
## Native day-10 frame warmup; atomic versus continued queues and real holds.
const WALL_USEC: int = 50000000
const SPLIT_KINDS: Array = ["herds", "army", "army_pay", "army_tree", "army_misc", "arms_supply"]
const KINDS: Array = ["army", "army_pay", "army_tree", "army_misc", "arms_supply"]
var _deadline: int = 0
var _failure: String = ""
var _held: int = 0
var _coverage: Dictionary = {}
var _actions: Array = []
var _save_checked: bool = false
var _directed_started: Dictionary = {}
var _held_receipts: Dictionary = {}
var _held_by_kind: Dictionary = {}
var _camp_id: String = ""
var _camp_atomic_paid: bool = false
var _camp_continued_paid: bool = false
var _camp_payroll_held: bool = false
var _camp_payroll_receipt: Dictionary = {}
var _fixture_ready: bool = false
var _warmup_ready: bool = false
var _native_counters: Dictionary = {"camps_checked": 0, "volunteers_available": 0,
	"soldiers_registered": 0, "payroll_funded": 0, "selected_payable": 0,
	"same_faction_towns": 0, "supply_moved": 0, "supply_towns_moved": 0}
var _fixture_receipt: Dictionary = {}
const CONTRACT_PROBE: GDScript = preload("res://tests/day_job_contract_probe.gd")

## The frame test's exact setup and existing day 1-9 warmup.
## Required camp/supply subjects must arise in that same world or fail.
class NativeFixture:
	extends "res://tests/frame_measure_common.gd"
	var hard_deadline: int = 0
	var settle_sim_usec: int = 0

	func _progress_ok(phase: String, budget_us: int, token: String) -> bool:
		if Time.get_ticks_usec() >= hard_deadline:
			_reason = "50-second deadline exceeded during native fixture " + phase
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

	func _setup_world(tree: SceneTree) -> bool:
		return await super._setup_world(tree)

	func settle(tree: SceneTree) -> bool:
		var started_usec: int = Time.get_ticks_usec()
		var sim_done_usec: int = started_usec if _warmup_sim_settled() else 0
		settle_sim_usec = 0
		var yielded_us: int = Time.get_ticks_usec()
		while not _settled():
			if sim_done_usec == 0 and _warmup_sim_settled():
				sim_done_usec = Time.get_ticks_usec()
			if not _progress_ok("warmup", WARMUP_USEC, _progress_token()):
				return false
			Game._process(FRAME_DELTA)
			if not tree.paused:
				if CampaignWorld.work_slice(Game, 4000) > 0:
					Game.changed.emit()
			var writer_only: bool = not (Game.get("_save_capture") is Object) \
				and int(Game.get("_save_task")) != -1 \
				and (Game.world.get("work", []) as Array).is_empty() \
				and (Game.world.get("fight_work", []) as Array).is_empty()
			if writer_only or Time.get_ticks_usec() - yielded_us >= WARMUP_YIELD_USEC:
				await tree.process_frame
				yielded_us = Time.get_ticks_usec()
		settle_sim_usec = (Time.get_ticks_usec() if sim_done_usec == 0 else sim_done_usec) - started_usec
		return true

## Force only scheduling deadlines, then await the real inherited checkpoint.
## One forced progressed hold per kind and one post-payment camp hold keep this
## bounded and independent of CPU speed; no economic operation is overridden.
class HeldArmyJob:
	extends "res://campaign/army_day_job.gd"
	var forced_once: bool = false
	var payroll_id: String = ""
	var payroll_lair: Dictionary = {}
	var payroll_families: Array = []
	var payroll_gold: float = 0.0
	var payroll_purse: float = 0.0
	var payroll_yielded: bool = false
	var payroll_frame: int = -1

	func _init(game: Variant, header: Array) -> void:
		super(game, header)

	func _purses() -> float:
		var total: float = 0.0
		for family: Dictionary in payroll_families:
			total += float(family["purse"])
		return total

	func _checkpoint(label: String) -> void:
		if budgeted and not forced_once and String(_s["stage"]) != "open":
			_deadline_usec = 0
			forced_once = true
		if budgeted and not payroll_lair.is_empty() and String(_s["stage"]) == "camp" and int(_s["i"]) > 0 and String(_s["lids"][int(_s["i"]) - 1]) == payroll_id:
			if label == "Army.pay_units:enter":
				payroll_gold = float(payroll_lair.get("gold", 0.0))
				payroll_purse = _purses()
			elif label == "Army.pay_units:loop" and not payroll_yielded and float(payroll_lair.get("gold", 0.0)) < payroll_gold and _purses() > payroll_purse:
				_deadline_usec = 0
				payroll_yielded = true
				payroll_frame = Engine.get_process_frames()
		await super._checkpoint(label)

func _check_admission() -> void:
	var saved: Dictionary = CampaignWorld.frame_job_worst.duplicate()
	CampaignWorld.frame_job_worst["army"] = CampaignWorld.WORK_FRAME_LIMIT_USEC + 1
	if not CampaignWorld.job_admitted(["army", 17], 16000, 4000, false):
		_failure = "A historical whole-job maximum starved a fresh continued slice."
	if not CampaignWorld.job_admitted(["army", 17], 16000, 4000, true) or not CampaignWorld.job_admitted(["army", 17], 4000, 8000, true):
		_failure = "An affordable continuation was deferred after a completed prefix."
	if CampaignWorld.job_admitted(["army", 17], 3999, 4000, false):
		_failure = "A continuation started without its slice reservation."
	CampaignWorld.frame_job_worst = saved
	var saved_atomic: Dictionary = CampaignWorld.job_worst.duplicate()
	for kind: String in ["coin", "tturn"]:
		CampaignWorld.job_worst[kind] = CampaignWorld.WORK_FRAME_LIMIT_USEC + 1
		var header: Array = [kind, 17] if kind == "coin" else [kind, "t0", 17]
		if not CampaignWorld.job_admitted(header, 16000, 4000, false):
			_failure = "A historical maximum starved a native atomic head: " + kind
		if CampaignWorld.job_admitted(header, 3999, 4000, true):
			_failure = "A known heavy atomic head followed an earlier frame prefix: " + kind
		if not CampaignWorld.job_admitted(header, 0, 4000, false):
			_failure = "A fresh atomic head was starved by an exhausted estimate: " + kind
		CampaignWorld.job_worst[kind] = 500
		if not CampaignWorld.job_admitted(header, 3999, 4000, true):
			_failure = "An affordable atomic head was needlessly deferred: " + kind
		if CampaignWorld.job_admitted(header, 499, 4000, true):
			_failure = "An atomic head exceeded the remaining prefix allowance: " + kind
	CampaignWorld.job_worst = saved_atomic
	_check_budgeted_batching()

## Tiny scheduling probes use a separate Game instance, never the campaign world.
## They check production dispatch/commit/fences without economic inputs or waits.
class BudgetProbeJob:
	extends CampaignDayJob
	var events: Array = []
	var label: String = ""
	var suspend_once: bool = false
	var calls: int = 0
	var reentry_ok: bool = true
	var committed_observation: bool = false

	func _init(receipts: Array, name: String, suspend: bool = false) -> void:
		events = receipts
		label = name
		suspend_once = suspend

	func step(game: Variant) -> bool:
		calls += 1
		reentry_ok = reentry_ok and game._day_job_dispatch_busy() and CampaignWorld.work_slice(game, 4000) == 0
		events.append(label + str(calls))
		done = not suspend_once or calls > 1
		return done

	func observe(game: Variant) -> void:
		committed_observation = game._day_job_owner == null and not game._day_job_dispatch_busy() and not game._day_job_observation_blocked()
		events.append("after")

func _check_budgeted_batching() -> void:
	var saved_worst: Dictionary = CampaignWorld.job_worst.duplicate()
	var saved_total: Dictionary = CampaignWorld.job_total.duplicate(true)
	var saved_frame: Dictionary = CampaignWorld.frame_job_worst.duplicate()
	for mode: int in range(7):
		var game: Variant = Game.get_script().new()
		var events: Array = []
		var first: BudgetProbeJob = BudgetProbeJob.new(events, "a", mode == 1)
		var second: BudgetProbeJob = BudgetProbeJob.new(events, "b")
		game.world = {"seed": 9001, "work": [["budget_probe", 0, first], ["budget_probe", 0, second]]}
		if mode >= 5:
			game.world["work"].pop_back()   # a second caller queues its own cheap head
		game._save_pending = mode == 4
		var frame: int = Engine.get_process_frames()
		if mode == 2:
			first.after.append(first.observe.bind(game))
		if mode == 3:
			game._day_job_begin_frame(Time.get_ticks_usec())
			game._day_job_frame_started_usec = Time.get_ticks_usec() - CampaignWorld.WORK_FRAME_LIMIT_USEC
		var call_started_usec: int = Time.get_ticks_usec()
		var count: int = CampaignWorld.work_slice(game, 4000 if mode >= 5 else 16000)
		var valid: bool = first.reentry_ok and second.reentry_ok and Engine.get_process_frames() == frame
		match mode:
			0:
				valid = valid and count == 2 and events == ["a1", "b1"] and game._day_job_owner == null and game._day_job_frame_jobs == 2
			1:
				valid = valid and count == 1 and game._day_job_owner == first and game.world["work"][0][-1] == first
				valid = valid and CampaignWorld.work_slice(game, 16000) == 2 and events == ["a1", "a2", "b1"] and game._day_job_owner == null
			2:
				valid = valid and count == 1 and CampaignWorld.work_slice(game, 16000) == 0 and events == ["a1"]
				valid = valid and game._day_job_flush_actions() and first.committed_observation
				valid = valid and CampaignWorld.work_slice(game, 16000) == 1 and events == ["a1", "after", "b1"]
			3:
				valid = valid and count == 0 and first.calls == 0 and second.calls == 0
			4:
				valid = valid and count == 2 and game._day_job_owner == null and game._save_pending and game._day_job_fence_pending()
			5, 6:
				valid = valid and count == 1 and events == ["a1"] and game._day_job_owner == null
				game.world["work"].append(["budget_probe", 0, second])
				if mode == 5:
					# Two real 4000-us callers must share this same engine frame.
					valid = valid and CampaignWorld.work_slice(game, 4000) == 1
				else:
					# The time-advance work phase has its own invocation prefix.
					var run: Dictionary = {"phase": "work", "rng": CampaignWorld._rng(game.world),
						"work_budget_usec": 4000, "jobs_done": 0, "jobs": 1,
						"work_started": call_started_usec, "frame_started_usec": call_started_usec}
					valid = valid and CampaignWorld._time_part(game, run) and int(run["jobs_done"]) == 1
				valid = valid and events == ["a1", "b1"] and second.reentry_ok and game._day_job_owner == null \
					and game._day_job_frame_jobs == 2 and Engine.get_process_frames() == frame
		if not valid and _failure.is_empty():
			_failure = "Production budget/ownership/action-order probe failed, case %d: %s" % [mode, str(events)]
		game.free()
	CampaignWorld.job_worst = saved_worst
	CampaignWorld.job_total = saved_total
	CampaignWorld.frame_job_worst = saved_frame

func run(tree: SceneTree) -> int:
	_deadline = Time.get_ticks_usec() + WALL_USEC
	_check_admission()
	if not _failure.is_empty():
		printerr("ARMY SPLIT EQUIV FAIL: " + _failure)
		return 1
	Game.wait_save()
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
	_phase("generation")
	var fixture: NativeFixture = NativeFixture.new()
	fixture.hard_deadline = _deadline
	fixture._started_us = Time.get_ticks_usec()
	_fixture_ready = await fixture._setup_world(tree)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	_fixture_receipt = fixture._receipt.duplicate(true)
	if not _fixture_ready:
		_failure = fixture._reason if not fixture._reason.is_empty() else "Full frame fixture unavailable."
	Game._active_screen = "map"
	if _ok():
		_phase("warmup")
		_warmup_ready = await fixture._warmup(tree)
		if not _warmup_ready:
			_failure = fixture._reason
	_phase("preparation")
	if _ok():
		# Public native time advance schedules day 10, including the ten-day
		# supply checkpoint. The one-microsecond budget leaves its queue intact.
		Game.advance_time(1.0, false, 0, 1)
		if int(Game.world.get("last_day", -1)) != 10 or not is_equal_approx(Game.day, 10.0):
			_failure = "Native frame warmup did not reach the real day-10 queue."
		if not (Game.world.get("work", []) as Array).any(func(job: Array) -> bool: return job[0] == "arms_supply" and int(job[1]) == 10):
			_failure = "Native day 10 did not schedule its supply checkpoint."
		if _ok():
			_prime_supply()
			await _compare_day(tree)
	for kind: String in KINDS:
		if not _coverage.has(kind) and _failure == "": _failure = "Missing native job coverage: " + kind
		if not _held_by_kind.has(kind) and _failure == "": _failure = "No progressed ArmyDayJob retained across distinct frames for kind: " + kind
	if _held == 0 and _failure == "": _failure = "No continuation crossed an engine frame."
	if _failure == "" and (not _camp_atomic_paid or not _camp_continued_paid or not _camp_payroll_held):
		_failure = "Camp payroll lacked a real debit/home credit in both forks or a retained post-payment payroll checkpoint."
	_phase("cleanup")
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
	if not _ok():
		printerr("ARMY SPLIT EQUIV FAIL: " + _failure)
		return 1
	print("ARMY SPLIT EQUIV PASS: real day-10 native queue; all five kinds retained after progress; native camp wages and payroll hold; redraw/save progress; %d held frames; full ordered save state, RNG, counters, queue order and codec exact." % _held)
	return 0

func _phase(_label: String) -> void:
	pass

func _ok() -> bool:
	if _failure == "" and Time.get_ticks_usec() >= _deadline:
		_failure = "50-second deadline exceeded: incomplete, not a pass."
	return _failure == ""

func _drain_atomic() -> Array:
	var trace: Array = []
	var rng: RandomNumberGenerator = CampaignWorld._rng(Game.world)
	while _ok() and not Game.world.get("work", []).is_empty():
		var head: Array = Game.world["work"][0]
		trace.append(Game._serialize(head))
		if head[0] == "army_misc": _prime_camp()
		var camp_before: Dictionary = _camp_state() if head[0] == "army_misc" and _camp_id != "" else {}
		var supply_towns: Dictionary = _supply_receipts() if head[0] == "arms_supply" else {}
		CampaignWorld._run_job(Game, rng, false)
		Game.world["rng_state"] = str(rng.state)
		if not supply_towns.is_empty():
			var after_supply: Dictionary = _supply_receipts()
			var participants: int = 0
			for tid: String in supply_towns:
				if after_supply[tid] != supply_towns[tid]: participants += 1
			_native_counters["supply_towns_moved"] = participants
		if not camp_before.is_empty():
			if not _paid_camp(camp_before):
				_failure = "Native atomic camp job did not debit real camp coin and credit a home household."
			else:
				_camp_atomic_paid = true
	return trace

func _compare_day(tree: SceneTree) -> void:
	var before: Dictionary = Game._save_tree()
	# Reconstruct both branches identically, including native Unit/Item types.
	_restore(before)
	if not _ok(): return
	if var_to_bytes(Game._save_tree()) != var_to_bytes(before):
		_failure = "Fork restore changed the complete native snapshot."
		return
	var supply_before: int = int(Game.world.get("arms", {}).get("supply_moved", 0))
	var has_supply: bool = (Game.world["work"] as Array).any(func(job: Array) -> bool: return job[0] == "arms_supply")
	var expected_trace: Array = _drain_atomic()
	if not _ok(): return
	_native_counters["supply_moved"] = int(Game.world.get("arms", {}).get("supply_moved", 0)) - supply_before
	if has_supply and int(_native_counters["supply_moved"]) <= 0:
		_failure = "The real day-10 supply checkpoint moved no stock."
		return
	if has_supply and int(_native_counters.get("supply_towns_moved", 0)) < 3:
		_failure = "The real day-10 supply checkpoint involved fewer than three towns."
		return
	var expected: PackedByteArray = var_to_bytes(Game._save_tree())
	_restore(before)
	if not _ok(): return
	var trace: Array = []
	var day: float = Game.day
	var midnight: int = int(Game.world["last_day"])
	var tail: PackedByteArray = PackedByteArray()
	var tested_save: bool = _save_checked
	var queued_actions: bool = false
	var waiting_actions: bool = false
	var probe: Variant = CONTRACT_PROBE.new()
	var camp_before: Dictionary = {}
	_actions.clear()
	while _ok() and not Game.world.get("work", []).is_empty():
		var pending: bool = CampaignWorld.day_job_pending(Game)
		var head: Array = Game.world["work"][0]
		if not pending:
			trace.append(Game._serialize(head))
			if head[0] in KINDS:
				_coverage[head[0]] = int(_coverage.get(head[0], 0)) + 1
			if head[0] in SPLIT_KINDS:
				tail = var_to_bytes(Game._serialize((Game.world["work"] as Array).slice(1)))
			camp_before = _camp_state() if head[0] == "army_misc" else {}
			if head[0] in KINDS and not _directed_started.has(head[0]):
				var directed: HeldArmyJob = HeldArmyJob.new(Game, head)
				if head[0] == "army_misc" and _camp_id != "":
					directed.payroll_id = _camp_id
					directed.payroll_lair = Game.world["lairs"][_camp_id]
					directed.payroll_families = _camp_state()["families"]
				head.append(directed)
				directed.hold(Game)
				_directed_started[head[0]] = true
			if head[0] in SPLIT_KINDS:
				# Observe each native header at its own committed callback boundary.
				# Budget batching itself is checked independently below.
				if not head[-1] is CampaignDayJob:
					var worker: CampaignDayJob = CampaignWorld._new_day_job(Game, head)
					head.append(worker)
					worker.hold(Game)
				(head[-1] as CampaignDayJob).after.append(_queue_boundary)
		await tree.process_frame
		var resumed: CampaignDayJob = Game._day_job_owner if pending else null
		var yields_before: int = (resumed as ArmyDayJob).yields if resumed is ArmyDayJob else 0
		if pending:
			Game._process(1.0 / 60.0)
		elif head[0] in SPLIT_KINDS:
			if CampaignWorld.work_slice(Game, 4000) <= 0:
				_failure = "A reserved native job slice made no dispatch progress."
				break
		else:
			var rng: RandomNumberGenerator = CampaignWorld._rng(Game.world)
			CampaignWorld._run_job(Game, rng, false)
			Game.world["rng_state"] = str(rng.state)
		if resumed is ArmyDayJob:
			var run: ArmyDayJob = resumed as ArmyDayJob
			var identity: int = run.get_instance_id()
			var resumed_work: bool = run.done or run.yields > yields_before
			if _held_receipts.has(identity) and _held_receipts[identity]["owner"] == run and Engine.get_process_frames() > int(_held_receipts[identity]["frame"]) and resumed_work:
				_held_by_kind[String(run._header[0])] = true
			if not _camp_payroll_receipt.is_empty() and _camp_payroll_receipt["owner"] == run and Engine.get_process_frames() > int(_camp_payroll_receipt["frame"]) and yields_before >= int(_camp_payroll_receipt["yields"]) and resumed_work:
				_camp_payroll_held = true
		if head[0] == "army_misc" and not CampaignWorld.day_job_pending(Game) and not camp_before.is_empty():
			if not _paid_camp(camp_before):
				_failure = "Continued camp job did not debit real camp coin and credit a home household."
				break
			_camp_continued_paid = true
		if Game.day != day or int(Game.world["last_day"]) != midnight:
			_failure = "A daily effect crossed its original day."
			break
		if CampaignWorld.day_job_pending(Game):
			_held += 1
			if Game._day_job_owner is ArmyDayJob:
				var owner: ArmyDayJob = Game._day_job_owner as ArmyDayJob
				var identity: int = owner.get_instance_id()
				if owner.yields > 0 and String(owner._s["stage"]) != "open" and not _held_receipts.has(identity):
					_held_receipts[identity] = {"owner": owner, "frame": Engine.get_process_frames(), "kind": String(owner._header[0]), "boundary": owner.boundary}
				if owner is HeldArmyJob and owner.boundary == "Army.pay_units:loop":
					var payroll: HeldArmyJob = owner as HeldArmyJob
					if payroll.payroll_yielded and payroll.payroll_frame == Engine.get_process_frames() and float(payroll.payroll_lair["gold"]) < payroll.payroll_gold and payroll._purses() > payroll.payroll_purse:
						_camp_payroll_receipt = {"owner": owner, "frame": Engine.get_process_frames(), "yields": owner.yields}
			if not tree.paused:
				_failure = "Partial daily work lost the simulation hold."
				break
			if var_to_bytes(Game._serialize((Game.world["work"] as Array).slice(1))) != tail:
				_failure = "Queue tail changed during a retained continuation."
				break
			if not queued_actions:
				queued_actions = true
				waiting_actions = true
				CampaignWorld.defer_day_job_action(Game, _record.bind("first"))
				CampaignWorld.defer_day_job_action(Game, _record.bind("second"))
			if waiting_actions and not _actions.is_empty():
				_failure = "A deferred observer saw incomplete daily work."
				break
			if not tested_save:
				tested_save = true
				_save_checked = true
				var started: int = int(Game.save_stats()["started"])
				Game.save_game_async()
				if Game.save_game():
					_failure = "Mid-job synchronous save reported a completed write."
					break
				Game.wait_save()
				if int(Game.save_stats()["started"]) != started or Game._save_capture != null or not Game._save_pending:
					_failure = "Mid-job save captured partial state or lost its pending request."
					break

			var draw_problem: String = await probe.observe_hold(tree, _deadline)
			if draw_problem != "":
				_failure = draw_problem
				break
		elif waiting_actions or not Game._day_job_actions.is_empty():
			var problem: String = await probe.finish(tree, _deadline, "sync_save")
			if problem != "":
				_failure = problem
				break
			if waiting_actions and _actions != ["first", "second"]:
				_failure = "Deferred requests did not run once in arrival order."
				break
			waiting_actions = false
	if not _ok():
		probe.dispose()
		return
	if tree.paused:
		_failure = "Completed daily work did not release its hold."
		return
	if trace != expected_trace:
		_failure = "Original jobs or generated children changed order/count."
		return
	if var_to_bytes(Game._save_tree()) != expected:
		_failure = "Full ordered state differs from the unmodified atomic queue."
		return
	# Exercise the exact production persistence codec at the completed boundary.
	var complete: Dictionary = Game._save_tree()
	var parsed: Variant = JSON.parse_string(Game.save_text(complete))
	if not parsed is Dictionary:
		_failure = "Completed save codec was unreadable."
		return
	Game.restore_exact(parsed)
	_restore(parsed)
	if _ok() and var_to_bytes(Game._save_tree()) != expected:
		_failure = "Completed save/load codec changed full native state."

func _supply_receipts() -> Dictionary:
	var receipts: Dictionary = {}
	for tid: String in Game.world["towns"]:
		var stats: Dictionary = Game.world["towns"][tid].get("econ", {}).get("stats", {})
		receipts[tid] = [int(stats.get("military_supply_in", 0)),
			int(stats.get("military_supply_out", 0)), int(stats.get("military_supply_in_arrows", 0)),
			int(stats.get("military_supply_out_arrows", 0))]
	return receipts

## Observe the actual same-faction towns; never pool stocks or reset cursors.
func _prime_supply() -> void:
	var counts: Dictionary = {}
	for town: Dictionary in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var fid: String = String(town.get("faction", ""))
		if fid != "": counts[fid] = int(counts.get(fid, 0)) + 1
	var largest: int = 0
	for count: Variant in counts.values(): largest = maxi(largest, int(count))
	_native_counters["same_faction_towns"] = largest
	if largest < 3:
		_failure = "No native faction has three full-depth towns for supply."

## Select only an already registered and funded native camp at its real payday.
## No recruitment, money, food, inventory or population fields are changed.
func _prime_camp() -> void:
	_camp_id = ""
	var checked: int = 0
	var registered: int = 0
	var funded: int = 0
	var volunteers: int = 0
	var best: int = 0
	var ids: Array = Game.world.get("lairs", {}).keys()
	ids.sort()
	for lid: Variant in ids:
		var lair: Dictionary = Game.world["lairs"][lid]
		if String(lair.get("kind", "")) != "bandit_camp": continue
		checked += 1
		_camp_id = String(lid)
		var state: Dictionary = _camp_state()
		if state.is_empty(): continue
		var payable: int = int(state["payable"])
		registered += payable
		var enough: bool = payable >= 2 and float(state["gold"]) >= float(state["bill"])
		if enough:
			funded += 1
			if payable > best:
				best = payable
				_native_counters["selected_camp"] = String(lid)
		volunteers += _available_volunteers(lair)
	_camp_id = String(_native_counters.get("selected_camp", "")) if best > 0 else ""
	_native_counters.merge({"day": Game.day, "camps_checked": checked,
		"volunteers_available": volunteers, "soldiers_registered": registered,
		"payroll_funded": funded, "selected_payable": best}, true)

## Read-only count under People.draw_outlaw's genuine value/availability rules.
## Use existing registered persons and cohort slots, without sync/promote/draw.
func _available_volunteers(lair: Dictionary) -> int:
	var tids: Dictionary = {}
	for race: String in ["", "human"]:
		var nearest: String = ""
		var distance: float = INF
		for tid: String in Game.world["towns"]:
			var town: Dictionary = Game.world["towns"][tid]
			if not TownEcon.has_econ(town): continue
			if race != "" and String(TownEcon.culture_of(town["econ"]).get("race", "")) != race: continue
			var d: float = (town["pos"] as Vector2).distance_squared_to(lair["pos"])
			if d < distance:
				distance = d
				nearest = tid
		if nearest != "": tids[nearest] = true
	var total: int = 0
	var offer: Dictionary = {"pay_day": minf(float(Army.A()["wage"]["bandit"]), float(lair.get("gold", 0.0)) / 7.0), "food_days": 0.0}
	for tid: String in tids:
		var e: Dictionary = (Game.world["towns"][tid]["econ"] as Dictionary).duplicate(true)
		for family: Dictionary in e["fams"]:
			if bool(family.get("gone", false)) or bool(family.get("estate", false)) or Population.spare(family) <= 0: continue
			var jobs: Dictionary = Persons.work(e, family)
			var available: int = 0
			for person: Array in family.get("pp", []):
				if People.outlaw_value(e, family, person, jobs.get(int(person[0]), {}), "bandit", offer) > 0.0:
					available += 1
			var slots: int = Population.eligible_slots(e, family, float(e.get("day", 0)))
			if slots > 0:
				var current: float = 0.0
				if int(family.get("idle", 0)) <= 0:
					current = INF
					for key: Variant in family.get("jobs", {}): current = minf(current, float(e["biz"][int(key)]["wage"]))
					for key: Variant in family.get("cj", {}): current = minf(current, Barge.casual_wage(e, String(key)))
					if current == INF: current = 0.0
				if People.outlaw_value(e, family, [-1, 0, 0, 0.0, "", -1, 0], {"wage": current}, "bandit", offer) > 0.0:
					available += slots
			total += mini(available, Population.spare(family))
	return total

func _camp_state() -> Dictionary:
	var lair: Dictionary = Game.world.get("lairs", {}).get(_camp_id, {})
	if lair.is_empty():
		return {}
	var seen: Dictionary = {}
	var families: Array = []
	var purses: float = 0.0
	var payable: int = 0
	var bill: float = 0.0
	var men: Array = []
	var roll: Dictionary = Game.world.get("army", {}).get("roll", {})
	var bands: Array = [String(lair.get("resident", ""))]
	bands.append_array(Bandits.bands_of(Game, _camp_id))
	for wid: Variant in bands:
		var band: Dictionary = Game.world["warbands"].get(wid, {})
		for unit: Unit in band.get("units", []):
			var family: Dictionary = People.fam_of(Game.world["towns"].get(unit.home_town, {}), unit.family)
			if unit.dead or family.is_empty() or bool(family.get("gone", false)):
				continue
			if Persons.by_uid(family, unit.uid).is_empty() or not roll.has(str(unit.uid)):
				_failure = "Camp fixture soldier has no real bound home person."
				return {}
			payable += 1
			men.append(unit)
			var key: String = unit.home_town + "|" + str(unit.family)
			if not seen.has(key):
				seen[key] = true
				families.append(family)
				purses += float(family["purse"])
	var lo: int = Army.low_officer(men, "bandit")
	for unit: Unit in men: bill += Army.wage("bandit", unit.rank, lo, unit)
	return {"gold": float(lair.get("gold", 0.0)), "purses": purses, "payable": payable, "families": families, "bill": bill}

func _paid_camp(before: Dictionary) -> bool:
	var after: Dictionary = _camp_state()
	return not after.is_empty() and float(after["gold"]) < float(before["gold"]) and float(after["purses"]) > float(before["purses"])

func _queue_boundary() -> void:
	pass

func _record(value: String) -> void:
	_actions.append(value)

func _restore(d: Dictionary) -> void:
	# The native deserializer consumes its input; retain every reference snapshot.
	d = d.duplicate(true)
	Unit._next_uid = int(d["next_unit_uid"])
	Item._next_uid = int(d["next_item_uid"])
	Game.seed_value = int(d["seed"])
	Game.rng.seed = Game.seed_value
	Game.rng.state = str(d["rng_state"]).to_int()
	Game.day = float(d["day"])
	Game.gold = int(d["gold"])
	Game.company.clear()
	for record: Dictionary in d["company"]: Game.company.append(Unit.from_dict(record))
	Game.stash.clear()
	for record: Dictionary in d["stash"]: Game.stash.append(Item.from_dict(record))
	Game.squads = {}
	for key: Variant in d["squads"]: Game.squads[int(key)] = d["squads"][key]
	Game.rep = d["rep"].duplicate(true)
	Game.location = String(d["location"])
	Game.provisions = Food.stock_from_save(d["provisions"])
	Game.rations = d["rations"].duplicate(true)
	Game.food_clock = d["food_clock"].duplicate(true)
	Game.world = Game._deserialize(d["world"])
	Game.contract = Game._deserialize(d["contract"])
	WorldGen.use_world(Game.world)
	Sickness.use_world_deadliness(Game.world)
	Monsters.use_world(Game.world)
	TownEcon.gold_gone = float(d["gold_gone"])
	TownEcon.goods_lost = Game._deserialize(d["goods_lost"])
	if not HerdRaids.load_state(Game, String(d["raid_state"])):
		_failure = "Native off-screen raid state could not restore."
		return
	WarAI.load_runtime(Game.world, d["war_runtime"])
	# Non-economic continuation bookkeeping never belongs to a fork snapshot.
	Game._save_pending = false
	Game._autosave_day_pending = false
	Game._day_job_owner = null
	Game._day_job_dispatching = false
	Game._day_job_actions.clear()
	Game._day_job_observers.clear()
	Game._day_job_changed_pending = false
	Game._day_job_slice_frame = -1
	Game._day_job_quit_generation = -1
