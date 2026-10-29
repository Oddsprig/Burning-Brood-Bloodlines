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
	var saved_world = Game.world
	var saved_company: Array = Game.company.duplicate()
	var saved_gold = Game.gold
	var saved_day = Game.day
	var saved_location = Game.location
	var before_scale: Variant = EconGen.town_scale_override
	var saved_w := WorldGen.W
	var saved_h := WorldGen.H
	var saved_k := WorldGen.K
	var saved_tf := WorldGen.TF
	var saved_kd := WorldGen.KD
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
		check(int(gob["troll"]) == 2 and int(gob["giant"]) == 0, "goblin minorities troll %d giant %d seed %d" % [gob["troll"], gob["giant"], seed])
		if int(orc["troll"]) == 1:
			saw["t1"] = true
		if int(orc["troll"]) == 2:
			saw["t2"] = true
		if int(orc["giant"]) == 0:
			saw["g0"] = true
		if int(orc["giant"]) == 1:
			saw["g1"] = true
		if sample.is_empty() and int(orc["troll"]) >= 1 and int(gob["troll"]) >= 2:
			sample = built
	check(bool(saw["t1"]) and bool(saw["t2"]) and bool(saw["g0"]) and bool(saw["g1"]), "orc rates did not show both ends of 1-2 trolls and 0-1 giants")
	if not sample.is_empty():
		_people(sample)
		_army(sample)
		_attach(sample)
		_ruler(sample)
		_marry(sample)
		_legacy(sample)
	_stores()
	_old_save()
	_sovereign()
	EconGen.town_scale_override = before_scale
	WorldGen.W = saved_w
	WorldGen.H = saved_h
	WorldGen.K = saved_k
	WorldGen.TF = saved_tf
	WorldGen.KD = saved_kd
	Game.world = saved_world
	Game.company = saved_company
	Game.gold = saved_gold
	Game.day = saved_day
	Game.location = saved_location
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

func _attach(sample: Dictionary) -> void:
	var orc: Dictionary = sample["orc"]
	var gob: Dictionary = sample["gob"]
	Game.world = {"version": 1, "seed": sample["seed"], "w": WorldGen.W, "h": WorldGen.H, "cell": WorldGen.CELL,
		"terrain": "", "road": "", "region": "",
		"towns": {"orc_town": orc, "gob_town": gob}, "warbands": {}, "lairs": {},
		"factions": {"orc_horde": {"towns": ["orc_town"], "capital": ""}, "goblin_warren": {"towns": ["gob_town"], "capital": ""}},
		"party": {}, "start_town": "orc_town", "log": [], "encounter": "", "dragons": {"schema": 1, "next_id": 2, "records": {}, "pairs": {}}}

func _orc_adults(e: Dictionary) -> Array:
	var out := []
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false) or f.has("households"):
			continue
		if Persons.family_race(e, f) != "orc":
			continue
		for p in f.get("pp", []):
			if int(p[6]) == 0:
				out.append([f, p])
			if out.size() >= 5:
				return out
	return out

func _bind_soldier(e: Dictionary, town: Dictionary, f: Dictionary, p: Array, race: String) -> Unit:
	var u := Unit.create(race, "orc_horde", true)
	u.home_town = str(town["id"])
	u.battles = 3
	u.rank = 0
	Persons.bind(e, f, p, u, "army", 0.0)
	u.home_town = str(town["id"])
	u.family = int(f["id"])
	return u

