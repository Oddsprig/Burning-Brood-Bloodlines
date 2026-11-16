extends RefCounted
## v0.101: seven review fixes plus validated high_elf fixtures.
## Lead-only: one headless launch, --watchdog=55, outer wall timeout below 60 s.
## No generated campaign or combat ticks. --v101-case=f1|f2|f3|ui|f5 selects a group.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief. A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.
const U = preload("res://tests/sim_util.gd")
# Build the production HUD alone; terrain, movement and sprite generation are unrelated.
class HudMap:
	extends "res://campaign/world_map.gd"
	func _ready() -> void:
		set_process(false)
		_build_hud()

class HudBattle:
	extends "res://battle/battle.gd"
	func _ready() -> void:
		paused = true
		set_process(false)
		sim = BattleSim.new()
		sim.setup(Game.pending_battle["round_side0"], Game.pending_battle["enemy"], 7)
		_build_ui()


var checks: int = 0
var fails: int = 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if ok: print("ok   ", what)
	else:
		fails += 1
		print("FAIL ", what)

func run(tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	var saved_world: Dictionary = Game.world
	var saved_day: float = Game.day
	var saved_pb: Dictionary = Game.pending_battle.duplicate(true)
	var saved_loc: String = Game.location
	var saved_company: Array = Game.company.duplicate()
	var saved_squads: Dictionary = Game.squads.duplicate(true)
	var saved_stash: Array = Game.stash.duplicate()
	var saved_mobile: Variant = UiTheme._mobile_override
	var saved_process: bool = Game.is_processing()
	Game.set_process(false)
	Game.location = ""
	Game.company = []
	Game.squads = {}
	Game.stash = []
	var which: String = "all"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--v101-case="): which = arg.get_slice("=", 1)
	check(which in ["all", "f1", "f2", "f3", "ui", "f5"], "known v101 case selector")
	_fixture_validity()
	if fails == 0 and which in ["all", "f1"]: _test_f1_ai_age_gap()
	if fails == 0 and which in ["all", "f2"]: _test_f2_betrothal_window()
	if fails == 0 and which in ["all", "f5"]: _test_f5_cross_race_spouse()
	if fails == 0 and which in ["all", "f5"]: _test_f7_mortality_intervals()
	if fails == 0 and which in ["all", "f3"]: _test_f3_mounted_pool_rider_accounting()
	if fails == 0 and which in ["all", "f3"]: _test_f3_army_rider_settlement()
	if fails == 0 and which in ["all", "ui"]: await _test_f4_landscape_ui_layouts(tree)
	Game.world = saved_world
	Game.day = saved_day
	Game.pending_battle = saved_pb
	Game.location = saved_loc
	Game.company = saved_company
	Game.squads = saved_squads
	Game.stash = saved_stash
	Game.set_process(saved_process)
	UiTheme.set_mobile_override(saved_mobile)
	Dynasty.note_households_changed()
	check(Time.get_ticks_msec() - started < 55000, "selected v101 case completes below 55 seconds (%s)" % which)
	print("v101 checks %d, failures %d" % [checks, fails])
	return fails

func _fixture_validity() -> void:
	for pair: Array in [["human", "middle"], ["high_elf", "high_elf"]]:
		var race: String = str(pair[0])
		var culture: String = str(pair[1])
		var cultures: Dictionary = TownEcon.data()["cultures"]
		check(DB.races.has(race) and TownEcon.data()["ages"].has(race) and cultures.has(culture),
			"fixture race/culture keys exist: %s/%s" % [race, culture])
		if fails > 0: return
		check(str(cultures[culture].get("race", "")) == race, "fixture culture matches its race")
	var ab: Dictionary = People.ages("high_elf")
	check(int(ab["adult"]) == 40 and int(ab["elder"]) == 300 and int(ab["lifespan"]) == 450,
		"high_elf fixture uses native ages 40/300/450 without fallback")
	check(int(People.ages("human")["lifespan"]) == 75, "human lifespan control is 75")

func _member_row(uid: String) -> Dictionary:
	for row: Dictionary in Marriage.family(Game):
		if str(row.get("person_uid", "")) == uid: return row
	return {}

func _make_person(e: Dictionary, f: Dictionary, pid: int, name_idx: int, sex: int, age_years: float, day: float, kind: int = 0) -> Array:
	var born: int = int(round(day - age_years * People.year_days()))
	var p: Array = [pid, name_idx, sex, born, "", -1, kind, "", -1, -1, -1, "", []]
	Persons.identity(e, f, p)
	return p

func _make_town(tid: String, tname: String, faction: String, race: String, culture: String, day: float) -> Dictionary:
	var e: Dictionary = {
		"day": day, "race": race, "culture": culture, "faction": faction,
		"identity_scope": "1:%s" % tid, "next_pid": 100, "next_fid": 10,
		"pop": 3, "adults": 3, "idle_n": 0, "hands": 0, "homes": 3, "treasury": 1000.0,
		"fams": [], "biz": [], "open": [], "head": {}, "dead_log": [],
		"stats": {"deaths": 0, "births": 0, "sales": 0.0, "gold_left": 0.0},
		"census": {"births": 0, "deaths": [], "moves": []}
	}
	return {"id": tid, "name": tname, "faction": faction, "pos": Vector2(100, 100), "econ": e, "shop": [], "goods": {}}

func _make_noble_family(e: Dictionary, fid: int, hname: String, tid: String, race: String, day: float, child_sex: int, child_age: float, child_kind: int = 0) -> Dictionary:
	var f: Dictionary = {
		"id": fid, "name": hname, "race": race, "tier": "rich", "cls": 2, "job": "ruler",
		"named": true, "gone": false, "farm": -1, "purse": 5000.0, "m": 2, "f": 0, "kids": 0, "old": 0,
		"homes": 2, "cond": 1.0, "hungry": 0, "unpaid": 0, "idle": 0, "debt": 0.0,
		"hands": 0, "worked": 0.0, "land": {}, "herd": {}, "jobs": {}, "owns": [], "keeps": [],
		"store": {"food": 14.0, "drink": 14.0, "wood": 14.0}, "wear": {}, "cum": {}, "serve": {},
		"hist": [], "pp": [], "kp": [], "dp": [], "seed": fid * 100 + 7
	}
	Families.identity(e, f)
	var head_age: float = 160.0 if race == "high_elf" else 42.0
	var heir_age: float = 120.0 if race == "high_elf" else 24.0
	var head: Array = _make_person(e, f, fid * 10 + 1, 0, 0, head_age, day, 0)
	var heir: Array = _make_person(e, f, fid * 10 + 2, 1, 0, heir_age, day, 0)
	var match_p: Array = _make_person(e, f, fid * 10 + 3, 2, child_sex, child_age, day, child_kind)
	heir[Persons.FA] = int(head[0])
	match_p[Persons.FA] = int(head[0])
	f["pp"].append(head)
	f["pp"].append(heir)
	if child_kind == 2:
		f["kp"].append(match_p)
		f["kids"] = 1
	elif child_kind == 1:
		f["pp"].append(match_p)
		f["old"] = 1
	else:
		f["pp"].append(match_p)
		var sk: String = "f" if child_sex == 1 else "m"
		f[sk] = int(f[sk]) + 1
	for p: Array in f["pp"] + f["kp"]:
		Persons.identity_kin(e, p)
	# Production family lookup indexes fams by id; retain that contract in tiny fixtures.
	while (e["fams"] as Array).size() <= fid:
		var padding: Dictionary = Families._blank((e["fams"] as Array).size())
		padding["estate"] = true
		padding["pp"] = []; padding["kp"] = []; padding["dp"] = []
		e["fams"].append(padding)
	e["fams"][fid] = f
	e["head"] = {
		"fam": fid, "pid": int(head[0]), "name": Persons.name_of(f, head, race),
		"person_uid": str(head[Persons.PERSON_UID]), "house_uid": str(head[Persons.HOUSE_UID]),
		"household_uid": str(f["household_uid"]), "home_town": tid, "title": "Lord"
	}
	return {"family": f, "head": head, "heir": heir, "member": match_p}

func _test_f1_ai_age_gap() -> void:
	var day: float = 36000.0
	Game.day = day
	var tp: Dictionary = _make_town("t_player", "Playerkeep", "middle_kingdom", "human", "middle", day)
	var hp: Dictionary = _make_noble_family(tp["econ"], 1, "Valen", "t_player", "human", day, 0, 22.0)
	var te1: Dictionary = _make_town("t_elf1", "Sylvanor", "sun_court", "high_elf", "high_elf", day)
	var he1: Dictionary = _make_noble_family(te1["econ"], 2, "Aelintar", "t_elf1", "high_elf", day, 0, 80.0)
	var te2: Dictionary = _make_town("t_elf2", "Lorien", "sun_court", "high_elf", day_culture("high_elf"), day)
	var he2: Dictionary = _make_noble_family(te2["econ"], 3, "Caelond", "t_elf2", "high_elf", day, 1, 110.0)
	var th1: Dictionary = _make_town("t_hum1", "Oakhaven", "middle_kingdom", "human", "middle", day)
	var hh1: Dictionary = _make_noble_family(th1["econ"], 4, "Bram", "t_hum1", "human", day, 0, 20.0)
	var th2: Dictionary = _make_town("t_hum2", "Redford", "middle_kingdom", "human", "middle", day)
	var hh2: Dictionary = _make_noble_family(th2["econ"], 5, "Dorn", "t_hum2", "human", day, 1, 40.0)
	Game.world = {
		"seed": 1, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_player": tp, "t_elf1": te1, "t_elf2": te2, "t_hum1": th1, "t_hum2": th2},
		"player_house": {
			"town_id": "t_player", "house_uid": str(hp["head"][Persons.HOUSE_UID]),
			"household_uid": str(hp["family"]["household_uid"]), "ruler_uid": str(hp["head"][Persons.PERSON_UID]),
			"ruler_race": "human"
		}
	}
	Dynasty.prepare_world(Game)
	var hum_groom_uid: String = str(hh1["member"][Persons.PERSON_UID])
	var hum_bride_uid: String = str(hh2["member"][Persons.PERSON_UID])
	var hum_res: Dictionary = Marriage.try_ai_match(Game, hum_groom_uid, hum_bride_uid)
	check(not bool(hum_res.get("ok", true)) and str(hum_res.get("reason", "")).contains("age gap"),
		"F1: two humans aged 20 and 40 fail the AI age gate (%s)" % str(hum_res.get("reason", "")))
	var elf_groom_uid: String = str(he1["member"][Persons.PERSON_UID])
	var elf_bride_uid: String = str(he2["member"][Persons.PERSON_UID])
	var groom_loc: Dictionary = Dynasty._person(Game, elf_groom_uid)
	var bride_loc: Dictionary = Dynasty._person(Game, elf_bride_uid)
	var born_before: int = int(he2["member"][3])
	var score_30: Dictionary = Marriage._ai_score(Game, groom_loc, bride_loc)
	he2["member"][3] = he1["member"][3]
	var score_0: Dictionary = Marriage._ai_score(Game, groom_loc, bride_loc)
	he2["member"][3] = int(round(day - 140.0 * People.year_days()))
	var score_60: Dictionary = Marriage._ai_score(Game, groom_loc, bride_loc)
	he2["member"][3] = born_before
	var penalty_60: float = (60.0 / Marriage.age_gap_scale("high_elf", "high_elf") - 8.0) * 1.5
	check(is_equal_approx(float(score_30["score"]), float(score_0["score"])) and
		is_equal_approx(float(score_0["score"]) - float(score_60["score"]), penalty_60),
		"F1: AI score normalizes the gap before the eight-year penalty")
	var mixed: Dictionary = Marriage.try_ai_match(Game, elf_groom_uid, hum_bride_uid)
	check(not bool(mixed.get("ok", true)) and str(mixed.get("reason", "")).contains("same race"),
		"F1: AI same-race policy is unchanged")
	var elf_res: Dictionary = Marriage.try_ai_match(Game, elf_groom_uid, elf_bride_uid)
	check(bool(elf_res.get("ok", false)),
		"F1: two elves aged 80 and 110 pass try_ai_match (%s)" % str(elf_res))
	# Also verify arrange_ai matches an 80-year-old elf and a 110-year-old elf, while rejecting 20 vs 40 humans.
	var ph: Dictionary = Game.world["player_house"].duplicate(true)
	var te3: Dictionary = _make_town("t_elf3", "Sylvanor", "sun_court", "high_elf", "high_elf", day)
	_make_noble_family(te3["econ"], 2, "Aelintar", "t_elf3", "high_elf", day, 0, 80.0)
	var te4: Dictionary = _make_town("t_elf4", "Lorien", "sun_court", "high_elf", "high_elf", day)
	_make_noble_family(te4["econ"], 3, "Caelond", "t_elf4", "high_elf", day, 1, 110.0)
	Game.world = {
		"seed": 2, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_player": tp, "t_elf3": te3, "t_elf4": te4},
		"player_house": ph
	}
	Dynasty.prepare_world(Game)
	var arr_elf: Dictionary = Marriage.arrange_ai(Game)
	check(bool(arr_elf.get("arranged", false)),
		"F1: arrange_ai weds two elves aged 80 and 110 (%s)" % str(arr_elf))

func day_culture(_race: String) -> String:
	return "high_elf"

func _test_f2_betrothal_window() -> void:
	var day: float = 36000.0
	Game.day = day
	var te1: Dictionary = _make_town("t_elf_home", "Sylvanor", "sun_court", "high_elf", "high_elf", day)
	var he1: Dictionary = _make_noble_family(te1["econ"], 1, "Aelintar", "t_elf_home", "high_elf", day, 0, 30.0, 2)
	var te2: Dictionary = _make_town("t_elf_other", "Lorien", "sun_court", "high_elf", "high_elf", day)
	var he2: Dictionary = _make_noble_family(te2["econ"], 2, "Caelond", "t_elf_other", "high_elf", day, 1, 30.0, 2)
	Game.world = {
		"seed": 3, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_elf_home": te1, "t_elf_other": te2},
		"player_house": {
			"town_id": "t_elf_home", "house_uid": str(he1["head"][Persons.HOUSE_UID]),
			"household_uid": str(he1["family"]["household_uid"]), "ruler_uid": str(he1["head"][Persons.PERSON_UID]),
			"ruler_race": "high_elf"
		}
	}
	Dynasty.prepare_world(Game)
	var child_uid: String = str(he1["member"][Persons.PERSON_UID])
	var win: Vector2i = Marriage.betrothal_window("high_elf")
	check(win.x <= 30 and 30 < 40 and win.y > 40,
		"F2: elf betrothal_window (%s) covers age 30" % str(win))
	check(win.x >= 20 and Marriage.betrothal_window("human") == Vector2i(10, 20),
		"F2: no infant betrothals for long-lived races (elf from %d); humans keep 10..20 (%s)" % [win.x, str(Marriage.betrothal_window("human"))])
	var fam_rows: Array = Marriage.family(Game)
	var child_row: Dictionary = {}
	for r: Dictionary in fam_rows:
		if str(r.get("person_uid", "")) == child_uid:
			child_row = r
			break
	var cands: Array = Marriage.candidates(Game, child_uid)
	check(bool(child_row.get("can_betroth", false)) and not cands.is_empty(),
		"F2: elf child of 30 is advertised can_betroth=%s and has %d candidate(s)" % [str(child_row.get("can_betroth", false)), cands.size()])
	for age: int in [24, 25, 30, 32, 33]:
		he1["member"][3] = int(round(day - float(age) * People.year_days()))
		he2["member"][3] = int(round(day - float(age) * People.year_days()))
		var boundary_row: Dictionary = _member_row(child_uid)
		var boundary_cands: Array = Marriage.candidates(Game, child_uid)
		check(bool(boundary_row.get("can_betroth", false)) == (age >= win.x) and
			(not boundary_cands.is_empty()) == (age >= win.x),
			"F2: high_elf advertisement and candidates agree at age %d" % age)
	he1["member"][3] = int(round(day - 30.0 * People.year_days()))
	he2["member"][3] = int(round(day - 60.0 * People.year_days()))
	check(not Marriage.candidates(Game, child_uid).is_empty(), "F2: scaled child candidate upper window admits high_elf age 60")
	he2["member"][3] = int(round(day - float(win.y) * People.year_days()))
	check(Marriage.candidates(Game, child_uid).is_empty(), "F2: scaled upper candidate boundary stays exclusive")
	# Check agreement between Marriage.family and Marriage.candidates at adult boundary (age 40):
	# UI uses can_betroth for adult spouse searches too, and adult=true at 40.
	# Recount actual resident rows before invoking the native child-to-adult transition.
	TownEcon.recount(te1["econ"])
	TownEcon.recount(te2["econ"])
	check(int(te1["econ"]["pop"]) == 3 and int(te2["econ"]["pop"]) == 3 and
		int(te1["econ"]["adults"]) == 2 and int(te2["econ"]["adults"]) == 2 and
		int(he1["member"][6]) == 2 and int(he2["member"][6]) == 2,
		"F2: native recount matches two adults and one actual child per town before promotion")
	if fails > 0: return
	he1["member"][3] = int(round(day - 40.0 * People.year_days()))
	he2["member"][3] = int(round(day - 40.0 * People.year_days()))
	var aged_home: bool = Persons.age_up(te1["econ"], he1["family"], day)
	var aged_other: bool = Persons.age_up(te2["econ"], he2["family"], day)
	check(aged_home and aged_other and (he1["family"]["pp"] as Array).has(he1["member"]) and
		(he2["family"]["pp"] as Array).has(he2["member"]) and
		(he1["family"]["kp"] as Array).is_empty() and (he2["family"]["kp"] as Array).is_empty() and
		int(he1["family"]["kids"]) == 0 and int(he2["family"]["kids"]) == 0 and
		int(he1["member"][6]) == 0 and int(he2["member"][6]) == 0 and
		int(he1["family"]["m"]) == 3 and int(he1["family"]["f"]) == 0 and
		int(he2["family"]["m"]) == 2 and int(he2["family"]["f"]) == 1 and
		int(te1["econ"]["pop"]) == 3 and int(te2["econ"]["pop"]) == 3 and
		int(te1["econ"]["adults"]) == 3 and int(te2["econ"]["adults"]) == 3,
		"F2: native age_up promotes both real child records before the adult-boundary search")
	if fails > 0: return
	var fam_adult: Array = Marriage.family(Game)
	var adult_row: Dictionary = {}
	for r: Dictionary in fam_adult:
		if str(r.get("person_uid", "")) == child_uid:
			adult_row = r
			break
	var adult_cands: Array = Marriage.candidates(Game, child_uid)
	check(bool(adult_row.get("adult", false)) and bool(adult_row.get("can_betroth", false)) and not adult_cands.is_empty(),
		"F2: at elf adulthood (40), adult is true, can_betroth stays true for spouse search, and candidates match (%d)" % adult_cands.size())
	# The original human child-candidate interval remains [10, 20).
	for sample: Array in [[9, 10, false], [10, 10, true], [10, 19, true], [10, 20, false]]:
		var home: Dictionary = _make_town("t_hwin_a", "Human home", "middle_kingdom", "human", "middle", day)
		var other: Dictionary = _make_town("t_hwin_b", "Human other", "middle_kingdom", "human", "middle", day)
		var hhome: Dictionary = _make_noble_family(home["econ"], 1, "Valen", "t_hwin_a", "human", day, 0, float(sample[0]), 2)
		var hother: Dictionary = _make_noble_family(other["econ"], 1, "Bram", "t_hwin_b", "human", day, 1, float(sample[1]), 2 if int(sample[1]) < 16 else 0)
		Game.world = {"seed": 3, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
			"towns": {"t_hwin_a": home, "t_hwin_b": other}, "player_house": {"town_id": "t_hwin_a",
			"house_uid": str(hhome["head"][Persons.HOUSE_UID]), "household_uid": str(hhome["family"]["household_uid"]),
			"ruler_uid": str(hhome["head"][Persons.PERSON_UID]), "ruler_race": "human"}}
		Dynasty.prepare_world(Game)
		var human_uid: String = str(hhome["member"][Persons.PERSON_UID])
		var human_cands: Array = Marriage.candidates(Game, human_uid)
		check(bool(_member_row(human_uid).get("can_betroth", false)) == (int(sample[0]) >= 10) and
			(not human_cands.is_empty()) == bool(sample[2]),
			"F2: human member %d/candidate %d retains the 10..20 window" % [sample[0], sample[1]])

func _test_f3_mounted_pool_rider_accounting() -> void:
	var day: float = 36000.0
	Game.day = day
	var saved_pb: Dictionary = Game.pending_battle.duplicate(true)
	var saved_company: Array = Game.company.duplicate()
	var t_f3: Dictionary = _make_town("t_f3", "Valorhall", "middle_kingdom", "human", "middle", day)
	var e_f3: Dictionary = t_f3["econ"]
	var h_f3: Dictionary = _make_noble_family(e_f3, 1, "Valen", "t_f3", "human", day, 0, 26.0, 0)
	var f_f3: Dictionary = h_f3["family"]
	var p_rider: Array = h_f3["member"]
	var rider_uid: String = str(p_rider[Persons.PERSON_UID])
	Game.world = {
		"seed": 42, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_f3": t_f3}, "warbands": {}, "party": {"pos": Vector2(100, 100)},
		"player_house": {
			"town_id": "t_f3", "house_uid": str(h_f3["head"][Persons.HOUSE_UID]),
			"household_uid": str(f_f3["household_uid"]), "ruler_uid": str(h_f3["head"][Persons.PERSON_UID]),
			"ruler_race": "human"
		}
	}
	Dynasty.prepare_world(Game)
	var u_foot: Unit = U.soldier("copper", "arming_sword", "", "", "")
	u_foot.name = "Footman Hal"
	var u_rider: Unit = U.soldier("copper", "arming_sword", "", "", "")
	u_rider.home_town = "t_f3"
	Persons.bind(e_f3, f_f3, p_rider, u_rider, "hire", day)
	# Native enlistment removes this already-away man from all three resident counts and books his departure.
	Mobilization._away(Game, u_rider, {"econ": e_f3, "family": f_f3, "person": p_rider})
	check(int(f_f3["m"]) == 2 and int(e_f3["pop"]) == 2 and int(e_f3["adults"]) == 2 and str(p_rider[4]) == "company",
		"F3: native company enlistment establishes the already-away baseline")
	u_rider.name = "Lord Commander Valen"
	u_rider.role = "captain"
	u_rider.rank = 3
	u_rider.set_meta("house_member", true)
	Game.company = [u_foot, u_rider]
	var u_foe: Unit = U.soldier("copper", "arming_sword", "", "", "")
	u_foe.name = "Enemy Footman"
	var u_dragon: Unit = Unit.create("dragon", "middle_kingdom", false)
	u_dragon.dragon_uid = "drg_test_1"
	u_dragon.name = "Vaelor"
	Game.pending_battle = {"seed": 42}
	BattleRounds.begin(Game, [u_foot, u_rider], [u_foe])
	var st: Dictionary = Game.pending_battle["rounds"]
	st["commander"][0] = u_rider.uid
	# Rider is in st["pool"][0], seated on a dragon off-round (not in fighter_units), and killed while mounted.
	var r: Dictionary = {
		"winner": 0,
		"side_names": ["Your army", "Enemy"],
		"fighter_units": [u_foot, u_foe],
		"fighter_states": ["alive", "dead"],
		"dragon_downs": {},
		"dragon_seats": {
			"drg_test_1": {
				"person_uid": rider_uid,
				"unit": u_rider,
				"joined": true,
				"detached": false,
				"dead": true,
				"state": "dead",
				"damage": 60.0
			}
		}
	}
	u_foe.dead = true
	check(is_same(People.fam_of(t_f3, u_rider.family), f_f3) and
		is_same(Dynasty.bound_unit(Game, Dynasty.person(Game, rider_uid)), u_rider),
		"F3: rider resolves to his exact household and bound Unit")
	var d: Dictionary = BattleRounds.after_round(Game, r)
	var hh_matches: Array = (d["household"] as Array).filter(func(row: Dictionary) -> bool: return str(row.get("name", "")) == u_rider.name)
	check(int(d["fought"][0]) == 2 and int(d["dead"][0]) == 1 and int(st["dead"][0]) == 1,
		"F3: seated pool rider is counted once in round fought (%d) and dead (%d)" % [int(d["fought"][0]), int(d["dead"][0])])
	check(int(d["morale_change"][0]) == -13,
		"F3: seated pool commander/officer loss applies nerve morale penalty (morale_change=%d)" % int(d["morale_change"][0]))
	check(hh_matches.size() == 1 and str(hh_matches[0].get("fate", "")) == "dead",
		"F3: seated pool rider appears once in round household list (%d)" % hh_matches.size())
	# Game.finish_battle resolves riders first, then CampaignWorld's actual company-role roster helper.
	var final_r: Dictionary = BattleRounds.final_result(Game, r)
	var counts_before: Array = _f3_counts(e_f3, f_f3)
	var entry: Dictionary = {"rider_person_uid": rider_uid, "damage_before": 0.0, "flying": false}
	var rr: Dictionary = DragonCombat._rider_result(Game, final_r, entry, u_dragon, 42)
	check(rr.is_empty() and _f3_counts(e_f3, f_f3) == counts_before,
		"F3: rostered company rider defers to the real company casualty contract")
	CampaignWorld.on_battle_result(Game, final_r)
	var book: Dictionary = Census._book(e_f3)
	check(_f3_counts(e_f3, f_f3) == counts_before and not (f_f3["pp"] as Array).has(p_rider) and
		_matching_deaths(e_f3, f_f3, p_rider, "battle", 0) == 1 and (book["deaths"] as Array).size() == 1 and
		book["death_ids"].has(rider_uid) and book["death_ids"].has("unit:%d" % u_rider.uid) and
		int(book["cur"]["away"].get("battle", 0)) == 1 and int(book.get("dt", 0)) == 0,
		"F3: production company settlement records one identity-specific away death without losing a second resident")
	var repeat_rr: Dictionary = DragonCombat._rider_result(Game, final_r, entry, u_dragon, 42)
	CampaignWorld.on_battle_result(Game, final_r)
	check(repeat_rr.is_empty() and _f3_counts(e_f3, f_f3) == counts_before and
		(book["deaths"] as Array).size() == 1 and _matching_deaths(e_f3, f_f3, p_rider, "battle", 0) == 1 and
		int(book["cur"]["away"].get("battle", 0)) == 1 and int(book.get("dt", 0)) == 0,
		"F3: repeated production settlement changes neither company census rows nor resident counters")
	check((r["fighter_units"] as Array).size() == 2 and (r["fighter_states"] as Array).size() == 2,
		"F3: merging seats never changes input result arrays")
	# Repeat only the tiny accounting fixture for dedup and detached-body controls.
	for mode: String in ["roster", "detached", "outside", "state_dead"]:
		u_rider.dead = false
		Game.pending_battle = {"seed": 42}
		BattleRounds.begin(Game, [u_foot, u_rider], [u_foe])
		Game.pending_battle["rounds"]["commander"][0] = u_rider.uid
		var control: Dictionary = r.duplicate(true)
		var seat: Dictionary = control["dragon_seats"]["drg_test_1"]
		if mode == "roster":
			(control["fighter_units"] as Array).append(u_rider)
			(control["fighter_states"] as Array).append("alive")
		elif mode == "detached":
			seat["detached"] = true
		elif mode == "outside":
			seat["unit"] = U.soldier("copper", "arming_sword", "", "", "")
		elif mode == "state_dead":
			seat["dead"] = false
		var control_summary: Dictionary = BattleRounds.after_round(Game, control)
		var should_count: bool = mode in ["roster", "state_dead"]
		check(int(control_summary["fought"][0]) == (2 if should_count else 1) and
			int(control_summary["dead"][0]) == (1 if should_count else 0),
			"F3: %s seat is counted or excluded exactly once" % mode)
	u_rider.dead = true
	Game.company = saved_company
	Game.pending_battle = saved_pb

func _f3_counts(e: Dictionary, f: Dictionary) -> Array:
	return [int(f["m"]), int(f["f"]), int(f["kids"]), int(f["old"]), int(e["pop"]), int(e["adults"]),
		int(e["stats"].get("deaths", 0)), (f["serve"] as Dictionary).duplicate()]

func _matching_deaths(e: Dictionary, f: Dictionary, p: Array, cause: String, counted: int) -> int:
	var matches: int = 0
	for row: Array in Census._book(e)["deaths"]:
		if int(row[1]) == int(p[0]) and int(row[7]) == int(f["id"]) and str(row[5]) == cause and int(row[9]) == counted:
			matches += 1
	return matches

func _test_f3_army_rider_settlement() -> void:
	# Both army sides use their real service before the company roster and native roll sweep.
	for config: Array in [[0, false], [0, true], [1, false], [1, true]]:
		var side: int = int(config[0])
		var state_only: bool = bool(config[1])
		var label: String = "side %d (%s)" % [side, "state-only" if state_only else "dead flag"]
		var day: float = 36000.0
		Game.day = day
		var tid: String = "t_army_v101"
		var town: Dictionary = _make_town(tid, "Armyhold", "middle_kingdom", "human", "middle", day)
		var e: Dictionary = town["econ"]
		var house: Dictionary = _make_noble_family(e, 1, "ArmyTest", tid, "human", day, 0, 26.0)
		var f: Dictionary = house["family"]
		var p: Array = house["member"]
		var person_uid: String = str(p[Persons.PERSON_UID])
		Game.world = {"seed": 42, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
			"towns": {tid: town}, "warbands": {}, "party": {"pos": Vector2(100, 100)},
			"player_house": {"town_id": tid, "house_uid": str(house["head"][Persons.HOUSE_UID]),
				"household_uid": str(f["household_uid"]), "ruler_uid": str(house["head"][Persons.PERSON_UID]), "ruler_race": "human"}}
		Dynasty.prepare_world(Game)
		var foot: Unit = U.soldier("copper", "arming_sword", "", "", "")
		var foe: Unit = U.soldier("copper", "arming_sword", "", "", "")
		var rider: Unit = U.soldier("copper", "arming_sword", "", "", "")
		Game.company = [foot]
		var pool: Array = [[0, 0.0, int(f["id"]), int(p[0])]]
		var drafted: int = People.draft(town, pool, "army")
		check(drafted == int(f["id"]), "F3 army %s: native draft selects the real household member" % label)
		if fails > 0: return
		People.bind(town, drafted, rider, "army")
		var band: Dictionary = {"id": "army_v101", "kind": "assault", "faction": "middle_kingdom", "units": [rider]}
		Game.world["warbands"]["army_v101"] = band
		var enlistment: Dictionary = Army.enlist_begin(Game, band)
		check(not enlistment.is_empty(), "F3 army %s: actual army enlistment context is available" % label)
		if fails > 0: return
		var enlisted: bool = Army.enlist_some(Game, band, enlistment, 1)
		var roll: Dictionary = Army.state(Game.world)["roll"]
		check(enlisted and not Game.company.has(rider) and str(p[4]) == "army" and int(f["serve"].get("army", 0)) == 1 and
			roll.get(str(rider.uid), []) == [tid, int(f["id"]), "army", rider.name] and
			is_same(Dynasty.bound_unit(Game, Dynasty.person(Game, person_uid)), rider),
			"F3 army %s: real service, roll and warband Unit agree outside Game.company" % label)
		if fails > 0: return
		rider.role = "captain"
		rider.rank = 3
		rider.set_meta("house_member", true)
		var dragon: Unit = Unit.create("dragon", "middle_kingdom", false)
		dragon.dragon_uid = "drg_army_v101"
		Game.pending_battle = {"seed": 42}
		BattleRounds.begin(Game, [foot, rider] if side == 0 else [foot], [foe, rider] if side == 1 else [foe])
		Game.pending_battle["rounds"]["commander"][side] = rider.uid
		var result: Dictionary = {"winner": 0, "fighter_units": [foot, foe], "fighter_states": ["alive", "alive"],
			"dragon_seats": {dragon.dragon_uid: {"person_uid": person_uid, "unit": rider, "joined": true,
				"detached": false, "dead": not state_only, "state": "dead", "damage": 60.0}}}
		var summary: Dictionary = BattleRounds.after_round(Game, result)
		check(int(summary["fought"][side]) == 2 and int(summary["dead"][side]) == 1,
			"F3 army %s: seat-only death reaches round accounting once" % label)
		var final_result: Dictionary = BattleRounds.final_result(Game, result)
		var before: Array = _f3_counts(e, f)
		var expected: Array = [int(f["m"]) - 1, int(f["f"]), int(f["kids"]), int(f["old"]),
			int(e["pop"]) - 1, int(e["adults"]) - 1, int(e["stats"].get("deaths", 0)) + 1, {}]
		var entry: Dictionary = {"rider_person_uid": person_uid, "damage_before": 0.0, "flying": false}
		var outcome: Dictionary = DragonCombat._rider_result(Game, final_result, entry, dragon, 42)
		check(str(outcome.get("outcome", "")) == "killed" and _f3_counts(e, f) == expected and before != expected,
			"F3 army %s: dragon settlement decrements the actual army service and resident counts once" % label)
		if fails > 0: return
		CampaignWorld.on_battle_result(Game, final_result)
		Army.sweep(Game)
		var book: Dictionary = Census._book(e)
		check(_f3_counts(e, f) == expected and roll.is_empty() and not (f["pp"] as Array).has(p) and
			(book["deaths"] as Array).size() == 1 and _matching_deaths(e, f, p, "battle", 1) == 1 and
			book["death_ids"].has(person_uid) and book["death_ids"].has("unit:%d" % rider.uid) and
			int(book["cur"]["deaths"].get("battle", 0)) == 1 and int(book.get("dt", 0)) == 1,
			"F3 army %s: production roster and army sweep deduplicate the same counted battle death" % label)
		if fails > 0: return
		var repeated: Dictionary = DragonCombat._rider_result(Game, final_result, entry, dragon, 42)
		CampaignWorld.on_battle_result(Game, final_result)
		Army.sweep(Game)
		check(repeated.is_empty() and _f3_counts(e, f) == expected and (book["deaths"] as Array).size() == 1 and
			_matching_deaths(e, f, p, "battle", 1) == 1 and int(book.get("dt", 0)) == 1,
			"F3 army %s: repeated native settlement and sweep have no extra effect" % label)
		if fails > 0: return

func _test_f4_landscape_ui_layouts(tree: SceneTree) -> void:
	var day: float = 36000.0
	Game.day = day
	var town: Dictionary = _make_town("t_ui", "Valorhall", "middle_kingdom", "human", "middle", day)
	var household: Dictionary = _make_noble_family(town["econ"], 1, "Valen", "t_ui", "human", day, 0, 26.0)
	Game.world = {"seed": 8, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {}, "warbands": {},
		"towns": {"t_ui": town}, "player_house": {"town_id": "t_ui",
		"house_uid": str(household["head"][Persons.HOUSE_UID]), "household_uid": str(household["family"]["household_uid"]),
		"ruler_uid": str(household["head"][Persons.PERSON_UID]), "ruler_race": "human"}}
	Dynasty.prepare_world(Game)
	UiTheme.set_mobile_override(true)
	check(UiTheme.is_mobile(), "F4: UiTheme.set_mobile_override(true) forces phone/mobile layout path")
	for sz: Vector2i in [Vector2i(844, 390), Vector2i(1280, 720)]:
		var svp: SubViewport = SubViewport.new()
		svp.size = sz
		tree.root.add_child(svp)
		var wm: Node2D = HudMap.new()
		svp.add_child(wm)
		wm.lbl_day.text = "Year 100, early spring"
		wm._layout_accounts(true)
		wm._layout_hud()
		await tree.process_frame
		await tree.process_frame
		wm._layout_hud()
		var nav_scroll_ok: bool = wm.bottom_nav.get_child_count() > 0 and wm.bottom_nav.get_child(0) is ScrollContainer and (wm.bottom_nav.get_child(0) as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO
		var top_bottom: float = wm.top_panel.position.y + wm.top_panel.size.y
		var card_ok: bool = not wm.ruler_card.visible or (wm.ruler_card.position.y >= top_bottom and wm.ruler_card.position.y + wm.ruler_card.size.y <= wm.bottom_nav.position.y)
		if sz.y >= 720: card_ok = card_ok and wm.ruler_card.visible
		check(card_ok and nav_scroll_ok,
			"F4a (%dx%d): ruler card fits above one scrolling nav row; taller screen keeps card visible" % [sz.x, sz.y])
		if sz.x == 844:
			wm.lbl_contract.text = "Contract: Hunt the brigand warband near Oakhaven, beyond the long northern mountain road, with five days remaining"
			wm.lbl_contract.visible = true
			wm._layout_hud()
			await tree.process_frame
			await tree.process_frame
			wm._layout_hud()
			var top_b_contract: float = wm.top_panel.position.y + wm.top_panel.size.y
			var contract_ok: bool = not wm.ruler_card.visible or (wm.ruler_card.position.y >= top_b_contract and wm.ruler_card.position.y + wm.ruler_card.size.y <= wm.bottom_nav.position.y)
			check(contract_ok, "F4a: wrapped contract never overlaps a visible ruler card")
		svp.remove_child(wm)
		wm.free()

		var s0: Unit = U.soldier("copper", "arming_sword", "", "", "")
		s0.name = "Captain Aldric of the Golden Vanguard and the Western March"
		var s1: Unit = U.soldier("copper", "arming_sword", "", "", "")
		s1.name = "Dread Warlord Gorgash of the Iron Crags and the Eastern Reach"
		Game.pending_battle = {"round_side0": [s0], "enemy": [s1], "seed": 7}
		var b: Node2D = HudBattle.new()
		svp.add_child(b)
		for i: int in 6:
			b._add_feed({"type": "decisive", "actor": 0, "target": 1,
				"text": "%s severs the left arm of %s. The enemy stumbles and falls. Event %d." % [s0.name, s1.name, i]})
		b._layout_diagnostics()
		await tree.process_frame
		await tree.process_frame
		b._layout_diagnostics()
		_feed_bounds(b, "F4b (%dx%d)" % [sz.x, sz.y])
		if b.feed_box.get_child_count() > 0:
			check((b.feed_box.get_child(b.feed_box.get_child_count() - 1) as Button).tooltip_text.ends_with("Event 5."),
				"F4b: trimming preserves the actual newest event")
		if sz.y == 720:
			svp.size = Vector2i(844, 390)
			await tree.process_frame
			await tree.process_frame
			b._layout_diagnostics()
			_feed_bounds(b, "F4b resized to 844x390")
		# A newest entry that cannot fit must not be forced outside the safe area.
		b.feed_box.position.y = b._safe_area_size().y - 40.0
		b._trim_toasts()
		check(b.feed_box.get_child_count() == 0, "F4b: no toast is retained without a usable vertical band")
		svp.remove_child(b)
		b.free()
		tree.root.remove_child(svp)
		svp.free()

	var market_vp: SubViewport = SubViewport.new()
	market_vp.size = Vector2i(844, 390)
	tree.root.add_child(market_vp)
	var host: Control = Control.new()
	host.size = Vector2(844, 390)
	host.theme = UiTheme.get_theme()
	market_vp.add_child(host)
	var stock_town: Dictionary = {"id": "t_stock", "name": "Stock fixture", "shop": [Item.make("arming_sword", "copper")], "goods": {}, "prices": {}}
	var market_root: Control = TownMarketTab.build(host, stock_town)
	host.add_child(market_root)
	market_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await tree.process_frame
	await tree.process_frame
	var market_sc: ScrollContainer = null
	for c: Node in market_root.get_children():
		if c is ScrollContainer:
			market_sc = c as ScrollContainer
			break
	check(market_sc != null and market_sc.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
		"F4c: TownMarketTab stock scroll enables horizontal scrolling")
	if market_sc != null:
		var bar: HScrollBar = market_sc.get_h_scroll_bar()
		var range_x: float = bar.max_value - bar.page
		var details: Button = null
		var buy: Button = null
		for node: Node in market_root.find_children("*", "Button", true, false):
			if (node as Button).text == "Details": details = node as Button
			elif (node as Button).text == "Buy": buy = node as Button
		check(range_x > 0.0 and details != null and buy != null,
			"F4c: populated 844px stock view has a real horizontal range and both actions")
		market_sc.scroll_horizontal = int(ceil(range_x))
		var vertical: VScrollBar = market_sc.get_v_scroll_bar()
		market_sc.scroll_vertical = int(ceil(vertical.max_value - vertical.page))
		await tree.process_frame
		await tree.process_frame
		if details != null and buy != null:
			var visible_rect: Rect2 = Rect2(market_sc.global_position, Vector2(bar.page, vertical.page))
			check(visible_rect.encloses(details.get_global_rect()) and visible_rect.encloses(buy.get_global_rect()),
				"F4c: scrolling to the end brings Buy and Details fully into view")
	tree.root.remove_child(market_vp)
	market_vp.free()
	UiTheme.set_mobile_override(null)

func _feed_bounds(b: Node2D, label: String) -> void:
	var margins: Dictionary = UiKit.safe_area_margins(b.get_viewport())
	var viewport: Vector2 = b.get_viewport_rect().size
	var usable: Vector2 = viewport - Vector2(float(margins["left"] + margins["right"]) + UiKit.diagnostics_lane(viewport.x),
		float(margins["top"] + margins["bottom"]))
	var feed_bottom: float = b.feed_box.position.y + b.feed_box.size.y
	var feed_right: float = b.feed_box.position.x + b.feed_box.size.x
	check(feed_bottom <= usable.y and feed_right <= usable.x and b.feed_box.get_child_count() >= 1,
		label + ": wrapped mobile toasts remain readable and inside the safe area")
	if b.feed_box.get_child_count() > 0:
		var newest: Button = b.feed_box.get_child(b.feed_box.get_child_count() - 1) as Button
		check(newest != null and newest.size.y >= float(UiKit.MOBILE_TAP) and newest.text != "" and newest.tooltip_text != "",
			label + ": newest event retains readable text and full tooltip")

func _test_f5_cross_race_spouse() -> void:
	var day: float = 36000.0
	Game.day = day
	var th: Dictionary = _make_town("t_hum_seat", "Oakhaven", "middle_kingdom", "human", "middle", day)
	var hh: Dictionary = _make_noble_family(th["econ"], 1, "Valen", "t_hum_seat", "human", day, 0, 25.0)
	var te: Dictionary = _make_town("t_elf_seat", "Sylvanor", "sun_court", "high_elf", "high_elf", day)
	# Elf bride aged 75: young adult for an elf (adult=40, elder=300, lifespan=450), but past human elder (55) and near human lifespan (75).
	var he: Dictionary = _make_noble_family(te["econ"], 2, "Aelintar", "t_elf_seat", "high_elf", day, 1, 75.0)
	Game.world = {
		"seed": 5, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
		"towns": {"t_hum_seat": th, "t_elf_seat": te},
		"player_house": {
			"town_id": "t_hum_seat", "house_uid": str(hh["head"][Persons.HOUSE_UID]),
			"household_uid": str(hh["family"]["household_uid"]), "ruler_uid": str(hh["head"][Persons.PERSON_UID]),
			"ruler_race": "human"
		}
	}
	Dynasty.prepare_world(Game)
	var groom_uid: String = str(hh["member"][Persons.PERSON_UID])
	var bride_uid: String = str(he["member"][Persons.PERSON_UID])
	check(str(Dynasty.person(Game, bride_uid).get("race", "")) == "high_elf", "F5: source spouse starts as high_elf")
	var w: Dictionary = Marriage.wed(Game, groom_uid, bride_uid)
	check(bool(w.get("ok", false)), "F5: cross-race wedding between human groom and elf bride succeeds")
	var bride_row: Dictionary = Dynasty.person(Game, bride_uid)
	check(str(bride_row.get("race", "")) == "high_elf",
		"F5: married-in elf spouse in human household keeps her own 'high_elf' race (got '%s')" % str(bride_row.get("race", "")))
	# Reload native codec output; optional race and stable UIDs must survive.
	var save_text: String = Game.save_text({"world": Game.world}, true)
	var restored: Variant = JSON.parse_string(save_text)
	check(save_text != "" and restored is Dictionary, "F5: mixed household encodes and parses through the native save codec")
	if not (restored is Dictionary): return
	Game.restore_exact(restored)
	Game.world = restored["world"]
	Dynasty.prepare_world(Game)
	check(str(Game.world["dynasty"]["kin"][bride_uid].get("race", "")) == "high_elf",
		"F5: succession genealogy retains the spouse's personal race")
	var bride_loc: Dictionary = Dynasty._person(Game, bride_uid)
	check(not bride_loc.is_empty() and str(Dynasty.person(Game, bride_uid).get("race", "")) == "high_elf" and
		str(Persons.g(bride_loc.get("person", []), Persons.PERSON_UID, "")) == bride_uid,
		"F5: save/load preserves the spouse's race and stable identity")
	if bride_loc.is_empty(): return
	var f_hum: Dictionary = bride_loc["family"]
	var e_hum: Dictionary = bride_loc["econ"]
	# Two direct threshold calls, without simulating campaign years.
	Persons.age_up(e_hum, f_hum, day)
	var bride_person: Array = bride_loc["person"]
	check(int(bride_person[6]) == 0 and is_same(Persons.mother_for(e_hum, f_hum, day), bride_person),
		"F5: spouse stays an adult and fertile past human elder/lifespan thresholds")
	Game.day = day + 30.0 * People.year_days()
	e_hum["day"] = Game.day
	Persons.age_up(e_hum, f_hum, Game.day)
	var after_row: Dictionary = Dynasty.person(Game, bride_uid)
	check(bool(after_row.get("alive", false)) and str(after_row.get("race", "")) == "high_elf" and int(after_row.get("age", 0)) >= 104,
		"F5: elf spouse in human household ages by elf rules and survives at age %d (alive=%s, race=%s)" % [int(after_row.get("age", 0)), str(after_row.get("alive", false)), str(after_row.get("race", ""))])
	var original_born: int = int(bride_person[3])
	bride_person[3] = int(round(Game.day - 30.0 * People.year_days()))
	check(not Marriage._of_age(Game, bride_loc), "F5: marriage eligibility uses personal high_elf adulthood")
	bride_person[3] = original_born
	# F5(a): weekly elder mortality in Families._people uses each elder's own race, not the town/household human race.
	var f_mort: Dictionary = _make_noble_family(e_hum, 6, "MortTest", "t_hum_seat", "human", Game.day, 1, 310.0, 1)["family"]
	var p_elf_elder: Array = (f_mort["pp"] as Array)[2]
	Persons.set_person_race(p_elf_elder, "high_elf")
	var yd: float = float(EconGen.YEAR_DAYS)
	var ab_hum: Dictionary = People.ages("human")
	var ab_elf: Dictionary = People.ages("high_elf")
	var po_hum: float = 7.0 / (Families.ELDER_MEAN * maxf(1.0, float(ab_hum["lifespan"]) - float(ab_hum["elder"])) * yd)
	var po_elf: float = 7.0 / (Families.ELDER_MEAN * maxf(1.0, float(ab_elf["lifespan"]) - float(ab_elf["elder"])) * yd)
	var native_seed: int = _native_roll_seed(po_elf, po_hum)
	check(native_seed >= 0, "F5a: native RNG seed reaches the distinguishing mortality interval within the setup budget")
	if native_seed < 0: return
	var rng_run: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_run.seed = native_seed
	var cul: Dictionary = TownEcon.culture_of(e_hum)
	Families._people(Game.world["towns"]["t_hum_seat"], e_hum, f_mort, cul, Game.day, rng_run)
	check((f_mort["pp"] as Array).has(p_elf_elder) and int(f_mort["old"]) == 1,
		"F5a: per-elder weekly mortality in Families._people uses elf elder's own race (po_elf=%.6f < po_hum=%.6f)" % [po_elf, po_hum])
	var human_control: Dictionary = _make_noble_family(e_hum, 7, "MortControl", "t_hum_seat", "human", Game.day, 1, 60.0, 1)["family"]
	var human_elder: Array = human_control["pp"][2]
	var human_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	human_rng.seed = native_seed
	Families._people(Game.world["towns"]["t_hum_seat"], e_hum, human_control, cul, Game.day, human_rng)
	check(not (human_control["pp"] as Array).has(human_elder) and int(human_control["old"]) == 0,
		"F5a: identical weekly mortality roll kills the human control")
	# F5(b): set_person_race pads RESEARCH (index 20) with null so Academy._training still rolls seeded aptitude.
	var p_sch: Array = _make_person(e_hum, f_hum, 901, 0, 0, 30.0, Game.day, 0)
	Persons.set_person_race(p_sch, "high_elf")
	var research_null_ok: bool = p_sch.size() > Persons.RACE and p_sch[Persons.RESEARCH] == null and absf(Academy._skill(p_sch, 2.5) - 2.5) < 1e-6
	var apt_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	apt_rng.seed = hash([Persons.g(p_sch, Persons.PERSON_UID, ""), int(p_sch[0]), float(p_sch[3]), "research aptitude"])
	var expected_apt: float = apt_rng.randf_range(0.9, 1.1)
	var tr: Dictionary = Academy._training(p_sch, 2.5)
	check(research_null_ok and absf(float(tr.get("aptitude", 0.0)) - expected_apt) < 1e-6,
		"F5b: set_person_race leaves RESEARCH null and Academy._training rolls seeded aptitude (%.4f == %.4f)" % [float(tr.get("aptitude", 0.0)), expected_apt])
	# F5(c): a person array of the old length (no index 21) still reads family_race.
	var p_old: Array = _make_person(e_hum, f_hum, 902, 0, 0, 28.0, Game.day, 0)
	var f_dwarf: Dictionary = {"id": 99, "name": "Ironbeard", "race": "dwarf"}
	check(p_old.size() <= Persons.RACE and Persons.person_race(e_hum, f_dwarf, p_old) == "dwarf" and Persons.person_race(e_hum, {}, p_old) == "human",
		"F5c: legacy person array without index 21 (size=%d) falls back to family_race ('%s')" % [p_old.size(), Persons.person_race(e_hum, f_dwarf, p_old)])

func _test_f7_mortality_intervals() -> void:
	# Mixed cases put the older elf first; homogeneous cases put the younger elder first.
	for mode: String in ["mixed_human", "mixed_elf", "mixed_away", "homogeneous", "minority", "minority_rate"]:
		var day: float = 36000.0
		Game.day = day
		var minority: bool = mode.begins_with("minority")
		var town: Dictionary = _make_town("t_elder_v101", "Elderhold", "orc_horde" if minority else "middle_kingdom",
			"orc" if minority else "human", "orc" if minority else "middle", day)
		var e: Dictionary = town["econ"]
		var house: Dictionary = _make_noble_family(e, 1, "ElderTest", "t_elder_v101", "troll" if minority else "human", day, 1,
			90.0 if minority else (60.0 if mode == "homogeneous" else 310.0), 1)
		var f: Dictionary = house["family"]
		var first: Array = house["member"]
		if not minority and mode != "homogeneous": Persons.set_person_race(first, "high_elf")
		var second: Array = _make_person(e, f, 14, 3, 0, 100.0 if minority else (70.0 if mode == "homogeneous" else 60.0), day, 1)
		Persons.identity_kin(e, second)
		(f["pp"] as Array).append(second)
		f["old"] = 2
		e["pop"] = 4
		e["adults"] = 2
		if mode == "mixed_away":
			second[4] = "army"
			f["serve"]["army"] = 1
		Game.world = {"seed": 42, "day": day, "log": [], "factions": {}, "rep": {}, "relations": {},
			"towns": {"t_elder_v101": town}, "warbands": {}}
		Game.company = []
		Dynasty.prepare_world(Game)
		var yd: float = float(EconGen.YEAR_DAYS)
		var human_ages: Dictionary = People.ages("human")
		var elf_ages: Dictionary = People.ages("high_elf")
		var human_rate: float = 7.0 / (Families.ELDER_MEAN * (float(human_ages["lifespan"]) - float(human_ages["elder"])) * yd)
		var elf_rate: float = 7.0 / (Families.ELDER_MEAN * (float(elf_ages["lifespan"]) - float(elf_ages["elder"])) * yd)
		var roll_low: float = 2.0 * elf_rate
		var roll_high: float = human_rate
		var victim: Array = second
		var survivor: Array = first
		if mode == "mixed_elf":
			roll_low = 0.0
			roll_high = elf_rate
			victim = first
			survivor = second
		elif mode == "mixed_away":
			victim = []
		elif mode == "homogeneous":
			# A native draw below one human rate must still kill the oldest second elder.
			roll_low = 0.0
			roll_high = human_rate
		elif minority:
			var troll_ages: Dictionary = People.ages("troll")
			var troll_rate: float = 7.0 / (Families.ELDER_MEAN * (float(troll_ages["lifespan"]) - float(troll_ages["elder"])) * yd)
			check(DB.races.has("troll") and int(troll_ages["elder"]) == 80 and int(troll_ages["lifespan"]) == 120 and
				Persons.age_of(first, day) == 90 and Persons.age_of(second, day) == 100 and
				Persons.race_of(e) == "orc" and Persons.person_race(e, f, first) == "troll" and Persons.person_race(e, f, second) == "troll" and
				str(Persons.g(first, Persons.RACE, "")) == "" and str(Persons.g(second, Persons.RACE, "")) == "",
				"F7 %s: two native troll elders inherit household race in an orc town, without personal overrides" % mode)
			# A native draw below one troll rate must still kill the oldest second troll.
			roll_low = 0.0
			roll_high = troll_rate
			if mode == "minority_rate":
				var orc_ages: Dictionary = People.ages("orc")
				var orc_rate: float = 7.0 / (Families.ELDER_MEAN * (float(orc_ages["lifespan"]) - float(orc_ages["elder"])) * yd)
				roll_low = 2.0 * troll_rate
				roll_high = 2.0 * orc_rate
				victim = []
				check(roll_low < roll_high,
					"F7 minority_rate: controlled roll separates summed troll hazard from summed orc hazard")
		var native_seed: int = _native_roll_seed(roll_low, roll_high)
		check(native_seed >= 0, "F7 %s: native RNG seed reaches the required interval within the setup budget" % mode)
		if native_seed < 0: return
		var probe: RandomNumberGenerator = RandomNumberGenerator.new()
		probe.seed = native_seed
		var first_draw: float = probe.randf()
		var target_roll: float = first_draw
		check(target_roll > roll_low and target_roll < roll_high,
			"F7 %s: native draw lies inside the unchanged distinguishing mortality bounds" % mode)
		var run_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		run_rng.seed = native_seed
		check(first_draw > 0.0 and (mode != "mixed_human" or (target_roll > 2.0 * elf_rate and target_roll < human_rate)),
			"F7 %s: deterministic roll distinguishes the human hazard from the oldest elf's own hazard" % mode)
		if fails > 0: return
		Families._people(town, e, f, TownEcon.culture_of(e), day, run_rng)
		var deaths: int = 0 if victim.is_empty() else 1
		var book: Dictionary = Census._book(e)
		check(run_rng.state == probe.state and int(f["old"]) == 2 - deaths and int(e["pop"]) == 4 - deaths and
			int(e["adults"]) == 2 and int(e["stats"].get("deaths", 0)) == deaths and
			(f["pp"] as Array).size() == 4 - deaths and (book["deaths"] as Array).size() == deaths and
			int(book.get("dt", 0)) == deaths and int(book["cur"]["deaths"].get("old age", 0)) == deaths,
			"F7 %s: one existing weekly draw, exact population/elder/death counters and one native census flow" % mode)
		if fails > 0: return
		if not victim.is_empty():
			check(not (f["pp"] as Array).has(victim) and (f["pp"] as Array).has(survivor) and
				_matching_deaths(e, f, victim, "old age", 1) == 1 and
				book["death_ids"].has(str(victim[Persons.PERSON_UID])) and
				not book["death_ids"].has(str(survivor[Persons.PERSON_UID])),
				"F7 %s: the correct elder dies and the other elder survives with no census ID" % mode)
		elif mode == "mixed_away":
			check((f["pp"] as Array).has(first) and (f["pp"] as Array).has(second) and
				int(f["serve"].get("army", 0)) == 1 and (book["death_ids"] as Dictionary).is_empty(),
				"F7 mixed_away: an absent human elder contributes no home-elder hazard")
		else:
			check((f["pp"] as Array).has(first) and (f["pp"] as Array).has(second) and (book["death_ids"] as Dictionary).is_empty(),
				"F7 minority_rate: both trolls survive a roll above their own summed hazard but below the orc town hazard")
		if fails > 0: return

## Select an actual native draw; never rewrite RNG state, event multipliers or outcomes.
func _native_roll_seed(low: float, high: float) -> int:
	var started: int = Time.get_ticks_msec()
	var candidate: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(100000):
		if Time.get_ticks_msec() - started >= 1000: break
		candidate.seed = seed_value
		var draw: float = candidate.randf()
		if draw > low and draw < high:
			print("NATIVE_ROLL_SEED ", {"seed": seed_value, "draw": draw, "low": low, "high": high,
				"search_ms": Time.get_ticks_msec() - started})
			return seed_value
	print("NATIVE_ROLL_SEED_MISS ", {"low": low, "high": high, "search_ms": Time.get_ticks_msec() - started})
	return -1
