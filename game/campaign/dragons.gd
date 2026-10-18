class_name Dragons
extends RefCounted
## Individual wyverns and eggs, stored as plain records. No Units, items,
## population or accounts. Native daily care/growth; bonding/combat come later.
const HISTORY_LIMIT := 32
const DATA_PATH := "res://data/dragons.json"
static var _catalog: Dictionary = {}

static func _ensure_catalog() -> void:
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: _catalog = parsed

static func catalogs() -> Dictionary:
	_ensure_catalog()
	return _catalog.duplicate(true)

## A detached section for pure calculations; keep the public catalog mutable
## only in its returned copy without copying every unrelated definition.
static func catalog_section(category: String) -> Variant:
	_ensure_catalog()
	var section: Variant = _catalog.get(category, [])
	return section.duplicate(true) if section is Dictionary or section is Array else section

static func _state(game) -> Dictionary:
	return game.world.get("dragons", {})

static func get_record(game, uid: String) -> Dictionary:
	return (_state(game).get("records", {}).get(uid, {}) as Dictionary).duplicate(true)

static func records(game, house_uid: String = "") -> Array:
	var out := []
	for row in _state(game).get("records", {}).values():
		if house_uid == "" or str(row.get("owner_house_uid", "")) == house_uid: out.append(row.duplicate(true))
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out

static func age_years(game, row: Dictionary) -> float:
	if str(row.get("stage", "")) == "egg": return 0.0
	return maxf(0.0, (float(game.day) - float(row.get("birth_day", game.day))) / People.year_days())

static func _catalog_row(category: String, uid: String) -> Dictionary:
	_ensure_catalog()
	for row in _catalog.get(category, []):
		if str(row.get("id", "")) == uid: return row.duplicate(true)
	return {}

## Type is authoritative gem identity, never inferred from an individual's name.
static func type_label(row: Dictionary) -> String:
	var gem := _catalog_row("gems", str(row.get("gem_id", "")))
	var suffix := " Egg" if str(row.get("stage", "")) == "egg" else " Dragon"
	return (str(gem["name"]) if not gem.is_empty() else "Unknown") + suffix

static func _variation(row: Dictionary, channel: String) -> float:
	var stored: Variant = row.get("variation", {})
	if stored is Dictionary and (stored as Dictionary).has(channel):
		return float((stored as Dictionary)[channel])
	# Independent stored-seed channels; neither gem/name nor campaign RNG is involved.
	var seed_value := int(hash([int(row.get("appearance_seed", 0)), "physique", channel])) & 0x7fffffff
	return 0.9 + float(seed_value % 201) / 1000.0

static func _attack_profile(verb: String, mass: float, strength: float, base_p: float, velocity: float,
		contact_cm2: float, depth_cm: float, torque_nm: float, contact_factor: float) -> Dictionary:
	# Native natural scaling is applied ONCE. These unscaled attack inputs are for
	# later body binding; feeding the reported scaled p back as base p would double it.
	var swing := Formulas.natural_swing("bite", strength, mass, 0.0, 0.0,
		base_p / float(Formulas.NATURAL["bite"]["p"]), 0.0, 0.0)
	var momentum := float(swing["p"])
	var attack := {"verb": verb, "type": "edge", "contact": contact_cm2 * contact_factor,
		"penetration": depth_cm * 10.0 / Formulas.PENETRATION_MM_PER_UNIT,
		"p": base_p, "v": velocity, "prep": 3, "rec": 3,
		"needs": "head" if verb == "bite" else "foot"}
	return {"attack": attack, "p_kg_m_s": momentum, "v_m_s": velocity,
		"energy_j": 0.5 * momentum * velocity, "torque_nm": torque_nm,
		"native_scale_ratio": float(swing["ratio"])}

