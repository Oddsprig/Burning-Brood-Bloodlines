class_name DragonCombat
extends RefCounted
## Persistent original dragon actors in the existing native tissue resolver.
## Readers never allocate bodies, people, equipment, supplies or orders.
const DATA_PATH := "res://data/dragon_combat.json"
static var _definitions: Dictionary = {}

static func definitions() -> Dictionary:
	if _definitions.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: _definitions = parsed
	return _definitions.duplicate(true)

static func register_definitions(db) -> void:
	var data: Dictionary = definitions()
	if data.is_empty(): return
	var plan: Dictionary = data["body"]
	for part: Dictionary in plan["parts"]: part["_ck"] = "wyvern:" + str(part["id"])
	db.bodies["wyvern"] = plan
	db.races["dragon"] = data["race"]

static func _registry(game) -> Dictionary:
	return game.world.get("dragons", {})

static func _record(game, uid: String) -> Dictionary:
	return _registry(game).get("records", {}).get(uid, {})

static func _unit(game, uid: String) -> Unit:
	var value: Variant = _registry(game).get("combat_units", {}).get(uid)
	return value if value is Unit else null

static func is_dragon_unit(game, value: Variant) -> bool:
	if not value is Unit or value.dragon_uid == "": return false
	var row: Dictionary = _record(game, value.dragon_uid)
	return not row.is_empty() and str(row.get("id", "")) == value.dragon_uid \
		and int(row.get("combat_unit_uid", -1)) == value.uid and is_same(_unit(game, value.dragon_uid), value)

static func record_for_unit(game, value: Variant) -> Dictionary:
	return _record(game, value.dragon_uid).duplicate(true) if is_dragon_unit(game, value) else {}

static func uid_floor(game) -> int:
	var floor_uid: int = 1
	for value: Variant in _registry(game).get("combat_units", {}).values():
		if value is Unit: floor_uid = maxi(floor_uid, value.uid + 1)
	for row: Dictionary in _registry(game).get("records", {}).values():
		floor_uid = maxi(floor_uid, int(row.get("combat_unit_uid", -1)) + 1)
	return floor_uid

static func _source(row: Dictionary) -> Array:
	return [str(row.get("id", "")), str(row.get("name", "")), str(row.get("gem_id", "")), str(row.get("morph_id", "")),
		str(row.get("size_class", "")), int(row.get("appearance_seed", 0)), float(DragonGrowth.metrics(row).get("growth_points", -1.0)),
		float(row.get("care", {}).get("health", 1.0)), str(row.get("sex", "")), float(row.get("birth_day", 0.0)), str(row.get("stage", ""))]

static func _profile(game, row: Dictionary) -> Dictionary:
	var profile: Dictionary = Dragons.physical_profile(game, row)
	if not bool(profile.get("active", false)): return {}
	var data: Dictionary = definitions(); var tuning: Dictionary = data["combat"]
	var linear: float = float(DragonGrowth.metrics(row)["linear_scale"])
	var reach: float = float(tuning["reference_reach_m"]) * linear + float(profile["jaw_out_lever_m"]) * float(tuning["reach_jaw_lever_gain"])
	profile["linear_scale"] = linear
	profile["height_m"] = float(data["race"]["height"]) * linear
	profile["width_m"] = float(data["race"]["width"]) * linear
	profile["anatomical_reach_m"] = reach
	profile["reach_m"] = clampf(reach, 0.05, float(tuning["maximum_reach_tiles"]))
	profile["reach_tiles"] = clampi(ceili(float(profile["reach_m"])), 1, 3)
	profile["reach_provenance"] = "Authored neck reach per linear growth plus two jaw out-levers; native grid reach capped at three cells. Gem hardness never sets reach."
	profile["battle_bound"] = true
	profile["source"] = _source(row)
	profile["rider_person_uid"] = str(row.get("rider_person_uid", ""))
	return profile

static func _mark_death(game, row: Dictionary, unit: Unit, cause: String) -> void:
	var first: bool = bool(row.get("alive", false))
	unit.dead = true
	row["alive"] = false
	if row.has("combat_order"): row["combat_order"]["enabled"] = false
	if first:
		row["combat_death_day"] = float(game.day)
		Dragons._history(game, row, "combat_death", {"unit_uid": unit.uid, "cause": cause})
	DragonBond.reconcile(game)

