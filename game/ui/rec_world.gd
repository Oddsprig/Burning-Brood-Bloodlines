class_name RecWorld
extends RefCounted
## The whole-world and faction tabs of the records screen (world screen spec parts 1-2). A faction view is the same
## tabs over that faction's towns and forces, plus Army. Every number from the sim; "not tracked" for the rest.
## tids = the towns in view (every town, or the faction's); fid = "" for the whole world.

const SIZE_WORDS := ["hamlet", "village", "town", "large town", "city"]

static func build(scr, tids: Array, fid: String, tab: String) -> Control:
	# Counts live only for one build; every navigation still opens real identities.
	_pc.clear()
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Census already needs this fresh balance; reuse its population for the header.
	var census_world := {}
	var census_balance := {}
	if tab == "Census":
		census_world = RecFlows.read_world(tids)
		census_balance = Census.balance_of(census_world, tids)
	var people := int(census_balance["people"]) if tab == "Census" else _people(tids)
	RecKit.line(v, "%d people; %d towns in view" % [people, tids.size()], "Small").add_theme_color_override("font_color", UiTheme.LIGHT)
	match tab:
		"Towns": RecRegions.towns(scr, tids, fid, v, towns_table(scr, tids, RecRegions.town_columns()), func(b): towns(scr, tids, fid, b))
		"Army": RecRegions.army(scr, fid, v, func(b): army(scr, fid, b))
		"Factions": RecRegions.factions(scr, tids, fid, v, factions_table(scr), func(b): factions(scr, tids, fid, b))
		"Rulers": RecRegions.rulers(scr, tids, v, rulers_table(scr, tids), func(b): rulers(scr, tids, b))
		"On the move": RecRegions.on_the_move(scr, tids, fid, v, move_table(scr, fid, RecRegions.move_columns()), func(b): on_the_move(scr, tids, fid, b))
		"Goods": RecFlows.goods(scr, tids, v, func(b): goods(scr, tids, b))
		"Food flows": RecFlows.food_flows(scr, tids, v, func(b): food_flows(scr, tids, b))
		"Fights": RecFlows.fights(scr, tids, fid, v, func(b): fights(scr, tids, fid, b))
		"Mines & land": RecFlows.mines_land(scr, tids, v, func(b): mines_land(scr, tids, b))
		"Merchants": RecFlows.merchants(scr, tids, v, func(b): merchants(scr, tids, b))
		"Census": census(scr, tids, v, census_world, census_balance)
	RecKit.disclosure(v, "Scope totals", func(b):
		var wars: Array = Game.world.get("wars", [])
		if fid != "": wars = wars.filter(func(p): return String(p[0]) == fid or String(p[1]) == fid)
		RecKit.grid(b, ["Recorded scope", "Count"], [
			{"values": ["Towns", str(tids.size())]}, {"values": ["People", str(_people(tids))]},
			{"values": ["Pairs of factions at war", str(wars.size())]}, {"values": ["Forces on the map", str(_forces(fid).size())]}], [2, 1]))
	_pc.clear()
	return v

static func census(scr, tids: Array, v: VBoxContainer, prepared_world: Dictionary = {}, prepared_balance: Dictionary = {}) -> void:
	var world := prepared_world if not prepared_world.is_empty() else RecFlows.read_world(tids)
	var balance := prepared_balance if not prepared_balance.is_empty() else Census.balance_of(world, tids)
	var ok := Census.adds_up(balance)
	RecKit.metrics(v, [
		{"title": "People now", "value": str(int(balance["people"])), "note": "%d at last census" % int(balance["last"]), "color": UiTheme.BLUE},
		{"title": "Population change", "value": "%+d" % int(balance["change"]), "note": "Since last census", "color": UiTheme.COPPER},
		{"title": "Census balance", "value": "Adds up" if ok else "DOES NOT ADD UP", "note": "Recorded births, deaths and moves", "color": UiTheme.GOOD if ok else UiTheme.BAD}])
	RecKit.grid(v, ["Since last census", "People"], [
		{"values": ["Born", str(int(balance["births"]))]}, {"values": ["Died", str(int(balance["deaths"]))]},
		{"values": ["Arrived", str(int(balance["arrived"]))]}, {"values": ["Left", str(int(balance["left"]))]}], [2, 1])
	var table := RecTown.seasons_table(scr, world, tids, [{"k": "_l", "t": "Season", "w": 1.7}, {"k": "people", "t": "People"},
		{"k": "births", "t": "Born"}, {"k": "deaths", "t": "Died"}, {"k": "arrived", "t": "Arrived"}, {"k": "left", "t": "Left"}])
	RecKit.card(v, "Season records").add_child(table)
	var causes := Census.causes_of(world, tids)
	var rows := []
	for cause in Census.CAUSES:
		var cs := String(cause)
		var now := int(causes["now"].get(cs, 0))
		rows.append({"values": [cs.capitalize(), str(now), str(int(causes["last"].get(cs, 0))), RecKit.per_k(now, int(balance["people"]))],
			"tap": func(): scr.page("Died of %s" % cs, func(b): RecTown.dead_list(scr, Game.world, tids, cs, b))})
	RecKit.grid(v, ["Death cause", "This season", "Last season", "Per 1,000 people"], rows, [1.7, 1, 1, 1.3])
	RecKit.card(v, "More census records").add_child(UiKit.button("View census by race", func(): scr.page("Census by race", func(b): RecRaces.card(scr, tids, b)), "Row"))
	RecKit.disclosure(v, "Population charts, sickness and movements", func(b): RecTown.census_cards(scr, RecFlows.read_world(tids), tids, b))

static func _m(v: float) -> String:
	return RecData.money(v)

static func _t(tid: String) -> Dictionary:
	return RecData.town(tid)

