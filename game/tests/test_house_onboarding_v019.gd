extends RefCounted
## Small native registers, real kin and owner accounts; no map generation.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

## Shared chooser fixture. Returned families/persons are the actual native rows.
func fixture() -> Dictionary:
	var native = NativeFixture.new()
	native.fixture()
	Game.world.erase("player_house"); Game.gold = 0; Game.location = ""
	Game.company.clear(); Game.stash.clear(); Game.squads.clear()
	Game.provisions = {"meal": [], "beer": [], "wine": []}
	Game.world["party"] = {"pos": Vector2(9, 11), "target": Vector2(9, 11), "path": [], "dest_town": "", "arrived": "", "waiting": false}
	var town: Dictionary = Game.world["towns"]["seat"]; var e: Dictionary = town["econ"]
	var ruling: Dictionary = e["fams"][0]; var king: Array = ruling["pp"][0]
	var ordinary: Dictionary = Families._blank(1)
	ordinary["name"] = "Native Cadet"; ordinary["purse"] = 417.0; ordinary["homes"] = 1
	ordinary["land"] = {"wheat": 2}; ordinary["pp"] = []; ordinary["kp"] = []
	e["fams"].append(ordinary); Families.identity(e, ordinary)
	var leader: Array = native.person(e, ordinary, int(e["next_pid"]), 0, 42, "Cadet father")
	leader[Persons.HOUSE_UID] = king[Persons.HOUSE_UID]; leader[Persons.FATHER_UID] = king[Persons.PERSON_UID]
	ordinary["pp"].append(leader); ordinary["m"] = 1
	var daughter: Array = native.child(e, ordinary, int(e["next_pid"]), 1, 25, leader, "Elder daughter")
	var son: Array = native.child(e, ordinary, int(e["next_pid"]), 0, 22, leader, "Younger son")
	e["pop"] = int(e["pop"]) + 3; e["adults"] = int(e["adults"]) + 3
	# Even a valid named person in an aggregate owner row is not a local house choice.
	var cohort: Dictionary = Families._blank(2)
	cohort["name"] = "Worker pool"; cohort["cohort"] = true; cohort["pp"] = []; cohort["kp"] = []
	e["fams"].append(cohort); Families.identity(e, cohort)
	var worker: Array = native.person(e, cohort, int(e["next_pid"]), 0, 35, "Named worker")
	cohort["pp"].append(worker); cohort["m"] = 1
	Dynasty.prepare_world(Game)
	return {"town_id": "seat", "ordinary": ordinary, "ruling": ruling, "leader": leader, "son": son, "daughter": daughter, "cohort": cohort}

func fingerprint() -> String:
	return JSON.stringify(Game._save_tree()) + "|%s|%s|%s" % [str(Game.rng.state), str(Unit._next_uid), str(Item._next_uid)]

func owners() -> String:
	return JSON.stringify(Game._serialize(Game.world["towns"])) + JSON.stringify(Game._serialize(Game.world["factions"]))

