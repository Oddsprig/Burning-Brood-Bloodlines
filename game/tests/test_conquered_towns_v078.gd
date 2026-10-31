extends RefCounted
## v0.078: a conquered town's old lord loses the seat, and the liege keeps it or grants it.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0
var native: NativeFixture

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func head(tid: String) -> String:
	return str(Game.world["towns"][tid]["econ"]["head"].get("person_uid", ""))

func loyalty(tid: String) -> float:
	return float(Game.world["feudal"]["towns"][tid]["loyalty"])

func grievance(tid: String) -> float:
	return float(Game.world["feudal"]["towns"][tid]["grievance"])

func adult_of(e: Dictionary) -> int:
	return int(People.ages(Persons.race_of(e))["adult"])

func player_keep_grant_save_revoke() -> void:
	native.fixture()
	var seat_e: Dictionary = Game.world["towns"]["seat"]["econ"]
	var seat_f: Dictionary = seat_e["fams"][0]
	var king: Array = seat_f["pp"][0]
	var adult := adult_of(seat_e)
	var son: Array = native.child(seat_e, seat_f, int(seat_e["next_pid"]), 0, adult + 10, king, "Grown son")
	var young: Array = native.child(seat_e, seat_f, int(seat_e["next_pid"]), 1, adult - 1, king, "Young daughter")
	var old := head("foreign")
	var seat := head("seat")
	var old_family: Dictionary = Game.world["towns"]["foreign"]["econ"]["fams"][0]
	var purse := float(seat_f["purse"])
	var taken := Warfare._conquer(Game, "foreign")
	check(str(taken.get("to", "")) == "middle_kingdom", "player siege transfers the town")
	check(head("foreign") == seat and head("seat") == seat and head("foreign") != old, "the liege keeps the conquered town and the old lord loses it")
	check(loyalty("foreign") == 30.0 and grievance("foreign") == 45.0, "keeping a conquest does not add the grant loyalty")
	check(bool(old_family.get("ruined", false)) and Families.acres(old_family) == 0, "a conquered lord with no land is landless")
	check(str(Game.world["factions"]["middle_kingdom"]["capital"]) == "seat", "the liege's capital stays the liege's")
	check(not Feudal.grant_lordship(Game, "seat", str(son[Persons.PERSON_UID])).get("ok", false) and head("seat") == seat, "a town that was not conquered cannot be granted")
	check(not Feudal.grant_lordship(Game, "foreign", str(young[Persons.PERSON_UID])).get("ok", false) and head("foreign") == seat, "an under-age child is rejected")
	var before_l := loyalty("foreign")
	var before_g := grievance("foreign")
	var granted: Dictionary = Feudal.grant_lordship(Game, "foreign", str(son[Persons.PERSON_UID]))
	check(bool(granted.get("ok", false)) and head("foreign") == str(son[Persons.PERSON_UID]), "the liege grants the town to an adult of the house")
	check(is_equal_approx(loyalty("foreign"), before_l + 12.0) and is_equal_approx(grievance("foreign"), before_g - 10.0), "a grant uses the existing loyalty and grievance deltas")
	check(head("seat") == seat and str(Game.world["factions"]["middle_kingdom"]["capital"]) == "seat", "the grant leaves the liege's own seat")
	check(is_equal_approx(float(seat_f["purse"]), purse), "a lordship grant does not charge the house purse")
	var uid := head("foreign")
	var parsed = JSON.parse_string(JSON.stringify(Game._serialize(Game.world)))
	var saved := false
	if parsed is Dictionary:
		var back = Game._deserialize(parsed)
		var towns: Dictionary = back.get("towns", {})
		var foreign: Dictionary = towns.get("foreign", {})
		var econ: Dictionary = foreign.get("econ", {})
		var saved_head: Dictionary = econ.get("head", {})
		saved = str(saved_head.get("person_uid", "")) == uid
	check(saved and head("foreign") == uid, "the save keeps the new holder")
	var county := head("county")
	var blocked: Dictionary = Feudal.grant_lordship(Game, "foreign", county)
	check(not blocked.get("ok", false) and str(blocked.get("reason", "")).contains("seven days") and head("foreign") == uid, "a later grant waits seven days")
	var g := grievance("foreign")
	var l := loyalty("foreign")
	var revoked: Dictionary = Feudal.revoke_lordship(Game, "foreign")
	check(bool(revoked.get("ok", false)) and head("foreign") == seat, "revoke returns the town to the liege")
	check(is_equal_approx(loyalty("foreign"), l) and is_equal_approx(grievance("foreign"), g + Dynasty.LAW_GRIEVANCE), "revoke adds the existing law grievance and does not change loyalty")

func outside_authority() -> void:
	native.fixture()
	var e: Dictionary = Game.world["towns"]["seat"]["econ"]
	var f: Dictionary = e["fams"][0]
	var son: Array = native.child(e, f, int(e["next_pid"]), 0, adult_of(e) + 8, f["pp"][0], "Another son")
	var old := head("foreign")
	var denied: Dictionary = Feudal.grant_lordship(Game, "foreign", str(son[Persons.PERSON_UID]))
	check(not denied.get("ok", false) and head("foreign") == old, "a town outside the liege's authority cannot be granted")

