class_name DragonBreeding
extends RefCounted
## Player-directed dragon pairing, clutch laying, and trait inheritance.
const LAY_MAX_DAYS := 20
const RARE_GEM_CHANCE := 0.08
const RARE_GEM_IDS := ["diamond", "black_diamond", "ruby", "sapphire", "opal", "pearl"]
const VARIATION_CHANNELS := ["mass", "strength", "tooth", "claw", "tooth_contact", "claw_contact", "jaw_lever", "jaw_gain"]

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": reason, "clutch_estimate": 0, "traits_preview": {}}

static func _pairs(game) -> Dictionary:
	var state: Dictionary = game.world.get("dragons", {})
	if not state.has("pairs") or not (state["pairs"] is Dictionary):
		state["pairs"] = {}
	return state["pairs"]

static func pairs(game) -> Dictionary:
	return _pairs(game).duplicate(true)

static func house_dragon_count(game, house_uid: String) -> int:
	if house_uid == "": return 0
	var count := 0
	var records: Dictionary = game.world.get("dragons", {}).get("records", {})
	for row: Dictionary in records.values():
		if bool(row.get("alive", false)) and str(row.get("owner_house_uid", "")) == house_uid:
			count += 1
	return count

static func _lay_delay(game, mother_uid: String, father_uid: String, salt: int) -> int:
	return 1 + (Dragons._seed(game, "%s:%s:lay_days:%d" % [mother_uid, father_uid, salt]) % LAY_MAX_DAYS)

static func _clutch_count(game, mother_uid: String, father_uid: String, salt: int, headroom: int) -> int:
	if headroom <= 0: return 0
	var raw: int = 1 + (Dragons._seed(game, "%s:%s:clutch_size:%d" % [mother_uid, father_uid, salt]) % 3)
	return clampi(raw, 1, mini(3, headroom))

static func rare_gems() -> Array:
	var gems: Array = Dragons.catalogs().get("gems", [])
	var out: Array = []
	for g: Dictionary in gems:
		var gid: String = str(g.get("id", ""))
		if gid in RARE_GEM_IDS or float(g.get("hardness_index", 0.0)) >= 90.0:
			out.append(gid)
	if out.is_empty():
		for g: Dictionary in gems:
			out.append(str(g.get("id", "")))
	return out

static func is_rare_gem(gem_id: String) -> bool:
	return gem_id in rare_gems()

static func pick_gem_id(game, mother: Dictionary, father: Dictionary, key: String) -> String:
	var roll: float = float(Dragons._seed(game, key + ":rare_gem") % 10000) / 10000.0
	if roll < RARE_GEM_CHANCE:
		var pool: Array = rare_gems()
		if not pool.is_empty():
			var idx: int = Dragons._seed(game, key + ":rare_gem_pick") % pool.size()
			return str(pool[idx])
	var pick_mother: bool = (Dragons._seed(game, key + ":parent_gem") % 2) == 0
	return str(mother.get("gem_id", "")) if pick_mother else str(father.get("gem_id", ""))

static func pick_morph_id(game, mother: Dictionary, father: Dictionary, key: String) -> String:
	var pick_mother: bool = (Dragons._seed(game, key + ":parent_morph") % 2) == 0
	return str(mother.get("morph_id", "")) if pick_mother else str(father.get("morph_id", ""))

static func inherited_variation(game, mother: Dictionary, father: Dictionary, key: String) -> Dictionary:
	var out := {}
	for ch in VARIATION_CHANNELS:
		var channel: String = str(ch)
		var mv: float = Dragons._variation(mother, channel)
		var fv: float = Dragons._variation(father, channel)
		var avg: float = 0.5 * (mv + fv)
		var seed_val: int = Dragons._seed(game, key + ":variation:" + channel)
		var noise: float = (float(seed_val % 41) - 20.0) / 1000.0
		out[channel] = clampf(avg + noise, 0.85, 1.15)
	return out

static func traits_preview(_game, mother: Dictionary, father: Dictionary) -> Dictionary:
	var avg_var := {}
	for ch in VARIATION_CHANNELS:
		var channel: String = str(ch)
		avg_var[channel] = 0.5 * (Dragons._variation(mother, channel) + Dragons._variation(father, channel))
	var m_gem: String = str(mother.get("gem_id", ""))
	var f_gem: String = str(father.get("gem_id", ""))
	var m_morph: String = str(mother.get("morph_id", ""))
	var f_morph: String = str(father.get("morph_id", ""))
	return {
		"mother_gem_id": m_gem,
		"father_gem_id": f_gem,
		"possible_gems": [m_gem, f_gem],
		"rare_gem_chance": RARE_GEM_CHANCE,
		"rare_gems": rare_gems(),
		"mother_morph_id": m_morph,
		"father_morph_id": f_morph,
		"possible_morphs": [m_morph, f_morph],
		"variation_average": avg_var,
		"bloodline_uid": str(mother.get("bloodline_uid", ""))
	}

