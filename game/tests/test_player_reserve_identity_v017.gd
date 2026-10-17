extends RefCounted
## Small native-register/physical-holder adapter fixtures, not troop-allocation receipts.
## Mobilization's separate tests prove recruitment/payment/stock commands.
const Fixture := preload("res://tests/test_dynasty_foundation.gd")
const U := preload("res://tests/sim_util.gd")
var checks: int = 0
var fails: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL player reserve identity: ", why)

func native_sha() -> String:
	return JSON.stringify(Game._save_tree(), "", true, true).sha256_text()

func native_json_equal(source: Variant, loaded: Variant) -> bool:
	# Native JSON changes int/float container tags. Values must still be EXACT;
	# boolean/string types, dictionary keys and array order remain strict.
	if typeof(source) in [TYPE_INT, TYPE_FLOAT] and typeof(loaded) in [TYPE_INT, TYPE_FLOAT]:
		return is_finite(float(source)) and is_finite(float(loaded)) and source == loaded
	if typeof(source) != typeof(loaded): return false
	if source is Dictionary:
		if source.size() != loaded.size(): return false
		for key: Variant in source:
			if not loaded.has(key) or not native_json_equal(source[key], loaded[key]): return false
		return true
	if source is Array:
		if source.size() != loaded.size(): return false
		for i: int in source.size():
			if not native_json_equal(source[i], loaded[i]): return false
		return true
	return source == loaded

func json_diff(source: Variant, loaded: Variant, path: String, stats: Dictionary) -> void:
	if int(stats["visited"]) >= 4096: return
	stats["visited"] = int(stats["visited"]) + 1
	if source is Dictionary and loaded is Dictionary:
		var keys: Array = source.keys()
		for key: Variant in loaded:
			if not keys.has(key): keys.append(key)
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for key: Variant in keys:
			if not source.has(key) or not loaded.has(key):
				if stats["values"].size() < 16: stats["values"].append(path + "." + str(key) + " missing on " + ("source" if not source.has(key) else "loaded"))
			else: json_diff(source[key], loaded[key], path + "." + str(key), stats)
	elif source is Array and loaded is Array:
		if source.size() != loaded.size() and stats["values"].size() < 16:
			stats["values"].append(path + " array length %d -> %d" % [source.size(), loaded.size()])
		for i: int in mini(source.size(), loaded.size()): json_diff(source[i], loaded[i], path + "[%d]" % i, stats)
	else:
		var numeric: bool = typeof(source) in [TYPE_INT, TYPE_FLOAT] and typeof(loaded) in [TYPE_INT, TYPE_FLOAT]
		if numeric and typeof(source) != typeof(loaded): stats["numeric_types"] = int(stats["numeric_types"]) + 1
		if source != loaded and stats["values"].size() < 16:
			stats["values"].append("%s: source(%s)=%s loaded(%s)=%s" % [path, type_string(typeof(source)),
				JSON.stringify(source, "", true, true), type_string(typeof(loaded)), JSON.stringify(loaded, "", true, true)])

func item_owners(value: Variant, counts: Dictionary) -> void:
	if value is Item:
		counts[value.uid] = int(counts.get(value.uid, 0)) + 1
	elif value is Unit:
		item_owners(value.equip, counts)
	elif value is Dictionary:
		for child: Variant in value.values(): item_owners(child, counts)
	elif value is Array:
		for child: Variant in value: item_owners(child, counts)

func owned_items() -> Dictionary:
	var counts: Dictionary = {}
	item_owners(Game.world, counts); item_owners(Game.company, counts); item_owners(Game.stash, counts)
	return counts