static func _e(tid: String) -> Dictionary:
	return RecData.econ(_t(tid))

static var _pc := {}     # people per town, shared only by cards in one build

static func _people(tids: Array) -> int:
	var n := 0
	for tid in tids:
		n += _town_people(tid)
	return n

static func _town_people(tid: String) -> int:
	if not _pc.has(tid):
		_pc[tid] = RecData.live_people(_e(tid))
	return int(_pc[tid])

## Forces on the map in view: every one (world) or the faction's.
static func _forces(fid: String) -> Array:
	var out := []
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		if fid == "" or String(wb.get("faction", "")) == fid:
			out.append(wb)
	return out

static func _header(tids: Array, fid: String, v: VBoxContainer, people: int = -1) -> void:
	var w: Dictionary = Game.world
	var wars: Array = w.get("wars", [])
	if fid != "":
		wars = wars.filter(func(p): return String(p[0]) == fid or String(p[1]) == fid)
	RecKit.line(v, "%s. %d towns, %d people; %d pairs of factions at war; %d forces on the map." % [Calendar.text(Game.day), tids.size(),
		_people(tids) if people < 0 else people, wars.size(), _forces(fid).size()], "Small")

## v0.012: the faction's research house (campaign/academy.gd): its name and lead's title, know-how, budget, staff,
## each research line; tap through to the house's business page.
static func research_card(scr, fid: String, v: VBoxContainer) -> void:
	RecRegions.research(scr, fid, v)

static func towns(scr, tids: Array, fid: String, v: VBoxContainer) -> void:
	var w: Dictionary = Game.world
	if fid != "":
		research_card(scr, fid, v)   # v0.012: steel know-how, the research budget, staff and lines
	var food_d := 0.0; var short := 0; var starving := 0
	var avg := {"food": 0.0, "drink": 0.0, "metal": 0.0}
	var info := {}   # per town, read once: [food index, copper bar price, food days, beer price]
	for tid in tids:
		var t := _t(tid)
		var fd := RecData.days_food(t)
		info[tid] = [RecData.food_index(t), RecData.price(t, "copper_bars"), fd, RecData.price(t, "beer")]
		food_d += fd
		var lvl := TownEcon.supply_level(t, fd)
		if lvl == "short": short += 1
		elif lvl == "starving": starving += 1
		avg["food"] += float(info[tid][0])
		avg["drink"] += float(info[tid][3])
		avg["metal"] += float(info[tid][1])
	var n := maxf(1.0, float(tids.size()))
	for k in avg:
		avg[k] = float(avg[k]) / n
	var hc := RecKit.card(v, "The towns")
	RecKit.kv(hc, "Towns, people", "%d, %d" % [tids.size(), _people(tids)])
	RecKit.kv(hc, "Average food days", RecKit.num(food_d / n))
	RecKit.kv(hc, "Short of food, starving", "%d, %d" % [short, starving])
	var cars := _forces(fid).filter(func(wb): return String(wb.get("kind", "")) == "caravan")
	RecKit.kv(hc, "Caravans on the road", "%d" % cars.size())
	var hfs := []
	for tid in tids:
		var hv: Variant = RecData.harvest_factor(_e(tid))
		if hv != null:
			hfs.append("%s x%.2f" % [String(_t(tid)["name"]), float(hv)])
	RecKit.kv(hc, "This year's harvest factor (weather, x1.00 = normal)", ", ".join(PackedStringArray(hfs)) if not hfs.is_empty() else RecKit.NT)
	v.add_child(UiKit.button("View town price and wealth spreads", func(): scr.page("Asymmetry at a glance", func(b): _town_spreads(tids, b)), "Row"))
	v.add_child(towns_table(scr, tids))
static func _town_row_details(t: Dictionary, e: Dictionary, info: Array, mil: int, hard: float, fi: float, di: float, mi: float) -> String:
	var specialties := []
	var definitions: Dictionary = RecData.D()["specialties"]
	for specialty in e.get("specialties", []):
		specialties.append(String(definitions.get(specialty, {}).get("text", specialty)))
	var kind := String(SIZE_WORDS[clampi(int(t.get("size", 0)), 0, 4)]) + (", capital" if t.get("capital", false) else "")
	return "%s, %s, %s; known for %s; makes %s; food %d days, granary %d days; treasury %s; hardship %d%%; militia %d; food x%.2f drink x%.2f metal x%.2f of average; open cases of sickness %s; health, lives on: %s" % [
		kind, UiWords.faction_name(String(t.get("faction", ""))), String(TownEcon.culture_of(e).get("race", "?")), " and ".join(PackedStringArray(specialties)),
		_makes(e), int(info[2]), int(RecData.granary_days(e)), _m(RecData.treasury(e)), int(hard), mil, fi, di, mi, RecPages.open_cases(t), RecKit.NT]

## Families in hardship (at or past the recruit-pool line), %: the census's latest weekly count when it has one.
static func _hard_pct(e: Dictionary) -> float:
	var wb: Dictionary = e.get("census", {}).get("wbuf", {})
	if (wb.get("hard", []) as Array).size() > 0 and int(wb["fams"][-1]) > 0:
		return 100.0 * float(wb["hard"][-1]) / float(wb["fams"][-1])
	var fs := RecData.fams(e)
	if fs.is_empty():
		return 0.0
	var n := 0
	for f in fs:
		if RecData.hardship(f) >= float(RecData.D()["family"]["recruit_hardship"]):
			n += 1
	return 100.0 * n / fs.size()

