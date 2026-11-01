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
## Arms (finished weapons and armour: a town's armoury and stalls, and caravan cargo on the road, as the conservation
## test counts them): change in held = made - used (town ledgers, good "arms") - lost (TownEcon.goods_lost["arms"]:
## cargo destroyed with its wagons) + booked (flow book good "arms": cargo taken by the company, outlaws or a band).
## Moves between the armoury, the stalls and the wagons are inside the holdings.
## Treasure pieces (house treasure rooms, merchants' court stock, realms' carried-off hoards): balanced since r5.
##   change in held = commissioned (CourtEvents.hold "treasure", booked in the treasure book below)
##   (sold to a merchant, carried off in a sack: moves between counted holders)
##
## r5 (QC 122fabf8): every owned holder is in the gate.
## Items, by identity: every Item the save holds (the company's men and stash, every force's men alive or dead,
## prisoners and captives, caravan cargo, armouries, stalls, recruits, lair stock, anything else in the world tree).
## Moving between holders is a transfer. Between two censuses every Item that is gone must have been booked gone by
## its uid at the line that destroyed it (lose_item: melted to scrap, left on the field...), every new Item must come
## from Item.make in that window, and nothing booked gone may still be held. The arms identity above stays the towns'
## and wagons' operating stock (the town ledgers book a piece put on a soldier as used); the item identity covers kit.
## Rations (band stores {grain, meat, fruit, beer, wine} and the company's provisions {meal lots, beer, wine}), rows
## food (every meal unit), beer, wine: change in held = what the ration book names (bought in a town, seeded,
## eaten, drunk, spoiled, left on the field, fed to horses or dragons, gone with a removed band ...). A beaten
## force's stores taken by the winner or by the company are a transfer.

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

# ------------------------------------------------------------------ r5: items, rations, treasure books
## In-process books (like TownEcon.goods_lost: the audit compares two censuses of one running world).
## items_gone: [uid, why] for every Item destroyed while an audit is running (census() starts it); gone_by: why -> n.
static var tracking := false
static var items_gone: Array = []
static var gone_by: Dictionary = {}
## rations: row ("food" | "beer" | "wine") -> {name: n}, "+" in, "-" out. treasure: name -> pieces.
static var rations: Dictionary = {}
static var treasure_book: Dictionary = {}

## The Item stops existing here (why: "-melted into scrap stock" ...). Call it on the line that drops the last reference.
static func lose_item(it, why: String) -> void:
	if not (it is Item): return
	gone_by[why] = int(gone_by.get(why, 0)) + 1
	if tracking: items_gone.append([int(it.uid), why])

static func lose_items(items, why: String) -> void:
	for it in items: lose_item(it, why)

## A ration good (grain, meat, fruit, a meal lot, beer, wine) n units in (+) or out (-) under a name.
static func ration(good: String, name: String, n: int) -> void:
	if n == 0: return
	var row := "food" if good in ["grain", "meat", "fruit", "meal", "fresh_meat"] else good
	if not rations.has(row): rations[row] = {}
	rations[row][name] = int(rations[row].get(name, 0)) + n

## A force's stores {good: n} n units out under a name (what was left on the field, gone with the band).
static func ration_out(st: Dictionary, name: String) -> void:
	for g in st:
		if g in Supplies.FOOD or g in Supplies.DRINK: ration(g, name, -int(st[g]))

## A force leaves the map: its stores go with it (booked), its men's kit is checked item by item.
static func band_gone(wb: Dictionary, why: String) -> void:
	if wb.is_empty(): return
	ration_out(wb.get("stores", {}), why)

static func treasure(name: String, n: int) -> void:
	if n != 0: treasure_book[name] = int(treasure_book.get(name, 0)) + n

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
	var arms := {"armoury": 0, "made": 0, "used": 0, "shop": 0, "cargo": 0}
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
		arms["cargo"] += (wb.get("cargo", {}).get("items", []) as Array).size()
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
	arms["lost"] = int(TownEcon.goods_lost.get("arms", 0))
	arms["book"] = _arms_book(w)
	tracking = true
	# r5 rations: band stores and the company's provisions, by row.
	var held_r := {}   # row -> {holder: n}
	for wid in w.get("warbands", {}):
		var st: Dictionary = w["warbands"][wid].get("stores", {})
		for g in st:
			if g in Supplies.FOOD or g in Supplies.DRINK:
				var row := "food" if g in Supplies.FOOD else str(g)
				if not held_r.has(row): held_r[row] = {}
				_add(held_r[row], "band stores", int(st[g]))
	if game.provisions is Dictionary:
		for kind in game.provisions:
			var row := "food" if str(kind) == "meal" else str(kind)
			if not held_r.has(row): held_r[row] = {}
			for lot in game.provisions[kind]:
				_add(held_r[row], "company provisions", int(lot[0]))
	return {"day": float(game.day), "coin": coin, "goods": goods, "arms": arms, "treasure": treasure,
		"cast": float(L.get("cast", 0.0)), "melted": float(L.get("melted", 0.0)), "drained": float(L.get("drained", 0.0)),
		"made": made, "used": used, "spoil": spoil, "lost": lost, "book": book_in, "outside": outside, "bands": bands,
		"book_names": (w.get("flow", {}).get("goods", {}) as Dictionary).duplicate(true),
		"items": items(game), "rations": held_r, "ration_book": rations.duplicate(true),
		"treasure_book": treasure_book.duplicate(), "items_booked": items_gone.size()}

