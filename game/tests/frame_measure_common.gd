extends RefCounted
## Full profiler fixture shared by the measurement and enforcing frame tests.
## Native warmup covers days 1-9 only, then one mounted map runs days 10-15.
## The six-day window has no native fast-forward, remount or intermediate stop.

const FRAME_DELTA: float = 1.0 / 60.0
const FIRST_DAY: int = 10
const LAST_DAY: int = 15
const DAYS: int = LAST_DAY - FIRST_DAY + 1
const LIMIT_USEC: int = 16000
# Phase budgets are no-progress allowances, never total-time truncation points.
# Observed r6 A: load 8.0 s, days 1-9 warmup 22.0 s, two measured days 6.5 s.
# Six measured days project about 50 s in run(); skip unneeded import externally.
# The lead must cap the whole command below 60 s, including startup/shutdown.
const LOAD_USEC: int = 9000000
const WARMUP_USEC: int = 22000000
const MOUNT_USEC: int = 1000000
const MEASURE_USEC: int = 22000000
const CLEANUP_USEC: int = 1000000
const TARGET_USEC: int = 55000000
const WARMUP_YIELD_USEC: int = 50000
const STALL_FRAMES: int = 1200
const TOP_COUNT: int = 10
const MAP_SCRIPT: GDScript = preload("res://campaign/world_map.gd")
const REQUIRED: Array[String] = [
	"econ", "bday", "fam", "fam2", "tturn", "fturn", "coin", "movein",
	"migrate", "wed", "tmonth", "arms_town", "arms_supply"
]

# Simulation ends only after native jobs, fights and ordered callbacks finish.
# Full settlement additionally waits for native autosave capture/writing.
# No generation or simulation kernel is subtracted from either measurement.
var warmup_day_worst_usec: int = 0
var warmup_sim_usec: int = 0
var warmup_day_receipts: Array = []

class FrameDriver extends Node:
	var callback: Callable = Callable()

	func _process(_delta: float) -> void:
		callback.call()


## Time the native UI callbacks in this test only, including deferred layout/draw.
## The wrappers call each original exactly once with its original arguments.
class DiagnosticMap extends "res://campaign/world_map.gd":
	func _diagnostic(label: String, started: int) -> void:
		if Perf.has_method("diagnostic_label"):
			Perf.call("diagnostic_label", label, Time.get_ticks_usec() - started)

	func _refresh_trade_overlay() -> void:
		var started: int = Time.get_ticks_usec()
		super._refresh_trade_overlay()
		_diagnostic("Measure trade overlay refresh", started)

	func _settle_hud_layout() -> void:
		var started: int = Time.get_ticks_usec()
		super._settle_hud_layout()
		_diagnostic("Measure deferred HUD layout", started)

	func _layout_hud() -> void:
		var started: int = Time.get_ticks_usec()
		super._layout_hud()
		_diagnostic("Measure HUD layout", started)

	func _draw_overlay() -> void:
		var started: int = Time.get_ticks_usec()
		super._draw_overlay()
		_diagnostic("Measure overlay draw", started)

