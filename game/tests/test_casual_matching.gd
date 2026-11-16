extends RefCounted
const NativeCultures = preload("res://tests/class_d_culture_fixtures.gd")
const NativeEconomy = preload("res://tests/class_d_native_economy.gd")
var checks: int = 0
var fails: int = 0
var _deadline_msec: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	check(false, "native casual fixtures reached their supplied deadline; incomplete cases fail")
	return false

func money(e: Dictionary) -> float:
	return NativeEconomy.money(e)

## Snapshot actual holders and non-assignment books, not just their sum.
func _unchanged(e: Dictionary) -> String:
	var rows: Array = []
	for family: Dictionary in e["fams"]:
		rows.append([family["id"], family["purse"], family["store"].duplicate(true), family["last"],
			family.get("cjearned", {}).duplicate(true), family.get("wage_receipts", 0.0)])
	var books: Array = []
	for business: Dictionary in e["biz"]:
		books.append([business["id"], business["till"], business["owed"], business.get("wage_claims", {}).duplicate(true)])
	var goods: Dictionary = {}
	for key: String in ["stock", "barn", "granary", "hh", "plots", "hd", "land", "herd", "treasury", "farm_till", "land_fund", "wage_day", "sanitation"]:
		if e.has(key): goods[key] = e[key]
	return JSON.stringify([rows, books, goods])

func _reservations(e: Dictionary) -> bool:
	for job: String in e["cjcap"]:
		if absf(NativeEconomy.reservations(e, job) - float(e["cjused"].get(job, 0))) > 0.000001: return false
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false): continue
		if Families.assignments_stale(family): return false
		for pid: String in family.get("child_cj", {}):
			var person: Array = Persons.by_pid(family, int(pid))
			if person.is_empty() or not Shelter.cleanup_child_eligible(e, person, Game.day, family): return false
	return true

## All capacity is native. Only existing holdings and coin change holders.
func _prepare(town: Dictionary) -> Dictionary:
	var e: Dictionary = (town["econ"] as Dictionary).duplicate(true)
	var before: float = money(e)
	var pooled: Dictionary = NativeEconomy.pool(e)
	if not bool(pooled["ok"]): return pooled
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false): continue
		HarvestClaims.transfer(e, "f:%d" % int(family["id"]), "f:0")
		NativeEconomy.vacate(e, family)
		NativeEconomy.transfer_holding(e, family)
	pooled = NativeEconomy.pool(e)
	if not bool(pooled["ok"]): return pooled
	Shelter.weekly(Game, town, e)
	for family: Dictionary in e["fams"]:
		if not family.get("gone", false) and not family.get("estate", false): Families.reassign(e, family)
	# A one-adult household before the target gets real field work, not a gone/idle override.
	var physical: Variant = load("res://tests/farm_fixture_tools.gd").new()
	var target: Dictionary = {}
	for family: Dictionary in e["fams"]:
		if not _within_budget(): return {"ok": false, "reason": "casual setup budget"}
		if family.get("gone", false) or family.get("estate", false): continue
		if int(family["idle"]) >= 2:
			target = family
			break
		for acre: int in 64:
			if int(family["idle"]) == 0: break
			if not physical.grain(e, family, 1): break
			Families.reassign(e, family)
		if int(family["idle"]) != 0: return {"ok": false, "reason": "earlier real household needs productive work before a two-adult matching target"}
	if target.is_empty(): return {"ok": false, "reason": "native casual fixture needs a first idle household with two actual spare adults"}
	pooled = NativeEconomy.pool(e)
	if not bool(pooled["ok"]): return pooled
	if absf(money(e) - before) > 0.00001 or not _reservations(e):
		return {"ok": false, "reason": "native casual preparation must conserve coin and every adult/child assignment"}
	var excluded: Array[int] = [int(target["id"])]
	var cleanup_family: int = -1
	var cleanup_pid: int = -1
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false): continue
		for person: Array in Persons.kp(family):
			if not Shelter.cleanup_child_eligible(e, person, Game.day, family): continue
			var illness: Array = Sickness.case_of(family, int(person[0]))
			if not illness.is_empty() and int(illness[Sickness.C_BED]) == 1 and Sickness.sick_phase(illness, Game.day): continue
			cleanup_family = int(family["id"]); cleanup_pid = int(person[0]); break
		if cleanup_family >= 0: break
	if cleanup_family < 0: return {"ok": false, "reason": "native fractional cleanup needs an existing eligible healthy child"}
	if not excluded.has(cleanup_family): excluded.append(cleanup_family)
	return {"ok": true, "econ": e, "target": int(target["id"]), "excluded": excluded, "cleanup_family": cleanup_family, "cleanup_pid": cleanup_pid}

