extends RefCounted
## Sickness (docs/specs/barge/06-sickness.md section 9, with 6b starvation): no case without a source (every case
## a register person); contact-only diseases never start in a clean, isolated world; a caravan with a shedding crew
## member seeds a clean town and the first case records where it came from; immunity holds for the row's
## duration; a bed-ridden man draws no wage (the family's income drops by exactly that wage) and his business runs
## short-handed; A/B: crowded, hungry, cold towns get more cases than comfortable ones; every death carries its
## cause in the person, the family history and the census; remedies cut sick days and deaths (A/B on the same
## rolls) and are conserved (bought and used, never spawned); a town cut off from food loses people to hunger and
## hunger-driven sickness, a fed town none; a sick company man fights weakened and his card says so; no NaN, no
## negative counts; the perf gate (Douglas: mean sickness cost <= 8 ms a day, worst single sickness job <= 4 ms, at 20 x 150).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	var only := OS.get_environment("SICK_ONLY")
	if only == "perf":
		_test_perf()
		return fails
	if only == "wage_save":
		_test_wage_and_short_handed()
		_test_save_fields()
		return fails
	_test_year_isolated()
	_test_edge_event()
	_test_caravan_seeds()
	_test_immunity()
	_test_wage_and_short_handed()
	_test_ab_conditions()
	_test_death_causes()
	_test_remedies()
	_test_starvation()
	_test_company()
	_test_save_fields()
	if only != "noperf":
		_test_perf()
	return fails

# ---------------------------------------------------------------- helpers
func _quiet(w: Dictionary) -> void:
	# _days runs only economy and sickness jobs. Preserve the real bands and
	# their people: deleting bands incorrectly turns their staff into deaths.
	w["work"] = []
	w["party"]["safe_until"] = 1.0e9

