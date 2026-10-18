extends RefCounted
## v0.041: tactical battle systems headless test.
## Verifies TACTICS, counter table, terrain math, ai_pick determinism and sensitivity,
## modifiers bounds and commander tactician scaling, ClashRounds tactic logs, and a real
## round battle with BattleTactics.choose(Game, 0, "hold").
## Run with: -- --test=res://tests/claude_tactics_v041.gd

var checks: int = 0
var fails: int = 0
var previous_save_path: String = ""


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL tactics041: ", what)


func frames(tree: SceneTree, n: int = 3) -> void:
	for _i in n:
		await tree.process_frame


func _finish() -> int:
	DevTools.set_round_size(BattleRounds.ROUND)
	Game.wait_save()
	if previous_save_path != "":
		Game.SAVE_PATH = previous_save_path
	print("tactics041: %d checks, %d failures" % [checks, fails])
	return fails


func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH

	# 1. TACTICS dictionary and one-line descriptions.
	var expected_tactics: Array[String] = ["charge", "hold", "flank", "skirmish", "feint"]
	check(BattleTactics.TACTICS.size() == 5, "TACTICS has 5 tactics")
	for t in expected_tactics:
		check(BattleTactics.TACTICS.has(t), "TACTICS has " + t)
		var desc: String = BattleTactics.description(t)
		check(desc.length() > 10 and not desc.contains("\n"), "tactic '%s' has a one-line description" % t)

	# 2. Counter table bounds and relationships.
	check(BattleTactics.counter_mod("charge", "skirmish") > 0.0, "charge beats skirmish")
	check(BattleTactics.counter_mod("hold", "charge") > 0.0, "hold beats charge")
	check(BattleTactics.counter_mod("flank", "hold") > 0.0, "flank beats hold")
	check(BattleTactics.counter_mod("skirmish", "flank") > 0.0, "skirmish beats flank")
	check(BattleTactics.counter_mod("feint", "charge") > 0.0, "feint beats charge")
	check(BattleTactics.counter_mod("feint", "hold") < 0.0, "feint loses to hold")
	var all_in_bounds: bool = true
	var all_antisym: bool = true
	for a in expected_tactics:
		for b in expected_tactics:
			var ab: float = BattleTactics.counter_mod(a, b)
			var ba: float = BattleTactics.counter_mod(b, a)
			if ab < -0.1501 or ab > 0.1501:
				all_in_bounds = false
			if not is_equal_approx(ab, -ba):
				all_antisym = false
	check(all_in_bounds, "all counter modifiers are within [-0.15, +0.15]")
	check(all_antisym, "counter table is antisymmetric")
	check(BattleTactics.outcome_note("hold", "charge", 0, true) == "Your shield wall broke their charge",
		"outcome_note describes shield wall breaking charge")

	# 3. Terrain math.
	check(BattleTactics.terrain_mod("grassland", "charge", 0) > 0.0 and BattleTactics.terrain_mod("plains", "flank", 0) > 0.0,
		"grassland/plains favour charge and flank")
	check(BattleTactics.terrain_mod("forest", "hold", 0) > 0.0 and BattleTactics.terrain_mod("forest", "skirmish", 0) > 0.0,
		"forest favours hold and skirmish")
	check(BattleTactics.terrain_mod("marsh", "hold", 0) > 0.0 and BattleTactics.terrain_mod("marsh", "skirmish", 0) > 0.0,
		"marsh favours hold and skirmish")
	check(BattleTactics.terrain_mod("forest", "charge", 0) < 0.0 and BattleTactics.terrain_mod("marsh", "charge", 0) < 0.0,
		"forest and marsh penalize charge")
	var hills_att_hold: float = BattleTactics.terrain_mod("hills", "hold", 0, 1)
	var hills_def_hold: float = BattleTactics.terrain_mod("hills", "hold", 1, 1)
	var hills_def0_hold: float = BattleTactics.terrain_mod("hills", "hold", 0, 0)
	var hills_att1_hold: float = BattleTactics.terrain_mod("hills", "hold", 1, 0)
	check(hills_def_hold > hills_att_hold and hills_def_hold > 0.05,
		"hills favour hold for the defender (side 1 defending)")
	check(is_equal_approx(hills_def0_hold, hills_def_hold) and hills_def0_hold > hills_att1_hold,
		"hills defender bonus goes to side 0 when side 0 is the defender")

	# 4. ai_pick determinism and sensitivity to terrain and the enemy's last tactic.
	var st_det: Dictionary = {"terrain": "plains", "seed": 12345, "log": []}
	var p1: String = BattleTactics.ai_pick(st_det, 1, 1)
	var p2: String = BattleTactics.ai_pick(st_det, 1, 1)
	check(p1 == p2 and BattleTactics.TACTICS.has(p1), "ai_pick is deterministic for a given seed and round")

	# Round 1 has no enemy last tactic, so ai_pick's weight is max(0.10, 1 + terrain_mod * 4).
	# Compare those terrain weights directly, then confirm picks over a larger sample.
	var plains_mobile_w: float = 0.0
	var marsh_mobile_w: float = 0.0
	var marsh_def_w: float = 0.0
	var plains_def_w: float = 0.0
	for tactic_name in ["charge", "flank"]:
		plains_mobile_w += maxf(0.10, 1.0 + BattleTactics.terrain_mod("plains", tactic_name, 1, 1) * 4.0)
		marsh_mobile_w += maxf(0.10, 1.0 + BattleTactics.terrain_mod("marsh", tactic_name, 1, 1) * 4.0)
	for tactic_name in ["hold", "skirmish"]:
		marsh_def_w += maxf(0.10, 1.0 + BattleTactics.terrain_mod("marsh", tactic_name, 1, 1) * 4.0)
		plains_def_w += maxf(0.10, 1.0 + BattleTactics.terrain_mod("plains", tactic_name, 1, 1) * 4.0)
	var plains_mobile: int = 0
	var marsh_mobile: int = 0
	var marsh_defensive: int = 0
	var plains_defensive: int = 0
	var samples: int = 600
	for s in range(1, samples + 1):
		var tp: String = BattleTactics.ai_pick({"terrain": "plains", "seed": s * 97, "log": []}, 1, 1)
		var tm: String = BattleTactics.ai_pick({"terrain": "marsh", "seed": s * 97, "log": []}, 1, 1)
		if tp in ["charge", "flank"]:
			plains_mobile += 1
		if tm in ["charge", "flank"]:
			marsh_mobile += 1
		if tm in ["hold", "skirmish"]:
			marsh_defensive += 1
		if tp in ["hold", "skirmish"]:
			plains_defensive += 1
	check(plains_mobile_w > marsh_mobile_w and marsh_def_w > plains_def_w and plains_mobile > marsh_mobile and marsh_defensive > plains_defensive,
		"ai_pick weights tactics by terrain (plains mobile w=%.2f vs marsh w=%.2f; marsh hold/skirmish w=%.2f vs plains w=%.2f; samples plains mobile=%d vs marsh=%d; marsh hold/skirmish=%d vs plains=%d)" % [
			plains_mobile_w, marsh_mobile_w, marsh_def_w, plains_def_w, plains_mobile, marsh_mobile, marsh_defensive, plains_defensive])

	var vs_charge_counters: int = 0
	var vs_hold_counters: int = 0
	for s in range(1, 81):
		var pick_vs_charge: String = BattleTactics.ai_pick(
			{"terrain": "plains", "seed": s * 131, "log": [{"tactics": ["charge", "hold"]}]}, 1, 2)
		var pick_vs_hold: String = BattleTactics.ai_pick(
			{"terrain": "plains", "seed": s * 131, "log": [{"tactics": ["hold", "charge"]}]}, 1, 2)
		if pick_vs_charge in ["hold", "feint"]:
			vs_charge_counters += 1
		if pick_vs_hold in ["flank", "skirmish"]:
			vs_hold_counters += 1
	check(vs_charge_counters > 25 and vs_hold_counters > 25,
		"ai_pick adapts to enemy's last tactic (vs charge=%d, vs hold=%d)" % [vs_charge_counters, vs_hold_counters])

	# 5. Modifiers bounds and commander tactician scaling (0..MAX_TACTICIAN_BONUS).
	check(is_equal_approx(BattleTactics.tactician_bonus(0), 0.0), "tactician 0 gives +0% bonus")
	check(is_equal_approx(BattleTactics.tactician_bonus(5), BattleTactics.MAX_TACTICIAN_BONUS * 0.5), "tactician 5 gives half max bonus")
	check(is_equal_approx(BattleTactics.tactician_bonus(10), BattleTactics.MAX_TACTICIAN_BONUS), "tactician 10 gives max bonus")
	check(is_equal_approx(BattleTactics.tactician_bonus(15), BattleTactics.MAX_TACTICIAN_BONUS), "tactician bonus is capped at MAX_TACTICIAN_BONUS")

	var rng_u := RandomNumberGenerator.new()
	rng_u.seed = 42
	var off_low: Unit = Factory.make_troop(rng_u, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 2)
	off_low.role = "officer"
	off_low.skills["tactician"] = 0
	var off_high: Unit = Factory.make_troop(rng_u, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 2)
	off_high.role = "officer"
	off_high.skills["tactician"] = 10
	check(BattleTactics.commander_tactician(null, [off_low], 0) == 0, "commander_tactician reads 0")
	check(BattleTactics.commander_tactician(null, [off_low, off_high], 0) == 10, "commander_tactician picks best officer tactician skill")

	var st_low: Dictionary = {
		"round": 1, "terrain": "hills", "tactics": ["charge", "hold"],
		"last_fought": [[off_low], [off_low]]
	}
	var st_high: Dictionary = {
		"round": 1, "terrain": "hills", "tactics": ["charge", "hold"],
		"last_fought": [[off_low], [off_high]]
	}
	var mods_low: Dictionary = BattleTactics.modifiers(null, st_low)
	var mods_high: Dictionary = BattleTactics.modifiers(null, st_high)
	var m0_low: Dictionary = mods_low["side0"]
	var m1_low: Dictionary = mods_low["side1"]
	var m1_high: Dictionary = mods_high["side1"]
	check(float(m1_low["defence"]) > float(m0_low["defence"]) and float(m1_low["attack"]) > float(m0_low["attack"]),
		"defender holding on hills vs charge gets higher attack and defence multipliers")
	check(float(m1_high["defence"]) > float(m1_low["defence"]) and float(m1_high["attack"]) > float(m1_low["attack"]),
		"commander tactician skill increases side's tactical multipliers")
	for side_key in ["side0", "side1"]:
		var sm: Dictionary = mods_high[side_key]
		for k in ["attack", "defence", "morale"]:
			var v: float = float(sm[k])
			check(v >= BattleTactics.MIN_MULT and v <= BattleTactics.MAX_MULT,
				"modifier %s.%s (%.3f) within bounds" % [side_key, k, v])

	var st_carry: Dictionary = {"round": 1, "terrain": "plains", "last_fought": [[off_low], [off_high]]}
	BattleTactics.setup_round(null, st_carry)
	check(str((st_carry["tactics"] as Array)[0]) == "hold", "round 1 player order defaults to hold when unpicked")
	st_carry["last_tactics"] = ["flank", "charge"]
	st_carry["round"] = 2
	BattleTactics.setup_round(null, st_carry)
	check(str((st_carry["tactics"] as Array)[0]) == "flank", "round 2 player order carries over last_tactics[0]")

	var orig_str: int = int(off_low.attrs["STR"])
	var orig_courage: int = int(off_low.personality.get("courage", 50))
	off_low.attrs["TOU"] = 80
	var test_sim := BattleSim.new()
	test_sim.setup([off_low], [off_high], 123, {"terrain": "hills", "map": "small"})
	var f0: Fighter = test_sim.fighters[0]
	var init_before: float = f0.initiative
	var courage_before: float = f0.tr_courage
	BattleTactics.apply_sim(test_sim, mods_high)
	var morale_once: float = f0.morale
	var morale_start_once: float = f0.morale_start
	BattleTactics.apply_sim(test_sim, mods_high)
	check(int(off_low.attrs["STR"]) == orig_str and int(off_low.personality.get("courage", 50)) == orig_courage,
		"Unit.attrs and Unit.personality are never mutated in place")
	check(is_equal_approx(f0.morale, morale_once) and is_equal_approx(f0.morale_start, morale_start_once),
		"apply_sim does not compound morale/morale_start when called twice")
	check(is_equal_approx(f0.initiative, init_before) and is_equal_approx(f0.tr_courage, courage_before),
		"apply_sim preserves fighter initiative and tr_courage")
	check(float(f0.alv["endurance"][0]) < 150.0,
		"low attribute (TOU=80) is scaled with maxi(1, ...) rather than floored at 200")

	# 6. ClashRounds integration: off-screen AI battles log tactics and tactic_note.
	var cr_rng := RandomNumberGenerator.new()
	cr_rng.seed = 901
	var cr: Dictionary = ClashRounds.resolve(220, 220, 12.0, 12.0, 4, 4, cr_rng, 70.0, 70.0, "forest", 6, 2)
	var cr_log: Array = cr.get("log", [])
	check(not cr_log.is_empty(), "ClashRounds produced round log entries")
	if not cr_log.is_empty():
		var first_entry: Dictionary = cr_log[0]
		var ct: Variant = first_entry.get("tactics", [])
		check(ct is Array and (ct as Array).size() == 2 and BattleTactics.TACTICS.has(str((ct as Array)[0])) and BattleTactics.TACTICS.has(str((ct as Array)[1])),
			"ClashRounds round entry records both sides' tactics")
		check(str(first_entry.get("tactic_note", "")).length() > 5,
			"ClashRounds round entry records tactic_note")

	# 7. Real round battle with BattleTactics.choose(Game, 0, "hold").
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-30000, -30000)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 4)
	if not await DevTools.start_world(tree, "user://tactics041-test.json"):
		check(false, "the start world loaded for round battle")
		return _finish()
	DevTools.set_round_size(10)
	var want: int = BattleRounds.round_size + 4
	var best: String = ""
	var best_pop: int = 0
	for tid in Game.world["towns"]:
		var t: Dictionary = Game.world["towns"][tid]
		if int(t.get("econ", {}).get("pop", 0)) > best_pop:
			var office: Dictionary = Dynasty.town_office(Game, str(tid))
			if bool(office.get("alive", false)) and bool(HouseOnboarding.begin(Game, str(tid), str(office.get("household_uid", ""))).get("ok", false)):
				best = str(tid)
				best_pop = int(t["econ"]["pop"])
				break
	check(best != "", "a ruling house was chosen for the round battle")
	if best == "":
		return _finish()
	Game.settings["guide_seen"] = true
	Game.goto("map")
	await frames(tree, 3)
	Game.location = best
	Mobilization.fund(Game, int(floor(float(Feudal._payer(Game).get("purse", 0.0)) * 0.9)))
	for row in Mobilization.household_candidates(Game).slice(0, 3):
		var er: Dictionary = Mobilization.enlist_household(Game, str(row["person_uid"]))
		if bool(er.get("ok", false)) and er.get("unit") is Unit:
			var hu: Unit = er["unit"]
			hu.skills["tactician"] = 6
	var quote: Dictionary = Mobilization.quote(Game, best, want)
	if bool(quote.get("ok", false)):
		Mobilization.muster(Game, best, want, quote["review"])
	var enemy_id: String = ""
	for key in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][key]
		if band.get("faction", "") != Game.world["towns"][best].get("faction", "") and Army.is_people_band(band) and not (band.get("units", []) as Array).is_empty() and not Monsters.suspended_band(band) and str(band.get("kind", "")) != "caravan":
			enemy_id = str(key)
			break
	check(enemy_id != "", "an enemy band exists for the round battle")
	if enemy_id == "":
		return _finish()
	var wb: Dictionary = Game.world["warbands"][enemy_id]
	var erng := RandomNumberGenerator.new()
	erng.seed = 77
	var extra: Array = Factory.make_warband(erng, str(wb["faction"]), maxi(0, want - (wb["units"] as Array).size()))
	for u in extra:
		u.home_town = str(wb.get("home", ""))
	(wb["units"] as Array).append_array(extra)

	BattleTactics.choose(Game, 0, "hold")
	Game.start_battle({"enemy": (wb["units"] as Array).duplicate(), "allies": [], "warband_id": enemy_id, "seed": 31, "terrain": "hills", "map": "small"})
	await frames(tree, 6)
	check(BattleRounds.active(Game), "round battle is active")
	if BattleRounds.active(Game):
		BattleTactics.choose(Game, 0, "hold")
		Game.pending_battle["rounds"]["morale"] = [BattleRounds.BREAK_MORALE + 1.0, BattleRounds.BREAK_MORALE + 1.0]
	var b: Node = main.current
	check(b != null and "sim" in b and b.sim != null, "battle scene sim is running")
	if b != null and "sim" in b and b.sim != null:
		b.skip_to_end()
		var waited: int = 0
		while not b.result_shown and waited < 6000:
			await tree.process_frame
			waited += 1
		check(bool(b.result_shown), "round 1 finished")
		var st: Dictionary = Game.pending_battle.get("rounds", {})
		var rlog: Array = st.get("log", [])
		check(not rlog.is_empty(), "round log has an entry")
		if not rlog.is_empty():
			var d: Dictionary = rlog[-1]
			var dt: Variant = d.get("tactics", [])
			var dnote: String = str(d.get("tactic_note", ""))
			check(dt is Array and (dt as Array).size() == 2 and str((dt as Array)[0]) == "hold" and BattleTactics.TACTICS.has(str((dt as Array)[1])),
				"round log entry records d['tactics'] with side 0 'hold' (got %s)" % [str(dt)])
			check(dnote.length() > 5 and dnote.to_lower().contains("shield wall"),
				"round log entry records readable d['tactic_note'] (got '%s')" % dnote)
		var over: bool = bool(st.get("over", false))
		b._after_round_panel(over)
		await frames(tree, 4)
		if over:
			b.finish()
			await frames(tree, 4)

	return _finish()
