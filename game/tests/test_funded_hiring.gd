extends RefCounted

var checks := 0
var fails := 0
var matching_seed: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func cash_contract() -> void:
	for kind in ["farm", "estate", "carpenter", "market"]:
		var b := {"type": kind, "closed": false, "cap": 4, "workers": 1, "kw": 1, "wage": 100.0, "till": 1000.0, "owed": 0.0}
		check(Businesses.takeable(b) == 3, kind + ": debt-free cash retains the existing two-day offer")
		b["owed"] = 400.0
		check(Businesses.takeable(b) == 2, kind + ": earned wages and the two-day bill of existing staff leave two offers")
		b["owed"] = 700.0
		check(Businesses.takeable(b) == 0, kind + ": committed cash cannot fund another hand")
		b["workers"] = 0
		check(Businesses.takeable(b) == 1, kind + ": partly committed cash supports one real offer")
		# Paying an existing claim changes cash and liabilities equally; it must not change free cash.
		b["till"] = 300.0; b["owed"] = 0.0
		check(Businesses.takeable(b) == 1, kind + ": settling the claim does not release a second use of its coins")
		b["till"] = 1000.0; b["owed"] = 1000.0
		check(Businesses.takeable(b) == 0, kind + ": fully committed till offers no place")
		b["owed"] = 1200.0
		check(Businesses.takeable(b) == 0, kind + ": unfunded older liabilities remain committed")
		b["owed"] = 0.0; b["kw"] = 9
		check(Businesses.takeable(b) == 4, kind + ": profit-taking keepers do not require hired wage reserves")
		b["workers"] = 5
		check(Businesses.takeable(b) == 0, kind + ": overcapacity does not offer places")
		b["workers"] = 0; b["closed"] = true
		check(Businesses.takeable(b) == 0, kind + ": closed business offers no place")
		b["closed"] = false; b["wage"] = 0.0
		check(Businesses.takeable(b) == 0, kind + ": zero wage offers no place")
		b["wage"] = 100.0; b["till"] = -50.0
		check(Businesses.takeable(b) == 0, kind + ": negative cash offers no place")
	# Old saves need not have an owed key before migration.
	check(Businesses.takeable({"closed": false, "cap": 1, "workers": 0, "wage": 100.0, "till": 200.0}) == 1, "missing legacy liability defaults to zero")

func ordinary_matching() -> void:
	for seed_value in [713, 2026, 8801]:
		if matching_seed != 0 and seed_value != matching_seed: continue
		Game.new_game(seed_value)
		var found := false
		for t in Game.world["towns"].values():
			if not TownEcon.has_econ(t): continue
			var e: Dictionary = t["econ"]
			for f in e["fams"]:
				if f.get("gone", false) or f.get("estate", false) or Families.adults(f) != 1 or Families.serving(f) > 0: continue
				for family in e["fams"]:
					for key in family["jobs"].keys(): Families.set_job(e, family, int(key), 0)
				for b in e["biz"]: b["closed"] = true
				var estate: Dictionary = e["fams"][0]
				for crop in f["land"].keys(): Families.move_land(e, f, estate, crop, int(f["land"][crop]))
				# Small stock and any spare oxen are actual records too; a mirror
				# reset would leave this adult responsible for those animals.
				for herd in Herds.of_family(e, int(f["id"])):
					var target := Herds.herd_for(e, 0, String(herd["k"]), float(e["day"]))
					for age in Herds.AGES:
						Herds._transfer(e, herd, target, age, int(herd[age]), "sold", "bought", "controlled fixture transfer", "controlled fixture transfer", float(e["day"]))
				f["hands"] = 0; f["farm"] = -1; f["owns"] = []; f["keeps"] = []
				f["idle"] = 1; f["unpaid"] = 0
				for key in ["hl", "cj", "cjearned"]: f.erase(key)
				e["cjcap"] = {}; e["cjused"] = {}
				var committed := Businesses._row(e, "farm", -1, 2, TownEcon.data())
				committed["wage"] = 200.0; committed["till"] = 1000.0; committed["owed"] = 1000.0
				var funded := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
				funded["wage"] = 100.0; funded["till"] = 200.0
				Businesses.rebuild_open(e)
				Families.reassign(e, f)
				check(int(f["jobs"].get(str(int(funded["id"])), 0)) == 1, "ordinary matching chooses actual free cash over a higher committed offer")
				check(int(committed["workers"]) == 0 and int(funded["workers"]) == 1 and int(f["idle"]) == 0, "matching preserves real staff and fills the funded place")
				check(float(committed["till"]) == 1000.0 and float(committed["owed"]) == 1000.0, "hiring neither spends nor erases old wage money")
				found = true; break
			if found: break
		check(found, "real generated free adult exists for general matching contract")

