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

func lord_unit(tid: String) -> Unit:
	var town: Dictionary = Game.world["towns"][tid]
	var e: Dictionary = town["econ"]
	e["led"] = {"made": {}, "used": {}}   # native kit return books into this real fixture ledger
	var family: Dictionary = e["fams"][0]
	var person: Array = family["pp"][0]
	var u := Unit.create(Persons.family_race(e, family), str(town["faction"]), false)
	Persons.bind(e, family, person, u, "army", 0.0)
	u.home_town = tid
	family["serve"] = {"army": 1}
	u.equip["body"] = Item.make("tunic", "linen", 0)
	u.quiver["arrow_wood"] = 7
	Army.state(Game.world)["roll"][str(u.uid)] = [tid, int(family["id"]), "army", u.name]
	return u

func active_count(uid: int) -> int:
	var n := 0
	for u: Unit in Game.company + Mobilization.reserves(Game):
		if u.uid == uid: n += 1
	for town: Dictionary in Game.world["towns"].values():
		for u: Unit in town.get("recruits", []):
			if u.uid == uid: n += 1
	for band: Dictionary in Game.world["warbands"].values():
		for u: Unit in band.get("units", []):
			if u.uid == uid: n += 1
	for u: Unit in CampaignWorld.mustering_units(Game.world):
		if u.uid == uid: n += 1
	return n

## File IO plus the actual recursive Unit serializer/reader, without pretending this tiny economics fixture is
## a complete generated campaign. The full Game save/load gate is v074; this covers captive ownership itself.
func custody_reload(label: String) -> void:
	var path := "user://conquest078-" + label + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "the isolated custody save opens")
	if file == null: return
	file.store_string(JSON.stringify(Game._serialize(Game.world)))
	file.close()
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(raw is Dictionary, "the isolated custody save is valid JSON")
	if not raw is Dictionary: return
	Game.world = Game._deserialize(raw)
	Prisoners.after_load(Game)
	Army.after_load(Game)

func prisoner() -> void:
	for holder in ["recruit", "field", "company", "reserve", "mustering"]:
		native.fixture()
		var town: Dictionary = Game.world["towns"]["foreign"]
		var ruler: Array = town["econ"]["fams"][0]["pp"][0]
		var old := str(ruler[Persons.PERSON_UID])
		var u := lord_unit("foreign")
		var uid := u.uid
		var kit_uid: int = u.equip["body"].uid
		match holder:
			"recruit": town["recruits"].append(u)
			"field":
				Game.world["warbands"]["lord"] = {"id": "lord", "kind": "patrol", "faction": "moon_court", "home": "foreign", "pos": town["pos"], "units": [u]}
			"company": Game.company.append(u)
			"reserve": Mobilization._state(Game)["reserve"].append(u)
			"mustering": Game.world["work"].append(["muster", "foreign", {"fid": "moon_court", "kind": "patrol", "stage": "outfit", "wb": {"home": "foreign", "units": [u]}}])
		check(active_count(uid) > 0, "the lord is found in the real active %s holder before conquest" % holder)
		Warfare._conquer(Game, "foreign")
		check(head("foreign") != old and head("foreign") == head("seat"), "the %s lord loses his seat" % holder)
		var rec := Prisoners._find(Prisoners.held(Game), uid)
		check(not rec.is_empty() and bool(rec.get("noble", false)) and str(rec.get("former_office", "")) == "ruler", "the old lord is held once as a former ruling noble")
		check(active_count(uid) == 0 and Prisoners.units(Game).filter(func(v: Unit): return v.uid == uid).size() == 1, "capture removes the %s lord from active holders with one captive body" % holder)
		check(str(rec.get("faction", "")) == "moon_court" and u.faction == "moon_court" and str(rec.get("held_by", "")) == "middle_kingdom", "capture preserves original allegiance and the actual winner")
		check(str(rec.get("role", "")) == "army" and Army.state(Game.world)["roll"].has(str(uid)) and str(ruler[4]) == "army", "capture preserves native service role and person binding until release")
		check(Prisoners.kind_of(Game, rec) == "noble" and u.equip["body"].uid == kit_uid and int(u.quiver["arrow_wood"]) == 7, "the captive keeps his exact kit/quiver and native noble price")
		custody_reload(holder)
		rec = Prisoners._find(Prisoners.held(Game), uid)
		var back: Unit = rec.get("unit")
		check(back != null and back.uid == uid and active_count(uid) == 0 and Prisoners.units(Game).filter(func(v: Unit): return v.uid == uid).size() == 1, "serialized %s custody has no active clone" % holder)
		check(back != null and back.equip["body"].uid == kit_uid and str(rec.get("role", "")) == "army", "serialized custody retains equipment and original service")
		Prisoners._free_enemy(Game, rec, "released")
		var home: Dictionary = Game.world["towns"]["foreign"]
		var person: Array = Persons.by_pid(home["econ"]["fams"][0], 0)
		check(Prisoners._find(Prisoners.held(Game), uid).is_empty() and not Army.state(Game.world)["roll"].has(str(uid)) and str(person[4]) == "" and int(person[5]) == -1, "release returns the same person home and clears the original army service")

