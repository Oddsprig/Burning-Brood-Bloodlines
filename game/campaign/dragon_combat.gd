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
		float(row.get("care", {}).get("health", 1.0)), str(row.get("sex", "")), float(row.get("birth_day", 0.0)), str(row.get("stage", "")), bool(row.get("flying", false))]

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
	# Autobattles are grounded today; honour an explicit flying state without adding flight mechanics.
	profile["flying"] = bool(row.get("flying", false))
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
		if str(row.get("stage", "")) != "egg":
			DragonGrowth.ensure(row)
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
	# Growth rescales mass and blood. The injured part map, severed limbs and scar list stay put.
	var injured: Dictionary = unit.body.parts
	var marks: Array = unit.body.permanent
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
	if not is_same(unit.body.parts, injured):
		unit.body.parts = injured
	if unit.body.permanent != marks:
		unit.body.permanent = marks
	return true

static func after_load(game) -> void:
	DragonGrowth.ensure_all(game)
	var state: Dictionary = _registry(game)
	for row: Dictionary in state.get("records", {}).values():
		for key: String in ["combat_unit_uid", "combat_last_care_day", "combat_last_receipt"]:
			if row.has(key): row[key] = int(row[key])
	for uid: Variant in state.get("combat_units", {}): sync_profile(game, str(uid))
	if state.has("rider_bodies_day"): state["rider_bodies_day"] = int(state["rider_bodies_day"])
	for row: Variant in state.get("rider_bodies", {}).values():
		if row is Dictionary:
			row["day"] = int(row.get("day", -1))
			for a: Variant in row.get("attrs", {}): row["attrs"][a] = int(row["attrs"][a])
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

## v0.081: the seated riders of the dragons in a battle, for BattleSim's "dragon_riders" option (sim/dragon_riders.gd).
## {str(dragon unit uid): {"unit": Unit, "detached": bool}}. A rider with a Unit of his own (company, reserve,
## prisoner records) rides as that Unit, so his wounds and death are his. Any other living rider rides as a battle
## body made from his register record (race, sex, age, name; no kit), kept for the rounds of this one battle in
## pending_battle["rider_bodies"]; it owns no campaign records and carries no loot.
## r4 (QC 722eaab1): the battle body's physical state is his own. After the battle it is kept by his person uid in
## the dragon registry (kept_bodies: wounds, lost parts, blood, pain, healing timers; saved with the world), his
## next battle body is made with it, and it heals a day at a time like a dragon in care (heal_kept_bodies). It is
## only a body: no register row, no Unit in any roster. If he is later bound to a Unit of his own, that Unit takes
## the kept body at binding; any already present injuries are retained too (adopt_kept_body).
static func battle_riders(game, units: Array) -> Dictionary:
	var out := {}
	for value: Variant in units:
		if not is_dragon_unit(game, value) or value.dead: continue
		var row: Dictionary = _record(game, value.dragon_uid)
		var person_uid := str(row.get("rider_person_uid", ""))
		if person_uid == "" or not bool(row.get("alive", false)): continue
		var person := Dynasty.person(game, person_uid)
		if person.is_empty() or not bool(person.get("alive", false)): continue
		var rider: Unit = Dynasty.bound_unit(game, person)
		if rider != null:
			adopt_kept_body(game, person_uid, rider)
			if not rider.dead: out[str(value.uid)] = {"unit": rider, "detached": false}
			continue
		if not game.pending_battle.has("rider_bodies"): game.pending_battle["rider_bodies"] = {}
		var bodies: Dictionary = game.pending_battle["rider_bodies"]
		var body = bodies.get(person_uid)
		if not body is Unit:
			body = _rider_body(game, person, value)
			bodies[person_uid] = body
		if not body.dead: out[str(value.uid)] = {"unit": body, "detached": true}
	return out

