class_name Economy
extends RefCounted
## Towns' crafting, shops and prices. The company never crafts: every town rolls its own named
## weaponsmith and armorsmith (DF-style skill 0-15) at world generation; shop quality comes from
## their skill and prices skew by the town's specialty.

const REFRESH_DAYS := 7.0
const SELL_FRACTION := 0.4
const SKILL_RANKS := ["Dabbling", "Novice", "Adequate", "Competent", "Skilled", "Proficient", "Talented",
	"Adept", "Expert", "Professional", "Accomplished", "Great", "Master", "High Master", "Grand Master", "Legendary"]
const SIZE_NAMES := ["hamlet", "village", "town", "large town", "city"]
const WEALTH_NAMES := ["", "poor", "modest", "comfortable", "rich", "opulent"]
const SPECIALTY_DESC := {
	"mining": "Miners' town: metal is cheap and the smiths know their trade.",
	"farming": "Farming country: linen everywhere, metal dear, the smithing a side trade.",
	"trade": "Trading town: goods from every neighbour, fair prices.",
	"military": "Garrison town: weapons are plentiful and well made.",
	"timber": "Timber town: hafts and shields come cheap.",
	"herding": "Herders' town: leather is cheap.",
}

static func rank_name(skill: int) -> String:
	return SKILL_RANKS[clampi(skill, 0, 15)]

static func size_name(size: int) -> String:
	return SIZE_NAMES[clampi(size, 0, 4)]

# ------------------------------------------------------------------ crafters
static func _person(rng: RandomNumberGenerator, race: String, title: String, skill: int) -> Dictionary:
	skill = clampi(skill, 0, 15)
	return {"name": Factory.random_name(rng, race), "skill": skill, "rank": rank_name(skill), "title": title}

static func make_crafters(town: Dictionary, rng: RandomNumberGenerator) -> void:
	var race: String = DB.factions[town["faction"]]["race"]
	var size := int(town["size"])
	var base: float = [2.0, 4.0, 6.5, 9.0, 12.0][clampi(size, 0, 4)]
	var bw := 0.0; var ba := 0.0
	match town["specialty"]:
		"mining": bw = 2.0; ba = 2.0
		"military": bw = 2.0; ba = 1.0
		"trade": bw = 0.5; ba = 0.5
		"farming": bw = -1.5; ba = -1.5
		"timber": bw = 1.0
		"herding": ba = 0.5
	var ws := int(round(base + bw + rng.randfn(0.0, 1.3)))
	var as_ := int(round(base + ba + rng.randfn(0.0, 1.3)))
	var crafters := {}
	if town["specialty"] == "farming" and size <= 1:
		# one part-time smith does both jobs
		var p := _person(rng, race, "part-time smith", mini(ws, as_))
		crafters["weaponsmith"] = p
		crafters["armorsmith"] = p.duplicate()
	else:
		crafters["weaponsmith"] = _person(rng, race, "weaponsmith", ws)
		crafters["armorsmith"] = _person(rng, race, "armorsmith", as_)
	town["crafters"] = crafters
	town["healer"] = _person(rng, race, "healer", int(round(base * 0.8 + rng.randfn(0.0, 1.5))))

# ------------------------------------------------------------------ prices
static func _is_metal(mat: String) -> bool:
	return DB.materials.get(mat, {}).get("kind", "") == "metal"

static func roll_prices(town: Dictionary, rng: RandomNumberGenerator) -> void:
	var wealth := int(town["wealth"])
	var wm := 0.85 + 0.06 * wealth
	var spec: String = town["specialty"]
	var mp := {"copper": 1.0, "tin": 1.0, "linen": 1.0, "leather": 1.0}
	match spec:
		"mining": mp["copper"] = 0.8; mp["tin"] = 0.75
		"farming": mp["linen"] = 0.55; mp["leather"] = 0.8; mp["copper"] = 1.15; mp["tin"] = 1.15
		"herding": mp["leather"] = 0.6; mp["linen"] = 0.85
		"trade":
			for k in mp: mp[k] = 0.95
	town["material_prices"] = mp
	var prices := {}
	var culture: String = town["culture"]
	for tid in DB.weapons.keys() + DB.armor.keys():
		var t := DB.template(tid)
		var m := wm * (1.0 + rng.randfn(0.0, 0.06))
		if t.get("culture", "") not in [culture, "common"]:
			m *= 1.25 if spec != "trade" else 1.1
		var is_shield: bool = t.get("slot", "") == "shield"
		var hafted: bool = t.get("skill", "") in ["spear", "polearm"]
		match spec:
			"military":
				if DB.is_weapon(tid): m *= 0.88
			"timber":
				if is_shield or hafted: m *= 0.82
		prices[tid] = snappedf(clampf(m, 0.5, 2.0), 0.01)
	town["prices"] = prices

