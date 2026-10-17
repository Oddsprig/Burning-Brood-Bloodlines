extends RefCounted

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func cash(e: Dictionary, fac: Dictionary) -> float:
	var total := float(e["treasury"]) + float(fac["treasury"])
	for f in e["fams"]: total += float(f["purse"])
	for b in e["biz"]: total += float(b["till"])
	return total

func balance(e: Dictionary, ids: Array, label: String) -> void:
	var idle := 0
	for id in ids:
		var f: Dictionary = e["fams"][int(id)]
		check(not Families.assignments_stale(f), label + ": each real civilian adult has exactly one assignment")
		idle += int(f["idle"])
		var none := 0
		for place in Persons.work(e, f).values():
			if String(place.get("kind", "")) == "none": none += 1
		check(none == int(f["idle"]), label + ": person records agree with real idle adults")
	check(int(e["idle_n"]) == idle, label + ": town idle count agrees with households")

func fixture(source: Dictionary, mode: String, funded: bool, shared: bool, reverse_order: bool) -> void:
	var town: Dictionary = source.duplicate(true)
	var e: Dictionary = town["econ"]
	var fid := String(town["faction"])
	var tid := String(town["id"])
	var ids := []
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false) and Families.adults(f) >= 3 and Families.serving(f) == 0 \
				and Persons.pp(f).all(func(p): return int(p[6]) != 0 or String(p[4]) in ["", "hire"]):
			ids.append(int(f["id"]))
	check(ids.size() >= 2, "culture supplies two real civilian households")
	if ids.size() < 2: return
	if reverse_order: ids.reverse()
	ids = ids.slice(0, 2)
	# Job-only fixture: remove actual physical plots and herd records as well as mirrors.
	e["plots"] = {}; e.erase("hd"); Herds.H(e); e["herd"] = {}
	for f in e["fams"]:
		for key in f["jobs"].keys(): Families.set_job(e, f, int(key), 0)
		Shelter.release_casual(e, f)
		f["owns"] = []; f["keeps"] = []; f["land"] = {}; f["herd"] = {}; f["farm"] = -1; f["ox"] = 0
		f["hands"] = 0; f["idle"] = Families.adults(f) - Families.serving(f)
		f["gone"] = not ids.has(int(f["id"]))
		f["unpaid"] = 0; f["hungry"] = 0; f["debt"] = 0.0; f["purse"] = 5000.0
		f["homes"] = 1; f["cond"] = 1.0; f["last"] = 0.0; f["tax_season"] = e["tax"]["season"]; f["nxa"] = 100.0
		f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}
		for key in ["hl", "rent", "landlord", "cjearned", "wage_receipts"]: f.erase(key)
	for b in e["biz"]: b["closed"] = true; b["kw"] = 0
	if mode == "reserve":
		# Explicit reserve-only register state: these real working-age people
		# remain civilians, while lead_gone rejects reserve as a lead's service.
		for id in ids:
			for p in Persons.pp(e["fams"][int(id)]):
				if int(p[6]) == 0: p[4] = "reserve"
	e["cjcap"] = {}; e["cjused"] = {}; e["hands"] = 0; e["idle_n"] = 0
	e["treasury"] = 0.0; e["day"] = 7; Game.day = 7.0
	e["ruler"]["temper"] = "greedy"
	town["shop"] = []; town["armory_items"] = []
	var fac := {"capital": tid, "towns": [tid], "treasury": 0.0}
	Game.world = {"seed": 2026, "factions": {fid: fac}, "towns": {tid: town}, "research": {}, "wars": [], "army": {"f": {fid: {"bill": 1.0}}}}
	var academy := Businesses._row(e, "academy", -1, 2 if mode.begins_with("cut") or mode == "displace" else 1, TownEcon.data())
	e["academy"] = int(academy["id"])
	academy["wage"] = 10.0; academy["till"] = 10000.0; academy["skill"] = 1.0; academy["lead"] = []
	var lead: Dictionary = e["fams"][int(ids[0])]
	var staff: Dictionary = lead if shared else e["fams"][int(ids[1])]
	if not mode in ["appoint", "reserve"]:
		Families.set_job(e, lead, int(academy["id"]), 1)
		var p: Array = Persons.pp(lead).filter(func(q): return int(q[6]) == 0 and String(q[4]) in ["", "hire"])[0]
		academy["lead"] = [int(lead["id"]), int(p[0])]
		academy["lskill"] = 3.0
	if mode.begins_with("cut") or mode == "displace":
		Families.set_job(e, staff, int(academy["id"]), int(staff["jobs"].get(str(int(academy["id"])), 0)) + 1)
	var count := 0
	for id in ids: count += Families.adults(e["fams"][int(id)])
	var filler := Businesses._row(e, "carpenter", -1, count - int(academy["workers"]) - (3 if mode == "growth" else (1 if mode in ["appoint", "reserve"] else 0)), TownEcon.data())
	filler["wage"] = 1.0; filler["till"] = 10000.0
	var offer := Businesses._row(e, "carpenter", -1, 0, TownEcon.data())
	offer["wage"] = 5.0; offer["till"] = 0.0
	if mode in ["appoint", "reserve"]: academy["closed"] = true
	Businesses.rebuild_open(e)
	var rng := RandomNumberGenerator.new(); rng.seed = 88271
	for id in ids: Families.turn(Game, town, e, e["fams"][int(id)], 7.0, rng)
	academy["closed"] = false
	e["idle_n"] = 0
	for id in ids: e["idle_n"] += int(e["fams"][int(id)]["idle"])
	balance(e, ids, "before weekly staffing")
	var S := Academy.state(Game.world, fid)
	for key in S["kh"]: S["kh"][key] = 0.0 if mode in ["cut0", "growth", "displace", "reserve"] else 100.0
	if mode == "growth": fac["treasury"] = 100000.0
	if mode.begins_with("cut"):
		offer["cap"] = 2 if mode == "cut0" else 1
		offer["till"] = 10000.0 if funded else 0.0
		academy["till"] = 10000.0 if funded else 10.0
	elif mode == "appoint": academy["till"] = 10000.0 if funded else 0.0
	elif mode in ["displace", "reserve"]:
		# A real budget cut releases one relative. The existing matcher ranks
		# every paid place of that household and can also move its lead.
		e["ruler"]["temper"] = "merciful"
		if mode == "displace":
			offer["cap"] = Families.adults(lead); offer["wage"] = 100.0; offer["till"] = 1000000.0
		var item_ids: Array = DB.weapons.keys(); item_ids.sort()
		for item_id in item_ids:
			if float(DB.weapons[item_id].get("head_cm3", 0.0)) > 0.0:
				town["shop"] = [Item.make(String(item_id), "steel", 2)]
				break
		check((town["shop"] as Array).size() == 1, "property-selected real steel study piece exists")
		if (town["shop"] as Array).is_empty(): return
		academy["till"] = maxf(float(academy["till"]), 3.0 * Economy.base_value(town, town["shop"][0]) + 10000.0)
		check(float(academy["till"]) >= 2.0 * Economy.base_value(town, town["shop"][0]), "study piece is actually affordable before lead departure")
	e["day"] = 8; Game.day = 8.0
	WageClaims.accrue_day(e, 8)
	var claims := {}
	for b in e["biz"]:
		for key in b.get("wage_claims", {}): claims[key] = float(claims.get(key, 0.0)) + float(b["wage_claims"][key])
	var receipts := {}; var last := {}; var population := {}; var records := {}
	for id in ids:
		var f: Dictionary = e["fams"][int(id)]
		receipts[id] = float(f.get("wage_receipts", 0.0)); last[id] = f["last"]
		population[id] = Families.people(f); records[id] = Persons.pp(f).duplicate(true)
	var before_cash := cash(e, fac)
	var wage_day: int = e["wage_day"]
	var stock_before: Dictionary = e["stock"].duplicate(true)
	var used_before: Dictionary = e["led"]["used"].duplicate(true)
	var market_before := float(e["biz"][int(e["mkt"])]["till"])
	Academy.faction_turn(Game, 8.0)
	var label := "%s funded=%s shared=%s reverse=%s culture=%s" % [mode, funded, shared, reverse_order, e["culture"]]
	balance(e, ids, label)
	check(absf(cash(e, fac) - before_cash) < 0.00001, label + ": real coins conserved")
	check(int(e["wage_day"]) == wage_day, label + ": no extra wage accrual day")
	for id in ids:
		var f: Dictionary = e["fams"][int(id)]
		check(f["last"] == last[id], label + ": no household payday advanced")
		check(Families.people(f) == population[id] and Persons.pp(f) == records[id], label + ": real adults and register preserved")
		var remaining := 0.0
		for b in e["biz"]: remaining += float(b.get("wage_claims", {}).get(str(int(id)), 0.0))
		var paid := float(f.get("wage_receipts", 0.0)) - float(receipts[id])
		check(absf(remaining + paid - float(claims.get(str(int(id)), 0.0))) < 0.00001, label + ": prior earned wages paid or preserved exactly once")
	check(float(offer["owed"]) == 0.0, label + ": new jobs gain no preceding wages")
	if mode.begins_with("cut"):
		var places := 0 if mode == "cut0" else 1
		check(int(academy["cap"]) == places and int(academy["workers"]) == places, label + ": actual budget cut completes")
		check(int(offer["workers"]) == (2 - places if funded else 0), label + ": released adults take only funded alternatives")
		check((academy["lead"] as Array).size() == (0 if places == 0 else 2), label + ": lead removal or retention follows actual places")
	elif mode == "growth":
		check(int(academy["cap"]) > 1 and int(academy["workers"]) == int(academy["cap"]), label + ": newly financed academy places match immediately")
	elif mode in ["displace", "reserve"]:
		check(int(academy["cap"]) == 1, label + ": real interest budget cuts two places to one")
		if mode == "displace":
			check(int(lead["jobs"].get(str(int(academy["id"])), 0)) == 0 and int(offer["workers"]) == Families.adults(lead), label + ": higher funded pay genuinely displaces the shared household lead")
		else:
			check(int(academy["workers"]) == 1 and Persons.pp(lead).all(func(p): return int(p[6]) != 0 or String(p[4]) == "reserve"), label + ": reserve civilian still holds an ordinary paid place")
		check((academy["lead"] as Array).is_empty() and academy.has("vac"), label + ": departed lead is vacated before study")
		check((town["shop"] as Array).size() == 1, label + ": no study piece dismantled after lead departure")
		check(float(e["biz"][int(e["mkt"])]["till"]) == market_before, label + ": no study purchase after lead departure")
		check((S["pts"] as Dictionary).values().all(func(value): return float(value) == 0.0), label + ": no study points credited after lead departure")
		check(float((S["hist"] as Array).back()[1]) == 0.0, label + ": weekly output contains no departed-lead study credit")
		var mkt: Dictionary = e["biz"][int(e["mkt"])]
		var material_spend := Academy.day(Game, town, e, academy, 0.0, mkt, {})
		check(material_spend == 0.0 and e["stock"] == stock_before and e["led"]["used"] == used_before, label + ": absent lead consumes no research materials")
		check(float(S["out"]) == 0.0, label + ": absent lead credits no daily output")
	else:
		check(int(academy["workers"]) == 1 and (academy["lead"] as Array).size() == 2, label + ": idle adult appointed in existing lead path")
	var snapshot := JSON.stringify(e)
	Families.match_idle(e)
	check(JSON.stringify(e) == snapshot, label + ": completed matching has no repeated coins or assignment changes")
	var expected := 0.0
	for b in e["biz"]:
		if not b.get("closed", false): expected += int(b["workers"]) * float(b["wage"])
	var prior_owed := 0.0
	for b in e["biz"]: prior_owed += float(b.get("owed", 0.0))
	WageClaims.accrue_day(e, 9)
	var owed := 0.0
	for b in e["biz"]: owed += float(b.get("owed", 0.0))
	check(absf(owed - prior_owed - expected) < 0.00001, label + ": following day accrues only actual current staffing wages")
	check(absf(cash(e, fac) - before_cash) < 0.00001, label + ": wage accrual creates no coins")

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"; Game.new_game(2026)
	var towns: Array = Game.world["towns"].values().duplicate(true)
	var seen := {}
	for town in towns:
		if not TownEcon.has_econ(town): continue
		var culture := String(town["econ"]["culture"])
		if seen.has(culture): continue
		seen[culture] = true
		for mode in ["cut1", "cut0", "appoint", "growth"]:
			for funded in [false, true]:
				for shared in [false, true]:
					for reverse_order in [false, true]: fixture(town, mode, funded, shared, reverse_order)
		for reverse_order in [false, true]: fixture(town, "displace", true, true, reverse_order)
		fixture(town, "reserve", true, false, false)
	check(seen.size() == TownEcon.data()["cultures"].size(), "every registered economy culture is exercised")
	print("ACADEMY ASSIGNMENTS cultures=", seen.keys(), " checks=", checks, " failures=", fails)
	return fails
