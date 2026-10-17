extends RefCounted
## Frozen native tick control. Tiny fixtures exercise actual _fight, without generation.
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func _units(n: int, first_uid: int, faction: String) -> Array:
	var out := []
	for i in n:
		var u := Unit.new()
		u.uid = first_uid + i; u.faction = faction; u.name = "Fixture %d" % u.uid
		u.body = BodyState.new()
		out.append(u)
	return out

func _band(id: String, kind: String, faction: String, n: int, first_uid: int) -> Dictionary:
	return {"id": id, "kind": kind, "faction": faction, "units": _units(n, first_uid, faction),
		"pos": Vector2(10, 0), "anchor": Vector2.ZERO, "path": [], "walls": false,
		"mustered": false, "drill_today": true, "stores": {"grain": 3}, "gold": 0.0}

func _fixture(winning: bool) -> Dictionary:
	var a := _band("mil_a", "militia", "middle_kingdom", 20 if winning else 5, 100)
	var b := _band("mil_b", "militia", "middle_kingdom", 4, 200)
	a["home"] = "a"; b["home"] = "b"
	var main := _band("main", "raider", "moon_court", 1 if winning else 4, 300)
	var raid0 := _band("raid0", "raider", "moon_court", 1, 400)
	var raid1 := _band("raid1", "raider", "moon_court", 1, 500)
	raid0["raid"] = {"town": "a"}; raid1["raid"] = {"town": "b"}
	var pair := {"state": Diplomacy.WAR, "rel": -60.0, "cap": 4, "losses": 0.0}
	Game.world = {"seed": 711, "towns": {
		"a": {"id": "a", "name": "First fixture", "faction": "middle_kingdom", "pos": Vector2.ZERO, "econ": {}, "size": 2},
		"b": {"id": "b", "name": "Second fixture", "faction": "middle_kingdom", "pos": Vector2(20, 0), "econ": {}, "size": 2}},
		"militia": {"a": "mil_a", "b": "mil_b"},
		# Original insertion order includes repeated raid muster calls around the fight.
		"warbands": {"mil_a": a, "mil_b": b, "raid0": raid0, "main": main, "raid1": raid1},
		"factions": {"moon_court": {"strength": 1.0, "treasury": 0.0}},
		"diplo": {"day": 1, "pairs": {Diplomacy.pair_key("middle_kingdom", "moon_court"): pair}},
		"log": [], "encounter": ""}
	return Game.world

func _seed(winning: bool) -> int:
	var pwin := 400.0 / 401.0 if winning else 25.0 / 41.0
	for seed in 100:
		var rng := RandomNumberGenerator.new(); rng.seed = seed
		if (rng.randf() < pwin) == winning: return seed
	return -1

func _plain(value):
	if value is Unit: return value.to_dict()
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = _plain(value[key])
		return out
	if value is Array:
		var out := []
		for part in value: out.append(_plain(part))
		return out
	return value

func _case(winning: bool) -> void:
	_fixture(winning)
	var rng := RandomNumberGenerator.new(); rng.seed = _seed(winning)
	ArmsTrade.ledger = {}; ArmsTrade.spoils_gold = {"soldiers": 0.0, "coffer": 0.0}
	_reference_tick(Game, rng)
	var old: Dictionary = _plain(Game.world)
	var old_rng := rng.state
	var old_ledger := ArmsTrade.ledger.duplicate(true)
	var old_spoils := ArmsTrade.spoils_gold.duplicate(true)
	_fixture(winning)
	rng.seed = _seed(winning)
	ArmsTrade.ledger = {}; ArmsTrade.spoils_gold = {"soldiers": 0.0, "coffer": 0.0}
	Militia.tick(Game, rng)
	check(JSON.stringify(_plain(Game.world), "", false, true) == JSON.stringify(old, "", false, true),
		"complete ordered native world matches frozen tick after " + ("win" if winning else "loss"))
	check(rng.state == old_rng and ArmsTrade.ledger == old_ledger and ArmsTrade.spoils_gold == old_spoils,
		"native fight RNG, gear and coin books match frozen tick")
	check(Game.world["warbands"]["mil_a"]["units"].size() < (20 if winning else 5), "actual fight changes the first militia roster")
	if winning:
		var pair: Dictionary = Game.world["diplo"]["pairs"].values()[0]
		check(not Game.world["warbands"].has("main") and float(pair["losses"]) > 0 and float(pair["rel"]) < -60.0,
			"actual native victory removes the force and changes diplomacy")
	else:
		check(float(Game.world["warbands"]["main"]["rest_until"]) > float(Game.day), "actual loss gives the enemy its native rest period")
		check(Game.world["warbands"]["mil_b"]["units"].size() == 4,
			"fight invalidation makes the next same-faction town reject the newly resting enemy")