func hold(town: Dictionary) -> Array:
	var e: Dictionary = town["econ"]
	for f: Dictionary in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		for p: Array in Persons.pp(f):
			if String(p[4]) != "" or int(p[5]) >= 0 or int(p[6]) != 0: continue
			var u: Unit = U.soldier("copper")
			Persons.bind(e, f, p, u, "reserve", Game.day)
			u.home_town = String(town["id"]); u.faction = "player"
			Food.roll_fav_drink(u, hash([u.uid, u.name])) # complete native current-record clone identity
			var person_uid: String = str(Persons.g(p, Persons.PERSON_UID, ""))
			var book: Dictionary = Game.world["mobilization"]
			(book["reserve"] as Array).append(u)
			book["enlisted"][person_uid] = {"person_uid": person_uid, "unit_uid": u.uid,
				"home_town_id": u.home_town, "family_id": u.family,
				"household_uid": str(f.get("household_uid", "")), "wage": u.wage, "borrowed": []}
			if not f.has("player_reserve_uids"): f["player_reserve_uids"] = {}
			f["player_reserve_uids"][str(u.uid)] = true
			return [u, f, p]
	return []

func presence_checks(town: Dictionary, row: Array) -> void:
	var u: Unit = row[0]; var f: Dictionary = row[1]; var p: Array = row[2]
	u.skills["sword"] = 8
	u.look["seed"] = 8675309
	u.body.wound_part("arm_upper_r")["layers"][2]["dmg"] = 0.6
	u.body.parts["arm_upper_r"]["layers"][2]["kind"] = "cut"
	u.body.wound_part("foot_l")["severed"] = true
	u.body.permanent.append("Lost left foot")
	u.body.blood = u.body.blood_max * 0.76
	var native: Dictionary = u.to_dict().duplicate(true)
	var before: String = native_sha()
	var rng_before: int = Game.rng.state
	var next_u: int = Unit._next_uid; var next_i: int = Item._next_uid
	check(Mobilization.reserves(Game).has(u), "actual saved private reserve remains outside public/company forces")
	check(Mobilization.reserve_unit(Game, u.uid, u.home_town, u.family) == u, "exact home/family resolves same physical Unit")
	check(Mobilization.reserve_unit(Game, u.uid, "city_b", u.family) == null, "wrong home cannot resolve privately held Unit")
	check(Persons.live_uids(Game).has(u.uid), "native weekly live UID pass sees private reserve")
	check(ServiceIdentity.inventory(Game).get(u.uid, []) == [u], "native inventory sees one physical holder")
	check(ServiceIdentity.uid_floor(Game) > u.uid, "allocation floor includes actual reserve UID")
	check(Persons._unit(u.uid) == u, "native bound-unit display resolves actual reserve body/gear")
	check(Sickness._find_unit(Game, town, p) == u, "native home sickness resolves exact private reserve person")
	var forged: Array = p.duplicate(true)
	check(Sickness._find_unit(Game, town, forged) == null, "copied/fabricated Array cannot claim actual reserve illness mirror")
	check(u.to_dict() == native and native_sha() == before and Game.rng.state == rng_before
		and Unit._next_uid == next_u and Item._next_uid == next_i, "reserve readers preserve native body/skills/kit/world/RNG/counters")
	var people_before: int = int(town["econ"]["pop"])
	var person_uid: String = str(Persons.g(p, Persons.PERSON_UID, ""))
	Army.sweep(Game)
	Persons.sweep_town(Game, town, Persons.live_uids(Game))
	check(is_same(Persons.by_uid(f, u.uid), p) and str(p[Persons.PERSON_UID]) == person_uid
		and int(town["econ"]["pop"]) == people_before, "invisible private holder survives actual Army and Persons death sweeps")
	var report: Dictionary = ServiceIdentity.after_load(Game)
	check(int(report.get("unresolved", -1)) == 0 and is_same(Persons.by_uid(f, u.uid), p)
		and u.to_dict() == native, "native service reconciliation retains same physical person without guessed replacement")
	# Native Unit serialization, independently restored; no fixture copy is registered twice.
	var restored: Unit = Unit.from_dict(native.duplicate(true))
	check(restored.to_dict() == native and restored.uid == u.uid and restored.equip["main_hand"].uid == u.equip["main_hand"].uid,
		"native saved Unit retains wounds/loss/skill/look/equipment identities")
	var json_world: Dictionary = JSON.parse_string(JSON.stringify(Game._serialize(Game.world)))
	var roundtrip: Dictionary = Game._deserialize(json_world.duplicate(true))
	var loaded: Unit = roundtrip["mobilization"]["reserve"][0]
	var loaded_person: Array = Persons.by_uid(roundtrip["towns"][loaded.home_town]["econ"]["fams"][loaded.family], loaded.uid)
	if not native_json_equal(native, loaded.to_dict()) or loaded_person.is_empty() or str(loaded_person[Persons.PERSON_UID]) != person_uid or String(loaded_person[4]) != "reserve":
		var diagnostic: Dictionary = {"visited": 0, "values": [], "numeric_types": 0}
		json_diff(native, loaded.to_dict(), "unit", diagnostic)
		print("  JSON reserve diagnostic: ", JSON.stringify(diagnostic, "", true, true))
		print("  JSON canonical unit equal: ", JSON.stringify(native) == JSON.stringify(loaded.to_dict()),
			"; person: ", str(Persons.g(loaded_person, Persons.PERSON_UID, "")), " source: ", person_uid,
			"; state: ", str(Persons.g(loaded_person, 4, "MISSING")))
	check(native_json_equal(native, loaded.to_dict()) and not loaded_person.is_empty()
		and native_json_equal(p, loaded_person) and str(loaded_person[Persons.PERSON_UID]) == person_uid and String(loaded_person[4]) == "reserve",
		"current native JSON retains full physical reserve and corresponding person UID")
	var wrong: Dictionary = loaded.to_dict().duplicate(true)
	wrong["uid"] = u.uid + 1
	check(not native_json_equal(native, wrong), "JSON comparison still rejects changed exact Unit identity")
	wrong = loaded.to_dict().duplicate(true); wrong["body"]["parts"]["foot_l"]["severed"] = false
	check(not native_json_equal(native, wrong), "JSON comparison still rejects regenerated lost limb")
	wrong = loaded.to_dict().duplicate(true); wrong["body"]["parts"]["arm_upper_r"]["layers"][2]["dmg"] = 0.61
	check(not native_json_equal(native, wrong), "JSON comparison still rejects changed actual wound damage without tolerance")
	check(ServiceIdentity.uid_floor(Game) > loaded.uid and Item._next_uid > loaded.equip["main_hand"].uid,
		"independent native Unit and Item allocation floors exceed current retained identities")
	Healing.heal(u, 0.25, true, 0); Healing.heal(restored, 0.25, true, 0)
	check(u.body.to_dict() == restored.body.to_dict() and u.skills == restored.skills
		and u.body.part("foot_l").get("severed", false), "native home healing matches control and never regrows lost foot")
	check(is_same(Persons.by_uid(f, u.uid), p) and Sickness._find_unit(Game, town, p) == u,
		"healed wounded reserve retains the same person and physical holder")
	Game.day = People.year_days()
	People.tick_ages(Game, int(Game.day))
	check(u.age == Persons.age_of(p, Game.day), "actual reserve age advances with native calendar, not a new roll")
	Game.day = 0.0