## Find whole real households whose target-only reservations total exactly one/two.
## Releasing them with the native path cannot free a competing kind of casual job.
func _donors(e: Dictionary, job: String, places: int, target: int) -> Array[int]:
	var chosen: Array[int] = []
	if places == 0: return chosen
	var singles: Array[int] = []
	for family: Dictionary in e["fams"]:
		if int(family["id"]) <= target or family.get("gone", false) or family.get("estate", false): continue
		var shifts: Dictionary = family.get("cj", {})
		if shifts.size() != 1 or not shifts.has(job): continue
		var count: int = int(shifts[job])
		if _donor_spare(family) != count or Families.assignments_stale(family): continue
		if count == places: chosen.append(int(family["id"])); return chosen
		if count == 1: singles.append(int(family["id"]))
	if places == 2 and singles.size() >= 2: chosen.assign(singles.slice(0, 2))
	return chosen

## Count every adult outside land/keeper work, including retained regular jobs.
func _donor_spare(family: Dictionary) -> int:
	var spare: int = int(family["idle"]) + Families.job_total(family)
	for count: Variant in (family.get("cj", {}) as Dictionary).values(): spare += int(count)
	return spare

## Report the actual rejection guard and native funded offers; never substitute a reservation.
func _donor_reject(stage: String, e: Dictionary, family: Dictionary, job: String, places: int, steps: int, reason: String = "") -> void:
	var available: Dictionary = {}
	for offer: String in e["cjcap"]: available[offer] = Shelter.available_casual(e, offer)
	print("CASUAL_DONOR_REJECT ", JSON.stringify({"stage": stage, "culture": e["culture"], "id": family["id"],
		"job": job, "places": places, "idle": family["idle"], "hands": family["hands"],
		"shifts": family.get("cj", {}), "jobs": family.get("jobs", {}), "keepers": family.get("keeps", []),
		"adults": Families.adults(family), "serving": Families.serving(family), "spare": _donor_spare(family),
		"used": e["cjused"], "funded_available": available,
		"field_steps": steps, "stale": Families.assignments_stale(family), "reason": reason}))

## Quote the actual native offers after this holder leaves and its payer is funded.
## Scan cheap reservation orders before doing any physical donor construction.
func _window_candidates(original: Dictionary, job: String, places: int, target: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var payer: String = str(TownEcon.data()["casual_jobs"][job]["payer"])
	for holder: Dictionary in original["fams"]:
		if int(holder["id"]) <= target or holder.get("gone", false) or holder.get("estate", false): continue
		if int(holder.get("cj", {}).get(job, 0)) < places or _donor_spare(holder) < places: continue
		var offers: Dictionary = original.duplicate(true)
		var released: Dictionary = offers["fams"][int(holder["id"])]
		Shelter.release_casual(offers, released)
		if not _fund(offers, job, float(offers["cjcap"][job])): continue
		if Shelter.available_casual(offers, job) < places: continue
		var safe: bool = true
		for other: String in offers["cjcap"]:
			if other == job or str(TownEcon.data()["casual_jobs"][other]["payer"]) != payer: continue
			if Barge.casual_wage(offers, other) < Barge.casual_wage(offers, job): continue
			if Shelter.available_casual(offers, other) > 0:
				safe = false
				print("CASUAL_DONOR_SKIP ", original["culture"], " job=", job, " places=", places,
					" id=", holder["id"], " reason=funded_co_payer_offer competitor=", other,
					" available=", Shelter.available_casual(offers, other))
				break
		if safe: candidates.append(holder)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_spare: int = _donor_spare(a)
		var b_spare: int = _donor_spare(b)
		return a_spare < b_spare if a_spare != b_spare else int(a["id"]) < int(b["id"]))
	return candidates

