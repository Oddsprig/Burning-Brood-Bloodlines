extends RefCounted
## Private owner lineage, actual households and existing orc office bindings only.
const NativeFixture = preload("res://tests/test_dragon_identities.gd")
var native: NativeFixture
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon asset succession: " + message)

func fixture() -> void:
	native = NativeFixture.new()
	native.fixture()

func heirs(owner: String, house: String) -> Array:
	var before: String = native.snapshot()
	var rng_state: int = Game.rng.state
	var next_unit: int = Unit._next_uid
	var rows: Array = Dynasty.asset_heirs(Game, owner, house)
	check(rows == Dynasty.asset_heirs(Game, owner, house), "repeated asset-heir reads are deterministic")
	check(native.snapshot() == before and Game.rng.state == rng_state and Unit._next_uid == next_unit,
		"asset-heir reads preserve offices, native people/accounts, RNG and Unit counter")
	return rows

func trim_memory(e: Dictionary, f: Dictionary) -> void:
	# Exercise actual bounded native memory rather than deleting the kin index.
	for i in Persons.DP_MAX + 1:
		var p: Array = native.person(e, f, int(e["next_pid"]), 0, 40, "Departed resident " + str(i))
		native.kill(str(p[Persons.PERSON_UID]))
	Feudal.finish(Game)

func gifted_owner_and_household() -> void:
	fixture()
	var e: Dictionary = Game.world["towns"]["b"]["econ"]
	var family: Dictionary = e["fams"][1]
	var destination: Dictionary = e["fams"][0]
	var owner: Array = Persons.by_pid(family, 10)
	var owner_uid: String = str(owner[Persons.PERSON_UID])
	var house: String = str(owner[Persons.HOUSE_UID])
	var daughter: Array = native.person(e, family, 12, 1, 30, "")
	daughter[1] = 1 # Native marriage rejects duplicate female given names in the destination surname.
	daughter[Persons.HOUSE_UID] = house
	daughter[Persons.FATHER_UID] = owner_uid; daughter[Persons.FA] = int(owner[0])
	var daughter_uid: String = str(daughter[Persons.PERSON_UID])
	var grandson: Array = native.person(e, family, 13, 0, 5, "Real eldest-branch grandson")
	grandson[Persons.HOUSE_UID] = house
	grandson[Persons.MOTHER_UID] = daughter_uid; grandson[Persons.MO] = int(daughter[0])
	var grandson_uid: String = str(grandson[Persons.PERSON_UID])
	native.person(e, destination, 20, 0, 33, "")
	# Complete native empty land/work metadata for the marriage's reassignment.
	var plots: Dictionary = {"v": 1, "gw": 0, "gh": 0, "g": PackedInt32Array(), "st": PackedFloat32Array(),
		"h": [], "crops": [], "bld": [], "heads": {}, "clear": -1, "cl_done": 0.0,
		"overcut": 0.0, "wood_seen": 0, "dirty": true, "drift": 0}
	for column in Plots.COLS: plots[column] = PackedInt32Array()
	e.merge({"plots": plots, "crops": {}, "wacres": {}, "wherd": {}, "open": [], "hands": 0,
		"idle_n": 0, "homes": 1, "granary": 0.0, "barn": {}, "food_short": 0.0, "unrest": 0.0, "fstage": 0})
	check(Persons.marriages(e, 0.0, 1) == 1 and destination["pp"].has(daughter) and not family["pp"].has(daughter),
		"real marriage moves one existing daughter to a different economic household")
	Feudal.finish(Game)
	Dragons.init_world(Game); Dynasty.select_city(Game, "a")
	var egg: String = native.holding("a")
	check(Dragons.transfer(Game, egg, owner_uid)["ok"] and Dynasty.town_office(Game, "b")["person_uid"] != owner_uid,
		"actual gifted owner is a registered private person distinct from the office holder")
	native.kill(owner_uid); Feudal.finish(Game)
	var rows: Array = heirs(owner_uid, house)
	check(not rows.is_empty() and rows[0]["person_uid"] == daughter_uid and rows[0]["alive"],
		"post-death private heirs follow the gifted owner, not estate or current office")
	check(not rows.is_empty() and rows[0]["town_id"] == "b" and rows[0]["family_id"] == destination["id"]
		and rows[0]["household_uid"] == destination["household_uid"] and rows[0]["house_uid"] == house,
		"moved heir keeps birth lineage and resolves her actual new household references")
	var record: Dictionary = Dragons.get_record(Game, egg)
	check(record["owner_person_uid"] == daughter_uid and record["owner_household_uid"] == destination["household_uid"],
		"actual Feudal.finish transfers the holding to that living moved heir")
	native.kill(daughter_uid); Feudal.finish(Game)
	trim_memory(e, family); trim_memory(e, destination)
	check(Dynasty._person(Game, owner_uid, true).is_empty() and Dynasty._person(Game, daughter_uid, true).is_empty(),
		"bounded native dead-person rows really trimmed both owner and eldest child")
	check(Game.world["dynasty"]["kin"].has(owner_uid) and Game.world["dynasty"]["kin"].has(daughter_uid),
		"persistent ancestry retains both actual dead identities after memory trimming")
	rows = heirs(owner_uid, house)
	check(not rows.is_empty() and rows[0]["person_uid"] == grandson_uid and rows[0]["age"] == 5,
		"dead eldest branch's real minor descendant precedes a younger living daughter after trimming")
	check(heirs(owner_uid, str(destination["founding_house_uid"])).is_empty(), "wrong household's founding lineage cannot substitute for the stored owner house")

