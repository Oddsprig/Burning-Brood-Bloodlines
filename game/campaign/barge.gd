class_name Barge
extends RefCounted
## The Barge economy model (docs/specs/barge/01-05, Douglas 02:36: "The Late Barge, Economy Rules v0.18.41") and the
## coinage (bronze cash "coins"; 100 coins = a labourer's day). One economy for every race: the same price formation,
## wage formula, household spending, famine stages, movers and coin. Barge numbers are used as given (data
## economy.json "barge"); [ours] marks where our world differs. The rest of the economy calls in here:
##   prices      update_prices (part 2 section 2): demand and supply EMAs, scarcity, staples together, steps, noise
##   spoilage    spoil_frac (part 2 section 3): by the town's temperature and the good's perish days
##   harvest     harvest_factor (part 2 section 4): rolled per town and year
##   labour      labour_day (part 3 section 1): the town's day wage from labour demand over labourers, x PL^0.8
##   famine      town_stage_day / family stages (part 4 section 5): Fed .. Collapse, deaths as real persons
##   movers      flee / move_family / move_in (part 4 section 6): families walk to a real town with their purse
##   treasury    treasury_month (part 4 section 1), granary_day (part 4 section 2)
##   coin        the world's coin ledger (cast - melted - drained = all holdings), the price level PL per faction,
##               the coin shortage, the daily drain, mints casting from real bars, melting (part 1 section 2; coinage)
## Rule zero: no good or coin appears except by production, minting or births; no person except by birth.

const FED := 0
const STAGES := ["fed", "short", "want", "famine", "starvation", "collapse"]

static func B() -> Dictionary:
	return TownEcon.data()["barge"]

# =====================================================================================================
# goods categories, temperature, spoilage
# =====================================================================================================
static var _cat_cache: Dictionary = {}
## {target, el, ceil, floor, perish, fresh, step} for good g (its category with the good's own perish override).
static func cat(g: String) -> Dictionary:
	if _cat_cache.has(g):
		return _cat_cache[g]
	var G: Dictionary = TownEcon.data()["goods"].get(g, {})
	var C: Dictionary = B()["categories"].get(String(G.get("bcat", "material")), B()["categories"]["material"])
	var c := {"target": float(C["target"]), "el": float(C["el"]), "ceil": float(C["ceil"]), "floor": float(C.get("floor", B()["floor"])),
		"perish": float(G.get("perish", C.get("perish", 0))), "fresh": bool(C.get("fresh", false)), "step": float(C.get("step", 0.22)),
		"name": String(G.get("bcat", "material"))}
	_cat_cache[g] = c
	return c

## The town's mean temperature today (C) [ours: by climate and season].
static func temp(e: Dictionary, si: int) -> float:
	var t: Array = B()["temp"].get(String(e.get("climate", "temperate")), B()["temp"]["temperate"])
	return float(t[clampi(si, 0, 3)])

## Spoil rate at temperature t: 0.06 at -6 C, 0.3 at 2 C, 1.0 at 18 C, 1.5 at 30 C (interpolated, held flat outside).
static func spoil_rate(t: float) -> float:
	var pts: Array = B()["spoil_rate"]
	if t <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if t <= float(pts[i][0]):
			var a: Array = pts[i - 1]; var b: Array = pts[i]
			return lerpf(float(a[1]), float(b[1]), (t - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(pts[-1][1])

## Share of a stock of g that spoils in one day at the town's temperature: min(1, rate / perish days); 0 if it keeps.
static func spoil_frac(g: String, rate: float) -> float:
	var p := float(cat(g)["perish"])
	if p <= 0.0:
		return 0.0
	return minf(1.0, rate / p)

# =====================================================================================================
# the year's harvest
# =====================================================================================================
## Harvest factor of the town this year: 12% of years 0.55-0.70, 10% 1.15-1.25, else 0.9-1.1 (rolled once a year).
static func harvest_factor(w: Dictionary, e: Dictionary, tid: String, day: float) -> float:
	var yr := Calendar.year(day)
	if int(e.get("hf_year", -1)) == yr:
		return float(e["hf"])
	var H: Dictionary = B()["harvest"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), tid, yr, "harvest"])
	var r := rng.randf()
	var hf := 1.0
	if r < float(H["bad"][0]):
		hf = rng.randf_range(float(H["bad"][1]), float(H["bad"][2]))
	elif r < float(H["bad"][0]) + float(H["good"][0]):
		hf = rng.randf_range(float(H["good"][1]), float(H["good"][2]))
	else:
		hf = rng.randf_range(float(H["normal"][0]), float(H["normal"][1]))
	e["hf_year"] = yr
	e["hf"] = snappedf(hf, 0.001)
	return float(e["hf"])

# =====================================================================================================
# price level, coin shortage
# =====================================================================================================
static func pl_of(w: Dictionary, fid: String) -> float:
	return float(w.get("factions", {}).get(fid, {}).get("pl", 1.0))

static func pl(e: Dictionary) -> float:
	return float(e.get("pl", 1.0))

## Wages and the pay table move with PL^0.8.
static func wage_mult(e: Dictionary) -> float:
	var p := pl(e)
	if float(e.get("_wm_pl", -1.0)) != p:   # cached per price level (it moves once a day)
		e["_wm_pl"] = p
		e["_wm_v"] = pow(p, float(B()["labour"]["pl_power"]))
	return float(e["_wm_v"])

static func shortage(e: Dictionary) -> float:
	return float(e.get("coin_short", 0.0))

# =====================================================================================================
# prices (part 2 section 2)
# =====================================================================================================
static var _pg: Array = []
static var _pbase := PackedFloat64Array()
static var _ptgt := PackedFloat64Array()
static var _pel := PackedFloat64Array()
static var _pstep := PackedFloat64Array()
static var _pfloor := PackedFloat64Array()
static var _pceil := PackedFloat64Array()
static var _pfresh: Array = []
static var _pstaple: Array = []
static var _precs: Array = []   # per good: [[input good, amount per unit] ...] per recipe, or []
static var _recipes_for: Dictionary = {}   # good -> [input dicts] (made goods' cost floor)

static func _init_prices() -> void:
	if not _pg.is_empty():
		return
	var D := TownEcon.data()
	for g in D["goods"]:
		_pg.append(g)
		_pbase.append(float(D["goods"][g]["price"]))
		var C := cat(g)
		_ptgt.append(float(C["target"])); _pel.append(float(C["el"])); _pstep.append(float(C["step"]))
		_pfloor.append(float(C["floor"])); _pceil.append(float(C["ceil"]))
		_pfresh.append(bool(C["fresh"])); _pstaple.append(C["name"] == "staple")
	for bt in D["businesses"]:
		if String(bt).begins_with("_"):
			continue
		for r in D["businesses"][bt]["recipes"]:
			if r.get("home", false):
				continue
			for og in r["out"]:
				if not _recipes_for.has(og):
					_recipes_for[og] = []
				var per := {}
				for ig in r["in"]:
					per[ig] = float(r["in"][ig]) / float(r["out"][og])
				if not per.is_empty():
					_recipes_for[og].append(per)
	for g in _pg:
		var rl := []
		for per in _recipes_for.get(g, []):
			var pairs := []
			for ig in per:
				pairs.append([ig, float(per[ig])])
			rl.append(pairs)
		_precs.append(rl)

## Demand from a buyer: what was bought + unmet demand (stock short) + 20% of what households wanted but could not
## afford. The day's demand e.req feeds the demand EMA.
static func add_demand(e: Dictionary, g: String, bought: float, unmet: float, unaffordable: float) -> void:
	var req: Dictionary = e["req"]
	req[g] = float(req.get(g, 0.0)) + bought + unmet + float(B()["unaffordable"]) * unaffordable

