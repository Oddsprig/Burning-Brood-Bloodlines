extends RefCounted
## v0.071: troll and giant families inside orc and goblin towns, on foot only.

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func run(_tree: SceneTree) -> int:
	var before_scale: Variant = EconGen.town_scale_override
	EconGen.town_scale_override = 0.2
	WorldGen.set_size(WorldGen.STRETCH)
	var saw := {"t1": false, "t2": false, "g0": false, "g1": false}
	var sample: Dictionary = {}
	for seed in [1, 2, 3, 5, 8, 13, 21, 34]:
		var built := _world(seed)
		var orc: Dictionary = _counts(built["orc"]["econ"])
		var gob: Dictionary = _counts(built["gob"]["econ"])
		check(int(orc["troll"]) >= 1 and int(orc["troll"]) <= 2, "orc trolls %d seed %d" % [orc["troll"], seed])
		check(int(orc["giant"]) >= 0 and int(orc["giant"]) <= 1, "orc giants %d seed %d" % [orc["giant"], seed])
		check(int(gob["troll"]) == 1 and int(gob["giant"]) == 0, "goblin minorities troll %d giant %d seed %d" % [gob["troll"], gob["giant"], seed])
		if int(orc["troll"]) == 1:
			saw["t1"] = true
		if int(orc["troll"]) == 2:
			saw["t2"] = true
		if int(orc["giant"]) == 0:
			saw["g0"] = true
		if int(orc["giant"]) == 1:
			saw["g1"] = true
		if sample.is_empty() and int(orc["troll"]) >= 1:
			sample = built
	check(bool(saw["t1"]) and bool(saw["t2"]) and bool(saw["g0"]) and bool(saw["g1"]), "orc rates did not show both ends of 1-2 trolls and 0-1 giants")
	if not sample.is_empty():
		_people(sample)
		_army(sample)
	_old_save()
	_sovereign()
	EconGen.town_scale_override = before_scale
	print("trolls_giants_v071 checks %d fails %d" % [checks, fails])
	return fails

func _world(seed: int) -> Dictionary:
	Game.day = 0.0
	Game.gold = 100
	Game.location = ""
	Game.company.clear()
	var orc := _town("orc_town", "Red Camp", "orc", "orc_horde", "east", 20)
	var gob := _town("gob_town", "Skrag Pit", "goblin", "goblin_warren", "south", 40)
	var towns := {"orc_town": orc, "gob_town": gob}
	var cells := WorldGen.W * WorldGen.H
	Game.world = {"version": 1, "seed": seed, "w": WorldGen.W, "h": WorldGen.H, "cell": WorldGen.CELL,
		"terrain": "g".repeat(cells), "road": "0".repeat(cells), "region": "0".repeat(cells),
		"towns": towns, "warbands": {}, "lairs": {},
		"factions": {"orc_horde": {"towns": ["orc_town"], "capital": ""}, "goblin_warren": {"towns": ["gob_town"], "capital": ""}},
		"party": {"pos": orc["pos"], "target": orc["pos"], "path": [], "dest_town": "", "arrived": "", "safe_until": 0.0, "waiting": false},
		"start_town": "orc_town", "log": [], "encounter": ""}
	for town in [orc, gob]:
		var town_rng := RandomNumberGenerator.new()
		town_rng.seed = hash([seed, town["id"], "fixture-town"])
		Economy.make_crafters(town, town_rng)
		Economy.roll_prices(town, town_rng)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, town["id"], "econ"])
		EconGen.generate(Game.world, town, rng)
	return {"orc": orc, "gob": gob, "seed": seed}

func _town(tid: String, name: String, culture: String, faction: String, region: String, x: int) -> Dictionary:
	return {"id": tid, "name": name, "culture": culture, "faction": faction, "capital": false, "size": 2,
		"wealth": 2, "specialty": "military", "pos": WorldGen.cell_center(Vector2i(x, 25)), "recruits": [], "shop": [],
		"roads": [], "neighbours": [], "region": region, "crafters": {}, "healer": {}, "prices": {},
		"material_prices": {}, "contracts": [], "next_refresh": 0.0}

func _counts(e: Dictionary) -> Dictionary:
	var c := {"troll": 0, "giant": 0}
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false) or f.has("households"):
			continue
		var race := String(f.get("race", ""))
		if c.has(race):
			c[race] = int(c[race]) + 1
	return c

func _family(e: Dictionary, race: String) -> Dictionary:
	for f in e["fams"]:
		if f.get("estate", false) or f.has("households"):
			continue
		if String(f.get("race", "")) == race:
			return f
	return {}

func _adult(f: Dictionary) -> Array:
	for p in f.get("pp", []):
		if int(p[6]) == 0:
			return p
	return []