func _ruler(sample: Dictionary) -> void:
	var town: Dictionary = sample["orc"]
	var e: Dictionary = town["econ"]
	var tf := _family(e, "troll")
	var troll_person := _adult(tf)
	var orc_people := _orc_adults(e)
	if tf.is_empty() or troll_person.is_empty() or orc_people.is_empty():
		check(false, "ruler test needs an orc adult and a troll adult")
		return
	var units := []
	# Family is troll, body race forced back to orc: the old u.race gate would seat him.
	var disguised := _bind_soldier(e, town, tf, troll_person, "orc")
	disguised.race = "orc"
	disguised.attrs["STR"] = 4000
	units.append(disguised)
	var brute := _bind_soldier(e, town, tf, troll_person, "troll")
	brute.attrs["STR"] = 5000
	units.append(brute)
	for i in 5:
		var pair: Array = orc_people[mini(i, orc_people.size() - 1)]
		var u := _bind_soldier(e, town, pair[0], pair[1], "orc")
		u.race = "orc"
		u.attrs["STR"] = 400
		units.append(u)
	var by := {}
	for u in units:
		by[u.uid] = u
	Game.world["warbands"]["ruler"] = {"id": "ruler", "units": units, "faction": "orc_horde", "kind": "army", "home": town["id"], "pos": town["pos"]}
	var r := Army.rec(Game.world, "orc_horde")
	r["levels"] = 1
	r["posts"] = [-1]
	r["fights"] = []
	ArmyRanks.fill(Game, "orc_horde", 0, by, true, 0, false)
	var holder := int(r["posts"][0])
	var holder_u = by.get(holder, null)
	var holder_race := ""
	if holder_u is Unit:
		holder_race = Persons.family_race(e, People.fam_of(town, holder_u.family))
	check(holder > 0 and holder != disguised.uid and holder != brute.uid and holder_race == "orc", "troll family does not take the orc warlord post (holder %d race %s)" % [holder, holder_race])
	r["posts"] = [-1]
	r["fights"] = []
	for u in units:
		u.rank = 0
		u.role = "troop"
	ArmyRanks.fill(Game, "orc_horde", 0, by, false, 0, false)
	var fight_uids: Array = []
	if not (r["fights"] as Array).is_empty():
		fight_uids = r["fights"][0]["c"]
	check(fight_uids.size() >= 2 and not fight_uids.has(disguised.uid) and not fight_uids.has(brute.uid), "warlord duel excludes troll families (%s)" % str(fight_uids))
	r["levels"] = 2
	r["posts"] = [-1, -1, -1, -1, -1, -1]
	r["fights"] = []
	brute.rank = 0
	brute.battles = 3
	var only := {}
	only[brute.uid] = brute
	ArmyRanks.fill(Game, "orc_horde", 1, only, true, 0, false)
	check(int(r["posts"][1]) == brute.uid, "troll can still hold a lower champion post")
	r["levels"] = 1
	r["posts"] = [brute.uid]
	r["fights"] = []
	for u in units:
		u.rank = 0
		u.role = "troop"
	ArmyRanks.update_tree(Game, "orc_horde", units, true, 0)
	var seated := int(r["posts"][0]) if not (r["posts"] as Array).is_empty() else -1
	check(seated > 0 and seated != brute.uid and seated != disguised.uid, "a seated troll warlord is removed (post %d)" % seated)

func _troll_houses(e: Dictionary) -> Array:
	var out := []
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false) or f.has("households"):
			continue
		if String(f.get("race", "")) == "troll":
			out.append(f)
	return out

func _home_adult(f: Dictionary, sex: int) -> Array:
	for p in f.get("pp", []):
		if int(p[6]) != 0:
			continue
		p[2] = sex
		p[6] = 0
		return p
	return []

