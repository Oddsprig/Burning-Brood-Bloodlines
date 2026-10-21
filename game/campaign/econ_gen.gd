class_name EconGen
extends RefCounted
## World generation for the town economy (docs/specs/economy-1-town.md section 2): climate from latitude,
## ore deposits, crops and herds, specialties, the culture row, families (land, herds, homes, purses, goods),
## family-owned businesses, the political head, and the opening stocks. Everything a town owns at the start
## is "pre-history" production; from day 1 goods only appear by production (rule zero).
##
## town["econ"] layout (all plain values, saved with the world):
##   climate, lat, terrain {forest, water, hills}, crops {grain: variety, fruit: variety}, herd_kinds [animal],
##   deposits {copper_ore: richness, tin_ore: richness}, specialties [id], culture
##   stock {good: int} market stock | barn {good: int} harvest stores (landholders') | granary int (town grain)
##   price {good: float} | why {good: text} | pweek {good: price a week ago}
##   fams [family] (index = id; families[0] is the town estate) | biz [business] (index = id)
##   land {crop: acres owned} | herd {animal: head} | wacres {crop: acres x worked} | wherd {animal: head x worked}
##   cum {crop|"herd": gold per acre/head since the start} | farm_till: barn sales not yet claimed by owners
##   hh {good: int}: what the households hold, summed | pop, adults, homes, room
##   treasury, knowhow {material: 0-100}, tax {season, leak}, head {name, title, fam}, orders [[fam, good, qty]]
##   led {made, used, spoil}: per-good ledgers (conservation), hist [lines], stats {...}

const YEAR_DAYS := 4 * Calendar.DAYS_PER_SEASON
## World-gen town size lever (Douglas 03:05, "we can increase residents, acreage, plots"): families per town (and the
## 150 cap) x this; the fields and herds follow the people, so land per head stays the same. 1.0 = the v0.009 sizes.
const TOWN_SCALE := 1.0
## Tests and diagnostics may set this (null = TOWN_SCALE).
static var town_scale_override = null

static func town_scale() -> float:
	return float(town_scale_override) if town_scale_override != null else TOWN_SCALE