func death_checks(town: Dictionary, dead_row: Array, alive_row: Array) -> void:
	var dead: Unit = dead_row[0]; var df: Dictionary = dead_row[1]; var dp: Array = dead_row[2]
	var living: Unit = alive_row[0]; var lf: Dictionary = alive_row[1]; var lp: Array = alive_row[2]
	# Names deliberately collide; only the actual native binding identifies the casualty.
	dp[7] = "Shared Native Name"; dead.name = String(dp[7])
	lp[7] = String(dp[7]); living.name = String(lp[7])
	var pop_before: int = int(town["econ"]["pop"])
	var deaths_before: int = (Census._book(town["econ"])["deaths"] as Array).size()
	var survivor: Dictionary = living.to_dict().duplicate(true)
	var item_counts: Dictionary = owned_items()
	var personal_items: Array = dead.equip.values().duplicate()
	var person_uid: String = str(dp[Persons.PERSON_UID])
	var treasury: float = float(town["econ"]["treasury"])
	Sickness.kill(Game, town, df, dp, Game.day, "starved", "hunger")
	check(dead.dead and not (Game.world["mobilization"]["reserve"] as Array).has(dead), "native reserve starvation removes only actual physical Unit")
	check(Persons.by_uid(df, dead.uid).is_empty() and not df.get("player_reserve_uids", {}).has(str(dead.uid)),
		"native death clears exact person and private holder marker")
	check(int(town["econ"]["pop"]) == pop_before - 1
		and (Census._book(town["econ"])["deaths"] as Array).size() == deaths_before + 1, "home reserve death consumes exactly one resident and census death")
	check(is_same(Persons.by_uid(lf, living.uid), lp) and Mobilization.reserves(Game).has(living)
		and living.to_dict() == survivor, "same-name living reserve keeps body/kit/registered identity")
	var retained: Array = []
	for estate: Dictionary in Mobilization.estate_items(Game):
		if str(estate.get("person_uid", "")) == person_uid:
			retained.append(estate["item"])
	check(retained.size() == personal_items.size() and dead.equip.is_empty() and owned_items() == item_counts,
		"home death retains every exact private Item once in native pending estate")
	var exact: bool = true
	for item: Item in personal_items: exact = exact and retained.has(item)
	check(exact and float(town["econ"]["treasury"]) == treasury, "estate keeps actual Item objects without public fencing or treasury debit")
	var plain: Dictionary = JSON.parse_string(JSON.stringify(Game._serialize(Game.world)))
	var roundtrip: Dictionary = Game._deserialize(plain.duplicate(true))
	var estate_uids: Array = []
	var maximum: int = 0
	for estate: Dictionary in roundtrip["mobilization"].get("estate_items", []):
		var item: Item = estate["item"]
		maximum = maxi(maximum, item.uid)
		if str(estate.get("person_uid", "")) == person_uid: estate_uids.append(item.uid)
	var source_uids: Array = personal_items.map(func(item): return item.uid)
	estate_uids.sort(); source_uids.sort()
	check(estate_uids == source_uids and Item._next_uid > maximum, "current estate JSON keeps real Item UID floor and deceased owner references")
	var after: String = native_sha()
	People.casualty(Game, dead, "dead", "reserve")
	check(native_sha() == after, "repeat actual casualty cannot remove namesake or duplicate death")