static func prepare_world(game) -> void:
	if not game.world.has("dragons"): return
	var state: Dictionary = _registry(game)
	if not state.has("combat_units"): state["combat_units"] = {}
	var ids: Array = state.get("records", {}).keys(); ids.sort()
	for uid: Variant in ids:
		var row: Dictionary = state["records"][uid]
		if not row.has("combat_order"): row["combat_order"] = {"enabled": false}
		if state["combat_units"].has(uid): continue # never replace an existing physical identity
		if not bool(row.get("alive", false)) or str(row.get("stage", "")) not in ["juvenile", "adult"]: continue
		var profile: Dictionary = _profile(game, row)
		if profile.is_empty(): continue
		var unit: Unit = Unit.create("dragon", "", false)
		unit.dragon_uid = str(uid); unit.role = "dragon"; unit.squad = -1; unit.family = -1
		unit.fav_drink = "none"; unit.belly = float(definitions()["combat"]["initial_belly"])
		unit.skills.merge(definitions()["combat"]["skills"], true)
		unit.native_dragon_profile = profile
		unit.body.plan_id = "wyvern"
		unit.body.init_from_plan(DB.bodies["wyvern"], float(profile["body_mass_kg"]))
		row["combat_unit_uid"] = unit.uid; row["combat_last_care_day"] = int(floor(game.day))
		state["combat_units"][uid] = unit
		sync_profile(game, str(uid))
	Unit._next_uid = maxi(Unit._next_uid, uid_floor(game))

## Boundary refresh only: keep wounds, body identity, loss, blood fraction and XP.
static func sync_profile(game, uid: String) -> bool:
	var unit: Unit = _unit(game, uid); var row: Dictionary = _record(game, uid)
	if unit == null or not is_dragon_unit(game, unit) or unit.race != "dragon" or unit.body == null or unit.body.plan_id != "wyvern": return false
	if unit.dead or not bool(row.get("alive", false)):
		_mark_death(game, row, unit, "native body or care death"); return true
	var profile: Dictionary = _profile(game, row)
	if profile.is_empty(): return false
	var fraction: float = unit.body.blood / maxf(0.001, unit.body.blood_max)
	var learned: int = int(unit.attrs.get("STR", 1000)) - int(unit.attr_base.get("STR", 1000))
	var old_base: int = int(unit.attr_base.get("STR", 1000))
	var base: int = int(profile["strength"])
	unit.attrs["STR"] = base + learned; unit.attr_base["STR"] = base
	unit.attr_cap["STR"] = maxi(base + learned, int(unit.attr_cap.get("STR", DB.attr_ceiling(old_base, old_base))) + base - old_base)
	unit.native_dragon_profile = profile
	unit.name = str(row["name"]); unit.title = Dragons.type_label(row)
	unit.born = float(row.get("birth_day", game.day)); unit.age = int(Dragons.age_years(game, row))
	unit.sex = 1 if str(row.get("sex", "")) == "female" else 0
	unit.home_town = str(row.get("location_town_id", ""))
	unit.faction = str(game.world.get("towns", {}).get(unit.home_town, {}).get("faction", ""))
	unit.body.scale = pow(float(profile["body_mass_kg"]) / 70.0, 1.0 / 3.0)
	var blood_max: float = 100.0 * float(profile["body_mass_kg"]) / 70.0
	if blood_max != unit.body.blood_max:
		unit.body.blood_max = blood_max
		unit.body.blood = maxf(0.0, fraction * blood_max)
	return true

static func after_load(game) -> void:
	var state: Dictionary = _registry(game)
	for row: Dictionary in state.get("records", {}).values():
		for key: String in ["combat_unit_uid", "combat_last_care_day", "combat_last_receipt"]:
			if row.has(key): row[key] = int(row[key])
	for uid: Variant in state.get("combat_units", {}): sync_profile(game, str(uid))
	Unit._next_uid = maxi(Unit._next_uid, uid_floor(game))

