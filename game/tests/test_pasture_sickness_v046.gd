extends "res://tests/test_pasture_assignment_v046.gd"
## Bounded event-boundary reproduction, not an ordinary full-campaign estimate.
## The parent supplies generated property selection and independent accounts.
## A real native raid must first create live registered pasture defenders.
## Existing test_sickness's native infect/case-date/queue technique then exercises
## town_day while that same asynchronous fight remains open; native raid cleanup
## must preserve the first cause and remove only actual fallen defender identities.
## No direct People.casualty, synthetic economy, or household counter repair.
## Defaults Normal/2026. Optional PASTURE_TEST_SIZE and PASTURE_SICK_SEED.

func run(_tree: SceneTree) -> int:
	var size: String = OS.get_environment("PASTURE_TEST_SIZE")
	if size.is_empty():
		size = "normal"
	check(WorldGen.SIZES.has(size), "valid generated sickness-reproduction size", {"size": size})
	if not WorldGen.SIZES.has(size):
		return failures
	var seed_value: int = 2026
	var seed_text: String = OS.get_environment("PASTURE_SICK_SEED")
	if not seed_text.is_empty():
		check(seed_text.is_valid_int(), "integer sickness-reproduction seed")
		if not seed_text.is_valid_int():
			return failures
		seed_value = seed_text.to_int()
	var keep_size: String = WorldGen.gen_size
	WorldGen.gen_size = size
	_reproduce(seed_value)
	WorldGen.gen_size = keep_size
	print("PASTURE_SICKNESS_RESULT ", JSON.stringify({"checks": checks, "failures": failures, "seed": seed_value,
		"size": size, "event_boundary_reproduction": true, "full_campaign_probability_estimate": false}))
	return failures

func _people_snapshot(e: Dictionary) -> Dictionary:
	var persons: Dictionary = {}
	var uid_to_pid: Dictionary = {}
	for f: Dictionary in e["fams"]:
		for slot: String in ["pp", "kp"]:
			for p: Array in f.get(slot, []):
				var pid: int = int(p[0])
				persons[pid] = {"fid": int(f["id"]), "pid": pid, "uid": int(p[5]), "state": String(p[4]),
					"name": Persons.name_of(f, p, Persons.race_of(e)), "kind": int(p[6]),
					"counted": not bool(f.get("gone", false)) and not bool(f.get("estate", false)) and not Persons.AWAY.has(String(p[4]))}
				if int(p[5]) >= 0:
					uid_to_pid[int(p[5])] = pid
	return {"persons": persons, "uid_to_pid": uid_to_pid, "pop": int(e["pop"]),
		"deaths": (Census._book(e)["deaths"] as Array).duplicate(true), "dt": int(Census._book(e).get("dt", 0))}

func _rows_for(rows: Array, pid: int) -> Array:
	var out: Array = []
	for row: Array in rows:
		if int(row[1]) == pid:
			out.append(row)
	return out

func _removed(before: Dictionary, after: Dictionary) -> Dictionary:
	var lost: Dictionary = {}
	for pid: int in before["persons"]:
		if not after["persons"].has(pid):
			lost[pid] = before["persons"][pid]
	return lost

func _actual_events(before: Dictionary, after: Dictionary, label: String) -> Array:
	var rows: Array = (after["deaths"] as Array).slice((before["deaths"] as Array).size())
	var lost: Dictionary = _removed(before, after)
	var counted: int = 0
	for row: Array in rows:
		counted += int(row[9])
		print("PASTURE_SICKNESS_ACTUAL_DEATH ", JSON.stringify({"boundary": label, "row": row}))
		check(lost.has(int(row[1])), label + ": each actual Census death corresponds to its removed register PID", {"row": row})
	for pid: int in lost:
		print("PASTURE_SICKNESS_ACTUAL_REMOVAL ", JSON.stringify({"boundary": label, "person": lost[pid]}))
		check(_rows_for(rows, pid).size() == 1, label + ": each register removal has one actual Census death", {"person": lost[pid]})
	check(int(before["pop"]) - int(after["pop"]) == counted and int(after["dt"]) - int(before["dt"]) == counted,
		label + ": all actual counted deaths reconcile population and cumulative Census", {"before_pop": before["pop"], "after_pop": after["pop"], "counted_rows": counted})
	return rows

