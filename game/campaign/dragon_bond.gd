class_name DragonBond
extends RefCounted
## Reviewed relationships between existing individual dragons and tracked people.
## No combat bodies, service allocation, travel, items, accounts or random rolls.

static func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": reason}

static func _person(game, uid: String) -> Dictionary:
	var person: Dictionary = Dragons._person(game, uid)
	if person.is_empty(): return {}
	if _physical_dead(game, person): return {}
	return person

static func _physical_dead(game, person: Dictionary) -> bool:
	var unit: Unit = Dynasty.bound_unit(game, person)
	if unit == null or not unit.dead: return false
	var address: Dictionary = Mobilization._address(game, unit)
	return not address.is_empty() and str(Persons.g(address["person"], Persons.PERSON_UID, "")) == str(person.get("person_uid", ""))

static func _adult(person: Dictionary) -> bool:
	return int(person.get("age", -1)) >= int(People.ages(str(person.get("race", "human")))["adult"])

static func _present(game, person: Dictionary, town_id: String) -> bool:
	if Dragons._present(person, town_id): return true
	# A company's registered home is not its physical location. Prove the exact
	# existing service holder and the native town visit instead of summoning it.
	if str(person.get("state", "")) != "company" or not Mobilization._here(game, town_id): return false
	var unit: Unit = Dynasty.bound_unit(game, person)
	if unit == null or unit.dead or not game.company.has(unit): return false
	var address: Dictionary = Mobilization._address(game, unit)
	return not address.is_empty() and str(Persons.g(address["person"], Persons.PERSON_UID, "")) == str(person["person_uid"])

static func _links(game, person_uid: String) -> Array:
	var ids: Array = []
	if person_uid == "": return ids
	for row: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		if str(row.get("rider_person_uid", "")) == person_uid: ids.append(str(row.get("id", "")))
	ids.sort()
	return ids

static func _bind_gate(game, row: Dictionary) -> String:
	if game.get("_save_capture") != null: return "Wait for the consistent save snapshot to finish."
	if row.is_empty(): return "This dragon is unavailable."
	if not bool(row.get("alive", false)): return "A deceased dragon cannot form a bond."
	if str(row.get("stage", "")) not in ["juvenile", "adult"]: return "An egg cannot form a rider bond."
	if str(row.get("rider_person_uid", "")) != "": return "This dragon already has a rider bond. Release it before choosing another person."
	var rights: Dictionary = Dragons.authority(game, row)
	if not bool(rights["ok"]): return str(rights["reason"])
	var town_id: String = str(row.get("location_town_id", ""))
	if not game.world.get("towns", {}).has(town_id) or not game.world.get("towns", {}).has(str(row.get("estate_town_id", ""))):
		return "Its estate and current location must be existing settlements."
	if not Mobilization._here(game, town_id): return "Visit the dragon's recorded settlement before forming a bond."
	return ""

static func _eligibility(game, row: Dictionary, person: Dictionary) -> String:
	if person.is_empty(): return "Choose a living tracked person with a real household."
	if not _adult(person): return "This person has not reached their native race's adult age."
	if not _present(game, person, str(row.get("location_town_id", ""))): return "This person is not actually present at the dragon's settlement."
	if not _links(game, str(person["person_uid"])).is_empty(): return "This person already has a rider bond with another dragon."
	return ""

static func status(game, dragon_uid: String) -> Dictionary:
	var row: Dictionary = Dragons.get_record(game, dragon_uid)
	var rider_uid: String = str(row.get("rider_person_uid", ""))
	var rider: Dictionary = _person(game, rider_uid)
	var rights: Dictionary = Dragons.authority(game, row)
	var reason: String = _bind_gate(game, row)
	var release_reason: String = "No rider bond is recorded." if rider_uid == "" else ("" if bool(rights["ok"]) else str(rights["reason"]))
	if game.get("_save_capture") != null: release_reason = "Wait for the consistent save snapshot to finish."
	var active: bool = rider_uid != "" and bool(row.get("alive", false)) and not rider.is_empty() and _links(game, rider_uid).size() == 1
	return {"ok": not row.is_empty(), "dragon_uid": dragon_uid, "bonded": rider_uid != "", "active": active,
		"rider_person_uid": rider_uid, "rider": rider, "can_bind": reason == "", "can_release": release_reason == "",
		"reason": reason, "release_reason": release_reason, "location_town_id": str(row.get("location_town_id", "")),
		"at_location": not row.is_empty() and Mobilization._here(game, str(row.get("location_town_id", ""))),
		"last_rider_person_uid": str(row.get("last_rider_person_uid", "")), "last_separation_reason": str(row.get("last_separation_reason", ""))}

## Eligible-only native candidates; the command rechecks the chosen person.
static func candidates(game, dragon_uid: String) -> Array:
	var row: Dictionary = Dragons.get_record(game, dragon_uid)
	var out: Array = []
	if _bind_gate(game, row) != "": return out
	var linked: Dictionary = {}
	for other: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		var rider_uid: String = str(other.get("rider_person_uid", ""))
		if rider_uid != "": linked[rider_uid] = true
	for person: Dictionary in Dragons.people(game):
		if linked.has(str(person["person_uid"])) or not _adult(person): continue
		if _physical_dead(game, person): continue
		if _present(game, person, str(row["location_town_id"])): out.append(person.duplicate(true))
	return out

