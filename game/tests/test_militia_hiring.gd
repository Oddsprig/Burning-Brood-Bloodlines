extends RefCounted
const NativeEconomy = preload("res://tests/class_d_native_economy.gd")
const NativeCultures = preload("res://tests/class_d_culture_fixtures.gd")

var fails: int = 0
var _deadline_msec: int = 0
var checks: int = 0
var _native_households: Dictionary = {}

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1; printerr("FAIL: ", msg)

func cash(e: Dictionary) -> float:
	return NativeEconomy.money(e)

func civil_balance(e: Dictionary, label: String) -> void:
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		check(not Families.assignments_stale(f), label + ": civilian assignments balance")
		check(Families.job_total(f) <= Families.adults(f) - Families.serving(f), label + ": serving people cannot take civilian jobs")

func _bindings(town: Dictionary, wb: Dictionary, state: String) -> Dictionary:
	var identities: Dictionary = {}
	for unit: Unit in wb["units"]:
		var family: Dictionary = People.fam_of(town, unit.family)
		var person: Array = Persons.by_uid(family, unit.uid) if not family.is_empty() else []
		check(not unit.dead and unit.home_town == str(town["id"]) and not person.is_empty(), "selected living militia keeps its actual home and registered family")
		if fails > 0: return {}
		check(unit.uid >= 0 and not identities.has(unit.uid) and int(person[5]) == unit.uid and str(person[4]) == state,
			"selected militia has one actual Unit/person binding in " + state)
		var person_uid: String = str(Persons.g(person, Persons.PERSON_UID, ""))
		check(person_uid not in ["", "0"], "selected militia has a real registered person UID")
		if fails > 0: return {}
		identities[unit.uid] = {"unit_uid": unit.uid, "family": unit.family, "home_town": unit.home_town,
			"person_pid": int(person[0]), "person_uid": person_uid, "birth_day": float(person[3]),
			"mother_pid": int(Persons.g(person, Persons.MO, -1)), "father_pid": int(Persons.g(person, Persons.FA, -1)),
			"mother_uid": str(Persons.g(person, Persons.MOTHER_UID, "")), "father_uid": str(Persons.g(person, Persons.FATHER_UID, ""))}
	return identities

func _equipment(wb: Dictionary) -> Dictionary:
	var kits: Dictionary = {}
	for unit: Unit in wb["units"]:
		var slots: Dictionary = {}
		for slot: String in unit.equip:
			# Detach every retained Item field, including nested maker/history data.
			slots[slot] = (unit.equip[slot] as Item).to_dict().duplicate(true)
		kits[unit.uid] = slots
	return kits

func _militia_service_is(family: Dictionary, before: Dictionary, militia: int) -> bool:
	var expected: Dictionary = before.duplicate()
	expected["militia"] = militia
	return family.get("serve", {}) == expected

func _reservists(town: Dictionary, wb: Dictionary, fid: int, count: int) -> Array:
	var units: Array = []
	for unit: Unit in wb["units"]:
		if unit.family == fid and units.size() < count: units.append(unit)
	if units.size() == count: return units
	# Use actual draft-age residents, including promotion from counted cohort
	# bins. Never relabel another family's Unit or invent an adult/service slot.
	var pool: Array = People.draft_pool(town).filter(func(row: Array) -> bool: return int(row[2]) == fid)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([town["id"], fid, "native-militia-hiring"])
	while units.size() < count:
		if People.draft(town, pool, "militia") != fid: return []
		var unit: Unit = CampaignWorld.make_resident_troop(rng, str(town["faction"]), town, int(town["wealth"]))
		People.bind(town, fid, unit, "militia")
		unit.title = "militia " + unit.title
		TownEcon.outfit_units(town, [unit], 0.25)
		(wb["units"] as Array).append(unit); units.append(unit)
	return units