static func _rider_body(game, person: Dictionary, dragon: Unit) -> Unit:
	var race := str(person.get("race", "human"))
	if not DB.races.has(race): race = "human"
	var local := RandomNumberGenerator.new()
	local.seed = hash([int(game.world.get("seed", 0)), str(person.get("person_uid", "")), "rider-body-v081"])
	var u := Unit.create(race, dragon.faction)
	Factory.roll_attrs(local, u)
	Factory.roll_size(local, u)
	Factory.roll_look(local, u)
	u.name = str(person.get("name", "Rider"))
	u.sex = int(person.get("sex", 0))
	u.age = int(person.get("age", 25))
	u.home_town = str(person.get("town_id", ""))
	u.family = int(person.get("family_id", -1))
	u.role = "troop"
	u.title = "dragon rider"
	var kept: Variant = kept_bodies(game).get(str(person.get("person_uid", "")))
	if kept is Dictionary and (kept as Dictionary).get("body") is Dictionary:
		u.body = BodyState.from_dict((kept["body"] as Dictionary).duplicate(true))   # his body as the last battle left it
	return u

## {person uid: {"body": BodyState dict, "attrs": {attr: n}, "race": id, "day": last day healed}} (the dragon registry).
static func kept_bodies(game) -> Dictionary:
	var state: Dictionary = _registry(game)
	if not game.world.has("dragons"): return {}
	if not state.has("rider_bodies"): state["rider_bodies"] = {}
	return state["rider_bodies"]

static func _wounded(body: BodyState) -> bool:
	return body != null and (not body.parts.is_empty() or body.blood < body.blood_max - 1e-9 or body.pain > 0.0)

## After the battle (once per pending battle): each living battle-body rider's body is kept, or dropped when whole;
## a dead one's is dropped (his death went through the register).
static func keep_rider_bodies(game) -> void:
	var pb: Dictionary = game.pending_battle
	if bool(pb.get("rider_bodies_kept", false)): return
	var bodies: Dictionary = pb.get("rider_bodies", {})
	if bodies.is_empty(): return
	pb["rider_bodies_kept"] = true
	var kept := kept_bodies(game)
	for person_uid: Variant in bodies:
		var u: Variant = bodies[person_uid]
		if not (u is Unit): continue
		var alive: bool = not u.dead and not Dynasty._person(game, str(person_uid)).is_empty()
		if alive: Healing.after_battle(u)   # bandaged as every other fighter is
		if alive and _wounded(u.body):
			kept[str(person_uid)] = {"body": u.body.to_dict(), "attrs": u.attrs.duplicate(), "race": u.race, "day": int(game.day)}
		else:
			kept.erase(str(person_uid))

## One day's healing for every kept body (once a day, from the daily dragon care). A body healed whole, a person no
## longer living, or one now bound to a Unit (who takes it) leaves the store.
static func heal_kept_bodies(game, day: int) -> void:
	var state: Dictionary = _registry(game)
	var kept := kept_bodies(game)
	if kept.is_empty() or day <= int(state.get("rider_bodies_day", day - 1)): return
	state["rider_bodies_day"] = day
	for person_uid: String in kept.keys():
		var row: Dictionary = kept[person_uid]
		var person := Dynasty.person(game, person_uid)
		if person.is_empty() or not bool(person.get("alive", false)) or Dynasty._person(game, person_uid).is_empty():
			kept.erase(person_uid)
			continue
		var bound: Unit = Dynasty.bound_unit(game, person)
		if bound != null:
			adopt_kept_body(game, person_uid, bound)
			continue
		if day <= int(row.get("day", -1)): continue
		var u := Unit.new()   # (no uid minted: a frame for the healing rules only)
		u.race = str(row.get("race", "human"))
		for a: Variant in row.get("attrs", {}): u.attrs[str(a)] = int(row["attrs"][a])
		u.body = BodyState.from_dict((row["body"] as Dictionary).duplicate(true))
		Healing.heal(u, 1.0, true, 0)   # one actual day, never retrospective catch-up (as the dragon's care)
		if _wounded(u.body):
			row["body"] = u.body.to_dict()
			row["day"] = day
		else:
			kept.erase(person_uid)