static func pair_preview(game, mother_uid: String, father_uid: String) -> Dictionary:
	var records: Dictionary = game.world.get("dragons", {}).get("records", {})
	var mother: Dictionary = records.get(mother_uid, {})
	var father: Dictionary = records.get(father_uid, {})
	if mother.is_empty() or father.is_empty():
		return _failure("Both dragons must exist in the registry.")
	if mother_uid == father_uid:
		return _failure("Choose two distinct dragons to form a pair.")
	if not bool(mother.get("alive", false)) or not bool(father.get("alive", false)):
		return _failure("Both dragons must be alive.")
	if str(mother.get("stage", "")) != "adult" or str(father.get("stage", "")) != "adult":
		return _failure("Both dragons must be adults to breed.")
	if str(mother.get("sex", "")) != "female" or str(father.get("sex", "")) != "male":
		return _failure("Breeding requires an adult female mother and an adult male father.")
	var player_house: String = str(game.world.get("player_house", {}).get("house_uid", ""))
	if player_house == "" or str(mother.get("owner_house_uid", "")) != player_house or str(father.get("owner_house_uid", "")) != player_house:
		return _failure("Both dragons must belong to the player's house.")
	if str(mother.get("owner_status", "claimed")) != "claimed" or str(father.get("owner_status", "claimed")) != "claimed":
		return _failure("Both dragons must be claimed by your house.")
	var mother_owner: Dictionary = Dragons._person(game, str(mother.get("owner_person_uid", "")))
	if mother_owner.is_empty():
		return _failure("The mother dragon must have a living registered owner.")
	var town_id: String = str(mother.get("location_town_id", ""))
	if town_id == "" or town_id != str(father.get("location_town_id", "")) or not game.world.get("towns", {}).has(town_id):
		return _failure("Both dragons must be at the same roost town.")
	if bool(mother.get("campaign_march", {}).get("enabled", false)) or bool(father.get("campaign_march", {}).get("enabled", false)):
		return _failure("Marching dragons cannot be paired for breeding.")
	var m_health: float = float(mother.get("care", {}).get("health", 1.0))
	var f_health: float = float(father.get("care", {}).get("health", 1.0))
	if m_health < 0.7 or f_health < 0.7:
		return _failure("Both dragons must have at least 0.7 health to breed.")
	var day: int = int(floor(float(game.day)))
	var last_clutch: int = int(mother.get("last_clutch_day", -DragonLife.BREED_COOLDOWN))
	if day - last_clutch < DragonLife.BREED_COOLDOWN:
		return _failure("The mother is still on breeding cooldown.")
	var current_count: int = house_dragon_count(game, player_house)
	var headroom: int = DragonLife.MAX_DRAGONS_PER_HOUSE - current_count
	if headroom <= 0:
		return _failure("Your house has reached the maximum of %d dragons." % DragonLife.MAX_DRAGONS_PER_HOUSE)
	var lay_days: int = _lay_delay(game, mother_uid, father_uid, last_clutch)
	var clutch_est: int = _clutch_count(game, mother_uid, father_uid, last_clutch, headroom)
	var traits: Dictionary = traits_preview(game, mother, father)
	var reason := "%s and %s can be paired at %s (expected clutch of %d within %d days)." % [
		str(mother.get("name", mother_uid)), str(father.get("name", father_uid)), town_id, clutch_est, lay_days]
	return {
		"ok": true,
		"reason": reason,
		"message": reason,
		"mother_uid": mother_uid,
		"father_uid": father_uid,
		"house_uid": player_house,
		"town_id": town_id,
		"lay_days": lay_days,
		"clutch_estimate": clutch_est,
		"clutch_min": 1,
		"clutch_max": mini(3, headroom),
		"traits_preview": traits
	}

