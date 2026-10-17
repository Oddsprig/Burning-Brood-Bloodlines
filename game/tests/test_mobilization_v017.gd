extends RefCounted
## Actual small native economies and residents. No map generation or whole battle.
const NativeFixture = preload("res://tests/test_dynasty_foundation.gd")
const HealthUtil = preload("res://tests/health_util.gd")
const PersonFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL mobilization: ", text)

## Shared with the owned UI test. Supplying120 actual weapons intentionally
## limits a requested200-person muster despite ample actual native manpower.
func fixture(_game = Game) -> Dictionary:
	NativeFixture.new().fixture()
	Game.rng.seed = 17017; Game.gold = 0; Game.contract = {}; Food.init_company(Game, 0.0)
	Feudal.prepare_world(Game)
	Dynasty.select_city(Game, "city_a")
	var town: Dictionary = Game.world["towns"]["city_a"]
	Game.location = "city_a"; Game.world["party"]["pos"] = town["pos"]
	var e: Dictionary = town["econ"]
	var payer: Dictionary = Feudal._payer(Game); payer["purse"] = 2000000.0
	var f: Dictionary = Families._blank(e["fams"].size())
	f["name"] = "Mobilization workforce"; f["m"] = 400; f["homes"] = 200; f["households"] = 200; f["purse"] = 10000.0; f["cul"] = e["culture"]
	Families.identity(e, f); Population.initialize(e, f); e["fams"].append(f)
	e["pop"] += 400; e["adults"] += 400; e["homes"] += 200
	Families.reassign(e, f)
	e["stock"]["grain"] = 100000; e["stock"]["fruit"] = 20000; e["stock"]["meat"] = 10000
	e["price"]["grain"] = 2.0; e["price"]["fruit"] = 3.0; e["price"]["meat"] = 4.0
	town["shop"] = []; town["armory_items"] = []
	for i in 120:
		var it: Item = Item.make("arming_sword", "copper", 1)
		if i < 10: town["armory_items"].append(it)
		else: town["shop"].append(it)
	# Actual native public guards/reserve are not private field candidates.
	var rng := RandomNumberGenerator.new(); rng.seed = 1733
	var public_units: Array = []
	for role in ["guard", "reserve"]:
		var p: Array = Population.promote(e, f, 0.0, rng, true)
		var u: Unit = Unit.create("human", "middle_kingdom", false)
		Persons.bind(e, f, p, u, role, 0.0); u.home_town = "city_a"
		f["serve"]["guard" if role == "guard" else "militia"] = 1
		public_units.append(u)
	Game.world["warbands"]["public"] = {"id": "public", "kind": "militia", "faction": "middle_kingdom", "home": "city_a", "units": public_units,
		"mustered": false, "drill_today": false, "pos": town["pos"]}
	Families.reassign(e, f)
	return {"town": town, "econ": e, "pool": f, "payer": payer, "public_units": public_units}

func coins() -> float:
	var total := float(Game.gold)
	for town in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		total += float(e["treasury"]) + float(e.get("farm_till", 0.0))
		for f in e["fams"]: total += float(f["purse"])
		for b in e["biz"]: total += float(b.get("till", 0.0))
	for fac in Game.world["factions"].values(): total += float(fac.get("treasury", 0.0))
	for band in Game.world["warbands"].values(): total += float(band.get("gold", 0.0))
	return total

func population() -> int:
	var total := 0
	for town in Game.world["towns"].values(): total += int(town["econ"]["pop"])
	for u in Game.company:
		if not u.dead: total += 1
	return total

func items() -> Dictionary:
	var out := {}
	for town in Game.world["towns"].values():
		for it in town.get("shop", []) + town.get("armory_items", []):
			out[it.get_instance_id()] = int(out.get(it.get_instance_id(), 0)) + 1
	var units: Array = Game.company + Mobilization.reserves(Game)
	for wb in Game.world["warbands"].values(): units.append_array(wb.get("units", []))
	for u in units:
		for it in u.equip.values(): out[it.get_instance_id()] = int(out.get(it.get_instance_id(), 0)) + 1
	for it in Game.stash: out[it.get_instance_id()] = int(out.get(it.get_instance_id(), 0)) + 1
	for row in Mobilization.estate_items(Game):
		var it: Item = row["item"]
		out[it.get_instance_id()] = int(out.get(it.get_instance_id(), 0)) + 1
	return out

