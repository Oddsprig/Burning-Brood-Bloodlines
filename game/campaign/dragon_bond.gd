class_name DragonBond
extends RefCounted
## Reviewed relationships between existing individual dragons and tracked people.
## A direct bond does not roll. An earned approach (v0.051) uses a deterministic
## hash of the dragon and the person, never Game.rng.
## No combat bodies, service allocation, travel, items or accounts.

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

static func _bind_gate(game, row: Dictionary, skip_player_visit: bool = false) -> String:
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
	# Earned acceptance already proved the pair is together. Only a direct order waits for the player.
	if not skip_player_visit and not Mobilization._here(game, town_id): return "Visit the dragon's recorded settlement before forming a bond."
	return ""

static func _eligibility(game, row: Dictionary, person: Dictionary, skip_player_visit: bool = false) -> String:
	if person.is_empty(): return "Choose a living tracked person with a real household."
	if not _adult(person): return "This person has not reached their native race's adult age."
	if skip_player_visit:
		if not _with_dragon(game, person, row): return "This person is not actually with the dragon."
	elif not _present(game, person, str(row.get("location_town_id", ""))):
		return "This person is not actually present at the dragon's settlement."
	if not _links(game, str(person["person_uid"])).is_empty(): return "This person already has a rider bond with another dragon."
	return ""

## Approach bond rules, apart from co-location. Empty when this person may approach.
## A gift to another person of the same household keeps them eligible. It fails only
## when they leave the owning household, the holding is unclaimed, or a bond rule excludes them.
static func _approach_eligibility(game, row: Dictionary, person: Dictionary) -> String:
	if person.is_empty(): return "Choose a living tracked person with a real household."
	if not _adult(person): return "This person has not reached their native race's adult age."
	if str(row.get("owner_status", "claimed")) != "claimed" or str(person.get("household_uid", "")) == "" or str(person.get("household_uid", "")) != str(row.get("owner_household_uid", "")):
		return "Only an adult of the owning household may approach this dragon."
	if not _links(game, str(person.get("person_uid", ""))).is_empty():
		return "This person already has a rider bond with another dragon."
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

static func bind_preview(game, dragon_uid: String, person_uid: String, skip_player_visit: bool = false) -> Dictionary:
	var row: Dictionary = Dragons.get_record(game, dragon_uid)
	var reason: String = _bind_gate(game, row, skip_player_visit)
	if reason != "": return _failure(reason)
	var person: Dictionary = _person(game, person_uid)
	reason = _eligibility(game, row, person, skip_player_visit)
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

static func _cancel_bonded_approaches(game, dragon_uid: String, person_uid: String, include_pair: bool) -> void:
	var registry: Dictionary = game.world.get("dragons", {}).get("records", {})
	var ids: Array = registry.keys()
	ids.sort()
	for uid in ids:
		var pending: Dictionary = registry[uid]
		var who := str(_approach(pending).get("person_uid", ""))
		if who == "": continue
		var same_pair := str(uid) == dragon_uid and who == person_uid
		if same_pair and not include_pair: continue
		if str(uid) == dragon_uid or who == person_uid:
			_end_approach(game, pending, "already_bonded")

static func _commit_bond(game, dragon_uid: String, person_uid: String, authority_uid: String) -> void:
	var row: Dictionary = game.world["dragons"]["records"][dragon_uid]
	row["rider_person_uid"] = person_uid
	row["bond_day"] = float(game.day)
	Dragons._history(game, row, "bonded", {"rider_person_uid": person_uid, "authorized_by_person_uid": authority_uid})
	# The completing pair keeps its own closing line. Every other approach on this person or dragon ends now.
	_cancel_bonded_approaches(game, dragon_uid, person_uid, false)