## Forward native diagnostics unchanged. Completion is observed AFTER _do_work:
## _run_job increments job_total, then calls record_us with the same label.
class FrameTrace extends PerformanceTracker:
	var recording: bool = false
	var job_max: Dictionary = {}
	var job_calls: Dictionary = {}
	var job_pending: Dictionary = {}
	var job_baseline: Dictionary = {}
	var phase: String = "world_load"
	var events: Array = []
	var pending: Dictionary = {}
	var seen: Dictionary = {}
	var kinds: Dictionary = {}
	var expected: Dictionary = {}
	var original_towns: Dictionary = {}
	var coverage_fail: Callable = Callable()
	var queued_kinds: Dictionary = {}
	var midnights: Dictionary = {}

	static func _diagnostic_head(job: Array) -> String:
		var words: PackedStringArray = PackedStringArray()
		for index: int in mini(5, job.size()):
			var value: Variant = job[index]
			words.append(str(value) if typeof(value) <= TYPE_STRING else "<state>")
		return "[" + ", ".join(words) + "]"

	func diagnostic_label(label: String, elapsed_us: int) -> void:
		if recording:
			frame_labels.append({"label": label, "us": elapsed_us, "overall": false})
	var background_scope: String = "<world>"
	var background_steps: int = 0
	# Diagnostic-only receipts; do not alter coverage or gate counters.
	var frame_labels: Array = []
	var slow_jobs: Array = []
	var native_pending: Dictionary = {}

	static func event_key(kind: String, scope: String, day: int) -> String:
		return "%s|%s|%d" % [kind, scope, day]

	func _expect(kind: String, scope: String, day: int) -> void:
		expected[event_key(kind, scope, day)] = true

	func snapshot_original_towns(receipts: Dictionary, first_day: int, last_day: int, on_failure: Callable) -> void:
		original_towns = receipts.duplicate(true)
		coverage_fail = on_failure
		# Fix every original town/day obligation before live filtering can shrink it.
		for tid: String in original_towns:
			for day: int in range(first_day, last_day + 1):
				for kind: String in ["econ", "bday", "fam", "fam2"]:
					_expect(kind, tid, day)

	func _midnight(day: int) -> void:
		if midnights.has(day):
			return
		midnights[day] = true
		var towns: Dictionary = Game.world["towns"]
		for tid: String in original_towns:
			if not towns.has(tid):
				coverage_fail.call("original town %s missing at measured midnight day %d" % [tid, day])
				continue
			var town: Dictionary = towns[tid]
			if not TownEcon.has_econ(town):
				coverage_fail.call("original town %s lost economy at measured midnight day %d" % [tid, day])
		var ids: Array = towns.keys()
		ids.sort()
		for index: int in ids.size():
			var tid: String = String(ids[index])
			var town: Dictionary = towns[tid]
			if not TownEcon.has_econ(town):
				continue
			for kind: String in ["econ", "bday", "fam", "fam2"]:
				_expect(kind, tid, day)
			if (day + index) % 7 == 0:
				_expect("tturn", tid, day)
			if (day + index) % 28 == 3:
				_expect("wed", tid, day)
			if (day + index * 7) % 30 == 0 and day > 0:
				_expect("tmonth", tid, day)
			if (day + absi(tid.hash())) % ArmsTrade.ARMORY_EVERY == 0:
				_expect("arms_town", tid, day)
		_expect("coin", "<world>", day)
		if day % 7 == 3:
			_expect("fturn", "<world>", day)
		if day % 30 == 15:
			_expect("movein", "<world>", day)
		if day % 7 == 5:
			_expect("migrate", "<world>", day)
		if day % ArmsTrade.SUPPLY_EVERY == 0:
			_expect("arms_supply", "<world>", day)
		# Also require every campaign job kind actually queued at this midnight.
		# This includes army, sickness, herds, census and native spawn work.
		for job: Array in (Game.world.get("work", []) as Array):
			queued_kinds[String(job[0])] = true

	func set_stage(stage: String) -> void:
		super.set_stage(stage)
		var work: Array = Game.world.get("work", [])
		if work.is_empty():
			return
		var job: Array = work[0]
		var kind: String = String(job[0])
		var label: String = String(CampaignWorld.WORK_LABELS.get(
			kind, kind.replace("_", " ").capitalize()))
		if stage != label:
			return
		var native_totals: Array = CampaignWorld.job_total.get(kind, [0, 0])
		native_pending = {"kind": kind, "label": label, "phase": phase,
			"head": _diagnostic_head(job),
			"before": int(native_totals[1]), "day": Game.day,
			"engine": Engine.get_process_frames()}
		# Native _run_job supplies the exact _do_work boundary duration below.
		# Outside measurement only these two cheap scalar receipts are retained.
		if not recording and kind not in ["coin", "tturn"]:
			return
		if kind in ["coin", "tturn"]:
			var target_totals: Array = CampaignWorld.job_total.get(kind, [0, 0])
			job_pending = {"kind": kind, "scope": String(job[1]) if kind == "tturn" else "<world>",
				"day": int(job[2]) if kind == "tturn" else int(job[1]),
				"before": int(target_totals[1]), "phase": phase}
		if not recording:
			return
		var scope: String = "<world>"
		var scheduled: int = -1
		if kind == "arms_town" and job.size() > 2:
			scope = String(job[2])
			scheduled = int(job[1])
		else:
			if job.size() > 1 and (job[1] is String or job[1] is StringName):
				scope = String(job[1])
			if kind in ["econ", "bday", "fam", "fam2", "tturn", "tmonth", "wed",
					"refresh", "census_t", "plots_t", "sick", "herds"] and job.size() > 2:
				if job[2] is int or job[2] is float:
					scheduled = int(job[2])
			elif kind in ["fturn", "coin", "movein", "migrate", "arms_supply",
					"feudal", "dragon_care", "dragon_care_pay"] and job.size() > 1:
				scheduled = int(job[1])
		var totals: Array = CampaignWorld.job_total.get(kind, [0, 0])
		pending = {"kind": kind, "scope": scope, "scheduled": scheduled,
			"day": int(floor(Game.day)), "label": label, "before": int(totals[1])}
		events.append(pending)

	func record_us(label: String, elapsed_us: int, overall: bool = false) -> void:
		super.record_us(label, elapsed_us, overall)
		if recording:
			frame_labels.append({"label": label, "us": elapsed_us, "overall": overall,
				"worker_receipt": label.begins_with("Autosave worker ")})
		if not overall and not native_pending.is_empty() and label == String(native_pending["label"]):
			var native_totals: Array = CampaignWorld.job_total.get(String(native_pending["kind"]), [0, 0])
			if int(native_totals[1]) == int(native_pending["before"]) + 1:
				native_pending["us"] = elapsed_us
				if elapsed_us > LIMIT_USEC:
					slow_jobs.append(native_pending)
				native_pending = {}
		if not overall and not job_pending.is_empty():
			var target_kind: String = String(job_pending["kind"])
			var native_label: String = String(CampaignWorld.WORK_LABELS[target_kind])
			var target_totals: Array = CampaignWorld.job_total.get(target_kind, [0, 0])
			if label == native_label and int(target_totals[1]) == int(job_pending["before"]) + 1:
				job_calls[target_kind] = int(job_calls.get(target_kind, 0)) + 1
				var previous: Dictionary = job_max.get(target_kind, {})
				if elapsed_us > int(previous.get("us", -1)):
					var row: Dictionary = job_pending.duplicate()
					row["us"] = elapsed_us
					job_max[target_kind] = row
				job_pending = {}
		if label == "Army battles":
			background_steps += 1
		if not recording:
			return
		if label == "Midnight bookkeeping":
			_midnight(int(Game.world.get("last_day", -1)))
		if not pending.is_empty():
			var kind: String = String(pending["kind"])
			var totals: Array = CampaignWorld.job_total.get(kind, [0, 0])
			if label == String(pending["label"]) and int(totals[1]) > int(pending["before"]):
				pending["us"] = elapsed_us
				var key: String = event_key(kind, String(pending["scope"]), int(pending["scheduled"]))
				seen[key] = int(seen.get(key, 0)) + 1
				kinds[kind] = int(kinds.get(kind, 0)) + 1
				pending = {}
			# A queued army_fight has the same label as a background fight.
			return
		if label == "Army battles":
			# Called before the map can advance across midnight. Save the event day.
			events.append({"kind": "background_fight", "scope": background_scope,
				"scheduled": -1, "day": int(floor(Game.day)), "us": elapsed_us})

