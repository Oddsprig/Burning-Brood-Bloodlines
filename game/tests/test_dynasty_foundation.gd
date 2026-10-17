extends RefCounted
## Two real native town economies; no full map/world/army generation or presim.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

## Reusable small native fixture for the interface specialist's orientation check.
func fixture() -> void:
	WorldGen.set_size(WorldGen.STRETCH)
	Game.day = 0.0; Game.gold = 1234; Game.location = ""
	Game.company.clear(); Game.stash.clear(); Game.squads.clear()
	var towns := {}
	for i in 2:
		var tid := "city_a" if i == 0 else "city_b"
		towns[tid] = {"id": tid, "name": "Aster" if i == 0 else "Bracken", "culture": "middle",
			"faction": "middle_kingdom", "capital": false, "size": 2, "wealth": 3, "specialty": "farming",
			"pos": WorldGen.cell_center(Vector2i(20 + i * 20, 25)), "recruits": [], "shop": [],
			"roads": [], "neighbours": [], "region": "middle", "crafters": {}, "healer": {},
			"prices": {}, "material_prices": {}, "contracts": [], "next_refresh": 0.0}
	Game.world = {"version": 1, "seed": 2468, "w": WorldGen.W, "h": WorldGen.H, "cell": WorldGen.CELL,
		"terrain": "g".repeat(WorldGen.W * WorldGen.H), "road": "0".repeat(WorldGen.W * WorldGen.H),
		"region": "0".repeat(WorldGen.W * WorldGen.H), "towns": towns, "warbands": {}, "lairs": {},
		"factions": {"middle_kingdom": {"treasury": 3456.0, "loot": 0.0, "towns": ["city_a", "city_b"], "capital": "city_a"}},
		"party": {"pos": towns["city_a"]["pos"], "target": towns["city_a"]["pos"], "path": [],
			"dest_town": "", "arrived": "", "safe_until": 0.0, "waiting": false}, "start_town": "city_a", "log": [], "encounter": ""}
	var before_scale: Variant = EconGen.town_scale_override
	EconGen.town_scale_override = 0.15
	for town in towns.values():
		# Match native pre-economy inputs without changing the household RNG stream.
		var town_rng := RandomNumberGenerator.new(); town_rng.seed = hash([2468, town["id"], "fixture-town"])
		Economy.make_crafters(town, town_rng)
		Economy.roll_prices(town, town_rng)
		var rng := RandomNumberGenerator.new(); rng.seed = hash([2468, town["id"], "econ"])
		EconGen.generate(Game.world, town, rng)
	EconGen.town_scale_override = before_scale
	Dynasty.prepare_world(Game)

func population() -> int:
	var n := 0
	for town in Game.world["towns"].values():
		for f in town["econ"]["fams"]:
			if not f.get("gone", false) and not f.get("estate", false): n += Families.people(f)
	return n

func goods() -> Dictionary:
	var out := {}
	for good in TownEcon.data()["goods"]:
		var n := 0
		for town in Game.world["towns"].values(): n += TownEcon.town_total(town["econ"], String(good))
		out[good] = n
	return out