func reads_and_customization() -> void:
	var fx: Dictionary = fixture(); var f: Dictionary = fx["ordinary"]
	var before := fingerprint(); var uid := str(f["household_uid"])
	var towns: Array = HouseOnboarding.settlements(Game)
	var houses: Array = HouseOnboarding.houses(Game, "seat")
	check(towns.size() == 4 and towns[0].has("pos"), "choices expose actual existing settlements and map positions")
	check(houses.size() == 2 and houses[0]["holds_office"], "actual ruling family and tracked cadet are choices; named cohort is excluded")
	for row in houses:
		check(row["household_uid"] != str(fx["cohort"]["household_uid"]), "aggregate owner cannot become campaign house")
		check(not Dynasty.person(Game, str(row["leader_uid"])).is_empty(), "each displayed leader is an actual registered identity")
	var custom := {"display_name": "  The   Copper Oath  ", "emblem": "wolf", "primary_color": "#abcdef", "secondary_color": "#123456"}
	var review: Dictionary = HouseOnboarding.preview(Game, "seat", uid, custom)
	check(review["ok"] and review["customization"]["display_name"] == "The Copper Oath", "display customization is sanitized without renaming native family")
	check(review["customization"]["primary_color"] == "#ABCDEF" and review["portrait_spec"]["prim"] == Color("#ABCDEF"), "normalized banner colour reaches actual person's portrait spec")
	check(review["leader_uid"] == fx["leader"][Persons.PERSON_UID] and not review["holds_office"] and review["leadership_mode"] == "household", "same-lineage cadet remains a private household")
	check(review["house"]["house_purse"] == 417.0 and review["house"]["member_count"] == 3, "preview shows actual private purse and actual registered members")
	check(review["house"]["house_uid"] == fx["ruling"]["pp"][0][Persons.HOUSE_UID] and uid != fx["ruling"]["household_uid"], "test deliberately separates shared dynasty and private household ownership")
	review["house"]["house_purse"] = -1; review["customization"]["display_name"] = "Tampered"
	towns[0]["town_name"] = "Tampered"; houses[0]["leader_name"] = "Tampered"
	var again: Dictionary = HouseOnboarding.preview(Game, "seat", uid)
	check(again["house"]["house_purse"] == 417.0 and again["customization"]["display_name"] == "Native Cadet", "returned lists and review metadata are detached")
	for bad in [{"display_name": "[b]Name"}, {"display_name": "Name\n"}, {"display_name": " ", "emblem": "wolf"}, {"display_name": "X".repeat(41)}, {"emblem": "invented"}, {"primary_color": "#12345"}, {"secondary_color": "#12345Z"}, {"purse": 999}]:
		check(not HouseOnboarding.preview(Game, "seat", uid, bad)["ok"], "invalid display-only customization rejected")
	check(not HouseOnboarding.preview(Game, "missing", uid)["ok"] and HouseOnboarding.houses(Game, "missing").is_empty(), "missing settlement cannot produce a house")
	check(fingerprint() == before, "all lists, preview, invalid inputs and cancelled review preserve full native snapshot/RNG/UIDs")

func begin_and_roundtrip() -> void:
	var fx: Dictionary = fixture(); var f: Dictionary = fx["ordinary"]
	var before_owners := owners(); var units := Unit._next_uid; var items := Item._next_uid; var rng := Game.rng.state
	var custom := {"display_name": "Copper Oath", "emblem": "hammer", "primary_color": "#B87943", "secondary_color": "#EDE5D0"}
	var result: Dictionary = HouseOnboarding.begin(Game, "seat", str(f["household_uid"]), custom, str(fx["leader"][Persons.PERSON_UID]))
	check(result["ok"], "explicit Begin accepts reviewed real local household")
	check(Game.company.is_empty() and Game.gold == 0 and Game.stash.is_empty() and Game.provisions["meal"].is_empty(), "Begin grants no army, coin, equipment or food")
	check(Unit._next_uid == units and Item._next_uid == items and Game.rng.state == rng, "Begin allocates no Unit/Item identity and consumes no native random stream")
	check(owners() == before_owners and f["name"] == "Native Cadet", "Begin/custom name does not appoint a lord, rename fiscal records or alter any owner assets")
	check(Game.world["party"]["pos"] == Game.world["towns"]["seat"]["pos"] and Game.location == "seat", "Begin positions only existing native party at chosen settlement")
	var state: Dictionary = Dynasty.selected(Game); var ruler: Dictionary = Dynasty.ruler(Game)
	check(state["house_name"] == "Copper Oath" and state["native_house_name"] == "Native Cadet" and state["household_uid"] == f["household_uid"], "saved display identity remains separate from real native household")
	check(ruler["person_uid"] == fx["leader"][Persons.PERSON_UID] and ruler["title"] == "House leader" and not Dynasty.holds_office(Game), "ordinary household selected ruler means real private leader, not town lord")
	check(not Feudal.can_act(Game, "seat") and not Feudal.can_act(Game, "county"), "cadet shared birth-house reference grants no public settlement or vassal command")
	check(Dynasty.accounts(Game)["house_purse"] == 417.0 and Dynasty.accounts(Game)["company_wallet"] == 0.0, "native private and army account readers remain separate")
	var pure := fingerprint()
	check(not HouseOnboarding.begin(Game, "county", str(Game.world["towns"]["county"]["econ"]["fams"][0]["household_uid"]))["ok"], "Begin cannot switch family or reset campaign")
	Dynasty.selected(Game); Dynasty.ruler(Game); Dynasty.selected_heir(Game); Dynasty.selected_office(Game); Dynasty.portrait_spec(Game)
	check(fingerprint() == pure, "repeat Begin and selected leadership/portrait readers are pure")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(Game._save_tree()))
	var restored: Dictionary = Game._deserialize(saved["world"])
	check(restored["player_house"]["customization"] == custom and restored["player_house"]["household_uid"] == f["household_uid"], "current native JSON snapshot preserves custom display and exact stable owner refs")
	check(restored["towns"]["seat"]["econ"]["fams"][1]["name"] == "Native Cadet" and restored["player_house"]["leadership_mode"] == "household", "saved economic name and private leadership mode remain distinct")