## Pure, authored resting profile, not a dragon battle resolver. No wounds,
## armour outcomes, time progression or Unit/material registry mutation occurs.
## Material yields use existing native units, NOT Mohs converted to stress.
static func physical_profile(_game, row: Dictionary) -> Dictionary:
	var gem := _catalog_row("gems", str(row.get("gem_id", "")))
	var morph := _catalog_row("morphs", str(row.get("morph_id", "")))
	var size := _catalog_row("sizes", str(row.get("size_class", "")))
	var stage := str(row.get("stage", ""))
	if gem.is_empty() or morph.is_empty() or size.is_empty() or stage not in ["egg", "juvenile", "adult"]:
		return {"active": false, "valid": false, "type_label": type_label(row), "reason": "Unknown gem, body form, size or stage; no physical strike available."}
	var out := {"active": false, "valid": true, "stage": stage, "type_label": type_label(row),
		"hardness_index": float(gem["hardness_index"]), "battle_bound": false}
	if stage == "egg" or not row.get("alive", false): return out
	var physics: Dictionary = catalog_section("physics")
	var shape: Dictionary = morph["physical"]; var scale: Dictionary = DragonGrowth.metrics(row)
	if not bool(scale.get("valid", false)): return {"active": false, "valid": false, "reason": "Invalid growth profile."}
	var linear := float(scale["linear_scale"])
	var mass := float(scale["body_mass_kg"]) * float(shape["mass"]) * _variation(row, "mass")
	var health := clampf(float(row.get("care", {}).get("health", 1.0)), 0.0, 1.0)
	var strength := float(scale["strength"]) * float(shape["strength"]) * _variation(row, "strength") * (0.4 + 0.6 * health)
	var tooth_relative := float(shape["tooth"]) * _variation(row, "tooth")
	var claw_relative := float(shape["claw"]) * _variation(row, "claw")
	var tooth_length := float(physics["reference_tooth_length_cm"]) * linear * tooth_relative
	var claw_length := float(physics["reference_claw_length_cm"]) * linear * claw_relative
	var tooth_diameter := 1.6 * linear * tooth_relative
	var claw_width := 2.4 * linear * claw_relative
	# Contact is tip footprint, not the whole tooth base. Its independent seed
	# channel and penetration depth remain separate inputs to native layer tests.
	var tooth_contact := 0.08 * pow(linear * tooth_relative, 2.0) * _variation(row, "tooth_contact")
	var claw_contact := 0.12 * pow(linear * claw_relative, 2.0) * _variation(row, "claw_contact")
	var tooth_depth := tooth_length * 0.85; var claw_depth := claw_length * 0.75
	var lever := float(physics["reference_jaw_out_lever_m"]) * linear * float(shape["jaw_lever"]) * _variation(row, "jaw_lever")
	# Linear jaw gain offsets the larger out-lever. Formulas.torque supplies
	# mass^(2/3) cross-section scaling; it is not repeated in this gain.
	var jaw_gain := linear * float(shape["jaw_gain"]) * _variation(row, "jaw_gain")
	var torque := Formulas.torque(strength, mass, 1.0, 0.0, 0.0, 0.0)
	var jaw_torque := torque * jaw_gain
	var bite_force := jaw_torque / lever
	# Force modifies the unscaled momentum only relative to its own native
	# strength/mass baseline, avoiding downstream double-counting of body size.
	var force_gain := bite_force / (torque / float(physics["reference_jaw_out_lever_m"]))
	var bite_base := float(Formulas.NATURAL["bite"]["p"]) * force_gain * sqrt(tooth_relative)
	var claw_base := 5.0 * sqrt(claw_relative)
	var material: Dictionary = physics["tissue_material"].duplicate(true)
	material["shear_yield"] = float(gem["shear_yield"]); material["impact_yield"] = float(gem["impact_yield"])
	material["name"] = str(gem["name"]) + " dragon tooth"; material["kind"] = "tissue"
	var claw_material := material.duplicate(true); claw_material["name"] = str(gem["name"]) + " dragon claw"
	out.merge({"active": true, "body_mass_kg": mass, "strength": strength, "bite_force_n": bite_force,
		"jaw_torque_nm": jaw_torque, "jaw_out_lever_m": lever, "jaw_muscle_gain": jaw_gain,
		"tooth_length_cm": tooth_length, "claw_length_cm": claw_length,
		"tooth_diameter_cm": tooth_diameter, "claw_width_cm": claw_width,
		"tooth_contact_cm2": tooth_contact, "claw_contact_cm2": claw_contact,
		"tooth_penetration_cm": tooth_depth, "claw_penetration_cm": claw_depth,
		"tooth_material": material, "claw_material": claw_material,
		"attacks": {"bite": _attack_profile("bite", mass, strength, bite_base, 6.0, tooth_contact, tooth_depth, jaw_torque, float(physics["native_contact_per_cm2"])),
			"claw": _attack_profile("claw", mass, strength, claw_base, 8.0, claw_contact, claw_depth, torque, float(physics["native_contact_per_cm2"]))}}, true)
	return out