func state() -> String:
	return JSON.stringify(Game._save_tree())

func native_commands() -> void:
	var fxt: Dictionary = fixture()
	var town: Dictionary = fxt["town"]; var e: Dictionary = fxt["econ"]
	var all_coin := coins(); var all_pop := population(); var all_items: Dictionary = items()
	check(Game.company.is_empty() and Game.gold == 0 and Food.stock(Game, "meal") == 0 and Game.daily_wages() == 0, "house selection starts with no army, minted wallet, provisions or payroll")
	check(not Game.is_game_over(), "living unraised house is not defeated")
	var before := state(); var rng_before := Game.rng.state; var units_before := Unit._next_uid; var items_before := Item._next_uid
	var unfunded: Dictionary = Mobilization.quote(Game, "city_a", 200)
	Mobilization.status(Game); Mobilization.stand_down_quote(Game, "city_a")
	check(not unfunded["ok"] and int(unfunded["required_funding"]) > 0, "unfunded actual manpower cannot become a free company")
	check(state() == before and Game.rng.state == rng_before and Unit._next_uid == units_before and Item._next_uid == items_before, "preview and cancelled review preserve native state, rolls and both UID counters")
	check(Mobilization.fund(Game, 1000000.0)["ok"] and absf(coins() - all_coin) < 0.000001, "explicit private funding conserves all real owner accounts")
	check(not Mobilization.fund(Game, 0.5)["ok"], "fractional funding cannot truncate private coin into the integer wallet")
	var q: Dictionary = Mobilization.quote(Game, "city_a", 200)
	check(q["ok"] and int(q["available"]) == 120 and int(q["eligible"]) >= 200, "actual120 weapons limit200 requested despite sufficient conserved native people")
	Game.world["work"] = [{"kind": "pending native job"}]
	check(not Mobilization.quote(Game, "city_a", 200)["ok"], "pending native settlement jobs block premature recruitment")
	Game.world["work"] = []
	before = state(); rng_before = Game.rng.state; units_before = Unit._next_uid
	for i in 3: Mobilization.quote(Game, "city_a", 200)
	check(before == state() and rng_before == Game.rng.state and units_before == Unit._next_uid and Item._next_uid == items_before, "funded repeated read is pure and never materializes cohort slots")
	Game.gold -= 1
	var changed := state()
	check(not Mobilization.muster(Game, "city_a", 200, q["review"])["ok"] and state() == changed, "stale wallet review rejects before native population, gear or food mutation")
	Game.gold += 1
	q = Mobilization.quote(Game, "city_a", 200)
	var old_ruler := str(Game.world["player_house"]["ruler_uid"])
	Game.world["player_house"]["ruler_uid"] = old_ruler + ":stale"
	changed = state()
	check(not Mobilization.muster(Game, "city_a", 200, q["review"])["ok"] and changed == state(), "changed ruler cannot reuse a reviewed enlistment under another office")
	Game.world["player_house"]["ruler_uid"] = old_ruler
	q = Mobilization.quote(Game, "city_a", 200)
	var home_pop := int(e["pop"]); var grain := int(e["stock"]["grain"]); var food_before := Food.stock(Game, "meal")
	var treasury := float(e["treasury"]); var market := float(e["biz"][int(e["mkt"])]["till"]); var wallet := int(Game.gold)
	var public_state := JSON.stringify(fxt["public_units"].map(func(u): return u.to_dict()))
	var raised: Dictionary = Mobilization.muster(Game, "city_a", 200, q["review"])
	check(raised["ok"] and raised["partial"] and int(raised["raised"]) == 120, "muster reports actual partial acceptance without fictional120 new population")
	check(population() == all_pop and int(e["pop"]) == home_pop - 120, "native company AWAY conversion preserves total people exactly")
	check(items() == all_items and Item._next_uid == items_before, "all actual armory/market Items move once without factory-created equipment")
	check(absf(coins() - all_coin) < 0.000001 and float(e["treasury"]) == treasury, "bounties and actual purchases preserve private/public/all-owner coin")
	check(wallet - int(Game.gold) == int(raised["cost"]) and int(raised["cost"]) == int(q["raise_cost"]) and float(e["biz"][int(e["mkt"])]["till"]) > market, "actual quote bill debits army wallet and credits real recipients")
	check(Food.stock(Game, "meal") - food_before == 720 and grain - int(e["stock"]["grain"]) == 720 and int(raised["food_units"]) == 720, "six paid native meals per actual departing person are counted once")
	check(public_state == JSON.stringify(fxt["public_units"].map(func(u): return u.to_dict())), "existing guards/public militia retain exact bodies, kit and duty")
	check(Game.squads.size() == 5 and Game.company.filter(func(u): return u.is_officer()).size() == 5, "120 actual people include five enlisted officers with native rally squad links")
	var first_leader: Unit = Game.company.filter(func(x): return x.is_officer())[0]
	Game.squads[first_leader.uid] = {"uniform": {"head": "nasal_helm"}, "material": "bronze"}
	Mobilization.command_plan(Game)
	check(Game.squads[first_leader.uid]["material"] == "bronze" and Game.squads[first_leader.uid]["uniform"] == {"head": "nasal_helm"}, "command refresh preserves actual retained leader uniform/material settings")
	for u in Game.company:
		check(u.is_officer() or Game.squads.has(u.squad), "each enlisted fighter has a real living native officer")
	var u: Unit = Game.company[0]; var original_uid := u.uid
	var address: Dictionary = Mobilization._address(Game, u); var person_uid := str(address["person"][Persons.PERSON_UID])
	HealthUtil.wound(u, "head", "skin", "bruised", 0.1)
	var body := JSON.stringify(u.body.to_dict()); var skill := u.skills.duplicate(true); var look := u.look.duplicate(true)
	Game.location = "city_b"; Game.world["party"]["pos"] = Game.world["towns"]["city_b"]["pos"]
	before = state()
	check(not Mobilization.stand_down(Game, "city_a")["ok"] and state() == before, "remote records cannot teleport people or their borrowed gear home")
	Game.location = "city_a"; Game.world["party"]["pos"] = town["pos"]
	var down: Dictionary = Mobilization.stand_down_quote(Game, "city_a")
	var loan_holder: Unit = Game.company.filter(func(x): return not Mobilization._entry(Game, x, Mobilization._address(Game, x))["borrowed"].is_empty())[0]
	var stored_loan: Item = loan_holder.equip["main_hand"]
	loan_holder.equip.erase("main_hand"); Game.stash.append(stored_loan)
	# Home return owns no market purchase. Even a closed/removed market must not
	# strand legitimate living people or redirect their property into city funds.
	var market_index := int(e["mkt"]); e["mkt"] = -1
	var result: Dictionary = Mobilization.stand_down(Game, "city_a", down["review"])
	e["mkt"] = market_index
	check(result["ok"] and int(result["returned"]) == 120 and Game.company.is_empty() and Mobilization.reserves(Game).size() == 120, "proper home stand-down retains120 unique actual bodies outside field service")
	check(population() == all_pop and int(e["pop"]) == home_pop and Game.daily_wages() == 0 and absf(coins() - all_coin) < 0.000001, "home residents return once and field payroll stops without a refund mint")
	check(items() == all_items and town["armory_items"].size() == 10, "borrowed Items return exact native armory while privately bought gear stays owned")
	check(not Game.stash.has(stored_loan) and town["armory_items"].has(stored_loan), "loan moved through the native company stash still returns to its real armory owner")
	check(Mobilization.reserve_unit(Game, original_uid) == u and JSON.stringify(u.body.to_dict()) == body and u.skills == skill and u.look == look, "reserve retains exact instance, original wound, skills and look")
	check(Persons.live_uids(Game).has(original_uid) and ServiceIdentity.inventory(Game)[original_uid] == [u], "native sweep/inventory sees one real retained Unit and cannot declare it missing")
	check(str(address["person"][4]) == "reserve" and int(address["person"][5]) == original_uid and str(address["person"][Persons.PERSON_UID]) == person_uid, "person/house/UID registry survives home return")
	var reserve_enlisted: Dictionary = Game.world["mobilization"]["enlisted"]
	var actual_record: Dictionary = reserve_enlisted[person_uid].duplicate(true)
	Persons.forget(e, address["family"], address["person"])
	check(reserve_enlisted.has(person_uid) and reserve_enlisted[person_uid] == actual_record,
		"native remember/forget false does not retire a proven living actual home reserve enlistment")
	Dynasty.record_person(e, address["family"], address["person"], true)
	var age_before := u.age
	Game.day += People.year_days(); People.tick_ages(Game, int(Game.day))
	check(u.age == Persons.age_of(address["person"], Game.day) and u.age > age_before, "native reserve age update reaches the same visible physical Unit")
	Game.day -= People.year_days(); People.tick_ages(Game, int(Game.day))
	before = state()
	check(not Mobilization.stand_down(Game, "city_a")["ok"] and before == state(), "replayed stand-down cannot add a second resident or free an unrelated relative")
	q = Mobilization.quote(Game, "city_a", 120); units_before = Unit._next_uid; items_before = Item._next_uid
	result = Mobilization.muster(Game, "city_a", 120, q["review"])
	check(result["ok"] and int(result["raised"]) == 120 and Unit._next_uid == units_before and Item._next_uid == items_before, "re-raise reuses all actual retained people and Items without Factory rerolls")
	check(Game.company.has(u) and u.uid == original_uid and JSON.stringify(u.body.to_dict()) == body and u.skills == skill, "re-raised fighter retains exact body injuries and skills")
	Dynasty.record_person(e, address["family"], address["person"], false)
	check(Game.world["mobilization"]["enlisted"].has(person_uid), "native false memory record preserves a proven living actual field company holder")
	Dynasty.record_person(e, address["family"], address["person"], true)
	check(population() == all_pop and items() == all_items and absf(coins() - all_coin) < 0.000001, "second deployment preserves people, physical gear and all owners' coin")
	# Real native casualty: company was already AWAY, so death must not subtract
	# another home resident. Its native battlefield gear remains separately owned.
	u.dead = true; People.casualty(Game, u, "dead", "company"); Game.company.erase(u)
	var dead_pop := population(); var death_count: int = Census._book(e)["death_ids"].size()
	People.casualty(Game, u, "dead", "company")
	check(dead_pop == all_pop - 1 and population() == dead_pop and Census._book(e)["death_ids"].size() == death_count, "actual death is counted once with no duplicate resident subtraction")
	result = Mobilization.stand_down(Game, "city_a")
	check(int(result.get("returned", 0)) == 119 and not Mobilization.reserves(Game).has(u) and population() == all_pop - 1, "dead fighter cannot return or reappear as a living reserve")
	var survivor: Unit = Mobilization.reserves(Game).filter(func(x): return not x.equip.is_empty())[0]
	var resident_pop := int(e["pop"])
	var survivor_family: Dictionary = Mobilization._address(Game, survivor)["family"]
	var before_home_death: Dictionary = items(); var dead_equipment := survivor.equip.size(); var home_coin := coins()
	survivor.dead = true; People.casualty(Game, survivor, "dead", "reserve")
	check(int(e["pop"]) == resident_pop - 1 and not Mobilization.reserves(Game).has(survivor) and not survivor_family["player_reserve_uids"].has(str(survivor.uid)), "home reserve death removes holder/marker and exactly one native resident")
	check(items() == before_home_death and absf(coins() - home_coin) < 0.000001 and Mobilization.estate_items(Game).size() == dead_equipment,
		"home death conserves surviving actual private equipment in the deceased household estate, without public gifting or sale")
	var round_trip: Dictionary = Game._deserialize(JSON.parse_string(JSON.stringify(Game._save_tree())))
	check(round_trip["world"]["mobilization"]["reserve"].size() == 118 and round_trip["world"]["mobilization"]["reserve"][0] is Unit, "current save schema restores actual retained native Units")
	print("mobilization native conservation case complete")

