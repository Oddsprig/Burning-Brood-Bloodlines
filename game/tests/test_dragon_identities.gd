extends RefCounted
## Semantic native-register fixtures only; no whole-world generation or battles.
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL dragon identities: " + why)

func person(e: Dictionary, f: Dictionary, pid: int, sex: int, years: int, name: String, parent: Array = []) -> Array:
	var p := [pid, 0, sex, -int(years * People.year_days()), "", -1,
		2 if years < int(People.ages(Persons.race_of(e))["adult"]) else 0, name, -1, -1, -1, "", []]
	Persons.identity(e, f, p)
	if not parent.is_empty():
		p[Persons.HOUSE_UID] = parent[Persons.HOUSE_UID]
		p[Persons.FATHER_UID] = parent[Persons.PERSON_UID]
		p[Persons.FA] = parent[0]
	if int(p[6]) == 2: f["kp"].append(p); f["kids"] = int(f["kids"]) + 1
	else: f["pp"].append(p); f["m" if sex == 0 else "f"] = int(f["m" if sex == 0 else "f"]) + 1
	e["next_pid"] = maxi(int(e.get("next_pid", 0)), pid + 1)
	e["pop"] = int(e.get("pop", 0)) + 1
	if int(p[6]) != 2: e["adults"] = int(e.get("adults", 0)) + 1
	return p

func fixture(seed_value: int = 5005) -> void:
	Game.day = 0.0; Game.gold = 123.0; Game.company = []; Game.squads = {}
	var towns := {}; var ids := ["a", "b", "c", "d", "invalid"]
	var cultures := ["middle", "middle", "moon_elf", "dwarf", "middle"]
	var factions := ["middle_kingdom", "middle_kingdom", "moon_court", "dwarf_holds", "middle_kingdom"]
	for i in ids.size():
		var tid := str(ids[i]); var f := Families._blank(0)
		f["name"] = "Native " + tid; f["purse"] = 321.0; f["pp"] = []; f["kp"] = []
		var e := {"culture": cultures[i], "identity_scope": "%d:%s" % [seed_value, tid], "day": 0.0,
			"fams": [f], "next_pid": 0, "pop": 0, "adults": 0, "stock": {"grain": 50}, "biz": [],
			"price": {"grain": 4.0}, "treasury": 456.0, "head": {"fam": 0, "title": "Lord"}}
		Families.identity(e, f)
		if tid != "invalid":
			var parent := person(e, f, 0, 0, 160 if tid == "c" else 55, tid + " ruler")
			person(e, f, 1, 1, 80 if tid == "c" else (35 if tid == "d" else 12), tid + " eldest daughter", parent)
			person(e, f, 2, 0, 60 if tid == "c" else (22 if tid == "d" else 8), tid + " younger son", parent)
		else: e["head"] = {}
		towns[tid] = {"id": tid, "name": tid, "faction": factions[i], "culture": cultures[i],
			"capital": tid in ["a", "c", "d"], "size": 2, "wealth": 3, "pos": Vector2(i * 30, 0), "econ": e}
		Dynasty.bind_head(towns[tid])
	# A real detailed private household whose head holds no political office.
	var be: Dictionary = towns["b"]["econ"]; var private := Families._blank(1)
	private["name"] = "Private Gift House"; private["pp"] = []; private["kp"] = []; private["purse"] = 789.0
	be["fams"].append(private); Families.identity(be, private)
	var gift_owner := person(be, private, 10, 0, 40, "Non-ruler owner")
	person(be, private, 11, 1, 9, "Non-ruler daughter", gift_owner)
	Game.world = {"seed": seed_value, "towns": towns, "factions": {
		"middle_kingdom": {"capital": "a", "towns": ["a", "b", "invalid"], "treasury": 654.0},
		"moon_court": {"capital": "c", "towns": ["c"], "treasury": 987.0},
		"dwarf_holds": {"capital": "d", "towns": ["d"], "treasury": 852.0}},
		"warbands": {}, "lairs": {}, "party": {"pos": Vector2.ZERO}, "log": [], "work": []}
	Dynasty.prepare_world(Game); Feudal.prepare_world(Game)

func snapshot() -> String:
	return JSON.stringify(Game._serialize(Game.world))

func native_snapshot() -> String:
	var world: Dictionary = Game.world.duplicate(true); world.erase("dragons")
	return JSON.stringify(Game._serialize(world))

