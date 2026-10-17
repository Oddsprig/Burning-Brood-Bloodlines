class_name BowsEcon
extends RefCounted
## bows (docs/specs/bows.md section 6): bows and arrows in the real town economy. Rule zero holds: goods and gold
## only move by production, use, trade, loss, raids and wages.
## - BOWYER (data/economy.json row): splits bow-grade staves out of the town's wood stock (6 loads of cut wood give
##   one green stave), which season for months (SEASON_DAYS); makes bows (Items on the arms stalls, each culture its
##   own styles, data/bows.json "inputs" and "rate") part-time when the town is short of bows.
## - FLETCHER: arrows from wood (shafts need no seasoning), feathers (the hunt, barnyard fowl) and the smiths'
##   arrowheads (weaponsmiths make them part-time when they are wanted). Both buy from the same wood stock as
##   firewood, builders and carpenters: a short town raises the price ("short of wood").
## - Horn and sinew come from the herds and the hunt (economy.json herds/hunter), glue from the tanner.
## - SUPPLY TARGETS: the town head's armory keeps days of use of arrows for the archers its town arms (militia and
##   every force with this home town): full quivers + ARROW_USE_DAY x TARGET_DAYS each. Its standing orders raise the
##   arrows' price when short; it buys from the market with the treasury, refills the militia's quivers and loses
##   arrows to practice and wear. The town wants spare bows (BOW_SPARE per archer): short = bowyers make bows and the
##   bows' price rises. Forces raised from a town fill their quivers from its market (outfit_units), ordering any
##   shortfall. The company fills quivers from its own stock (world.company_goods) and recovers arrows from a held field.

const SEASON_DAYS := 120.0     # [ours] staves season for some months: 1/120 of the green staves are ready each day
const FOWL_FEATHERS := 0.004   # [ours] bundles of feathers (100) a day per worked acre of grain (barnyard fowl)
const ARROW_USE_DAY := 0.5     # [ours] arrows an archer spends a day in practice, wear and loss
const TARGET_DAYS := 30.0      # [ours] the armory keeps this many days of use beyond full quivers
const ARMORY_BASE := 60        # [ours] arrows a town head keeps on hand with no archers at all
const BOW_SPARE := 0.3         # [ours] spare bows on the stalls per archer the town arms
const TIP_SHARE := 0.25        # [ours] share of a weaponsmith's day on arrowheads while the fletchers want them
const BOW_MAKE_SHARE := 0.6    # [ours] share of a bowyer's day on bows (else splitting staves) while bows are short
const KIND_SHARES := [0.6, 0.4]   # [ours] the culture's preferred arrow and its second
const ARMORY_SPEND := 0.05     # [ours] at most this share of the treasury goes on arrows in a day

static func culture_arrows(town: Dictionary) -> Array:
	return DB.culture_arrows.get(String(town.get("culture", "middle")), DB.culture_arrows.get("middle", []))

static func arrow_ids() -> Array:
	return DB.arrows.keys()

# =====================================================================================================
# world generation and old saves
# =====================================================================================================
## Bowyer and fletcher rows (Businesses._row), owned by town families. Own RNG: world gen rolls stay as they were.
static func gen_businesses(town: Dictionary, e: Dictionary, D: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(town.get("id", "")), "bows-biz"])
	var fams: Array = e["fams"]
	var owners := []
	for f in fams:
		if not f.get("estate", false):
			owners.append(int(f["id"]))
	if owners.is_empty():
		return
	# v0.014: a family that owns no shop yet keeps the new one (Businesses.free_first)
	var free := []
	for fid in owners:
		if (fams[int(fid)]["owns"] as Array).is_empty() and not fams[int(fid)].get("gone", false):
			free.append(fid)
	if not free.is_empty():
		owners = free
	var size := int(town.get("size", 0))
	var cul := String(town.get("culture", "middle"))
	# v0.014 (Douglas 21:12: "multiple boweyers in one town.... no"): one bowyer; a big town's second bowyer of old is
	# more places in the one shop
	var bowyers := 1 + (1 if size >= 3 else 0)
	var cap := 2 + size / 2 + (1 if cul == "moon_elf" else 0)
	var b: Dictionary = Businesses._row(e, "bowyer", owners[rng.randi() % owners.size()], cap * bowyers, D)
	b["skill"] = clampi(rng.randi_range(2, 7) + (2 if cul == "moon_elf" else 0), 0, 15)
	Businesses._row(e, "fletcher", owners[rng.randi() % owners.size()], 2 + size / 2 + (1 if cul in ["moon_elf", "goblin"] else 0), D)