func negotiated_native_hires() -> void:
	var fxt: Dictionary = fixture(); var town: Dictionary = fxt["town"]; var e: Dictionary = fxt["econ"]; var f: Dictionary = fxt["pool"]
	var local := RandomNumberGenerator.new(); local.seed = 1789
	for i in 2:
		var p: Array = Population.promote(e, f, 0.0, local, true)
		var u: Unit = Unit.create("human", "middle_kingdom")
		u.hire_cost = 500; u.wage = 70; u.skills["negotiator"] = 15 if i == 0 else 0
		Persons.bind(e, f, p, u, "hire", 0.0); u.home_town = "city_a"
		u.equip["main_hand"] = town["shop"].pop_back() # existing actual private recruiting kit, not a new Item
		town["recruits"].append(u)
	Mobilization.fund(Game, 1000000.0)
	var before := coins(); var pop := population(); var equipment: Dictionary = items()
	# Include existing hiring pool private gear in this independent inventory book.
	for recruit in town["recruits"]:
		for it in recruit.equip.values(): equipment[it.get_instance_id()] = 1
	var wallet := int(Game.gold); var q: Dictionary = Mobilization.quote(Game, "city_a", 2)
	var result: Dictionary = Mobilization.muster(Game, "city_a", 2, q["review"])
	check(result["ok"] and int(result["raised"]) == 2 and int(result["cost"]) == wallet - int(Game.gold) and int(result["cost"]) < int(q["raise_cost"]),
		"native improved negotiation charges and receipts actual hire payment beneath the reviewed ceiling")
	check(population() == pop and absf(coins() - before) < 0.000001 and items() == equipment, "existing native recruits conserve their exact people/private kit/hiring recipients")
	wallet = int(Game.gold); Game.gold = 500
	q = Mobilization.quote(Game, "city_a", 1)
	check(not q["ok"] and int(q["required_funding"]) > 0, "additional raising protects three days of TOTAL existing plus additional native payroll")
	Game.gold = wallet
	var victim: Unit = Game.company[1]; var a: Dictionary = Mobilization._address(Game, victim)
	var all_gear: Dictionary = items(); var dead_person := str(a["person"][Persons.PERSON_UID]); var estate_count := Mobilization.estate_items(Game).size()
	# Actual native natural-death path: sickness owns one person/census removal;
	# explicit settlement preserves private equipment before Unit erasure.
	Sickness._kill(Game, town, a["family"], a["person"], Game.day, "starved", "")
	check(not Game.company.has(victim) and Mobilization.estate_items(Game).size() == estate_count + 1 and items() == all_gear,
		"actual natural company death preserves exact private Item instead of dropping its owner")
	check(Mobilization.estate_items(Game)[-1]["person_uid"] == dead_person and absf(coins() - before) < 0.000001 and population() == pop - 1,
		"natural death receipt names actual deceased owner and counts death once without invented coin")
	var fighter: Unit = Game.company[0]; var loot: Item = fighter.equip["main_hand"]
	fighter.equip.clear(); Game.stash.append(loot) # actual native loot was already assigned to company stash
	estate_count = Mobilization.estate_items(Game).size(); fighter.dead = true
	People.casualty(Game, fighter, "dead", "company"); Game.company.erase(fighter)
	check(Mobilization.estate_items(Game).size() == estate_count and Game.stash.has(loot), "ordinary battlefield casualty cannot duplicate already-owned native loot into an estate")
	print("mobilization negotiated-hire/natural-death case complete")