var _started_us: int = 0
var _guard_phase: String = ""
var _guard_token: String = ""
var _guard_changed_us: int = 0
var _guard_frame: int = -1
var _guard_stagnant: int = 0
var _special_top: Dictionary = {}
var _load_us: int = 0
var _warmup_us: int = 0
var _mount_us: int = 0
var _measure_us: int = 0
var _map: Node2D = null
var _driver: FrameDriver = null
var _samples: PackedInt64Array = PackedInt64Array()
var _top: Array[Dictionary] = []
var _baseline: Dictionary = {}
var _covered: PackedStringArray = PackedStringArray()
var _frame_started: int = 0
var _engine_frame: int = 0
var _day_before: float = 0.0
var _midnight_before: int = 0
var _save_before: bool = false
var _over: int = 0
var _ticks: int = 0
var _reason: String = ""
var _receipt: Dictionary = {}
var _spikes: Array = []
var _game_usec: int = 0
var _map_usec: int = 0
var _memory_before: int = 0
var _objects_before: int = 0
var _save_state_before: Dictionary = {}

func measure(tree: SceneTree, enforce_gate: bool) -> int:
	_started_us = Time.get_ticks_usec()
	print("FRAME WINDOW %d-%d; native warmup 1-9; one continuous real-loop measurement" % [FIRST_DAY, LAST_DAY])
	_guard_phase = ""
	_special_top.clear()
	_samples.clear()
	_top.clear()
	_spikes.clear()
	_covered.clear()
	_reason = ""
	_ticks = 0
	_over = 0
	# Leave runner._ready; do not depend on a test-local callback to release awaits.
	var old_game_processing: bool = Game.is_processing()
	var old_perf_processing: bool = Perf.is_processing()
	var old_screen: String = String(Game.get("_active_screen"))
	var old_paused: bool = tree.paused
	var old_fps: int = Engine.max_fps
	var old_scale: float = Engine.time_scale
	var old_size: String = WorldGen.gen_size
	var old_span: int = CampaignWorld.presim_span_days
	var old_prof_on: bool = TownEcon.prof_on
	var old_perf_script: Script = Perf.get_script() as Script
	var old_perf_state: Dictionary = {}
	for property: Dictionary in Perf.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var key: String = String(property["name"])
			old_perf_state[key] = Perf.get(key)
	Game.set_process(false)
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	tree.paused = false
	await tree.process_frame
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	TownEcon.prof_on = false
	# Install before generation/warmup so first-use coin and town-turn spikes count.
	Perf.set_script(FrameTrace)
	Perf.set_process(old_perf_processing)
	Perf.set("job_baseline", _job_counts())
	var ready: bool = await _setup_world(tree)
	WorldGen.gen_size = old_size
	CampaignWorld.presim_span_days = old_span
	_load_us = Time.get_ticks_usec() - _started_us
	print("FRAME TIMING world_load_ms %.3f; wall_ms %.3f; towns %d; family_rows %d; households %d; people %d; businesses %d" % [
		float(_load_us) / 1000.0, _wall_ms(), int(_receipt.get("towns", 0)),
		int(_receipt.get("family_rows", 0)), int(_receipt.get("households", 0)),
		int(_receipt.get("people", 0)), int(_receipt.get("businesses", 0))])
	if not ready:
		_harness_fail("full profiler fixture unavailable")
	else:
		Game.set("_active_screen", "map")
		Perf.set("phase", "warmup")
		var warm_started: int = Time.get_ticks_usec()
		ready = await _warmup(tree)
		_warmup_us = Time.get_ticks_usec() - warm_started
		print("FRAME TIMING warmup_ms %.3f; wall_ms %.3f; day %.6f" % [
			float(_warmup_us) / 1000.0, _wall_ms(), Game.day])
	if ready:
		Perf.set("phase", "mount")
		var mount_started: int = Time.get_ticks_usec()
		_map = DiagnosticMap.new() as Node2D
		_map.set_process(false)
		_map.set("speed_mult", 1)
		_driver = FrameDriver.new()
		_driver.name = "FrameGateScheduler"
		_driver.process_mode = Node.PROCESS_MODE_ALWAYS
		_driver.process_priority = -2147483648
		_driver.set_process(false)
		_driver.callback = _drive_frame
		_progress_ok("mount", MOUNT_USEC, "queued")
		tree.root.add_child.call_deferred(_map)
		tree.root.add_child.call_deferred(_driver)
		await tree.process_frame
		_map.set_process(false)
		if not _mounted(tree):
			_harness_fail("map or scheduler failed to mount in the runner tree")
		else:
			_progress_ok("mount", MOUNT_USEC, "mounted")
			# Drain the map's initial deferred layout/redraw before opening the window.
			await tree.process_frame
			_mount_us = Time.get_ticks_usec() - mount_started
			print("FRAME TIMING map_mount_ms %.3f; wall_ms %.3f" % [
				float(_mount_us) / 1000.0, _wall_ms()])
			Perf.set("phase", "measured")
			var measure_started: int = Time.get_ticks_usec()
			await _measure(tree)
			_measure_us = Time.get_ticks_usec() - measure_started
	if _driver != null:
		_driver.set_process(false)
	if Perf.get_script() == FrameTrace:
		Perf.set("recording", false)
	if not _samples.is_empty():
		_validate_coverage()
	if _samples.size() < TOP_COUNT:
		_harness_fail("ten complete measured frame samples required")
	_validate_job_receipts()
	# Report even a setup/mount/stall failure; unavailable samples are explicit.
	var p99_ms: float = _report()
	_report_job_max()
	var gate_worst: int = 0
	if not _samples.is_empty():
		gate_worst = int(_top[0]["us"])
	var job_max: Dictionary = Perf.get("job_max")
	for kind: String in ["coin", "tturn"]:
		var row: Dictionary = job_max.get(kind, {})
		gate_worst = maxi(gate_worst, int(row.get("us", 0)))
	if _map != null:
		_map.queue_free()
		_map = null
	if _driver != null:
		_driver.queue_free()
		_driver = null
	# A healthy measured window has already settled all saves. For an interrupted
	# run retire an existing capture/writer only while native progress continues.
	Perf.set("phase", "cleanup")
	while _save_inflight():
		if not _progress_ok("cleanup", CLEANUP_USEC, _progress_token()):
			break
		Game._process(FRAME_DELTA)
		await tree.process_frame
	if Time.get_ticks_usec() - _started_us >= TARGET_USEC:
		_harness_fail("completed run exceeded 55 s wall target; wall_ms %.3f" % _wall_ms())
	# Emit classifications only after SUMMARY, WORST and JOB MAX, even on failure.
	if not _reason.is_empty():
		printerr("FAIL FRAME HARNESS: %s; day %.6f; frames %d; wall_ms %.3f" % [
			_reason, Game.day, _samples.size(), _wall_ms()])
	# Only a complete, valid harness run earns a gate verdict.
	if _reason.is_empty():
		if gate_worst <= LIMIT_USEC:
			print("FRAME GATE: MET worst %.3f ms" % (float(gate_worst) / 1000.0))
		else:
			print("FRAME GATE: NOT MET worst %.3f ms; frames_over_16ms %d; p99 %.3f ms" % [
				float(gate_worst) / 1000.0, _over, p99_ms])
	if enforce_gate and gate_worst > LIMIT_USEC:
		printerr("FAIL FRAME GATE: worst %.3f ms > 16; frames_over_16ms %d; includes whole-run coin/tturn" % [
			float(gate_worst) / 1000.0, _over])
	Perf.set_script(old_perf_script)
	for key: String in old_perf_state:
		Perf.set(key, old_perf_state[key])
	Perf.set_process(old_perf_processing)
	Game.set("_active_screen", old_screen)
	Game.set_process(old_game_processing)
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	tree.paused = old_paused
	TownEcon.prof_on = old_prof_on
	print("FRAME TIMING total_ms %.3f; world_load_ms %.3f; warmup_ms %.3f; map_mount_ms %.3f; measured_ms %.3f" % [
		_wall_ms(), float(_load_us) / 1000.0, float(_warmup_us) / 1000.0,
		float(_mount_us) / 1000.0, float(_measure_us) / 1000.0])
	return 0 if _reason.is_empty() and (not enforce_gate or gate_worst <= LIMIT_USEC) else 1

