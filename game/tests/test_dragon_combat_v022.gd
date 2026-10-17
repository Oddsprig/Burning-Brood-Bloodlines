extends RefCounted
## Native original actor/body fixtures; no generation, campaign rewards or engine UI.
const NativeFixture = preload("res://tests/test_dragon_identities.gd")
const U = preload("res://tests/sim_util.gd")
var native: NativeFixture
var dragon_uid: String = ""
var other_uid: String = ""
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon combat: ", why)

func row(uid: String = "") -> Dictionary:
	return Game.world["dragons"]["records"][dragon_uid if uid == "" else uid]

func actor(uid: String = "") -> Unit:
	return Game.world["dragons"]["combat_units"][dragon_uid if uid == "" else uid]

func snapshot() -> String:
	return JSON.stringify(Game._serialize({"world": Game.world, "company": Game.company, "gold": Game.gold,
		"rng": str(Game.rng.state), "unit_next": Unit._next_uid, "item_next": Item._next_uid}), "", true, true)

func people_and_funds() -> String:
	var world: Dictionary = Game.world.duplicate(true); world.erase("dragons")
	return JSON.stringify(Game._serialize({"world": world, "company": Game.company, "gold": Game.gold,
		"rng": str(Game.rng.state), "item_next": Item._next_uid}), "", true, true)

func fixture() -> void:
	native = NativeFixture.new(); native.fixture()
	Dragons.init_world(Game)
	var ids: Array = []
	for record: Dictionary in Dragons.records(Game):
		if str(record["stage"]) == "adult" and str(record["estate_town_id"]) == "a": ids.append(str(record["id"]))
	dragon_uid = str(ids[0]); other_uid = str(ids[1])
	check(Dynasty.select_city(Game, "a"), "real existing owner household selected")
	Game.location = "a"; Game.world["party"]["pos"] = Game.world["towns"]["a"]["pos"]
	row()["gem_id"] = "ruby"; row()["size_class"] = "small"; row()["growth_points"] = 0.0
	row(other_uid)["gem_id"] = "pearl"; row(other_uid)["size_class"] = "colossal"; row(other_uid)["growth_points"] = 4.0
	DragonCombat.prepare_world(Game)
	var person_uid: String = native.uid("a", 0)
	check(DragonBond.bind(Game, dragon_uid, person_uid, DragonBond.bind_preview(Game, dragon_uid, person_uid))["ok"], "actual adult civilian owner bond, no new rider Unit")
	DragonCombat.sync_profile(Game, dragon_uid)

func reject(result: Dictionary, before: String, why: String) -> void:
	check(not bool(result.get("ok", false)) and str(result.get("reason", "")) != "", why)
	check(snapshot() == before, why + " is pure")

