extends RefCounted
const NativeCultures = preload("res://tests/class_d_culture_fixtures.gd")
const NativeEconomy = preload("res://tests/class_d_native_economy.gd")
var checks: int = 0
var fails: int = 0
var _deadline_msec: int = 0
var _prepared: Dictionary = {}

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", why)

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	check(false, "native farm batch setup exceeded 150 seconds; incomplete cases fail")
	return false

func cash(e: Dictionary) -> float:
	return NativeEconomy.money(e)

func _civilian(e: Dictionary, family: Dictionary) -> bool:
	if family.get("gone", false) or family.get("estate", false): return false
	var shops: int = 0
	for bid: int in family["owns"]:
		if str(e["biz"][bid]["type"]) != "farm" and not bool(e["biz"][bid].get("closed", false)): shops += 1
	return Families.adults(family) - Families.serving(family) > shops

func _native_pair(e: Dictionary, half: int, owner_late: bool) -> Dictionary:
	var selected: Dictionary = {}
	var first_day: int = int(e["day"]) + 1
	# The owner must fund only its farm. Matching itself visits the whole town,
	# so the idle worker need not occupy this half's stride-14 positions.
	for owner: Dictionary in e["fams"]:
		var fid: int = int(owner["id"])
		if not _civilian(e, owner) or not NativeEconomy.no_shop(e, owner): continue
		if (fid % 14 >= 7) != (half == 1): continue
		var day: int = first_day + posmod(fid % 7 - first_day % 7, 7)
		if not selected.is_empty() and day >= int(selected["day"]): continue
		for worker: Dictionary in e["fams"]:
			if not _civilian(e, worker) or int(worker["id"]) == fid: continue
			if (fid > int(worker["id"])) != owner_late: continue
			var competes: bool = false
			for earlier: Dictionary in e["fams"]:
				var eid: int = int(earlier["id"])
				if eid >= int(worker["id"]): break
				if eid == fid or not _civilian(e, earlier): continue
				# Keep earlier pools out of this exact-worker fixture.
				# A prior batch participant loses an unpaid casual reservation
				# on its ordinary turn and would win this farm in native order.
				if Population.is_cohort(earlier) or eid % 14 == fid % 14: competes = true; break
			if competes: continue
			selected = {"owner": fid, "worker": int(worker["id"]), "day": day}; break
	return selected

func _pairs_ready(e: Dictionary) -> bool:
	return not _native_pair(e, 0, true).is_empty() and not _native_pair(e, 1, true).is_empty() and not _native_pair(e, 0, false).is_empty()