func _people(sample: Dictionary) -> void:
	var e: Dictionary = sample["orc"]["econ"]
	var tf := _family(e, "troll")
	check(not tf.is_empty(), "sample orc town has a troll family")
	if tf.is_empty():
		return
	check(String(tf.get("minority_role", "")) != "", "troll family stores a minority role")
	for p in tf.get("pp", []) + tf.get("kp", []):
		var shown := Persons.name_of(tf, p, "orc")
		var first := shown.split(" ")[0]
		check(Persons.names_for("troll", int(p[2])).has(first), "troll member named %s" % shown)
	var mother := _adult(tf)
	if mother.is_empty():
		return
	var kid := Persons.birth(e, tf, mother, 10.0, -2, 0)
	check(String(tf["race"]) == "troll", "birth keeps the family race")
	var kn := Persons.name_of(tf, kid, "orc")
	check(Persons.names_for("troll", int(kid[2])).has(kn.split(" ")[0]), "newborn named %s" % kn)

func _army(sample: Dictionary) -> void:
	var town: Dictionary = sample["orc"]
	var e: Dictionary = town["econ"]
	var tf := _family(e, "troll")
	var person := _adult(tf)
	if person.is_empty():
		check(false, "troll family has no adult to recruit")
		return
	var u := Unit.create("orc", "orc_horde", true)
	u.wage = 10
	u.hire_cost = 100
	u.horse = Unit.create("horse", "orc_horde", false)
	u.family = -1
	Persons.bind(e, tf, person, u, "army", 0.0)
	var wb := {"id": "v071", "units": [u], "faction": "orc_horde", "kind": "army", "home": town["id"], "pos": town["pos"]}
	Game.world["warbands"]["v071"] = wb
	check(u.race == "troll", "recruit keeps troll race, got %s" % u.race)
	check(u.horse == null, "troll recruit is not mounted")
	check(not Horses.can_mount_race("troll") and not Horses.can_mount_race("giant"), "troll and giant cannot be mount races")
	check(Horses.fights_on_foot_only("troll") and Horses.fights_on_foot_only("giant"), "foot-only check")
	u.horse = Unit.create("horse", "orc_horde", false)
	u.horse_care = {"fed": true, "paid": true}
	check(not Horses.can_field(u), "a horse does not field a troll")
	u.horse = null
	check(u.equip.has("main_hand") and not u.equip.has("off_hand") and not u.equip.has("ranged"), "heavy kit has no shield or bow")
	check(u.wage == 22 and u.hire_cost == 220, "wage scaled by troll food_mult, wage %d hire %d" % [u.wage, u.hire_cost])
	var why := DragonBond._eligibility(null, {}, {"race": "troll", "age": 40, "person_uid": "x"})
	var why2 := DragonBond._approach_eligibility(null, {}, {"race": "giant", "age": 40, "person_uid": "y"})
	check(why == "Trolls and giants fight on foot only.", "dragon bind refused: %s" % why)
	check(why2 == "Trolls and giants fight on foot only.", "dragon approach refused: %s" % why2)
	check(Army.heavy_cap(20) == 3 and Army.heavy_cap(6) == 0 and Army.heavy_cap(7) == 1, "heavy cap is floor of 15 percent")
	var pool := []
	for _i in 6:
		pool.append([0, 0, int(tf["id"]), int(person[0])])
	var plain := _family(e, "orc")
	if plain.is_empty():
		for f in e["fams"]:
			if not f.get("estate", false) and not f.has("households") and String(f.get("race", "orc")) == "orc":
				plain = f
				break
	for _i in 6:
		pool.append([0, 0, int(plain.get("id", -1)), 1])
	Army.drop_heavy_drafts(town, pool)
	var left_heavy := false
	for row in pool:
		if int(row[2]) == int(tf["id"]):
			left_heavy = true
	check(not left_heavy and pool.size() == 6, "draft pool drops troll families once the heavy cap is full")

func _old_save() -> void:
	var e := {"culture": "orc", "fams": [], "next_pid": 1}
	check(Persons.family_race(e, {}) == Persons.race_of(e), "missing family race defaults to the town race")
	var bare := {"id": 3, "name": "Oldsave", "seed": 1}
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var p := Persons._new(e, bare, "orc", 0, 0.0, 0, rng)
	check(String(p[7]) == "", "old-save person does not freeze a minority name")
	var shown := Persons.name_of(bare, p, "orc")
	check(Persons.names_for("orc", 0).has(shown.split(" ")[0]), "old-save name stays an orc name (%s)" % shown)

func _sovereign() -> void:
	check(bool(DB.factions["troll_den"].get("minor_only", false)), "troll_den is minor_only")
	check(not WorldGen.is_sovereign_faction("troll_den"), "troll_den is not sovereign")
	for region in ["middle", "north", "east", "south", "west", "holds", "southeast", ""]:
		check(WorldGen.region_faction(region) != "troll_den", "region %s is not a troll den" % region)
	for fid in DB.factions:
		if bool(DB.factions[fid].get("minor_only", false)):
			check(not WorldGen.is_sovereign_faction(fid), "%s stayed out of sovereign generation" % fid)