func _wall_ms() -> float:
	return float(Time.get_ticks_usec() - _started_us) / 1000.0

func _setup_world(tree: SceneTree) -> bool:
	if _save_inflight() or EconGen.town_scale() < 1.0:
		return false
	var data: Dictionary = TownEcon.data()
	var keep: Array = data["families_by_size"]
	data["families_by_size"] = [150, 150, 150, 150, 150]
	# Same native generation/RNG as Game.new_game(9001), with bounded yields.
	var generation: Dictionary = Game.new_game_begin(9001)
	while not Game.new_game_slice(generation, 4000):
		var token: String = "%.9f|%d|%d|%d|%d" % [
			WorldPresim.generation_progress(generation), int(generation.get("phase", -1)),
			int(generation.get("i", -1)), int(generation.get("band_i", -1)),
			(Game.world.get("work", []) as Array).size()]
		if not _progress_ok("world_load", LOAD_USEC, token):
			data["families_by_size"] = keep
			return false
		await tree.process_frame
	Game.new_game_finalize()
	data["families_by_size"] = keep
	var world: Dictionary = Game.world
	# Exact profiler initial-force fixture. Every later native spawn is retained.
	for wid: Variant in (world["warbands"] as Dictionary).keys():
		CampaignWorld.remove_warband(Game, String(wid))
	world["work"] = []
	world["party"]["safe_until"] = 1.0e9
	var ids: Array = (world["towns"] as Dictionary).keys()
	ids.sort()
	if ids.is_empty():
		return false
	var copied: int = 0
	while (world["towns"] as Dictionary).size() < 20:
		if not _progress_ok("world_load", LOAD_USEC, "fallback|%d" % copied):
			return false
		var source: Dictionary = world["towns"][ids[copied % ids.size()]]
		var town: Dictionary = {}
		for key: Variant in source:
			if key not in ["econ", "shop", "recruits", "contracts"]:
				town[key] = source[key]
		town["id"] = "tx%d" % copied
		town["name"] = "%s Minor" % source["name"]
		town["pos"] = (source["pos"] as Vector2) + Vector2(30, 30)
		town["shop"] = []
		town["recruits"] = []
		town["contracts"] = []
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 77 + copied
		data["families_by_size"] = [150, 150, 150, 150, 150]
		EconGen.generate(world, town, rng)
		data["families_by_size"] = keep
		world["towns"][town["id"]] = town
		copied += 1
	var families: int = 0
	var households: int = 0
	var people: int = 0
	var businesses: int = 0
	var town_receipts: Dictionary = {}
	for tid: String in world["towns"]:
		var econ: Dictionary = world["towns"][tid].get("econ", {})
		if econ.is_empty():
			return false
		var fams: Array = econ["fams"]
		var homes: int = 0
		var population: int = 0
		var shops: int = (econ.get("biz", []) as Array).size()
		for family: Dictionary in fams:
			if bool(family.get("estate", false)):
				continue
			homes += Population.households(family)
			population += Families.people(family)
		if fams.size() < 24 or homes < 135 * Population.INITIAL_SCALE or population <= homes or shops == 0:
			return false
		families += fams.size() - 1
		households += homes
		people += population
		businesses += shops
		town_receipts[tid] = {"family_rows": fams.size() - 1,
			"households": homes, "people": population, "businesses": shops}
	_receipt = {"towns": (world["towns"] as Dictionary).size(), "family_rows": families,
		"households": households, "people": people, "businesses": businesses}
	# Retain immutable scalar depth receipts for every original town.
	_receipt["per_town"] = town_receipts
	return (world["towns"] as Dictionary).size() >= 27 and families >= 621

