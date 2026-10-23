extends RefCounted
## One DevTools world, native spawn/crew/settlement/raid and one real save/load.
## godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_supply_orders_v049.gd --watchdog=60
var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL supply049: ", message)

func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.001, "%s (%.6f vs %.6f)" % [message, a, b])

func market(t: Dictionary) -> Dictionary:
	return t["econ"]["biz"][int(t["econ"]["mkt"])]

func spare(t: Dictionary) -> int:
	var n := 0
	for f: Dictionary in t["econ"]["fams"]:
		if not f.get("gone", false) and not f.has("estate"): n += maxi(0, Population.spare(f))
	return n

func pair(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid in ids:
		var source: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(source) or Monsters.is_monster_faction(str(source["faction"])): continue
		if not RecTown._caravans_of(str(tid)).is_empty() or spare(source) < ArmsTrade.max_guards(source) * 3 + People.DRIVERS + 4: continue
		for link: Dictionary in Caravans.trade_partners(w, source):
			var buyer: Dictionary = w["towns"][link["id"]]
			if TownEcon.has_econ(buyer) and buyer["faction"] == source["faction"] \
					and RecTown._caravans_of(str(buyer["id"])).is_empty() and spare(buyer) > ArmsTrade.max_guards(buyer) + People.DRIVERS + 4:
				return [source, buyer, link]
	return []

## Include destruction and the company's actual raid loot, never an order's memo quantities.
func goods(good: String = "grain") -> int:
	var total := int(TownEcon.goods_lost.get(good, 0))
	for town: Dictionary in Game.world["towns"].values():
		if TownEcon.has_econ(town): total += TownEcon.town_total(town["econ"], good)
	for band: Dictionary in Game.world["warbands"].values():
		total += int(band.get("cargo", {}).get("goods", {}).get(good, 0))
	total += int(Game.world.get("company_goods", {}).get(good, 0))
	return total

func balanced(order: Dictionary) -> void:
	near(float(order["cap"]), float(order["reserved"]) + float(order["spent"]) + float(order["refunded"]), "cap has exactly one owner")

func place(tid: String, source: String, quantity: int = 20, cap: float = 40000.0, good: String = "grain") -> String:
	var result := SupplyOrders.place(Game, tid, good, quantity, 10.0, cap, source)
	check(result["ok"], "ruler places a funded order: " + str(result.get("reason", "")))
	return str(result.get("id", ""))

func close_trip(wid: String, buyer: Dictionary, source: Dictionary) -> void:
	if not Game.world["warbands"].has(wid): return
	var band: Dictionary = Game.world["warbands"][wid]
	band["pos"] = buyer["pos"]; Caravans.arrive(Game, wid)
	band["pos"] = source["pos"]; Caravans.arrive(Game, wid)
	Caravans.arrive(Game, wid) # duplicate final event

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	if not await DevTools.start_world(tree, Game.SAVE_PATH):
		check(false, "DevTools start world loads"); return fails
	var towns := pair(Game.world)
	check(towns.size() == 3 and Caravans.count(Game.world) < Caravans.max_caravans(Game.world), "fixture has a staffed road pair and free caravan slot")
	if towns.size() != 3: return fails
	var source: Dictionary = towns[0]; var buyer: Dictionary = towns[1]
	var sid := str(source["id"]); var tid := str(buyer["id"])
	Game.world["work"] = []
	source["road_links"] = [towns[2]]
	buyer["road_links"] = [{"id": sid, "faction": source["faction"], "dist": towns[2]["dist"]}]
	check(Dynasty.select_city(Game, tid), "select the actual local ruling house")
	if not SupplyOrders.can_manage(Game, tid): return fails
	for town in [source, buyer]:
		town["econ"]["treasury"] = 120000.0
		market(town)["till"] = 1000000.0
	source["econ"]["stock"]["grain"] = 10000
	source["econ"]["need"]["grain"] = 1.0
	source["econ"]["price"]["grain"] = 4.0
	var coins := BargeViews.holdings(Game); var stock := goods()
	var treasury := float(buyer["econ"]["treasury"])
	check(not SupplyOrders.place(Game, sid, "grain", 20, 10.0, 10000.0, tid)["ok"], "player cannot order for another town")
	check(not SupplyOrders.place(Game, tid, "grain", 20, 10.0, treasury + 1.0, sid)["ok"], "unfunded order is rejected")
	var id := place(tid, sid)
	if id == "": return fails
	var order := SupplyOrders.find(buyer, id)
	near(float(buyer["econ"]["treasury"]), treasury - 40000.0, "placing reserves the whole cap")
	near(float(order["reserved"]), 40000.0, "reservation is a saved coin holder")
	near(BargeViews.holdings(Game), coins, "reservation conserves world coin")
	check(goods() == stock and order["state"] == "ordered", "ordering moves no goods")
	var rng_state: int = Game.rng.state
	var before := JSON.stringify([order, source["econ"]["stock"], buyer["econ"]["stock"]])
	var quote := SupplyOrders.quote(Game, buyer, order)
	check(quote["ok"] and SupplyOrders.quote(Game, buyer, order) == quote, "quotes are deterministic")
	check(Game.rng.state == rng_state and before == JSON.stringify([order, source["econ"]["stock"], buyer["econ"]["stock"]]), "quotes do not mutate stock, funding or RNG")
	source["econ"]["price"]["grain"] = 11.0
	check(SupplyOrders.depart(Game, tid, id) == "" and order["state"] == "blocked" and str(order["reason"]) != "", "departure rechecks price limit and exposes why it is blocked")
	near(float(order["reserved"]), 40000.0, "blocked order retains funds")
	check(goods() == stock, "blocked departure moves no goods")
	source["econ"]["price"]["grain"] = 4.0
	var gone := []
	for family: Dictionary in source["econ"]["fams"]:
		gone.append(bool(family["gone"])); family["gone"] = true
	var refused := SupplyOrders.depart(Game, tid, id)
	for i in gone.size(): source["econ"]["fams"][i]["gone"] = gone[i]
	check(refused == "" and order["state"] == "blocked", "native crew refusal rolls departure back")
	near(float(order["reserved"]), 40000.0, "failed sail restores its whole reservation")
	near(BargeViews.holdings(Game), coins, "failed sail returns payment exactly once")
	check(goods() == stock and int(source["econ"]["stock"]["grain"]) == 10000, "failed sail restores real preset stock once")
	var wid := SupplyOrders.depart(Game, tid, id)
	check(wid != "" and order["state"] == "travelling", "funded preset sails through native caravan crew hiring")
	if wid == "": return fails
	var band: Dictionary = Game.world["warbands"][wid]
	check(int(band["cargo"]["goods"]["grain"]) == 20 and not band.get("crew", []).is_empty(), "real cargo and native crew travel together")
	near(float(band["gold"]), 0.0, "supplier receives payment; reservation is not also on the wagons")
	balanced(order)
	near(BargeViews.holdings(Game), coins, "departure conserves every coin")
	check(goods() == stock, "departure conserves every cargo unit")
	# An occupied source blocks another trip, and cancelling twice releases once.
	var second := place(tid, sid)
	if second == "": return fails
	check(SupplyOrders.depart(Game, tid, second) == "", "source keeps its ordinary per-town caravan slot")
	check(SupplyOrders.cancel(Game, tid, second)["ok"] and SupplyOrders.cancel(Game, tid, second)["ok"], "cancelling is idempotent")
	balanced(SupplyOrders.find(buyer, second))
	near(BargeViews.holdings(Game), coins, "cancel releases reserved coins exactly once")

	var saved_reserve := float(order["reserved"]); var paid := float(order["spent"])
	Game.save_game(); Game.wait_save()
	check(Game.load_game(), "native save loads during transit")
	source = Game.world["towns"][sid]; buyer = Game.world["towns"][tid]
	order = SupplyOrders.find(buyer, id)
	check(order["state"] == "travelling" and str(order["caravan"]) == wid and Game.world["warbands"].has(wid), "save/load keeps the order and its caravan")
	near(float(order["reserved"]), saved_reserve, "load preserves escrow without re-reserving")
	near(float(order["spent"]), paid, "load never pays supplier twice")
	band = Game.world["warbands"][wid]
	check(int(band["cargo"]["goods"]["grain"]) == 20, "mid-trip cargo survives load")
	near(BargeViews.holdings(Game), coins, "mid-trip save/load conserves coins")
	check(goods() == stock, "mid-trip save/load conserves goods")
	# Native crew wages still reach their households; buyer need not fund its market.
	People.pay_crews(Game)
	buyer["econ"]["treasury"] = float(buyer["econ"]["treasury"]) + float(market(buyer)["till"])
	market(buyer)["till"] = 0.0
	var buyer_stock := Goods.supply(buyer, "grain")
	var buyer_cash := float(buyer["econ"]["treasury"])
	band["pos"] = buyer["pos"]; Caravans.arrive(Game, wid)
	check(order["state"] == "delivered" and int(order["delivered"]) == 20, "arrival delivers to the prepaid buyer even with an empty market till")
	near(Goods.supply(buyer, "grain"), buyer_stock + 20.0, "delivery credits exactly the carried stock")
	near(float(buyer["econ"]["treasury"]), buyer_cash + saved_reserve, "delivery releases all unspent funding")
	near(float(order["reserved"]), 0.0, "delivery closes escrow")
	SupplyOrders.deliver(Game, band) # duplicate destination notification
	Caravans.arrive(Game, wid)
	check(Game.world["warbands"].has(wid), "duplicate destination event does not skip the return journey")
	near(Goods.supply(buyer, "grain"), buyer_stock + 20.0, "duplicate delivery credits nothing")
	band["pos"] = source["pos"]; Caravans.arrive(Game, wid); Caravans.arrive(Game, wid)
	check(not Game.world["warbands"].has(wid), "supplier's empty wagons and crew return through native homecoming")
	balanced(order)
	near(BargeViews.holdings(Game), coins, "delivery, refund and crew pay conserve coins")
	check(goods() == stock, "delivery conserves goods")

	# Insufficient supplier stock closes a partial delivery and releases the remainder.
	source["econ"]["stock"]["grain"] = 5 # target 1.1 leaves three spare units
	stock = goods(); coins = BargeViews.holdings(Game)
	id = place(tid, sid)
	if id == "": return fails
	wid = SupplyOrders.depart(Game, tid, id)
	check(wid != "", "partial shipment departs")
	if wid == "": return fails
	order = SupplyOrders.find(buyer, id)
	check(int(order["loaded"]) == 3, "partial cargo is limited to actual spare stock")
	close_trip(wid, buyer, source)
	check(order["state"] == "delivered" and int(order["delivered"]) == 3, "partial delivery remains visible")
	balanced(order)
	near(BargeViews.holdings(Game), coins, "partial settlement conserves coin")
	check(goods() == stock, "partial settlement conserves goods")

	# The spending cap limits quantity after freight. In-transit cancellation cannot
	# undo the paid purchase or conjure cargo back at the supplier.
	source["econ"]["stock"]["grain"] = 10000
	var draft := {"id": "supply%d" % int(Game.world["next_id"]), "good": "grain", "quantity": 20,
		"max_unit": 10.0, "source": sid, "reserved": 80000.0}
	quote = SupplyOrders.quote(Game, buyer, draft)
	check(quote["ok"], "cap fixture has an affordable route")
	if not quote["ok"]: return fails
	var cap := float(quote["freight"]) + 8.5
	stock = goods(); coins = BargeViews.holdings(Game)
	id = place(tid, sid, 20, cap)
	if id == "": return fails
	wid = SupplyOrders.depart(Game, tid, id)
	if wid == "": check(false, "cap-limited trip departs"); return fails
	order = SupplyOrders.find(buyer, id)
	check(int(order["loaded"]) == 2, "all-in cap buys only two units after freight")
	near(float(order["reserved"]), 0.5, "only the unspent half coin remains reserved")
	check(SupplyOrders.cancel(Game, tid, id)["ok"], "travelling remainder can be cancelled")
	near(float(order["refunded"]), 0.5, "in-transit cancellation releases only unused coins")
	close_trip(wid, buyer, source)
	check(order["state"] == "cancelled" and int(order["delivered"]) == 2, "cancelled remainder retains its eventual paid delivery")
	balanced(order)
	near(BargeViews.holdings(Game), coins, "in-transit cancellation conserves coin")
	check(goods() == stock, "in-transit cancellation conserves cargo")

	# Meat and metal use concrete native goods, never an invented aggregate stock.
	for good in ["meat", "metal"]:
		var native := "iron_bars" if good == "metal" else str(good)
		source["econ"]["stock"][native] = 10000
		source["econ"]["need"][native] = 1.0; source["econ"]["price"][native] = 4.0
		stock = goods(native); coins = BargeViews.holdings(Game)
		id = place(tid, sid, 1, 40000.0, str(good))
		if id == "": return fails
		wid = SupplyOrders.depart(Game, tid, id)
		check(wid != "", "native " + native + " shipment sails")
		if wid == "": return fails
		order = SupplyOrders.find(buyer, id)
		check(order["good"] == native, "order names the actual stock good")
		close_trip(wid, buyer, source)
		check(int(order["delivered"]) == 1 and goods(native) == stock, "native good settles once")
		near(BargeViews.holdings(Game), coins, "native-good purchase conserves coins")
		balanced(order)

	# A dead/replaced issuer cannot spend a reservation at departure.
	id = place(tid, sid)
	if id == "": return fails
	var head: Dictionary = buyer["econ"]["head"]
	var issuer := str(head["person_uid"]); head["person_uid"] = ""
	check(SupplyOrders.depart(Game, tid, id) == "", "departure rechecks actual office authority")
	head["person_uid"] = issuer
	order = SupplyOrders.find(buyer, id)
	check(order["state"] == "blocked" and order["closed"], "lost authority terminates the blocked order")
	near(float(order["reserved"]), 0.0, "lost authority releases funds")
	balanced(order)

	# AI checks once per week, uses its living ruler and never drives the player's town.
	for holder in ["stock", "barn", "hh"]:
		for good in ["grain", "fruit", "meat", "fresh_meat"]: source["econ"][holder][good] = 0
	source["econ"]["granary"] = 0
	source["econ"]["price"]["grain"] = 10.0
	buyer["econ"]["stock"]["grain"] = 10000
	buyer["econ"]["need"]["grain"] = 1.0; buyer["econ"]["price"]["grain"] = 4.0
	var day := (int(Game.day) / 7 + 1) * 7
	var count := SupplyOrders.orders(source).size()
	coins = BargeViews.holdings(Game)
	SupplyOrders.ai_week(Game, source, day); SupplyOrders.ai_week(Game, source, day)
	check(SupplyOrders.orders(source).size() == count + 1, "hungry AI ruler places at most one affordable grain order per week")
	count = SupplyOrders.orders(buyer).size()
	SupplyOrders.ai_week(Game, buyer, day)
	check(SupplyOrders.orders(buyer).size() == count, "player's town remains manual")
	near(BargeViews.holdings(Game), coins, "AI reservation conserves coin")

	# Both native loss paths refund only the safe reserve. Physical cargo is
	# destroyed or becomes real raid loot once; payment already at the seller stays paid.
	source["econ"]["stock"]["grain"] = 10000
	source["econ"]["price"]["grain"] = 4.0
	for raid in [false, true]:
		stock = goods(); coins = BargeViews.holdings(Game)
		id = place(tid, sid)
		if id == "": return fails
		wid = SupplyOrders.depart(Game, tid, id)
		check(wid != "", "loss fixture departs")
		if wid == "": return fails
		order = SupplyOrders.find(buyer, id)
		saved_reserve = float(order["reserved"]); paid = float(order["spent"])
		buyer_cash = float(buyer["econ"]["treasury"])
		if raid:
			var loot := Caravans.plunder(Game, wid)
			check(int(loot.get("goods", {}).get("grain", 0)) == int(round(20.0 * Caravans.PLUNDER_SHARE)), "player receives only the native raid share")
			check(Caravans.plunder(Game, wid).is_empty(), "duplicate raid takes nothing")
		else:
			Caravans.lost(Game, wid, str(source["faction"]))
			Caravans.lost(Game, wid, str(source["faction"]))
		Caravans.arrive(Game, wid)
		check(order["state"] == "blocked" and order["closed"] and int(order["delivered"]) == 0 and str(order["reason"]) != "", "lost caravan never delivers or retries")
		near(float(buyer["econ"]["treasury"]), buyer_cash + saved_reserve, "loss releases exactly the safe reserve")
		near(float(order["spent"]), paid, "loss never refunds already purchased goods")
		balanced(order)
		near(BargeViews.holdings(Game), coins, "raid/loss conserves all coin (these wagons carried no purse)")
		check(goods() == stock, "raid/loss accounts every unit once as stock, cargo, loot or destruction")
	check(Time.get_ticks_msec() - started < 60000, "one-fixture test finishes within 60 seconds")
	return fails