func strength_office_gate() -> void:
	fixture()
	var town: Dictionary = Game.world["towns"]["a"]
	var e: Dictionary = town["econ"]
	var family: Dictionary = e["fams"][0]
	town["culture"] = "orc"; e["culture"] = "orc"
	var owner: Array = Persons.by_pid(family, 0)
	var owner_uid: String = str(owner[Persons.PERSON_UID])
	var house: String = str(owner[Persons.HOUSE_UID])
	var winner: Array = native.person(e, family, 3, 0, 35, "Existing native strength officeholder", owner)
	var winner_uid: String = str(winner[Persons.PERSON_UID])
	var unrelated_uid: String = native.uid("b", 0)
	var faction: Dictionary = Game.world["factions"][str(town["faction"])]
	Feudal.finish(Game)
	native.kill(owner_uid); Feudal.finish(Game)
	check(heirs(owner_uid, house).is_empty(), "unbound same-house orc kin cannot inherit through an invented contest")
	check(Dynasty.appoint(Game, "a", unrelated_uid, "Warlord"), "unrelated office holder is an actual registered person")
	Feudal.finish(Game)
	check(heirs(owner_uid, house).is_empty(), "real unrelated new title holder cannot seize the dead house's private assets")
	check(Dynasty.appoint(Game, "a", winner_uid, "Warlord"), "same-house strength office is explicitly bound to an existing real person")
	faction["war_leader"] = {"person_uid": unrelated_uid}
	Feudal.finish(Game)
	check(heirs(owner_uid, house).is_empty(), "capital office cannot inherit while native war-leader identity disagrees")
	faction["war_leader"]["person_uid"] = winner_uid
	Feudal.finish(Game)
	var rows: Array = heirs(owner_uid, house)
	check(rows.size() == 1 and rows[0]["person_uid"] == winner_uid and rows[0]["household_uid"] == family["household_uid"],
		"actual same-house bound strength office inherits only with matching capital war-leader identity")

func run(_tree: SceneTree) -> int:
	var original_world: Dictionary = Game.world
	var original_company: Array = Game.company
	var original_squads: Dictionary = Game.squads
	var original_day: float = Game.day
	var original_gold: float = Game.gold
	var original_location: String = Game.location
	gifted_owner_and_household(); strength_office_gate()
	Game.world = original_world; Game.company = original_company; Game.squads = original_squads
	Game.day = original_day; Game.gold = original_gold; Game.location = original_location
	print("dragon asset succession: %d checks, %d failures" % [checks, fails])
	return fails
