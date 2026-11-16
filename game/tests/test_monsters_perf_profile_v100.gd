extends "res://tests/test_campaign_monsters.gd"
## Apply fix_monsters_perf_r3.diff first. Inherits the exact seed-777 fixture.
## Default: profile the real native map/Game frame; --monsters-profile=legacy reproduces the old failure.
## Instrumented timings diagnose cost; run the ordinary perf row to certify its gate.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.

var _profile_rows: Array[Dictionary] = []
var _profile_mode: String = "map"
var _profile_deadline: int = 0
var _profile_timed_out: bool = false

func run(tree: SceneTree) -> int:
	_profile_deadline = Time.get_ticks_msec() + 55000
	return await super.run(tree)

func _within_budget() -> bool:
	if Time.get_ticks_msec() >= _profile_deadline:
		if not _profile_timed_out:
			check(false, "monster profile exceeded 55 seconds; incomplete work is a failure")
			_profile_timed_out = true
		return false
	return super._within_budget()

func _profile_snapshot() -> Dictionary:
	return {"jobs": CampaignWorld.job_total.duplicate(true),
		"steps": CampaignWorld.step_parts.duplicate(), "daily": CampaignWorld.daily_total.duplicate(),
		"movement": CampaignWorld.steps_total, "day": Game.day,
		"midnight": int(Game.world.get("last_day", 0))}

func _counter_delta(current: Dictionary, before: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in current:
		var change: int = int(current[key]) - int(before.get(key, 0))
		if change != 0: result[key] = change
	return result

func _sum_usec(parts: Dictionary) -> int:
	var total: int = 0
	for value: Variant in parts.values(): total += int(value)
	return total

func _profile_sample(before: Dictionary, elapsed: int) -> void:
	var jobs: Dictionary = {}
	var jobs_usec: int = 0
	for kind: String in CampaignWorld.job_total:
		var previous: Array = before["jobs"].get(kind, [0, 0])
		var current: Array = CampaignWorld.job_total[kind]
		var us: int = int(current[0]) - int(previous[0])
		var steps: int = int(current[1]) - int(previous[1])
		if us != 0 or steps != 0: jobs[kind] = {"us": us, "steps": steps}
		jobs_usec += us
	var parts: Dictionary = _counter_delta(CampaignWorld.step_parts, before["steps"])
	var daily: Dictionary = _counter_delta(CampaignWorld.daily_total, before["daily"])
	var movement: int = CampaignWorld.steps_total - int(before["movement"])
	_profile_rows.append({"sample": _profile_rows.size() + 1, "engine_frame": Engine.get_process_frames(),
		"total_us": elapsed, "day_before": before["day"], "day_after": Game.day,
		"midnight_before": before["midnight"], "midnight_after": int(Game.world.get("last_day", 0)),
		"midnight_delta": int(Game.world.get("last_day", 0)) - int(before["midnight"]),
		"autosave_day_pending": bool(Game.get("_autosave_day_pending")), "saves": Game.save_stats(),
		"warband_update_us": int(parts.get("move", 0)), "step_parts_us": parts,
		"movement_and_creature_checks_us": movement, "midnight_parts_us": daily, "jobs": jobs,
		"unattributed_us": elapsed - jobs_usec - movement - _sum_usec(daily),
		"pending": Game.world.get("work", []).size(), "warbands": Game.world["warbands"].size()})

func _perf_map_frame(delta: float) -> void:
	var before: Dictionary = _profile_snapshot()
	var started: int = Time.get_ticks_usec()
	super._perf_map_frame(delta)
	var elapsed: int = Time.get_ticks_usec() - started
	_profile_sample(before, elapsed)

func _legacy_perf(w: Dictionary) -> int:
	w["party"]["safe_until"] = Game.day + 100.0
	var frame_days: float = (1.0 / 60.0) / 5.0
	var total: int = 0
	var worst: int = 0
	for i in 600:
		if not _within_budget(): break
		var before: Dictionary = _profile_snapshot()
		var t0: int = Time.get_ticks_usec()
		Game.day += frame_days
		CampaignWorld.on_time(Game, frame_days, false)
		var dtu: int = Time.get_ticks_usec() - t0
		total += dtu
		worst = maxi(worst, dtu)
		_profile_sample(before, dtu)
		w["encounter"] = ""
	check(_profile_rows.size() == 600, "monster profile must measure all 600 legacy calls")
	print("on_time per map frame with monsters: mean %.3f ms, worst %.2f ms, %d warbands" % [total / 600.0 / 1000.0, worst / 1000.0, w["warbands"].size()])
	check(total / 600.0 / 1000.0 < 0.5, "on_time too slow per frame")
	return fails

func _perf(w: Dictionary, rng: RandomNumberGenerator) -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--monsters-profile="): _profile_mode = argument.trim_prefix("--monsters-profile=")
	check(_profile_mode in ["legacy", "map"], "monster profile mode must be legacy or map")
	if fails > 0: return fails
	var result: int = 0
	if _profile_mode == "map": result = await super._perf(w, rng)
	else: result = _legacy_perf(w)
	# Print after timing. Never subtract nested counters twice: warband_update is
	# part of step_parts, and step_parts is inside movement_and_creature_checks.
	# midnight_parts are native partial bookkeeping counters, not the whole _daily.
	var totals: Dictionary = {}
	for row: Dictionary in _profile_rows:
		print("MONSTER_PROFILE ", _profile_mode, " ", JSON.stringify(row))
		for kind: String in row["jobs"]:
			totals[kind] = int(totals.get(kind, 0)) + int(row["jobs"][kind]["us"])
	print("MONSTER_PROFILE_TOTAL ", _profile_mode, " job_us=", JSON.stringify(totals),
		" samples=", _profile_rows.size(), " pending=", w.get("work", []).size(),
		" hold=", Game._day_job_hold_active(), " autosave_day_pending=", Game.get("_autosave_day_pending"),
		" saves=", JSON.stringify(Game.save_stats()))
	return result