## Opening stocks (pre-history): staves seasoning and seasoned, arrows, heads, feathers, horn, sinew, glue, a few bows.
static func opening_stocks(town: Dictionary, e: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(town.get("id", "")), "bows-stock"])
	var size := int(town.get("size", 0))
	var st: Dictionary = e["stock"]
	st["staves"] = 4 + 3 * size
	st["staves_green"] = 6 + 3 * size
	st["heads_copper"] = 60 + 20 * size
	st["heads_tin"] = 30 + 10 * size
	st["feathers"] = 6 + 2 * size
	for g in ["horn", "sinew", "glue"]:
		st[g] = 3 + size
	var kinds := culture_arrows(town)
	for i in kinds.size():
		st[kinds[i]] = int(st.get(kinds[i], 0)) + (120 + 60 * size if i == 0 else 60 + 30 * size)
	var arm := {}
	if not kinds.is_empty():
		arm[kinds[0]] = 100 + 50 * size
	e["armory"] = arm
	var shop: Array = town.get("shop", [])
	var pool := Businesses.gear_pool(String(town.get("culture", "middle")), "bow")
	if not pool.is_empty():
		for i in 1 + size:
			var it := Item.make(pool[rng.randi() % pool.size()], "wood", Factory.roll_quality(rng, 4.0))
			it.vr = Factory.roll_bow_variance(rng, 4.0)
			shop.append(it)
	town["shop"] = shop

## Older saves: towns without bowyers or fletchers get them; the armory is created.
static func after_load(_w: Dictionary, town: Dictionary) -> void:
	if not TownEcon.has_econ(town):
		return
	var e: Dictionary = town["econ"]
	var has := false
	for b in e["biz"]:
		if b["type"] == "bowyer" or b["type"] == "fletcher":
			has = true
			break
	if not has:
		gen_businesses(town, e, TownEcon.data())
		Businesses.rebuild_open(e)
	if not e.has("armory"):
		e["armory"] = {}
	var arm: Dictionary = e["armory"]
	for k in arm:
		arm[k] = int(arm[k])

# =====================================================================================================
# daily (TownEcon.daily_pass)
# =====================================================================================================
static func econ_daily(game, town: Dictionary, e: Dictionary, _D: Dictionary) -> void:
	_season(e)
	_fowl(e)
	_armory(game, town, e)
	_wood_hint(e)

## Green staves season: a share of them becomes seasoned each day (production from time; ledgered).
static func _season(e: Dictionary) -> void:
	var st: Dictionary = e["stock"]
	var green := int(st.get("staves_green", 0))
	if green <= 0:
		return
	var carry: Dictionary = e["carry"]
	var amt := float(green) / SEASON_DAYS + float(carry.get("bows_season", 0.0))
	var n := mini(green, int(floor(amt)))
	carry["bows_season"] = amt - n
	if n > 0:
		st["staves_green"] = green - n
		st["staves"] = int(st.get("staves", 0)) + n
		TownEcon.led(e, "used", "staves_green", n)
		TownEcon.led(e, "made", "staves", n)

## Barnyard fowl on the grain farms: feathers into the barns.
## v0.012: a town whose herds are records has real poultry (Herds: feathers plucked at slaughter and gathered from
## the living birds), so this stand-in runs only for older towns without them (no feathers counted twice).
static func _fowl(e: Dictionary) -> void:
	if Herds.has(e):
		return
	var acres := float(e.get("wacres", {}).get("grain", 0.0))
	if acres <= 0.0:
		return
	var carry: Dictionary = e["carry"]
	var previous := float(carry.get("bows_fowl", 0.0))
	var produced := acres * FOWL_FEATHERS
	var amt := produced + previous
	var n := int(floor(amt))
	carry["bows_fowl"] = amt - n
	var weights := {}
	for f in e.get("fams", []):
		weights["f:%d" % int(f["id"])] = float(f.get("land", {}).get("grain", 0)) * float(f.get("worked", 0.0))
	HarvestClaims.harvest(e, "feathers", "bows_fowl", weights, produced, n, 0, previous, int(e.get("day", 0)))
	if n > 0: TownEcon.led(e, "made", "feathers", n)

## Same living supported population as the equipment reserve; includes professional
## guards and the largest active origin caravan, rather than militia alone.
static func archers(game, tid: String) -> int:
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	return int(ArmsTrade.arrow_requirement(game, town) / DB.QUIVER_MAX) if not town.is_empty() else 0