## Every Item the save holds, by uid: {"held": {uid: [holder, tid]}, "by": {holder: n}, "next": the next uid
## Item.make gives, "dupes": [uid] two distinct Items carry}. Walks the company, the stash and the whole world tree
## (an Item reachable only from something the save does not write is not held).
static func items(game) -> Dictionary:
	var out := {"held": {}, "by": {}, "next": Item._next_uid, "dupes": []}
	var seen := {}
	_walk(game.company, "company kit", out, seen, 0)
	_walk(game.stash, "company stash", out, seen, 0)
	var w: Dictionary = game.world
	for k in w:
		var key := str(k)
		match key:
			"towns":
				for tid in w["towns"]:
					var t = w["towns"][tid]
					if not (t is Dictionary): continue
					for tk in t:
						var lab: String = {"armory_items": "town armoury", "shop": "town stalls", "recruits": "recruits' own kit"}.get(str(tk), "town " + str(tk))
						_walk(t[tk], lab, out, seen, 0)
			"warbands":
				for wid in w["warbands"]:
					var wb = w["warbands"][wid]
					if not (wb is Dictionary): continue
					var kind := str(wb.get("kind", "band"))
					for bk in wb:
						var lab: String = {"units": kind + " men's kit", "cargo": "caravan cargo"}.get(str(bk), kind + " " + str(bk))
						_walk(wb[bk], lab, out, seen, 0)
			"lairs":
				for lid in w["lairs"]:
					_walk(w["lairs"][lid], "lair stock", out, seen, 0)
			"prisoners":
				_walk(w[k], "prisoners' kit", out, seen, 0)
			"captives":
				_walk(w[k], "captives' kit", out, seen, 0)
			_:
				_walk(w[k], "world " + key, out, seen, 0)
	return out

static func _walk(v, label: String, out: Dictionary, seen: Dictionary, depth: int) -> void:
	if depth > 40: return
	match typeof(v):
		TYPE_OBJECT:
			if v is Item:
				var id: int = v.get_instance_id()
				if seen.has(id): return
				seen[id] = true
				var held: Dictionary = out["held"]
				if held.has(v.uid): (out["dupes"] as Array).append(v.uid)
				held[v.uid] = [label, v.tid]
				_add(out["by"], label, 1)
			elif v is Unit:
				var id: int = v.get_instance_id()
				if seen.has(id): return
				seen[id] = true
				for s in v.equip: _walk(v.equip[s], label, out, seen, depth + 1)
				if v.horse != null: _walk(v.horse, label, out, seen, depth + 1)
		TYPE_DICTIONARY:
			for k in v:
				var x = v[k]
				var t := typeof(x)
				if t == TYPE_OBJECT or t == TYPE_DICTIONARY or t == TYPE_ARRAY: _walk(x, label, out, seen, depth + 1)
		TYPE_ARRAY:
			var a: Array = v
			if a.is_typed() and a.get_typed_builtin() != TYPE_OBJECT and a.get_typed_builtin() != TYPE_DICTIONARY and a.get_typed_builtin() != TYPE_ARRAY: return
			for x in a:
				var t := typeof(x)
				if t == TYPE_OBJECT or t == TYPE_DICTIONARY or t == TYPE_ARRAY: _walk(x, label, out, seen, depth + 1)

static func _arms_book(w: Dictionary) -> int:
	var net := 0
	var a: Dictionary = w.get("flow", {}).get("goods", {}).get("arms", {})
	for name in a: net += int(a[name])
	return net

