extends RefCounted
var checks := 0
var fails := 0
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL ", text)

func fixture(culture: String) -> Array:
	var D := TownEcon.data()
	var e := {"culture": culture, "stock": {}, "price": {}, "stats": {"sales": 0.0}, "led": {"used": {}, "made": {}}}
	for g in D["goods"]:
		e["price"][g] = float(D["goods"][g]["price"])
		e["stock"][g] = 0
	for g in D["cultures"][culture]["home"]["materials"]: e["stock"][g] = 10000
	var b := {"type": "builder", "state": "busy", "why": "", "till": 100000.0, "carry": 0.99, "oc": {}, "owed": 321.0}
	var m := {"till": 100000.0, "spend": 0.0}
	return [e, b, m]

func material_cost(e: Dictionary) -> float:
	var cost := 0.0
	for g in TownEcon.data()["cultures"][e["culture"]]["home"]["materials"]:
		cost += float(TownEcon.data()["cultures"][e["culture"]]["home"]["materials"][g]) * float(e["price"][g])
	return cost

func make(e: Dictionary, b: Dictionary, m: Dictionary, hands: float = 1.0) -> void:
	var D := TownEcon.data()
	Businesses._recipes(e, D, b, D["businesses"]["builder"], hands, 1.0, 1.0, m, float(D["market"]["buy_share"]), {})

func daily_and_buyer() -> void:
	Game.new_game(2026)
	var seen := {}
	var rng := RandomNumberGenerator.new(); rng.seed = 283
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		var culture := String(e["culture"])
		if seen.has(culture): continue
		var b: Dictionary = {}
		for candidate in e["biz"]:
			if candidate["type"] == "builder": b = candidate; break
		if b.is_empty(): continue
		seen[culture] = true
		var D := TownEcon.data()
		var m: Dictionary = e["biz"][int(e["mkt"])]
		var mats: Dictionary = D["cultures"][culture]["home"]["materials"]
		for g in mats: e["stock"][g] = 10000
		e["stock"]["home"] = 0; e["stock"]["tools"] = 0
		e["_aimrest"] = {}; e["specialties"] = []; e["prod"] = [int(b["id"])]
		var cost := material_cost(e)
		var quote := cost * 2.0
		e["price"]["home"] = quote / float(D["market"]["buy_share"])
		b["closed"] = false; b["workers"] = 0; b["kw"] = 1; b["wage"] = 100.0
		b["sick"] = 0; b["tools"] = 1; b["tw"] = 0.0; b["carry"] = 0.99
		b["state"] = "busy"; b["oc"] = {}; b["owed"] = 321.0; b["net_receipts"] = []
		b["till"] = cost * 2.0; m["till"] = quote * 2.0
		var coins := Barge.holdings(Game)
		Businesses.daily(Game, t, e, D, 0, rng)
		check(int(e["stock"]["home"]) == 1 and b["net_receipts"].size() == 1 and absf(float(b["net_receipts"][0]) - quote + cost) < 0.01, culture + ": ordinary production records builder's signed actual net receipt")
		check(absf(Barge.holdings(Game) - coins) < 0.01 and float(b["owed"]) == 321.0, culture + ": daily keeper production conserves coin and prior staff debt")
		var buyer: Dictionary = e["fams"][1]
		buyer["purse"] = 1000000.0
		var bp := float(b["till"]); var mp := float(m["till"]); var fp := float(buyer["purse"])
		var homes := int(buyer["homes"])
		coins = Barge.holdings(Game)
		check(TownEcon.family_buy(e, buyer, "home", 1) == 1 and int(buyer["homes"]) == homes + 1 and int(e["stock"]["home"]) == 0, culture + ": existing household order takes one paid market home")
		var retail := float(e["price"]["home"]) * TownEcon.markup()
		check(absf(fp - float(buyer["purse"]) - retail) < 0.01 and absf(float(m["till"]) - mp - retail) < 0.01 and float(b["till"]) == bp and absf(Barge.holdings(Game) - coins) < 0.01, culture + ": buyer pays market once after its earlier builder payment")
		# A saturated inventory can legitimately leave the keeper idle and old debt outstanding.
		e["stock"]["home"] = 2; b["till"] = 0.0; e["need"]["home"] = 10.0
		for i in 14: Businesses.daily(Game, t, e, D, 0, rng)
		check(b["state"] == "full" and (b["net_receipts"] as Array).all(func(v): return float(v) == 0) and float(b["owed"]) == 321.0 and Businesses.takeable(b) == 0, culture + ": full-market idle observation and old debt stay visible without invented sales")
	check(seen.size() >= 5, "ordinary production and purchase covered multiple generated cultures")

func run(_tree: SceneTree) -> int:
	for culture in TownEcon.data()["cultures"]:
		var rows := fixture(culture)
		var e: Dictionary = rows[0]; var b: Dictionary = rows[1]; var m: Dictionary = rows[2]
		var mats: Dictionary = TownEcon.data()["cultures"][culture]["home"]["materials"]
		var cost := material_cost(e)
		b["till"] = cost * 0.05
		var stock_before: Dictionary = e["stock"].duplicate()
		var coins := float(b["till"]) + float(m["till"])
		make(e, b, m)
		check(int(e["stock"]["home"]) == 0 and e["stock"] == stock_before, culture + ": partial cash cannot consume unpaid materials or complete a house")
		check(absf(float(b["till"]) + float(m["till"]) - coins) < 0.001 and float(b["owed"]) == 321.0, culture + ": blocked completion preserves money and old debt")
		# Real funding allows the saved work to finish later and transfers the full material and home quotes.
		b["till"] = cost * 2.0
		var bp := float(b["till"]); var mp := float(m["till"])
		make(e, b, m)
		var quote := float(e["price"]["home"]) * float(TownEcon.data()["market"]["buy_share"])
		check(int(e["stock"]["home"]) == 1, culture + ": funded saved work completes one physical home")
		check(absf(float(b["till"]) - bp - quote + cost) < 0.001 and absf(float(m["till"]) - mp + quote - cost) < 0.001, culture + ": builder receives the full quoted market payment after paying all inputs")
		for g in mats: check(int(stock_before[g]) - int(e["stock"][g]) == int(mats[g]), culture + ": completed home consumes exact " + g)
		rows = fixture(culture); e = rows[0]; b = rows[1]; m = rows[2]
		for g in mats: e["stock"][g] = int(float(mats[g]) * 1.5)
		stock_before = e["stock"].duplicate()
		make(e, b, m, 100.0)
		check(int(e["stock"]["home"]) == 1, culture + ": saved work cannot finish a second home without its full materials")
		for g in mats: check(int(stock_before[g]) - int(e["stock"][g]) == int(mats[g]), culture + ": scarce-material completion pays and consumes exactly one batch of " + g)
		rows = fixture(culture); e = rows[0]; b = rows[1]; m = rows[2]
		e["price"]["home"] = cost * 10.0 / float(TownEcon.data()["market"]["buy_share"])
		m["till"] = cost * 0.3
		stock_before = e["stock"].duplicate(); bp = float(b["till"]); mp = float(m["till"])
		make(e, b, m)
		check(int(e["stock"]["home"]) == 0 and e["stock"] == stock_before and float(b["till"]) == bp and float(m["till"]) == mp, culture + ": a market unable to pay the whole quote cannot take a discounted completed home")
	daily_and_buyer()
	print("BUILDER PAYMENTS checks=", checks, " failures=", fails)
	return fails
