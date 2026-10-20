class_name HerdsViews
extends RefCounted
## Grazing tile assignment, home pens, and UI/land-map/ledger read helpers split from Herds
## (game/campaign/herds.gd) to keep each file focused and under the size threshold.
## Structure only; all Herds.* entry points delegate here with identical behavior.

const GRAZE := Herds.GRAZE
const AGES := Herds.AGES

# ================================================================== tile assignment (Plots._sync_grazing)
## Pasture plots shared among the grazing herds: a family's OWN pasture plots go to its herds; the common plots
## (held by the town) are shared out among the rest by the acres their herds need, each family at most the data's
## common cap (largest remainder). At world gen the families whose herds need more than the cap own the plots
## their herds need (owned pasture, B2). P.ten = the family whose herd grazes it.
static func assign_tiles(e: Dictionary, P: Dictionary) -> void:
	var past := []
	for i in Plots.count(P):
		if int(P["use"][i]) == Plots.PASTURE:
			past.append(i)
	var hd := Herds.H(e)
	var tiles := {}
	for hid in hd["h"]:
		hd["h"][hid]["pl"] = []
		hd["h"][hid]["opl"] = []
		hd["h"][hid]["cs"] = 0.0
	_pens(e, P)
	var fams: Array = e["fams"]
	# the acres each grazing family's herds need
	var need := {}   # fid -> acres
	var by_f := {}   # fid -> [herds]
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		var k := String(h["k"])
		if not GRAZE.has(k) or Herds.head(h) <= 0:
			continue
		var fid := Herds.grazer(e, h)
		if fid < 0:
			continue
		need[fid] = float(need.get(fid, 0.0)) + Herds.ge(h) * float(Herds.kind(k)["feed"])
		if not by_f.has(fid):
			by_f[fid] = []
		by_f[fid].append(h)
	var cap := float(Herds.A()["common_cap"])
	if not P.get("past_own", false):
		P["past_own"] = true
		if int(e.get("day", 0)) <= 0:   # world gen only: the big herds' families own their pasture
			var fids: Array = need.keys()
			fids.sort()
			var at := 0
			for fid in fids:
				if int(fid) == 0 or float(need[fid]) <= cap:
					continue
				var nt := int(round(float(need[fid]) / float(Plots.ACRES)))
				for j in nt:
					if at >= past.size():
						break
					P["own"][past[at]] = int(fid)
					at += 1
	for i in past:
		var o := int(P["own"][i])
		if o > 0 and (o >= fams.size() or fams[o].get("gone", false)):
			P["own"][i] = Plots.TOWN
	var own_ac := {}
	var common := []
	for i in past:
		P["ten"][i] = -1
		var o2 := int(P["own"][i])
		if o2 > 0:
			if by_f.has(o2):
				P["ten"][i] = o2
				own_ac[o2] = float(own_ac.get(o2, 0.0)) + float(P["ac"][i])
				_give_tile(by_f[o2], i, tiles, true)
		else:
			common.append(i)
	# common plots: each family's stint (its right to graze, in acres: what its herds needed when it was first
	# counted, at most the cap; the town's own herds what they need), shared out by largest remainder
	if not hd.has("stint"):
		hd["stint"] = {}
	var stint: Dictionary = hd["stint"]
	for sk in stint.keys():
		var sf0 := int(sk)
		if sf0 >= fams.size() or fams[sf0].get("gone", false):
			stint.erase(sk)
	var rows := []
	var tot := 0.0
	var fids2: Array = need.keys()
	fids2.sort()
	var stot := 0.0
	for fid in fids2:
		var left := float(need[fid]) - float(own_ac.get(fid, 0.0))
		if int(fid) != 0:
			if not stint.has(str(int(fid))):
				stint[str(int(fid))] = snappedf(clampf(left, 0.0, cap), 0.01)
			left = minf(left, cap)
		var stv := float(stint.get(str(int(fid)), maxf(0.0, left)))
		if left > 0.0:
			rows.append([int(fid), left, stv])
			tot += left
			stot += stv
	hd["cpool"] = common
	hd.erase("_pg"); hd.erase("_pa")
	var cac := 0.0
	for i in common:
		cac += float(P["ac"][i])
	if tot > cac and stot > 0.0:   # more wanted than the common grows: each family by its stint
		for r0 in rows:
			r0[1] = float(r0[2]) * cac / stot
		tot = cac
	# each family's share of the common's grass (its capped need over the common, all of it when there is room),
	# split among its herds by their need
	for r in rows:
		var sf := float(r[1]) / maxf(tot, maxf(1.0, cac))
		var fneed := 0.0
		for h2 in by_f[int(r[0])]:
			fneed += Herds.ge(h2) * float(Herds.kind(String(h2["k"]))["feed"])
		for h3 in by_f[int(r[0])]:
			h3["cs"] = snappedf(sf * Herds.ge(h3) * float(Herds.kind(String(h3["k"]))["feed"]) / maxf(0.0001, fneed), 0.000001)
	if common.is_empty() or tot <= 0.0:
		_tiles_done(hd, tiles)
		return
	var n_t := float(common.size()) * minf(1.0, tot / maxf(1.0, cac))
	var share := []
	var given := 0
	for r in rows:
		var q := n_t * float(r[1]) / tot
		share.append([r[0], int(floor(q)), q - floor(q)])
		given += int(floor(q))
	var order := range(share.size())
	order.sort_custom(func(a, b): return float(share[a][2]) > float(share[b][2]) if float(share[a][2]) != float(share[b][2]) else int(share[a][0]) < int(share[b][0]))
	for k in mini(int(round(n_t)) - given, order.size()):
		share[order[k]][1] = int(share[order[k]][1]) + 1
	var at2 := 0
	for s in share:
		for j in int(s[1]):
			if at2 < common.size():
				var i2: int = common[at2]
				P["ten"][i2] = int(s[0])
				_give_tile(by_f[int(s[0])], i2, tiles)
				at2 += 1
	_tiles_done(hd, tiles)