func uid(town_id: String, pid: int, family_id: int = 0) -> String:
	var f: Dictionary = Game.world["towns"][town_id]["econ"]["fams"][family_id]
	return str(Persons.g(Persons.by_pid(f, pid), Persons.PERSON_UID, ""))

func holding(town_id: String, stage: String = "egg") -> String:
	for row in Dragons.records(Game):
		if row["estate_town_id"] == town_id and row["stage"] == stage: return str(row["id"])
	return ""

func kill(person_uid: String) -> void:
	var loc := Dynasty._person(Game, person_uid)
	if loc.is_empty(): return
	var e: Dictionary = loc["econ"]; var f: Dictionary = loc["family"]; var p: Array = loc["person"]
	if int(p[6]) == 2:
		Persons.forget(e, f, p); Persons.kp(f).erase(p); f["kids"] = maxi(0, int(f["kids"]) - 1)
	else:
		Persons.remove(f, p, e); f["m" if int(p[2]) == 0 else "f"] = maxi(0, int(f["m" if int(p[2]) == 0 else "f"]) - 1)
		e["adults"] = maxi(0, int(e["adults"]) - 1)
	e["pop"] = maxi(0, int(e["pop"]) - 1)
	Dynasty.succession_day(Game)

func catalog_and_generation() -> void:
	fixture()
	var native := native_snapshot(); var rs := Game.rng.state; var next_unit := Unit._next_uid
	Dragons.init_world(Game)
	check(native_snapshot() == native and Game.rng.state == rs and Unit._next_uid == next_unit, "initial records conserve native people/coin/goods/RNG/Unit counter")
	var cat := Dragons.catalogs()
	check(cat["gems"].size() >= 16 and cat["morphs"].size() >= 6 and cat["sizes"].size() == 5, "complete palettes, builds and sizes")
	check(cat["anatomy"]["hind_legs"] == 2 and cat["anatomy"]["wings"] == 2 and cat["anatomy"]["separate_front_legs"] == 0, "two hind legs and wings as forelimbs only")
	var names := []; var gems := {}
	for gem in cat["gems"]:
		names.append(gem["name"]); gems[gem["id"]] = gem
		check(str(gem["base"]).begins_with("#") and str(gem["base"]).length() == 7 and str(gem["accent"]).length() == 7, "HTML hex palette " + str(gem["name"]))
	for name in ["Ruby", "Sapphire", "Black Diamond", "Emerald", "Amethyst", "Opal", "Topaz", "Garnet", "Jade", "Aquamarine", "Citrine", "Moonstone", "Pearl", "Onyx", "Diamond", "Tourmaline"]:
		check(names.has(name), "canonical gem naming " + name)
	var size_ids := []
	for size in cat["sizes"]: size_ids.append(size["id"])
	check(size_ids == ["small", "medium", "large", "huge", "colossal"], "size classes do not invent a growth stage")
	var rows := Dragons.records(Game)
	check(rows.size() == 10 and int(Game.world["dragons"]["next_id"]) == 11, "two founders per faction plus one egg per valid seat; invalid office skipped")
	var egg_palettes := {}; var ids := {}; var proper_names := {}
	for row in rows:
		check(not ids.has(row["id"]) and str(row["id"]).begins_with("dragon:5005:"), "globally stable registry UID")
		ids[row["id"]] = true
		var owner := Dynasty.person(Game, row["owner_person_uid"])
		check(owner.get("alive", false) and owner["house_uid"] == row["owner_house_uid"] and owner["household_uid"] == row["owner_household_uid"], "actual native owner/house/household")
		check(row["alive"] and row["rider_person_uid"] == "" and row["history"].size() <= 32, "living identity, empty rider and bounded history")
		if row["stage"] == "egg":
			var mother := Dragons.get_record(Game, row["mother_uid"]); var father := Dragons.get_record(Game, row["father_uid"])
			check(mother.get("stage", "") == "adult" and father.get("stage", "") == "adult" and mother["sex"] == "female" and father["sex"] == "male", "real recorded founding parents")
			check(row["bloodline_uid"] == mother["bloodline_uid"] and row["bloodline_uid"] == father["bloodline_uid"], "parent bloodline references")
			check(row["name"] == str(gems[row["gem_id"]]["name"]) + " Egg", "gem-named egg")
			egg_palettes[row["gem_id"]] = true
		else:
			check(cat["proper_names"].has(row["name"]) and not proper_names.has(row["name"]), "founders have distinct original personal names")
			proper_names[row["name"]] = true
			check(Dragons.type_label(row) == str(gems[row["gem_id"]]["name"]) + " Dragon", "gem type is separate from personal name")
	check(egg_palettes.size() == 4, "distinct deterministic palettes across the four valid towns")
	var saved := snapshot(); Dragons.init_world(Game); Dragons.reconcile(Game)
	check(snapshot() == saved, "initialization and reconciliation idempotent")
	var registry := JSON.stringify(Game.world["dragons"])
	fixture(); Dynasty.select_city(Game, "b"); Dragons.init_world(Game)
	check(JSON.stringify(Game.world["dragons"]) == registry, "identities and palette seeds independent of player selection")
	fixture(); Game.world["factions"]["middle_kingdom"]["capital"] = "invalid"
	Dragons.init_world(Game)
	check(Dragons.records(Game).filter(func(r): return r["stage"] == "adult" and r["estate_town_id"] == "a").size() == 2, "invalid capital falls back to sorted valid native seat")