static func _enable_reason(game, row: Dictionary, unit: Unit) -> String:
	if row.is_empty() or unit == null or not is_dragon_unit(game, unit) or not unit.is_native_dragon(): return "No valid saved native dragon body is available."
	if not bool(row.get("alive", false)) or unit.dead: return "This dragon is deceased."
	if str(row.get("stage", "")) != "adult": return "Only an adult dragon can defend a settlement."
	var rights: Dictionary = Dragons.authority(game, row)
	if not bool(rights["ok"]): return str(rights["reason"])
	if unit.native_dragon_profile.get("source", []) != _source(row): return "The dragon's current physical profile needs its native boundary refresh."
	var location: String = str(row.get("location_town_id", ""))
	var owner: Dictionary = Dragons._person(game, str(row.get("owner_person_uid", "")))
	if owner.is_empty() or str(owner["town_id"]) != location: return "The dragon must be at its owning household's actual home settlement."
	if not Mobilization._here(game, location): return "Visit the dragon's recorded home settlement; remote defence cannot summon it."
	var bond: Dictionary = DragonBond.status(game, str(row["id"]))
	var rider: Dictionary = bond["rider"]
	if not bool(bond["active"]) or not DragonBond._adult(rider) or not DragonBond._present(game, rider, location): return "A living adult bonded person must be actually present here."
	var health: Dictionary = HealthReport.describe(unit)
	if str(health["status"]) != "healthy" or str(health["fitness"]) != "fit to fight": return "This native body must recover before defending: " + str(health["fitness"]) + "."
	if float(row.get("care", {}).get("health", 0.0)) <= 0.0: return "Its daily care health is depleted."
	return ""

static func _order_matches(row: Dictionary) -> bool:
	var order: Dictionary = row.get("combat_order", {})
	return bool(order.get("enabled", false)) and str(order.get("town_id", "")) == str(row.get("location_town_id", "")) \
		and str(order.get("owner_person_uid", "")) == str(row.get("owner_person_uid", "")) \
		and str(order.get("owner_household_uid", "")) == str(row.get("owner_household_uid", "")) \
		and str(order.get("rider_person_uid", "")) == str(row.get("rider_person_uid", ""))

static func combat_status(game, uid: String) -> Dictionary:
	var row: Dictionary = _record(game, uid); var unit: Unit = _unit(game, uid)
	var rights: Dictionary = Dragons.authority(game, row)
	var enabled: bool = bool(row.get("combat_order", {}).get("enabled", false))
	var reason: String = _enable_reason(game, row, unit)
	var admitted: bool = enabled and reason == "" and _order_matches(row)
	if enabled and reason == "" and not _order_matches(row): reason = "Ownership, rider or location changed. Withdraw and review a new defence order."
	var health: Dictionary = HealthReport.describe(unit) if unit != null and unit.body != null and DB.bodies.has(unit.body.plan_id) else {}
	return {"ok": not row.is_empty(), "dragon_uid": uid, "unit_uid": unit.uid if unit != null else -1,
		"enabled": enabled, "admitted": admitted, "can_enable": not enabled and reason == "", "can_withdraw": enabled and bool(rights["ok"]),
		"reason": reason if reason != "" else ("Defending this settlement." if enabled else "Defence is not ordered."),
		"health": health, "rider_person_uid": str(row.get("rider_person_uid", "")), "location_town_id": str(row.get("location_town_id", "")),
		"owner_household_uid": str(row.get("owner_household_uid", "")), "profile": unit.native_dragon_profile.duplicate(true) if unit != null else {}}

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": reason}

static func participation_preview(game, uid: String, enabled: bool) -> Dictionary:
	if game.get("_save_capture") != null: return _failure("Wait for the consistent save snapshot to finish.")
	var row: Dictionary = _record(game, uid); var unit: Unit = _unit(game, uid)
	var rights: Dictionary = Dragons.authority(game, row)
	if not bool(rights["ok"]): return rights
	if enabled == bool(row.get("combat_order", {}).get("enabled", false)): return _failure("This defence order is already recorded.")
	if enabled:
		var reason: String = _enable_reason(game, row, unit)
		if reason != "": return _failure(reason)
	return {"ok": true, "dragon_uid": uid, "enabled": enabled, "action": "defend" if enabled else "withdraw",
		"reason": "Defend this home settlement in its actual local battle." if enabled else "Withdraw this dragon from settlement battles.",
		"authority_person_uid": rights["authority_person_uid"], "authority_household_uid": rights["authority_household_uid"],
		"source": row.duplicate(true), "body": unit.to_dict() if unit != null else {}, "day": float(game.day),
		"contact": str(game.location) if enabled else ""}

