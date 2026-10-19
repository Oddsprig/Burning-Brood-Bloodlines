class_name EconomyRules
extends RefCounted
## Accounting helpers shared by all households and businesses.

## Emergency meals substitute by price before spending a scarce household purse.
## The quote and the purchase must use the same order.
static func food_order(e: Dictionary) -> Array:
	var goods: Array = ["grain", "fruit", "meat", "fresh_meat"]
	var prices: Dictionary = e.get("price", {})
	goods.sort_custom(func(a, b): return float(prices.get(a, INF)) < float(prices.get(b, INF)))
	return goods

## Pure quote of the same staple order and retail prices as cover_food.
## Barn reserves are private physical stock, not freely purchasable food.
static func essential_food_cost(e: Dictionary, meals: float) -> float:
	var left := maxf(0.0, meals)
	var cost := 0.0
	var fallback := 0.0
	var last_available := 0.0
	for good in food_order(e):
		var unit := float(e.get("price", {}).get(good, 0.0)) * TownEcon.markup()
		if unit <= 0.0: continue
		if fallback <= 0.0: fallback = unit
		var barn := maxf(0.0, float(e.get("barn", {}).get(good, 0.0)))
		if e.get("harvest_book") is Dictionary:
			var free := 0.0
			for goods in e["harvest_book"].get("balances", {}).values():
				var row: Array = goods.get(good, [0.0, 0.0])
				free += maxf(0.0, float(row[0]) - float(row[1]))
			barn = minf(barn, floorf(free + HarvestClaims.EPS))
		var have := maxf(0.0, float(e.get("stock", {}).get(good, 0.0))) + barn
		if have > 0.0: last_available = unit
		var take := minf(left, have)
		cost += take * unit
		left -= take
		if left <= 0.0: break
	# An empty market does not make the essential reserve zero. Quote the
	# last staple on offer, or the first priced staple awaiting replenishment.
	return cost + left * (last_available if last_available > 0.0 else fallback)

static func buy_essential(e: Dictionary, f: Dictionary, good: String, meals: int, store: String, rate: float) -> int:
	if meals <= 0 or rate <= 0: return 0
	var bought := 0
	for from_barn in [false, true]:
		var source: Dictionary = e["barn"] if from_barn else e["stock"]
		var unit := float(e["price"].get(good, 0)) * TownEcon.markup()
		if unit <= 0: continue
		var n := mini(meals - bought, mini(HarvestClaims.available(e, good) if from_barn else int(source.get(good, 0)), int(float(f["purse"]) / unit)))
		if n <= 0: continue
		var taken := HarvestClaims.take(e, good, n) if from_barn else {}
		if not from_barn: source[good] = int(source[good]) - n
		var paid := n * unit
		f["purse"] = float(f["purse"]) - paid
		if from_barn: HarvestClaims.credit(e, taken["shares"], paid)
		else: e["biz"][int(e["mkt"])]["till"] += paid
		e["stats"]["sales"] += paid
		e["hh"][good] = int(e["hh"].get(good, 0)) + n
		f["store"][store] += float(n) / rate
		Barge.add_demand(e, good, n, 0, 0)
		bought += n
	return bought

static func cover_food(e: Dictionary, f: Dictionary, days: float, day: float) -> void:
	var rate := float(Families.daily_rates(e, f)["food"])
	if rate <= 0: return
	Families.keep_harvest(e, f, int(ceil(maxf(0.0, days - float(f["store"]["food"])) * rate)), rate)
	for good in food_order(e):
		var gap := maxf(0, days - float(f["store"]["food"]))
		if gap <= 0: break
		buy_essential(e, f, good, int(ceil(gap * rate)), "food", rate)
	# A stocked-out shop is still wanted. Record the remaining affordable
	# order once, after all food substitutions, so zero sales cannot erase
	# staple demand, lower farm wages and stop the broker restocking barns.
	var short_meals: float = maxf(0.0, days - float(f["store"]["food"])) * rate
	if short_meals > 0.0:
		for good in food_order(e):
			var unit: float = float(e["price"].get(good, 0.0)) * TownEcon.markup()
			if unit <= 0.0: continue
			var affordable: float = minf(short_meals, floorf(maxf(0.0, float(f["purse"])) / unit))
			Barge.add_demand(e, good, 0.0, affordable, short_meals - affordable)
			break
	if float(f["store"]["food"]) >= days or not Herds.has(e): return
	# Owners choose their least valuable healthy animals first. Every head and yield uses the existing ledger.
	var choices := []
	for h in Herds.herds(e).values():
		if String(h["ow"]) != "f" or int(h["oi"]) != int(f["id"]) or Herds.sick(h) > 0: continue
		for age in Herds.AGES:
			if int(h[age]) > 0 and float(Herds.yields(String(h["k"]), age).get("fresh_meat", 0)) > 0:
				choices.append([Herds.price(e, String(h["k"]), age), h, age])
	choices.sort_custom(func(a, b): return a[0] < b[0])
	for choice in choices:
		var h: Dictionary = choice[1]
		var age := String(choice[2])
		while int(h[age]) > 0 and float(f["store"]["food"]) < days:
			Herds.change(e, h, age, -1, "slaughtered", "household needed food", day)
			var goods := Herds.yields(String(h["k"]), age)
			var out := {}
			for good in goods: out[good] = int(floor(float(goods[good])))
			var meat := int(out.get("fresh_meat", 0))
			var keep := mini(meat, int(ceil(maxf(0, days + float(Herds.A()["larder_days"]) - float(f["store"]["food"])) * rate)))
			f["store"]["food"] += float(keep) / rate
			e["hh"]["meat"] = int(e["hh"].get("meat", 0)) + keep
			TownEcon.led(e, "made", "meat", keep)
			out["fresh_meat"] = meat - keep
			Herds._sell(e, h, out, float(TownEcon.data()["market"]["broker_share"]))