func reads_and_commands() -> void:
	fixture(); Dragons.init_world(Game); Dynasty.select_city(Game, "a")
	var dragon_uid := holding("a"); var daughter_uid := uid("a", 1); var son_uid := uid("a", 2)
	var foreign_uid := uid("b", 10, 1)
	var before := snapshot(); var rs := Game.rng.state; var next_unit := Unit._next_uid
	var row := Dragons.get_record(Game, dragon_uid); var rows := Dragons.records(Game); var cat := Dragons.catalogs()
	row["name"] = "copy"; rows[0]["history"].append({"kind": "copy"}); cat["gems"][0]["name"] = "copy"
	Dragons.people(Game); Dragons.age_years(Game, row)
	var review := Dragons.transfer_preview(Game, dragon_uid, foreign_uid)
	Dragons.set_custodian_preview(Game, dragon_uid, daughter_uid)
	check(review["ok"] and snapshot() == before and Game.rng.state == rs and Unit._next_uid == next_unit, "deep-copy readers/previews leave native world/RNG/counters untouched")
	for bad in ["", "unknown", uid("a", 0)]:
		check(not Dragons.transfer(Game, dragon_uid, bad)["ok"] and snapshot() == before, "invalid/empty/self recipient rejected without writes")
	check(not Dragons.transfer(Game, "missing", foreign_uid)["ok"] and snapshot() == before, "unknown identity cannot create a record")
	check(not Dragons.set_custodian(Game, dragon_uid, foreign_uid)["ok"] and snapshot() == before, "remote resident cannot be local keeper")
	var girl := Dynasty._person(Game, daughter_uid)
	girl["person"][4] = "army"; var away := snapshot()
	check(not Dragons.set_custodian(Game, dragon_uid, daughter_uid)["ok"] and snapshot() == away, "home-registered army member is physically unavailable")
	girl["person"][4] = ""
	# Native source changes after review must require another review.
	var keeper_review := Dragons.set_custodian_preview(Game, dragon_uid, daughter_uid)
	check(Dragons.set_custodian(Game, dragon_uid, daughter_uid, keeper_review)["ok"], "real co-located keeper appointment")
	var assigned := Dragons.get_record(Game, dragon_uid)
	check(assigned["owner_person_uid"] == uid("a", 0) and assigned["location_town_id"] == "a" and assigned["rider_person_uid"] == "", "keeper order changes only custody/history")
	var stale := snapshot()
	check(not Dragons.transfer(Game, dragon_uid, foreign_uid, review)["ok"] and snapshot() == stale, "reviewed source custody change rejects stale gift")
	var current := Dragons.transfer_preview(Game, dragon_uid, foreign_uid)
	var receiver := Dynasty._person(Game, foreign_uid); receiver["family"]["name"] = "Changed native household"
	stale = snapshot()
	check(not Dragons.transfer(Game, dragon_uid, foreign_uid, current)["ok"] and snapshot() == stale, "changed native recipient rejects stale review")
	receiver["family"]["name"] = "Private Gift House"
	current = Dragons.transfer_preview(Game, dragon_uid, foreign_uid)
	Dynasty.appoint(Game, "a", son_uid); stale = snapshot()
	check(not Dragons.transfer(Game, dragon_uid, foreign_uid, current)["ok"] and snapshot() == stale, "changed living ruler cannot use predecessor authority")
	Dynasty.appoint(Game, "a", uid("a", 0))
	current = Dragons.transfer_preview(Game, dragon_uid, foreign_uid)
	var native := native_snapshot(); var before_record := Dragons.get_record(Game, dragon_uid)
	check(Dragons.transfer(Game, dragon_uid, foreign_uid, current)["ok"], "actual reviewed gift to a non-ruling native person")
	var gifted := Dragons.get_record(Game, dragon_uid)
	check(gifted["owner_person_uid"] == foreign_uid and gifted["owner_house_uid"] == receiver["person"][Persons.HOUSE_UID] and gifted["owner_household_uid"] == receiver["family"]["household_uid"], "gift links actual recipient identity/house/household")
	check(gifted["custodian_person_uid"] == before_record["custodian_person_uid"] and gifted["location_town_id"] == before_record["location_town_id"] and gifted["estate_town_id"] == before_record["estate_town_id"] and gifted["rider_person_uid"] == "", "gift preserves custody/location/estate/rider")
	check(native_snapshot() == native and Game.rng.state == rs and Unit._next_uid == next_unit, "successful commands conserve native people/coin/goods/RNG/counters")
	stale = snapshot()
	check(not Dragons.transfer(Game, dragon_uid, son_uid)["ok"] and snapshot() == stale, "former owner ruler cannot give away gifted property")
	var receiver_child := uid("b", 11, 1); kill(foreign_uid); Dragons.reconcile(Game)
	check(Dragons.get_record(Game, dragon_uid)["owner_person_uid"] == receiver_child and Dynasty.town_office(Game, "a")["person_uid"] != receiver_child, "non-ruler private descendant inherits instead of estate title holder")