static func generate(w: Dictionary, town: Dictionary, rng: RandomNumberGenerator) -> void:
	var D := TownEcon.data()
	var e := {"v": 1, "faction": String(town.get("faction", "")),
		"identity_scope": "%d:%s" % [int(w.get("seed", 0)), String(town.get("id", ""))]}
	town["econ"] = e
	var cul_id: String = town.get("culture", "middle")
	if not D["cultures"].has(cul_id):
		cul_id = "middle"
	e["culture"] = cul_id
	var cul: Dictionary = D["cultures"][cul_id]
	# ---------------------------------------------------------------- climate, terrain, deposits
	var map_h: float = float(w.get("h", WorldGen.H)) * float(w.get("cell", WorldGen.CELL))
	var lat := Calendar.latitude(town["pos"], map_h)
	e["lat"] = snappedf(lat, 0.01)
	e["climate"] = "cold" if lat > float(D["cold_lat"]) else ("hot" if lat < float(D["hot_lat"]) else "temperate")
	# v0.012: the dry eastern band (WorldGen.dryness): a town there is "dry" whatever its latitude
	var dry := WorldGen.dryness_at(town["pos"])
	if dry > 0.0:
		e["dry"] = snappedf(dry, 0.01)
	if dry >= float(D.get("dry_min", 0.5)) and D["climates"].has("dry"):
		e["climate"] = "dry"
	var clim: Dictionary = D["climates"][e["climate"]]
	var terr := _terrain_near(w, town)
	e["terrain"] = terr
	var spec: String = town.get("specialty", "")
	var deps := _deposits(w, town, int(terr["hill_cells"]), spec)   # v0.014: each city its own mix, from its ground
	e["deposits"] = deps
	# ---------------------------------------------------------------- crops, herds (1-3 varieties)
	var grains: Array = clim["grain"]
	var fruits: Array = clim["fruit"]
	e["crops"] = {"grain": grains[rng.randi() % grains.size()], "fruit": fruits[rng.randi() % fruits.size()]}
	# v0.012 (spec 1 A): the grazing herds follow the culture's start mix (data animals.start), not the climate
	var hmix := herd_mix(e, D)
	var hk: Array = hmix.keys()
	hk.sort_custom(func(a, b): return float(hmix[a]) > float(hmix[b]) if float(hmix[a]) != float(hmix[b]) else String(a) < String(b))
	e["herd_kinds"] = hk
	# ---------------------------------------------------------------- specialties (1-2)
	e["specialties"] = _pick_specialties(town, e, rng)
	# ---------------------------------------------------------------- families
	var ts := town_scale()
	var nf := mini(int(round(150.0 * ts)), int(round(float(D["families_by_size"][clampi(int(town["size"]), 0, 4)]) * ts * rng.randf_range(0.9, 1.05))))
	var race: String = cul.get("race", "human")
	var fams := []
	fams.append(Families.make_estate(town))
	var used := {}
	var tracked_count := mini(Population.TRACKED_HOUSEHOLDS, nf)
	for i in tracked_count:
		var nf_f := Families.make_family(fams.size(), race, cul, rng, used)
		nf_f["cul"] = cul_id   # v0.012: the family's own culture (its babies' names), kept wherever it moves
		fams.append(nf_f)
	var represented := nf * Population.INITIAL_SCALE - tracked_count
	for pool_i in mini(Population.POOLS, represented):
		var group := Families._blank(fams.size())
		group["name"] = "%s common households %d" % [town["name"], pool_i + 1]
		group["cul"] = cul_id; group["seed"] = rng.randi(); group["households"] = 0
		var share := represented / Population.POOLS + (1 if pool_i < represented % Population.POOLS else 0)
		for h in share:
			var native := Families.make_family(-1, race, cul, rng, {})
			for field in ["m", "f", "kids", "old", "homes", "purse"]: group[field] += native[field]
			group["households"] += 1
		fams.append(group)
	e["fams"] = fams
	for f in fams:
		if f.has("households"): Population.initialize(e, f)
	# The same real ages used for household meals must exist before food acreage
	# is sized. These household/pregnancy RNG streams are independent of land.
	for f in fams:
		Persons.generate(e, f, 0.0)
		Persons.gen_preg(e, f, 0.0)
	var pop := 0; var adults := 0
	for f in fams:
		pop += Families.people(f); adults += int(f["m"]) + int(f["f"])
	# ---------------------------------------------------------------- land and herds (sized from the town's needs)
	var needs: Dictionary = D["needs"]
	var land: Dictionary = D["land"]
	var eaters := food_eaters(e)
	# barge: the diet follows the race's staple tastes (Barge.diet: staples by taste, meat and produce as the rest)
	var dt := Barge.diet(e)
	var farm_mult: float = {"farming": 1.35, "herding": 1.0, "timber": 0.95, "trade": 0.85, "mining": 0.8, "military": 0.9}.get(spec, 1.0)
	farm_mult *= rng.randf_range(0.95, 1.2)
	var gy := CropRotation.mean_yield(e) * float(clim["grain_yield"])
	var fy := float(land["yield"]["fruit"]) * float(clim["fruit_yield"])
	var drink_year := float(adults) * float(needs["drink_adult"]) * YEAR_DAYS
	var beer_share := beer_share_of(e)
	var grain_acres := (eaters * float(dt["grain"]) * YEAR_DAYS + drink_year * beer_share * 0.5) / gy * farm_mult * 1.45
	var fruit_acres := (eaters * float(dt["fruit"]) * YEAR_DAYS + drink_year * (1.0 - beer_share)) / fy * farm_mult * 1.4
	var flax_acres := float(pop) / 180.0 * 2.0 * 2.0 * YEAR_DAYS / float(land["yield"]["flax"]) * 0.7
	var meat_day := eaters * float(dt["meat"]) * farm_mult
	var head_total := 0.0
	var meat_per_head := 0.0
	var share_sum := 0.0
	for a in hk:
		meat_per_head += float(D["herds"].get(a, {}).get("meat", 0.1)) * float(hmix[a])
		share_sum += float(hmix[a])
	meat_per_head /= maxf(0.0001, share_sum)
	head_total = meat_day * 0.75 / maxf(0.05, meat_per_head)   # hunters and fishers bring the rest
	head_total *= float(_start_row(e, D).get("head_mult", 1.0))   # (moon elves: few meat beasts, kept long)
	Families.distribute_land(e, fams, {"grain": grain_acres, "fruit": fruit_acres, "flax": flax_acres}, head_total, hk, rng, hmix)
	e["territory"] = TownEcon.land_total(e)   # the town's territory = its land pool at world gen (all held by families then)
	Barge.gen_oxen(e)   # farm families plough with oxen (one per 8 acres)
	# ---------------------------------------------------------------- businesses
	Businesses.generate(w, town, e, D, rng)
	BowsEcon.gen_businesses(town, e, D)   # bows: bowyer and fletcher rows (own rng)
	Barge.gen_mint(town, e)   # coinage: a mint in the realm's seat and mining towns
	Academy.gen_town(town, e)   # v0.012: the state's research house in the capital (its lead is named in Academy.init_world)
	Sickness.gen_businesses(town, e, D)   # sickness: the herbalist row (own rng; hires from idle hands at their turns)
	Herds.gen_town(w, town, e, D)   # herds as records, small stock, the herder, butcher, salter, dairy, chandler, salt works, drover (own rng)
	# v0.014: every row made (one per trade), the trades get the hands the people can give, each with its keeper
	Population.generated_business_owners(e)
	Businesses.fit_to_people(e)
	# ---------------------------------------------------------------- jobs (keepers, land, own business, then hire)
	Families.assign_all(e)
	for f in fams:
		Persons.track_jobs(e, f, 0.0)   # the places they hold when the world begins
	# ---------------------------------------------------------------- classes, cash, renting, the ruler (barge part 1 1b)
	TownEcon.recount(e)
	var brng := RandomNumberGenerator.new()
	brng.seed = hash([int(w.get("seed", 0)), String(town.get("id", "")), "barge-gen"])   # own stream: the rolls above stay
	Barge.gen_town(w, town, e, brng)
	# ---------------------------------------------------------------- head of the town (richest family, named)
	var head := Families.richest(e)
	var head_fam: Dictionary = fams[head]
	head_fam["named"] = true
	head_fam["purse"] = float(head_fam["purse"]) + 400.0 * TownEcon.COIN * (int(town["size"]) + 1)
	var title: String = cul["capital_title"] if town.get("capital", false) else cul["head_title"]
	# Keep the inherited name draw so every later generation roll stays in order;
	# the displayed office holder is the real registered adult, never that draw.
	Families.person_name(head_fam, rng, String(cul.get("names", race)))
	e["head"] = {"name": "", "title": title, "fam": head}
	Dynasty.bind_head(town)
	Families.add_hist(head_fam, "Holds the %s's seat in %s." % [title, town["name"]], 0.0)
	# ---------------------------------------------------------------- opening stocks
	_opening_stocks(town, e, D, rng)
	BowsEcon.opening_stocks(town, e)   # bows: staves, arrows, heads, feathers, horn, sinew, glue, a few bows (own rng)
	Herds.opening_stocks(town, e)   # herds: salt for a month of salting, candles, tallow (pre-history)
	TownEcon.recount(e)
	# know-how: towns with both copper and tin know bronze a little; trade capitals have heard of it
	var kh: Dictionary = D["knowhow"]["bronze"]
	var bk := 0.0
	if deps.has("copper_ore") and deps.has("tin_ore"):
		bk = float(kh["start_both"]) * rng.randf_range(0.7, 1.3)
	elif town.get("capital", false) and spec == "trade":
		bk = float(kh["start_trade"])
	e["knowhow"] = {"bronze": snappedf(bk, 0.1)}
	e["tax"] = {"season": TownEcon.season_stamp(0.0), "leak": 0.0, "paid": 0.0, "owed": 0.0}
	e["req"] = {}
	e["need"] = {}
	e["rich"] = 0
	e["hist"] = []
	e["stats"] = {"sales": 0.0, "tax_in": 0.0, "pop_hist": [e["pop"]], "trade_out": 0.0, "trade_in": 0.0}
	e["led"] = {"made": {}, "used": {}, "spoil": {}}
	e["carry"] = {}
	e["why"] = {}
	e["price"] = {}
	e["pweek"] = {}
	e["bdem"] = {}
	e["rep"] = 0
	e["day"] = 0
	# opening demand: what the households use (business wants join from the first market day)
	e["dem"] = TownEcon.household_use(e, 0)
	for g in TownEcon.data()["goods"]:
		if not e["dem"].has(g):
			e["dem"][g] = 0.0
	# barge: every price starts at its base (PL 1, index 1 at start); supply as demand
	for g in TownEcon.data()["goods"]:
		e["price"][g] = float(TownEcon.data()["goods"][g]["price"])
	e["sup"] = (e["dem"] as Dictionary).duplicate()
	e["need"] = {}
	for g in e["dem"]:
		e["need"][g] = float(e["dem"][g]) * float(Barge.cat(g)["target"])
	e["pweek"] = (e["price"] as Dictionary).duplicate()
	HarvestClaims.opening(e)

