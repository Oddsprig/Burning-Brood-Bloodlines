extends RefCounted
## Short native-world conservation checks; primary runs hidden/headless and isolated.
var fails := 0
var checks := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", text)
	else: print("ok: ", text)

func run(_tree: SceneTree) -> int:
	var old_size := WorldGen.gen_size
	var old_stretch := WorldGen.gen_stretch
	WorldGen.gen_size = "normal"
	WorldGen.gen_stretch = WorldGen.STRETCH
	Game.new_game(20261010)
	check(Game.company.size() == 100, "native starting company has 100 actual people")
	var company_ids := {}
	for u in Game.company:
		var home: Dictionary = Game.world["towns"].get(u.home_town, {})
		var family := People.fam_of(home, u.family)
		var person := Persons.by_uid(family, u.uid) if not family.is_empty() else []
		check(not family.is_empty() and not person.is_empty(), "starting Unit has actual home household and registered person")
		if person.is_empty(): continue
		var uid := str(Persons.g(person, Persons.PERSON_UID, ""))
		check(uid != "" and not company_ids.has(uid) and String(person[4]) == "company", "starting company consumes 100 distinct away resident identities")
		check(u.race == String(family.get("race", Persons.race_of(home["econ"]))), "starting company body matches actual source resident race")
		company_ids[uid] = true
	var picked := {}
	var owner := {}
	var away := 0
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var c := Population.summary(e)
		away += int(c["away"])
		check(int(c["tracked_families"]) >= Population.TRACKED_HOUSEHOLDS and int(c["tracked_families"]) <= 20, "%s: 15 initial tracked households plus actual exceptional offices within 20" % town["name"])
		check(int(c["cohorts"]) <= 8 and int(c["cohorts"]) > 0, "%s: bounded workforce owners" % town["name"])
		check(int(c["anonymous"]) > int(c["detailed"]), "%s: common-folk majority" % town["name"])
		check(int(c["population"]) == Census.people(e) and int(c["population"]) == int(c["male"]) + int(c["female"]), "%s: authoritative resident census" % town["name"])
		check(int(c["households"]) > int(c["tracked_families"]) + int(c["cohorts"]), "%s: represented homes differ from tracked families" % town["name"])
		for f in e["fams"]:
			if not Population.is_cohort(f): continue
			check(f["owns"].is_empty() and Families.acres(f) == 0 and Families.heads(f) == 0, "workforce owns its purse, no family shop/estate")
			if owner.is_empty() and Population.eligible_slots(e, f, float(e.get("day", 0)), true) >= 2: picked = town; owner = f
		for b in e["biz"]:
			if b.get("closed", false) or b.get("for_sale", false): continue
			check(int(b["owner"]) >= 0 and not Population.is_cohort(e["fams"][int(b["owner"])]) and not e["fams"][int(b["owner"])].get("estate", false), "every generated active native business belongs to tracked family")
	check(not picked.is_empty(), "real anonymous draft-age residents exist")
	check(away == Game.company.size() and company_ids.size() == Game.company.size(), "company is counted exactly once away from resident town census")
	if picked.is_empty():
		WorldGen.gen_size = old_size; WorldGen.gen_stretch = old_stretch
		return fails
	var e: Dictionary = picked["econ"]
	var before := Census.people(e)
	var detail := int(Population.summary(e)["detailed"])
	var purse := float(owner["purse"])
	var stock: Dictionary = e["stock"].duplicate(true)
	var bins: Dictionary = owner["age_bins"].duplicate(true)
	for i in 3:
		Population.summary(e); Population.race_rows(e); Population.available(picked)
		People.draft_pool(picked); Persons.sync(e, owner, float(e.get("day", 0)))
	check(int(Population.summary(e)["detailed"]) == detail and owner["age_bins"] == bins, "pure census/eligibility reads never materialize anonymous people")
	var fid := People.draft(picked, [[0, 0.0, int(owner["id"]), -1]], "army")
	check(fid == int(owner["id"]) and People.last_person.size() > Persons.PERSON_UID, "one real anonymous draft becomes one stable person")
	check(Census.people(e) == before and int(Population.summary(e)["detailed"]) == detail + 1, "materialization preserves resident headcount")
	check(float(owner["purse"]) == purse and e["stock"] == stock, "materialization conserves private coin and physical market stock")
	var rng := RandomNumberGenerator.new(); rng.seed = 19
	var u := CampaignWorld.make_resident_troop(rng, String(picked["faction"]), picked)
	People.bind(picked, fid, u, "army")
	check(int(owner["serve"].get("army", 0)) > 0 and not Persons.by_uid(owner, u.uid).is_empty(), "native service removes actual working hands and binds Unit")
	var wage := 37.0
	e["treasury"] -= wage
	check(People.pay(picked, fid, wage) == wage and float(owner["purse"]) == purse + wage, "real payroll credits the same private owner")
	var p := Persons.by_uid(owner, u.uid)
	var person_uid := str(p[Persons.PERSON_UID])
	People.casualty(Game, u, "dead", "army")
	check(Census.people(e) == before - 1 and Census._book(e)["death_ids"].has(person_uid), "field death leaves town count exactly once and retains immutable identity")
	owner["ev"] = []; owner["dp"] = []; Census._book(e)["deaths"] = []
	People.casualty(Game, u, "dead", "army")
	People.casualty_rec(Game, String(picked["id"]), fid, u.name, "dead", "army", [], u.uid)
	check(Census.people(e) == before - 1, "duplicate unit death remains deduplicated after visible histories trim")
	var renewed := People.draft(picked, [[0, 0.0, int(owner["id"]), -1]], "army")
	check(renewed == fid and str(People.last_person[Persons.PERSON_UID]) != person_uid, "next soldier consumes another slot with another stable identity")
	var winner := CampaignWorld.make_resident_troop(rng, String(picked["faction"]), picked)
	People.bind(picked, renewed, winner, "army")
	var winner_p := Persons.by_uid(owner, winner.uid)
	var winner_id := str(winner_p[Persons.PERSON_UID])
	var old_house := str(winner_p[Persons.HOUSE_UID])
	var winner_name := winner.name
	var winner_birth := winner.born
	var winner_body := winner.body.to_dict()
	var row_before := Population.summary(e)
	var houses_before := int(e["homes"])
	var service_before := Families.serving(owner)
	Army.state(Game.world)["roll"][str(winner.uid)] = [picked["id"], renewed, "army", winner.name]
	var royal := Population.promote_ruler(Game, winner)
	check(not royal.is_empty() and not Population.is_cohort(royal), "actual common-folk contest winner has his own tracked household")
	if not royal.is_empty():
		var row_after := Population.summary(e)
		check(Persons.by_uid(royal, winner.uid) == winner_p and str(winner_p[Persons.PERSON_UID]) == winner_id, "office promotion moves the same registered person and Unit identity")
		check(winner.name == winner_name and winner.born == winner_birth and winner.body.to_dict() == winner_body, "office promotion preserves actual name, age and combat body")
		check(str(winner_p[Persons.HOUSE_UID]) != old_house and str(owner["founding_house_uid"]) == old_house, "only actual winner founds a lineage; cohort lineage stays separate")
		check(int(row_before["population"]) == int(row_after["population"]) and int(row_before["households"]) == int(row_after["households"]) and houses_before == int(e["homes"]), "office promotion preserves residents, represented households and physical dwellings")
		check(absf(float(row_before["private_wealth"]) - float(row_after["private_wealth"])) < 0.000001, "office purse is an owned transfer, never new money")
		check(Families.serving(owner) + Families.serving(royal) == service_before and int(Army.state(Game.world)["roll"][str(winner.uid)][1]) == winner.family, "actual service and retained Army roll follow office holder")
	_maternal_fixture(rng)
	WorldGen.gen_size = old_size; WorldGen.gen_stretch = old_stretch
	print("Population cohorts: %d checks, %d failures" % [checks, fails])
	return fails

