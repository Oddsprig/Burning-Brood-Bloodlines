class_name SupplyOrders
extends RefCounted
## v0.049: treasury-funded purchases, carried by ordinary merchant caravans.
## Only reserved is a coin holder; spent/refunded are receipts. No static state.
## Goods + a fixed quoted freight fee are paid at departure. Cancelling in transit
## releases unspent coins; the paid cargo continues to its buyer. Loss never refunds
## a purchase already paid to the supplier. Native crews/kit remain supplier-owned.
const GOODS := ["grain", "meat", "copper_bars", "tin_bars", "bronze_bars", "iron_bars", "steel_bars"]
const MAX_OPEN := 2
const HISTORY := 32
const FOOD_DAYS := 7.0

static func orders(town: Dictionary) -> Array:
	return town.get("econ", {}).get("supply_orders", [])

static func find(town: Dictionary, id: String) -> Dictionary:
	for order: Dictionary in orders(town):
		if str(order["id"]) == id: return order
	return {}

static func reserved(e: Dictionary) -> float:
	var coins := 0.0
	for order: Dictionary in e.get("supply_orders", []):
		coins += float(order.get("reserved", 0.0))
	return coins

static func can_manage(game, tid: String) -> bool:
	return str(game.world.get("player_house", {}).get("town_id", "")) == tid and Feudal.can_act(game, tid)

static func _ruler(game, town: Dictionary) -> String:
	var uid := str(town.get("econ", {}).get("head", {}).get("person_uid", ""))
	return uid if Dynasty._person(game, uid).get("alive", false) else ""

static func _open(town: Dictionary) -> int:
	var n := 0
	for order: Dictionary in orders(town):
		if not order.get("closed", false): n += 1
	return n

static func _prune(game, town: Dictionary) -> void:
	var rows := orders(town)
	var closed := 0
	for i in range(rows.size() - 1, -1, -1):
		var order: Dictionary = rows[i]
		if not order.get("closed", false) or game.world.get("warbands", {}).has(str(order.get("caravan", ""))): continue
		closed += 1
		if closed > HISTORY: rows.remove_at(i)

static func place(game, tid: String, good: String, quantity: int, max_unit: float, cap: float,
		source: String = "best", ai: bool = false) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	if not TownEcon.has_econ(town): return {"ok": false, "reason": "No town treasury."}
	if (not ai and not can_manage(game, tid)) or (ai and can_manage(game, tid)):
		return {"ok": false, "reason": "Only the town's ruler may place its orders."}
	var issuer := _ruler(game, town)
	if issuer == "": return {"ok": false, "reason": "The town has no living ruler."}
	# 'metal' is an explicit iron-bar shorthand; never mint an aggregate metal good.
	if good == "metal": good = "iron_bars"
	if not GOODS.has(good) or quantity < 1 or quantity > 1000000 \
			or not is_finite(max_unit) or not is_finite(cap) or max_unit <= 0.0 or cap <= 0.0:
		return {"ok": false, "reason": "Choose a good, positive quantity, unit price limit and total cap."}
	if source != "best" and (source == tid or not game.world["towns"].has(source)):
		return {"ok": false, "reason": "Choose another source town or best."}
	if _open(town) >= MAX_OPEN: return {"ok": false, "reason": "At most two open orders per town."}
	var e: Dictionary = town["econ"]
	if float(e["treasury"]) < cap: return {"ok": false, "reason": "The treasury cannot reserve that cap."}
	var order := {"id": CampaignWorld.new_id(game.world, "supply"), "issuer": issuer,
		"faction": str(town["faction"]), "ai": ai, "good": good, "quantity": quantity,
		"max_unit": max_unit, "cap": cap, "source": source, "actual_source": "",
		"reserved": cap, "spent": 0.0, "refunded": 0.0, "loaded": 0, "delivered": 0,
		"caravan": "", "state": "ordered", "reason": "", "closed": false,
		"delivery_done": false, "created_day": int(game.day)}
	e["treasury"] = float(e["treasury"]) - cap
	if not e.has("supply_orders"): e["supply_orders"] = []
	e["supply_orders"].append(order)
	_prune(game, town)
	return {"ok": true, "id": order["id"]}