func _warmup(tree: SceneTree) -> bool:
	# No mounted map/HUD. Use the native public day API, not assignments to day,
	# queue_day, do_job, or a reduced economy. advance_time runs wages, healing,
	# meals and CampaignWorld.on_time (movement, midnight and all job queues).
	# This phase has no mounted map/FrameDriver. Budget zero uses native work.
	# The mounted measured phase still calls the budgeted map loop unchanged.
	warmup_day_worst_usec = 0
	warmup_sim_usec = 0
	warmup_day_receipts.clear()
	Game.world["party"]["waiting"] = false
	var yielded_us: int = Time.get_ticks_usec()
	for day: int in range(1, FIRST_DAY):
		var day_started_usec: int = Time.get_ticks_usec()
		if not _progress_ok("warmup", WARMUP_USEC, _progress_token()):
			return false
		Game.advance_time(1.0, false, 0, 0)
		var sim_done_usec: int = Time.get_ticks_usec() if _warmup_sim_settled() else 0
		while not _settled():
			if sim_done_usec == 0 and _warmup_sim_settled():
				sim_done_usec = Time.get_ticks_usec()
			Game._process(FRAME_DELTA)
			if not tree.paused:
				if CampaignWorld.work_slice(Game, 0) > 0:
					Game.changed.emit()
			# Tight native slices avoid hundreds of map/HUD frames per warmup day.
			# Yield periodically for engine timers and worker completion.
			# Do not busy-spin between native worker completions. No queued work
			# is omitted: this branch only yields when capture/jobs/fights are done.
			var writer_only: bool = not (Game.get("_save_capture") is Object) \
				and int(Game.get("_save_task")) != -1 \
				and (Game.world.get("work", []) as Array).is_empty() \
				and (Game.world.get("fight_work", []) as Array).is_empty()
			if writer_only or Time.get_ticks_usec() - yielded_us >= WARMUP_YIELD_USEC:
				await tree.process_frame
				yielded_us = Time.get_ticks_usec()
				if not _progress_ok("warmup", WARMUP_USEC, _progress_token()):
					return false
		if int(Game.world.get("last_day", -1)) != day or not is_equal_approx(Game.day, float(day)):
			_reason = "native warmup calendar did not advance exactly to day %d" % day
			return false
		var settled_usec: int = Time.get_ticks_usec()
		if sim_done_usec == 0:
			sim_done_usec = settled_usec
		var sim_usec: int = sim_done_usec - day_started_usec
		warmup_day_worst_usec = maxi(warmup_day_worst_usec, sim_usec)
		warmup_sim_usec += sim_usec
		warmup_day_receipts.append({"day": day, "sim_usec": sim_usec, "settled_usec": settled_usec - day_started_usec})
		print("FRAME DAY TIMING day %d; simulation_ms %.3f; settled_ms %.3f; post_sim_save_ms %.3f" % [day, float(sim_usec) / 1000.0, float(settled_usec - day_started_usec) / 1000.0, float(settled_usec - sim_done_usec) / 1000.0])
		print("FRAME PROGRESS day %d; phase warmup; wall_ms %.3f; frames 0" % [day, _wall_ms()])
	return true

func _warmup_sim_settled() -> bool:
	return (Game.world.get("work", []) as Array).is_empty() \
		and (Game.world.get("fight_work", []) as Array).is_empty() \
		and not Game._day_job_transaction_active() and Game._day_job_actions.is_empty()

func _mounted(tree: SceneTree) -> bool:
	return _map != null and _map.is_inside_tree() and _map.get_tree() == tree \
		and _driver != null and _driver.is_inside_tree() and _driver.get_tree() == tree \
		and Game.is_inside_tree() and Game.get_tree() == tree

func _measure(tree: SceneTree) -> void:
	# Use the fixture's saved IDs, including any town lost during native warmup.
	Perf.call("snapshot_original_towns", _receipt["per_town"], FIRST_DAY, LAST_DAY, _harness_fail)
	_baseline = _job_counts()
	Perf.set("recording", true)
	_driver.set_process(true)
	Game.world["party"]["waiting"] = true
	var previous_ticks: int = _ticks
	var last_day: int = FIRST_DAY - 1
	var phase_started: int = Time.get_ticks_usec()
	_open_frame(phase_started)
	while true:
		# Closing at the NEXT engine boundary includes deferred HUD/redraw and
		# the engine tail plus intervening physics. No final deferred tail is lost.
		await tree.process_frame
		var boundary_us: int = Time.get_ticks_usec()
		_close_frame(boundary_us)
		if not _mounted(tree) or not _driver.is_processing():
			_reason = "map or active scheduler left the runner tree"
			break
		if _ticks != previous_ticks + 1 or Engine.get_process_frames() != _engine_frame + 1:
			_reason = "scheduler must tick once in every consecutive engine frame"
			break
		previous_ticks = _ticks
		var day_now: int = int(Game.world.get("last_day", -1))
		if day_now > last_day:
			print("FRAME PROGRESS day %d; phase measured; wall_ms %.3f; measured_ms %.3f; frames %d; pending %d" % [
				day_now, _wall_ms(), float(boundary_us - phase_started) / 1000.0,
				_samples.size(), (Game.world.get("work", []) as Array).size()])
			last_day = day_now
		# Accept final settlement BEFORE any stall check. At day 15 stopping the
		# wait order is intentional; queued jobs and save slices remain progress.
		if day_now >= LAST_DAY and _settled():
			if day_now != LAST_DAY:
				_reason = "calendar advanced past final measured day"
			break
		if not _progress_ok("measured", MEASURE_USEC, _progress_token()):
			break
		# Use the SAME boundary timestamp: bookkeeping/progress overhead is
		# conservatively charged to the next sample, with no gap between samples.
		_open_frame(boundary_us)
	_driver.set_process(false)
	Perf.set("recording", false)