func ai_captor() -> void:
	native.fixture()
	# The player observes from a third realm. Neither the loser nor winner is their army.
	Game.world["towns"]["village"]["faction"] = "orc_horde"
	Game.world["towns"]["village"]["econ"]["faction"] = "orc_horde"
	Game.world["factions"]["orc_horde"] = {"capital": "village", "towns": ["village"], "treasury": 5000.0}
	Feudal.prepare_world(Game)
	Game.world.erase("player_house")   # the fixture initially selected seat; choose the independent observer natively
	check(Dynasty.select_city(Game, "village") and Warfare.player_faction(Game) == "orc_horde", "the observer actually selected the third realm")
	var u := lord_unit("county")
	var uid := u.uid
	var purse := float(Feudal._payer(Game).get("purse", 0.0))
	var gold := float(Game.gold)
	Game.world["towns"]["county"]["recruits"].append(u)
	Warfare._apply_siege(Game, "county", "moon_court")
	var rec := Prisoners._find(Prisoners.realm_held(Game, "moon_court"), uid)
	check(not rec.is_empty() and rec.get("unit") == u and str(rec.get("held_by", "")) == "moon_court" and str(rec.get("faction", "")) == "middle_kingdom", "AI conquest assigns the old-allegiance body to the actual AI captor")
	check(Prisoners.held(Game).is_empty() and Prisoners.captives(Game).is_empty() and active_count(uid) == 0, "AI-AI captivity never enters either player bargaining list or an active roster")
	check(not Prisoners.preview(Game, "ransom", uid).get("ok", false) and float(Game.gold) == gold and float(Feudal._payer(Game).get("purse", 0.0)) == purse, "the player cannot ransom another realm's prisoner or receive its money")
	custody_reload("ai")
	rec = Prisoners._find(Prisoners.realm_held(Game, "moon_court"), uid)
	check(rec.get("unit") is Unit and active_count(uid) == 0 and Prisoners.units(Game).filter(func(v: Unit): return v.uid == uid).size() == 1, "AI captive save/read retains one body under its actual captor")
	check(not Prisoners.release_realm(Game, "orc_horde", uid), "a different realm cannot release that captive")
	check(Prisoners.release_realm(Game, "moon_court", uid) and Prisoners.realm_held(Game, "moon_court").is_empty(), "the actual realm releases its prisoner through native family/army return")