static func _refund(town: Dictionary, order: Dictionary) -> void:
	var coins := float(order["reserved"])
	order["reserved"] = 0.0
	order["refunded"] = float(order["refunded"]) + coins
	town["econ"]["treasury"] = float(town["econ"]["treasury"]) + coins

static func cancel(game, tid: String, id: String) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	if not can_manage(game, tid): return {"ok": false, "reason": "Only the town's ruler may cancel its orders."}
	var order := find(town, id)
	if order.is_empty(): return {"ok": false, "reason": "Order not found."}
	if order["state"] == "cancelled": return {"ok": true}
	if order.get("closed", false): return {"ok": false, "reason": "That order is already settled."}
	_refund(town, order)
	order["state"] = "cancelled"; order["closed"] = true
	order["reason"] = "Unused reserve released; paid cargo still travels to town." if int(order["loaded"]) > 0 else "Reserve released."
	return {"ok": true}

## Native trade diplomacy; quote_trip/way checks actual reachability, including
## multi-road routes. Stable IDs break all ties without consuming campaign RNG.
static func sources(w: Dictionary, town: Dictionary) -> Array:
	var ids := []
	for tid in w.get("towns", {}):
		var source: Dictionary = w["towns"][tid]
		if str(tid) != str(town["id"]) and TownEcon.has_econ(source) \
				and Diplomacy.trade_ok(w, str(town["faction"]), str(source["faction"])):
			ids.append(str(tid))
	ids.sort()
	return ids

static func _busy(w: Dictionary, tid: String) -> bool:
	for wb: Dictionary in w.get("warbands", {}).values():
		if wb.get("kind", "") == "caravan" and str(wb.get("origin", "")) == tid: return true
	for muster: Dictionary in CampaignWorld.mustering(w):
		var band: Dictionary = muster.get("wb", muster.get("extra", {}))
		if muster.get("kind", "") == "caravan" and str(band.get("origin", "")) == tid: return true
	for job: Array in w.get("work", []):
		if job.size() > 1 and str(job[0]) == "caravan" and str(job[1]) == tid: return true
	return false

static func _rng(w: Dictionary, order: Dictionary, source: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), str(order["id"]), source, "supply049"])
	return rng

static func _preset(town: Dictionary, order: Dictionary, q: Dictionary) -> Dictionary:
	return {"items": [], "goods": {str(order["good"]): int(q["quantity"])},
		"supply_order_id": str(order["id"]), "supply_town": str(town["id"]),
		"supply_cost": float(q["price"]) * int(q["quantity"])}

static func _quote_source(game, town: Dictionary, order: Dictionary, source: Dictionary) -> Dictionary:
	if _busy(game.world, str(source["id"])): return {"ok": false, "reason": "Source caravan is already away or queued."}
	if Monsters.suspended_band({"faction": source["faction"], "kind": "caravan"}):
		return {"ok": false, "reason": "Source caravans are suspended."}
	var good := str(order["good"])
	var price := Goods.price_f(source, good)
	if not is_finite(price) or price <= 0.0 or price > float(order["max_unit"]):
		return {"ok": false, "reason": "Source price exceeds the unit limit."}
	var kg := maxf(0.05, float(Goods.table()[good].get("weight", 1.0)))
	var quantity := mini(int(order["quantity"]), mini(maxi(0, Caravans.surplus(source, good)), int(Caravans.CAPACITY_KG / kg)))
	if quantity < 1: return {"ok": false, "reason": "Source has no spare stock."}
	var result := {"quantity": quantity, "price": price}
	var trip := Caravans.quote_trip(game.world, source, town, _rng(game.world, order, str(source["id"])), true, _preset(town, order, result))
	if not trip["ready"]: return {"ok": false, "reason": "No passable caravan route."}
	var freight := float(trip["expected"]["crew"])
	quantity = mini(quantity, int(floor(maxf(0.0, float(order["reserved"]) - freight) / price)))
	if quantity < 1: return {"ok": false, "reason": "Reserve cannot cover freight and one unit."}
	var spend := freight + quantity * price
	var e: Dictionary = source["econ"]
	if float(e["biz"][int(e["mkt"])]["till"]) + spend < freight:
		return {"ok": false, "reason": "Source cannot fund its crew."}
	return {"ok": true, "source": str(source["id"]), "quantity": quantity, "price": price, "freight": freight, "spend": spend}