func _open_frame(boundary_us: int) -> void:
	Perf.set("events", [])
	Perf.set("pending", {})
	Perf.set("frame_labels", [])
	_game_usec = 0
	_map_usec = 0
	_memory_before = int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_objects_before = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_save_state_before = _diagnostic_save_state()
	_frame_started = boundary_us
	_engine_frame = Engine.get_process_frames()
	_day_before = Game.day
	_midnight_before = int(Game.world.get("last_day", -1))
	_save_before = _save_inflight()

func _drive_frame() -> void:
	_ticks += 1
	var fights: Array = Game.world.get("fight_work", [])
	Perf.set("background_scope", String(fights[0]) if not fights.is_empty() else "<world>")
	# Exact native player path once per actual engine frame; no duplicate
	# automatic Game/map processing, altered job budget, or skipped idle frame.
	var game_started: int = Time.get_ticks_usec()
	Game._process(FRAME_DELTA)
	_game_usec = Time.get_ticks_usec() - game_started
	var map_started: int = Time.get_ticks_usec()
	_map.call("_process", FRAME_DELTA)
	_map_usec = Time.get_ticks_usec() - map_started
	if int(Game.world.get("last_day", -1)) >= LAST_DAY:
		Game.world["party"]["waiting"] = false

func _close_frame(boundary_us: int) -> void:
	var elapsed: int = boundary_us - _frame_started
	_samples.append(elapsed)
	if elapsed > LIMIT_USEC:
		_over += 1
	var keep_overall: bool = _top.size() < TOP_COUNT
	if not keep_overall:
		keep_overall = elapsed > int(_top[TOP_COUNT - 1]["us"])
	var events: Array = Perf.get("events")
	var targets: PackedStringArray = PackedStringArray()
	# Keep each target's worst frame even when it misses the overall top ten.
	for event: Dictionary in events:
		var kind: String = String(event["kind"])
		if kind in ["coin", "tturn"] and not targets.has(kind):
			var previous: Dictionary = _special_top.get(kind, {})
			if elapsed > int(previous.get("us", -1)):
				targets.append(kind)
	if elapsed <= LIMIT_USEC and not keep_overall and targets.is_empty():
		return
	# Allocate diagnostic rows only when retained, keeping idle-frame cost low.
	var row: Dictionary = {"us": elapsed, "frame": _samples.size(), "engine": _engine_frame,
		"before": _day_before, "after": Game.day, "midnight": _midnight_before,
		"last_day": int(Game.world.get("last_day", -1)), "events": events,
		"save": _save_before or _save_inflight(), "labels": Perf.get("frame_labels"),
		"game_us": _game_usec, "map_us": _map_usec,
		"outside_driver_us": maxi(0, elapsed - _game_usec - _map_usec),
		"save_before": _save_state_before, "save_after": _diagnostic_save_state(),
		"memory_delta": int(Performance.get_monitor(Performance.MEMORY_STATIC)) - _memory_before,
		"objects_delta": int(Performance.get_monitor(Performance.OBJECT_COUNT)) - _objects_before}
	if elapsed > LIMIT_USEC:
		_spikes.append(row)
	for kind: String in targets:
		_special_top[kind] = row
	if not keep_overall:
		return
	var slot: int = 0
	while slot < _top.size() and int(_top[slot]["us"]) >= elapsed:
		slot += 1
	_top.insert(slot, row)
	if _top.size() > TOP_COUNT:
		_top.pop_back()

func _job_counts() -> Dictionary:
	var counts: Dictionary = {}
	for kind: String in CampaignWorld.job_total:
		var totals: Array = CampaignWorld.job_total[kind]
		counts[kind] = int(totals[1])
	return counts

func _validate_coverage() -> void:
	var after: Dictionary = _job_counts()
	var observed: Dictionary = Perf.get("kinds")
	var seen: Dictionary = Perf.get("seen")
	var expected: Dictionary = Perf.get("expected")
	var midnights: Dictionary = Perf.get("midnights")
	var required_kinds: Dictionary = (Perf.get("queued_kinds") as Dictionary).duplicate()
	for kind: String in REQUIRED:
		required_kinds[kind] = true
	for kind: String in after:
		var delta: int = int(after[kind]) - int(_baseline.get(kind, 0))
		if delta > 0 and int(observed.get(kind, 0)) == delta:
			_covered.append(kind)
	_covered.sort()
	var missing: PackedStringArray = PackedStringArray()
	for kind: String in required_kinds:
		var delta: int = int(after.get(kind, 0)) - int(_baseline.get(kind, 0))
		if delta <= 0 or int(observed.get(kind, 0)) != delta:
			missing.append("type " + kind)
	for day: int in range(FIRST_DAY, LAST_DAY + 1):
		if not midnights.has(day):
			missing.append("midnight %d" % day)
	for key: String in expected:
		if int(seen.get(key, 0)) <= 0:
			missing.append("scheduled " + key)
	var towns: Dictionary = Game.world["towns"]
	var originals: Dictionary = _receipt["per_town"]
	# Validate the union so vanished originals cannot escape final cursor checks.
	var town_ids: Dictionary = originals.duplicate()
	for tid: String in towns:
		town_ids[tid] = true
	for tid: String in town_ids:
		if not towns.has(tid):
			missing.append("original town " + tid)
			continue
		var town: Dictionary = towns[tid]
		if originals.has(tid) and not TownEcon.has_econ(town):
			missing.append("original town economy " + tid)
			continue
		var econ: Dictionary = town.get("econ", {})
		if not econ.is_empty() and (int(econ.get("day", -1)) < LAST_DAY \
				or int(econ.get("wage_day", -1)) < LAST_DAY or int(econ.get("bday", -1)) < LAST_DAY):
			missing.append("town daily/wage/books cursor " + tid)
	if int(Game.world.get("last_day", -1)) != LAST_DAY or _samples.is_empty():
		missing.append("six complete measured midnights")
	if not missing.is_empty():
		var message: String = "missing economy coverage: " + "; ".join(missing.slice(0, 12))
		_harness_fail(message)
	print("FRAME COVERAGE completed events %d; scheduled town/day receipts %d; midnights %d; missing %d" % [
		_sum_counts(observed), expected.size(), midnights.size(), missing.size()])