## The coin and arms totals only, for a check after every work job (the test's job trace). Cheap: no goods.
## {coin, booked (cast - melted - drained), arms, arms_booked (made - used - lost + book)}.
static func quick(game) -> Dictionary:
	var w: Dictionary = game.world
	var coin := float(game.gold)
	var held := 0
	var net := 0
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		coin += float(e["treasury"]) + float(e["farm_till"]) + float(e.get("land_fund", 0.0)) + SupplyOrders.reserved(e)
		for b in e["biz"]: coin += float(b["till"])
		for f in e["fams"]: coin += float(f["purse"])
		held += (t.get("armory_items", []) as Array).size() + (t.get("shop", []) as Array).size()
		var led: Dictionary = e.get("led", {})
		net += int(led.get("made", {}).get("arms", 0)) - int(led.get("used", {}).get("arms", 0))
	for fid in w.get("factions", {}):
		coin += float(w["factions"][fid].get("treasury", 0.0)) + float(w["factions"][fid].get("loot", 0.0))
	for lid in w.get("lairs", {}): coin += float(w["lairs"][lid].get("gold", 0.0))
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		coin += float(wb.get("gold", 0.0))
		held += (wb.get("cargo", {}).get("items", []) as Array).size()
	var L: Dictionary = w.get("coin", {})
	return {"coin": coin, "booked": float(L.get("cast", 0.0)) - float(L.get("melted", 0.0)) - float(L.get("drained", 0.0)),
		"arms": held, "arms_booked": net - int(TownEcon.goods_lost.get("arms", 0)) + _arms_book(w)}

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
	var arm_d := {}
	for k in ["armoury", "shop", "cargo", "made", "used", "lost", "book"]:
		arm_d[k] = int(b["arms"].get(k, 0)) - int(a["arms"].get(k, 0))
	var ar := int(arm_d["armoury"]) + int(arm_d["shop"]) + int(arm_d["cargo"])
	var ab := int(arm_d["made"]) - int(arm_d["used"]) - int(arm_d["lost"]) + int(arm_d["book"])
	out["arms"] = {"held": ar, "made": arm_d["made"], "used": arm_d["used"], "lost": arm_d["lost"], "book": arm_d["book"],
		"residual": ar - ab, "ok": ar == ab, "armoury": arm_d["armoury"], "shop": arm_d["shop"], "cargo": arm_d["cargo"]}
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
	for k in a["treasure"]:
		if not b["treasure"].has(k): tr[k] = -int(a["treasure"][k])
	out["treasure"] = tr
	# r5 treasure: balanced against the treasure book.
	var tb_d := _book_delta(a.get("treasure_book", {}), b.get("treasure_book", {}))
	var t_held := int(total(b["treasure"]) - total(a["treasure"]))
	var t_book := int(total(tb_d))
	out["treasure_gate"] = {"held": t_held, "book": t_book, "names": tb_d, "residual": t_held - t_book, "ok": t_held == t_book}
	if not out["treasure_gate"]["ok"]: out["ok"] = false
	# r5 rations.
	out["rations"] = {}
	var ra: Dictionary = a.get("rations", {})
	var rb: Dictionary = b.get("rations", {})
	var rows := {"food": true, "beer": true, "wine": true}
	for row in ra: rows[row] = true
	for row in rb: rows[row] = true
	for row in rows:
		var hb_r: Dictionary = rb.get(row, {})
		var ha_r: Dictionary = ra.get(row, {})
		var by_r := {}
		for k in hb_r: by_r[k] = int(hb_r[k]) - int(ha_r.get(k, 0))
		for k in ha_r:
			if not hb_r.has(k): by_r[k] = -int(ha_r[k])
		var names := _book_delta(a.get("ration_book", {}).get(row, {}), b.get("ration_book", {}).get(row, {}))
		var h_r := int(total(hb_r) - total(ha_r))
		var k_r := int(total(names))
		out["rations"][row] = {"held": h_r, "book": k_r, "residual": h_r - k_r, "by_holder": by_r, "names": names, "ok": h_r == k_r}
		if h_r != k_r: out["ok"] = false
	# r5 items, by identity.
	out["items"] = compare_items(a.get("items", {}), b.get("items", {}), int(a.get("items_booked", 0)), int(b.get("items_booked", 0)))
	if not out["items"]["ok"]: out["ok"] = false
	return out