static func participation_order(game, uid: String, enabled: bool, review: Dictionary = {}) -> Dictionary:
	if review.is_empty(): return _failure("Review this defence order before confirming it.")
	var fresh: Dictionary = participation_preview(game, uid, enabled)
	if not bool(fresh["ok"]): return fresh
	if review != fresh: return _failure("The household, rider, body or location changed. Review the order again.")
	var row: Dictionary = _record(game, uid)
	row["combat_order"] = {"enabled": enabled, "town_id": str(row.get("location_town_id", "")),
		"owner_person_uid": str(row["owner_person_uid"]), "owner_household_uid": str(row["owner_household_uid"]),
		"rider_person_uid": str(row.get("rider_person_uid", "")), "authorized_by_person_uid": fresh["authority_person_uid"], "day": float(game.day)}
	var unit: Unit = _unit(game, uid)
	if unit != null: unit.native_dragon_profile["rider_person_uid"] = str(row.get("rider_person_uid", ""))
	Dragons._history(game, row, "defence_order", {"enabled": enabled, "town_id": row["location_town_id"], "authorized_by_person_uid": fresh["authority_person_uid"]})
	return {"ok": true, "reason": "Settlement defence ordered." if enabled else "Settlement defence withdrawn.", "record": row.duplicate(true)}

static func battle_units(game) -> Array:
	var units: Array = []; var ids: Array = _registry(game).get("records", {}).keys(); ids.sort()
	for uid: Variant in ids:
		var row: Dictionary = _record(game, str(uid))
		if not _order_matches(row): continue
		var unit: Unit = _unit(game, str(uid))
		if _enable_reason(game, row, unit) == "" and not units.has(unit): units.append(unit)
	# Dragons ordered to march with the field army fight wherever the army fights (campaign/warfare.gd).
	for unit: Unit in Warfare.marching_units(game):
		if not units.has(unit): units.append(unit)
	return units

## Capture at the explicit battle-start boundary; no Unit references in receipt.
static func admission_receipt(game, units: Array) -> Dictionary:
	var admitted: Array = battle_units(game)
	var rows: Array = []
	for value: Variant in units:
		if is_dragon_unit(game, value) and admitted.has(value):
			rows.append({"dragon_uid": value.dragon_uid, "unit_uid": value.uid})
	if rows.is_empty(): return {}
	var state: Dictionary = _registry(game)
	var receipt: int = int(state.get("next_combat_receipt", 1))
	state["next_combat_receipt"] = receipt + 1
	var issued: Dictionary = {"id": receipt, "day": float(game.day), "town_id": str(game.location), "units": rows}
	state["combat_admission"] = issued.duplicate(true) # one actual current battle, no owned Unit refs
	return issued

