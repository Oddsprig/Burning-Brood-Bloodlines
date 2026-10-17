extends RefCounted
## Registered professional guards from an ordinary generated campaign only.
## Native death and save/load APIs are unchanged on delivered v045.
var checks := 0
var fails := 0
var cases := 0
var original_save := ""
var base_save := ""
var killed_save := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.00001, "%s (%.9f versus %.9f)" % [message, a, b])

func identity(e: Dictionary, omit: int = -1) -> Dictionary:
	var out := {}
	for f in e["fams"]:
		for group in ["pp", "kp"]:
			for p in f.get(group, []):
				if int(p[0]) == omit: continue
				# Kinship, work history and sickness may legitimately change at death.
				out[str(int(p[0]))] = [int(f["id"]), p[1], p[2], p[3], p[4], p[5], p[6], Persons.g(p, 7, "")]
	return out

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= 0.000001 + 0.0000000001 * maxf(absf(float(a)), absf(float(b)))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key], b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not equivalent(a[i], b[i]): return false
		return true
	return a == b

func dated_ownership(e: Dictionary) -> Dictionary:
	var out: Dictionary = e.get("harvest_book", {}).duplicate(true)
	# The real loader rebuilds derived balances and household food reserves.
	# Dates, production sources, owned quantities and pending receipts stay real.
	out.erase("balances")
	for rows in out.get("lots", {}).values():
		for row in rows: row.erase("reserve")
	return out

func unit_present(uid: int) -> bool:
	for band in Game.world.get("warbands", {}).values():
		for u in band.get("units", []):
			if u is Unit and u.uid == uid: return true
	return false

func registered_guards(f: Dictionary) -> int:
	var n := 0
	for p in f.get("pp", []):
		if String(p[4]) == "guard": n += 1
	return n

func labour(e: Dictionary, label: String) -> void:
	var jobs := {}
	var population := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		var home := {}
		var registered: int = f.get("kp", []).size()
		for p in f.get("pp", []):
			if not String(p[4]) in Persons.AWAY: registered += 1
			if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]: home[int(p[0])] = true
		var available := maxi(0, Families.adults(f) - Families.serving(f))
		var assigned: int = int(f.get("hands", 0)) + int(f.get("idle", 0)) + f.get("keeps", []).size()
		for bid in f.get("jobs", {}):
			var n := int(f["jobs"][bid]); assigned += n
			jobs[int(bid)] = int(jobs.get(int(bid), 0)) + n
		for n in f.get("cj", {}).values(): assigned += int(n)
		check(available == home.size(), label + ": civilian register equals available adult capacity")
		check(assigned == available, label + ": adult assignments cover capacity exactly once")
		var work := Persons.work(e, f)
		var work_adults := 0
		for p in f.get("pp", []):
			if int(p[6]) != 0: continue
			var pid := int(p[0])
			check(work.has(pid) == home.has(pid), label + ": native work includes exactly eligible civilian identities")
			if work.has(pid): work_adults += 1
		check(work_adults == available, label + ": native adult work coverage equals available capacity")
		check(registered == Families.people(f), label + ": register population remains physical")
		population += Families.people(f)
	for b in e["biz"]:
		check(int(jobs.get(int(b["id"]), 0)) == int(b["workers"]), label + ": employer workers equal household job records")
	check(population == int(e["pop"]), label + ": town population equals surviving family rows")
	check(Census.adds_up(Census.balance(e)), label + ": native current census balance")

func candidates(cause: String) -> Dictionary:
	var out := {}
	var tids: Array = Game.world.get("town_guards", {}).keys(); tids.sort()
	for tid in tids:
		var town: Dictionary = Game.world["towns"][tid]
		var e: Dictionary = town["econ"]
		var culture := String(e["culture"])
		if out.has(culture): continue
		var band := TownDefence.guard_band(Game, String(tid))
		if not band.get("professional", false): continue
		for u in band.get("units", []):
			if not u is Unit or u.dead or u.family < 0 or u.family >= e["fams"].size(): continue
			var f: Dictionary = e["fams"][u.family]
			var p := Persons.by_uid(f, u.uid)
			if p.is_empty() or String(p[4]) != "guard" or int(p[6]) != 0: continue
			if cause == "childbirth" and int(p[2]) != 1: continue
			out[culture] = {"town": String(tid), "family": u.family, "pid": int(p[0]), "uid": u.uid}
			break
	return out