func stale_and_work_guards() -> void:
	var fx: Dictionary = fixture(); var f: Dictionary = fx["ordinary"]; var leader: Array = fx["leader"]
	var uid := str(f["household_uid"]); var leader_uid := str(leader[Persons.PERSON_UID])
	Persons.remove(f, leader, Game.world["towns"]["seat"]["econ"])
	var before := fingerprint()
	check(not HouseOnboarding.begin(Game, "seat", uid, {}, leader_uid)["ok"], "dead reviewed candidate must be reviewed again, never silently substituted")
	check(Game.world.get("player_house", {}).is_empty() and fingerprint() == before, "stale leader rejection has no campaign/account/location side effects")
	fx = fixture(); f = fx["ordinary"]
	var moved: Dictionary = f.duplicate(true); moved["id"] = 1
	f["gone"] = true; f["moved"] = "county"; Game.world["towns"]["county"]["econ"]["fams"].append(moved)
	before = fingerprint()
	check(not HouseOnboarding.begin(Game, "seat", str(f["household_uid"]), {}, str(fx["leader"][Persons.PERSON_UID]))["ok"], "moved household is not selectable at old settlement")
	check(fingerprint() == before and HouseOnboarding.preview(Game, "county", str(moved["household_uid"]))["ok"], "moved actual household retains stable refs at new native location")
	fx = fixture(); f = fx["ordinary"]
	Game.world["work"] = [{"kind": "fixture"}]; before = fingerprint()
	check(not HouseOnboarding.begin(Game, "seat", str(f["household_uid"]))["ok"] and fingerprint() == before, "pending native work cannot be bypassed by Begin")
	Game.world["work"] = []; Game.world["party"] = {}; before = fingerprint()
	check(not HouseOnboarding.begin(Game, "seat", str(f["household_uid"]))["ok"] and fingerprint() == before, "missing party is rejected without creating a replacement")

