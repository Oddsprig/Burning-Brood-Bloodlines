class_name Goods
extends RefCounted
## Bulk goods: the read side of the town economy for menus, Food and caravans (table: data/economy.json
## "goods"; the economy itself is campaign/town_econ.gd). A town's market stock is town.econ.stock
## {good: int}; prices are real (supply and need). "food" is the three foods together (grain, fruit, meat),
## the way the company buys meals.
##
## Towns without an economy (dev/test stand-ins) keep a plain town.goods {good: int} with fixed-target prices.
## The company's own bulk goods (from raids) are world.company_goods = {good: quantity}; they sell to a town's
## market at that town's price (the market pays from its till).

const SELL_FRACTION := 0.9   # the market buys at its buy share of the price
const FOODS := ["grain", "fruit", "meat"]

static func table() -> Dictionary:
	return TownEcon.data()["goods"]

## Tradeable goods (everything but new homes), sorted.
static func ids() -> Array:
	var out := []
	for k in table():
		if not table()[k].get("no_trade", false):
			out.append(k)
	out.sort()
	return out

static func good_name(g: String) -> String:
	if g == "food":
		return "food"
	return table().get(g, {}).get("name", g)

static func unit_of(g: String) -> String:
	if g == "food":
		return "meals"
	return table().get(g, {}).get("unit", "loads")

static func _stock(town: Dictionary) -> Dictionary:
	if TownEcon.has_econ(town):
		return town["econ"]["stock"]
	if not town.has("goods"):
		town["goods"] = {}
	return town["goods"]

## Units of good g (or "food") for sale in the town's market.
static func supply(town: Dictionary, g: String) -> float:
	var st := _stock(town)
	if g == "food":
		var n := 0.0
		for k in FOODS:
			n += float(st.get(k, 0))
		return n
	return float(st.get(g, 0))

## What the town wants on hand (need x target days); fixed for towns without an economy.
static func target(town: Dictionary, g: String) -> float:
	if TownEcon.has_econ(town):
		var need: Dictionary = town["econ"].get("need", {})
		if g == "food":
			var n := 0.0
			for k in FOODS:
				n += float(need.get(k, 0.0))
			return n
		return maxf(1.0, float(need.get(g, 0.0)))
	return 40.0 * (1.0 + 0.5 * int(town.get("size", 0))) * (3.0 if g == "food" else 1.0)

## Price per unit as a float (what the market charges).
static func price_f(town: Dictionary, g: String) -> float:
	if g == "food":
		# the cheapest food on the stalls feeds a man as well as any
		var best := INF
		for k in FOODS:
			if supply(town, k) >= 1.0:
				best = minf(best, price_f(town, k))
		return best if best < INF else price_f(town, "grain")
	var base := float(table().get(g, {}).get("price", 1.0))
	if TownEcon.has_econ(town):
		return float(town["econ"]["price"].get(g, base))
	return base * clampf(sqrt(target(town, g) / maxf(supply(town, g), 0.5)), 0.5, 3.0)

## Price over base (1.0 = normal); for "food" the cheapest food's.
static func price_mult(town: Dictionary, g: String) -> float:
	if g == "food":
		var best := INF
		for k in FOODS:
			if supply(town, k) >= 1.0:
				best = minf(best, price_f(town, k) / float(table()[k]["price"]))
		return best if best < INF else 3.0
	return price_f(town, g) / float(table().get(g, {}).get("price", 1.0))

static func price(town: Dictionary, g: String) -> int:
	return maxi(1, int(round(price_f(town, g))))

static func sell_price(town: Dictionary, g: String) -> int:
	return maxi(1, int(round(price_f(town, g) * SELL_FRACTION)))

## Takes n units out of the market (for "food": the most plentiful food first). Returns units taken.
static func take(town: Dictionary, g: String, n: int) -> int:
	var st := _stock(town)
	if g != "food":
		var t := mini(n, int(st.get(g, 0)))
		st[g] = int(st.get(g, 0)) - t
		return t
	var got := 0
	while got < n:
		var best := ""; var bv := 0
		for k in FOODS:
			if int(st.get(k, 0)) > bv:
				bv = int(st[k]); best = k
		if best == "":
			break
		var t2 := mini(n - got, maxi(1, bv / 2))
		st[best] = int(st[best]) - t2
		got += t2
	return got