func away_house(town: Dictionary) -> Dictionary:
	var e: Dictionary = town["econ"]
	var f: Dictionary = Families._blank(e["fams"].size())
	f["name"] = "Actual away household " + str(f["id"]); f["homes"] = 1; f["households"] = 1; f["purse"] = 500.0
	Families.identity(e, f); Population.initialize(e, f); e["fams"].append(f); e["homes"] += 1
	var p: Array = PersonFixture.new().person(e, f, int(e["next_pid"]), 0, 25, "Actual absent person " + str(f["id"]))
	f["pp"].append(p)
	var u: Unit = Unit.create("human", "player")
	Persons.bind(e, f, p, u, "company", Game.day); u.home_town = str(town["id"])
	Game.company.append(u); Mobilization.register_company(Game, u)
	return {"econ": e, "family": f, "person": p, "unit": u}

func empty_home_survivors() -> void:
	var fxt: Dictionary = fixture(); var town: Dictionary = fxt["town"]
	var a: Dictionary = away_house(town); var e: Dictionary = a["econ"]; var f: Dictionary = a["family"]; var u: Unit = a["unit"]
	var before := state()
	check(Families.people(f) == 0 and Families.living_company_member(e, f), "zero home population still has its actual living bound company member")
	Families.extinct(e, f, Game.day)
	check(state() == before and not f["gone"], "native extinction does not liquidate living away household property or coin")
	Population.turn(e, f, Game.day, 0.0)
	check(not f["gone"] and float(f["purse"]) == 500.0, "native cohort extinction caller also preserves actual away survivors")
	var local := RandomNumberGenerator.new(); local.seed = 1790
	Families.turn(Game, town, e, f, Game.day + 7.0, local)
	check(not f["gone"] and Families.living_company_member(e, f), "native weekly family turn keeps a real absent survivor active")
	var bound_uid := int(a["person"][5]); a["person"][5] = -1
	check(not Families.living_company_member(e, f), "company state alone without actual bound UID cannot prevent genuine extinction")
	a["person"][5] = bound_uid
	check(not Families.living_company_member(e.duplicate(true), f), "historical/copied economy is not the Unit's actual current native home address")
	# Reproduce an earlier strike-off when a physical member was not visible:
	# restoration must reactivate only the real row, never reclaim its old assets.
	Game.company.erase(u); var purse := float(f["purse"]); var home_estate := int(e["fams"][0]["homes"])
	var realm: Dictionary = Game.world["factions"][town["faction"]]; var realm_coin := float(realm["treasury"])
	Families.extinct(e, f, Game.day)
	check(f["gone"] and f.get("extinct", false) and float(f["purse"]) == 0.0 and float(realm["treasury"]) == realm_coin + purse,
		"truly unbound zero-home household still follows native property/cash liquidation")
	Game.company.append(u); var all_coin := coins(); var all_pop := population()
	check(Mobilization.return_home(Game, u) and not f["gone"] and not f.get("extinct", false), "actual return safely reactivates an already struck-off native family")
	check(float(f["purse"]) == 0.0 and int(f["homes"]) == 0 and int(e["fams"][0]["homes"]) == home_estate + 1 and float(realm["treasury"]) == realm_coin + purse,
		"reactivation does not reclaim previously inherited homes or transferred coin")
	check(population() == all_pop and absf(coins() - all_coin) < 0.000001 and int(f["m"]) == 1 and str(a["person"][4]) == "reserve",
		"reactivated actual survivor returns once with native population/account conservation")
	var dead: Dictionary = away_house(town); var dead_unit: Unit = dead["unit"]; dead_unit.dead = true
	check(not Families.living_company_member(e, dead["family"]), "dead physical Unit cannot keep a household falsely alive")
	Families.extinct(e, dead["family"], Game.day)
	check(dead["family"]["gone"] and dead["family"].get("extinct", false), "genuinely dead last-away member still permits native extinction")
	var survivor: Dictionary = away_house(town); var survivor_family: Dictionary = survivor["family"]
	var fallen_person: Array = PersonFixture.new().person(e, survivor_family, int(e["next_pid"]), 0, 26, "Actual fallen relative")
	survivor_family["pp"].append(fallen_person)
	var fallen: Unit = Unit.create("human", "player")
	Persons.bind(e, survivor_family, fallen_person, fallen, "company", Game.day); fallen.home_town = str(town["id"])
	Game.company.append(fallen); Mobilization.register_company(Game, fallen); fallen.dead = true
	var family_coin := float(survivor_family["purse"]); realm_coin = float(realm["treasury"]); all_coin = coins()
	var carried := Families.take_carried_coin(fallen, 0.1, 0.5, 1000); Game.gold += carried
	check(carried == int(family_coin * 0.1) and float(survivor_family["purse"]) == family_coin - carried and float(realm["treasury"]) == realm_coin,
		"real surviving away relative preserves ordinary fallen carry share without liquidating the household purse")
	check(absf(coins() - all_coin) < 0.000001, "actual dead-person carry transfer into native army wallet conserves every owner's coin")
	People.casualty(Game, fallen, "dead", "company"); Game.company.erase(fallen)
	var last_unit: Unit = survivor["unit"]; last_unit.dead = true
	family_coin = float(survivor_family["purse"]); all_coin = coins(); realm_coin = float(realm["treasury"])
	carried = Families.take_carried_coin(last_unit, 0.1, 0.5, 1000); Game.gold += carried
	check(carried == int(family_coin * 0.5) and float(survivor_family["purse"]) == 0.0 and float(realm["treasury"]) == realm_coin + family_coin - carried,
		"genuinely dead last-away member retains native final-household carry and realm remainder")
	check(absf(coins() - all_coin) < 0.000001, "native last-household loot share and realm remainder preserve all-owner coin")
	People.casualty(Game, last_unit, "dead", "company"); Game.company.erase(last_unit)
	var enlisted: Dictionary = Game.world["mobilization"]["enlisted"]
	check(not enlisted.has(str(fallen_person[Persons.PERSON_UID])) and not enlisted.has(str(survivor["person"][Persons.PERSON_UID])),
		"actual final deaths retire enlisted IDs without retained dead Unit/body or Item references")
	var vanished: Dictionary = away_house(town); var missing: Unit = vanished["unit"]
	var missing_uid := str(vanished["person"][Persons.PERSON_UID]); Game.company.erase(missing)
	Persons.sweep_town(Game, town, Persons.live_uids(Game))
	check(Persons.by_uid(vanished["family"], missing.uid).is_empty() and not enlisted.has(missing_uid),
		"actual native missing-unit death sweep retires the exact enlisted ID even without a physical casualty callback")
	print("mobilization empty-home survivor case complete")

