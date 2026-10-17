extends RefCounted
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func money(e: Dictionary) -> float:
	var total := float(e["treasury"])
	for f in e["fams"]: total += float(f["purse"])
	for b in e["biz"]: total += float(b["till"])
	return total

func fixture(original: Dictionary, job: String, cap: int, occupied: float, funded: bool) -> void:
	var e: Dictionary = original.duplicate(true)
	var chosen := -1
	for f in e["fams"]:
		if not f.get("estate", false) and not f.get("gone", false) and Families.adults(f) >= 2 and Families.serving(f) == 0:
			chosen = int(f["id"]); break
	check(chosen >= 0, "real civilian household available")
	if chosen < 0: return
	# An isolated town economy with no regular business offer. Existing fractional
	# reservations belong to other short-shift workers and must remain occupied.
	e["plots"] = {}; e.erase("hd"); Herds.H(e)
	e["herd"] = {}; e["land"] = {}; e["wacres"] = {}; e["wherd"] = {}
	for f in e["fams"]:
		for bid in f["jobs"].keys(): Families.set_job(e, f, int(bid), 0)
		Shelter.release_casual(e, f)
		f["owns"] = []; f["keeps"] = []; f["land"] = {}; f["herd"] = {}; f["ox"] = 0; f["farm"] = -1
		f["hands"] = 0; f["idle"] = maxi(0, Families.adults(f) - Families.serving(f))
		f["gone"] = not f.get("estate", false) and int(f["id"]) != chosen
		f["purse"] = 0.0; f["store"] = {"food": 100.0, "drink": 100.0, "wood": 100.0}
		f.erase("child_cj"); f.erase("cjearned")
	for b in e["biz"]:
		b["closed"] = true; b["workers"] = 0; b["kw"] = 0; b["cap"] = 0; b["till"] = 0.0; b["owed"] = 0.0
	Businesses.rebuild_open(e)
	var f: Dictionary = e["fams"][chosen]
	var wage := Barge.casual_wage(e, job)
	e["treasury"] = wage * 100.0 if funded and job == "street_sweeper" else 0.0
	f["purse"] = wage * 100.0 if funded and job == "night_soil_man" else 0.0
	e["cjcap"] = {job: cap}; e["cjused"] = {job: occupied}; e["idle_n"] = int(f["idle"])
	var expected := mini(Families.adults(f), maxi(0, int(floor(float(cap) - occupied + 0.00001)))) if funded else 0
	var before_money := money(e)
	var last := float(f["last"])
	var wage_day: Variant = e.get("wage_day", null)
	var stock: Dictionary = e["stock"].duplicate(true)
	Families.match_idle(e)
	check(int(f.get("cj", {}).get(job, 0)) == expected, "funded casual-only offers reach idle adults")
	check(int(f["idle"]) == Families.adults(f) - expected, "casual matching conserves idle adults")
	check(not Families.assignments_stale(f), "every adult retains exactly one assignment")
	check(absf(float(e["cjused"].get(job, 0)) - occupied - expected) < 0.000001, "fractional occupied shifts remain reserved")
	check(absf(money(e) - before_money) < 0.000001, "matching moves no wages or money")
	check(float(f["last"]) == last and e.get("wage_day", null) == wage_day, "matching never advances paydays or wage accrual")
	check(e["stock"] == stock and f.get("cjearned", {}).is_empty(), "matching neither creates service nor consumes goods")
	var snapshot := JSON.stringify(e)
	Families.match_idle(e)
	check(JSON.stringify(e) == snapshot, "repeated matching with no available full shift is inert")

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"; Game.new_game(2026)
	var seen := {}
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		var culture := String(e["culture"])
		if seen.has(culture): continue
		seen[culture] = true
		for job in ["street_sweeper", "night_soil_man"]:
			for funded in [false, true]:
				for spec in [[1, 0.0], [1, 0.2], [2, 0.2], [0, 0.0]]:
					fixture(e, job, int(spec[0]), float(spec[1]), funded)
	check(seen.size() == TownEcon.data()["cultures"].size(), "all cultures use the same casual matcher")
	print("CASUAL MATCHING checks=%d failures=%d" % [checks, fails])
	return fails