func _prepare(town: Dictionary, original: Dictionary, owner_late: bool, half: int) -> Dictionary:
	if not _within_budget(): return {}
	var e: Dictionary = original.duplicate(true); town["econ"] = e
	var pair: Dictionary = _native_pair(e, half, owner_late)
	check(not pair.is_empty(), "native batch needs a shop-free owner and an earlier/later civilian, without padding or reindexing: %s half %d" % [e["culture"], half])
	if pair.is_empty(): return {}
	var day: int = int(pair["day"])
	var owner: Dictionary = e["fams"][int(pair["owner"])]
	var worker: Dictionary = e["fams"][int(pair["worker"])]
	check(day <= int(Game.day) and int(owner["id"]) % 14 == day % 7 + half * 7, "selected owner belongs to an actual elapsed native batch day")
	# Close preceding real market days before creating this one-day wage claim.
	for prior_day: int in range(int(e["day"]) + 1, day):
		if not _within_budget(): return {}
		TownEcon.daily_pass(Game, town, prior_day, false)
	var identities: Dictionary = {}
	for family: Dictionary in [owner, worker]:
		for person: Array in Persons.pp(family) + Persons.kp(family):
			identities[str(Persons.g(person, Persons.PERSON_UID, ""))] = [float(person[3]), str(Persons.g(person, Persons.MOTHER_UID, "")), str(Persons.g(person, Persons.FATHER_UID, ""))]
	var setup_coin: float = cash(e)
	for family: Dictionary in e["fams"]:
		if not family.get("estate", false): HarvestClaims.transfer(e, "f:%d" % int(family["id"]), "f:0")
	var pooled: Dictionary = NativeEconomy.pool(e)
	check(bool(pooled["ok"]), str(pooled.get("reason", "")))
	if not bool(pooled["ok"]): return {}
	for family: Dictionary in e["fams"]:
		if not family.get("gone", false) and not family.get("estate", false): NativeEconomy.vacate(e, family)
	NativeEconomy.transfer_holding(e, owner); NativeEconomy.transfer_holding(e, worker)
	var physical: Variant = load("res://tests/farm_fixture_tools.gd").new()
	# Add actual productive cereal acreage until native work creates exactly one hired place.
	# A real cohort keeps its full adult/helper count; no adult rows or ages are rewritten.
	var farm: Dictionary = {}
	var transferred: int = 0
	# Move the cohort's own-work acreage in conserved chunks, then find the
	# first hired place one acre at a time through the native reassignment.
	var own_acres: int = int(floor(4.0 * (Families.adults(owner) - Families.serving(owner) + Barge.helper_hands(e, owner, float(e["day"])))))
	while own_acres > 0:
		if not _within_budget(): return {}
		var largest: int = 0
		for source: Dictionary in e["fams"]:
			if int(source["id"]) != int(owner["id"]): largest = maxi(largest, int(source["land"].get("grain", 0)))
		var count: int = mini(own_acres, largest)
		if count <= 0 or not physical.grain(e, owner, count): break
		transferred += count; own_acres -= count
	for acre: int in int(e["territory"]) + 1:
		if not _within_budget(): return {}
		if not physical.grain(e, owner, 1): break
		transferred += 1
		Families.reassign(e, owner)
		farm = Businesses.farm_of(e, owner)
		if not farm.is_empty() and int(farm["cap"]) > 0: break
	check(transferred > 0 and not farm.is_empty() and int(farm["cap"]) == 1 and physical.base_need(e, owner) > 1.0,
		"real productive cereal holding must naturally need exactly one hired hand")
	if fails > 0: return {}
	var creditor: Dictionary = {}
	for family: Dictionary in e["fams"]:
		if int(family["id"]) <= int(worker["id"]) or int(family["id"]) % 14 == day % 7 + half * 7 or not _civilian(e, family): continue
		if int(family["idle"]) > 0: creditor = family; break
	check(not creditor.is_empty(), "retained wage debt needs an actual former worker outside this batch and after the intended worker in native matching order")
	if creditor.is_empty(): return {}
	var vault: Dictionary = pooled["vault"]
	var wage: float = float(farm["wage"])
	var creditor_reserve: float = maxf(5.0 * TownEcon.COIN, EconomyRules.essential_food_cost(e, maxf(0.0, 14.0 - float(owner["store"]["food"])) * float(Families.daily_rates(e, owner)["food"])))
	check(NativeEconomy.move(vault, "purse", owner, "purse", float(farm["owed"]) + wage * 3.0 + creditor_reserve), "earlier native farm work funds the real payroll bill AND the native owner's food reserve with conserved coin")
	Businesses.fund_farm(owner, farm, e)
	check(Businesses.takeable(farm, e) >= 1, "earlier worker's native offer was actually funded")
	if fails > 0: return {}
	check(e.has("wage_day") and int(e["wage_day"]) < day and int(e["day"]) < day, "former-worker fixture needs an actual unprocessed native day, not an already-accrued cursor")
	check(float(farm["owed"]) == 0.0 and farm.get("wage_claims", {}).is_empty(), "selected native farm starts without an unrelated inherited wage debt")
	if fails > 0: return {}
	Families.set_job(e, creditor, int(farm["id"]), 1)
	Families.reassign(e, creditor)
	check(int(creditor["jobs"].get(str(int(farm["id"])), 0)) == 1 and not Families.assignments_stale(creditor), "the former worker must actually hold one balanced native farm assignment before earning wages")
	if fails > 0: return {}
	# The real market day accrues attendance and advances this economy's own clock.
	TownEcon.daily_pass(Game, town, day, false)
	check(int(e["day"]) == day and int(e["wage_day"]) == day, "native daily pass must actually establish the batch day and its wage cursor")
	if not _within_budget() or fails > 0: return {}
	var retained_debt: float = float(farm["owed"])
	var retained_claims: Dictionary = (farm.get("wage_claims", {}) as Dictionary).duplicate(true)
	check(retained_debt > 0.0 and is_equal_approx(float(retained_claims.get(str(int(creditor["id"])), 0.0)), wage),
		"retained debt is this actual worker's exact independently accrued day wage")
	# Remove actual newly produced grain rights from payroll backing before the departure.
	for family: Dictionary in e["fams"]:
		if not family.get("estate", false): HarvestClaims.transfer(e, "f:%d" % int(family["id"]), "f:0")
	pooled = NativeEconomy.pool(e)
	check(bool(pooled["ok"]), str(pooled.get("reason", "")))
	if fails > 0: return {}
	Families.set_job(e, creditor, int(farm["id"]), 0)
	Families.reassign(e, creditor)
	check(not Families.assignments_stale(creditor), "native departure restores the former worker's real idle assignment")
	check(float(farm["owed"]) == retained_debt and farm["wage_claims"] == retained_claims, "native departure preserves actually unpaid former-worker debt")
	var reserved: Dictionary = NativeEconomy.reserve_casual(town, e, [int(owner["id"]), int(worker["id"]), int(creditor["id"])], _deadline_msec)
	check(bool(reserved["ok"]), "actual other workers reserve casual places: " + str(reserved.get("reason", "")))
	if not bool(reserved["ok"]): return {}
	vault = reserved["vault"]
	Families.reassign(e, owner); Families.reassign(e, worker)
	var worker_spare: int = int(worker["idle"])
	check(worker_spare > 0 and Families.job_total(worker) == 0 and worker.get("cj", {}).is_empty(), "actual native worker has an idle civilian place before this batch")
	check(int(farm["workers"]) == 0 and int(farm["cap"]) == 1, "the actual one-place farm must still be empty immediately before owner funding")
	# match_idle scans every live household in native family order, even outside this batch.
	for family: Dictionary in e["fams"]:
		if int(family["id"]) >= int(worker["id"]): break
		if int(family["id"]) == int(owner["id"]) or family.get("gone", false) or family.get("estate", false): continue
		check(int(family["idle"]) == 0, "native farm fixture needs no earlier idle competitor for this exact worker; household %d" % int(family["id"]))
	check(int(owner["idle"]) == 0, "native farm owner works its actual holding instead of consuming the intended hired vacancy")
	if fails > 0: return {}
	return {"e": e, "pair": pair, "identities": identities, "setup_coin": setup_coin, "farm": int(farm["id"]),
		"creditor": int(creditor["id"]), "wage": wage, "debt": retained_debt, "claims": retained_claims, "worker_spare": worker_spare}

