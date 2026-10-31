class_name WorldAudit
extends RefCounted
## v0.075 whole-world money and stock audit (build_strategy: daily conservation check). Read-only: census() counts
## every coin and every counted good where it is held; between two censuses, what the holders gained or lost must
## equal what the named mints, harvests and sinks booked. Anything else is a leak (coin or goods made or lost by
## a move that was not booked).
##
## Coin. Held: town treasuries, farm tills, land funds, supply-order reserves, business tills, family purses (towns),
## realm treasuries and loot chests, lair hoards, caravan purses, other bands' purses, the company's army purse.
##   change in held = cast - melted - drained   (Barge's world coin ledger: the mint casts, melting and wear drain)
## Goods (grain, meat, fresh meat, wood, ores, bars, scrap; "metal" is the ores, bars and scrap together).
## Held: town markets, barns, households, families' stones, the granary (grain); caravan cargo, the company's own
## goods. Band stores are the army's mess (Supplies.provision books what it buys as used in the town), so they are
## outside the counted holders, like the company's provisions; their change is reported, not balanced.
##   change in held = made - used - spoil (every town's ledger) - lost (goods destroyed outside a town)
##                    + moved in - moved out (the world flow book below: a town booked the good used, but it went to
##                    another counted holder, or a holder outside the towns made or ate it)
## Arms (finished weapons and armour a town holds: its armoury and its stalls): change in held = made - used (town
## ledgers, good "arms"; moves between the armoury and the stalls are inside the holdings).
## Treasure pieces (house treasure rooms, merchants' court stock, realms' carried-off hoards): reported.

const GOODS := ["grain", "meat", "fresh_meat", "wood", "copper_ore", "tin_ore", "iron_ore", "copper_bars", "tin_bars",
	"bronze_bars", "iron_bars", "pig_iron", "steel_bars", "scrap_copper", "scrap_tin", "scrap_bronze", "scrap_iron", "scrap_steel"]
const GROUPS := {"grain": ["grain"], "meat": ["meat", "fresh_meat"], "wood": ["wood"],
	"metal": ["copper_ore", "tin_ore", "iron_ore", "copper_bars", "tin_bars", "bronze_bars", "iron_bars", "pig_iron",
		"steel_bars", "scrap_copper", "scrap_tin", "scrap_bronze", "scrap_iron", "scrap_steel"]}
## Keys whose numbers look like money; scan() lists any such field the census does not count.
const COINISH := ["purse", "till", "treasury", "gold", "coin", "coins", "loot", "farm_till", "land_fund", "reserved",
	"chest", "coffer", "hoard_gold", "cash", "fund", "funds", "wallet"]

# ------------------------------------------------------------------ the world flow book
## Named moves the town ledgers cannot see: {"goods": {good: {name: n}}}. "+" names are inflows to counted holders,
## "-" names outflows (book(w, good, "-band meals", 12)). Plain dictionaries in the save.
static func flows(w: Dictionary) -> Dictionary:
	if not w.has("flow"): w["flow"] = {"goods": {}}
	return w["flow"]

static func book(w: Dictionary, good: String, name: String, n: int) -> void:
	if n == 0 or w.is_empty(): return
	var g: Dictionary = flows(w)["goods"]
	if not g.has(good): g[good] = {}
	g[good][name] = int(g[good].get(name, 0)) + n

# ------------------------------------------------------------------ census
static func _add(d: Dictionary, k: String, v) -> void:
	d[k] = d.get(k, 0) + v

