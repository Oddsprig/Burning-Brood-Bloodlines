extends RefCounted
## v0.081 riders are live targets in BattleSim ticks (the v0.023 gap), with the existing v0.054 rider rules after.
##   godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_rider_targeting_v081.gd --watchdog=120
## One DevTools start world, no campaign days. A house ruler (a real enlisted Unit) rides one dragon; another adult of
## the house, with no Unit of his own, rides a second dragon as a battle body. Enemy troops are made natively.
const BattleScene = preload("res://battle/battle.gd")
var fails := 0
var checks := 0
var town_id := ""
var rider: Unit
var dragon: Unit
var dragon_uid := ""
var person_uid := ""
var dragon2: Unit
var dragon2_uid := ""
var person2_uid := ""
var fresh: Dictionary = {}
var rider_fresh: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL rider targeting v081: " + message)

func suitable(choice: Dictionary) -> bool:
	var person := Dynasty.person(Game, str(choice["ruler_uid"]))
	return str(person.get("race", "")) == "human" and int(person.get("unit_uid", -1)) < 0 and str(person.get("state", "")) == ""

## v0.081: a suitable house that also has a second adult without a Unit (dragon two's rider, the battle-body checks).
## The start world is rebuilt from the current fixture, so the test looks for such a house instead of assuming one.
func suitable_with_kin(choice: Dictionary) -> bool:
	return suitable(choice) and house_adult_without_unit(str(choice["town_id"]), str(choice["household_uid"]), str(choice["ruler_uid"])) != ""

