extends RefCounted
## Small native register fixture: no map/army generation or simulated contests.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func fixture() -> void:
	Game.day = 0.0; Game.gold = 50.0; Game.company.clear(); Game.squads.clear()
	var towns := {}
	for i in 4:
		var tid: String = str(["seat", "county", "village", "foreign"][i])
		var f := Families._blank(0); f["name"] = "Fixture House " + tid; f["purse"] = 10000.0
		var e := {"culture": "middle" if i < 3 else "moon_elf", "faction": "middle_kingdom" if i < 3 else "moon_court",
			"identity_scope": "987:" + tid, "fams": [f], "day": 0, "next_pid": 1, "pop": 1, "adults": 1,
			"treasury": 2000.0, "stock": {}, "hh": {}, "biz": [], "knowhow": {}, "stats": {}, "head": {"fam": 0, "title": "baron"}}
		Families.identity(e, f)
		var p := person(e, f, 0, 0, 50 if i < 3 else 200, tid + " ruler")
		f["pp"] = [p]; f["kp"] = []; f["m"] = 1
		towns[tid] = {"id": tid, "name": tid.capitalize(), "size": [3, 2, 0, 3][i], "wealth": 3,
			"pos": Vector2(i * 80, 0), "culture": e["culture"], "faction": e["faction"], "capital": i == 0 or i == 3,
			"econ": e, "recruits": [], "shop": []}
		Dynasty.bind_head(towns[tid])
	Game.world = {"seed": 987, "towns": towns, "factions": {
		"middle_kingdom": {"towns": ["seat", "county", "village"], "capital": "seat", "treasury": 3000.0},
		"moon_court": {"towns": ["foreign"], "capital": "foreign", "treasury": 4000.0}},
		"warbands": {}, "party": {"pos": Vector2.ZERO}, "log": [], "work": [], "next_id": 0}
	Dynasty.prepare_world(Game); Feudal.prepare_world(Game)
	Dynasty.select_city(Game, "seat")

func person(e: Dictionary, f: Dictionary, pid: int, sex: int, age: int, pname: String) -> Array:
	var p := [pid, 0, sex, -int(age * People.year_days()), "", -1, 0 if age >= int(People.ages(Persons.race_of(e))["adult"]) else 2, pname, -1, -1, -1, "", []]
	Persons.identity(e, f, p)
	e["next_pid"] = maxi(int(e.get("next_pid", 0)), pid + 1)
	return p

func child(e: Dictionary, f: Dictionary, pid: int, sex: int, age: int, parent: Array, pname: String) -> Array:
	var p := person(e, f, pid, sex, age, pname)
	p[Persons.HOUSE_UID] = parent[Persons.HOUSE_UID]; p[Persons.FATHER_UID] = parent[Persons.PERSON_UID]
	if int(p[6]) == 2: f["kp"].append(p); f["kids"] = int(f["kids"]) + 1
	else: f["pp"].append(p); f["m" if sex == 0 else "f"] = int(f["m" if sex == 0 else "f"]) + 1
	return p