func _sum_counts(counts: Dictionary) -> int:
	var total: int = 0
	for value: Variant in counts.values():
		total += int(value)
	return total

func _save_inflight() -> bool:
	return Game.get("_save_capture") != null or int(Game.get("_save_task")) != -1

func _settled() -> bool:
	return (Game.world.get("work", []) as Array).is_empty() \
		and (Game.world.get("fight_work", []) as Array).is_empty() \
		and not _save_inflight() and not bool(Game.get("_save_pending")) \
		and not bool(Game.get("_autosave_day_pending"))

func _event_text(event: Dictionary) -> String:
	var scope: String = String(event["scope"])
	var towns: Dictionary = Game.world["towns"]
	var town_text: String = "<world>"
	if towns.has(scope):
		town_text = "%s (%s)" % [scope, String(towns[scope].get("name", scope))]
	elif scope != "<world>":
		town_text = "<world>; scope " + scope
	var scheduled: String = ""
	if int(event["scheduled"]) >= 0:
		scheduled = "; scheduled day %d" % int(event["scheduled"])
	return "%s day %d%s town %s" % [
		String(event["kind"]), int(event["day"]), scheduled, town_text]

func _report() -> float:
	var sorted: PackedInt64Array = _samples.duplicate()
	sorted.sort()
	var count: int = sorted.size()
	var p99_index: int = maxi(0, ceili(float(count) * 0.99) - 1)
	var worst_ms: float = NAN
	var p99_ms: float = NAN
	if count > 0:
		worst_ms = float(sorted[count - 1]) / 1000.0
		p99_ms = float(sorted[p99_index]) / 1000.0
	var days: int = clampi(int(Game.world.get("last_day", FIRST_DAY - 1)) - FIRST_DAY + 1, 0, DAYS)
	print("FRAME SUMMARY frames %d; worst %.3f ms; p99 %.3f ms; frames_over_16ms %d; days %d; jobs_covered %s" % [
		count, worst_ms, p99_ms,
		_over, days, ",".join(_covered)])
	for rank: int in TOP_COUNT:
		if rank < _top.size():
			_report_frame("FRAME WORST %02d" % (rank + 1), _top[rank])
		else:
			print("FRAME WORST %02d unavailable; no completed measured frame" % (rank + 1))
	for kind: String in ["coin", "tturn"]:
		if _special_top.has(kind):
			var row: Dictionary = _special_top[kind]
			_report_frame("FRAME WORST JOB " + kind, row)
		else:
			print("FRAME WORST JOB %s unavailable; no completed matching measured frame" % kind)
	_report_spikes()
	return p99_ms

func _report_frame(prefix: String, row: Dictionary) -> void:
	var contexts: PackedStringArray = PackedStringArray()
	if int(row["last_day"]) > int(row["midnight"]):
		contexts.append("midnight day %d town <world>" % int(row["last_day"]))
	for event: Dictionary in row["events"]:
		contexts.append(_event_text(event))
	if bool(row["save"]):
		contexts.append("autosave capture/writer")
	if contexts.is_empty():
		contexts.append("no queued job; native clock/movement/map/HUD/deferred work")
	print("%s frame %d engine %d; %.3f ms; day %.6f -> %.6f; jobs %s" % [
		prefix, int(row["frame"]), int(row["engine"]), float(row["us"]) / 1000.0,
		float(row["before"]), float(row["after"]), " | ".join(contexts)])

func _harness_fail(message: String) -> void:
	_reason = message if _reason.is_empty() else _reason + "; " + message

func _progress_token() -> String:
	var jobs: int = _sum_counts(_job_counts())
	var capture: Object = Game.get("_save_capture") as Object
	var slices: int = -1 if capture == null else int(capture.get("slices"))
	return "%.9f|%d|%d|%d|%d|%d|%d|%d" % [
		Game.day, int(Game.world.get("last_day", -1)),
		(Game.world.get("work", []) as Array).size(),
		(Game.world.get("fight_work", []) as Array).size(),
		jobs, slices, int(Game.get("_save_task")), int(Perf.get("background_steps"))]

func _progress_ok(phase: String, budget_us: int, token: String) -> bool:
	var now: int = Time.get_ticks_usec()
	var frame: int = Engine.get_process_frames()
	if phase != _guard_phase or token != _guard_token:
		_guard_phase = phase
		_guard_token = token
		_guard_changed_us = now
		_guard_frame = frame
		_guard_stagnant = 0
		return true
	if frame != _guard_frame:
		_guard_stagnant += 1
		_guard_frame = frame
	if _guard_stagnant >= STALL_FRAMES or now - _guard_changed_us >= budget_us:
		_harness_fail("no progress phase %s; days/work stopped advancing for %d frames; idle_ms %.3f; allowance_ms %.3f" % [
			phase, _guard_stagnant, float(now - _guard_changed_us) / 1000.0, float(budget_us) / 1000.0])
		return false
	return true