## The town's top 3 products by what it really made (the conservation ledgers, all time).
static func _makes(e: Dictionary) -> String:
	var made: Dictionary = e.get("led", {}).get("made", {})
	var goods: Dictionary = RecData.D()["goods"]
	var ranked := []
	for g in made:
		var info: Dictionary = goods.get(g, {})
		if String(info.get("cat", "")) in ["made", "bars", "raw", "drink", "arms"]:
			ranked.append([float(made[g]) * float(info.get("price", 1.0)), g])
	ranked.sort_custom(func(a, b): return a[0] > b[0])
	var out := []
	for record in ranked.slice(0, 3):
		out.append(RecData.good_name(e, String(record[1])))
	return ", ".join(PackedStringArray(out)) if not out.is_empty() else "nothing yet"
## Scan purses and tills only when the comparison is opened; the tab's town rows do not need it.
static func _town_spreads(tids: Array, box: VBoxContainer) -> void:
	var info := {}
	for tid in tids:
		var t := _t(tid)
		var e := _e(tid)
		info[tid] = [RecData.food_index(t), RecData.price(t, "copper_bars"),
			TownEcon.town_gold(e) / maxf(1.0, float(RecData.live_people(e))), RecData.days_food(t), _hard_pct(e)]
	var sp := RecKit.card(box, "Asymmetry at a glance", "Readout only: the dearest and cheapest town for each.")
	for k in [["Food price index", 0], ["Copper bar price", 1], ["Wealth a person (purses + treasury + tills)", 2], ["Food days", 3],
			["Families in hardship %", 4]]:
		var hi := ""; var lo := ""; var hv := -INF; var lv := INF
		for tid in tids:
			var x := float(info[tid][int(k[1])])
			if x > hv: hv = x; hi = tid
			if x < lv: lv = x; lo = tid
		if hi != "":
			RecKit.kv(sp, String(k[0]), "%s in %s, %s in %s" % [RecKit.num(hv), RecData.tname(hi), RecKit.num(lv), RecData.tname(lo)])
	RecKit.nt(sp, "Arms price spread")

# ================================================================== Factions
static func factions(scr, _tids: Array, _fid: String, v: VBoxContainer) -> void:
	v.add_child(factions_table(scr))

static func _faction_page(scr, fid: String, box: VBoxContainer) -> void:
	var w: Dictionary = Game.world
	box.add_child(RecKit.row("Open the faction view", "", "its towns, army and census", func(): scr.open_faction(fid)))
	research_card(scr, fid, box)
	var c := RecKit.card(box, "Relations")
	for o in w.get("factions", {}):
		if o == fid:
			continue
		RecKit.kv(c, UiWords.faction_name(String(o)), "%s, %d" % [String(Diplomacy.state(w, fid, String(o))).to_lower().replace("_", " "), int(round(Diplomacy.relation(w, fid, String(o))))])
	RecKit.nt(c, "Last change of each relation and its cause; war chest chart")
	var ac := RecKit.card(box, "Armies in the field")
	for wb in _forces(fid):
		if Army.is_field(wb):
			var wid := String(wb["id"])
			ac.add_child(RecKit.row(RecPages.force_name(wb), "%d men" % (wb["units"] as Array).size(), "near %s" % CampaignWorld.nearest_town_name(w, wb["pos"]), func(): scr.open_force(wid)))

# ================================================================== Army (faction view)
static func army(scr, fid: String, v: VBoxContainer) -> void:
	if fid == "":
		RecKit.line(v, "Pick a faction for its army.", "Muted")
		return
	var w: Dictionary = Game.world
	var fac: Dictionary = w["factions"].get(fid, {})
	var cul := Army.cul_of_faction(fid)
	var c := RecKit.card(v, "The army of %s" % UiWords.faction_name(fid))
	var bill := Army.bill(Game, fid)
	var dl := Army.days_of_pay(Game, fid)
	RecKit.kv(c, "Men under arms", "%d" % Army.members(Game, fid).size())
	RecKit.kv(c, "Wage bill", _m(bill) + " a day")
	RecKit.kv(c, "War chest", "%s (%s days of pay)" % [_m(float(fac.get("treasury", 0.0))), RecKit.num(dl) if dl < 1.0e9 else "-"])
	RecKit.kv(c, "Rank rule", String(cul.get("rank_rule", "")))
	var rc := RecKit.card(v, "Ranks", "The culture's rank names, counts against the caps, pay a day by rank.")
	for row in Army.tree_rows(RecRegions._army_read(), fid):
		var cap := int(row["cap"])
		var offs := []
		for u in row["officers"]:
			offs.append((u as Unit).name)
		RecKit.kv(rc, String(row["title"]).capitalize(), "%d%s, %s a day%s" % [int(row["count"]), (" of %d" % cap) if cap >= 0 else "",
			_m(Army.wage("army", int(row["rank"]))), (": " + ", ".join(PackedStringArray(offs))) if not offs.is_empty() else ""])
	var hc := RecKit.card(v, "Promotions and successions", "Newest first (the realm's own record).")
	var hist: Array = w.get("army", {}).get("f", {}).get(fid, {}).get("hist", [])
	if hist.is_empty():
		RecKit.line(hc, "Nothing yet.", "Muted")
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 15), -1):
		RecKit.line(hc, String(hist[i]), "Small")
	var fc := RecKit.card(v, "Armies and their commanders")
	for wb in _forces(fid):
		if not Army.is_field(wb):
			continue
		var lead: Unit = null
		for u in wb["units"]:
			if not u.dead and (lead == null or u.rank > lead.rank):
				lead = u
		var wid := String(wb["id"])
		fc.add_child(RecKit.row(RecPages.force_name(wb), "%d men" % (wb["units"] as Array).size(),
			"led by %s %s" % [Army.rank_title(lead), lead.name] if lead != null else "no leader", func(): scr.open_force(wid)))