static func bind(game, dragon_uid: String, person_uid: String, review: Dictionary = {}, skip_player_visit: bool = false) -> Dictionary:
	if review.is_empty(): return _failure("Review the proposed rider bond before confirming it.")
	var fresh: Dictionary = bind_preview(game, dragon_uid, person_uid, skip_player_visit)
	if not bool(fresh["ok"]): return fresh
	if review != fresh: return _failure("The person, ownership, location or dragon changed. Review the bond again.")
	_commit_bond(game, dragon_uid, person_uid, str(fresh["authority_person_uid"]))
	# A direct bond has no acceptance line. End the approach on this pair as well.
	if not skip_player_visit:
		_cancel_bonded_approaches(game, dragon_uid, person_uid, true)
	var row: Dictionary = game.world["dragons"]["records"][dragon_uid]
	return {"ok": true, "reason": "Rider bond recorded.", "message": "Rider bond recorded.", "record": row.duplicate(true)}

static func release(game, dragon_uid: String, review: Dictionary = {}) -> Dictionary:
	if review.is_empty(): return _failure("Review the recorded rider bond before releasing it.")
	var fresh: Dictionary = release_preview(game, dragon_uid)
	if not bool(fresh["ok"]): return fresh
	if review != fresh: return _failure("The owner, rider or dragon changed. Review the release again.")
	var row: Dictionary = game.world["dragons"]["records"][dragon_uid]
	_separate(game, row, "released", str(fresh["authority_person_uid"]))
	return {"ok": true, "reason": "Rider bond released.", "message": "Rider bond released.", "record": row.duplicate(true)}

## Days of steady presence for an average dragon (fed, unhurt, not the keeper)
## before it decides. A season is 30 days, so this is three months. Temperament
## spreads the decision from two to four months (60–120 days).
const APPROACH_PACE_DAYS := 90
const FAMILIARITY_CAP := 100.0
const KEEPER_MULT := 1.5
const HUNGRY_MULT := 0.5
const HURT_MULT := 0.5
const HUNGRY_FOOD := 0.8
const HURT_HEALTH := 0.8
const REFUSAL_COOLDOWN_DAYS := 30
## Share of familiarity kept when the dragon refuses. The rest is lost.
const REFUSAL_KEEP := 0.6
const ACCEPT_CHANCE := 55
const _CANCEL_TEXT := {
	"dragon_died": "The dragon died, so the approach ended.",
	"approacher_died": "They died, so the approach ended.",
	"already_bonded": "A rider bond now exists, so the approach ended.",
	"ownership": "Ownership changed, so the approach ended.",
	"left": "They left the dragon, so the approach ended.",
	"not_grown": "This dragon can no longer take a rider, so the approach ended.",
	"stopped": "The approach stopped. Familiarity stays.",
	"duplicate": "This person is approaching another dragon, so this approach ended.",
}

static func pace_days(row: Dictionary) -> int:
	var n := int(hash([int(row.get("appearance_seed", 0)), str(row.get("id", "")), "approach-pace"])) & 0x7fffffff
	return APPROACH_PACE_DAYS - 30 + (n % 61)

## True when this dragon would accept this person at the familiarity cap.
## The same pair always gives the same answer.
static func will_accept(row: Dictionary, person_uid: String) -> bool:
	var n := int(hash([int(row.get("appearance_seed", 0)), str(row.get("id", "")), person_uid, "approach-verdict"])) & 0x7fffffff
	return (n % 100) < ACCEPT_CHANCE

static func _approach(row: Dictionary) -> Dictionary:
	var stored: Variant = row.get("approach", {})
	if stored is Dictionary:
		return stored
	return {}