## Adult meal equivalents, using the household's existing age shares exactly
## once. Reserving home-grown food changes its destination, not mouths to feed.
static func food_eaters(e: Dictionary) -> float:
	var total := 0.0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false): continue
		total += float(Barge.eaters(e, f, 0.0)[0])
	return total

## The culture's start row (data animals.start; a culture with none uses the middle row).
static func _start_row(e: Dictionary, D: Dictionary) -> Dictionary:
	var S: Dictionary = D["animals"].get("start", {})
	return S.get(String(e.get("culture", "middle")), S.get("middle", {}))

## v0.012 (spec 1 A): the town's grazing herds at world gen by its culture: {kind: share} (data animals.start graze;
## a "valley" kind only where the town has valley land, water nearby: the dwarves' cattle). Shares at world gen only:
## after that the owners buy, sell and breed by market and land. Falls back to the climate's herds (equal shares).
static func herd_mix(e: Dictionary, D: Dictionary) -> Dictionary:
	var row := _start_row(e, D)
	var valley: Array = row.get("valley", [])
	var vale := bool(e.get("terrain", {}).get("water", false))
	var out := {}
	var g: Dictionary = row.get("graze", {})
	for k in g:
		if float(g[k]) <= 0.0 or not D["animals"]["kinds"].has(k) or (valley.has(k) and not vale):
			continue
		out[k] = float(g[k])
	if out.is_empty():
		for k2 in D["climates"][e["climate"]]["herds"]:
			out[k2] = 1.0
	return out