func identity_selection() -> void:
	var before := JSON.stringify(Game._serialize(Game.world))
	var pop := population()
	var money := Barge.holdings(Game)
	var next_unit := Unit._next_uid
	var picks := Dynasty.choices(Game)
	check(picks.size() == 2, "both existing native town rulers are eligible choices")
	check(not Dynasty.select_city(Game, "missing"), "invalid city selection is rejected")
	check(JSON.stringify(Game._serialize(Game.world)) == before, "invalid selection and choices are pure")
	var ids := {}
	var homes := {}
	for town in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		var head: Dictionary = e["head"]
		var f: Dictionary = e["fams"][int(head["fam"])]
		var p := Persons.by_pid(f, int(head["pid"]))
		check(not p.is_empty() and String(p[Persons.PERSON_UID]) == String(head["person_uid"]), "office points at a real native registered person")
		check(head["name"] == Persons.name_of(f, p, Persons.race_of(e)), "displayed ruler name agrees with the native register")
		check(int(p[6]) != 2 and Persons.age_of(p, Game.day) >= int(People.ages(Persons.race_of(e))["adult"]), "rulers are real eligible adults")
		for family in e["fams"]:
			if family.get("estate", false): continue
			var h := String(family["household_uid"])
			check(not homes.has(h) and h != String(family["founding_house_uid"]), "household and political references are separate and globally scoped")
			homes[h] = true
			for person in family.get("pp", []) + family.get("kp", []):
				var uid := String(person[Persons.PERSON_UID])
				check(uid != "" and not ids.has(uid), "every registered adult/child has a unique stable identity")
				ids[uid] = true
	if picks.is_empty(): return
	check(Dynasty.select_city(Game, String(picks[0]["town_id"])), "valid city selects its existing ruling lineage once")
	var selected_before := JSON.stringify(Game.world["player_house"])
	check(not Dynasty.select_city(Game, String(picks[1]["town_id"])), "selection cannot switch ruling house or reset travel")
	check(JSON.stringify(Game.world["player_house"]) == selected_before, "repeat selection preserves stable references")
	check(population() == pop and absf(Barge.holdings(Game) - money) < 0.001 and Unit._next_uid == next_unit and Game.company.is_empty(), "selection never conjures population, money or Units")
	check(Game.world["party"]["pos"] == Game.world["towns"][picks[0]["town_id"]]["pos"], "native party is positioned at selected existing city")
	before = JSON.stringify(Game._serialize(Game.world))
	var r := Dynasty.ruler(Game)
	var members := Dynasty.living_members(Game)
	var a := Dynasty.accounts(Game)
	var portrait := Dynasty.portrait_spec(Game)
	Dynasty.selected(Game); Dynasty.is_extinct(Game)
	check(not r.is_empty() and not members.is_empty() and not portrait.is_empty(), "ruler, living lineage and native portrait spec are available")
	check(JSON.stringify(Game._serialize(Game.world)) == before, "all dynasty display readers leave native world data unchanged")
	var state := Dynasty.selected(Game)
	var town: Dictionary = Game.world["towns"][state["house_town_id"]]
	var f: Dictionary = town["econ"]["fams"][int(state["house_family_id"])]
	check(a["house_purse"] == float(f["purse"]) and a["company_wallet"] == float(Game.gold), "private and company accounts refer to their distinct native owners")
	check(a["city_treasury"] == float(Game.world["towns"][state["town_id"]]["econ"]["treasury"]) and a["faction_treasury"] == 3456.0, "public city and faction accounts stay separate")
	var pupil := _eligible_bride(Game.world["towns"]["city_a"]["econ"])
	if pupil.is_empty(): return
	var e: Dictionary = pupil[0]
	var mother_family: Dictionary = pupil[1]
	var mother: Array = pupil[2]
	var before_birth := (mother_family["kp"] as Array).size()
	var child := Persons.birth(e, mother_family, mother, 0.0)
	Families.born(e, mother_family, child, 0.0)
	check((mother_family["kp"] as Array).size() == before_birth + 1 and String(child[Persons.PERSON_UID]) != String(mother[Persons.PERSON_UID]), "native birth creates one child with its own immutable person reference")
	check(child[Persons.HOUSE_UID] == mother_family["founding_house_uid"] and child[Persons.MOTHER_UID] == mother[Persons.PERSON_UID], "birth uses bounded current-household affiliation and stable native maternal identity")

func _eligible_bride(e: Dictionary) -> Array:
	for f in e["fams"]:
		if f.get("estate", false): continue
		for p in f.get("pp", []):
			if int(p[6]) == 0 and int(p[2]) == 1: return [e, f, p]
	return []

func marriage_and_renumber() -> void:
	var e: Dictionary = Game.world["towns"]["city_a"]["econ"]
	# Isolate two existing adults so the real native marriage path is predictable.
	var woman_info := _eligible_bride(e)
	check(not woman_info.is_empty(), "small native fixture includes an adult woman")
	if woman_info.is_empty(): return
	var wf: Dictionary = woman_info[1]; var woman: Array = woman_info[2]
	var hf := {}; var man: Array = []
	for f in e["fams"]:
		if f.get("estate", false) or f == wf or f["name"] == wf["name"]: continue
		for p in f.get("pp", []):
			if int(p[6]) == 0 and int(p[2]) == 0: hf = f; man = p; break
		if not man.is_empty(): break
	check(not man.is_empty(), "small native fixture includes an adult man in another surname household")
	if man.is_empty(): return
	for f in e["fams"]:
		for p in f.get("pp", []): p[7] = Persons.name_of(f, p, "human")
	man[7] = ""; woman[7] = ""
	man[Persons.SP] = -1; woman[Persons.SP] = -1
	man[3] = -30 * int(People.year_days()); woman[3] = -27 * int(People.year_days())
	man[4] = ""; woman[4] = ""
	var woman_uid := String(woman[Persons.PERSON_UID]); var woman_house := String(woman[Persons.HOUSE_UID])
	var man_uid := String(man[Persons.PERSON_UID])
	var pop := population(); var money := Barge.holdings(Game)
	check(Persons.marriages(e, 0.0, 1) == 1, "real native marriage moves one actual adult")
	check(Persons.pp(hf).has(woman) and not Persons.pp(wf).has(woman), "marriage changes economic household without copying a person")
	check(woman[Persons.PERSON_UID] == woman_uid and woman[Persons.HOUSE_UID] == woman_house and woman[Persons.SPOUSE_UID] == man_uid, "marriage retains lineage/person refs and links real spouse identity")
	check(population() == pop and absf(Barge.holdings(Game) - money) < 0.001, "marriage conserves native population and money")
	var local_before := int(woman[0]); var kin_before := [woman[Persons.SPOUSE_UID], woman[Persons.MOTHER_UID], woman[Persons.FATHER_UID]]
	var copied := hf.duplicate(true)
	var target: Dictionary = Game.world["towns"]["city_b"]["econ"]
	target["next_pid"] = maxi(int(target.get("next_pid", 1)), 10000)
	var remap := Barge._renumber(target, copied)
	var moved: Array = Persons.by_pid(copied, int(remap[local_before]))
	check(not moved.is_empty() and int(moved[0]) != local_before and moved[Persons.PERSON_UID] == woman_uid and moved[Persons.HOUSE_UID] == woman_house, "native PID renumbering preserves immutable person/lineage identity")
	check([moved[Persons.SPOUSE_UID], moved[Persons.MOTHER_UID], moved[Persons.FATHER_UID]] == kin_before, "cross-town renumbering preserves stable external kinship refs")
	check(copied["household_uid"] == hf["household_uid"], "renumbering keeps stable economic household anchor")