## Join two snapshots of one person's wounds, not two damage events. Shared damage is kept at the worse
## observed state (never added twice); independent parts/layers and permanent marks survive from both.
static func _join_wound_state(target: Dictionary, other: Dictionary) -> void:
	for key: Variant in other:
		var value: Variant = other[key]
		if key == "layers": continue
		if not target.has(key):
			target[key] = value
		elif value is bool:
			target[key] = bool(target[key]) or value
		elif value is int or value is float:
			target[key] = maxf(float(target[key]), float(value))
		elif key == "kind" and int(Healing.KIND_RANK.get(str(value), 1)) > int(Healing.KIND_RANK.get(str(target[key]), 1)):
			target[key] = value

## He now has a Unit of his own. Transfer before publishing him in a roster, preserving an already wounded
## Unit as well as the kept body. Consume the row only after the complete transfer; repeated adoption is a no-op.
static func adopt_kept_body(game, person_uid: String, unit: Unit) -> void:
	var kept := kept_bodies(game)
	if not kept.has(person_uid) or unit == null or unit.dead or unit.body == null: return
	var row: Dictionary = kept[person_uid]
	if not (row.get("body") is Dictionary): return
	var current := unit.body
	var saved: Dictionary = (row["body"] as Dictionary).duplicate(true)
	saved["plan"] = current.plan_id
	var joined := BodyState.from_dict(saved)
	for pid: Variant in current.parts:
		var old_part: Dictionary = joined.wound_part(str(pid))
		var new_part: Dictionary = current.parts[pid]
		_join_wound_state(old_part, new_part)
		var old_layers: Array = old_part.get("layers", [])
		var new_layers: Array = new_part.get("layers", [])
		for i in mini(old_layers.size(), new_layers.size()):
			_join_wound_state(old_layers[i], new_layers[i])
	# Blood is a body state, not another bleeding event. Retain the lower fraction when sizes differ.
	var fraction := minf(joined.blood / maxf(joined.blood_max, 1e-9), current.blood / maxf(current.blood_max, 1e-9))
	joined.blood = clampf(fraction, 0.0, 1.0) * joined.blood_max
	joined.pain = maxf(joined.pain, current.pain)
	joined.exertion = maxf(joined.exertion, current.exertion)
	for mark: Variant in current.permanent:
		if not joined.permanent.has(mark): joined.permanent.append(mark)
	unit.body = joined
	Healing.update_heal_days(unit)
	kept.erase(person_uid)

## Round battles: one record per dragon across the rounds (live damage adds up; a death or fall is kept).
static func merge_seats(st: Dictionary, seats: Dictionary) -> void:
	if not st.has("dragon_seats"): st["dragon_seats"] = {}
	var all: Dictionary = st["dragon_seats"]
	for uid in seats:
		var now: Dictionary = (seats[uid] as Dictionary).duplicate()
		var was: Dictionary = all.get(uid, {})
		if not was.is_empty():
			now["damage"] = float(was.get("damage", 0.0)) + float(now.get("damage", 0.0))
			now["dead"] = bool(was.get("dead", false)) or bool(now.get("dead", false))
			if str(now.get("unseated", "")) == "" or str(was.get("unseated", "")) == "the rider fell": now["unseated"] = was.get("unseated", "")
		all[uid] = now

## Capture at the explicit battle-start boundary; no Unit references in receipt.
static func admission_receipt(game, units: Array) -> Dictionary:
	var admitted: Array = battle_units(game)
	var rows: Array = []
	for value: Variant in units:
		if is_dragon_unit(game, value) and admitted.has(value):
			rows.append({"dragon_uid": value.dragon_uid, "unit_uid": value.uid,
				"rider_person_uid": str(_record(game, value.dragon_uid).get("rider_person_uid", "")),
				"damage_before": rider_damage(value), "flying": bool(value.native_dragon_profile.get("flying", false))})
	if rows.is_empty(): return {}
	var state: Dictionary = _registry(game)
	var receipt: int = int(state.get("next_combat_receipt", 1))
	state["next_combat_receipt"] = receipt + 1
	var issued: Dictionary = {"id": receipt, "day": float(game.day), "town_id": str(game.location), "units": rows,
		"seed": int(game.pending_battle.get("seed", 0))}
	state["combat_admission"] = issued.duplicate(true) # one actual current battle, no owned Unit refs
	return issued