## Gold paid to (or by) the town's market for a trade with the company.
static func pay_market(town: Dictionary, gold: float) -> void:
	if TownEcon.has_econ(town):
		var e: Dictionary = town["econ"]
		var m: Dictionary = e["biz"][int(e["mkt"])]
		m["till"] = float(m["till"]) + gold
		e["stats"]["sales"] = float(e["stats"]["sales"]) + maxf(0.0, gold)
		TownEcon.gold_out(-gold)   # the company sits outside the town ledgers

static func market_gold(town: Dictionary) -> float:
	if TownEcon.has_econ(town):
		var e: Dictionary = town["econ"]
		return float(e["biz"][int(e["mkt"])]["till"])
	return INF

## Plain stock for a town without an economy (dev town, tests): a few weeks of food and drink.
static func init_town(town: Dictionary) -> void:
	if TownEcon.has_econ(town):
		return
	var s := 1.0 + 0.5 * int(town.get("size", 0))
	town["goods"] = {"grain": int(60 * s), "fruit": int(15 * s), "meat": int(20 * s), "beer": int(40 * s), "wine": int(15 * s)}

## Legacy hook (pre-economy daily goods tick); the town economy runs from the work queue now.
static func daily(_game, _town: Dictionary) -> void:
	pass

static func level_word(town: Dictionary, g: String) -> String:
	var r := supply(town, g) / maxf(1.0, target(town, g))
	if r < 0.25: return "scarce"
	if r < 0.7: return "short"
	if r < 1.4: return "enough"
	return "plenty"

## "Food: 34 days (well supplied), beer: 12 days, wine: 20 days" for the town header.
static func summary(town: Dictionary) -> String:
	if not TownEcon.has_econ(town):
		return "Food: %s, drink: %s" % [level_word(town, "food"), level_word(town, "beer")]
	var e: Dictionary = town["econ"]
	var ad := maxf(1.0, float(e["adults"]))
	return "Food: %d days (%s), %s: %d days, %s: %d days" % [int(TownEcon.days_food(town)),
		TownEcon.supply_word(TownEcon.supply_level(town)), TownEcon.label(e, "beer"),
		int((float(e["stock"].get("beer", 0)) + float(e["hh"].get("beer", 0))) / ad / EconGen.beer_share_of(e)),
		TownEcon.label(e, "wine"), int((float(e["stock"].get("wine", 0)) + float(e["hh"].get("wine", 0))) / ad / maxf(0.1, 1.0 - EconGen.beer_share_of(e)))]

# ------------------------------------------------------------------ company goods store
static func company_goods(game) -> Dictionary:
	if not game.world.has("company_goods"):
		game.world["company_goods"] = {}
	return game.world["company_goods"]

static func add_to_company(game, g: String, qty: float) -> void:
	var cg := company_goods(game)
	cg[g] = float(cg.get(g, 0.0)) + qty

## Sell `qty` of the company's goods in a town; the market pays from its till and the goods join its stock.
static func sell(game, town: Dictionary, g: String, qty: int) -> int:
	var cg := company_goods(game)
	qty = mini(qty, int(floor(float(cg.get(g, 0.0)))))
	if qty <= 0:
		return 0
	var st := _stock(town)
	var gold := 0
	var sold := 0
	for i in qty:   # each unit sold lowers the price a little
		var p := sell_price(town, g)
		if float(p) > market_gold(town):
			break
		gold += p
		pay_market(town, -float(p))
		st[g] = int(st.get(g, 0)) + 1
		sold += 1
		if TownEcon.has_econ(town):
			var e: Dictionary = town["econ"]
			e["price"][g] = float(table()[g]["price"]) * clampf(sqrt(maxf(1.0, float(e["need"].get(g, 0.0))) / maxf(0.5, float(st[g]) + float(e["barn"].get(g, 0)))), float(TownEcon.data()["price_min"]), float(TownEcon.data()["price_max"]))
	cg[g] = float(cg[g]) - sold
	if float(cg[g]) < 0.01:
		cg.erase(g)
	game.gold += gold
	game.changed.emit()
	return gold