func succession() -> void:
	var town: Dictionary = Game.world["towns"]["seat"]; var e: Dictionary = town["econ"]; var f: Dictionary = e["fams"][0]
	var king: Array = f["pp"][0]
	var older := child(e, f, 1, 0, 30, king, "Elder son")
	var younger := child(e, f, 2, 0, 28, king, "Younger son")
	var daughter := child(e, f, 3, 1, 32, king, "Elder daughter")
	var granddaughter := child(e, f, 4, 1, 12, older, "Eldest branch daughter")
	Dynasty.prepare_world(Game)
	check(Dynasty.heir(Game, "seat").get("person_uid", "") == older[Persons.PERSON_UID], "male-preference eldest son precedes older daughter")
	Persons.remove(f, older, e); Dynasty.succession_day(Game)
	f["dp"] = [] # Simulate bounded native memories having already trimmed him.
	check(Dynasty.heir(Game, "seat").get("person_uid", "") == granddaughter[Persons.PERSON_UID], "dead eldest child's descendant retains branch precedence")
	var anchor := str(e["head"]["household_uid"]); var family_index := int(e["head"]["fam"]); var money := total_coin()
	Persons.remove(f, king, e); Dynasty.succession_day(Game)
	var office := Dynasty.town_office(Game, "seat")
	check(office.get("person_uid", "") == granddaughter[Persons.PERSON_UID] and office.get("regency", false), "rightful minor inherits with visible regency")
	check(str(office.get("regent_uid", "")) != "", "living adult same-house kin provides regency")
	check(Dynasty.ruler(Game).get("person_uid", "") == granddaughter[Persons.PERSON_UID], "selected house ruler follows explicit succession")
	check(str(e["head"]["household_uid"]) == anchor and int(e["head"]["fam"]) == family_index and absf(total_coin() - money) < 0.000001, "succession preserves native account and estate anchors")
	# Native adult remove() erases pp only. Child death forgets then erases kp.
	Persons.forget(e, f, granddaughter); Persons.kp(f).erase(granddaughter)
	f["kids"] = maxi(0, int(f["kids"]) - 1); Dynasty.succession_day(Game)
	check(Dynasty.town_office(Game, "seat").get("person_uid", "") == younger[Persons.PERSON_UID], "real collateral uncle inherits after exhausted eldest branch")
	Persons.remove(f, younger, e); Dynasty.succession_day(Game)
	check(Dynasty.town_office(Game, "seat").get("person_uid", "") == daughter[Persons.PERSON_UID], "daughter fallback inherits when male branches exhausted")
	var prior_house := str(f["founding_house_uid"])
	f["founding_house_uid"] = str(Game.world["towns"]["foreign"]["econ"]["fams"][0]["founding_house_uid"])
	var newborn := Persons.birth(e, f, daughter, 0.0)
	check(str(newborn[Persons.HOUSE_UID]) == str(daughter[Persons.HOUSE_UID]), "reigning mother's newborn retains dynasty despite another birth-house lineage")
	f["founding_house_uid"] = prior_house
	e["culture"] = "dwarf"
	check(Dynasty.law(Game, "seat") == "male_preference", "dwarves use confirmed male-preference law")
	e["culture"] = "middle"
	var ee: Dictionary = Game.world["towns"]["foreign"]["econ"]; var ef: Dictionary = ee["fams"][0]; var elf: Array = ef["pp"][0]
	var eldest := child(ee, ef, 1, 1, 100, elf, "Eldest elven daughter")
	child(ee, ef, 2, 0, 80, elf, "Younger elven son"); Dynasty.prepare_world(Game)
	check(Dynasty.law(Game, "foreign") == "absolute" and Dynasty.heir(Game, "foreign").get("person_uid", "") == eldest[Persons.PERSON_UID], "elves inherit absolute eldest-child branches regardless of sex")
	var pure := JSON.stringify(Game._serialize(Game.world))
	Dynasty.town_office(Game, "seat"); Dynasty.heirs(Game, "foreign"); Feudal.hierarchy(Game, "middle_kingdom")
	check(JSON.stringify(Game._serialize(Game.world)) == pure, "political and genealogy readers are pure")

func total_coin() -> float:
	var coin := float(Game.gold)
	for town in Game.world["towns"].values():
		coin += float(town["econ"]["treasury"])
		for f in town["econ"]["fams"]: coin += float(f["purse"])
	for fac in Game.world["factions"].values(): coin += float(fac["treasury"])
	for band in Game.world["warbands"].values(): coin += float(band.get("gold", 0.0))
	return coin