## The head's armory: standing orders (days of use), purchases from the market, practice/wear, militia refills.
static func _armory(game, town: Dictionary, e: Dictionary) -> void:
	if not e.has("armory"):
		e["armory"] = {}
	var arm: Dictionary = e["armory"]
	var tid := String(town.get("id", ""))
	var n := archers(game, tid) if game != null and game.get("world") != null else 0
	var kinds := culture_arrows(town)
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var req: Dictionary = e["req"]
	var carry: Dictionary = e["carry"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var G: Dictionary = TownEcon.data()["goods"]
	var tgt_total := ArmsTrade.reserve_amount(n * DB.QUIVER_MAX)
	e["arrow_reserve"] = tgt_total
	var remaining := maxi(0, tgt_total - ArmsTrade.arrow_stock(town))
	var budget := maxf(0.0, float(e["treasury"]) - ArmsTrade.arms_reserve(game, town, e)) * ARMORY_SPEND
	var preferences: Array = kinds.duplicate()
	var other: Array = DB.arrows.keys(); other.sort()
	for k in other:
		if not preferences.has(k): preferences.append(k)
	# Prefer the cultural mix, then fill any remaining aggregate reserve with
	# valid arrows actually available. Foreign arrows work in the same quiver.
	for pass_no in 2:
		for i in preferences.size():
			var k: String = preferences[i]
			var have := int(arm.get(k, 0))
			var sh: float = KIND_SHARES[mini(i, KIND_SHARES.size() - 1)] if i < kinds.size() else 0.0
			var wanted := remaining if pass_no == 1 else mini(remaining, maxi(0, int(ceil(float(tgt_total) * sh)) - have))
			if pass_no == 0 and i < kinds.size(): req[k] = float(req.get(k, 0.0)) + float(wanted) / 7.0
			var p := maxf(0.01, float(price.get(k, G.get(k, {}).get("price", 0.4))))
			var q := mini(wanted, mini(int(st.get(k, 0)), int(budget / p)))
			if q > 0:
				st[k] = int(st[k]) - q; arm[k] = have + q; remaining -= q
				var cost := float(q) * p
				budget -= cost; e["treasury"] = float(e["treasury"]) - cost
				mkt["till"] = float(mkt["till"]) + cost
				e["stats"]["sales"] = float(e["stats"]["sales"]) + cost
				TownEcon.led(e, "used", k, q)
	# Existing drill consumption uses the preferred mix and actual stored stock.
	var mil := Militia.band_of(game, tid) if game != null else {}
	for i in kinds.size():
		var k: String = kinds[i]
		var sh: float = KIND_SHARES[mini(i, KIND_SHARES.size() - 1)]
		var ck: String = "bows_use_" + k
		var practice := float(n) * ARROW_USE_DAY * sh if mil.get("drill_today", false) else 0.0
		var amt := practice + float(carry.get(ck, 0.0))
		var use := mini(int(floor(amt)), int(arm.get(k, 0)))
		carry[ck] = minf(amt - use, 5.0)
		if use > 0: arm[k] = int(arm[k]) - use
	if game != null and game.get("world") != null:
		for u in TownDefence.garrison(game, tid):
			if u.dead or not u.equip.has("ranged"): continue
			for k in preferences:
				var room: int = DB.QUIVER_MAX - u.arrows()
				if room <= 0: break
				var q := mini(room, int(arm.get(k, 0)))
				if q > 0:
					arm[k] = int(arm[k]) - q; u.quiver[k] = int(u.quiver.get(k, 0)) + q
	# spare bows the town wants on its stalls
	e["bow_target"] = int(ceil(float(n) * BOW_SPARE)) + 1 + int(town.get("size", 0)) / 2

## "short of wood": the price reason for arrows and staves when the fletchers or bowyers stand idle for wood.
static func _wood_hint(e: Dictionary) -> void:
	for b in e["biz"]:
		if (b["type"] == "fletcher" or b["type"] == "bowyer") and b.get("state", "") == "inputs" and b.get("why", "") == "wood":
			if not e.has("why_hint"):
				e["why_hint"] = {}
			var hints: Dictionary = e["why_hint"]
			for g in (["staves_green", "staves"] if b["type"] == "bowyer" else DB.arrows.keys()):
				hints[g] = "short of wood"
			return

# =====================================================================================================
# businesses (Businesses.daily hooks)
# =====================================================================================================
static func bows_on_stalls(town: Dictionary) -> int:
	var n := 0
	for it in town.get("shop", []):
		if DB.is_bow(it.tid):
			n += 1
	return n

static func bows_wanted(town: Dictionary, e: Dictionary) -> bool:
	return bows_on_stalls(town) < int(e.get("bow_target", 2))

static func tips_wanted(e: Dictionary) -> bool:
	var price: Dictionary = e.get("price", {})
	var G: Dictionary = TownEcon.data()["goods"]
	for g in ["heads_copper", "heads_tin"]:
		if float(price.get(g, 0.0)) >= float(G[g]["price"]) * 1.15:
			return true
	return false

## Share of an arms business's worker-days on its arms (the rest runs its recipes).
static func arms_share(town: Dictionary, e: Dictionary, kind: String) -> float:
	if kind == "weapon":
		return 1.0 - (TIP_SHARE if tips_wanted(e) else 0.0)
	if kind == "bow":
		return BOW_MAKE_SHARE if bows_wanted(town, e) else 0.0
	return 1.0

## The bowyer's bows: each bow takes 1/rate worker-days of its style (composites are slowest) and its inputs.
static func make_bows(town: Dictionary, e: Dictionary, D: Dictionary, b: Dictionary, wd: float, toolf: float, spec: float,
		rng: RandomNumberGenerator, mkt: Dictionary, bdem: Dictionary) -> float:
	var pool := Businesses.gear_pool(String(town.get("culture", "middle")), "bow")
	if pool.is_empty():
		b["state"] = "idle"
		return 0.0
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var shop: Array = town.get("shop", [])
	var share := float(D["market"]["arms_buy_share"])
	var prog := float(b.get("bowp", 0.0)) + wd * toolf * spec
	var spent := 0.0
	var made := 0
	var start := rng.randi() % pool.size()
	while made < 3:
		# the first style (from a rolled one) whose inputs the bins hold
		var tid := ""
		var missing := ""
		for k in pool.size():
			var cand: String = pool[(start + k) % pool.size()]
			var gi := Businesses.gear_inputs(cand, "wood")
			var ok := true
			for ig in gi:
				if int(st.get(ig, 0)) < int(gi[ig]):
					ok = false
					if missing == "":
						missing = ig
					bdem[ig] = float(bdem.get(ig, 0.0)) + float(gi[ig])
			if ok:
				tid = cand
				break
		if tid == "":
			b["state"] = "inputs"
			b["why"] = missing
			break
		var t: Dictionary = DB.bows[tid]
		var need := 1.0 / maxf(0.01, float(t.get("rate", 0.4)))
		if prog < need:
			break
		var ins := Businesses.gear_inputs(tid, "wood")
		var cost := 0.0
		for ig in ins:
			bdem[ig] = float(bdem.get(ig, 0.0)) + float(ins[ig])
			cost += float(ins[ig]) * float(price.get(ig, 1.0))
		if float(b["till"]) < cost:
			b["state"] = "wages"
			b["why"] = "money for staves"
			break
		var skill := float(b.get("skill", 3)) + (3.0 if spec > 1.0 else 0.0)
		var it := Item.make(tid, "wood", Factory.roll_quality(rng, skill, true))   # v0.014: a real bowyer may make a legendary bow
		it.vr = Factory.roll_bow_variance(rng, skill)
		ArmsTrade.mark(it, town, b)   # arms trade: the bowyer's mark
		if it.is_legend():
			Legends.forge(Game, town, e, b, it, rng, float(e.get("day", 0)))
		var value := Economy.base_value(town, it) * share
		if it.is_legend():
			value = minf(value, maxf(0.0, float(mkt["till"])))
		if float(mkt["till"]) < value:
			b["state"] = "nopay"
			break
		for ig in ins:
			st[ig] = int(st[ig]) - int(ins[ig])
			TownEcon.led(e, "used", ig, int(ins[ig]))
		b["till"] = float(b["till"]) - cost + value
		mkt["till"] = float(mkt["till"]) + cost - value
		mkt["spend"] = float(mkt["spend"]) + value
		e["stats"]["sales"] = float(e["stats"]["sales"]) + cost
		spent += cost
		shop.append(it)
		TownEcon.led(e, "made", "arms", 1)
		prog -= need
		made += 1
	b["bowp"] = minf(prog, 3.0)
	town["shop"] = shop
	return spent

## Bow price multiplier: short of bows on the stalls (vs the town's target) and the price of seasoned staves.
static func bow_price_mult(town: Dictionary) -> float:
	if not TownEcon.has_econ(town):
		return 1.0
	var e: Dictionary = town["econ"]
	var tgt := float(e.get("bow_target", 2))
	var have := float(bows_on_stalls(town))
	return clampf(sqrt(tgt / maxf(have, 0.5)), 0.6, 2.5) * clampf(0.7 + 0.3 * Goods.price_mult(town, "staves"), 0.8, 1.6)

# =====================================================================================================
# forces and the company
# =====================================================================================================
## A force raised from a town (TownEcon.outfit_units): its archers' quivers come out of the town's market stock
## (the treasury pays; the spawned arrows never existed); any shortfall is ordered (raises the price).
static func fill_quivers(town: Dictionary, units: Array) -> void:
	for u in units:
		if u is Unit:
			u.quiver.clear()
	if not TownEcon.has_econ(town):
		return
	var e: Dictionary = town["econ"]
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var kinds := culture_arrows(town).duplicate()
	for k in DB.arrows:
		if not kinds.has(k):
			kinds.append(k)
	for u in units:
		if not u is Unit or not u.equip.has("ranged"):
			continue
		for k in kinds:
			var room: int = DB.QUIVER_MAX - u.arrows()
			if room <= 0:
				break
			var p := float(price.get(k, 0.4))
			var t := mini(room, int(st.get(k, 0)))
			t = mini(t, int(maxf(0.0, float(e["treasury"])) / maxf(p, 0.01)))
			if t <= 0:
				continue
			st[k] = int(st[k]) - t
			u.quiver[k] = int(u.quiver.get(k, 0)) + t
			e["treasury"] = float(e["treasury"]) - float(t) * p
			mkt["till"] = float(mkt["till"]) + float(t) * p
			e["stats"]["sales"] = float(e["stats"]["sales"]) + float(t) * p
			TownEcon.led(e, "used", k, t)
		var short: int = DB.QUIVER_MAX - u.arrows()
		if short > 0 and not kinds.is_empty():
			var req: Dictionary = e["req"]
			req[kinds[0]] = float(req.get(kinds[0], 0.0)) + float(short)   # the order for what the stalls lacked

## The company's archers fill their quivers from the company's own arrows (world.company_goods) before a battle.
static func fill_company_quivers(game) -> void:
	var cg := Goods.company_goods(game)
	for u in game.deployed_units():
		if u.bow() == null:
			continue
		var order: Array = u.quiver.keys()
		for k in DB.arrows:
			if not order.has(k):
				order.append(k)
		for k in order:
			var room: int = DB.QUIVER_MAX - u.arrows()
			if room <= 0:
				break
			var t := mini(room, int(floor(float(cg.get(k, 0.0)))))
			if t <= 0:
				continue
			cg[k] = float(cg[k]) - t
			if float(cg[k]) < 0.01:
				cg.erase(k)
			u.quiver[k] = int(u.quiver.get(k, 0)) + t

## The company holds the field: recovered arrows (broken ones are scrap), the beaten enemy's quivers and its own dead
## men's quivers go to the company's stock. Returns {arrow id: n} gained.
static func after_battle(game, result: Dictionary, looted: Dictionary) -> Dictionary:
	var got := {}
	if int(result.get("winner", -1)) != 0:
		return got
	var rec := Archery.recovered(result.get("arrow_field", {}))
	for k in rec:
		got[k] = int(got.get(k, 0)) + int(rec[k])
	for k in looted:
		got[k] = int(got.get(k, 0)) + int(looted[k])
	for u in game.company:
		if u.dead and not u.quiver.is_empty():
			for k in u.quiver:
				got[k] = int(got.get(k, 0)) + int(u.quiver[k])
			u.quiver.clear()
	for k in got:
		Goods.add_to_company(game, k, float(got[k]))
	return got

## The company buys arrows (or any good) from a town's market at its price. Returns the number bought.
static func buy_for_company(game, town: Dictionary, g: String, qty: int) -> int:
	var st := Goods._stock(town)
	var p := Goods.price_f(town, g)
	var n := mini(qty, int(st.get(g, 0)))
	n = mini(n, int(floor(float(game.gold) / maxf(p, 0.01))))
	if n <= 0:
		return 0
	var cost := mini(game.gold, int(ceil(p * n)))   # whole coins (an arrow costs a fraction of one)
	st[g] = int(st[g]) - n
	game.gold -= cost
	Goods.pay_market(town, float(cost))
	if TownEcon.has_econ(town):
		TownEcon.led(town["econ"], "used", g, n)   # out of the town's ledgers into the company's stock
	Goods.add_to_company(game, g, float(n))
	game.changed.emit()
	return n
