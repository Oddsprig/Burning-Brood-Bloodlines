extends RefCounted
const NativeForces = preload("res://tests/class_d_registered_forces.gd")
var bad_home_details: Array[Dictionary] = []
const Observations = preload("res://tests/class_d_observations.gd")
const MONSTER_PERF_MAP: GDScript = preload("res://campaign/world_map.gd")
const MONSTER_PERF_SCENE: PackedScene = preload("res://campaign/world_map.tscn")
var _perf_map: Node
var _perf_process_enabled: Dictionary = {}
const MONSTER_PERF_START_BANDS: int = 96
var _perf_min_warbands: int = 0
var _perf_observation: Dictionary = {}
var failed_assertions: Array[String] = []
var battle_evidence: Array[Dictionary] = []
var asset_transfers: Array[Dictionary] = []
## Monsters wave 1 on the campaign map (docs/specs/monsters-wave1.md, blocking tests):
## - militia spawns per town with home town and faction, sized by the town, rebuilds after losses,
##   auto-fights threats near town, and joins a defend battle as allies (pay bonus for sparing them)
## - every non-monster map unit has a home (town, or a bandit camp for outlaws) and a faction; deserters keep theirs
## - a bandit camp re-equips from its stock (and its gangs bring raided cargo home)
## - spawn density scales with wild area; rarity weights spawns and new types start rare
## - lair / hunt / bounty contracts: lair battle terrain, trophies auto-sold, lair cleared, contract paid
## - save/load round trip of the new world state; on_time per map frame stays cheap

var fails: int = 0
var _part: String = ""
var _deadline_msec: int = 0
var _budget_failed: bool = false
const PARTS: Array[String] = ["initial", "campaign", "camp", "militia", "lair", "hunt_bounty", "defend", "persistence", "perf", "upgrade"]
## Opt-in only; held for the later frame-gate version, never enumerate in the v0.100 run list.
const HELD_PARTS: Array[String] = ["frame_budget_later"]

func check(ok: bool, msg: String) -> void:
	if not ok:
		failed_assertions.append(msg)
		print("FAIL: ", msg)
		fails += 1

func _homes_ok(w: Dictionary) -> int:
	var bad: int = 0
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.is_monster_band(wb):
			check(wb["faction"] == "beasts", "monster band %s faction %s" % [wid, wb["faction"]])
			continue
		var fid: String = wb["faction"]
		var home: String = wb["home"]
		var ok: bool = DB.factions.has(fid)
		if w["towns"].has(home):
			ok = ok and w["towns"][home]["faction"] == fid
		elif w["lairs"].has(home):
			ok = ok and w["lairs"][home]["kind"] == "bandit_camp" and fid == "outlaws"
		else:
			ok = false
		for u in wb["units"]:
			# economy spec 2: an outlaw's band lives at its camp, the man himself comes from a family in a town
			var uh: bool = u.home_town == home or (fid == "outlaws" and w["towns"].has(u.home_town))
			# v0.100: a realm's patrols and raiders muster from any of its towns (the realm's field army)
			uh = uh or (fid != "outlaws" and str(w["towns"].get(u.home_town, {}).get("faction", "")) == fid)
			ok = ok and uh and u.faction == fid
		var native: Dictionary = NativeForces.registered(Game, wb)
		ok = ok and bool(native["ok"])
		if not ok:
			bad_home_details.append({"id": wid, "kind": wb["kind"], "home": home, "faction": fid,
				"binding_error": native.get("reason", ""), "units": wb["units"]})
			bad += 1
			var other_home: int = 0
			var other_faction: int = 0
			for u in wb["units"]:
				if u.home_town != home: other_home += 1
				if u.faction != fid: other_faction += 1
			print("  bad home: %s %s %s home '%s' (home's realm %s; %d of %d men from another town, %d of another realm)" % [wid, wb["kind"], fid, home,
				str(w["towns"].get(home, {}).get("faction", "-")), other_home, (wb["units"] as Array).size(), other_faction])
	return bad

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	if not _budget_failed:
		check(false, "monster part " + _part + " exceeded 150 seconds; incomplete work is a failure")
		_budget_failed = true
	return false

## Actual observations are never a golden reference or an assigned battle result.
func _battle_snapshot(sim: BattleSim) -> Dictionary:
	var fighters: Array[Dictionary] = []
	for fighter: Fighter in sim.fighters:
		fighters.append({"unit": Game._serialize(fighter.unit), "side": fighter.side, "state": fighter.state,
			"cell": fighter.cell, "logs": Game._serialize(fighter.log)})
	return {"winner": sim.winner, "tick": sim.tick, "over": sim.is_over(),
		"events": Game._serialize(sim.events), "fighters": fighters}

## Settle a real native battle; no assigned winner, casualty flag, or resurrection.
func _fight_pending() -> Dictionary:
	for round_index: int in BattleRounds.MAX_ROUNDS:
		if not _within_budget(): return {}
		var pending: Dictionary = Game.pending_battle
		var side0: Array = Game.deployed_units() + pending.get("allies", [])
		for dragon: Unit in pending.get("dragon_units", []):
			if DragonCombat.is_dragon_unit(Game, dragon) and not side0.has(dragon): side0.append(dragon)
		if pending.has("round_side0"): side0 = (pending["round_side0"] as Array).duplicate()
		var side1: Array = pending.get("enemy", [])
		check(not side0.is_empty() and not side1.is_empty(), "native contract battle needs both actual rosters")
		if fails > 0: return {}
		var screen: Variant = load("res://battle/battle.gd").new()
		var options: Dictionary = screen.battle_opts(pending, side0.size(), side1.size())
		options["dragon_riders"] = DragonCombat.battle_riders(Game, side0 + side1)
		var receipt: Dictionary = {"round": round_index, "seed": int(pending.get("seed", 1)),
			"pending_before": Game._serialize(pending), "company_before": Game._serialize(Game.company),
			"side0_before": Game._serialize(side0), "side1_before": Game._serialize(side1),
			"options": Game._serialize(options)}
		battle_evidence.append(receipt)
		var sim: BattleSim = BattleSim.new()
		sim.setup(side0, side1, int(pending.get("seed", 1)), options)
		var steps: int = 0
		while not sim.is_over() and steps < 4000:
			if not _within_budget():
				receipt["interrupted_sim"] = _battle_snapshot(sim)
				screen.free(); return {}
			sim.step()
			steps += 1
		receipt["sim"] = _battle_snapshot(sim)
		check(sim.is_over(), "native contract round must actually finish within 4000 ticks; tick=%d" % sim.tick)
		if fails > 0: screen.free(); return {}
		screen.sim = sim
		var outcome: Dictionary = screen.build_result()
		receipt["round_outcome"] = Game._serialize(outcome)
		screen.free()
		if BattleRounds.active(Game):
			BattleRounds.after_round(Game, outcome)
			if not bool(Game.pending_battle["rounds"].get("over", false)):
				BattleRounds.next_round(Game)
				continue
			outcome = BattleRounds.final_result(Game, outcome)
		receipt["campaign_outcome"] = Game._serialize(outcome)
		print("native %s contract battle: %d v %d, seed %d, tick %d, winner %d" %
			[_part, side0.size(), side1.size(), int(receipt["seed"]), sim.tick, int(outcome.get("winner", -1))])
		check(int(outcome.get("winner", -1)) == 0, "native fixture must actually win its contract battle")
		if fails > 0: return {}
		return outcome
	check(false, "native contract battle did not finish within the game's round limit")
	return {}

func run(_tree: SceneTree) -> int:
	fails = 0; failed_assertions.clear(); bad_home_details.clear()
	battle_evidence.clear(); asset_transfers.clear()
	_part = ""; _budget_failed = false
	var selected: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--monsters-part="): continue
		check(not selected, "select exactly one monster part per invocation")
		selected = true
		_part = argument.trim_prefix("--monsters-part=")
	check(selected, "select exactly one monster part per invocation: --monsters-part=<part>; no-argument invocation is incomplete")
	check(_part in PARTS or _part in HELD_PARTS, "unknown monster part: " + _part)
	if fails > 0: return fails
	_deadline_msec = Time.get_ticks_msec() + 150000
	var previous_next_world: bool = Monsters.new_world_creatures
	var had_setting: bool = Game.settings.has("creatures_enabled")
	var previous_setting: Variant = Game.settings.get("creatures_enabled", null)
	Monsters.new_world_creatures = true
	Game.settings["creatures_enabled"] = true
	var result: int = await _run_enabled()
	if not _within_budget(): result += 1
	Monsters.new_world_creatures = previous_next_world
	if had_setting: Game.settings["creatures_enabled"] = previous_setting
	else: Game.settings.erase("creatures_enabled")
	# Every selected part leaves a receipt; the external process result/time remains authoritative.
	if not Observations.write("campaign_monsters_" + _part, {"evidence_kind": "native_observation_not_reference",
		"assertion_result": result, "failed_assertions": failed_assertions, "part": _part, "day": Game.day,
		"creatures_enabled": Game.world.get("creatures_enabled", false), "company": Game.company,
		"warband_ids": Game.world.get("warbands", {}).keys(), "lairs": Game.world.get("lairs", {}),
		"bad_homes": bad_home_details, "battles": battle_evidence, "asset_transfers": asset_transfers,
		"pending_battle": Game.pending_battle, "last_result": Game.last_result, "contract": Game.contract}):
		result += 1
	if not _within_budget(): result += 1
	return result

func _run_enabled() -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	if not _within_budget(): return fails
	Game.new_game(777)
	if not _within_budget(): return fails
	check(bool(Game.world.get("creatures_enabled", false)) and Monsters.campaign_creatures_enabled(), "native fixture world must actually enable creatures")
	if fails > 0: return fails
	var seat: String = DevTools.choose_house(Game, func(choice: Dictionary):
		return str(Dynasty.person(Game, str(choice["ruler_uid"])).get("race", "")) == "human")
	check(seat != "", "native monster fixture needs an actual human ruling house")
	if seat == "": return fails
	var raised: int = DevTools.raise_army(Game, seat, 6)
	check(raised == 6 and Game.company.size() == 6, "exactly six native registered residents must muster")
	if fails > 0: return fails
	Diplomacy.init_world(Game)
	var w: Dictionary = Game.world
	check(not w["towns"].is_empty() and not w.get("militia", {}).is_empty(), "native world has actual towns and militia IDs")
	if fails > 0: return fails
	# Actual company payroll: each selected part simulates only these native campaign days.
	var funded_days: int = int({"campaign": 15, "militia": 12, "persistence": 4, "perf": 2, "frame_budget_later": 2}.get(_part, 0))
	var need: int = 0
	for unit: Unit in Game.company: need += unit.wage * funded_days
	if need > Game.gold:
		var funding: Dictionary = Mobilization.fund(Game, need - Game.gold)
		check(bool(funding.get("ok", false)), "native house funding refused the actual company wage bill: " + str(funding.get("reason", "")))
	check(Game.gold >= need, "native household could not actually fund the company for the selected campaign part")
	if fails > 0: return fails
	match _part:
		"initial": return _initial(w, rng)
		"campaign": return _campaign(w, rng)
		"camp": return _camp(w, rng)
		"militia": return _militia(w, rng)
		"lair": return _lair(w, rng)
		"hunt_bounty": return _hunt_bounty(w, rng)
		"defend": return _defend(w, rng)
		"persistence": return _persistence(w, rng)
		"perf": return await _perf(w, rng)
		"frame_budget_later": return await _perf(w, rng)
		"upgrade": return _upgrade(w, rng)
	check(false, "monster part dispatcher did not execute a selected part")
	return fails