func feudal() -> void:
	check(Feudal.hierarchy(Game, "middle_kingdom").size() == 3, "every settlement appears in its real faction hierarchy")
	check(Feudal.summary(Game, "village")["liege_town_id"] == "county" and Feudal.summary(Game, "county")["liege_town_id"] == "seat", "village -> county -> sovereign hierarchy is cycle-free")
	var coin := total_coin(); var f := Feudal.tax_recipient(Game, "county"); var purse := float(f["purse"])
	var gold := float(Game.gold)
	check(Feudal.fund_army(Game, 400.0)["ok"] and absf(float(Game.gold) - gold - 400.0) < 0.000001, "Fund Army transfers real house funds into company wallet")
	check(absf(total_coin() - coin) < 0.000001, "Fund Army conserves all-account coin")
	check(not Feudal.fund_army(Game, 0.5)["ok"] and absf(total_coin() - coin) < 0.000001, "integer company wallet never truncates a fractional private transfer")
	check(Feudal.intrigue(Game, "county", "grant")["ok"] and float(f["purse"]) > purse, "vassal grant pays a real native house and affects loyalty")
	check(not Feudal.intrigue(Game, "county", "pressure")["ok"] and not Feudal.intrigue(Game, "foreign", "pressure")["ok"], "political cooldown and domain authorization are enforced")
	Feudal.daily(Game, 1); var after := total_coin(); var once := JSON.stringify(Game._serialize(Game.world))
	Feudal.daily(Game, 1)
	check(absf(after - coin) < 0.000001 and once == JSON.stringify(Game._serialize(Game.world)), "private daily tribute conserves coin and runs once per day")
	var troop := Unit.create("human", "middle_kingdom", false); troop.home_town = "county"; troop.family = 0
	var other := Unit.create("human", "middle_kingdom", false); other.home_town = "seat"; other.family = 0
	var cp: Array = Game.world["towns"]["county"]["econ"]["fams"][0]["pp"][0]
	Persons.bind(Game.world["towns"]["county"]["econ"], Game.world["towns"]["county"]["econ"]["fams"][0], cp, troop, "army", 0)
	Game.world["warbands"]["mixed"] = {"id": "mixed", "faction": "middle_kingdom", "kind": "patrol", "home": "seat", "pos": Vector2.ZERO,
		"units": [troop, other], "stores": {"grain": 7}, "gold": 90.0}
	Game.world["army"] = {"v": 1, "roll": {str(troop.uid): ["county", 0, "army", troop.name]}, "f": {"middle_kingdom": {"posts": [troop.uid], "fights": [], "bill": 5.0}}}
	Game.world["feudal"]["towns"]["county"]["loyalty"] = 10.0
	var refs := Unit._next_uid; coin = total_coin(); var race := troop.race
	check(Feudal.defect(Game, "county", "moon_court")["ok"], "player-owned vassal can defect to a different-race realm")
	check(Game.world["towns"]["county"]["faction"] == "moon_court" and Game.world["towns"]["county"]["econ"]["culture"] == "middle", "real ownership changes while resident culture stays authoritative")
	check(troop.faction == "moon_court" and troop.race == race and other.faction == "middle_kingdom" and Unit._next_uid == refs, "existing home-town Units change allegiance without body conversion or duplication")
	var grain := 0; var men := 0
	for band in Game.world["warbands"].values(): grain += int(band.get("stores", {}).get("grain", 0)); men += band["units"].size()
	check(grain == 7 and men == 2 and absf(total_coin() - coin) < 0.000001, "mixed-force split conserves soldiers, provisions and wallet coin")
	check(not Game.world["factions"]["middle_kingdom"]["towns"].has("county") and Game.world["factions"]["moon_court"]["towns"].has("county"), "faction holdings reflect actual defection")
	check(Game.world["army"]["f"]["middle_kingdom"]["posts"][0] == -1 and Game.world["army"]["roll"].has(str(troop.uid)), "native rank vacancy changes while stable service roll survives")
	check(not Feudal.defect(Game, "county", "middle_kingdom")["ok"], "lost domain and cooldown prevent immediate reverse defection")
	Game.world["feudal"]["towns"]["seat"]["loyalty"] = 10.0
	check(Feudal.defect(Game, "seat", "moon_court")["ok"] and Game.world["factions"]["middle_kingdom"]["capital"] == "village", "capital defection appoints a real remaining native settlement seat")
	check(Feudal.hierarchy(Game, "middle_kingdom").size() == 1 and Feudal.summary(Game, "village")["liege_town_id"] == "", "remaining settlement retains a sovereign root with no hierarchy cycle")
	check(absf(total_coin() - coin) < 0.000001, "capital ownership changes never mint or confiscate faction wealth")

func orc_binding() -> void:
	var cap: Dictionary = Game.world["towns"]["seat"]
	var home: Dictionary = Game.world["towns"]["county"]
	home["econ"]["culture"] = "orc"; home["faction"] = "orc_horde"; home["econ"]["faction"] = "orc_horde"
	Game.world["factions"]["orc_horde"] = {"capital": "seat", "towns": ["seat", "county"], "treasury": 20.0}
	var f: Dictionary = home["econ"]["fams"][0]; var p: Array = f["pp"][0]
	var u := Unit.create("orc", "orc_horde", false); u.home_town = "county"; u.family = 0
	Persons.bind(home["econ"], f, p, u, "army", 0)
	var anchor := str(cap["econ"]["head"]["household_uid"]); var purse := float(cap["econ"]["fams"][0]["purse"])
	var before := Unit._next_uid
	Army._war_leader(Game, "orc_horde", u, "warlord")
	check(str(cap["econ"]["head"]["person_uid"]) == str(p[Persons.PERSON_UID]) and cap["econ"]["head"]["name"] == u.name, "native orc army winner binds the actual registered person from another town")
	check(cap["econ"]["head"]["household_uid"] == anchor and int(cap["econ"]["head"]["fam"]) == 0 and float(cap["econ"]["fams"][0]["purse"]) == purse and Unit._next_uid == before, "orc sovereign binding preserves capital economic owners, money and existing Unit")

func run(_tree: SceneTree) -> int:
	fixture(); succession(); fixture(); feudal(); fixture(); orc_binding()
	print("Feudal succession: %d checks, %d failures" % [checks, fails])
	return fails
