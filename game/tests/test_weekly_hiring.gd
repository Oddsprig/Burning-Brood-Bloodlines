extends RefCounted

var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func cash(e: Dictionary) -> float:
	var total := float(e["treasury"])
	for f in e["fams"]: total += float(f["purse"])
	for b in e["biz"]: total += float(b["till"])
	return total

func fixture(town: Dictionary, original: Dictionary, funded: bool, reverse_order: bool) -> void:
	# Synthetic land/payroll mix, using actual generated households. Ordinary
	# civilian turns run before this week's public capacities and real funding.
	var e: Dictionary = original.duplicate(true)
	town["econ"] = e
	e["plots"] = {}; e.erase("hd"); Herds.H(e); e["herd"] = {}
	var selected := []
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false) and Families.adults(f) >= 3 and Families.serving(f) == 0:
			selected.append(int(f["id"]))
	check(selected.size() >= 6, "six real civilian households exist")
	if selected.size() < 6: return
	if reverse_order: selected.reverse()
	selected = selected.slice(0, 6)
	for f in e["fams"]:
		for key in f["jobs"].keys(): Families.set_job(e, f, int(key), 0)
		Shelter.release_casual(e, f)
		f["owns"] = []; f["keeps"] = []; f["land"] = {}; f["herd"] = {}; f["farm"] = -1; f["ox"] = 0
		f["hands"] = 0; f["idle"] = maxi(0, Families.adults(f) - Families.serving(f))
		f["gone"] = not f.get("estate", false) and not selected.has(int(f["id"]))
		f["unpaid"] = 0; f["hungry"] = 0; f["debt"] = 0.0; f["purse"] = 100.0
		f["homes"] = 1; f["cond"] = 1.0; f["last"] = 0.0; f["tax_season"] = e["tax"]["season"]
		f["store"] = {"food": 100.0, "drink": 100.0, "wood": 100.0}
		for key in ["hl", "rent", "landlord", "cjearned"]: f.erase(key)
	for b in e["biz"]: b["closed"] = true; b["for_sale"] = false; b["owner"] = 0; b["kw"] = 0
	e["cjcap"] = {}; e["cjused"] = {}; e["stats"]["sales"] = 0.0
	e["head"]["fam"] = selected[0]
	e["day"] = 7; Game.day = 7.0
	WageClaims.accrue_day(e, 7)
	var rng := RandomNumberGenerator.new(); rng.seed = 17263
	for fid in selected: Families.turn(Game, town, e, e["fams"][int(fid)], 7.0, rng)
	for f in e["fams"]: f["purse"] = 0.0
	# The isolated fixture has six occupied homes, not the generated town's
	# former crowd of houses and customers competing for casual places.
	e["homes"] = selected.size(); e["pop"] = 0; e["granary"] = 0
	for fid in selected: e["pop"] += Families.people(e["fams"][int(fid)])
	for good in e["stock"]: e["stock"][good] = 0
	for good in Barge._mint_recipes(e)[0]: e["stock"][good] = float(Barge._mint_recipes(e)[0][good]) * 10.0
	e["treasury"] = float(Barge.treasury_lines(e)["full"]) * 0.9 if funded else 0.0
	# An estate opens from its actual fixture holding; the mint opens from real
	# fixture bars. A family farm offers coins only after its saved obligation.
	var est: Dictionary = e["fams"][0]
	est["land"] = {"grain": 16}; est["ox"] = 2; est["cum"] = (e["cum"] as Dictionary).duplicate(true)
	var estate: Dictionary = e["biz"][int(e["estate_biz"])]
	estate["owner"] = -1; estate["closed"] = false; estate["cap"] = 0; estate["workers"] = 0
	estate["wage"] = 100.0; estate["till"] = 0.0; estate["owed"] = 0.0; estate["owed_unattributed"] = 0.0; estate["wage_claims"] = {}
	var mint := Businesses._row(e, "mint", -1, 0, TownEcon.data())
	mint["till"] = 0.0; e["mint_biz"] = int(mint["id"])
	var farm := Businesses._row(e, "farm", 0, 2, TownEcon.data())
	farm["wage"] = 40.0; farm["owed"] = 14.0; farm["owed_unattributed"] = 14.0; farm["wage_claims"] = {}
	farm["till"] = 174.0 if funded else 14.0
	var last := selected.map(func(fid): return float(e["fams"][int(fid)]["last"]))
	var before := cash(e)
	TownEcon.town_turn(Game, town, 7)
	check(absf(cash(e) - before) < 0.00001, "weekly event moves existing coins only")
	check(int(estate["cap"]) > 0 and int(mint["cap"]) > 0, "ordinary weekly capacities open estate and mint")
	if funded:
		check(int(estate["workers"]) == int(estate["cap"]), "new funded estate jobs fill after civilian turns")
		check(int(mint["workers"]) == int(mint["cap"]), "new funded mint jobs fill after civilian turns")
		check(int(farm["workers"]) == 2, "funded family farm joins the same matching event")
	else:
		check(int(estate["workers"]) == 0 and int(mint["workers"]) == 0 and int(farm["workers"]) == 0, "unfinanced capacities do not become jobs")
	check(float(farm["owed"]) == 14.0, "hiring preserves committed anonymous obligations")
	var public_bill := 0.0; var idle := 0
	for b in e["biz"]:
		if int(b["owner"]) < 0 and not b.get("closed", false): public_bill += int(b["workers"]) * float(b["wage"])
	for fid in selected:
		var f: Dictionary = e["fams"][int(fid)]
		idle += int(f["idle"])
		check(not Families.assignments_stale(f), "weekly matching balances civilian adults")
		check(float(f.get("wage_receipts", 0)) == 0.0, "new hires receive no preceding wages")
	check(absf(float(e["stats"]["town_wages"]) - public_bill) < 0.00001, "reserve bill includes newly matched public hands")
	check(int(e["idle_n"]) == idle, "weekly idle recount sees the completed matching")
	check(last == selected.map(func(fid): return float(e["fams"][int(fid)]["last"])), "weekly matching leaves ordinary paydays unchanged")
	var snapshot := JSON.stringify(e)
	Families.match_idle(e)
	check(JSON.stringify(e) == snapshot, "no genuine remaining offer leaves coins and assignments identical")
	var expected := 0.0
	for b in e["biz"]:
		if not b.get("closed", false): expected += int(b["workers"]) * float(b["wage"])
	WageClaims.accrue_day(e, 8)
	var paid := 0.0
	for fid in selected: paid += float(WageClaims.pay_family(e, e["fams"][int(fid)])[0])
	check(absf(paid - expected) < 0.00001, "following day pays actual new staff wages from funded tills")
	check(absf(cash(e) - before) < 0.00001, "settling worked wages preserves existing coins")
	check(float(farm["owed"]) == 14.0, "paying today's workers preserves older unattributed wages")

func run(_tree: SceneTree) -> int:
	WorldGen.gen_size = "normal"; Game.new_game(2026)
	var seen := {}
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	for tid in ids:
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town): continue
		var culture := String(town["econ"]["culture"])
		if seen.has(culture): continue
		seen[culture] = true
		var original: Dictionary = town["econ"].duplicate(true)
		for funded in [false, true]:
			for reverse_order in [false, true]: fixture(town, original, funded, reverse_order)
	check(seen.size() == TownEcon.data()["cultures"].size(), "every registered economy culture is exercised")
	print("WEEKLY HIRING cultures=", seen.keys(), " checks=", checks, " failures=", fails)
	return fails