static func census(game) -> Dictionary:
	var w: Dictionary = game.world
	var coin := {}
	var goods := {}
	var made := {}
	var used := {}
	var spoil := {}
	for g in GOODS:
		goods[g] = {}
		made[g] = 0
		used[g] = 0
		spoil[g] = 0
	var arms := {"armoury": 0, "made": 0, "used": 0, "shop": 0}
	var outside := {}   # goods outside the counted holders (band stores), reported only
	var bands := {}   # warband id -> its purse (a leak report names bands that came or went with coin)
	var treasure := {}
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t): continue   # (a stand-in town without an economy keeps no ledger: not counted)
		arms["armoury"] += (t.get("armory_items", []) as Array).size()
		arms["shop"] += (t.get("shop", []) as Array).size()
		var e: Dictionary = t["econ"]
		_add(coin, "town treasury", float(e["treasury"]))
		_add(coin, "farm till", float(e["farm_till"]))
		_add(coin, "land fund", float(e.get("land_fund", 0.0)))
		_add(coin, "supply reserve", SupplyOrders.reserved(e))
		for b in e["biz"]:
			_add(coin, "business till", float(b["till"]))
			for row in b.get("court_stock", []):
				_add(treasure, "merchant stock", int(row.get("quantity", 0)))
		for f in e["fams"]:
			_add(coin, "family purse", float(f["purse"]))
			for row in f.get("hoard", []):
				_add(treasure, "treasure room", int(row.get("quantity", 0)))
		for g in GOODS:
			var row: Dictionary = goods[g]
			_add(row, "market", int(e["stock"].get(g, 0)))
			_add(row, "barn", int(e["barn"].get(g, 0)))
			_add(row, "households", int(e["hh"].get(g, 0)))
			_add(row, "stones", int(e.get("gh", {}).get(g, 0)))
			if g == "grain": _add(row, "granary", int(e["granary"]))
		var led: Dictionary = e.get("led", {})
		for g in GOODS:
			made[g] += int(led.get("made", {}).get(g, 0))
			used[g] += int(led.get("used", {}).get(g, 0))
			spoil[g] += int(led.get("spoil", {}).get(g, 0))
		arms["made"] += int(led.get("made", {}).get("arms", 0))
		arms["used"] += int(led.get("used", {}).get("arms", 0))
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		_add(coin, "realm treasury", float(fac.get("treasury", 0.0)))
		_add(coin, "realm loot", float(fac.get("loot", 0.0)))
		for row in fac.get("loot_hoard", []):
			_add(treasure, "carried-off hoard", int(row.get("quantity", 0)))
	for lid in w.get("lairs", {}):
		_add(coin, "lair hoard", float(w["lairs"][lid].get("gold", 0.0)))
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		var caravan := str(wb.get("kind", "")) == "caravan"
		_add(coin, "caravan purse" if caravan else "band purse", float(wb.get("gold", 0.0)))
		bands[str(wid)] = float(wb.get("gold", 0.0))
		var cg: Dictionary = wb.get("cargo", {}).get("goods", {})
		var st: Dictionary = wb.get("stores", {})
		for g in GOODS:
			_add(goods[g], "caravan cargo", int(cg.get(g, 0)))
			_add(outside, g, int(st.get(g, 0)))
	_add(coin, "army purse", float(game.gold))
	var cgoods: Dictionary = w.get("company_goods", {})
	for g in GOODS:
		_add(goods[g], "company goods", int(cgoods.get(g, 0)))
	var L: Dictionary = w.get("coin", {})
	var book_in := {}
	for g in GOODS:
		var net := 0
		for name in w.get("flow", {}).get("goods", {}).get(g, {}):
			net += int(w["flow"]["goods"][g][name])
		book_in[g] = net
	var lost := {}
	for g in GOODS:
		lost[g] = int(TownEcon.goods_lost.get(g, 0))
	return {"day": float(game.day), "coin": coin, "goods": goods, "arms": arms, "treasure": treasure,
		"cast": float(L.get("cast", 0.0)), "melted": float(L.get("melted", 0.0)), "drained": float(L.get("drained", 0.0)),
		"made": made, "used": used, "spoil": spoil, "lost": lost, "book": book_in, "outside": outside, "bands": bands,
		"book_names": (w.get("flow", {}).get("goods", {}) as Dictionary).duplicate(true)}

static func total(d: Dictionary) -> float:
	var s := 0.0
	for k in d: s += float(d[k])
	return s