func fixture(town: Dictionary, original: Dictionary, mode: String, owner_late: bool, half: int) -> void:
	if not _within_budget(): return
	var key: String = "%s:%d:%s" % [town["id"], half, owner_late]
	if not _prepared.has(key):
		var prepared: Dictionary = _prepare(town, original, owner_late, half)
		if prepared.is_empty(): return
		_prepared[key] = prepared
	# Modes share identical native setup, each on its own deep copy.
	var prepared: Dictionary = _prepared[key]
	var e: Dictionary = (prepared["e"] as Dictionary).duplicate(true); town["econ"] = e
	var pair: Dictionary = prepared["pair"]
	var day: int = int(pair["day"])
	var owner: Dictionary = e["fams"][int(pair["owner"])]
	var worker: Dictionary = e["fams"][int(pair["worker"])]
	var creditor: Dictionary = e["fams"][int(prepared["creditor"])]
	var farm: Dictionary = e["biz"][int(prepared["farm"])]
	var vault: Dictionary = e["fams"][0]
	var identities: Dictionary = prepared["identities"]
	var setup_coin: float = float(prepared["setup_coin"])
	var wage: float = float(prepared["wage"])
	var retained_debt: float = float(prepared["debt"])
	var retained_claims: Dictionary = prepared["claims"]
	var worker_spare: int = int(prepared["worker_spare"])
	if mode == "funded":
		var food_reserve: float = maxf(5.0 * TownEcon.COIN, EconomyRules.essential_food_cost(e, maxf(0.0, 14.0 - float(owner["store"]["food"])) * float(Families.daily_rates(e, owner)["food"])))
		check(NativeEconomy.move(vault, "purse", owner, "purse", retained_debt + wage * 8.0 + food_reserve),
			"ordinary owner turn receives only the actual debt, payroll bill and native food reserve from another holder")
	elif mode == "no_offer":
		# Relinquish the real holding to the actual estate, then retire that native farm.
		NativeEconomy.transfer_holding(e, owner)
		Businesses.town_inherits(farm)
		check(bool(farm["closed"]) and int(farm["owner"]) == -1, "actual relinquished farm is retired by its native lifecycle")
	Businesses.rebuild_open(e)
	check(Businesses.takeable(farm, e) == 0, "actually accrued debt makes the empty old farm till unavailable for hiring")
	check(absf(cash(e) - setup_coin) < 0.00001, "native plots, reservations and payroll preparation conserve actual coin")
	if fails > 0: return
	var before: float = cash(e)
	var drain: float = 0.0
	var paydays: Dictionary = {}
	for family: Dictionary in e["fams"]: paydays[int(family["id"])] = family["last"]
	for index: int in range(day % 7 + half * 7, (e["fams"] as Array).size(), 14):
		var family: Dictionary = e["fams"][index]
		if family.get("gone", false) or family.get("estate", false): continue
		drain += float(family["purse"]) * (1.0 - pow(1.0 - float(Barge.B()["coin"]["drain"]), clampf(float(day) - float(family["last"]), 1.0, 60.0)))
	TownEcon.family_batch(Game, town, day, half)
	check(absf(cash(e) - before + drain) < 0.00001, "batch moves existing cash only after exactly the native participants' ordinary purse drain")
	check(float(owner["last"]) == day, "the existing batch owner has its ordinary payday")
	for family: Dictionary in e["fams"]:
		var fid: int = int(family["id"])
		var turns: bool = fid % 14 == day % 7 + half * 7 and not family.get("gone", false) and not family.get("estate", false)
		check(float(family["last"]) == (float(day) if turns else float(paydays[fid])), "only actual batch participants advance their ordinary payday; household %d" % fid)
	check(float(farm["owed"]) == retained_debt and farm["wage_claims"] == retained_claims, "matching preserves exact genuinely earned debt and adds no prior wages")
	check(float(worker.get("wage_receipts", 0.0)) == 0.0, "new farm hand receives no backdated wages")
	if mode == "funded":
		check(int(farm["cap"]) == 1, "ordinary owner harvest turn keeps exactly one actual field vacancy")
		check(int(farm["workers"]) == 1 and int(worker["jobs"].get(str(int(farm["id"])), 0)) == 1 and int(worker["idle"]) == worker_spare - 1,
			"completed batch fills the genuinely funded private offer with the actual earlier/later worker")
		check(float(farm["till"]) >= retained_debt + 2.0 * wage, "new hire stays backed after actually earned obligations")
	else:
		check(int(farm["workers"]) == 0 and int(worker["idle"]) == worker_spare, "unfunded or retired farm never manufactures employment")
		check(Businesses.takeable(farm, e) == 0, "unfunded or retired batch has no genuine offer")
	check(not Families.assignments_stale(owner) and not Families.assignments_stale(worker), "batch preserves real adult assignment counts")
	var retained_people: Dictionary = {}
	for family: Dictionary in [owner, worker]:
		for person: Array in Persons.pp(family) + Persons.kp(family):
			var uid: String = str(Persons.g(person, Persons.PERSON_UID, ""))
			retained_people[uid] = true
			if identities.has(uid): check(identities[uid] == [float(person[3]), str(Persons.g(person, Persons.MOTHER_UID, "")), str(Persons.g(person, Persons.FATHER_UID, ""))], "native batch retains actual birthdates and parent links")
	for uid: String in identities: check(retained_people.has(uid), "every original native fixture person survives this bounded hiring case")
	var purse: float = cash(e); var last: float = float(worker["last"]); var debt: float = float(farm["owed"])
	Families.match_idle(e)
	check(cash(e) == purse and float(worker["last"]) == last and float(farm["owed"]) == debt, "repeated matching cannot move coins, advance payday or alter earned debt")
	if mode == "funded":
		WageClaims.accrue_day(e, day + 1)
		var paid: float = float(WageClaims.pay_family(e, worker)[0])
		check(absf(paid - wage) < 0.00001, "next actual worked day earns exactly one hand's native wage")
		check(absf(cash(e) - purse) < 0.00001 and float(farm["owed"]) == debt and farm["wage_claims"] == retained_claims, "real wage payout conserves cash and exact older-worker debt")
	print("FARM_BATCH_CASE ", JSON.stringify({"culture": e["culture"], "day": day, "econ_day": e["day"], "mode": mode, "half": half, "owner_late": owner_late, "owner": owner["id"], "worker": worker["id"], "creditor": creditor["id"], "farm": farm["id"], "debt": retained_debt, "claims": retained_claims}))