func run(_tree: SceneTree) -> int:
	var original: Dictionary = Game._save_tree(); var original_ready: bool = Game._save_ready
	var original_company: Array = Game.company.duplicate(); var original_stash: Array = Game.stash.duplicate()
	var original_world: Dictionary = Game.world.duplicate(true); var original_squads: Dictionary = Game.squads.duplicate(true)
	var original_rng := Game.rng.state; var original_unit := Unit._next_uid; var original_item := Item._next_uid
	# Real startup boundary; stop before the returned generation jobs are run.
	Game.new_game_begin(17017)
	check(Game.company.is_empty() and Game.gold == 0 and Food.stock(Game, "meal") == 0, "real new_game_begin has no inherited minted company/wallet/food")
	native_commands(); negotiated_native_hires(); empty_home_survivors()
	# Restore through the native detached schema rather than sharing mutated arrays.
	Game.company = original_company; Game.stash = original_stash; Game.squads = original_squads
	Game.world = original_world; Game.day = float(original["day"]); Game.gold = int(original["gold"])
	Game.location = str(original.get("location", "")); Game.contract = original.get("contract", {})
	Game.seed_value = int(original["seed"]); Game.rep = original["rep"]
	Game.provisions = Food.stock_from_save(original.get("provisions", {})); Game.rations = original.get("rations", {}); Game.food_clock = original.get("food_clock", {})
	Game._save_ready = original_ready; Game.rng.state = original_rng; Unit._next_uid = original_unit; Item._next_uid = original_item
	Game.invalidate_deploy()
	print("mobilization v017: %d checks, %d failures" % [checks, fails])
	return fails