# ================================================================== Rulers
static func rulers(scr, tids: Array, v: VBoxContainer) -> void:
	var c := RecKit.card(v, "Rulers", "Heads as register persons with traits, and town rules rolled from them: not tracked yet (world spec 1, NEW SIM). What the sim has:")
	RecKit.nt(c, "Faction heads, traits, what each head cares most for, when the rules last changed")
	var ac := RecKit.card(v, "What each town asks", "Built from the live values (the same in every town until heads roll their own rules).")
	ac.add_child(rulers_table(scr, tids))
static func on_the_move(scr, tids: Array, fid: String, v: VBoxContainer) -> void:
	var w: Dictionary = Game.world
	var gold := 0.0; var ncar := 0; var nfield := 0
	for wb in _forces(fid):
		if String(wb.get("kind", "")) == "caravan":
			ncar += 1; gold += float(wb.get("gold", 0.0))
		if Army.is_field(wb): nfield += 1
	var c := RecKit.card(v, "On the move")
	RecKit.kv(c, "Caravans on the road", "%d, carrying %s in coin" % [ncar, _m(gold)])
	RecKit.kv(c, "Armies in the field", "%d" % nfield)
	var ws: Dictionary = w.get("war", {}).get("stats", {})
	RecKit.kv(c, "Interceptions (since the world began)", "%d" % int(ws.get("intercepts", 0)))
	RecKit.kv(c, "Carriers", "wagons (caravans) only: no pack animals, porters or boats in the sim")
	for k in ["Robbed this season", "Worth of consignments", "Carriers going home empty", "Relief grain on the way", "Fetched by the buyer vs sent by the seller", "Arriving soonest (ETA)"]:
		RecKit.nt(c, k)
	v.add_child(move_table(scr, fid))

# ================================================================== Goods
static func goods(scr, tids: Array, v: VBoxContainer) -> void:
	var c := RecKit.card(v, "Goods by kind", "Market stock summed over the towns, days at today's demand, the price spread.")
	for cat in RecTown.CATS:
		var ck := String(cat[0])
		var goods_in := RecTown._goods_in(ck)
		var st := 0; var dem := 0.0
		for tid in tids:
			var totals := RecData.market_totals(_e(tid), goods_in)
			st += int(totals[0])
			dem += float(totals[1])
		c.add_child(RecKit.row(String(cat[1]), "%d" % st, "%s days" % (RecKit.num(st / dem) if dem > 0.0 else "-"),
			func(): scr.page(String(cat[1]), func(b): _cat_page(scr, tids, ck, b))))
	var hc := RecKit.card(v, "Herds by town", "Head counted in each town's herd records (every owner), fodder days left.")
	var tot := {}
	for tid in tids:
		var hs: Dictionary = RecData.herds(_e(tid))
		for k in hs: tot[k] = int(tot.get(k, 0)) + int(hs[k])
	RecKit.kv(hc, "All", RecTown.herd_text({}, tot))
	hc.add_child(herds_table(scr, tids))
	var dv := RecData.droves()
	if not dv.is_empty():
		var dc := RecKit.card(v, "Herds on the road", "Drovers walking beasts to a town that pays more.")
		for d in dv:
			if tids.has(String(d["from"])) or tids.has(String(d["to"])):
				RecKit.kv(dc, "%s to %s" % [RecData.tname(String(d["from"])), RecData.tname(String(d["to"]))], "%d %s" % [int(d["head"]), String(d["kind"])])

static func _cat_page(scr, tids: Array, cat: String, box: VBoxContainer) -> void:
	for g in RecTown._goods_in(cat):
		var gg := String(g)
		var st := 0
		var lo := INF; var hi := -INF
		for tid in tids:
			st += RecData.stock(_e(tid), g)
			var p := RecData.price(_t(tid), g)
			lo = minf(lo, p); hi = maxf(hi, p)
		box.add_child(RecKit.row(Goods.good_name(g).capitalize(), "%d" % st, "price %s to %s" % [RecKit.num(lo), RecKit.num(hi)],
			func(): scr.page(Goods.good_name(gg).capitalize(), func(b): _good_towns(scr, tids, gg, b))))

static func _good_towns(scr, tids: Array, g: String, box: VBoxContainer) -> void:
	var rows := []
	var lo := INF; var hi := -INF; var lt := ""; var ht := ""
	for tid in tids:
		var p := RecData.price(_t(tid), g)
		if p < lo: lo = p; lt = tid
		if p > hi: hi = p; ht = tid
	for tid in tids:
		var t := _t(tid); var e := _e(tid)
		var p := RecData.price(t, g)
		var pw: Variant = RecData.price_week_ago(e, g)
		var ch: Variant = (p / float(pw) - 1.0) * 100.0 if pw != null and float(pw) > 0.0 else null
		var st := RecData.stock(e, g); var dem := RecData.demand(e, g)
		var tt := String(tid)
		rows.append({"name": String(t["name"]), "price": p, "stock": st, "days": st / dem if dem > 0.0 else null, "chg": ch,
			"_l": String(t["name"]) + (" (cheapest)" if tid == lt else (" (dearest)" if tid == ht else "")), "_r": _m(p),
			"_d": "x%.2f base, stock %d, %s days, %s a week" % [p / RecData.base_price(g), st, RecKit.num(st / dem) if dem > 0.0 else "-",
				("%+d%%" % int(round(float(ch)))) if ch != null else "-"], "_tap": func(): scr.open_town(tt)})
	box.add_child(RecTable.make([{"k": "name", "t": "Town"}, {"k": "price", "t": "Price", "num": true}, {"k": "stock", "t": "Stock", "num": true},
		{"k": "days", "t": "Days", "num": true}, {"k": "chg", "t": "7-day %", "num": true}], rows, "price", true))