## What changed from census a to census b and whether it is all booked. Returns
## {"coin": {held, booked, residual, by_holder}, "goods": {good: {...}}, "arms": {...}, "ok": bool}.
static func compare(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"ok": true, "goods": {}}
	var held := total(b["coin"]) - total(a["coin"])
	var booked := (float(b["cast"]) - float(a["cast"])) - (float(b["melted"]) - float(a["melted"])) - (float(b["drained"]) - float(a["drained"]))
	var tol := maxf(0.01, 1e-9 * absf(total(b["coin"])))
	var by := {}
	for k in b["coin"]: by[k] = float(b["coin"][k]) - float(a["coin"].get(k, 0.0))
	for k in a["coin"]:
		if not b["coin"].has(k): by[k] = -float(a["coin"][k])
	out["coin"] = {"held": held, "booked": booked, "residual": held - booked, "tol": tol, "by_holder": by,
		"cast": float(b["cast"]) - float(a["cast"]), "melted": float(b["melted"]) - float(a["melted"]),
		"drained": float(b["drained"]) - float(a["drained"]), "ok": absf(held - booked) <= tol}
	if not out["coin"]["ok"]: out["ok"] = false
	for g in GOODS:
		var hb := 0
		var ha := 0
		var gby := {}
		for k in b["goods"][g]:
			hb += int(b["goods"][g][k])
			gby[k] = int(b["goods"][g][k]) - int(a["goods"][g].get(k, 0))
		for k in a["goods"][g]: ha += int(a["goods"][g][k])
		var dm := int(b["made"][g]) - int(a["made"][g])
		var du := int(b["used"][g]) - int(a["used"][g])
		var ds := int(b["spoil"][g]) - int(a["spoil"][g])
		var dl := int(b["lost"][g]) - int(a["lost"][g])
		var dk := int(b["book"][g]) - int(a["book"][g])
		var row := {"held": hb - ha, "made": dm, "used": du, "spoil": ds, "lost": dl, "book": dk,
			"residual": (hb - ha) - (dm - du - ds - dl + dk), "by_holder": gby}
		row["ok"] = int(row["residual"]) == 0
		if not row["ok"]: out["ok"] = false
		out["goods"][g] = row
	var ar := int(b["arms"]["armoury"]) + int(b["arms"]["shop"]) - int(a["arms"]["armoury"]) - int(a["arms"]["shop"])
	var am := int(b["arms"]["made"]) - int(a["arms"]["made"])
	var au := int(b["arms"]["used"]) - int(a["arms"]["used"])
	out["arms"] = {"held": ar, "made": am, "used": au, "residual": ar - (am - au), "ok": ar == am - au,
		"armoury": int(b["arms"]["armoury"]) - int(a["arms"]["armoury"]), "shop": int(b["arms"]["shop"]) - int(a["arms"]["shop"])}
	var outside := {}
	for g in b.get("outside", {}): outside[g] = int(b["outside"][g]) - int(a.get("outside", {}).get(g, 0))
	for g in a.get("outside", {}):
		if not b.get("outside", {}).has(g): outside[g] = -int(a["outside"][g])
	out["outside"] = outside
	var came := {}
	var went := {}
	for wid in b.get("bands", {}):
		if not a.get("bands", {}).has(wid) and float(b["bands"][wid]) != 0.0: came[wid] = float(b["bands"][wid])
	for wid in a.get("bands", {}):
		if not b.get("bands", {}).has(wid) and float(a["bands"][wid]) != 0.0: went[wid] = float(a["bands"][wid])
	out["coin"]["bands_came"] = came
	out["coin"]["bands_went"] = went
	if not out["arms"]["ok"]: out["ok"] = false
	var tr := {}
	for k in b["treasure"]: tr[k] = int(b["treasure"][k]) - int(a["treasure"].get(k, 0))
	out["treasure"] = tr
	return out