func migration_death() -> void:
	fixture()
	var picks := Dynasty.choices(Game)
	if picks.is_empty(): check(false, "native migration fixture has a ruling family"); return
	Dynasty.select_city(Game, String(picks[0]["town_id"]))
	var state := Dynasty.selected(Game)
	var source: Dictionary = Game.world["towns"][state["house_town_id"]]
	var to: Dictionary = Game.world["towns"]["city_b" if source["id"] == "city_a" else "city_a"]
	var f: Dictionary = source["econ"]["fams"][int(state["house_family_id"])]
	var uid := String(state["ruler_uid"]); var house := String(state["house_uid"])
	var before_refs := []
	for p in f["pp"] + f["kp"]: before_refs.append(String(p[Persons.PERSON_UID]))
	var pop := population(); var money := Barge.holdings(Game); var stores := goods()
	var ruler_pid := int(Dynasty.ruler(Game)["pid"])
	to["econ"]["next_pid"] = maxi(int(to["econ"].get("next_pid", 1)), 10000)
	var nf := Barge.move_family(Game, source, f, to, "test", 1.0)
	check(not nf.is_empty(), "real native household migration succeeds without force duplication")
	if nf.is_empty(): return
	var after_refs := []
	for p in nf["pp"] + nf["kp"]: after_refs.append(String(p[Persons.PERSON_UID]))
	check(after_refs == before_refs and nf["household_uid"] == state["household_uid"], "native migration retains all immutable person/household references")
	check(population() == pop and absf(Barge.holdings(Game) - money) < 0.001, "native migration conserves total people and every coin owner")
	check(goods() == stores, "native migration conserves actual market/barn/household/granary goods")
	var r := Dynasty.ruler(Game)
	check(r["person_uid"] == uid and r["town_id"] == to["id"] and int(r["family_id"]) == int(nf["id"]) and int(r["pid"]) != ruler_pid, "selected ruler resolves to current native location after movement")
	check(Dynasty.accounts(Game)["house_purse"] == float(nf["purse"]), "private account follows the real moved economic household")
	var p := Persons.by_pid(nf, int(r["pid"]))
	Persons.remove(nf, p, to["econ"])
	var remembered := Dynasty.ruler(Game)
	check(not remembered["alive"] and remembered["person_uid"] == uid and Game.world["player_house"]["ruler_uid"] == uid, "ruler death is remembered without silently appointing a replacement")
	check(not Dynasty.is_extinct(Game), "living relatives preserve dynasty after ruler death and empty company")
	for family in to["econ"]["fams"]:
		for person in (family.get("pp", []) as Array).duplicate() + (family.get("kp", []) as Array).duplicate():
			if String(Persons.g(person, Persons.HOUSE_UID, "")) == house:
				Persons.forget(to["econ"], family, person)
				(family["kp"] if int(person[6]) == 2 else family["pp"]).erase(person)
	check(Dynasty.is_extinct(Game), "gone historical source copies do not keep a deceased dynasty alive")
	var company_person := p.duplicate(true)
	company_person[4] = "company"
	var u := Unit.new(); u.home_town = String(source["id"]); u.family = int(f["id"])
	company_person[5] = u.uid; f["pp"] = [company_person]; f["extinct"] = true; f.erase("moved")
	Game.company = [u]
	check(not Dynasty.is_extinct(Game), "real living company member outlasts economic household extinction")
	u.dead = true
	check(Dynasty.is_extinct(Game), "dead Unit cannot keep a gone household's company person alive")

func run(_tree: SceneTree) -> int:
	fixture()
	identity_selection()
	marriage_and_renumber()
	migration_death()
	print("DYNASTY FOUNDATION checks=", checks, " failures=", fails)
	return fails