## The day's prices: DemandEma moves 12%/day toward demand, SupplyEma 20%/day toward the day's supply (what was made
## or brought in); normal stock = DemandEma x TargetDays; scarcity (clamped 0.2-40): keeping goods (TargetDays / days
## of stock)^elasticity, fresh food (demand / (SupplyEma + 0.35 stock))^(1.4 elasticity); target = base x PL x scarcity;
## staples together: sqrt(own target x base x PL x (40 / staple days)^0.8); made goods >= 1.05 x their input cost; the
## Prices step toward the target with noise. Food keeps its floor and scarcity response, without a price ceiling.
static func update_prices(town: Dictionary, rng: RandomNumberGenerator, every: bool = false) -> void:
	_init_prices()
	var e: Dictionary = town["econ"]
	var Bd := B()
	var de := float(Bd["demand_ema"]); var se := float(Bd["supply_ema"]); var noise := float(Bd["noise"])
	var req: Dictionary = e["req"]
	var bdem: Dictionary = e.get("bdem", {})
	var dem: Dictionary = e["dem"]
	if not e.has("sup"):
		e["sup"] = {}
	var sup: Dictionary = e["sup"]
	if not e.has("pmade"):
		e["pmade"] = {}
	var pmade: Dictionary = e["pmade"]
	var made: Dictionary = e["led"]["made"]
	var st: Dictionary = e["stock"]
	var barn: Dictionary = e["barn"]
	var price: Dictionary = e["price"]
	var need: Dictionary = e["need"]
	var P := pl(e)
	var cin: Dictionary = e.get("cin", {})
	# staples together: the town's staple days (all staple goods' stock over their demand)
	var sst := 0.0; var sdm := 0.0
	for i in _pg.size():
		if _pstaple[i]:
			var g0: String = _pg[i]
			sst += float(st.get(g0, 0)) + float(barn.get(g0, 0))
			sdm += float(dem.get(g0, 0.0))
	var staple_days := sst / maxf(0.01, sdm)
	var mf := float(Bd["made_floor"])
	var de2 := 1.0 - pow(1.0 - de, 2.0)
	var se2 := 1.0 - pow(1.0 - se, 2.0)
	var par := int(e.get("day", 0)) % 2
	for i in _pg.size():
		var g: String = _pg[i]
		# keeping goods other than staples are worked in 2-day steps (the same daily rates; half the work, like the
		# spoilage's 3-day steps); staples and fresh food every day
		var two: bool = not every and not _pfresh[i] and not _pstaple[i]
		if two and i % 2 != par:
			continue
		var dt := 2.0 if two else 1.0
		var base: float = _pbase[i]
		var el: float = _pel[i]
		var tg: float = _ptgt[i]
		var d1: float = dem.get(g, 0.0)
		d1 += (float(req.get(g, 0.0)) / dt + float(bdem.get(g, 0.0)) - d1) * (de2 if two else de)
		req.erase(g)
		dem[g] = d1
		var mnow := float(made.get(g, 0)) + float(cin.get(g, 0))
		var inflow := maxf(0.0, mnow - float(pmade.get(g, mnow))) / dt
		pmade[g] = mnow
		var s1: float = sup.get(g, d1)
		s1 += (inflow - s1) * (se2 if two else se)
		sup[g] = s1
		need[g] = d1 * tg
		var stock := float(st.get(g, 0)) + float(barn.get(g, 0))
		var sc := 1.0
		if _pfresh[i]:
			sc = pow(maxf(d1, 0.0001) / maxf(0.0001, s1 + 0.35 * stock), 1.4 * el)
		else:
			sc = pow(tg * maxf(d1, 0.0001) / maxf(0.0001, stock), el)
		sc = clampf(sc, 0.2, 40.0)
		var tgt := base * P * sc
		if _pstaple[i]:
			tgt = sqrt(tgt * base * P * pow(40.0 / maxf(0.01, staple_days), 0.8))
		var rl: Array = _precs[i]
		if not rl.is_empty():
			var lo := INF
			for pairs in rl:
				var c := 0.0
				for pr in pairs:
					c += float(pr[1]) * float(price.get(pr[0], 1.0))
				lo = minf(lo, c)
			tgt = maxf(tgt, mf * lo)
		var p0: float = price.get(g, base * P)
		var stp: float = _pstep[i]
		if two:
			stp = 1.0 - (1.0 - stp) * (1.0 - stp)
		var p1 := p0 + (tgt - p0) * stp
		p1 *= 1.0 + noise * (rng.randf() * 2.0 - 1.0)
		if g in ["grain", "fruit", "meat", "fresh_meat"]:
			price[g] = maxf(p1, _pfloor[i] * base * P)
		else:
			price[g] = clampf(p1, _pfloor[i] * base * P, _pceil[i] * base * P)

## Staple index of the town: the staple's price over base x PL (campaign/barge_views.gd).
static func staple_index(e: Dictionary) -> float: return BargeViews.staple_index(e)

# =====================================================================================================
# households: staples by race taste, eaters, classes
# =====================================================================================================
## Staple shares of the town's race: taste x (P per peck / 55)^-2.6 over the staples it eats (barge part 2 section 5).
static func staple_shares(e: Dictionary, at_base: bool = false) -> Dictionary:
	if not at_base and int(e.get("_ssh_day", -1)) == int(e.get("day", 0)) and e.has("_ssh"):
		return e["_ssh"]   # once a day per town (prices move daily)
	var r := _staple_shares(e, at_base)
	if not at_base:
		e["_ssh"] = r
		e["_ssh_day"] = int(e.get("day", 0))
	return r

static func _staple_shares(e: Dictionary, at_base: bool) -> Dictionary:
	var T: Dictionary = B()["tastes"].get(String(e.get("culture", "middle")), {"grain": 1.0})
	var G: Dictionary = TownEcon.data()["goods"]
	var ppm := float(B()["peck_per_meal"])
	var out := {}
	var tot := 0.0
	for g in T:
		var p := float(G[g]["price"]) if at_base else float(e["price"].get(g, G[g]["price"]))
		var v := float(T[g]) * pow(maxf(0.01, p / ppm) / float(B()["taste_peck"]), -float(B()["taste_power"]))
		out[g] = v
		tot += v
	for g in out:
		out[g] = float(out[g]) / maxf(0.000001, tot)
	return out

## The town's diet at base prices, meals a person a day by food (campaign/barge_views.gd).
static func diet(e: Dictionary) -> Dictionary: return BargeViews.diet(e)

## Households' want of a good: q x clamp((P / base)^-elasticity, 0.12, 1.6) (elasticities by category: salt 0.15, fuel
## and condiments 0.35, medicine 0.4, prepared 0.7, produce 0.8, meat 1.0, drink 1.2; [ours] cloth, household goods
## and tools 0.5). Returns the multiplier on q.
static func want_mult(e: Dictionary, g: String, H: Dictionary) -> float:
	if int(e.get("_wm_day", -1)) != int(e.get("day", 0)) or not e.has("_wm"):
		e["_wm"] = {}
		e["_wm_day"] = int(e.get("day", 0))
	var wm: Dictionary = e["_wm"]
	if wm.has(g):
		return wm[g]
	var el := float(H["el"].get(String(cat(g)["name"]), 0.5))
	var base := float(TownEcon.data()["goods"][g]["price"])
	var C: Array = H["want_clamp"]
	var v := clampf(pow(maxf(0.0001, float(e["price"].get(g, base)) / base), -el), float(C[0]), float(C[1]))
	wm[g] = v
	return v

## The town's household constants for today (one dictionary per town and day: the weekly family turns read it):
## jars and fuel stores by class with the town's fear and rationing, the week's fill and budget shares, the staples
## on offer and their shares, the want multipliers, the rent, the markup.
static func hctx(e: Dictionary) -> Dictionary:
	var d := int(e.get("day", 0))
	if int(e.get("_hx_day", -1)) == d and e.has("_hx"):
		return e["_hx"]
	var H: Dictionary = B()["household"]
	var fear := 1.0 + 1.5 * float(e.get("fstage", 0)) / 5.0
	var jar := []
	var fs := []
	var rest7 := []
	var winter := Calendar.season_index(float(d)) == 3
	for c in 3:
		var j := float(H["jar"][c]) * fear
		if e.get("rationing", false):
			j = minf(j, float(H["ration_jar"]))
		jar.append(j)
		fs.append(float(H["fuel_store"][c]) * (float(H["winter_fuel"]) if winter else 1.0))
		rest7.append(1.0 - pow(1.0 - float(H["rest_save"][c]), 7.0))
	var sh := staple_shares(e)
	var avail := 0.0
	for g in sh:
		if int(e["stock"].get(g, 0)) + int(e["barn"].get(g, 0)) > 0:
			avail += float(sh[g])
	# the rest wants by class: meals of meat and fruit a person a day, mugs and cups a grown-up a day (q x want);
	# the worn goods' want multipliers (clothing, tools, blankets, furniture: Families.K_WEAR_G order)
	var RQ: Dictionary = H["rest_q"]
	var bs := EconGen.beer_share_of(e)
	var rq := []
	for c in 3:
		rq.append([float(RQ["meat"][c]) * want_mult(e, "meat", H), float(RQ["fruit"][c]) * want_mult(e, "fruit", H),
			float(RQ["drink"][c]) * bs * want_mult(e, "beer", H), float(RQ["drink"][c]) * (1.0 - bs) * want_mult(e, "wine", H)])
	var wwm := []
	for g in Families.K_WEAR_G:
		wwm.append(want_mult(e, g, H))
	var x := {"mk": TownEcon.markup(), "day": float(d), "jar": jar, "fs": fs, "rest7": rest7,
		"ess7": 1.0 - pow(1.0 - float(H["essentials_save"]), 7.0), "fill7": 1.0 - pow(0.8, 7.0),
		"sh": sh, "avail": avail, "broker": float(TownEcon.data()["market"]["broker_share"]),
		"wm_wood": want_mult(e, "wood", H), "rent": rent_week(e), "rq": rq, "wwm": wwm, "hlux": float(H["hungry_lux"]),
		"gather": float(H["gather"]),
		"spend": 1.0 - float(B()["coin"]["spend_cut"]) * shortage(e)}
	e["_hx"] = x
	e["_hx_day"] = d
	return x

## Class of a family: 0 poor, 1 middling, 2 rich (world gen roll, then by savings with a margin: up past 1.5x the line,
## down under half of it) [ours].
static func klass(f: Dictionary) -> int:
	var c := int(f.get("cls", 0))
	var L: Array = B()["household"]["class_line"]
	var p := Population.household_purse(f)
	if c < 2 and p > float(L[c]) * 1.5:
		c += 1
	elif c > 0 and p < float(L[c - 1]) * 0.5:
		c -= 1
	f["cls"] = c
	return c

## [eaters (meal shares), children 10-14, children under 10, elders]: under 10 eat 0.6, 10-14 eat 0.8 (ages scaled to
## the race: 10-14 of a human whose adulthood is 16). Children without records count as under 10.
static func eaters(e: Dictionary, f: Dictionary, day: float, cache: bool = true) -> Array:
	var kids := int(f["kids"])
	var k1014 := 0
	# Age classification needs a race only when actual child records exist.
	# Missing/empty legacy registers use the documented younger-child share.
	if kids > 0 and f.has("kp") and not (f["kp"] as Array).is_empty():
		var race := Persons.race_of(e)
		# Native array hashing detects replacement/repair of a same-sized child register.
		# Older saves lack this fingerprint and rebuild their derived count once.
		var signature := hash(f.get("kp", []))
		var counted := float(f.get("k1014_d", -99.0))
		if f.has("k1014") and day >= counted and day - counted < 7.0 and day < float(f.get("k1014_next", -99.0)) and int(f.get("k1014_n", -1)) == kids and f.get("k1014_race", "") == race and int(f.get("k1014_sig", -1)) == signature:
			k1014 = int(f["k1014"])
		else:
			var ab := People.ages(race)
			var sc := float(ab["adult"]) / 16.0
			var yd := People.year_days()
			var lo := float(B()["labour"]["kid_from"]) * sc * yd
			var next_age := day + 7.0
			for p in f["kp"]:
				if day - float(p[3]) >= lo:
					k1014 += 1
				else:
					next_age = minf(next_age, float(p[3]) + lo)
			k1014 = mini(k1014, kids)
			if cache:
				f["k1014"] = k1014
				f["k1014_d"] = day
				f["k1014_n"] = kids
				f["k1014_next"] = next_age
				f["k1014_race"] = race
				f["k1014_sig"] = signature
	if f.get("cohort", false):
		k1014 = mini(kids, k1014 + Population.child_older(f, e, day))
	var small := kids - k1014
	var KE: Array = B()["household"]["kid_eat"]
	var eq := float(Families.adults(f) + int(f["old"])) + float(small) * float(KE[0]) + float(k1014) * float(KE[1])
	return [eq, k1014, small, int(f["old"])]

