extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", text)

func select_shop() -> Array:
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	for tid in ids:
		var t: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(t): continue
		for b in t["econ"]["biz"]:
			if b["type"] != "weaponsmith" or int(b["owner"]) < 0: continue
			var f: Dictionary = t["econ"]["fams"][int(b["owner"])]
			if Families.adults(f) - Families.serving(f) >= 2: return [t, b, f]
	return []

func receipt_losses() -> void:
	var b := {"till": 1000.0}
	EconomyRules.record_receipts(b, 1100.0, 1)
	b["till"] = 1200.0
	EconomyRules.record_receipts(b, 1000.0, 1)
	check(b["net_receipts"] == [-100.0, 200.0], "signed operating loss and gain retained")
	check((float(b["net_receipts"][0]) + float(b["net_receipts"][1])) / 2.0 == 50.0, "average reflects actual net receipts")
	# Funding before the operating window is not counted as a sale.
	b["till"] = 5000.0
	EconomyRules.record_receipts(b, 5000.0, 1)
	check(float(b["net_receipts"][-1]) == 0.0, "existing owner funding does not become a receipt")
	for i in 14: EconomyRules.record_receipts(b, float(b["till"]), 1)
	check(b["net_receipts"].size() == 14 and (b["net_receipts"] as Array).all(func(v): return float(v) == 0), "old profits and losses age out after fourteen staffed days")

func full_market_and_ownerless(rows: Array) -> void:
	var t: Dictionary = rows[0]; var b: Dictionary = rows[1]
	var e: Dictionary = t["econ"]
	var old_owner := int(b["owner"])
	e["prod"] = [int(b["id"])]
	e["arms_short"] = {}; e["arms_tgt"] = {}
	(t["shop"] as Array).clear()
	for i in Businesses.arms_cap(t) + 1: (t["shop"] as Array).append(Item.make("arming_sword", "copper", 2))
	for k in ["heads_copper", "heads_tin"]:
		e["stock"][k] = 100000
		e["price"][k] = float(TownEcon.data()["goods"][k]["price"])
	check(not BowsEcon.tips_wanted(e), "blocked smith fixture has no arrowhead demand")
	b["cap"] = 1; b["workers"] = 1; b["kw"] = 0; b["sick"] = 0
	b["wage"] = 100.0; b["till"] = 0.0; b["owed"] = 0.0
	# A paid place belongs to an actual household, so the debt has a creditor.
	for f in e["fams"]:
		if f["jobs"].has(str(int(b["id"]))): Families.set_job(e, f, int(b["id"]), 0)
	b["workers"] = 0
	Families.set_job(e, rows[2], int(b["id"]), 1)
	b["state"] = "full"; b["fg"] = "arms"; b["net_receipts"] = []
	for i in 14: (b["net_receipts"] as Array).append(500.0)
	b["tools"] = 5; b["tw"] = 0.5
	var tool_stock := int(e["stock"].get("tools", 0))
	var coins := Barge.holdings(Game)
	var rng := RandomNumberGenerator.new(); rng.seed = 45
	for i in 14:
		e["day"] = i + 1
		WageClaims.accrue_day(e, i + 1)
		Businesses.daily(Game, t, e, TownEcon.data(), 0, rng)
	check(b["net_receipts"].size() == 14 and (b["net_receipts"] as Array).all(func(v): return float(v) == 0), "staffed full-market days replace stale profitable history")
	check(String(b["state"]) == "wages" and float(b["owed"]) == 1400.0, "overdue pay remains visible despite market rest")
	check(absf(Barge.holdings(Game) - coins) < 0.001, "rest bookkeeping makes no money or artificial sales")
	check(int(b["tools"]) == 5 and float(b["tw"]) == 0.5 and int(e["stock"].get("tools", 0)) == tool_stock, "blocked resting days do not wear or purchase tools")
	b["owner"] = -1
	Barge.pay_week(e)
	check(float(b["wage"]) == 0 and float(b["revenue_hand"]) == 0, "ownerless production cannot bypass realised wage support")
	Businesses.bid_day(e)
	check(float(b["wage"]) == 0, "daily ownerless bidding observes same production limit")
	b["owner"] = old_owner
	Businesses.bid_day(e)
	check(float(b["wage"]) == 0, "ownership resale does not reset an unsupported offer")
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	check(absf(float(mkt["wage"]) - float(TownEcon.data()["businesses"]["market"]["wage"]) * Barge.wage_mult(e)) < 0.001, "funded public-service pay keeps its table rule")

