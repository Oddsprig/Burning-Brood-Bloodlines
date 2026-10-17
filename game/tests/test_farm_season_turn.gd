extends RefCounted

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func scenario(seed_v: int) -> void:
	Game.new_game(seed_v)
	var town: Dictionary = {}
	for candidate in Game.world["towns"].values():
		if TownEcon.has_econ(candidate) and String(TownEcon.culture_of(candidate["econ"])["race"]) == "human":
			town = candidate; break
	check(not town.is_empty(), "a generated town supports the ordinary seasonal fixture")
	if town.is_empty(): return
	var town_id := String(town["id"])
	var e: Dictionary = town["econ"]
	# A controlled real register household has enough own labour in spring,
	# but needs one hired place at harvest. Ordinary turn is the only entry point.
	var f := Families._blank(e["fams"].size())
	f["m"] = 1; f["name"] = "Season fixture"; f["seed"] = 91245
	f["homes"] = 1; f["purse"] = 10000.0
	f["store"] = {"food": 1000.0, "drink": 1000.0, "wood": 1000.0}
	e["fams"].append(f)
	Persons.generate(e, f, 0.0)
	f["pp"][0][3] = -24.0 * People.year_days()
	TownEcon.recount(e)
	var physical = load("res://tests/farm_fixture_tools.gd").new()
	check(physical.grain(e, f, 8), "season fixture uses transferred real productive fields and draft animals")
	# Existing outside employers have no vacancies in this unit fixture. Their
	# current staff and money stay intact, so a higher bid cannot mask the trigger.
	for b in e["biz"]: b["cap"] = int(b["workers"])
	Families.reassign(e, f)
	check(int(f["farm"]) == -1 and int(f["hands"]) == 1 and int(f["idle"]) == 0, "spring requires no hired farm position")
	var population := Families.people(f)
	var rng := RandomNumberGenerator.new(); rng.seed = 66829
	var prior_farm := -1
	for day in [30, 37, 60, 67, 90, 97, 120, 150, 180, 187, 210]:
		Game.day = float(day); e["day"] = float(day); f["last"] = float(day - 1)
		# Remove unrelated economic causes of reassignment; the season must trigger it.
		f["unpaid"] = 0; f["idle"] = 0; f["hungry"] = 0
		f["tax_season"] = e["tax"]["season"]
		f["cond"] = 1.0
		var jobs: Dictionary = f["jobs"].duplicate(true)
		Families.turn(Game, town, e, f, float(day), rng)
		var harvest := Calendar.season_index(float(day)) in [1, 2]
		check(f.has("farm_harvest") and bool(f.get("farm_harvest", false)) == harvest, "ordinary family turn records current harvest state")
		check(int(f["farm"]) >= 0, "harvest opens the real missing hired place (seed%d day%d land%s need%.3f gone%s)" % [seed_v, day, f["land"], Families.need_hands(f, e), f.get("gone", false)])
		if int(f["farm"]) < 0: continue
		var farm: Dictionary = e["biz"][int(f["farm"]) ]
		check(int(farm["cap"]) == (1 if harvest else 0), "ordinary seasonal transition sets capacity once")
		check(prior_farm < 0 or int(f["farm"]) == prior_farm, "repeated seasons reuse the existing family farm")
		prior_farm = int(f["farm"])
		check(Families.people(f) == population and int(farm["workers"]) == 0 and f["jobs"] == jobs, "seasonal capacity does not invent adults or hired workers")
		if day == 67:
			var marker: bool = bool(f.get("farm_harvest", false))
			var cap: int = int(farm["cap"])
			# The ordinary save writer serializes floats at JSON precision.
			var till: float = float(JSON.parse_string(JSON.stringify([farm["till"]]))[0])
			Game.save_game()
			check(Game.load_game(), "seasonal farm campaign saves and loads")
			town = Game.world["towns"][town_id]; e = town["econ"]; f = e["fams"][int(f["id"])]
			farm = e["biz"][int(f["farm"])]
			check(f.get("farm_harvest", null) == marker and farm["cap"] == cap and float(farm["till"]) == float(till), "save retains season marker, places and actual till (seed%d farm%d/%d owner%d fid%d cap%d/%d till%.3f/%.3f land%s)" % [seed_v, f["farm"], prior_farm, farm["owner"], f["id"], farm["cap"], cap, farm["till"], till, f["land"]])
	# A current save without the new marker initializes at its next ordinary turn.
	f.erase("farm_harvest")
	e["day"] = 211.0; Game.day = 211.0; f["last"] = 210.0
	Families.turn(Game, town, e, f, 211.0, rng)
	check(f.has("farm_harvest") and not bool(f["farm_harvest"]), "existing unmarked family initializes on ordinary turn")

func run(_tree: SceneTree) -> int:
	for seed_v in [901, 2026, 8801]: scenario(seed_v)
	print("FARM SEASON TURN checks=", checks, " failures=", fails)
	return fails