## Actual meal shares supplied by the household pool today. Broth families are
## fed by the shelter; army, bandit and deserter members eat away from home.
## Militia, guards and caravans keep their existing home-food policy.
static func household_eaters(e: Dictionary, day: float, cache: bool = true) -> float:
	if not e.has("fams"):
		return maxf(0.0, float(e.get("pop", 0)))
	var total := 0.0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or (f.get("shel", false) and f.get("broth", false)):
			continue
		var eq := float(eaters(e, f, day, cache)[0])
		for role in ["army", "bandit", "deserter"]:
			eq -= float(f.get("serve", {}).get(role, 0))
		total += maxf(0.0, eq)
	return total

## Helpers' hands: children 10-14 at 0.2 and elders at 0.15 of a hand (barge part 2 section 5; part 3 section 1).
static func helper_hands(e: Dictionary, f: Dictionary, day: float) -> float:
	var L: Dictionary = B()["labour"]
	var ea := eaters(e, f, day)
	var old_home := int(f["old"])
	if f.has("pp"):
		old_home = Persons.home_n(f, 2)
	var cleanup := 0
	for p in Persons.kp(f):
		if f.get("child_cj", {}).has(str(int(p[0]))) and Shelter.cleanup_child_eligible(e, p, day): cleanup += 1
	return float(maxi(0, int(ea[1]) - cleanup)) * float(L["kid_share"]) + float(old_home) * float(L["elder_share"])

# =====================================================================================================
# labour (part 3 section 1)
# =====================================================================================================
## Daily: labour demand (field hands first: farm rows and the town fields, x2 hands in harvest weeks; builders by
## season; porters; public works; trades short of staff) x (1 - 0.3 x coin shortage) over the labourers (adults
## doing day labour: idle, casual, field hands, works, builders); day wage = clamp(100 (demand / labourers)^0.3, 55,
## 140) x PL^0.8. This anchors the bands; employers retain and adjust their own offers weekly.
static func labour_day(e: Dictionary, si: int) -> void:
	var L: Dictionary = B()["labour"]
	if not e.has("idle_n"):
		recount_week(e)
	var dem := 0.0; var sup := 0.0
	var bs := float(L["builder_season"][si])
	for b in e["biz"]:
		var lk: int = b.get("lk", -1)
		if lk < 0:
			lk = labour_kind(b)
		if b["closed"]:
			continue
		var cap := float(b["cap"]); var w := float(b["workers"])
		match lk:
			1:
				# Family and estate capacities include their seasonal crop hands on
				# ordinary turns. Count real places once, including filled ones.
				dem += cap
				sup += w
			2:
				dem += cap * (bs if b["type"] == "builder" else 1.0)
				sup += w
			0:
				dem += maxf(0.0, cap - w)
	var cjc: Dictionary = e.get("cjcap", {})
	for j in cjc:
		dem += float(cjc[j])
	var cju: Dictionary = e.get("cjused", {})
	for j in cju:
		sup += float(cju[j])
	sup += float(e.get("idle_n", 0))
	dem *= 1.0 - float(L["shortage_cut"]) * shortage(e)
	var wage := clampf(float(L["base"]) * pow(maxf(dem, 0.5) / maxf(sup, 1.0), float(L["power"])), float(L["min"]), float(L["max"])) * wage_mult(e)
	e["dwage"] = snappedf(wage, 0.01)
	e["ldem"] = snappedf(dem, 0.1)
	e["lsup"] = snappedf(sup, 0.1)

## A business row's place in the labour market (cached on the row as b.lk): 1 field hands (farms, the town's fields),
## 2 day work (builders, public works), 0 trades short of staff count as demand, 3 neither (the market, collectors, mint).
static func labour_kind(b: Dictionary) -> int:
	var T: Dictionary = TownEcon.data()["businesses"][b["type"]]
	var lk := 0
	if T.get("field", false):
		lk = 1
	elif T.get("day", false):
		lk = 2
	elif b["type"] in ["market", "collector", "mint", "academy"]:
		lk = 3
	b["lk"] = lk
	return lk

## Weekly (the town turn): the counts the daily pass reads (idle grown-ups, children, the coin in purses), from the
## family rows.
static func recount_week(e: Dictionary) -> void:
	var idle := 0; var kids := 0; var purses := 0.0
	for f in e["fams"]:
		purses += float(f["purse"])
		if not f["gone"]:
			idle += int(f.get("idle", 0))
			kids += int(f["kids"])
	e["idle_n"] = idle
	e["kids_n"] = kids
	e["purses_n"] = purses

static func day_wage(e: Dictionary) -> float:
	return float(e.get("dwage", float(B()["labour"]["base"])))

## Weekly callers share the daily observer's per-employer seven-day guard.
static func pay_week(e: Dictionary) -> void:
	Businesses.bid_day(e)

## Casual adult work follows local labour conditions. Even the cheapest adult
## shift pays 0.75 of the day wage: children's existing 0.2 shifts earn 0.15+.
static func casual_wage(e: Dictionary, j: String) -> float:
	var cj: Dictionary = TownEcon.data()["casual_jobs"][j]
	var day: float = day_wage(e)
	if cj.has("day"):
		return day
	var ratio: float = float(cj["wage"]) / float(B()["labour"]["base"])
	return clampf(day * ratio, day * 0.75, day * 1.8)

# =====================================================================================================
# famine stages (part 4 section 5) and hunger per family (part 2 section 6)
# =====================================================================================================
## The town's own stage from its households' pool: worse by a stage per 2 days of shortfall, better by a stage per
## 2 fed days.
static func town_stage_day(e: Dictionary) -> void:
	var s := int(e.get("fstage", 0))
	if float(e.get("food_short", 0.0)) > 0.05:
		e["fs_bad"] = int(e.get("fs_bad", 0)) + 1
		e["fs_ok"] = 0
		if int(e["fs_bad"]) >= 2:
			s = mini(5, s + 1)
			e["fs_bad"] = 0
	else:
		e["fs_ok"] = int(e.get("fs_ok", 0)) + 1
		e["fs_bad"] = 0
		if int(e["fs_ok"]) >= 2:
			s = maxi(0, s - 1)
			e["fs_ok"] = 0
	e["fstage"] = s

## A family's own stage after `days`: `short_days` of them without staple (worse a stage per 2), the rest fed (better a
## stage per 2; Short to Fed needs 7 days' store). Then max(own, town stage - offset by class: rich 3, middling 1,
## poor 0). A family with a full larder is Fed whatever the town's stage.
static func family_stage(e: Dictionary, f: Dictionary, days: float, short_days: float, store_days: float) -> int:
	var F: Dictionary = B()["famine"]
	var own := int(f.get("hst", 0))
	var acc := float(f.get("hacc", 0.0))
	if short_days > 0.0:
		acc = maxf(0.0, acc) + short_days
		while acc >= 2.0:
			own = mini(5, own + 1)
			acc -= 2.0
	else:
		acc = minf(0.0, acc) - days
		while acc <= -2.0 and own > 0:
			if own == 1 and store_days < float(F["fed_days"]):
				break
			own -= 1
			acc += 2.0
		acc = maxf(acc, -2.0)
	f["hst"] = own
	f["hacc"] = acc
	if store_days >= float(F["fed_days"]) and own == 0:
		return 0
	var off: Array = B()["class_off"]
	var ts := int(e.get("fstage", 0)) - int(off[clampi(int(f.get("cls", 0)), 0, 2)])
	return maxi(own, ts) if store_days < float(F["fed_days"]) else own

## Work output by stage: 1 / 0.95 / 0.8 / 0.6 / 0.4 / 0.25.
static func output_mult(stage: int) -> float:
	return float(B()["famine"]["output"][clampi(stage, 0, 5)])

## Deaths of hunger: ONE path, the sickness module's body meter (spec 6b; Sickness.body_turn from the family turn): each
## person's condition falls on the days the family's own larder (this module's per-family hunger, Sickness.food_short_days)
## leaves him short and he dies "starved" at zero (Census.record_death once). The famine stages here set work output,
## gruel, flight and the town's stage; they kill nobody themselves (the barge's stage death rates are not used, so no
## death is counted twice).

# =====================================================================================================
# movers (part 4 section 6, FIX-8)
# =====================================================================================================
## Hungry families flee (0.4% x (stage - 1) a day) to a real town of their faction or a friendly one, with their purse
## and goods. Returns true when the family left.
static func maybe_flee(game, town: Dictionary, e: Dictionary, f: Dictionary, stage: int, days: float, rng: RandomNumberGenerator, day: float) -> bool:
	# v0.034: a cohort row is many households; some of them leave each week (Migration), never the whole row at once
	if stage < 2 or Population.is_cohort(f) or Families.serving(f) > 0 or _away(f):
		return false
	var p := float(B()["movers"]["flight"]) * float(stage - 1)
	if rng.randf() >= 1.0 - pow(1.0 - p, days):
		return false
	var dest := _refuge(game.world, town)
	if dest.is_empty():
		return false
	return not move_family(game, town, f, dest, "hunger", day).is_empty()