func owner_reserves() -> void:
	var f := Families._blank(1)
	f["purse"] = 10000.0; f["hands"] = 1; f["lpay"] = 0.0
	var b := {"closed": false, "type": "farm", "cap": 2, "workers": 4, "wage": 100.0, "till": 0.0, "owed": 700.0, "t_paid": 0.0}
	var before := float(f["purse"]) + float(b["till"])
	Businesses.owner_turn({}, f, b)
	check(float(b["till"]) == 3900.0, "farm funds earned wages plus the existing eight-day future reserve of actual staff")
	check(float(b["owed"]) == 700.0, "funding preserves accrued or inherited wage obligations")
	check(float(f["purse"]) + float(b["till"]) == before, "farm funding moves existing household coins only")
	b["till"] = 0.0; f["purse"] = 150.0
	Businesses.owner_turn({}, f, b)
	check(float(b["till"]) == 50.0 and float(f["purse"]) == 100.0, "limited farm savings retain the existing five-coin household floor")
	check(float(b["owed"]) == 700.0 and Businesses.takeable(b) == 0, "insufficient owner savings neither erase debt nor offer funded jobs")
	b["till"] = 0.0; f["purse"] = 80.0
	Businesses.owner_turn({}, f, b)
	check(float(b["till"]) == 0.0 and float(f["purse"]) == 80.0, "poor farm owner cannot create a payroll reserve")
	# Debt-free targets keep the existing reserve, including empty places.
	b["workers"] = 1; b["cap"] = 2; b["owed"] = 0.0; f["purse"] = 10000.0
	Businesses.owner_turn({}, f, b)
	check(float(b["till"]) == 1600.0, "farm keeps its existing debt-free eight-day target for advertised capacity")
	for kind in ["carpenter", "market"]:
		# Each independent trade case starts with its own household funding week.
		f = Families._blank(1)
		b = {"closed": false, "type": kind, "cap": 1, "workers": 1, "wage": 100.0, "till": 21000.0, "owed": 20000.0, "t_paid": 0.0, "spend": 0.0, "state": "idle", "ld": 0}
		f["purse"] = 1000.0
		Businesses.owner_turn({}, f, b)
		check(float(f["purse"]) == 1000.0 and float(b["till"]) == 21000.0, kind + ": earned wages are excluded from the owner's profit withdrawal")
		b["owed"] = 0.0
		Businesses.owner_turn({}, f, b)
		if kind == "carpenter":
			# Working capital is not booked earned profit (businesses.gd owner_turn).
			check(float(f["purse"]) == 1000.0 and float(b["till"]) == 21000.0, kind + ": unearned working capital is not withdrawn as profit")
		else:
			check(float(f["purse"]) > 1000.0 and float(b["till"]) < 21000.0, kind + ": real surplus still pays the owner's existing profit take")
		b["owed"] = 700.0; b["till"] = 700.0; f["purse"] = 1000.0
		before = float(f["purse"]) + float(b["till"])
		Businesses.owner_turn({}, f, b)
		check(float(b["till"]) == 790.0 and float(f["purse"]) == 910.0, kind + ": earned wages and future weekly payroll remain separate within ten percent above the protected floor")
		check(float(b["owed"]) == 700.0 and float(f["purse"]) + float(b["till"]) == before, kind + ": constrained funding retains wages and coins")
		var sibling: Dictionary = b.duplicate(true)
		Businesses.owner_turn({}, f, sibling)
		check(float(sibling["till"]) == 790.0 and float(sibling["owed"]) == 700.0 and float(f["purse"]) == 910.0,
			kind + ": another business cannot reuse the household's exhausted weekly funding room")
		b["till"] = 0.0; f["purse"] = 100.0
		Businesses.owner_turn({}, f, b)
		check(float(b["till"]) == 0.0 and float(f["purse"]) == 100.0, kind + ": poor owner cannot make payroll coins")