## A plot to the family's herd that has the least grass for its need.
static func _give_tile(hl: Array, i: int, tiles: Dictionary, own: bool = false) -> void:
	var best: Dictionary = {}
	var bv := INF
	for h in hl:
		var have := float((h["pl"] as Array).size()) * float(Plots.ACRES)
		var v := have / maxf(0.01, Herds.ge(h) * float(Herds.kind(String(h["k"]))["feed"]))
		if v < bv:
			bv = v; best = h
	if not best.is_empty():
		(best["pl"] as Array).append(i)
		if own:
			(best["opl"] as Array).append(i)
		tiles[str(i)] = int(best["id"])

static func _tiles_done(hd: Dictionary, tiles: Dictionary) -> void:
	hd["tiles"] = tiles

## Pens: a family's small stock lives at its first home plot (hd.pens {str(plot): kind}, the herds' pl).
static func _pens(e: Dictionary, P: Dictionary) -> void:
	var hd := Herds.H(e)
	var first := {}
	for i in Plots.count(P):
		if int(P["use"][i]) != Plots.HOME:
			continue
		var fid := int(P["ten"][i]) if int(P["ten"][i]) > 0 else int(P["own"][i])
		if fid > 0 and not first.has(fid):
			first[fid] = i
	var pens := {}
	for hid in hd["h"]:
		var h: Dictionary = hd["h"][hid]
		if GRAZE.has(String(h["k"])) or String(h["k"]) == "oxen" or String(h["ow"]) != "f" or Herds.head(h) <= 0:
			continue
		var p := int(first.get(int(h["oi"]), -1))
		if p >= 0:
			h["pl"] = [p]
			if not pens.has(str(p)):
				pens[str(p)] = String(h["k"])
	hd["pens"] = pens

## Acres of pasture the town's grazing herds need at a full season's grass (head x the kind's feed; land layout).
static func graze_acres(e: Dictionary) -> float:
	var a := 0.0
	for hid in Herds.herds(e):
		var h: Dictionary = Herds.herds(e)[hid]
		if GRAZE.has(String(h["k"])):
			a += float(Herds.head(h)) * float(Herds.kind(String(h["k"]))["feed"])
	return a