func _native_militia_town(culture: String, fallback: Dictionary) -> Dictionary:
	# Random militia recruitment need not draw from the earliest idle pools.
	# Prepare counted native reservists and real setup resources independently
	# of the funded return, drill and wage assertions exercised in each case.
	var candidates: Array[Dictionary] = []
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	for tid: String in ids:
		var town: Dictionary = Game.world["towns"][tid]
		if TownEcon.has_econ(town) and str(town["econ"]["culture"]) == culture: candidates.append(town)
	if not Game.world["towns"].has(fallback["id"]):
		Game.world["towns"][fallback["id"]] = fallback
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = hash([Game.world["seed"], culture, "class-d-native-militia"])
		Militia.ensure(Game, str(fallback["id"]), rng)
		candidates.append(fallback)
	var rejected: Array[Dictionary] = []
	for town: Dictionary in candidates:
		if not _within_budget(): return {}
		var band: Dictionary = Militia.band_of(Game, str(town["id"]))
		check(not band.is_empty(), culture + ": generated town has its native militia band")
		if band.is_empty(): return {}
		for unit: Unit in band["units"]:
			var family: Dictionary = People.fam_of(town, unit.family)
			var person: Array = Persons.by_uid(family, unit.uid) if not family.is_empty() else []
			check(not unit.dead and unit.home_town == str(town["id"]) and not person.is_empty()
				and str(person[4]) in ["reserve", "militia"] and int(person[5]) == unit.uid,
				"candidate militia has an actual living local Unit/person binding")
			if fails > 0: return {}
		var eligible: Array[int] = []
		for fid: int in (town["econ"]["fams"] as Array).size():
			var family: Dictionary = town["econ"]["fams"][fid]
			if not Population.is_cohort(family) or family.get("gone", false): continue
			# Preview stand-down: only this militia service returns to civilian
			# work. Guards, field troops and caravan obligations still count.
			var other_service: int = Families.serving(family) - int(family.get("serve", {}).get("militia", 0))
			if Families.adults(family) - other_service >= 3 and NativeEconomy.no_shop(town["econ"], family): eligible.append(fid)
		var original: Dictionary = Game._serialize({"town": town, "band": band})
		# Each waiter alternative is an independent native fixture. The two
		# households may exchange roles: real matching visits earlier idle
		# households first, so a fixed pool need not admit two later waiters.
		var ready: Array[Dictionary] = []
		for held: int in eligible:
			var waiters: Array[int] = []
			for fid: int in eligible:
				if fid != held and Families.adults(town["econ"]["fams"][fid]) >= 3: waiters.append(fid)
			for waiter: int in waiters:
				if not _within_budget(): return {}
				var facts: Dictionary = {"culture": culture, "town": town["id"], "incumbent_family": held,
					"waiter_family": waiter, "source_households": {"incumbent_family": held, "waiter_family": waiter},
					"admission_ok": false}
				# Use the fixture's exact native setup on isolated save objects.
				# Admission stops before the offered jobs, wage close or drill.
				var unit_uid: int = Unit._next_uid
				var item_uid: int = Item._next_uid
				var world: Dictionary = Game.world
				var arms_ledger: Dictionary = ArmsTrade.ledger
				Game.world = Game.world.duplicate(true)
				ArmsTrade.ledger = arms_ledger.duplicate(true)
				_fixture(str(town["id"]), original, false, false, facts, true)
				Game.world = world
				ArmsTrade.ledger = arms_ledger
				Unit._next_uid = unit_uid; Item._next_uid = item_uid
				if fails > 0: return {}
				if bool(facts["admission_ok"]):
					if ready.is_empty() or int(ready[0]["waiter_family"]) != waiter:
						ready.append(facts["source_households"])
				else:
					print("MILITIA_HIRING_PREREQUISITE ", JSON.stringify(facts))
					rejected.append(facts)
				if ready.size() == 2:
					_native_households[str(town["id"])] = {"alternatives": ready}
					print("MILITIA_HIRING_SOURCE ", JSON.stringify({"culture": culture, "town": town["id"],
						"alternatives": ready}))
					return town
				if bool(facts["admission_ok"]): break
		if eligible.is_empty(): rejected.append({"culture": culture, "town": town["id"], "eligible_families": eligible})
	check(false, "native culture needs a town and two waiter choices satisfying every hiring fixture prerequisite: " + JSON.stringify(rejected))
	return {}