static func _proper_name(game, key: String) -> String:
	var pool: Array = catalogs()["proper_names"]; var used := {}
	for row in _state(game).get("records", {}).values(): used[str(row.get("name", ""))] = true
	var offset := _seed(game, key + ":name") % pool.size()
	for i in pool.size():
		var candidate := str(pool[(offset + i) % pool.size()])
		if not used.has(candidate): return candidate
	# Large worlds still get deterministic unique names after the original pool.
	return str(pool[offset]) + " " + str(int(_state(game)["next_id"]) - 1)

## Only detailed native people/households can hold these references.
static func _person(game, uid: String) -> Dictionary:
	var loc := Dynasty._person(game, uid)
	if loc.is_empty() or loc["family"].get("cohort", false) or loc["family"].get("estate", false): return {}
	var row := Dynasty._row(loc, float(game.day))
	if not row.get("alive", false) or str(row.get("house_uid", "")) == "" or str(row.get("household_uid", "")) == "": return {}
	if not game.world.get("towns", {}).has(str(row.get("town_id", ""))): return {}
	return row.duplicate(true)

static func people(game) -> Array:
	var out := []; var seen := {}
	for town in game.world.get("towns", {}).values():
		var town_id := str(town.get("id", "")); var econ: Dictionary = town.get("econ", {})
		if not game.world.get("towns", {}).has(town_id): continue
		for family in econ.get("fams", []):
			if family.get("cohort", false) or family.get("estate", false): continue
			for person in family.get("pp", []) + family.get("kp", []):
				var uid := str(Persons.g(person, Persons.PERSON_UID, ""))
				if uid == "" or seen.has(uid): continue
				if not Dynasty._living(game, town_id, family, person): continue
				if str(Persons.g(person, Persons.HOUSE_UID, "")) == "" or str(family.get("household_uid", "")) == "": continue
				var row := Dynasty._row({"town": town, "econ": econ, "family": family, "person": person, "alive": true}, float(game.day))
				seen[uid] = true; out.append(row.duplicate(true))
	out.sort_custom(func(a, b): return str(a["person_uid"]) < str(b["person_uid"]))
	return out

static func _seed(game, key: String) -> int:
	return int(hash([int(game.world.get("seed", 0)), "bloodlines-dragons", key])) & 0x7fffffff

static func _history(game, row: Dictionary, kind: String, detail: Dictionary = {}) -> void:
	var entry := {"day": float(game.day), "kind": kind}
	entry.merge(detail.duplicate(true))
	var history: Array = row.get("history", [])
	history.append(entry)
	if history.size() > HISTORY_LIMIT: history = history.slice(history.size() - HISTORY_LIMIT)
	row["history"] = history

static func _set_owner(row: Dictionary, person: Dictionary) -> void:
	row["owner_person_uid"] = str(person["person_uid"])
	row["owner_house_uid"] = str(person["house_uid"])
	row["owner_household_uid"] = str(person["household_uid"])
	row["owner_status"] = "claimed"

static func _present(person: Dictionary, town_id: String) -> bool:
	return str(person.get("town_id", "")) == town_id and str(person.get("state", "")) in ["", "hire", "reserve"]

