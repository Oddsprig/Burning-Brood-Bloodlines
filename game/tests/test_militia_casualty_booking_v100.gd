extends RefCounted
## v0.100 fallback: real BattleSim casualties, native defend-allies handoff and settlement.
## A sheltered third militiaman makes the survivor assertions non-vacuous.
## No assigned death, wound, hit, winner, or post-battle resurrection.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.

const TID := "militia_booking_v100"
const SEED := 1001701
var fails: int = 0
var checks: int = 0
var deadline: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL militia booking v100: ", message)

func within_budget() -> bool:
	var ok: bool = Time.get_ticks_msec() < deadline
	check(ok, "setup, native combat and every assertion must finish within 45 seconds")
	return ok

func run(tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	deadline = started + 45000
	var saved: Dictionary = {"world": Game.world, "company": Game.company, "squads": Game.squads,
		"stash": Game.stash, "contract": Game.contract, "pending": Game.pending_battle,
		"day": Game.day, "gold": Game.gold, "location": Game.location,
		"creatures": Monsters.creatures_on, "ctx": Census._ctx.duplicate(),
		"w": WorldGen.W, "h": WorldGen.H, "tf": WorldGen.TF}
	Census.ctx_end()
	await exercise(tree)
	Game.world = saved["world"]; Game.company = saved["company"]; Game.squads = saved["squads"]
	Game.stash = saved["stash"]; Game.contract = saved["contract"]; Game.pending_battle = saved["pending"]
	Game.day = saved["day"]; Game.gold = saved["gold"]; Game.location = saved["location"]
	Monsters.creatures_on = saved["creatures"]; Census._ctx = saved["ctx"]
	WorldGen.use_world({"w": saved["w"], "h": saved["h"], "tf": saved["tf"]})
	check(Time.get_ticks_msec() - started < 55000, "complete fallback stays under 55 seconds")
	print("MILITIA BOOKING v100 checks=", checks, " failures=", fails,
		" elapsed_ms=", Time.get_ticks_msec() - started)
	return fails

func fixture() -> Dictionary:
	# One small native economy on Normal map geometry, at day one. No full world generation.
	# Same economy-generation inputs as test_dynasty_foundation's bounded native fixture.
	WorldGen.set_size(float(WorldGen.SIZES["normal"]["stretch"]))
	Game.day = 1.0; Game.gold = 0; Game.location = TID
	Game.company = []; Game.squads = {}; Game.stash = []; Game.pending_battle = {}
	var town: Dictionary = {"id": TID, "name": "Booking Ford", "culture": "middle",
		"faction": "middle_kingdom", "capital": false, "size": 2, "wealth": 1, "specialty": "farming",
		"pos": WorldGen.cell_center(Vector2i(30, 25)), "recruits": [], "shop": [],
		"roads": [], "neighbours": [], "region": "middle", "crafters": {}, "healer": {},
		"prices": {}, "material_prices": {}, "contracts": [], "next_refresh": 0.0}
	Game.world = {"version": 1, "seed": SEED, "w": WorldGen.W, "h": WorldGen.H,
		"cell": WorldGen.CELL, "tf": 1.0, "last_day": 1, "next_id": 1, "work": [],
		"terrain": "g".repeat(WorldGen.W * WorldGen.H), "road": "0".repeat(WorldGen.W * WorldGen.H),
		"region": "0".repeat(WorldGen.W * WorldGen.H), "towns": {TID: town}, "warbands": {},
		"militia": {}, "lairs": {}, "creatures_enabled": true,
		"factions": {"middle_kingdom": {"treasury": 3456.0, "loot": 0.0, "towns": [TID], "capital": TID}},
		"party": {"pos": town["pos"], "target": town["pos"], "path": [], "dest_town": "",
			"arrived": "", "safe_until": 0.0, "waiting": false},
		"start_town": TID, "log": [], "encounter": ""}
	Monsters.use_world(Game.world)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	Economy.make_crafters(town, rng); Economy.roll_prices(town, rng)
	var old_scale: Variant = EconGen.town_scale_override
	EconGen.town_scale_override = 0.15
	EconGen.generate(Game.world, town, rng)
	EconGen.town_scale_override = old_scale
	var militia: Array = []
	for i: int in 3:
		var unit: Unit = Militia.make_unit(town, rng)
		check(unit.family >= 0, "native militia recruitment finds a real household")
		if unit.family < 0: return {}
		militia.append(unit)
	var mid: String = CampaignWorld.spawn_warband(Game, "middle_kingdom", town["pos"], 3, "militia", rng,
		{"units": militia, "home": TID, "anchor": town["pos"]})
	Game.world["militia"][TID] = mid
	var enemies: Array = Creatures.make_group(rng, "bear", 8)
	var wid: String = CampaignWorld.spawn_warband(Game, "beasts", town["pos"] + Vector2(40, 0), 8, "beasts", rng,
		{"units": enemies, "home": "", "creature": "bear"})
	check(mid != "" and wid != "", "native militia and creature bands both spawn")
	if mid == "" or wid == "": return {}
	Game.contract = {"kind": "defend", "town_id": TID, "target_id": wid, "pay": 0}
	var pending: Dictionary = {"warband_id": wid, "enemy": enemies, "seed": SEED}
	Monsters.battle_extras(Game, Game.world["warbands"][wid], pending)
	Game.pending_battle = pending
	check(pending.get("militia_town", "") == TID and int(pending.get("militia_start", 0)) == 3
		and pending.get("allies", []) == militia, "native defend handoff must include all three actual militia")
	return town

func person_count(e: Dictionary, uid: String) -> int:
	var n: int = 0
	for family: Dictionary in e["fams"]:
		for person: Array in family.get("pp", []) + family.get("kp", []):
			if str(Persons.g(person, Persons.PERSON_UID, "")) == uid: n += 1
	return n

func survivor_state(unit: Unit) -> Dictionary:
	# Native salvage may legitimately re-equip a survivor; identity and health must not change.
	var state: Dictionary = unit.to_dict().duplicate(true)
	state.erase("equip"); state.erase("quiver")
	return state

func exercise(tree: SceneTree) -> void:
	var town: Dictionary = fixture()
	if fails > 0 or town.is_empty() or not within_budget(): return
	var e: Dictionary = town["econ"]
	var band: Dictionary = Militia.band_of(Game, TID)
	var roster: Array = (band["units"] as Array).duplicate()
	var identities: Dictionary = {}
	for unit: Unit in roster:
		var family: Dictionary = People.fam_of(town, unit.family)
		var person: Array = Persons.by_uid(family, unit.uid)
		check(not unit.dead and not person.is_empty(), "every participant starts living and registered")
		if person.is_empty(): return
		var uid: String = str(Persons.g(person, Persons.PERSON_UID, ""))
		check(str(person[4]) == "militia" and int(person[5]) == unit.uid and int(person[6]) == 0
			and uid not in ["", "0"] and person_count(e, uid) == 1, "one real adult militia person per native Unit")
		check(not identities.has(unit.uid), "native militia Unit IDs are unique")
		identities[unit.uid] = {"family": unit.family, "pid": int(person[0]), "uid": uid,
			"sex": int(person[2]), "person": person.duplicate(true)}
	if fails > 0: return
	var before: Dictionary = Game._serialize({"econ": e})
	var before_census: Dictionary = People.census(e)
	var book: Dictionary = Census._book(e)
	var before_book: Dictionary = book.duplicate(true)
	var sim: BattleSim = BattleSim.new()
	# The first militia holds an enclosed rear cell; two exposed comrades face eight native bears.
	# Ordinary blocked tiles preserve a real survivor without changing any combat/body/death rules.
	var tiles: Array = []
	for y: int in 12:
		var row: String = "################" if y in [0, 11] else "#..............#"
		if y in [1, 2]: row = "#.##...........#" if y == 1 else "####...........#"
		tiles.append(row)
	sim.setup(Game.pending_battle["allies"], Game.pending_battle["enemy"], SEED,
		{"w": 16, "h": 12, "tiles": tiles, "max_ticks": 1200, "verbose": false,
			"log_moves": false, "combat_journal": false,
			"cells0": [Vector2i(1, 1), Vector2i(9, 5), Vector2i(9, 8)],
			"cells1": [Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4), Vector2i(10, 5),
				Vector2i(8, 7), Vector2i(9, 7), Vector2i(10, 7), Vector2i(10, 8)]})
	while not sim.is_over():
		sim.step()
		if sim.tick % 64 == 0:
			if not within_budget(): return
			await tree.process_frame
	check(sim.is_over() and sim.tick > 0, "the native battle actually finishes")
	# Real native aftermath bleeding is allowed; use the actual field holder and ordinary tending.
	for i: int in 120:
		sim.aftermath_step(sim.winner, 0)
		if i % 32 == 0:
			if not within_budget(): return
			await tree.process_frame
	var screen: Variant = load("res://battle/battle.gd").new()
	screen.sim = sim
	var result: Dictionary = screen.build_result()
	screen.free()
	check(result["player_units"] == roster and result["winner"] == sim.winner
		and int(result["ticks"]) == sim.tick, "settle the real unmodified battle-screen result")
	var fallen: Array = roster.filter(func(u: Unit): return u.dead)
	var survivors: Array = roster.filter(func(u: Unit): return not u.dead)
	check(not fallen.is_empty(), "at least one militia must really die; zero-casualty runs fail")
	check(not survivors.is_empty(), "at least one actual militia survivor must exercise preservation")
	var survivor_states: Dictionary = {}
	for unit: Unit in survivors: survivor_states[unit.uid] = survivor_state(unit)
	for unit: Unit in fallen:
		var witnessed: int = 0
		for event: Dictionary in sim.events:
			var target: int = int(event.get("target", -1))
			if event.get("type", "") == "death" and target >= 0 and sim.fighters[target].unit == unit:
				witnessed += 1
		check(witnessed == 1, "each casualty has exactly one native death event: " + str(unit.uid))
	check(e["pop"] == before["econ"]["pop"] and e["adults"] == before["econ"]["adults"]
		and book == before_book, "combat itself has not pre-booked any campaign casualty")
	if fails > 0 or not within_budget(): return
	print("MILITIA BOOKING native seed=", SEED, " ticks=", sim.tick, " winner=", sim.winner,
		" fallen=", fallen.map(func(u: Unit): return u.uid),
		" survivors=", survivors.map(func(u: Unit): return u.uid))
	CampaignWorld._battle_result(Game, result)
	verify(town, band, roster, fallen, survivors, survivor_states, identities, before["econ"], before_census, before_book)
	# Replay both entry points. The complete town and militia must stay byte-for-byte equivalent as values.
	var settled: Variant = Game._serialize({"town": town, "band": band})
	CampaignWorld._battle_result(Game, result)
	var wid: String = str(Game.pending_battle["warband_id"])
	Monsters.on_battle_result(Game, wid, Game.world["warbands"].get(wid, {}), result)
	check(Militia.bury_dead(Game, TID) == 0, "repeated burial consumes zero additional people")
	check(Game._serialize({"town": town, "band": band}) == settled, "repeated settlement changes no town or militia value")
	verify(town, band, roster, fallen, survivors, survivor_states, identities, before["econ"], before_census, before_book)
	within_budget()

