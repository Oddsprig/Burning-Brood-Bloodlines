extends RefCounted

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func family_scope(culture: String, crop: int, herd: int, ox: int) -> void:
	var fixture = load("res://tests/test_harvest_labour.gd").new()
	var e: Dictionary = fixture.fixture(culture, 1, crop, herd)
	var f: Dictionary = e["fams"][1]
	f["ox"] = ox
	var land_before: Dictionary = f["land"].duplicate(true)
	var herd_before: Dictionary = f["herd"].duplicate(true)
	var adults_before := Families.adults(f)
	var acres := float(crop * 8)
	var ox_acres := minf(acres, float(ox) * 8.0)
	var crop_work := ox_acres / 8.0 + (acres - ox_acres) / 4.0
	var herd_work := float(herd * 25) / 60.0 + float(ox) / 8.0
	for day in [0, 30, 60, 61, 90, 120, 150, 180, 210]:
		e["day"] = float(day)
		var harvest := Calendar.season_index(day) in [1, 2]
		Families.reassign(e, f)
		var crop_multiplier := float(Barge.B()["labour"]["harvest_hands"]) if harvest else 1.0
		var expected := maxi(0, int(ceil(crop_work * crop_multiplier + herd_work - int(f["hands"]) - 0.3)))
		check(int(e["biz"][0]["cap"]) == expected, "harvest increases crop work only (%s crop%d herd%d ox%d day%d)" % [culture, crop, herd, ox, day])
		check(is_equal_approx(Families.need_hands(f), crop_work + herd_work), "base cultivation and herd need stays unchanged")
		Families.reassign(e, f)
		check(int(e["biz"][0]["cap"]) == expected, "repeat assignment adds no extra harvest places")
		check(f["land"] == land_before and f["herd"] == herd_before and Families.adults(f) == adults_before, "capacity change preserves land, animals and people")
		check(int(e["biz"][0]["workers"]) == 0, "a seasonal opening does not create hired workers")

func estate_scope(seed_value: int) -> void:
	Game.new_game(seed_value)
	var town: Dictionary = Game.world["towns"].values()[0]
	var original: Dictionary = town["econ"]
	var physical = load("res://tests/farm_fixture_tools.gd").new()
	for spec in [[4, 0], [3, 2], [0, 2]]:
		var e: Dictionary = original.duplicate(true); town["econ"] = e
		var estate: Dictionary = e["fams"][0]
		var business: Dictionary = e["biz"][int(e["estate_biz"])]
		for f in e["fams"]:
			if not f.get("estate", false): f["debt"] = 1.0
		if spec[0] > 0: check(physical.grain(e, estate, spec[0] * 8), "estate fixture transfers existing physical crop fields")
		if spec[1] > 0: check(physical.animals(e, estate, "sheep", spec[1] * 60), "estate fixture transfers existing age-counted animals")
		var land_before: Dictionary = estate["land"].duplicate(true)
		var herd_before: Dictionary = estate["herd"].duplicate(true)
		for day in [30, 37, 60, 67, 90, 97, 150, 180, 210]:
			Game.day = float(day); e["day"] = float(day)
			var base: float = physical.base_need(e, estate)
			var active: float = Families.crop_work(estate, e)["cultivation"]
			var expected := maxi(0, int(ceil(base + (active if Calendar.season_index(day) in [1, 2] else 0.0) - 0.2)))
			TownEcon.town_turn(Game, town, day)
			check(int(business["cap"]) == expected, "weekly estate turn opens real crop-only seasonal places")
			var other = load("res://tests/test_harvest_labour.gd").new()
			var quote_e: Dictionary = other.fixture(String(e["culture"]), 1, 0, 0)
			quote_e["day"] = float(day); quote_e["biz"][0]["cap"] = 0; quote_e["biz"][1]["cap"] = int(business["cap"])
			for repeat in 2:
				Barge.labour_day(quote_e, Calendar.season_index(day))
				check(absf(float(quote_e["ldem"]) - expected) < 0.051, "daily estate demand counts its actual seasonal places once")
			check(estate["land"] == land_before and estate["herd"] == herd_before, "estate seasonal turn preserves real physical holdings")
			var registered_hired := 0
			for f in e["fams"]: registered_hired += int(f["jobs"].get(str(int(business["id"])), 0))
			check(registered_hired == int(business["workers"]), "estate hires resolve to actual household assignments")
			var expected_worked := minf(1.0, float(registered_hired) / base) if base > 0.0 else 0.0
			check(is_equal_approx(float(estate["worked"]), expected_worked), "estate output follows actual staff and base need without harvest yield multiplication")
	town["econ"] = original

