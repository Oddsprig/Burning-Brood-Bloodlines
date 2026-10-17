extends RefCounted

var checks := 0
var fails := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)
func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.00001, "%s (got %.6f expected %.6f)" % [message, a, b])

func fixture(culture: String, estate: bool = false, good: String = "grain", phase: int = 0) -> Dictionary:
	var helper = load("res://tests/test_harvest_labour.gd").new()
	var e: Dictionary = helper.fixture(culture, 1, 0, 0)
	e["climate"] = "temperate"; e["crops"] = {"grain": "grain", "fodder": "hay", "flax": "flax", "fruit": "apples"}
	var f: Dictionary = e["fams"][0 if estate else 1]
	f["land"] = {good: 8}; f["ox"] = -1
	if estate: e["fams"][1]["land"] = {}; e["fams"][1]["ox"] = -1
	e["plots"] = {"x": PackedInt32Array([0]), "y": PackedInt32Array([0]), "ac": PackedInt32Array([8]),
		"use": PackedInt32Array([Plots.FIELD]), "own": PackedInt32Array([f["id"]]), "sub": PackedInt32Array([0]),
		"crops": [good], "variety": [""], "soil": ["loam"], "rotation_phase": [posmod(phase - Calendar.year(0.0), 4)], "h": [[]]}
	e["land"] = {good: 8}; e["wacres"] = {good: 0.0}; e["herd"] = {}; e["wherd"] = {}
	Herds.H(e)
	return e

func crop_rules(culture: String, estate: bool) -> void:
	for phase in [0, 3]:
		var e := fixture(culture, estate, "grain", phase)
		var f: Dictionary = e["fams"][0 if estate else 1]
		var expected := 1.0 if phase == 0 else 0.25
		near(Families.need_hands(f, e), expected, "physical active/fallow work has explicit upkeep across cultures and estates")
		for day in [0, 30, 60, 90]:
			e["day"] = float(day)
			var harvest: bool = day in [30, 60] and phase == 0
			near(Families.seasonal_need_hands(f, day, e), expected + (1.0 if harvest else 0.0), "only real active crop cuts add harvest staff")
		near(float(e["plots"]["ac"][0]), 8.0, "labour rule preserves nominal physical acreage")
	for spec in [["fodder", 30], ["flax", 60]]:
		var e := fixture(culture, estate, spec[0])
		var f: Dictionary = e["fams"][0 if estate else 1]
		for day in [30, 60]:
			e["day"] = float(day)
			near(Families.seasonal_need_hands(f, day, e), 2.0 if day == spec[1] else 1.0, "crop-specific harvest calendar counts once")

func herd_rules(culture: String, estate: bool) -> void:
	var e := fixture(culture, estate)
	var f: Dictionary = e["fams"][0 if estate else 1]
	var expected := 0.0
	for spec in [["sheep", 60], ["goats", 50], ["pigs", 40], ["cattle", 25], ["horses", 15], ["donkeys", 20], ["hens", 200], ["oxen", 8]]:
		var h := Herds.new_herd(e, spec[0], "s" if estate else "f", int(f["id"]), 0.0)
		Herds.change(e, h, "y", int(spec[1]), "born", "unit fixture", 0.0)
		expected += 0.5
		near(Families.herd_hands(f, e), expected, "actual young species including hens/oxen each count once")
	var business := {"id": 2, "type": "herder", "owner": f["id"], "closed": false, "kw": 1, "cap": 0, "workers": 0}
	e["biz"].append(business)
	var paid := Herds.new_herd(e, "sheep", "b", 2, 0.0)
	Herds.change(e, paid, "g", 60, "bought", "unit fixture", 0.0)
	near(Families.herd_hands(f, e), expected, "business herd does not also consume family farm labour")
	Herds._herder_caps(e)
	check(int(business["cap"]) == 0, "real keeper covers one hand without duplicate paid job")
	business["kw"] = 0; Herds._herder_caps(e)
	check(int(business["cap"]) == 1, "missing keeper leaves one real funded-eligible place")
	Herds.change(e, paid, "g", -60, "sold", "unit fixture", 0.0)
	Herds._herder_caps(e)
	check(int(business["cap"]) == 0, "empty herd creates no task")

func rotation_repair(culture: String) -> void:
	var e := fixture(culture, false, "grain", 3)
	var f: Dictionary = e["fams"][1]
	Families.reassign(e, f)
	var old_need := Families.need_hands(f, e)
	var old_assigned: float = f["assigned_need"]
	var old_hands := int(f["hands"])
	check(old_hands == 0 and Families.job_total(f) == 1, "fallow upkeep leaves the real adult in one existing hired job")
	var people := Families.people(f)
	var coin: float = f["purse"] + e["biz"][0]["till"]
	# Copying through JSON exercises the same saved scalar/index representations.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(e))
	saved["day"] = 120.0
	var loaded: Dictionary = saved["fams"][1]
	Herds._fix(saved["hd"])
	Families.refresh_worked(saved, loaded)
	check(int(loaded["hands"]) == old_hands and Families.job_total(loaded) == 1, "output refresh preserves actual adult allocation until ordinary matching")
	check(Families.need_hands(loaded, saved) > old_need, "saved fallow rotates to a real crop next year")
	near(float(loaded["assigned_need"]), old_assigned, "output refresh does not pretend to reassign adults")
	check(Families.farm_capacity_stale(saved, loaded), "rotation triggers ordinary allocation repair even after ratio refresh")
	Families.reassign(saved, loaded)
	check(int(loaded["hands"]) == 1 and Families.job_total(loaded) == 0, "ordinary matching moves the same adult from paid job to new active crop work")
	near(float(loaded["assigned_need"]), Families.need_hands(loaded, saved), "ordinary allocation records actual new base requirement")
	check(not Families.farm_capacity_stale(saved, loaded), "ordinary turn repairs rounded capacity and allocation marker")
	check(Families.people(loaded) == people, "rotation/save repair invents no people")
	near(float(loaded["purse"]) + float(saved["biz"][0]["till"]), coin, "rotation/save repair conserves real owner coins")

func animal_roles(culture: String, kind: String) -> void:
	var e := fixture(culture)
	var f: Dictionary = e["fams"][1]
	e.erase("plots"); e["land"] = {}; e["wacres"] = {}; f["land"] = {}
	f["seed"] = 77281
	Persons.generate(e, f, 0.0)
	var h := Herds.new_herd(e, kind, "f", 1, 0.0)
	Herds.change(e, h, "g", int(Herds.kind(kind)["per_hand"]), "bought", "unit fixture", 0.0)
	f["hands"] = 1
	var work := Persons.work(e, f)
	check(work.size() == 1, "animal-only household has one real named adult work role")
	for row in work.values():
		check(String(row["kind"]) == "herd" and String(row["title"]).contains(kind), "poultry/oxen caretaker uses real animal role rather than zero-acre field")
	check(Herds.herders(e, h).size() == 1, "animal-only herders resolve to the household's actual assigned person")

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		for estate in [false, true]: crop_rules(culture, estate); herd_rules(culture, estate)
		rotation_repair(culture)
		for kind in ["hens", "oxen"]: animal_roles(culture, kind)
	print("FARM WORK RULES checks=", checks, " failures=", fails)
	return fails