func dismissal_checks(town: Dictionary) -> void:
	var p: Array = []
	var f: Dictionary = {}
	for family: Dictionary in town["econ"]["fams"]:
		if family.get("gone", false) or family.get("estate", false): continue
		for person: Array in Persons.pp(family):
			if String(person[4]) == "" and int(person[5]) < 0:
				f = family; p = person; break
		if not p.is_empty(): break
	check(not p.is_empty(), "small native fixture has ordinary registered recruit/return case")
	if p.is_empty(): return
	var unit: Unit = U.soldier("copper")
	Persons.bind(town["econ"], f, p, unit, "hire", Game.day)
	unit.home_town = String(town["id"]); unit.faction = String(town["faction"])
	unit.hire_cost = 200; unit.wage = 80
	unit.body.wound_part("arm_upper_l")["layers"][2]["dmg"] = 0.4
	unit.body.parts["arm_upper_l"]["layers"][2]["kind"] = "cut"
	(town["recruits"] as Array).append(unit)
	var quote: Dictionary = Recruits.offer(Game, unit)
	var purse: float = float(f["purse"]); var wallet: int = Game.gold
	var pop: int = int(town["econ"]["pop"])
	var next_uid: int = Unit._next_uid; var next_item: int = Item._next_uid
	check(Recruits.hire(Game, town, unit), "ordinary native registered recruit hires at native offer")
	var person_uid: String = str(p[Persons.PERSON_UID])
	check(Mobilization.manages(Game, unit) and Game.world["mobilization"]["enlisted"].has(person_uid)
		and Unit._next_uid == next_uid and Item._next_uid == next_item,
		"completed native hire registers same physical person/gear without additional allocation")
	check(Game.gold == wallet - int(quote["hire_cost"]) and float(f["purse"]) == purse + float(quote["hire_cost"])
		and int(town["econ"]["pop"]) == pop - 1 and String(p[4]) == "company",
		"ordinary hire debits/credits once and applies native company AWAY counts")
	var before: String = native_sha()
	var reason: String = Roster.dismiss(Game, unit)
	check(reason != "" and native_sha() == before and Game.company.has(unit)
		and not unit.equip.is_empty() and is_same(Persons.by_uid(f, unit.uid), p),
		"remote registered dismissal rejects without disappearance, stripping or false death")
	var physical: PackedByteArray = var_to_bytes([unit.body.to_dict(), unit.skills, unit.look, unit.equip.values().map(func(it): return it.to_dict())])
	var treasury: float = float(town["econ"]["treasury"])
	var market: Dictionary = town["econ"]["biz"][int(town["econ"]["mkt"])]
	var till: float = float(market["till"])
	var unpaid: int = int(Army.A()["company_desert_days"])
	unit.unpaid_days = unpaid
	Army.company_desertion(Game)
	check(not Game.company.has(unit) and Mobilization.reserves(Game).has(unit) and is_same(Persons.by_uid(f, unit.uid), p)
		and p[4] == "reserve" and int(p[5]) == unit.uid and int(town["econ"]["pop"]) == pop,
		"native unpaid return retains actual body/person and restores resident count once")
	check(var_to_bytes([unit.body.to_dict(), unit.skills, unit.look, unit.equip.values().map(func(it): return it.to_dict())]) == physical
		and float(town["econ"]["treasury"]) == treasury and float(market["till"]) == till,
		"managed desertion preserves private kit/wounds without foreign fencing/public money")
	check(int(Persons.unpaid_memory(p, "company").get("days", -1)) == unpaid, "native person remembers actual unpaid service")
	before = native_sha()
	Army.company_desertion(Game)
	check(native_sha() == before, "empty desertion retry cannot duplicate home return")
	# Capacity fixture is repeated references only, never claimed as 200 allocated residents.
	Game.company.resize(200); Game.company.fill(unit)
	(town["recruits"] as Array).append(unit)
	before = native_sha()
	check(Roster.MAX_OFFICERS == 8 and Roster.MAX_TROOPS == 24 and Roster.MAX_COMPANY == 200, "ordinary roster caps match actual 200-person command design")
	check(not Recruits.hire(Game, town, unit) and Roster.hire(Game, town, unit, -1) != "" and native_sha() == before,
		"both direct and roster hiring reject capacity before any native transaction")
	Game.company.clear(); (town["recruits"] as Array).erase(unit)