## Members away from the row (the company): the family stays where his family record is.
static func _away(f: Dictionary) -> bool:
	for p in f.get("pp", []):
		if Persons.AWAY.has(String(p[4])) or String(p[4]) == "hire":
			return true
	return false

## The best town to flee to: of the town's faction or one at peace with a pact/alliance; lowest famine stage, then the
## highest day wage, then the nearest.
static func _refuge(w: Dictionary, town: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bv := -INF
	var fid := String(town["faction"])
	var race := Persons.race_of(town["econ"]) if TownEcon.has_econ(town) else ""
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if tid == town["id"] or not TownEcon.has_econ(t):
			continue
		var tf := String(t["faction"])
		if tf != fid and not (Diplomacy.state(w, fid, tf) in [Diplomacy.TRADE_PACT, Diplomacy.ALLIANCE]):
			continue
		var e: Dictionary = t["econ"]
		# v0.012: a family flees only to a town of its own race (a person's ages and names are read by the town's race;
		# a human family in a dwarf hold would turn dwarf). Culture is no wall: any human town of the realm or a
		# friendly realm takes human families of any culture.
		if race != "" and Persons.race_of(e) != race:
			continue
		var v := -10.0 * float(e.get("fstage", 0)) + day_wage(e) / 100.0 - (t["pos"] as Vector2).distance_to(town["pos"]) / 2000.0
		if v > bv:
			bv = v; best = t
	return best

## The family walks from one town to another: its records (persons, purse, household stores, debts written off by
## the old head) leave the old town's books and join the new one; land, herds and businesses stay behind (to the town
## estate, for sale); its house is left empty (to the estate). In the new town it takes an empty house of the town
## estate when there is one (renting), else it is homeless (the shelter). No person or coin is made or lost.
static func move_family(game, from: Dictionary, f: Dictionary, to: Dictionary, why: String, day: float) -> Dictionary:
	var service := ServiceIdentity.reserve_move(game, from, f, to)
	if not service["ok"]: return {}
	var e: Dictionary = from["econ"]
	var e2: Dictionary = to["econ"]
	Families.settle(e, f)
	HarvestClaims.depart(e, f)
	Shelter.forget(e, f)
	var estate: Dictionary = e["fams"][0]
	for c in f["land"].keys():
		Families.move_land(e, f, estate, c, int(f["land"][c]))
	for a in f["herd"].keys():
		Families.move_herd(e, f, estate, a, int(f["herd"][a]))
	for k in f["jobs"].keys():
		Families.set_job(e, f, int(k), 0)
	Families.set_worked(e, f, 0.0)
	e["hands"] = int(e.get("hands", 0)) - int(f["hands"])
	f["hands"] = 0
	for bid in f["owns"]:
		var b: Dictionary = e["biz"][int(bid)]
		Businesses.town_inherits(b)
	f["keeps"] = []
	TownHousing.leave(e, f, day)
	estate["homes"] = int(estate["homes"]) + int(f["homes"])
	e["homes"] = int(e["homes"]) - int(f["homes"])
	if int(f.get("farm", -1)) >= 0:
		var fb: Dictionary = e["biz"][int(f["farm"])]
		fb["cap"] = 0
	# what they carry: the household stores (out of this town's pool into the other's), the purse
	var carried := _carry_stores(e, e2, f)
	var n := Families.people(f)
	var nf := f.duplicate(true)
	f["gone"] = true
	f["moved"] = String(to["id"])
	f["purse"] = 0.0
	f["debt"] = 0.0
	f["store"] = {"food": 0.0, "drink": 0.0, "wood": 0.0}
	for g in (f.get("gems", {}) as Dictionary).keys():   # v0.014: their stones go with them (nf keeps the copy)
		var gn := int(f["gems"][g])
		Legends.add_fam_gem(e, f, g, -gn)
		if not e2.has("gh"):
			e2["gh"] = {}
		e2["gh"][g] = int(e2["gh"].get(g, 0)) + gn
	f["homes"] = 0
	e["pop"] = int(e["pop"]) - n
	e["adults"] = int(e["adults"]) - Families.adults(f)
	var st: Dictionary = e["stats"]
	st["left"] = int(st.get("left", 0)) + n
	st["left_" + why] = int(st.get("left_" + why, 0)) + n
	if not st.has("left_to"):
		st["left_to"] = {}
	st["left_to"][String(to["id"])] = int(st["left_to"].get(String(to["id"]), 0)) + n
	Families.add_hist(f, "The family left %s for %s, driven off by %s." % [from.get("name", "town"), to.get("name", "town"), why], day)
	# in the new town: a new row (new id), its people re-numbered in this town's register, an empty house if any
	var nid := (e2["fams"] as Array).size()
	f["wage_destination"] = [String(to["id"]), nid]
	nf["id"] = nid
	nf["land"] = {}; nf["herd"] = {}; nf["jobs"] = {}; nf["owns"] = []; nf["keeps"] = []; nf["farm"] = -1; nf["hands"] = 0; nf["worked"] = 0.0
	nf["cum"] = {}; nf["serve"] = {}; nf["homes"] = 0; nf["debt"] = 0.0; nf["idle"] = 0; nf["ox"] = 0
	nf["last"] = day; nf["tax_season"] = int(e2["tax"]["season"]); nf["hst"] = int(f.get("hst", 0))
	nf.erase("ln"); nf.erase("cj"); nf.erase("rent"); nf.erase("hl"); nf.erase("shel"); nf.erase("broth"); nf.erase("landlord"); nf.erase("wsig")
	nf.erase("moved"); nf.erase("lpay")
	nf.erase("wage_destination")
	nf.erase("hv"); nf.erase("legacy_hv"); nf.erase("legacy_land_pending")
	nf["gone"] = false
	nf["store"] = carried
	var remap := _renumber(e2, nf)
	(e2["fams"] as Array).append(nf)
	Dynasty.note_households_changed()
	Sickness.family_moved(e, e2, f, nf, remap, day)   # their open cases, immunities and body condition go with them
	ServiceIdentity.transfer(game, from, to, nf, service["units"])
	for p in f.get("pp", []):
		if int(p[5]) >= 0: ServiceIdentity.detach(p)
	ServiceIdentity.recount(f)
	Census.record_move(e, -1, "out", String(to.get("name", "")), day, why, n)   # the census: n people left, and where to
	Census.record_move(e2, -1, "in", String(from.get("name", "")), day, why, n)
	for c in e2.get("cum", {}):
		nf["cum"][c] = float(e2["cum"][c])
	e2["pop"] = int(e2["pop"]) + n
	e2["adults"] = int(e2["adults"]) + Families.adults(nf)
	var st2: Dictionary = e2["stats"]
	st2["moved_in"] = int(st2.get("moved_in", 0)) + n
	var est2: Dictionary = e2["fams"][0]
	if int(est2["homes"]) > 0:
		est2["homes"] = int(est2["homes"]) - 1
		nf["homes"] = 1
		nf["rent"] = 1
		nf["cond"] = 0.7
		e2["homes"] = int(e2["homes"]) + 1
	else:
		Shelter.lost_home(e2, nf, "moved", day)
	Families.event(nf, "arrived", [String(from.get("name", "")), why], day)
	Families.add_hist(nf, "Came to %s from %s." % [to.get("name", "town"), from.get("name", "town")], day)
	Families.reassign(e2, nf)
	Persons.sync(e2, nf, day)
	Persons.track_jobs(e2, nf, day)   # their life histories: the places they take in the new town
	return nf

## Household stores move with the family (goods out of one town's pool into the other's: neither made nor used).
static func _carry_stores(e: Dictionary, e2: Dictionary, f: Dictionary) -> Dictionary:
	var hh: Dictionary = e["hh"]
	var hh2: Dictionary = e2["hh"]
	var st: Dictionary = f["store"]
	var rates := Families.daily_rates(e, f)
	var out := {"food": 0.0, "drink": 0.0, "wood": 0.0}
	for k in ["food", "drink", "wood"]:
		var goods: Array = Families.HOUSEHOLD_FOOD if k == "food" else (["beer", "wine"] if k == "drink" else ["wood"])
		var want := float(st.get(k, 0.0)) * float(rates[k])
		var moved := 0
		var quantities := Families.store_quantities(hh, goods, want)
		for g in quantities:
			var q := int(quantities[g])
			if q > 0:
				hh[g] = int(hh[g]) - q
				hh2[g] = int(hh2.get(g, 0)) + q
				moved += q
		out[k] = float(moved) / maxf(0.01, float(rates[k]))
	return out

## The moving family's people get new numbers in the new town's register (links inside the family kept; links to
## people left behind in the old town dropped). Units bound to them do not exist (families with members away do not move).
static func _renumber(e2: Dictionary, f: Dictionary) -> Dictionary:
	var remap := {}
	for p in Persons.pp(f) + Persons.kp(f):
		var pid := int(e2.get("next_pid", 1))
		e2["next_pid"] = pid + 1
		remap[int(p[0])] = pid
	for p in Persons.pp(f) + Persons.kp(f):
		p[0] = int(remap[int(p[0])])
		for k in [Persons.SP, Persons.MO, Persons.FA]:
			if p.size() > k:
				var o := int(p[k])
				p[k] = int(remap.get(o, -1)) if o >= 0 else -1
	var keep := []   # a woman with child carries it to the new town (Persons.childbearing: f.preg by pid)
	for x in f.get("preg", []):
		if remap.has(int(x[0])):
			keep.append([int(remap[int(x[0])]), float(x[1]), int(remap.get(int(x[2]), -1))])
	if keep.is_empty():
		f.erase("preg")
	else:
		f["preg"] = keep
	f.erase("nxa")
	return remap

## Monthly: a town with empty homes and a day wage over its realm's average draws up to 3 families from towns of the
## realm with lower wages or hunger (poor families without land, business or anyone away) [ours: monthly, 3].
static func move_in(game, day: float) -> void:
	var w: Dictionary = game.world
	var M: Dictionary = B()["movers"]
	var by_f := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var fid := String(t["faction"])
		if not by_f.has(fid):
			by_f[fid] = []
		by_f[fid].append(t)
	var fids: Array = by_f.keys()
	fids.sort()
	for fid in fids:
		var ts: Array = by_f[fid]
		ts.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
		var avg := 0.0
		for t in ts:
			avg += day_wage(t["econ"])
		avg /= maxf(1.0, float(ts.size()))
		for t in ts:
			var e: Dictionary = t["econ"]
			var room := int(e["fams"][0]["homes"])
			if room <= 0 or day_wage(e) <= avg or int(e.get("fstage", 0)) > 0:
				continue
			var n := mini(room, int(M["move_in_max"]))
			for src in ts:
				if n <= 0:
					break
				if src == t:
					continue
				var es: Dictionary = src["econ"]
				if day_wage(es) >= day_wage(e) and int(es.get("fstage", 0)) == 0:
					continue
				for f in (es["fams"] as Array).duplicate():
					if n <= 0:
						break
					if f["gone"] or f.has("estate") or Population.is_cohort(f) or Families.acres(f) > 0 or Families.heads(f) > 0 or not (f["owns"] as Array).is_empty() \
							or Families.serving(f) > 0 or _away(f) or int(f.get("cls", 0)) > 0 or float(f.get("debt", 0.0)) > 0.0:
						continue
					if int(f.get("idle", 0)) <= 0 and int(f.get("hungry", 0)) <= 0:
						continue
					if not move_family(game, src, f, t, "work", day).is_empty(): n -= 1

# =====================================================================================================
# the world's coin (part 1 section 2; coinage spec)
# =====================================================================================================
static func ledger(w: Dictionary) -> Dictionary:
	if not w.has("coin"):
		w["coin"] = {"cast": 0.0, "melted": 0.0, "drained": 0.0}
	return w["coin"]

## Every coin held anywhere: towns, realm treasuries/loot, bandit hoards, caravans/forces, company (campaign/barge_views.gd).
static func holdings(game) -> float: return BargeViews.holdings(game)

## World gen (and older saves): all coin that exists counts as cast before the world began; each realm's and town's
## money need = the coin it holds now (index 1 at start: Douglas's default).
static func init_world(game) -> void:
	var w: Dictionary = game.world
	var L := ledger(w)
	L["cast"] = holdings(game)
	L["target"] = float(L["cast"])
	L["melted"] = 0.0
	L["drained"] = 0.0
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		fac["pl"] = 1.0
		fac["trust"] = 1.0
		fac["need"] = maxf(1.0, faction_coin(w, fid))
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t):
			t["econ"]["cneed"] = maxf(1.0, TownEcon.town_gold(t["econ"]))
			t["econ"]["pl"] = 1.0

