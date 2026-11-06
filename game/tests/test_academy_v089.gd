extends RefCounted
## SOURCE ONLY / UNRUN. One cached Normal/one-day world, tiny native-register
## fixtures, no campaign-day loop. Runner watchdog: 180 s; aim: under 60 s.

const GROUPS := 8
var fails := 0
var checks := 0
var completed := 0
var base: Dictionary

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v089: ", why)

func near(a: float, b: float) -> bool:
	return absf(a - b) <= 0.000001

## JSON may represent whole counts as floats. Compare exact whole quantities,
## rejecting changed counts and fractions rather than rounding or tolerating them.
func same_counts(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size(): return false
	for good in a:
		if not b.has(good): return false
		if float(a[good]) != float(int(a[good])) or float(b[good]) != float(int(b[good])): return false
		if int(a[good]) != int(b[good]): return false
	return true

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	var path := "user://test_academy_v089_%d.json" % OS.get_process_id()
	check(await DevTools.start_world(tree, path), "native Normal/one-day start world loads")
	if fails > 0: return fails
	base = Game.world
	_rules_and_houses()
	_funding_and_pay()
	_material_controls()
	_budget_controls()
	_hiring()
	_departures_and_successor()
	_trained_move()
	_save_load(path)
	check(completed == GROUPS, "all eight groups completed; an aborted helper cannot pass")
	check(checks >= 100, "the bounded assertion set actually executed")
	check(Time.get_ticks_msec() - started < 180000, "whole test stays within the hard 180 s budget")
	print("ACADEMY v089 groups=", completed, "/", GROUPS, " checks=", checks, " failures=", fails,
		" elapsed_ms=", Time.get_ticks_msec() - started)
	return fails

## Native constructors create two real adults, with stable UIDs and household
## membership. Only this small detached capital is used by each control.
func fixture(fid: String = "middle_kingdom", cash: float = 100000.0) -> Dictionary:
	var fac: Dictionary = base["factions"][fid].duplicate(true)
	var tid := String(fac["capital"])
	var town: Dictionary = base["towns"][tid].duplicate(true)
	var e: Dictionary = town["econ"]
	var culture := String(DB.factions[fid]["culture"])
	e["culture"] = culture
	e["faction"] = fid
	e["identity_scope"] = "test-v089:" + fid
	e["next_pid"] = 1
	e["biz"] = []
	e.erase("academy")
	e.erase("hd")
	# The replacement households own no part of the source capital's plots.
	# Keeping its physical plot book lets reassign create/fund a real farm
	# for the unrelated new family with the same local id.
	e.erase("plots")
	e["lodgings"] = []
	e["cjcap"] = {}
	e["cjused"] = {}
	e["hands"] = 0
	e["idle_n"] = 0
	e["day"] = int(base["towns"][tid]["econ"].get("day", 0)) + 1
	e["treasury"] = 0.0
	e["head"] = {"fam": 1, "name": "Researcher", "title": "Master"}
	e["land"] = {}
	e["herd"] = {}
	var f := Families._blank(1)
	f["name"] = "Trial"
	f["race"] = Academy.faction_race(fid)
	f["cul"] = culture
	f["homes"] = 1
	f["m"] = 1
	f["f"] = 1
	f["purse"] = 1000.125
	f["pp"] = []
	f["kp"] = []
	e["fams"] = [Families.make_estate(town), f]
	TownEcon.recount(e)
	check(float(Families.crop_work(f, e)["base"]) == 0.0 and Families.herd_hands(f, e) == 0.0,
		"detached research household has no inherited plot or livestock work")
	var rng := RandomNumberGenerator.new()
	rng.seed = 89089
	var adult := float(People.ages(String(f["race"]))["adult"])
	for sex in 2:
		f["pp"].append(Persons._new(e, f, String(f["race"]), sex,
			float(e["day"]) - (adult + 20.0 - sex * 5.0) * People.year_days(), 0, rng))
	var market := Businesses._row(e, "market", -1, 0, TownEcon.data())
	e["mkt"] = int(market["id"])
	market["till"] = 3000.75
	Academy.gen_town(town, e)
	var b := Academy.biz_of(e)
	b["till"] = cash
	b["cap"] = 2
	b["skill"] = 2.0
	b["lskill"] = 8.0
	b["personal_training"] = true
	b["research_idle"] = false
	Families.set_job(e, f, int(b["id"]), 2)
	var head: Array = f["pp"][0]
	var staff: Array = f["pp"][1]
	b["lead"] = [1, int(head[0])]
	b["lead_uid"] = String(head[Persons.PERSON_UID])
	var lead_training := Academy._training(head, 8.0)
	lead_training["aptitude"] = 1.0
	var staff_training := Academy._training(staff, 2.0)
	staff_training["aptitude"] = 1.0
	for good in Academy.materials():
		e["stock"][good] = 100
	town["shop"] = []
	town["armory_items"] = []
	var w := base.duplicate()
	w["towns"] = (base["towns"] as Dictionary).duplicate()
	w["towns"][tid] = town
	w["factions"] = {fid: fac}
	fac["towns"] = [tid]
	w["research"] = {}
	Academy.state(w, fid)
	Academy.sync_towns(w, fid)
	Businesses.rebuild_open(e)
	Game.world = w
	Game.day = float(e["day"])
	if Academy.active_lines(w, fid).is_empty():
		Academy._idle_house(e, b)
	return {"w": w, "town": town, "e": e, "b": b, "f": f, "head": head, "staff": staff, "fid": fid, "market": market}

func work(x: Dictionary) -> float:
	var e: Dictionary = x["e"]
	e["day"] = int(e["day"]) + 1
	Game.day = float(e["day"])
	WageClaims.accrue_day(e, int(e["day"]))
	return Academy.day(Game, x["town"], e, x["b"], float(x["b"]["workers"]), x["market"], {})

func points(x: Dictionary) -> float:
	var total := 0.0
	for amount in Academy.state(x["w"], String(x["fid"]))["pts"].values(): total += float(amount)
	return total

func coins(x: Dictionary) -> float:
	var total := float(x["w"]["factions"][x["fid"]]["treasury"]) + float(x["e"]["treasury"])
	for b in x["e"]["biz"]: total += float(b["till"])
	for f in x["e"]["fams"]: total += float(f["purse"])
	return total

func _rules_and_houses() -> void:
	check(TownEcon.data()["goods"].has("charcoal"), "accepted v087 charcoal data is present before v089 tests")
	check(Academy.materials().has("charcoal") and not Academy.materials().has("wood"), "trials require charcoal rather than raw wood")
	check(same_counts({"iron_bars": 1}, {"iron_bars": 1.0}) and not same_counts({"iron_bars": 1}, {"iron_bars": 2})
		and not same_counts({"iron_bars": 1}, {"iron_bars": 1.5}), "material equality accepts JSON number types but rejects changed or fractional counts")
	var covered := {}
	var races := {}
	for fid in base["factions"]:
		var cap: Dictionary = base["towns"].get(String(base["factions"][fid].get("capital", "")), {})
		if not TownEcon.has_econ(cap):
			check(not bool(Academy.report(base, String(fid))["has"]), "faction without an economic capital reports no house: " + String(fid))
			continue
		covered[String(cap["id"])] = true
		races[Academy.faction_race(String(fid))] = true
		var e: Dictionary = cap["econ"]
		var b := Academy.biz_of(e)
		check(not b.is_empty(), "every race retains a capital house: " + String(fid))
		if b.is_empty(): continue
		var houses := 0
		for row in e["biz"]:
			if String(row["type"]) == "academy": houses += 1
		check(houses == 1, "actual economic capital has exactly one state house: " + String(fid))
		check(int(b["owner"]) == -1 and String(b.get("public_funding", "")) == "realm" and int(b.get("kw", 0)) == 0, "house has state ownership and no profit-taking keeper")
		for f in e["fams"]:
			check(not (f["owns"] as Array).has(int(b["id"])), "no private family owns the state Academy")
		check(Academy._staff(e, b).size() == int(b["workers"]), "every paid Academy place is a registered adult")
		if Academy.active_lines(base, String(fid)).is_empty():
			check(int(b["workers"]) == 0 and int(b["cap"]) == 0, "race with no eligible line keeps no paid staff")
	var actual := {}
	for tid in base["towns"]:
		var town: Dictionary = base["towns"][tid]
		if bool(town.get("capital", false)) and TownEcon.has_econ(town): actual[String(tid)] = true
	check(not actual.is_empty() and covered == actual, "every actual economic capital is covered by the faction checks")
	for race in ["human", "orc", "goblin", "dwarf", "moon_elf", "high_elf", "dark_elf"]:
		check(races.has(race), "all settled world races retain capital coverage: " + race)
	for pair in [["middle", "human", "Academy", "Master"], ["northern", "human", "Lorehall", "Loremaster"],
		["eastern", "human", "House of Wisdom", "Hakim"], ["moon_elf", "moon_elf", "Athenaeum", "Sage"],
		["orc", "orc", "Blood Forge", "Forge-Boss"], ["goblin", "goblin", "The Pit", "Pit-Master"], ["dwarf", "dwarf", "Hall of Makers", "Maker-Lord"]]:
		check(Academy.names_of(pair[0], pair[1]) == [pair[2], pair[3]], "culture name and lead title remain data-driven")
	for fid in ["orc_horde", "goblin_warren", "dwarf_holds"]:
		var expected := 100.0 if fid == "dwarf_holds" else 0.0
		var w := {"research": {fid: {"kh": {"steel": 55.0}, "pts": {}, "hist": [], "log": []}}}
		check(Academy.state(w, fid)["kh"]["steel"] == expected, "saved steel obeys immutable racial knowledge")
		check(Academy.kh_after(fid, "steel", 1.0e12) == expected, "even huge point inputs cannot bypass racial steel rules")
		check(Businesses.kh_of({"faction": fid, "fkh": {"steel": 55.0}}, "steel") == expected, "smith query rejects a stale forbidden steel mirror")
	check(Academy.start_kh("middle_kingdom", "steel") == 0.0 and Academy.start_kh("moon_court", "steel") == 0.0, "human and moon elf steel begins at zero")
	check(Academy.race_factor("moon_court", "steel") == 1.25, "elf steel learning factor is 1.25")
	var p0 := float(Academy.R()["p0"])
	check(Academy.kh_after("middle_kingdom", "steel", p0 * 0.9) == 0.0 and Academy.kh_after("moon_court", "steel", p0 * 0.9) > 0.0, "equal accumulated work reaches elf steel sooner without simulating years")
	check(Academy.best_quality(0.0) == -1 and Academy.best_quality(0.01) == 0 and Academy.best_quality(100.0) == 5, "steel gates none, poor, and all six qualities")
	for quality in range(1, 6):
		check(Academy.best_quality(float(quality) * 100.0 / 6.0 + 0.0001) == quality, "each quality boundary is executable")
	var incomplete := {"research": {"middle_kingdom": {"kh": {"steel": 0.0, "bronze": 100.0, "unrelated": 1.0}, "pts": {}, "hist": [], "log": []}}}
	var repaired := Academy.state(incomplete, "middle_kingdom")
	check(repaired["kh"].has("iron") and repaired["pts"].has("steel") and repaired["pts"].has("bronze"), "missing line and points keys initialize independently of dictionary size")
	completed += 1

func _funding_and_pay() -> void:
	var x := fixture("middle_kingdom", 0.0)
	x["w"]["factions"][x["fid"]]["treasury"] = 1000000.125
	var total := coins(x)
	var treasury := float(x["w"]["factions"][x["fid"]]["treasury"])
	Academy.faction_turn(Game, float(x["e"]["day"]))
	var S := Academy.state(x["w"], x["fid"])
	check(float(S["paid"]) > 0.0 and near(float(S["paid"]), treasury - float(x["w"]["factions"][x["fid"]]["treasury"])), "exact state receipt equals the treasury debit")
	check(near(float(x["b"]["till"]), float(S["paid"])) and near(coins(x), total), "funding credits the actual house till and conserves coin")
	var once: Dictionary = x["w"]["research"].duplicate(true)
	var funded := coins(x)
	Academy.faction_turn(Game, float(x["e"]["day"]))
	check(x["w"]["research"] == once and near(coins(x), funded), "duplicate faction turn cannot transfer or study twice")
	var stock: Dictionary = x["e"]["stock"].duplicate()
	var market := float(x["market"]["till"])
	var purse := float(x["f"]["purse"])
	var spent := work(x)
	var wage := float(x["b"]["wage"])
	check(spent > 0.0 and near(float(x["market"]["till"]) - market, spent), "trial purchases credit the market exactly")
	for good in Academy.materials():
		check(int(stock[good]) - int(x["e"]["stock"][good]) == int(x["b"]["research_materials"].get(good, 0)) and int(x["b"]["research_materials"].get(good, 0)) > 0, "every initial trial input has an integer paid source: " + String(good))
	check(near(float(x["f"]["purse"]) - purse, wage * float(Academy.R()["lead_pay"])), "only the real head household receives the supplement")
	check(near(float(x["b"]["owed"]), 2.0 * wage), "native daily claims accrue both registered employees' basic salary")
	WageClaims.pay_family(x["e"], x["f"])
	check(near(float(x["f"]["purse"]) - purse, wage * (2.0 + float(Academy.R()["lead_pay"]))) and near(float(x["b"]["owed"]), 0.0), "native payday credits both salaries from the house, without extra money")
	check(points(x) > 0.0 and near(coins(x), total), "paid work raises faction research with conserved coin")
	var before: Dictionary = x["w"]["research"].duplicate(true)
	var training: Array = x["f"]["pp"].duplicate(true)
	var replay := {"till": float(x["b"]["till"]), "purse": float(x["f"]["purse"]),
		"stock": x["e"]["stock"].duplicate(), "credit": x["b"]["trial_credit"].duplicate()}
	Academy.day(Game, x["town"], x["e"], x["b"], 2.0, x["market"], {})
	check(x["w"]["research"] == before and x["f"]["pp"] == training and float(x["b"]["till"]) == replay["till"] and float(x["f"]["purse"]) == replay["purse"], "replayed day cannot teach, pay the head, or research twice")
	check(same_counts(x["e"]["stock"], replay["stock"]) and x["b"]["trial_credit"] == replay["credit"], "replayed day cannot burn stock or prepaid trial capacity")
	var report_before := {"econ": x["e"].duplicate(true), "state": S.duplicate(true)}
	var report := Academy.report(x["w"], x["fid"])
	check(x["e"] == report_before["econ"] and S == report_before["state"] and (report["roster"] as Array).size() == 2, "read-only report resolves two actual named employees")
	check(float(report["roster"][0]["skill"]) > 8.0 and String(report["roster"][0]["uid"]) == String(x["head"][Persons.PERSON_UID]), "roster reports trained head identity rather than a building average")
	var reported := 0.0
	for line in report["lines"]:
		reported += float(line["pts"])
		check(near(float(line["budget_on"]), float(report["budget"]) * float(line["share"])), "line's budget share is data-driven")
	check(near(reported, points(x)) and (report["lines"] as Array).size() == (Academy.R()["lines"] as Array).size(), "report preserves all existing research data lines and exact points")
	x = fixture("middle_kingdom", 0.0)
	x["w"]["factions"][x["fid"]]["treasury"] = 0.0
	x["w"]["wars"] = [[x["fid"], "orc_horde"]]
	x["e"]["treasury"] = float(Barge.treasury_lines(x["e"])["short"]) + 1000000.0
	var capital_cash := float(x["e"]["treasury"])
	purse = float(x["f"]["purse"])
	total = coins(x)
	Academy.faction_turn(Game, float(x["e"]["day"]))
	var transfer := float(x["w"]["research"][x["fid"]]["paid"])
	check(transfer > 0.0 and near(transfer, capital_cash - float(x["e"]["treasury"])), "capital treasury fallback has an exact recorded payer debit")
	check(near(float(x["f"]["purse"]), purse), "capital funding uses public coin rather than the head's household purse")
	check(near(float(x["b"]["till"]), transfer), "capital funding reaches the actual house till without another payment")
	check(near(coins(x), total), "capital funding conserves total coin across every native wallet")
	check(int(x["f"]["farm"]) == -1 and (x["f"]["owns"] as Array).is_empty(), "research funding cannot acquire a farm from inherited capital plots")
	completed += 1

func _material_controls() -> void:
	for missing in Academy.materials():
		var x := fixture()
		x["e"]["stock"][missing] = 0
		x["b"]["mc"] = {missing: 0.99}
		x["b"]["mgot"] = 1.0
		var before: Array = x["f"]["pp"].duplicate(true)
		var stock: Dictionary = x["e"]["stock"].duplicate()
		check(work(x) == 0.0 and points(x) == 0.0, "missing input stalls trials despite legacy smoothing: " + String(missing))
		check(same_counts(x["e"]["stock"], stock) and x["f"]["pp"] == before, "failed trial buys no unrelated inputs and teaches nobody")
	var x := fixture()
	work(x)
	var bought: Dictionary = x["b"]["trial_credit"].duplicate()
	for good in Academy.materials(): x["e"]["stock"][good] = 0
	var market := float(x["market"]["till"])
	check(work(x) == 0.0 and float(x["b"]["research_out_day"]) > 0.0, "previously paid trial fractions can support a later working day")
	check(x["b"]["trial_credit"] != bought and near(float(x["market"]["till"]), market), "using prepaid fractions neither repurchases nor invents stock")
	work(x)
	check(float(x["b"]["research_out_day"]) > 0.0 and String(x["b"]["why"]) == "materials", "remaining partial supplies proportionally reduce work")
	work(x)
	check(float(x["b"]["research_out_day"]) == 0.0 and String(x["b"]["state"]) == "inputs", "exhausted paid fractions cannot sustain free research")
	completed += 1

func _budget_controls() -> void:
	var x := fixture("middle_kingdom", 0.0)
	x["w"]["factions"][x["fid"]]["treasury"] = 0.0
	x["e"]["treasury"] = 0.0
	var before := [Academy._skill(x["head"], 0.0), Academy._skill(x["staff"], 0.0)]
	var total := coins(x)
	Academy.faction_turn(Game, float(x["e"]["day"]))
	check(float(x["b"]["till"]) == 0.0 and int(x["b"]["workers"]) == 0 and int(x["b"]["cap"]) == 0, "empty state and capital treasuries lay off unfunded staff")
	check(work(x) == 0.0 and points(x) == 0.0 and [Academy._skill(x["head"], 0.0), Academy._skill(x["staff"], 0.0)] == before and near(coins(x), total), "no budget means no output, training, or new wages")
	x = fixture()
	x["e"]["day"] = int(x["e"]["day"]) + 1
	WageClaims.accrue_day(x["e"], int(x["e"]["day"]))
	var owed := float(x["b"]["owed"])
	x["b"]["till"] = owed
	var stock: Dictionary = x["e"]["stock"].duplicate()
	check(Academy.day(Game, x["town"], x["e"], x["b"], 2.0, x["market"], {}) == 0.0 and points(x) == 0.0, "earned claims block unfunded research and the head supplement")
	check(same_counts(x["e"]["stock"], stock) and near(float(x["b"]["owed"]), owed), "trial shortage cannot erase wage claims or consume stock")
	Businesses.books_day(x["e"])
	check(near(float(x["b"]["till"]), owed), "building upkeep cannot spend the scientists' already earned salary")
	WageClaims.pay_family(x["e"], x["f"])
	check(near(float(x["b"]["owed"]), 0.0) and near(float(x["b"]["till"]), 0.0), "reserved claims still settle through native payday")
	x = fixture()
	work(x)
	var earned := float(x["b"]["owed"])
	var paid_till := float(x["b"]["till"])
	var paid_purse := float(x["f"]["purse"])
	var receipts := float(x["f"]["wage_receipts"])
	total = coins(x)
	Academy.state(x["w"], x["fid"])["kh"]["steel"] = 100.0
	Academy.faction_turn(Game, float(x["e"]["day"]))
	check(earned > 0.0 and near(float(x["b"]["till"]), paid_till - earned)
		and near(float(x["f"]["purse"]), paid_purse + earned), "becoming idle settles only the staff's already earned wages")
	check(near(float(x["f"]["wage_receipts"]), receipts + earned) and float(x["b"]["owed"]) == 0.0
		and int(x["b"]["workers"]) == 0 and near(coins(x), total), "idle transition preserves exact wage receipts and total coin")
	receipts = float(x["f"]["wage_receipts"])
	check(work(x) == 0.0 and float(x["f"]["wage_receipts"]) == receipts and float(x["b"]["owed"]) == 0.0,
		"honorary post accrues no salary or supplement on subsequent idle days")
	for fid in ["orc_horde", "goblin_warren", "dwarf_holds"]:
		x = fixture(fid)
		var honorary := String(x["b"]["lead_uid"])
		check(int(x["b"]["workers"]) == 0 and int(x["b"]["cap"]) == 0 and x["f"]["jobs"].is_empty(), "idle native fixture begins with an honorary post and no paid jobs")
		total = coins(x)
		var idle := {"till": float(x["b"]["till"]), "market": float(x["market"]["till"]), "purse": float(x["f"]["purse"]), "stock": x["e"]["stock"].duplicate()}
		Academy.faction_turn(Game, float(x["e"]["day"]))
		Businesses.books_day(x["e"])
		check(int(x["b"]["workers"]) == 0 and int(x["b"]["cap"]) == 0 and Academy.lead_gone(x["e"], x["b"]) == "", "blocked house keeps a real honorary head without employees")
		check(work(x) == 0.0 and points(x) == 0.0 and near(coins(x), total) and float(x["w"]["research"][fid]["paid"]) == 0.0, "idle house makes no purchases, upkeep payment, transfer or steel research")
		check(float(x["b"]["till"]) == idle["till"], "idle house retains its exact saved till")
		check(float(x["market"]["till"]) == idle["market"] and float(x["f"]["purse"]) == idle["purse"], "idle house's individual wallets remain unchanged")
		check(same_counts(x["e"]["stock"], idle["stock"]), "idle house's exact material counts remain unchanged")
		check(String(x["b"]["lead_uid"]) == honorary and not Persons.work(x["e"], x["f"])[int(x["head"][0])].has("biz")
			and float(x["b"]["owed"]) == 0.0, "honorary head retains identity without a salaried assignment or new claims")
	completed += 1

func _hiring() -> void:
	var x := fixture()
	Families.set_job(x["e"], x["f"], int(x["b"]["id"]), 0)
	x["f"]["idle"] = 2
	x["b"]["lead"] = []
	x["b"]["lead_uid"] = ""
	Families.reassign(x["e"], x["f"])
	check(int(x["b"]["workers"]) == 2 and Academy._staff(x["e"], x["b"]).size() == 2, "ordinary household matcher fills funded Academy places with real adults")
	var cohort := Families._blank(2)
	cohort["name"] = "Unregistered pool"
	cohort["cohort"] = true
	cohort["households"] = 20
	cohort["m"] = 20
	cohort["f"] = 20
	cohort["homes"] = 20
	cohort["pp"] = []
	cohort["kp"] = []
	x["e"]["fams"].append(cohort)
	x["b"]["cap"] = 4
	check(Academy.hiring_places(x["e"], cohort, x["b"]) == 0, "an unnamed cohort cannot offer scientists")
	Families.reassign(x["e"], cohort)
	check(int(cohort["jobs"].get(str(int(x["b"]["id"])), 0)) == 0 and int(x["b"]["workers"]) == 2, "real hiring matcher cannot create ghost Academy staff")
	x = fixture()
	# A real legacy keeper plus one employee accounts for the two adults once.
	Families.set_job(x["e"], x["f"], int(x["b"]["id"]), 1)
	x["b"]["owner"] = 1
	x["b"]["kw"] = 1
	x["f"]["owns"] = [int(x["b"]["id"])]
	x["f"]["keeps"] = [float(x["b"]["id"])]
	x["b"]["till"] = 0.0
	x["b"]["wage_claims"] = {"1": 3.125}
	x["b"]["owed_unattributed"] = 0.0
	x["b"]["owed"] = 3.125
	x["f"]["wage_receipts"] = 0.875
	var cash := coins(x)
	Academy.after_load(Game)
	check(int(x["b"]["owner"]) == -1 and int(x["b"]["kw"]) == 0 and (x["f"]["owns"] as Array).is_empty(), "legacy private operator is released from the state house")
	check((x["f"]["keeps"] as Array).is_empty() and not Families.assignments_stale(x["f"]), "after_load reassigns the released keeper exactly once")
	check(Academy._staff(x["e"], x["b"]).size() == 1 and int(x["b"]["workers"]) == 1, "legacy employee is still a real registered adult after operator release")
	check(x["b"]["wage_claims"] == {"1": 3.125} and float(x["b"]["owed"]) == 3.125 and float(x["f"]["wage_receipts"]) == 0.875, "operator correction preserves unfunded earned claims and previous receipts")
	Academy.after_load(Game)
	check(near(coins(x), cash), "state-ownership correction preserves all existing coin")
	check(not Families.assignments_stale(x["f"]) and float(x["b"]["owed"]) == 3.125, "repeated after_load cannot repeat the keeper transition or erase debt")
	for fid in ["orc_horde", "goblin_warren", "dwarf_holds"]:
		x = fixture(fid)
		# Emulate an older saved paid place in a house with no eligible line.
		x["b"]["research_idle"] = false
		x["b"]["cap"] = 1
		Families.set_job(x["e"], x["f"], int(x["b"]["id"]), 1)
		x["f"]["idle"] = 1
		x["b"]["till"] = 0.0
		x["b"]["wage_claims"] = {"1": 3.125}
		x["b"]["owed_unattributed"] = 0.0
		x["b"]["owed"] = 3.125
		var uid := String(x["b"]["lead_uid"])
		Academy.after_load(Game)
		check(int(x["b"]["workers"]) == 0 and int(x["b"]["cap"]) == 0 and not Families.assignments_stale(x["f"]), "blocked saved house releases paid jobs before another wage day: " + fid)
		check(String(x["b"]["lead_uid"]) == uid and Academy.lead_gone(x["e"], x["b"]) == "" and float(x["b"]["owed"]) == 3.125, "loaded idle house retains its honorary identity and outstanding salary debt: " + fid)
	completed += 1

func _departures_and_successor() -> void:
	for cause in ["death", "retirement", "service", "fled", "uid", "keeper", "job"]:
		var x := fixture()
		match cause:
			"death": x["f"]["pp"].erase(x["head"])
			"retirement": x["head"][6] = 1
			"service": x["head"][4] = "army"
			"fled": x["f"]["gone"] = true
			"uid": x["head"][Persons.PERSON_UID] = "a-different-person"
			"job": Families.set_job(x["e"], x["f"], int(x["b"]["id"]), 0)
			"keeper":
				var shop := Businesses._row(x["e"], "weaponsmith", 1, 1, TownEcon.data())
				shop["kw"] = 1
				x["f"]["keeps"] = [int(shop["id"])]
		var purse := float(x["f"]["purse"])
		var stock: Dictionary = x["e"]["stock"].duplicate()
		check(Academy.lead_gone(x["e"], x["b"]) != "", "real head is absent: " + cause)
		check(work(x) == 0.0 and points(x) == 0.0 and near(float(x["f"]["purse"]), purse) and same_counts(x["e"]["stock"], stock), "vacancy blocks supplement, materials, and output: " + cause)
		check((x["b"]["lead"] as Array).is_empty(), "departure clears the designated post rather than substituting another worker")
	var x := fixture()
	work(x)
	var old_output := float(x["b"]["research_out_day"])
	x["head"][4] = "army"
	x["f"]["serve"] = {"army": 1}
	Academy.vacate(x["w"], x["fid"], x["e"], x["b"], "left for service", float(x["e"]["day"]))
	Families.set_job(x["e"], x["f"], int(x["b"]["id"]), 1)
	var trained := Academy._skill(x["staff"], 0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 89
	check(Academy.appoint(x["w"], x["fid"], x["e"], x["b"], float(x["e"]["day"]), rng), "best eligible registered staff succeeds the departing lead")
	check(String(x["b"]["lead_uid"]) == String(x["staff"][Persons.PERSON_UID]) and near(float(x["b"]["lskill"]), trained), "successor keeps personal skill and UID rather than the predecessor's skill")
	work(x)
	check(float(x["b"]["research_out_day"]) > 0.0 and float(x["b"]["research_out_day"]) < old_output, "weaker actual successor causes lower research output")
	x["staff"][4] = "army"
	x["b"]["lead"] = []
	check(not Academy.appoint(x["w"], x["fid"], x["e"], x["b"], float(x["e"]["day"]), rng), "no eligible adult means a genuine vacancy")
	completed += 1

func _trained_move() -> void:
	var x := fixture()
	work(x)
	var woman: Array = x["staff"]
	var uid := String(woman[Persons.PERSON_UID])
	var training: Dictionary = (woman[Persons.RESEARCH] as Dictionary).duplicate()
	var other := Families._blank(2)
	other["name"] = "Other"
	other["race"] = "human"
	other["homes"] = 1
	other["f"] = 1
	other["pp"] = [woman]
	other["kp"] = []
	x["e"]["fams"].append(other)
	Families.identity(x["e"], other)
	x["f"]["pp"].erase(woman)
	x["f"]["f"] = 0
	Families.set_job(x["e"], x["f"], int(x["b"]["id"]), 1)
	Families.set_job(x["e"], other, int(x["b"]["id"]), 1)
	check(Persons.marriages(x["e"], float(x["e"]["day"]), 1) == 1, "native marriage moves the trained adult to her spouse's household")
	var moved := Persons.by_pid(x["f"], int(woman[0]))
	check(not moved.is_empty() and Persons.by_pid(other, int(woman[0])).is_empty(), "there is exactly one resident record after the native move")
	check(String(moved[Persons.PERSON_UID]) == uid and moved[Persons.RESEARCH] == training, "training and aptitude follow the actual person across household membership")
	completed += 1

func _save_load(path: String) -> void:
	Game.world = base
	var fid := "middle_kingdom"
	var town: Dictionary = Game.world["towns"][Game.world["factions"][fid]["capital"]]
	var e: Dictionary = town["econ"]
	var b := Academy.biz_of(e)
	# A one-day start can legitimately have no research employees. Prepare
	# public funding at the real army bill, then a native registered employee
	# if normal appointments/matching still leave this capital vacant.
	e["day"] = int(e["day"]) + 1
	Game.day = float(e["day"])
	var fac: Dictionary = Game.world["factions"][fid]
	fac["treasury"] = maxf(1000000.125, Army.bill(Game, fid) * float(Academy.R()["interest"]["keep_days"]) * 2.0)
	Academy.faction_turn(Game, float(e["day"]))
	var crew := Academy._staff(e, b)
	if crew.is_empty() and int(b["cap"]) > 0:
		var f := Families._blank((e["fams"] as Array).size())
		f["name"] = "Save Researcher"
		f["race"] = Academy.faction_race(fid)
		f["cul"] = String(e["culture"])
		f["homes"] = 1
		f["m"] = 1
		f["pp"] = []
		f["kp"] = []
		e["fams"].append(f)
		var rng := RandomNumberGenerator.new()
		rng.seed = 890890
		var new_person := Persons._new(e, f, String(f["race"]), 0,
			float(e["day"]) - (float(People.ages(String(f["race"]))["adult"]) + 20.0) * People.year_days(), 0, rng)
		f["pp"].append(new_person)
		Families.set_job(e, f, int(b["id"]), 1)
		b["lead"] = [int(f["id"]), int(new_person[0])]
		b["lead_uid"] = String(new_person[Persons.PERSON_UID])
		TownEcon.recount(e)
		crew = Academy._staff(e, b)
	check(not crew.is_empty() and crew.size() == int(b["workers"]), "prepared native capital has real registered staff for the save regression")
	if crew.is_empty(): return
	var person: Array = crew[0][1]
	var employee: Dictionary = crew[0][0]
	var job: Dictionary = Persons.work(e, employee).get(int(person[0]), {})
	check(int(job.get("biz", -1)) == int(b["id"]) and not bool(job.get("keeper", false))
		and String(Persons.g(person, Persons.PERSON_UID, "")) != "", "save subject has a paid native job and persistent person UID")
	e["day"] = int(e["day"]) + 1
	Game.day = float(e["day"])
	WageClaims.accrue_day(e, int(e["day"]))
	var training := Academy._training(person, 3.125)
	training["skill"] = 3.125
	training["aptitude"] = 1.0625
	b["trial_credit"] = {"iron_bars": 0.625, "flux": 0.375, "charcoal": 0.125}
	b["research_day"] = int(e["day"])
	var uid := String(person[Persons.PERSON_UID])
	var before := {"uid": uid, "training": training.duplicate(), "credit": b["trial_credit"].duplicate(),
		"till": float(b["till"]), "owed": float(b["owed"]), "lead": b["lead"].duplicate(), "lead_uid": String(b.get("lead_uid", "")),
		"claims": b["wage_claims"].duplicate(), "receipts": float(employee.get("wage_receipts", 0.0)),
		"stock": e["stock"].duplicate(), "research_day": int(b["research_day"]),
		"state": JSON.parse_string(JSON.stringify(Game.world["research"][fid]))}
	Game.SAVE_PATH = path
	Game.save_game()
	check(Game.load_game(), "real isolated native save/load completes")
	town = Game.world["towns"][Game.world["factions"][fid]["capital"]]
	e = town["econ"]
	b = Academy.biz_of(e)
	var found: Array = []
	var household: Dictionary = {}
	var count := 0
	for f in e["fams"]:
		for p in Persons.pp_read(f):
			if String(Persons.g(p, Persons.PERSON_UID, "")) == uid:
				found = p
				household = f
				count += 1
	check(count == 1 and not found.is_empty(), "saved researcher reloads as exactly one actual person")
	if found.is_empty(): return
	check(found[Persons.RESEARCH] == before["training"] and b["trial_credit"] == before["credit"], "fractional personal training and prepaid inputs survive native serialization")
	check(b["lead"] == before["lead"] and String(b.get("lead_uid", "")) == before["lead_uid"] and int(b["research_day"]) == int(before["research_day"]), "head identity and once-only work guard survive reload")
	check(near(float(b["till"]), float(before["till"])) and near(float(b["owed"]), float(before["owed"])) and Game.world["research"][fid] == before["state"], "loading neither funds the Academy nor changes research or claims")
	check(b["wage_claims"] == before["claims"] and float(household.get("wage_receipts", 0.0)) == before["receipts"]
		and same_counts(e["stock"], before["stock"]), "native reload preserves individual earned claims, receipts and exact material counts")
	job = Persons.work(e, household).get(int(found[0]), {})
	check(int(job.get("biz", -1)) == int(b["id"]) and Academy._staff(e, b).size() == int(b["workers"]), "saved researcher remains a real employee after native load repair")
	var report := Academy.report(Game.world, fid)
	var listed := false
	for row in report["roster"]:
		if String(row["uid"]) == uid:
			listed = float(row["skill"]) == float(before["training"]["skill"])
	check(listed, "loaded native roster reads the saved person's UID and fractional skill")
	var again: Dictionary = Game.world["research"][fid].duplicate(true)
	var cash := float(b["till"])
	Academy.day(Game, town, e, b, float(b["workers"]), e["biz"][int(e["mkt"])], {})
	check(Game.world["research"][fid] == again and near(float(b["till"]), cash), "saved work guard prevents paying or researching again on the loaded day")
	completed += 1