func fixture(town_id: String, original: Dictionary, reverse_units: bool, reverse_waiters: bool, funded: bool) -> void:
	var case_fails: int = fails
	var case_checks: int = checks
	var receipt: Dictionary = {"evidence_kind": "native_observation_not_reference", "town": town_id,
		"culture": str(original.get("town", {}).get("econ", {}).get("culture", "")),
		"reverse_units": reverse_units, "reverse_waiters": reverse_waiters, "funded": funded,
		"source_households": _native_households[town_id]["alternatives"][1 if reverse_waiters else 0]}
	_fixture(town_id, original, reverse_units, funded, receipt)
	receipt["assertions"] = checks - case_checks
	receipt["assertion_result"] = fails - case_fails
	print("MILITIA_HIRING_CASE ", JSON.stringify(receipt))

func _fixture(town_id: String, original: Dictionary, reverse_units: bool, funded: bool, receipt: Dictionary, admission: bool = false) -> void:
	if not _within_budget(): return
	# Native save reconstruction keeps Unit/Item objects isolated between the eight cases.
	var restored: Dictionary = Game._deserialize(original.duplicate(true))
	var town: Dictionary = restored["town"]
	var wb: Dictionary = restored["band"]
	Game.world["towns"][town_id] = town
	Game.world["warbands"][str(wb["id"])] = wb
	var e: Dictionary = town["econ"]
	TownDefence.set_muster(Game, town, false, false)
	for unit: Unit in wb["units"]:
		var family: Dictionary = People.fam_of(town, unit.family)
		var person: Array = Persons.by_uid(family, unit.uid) if not family.is_empty() else []
		check(not person.is_empty() and not unit.dead and str(person[4]) == "reserve" and unit.home_town == town_id and int(person[5]) == unit.uid, "actual living reserve militia UID/family/home binding")
		if fails > 0: return
	var held: Dictionary = {}
	var waiters: Array[Dictionary] = []
	var source: Dictionary = receipt["source_households"]
	for id: int in (e["fams"] as Array).size():
		var family: Dictionary = e["fams"][id]
		if not NativeEconomy.no_shop(e, family): continue
		if id == int(source["incumbent_family"]): held = family
		elif id == int(source["waiter_family"]) and Families.adults(family) >= 3: waiters.append(family)
	check(not held.is_empty() and waiters.size() == 1, "native militia needs its actual incumbent and waiting households")
	if held.is_empty() or waiters.size() != 1: return
	var waiter: Dictionary = waiters[0]
	var service_before: Array[Dictionary] = [(held.get("serve", {}) as Dictionary).duplicate(), (waiter.get("serve", {}) as Dictionary).duplicate()]
	receipt["service_before"] = service_before.duplicate(true)
	var adults_before: Array[int] = [Families.adults(held), Families.adults(waiter)]
	var people_before: Array[int] = [Families.people(held), Families.people(waiter)]
	var incumbent_units: Array = _reservists(town, wb, int(held["id"]), 2)
	var waiter_units: Array = _reservists(town, wb, int(waiter["id"]), 1)
	var supplied: bool = incumbent_units.size() == 2 and waiter_units.size() == 1
	if admission and not supplied:
		receipt["prerequisite"] = "native draft cannot supply two incumbent reservists and one waiter reservist"
		return
	check(supplied, "native militia needs two real incumbent reservists and one genuine waiting reservist")
	if not supplied: return
	TownDefence.set_muster(Game, town, false, false)
	check(_militia_service_is(held, service_before[0], 0) and _militia_service_is(waiter, service_before[1], 0), "native fixture recruitment returns only its militia and preserves all other service")
	check([Families.adults(held), Families.adults(waiter)] == adults_before
		and [Families.people(held), Families.people(waiter)] == people_before, "native fixture recruitment conserves every actual household adult and person")
	if fails > 0: return
	var selected: Array = [incumbent_units[0], incumbent_units[1], waiter_units[0]]
	receipt["band"] = str(wb["id"])
	receipt["incumbent_family"] = int(held["id"])
	receipt["waiter_family"] = int(waiter["id"])
	# Release actual surplus reservists, including their kit, before erasing their roster entries.
	for unit: Unit in (wb["units"] as Array).duplicate():
		if selected.has(unit): continue
		var family: Dictionary = People.fam_of(town, unit.family)
		var person: Array = Persons.by_uid(family, unit.uid)
		Horses.return_mount(Game, unit); ArmsTrade.kit_home(Game, unit)
		People.release(town, unit.family, str(person[4]), unit.uid)
		(wb["units"] as Array).erase(unit)
	if reverse_units: (wb["units"] as Array).reverse()
	var setup_coin: float = cash(e)
	for family: Dictionary in e["fams"]:
		if not family.get("estate", false): HarvestClaims.transfer(e, "f:%d" % int(family["id"]), "f:0")
	var pooled: Dictionary = NativeEconomy.pool(e)
	check(bool(pooled["ok"]), str(pooled.get("reason", "")))
	if not bool(pooled["ok"]): return
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false): continue
		NativeEconomy.vacate(e, family)
	NativeEconomy.transfer_holding(e, waiter)
	var occupied: Dictionary = NativeEconomy.reserve_casual(town, e, [int(held["id"]), int(waiter["id"])], _deadline_msec)
	if admission and not bool(occupied["ok"]):
		var reason: String = str(occupied.get("reason", ""))
		if reason.begins_with("native other workers could not fill every actual ") or reason in [
			"native casual reservations need a real customer payer", "native holders cannot fund the actual casual reservation bill"]:
			receipt["prerequisite"] = reason
			return
	check(bool(occupied["ok"]), "native other-worker casual reservations: " + str(occupied.get("reason", "")))
	if not bool(occupied["ok"]): return
	Families.reassign(e, held); Families.reassign(e, waiter)
	var held_places: int = int(held["idle"])
	# Common-household pools span many employers. Keep native business caps and
	# fund individual places across town, as Families._best_places actually does.
	var offers: Array[Dictionary] = []
	var places: Dictionary = {}
	var remaining: int = held_places
	var bill: float = 0.0
	for business: Dictionary in e["biz"]:
		if business.get("closed", false) or str(business["type"]) in ["farm", "estate", "market", "academy"]: continue
		if int(business["workers"]) != 0 or int(business["cap"]) <= 0 or float(business["wage"]) <= 0.0: continue
		var count: int = mini(remaining, int(business["cap"]))
		offers.append(business); places[str(int(business["id"]))] = count
		bill += float(business["owed"]) + float(business["wage"]) * float(count) * 3.0
		remaining -= count
		if remaining == 0: break
	receipt["held_adults"] = Families.adults(held); receipt["held_hands"] = int(held["hands"])
	receipt["held_places"] = held_places; receipt["offers"] = places.duplicate()
	if admission:
		check(absf(cash(e) - setup_coin) < 0.00001, "native admission preparation conserves actual coin")
		if held_places < 3 or remaining != 0:
			receipt["prerequisite"] = "needs three spare incumbent adults and enough actual places across generated businesses"
			return
	check(held_places >= 3 and remaining == 0, "native militia fixture needs three actual spare adults and town businesses covering their real places")
	if held_places < 3 or remaining != 0: return
	var vault: Dictionary = occupied["vault"]
	if admission:
		# These are setup inputs, not the service/matching behaviour under test.
		if float(vault["purse"]) + 0.000001 < bill:
			receipt["prerequisite"] = "native estate cannot fund the full incumbent offer bill"
			return
		if not (_militia_service_is(waiter, service_before[1], 0) and Families.adults(waiter) - Families.serving(waiter) >= 3
			and int(waiter["idle"]) >= 3 and Families.job_total(waiter) == 0 and waiter.get("cj", {}).is_empty()
			and float(waiter.get("wage_receipts", 0.0)) == 0.0):
			receipt["prerequisite"] = "native waiter needs three real idle adults and no preceding jobs or casual reservations"
			return
		for family: Dictionary in e["fams"]:
			if int(family["id"]) >= int(waiter["id"]): break
			if family.get("gone", false) or family.get("estate", false) or int(family["id"]) == int(held["id"]): continue
			if int(family["idle"]) != 0:
				receipt["prerequisite"] = "earlier household %d competes for this waiter's vacancies" % int(family["id"])
				return
		for business: Dictionary in e["biz"]:
			if float(business.get("wage_claims", {}).get(str(int(waiter["id"])), 0.0)) != 0.0:
				receipt["prerequisite"] = "native waiter has a preceding-day wage claim"
				return
		check(_bindings(town, wb, "reserve").size() == selected.size(), "every admitted native militia identity is bound before drill")
		if fails > 0: return
		receipt["admission_ok"] = true
		return
	# First prove a real paid return, before the waiter occupies the released
	# places. Only the incumbent is raised in this setup; the actual waiting
	# reservist joins the roster unchanged before stand-down.
	for unit: Unit in selected:
		# Supply an empty reservist only from actual native armory/shop stock.
		if unit.equip.is_empty(): ArmsTrade.rekit_units(Game, town, [unit], true, null, true)
		check(not unit.equip.is_empty(), "every selected reservist has actual issued equipment before initial muster")
		for item: Item in unit.equip.values():
			check(item.uid > 0, "issued reservist equipment has actual Item UIDs")
	if fails > 0: return
	var equipment_before: Dictionary = _equipment(wb)
	receipt["equipment_before_initial_muster"] = equipment_before.duplicate(true)
	var initial_bindings: Dictionary = _bindings(town, wb, "reserve")
	if fails > 0: return
	var ordered_units: Array = (wb["units"] as Array).duplicate()
	(wb["units"] as Array).erase(selected[2])
	TownDefence.set_muster(Game, town, true, false)
	check(_militia_service_is(held, service_before[0], 2) and _militia_service_is(waiter, service_before[1], 0), "initial muster raises precisely the incumbent's two real adults and preserves other service")
	var incumbent_bindings: Dictionary = _bindings(town, wb, "militia")
	check(incumbent_bindings.size() == 2, "initial muster binds both actual incumbent reservists")
	wb["units"] = ordered_units
	check(_equipment(wb) == equipment_before, "initial muster preserves exact equipment slots, Item UIDs and retained item state")
	if fails > 0: return
	remaining = held_places - 2
	for business: Dictionary in offers:
		var count: int = mini(remaining, int(places[str(int(business["id"]))]))
		Families.set_job(e, held, int(business["id"]), count)
		remaining -= count
	WageClaims.accrue_day(e, int(e.get("wage_day", e["day"])) + 1)
	for business: Dictionary in offers:
		var count: int = int(places[str(int(business["id"]))])
		# Reserve earned claims PLUS exactly two days per offered place. A
		# partially used last business must not advertise extra funded jobs.
		var funding: float = float(business["owed"]) + 2.0 * float(business["wage"]) * float(count) + 0.000001
		check(NativeEconomy.move(vault, "purse", business, "till", funding), "native offer funding has a matching actual estate debit")
		check(Businesses.takeable(business, e) + int(business["workers"]) >= count, "native offer can actually fund every planned incumbent place")
	if fails > 0: return
	Families.reassign(e, held)
	check(Families.job_total(held) == held_places - 2 and int(held["idle"]) == 0, "initial civilian jobs exclude precisely the two serving incumbent adults")
	receipt["incumbent_jobs_before_return"] = (held["jobs"] as Dictionary).duplicate()
	var return_last: Array = [held["last"], waiter["last"]]
	TownDefence.set_muster(Game, town, false, false)
	check(_militia_service_is(held, service_before[0], 0) and _militia_service_is(waiter, service_before[1], 0), "initial stand-down releases precisely the two incumbent adults and preserves other service")
	check(Families.job_total(held) == held_places and int(held["idle"]) == 0, "native incumbent jobs cover precisely the household's spare civilians")
	check(Families.job_total(waiter) == 0, "incumbent return fills its two real vacancies before the waiting household is hired")
	var paid_return_bindings: Dictionary = _bindings(town, wb, "reserve")
	check(paid_return_bindings == initial_bindings, "initial paid return preserves every selected native identity and parent link")
	check(_equipment(wb) == equipment_before, "initial stand-down preserves exact equipment slots, Item UIDs and retained item state")
	check(held["last"] == return_last[0] and waiter["last"] == return_last[1], "initial paid return leaves household paydays unchanged")
	for key: String in held["jobs"]:
		var business: Dictionary = e["biz"][int(key)]
		check(places.has(key) and int(held["jobs"][key]) <= int(business["workers"])
			and int(business["workers"]) <= int(business["cap"]), "returned incumbent civilians hold actual generated business places")
	receipt["incumbent_jobs_after_return"] = (held["jobs"] as Dictionary).duplicate()
	receipt["bindings_after_paid_return"] = paid_return_bindings
	if fails > 0: return
	if not funded:
		for business: Dictionary in offers:
			check(NativeEconomy.move(business, "till", vault, "purse", float(business["till"])), "unfunded condition transfers the real till to another holder")
	check(absf(cash(e) - setup_coin) < 0.00001, "all native hiring preparation conserves actual coin")
	if fails > 0: return
	check(_militia_service_is(waiter, service_before[1], 0) and Families.adults(waiter) - Families.serving(waiter) >= 3
		and int(waiter["idle"]) >= 3 and Families.job_total(waiter) == 0
		and waiter.get("cj", {}).is_empty(),
		"native militia waiter needs three real idle reserve-state adults before drill")
	for family: Dictionary in e["fams"]:
		if int(family["id"]) >= int(waiter["id"]): break
		if family.get("gone", false) or family.get("estate", false): continue
		check(int(family["idle"]) == 0,
			"native militia prerequisite: earlier household %d competes for this exact waiter's vacancies" % int(family["id"]))
	var claims_before: Dictionary = {}
	for business: Dictionary in e["biz"]:
		claims_before[str(int(business["id"]))] = (business.get("wage_claims", {}) as Dictionary).duplicate(true)
		check(float(business.get("wage_claims", {}).get(str(int(waiter["id"])), 0.0)) == 0.0,
			"new waiter has no preceding-day wage claim")
	receipt["claims_before_drill"] = claims_before
	if fails > 0: return
	var identities: Dictionary = _bindings(town, wb, "reserve")
	check(identities.size() == selected.size(), "every selected native militia identity is captured before drill")
	receipt["bindings_before_drill"] = identities
	if fails > 0: return
	var before_cash: float = cash(e)
	var last: Array = [held["last"], waiter["last"]]
	TownDefence.set_muster(Game, town, false, true)
	check(_militia_service_is(held, service_before[0], 2) and _militia_service_is(waiter, service_before[1], 1), "drill keeps every real militia transition and all other service")
	check(Families.job_total(waiter) == (2 if funded else 0), "waiting civilians take released funded jobs in either force order")
	check(Families.job_total(held) == held_places - 2, "drill releases precisely two incumbent civilian places even for pooled households")
	for business: Dictionary in offers:
		check(Businesses.takeable(business, e) == 0, "released offers match or remain genuinely unfunded")
	civil_balance(e, "drill")
	check(absf(cash(e) - before_cash) < 0.00001, "matching preserves actual coins")
	check(held["last"] == last[0] and waiter["last"] == last[1], "matching leaves household paydays unchanged")
	check(float(waiter.get("wage_receipts", 0)) == 0.0, "newly hired civilians receive no preceding drill-day wages")
	var drill_bindings: Dictionary = _bindings(town, wb, "militia")
	check(drill_bindings == identities, "drill preserves the exact selected Unit/person identities, birthdates and parent links")
	check(_equipment(wb) == equipment_before, "drill preserves exact equipment slots, Item UIDs and retained item state")
	receipt["bindings_after_drill"] = drill_bindings
	receipt["waiter_jobs_after_drill"] = Families.job_total(waiter)
	var claims_after_drill: Dictionary = {}
	for business: Dictionary in e["biz"]:
		claims_after_drill[str(int(business["id"]))] = (business.get("wage_claims", {}) as Dictionary).duplicate(true)
		check(float(business.get("wage_claims", {}).get(str(int(waiter["id"])), 0.0)) == 0.0,
			"new waiter has no preceding-day wage claim immediately after drill")
	receipt["claims_after_drill"] = claims_after_drill
	if fails > 0: return
	WageClaims.accrue_day(e, int(e.get("wage_day", e["day"])) + 1)
	var earned: float = 0.0
	for business: Dictionary in offers: earned += float(business["owed"])
	check(earned > 0.0, "no-op fixture includes actual earned wage claims")
	var snapshot: String = JSON.stringify(e)
	TownDefence.set_muster(Game, town, false, true)
	check(JSON.stringify(e) == snapshot, "same drill request leaves coins, claims and assignments identical")
	check(_bindings(town, wb, "militia") == identities, "repeated drill preserves every selected native identity")
	check(_equipment(wb) == equipment_before, "repeated drill preserves exact equipment slots, Item UIDs and retained item state")
	if fails > 0: return
	TownDefence.set_muster(Game, town, true, false)
	check(JSON.stringify(e) == snapshot, "drill to muster retains existing service assignments")
	var muster_bindings: Dictionary = _bindings(town, wb, "militia")
	check(muster_bindings == identities, "muster preserves the exact selected Unit/person identities, birthdates and parent links")
	check(_equipment(wb) == equipment_before, "drill to muster preserves exact equipment slots, Item UIDs and retained item state")
	receipt["bindings_after_muster"] = muster_bindings
	if fails > 0: return
	TownDefence.set_muster(Game, town, false, false)
	check(_militia_service_is(held, service_before[0], 0) and _militia_service_is(waiter, service_before[1], 0), "return releases each militia adult and preserves all other service")
	var return_bindings: Dictionary = _bindings(town, wb, "reserve")
	check(return_bindings == identities, "return preserves the exact selected Unit/person identities, birthdates and parent links")
	check(_equipment(wb) == equipment_before, "return preserves exact equipment slots, Item UIDs and retained item state")
	receipt["bindings_after_return"] = return_bindings
	civil_balance(e, "return")
	check(absf(cash(e) - before_cash) < 0.00001, "return preserves actual coins")
	snapshot = JSON.stringify(e)
	TownDefence.set_muster(Game, town, false, false)
	check(JSON.stringify(e) == snapshot, "repeated return leaves economy identical")
	check(_bindings(town, wb, "reserve") == identities, "repeated return preserves every selected native identity")
	check(_equipment(wb) == equipment_before, "repeated return preserves exact equipment slots, Item UIDs and retained item state")
	if fails > 0: return
	TownDefence.set_muster(Game, town, true, false)
	check(_militia_service_is(held, service_before[0], 2) and _militia_service_is(waiter, service_before[1], 1), "direct muster counts all household militia and preserves all other service")
	civil_balance(e, "muster")
	check(absf(cash(e) - before_cash) < 0.00001, "muster preserves actual coins")
	var direct_bindings: Dictionary = _bindings(town, wb, "militia")
	check(direct_bindings == identities, "direct muster preserves every selected native identity")
	check(_equipment(wb) == equipment_before, "direct muster preserves exact equipment slots, Item UIDs and retained item state")
	receipt["bindings_after_direct_muster"] = direct_bindings
	var claims_after: Dictionary = {}
	for business: Dictionary in e["biz"]:
		claims_after[str(int(business["id"]))] = (business.get("wage_claims", {}) as Dictionary).duplicate(true)
	receipt["claims_after"] = claims_after

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	check(false, "native militia hiring exceeded 150 seconds; incomplete combinations fail")
	return false