static func _make(game, stage: String, town_id: String, owner: Dictionary, key: String, palette: int,
		sex: String, mother_uid: String = "", father_uid: String = "", bloodline_uid: String = "") -> Dictionary:
	var state := _state(game); var cat := catalogs()
	var uid := "dragon:%d:%d" % [int(game.world.get("seed", 0)), int(state["next_id"])]
	state["next_id"] = int(state["next_id"]) + 1
	var appearance := _seed(game, key)
	var gem: Dictionary = cat["gems"][palette % cat["gems"].size()]
	var morph: Dictionary = cat["morphs"][_seed(game, key + ":morph") % cat["morphs"].size()]
	var size: Dictionary = cat["sizes"][_seed(game, key + ":size") % cat["sizes"].size()]
	var age := float(18 + _seed(game, key + ":age") % 73)
	var row := {"id": uid, "name": str(gem["name"]) + " Egg" if stage == "egg" else _proper_name(game, key),
		"stage": stage, "gem_id": str(gem["id"]), "morph_id": str(morph["id"]), "size_class": str(size["id"]),
		"appearance_seed": appearance, "sex": sex, "birth_day": float(game.day) - age * People.year_days() if stage != "egg" else 0.0,
		"laid_day": float(game.day) - float(_seed(game, key + ":laid") % 30) if stage == "egg" else 0.0,
		"mother_uid": mother_uid, "father_uid": father_uid, "bloodline_uid": bloodline_uid if bloodline_uid != "" else "dragonline:" + uid,
		"owner_person_uid": "", "owner_house_uid": "", "owner_household_uid": "", "owner_status": "claimed",
		"estate_town_id": town_id, "custodian_person_uid": str(owner["person_uid"]), "location_town_id": town_id,
		"rider_person_uid": "", "alive": true, "history": []}
	_set_owner(row, owner)
	DragonCare.initialize(row, int(floor(game.day)))
	# The owner can live elsewhere; custody requires actual co-location.
	if not _present(owner, town_id): row["custodian_person_uid"] = ""
	_history(game, row, "registered", {"stage": stage, "owner_person_uid": row["owner_person_uid"]})
	state["records"][uid] = row
	return row

## Called after native dynasty/feudal history preparation, before player selection.
## Any existing registry is retained, even an empty one: no saved identity regeneration.
static func init_world(game) -> void:
	if game.world.has("dragons"): return
	game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var valid := {}; var towns: Dictionary = game.world.get("towns", {})
	var town_ids: Array = towns.keys(); town_ids.sort()
	for tid in town_ids:
		var office := Dynasty.town_office(game, str(tid))
		var owner := _person(game, str(office.get("person_uid", "")))
		if not owner.is_empty() and office.get("alive", false): valid[str(tid)] = owner
	var parents := {}; var fids: Array = game.world.get("factions", {}).keys(); fids.sort()
	var palette_offset: int = _seed(game, "palettes") % catalogs()["gems"].size()
	for fid in fids:
		var seats := []
		for tid in town_ids:
			if valid.has(str(tid)) and str(towns[tid].get("faction", "")) == str(fid): seats.append(str(tid))
		if seats.is_empty(): continue
		var cap := str(game.world["factions"][fid].get("capital", ""))
		var seat := cap if seats.has(cap) else str(seats[0])
		var lineage := "dragonline:%d:%s" % [int(game.world.get("seed", 0)), seat]
		var mother := _make(game, "adult", seat, valid[seat], str(fid) + ":founder:mother", palette_offset + parents.size() * 2,
			"female", "", "", lineage)
		var father := _make(game, "adult", seat, valid[seat], str(fid) + ":founder:father", palette_offset + parents.size() * 2 + 1,
			"male", "", "", lineage)
		parents[str(fid)] = [str(mother["id"]), str(father["id"]), lineage]
	var index := 0
	for tid in town_ids:
		var fid := str(towns[tid].get("faction", ""))
		if not valid.has(str(tid)) or not parents.has(fid): continue
		var pair: Array = parents[fid]
		_make(game, "egg", str(tid), valid[str(tid)], str(tid) + ":egg", palette_offset + index,
			"unknown", pair[0], pair[1], pair[2])
		index += 1