func native_actor_and_order() -> void:
	fixture()
	var unit: Unit = actor(); var body: BodyState = unit.body
	var before: String = snapshot(); var funds: String = people_and_funds()
	var count: int = Unit._next_uid
	DragonCombat.prepare_world(Game); DragonCombat.after_load(Game)
	check(snapshot() == before and actor() == unit and unit.body == body and Unit._next_uid == count, "repeat setup/load keeps original Unit/body/counters without resurrection")
	check(unit.is_native_dragon() and unit.family == -1 and unit.role == "dragon" and unit.equip.is_empty() and Game.company.is_empty(), "actual dragon holder is not a humanoid/service/gear allocation")
	check(not ServiceIdentity.inventory(Game).has(unit.uid) and DragonCombat.uid_floor(Game) > unit.uid, "native UID floor includes actor but humanoid service inventory excludes it")
	check(DragonCombat.record_for_unit(Game, unit)["id"] == dragon_uid, "actual Unit resolves its original individual identity")
	var clone: Unit = Unit.from_dict(unit.to_dict().duplicate(true))
	check(not DragonCombat.is_dragon_unit(Game, clone), "same UID/body copy cannot impersonate actual admitted holder")
	Unit._next_uid = count
	var copied: Dictionary = DragonCombat.record_for_unit(Game, unit); copied["name"] = "Copy"
	var status: Dictionary = DragonCombat.combat_status(Game, dragon_uid); status["profile"]["strength"] = 0.0
	check(snapshot() == before and not status["enabled"] and status["can_enable"] and not status["can_withdraw"], "detached physical status/default OFF and reads are pure")
	var all_ids: Dictionary = {}; var stance: Array = []
	for part: Dictionary in body.plan()["parts"]:
		check(not all_ids.has(str(part["id"])) and str(part["_ck"]) == "wyvern:" + str(part["id"]), "unique native anatomy/cache key: " + str(part["id"]))
		all_ids[str(part["id"])] = true
		if "stance" in part.get("functions", []): stance.append(str(part["id"]))
	check(not all_ids.has("leg_front_upper_l") and not all_ids.has("hand_l") and all_ids.has("wing_upper_l") and all_ids.has("wing_membrane_r"), "wyvern wings are forelimbs without separate walking front legs/hands")
	check(stance.size() == 6 and stance.has("foot_l") and stance.has("foot_r"), "exactly two native hind-leg stance chains")
	var wing_stance: bool = false
	for part: Dictionary in body.plan()["parts"]:
		if str(part["id"]).begins_with("wing"):
			for layer: Dictionary in part["layers"]: wing_stance = wing_stance or "stance" in layer.get("functions", [])
	check(not wing_stance, "wing tendon wounds cannot claim hind-leg walking function")
	check(body.has_part("brain") and body.has_part("heart") and body.has_part("lung_l") and body.has_part("spine_upper") and body.has_part("jaw"), "native vital organs/airway/spine/jaw present")
	check(body.part_def("torso_upper")["layers"][0]["tissue"] == "scale" and body.part_def("jaw")["layers"][0]["tissue"] == "skin", "body coat is organic scale/skin, not gem armour")
	reject(DragonCombat.participation_order(Game, dragon_uid, true), before, "unreviewed defence order refused")
	var review: Dictionary = DragonCombat.participation_preview(Game, dragon_uid, true)
	unit.body.pain = 0.01; var changed: String = snapshot()
	reject(DragonCombat.participation_order(Game, dragon_uid, true, review), changed, "actual body change invalidates reviewed order")
	unit.body.pain = 0.0
	check(DragonCombat.participation_order(Game, dragon_uid, true, DragonCombat.participation_preview(Game, dragon_uid, true))["ok"], "explicit reviewed local defence order is recorded")
	check(DragonCombat.battle_units(Game) == [unit] and people_and_funds() == funds and Unit._next_uid == count, "pure admission borrows original actor without population/coin/gear/Unit creation")
	row()["stage"] = "juvenile"
	check(DragonCombat.battle_units(Game).is_empty(), "juvenile body cannot join adult defence")
	row()["stage"] = "adult"
	var bonded: String = str(row()["rider_person_uid"]); row()["rider_person_uid"] = ""
	check(DragonCombat.battle_units(Game).is_empty(), "unbonded dragon cannot join defence")
	row()["rider_person_uid"] = bonded
	var household: String = str(row()["owner_household_uid"]); row()["owner_household_uid"] = "foreign-household"
	check(DragonCombat.battle_units(Game).is_empty(), "other actual household cannot use a shared dynasty name to join defence")
	row()["owner_household_uid"] = household
	changed = snapshot(); reject(DragonCombat.participation_order(Game, dragon_uid, true, review), changed, "repeated enable cannot duplicate order/history")
	Game.location = ""; Game.world["party"]["pos"] = Vector2(999, 999)
	check(DragonCombat.battle_units(Game).is_empty() and row()["combat_order"]["enabled"], "remote party cannot summon body or silently erase defence order")
	check(DragonCombat.participation_order(Game, dragon_uid, false, DragonCombat.participation_preview(Game, dragon_uid, false))["ok"], "current household may withdraw explicit order while away")
	check(unit == actor() and not row()["combat_order"]["enabled"], "withdrawal does not lose or reroll native body")

