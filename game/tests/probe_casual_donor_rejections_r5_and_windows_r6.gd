extends "res://tests/test_casual_matching.gd"
## Diagnostic only: one native culture and all 16 current acceptance cases.
## Select --culture=eastern (default: middle), using the same complete culture fixtures as #80.
## The already-confirmed r5 rejection trace is optional (--trace-r5).
## Observed fixture/game differences return zero; structural harness errors return one.
## The 25-second cooperative deadline and 30-second external cap include world setup.

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("CASUAL_R6_OBSERVATION ", message)

func _harness_error(reason: String) -> int:
	printerr("CASUAL_R6_HARNESS_ERROR: ", reason)
	return 1

func _observed(reason: String) -> int:
	print("CASUAL_R6_DIAGNOSTIC_ONLY observed_failures=", fails, " reason=", reason, "; not a #80 acceptance pass")
	return 0

## Keep the old spare-count bug only inside the optional historical trace.
func _r5_donor_spare(family: Dictionary) -> int:
	var spare: int = int(family["idle"])
	for count: Variant in (family.get("cj", {}) as Dictionary).values(): spare += int(count)
	return spare

## Historical r5 constructor, retaining its spare-count bug and rejection receipts.
## It runs once for street_sweeper/two places/rotation zero, never per current window.
func _trace_r5_search(town: Dictionary, prepared: Dictionary, original: Dictionary, job: String, places: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var attempts: int = 0
	var target: int = int(prepared["target"])
	var before: float = money(original)
	var physical: Variant = load("res://tests/farm_fixture_tools.gd").new()
	var candidates: Array[Dictionary] = []
	for holder: Dictionary in original["fams"]:
		if int(holder["id"]) <= target or holder.get("gone", false) or holder.get("estate", false): continue
		# A small idle household can take an existing holder's real shift too.
		# The final target-only reservation checks below still decide success.
		if _r5_donor_spare(holder) >= places: candidates.append(holder)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_spare: int = _r5_donor_spare(a)
		var b_spare: int = _r5_donor_spare(b)
		return a_spare < b_spare if a_spare != b_spare else int(a["id"]) < int(b["id"]))
	for candidate: Dictionary in candidates:
		if not _within_budget(): return {"ok": false, "reason": "native donor construction exceeded its budget"}
		var id: int = int(candidate["id"])
		if id <= target or candidate.get("gone", false) or candidate.get("estate", false): continue
		attempts += 1
		var e: Dictionary = original.duplicate(true)
		var family: Dictionary = e["fams"][id]
		Shelter.release_casual(e, family)
		Families.reassign(e, family)
		# Open enough physical target places before funding the new donor.
		# Whole-household releases remain native; all other places are refilled below.
		var released_holders: int = 0
		for holder: Dictionary in e["fams"]:
			if float(e["cjcap"][job]) - float(e["cjused"].get(job, 0)) + 0.00001 >= float(places): break
			if int(holder.get("cj", {}).get(job, 0)) <= 0: continue
			Shelter.release_casual(e, holder)
			Families.reassign(e, holder)
			released_holders += 1
		var field_steps: int = 0
		for acre: int in 64:
			if not _within_budget(): return {"ok": false, "reason": "native donor field work exceeded its budget"}
			if int(family["idle"]) <= places: break
			var acres: int = maxi(1, int(family["idle"]) - places)
			if not physical.grain(e, family, acres) and not physical.grain(e, family, 1): break
			field_steps += 1
			Families.reassign(e, family)
		if int(family["idle"]) != places:
			_donor_reject("r5_idle_count", e, family, job, places, field_steps)
			continue
		if not _fund(e, job, float(e["cjcap"][job])):
			return {"ok": false, "reason": "existing coin cannot fund the constructed native donor"}
		Families.reassign(e, family)
		var shifts: Dictionary = family.get("cj", {})
		if shifts.size() != 1 or int(shifts.get(job, 0)) != places or Families.assignments_stale(family):
			_donor_reject("r5_target_only", e, family, job, places, field_steps)
			continue
		var excluded: Array[int] = []
		excluded.assign(prepared["excluded"])
		excluded.append(id)
		var local_town: Dictionary = town.duplicate(false)
		local_town["econ"] = e
		var reserved: Dictionary = NativeEconomy.reserve_casual(local_town, e, excluded, _deadline_msec)
		if not bool(reserved["ok"]):
			_donor_reject("r5_refill", e, family, job, places, field_steps, str(reserved.get("reason", "")))
			continue
		var donors: Array[int] = _donors(e, job, places, target)
		if donors.is_empty() or not _reservations(e):
			_donor_reject("r5_reservation_books", e, family, job, places, field_steps)
			continue
		if absf(money(e) - before) > 0.00001:
			return {"ok": false, "reason": "native donor construction must conserve every coin"}
		print("CASUAL_R5_TRACE ", e["culture"], " job=", job, " places=", places, " attempts=", attempts,
			" donors=", donors, " released_holders=", released_holders, " field_steps=", field_steps, " construct_ms=", Time.get_ticks_msec() - started)
		return {"ok": true, "econ": e, "target": target, "donors": donors, "cleanup_family": prepared["cleanup_family"], "cleanup_pid": prepared["cleanup_pid"]}
	print("CASUAL_R5_TRACE ", original["culture"], " job=", job, " places=", places, " rejected_attempts=", attempts, " construct_ms=", Time.get_ticks_msec() - started)
	return {"ok": false, "reason": "no native target-only holder could supply the exact donor workforce"}