static func faction_coin(w: Dictionary, fid: String, fresh: bool = true) -> float: return BargeViews.faction_coin(w, fid, fresh)

## Saves from before v0.010 count money in gold: every holding, price, wage, debt and contract x20 into coins
## (the coinage factor), before the economy's own load fix-ups. Runs once (the coin ledger marks a coin world).
static func before_load(game) -> void:
	var w: Dictionary = game.world
	if w.has("coin") or not w.has("towns"):
		return
	var k := TownEcon.COIN
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		for c in t.get("contracts", []):
			for key in ["pay", "base_pay"]:
				if c.has(key):
					c[key] = int(c[key]) * int(k)
		for u in t.get("recruits", []):
			if u is Unit:
				u.wage *= int(k); u.hire_cost *= int(k)
		if not t.has("econ") or not (t["econ"] as Dictionary).has("stock"):
			continue
		var e: Dictionary = t["econ"]
		for key in ["treasury", "farm_till", "land_fund"]:
			e[key] = float(e.get(key, 0.0)) * k
		for g in e.get("price", {}):
			e["price"][g] = float(e["price"][g]) * k
		for g in e.get("pweek", {}):
			e["pweek"][g] = float(e["pweek"][g]) * k
		for b in e["biz"]:
			for key in ["till", "owed", "wage", "spend"]:
				b[key] = float(b.get(key, 0.0)) * k
		for f in e["fams"]:
			for key in ["purse", "debt", "inc", "lpay"]:
				if f.has(key):
					f[key] = float(f[key]) * k
			var ln: Dictionary = f.get("ln", {})
			for key in ["pay", "lent", "int", "acc"]:
				if ln.has(key):
					ln[key] = float(ln[key]) * k
		for c in e.get("cum", {}):
			e["cum"][c] = float(e["cum"][c]) * k
		for f2 in e["fams"]:
			for c in f2.get("cum", {}):
				f2["cum"][c] = float(f2["cum"][c]) * k
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		for key in ["treasury", "loot"]:
			if fac.has(key):
				fac[key] = float(fac[key]) * k
	for lid in w.get("lairs", {}):
		if w["lairs"][lid].has("gold"):
			w["lairs"][lid]["gold"] = float(w["lairs"][lid]["gold"]) * k
	for wid in w.get("warbands", {}):
		if w["warbands"][wid].has("gold"):
			w["warbands"][wid]["gold"] = float(w["warbands"][wid]["gold"]) * k
	game.gold = int(game.gold) * int(k)
	for u in game.company:
		u.wage *= int(k)
	for key in ["pay", "base_pay"]:
		if game.contract.has(key):
			game.contract[key] = int(game.contract[key]) * int(k)

## Coin gone out of the world (lost, buried, worn: the daily drain; a purse lost on the road).
static func drained(w: Dictionary, v: float) -> void:
	var L := ledger(w)
	L["drained"] = float(L["drained"]) + v

## The day's coin pass (one work job): the drain (0.072% of every purse, till and treasury), the mints, melting,
## the price level per faction and the coin shortage per town.
## The town's part of the day's coin pass (from its daily pass): the drain on every purse, till and treasury, the
## mint, melting; then the town's coin (e.coin_now) for the realm's price level.
static func coin_town(game, t: Dictionary, e: Dictionary) -> void:
	var dr := float(B()["coin"]["drain"])
	var lost := 0.0
	var held := 0.0
	var k := 1.0 - dr
	# (family purses lose theirs at the family's weekly turn: purse_drain)
	for b in e["biz"]:
		var tl: float = b["till"]
		if tl > 0.0:
			b["till"] = tl * k
			lost += tl * dr
			held += tl * k
	var tr := float(e["treasury"])
	if tr > 0.0:
		e["treasury"] = tr * k
		lost += tr * dr
	var lf := float(e.get("land_fund", 0.0))
	if lf > 0.0:
		e["land_fund"] = lf * k
		lost += lf * dr
	drained(game.world, lost)
	mint_day(game, t, e)
	melt_day(game, t, e)
	e["coin_now"] = held + float(e["treasury"]) + float(e["farm_till"]) + float(e.get("land_fund", 0.0)) + float(e.get("purses_n", 0.0))   # (purses: as of the town's weekly turn)

## The daily drain on a family's purse over the days since its last turn (0.072% a day), out of the world's coin.
static func purse_drain(w: Dictionary, f: Dictionary, days: float) -> void:
	var p := float(f["purse"])
	if p <= 0.0:
		return
	var np := p * pow(1.0 - float(B()["coin"]["drain"]), days)
	f["purse"] = np
	drained(w, p - np)

static func coin_day(game, d: int) -> void:
	var w: Dictionary = game.world
	var C: Dictionary = B()["coin"]
	var dr := float(C["drain"])
	var lost := 0.0
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		var t0: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t0) and bool(t0["econ"].get("land_market_dirty", false)):
			Loans.settle_land_buys(t0["econ"])
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		var ft := float(fac.get("treasury", 0.0))
		if ft > 0.0:
			fac["treasury"] = ft * (1.0 - dr)
			lost += ft * dr
	drained(w, lost)
	# price level per faction: PL moves 2.5%/day toward clamp(money index^0.6 / sqrt(trust), 0.5, 3)
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		if not fac.has("need"):
			continue
		var idx := faction_coin(w, fid, false) / maxf(1.0, float(fac["need"]))
		var debase := 0.0; var nt := 0
		for tid in fac.get("towns", []):
			var t2: Dictionary = w["towns"].get(tid, {})
			if TownEcon.has_econ(t2):
				debase += float(t2["econ"].get("debase", 0.0))
				nt += 1
		debase /= maxf(1.0, float(nt))
		var trust := clampf(1.0 - float(C["trust_debase"]) * debase, 0.05, 1.0)
		fac["trust"] = trust
		var tgt := clampf(pow(maxf(0.0001, idx), float(C["pl_power"])) / sqrt(trust), float(C["pl_clamp"][0]), float(C["pl_clamp"][1]))
		fac["pl"] = float(fac.get("pl", 1.0)) + (tgt - float(fac.get("pl", 1.0))) * float(C["pl_step"])
		fac["mindex"] = idx
	# per town: its realm's PL; coin shortage from the town's own coin over its need
	var S: Array = C["shortage"]
	for tid in ids:
		var t3: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t3):
			continue
		var e3: Dictionary = t3["econ"]
		e3["pl"] = pl_of(w, String(t3["faction"]))
		var ti := float(e3.get("coin_now", e3.get("cneed", 1.0))) / maxf(1.0, float(e3.get("cneed", 1.0)))
		e3["mindex"] = ti
		e3["coin_short"] = clampf((float(S[0]) - ti) * float(S[1]), 0.0, float(S[2]))

## Metal in 1,000 coins at today's town prices, less debasement (campaign/barge_views.gd).
static func metal_per_k(e: Dictionary) -> float: return BargeViews.metal_per_k(e)