func native_carpenter_profit() -> void:
	# Reuse the existing complete material/market/keeper fixture. Earn the draw
	# through its native production and books; never seed p_acc or sale receipts.
	var fixture_script: GDScript = load("res://tests/test_keeper_operating_cash.gd")
	var fixture_test: RefCounted = fixture_script.new()
	var rows: Array = fixture_test.call("fixture", "middle", "carpenter")
	var e: Dictionary = rows[0]
	var b: Dictionary = rows[1]
	var f: Dictionary = rows[2]
	var market: Dictionary = rows[3]
	var cash: float = float(f["purse"]) + float(b["till"]) + float(market["till"])
	fixture_test.call("owner", rows)
	# These are bounded local producer/book calls, not generated campaign days.
	# Keep the fixture's native prices, recipes, capacity, labour and tool wear.
	for production_day: int in range(1, 71):
		fixture_test.call("produce", rows, production_day)
	var profit: float = float(b.get("p_acc", 0.0))
	check(profit > 0.0 and not (e["led"]["made"] as Dictionary).is_empty(), "carpenter earns actual booked profit from paid native output")
	var purse: float = float(f["purse"])
	var till: float = float(b["till"])
	var kept: Array = [float(b["owed"]), int(b["workers"]), int(b["tools"])]
	fixture_test.call("owner", rows)
	check(float(f["purse"]) > purse and float(b["till"]) < till, "carpenter: real earned surplus still pays the owner's profit take")
	var paid: float = float(f["purse"]) - purse
	check(paid > 0.0 and paid <= profit * 0.5 + 0.001 and absf(till - float(b["till"]) - paid) < 0.001, "carpenter draw transfers only available booked profit")
	check(absf(float(f["purse"]) + float(b["till"]) + float(market["till"]) - cash) < 0.001, "native carpenter production, upkeep, funding and draw conserve existing coins")
	check([float(b["owed"]), int(b["workers"]), int(b["tools"])] == kept, "carpenter draw preserves wage debt, actual staff and physical tools")
	purse = float(f["purse"]); till = float(b["till"])
	fixture_test.call("owner", rows)
	check(float(f["purse"]) == purse and float(b["till"]) == till and float(b.get("p_acc", -1.0)) == 0.0, "carpenter cannot draw the same earned profit twice")