func death(row: Dictionary, culture: String, cause: String) -> Dictionary:
	var town: Dictionary = Game.world["towns"][row["town"]]
	var e: Dictionary = town["econ"]
	var f: Dictionary = e["fams"][int(row["family"])]
	var p := Persons.by_uid(f, int(row["uid"]))
	var unit: Unit = null
	for u in TownDefence.guards(Game, String(row["town"])):
		if u.uid == int(row["uid"]): unit = u; break
	var label := "%s %s" % [culture, cause]
	check(unit != null and not p.is_empty(), label + ": selected real guard exists at native death boundary")
	if unit == null or p.is_empty(): return {}
	labour(e, label + " before")
	var before_people := Families.people(f)
	var before_adults := Families.adults(f)
	var before_pop := int(e["pop"])
	var before_town_adults := int(e["adults"])
	var before_guard := int(f.get("serve", {}).get("guard", 0))
	check(before_guard == registered_guards(f), label + ": opening guard places match actual registered guards")
	check(Army.state(Game.world)["roll"].has(str(int(row["uid"]))), label + ": selected real guard has an Army roll entry")
	var before_deaths := Census.sum(Census.current(e)["deaths"])
	var before_total := int(Census._book(e).get("dt", 0))
	var before_stats := int(e["stats"].get("deaths", 0))
	var survivors := identity(e, int(p[0]))
	var harvest: Dictionary = e.get("harvest_book", {}).duplicate(true)
	var cash := Barge.holdings(Game)
	var town_cash := TownEcon.town_gold(e)
	Sickness.kill(Game, town, f, p, Game.day, cause, "guard death regression")
	cases += 1
	check(Families.people(f) == before_people - 1 and Families.adults(f) == before_adults - 1, label + ": one actual adult leaves its family row")
	check(int(e["pop"]) == before_pop - 1 and int(e["adults"]) == before_town_adults - 1, label + ": one actual adult leaves town counts")
	check(int(f.get("serve", {}).get("guard", 0)) == before_guard - 1, label + ": native death releases exactly one guard service place")
	check(int(f.get("serve", {}).get("guard", 0)) == registered_guards(f), label + ": guard count matches surviving registered guards")
	check(unit.dead and not unit_present(int(row["uid"])), label + ": actual Unit is dead and removed from its force")
	check(not Army.state(Game.world)["roll"].has(str(int(row["uid"]))), label + ": dead guard leaves Army roll")
	check(Persons.by_pid(f, int(row["pid"])).is_empty(), label + ": deceased identity leaves living register")
	check(identity(e) == survivors, label + ": every surviving identity is preserved")
	check(e.get("harvest_book", {}) == harvest, label + ": native death leaves dated harvest book unchanged")
	near(Barge.holdings(Game), cash, label + ": native death creates or destroys no ledger coins")
	near(TownEcon.town_gold(e), town_cash, label + ": reassignment conserves existing town coins")
	# Exercise the normal cleanup readers after removal: they cannot book it twice.
	Army.sweep(Game)
	Persons.sweep_town(Game, town, Persons.live_uids(Game))
	check(Census.sum(Census.current(e)["deaths"]) == before_deaths + 1 and int(Census._book(e)["dt"]) == before_total + 1, label + ": census records exactly one counted death")
	check(int(e["stats"]["deaths"]) == before_stats + 1, label + ": native death statistic increases once")
	var entries := 0
	for d in Census._book(e)["deaths"]:
		if int(d[1]) != int(row["pid"]): continue
		entries += 1
		check(String(d[5]) == cause and float(d[0]) == Game.day and int(d[9]) == 1, label + ": death retains actual cause, day and census inclusion")
	check(entries == 1, label + ": deceased PID has exactly one census death entry")
	labour(e, label + " after")
	print("GUARD DEATH case culture=", culture, " cause=", cause, " town=", row["town"], " family=", row["family"], " pid=", row["pid"])
	return row

