extends RefCounted
## Diagnostic only: exit zero for observed game differences, one for fixture/harness errors.
## Reuse the exact r2 first case, not a fabricated population or reservation count.
const Matching = preload("res://tests/test_casual_matching.gd")
const NativeEconomy = preload("res://tests/class_d_native_economy.gd")

func _state(e: Dictionary) -> Dictionary:
	var rows: Dictionary = {}
	var idle_sum: int = 0
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false): continue
		idle_sum += int(family["idle"])
		rows[str(int(family["id"]))] = {"idle": int(family["idle"]), "hands": int(family["hands"]),
			"cj": (family.get("cj", {}) as Dictionary).duplicate(), "jobs": (family["jobs"] as Dictionary).duplicate()}
	return {"idle_n": int(e["idle_n"]), "idle_sum": idle_sum, "used": (e["cjused"] as Dictionary).duplicate(), "rows": rows}

func _receipt(label: String, before: Dictionary, after: Dictionary, target: int) -> void:
	print("CASUAL_PATH ", label, " ", JSON.stringify({"target": target,
		"idle_n_before": before["idle_n"], "idle_n_after": after["idle_n"],
		"idle_sum_before": before["idle_sum"], "idle_sum_after": after["idle_sum"],
		"used_before": before["used"], "used_after": after["used"]}))
	for id: String in before["rows"]:
		if before["rows"][id] != after["rows"][id]:
			print("CASUAL_PATH_HOUSEHOLD ", label, " ", id, " ", JSON.stringify({"before": before["rows"][id], "after": after["rows"][id]}))

func _error(reason: String) -> int:
	printerr("CASUAL_PATH_HARNESS_ERROR: ", reason)
	return 1

func run(_tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	var fixture: Variant = Matching.new()
	fixture._deadline_msec = started + 50000
	WorldGen.gen_size = "normal"; Game.new_game(2026)
	print("CASUAL_PATH_STAGE world_ms=", Time.get_ticks_msec() - started)
	var town: Dictionary = {}
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	for id: String in ids:
		var candidate: Dictionary = Game.world["towns"][id]
		if TownEcon.has_econ(candidate) and str(candidate["econ"]["culture"]) == "middle":
			town = candidate
			break
	if town.is_empty(): return _error("seed 2026 has no native middle-culture town")
	if Time.get_ticks_msec() >= int(fixture._deadline_msec): return _error("world setup exceeded the 50-second diagnostic budget")
	var prepared: Dictionary = fixture._prepare(town)
	print("CASUAL_PATH_STAGE prepared_ms=", Time.get_ticks_msec() - started)
	if not bool(prepared.get("ok", false)): return _error(str(prepared.get("reason", "prepare failed")))
	var e: Dictionary = prepared["econ"]
	var original: Dictionary = e
	var target: int = int(prepared["target"])
	var excluded: Array[int] = []
	excluded.assign(prepared["excluded"])
	var window: Dictionary = {}
	var last_reason: String = "no exact target-only donor found"
	# _windows retries each reservation order from the untouched prepared state.
	# Search only this one diagnostic window, retaining the same native fallback.
	for rotation: int in (original["fams"] as Array).size():
		if Time.get_ticks_msec() >= int(fixture._deadline_msec):
			return _error("donor search exceeded the 50-second diagnostic budget: " + last_reason)
		e = original.duplicate(true)
		var local_town: Dictionary = town.duplicate(false)
		local_town["econ"] = e
		var reserved: Dictionary = NativeEconomy.reserve_casual(local_town, e, excluded, int(fixture._deadline_msec), rotation)
		if not bool(reserved.get("ok", false)): return _error(str(reserved.get("reason", "reservation failed")))
		var donors: Array[int] = []
		donors.assign(fixture._donors(e, "street_sweeper", 1, target))
		if not donors.is_empty():
			window = {"econ": e, "target": target, "donors": donors,
				"cleanup_family": prepared["cleanup_family"], "cleanup_pid": prepared["cleanup_pid"]}
		else:
			var constructed: Dictionary = fixture._construct_window(town, prepared, e, "street_sweeper", 1)
			if bool(constructed.get("ok", false)):
				window = constructed
			else:
				last_reason = str(constructed.get("reason", "donor construction failed"))
		print("CASUAL_PATH_STAGE rotation=", rotation, " donor_search_ms=", Time.get_ticks_msec() - started,
			" donors=", window.get("donors", []), " reason=", last_reason if window.is_empty() else "")
		if Time.get_ticks_msec() >= int(fixture._deadline_msec):
			return _error("donor search exceeded the 50-second diagnostic budget: " + last_reason)
		if not window.is_empty(): break
	if window.is_empty(): return _error("all native reservation orders rejected the diagnostic window: " + last_reason)
	print("CASUAL_PATH_STAGE window_ms=", Time.get_ticks_msec() - started)
	var scenario: Dictionary = fixture._scenario(window, "street_sweeper", 1, 0.0)
	if not bool(scenario.get("ok", false)): return _error(str(scenario.get("reason", "scenario failed")))
	e = scenario["econ"]
	if not bool(fixture._fund(e, "street_sweeper", float(e["cjcap"]["street_sweeper"]))):
		return _error("existing coin cannot fund the actual street-sweeper bill")
	var target_family: Dictionary = e["fams"][target]
	if int(target_family["idle"]) < 2 or not target_family.get("cj", {}).is_empty():
		return _error("the original two-idle-adult target prerequisite is missing")
	for business: Dictionary in e["biz"]:
		if Businesses.takeable(business, e) > 0: return _error("a real regular offer competes with the diagnostic case")
	if Shelter.available_casual(e, "street_sweeper") != 1 or not bool(fixture._reservations(e)):
		return _error("the original single native funded vacancy or balanced assignments are missing")
	if Time.get_ticks_msec() >= int(fixture._deadline_msec): return _error("fixture setup exceeded the 50-second diagnostic budget")
	var before: Dictionary = _state(e)
	var legacy: Dictionary = e.duplicate(true)
	# This is the old match_idle loop, after its successful initial vacancy check.
	for family: Dictionary in legacy["fams"]:
		if not family.get("gone", false) and not family.get("estate", false) and int(family.get("idle", 0)) > 0:
			Families.reassign(legacy, family)
			if Time.get_ticks_msec() >= int(fixture._deadline_msec): return _error("old-path trace exceeded the 50-second diagnostic budget")
	_receipt("old_full_reassignment_loop", before, _state(legacy), target)
	Families.match_idle(e)
	if Time.get_ticks_msec() >= int(fixture._deadline_msec): return _error("installed-path trace exceeded the 50-second diagnostic budget")
	_receipt("installed_match_idle", before, _state(e), target)
	print("CASUAL_PATH_DIAGNOSTIC_ONLY elapsed_ms=", Time.get_ticks_msec() - started,
		"; observations are not an acceptance-test pass")
	return 0