## Drink split: beer from grain, "wine" from the town's fruit (cider, perry, wine, fig wine).
static func beer_share_of(e: Dictionary) -> float:
	match e.get("climate", "temperate"):
		"hot": return 0.45
		"cold": return 0.85
		"dry": return 0.6   # v0.012 [ours]: millet beer and the dry land's wine
	return 0.75

static func _terrain_near(w: Dictionary, town: Dictionary) -> Dictionary:
	var c := WorldGen.cell_of(town["pos"])
	var terr: String = w.get("terrain", "")
	var n := {"f": 0, "w": 0, "h": 0}
	var rr := roundi(4 * WorldGen.K)   # 4 BASE cells around the town at any map size (war pick 5's 1.5x map)
	if terr != "":
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				var x := c.x + dx; var y := c.y + dy
				if x < 0 or y < 0 or x >= WorldGen.W or y >= WorldGen.H:
					continue
				match terr[WorldGen.idx(x, y)]:
					"f", "s": n["f"] += 1
					"w": n["w"] += 1
					"h", "m": n["h"] += 1
	for k in n:   # counted in BASE cells
		n[k] = int(round(n[k] / (WorldGen.K * WorldGen.K)))
	return {"forest": n["f"] >= 4, "water": n["w"] >= 3, "hills": n["h"] >= 3, "hill_cells": n["h"], "forest_cells": n["f"]}

static func _pick_specialties(town: Dictionary, e: Dictionary, rng: RandomNumberGenerator) -> Array:
	var cands := []
	var deps: Dictionary = e["deposits"]
	if deps.has("tin_ore"): cands.append("tin")
	if deps.has("copper_ore"): cands.append("copper")
	match town.get("specialty", ""):
		"farming": cands.append("wine" if e["climate"] == "hot" else "ale")
		"herding": cands.append("wool" if e["herd_kinds"].has("sheep") else "leather")
		"timber": cands.append_array(["timber", "furniture"])
		"military": cands.append_array(["weapons", "armor"])
		"trade": cands.append("cloth")
		"mining": cands.append_array(["weapons", "armor"])
	if e["terrain"]["water"]: cands.append("fish")
	if e["terrain"]["forest"]: cands.append("game")
	if cands.is_empty():
		cands = ["ale"]
	var out := [cands[0] if rng.randf() < 0.7 else cands[rng.randi() % cands.size()]]
	if cands.size() > 1 and rng.randf() < 0.5:
		var s2: String = cands[rng.randi() % cands.size()]
		if not out.has(s2):
			out.append(s2)
	return out