func funded_family_staff(rows: Array) -> void:
	var t: Dictionary = rows[0]; var b: Dictionary = rows[1]; var f: Dictionary = rows[2]
	var e: Dictionary = t["econ"]
	for fam in e["fams"]:
		for key in fam["jobs"].keys(): Families.set_job(e, fam, int(key), 0)
	for other in e["biz"]:
		other["workers"] = 0
		other["closed"] = other != b
	b["closed"] = false; b["owner"] = int(f["id"])
	b["cap"] = 3; b["till"] = 0.0; b["wage"] = 100.0; b["kw"] = 0
	f["owns"] = [int(b["id"])]; f["keeps"] = []
	# Make the shop-only household physically landless, including its real herd
	# records. Clearing old mirrors alone leaves field/animal work in the town.
	var estate: Dictionary = e["fams"][0]
	for crop in f["land"].keys(): Families.move_land(e, f, estate, String(crop), int(f["land"][crop]))
	for h in Herds.of_owner(e, "f", int(f["id"])):
		var destination := Herds.herd_for(e, 0, String(h["k"]), float(e["day"]))
		for age in Herds.AGES:
			Herds._transfer(e, h, destination, age, int(h[age]), "sold", "bought", "job fixture transfer", "job fixture transfer", float(e["day"]))
	f["serve"] = {}; f["hands"] = 0
	f.erase("cj"); f.erase("hl")
	e["cjcap"] = {}; e["cjused"] = {}
	Businesses.rebuild_open(e)
	Families.reassign(e, f)
	check(int(b["kw"]) == 1 and f["keeps"] == [int(b["id"])], "empty till still has its profit-taking real keeper")
	check(int(b["workers"]) == 0 and int(f["jobs"].get(str(int(b["id"])), 0)) == 0, "extra relatives cannot bypass funded paid hiring")
	b["till"] = 200.0
	Businesses.rebuild_open(e); Families.reassign(e, f)
	check(int(b["workers"]) == 0, "cash committed to retained employee wages cannot fund an additional paid relative")
	b["till"] = float(b["owed"]) + 200.0
	Businesses.rebuild_open(e); Families.reassign(e, f)
	check(int(b["workers"]) == 1, "real uncommitted till funds exactly one additional paid relative")
	var outside: Dictionary = {}
	for other in e["biz"]:
		if other != b and not String(other["type"]) in ["farm", "estate"]:
			outside = other; break
	check(not outside.is_empty(), "outside job fixture exists")
	if outside.is_empty(): return
	outside["closed"] = false; outside["cap"] = 1; outside["workers"] = 0
	outside["owner"] = -1; outside["wage"] = 1000.0; outside["till"] = 2000.0
	Businesses.rebuild_open(e); Families.reassign(e, f)
	check(int(f["jobs"].get(str(int(outside["id"])), 0)) == 1, "paid relatives can choose better funded outside work")
	check(int(b["kw"]) == 1, "outside staff choice does not remove the keeper")
	check(int(b["workers"]) <= 1 and int(outside["workers"]) <= 1, "paid family staffing respects every cash capacity")

func run(_tree: SceneTree) -> int:
	receipt_losses()
	for seed_v in [713, 2026, 8801]:
		Game.new_game(seed_v)
		var rows := select_shop(); check(rows.size() == 3, "generated general producer fixture exists")
		if rows.size() == 3: full_market_and_ownerless(rows); funded_family_staff(rows)
	print("PRODUCER CASH checks=", checks, " failures=", fails)
	return fails