## A derived measure of native tissue loss and blood loss, used only to scale a fall.
static func rider_damage(unit: Unit) -> float:
	if unit.body == null: return 0.0
	var damage := maxf(0.0, 1.0 - unit.body.blood / maxf(0.001, unit.body.blood_max))
	for part: Dictionary in unit.body.parts.values():
		if bool(part.get("severed", false)): damage += 1.0
		for layer: Dictionary in part.get("layers", []):
			damage += float(layer.get("dmg", 0.0))
	return damage

## v0.029 refits issue these actual slots. Broken pieces give no protection.
static func rider_protection(unit: Unit) -> float:
	if unit == null: return 0.0
	var protection := 0.0
	for spec: Array in [[Mobilization.BODY_SLOT, 0.25], [Mobilization.HELM_SLOT, 0.20], ["clothing", 0.15]]:
		var item: Item = unit.equip.get(str(spec[0]))
		if item == null or item.broken or item.slot() != str(spec[0]): continue
		if str(spec[0]) == "clothing" and not bool(item.tmpl().get("padded", false)): continue
		protection += float(spec[1]) * clampf(1.0 - float(item.wear) * 0.2, 0.4, 1.0)
	return protection

## Local RNG: neither the campaign stream nor combat initiative/attacks are consumed.
static func rider_roll(battle_seed: int, dragon_uid: String, person_uid: String, downed: bool,
		flying: bool, damage: float, protection: float) -> Dictionary:
	var harm := clampf(damage, 0.0, 1.0)
	var air := 1.0 if flying else 0.0
	var safe := 1.0 - clampf(protection, 0.0, 0.75)
	var lethal := (0.04 + 0.16 * harm + 0.12 * air) * safe if downed else 0.0
	var wound := (0.30 + 0.25 * harm + 0.10 * air) * safe if downed else (0.04 + 0.16 * harm) * safe
	var random := RandomNumberGenerator.new()
	random.seed = hash([battle_seed, dragon_uid, person_uid, "rider-danger-v054"])
	var roll := random.randf()
	return {"outcome": "killed" if roll < lethal else ("wounded" if roll < lethal + wound else "unhurt"),
		"downed": downed, "flying": flying, "damage": harm, "roll": roll, "kill_chance": lethal, "wound_chance": wound,
		"wound_damage": (0.22 + 0.30 * harm + 0.12 * air) * safe if downed else (0.06 + 0.12 * harm) * safe}

static func _rider_wound(unit: Unit, damage: float) -> void:
	if unit == null or unit.body == null or not unit.body.has_part("torso_upper") or unit.body.is_lost("torso_upper"): return
	# The existing native muscle layer, wound kinds and healing timers persist on this exact Unit.
	for layer: Dictionary in unit.body.wound_part("torso_upper")["layers"]:
		if str(layer["tissue"]) != "muscle": continue
		layer["dmg"] = minf(1.0, float(layer["dmg"]) + damage)
		layer["kind"] = Formulas.worse_kind(str(layer.get("kind", "")), "bruised")
		unit.body.pain += float(Formulas.PAIN_RECEPTORS.get("muscle", 5.0)) * damage
		break
	Healing.update_heal_days(unit)