## Divide a concentrated native reservation before seeking a small target-only donor.
## Other households must retain enough co-payer shifts to block their funded offers.
func _split_window_reservations(town: Dictionary, prepared: Dictionary, original: Dictionary, job: String, places: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var payer: String = str(TownEcon.data()["casual_jobs"][job]["payer"])
	var bill: float = 7.0 * Barge.casual_wage(original, job) * float(original["cjcap"][job])
	var spare_limit: int = 2147483647
	var constrained: bool = false
	for other: String in original["cjcap"]:
		if other == job or str(TownEcon.data()["casual_jobs"][other]["payer"]) != payer: continue
		if Barge.casual_wage(original, other) < Barge.casual_wage(original, job): continue
		var funded: int = maxi(0, int(floor(bill / maxf(0.01, 7.0 * Barge.casual_wage(original, other)) + 0.00001)))
		if funded <= 0 or int(original["cjcap"][other]) <= 0: continue
		spare_limit = mini(spare_limit, int(original["cjcap"][other]) - mini(int(original["cjcap"][other]), funded))
		constrained = true
	if not constrained:
		return {"ok": false, "reason": "native reservation split found no funded co-payer competitor"}
	# Allow the target shifts alongside the competing tail, then verify the
	# actual split through native offers instead of assuming how ties sort.
	var split_limit: int = spare_limit + int(original["cjcap"][job])
	var excluded: Array[int] = []
	excluded.assign(prepared["excluded"])
	var physical: Variant = load("res://tests/farm_fixture_tools.gd").new()
	for holder: Dictionary in original["fams"]:
		var id: int = int(holder["id"])
		if id <= int(prepared["target"]) or holder.get("gone", false) or holder.get("estate", false) or excluded.has(id): continue
		if int(holder.get("cj", {}).get(job, 0)) < places or _donor_spare(holder) < places: continue
		var e: Dictionary = original.duplicate(true)
		var family: Dictionary = e["fams"][id]
		# These are desired field obligations, never writes to adult/job counts.
		# Quote the resulting native assignments; do not assume an equal-pay tie.
		for desired: int in range(mini(maxi(places, split_limit), _donor_spare(holder)), places - 1, -1):
			if not _within_budget(): return {"ok": false, "reason": "native reservation split exceeded its budget"}
			var pooled: Dictionary = NativeEconomy.pool(e)
			if not bool(pooled["ok"]): return pooled
			for household: Dictionary in e["fams"]:
				if not household.get("gone", false) and not household.get("estate", false): NativeEconomy.vacate(e, household)
			var field_steps: int = 0
			for acre: int in 64:
				if not _within_budget(): return {"ok": false, "reason": "native split field work exceeded its budget"}
				var excess: int = _donor_spare(family) - desired
				if excess <= 0: break
				var acres: int = maxi(1, int(floor(float(excess) * minf(
					float(TownEcon.data()["land"]["acres_per_hand"]), float(TownEcon.data()["land"]["acres_no_ox"])))))
				if not physical.grain(e, family, acres) and not physical.grain(e, family, 1): break
				field_steps += 1
				Families.reassign(e, family)
			if _donor_spare(family) != desired or Families.assignments_stale(family): continue
			var local_town: Dictionary = town.duplicate(false)
			local_town["econ"] = e
			var reserved: Dictionary = NativeEconomy.reserve_casual(local_town, e, excluded, _deadline_msec)
			if not bool(reserved["ok"]): return reserved
			var candidates: Array[Dictionary] = _window_candidates(e, job, places, int(prepared["target"]))
			print("CASUAL_SPLIT ", e["culture"], " job=", job, " id=", id, " desired_spare=", desired,
				" actual_spare=", _donor_spare(family), " shifts=", family.get("cj", {}),
				" field_steps=", field_steps, " safe_candidates=", candidates.size(), " split_ms=", Time.get_ticks_msec() - started)
			if candidates.is_empty(): continue
			if not _reservations(e) or absf(money(e) - money(original)) > 0.00001:
				return {"ok": false, "reason": "native split must preserve every assignment and coin"}
			return {"ok": true, "econ": e}
	return {"ok": false, "reason": "bounded native field transfers could not split a usable target reservation"}

## Build a target-only donor from a safe native holder through productive farm work.
## Protect its exact reservation while other real households refill the remaining places.
func _construct_window(town: Dictionary, prepared: Dictionary, original: Dictionary, job: String, places: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var attempts: int = 0
	var target: int = int(prepared["target"])
	var before: float = money(original)
	var physical: Variant = load("res://tests/farm_fixture_tools.gd").new()
	var baseline: Dictionary = original
	var candidates: Array[Dictionary] = _window_candidates(baseline, job, places, target)
	if candidates.is_empty():
		var split: Dictionary = _split_window_reservations(town, prepared, original, job, places)
		if not bool(split["ok"]): return split
		baseline = split["econ"]
		candidates = _window_candidates(baseline, job, places, target)
	for candidate: Dictionary in candidates:
		if not _within_budget(): return {"ok": false, "reason": "native donor construction exceeded its budget"}
		var id: int = int(candidate["id"])
		if id <= target or candidate.get("gone", false) or candidate.get("estate", false): continue
		attempts += 1
		var e: Dictionary = baseline.duplicate(true)
		var family: Dictionary = e["fams"][id]
		NativeEconomy.vacate(e, family)
		# The target shifts are its own; no tied/better co-payer job was reopened.
		var field_steps: int = 0
		for acre: int in 64:
			if not _within_budget(): return {"ok": false, "reason": "native donor field work exceeded its budget"}
			var excess: int = _donor_spare(family) - places
			if excess <= 0: break
			# Even without draft animals this many existing acres need at most
			# the excess adults; native reassignment still decides the exact count.
			var acres: int = maxi(1, int(floor(float(excess) * minf(
				float(TownEcon.data()["land"]["acres_per_hand"]), float(TownEcon.data()["land"]["acres_no_ox"])))))
			if not physical.grain(e, family, acres) and not physical.grain(e, family, 1): break
			field_steps += 1
			Families.reassign(e, family)
		if int(family["idle"]) != places or _donor_spare(family) != places or Families.assignments_stale(family):
			_donor_reject("r7_adult_count", e, family, job, places, field_steps)
			continue
		if not _fund(e, job, float(e["cjcap"][job])):
			return {"ok": false, "reason": "existing coin cannot fund the constructed native donor"}
		Families.reassign(e, family)
		var shifts: Dictionary = family.get("cj", {})
		if shifts.size() != 1 or int(shifts.get(job, 0)) != places or _donor_spare(family) != places or Families.assignments_stale(family):
			_donor_reject("r7_target_only", e, family, job, places, field_steps)
			continue
		var excluded: Array[int] = []
		excluded.assign(prepared["excluded"])
		excluded.append(id)
		var local_town: Dictionary = town.duplicate(false)
		local_town["econ"] = e
		var reserved: Dictionary = NativeEconomy.reserve_casual(local_town, e, excluded, _deadline_msec)
		if not bool(reserved["ok"]):
			_donor_reject("r6_refill", e, family, job, places, field_steps, str(reserved.get("reason", "")))
			continue
		var donors: Array[int] = _donors(e, job, places, target)
		if donors.is_empty() or not _reservations(e):
			_donor_reject("r6_reservation_books", e, family, job, places, field_steps)
			continue
		if absf(money(e) - before) > 0.00001:
			return {"ok": false, "reason": "native donor construction must conserve every coin"}
		print("CASUAL_DONOR ", e["culture"], " job=", job, " places=", places, " attempts=", attempts,
			" donors=", donors, " source_shifts=", candidate.get("cj", {}), " field_steps=", field_steps, " construct_ms=", Time.get_ticks_msec() - started)
		return {"ok": true, "econ": e, "target": target, "donors": donors, "cleanup_family": prepared["cleanup_family"], "cleanup_pid": prepared["cleanup_pid"]}
	print("CASUAL_DONOR ", original["culture"], " job=", job, " places=", places, " rejected_attempts=", attempts, " construct_ms=", Time.get_ticks_msec() - started)
	return {"ok": false, "reason": "no native target-only holder could supply the exact donor workforce"}

## Select one usable native reservation order per culture, then freeze/reuse it.
func _windows(town: Dictionary, prepared: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	var original: Dictionary = prepared["econ"]
	var target: int = int(prepared["target"])
	var excluded: Array[int] = []
	excluded.assign(prepared["excluded"])
	for rotation: int in (original["fams"] as Array).size():
		if not _within_budget(): return {"ok": false, "reason": "native reservation search exceeded its budget"}
		var reservation_started: int = Time.get_ticks_msec()
		var e: Dictionary = original.duplicate(true)
		var local_town: Dictionary = town.duplicate(false); local_town["econ"] = e
		var reserved: Dictionary = NativeEconomy.reserve_casual(local_town, e, excluded, _deadline_msec, rotation)
		if not bool(reserved["ok"]): return reserved
		print("CASUAL_RESERVE ", e["culture"], " rotation=", rotation, " reservation_ms=", Time.get_ticks_msec() - reservation_started)
		# Construction can first divide a concentrated native reservation.
		# Do not require its finished donor partition before doing that work.
		print("CASUAL_BASELINE ", e["culture"], " rotation=", rotation, " selected_ms=", Time.get_ticks_msec() - reservation_started)
		for job: String in ["street_sweeper", "night_soil_man"]:
			for places: int in [0, 2, 1]:
				var window_started: int = Time.get_ticks_msec()
				var key: String = "%s:%d" % [job, places]
				if int(e["cjcap"].get(job, 0)) < places: continue
				if places == 1 and not found.has("%s:2" % job): continue
				var basis: Dictionary = found["%s:2" % job]["econ"] if places == 1 else e
				var donors: Array[int] = _donors(basis, job, places, target)
				var source: String = "native_full" if places == 0 else "existing"
				if places > 0 and donors.is_empty():
					var constructed: Dictionary = _construct_window(town, prepared, basis, job, places)
					if not bool(constructed["ok"]): return constructed
					found[key] = constructed
					source = "constructed"
				else:
					# Constructors and _scenario copy before changing a frozen state.
					found[key] = {"econ": basis, "target": target, "donors": donors, "cleanup_family": prepared["cleanup_family"], "cleanup_pid": prepared["cleanup_pid"]}
				print("CASUAL_WINDOW ", e["culture"], " job=", job, " places=", places,
					" donors=", found[key]["donors"], " source=", source, " rotation=", rotation,
					" window_ms=", Time.get_ticks_msec() - window_started)
		if found.size() == 6: return {"ok": true, "windows": found}
		break
	return {"ok": false, "reason": "native full reservations need genuine target-only household releases of one AND two adults for both sanitation jobs; found " + str(found.keys())}

## Exact native payer bill, with a matching estate debit and a real customer food reserve.
func _fund(e: Dictionary, job: String, shares: float) -> bool:
	var pooled: Dictionary = NativeEconomy.pool(e)
	if not bool(pooled["ok"]): return false
	var vault: Dictionary = pooled["vault"]
	var bill: float = Barge.casual_wage(e, job) * 7.0 * shares
	if str(TownEcon.data()["casual_jobs"][job]["payer"]) == "treasury":
		return NativeEconomy.move(vault, "purse", e, "treasury", bill)
	for family: Dictionary in e["fams"]:
		if family.get("gone", false) or family.get("estate", false): continue
		var keep: float = float(Families.daily_rates(e, family)["food"]) * float(e["price"].get("grain", 1.0)) * 7.0
		return NativeEconomy.move(vault, "purse", family, "purse", bill + keep)
	return false

func _scenario(window: Dictionary, job: String, places: int, occupied: float) -> Dictionary:
	var e: Dictionary = (window["econ"] as Dictionary).duplicate(true)
	var target: int = int(window["target"])
	var cap: int = int(e["cjcap"][job])
	for id: int in window["donors"]:
		var family: Dictionary = e["fams"][id]
		Shelter.release_casual(e, family)
		Families.reassign(e, family)
	if absf(float(e["cjused"].get(job, 0)) - float(cap - places)) > 0.000001:
		return {"ok": false, "reason": "real donor releases did not leave the exact physical casual window"}
	if occupied > 0.0:
		if not is_equal_approx(float(Barge.B()["labour"]["kid_share"]), occupied):
			return {"ok": false, "reason": "native cleanup share must equal the original 0.2 case"}
		if not _fund(e, job, float(cap - places) + occupied):
			return {"ok": false, "reason": "native coin cannot fund the exact actual child reservation bill"}
		var children_before: int = 0
		for family: Dictionary in e["fams"]: children_before += (family.get("child_cj", {}) as Dictionary).size()
		Shelter.assign_child_cleanup(e, Game.day)
		var children_after: int = 0
		for family: Dictionary in e["fams"]: children_after += (family.get("child_cj", {}) as Dictionary).size()
		if children_after != children_before + 1 or str(e["fams"][int(window["cleanup_family"])].get("child_cj", {}).get(str(int(window["cleanup_pid"])), "")) != job:
			return {"ok": false, "reason": "fractional case needs exactly one actual eligible, healthy cleanup child"}
	var pooled: Dictionary = NativeEconomy.pool(e)
	if not bool(pooled["ok"]): return pooled
	if absf(float(e["cjused"].get(job, 0)) - float(cap - places) - occupied) > 0.000001 or not _reservations(e):
		return {"ok": false, "reason": "every exact full/fractional shift must still belong to actual native participants"}
	for other: String in e["cjcap"]:
		if other != job and absf(float(e["cjused"].get(other, 0)) - float(e["cjcap"][other])) > 0.000001:
			return {"ok": false, "reason": "native setup left a competing casual vacancy: " + other}
	for family: Dictionary in e["fams"]:
		if int(family["id"]) >= target: break
		if not family.get("gone", false) and not family.get("estate", false) and int(family["idle"]) > 0:
			return {"ok": false, "reason": "an earlier real idle household would compete with the required two-adult target"}
	return {"ok": true, "econ": e, "target": target}

func fixture(scenario: Dictionary, job: String, places: int, occupied: float, funded: bool) -> void:
	if not _within_budget(): return
	var e: Dictionary = (scenario["econ"] as Dictionary).duplicate(true)
	var family: Dictionary = e["fams"][int(scenario["target"])]
	var setup_coin: float = money(e)
	if funded:
		check(_fund(e, job, float(e["cjcap"][job])), "actual payer can fund the complete native capacity from existing coin")
	else:
		var pooled: Dictionary = NativeEconomy.pool(e)
		check(bool(pooled["ok"]), "unfunded payer money is transferred to an actual other holder")
	check(absf(money(e) - setup_coin) < 0.00001, "funded/unfunded setup conserves actual coin")
	var idle: int = int(family["idle"])
	check(idle >= 2 and family.get("cj", {}).is_empty(), "matching target retains its two actual idle adults before matching")
	for business: Dictionary in e["biz"]: check(Businesses.takeable(business, e) == 0, "casual-only case has no real funded regular offer")
	var expected: int = mini(idle, maxi(0, int(floor(float(places) - occupied + 0.00001)))) if funded else 0
	check(Shelter.available_casual(e, job) == (maxi(0, int(floor(float(places) - occupied + 0.00001))) if funded else 0), "both physical and funding gates retain the original full/fractional case")
	if fails > 0: return
	var before_money: float = money(e)
	var before_idle: int = int(e["idle_n"])
	var before_used: float = float(e["cjused"].get(job, 0))
	var caps: Dictionary = e["cjcap"].duplicate(true)
	var immutable: String = _unchanged(e)
	Families.match_idle(e)
	check(int(family.get("cj", {}).get(job, 0)) == expected, "funded casual-only offers reach the real first idle adults")
	check(int(family["idle"]) == idle - expected and int(e["idle_n"]) == before_idle - expected, "casual matching conserves exact household AND town idle adults")
	check(not Families.assignments_stale(family) and _reservations(e), "every adult and child retains an actual balanced assignment")
	check(absf(float(e["cjused"].get(job, 0)) - before_used - expected) < 0.000001, "actual full and fractional occupied shifts remain reserved")
	check(e["cjcap"] == caps and absf(money(e) - before_money) < 0.000001, "matching changes no native cap or total coin")
	check(_unchanged(e) == immutable, "matching moves no holder money, goods, paydays, earned wages, debt or sanitation service")
	var snapshot: String = JSON.stringify(e)
	Families.match_idle(e)
	check(JSON.stringify(e) == snapshot, "repeated matching with no available full shift is inert")
	print("CASUAL_CASE ", JSON.stringify({"culture": e["culture"], "job": job, "window": places, "occupied": occupied, "funded": funded, "cap": caps[job], "used_before": before_used, "expected": expected, "target": family["id"]}))

func run(_tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	_deadline_msec = Time.get_ticks_msec() + 150000
	WorldGen.gen_size = "normal"; Game.new_game(2026)
	print("CASUAL_SETUP world_ms=", Time.get_ticks_msec() - started)
	var native: Dictionary = NativeCultures.towns(Game)
	print("CASUAL_SETUP cultures_ms=", Time.get_ticks_msec() - started)
	check(bool(native.get("ok", false)), "native culture fixtures: " + str(native.get("reason", "")))
	if not bool(native.get("ok", false)): return fails
	var seen: Dictionary = {}
	for culture: String in native["towns"]:
		if not _within_budget(): return fails
		var town: Dictionary = native["towns"][culture]
		var prepared: Dictionary = _prepare(town)
		print("CASUAL_SETUP ", culture, " prepared_ms=", Time.get_ticks_msec() - started)
		check(bool(prepared["ok"]), culture + ": " + str(prepared.get("reason", "")))
		if not bool(prepared["ok"]): return fails
		var windows: Dictionary = _windows(town, prepared)
		print("CASUAL_SETUP ", culture, " windows_ms=", Time.get_ticks_msec() - started)
		check(bool(windows["ok"]), culture + ": " + str(windows.get("reason", "")))
		if not bool(windows["ok"]): return fails
		seen[culture] = true
		for job: String in ["street_sweeper", "night_soil_man"]:
			for spec: Array in [[1, 0.0], [1, 0.2], [2, 0.2], [0, 0.0]]:
				var scenario: Dictionary = _scenario(windows["windows"]["%s:%d" % [job, int(spec[0])]], job, int(spec[0]), float(spec[1]))
				check(bool(scenario["ok"]), culture + "/" + job + "/" + str(spec) + ": " + str(scenario.get("reason", "")))
				if not bool(scenario["ok"]): return fails
				for funded: bool in [false, true]:
					fixture(scenario, job, int(spec[0]), float(spec[1]), funded)
					if fails > 0 or not _within_budget(): return maxi(1, fails)
		print("CASUAL_SETUP ", culture, " cases_ms=", Time.get_ticks_msec() - started)
	var actual_cultures: Array = seen.keys(); actual_cultures.sort()
	var expected_cultures: Array = TownEcon.data()["cultures"].keys(); expected_cultures.sort()
	check(actual_cultures == expected_cultures, "all cultures use the same casual matcher: " + str(actual_cultures))
	print("CASUAL MATCHING checks=%d failures=%d" % [checks, fails])
	return fails