func public_funding() -> void:
	Game.new_game(713)
	var t: Dictionary = {}
	var acres_per_hand := int(TownEcon.data()["land"]["acres_per_hand"])
	for candidate in Game.world["towns"].values():
		if TownEcon.has_econ(candidate) and int(candidate["econ"]["land"].get("grain", 0)) >= acres_per_hand * 2:
			t = candidate; break
	check(not t.is_empty(), "generated town with real estate labour exists for ordinary public funding")
	if t.is_empty(): return
	var original: Dictionary = t["econ"]
	for mode in ["earned", "poor", "threshold", "no_debt", "staff_above_cap"]:
		var e: Dictionary = original.duplicate(true)
		t["econ"] = e
		# Isolate this public wage transfer from optional household land purchases,
		# sales tax and material purchases, while running the actual weekly town turn.
		for f in e["fams"]: f["purse"] = 0.0
		for other in e["biz"]:
			other["owner"] = 0; other["for_sale"] = false
		for good in e["stock"]: e["stock"][good] = 0
		e["stats"]["sales"] = 0.0
		var b: Dictionary = e["biz"][int(e["estate_biz"])]
		b["owner"] = -1; b["closed"] = false
		b["wage"] = 100.0
		var est: Dictionary = e["fams"][0]
		# Put existing grain land into the existing estate through its transfer
		# mechanism; starting generated estates need not already hold land.
		var remaining := acres_per_hand * 2
		for source in e["fams"]:
			if source.get("estate", false): continue
			var n := mini(remaining, int(source["land"].get("grain", 0)))
			if n > 0: Families.move_land(e, source, est, "grain", n); remaining -= n
			if remaining <= 0: break
		est["cum"] = (e["cum"] as Dictionary).duplicate(true)
		if mode == "staff_above_cap":
			# Return the real estate property before exercising wages for an
			# incumbent above zero future capacity; mirrors alone are not holdings.
			var recipient: Dictionary = e["fams"][1]
			for crop in est["land"].keys(): Families.move_land(e, est, recipient, crop, int(est["land"][crop]))
			for kind in est["herd"].keys(): Families.move_herd(e, est, recipient, kind, int(est["herd"][kind]))
			b["workers"] = 1
		var need := Families.need_hands(est, e)
		var cap := int(ceil(need - 0.2)) if need > 0.0 else 0
		var future := float(maxi(int(b["workers"]), cap)) * 100.0 * 14.0
		var debt := 0.0 if mode == "no_debt" else 1000000.0
		b["owed"] = debt; b["owed_unattributed"] = debt; b["wage_claims"] = {}
		b["till"] = debt
		e["treasury"] = 0.0 if mode == "poor" else (3.0 * future if mode == "threshold" else 100000000.0)
		var cash := Barge.holdings(Game)
		var paid_offset := float(b.get("t_paid", 0.0))
		TownEcon.town_turn(Game, t, int(e["day"]) + 7)
		var expected := debt if mode in ["poor", "threshold"] else debt + future
		check(absf(float(b["till"]) - expected) < 0.001, mode + ": ordinary public funding separates earned liabilities and the existing fourteen-day target within treasury constraints")
		check(float(b["owed"]) == debt, mode + ": public funding retains accrued or inherited liability")
		check(absf(float(b.get("t_paid", 0.0)) - paid_offset + expected - debt) < 0.001, mode + ": treasury funding is excluded from operating profit")
		check(absf(Barge.holdings(Game) - cash) < 0.001, mode + ": the ordinary town turn conserves every existing coin")
		t["econ"] = original

func run(_tree: SceneTree) -> int:
	var selected_case: String = "all"
	var selected_seed: String = "all"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--funded-hiring-case="): selected_case = arg.trim_prefix("--funded-hiring-case=")
		if arg.begins_with("--funded-hiring-seed="): selected_seed = arg.trim_prefix("--funded-hiring-seed=")
	var valid_selection: bool = selected_case in ["all", "cash", "owners", "matching", "public"] and selected_seed in ["all", "713", "2026", "8801"] and (selected_seed == "all" or selected_case == "matching")
	check(valid_selection, "funded-hiring selector names an existing case and matching seed")
	if not valid_selection: return fails
	matching_seed = 0 if selected_seed == "all" else int(selected_seed)
	if selected_case in ["all", "cash"]: cash_contract()
	if selected_case in ["all", "owners"]:
		owner_reserves()
		native_carpenter_profit()
	if selected_case in ["all", "matching"]: ordinary_matching()
	if selected_case in ["all", "public"]: public_funding()
	print("FUNDED HIRING case=", selected_case, " seed=", selected_seed, " checks=", checks, " failures=", fails)
	return fails