func _marry(sample: Dictionary) -> void:
	var e: Dictionary = sample["gob"]["econ"]
	var houses := _troll_houses(e)
	if houses.size() < 2:
		check(false, "goblin town has %d troll houses" % houses.size())
		return
	var groom_f: Dictionary = houses[0]
	var bride_f: Dictionary = houses[1]
	var man := _home_adult(groom_f, 0)
	var woman := _home_adult(bride_f, 1)
	if man.is_empty() or woman.is_empty():
		check(false, "troll houses need an adult each")
		return
	if String(groom_f["name"]) == String(bride_f["name"]):
		bride_f["name"] = String(bride_f["name"]) + " Kin"
	var yd := People.year_days()
	man[3] = int(round(-30.0 * yd))
	woman[3] = int(round(-27.0 * yd))
	man[4] = ""
	woman[4] = ""
	man[6] = 0
	woman[6] = 0
	if man.size() > Persons.SP:
		man[Persons.SP] = -1
	if woman.size() > Persons.SP:
		woman[Persons.SP] = -1
	if man.size() > Persons.SPOUSE_UID:
		man[Persons.SPOUSE_UID] = ""
	if woman.size() > Persons.SPOUSE_UID:
		woman[Persons.SPOUSE_UID] = ""
	if String(woman[7]) == "":
		woman[7] = "Krusha " + String(bride_f["name"])
	# marriages() refuses a bride whose given-name index is already held by any
	# woman or girl of the groom's surname (adults in pp and children in kp).
	# Troll lists are short, so an adult-only check still blocks the wedding.
	var blocked := {}
	var sur := String(groom_f.get("name", ""))
	for gf in e.get("fams", []):
		if String(gf.get("name", "")) != sur:
			continue
		for key in ["pp", "kp"]:
			for q in gf.get(key, []):
				if int(q[2]) == 1:
					blocked[int(q[1])] = true
	var fi := 9001
	while blocked.has(fi):
		fi += 1
	woman[1] = fi
	for f in houses:
		for p in f.get("pp", []):
			if int(p[0]) == int(man[0]) or int(p[0]) == int(woman[0]):
				continue
			p[4] = "army"
	var n := Persons.marriages(e, 0.0)
	var moved := false
	for q in groom_f.get("pp", []):
		if int(q[0]) == int(woman[0]):
			moved = true
	check(moved, "goblin troll bride joined the other troll house (weddings %d)" % n)

func _horse_stocked(e: Dictionary, fid: int, horse_uid: int) -> bool:
	var h := Herds.herd_for(e, fid, "horses", 0.0)
	for body in h.get("mount_bodies", []):
		if int(body.get("uid", -1)) == horse_uid:
			return true
	return false

func _legacy(sample: Dictionary) -> void:
	var town: Dictionary = sample["orc"]
	var e: Dictionary = town["econ"]
	var tf := _family(e, "troll")
	var person := _adult(tf)
	if person.is_empty():
		check(false, "legacy load needs a troll adult")
		return
	var u := _bind_soldier(e, town, tf, person, "troll")
	var horse := Unit.create("horse", "orc_horde", true)
	var horse_uid := horse.uid
	u.horse = horse
	u.horse_care = {"fed": true, "paid": true}
	Game.company.append(u)
	var giant := Unit.create("giant", "orc_horde", true)
	giant.home_town = str(town["id"])
	giant.family = -1
	giant.horse = Unit.create("horse", "orc_horde", true)
	Game.company.append(giant)
	var rider_uid := str(Persons.g(person, Persons.PERSON_UID, ""))
	check(rider_uid != "", "troll person has an identity for the legacy bond")
	Game.world["dragons"] = {"schema": 1, "next_id": 2, "records": {}, "pairs": {}}
	Game.world["dragons"]["records"]["dragon:v071:1"] = {"id": "dragon:v071:1", "alive": true, "rider_person_uid": rider_uid, "history": [], "owner_person_uid": ""}
	DragonBond.after_load(Game)
	Horses.after_load(Game)
	var bond: Dictionary = Game.world["dragons"]["records"]["dragon:v071:1"]
	check(str(bond.get("rider_person_uid", "x")) == "" and str(bond.get("last_separation_reason", "")) == "foot_only", "legacy troll dragon rider separated (%s)" % str(bond.get("last_separation_reason", "")))
	check(u.horse == null and _horse_stocked(e, int(tf["id"]), horse_uid), "legacy troll horse returned to stock")
	check(giant.horse == null, "legacy giant horse link cleared")

func _stores() -> void:
	var orc := Unit.create("orc", "orc_horde", false)
	var troll := Unit.create("troll", "orc_horde", false)
	var orc_band := {"units": [orc]}
	var troll_band := {"units": [troll]}
	Supplies.seed_stores(orc_band)
	Supplies.seed_stores(troll_band)
	check(is_equal_approx(float(orc_band["stores"]["grain"]), 9.0) and is_equal_approx(float(orc_band["stores"]["meat"]), 3.0) and is_equal_approx(float(orc_band["stores"]["beer"]), 6.0), "orc seed stores stay one share")
	check(is_equal_approx(float(troll_band["stores"]["grain"]), 19.8) and is_equal_approx(float(troll_band["stores"]["meat"]), 6.6) and is_equal_approx(float(troll_band["stores"]["beer"]), 13.2), "troll seed stores use food_mult 2.2")

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