func natural_company_checks(town: Dictionary) -> void:
	var row: Array = hold(town)
	check(row.size() == 3, "small native physical-holder fixture has natural company death case")
	if row.size() != 3: return
	var u: Unit = row[0]; var f: Dictionary = row[1]; var p: Array = row[2]
	var a: Dictionary = Mobilization._address(Game, u)
	Mobilization.reserves(Game).erase(u)
	Mobilization._away(Game, u, a) # adapter fixture departure, not a funded muster claim
	Game.company.append(u)
	var uid: String = str(p[Persons.PERSON_UID])
	var items_before: Dictionary = owned_items()
	var all_private: Array = u.equip.values().duplicate()
	var pop: int = int(town["econ"]["pop"])
	var treasury: float = float(town["econ"]["treasury"])
	var market: Dictionary = town["econ"]["biz"][int(town["econ"]["mkt"])]
	var till: float = float(market["till"])
	var arrow: String = String(DB.arrows.keys()[0])
	var expected_quiver: Dictionary = {}
	expected_quiver[arrow] = 7; u.quiver = expected_quiver.duplicate()
	Sickness.kill(Game, town, f, p, Game.day, "starved", "hunger")
	check(u.dead and not Game.company.has(u) and Persons.by_uid(f, u.uid).is_empty()
		and int(town["econ"]["pop"]) == pop, "natural company death removes exact AWAY person without second population debit")
	var retained: Array = []
	for estate: Dictionary in Mobilization.estate_items(Game):
		if str(estate.get("person_uid", "")) == uid: retained.append(estate["item"])
	var exact: bool = retained.size() == all_private.size()
	for item: Item in all_private: exact = exact and retained.has(item)
	check(exact and u.equip.is_empty() and owned_items() == items_before,
		"natural company death conserves exact private Item owners rather than dropping gear")
	check(float(town["econ"]["treasury"]) == treasury and float(market["till"]) == till,
		"natural private estate does not fence, sell or debit public coin")
	var retained_quiver: bool = false
	for estate: Dictionary in Game.world["mobilization"].get("estate_quivers", []):
		if str(estate.get("person_uid", "")) == uid: retained_quiver = estate.get("goods", {}) == expected_quiver
	check(retained_quiver and u.quiver.is_empty(), "natural death preserves actual quiver quantities in private estate once")
	var before: String = native_sha()
	People.casualty(Game, u, "dead", "company")
	check(native_sha() == before, "repeat natural company casualty cannot double estate or census")
	# Game.finish_battle owns battlefield gear. This fixture supplies its already
	# stripped stash consequence, without rerunning rewards or pretending a fight.
	row = hold(town)
	check(row.size() == 3, "small native physical-holder fixture has already-looted battlefield casualty case")
	if row.size() != 3: return
	u = row[0]; f = row[1]; p = row[2]
	a = Mobilization._address(Game, u)
	Mobilization.reserves(Game).erase(u); Mobilization._away(Game, u, a)
	Game.company.append(u)
	var estate_before: int = Mobilization.estate_items(Game).size()
	Outfit.strip(u, Game.stash); u.dead = true; Game.company.erase(u)
	items_before = owned_items()
	People.casualty(Game, u, "dead", "company")
	check(owned_items() == items_before and Mobilization.estate_items(Game).size() == estate_before
		and Persons.by_uid(f, u.uid).is_empty(), "battle company cleanup cannot duplicate already-looted stash Items into private estate")

