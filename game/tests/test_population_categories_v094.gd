extends RefCounted
## Native mutation paths around staggered year updates; no world generation.
const Fixtures = preload("res://tests/test_population_economy_controls.gd")
var checks: int = 0
var fails: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL: ", label)

func expected(e: Dictionary, f: Dictionary) -> Array:
	var out: Array = [0, 0, 0, 0]
	var epoch: float = float(f["population_year"]) * People.year_days()
	for key in f["age_bins"]:
		out[Population.bin_category(e, f, str(key), epoch)] += int(f["age_bins"][key])
	for p in f.get("pp", []) + f.get("kp", []):
		if not Persons.AWAY.has(str(p[4])): out[Population.category(p)] += 1
	return out

func counts(f: Dictionary) -> Array:
	return [int(f["m"]), int(f["f"]), int(f["old"]), int(f["kids"])]

func fixture(epoch: int, bins: Dictionary) -> Dictionary:
	var builder = Fixtures.new()
	var e: Dictionary = builder.fixture([4])
	var f: Dictionary = e["fams"][3]
	f["population_year"] = epoch
	f["age_bins"] = bins.duplicate()
	f["pp"] = []; f["kp"] = []
	f["hungry"] = 1  # no births in the zero-duration age-only continuation
	f["purse"] = 0.0
	f["store"] = {"food": 0.0, "drink": 0.0, "wood": 0.0}
	var wanted: Array = expected(e, f)
	for i in 4: f[["m", "f", "old", "kids"][i]] = wanted[i]
	e["pop"] = Census.people(e)
	e["adults"] = 0
	e["homes"] = 0
	for family: Dictionary in e["fams"]:
		e["adults"] += Families.adults(family)
		e["homes"] += int(family["homes"])
	e["day"] = 121.0
	return e

func migration_case(source_epoch: int, destination_epoch: int) -> void:
	var ages: Dictionary = People.ages("human")
	var bins: Dictionary = {"0:-20": 8, "1:-20": 8}
	bins["0:%d" % (1 - int(ages["elder"]))] = 8
	bins["1:%d" % (1 - int(ages["elder"]))] = 8
	bins["0:%d" % (1 - int(ages["adult"]))] = 8
	bins["1:%d" % (1 - int(ages["adult"]))] = 8
	var a: Dictionary = fixture(source_epoch, bins)
	var b: Dictionary = fixture(destination_epoch, bins)
	var f: Dictionary = a["fams"][3]
	var d: Dictionary = b["fams"][3]
	var opening: int = Census.people(a) + Census.people(b)
	var before_coin: float = Fixtures.new().coin(a) + Fixtures.new().coin(b)
	var source: Dictionary = {"id": "a", "name": "Source", "econ": a}
	var destination: Dictionary = {"id": "b", "name": "Destination", "econ": b}
	var moved: int = Migration.move_households(null, source, f, destination, 2, "war", 121.0)
	var label: String = str(source_epoch) + "/" + str(destination_epoch)
	check(moved > 0 and Census.people(a) + Census.people(b) == opening, "migration conserves actual residents " + label)
	check(counts(f) == expected(a, f), "source categories match its own stored year " + label)
	check(counts(d) == expected(b, d), "destination categories match its own stored year " + label)
	check(absf(Fixtures.new().coin(a) + Fixtures.new().coin(b) - before_coin) < 1e-9, "category bookkeeping creates no money " + label)
	# The original scheduled year advance must age each remaining/moved slot once.
	Population.turn(a, f, 121.0, 0.0)
	Population.turn(b, d, 121.0, 0.0)
	check(counts(f) == expected(a, f) and counts(d) == expected(b, d), "normal year turn keeps both rows exact " + label)
	var before_deaths: int = Census.people(a)
	var deaths: int = Census.sum(Census.current(a)["deaths"])
	for key in f["age_bins"].keys():
		if Population.bin_category(a, f, str(key), 121.0) == 2:
			Population.kill_slots(a, f, str(key), int(f["age_bins"][key]), 121.0, "starved")
	check(before_deaths - Census.people(a) == Census.sum(Census.current(a)["deaths"]) - deaths, "every elder mortality slot is one real census death " + label)

func promotion_case(sex: int, epoch: int) -> void:
	var ages: Dictionary = People.ages("human")
	var key: String = "%d:%d" % [sex, 1 - int(ages["adult"])]
	var e: Dictionary = fixture(epoch, {key: 1})
	var f: Dictionary = e["fams"][3]
	var rng := RandomNumberGenerator.new()
	rng.seed = 94301
	# Four existing detailed adults leave an actual spare worker place.
	for i in 4:
		var person: Array = Persons._new(e, f, "human", 0, -30.0 * People.year_days(), 0, rng)
		Persons.pp(f).append(person)
	f["m"] += 4
	e["pop"] += 4
	e["adults"] += 4
	var before: int = Census.people(e)
	var adults: int = int(e["adults"])
	var p: Array = Population.promote(e, f, 121.0, rng)
	check(not p.is_empty() and int(p[2]) == sex, "the actual anonymous young adult is named")
	check(Census.people(e) == before and f["age_bins"].is_empty(), "promotion consumes one slot without adding a person")
	check(counts(f) == expected(e, f), "promoted category is booked once across the year boundary")
	check(int(e["adults"]) == adults + (1 if epoch == 0 else 0), "promotion updates only the newly adult count")

func run(_tree: SceneTree) -> int:
	for source_epoch in [0, 1]:
		for destination_epoch in [0, 1]: migration_case(source_epoch, destination_epoch)
	for sex in [0, 1]:
		for epoch in [0, 1]: promotion_case(sex, epoch)
	print("Population categories v094: ", checks - fails, "/", checks, " checks passed")
	return fails