func per_individual_native_physics() -> void:
	fixture()
	var hard: Unit = actor(); var big: Unit = actor(other_uid)
	var profile: Dictionary = Dragons.physical_profile(Game, row())
	check(hard.mass() == profile["body_mass_kg"] and hard.combat_strength() == profile["strength"], "exact authored individual kg/fractional STR, no belly/height duplicate scaling")
	hard.belly = 99.0; hard.size_h = 140; hard.size_b = 140
	check(hard.mass() == profile["body_mass_kg"], "unrelated humanoid belly/percent fields cannot scale dragon mass again")
	hard.skills["brawler"] = 0; big.skills["brawler"] = 0
	var sim: BattleSim = BattleSim.new()
	sim.setup([hard], [big], 22222, {"w": 12, "h": 7, "cells0": [Vector2i(4,3)], "cells1": [Vector2i(5,3)], "combat_journal": false})
	var a: Fighter = sim.fighters[0]; var b: Fighter = sim.fighters[1]
	check(float(a.rdef["height"]) == float(a.dragon_profile["height_m"]) and float(b.rdef["height"]) > float(a.rdef["height"]) and float(DB.races["dragon"]["height"]) == 3.0, "native arrow silhouette has individual size without shared race mutation")
	var small_bite: Dictionary = sim._swing_for(a, a.dragon_attacks[0][0])
	var big_bite: Dictionary = sim._swing_for(b, b.dragon_attacks[0][0])
	check(a.dragon and b.dragon and a.dragon_attacks[0][0]["native_material"]["shear_yield"] == 800000.0 and b.dragon_attacks[0][0]["native_material"]["shear_yield"] == 160000.0, "same race retains distinct individual gem materials in native strikes")
	check(absf(float(small_bite["p"]) / float(profile["attacks"]["bite"]["p_kg_m_s"]) - 1.0) < 0.000000001 and absf(float(small_bite["E"]) / float(profile["attacks"]["bite"]["energy_j"]) - 1.0) < 0.000000001, "zero-skill/rest native attack scale applied once")
	check(float(big_bite["E"]) > float(small_bite["E"]) and b.reach_tiles >= a.reach_tiles and b.reach_tiles <= 3, "soft giant force/geometry can dominate hard small dragon; bounded native reach")
	check(a.dragon_attacks[0][0]["contact"] == profile["attacks"]["bite"]["attack"]["contact"] and a.dragon_attacks[0][0]["penetration"] == profile["attacks"]["bite"]["attack"]["penetration"], "native contact/penetration comes from actual tooth geometry")
	var pearl: Dictionary = row().duplicate(true); pearl["gem_id"] = "pearl"
	var softer: Dictionary = Dragons.physical_profile(Game, pearl)
	check(softer["body_mass_kg"] == profile["body_mass_kg"] and softer["strength"] == profile["strength"] and softer["bite_force_n"] == profile["bite_force_n"], "gem affects hardness, not body/force/mouth dimensions")
	var steel: Dictionary = DB.materials["steel"]
	var material: Dictionary = profile["tooth_material"]
	var r1: float = Formulas.edge_resistance(steel, material, 8.0, 1.0, 1.0, 1.0, true)
	var r2: float = Formulas.edge_resistance(steel, material, 8.0, 1.0, 1.0, 4.0, true)
	check(is_finite(r1) and is_finite(r2) and r2 > r1, "same native steel varies by actual thickness; hardness is not automatic armour defeat")
	# Inspect tooth material first, before a giant's torso strike can kill its target.
	var tooth: Dictionary = sim.debug_strike(1, 0, "tooth2", 0, true)
	check(tooth["part"] == "tooth2" and not tooth["tissue"].is_empty(), "native targeted tooth contact visits original anatomical tissue, not separate HP")
	var strike: Dictionary = sim.debug_strike(1, 0, "torso_upper", 0, true)
	check(strike["landed"] and not strike["tissue"].is_empty() and hard.body.is_wounded(), "actual native dragon attack damages organic body layers")
	check(strike["dragon_attack"]["material"]["shear_yield"] == 160000.0 and strike["dragon_attack"]["mass_kg"] == big.mass(), "actual outcome retains soft-gem/large-force provenance")
	var jaw: Dictionary = hard.body.wound_part("jaw"); jaw["severed"] = true
	sim._mark_lost(a, "jaw"); sim._update_functions(a, false)
	var usable: Array = NaturalAttacks.attacks_for(sim, a, b)
	check(usable.filter(func(atk: Dictionary): return str(atk["verb"]) == "bite").is_empty(), "native jaw/parent loss prevents a ghost bite")
	for pid: String in big.body.defs():
		if pid.begins_with("tooth") or pid.begins_with("claw"):
			big.body.wound_part(pid)["severed"] = true; sim._mark_lost(b, pid)
	sim._update_functions(b, false)
	check(NaturalAttacks.attacks_for(sim, b, a).is_empty(), "all native tooth/claw losses remove gem-edged attacks without a ghost fallback")
	if sim.combat_journal != null: sim.combat_journal.dispose()