# ================================================================== Food flows
static func food_flows(scr, tids: Array, v: VBoxContainer) -> void:
	var w: Dictionary = Game.world
	var c := RecKit.card(v, "How the world feeds itself", "Towns by climate (latitude): food days in the market and the households' use.")
	for clim in (TownEcon.data()["climates"] as Dictionary).keys():   # (v0.012: the data's climates, "dry" too)
		var n := 0; var days := 0.0; var gran := 0
		for tid in tids:
			if String(_e(tid).get("climate", "")) == clim:
				n += 1; days += RecData.days_food(_t(tid)); gran += RecData.granary(_e(tid))
		if n > 0:
			RecKit.kv(c, "%s (%d towns)" % [String(clim).capitalize(), n], "%s food days on average, %d meals in the granaries" % [RecKit.num(days / n), gran])
	RecKit.nt(c, "Surplus and shortfall by food (grain, meat, fruit, beer, wine) per region")
	var fc := RecKit.card(v, "Food on the road now", "Caravans carrying food and drink, by direction.")
	var any := false
	for wb in _forces(""):
		if String(wb.get("kind", "")) != "caravan":
			continue
		var gd: Dictionary = wb.get("cargo", {}).get("goods", {})
		var food := 0
		for g in ["grain", "fruit", "meat", "beer", "wine"]:
			food += int(gd.get(g, 0))
		if food <= 0:
			continue
		var o := _t(String(wb.get("origin", ""))); var d := _t(String(wb.get("dest", "")))
		if not tids.has(String(wb.get("origin", ""))) and not tids.has(String(wb.get("dest", ""))):
			continue
		any = true
		var way := "-"
		if not o.is_empty() and not d.is_empty():
			var dv: Vector2 = (d["pos"] as Vector2) - (o["pos"] as Vector2)
			way = ("north" if dv.y < 0 else "south") if absf(dv.y) > absf(dv.x) else ("west" if dv.x < 0 else "east")
		var wid := String(wb["id"])
		fc.add_child(RecKit.row("%s -> %s" % [String(o.get("name", "?")), String(d.get("name", "?"))], "%d" % food, "%s; %s" % [way, Caravans.cargo_text(wb.get("cargo", {}))],
			func(): scr.open_force(wid)))
	if not any:
		RecKit.line(fc, "No food on the road.", "Muted")
	RecKit.nt(v, "The great food houses (merchant families shipping food) and relief grain sent to starving towns")

# ================================================================== Fights
static func fights(scr, tids: Array, fid: String, v: VBoxContainer) -> void:
	var w: Dictionary = Game.world
	var causes := Census.causes_of(RecFlows.read_world(tids), tids)
	var c := RecKit.card(v, "Fights", "Fight records of their own (both sides, the named dead, loot, what changed after): not tracked. What the sim keeps:")
	RecKit.kv(c, "Died fighting this season (people of these towns)", "%d (last season %d)" % [int(causes["now"].get("battle", 0)), int(causes["last"].get("battle", 0))])
	var ws: Dictionary = w.get("war", {}).get("stats", {})
	RecKit.kv(c, "War bands that ran their prey down / were beaten / gave up (since the world began)", "%d / %d / %d" % [int(ws.get("caught", 0)), int(ws.get("beaten", 0)), int(ws.get("gave_up", 0))])
	for k in ["Fights seen vs resolved out of sight vs called off", "Wounded, maimed, died of wounds later, fled", "Taken prisoner", "Coming up (fights set by the AI)"]:
		RecKit.nt(c, k)
	c.add_child(RecKit.row("The dead in battle", "", "name, age, family, the fight", func(): scr.page("Died in battle", func(b): RecTown.dead_list(scr, w, tids, "battle", b))))
	v.add_child(UiKit.button("View legendary arms", func(): scr.page("Legendary arms", func(b): legends_card(scr, b)), "Row"))
	var lc := RecKit.card(v, "The world's log", "Newest first%s." % ("" if fid == "" else ", lines naming %s or its towns" % UiWords.faction_name(fid)))
	var names := tids.map(func(x): return RecData.tname(x))
	if fid != "":
		names.append(CampaignWorld.faction_the(fid).trim_prefix("the "))
	var log: Array = w.get("log", [])
	var n := 0
	for i in range(log.size() - 1, -1, -1):
		var line := String(log[i])
		var hit := fid == ""
		if not hit:
			for nm in names:
				if line.contains(String(nm)):
					hit = true
					break
		if hit:
			RecKit.line(lc, line, "Small")
			n += 1
			if n >= 40:
				break
	if n == 0:
		RecKit.line(lc, "Nothing on the log.", "Muted")

## v0.014: every legendary piece in the world, each with its own page (gem, maker, kills, every change of hands).
static func legends_card(scr, v: VBoxContainer) -> void:
	var lc := RecKit.card(v, "Legendary arms", "Unique pieces made by real smiths in an inspired hour; never lost in battle.")
	var all := Legends.all_held(Game)
	if all.is_empty():
		RecKit.line(lc, "None made yet.", "Muted")
	for row in all:
		var it: Item = row[0]
		var where := String(row[1])
		lc.add_child(RecKit.row(it.display_name(), "%d kills" % int(it.legend.get("k", 0)), where, func(): scr.page(String(it.legend.get("nm", "?")), func(b): legend_page(it, where, b))))

static func legend_page(it: Item, where: String, box: VBoxContainer) -> void:
	var c := RecKit.card(box, it.display_name())
	RecKit.kv(c, "Now", where)
	RecKit.kv(c, "Worth", _m(float(it.value())))
	RecKit.kv(c, "Gem", "%s, in its %s" % [it.gem_name(), String(it.legend.get("at", "?"))])
	var hc := RecKit.card(box, "Its story", "Maker, kills and every change of hands, oldest first.")
	for line in it.legend_lines().slice(1):
		RecKit.line(hc, String(line), "Small")

