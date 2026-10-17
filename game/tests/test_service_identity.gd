extends RefCounted

var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func cash(w: Dictionary) -> float:
	var n := 0.0
	for t in w.get("towns", {}).values():
		var e: Dictionary = t.get("econ", {})
		n += float(e.get("treasury", 0))
		for f in e.get("fams", []): n += float(f.get("purse", 0))
		for b in e.get("biz", []): n += float(b.get("till", 0))
	return n

func people(w: Dictionary) -> int:
	var n := 0
	for t in w.get("towns", {}).values(): n += Census.people(t["econ"])
	return n

func unit_state(u: Unit) -> Dictionary:
	var d := u.to_dict().duplicate(true)
	d.erase("family"); d.erase("home_town")
	return d

func retired_officer_floor() -> void:
	# A real draft binds a newly allocated Unit to a real household. The split
	# faction turn releases him before its queued rank-tree work removes his post.
	var wb := {}
	var town := {}
	var pool := []
	for band in Game.world["warbands"].values():
		if not Army.is_field(band): continue
		var source: Dictionary = Game.world["towns"].get(String(band.get("home", "")), {})
		var candidates := People.draft_pool(source)
		if not candidates.is_empty(): wb = band; town = source; pool = candidates; break
	check(not wb.is_empty(), "a real field force has an available registered draft person")
	if wb.is_empty(): return
	var fid := String(wb["faction"])
	var rng := RandomNumberGenerator.new(); rng.seed = 223
	var officer := Factory.make_troop(rng, fid, Factory.pick_troop(rng, fid))
	var family := People.draft(town, pool, "army")
	check(family >= 0, "retiring officer is an actual drafted household member")
	if family < 0: return
	People.bind(town, family, officer, "army")
	wb["units"].append(officer)
	Army.enlist(Game, wb)
	var r := Army.rec(Game.world, fid)
	if (r["posts"] as Array).is_empty(): r["posts"].append(officer.uid)
	else: r["posts"][0] = officer.uid
	officer.role = "officer"
	officer.rank = Army.rank_at(0, Army.ranks(Army.cul_of_faction(fid), "army"))
	officer.unpaid_days = int(Army.A()["desert_days"])
	Game.world["factions"][fid]["treasury"] = 0.0
	Game.world["factions"][fid]["loot"] = 0.0
	Army.faction_day(Game, fid, int(Game.day), true)
	check(not Persons.live_uids(Game).has(officer.uid) and not Army.state(Game.world)["roll"].has(str(officer.uid)), "split faction turn lawfully releases the highest allocated officer")
	check((r["posts"] as Array).has(officer.uid), "queued tree boundary retains the departed officer UID")
	var legacy := Game._save_tree()
	legacy.erase("next_unit_uid")
	var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	Unit._next_uid = 1
	check(Game.load_game() and Unit._next_uid > officer.uid, "cold old-save load protects a retired faction post UID before tree work")
	# Candidates are another retained reference even after their post is cleared.
	var candidate := Unit._next_uid + 20
	r = Army.rec(Game.world, fid)
	r["fights"].append({"p": 0, "c": [candidate], "beat": []})
	legacy = Game._save_tree(); legacy.erase("next_unit_uid")
	file = FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	Unit._next_uid = 1
	check(Game.load_game() and Unit._next_uid > candidate, "cold old-save load protects retained faction fight candidates")

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"
	Game.new_game(2026)
	var w: Dictionary = Game.world
	var from := {}
	var to := {}
	var third := {}
	var family := {}
	var planned := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		var mates: Array = w["towns"].values().filter(func(x): return x["id"] != tid and x["faction"] == t["faction"])
		if mates.size() < 2: continue
		var b := Militia.band_of(Game, tid)
		if b.is_empty(): continue
		TownDefence.set_muster(Game, t, false, false)
		for f in t["econ"]["fams"]:
			var plan := ServiceIdentity.reserve_move(Game, t, f, mates[0])
			if plan["ok"] and (plan["units"] as Array).size() >= 2:
				from = t; to = mates[0]; third = mates[1]; family = f; planned = plan
				break
		if not family.is_empty(): break
	check(not family.is_empty(), "generated registered reserve household is available")
	if family.is_empty(): return fails
	var units: Array = planned["units"].duplicate()
	var first: Unit = units[0]
	var sick_person := Persons.by_uid(family, first.uid)
	var sick_rng := RandomNumberGenerator.new(); sick_rng.seed = 917
	var infected := false
	for disease in Sickness.data()["diseases"]:
		if Sickness.infect(Game, from, family, sick_person, disease, Game.day, "garrison:identity fixture", sick_rng, first): infected = true; break
	check(infected and first.sick != "", "actual registered reserve has a real open sickness case")
	Persons.remember_unpaid(sick_person, "militia", 3, Game.day, 4)
	var memory_before: Dictionary = Persons.g(sick_person, Persons.SERVICE_MEMORY, {}).duplicate(true)
	var source_people: Array = family["pp"].duplicate(true)
	var source_id := int(family["id"])
	var before_people := people(w)
	var before_cash := cash(w)
	var before_live := Persons.live_uids(Game)
	var unit_before := {}
	for u in units: unit_before[u.uid] = unit_state(u)
	# Every rejected move must leave all economy, Unit, and counter data intact.
	var snap := Game._save_tree()
	var foreign: Dictionary = w["towns"].values().filter(func(x): return x["faction"] != from["faction"])[0]
	check(Barge.move_family(Game, from, family, foreign, "work", Game.day).is_empty(), "cross-faction reserve transfer is rejected")
	check(Game._save_tree() == snap, "rejected transfer precedes every economy mutation")
	var p := Persons.by_uid(family, first.uid)
	var saved_uid := int(p[5])
	p[5] = Unit._next_uid + 100
	snap = Game._save_tree()
	check(Barge.move_family(Game, from, family, to, "work", Game.day).is_empty() and Game._save_tree() == snap, "missing binding rejects the entire move unchanged")
	p[5] = saved_uid
	TownDefence.set_muster(Game, from, true)
	snap = Game._save_tree()
	check(Barge.move_family(Game, from, family, to, "work", Game.day).is_empty() and Game._save_tree() == snap, "active militia household cannot move")
	TownDefence.set_muster(Game, from, false, false)
	TownDefence.set_muster(Game, to, false, false)
	var nf := Barge.move_family(Game, from, family, to, "work", Game.day)
	check(not nf.is_empty(), "reserve household migrates with its existing service")
	if nf.is_empty(): return fails
	check(people(w) == before_people and absf(cash(w) - before_cash) < 0.0001, "migration conserves people and actual cash")
	check(Persons.live_uids(Game) == before_live, "migration neither deletes nor recruits registered forces")
	for u in units:
		check(u.home_town == to["id"] and u.family == int(nf["id"]) and Militia.units_of(Game, to["id"]).has(u) and not Militia.units_of(Game, from["id"]).has(u), "existing Unit moves to its actual new household and roster")
		check(unit_state(u) == unit_before[u.uid], "kit, rank, wages, sickness and Unit identity survive")
	var migrated_sick := Persons.by_uid(nf, first.uid)
	check(not Sickness.case_of(nf, int(migrated_sick[0])).is_empty() and Persons.g(migrated_sick, Persons.SERVICE_MEMORY, {}) == memory_before, "actual sickness case and unpaid service memory travel with the person")
	check(Families.serving(nf) == 0, "destination reserves retain civilian availability")
	# Recreate the historical copying defect generally, using the same people.
	family["pp"] = source_people.duplicate(true)
	for u in units:
		Militia.band_of(Game, to["id"])["units"].erase(u)
		Militia.band_of(Game, from["id"])["units"].append(u)
		u.home_town = from["id"]; u.family = source_id
	# Legacy current Unit facts can be newer than the copied household mirror.
	if nf.has("sk"): nf["sk"].erase(str(migrated_sick[0]))
	var report := ServiceIdentity.after_load(Game)
	check(int(report["transferred"]) == units.size(), "load repair follows exact migration lineage for every bound member")
	check(Persons.live_uids(Game) == before_live and people(w) == before_people and absf(cash(w) - before_cash) < 0.0001, "legacy repair preserves forces, people and cash")
	for u in units: check(unit_state(u) == unit_before[u.uid], "legacy repair preserves all Unit service and equipment facts")
	check(first.sick != "", "legacy missing case mirror cannot silently heal a living sick Unit")
	snap = Game._save_tree()
	report = ServiceIdentity.after_load(Game)
	check(Game._save_tree() == snap and int(report["transferred"]) == 0, "load repair is idempotent")
	# A second real move into drilling militia changes only current service.
	TownDefence.set_muster(Game, third, false, true)
	var nf2 := Barge.move_family(Game, to, nf, third, "work", Game.day)
	check(not nf2.is_empty() and int(nf2["serve"].get("militia", 0)) == units.size(), "destination drill counts each transferred reserve once")
	if nf2.is_empty(): return fails
	TownDefence.set_muster(Game, third, false, false)
	# Exact copied release history is propagated, never converted into a death.
	var q := Persons.by_uid(nf2, first.uid)
	var source_q := Persons.by_uid(nf, first.uid)
	if source_q.is_empty():
		for candidate in nf["pp"]:
			if ServiceIdentity.same_person(candidate, q): source_q = candidate; break
	Militia.band_of(Game, third["id"])["units"].erase(first)
	source_q[4] = ""; source_q[5] = -1
	Persons.log_life(source_q, Game.day + 1, "home", "militia")
	var deaths := JSON.stringify(Census._book(third["econ"])["deaths"])
	report = ServiceIdentity.after_load(Game)
	check(q[4] == "" and int(q[5]) == -1 and int(report["released"]) == 1, "proven dated release repairs its stale active copy")
	check(JSON.stringify(Census._book(third["econ"])["deaths"]) == deaths, "release repair invents no death")
	# A UID match with different identity is insufficient proof.
	if units.size() > 1:
		var other: Unit = units[1]
		var active_p := Persons.by_uid(nf2, other.uid)
		var original_p: Array = []
		for candidate in nf["pp"]:
			if ServiceIdentity.same_person(candidate, active_p): original_p = candidate; break
		original_p[4] = "reserve"; original_p[5] = other.uid
		other.home_town = to["id"]; other.family = int(nf["id"])
		Militia.band_of(Game, third["id"])["units"].erase(other)
		Militia.band_of(Game, to["id"])["units"].append(other)
		active_p[3] = float(active_p[3]) - 1
		snap = Game._save_tree()
		report = ServiceIdentity.after_load(Game)
		check(Game._save_tree() == snap and int(report["unresolved"]) > 0, "conflicting person identity remains unchanged and reported")
	# Save during the world's actual staged draft, then sweep the loaded register.
	Game.new_game(2026)
	w = Game.world
	# Ordinary daily scheduling creates this queue before requesting a muster.
	w["work"] = []
	var muster_rng := RandomNumberGenerator.new(); muster_rng.seed = 864
	var bound_pending := []
	for fid in w["factions"]:
		CampaignWorld.spawn_faction_band(Game, fid, muster_rng, true, false, ["spawn", fid])
		for step in 20:
			bound_pending = CampaignWorld.mustering_units(w).filter(func(u): return u.family >= 0 and not u.dead)
			if not bound_pending.is_empty() or w["work"].is_empty(): break
			CampaignWorld._do_work(Game, muster_rng)
		if not bound_pending.is_empty(): break
	check(not bound_pending.is_empty(), "actual staged draft contains registered people before map insertion")
	if not bound_pending.is_empty():
		var pending_ids: Array = bound_pending.map(func(u): return u.uid)
		Game.save_game()
		check(Game.load_game(), "mid-muster save reloads")
		var pending_after: Array = CampaignWorld.mustering_units(Game.world)
		Persons.sweep(Game)
		Army.sweep(Game)
		for uid in pending_ids:
			var found: Array = pending_after.filter(func(u): return u.uid == uid)
			check(found.size() == 1 and Persons.live_uids(Game).has(uid), "loaded queued soldier remains living through both sweeps")
			if found.size() == 1:
				var u: Unit = found[0]
				var f := People.fam_of(Game.world["towns"][u.home_town], u.family)
				check(not Persons.by_uid(f, uid).is_empty(), "queued soldier keeps his exact household person after sweep")
	# Saved allocation history survives retirement of the greatest Unit UID.
	Unit._next_uid += 10000
	var high := Unit._next_uid
	Game.save_game()
	Unit._next_uid = 1
	check(Game.load_game() and Unit._next_uid >= high, "saved UID high-water survives cold load with no Unit at its ceiling")
	var retained := Unit._next_uid + 100
	if not Game.world.has("census_fate"): Game.world["census_fate"] = {}
	Game.world["census_fate"][str(retained)] = ["battle", "retained reference", 0]
	check(ServiceIdentity.uid_floor(Game) > retained, "old-save retained fate references bound future allocation")
	var legacy := Game._save_tree()
	legacy.erase("next_unit_uid")
	var legacy_file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy)); legacy_file.close()
	Unit._next_uid = 1
	check(Game.load_game() and Unit._next_uid > retained, "old save without counter restores its retained-reference floor before allocation")
	retired_officer_floor()
	print("service identity checks: %d; report: %s" % [checks, ServiceIdentity.last_report])
	return fails