## One day's familiarity, before the cap. Keeper care quickens it. Hunger and injury slow it.
static func day_gain(_game, row: Dictionary, person_uid: String) -> Dictionary:
	var pace := pace_days(row)
	var gain := FAMILIARITY_CAP / float(pace)
	var keeper := person_uid != "" and str(row.get("custodian_person_uid", "")) == person_uid
	var care: Dictionary = row.get("care", {})
	var last: Dictionary = care.get("last", {})
	var hungry := float(last.get("food_ratio", 1.0)) < HUNGRY_FOOD
	var hurt := float(care.get("health", 1.0)) < HURT_HEALTH
	if keeper: gain *= KEEPER_MULT
	if hungry: gain *= HUNGRY_MULT
	if hurt: gain *= HURT_MULT
	return {"gain": gain, "pace_days": pace, "keeper": keeper, "hungry": hungry, "hurt": hurt}

static func _marching(game, row: Dictionary) -> bool:
	return bool(row.get("campaign_march", {}).get("enabled", false)) and not game.company.is_empty()

static func _in_company(game, person: Dictionary) -> bool:
	if person.is_empty() or str(person.get("state", "")) != "company": return false
	var unit: Unit = Dynasty.bound_unit(game, person)
	if unit == null or unit.dead or not game.company.has(unit): return false
	var address: Dictionary = Mobilization._address(game, unit)
	return not address.is_empty() and str(Persons.g(address["person"], Persons.PERSON_UID, "")) == str(person.get("person_uid", ""))

## Real co-location. At the roost, the bond presence rule. On the march, the same army.
static func _with_dragon(game, person: Dictionary, row: Dictionary) -> bool:
	if person.is_empty(): return false
	if _marching(game, row): return _in_company(game, person)
	return _present(game, person, str(row.get("location_town_id", "")))

static func _approaching_dragon(game, person_uid: String, except_uid: String = "") -> String:
	if person_uid == "": return ""
	var registry: Dictionary = game.world.get("dragons", {}).get("records", {})
	var ids: Array = registry.keys()
	ids.sort()
	for uid in ids:
		if str(uid) == except_uid: continue
		if str(_approach(registry[uid]).get("person_uid", "")) == person_uid: return str(uid)
	return ""

static func _order_gate(game, row: Dictionary) -> String:
	if game.get("_save_capture") != null: return "Wait for the consistent save snapshot to finish."
	if row.is_empty(): return "This dragon is unavailable."
	if not bool(row.get("alive", false)): return "A deceased dragon cannot be approached."
	if str(row.get("stage", "")) not in ["juvenile", "adult"]: return "An egg cannot form a rider bond."
	if str(row.get("rider_person_uid", "")) != "": return "This dragon already has a rider bond."
	var rights: Dictionary = Dragons.authority(game, row)
	if not bool(rights.get("ok", false)): return str(rights.get("reason", ""))
	if not game.world.get("towns", {}).has(str(row.get("location_town_id", ""))):
		return "Its current location must be an existing settlement."
	var approach := _approach(row)
	if str(approach.get("person_uid", "")) != "": return "Someone is already approaching this dragon."
	var today := int(floor(float(game.day)))
	var until := int(approach.get("cooldown_until", 0))
	if until > today: return "This dragon refused an approach. It may be approached again on day %d." % until
	return ""

static func _approach_cancel_reason(game, row: Dictionary, person_uid: String) -> String:
	if not bool(row.get("alive", false)): return "dragon_died"
	if str(row.get("stage", "")) not in ["juvenile", "adult"]: return "not_grown"
	if str(row.get("rider_person_uid", "")) != "": return "already_bonded"
	if not _links(game, person_uid).is_empty(): return "already_bonded"
	var person := _person(game, person_uid)
	if person.is_empty() or _physical_dead(game, person): return "approacher_died"
	if not _with_dragon(game, person, row): return "left"
	# Same-household gifts stay. Lost eligibility under the approach rules cancels.
	var eligibility := _approach_eligibility(game, row, person)
	if eligibility == "This person already has a rider bond with another dragon.": return "already_bonded"
	if eligibility != "": return "ownership"
	return ""