static func _book_delta(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := {}
	for k in b:
		var n := int(b[k]) - int(a.get(k, 0))
		if n != 0: d[k] = n
	for k in a:
		if not b.has(k) and int(a[k]) != 0: d[k] = -int(a[k])
	return d

## Item identity between two item censuses; booked = items_gone[from_n .. to_n). Returns {ok, held (net), made,
## booked, gone_unbooked: {holder: n}, appeared: {holder: n}, booked_but_held: n, dupes: n, samples: [text]}.
static func compare_items(a: Dictionary, b: Dictionary, from_n: int, to_n: int) -> Dictionary:
	var ha: Dictionary = a.get("held", {})
	var hb: Dictionary = b.get("held", {})
	var lo := int(a.get("next", 0))
	var hi := int(b.get("next", 0))
	var booked := {}
	var why_n := {}
	for i in range(from_n, mini(to_n, items_gone.size())):
		var r: Array = items_gone[i]
		booked[int(r[0])] = str(r[1])
		why_n[str(r[1])] = int(why_n.get(str(r[1]), 0)) + 1
	var unbooked := {}
	var samples: Array = []
	for uid in ha:
		if hb.has(uid) or booked.has(int(uid)): continue
		var key := str(ha[uid][0])
		unbooked[key] = int(unbooked.get(key, 0)) + 1
		if samples.size() < 12: samples.append("gone unbooked: #%d %s (last held: %s)" % [int(uid), str(ha[uid][1]), key])
	for uid in range(lo, hi):   # made in this window and gone again: booked too
		if hb.has(uid) or booked.has(uid) or ha.has(uid): continue
		unbooked["made and gone in the window"] = int(unbooked.get("made and gone in the window", 0)) + 1
		if samples.size() < 12: samples.append("made and gone unbooked: #%d" % uid)
	var appeared := {}
	for uid in hb:
		if ha.has(uid) or (int(uid) >= lo and int(uid) < hi): continue
		var key := str(hb[uid][0])
		appeared[key] = int(appeared.get(key, 0)) + 1
		if samples.size() < 12: samples.append("appeared without Item.make: #%d %s (in %s)" % [int(uid), str(hb[uid][1]), key])
	var still := 0
	for uid in booked:
		if hb.has(uid):
			still += 1
			if samples.size() < 12: samples.append("booked gone (%s) but still held: #%d in %s" % [booked[uid], uid, str(hb[uid][0])])
	var dupes := (b.get("dupes", []) as Array).size()
	if dupes > 0 and samples.size() < 12: samples.append("two Items share uid %s" % str(b["dupes"].slice(0, 5)))
	var by := {}
	for k in b.get("by", {}): by[k] = int(b["by"][k]) - int(a.get("by", {}).get(k, 0))
	for k in a.get("by", {}):
		if not b.get("by", {}).has(k): by[k] = -int(a["by"][k])
	var ok := unbooked.is_empty() and appeared.is_empty() and still == 0 and dupes == 0
	return {"ok": ok, "held": hb.size() - ha.size(), "made": hi - lo, "booked": booked.size(), "booked_by": why_n,
		"gone_unbooked": unbooked, "appeared": appeared, "booked_but_held": still, "dupes": dupes, "by_holder": by,
		"samples": samples}

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
		out.append("%s arms LEAK: held %+d (armoury %+d, stalls %+d, caravan cargo %+d) vs made %d - used %d - lost %d %+d booked, residual %+d" % [
			label, a["held"], a["armoury"], a["shop"], a["cargo"], a["made"], a["used"], a["lost"], a["book"], a["residual"]])
	var od: Dictionary = c.get("outside", {})
	var parts2 := PackedStringArray()
	for g in od:
		if int(od[g]) != 0: parts2.append("%s %+d" % [g, int(od[g])])
	if not parts2.is_empty(): out.append("%s band stores (also in the rations identity below): %s" % [label, ", ".join(parts2)])
	for row in c.get("rations", {}):
		var r: Dictionary = c["rations"][row]
		if r["ok"]: continue
		out.append("%s rations %s LEAK: held %+d (%s) vs booked %+d %s, residual %+d" % [label, row, int(r["held"]),
			JSON.stringify(r["by_holder"]), int(r["book"]), JSON.stringify(r["names"]), int(r["residual"])])
	var tg: Dictionary = c.get("treasure_gate", {})
	if not tg.is_empty() and not tg["ok"]:
		out.append("%s treasure LEAK: held %+d %s vs booked %+d %s, residual %+d" % [label, int(tg["held"]),
			JSON.stringify(c["treasure"]), int(tg["book"]), JSON.stringify(tg["names"]), int(tg["residual"])])
	var ic: Dictionary = c.get("items", {})
	if not ic.is_empty() and not ic["ok"]:
		out.append("%s items LEAK: net %+d, made %d, booked gone %d %s; gone unbooked %s; appeared %s; booked but held %d; shared uids %d" % [label,
			int(ic["held"]), int(ic["made"]), int(ic["booked"]), JSON.stringify(ic["booked_by"]), JSON.stringify(ic["gone_unbooked"]),
			JSON.stringify(ic["appeared"]), int(ic["booked_but_held"]), int(ic["dupes"])])
		for s in ic["samples"]: out.append("    " + str(s))
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
