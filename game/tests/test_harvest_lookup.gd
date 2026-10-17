extends RefCounted
## Differential sequences use the frozen shipped v0.033 implementation as the
## output oracle, including authoritative lots, cash, reserves and family hv.

var checks := 0
var fails := 0
var old = load("res://tests/fixtures/harvest_claims_v033.gd")
var current = load("res://campaign/harvest_claims.gd")

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

func same_state(a: Dictionary, b: Dictionary) -> bool:
	# The unsorted form also preserves dictionary insertion order, which can
	# affect future iteration. Arrays and exact scalar values must agree too.
	return a == b and JSON.stringify(a, "", false, true) == JSON.stringify(b, "", false, true)

func fixture(n: int, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var spec := []
	for _i in n: spec.append([rng.randi_range(0, 8), rng.randf()])
	var e: Dictionary = load("res://tests/test_harvest_ownership.gd").new().fixture("middle", spec)
	for f in e["fams"]:
		f["m"] = rng.randi_range(0, 4); f["f"] = rng.randi_range(0, 3)
		f["kids"] = rng.randi_range(0, 5); f["old"] = rng.randi_range(0, 2)
		f["k1014"] = rng.randi_range(0, int(f["kids"])); f["k1014_n"] = f["kids"]; f["k1014_d"] = e["day"]
		f["store"]["food"] = rng.randf_range(-0.25, float(EconGen.YEAR_DAYS) * 1.5)
		f["hv"] = rng.randf_range(0.0, 60.0)
	e["barn"] = {"grain": 125, "fruit": 93, "fodder": 47}
	old.ensure(e)
	for day in 24:
		for good in ["grain", "fruit", "fodder"]:
			var owners := {}
			for id in range(1, n + 1):
				if rng.randf() < 0.35: owners["f:%d" % id] = rng.randf_range(0.01, 5.0)
			if day % 4 == 0: owners["?"] = 0.125
			if day % 7 == 0: owners["b:0"] = 0.5
			old.add(e, good, rng.randi_range(1, 9), owners, day, "harvest" if day % 2 == 0 else "herd")
	return e

func pair(a: Dictionary, b: Dictionary, method: String, args: Array, context: String) -> void:
	var aa := [a]; aa.append_array(args)
	var bb := [b]; bb.append_array(args)
	var x = old.callv(method, aa)
	var y = current.callv(method, bb)
	check(x == y, context + ": return agrees with shipped baseline")
	check(same_state(a, b), context + ": complete authoritative economy and saved output agree exactly")

func adversarial(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var a := fixture(rng.randi_range(2, 16), seed_value)
	var b := a.duplicate(true)
	for step in 180:
		var good: String = ["grain", "fruit", "fodder"][rng.randi_range(0, 2)]
		var fid := rng.randi_range(1, a["fams"].size() - 1)
		var who := "f:%d" % fid
		var context := "seed %d step %d" % [seed_value, step]
		match step % 15:
			0:
				for e in [a, b]: e["fams"][fid]["store"]["food"] = float(step % (EconGen.YEAR_DAYS + 1))
				pair(a, b, "reserve_all", [], context)
			1:
				pair(a, b, "add", [good, rng.randi_range(1, 15), {who: 0.125, "f:0": 0.25, "?": 0.5}, rng.randi_range(-10, 80), "herd"], context)
			2:
				pair(a, b, "take", [good, rng.randi_range(0, 12), true, ""], context)
			3:
				pair(a, b, "take", [good, rng.randi_range(0, 12), false, who], context)
			4:
				# Family arguments must refer to their own copy, not a shared input.
				var x = old.keep_food(a, a["fams"][fid], 3, 2.0)
				var y = current.keep_food(b, b["fams"][fid], 3, 2.0)
				check(x == y and same_state(a, b), context + ": own-food removal matches baseline")
			5:
				pair(a, b, "transfer_units", [good, who, {"f:0": 0.25, "?": 0.5, who: 0.125}, 7.125], context)
			6:
				pair(a, b, "lose", [good, rng.randi_range(0, 5)], context)
			7:
				old.reserve_food(a, a["fams"][fid]); current.reserve_food(b, b["fams"][fid])
				check(same_state(a, b), context + ": independent family update matches baseline")
			8:
				pair(a, b, "credit", [{who: 0.25, "f:0": 0.125, "?": 0.5}, 3.75], context)
			9:
				var x = old.collect(a, a["fams"][fid], 0.75)
				var y = current.collect(b, b["fams"][fid], 0.75)
				check(x == y and same_state(a, b), context + ": backed cash collection matches baseline")
			10:
				for e in [a, b]: e["fams"][fid]["gone"] = step % 2 == 0
				old.depart(a, a["fams"][fid]); current.depart(b, b["fams"][fid])
				check(same_state(a, b), context + ": departure reserve release matches baseline")
			11:
				pair(a, b, "transfer", [who, "f:0"], context)
			12:
				var amount := rng.randf_range(0.0, 2.0)
				var previous := float(a["carry"].get("h_" + good, 0.0))
				var gross := int(floor(previous + amount))
				for e in [a, b]: e["carry"]["h_" + good] = previous + amount - float(gross)
				pair(a, b, "harvest", [good, "h_" + good, {who: 0.375, "f:0": 0.625}, amount, gross, int(gross / 2), previous, step], context)
			13:
				# Actual JSON round-trip changes identity and numeric representation.
				a = JSON.parse_string(JSON.stringify(a)); b = JSON.parse_string(JSON.stringify(b))
				pair(a, b, "after_load", [], context)
			14:
				pair(a, b, "reserve_all", [], context)
				pair(a, b, "reserve_all", [], context + " repeated")

func broken_backing() -> void:
	var a := fixture(8, 551)
	# Physical losses and legacy malformed cached totals must reconcile through
	# the shipped loader, without inventing stock or old producer identities.
	a["barn"]["grain"] = 17; a["barn"]["fruit"] = 1000
	a["harvest_book"]["balances"] = {"fabricated": {"grain": [99999.0, 88888.0]}}
	a["harvest_book"]["lots"]["grain"].append({"day": -100, "shares": {"?": 3.25, "f:1": -0.5}, "reserve": {"f:1": 12.0}})
	a["harvest_book"]["lots"]["fruit"].append("invalid saved row")
	var b := a.duplicate(true)
	pair(a, b, "after_load", [], "damaged backing")
	pair(a, b, "reserve_all", [], "recovered backing")
	# Reserve-only legacy entries also exercise direct reserve_all before repair.
	for e in [a, b]:
		e["harvest_book"]["lots"]["grain"].append({"day": 1000, "source": "legacy", "shares": {"?": 1.0}, "reserve": {"f:7": 0.5}})
		if not e["harvest_book"]["balances"].has("f:7"): e["harvest_book"]["balances"]["f:7"] = {}
		e["harvest_book"]["balances"]["f:7"]["grain"] = [0.0, 0.5]
	pair(a, b, "reserve_all", [], "reserve-only old entry")

func duplicate_and_epsilon() -> void:
	var a := fixture(3, 884)
	a["fams"][2]["id"] = a["fams"][1]["id"]
	a["fams"][1]["store"]["food"] = 0.0
	a["fams"][2]["store"]["food"] = float(EconGen.YEAR_DAYS)
	var b := a.duplicate(true)
	pair(a, b, "reserve_all", [], "duplicate saved family id releases earlier owner's reservation")
	a = fixture(3, 995)
	for e_good in ["grain", "fruit"]:
		old.lose(a, e_good, int(a["barn"].get(e_good, 0)))
		for day in 11:
			old._lot(a, e_good, {"f:1": old.EPS * 0.7, "?": 1.0}, day, "epsilon")
			a["barn"][e_good] = int(a["barn"].get(e_good, 0)) + 1
		old._lot(a, e_good, {"f:1": old.EPS * 2.0, "?": 1.0}, 99, "epsilon")
		a["fams"][1]["store"]["food"] = 0.0
	b = a.duplicate(true)
	pair(a, b, "reserve_all", [], "subepsilon row capacities remain untouched")

func cleanup_predicate() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 668034
	for sample in 500:
		var shares := {}
		for id in rng.randi_range(0, 180):
			shares["f:%d" % id] = [-3.0, 0.0, old.EPS * 0.01, old.EPS * 0.7, old.EPS, old.EPS * 1.01, 0.375][rng.randi_range(0, 6)]
		cleanup_case(shares, "finite EPS/negative sample%d" % sample, true)
	# A live finite producer must not hide a later malformed NaN. Neither the
	# baseline nor optimized cleanup may silently retain that damaged lot.
	for values in [[NAN], [1.0, NAN], [NAN, 1.0], [INF], [-INF], [1.0, -INF]]:
		var shares := {}
		for id in values.size(): shares[str(id)] = values[id]
		cleanup_case(shares, "nonfinite shares %s" % str(values), false)
	for key in ["?", "f:", "f:0", "f:1", "f:-1", "f:+3", "f:0004", "f:1.0", "f:2147483649", "f:9223372036854775807", "b:0", "d:town:2"]:
		check(current._family_id(key) == old._family_id(key), "family owner decoding preserves legacy key %s" % key)

func cleanup_case(shares: Dictionary, label: String, finite: bool) -> void:
	# A zero-unit withdrawal still performs the original cleanup of already
	# empty/damaged rows. Exercise that observable public API behavior directly.
	var a := {"barn": {"grain": 1}, "fams": [], "harvest_book": {"version": 1,
		"lots": {"grain": [{"day": 1, "source": "legacy", "shares": shares, "reserve": {}}]},
		"carry": {}, "balances": {}, "cash": {}, "legacy_food": {}, "unattributed_cash": 0.0}}
	var b := a.duplicate(true)
	var x = old.take(a, "grain", 0, false)
	var y = current.take(b, "grain", 0, false)
	check(x == y and a == b, "zero-unit withdrawal preserves complete cleanup behavior: " + label)
	if finite: check(same_state(a, b), "empty-row cleanup preserves exact saved output: " + label)

func key_ordering() -> void:
	var a := fixture(13, 813)
	for good in ["grain", "fruit"]: old.lose(a, good, int(a["barn"].get(good, 0)))
	var weights := {}
	var family_order := []
	for f in a["fams"]:
		if f.get("estate", false): continue
		f["m"] = 4; f["store"]["food"] = 0.0
		var key := "f:%d" % int(f["id"])
		weights[key] = 1.0; family_order.append(key)
	old.harvest(a, "grain", "h_grain", weights, 13.0, 13, 0, 0.0, 100)
	var b := a.duplicate(true)
	check(a["harvest_book"]["lots"]["grain"][0]["shares"].keys() != family_order, "dated batch's lexical producer order differs from family order")
	pair(a, b, "reserve_all", [], "reserve insertion order")
	check(a["harvest_book"]["balances"].keys() == b["harvest_book"]["balances"].keys(), "balance insertion order is preserved")
	check(a["harvest_book"]["lots"]["grain"][0]["reserve"].keys() == b["harvest_book"]["lots"]["grain"][0]["reserve"].keys(), "reserve key insertion order agrees with baseline")
	check(b["harvest_book"]["lots"]["grain"][0]["reserve"].keys() == family_order, "new reserve keys follow original family iteration")

func missing_book() -> void:
	var a := {"day": 100.0, "culture": "middle", "fams": [{"id": 1, "kids": 2, "kp": [], "k1014_d": 0.0}]}
	var b := a.duplicate(true)
	pair(a, b, "reserve_all", [], "missing barn/book stays inert without touching child caches or incomplete family stores")

func malformed_ids() -> void:
	var a := fixture(3, 414)
	for good in ["grain", "fruit"]: old.lose(a, good, int(a["barn"].get(good, 0)))
	a["fams"] = []
	var weights := {}
	for id in [-4, 19, 2, 1]:
		var f := Families._blank(id); f["m"] = 1; f["store"]["food"] = 0.0
		a["fams"].append(f); weights["f:%d" % id] = 1.0
	for good in ["grain", "fruit"]: old.harvest(a, good, "h_" + good, weights, 8.0, 8, 0, 0.0, 101)
	var b := a.duplicate(true)
	pair(a, b, "reserve_all", [], "distinct negative/out-of-range/reordered saved household IDs")
	for e in [a, b]: e["fams"][1]["store"]["food"] = float(EconGen.YEAR_DAYS)
	pair(a, b, "reserve_all", [], "malformed saved ID reserve release preserves existing array-index hv behavior")

func run(_tree: SceneTree) -> int:
	for seed_value in [17, 2026, 31034, 44001, 71913, 99000]: adversarial(seed_value)
	broken_backing()
	duplicate_and_epsilon()
	cleanup_predicate()
	key_ordering()
	missing_book()
	malformed_ids()
	print("HARVEST LOOKUP DIFFERENTIAL checks=", checks, " failures=", fails)
	return fails