static func _end_approach(game, row: Dictionary, code: String) -> void:
	var approach := _approach(row)
	var person_uid := str(approach.get("person_uid", ""))
	if person_uid == "" or approach.is_empty(): return
	approach["person_uid"] = ""
	approach["present"] = false
	approach["last_gain"] = 0.0
	approach["last_reason"] = str(_CANCEL_TEXT.get(code, "The approach ended."))
	row["approach"] = approach
	Dragons._history(game, row, "approach_stopped" if code == "stopped" else "approach_cancelled",
		{"person_uid": person_uid, "reason": code})

static func _live(game, dragon_uid: String) -> Dictionary:
	var records: Dictionary = game.world.get("dragons", {}).get("records", {})
	var row: Variant = records.get(dragon_uid, {})
	if row is Dictionary:
		return row
	return {}

static func approach_candidates(game, dragon_uid: String) -> Array:
	var row := Dragons.get_record(game, dragon_uid)
	if _order_gate(game, row) != "": return []
	var blocked := {}
	for other in game.world.get("dragons", {}).get("records", {}).values():
		var rider := str(other.get("rider_person_uid", ""))
		if rider != "": blocked[rider] = true
		var who := str(_approach(other).get("person_uid", ""))
		if who != "": blocked[who] = true
	var out: Array = []
	for person in Dragons.people(game):
		var person_uid := str(person.get("person_uid", ""))
		if blocked.has(person_uid) or _physical_dead(game, person): continue
		if _approach_eligibility(game, row, person) != "": continue
		if not _with_dragon(game, person, row): continue
		out.append(person.duplicate(true))
	return out

static func approach(game, dragon_uid: String, person_uid: String) -> Dictionary:
	var row := _live(game, dragon_uid)
	var gate := _order_gate(game, row)
	if gate != "": return _failure(gate)
	var person := _person(game, person_uid)
	var eligibility := _approach_eligibility(game, row, person)
	if eligibility != "": return _failure(eligibility)
	if _approaching_dragon(game, person_uid, dragon_uid) != "": return _failure("This person is already approaching another dragon.")
	if not _with_dragon(game, person, row): return _failure("This person is not actually with the dragon.")
	var prior := _approach(row)
	var same := str(prior.get("familiar_person_uid", "")) == person_uid
	var care: Dictionary = row.get("care", {})
	var approach := {
		"person_uid": person_uid,
		"familiar_person_uid": person_uid,
		"familiarity": 0.0,
		"cooldown_until": 0,
		"last_day": int(care.get("last_day", int(floor(float(game.day))))),
		"last_gain": 0.0,
		"last_reason": "Approach begun. Familiarity rises once each day they stay with the dragon.",
		"keeper": false, "hungry": false, "hurt": false, "present": true,
	}
	if same:
		approach["familiarity"] = float(prior.get("familiarity", 0.0))
		approach["cooldown_until"] = int(prior.get("cooldown_until", 0))
	row["approach"] = approach
	Dragons._history(game, row, "approach_started", {"person_uid": person_uid})
	return {"ok": true, "reason": str(approach["last_reason"]), "message": str(approach["last_reason"]), "record": row.duplicate(true)}

static func stop_approach(game, dragon_uid: String) -> Dictionary:
	if game.get("_save_capture") != null: return _failure("Wait for the consistent save snapshot to finish.")
	var row := _live(game, dragon_uid)
	if row.is_empty(): return _failure("This dragon is unavailable.")
	var rights: Dictionary = Dragons.authority(game, row)
	if not bool(rights.get("ok", false)): return rights
	if str(_approach(row).get("person_uid", "")) == "": return _failure("No one is approaching this dragon.")
	_end_approach(game, row, "stopped")
	var reason := str(_CANCEL_TEXT["stopped"])
	return {"ok": true, "reason": reason, "message": reason, "record": row.duplicate(true)}

