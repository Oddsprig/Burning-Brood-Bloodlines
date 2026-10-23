class_name Supplies
extends RefCounted
## Force stores (Douglas, economy spec 2 additions): every non-monster force carries real counted food and drink
## (wb.stores {grain, fruit, meat, beer, wine}). A faction's field bands and the militia are provisioned from their
## home town's market (the payer pays the market at its price; the goods leave the town's books as used: the
## army's mess). Bandits carry only what they steal. The men eat 2 meals and drink 1 mug a day out of the stores.
## A fight's winner takes the beaten force's stores up to what it can carry (army.carry_kg per man, goods
## weights); the rest is lost on the field. The company takes them into its provisions (core/food.gd) when it
## wins; the company NEVER loses its own stores to an AI winner.

const FOOD := ["meat", "fruit", "grain"]
const DRINK := ["beer", "wine"]

static func A() -> Dictionary:
	return TownEcon.data()["army"]

static func stores(wb: Dictionary) -> Dictionary:
	if not wb.has("stores"):
		wb["stores"] = {}
	return wb["stores"]

static func men(wb: Dictionary) -> int:
	var n := 0
	for u in wb.get("units", []):
		if not u.dead and not u.race_def().get("creature", false):
			n += 1
	return n

static func weight(st: Dictionary) -> float:
	var t: Dictionary = Goods.table()
	var kg := 0.0
	for g in st:
		kg += float(st[g]) * float(t.get(g, {}).get("weight", 0.5))
	return kg

static func capacity(n_men: int) -> float:
	return float(n_men) * float(A()["carry_kg"])

static func days(wb: Dictionary) -> float:
	var n := men(wb)
	if n <= 0:
		return 0.0
	var st := stores(wb)
	var food := 0
	for g in FOOD:
		food += int(st.get(g, 0))
	return float(food) / (2.0 * n)

## The day's meals and mugs out of the stores; a band short of food counts hungry days (wb.hungry).
static func eat(wb: Dictionary) -> void:
	var n := men(wb)
	if n <= 0:
		return
	var st := stores(wb)
	var need := 2 * n
	for g in FOOD:
		var t := mini(need, int(st.get(g, 0)))
		if t > 0:
			st[g] = int(st[g]) - t
			need -= t
	var dn := n
	for g in DRINK:
		var t2 := mini(dn, int(st.get(g, 0)))
		if t2 > 0:
			st[g] = int(st[g]) - t2
			dn -= t2
	for g in st.keys():
		if int(st[g]) <= 0:
			st.erase(g)
	wb["hungry"] = int(wb.get("hungry", 0)) + 1 if need > n else 0

## Top the stores up to store_days from the home market (the payer pays the market). payer as Army.pay_units.
static func provision(game, wb: Dictionary, payer: Dictionary) -> void:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"].get(String(wb.get("home", "")), {})
	if not TownEcon.has_econ(town):
		return
	var n := men(wb)
	if n <= 0:
		return
	var e: Dictionary = town["econ"]
	var st := stores(wb)
	var dd := float(A()["store_days"])
	var room := capacity(n) - weight(st)
	var t: Dictionary = Goods.table()
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var want_food := int(2.0 * n * dd) - (int(st.get("grain", 0)) + int(st.get("fruit", 0)) + int(st.get("meat", 0)))
	var want_drink := int(n * dd) - (int(st.get("beer", 0)) + int(st.get("wine", 0)))
	for pair in [[["grain", "meat", "fruit"], want_food], [["beer", "wine"], want_drink]]:
		var want: int = pair[1]
		for g in pair[0]:
			if want <= 0 or room <= 0.0:
				break
			var p := float(e["price"].get(g, 1.0))
			var kg := float(t[g]["weight"])
			var q := mini(want, mini(int(e["stock"].get(g, 0)), int(room / kg)))
			q = mini(q, int(Army._funds(payer) / maxf(0.01, p)))
			if q <= 0:
				continue
			Army._spend(payer, float(q) * p)
			mkt["till"] = float(mkt["till"]) + float(q) * p
			e["stock"][g] = int(e["stock"][g]) - q
			TownEcon.led(e, "used", g, q)   # out of the town's books: the army's mess
			st[g] = int(st.get(g, 0)) + q
			want -= q
			room -= float(q) * kg

