extends RefCounted
## Headless: one DevTools fixture, native spawn/pay/arrival paths, no campaign days simulated.
## godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_caravan_margins_v048.gd --watchdog=60
var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL caravan048: ", message)

func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.001, "%s (%.6f vs %.6f)" % [message, a, b])

func market(t: Dictionary) -> Dictionary:
	return t["econ"]["biz"][int(t["econ"]["mkt"])]

func family_coin(t: Dictionary) -> float:
	var total := 0.0
	for f in t["econ"]["fams"]: total += float(f["purse"])
	return total

func item_uids(w: Dictionary) -> Array:
	var ids := []
	for t in w["towns"].values():
		for it in t.get("shop", []): ids.append(str(it.uid))
		for it in t.get("armory_items", []): ids.append(str(it.uid))
	for wb in w["warbands"].values():
		if wb.get("kind", "") == "caravan":
			for it in wb.get("cargo", {}).get("items", []): ids.append(str(it.uid))
	for it in Game.stash: ids.append(str(it.uid))
	ids.sort()
	return ids

func goods_total(o: Dictionary, d: Dictionary, good: String = "linen") -> int:
	var n := TownEcon.town_total(o["econ"], good) + TownEcon.town_total(d["econ"], good)
	for wb in Game.world["warbands"].values():
		if wb.get("kind", "") == "caravan":
			n += int(wb.get("cargo", {}).get("goods", {}).get(good, 0))
	return n

func snapshot(o: Dictionary, d: Dictionary) -> String:
	return JSON.stringify([o["econ"]["stock"], d["econ"]["stock"], o["econ"]["stats"], d["econ"]["stats"],
		market(o)["till"], market(d)["till"], o["econ"]["treasury"], d["econ"]["treasury"],
		o["shop"].map(func(it): return it.uid), d["shop"].map(func(it): return it.uid)])

func pair(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t) or Monsters.is_monster_faction(String(t["faction"])): continue
		if not RecTown._caravans_of(String(tid)).is_empty(): continue
		var spare := 0
		for f in t["econ"]["fams"]:
			if not f.get("gone", false) and not f.has("estate"): spare += maxi(0, Population.spare(f))
		if spare < ArmsTrade.max_guards(t) + People.DRIVERS + 4: continue
		for link in Caravans.trade_partners(w, t):
			var d: Dictionary = w["towns"][link["id"]]
			if TownEcon.has_econ(d) and d["faction"] == t["faction"]:
				return [t, d, link]
	return []