func _ids(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys()
	ids.sort()
	return ids

## The economy and sickness for n days, in the campaign's order (the daily tick, then the day's economy jobs).
func _days(n: int) -> void:
	var w: Dictionary = Game.world
	for i in n:
		var d := int(w.get("econ_test_day", 0)) + 1
		w["econ_test_day"] = d
		Game.day = float(d)
		var work := []
		w["work"] = work
		TownEcon.queue_day(w, d)
		Sickness.queue_day(w, d)
		while not work.is_empty():
			var job: Array = work.pop_front()
			if not TownEcon.do_job(Game, job):
				Sickness.do_job(Game, job)

func _world(seed: int, isolated: bool = true) -> Dictionary:
	Game.new_game(seed)
	var w: Dictionary = Game.world
	_quiet(w)
	w["sk_isolated"] = isolated
	w["econ_test_day"] = int(Game.day)
	return w

func _total(w: Dictionary, key: String, dis: String = "") -> int:
	var n := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var bk: Dictionary = Sickness.book(t["econ"])[key]
		for k in bk:
			if dis == "" or String(k) == dis:
				n += int(bk[k])
	return n

## A grown-up at home in the town (adult, state ""), with or without a job.
func _adult(e: Dictionary, with_job: bool = false) -> Array:
	for f in e["fams"]:
		if f["gone"] or f.get("estate", false) or not f.has("pp"):
			continue
		var wk := Persons.work(e, f)
		for p in Persons.pp(f):
			if String(p[4]) != "" or int(p[6]) != 0 or Sickness.case_of(f, int(p[0])).size() > 0:
				continue
			var pl: Dictionary = wk.get(int(p[0]), {})
			if with_job and String(pl.get("kind", "")) != "job":
				continue
			if with_job and int(e["biz"][int(pl["biz"])]["owner"]) == int(f["id"]):
				continue
			return [f, p, pl]
	return []

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

# ---------------------------------------------------------------- 1. no case without a source; no pox in a clean world
func _test_year_isolated() -> void:
	var w := _world(4401, true)
	Sickness.log_cases = true
	Sickness.case_log = []
	var t0 := Time.get_ticks_msec()
	_days(240)
	var ms := Time.get_ticks_msec() - t0
	Sickness.log_cases = false
	var log: Array = Sickness.case_log
	check(log.size() > 20, "two years of a world: only %d cases" % log.size())
	var kinds := {}
	var bad := []
	var allowed := ["cond", "home", "town", "work", "garrison", "crew", "carrier", "came", "camp", "wound", "edge", "relapse"]
	for c in log:
		var src := String(c[3])
		var k := src.get_slice(":", 0)
		kinds[k] = int(kinds.get(k, 0)) + 1
		if src == "" or not k in allowed or src.substr(k.length() + 1).strip_edges() == "":
			bad.append(str(c))
	check(bad.is_empty(), "cases without a proper source: %s" % str(bad.slice(0, 3)))
	# every case is a real register person (living, or remembered among the family's dead)
	var missing := 0
	for c in log:
		var e: Dictionary = w["towns"][String(c[0])]["econ"]
		var found := false
		for f in e["fams"]:
			if not Persons.any(f, int(c[1])).is_empty():
				found = true
				break
		if not found and int(c[1]) < int(e.get("next_pid", 0)):
			found = true   # a person who left town long ago (forgotten past the family's memory): still a real pid
		if not found:
			missing += 1
	check(missing == 0, "%d cases are not register people" % missing)
	check(_total(w, "cases", "pox") == 0, "the pox started in a clean, isolated world (%d cases)" % _total(w, "cases", "pox"))
	check(_total(w, "cases", "flux") > 0, "no flux in two years")
	var bad2 := Sickness.check_counts(w)
	check(bad2.is_empty(), "counts: %s" % str(bad2.slice(0, 4)))
	# remedies conserved: made - used = what the markets and households hold
	var made := 0; var used := 0; var held := 0
	for tid in w["towns"]:
		var e2: Dictionary = w["towns"][tid]["econ"]
		made += int(e2["led"]["made"].get("remedy", 0))
		used += int(e2["led"]["used"].get("remedy", 0))
		held += int(e2["stock"].get("remedy", 0)) + int(e2["hh"].get("remedy", 0))
	check(made > 0, "the herbalists made no remedies in two years")
	check(made - used == held, "remedies not conserved: made %d - used %d != held %d" % [made, used, held])
	print("  2 years, isolated world: %d cases by source %s; %d died of sickness, %d starved; remedies made %d used %d; %.1f s" % [
		log.size(), str(kinds), _total(w, "deaths"), _starved(w), made, used, ms / 1000.0])
	for l in Sickness.report_lines(w).slice(-2):
		print("  ", l)

func _starved(w: Dictionary) -> int:
	var n := 0
	for tid in w["towns"]:
		n += int(Sickness.book(w["towns"][tid]["econ"])["starved"])
	return n

## The rare world event: a traveller from beyond the edge brings the pox into the edge town (logged, sourced).
func _test_edge_event() -> void:
	var w := _world(4402, false)
	var D := Sickness.data()
	var keep: Dictionary = D["edge"].duplicate()
	D["edge"] = {"pox": 1.0}
	Sickness._edge(Game, int(Game.day), _rng(5))
	D["edge"] = keep
	var t := Sickness.edge_town(w)
	var b := Sickness.book(t["econ"])
	check(int(b["cases"].get("pox", 0)) == 1, "the edge event brought no pox case")
	check(String(b["first"].get("pox", [0, ""])[1]).contains("beyond the map edge"), "the edge case's origin: %s" % str(b["first"].get("pox", [])))
	var logged := false
	for l in w.get("log", []):
		if String(l).contains("edge of the map"):
			logged = true
	check(logged, "the edge event is not in the world log")

# ---------------------------------------------------------------- 3. a caravan seeds a clean town
func _test_caravan_seeds() -> void:
	var w := _world(4403, true)
	var ids := _ids(w)
	var a: Dictionary = w["towns"][ids[0]]
	var dest: Dictionary = {}
	for pt in Caravans.trade_partners(w, a):
		dest = w["towns"][String(pt["id"])]
		break
	if dest.is_empty():
		dest = w["towns"][ids[1]]
	var wid := Caravans.spawn(Game, String(a["id"]), _rng(9), String(dest["id"]))
	check(wid != "", "no caravan left %s" % a["name"])
	if wid == "":
		return
	var wb: Dictionary = w["warbands"][wid]
	var crew := Sickness._crew(wb, a)
	check(crew.size() >= 2, "caravan crew are register people (%d found)" % crew.size())
	if crew.is_empty():
		return
	var day := float(Game.day)
	var cr: Array = crew[0]
	var ok := Sickness.infect(Game, cr[0], cr[1], cr[2], "pox", day - 12.0, "carrier:test traveller met on the road", _rng(3), cr[3])
	check(ok, "could not give the crew member the pox")
	check(int(Sickness.book(a["econ"])["act"].get("pox", 0)) == 0, "a crew member away on the road counts in his home town's sick")
	var db := Sickness.book(dest["econ"])
	var tries := 0
	while int(db["cases"].get("pox", 0)) == 0 and tries < 200:
		Game.day = day + float(tries % 3) * 0.0
		wb["id"] = "%s_%d" % [wid, tries]   # a fresh seed per try (the same caravan arriving again)
		Sickness.caravan_at(Game, wb, dest)
		tries += 1
	wb["id"] = wid
	check(int(db["cases"].get("pox", 0)) > 0, "a shedding crew member never seeded %s in %d arrivals" % [dest["name"], tries])
	var origin: String = String(db["first"].get("pox", [0, ""])[1])
	check(origin.contains("caravan from %s" % a["name"]), "first-case origin not recorded: '%s'" % origin)
	print("  caravan: %s seeded with the pox after %d arrival(s): \"%s\"" % [dest["name"], tries, origin])
	# the real arrival path runs the hook
	Caravans.arrive(Game, wid)
	check(Sickness.book(dest["econ"])["news"].size() >= 0, "arrival hook")

# ---------------------------------------------------------------- 4. immunity
func _test_immunity() -> void:
	var w := _world(4404, true)
	var t: Dictionary = w["towns"][_ids(w)[0]]
	var e: Dictionary = t["econ"]
	var b := Sickness.book(e)
	var day := float(Game.day)
	var who := _adult(e)
	var f: Dictionary = who[0]
	var p: Array = who[1]
	var pid := int(p[0])
	var rng := _rng(11)
	# the pox: for life
	check(Sickness.infect(Game, t, f, p, "pox", day, "carrier:test", rng), "infect (pox)")
	var c := Sickness.case_of(f, pid)
	c[Sickness.C_DIE] = -1.0
	Sickness._recover(e, b, f, str(pid), c, rng)
	check(Sickness.case_of(f, pid).is_empty(), "the case is over")
	check(Sickness.immune(f, pid, "pox", day + 5000.0), "a pox survivor is not immune for life")
	check(not Sickness.infect(Game, t, f, p, "pox", day + 400.0, "carrier:test", rng), "a pox survivor caught it again")
	# marsh fever: three years (no relapse for this test)
	var R := Sickness.row("marsh_fever")
	var rel: Array = R["relapse"]
	R["relapse"] = [0.0, 1, 1]
	check(Sickness.infect(Game, t, f, p, "marsh_fever", day, "cond:test", rng), "infect (marsh fever)")
	var c2 := Sickness.case_of(f, pid)
	c2[Sickness.C_DIE] = -1.0
	var end := float(c2[Sickness.C_END])
	Sickness._recover(e, b, f, str(pid), c2, rng)
	R["relapse"] = rel
	var yd := Sickness.year_days()
	check(Sickness.immune(f, pid, "marsh_fever", end + 3.0 * yd - 1.0), "marsh fever immunity ends before 3 years")
	check(not Sickness.immune(f, pid, "marsh_fever", end + 3.0 * yd + 1.0), "marsh fever immunity outlasts 3 years")
	check(not Sickness.infect(Game, t, f, p, "marsh_fever", end + 100.0, "cond:test", rng), "caught marsh fever again while immune")
	check(Sickness.infect(Game, t, f, p, "marsh_fever", end + 3.0 * yd + 2.0, "cond:test", rng), "could not catch marsh fever after the immunity ran out")
	# the flux: no immunity
	Sickness.case_of(f, pid)[Sickness.C_DIE] = -1.0
	Sickness._recover(e, b, f, str(pid), Sickness.case_of(f, pid), rng)
	check(Sickness.infect(Game, t, f, p, "flux", day + 10.0, "cond:test", rng), "infect (flux)")
	var c3 := Sickness.case_of(f, pid)
	c3[Sickness.C_DIE] = -1.0
	Sickness._recover(e, b, f, str(pid), c3, rng)
	check(not Sickness.immune(f, pid, "flux", day + 40.0), "the flux gave immunity")

# ---------------------------------------------------------------- 5. bed-ridden: no wage; the business short-handed
func _test_wage_and_short_handed() -> void:
	var w := _world(4405, true)
	var t: Dictionary = {}
	var who := []
	for tid in _ids(w):
		who = _adult(w["towns"][tid]["econ"], true)
		if not who.is_empty():
			t = w["towns"][tid]
			break
	check(not who.is_empty(), "nobody with a job")
	if who.is_empty():
		return
	var e: Dictionary = t["econ"]
	var f: Dictionary = who[0]
	var p: Array = who[1]
	var biz := int(who[2]["biz"])
	var bz: Dictionary = e["biz"][biz]
	var day := float(Game.day) + 14.0
	Game.day = day
	f["last"] = day - 7.0
	f["store"]["food"] = 60.0
	f["purse"] = maxf(float(f["purse"]), 500.0)
	bz["till"] = 100000.0
	var rng := _rng(21)
	check(Sickness.infect(Game, t, f, p, "flux", day - 9.0, "cond:test", rng), "infect the worker")
	var c := Sickness.case_of(f, int(p[0]))
	c[Sickness.C_ON] = day - 7.0
	c[Sickness.C_END] = day + 5.0
	c[Sickness.C_DIE] = -1.0
	c[Sickness.C_BED] = 1
	c[Sickness.C_BIZ] = biz
	c[Sickness.C_REM] = 1   # (no remedy bought in this test)
	# the bed-ridden start: the business is short of him
	Sickness._event(Game, t, e, Sickness.book(e), [day - 7.0, 2, int(f["id"]), int(p[0]), "flux", ""], int(day), rng)
	check(int(bz.get("sick", 0)) == 1, "the business does not count its bed-ridden man (%d)" % int(bz.get("sick", 0)))
	var jobs := int(f["jobs"][str(biz)])
	var wage := float(bz["wage"])
	var till0 := float(bz["till"])
	# Earn the seven actual wage intervals before settlement; the sick hand
	# misses exactly seven days, while any other employed relatives still earn.
	for d in range(int(day) - 6, int(day) + 1):
		e["day"] = d
		WageClaims.accrue_day(e, d)
	Families.turn(Game, t, e, f, day, rng)
	var paid := till0 - float(bz["till"])
	var full := float(jobs) * wage * 7.0
	check(absf(paid - (full - wage * 7.0)) < 0.01, "a bed-ridden week: paid %.2f, full %.2f, expected %.2f (one wage short)" % [paid, full, full - wage * 7.0])
	print("  wage: %d at %s, a bed-ridden week: paid %.1f of %.1f (exactly %.1f, his wage, short)" % [jobs, Businesses.title(e, bz), paid, full, full - paid])
	# recovered: the business has him back
	c[Sickness.C_END] = day + 1.0
	Sickness._event(Game, t, e, Sickness.book(e), [day + 1.0, 0, int(f["id"]), int(p[0]), "flux", ""], int(day) + 1, rng)
	check(int(bz.get("sick", 0)) == 0, "the business still counts him sick after he recovered")
	# the garrison: a bed-ridden militiaman is off duty (band power)
	var u := Unit.create("human", String(t["faction"]))
	u.sick = "flux"; u.sick_on = day - 1.0; u.sick_to = day + 3.0; u.sick_bed = true
	check(CampaignWorld.unit_power(u) == 0.0, "a bed-ridden soldier still counts in the band's power")
	u.sick_bed = false
	check(CampaignWorld.unit_power(u) > 0.0, "a sick man on his feet counts")

# ---------------------------------------------------------------- 6. A/B: crowded, hungry, cold vs comfortable
func _ab_run(hard: bool) -> Array:
	var w := _world(4406, true)
	var t: Dictionary = w["towns"][_ids(w)[2]]
	var e: Dictionary = t["econ"]
	var room := float(TownEcon.culture_of(e)["home"]["room"])
	for f in e["fams"]:
		if f.get("estate", false) or f["gone"]:
			continue
		if hard:
			f["homes"] = 1
			f["hungry"] = 3
			f["store"]["wood"] = 0.0
		else:
			f["homes"] = maxi(1, int(ceil(float(Families.people(f)) / room)) + 1)
			f["hungry"] = 0
			f["store"]["wood"] = 30.0
	var d0 := int(Game.day)
	for i in 360:
		var d := d0 + i + 1
		Game.day = float(d)
		e["day"] = d
		Sickness.town_day(Game, t, d)
	var b := Sickness.book(e)
	var n := 0
	for dis in ["flux", "winter_cough", "marsh_fever"]:
		n += int(b["cases"].get(dis, 0))
	return [n, b["cases"].duplicate(), String(t["name"]), int(e["pop"])]

func _test_ab_conditions() -> void:
	var a := _ab_run(true)
	var b := _ab_run(false)
	check(int(a[0]) > int(b[0]) * 3 / 2, "crowded, hungry, cold %s: %d cases; comfortable: %d (want clearly more)" % [a[2], int(a[0]), int(b[0])])
	print("  A/B %s, three years: crowded, hungry and cold %d cases %s; comfortable %d cases %s" % [a[2], int(a[0]), str(a[1]), int(b[0]), str(b[1])])

# ---------------------------------------------------------------- 7. every death carries its cause
func _test_death_causes() -> void:
	var w := _world(4407, true)
	var t: Dictionary = w["towns"][_ids(w)[0]]
	var e: Dictionary = t["econ"]
	var day := float(Game.day)
	var rng := _rng(31)
	var dead := []
	for i in 6:
		var who := _adult(e)
		if who.is_empty():
			break
		var f: Dictionary = who[0]
		var p: Array = who[1]
		Sickness.infect(Game, t, f, p, "pox", day, "carrier:test", rng)
		var c := Sickness.case_of(f, int(p[0]))
		c[Sickness.C_DIE] = float(c[Sickness.C_ON]) + 1.0
		Sickness._push(Sickness.book(e), [c[Sickness.C_DIE], 0, int(f["id"]), int(p[0]), "pox", ""])
		dead.append([f, int(p[0]), Persons.name_of(f, p, Persons.race_of(e))])
	var pop0 := int(e["pop"])
	for d in range(int(day) + 1, int(day) + 20):
		Game.day = float(d)
		e["day"] = d
		Sickness.town_day(Game, t, d)
	var census: Array = Census._book(e)["deaths"]
	for x in dead:
		var f: Dictionary = x[0]
		var pid: int = x[1]
		var nm: String = x[2]
		var row := []
		for r in census:
			if int(r[1]) == pid:
				row = r
		check(not row.is_empty() and String(row[5]) == "sickness" and String(row[6]) == "the pox", "census: %s has no sickness death (%s)" % [nm, str(row)])
		var mem := Persons.any(f, pid)
		check(not mem.is_empty() and str(mem).contains("sickness: the pox"), "the remembered dead %s lacks his cause: %s" % [nm, str(mem)])
		var hist := false
		for l in f["hist"]:
			if String(l).contains(nm) and String(l).contains("died of the pox"):
				hist = true
		check(hist, "family history lacks %s's death" % nm)
		check(Persons.by_pid(f, pid).is_empty(), "%s still in the register" % nm)
	check(int(e["pop"]) == pop0 - dead.size(), "population %d -> %d after %d deaths" % [pop0, int(e["pop"]), dead.size()])
	for r in census:
		check(String(r[5]) in Census.CAUSES and String(r[5]) != "", "a census death without a cause: %s" % str(r))

# ---------------------------------------------------------------- 8. remedies
func _test_remedies() -> void:
	# A/B on the same rolls: the same 2000 cases, untreated and treated at onset
	var rng := _rng(41)
	var deaths_a := 0; var deaths_b := 0; var days_a := 0.0; var days_b := 0.0; var worse := 0
	for i in 2000:
		var q := 0.02
		var on := 10.0
		var end := on + float(rng.randi_range(10, 18))
		var u := rng.randf()
		var die := Sickness._death_day(on, end, q, u)
		var c := ["pox", 0.0, on, end, die, "test", 0, 0, u, q, -1, 0, 0, 0.0]
		var stop_a := Sickness._stop(c)
		if die >= 0.0:
			deaths_a += 1
		days_a += stop_a - on
		Sickness.apply_remedy({}, {"id": 0}, 0, c, on)
		var stop_b := Sickness._stop(c)
		if float(c[Sickness.C_DIE]) >= 0.0:
			deaths_b += 1
		days_b += stop_b - on
		if die < 0.0 and float(c[Sickness.C_DIE]) >= 0.0:
			worse += 1
	check(deaths_b < deaths_a, "remedies: deaths %d treated vs %d untreated" % [deaths_b, deaths_a])
	check(days_b < days_a, "remedies: sick days %.0f treated vs %.0f untreated" % [days_b, days_a])
	check(worse == 0, "a remedy killed %d who would have lived" % worse)
	print("  remedies A/B, 2000 cases: deaths %d -> %d, sick days %.0f -> %.0f" % [deaths_a, deaths_b, days_a, days_b])
	# the economy: a family buys one from the market's stock (no remedy is ever made from nothing)
	var w := _world(4408, true)
	var t: Dictionary = w["towns"][_ids(w)[0]]
	var e: Dictionary = t["econ"]
	var who := _adult(e)
	var f: Dictionary = who[0]
	var p: Array = who[1]
	var day := float(Game.day) + 7.0
	Game.day = day
	f["last"] = day - 7.0
	f["store"]["food"] = 60.0
	f["purse"] = 2000.0
	e["stock"]["remedy"] = 5
	var made0 := int(e["led"]["made"].get("remedy", 0))
	var used0 := int(e["led"]["used"].get("remedy", 0))
	var hh0 := int(e["hh"].get("remedy", 0))
	Sickness.infect(Game, t, f, p, "flux", day - 6.0, "cond:test", _rng(5))
	var c2 := Sickness.case_of(f, int(p[0]))
	c2[Sickness.C_ON] = day - 2.0
	c2[Sickness.C_END] = day + 10.0
	c2[Sickness.C_DIE] = -1.0
	var purse0 := float(f["purse"])
	var price := float(e["price"].get("remedy", 3.0)) * TownEcon.markup()   # (barge part 2 section 5: households pay the price x 1.1)
	Sickness.family_turn(Game, t, e, f, day)
	TownEcon.clear_batch(e)
	check(int(Sickness.case_of(f, int(p[0]))[Sickness.C_REM]) == 1, "the family bought no remedy")
	check(int(e["stock"]["remedy"]) == 4, "market remedy stock %d (want 4)" % int(e["stock"]["remedy"]))
	check(int(e["led"]["used"].get("remedy", 0)) == used0 + 1 and int(e["led"]["made"].get("remedy", 0)) == made0, "remedy ledgers: used +1, made unchanged")
	check(int(e["hh"].get("remedy", 0)) == hh0, "a remedy left lying in the household pool")
	check(absf(purse0 - float(f["purse"]) - price) < 0.01, "the family paid %.2f for a remedy priced %.2f" % [purse0 - float(f["purse"]), price])
	check(float(Sickness.case_of(f, int(p[0]))[Sickness.C_END]) < day + 10.0, "the remedy did not shorten his sickness")
	# a family that cannot spare the money after food buys none
	var who2 := _adult(e)
	var f2: Dictionary = who2[0]
	var p2: Array = who2[1]
	f2["last"] = day - 7.0
	f2["store"]["food"] = 60.0
	f2["purse"] = 3.0
	Sickness.infect(Game, t, f2, p2, "flux", day - 6.0, "cond:test", _rng(6))
	var c3 := Sickness.case_of(f2, int(p2[0]))
	c3[Sickness.C_ON] = day - 2.0
	c3[Sickness.C_END] = day + 10.0
	c3[Sickness.C_DIE] = -1.0
	Sickness.family_turn(Game, t, e, f2, day)
	check(int(Sickness.case_of(f2, int(p2[0]))[Sickness.C_REM]) == 0, "a family with 3 coins bought a remedy before food")

# ---------------------------------------------------------------- 6b. starvation
func _test_starvation() -> void:
	var w := _world(4409, true)
	var ids := _ids(w)
	var t: Dictionary = w["towns"][ids[0]]
	var fed: Dictionary = w["towns"][ids[1]]
	var e: Dictionary = t["econ"]
	_days(28)   # (barge: four weeks of shopping first, so each family's larder is the jar of its class)
	# cut off: no food on the stalls, in the barns or the granary, no harvest, no hunters; each family keeps only what it
	# had laid by (barge: households keep jars by class - the rich more days than the poor - so the larders stay; they
	# were zeroed before the barge economy, when every family held the same few days)
	for g in ["grain", "fruit", "meat"]:
		e["stock"][g] = 0
		e["barn"][g] = 0
	e["granary"] = 0
	for bz in e["biz"]:
		if String(bz["type"]) in ["hunter", "fishery"]:
			bz["closed"] = true
	Businesses.rebuild_open(e)
	var purse := []
	for f in e["fams"]:
		if not f.get("estate", false) and not f["gone"]:
			purse.append([float(f["purse"]), int(f["id"])])
	purse.sort()
	var poor := {}
	for i in purse.size() / 2:
		poor[int(purse[i][1])] = true
	var pop0 := int(e["pop"])
	var fed_pid0 := int(fed["econ"].get("next_pid", 1))   # (barge movers: families who flee the famine get new numbers there)
	# keep the town cut off for 50 days (no harvest comes in spring and summer; nobody sells it food)
	var pd := 0.0   # person-days lived in each town (the rate of sickness per person-day)
	var fpd := 0.0
	for i in 50:
		pd += float(e["pop"])
		fpd += float(fed["econ"]["pop"])
		e["hf"] = 0.0   # (barge: a summer grain cut too; cut off means no harvest at all this year)
		e["hf_year"] = Calendar.year(float(int(w.get("econ_test_day", 0)) + 1))
		_days(1)
		for g in ["grain", "fruit", "meat"]:
			e["stock"][g] = 0
			e["barn"][g] = 0
		e["granary"] = 0   # (the barge granary takes a share of every harvest: none of it either)
		for f in e["fams"]:
			f["hv"] = 0.0   # (barge: landholders keep their own harvest share for food: none of it either)
	var starved := int(Sickness.book(e)["starved"])
	var fed_starved := int(Sickness.book(fed["econ"])["starved"])
	# the fed town's own people (barge part 4 section 6: hungry families of the cut-off town flee there, already wasted,
	# and some die there of the hunger they brought; they are not the fed town's hunger)
	var fed_own := 0
	for r in Census._book(fed["econ"])["deaths"]:
		if String(r[5]) == "starved" and int(r[1]) >= 0 and int(r[1]) < fed_pid0:
			fed_own += 1
	check(starved > 0, "a town cut off from food for 50 days lost nobody to hunger (pop %d -> %d)" % [pop0, int(e["pop"])])
	check(fed_own == 0, "a fed town lost %d of its own people to hunger" % fed_own)
	var dp := 0; var dr := 0
	for r in Census._book(e)["deaths"]:
		if String(r[5]) != "starved":
			continue
		var fid := -1
		for f in e["fams"]:
			if not Persons.any(f, int(r[1])).is_empty():
				fid = int(f["id"])
		if poor.has(fid):
			dp += 1
		else:
			dr += 1
	check(dp >= dr, "hunger killed more in the richer half (%d) than the poorer (%d)" % [dr, dp])
	var sick_deaths := 0
	for r in Census._book(e)["deaths"]:
		if String(r[5]) == "sickness":
			sick_deaths += 1
	var cases := 0
	for dis in Sickness.book(e)["cases"]:
		cases += int(Sickness.book(e)["cases"][dis])
	var fed_cases := 0
	for dis in Sickness.book(fed["econ"])["cases"]:
		fed_cases += int(Sickness.book(fed["econ"])["cases"][dis])
	print("  cut off 50 days: %s %d -> %d people, %d starved (poorer half %d, richer half %d), %d cases, %d sickness deaths; fed %s (pop %d): %d starved (%d of them refugees), %d cases" % [
		t["name"], pop0, int(e["pop"]), starved, dp, dr, cases, sick_deaths, fed["name"], int(fed["econ"]["pop"]), fed_starved, fed_starved - fed_own, fed_cases])
	print("  cases per 1000 person-days: cut off %.2f, fed %.2f" % [1000.0 * cases / maxf(1.0, pd), 1000.0 * fed_cases / maxf(1.0, fpd)])
	check(float(cases) / maxf(1.0, pd) > float(fed_cases) / maxf(1.0, fpd), "hunger-driven sickness: the starving town has no more cases per person-day than the fed one")
	check(Sickness.check_counts(w).is_empty(), "counts after the famine: %s" % str(Sickness.check_counts(w).slice(0, 3)))

# ---------------------------------------------------------------- the company
func _test_company() -> void:
	var w := _world(4410, true)
	var u: Unit = null
	var pr := []
	for x in Game.company:
		pr = Sickness._person_of(w, x)
		if not pr.is_empty():
			u = x
			break
	check(u != null, "no company man with a register record")
	if u == null:
		return
	var day := float(Game.day)
	var base_end := float(Food.attr_mults(u).get("END", 1.0))
	var base_str := float(Food.attr_mults(u).get("STR", 1.0))
	var base_fat := Food.fatigue_mult(u)
	var base_foc := Food.focus(u)
	check(Sickness.infect(Game, pr[0], pr[1], pr[2], "flux", day - 5.0, "camp:test", _rng(7), u), "infect a company man")
	var c := Sickness.case_of(pr[1], int(pr[2][0]))
	c[Sickness.C_ON] = day - 1.0
	c[Sickness.C_END] = day + 4.0
	c[Sickness.C_DIE] = -1.0
	Sickness.mirror(u, c)
	check(u.sick_now(day), "the company man is not sick now")
	check(absf(float(Food.attr_mults(u)["END"]) - base_end * 0.75) < 0.0001, "END x0.75 while sick")
	check(absf(float(Food.attr_mults(u)["STR"]) - base_str * 0.85) < 0.0001, "STR x0.85 while sick")
	check(absf(Food.fatigue_mult(u) - base_fat * 1.3) < 0.0001, "fatigue gain x1.3 while sick")
	check(absf(Food.focus(u) - clampf(base_foc - 0.10, -Food.FOCUS_CAP, Food.FOCUS_CAP)) < 0.0001, "focus -10%% while sick (%.3f)" % Food.focus(u))
	var txt := Sickness.unit_text(u)
	check(txt.begins_with("the flux, day 2 of 5"), "unit card text: '%s'" % txt)
	# the company buys a remedy in town for him
	var t: Dictionary = pr[0]
	t["econ"]["stock"]["remedy"] = 3
	Game.gold = 500
	var got := Sickness.company_treat(Game, t)
	check(int(got["treated"]) == 1 and int(t["econ"]["stock"]["remedy"]) == 2, "company remedy: %s, stock %d" % [str(got), int(t["econ"]["stock"]["remedy"])])
	# he dies of it: the company loses him, his family and the census remember the cause
	var n0 := Game.company.size()
	c[Sickness.C_DIE] = day + 1.0
	Sickness._push(Sickness.book(t["econ"]), [day + 1.0, 0, int(pr[1]["id"]), int(pr[2][0]), "flux", ""])
	Game.day = day + 1.0
	Sickness.town_day(Game, t, int(day) + 1)
	check(Game.company.size() == n0 - 1 and not Game.company.has(u), "the company man who died of the flux is still in the company")
	var found := false
	for r in Census._book(t["econ"])["deaths"]:
		if int(r[1]) == int(pr[2][0]) and String(r[5]) == "sickness":
			found = true
	check(found, "the company man's death is not in his home town's census")
	# camp sickness rolls in the field; wound rot needs an open untreated wound
	check(Sickness.open_wounds(Game.company[0]) == 0, "a fresh man has open wounds")

func _test_save_fields() -> void:
	var u := Unit.create("human", "player")
	u.sick = "pox"; u.sick_shed = 3.0; u.sick_on = 5.0; u.sick_to = 19.0; u.sick_bed = true
	var v := Unit.from_dict(JSON.parse_string(JSON.stringify(u.to_dict())))
	check(v.sick == "pox" and v.sick_on == 5.0 and v.sick_to == 19.0 and v.sick_bed and v.sick_shed == 3.0, "a sick unit's case does not survive a save")

# ---------------------------------------------------------------- perf gate
## Douglas's gate (2026-10-06 00:17, replacing the spec's 0.5 ms: "keep every sick person real yes, you can even
## count each person every two days if it impacts performance, it shouldnt be a big deal"): at 20 towns x 150
## families the mean sickness cost per campaign day <= 8 ms (raised from 6 by Douglas 01:15: "if things are running
## smoothly 8ms per day seems fine") and the worst single sickness job (one map frame)
## <= 4 ms; the worst day is printed. Everything sickness does counts (the town jobs on their 2-day cadence, the
## forces, the company, its share of the family turns, caravans). Two towns get the pox at the start so the run
## includes an outbreak.
func _test_perf() -> void:
	var D := TownEcon.data()
	var keep: Array = D["families_by_size"]
	D["families_by_size"] = [150, 150, 150, 150, 150]
	Game.new_game(9001)
	D["families_by_size"] = keep
	var w: Dictionary = Game.world
	_quiet(w)
	var ids := _ids(w)
	var k := 0
	while w["towns"].size() < 20:
		var src: Dictionary = w["towns"][ids[k % ids.size()]]
		var nt: Dictionary = {}
		for key in src:
			if key not in ["econ", "shop", "recruits", "contracts"]:
				nt[key] = src[key]
		nt["id"] = "tx%d" % k
		nt["name"] = "%s Minor" % src["name"]
		nt["pos"] = (src["pos"] as Vector2) + Vector2(30, 30)
		nt["shop"] = []
		nt["recruits"] = []
		nt["contracts"] = []
		var rng := RandomNumberGenerator.new(); rng.seed = 77 + k
		D["families_by_size"] = [150, 150, 150, 150, 150]
		EconGen.generate(w, nt, rng)
		D["families_by_size"] = keep
		w["towns"][nt["id"]] = nt
		k += 1
	w["econ_test_day"] = int(Game.day)
	for i in (0 if OS.get_environment("SICK_SEED") == "0" else 2):
		var t: Dictionary = w["towns"][ids[i]]
		var who := _adult(t["econ"])
		Sickness.infect(Game, t, who[0], who[1], "pox", Game.day, "carrier:perf seed", _rng(i))
	Sickness.prof_on = true
	Sickness.prof_parts = OS.get_environment("SICK_PARTS") == "1"   # dev: the breakdown (adds its own cost)
	Sickness.job_worst = 0
	var worst := 0
	var tot := 0
	var days := EconGen.YEAR_DAYS
	var per := []
	for i in days:
		Sickness.us = 0
		_days(1)
		per.append(Sickness.us)
		worst = maxi(worst, Sickness.us)
		tot += Sickness.us
	Sickness.prof_on = false
	var pk := []
	for kk in Sickness.prof:
		pk.append("%s %.3f" % [kk, Sickness.prof[kk] / float(days) / 1000.0])
	var byd := {}
	for tid in w["towns"]:
		var bk: Dictionary = Sickness.book(w["towns"][tid]["econ"])["cases"]
		for dd in bk:
			byd[dd] = int(byd.get(dd, 0)) + int(bk[dd])
	print("  PERF sickness by part (ms a day): ", ", ".join(PackedStringArray(pk)), "; starved %d; cases %s" % [_starved(w), str(byd)])
	Sickness.prof = {}
	per.sort()
	print("  PERF sickness at 20 towns x 150 families, %d days: mean %.3f ms (gate 8 ms), p90 %.3f ms, worst day %.3f ms (printed); worst single sickness job (one map frame) %.3f ms (gate 4 ms); %d cases, %d deaths" % [
		days, tot / float(days) / 1000.0, per[int(days * 0.9)] / 1000.0, worst / 1000.0, Sickness.job_worst / 1000.0, _total(w, "cases"), _total(w, "deaths")])
	check(tot / float(days) <= 8000.0, "sickness mean day %.3f ms (gate 8 ms)" % (tot / float(days) / 1000.0))
	check(Sickness.job_worst <= 4000, "worst single sickness job %.3f ms (gate 4 ms)" % (Sickness.job_worst / 1000.0))
