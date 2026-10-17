extends RefCounted
## Frozen canonical v0.042 Goods/herds-table builders for v0.043 comparisons.
## Goods body is unchanged except its table call uses this frozen builder and
## category-detail callback remains the shared live helper. Data/detail/kit helpers
## stay shared except the frozen herd-count backend below. No class_name, simulation edits, save writes, or timing assertions.

static func _number(value: Variant) -> String:
	return RecKit.num(float(value)) if value != null else "-"

static func goods(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
	var categories := []
	var market_units := 0
	for cat in RecTown.CATS:
		var key := String(cat[0])
		var title := String(cat[1])
		var goods_in := RecTown._goods_in(key)
		var stock := 0; var demand := 0.0
		for tid in tids:
			var totals := RecData.market_totals(RecWorld._e(tid), goods_in)
			stock += int(totals[0]); demand += float(totals[1])
		market_units += stock
		categories.append({"values": [title, {"text": str(stock), "color": UiTheme.BLUE},
			{"text": RecKit.num(stock / demand) if demand > 0.0 else "-", "color": UiTheme.COPPER}],
			"tap": func(): scr.page(title, func(box): RecFlows._category(scr, tids, key, box))})
	var herds := {}; var heads := 0; var town_heads := {}
	for tid in tids:
		var town_herds := herd_heads(RecWorld._e(tid))
		var town_total := 0
		for kind in town_herds:
			var n := int(town_herds[kind])
			herds[kind] = int(herds.get(kind, 0)) + n; heads += n
			town_total += n
		town_heads[String(tid)] = town_total
	RecKit.metrics(v, [
		{"title": "Towns covered", "value": str(tids.size()), "color": UiTheme.BLUE},
		{"title": "Market stock units", "value": str(market_units), "note": "Across the listed goods categories", "color": UiTheme.COPPER},
		{"title": "Animals in town herds", "value": str(heads), "note": "Every recorded owner", "color": UiTheme.BLUE}])
	var card := RecKit.card(v, "Goods by kind", "Market stock and days at recorded demand. Select a kind for goods and price spreads.")
	RecKit.grid(card, ["Kind", "Stock units", "Market days"], categories, [2.0, 1.0, 1.0])
	var table := herds_table(scr, tids)
	for row: Dictionary in table.rows:
		var economy := RecWorld._e(String(row["tid"]))
		row["head"] = int(town_heads.get(String(row["tid"]), 0))
		var fodder: Variant = RecData.fodder_days(economy)
		row["fodder"] = fodder if fodder != null and float(fodder) >= 0.0 else null
	table.cols.append_array([{"k": "head", "t": "Head", "num": true}, {"k": "fodder", "t": "Fodder days", "num": true}])
	table._build_controls()
	table.display_cells([{"k": "town", "t": "Town", "w": 2.0}, {"k": "head", "t": "Head"},
		{"k": "fodder", "t": "Fodder days", "format": _number}])
	RecKit.card(v, "Herds by town", "Select a town for its animals and owners.").add_child(table)
	RecKit.disclosure(v, "Head by animal", func(box):
		var rows := []
		var keys: Array = herds.keys(); keys.sort()
		for key in keys: rows.append({"values": [RecData.herd_word({}, key).capitalize(), str(int(herds[key]))]})
		RecKit.grid(box, ["Animal", "Head"], rows, [2, 1]))
	RecKit.disclosure(v, "Full goods record and drovers on the road", legacy)

static func herds_table(scr, tids: Array) -> RecTable:
	var herd_rows := []
	for tid in tids:
		var e2 := RecWorld._e(tid)
		var hs: Dictionary = herd_heads(e2)
		var fd: Variant = RecData.fodder_days(e2)
		var tt := String(tid)
		herd_rows.append({"tid": tt, "town": RecData.tname(tid), "_l": RecData.tname(tid),
			"_d": func(): return RecTown.herd_text(e2, hs) + ((" (fodder %d days)" % int(float(fd))) if fd != null else ""),
			"_tap": func(): scr.open_town(tt)})
	return RecTable.make([{"k": "town", "t": "Town"}], herd_rows, "town", true, [], true, 8)

## Equivalent exact row-construction sequence split out for phase attribution.
## Full frozen herds_table above remains the independent baseline.
static func herd_rows(scr, tids: Array) -> Array:
	var herd_rows := []
	for tid in tids:
		var e2 := RecWorld._e(tid)
		var hs: Dictionary = herd_heads(e2)
		var fd: Variant = RecData.fodder_days(e2)
		var tt := String(tid)
		herd_rows.append({"tid": tt, "town": RecData.tname(tid), "_l": RecData.tname(tid),
			"_d": func(): return RecTown.herd_text(e2, hs) + ((" (fodder %d days)" % int(float(fd))) if fd != null else ""),
			"_tap": func(): scr.open_town(tt)})
	return herd_rows

## Goods-only frozen v0.042 world wrapper, retaining its per-build people cache.
static var _pc := {}

static func _people(tids: Array) -> int:
	var n := 0
	for tid in tids:
		if not _pc.has(tid): _pc[tid] = RecData.live_people(RecWorld._e(tid))
		n += int(_pc[tid])
	return n

static func build(scr, tids: Array, fid: String = "") -> Control:
	_pc.clear()
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	RecKit.line(v, "%d people; %d towns in view" % [_people(tids), tids.size()], "Small").add_theme_color_override("font_color", UiTheme.LIGHT)
	goods(scr, tids, v, func(b): RecWorld.goods(scr, tids, b))
	RecKit.disclosure(v, "Scope totals", func(b):
		var wars: Array = Game.world.get("wars", [])
		if fid != "": wars = wars.filter(func(p): return String(p[0]) == fid or String(p[1]) == fid)
		RecKit.grid(b, ["Recorded scope", "Count"], [
			{"values": ["Towns", str(tids.size())]}, {"values": ["People", str(_people(tids))]},
			{"values": ["Pairs of factions at war", str(wars.size())]}, {"values": ["Forces on the map", str(RecWorld._forces(fid).size())]}], [2, 1]))
	_pc.clear()
	return v


## Read-only records entry point: same shallow hd copy as RecData.herds.
static func herd_heads(e: Dictionary) -> Dictionary:
	return town_heads(RecData._herd_read(e))

## Exact v0.042 Herds.town_heads body; only helper names are rebound.
## Raw entry point also lets focused tests compare derived-cache mutations.
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
	for hid in Herds.herds(e):
		var h: Dictionary = Herds.herds(e)[hid]
		var n := Herds.head(h)
		if n > 0:
			out[String(h["k"])] = int(out.get(String(h["k"]), 0)) + n
	return out