## Opening stocks: the market holds a few weeks of everyday goods, the barns hold last year's harvest until
## the autumn, households hold a fortnight, and the stalls carry the smiths' earlier work.
## v0.014 (Douglas 22:26-22:27: "various different cities, asymmetrical economy"; "not every city has all - an extreme
## rarity"): a city's deposits come from the ground around it (data deposits, chances [ours]), each kind rolled on its
## own from its own random stream: copper, iron and flux by the hill and mountain cells near the city (a mining town,
## 6+ hill cells, some hills, flat; flat land still has bog iron and chalk or limestone), tin only near the world's few
## tin belts (granite country, like Cornwall or Bohemia: tin_belts points on hill or mountain cells, tin_belt_r of the
## map's width), so bronze needs trade. No cap: all four together is rare because each is. A mining town with nothing
## gets its likeliest ore (copper or iron), since it was founded on one. A dwarf hold is dug where the iron is.
static func _deposits(w: Dictionary, town: Dictionary, hillish: int, spec: String) -> Dictionary:
	var P: Dictionary = TownEcon.data()["deposits"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(town.get("id", "")), "deposits"])
	var band := 3 if spec == "mining" else (2 if hillish >= 6 else (1 if hillish >= 1 else 0))
	var in_belt := false
	var r := float(P["tin_belt_r"]) * float(WorldGen.W * WorldGen.CELL)
	for c in tin_belts(w):
		if (town["pos"] as Vector2).distance_to(Vector2(float(c[0]), float(c[1]))) <= r:
			in_belt = true
	var deps := {}
	for k in ["copper_ore", "iron_ore", "flux", "tin_ore"]:
		var ch: float = float(P[k][band])
		if k == "tin_ore" and not in_belt:
			ch = float(P["tin_out"]) if band > 0 else 0.0
		if k == "iron_ore" and String(town.get("culture", "")) == "dwarf":
			ch = 1.0
		if rng.randf() < ch:
			deps[k] = snappedf(rng.randf_range(0.5, 1.5), 0.01)
	if spec == "mining" and deps.is_empty():
		deps["copper_ore" if rng.randf() < 0.5 else "iron_ore"] = snappedf(rng.randf_range(0.5, 1.5), 0.01)
	return deps

## The world's tin belts (once per world, kept in w.tin_belts): points on hill or mountain cells, from their own stream.
static func tin_belts(w: Dictionary) -> Array:
	if w.has("tin_belts"):
		return w["tin_belts"]
	var P: Dictionary = TownEcon.data()["deposits"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), "tin-belts"])
	var terr: String = w.get("terrain", "")
	var out := []
	var tries := 0
	while out.size() < int(P["tin_belts"]) and tries < 5000:
		tries += 1
		var x := rng.randi_range(0, WorldGen.W - 1); var y := rng.randi_range(0, WorldGen.H - 1)
		if terr == "" or terr[WorldGen.idx(x, y)] in ["h", "m"]:
			out.append([(x + 0.5) * WorldGen.CELL, (y + 0.5) * WorldGen.CELL])
	w["tin_belts"] = out
	return out