## Called from the daily care close, after that day's feed and health are known.
## A second call the same day does nothing. Starting or stopping an approach adds no familiarity.
static func approach_day(game, row: Dictionary, day: int) -> void:
	if not row.has("approach"): return
	var approach := _approach(row)
	var person_uid := str(approach.get("person_uid", ""))
	if person_uid == "": return
	if int(approach.get("last_day", -1)) >= day: return
	var why := _approach_cancel_reason(game, row, person_uid)
	if why != "":
		_end_approach(game, row, why)
		return
	approach["last_day"] = day
	var parts := day_gain(game, row, person_uid)
	var gain := float(parts["gain"])
	var familiarity := clampf(float(approach.get("familiarity", 0.0)) + gain, 0.0, FAMILIARITY_CAP)
	approach["last_gain"] = gain
	approach["keeper"] = bool(parts["keeper"])
	approach["hungry"] = bool(parts["hungry"])
	approach["hurt"] = bool(parts["hurt"])
	approach["present"] = true
	approach["familiar_person_uid"] = person_uid
	row["approach"] = approach
	if familiarity >= FAMILIARITY_CAP:
		if will_accept(row, person_uid):
			var dragon_id := str(row.get("id", ""))
			var preview := bind_preview(game, dragon_id, person_uid, true)
			if bool(preview.get("ok", false)):
				var bound := bind(game, dragon_id, person_uid, preview, true)
				if bool(bound.get("ok", false)):
					approach["familiarity"] = FAMILIARITY_CAP
					approach["person_uid"] = ""
					approach["last_reason"] = "The dragon accepted the bond."
					row["approach"] = approach
					return
			approach["familiarity"] = familiarity
			approach["last_reason"] = "Ready to bond, but the bond could not be recorded yet."
			row["approach"] = approach
			return
		var until := day + REFUSAL_COOLDOWN_DAYS
		approach["familiarity"] = familiarity * REFUSAL_KEEP
		approach["cooldown_until"] = until
		approach["person_uid"] = ""
		approach["last_gain"] = 0.0
		approach["last_reason"] = "The dragon refused. It may be approached again on day %d." % until
		row["approach"] = approach
		Dragons._history(game, row, "approach_refused", {"person_uid": person_uid, "cooldown_until": until})
		return
	var reason := "Familiarity rose"
	if bool(parts["keeper"]): reason += " faster with the keeper"
	if bool(parts["hungry"]): reason += ", slowed by hunger"
	if bool(parts["hurt"]): reason += ", slowed by injury"
	approach["familiarity"] = familiarity
	approach["last_reason"] = reason + "."
	row["approach"] = approach

static func approach_status(game, dragon_uid: String) -> Dictionary:
	var row := Dragons.get_record(game, dragon_uid)
	var approach := _approach(row)
	var person_uid := str(approach.get("person_uid", ""))
	var familiarity := float(approach.get("familiarity", 0.0))
	var until := int(approach.get("cooldown_until", 0))
	var today := int(floor(float(game.day)))
	var left := maxi(0, until - today)
	var person := _person(game, person_uid) if person_uid != "" else {}
	var present := person_uid != "" and _with_dragon(game, person, row)
	var parts := day_gain(game, row, person_uid) if person_uid != "" else {}
	var lines := PackedStringArray()
	lines.append("Familiarity %.1f / %.0f." % [familiarity, FAMILIARITY_CAP])
	if left > 0:
		lines.append("Cooldown: refused until day %d (%d days left)." % [until, left])
	if person_uid == "":
		lines.append("No one is approaching.")
	elif not present:
		lines.append("Stalling: %s is not with the dragon." % str(person.get("name", "They")))
	else:
		var why := "Rising: %s is with the dragon" % str(person.get("name", "They"))
		if bool(parts.get("keeper", false)): why += "; keeper care quickens it"
		if bool(parts.get("hungry", false)): why += "; hunger slows it"
		if bool(parts.get("hurt", false)): why += "; injury slows it"
		if not bool(parts.get("keeper", false)) and not bool(parts.get("hungry", false)) and not bool(parts.get("hurt", false)):
			why += "; steady pace"
		lines.append(why + ".")
	lines.append("An average dragon decides after about %d days of steady presence." % APPROACH_PACE_DAYS)
	var gate := _order_gate(game, row)
	var can_approach := gate == "" and not approach_candidates(game, dragon_uid).is_empty()
	var can_stop := person_uid != "" and bool(Dragons.authority(game, row).get("ok", false))
	return {"ok": not row.is_empty(), "approaching": person_uid != "", "person_uid": person_uid,
		"person_name": str(person.get("name", "")), "familiarity": familiarity, "cap": FAMILIARITY_CAP,
		"cooldown_until": until, "cooldown_left": left, "present": present, "can_approach": can_approach,
		"can_stop": can_stop, "reason": gate if gate != "" else str(approach.get("last_reason", "")),
		"line": "\n".join(lines), "rising": person_uid != "" and present and left == 0,
		"pace_days": pace_days(row) if not row.is_empty() else APPROACH_PACE_DAYS}