## Base value of an item in this town before the company's appraiser and standing: template value x the town's
## price roll x its material price (with an economy: the metal's bar price over base) x scarcity of gear on
## the stalls. The market pays producers a share of this (economy spec: smiths sell to the market).
static func base_value(town: Dictionary, item: Item) -> float:
	var m: float = float(town.get("prices", {}).get(item.tid, 1.0))
	m *= float(town.get("material_prices", {}).get(item.material, 1.0))
	if TownEcon.has_econ(town):
		var bars: String = TownEcon.data()["metal_bars"].get(item.material, "")
		if bars != "":
			m *= clampf(0.7 + 0.3 * Goods.price_mult(town, bars), 0.8, 1.5)   # moves with the day's bar price only
		if DB.is_bow(item.tid):   # bows: dearer when the town is short of bows or of seasoned staves
			m *= BowsEcon.bow_price_mult(town)
	return item.value() * m

## Shop price of an item in a town (what the player pays). appraiser = the company's best Appraiser
## (Game.best_skill("appraiser")): -0.5% per level, lightly (tuned).
static func price(town: Dictionary, item: Item, appraiser: int = 0) -> int:
	var m := base_value(town, item)
	m *= 1.0 - 0.005 * clampi(appraiser, 0, 20)
	if DB.factions.has(town.get("faction", "")):
		m *= Diplomacy.price_mult(Game, town["faction"])   # diplomacy: x(1 - standing/500)
	m *= rep_mult(town)
	return maxi(1, int(round(m)))

## Town-level standing (economy spec 9: raiding this town's caravans costs it): prices x(1 - rep/400).
static func rep_mult(town: Dictionary) -> float:
	if not TownEcon.has_econ(town):
		return 1.0
	return 1.0 - clampf(float(town["econ"].get("rep", 0)), -100.0, 100.0) / 400.0

## What the town pays the player for an item (+0.5% per Appraiser level).
## Diplomacy: x(1 + standing/500), and +5% for goods of a trade-pact partner's culture.
static func sell_price(town: Dictionary, item: Item, appraiser: int = 0) -> int:
	var fid: String = town.get("faction", "")
	var base: float = base_value(town, item)
	if DB.factions.has(fid):
		base *= Diplomacy.sell_mult(Game, fid) * _pact_goods_mult(town, item)
	return maxi(1, int(round(base * SELL_FRACTION * (1.0 + 0.005 * clampi(appraiser, 0, 20)) * (1.0 - 0.15 * item.wear))))

## Diplomacy TRADE_PACT: +5% sell price for goods made by a partner faction's culture.
static func _pact_goods_mult(town: Dictionary, item: Item) -> float:
	var cul: String = item.tmpl().get("culture", "")
	for f in DB.factions:
		if f != town["faction"] and DB.factions[f].get("culture", "") == cul \
				and Diplomacy.state(Game.world, f, town["faction"]) in [Diplomacy.TRADE_PACT, Diplomacy.ALLIANCE]:
			return 1.05
	return 1.0

static func appraiser_of(game) -> int:
	return game.best_skill("appraiser") if game.has_method("best_skill") else 0

static func buy(game, town: Dictionary, item: Item) -> bool:
	if not Diplomacy.can_trade(game, town.get("faction", "")):
		return false   # diplomacy: towns of a hostile faction refuse trade
	var p := price(town, item, appraiser_of(game))
	if game.gold < p or not town["shop"].has(item):
		return false
	game.gold -= p
	Goods.pay_market(town, float(p))   # economy: the gold goes to the town's market
	town["shop"].erase(item)
	game.stash.append(item)
	game.changed.emit()
	return true