# ================================================================== Mines & land
static func mines_land(scr, tids: Array, v: VBoxContainer) -> void:
	var mc := RecKit.card(v, "Ore deposits")
	mc.add_child(mines_table(scr, tids))
	v.add_child(UiKit.button("View land and herds", func(): scr.page("The land", func(b): _land_card(tids, b)), "Row"))

static func _land_card(tids: Array, box: VBoxContainer) -> void:
	var crops := {}; var herds := {}; var est := 0; var fam := 0
	for tid in tids:
		var ls := RecData.land(_e(tid))
		fam += int(ls["families"]); est += int(ls["estate"])
		for k in ls["fam_crops"]:
			crops[k] = int(crops.get(k, 0)) + int(ls["fam_crops"][k])
		for k in ls["est_crops"]:
			crops[k] = int(crops.get(k, 0)) + int(ls["est_crops"][k])
		for k in ls["herds"]:
			herds[k] = int(herds.get(k, 0)) + int(ls["herds"][k])
	var lc := RecKit.card(box, "The land")
	RecKit.kv(lc, "Acres", "%d held by families, %d by the towns" % [fam, est])
	for k in crops:
		RecKit.kv(lc, String(k).capitalize(), "%d acres" % int(crops[k]))
	for k in herds:
		RecKit.kv(lc, String(k).capitalize(), "%d head" % int(herds[k]))
	RecKit.nt(lc, "Pasture, woodland, and woodland cut vs regrown each season")

# ================================================================== Merchants
static func merchants(scr, tids: Array, v: VBoxContainer) -> void:
	var c := RecKit.card(v, "Merchants", "Merchant families owning caravans: not tracked (each town's merchants trade on the treasury's purse). By town:")
	c.add_child(merchants_table(scr, tids))
	var ac := RecKit.card(v, "Garrison supply", "Own-faction armouries distribute real surplus every ten days; reserves are 2.5 times supported troop equipment beyond issued kit.")
	ac.add_child(supply_table(scr, tids))

# Original live table sources; presentation never duplicates these rows.
static func towns_table(scr, tids: Array, display_columns: Array = []) -> RecTable:
	var avg := {"food": 0.0, "drink": 0.0, "metal": 0.0}
	var info := {}   # per town, read once: [food index, copper bar price, food days, beer price]
	for tid in tids:
		var t := _t(tid)
		var fd := RecData.days_food(t)
		info[tid] = [RecData.food_index(t), RecData.price(t, "copper_bars"), fd, RecData.price(t, "beer")]
		avg["food"] += float(info[tid][0])
		avg["drink"] += float(info[tid][3])
		avg["metal"] += float(info[tid][1])
	var n := maxf(1.0, float(tids.size()))
	for k in avg:
		avg[k] = float(avg[k]) / n
	var rows := []
	for tid in tids:
		var t := _t(tid)
		var e := _e(tid)
		var tt := String(tid)
		# These values are needed only for visible details or when sorting their own column.
		var mil := func(): return Militia.units_of(Game, tt).size()
		var hard := func(): return _hard_pct(e)
		var gran := func(): return RecData.granary_days(e)
		var inf: Array = info[tid]
		var fi := float(inf[0]) / maxf(0.01, float(avg["food"]))
		var di := float(inf[3]) / maxf(0.01, float(avg["drink"]))
		var mi := float(inf[1]) / maxf(0.01, float(avg["metal"]))
		var ppl := _town_people(tid)
		rows.append({"name": String(t["name"]), "faction": UiWords.faction_name(String(t.get("faction", ""))), "people": ppl,
			"food": float(inf[2]), "gran": gran, "tre": RecData.treasury(e), "hard": hard, "mil": mil,
			"fi": fi, "di": di, "mi": mi,
			"_l": String(t["name"]), "_r": "%d people" % ppl,
			"_d": func(): return _town_row_details(t, e, inf, int(mil.call()), float(hard.call()), fi, di, mi),
			"_s": String(t["name"]), "_tap": func(): scr.open_town(tt)})
	return RecTable.make([{"k": "name", "t": "Town"}, {"k": "faction", "t": "Faction"}, {"k": "people", "t": "People", "num": true},
		{"k": "food", "t": "Food days", "num": true}, {"k": "gran", "t": "Granary", "num": true}, {"k": "tre", "t": "Treasury", "num": true},
		{"k": "hard", "t": "Hardship", "num": true}, {"k": "mil", "t": "Militia", "num": true}, {"k": "fi", "t": "Food x", "num": true},
		{"k": "di", "t": "Drink x", "num": true}, {"k": "mi", "t": "Metal x", "num": true}], rows, "name", true, [], true, RecTable.LIMIT, display_columns)