## Lines for a log: one per failing identity, holders that moved, unrounded numbers.
static func lines(c: Dictionary, label: String) -> Array:
	var out: Array = []
	var co: Dictionary = c["coin"]
	out.append("%s coin %s: held %s, booked %s (cast %s, melted %s, drained %s), residual %s" % [label,
		"ok" if co["ok"] else "LEAK", String.num(co["held"], 6), String.num(co["booked"], 6), String.num(co["cast"], 6),
		String.num(co["melted"], 6), String.num(co["drained"], 6), String.num(co["residual"], 6)])
	if not co["ok"]:
		var parts := PackedStringArray()
		for k in co["by_holder"]:
			if absf(float(co["by_holder"][k])) > 0.0: parts.append("%s %s" % [k, String.num(co["by_holder"][k], 6)])
		out.append("    coin holders: " + ", ".join(parts))
		if not (co.get("bands_came", {}) as Dictionary).is_empty(): out.append("    bands that came with coin: " + JSON.stringify(co["bands_came"]))
		if not (co.get("bands_went", {}) as Dictionary).is_empty(): out.append("    bands that went with coin: " + JSON.stringify(co["bands_went"]))
	for g in GOODS:
		var r: Dictionary = c["goods"][g]
		if r["ok"] and int(r["held"]) == 0 and int(r["made"]) == 0 and int(r["used"]) == 0: continue
		if r["ok"]: continue
		var parts := PackedStringArray()
		for k in r["by_holder"]:
			if int(r["by_holder"][k]) != 0: parts.append("%s %+d" % [k, int(r["by_holder"][k])])
		out.append("%s %s LEAK: held %+d vs made %d - used %d - spoil %d - lost %d %+d booked = residual %+d  [%s]" % [label, g,
			int(r["held"]), int(r["made"]), int(r["used"]), int(r["spoil"]), int(r["lost"]), int(r["book"]), int(r["residual"]), ", ".join(parts)])
	var a: Dictionary = c["arms"]
	if not a["ok"]:
		out.append("%s arms LEAK: held %+d (armoury %+d, stalls %+d) vs made %d - used %d, residual %+d" % [label, a["held"], a["armoury"], a["shop"], a["made"], a["used"], a["residual"]])
	var od: Dictionary = c.get("outside", {})
	var parts2 := PackedStringArray()
	for g in od:
		if int(od[g]) != 0: parts2.append("%s %+d" % [g, int(od[g])])
	if not parts2.is_empty(): out.append("%s band stores (the army's mess, not balanced): %s" % [label, ", ".join(parts2)])
	return out

## Money-looking numbers in the world tree the census does not count (a holder it is missing). Diagnostic only.
static func scan(game) -> Dictionary:
	var found := {}
	_scan(game.world, "", found, 0)
	return found

static func _counted(path: String) -> bool:
	for p in ["/towns/*/econ/treasury", "/towns/*/econ/farm_till", "/towns/*/econ/land_fund", "/towns/*/econ/biz[#]/till",
			"/towns/*/econ/fams[#]/purse", "/towns/*/econ/supply_orders[#]/reserved", "/factions/*/treasury", "/factions/*/loot",
			"/lairs/*/gold", "/warbands/*/gold", "/coin/"]:
		if path == p or path.begins_with(p) or path.match(p + "*"): return true   # ("*" stands for a town or realm id)
	return false

static func _scan(v, path: String, found: Dictionary, depth: int) -> void:
	if depth > 9: return
	if v is Dictionary:
		for k in v:
			var key := str(k)
			var sub := "%s/%s" % [path, "*" if _has_digit(key) else key]
			var x = v[k]
			if (x is float or x is int) and COINISH.has(key) and float(x) != 0.0 and not _counted(sub):
				if not found.has(sub): found[sub] = [0, 0.0]
				found[sub][0] += 1
				found[sub][1] += float(x)
			elif x is Dictionary or x is Array:
				_scan(x, sub, found, depth + 1)
	elif v is Array:
		for x in v:
			if x is Dictionary or x is Array: _scan(x, path + "[#]", found, depth + 1)

static func _has_digit(s: String) -> bool:
	for c in s:
		if c >= "0" and c <= "9": return true
	return false

## JSON numbers back to ints (the save keeps the flow book).
static func after_load(game) -> void:
	var g: Dictionary = game.world.get("flow", {}).get("goods", {})
	for good in g:
		for name in g[good]: g[good][name] = int(g[good][name])