func _initial(w: Dictionary, rng: RandomNumberGenerator) -> int:
	# ---------------------------------------------------------------- militia per town
	var n_mil: int = 0
	for tid in w["towns"]:
		if not _within_budget(): return fails
		var t: Dictionary = w["towns"][tid]
		var wb: Dictionary = Militia.band_of(Game, tid)
		check(not wb.is_empty(), "town %s has no militia" % t["name"])
		if wb.is_empty(): return fails
		var native: Dictionary = NativeForces.registered(Game, wb)
		check(bool(native["ok"]), "initial native militia binding: " + str(native.get("reason", "")))
		if fails > 0: return fails
		n_mil += 1
		check(wb["kind"] == "militia" and wb["home"] == tid and wb["faction"] == t["faction"], "militia of %s: home/faction" % t["name"])
		check((wb["units"] as Array).size() == Militia.target_size(t), "militia of %s sized %d, want %d" % [t["name"], (wb["units"] as Array).size(), Militia.target_size(t)])
		for u in wb["units"]:
			if not _within_budget(): return fails
			check(u.home_town == tid and u.faction == t["faction"], "militiaman without home/faction")
	print("militia: %d towns, %d bands; e.g. %s" % [w["towns"].size(), n_mil, CampaignWorld.scout_report(Game, w["militia"].values()[0])])
	# ---------------------------------------------------------------- lairs and camps at start
	var lairs: Dictionary = w["lairs"]
	var wild: int = Lairs.wild_count(w)
	print("wild cells %d -> target lairs %d, camps %d; placed %d lairs/camps: %s" % [wild, Lairs.target_lairs(wild), Lairs.target_camps(wild),
		lairs.size(), str(lairs.values().map(func(l): return "%s@%s" % [l["kind"], CampaignWorld.terrain_at(w, l["pos"])]))])
	check(Lairs.count(w, true) >= 1, "no bandit camp")
	check(Lairs.count(w, false) >= 1, "no creature lair")
	for lid in lairs:
		if not _within_budget(): return fails
		var l: Dictionary = lairs[lid]
		check(CampaignWorld.terrain_char_at(w, l["pos"]) in ["f", "s", "h", "b"], "lair %s not in the wilds" % lid)
		var tdist: float = INF
		for tid in w["towns"]:
			if not _within_budget(): return fails
			tdist = minf(tdist, (w["towns"][tid]["pos"] as Vector2).distance_to(l["pos"]))
		check(tdist > WorldGen.CELL * 5, "lair %s too close to a town (%.0f px)" % [lid, tdist])
	# ---------------------------------------------------------------- spawn density scales with wild area
	var w2: Dictionary = {"seed": w["seed"], "terrain": (w["terrain"] as String).replace("f", "g").replace("s", "g"), "towns": w["towns"]}
	var wild2: int = Lairs.wild_count(w2)
	var t1: int = Lairs.target_lairs(wild)
	var t2: int = Lairs.target_lairs(wild2)
	print("density: wild %d -> %d lairs; forests cleared, wild %d -> %d lairs" % [wild, t1, wild2, t2])
	check(wild2 < wild and t2 < t1, "fewer wilds should mean fewer lairs")
	check(Lairs.target_lairs(wild * 2) >= t1 and Lairs.target_lairs(0) == 0, "lair target not monotonic in wild area")
	Lairs.wild_count(w)   # restore the cache for the real map
	# rarity weights spawns, new types start rare
	var st: Dictionary = Monsters.state(w)
	var bear_unlock: float = float(st["unlocked"].get("bear", Game.day))
	check(is_equal_approx(Monsters.weight(w, "bear", bear_unlock), float(Creatures.rarity_info("rare")["weight"])), "a new type should start rare")
	check(Monsters.weight(w, "wolf", Game.day + 100.0) > Monsters.weight(w, "bear", Game.day + 100.0), "common should outweigh uncommon")
	if fails == 0: _registered_rebase(w, rng)
	return fails

## Rebase one whole native field force; its people retain their own registered residences.
func _registered_rebase(w: Dictionary, rng: RandomNumberGenerator) -> void:
	var ids: Array = w["warbands"].keys()
	var town_ids: Array = w["towns"].keys()
	ids.sort(); town_ids.sort()
	var source: Dictionary = {}
	var destination: Dictionary = {}
	for id: String in ids:
		if not _within_budget(): return
		var band: Dictionary = w["warbands"][id]
		if band["kind"] not in ["patrol", "raider"] or (band["units"] as Array).is_empty() or Supplies.weight(Supplies.stores(band)) <= 0.0: continue
		for tid: String in town_ids:
			var town: Dictionary = w["towns"][tid]
			if town["faction"] == band["faction"] and tid != band["home"] and tid != band["units"][0].home_town:
				source = band; destination = town
				break
		if not source.is_empty(): break
	check(not source.is_empty(), "residence fixture needs a native field force and a second town of its realm")
	if source.is_empty(): return
	var valid: Dictionary = NativeForces.registered(Game, source)
	check(bool(valid["ok"]), "source field force has actual registered people: " + str(valid.get("reason", "")))
	if fails > 0: return
	var homes: Dictionary = {}
	for unit: Unit in source["units"]: homes[unit.uid] = [unit.home_town, unit.family]
	var people_before: int = NativeForces.population(Game)
	var coin_before: float = Barge.holdings(Game)
	# Preserve the real rations through the native transfer before removal books any losses.
	var expected_stores: Dictionary = Supplies.stores(source).duplicate()
	var transit: Dictionary = {"units": source["units"]}
	var taken: Dictionary = Supplies.take(transit, source)
	for good: String in expected_stores:
		check(int(taken.get(good, 0)) == int(expected_stores[good]), "whole-force rebase carries every actual ration")
	if fails > 0: return
	var extra: Dictionary = source.duplicate()
	extra.erase("id")
	extra.erase("pos")
	extra["home"] = destination["id"]
	extra["stores"] = Supplies.stores(transit)
	CampaignWorld.remove_warband(Game, str(source["id"]))
	var new_id: String = CampaignWorld.spawn_warband(Game, str(source["faction"]), destination["pos"],
		(source["units"] as Array).size(), str(source["kind"]), rng, extra)
	check(new_id != "" and w["warbands"].has(new_id), "native whole-force rebase returns an actual band")
	if new_id == "" or not w["warbands"].has(new_id): return
	var rebased: Dictionary = w["warbands"][new_id]
	check(rebased["home"] == destination["id"] and rebased["pos"] == CampaignWorld.nearest_passable(w, destination["pos"])
		and (rebased["units"] as Array).size() == homes.size(),
		"rebasing keeps the complete native force at its real destination")
	for unit: Unit in rebased["units"]:
		check(homes.has(unit.uid) and homes[unit.uid] == [unit.home_town, unit.family],
			"rebasing preserves each actual person's hometown and family")
	check(Supplies.stores(rebased) == expected_stores, "native whole-force rebase preserves all ration stores")
	var after: Dictionary = NativeForces.registered(Game, rebased)
	check(bool(after["ok"]), "rebased force retains native person bindings: " + str(after.get("reason", "")))
	check(NativeForces.population(Game) == people_before and absf(Barge.holdings(Game) - coin_before) < 0.01,
		"whole-force rebase conserves people and money")
	check(_homes_ok(w) == 0, "all homes remain valid after native whole-force rebasing")

func _campaign(w: Dictionary, rng: RandomNumberGenerator) -> int:
	var lairs: Dictionary = w["lairs"]
	var wild: int = Lairs.wild_count(w)
	var t1: int = Lairs.target_lairs(wild)
	# ---------------------------------------------------------------- simulate: homes, gradual lairs, militia fights
	for i in 60:
		if not _within_budget(): return fails
		Game.advance_time(0.25, false)
		w["encounter"] = ""
	print("after 15 days: %d warbands, %d lairs (target %d), log tail %s" % [w["warbands"].size(), lairs.size(), t1 + Lairs.target_camps(wild), w["log"].slice(-4)])
	check(Lairs.count(w, false) <= t1 and Lairs.count(w, true) <= Lairs.target_camps(wild), "more lairs than the density allows")
	var kinds: Dictionary = {}
	for wid in w["warbands"]:
		if not _within_budget(): return fails
		kinds[w["warbands"][wid]["kind"]] = int(kinds.get(w["warbands"][wid]["kind"], 0)) + 1
	print("warband kinds: ", kinds)
	check(_homes_ok(w) == 0, "every non-monster map unit needs a home and a faction")
	# Option A: a real failed payroll establishes the separate breakaway prerequisite.
	_prepare_soldier_deserters(w)
	if fails > 0: return fails
	var soldiers_before: Dictionary = {}
	var bands_before: Dictionary = {}
	for source: Dictionary in w["warbands"].values():
		if not Army.is_field(source): continue
		bands_before[source["id"]] = {"stores": Supplies.stores(source).duplicate(), "hungry": int(source.get("hungry", 0))}
		for soldier: Unit in source["units"]:
			var family: Dictionary = People.fam_of(w["towns"].get(soldier.home_town, {}), soldier.family)
			soldiers_before[soldier.uid] = {"unit": soldier, "source": source["id"], "equip": soldier.equip.duplicate(),
				"home": soldier.home_town, "family": soldier.family, "unpaid": soldier.unpaid_days,
				"serve": (family.get("serve", {}) as Dictionary).duplicate()}
	var people_before: int = NativeForces.population(Game)
	var coin_before: float = Barge.holdings(Game)
	var audit_before: Dictionary = WorldAudit.census(Game)
	var did: String = ""
	for attempt in 10:   # v0.100: men must agree to desert; a draw can find nobody willing
		if not _within_budget(): return fails
		did = Bandits.spawn_deserters(Game, rng)
		if did != "": break
	check(did != "", "a deserter band formed")
	if did != "":
		var dwb: Dictionary = w["warbands"][did]
		check(dwb["deserter"] and w["towns"][dwb["home"]]["faction"] == dwb["faction"], "deserters keep town and faction")
		check(Monsters.band_hostile(Game, dwb) and not CampaignWorld.is_hostile(Game, dwb["faction"]), "deserters hostile while their faction is not")
		_check_soldier_deserters(w, dwb, soldiers_before, bands_before)
	check(NativeForces.population(Game) == people_before and absf(Barge.holdings(Game) - coin_before) < 0.01,
		"breakaway conserves population and all coin")
	var audit_after: Dictionary = WorldAudit.census(Game)
	var audit: Dictionary = WorldAudit.compare(audit_before, audit_after)
	check(bool(audit["ok"]), "breakaway conserves audited coin, goods, rations and item identities: " + str(audit))
	check(audit_before["ration_book"] == audit_after["ration_book"], "moving rations books no creation or loss")
	check(_homes_ok(w) == 0, "deserter homes")
	return fails