func persistence_growth_care_and_receipt() -> void:
	fixture()
	var unit: Unit = actor(); var body: BodyState = unit.body
	var part: Dictionary = body.wound_part("leg_upper_l")
	for layer: Dictionary in part["layers"]:
		if str(layer["tissue"]) == "muscle": layer["dmg"] = 0.3; layer["kind"] = "cut"; layer["bleed"] = 0.03
	body.wound_part("wing_lower_r")["severed"] = true
	body.permanent.append("right wing lost")
	body.blood *= 0.7; body.pain = 4.0; body.exertion = 30.0
	unit.skill_xp["brawler"] = 123.5; unit.attrs["STR"] += 7
	var wounds: Dictionary = body.parts.duplicate(true); var fraction: float = body.blood / body.blood_max
	row()["growth_points"] = 0.5
	check(DragonCombat.sync_profile(Game, dragon_uid) and body == unit.body and body.parts == wounds and body.permanent == ["right wing lost"], "continuous growth preserves exact sparse wounds/body/lost limb")
	check(absf(body.blood / body.blood_max - fraction) < 0.000000001 and unit.skill_xp["brawler"] == 123.5 and int(unit.attrs["STR"]) - int(unit.attr_base["STR"]) == 7, "growth retains actual blood fraction and native skill/attribute progress")
	var visual: Dictionary = DragonCombat.visual_state(unit)
	check(visual["lost"].has("wing_lower_r") and visual["dmg"]["leg_upper_l"] >= 0.3 and visual["bleed"]["leg_upper_l"] and not visual["lost"].has("head"), "native wing/layer loss maps only correct coherent visual regions")
	visual["dmg"]["leg_upper_l"] = 0.0
	check(body.parts == wounds, "visual snapshots never change actual body")
	var control: Unit = Unit.from_dict(unit.to_dict().duplicate(true))
	Healing.heal(control, 1.0, true, 0)
	DragonCombat.on_care(Game, dragon_uid, 1)
	check(unit.body.to_dict() == control.body.to_dict() and unit.body.is_lost("wing_lower_r"), "scheduled native one-day healing matches direct control and never regrows wing")
	var before: String = snapshot(); DragonCombat.on_care(Game, dragon_uid, 1)
	check(snapshot() == before, "same scheduled care day cannot heal twice")
	var plain: Dictionary = unit.to_dict().duplicate(true)
	var current: Unit = Unit.from_dict(plain.duplicate(true))
	check(current.to_dict() == plain and current.dragon_uid == dragon_uid and current.body.plan_id == "wyvern", "native actor/body current dictionary roundtrip preserves full original physics/injury identity")
	# Restore this native wounded actor to the holder through current native JSON.
	var world: Dictionary = JSON.parse_string(JSON.stringify(Game._serialize(Game.world), "", true, true))
	Game.world = Game._deserialize(world.duplicate(true)); DragonCombat.after_load(Game); Dragons.after_load(Game)
	unit = actor()
	check(unit.dragon_uid == dragon_uid and unit.uid == int(plain["uid"]) and unit.body.is_lost("wing_lower_r") and unit.skill_xp["brawler"] == 123.5 and DragonCombat.uid_floor(Game) > unit.uid, "current JSON retains lost wing/XP/UID floor, no humanoid race mismatch")
	before = snapshot(); DragonCombat.after_load(Game)
	check(snapshot() == before, "current load does not heal/create/reset body on repeat")
	# Fresh actual native fight; only admitted exact holder accepts its receipt.
	fixture(); unit = actor()
	check(DragonCombat.participation_order(Game, dragon_uid, true, DragonCombat.participation_preview(Game, dragon_uid, true))["ok"], "actual selected actor has reviewed admission for receipt test")
	var receipt: Dictionary = DragonCombat.admission_receipt(Game, DragonCombat.battle_units(Game))
	var sim: BattleSim = BattleSim.new()
	sim.setup([unit], [actor(other_uid)], 22009, {"cells0": [Vector2i(4,3)], "cells1": [Vector2i(5,3)], "combat_journal": true})
	var death: Dictionary = sim.debug_strike(1, 0, "brain", 0, true)
	check(death["landed"] and unit.dead and sim.fighters[0].state == "dead", "actual native vital brain destruction kills original dragon actor")
	check(sim.combat_journal.participant(0).get("dragon_uid", "") == dragon_uid and sim.combat_journal.participant(0).get("rider_person_uid", "") == row()["rider_person_uid"], "native fighter journal keeps original dragon and actual bonded person IDs")
	var copy: Unit = Unit.from_dict(unit.to_dict().duplicate(true))
	before = snapshot()
	check(not DragonCombat.on_battle_result(Game, {"fighter_units": [copy]}, receipt)["applied"] and snapshot() == before, "forged same UID result reference cannot consume actual admission or casualty")
	var funds: String = people_and_funds()
	var actual_result: Dictionary = {"fighter_units": [unit, actor(other_uid)], "player_units": [unit], "enemy_units": [actor(other_uid)]}
	check(DragonCombat.on_battle_result(Game, actual_result, receipt)["applied"], "native issued receipt consumes actual holder outcome once")
	check(not row()["alive"] and row()["rider_person_uid"] == "" and row()["last_rider_person_uid"] == native.uid("a",0) and unit.battles == 1 and not row()["combat_order"]["enabled"], "real death ends bond/order with original IDs and one battle count")
	check(people_and_funds() == funds and Game.company.is_empty(), "dragon casualty never debits humanoid population/coin/gear or creates rider Unit")
	before = snapshot(); DragonCombat.on_battle_result(Game, actual_result, receipt); DragonCombat.prepare_world(Game); DragonCombat.after_load(Game)
	check(snapshot() == before and actor() == unit and unit.dead, "repeated result/setup/load cannot revive original dead body or pay rewards")
	sim.combat_journal.dispose()

func run(_tree: SceneTree) -> int:
	var original: Dictionary = {"world": Game.world, "company": Game.company, "squads": Game.squads, "day": Game.day,
		"gold": Game.gold, "location": Game.location, "rng": Game.rng.state, "unit": Unit._next_uid, "item": Item._next_uid}
	native_actor_and_order(); per_individual_native_physics(); persistence_growth_care_and_receipt()
	Game.world = original["world"]; Game.company = original["company"]; Game.squads = original["squads"]
	Game.day = float(original["day"]); Game.gold = int(original["gold"]); Game.location = str(original["location"])
	Game.rng.state = int(original["rng"]); Unit._next_uid = int(original["unit"]); Item._next_uid = int(original["item"])
	native = null
	print("Dragon combat v022: ", checks, " checks, ", fails, " failures")
	return fails