static func _rider_result(game, result: Dictionary, entry: Dictionary, dragon: Unit, battle_seed: int) -> Dictionary:
	var person_uid := str(entry.get("rider_person_uid", ""))
	if person_uid == "": return {}
	var downs: Dictionary = result.get("dragon_downs", {})
	var downed := dragon.dead or downs.has(dragon.dragon_uid)
	var units: Array = result.get("fighter_units", [])
	var states: Array = result.get("fighter_states", [])
	var idx := units.find(dragon)
	if idx >= 0 and idx < states.size():
		downed = downed or str(states[idx]) in ["dead", "unconscious", "prone"]
	var damage := maxf(0.0, rider_damage(dragon) - float(entry.get("damage_before", 0.0)))
	# v0.081: the rider was a live target on his dragon (sim/dragon_riders.gd). A rider who fell before his dragon
	# went down was not thrown by it; his own live wounds and death come first, then the existing fall rules.
	var seat: Dictionary = result.get("dragon_seats", {}).get(dragon.dragon_uid, {})
	var live_dead := not seat.is_empty() and bool(seat.get("dead", false))
	var live_hurt := not seat.is_empty() and float(seat.get("damage", 0.0)) > 0.0
	var joined := not seat.is_empty() and (bool(seat.get("joined", false)) or bool(seat.get("detached", false)))
	if not seat.is_empty() and str(seat.get("unseated", "")) == "the rider fell": downed = false
	if not downed and damage <= 0.0 and not live_dead and not live_hurt: return {}
	var loc := Dynasty._person(game, person_uid)
	if loc.is_empty(): return {} # The normal death path already retired this person.
	var person := Dynasty.person(game, person_uid)
	var rider: Unit = Dynasty.bound_unit(game, person)
	# r4: a rider with no Unit of his own carries his wounds on his battle body (kept after the battle).
	var carrier: Unit = rider
	if carrier == null:
		var bb: Variant = game.pending_battle.get("rider_bodies", {}).get(person_uid)
		if bb is Unit: carrier = bb
	# An existing combat death is never rolled/handled again. A deployed rider's death is the battle's own
	# casualty; a rider who joined only on his dragon has no roster row, so his live death is settled here.
	if rider != null and rider.dead and not (live_dead and joined and is_same(seat.get("unit"), rider)): return {}
	var flying := bool(downs.get(dragon.dragon_uid, entry.get("flying", false)))
	var outcome := rider_roll(battle_seed, dragon.dragon_uid, person_uid, downed, flying, damage, rider_protection(carrier))
	if not downed and damage <= 0.0:
		outcome["outcome"] = "unhurt"   # no fall and no saddle wound to roll: only the live fight below counts
		outcome["wound_damage"] = 0.0
	var live := ""
	if live_dead:
		outcome["outcome"] = "killed"
		live = "killed"
	elif live_hurt and str(outcome["outcome"]) == "unhurt":
		outcome["outcome"] = "wounded"
		# His live wounds are already on his body (his own Unit, or the battle body that is kept for him).
		outcome["wound_damage"] = 0.0
		live = "wounded"
	outcome["live"] = live
	outcome["live_damage"] = float(seat.get("damage", 0.0))
	outcome["rider_person_uid"] = person_uid
	outcome["rider_name"] = str(person["name"])
	outcome["dragon_uid"] = dragon.dragon_uid
	outcome["dragon_name"] = dragon.name
	var cause := "a fall as %s went down%s" % [dragon.name, " from the air" if flying else ""] if downed else "the saddle as %s was wounded" % dragon.name
	if live != "": cause = "the fighting on %s" % dragon.name
	var fate: String = outcome["outcome"]
	outcome["text"] = "%s %s %s." % [person["name"],
		"escaped unhurt from" if fate == "unhurt" else ("was killed in" if fate == "killed" else ("was wounded in" if downed or live != "" else "was lightly wounded in")), cause]
	var p: Array = loc["person"]
	if fate == "killed":
		var previous_context: Array = Census._ctx.duplicate()
		Census.ctx("battle", str(outcome["text"]))
		if rider != null:
			rider.dead = true
			People.casualty(game, rider, "dead", str(p[4]))
		else:
			if carrier != null: carrier.dead = true   # (his battle body is not kept)
			People.casualty_rec(game, str(person["town_id"]), int(person["family_id"]), str(person["name"]), "dead", str(p[4]), p)
		Census._ctx = previous_context
	elif fate == "wounded":
		if float(outcome["wound_damage"]) > 0.0: _rider_wound(carrier, float(outcome["wound_damage"]))
		elif carrier != null: Healing.update_heal_days(carrier)   # v0.081: live wounds are already on his body
		Persons.log_life(p, float(game.day), "wound", str(outcome["text"]))
		Families.add_hist(loc["family"], str(outcome["text"]), float(game.day))
	var event := {"tick": int(result.get("ticks", 0)), "type": "rider_danger", "actor": idx, "target": -1,
		"text": outcome["text"], "decisive": fate != "unhurt", "part": "", "rider_person_uid": person_uid}
	if not result.has("events"): result["events"] = []
	result["events"].append(event)
	var journal: Variant = result.get("combat_journal")
	if journal is CombatJournal:
		journal.append({"tick": event["tick"], "k": "event", "d": {"event": event, "context": {}}}, idx, -1, "rider_danger")
	return outcome