## Empty a real faction purse into its town, then let the actual payroll record the missed wage.
func _prepare_soldier_deserters(w: Dictionary) -> void:
	var ids: Array = w["warbands"].keys()
	ids.sort()
	var source: Dictionary = {}
	for id: String in ids:
		var band: Dictionary = w["warbands"][id]
		var faction: String = str(band["faction"])
		if not Army.is_field(band) or DB.factions[faction]["race"] != "human" or CampaignWorld.is_hostile(Game, faction):
			continue
		for soldier: Unit in band["units"]:
			var town: Dictionary = w["towns"].get(soldier.home_town, {})
			var family: Dictionary = People.fam_of(town, soldier.family)
			var person: Array = Persons.by_uid(family, soldier.uid)
			if not soldier.dead and not person.is_empty() and str(person[4]) == "army" and town.get("faction", "") == faction and soldier.unpaid_days + 1 < int(Army.A()["desert_days"]):
				source = band
				break
		if not source.is_empty(): break
	check(not source.is_empty(), "soldier deserters need a real nonhostile human field army before unpaid timeout")
	if source.is_empty(): return
	var fixture: Variant = load("res://tests/test_econ_army.gd").new()
	var before: float = Barge.holdings(Game)
	fixture._empty_faction(str(source["faction"]))
	var payroll: Dictionary = Army.pay_units(Game, source["units"], {"kind": "faction", "fac": w["factions"][source["faction"]]},
		"army", Army.cul_of_faction(str(source["faction"])))
	check(int(payroll["unpaid"]) > 0 and absf(Barge.holdings(Game) - before) < 0.01,
		"native unfunded payroll must create a missed wage without creating or losing coin")

func _check_soldier_deserters(w: Dictionary, band: Dictionary, soldiers: Dictionary, sources: Dictionary) -> void:
	var source_id: String = str(band.get("deserted_from", ""))
	check(sources.has(source_id), "deserters identify their actual former field army")
	if not sources.has(source_id): return
	var original: Dictionary = sources[source_id]
	check(Supplies.weight(Supplies.stores(band)) <= Supplies.capacity(Supplies.men(band)) + 0.00001,
		"breakaway rations stay within the actual soldiers' carry capacity")
	check(int(band.get("hungry", 0)) == int(original["hungry"]), "breakaway retains the source soldiers' actual hungry-day history")
	var former: Dictionary = w["warbands"].get(source_id, {})
	var moved: Dictionary = {}
	var households: Dictionary = {}
	for soldier: Unit in band["units"]:
		check(soldiers.has(soldier.uid), "every deserter was already a serving soldier")
		if not soldiers.has(soldier.uid): continue
		var old: Dictionary = soldiers[soldier.uid]
		check(old["unit"] == soldier and old["source"] == source_id and old["equip"] == soldier.equip
			and old["home"] == soldier.home_town and old["family"] == soldier.family and old["unpaid"] == soldier.unpaid_days,
			"breakaway moves the same body, identity, kit, residence and unpaid history")
		check(not (former.get("units", []) as Array).has(soldier), "source army no longer owns the deserter")
		var family: Dictionary = People.fam_of(w["towns"][soldier.home_town], soldier.family)
		var person: Array = Persons.by_uid(family, soldier.uid)
		check(not person.is_empty() and str(person[4]) == "deserter" and str(Army.state(w)["roll"][str(soldier.uid)][2]) == "deserter",
			"person and army roll both retain the actual deserter service binding")
		var household: String = soldier.home_town + "/" + str(soldier.family)
		if not households.has(household): households[household] = {"family": family, "before": old["serve"], "count": 0}
		households[household]["count"] = int(households[household]["count"]) + 1
		if soldier.unpaid_days > 0:
			check(int(Persons.unpaid_memory(person, "army").get("days", -1)) == soldier.unpaid_days,
				"former unpaid army service remains in the person's memory")
		moved[soldier.uid] = true
	for row: Dictionary in households.values():
		check(int(row["family"]["serve"].get("army", 0)) == int(row["before"].get("army", 0)) - int(row["count"])
			and int(row["family"]["serve"].get("deserter", 0)) == int(row["before"].get("deserter", 0)) + int(row["count"]),
			"household service counts move exactly once from army to deserter")
	for soldier: Unit in band["units"]:
		check(soldier.squad < 0 or moved.has(soldier.squad), "deserter commands stay inside the breakaway band")
	var command: Dictionary = Army.rec(w, str(band["faction"]))
	for uid: Variant in command["posts"]:
		check(not moved.has(int(uid)), "former army posts no longer claim a deserter")
	check(not moved.has(int(w["factions"][band["faction"]].get("war_leader", {}).get("uid", -1))),
		"former faction no longer names a deserter as war leader")
	for soldier: Unit in Army.members(Game, str(band["faction"])):
		check(not moved.has(soldier.squad), "remaining army soldiers no longer report to deserters")
	for good: String in original["stores"]:
		var after: float = float(former.get("stores", {}).get(good, 0)) + float(Supplies.stores(band).get(good, 0))
		check(absf(after - float(original["stores"][good])) < 0.00001, "each actual carried ration is conserved: " + good)
	var restored: Dictionary = Game._deserialize(Game._serialize(band))
	check(restored["home"] == band["home"] and restored["stores"] == band["stores"] and restored["deserted_from"] == source_id,
		"native serializer retains deserter residence, exact rations and origin")
	for index: int in (band["units"] as Array).size():
		var saved: Unit = restored["units"][index]
		var live: Unit = band["units"][index]
		check(saved is Unit and saved.uid == live.uid and saved.family == live.family and saved.home_town == live.home_town
			and saved.unpaid_days == live.unpaid_days and saved.equip.size() == live.equip.size(),
			"native serializer retains each deserter body, family, kit and unpaid timer")

## Reuse conserved native volunteer/cash preparation without _funded_camp's extra roaming gang.
func _funded_camp(fixture: Variant) -> String:
	var w: Dictionary = Game.world
	var pay: float = float(Army.A()["wage"]["bandit"])
	var lid: String = ""
	var garrison_town: Dictionary = {}
	var human_town: Dictionary = {}
	var best: int = -1
	var ids: Array = w["lairs"].keys()
	ids.sort()
	for key: String in ids:
		if not _within_budget(): return ""
		var lair: Dictionary = w["lairs"][key]
		if str(lair.get("kind", "")) != "bandit_camp": continue
		var gtown: Dictionary = fixture._garrison_town(w, lair)
		var htown: Dictionary = fixture._nearest_econ_town(w, lair["pos"], "human")
		if gtown.is_empty() or htown.is_empty(): continue
		var resident: bool = w["warbands"].has(str(lair.get("resident", "")))
		var shared: bool = str(gtown["id"]) == str(htown["id"])
		var g_n: int = int(fixture._count_ready(gtown, pay))
		var h_n: int = g_n if shared else int(fixture._count_ready(htown, pay))
		var need_g: int = 0 if resident else (4 if shared else 1)
		var need_h: int = 1 if resident or not shared else 4
		if g_n >= need_g and h_n >= need_h and g_n + h_n > best:
			best = g_n + h_n
			lid = key; garrison_town = gtown; human_town = htown
	check(lid != "", "native camp needs genuine free garrison and gang volunteers")
	if lid == "": return ""
	var before_coin: float = Barge.holdings(Game)
	var before_people: int = NativeForces.population(Game)
	var ready_g: int = int(fixture._prepare_outlaws(garrison_town, pay))
	var ready_h: int = ready_g if str(garrison_town["id"]) == str(human_town["id"]) else int(fixture._prepare_outlaws(human_town, pay))
	var lair: Dictionary = w["lairs"][lid]
	var resident_id: String = str(lair.get("resident", ""))
	var existing: int = (w["warbands"][resident_id]["units"] as Array).size() if w["warbands"].has(resident_id) else 0
	check((ready_g > 0 or existing > 0) and ready_h > 0, "native camp preparation left no actual volunteers")
	if fails > 0: return ""
	var gang_sizes: Array = Creatures.tun("bandit_band", [3, 6])
	var target: float = pay * float((existing if existing > 0 else 3) + int(gang_sizes[1])) * 7.0
	var fac: Dictionary = w["factions"][human_town["faction"]]
	fixture._fund_faction(str(human_town["faction"]), maxf(0.0, target - float(lair.get("gold", 0.0))))
	fixture._move_cash(fac, "treasury", lair, "gold", maxf(0.0, target - float(lair.get("gold", 0.0))))
	check(int(fixture.fails) == 0 and float(lair.get("gold", 0.0)) >= target, "native camp needs the real seven-day volunteer offer bill")
	if fails > 0: return ""
	if not w["warbands"].has(resident_id):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 73
		lair["resident"] = CampaignWorld.spawn_warband(Game, "outlaws", lair["pos"], 3, "camp", rng, {"home": lid, "lair": lid, "anchor": lair["pos"]})
	check(w["warbands"].has(str(lair.get("resident", ""))), "native camp did not recruit actual resident volunteers")
	check(absf(Barge.holdings(Game) - before_coin) < 0.01 and NativeForces.population(Game) == before_people, "native camp preserves total coin and population")
	if fails > 0: return ""
	return lid

## Transfer an existing shop Item through the native stock API; no generated prize gear.
## Preview the native quality/material ordering before choosing a genuine upgrade.
func _camp_piece(w: Dictionary, garrison: Dictionary, lair: Dictionary, slot: String) -> Item:
	var threshold: float = 0.0
	for unit: Unit in garrison["units"]:
		var current: Item = unit.equip.get(slot, null)
		if current != null: threshold = maxf(threshold, current.value())
	for item: Item in lair["stock"]:
		if item.slot() == slot: threshold = maxf(threshold, item.value())
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid: String in ids:
		if not _within_budget(): return null
		var town: Dictionary = w["towns"][tid]
		var shop: Array = town.get("shop", [])
		for candidate: Item in shop:
			if candidate.slot() != slot or candidate.value() <= threshold: continue
			if slot == "main_hand" and bool(candidate.tmpl().get("two_handed", false)): continue
			var native_first: Item = candidate
			for other: Item in shop:
				if other.tid != candidate.tid or other.slot() != slot or other.quality < candidate.quality: continue
				if other.quality > native_first.quality or (other.quality == native_first.quality and other.material < native_first.material):
					native_first = other
			if native_first.value() <= threshold: continue
			var count_before: int = shop.size()
			var moved: Array = TownEcon.take_arms(town, 1, candidate.quality, slot, candidate.tid, false)
			check(moved.size() == 1 and moved[0] == native_first and shop.size() == count_before - 1 and not shop.has(native_first),
				"native camp prize must be the exact existing Item removed once from its actual shop")
			if fails > 0: return null
			asset_transfers.append({"source_town": tid, "destination_camp": lair["id"], "uid": native_first.uid,
				"slot": slot, "value": native_first.value(), "previous_max_value": threshold})
			return native_first
	return null