func _maternal_fixture(rng: RandomNumberGenerator) -> void:
	var e := {"identity_scope": "maternal-fixture", "culture": "middle", "fams": [], "next_pid": 1}
	var birth_house := Families._blank(1); birth_house["name"] = "Birthhouse"
	var married_house := Families._blank(2); married_house["name"] = "Marriedhouse"
	e["fams"] = [Families._blank(0), birth_house, married_house]
	var mother := Persons._new(e, birth_house, "human", 1, -25.0 * People.year_days(), 0, rng)
	var father := Persons._new(e, married_house, "human", 0, -27.0 * People.year_days(), 0, rng)
	Persons.pp(married_house).append(father)
	Persons.pp(married_house).append(mother)   # same actual mother after native residence change
	mother[Persons.SP] = int(father[0]); father[Persons.SP] = int(mother[0])
	var original_house := str(mother[Persons.HOUSE_UID])
	var mother_id := str(mother[Persons.PERSON_UID])
	Game.world["dynasty"]["rulers"][mother_id] = original_house
	var royal_child := Persons.birth(e, married_house, mother, 0.0)
	check(str(royal_child[Persons.HOUSE_UID]) == original_house and str(mother[Persons.HOUSE_UID]) == original_house, "reigning mother's newborn preserves actual maternal dynasty after marriage")
	check(str(royal_child[Persons.MOTHER_UID]) == mother_id and str(royal_child[Persons.FATHER_UID]) == str(father[Persons.PERSON_UID]), "maternal office birth preserves real immutable parents")
	Game.world["dynasty"]["rulers"].erase(mother_id)
	var ordinary_child := Persons.birth(e, married_house, mother, 1.0)
	check(str(ordinary_child[Persons.HOUSE_UID]) == str(married_house["founding_house_uid"]), "nonreigning parent retains native birth-house affiliation rule")