## Read-only: best means most units within both caps, then lowest delivered cost/unit.
static func quote(game, town: Dictionary, order: Dictionary) -> Dictionary:
	var best := {"ok": false, "reason": "No peaceful reachable town can supply this order."}
	var requested := str(order["source"])
	for tid in sources(game.world, town):
		if requested != "best" and requested != tid: continue
		var candidate := _quote_source(game, town, order, game.world["towns"][tid])
		if not candidate["ok"]:
			if not best["ok"]: best["reason"] = candidate["reason"]
			continue
		if not best["ok"] or int(candidate["quantity"]) > int(best["quantity"]) \
				or (int(candidate["quantity"]) == int(best["quantity"]) and float(candidate["spend"]) / int(candidate["quantity"]) < float(best["spend"]) / int(best["quantity"])):
			best = candidate
	return best

static func _blocked(order: Dictionary, reason: String) -> String:
	order["state"] = "blocked"; order["reason"] = reason
	return ""

## One atomic departure: validate, debit escrow, transfer real stock, then use native
## spawn/sail. A failed sail returns its cargo; any pre-spawn failure is rolled back here.
static func depart(game, tid: String, id: String) -> String:
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	var order := find(town, id)
	if order.is_empty() or order.get("closed", false) or str(order["caravan"]) != "": return ""
	if str(town.get("faction", "")) != str(order["faction"]) or _ruler(game, town) != str(order["issuer"]) \
			or (not order["ai"] and not can_manage(game, tid)):
		_refund(town, order); order["closed"] = true
		return _blocked(order, "Ruler or authority changed; reserve released.")
	if not is_finite(float(order["reserved"])) or float(order["reserved"]) <= 0.0 \
			or float(order["reserved"]) > float(order["cap"]):
		return _blocked(order, "Order funding is unavailable.")
	if Caravans.count(game.world) >= Caravans.max_caravans(game.world):
		return _blocked(order, "All caravan slots are occupied.")
	var q := quote(game, town, order)
	if not q["ok"]: return _blocked(order, str(q["reason"]))
	var source: Dictionary = game.world["towns"][q["source"]]
	var e: Dictionary = source["econ"]
	var market: Dictionary = e["biz"][int(e["mkt"])]
	var cargo := _preset(town, order, q)
	var taken := Goods.take(source, str(order["good"]), int(q["quantity"]))
	cargo["goods"][str(order["good"])] = taken
	if taken != int(q["quantity"]):
		Caravans.unload(source, cargo)
		return _blocked(order, "Source stock changed before departure.")
	var spend := float(q["spend"])
	if spend > float(order["reserved"]):
		Caravans.unload(source, cargo)
		return _blocked(order, "Order funding changed before departure.")
	order["reserved"] = float(order["reserved"]) - spend
	market["till"] = float(market["till"]) + spend
	var wid := Caravans.spawn(game, str(source["id"]), _rng(game.world, order, str(source["id"])), tid, "", cargo)
	if wid == "":
		# _come_home clears the shared preset when sail failed after spawning.
		Caravans.unload(source, cargo)
		cargo["goods"].clear()
		market["till"] = float(market["till"]) - spend
		order["reserved"] = float(order["reserved"]) + spend
		return _blocked(order, "Caravan could not depart (route or available crew).")
	order["spent"] = float(order["spent"]) + spend
	order["loaded"] = taken; order["caravan"] = wid; order["actual_source"] = str(source["id"])
	order["price"] = float(q["price"]); order["freight"] = float(q["freight"])
	order["state"] = "travelling"; order["reason"] = ""; order["depart_day"] = int(game.day)
	e["stats"]["sales"] = float(e["stats"].get("sales", 0.0)) + taken * float(q["price"])
	e["stats"]["trade_out"] = float(e["stats"].get("trade_out", 0.0)) + taken * float(q["price"])
	var wb: Dictionary = game.world["warbands"][wid]
	Caravans.receipt_add(wb, "buy_cost", taken * float(q["price"]))
	wb["receipt"]["supply_paid"] = spend
	return wid