static func pair(game, mother_uid: String, father_uid: String, review: Dictionary = {}) -> Dictionary:
	var fresh: Dictionary = pair_preview(game, mother_uid, father_uid)
	if not bool(fresh.get("ok", false)):
		return fresh
	if not review.is_empty():
		if not bool(review.get("ok", false)) or str(review.get("mother_uid", mother_uid)) != mother_uid or str(review.get("father_uid", father_uid)) != father_uid:
			return _failure("The breeding review no longer matches this pair.")
	var state_pairs: Dictionary = _pairs(game)
	var records: Dictionary = game.world.get("dragons", {}).get("records", {})
	if state_pairs.has(mother_uid) and (state_pairs[mother_uid] is Dictionary):
		var cur: Dictionary = state_pairs[mother_uid]
		if str(cur.get("mother_uid", mother_uid)) == mother_uid and str(cur.get("father_uid", "")) == father_uid:
			(records[mother_uid] as Dictionary)["paired_with_uid"] = father_uid
			(records[father_uid] as Dictionary)["paired_with_uid"] = mother_uid
			return {
				"ok": true,
				"reason": str(fresh["reason"]),
				"message": "Chosen breeding pair established.",
				"pair": cur.duplicate(true),
				"clutch_estimate": int(cur.get("clutch_estimate", fresh["clutch_estimate"])),
				"traits_preview": (fresh["traits_preview"] as Dictionary).duplicate(true)
			}
	var to_remove: Array = []
	for k in state_pairs.keys():
		if not (state_pairs[k] is Dictionary):
			to_remove.append(k)
			continue
		var existing: Dictionary = state_pairs[k]
		var em: String = str(existing.get("mother_uid", k))
		var ef: String = str(existing.get("father_uid", ""))
		if em == mother_uid or em == father_uid or ef == mother_uid or ef == father_uid:
			to_remove.append(k)
			if records.has(em): (records[em] as Dictionary).erase("paired_with_uid")
			if records.has(ef): (records[ef] as Dictionary).erase("paired_with_uid")
	for k in to_remove:
		state_pairs.erase(k)
	var day: int = int(floor(float(game.day)))
	var mother: Dictionary = records[mother_uid]
	var father: Dictionary = records[father_uid]
	var lay_days: int = int(fresh["lay_days"])
	var entry := {
		"mother_uid": mother_uid,
		"father_uid": father_uid,
		"house_uid": str(fresh["house_uid"]),
		"town_id": str(fresh["town_id"]),
		"paired_day": day,
		"due_day": day + lay_days,
		"clutch_estimate": int(fresh["clutch_estimate"]),
		"last_clutch_day": int(mother.get("last_clutch_day", -DragonLife.BREED_COOLDOWN)),
		"clutches": 0
	}
	state_pairs[mother_uid] = entry
	mother["paired_with_uid"] = father_uid
	father["paired_with_uid"] = mother_uid
	Dragons._history(game, mother, "paired", {"partner_uid": father_uid, "due_day": int(entry["due_day"])})
	Dragons._history(game, father, "paired", {"partner_uid": mother_uid, "due_day": int(entry["due_day"])})
	return {
		"ok": true,
		"reason": str(fresh["reason"]),
		"message": "Chosen breeding pair established.",
		"pair": entry.duplicate(true),
		"clutch_estimate": int(fresh["clutch_estimate"]),
		"traits_preview": (fresh["traits_preview"] as Dictionary).duplicate(true)
	}

static func spawn_egg(game, mother: Dictionary, father: Dictionary, day: int, egg_index: int) -> Dictionary:
	var town_id: String = str(mother.get("location_town_id", ""))
	var owner: Dictionary = Dragons._person(game, str(mother.get("owner_person_uid", "")))
	if owner.is_empty():
		return {}
	var key := "%s:%s:clutch:%d:%d" % [str(mother["id"]), str(father["id"]), day, egg_index]
	var gem_id: String = pick_gem_id(game, mother, father, key)
	var morph_id: String = pick_morph_id(game, mother, father, key)
	var gems: Array = Dragons.catalogs()["gems"]
	var palette := 0
	for i in gems.size():
		if str((gems[i] as Dictionary).get("id", "")) == gem_id:
			palette = i
			break
	var egg: Dictionary = Dragons._make(game, "egg", town_id, owner, key, palette, "unknown",
		str(mother["id"]), str(father["id"]), str(mother.get("bloodline_uid", "")))
	egg["gem_id"] = gem_id
	var gem_row: Dictionary = Dragons._catalog_row("gems", gem_id)
	if not gem_row.is_empty():
		egg["name"] = str(gem_row["name"]) + " Egg"
	if morph_id != "":
		egg["morph_id"] = morph_id
	egg["variation"] = inherited_variation(game, mother, father, key)
	var inherited := DragonGrowth.inherit(game, mother, father, key)
	var egg_points := DragonGrowth.current_points(egg)
	if egg_points < 0.0: egg_points = 0.0
	egg["growth_potential"] = clampf(maxf(inherited, egg_points), 0.0, DragonGrowth.MAX_POINTS)
	egg["laid_day"] = float(day)
	egg["incubation"] = 0.0
	Dragons._history(game, mother, "clutch", {"egg_uid": egg["id"], "father_uid": str(father["id"]), "day": day})
	Dragons._history(game, father, "sired_clutch", {"egg_uid": egg["id"], "mother_uid": str(mother["id"]), "day": day})
	return egg

