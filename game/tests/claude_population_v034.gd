extends RefCounted
## v0.034: the common folk (cohort rows) fall sick and migrate, on a real generated world (seed 4242).
## Sickness runs through the real town run (Sickness.town_day) with the disease made common for the test; migration
## through the real weekly job (Migration.weekly). Checks people, coin and goods are conserved and every death and
## move reaches the census. Run with -- --test=res://tests/claude_population_v034.gd (headless).
var checks := 0
var fails := 0
var previous_save_path := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL population034: ", what)

func _finish() -> int:
	Game.wait_save()
	if previous_save_path != "": Game.SAVE_PATH = previous_save_path
	print("population034: %d checks, %d failures" % [checks, fails])
	return fails

func _cohort(e: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for f in e["fams"]:
		if Population.is_cohort(f) and not f.get("gone", false) and (best.is_empty() or Families.people(f) > Families.people(best)): best = f
	return best

func _anon(f: Dictionary) -> int:
	return Population.anonymous(f, 0) + Population.anonymous(f, 1) + Population.anonymous(f, 2) + Population.anonymous(f, 3)

func _bins(f: Dictionary) -> int:
	var n := 0
	for k in f.get("age_bins", {}): n += int(f["age_bins"][k])
	return n

func _act(e: Dictionary, dis: String) -> int:
	return int(e.get("sk", {}).get("act", {}).get(dis, 0))

func _census_sick(e: Dictionary, detail: String) -> int:
	var n := 0
	for row in Census._book(e)["deaths"]:
		if String(row[5]) == "sickness" and String(row[6]) == detail and int(row[1]) == -1: n += int(row[10])
	return n

func _goods(e: Dictionary) -> int:
	var n := 0
	for g in Families.HOUSEHOLD_FOOD + ["beer", "wine", "wood"]: n += int(e["hh"].get(g, 0))
	return n

func _purses(e: Dictionary) -> float:
	var n := float(e.get("treasury", 0.0))
	for f in e["fams"]: n += float(f.get("purse", 0.0))
	return n

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	Game.SAVE_PATH = "user://population034-test.json"
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(4242)
	while not Game.new_game_slice(generation, 8000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game); Game.new_game_finalize()
	var by_pop: Array = Dynasty.choices(Game)
	by_pop.sort_custom(func(a, b): return int(Game.world["towns"][a["town_id"]]["econ"]["pop"]) > int(Game.world["towns"][b["town_id"]]["econ"]["pop"]))
	var seat := ""
	for choice: Dictionary in by_pop:
		if bool(HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false)):
			seat = str(choice["town_id"]); break
	check(seat != "", "selected a native ruling house")
	if seat == "": return _finish()
	var w: Dictionary = Game.world
	var town: Dictionary = w["towns"][seat]
	var e: Dictionary = town["econ"]
	var row := _cohort(e)
	check(not row.is_empty() and _anon(row) > 50, "the seat has a cohort row of common folk (%d)" % _anon(row))
	if row.is_empty(): return _finish()

	# --- Sickness reaches the common folk: the flux made common and deadly for the test, through the real town run.
	var flux: Dictionary = Sickness.data()["diseases"]["flux"]
	var saved := flux.duplicate(true)
	flux["base"] = 0.05; flux["death"] = {"child": 0.3, "adult": 0.3, "elder": 0.3}; flux["season"] = [1.0, 1.0, 1.0, 1.0]
	var b: Dictionary = Sickness.book(e)
	b.erase("tf")   # the town's cached factors are remade with the new rate
	var d := int(Game.day) + 1
	var pop0 := int(e["pop"]); var people0 := Families.people(row); var cases0 := int(b["cases"].get("flux", 0)); var act0 := _act(e, "flux")
	var deaths0 := int(b["deaths"].get("the flux", 0)); var census0 := _census_sick(e, "the flux")
	Sickness.town_day(Game, town, d, 0)
	var opened := Sickness.pool_sick(row, "flux")
	check(opened > 0, "common folk catch the flux (%d)" % opened)
	var pooled := 0
	for f in e["fams"]:
		if Population.is_cohort(f): pooled += Sickness.pool_sick(f, "flux")
	check(_act(e, "flux") - act0 >= pooled and int(b["cases"].get("flux", 0)) - cases0 >= pooled, "their cases count in the town's book")
	check(Families.people(row) == people0, "catching the flux kills nobody that day")
	var report := Migration.report(Game, seat)
	var sum := 0
	for dis in b["act"]: sum += int(b["act"][dis])
	check(int(report["sick"]) == sum, "the population report counts every open case")
	# Run the town forward until every case of the row has ended.
	var guard := 0
	while (row.has("psk") or Sickness.pool_sick(row) > 0) and guard < 40:
		guard += 1; d += 2
		flux["base"] = 0.0   # no new cases while the open ones run their course
		b.erase("tf")
		Sickness.town_day(Game, town, d, 0)
	check(not row.has("psk"), "every common case ends (%d runs)" % guard)
	var died := pop0 - int(e["pop"])
	var sick_deaths := int(b["deaths"].get("the flux", 0)) - deaths0
	var census_deaths := _census_sick(e, "the flux") - census0
	check(sick_deaths > 0, "deadly flux kills some of the common folk (%d)" % sick_deaths)
	check(census_deaths > 0 and census_deaths <= sick_deaths, "their deaths reach the census with the disease named (%d of %d)" % [census_deaths, sick_deaths])
	check(_bins(row) == _anon(row), "the row's age bins match its residents after deaths")
	check(died >= census_deaths and int(e["pop"]) >= 0, "the town's people fall with the deaths")
	check(_act(e, "flux") >= 0, "the town's open count never goes negative")
	var flux_left := 0
	for f in e["fams"]:
		if Population.is_cohort(f): flux_left += Sickness.pool_sick(f, "flux")
	check(flux_left == 0, "no common case of the flux stays open")
	for k in saved: flux[k] = saved[k]
	b.erase("tf")
	# Immunity as counts: a disease that leaves the recovered immune.
	var pox: Dictionary = Sickness.data()["diseases"]["pox"]
	if float(pox.get("immune", 0)) != 0.0:
		row["psk"] = [["pox", "adult", 5, 0, d + 1, d + 2, false]]
		e["sk"]["act"]["pox"] = int(e["sk"]["act"].get("pox", 0)) + 5
		Sickness.town_day(Game, town, d + 4, 0)
		check(Sickness._pool_immune(row, "pox", float(d + 4)) >= 5, "the recovered are immune to the pox")
	# A row that dies out or leaves takes its open cases off the town's count.
	var ghost := {"cohort": true, "gone": true, "psk": [["flux", "adult", 7, 0, d + 50, d + 60, false]], "id": -1}
	e["sk"]["act"]["flux"] = int(e["sk"]["act"].get("flux", 0)) + 7
	var before_ghost := _act(e, "flux")
	Sickness._pool_resolve(e, e["sk"], ghost, d, RandomNumberGenerator.new())
	check(_act(e, "flux") == before_ghost - 7 and not ghost.has("psk"), "a gone row's open cases leave the town's count")

	# --- Migration: war drives common households to a town of their people with room.
	var mine := Diplomacy.player_realm(w)
	var src: Dictionary = {}
	var dst: Dictionary = {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t) or String(t["faction"]) != mine: continue
		var f := _cohort(t["econ"])
		if f.is_empty() or Population.households(f) < 20: continue
		Migration.note_attack(w, String(tid), Game.day)
		var dest := Migration.destination(Game, t, f, "war", Game.day)
		w["migration"]["attacked"].erase(String(tid))
		if not dest.is_empty() and String(dest["faction"]) == mine: src = t; dst = dest; break
	check(not src.is_empty(), "a town of your realm has a common row and a place to flee to")
	if src.is_empty(): return _finish()
	var es: Dictionary = src["econ"]; var ed: Dictionary = dst["econ"]
	var fs := _cohort(es)
	var fd := Migration._row_for(ed, String(fs["race"]))
	check(String(fd.get("race", "")) == String(fs["race"]) and Persons.race_of(ed) == Persons.race_of(es), "refugees go to a town of their own race")
	Migration.note_attack(w, String(src["id"]), Game.day)
	check(Migration.push(Game, src, Game.day) == "war", "a sacked town is under the push of war")
	var dest_now := Migration.destination(Game, src, fs, "war", Game.day)
	Migration.note_attack(w, String(dest_now["id"]), Game.day)
	check(Migration.destination(Game, src, fs, "war", Game.day) != dest_now, "nobody flees into a town at war")
	w["migration"]["attacked"].erase(String(dest_now["id"]))
	var total_pop := int(es["pop"]) + int(ed["pop"])
	var total_coin := _purses(es) + _purses(ed)
	var total_goods := _goods(es) + _goods(ed)
	var hh0 := Population.households(fs); var hd0 := Population.households(fd)
	var ps0 := Families.people(fs); var pd0 := Families.people(fd)
	var left0 := int(es["stats"].get("left_war", 0))
	var moves0: int = (Census._book(es)["moves"] as Array).size()
	var moved := Migration.move_households(Game, src, fs, dst, 10, "war", Game.day)
	check(moved > 0 and Families.people(fs) == ps0 - moved and Families.people(fd) == pd0 + moved, "ten households' people move from one row to the other (%d)" % moved)
	check(Population.households(fs) == hh0 - 10 and Population.households(fd) == hd0 + 10, "the households move with them")
	check(int(es["pop"]) + int(ed["pop"]) == total_pop, "no person is made or lost")
	check(is_equal_approx(_purses(es) + _purses(ed), total_coin), "no coin is made or lost (house purchases go to the treasury)")
	check(_goods(es) + _goods(ed) == total_goods, "their stores move as goods, none made or lost")
	check(_bins(fs) == _anon(fs) and _bins(fd) == _anon(fd), "age bins match residents in both rows")
	check(int(es["stats"].get("left_war", 0)) == left0 + moved, "the old town counts them as left for war")
	var mv: Array = Census._book(es)["moves"]
	check(mv.size() == moves0 + 1 and String(mv[-1][2]) == "out" and String(mv[-1][4]) == "war" and int(mv[-1][5]) == moved, "the census records the move out")
	var mvd: Array = Census._book(ed)["moves"]
	check(String(mvd[-1][2]) == "in" and int(mvd[-1][5]) == moved, "and the move in")
	check(Migration.move_households(Game, src, fs, dst, Population.households(fs) + 5, "war", Game.day) > 0 and Population.households(fs) == 1, "one household always stays")
	# The weekly job: a sacked town of your realm sends people away by degrees, and big weeks are logged.
	var hh_all := 0
	for f in es["fams"]:
		if Population.is_cohort(f): hh_all += Population.households(f)
	var big_week := false; var logged := 0
	for i in 4:
		var left_before := int(es["stats"].get("left_war", 0))
		var log0: int = (w["log"] as Array).size()
		Migration.weekly(Game, Game.day + float(i * 7))
		var week := int(es["stats"].get("left_war", 0)) - left_before
		if week >= Migration.LOG_AT: big_week = true
		for line in (w["log"] as Array).slice(log0):
			if str(line).contains("War drove") and str(line).contains(String(src["name"])): logged += 1
		check(week < Migration.LOG_AT or logged > 0, "a week's departures are logged when %d or more leave (week %d: %d)" % [Migration.LOG_AT, i, week])
		logged = 0
	var hh_after := 0
	for f in es["fams"]:
		if Population.is_cohort(f): hh_after += Population.households(f)
	check(hh_after < hh_all, "weeks of war empty the common rows by degrees (%d -> %d households)" % [hh_all, hh_after])
	print("population034: war weeks, a big week seen: ", big_week)
	w["migration"]["attacked"].erase(String(src["id"]))
	# Hunger: famine stage 2 pushes; a whole cohort never flees through the tracked families' rule.
	es["fstage"] = 3
	check(Migration.push(Game, src, Game.day) == "hunger", "famine pushes people out")
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	check(not Barge.maybe_flee(Game, src, es, fs, 5, 30.0, rng, Game.day) and not fs.get("gone", false), "a whole common row never flees at once")
	es["fstage"] = 0
	# Crowding: no empty house and no home on the market; the crowded go where houses wait, and buy them.
	var crowded := _cohort(ed)
	ed["fams"][0]["homes"] = 0; ed["stock"]["home"] = 0
	var gave := int(crowded["homes"]) - maxi(1, int(crowded["homes"]) / 3)
	crowded["homes"] = int(crowded["homes"]) - gave
	ed["homes"] = int(ed["homes"]) - gave
	check(Migration.push(Game, dst, Game.day) == "crowd", "a town too crowded with no house to be had pushes people out (%s)" % Migration.push(Game, dst, Game.day))
	var where := Migration.destination(Game, dst, crowded, "crowd", Game.day)
	check(not where.is_empty() and int(where["econ"]["fams"][0]["homes"]) > 0, "the crowded go where empty town houses wait")
	if not where.is_empty():
		var ew: Dictionary = where["econ"]
		var fw := Migration._row_for(ew, String(crowded["race"]))
		var homes0 := int(fw["homes"]); var estate0 := int(ew["fams"][0]["homes"]); var treasury0 := float(ew["treasury"])
		crowded["purse"] = float(crowded["purse"]) + 100000.0
		var coin_all := _purses(ed) + _purses(ew)
		var n := Migration.move_households(Game, dst, crowded, where, 3, "crowd", Game.day)
		var bought := int(fw["homes"]) - homes0
		check(n > 0 and bought > 0 and bought <= 3, "arrivals buy empty town houses (%d)" % bought)
		check(int(ew["fams"][0]["homes"]) == estate0 - bought, "the houses come from the town estate")
		check(is_equal_approx(float(ew["treasury"]) - treasury0, float(bought) * float(Shelter.D()["estate_home"])), "at the estate price, into the treasury")
		check(is_equal_approx(_purses(ed) + _purses(ew), coin_all), "no coin is made or lost")
	# --- Save and load keep the war memory and the open common cases.
	Migration.note_attack(w, String(src["id"]), Game.day)
	row["psk"] = [["flux", "adult", 3, 1, d + 100, d + 110, false]]
	Game.save_game(); Game.wait_save()
	Game.world = {}; Game.rep = {}
	check(Game.load_game(), "real save reloads")
	w = Game.world
	check(Migration.push(Game, w["towns"][String(src["id"])], Game.day) == "war", "the memory of war survives a reload")
	var row2 := {}
	for f in w["towns"][seat]["econ"]["fams"]:
		if f.has("psk"): row2 = f
	check(not row2.is_empty() and int(row2["psk"][0][2]) == 3 and int(row2["psk"][0][3]) == 1, "open common cases survive a reload")
	check(Shelter.state_line(w["towns"][seat]["econ"], {"hl": {"how": "moved", "d": 0.0}}).begins_with("Came to town with no house"), "the homeless line says why")
	return _finish()