func save_at(path: String) -> bool:
	Game.SAVE_PATH = path
	Game.save_game()
	var exists := FileAccess.file_exists(path)
	check(exists, "native isolated guard checkpoint is saved")
	return exists

func roundtrip(row: Dictionary) -> void:
	var e: Dictionary = Game.world["towns"][row["town"]]["econ"]
	var expected_identity := identity(e)
	var expected_book := dated_ownership(e)
	var pop := int(e["pop"]); var adults := int(e["adults"])
	var deaths := int(Census._book(e)["dt"])
	var guards := int(e["fams"][int(row["family"])].get("serve", {}).get("guard", 0))
	var cash := Barge.holdings(Game)
	if not save_at(killed_save): return
	var loaded := Game.load_game()
	check(loaded, "native killed-guard checkpoint loads")
	if not loaded: return
	e = Game.world["towns"][row["town"]]["econ"]
	var f: Dictionary = e["fams"][int(row["family"])]
	check(int(e["pop"]) == pop and int(e["adults"]) == adults and int(Census._book(e)["dt"]) == deaths, "killed-guard load preserves actual counts and records no second death")
	check(Persons.by_pid(f, int(row["pid"])).is_empty() and not unit_present(int(row["uid"])), "killed guard cannot return through register or force load")
	check(not Army.state(Game.world)["roll"].has(str(int(row["uid"]))), "killed guard cannot return through Army roll load")
	check(int(f.get("serve", {}).get("guard", 0)) == guards and guards == registered_guards(f), "native load preserves absence of phantom guard service")
	check(equivalent(identity(e), expected_identity), "native save/load preserves surviving identities")
	check(equivalent(dated_ownership(e), expected_book), "native save/load preserves dated ownership and pending harvest receipts")
	check(absf(Barge.holdings(Game) - cash) < 1.0, "native save/load conserves global coins at unchanged ledger tolerance")
	labour(e, "killed-guard loaded boundary")

func finish() -> int:
	Game.wait_save()
	for path in [base_save, killed_save]:
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	Game.SAVE_PATH = original_save
	print("GUARD DEATH v046 cases=", cases, " checks=", checks, " failures=", fails)
	return fails

func run(_tree: SceneTree) -> int:
	original_save = Game.SAVE_PATH
	var prefix := "user://test_guard_death_v046_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	base_save = prefix + "_base.json"; killed_save = prefix + "_killed.json"
	Game.SAVE_PATH = base_save
	WorldGen.gen_size = "large"
	Game.new_game(901)
	Game.advance_time(1.0, true)
	check(Game.day == 1.0 and (Game.world.get("work", []) as Array).is_empty(), "ordinary campaign completes actual day1 guard instantiation")
	if not save_at(base_save): return finish()
	var first := true
	for cause in ["sickness", "starved", "childbirth"]:
		if not first:
			Game.SAVE_PATH = base_save
			if not Game.load_game():
				check(false, "actual generated control checkpoint loads")
				return finish()
		var pool := candidates(String(cause))
		check(not pool.is_empty(), String(cause) + ": at least one actual registered eligible professional guard")
		var cultures: Array = pool.keys(); cultures.sort()
		var absent := []
		for culture in TownEcon.data()["cultures"]:
			if not pool.has(culture): absent.append(culture)
		var last := {}
		for culture in cultures:
			last = death(pool[culture], String(culture), String(cause))
		print("GUARD DEATH coverage cause=", cause, " actual_eligible_cultures=", cultures, " without_eligible_native_guard=", absent)
		if first and not last.is_empty(): roundtrip(last)
		first = false
	return finish()