func run(_tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	_deadline_msec = started + 25000
	WorldGen.gen_size = "normal"; Game.new_game(2026)
	print("CASUAL_R6_PROBE world_ms=", Time.get_ticks_msec() - started)
	var culture: String = "middle"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--culture="):
			culture = argument.trim_prefix("--culture=")
	if not (TownEcon.data()["cultures"] as Dictionary).has(culture):
		return _harness_error("unknown native culture: " + culture)
	var native: Dictionary = NativeCultures.towns(Game)
	if not bool(native.get("ok", false)):
		return _harness_error(str(native.get("reason", "native culture fixture failed")))
	if not (native["towns"] as Dictionary).has(culture):
		return _harness_error("seed 2026 has no native fixture for culture " + culture)
	var town: Dictionary = native["towns"][culture]
	print("CASUAL_R6_PROBE culture=", culture)
	if Time.get_ticks_msec() >= _deadline_msec: return _observed("world setup exhausted diagnostic budget")
	var prepared: Dictionary = _prepare(town)
	print("CASUAL_R6_PROBE prepared_ms=", Time.get_ticks_msec() - started)
	if not bool(prepared.get("ok", false)): return _observed(str(prepared.get("reason", "prepare failed")))
	if OS.get_cmdline_user_args().has("--trace-r5"):
		var e: Dictionary = (prepared["econ"] as Dictionary).duplicate(true)
		var local_town: Dictionary = town.duplicate(false)
		local_town["econ"] = e
		var excluded: Array[int] = []
		excluded.assign(prepared["excluded"])
		var reserved: Dictionary = NativeEconomy.reserve_casual(local_town, e, excluded, _deadline_msec, 0)
		if not bool(reserved.get("ok", false)): return _observed(str(reserved.get("reason", "r5 baseline reservation failed")))
		var traced: Dictionary = _trace_r5_search(town, prepared, e, "street_sweeper", 2)
		print("CASUAL_R6_PROBE r5_trace_ms=", Time.get_ticks_msec() - started, " result=", traced.get("ok", false),
			" reason=", traced.get("reason", ""))
		if Time.get_ticks_msec() >= _deadline_msec: return _observed("r5 trace exhausted diagnostic budget")
	var windows: Dictionary = _windows(town, prepared)
	print("CASUAL_R6_PROBE windows_ms=", Time.get_ticks_msec() - started)
	if not bool(windows.get("ok", false)): return _observed(str(windows.get("reason", "current windows failed")))
	var cases: int = 0
	for job: String in ["street_sweeper", "night_soil_man"]:
		for spec: Array in [[1, 0.0], [1, 0.2], [2, 0.2], [0, 0.0]]:
			if Time.get_ticks_msec() >= _deadline_msec: return _observed("case matrix exhausted diagnostic budget")
			var scenario: Dictionary = _scenario(windows["windows"]["%s:%d" % [job, int(spec[0])]], job, int(spec[0]), float(spec[1]))
			if not bool(scenario.get("ok", false)): return _observed(str(scenario.get("reason", "scenario failed")))
			for funded: bool in [false, true]:
				fixture(scenario, job, int(spec[0]), float(spec[1]), funded)
				cases += 1
				if fails > 0: return _observed("current acceptance assertions rejected this culture")
	print("CASUAL_R6_PROBE cases_ms=", Time.get_ticks_msec() - started, " cases=", cases, " checks=", checks)
	return _observed("completed one culture; full nine-culture #80 remains required")