func _verdict_boundary() -> void:
	var w := _fixture(true)
	var mil: Dictionary = w["warbands"]["mil_a"]
	var x: Dictionary = w["warbands"]["main"]
	var cache := {}
	check(Militia._tick_threat(Game, mil, x, cache) == Militia.is_threat(Game, mil, x), "first cached verdict is native")
	check(Militia._tick_threat(Game, w["warbands"]["mil_b"], x, cache), "same faction shares the native verdict")
	var pair: Dictionary = w["diplo"]["pairs"].values()[0]
	pair["state"] = Diplomacy.NEUTRAL
	cache.clear() # the production tick does this immediately after every native fight
	check(not Militia._tick_threat(Game, mil, x, cache), "fresh boundary observes a changed diplomatic state")
	pair["state"] = Diplomacy.WAR; x["units"][0].race = "wolf"
	cache.clear()
	check(Militia._tick_threat(Game, mil, x, cache) == Militia.is_threat(Game, mil, x),
		"fresh boundary observes an actually changed roster through native suspension rules")

func _muster_fixture(mixed: bool) -> Dictionary:
	var rows := []
	for i in 160:
		rows.append(["Person %d" % i, 0, -9000, 0, "militia" if mixed and i % 3 == 0 else "reserve", 600 + i, 0])
	# Deliberate duplicate and alias cases must retain the FIRST native match.
	rows.append(["Later duplicate", 0, -8000, 0, "militia" if mixed else "reserve", 601, 0])
	rows.append(rows[8])
	var units := []
	for uid in [601, 603, 608, 603, 600, 700, 9999]:
		var u := Unit.new(); u.uid = uid; u.family = 0; u.body = BodyState.new()
		units.append(u)
	# A retained gone family makes the mixed edge fixture independent of town
	# production setup; it still uses native person/service updates in full.
	var f := {"id": 0, "gone": mixed, "pp": rows, "serve": {"militia": 54 if mixed else 0}, "purse": 77.0}
	var town := {"id": "muster", "pos": Vector2(25, 30),
		"econ": {"stock": {}, "fams": [f], "biz": [], "treasury": 123.0}}
	Game.world = {"militia": {"muster": "band"}, "towns": {"muster": town},
		"warbands": {"band": {"units": units, "mustered": true, "drill_today": true,
			"path": [Vector2(9, 9)], "pos": Vector2(10, 10)}}}
	return town

func _muster_differential() -> void:
	for mixed in [false, true]:
		var town := _muster_fixture(mixed)
		_reference_muster(Game, town, false)
		var old: Dictionary = _plain(Game.world)
		town = _muster_fixture(mixed)
		TownDefence.set_muster(Game, town, false)
		check(JSON.stringify(_plain(Game.world), "", false, true) == JSON.stringify(old, "", false, true),
			"uniform/mixed call-local muster preserves ordered people/service/coin/position (mixed=%s)" % mixed)
		var f: Dictionary = town["econ"]["fams"][0]
		check(String(f["pp"][1][4]) == "reserve" and String(f["pp"][160][4]) == ("militia" if mixed else "reserve"),
			"later duplicate UID does not replace the first person")
		check(is_same(f["pp"][8], f["pp"][161]), "native shared person Array alias is retained")
		check(Game.world["warbands"]["band"]["path"].is_empty()
			and Game.world["warbands"]["band"]["pos"] == town["pos"], "off-duty no-op still resets native path and position")
	var town := _muster_fixture(false)
	var f: Dictionary = town["econ"]["fams"][0]
	check(TownDefence._muster_rows(f, "reserve").is_empty(), "homogeneous already-requested jobs need no UID map")
	f["pp"][0][4] = "militia"
	var index := TownDefence._muster_rows(f, "reserve")
	for uid in [600, 601, 608, 760, 9999]:
		var actual: Array = index.get(uid, [])
		var expected := Persons.by_uid(f, uid)
		check(actual == expected and (actual.is_empty() or is_same(actual, expected)), "mixed reverse-built lookup preserves first match and alias for UID %d" % uid)