func reserve_aging_checks(town: Dictionary) -> void:
	var row: Array = hold(town)
	check(row.size() == 3, "small native physical-holder fixture has private home aging case")
	if row.size() != 3: return
	var u: Unit = row[0]; var f: Dictionary = row[1]; var p: Array = row[2]
	var e: Dictionary = town["econ"]
	var ages: Dictionary = People.ages(u.race)
	# Author native threshold dates in this bounded fixture, never a retrospective
	# full-world simulation or a claimed funded troop allocation.
	p[3] = Game.day - (float(ages["elder"]) + 0.5) * People.year_days()
	u.born = float(p[3]); f.erase("nxa")
	var category: String = "m" if int(p[2]) == 0 else "f"
	var adult_before: int = int(f[category]); var old_before: int = int(f["old"])
	var physical: Dictionary = u.to_dict().duplicate(true)
	check(Persons._private_home_reserve(e, f, p) == u and Persons._private_home_reserve(e, f, p.duplicate(true)) == null,
		"home aging accepts only exact native reserve person/Unit, not copied UID rows")
	Persons.age_up(e, f, Game.day)
	check(int(p[6]) == 1 and int(f[category]) == adult_before - 1 and int(f["old"]) == old_before + 1
		and u.to_dict() == physical, "private home resident reaches native elder class without rerolling physical Unit")
	p[3] = Game.day - (float(ages["lifespan"]) + 0.5) * People.year_days(); u.born = float(p[3])
	f["player_reserve_uids"].erase(str(u.uid))
	check(Persons._private_home_reserve(e, f, p) == null and not is_same(Persons.oldest_elder(f), p),
		"unmarked public/service reserve keeps inherited policy and cannot claim private settlement")
	f["player_reserve_uids"][str(u.uid)] = true
	check(is_same(Persons.oldest_elder(f), p), "exact held elder participates in native oldest-home ordering")
	var pop_before: int = int(e["pop"])
	var deaths_before: int = (Census._book(e)["deaths"] as Array).size()
	var owned_before: Dictionary = owned_items()
	var held_items: Array = u.equip.values().duplicate()
	f.erase("nxa")
	Persons.age_up(e, f, Game.day)
	check(u.dead and not Mobilization.reserves(Game).has(u) and Persons.by_uid(f, u.uid).is_empty()
		and int(e["pop"]) == pop_before - 1 and (Census._book(e)["deaths"] as Array).size() == deaths_before + 1,
		"private held elder reaches native lifespan with one actual person/census death")
	var estate: Array = Mobilization.estate_items(Game).map(func(record): return record["item"])
	var exact: bool = true
	for item: Item in held_items: exact = exact and estate.has(item)
	check(exact and owned_items() == owned_before and u.equip.is_empty(), "old-age settlement conserves physical Item owners before census ID retirement")

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var original: Dictionary = {"world": Game.world, "company": Game.company.duplicate(), "stash": Game.stash.duplicate(),
		"squads": Game.squads.duplicate(true), "day": Game.day, "gold": Game.gold, "location": Game.location,
		"rng": Game.rng.state, "unit_next": Unit._next_uid, "item_next": Item._next_uid}
	var original_sha: String = native_sha()
	var dims: Array = [WorldGen.W, WorldGen.H, WorldGen.K, WorldGen.TF, WorldGen.KD]
	Fixture.new().fixture()
	Army.state(Game.world)
	Game.world["mobilization"] = {"v": 1, "reserve": [], "enlisted": {}, "history": []}
	var town: Dictionary = Game.world["towns"]["city_a"]
	var held: Array = []
	for i: int in 3: held.append(hold(town))
	var complete: bool = true
	for row: Array in held: complete = complete and row.size() == 3
	check(complete, "three exact actual register/physical-holder fixture identities, not allocation receipts")
	if complete:
		var treasury_before: float = float(town["econ"]["treasury"])
		town["econ"]["treasury"] = 1.0e9 # fixture removes the affordability cap, not a gameplay funding claim
		check(TownDefence.militia_target(town) == Population.available(town), "private reserve marker excludes held people from public militia target")
		town["econ"]["treasury"] = treasury_before
		presence_checks(town, held[0])
		death_checks(town, held[0], held[1])
		var third: Unit = held[2][0]
		var third_family: Dictionary = held[2][1]
		var pop: int = int(town["econ"]["pop"])
		third.dead = true
		Census.note_fate(Game.world, third.uid, "wounds", "native injury fixture")
		People.casualty(Game, third, "dead", "reserve")
		check(not (Game.world["mobilization"]["reserve"] as Array).has(third)
			and Persons.by_uid(third_family, third.uid).is_empty() and int(town["econ"]["pop"]) == pop - 1,
			"actual dead reserve casualty consumes holder/person/population once")
		var after: String = native_sha()
		People.casualty(Game, third, "dead", "reserve")
		check(native_sha() == after, "repeat reserve wound death is pure")
		dismissal_checks(town)
		natural_company_checks(town)
		reserve_aging_checks(town)
	Game.world = original["world"]; Game.company = original["company"]; Game.stash = original["stash"]
	Game.squads = original["squads"]; Game.day = float(original["day"]); Game.gold = int(original["gold"])
	Game.location = String(original["location"]); Game.rng.state = int(original["rng"])
	Unit._next_uid = int(original["unit_next"]); Item._next_uid = int(original["item_next"])
	WorldGen.W = int(dims[0]); WorldGen.H = int(dims[1]); WorldGen.K = float(dims[2])
	WorldGen.TF = float(dims[3]); WorldGen.KD = float(dims[4])
	Game.invalidate_deploy()
	check(native_sha() == original_sha and Game.rng.state == int(original["rng"]), "focused fixtures restore original native campaign/RNG/counters")
	print("Player reserve identity v017: ", checks, " checks, ", fails, " failures")
	return fails