## Current JSON normalization only. Absence does not trigger init or migration.
static func after_load(game) -> void:
	if not game.world.has("dragons"): return
	var state := _state(game)
	for field in ["schema", "next_id", "life_day"]:
		if state.has(field): state[field] = int(state[field])
	for row in state.get("records", {}).values():
		if row.has("appearance_seed"): row["appearance_seed"] = int(row["appearance_seed"])
		if row.has("last_clutch_day"): row["last_clutch_day"] = int(row["last_clutch_day"])
		if row.has("variation") and row["variation"] is Dictionary:
			var vmap: Dictionary = row["variation"]
			for ch in vmap.keys():
				vmap[ch] = float(vmap[ch])
		for entry in row.get("history", []):
			if entry.has("appearance_seed"): entry["appearance_seed"] = int(entry["appearance_seed"])
	reconcile(game)
	DragonCare.after_load(game)
	DragonBreeding.after_load(game)

## Explicit post-succession/death boundary. Legal kin inherit assets independently
## of location/custody/current title; missing lawful heirs leave prior refs unclaimed.
static func reconcile(game) -> void:
	for row in _state(game).get("records", {}).values():
		var uid := str(row.get("owner_person_uid", ""))
		if uid != "":
			var owner := _person(game, uid)
			if not owner.is_empty():
				if str(row.get("owner_house_uid", "")) != str(owner["house_uid"]) or str(row.get("owner_household_uid", "")) != str(owner["household_uid"]):
					_history(game, row, "owner_refs", {"owner_person_uid": uid, "prior_household_uid": str(row.get("owner_household_uid", ""))})
					_set_owner(row, owner)
			else:
				var heirs := Dynasty.asset_heirs(game, uid, str(row.get("owner_house_uid", "")))
				var next := {}
				for heir in heirs:
					next = _person(game, str(heir.get("person_uid", "")))
					if not next.is_empty(): break
				if not next.is_empty():
					_history(game, row, "inherited", {"prior_owner_person_uid": uid, "owner_person_uid": next["person_uid"],
						"prior_house_uid": str(row.get("owner_house_uid", "")), "prior_household_uid": str(row.get("owner_household_uid", ""))})
					_set_owner(row, next)
				elif str(row.get("owner_status", "claimed")) != "unclaimed":
					row["owner_status"] = "unclaimed"
					_history(game, row, "unclaimed", {"prior_owner_person_uid": uid, "prior_house_uid": str(row.get("owner_house_uid", "")),
						"prior_household_uid": str(row.get("owner_household_uid", ""))})
		var custodian := str(row.get("custodian_person_uid", ""))
		if custodian != "":
			var keeper := _person(game, custodian)
			if keeper.is_empty() or not _present(keeper, str(row.get("location_town_id", ""))):
				row["custodian_person_uid"] = ""
				_history(game, row, "custodian_died" if keeper.is_empty() else "custodian_unavailable", {"prior_custodian_person_uid": custodian})
	DragonBond.reconcile(game)

## Native ownership and the selected economic household must agree. Shared
## ancestry or a settlement title alone never grants authority over this asset.
static func authority(game, row: Dictionary) -> Dictionary:
	var leader: Dictionary = Dynasty.ruler(game)
	var owner: Dictionary = _person(game, str(row.get("owner_person_uid", "")))
	var household: String = str(game.world.get("player_house", {}).get("household_uid", ""))
	if str(row.get("owner_status", "claimed")) != "claimed" or owner.is_empty() or DragonBond._physical_dead(game, owner) or not bool(leader.get("alive", false)):
		return _failure("A living owner and current selected household leader are required for this order.")
	var current: Dictionary = _person(game, str(leader.get("person_uid", "")))
	if current.is_empty(): return _failure("Your current household leader is unavailable.")
	if household == "" or household != str(leader.get("household_uid", "")) or household != str(owner["household_uid"]) or household != str(row.get("owner_household_uid", "")):
		return _failure("The dragon belongs to another actual household, or its ownership needs reconciliation.")
	if str(current["household_uid"]) != household: return _failure("Your selected household leadership needs reconciliation.")
	if str(row.get("owner_house_uid", "")) != str(owner["house_uid"]):
		return _failure("Its ownership references need reconciliation.")
	return {"ok": true, "reason": "", "authority_person_uid": str(current["person_uid"]), "authority_household_uid": household,
		"owner_person_uid": str(owner["person_uid"])}

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message, "reason": message}