func succession_and_custody() -> void:
	fixture(); Dragons.init_world(Game); Dynasty.select_city(Game, "a")
	var egg := holding("a"); var king := uid("a", 0); var son := uid("a", 2); var daughter := uid("a", 1)
	var original := Dragons.get_record(Game, egg)
	kill(king); Dragons.reconcile(Game)
	var inherited := Dragons.get_record(Game, egg)
	check(inherited["owner_person_uid"] == son, "male preference includes younger minor son's branch")
	check(inherited["custodian_person_uid"] == "" and inherited["estate_town_id"] == original["estate_town_id"] and inherited["location_town_id"] == original["location_town_id"], "dead custody clears without moving estate/location")
	var once := snapshot(); Dragons.reconcile(Game)
	check(snapshot() == once, "inheritance and dead custody are reconciled once")
	kill(son)
	# Household founding metadata is not a substitute for the person's retained house.
	var family: Dictionary = Game.world["towns"]["a"]["econ"]["fams"][0]
	family["founding_house_uid"] = Game.world["towns"]["b"]["econ"]["fams"][1]["founding_house_uid"]
	Dragons.reconcile(Game)
	check(Dragons.get_record(Game, egg)["owner_person_uid"] == daughter and Dragons.get_record(Game, egg)["owner_house_uid"] == original["owner_house_uid"], "daughter fallback preserves actual political lineage despite household founding metadata")
	check(Dragons.get_record(Game, egg)["owner_household_uid"] == family["household_uid"], "inherited owner points at actual household")
	kill(daughter); family["gone"] = true; Dynasty.succession_day(Game); Dragons.reconcile(Game)
	var unclaimed := Dragons.get_record(Game, egg)
	check(unclaimed["owner_status"] == "unclaimed" and unclaimed["owner_person_uid"] == daughter and unclaimed["owner_house_uid"] == original["owner_house_uid"] and unclaimed["alive"], "extinct owners remain remembered, property unclaimed, no respawn")
	check(unclaimed["rider_person_uid"] == "" and unclaimed["custodian_person_uid"] == "", "extinction invents neither keeper nor rider")
	once = snapshot(); Dragons.reconcile(Game); Dragons.init_world(Game)
	check(snapshot() == once, "extinction does not repeat history or regenerate records")
	# Elven eldest daughter precedes a younger son; dwarves still prefer a son's line.
	fixture(); Dragons.init_world(Game)
	var elf_egg := holding("c"); var elf_girl := uid("c", 1); kill(uid("c", 0)); Dragons.reconcile(Game)
	check(Dragons.get_record(Game, elf_egg)["owner_person_uid"] == elf_girl, "elven absolute eldest-child asset succession")
	var dwarf_egg := holding("d"); var dwarf_boy := uid("d", 2); kill(uid("d", 0)); Dragons.reconcile(Game)
	check(Dragons.get_record(Game, dwarf_egg)["owner_person_uid"] == dwarf_boy, "dwarven male preference")
	# Custody can become unavailable through service without killing the keeper.
	fixture(); Dragons.init_world(Game); Dynasty.select_city(Game, "a")
	egg = holding("a"); daughter = uid("a", 1)
	Dragons.set_custodian(Game, egg, daughter)
	var girl := Dynasty._person(Game, daughter); girl["person"][4] = "company"
	Dragons.reconcile(Game); once = snapshot(); Dragons.reconcile(Game)
	check(Dragons.get_record(Game, egg)["custodian_person_uid"] == "" and snapshot() == once, "service departure clears custody once without teleport")
	# Alternate only real local people to exercise the bounded actual-order history.
	girl["person"][4] = ""
	var boy := uid("a", 2)
	for i in 40:
		check(Dragons.set_custodian(Game, egg, daughter if i % 2 == 0 else boy)["ok"], "actual local custody order " + str(i))
	check(Dragons.get_record(Game, egg)["history"].size() == 32, "actual native order history capped at 32")