func run(_tree: SceneTree) -> int:
	_deadline_msec = Time.get_ticks_msec() + 150000
	Game.new_game(901)
	var native: Dictionary = NativeCultures.towns(Game)
	check(bool(native.get("ok", false)), "native culture fixtures: " + str(native.get("reason", "")))
	if not bool(native.get("ok", false)): return fails
	# Admit fixture prerequisites before exercising hiring. Use the smallest
	# generated town with no earlier participant competing for the exact worker.
	for culture: String in native["towns"]:
		var town: Dictionary = {}
		for candidate: Dictionary in Game.world["towns"].values():
			if not TownEcon.has_econ(candidate) or str(candidate["econ"]["culture"]) != culture or not _pairs_ready(candidate["econ"]): continue
			if town.is_empty() or int(candidate["econ"]["pop"]) < int(town["econ"]["pop"]): town = candidate
		# Missing, unsuitable or larger towns use native hamlet inputs and bounded,
		# deterministic generator seeds; no household rows are edited or moved.
		for attempt: int in (16 if town.is_empty() or int(town["size"]) > 0 else 0):
			town = (native["towns"][culture] as Dictionary).duplicate(true)
			town["id"] = "farm_batch_" + culture
			town["size"] = 0; town.erase("econ")
			for field: String in ["shop", "recruits", "contracts", "roads", "neighbours"]: town[field] = []
			for field: String in ["crafters", "healer", "prices", "material_prices"]: town[field] = {}
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = hash([Game.world["seed"], culture, "native-farm-batch-hamlet", attempt])
			Economy.make_crafters(town, rng); Economy.roll_prices(town, rng)
			EconGen.generate(Game.world, town, rng); Plots.layout(Game.world, town)
			check(str(town["econ"]["culture"]) == culture and not Plots.needs_layout(town["econ"]), "native hamlet retains its generated culture and complete physical plots")
			if fails > 0: return fails
			if _pairs_ready(town["econ"]): break
		check(not town.is_empty() and _pairs_ready(town["econ"]), "native fixture prerequisites cover every order and half for " + culture)
		if fails > 0: return fails
		native["towns"][culture] = town
	var originals: Dictionary = {}
	for culture: String in native["towns"]: originals[culture] = (native["towns"][culture]["econ"] as Dictionary).duplicate(true)
	Game.wait_save()
	while not Game.world.get("work", []).is_empty():
		if not _within_budget(): return fails
		CampaignWorld.work_slice(Game, 8000)
	# Advance the real clock only as far as the selected native batch days.
	# Each isolated economy closes its preceding market days in fixture().
	var through_day: int = int(Game.day) + 1
	for culture: String in originals:
		for half: int in [0, 1]:
			for owner_late: bool in ([true, false] if half == 0 else [true]):
				var pair: Dictionary = _native_pair(originals[culture], half, owner_late)
				check(not pair.is_empty(), "native batch selection covers %s half %d owner_late %s" % [culture, half, owner_late])
				if pair.is_empty(): return fails
				through_day = maxi(through_day, int(pair["day"]))
	var from_day: float = Game.day
	Game.advance_time(float(through_day) - from_day, false, 0, 1)
	check(is_equal_approx(Game.day, float(through_day)), "farm batch fixture actually advances to its native scheduled days")
	if fails > 0: return fails
	var seen: Dictionary = {}
	for culture: String in native["towns"]:
		var town: Dictionary = native["towns"][culture]
		seen[culture] = true
		for mode: String in ["funded", "unfunded", "no_offer"]:
			for half: int in [0, 1]:
				fixture(town, originals[culture], mode, true, half)
				if fails > 0 or not _within_budget(): return maxi(1, fails)
		fixture(town, originals[culture], "funded", false, 0)
		if fails > 0 or not _within_budget(): return maxi(1, fails)
	var actual_cultures: Array = seen.keys(); actual_cultures.sort()
	var expected_cultures: Array = TownEcon.data()["cultures"].keys(); expected_cultures.sort()
	check(actual_cultures == expected_cultures, "private batch regression covers every culture: " + str(actual_cultures))
	print("PRIVATE FARM BATCH HIRING checks=", checks, " failures=", fails)
	return fails