func ordinary_legacy_scope(seed_value: int) -> void:
	Game.new_game(seed_value)
	var town: Dictionary = {}
	for candidate in Game.world["towns"].values():
		var sheep := 0
		for family in candidate["econ"]["fams"]: sheep += int(family["herd"].get("sheep", 0))
		if sheep >= 180 and int(candidate["econ"]["land"].get("grain", 0)) >= 16: town = candidate; break
	check(not town.is_empty(), "generated mixed-holding fixture has existing sheep and physical fields")
	if town.is_empty(): return
	var town_id := String(town["id"])
	var e: Dictionary = town["econ"]
	var f := Families._blank(e["fams"].size())
	f["m"] = 3; f["seed"] = 82741; f["homes"] = 1
	f["purse"] = 100000.0
	f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}
	e["fams"].append(f); Persons.generate(e, f, 0.0)
	for p in f["pp"]: p[3] = -24.0 * People.year_days()
	var physical = load("res://tests/farm_fixture_tools.gd").new()
	check(physical.grain(e, f, 16), "legacy mixed holding has real transferred fields")
	check(physical.animals(e, f, "sheep", 180), "legacy mixed holding has real transferred age-counted sheep")
	for b in e["biz"]: b["cap"] = b["workers"]
	e["cjcap"] = {}; e["cjused"] = {}
	Game.day = 60.0; e["day"] = 60.0
	Families.reassign(e, f)
	check(int(f["farm"]) >= 0 and int(f["hands"]) == 3, "mixed holding supports its normal three own hands")
	if int(f["farm"]) < 0: return
	var farm: Dictionary = e["biz"][int(f["farm"])]
	var expected_cap := int(farm["cap"])
	var legacy_cap := expected_cap + 2
	# Reproduce the prior formula in an already-marked autumn save. No new
	# season, idle adult, unpaid employee or missing keeper should force this repair.
	farm["cap"] = legacy_cap; farm["owed"] = 123.0; farm["owed_unattributed"] = 123.0
	farm["till"] = 50000.0; f["farm_harvest"] = true
	f["last"] = 59.0; f["hungry"] = 0; f["unpaid"] = 0; f["idle"] = 0
	f["tax_season"] = e["tax"]["season"]; f["cond"] = 1.0
	var fid := int(f["id"])
	Game.save_game(); check(Game.load_game(), "old seasonal capacity survives a real save/load for ordinary-turn repair")
	town = Game.world["towns"][town_id]; e = town["econ"]; f = e["fams"][fid]
	farm = e["biz"][int(f["farm"])]
	check(int(farm["cap"]) == legacy_cap, "loading does not force immediate reassignment")
	var rng := RandomNumberGenerator.new(); rng.seed = 77329
	Families.turn(Game, town, e, f, 60.0, rng)
	check(int(farm["cap"]) == expected_cap, "next ordinary turn repairs prior herd-multiplied harvest capacity")
	check(float(farm["owed"]) == 123.0 and float(farm["owed_unattributed"]) == 123.0, "capacity repair preserves old earned wage balances")
	check(Families.adults(f) == 3 and int(farm["workers"]) == 0, "capacity repair invents no people or workers")

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		for spec in [[4, 0, 4], [3, 2, 3], [0, 2, 0], [2, 1, 0], [2, 1, 1]]:
			family_scope(culture, spec[0], spec[1], spec[2])
	for seed_value in [901, 2026, 8801]:
		estate_scope(seed_value)
		ordinary_legacy_scope(seed_value)
	print("HARVEST SCOPE checks=", checks, " failures=", fails)
	return fails
