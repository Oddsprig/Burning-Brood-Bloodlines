class_name Caravans
extends RefCounted
## Merchant caravans: warbands of kind "caravan" that carry REAL goods and gold by road between neighbouring
## towns (economy spec 1, section 9).
##
## caravan warband extra fields: {origin (home town), dest (where it is going now), leg: out|home,
##   cargo: {items: Array[Item], goods: {good: int}}, gold (the merchants' purse), state: waiting|travel,
##   depart_day, escort: contract id or "", away: days the escort has been out of range}
## - The town turn (TownEcon) plans trade: one caravan per town at a time, to the road partner where its surplus
##   is wanted. The treasury funds the purse; the caravan buys real counts from the origin market at the
##   origin price (gold to the origin market). Cargo exists only on the wagons.
## - At the destination it sells to the market at that town's price (gold from that market) and buys what its
##   home town lacks, then goes home, where the return cargo goes into the market and the purse back to the
##   treasury. Caravans from towns that know bronze better carry the know-how (a small nudge).
## - Hostile bands (war, or player-hostile raiders) attack them through CampaignWorld's clash logic; a lost
##   caravan's cargo and purse are gone.
## - Escort contracts (Contracts kind "escort"): the caravan waits for the company, halts when it strays beyond
##   ESCORT_RADIUS, and fails the contract after MAX_AWAY days away. Done when it reaches the destination.
## - The player may raid caravans (can_raid hook): battle vs the guards; on a win the company takes part of
##   the real cargo (PLUNDER_SHARE, the rest is lost in the fight) and the purse; standing falls with the
##   owner town and faction, more if witnesses (guards) survive.

const MAX_CARAVANS := 8
const SPEED := 0.85            # x WARBAND_SPEED; slower than the company
const ESCORT_RADIUS := 170.0   # px
const MAX_AWAY := 0.75         # days out of escort range before the contract fails
const UNPAID_WAIT_DAYS := 30   # daily retries while home cannot pay; then the remainder is consigned and the slot frees
const MAX_ITEMS := 6
const MAX_GOODS := 30.0        # per good per caravan without an economy (stand-in towns)
const CAPACITY_KG := 2500.0    # wagons [ours]
const PURSE_SHARE := 0.3       # of the treasury, capped at PURSE_MAX
const PURSE_MAX := 800.0 * TownEcon.COIN
const DUTY := 0.03             # barge part 4 section 1: duties of 3% of caravan cargo in and out
const PLUNDER_SHARE := 0.6     # [ours]
const TOWN_RAID_REP := -10     # owner town; doubled with witnesses [ours]
const WITNESS_REP := -6        # extra faction standing when guards live to tell [ours]
const RAID_REP := Diplomacy.RAID_CARAVAN   # diplomacy: raiding their caravan -12 (folds in v0.004's raid hit)

## Road neighbours of a town a caravan may go to: [{id, faction, dist}].
## Diplomacy: never between HOSTILE or WAR pairs (Diplomacy.trade_ok).
static func trade_partners(w: Dictionary, town: Dictionary) -> Array:
	var out := []
	for l in town.get("road_links", []):
		var o: Dictionary = w["towns"].get(l["id"], {})
		if o.is_empty():
			continue
		if Diplomacy.trade_ok(w, o["faction"], town["faction"]):
			out.append(l)
	return out