func _reproduce(seed_value: int) -> void:
	Game.new_game(seed_value)
	# Existing paid civilian work guarantees an independent person whose identity
	# cannot legitimately be substituted for a previously deceased defender.
	var picked: Dictionary = _select("mixed", 1)
	check(not picked.is_empty(), "generated mixed-work household supplies real herders and an independent civilian", {"seed": seed_value})
	if picked.is_empty():
		print("PASTURE_SICKNESS_SCENARIO_INVALID no native mixed-work candidate; no data forced")
		return
	var town: Dictionary = picked["town"]
	var e: Dictionary = town["econ"]
	var f: Dictionary = picked["family"]
	var h: Dictionary = picked["herd"]
	var goal: Vector2 = picked["goal"]
	var expected_pids: Array = picked["pids"]
	_town_accounts(town, "sickness fixture before native muster")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value + 88046
	var wolves: Array = []
	for i: int in 8:
		wolves.append(Unit.create("wolf", "beasts"))
	var wid: String = CampaignWorld.spawn_warband(Game, "beasts", goal + Vector2(40, 0), wolves.size(), "beasts", rng, {"units": wolves})
	check(not wid.is_empty(), "native sickness-fixture wolf force exists")
	if wid.is_empty():
		return
	var wb: Dictionary = Game.world["warbands"][wid]
	wb["pos"] = goal + Vector2(40, 0)
	wb["raid"] = {"town": town["id"], "herd": h["id"], "goal": goal, "wolves": true, "phase": "travelling", "day": Game.day}
	wb["path"] = [goal]
	for force: Dictionary in [Militia.band_of(Game, String(town["id"])), TownDefence.guard_band(Game, String(town["id"]))]:
		if not force.is_empty():
			force["pos"] = goal
	var arrival_dt: float = (wb["pos"] as Vector2).distance_to(goal) / CampaignWorld.WARBAND_SPEED + 0.001
	HerdRaids.step(Game, wb, arrival_dt, Game.day, rng)
	var pending: bool = wb.has("raid") and HerdRaids.fights.has(wid)
	check(pending, "native arrival supplies a still-open asynchronous raid")
	if not pending:
		print("PASTURE_SICKNESS_SCENARIO_INVALID native combat completed before sickness injection")
		return
	var fight: Dictionary = HerdRaids.fights[wid]
	var defenders: Array = (fight["defenders"] as Array).duplicate()
	var victim: Unit = null
	var p: Array = []
	for u: Unit in defenders:
		if u.dead or u.family != int(f["id"]) or u.home_town != String(town["id"]):
			continue
		var person: Array = Persons.by_uid(f, u.uid)
		if not person.is_empty() and String(person[4]) == "pasture" and expected_pids.has(int(person[0])):
			victim = u
			p = person
			break
	check(victim != null and not p.is_empty(), "a still-living native pasture defender retains its original registered person")
	if victim == null or p.is_empty():
		print("PASTURE_SICKNESS_SCENARIO_INVALID no living registered pasture defender remains")
		return
	var independent_civilians: Dictionary = {}
	for person: Array in f.get("pp", []):
		if int(person[6]) == 0 and String(person[4]) in CIVILIAN_STATES:
			independent_civilians[int(person[0])] = Persons.name_of(f, person, Persons.race_of(e))
	check(not independent_civilians.is_empty(), "muster leaves at least one actual civilian outside the defender roster")
	if independent_civilians.is_empty():
		print("PASTURE_SICKNESS_SCENARIO_INVALID no independent civilian after native selection")
		return
	var pid: int = int(p[0])
	var uid: int = victim.uid
	var name: String = Persons.name_of(f, p, Persons.race_of(e))
	var before_sickness: Dictionary = _people_snapshot(e)
	var case_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	case_rng.seed = 31
	var infected: bool = Sickness.infect(Game, town, f, p, "pox", Game.day, "carrier:test", case_rng)
	check(infected, "native pox infection accepts the actual living pasture defender", {"pid": pid, "state": p[4]})
	if not infected:
		print("PASTURE_SICKNESS_SCENARIO_INVALID native infection refused; no case fabricated")
		return
	var c: Array = Sickness.case_of(f, pid)
	check(not c.is_empty(), "native infection installs its authoritative real-person case")
	if c.is_empty():
		return
	# The unchanged sickness test's forced outcome and native queued death method.
	c[Sickness.C_DIE] = float(c[Sickness.C_ON]) + 1.0
	Sickness._push(Sickness.book(e), [c[Sickness.C_DIE], 0, int(f["id"]), pid, "pox", ""])
	var forced_day: int = ceili(float(c[Sickness.C_DIE]))
	var from_day: int = int(Game.day)
	check(forced_day > from_day and forced_day - from_day <= 20, "native pox forced date is a bounded future event", {"from": from_day, "to": forced_day})
	if forced_day <= from_day or forced_day - from_day > 20:
		return
	print("PASTURE_SICKNESS_FIXTURE ", JSON.stringify({"seed": seed_value, "town": town["id"], "family": f["id"],
		"culture": e["culture"], "raid": wid, "sick_pid": pid, "sick_uid": uid, "sick_name": name,
		"expected_muster_pids": expected_pids, "independent_civilians": independent_civilians,
		"case": c.duplicate(true), "forced_day": forced_day, "progression": "native town_day only; same raid remains open"}))
	for d: int in range(from_day + 1, forced_day + 1):
		Game.day = float(d)
		e["day"] = d
		Sickness.town_day(Game, town, d)
	var after_sickness: Dictionary = _people_snapshot(e)
	_actual_events(before_sickness, after_sickness, "queued sickness boundary")
	var first_rows: Array = _rows_for(after_sickness["deaths"], pid)
	var first_cause_ok: bool = first_rows.size() == 1 and String(first_rows[0][5]) == "sickness" and String(first_rows[0][6]) == "the pox"
	check(first_cause_ok, "queued death records the first actual sickness cause exactly once", {"pid": pid, "rows": first_rows})
	var first_memory: Array = Persons.any(f, pid).duplicate(true)
	check(not first_memory.is_empty() and str(first_memory).contains("sickness: the pox"), "the actual departed person retains the first sickness cause", {"pid": pid, "memory": first_memory})
	check(Persons.by_pid(f, pid).is_empty() and victim.dead, "queued sickness removes the real person and marks its actual defender dead", {"pid": pid, "uid": uid})
	var hid: String = String(wb["raid"].get("herders", ""))
	var temporary: Dictionary = Game.world["warbands"].get(hid, {})
	var retains_uid: bool = false
	for u: Unit in temporary.get("units", []):
		if u.uid == uid:
			retains_uid = true
	check(not retains_uid, "queued sickness removes the actual Unit from its live pasture force")
	var alive_pasture: int = 0
	for person: Array in f.get("pp", []):
		if String(person[4]) == "pasture":
			alive_pasture += 1
	var service_stale: bool = int(f.get("serve", {}).get("pasture", 0)) != alive_pasture
	check(not service_stale, "queued sickness releases exactly the dead defender's pasture service slot", {"recorded_pasture": f.get("serve", {}).get("pasture", 0), "living_pasture_people": alive_pasture})
	check(wb.has("raid") and HerdRaids.fights.has(wid), "the exact original raid remains open at sickness accounting boundary")
	_town_accounts(town, "after actual queued pasture sickness death")
	var before_cleanup: Dictionary = _people_snapshot(e)
	var independent_before_cleanup: Dictionary = {}
	for civilian_pid: int in independent_civilians:
		if before_cleanup["persons"].has(civilian_pid):
			independent_before_cleanup[civilian_pid] = before_cleanup["persons"][civilian_pid]
	check(not independent_before_cleanup.is_empty(), "an actual independent civilian survives sickness to the cleanup boundary")
	var calls: int = 0
	while wb.has("raid") and calls < MAX_BATTLE_CALLS:
		HerdRaids.step(Game, wb, 0.01, Game.day, rng)
		calls += 1
	check(not wb.has("raid"), "same native raid reaches bounded real cleanup", {"calls": calls})
	if wb.has("raid"):
		return
	var after_cleanup: Dictionary = _people_snapshot(e)
	var cleanup_rows: Array = _actual_events(before_cleanup, after_cleanup, "native raid cleanup")
	var expected_combat_losses: Dictionary = {}
	for u: Unit in defenders:
		if u.dead and before_cleanup["uid_to_pid"].has(u.uid):
			var combat_pid: int = int(before_cleanup["uid_to_pid"][u.uid])
			expected_combat_losses[combat_pid] = u.uid
	var cleanup_lost: Dictionary = _removed(before_cleanup, after_cleanup)
	var unrelated_losses: Dictionary = {}
	for lost_pid: int in cleanup_lost:
		if not expected_combat_losses.has(lost_pid):
			unrelated_losses[lost_pid] = cleanup_lost[lost_pid]
	check(unrelated_losses.is_empty(), "cleanup removes only actual fallen defender identities, never a substitute civilian", {"unrelated_losses": unrelated_losses, "actual_dead_defenders": expected_combat_losses})
	for combat_pid: int in expected_combat_losses:
		check(cleanup_lost.has(combat_pid), "each newly fallen defender leaves through its own actual person", {"pid": combat_pid})
	var civilian_losses: Dictionary = {}
	for civilian_pid: int in independent_before_cleanup:
		if not after_cleanup["persons"].has(civilian_pid):
			civilian_losses[civilian_pid] = independent_before_cleanup[civilian_pid]
	check(civilian_losses.is_empty(), "independent surviving civilians retain their identities through combat cleanup", {"lost_civilians": civilian_losses})
	var final_rows: Array = _rows_for(after_cleanup["deaths"], pid)
	var cause_preserved: bool = final_rows == first_rows and first_cause_ok
	check(cause_preserved, "combat cleanup preserves the original sickness Census row without another death for its PID", {"first": first_rows, "final": final_rows})
	check(Persons.any(f, pid) == first_memory, "combat cleanup preserves the original deceased person's actual identity and remembered cause", {"pid": pid})
	check(Persons.by_pid(f, pid).is_empty(), "combat cleanup cannot recreate the deceased register person")
	check(not HerdRaids.fights.has(wid) and not Game.world["warbands"].has(hid), "cleanup drops the original fight and temporary force")
	_town_accounts(town, "after native cleanup following sickness")
	print("PASTURE_SICKNESS_OBSERVED ", JSON.stringify({"seed": seed_value, "town": town["id"], "family": f["id"],
		"sick_pid": pid, "sick_uid": uid, "forced_day": forced_day, "observed_stale_pasture_service_at_sickness": service_stale,
		"observed_nondefender_cleanup_losses": unrelated_losses, "observed_independent_civilian_cleanup_losses": civilian_losses,
		"first_actual_cause_preserved": cause_preserved, "first_sickness_rows": first_rows, "final_sick_pid_rows": final_rows,
		"actual_cleanup_death_rows": cleanup_rows, "actual_dead_defender_pids": expected_combat_losses,
		"battle_calls": calls, "event_boundary_reproduction": true}))