func leadership_and_office_collision() -> void:
	var fx: Dictionary = fixture(); var f: Dictionary = fx["ordinary"]; var e: Dictionary = Game.world["towns"]["seat"]["econ"]
	var leader: Array = fx["leader"]; var son: Array = fx["son"]; var daughter: Array = fx["daughter"]
	check(HouseOnboarding.begin(Game, "seat", str(f["household_uid"]), {"display_name": "Copper Oath"}, str(leader[Persons.PERSON_UID]))["ok"], "private leadership fixture begins")
	check(Dynasty.leadership_law(Game) == "male_preference" and Dynasty.selected_heir(Game)["person_uid"] == son[Persons.PERSON_UID], "private human leader uses real male-preference child branches")
	var state_before := JSON.stringify(Game.world["player_house"]); var purse := float(f["purse"])
	var native = NativeFixture.new(); var ruling: Dictionary = fx["ruling"]
	var replacement: Array = native.child(e, ruling, int(e["next_pid"]), 0, 26, ruling["pp"][0], "Native new lord")
	Dynasty.prepare_world(Game)
	check(Dynasty.appoint(Game, "seat", str(replacement[Persons.PERSON_UID])), "real native lord appointment succeeds")
	check(JSON.stringify(Game.world["player_house"]) == state_before and float(f["purse"]) == purse, "same-lineage lord appointment cannot redirect ordinary leader or purse anchor")
	check(not Dynasty.holds_office(Game) and Dynasty.ruler(Game)["person_uid"] == leader[Persons.PERSON_UID], "private selection stays independent after town office changes")
	var office := JSON.stringify(e["head"]); var all_owners := owners()
	Persons.remove(f, leader, e); Dynasty.succession_day(Game)
	check(Dynasty.ruler(Game)["person_uid"] == son[Persons.PERSON_UID] and Dynasty.selected(Game)["house_name"] == "Copper Oath", "private native leader death follows real child and keeps customization")
	check(JSON.stringify(e["head"]) == office and str(Game.world["player_house"]["estate_household_uid"]) == str(f["household_uid"]), "private succession neither appoints town lord nor acquires lord estate")
	check(float(f["purse"]) == purse and all_owners != owners(), "actual death updates only native genealogy; private purse remains unchanged")
	Persons.remove(f, son, e); Dynasty.succession_day(Game)
	check(Dynasty.ruler(Game)["person_uid"] == daughter[Persons.PERSON_UID], "private daughter inherits after male child branch is exhausted")
	check(Dynasty.appoint(Game, "seat", str(daughter[Persons.PERSON_UID])) and Dynasty.holds_office(Game), "exact selected person legitimately appointed to office gains only actual native office mode")
	check(Game.world["player_house"]["leadership_mode"] == "office" and Game.world["player_house"]["customization"]["display_name"] == "Copper Oath", "real appointment preserves customization and marks office leadership explicitly")
	fx = fixture(); f = fx["ordinary"]; e = Game.world["towns"]["seat"]["econ"]
	e["culture"] = "moon_elf"; Dynasty.prepare_world(Game)
	check(HouseOnboarding.begin(Game, "seat", str(f["household_uid"]))["ok"], "real local elven household can begin")
	check(Dynasty.leadership_law(Game) == "absolute" and Dynasty.selected_heir(Game)["person_uid"] == fx["daughter"][Persons.PERSON_UID], "private elves retain eldest-child native law")
	fx = fixture(); f = fx["ordinary"]; e = Game.world["towns"]["seat"]["econ"]
	e["culture"] = "dwarf"; Dynasty.prepare_world(Game)
	check(HouseOnboarding.begin(Game, "seat", str(f["household_uid"]))["ok"] and Dynasty.leadership_law(Game) == "male_preference", "private dwarves preserve confirmed native male preference")
	fx = fixture(); f = fx["ordinary"]; e = Game.world["towns"]["seat"]["econ"]
	e["culture"] = "orc"; Dynasty.prepare_world(Game)
	check(HouseOnboarding.begin(Game, "seat", str(f["household_uid"]))["ok"] and Dynasty.leadership_law(Game) == "household_head" and Dynasty.law(Game, "seat") == "strength", "civilian orc head rule cannot replace native strength office law")
	fx = fixture()
	check(Dynasty.select_city(Game, "seat") and Dynasty.holds_office(Game) and Feudal.can_act(Game, "seat"), "legacy select_city remains real office selection with existing command rights")
	check(Dynasty.selected_heir(Game) == Dynasty.heir(Game, "seat") and Dynasty.leadership_law(Game) == Dynasty.law(Game, "seat"), "selected actual office keeps existing heir and law semantics")

func run(_tree: SceneTree) -> int:
	reads_and_customization(); begin_and_roundtrip(); stale_and_work_guards(); leadership_and_office_collision()
	print("House onboarding v019: %d checks, %d failures" % [checks, fails])
	return fails