static func wood_available(e: Dictionary) -> float:
	var P: Dictionary = e.get("plots", {})
	if P.is_empty(): return 0
	var total := 0.0
	for i in Plots.count(P):
		if int(P["use"][i]) == Plots.WOOD:
			total += maxf(0, float(P["st"][i])) * float(P["ac"][i]) * Plots.LOADS_PER_ACRE
	var made := int(e.get("led", {}).get("made", {}).get("wood", 0))
	return maxf(0, total - maxi(0, made - int(P.get("wood_seen", made))))

static func farm_hand_value(e: Dictionary, f: Dictionary) -> float:
	var D := TownEcon.data()
	var L: Dictionary = D["land"]
	var prices: Dictionary = e.get("price", {}) # Initial hiring precedes the first market price book.
	var climate: Dictionary = D["climates"].get(String(e.get("climate", "temperate")), {})
	var revenue := 0.0
	for crop in f["land"]:
		var yield_v := CropRotation.family_yield(e, f, String(crop))
		if crop in ["grain", "fruit"]: yield_v *= float(climate.get(crop + "_yield", 1))
		revenue += float(f["land"][crop]) * yield_v * float(prices.get(crop, D["goods"].get(crop, {}).get("price", 0))) / EconGen.YEAR_DAYS
	for animal in f["herd"]:
		for good in D["herds"].get(animal, {}):
			revenue += float(f["herd"][animal]) * float(D["herds"][animal][good]) * float(prices.get(good, D["goods"].get(good, {}).get("price", 0)))
	return maxf(0, revenue / maxf(1, Families.need_hands(f, e)))

## Skilled work keeps a higher band and is not discounted for surplus staff.
const SKILLED_WORK := ["smelter", "weaponsmith", "armorsmith", "carpenter", "weaver", "tailor",
	"tanner", "butcher", "salter", "dairy", "chandler", "bowyer", "fletcher", "leatherworker",
	"brewer", "vintner", "jeweler", "herbalist", "mint", "academy"]

static func skilled_work(b: Dictionary) -> bool:
	return String(b["type"]) in SKILLED_WORK

## Adult cash wages are a labour-market price, never capped by output value.
## Revenue and cash determine whether the employer can sustain these places.
static func wage_limit(e: Dictionary, b: Dictionary, offered: float) -> float:
	var day: float = Barge.day_wage(e)
	if skilled_work(b):
		var table: Dictionary = TownEcon.data()["businesses"][b["type"]]
		var premium: float = maxf(1.15, float(table["wage"]) / float(Barge.B()["labour"]["base"]))
		return clampf(offered, day * premium, day * premium * 1.8)
	return clampf(offered, day * 0.6, day * 1.8)

static func record_receipts(b: Dictionary, before: float, workers: int) -> void:
	if workers <= 0: return
	var receipts: Array = b.get("net_receipts", [])
	receipts.append((float(b["till"]) - before) / workers)
	while receipts.size() > 14: receipts.pop_front()
	b["net_receipts"] = receipts

static func clear_surplus(e: Dictionary, good: String) -> void:
	if not e["price"].has(good): return
	var stock := float(e["stock"].get(good, 0)) + float(e["barn"].get(good, 0))
	var need := maxf(1, float(e.get("need", {}).get(good, 0)))
	if stock <= need: return
	var base := float(TownEcon.data()["goods"][good]["price"]) * Barge.pl(e)
	# A stock-based clearing quote, rather than an arbitrary discount or production freeze.
	e["price"][good] = minf(float(e["price"][good]), base * need / stock)
