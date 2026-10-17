extends RefCounted

var fails := 0
var checks := 0

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1; printerr("FAIL: ", msg)

func cash(e: Dictionary) -> float:
	var total := float(e["treasury"])
	for f in e["fams"]: total += float(f["purse"])
	for b in e["biz"]: total += float(b["till"])
	return total

func civil_balance(e: Dictionary, label: String) -> void:
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		check(not Families.assignments_stale(f), label + ": civilian assignments balance")
		check(Families.job_total(f) <= Families.adults(f) - Families.serving(f), label + ": serving people cannot take civilian jobs")

func fixture(town: Dictionary, original: Dictionary, reverse_units: bool, reverse_waiters: bool, funded: bool) -> void:
	var e: Dictionary = original.duplicate(true)
	town["econ"] = e
	# Synthetic job-only fixture, using actual generated household adults and
	# register people. Clear the physical land/herd records as well as summaries.
	e.erase("plots"); e.erase("hd"); e["herd"] = {}
	var choices := []
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or Families.adults(f) < 3: continue
		var adults_here: Array = Persons.pp(f).filter(func(p): return int(p[6]) == 0 and not Persons.AWAY.has(String(p[4])))
		if adults_here.size() >= 3: choices.append(f)
	check(choices.size() >= 3, "generated culture has three real adult households")
	if choices.size() < 3: return
	var held: Dictionary = choices[0]
	var waiter: Dictionary = choices[2] if reverse_waiters else choices[1]
	for f in e["fams"]:
		for key in f["jobs"].keys(): Families.set_job(e, f, int(key), 0)
		Shelter.release_casual(e, f)
		f["owns"] = []; f["keeps"] = []; f["land"] = {}; f["herd"] = {}; f["farm"] = -1
		f["ox"] = 0
		f["serve"] = {}; f["hands"] = 0; f["idle"] = Families.adults(f)
		f["gone"] = f != held and f != waiter
	for b in e["biz"]: b["closed"] = true; b["kw"] = 0
	e["cjcap"] = {}; e["cjused"] = {}
	var offer := Businesses._row(e, "carpenter", -1, Families.adults(held), TownEcon.data())
	offer["wage"] = 10.0; offer["till"] = 10000.0 if funded else 0.0
	Families.set_job(e, held, int(offer["id"]), Families.adults(held))
	held["idle"] = 0
	# These are real register adults. Two belong to one household; one belongs
	# to the waiting household, which can be reassigned before places release.
	var units := []
	for row in [[waiter, 1], [held, 2]]:
		var f: Dictionary = row[0]
		var pp: Array = Persons.pp(f).filter(func(p): return int(p[6]) == 0 and not Persons.AWAY.has(String(p[4])))
		for n in int(row[1]):
			var p: Array = pp[n]
			var u := Unit.new(); u.uid = 900000 + int(f["id"]) * 10 + n; u.family = int(f["id"])
			p[4] = "reserve"; p[5] = u.uid; units.append(u)
	if reverse_units: units.reverse()
	var wb := Militia.band_of(Game, String(town["id"]))
	wb["units"] = units
	WageClaims.accrue_day(e, int(e["day"]) + 1)
	var before_cash := cash(e)
	var last := [held["last"], waiter["last"]]
	TownDefence.set_muster(Game, town, false, true)
	check(Families.serving(held) == 2 and Families.serving(waiter) == 1, "drill keeps every real service transition")
	check(Families.job_total(waiter) == (mini(2, Families.adults(waiter) - 1) if funded else 0), "waiting civilians take released funded jobs in either force order")
	check(Businesses.takeable(offer) == 0, "released offers match or remain genuinely unfunded")
	civil_balance(e, "drill")
	check(absf(cash(e) - before_cash) < 0.00001, "matching preserves actual coins")
	check(held["last"] == last[0] and waiter["last"] == last[1], "matching leaves household paydays unchanged")
	check(float(waiter.get("wage_receipts", 0)) == 0.0, "newly hired civilians receive no preceding drill-day wages")
	WageClaims.accrue_day(e, int(e["day"]) + 2)
	check(float(offer["owed"]) > 0.0, "no-op fixture includes actual earned wage claims")
	var snapshot := JSON.stringify(e)
	TownDefence.set_muster(Game, town, false, true)
	check(JSON.stringify(e) == snapshot, "same drill request leaves coins, claims and assignments identical")
	TownDefence.set_muster(Game, town, true, false)
	check(JSON.stringify(e) == snapshot, "drill to muster retains existing service assignments")
	TownDefence.set_muster(Game, town, false, false)
	check(Families.serving(held) == 0 and Families.serving(waiter) == 0, "return releases each militia adult")
	civil_balance(e, "return")
	check(absf(cash(e) - before_cash) < 0.00001, "return preserves actual coins")
	snapshot = JSON.stringify(e)
	TownDefence.set_muster(Game, town, false, false)
	check(JSON.stringify(e) == snapshot, "repeated return leaves economy identical")
	TownDefence.set_muster(Game, town, true, false)
	check(Families.serving(held) == 2 and Families.serving(waiter) == 1, "direct muster counts all household units")
	civil_balance(e, "muster")
	check(absf(cash(e) - before_cash) < 0.00001, "muster preserves actual coins")

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(2026)
	var tested := {}
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	for tid in ids:
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town): continue
		var culture := String(town["econ"]["culture"])
		if tested.has(culture): continue
		tested[culture] = true
		var original: Dictionary = town["econ"].duplicate(true)
		for reverse_units in [false, true]:
			for reverse_waiters in [false, true]:
				for funded in [false, true]: fixture(town, original, reverse_units, reverse_waiters, funded)
	check(tested.size() == TownEcon.data()["cultures"].size(), "all registered economy cultures are exercised")
	print("MILITIA HIRING cultures=", tested.keys(), " checks=", checks, " failures=", fails)
	return fails
