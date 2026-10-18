class_name DragonLife
extends RefCounted
## The dragon lifecycle, run once a day after DragonCare has fed and housed every dragon:
##   egg      - incubates while it is kept warm and cared for; hatches after HATCH_DAYS of good care.
##   juvenile - a small hatchling that grows with feeding (DragonGrowth); becomes an adult after MATURE_DAYS.
##   adult    - can be bonded, ridden to war and breathe; a healthy female and male kept at the same roost
##              by the same house may lay a clutch once per BREED_COOLDOWN days.
## New eggs and hatchlings are ordinary dragon records with their own identity, owner, custody and history.
const HATCH_DAYS := 40.0
const MATURE_DAYS := 120.0          # one campaign year
const BREED_COOLDOWN := 150
const BREED_CHANCE := 0.04          # per eligible day (about one clutch in a season)
const MAX_DRAGONS_PER_HOUSE := 8

static func daily(game, day: int) -> void:
	var state: Dictionary = game.world.get("dragons", {})
	var registry: Dictionary = state.get("records", {})
	if registry.is_empty() or int(state.get("life_day", -1)) >= day: return
	# Only a day that DragonCare actually settled advances the lifecycle (re-runs and quotes change nothing).
	if not registry.values().any(func(r): return int(r.get("care", {}).get("last_day", -1)) == day and bool(r.get("alive", false))): return
	state["life_day"] = day
	var born := false
	var ids: Array = registry.keys(); ids.sort()
	for uid in ids:
		var row: Dictionary = registry[uid]
		if not bool(row.get("alive", false)): continue
		match str(row.get("stage", "")):
			"egg": born = _incubate(game, row, day) or born
			"juvenile":
				if float(day) - float(row.get("birth_day", day)) >= MATURE_DAYS:
					row["stage"] = "adult"
					Dragons._history(game, row, "matured", {})
					_announce(game, row, "%s has grown into an adult dragon and can now be ridden to war." % row.get("name", "A dragon"))
	_breed(game, registry, day)
	if born: DragonCombat.prepare_world(game)   # bodies for new hatchlings; existing bodies are never replaced

static func _has_keeper(game, row: Dictionary) -> bool:
	var town_id: String = str(row.get("location_town_id", ""))
	if town_id == "": return false
	var cuid: String = str(row.get("custodian_person_uid", ""))
	if cuid == "":
		cuid = str(row.get("owner_person_uid", ""))
	if cuid == "": return false
	var keeper: Dictionary = Dragons._person(game, cuid)
	if keeper.is_empty() or not Dragons._present(keeper, town_id): return false
	return true

static func _incubate(game, row: Dictionary, day: int) -> bool:
	var care: Dictionary = row.get("care", {})
	var last: Dictionary = care.get("last", {})
	var ratio: float = float(last.get("care_ratio", 1.0))
	var health: float = float(care.get("health", 1.0))
	if health < 0.3: return false
	var keeper_ok: bool = _has_keeper(game, row)
	var care_step: float = clampf(ratio, 0.25, 1.0)
	var speed: float = 1.0 if keeper_ok else 0.5
	row["incubation"] = float(row.get("incubation", 0.0)) + care_step * speed
	if float(row["incubation"]) < HATCH_DAYS: return false
	var key := str(row["id"]) + ":hatch"
	var seed_value := Dragons._seed(game, key)
	row["stage"] = "juvenile"
	row["name"] = Dragons._proper_name(game, key)
	row["sex"] = "female" if seed_value % 2 == 0 else "male"
	row["birth_day"] = float(day)
	row["size_class"] = "small"
	row["growth_points"] = 0.0
	row.erase("incubation")
	var mother_uid: String = str(row.get("mother_uid", ""))
	var father_uid: String = str(row.get("father_uid", ""))
	var mother_name: String = str(Dragons.get_record(game, mother_uid).get("name", "")) if mother_uid != "" else ""
	var father_name: String = str(Dragons.get_record(game, father_uid).get("name", "")) if father_uid != "" else ""
	var parent_note := "%s & %s" % [mother_name if mother_name != "" else mother_uid, father_name if father_name != "" else father_uid]
	Dragons._history(game, row, "hatched", {"day": day, "mother_uid": mother_uid, "father_uid": father_uid,
		"mother_name": mother_name, "father_name": father_name, "parents": parent_note})
	_announce(game, row, "The %s has hatched! A %s hatchling, %s, has broken from the shell." % [
		Dragons.type_label(row).replace(" Dragon", " egg"), "female" if row["sex"] == "female" else "male", row["name"]])
	return true

static func _breed(game, registry: Dictionary, day: int) -> void:
	DragonBreeding.breed_chosen_pairs(game, registry, day)
	var player_house: String = str(game.world.get("player_house", {}).get("house_uid", ""))
	var roosts := {}   # town|house -> {female: [], male: []}
	var per_house := {}
	for row: Dictionary in registry.values():
		if not bool(row.get("alive", false)): continue
		var house := str(row.get("owner_house_uid", ""))
		per_house[house] = int(per_house.get(house, 0)) + 1
		if player_house != "" and house == player_house: continue
		if str(row.get("stage", "")) != "adult": continue
		if float(row.get("care", {}).get("health", 0.0)) < 0.7: continue
		if row.get("campaign_march", {}).get("enabled", false): continue
		var key := str(row.get("location_town_id", "")) + "|" + house
		if not roosts.has(key): roosts[key] = {"female": [], "male": []}
		var sex := str(row.get("sex", ""))
		if sex in ["female", "male"]: roosts[key][sex].append(row)
	var keys: Array = roosts.keys(); keys.sort()
	for key in keys:
		var r: Dictionary = roosts[key]
		if r["female"].is_empty() or r["male"].is_empty(): continue
		var mother: Dictionary = r["female"][0]
		var father: Dictionary = r["male"][0]
		var house := str(mother.get("owner_house_uid", ""))
		if int(per_house.get(house, 0)) >= MAX_DRAGONS_PER_HOUSE: continue
		if day - int(mother.get("last_clutch_day", -BREED_COOLDOWN)) < BREED_COOLDOWN: continue
		var roll := float(Dragons._seed(game, "%s:clutch:%d" % [mother["id"], day]) % 10000) / 10000.0
		if roll >= BREED_CHANCE: continue
		var town_id := str(mother.get("location_town_id", ""))
		var owner := Dragons._person(game, str(mother.get("owner_person_uid", "")))
		if owner.is_empty(): continue
		mother["last_clutch_day"] = day
		var egg: Dictionary = DragonBreeding.spawn_egg(game, mother, father, day, 0)
		if egg.is_empty(): continue
		per_house[house] = int(per_house.get(house, 0)) + 1
		_announce(game, egg, "%s and %s have produced a clutch: a %s at %s." % [mother.get("name", "?"), father.get("name", "?"),
			egg.get("name", "dragon egg"), game.world.get("towns", {}).get(town_id, {}).get("name", "their roost")])

static func _announce(game, row: Dictionary, text: String) -> void:
	var mine := str(game.world.get("player_house", {}).get("house_uid", ""))
	var household := str(game.world.get("player_house", {}).get("household_uid", ""))
	if str(row.get("owner_household_uid", "")) == household or (mine != "" and str(row.get("owner_house_uid", "")) == mine):
		CampaignWorld.log_event(game, text)
		Ambitions.notify(game, text)