func run(_tree: SceneTree) -> int:
	_deadline_msec = Time.get_ticks_msec() + 150000
	WorldGen.gen_size = "normal"
	Game.new_game(2026)
	var native: Dictionary = NativeCultures.towns(Game)
	check(bool(native.get("ok", false)), "native culture fixtures: " + str(native.get("reason", "")))
	if not bool(native.get("ok", false)): return fails
	var tested: Dictionary = {}
	for culture: String in native["towns"]:
		var town: Dictionary = _native_militia_town(culture, native["towns"][culture])
		if town.is_empty(): return maxi(1, fails)
		check(not Militia.band_of(Game, str(town["id"])).is_empty(), culture + ": native militia band exists")
		if Militia.band_of(Game, str(town["id"])).is_empty(): return fails
		tested[culture] = true
		var original: Dictionary = Game._serialize({"town": town, "band": Militia.band_of(Game, str(town["id"]))})
		for reverse_units: bool in [false, true]:
			for reverse_waiters: bool in [false, true]:
				for funded: bool in [false, true]:
					fixture(str(town["id"]), original, reverse_units, reverse_waiters, funded)
					if fails > 0 or not _within_budget(): return maxi(1, fails)
	var actual_cultures: Array = tested.keys(); actual_cultures.sort()
	var expected_cultures: Array = TownEcon.data()["cultures"].keys(); expected_cultures.sort()
	check(actual_cultures == expected_cultures, "all registered economy cultures are exercised: " + str(actual_cultures))
	print("MILITIA HIRING cultures=", tested.keys(), " checks=", checks, " failures=", fails)
	return fails