static func breed_chosen_pairs(game, registry: Dictionary, day: int) -> Array:
	var laid: Array = []
	var state_pairs: Dictionary = _pairs(game)
	var mother_ids: Array = state_pairs.keys()
	mother_ids.sort()
	for m_key in mother_ids:
		var mother_uid: String = str(m_key)
		if not (state_pairs[m_key] is Dictionary):
			state_pairs.erase(m_key)
			continue
		var entry: Dictionary = state_pairs[mother_uid]
		var father_uid: String = str(entry.get("father_uid", ""))
		var mother: Dictionary = registry.get(mother_uid, {})
		var father: Dictionary = registry.get(father_uid, {})
		var pair_house: String = str(entry.get("house_uid", ""))
		if pair_house == "":
			pair_house = str(mother.get("owner_house_uid", ""))
		if mother.is_empty() or father.is_empty() \
				or not bool(mother.get("alive", false)) or not bool(father.get("alive", false)) \
				or pair_house == "" \
				or str(mother.get("owner_house_uid", "")) != pair_house \
				or str(father.get("owner_house_uid", "")) != pair_house \
				or str(mother.get("owner_status", "claimed")) != "claimed" \
				or str(father.get("owner_status", "claimed")) != "claimed":
			state_pairs.erase(mother_uid)
			if not mother.is_empty(): mother.erase("paired_with_uid")
			if not father.is_empty(): father.erase("paired_with_uid")
			continue
		if day < int(entry.get("due_day", day + 1)):
			continue
		var check: Dictionary = pair_preview(game, mother_uid, father_uid)
		if not bool(check.get("ok", false)):
			continue
		var house_uid: String = str(mother.get("owner_house_uid", ""))
		var headroom: int = DragonLife.MAX_DRAGONS_PER_HOUSE - house_dragon_count(game, house_uid)
		if headroom <= 0:
			continue
		var last_clutch: int = int(mother.get("last_clutch_day", -DragonLife.BREED_COOLDOWN))
		var count: int = _clutch_count(game, mother_uid, father_uid, last_clutch, headroom)
		var clutch_eggs: Array = []
		for i in count:
			var egg: Dictionary = spawn_egg(game, mother, father, day, i)
			if not egg.is_empty():
				clutch_eggs.append(egg)
				laid.append(egg)
		if not clutch_eggs.is_empty():
			mother["last_clutch_day"] = day
			entry["last_clutch_day"] = day
			entry["clutches"] = int(entry.get("clutches", 0)) + 1
			entry["due_day"] = day + DragonLife.BREED_COOLDOWN + _lay_delay(game, mother_uid, father_uid, day)
			var town_id: String = str(mother.get("location_town_id", ""))
			var first_egg: Dictionary = clutch_eggs[0]
			DragonLife._announce(game, first_egg, "%s and %s have produced a clutch of %d egg(s) at %s." % [
				mother.get("name", "?"), father.get("name", "?"), clutch_eggs.size(),
				game.world.get("towns", {}).get(town_id, {}).get("name", "their roost")])
	return laid

static func after_load(game) -> void:
	if not game.world.has("dragons"): return
	DragonGrowth.ensure_all(game)
	var state: Dictionary = game.world["dragons"]
	if not state.has("pairs") or not (state["pairs"] is Dictionary):
		state["pairs"] = {}
		return
	var state_pairs: Dictionary = state["pairs"]
	for k in state_pairs.keys():
		var entry: Variant = state_pairs[k]
		if entry is Dictionary:
			var d: Dictionary = entry
			for field in ["paired_day", "due_day", "clutch_estimate", "last_clutch_day", "clutches"]:
				if d.has(field):
					d[field] = int(d[field])
		else:
			state_pairs.erase(k)