## The isolated camp part has no trade history; dispatch already bought stock through the native consignment path.
func _camp_caravan(w: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid: String in ids:
		if not _within_budget(): return {}
		var town: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(town) or Monsters.suspended_band({"faction": town["faction"], "kind": "caravan"}): continue
		var economy: Dictionary = town["econ"]
		var available: int = 0
		for family: Dictionary in economy["fams"]:
			available += Population.eligible_slots(economy, family, float(economy.get("day", 0)))
		if available < ArmsTrade.max_guards(town) + People.DRIVERS: continue
		var ordered: Array = (town.get("shop", []) as Array).duplicate()
		if ordered.is_empty(): continue
		ordered.sort_custom(func(a: Item, b: Item): return a.quality > b.quality if a.quality != b.quality else a.material < b.material)
		var piece: Item = ordered[0]
		if piece.mass() > Caravans.CAPACITY_KG or float(economy["treasury"]) < Economy.base_value(town, piece): continue
		for link: Dictionary in Caravans.trade_partners(w, town):
			if not _within_budget(): return {}
			var destination: Dictionary = w["towns"][str(link["id"])]
			var quote: Dictionary = Caravans.quote_trip(w, town, destination, rng, false, {"items": [piece], "goods": {}})
			if not bool(quote["ready"]): continue
			var coin_before: float = Barge.holdings(Game)
			var people_before: int = NativeForces.population(Game)
			var shop_before: int = (town["shop"] as Array).size()
			var cargo: Array = TownEcon.take_arms(town, 1)
			check(cargo.size() == 1 and cargo[0] == piece and (town["shop"] as Array).size() == shop_before - 1
				and not (town["shop"] as Array).has(piece), "camp consignment buys one exact existing shop Item")
			if fails > 0: return {}
			var id: String = Caravans.spawn(Game, tid, rng, str(destination["id"]), "", {"items": cargo, "goods": {}})
			check(id != "" and w["warbands"].has(id), "camp consignment needs native dispatch, route and hired crew")
			if id == "" or not w["warbands"].has(id): return {}
			var caravan: Dictionary = w["warbands"][id]
			var valid: Dictionary = NativeForces.record(Game, caravan)
			check(bool(valid["ok"]), "camp consignment native record: " + str(valid.get("reason", "")))
			check((caravan["cargo"]["items"] as Array).size() == 1 and caravan["cargo"]["items"][0] == piece
				and not (town["shop"] as Array).has(piece), "camp consignment retains the bought Item solely on its wagon")
			check(NativeForces.population(Game) == people_before and absf(Barge.holdings(Game) - coin_before) < 0.01,
				"native camp consignment preserves total population and coin")
			asset_transfers.append({"source_town": tid, "destination_caravan": id, "uid": piece.uid,
				"destination_town": destination["id"], "crew_count": (caravan.get("crew", []) as Array).size()})
			if fails > 0: return {}
			return caravan
	check(false, "camp plunder needs an existing shop Item, a funded native route and enough real crew")
	return {}

func _camp(w: Dictionary, rng: RandomNumberGenerator) -> int:
	var lairs: Dictionary = w["lairs"]
	# ---------------------------------------------------------------- bandit camp re-equips from its stock
	# Reuse only conserved native preparation; no helper test run or incidental gang.
	var camp_fixture: Variant = load("res://tests/test_econ_army.gd").new()
	var camp_id: String = _funded_camp(camp_fixture)
	check(int(camp_fixture.fails) == 0, "native camp funding / genuine volunteer prerequisites failed")
	if fails > 0: return fails
	check(camp_id != "" and lairs.has(camp_id), "no bandit camp with a garrison")
	if camp_id == "" or not lairs.has(camp_id): return fails
	if camp_id != "":
		var l: Dictionary = lairs[camp_id]
		check(w["warbands"].has(str(l.get("resident", ""))), "funded camp needs its actual resident ID")
		if not w["warbands"].has(str(l.get("resident", ""))): return fails
		var garrison: Dictionary = w["warbands"][l["resident"]]
		check(not (garrison["units"] as Array).is_empty(), "funded camp resident has actual registered volunteers")
		if (garrison["units"] as Array).is_empty(): return fails
		var prize: Item = _camp_piece(w, garrison, l, "body")
		var blade: Item = _camp_piece(w, garrison, l, "main_hand")
		check(prize != null and blade != null, "native camp re-arm needs existing shop body armor and a one-hand weapon worth more than its actual kit/stock")
		if prize == null or blade == null: return fails
		check((l["stock"] as Array).size() + 2 <= Bandits.STOCK_MAX, "native camp needs room for both actual transferred Items")
		if fails > 0: return fails
		(l["stock"] as Array).append_array([prize, blade])
		Bandits.daily(Game)
		var worn: bool = false
		var wielded: bool = false
		for u in garrison["units"]:
			if not _within_budget(): return fails
			worn = worn or u.equip.get("body", null) == prize
			wielded = wielded or u.equip.get("main_hand", null) == blade
		check(worn and wielded, "camp did not re-arm from its stock")
		check(not (l["stock"] as Array).has(prize) and not (l["stock"] as Array).has(blade), "both actual transferred pieces leave camp stock for real equipped owners")
		# One real native gang and an existing complete caravan own this cargo.
		var gid: String = Bandits.spawn_band(Game, camp_id, rng)
		check(gid != "" and w["warbands"].has(gid), "native camp gang needs an actual live force ID")
		if gid == "" or not w["warbands"].has(gid): return fails
		var gang: Dictionary = w["warbands"][gid]
		check(gang["home"] == camp_id and gang["faction"] == "outlaws", "camp gang home")
		var gang_binding: Dictionary = NativeForces.registered(Game, gang)
		check(bool(gang_binding["ok"]), "native camp gang binding: " + str(gang_binding.get("reason", "")))
		if fails > 0: return fails
		var caravan: Dictionary = {}
		var cargo_item: Item = null
		var ids: Array = w["warbands"].keys(); ids.sort()
		for id: String in ids:
			var candidate: Dictionary = w["warbands"][id]
			if str(candidate.get("kind", "")) != "caravan": continue
			var valid: Dictionary = NativeForces.record(Game, candidate)
			if not bool(valid["ok"]): continue
			var cargo: Array = candidate.get("cargo", {}).get("items", [])
			if cargo.is_empty() or (l["stock"] as Array).size() + cargo.size() > Bandits.STOCK_MAX: continue
			caravan = candidate; cargo_item = cargo[0]; break
		if caravan.is_empty() and (l["stock"] as Array).size() < Bandits.STOCK_MAX:
			caravan = _camp_caravan(w, rng)
			if not caravan.is_empty(): cargo_item = caravan["cargo"]["items"][0]
		check(not caravan.is_empty() and cargo_item != null, "camp plunder needs actual native caravan cargo and room for its complete Item load")
		if caravan.is_empty() or cargo_item == null: return fails
		var cargo_before: Array = (caravan["cargo"]["items"] as Array).duplicate()
		var stock_before: int = (l["stock"] as Array).size()
		check((l["stock"] as Array).count(cargo_item) == 0 and cargo_before.count(cargo_item) == 1, "actual cargo UID starts once in its caravan and outside the camp")
		if fails > 0: return fails
		Bandits.on_plunder(Game, gang, caravan)
		check((caravan["cargo"]["items"] as Array).is_empty() and (l["stock"] as Array).size() == stock_before + cargo_before.size(), "complete actual caravan cargo leaves its wagon and reaches the camp")
		for item: Item in cargo_before:
			check((l["stock"] as Array).count(item) == 1, "actual plunder Item UID %d enters the camp exactly once" % item.uid)
		var settled: String = JSON.stringify(Game._serialize(l["stock"]))
		Bandits.on_plunder(Game, gang, caravan)
		check(JSON.stringify(Game._serialize(l["stock"])) == settled and (l["stock"] as Array).count(cargo_item) == 1, "repeated actual empty-cargo settlement cannot duplicate plunder")
	return fails

func _militia(w: Dictionary, rng: RandomNumberGenerator) -> int:
	# ---------------------------------------------------------------- militia auto-fights and rebuilds
	var town_id: String = w["start_town"]
	var town: Dictionary = w["towns"][town_id]
	var mil: Dictionary = Militia.band_of(Game, town_id)
	var pack: String = CampaignWorld.spawn_warband(Game, "beasts", town["pos"] + Vector2(30, 0), 3, "beasts", rng,
		{"units": Creatures.make_group(rng, "wolf", 3), "creature": "wolf", "anchor": town["pos"], "roam": 50.0})
	check(pack != "" and w["warbands"].has(pack), "native enabled creature fixture did not produce the three-wolf pack")
	check(not mil.is_empty() and not (mil.get("units", []) as Array).is_empty(), "gate defence needs actual native militia")
	if fails > 0: return fails
	var mil_n0: int = (mil["units"] as Array).size()
	Militia.tick(Game, rng)
	check(not w["warbands"].has(pack) or (mil["units"] as Array).size() < mil_n0, "militia ignored wolves at the gate")
	print("militia vs wolves at %s: pack %s, militia %d -> %d; %s" % [town["name"], "gone" if not w["warbands"].has(pack) else "won", mil_n0, (mil["units"] as Array).size(), w["log"][-1]])
	if w["warbands"].has(pack):
		CampaignWorld.remove_warband(Game, pack)
	# Release only the removed fixture defenders through native service release.
	var removed_militia: Array = (mil["units"] as Array).slice(1)
	for unit: Unit in removed_militia:
		if not _within_budget(): return fails
		var family: Dictionary = People.fam_of(town, unit.family)
		var person: Array = Persons.by_uid(family, unit.uid) if not family.is_empty() else []
		check(not person.is_empty(), "removed native militia must resolve its actual service person")
		if person.is_empty(): return fails
		Horses.return_mount(Game, unit)
		ArmsTrade.kit_home(Game, unit)
		People.release(town, unit.family, str(person[4]), unit.uid)
		(mil["units"] as Array).erase(unit)
	var peak: int = (mil["units"] as Array).size()
	for d in 12:
		if not _within_budget(): return fails
		Game.advance_time(1.0, true)
		peak = maxi(peak, (mil["units"] as Array).size())   # (it may lose men to fights meanwhile)
	check(peak >= 4, "militia did not rebuild")
	print("militia rebuilt to a peak of %d of %d in 12 days (now %d)" % [peak, Militia.target_size(town), (mil["units"] as Array).size()])
	return fails

func _lair(w: Dictionary, rng: RandomNumberGenerator) -> int:
	var lairs: Dictionary = w["lairs"]
	# ---------------------------------------------------------------- lair contract: choke-point map, trophies, cleared lair, pay
	var den: String = ""
	for lid in lairs:
		if not _within_budget(): return fails
		# (a lair near a town that hires the company: orcs and goblins start hostile to it, -60, Douglas)
		var nt: Dictionary = w["towns"][CampaignWorld.nearest_town(w, lairs[lid]["pos"])]
		if lairs[lid]["kind"] != "bandit_camp" and w["warbands"].has(String(lairs[lid]["resident"])) \
				and Diplomacy.contracts_allowed(Game, nt["faction"]):
			den = lid
	if den == "":
		den = Monsters.new_lair(Game, rng)
	check(den != "" and lairs.has(den), "native enabled-world lair fixture returned no real lair ID")
	if den == "" or not lairs.has(den): return fails
	var dl: Dictionary = lairs[den]
	var resident: String = dl["resident"]
	check(resident != "" and w["warbands"].has(resident), "native lair has no live resident force")
	if resident == "" or not w["warbands"].has(resident): return fails
	check(not (w["warbands"][resident]["units"] as Array).is_empty(), "native lair resident has an actual creature roster")
	if (w["warbands"][resident]["units"] as Array).is_empty(): return fails
	var near_town: String = CampaignWorld.nearest_town(w, dl["pos"])
	check(w["towns"].has(near_town) and Diplomacy.contracts_allowed(Game, w["towns"].get(near_town, {}).get("faction", "")), "native lair needs a real eligible employer")
	if fails > 0: return fails
	# Each part starts with six residents, not an army proven able to clear a den.
	# Raise one ordinary native group before departure; retain the whole resident pack.
	var company_before: int = Game.company.size()
	var people_before: int = NativeForces.population(Game) + company_before
	var coin_before: float = Barge.holdings(Game)
	var requested: int = Mobilization.GROUP - company_before
	var added: int = DevTools.raise_army(Game, str(w["start_town"]), requested)
	check(added == requested and Game.company.size() == Mobilization.GROUP,
		"lair fixture needs one funded native group (added %d/%d, total %d)" % [added, requested, Game.company.size()])
	if fails > 0: return fails
	var binding: Dictionary = NativeForces.registered(Game, {"faction": "player", "units": Game.company})
	check(bool(binding["ok"]), "native lair company binding: " + str(binding.get("reason", "")))
	check(Game.deployed_units().size() == Mobilization.GROUP, "the whole native lair company must actually be fit to deploy")
	check(NativeForces.population(Game) + Game.company.size() == people_before, "lair muster conserves home and company people")
	check(absf(Barge.holdings(Game) - coin_before) < 0.01, "lair muster spends existing house coin without creating money")
	if fails > 0: return fails
	var c: Dictionary = MonsterContracts._mk(w["towns"][near_town], Game.day, "lair", 9, w["warbands"][resident], 200, "Clear it", "test", 8)
	(w["towns"][near_town]["contracts"] as Array).append(c)
	Game.contract = {}
	var why: String = Contracts.refusal(Game, c)
	check(Contracts.accept(Game, c), "lair contract not accepted (%s; employer %s, resident %s)" % [why, c.get("employer", "?"), str(w["warbands"].has(resident))])
	if fails > 0: return fails
	check(dl["known"], "accepted lair not marked on the map")
	w["party"]["pos"] = dl["pos"] + Vector2(10, 0)
	CampaignWorld.engage(Game, resident)
	var pb: Dictionary = Game.pending_battle
	check(pb.has("enemy") and not (pb.get("enemy", []) as Array).is_empty(), "native lair encounter produced no actual enemy roster")
	if fails > 0: return fails
	check(pb.has("tiles") and (pb["tiles"] as Array).size() > 0, "lair battle without lair terrain")
	if pb.has("tiles"):
		var rows: Array = pb["tiles"]
		print("lair map (%s):\n  %s" % [dl["kind"], "\n  ".join(rows)])
		var blocked: int = 0
		for r in rows:
			if not _within_budget(): return fails
			blocked += String(r).count("#") + String(r).count(",")   # rough tiles are chokes too (thicket lairs are mostly rough; lairs.gd)
		check(blocked > 10, "lair map has no choke points")
	var gold0: int = Game.gold
	var pay: int = int(Game.contract.get("pay", 0))
	var payer_id: String = str(Game.contract.get("payer_town", Game.contract.get("town_id", "")))
	check(w["towns"].has(payer_id) and TownEcon.has_econ(w["towns"].get(payer_id, {})), "native lair settlement needs the contract's actual payer town and economy: " + payer_id)
	if fails > 0: return fails
	var payer: Dictionary = w["towns"][payer_id]["econ"]
	check(payer.has("treasury") and payer.get("stats", null) is Dictionary, "native lair payer needs actual treasury and payment counters")
	var payer_faction_id: String = str(w["towns"][payer_id].get("faction", ""))
	var payer_faction: Dictionary = w.get("factions", {}).get(payer_faction_id, {})
	check(not payer_faction.is_empty() and payer_faction.has("treasury"), "native lair payer needs its actual faction treasury: " + payer_faction_id)
	if fails > 0: return fails
	var expected_payment: float = float(pay)
	var payer_treasury_before: float = float(payer["treasury"])
	var faction_treasury_before: float = float(payer_faction["treasury"])
	check(pay > 0 and maxf(0.0, payer_treasury_before) + maxf(0.0, faction_treasury_before) >= expected_payment,
		"native lair real-payer-funds prerequisite: existing town and faction coin must cover the actual pay")
	if fails > 0: return fails
	var contract_paid_before: float = float(payer["stats"].get("contracts_paid", 0.0))
	var contract_debt_before: float = float(payer.get("debt_to_company", 0.0))
	var enemy: Array = pb["enemy"]
	var outcome: Dictionary = _fight_pending()
	if outcome.is_empty(): return fails
	Game.finish_battle(outcome)
	check(absf(float(payer["stats"].get("contracts_paid", 0.0)) - contract_paid_before - expected_payment) < 0.000001,
		"native employer paid the exact contract amount independently of loot and trophies")
	check(float(payer.get("debt_to_company", 0.0)) == contract_debt_before,
		"successful funded contract creates no unpaid company debt")
	battle_evidence[-1]["contract_settlement"] = {"payer_town": payer_id, "payer_faction": payer_faction_id,
		"expected_payment": expected_payment, "contracts_paid_before": contract_paid_before,
		"contracts_paid_after": float(payer["stats"].get("contracts_paid", 0.0)),
		"debt_to_company_before": contract_debt_before, "debt_to_company_after": float(payer.get("debt_to_company", 0.0)),
		"payer_treasury_before": payer_treasury_before, "payer_treasury_after": float(payer["treasury"]),
		"faction_treasury_before": faction_treasury_before, "faction_treasury_after": float(payer_faction["treasury"])}
	battle_evidence[-1]["settled_result"] = Game._serialize(Game.last_result)
	battle_evidence[-1]["company_gold_before"] = gold0
	battle_evidence[-1]["company_gold_after"] = Game.gold
	battle_evidence[-1]["employer_treasury_after"] = w["towns"][near_town]["econ"]["treasury"]
	var res: Dictionary = Game.last_result
	print("lair cleared: trophies %s, gold %d -> %d (contract %d), log %s" % [res.get("trophies", []), gold0, Game.gold, pay, w["log"][-1]])
	if Creatures.is_creature(enemy[0].race):
		check(int(res.get("trophy_gold", 0)) > 0, "no trophies from slain beasts")
	check(not w["warbands"].has(resident), "lair resident survived")
	check(Game.contract.is_empty() and Game.gold >= gold0 + pay, "lair contract not paid")
	if lairs.has(den):
		check(lairs[den]["resident"] == "" and float(lairs[den]["cleared_until"]) > Game.day, "lair not cleared")
	return fails

func _hunt_bounty(w: Dictionary, rng: RandomNumberGenerator) -> int:
	var town: Dictionary = w["towns"][w["start_town"]]
	# ---------------------------------------------------------------- hunt: a pack plagues the village
	var hc: Dictionary = {}
	for i in 30:
		if not _within_budget(): return fails
		var offers: Array = MonsterContracts.offers(town, Game.day + i, rng)
		for o in offers:
			if not _within_budget(): return fails
			if o["kind"] == "hunt":
				hc = o
		if not hc.is_empty():
			break
	check(not hc.is_empty(), "no hunt offers")
	if not hc.is_empty():
		(town["contracts"] as Array).append(hc)
		check(Contracts.accept(Game, hc), "hunt not accepted")
		if fails > 0: return fails
		var hp: Dictionary = w["warbands"].get(String(hc["target_id"]), {})
		check(not hp.is_empty() and (hp["pos"] as Vector2).distance_to(town["pos"]) < 400.0, "hunt pack not near the village")
		print("hunt: %s, pay %d, pack of %d %s" % [hc["title"], int(hc["pay"]), (hp.get("units", []) as Array).size(), hc["creature"]])
		Contracts.fail(Game, "test")
		check(w["warbands"].has(String(hc["target_id"])) and w["warbands"][hc["target_id"]]["kind"] == "beasts", "a failed hunt's pack should stay a pack")
	# ---------------------------------------------------------------- bounty grows the longer the target lives
	var named_rng: RandomNumberGenerator = RandomNumberGenerator.new(); named_rng.seed = 5
	var boss: Unit = Creatures.make_named(named_rng, "bear")
	var bwid: String = CampaignWorld.spawn_warband(Game, "beasts", town["pos"] + Vector2(300, 0), 1, "den", rng,
		{"units": [boss], "creature": "bear", "named": boss.name, "since": Game.day})
	check(bwid != "" and w["warbands"].has(bwid), "native enabled-world named bear spawn returned no live ID")
	if bwid == "" or not w["warbands"].has(bwid): return fails
	var bwb: Dictionary = w["warbands"][bwid]
	var p0: int = MonsterContracts.bounty_pay(500, bwb, Game.day)
	var p30: int = MonsterContracts.bounty_pay(500, bwb, Game.day + 30.0)
	print("bounty on %s: %d now, %d in 30 days" % [boss.name, p0, p30])
	check(p30 > p0, "bounty should grow while the target lives")
	check(MonsterContracts.creature_fee([boss], "bear", 3) > MonsterContracts.creature_fee([Creatures.make(rng, "wolf")], "wolf", 3), "rarity/power should scale the fee")
	CampaignWorld.remove_warband(Game, bwid)
	return fails

func _defend(w: Dictionary, rng: RandomNumberGenerator) -> int:
	# ---------------------------------------------------------------- defend: militia fights beside the company
	Game.contract = {}
	# Use the first eligible native offer; no strength ranking or offer rerolls.
	var company: Array = Game.deployed_units()
	check(company.size() == 6, "defend keeps all six native company fighters")
	if fails > 0: return fails
	var defend_selection: Dictionary = {"method": "first_eligible_native_offer"}
	var dc: Dictionary = {}
	var dtown: String = ""
	var town_ids: Array = w["towns"].keys()
	town_ids.sort()
	for tid: String in town_ids:
		if not _within_budget(): return fails
		var tt: Dictionary = w["towns"][tid]
		if DB.factions[tt["faction"]].get("player_hostile", false) or TownDefence.defence_policy(Game, tt) == "stand_down":
			continue
		var militia: Array = Militia.units_of(Game, tid)
		if militia.is_empty() or militia.size() != Militia.target_size(tt): continue
		# Exactly one generated set for each eligible town; no offer rerolls.
		for o: Dictionary in Contracts.generate_offers(tt, Game.day, rng):
			if not _within_budget(): return fails
			if o["kind"] != "defend" or Contracts.refusal(Game, o) != "": continue
			var target: String = str(o["target_faction"])
			if Diplomacy.peace_bound(w, Diplomacy.player_realm(w), target): continue
			dc = o
			dtown = tid
			break
		if not dc.is_empty(): break
	check(not dc.is_empty(), "no eligible native defend offer with a full militia")
	if not dc.is_empty():
		(w["towns"][dtown]["contracts"] as Array).append(dc)
		Militia.ensure(Game, dtown, rng)
		var mb: Dictionary = Militia.band_of(Game, dtown)
		check(not mb.is_empty() and (mb.get("units", []) as Array).size() == Militia.target_size(w["towns"][dtown]), "defend fixture needs the full native mustered militia; no synthetic refill")
		if fails > 0: return fails
		check(Contracts.accept(Game, dc), "defend not accepted")
		if fails > 0: return fails
		# coinage: the employer pays only coin it holds; this town can pay the contract and the bonus
		var payer_id: String = str(Game.contract.get("payer_town", Game.contract.get("town_id", "")))
		check(w["towns"].has(payer_id) and TownEcon.has_econ(w["towns"].get(payer_id, {})), "native defend settlement needs the contract's actual payer town and economy: " + payer_id)
		if fails > 0: return fails
		var payer: Dictionary = w["towns"][payer_id]["econ"]
		check(payer.has("treasury") and payer.get("stats", null) is Dictionary, "native defend payer needs actual treasury and payment counters")
		if fails > 0: return fails
		var payer_faction_id: String = str(w["towns"][payer_id].get("faction", ""))
		var employer: Dictionary = payer
		var required_coin: float = ceilf(float(dc["pay"]) * (1.0 + Militia.PAY_BONUS))
		var before_coin: float = Barge.holdings(Game)
		for donor: Dictionary in w["towns"].values():
			if not _within_budget(): return fails
			if not TownEcon.has_econ(donor) or str(donor["id"]) == payer_id: continue
			var amount: float = minf(maxf(0.0, required_coin - float(employer["treasury"])), maxf(0.0, float(donor["econ"]["treasury"])))
			donor["econ"]["treasury"] = float(donor["econ"]["treasury"]) - amount
			employer["treasury"] = float(employer["treasury"]) + amount
		check(float(employer["treasury"]) >= required_coin and absf(Barge.holdings(Game) - before_coin) < 0.01, "defend employer needs actual transferred contract/bonus money")
		if fails > 0: return fails
		var awid: String = Game.contract["target_id"]
		check(awid != "" and w["warbands"].has(awid), "accepted native defend contract has no live attacking force")
		if awid == "" or not w["warbands"].has(awid): return fails
		var attacker: Dictionary = w["warbands"][awid]
		var attacker_binding: Dictionary = NativeForces.registered(Game, attacker)
		check(bool(attacker_binding["ok"]) and (attacker["units"] as Array).size() == int(dc["size"]),
			"selected defend offer must spawn its full actual registered attacking force: " + str(attacker_binding.get("reason", "")))
		if fails > 0: return fails
		defend_selection["selected_offer_id"] = str(dc["id"])
		defend_selection["actual_company_count"] = company.size()
		defend_selection["actual_militia_count"] = (mb["units"] as Array).size()
		defend_selection["actual_attacker_count"] = (attacker["units"] as Array).size()
		print("defend first eligible native offer: %s, %d + %d v %d" %
			[dc["id"], company.size(), (mb["units"] as Array).size(), (attacker["units"] as Array).size()])
		w["party"]["pos"] = attacker["pos"]
		CampaignWorld.engage(Game, awid)
		var allies: Array = Game.pending_battle.get("allies", [])
		var mil_units: Array = Militia.units_of(Game, dtown)
		check(allies.size() == mil_units.size() and allies.size() > 0 and allies[0] == mil_units[0], "militia not deployed as allies")
		if allies.is_empty(): return fails
		check(int(Game.pending_battle.get("militia_start", 0)) == allies.size(), "native pending battle records the actual original allied militia count")
		if fails > 0: return fails
		# Snapshot real identities and counted accounts after muster, before any combat.
		var militia_econ: Dictionary = w["towns"][dtown]["econ"]
		var militia_book: Dictionary = Census._book(militia_econ)
		var militia_book_before: Dictionary = militia_book.duplicate(true)
		var militia_counts_before: Dictionary = {"people": Census.people(militia_econ),
			"pop": int(militia_econ["pop"]), "adults": int(militia_econ["adults"]),
			"deaths": int(militia_econ["stats"].get("deaths", 0)), "dt": int(militia_book.get("dt", 0)),
			"battle": int(militia_book["cur"]["deaths"].get("battle", 0))}
		var militia_families: Dictionary = {}
		var militia_people: Dictionary = {}
		var militia_binding: Dictionary = NativeForces.registered(Game, mb)
		check(bool(militia_binding["ok"]), "native defend militia binding: " + str(militia_binding.get("reason", "")))
		if fails > 0: return fails
		for unit: Unit in allies:
			if not _within_budget(): return fails
			check(unit.home_town == dtown and (mb["units"] as Array).has(unit) and not Game.company.has(unit)
				and not militia_people.has(unit.uid), "each defend ally is a distinct actual town militiaman")
			var family: Dictionary = People.fam_of(w["towns"][dtown], unit.family)
			var person: Array = Persons.by_uid(family, unit.uid)
			check(not person.is_empty() and str(person[4]) == "militia" and int(person[6]) == 0,
				"defend casualty fixture needs each actual adult militia service record")
			if fails > 0: return fails
			var person_uid: String = str(Persons.g(person, Persons.PERSON_UID, ""))
			check(person_uid not in ["", "0"] and not militia_book["death_ids"].has(person_uid)
				and not militia_book["death_ids"].has("unit:%d" % unit.uid), "living militia must have unbooked stable identities")
			militia_people[unit.uid] = {"pid": int(person[0]), "person_uid": person_uid, "sex": int(person[2]),
				"family": unit.family, "person": person.duplicate(true)}
			if not militia_families.has(unit.family):
				militia_families[unit.family] = {"m": int(family["m"]), "f": int(family["f"]),
					"kids": int(family["kids"]), "old": int(family["old"]),
					"militia": int(family["serve"].get("militia", 0)), "serve": (family["serve"] as Dictionary).duplicate(true),
					"fallen_m": 0, "fallen_f": 0}
		if fails > 0: return fails
		var militia_accounts_before: Dictionary = {"town": dtown,
			"counts": militia_counts_before.duplicate(true), "people": militia_people.duplicate(true),
			"families": militia_families.duplicate(true), "census": militia_book_before}
		var pay0: int = int(Game.contract["pay"])
		var g0: int = Game.gold
		var employer_before: float = float(employer["treasury"])
		var contract_paid_before: float = float(payer["stats"].get("contracts_paid", 0.0))
		var contract_debt_before: float = float(payer.get("debt_to_company", 0.0))
		var outcome: Dictionary = _fight_pending()
		if not battle_evidence.is_empty():
			battle_evidence[-1]["militia_accounts_before"] = militia_accounts_before
			battle_evidence[-1]["defend_selection"] = defend_selection
		if outcome.is_empty(): return fails
		var fallen_allies: int = 0
		for unit: Unit in allies:
			if not _within_budget(): return fails
			if unit.dead:
				fallen_allies += 1
				var key: String = "fallen_m" if int(militia_people[unit.uid]["sex"]) == 0 else "fallen_f"
				militia_families[unit.family][key] = int(militia_families[unit.family][key]) + 1
		battle_evidence[-1]["allies_after"] = Game._serialize(allies)
		battle_evidence[-1]["fallen_allies"] = fallen_allies
		battle_evidence[-1]["militia_before_settlement"] = Game._serialize(mil_units)
		# Guaranteed real-death coverage belongs to test_militia_casualty_booking_v100.gd.
		# This contract checks every actual casualty, including exact zero-death preservation below.
		print("defend actual militia deaths: %d of %d" % [fallen_allies, allies.size()])
		check(fallen_allies < allies.size(), "native defend must leave actual militia survivors")
		if fails > 0: return fails
		# Independent rule oracle: monsters.gd on_battle_result, rounded to five coins.
		var expected_bonus: int = int(round(float(pay0) * Militia.PAY_BONUS * float(allies.size() - fallen_allies) / float(allies.size()) / 5.0)) * 5
		var expected_payment: float = float(pay0 + expected_bonus)
		Game.finish_battle(outcome)
		check(absf(float(payer["stats"].get("contracts_paid", 0.0)) - contract_paid_before - expected_payment) < 0.000001,
			"native employer paid the exact contract amount independently of loot and trophies")
		check(float(payer.get("debt_to_company", 0.0)) == contract_debt_before,
			"successful funded contract creates no unpaid company debt")
		battle_evidence[-1]["contract_settlement"] = {"payer_town": payer_id, "payer_faction": payer_faction_id,
			"expected_payment": expected_payment, "contracts_paid_before": contract_paid_before,
			"contracts_paid_after": float(payer["stats"].get("contracts_paid", 0.0)),
			"debt_to_company_before": contract_debt_before, "debt_to_company_after": float(payer.get("debt_to_company", 0.0)),
			"payer_treasury_before": employer_before, "payer_treasury_after": float(payer["treasury"])}
		battle_evidence[-1]["settled_result"] = Game._serialize(Game.last_result)
		battle_evidence[-1]["company_gold_before"] = g0
		battle_evidence[-1]["company_gold_after"] = Game.gold
		battle_evidence[-1]["contract_pay"] = pay0
		battle_evidence[-1]["employer_treasury_before"] = employer_before
		battle_evidence[-1]["militia_after_settlement"] = Game._serialize(Militia.units_of(Game, dtown))
		battle_evidence[-1]["employer_treasury_after"] = employer["treasury"]
		var bonus: int = int(Game.last_result.get("militia_bonus", 0))
		check(bonus == expected_bonus, "native militia bonus equals the documented exact survivor-share formula")
		battle_evidence[-1]["expected_bonus_from_rule"] = expected_bonus
		print("defend %s with %d militia: %d fell, bonus %d on %d, militia now %d" % [w["towns"][dtown]["name"], allies.size(), fallen_allies, bonus, pay0, Militia.units_of(Game, dtown).size()])
		check(bonus > 0 and Game.gold >= g0 + pay0 + bonus, "no militia bonus")
		# Verify the first settlement and the same accounts after duplicate cleanup.
		for settlement_pass: int in 2:
			if not _within_budget(): return fails
			if settlement_pass == 1:
				Game.finish_battle(outcome)
				check(Militia.bury_dead(Game, dtown) == 0, "repeated militia burial removes and books nobody twice")
			var roster: Array = Militia.band_of(Game, dtown).get("units", [])
			check(roster.size() == allies.size() - fallen_allies
				and Militia.units_of(Game, dtown).size() == roster.size(), "all actual dead militia leave the raw roster exactly once")
			if fallen_allies == 0:
				check(roster == allies and militia_book == militia_book_before,
					"zero actual militia deaths remove nobody and leave all census bookings unchanged")
			for unit: Unit in allies:
				if not _within_budget(): return fails
				var family: Dictionary = People.fam_of(w["towns"][dtown], unit.family)
				var saved: Dictionary = militia_people[unit.uid]
				var person: Array = Persons.by_uid(family, unit.uid)
				check(roster.count(unit) == (0 if unit.dead else 1), "militia roster retains exactly the actual survivors")
				if unit.dead:
					check(person.is_empty() and Persons.by_pid(family, int(saved["pid"])).is_empty(),
						"each actual fallen militia identity leaves its household register")
					var entries: int = 0
					for entry: Array in militia_book["deaths"]:
						if int(entry[1]) != int(saved["pid"]): continue
						entries += 1
						check(str(entry[5]) == "battle" and int(entry[7]) == unit.family
							and int(entry[9]) == 1 and float(entry[0]) == Game.day,
							"fallen militia census entry has its actual family, battle cause, day and counted status")
					check(entries == 1 and militia_book["death_ids"].has(str(saved["person_uid"]))
						and militia_book["death_ids"].has("unit:%d" % unit.uid), "each fallen militiaman is booked exactly once by person and Unit identity")
				else:
					check(not person.is_empty() and int(person[0]) == int(saved["pid"])
						and str(Persons.g(person, Persons.PERSON_UID, "")) == str(saved["person_uid"])
						and str(person[4]) == "militia" and person == saved["person"]
						and unit.home_town == dtown and unit.family == int(saved["family"]),
						"each surviving militia identity keeps its exact person record, home, family and service")
					check(not militia_book["death_ids"].has(str(saved["person_uid"]))
						and not militia_book["death_ids"].has("unit:%d" % unit.uid), "surviving militia have no death ledger keys")
			for fid: int in militia_families:
				if not _within_budget(): return fails
				var family: Dictionary = People.fam_of(w["towns"][dtown], fid)
				var before: Dictionary = militia_families[fid]
				var lost: int = int(before["fallen_m"]) + int(before["fallen_f"])
				check(int(family["m"]) == int(before["m"]) - int(before["fallen_m"])
					and int(family["f"]) == int(before["f"]) - int(before["fallen_f"])
					and int(family["kids"]) == int(before["kids"]) and int(family["old"]) == int(before["old"]),
					"household population loses exactly its actual fallen adult militia")
				check(int(family["serve"].get("militia", 0)) == int(before["militia"]) - lost,
					"household militia service places decrease exactly once per actual death")
				if fallen_allies == 0:
					check(family["serve"] == before["serve"], "zero actual militia deaths leave every household service place unchanged")
			check(Census.people(militia_econ) == int(militia_counts_before["people"]) - fallen_allies
				and int(militia_econ["pop"]) == int(militia_counts_before["pop"]) - fallen_allies
				and int(militia_econ["adults"]) == int(militia_counts_before["adults"]) - fallen_allies,
				"town family totals and population ledger lose exactly the actual fallen militia")
			check(int(militia_econ["stats"].get("deaths", 0)) == int(militia_counts_before["deaths"]) + fallen_allies
				and int(militia_book.get("dt", 0)) == int(militia_counts_before["dt"]) + fallen_allies
				and int(militia_book["cur"]["deaths"].get("battle", 0)) == int(militia_counts_before["battle"]) + fallen_allies,
				"death statistics and counted battle census increase exactly once per actual militia death")
			battle_evidence[-1]["militia_accounts_after_" + str(settlement_pass)] = {
				"counts": {"people": Census.people(militia_econ), "pop": militia_econ["pop"], "adults": militia_econ["adults"],
					"deaths": militia_econ["stats"].get("deaths", 0), "dt": militia_book.get("dt", 0),
					"battle": militia_book["cur"]["deaths"].get("battle", 0)},
				"deaths": militia_book["deaths"].duplicate(true), "death_ids": militia_book["death_ids"].duplicate(true)}
	return fails

func _persistence(w: Dictionary, rng: RandomNumberGenerator) -> int:
	# ---------------------------------------------------------------- save/load round trip of the new state
	for i in 8:
		if not _within_budget(): return fails
		Game.advance_time(0.25, false)
		w["encounter"] = ""
	var fp: String = _fingerprint(w)
	check(Game.save_game(), "native monster-world save request accepted")
	Game.wait_save()
	check(bool(Game.save_stats().get("last_ok", false)), "native monster-world save actually completed")
	if fails > 0: return fails
	Game.world = {}
	check(Game.load_game(), "native monster-world save loads")
	if fails > 0: return fails
	w = Game.world
	var fp2: String = _fingerprint(w)
	if fp != fp2:
		var a: PackedStringArray = fp.split("\n")
		var b: PackedStringArray = fp2.split("\n")
		for i in mini(a.size(), b.size()):
			if not _within_budget(): return fails
			if a[i] != b[i]:
				print("  first diff: ", a[i], " | ", b[i])
				break
	check(fp == fp2, "monster world state changed in save/load")
	for lid in w["lairs"]:
		if not _within_budget(): return fails
		for it in w["lairs"][lid].get("stock", []):
			if not _within_budget(): return fails
			check(it is Item, "camp stock not Items after load")
	for wid in w["warbands"]:
		if not _within_budget(): return fails
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.is_monster_band(wb):
			check(not (wb["units"] as Array).is_empty(), "loaded creature force has an actual first Unit")
			if (wb["units"] as Array).is_empty(): return fails
			check(wb["units"][0] is Unit and wb["units"][0].body.plan_id.begins_with("quadruped_"), "creature lost its body plan in save/load")
	for i in 8:
		if not _within_budget(): return fails
		Game.advance_time(0.25, false)   # keeps running after load
		w["encounter"] = ""
	check(_homes_ok(w) == 0, "homes after load")
	return fails

## Native placement and native resident creation, before any measured frame.
## Keep a margin for normal attrition; never replenish or protect bands during sampling.
func _perf_prepare_warbands(w: Dictionary, rng: RandomNumberGenerator) -> void:
	var initial: int = _perf_live_warbands(w)
	var added: int = 0
	for attempt in 128:
		if not _within_budget(): return
		if _perf_live_warbands(w) >= MONSTER_PERF_START_BANDS: break
		var lid: String = Monsters.new_lair(Game, rng)
		if lid == "": continue # native placement may refuse a crowded location
		var lair: Dictionary = w["lairs"][lid]
		var band: Dictionary = w["warbands"].get(str(lair.get("resident", "")), {})
		check(not band.is_empty() and Monsters.is_monster_band(band) and str(band.get("lair", "")) == lid and not (band.get("units", []) as Array).is_empty(), "monster perf setup needs an actual native lair and resident roster")
		if fails > 0: return
		added += 1
	_perf_min_warbands = _perf_live_warbands(w)
	print("monster perf native fixture: entry %d live bands, added %d lairs/resident bands, start %d (target %d)" % [initial, added, _perf_min_warbands, MONSTER_PERF_START_BANDS])
	check(_perf_min_warbands >= MONSTER_PERF_START_BANDS, "monster perf native setup could not reach %d live warbands within 128 placement attempts; found %d" % [MONSTER_PERF_START_BANDS, _perf_min_warbands])

## Empty, dead-only or suspended records do not satisfy the native workload floor.
func _perf_live_warbands(w: Dictionary) -> int:
	var count: int = 0
	for band: Dictionary in w["warbands"].values():
		if Monsters.suspended_band(band): continue
		for unit: Unit in band.get("units", []):
			if not unit.dead:
				count += 1
				break
	return count

## Keep native enabled states while preventing duplicate automatic frame calls.
## Signals remain connected, including the ruler card's set_process(true) observer.
func _perf_suspend_map_process(node: Node) -> void:
	if node.has_method("_process"):
		_perf_process_enabled[node] = node.is_processing()
		node.set_process(false)
	for child: Node in node.get_children():
		_perf_suspend_map_process(child)

func _perf_process_map_node(node: Node, delta: float) -> void:
	if node.is_processing() and node.can_process() and node.has_method("_process"):
		check(node.process_priority == 0, "monster perf native map callbacks must retain scene order")
		node.call("_process", delta)
	for child: Node in node.get_children():
		_perf_process_map_node(child, delta)

## One native autoload frame, then the real map and its native child callbacks.
## No simulation, HUD, ambitions or save scheduling is reimplemented here.
func _perf_map_frame(delta: float) -> void:
	for node: Node in _perf_process_enabled:
		if is_instance_valid(node): node.set_process(bool(_perf_process_enabled[node]))
	Game._process(delta)
	_perf_fixture_checks(Game.world)
	_perf_process_map_node(_perf_map, delta)
	_perf_fixture_checks(Game.world)
	_perf_suspend_map_process(_perf_map)

func _perf_fixture_checks(w: Dictionary) -> void:
	var live_bands: int = _perf_live_warbands(w)
	_perf_min_warbands = mini(_perf_min_warbands, live_bands)
	check(live_bands >= 78, "monster perf must retain at least 78 live native warbands throughout sampling; found %d" % live_bands)
	check(is_instance_valid(_perf_map) and _perf_map.is_inside_tree() and _perf_map.is_node_ready(), "monster perf requires the ready native map in the scene tree")
	check(str(Game.get("_active_screen")) == "map" and Game.location == "", "monster perf must remain on the native map")
	check(int(_perf_map.get("speed_mult")) == 1 and str(_perf_map.get("pursue_wid")) == "", "monster perf must remain at 1x without pursuit")
	check(str(w.get("encounter", "")) == "", "monster perf unexpected encounter must fail, never be erased")
	check(str(w["party"].get("arrived", "")) == "" and not CampaignWorld.is_travelling(Game), "monster perf waiting fixture must not arrive or travel")
	check(bool(w["party"].get("waiting", false)), "monster perf waiting must not be stopped")

## Native cumulative timers only: no replay, subtraction from a whole frame, or skipped work.
func _perf_cost_snapshot() -> Dictionary:
	var day_work: int = CampaignWorld.background_fights_total_usec
	for totals: Array in CampaignWorld.job_total.values(): day_work += int(totals[0])
	return {"monster": CampaignWorld.monster_warband_total_usec,
		"day_work": day_work, "autosave": Game.autosave_process_usec}

## These exact former perf assertions are held together for the frame-gate version.
## Uses the same 600 native frames; no additional advancement or untimed drain.
func _perf_frame_budget_later(w: Dictionary, total: int, saves: Dictionary) -> void:
	check(w.get("work", []).is_empty() and not Game._day_job_hold_active(), "monster perf must finish all due daily work inside the measured frames")
	check(w.get("fight_work", []).is_empty(), "monster perf must finish due background fights inside the measured frames")
	check(not bool(Game.get("_autosave_day_pending")), "monster perf must service every due autosave inside the measured frames")
	check(not bool(saves.get("pending", true)) and int(saves.get("active_snapshots", -1)) == 0, "monster perf must finish autosave capture, writer and retirement inside the measured frames")
	check(total / 600.0 / 1000.0 < 0.5, "on_time too slow per frame")

func _perf(w: Dictionary, rng: RandomNumberGenerator) -> int:
	_perf_observation = {"reached_native_map": false, "frames_measured": 0,
		"midnight_seen": false, "live_native_bands": 0, "mean_ms": -1.0, "worst_ms": -1.0}
	for cost: String in ["monster", "day_work", "autosave"]:
		_perf_observation[cost + "_mean_ms"] = -1.0
		_perf_observation[cost + "_worst_ms"] = -1.0
	_perf_prepare_warbands(w, rng)
	_perf_observation["live_native_bands"] = _perf_live_warbands(w)
	if fails > 0: return fails
	w["party"]["safe_until"] = Game.day + 100.0
	check(w["warbands"].size() >= 78, "monster perf fixture must retain at least 78 native warbands")
	check(Game.main == null and DisplayServer.get_name() == "headless", "monster perf requires the standalone headless runner")
	if fails > 0: return fails
	var tree: SceneTree = Game.get_tree()
	var old_processing: bool = Game.is_processing()
	var old_paused: bool = tree.paused
	var old_screen: String = str(Game.get("_active_screen"))
	var old_params: Dictionary = Game.screen_params
	var old_fps: int = Engine.max_fps
	var old_scale: float = Engine.time_scale
	var old_waiting: bool = bool(w["party"].get("waiting", false))
	Game.set_process(false)
	tree.paused = false
	Engine.max_fps = 0
	Engine.time_scale = 1.0
	Game.goto("map")
	_perf_map = MONSTER_PERF_SCENE.instantiate()
	# run() starts inside Runner._ready(); the root is still setting up children.
	# Wait for native _ready (including leaving town) before suspending callbacks.
	tree.root.add_child.call_deferred(_perf_map)
	await _perf_map.ready
	_perf_observation["reached_native_map"] = _perf_map.is_inside_tree() and _perf_map.is_node_ready() and str(Game.get("_active_screen")) == "map" and Game.location == ""
	w["party"]["waiting"] = true
	_perf_process_enabled.clear()
	_perf_suspend_map_process(_perf_map)
	_perf_fixture_checks(w)
	check(Game.process_priority == 0, "monster perf autoload must precede native map callbacks")
	var delta: float = 1.0 / 60.0
	var first_day: float = Game.day
	var first_midnight: int = int(w.get("last_day", 0))
	check(first_midnight == int(floor(first_day)), "monster perf initial midnight cursor must match the actual day")
	var midnight_counts: Dictionary = {}
	# Align once; each sample then owns one complete engine-frame interval.
	await tree.process_frame
	var previous_frame: int = Engine.get_process_frames()
	var samples: int = 0
	var advances: int = 0
	var total: int = 0
	var worst: int = 0
	var cost_total: Dictionary = {"monster": 0, "day_work": 0, "autosave": 0}
	var cost_worst: Dictionary = cost_total.duplicate()
	for i in 600:
		if fails > 0: break
		if not _within_budget(): break
		_perf_fixture_checks(w)
		var before_day: float = Game.day
		var before_midnight: int = int(w.get("last_day", 0))
		var before_cost: Dictionary = _perf_cost_snapshot()
		var t0: int = Time.get_ticks_usec()
		_perf_map_frame(delta)
		# Include native idle/deferred work through the next real frame boundary.
		await tree.process_frame
		var dtu: int = Time.get_ticks_usec() - t0
		total += dtu
		worst = maxi(worst, dtu)
		samples += 1
		var after_cost: Dictionary = _perf_cost_snapshot()
		for cost: String in cost_total:
			var elapsed: int = int(after_cost[cost]) - int(before_cost[cost])
			check(elapsed >= 0, "monster perf cumulative timer must not reset: " + cost)
			cost_total[cost] = int(cost_total[cost]) + elapsed
			cost_worst[cost] = maxi(int(cost_worst[cost]), elapsed)
		check(Engine.get_process_frames() == previous_frame + 1, "monster perf must drive consecutive engine frames")
		previous_frame = Engine.get_process_frames()
		var cursor: int = int(w.get("last_day", 0))
		var crossed: int = cursor - before_midnight
		check(cursor == int(floor(Game.day)), "monster perf must process every due midnight in its measured frame")
		check(crossed == 0 or crossed == 1, "monster perf midnight cursor must advance by zero or one per frame")
		check(Game.day >= before_day and Game.day - before_day <= delta / MONSTER_PERF_MAP.SEC_PER_DAY + 1.0e-10, "monster perf time must advance monotonically by at most one 1x map step")
		if crossed == 1: midnight_counts[cursor] = int(midnight_counts.get(cursor, 0)) + 1
		if Game.day > before_day: advances += 1
		_perf_fixture_checks(w)
	_perf_observation["frames_measured"] = samples
	_perf_observation["midnight_seen"] = int(w.get("last_day", 0)) > first_midnight
	_perf_observation["live_native_bands"] = _perf_min_warbands
	_perf_observation["mean_ms"] = float(total) / samples / 1000.0 if samples > 0 else -1.0
	_perf_observation["worst_ms"] = float(worst) / 1000.0 if samples > 0 else -1.0
	for cost: String in cost_total:
		_perf_observation[cost + "_mean_ms"] = float(cost_total[cost]) / samples / 1000.0 if samples > 0 else -1.0
		_perf_observation[cost + "_worst_ms"] = float(cost_worst[cost]) / 1000.0 if samples > 0 else -1.0
	# Exactly 600 measured intervals/native calls; no extra advance or untimed drain.
	check(samples == 600, "monster perf must measure all 600 frames")
	check(int(w.get("last_day", 0)) > first_midnight, "monster perf must include a real midnight")
	for midnight: int in range(int(floor(first_day)) + 1, int(floor(Game.day)) + 1):
		check(int(midnight_counts.get(midnight, 0)) == 1, "monster perf midnight %d must be processed exactly once" % midnight)
	check(midnight_counts.size() == int(floor(Game.day)) - int(floor(first_day)), "monster perf must count every crossed midnight day by day")
	var saves: Dictionary = Game.save_stats()
	if _part == "frame_budget_later":
		_perf_frame_budget_later(w, total, saves)
	else:
		check(float(cost_total["monster"]) / 600.0 / 1000.0 < 0.5, "monster and warband non-budgeted updates too slow per frame")
	check(w["warbands"].size() >= 78, "monster perf must retain at least 78 native warbands")
	_perf_process_enabled.clear()
	_perf_map.free()
	_perf_map = null
	Game.set_process(old_processing)
	tree.paused = old_paused
	Game.set("_active_screen", old_screen)
	Game.screen_params = old_params
	Engine.max_fps = old_fps
	Engine.time_scale = old_scale
	w["party"]["waiting"] = old_waiting
	print("monster perf minimum live native warbands: %d" % _perf_min_warbands)
	print("monster native map frames: %d samples, %d advances, day %.6f, midnight_counts %s, pending %d, saves %s, budget %d us" % [samples, advances, Game.day, str(midnight_counts), w.get("work", []).size(), str(saves), MONSTER_PERF_MAP.WORK_BUDGET_USEC])
	print("native whole map frame (reported in v0.100): mean %.3f ms, worst %.2f ms, %d warbands" % [total / 600.0 / 1000.0, worst / 1000.0, w["warbands"].size()])
	print("monster and warband non-budgeted updates: mean %.6f ms, worst %.6f ms" % [_perf_observation["monster_mean_ms"], _perf_observation["monster_worst_ms"]])
	print("budgeted day-work slices (reported): mean %.6f ms, worst %.6f ms; background fights pending %d" % [_perf_observation["day_work_mean_ms"], _perf_observation["day_work_worst_ms"], w.get("fight_work", []).size()])
	print("autosave main-thread service (reported): mean %.6f ms, worst %.6f ms; day request pending %s; worker timings in saves above" % [_perf_observation["autosave_mean_ms"], _perf_observation["autosave_worst_ms"], str(Game.get("_autosave_day_pending"))])
	print("monster perf gate: ", "whole frame and day/fight/autosave completion (held for later frame-gate version)" if _part == "frame_budget_later" else "monster and warband non-budgeted mean < 0.5 ms; completion gates held in frame_budget_later")
	return fails

func _upgrade(w: Dictionary, rng: RandomNumberGenerator) -> int:
	# a save from before monsters wave 1 gets its lairs, camps and militia on load
	for wid in w["warbands"].keys():
		if not _within_budget(): return fails
		var k: String = w["warbands"][wid]["kind"]
		if k in ["militia", "beasts", "den", "camp", "bandit", "deserter"]:
			var band: Dictionary = w["warbands"][wid]
			for unit: Unit in band["units"]:
				if not _within_budget(): return fails
				if unit.dead or Creatures.is_creature(unit.race): continue
				if k == "militia":
					var town: Dictionary = w["towns"].get(unit.home_town, {})
					var family: Dictionary = People.fam_of(town, unit.family)
					var person: Array = Persons.by_uid(family, unit.uid) if not family.is_empty() else []
					check(not person.is_empty(), "old-save fixture needs each removed militia person's actual service")
					if person.is_empty(): return fails
					Horses.return_mount(Game, unit)
					ArmsTrade.kit_home(Game, unit)
					People.release(town, unit.family, str(person[4]), unit.uid)
				else: Army.release(Game, unit, "fled")
			CampaignWorld.remove_warband(Game, wid)
	for k in ["lairs", "militia", "monsters"]:
		if not _within_budget(): return fails
		w.erase(k)
	CampaignWorld.after_load(Game)
	check(w.has("lairs") and not w["lairs"].is_empty() and w["militia"].size() == w["towns"].size(), "old save not upgraded")
	check(_homes_ok(w) == 0, "homes after an old-save upgrade")
	return fails

func _fingerprint(w: Dictionary) -> String:
	var parts: Array = []
	var lids: Array = w["lairs"].keys()
	lids.sort()
	for lid in lids:
		var l: Dictionary = w["lairs"][lid]
		parts.append("%s %s %s %s %s %s %.2f %s" % [lid, l["kind"], str((l["pos"] as Vector2).round()), l["resident"], l["known"], l["creature"],
			float(l["cleared_until"]), str(l.get("stock", []).map(func(it): return "%d/%s/%d" % [it.uid, it.tid, it.quality]))])
	var mids: Array = w["militia"].keys()
	mids.sort()
	for tid in mids:
		parts.append("militia %s %s" % [tid, w["militia"][tid]])
	parts.append("monsters %d %s" % [int(w["monsters"]["fights"]), str(w["monsters"]["unlocked"].keys())])
	var wids: Array = w["warbands"].keys()
	wids.sort()
	for wid in wids:
		var wb: Dictionary = w["warbands"][wid]
		parts.append("%s %s %s %s %s %s %s" % [wid, wb["kind"], wb["faction"], wb["home"], wb.get("lair", ""), wb.get("named", ""),
			str(wb["units"].map(func(u): return "%d %s %s %s %d" % [u.uid, u.race, u.title, u.home_town, u.equip.size()]))])
	return "\n".join(parts)