## Replace losses against a fixed opening money supply, not a municipal cash
## target. Market takes and house funding can fill a treasury while money
## elsewhere is draining. All mints share this room, so they cannot each
## replace the same loss. Only mint_day creates actual coin.
static func mint_room(w: Dictionary) -> float:
	var L: Dictionary = ledger(w)
	if not L.has("target"):
		# Current checkpoints predate target; their cumulative mint receipts
		# distinguish opening coin from coin cast during play.
		var opening: float = float(L["cast"])
		for town: Dictionary in w.get("towns", {}).values():
			opening -= float(town.get("econ", {}).get("stats", {}).get("cast", 0.0))
		L["target"] = maxf(0.0, opening)
	return maxf(0.0, float(L["target"]) - (float(L["cast"]) - float(L["melted"]) - float(L["drained"])))

## The mint uses real staff, bars and charcoal and pays their real market.
## Casting replaces drained/melted coin, within daily capacity and metal cost.
static func mint_day(game, t: Dictionary, e: Dictionary) -> void:
	if not e.has("mint_biz"):
		return
	var b: Dictionary = e["biz"][int(e["mint_biz"])]
	var C: Dictionary = B()["coin"]
	# The real operator is a working keeper, as in every other production row.
	# Paid staff may leave for the fields; that does not remove this keeper.
	var staff: float = float(maxi(0, int(b["workers"]) - int(b.get("sick", 0))) + int(b.get("kw", 0))) / maxf(1.0, float(C["minters"]))
	if b.get("closed", false):
		b["state"] = "hands"
		return
	var lines := treasury_lines(e)
	var tr := float(e["treasury"])
	var room: float = mint_room(game.world)
	if room < 100.0:
		b["state"] = "idle"
		return
	# Keep input orders alive while the crew is vacant. Previously no hands
	# meant no bar demand; no bars then also prevented the self-paying mint's
	# staffing reserve. Planning capacity never substitutes for actual labour.
	var base_k: float = (float(C["mint_day_short"]) if tr < float(lines["short"]) else float(C["mint_day"])) / 1000.0
	var planned_staff: float = maxf(staff, float(b["cap"]) / maxf(1.0, float(C["minters"])))
	var day_k: float = minf(base_k * planned_staff, room / 1000.0)
	if day_k < 0.1:
		b["state"] = "idle"
		return
	var st: Dictionary = e["stock"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var L := ledger(game.world)
	var left: float = minf(day_k, base_k * staff)
	var cast := 0.0
	var dear := false
	var recs := _mint_recipes(e)
	var took := {}
	# the metal: copper and tin bars, or bronze bars (melted coin, the smelters' bronze: coinage spec 2), the cheaper
	# first; each only while its metal costs less than the coin it makes
	for R in recs:
		if left < 0.1:
			break
		var lim := left
		for g in R:
			lim = minf(lim, float(st.get(g, 0)) / float(R[g]))
		var k := floorf(lim * 10.0) / 10.0   # in tenths of a thousand: whole bars
		if k <= 0.0:
			continue
		if _recipe_cost(e, R) >= 1000.0:
			dear = true
			continue
		# the treasury pays the market for the metal out of the coin it casts and keeps face minus metal
		var cost := 0.0
		for g in R:
			var q := mini(int(ceil(k * float(R[g]))), int(st.get(g, 0)))
			st[g] = int(st[g]) - q
			took[g] = int(took.get(g, 0)) + q
			TownEcon.led(e, "used", g, q)
			cost += float(q) * float(e["price"].get(g, 1.0))
		var face := k * 1000.0
		mkt["till"] = float(mkt["till"]) + cost
		e["treasury"] = float(e["treasury"]) + face - cost
		L["cast"] = float(L["cast"]) + face
		cast += face
		left -= k
	# the mint asks the market for its metal like any buyer (Barge.add_demand: what it took, the rest of the day's
	# recipe unmet, or wanted but dearer than the coin): before, its want counted nowhere, so the market's normal stock
	# of bars stayed a smith's few, the smelters rested "market full" and 4,000-7,000 ore lay unsmelted (v0.011)
	var R0: Dictionary = recs[0]
	for g in R0:
		var tk := float(took.get(g, 0))
		var short: float = maxf(0.0, day_k * float(R0[g]) - tk) if day_k - cast / 1000.0 >= 0.1 else 0.0
		add_demand(e, g, tk, 0.0 if dear else short, short if dear else 0.0)
	for g in took:
		if not R0.has(g):
			add_demand(e, g, float(took[g]), 0.0, 0.0)
	if cast <= 0.0:
		b["state"] = "hands" if staff <= 0.0 else "inputs"
		b["why"] = "minters" if staff <= 0.0 else ("bars dearer than coin" if dear else "bars")
		return
	e["stats"]["cast"] = float(e["stats"].get("cast", 0.0)) + cast
	b["state"] = "busy"
	# the minters are paid out of what they cast: the mint's till is kept at two weeks of its wages from the new coin
	# (a town-owned row is otherwise topped up only while the treasury holds 3 x the bill, and nobody signs on at an
	# empty till: a poor treasury's mint then stood empty with bars in the market)
	var want := float(b["cap"]) * float(b["wage"]) * 14.0 - float(b["till"])
	if want > 0.0:
		var top := minf(want, minf(cast, maxf(0.0, float(e["treasury"]))))
		b["till"] = float(b["till"]) + top
		e["treasury"] = float(e["treasury"]) - top

## The mint's recipes, metal cost, and bar availability for 1,000 coins (campaign/barge_views.gd).
static func _mint_recipes(e: Dictionary) -> Array: return BargeViews._mint_recipes(e)
static func _recipe_cost(e: Dictionary, R: Dictionary) -> float: return BargeViews._recipe_cost(e, R)
static func mint_bars(e: Dictionary) -> bool: return BargeViews.mint_bars(e)

## Melting: when the metal in coin is worth over 90% of face the town's smiths melt coin into bars (a share of the
## market's till a day): copper and tin bars into the stock, the coin out of the world (melted). Logged.
static func melt_day(game, t: Dictionary, e: Dictionary) -> void:
	var C: Dictionary = B()["coin"]
	var per_k := metal_per_k(e)   # (debased coin holds less metal)
	if per_k <= float(C["melt_above"]) * 1000.0:
		return
	var smiths := false
	for b in e["biz"]:
		if b["type"] in ["smelter", "weaponsmith", "armorsmith"] and int(b["workers"]) > 0 and not b.get("closed", false):
			smiths = true
			break
	if not smiths:
		return
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var face := floorf(maxf(0.0, float(mkt["till"])) * float(C["melt_share"]) / 100.0) * 100.0
	if face <= 0.0:
		return
	var R: Dictionary = C["mint_recipe"]
	mkt["till"] = float(mkt["till"]) - face
	# melted, the coin gives back the metal in it (barge part 1: 4.6 copper + 0.4 tin a thousand, less debasement):
	# the copper and tin whose dearness made melting pay (whole bars; the part of a bar left over waits for the next melt).
	# (Before v0.011 it gave bronze bars, which neither eased the copper price that set it off nor fed the mint, so the
	# smiths melted 1% of the market's till a day for years.)
	var carry: Dictionary = e.get("melt_carry", {})
	for g in ["copper_bars", "tin_bars"]:
		var x := float(carry.get(g, 0.0)) + face / 1000.0 * float(R[g]) * (1.0 - float(e.get("debase", 0.0)))
		var q := int(floor(x))
		carry[g] = x - float(q)
		if q > 0:
			e["stock"][g] = int(e["stock"].get(g, 0)) + q
			TownEcon.led(e, "made", g, q)
	e["melt_carry"] = carry
	var L := ledger(game.world)
	L["melted"] = float(L["melted"]) + face
	e["stats"]["melted"] = float(e["stats"].get("melted", 0.0)) + face

# =====================================================================================================
# treasury (part 4 section 1) and granary (part 4 section 2)
# =====================================================================================================
## Treasury lines and annual public payroll + due claims target for the town (campaign/barge_views.gd).
static func treasury_lines(e: Dictionary) -> Dictionary: return BargeViews.treasury_lines(e)
static func treasury_target(game, town: Dictionary, e: Dictionary) -> float: return BargeViews.treasury_target(game, town, e)


static func release_surplus(game, town: Dictionary, e: Dictionary) -> void:
	var target: float = treasury_target(game, town, e)
	var surplus: float = maxf(0.0, float(e.get("treasury", 0.0)) - target)
	e["stats"]["treasury_target"] = target
	if surplus <= 0.0: return
	# An allowance is distinct from tax; tax still credits the actual local ruler.
	# A vacant seat funds local households instead. One debit, one equal credit.
	_repay_forced(e, target)
	surplus = maxf(0.0, float(e["treasury"]) - target)
	var ruler: Dictionary = Feudal.tax_recipient(game, str(town["id"]))
	e["treasury"] = float(e["treasury"]) - surplus
	if ruler.is_empty():
		HouseUpkeep._pay_town_folk(e, {}, surplus)
	else:
		ruler["purse"] = float(ruler.get("purse", 0.0)) + surplus
		e["stats"]["allowance_uid"] = str(ruler.get("household_uid", ""))
		e["stats"]["allowance_total"] = float(e["stats"].get("allowance_total", 0.0)) + surplus


## Ruler temper and common-folk estate tax quote/reserve views (campaign/barge_views.gd).
static func temper(e: Dictionary) -> String: return BargeViews.temper(e)
static func common_tax_rate(e: Dictionary) -> float: return BargeViews.common_tax_rate(e)
static func _common_food_gap(e: Dictionary, f: Dictionary) -> float: return BargeViews._common_food_gap(e, f)
static func _common_food_unit(e: Dictionary) -> float: return BargeViews._common_food_unit(e)
static func _common_owner_budget(e: Dictionary, f: Dictionary, food_unit: float) -> Dictionary: return BargeViews._common_owner_budget(e, f, food_unit)
static func common_tax_budget(e: Dictionary) -> Dictionary: return BargeViews.common_tax_budget(e)

## Returns only money actually transferred; vacancy never redirects private
## estate tax into a municipal bill or creates tax arrears against the pool.
static func common_tax_month(game, town: Dictionary, e: Dictionary, day: float) -> float:
	var month := int(floor(day / 30.0))
	var lord: Dictionary = Feudal.tax_recipient(game, String(town.get("id", ""))) if game.world.has("feudal") else {}
	var unit := _common_food_unit(e)
	var paid := 0.0
	for f in e.get("fams", []):
		if not Population.is_cohort(f) or Population.households(f) <= 0: continue
		if int(f.get("lord_tax_month", -1)) == month: continue
		if lord.is_empty():
			f["lord_tax_held_month"] = month
			continue
		var quote := _common_owner_budget(e, f, unit)
		var amount := float(quote["monthly_due"])
		f["purse"] = float(f["purse"]) - amount
		lord["purse"] = float(lord["purse"]) + amount
		f["lord_tax_month"] = month
		f["lord_tax_town_id"] = String(town.get("id", ""))
		f["lord_tax_last"] = amount
		f["lord_tax_reserve"] = float(quote["food_reserve"])
		f["lord_tax_paid"] = float(f.get("lord_tax_paid", 0.0)) + amount
		f.erase("lord_tax_held_month")
		paid += amount
	return paid

## Monthly (tax day, the first of every 30 days per town): service money by class (40 / 150 / 1,200 a month x scale x
## PL; the poor excused in a bad year), house and land tax (value x 0.0008 x (1 + surcharge)); what a family cannot
## pay becomes arrears (a loan from the head). Then the short / full levers, the surcharge, the crisis rules.
static func treasury_month(game, town: Dictionary, e: Dictionary, day: float) -> void:
	var T: Dictionary = B()["treasury"]
	var tx: Dictionary = e["tax"]
	var L := treasury_lines(e)
	var tr0 := float(e["treasury"])
	var scale := float(e.get("svc_scale", 1.0))
	var sur := float(e.get("surcharge", 0.0))
	var bad_year := float(e.get("hf", 1.0)) < 0.8
	var P := pl(e)
	var leak := float(tx.get("leak", 0.0))
	var hp := float(TownEcon.data()["goods"]["home"]["price"]) * P
	var ap := float(TownEcon.data()["land"]["acre_price"]) * P
	var got := 0.0; var owed := 0.0; var unable := 0; var owners := 0
	var title: String = e.get("head", {}).get("title", "head")
	if int(e["stats"].get("estate_tax_day", -1)) != int(day):
		e["stats"]["estate_tax_received"] = 0.0
		e["stats"]["estate_tax_day"] = int(day)
	var estate_paid := common_tax_month(game, town, e, day)
	e["stats"]["lord_tax"] = float(e["stats"].get("lord_tax", 0.0)) + estate_paid
	e["stats"]["estate_tax_received"] = float(e["stats"].get("estate_tax_received", 0.0)) + estate_paid
	tx["lord_paid"] = float(tx.get("lord_paid", 0.0)) + estate_paid
	for f in e["fams"]:
		if f["gone"] or f.has("estate"):
			continue
		if Population.is_cohort(f): continue
		var c := klass(f)
		var due := 0.0
		if not (c == 0 and bad_year):
			due += float(T["service"][c]) * scale * P
		var own_homes := int(f["homes"]) if int(f.get("rent", 0)) <= 0 and not f.has("landlord") else 0
		if own_homes > 0 or Families.acres(f) > 0:
			owners += 1
			due += (float(own_homes) * hp + float(Families.acres(f)) * ap) * float(T["house_tax"]) * (1.0 + sur)
		due *= 1.0 - leak
		if due <= 0.0:
			continue
		var pay := minf(due, maxf(0.0, float(f["purse"]) - 1.0))
		f["purse"] = float(f["purse"]) - pay
		e["treasury"] = float(e["treasury"]) + pay
		got += pay
		if due - pay > 0.5:
			Loans.owe(e, f, due - pay, day)
			owed += due - pay
			unable += 1
			Families.event(f, "loan", [int(round(due - pay)), title], day)
	tx["paid"] = float(tx.get("paid", 0.0)) + got
	tx["owed"] = float(tx.get("owed", 0.0)) + owed
	e["stats"]["tax_in"] = float(e["stats"].get("tax_in", 0.0)) + got
	e["stats"]["tax_month"] = got
	# short / full: each month the levers move (service money +0.1 up to x1.6, eased back when full)
	var tr := float(e["treasury"])
	var garrison_owed := int(e["stats"].get("militia_unpaid", 0)) > 0
	var S: Array = T["service_scale"]
	if tr < float(L["short"]) or garrison_owed:
		e["svc_scale"] = minf(float(S[1]), scale + 0.1)
	elif tr > float(L["full"]):
		e["svc_scale"] = maxf(float(S[0]), scale - 0.1)
	# surcharge on the house tax: need = half a year's tribute + a month of garrison pay + works + overdue
	# + v0.014 the armory's shortfall (ArmsTrade: arms_due, the kit its militia and caravan guards lack)
	var need := float(e["stats"].get("to_faction_month", 0.0)) * 2.0 + Army.town_bill(game, town) * 30.0 + float(e["stats"].get("works", 0.0)) * 4.0 + float(tx.get("owed", 0.0)) \
		+ float(e.get("arms_due", 0.0))
	var t2 := temper(e)
	var k := float(T["greedy"]) if t2 == "greedy" else (float(T["merciful"]) if t2 == "merciful" else 1.0)
	var SC: Array = T["surcharge"]
	if tr < need * k:
		e["surcharge"] = float(SC[1]) if tr < need * 0.5 else float(SC[0])
	elif tr > need * float(T["surcharge_off"]):
		e["surcharge"] = 0.0
	if float(e.get("surcharge", 0.0)) >= float(SC[1]) and owners > 0 and float(unable) / float(owners) >= 0.12:
		e["unrest"] = minf(1.0, float(e.get("unrest", 0.0)) + 0.1)   # a fifth with 12%+ unable to pay: crowds
	else:
		e["unrest"] = maxf(0.0, float(e.get("unrest", 0.0)) - 0.05)
	# crisis: the garrison unpaid and the chest near empty: a forced loan from the rich (15% of savings, at most every
	# 30 days, repaid when flush); debasement 10% (up to 30%)
	if garrison_owed and tr < float(L["short"]) * 0.1:
		_forced_loan(e, day)
		e["debase"] = minf(float(T["debase_max"]), float(e.get("debase", 0.0)) + float(T["debase_step"]))
	elif tr > float(L["full"]):
		_repay_forced(e)
	e["stats"]["treasury_month"] = float(e["treasury"]) - tr0

static func _forced_loan(e: Dictionary, day: float) -> void:
	if day - float(e.get("forced_day", -999.0)) < 30.0:
		return
	e["forced_day"] = day
	var T: Dictionary = B()["treasury"]
	for f in e["fams"]:
		if f["gone"] or f.has("estate") or int(f.get("cls", 0)) < 2:
			continue
		var take := float(f["purse"]) * float(T["forced_loan"])
		f["purse"] = float(f["purse"]) - take
		e["treasury"] = float(e["treasury"]) + take
		f["forced"] = float(f.get("forced", 0.0)) + take
		Families.add_hist(f, "The %s took a forced loan of %d coins." % [e.get("head", {}).get("title", "head"), int(take)], day)

static func _repay_forced(e: Dictionary, reserve: float = -1.0) -> void:
	if reserve < 0.0: reserve = float(treasury_lines(e)["full"])
	for f in e["fams"]:
		var owed := float(f.get("forced", 0.0))
		if owed <= 0.0 or f["gone"]:
			continue
		var pay := minf(owed, maxf(0.0, float(e["treasury"]) - reserve))
		if pay <= 0.0:
			return
		e["treasury"] = float(e["treasury"]) - pay
		f["purse"] = float(f["purse"]) + pay
		f["forced"] = owed - pay

## The granary (daily): sells when the staple index > 1.3 (daily demand x clamp((index - 1.2) x 0.6, 0.05, 0.5) at the
## relief price 55 x PL a peck); buys at index < 0.85 when the treasury is comfortable (8% of daily demand at 45 x PL);
## rationing below 9 days of the town's grain (lifted above 15); the gruel kitchen at index > 1.9 or poor hunger > 0.3
## (0.07 peck a person a day for the hungry poor, out of the granary); brewing banned at index > 1.9 (lifted < 1.4).
static func granary_day(game, town: Dictionary, e: Dictionary, day: float) -> void:
	var G: Dictionary = B()["granary"]
	var ppm := float(B()["peck_per_meal"])
	var idx := staple_index(e)
	var P := pl(e)
	var dd := float(e["dem"].get("grain", 0.0))
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var gr := int(e["granary"])
	e["gran_today"] = [day, 0, 0.0]   # (the records screen: grain sold (-) or bought (+) today, at what price a meal)
	if idx > float(G["sell_index"]) and gr > 0:
		var K: Array = G["sell_k"]
		var q := mini(gr, int(dd * clampf((idx - float(K[0])) * float(K[1]), float(K[2]), float(K[3]))))
		var p := float(G["relief_peck"]) * ppm * P
		q = mini(q, int(maxf(0.0, float(mkt["till"])) / maxf(0.01, p)))
		if q > 0:
			e["gran_today"] = [day, -q, snappedf(p, 0.01)]
			e["granary"] = gr - q
			e["stock"]["grain"] = int(e["stock"].get("grain", 0)) + q
			mkt["till"] = float(mkt["till"]) - float(q) * p
			e["treasury"] = float(e["treasury"]) + float(q) * p
			e["cin"]["grain"] = int(e["cin"].get("grain", 0)) + q
			if not e.get("gran_open", false):
				e["gran_open"] = true
				TownEcon.town_hist(e, "The %s opened the granary." % e["head"]["title"], day)
				TownEcon.town_event(e, "famine", [], day)
	elif idx < float(G["buy_index"]) and float(e["treasury"]) > treasury_lines(e)["short"]:
		e["gran_open"] = false
		var want := int(dd * float(G["buy_share"]))
		var have := int(e["stock"].get("grain", 0))
		var p2 := float(G["buy_peck"]) * ppm * P
		var q2 := mini(want, mini(have / 5, int(maxf(0.0, float(e["treasury"]) - treasury_lines(e)["short"]) / maxf(0.01, p2))))
		if q2 > 0:
			e["gran_today"] = [day, q2, snappedf(p2, 0.01)]
			e["stock"]["grain"] = have - q2
			e["granary"] = int(e["granary"]) + q2
			e["treasury"] = float(e["treasury"]) - float(q2) * p2
			mkt["till"] = float(mkt["till"]) + float(q2) * p2
	else:
		e["gran_open"] = false
	# rationing by the town's grain days (market, barns, granary, households)
	var grain := float(e["stock"].get("grain", 0)) + float(e["barn"].get("grain", 0)) + float(e["granary"]) + float(e["hh"].get("grain", 0))
	var gd := grain / maxf(1.0, float(e["pop"]) * float(TownEcon.data()["needs"]["food"]))
	var RD: Array = G["ration_days"]
	if gd < float(RD[0]):
		e["rationing"] = true
	elif gd > float(RD[1]):
		e["rationing"] = false
	var BB: Array = G["brew_ban"]
	if idx > float(BB[0]):
		e["brew_ban"] = true
	elif idx < float(BB[1]):
		e["brew_ban"] = false
	e["gruel"] = idx > float(G["gruel_index"]) or float(e.get("poor_hunger", 0.0)) > float(G["gruel_hunger"])

## The coping ladder (part 2 section 7, steps 1-2: savings < 20, or hungry): pawn the bedding (in winter only when
## desperate), then max(150, 15% of possessions) for 40% of their value: the family's share of the household goods
## goes to the market (the market pays 40% of the price). Steps 3 (stripping the house) and the grain loan from a
## neighbour are not modelled; step 4 (the county loan) is Loans.maybe_borrow. Returns coins raised.
static func pawn(e: Dictionary, f: Dictionary, day: float) -> float:
	var hh: Dictionary = e["hh"]
	var price: Dictionary = e["price"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var winter := Calendar.season_index(day) == 3
	var share := float(f["homes"]) / maxf(1.0, float(e["homes"]))
	var goods := ["jewelry", "furniture", "clothing", "tools"]
	if not winter or int(f.get("hungry", 0)) >= 3:
		goods.push_front("blankets")
	var worth := 0.0
	for g in goods:
		worth += float(hh.get(g, 0)) * share * float(price.get(g, 0.0))
	var target := maxf(150.0, 0.15 * worth)
	var got := 0.0
	for g in goods:
		if got >= target * 0.4:
			break
		var mine := int(float(hh.get(g, 0)) * share)
		var p := 0.4 * float(price.get(g, 0.0))
		var q := mini(mine, int(ceil((target * 0.4 - got) / maxf(0.01, p))))
		q = mini(q, int(maxf(0.0, float(mkt["till"])) / maxf(0.01, p)))
		if q <= 0:
			continue
		hh[g] = int(hh[g]) - q
		e["stock"][g] = int(e["stock"].get(g, 0)) + q
		mkt["till"] = float(mkt["till"]) - float(q) * p
		f["purse"] = float(f["purse"]) + float(q) * p
		got += float(q) * p
	if got > 0.0:
		f["pawned"] = float(f.get("pawned", 0.0)) + got
		Families.event(f, "pawned", [int(got)], day)
	return got

## The gruel kitchen feeds a hungry poor family out of the granary (0.07 peck = one meal a person a day); returns days fed.
static func gruel(e: Dictionary, f: Dictionary, days: float) -> float:
	if not e.get("gruel", false) or int(f.get("cls", 0)) > 0:
		return 0.0
	var per := float(B()["granary"]["gruel_peck"]) / float(B()["peck_per_meal"])   # meals a person a day
	var n := int(ceil(float(Families.people(f)) * per * days))
	var q := mini(n, int(e["granary"]))
	if q <= 0:
		return 0.0
	e["granary"] = int(e["granary"]) - q
	TownEcon.led(e, "used", "grain", q)   # eaten at the kitchen
	var rate := float(Families.daily_rates(e, f)["food"])
	return float(q) / maxf(0.01, rate)

# =====================================================================================================
# world gen (part 1 section 1b): ruler, classes and cash, renting, oxen, treasury, the mint
# =====================================================================================================
static func gen_town(w: Dictionary, town: Dictionary, e: Dictionary, rng: RandomNumberGenerator) -> void:
	var D := TownEcon.data()
	var Cs: Dictionary = B()["cash"]
	var T: Dictionary = B()["treasury"]
	# the ruler: temper, tax in coin or in kind, tribute share
	var r := rng.randf()
	var temper := "greedy" if r < 0.3 else ("merciful" if r > 0.75 else "steady")
	var kind := rng.randf() < 0.5
	var share := rng.randf_range(float(T["tribute_kind"][0]), float(T["tribute_kind"][1])) if kind else rng.randf_range(float(T["tribute_coin"][0]), float(T["tribute_coin"][1]))
	e["ruler"] = {"temper": temper, "kind": "kind" if kind else "coin", "tribute": snappedf(share, 0.0001)}
	# classes from what the family holds: the richest few rich, the next quarter middling, the rest poor; cash by class
	var fams: Array = e["fams"]
	var ranked := []
	var land: Dictionary = D["land"]
	for f in fams:
		if f.get("estate", false):
			continue
		var households := maxi(1, int(f.get("households", 1)))
		ranked.append([(float(Families.acres(f)) * float(land["acre_price"]) + float(Families.heads(f)) * float(land["head_price"]) + float((f["owns"] as Array).size()) * 3000.0) / households + rng.randf() * 100.0, f])
	ranked.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var nr := maxi(1, int(round(float(ranked.size()) * float(Cs["rich_share"]))))
	var nm := int(round(float(ranked.size()) * float(Cs["middling_share"])))
	for i in ranked.size():
		var f: Dictionary = ranked[i][1]
		var c := 2 if i < nr else (1 if i < nr + nm else 0)
		f["cls"] = c
		var households := maxi(1, int(f.get("households", 1)))
		var m := float(Families.people(f)) / households
		var kk := rng.randf_range(float(Cs["k"][0]), float(Cs["k"][1]))
		var cash := 0.0
		match c:
			0: cash = (float(Cs["poor"][0]) + float(Cs["poor"][1]) * sqrt(m)) * kk
			1: cash = (float(Cs["middling"][0]) + float(Cs["middling"][1]) * m) * kk
			2: cash = (float(Cs["rich"][0]) + float(Cs["rich"][1]) * m) * kk
		if not (f["owns"] as Array).is_empty():
			cash += float(Cs["business"])
		f["purse"] = snappedf(cash * households, 0.01)
	# homes: who owns, who rents from the town's rich landlords (by class and walk of life)
	var R: Dictionary = B()["rent"]["own"]
	var rich := []
	for f in fams:
		if not f.get("estate", false) and int(f.get("cls", 0)) == 2:
			rich.append(int(f["id"]))
	var ri := 0
	for x in ranked:
		var f: Dictionary = x[1]
		var walk := "labourer"
		var c2 := int(f["cls"])
		if c2 == 2:
			walk = "rich"
		elif Families.acres(f) > 0 or Families.heads(f) > 0:
			walk = "farmer"
		elif c2 == 1:
			walk = "middling"
		elif not (f["owns"] as Array).is_empty():
			walk = "craftsman"
			for bid in f["owns"]:
				if e["biz"][int(bid)]["type"] == "market":
					walk = "merchant"
		if rng.randf() >= float(R.get(walk, 0.25)) and not rich.is_empty() and int(f["homes"]) > 0:
			var lord := int(rich[ri % rich.size()])
			ri += 1
			if lord != int(f["id"]):
				f["landlord"] = lord
	# farm families keep last year's food in the barns until the early grain (pre-history) [ours: 60 days of it]
	for f in fams:
		if not f.get("estate", false) and Families.acres(f) > 0:
			f["hv"] = float(Families.people(f)) * float(TownEcon.data()["needs"]["food"]) * 60.0
	# treasury at the barge start line for the town's people; the money need is set after (index 1 at start)
	e["pop0"] = int(e["pop"])
	e["treasury"] = treasury_lines(e)["start"]
	e["svc_scale"] = 1.0
	e["surcharge"] = 0.0
	e["dwage"] = float(B()["labour"]["base"])
	e["pl"] = 1.0

## Oxen: farm families work their fields with oxen, one per 8 acres (Douglas's default for v0.010).
static func gen_oxen(e: Dictionary) -> void:
	var aph := float(TownEcon.data()["land"]["acres_per_hand"])
	for f in e["fams"]:
		f["ox"] = int(ceil(float(Families.acres(f)) / aph))

## The mint (barge part 1: in the faction's seat and mining towns): a town-owned row of real minters.
static func gen_mint(town: Dictionary, e: Dictionary) -> void:
	var mining := String(town.get("specialty", "")) == "mining" or (e["deposits"] as Dictionary).has("copper_ore") and (e["deposits"] as Dictionary).has("tin_ore")
	if not (town.get("capital", false) or mining):
		return
	var b: Dictionary = Businesses._row(e, "mint", -1, int(B()["coin"]["minters"]), TownEcon.data())
	b["till"] = float(b["wage"]) * float(b["cap"]) * 14.0
	e["mint_biz"] = int(b["id"])

## Rent a week for a house (value x 0.008 a month; campaign/barge_views.gd).
static func rent_week(e: Dictionary) -> float: return BargeViews.rent_week(e)