## The winner takes the beaten force's stores up to what it can carry; the rest is lost. Returns {good: n}.
static func take(winner: Dictionary, loser: Dictionary) -> Dictionary:
	var src := stores(loser)
	var dst := stores(winner)
	var room := capacity(men(winner)) - weight(dst)
	var got := _move(src, room, func(g, q): dst[g] = int(dst.get(g, 0)) + q)
	loser["stores"] = {}
	return got

## The company holds the field: the beaten force's food and drink go into its provisions (meals, mugs, cups),
## up to what its men can carry beyond what they already carry.
static func company_take(game, loser: Dictionary) -> Dictionary:
	var src := stores(loser)
	var have := Food.food_weight(game)
	var n := 0
	for u in game.company:
		if not u.dead:
			n += 1
	var room := capacity(n) - have
	var got := _move(src, room, func(g, q):
		if g in FOOD:
			Food.add_stock(game, "meal", q, 0, g, Goods.good_name(g).capitalize())
		else:
			Food.add_stock(game, g, q))
	loser["stores"] = {}
	return got

static func _move(src: Dictionary, room: float, put: Callable) -> Dictionary:
	var t: Dictionary = Goods.table()
	var got := {}
	for g in ["meat", "beer", "wine", "fruit", "grain"]:   # the best first
		var q := int(src.get(g, 0))
		if q <= 0 or room <= 0.0:
			continue
		var kg := float(t[g]["weight"])
		q = mini(q, int(room / kg))
		if q <= 0:
			continue
		put.call(g, q)
		got[g] = q
		room -= float(q) * kg
	return got

## "34 meals, 12 mugs of beer"
static func text(got: Dictionary) -> String:
	var meals := int(got.get("grain", 0)) + int(got.get("fruit", 0)) + int(got.get("meat", 0))
	var parts := []
	if meals > 0: parts.append("%d meals" % meals)
	if int(got.get("beer", 0)) > 0: parts.append("%d mugs of beer" % int(got["beer"]))
	if int(got.get("wine", 0)) > 0: parts.append("%d cups of wine" % int(got["wine"]))
	return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "nothing"

## Named meat and fresh meat out of the company's packed meals. Age stays on the lot. Nothing spoils here.
static func draw_dragon_meat(game, qty: int) -> Dictionary:
	var before := Food.meat_units(game)
	var drawn: Dictionary = Food.take_named(game, Food.MEAT_GOODS, qty)
	drawn["before"] = before
	drawn["after"] = Food.meat_units(game)
	drawn["spoiled"] = int(drawn.get("spoiled", 0))
	return drawn

## Days of named meat packed for marching dragons, against the army's store_days horizon. Pure.
static func dragon_meat_plan(game) -> Dictionary:
	var need_per_day := 0
	var dragons := 0
	for row: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		if not bool(row.get("campaign_march", {}).get("enabled", false)): continue
		if not bool(row.get("alive", false)) or str(row.get("stage", "")) == "egg": continue
		need_per_day += DragonCare.food_need_units(game, row)
		dragons += 1
	var packed := Food.meat_units(game)
	var days_needed := float(A()["store_days"]) if dragons > 0 else 0.0
	var days_packed := float(packed) / float(need_per_day) if need_per_day > 0 else 0.0
	var units_needed := need_per_day * int(A()["store_days"]) if need_per_day > 0 else 0
	var short := need_per_day > 0 and packed < units_needed
	var line := "No marching dragon needs packed meat."
	if dragons > 0:
		line = "Dragon meat: %.1f days packed, %.0f days needed." % [days_packed, days_needed]
		if short: line += " Shortfall: the packed meat will not last the march."
	return {"dragons": dragons, "need_per_day": need_per_day, "packed": packed,
		"days_packed": days_packed, "days_needed": days_needed, "units_needed": units_needed,
		"short": short, "line": line}

## Prehistory stores (world gen, old saves): what the band set out with.
static func seed_stores(wb: Dictionary) -> void:
	var n := men(wb)
	if n <= 0 or not stores(wb).is_empty():
		return
	var dd := int(A()["store_days"])
	wb["stores"] = {"grain": 2 * n * dd * 3 / 4, "meat": 2 * n * dd / 4, "beer": n * dd}