func ai_child() -> void:
	native.fixture()
	var e: Dictionary = Game.world["towns"]["foreign"]["econ"]
	var f: Dictionary = e["fams"][0]
	var elf: Array = f["pp"][0]
	var adult := adult_of(e)
	var older: Array = native.child(e, f, int(e["next_pid"]), 0, adult + 40, elf, "Older elf")
	native.child(e, f, int(e["next_pid"]), 1, adult + 10, elf, "Younger elf")
	Warfare._apply_siege(Game, "county", "moon_court")
	check(head("county") == str(older[Persons.PERSON_UID]), "an AI conqueror grants to the oldest seatless adult of the house")
	check(is_equal_approx(loyalty("county"), 42.0) and is_equal_approx(grievance("county"), 35.0), "an AI grant uses the same loyalty and grievance deltas")
	var listed := false
	var warfare: Dictionary = Game.world.get("warfare", {})
	for row in warfare.get("conquests", []):
		if str(row.get("town_id", "")) == "county": listed = true
	check(not listed and str(Game.world["towns"]["seat"]["faction"]) == "middle_kingdom", "an offscreen conquest is not recorded as the player's")

func ai_vassals() -> void:
	native.fixture()
	Game.world["towns"]["county"]["faction"] = "moon_court"
	Game.world["towns"]["county"]["econ"]["faction"] = "moon_court"
	Feudal.prepare_world(Game)
	Game.world["feudal"]["towns"]["county"]["loyalty"] = 20.0
	var liege := head("foreign")
	var vassal := head("county")
	Warfare._apply_siege(Game, "village", "moon_court")
	check(head("village") == liege and head("village") != vassal and is_equal_approx(loyalty("village"), 30.0), "a vassal at loyalty 35 or below is not given the town")
	native.fixture()
	Game.world["towns"]["county"]["faction"] = "moon_court"
	Game.world["towns"]["county"]["econ"]["faction"] = "moon_court"
	Feudal.prepare_world(Game)
	Game.world["feudal"]["towns"]["county"]["loyalty"] = 50.0
	liege = head("foreign")
	vassal = head("county")
	Warfare._apply_siege(Game, "village", "moon_court")
	check(head("village") == vassal and head("village") != liege, "an AI conqueror grants to the most loyal vassal when no adult of the house is free")

func child_vassal() -> void:
	native.fixture()
	Game.world["towns"]["county"]["faction"] = "moon_court"
	Game.world["towns"]["county"]["econ"]["faction"] = "moon_court"
	Feudal.prepare_world(Game)
	var e: Dictionary = Game.world["towns"]["county"]["econ"]
	var ruler: Array = e["fams"][0]["pp"][0]
	var adult := adult_of(e)
	ruler[3] = -int((adult - 1) * People.year_days())
	ruler[6] = 2
	Game.world["feudal"]["towns"]["county"]["loyalty"] = 80.0
	var liege := head("foreign")
	var child := head("county")
	Warfare._apply_siege(Game, "village", "moon_court")
	check(head("village") == liege and head("village") != child and head("county") == child and is_equal_approx(loyalty("village"), 30.0), "a child vassal is never granted the conquered town")

func failed_appoint() -> void:
	native.fixture()
	Game.world["towns"]["village"]["faction"] = "moon_court"
	Game.world["towns"]["village"]["econ"]["faction"] = "moon_court"
	Feudal.prepare_world(Game)
	var old := head("village")
	Game.world["towns"]["foreign"]["econ"]["fams"][0]["pp"] = []
	var before_l := loyalty("village")
	var result: Dictionary = Feudal.after_conquest(Game, "village", "middle_kingdom", "moon_court")
	check(result.get("ok", true) == false and head("village") == old and str(result.get("holder_uid", "")) == old and is_equal_approx(loyalty("village"), before_l), "a failed appoint does not report success")

func prisoner() -> void:
	native.fixture()
	var town: Dictionary = Game.world["towns"]["foreign"]
	var e: Dictionary = town["econ"]
	var f: Dictionary = e["fams"][0]
	var ruler: Array = f["pp"][0]
	var old := str(ruler[Persons.PERSON_UID])
	var race := Persons.race_of(e)
	var u := Unit.create(race, "moon_court", false)
	u.home_town = "foreign"
	u.family = int(f["id"])
	Persons.bind(e, f, ruler, u, "army", 0.0)
	u.home_town = "foreign"
	u.family = int(f["id"])
	u.race = Persons.family_race(e, f)
	town["recruits"].append(u)
	Warfare._conquer(Game, "foreign")
	check(head("foreign") != old and head("foreign") == head("seat"), "a lord with a living company is unseated")
	var found := false
	for rec in Game.world.get("prisoners", []):
		if int(rec.get("uid", -1)) != int(u.uid): continue
		found = bool(rec.get("noble", false)) and str(rec.get("role", "")) == "ruler"
		check(Prisoners.kind_of(Game, rec) == "noble", "the unseated lord is priced as a noble, not by an invented captive flag")
	check(found, "the old lord is recorded as a noble prisoner")
	check(str(ruler[4]) != "captive", "an enemy prisoner does not take the captive person state")

func run(_tree: SceneTree) -> int:
	native = NativeFixture.new()
	player_keep_grant_save_revoke()
	outside_authority()
	ai_child()
	ai_vassals()
	child_vassal()
	failed_appoint()
	prisoner()
	print("Conquered towns v0.078: %d checks, %d failures" % [checks, fails])
	return fails