func enemies(n: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	for i in n:
		var u := Factory.make_troop(rng, "northern_clans", DB.factions["northern_clans"]["troops"][i % 2], 2)
		out.append(u)
	return out

func reset_dragons() -> void:
	for uid in fresh:
		var u: Unit = DragonCombat._unit(Game, uid)
		u.body = BodyState.from_dict((fresh[uid] as Dictionary).duplicate(true))
		u.dead = false
		DragonCombat.sync_profile(Game, uid)
	if rider != null and not rider_fresh.is_empty() and not rider.dead and not Dynasty._person(Game, person_uid).is_empty():
		rider.body = BodyState.from_dict(rider_fresh.duplicate(true))   # each fixture battle starts with him whole

func make_sim(dragons: Array, foes: Array, seed: int, riders: bool = true) -> BattleSim:
	var sim := BattleSim.new()
	var opts := {"w": 8, "h": 5, "verbose": false, "history_events": 1, "combat_journal": false}
	if riders: opts["dragon_riders"] = DragonCombat.battle_riders(Game, dragons)
	sim.setup(dragons, foes, seed, opts)
	return sim

func seat_of(sim: BattleSim, d: Unit) -> Fighter:
	for f: Fighter in sim.fighters:
		if f.seated_on >= 0 and sim.fighters[f.seated_on].unit == d: return f
	return null

func fighter_of(sim: BattleSim, u: Unit) -> Fighter:
	for f: Fighter in sim.fighters:
		if f.unit == u: return f
	return null

func result_of(sim: BattleSim) -> Dictionary:
	var screen := BattleScene.new()
	screen.sim = sim
	var result: Dictionary = screen.build_result()
	screen.free()
	return result

func house_adult_without_unit(tid: String, house: String, skip: String) -> String:
	var town: Dictionary = Game.world["towns"][tid]
	for family in town["econ"]["fams"]:
		if str(family.get("household_uid", "")) != house: continue
		for person in family.get("pp", []):
			var uid := str(Persons.g(person, Persons.PERSON_UID, ""))
			if uid == skip: continue
			var row := Dynasty.person(Game, uid)
			if row.is_empty() or not bool(row.get("alive", false)) or int(row.get("unit_uid", -1)) >= 0: continue
			if int(row.get("age", 0)) < int(People.ages(str(row.get("race", "human")))["adult"]): continue
			return uid
	return ""

## Persons in the house's family records (a kept body must never add one).
func people_count() -> int:
	var n := 0
	for family in Game.world["towns"][town_id]["econ"]["fams"]:
		n += (family.get("pp", []) as Array).size()
	return n

## One fixture battle on dragon d whose rider takes a native, nonfatal muscle wound in the saddle (the existing
## _rider_wound path), settled through the real receipt. Returns the rider's Unit in that battle, or null.
func wounded_battle(d: Unit, seed: int) -> Unit:
	Game.pending_battle = {"seed": seed}
	var receipt := DragonCombat.admission_receipt(Game, [d])
	check(not receipt.is_empty(), "dragon %s is admitted for the wound battle (seed %d)" % [d.dragon_uid, seed])
	var riders := DragonCombat.battle_riders(Game, [d])
	var sim := BattleSim.new()
	sim.setup([d], enemies(2, seed), seed, {"w": 8, "h": 5, "verbose": false, "history_events": 1, "combat_journal": false, "dragon_riders": riders})
	var seat := seat_of(sim, d)
	check(seat != null, "the rider is seated for the wound battle (seed %d)" % seed)
	if seat == null: return null
	DragonCombat._rider_wound(seat.unit, 0.35)
	sim.step()
	var result := result_of(sim)
	DragonCombat.on_battle_result(Game, result, receipt)
	return seat.unit

func part_ids(u: Unit) -> Array:
	if u == null or u.body == null: return []
	var ids: Array = u.body.parts.keys()
	ids.sort()
	return ids

func body_text(u: Unit) -> String:
	return JSON.stringify(u.body.to_dict()) if u != null and u.body != null else ""

func persistence_checks() -> void:
	if person2_uid == "" or Dynasty._person(Game, person2_uid).is_empty() or rider == null or rider.dead:
		check(false, "the persistence checks need the living kin rider and the living ruler")
		return
	reset_dragons()
	DragonCombat.kept_bodies(Game).erase(person2_uid)   # (he starts this section whole)
	var people0 := people_count()
	# The battle-body rider.
	var b1 := wounded_battle(dragon2, 814)
	if b1 == null: return
	check(not b1.dead and Dynasty.bound_unit(Game, Dynasty.person(Game, person2_uid)) == null, "the kin rider lived and still has no Unit of his own")
	var hurt := DragonCombat.rider_damage(b1)
	check(hurt > 0.0, "his battle body carries the wound (%.4f)" % hurt)
	var kept: Dictionary = DragonCombat.kept_bodies(Game).get(person2_uid, {})
	check(not kept.is_empty() and JSON.stringify(kept.get("body", {})) == body_text(b1), "his wounded body is kept by his person uid after the battle")
	Game.pending_battle = {"seed": 815}
	var b2: Unit = DragonCombat.battle_riders(Game, [dragon2]).get(str(dragon2.uid), {}).get("unit")
	check(b2 != null and b2 != b1 and absf(DragonCombat.rider_damage(b2) - hurt) <= 1e-12 * maxf(1.0, hurt) and part_ids(b2) == part_ids(b1), "the next battle's body for him has the same wounds (%.6f vs %.6f)" % [DragonCombat.rider_damage(b2) if b2 != null else -1.0, hurt])
	# The bound rider (the ruler, his own Unit).
	var r1 := wounded_battle(dragon, 816)
	check(r1 == rider and not rider.dead, "the ruler rode as his own Unit and lived")
	var ruler_hurt := DragonCombat.rider_damage(rider)
	var ruler_text := body_text(rider)
	check(ruler_hurt > 0.0, "the ruler's own Unit carries the wound (%.4f)" % ruler_hurt)
	Game.pending_battle = {"seed": 817}
	var r2: Unit = DragonCombat.battle_riders(Game, [dragon]).get(str(dragon.uid), {}).get("unit")
	check(r2 == rider and body_text(r2) == ruler_text, "the ruler's next battle has him with the same wounds")
	check(not DragonCombat.kept_bodies(Game).has(person_uid), "a rider with his own Unit has no kept body (his Unit is his body)")
	check(people_count() == people0, "no person was added for either rider (%d vs %d)" % [people_count(), people0])
	# A real save and load (a fresh read of the save file).
	Game.pending_battle = {}
	var kin_text := body_text(b1)
	Game.save_game()
	Game.wait_save()
	check(Game.load_game(), "the save with the wounded riders loads")
	dragon = DragonCombat._unit(Game, dragon_uid)
	dragon2 = DragonCombat._unit(Game, dragon2_uid)
	rider = Dynasty.bound_unit(Game, Dynasty.person(Game, person_uid))
	var kept_l: Dictionary = DragonCombat.kept_bodies(Game).get(person2_uid, {})
	check(not kept_l.is_empty(), "the kin rider's kept body is in the loaded save")
	Game.pending_battle = {"seed": 818}
	var b3: Unit = DragonCombat.battle_riders(Game, [dragon2]).get(str(dragon2.uid), {}).get("unit") if dragon2 != null else null
	check(b3 != null and absf(DragonCombat.rider_damage(b3) - hurt) <= 1e-9 * maxf(1.0, hurt), "after loading, his battle body has the same wounds (%.6f vs %.6f)" % [DragonCombat.rider_damage(b3) if b3 != null else -1.0, hurt])
	var kin_parts: Array = (JSON.parse_string(kin_text).get("parts", {}) as Dictionary).keys()
	kin_parts.sort()
	check(b3 != null and part_ids(b3) == kin_parts and not kin_parts.is_empty(), "after loading, the same wounded parts (%s)" % str(kin_parts))
	check(rider != null and absf(DragonCombat.rider_damage(rider) - ruler_hurt) <= 1e-9 * maxf(1.0, ruler_hurt), "after loading, the ruler's own Unit has the same wounds (%.6f vs %.6f)" % [DragonCombat.rider_damage(rider) if rider != null else -1.0, ruler_hurt])
	check(people_count() == people0, "no person was added by the save and load")
	# Time heals the kept body (one day of care), and a Unit he is later bound to takes it.
	Game.pending_battle = {}
	var day := int(Game.day) + 1
	DragonCombat.heal_kept_bodies(Game, day)
	var healed: Dictionary = DragonCombat.kept_bodies(Game).get(person2_uid, {})
	var left := 0.0
	if not healed.is_empty():
		var frame := Unit.new()
		frame.body = BodyState.from_dict((healed["body"] as Dictionary).duplicate(true))
		left = DragonCombat.rider_damage(frame)
	check(healed.is_empty() or left < hurt, "a day of care heals his kept body (%.6f -> %.6f)" % [hurt, left])
	var healed_text := JSON.stringify(healed)
	DragonCombat.heal_kept_bodies(Game, day)
	check(JSON.stringify(DragonCombat.kept_bodies(Game).get(person2_uid, {})) == healed_text, "the same day heals once")
	if not healed.is_empty():
		var keep_copy: Dictionary = healed.duplicate(true)
		var unit_now := Unit.create("human", "player")
		DragonCombat.adopt_kept_body(Game, person2_uid, unit_now)
		check(not DragonCombat.kept_bodies(Game).has(person2_uid) and absf(DragonCombat.rider_damage(unit_now) - left) <= 1e-9 * maxf(1.0, left), "a Unit he is bound to takes his kept wounds, and the kept body goes")
		DragonCombat.kept_bodies(Game)[person2_uid] = keep_copy
	reset_dragons()

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start world loads")
		return fails
	town_id = DevTools.choose_house(Game, suitable_with_kin)
	if town_id == "": town_id = DevTools.choose_house(Game, suitable)   # none has one: the battle-body checks report it
	check(town_id != "", "a human ruler without a Unit is available")
	if town_id == "": return fails
	DevTools.stand_at(Game, town_id)
	person_uid = str(Dynasty.selected(Game)["ruler_uid"])
	var house := str(Dynasty.person(Game, person_uid).get("household_uid", ""))
	person2_uid = house_adult_without_unit(town_id, house, person_uid)
	var enlisted := Mobilization.enlist_household(Game, person_uid)
	check(bool(enlisted.get("ok", false)), "the ruler enlists through native service")
	if not bool(enlisted.get("ok", false)): return fails
	rider = enlisted["unit"]
	rider_fresh = rider.body.to_dict()
	var owner := Dragons._person(Game, person_uid)
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var one := Dragons._make(Game, "adult", town_id, owner, "v081:ruler", 0, "female")
	var two := Dragons._make(Game, "adult", town_id, owner, "v081:kin", 0, "male")
	dragon_uid = str(one["id"])
	dragon2_uid = str(two["id"])
	one["rider_person_uid"] = person_uid
	if person2_uid != "": two["rider_person_uid"] = person2_uid
	DragonCombat.prepare_world(Game)
	dragon = DragonCombat._unit(Game, dragon_uid)
	dragon2 = DragonCombat._unit(Game, dragon2_uid)
	fresh = {dragon_uid: dragon.body.to_dict(), dragon2_uid: dragon2.body.to_dict()}
	for uid in ([dragon_uid, dragon2_uid] if person2_uid != "" else [dragon_uid]):   # (dragon two needs its rider)
		check(bool(DragonCombat.participation_order(Game, uid, true, DragonCombat.participation_preview(Game, uid, true)).get("ok", false)), "the defence order admits dragon " + uid)

	# --- The rider is on the field as a live target, at his dragon's cell, holding no tile of his own.
	var riders := DragonCombat.battle_riders(Game, [dragon])
	check(riders.has(str(dragon.uid)) and riders[str(dragon.uid)]["unit"] == rider and not bool(riders[str(dragon.uid)]["detached"]), "a rider with a Unit of his own rides as that Unit")
	var plain := make_sim([dragon], enemies(3, 1), 1, false)
	check(plain.fighters.size() == 4 and seat_of(plain, dragon) == null, "without the option a battle is unchanged (no rider fighter)")
	var struck_seeds := 0
	var rider_acted := false
	var off_cell := false
	var in_occ := false
	for seed in 12:
		reset_dragons()
		var sim := make_sim([dragon], enemies(3, 100 + seed), 100 + seed)
		var seat := seat_of(sim, dragon)
		var df := fighter_of(sim, dragon)
		if seed == 0:
			check(seat != null and seat.unit == rider and seat.side == df.side and seat.seat_dragon == df.idx and df.seated_rider == seat.idx, "the ruler sits on his dragon in the battle")
			check(seat != null and seat.seat_joined and not seat.seat_body, "he joined on his dragon (not deployed) and is his own Unit")
		if seat == null: break
		var struck := false
		for t in 3000:
			if sim.over: break
			sim.step()
			if seat.seat_dragon >= 0:
				if seat.cell != df.cell: off_cell = true
				if sim.occ[sim._ci(df.cell)] == seat.idx: in_occ = true
			for ev: Dictionary in sim.new_events:
				if int(ev.get("target", -1)) == seat.idx and int(ev.get("actor", -1)) != seat.idx: struck = true
				if int(ev.get("actor", -1)) == seat.idx and str(ev.get("type", "")) in ["hit", "miss", "attack", "strike", "parry", "block", "dodge"]: rider_acted = true
		if struck: struck_seeds += 1
		check(sim.over, "battle seed %d ends (a seated or fallen rider never holds the field)" % (100 + seed))
		rider.dead = false   # fixture battles settle nothing: he is put back whole for the next seed
	check(struck_seeds >= 1, "enemies pick and strike the seated rider in live ticks (%d of 12 seeds)" % struck_seeds)
	check(not off_cell, "a seated rider is always at his dragon's cell")
	check(not in_occ, "a seated rider holds no tile")
	check(not rider_acted, "a seated rider never attacks on his own")

	# --- When the dragon goes down the rider is out of the fight; he is no longer a target and does not hold the field.
	if not rider.dead:
		reset_dragons()
		var sim := make_sim([dragon], enemies(2, 7), 7)
		var seat := seat_of(sim, dragon)
		var df := fighter_of(sim, dragon)
		sim.step()
		check(sim._targets[df.side].has(seat), "the seated rider is in his side's target list")
		sim._fall(df, "pain", 5)
		sim.step()
		check(seat.seat_dragon < 0 and seat.waiting and seat.unseated == "the mount went down", "the rider leaves the saddle when his dragon falls")
		sim.step()
		check(not sim._targets[df.side].has(seat), "a fallen rider is no longer a target")
		sim._kill(df, -1, "native fixture collapse")
		for t in 10:
			if sim.over: break
			sim.step()
		check(sim.over and sim.winner == 1, "with the dragon dead the battle ends against its side")
		var result := result_of(sim)
		check(not (result["player_units"] as Array).has(rider), "a rider who only fought on his dragon has no roster row in the result")
		check((result.get("dragon_seats", {}) as Dictionary).has(dragon_uid), "the result reports the seat for the post-battle rules")
		check(str(result["dragon_seats"][dragon_uid]["unseated"]) == "the mount went down", "the report says why he left the saddle")

	# --- A rider with no Unit of his own rides as a battle body; his live wound reaches his record.
	# v0.081 r3: this runs before the killed-ruler section. The ruler owns both dragons, and once he is dead
	# dragon two's defence order no longer has a living owner, so it is (rightly) not admitted and no outcome is made.
	if person2_uid == "":
		print("rider targeting v081: no second adult without a Unit in this house; battle-body checks skipped")
		check(false, "the house has a second adult without a Unit for the battle-body checks")
	else:
		reset_dragons()
		Game.pending_battle = {"seed": 812}
		var receipt := DragonCombat.admission_receipt(Game, [dragon2])
		check(not receipt.is_empty(), "dragon two (battle-body rider) is admitted: %s" % str(DragonCombat.combat_status(Game, dragon2_uid).get("reason", "")))
		var riders2 := DragonCombat.battle_riders(Game, [dragon2])
		var entry: Dictionary = riders2.get(str(dragon2.uid), {})
		check(not entry.is_empty() and bool(entry["detached"]) and (entry["unit"] as Unit).name == str(Dynasty.person(Game, person2_uid)["name"]), "a rider without a Unit rides as a battle body named for him")
		check(DragonCombat.battle_riders(Game, [dragon2])[str(dragon2.uid)]["unit"] == entry["unit"], "the same battle body serves every round of one battle")
		var sim := BattleSim.new()
		sim.setup([dragon2], enemies(2, 11), 812, {"w": 8, "h": 5, "verbose": false, "history_events": 1, "combat_journal": false, "dragon_riders": riders2})
		var seat := seat_of(sim, dragon2)
		var foe: Fighter = null
		for f: Fighter in sim.fighters:
			if f.side == 1:
				foe = f
				break
		check(seat != null and seat.seat_body, "the battle body is seated")
		if seat != null and foe != null:
			var strike: Dictionary = sim.debug_strike(foe.idx, seat.idx, "torso_upper", -1, true)
			check(DragonCombat.rider_damage(seat.unit) > seat.seat_damage0 or seat.unit.dead, "a landed strike wounds the rider's live body (%s)" % str(strike.get("result", "")))
			sim.step()
			var result := result_of(sim)
			check(not (result["player_units"] as Array).has(seat.unit), "a battle body is never a roster unit (no loot or prisoners)")
			var applied2 := DragonCombat.on_battle_result(Game, result, receipt)
			var outcomes: Array = result.get("rider_outcomes", [])
			check(outcomes.size() == 1, "one outcome for the battle-body rider (got %d; applied %s; seat %s)" % [outcomes.size(),
				str(applied2.get("applied", false)), str((result.get("dragon_seats", {}) as Dictionary).get(dragon2_uid, {}).get("damage", "none"))])
			if outcomes.size() == 1:
				var fate := str(outcomes[0]["outcome"])
				check(fate in ["wounded", "killed"] and str(outcomes[0]["live"]) != "", "his live harm is the outcome (%s)" % fate)
				if fate == "wounded":
					var loc := Dynasty._person(Game, person2_uid)
					check(not loc.is_empty() and (loc["person"][Persons.HIST] as Array).any(func(event: Array): return str(event[1]) == "wound"), "the wound is in his life history")
			check(Dynasty.bound_unit(Game, Dynasty.person(Game, person2_uid)) == null, "no campaign Unit was made for him")

	# --- r4 (QC 722eaab1): a surviving rider's native wounds are his: they are on his body at the next battle and
	# after a real save and load, for a battle-body rider and for a rider with his own Unit. Nothing heals them but time.
	persistence_checks()

	# --- A rider killed in the fight dies through the existing casualty path, once.
	# (Last of the dragon sections: it removes the ruler, who owns both dragons.)
	reset_dragons()
	if not rider.dead:
		var book := Census._book(Game.world["towns"][town_id]["econ"])
		var deaths_before: int = book["deaths"].size()
		Game.pending_battle = {"seed": 811}
		var receipt := DragonCombat.admission_receipt(Game, [dragon])
		check(not receipt.is_empty(), "the native dragon is admitted")
		var sim := make_sim([dragon], enemies(2, 9), 811)
		var seat := seat_of(sim, dragon)
		sim._kill(seat, -1, "native fixture: struck down in the saddle")
		sim.step()
		check(seat.unseated == "the rider fell" and seat.seat_dragon < 0, "a rider struck down leaves the saddle")
		var result := result_of(sim)
		var applied := DragonCombat.on_battle_result(Game, result, receipt)
		var outcomes: Array = result.get("rider_outcomes", [])
		check(bool(applied["applied"]) and outcomes.size() == 1, "one rider outcome (got %d)" % outcomes.size())
		if outcomes.size() == 1:
			check(str(outcomes[0]["outcome"]) == "killed" and str(outcomes[0]["live"]) == "killed", "the live death is the outcome (no fall roll over it)")
			check("the fighting on" in str(outcomes[0]["text"]), "the report says he died in the fighting on his dragon")
		check(rider.dead and Dynasty._person(Game, person_uid).is_empty(), "the killed rider leaves the living register through normal casualties")
		check(book["deaths"].size() == deaths_before + 1 and book["death_ids"].has(person_uid), "one census death")
		check(not bool(DragonCombat.on_battle_result(Game, result, receipt)["applied"]), "the receipt cannot apply twice")

	# --- Horse riders were already the live fighters; their horse is the passive body under them.
	var horseman: Unit = enemies(1, 21)[0]
	horseman.faction = "player"
	horseman.horse = Unit.create("horse", "player")
	horseman.horse_care = {"fed": true, "paid": true, "last_day": int(Game.day)}
	var hs := BattleSim.new()
	hs.setup([horseman], enemies(2, 22), 21, {"w": 8, "h": 5, "verbose": false, "history_events": 1, "combat_journal": false})
	hs.step()
	var hf := fighter_of(hs, horseman)
	check(hf != null and hf.mount_idx >= 0 and hs._targets[0].has(hf), "a mounted horseman is a live target in BattleSim ticks")
	print("rider targeting v081: %d checks, %d fails, %.1f s" % [checks, fails, float(Time.get_ticks_msec() - started) / 1000.0])
	return fails