## Frozen old lookup and transaction order; actual native reassignment/matching
## remain the same and are invoked for the same affected families.
func _reference_muster(game, town: Dictionary, active: bool, drill: bool = false) -> void:
	match TownDefence.defence_policy(game, town):
		"muster": active = true
		"stand_down": active = false; drill = false
	var wb := Militia.band_of(game, String(town["id"]))
	if wb.is_empty(): return
	wb["mustered"] = active; wb["drill_today"] = drill
	var e: Dictionary = town["econ"]
	var families: Array = e.get("fams", []) if TownEcon.has_econ(town) else []
	var wanted := "militia" if active or drill else "reserve"
	var affected := []; var person_rows := {}
	for u in wb["units"]:
		if u.family < 0 or u.family >= families.size(): continue
		var f: Dictionary = families[u.family]
		if f.is_empty(): continue
		if not person_rows.has(u.family):
			var by_uid := {}
			for row: Array in Persons.pp(f):
				var uid := int(row[5])
				if not by_uid.has(uid): by_uid[uid] = row
			person_rows[u.family] = by_uid
		var p: Array = person_rows[u.family].get(u.uid, [])
		if p.is_empty(): continue
		var old := String(p[4])
		if old == wanted: continue
		if old == "militia": f["serve"]["militia"] = maxi(0, int(f["serve"].get("militia", 0)) - 1)
		if active or drill: f["serve"]["militia"] = int(f["serve"].get("militia", 0)) + 1
		p[4] = wanted
		if not affected.has(int(u.family)): affected.append(int(u.family))
	for fid in affected: Families.reassign(e, families[int(fid)])
	if not affected.is_empty(): Families.match_idle(e)
	if not active: wb["path"] = []; wb["pos"] = town["pos"]

func run(_tree: SceneTree) -> int:
	var world: Dictionary = Game.world
	var day: float = Game.day
	var contract: Dictionary = Game.contract
	var ledger: Dictionary = ArmsTrade.ledger
	var spoils: Dictionary = ArmsTrade.spoils_gold
	var last: Dictionary = ArmsTrade.last_spoils
	var gold_gone: float = TownEcon.gold_gone
	var next_uid := Unit._next_uid
	Game.day = 1.0; Game.contract = {}
	_case(true); _case(false); _verdict_boundary(); _muster_differential()
	check(Unit._next_uid == next_uid, "tick creates no new person identity")
	Game.world = world; Game.day = day; Game.contract = contract
	ArmsTrade.ledger = ledger; ArmsTrade.spoils_gold = spoils; ArmsTrade.last_spoils = last
	TownEcon.gold_gone = gold_gone
	print("Militia tick v011: ", checks, " checks; ", fails, " failures")
	return fails

## Frozen pre-optimization control. Same force ordinal order; each nearby
## threat calls the native muster and performs an uncached threat read.
func _reference_tick(game, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var r2 := Militia.RADIUS * Militia.RADIUS
	var powers := {}
	var raid_towns := Militia._raid_towns(w)
	var cells := {}
	var ids: Array = w["warbands"].keys()
	for order in ids.size():
		var x: Dictionary = w["warbands"][ids[order]]
		if Monsters.suspended_band(x): continue
		if String(x.get("kind", "")) in Militia.NO_THREAT: continue
		var xp: Vector2 = x["pos"]
		var ck := Vector2i(floori(xp.x / Militia.RADIUS), floori(xp.y / Militia.RADIUS))
		if not cells.has(ck): cells[ck] = []
		(cells[ck] as Array).append(order)
	for tid in w.get("militia", {}):
		var mil: Dictionary = w["warbands"].get(String(w["militia"][tid]), {})
		if mil.is_empty() or (mil["units"] as Array).is_empty(): continue
		if TownDefence.defence_policy(game, w["towns"][tid]) == "stand_down":
			TownDefence.set_muster(game, w["towns"][tid], false)
			mil["walls"] = false
			continue
		var tpos: Vector2 = w["towns"][tid]["pos"]
		var held := false
		var nearby: bool = raid_towns.has(tid)
		if nearby: TownDefence.set_muster(game, w["towns"][tid], true)
		var cand := PackedInt32Array()
		var tc := Vector2i(floori(tpos.x / Militia.RADIUS), floori(tpos.y / Militia.RADIUS))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				cand.append_array(PackedInt32Array(cells.get(tc + Vector2i(dx, dy), [])))
		cand.sort()
		for ce in cand:
			var xid: String = ids[ce]
			var x: Dictionary = w["warbands"].get(xid, {})
			if x.is_empty() or (x["pos"] as Vector2).distance_squared_to(tpos) > r2 or not Militia.is_threat(game, mil, x): continue
			nearby = true
			TownDefence.set_muster(game, w["towns"][tid], true)
			if x.has("raid"): continue
			var pa := Militia._tick_power(mil, powers)
			var pb := Militia._tick_power(x, powers)
			if not Militia.sallies(pa, pb):
				held = true
				continue
			Militia._fight(game, tid, mil, x, rng, pa, pb)
			powers.clear()
			raid_towns = Militia._raid_towns(w)
			if (mil["units"] as Array).is_empty(): break
		if not nearby: TownDefence.set_muster(game, w["towns"][tid], false, bool(mil.get("drill_today", false)))
		if held != bool(mil.get("walls", false)):
			mil["walls"] = held
			if held: mil["path"] = [mil["anchor"]]