## Configure adversarial prices and liquidity before the conservation boundary.
## Existing Items stay in native holders; crew identities stay native.
func configure(o: Dictionary, d: Dictionary) -> void:
	for t in [o, d]:
		var e: Dictionary = t["econ"]
		for g in Goods.ids(): e["need"][g] = float(e["stock"].get(g, 0)) + 100.0
		e["arms_short"] = {}
		var arms := ArmsTrade.armory(t)
		for it in t["shop"]:
			if ArmsTrade.cls(it.tid) != "": arms.append(it)
			else: Game.stash.append(it)
		t["shop"] = []
		# Clothing is outside this fixture's guard-kit transfers and cargo purchases.
		for it in arms.duplicate():
			if ArmsTrade.cls(it.tid) == "":
				arms.erase(it)
				Game.stash.append(it)
		# No guard-quiver purchase in this isolated trade ledger.
		for g in DB.arrows:
			e["barn"][g] = int(e["barn"].get(g, 0)) + int(e["stock"].get(g, 0))
			e["stock"][g] = 0
		e["treasury"] = 50000.0
		market(t)["till"] = 1000000.0
	o["econ"]["stock"]["linen"] = 6000
	o["econ"]["need"]["linen"] = 10.0
	o["econ"]["price"]["linen"] = 10.0
	d["econ"]["stock"]["linen"] = 0
	d["econ"]["need"]["linen"] = 1000.0
	d["econ"]["price"]["linen"] = 13.0

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start_world loads")
		return fails
	var w: Dictionary = Game.world
	var towns := pair(w)
	check(towns.size() == 3 and Caravans.count(w) < Caravans.max_caravans(w), "fixture has a staffed road pair and a caravan slot")
	if towns.size() != 3: return fails
	var o: Dictionary = towns[0]; var d: Dictionary = towns[1]
	o["road_links"] = [towns[2]]
	w["work"] = []
	configure(o, d)
	var rng := RandomNumberGenerator.new(); rng.seed = 48
	var state := rng.state
	var game_state: int = Game.rng.state
	var before := snapshot(o, d)
	var coins := BargeViews.holdings(Game)
	var linen := goods_total(o, d)
	var losing := Caravans.quote_trip(w, o, d, rng)
	check(losing["ready"] and Goods.price_f(d, "linen") > Goods.price_f(o, "linen"), "gross-profitable cargo is available")
	check(float(losing["expected"]["sale_value"]) > float(losing["expected"]["buy_cost"]) and float(losing["expected"]["net"]) < 0.0, "spread, duties and trip payroll turn gross profit into a net loss")
	Caravans.quote_trip(w, o, d, rng)
	check(rng.state == state and Game.rng.state == game_state and snapshot(o, d) == before, "quotes preserve live holders and RNG streams")
	TownEcon._plan_trade(Game, o, o["econ"], int(Game.day))
	check(w["work"].is_empty(), "planner rejects the net-losing route")
	check(Caravans.spawn(Game, String(o["id"]), rng, String(d["id"])) == "", "spawn rechecks and rejects a losing route")
	check(rng.state == state and snapshot(o, d) == before, "rejection neither buys cargo nor consumes RNG")
	near(BargeViews.holdings(Game), coins, "rejection conserves coin")
	check(goods_total(o, d) == linen, "rejection conserves goods")

	d["econ"]["price"]["linen"] = 1000.0
	# A second good earns its margin on the return leg; both legs must reconcile.
	o["econ"]["stock"]["leather"] = 0; o["econ"]["need"]["leather"] = 1000.0; o["econ"]["price"]["leather"] = 1000.0
	d["econ"]["stock"]["leather"] = 6000; d["econ"]["need"]["leather"] = 10.0; d["econ"]["price"]["leather"] = 10.0
	var leather := goods_total(o, d, "leather")
	var quote := Caravans.quote_trip(w, o, d, rng)
	check(quote["ready"] and float(quote["expected"]["net"]) > 0.0, "a real net-profitable round trip exists")
	TownEcon._plan_trade(Game, o, o["econ"], int(Game.day))
	check(w["work"].size() == 1 and w["work"][0][2] == d["id"], "planner queues the profitable destination")
	w["work"] = []   # consume the planned job; invoke its native spawn directly
	var treasury := float(o["econ"]["treasury"]); var till := float(market(o)["till"])
	var buyer_till := float(market(d)["till"]); var buyer_chest := float(d["econ"]["treasury"])
	var purses := family_coin(o)
	var out0 := float(o["econ"]["stats"].get("trade_out", 0.0))
	var in0 := float(d["econ"]["stats"].get("trade_in", 0.0))
	var home_in0 := float(o["econ"]["stats"].get("trade_in", 0.0))
	var sales0 := float(d["econ"]["stats"].get("sales", 0.0))
	var duties0 := float(d["econ"]["stats"].get("duties", 0.0))
	var wid := Caravans.spawn(Game, String(o["id"]), rng, String(d["id"]))
	check(wid != "", "profitable caravan sails through native crew hiring")
	if wid == "": return fails
	var wb: Dictionary = w["warbands"][wid]
	var receipt: Dictionary = wb["receipt"]
	check(receipt["expected"] == quote["expected"], "departure receipt uses the same quoted cargo and costs")
	check(Caravans.cargo_weight(wb["cargo"]) <= Caravans.CAPACITY_KG and int(wb["cargo"]["goods"].get("linen", 0)) > 0, "real cargo obeys aggregate wagon capacity")
	near(float(o["econ"]["stats"]["trade_out"]) - out0, float(receipt["realized"]["buy_cost"]), "purchase receipt reconciles with trade-out ledger")
	near(treasury - float(o["econ"]["treasury"]), float(receipt["realized"]["buy_cost"]) + float(wb["gold"]), "treasury owns cargo funding and unspent purse")
	var daily_wages := 0.0
	for c in wb["crew"]: daily_wages += float(c[2])
	var paid_days := int(ceil(float(quote["days"])))
	for day in paid_days:
		Game.day += 1.0
		People.pay_crews(Game)   # only payroll, no production, prices or unrelated daily turns
	near(float(receipt["realized"]["crew"]), daily_wages * paid_days, "realized payroll counts actual daily transfers")
	wb["pos"] = d["pos"]; Caravans.arrive(Game, wid)
	check(wb["leg"] == "home" and int(wb["cargo"]["goods"].get("leather", 0)) > 0, "native arrival sells and buys real return cargo")
	check(Caravans.cargo_weight(wb["cargo"]) <= Caravans.CAPACITY_KG, "return cargo shares the same wagon capacity")
	wb["pos"] = o["pos"]; Caravans.arrive(Game, wid)
	check(not w["warbands"].has(wid), "paid trip closes")
	var actual: Dictionary = receipt["realized"]
	var out_buy := float(o["econ"]["stats"]["trade_out"]) - out0
	var return_buy := float(d["econ"]["stats"]["sales"]) - sales0
	var out_sale := float(d["econ"]["stats"]["trade_in"]) - in0
	var home_sale := float(o["econ"]["stats"]["trade_in"]) - home_in0
	near(float(actual["buy_cost"]), out_buy + return_buy, "both purchases reconcile with market ledgers")
	near(float(actual["sale_value"]), out_sale + home_sale, "both sales reconcile with trade-in ledgers")
	near(float(actual["duties"]), float(d["econ"]["stats"]["duties"]) - duties0, "duties reconcile with ledger")
	near(float(market(d)["till"]) - buyer_till, return_buy - out_sale, "destination till reconciles both trades")
	near(float(actual["duties"]), float(d["econ"]["treasury"]) - buyer_chest, "duty credits the actual destination treasury")
	near(float(actual["crew"]), family_coin(o) - purses, "wages reach the real crew families")
	near(float(market(o)["till"]) - till, out_buy - home_sale - float(actual["crew"]), "home till reconciles cargo and payroll")
	near(float(o["econ"]["treasury"]) - treasury, float(actual["net"]) + float(actual["crew"]), "treasury return and separately owned crew expense reconcile to net")
	check(float(actual["net"]) > 0.0 and receipt["status"] == "returned", "realized trip is profitable and closed")
	check(o["econ"]["caravan_receipts"].back() == receipt, "closed receipt remains in town records")
	near(BargeViews.holdings(Game), coins, "profitable trip conserves every coin")
	check(goods_total(o, d) == linen and goods_total(o, d, "leather") == leather, "both legs conserve every cargo unit")

	configure(o, d)
	d["econ"]["price"]["linen"] = 1000.0
	var unpaid_id := Caravans.spawn(Game, String(o["id"]), rng, String(d["id"]))
	check(unpaid_id != "", "second profitable caravan sails before buyer liquidity changes")
	if unpaid_id == "": return fails
	wb = w["warbands"][unpaid_id]
	# One exact existing Item also travels: a fixture transfer, not generated gear.
	var armory := ArmsTrade.armory(o)
	check(not armory.is_empty(), "fixture has an existing Item to test unpaid identity")
	if armory.is_empty(): return fails
	var item: Item = armory.pop_back()
	wb["cargo"]["items"].append(item)
	var cargo_goods: Dictionary = wb["cargo"]["goods"].duplicate()
	var cargo_items: Array = wb["cargo"]["items"].duplicate()
	for t in [o, d]:   # move funds to their actual treasuries; never erase coins
		t["econ"]["treasury"] = float(t["econ"]["treasury"]) + float(market(t)["till"])
		market(t)["till"] = 0.0
	coins = BargeViews.holdings(Game); linen = goods_total(o, d)
	var purse := float(wb["gold"])
	var stock := Goods.supply(d, "linen")
	wb["pos"] = d["pos"]; Caravans.arrive(Game, unpaid_id)
	check(wb["cargo"]["goods"] == cargo_goods and wb["cargo"]["items"] == cargo_items and is_same(wb["cargo"]["items"][0], item), "unpaid destination keeps all cargo and exact Item identity")
	near(Goods.supply(d, "linen"), stock, "unpaid goods never enter destination stock")
	near(float(wb["gold"]), purse, "no sale or return purchase invents coin")
	near(float(wb["receipt"]["realized"]["sale_value"]), 0.0, "unpaid sale realizes no revenue")
	near(float(wb["receipt"]["realized"]["duties"]), 0.0, "unpaid sale charges no duty")
	wb["pos"] = o["pos"]; Caravans.arrive(Game, unpaid_id)
	check(w["warbands"].has(unpaid_id) and wb["state"] == "unpaid" and wb["crew"].is_empty() and wb["units"].is_empty(), "unpaid home cargo stays on parked wagons; crew goes home")
	check(wb["cargo"]["goods"] == cargo_goods and wb["cargo"]["items"] == cargo_items, "home settlement also transfers only paid cargo")
	check(String(wb["receipt"]["unpaid_cargo"]) != "", "pending receipt exposes unpaid cargo")
	Caravans.daily(Game, rng)
	check(w["warbands"].has(unpaid_id) and wb["cargo"]["goods"] == cargo_goods, "daily retry with no money retains the shipment")
	TownEcon._plan_trade(Game, o, o["econ"], int(Game.day))
	check(w["work"].is_empty(), "unpaid wagons retain the per-town caravan slot")
	near(BargeViews.holdings(Game), coins, "unpaid destinations and retries conserve coin")
	check(goods_total(o, d) == linen, "unpaid destinations and retries conserve goods")
	o["econ"]["treasury"] = float(o["econ"]["treasury"]) - 100000.0
	market(o)["till"] = 100000.0
	Caravans.daily(Game, rng)
	check(not w["warbands"].has(unpaid_id) and wb["cargo"]["goods"].is_empty() and wb["cargo"]["items"].is_empty(), "funded retry pays for cargo once and closes")
	check(o["shop"].has(item), "paid Item transfers intact to home shop")
	near(BargeViews.holdings(Game), coins, "funded retry conserves coin")
	check(goods_total(o, d) == linen, "funded retry conserves goods")

	# An insolvent home market can never buy even one Item. After the wait the wagons leave.
	configure(o, d)
	d["econ"]["price"]["linen"] = 1000.0
	o["econ"]["stock"]["leather"] = 0; o["econ"]["need"]["leather"] = 1000.0; o["econ"]["price"]["leather"] = 1000.0
	d["econ"]["stock"]["leather"] = 6000; d["econ"]["need"]["leather"] = 10.0; d["econ"]["price"]["leather"] = 10.0
	var stuck_id := Caravans.spawn(Game, String(o["id"]), rng, String(d["id"]))
	check(stuck_id != "", "insolvent-home fixture sails before the tills are emptied")
	if stuck_id == "": return fails
	wb = w["warbands"][stuck_id]
	var pool: Array = ArmsTrade.armory(o)
	if pool.is_empty(): pool = Game.stash
	check(not pool.is_empty(), "fixture has an existing Item the home market cannot buy")
	if pool.is_empty(): return fails
	var stuck_item: Item = pool.pop_back()
	wb["cargo"]["items"].append(stuck_item)
	var stuck_goods: Dictionary = wb["cargo"]["goods"].duplicate()
	check(int(stuck_goods.get("linen", 0)) > 0, "insolvent fixture carries goods as well as the Item")
	for t in [o, d]:
		t["econ"]["treasury"] = float(t["econ"]["treasury"]) + float(market(t)["till"])
		market(t)["till"] = 0.0
	var buy_price := Economy.base_value(o, stuck_item) * float(TownEcon.data()["market"]["arms_buy_share"])
	check(buy_price > float(market(o)["till"]), "home till cannot pay for even one Item")
	wb["pos"] = d["pos"]; Caravans.arrive(Game, stuck_id)
	wb["pos"] = o["pos"]; Caravans.arrive(Game, stuck_id)
	var aboard := false
	for it in wb["cargo"]["items"]:
		if is_same(it, stuck_item): aboard = true
	check(w["warbands"].has(stuck_id) and wb["state"] == "unpaid" and wb["crew"].is_empty() and aboard, "insolvent home parks the caravan with the Item still aboard")
	check(int(wb["cargo"]["goods"].get("linen", 0)) == int(stuck_goods.get("linen", 0)) and not wb["cargo"]["goods"].is_empty(), "insolvent home leaves the outbound goods unpaid")
	coins = BargeViews.holdings(Game)
	linen = goods_total(o, d)
	var leather_stuck := goods_total(o, d, "leather")
	var held := item_uids(w)
	var slots := Caravans.count(w)
	Caravans.daily(Game, rng)
	check(w["warbands"].has(stuck_id) and int(wb["unpaid_wait"]) == 1, "one unpaid day does not free the slot")
	var packed := JSON.stringify(Game._serialize(wb))
	var restored = Game._deserialize(JSON.parse_string(packed))
	check(int(restored["unpaid_wait"]) == int(wb["unpaid_wait"]), "save/load keeps the unpaid wait counter")
	wb["unpaid_wait"] = Caravans.UNPAID_WAIT_DAYS - 1
	Caravans.daily(Game, rng)
	check(not w["warbands"].has(stuck_id), "the wait consigns the caravan and removes it")
	check(Caravans.count(w) == slots - 1, "removing the caravan frees its global slot")
	var handed := false
	for it in o["shop"]:
		if is_same(it, stuck_item): handed = true
	check(handed, "consigned Item is the same piece in the home shop")
	check(item_uids(w) == held, "consignment keeps every Item identity")
	check(wb["cargo"]["goods"].is_empty() and wb["cargo"]["items"].is_empty(), "consigned cargo leaves the wagons")
	check(int(o["econ"]["stock"].get("linen", 0)) >= int(stuck_goods.get("linen", 0)), "consigned goods sit in home market stock")
	near(BargeViews.holdings(Game), coins, "consignment conserves every coin")
	check(goods_total(o, d) == linen and goods_total(o, d, "leather") == leather_stuck, "consignment conserves every good")
	var closed: Dictionary = o["econ"]["caravan_receipts"].back()
	check(closed["status"] == "consigned" and String(closed.get("consigned", "")) != "" and int(closed.get("unpaid_wait", 0)) == Caravans.UNPAID_WAIT_DAYS, "receipt records the consigned cargo and the wait")
	for t in [o, d]:
		var back := minf(200000.0, float(t["econ"]["treasury"]))
		t["econ"]["treasury"] = float(t["econ"]["treasury"]) - back
		market(t)["till"] = float(market(t)["till"]) + back
	w["work"] = []
	TownEcon._plan_trade(Game, o, o["econ"], int(Game.day))
	check(w["work"].size() == 1 and w["work"][0][0] == "caravan" and w["work"][0][1] == o["id"], "the home town's caravan slot is free again")
	check(Time.get_ticks_msec() - started < 60000, "bounded fixture finishes under 60 seconds")
	return fails