static func bind_preview(game, dragon_uid: String, person_uid: String) -> Dictionary:
	var row: Dictionary = Dragons.get_record(game, dragon_uid)
	var reason: String = _bind_gate(game, row)
	if reason != "": return _failure(reason)
	var person: Dictionary = _person(game, person_uid)
	reason = _eligibility(game, row, person)
	if reason != "": return _failure(reason)
	var rights: Dictionary = Dragons.authority(game, row)
	var message: String = "Bond %s with %s. Ownership, custody and location stay as recorded." % [row.get("name", "this dragon"), person["name"]]
	return {"ok": true, "reason": message, "message": message, "action": "bind", "dragon_uid": dragon_uid,
		"recipient_person_uid": person_uid, "authority_person_uid": rights["authority_person_uid"],
		"authority_household_uid": rights["authority_household_uid"], "source": row, "recipient": person,
		"contact": {"location": str(game.location), "town_id": str(row["location_town_id"]), "day": float(game.day), "present": true}}

static func release_preview(game, dragon_uid: String) -> Dictionary:
	if game.get("_save_capture") != null: return _failure("Wait for the consistent save snapshot to finish.")
	var row: Dictionary = Dragons.get_record(game, dragon_uid)
	if row.is_empty() or str(row.get("rider_person_uid", "")) == "": return _failure("No rider bond is recorded.")
	var rights: Dictionary = Dragons.authority(game, row)
	if not bool(rights["ok"]): return rights
	var rider_uid: String = str(row["rider_person_uid"])
	var message: String = "Release this rider bond. Ownership, custody and location stay as recorded."
	return {"ok": true, "reason": message, "message": message, "action": "release", "dragon_uid": dragon_uid,
		"recipient_person_uid": rider_uid, "authority_person_uid": rights["authority_person_uid"],
		"authority_household_uid": rights["authority_household_uid"], "source": row, "recipient": Dynasty.person(game, rider_uid),
		"day": float(game.day)}

static func _separate(game, row: Dictionary, reason: String, authority_uid: String = "") -> void:
	var rider_uid: String = str(row.get("rider_person_uid", ""))
	if rider_uid == "": return
	row["rider_person_uid"] = ""
	row["last_rider_person_uid"] = rider_uid
	row["last_separation_day"] = float(game.day)
	row["last_separation_reason"] = reason
	Dragons._history(game, row, "bond_released" if reason == "released" else "bond_ended",
		{"prior_rider_person_uid": rider_uid, "reason": reason, "authorized_by_person_uid": authority_uid})

static func bind(game, dragon_uid: String, person_uid: String, review: Dictionary = {}) -> Dictionary:
	if review.is_empty(): return _failure("Review the proposed rider bond before confirming it.")
	var fresh: Dictionary = bind_preview(game, dragon_uid, person_uid)
	if not bool(fresh["ok"]): return fresh
	if review != fresh: return _failure("The person, ownership, location or dragon changed. Review the bond again.")
	var row: Dictionary = game.world["dragons"]["records"][dragon_uid]
	row["rider_person_uid"] = person_uid
	row["bond_day"] = float(game.day)
	Dragons._history(game, row, "bonded", {"rider_person_uid": person_uid, "authorized_by_person_uid": fresh["authority_person_uid"]})
	return {"ok": true, "reason": "Rider bond recorded.", "message": "Rider bond recorded.", "record": row.duplicate(true)}

static func release(game, dragon_uid: String, review: Dictionary = {}) -> Dictionary:
	if review.is_empty(): return _failure("Review the recorded rider bond before releasing it.")
	var fresh: Dictionary = release_preview(game, dragon_uid)
	if not bool(fresh["ok"]): return fresh
	if review != fresh: return _failure("The owner, rider or dragon changed. Review the release again.")
	var row: Dictionary = game.world["dragons"]["records"][dragon_uid]
	_separate(game, row, "released", str(fresh["authority_person_uid"]))
	return {"ok": true, "reason": "Rider bond released.", "message": "Rider bond released.", "record": row.duplicate(true)}

## Native death/succession/care boundaries only. Absence, travel, ownership and
## custody changes do not erase a surviving relationship or assign a successor.
static func reconcile(game) -> void:
	var registry: Dictionary = game.world.get("dragons", {}).get("records", {})
	var counts: Dictionary = {}
	for row: Dictionary in registry.values():
		var rider_uid: String = str(row.get("rider_person_uid", ""))
		if rider_uid != "": counts[rider_uid] = int(counts.get(rider_uid, 0)) + 1
	var ids: Array = registry.keys(); ids.sort()
	for uid: Variant in ids:
		var row: Dictionary = registry[uid]
		var rider_uid: String = str(row.get("rider_person_uid", ""))
		if rider_uid == "": continue
		if not bool(row.get("alive", false)): _separate(game, row, "dragon_died")
		elif _person(game, rider_uid).is_empty(): _separate(game, row, "rider_died_or_unavailable")
		elif int(counts[rider_uid]) > 1: _separate(game, row, "conflicting_bonds")