## QC 097e4612: field-army people are counted at home, whereas house-company people are already away.
## Both captive paths keep one living body/person through file IO, real Court pay/exchange, and Army.sweep.
func player_losing_service(action: String, company_service: bool = false) -> void:
	native.fixture()
	var town: Dictionary = Game.world["towns"]["county"]
	var family: Dictionary = town["econ"]["fams"][0]
	var person: Array = family["pp"][0]
	town["econ"]["led"] = {"made": {}, "used": {}}
	var people_before := int(town["econ"]["pop"])
	var adults_before := int(town["econ"]["adults"])
	var males_before := int(family["m"])
	var u: Unit = null
	if company_service:
		Game.location = "county"; Game.world["party"]["pos"] = town["pos"]
		var enlisted := Mobilization.enlist_household(Game, str(person[Persons.PERSON_UID]))
		check(bool(enlisted.get("ok", false)), "the company captive fixture enlists through native service")
		if not bool(enlisted.get("ok", false)): return
		u = enlisted["unit"]
	else:
		u = lord_unit("county")
		Game.world["warbands"]["player-realm-lord"] = {"id": "player-realm-lord", "faction": "middle_kingdom", "kind": "patrol", "home": "county", "pos": town["pos"], "units": [u]}
	var uid := u.uid
	Warfare._apply_siege(Game, "county", "moon_court")
	check(not Prisoners._find(Prisoners.captives(Game), uid).is_empty() and active_count(uid) == 0, "AI victory takes the actual player-realm lord into one away captive body")
	check(not Army.state(Game.world)["roll"].has(str(uid)) and str(person[4]) == "captive" and int(family.get("serve", {}).get("army", 0)) == 0, "original public service transfers once before captivity can reach Army.sweep")
	check(int(town["econ"]["pop"]) == people_before - 1 and int(town["econ"]["adults"]) == adults_before - 1 and int(family["m"]) == males_before - 1, "captivity leaves exactly one away person, without double departure or population growth")
	var other_uid := -1
	if action == "exchange":
		var enemy := lord_unit("foreign")
		other_uid = enemy.uid
		Prisoners.held(Game).append({"uid": enemy.uid, "name": enemy.name, "faction": "moon_court", "home_town": "foreign", "family": enemy.family, "day": Game.day, "noble": true, "unit": enemy, "role": "army"})
	custody_reload(action + ("-company" if company_service else "-field"))
	var verdict := Prisoners.confirm(Game, action, uid, other_uid)
	check(bool(verdict.get("ok", false)), "actual Court %s returns the captured %s lord: %s" % [action, "company" if company_service else "realm-army", str(verdict.get("text", ""))])
	town = Game.world["towns"]["county"]; family = town["econ"]["fams"][0]
	person = Persons.by_uid(family, uid)
	var returned: Unit = Mobilization.reserve_unit(Game, uid, "county", 0)
	var deaths_before := (Census._book(town["econ"])["deaths"] as Array).size()
	Army.sweep(Game)
	check(returned != null and not returned.dead and not person.is_empty() and str(person[4]) == "reserve" and int(person[5]) == uid, "the returned lord is the same living register person and one reserve body")
	check(not Army.state(Game.world)["roll"].has(str(uid)) and Prisoners._find(Prisoners.captives(Game), uid).is_empty() and active_count(uid) == 1, "release leaves no old army roll, captive record, or duplicate active body")
	check(int(town["econ"]["pop"]) == people_before and int(town["econ"]["adults"]) == adults_before and int(family["m"]) == males_before and (Census._book(town["econ"])["deaths"] as Array).size() == deaths_before, "pay/exchange and sweep preserve original population/category counts with no false death")

func run(_tree: SceneTree) -> int:
	native = NativeFixture.new()
	player_keep_grant_save_revoke()
	outside_authority()
	ai_child()
	ai_vassals()
	child_vassal()
	failed_appoint()
	prisoner()
	ai_captor()
	player_losing_service("pay")
	player_losing_service("exchange")
	player_losing_service("pay", true)
	print("Conquered towns v0.078: %d checks, %d failures" % [checks, fails])
	return fails