## Diplomacy: pick a destination, weight x1.5 toward trade-pact partners.
static func pick_partner(w: Dictionary, town: Dictionary, partners: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for l in partners:
		total += Diplomacy.route_weight(w, town["faction"], l["faction"])
	var r := rng.randf() * total
	for l in partners:
		r -= Diplomacy.route_weight(w, town["faction"], l["faction"])
		if r <= 0.0:
			return l["id"]
	return partners[-1]["id"]

## World size: a caravan walks the roads' own points (the roads world gen laid between towns), not a grid path: the
## fewest-px chain of roads from one town to the other (one road for neighbours; arms convoys may cross several).
## Ends on the town's own spot when it is passable. Empty when no road chain joins them (the caller falls back to
## CampaignWorld.find_path). The road graph is built once per world (static cache, keyed by the roads array).
static var _rg_roads: Array = []
static var _rg: Dictionary = {}   # town id -> [[other town id, road index, length px]]

static func road_path(w: Dictionary, from_tid: String, to_tid: String) -> Array:
	var roads: Array = w.get("roads", [])
	if from_tid == to_tid or roads.is_empty() or not w["towns"].has(from_tid) or not w["towns"].has(to_tid):
		return []
	if not is_same(_rg_roads, roads):
		_rg_roads = roads
		_rg = {}
		for i in roads.size():
			var r: Dictionary = roads[i]
			var pts: Array = r["pts"]
			if pts.size() < 2:
				continue
			var ln := CampaignWorld.path_length(pts[0], pts)
			for pr in [[String(r["a"]), String(r["b"])], [String(r["b"]), String(r["a"])]]:
				if not _rg.has(pr[0]):
					_rg[pr[0]] = []
				(_rg[pr[0]] as Array).append([pr[1], i, ln])
	# Dijkstra over the towns (a few dozen nodes: the plain O(n^2) form)
	var dist := {from_tid: 0.0}
	var via := {}   # town -> [previous town, road index]
	var done := {}
	while true:
		var cur := ""; var cd := INF
		for tt in dist:
			if not done.has(tt) and float(dist[tt]) < cd:
				cd = float(dist[tt]); cur = tt
		if cur == "" or cur == to_tid:
			break
		done[cur] = true
		for l in _rg.get(cur, []):
			var nd := cd + float(l[2])
			if nd < float(dist.get(l[0], INF)):
				dist[l[0]] = nd
				via[l[0]] = [cur, int(l[1])]
	if not via.has(to_tid):
		return []
	var chain := []   # [road index, walked from its a end]
	var at := to_tid
	while at != from_tid:
		var v: Array = via[at]
		chain.push_front([int(v[1]), String(roads[int(v[1])]["a"]) == String(v[0])])
		at = String(v[0])
	var out := []
	for c in chain:
		var pts: Array = (roads[int(c[0])]["pts"] as Array).duplicate()
		if not bool(c[1]):
			pts.reverse()
		if not out.is_empty() and (out[-1] as Vector2).is_equal_approx(pts[0]):
			pts.remove_at(0)
		out.append_array(pts)
	var tp: Vector2 = w["towns"][to_tid]["pos"]
	if CampaignWorld.passable(w, tp) and WorldGen.cell_of(tp) == WorldGen.cell_of(out[-1]):
		out.append(tp)
	return out

## The caravan's way from where it stands to a town: the roads, else a grid path (no road chain).
static func way(w: Dictionary, wb: Dictionary, from_tid: String, to_tid: String) -> Array:
	var p := road_path(w, from_tid, to_tid)
	if p.is_empty():
		p = CampaignWorld.find_path(w, wb["pos"], w["towns"][to_tid]["pos"])
	return p

## World size: the cap grows with the land (and so with the towns): MAX_CARAVANS on the normal map.
static func max_caravans(w: Dictionary) -> int:
	return roundi(MAX_CARAVANS * WorldGen.tf_of(w))

static func count(w: Dictionary) -> int:
	var n := 0
	for wid in w["warbands"]:
		if w["warbands"][wid]["kind"] == "caravan":
			n += 1
	for m in CampaignWorld.mustering(w):   # world size: a caravan whose guards are still being made counts
		if String(m["kind"]) == "caravan":
			n += 1
	return n

## Retry unpaid home cargo once a day. Parked wagons count against the caravan limits until UNPAID_WAIT_DAYS
## (unpaid_wait, saved on the warband). Whatever the home market still cannot buy is then consigned into its
## stock and shop, and the wagons leave.
static func daily(game, _rng: RandomNumberGenerator) -> void:
	for wid in game.world.get("warbands", {}).keys():
		var wb: Dictionary = game.world["warbands"][wid]
		if wb.get("kind", "") != "caravan" or wb.get("state", "") != "unpaid":
			continue
		if not wb.has("unpaid_wait"):
			wb["unpaid_wait"] = 0
		if _come_home(game, wb):
			CampaignWorld.remove_warband(game, wid)
			continue
		wb["unpaid_wait"] = int(wb["unpaid_wait"]) + 1
		var home: Dictionary = game.world["towns"].get(wb.get("origin", ""), {})
		if int(wb["unpaid_wait"]) >= UNPAID_WAIT_DAYS and TownEcon.has_econ(home):
			_consign_unpaid(game, wb)
			CampaignWorld.remove_warband(game, wid)

# ------------------------------------------------------------------ what to carry
## Units of g the origin can spare (above what it needs on hand).
static func surplus(town: Dictionary, g: String) -> int:
	return int(Goods.supply(town, g) - Goods.target(town, g) * 1.1)

## Units of g the town would take before its price falls to normal.
static func wanted(town: Dictionary, g: String) -> int:
	return int(Goods.target(town, g) - Goods.supply(town, g))

## v0.048: one cash receipt for both the quote and actual settlement.
static func _totals() -> Dictionary:
	return {"buy_cost": 0.0, "sale_value": 0.0, "duties": 0.0, "crew": 0.0, "lost_coin": 0.0, "net": 0.0}

static func _add(totals: Dictionary, key: String, amount: float) -> void:
	if totals.is_empty(): return
	totals[key] = float(totals.get(key, 0.0)) + amount
	totals["net"] = float(totals["sale_value"]) - float(totals["buy_cost"]) - float(totals["duties"]) - float(totals["crew"]) - float(totals["lost_coin"])

static func receipt_add(wb: Dictionary, key: String, amount: float) -> void:
	_add(wb.get("receipt", {}).get("realized", {}), key, amount)

static func trade_purse(town: Dictionary) -> float:
	if not TownEcon.has_econ(town): return 0.0
	return minf(maxf(0.0, float(town["econ"]["treasury"])) * PURSE_SHARE, PURSE_MAX)

static func trip_days(pos: Vector2, path: Array) -> float:
	return CampaignWorld.path_length(pos, path) / (CampaignWorld.WARBAND_SPEED * SPEED) * 2.0 + 2.0

static func cargo_weight(cargo: Dictionary) -> float:
	var kg := Supplies.weight(cargo.get("goods", {}))
	for it in cargo.get("items", []):
		kg += (it as Item).mass()
	return kg

## Copy only the trade's mutable holders, never the people/Items or the whole world.
static func _trade_copy(town: Dictionary) -> Dictionary:
	var out := town.duplicate()
	out["shop"] = (town.get("shop", []) as Array).duplicate()
	out["goods"] = (town.get("goods", {}) as Dictionary).duplicate()
	if TownEcon.has_econ(town):
		var e: Dictionary = town["econ"].duplicate()
		for key in ["stock", "stats", "why_hint"]:
			e[key] = (town["econ"].get(key, {}) as Dictionary).duplicate(true)
		e["biz"] = (e["biz"] as Array).duplicate()
		e["biz"][int(e["mkt"])] = (e["biz"][int(e["mkt"])] as Dictionary).duplicate()
		out["econ"] = e
	return out

## Settle a whole round trip on detached trade holders at today's prices. In particular, buying spreads,
## duties, purse/weight limits, return purchases and the buyer's actual till all use the real settlement paths.
## A private RNG previews the existing cargo/guard/position draws without consuming the caller's stream.
static func quote_trip(w: Dictionary, origin: Dictionary, dest: Dictionary, rng: RandomNumberGenerator = null,
		force: bool = false, preset: Dictionary = {}) -> Dictionary:
	var o := _trade_copy(origin); var d := _trade_copy(dest)
	var preview := RandomNumberGenerator.new()
	if rng != null: preview.state = rng.state
	else: preview.seed = hash([int(w.get("seed", 0)), origin["id"], dest["id"], "caravan_quote"])
	var funded := trade_purse(o)
	var cargo := load_cargo(o, d, preview, force, funded) if preset.is_empty() else \
		{"items": (preset.get("items", []) as Array).duplicate(), "goods": (preset.get("goods", {}) as Dictionary).duplicate(), "gold": funded}
	var purse := float(cargo["gold"])
	cargo.erase("gold")
	var totals := _totals()
	_add(totals, "buy_cost", funded - purse)
	var guards := 2 + preview.randi_range(0, 2) + int(origin["wealth"]) / 2
	var pos: Vector2 = origin["pos"] + Vector2(preview.randf_range(-14, 14), 18)
	pos = CampaignWorld.nearest_passable(w, pos)
	var path := way(w, {"pos": pos}, String(origin["id"]), String(dest["id"]))
	var days := trip_days(pos, path)
	var crew := People.crew_bill(guards, days) if TownEcon.has_econ(o) else 0.0
	var ready := not path.is_empty() and (force or not cargo_empty(cargo))
	if TownEcon.has_econ(o):
		var market: Dictionary = o["econ"]["biz"][int(o["econ"]["mkt"])]
		ready = ready and float(market["till"]) >= crew
		# The same till pays the crew before buying the returning cargo.
		market["till"] = maxf(0.0, float(market["till"]) - crew)
	_add(totals, "crew", crew)
	var kg := cargo_weight(cargo)
	var wb := {"cargo": cargo, "gold": purse, "receipt": {"realized": totals}}
	wb["gold"] = float(wb["gold"]) + sell_cargo(d, cargo, String(origin.get("name", "")), totals)
	buy_return(d, o, wb)
	sell_cargo(o, cargo, "returning wagons", totals, false)
	return {"expected": totals, "days": maxf(4.0, days), "cargo_kg": kg, "ready": ready}

## Expected NET coins, including the return leg and its crew, rather than gross price differences.
static func trade_value(origin: Dictionary, dest: Dictionary, w: Dictionary = {}) -> float:
	var quote := quote_trip(Game.world if w.is_empty() else w, origin, dest)
	return float(quote["expected"]["net"]) if quote["ready"] else 0.0

static func _finish_receipt(game, wb: Dictionary, status: String) -> void:
	if not wb.has("receipt"): return
	var receipt: Dictionary = wb["receipt"]
	receipt["status"] = status
	receipt["day"] = float(game.day)
	receipt["unpaid_cargo"] = cargo_text(wb.get("cargo", {})) if status == "unpaid" else ""
	if status == "unpaid": return
	var home: Dictionary = game.world["towns"].get(wb.get("origin", ""), {})
	if not TownEcon.has_econ(home): return
	var history: Array = home["econ"].get("caravan_receipts", [])
	history.append(receipt.duplicate(true))
	while history.size() > 32: history.pop_front()
	home["econ"]["caravan_receipts"] = history

## Buy real cargo in the origin market with the purse: its surplus where the destination pays more.
## Returns {items, goods, gold (purse left)}; the origin's stock and market till change now.
static func load_cargo(origin: Dictionary, dest: Dictionary, rng: RandomNumberGenerator, force: bool, purse: float = 0.0) -> Dictionary:
	var items := []
	var goods := {}
	var econ := TownEcon.has_econ(origin)
	if not econ:
		# stand-in towns: the old rule (half the shop at most, a third of the goods it has more of)
		var shop: Array = origin.get("shop", [])
		var n := mini(MAX_ITEMS, mini(1 + int(origin.get("wealth", 1)), shop.size() / 2))
		if force and n == 0 and not shop.is_empty():
			n = 1
		for i in n:
			items.append(shop.pop_at(rng.randi() % shop.size()))
		if not origin.has("goods"):
			Goods.init_town(origin)
		for g in (origin["goods"] as Dictionary).keys():
			var q := int(minf(MAX_GOODS, Goods.supply(origin, g) * 0.35))
			if q >= 1 and Goods.supply(origin, g) > Goods.supply(dest, g) + 5.0:
				origin["goods"][g] = int(origin["goods"][g]) - q
				goods[g] = q
		return {"items": items, "goods": goods, "gold": purse}
	var e: Dictionary = origin["econ"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var kg_left := CAPACITY_KG
	var opts := []
	for g in Goods.ids():
		var s := surplus(origin, g)
		if s <= 0:
			continue
		var po := Goods.price_f(origin, g)
		var pd := Goods.price_f(dest, g) if TownEcon.has_econ(dest) else po * 1.2
		var spec_bonus := 1.15 if _is_specialty(e, g) else 1.0
		if pd * spec_bonus < po * 1.15 and not force:
			continue
		opts.append([(pd * spec_bonus - po) / maxf(0.01, po), g, s, po])
	opts.sort_custom(func(a, b): return a[0] > b[0])
	for o in opts:
		var g: String = o[1]
		var po: float = o[3]
		var kg := float(Goods.table()[g].get("weight", 1.0))
		var q := mini(int(o[2]), maxi(wanted(dest, g), 0) + 20) if TownEcon.has_econ(dest) else int(o[2]) / 2
		q = mini(q, int(kg_left / maxf(0.05, kg)))
		q = mini(q, int(purse / po))
		if q <= 0:
			continue
		var t := Goods.take(origin, g, q)
		goods[g] = t
		var cost := float(t) * po
		purse -= cost
		mkt["till"] = float(mkt["till"]) + cost
		e["stats"]["sales"] = float(e["stats"]["sales"]) + cost
		e["stats"]["trade_out"] = float(e["stats"].get("trade_out", 0.0)) + cost
		kg_left -= float(t) * kg
	# gear when the stalls are fuller than the town needs (or an escort job must carry something)
	var shop2: Array = origin.get("shop", [])
	var cap := Businesses.arms_cap(origin)
	var spare := shop2.size() - int(cap * 0.5)
	if force and spare <= 0 and items.is_empty() and goods.is_empty() and not shop2.is_empty():
		spare = 1
	# arms trade: first the pieces the destination's armory is short of (and this town is not)
	for it in ArmsTrade.export_picks(origin, dest, MAX_ITEMS):
		var pe := Economy.base_value(origin, it) * 0.8
		if pe > purse or it.mass() > kg_left:
			continue
		shop2.erase(it)
		items.append(it)
		purse -= pe
		kg_left -= it.mass()
		mkt["till"] = float(mkt["till"]) + pe
		e["stats"]["trade_out"] = float(e["stats"].get("trade_out", 0.0)) + pe
	var ni := mini(MAX_ITEMS - items.size(), spare - items.size())
	for i in ni:
		if shop2.is_empty():
			break
		var it: Item = shop2[rng.randi() % shop2.size()]
		var p := Economy.base_value(origin, it) * 0.8
		if p > purse or it.mass() > kg_left:
			continue
		shop2.erase(it)
		items.append(it)
		purse -= p
		kg_left -= it.mass()
		mkt["till"] = float(mkt["till"]) + p
		e["stats"]["trade_out"] = float(e["stats"].get("trade_out", 0.0)) + p
	return {"items": items, "goods": goods, "gold": purse}

static func _is_specialty(e: Dictionary, g: String) -> bool:
	var D := TownEcon.data()
	for s in e.get("specialties", []):
		var sp: Dictionary = D["specialties"][s]
		if sp.get("ore", "") == g:
			return true
		for r in D["businesses"][sp["biz"]]["recipes"]:
			if (r["out"] as Dictionary).has(g):
				return true
	return false

static func cargo_empty(cargo: Dictionary) -> bool:
	return (cargo.get("items", []) as Array).is_empty() and (cargo.get("goods", {}) as Dictionary).is_empty()

## Sells the cargo into a town's market at its price (the market pays what it can; unsold goods stay on
## the wagons). Returns the gold received.
static func sell_cargo(town: Dictionary, cargo: Dictionary, from_name: String, totals: Dictionary = {}, charge_duty: bool = true) -> float:
	var got := 0.0
	if not TownEcon.has_econ(town):
		return 0.0   # no paying market: ownership stays on the wagons
	var e: Dictionary = town["econ"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var share := float(TownEcon.data()["market"]["buy_share"])
	var goods: Dictionary = cargo.get("goods", {})
	if not e.has("why_hint"):
		e["why_hint"] = {}
	for g in goods.keys():
		var q := int(goods[g])
		var p := Goods.price_f(town, g) * share
		q = mini(q, int(maxf(0.0, float(mkt["till"])) / maxf(0.01, p)))
		if q <= 0:
			continue
		e["stock"][g] = int(e["stock"].get(g, 0)) + q
		var ci: Dictionary = e["stats"].get("cargo_in", {})
		ci[g] = int(ci.get(g, 0)) + q
		e["stats"]["cargo_in"] = ci
		goods[g] = int(goods[g]) - q
		if int(goods[g]) <= 0:
			goods.erase(g)
		mkt["till"] = float(mkt["till"]) - float(q) * p
		got += float(q) * p
		e["why_hint"][g] = "a caravan from %s" % from_name
	var items: Array = cargo.get("items", [])
	for it in items.duplicate():
		var p2 := Economy.base_value(town, it) * float(TownEcon.data()["market"]["arms_buy_share"])
		if float(mkt["till"]) < p2:
			continue
		mkt["till"] = float(mkt["till"]) - p2
		got += p2
		items.erase(it)
		(town["shop"] as Array).append(it)
	e["stats"]["trade_in"] = float(e["stats"].get("trade_in", 0.0)) + got
	# barge part 4 section 1: duties of 3% on cargo coming in, to the town's treasury out of the merchants' takings
	var duty := got * DUTY if charge_duty else 0.0
	e["treasury"] = float(e["treasury"]) + duty
	e["stats"]["duties"] = float(e["stats"].get("duties", 0.0)) + duty
	_add(totals, "sale_value", got)
	_add(totals, "duties", duty)
	return got - duty

## Buys what the home town lacks in this market for the trip home.
static func buy_return(here: Dictionary, home: Dictionary, wb: Dictionary) -> void:
	if not TownEcon.has_econ(here) or not TownEcon.has_econ(home):
		return
	var e: Dictionary = here["econ"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var goods: Dictionary = wb["cargo"]["goods"]
	var purse_before := float(wb["gold"])
	var kg_used := cargo_weight(wb["cargo"])
	var opts := []
	for g in Goods.ids():
		var want := wanted(home, g)
		var s := surplus(here, g)
		if want <= 0 or s <= 0:
			continue
		var ph := Goods.price_f(home, g); var pt := Goods.price_f(here, g)
		if ph < pt * 1.2:
			continue
		opts.append([ph / pt, g, mini(want, s), pt])
	opts.sort_custom(func(a, b): return a[0] > b[0])
	for o in opts:
		var g: String = o[1]
		var kg := float(Goods.table()[g].get("weight", 1.0))
		var q := mini(int(o[2]), int((CAPACITY_KG - kg_used) / maxf(0.05, kg)))
		q = mini(q, int(float(wb["gold"]) * 0.8 / float(o[3])))
		if q <= 0:
			continue
		var t := Goods.take(here, g, q)
		goods[g] = int(goods.get(g, 0)) + t
		var cost := float(t) * float(o[3])
		wb["gold"] = float(wb["gold"]) - cost
		mkt["till"] = float(mkt["till"]) + cost
		e["stats"]["sales"] = float(e["stats"]["sales"]) + cost
		kg_used += float(t) * kg
	ArmsTrade.import_buys(here, home, wb)   # arms trade: pieces the home armory is short of
	receipt_add(wb, "buy_cost", purse_before - float(wb["gold"]))

## Put cargo into a town without paying (stand-in towns; a caravan that could not leave puts it back).
static func unload(town: Dictionary, cargo: Dictionary) -> void:
	for it in cargo.get("items", []):
		(town["shop"] as Array).append(it)
	if TownEcon.has_econ(town):
		var st: Dictionary = town["econ"]["stock"]
		for g in cargo.get("goods", {}):
			st[g] = int(st.get(g, 0)) + int(cargo["goods"][g])
		return
	if not town.has("goods"):
		Goods.init_town(town)
	for g in cargo.get("goods", {}):
		town["goods"][g] = int(town["goods"].get(g, 0)) + int(cargo["goods"][g])

## "4 pieces of gear, 180 meals' worth of barley, 40 gold" for scouting panels.
static func cargo_text(cargo: Dictionary, gold: float = 0.0) -> String:
	var parts := []
	var n := (cargo.get("items", []) as Array).size()
	if n > 0:
		parts.append("%d piece%s of gear" % [n, "" if n == 1 else "s"])
	for g in cargo.get("goods", {}):
		parts.append("%d %s of %s" % [int(cargo["goods"][g]), Goods.unit_of(g), Goods.good_name(g)])
	if gold >= 1.0:
		parts.append("a purse of about %d coins" % int(round(gold / 10.0) * 10))
	return ", ".join(parts) if not parts.is_empty() else "empty carts"

## Spawn a caravan at town `tid` bound for `dest` (random trade partner when empty). Returns its warband id.
## Escort caravans always leave (with whatever little there is); others stay home when there is nothing to carry.
## preset: existing gathered cargo (including preserved legacy shipments).
## muster_head (world size): the guards are made over several work jobs (CampaignWorld.muster_start; then: what the
## muster does when the caravan is whole, e.g. an arms convoy's batch); returns "+" and the caravan sails from its
## last job ("" when it never got that far). own_rng: rng is the caller's own seeded generator (the muster keeps its
## state).
static func spawn(game, tid: String, rng: RandomNumberGenerator, dest: String = "", escort: String = "", preset: Dictionary = {},
		muster_head: Array = [], then: Dictionary = {"then": "caravan"}, own_rng: bool = false) -> String:
	var w: Dictionary = game.world
	var t: Dictionary = w["towns"].get(tid, {})
	if t.is_empty() or Monsters.suspended_band({"faction": t.get("faction", ""), "kind": "caravan"}):
		return ""
	if dest == "":
		var partners := trade_partners(w, t)
		if partners.is_empty():
			return ""
		dest = pick_partner(w, t, partners, rng)
	var d: Dictionary = w["towns"].get(dest, {})
	if d.is_empty():
		return ""
	var quote := quote_trip(w, t, d, rng, escort != "", preset)
	# Escort jobs/preserved consignments are obligations, rather than speculative trade.
	if escort == "" and preset.is_empty() and TownEcon.has_econ(t) \
			and (not quote["ready"] or float(quote["expected"]["net"]) <= 0.0):
		return ""
	# the treasury funds the merchants' purse
	var purse := trade_purse(t)
	var funded := purse
	if TownEcon.has_econ(t):
		t["econ"]["treasury"] = float(t["econ"]["treasury"]) - purse
	var cargo := load_cargo(t, d, rng, escort != "", purse) if preset.is_empty() else \
		{"items": preset.get("items", []), "goods": preset.get("goods", {}), "gold": purse}
	purse = float(cargo["gold"])
	cargo.erase("gold")
	if cargo_empty(cargo) and escort == "":
		if TownEcon.has_econ(t):
			t["econ"]["treasury"] = float(t["econ"]["treasury"]) + purse
		return ""
	var guards := 2 + rng.randi_range(0, 2) + int(t["wealth"]) / 2
	var pos: Vector2 = t["pos"] + Vector2(rng.randf_range(-14, 14), 18)
	var extra := {"home": tid, "origin": tid, "dest": dest, "leg": "out", "cargo": cargo, "gold": purse, "escort": escort, "away": 0.0,
		"state": "waiting" if escort != "" else "travel", "depart_day": game.day}
	extra["receipt"] = {"origin": tid, "destination": dest, "depart_day": float(game.day), "status": "out",
		"expected": quote["expected"], "realized": _totals(), "trip_days": quote["days"]}
	receipt_add(extra, "buy_cost", funded - purse)
	if not muster_head.is_empty():
		CampaignWorld.muster_start(game, muster_head, t["faction"], pos, guards, "caravan", extra, rng, own_rng, then)
		return "+"   # mustering: the caravan sails from the muster's last job
	var wid := CampaignWorld.spawn_warband(game, t["faction"], pos, guards, "caravan", rng, extra)
	return sail(game, wid, rng)

## The caravan (on the map, its guards made) takes the road: its way, its crew (the owner pays for the trip, or nobody
## signs on and it stays home), its guards' kit (ArmsTrade.kit_guards: the armory, then the stalls). Returns its id,
## "" when it did not sail.
static func sail(game, wid: String, rng: RandomNumberGenerator) -> String:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"].get(wid, {})
	if wb.is_empty(): return ""
	if wb.has("receipt"): wb["receipt"]["id"] = wid
	var tid := String(wb["origin"])
	var t: Dictionary = w["towns"][tid]
	var _t0 := Time.get_ticks_usec()
	wb["path"] = way(w, wb, tid, String(wb["dest"]))   # world size: by the roads (a grid path only without one)
	if TownEcon.prof_on: _t0 = TownEcon._prof("cv_path", _t0)
	var trip := trip_days(wb["pos"], wb["path"])
	# economy: the guards are people of the town's families with the town's gear; the owner (the merchants)
	# must be able to pay the crew for the trip, or nobody signs on and the caravan doesn't sail
	if (wb["path"] as Array).is_empty() or not People.hire_crew(game, t, wb, rng, trip):
		if _come_home(game, wb): CampaignWorld.remove_warband(game, wid)
		return ""
	if TownEcon.prof_on: _t0 = TownEcon._prof("cv_crew", _t0)
	if TownEcon.has_econ(t):
		ArmsTrade.kit_guards(game, t, wb)   # v0.014: the guards' kit from the armory first, then the stalls
	if TownEcon.prof_on: _t0 = TownEcon._prof("cv_outfit", _t0)
	return wid

## Per-step movement (called from CampaignWorld._move_warbands). Cheap: no pathfinding here.
static func step(game, wid: String, wb: Dictionary, dt: float) -> void:
	var w: Dictionary = game.world
	var party: Dictionary = w["party"]
	if wb.get("escort", "") != "":
		var c: Dictionary = game.contract
		if c.get("id", "") != wb["escort"] or c.get("state", "") != "active":
			wb["escort"] = ""   # contract over: go on alone
			wb["state"] = "travel"
		else:
			var near: bool = game.location == "" and (party["pos"] as Vector2).distance_to(wb["pos"]) <= ESCORT_RADIUS
			if wb["state"] == "waiting":
				if not near:
					return
				wb["state"] = "travel"
				CampaignWorld.log_event(game, "The caravan to %s sets out under your escort." % w["towns"][wb["dest"]]["name"])
			if not near:
				if game.location == "":
					wb["away"] = float(wb["away"]) + dt
					if float(wb["away"]) > MAX_AWAY:
						Contracts.fail(game, "The merchants gave up on you and went on alone.")
				return   # merchants halt without their escort
			wb["away"] = 0.0
	if wb["state"] != "travel":
		return
	if CampaignWorld._step_along(w, wb, CampaignWorld.WARBAND_SPEED * SPEED * CampaignWorld.smooth_speed(w, wb, dt) * dt):
		arrive(game, wid)

## Arrival at the destination: sell, carry the know-how, buy the home town's needs and turn for home.
## Arrival home: the return cargo goes into the market, the purse back to the treasury.
static func arrive(game, wid: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"].get(wid, {})
	if wb.is_empty():
		return
	var origin: Dictionary = w["towns"].get(wb["origin"], {})
	if wb.get("leg", "out") == "home":
		if _come_home(game, wb): CampaignWorld.remove_warband(game, wid)
		return
	var dest: Dictionary = w["towns"].get(wb["dest"], {})
	Sickness.caravan_at(game, wb, dest)   # sickness: the crew's diseases meet the town's (carriers, first-case origin)
	if not dest.is_empty():
		wb["gold"] = float(wb.get("gold", 0.0)) + sell_cargo(dest, wb["cargo"], origin.get("name", "abroad"), wb.get("receipt", {}).get("realized", {}))
		_carry_knowhow(origin, dest, wb["cargo"])
		if wb.has("receipt"):
			wb["receipt"]["unpaid_cargo"] = cargo_text(wb["cargo"]) if not cargo_empty(wb["cargo"]) else ""
		buy_return(dest, origin, wb)
	if not origin.is_empty():
		origin["trade"] = int(origin.get("trade", 0)) + 1
		if int(origin["trade"]) >= 4 + 2 * int(origin["wealth"]) and int(origin["wealth"]) < 5:
			origin["trade"] = 0
			origin["wealth"] = int(origin["wealth"]) + 1
			CampaignWorld.log_event(game, "Trade has made %s richer." % origin["name"])
	var escorted: bool = wb.get("escort", "") != "" and game.contract.get("id", "") == wb["escort"]
	if escorted:
		wb["escort"] = ""
		Contracts.complete(game)
	# turn for home (stand-in towns without an economy: the caravan's work ends here)
	if origin.is_empty() or not TownEcon.has_econ(origin):
		if _come_home(game, wb): CampaignWorld.remove_warband(game, wid)
		return
	wb["leg"] = "home"
	if wb.has("receipt"): wb["receipt"]["status"] = "home"
	wb["last_dest"] = wb["dest"]
	wb["dest"] = wb["origin"]
	wb["state"] = "travel"
	var _t0 := Time.get_ticks_usec()
	wb["path"] = way(w, wb, String(wb["last_dest"]), String(wb["origin"]))   # world size: home by the roads
	if TownEcon.prof_on: TownEcon._prof("cv_path_home", _t0)
	if (wb["path"] as Array).is_empty():
		if _come_home(game, wb): CampaignWorld.remove_warband(game, wid)

## Home: sell only paid quantities, return the purse to its treasury, and keep unpaid cargo on parked wagons.
## The home market has never charged the destination's import duty. Crew/kit are returned only once.
static func _come_home(game, wb: Dictionary) -> bool:
	var home: Dictionary = game.world["towns"].get(wb.get("origin", ""), {})
	wb["escort"] = ""
	if not wb.get("crew_home", false):
		ArmsTrade.guards_home(game, wb)
		People.end_crew(game, wb)
		wb["units"] = []   # returned people must not also remain as guards on parked wagons
		wb["crew_home"] = true
	if not TownEcon.has_econ(home):
		wb["state"] = "unpaid"
		if not wb.has("unpaid_wait"):
			wb["unpaid_wait"] = 0
		_finish_receipt(game, wb, "unpaid")
		return false
	var pay := sell_cargo(home, wb["cargo"], "returning wagons", wb.get("receipt", {}).get("realized", {}), false)
	home["econ"]["treasury"] = float(home["econ"]["treasury"]) + pay + float(wb.get("gold", 0.0))
	wb["gold"] = 0.0
	var done := cargo_empty(wb["cargo"])
	wb["state"] = "unpaid" if not done else "home"
	if not done and not wb.has("unpaid_wait"):
		wb["unpaid_wait"] = 0
	wb["path"] = []
	_finish_receipt(game, wb, "returned" if done else "unpaid")
	return done

## The home market still cannot pay for what is left. Goods go into market stock and Items into the shop
## (unload: no coins minted or spent). Crew and kit use the same return as a normal homecoming.
static func _consign_unpaid(game, wb: Dictionary) -> void:
	var home: Dictionary = game.world["towns"].get(wb.get("origin", ""), {})
	var cargo: Dictionary = wb.get("cargo", {})
	var note := cargo_text(cargo)
	if not wb.get("crew_home", false):
		ArmsTrade.guards_home(game, wb)
		People.end_crew(game, wb)
		wb["units"] = []
		wb["crew_home"] = true
	unload(home, cargo)
	cargo["items"] = []
	cargo["goods"] = {}
	if TownEcon.has_econ(home):
		home["econ"]["treasury"] = float(home["econ"]["treasury"]) + float(wb.get("gold", 0.0))
	wb["gold"] = 0.0
	if wb.has("receipt"):
		wb["receipt"]["consigned"] = note
		wb["receipt"]["unpaid_wait"] = int(wb.get("unpaid_wait", 0))
	wb["state"] = "home"
	_finish_receipt(game, wb, "consigned")

## Material adoption: merchants from a town that knows bronze better spread a little of it (more if they carry
## bronze gear). Never more than the origin knows.
static func _carry_knowhow(origin: Dictionary, dest: Dictionary, cargo: Dictionary) -> void:
	if not TownEcon.has_econ(origin) or not TownEcon.has_econ(dest):
		return
	var K: Dictionary = TownEcon.data()["knowhow"]
	for m in K:
		var ko := Businesses.kh_of(origin["econ"], m)   # v0.014: what the origin's smiths may use (orcs carry no bronze lore)
		var kd := float(dest["econ"]["knowhow"].get(m, 0.0))
		if ko <= kd:
			continue
		var bonus := 1.0
		for it in cargo.get("items", []):
			if it.material == m:
				bonus += 0.25
		dest["econ"]["knowhow"][m] = minf(ko, kd + float(K[m]["caravan"]) * minf(bonus, 2.0))

## Destroyed by a band (or abandoned by its escort): the cargo and purse are gone, nothing is delivered.
static func lost(game, wid: String, by_faction: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"].get(wid, {})
	if wb.is_empty():
		return
	var dest: Dictionary = w["towns"].get(wb["dest"], {})
	var origin: Dictionary = w["towns"].get(wb["origin"], {})
	CampaignWorld.log_event(game, "A caravan from %s to %s was plundered by %s." % [origin.get("name", "?"), dest.get("name", "?"),
		CampaignWorld.faction_the(by_faction)])
	Diplomacy.on_caravan_raided(w, wb["faction"], by_faction)   # diplomacy: grievance -3 against the raider
	var citems: Array = wb["cargo"].get("items", [])
	for i in range(citems.size() - 1, -1, -1):   # v0.014: a legendary piece in the cargo is never lost with the wagons
		if (citems[i] as Item).is_legend():
			var lit: Item = citems[i]
			citems.remove_at(i)
			ArmsTrade._legend_found(game, lit, null, wb["pos"])
	ArmsTrade.field(game, (wb["units"] as Array).filter(func(u): return not u.equip.is_empty()), {}, wb["pos"])   # kit nobody took: left
	_record_loss(wb, 1.0)
	receipt_add(wb, "lost_coin", float(wb.get("gold", 0.0)))
	_finish_receipt(game, wb, "lost")
	People.end_crew(game, wb, (wb["units"] as Array).duplicate())   # the guards fell; the drivers run home
	var escorted: bool = wb.get("escort", "") != "" and game.contract.get("id", "") == wb["escort"]
	CampaignWorld.remove_warband(game, wid)
	if escorted:
		Contracts.fail(game, "The caravan was lost.")

## Cargo and gold gone from the economy (raided, burned): counted for the conservation ledgers.
static func _record_loss(wb: Dictionary, share: float) -> void:
	var lg: Dictionary = TownEcon.goods_lost
	for g in wb["cargo"].get("goods", {}):
		var n := int(round(float(wb["cargo"]["goods"][g]) * share))
		lg[g] = int(lg.get(g, 0)) + n
	lg["arms"] = int(lg.get("arms", 0)) + int(round((wb["cargo"].get("items", []) as Array).size() * share))
	TownEcon.gold_out(float(wb.get("gold", 0.0)) * share)
	if not wb.get("purse_taken", false):
		Barge.drained(Game.world, float(wb.get("gold", 0.0)) * share)   # coinage: a purse nobody took is lost on the road

## The company beat the caravan's guards: it takes PLUNDER_SHARE of the real cargo and the purse; the rest
## of the goods is lost in the fight. Standing falls with the faction (Diplomacy -12) and the owner town
## (town rep), more if guards live to tell of it.
static func plunder(game, wid: String, witnesses: bool = false) -> Dictionary:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"].get(wid, {})
	if wb.is_empty():
		return {}
	var cargo: Dictionary = wb["cargo"]
	var took := {"items": [], "goods": {}}
	var items: Array = cargo.get("items", [])
	for i in range(items.size() - 1, -1, -1):   # v0.014: legendary pieces always go to the winners
		if (items[i] as Item).is_legend():
			var lit: Item = items[i]
			items.remove_at(i)
			game.stash.append(lit)
			took["items"].append(lit)
			Legends.note(lit, float(game.day), "Taken from a plundered caravan by your company.")
	var keep_n := int(ceil(items.size() * PLUNDER_SHARE))
	for i in items.size():
		if i < keep_n:
			game.stash.append(items[i])
			took["items"].append(items[i])
	var lg: Dictionary = TownEcon.goods_lost
	lg["arms"] = int(lg.get("arms", 0)) + items.size() - keep_n
	for g in cargo.get("goods", {}):
		var q := int(cargo["goods"][g])
		var t := int(round(float(q) * PLUNDER_SHARE))
		if t > 0:
			Goods.add_to_company(game, g, float(t))
			took["goods"][g] = t
		lg[g] = int(lg.get(g, 0)) + q - t
	var purse := int(floor(float(wb.get("gold", 0.0))))
	game.gold += purse
	Barge.drained(w, float(wb.get("gold", 0.0)) - float(purse))   # the odd fraction of a coin
	TownEcon.gold_out(float(wb.get("gold", 0.0)))   # out of the town economy (into the company's purse)
	ArmsTrade.guards_home(game, wb)   # arms trade: guards who lived run home with their kit
	People.end_crew(game, wb, (wb["units"] as Array).filter(func(u): return u.dead))   # dead guards: their families' loss
	took["gold"] = purse
	Diplomacy.on_raid(game, wb["faction"])   # diplomacy: -12 (RAID_REP)
	var origin: Dictionary = w["towns"].get(wb.get("origin", ""), {})
	if TownEcon.has_econ(origin):
		origin["econ"]["rep"] = clampi(int(origin["econ"].get("rep", 0)) + TOWN_RAID_REP * (2 if witnesses else 1), -100, 100)
	if witnesses:
		CampaignWorld.change_rep(game, wb["faction"], WITNESS_REP, "Survivors of a raided caravan named the company")
	var dest: Dictionary = w["towns"].get(wb["dest"], {})
	CampaignWorld.log_event(game, "The company plundered a caravan bound for %s: %s." % [dest.get("name", "?"), cargo_text(took, float(purse))])
	receipt_add(wb, "lost_coin", float(wb.get("gold", 0.0)))
	_finish_receipt(game, wb, "plundered")
	CampaignWorld.remove_warband(game, wid)
	if game.contract.get("kind", "") == "arms_raid" and game.contract.get("target_id", "") == wid:
		Contracts.complete(game)   # arms trade: the rival who hired the raid pays
	return took

## Would warband `attacker` fall on caravan `car`? War, or a player-hostile (monster) band of another faction.
static func is_prey(w: Dictionary, attacker: Dictionary, car: Dictionary) -> bool:
	if attacker["kind"] == "caravan" or attacker["faction"] == car["faction"]:
		return false
	if CampaignWorld.at_war(w, attacker["faction"], car["faction"]):
		return true
	if attacker["kind"] == "bandit":   # monsters wave 1: bandit gangs (outlaws, outside diplomacy) rob anyone's caravans
		return true
	# monster raiders (orcs, goblins) prey on caravans of anyone they are not at peace with (diplomacy: HOSTILE)
	# (never in the truce after a peace: war pick 2)
	return DB.factions[attacker["faction"]].get("player_hostile", false) and attacker["kind"] in ["raider", "contract"] \
		and not Diplomacy.trade_ok(w, attacker["faction"], car["faction"]) and not Diplomacy.in_truce(w, attacker["faction"], car["faction"])

## Is the company escorting this caravan and close enough to join a fight?
static func escort_near(game, car: Dictionary) -> bool:
	return car.get("escort", "") != "" and game.contract.get("id", "") == car["escort"] and game.location == "" \
		and (game.world["party"]["pos"] as Vector2).distance_to(car["pos"]) <= ESCORT_RADIUS

## The escorted caravan this company guards (or {}).
static func escorted_caravan(game) -> Dictionary:
	var c: Dictionary = game.contract
	if c.get("kind", "") != "escort":
		return {}
	return game.world["warbands"].get(c.get("target_id", ""), {})

## Raiding hook: the player may attack any caravan except the one it is escorting.
static func can_raid(game, wid: String) -> bool:
	var wb: Dictionary = game.world.get("warbands", {}).get(wid, {})
	if Diplomacy.peace_bound(game.world, Diplomacy.player_realm(game.world), str(wb.get("faction", ""))): return false
	return game.contract.get("kind", "") != "escort" or game.contract.get("target_id", "") != wid

static func describe(w: Dictionary, wb: Dictionary) -> String:
	var o: Dictionary = w["towns"].get(wb.get("origin", ""), {})
	var d: Dictionary = w["towns"].get(wb.get("dest", ""), {})
	var home: bool = wb.get("leg", "out") == "home"
	return "Merchants of %s %s %s, %d guards, carrying %s." % [o.get("name", "?"), "heading home from" if home else "bound for",
		d.get("name", "?") if not home else w["towns"].get(wb.get("last_dest", ""), {}).get("name", "market"),
		(wb["units"] as Array).size(), cargo_text(wb.get("cargo", {}), float(wb.get("gold", 0.0)))]