static func sell(game, town: Dictionary, item: Item) -> int:
	if not game.stash.has(item):
		return 0
	if not Diplomacy.can_trade(game, town.get("faction", "")):
		return 0   # diplomacy: towns of a hostile faction refuse trade
	var p := sell_price(town, item, appraiser_of(game))
	if float(p) > Goods.market_gold(town):
		return 0   # economy: the merchants cannot afford it
	Goods.pay_market(town, -float(p))
	game.gold += p
	game.stash.erase(item)
	town["shop"].append(item)
	game.changed.emit()
	return p

# ------------------------------------------------------------------ shop stock
static func _pool(culture: String, weapons: bool) -> Array:
	return (DB.weapons_by_culture if weapons else DB.armor_by_culture).get(culture, [])

static func roll_shop(town: Dictionary, rng: RandomNumberGenerator) -> Array:
	return roll_shop_n(town, rng, 4 + int(town["size"]) * 3 + (2 if town["specialty"] == "trade" else 0))

## n pieces of earlier smith work (world generation only: the economy's opening arms stock; from then on
## gear only comes from smiths spending bars).
static func roll_shop_n(town: Dictionary, rng: RandomNumberGenerator, n: int) -> Array:
	var wealth := int(town["wealth"])
	var spec: String = town["specialty"]
	var foreign_chance := 0.35 if spec == "trade" else 0.15
	var common_chance := 0.45 if spec == "farming" else 0.15
	var copper_chance := clampf(0.3 + 0.1 * wealth + (0.25 if spec == "mining" else 0.0), 0.0, 0.95)
	var neigh: Array = town.get("neighbours", [])
	var out := []
	for i in n:
		var culture: String = town["culture"]
		var foreign := false
		if not neigh.is_empty() and rng.randf() < foreign_chance:
			culture = neigh[rng.randi() % neigh.size()]
			foreign = true
		var pool: Array
		var r := rng.randf()
		if r < common_chance:
			pool = _pool("common", false)
		elif r < common_chance + (0.5 if spec == "military" else 0.4):
			pool = _pool(culture, true)
		else:
			pool = _pool(culture, false)
		if pool.is_empty():
			pool = _pool("common", false)
		var tid: String = pool[rng.randi() % pool.size()]
		var t := DB.template(tid)
		var mats: Array = ["copper", "tin"] if DB.is_weapon(tid) else t.get("materials", ["copper", "tin"])
		var mat: String = mats[0]
		if mats.has("copper") and mats.has("tin"):
			mat = "copper" if rng.randf() < copper_chance else "tin"
		var smith: Dictionary = town["crafters"]["weaponsmith" if DB.is_weapon(tid) else "armorsmith"]
		var skill := float(smith.get("skill", 2))
		if foreign:
			skill = 5.0     # imported goods: middling work
		elif not _is_metal(mat):
			skill *= 0.5    # tailoring and leatherwork are side jobs
		out.append(Item.make(tid, mat, Factory.roll_quality(rng, skill)))
	return out

## Periodic refresh: new recruits, new contracts. Towns with an economy (all generated towns) get their shop
## stock only from their smiths (town_econ.gd); stand-in towns without one keep the old rolled stock.
static func refresh_town(town: Dictionary, day: float, rng: RandomNumberGenerator) -> void:
	if not TownEcon.has_econ(town):
		var keep := []
		for it in town.get("shop", []):
			if rng.randf() < 0.33:
				keep.append(it)
		town["shop"] = keep + roll_shop(town, rng)
	town["recruits"] = Recruits.generate_pool(town, rng)
	town["contracts"] = Contracts.generate_offers(town, day, rng)
	town["next_refresh"] = day + REFRESH_DAYS

## Short human-readable lines for the town screen.
static func describe_town(town: Dictionary) -> String:
	var f: Dictionary = DB.factions.get(town["faction"], {})
	var known := ""
	if TownEcon.has_econ(town):
		var sp := []
		for s in town["econ"].get("specialties", []):
			sp.append(TownEcon.data()["specialties"][s]["text"])
		if not sp.is_empty():
			known = " Known for its %s." % " and ".join(PackedStringArray(sp))
	return "%s, a %s %s of the %s. %s%s" % [town["name"], WEALTH_NAMES[clampi(int(town["wealth"]), 1, 5)],
		size_name(int(town["size"])), f.get("name", "?"), SPECIALTY_DESC.get(town["specialty"], ""), known]

static func describe_crafter(c: Dictionary) -> String:
	return "%s, %s %s (skill %d)" % [c.get("name", "?"), c.get("rank", "?"), c.get("title", ""), int(c.get("skill", 0))]