static func after_load(game) -> void:
	for row in game.world.get("dragons", {}).get("records", {}).values():
		if not row.has("approach"): continue
		var stored: Variant = row.get("approach", {})
		if not stored is Dictionary:
			row.erase("approach")
			continue
		var approach: Dictionary = stored
		approach["familiarity"] = clampf(float(approach.get("familiarity", 0.0)), 0.0, FAMILIARITY_CAP)
		approach["cooldown_until"] = int(approach.get("cooldown_until", 0))
		approach["last_day"] = int(approach.get("last_day", -1))
		approach["last_gain"] = float(approach.get("last_gain", 0.0))
		approach["person_uid"] = str(approach.get("person_uid", ""))
		approach["familiar_person_uid"] = str(approach.get("familiar_person_uid", ""))
		approach["last_reason"] = str(approach.get("last_reason", ""))
		for flag in ["keeper", "hungry", "hurt", "present"]:
			approach[flag] = bool(approach.get(flag, false))

## One person approaches one dragon. Higher familiarity wins; a tie keeps the lower dragon id.
static func _dedupe_approaches(game) -> void:
	var registry: Dictionary = game.world.get("dragons", {}).get("records", {})
	var ids: Array = registry.keys()
	ids.sort()
	var best_uid := {}
	var best_fam := {}
	for uid in ids:
		var row: Dictionary = registry[uid]
		var who := str(_approach(row).get("person_uid", ""))
		if who == "": continue
		var fam := float(_approach(row).get("familiarity", 0.0))
		if not best_uid.has(who):
			best_uid[who] = str(uid)
			best_fam[who] = fam
			continue
		var kept_uid := str(best_uid[who])
		var kept_fam := float(best_fam[who])
		var keep_new := fam > kept_fam + 0.0001 or (absf(fam - kept_fam) <= 0.0001 and str(uid) < kept_uid)
		if keep_new:
			_end_approach(game, registry[kept_uid], "duplicate")
			best_uid[who] = str(uid)
			best_fam[who] = fam
		else:
			_end_approach(game, row, "duplicate")

## Native death/succession/care boundaries only. Absence, travel, ownership and
## custody changes do not erase a surviving relationship or assign a successor.
## An approach is not a bond: death, a new bond, lost eligibility and leaving cancel it.
static func reconcile(game) -> void:
	var registry: Dictionary = game.world.get("dragons", {}).get("records", {})
	var approach_ids: Array = registry.keys()
	approach_ids.sort()
	for uid in approach_ids:
		var pending: Dictionary = registry[uid]
		var who := str(_approach(pending).get("person_uid", ""))
		if who == "": continue
		var why := _approach_cancel_reason(game, pending, who)
		if why != "": _end_approach(game, pending, why)
	_dedupe_approaches(game)
	registry = game.world.get("dragons", {}).get("records", {})
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