static func on_battle_result(game, result: Dictionary, receipt: Dictionary) -> Dictionary:
	var receipt_id: int = int(receipt.get("id", -1))
	var done: Array = []; var rejected: Array = []
	if receipt_id < 1: return {"applied": false, "units": done, "rejected": rejected}
	if receipt != _registry(game).get("combat_admission", {}): return {"applied": false, "units": done, "rejected": rejected, "reason": "No matching issued admission receipt."}
	var participants: Array = result.get("fighter_units", [])
	if participants.is_empty(): participants = result.get("player_units", []) + result.get("enemy_units", [])
	# Validate every admitted actual object before mutating any receipt/actor.
	for entry: Dictionary in receipt.get("units", []):
		var unit: Unit = _unit(game, str(entry.get("dragon_uid", "")))
		if unit == null or not is_dragon_unit(game, unit) or int(entry.get("unit_uid", -1)) != unit.uid or not participants.has(unit): rejected.append(str(entry.get("dragon_uid", "")))
	if not rejected.is_empty(): return {"applied": false, "units": done, "rejected": rejected}
	for entry: Dictionary in receipt.get("units", []):
		var uid: String = str(entry.get("dragon_uid", "")); var row: Dictionary = _record(game, uid); var unit: Unit = _unit(game, uid)
		if unit == null or not is_dragon_unit(game, unit) or int(entry.get("unit_uid", -1)) != unit.uid or not participants.has(unit): rejected.append(uid); continue
		if int(row.get("combat_last_receipt", 0)) >= receipt_id: continue
		row["combat_last_receipt"] = receipt_id
		unit.battles += 1
		Food.clear_battle(unit)
		if unit.dead: _mark_death(game, row, unit, "native battle wounds")
		else: Healing.after_battle(unit)
		Dragons._history(game, row, "dragon_battle", {"unit_uid": unit.uid, "receipt": receipt_id, "alive": not unit.dead, "town_id": str(receipt.get("town_id", ""))})
		done.append({"dragon_uid": uid, "unit_uid": unit.uid, "alive": not unit.dead})
	_registry(game).erase("combat_admission")
	return {"applied": not done.is_empty(), "receipt": receipt_id, "units": done, "rejected": rejected}

static func on_care(game, uid: String, day: int) -> void:
	var row: Dictionary = _record(game, uid); var unit: Unit = _unit(game, uid)
	if unit == null or not is_dragon_unit(game, unit): return
	if unit.dead or not bool(row.get("alive", false)): _mark_death(game, row, unit, "native body or care death"); return
	if day <= int(row.get("combat_last_care_day", day)): return
	row["combat_last_care_day"] = day
	sync_profile(game, uid)
	Healing.heal(unit, 1.0, true, 0) # one actual scheduled day, never retrospective catchup

static func attack_rows(unit: Unit, profile: Dictionary) -> Array:
	var rows: Array = []
	for kind: String in ["bite", "claw"]:
		var attack: Dictionary = profile["attacks"][kind]["attack"].duplicate(true)
		attack["creature"] = true; attack["native_material"] = profile["tooth_material" if kind == "bite" else "claw_material"].duplicate(true)
		var needed: Array[String] = []
		if kind == "bite":
			needed.append("jaw")
		else:
			needed.append("foot_l"); needed.append("foot_r")
		var tips: Dictionary = {}
		for root: String in needed:
			tips[root] = []
			for pid: String in unit.body.defs():
				if (kind == "bite" and pid.begins_with("tooth")) or (kind == "claw" and pid.begins_with("claw") and pid.ends_with(root.trim_prefix("foot"))):
					tips[root].append(pid)
		rows.append([attack, needed, tips]) # cached once; missing tips cannot retain gem edges
	return rows

## Detached regional visual snapshot; anatomical losses remain physically native.
static func visual_state(unit: Unit) -> Dictionary:
	var out: Dictionary = {"lost": [], "dmg": {}, "wk": {}, "bleed": {}, "blood": 1.0, "dead": unit.dead}
	if unit.body == null or not DB.bodies.has(unit.body.plan_id): return out
	var body: BodyState = unit.body
	out["blood"] = clampf(body.blood / maxf(0.001, body.blood_max), 0.0, 1.0)
	for pid: String in body.lost_ids():
		var region: String = str(body.part_def(pid).get("visual_region", "torso"))
		if pid in ["head", "neck"] and not out["lost"].has(pid): out["lost"].append(pid)
		elif pid.begins_with("tooth") or pid.begins_with("claw"):
			out["lost"].append(pid) # tiny tip effects, not an invented missing head
		else:
			if not out["lost"].has(region): out["lost"].append(region)
			out["dmg"][region] = 1.0; out["wk"][region] = "mangled"
	for pid: String in body.parts:
		var region: String = str(body.part_def(pid).get("visual_region", "torso"))
		for layer: Dictionary in body.parts[pid]["layers"]:
			var damage: float = float(layer.get("dmg", 0.0))
			if damage > float(out["dmg"].get(region, 0.0)):
				out["dmg"][region] = damage; out["wk"][region] = str(layer.get("kind", ""))
			if float(layer.get("bleed", 0.0)) > 0.0: out["bleed"][region] = true
	return out