func verify(town: Dictionary, band: Dictionary, roster: Array, fallen: Array, survivors: Array,
		survivor_states: Dictionary, identities: Dictionary, before: Dictionary,
		before_census: Dictionary, before_book: Dictionary) -> void:
	var e: Dictionary = town["econ"]
	var n: int = fallen.size()
	var by_family: Dictionary = {}
	var lost_sex: Array = [0, 0]
	for unit: Unit in fallen:
		var identity: Dictionary = identities[unit.uid]
		var fid: int = int(identity["family"])
		if not by_family.has(fid): by_family[fid] = [0, 0]
		by_family[fid][int(identity["sex"])] += 1
		lost_sex[int(identity["sex"])] += 1
		check(not (band["units"] as Array).has(unit)
			and Persons.by_uid(People.fam_of(town, fid), unit.uid).is_empty()
			and person_count(e, str(identity["uid"])) == 0, "fallen leaves roster and all living person registers: " + str(unit.uid))
	check((band["units"] as Array).size() == roster.size() - n, "roster loses exactly the actual fallen")
	for family: Dictionary in e["fams"]:
		var fid: int = int(family["id"])
		var old: Dictionary = before["fams"][fid]
		var lost: Array = by_family.get(fid, [0, 0])
		check(int(family["m"]) == int(old["m"]) - int(lost[0])
			and int(family["f"]) == int(old["f"]) - int(lost[1])
			and family["kids"] == old["kids"] and family["old"] == old["old"],
			"exact household male/female deductions, children and elders unchanged: " + str(fid))
		var services: Dictionary = (old["serve"] as Dictionary).duplicate(true)
		if int(lost[0]) + int(lost[1]) > 0:
			var remaining: int = int(services.get("militia", 0)) - int(lost[0]) - int(lost[1])
			check(remaining >= 0, "each death consumes a real militia service place")
			if remaining > 0: services["militia"] = remaining
			else: services.erase("militia")
		check(family["serve"] == services, "only the exact fallen militia service places leave: " + str(fid))
		check((family.get("pp", []) as Array).size() == (old.get("pp", []) as Array).size() - int(lost[0]) - int(lost[1]),
			"household register shrinks exactly once per fallen adult: " + str(fid))
		var events: Array = (family.get("ev", []) as Array).slice((old.get("ev", []) as Array).size())
		var died: int = 0
		for event: Array in events:
			if event.size() > 3 and event[1] == "died":
				died += 1
				check(event[3] == "militia", "a militia death never receives company-death history")
		check(died == int(lost[0]) + int(lost[1]), "one household death event per actual casualty: " + str(fid))
	var census: Dictionary = People.census(e)
	for key: String in ["population", "adults"]:
		check(int(census[key]) == int(before_census[key]) - n, "live census " + key + " drops exactly once")
	check(int(census["male"]) == int(before_census["male"]) - int(lost_sex[0])
		and int(census["female"]) == int(before_census["female"]) - int(lost_sex[1]), "census sex totals match the actual fallen")
	check(int(e["pop"]) == int(before["pop"]) - n and int(e["adults"]) == int(before["adults"]) - n
		and Census.people(e) == int(before_census["population"]) - n, "town pop, adults and household census all lose exactly n")
	var book: Dictionary = Census._book(e)
	check(int(e["stats"].get("deaths", 0)) == int(before["stats"].get("deaths", 0)) + n
		and int(book["dt"]) == int(before_book["dt"]) + n
		and int(book["cur"]["deaths"].get("battle", 0)) == int(before_book["cur"]["deaths"].get("battle", 0)) + n,
		"death stats and counted battle totals rise exactly once per fallen militia")
	check(book["cur"]["away"] == before_book["cur"]["away"], "militia never enters the company's away-death census")
	check(book["deaths"].size() == before_book["deaths"].size() + n
		and book["death_ids"].size() == before_book["death_ids"].size() + 2 * n, "one census death row and two exact identity guards per casualty")
	for unit: Unit in fallen:
		var identity: Dictionary = identities[unit.uid]
		var matches: int = 0
		for row: Array in book["deaths"]:
			if int(row[1]) == int(identity["pid"]) and int(row[7]) == int(identity["family"]):
				matches += 1
				check(row[5] == "battle" and int(row[9]) == 1
					and str(row[6]) == "with the militia of " + str(town["name"]), "fallen has one counted militia battle death, never company booking")
		check(matches == 1 and book["death_ids"].has(str(identity["uid"]))
			and book["death_ids"].has("unit:%d" % unit.uid), "each actual fallen identity is booked exactly once")
	for unit: Unit in survivors:
		var identity: Dictionary = identities[unit.uid]
		check((band["units"] as Array).count(unit) == 1 and not unit.dead
			and survivor_state(unit) == survivor_states[unit.uid], "survivor retains its one roster place, identity and post-combat health")
		check(Persons.by_uid(People.fam_of(town, unit.family), unit.uid) == identity["person"]
			and person_count(e, str(identity["uid"])) == 1
			and not book["death_ids"].has(str(identity["uid"])) and not book["death_ids"].has("unit:%d" % unit.uid),
			"survivor's exact person record stays living and unbooked")
