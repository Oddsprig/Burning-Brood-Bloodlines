extends "res://tests/test_army_split_equiv.gd"
## One real day-1 prefix; compare its missing-army sweep with the frozen native
## body, then the indexed atomic path and retained production dispatcher.
## Reuse the existing full fixture and exact restore; no days 2-9 or new runner.

class SweepHold:
	extends "res://campaign/army_day_job.gd"
	var forced_once: bool = false
	var partial_ready: Callable = Callable()

	func _init(game: Variant, header: Array) -> void:
		super(game, header)

	func _checkpoint(label: String) -> void:
		# Require real native deaths on both sides of the retained checkpoint.
		if budgeted and not forced_once and label == "army_sweep/roll" \
				and partial_ready.is_valid() and bool(partial_ready.call()):
			_deadline_usec = 0
			forced_once = true
		await super._checkpoint(label)

func _original_sweep() -> void:
	var world: Dictionary = Game.world
	var here: Dictionary = {}
	for wid: Variant in world.get("warbands", {}):
		for unit: Unit in world["warbands"][wid]["units"]:
			if not unit.dead:
				here[str(unit.uid)] = true
			else:
				Horses.return_mount(Game, unit)
	for unit: Unit in CampaignWorld.mustering_units(world):
		here[str(unit.uid)] = true
	for unit: Unit in Prisoners.units(Game):
		here[str(unit.uid)] = true
	var roll: Dictionary = Army.state(world)["roll"]
	for key: Variant in roll.keys():
		if here.has(key): continue
		var rec: Array = roll[key]
		roll.erase(key)
		People.casualty_rec(Game, String(rec[0]), int(rec[1]), String(rec[3]), "dead", String(rec[2]), [], int(key))

func _sweep_deaths() -> int:
	var deaths: int = 0
	for tid: Variant in Game.world.get("towns", {}):
		var town: Dictionary = Game.world["towns"][tid]
		deaths += int(town.get("econ", {}).get("stats", {}).get("deaths", 0))
	return deaths

func _partial_sweep(roll_before: int, roll_after: int, deaths_before: int, deaths_after: int) -> bool:
	var entries: int = (Army.state(Game.world)["roll"] as Dictionary).size()
	var deaths: int = _sweep_deaths()
	return entries < roll_before and entries > roll_after and deaths > deaths_before and deaths < deaths_after

func _sweep_equal(expected: PackedByteArray, label: String) -> void:
	if _ok() and var_to_bytes(Game._save_tree()) != expected:
		_failure = label + " changed complete ordered native state, RNG, counters or queue tail."