## Records whose pens are a family's home plot (hens, rats, hives; pigs kept at home have pasture here too).
static func pen_herds(e: Dictionary, fid: int) -> Array:
	var out := []
	for h in Herds.of_family(e, fid):
		if not GRAZE.has(String(h["k"])) and String(h["k"]) != "oxen":
			out.append(h)
	return out

# ================================================================== reads (records screens, land map, tests)
## Head by kind in the town (every record, every owner; drovers' herds waiting to be sold included).
static func town_heads(e: Dictionary) -> Dictionary:
	var out := {}
	if not e.has("hd"):
		return e.get("herd", {})
	var hd: Dictionary = e["hd"]
	var key := "%d|%d" % [int(hd.get("ver", 0)), (hd["h"] as Dictionary).size()]
	if String(hd.get("_thk", "")) == key:
		return hd["_th"]
	hd["_thk"] = key
	hd["_th"] = out
	var records: Dictionary = hd["h"]
	for hid in records:
		var h: Dictionary = records[hid]
		var n := int(h["y"]) + int(h["g"]) + int(h["o"])
		if n > 0:
			var kind := String(h["k"])
			out[kind] = int(out.get(kind, 0)) + n
	return out

## {kind: [young, grown, old]} for the town.
static func town_ages(e: Dictionary) -> Dictionary:
	var out := {}
	if not e.has("hd"):
		return out
	for hid in Herds.herds(e):
		var h: Dictionary = Herds.herds(e)[hid]
		var k := String(h["k"])
		if not out.has(k):
			out[k] = [0, 0, 0]
		for i in 3:
			out[k][i] = int(out[k][i]) + int(h[AGES[i]])
	return out

## Days of winter fodder the town's herds have in reach (their own hay + the barns' and market's fodder) at the
## herds' last week's feed, or -1 when the town keeps no grazing beasts.
static func fodder_days(e: Dictionary) -> float:
	if not e.has("hd") or float(e["hd"].get("fneed", 0.0)) <= 0.0:
		return -1.0
	return float(e["hd"].get("fodd", 0.0))

## The herd's one-line text: "40 sheep (8 young, 28 grown, 4 old) of the Marsh family".
static func line(e: Dictionary, h: Dictionary) -> String:
	return "%s (%d young, %d grown, %d old) of %s" % [Herds.n_word(e, Herds.head(h), String(h["k"])), int(h["y"]), int(h["g"]), int(h["o"]), Herds.owner_text(e, h)]

## Herds on a plot: pasture by the tile map, a home plot's pens (its family's small stock).
static func on_plot(e: Dictionary, P: Dictionary, i: int) -> Array:
	var out := []
	if not e.has("hd"):
		return out
	var u := int(P["use"][i])
	if u == Plots.PASTURE:
		var hid := int(Herds.H(e)["tiles"].get(str(i), -1))
		if hid >= 0 and Herds.herds(e).has(str(hid)):
			out.append(Herds.herds(e)[str(hid)])
	elif u == Plots.HOME and Herds.H(e).get("pens", {}).has(str(i)):
		var fid := int(P["ten"][i]) if int(P["ten"][i]) > 0 else int(P["own"][i])
		out = pen_herds(e, fid)
	return out

## The kind drawn on a plot (land map sprites): the herd grazing a pasture, a home's small stock ("" = none).
static func plot_kind(e: Dictionary, P: Dictionary, i: int) -> String:
	if not e.has("hd"):
		return ""
	var hd: Dictionary = e["hd"]
	var u := int(P["use"][i])
	if u == Plots.PASTURE:
		var hid := str(int(hd["tiles"].get(str(i), -1)))
		return String(hd["h"][hid]["k"]) if hd["h"].has(hid) else ""
	if u == Plots.HOME:
		return String(hd.get("pens", {}).get(str(i), ""))
	return ""

