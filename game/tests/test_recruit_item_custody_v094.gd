extends RefCounted
## Real recruit creation/binding paths; no campaign mutation or conservation bypass.

class Holders extends RefCounted:
	var company: Array = []
	var stash: Array = []
	var world: Dictionary = {}

var fails: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL: ", label)

func _recruit(town: Dictionary, role: Dictionary, target_race: String, seed_value: int, replaced: bool = true) -> void:
	var holder := Holders.new()
	var before: Dictionary = WorldAudit.items(holder)
	var from_n: int = WorldAudit.items_gone.size()
	var unmade_before: int = WorldAudit.unmade_ids.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var u: Unit = Recruits.make_recruit(rng, town, Recruits.kit_for(role))
	if target_race != "":
		var person: Array = [1, 0, 0, -2400.0, "", -1, 0, "Audit Person"]
		var family: Dictionary = {"id": 0, "race": target_race, "name": "Fixture", "pp": [person]}
		Persons.bind({"culture": town["culture"]}, family, person, u, "hire", 1.0)
		check(u.race == target_race and person[5] == u.uid, "native Persons.bind applies the actual household identity/race")
	holder.company.append(u)
	var audit: Dictionary = WorldAudit.compare_items(before, WorldAudit.items(holder), from_n, WorldAudit.items_gone.size())
	print("RECRUIT_UID_V094 ", JSON.stringify({"role": role, "race": u.race, "audit": audit,
		"new_unmade": WorldAudit.unmade_ids.size() - unmade_before}, "", true, true))
	check(audit["ok"], "native recruit creation/adoption accounts for every item: " + str(role) + "/" + target_race)
	check((WorldAudit.unmade_ids.size() > unmade_before) == replaced, "only a replaced starting template was individually booked")
	for item in u.equip.values():
		check(not WorldAudit.unmade_ids.has(item.uid), "surviving native kit is never booked unmade")

func _fresh_kit_outfit(town: Dictionary, role: Dictionary, previously_held: bool = false) -> void:
	var holder := Holders.new()
	var before: Dictionary = WorldAudit.items(holder)
	var from_n: int = WorldAudit.items_gone.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = 94101
	var unit: Unit = Recruits.make_recruit(rng, town, Recruits.kit_for(role))
	if previously_held:
		holder.company.append(unit)
		before = WorldAudit.items(holder)
	var template_ids: Array = []
	for item: Item in unit.equip.values(): template_ids.append(item.uid)
	var outfit_town: Dictionary = town.duplicate(true)
	outfit_town["econ"] = {"stock": {}}
	outfit_town["shop"] = []
	TownEcon.outfit_units(outfit_town, [unit], 0.5, false, 0, false)
	if not previously_held: holder.company.append(unit)
	var audit: Dictionary = WorldAudit.compare_items(before, WorldAudit.items(holder), from_n, WorldAudit.items_gone.size())
	check(unit.equip.is_empty(), "native empty-stock outfit removes every construction template")
	if previously_held:
		check(not audit["ok"] and not audit["gone_unbooked"].is_empty(), "outfitting cannot excuse loss of previously held recruit clothing")
	else:
		check(audit["ok"], "fresh recruit clothing and shoes replaced by native outfit are all booked")
		for uid in template_ids:
			check(WorldAudit.unmade_ids.has(uid), "every discarded fresh kit UID is individually booked")


func _negative_controls() -> void:
	# A previously owned object remains a real loss even if tagged as a rolled template.
	var held := Holders.new()
	var piece: Item = Item.make("shiv", "copper", 0)
	WorldAudit.rolled(piece)
	held.stash.append(piece)
	var before: Dictionary = WorldAudit.items(held)
	var from_n: int = WorldAudit.items_gone.size()
	held.stash.clear()
	WorldAudit.drop_rolled(piece, "-synthetic previously held template")
	var audit: Dictionary = WorldAudit.compare_items(before, WorldAudit.items(held), from_n, WorldAudit.items_gone.size())
	check(not audit["ok"] and not audit["gone_unbooked"].is_empty(), "a real previously held item loss is still rejected")
	# An Item that was never a template must not be excused by drop_rolled.
	var current := Holders.new()
	before = WorldAudit.items(current)
	from_n = WorldAudit.items_gone.size()
	var real_piece: Item = Item.make("flanged_mace", "copper", 0)
	WorldAudit.drop_rolled(real_piece, "-synthetic non-template")
	audit = WorldAudit.compare_items(before, WorldAudit.items(current), from_n, WorldAudit.items_gone.size())
	check(not audit["ok"] and not WorldAudit.unmade_ids.has(real_piece.uid), "an unmarked real item disappearing is still rejected")
	# Booking an item unmade while continuing to hold it must remain an error.
	var contradiction := Holders.new()
	before = WorldAudit.items(contradiction)
	from_n = WorldAudit.items_gone.size()
	var retained: Item = Item.make("boar_spear", "copper", 0)
	WorldAudit.unmade(retained, "-synthetic contradictory booking")
	contradiction.stash.append(retained)
	audit = WorldAudit.compare_items(before, WorldAudit.items(contradiction), from_n, WorldAudit.items_gone.size())
	check(not audit["ok"] and audit["booked_but_held"] > 0, "a booked-unmade item that is still held is rejected")

func run(_tree: SceneTree) -> int:
	var faction: String = ""
	for key in DB.factions:
		if str(DB.factions[key].get("race", "")) == "human":
			faction = str(key)
			break
	check(faction != "" and DB.races.has("giant"), "native fixture races/faction exist")
	if faction == "" or not DB.races.has("giant"): return fails
	var town: Dictionary = {"id": "v094_recruit_uid", "name": "Audit Fixture", "faction": faction, "culture": "middle", "wealth": 2}
	var previous_tracking: bool = WorldAudit.tracking
	WorldAudit.tracking = true
	_recruit(town, {"kind": "job", "key": "hunter", "title": "hunter"}, "", 94001)
	_recruit(town, {"kind": "job", "key": "weaponsmith", "title": "smith"}, "giant", 94002)
	_recruit(town, {"kind": "job", "key": "market", "title": "carter"}, "giant", 94003)
	_recruit(town, {"kind": "job", "key": "weaponsmith", "title": "smith"}, "human", 94004, false)
	_recruit(town, {"kind": "job", "key": "weaponsmith", "title": "smith"}, "dwarf", 94005, false)
	_fresh_kit_outfit(town, {"kind": "state", "key": "idle", "title": "out of work"})
	_fresh_kit_outfit(town, {"kind": "job", "key": "weaponsmith", "title": "smith"})
	_fresh_kit_outfit(town, {"kind": "state", "key": "idle", "title": "out of work"}, true)
	_negative_controls()
	WorldAudit.tracking = previous_tracking
	print("Recruit item custody v094: ", checks - fails, "/", checks, " checks passed")
	return fails