static func _preview(game, uid: String, recipient_uid: String, action: String) -> Dictionary:
	var row := get_record(game, uid)
	if row.is_empty() or not row.get("alive", false): return _failure("This living dragon or egg is unavailable.")
	var rights: Dictionary = authority(game, row)
	if not bool(rights["ok"]): return rights
	if not game.world.get("towns", {}).has(str(row.get("estate_town_id", ""))) or not game.world.get("towns", {}).has(str(row.get("location_town_id", ""))):
		return _failure("Its estate and location must be existing towns.")
	var recipient := _person(game, recipient_uid)
	if recipient.is_empty(): return _failure("Choose a living registered person with a real house and home town.")
	if action == "transfer" and recipient_uid == str(row["owner_person_uid"]): return _failure("This person already owns it.")
	if action == "set_custodian":
		if recipient_uid == str(row.get("custodian_person_uid", "")): return _failure("This person is already its custodian.")
		if not _present(recipient, str(row["location_town_id"])): return _failure("A custodian must be present at its current location, outside military or travelling service.")
	var message := "Give ownership to %s. Custody, location and rider stay as recorded." % recipient["name"] if action == "transfer" else "Place custody with %s at its current location. Ownership and rider stay as recorded." % recipient["name"]
	return {"ok": true, "message": message, "reason": message, "action": action, "dragon_uid": uid,
		"recipient_person_uid": recipient_uid, "authority_person_uid": rights["authority_person_uid"],
		"authority_household_uid": rights["authority_household_uid"], "source": row,
		"recipient": recipient}

static func transfer_preview(game, uid: String, recipient_person_uid: String) -> Dictionary:
	return _preview(game, uid, recipient_person_uid, "transfer")

static func set_custodian_preview(game, uid: String, recipient_person_uid: String) -> Dictionary:
	return _preview(game, uid, recipient_person_uid, "set_custodian")

static func _apply(game, uid: String, recipient_uid: String, action: String, review: Dictionary) -> Dictionary:
	var fresh := _preview(game, uid, recipient_uid, action)
	if not fresh["ok"]: return fresh
	if not review.is_empty() and review != fresh: return _failure("The ruler, recipient or dragon record changed. Review this order again.")
	var row: Dictionary = _state(game)["records"][uid]
	if action == "transfer":
		var previous := str(row["owner_person_uid"])
		_set_owner(row, fresh["recipient"])
		_history(game, row, "gifted", {"prior_owner_person_uid": previous, "owner_person_uid": recipient_uid,
			"authorized_by_person_uid": fresh["authority_person_uid"]})
	else:
		var previous := str(row.get("custodian_person_uid", ""))
		row["custodian_person_uid"] = recipient_uid
		_history(game, row, "custodian_assigned", {"prior_custodian_person_uid": previous, "custodian_person_uid": recipient_uid,
			"authorized_by_person_uid": fresh["authority_person_uid"]})
	return {"ok": true, "message": "Ownership given." if action == "transfer" else "Custodian appointed.", "record": row.duplicate(true)}

static func transfer(game, uid: String, recipient_person_uid: String, review: Dictionary = {}) -> Dictionary:
	return _apply(game, uid, recipient_person_uid, "transfer", review)

static func set_custodian(game, uid: String, recipient_person_uid: String, review: Dictionary = {}) -> Dictionary:
	return _apply(game, uid, recipient_person_uid, "set_custodian", review)