static func _opening_stocks(town: Dictionary, e: Dictionary, D: Dictionary, rng: RandomNumberGenerator) -> void:
	TownEcon.recount(e)
	var pop := float(e["pop"]); var adults := float(e["adults"]); var homes := float(e["homes"])
	var needs: Dictionary = D["needs"]
	var mix: Dictionary = needs["food_mix"]
	var clim: Dictionary = D["climates"][e["climate"]]
	var food_day := pop * float(needs["food"])
	var bs := beer_share_of(e)
	var st := {}
	for g in D["goods"]:
		st[g] = 0
	st["grain"] = int(food_day * float(mix["grain"]) * 12.0)
	st["fruit"] = int(food_day * float(mix["fruit"]) * 6.0)
	st["meat"] = int(food_day * float(mix["meat"]) * 6.0)
	st["beer"] = int(adults * bs * 10.0)
	st["wine"] = int(adults * (1.0 - bs) * 12.0)
	st["wood"] = int(homes * float(needs["firewood_home"]) * float(clim["firewood"]) * 14.0) + 60
	st["stone"] = 30 + rng.randi_range(0, 40)
	st["flax"] = int(pop * 0.1); st["wool"] = int(pop * 0.05); st["hides"] = int(pop * 0.03)
	st["linen"] = int(pop * 0.03); st["wool_cloth"] = int(pop * 0.02); st["leather"] = int(pop * 0.03)
	st["clothing"] = int(pop * 0.03); st["blankets"] = int(homes * 0.03); st["tools"] = int(adults * 0.05) + 2
	st["furniture"] = int(homes * 0.05)
	var deps: Dictionary = e["deposits"]
	st["copper_ore"] = 40 if deps.has("copper_ore") else 0
	st["tin_ore"] = 30 if deps.has("tin_ore") else 0
	st["copper_bars"] = 40 + (60 if deps.has("copper_ore") else 0) + 10 * int(town["size"])
	st["tin_bars"] = 30 + (50 if deps.has("tin_ore") else 0) + 10 * int(town["size"])
	st["bronze_bars"] = 10 if deps.has("copper_ore") and deps.has("tin_ore") else 0
	st["iron_ore"] = 40 if deps.has("iron_ore") else 0   # v0.012 [ours]: pre-history iron, like the copper above
	st["iron_bars"] = 30 if deps.has("iron_ore") else 0
	st["flux"] = 30 if deps.has("flux") else 0
	st["home"] = 1
	e["stock"] = st
	# barns: grain to carry the town to the autumn harvest (it is spring), a little of everything else
	var to_harvest := float(Calendar.DAYS_PER_SEASON) * (2.0 + 0.6)
	var barn := {"grain": int(food_day * float(mix["grain"]) * to_harvest + adults * bs * 0.5 * to_harvest),
		"fruit": int(food_day * float(mix["fruit"]) * 4.0), "flax": int(pop * 0.4), "meat": 0, "wool": int(pop * 0.05), "hides": 0}
	e["barn"] = barn
	e["granary"] = int(food_day * 8.0)
	e["farm_till"] = 0.0
	e["land_fund"] = 0.0
	# households: each family has laid by some days of food, drink and firewood (its own targets are
	# needs.family_targets); the goods sit in the town's household pool, summed
	var hh := {}
	var tg: Dictionary = needs["family_targets"]
	var e_day0: int = int(e.get("day", 0))
	e["day"] = 0
	e["wf"] = float(needs["firewood_home"]) * float(needs["firewood_season"][0]) * float(clim["firewood"])
	e["hdecay"] = float(D["cultures"][e["culture"]]["home"]["decay"])
	e["food_short"] = 0.0
	for f in e["fams"]:
		if f.get("estate", false):
			continue
		var r := Families.daily_rates(e, f)
		var sd := {"food": float(tg["food"]) * rng.randf_range(0.3, 0.8), "drink": float(tg["drink"]) * rng.randf_range(0.3, 0.8),
			"wood": float(tg["wood"]) * rng.randf_range(0.3, 0.8)}
		f["store"] = sd
		var meals := float(sd["food"]) * float(r["food"])
		for k in mix:
			hh[k] = int(hh.get(k, 0)) + int(meals * float(mix[k]))
		var mugs := float(sd["drink"]) * float(r["drink"])
		hh["beer"] = int(hh.get("beer", 0)) + int(mugs * bs)
		hh["wine"] = int(hh.get("wine", 0)) + int(mugs * (1.0 - bs))
		hh["wood"] = int(hh.get("wood", 0)) + int(float(sd["wood"]) * float(r["wood"]))
		f["wear"] = {}
	e["day"] = e_day0
	hh["clothing"] = int(pop * 0.3); hh["blankets"] = int(homes); hh["tools"] = int(adults * 0.8)
	hh["furniture"] = int(homes * 2.0); hh["jewelry"] = int(homes * 0.1)
	e["hh"] = hh
	# the stalls: earlier smith work (copper and tin; bronze only where the smiths know it)
	if (town.get("shop", []) as Array).is_empty():
		town["shop"] = Economy.roll_shop_n(town, rng, 12 + 6 * int(town["size"]))