## The plot card's herd lines (Plots.card): who owns the pasture (the common's fee), each herd on it with its
## owner and herders, what the plot carries this season and its condition; a home's pens. {lines, taps}
static func card_lines(game, town: Dictionary, P: Dictionary, i: int) -> Dictionary:
	var e: Dictionary = town["econ"]
	var lines := []
	var taps := []
	var si := Calendar.season_index(float(game.day))
	var u := int(P["use"][i])
	if u == Plots.PASTURE:
		var own := int(P["own"][i])
		if own > 0:
			lines.append("Pasture owned by %s." % Plots.owner_text(e, own))
			taps.append({"text": "Owners: %s" % Plots.owner_text(e, own), "fid": own})
		else:
			lines.append("The town's common pasture: %s coins an acre a week to the treasury for grazing it." % num(float(Herds.A()["fee_acre_week"]) * Barge.pl(e)))
		lines.append("Grass this %s: %s bales a day (condition %d%%%s)." % [Calendar.SEASONS[si], num(Herds.grass_day(e, P, i, si)),
			int(round(Herds.cond(e, i) * 100.0)), ", overgrazed" if Herds.cond(e, i) < 0.95 else ""])
	for h in on_plot(e, P, i):
		var k := String(h["k"])
		lines.append("%s." % _cap(line(e, h)))
		if int(h["hun"]) > 0:
			lines.append("Short of feed: %d days in the last weeks." % int(h["hun"]))
		var hs := Herds.herders(e, h)
		if not hs.is_empty():
			var nm := []
			for p in hs.slice(0, 4):
				nm.append(String(p["name"]))
			lines.append("Herded by %s%s." % [", ".join(PackedStringArray(nm)), (" and %d more" % (hs.size() - 4)) if hs.size() > 4 else ""])
			taps.append({"text": "Herder: %s" % hs[0]["name"], "fid": int(hs[0]["fid"])})
		var gf := Herds.grazer(e, h)
		if gf > 0:
			taps.append({"text": "Herd owners: %s" % Plots.owner_text(e, gf), "fid": gf})
		if u == Plots.PASTURE:
			lines.append("This plot carries %s this season (the herd has %d plots of pasture, %s bales of hay)." % [Herds.n_word(e, Herds.carry_head(e, P, i, k, si), k),
				(h["pl"] as Array).size(), num(float(h["fod"]))])
	if u == Plots.PASTURE and on_plot(e, P, i).is_empty():
		lines.append("No herd grazes it this week.")
	return {"lines": lines, "taps": taps}

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

static func num(v: float) -> String:
	return str(int(round(v))) if absf(v) >= 10.0 else ("%.1f" % v)

## The town's herd ledger as a whole: {born, bought, sold, slaughtered, stolen, looted, died {cause: n}} all-time
## or this year ("yr") or last ("ly"), summed over kinds; by_kind gives {what: {kind: n}}.
static func book(e: Dictionary, which: String = "tot") -> Dictionary:
	var out := {"died": {}}
	if not e.has("hd"):
		return out
	var b: Dictionary = Herds.H(e).get(which, {})
	for key in b:
		var n := 0
		for k in b[key]:
			n += int(b[key][k])
		if String(key).begins_with("died:"):
			out["died"][String(key).substr(5)] = n
		else:
			out[key] = n
	return out

## Sum of every record's head by its ledger: h0 + born + bought - sold - slaughtered - stolen - died (tests).
static func ledger_head(h: Dictionary) -> int:
	var L: Dictionary = h["led"]
	var d := 0
	for c in L["d"]:
		d += int(L["d"][c])
	return int(h["h0"]) + int(L["b"]) + int(L["in"]) - int(L["out"]) - int(L["sl"]) - int(L["st"]) - d

## The page lines of a business's chain: [[way, who, what, n]] this season (and last).
static func chain_rows(b: Dictionary) -> Array:
	var out := []
	for src in ["chain", "chain_last"]:
		var c: Dictionary = b.get(src, {})
		for way in ["from", "to"]:
			var d: Dictionary = c.get(way, {})
			var keys: Array = d.keys()
			keys.sort_custom(func(x, y): return int(d[x]) > int(d[y]))
			for key in keys:
				var parts := String(key).split("|")
				out.append([way, parts[0], parts[1] if parts.size() > 1 else "", int(d[key]), src == "chain"])
	return out