static func _from_band(game, wb: Dictionary) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(str(wb.get("supply_town", "")), {})
	var order := find(town, str(wb.get("supply_order_id", "")))
	return order if str(order.get("caravan", "")) == str(wb.get("id", "")) else {}

## Direct ownership transfer, never a second purchase from the buyer's market.
static func deliver(game, wb: Dictionary) -> void:
	var order := _from_band(game, wb)
	if order.is_empty() or order.get("delivery_done", false): return
	var town: Dictionary = game.world["towns"][str(wb["supply_town"])]
	var cargo: Dictionary = wb["cargo"]
	var good := str(order["good"])
	var quantity := int(cargo["goods"].get(good, 0))
	order["delivery_done"] = true; order["delivered"] = quantity; order["closed"] = true
	wb["supply_delivery_pos"] = wb["pos"]
	Caravans.unload(town, cargo)
	cargo["goods"].clear(); cargo["items"].clear()
	_refund(town, order)
	var e: Dictionary = town["econ"]
	var incoming: Dictionary = e["stats"].get("cargo_in", {})
	incoming[good] = int(incoming.get(good, 0)) + quantity
	e["stats"]["cargo_in"] = incoming
	e["stats"]["trade_in"] = float(e["stats"].get("trade_in", 0.0)) + quantity * float(order["price"])
	if not e.has("why_hint"): e["why_hint"] = {}
	e["why_hint"][good] = "a town supply order"
	if order["state"] != "cancelled": order["state"] = "delivered"
	order["reason"] = "%d/%d delivered; unused reserve released." % [quantity, int(order["quantity"])]
	if order["state"] == "cancelled": order["reason"] = "Cancelled remainder; paid cargo: " + str(order["reason"])
	wb["receipt"]["delivered"] = quantity

## Called only by native loss/plunder paths, which own all destruction/loot ledgers.
static func lost(game, wb: Dictionary) -> void:
	var order := _from_band(game, wb)
	if order.is_empty() or order.get("delivery_done", false): return
	var town: Dictionary = game.world["towns"][str(wb["supply_town"])]
	_refund(town, order)
	order["closed"] = true
	if order["state"] != "cancelled": order["state"] = "blocked"
	order["reason"] = "Caravan lost or raided; paid cargo lost/taken, unused reserve released."
	order["lost"] = int(order["loaded"]) - int(order["delivered"])

## Invoked from the town's existing daily work job; repeat jobs cannot retry twice.
static func daily(game, town: Dictionary, day: int) -> void:
	if orders(town).is_empty() or int(town["econ"].get("supply_day", -1)) >= day: return
	town["econ"]["supply_day"] = day
	for order: Dictionary in orders(town):
		if not order.get("closed", false) and str(order["caravan"]) == "":
			depart(game, str(town["id"]), str(order["id"]))

## One affordable grain order per town/week at most, targeting seven days of food.
## Outstanding orders suppress another purchase; the player's own town is manual.
static func ai_week(game, town: Dictionary, day: int) -> void:
	var e: Dictionary = town["econ"]
	var week := int(floor(float(day) / 7.0))
	if int(e.get("supply_ai_week", -1)) >= week: return
	e["supply_ai_week"] = week
	if can_manage(game, str(town["id"])) or _open(town) > 0 or _ruler(game, town) == "" or TownEcon.days_food(town) >= FOOD_DAYS: return
	var cap := minf(maxf(0.0, float(e["treasury"])) * 0.25, Caravans.PURSE_MAX)
	if cap <= 0.0: return
	var quantity := mini(1000000, maxi(1, int(ceil((FOOD_DAYS - TownEcon.days_food(town)) * float(e["pop"]) * float(TownEcon.data()["needs"]["food"])))))
	var unit_limit := Goods.price_f(town, "grain") * 1.5
	var draft := {"id": "supply%d" % int(game.world.get("next_id", 1)), "good": "grain", "quantity": quantity,
		"max_unit": unit_limit, "source": "best", "reserved": cap}
	if quote(game, town, draft)["ok"]:
		place(game, str(town["id"]), "grain", quantity, unit_limit, cap, "best", true)