func persistence() -> void:
	fixture(); Dragons.init_world(Game)
	var egg := holding("a"); var record: Dictionary = Game.world["dragons"]["records"][egg]
	# Current saved juvenile records use the same UID as their earlier egg record.
	record["stage"] = "juvenile"; record["name"] = "Cinderwake"; record["birth_day"] = -People.year_days()
	check(Dragons.age_years(Game, record) == 1.0, "juvenile age derives purely from stored birth day")
	Game.day = People.year_days(); var before := snapshot()
	check(Dragons.age_years(Game, record) == 2.0 and snapshot() == before, "calendar age read does not grow or mutate the dragon")
	var saved: Dictionary = Game._serialize(Game.world)
	var registry := JSON.stringify(Game.world["dragons"])
	var physical := Dragons.physical_profile(Game, record)
	var next_unit := Unit._next_uid; var rs := Game.rng.state
	Game.world = Game._deserialize(JSON.parse_string(JSON.stringify(saved)))
	Dragons.after_load(Game)
	check(typeof(Game.world["dragons"]["next_id"]) == TYPE_INT and typeof(Game.world["dragons"]["records"][egg]["appearance_seed"]) == TYPE_INT, "current JSON counters and appearance seed normalized")
	check(JSON.stringify(Game.world["dragons"]) == registry and Dragons.get_record(Game, egg)["stage"] == "juvenile", "current JSON roundtrip preserves identity, stage, parents, owners, palettes and history")
	check(Dragons.physical_profile(Game, Dragons.get_record(Game, egg)) == physical and Dragons.get_record(Game, egg)["name"] == "Cinderwake", "current JSON roundtrip preserves proper name and complete computed physique")
	check(Unit._next_uid == next_unit and Game.rng.state == rs, "load reconciliation creates neither Units nor random draws")
	before = snapshot(); Dragons.after_load(Game); Dragons.init_world(Game)
	check(snapshot() == before, "repeated current load/init retains saved identities")
	Game.world.erase("dragons"); before = snapshot(); Dragons.after_load(Game)
	check(snapshot() == before and not Game.world.has("dragons"), "absent old registry is not regenerated by load")

