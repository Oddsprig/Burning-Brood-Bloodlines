extends RefCounted
## v0.080: high elves and dark elves are sovereign realms, with portraits, names and a fight.
## PortraitBust has no class_name (FigurePainter loads it). Preload it here.

const Bust = preload("res://art/portrait_bust.gd")
const Balance = preload("res://tests/balance_v070.gd")

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func run(_tree: SceneTree) -> int:
	_data()
	_world()
	_fight()
	print("high_dark_elves_v080 checks %d fails %d" % [checks, fails])
	return fails

func _data() -> void:
	check(bool(DB.races["high_elf"].get("enabled", false)), "high_elf race is not enabled")
	check(bool(DB.races["dark_elf"].get("enabled", false)), "dark_elf race is not enabled")
	check(not bool(DB.races["troll"].get("enabled", false)), "troll race must stay disabled")
	check(WorldGen.region_faction("sunwood") == "sun_court", "sunwood is not the Sunwood Court")
	check(WorldGen.region_faction("nightwood") == "night_court", "nightwood is not the Nightwood Court")
	check(not WorldGen.is_sovereign_faction("troll_den"), "troll_den must stay a minority den, not a realm")
	check(Balance.RACES.has("high_elf") and Balance.RACES.has("dark_elf") and not Balance.RACES.has("troll"), "BalanceV070 races missing an elf or listing trolls")
	for id in ["sun_glaive", "sun_helm", "sun_recurve", "night_glaive", "night_helm", "night_recurve"]:
		var row: Dictionary = DB.template(id)
		check(not row.is_empty(), "missing gear template " + id)
	check(FigurePainter.helm_maker({"culture": "high_elf", "tid": "sun_helm"}) == "high_elf", "sun helm maker")
	check(FigurePainter.helm_maker({"culture": "dark_elf", "tid": "night_helm"}) == "dark_elf", "night helm maker")
	check(FigurePainter.elf_helm_maker("high_elf") and FigurePainter.elf_helm_maker("dark_elf"), "elf helm art not shared")
	for race in ["high_elf", "dark_elf"]:
		var img: Image = Bust.paint({
			"race": race, "sex": "male", "age": 150, "seed": 8080,
			"skin": DB.races[race]["skin"][0], "hair": DB.races[race]["hair"][0],
		})
		var ink := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.2:
					ink += 1
		check(ink > 80, "%s portrait drew %d pixels" % [race, ink])

func _world() -> void:
	Game.new_game(1234)
	var w: Dictionary = Game.world
	var towns_of := {"high_elf": 0, "dark_elf": 0}
	var named := {"high_elf": false, "dark_elf": false}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		var fid := String(t.get("faction", ""))
		var race := String(DB.factions.get(fid, {}).get("race", ""))
		if not towns_of.has(race):
			continue
		towns_of[race] = int(towns_of[race]) + 1
		var e: Dictionary = t.get("econ", {})
		check(not e.is_empty() and e.has("fams"), race + " town " + String(t.get("name", tid)) + " has no households")
		if e.is_empty():
			continue
		check(Persons.race_of(e) == race, race + " town culture race is " + Persons.race_of(e))
		for f in e.get("fams", []):
			if f.get("estate", false) or f.get("gone", false) or f.has("households"):
				continue
			if String(f.get("race", "")) != race:
				continue
			var lasts: Array = DB.names.get(race, {}).get("last", [])
			if lasts.has(String(f.get("name", ""))):
				named[race] = true
			for p in f.get("pp", []):
				if typeof(p) != TYPE_ARRAY or p.size() < 3:
					continue
				var first := Persons.first_of(e, p)
				if Persons.names_for(race, int(p[2])).has(first):
					named[race] = true
	for race in ["high_elf", "dark_elf"]:
		check(int(towns_of[race]) >= 2, "%s towns %d, wanted at least 2" % [race, towns_of[race]])
		check(bool(named[race]), race + " household has neither an elf given name nor a race surname")
	var seen := {"high_elf": false, "dark_elf": false}
	for row in HouseOnboarding.settlements(Game):
		var race := String(row.get("race", ""))
		if seen.has(race):
			seen[race] = true
	check(bool(seen["high_elf"]) and bool(seen["dark_elf"]), "house select did not list both elf realms")

func _fight() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	var sun: Array = []
	var night: Array = []
	var sun_troop: Dictionary = DB.factions["sun_court"]["troops"][0]
	var night_troop: Dictionary = DB.factions["night_court"]["troops"][0]
	for _i in 3:
		sun.append(Factory.make_troop(rng, "sun_court", sun_troop))
		night.append(Factory.make_troop(rng, "night_court", night_troop))
	check(sun[0].race == "high_elf" and night[0].race == "dark_elf", "troops are not high elf vs dark elf")
	var sim := BattleSim.new()
	sim.setup(sun, night, 8080, {"w": 16, "h": 8, "max_ticks": 2500, "log_moves": false, "verbose": false, "combat_journal": false})
	var steps := 0
	while not sim.is_over() and steps < 3000:
		sim.step()
		steps += 1
	var hurt := 0.0
	for f in sim.fighters:
		hurt += _injury(f.unit)
	check(sim.is_over() and (hurt > 0.0 or sim.winner >= 0), "elf fight did not end in contact (steps %d hurt %.2f winner %d)" % [steps, hurt, sim.winner])
	print("elf fight steps %d hurt %.2f winner %d" % [steps, hurt, sim.winner])

func _injury(u: Unit) -> float:
	var total := 0.0
	for part: Dictionary in u.body.parts.values():
		for layer: Dictionary in part.get("layers", []):
			total += float(layer.get("dmg", 0.0))
	return total