static func on_battle_result(game, result: Dictionary, receipt: Dictionary) -> Dictionary:
	var out := _apply_battle_result(game, result, receipt)
	keep_rider_bodies(game)   # r4: what the battle did to a battle-body rider is his (any receipt outcome)
	return out

static func _apply_battle_result(game, result: Dictionary, receipt: Dictionary) -> Dictionary:
	var receipt_id: int = int(receipt.get("id", -1))
	var done: Array = []; var rejected: Array = []
	if receipt_id < 1: return {"applied": false, "units": done, "rejected": rejected}
	if receipt != _registry(game).get("combat_admission", {}): return {"applied": false, "units": done, "rejected": rejected, "reason": "No matching issued admission receipt."}
	var participants: Array = result.get("fighter_units", []).duplicate()
	# The final round only lists its own fighters; earlier actual participants remain in the side rosters.
	for value: Variant in result.get("player_units", []) + result.get("enemy_units", []):
		if not participants.has(value): participants.append(value)
	# Validate every admitted actual object before mutating any receipt/actor.
	for entry: Dictionary in receipt.get("units", []):
		var unit: Unit = _unit(game, str(entry.get("dragon_uid", "")))
		if unit == null or not is_dragon_unit(game, unit) or int(entry.get("unit_uid", -1)) != unit.uid:
			rejected.append(str(entry.get("dragon_uid", "")))
		elif not participants.has(unit):
			# An admitted reserve may never have entered a round; a same-ID impostor is still invalid.
			for value: Variant in participants:
				if value is Unit and (value.uid == unit.uid or value.dragon_uid == unit.dragon_uid): rejected.append(unit.dragon_uid)
	if not rejected.is_empty(): return {"applied": false, "units": done, "rejected": rejected}
	var riders: Array = []
	for entry: Dictionary in receipt.get("units", []):
		var uid: String = str(entry.get("dragon_uid", "")); var row: Dictionary = _record(game, uid); var unit: Unit = _unit(game, uid)
		if not participants.has(unit): continue
		if unit == null or not is_dragon_unit(game, unit) or int(entry.get("unit_uid", -1)) != unit.uid: rejected.append(uid); continue
		if int(row.get("combat_last_receipt", 0)) >= receipt_id: continue
		row["combat_last_receipt"] = receipt_id
		# Resolve before dragon death reconciles bonds, and before Game settles the company dead.
		var rider := _rider_result(game, result, entry, unit, int(receipt.get("seed", 0)))
		if not rider.is_empty(): riders.append(rider)
		unit.battles += 1
		Food.clear_battle(unit)
		if unit.dead: _mark_death(game, row, unit, "native battle wounds")
		else: Healing.after_battle(unit)
		Dragons._history(game, row, "dragon_battle", {"unit_uid": unit.uid, "receipt": receipt_id, "alive": not unit.dead, "town_id": str(receipt.get("town_id", ""))})
		done.append({"dragon_uid": uid, "unit_uid": unit.uid, "alive": not unit.dead})
	_registry(game).erase("combat_admission")
	result["rider_outcomes"] = riders
	return {"applied": not done.is_empty(), "receipt": receipt_id, "units": done, "rejected": rejected, "riders": riders}

static func on_care(game, uid: String, day: int) -> void:
	heal_kept_bodies(game, day)   # r4: kept rider bodies heal once a day
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