func _validate_job_receipts() -> void:
	var calls: Dictionary = Perf.get("job_calls")
	var baseline: Dictionary = Perf.get("job_baseline")
	var after: Dictionary = _job_counts()
	for kind: String in ["coin", "tturn"]:
		var expected: int = int(after.get(kind, 0)) - int(baseline.get(kind, 0))
		if expected <= 0 or int(calls.get(kind, 0)) != expected:
			_harness_fail("whole-run %s timing receipts %d != native calls %d" % [
				kind, int(calls.get(kind, 0)), expected])

func _report_job_max() -> void:
	var maxima: Dictionary = Perf.get("job_max")
	var coin: Dictionary = maxima.get("coin", {})
	var tturn: Dictionary = maxima.get("tturn", {})
	print("FRAME JOB MAX coin %.3f ms day %d; tturn %.3f ms day %d town %s" % [
		float(coin.get("us", NAN)) / 1000.0, int(coin.get("day", -1)),
		float(tturn.get("us", NAN)) / 1000.0, int(tturn.get("day", -1)),
		String(tturn.get("scope", "<unavailable>"))])
	var calls: Dictionary = Perf.get("job_calls")
	print("FRAME JOB RECEIPTS coin %d phase %s; tturn %d phase %s; window %d-%d" % [
		int(calls.get("coin", 0)), String(coin.get("phase", "unavailable")),
		int(calls.get("tturn", 0)), String(tturn.get("phase", "unavailable")), FIRST_DAY, LAST_DAY])
	print("FRAME BUDGET load_ms %d; warmup_ms %d; mount_ms %d; measured_ms %d; cleanup_ms %d; target_ms %d; budgets apply to no-progress gaps" % [
		LOAD_USEC / 1000, WARMUP_USEC / 1000, MOUNT_USEC / 1000,
		MEASURE_USEC / 1000, CLEANUP_USEC / 1000, TARGET_USEC / 1000])


## Capture/writer presence is correlation, not a claim that a worker used the CPU.
func _diagnostic_save_state() -> Dictionary:
	var capture: Object = Game.get("_save_capture") as Object
	return {"capture": capture != null, "capture_slices": -1 if capture == null else int(capture.get("slices")),
		"writer": int(Game.get("_save_task")), "pending": bool(Game.get("_save_pending")),
		"autosave_pending": bool(Game.get("_autosave_day_pending"))}

## Print after measurement: no stdout work is introduced into a timed frame.
## Exact combinations partition the over-limit set; kind membership overlaps.
func _report_spikes() -> void:
	var classes: Dictionary = {}
	var members: Dictionary = {}
	for row: Dictionary in _spikes:
		var kinds: PackedStringArray = PackedStringArray()
		var timed: PackedStringArray = PackedStringArray()
		for event: Dictionary in row["events"]:
			var kind: String = String(event["kind"])
			if not kinds.has(kind): kinds.append(kind)
			timed.append("%s %.3f ms" % [_event_text(event), float(event.get("us", 0)) / 1000.0])
		kinds.sort()
		var key: String = "+".join(kinds) if not kinds.is_empty() else "no_queued_job"
		var previous: Array = classes.get(key, [0, 0])
		classes[key] = [int(previous[0]) + 1, maxi(int(previous[1]), int(row["us"]))]
		for kind: String in kinds:
			var member: Array = members.get(kind, [0, 0])
			members[kind] = [int(member[0]) + 1, maxi(int(member[1]), int(row["us"]))]
		_report_frame("FRAME OVER", row)
		print("FRAME DETAIL frame %d; class %s; Game._process %.3f ms; map._process %.3f ms; outside_driver %.3f ms; memory_delta %d; objects_delta %d; save_before %s; save_after %s; native %s" % [
			int(row["frame"]), key, float(row["game_us"]) / 1000.0,
			float(row["map_us"]) / 1000.0, float(row["outside_driver_us"]) / 1000.0,
			int(row["memory_delta"]), int(row["objects_delta"]), str(row["save_before"]),
			str(row["save_after"]), " | ".join(timed)])
		for label: Dictionary in row["labels"]:
			print("FRAME LABEL frame %d; %s %.3f ms; overall %s; worker_receipt %s" % [int(row["frame"]),
				String(label["label"]), float(label["us"]) / 1000.0, str(label["overall"]),
				str(label.get("worker_receipt", false))])
	var keys: Array = classes.keys()
	keys.sort()
	for key: String in keys:
		var count: Array = classes[key]
		print("FRAME CLASS %s; count %d; worst %.3f ms" % [key, int(count[0]), float(count[1]) / 1000.0])
	keys = members.keys()
	keys.sort()
	for key: String in keys:
		var count: Array = members[key]
		print("FRAME MEMBER %s; count %d; worst %.3f ms" % [key, int(count[0]), float(count[1]) / 1000.0])
	var warm: Dictionary = {}
	for job: Dictionary in (Perf.get("slow_jobs") as Array):
		print("FRAME NATIVE OVER phase %s; kind %s; engine %d; day %.6f; %.3f ms; head %s" % [
			String(job["phase"]), String(job["kind"]), int(job["engine"]), float(job["day"]),
			float(job["us"]) / 1000.0, String(job["head"])])
		var key: String = String(job["phase"]) + "/" + String(job["kind"])
		var count: Array = warm.get(key, [0, 0])
		warm[key] = [int(count[0]) + 1, maxi(int(count[1]), int(job["us"]))]
	keys = warm.keys()
	keys.sort()
	for key: String in keys:
		var count: Array = warm[key]
		print("FRAME NATIVE CLASS %s; calls %d; worst %.3f ms" % [key, int(count[0]), float(count[1]) / 1000.0])