static func factions_table(scr) -> RecTable:
	var w: Dictionary = Game.world
	var fids: Array = w.get("factions", {}).keys()
	fids.sort()
	var rows := []
	for f in fids:
		var ff := String(f)
		var ft: Array = []
		for tid in w.get("towns", {}):
			if String(w["towns"][tid].get("faction", "")) == ff and RecData.town(tid).has("econ"):
				ft.append(tid)
		var fac: Dictionary = w["factions"][f]
		var bill := Army.bill(Game, ff)
		var dl := Army.days_of_pay(Game, ff)
		var men := Army.members(Game, ff).size()
		var war := []; var ally := []
		for o in fids:
			if o == f: continue
			var ds := Diplomacy.state(w, ff, String(o))
			if ds == Diplomacy.WAR:
				war.append(UiWords.faction_name(String(o)))
			elif ds == Diplomacy.ALLIANCE:
				ally.append(UiWords.faction_name(String(o)))
		rows.append({"name": UiWords.faction_name(ff), "towns": ft.size(), "people": _people(ft), "tre": float(fac.get("treasury", 0.0)),
			"bill": bill, "days": dl if dl < 1.0e9 else null, "men": men, "kh": snappedf(float(RecData.research(ff)["kh"].get("steel", 0.0)), 0.1),
			"_l": UiWords.faction_name(ff), "_r": _m(float(fac.get("treasury", 0.0))),
			"_d": "%d towns, %d people; army %d men, pay %s a day, %s days of pay; at war with %s; allied with %s; price level x%.2f, money index %s; head, tax in a day: %s" % [ft.size(), _people(ft), men,
				_m(bill), RecKit.num(dl) if dl < 1.0e9 else "-", ", ".join(PackedStringArray(war)) if not war.is_empty() else "nobody",
				", ".join(PackedStringArray(ally)) if not ally.is_empty() else "nobody", float(fac.get("pl", 1.0)),
				("x%.2f" % float(RecData.money_index(ff))) if RecData.money_index(ff) != null else RecKit.NT, RecKit.NT],
			"_col": UiTheme.BAD if not war.is_empty() else UiTheme.INK, "_s": UiWords.faction_name(ff),
			"_tap": func(): scr.page(UiWords.faction_name(ff), func(b): _faction_page(scr, ff, b))})
	return RecTable.make([{"k": "name", "t": "Faction"}, {"k": "towns", "t": "Towns", "num": true}, {"k": "people", "t": "People", "num": true},
		{"k": "tre", "t": "Treasury", "num": true}, {"k": "bill", "t": "Army pay", "num": true}, {"k": "days", "t": "Days of pay", "num": true},
		{"k": "men", "t": "Soldiers", "num": true}, {"k": "kh", "t": "Steel %", "num": true}], rows, "name", true)

static func rulers_table(scr, tids: Array) -> RecTable:
	var tr := RecData.tax_rules()
	var rows := []
	for tid in tids:
		var t := _t(tid)
		var e := _e(tid)
		var hd := RecData.head(e)
		var tt := t
		var hf := int(hd.get("fam", 0))
		var asks := "%s (%s %s): %s on every adult, %s an acre, %s a head of herd each season; %d in a hundred of the grain harvest in kind for the granary; loans at %.1f in a hundred a week." % [
			String(t["name"]), String(hd.get("title", "head")).capitalize(), String(hd.get("name", "?")), _m(float(tr["per_adult"])), _m(float(tr["per_acre"])),
			_m(float(tr["per_head"])), int(round(float(tr["grain_share"]) * 100.0)), 100.0 * RecData.loan_rate(e)]
		rows.append({"name": String(t["name"]), "head": String(hd.get("name", "?")), "people": _town_people(tid), "gran": RecData.granary_days(e),
			"_l": String(t["name"]) + (" (seat)" if t.get("capital", false) else ""), "_r": "%s %s" % [String(hd.get("title", "")), String(hd.get("name", "?"))],
			"_d": asks + " Labour duty, levies, relief rules: " + RecKit.NT, "_s": String(t["name"]) + " " + String(hd.get("name", "")),
			"_tap": func(): scr.open_family(tt, hf)})
	return RecTable.make([{"k": "name", "t": "Town"}, {"k": "head", "t": "Head"}, {"k": "people", "t": "People", "num": true},
		{"k": "gran", "t": "Granary days", "num": true}], rows, "name", true, [], true)

# ================================================================== On the move

static func move_table(scr, fid: String, display_columns: Array = []) -> RecTable:
	var w: Dictionary = Game.world
	var forces := _forces(fid)
	var kinds := ["all"]
	var facs := ["all"]
	var rows := []
	var gold := 0.0; var ncar := 0; var nfield := 0
	for wb in forces:
		var kind := String(wb.get("kind", ""))
		if not kinds.has(kind): kinds.append(kind)
		var fname := UiWords.faction_name(String(wb.get("faction", "")))
		if not facs.has(fname): facs.append(fname)
		var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
		var wid := String(wb["id"])
		var from := RecData.tname(String(wb.get("origin", wb.get("home", ""))))
		var to := String(wb.get("dest", wb.get("target_town", "")))
		if kind == "caravan":
			ncar += 1; gold += float(wb.get("gold", 0.0))
		if Army.is_field(wb):
			nfield += 1
		# Near is a sortable value, but a world-wide nearest-town scan is needed only when that sort or row is used.
		var near := func(): return CampaignWorld.nearest_town_name(w, wb["pos"])
		var force_name := RecPages.force_name(wb)
		rows.append({"kind": kind, "faction": fname, "men": units.size(), "near": near,
			"_l": force_name, "_r": "%d men" % units.size(),
			"_d": func(): return "%s; %s -> %s; near %s; %s; supply %s; %s" % [fname, from, RecData.tname(to) if to != "" else "-", near.call(),
				Caravans.cargo_text(wb.get("cargo", {}), float(wb.get("gold", 0.0))) if kind == "caravan" else "strength %s" % RecKit.num(CampaignWorld.band_power(units)),
				TownEcon.supply_word(TownEcon.force_supply(w, wb)), WarAI.mode_text(wb) if wb.has("mode") else String(wb.get("state", ""))],
			"_s": force_name, "_tap": func(): scr.open_force(wid)})
	return RecTable.make([{"k": "kind", "t": "Kind"}, {"k": "faction", "t": "Owner"}, {"k": "men", "t": "Men", "num": true}, {"k": "near", "t": "Near"}],
		rows, "kind", true, [{"t": "Kind", "opts": kinds, "fn": func(r, o): return r["kind"] == o},
		{"t": "Owner", "opts": facs, "fn": func(r, o): return r["faction"] == o}], true, 6, display_columns)