func run(tree: SceneTree) -> int:
	_deadline = Time.get_ticks_usec() + WALL_USEC
	_failure = ""
	if tree == null or Game._save_capture != null or Game._save_task != -1 or Game._save_pending or not Game.world.is_empty():
		printerr("DAY1 SWEEP EQUIV FAIL: isolated fresh runner required.")
		return 1
	var old_process: bool = Game.is_processing()
	var old_screen: String = Game._active_screen
	var old_paused: bool = tree.paused
	var old_fps: int = Engine.max_fps
	var old_scale: float = Engine.time_scale
	var old_size: String = WorldGen.gen_size
	var old_span: int = CampaignWorld.presim_span_days
	var old_prof: bool = TownEcon.prof_on
	Game.set_process(false)
	Game._active_screen = "map"
	tree.paused = false
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	TownEcon.prof_on = false
	var fixture: NativeFixture = NativeFixture.new()
	fixture.hard_deadline = _deadline
	fixture._started_us = Time.get_ticks_usec()
	var ready: bool = await fixture._setup_world(tree)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	if not ready: _failure = fixture._reason if not fixture._reason.is_empty() else "Native frame fixture unavailable."
	if _ok():
		Game.advance_time(1.0, false, 0, 1)
		var rng: RandomNumberGenerator = CampaignWorld._rng(Game.world)
		var yielded_usec: int = Time.get_ticks_usec()
		while _ok() and not Game.world.get("work", []).is_empty() and Game.world["work"][0][0] != "army_sweep":
			CampaignWorld._run_job(Game, rng, false)
			Game.world["rng_state"] = str(rng.state)
			if Time.get_ticks_usec() - yielded_usec >= 50000:
				await tree.process_frame
				yielded_usec = Time.get_ticks_usec()
		if _ok() and (Game.world.get("work", []).is_empty() or Game.world["work"][0][0] != "army_sweep" or Game.day != 1.0):
			_failure = "Native public day 1 did not expose its army-sweep header."
	var before: Dictionary = {}
	var expected: PackedByteArray = PackedByteArray()
	var reference_usec: int = 0
	var indexed_usec: int = 0
	var missing_before: int = 0
	var roll_after: int = 0
	var deaths_before: int = 0
	var deaths_after: int = 0
	if _ok():
		missing_before = (Army.state(Game.world)["roll"] as Dictionary).size()
		if missing_before == 0: _failure = "No original roll entries: casualty coverage would be empty."
	if _ok():
		deaths_before = _sweep_deaths()
		before = Game._save_tree()
		(Game.world["work"] as Array).pop_front()
		var started_usec: int = Time.get_ticks_usec()
		_original_sweep()
		reference_usec = Time.get_ticks_usec() - started_usec
		expected = var_to_bytes(Game._save_tree())
		roll_after = (Army.state(Game.world)["roll"] as Dictionary).size()
		deaths_after = _sweep_deaths()
		if roll_after >= missing_before:
			_failure = "Frozen native sweep processed no missing roll entries."
		elif deaths_after - deaths_before < 2:
			_failure = "Frozen native sweep needs at least two actual casualties for partial-hold coverage."
	if _ok():
		_restore(before)
		_sweep_equal(var_to_bytes(before), "First fork restore")
	if _ok():
		var rng: RandomNumberGenerator = CampaignWorld._rng(Game.world)
		var started_usec: int = Time.get_ticks_usec()
		CampaignWorld._run_job(Game, rng, false)
		indexed_usec = Time.get_ticks_usec() - started_usec
		Game.world["rng_state"] = str(rng.state)
		_sweep_equal(expected, "Indexed atomic sweep")
	if _ok():
		_restore(before)
		_sweep_equal(var_to_bytes(before), "Second fork restore")
	var held_frames: int = 0
	var partial_seen: bool = false
	var worker: SweepHold = null
	var scope_before: Dictionary = TownSweep._scope
	if _ok():
		var head: Array = Game.world["work"][0]
		worker = SweepHold.new(Game, head)
		worker.partial_ready = _partial_sweep.bind(missing_before, roll_after, deaths_before, deaths_after)
		head.append(worker)
		worker.hold(Game)
		worker.after.append(_queue_boundary)
		_actions.clear()
		var tail: PackedByteArray = var_to_bytes(Game._serialize((Game.world["work"] as Array).slice(1)))
		while _ok() and CampaignWorld.day_job_pending(Game):
			await tree.process_frame
			if CampaignWorld.work_slice(Game, 4000) <= 0:
				_failure = "Reserved sweep slice made no dispatch progress."
				break
			if not is_same(TownSweep._scope, scope_before):
				_failure = "TownSweep scope escaped a synchronous chunk."
				break
			if CampaignWorld.day_job_pending(Game):
				held_frames += 1
				if not tree.paused or Game.day != 1.0 or var_to_bytes(Game._serialize((Game.world["work"] as Array).slice(1))) != tail:
					_failure = "Sweep lost its original day, tree hold or queue tail."
					break
				if worker.forced_once and not partial_seen:
					if not _partial_sweep(missing_before, roll_after, deaths_before, deaths_after):
						_failure = "Forced sweep hold did not retain a partial native casualty state."
						break
					partial_seen = true
					CampaignWorld.defer_day_job_action(Game, _record.bind("first"))
					CampaignWorld.defer_day_job_action(Game, _record.bind("second"))
				if not _actions.is_empty():
					_failure = "Deferred action observed a partial sweep."
					break
		if _ok() and (held_frames == 0 or not partial_seen or not worker.forced_once or not worker.done or tree.paused):
			_failure = "No progressed sweep owner completed across distinct real frames."
		# A completed slice may leave too little frame budget for callbacks.
		# Keep the committed queue fenced and retry within the existing deadline.
		while _ok() and not Game._day_job_actions.is_empty():
			await tree.process_frame
			Game._day_job_flush_actions()
		if _ok() and _actions != ["first", "second"]:
			_failure = "Deferred sweep actions lost their once-only order."
		_sweep_equal(expected, "Retained production sweep")
	if CampaignWorld.day_job_pending(Game) and worker != null:
		worker.after.clear()
		worker.release(Game)
		Game.world["work"] = []
	Game._day_job_owner = null
	Game._day_job_dispatching = false
	Game._day_job_actions.clear()
	Game._day_job_observers.clear()
	Game._day_job_changed_pending = false
	Game._save_pending = false
	Game._autosave_day_pending = false
	Game._active_screen = old_screen
	Game.set_process(old_process)
	tree.paused = old_paused
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	TownEcon.prof_on = old_prof
	if not _ok():
		printerr("DAY1 SWEEP EQUIV FAIL: " + _failure)
		return 1
	print("DAY1 SWEEP EQUIV PASS: original/indexed/continued full ordered state/RNG/queue exact; roll_before %d; native_ms %.3f; indexed_ms %.3f; held_frames %d; casualty_deaths %d; partial_hold %s" % [missing_before, float(reference_usec) / 1000.0, float(indexed_usec) / 1000.0, held_frames, deaths_after - deaths_before, str(partial_seen)])
	return 0