func physical_profiles() -> void:
	fixture(); Dragons.init_world(Game)
	var before := snapshot(); var rs := Game.rng.state; var next_unit := Unit._next_uid
	var row := Dragons.get_record(Game, holding("a", "adult"))
	row["gem_id"] = "sapphire"; row["morph_id"] = "ironcrest"; row["size_class"] = "small"; row["appearance_seed"] = 73; row["name"] = "Cinderwake"
	row["growth_points"] = 0.0 # The current physical size is authoritative, not its label alone.
	var profile := Dragons.physical_profile(Game, row)
	check(profile["active"] and profile["valid"] and not profile["battle_bound"], "adult resting profile is available, native battle body remains deferred")
	check(Dragons.type_label(row) == "Sapphire Dragon" and row["name"] == "Cinderwake", "proper name and canonical gem type are distinct")
	check(is_equal_approx(profile["bite_force_n"], profile["jaw_torque_nm"] / profile["jaw_out_lever_m"]), "bite force is calculated from explicit jaw torque and lever in SI units")
	var native_torque := Formulas.torque(profile["strength"], profile["body_mass_kg"], 1.0, 0.0, 0.0, 0.0)
	check(is_equal_approx(profile["jaw_torque_nm"], native_torque * profile["jaw_muscle_gain"]), "native strength/mass torque plus independent jaw gain")
	for kind in ["bite", "claw"]:
		var strike: Dictionary = profile["attacks"][kind]; var attack: Dictionary = strike["attack"]
		var native := Formulas.natural_swing("bite", profile["strength"], profile["body_mass_kg"], 0.0, 0.0, attack["p"] / float(Formulas.NATURAL["bite"]["p"]), 0.0, 0.0)
		check(is_equal_approx(strike["p_kg_m_s"], native["p"]) and is_equal_approx(strike["energy_j"], 0.5 * native["p"] * attack["v"]), "native momentum/energy scaling applied once for " + kind)
		var prefix := "tooth" if kind == "bite" else "claw"
		check(is_equal_approx(attack["contact"], profile[prefix + "_contact_cm2"] * 100.0), "explicit authored physical-to-native contact projection " + kind)
		check(is_equal_approx(attack["penetration"] * Formulas.PENETRATION_MM_PER_UNIT, profile[prefix + "_penetration_cm"] * 10.0), "native penetration conversion retains centimetre geometry " + kind)
		check(attack["needs"] == ("head" if kind == "bite" else "foot"), "future attack requires actual head or hind foot, never an invented front leg")
	var changed := row.duplicate(true); changed["name"] = "A New Personal Name"
	check(Dragons.type_label(changed) == "Sapphire Dragon" and Dragons.physical_profile(Game, changed) == profile, "renaming affects neither gem hardness nor appearance/physique")
	changed["gem_id"] = "ruby"
	var ruby := Dragons.physical_profile(Game, changed)
	var ruby_material: Dictionary = ruby["tooth_material"].duplicate(true); ruby_material.erase("name")
	var sapphire_material: Dictionary = profile["tooth_material"].duplicate(true); sapphire_material.erase("name")
	check(ruby["hardness_index"] == profile["hardness_index"] and ruby_material == sapphire_material and ruby["attacks"] == profile["attacks"], "ruby and sapphire share authored hardness without altering attack force")
	var invariant := profile.duplicate(true)
	for key in ["type_label", "hardness_index", "tooth_material", "claw_material"]: invariant.erase(key)
	for gem in Dragons.catalogs()["gems"]:
		changed["gem_id"] = gem["id"]; var candidate := Dragons.physical_profile(Game, changed)
		var material: Dictionary = candidate["tooth_material"]
		check(material["kind"] == "tissue" and material["name"] == str(gem["name"]) + " dragon tooth" and candidate["claw_material"]["name"] == str(gem["name"]) + " dragon claw", "separate native tissue material labels " + str(gem["id"]))
		check(candidate["hardness_index"] >= 0 and candidate["hardness_index"] <= 100 and material["shear_yield"] < material["shear_fracture"] and material["impact_yield"] < material["impact_fracture"], "bounded authored hardness/yield separate from fracture " + str(gem["id"]))
		check(material["shear_fracture"] == 1500000 and material["impact_fracture"] == 4000000 and material["density"] == 2000 and material["max_edge"] == 10000 and material["shear_strain"] == 100 and material["impact_strain"] == 100, "biological toughness/edge/strain independent of gem " + str(gem["id"]))
		for key in ["type_label", "hardness_index", "tooth_material", "claw_material"]: candidate.erase(key)
		check(candidate == invariant, "gem changes only type hardness/material yields " + str(gem["id"]))
	changed = row.duplicate(true); changed["gem_id"] = "diamond"
	var small_hard := Dragons.physical_profile(Game, changed)
	changed["gem_id"] = "pearl"; changed["size_class"] = "colossal"
	changed["growth_points"] = 4.0
	var giant_soft := Dragons.physical_profile(Game, changed)
	check(giant_soft["hardness_index"] < small_hard["hardness_index"] and giant_soft["bite_force_n"] > small_hard["bite_force_n"] and giant_soft["attacks"]["bite"]["energy_j"] > small_hard["attacks"]["bite"]["energy_j"], "size/strength can dominate force and energy despite softer tooth material")
	check(giant_soft["tooth_length_cm"] > small_hard["tooth_length_cm"] and giant_soft["claw_contact_cm2"] > small_hard["claw_contact_cm2"] and giant_soft["claw_penetration_cm"] > small_hard["claw_penetration_cm"], "size independently changes native contact and penetration geometry")
	changed = row.duplicate(true); changed["morph_id"] = "reedrunner"
	var lean := Dragons.physical_profile(Game, changed)
	check(lean["hardness_index"] == profile["hardness_index"] and lean["strength"] != profile["strength"] and lean["tooth_length_cm"] != profile["tooth_length_cm"] and lean["bite_force_n"] != profile["bite_force_n"], "body build changes muscle/jaw/geometry independently of gem")
	var steel: Dictionary = DB.materials["steel"]
	var contact: float = profile["attacks"]["bite"]["attack"]["contact"]
	var resistance := Formulas.edge_resistance(steel, profile["tooth_material"], contact, 10.0, 10.0, 2.0, true)
	check(resistance > 0 and Formulas.edge_resistance(steel, profile["tooth_material"], contact, 10.0, 10.0, 4.0, true) > resistance, "same native steel gets more resistance from thicker armour")
	check(Formulas.edge_resistance(steel, profile["tooth_material"], contact * 2.0, 10.0, 10.0, 2.0, true) > resistance, "same native steel/contact formula consumes projected tooth footprint")
	changed = row.duplicate(true); changed["gem_id"] = "pearl"
	var soft := Dragons.physical_profile(Game, changed)
	check(Formulas.edge_resistance(steel, soft["tooth_material"], contact, 10.0, 10.0, 2.0, true) > resistance, "native layer formula consumes gem yield independently of fixed toughness")
	# No assertion that all steel holds or all steel fails: native battle layers decide.
	var egg := Dragons.get_record(Game, holding("a")); var egg_profile := Dragons.physical_profile(Game, egg)
	check(not egg_profile["active"] and not egg_profile.has("body_mass_kg") and not egg_profile.has("bite_force_n") and not egg_profile.has("attacks") and not egg_profile.has("tooth_length_cm"), "eggs expose no active mass, force, attacks or dimensions")
	check(Dragons.type_label(egg) == egg["name"], "egg label retains canonical gem naming")
	for field in ["gem_id", "morph_id", "size_class", "stage"]:
		changed = row.duplicate(true); changed[field] = "unknown"
		var invalid := Dragons.physical_profile(Game, changed)
		check(not invalid["active"] and not invalid["valid"] and not invalid.has("tooth_material") and not invalid.has("body_mass_kg"), "unknown authoritative catalog field fails closed " + field)
	changed = row.duplicate(true); changed["alive"] = false
	check(not Dragons.physical_profile(Game, changed)["active"], "dead identity has no active attack profile")
	profile["tooth_material"]["shear_yield"] = -1; profile["attacks"]["bite"]["attack"]["p"] = -1
	check(Dragons.physical_profile(Game, row)["tooth_material"]["shear_yield"] == 800000 and snapshot() == before and Game.rng.state == rs and Unit._next_uid == next_unit, "all physical/type readers and native formula probes are pure deep copies")
	# Force collisions deliberately: identical naming seed still yields 14 unique
	# founding-style proper names, enough for the seven-faction Normal world.
	var owner := Dragons._person(Game, uid("a", 0)); var names := {}
	for i in 14:
		var adult := Dragons._make(Game, "adult", "a", owner, "collision", i, "female")
		check(not names.has(adult["name"]), "deterministic proper-name collision resolution " + str(i))
		names[adult["name"]] = true

func run(_tree: SceneTree) -> int:
	var original_world: Dictionary = Game.world; var original_company: Array = Game.company; var original_squads: Dictionary = Game.squads
	var original_day: float = Game.day; var original_gold: float = Game.gold; var original_location: String = Game.location
	catalog_and_generation(); reads_and_commands(); succession_and_custody(); persistence(); physical_profiles()
	Game.world = original_world; Game.company = original_company; Game.squads = original_squads
	Game.day = original_day; Game.gold = original_gold; Game.location = original_location
	print("dragon identities: %d checks, %d failures" % [checks, fails])
	return fails