static func herds_table(scr, tids: Array, prepared: Dictionary = {}, structured: bool = false) -> RecTable:
	var herd_rows := []
	for tid in tids:
		var e2 := _e(tid)
		var tt := String(tid)
		var values: Dictionary = prepared.get(tt, {})
		var hs: Dictionary = values["herds"] if values.has("herds") else RecData.herds(e2)
		var fd: Variant = values["fodder"] if values.has("fodder") else RecData.fodder_days(e2)
		var row := {"tid": tt, "town": RecData.tname(tid), "_l": RecData.tname(tid),
			"_d": func(): return RecTown.herd_text(e2, hs) + ((" (fodder %d days)" % int(float(fd))) if fd != null else ""),
			"_tap": func(): scr.open_town(tt)}
		if structured:
			var total := int(values.get("head", 0))
			if not values.has("head"):
				for kind in hs: total += int(hs[kind])
			row["head"] = total
			row["fodder"] = fd if fd != null and float(fd) >= 0.0 else null
		herd_rows.append(row)
	var columns := [{"k": "town", "t": "Town"}]
	var lanes := []
	if structured:
		columns.append_array([{"k": "head", "t": "Head", "num": true}, {"k": "fodder", "t": "Fodder days", "num": true}])
		lanes = [{"k": "town", "t": "Town", "w": 2.0}, {"k": "head", "t": "Head"},
			{"k": "fodder", "t": "Fodder days", "format": RecFlows._number}]
	return RecTable.make(columns, herd_rows, "town", true, [], true, 8, lanes)

static func mines_table(scr, tids: Array, display_columns: Array = []) -> RecTable:
	var rows := []
	for tid in tids:
		var e := _e(tid)
		var t := _t(tid)
		var deposits: Dictionary = e.get("deposits", {})
		if deposits.is_empty(): continue
		# Preserve the last active mine for each ore, with one business scan per town.
		var mines := {}
		for b in RecData.biz(e):
			if String(b["type"]) == "mine" and not b.get("closed", false):
				mines[String(b.get("ore", "copper_ore"))] = b
		for ore in deposits:
			var mine: Dictionary = mines.get(String(ore), {})
			var tt := t
			var bid := int(mine.get("id", -1))
			rows.append({"town": String(t["name"]), "ore": Goods.good_name(String(ore)), "rich": float(e["deposits"][ore]), "workers": int(mine.get("workers", 0)),
				"_l": "%s: %s" % [String(t["name"]), Goods.good_name(String(ore))], "_r": "richness %.2f" % float(e["deposits"][ore]),
				"_d": ("%s, %d of %d at work; output a day: %s" % [RecData.biz_title(e, mine), int(mine["workers"]), int(mine["cap"]), RecKit.NT]) if not mine.is_empty() else "no mine working it",
				"_tap": (func(): scr.page(RecData.biz_title(RecData.econ(tt), RecData.biz(RecData.econ(tt))[bid]).capitalize(), func(b): RecPages.business(scr, tt, bid, b))) if bid >= 0 else Callable()})
	return RecTable.make([{"k": "town", "t": "Town"}, {"k": "ore", "t": "Ore"}, {"k": "rich", "t": "Richness", "num": true},
		{"k": "workers", "t": "Miners", "num": true}], rows, "town", true, [], false, RecTable.LIMIT, display_columns)

static func merchants_table(scr, tids: Array, display_columns: Array = []) -> RecTable:
	var cars_by_town := {}
	for wb in _forces(""):
		if String(wb.get("kind", "")) != "caravan": continue
		var origin := String(wb.get("origin", wb.get("home", "")))
		if not cars_by_town.has(origin): cars_by_town[origin] = []
		(cars_by_town[origin] as Array).append(wb)
	var rows := []
	for tid in tids:
		var cars: Array = cars_by_town.get(tid, [])
		var gold := 0.0
		for wb in cars:
			gold += float(wb.get("gold", 0.0))
		var st := RecData.stats(_e(tid))
		var tt := String(tid)
		rows.append({"town": RecData.tname(tid), "cars": cars.size(), "gold": gold, "out": float(st.get("trade_out", 0.0)),
			"_l": RecData.tname(tid), "_r": "%d caravans" % cars.size(),
			"_d": "%s in coin on the road; traded out %s, in %s (all time); profit and robbed this season: %s" % [_m(gold), _m(float(st.get("trade_out", 0.0))),
				_m(float(st.get("trade_in", 0.0))), RecKit.NT], "_tap": func(): scr.open_town(tt)})
	return RecTable.make([{"k": "town", "t": "Town"}, {"k": "cars", "t": "Caravans", "num": true}, {"k": "gold", "t": "Coin out", "num": true},
		{"k": "out", "t": "Traded out", "num": true}], rows, "cars", false, [], false, 8, display_columns)

static func supply_table(scr, tids: Array, display_columns: Array = []) -> RecTable:
	var supply_rows := []
	for tid in tids:
		var st := RecData.stats(_e(tid))
		var tt := String(tid)
		var received := int(st.get("military_supply_in", 0))
		var sent := int(st.get("military_supply_out", 0))
		supply_rows.append({"town": RecData.tname(tid), "received": received, "sent": sent,
			"_l": RecData.tname(tid), "_r": "%d received" % received, "_d": "%d equipment sent (all time)." % sent,
			"_tap": func(): scr.open_town(tt)})
	return RecTable.make([{"k": "town", "t": "Town"}, {"k": "received", "t": "Received", "num": true},
		{"k": "sent", "t": "Sent", "num": true}], supply_rows, "town", true, [], true, 8, display_columns)
