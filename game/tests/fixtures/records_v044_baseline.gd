extends RefCounted

## Frozen delivered v0.043 baseline: exact class bodies with only lexical class-name substitution and nesting.

## Live RecData/simulation/civic helpers are unchanged dependencies. The six measured builders,

## deferred native callbacks, table rendering and kit construction use the frozen classes below.
## FrozenPages preserves the complete existing family-detail observation contract independently.
## The original six bodies retain live RecPages references; its exact delivered source is manifest-verified.

const COMMIT := "33265175d0274084aff69a47020059e9310ac63f"

const SOURCE_BLOBS := {"game/ui/rec_world.gd": "8ab0d1f479b08770174d7fc114e36bb4868f6ff7", "game/ui/rec_regions.gd": "cd125884826a346a9930b694e7da814f5772b1e8", "game/ui/rec_flows.gd": "95f3e8bf05a9ab70534a581ffb49d92f8b897254", "game/ui/rec_town.gd": "462a4ba2a0cb6c36369b492c91548595004c5d2d", "game/ui/rec_table.gd": "46b89f79507df9b1db6f666dccee9afb66f2b92c", "game/ui/rec_kit.gd": "ccb8f08444bf0ef0e514858fae3338b8ae240b4f", "game/ui/rec_pages.gd": "86a2f0f5cd7b87e0d69ed3e3932ac2e6cc29da95"}
const LIVE_PAGES_SHA256 := "3072cd201e4709b610229503e9a146569e76278811aaa5f13e1ae2027a9c3567"


static func build(scr, tids: Array, fid: String, tab: String) -> Control:
	return FrozenWorld.build(scr, tids, fid, tab)

static func town_build(scr, town: Dictionary, tab: String) -> Control:
	return FrozenTown.build(scr, town, tab)

class FrozenWorld:
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
		FrozenKit.line(v, "%d people; %d towns in view" % [_people(tids), tids.size()], "Small").add_theme_color_override("font_color", UiTheme.LIGHT)
		match tab:
			"Towns": FrozenRegions.towns(scr, tids, fid, v, towns_table(scr, tids), func(b): towns(scr, tids, fid, b))
			"Army": FrozenRegions.army(scr, fid, v, func(b): army(scr, fid, b))
			"Factions": FrozenRegions.factions(scr, tids, fid, v, factions_table(scr), func(b): factions(scr, tids, fid, b))
			"Rulers": FrozenRegions.rulers(scr, tids, v, rulers_table(scr, tids), func(b): rulers(scr, tids, b))
			"On the move": FrozenRegions.on_the_move(scr, tids, fid, v, move_table(scr, fid), func(b): on_the_move(scr, tids, fid, b))
			"Goods": FrozenFlows.goods(scr, tids, v, func(b): goods(scr, tids, b))
			"Food flows": FrozenFlows.food_flows(scr, tids, v, func(b): food_flows(scr, tids, b))
			"Fights": FrozenFlows.fights(scr, tids, fid, v, func(b): fights(scr, tids, fid, b))
			"Mines & land": FrozenFlows.mines_land(scr, tids, v, func(b): mines_land(scr, tids, b))
			"Merchants": FrozenFlows.merchants(scr, tids, v, func(b): merchants(scr, tids, b))
			"Census": census(scr, tids, v)
		FrozenKit.disclosure(v, "Scope totals", func(b):
			var wars: Array = Game.world.get("wars", [])
			if fid != "": wars = wars.filter(func(p): return String(p[0]) == fid or String(p[1]) == fid)
			FrozenKit.grid(b, ["Recorded scope", "Count"], [
				{"values": ["Towns", str(tids.size())]}, {"values": ["People", str(_people(tids))]},
				{"values": ["Pairs of factions at war", str(wars.size())]}, {"values": ["Forces on the map", str(_forces(fid).size())]}], [2, 1]))
		_pc.clear()
		return v
	
	static func census(scr, tids: Array, v: VBoxContainer) -> void:
		var world := FrozenFlows.read_world(tids)
		var balance := Census.balance_of(world, tids)
		var ok := Census.adds_up(balance)
		FrozenKit.metrics(v, [
			{"title": "People now", "value": str(int(balance["people"])), "note": "%d at last census" % int(balance["last"]), "color": UiTheme.BLUE},
			{"title": "Population change", "value": "%+d" % int(balance["change"]), "note": "Since last census", "color": UiTheme.COPPER},
			{"title": "Census balance", "value": "Adds up" if ok else "DOES NOT ADD UP", "note": "Recorded births, deaths and moves", "color": UiTheme.GOOD if ok else UiTheme.BAD}])
		FrozenKit.grid(v, ["Since last census", "People"], [
			{"values": ["Born", str(int(balance["births"]))]}, {"values": ["Died", str(int(balance["deaths"]))]},
			{"values": ["Arrived", str(int(balance["arrived"]))]}, {"values": ["Left", str(int(balance["left"]))]}], [2, 1])
		var table := FrozenTown.seasons_table(scr, world, tids)
		table.display_cells([{"k": "_l", "t": "Season", "w": 1.7}, {"k": "people", "t": "People"},
			{"k": "births", "t": "Born"}, {"k": "deaths", "t": "Died"}, {"k": "arrived", "t": "Arrived"}, {"k": "left", "t": "Left"}])
		FrozenKit.card(v, "Season records").add_child(table)
		var causes := Census.causes_of(world, tids)
		var rows := []
		for cause in Census.CAUSES:
			var cs := String(cause)
			var now := int(causes["now"].get(cs, 0))
			rows.append({"values": [cs.capitalize(), str(now), str(int(causes["last"].get(cs, 0))), FrozenKit.per_k(now, int(balance["people"]))],
				"tap": func(): scr.page("Died of %s" % cs, func(b): FrozenTown.dead_list(scr, Game.world, tids, cs, b))})
		FrozenKit.grid(v, ["Death cause", "This season", "Last season", "Per 1,000 people"], rows, [1.7, 1, 1, 1.3])
		FrozenKit.card(v, "More census records").add_child(UiKit.button("View census by race", func(): scr.page("Census by race", func(b): RecRaces.card(scr, tids, b)), "Row"))
		FrozenKit.disclosure(v, "Population charts, sickness and movements", func(b): FrozenTown.census_cards(scr, FrozenFlows.read_world(tids), tids, b))
	
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
		FrozenKit.line(v, "%s. %d towns, %d people; %d pairs of factions at war; %d forces on the map." % [Calendar.text(Game.day), tids.size(),
			_people(tids) if people < 0 else people, wars.size(), _forces(fid).size()], "Small")
	
	## v0.012: the faction's research house (campaign/academy.gd): its name and lead's title, know-how, budget, staff,
	## each research line; tap through to the house's business page.
	static func research_card(scr, fid: String, v: VBoxContainer) -> void:
		FrozenRegions.research(scr, fid, v)
	
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
		var hc := FrozenKit.card(v, "The towns")
		FrozenKit.kv(hc, "Towns, people", "%d, %d" % [tids.size(), _people(tids)])
		FrozenKit.kv(hc, "Average food days", FrozenKit.num(food_d / n))
		FrozenKit.kv(hc, "Short of food, starving", "%d, %d" % [short, starving])
		var cars := _forces(fid).filter(func(wb): return String(wb.get("kind", "")) == "caravan")
		FrozenKit.kv(hc, "Caravans on the road", "%d" % cars.size())
		var hfs := []
		for tid in tids:
			var hv: Variant = RecData.harvest_factor(_e(tid))
			if hv != null:
				hfs.append("%s x%.2f" % [String(_t(tid)["name"]), float(hv)])
		FrozenKit.kv(hc, "This year's harvest factor (weather, x1.00 = normal)", ", ".join(PackedStringArray(hfs)) if not hfs.is_empty() else FrozenKit.NT)
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
			_makes(e), int(info[2]), int(RecData.granary_days(e)), _m(RecData.treasury(e)), int(hard), mil, fi, di, mi, RecPages.open_cases(t), FrozenKit.NT]
	
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
		var sp := FrozenKit.card(box, "Asymmetry at a glance", "Readout only: the dearest and cheapest town for each.")
		for k in [["Food price index", 0], ["Copper bar price", 1], ["Wealth a person (purses + treasury + tills)", 2], ["Food days", 3],
				["Families in hardship %", 4]]:
			var hi := ""; var lo := ""; var hv := -INF; var lv := INF
			for tid in tids:
				var x := float(info[tid][int(k[1])])
				if x > hv: hv = x; hi = tid
				if x < lv: lv = x; lo = tid
			if hi != "":
				FrozenKit.kv(sp, String(k[0]), "%s in %s, %s in %s" % [FrozenKit.num(hv), RecData.tname(hi), FrozenKit.num(lv), RecData.tname(lo)])
		FrozenKit.nt(sp, "Arms price spread")
	
	# ================================================================== Factions
	static func factions(scr, _tids: Array, _fid: String, v: VBoxContainer) -> void:
		v.add_child(factions_table(scr))
	
	static func _faction_page(scr, fid: String, box: VBoxContainer) -> void:
		var w: Dictionary = Game.world
		box.add_child(FrozenKit.row("Open the faction view", "", "its towns, army and census", func(): scr.open_faction(fid)))
		research_card(scr, fid, box)
		var c := FrozenKit.card(box, "Relations")
		for o in w.get("factions", {}):
			if o == fid:
				continue
			FrozenKit.kv(c, UiWords.faction_name(String(o)), "%s, %d" % [String(Diplomacy.state(w, fid, String(o))).to_lower().replace("_", " "), int(round(Diplomacy.relation(w, fid, String(o))))])
		FrozenKit.nt(c, "Last change of each relation and its cause; war chest chart")
		var ac := FrozenKit.card(box, "Armies in the field")
		for wb in _forces(fid):
			if Army.is_field(wb):
				var wid := String(wb["id"])
				ac.add_child(FrozenKit.row(RecPages.force_name(wb), "%d men" % (wb["units"] as Array).size(), "near %s" % CampaignWorld.nearest_town_name(w, wb["pos"]), func(): scr.open_force(wid)))
	
	# ================================================================== Army (faction view)
	static func army(scr, fid: String, v: VBoxContainer) -> void:
		if fid == "":
			FrozenKit.line(v, "Pick a faction for its army.", "Muted")
			return
		var w: Dictionary = Game.world
		var fac: Dictionary = w["factions"].get(fid, {})
		var cul := Army.cul_of_faction(fid)
		var c := FrozenKit.card(v, "The army of %s" % UiWords.faction_name(fid))
		var bill := Army.bill(Game, fid)
		var dl := Army.days_of_pay(Game, fid)
		FrozenKit.kv(c, "Men under arms", "%d" % Army.members(Game, fid).size())
		FrozenKit.kv(c, "Wage bill", _m(bill) + " a day")
		FrozenKit.kv(c, "War chest", "%s (%s days of pay)" % [_m(float(fac.get("treasury", 0.0))), FrozenKit.num(dl) if dl < 1.0e9 else "-"])
		FrozenKit.kv(c, "Rank rule", String(cul.get("rank_rule", "")))
		var rc := FrozenKit.card(v, "Ranks", "The culture's rank names, counts against the caps, pay a day by rank.")
		for row in Army.tree_rows(FrozenRegions._army_read(), fid):
			var cap := int(row["cap"])
			var offs := []
			for u in row["officers"]:
				offs.append((u as Unit).name)
			FrozenKit.kv(rc, String(row["title"]).capitalize(), "%d%s, %s a day%s" % [int(row["count"]), (" of %d" % cap) if cap >= 0 else "",
				_m(Army.wage("army", int(row["rank"]))), (": " + ", ".join(PackedStringArray(offs))) if not offs.is_empty() else ""])
		var hc := FrozenKit.card(v, "Promotions and successions", "Newest first (the realm's own record).")
		var hist: Array = w.get("army", {}).get("f", {}).get(fid, {}).get("hist", [])
		if hist.is_empty():
			FrozenKit.line(hc, "Nothing yet.", "Muted")
		for i in range(hist.size() - 1, maxi(-1, hist.size() - 15), -1):
			FrozenKit.line(hc, String(hist[i]), "Small")
		var fc := FrozenKit.card(v, "Armies and their commanders")
		for wb in _forces(fid):
			if not Army.is_field(wb):
				continue
			var lead: Unit = null
			for u in wb["units"]:
				if not u.dead and (lead == null or u.rank > lead.rank):
					lead = u
			var wid := String(wb["id"])
			fc.add_child(FrozenKit.row(RecPages.force_name(wb), "%d men" % (wb["units"] as Array).size(),
				"led by %s %s" % [Army.rank_title(lead), lead.name] if lead != null else "no leader", func(): scr.open_force(wid)))
	
	# ================================================================== Rulers
	static func rulers(scr, tids: Array, v: VBoxContainer) -> void:
		var c := FrozenKit.card(v, "Rulers", "Heads as register persons with traits, and town rules rolled from them: not tracked yet (world spec 1, NEW SIM). What the sim has:")
		FrozenKit.nt(c, "Faction heads, traits, what each head cares most for, when the rules last changed")
		var ac := FrozenKit.card(v, "What each town asks", "Built from the live values (the same in every town until heads roll their own rules).")
		ac.add_child(rulers_table(scr, tids))
	static func on_the_move(scr, tids: Array, fid: String, v: VBoxContainer) -> void:
		var w: Dictionary = Game.world
		var gold := 0.0; var ncar := 0; var nfield := 0
		for wb in _forces(fid):
			if String(wb.get("kind", "")) == "caravan":
				ncar += 1; gold += float(wb.get("gold", 0.0))
			if Army.is_field(wb): nfield += 1
		var c := FrozenKit.card(v, "On the move")
		FrozenKit.kv(c, "Caravans on the road", "%d, carrying %s in coin" % [ncar, _m(gold)])
		FrozenKit.kv(c, "Armies in the field", "%d" % nfield)
		var ws: Dictionary = w.get("war", {}).get("stats", {})
		FrozenKit.kv(c, "Interceptions (since the world began)", "%d" % int(ws.get("intercepts", 0)))
		FrozenKit.kv(c, "Carriers", "wagons (caravans) only: no pack animals, porters or boats in the sim")
		for k in ["Robbed this season", "Worth of consignments", "Carriers going home empty", "Relief grain on the way", "Fetched by the buyer vs sent by the seller", "Arriving soonest (ETA)"]:
			FrozenKit.nt(c, k)
		v.add_child(move_table(scr, fid))
	
	# ================================================================== Goods
	static func goods(scr, tids: Array, v: VBoxContainer) -> void:
		var c := FrozenKit.card(v, "Goods by kind", "Market stock summed over the towns, days at today's demand, the price spread.")
		for cat in FrozenTown.CATS:
			var ck := String(cat[0])
			var goods_in := FrozenTown._goods_in(ck)
			var st := 0; var dem := 0.0
			for tid in tids:
				var totals := RecData.market_totals(_e(tid), goods_in)
				st += int(totals[0])
				dem += float(totals[1])
			c.add_child(FrozenKit.row(String(cat[1]), "%d" % st, "%s days" % (FrozenKit.num(st / dem) if dem > 0.0 else "-"),
				func(): scr.page(String(cat[1]), func(b): _cat_page(scr, tids, ck, b))))
		var hc := FrozenKit.card(v, "Herds by town", "Head counted in each town's herd records (every owner), fodder days left.")
		var tot := {}
		for tid in tids:
			var hs: Dictionary = RecData.herds(_e(tid))
			for k in hs: tot[k] = int(tot.get(k, 0)) + int(hs[k])
		FrozenKit.kv(hc, "All", FrozenTown.herd_text({}, tot))
		hc.add_child(herds_table(scr, tids))
		var dv := RecData.droves()
		if not dv.is_empty():
			var dc := FrozenKit.card(v, "Herds on the road", "Drovers walking beasts to a town that pays more.")
			for d in dv:
				if tids.has(String(d["from"])) or tids.has(String(d["to"])):
					FrozenKit.kv(dc, "%s to %s" % [RecData.tname(String(d["from"])), RecData.tname(String(d["to"]))], "%d %s" % [int(d["head"]), String(d["kind"])])
	
	static func _cat_page(scr, tids: Array, cat: String, box: VBoxContainer) -> void:
		for g in FrozenTown._goods_in(cat):
			var gg := String(g)
			var st := 0
			var lo := INF; var hi := -INF
			for tid in tids:
				st += RecData.stock(_e(tid), g)
				var p := RecData.price(_t(tid), g)
				lo = minf(lo, p); hi = maxf(hi, p)
			box.add_child(FrozenKit.row(Goods.good_name(g).capitalize(), "%d" % st, "price %s to %s" % [FrozenKit.num(lo), FrozenKit.num(hi)],
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
				"_d": "x%.2f base, stock %d, %s days, %s a week" % [p / RecData.base_price(g), st, FrozenKit.num(st / dem) if dem > 0.0 else "-",
					("%+d%%" % int(round(float(ch)))) if ch != null else "-"], "_tap": func(): scr.open_town(tt)})
		box.add_child(FrozenTable.make([{"k": "name", "t": "Town"}, {"k": "price", "t": "Price", "num": true}, {"k": "stock", "t": "Stock", "num": true},
			{"k": "days", "t": "Days", "num": true}, {"k": "chg", "t": "7-day %", "num": true}], rows, "price", true))
	
	# ================================================================== Food flows
	static func food_flows(scr, tids: Array, v: VBoxContainer) -> void:
		var w: Dictionary = Game.world
		var c := FrozenKit.card(v, "How the world feeds itself", "Towns by climate (latitude): food days in the market and the households' use.")
		for clim in (TownEcon.data()["climates"] as Dictionary).keys():   # (v0.012: the data's climates, "dry" too)
			var n := 0; var days := 0.0; var gran := 0
			for tid in tids:
				if String(_e(tid).get("climate", "")) == clim:
					n += 1; days += RecData.days_food(_t(tid)); gran += RecData.granary(_e(tid))
			if n > 0:
				FrozenKit.kv(c, "%s (%d towns)" % [String(clim).capitalize(), n], "%s food days on average, %d meals in the granaries" % [FrozenKit.num(days / n), gran])
		FrozenKit.nt(c, "Surplus and shortfall by food (grain, meat, fruit, beer, wine) per region")
		var fc := FrozenKit.card(v, "Food on the road now", "Caravans carrying food and drink, by direction.")
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
			fc.add_child(FrozenKit.row("%s -> %s" % [String(o.get("name", "?")), String(d.get("name", "?"))], "%d" % food, "%s; %s" % [way, Caravans.cargo_text(wb.get("cargo", {}))],
				func(): scr.open_force(wid)))
		if not any:
			FrozenKit.line(fc, "No food on the road.", "Muted")
		FrozenKit.nt(v, "The great food houses (merchant families shipping food) and relief grain sent to starving towns")
	
	# ================================================================== Fights
	static func fights(scr, tids: Array, fid: String, v: VBoxContainer) -> void:
		var w: Dictionary = Game.world
		var causes := Census.causes_of(FrozenFlows.read_world(tids), tids)
		var c := FrozenKit.card(v, "Fights", "Fight records of their own (both sides, the named dead, loot, what changed after): not tracked. What the sim keeps:")
		FrozenKit.kv(c, "Died fighting this season (people of these towns)", "%d (last season %d)" % [int(causes["now"].get("battle", 0)), int(causes["last"].get("battle", 0))])
		var ws: Dictionary = w.get("war", {}).get("stats", {})
		FrozenKit.kv(c, "War bands that ran their prey down / were beaten / gave up (since the world began)", "%d / %d / %d" % [int(ws.get("caught", 0)), int(ws.get("beaten", 0)), int(ws.get("gave_up", 0))])
		for k in ["Fights seen vs resolved out of sight vs called off", "Wounded, maimed, died of wounds later, fled", "Taken prisoner", "Coming up (fights set by the AI)"]:
			FrozenKit.nt(c, k)
		c.add_child(FrozenKit.row("The dead in battle", "", "name, age, family, the fight", func(): scr.page("Died in battle", func(b): FrozenTown.dead_list(scr, w, tids, "battle", b))))
		v.add_child(UiKit.button("View legendary arms", func(): scr.page("Legendary arms", func(b): legends_card(scr, b)), "Row"))
		var lc := FrozenKit.card(v, "The world's log", "Newest first%s." % ("" if fid == "" else ", lines naming %s or its towns" % UiWords.faction_name(fid)))
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
				FrozenKit.line(lc, line, "Small")
				n += 1
				if n >= 40:
					break
		if n == 0:
			FrozenKit.line(lc, "Nothing on the log.", "Muted")
	
	## v0.014: every legendary piece in the world, each with its own page (gem, maker, kills, every change of hands).
	static func legends_card(scr, v: VBoxContainer) -> void:
		var lc := FrozenKit.card(v, "Legendary arms", "Unique pieces made by real smiths in an inspired hour; never lost in battle.")
		var all := Legends.all_held(Game)
		if all.is_empty():
			FrozenKit.line(lc, "None made yet.", "Muted")
		for row in all:
			var it: Item = row[0]
			var where := String(row[1])
			lc.add_child(FrozenKit.row(it.display_name(), "%d kills" % int(it.legend.get("k", 0)), where, func(): scr.page(String(it.legend.get("nm", "?")), func(b): legend_page(it, where, b))))
	
	static func legend_page(it: Item, where: String, box: VBoxContainer) -> void:
		var c := FrozenKit.card(box, it.display_name())
		FrozenKit.kv(c, "Now", where)
		FrozenKit.kv(c, "Worth", _m(float(it.value())))
		FrozenKit.kv(c, "Gem", "%s, in its %s" % [it.gem_name(), String(it.legend.get("at", "?"))])
		var hc := FrozenKit.card(box, "Its story", "Maker, kills and every change of hands, oldest first.")
		for line in it.legend_lines().slice(1):
			FrozenKit.line(hc, String(line), "Small")
	
	# ================================================================== Mines & land
	static func mines_land(scr, tids: Array, v: VBoxContainer) -> void:
		var mc := FrozenKit.card(v, "Ore deposits")
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
		var lc := FrozenKit.card(box, "The land")
		FrozenKit.kv(lc, "Acres", "%d held by families, %d by the towns" % [fam, est])
		for k in crops:
			FrozenKit.kv(lc, String(k).capitalize(), "%d acres" % int(crops[k]))
		for k in herds:
			FrozenKit.kv(lc, String(k).capitalize(), "%d head" % int(herds[k]))
		FrozenKit.nt(lc, "Pasture, woodland, and woodland cut vs regrown each season")
	
	# ================================================================== Merchants
	static func merchants(scr, tids: Array, v: VBoxContainer) -> void:
		var c := FrozenKit.card(v, "Merchants", "Merchant families owning caravans: not tracked (each town's merchants trade on the treasury's purse). By town:")
		c.add_child(merchants_table(scr, tids))
		var ac := FrozenKit.card(v, "Garrison supply", "Own-faction armouries distribute real surplus every ten days; reserves are 2.5 times supported troop equipment beyond issued kit.")
		ac.add_child(supply_table(scr, tids))
	
	# Original live table sources; presentation never duplicates these rows.
	static func towns_table(scr, tids: Array) -> FrozenTable:
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
		return FrozenTable.make([{"k": "name", "t": "Town"}, {"k": "faction", "t": "Faction"}, {"k": "people", "t": "People", "num": true},
			{"k": "food", "t": "Food days", "num": true}, {"k": "gran", "t": "Granary", "num": true}, {"k": "tre", "t": "Treasury", "num": true},
			{"k": "hard", "t": "Hardship", "num": true}, {"k": "mil", "t": "Militia", "num": true}, {"k": "fi", "t": "Food x", "num": true},
			{"k": "di", "t": "Drink x", "num": true}, {"k": "mi", "t": "Metal x", "num": true}], rows, "name", true, [], true)
	
	static func factions_table(scr) -> FrozenTable:
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
					_m(bill), FrozenKit.num(dl) if dl < 1.0e9 else "-", ", ".join(PackedStringArray(war)) if not war.is_empty() else "nobody",
					", ".join(PackedStringArray(ally)) if not ally.is_empty() else "nobody", float(fac.get("pl", 1.0)),
					("x%.2f" % float(RecData.money_index(ff))) if RecData.money_index(ff) != null else FrozenKit.NT, FrozenKit.NT],
				"_col": UiTheme.BAD if not war.is_empty() else UiTheme.INK, "_s": UiWords.faction_name(ff),
				"_tap": func(): scr.page(UiWords.faction_name(ff), func(b): _faction_page(scr, ff, b))})
		return FrozenTable.make([{"k": "name", "t": "Faction"}, {"k": "towns", "t": "Towns", "num": true}, {"k": "people", "t": "People", "num": true},
			{"k": "tre", "t": "Treasury", "num": true}, {"k": "bill", "t": "Army pay", "num": true}, {"k": "days", "t": "Days of pay", "num": true},
			{"k": "men", "t": "Soldiers", "num": true}, {"k": "kh", "t": "Steel %", "num": true}], rows, "name", true)
	
	static func rulers_table(scr, tids: Array) -> FrozenTable:
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
				"_d": asks + " Labour duty, levies, relief rules: " + FrozenKit.NT, "_s": String(t["name"]) + " " + String(hd.get("name", "")),
				"_tap": func(): scr.open_family(tt, hf)})
		return FrozenTable.make([{"k": "name", "t": "Town"}, {"k": "head", "t": "Head"}, {"k": "people", "t": "People", "num": true},
			{"k": "gran", "t": "Granary days", "num": true}], rows, "name", true, [], true)
	
	# ================================================================== On the move
	
	static func move_table(scr, fid: String) -> FrozenTable:
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
					Caravans.cargo_text(wb.get("cargo", {}), float(wb.get("gold", 0.0))) if kind == "caravan" else "strength %s" % FrozenKit.num(CampaignWorld.band_power(units)),
					TownEcon.supply_word(TownEcon.force_supply(w, wb)), WarAI.mode_text(wb) if wb.has("mode") else String(wb.get("state", ""))],
				"_s": force_name, "_tap": func(): scr.open_force(wid)})
		return FrozenTable.make([{"k": "kind", "t": "Kind"}, {"k": "faction", "t": "Owner"}, {"k": "men", "t": "Men", "num": true}, {"k": "near", "t": "Near"}],
			rows, "kind", true, [{"t": "Kind", "opts": kinds, "fn": func(r, o): return r["kind"] == o},
			{"t": "Owner", "opts": facs, "fn": func(r, o): return r["faction"] == o}], true, 6)
	
	static func herds_table(scr, tids: Array, prepared: Dictionary = {}, structured: bool = false) -> FrozenTable:
		var herd_rows := []
		for tid in tids:
			var e2 := _e(tid)
			var tt := String(tid)
			var values: Dictionary = prepared.get(tt, {})
			var hs: Dictionary = values["herds"] if values.has("herds") else RecData.herds(e2)
			var fd: Variant = values["fodder"] if values.has("fodder") else RecData.fodder_days(e2)
			var row := {"tid": tt, "town": RecData.tname(tid), "_l": RecData.tname(tid),
				"_d": func(): return FrozenTown.herd_text(e2, hs) + ((" (fodder %d days)" % int(float(fd))) if fd != null else ""),
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
				{"k": "fodder", "t": "Fodder days", "format": FrozenFlows._number}]
		return FrozenTable.make(columns, herd_rows, "town", true, [], true, 8, lanes)
	
	static func mines_table(scr, tids: Array) -> FrozenTable:
		var rows := []
		for tid in tids:
			var e := _e(tid)
			var t := _t(tid)
			for ore in e.get("deposits", {}):
				var mine := {}
				for b in RecData.biz(e):
					if String(b["type"]) == "mine" and String(b.get("ore", "copper_ore")) == String(ore) and not b.get("closed", false):
						mine = b
				var tt := t
				var bid := int(mine.get("id", -1))
				rows.append({"town": String(t["name"]), "ore": Goods.good_name(String(ore)), "rich": float(e["deposits"][ore]), "workers": int(mine.get("workers", 0)),
					"_l": "%s: %s" % [String(t["name"]), Goods.good_name(String(ore))], "_r": "richness %.2f" % float(e["deposits"][ore]),
					"_d": ("%s, %d of %d at work; output a day: %s" % [RecData.biz_title(e, mine), int(mine["workers"]), int(mine["cap"]), FrozenKit.NT]) if not mine.is_empty() else "no mine working it",
					"_tap": (func(): scr.page(RecData.biz_title(RecData.econ(tt), RecData.biz(RecData.econ(tt))[bid]).capitalize(), func(b): RecPages.business(scr, tt, bid, b))) if bid >= 0 else Callable()})
		return FrozenTable.make([{"k": "town", "t": "Town"}, {"k": "ore", "t": "Ore"}, {"k": "rich", "t": "Richness", "num": true},
			{"k": "workers", "t": "Miners", "num": true}], rows, "town", true)
	
	static func merchants_table(scr, tids: Array) -> FrozenTable:
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
					_m(float(st.get("trade_in", 0.0))), FrozenKit.NT], "_tap": func(): scr.open_town(tt)})
		return FrozenTable.make([{"k": "town", "t": "Town"}, {"k": "cars", "t": "Caravans", "num": true}, {"k": "gold", "t": "Coin out", "num": true},
			{"k": "out", "t": "Traded out", "num": true}], rows, "cars", false, [], false, 8)
	
	static func supply_table(scr, tids: Array) -> FrozenTable:
		var supply_rows := []
		for tid in tids:
			var st := RecData.stats(_e(tid))
			var tt := String(tid)
			var received := int(st.get("military_supply_in", 0))
			var sent := int(st.get("military_supply_out", 0))
			supply_rows.append({"town": RecData.tname(tid), "received": received, "sent": sent,
				"_l": RecData.tname(tid), "_r": "%d received" % received, "_d": "%d equipment sent (all time)." % sent,
				"_tap": func(): scr.open_town(tt)})
		return FrozenTable.make([{"k": "town", "t": "Town"}, {"k": "received", "t": "Received", "num": true},
			{"k": "sent", "t": "Sent", "num": true}], supply_rows, "town", true, [], true, 8)

class FrozenRegions:
	extends RefCounted
	## World/faction presentation over FrozenWorld's original live tables. Row dictionaries,
	## sort keys, lazy values, filters and tap callbacks stay owned by that source.
	## legacy is the unchanged account renderer, built only when its disclosure opens.
	
	class ArmyRead:
		extends RefCounted
		var world: Dictionary
	
	static func _money(value: Variant) -> String:
		return FrozenKit.NT if value == null else RecData.money(float(value))
	
	static func _number(value: Variant) -> String:
		return FrozenKit.NT if value == null else FrozenKit.num(float(value))
	
	static func _sum(rows: Array, key: String) -> float:
		var total := 0.0
		for row: Dictionary in rows:
			var value: Variant = row.get(key)
			if value is Callable: value = (value as Callable).call()
			if value != null: total += float(value)
		return total
	
	static func _table(v: VBoxContainer, title: String, table: FrozenTable, columns: Array) -> void:
		table.display_cells(columns)
		FrozenKit.card(v, title).add_child(table)
	
	static func _details(v: VBoxContainer, title: String, legacy: Callable) -> void:
		if legacy.is_valid(): FrozenKit.disclosure(v, title, legacy)
	
	static func towns(scr, tids: Array, fid: String, v: VBoxContainer, table: FrozenTable, legacy: Callable) -> void:
		var short := 0
		var starving := 0
		for i in mini(tids.size(), table.rows.size()):
			var town := RecData.town(String(tids[i]))
			var level := TownEcon.supply_level(town, float(table.rows[i]["food"]))
			if level == "short": short += 1
			elif level == "starving": starving += 1
		FrozenKit.metrics(v, [
			{"title": "Towns", "value": str(table.rows.size()), "note": "%d people" % int(_sum(table.rows, "people")), "color": UiTheme.BLUE},
			{"title": "Average food days", "value": _number(_sum(table.rows, "food") / float(table.rows.size())) if not table.rows.is_empty() else "-", "note": "Unweighted town average", "color": UiTheme.COPPER},
			{"title": "Short / starving", "value": "%d / %d" % [short, starving], "note": "Current town supply status", "color": UiTheme.BAD if starving > 0 else (UiTheme.WARN if short > 0 else UiTheme.GOOD)}])
		_table(v, "Towns", table, [
			{"k": "name", "t": "Town", "w": 1.7}, {"k": "faction", "t": "Realm", "w": 1.6},
			{"k": "people", "t": "People", "w": 0.8}, {"k": "food", "t": "Food days", "w": 0.8},
			{"k": "tre", "t": "Town chest", "w": 1.1, "format": _money}])
		v.add_child(UiKit.button("View town price and wealth spreads", func(): scr.page("Asymmetry at a glance", func(box): FrozenWorld._town_spreads(tids, box)), "Row"))
		if fid != "": research(scr, fid, v)
		_details(v, "Town accounts, harvests and price comparisons", legacy)
	
	static func factions(scr, _tids: Array, _fid: String, v: VBoxContainer, table: FrozenTable, legacy: Callable) -> void:
		FrozenKit.metrics(v, [
			{"title": "Factions", "value": str(table.rows.size()), "note": "All recorded factions", "color": UiTheme.BLUE},
			{"title": "People in their towns", "value": str(int(_sum(table.rows, "people"))), "note": "%d towns with an economy" % int(_sum(table.rows, "towns")), "color": UiTheme.COPPER},
			{"title": "Field soldiers", "value": str(int(_sum(table.rows, "men"))), "note": "%s total daily army bill" % _money(_sum(table.rows, "bill")), "color": UiTheme.BLUE}])
		_table(v, "Faction accounts", table, [
			{"k": "name", "t": "Faction", "w": 2.0}, {"k": "towns", "t": "Towns", "w": 0.65},
			{"k": "people", "t": "People", "w": 0.9}, {"k": "tre", "t": "War chest", "w": 1.15, "format": _money},
			{"k": "days", "t": "Pay days", "w": 0.85, "format": _number}])
		_details(v, "Diplomacy, pay and retained knowledge accounts", legacy)
	
	static func rulers(_scr, _tids: Array, v: VBoxContainer, table: FrozenTable, legacy: Callable) -> void:
		FrozenKit.metrics(v, [
			{"title": "Town heads", "value": str(table.rows.size()), "note": "Recorded town leadership", "color": UiTheme.BLUE},
			{"title": "People governed", "value": str(int(_sum(table.rows, "people"))), "color": UiTheme.COPPER},
			{"title": "Faction heads & traits", "value": FrozenKit.NT, "note": "Town-head household links remain available", "color": UiTheme.BLUE}])
		_table(v, "Town heads and rules", table, [
			{"k": "name", "t": "Town", "w": 1.5}, {"k": "head", "t": "Recorded head", "w": 2.0},
			{"k": "people", "t": "People", "w": 0.8}, {"k": "gran", "t": "Granary days", "w": 1.0}])
		_details(v, "Taxes, loan rates and unrecorded rules", legacy)
	
	static func on_the_move(_scr, _tids: Array, fid: String, v: VBoxContainer, table: FrozenTable, legacy: Callable) -> void:
		var caravans := 0
		var fields := 0
		var gold := 0.0
		for force: Dictionary in FrozenWorld._forces(fid):
			if String(force.get("kind", "")) == "caravan":
				caravans += 1
				gold += float(force.get("gold", 0.0))
			if Army.is_field(force): fields += 1
		FrozenKit.metrics(v, [
			{"title": "Caravans on the road", "value": str(caravans), "note": "%s carried in coin" % _money(gold), "color": UiTheme.COPPER},
			{"title": "Field armies", "value": str(fields), "note": "%d forces in this view" % table.rows.size(), "color": UiTheme.BLUE},
			{"title": "Interceptions", "value": str(int(Game.world.get("war", {}).get("stats", {}).get("intercepts", 0))), "note": "Whole world, since it began", "color": UiTheme.WARN}])
		_table(v, "Forces on the map", table, [
			{"k": "_l", "t": "Force", "w": 1.65}, {"k": "kind", "t": "Kind", "w": 0.8},
			{"k": "faction", "t": "Owner", "w": 1.45}, {"k": "men", "t": "Living members", "w": 0.8},
			{"k": "near", "t": "Near", "w": 1.4}])
		_details(v, "Cargo, routes, supply and movement accounts", legacy)
	
	## Army.tree_rows calls Army.rec on legacy saves; isolate only those containers.
	static func _army_read() -> ArmyRead:
		var view := ArmyRead.new()
		view.world = Game.world.duplicate()
		var army: Dictionary = Game.world.get("army", {}).duplicate()
		army["f"] = (army.get("f", {}) as Dictionary).duplicate()
		view.world["army"] = army
		return view
	
	static func army(scr, fid: String, v: VBoxContainer, legacy: Callable) -> void:
		if fid == "":
			FrozenKit.line(FrozenKit.card(v, "Army"), "Pick a faction for its army.", "Muted")
			return
		var faction: Dictionary = Game.world.get("factions", {}).get(fid, {})
		var bill := Army.bill(Game, fid)
		var days := Army.days_of_pay(Game, fid)
		var members := Army.members(Game, fid)
		FrozenKit.metrics(v, [
			{"title": "Living field soldiers", "value": str(members.size()), "color": UiTheme.BLUE},
			{"title": "Army bill / day", "value": _money(bill), "color": UiTheme.COPPER},
			{"title": "War chest", "value": _money(float(faction.get("treasury", 0.0))), "note": ("%s days of pay" % _number(days)) if days < 1.0e9 else "No current wage bill", "color": UiTheme.WARN if days < 1.0 else UiTheme.BLUE}])
		var ranks := []
		for rank: Dictionary in Army.tree_rows(_army_read(), fid):
			var cap := int(rank["cap"])
			ranks.append({"values": [String(rank["title"]).capitalize(), str(int(rank["count"])), str(cap) if cap >= 0 else "No cap", _money(Army.wage("army", int(rank["rank"])))]})
		FrozenKit.grid(v, ["Rank", "Serving", "Cap", "Rate / day"], ranks, [2, 1, 1, 1.4])
		var rows := []
		for force: Dictionary in FrozenWorld._forces(fid):
			if not Army.is_field(force): continue
			var lead: Unit = null
			for unit: Unit in force["units"]:
				if not unit.dead and (lead == null or unit.rank > lead.rank): lead = unit
			var wid := String(force["id"])
			rows.append({"name": RecPages.force_name(force), "men": (force["units"] as Array).size(), "commander": "%s %s" % [Army.rank_title(lead), lead.name] if lead != null else "No leader",
				"_l": RecPages.force_name(force), "_r": "%d men" % (force["units"] as Array).size(), "_s": RecPages.force_name(force),
				"_d": "Recorded force roster; commander is its highest-ranking living member.", "_tap": func(): scr.open_force(wid)})
		var table := FrozenTable.make([{"k": "name", "t": "Army"}, {"k": "men", "t": "Roster", "num": true}, {"k": "commander", "t": "Commander"}], rows, "name", true, [], true, 8)
		_table(v, "Armies and their commanders", table, [{"k": "name", "t": "Army", "w": 1.6}, {"k": "men", "t": "Recorded roster", "w": 0.8}, {"k": "commander", "t": "Commander", "w": 2.0}])
		_details(v, "Rank rules, officers and promotions", legacy)
	
	## The owned capital house is a recorded snapshot, not activity inferred from budget.
	static func research(scr, fid: String, v: VBoxContainer) -> void:
		var report := Academy.report(Game.world, fid)
		var state := TownResearchTab.house_state(report)
		var card := FrozenKit.card(v, "Research - %s" % String(report.get("name", "Research house")))
		var capital: Dictionary = {"faction": fid}
		if not bool(report.get("has", false)):
			FrozenKit.line(card, String(state["text"]), "Muted")
		else:
			var tid := String(report["tid"])
			capital = RecData.town(tid)
			var bid := int(report["bid"])
			var lead := String(report.get("lead", ""))
			FrozenKit.grid(card, ["Location", String(report.get("title", "Head")), "Recorded work"], [
				{"values": [String(report.get("town", "")), lead if lead != "" else "Post vacant", String(state["text"])], "color": state["color"], "tap": func():
					var live := Academy.report(Game.world, fid)
					if bool(live.get("has", false)) and String(live.get("tid", "")) == tid and int(live.get("bid", -1)) == bid:
						scr.open_business(RecData.town(tid), bid)}], [1.4, 1.8, 1.8])
		var rows := []
		for line: Dictionary in report.get("lines", []):
			var status := TownResearchTab.line_state(report, line)
			rows.append({"values": [String(line["name"]).capitalize(), String(status["text"]), "%.1f%%" % float(line.get("kh", 0.0)), "%.1f" % float(line.get("pts", 0.0))], "color": status["color"]})
		FrozenKit.grid(card, ["Research line", "Status", "Know-how", "Saved points"], rows, [1.3, 1.7, 0.8, 0.8])
		FrozenKit.disclosure(card, "Research funding, allocations, history and people", func(content):
			_research_account(scr, capital, fid, report, content)
			FrozenKit.grid(content, ["Recorded research account", "Value"], [
				{"values": ["State interest", "%.1f%%" % (100.0 * float(report.get("interest", 0.0)))]},
				{"values": ["Supporting staff skill", "%.1f / 15" % float(report.get("skill", 0.0)) if bool(report.get("has", false)) else FrozenKit.NT]},
				{"values": ["Steel pieces in its towns", str(int(report.get("met", 0)))]}], [2, 1])
			var rules := []
			for line: Dictionary in report.get("lines", []):
				var quality := int(line.get("best_q", -1))
				var limit := "No steel" if quality < 0 else ("Ordinary" if quality == 0 else String(DB.QUALITY_NAMES[clampi(quality, 0, DB.QUALITY_NAMES.size() - 1)]).capitalize()) + " at best"
				if not bool(line.get("caps", true)):
					limit = "May smelt and work %s" % String(line["name"]) if float(line.get("kh", 0.0)) > 0.0 else "Cannot smelt or work; bought, looted and repaired pieces are used"
				rules.append({"values": [String(line["name"]).capitalize(), "x%s" % FrozenKit.num(float(line.get("factor", 1.0))) if bool(line.get("open", false)) else "Unavailable", limit]})
			FrozenKit.grid(content, ["Line", "Learning factor", "Recorded use / quality limit"], rules, [1.2, 1, 2.8]))
	
	## Records uses flexible cells; the town report's fixed funding/header rows do not
	## fit inside an expanded Records card on a narrow window. Read the same snapshot.
	static func _research_account(scr, capital: Dictionary, fid: String, report: Dictionary, content: VBoxContainer) -> void:
		if bool(report.get("has", false)):
			var lead := String(report.get("lead", ""))
			var till := float(report.get("till", 0.0))
			FrozenKit.metrics(content, [
				{"title": String(report.get("title", "Head")), "value": lead if lead != "" else "Post vacant", "note": "Skill %.1f / 15" % float(report.get("lskill", 0.0)) if lead != "" else "Awaiting appointment", "color": UiTheme.BLUE if lead != "" else UiTheme.WARN},
				{"title": "Supporting staff", "value": str(int(report.get("staff", 0))), "note": "%d / %d paid places; includes the head" % [int(report.get("workers", 0)), int(report.get("cap", 0))], "color": UiTheme.BLUE},
				{"title": "Cash in till", "value": "%.1f coins" % till, "note": "Wages and materials", "color": UiTheme.BLUE if till > 0.0 else UiTheme.WARN}])
			var live := TownResearchTab._live_head(capital, report, fid)
			if not live.is_empty():
				var person: Array = live["lead"].duplicate()
				content.add_child(UiKit.button("%s's household" % lead, func():
					var current := TownResearchTab._live_head(capital, report, fid)
					if not current.is_empty() and current["lead"] == person:
						scr.open_family(current["capital"], int(person[0])), "Row"))
		var funding_day := int(report.get("funding_day", -1))
		var transfer_date := "Day %d" % (funding_day + 1) if funding_day >= 0 else "date not recorded"
		var history: Array = report.get("hist", [])
		var account := [
			{"values": ["Planned state budget", "%.1f coins/day" % float(report.get("budget", 0.0))]},
			{"values": ["Last state transfer", "%.1f coins (%s)" % [float(report.get("paid", 0.0)), transfer_date]]},
			{"values": ["Current week output", "%.1f research points" % float(report.get("current_week_output", 0.0))]},
			{"values": ["Last completed week", "No completed week recorded" if history.is_empty() else "%.1f research points" % float(report.get("last_week_output", history[-1][1]))]}]
		if bool(report.get("has", false)):
			account.append({"values": ["Staff offer", "%.1f coins/day" % float(report.get("wage", 0.0))]})
			account.append({"values": ["Head's nominal rate", "%.1f coins/day including the supplement" % float(report.get("lead_wage", 0.0))]})
		FrozenKit.grid(content, ["Funding and actual output", "Recorded value"], account, [1.4, 2])
		var allocations := []
		for line: Dictionary in report.get("lines", []):
			var share := "%.1f%%" % (100.0 * float(line.get("share", 0.0))) if bool(line.get("active", false)) else "-"
			allocations.append({"values": [String(line["name"]).capitalize(), share, "%.1f" % float(line.get("budget_on", 0.0)), "%.2f" % float(line.get("staff_on", 0.0))]})
		FrozenKit.grid(content, ["Line", "Planned share", "Coins/day", "Staff allocation"], allocations, [1.4, 1, 1, 1.2])
		FrozenKit.disclosure(content, "How to read the accounts", func(box):
			for text in [
				"Supporting staff excludes the head; paid places include the head.",
				"Know-how includes starting knowledge. Saved points may accumulate before know-how rises.",
				"House activity is the last recorded production state. Planned shares, coins and staff are allocations, not measured per-line output.",
				"A zero transfer can leave a funded till. Output covers all lines together; per-line speed and completion dates are not tracked."]:
				FrozenKit.line(box, text, "Small"))
		var weeks := []
		for entry in history:
			weeks.append({"values": ["Day %d" % (int(entry[0]) + 1), "%.1f" % float(entry[1])]})
		if weeks.is_empty(): FrozenKit.line(content, "No completed weeks recorded.", "Muted")
		else: FrozenKit.grid(content, ["Completed week, oldest first", "Research points"], weeks, [1.6, 1])
		var events := []
		for entry in report.get("log", []):
			var text := String(entry)
			events.append({"values": [text], "tap": func(): scr.page("Research event", func(box): FrozenKit.line(box, text))})
		if events.is_empty(): FrozenKit.line(content, "No research events recorded.", "Muted")
		else: FrozenKit.grid(content, ["Log book, oldest first"], events)

class FrozenFlows:
	extends RefCounted
	## Compact presentation of the existing world/faction trade and history records.
	## Original FrozenWorld tables provide their rows, sorts, filters and identity links.
	
	static func _m(value: Variant) -> String:
		return RecData.money(float(value))
	
	static func _number(value: Variant) -> String:
		return FrozenKit.num(float(value)) if value != null else "-"
	
	## Reader helpers may initialize missing legacy books; isolate only those reads.
	## Navigation still receives the actual town, force, person and item identities.
	static func read_world(tids: Array) -> Dictionary:
		var world := Game.world.duplicate()
		var towns: Dictionary = Game.world.get("towns", {}).duplicate()
		for tid in tids:
			var town := RecData.town(String(tid))
			if TownEcon.has_econ(town): towns[tid] = RecCivic._read_town(town, town["econ"])
		world["towns"] = towns
		return world
	
	static func goods(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
		var categories := []
		var market_units := 0
		var grouped := {}
		for cat in FrozenTown.CATS: grouped[String(cat[0])] = []
		var goods_data: Dictionary = TownEcon.data()["goods"]
		for good in Goods.ids():
			var category := String(goods_data.get(good, {}).get("cat", ""))
			if grouped.has(category): (grouped[category] as Array).append(good)
		for cat in FrozenTown.CATS:
			var key := String(cat[0])
			var title := String(cat[1])
			var goods_in: Array = grouped[key]
			var stock := 0; var demand := 0.0
			for tid in tids:
				var totals := RecData.market_totals(FrozenWorld._e(tid), goods_in)
				stock += int(totals[0]); demand += float(totals[1])
			market_units += stock
			categories.append({"values": [title, {"text": str(stock), "color": UiTheme.BLUE},
				{"text": FrozenKit.num(stock / demand) if demand > 0.0 else "-", "color": UiTheme.COPPER}],
				"tap": func(): scr.page(title, func(box): _category(scr, tids, key, box))})
		var herds := {}; var heads := 0; var prepared := {}
		for tid in tids:
			var economy := FrozenWorld._e(tid)
			var town_herds := RecData.herds(economy)
			var town_total := 0
			for kind in town_herds:
				var n := int(town_herds[kind])
				herds[kind] = int(herds.get(kind, 0)) + n; heads += n
				town_total += n
			prepared[String(tid)] = {"herds": town_herds, "head": town_total, "fodder": RecData.fodder_days(economy)}
		FrozenKit.metrics(v, [
			{"title": "Towns covered", "value": str(tids.size()), "color": UiTheme.BLUE},
			{"title": "Market stock units", "value": str(market_units), "note": "Across the listed goods categories", "color": UiTheme.COPPER},
			{"title": "Animals in town herds", "value": str(heads), "note": "Every recorded owner", "color": UiTheme.BLUE}])
		var card := FrozenKit.card(v, "Goods by kind", "Market stock and days at recorded demand. Select a kind for goods and price spreads.")
		FrozenKit.grid(card, ["Kind", "Stock units", "Market days"], categories, [2.0, 1.0, 1.0])
		# These values belong only to this synchronous build. Detail pages and
		# disclosures still perform fresh reads when opened.
		var table := FrozenWorld.herds_table(scr, tids, prepared, true)
		FrozenKit.card(v, "Herds by town", "Select a town for its animals and owners.").add_child(table)
		FrozenKit.disclosure(v, "Head by animal", func(box):
			var rows := []
			var keys: Array = herds.keys(); keys.sort()
			for key in keys: rows.append({"values": [RecData.herd_word({}, key).capitalize(), str(int(herds[key]))]})
			FrozenKit.grid(box, ["Animal", "Head"], rows, [2, 1]))
		FrozenKit.disclosure(v, "Full goods record and drovers on the road", legacy)
	
	static func _category(scr, tids: Array, category: String, v: VBoxContainer) -> void:
		var card := FrozenKit.card(v, "Goods and buying prices", "Stock summed over these towns; lowest and highest current price.")
		var rows := []
		for good in FrozenTown._goods_in(category):
			var key := String(good)
			var stock := 0; var low := INF; var high := -INF
			for tid in tids:
				stock += RecData.stock(FrozenWorld._e(tid), key)
				var price := RecData.price(FrozenWorld._t(tid), key)
				low = minf(low, price); high = maxf(high, price)
			rows.append({"values": [Goods.good_name(key).capitalize(), str(stock), _number(low), _number(high)],
				"tap": func(): scr.page(Goods.good_name(key).capitalize(), func(box): _good_towns(scr, tids, key, box))})
		FrozenKit.grid(card, ["Good", "Stock", "Low coins", "High coins"], rows, [2.2, 0.8, 1, 1])
	
	static func _good_towns(scr, tids: Array, good: String, v: VBoxContainer) -> void:
		var box := FrozenKit.card(v, "Price and stock by town")
		FrozenWorld._good_towns(scr, tids, good, box)
		for child in box.get_children():
			if child is FrozenTable:
				child.display_cells([{"k": "name", "t": "Town", "w": 2.0}, {"k": "price", "t": "Coins", "format": _m},
					{"k": "stock", "t": "Stock"}, {"k": "days", "t": "Days", "format": _number},
					{"k": "chg", "t": "7-day %", "format": func(value): return "%+d%%" % int(round(float(value))) if value != null else "-"}])
	
	static func _food_caravans(tids: Array) -> Array:
		var rows := []
		for band: Dictionary in FrozenWorld._forces(""):
			if String(band.get("kind", "")) != "caravan": continue
			var cargo: Dictionary = band.get("cargo", {}).get("goods", {})
			var food := 0
			for good in ["grain", "fruit", "meat", "beer", "wine"]: food += int(cargo.get(good, 0))
			if food <= 0: continue
			var origin := String(band.get("origin", "")); var destination := String(band.get("dest", ""))
			if not tids.has(origin) and not tids.has(destination): continue
			var start := FrozenWorld._t(origin); var end := FrozenWorld._t(destination)
			var direction := "-"
			if not start.is_empty() and not end.is_empty():
				var delta: Vector2 = (end["pos"] as Vector2) - (start["pos"] as Vector2)
				direction = ("north" if delta.y < 0 else "south") if absf(delta.y) > absf(delta.x) else ("west" if delta.x < 0 else "east")
			rows.append({"band": band, "origin": String(start.get("name", "?")), "destination": String(end.get("name", "?")), "food": food, "direction": direction})
		return rows
	
	static func food_flows(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
		var climate_rows := []; var days_sum := 0.0; var granary := 0
		for tid in tids:
			days_sum += RecData.days_food(FrozenWorld._t(tid)); granary += RecData.granary(FrozenWorld._e(tid))
		for climate in (TownEcon.data()["climates"] as Dictionary).keys():
			var n := 0; var days := 0.0; var grain := 0
			for tid in tids:
				if String(FrozenWorld._e(tid).get("climate", "")) == climate:
					n += 1; days += RecData.days_food(FrozenWorld._t(tid)); grain += RecData.granary(FrozenWorld._e(tid))
			if n > 0:
				climate_rows.append({"values": [String(climate).capitalize(), str(n), {"text": FrozenKit.num(days / n), "color": UiTheme.COPPER}, str(grain)]})
		var caravans := _food_caravans(tids)
		var cargo_units := 0
		for route: Dictionary in caravans: cargo_units += int(route["food"])
		FrozenKit.metrics(v, [
			{"title": "Food days / town", "value": FrozenKit.num(days_sum / tids.size()) if not tids.is_empty() else "-", "note": "Average of the towns' supply days", "color": UiTheme.COPPER},
			{"title": "Public granaries", "value": str(granary), "note": "Food equivalents stored", "color": UiTheme.BLUE},
			{"title": "Food and drink on road", "value": str(cargo_units), "note": "%d caravans touching these towns" % caravans.size(), "color": UiTheme.BLUE}])
		var card := FrozenKit.card(v, "Supply by climate", "Food supply includes market, barns, household stores and granaries.")
		FrozenKit.grid(card, ["Climate", "Towns", "Avg days", "Granary food"], climate_rows, [1.7, 0.7, 1, 1.4])
		card = FrozenKit.card(v, "Food and drink routes", "Actual caravan cargo; select a route to open its force record.")
		var rows := []
		for route: Dictionary in caravans:
			var band: Dictionary = route["band"]; var wid := String(band["id"])
			rows.append({"origin": route["origin"], "destination": route["destination"], "food": route["food"], "direction": route["direction"],
				"_l": "%s -> %s" % [route["origin"], route["destination"]], "_r": str(route["food"]),
				"_d": "%s; %s" % [route["direction"], Caravans.cargo_text(band.get("cargo", {}))], "_tap": func(): scr.open_force(wid)})
		var table := FrozenTable.make([{"k": "origin", "t": "Origin"}, {"k": "destination", "t": "Destination"},
			{"k": "food", "t": "Food + drink units", "num": true}, {"k": "direction", "t": "Direction"}], rows, "food", false)
		table.display_cells([{"k": "origin", "t": "Origin", "w": 1.8}, {"k": "destination", "t": "Destination", "w": 1.8},
			{"k": "food", "t": "Units", "w": 0.7}, {"k": "direction", "t": "Direction", "w": 1.0}])
		card.add_child(table)
		FrozenKit.disclosure(v, "Full food-flow record and unavailable totals", legacy)
	
	static func _fight_log(tids: Array, faction: String) -> Array:
		var names := tids.map(func(tid): return RecData.tname(tid))
		if faction != "": names.append(CampaignWorld.faction_the(faction).trim_prefix("the "))
		var log: Array = Game.world.get("log", [])
		var lines := []
		for i in range(log.size() - 1, -1, -1):
			var line := String(log[i]); var hit := faction == ""
			if not hit:
				for name in names:
					if line.contains(String(name)): hit = true; break
			if hit:
				lines.append(line)
				if lines.size() >= 40: break
		return lines
	
	static func fights(scr, tids: Array, fid: String, v: VBoxContainer, legacy: Callable) -> void:
		var causes := Census.causes_of(read_world(tids), tids)
		var now := int(causes["now"].get("battle", 0)); var last := int(causes["last"].get("battle", 0))
		var log := _fight_log(tids, fid)
		FrozenKit.metrics(v, [
			{"title": "Battle deaths", "value": str(now), "note": "This season, people of these towns", "color": UiTheme.BAD if now > 0 else UiTheme.BLUE},
			{"title": "Last season", "value": str(last), "note": "Battle deaths in the same towns", "color": UiTheme.COPPER},
			{"title": "Retained log lines", "value": str(log.size()), "note": "Latest matching records, up to 40", "color": UiTheme.BLUE}])
		var card := FrozenKit.card(v, "Recorded world pursuits", "All-time world totals; these are pursuits, not a count of battles in these towns.")
		var stats: Dictionary = Game.world.get("war", {}).get("stats", {})
		FrozenKit.grid(card, ["Outcome", "War bands"], [
			{"values": ["Ran their prey down", str(int(stats.get("caught", 0)))]},
			{"values": ["Were beaten", str(int(stats.get("beaten", 0)))]},
			{"values": ["Gave up", str(int(stats.get("gave_up", 0)))]}], [2, 1])
		card.add_child(FrozenKit.row("The dead in battle", str(now), "Names, ages, families and recorded fight details", func():
			scr.page("Died in battle", func(box): FrozenTown.dead_list(scr, Game.world, tids, "battle", box))))
		card.add_child(UiKit.button("View legendary arms", func(): scr.page("Legendary arms", func(box): FrozenWorld.legends_card(scr, box)), "Row"))
		card = FrozenKit.card(v, "Latest log", "Newest first; select a line to read the complete record.")
		var rows := []
		for line in log.slice(0, 8):
			var text := String(line)
			rows.append({"values": [text], "tap": func(): scr.page("A world record", func(box): FrozenKit.line(box, text))})
		if rows.is_empty(): FrozenKit.line(card, "Nothing on the log.", "Muted")
		else: FrozenKit.grid(card, ["Recorded event"], rows)
		FrozenKit.disclosure(v, "Full fight record, log and unavailable fields", legacy)
	
	static func mines_land(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
		var table := FrozenWorld.mines_table(scr, tids)
		var family_land := 0; var town_land := 0; var common := 0
		for tid in tids:
			var land := RecData.land(FrozenWorld._e(tid))
			family_land += int(land["families"]); town_land += int(land["estate"]); common += int(land["common"])
		FrozenKit.metrics(v, [
			{"title": "Ore deposits", "value": str(table.rows.size()), "note": "Recorded town / ore entries", "color": UiTheme.BLUE},
			{"title": "Family land", "value": "%d acres" % family_land, "color": UiTheme.COPPER},
			{"title": "Town land", "value": "%d acres" % town_land, "note": "%d acres common or unclaimed" % common, "color": UiTheme.BLUE}])
		table.display_cells([{"k": "town", "t": "Town", "w": 1.8}, {"k": "ore", "t": "Ore", "w": 1.5},
			{"k": "rich", "t": "Richness", "format": func(value): return "%.2f" % float(value)}, {"k": "workers", "t": "Miners"}])
		FrozenKit.card(v, "Ore deposits", "Select a working mine for its business record. Richness is the recorded deposit factor.").add_child(table)
		v.add_child(UiKit.button("View land and herds", func(): scr.page("The land", func(box): FrozenWorld._land_card(tids, box)), "Row"))
		FrozenKit.disclosure(v, "Land by crop", func(box): _land_crops(tids, box))
		FrozenKit.disclosure(v, "Full mines and land record", legacy)
	
	static func _land_crops(tids: Array, v: VBoxContainer) -> void:
		var family := {}; var estate := {}; var kinds := {}
		for tid in tids:
			var land := RecData.land(FrozenWorld._e(tid))
			for key in land["fam_crops"]:
				family[key] = int(family.get(key, 0)) + int(land["fam_crops"][key]); kinds[key] = true
			for key in land["est_crops"]:
				estate[key] = int(estate.get(key, 0)) + int(land["est_crops"][key]); kinds[key] = true
		var keys: Array = kinds.keys(); keys.sort()
		var rows := []
		for key in keys: rows.append({"values": [String(key).capitalize(), str(int(family.get(key, 0))), str(int(estate.get(key, 0)))]})
		FrozenKit.grid(v, ["Crop", "Family acres", "Town acres"], rows, [2, 1, 1])
	
	static func merchants(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
		var table := FrozenWorld.merchants_table(scr, tids)
		var caravans := 0; var coins := 0.0; var traded := 0.0
		for row: Dictionary in table.rows:
			caravans += int(row["cars"]); coins += float(row["gold"]); traded += float(row["out"])
		FrozenKit.metrics(v, [
			{"title": "Caravans on road", "value": str(caravans), "note": "Originating in these towns", "color": UiTheme.BLUE},
			{"title": "Coin on road", "value": _m(coins), "note": "Actual caravan purses", "color": UiTheme.COPPER},
			{"title": "Traded out", "value": _m(traded), "note": "All-time recorded value", "color": UiTheme.BLUE}])
		table.display_cells([{"k": "town", "t": "Town", "w": 2.0}, {"k": "cars", "t": "Caravans", "w": 0.9},
			{"k": "gold", "t": "Coin out", "format": _m, "w": 1.3}, {"k": "out", "t": "Traded out", "format": _m, "w": 1.4}])
		FrozenKit.card(v, "Trade by town", "Select a town for its records. Incoming trade remains in the full row details.").add_child(table)
		var supply := FrozenWorld.supply_table(scr, tids)
		supply.display_cells([{"k": "town", "t": "Town", "w": 2}, {"k": "received", "t": "Received"}, {"k": "sent", "t": "Sent"}])
		FrozenKit.card(v, "Garrison equipment transfers", "All-time real pieces moved between own-faction armories. Issued kit is separate from reserve stock.").add_child(supply)
		FrozenKit.disclosure(v, "Full merchant and supply record", legacy)

class FrozenTown:
	extends RefCounted
	
	class RecordsRead:
		extends RefCounted
		var world: Dictionary
		var day: float
	
	## Older records helpers initialize missing books or person slots. Keep those
	## display defaults local while navigation still opens the actual town below.
	static func _records_read(t: Dictionary, e: Dictionary) -> RecordsRead:
		var view := RecordsRead.new()
		view.world = RecCivic._read_world(t, e)
		view.world["research"] = Game.world.get("research", {}).duplicate(true)
		view.day = float(Game.day)
		return view
	## The town tabs of the records screen (town spec parts 1-3, addendum 1). Every number is read from a real sim
	## field through RecData / Census; a field the sim does not keep yet is shown as "not tracked" (DEV_NOTES lists
	## them). scr = the records screen (navigation: open_family / open_person / open_business / open_force / page).
	
	static func build(scr, t: Dictionary, tab: String) -> Control:
		var v := UiKit.vbox(8)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var e := RecData.econ(t)
		if e.is_empty():
			FrozenKit.line(v, "Nobody here keeps accounts.", "Muted")
			return v
		match tab:
			"Overview": overview(scr, t, e, v)
			"Market": RecMarket.market(scr, t, e, v)
			"Businesses": businesses(scr, t, e, v)
			"Register": register(scr, t, e, v)
			"Land & Homes": RecCivic.land(scr, t, e, v)
			"Census": RecCivic.census(scr, t, e, v)
			"Treasury": RecCivic.treasury(scr, t, e, v)
			"Hardship": RecCivic.hardship(scr, t, e, v)
			"Garrison": RecMarket.garrison(scr, t, e, v)
			"Roads": RecCivic.roads(scr, t, e, v)
			"Sickness": RecCivic.sickness(scr, t, e, v)
			"Books": RecCivic.books(scr, t, e, v)
		return v
	
	static func _m(v: float) -> String:
		return RecData.money(v)
	
	# ================================================================== 2. OVERVIEW
	static func overview(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var families := RecData.fams(e)
		var adults := 0
		var idle := 0
		var states := {}
		for state in RecData.STATES: states[state] = []
		for f: Dictionary in families:
			adults += Families.adults(f)
			idle += int(f.get("idle", 0))
			(states[RecData.state(f)] as Array).append(f)
		var supply := RecData.days_food(t)
		var supply_level := TownEcon.supply_level(t, supply)
		FrozenKit.metrics(v, [
			{"title": "People", "value": UiKit.thousands(Census.people(e)), "note": "%d families" % families.size(), "color": UiTheme.BLUE},
			{"title": "Food", "value": "%d days" % int(supply), "note": "Last famine stage: " + RecData.stage_word(RecData.town_stage(e)).capitalize(), "color": UiTheme.BAD if supply_level == "starving" else (UiTheme.WARN if supply_level == "short" else UiTheme.GOOD)},
			{"title": "Treasury", "value": _m(RecData.treasury(e)), "note": "Town chest", "color": UiTheme.COPPER}])
		var c := FrozenKit.card(v, "At a glance")
		var dw: Variant = RecData.day_wage(e)
		var ls := RecData.land(e)
		FrozenKit.grid(c, ["Measure", "Now", "Context"], [
			{"values": ["Adults working", "%d / %d" % [adults - idle, adults], "%d without work" % idle], "tap": func(): scr.show_tab("Hardship")},
			{"values": ["Day wage", _m(float(dw)) if dw != null else FrozenKit.NT, "Labourer's day"]},
			{"values": ["Price level", "x%.2f" % RecData.price_level(e), "%s coin shortage" % FrozenKit.pct(RecData.coin_short(e), 1.0)]},
			{"values": ["Territory", "%d acres" % int(ls["territory"]), "%d family-owned" % int(ls["families"])], "tap": func(): scr.show_tab("Land & Homes")}
		], [1.5, 1.1, 1.5])
		var hd := RecData.head(e)
		c.add_child(FrozenKit.row("%s %s" % [String(hd.get("title", "head")).capitalize(), String(hd.get("name", "?"))], "Household", "Town head · open family record", func(): scr.open_family(t, int(hd.get("fam", 0)))))
		var reserves := FrozenKit.card(v, "Supply reserves")
		FrozenKit.grid(reserves, ["Supply", "Days", "Where"], [
			{"values": ["Food", str(int(supply)), "Market + barns + homes + granary"]},
			{"values": [RecData.good_name(e, "beer").capitalize(), str(int(RecData.days_of(e, "beer"))), "Market + homes"]},
			{"values": [RecData.good_name(e, "wine").capitalize(), str(int(RecData.days_of(e, "wine"))), "Market + homes"]},
			{"values": ["Firewood", str(int(RecData.days_of(e, "wood"))), "Market + homes"]}
		], [1.5, 0.6, 2.0])
		FrozenKit.meter(reserves, "Public granary", RecData.granary(e), RecData.granary_target(e), "Food equivalents · stored / target", UiTheme.COPPER)
		var homes := FrozenKit.card(v, "Household condition", "Each family appears once, under its most serious condition. Select a row to open the Register.")
		var rows := []
		for state in RecData.STATES:
			var fs: Array = states[state]
			var ppl := 0
			var purse := 0.0
			var hungry := 0
			for f: Dictionary in fs:
				ppl += RecData.people(f)
				purse += RecData.purse(f)
				if RecData.hungry_weeks(f) > 0: hungry += 1
			var key := String(state)
			rows.append({"values": [key.capitalize(), str(fs.size()), str(ppl), _m(purse / fs.size()) if not fs.is_empty() else "—", FrozenKit.pct(hungry, fs.size())],
				"color": RecData.state_color(key) if not fs.is_empty() else FrozenKit.GREY, "tap": func(): scr.goto_tab("Register", {"State": key})})
		FrozenKit.grid(homes, ["Condition", "Families", "People", "Avg purse", "Hungry"], rows, [1.7, 0.8, 0.8, 1.3, 0.8])
		var links := FrozenKit.card(v, "Town services")
		links.add_child(FrozenKit.row("Sick now", RecPages.sick_count(t), "Open Sickness", func(): scr.show_tab("Sickness")))
		links.add_child(FrozenKit.row("Garrison", "%d defenders" % TownDefence.garrison(Game, String(t["id"])).size(), "Guards, militia and stored equipment", func(): scr.show_tab("Garrison")))
		FrozenKit.disclosure(v, "Full town accounts, classes, herds & stories", func(box): overview_details(scr, t, e, box))
	
	static func overview_details(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var fams := RecData.fams(e)
		var adults := 0; var idle := 0
		var by_class := {"poor": [], "middling": [], "rich": []}
		var by_state := {}
		for state in RecData.STATES:
			by_state[state] = []
		for f in fams:
			adults += Families.adults(f)
			idle += int(f.get("idle", 0))
			(by_class[RecData.wealth_class(f)] as Array).append(f)
			(by_state[RecData.state(f)] as Array).append(f)
		var c := FrozenKit.card(v, "The town")
		FrozenKit.kv(c, "People", "%d in %d families" % [Census.people(e), fams.size()])
		FrozenKit.kv(c, "Adults working", "%s (%d of %d; %d without work)" % [FrozenKit.pct(adults - idle, adults), adults - idle, adults, idle])
		var dw: Variant = RecData.day_wage(e)
		FrozenKit.kv(c, "Day wage (a labourer's day)", _m(float(dw)) if dw != null else FrozenKit.NT)
		FrozenKit.kv(c, "Price level", "x%.2f (the realm's money: x1.00 = as the world began); coin short %s" % [RecData.price_level(e), FrozenKit.pct(RecData.coin_short(e), 1.0)])
		FrozenKit.kv(c, "Famine stage", RecData.stage_word(RecData.town_stage(e)))
		var ls := RecData.land(e)
		FrozenKit.kv(c, "Land", "%d acres in the territory (families %d, the town %d, unclaimed %d)" % [int(ls["territory"]), int(ls["families"]), int(ls["estate"]), int(ls["common"])])
		FrozenKit.kv(c, "Treasury", _m(RecData.treasury(e)))
		c.add_child(FrozenKit.row("Sick now", RecPages.sick_count(t), "bed-ridden, new this week, the diseases: tap for the Sickness tab", func(): scr.show_tab("Sickness")))
		var hd := RecData.head(e)
		c.add_child(FrozenKit.row("%s %s" % [String(hd.get("title", "head")).capitalize(), String(hd.get("name", "?"))], "head of the town",
			"of the %s family: tap for the household" % String(RecData.fam(e, int(hd.get("fam", 0))).get("name", "?")), func(): scr.open_family(t, int(hd.get("fam", 0)))))
		FrozenKit.kv(c, "Food price index", "x%.2f (x1.00 = normal; grain, fruit and meat by the diet)" % RecData.food_index(t))
		FrozenKit.kv(c, "Staple index (grain)", "x%.2f" % RecData.staple_index(t))
		var hfv: Variant = RecData.harvest_factor(e)
		FrozenKit.kv(c, "This year's harvest factor (weather)", ("x%.2f (x1.00 = a normal year)" % float(hfv)) if hfv != null else FrozenKit.NT)
		FrozenKit.kv(c, "Grain held in barns", "%d meals' worth" % RecData.barn(e, "grain"))
		# families by class (real purses)
		var cc := FrozenKit.card(v, "Families by class", "The town's own classes (by savings and holdings, each week).")
		for cls in ["poor", "middling", "rich"]:
			var fs: Array = by_class[cls]
			var ppl := 0; var inc := 0.0; var incn := 0; var sav := 0.0; var hung := 0
			for f in fs:
				ppl += RecData.people(f)
				sav += RecData.purse(f)
				if RecData.income_day(f) != null:
					inc += float(RecData.income_day(f)); incn += RecData.people(f)
				if RecData.hungry_weeks(f) > 0:
					hung += 1
			cc.add_child(FrozenKit.row(cls.capitalize(), "%d families" % fs.size(),
				"%d people, income %s a day per person, savings %s on average, hungry %s, food share: %s" % [ppl,
				_m(inc / incn) if incn > 0 else "-", _m(sav / fs.size()) if not fs.is_empty() else "-", FrozenKit.pct(hung, fs.size()), FrozenKit.NT],
				func(): scr.goto_tab("Register", {"Class": cls})))
		# days of supply
		var sc := FrozenKit.card(v, "Days of supply")
		FrozenKit.kv(sc, "Food", "%d days" % int(RecData.days_food(t)))
		for g in ["beer", "wine"]:
			FrozenKit.kv(sc, RecData.good_name(e, g).capitalize(), "%d days" % int(RecData.days_of(e, g)))
		FrozenKit.kv(sc, "Firewood", "%d days" % int(RecData.days_of(e, "wood")))
		FrozenKit.kv(sc, "Granary", "%d of a %d target (meals' worth)" % [RecData.granary(e), RecData.granary_target(e)])
		var gt := RecData.granary_today(e)
		if gt.is_empty() or int(gt[0]) != int(e.get("day", -1)):
			FrozenKit.kv(sc, "Granary today", "neither buying nor selling")
		elif int(gt[1]) < 0:
			FrozenKit.kv(sc, "Granary today", "selling %d meals' worth at %s a meal (relief price)" % [-int(gt[1]), _m(float(gt[2]))])
		elif int(gt[1]) > 0:
			FrozenKit.kv(sc, "Granary today", "buying %d meals' worth at %s a meal" % [int(gt[1]), _m(float(gt[2]))])
		else:
			FrozenKit.kv(sc, "Granary today", "neither buying nor selling")
		for line in TownEconTab.stores_lines(t):
			if String(line).contains("bars"):
				FrozenKit.line(sc, String(line))
		FrozenKit.kv(sc, "Wood", "%d loads in the market, %s burned a day by the homes" % [RecData.stock(e, "wood"), FrozenKit.num(RecData.household_use(e, "wood"))])
		FrozenKit.nt(sc, "Wood cut a day")
		FrozenKit.nt(sc, "Timber held for building")
		# families by state
		var stc := FrozenKit.card(v, "Families by state", "The worst real state of each family. Tap a row for the Register filtered to it.")
		for s in RecData.STATES:
			var fs2: Array = by_state[s]
			var ppl2 := 0; var sav2 := 0.0; var h2 := 0
			for f in fs2:
				ppl2 += RecData.people(f); sav2 += RecData.purse(f)
				if RecData.hungry_weeks(f) > 0: h2 += 1
			var ss := String(s)
			stc.add_child(FrozenKit.row(ss.capitalize(), "%d" % fs2.size(), "%d people, purse %s on average, hungry %s" % [ppl2,
				_m(sav2 / fs2.size()) if not fs2.is_empty() else "-", FrozenKit.pct(h2, fs2.size())], func(): scr.goto_tab("Register", {"State": ss}),
				RecData.state_color(ss)))
		# herds (addendum 1, B4): the records
		_herds_card(scr, t, e, v)
		# town buildings (addendum 1, A)
		_buildings(scr, t, e, v)
		# forces
		var fc := FrozenKit.card(v, "Forces")
		var mil := Militia.units_of(Game, String(t["id"]))
		fc.add_child(FrozenKit.row("The %s" % Army.town_tier(t), "%d men" % mil.size(), "paid from the treasury: tap the Garrison tab", func(): scr.show_tab("Garrison")))
		FrozenKit.kv(fc, "Recruits on offer at the tavern", "%d" % (t.get("recruits", []) as Array).size())
		var cars := _caravans_of(String(t["id"]))
		FrozenKit.kv(fc, "Caravans of this town on the road today", "%d" % cars.size())
		FrozenKit.nt(fc, "Caravans sent this week")
		# latest stories
		var st := FrozenKit.card(v, "Latest stories", "The town's own record of what befell it, newest first.")
		var hist: Array = e.get("hist", [])
		if hist.is_empty():
			FrozenKit.line(st, "Nothing noted yet.", "Muted")
		for i in range(hist.size() - 1, maxi(-1, hist.size() - 11), -1):
			var txt := String(hist[i])
			st.add_child(FrozenKit.row(txt.substr(0, 60), "", txt, func(): scr.page("A story of %s" % t["name"], func(b): FrozenKit.line(b, txt))))
		var lost: Array = e.get("legends_lost", [])   # v0.014: the town never forgets a legendary piece it lost
		if not lost.is_empty():
			var lc := FrozenKit.card(v, "Legendary pieces lost", "Carried by its people and taken by the enemy when they fell.")
			for x in lost:
				FrozenKit.line(lc, "%s: %s, when %s fell (taken by %s)" % [FrozenTown._day_word(float(x[0])), String(x[1]), String(x[2]), String(x[3])], "Small")
	
	const HERD_ORDER := ["cattle", "oxen", "horses", "donkeys", "sheep", "pigs", "goats", "hens", "rats", "bees"]
	
	## "40 cattle, 12 oxen, 300 sheep" from {kind: head}, in the herd order.
	static func herd_text(e: Dictionary, hs: Dictionary) -> String:
		var parts := []
		for k in HERD_ORDER + Herds.kinds().filter(func(x): return not HERD_ORDER.has(x)):   # (v0.012: every kind in the data)
			if int(hs.get(k, 0)) > 0:
				parts.append(RecData.herd_n(e, int(hs[k]), k))
		return ", ".join(PackedStringArray(parts)) if not parts.is_empty() else "none"
	
	## Addendum 1 B4: the Herds line (head by kind, fodder days left) and this year's herd book; tap for the herds.
	static func _herds_card(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var hc := FrozenKit.card(v, "Herds", "Every beast is counted in a herd with an owner; tap for the herds.")
		var fd: Variant = RecData.fodder_days(e)
		hc.add_child(FrozenKit.row("Herds", "%d herds" % RecData.herd_records(e).size(), "%s; fodder days left: %s" % [herd_text(e, RecData.herds(e)),
			("%d (own hay, the barns' and the market's hay and straw at the herds' feed)" % int(float(fd))) if fd != null else "no grazing beasts"],
			func(): scr.page("Herds of %s" % t["name"], func(b): herds_page(scr, t, e, b))))
		var bk := RecData.herd_book(e, "yr")
		FrozenKit.kv(hc, "This year", _book_text(bk))
		FrozenKit.kv(hc, "Manure on the fields", "x%.3f field yield" % RecData.manure_factor(e))
	
	static func _book_text(bk: Dictionary) -> String:
		var died := 0
		var causes := []
		var dd: Dictionary = bk.get("died", {})
		var ks: Array = dd.keys()
		ks.sort_custom(func(a, b): return int(dd[a]) > int(dd[b]))
		for c in ks:
			died += int(dd[c])
			causes.append("%s %d" % [String(c), int(dd[c])])
		return "born %d, bought %d, sold %d, slaughtered %d, stolen %d, driven home as loot %d, died %d%s" % [int(bk.get("born", 0)), int(bk.get("bought", 0)),
			int(bk.get("sold", 0)), int(bk.get("slaughtered", 0)), int(bk.get("stolen", 0)), int(bk.get("looted", 0)), died,
			(" (" + ", ".join(PackedStringArray(causes)) + ")") if not causes.is_empty() else ""]
	
	## The town's herds: by kind and age, the books, every record (kind, head, ages, owner, herders), the latest log.
	static func herds_page(scr, t: Dictionary, e: Dictionary, box: VBoxContainer) -> void:
		var c := FrozenKit.card(box, "By kind", "Young, grown and old; the price of a grown head; offered, wanted and sold last week.")
		var ages := RecData.herd_ages(e)
		var wk := RecData.animals_week(e)
		for k in HERD_ORDER:
			if not ages.has(k):
				continue
			var a: Array = ages[k]
			FrozenKit.kv(c, RecData.herd_word(e, k).capitalize(), "%d young, %d grown, %d old; %s a head; offered %d, wanted %d, sold %d" % [int(a[0]), int(a[1]), int(a[2]),
				_m(RecData.animal_price(e, k)), int(wk.get("offered", {}).get(k, 0)), int(wk.get("wanted", {}).get(k, 0)), int(wk.get("sold", {}).get(k, 0))])
		var bc := FrozenKit.card(box, "The herd book")
		FrozenKit.kv(bc, "This year", _book_text(RecData.herd_book(e, "yr")))
		FrozenKit.kv(bc, "Last year", _book_text(RecData.herd_book(e, "ly")))
		FrozenKit.kv(bc, "Since the records began", _book_text(RecData.herd_book(e, "tot")))
		var rows := []
		for h in RecData.herd_records(e):
			var hh: Dictionary = h
			var fid := RecData.herd_owner_fid(e, hh)
			rows.append({"kind": RecData.herd_word(e, String(hh["k"])), "head": RecData.herd_head(hh), "owner": RecData.herd_owner(e, hh),
				"_l": "%s %s" % [RecData.herd_head(hh), RecData.herd_word(e, String(hh["k"]))], "_r": RecData.herd_owner(e, hh),
				"_d": func(): return _herd_details(e, hh),
				"_tap": (func(): scr.open_family(t, fid)) if fid > 0 else Callable()})
		box.add_child(FrozenTable.make([{"k": "kind", "t": "Kind"}, {"k": "head", "t": "Head", "num": true}, {"k": "owner", "t": "Owner"}], rows, "head", false))
		var lc := FrozenKit.card(box, "The latest changes", "Every change to a herd: births, deaths with their cause, slaughter, sales and theft.")
		var lg := RecData.herd_log(e)
		for i in range(lg.size() - 1, maxi(-1, lg.size() - 31), -1):
			var r: Array = lg[i]
			FrozenKit.line(lc, "%s: %s %+d %s%s" % [_day_word(float(r[0])), String(r[4]), int(r[3]), RecData.herd_word(e, String(r[2])),
				(" (" + String(r[5]) + ")") if String(r[5]) != "" else ""])
		if lg.is_empty():
			FrozenKit.line(lc, "Nothing yet.", "Muted")
	
	## One herd's grey line: ages, herders (register persons), hay, plots, hunger.
	static func _herd_details(e: Dictionary, hh: Dictionary) -> String:
		var nm := []
		for p in RecData.herders(e, hh).slice(0, 3):
			nm.append(String(p["name"]))
		return "%d young, %d grown, %d old; herded by %s; %s bales of hay; %d plots%s" % [int(hh["y"]), int(hh["g"]), int(hh["o"]),
			", ".join(PackedStringArray(nm)) if not nm.is_empty() else "nobody named", FrozenKit.num(float(hh["fod"])), (hh["pl"] as Array).size(),
			(("; short of feed %d days" % int(hh["hun"])) if int(hh["hun"]) > 0 else "") + RecData.herd_state(hh)]
	
	## Addendum 1 B4: live animals, their own row group in Raw: the price of a grown head, offered / wanted / sold last
	## week, head in the town.
	static func _animals_rows(scr, t: Dictionary, e: Dictionary, box: VBoxContainer) -> void:
		var c := FrozenKit.card(box, "Live animals", "Bought and sold between owners, butchers and drovers at the town's price (a grown head; young and old cheaper).")
		var hs := RecData.herds(e)
		var wk := RecData.animals_week(e)
		var rows := []
		for k in HERD_ORDER:
			var p := RecData.animal_price(e, k)
			rows.append({"kind": RecData.herd_word(e, String(k)), "price": p, "xbase": p / maxf(0.01, RecData.animal_base(k)),
				"head": int(hs.get(k, 0)), "off": int(wk.get("offered", {}).get(k, 0)), "sold": int(wk.get("sold", {}).get(k, 0)),
				"_l": RecData.herd_word(e, String(k)).capitalize(), "_r": _m(p),
				"_d": "x%.2f base; %d in the town; offered %d, wanted %d, sold %d last week" % [p / maxf(0.01, RecData.animal_base(k)), int(hs.get(k, 0)),
					int(wk.get("offered", {}).get(k, 0)), int(wk.get("wanted", {}).get(k, 0)), int(wk.get("sold", {}).get(k, 0))],
				"_tap": func(): scr.page("Herds of %s" % t["name"], func(b): herds_page(scr, t, e, b))})
		c.add_child(FrozenTable.make([{"k": "kind", "t": "Animal"}, {"k": "price", "t": "Price", "num": true}, {"k": "xbase", "t": "x base", "num": true},
			{"k": "head", "t": "Head", "num": true}, {"k": "off", "t": "Offered", "num": true}, {"k": "sold", "t": "Sold", "num": true}], rows, "kind"))
	
	## Addendum 1 A: the town's own buildings. Only what the sim runs today has numbers; the rest wait for state plots.
	static func _buildings(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		# the town's own buildings are state plots (campaign/plots.gd); each row: what it is doing now and who runs it
		var c := FrozenKit.card(v, "Town buildings", "The town's own buildings on its land; tap for who runs it.")
		var view := _records_read(t, e)
		for b in Plots.buildings(view, view.world["towns"][String(t["id"])]):
			var r: Dictionary = b.get("runner", {})
			var who := String(r.get("name", "")) if not r.is_empty() else "nobody named"
			var fid := int(r.get("fid", 0)) if not r.is_empty() else -1
			c.add_child(FrozenKit.row(String(b["name"]).capitalize(), who, String(b.get("now", "")),
				(func(): scr.open_family(t, fid)) if fid >= 0 else Callable()))
	
	## "the flux 4, winter cough 2 (word of day 131)" from Sickness.outbreak_news.
	static func _news_text(n: Dictionary) -> String:
		var parts := []
		for dn in n["diseases"]:
			parts.append("%s %d" % [String(dn), int(n["diseases"][dn])])
		return "%s (word of %s)" % [", ".join(PackedStringArray(parts)), _day_word(float(n["day"])).to_lower()]
	
	static func _caravans_of(tid: String) -> Array:
		var out := []
		for wid in Game.world.get("warbands", {}):
			var wb: Dictionary = Game.world["warbands"][wid]
			if String(wb.get("kind", "")) == "caravan" and String(wb.get("origin", wb.get("home", ""))) == tid:
				out.append(wb)
		return out
	
	# ================================================================== 3. MARKET
	const CATS := [["food", "Food"], ["drink", "Drink"], ["raw", "Raw"], ["made", "Made goods"], ["bars", "Metal"], ["arms", "Arms & armour"]]
	
	static func market(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var c := FrozenKit.card(v, "Market by kind", "Stock in the market, days of supply at today's demand, and the biggest price move in a week.")
		for cat in CATS:
			var ck := String(cat[0])
			var gs := _goods_in(ck)
			var stock := 0; var dem := 0.0; var mover := ""; var mv := 0.0
			for g in gs:
				stock += RecData.stock(e, g)
				dem += RecData.demand(e, g)
				var pw: Variant = RecData.price_week_ago(e, g)
				if pw != null and float(pw) > 0.0:
					var ch := RecData.price(t, g) / float(pw) - 1.0
					if absf(ch) > absf(mv):
						mv = ch; mover = g
			var extra := ""
			if ck == "arms":
				extra = "; %d pieces of arms and armour on the stalls" % (t.get("shop", []) as Array).size()
			c.add_child(FrozenKit.row(String(cat[1]), "%d" % stock, "%s days%s%s" % [FrozenKit.num(stock / dem) if dem > 0.0 else "-",
				(", biggest move: %s %+d%%" % [RecData.good_name(e, mover), int(round(mv * 100.0))]) if mover != "" else "", extra],
				func(): scr.page(String(cat[1]), func(b): _goods_page(scr, t, e, ck, b))))
			if ck == "raw":   # addendum 1 B4: the live animals, a row group of Raw
				var wk := RecData.animals_week(e)
				var off := 0; var sold := 0
				for k in wk.get("offered", {}):
					off += int(wk["offered"][k])
				for k in wk.get("sold", {}):
					sold += int(wk["sold"][k])
				var hs0 := RecData.herds(e)
				var tot0 := 0
				for k in hs0:
					tot0 += int(hs0[k])
				c.add_child(FrozenKit.row("Raw: live animals", "%d" % tot0, "%s; offered %d, sold %d last week" % [herd_text(e, hs0), off, sold],
					func(): scr.page("Raw", func(b): _goods_page(scr, t, e, "raw", b))))
		_arms_grid(t, e, v)
	
	static func _goods_in(cat: String) -> Array:
		var out := []
		for g in Goods.ids():
			if RecData.goods_cat(g) == cat:
				out.append(g)
		return out
	
	static func _goods_page(scr, t: Dictionary, e: Dictionary, cat: String, box: VBoxContainer) -> void:
		if cat == "raw":   # addendum 1 B4: animals are their own row group in Raw
			_animals_rows(scr, t, e, box)
		var rows := []
		for g in _goods_in(cat):
			var p := RecData.price(t, g)
			var pw: Variant = RecData.price_week_ago(e, g)
			var ch: Variant = (p / float(pw) - 1.0) * 100.0 if pw != null and float(pw) > 0.0 else null
			var st := RecData.stock(e, g)
			var dem := RecData.demand(e, g)
			var why := RecData.price_why(e, g)
			var gg := String(g)
			rows.append({"good": RecData.good_name(e, g), "price": p, "xbase": p / RecData.base_price(g), "chg": ch, "stock": st,
				"days": st / dem if dem > 0.0 else null, "dem": dem,
				"_l": RecData.good_name(e, g).capitalize(), "_r": _m(p),
				"_d": "x%.2f base, %s a week, stock %d, %s days, demand %s a day, supply a day: %s%s" % [p / RecData.base_price(g),
					("%+d%%" % int(round(float(ch)))) if ch != null else "-", st, FrozenKit.num(st / dem) if dem > 0.0 else "-", FrozenKit.num(dem), FrozenKit.NT,
					(". " + why) if why != "" else ""],
				"_col": (UiTheme.BAD if float(ch) > 5.0 else (UiTheme.GOOD if float(ch) < -5.0 else UiTheme.INK)) if ch != null else UiTheme.INK,
				"_tap": func(): scr.page(RecData.good_name(e, gg).capitalize(), func(b): _good_page(scr, t, e, gg, b))})
		box.add_child(FrozenTable.make([{"k": "good", "t": "Good"}, {"k": "price", "t": "Price", "num": true}, {"k": "xbase", "t": "x base", "num": true},
			{"k": "chg", "t": "7-day %", "num": true}, {"k": "stock", "t": "Stock", "num": true}, {"k": "days", "t": "Days", "num": true},
			{"k": "dem", "t": "Demand", "num": true}], rows, "good"))
	
	static func _good_page(scr, t: Dictionary, e: Dictionary, g: String, box: VBoxContainer) -> void:
		var c := FrozenKit.card(box, "Price")
		FrozenKit.kv(c, "Today", _m(RecData.price(t, g)))
		var pw: Variant = RecData.price_week_ago(e, g)
		FrozenKit.kv(c, "A week ago", _m(float(pw)) if pw != null else FrozenKit.NT)
		if g == "grain":
			var buf: Dictionary = e.get("census", {}).get("buf", {})
			FrozenKit.chart(c, "Grain price, last 60 days", buf.get("d", []), buf.get("grain", []), " " + RecData.MONEY)
		else:
			FrozenKit.nt(c, "Price chart (only grain keeps a 60-day buffer)")
		var why := RecData.price_why(e, g)
		if why != "":
			FrozenKit.kv(c, "Why it moved", why)
		var pc := FrozenKit.card(box, "Businesses making it")
		var any := false
		for b in RecData.biz(e):
			if b.get("closed", false):
				continue
			for r in RecData.recipes(b):
				if (r.get("out", {}) as Dictionary).has(g):
					any = true
					var bid := int(b["id"])
					pc.add_child(FrozenKit.row(RecData.biz_title(e, b).capitalize(), RecData.biz_state(b), RecData.staff_text(b),
						func(): scr.open_business(t, bid)))
					break
		if not any:
			FrozenKit.line(pc, "None in this town.", "Muted")
		var cc := FrozenKit.card(box, "Caravans carrying it")
		var anyc := false
		for wid in Game.world.get("warbands", {}):
			var wb: Dictionary = Game.world["warbands"][wid]
			if String(wb.get("kind", "")) == "caravan" and int(wb.get("cargo", {}).get("goods", {}).get(g, 0)) > 0 \
					and (String(wb.get("origin", "")) == String(t["id"]) or String(wb.get("dest", "")) == String(t["id"])):
				anyc = true
				var w2 := String(wid)
				cc.add_child(FrozenKit.row(RecPages.force_name(wb), "%d" % int(wb["cargo"]["goods"][g]), Caravans.describe(Game.world, wb), func(): scr.open_force(w2)))
		if not anyc:
			FrozenKit.line(cc, "None on the road to or from here.", "Muted")
	
	## Arms on the stalls: material x quality (counts and the average price), and the armory apart.
	static func _arms_grid(t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var c := FrozenKit.card(v, "Arms and armour by material and quality", "Counts on the market stalls, average price in brackets.")
		var cells := {}
		var mats := []
		for it in t.get("shop", []):
			var mat := String(it.material)
			if not mats.has(mat):
				mats.append(mat)
			var k := "%s|%d" % [mat, int(it.quality)]
			var cell: Array = cells.get(k, [0, 0.0])
			cell[0] = int(cell[0]) + 1
			cell[1] = float(cell[1]) + float(Market.price(t, it))
			cells[k] = cell
		mats.sort()
		if mats.is_empty():
			FrozenKit.line(c, "The stalls are bare.", "Muted")
		for mat in mats:
			var parts := []
			for q in 6:
				var cell: Array = cells.get("%s|%d" % [mat, q], [0, 0.0])
				parts.append("%s %d%s" % [DB.QUALITY_NAMES[q] if q < DB.QUALITY_NAMES.size() else str(q), int(cell[0]),
					(" (%s)" % FrozenKit.num(float(cell[1]) / int(cell[0]))) if int(cell[0]) > 0 else ""])
			FrozenKit.line(c, "%s: %s" % [String(mat).capitalize(), ", ".join(PackedStringArray(parts))])
		var al := ArmsTrade.armory_lines(t)
		FrozenKit.kv(c, "The %s's armory (stock vs target)" % String(RecData.head(e).get("title", "head")), "; ".join(PackedStringArray(al)) if not al.is_empty() else "empty, nothing wanted")
		for ln in ArmsTrade.armory_log(t):   # v0.014: the armory log (why the militia and guards go short)
			FrozenKit.line(c, String(ln))
	
	# ================================================================== 4. BUSINESSES
	## One row of the Businesses list, every value from the business's own fields (tests/test_biz_people.gd reads it).
	static func biz_row(scr, t: Dictionary, e: Dictionary, b: Dictionary, context: Dictionary = {}) -> Dictionary:
		var bid := int(b["id"])
		var owner := int(b.get("owner", -1))
		var of := RecData.fam(e, owner) if owner >= 0 else {}
		var st := RecData.biz_state(b)
		var why := ""
		if String(b.get("state", "")) == "inputs" and String(b.get("why", "")) != "":
			why = ", no " + RecData.good_name(e, String(b["why"]))
		elif String(b.get("state", "")) == "wages" and String(b.get("why", "")).begins_with("money"):
			why = " (no %s)" % String(b["why"])   # v0.014: the till could not buy its materials, not its wages
		var hl: Variant = RecData.biz_health(b)
		var pf: Variant = RecData.biz_profit(b)
		var hp := ("%s, profit %s a day over 14 days, %d loss days" % [String(hl), _m(float(pf)) if pf != null else "-", RecData.biz_loss_days(b)]) if hl != null else FrozenKit.NT
		var kp := RecData.keeper(e, b, context)
		var kt := ("%s (%s)" % [String(kp["name"]), String(kp["how"])]) if not kp.is_empty() else "nobody at work there"
		var kw := int(b.get("kw", 0))
		var title := RecData.biz_title(e, b)
		var trade := RecData.biz_trade(b)
		return {"name": title, "trade": trade, "owner": String(of.get("name", "the town")),
			"state": st, "staff": int(b.get("workers", 0)) + kw, "cap": int(b.get("cap", 0)) + (1 if int(b.get("owner", -1)) >= 0 and not String(b["type"]) in ["farm", "estate"] else 0), "cash": RecData.till(b), "wage": RecData.biz_wage(b),
			"_keeper": kp,
			"_l": title.capitalize(), "_r": _m(RecData.till(b)),
			"_d": "%s; %s%s; staff %d of %d places%s at %s a day; owned by %s; kept by: %s; health and profit: %s" % [trade, st, why,
				int(b.get("workers", 0)), int(b.get("cap", 0)), " and its keeper" if kw > 0 else "", _m(RecData.biz_wage(b)),
				("the %s family" % of["name"]) if not of.is_empty() else "the town", kt, hp],
			"_col": {"busy": UiTheme.GOOD, "inputs": UiTheme.BAD, "wages": UiTheme.BAD, "hands": UiTheme.WARN, "nopay": UiTheme.WARN}.get(String(b.get("state", "")), UiTheme.INK),
			"_s": title + " " + trade,
			"_tap": func(): scr.open_business(t, bid)}
	
	static func businesses(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var rows := []
		var context := RecData.work_context(e)
		for b in RecData.biz(e):
			if b.get("closed", false):
				continue
			if int(b.get("cap", 0)) <= 0 and int(b.get("workers", 0)) <= 0 and int(b.get("kw", 0)) <= 0:
				continue   # (a shop worked by its keeper alone is listed: v0.014)
			rows.append(biz_row(scr, t, e, b, context))
		var states := ["all"]
		for r in rows:
			if not states.has(r["state"]):
				states.append(r["state"])
		FrozenKit.metrics(v, [
			{"title": "Listed businesses", "value": str(rows.size()), "note": "Including keeper-run trades", "color": UiTheme.BLUE},
			{"title": "Working", "value": str(rows.filter(func(r): return r["state"] == RecData.biz_state({"state": "busy"})).size()), "note": "Current production state", "color": UiTheme.GOOD},
			{"title": "Closed", "value": str(RecData.biz(e).filter(func(b): return b.get("closed", false)).size()), "note": "Closed ledger below", "color": UiTheme.WARN}])
		var table := FrozenTable.make([{"k": "name", "t": "Name"}, {"k": "trade", "t": "Trade"}, {"k": "owner", "t": "Owner"},
			{"k": "state", "t": "State"}, {"k": "staff", "t": "Staff", "num": true}, {"k": "cash", "t": "Cash", "num": true},
			{"k": "wage", "t": "Wage", "num": true}], rows, "trade", true,
			[{"t": "State", "opts": states, "fn": func(r, o): return r["state"] == o}], true)
		table.display_cells([{"k": "name", "t": "Business", "w": 2.6}, {"k": "state", "t": "Status", "w": 1.5}, {"k": "staff", "t": "At work", "w": 0.8}, {"k": "cash", "t": "Till", "w": 1.0}, {"k": "wage", "t": "Wage/day", "w": 1.0}])
		FrozenKit.card(v, "Businesses").add_child(table)
		var cc := FrozenKit.card(v, "Closed")
		var closed := RecData.biz(e).filter(func(b): return b.get("closed", false))
		if closed.is_empty():
			FrozenKit.line(cc, "None.", "Muted")
		for b in closed:
			var bid2 := int(b["id"])
			cc.add_child(FrozenKit.row(RecData.biz_title(e, b).capitalize(), "closed", "%s; for sale: %s; when: %s" % [RecData.biz_trade(b),
				"yes" if b.get("for_sale", false) else "no", FrozenKit.NT], func(): scr.open_business(t, bid2)))
	
	# ================================================================== 5. REGISTER
	static func register(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var read_town := RecCivic._read_town(t, e)
		var c := People.census(read_town["econ"])
		FrozenKit.metrics(v, [
			{"title": "Households", "value": str(int(c["households"])), "note": "%d people" % int(c["population"]), "color": UiTheme.BLUE},
			{"title": "Adults", "value": str(int(c["adults"])), "note": "%d children · %d elders" % [int(c["children"]), int(c["elders"])], "color": UiTheme.COPPER},
			{"title": "Homeless", "value": str(int(c["homeless"])), "note": "%d empty homes" % int(c["empty_homes"]), "color": UiTheme.BAD if int(c["homeless"]) > 0 else UiTheme.GOOD}])
		var sick_by := {}   # family id -> its people at home sick now (campaign/sickness.gd)
		for hh in Sickness.hardest_homes(read_town, 1 << 30):
			sick_by[int(hh["fid"])] = int(hh["sick"])
		var rows := []
		for f in RecData.fams(e):
			var fid := int(f["id"])
			var family: Dictionary = f
			var st := RecData.state(f)
			var inc: Variant = RecData.income_day(f)
			var hire := RecData.n_state(f, "hire")
			var sk := int(sick_by.get(fid, 0))
			var wealth := RecData.wealth_class(f)
			var people := RecData.people(f)
			rows.append({"name": String(f["name"]), "class": wealth, "state": st, "people": people,
				"purse": RecData.purse(f), "income": inc, "hungry": RecData.hungry_weeks(f), "debt": RecData.debt(f), "hire": hire, "sick": sk,
				"_l": "The %s" % f["name"], "_r": _m(RecData.purse(f)),
				"_d": func(): return "%s, %s; %d people%s; income %s a day; famine stage %s (%s days short of food at the last turn)%s%s; home: %s" % [st, wealth, people,
					(", %d sick" % sk) if sk > 0 else "",
					_m(float(inc)) if inc != null else "-", RecData.stage_word(RecData.fam_stage(family)), FrozenKit.num(RecData.days_short(family)), ("; owes %s" % _m(RecData.debt(family))) if RecData.debt(family) > 0.5 else "",
					("; %d for hire" % hire) if hire > 0 else "", "none" if RecData.homeless(family) else ("%d, address %s" % [int(family.get("homes", 0)), FrozenKit.NT])],
				"_col": UiTheme.BAD if RecData.purse(f) < 0.0 else RecData.state_color(st), "_s": String(f["name"]),
				"_tap": func(): scr.open_family(t, fid)})
		var tbl := FrozenTable.make([{"k": "name", "t": "Family"}, {"k": "class", "t": "Class"}, {"k": "state", "t": "State"},
			{"k": "people", "t": "People", "num": true}, {"k": "purse", "t": "Purse", "num": true}, {"k": "income", "t": "Income", "num": true},
			{"k": "hungry", "t": "Hunger", "num": true}, {"k": "debt", "t": "Debt", "num": true}, {"k": "sick", "t": "Sick", "num": true}], rows, "name", true,
			[{"t": "Class", "opts": ["all", "poor", "middling", "rich"], "fn": func(r, o): return r["class"] == o},
			{"t": "State", "opts": ["all"] + RecData.STATES, "fn": func(r, o): return r["state"] == o},
			{"t": "Only", "opts": ["all", "homeless", "for hire", "in debt", "hungry", "sick"], "fn": func(r, o): return _only(r, o)}], true)
		FrozenKit.card(v, "Household register").add_child(tbl)
		tbl.display_cells([{"k": "name", "t": "Family", "w": 1.6}, {"k": "state", "t": "Condition", "w": 1.4}, {"k": "people", "t": "People", "w": 0.7}, {"k": "purse", "t": "Purse", "w": 1.1}, {"k": "income", "t": "Income/day", "w": 1.1}])
		for k in scr.preset:
			tbl.preset(String(k), String(scr.preset[k]))
		FrozenKit.disclosure(v, "Register totals & definitions", func(box):
			FrozenKit.grid(box, ["People", "Count"], [{"values": ["Female", str(int(c["female"]))]}, {"values": ["Male", str(int(c["male"]))]}, {"values": ["Sick", RecPages.sick_count(t)]}], [2, 1])
			FrozenKit.nt(box, "Hunger % of the last 14 days, cold, mourning")
			FrozenKit.line(box, "Income is household income per day. Purse is current coin. Hunger counts consecutive hungry weeks. The condition uses each family's worst current state.", "Small"))
	
	static func _only(r: Dictionary, o: String) -> bool:
		match o:
			"homeless": return r["state"] in ["homeless", "destitute", "poorhouse"]
			"for hire": return int(r["hire"]) > 0
			"in debt": return float(r["debt"]) > 0.5
			"hungry": return int(r["hungry"]) > 0
			"sick": return int(r["sick"]) > 0
		return true
	
	# ================================================================== 6. LAND & HOMES
	const LAND_MAP_SLOT := "LandMapSlot"
	
	static func land(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var ls := RecData.land(e)
		var c := FrozenKit.card(v, "Land")
		FrozenKit.kv(c, "Owned by the families", "%d acres%s" % [int(ls["families"]), _crops(e, ls["fam_crops"])])
		FrozenKit.kv(c, "Held by the town (offered for sale)", "%d acres%s" % [int(ls["estate"]), _crops(e, ls["est_crops"])])
		FrozenKit.kv(c, "Unclaimed or common", "%d acres" % int(ls["common"]))
		c.add_child(FrozenKit.row("Herds", "%d herds" % RecData.herd_records(e).size(), herd_text(e, RecData.herds(e)),
			func(): scr.page("Herds of %s" % t["name"], func(b): herds_page(scr, t, e, b))))
		FrozenKit.nt(c, "Pasture and woodland acres")
		# ------------------------------------------------ LAND MAP SLOT: the land helper's map view (ui/land_map.gd) mounts here
		var slot := FrozenKit.card(v, "Land map")
		slot.name = LAND_MAP_SLOT
		slot.set_meta("town_id", String(t["id"]))
		# the map opens full screen (built on tap: keeps the tab switch fast and the tab phone-width)
		FrozenKit.line(slot, "Every plot on the town's land book, tile by tile.", "Muted")
		slot.add_child(UiKit.button("Open the land map", func(): LandMap.open(scr, t), "", 220))
		# by owner
		var rows := []
		for f in RecData.fams(e):
			var ac := RecData.acres(f)
			if ac <= 0 and RecData.heads(f) <= 0:
				continue
			var fid := int(f["id"])
			var ff: Dictionary = f
			rows.append({"name": String(f["name"]), "acres": ac, "head": RecData.heads(f), "_l": "The %s" % f["name"], "_r": "%d acres" % ac,
				"_d": func(): return Families.land_line(e, ff).trim_prefix("Land: ") + " " + Families.herd_line(ff), "_s": String(f["name"]),
				"_tap": func(): scr.open_family(t, fid)})
		var oc := FrozenKit.card(v, "By owner")
		oc.add_child(FrozenTable.make([{"k": "name", "t": "Family"}, {"k": "acres", "t": "Acres", "num": true}, {"k": "head", "t": "Herd head", "num": true}],
			rows, "acres", false, [], true, 10))
		# homes
		var hc := FrozenKit.card(v, "Homes")
		FrozenKit.kv(hc, "Homes held by families", "%d" % int(e.get("homes", 0)))
		FrozenKit.kv(hc, "Empty (held by the town)", "%d" % RecData.empty_homes(e))
		FrozenKit.kv(hc, "New homes for sale in the market", "%d at %s" % [RecData.homes_for_sale(e), _m(RecData.price(t, "home"))])
		FrozenKit.kv(hc, "Value index", "x%.2f (market price of a new home over its base)" % (RecData.price(t, "home") / RecData.base_price("home")))
		FrozenKit.nt(hc, "Seized homes, rent this month, one record per home (kind, condition, mortgage)")
		var hrows := []
		for f in RecData.fams(e):
			var fid2 := int(f["id"])
			var cond := float(f.get("cond", 1.0))
			var fh: Dictionary = f
			hrows.append({"name": String(f["name"]), "homes": int(f.get("homes", 0)), "cond": cond if int(f.get("homes", 0)) > 0 else null,
				"people": RecData.people(f), "rent": f.has("rent"),
				"_l": "The %s" % f["name"], "_r": "%d home%s" % [int(f.get("homes", 0)), "" if int(f.get("homes", 0)) == 1 else "s"],
				"_d": func(): return ("homeless: " + Shelter.state_line(e, fh)) if RecData.homeless(fh) else "%d people; repair %d%%%s" % [RecData.people(fh), int(cond * 100.0),
					"; rents from the town" if fh.has("rent") else ""],
				"_s": String(f["name"]), "_tap": func(): scr.open_family(t, fid2)})
		hc.add_child(FrozenTable.make([{"k": "name", "t": "Household"}, {"k": "homes", "t": "Homes", "num": true}, {"k": "cond", "t": "Repair", "num": true},
			{"k": "people", "t": "People", "num": true}], hrows, "name", true,
			[{"t": "Show", "opts": ["all", "homeless", "renting"], "fn": func(r, o): return int(r["homes"]) <= 0 if o == "homeless" else bool(r["rent"])}], true, 10))
	
	static func _crops(e: Dictionary, d: Dictionary) -> String:
		var parts := []
		for k in d:
			if int(d[k]) > 0:
				parts.append("%s %d" % [RecData.crop_word(e, String(k)), int(d[k])])
		return "" if parts.is_empty() else " (%s)" % ", ".join(PackedStringArray(parts))
	
	# ================================================================== 7. CENSUS
	static func census(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		census_cards(scr, Game.world, [String(t["id"])], v)
	
	## The Census cards for any set of towns (a town, a faction, the world): population by season, the season table,
	## births and deaths by cause, coming and going, the balance line.
	static func census_cards(scr, w: Dictionary, tids: Array, v: VBoxContainer, balance: Dictionary = {}) -> void:
		var seasons := _season_rows(w, tids)
		var bal := Census.balance_of(w, tids) if balance.is_empty() else balance
		var people_now := int(bal["people"])
		var bc := FrozenKit.card(v, "Balance since the last census")
		var ok := Census.adds_up(bal)
		var bl := FrozenKit.line(bc, "%d born - %d died + %d arrived - %d left = %+d; people %d at the last census, %d now (%+d)%s" % [int(bal["births"]),
			int(bal["deaths"]), int(bal["arrived"]), int(bal["left"]), int(bal["births"]) - int(bal["deaths"]) + int(bal["arrived"]) - int(bal["left"]),
			int(bal["last"]), int(bal["people"]), int(bal["change"]), "" if ok else "  DOES NOT ADD UP"])
		if not ok:
			bl.add_theme_color_override("font_color", UiTheme.BAD)
		# population chart
		var pc := FrozenKit.card(v, "Population at each season's census")
		var xs := []; var ys := []
		for r in seasons:
			xs.append(int(r["stamp"])); ys.append(int(r["people"]))
		FrozenKit.chart(pc, "People", xs, ys, "", "seasons")
		# the season table
		var tc := FrozenKit.card(v, "Each season's census", "The first row is the count the record starts from; its births and deaths are the world before it.")
		tc.add_child(seasons_table(scr, w, tids))
		# births and deaths
		var bd := FrozenKit.card(v, "Births and deaths", "Every death has one cause, set by what killed him. Tap a cause for the dead.")
		var bx := []; var by := []; var dy := []
		for r in seasons:
			bx.append(int(r["stamp"])); by.append(int(r["births"])); dy.append(Census.sum(r["deaths"]))
		FrozenKit.chart(bd, "Births per season", bx, by, "", "seasons")
		FrozenKit.chart(bd, "Deaths per season", bx, dy, "", "seasons")
		var dd := _daily(w, tids)
		FrozenKit.chart(bd, "Deaths a day, last 60 days", dd["d"], dd["deaths"], "")
		var causes := Census.causes_of(w, tids)
		for cause in Census.CAUSES:
			var cs := String(cause)
			var now := int(causes["now"].get(cs, 0)); var last := int(causes["last"].get(cs, 0))
			bd.add_child(FrozenKit.row(cs.capitalize(), "%d this season" % now, "last season %d; %s per 1,000 people this season" % [last, FrozenKit.per_k(now, people_now)],
				func(): scr.page("Died of %s" % cs, func(b): dead_list(scr, w, tids, cs, b))))
		var aw := 0
		for tid in tids:
			aw += Census.sum(Census.current(w["towns"][tid]["econ"])["away"])
		FrozenKit.kv(bd, "Company men of here who died this season (not in the count)", "%d" % aw)
		_sick_card(w, tids, v)
		# coming and going
		var cg := FrozenKit.card(v, "Coming and going", "This season so far. Families who move walk to a real town (named below); company recruits and men from the countryside have no town.")
		var left := {}; var arr := {}
		for tid in tids:
			var cur := Census.current(w["towns"][tid]["econ"])
			for k in cur["left"]:
				left[k] = int(left.get(k, 0)) + int(cur["left"][k])
			for k in cur["arrived"]:
				arr[k] = int(arr.get(k, 0)) + int(cur["arrived"][k])
		FrozenKit.kv(cg, "Left", _whys(left))
		FrozenKit.kv(cg, "Arrived", _whys(arr))
		var mv := []
		for tid in tids:
			for m in Census._book(w["towns"][tid]["econ"])["moves"]:
				mv.append([m, tid])
		mv.sort_custom(func(a, b): return float(a[0][0]) > float(b[0][0]))
		for i in mini(mv.size(), 12):
			var m: Array = mv[i][0]
			var other := String(m[3])
			FrozenKit.line(cg, "%s: %d %s %s, %s (%s %s)" % [_day_word(float(m[0])), int(m[5]) if m.size() > 5 else 1, "left" if m[2] == "out" else "arrived in",
				RecData.tname(String(mv[i][1])), String(m[4]), "to" if m[2] == "out" else "from", other if other != "" else "where: " + FrozenKit.NT], "Small")
	
	## Census, sickness (06-sickness.md section 8): sick now, and cases and deaths by year from the sickness book
	## (e.sk.yr {year: [cases, sickness deaths, starved]}). The season's census rows do not count the sick.
	static func _sick_card(w: Dictionary, tids: Array, v: VBoxContainer) -> void:
		var sc := FrozenKit.card(v, "Sickness", "Open cases now, and every case and death of it by year.")
		var act := 0; var any := false
		var yr := {}
		for tid in tids:
			var t: Dictionary = w["towns"][tid]
			if not TownEcon.has_econ(t):
				continue
			any = true
			var sk: Dictionary = (t["econ"] as Dictionary).get("sk", {})
			for dis in sk.get("act", {}):
				act += int(sk["act"][dis])
			var y: Dictionary = sk.get("yr", {})
			for k in y:
				var a: Array = yr.get(int(k), [0, 0, 0])
				for i in 3:
					a[i] = int(a[i]) + int(y[k][i])
				yr[int(k)] = a
		if not any:
			FrozenKit.nt(sc, "Sickness")
			return
		if tids.size() == 1:   # one town: who is showing it (a wider view keeps to the counters: a tab stays fast)
			FrozenKit.kv(sc, "Sick now", RecPages.sick_count(w["towns"][tids[0]]))
		FrozenKit.kv(sc, "Open cases at home (caught, incubating or sick)", "%d" % act)
		var ks: Array = yr.keys()
		ks.sort()
		if ks.is_empty():
			FrozenKit.line(sc, "No case on record yet.", "Muted")
		for k in ks:
			FrozenKit.kv(sc, "Year %d" % int(k), "%d cases, %d died of sickness, %d starved" % [int(yr[k][0]), int(yr[k][1]), int(yr[k][2])])
		FrozenKit.nt(sc, "Sick at each season's census")
	
	static func _whys(d: Dictionary) -> String:
		if d.is_empty():
			return "nobody"
		var parts := []
		for k in d:
			parts.append("%d %s" % [int(d[k]), String(k)])
		return "%d: %s" % [Census.sum(d), ", ".join(PackedStringArray(parts))]
	
	## Season rows summed over towns by season stamp, oldest first.
	static func _season_rows(w: Dictionary, tids: Array) -> Array:
		var by := {}
		for tid in tids:
			for r in Census.rows(w["towns"][tid]["econ"]):
				var st := int(r["stamp"])
				if not by.has(st):
					by[st] = {"stamp": st, "people": 0, "families": 0, "children": 0, "adults": 0, "elders": 0, "female": 0, "male": 0, "homeless": 0,
						"empty_homes": 0, "soldiers": 0, "births": 0, "deaths": {}, "away": {}, "left": {}, "arrived": {}}
				var s: Dictionary = by[st]
				for k in ["people", "families", "children", "adults", "elders", "female", "male", "homeless", "empty_homes", "soldiers", "births"]:
					s[k] = int(s[k]) + int(r.get(k, 0))
				for k in ["deaths", "away", "left", "arrived"]:
					for kk in r.get(k, {}):
						s[k][kk] = int(s[k].get(kk, 0)) + int(r[k][kk])
		var ks: Array = by.keys()
		ks.sort()
		return ks.map(func(k): return by[k])
	
	static func _daily(w: Dictionary, tids: Array) -> Dictionary:
		var out := {"d": [], "deaths": []}
		var acc := {}
		for tid in tids:
			var buf: Dictionary = Census._book(w["towns"][tid]["econ"]).get("buf", {})
			var ds: Array = buf.get("d", [])
			var dt: Array = buf.get("dt", [])
			for i in range(1, ds.size()):
				var day := int(ds[i])
				acc[day] = int(acc.get(day, 0)) + int(dt[i]) - int(dt[i - 1])
		var ks: Array = acc.keys()
		ks.sort()
		for k in ks:
			out["d"].append(k); out["deaths"].append(acc[k])
		return out
	
	static func _season_word(stamp: int) -> String:
		return "%s of year %d" % [Calendar.SEASONS[(Calendar.START_SEASON + stamp) % 4], 1 + (Calendar.START_SEASON + stamp) / 4]
	
	static func _day_word(day: float) -> String:
		return "Day %d of %s, year %d" % [Calendar.day_of_season(day), Calendar.season(day), Calendar.year(day)]
	
	static func _season_page(r: Dictionary, box: VBoxContainer) -> void:
		var c := FrozenKit.card(box, "Deaths by cause")
		if (r["deaths"] as Dictionary).is_empty():
			FrozenKit.line(c, "Nobody died.", "Muted")
		for k in r["deaths"]:
			FrozenKit.kv(c, String(k).capitalize(), "%d" % int(r["deaths"][k]))
		var m := FrozenKit.card(box, "Coming and going")
		FrozenKit.kv(m, "Left", _whys(r["left"]))
		FrozenKit.kv(m, "Arrived", _whys(r["arrived"]))
		FrozenKit.kv(m, "Born", "%d" % int(r["births"]))
	
	## The dead of one cause: name, age, sex, family, job, date, where (tap -> his family page; the family remembers him).
	static func dead_list(scr, w: Dictionary, tids: Array, cause: String, box: VBoxContainer) -> void:
		var rows := []
		for tid in tids:
			var t: Dictionary = w["towns"][tid]
			var e: Dictionary = t["econ"]
			for d in e.get("census", {}).get("deaths", []):
				if String(d[5]) != cause:
					continue
				var fid := int(d[7]) if d.size() > 7 else -1
				var f := RecData.fam(e, fid)
				var tt: Dictionary = Game.world.get("towns", {}).get(String(tid), t)
				var nm := String(d[2]) if String(d[2]) != "" else "someone of the %s family" % String(f.get("name", "?"))
				rows.append({"name": nm, "age": int(d[3]) if int(d[3]) >= 0 else null, "day": float(d[0]), "town": String(t["name"]),
					"_l": nm, "_r": _day_word(float(d[0])),
					"_d": "%s%s; %s; %s; %s in %s%s" % [("age %d, " % int(d[3])) if int(d[3]) >= 0 else "", ["man", "woman"][int(d[4])] if int(d[4]) in [0, 1] else "sex: " + FrozenKit.NT,
						("the %s family" % f["name"]) if not f.is_empty() else "family: " + FrozenKit.NT, String(d[8]) if d.size() > 8 and String(d[8]) != "" else "job: " + FrozenKit.NT,
						String(d[6]) if String(d[6]) != "" else cause, t["name"], "" if (d.size() < 10 or int(d[9]) == 1) else " (away with the company: not in the count)"],
					"_s": nm, "_tap": (func(): scr.open_family(tt, fid)) if not f.is_empty() else Callable()})
		if rows.is_empty():
			FrozenKit.line(box, "Nobody on record died of %s (the record keeps the newest %d deaths per town)." % [cause, Census.DEATHS_MAX], "Muted")
			return
		box.add_child(FrozenTable.make([{"k": "day", "t": "Date", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
			{"k": "town", "t": "Where"}], rows, "day", false, [], true))
	
	# ================================================================== 8. TREASURY
	static func treasury(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var st := RecData.stats(e)
		var c := FrozenKit.card(v, "The chest")
		FrozenKit.kv(c, "Cash", _m(RecData.treasury(e)))
		var buf: Dictionary = e.get("census", {}).get("buf", {})
		FrozenKit.chart(c, "Treasury, last 60 days", buf.get("d", []), buf.get("tre", []), " " + RecData.MONEY)
		FrozenKit.nt(c, "In and out today")
		var tx := RecData.tax(e)
		var tr := RecData.tax_rules()
		var TL := RecData.treasury_lines(e)
		if not TL.is_empty():
			var TB: Dictionary = Barge.B()["treasury"]
			var svc: Array = TB["service"]
			var sk := float(e.get("svc_scale", 1.0)) * RecData.price_level(e)
			FrozenKit.kv(c, "Taxes (each month)", "service money %s / %s / %s a family (poor / middling / rich); house and land tax %.2f%% of their value%s; %d%% of the grain harvest to the granary" % [
				_m(float(svc[0]) * sk), _m(float(svc[1]) * sk), _m(float(svc[2]) * sk), 100.0 * float(TB["house_tax"]) * (1.0 + float(e.get("surcharge", 0.0))),
				(" (surcharge %d%%)" % int(round(100.0 * float(e.get("surcharge", 0.0))))) if float(e.get("surcharge", 0.0)) > 0.0 else "", int(round(float(tr["grain_share"]) * 100.0))])
			FrozenKit.kv(c, "This month", "%s in taxes; the chest %s over the month" % [_m(float(RecData.stats(e).get("tax_month", 0.0))),
				("%+d %s" % [int(round(float(RecData.stats(e).get("treasury_month", 0.0)))), RecData.MONEY])])
			FrozenKit.kv(c, "The chest's lines", "short below %s, full above %s" % [_m(float(TL["short"])), _m(float(TL["full"]))])
			var ru := RecData.ruler(e)
			FrozenKit.kv(c, "The ruler", "%s; tribute to the realm %d%% %s" % [String(ru.get("temper", "steady")), int(round(100.0 * float(ru.get("tribute", 0.0)))),
				"in grain" if String(ru.get("kind", "coin")) == "kind" else "in coin"])
		FrozenKit.kv(c, "Tax this season", "%s collected (last season %s), %d%% lost for want of collectors" % [_m(float(tx.get("paid", 0.0))),
			_m(float(tx.get("last_paid", 0.0))), int(round(float(tx.get("leak", 0.0)) * 100.0))])
		var lb := RecData.loans_book(e)
		FrozenKit.kv(c, "Arrears", "%d families behind on their loans" % int(lb["arrears"]))
		FrozenKit.kv(c, "Loans out", "%s owed by %d families" % [_m(float(lb["owed"])), int(lb["debtors"])])
		FrozenKit.kv(c, "Sent to the realm (last faction turn)", _m(float(st.get("to_faction", 0.0))) if st.has("to_faction") else FrozenKit.NT)
		FrozenKit.kv(c, "Tribute to the realm, about a month (weekly sends, smoothed)", _m(float(st["to_faction_month"])) if st.has("to_faction_month") else FrozenKit.NT)
		FrozenKit.kv(c, "Relief", "the poorhouse holds %d of %d places, costing %s a day" % [RecData.shelter_n(e), RecData.shelter_cap(t), _m(float(st.get("shelter_cost", 0.0)))])
		for b in RecData.biz(e):
			if String(b["type"]) == "collector":
				var cbid := int(b["id"])
				c.add_child(FrozenKit.row("Tax collectors", "%d of %d" % [int(b["workers"]), int(b["cap"])], "places filled, %s a day each, till %s: tap for who they are" % [
					_m(RecData.biz_wage(b)), _m(RecData.till(b))], func(): scr.open_business(t, cbid)))
		FrozenKit.nt(c, "The company's own dues here (tolls, fees)")
		var a := FrozenKit.card(v, "Accounts", "Running totals the sim keeps; month by month: not tracked.")
		for k in [["tax_in", "Tax taken in (all time)"], ["tax_month", "Taxes, last tax day"], ["treasury_month", "The chest's change, last month"], ["mtax", "Market tax, last week"], ["town_wages", "Town wages a day"],
				["militia_wages", "Militia paid yesterday"], ["militia_bill", "Militia bill a day"], ["shelter_cost", "Poorhouse a day"],
				["works", "Public works, last week"], ["lent", "Lent out (all time)"], ["int_earned", "Interest earned (all time)"],
				["written_off", "Written off (all time)"], ["army_levy", "Last army levy"], ["contracts_paid", "Contracts paid"]]:
			FrozenKit.kv(a, String(k[1]), _m(float(st[k[0]])) if st.has(k[0]) else FrozenKit.NT)
		# loans register
		var rows := []
		for f in RecData.fams(e):
			if RecData.debt(f) <= 0.5 and not f.has("ln"):
				continue
			var ln: Dictionary = f.get("ln", {})
			var fid := int(f["id"])
			var miss := int(ln.get("miss", 0))
			var status := "repaid" if RecData.debt(f) <= 0.5 else ("defaulted" if not (ln.get("sold", []) as Array).is_empty() else ("late" if miss > 0 else "current"))
			rows.append({"name": String(f["name"]), "lent": float(ln.get("lent", 0.0)), "owed": RecData.debt(f), "rate": float(ln.get("rate", RecData.loan_rate(e))),
				"pay": float(ln.get("pay", 0.0)), "miss": miss, "status": status,
				"_l": "The %s" % f["name"], "_r": _m(RecData.debt(f)),
				"_d": "%s; lent %s, rate %s a week, %s a week, %d missed%s; kind, collateral and clerk: %s" % [status, _m(float(ln.get("lent", 0.0))),
					"%.1f%%" % (100.0 * float(ln.get("rate", RecData.loan_rate(e)))), _m(float(ln.get("pay", 0.0))), miss,
					("; sold " + ", ".join(PackedStringArray(ln["sold"]))) if not (ln.get("sold", []) as Array).is_empty() else "", FrozenKit.NT],
				"_col": UiTheme.BAD if status in ["late", "defaulted"] else UiTheme.INK, "_s": String(f["name"]),
				"_tap": func(): scr.open_family(t, fid)})
		var lc := FrozenKit.card(v, "Loans register", "%d loans, %s out." % [rows.size(), _m(float(lb["owed"]))])
		lc.add_child(FrozenTable.make([{"k": "name", "t": "Borrower"}, {"k": "owed", "t": "Owed", "num": true}, {"k": "lent", "t": "Lent", "num": true},
			{"k": "rate", "t": "Rate", "num": true}, {"k": "pay", "t": "Pay", "num": true}, {"k": "miss", "t": "Missed", "num": true},
			{"k": "status", "t": "Status"}], rows, "owed", false,
			[{"t": "Show", "opts": ["all", "late", "defaulted"], "fn": func(r, o): return r["status"] == o}], true))
		FrozenKit.nt(v, "Ledger (last 60 entries)")
	
	# ================================================================== 9. HARDSHIP
	static func hardship(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var fams := RecData.fams(e)
		var n := {"hungry": 0, "homeless": 0, "destitute": 0, "debt": 0, "idle": 0}
		for f in fams:
			if RecData.hungry_weeks(f) > 0: n["hungry"] += 1
			if RecData.homeless(f): n["homeless"] += 1
			if RecData.destitute(f): n["destitute"] += 1
			if RecData.debt(f) > 0.5: n["debt"] += 1
			n["idle"] += int(f.get("idle", 0))
		var open := 0
		var dry := 0   # places its till cannot pay two days' wages for: nobody signs on there (Businesses.takeable)
		for b in RecData.biz(e):
			if not b.get("closed", false):
				var o := maxi(0, int(b.get("cap", 0)) - int(b.get("workers", 0)))
				open += o
				dry += o - Businesses.takeable(b)
		var c := FrozenKit.card(v, "Pressure")
		FrozenKit.kv(c, "Families going hungry", "%d (%s)" % [n["hungry"], FrozenKit.pct(n["hungry"], fams.size())])
		FrozenKit.kv(c, "Homeless households", "%d, of them destitute %d" % [n["homeless"], n["destitute"]])
		FrozenKit.kv(c, "Families in debt", "%d" % n["debt"])
		FrozenKit.kv(c, "Poorhouse", "%d of %d places" % [RecData.shelter_n(e), RecData.shelter_cap(t)])
		FrozenKit.kv(c, "Labour wanted vs offered", "%d open places (%d of them its till cannot pay two days' wages for), %d adults without work" % [open, dry, n["idle"]])
		var dw: Variant = RecData.day_wage(e)
		FrozenKit.kv(c, "Day wage", _m(float(dw)) if dw != null else FrozenKit.NT)
		FrozenKit.kv(c, "Food price index", "x%.2f" % RecData.food_index(t))
		var wb: Dictionary = e.get("census", {}).get("wbuf", {})
		var buf: Dictionary = e.get("census", {}).get("buf", {})
		FrozenKit.chart(c, "Hungry families (weekly), 60 days", wb.get("d", []), wb.get("hungry", []))
		FrozenKit.chart(c, "Homeless households (weekly), 60 days", wb.get("d", []), wb.get("homeless", []))
		FrozenKit.chart(c, "Families in debt (weekly), 60 days", wb.get("d", []), wb.get("debt", []))
		FrozenKit.chart(c, "Food days in the market, 60 days", buf.get("d", []), buf.get("food", []))
		var dc := FrozenKit.card(v, "Desperate: the recruit pool", "In the order the sim keeps them, with the family's real trouble.")
		var recs: Array = t.get("recruits", [])
		if recs.is_empty():
			FrozenKit.line(dc, "Nobody is for hire.", "Muted")
		for u in recs:
			var uu: Unit = u
			var f := People.fam_of(t, uu.family)
			var why := Families.story_line(e, f, uu.name.split(" ")[0], "his") if not f.is_empty() else ""
			dc.add_child(FrozenKit.row(uu.name, "%s" % uu.title, why if why != "" else "no hardship on record", func(): scr.open_unit(uu)))
		var sc := FrozenKit.card(v, "Seizures and forced sales", "Everything each family had to sell for its debt (when: not tracked).")
		var anys := false
		for f in fams:
			var sold: Array = f.get("ln", {}).get("sold", [])
			if sold.is_empty():
				continue
			anys = true
			var fid := int(f["id"])
			sc.add_child(FrozenKit.row("The %s" % f["name"], "%d sales" % sold.size(), ", ".join(PackedStringArray(sold)), func(): scr.open_family(t, fid)))
		for f in RecData.fams(e).filter(func(x): return x.has("lost")):
			anys = true
			var fid2 := int(f["id"])
			sc.add_child(FrozenKit.row("The %s" % f["name"], "lost", Families.lost_line(f), func(): scr.open_family(t, fid2)))
		if not anys:
			FrozenKit.line(sc, "None.", "Muted")
		var cg := FrozenKit.card(v, "Coming and going")
		# Census.current initializes missing old-save books; isolate that read.
		# All household and recruit actions above still target the actual town.
		var cur := Census.current(RecCivic._read_town(t, e)["econ"])
		FrozenKit.kv(cg, "Left this season", _whys(cur["left"]))
		FrozenKit.kv(cg, "Arrived this season", _whys(cur["arrived"]))
		FrozenKit.kv(cg, "Living in the poorhouse", "%d households" % fams.filter(func(f): return RecData.poorhouse(f)).size())
		FrozenKit.kv(cg, "Sleeping rough", "%d households" % fams.filter(func(f): return RecData.homeless(f) and not RecData.poorhouse(f)).size())
		FrozenKit.kv(cg, "Where they went (this season)", _whys(cur["to"]) if not (cur["to"] as Dictionary).is_empty() else "nobody")
		FrozenKit.kv(cg, "Where they came from (this season)", _whys(cur["from_t"]) if not (cur["from_t"] as Dictionary).is_empty() else "nobody")
	
	# ================================================================== 10. GARRISON
	static func garrison(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var tid := String(t["id"])
		var wb := Militia.band_of(Game, tid)
		var units: Array = TownDefence.garrison(Game, tid)
		var st := RecData.stats(e)
		var tier := Army.town_tier(t)
		var bill := Army.town_bill(Game, t)
		var c := FrozenKit.card(v, "The %s of %s" % [tier, t["name"]])
		FrozenKit.kv(c, "Men paid for", "%d" % units.size())
		FrozenKit.kv(c, "Pay bill a day", _m(bill))
		FrozenKit.kv(c, "Paid yesterday", _m(float(st.get("militia_wages", 0.0))))
		FrozenKit.kv(c, "Days of pay in the treasury", ("%d" % int(RecData.treasury(e) / bill)) if bill > 0.0 else "no bill")
		FrozenKit.kv(c, "Men unpaid", "%d" % int(st.get("militia_unpaid", 0)))
		var war := Diplomacy.enemies_at_war(Game.world, String(t.get("faction", "")))
		FrozenKit.kv(c, "War footing", ("yes: at war with " + ", ".join(PackedStringArray(war.map(func(x): return UiWords.faction_name(String(x)))))) if not war.is_empty() else "no")
		FrozenKit.kv(c, "Civilian militia", "%d; %s" % [Militia.units_of(Game, tid).size(), "mustered" if wb.get("mustered", false) else ("drilling" if wb.get("drill_today", false) else "at civilian work")])
		FrozenKit.kv(c, "Professional guards", str(TownDefence.guards(Game, tid).size()))
		FrozenKit.kv(c, "Drill days", str(wb.get("drill_days", 0)))
		FrozenKit.kv(c, "Barracks beds", str(e.get("barracks_beds", 0)))
		for k in ["Morale", "Kit %", "Deserted this year", "Promotion tests this month", "Sleeping in barracks vs at home"]:
			FrozenKit.nt(c, k)
		# ranks
		var rc := FrozenKit.card(v, "Ranks and pay", "The culture's rank names; pay a day by rank (base), plus %s a day for each grade of skill with his weapon." % _m(float(Army.A().get("per_grade", 5.0))))
		var by_rank := {}
		for u in units:
			var rt := Army.rank_title(u)
			by_rank[rt] = int(by_rank.get(rt, 0)) + 1
		var rl := Army.ranks(TownEcon.culture_of(e), tier)
		for i in range(rl.size() - 1, -1, -1):
			var nm := String(rl[i])
			FrozenKit.kv(rc, nm.capitalize(), "%d men, %s a day" % [int(by_rank.get(nm, 0)), _m(Army.wage(tier, i))])
		# weapons
		var wc := FrozenKit.card(v, "Weapons")
		var wpn := {}
		var qsum := 0.0; var qn := 0
		for u in units:
			var it: Variant = u.equip.get("main_hand", u.equip.get("ranged", null))
			if it != null:
				wpn[it.display_name()] = int(wpn.get(it.display_name(), 0)) + 1
				qsum += float(it.quality); qn += 1
		for k in wpn:
			FrozenKit.line(wc, "%d %s" % [int(wpn[k]), String(k)])
		FrozenKit.kv(wc, "Average quality", ("%.1f of 5" % (qsum / qn)) if qn > 0 else "-")
		var al := ArmsTrade.armory_lines(t)
		FrozenKit.kv(wc, "Armory vs target", "; ".join(PackedStringArray(al)) if not al.is_empty() else "empty, nothing wanted")
		# the roster
		var rows := []
		var view := _records_read(t, e)
		for u in units:
			var uu: Unit = u
			var rt := Army.rank_title(uu)
			var roster := func(): return Persons.roster_row(view, uu, "militia")
			var it2: Variant = uu.equip.get("main_hand", uu.equip.get("ranged", null))
			var sk := String(DB.weapons.get(it2.tid, {}).get("skill", "")) if it2 != null else ""
			var lvl := int(uu.skills.get(sk, 0)) if sk != "" else 0
			# The default rank sort needs no person lookup. Resolve ages/service when sorted, and the full
			# household record only for visible detail rows; every value still reads the current register.
			rows.append({"name": uu.name, "rank": rt, "rk": uu.rank, "age": func(): return int(roster.call()["age"]), "skill": lvl,
				"years": func(): return float(roster.call()["years_served"]), "pay": snappedf(uu.last_pay, 0.01), "renown": float(uu.renown),
				"_l": "%s %s" % [rt.capitalize(), uu.name], "_r": "%s a day" % _m(snappedf(uu.last_pay, 0.01)),
				"_d": func():
					var rr: Dictionary = roster.call()
					return "the %s; age %d; %s, %s (%d)%s; %s years served; renown %d; XP to next level: %s" % [String(rr["household"]) if String(rr["household"]) != "" else "?",
						int(rr["age"]), String(rr["weapon"]), UiWords.skill_level(lvl) if sk != "" else "-", lvl, "", FrozenKit.num(float(rr["years_served"])),
						int(round(uu.renown)), FrozenKit.NT],
				"_s": uu.name, "_tap": func(): scr.open_unit(uu)})
		var tc := FrozenKit.card(v, "Roster")
		tc.add_child(FrozenTable.make([{"k": "rk", "t": "Rank", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
			{"k": "skill", "t": "Skill", "num": true}, {"k": "years", "t": "Years", "num": true}, {"k": "pay", "t": "Pay", "num": true},
			{"k": "renown", "t": "Renown", "num": true}], rows, "rk", false, [], true))
		if not wb.is_empty():
			var wid := String(wb["id"])
			v.add_child(FrozenKit.row("The band on the map", "%d men" % units.size(), RecPages.force_name(wb), func(): scr.open_force(wid)))
	
	# ================================================================== 11. ROADS
	static func roads(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var w: Dictionary = Game.world
		var c := FrozenKit.card(v, "Roads to the neighbours", "Days at a caravan's pace along the road. Sickness: word brought by caravans (not seen from here). Danger from sightings: not tracked.")
		var news := Sickness.outbreak_news(RecCivic._read_town(t, e))
		for rl in t.get("road_links", []):
			var oid := String(rl.get("id", ""))
			var days := float(rl.get("dist", 0.0)) / (CampaignWorld.WARBAND_SPEED * Caravans.SPEED)
			var o := RecData.town(oid)
			var ob := ("; SICKNESS: " + _news_text(news[oid])) if news.has(oid) else ""
			c.add_child(FrozenKit.row(String(o.get("name", oid)) + (" (outbreak)" if ob != "" else ""), "%s days" % FrozenKit.num(days), UiWords.faction_name(String(o.get("faction", ""))) + "; " +
				("at war" if Diplomacy.at_war(w, String(t.get("faction", "")), String(o.get("faction", ""))) else Diplomacy.state(w, String(t.get("faction", "")), String(o.get("faction", ""))).to_lower().replace("_", " ")) + ob,
				func(): scr.open_town(oid), UiTheme.BAD if ob != "" else null))
		var nc := FrozenKit.card(v, "Word of sickness elsewhere", "What the caravans last said of each town they came from (open cases then).")
		if news.is_empty():
			FrozenKit.line(nc, "No word of sickness.", "Muted")
		for oid2 in news:
			var o2 := String(oid2)
			nc.add_child(FrozenKit.row(RecData.tname(o2), "", _news_text(news[o2]), func(): scr.open_town(o2)))
		var cc := FrozenKit.card(v, "Caravans of this town on the road")
		var cars := _caravans_of(String(t["id"]))
		if cars.is_empty():
			FrozenKit.line(cc, "None on the road now.", "Muted")
		for wb in cars:
			var wid := String(wb["id"])
			cc.add_child(FrozenKit.row("To %s" % RecData.tname(String(wb.get("dest", ""))), "%d men" % (wb["units"] as Array).size(), Caravans.describe(w, wb), func(): scr.open_force(wid)))
		var st := RecData.stats(e)
		FrozenKit.kv(cc, "Trade sent out (value, all time)", _m(float(st.get("trade_out", 0.0))) if st.has("trade_out") else FrozenKit.NT)
		FrozenKit.kv(cc, "Trade come in (value, all time)", _m(float(st.get("trade_in", 0.0))) if st.has("trade_in") else FrozenKit.NT)
		FrozenKit.nt(cc, "Caravans sent, arrived and robbed this year")
		var ac := FrozenKit.card(v, "Garrison supply", "Internal transfers use existing stock every ten days within the same faction.")
		FrozenKit.kv(ac, "Equipment received (all time)", str(int(st.get("military_supply_in", 0))))
		FrozenKit.kv(ac, "Equipment sent (all time)", str(int(st.get("military_supply_out", 0))))
		FrozenKit.kv(ac, "Arrows received / sent", "%d / %d" % [int(st.get("military_supply_in_arrows", 0)), int(st.get("military_supply_out_arrows", 0))])
		var lc := FrozenKit.card(v, "Road log", "The world's log lines that name this town, newest first.")
		var n := 0
		var log: Array = w.get("log", [])
		for i in range(log.size() - 1, -1, -1):
			var line := String(log[i])
			if line.contains(String(t["name"])):
				FrozenKit.line(lc, line, "Small")
				n += 1
				if n >= 20:
					break
		if n == 0:
			FrozenKit.line(lc, "Nothing on the log names %s." % t["name"], "Muted")
	
	# ================================================================== SICKNESS (06-sickness.md section 7)
	## Every number from campaign/sickness.gd's reads (town_summary, disease_rows, sick_people, hardest_homes,
	## remedies, deaths_season): people at home in their sick phase (a case still incubating is not seen).
	static func sickness(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var read_town := RecCivic._read_town(t, e)
		var hygiene := TownSanitation.book(read_town["econ"])
		var hygiene_card := FrozenKit.card(v, "Town cleanliness", "Weekly totals. Solids are kg; urine and drainage are litres.")
		for key in ["filth_kg", "incoming_kg", "swept_kg", "farm_manure_kg", "decayed_kg", "urine_litres", "urine_in_l", "night_soil_l", "river_l", "rats", "food_capacity", "caught", "births", "starved", "grain_eaten_kg", "cleaners"]:
			FrozenKit.kv(hygiene_card, String(key).replace("_", " ").capitalize(), "%.1f" % float(hygiene.get(key, 0)))
		var s := Sickness.town_summary(read_town)
		var c := FrozenKit.card(v, "Sickness", "People of the town at home and showing it (a case still incubating is not seen).")
		if s.is_empty():
			FrozenKit.nt(c, "Sickness")
			return
		FrozenKit.kv(c, "Sick now", "%d" % int(s["sick_now"]))
		FrozenKit.kv(c, "Bed-ridden", "%d" % int(s["bed_now"]))
		FrozenKit.kv(c, "New this week", "%d" % int(s["new_week"]))
		FrozenKit.kv(c, "Deaths this season (sickness and hunger)", "%d" % int(s["deaths_season"]))
		FrozenKit.kv(c, "Share of the town sick", "%.1f%%" % (100.0 * float(s["share"])))
		var h60: Array = s.get("h60", [])
		if h60.is_empty():
			FrozenKit.nt(c, "60-day chart of the sick")
		else:
			var day := int(e.get("day", 0))
			var xs := range(day - h60.size() + 1, day + 1)
			FrozenKit.chart(c, "Open cases at home (caught, incubating or sick), last 60 days", xs, h60)
		# disease rows: tap -> the sick of it
		var dc := FrozenKit.card(v, "Diseases", "Sick now, new this week, deaths this season; the trend over 8 days; where it came from. Tap for the sick.")
		var rows := Sickness.disease_rows(read_town)
		if rows.is_empty():
			FrozenKit.line(dc, "No disease in town.", "Muted")
		for r in rows:
			var dis := String(r["id"])
			var nm := String(r["name"])
			var tr := String(r["trend"])
			dc.add_child(FrozenKit.row(nm.capitalize(), "%d sick" % int(r["sick_now"]), "%d new this week, %d died this season, %s%s" % [int(r["new_week"]),
				int(r["deaths_season"]), tr, ("; " + String(r["origin"])) if String(r["origin"]) != "" else "; where it came from: " + FrozenKit.NT],
				func(): scr.page("Sick of %s" % nm, func(b): sick_list(scr, t, dis, b)),
				UiTheme.BAD if tr == "rising" else (UiTheme.GOOD if tr == "falling" else null)))
		if int(s["sick_now"]) > 0:
			dc.add_child(FrozenKit.row("Everyone sick", "%d" % int(s["sick_now"]), "all diseases: name, age, family, day N of M, remedy",
				func(): scr.page("The sick of %s" % t["name"], func(b): sick_list(scr, t, "", b))))
		# homes hit hardest
		var hc := FrozenKit.card(v, "Homes hit hardest", "Households with the most sick. Tap for the family.")
		var homes := Sickness.hardest_homes(read_town)
		if homes.is_empty():
			FrozenKit.line(hc, "Nobody sick at home.", "Muted")
		for hh in homes:
			var fid := int(hh["fid"])
			hc.add_child(FrozenKit.row("The %s" % String(hh["household"]), "%d sick" % int(hh["sick"]), "%d people in the household" % RecData.people(RecData.fam(e, fid)),
				func(): scr.open_family(t, fid)))
		# remedies
		var rm := Sickness.remedies(read_town)
		var rc := FrozenKit.card(v, "Remedies", "A family buys one for its sick if it can after food: the poor go without.")
		FrozenKit.kv(rc, "In the market", "%d" % int(rm.get("stock", 0)))
		FrozenKit.kv(rc, "Price", _m(float(rm.get("price", 0.0))))
		var hbs: Array = rm.get("herbalists", [])
		if hbs.is_empty():
			FrozenKit.line(rc, "No herbalist in town.", "Muted")
		for hb in hbs:
			var bid := int(hb["bid"])
			rc.add_child(FrozenKit.row(String(hb["title"]).capitalize(), String(hb["state"]), "%d of %d at work" % [int(hb["workers"]), int(hb["cap"])],
				func(): scr.open_business(t, bid)))
		# this season's dead of sickness and hunger
		var drows := []
		for d in Sickness.deaths_season(read_town):
			var pid := int(d["pid"])
			var nm2 := String(d["name"]) if String(d["name"]) != "" else "someone"
			var cause := String(d["detail"]) if String(d["cause"]) == "sickness" and String(d["detail"]) != "" else String(d["cause"])
			drows.append({"name": nm2, "age": int(d["age"]) if int(d["age"]) >= 0 else null, "day": float(d["day"]), "cause": cause,
				"_l": nm2, "_r": cause, "_d": "%s%s; %s" % [("age %d, " % int(d["age"])) if int(d["age"]) >= 0 else "",
					["man", "woman"][int(d["sex"])] if int(d["sex"]) in [0, 1] else "sex: " + FrozenKit.NT, _day_word(float(d["day"]))],
				"_s": nm2, "_tap": func(): _open_dead(scr, t, e, pid)})
		var kc := FrozenKit.card(v, "Died this season of sickness and hunger", "Person, age, cause (the disease, or starved). Tap for his page.")
		if drows.is_empty():
			FrozenKit.line(kc, "Nobody.", "Muted")
		else:
			kc.add_child(FrozenTable.make([{"k": "day", "t": "Date", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
				{"k": "cause", "t": "Cause"}], drows, "day", false, [], true, 10))
		var causes := Census.causes_of(RecCivic._read_world(t, e), [String(t["id"])])
		var cc := FrozenKit.card(v, "By cause, this season and last", "From the census: every death has one cause. Tap for all the dead of it on record.")
		for cs in ["sickness", "starved", "frozen"]:
			var css := String(cs)
			cc.add_child(FrozenKit.row(css.capitalize(), "%d" % int(causes["now"].get(css, 0)), "last season %d" % int(causes["last"].get(css, 0)),
				func(): scr.page("Died of %s" % css, func(b): dead_list(scr, Game.world, [String(t["id"])], css, b))))
	
	## The sick of one disease ("" = all): name, age, family, day N of M, remedy; by age band and by home (sort by
	## family). Tap -> his page.
	static func sick_list(scr, t: Dictionary, dis: String, box: VBoxContainer) -> void:
		var rows := []
		for p in Sickness.sick_people(t, dis):
			var fid := int(p["fid"]); var pid := int(p["pid"])
			rows.append({"name": String(p["name"]), "age": int(p["age"]), "family": String(p["family"]), "day": int(p["day_n"]), "band": String(p["band"]),
				"remedy": bool(p["remedy"]), "bed": bool(p["bed"]),
				"_l": "%s, %d" % [String(p["name"]), int(p["age"])], "_r": "day %d of %d" % [int(p["day_n"]), int(p["days_m"])],
				"_d": "%s%s; the %s household; remedy: %s%s; %s" % [(String(p["disease"]) + ", ") if dis == "" else "", String(p["band"]), String(p["family"]),
					"yes" if bool(p["remedy"]) else "no", "; bed-ridden" if bool(p["bed"]) else "", String(p["source"])],
				"_col": UiTheme.BAD if bool(p["bed"]) else UiTheme.INK, "_s": "%s %s" % [String(p["name"]), String(p["family"])],
				"_tap": func(): scr.open_person(t, fid, pid)})
		if rows.is_empty():
			FrozenKit.line(box, "Nobody is sick of it now.", "Muted")
			return
		box.add_child(FrozenTable.make([{"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true}, {"k": "family", "t": "Home"},
			{"k": "day", "t": "Day", "num": true}], rows, "day", false,
			[{"t": "Age", "opts": ["all", "child", "adult", "elder"], "fn": func(r, o): return r["band"] == o},
			{"t": "Remedy", "opts": ["all", "yes", "no"], "fn": func(r, o): return bool(r["remedy"]) == (o == "yes")}], true))
	
	## A dead person's page: his family from the census record (the newest death of that person id).
	static func _open_dead(scr, t: Dictionary, e: Dictionary, pid: int) -> void:
		var fid := -1
		for d in Census._book(e)["deaths"]:
			if int(d[1]) == pid and d.size() > 7:
				fid = int(d[7])
		if fid >= 0:
			scr.open_person(t, fid, pid)
	
	# ================================================================== 11b. BOOKS
	static func books(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
		var c := FrozenKit.card(v, "What the books noted", "One sentence per business event from live values: not tracked (the sim keeps no business event log yet).")
		FrozenKit.nt(c, "Harvest buying, shipments, hires and quits, loans and defaults, openings and closings, price swings")
		FrozenKit.nt(c, "Year-end line per business")
		var lc := FrozenKit.card(v, "The town's own record", "What the sim does note, newest first.")
		var hist: Array = e.get("hist", [])
		if hist.is_empty():
			FrozenKit.line(lc, "Nothing yet.", "Muted")
		for i in range(hist.size() - 1, -1, -1):
			FrozenKit.line(lc, String(hist[i]), "Small")
		var pc := FrozenKit.card(v, "Price reasons this week")
		var any := false
		for g in Goods.ids():
			var why := RecData.price_why(e, g)
			if why != "":
				any = true
				FrozenKit.line(pc, "%s: %s" % [RecData.good_name(e, g).capitalize(), why], "Small")
		if not any:
			FrozenKit.line(pc, "No price moved enough to note.", "Muted")
	
	static func seasons_table(scr, w: Dictionary, tids: Array) -> FrozenTable:
		var seasons := _season_rows(w, tids)
		var rows := []
		for i in seasons.size():
			var r: Dictionary = seasons[i]
			var rr := r
			rows.append({"season": int(r["stamp"]), "people": int(r["people"]), "families": int(r["families"]), "births": int(r["births"]),
				"deaths": Census.sum(r["deaths"]), "left": Census.sum(r["left"]), "arrived": Census.sum(r["arrived"]),
				"_l": _season_word(int(r["stamp"])), "_r": "%d people" % int(r["people"]),
				"_d": "%d families; %d children, %d adults, %d elders; %d female, %d male; born %d, died %d, came %d, left %d; homeless %d, soldiers %d, empty homes %d; sick: %s" % [
					int(r["families"]), int(r["children"]), int(r["adults"]), int(r["elders"]), int(r["female"]), int(r["male"]), int(r["births"]),
					Census.sum(r["deaths"]), Census.sum(r["arrived"]), Census.sum(r["left"]), int(r["homeless"]), int(r["soldiers"]), int(r["empty_homes"]), FrozenKit.NT],
				"_tap": func(): scr.page("Census of %s" % _season_word(int(rr["stamp"])), func(b): _season_page(rr, b))})
		return FrozenTable.make([{"k": "season", "t": "Season", "num": true}, {"k": "people", "t": "People", "num": true},
			{"k": "families", "t": "Families", "num": true}, {"k": "births", "t": "Births", "num": true}, {"k": "deaths", "t": "Deaths", "num": true},
			{"k": "arrived", "t": "Arrived", "num": true}, {"k": "left", "t": "Left", "num": true}], rows, "season", false)

class FrozenTable:
	extends VBoxContainer
	## A sortable, filterable list for the records screen (town spec part 1 section 1: "sort every list by any column").
	## One layout for phone and PC: a wrapping row of column chips (tap = sort by it, tap again = reverse, the arrow
	## shows which and which way), filter chips, a search box when the list has names, the shown count, then the rows
	## (two lines, the whole row tappable, >= 64 px). Nothing here scrolls sideways.
	##
	## cols = [{k, t, num}]: the column key in each row dict, its title, numeric (sorts by value) or text.
	## rows = [{<k>: value..., "_l": first-line name, "_r": main number, "_d": grey details (a String, or a Callable
	##          returning one: worked out only for the rows shown), "_tap": Callable, "_col": Color, "_s": search text}]
	## A column value may also be a no-argument Callable: evaluate it only when sorting that column.
	## filters = [{t: title, opts: [names], fn: Callable(row, opt) -> bool}] (opts[0] is "all": everything passes)
	
	const LIMIT := 15   # rows built at first (about a phone screen) ("Show more" adds as many again): keeps a tab switch fast
	
	var cols: Array = []
	var rows: Array = []
	var filters: Array = []
	var sort_k := ""
	var asc := true
	var fsel := {}
	var search := ""
	var limit := LIMIT
	var _rows_box: VBoxContainer
	var _count: Label
	var _ctl: VBoxContainer
	var display_columns: Array = []
	var _heading: RecCells
	var _search_box: LineEdit
	
	## Primary visible lanes are independent of all available sort/filter keys.
	func display_cells(columns: Array) -> FrozenTable:
		display_columns = columns
		_refresh()
		return self
	
	func ui_state() -> Dictionary:
		return {"sort": sort_k, "asc": asc, "filters": fsel.duplicate(), "search": search, "limit": limit}
	
	func restore_ui(state: Dictionary) -> void:
		if _col(String(state.get("sort", ""))).is_empty(): return
		sort_k = String(state["sort"])
		asc = bool(state.get("asc", true))
		fsel = state.get("filters", {}).duplicate()
		search = String(state.get("search", ""))
		limit = maxi(1, int(state.get("limit", LIMIT)))
		if _search_box != null: _search_box.set_text(search)
		_build_controls()
		_refresh()
	
	static func make(p_cols: Array, p_rows: Array, sort_key: String = "", ascending: bool = true, p_filters: Array = [],
			searchable: bool = false, first_rows: int = LIMIT, p_display_columns: Array = []) -> FrozenTable:
		var t := FrozenTable.new()
		t.limit = first_rows
		t.cols = p_cols
		t.rows = p_rows
		t.filters = p_filters
		t.sort_k = sort_key if sort_key != "" else (String(p_cols[0]["k"]) if not p_cols.is_empty() else "")
		t.asc = ascending
		# Build the final visible lanes once when the caller already knows them.
		# Later display_cells calls still refresh current rows and lazy details.
		t.display_columns = p_display_columns
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_constant_override("separation", 6)
		t._build(searchable)
		return t
	
	## Opens with a filter already set (e.g. Register filtered to "hungry" from the Overview).
	func preset(filter_title: String, opt: String) -> void:
		fsel[filter_title] = opt
		_build_controls()
		_refresh()
	
	func _build(searchable: bool) -> void:
		_ctl = UiKit.vbox(4)
		add_child(_ctl)
		_build_controls()
		if searchable:
			var le := LineEdit.new()
			_search_box = le
			le.placeholder_text = "Search by name"
			le.custom_minimum_size = Vector2(120, 48)
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.add_theme_stylebox_override("normal", UiTheme.sb(UiTheme.PARCH, UiTheme.PARCH_3, 1, 3, 10, 6))
			le.add_theme_stylebox_override("focus", UiTheme.sb(UiTheme.PARCH, UiTheme.COPPER, 2, 3, 10, 6))
			le.add_theme_color_override("font_color", UiTheme.INK)
			le.add_theme_color_override("font_placeholder_color", UiTheme.INK_SOFT)
			le.add_theme_color_override("caret_color", UiTheme.INK)
			le.text_changed.connect(func(s): search = s.strip_edges().to_lower(); _refresh())
			add_child(le)
		_count = UiKit.label("", "Muted", true)
		add_child(_count)
		_rows_box = UiKit.vbox(4)
		_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(_rows_box)
		_refresh()
	
	func _build_controls() -> void:
		UiKit.clear(_ctl)
		var fl := UiKit.flow(6)
		fl.add_child(_tag("Sort"))
		var sort := OptionButton.new()
		sort.custom_minimum_size = Vector2(150, 48)
		for i in cols.size():
			sort.add_item(String(cols[i]["t"]))
			if String(cols[i]["k"]) == sort_k: sort.select(i)
		sort.item_selected.connect(func(i): sort_by(String(cols[i]["k"])))
		fl.add_child(sort)
		fl.add_child(FrozenKit.chip_button("Ascending" if asc else "Descending", false, func(): sort_by(sort_k), 116))
		_ctl.add_child(fl)
		for f in filters:
			var title := String(f["t"])
			fl.add_child(_tag(title))
			var cur := String(fsel.get(title, f["opts"][0]))
			var pick := OptionButton.new()
			pick.custom_minimum_size = Vector2(140, 48)
			for i in (f["opts"] as Array).size():
				pick.add_item(String(f["opts"][i]).capitalize())
				if String(f["opts"][i]) == cur: pick.select(i)
			var options: Array = f["opts"]
			pick.item_selected.connect(func(i): set_filter(title, String(options[i])))
			fl.add_child(pick)
	
	func _tag(t: String) -> Label:
		var l := UiKit.label(t, "Small")
		l.custom_minimum_size = Vector2(0, 48)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		return l
	
	## Sort by a column; the same column again reverses.
	func sort_by(k: String) -> void:
		if k == sort_k:
			asc = not asc
		else:
			sort_k = k
			var c := _col(k)
			asc = not bool(c.get("num", false))   # numbers start biggest first, names A-Z
		_build_controls()
		_refresh()
	
	func set_filter(title: String, opt: String) -> void:
		fsel[title] = opt
		_build_controls()
		_refresh()
	
	func _col(k: String) -> Dictionary:
		for c in cols:
			if String(c["k"]) == k:
				return c
		return {}
	
	## The rows that pass the filters and search, in the current order.
	func shown() -> Array:
		var out := []
		for r in rows:
			var ok := true
			for f in filters:
				var opt := String(fsel.get(String(f["t"]), f["opts"][0]))
				if opt != String(f["opts"][0]) and not bool((f["fn"] as Callable).call(r, opt)):
					ok = false
					break
			if ok and search != "" and not String(r.get("_s", r.get("_l", ""))).to_lower().contains(search):
				ok = false
			if ok:
				out.append(r)
		# decorate once, sort on plain keys: [key, name, row]. Numbers fold the direction into the key; a missing
		# ("not tracked") number sorts after every real one either way.
		var c := _col(sort_k)
		var isnum := bool(c.get("num", false))
		var dec := []
		for r in out:
			var v: Variant = r.get(sort_k, null)
			if v is Callable:
				v = (v as Callable).call()
			var key: Variant
			if isnum:
				key = INF if (v == null or v is String) else (float(v) if asc else -float(v))
			else:
				key = (str(v) if v != null else "").to_lower()
			dec.append([key, String(r.get("_l", "")).to_lower(), r])
		var up := asc or isnum
		dec.sort_custom(func(a, b):
			if a[0] != b[0]:
				return (a[0] < b[0]) == up
			return a[1] < b[1])
		return dec.map(func(x): return x[2])
	
	func _refresh() -> void:
		if _rows_box == null:
			return
		var s := shown()
		if _heading != null:
			remove_child(_heading)
			_heading.queue_free()
			_heading = null
		if not display_columns.is_empty():
			_heading = RecCells.new()
			_heading.configure(display_columns.map(func(c): return String(c["t"])), display_columns.map(func(c): return float(c.get("w", 1.0))), display_columns.map(func(c): return String(c["t"])), true, UiTheme.INK_SOFT)
			add_child(_heading)
			move_child(_heading, _rows_box.get_index())
		_count.text = "%d shown of %d" % [mini(s.size(), limit), rows.size()] if s.size() > limit else "%d shown of %d" % [s.size(), rows.size()]
		# Re-evaluate filtering, ordering and lazy details on every refresh. Unchanged native rows keep
		# their shaped text and connections, especially when Show more adds another page.
		var previous := _rows_box.get_children()
		var keep := mini(s.size(), limit)
		for i in range(keep, previous.size()):
			_rows_box.remove_child(previous[i])
			previous[i].queue_free()
		for i in mini(s.size(), limit):
			var r: Dictionary = s[i]
			var d: Variant = r.get("_d", "")
			if d is Callable:   # details worked out only for the rows actually shown
				d = (d as Callable).call()
			var text := [String(r.get("_l", "")), String(r.get("_r", "")), String(d)]
			var tap: Callable = r.get("_tap", Callable())
			var col: Variant = r.get("_col", null)
			var color: Color = col if col is Color else UiTheme.INK
			var old: Node = previous[i] if i < previous.size() else null
			if not display_columns.is_empty():
				var values := []
				for column: Dictionary in display_columns:
					var value: Variant = r.get(String(column["k"]), null)
					if value is Callable: value = (value as Callable).call()
					var format: Callable = column.get("format", Callable())
					values.append(format.call(value) if format.is_valid() else (FrozenKit.NT if value == null else (FrozenKit.num(float(value)) if value is float else str(value))))
				if old is RecCells and old.get_meta("rec_values") == values and old.get_meta("rec_row") == text and old.get_meta("rec_tap", Callable()) == tap and old.get_meta("rec_color", UiTheme.INK) == color:
					continue
				if old != null:
					_rows_box.remove_child(old)
					old.queue_free()
				var cell := RecCells.new()
				cell.configure(values, display_columns.map(func(c): return float(c.get("w", 1.0))), display_columns.map(func(c): return String(c["t"])))
				cell.set_meta("rec_row", text)
				cell.set_meta("rec_tap", tap)
				cell.set_meta("rec_color", color)
				for ci in display_columns.size():
					if String(display_columns[ci]["k"]) in ["state", "status", "chg"]: cell.colors[ci] = color
				cell.tooltip_text += "\n" + String(d)
				cell.accessibility_description += "\n" + String(d)
				if tap.is_valid(): cell.pressed.connect(tap)
				_rows_box.add_child(cell)
				_rows_box.move_child(cell, i)
				continue
			if old is RecRow and old.get_meta("rec_row") == text and old.right_color == color and old.get_meta("rec_tap", Callable()) == tap:
				continue
			if old != null:
				_rows_box.remove_child(old)
				old.queue_free()
			var button := FrozenKit.row(text[0], text[1], text[2], tap, col)
			button.set_meta("rec_tap", tap)
			_rows_box.add_child(button)
			_rows_box.move_child(button, i)
		if s.size() > limit:
			_rows_box.add_child(UiKit.button("Show %d more" % mini(LIMIT, s.size() - limit), func(): limit += LIMIT; _refresh(), "Row"))
		if s.is_empty():
			_rows_box.add_child(UiKit.label("Nothing to show.", "Muted", true))

class FrozenKit:
	extends RefCounted
	## Builders for the town / faction / world records screen (ui/records.gd): cards, two-line tappable rows (min 64 px),
	## "not tracked" lines, small charts with min / max / now / span. Phone first: everything wraps to 720 px wide,
	## nothing scrolls sideways (only the screen's tab bar does). Sortable lists: ui/rec_table.gd.
	
	const ROW_H := 64
	const NT := "not tracked"
	const GREY := Color("6e5236")
	
	## A card: titled panel added to `parent`; returns its content box.
	static func card(parent: Control, title: String, note: String = "") -> VBoxContainer:
		var p := UiKit.panel("Card")
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(p)
		var v := UiKit.vbox(4)
		p.add_child(v)
		if title != "":
			v.add_child(UiKit.label(title, "H2", true))
		if note != "":
			v.add_child(UiKit.label(note, "Small", true))
		return v
	
	## A plain wrapped text line.
	static func line(parent: Control, text: String, variation: String = "") -> Label:
		var l := UiKit.label(text, variation, true)
		l.custom_minimum_size.x = 40
		parent.add_child(l)
		return l
	
	## Standalone notes need parchment behind their ink when the body shows wood.
	static func notice(parent: Control, text: String, variation: String = "Small") -> Label:
		return line(card(parent, ""), text, variation)
	
	## "Label: value" on one wrapped line, the value from a real field (or "not tracked").
	static func kv(parent: Control, key: String, value: String) -> Label:
		var l := line(parent, "%s: %s" % [key, value])
		if value == NT:
			l.theme_type_variation = "Muted"
		return l
	
	## A line for a field the sim does not keep yet: "Food share: not tracked".
	static func nt(parent: Control, what: String) -> Label:
		var l := UiKit.label("%s: %s" % [what, NT], "Muted", true)
		l.custom_minimum_size.x = 40
		parent.add_child(l)
		return l
	
	## A whole-row tap target, two lines: name and main number on the first, grey details on the second.
	static func row(left: String, right: String, details: String, cb: Callable, col: Variant = null) -> Button:
		var b := RecRow.new()
		b.theme_type_variation = "Row"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, ROW_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_contents = true
		b.set_content(left, right, details, col)
		if cb.is_valid():
			b.pressed.connect(cb)
		else:
			b.disabled = false
		b.set_meta("rec_row", [left, right, details])
		return b
	
	## A button that sits in a flow of chips (min 48 px tall).
	static func chip_button(text: String, on: bool, cb: Callable, min_w: int = 96) -> Button:
		var b := UiKit.button(text, cb, "TabOn" if on else "Tab", min_w)
		b.custom_minimum_size = Vector2(min_w, 48)
		b.add_theme_font_size_override("font_size", 18)
		return b
	
	## A small line chart of real samples with "min / max / now over N days" under it. xs = days (or season index).
	static func chart(parent: Control, title: String, xs: Array, ys: Array, unit: String = "", span_word: String = "days") -> void:
		var v := UiKit.vbox(2)
		parent.add_child(v)
		v.add_child(UiKit.label(title, "Small", true))
		if ys.size() < 2:
			v.add_child(UiKit.label("Too few samples yet (%d)." % ys.size(), "Muted", true))
			return
		var c := RecChart.new()
		c.ys = ys.map(func(x): return float(x))
		c.custom_minimum_size = Vector2(120, 90)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(c)
		var lo := INF; var hi := -INF
		for y in c.ys:
			lo = minf(lo, y); hi = maxf(hi, y)
		var span := float(xs[-1]) - float(xs[0]) if xs.size() >= 2 else float(ys.size())
		v.add_child(UiKit.label("min %s, max %s, now %s%s, over %s %s" % [num(lo), num(hi), num(float(c.ys[-1])), unit,
			num(span), span_word], "Muted", true))
	
	## 12 -> "12", 3.456 -> "3.46", 1234.5 -> "1235".
	static func num(v: float) -> String:
		if is_inf(v) or is_nan(v):
			return "-"
		if absf(v) >= 100.0 or is_equal_approx(v, round(v)):
			return str(int(round(v)))
		if absf(v) >= 10.0:
			return "%.1f" % v
		return "%.2f" % v
	
	static func pct(part: float, whole: float) -> String:
		return "%d%%" % int(round(100.0 * part / whole)) if whole > 0.0 else "-"
	
	## Per 1,000 people.
	static func per_k(n: float, people: float) -> String:
		return "%.1f" % (1000.0 * n / people) if people > 0.0 else "-"
	
	static func sep(parent: Control) -> void:
		parent.add_child(HSeparator.new())
	
	## Responsive summary cards; these expose only existing facts, never derived promises.
	static func metrics(parent: Control, entries: Array) -> GridContainer:
		var grid := GridContainer.new()
		grid.columns = 3
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		parent.add_child(grid)
		for entry: Dictionary in entries:
			var tone: Color = entry.get("color", UiTheme.BLUE)
			var p := UiKit.panel("Card")
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			p.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.LIGHT, tone, 2, 5, 10, 6))
			p.set_meta("rec_metric", entry.duplicate())
			grid.add_child(p)
			var box := UiKit.vbox(2)
			p.add_child(box)
			var title := UiKit.label(String(entry.get("title", "")), "Small", true)
			title.custom_minimum_size.x = 40
			box.add_child(title)
			var value := UiKit.label(String(entry.get("value", "")), "H2", true)
			value.custom_minimum_size.x = 40
			value.add_theme_font_size_override("font_size", 26)
			value.add_theme_color_override("font_color", tone)
			box.add_child(value)
			if String(entry.get("note", "")) != "":
				box.add_child(UiKit.label(String(entry["note"]), "Small", true))
		grid.resized.connect(func():
			var n := clampi(int(grid.size.x / 210.0), 1, 3)
			if grid.columns != n: grid.columns = n)
		return grid
	
	## One set of column weights across the header and all rows. Numbers stay in their lane.
	static func grid(parent: Control, headers: Array, rows: Array, weights: Array = []) -> VBoxContainer:
		var box := UiKit.vbox(2)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(box)
		var shares := weights if weights.size() == headers.size() else headers.map(func(_h): return 1.0)
		var head := RecCells.new()
		head.configure(headers, shares, headers, true, UiTheme.INK_SOFT)
		box.add_child(head)
		for row: Dictionary in rows:
			var b := RecCells.new()
			b.configure(row.get("values", []), shares, headers, false, row.get("color", UiTheme.INK))
			var tap: Callable = row.get("tap", Callable())
			if tap.is_valid():
				b.pressed.connect(tap)
				b.set_meta("rec_row", [str(row.get("values", [])), "", ""])
			else:
				b.custom_minimum_size.y = 48
			box.add_child(b)
		return box
	
	## Stock/target bars keep the exact text even above target; only the drawing saturates.
	static func meter(parent: Control, title: String, value: float, target: float, note: String = "", tone: Color = UiTheme.COPPER) -> VBoxContainer:
		var box := UiKit.vbox(3)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(box)
		var labels := UiKit.hbox(8)
		box.add_child(labels)
		var label := UiKit.label(title, "Small", true)
		UiKit.expand(label)
		labels.add_child(label)
		labels.add_child(UiKit.label("%s / %s" % [num(value), num(target)], "Small"))
		var bar := ProgressBar.new()
		bar.max_value = maxf(target, 1.0)
		bar.step = 0.0
		bar.value = value
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.add_theme_stylebox_override("background", UiTheme.sb(UiTheme.PARCH_2, UiTheme.PARCH_3, 1, 3, 0, 0))
		bar.add_theme_stylebox_override("fill", UiTheme.sb(tone, tone, 0, 3, 0, 0))
		bar.set_meta("rec_meter", {"title": title, "value": value, "target": target})
		box.add_child(bar)
		if note != "": box.add_child(UiKit.label(note, "Small", true))
		return box
	
	## Detail sections build on first opening, so a dashboard doesn't eagerly shape long logs.
	static func disclosure(parent: Control, title: String, fill: Callable) -> VBoxContainer:
		var box := UiKit.vbox(4)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(box)
		var body := UiKit.vbox(6)
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.visible = false
		var b := UiKit.button(title + "  +", func():
			if not body.has_meta("built"):
				fill.call(body)
				body.set_meta("built", true)
			body.visible = not body.visible
			var button := box.get_child(0) as Button
			button.text = title + ("  −" if body.visible else "  +"), "Row")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(b)
		box.add_child(body)
		box.set_meta("rec_disclosure", title)
		return box

class FrozenPages:
	extends RefCounted
	## Detail pages of the records screen (tap any name): family, person, business, force on the map, a unit with
	## no register record. Same rule: real fields only, "not tracked" for the rest.
	
	static func _m(v: float) -> String:
		return RecData.money(v)
	
	## "12 (3 bed-ridden)": the town's people at home in their sick phase (campaign/sickness.gd town_summary).
	static func sick_count(t: Dictionary) -> String:
		var read_town := t
		if TownEcon.has_econ(t):
			var e: Dictionary = t["econ"]
			read_town = RecCivic._read_town(t, e)
		var s := Sickness.town_summary(read_town)
		if s.is_empty():
			return FrozenKit.NT
		return "%d (%d bed-ridden)" % [int(s["sick_now"]), int(s["bed_now"])]
	
	## The town's open cases at home (caught: incubating or sick), from the sickness book's counter e.sk.act (cheap:
	## the wide lists use it; one town's own pages count who is showing it with sick_count).
	static func open_cases(t: Dictionary) -> String:
		if not TownEcon.has_econ(t):
			return FrozenKit.NT
		var act: Dictionary = (t["econ"] as Dictionary).get("sk", {}).get("act", {})
		var n := 0
		for dis in act:
			n += int(act[dis])
		return "%d" % n
	
	# ================================================================== family
	static func family(scr, t: Dictionary, fid: int, box: VBoxContainer) -> void:
		var e := RecData.econ(t)
		var f := RecData.fam(e, fid)
		if f.is_empty():
			FrozenKit.line(box, "No such family.", "Muted")
			return
		f["named"] = true   # an opened family keeps its life events from now on (economy spec 6)
		if f.get("estate", false):
			var ec := FrozenKit.card(box, "The town's own land")
			for l in Families.describe(t, e, f):
				FrozenKit.line(ec, String(l))
			return
		var st := RecData.state(f)
		var c := FrozenKit.card(box, "Condition")
		var sl := FrozenKit.line(c, "%s; hungry %d weeks in a row" % [st.capitalize(), RecData.hungry_weeks(f)])
		sl.add_theme_color_override("font_color", RecData.state_color(st))
		FrozenKit.kv(c, "Purse", _m(RecData.purse(f)))
		var inc: Variant = RecData.income_day(f)
		FrozenKit.kv(c, "Income before household expenses", (_m(float(inc)) + " a day (last week)") if inc != null else FrozenKit.NT)
		for part in f.get("income_parts", {}):
			FrozenKit.kv(c, String(part).capitalize(), _m(float(f["income_parts"][part]) / 7) + " a day (last week)")
		FrozenKit.kv(c, "Debt", _m(RecData.debt(f)) if RecData.debt(f) > 0.5 else "none")
		var s: Dictionary = f.get("store", {})
		FrozenKit.kv(c, "Stores", "food %d days, drink %d days, firewood %d days" % [int(s.get("food", 0)), int(s.get("drink", 0)), int(s.get("wood", 0))])
		var day := float(Game.day)
		Persons.sync(e, f, day)
		var members := Persons.household(e, f, day)
		var sick := members.filter(func(m): return String(m.get("sick", "")) != "")
		FrozenKit.kv(c, "Sick today", "%d of %d at home and away" % [sick.size(), members.size()] if not sick.is_empty() else "nobody")
		for k in ["Hunger % of the last 14 days", "Cold days", "Winter clothing", "Pawned goods", "Mourning", "Spent today (and on food)",
				"Food in store by kind", "Seed kept for sowing", "Rent a month and payments missed"]:
			FrozenKit.nt(c, k)
		if f.has("lodging"):
			FrozenKit.kv(c, "Rented rooms", "%d; %.1f coins a week" % [f["lodging_rooms"], TownHousing.rent_week(e, f)])
		var dc := FrozenKit.card(box, "The record")
		for l in Families.describe(t, e, f):
			if String(l).begins_with("Purse:") or String(l).begins_with("Income last week:") or String(l).begins_with("Stores:") or String(l).begins_with("Hunger:"): continue
			FrozenKit.line(dc, String(l), "Small")
		# members, eldest first
		var mc := FrozenKit.card(box, "Members", "Eldest first. Tap anyone for their own page.")
		for m in members:
			var pid := int(m["pid"])
			var wage := int(m["wage"])
			var sk := String(m.get("sick", ""))
			mc.add_child(FrozenKit.row("%s, %d, %s" % [String(m["name"]), int(m["age"]), String(m["kind"])],
				(_m(wage / 7.0) + " a day") if wage >= 0 and String(m["work"]) != "child" else "",
				"%s%s; %s%s" % [(sk + "; ") if sk != "" else "", String(m["kin"]), String(m["work"]), ("; " + Persons.SERVICE_WORDS.get(String(m["state"]), String(m["state"]))) if String(m["state"]) != "" else ""],
				func(): scr.open_person(t, fid, pid), UiTheme.BAD if sk != "" else null))
		if not Persons.pp(f).is_empty() or f.has("dp"):
			var gone := remembered(e, f)
			if not gone.is_empty():
				var gc := FrozenKit.card(box, "Remembered (dead and departed)")
				for p in gone:
					var pid2 := int(p[0])
					gc.add_child(FrozenKit.row(Persons.name_of(f, p, Persons.race_of(e)), "", departure_text(e, p), func(): scr.open_person(t, fid, pid2)))
		# animals (addendum 1 B4): the family's herds, oxen and pens
		_animals(e, RecData.family_herds(e, fid), box, "Animals", "Its herds, plough oxen and pens: each a record with its ages, herders and plots.")
		if not f.get("hives", {}).is_empty():
			var hive_card := FrozenKit.card(box, "Beehives")
			FrozenKit.line(hive_card, "%d owned hives; produced %.2f kg honey and %.2f kg wax from flowering land." % [int(f["hives"]["count"]), float(f["hives"]["honey_kg"]), float(f["hives"]["wax_kg"])])
		# loans
		var lc := FrozenKit.card(box, "Loans")
		var ll := Loans.family_line(e, f)
		FrozenKit.line(lc, ll if ll != "" else "No debt.", "" if ll != "" else "Muted")
		FrozenKit.nt(lc, "Collateral and the clerk who made the loan")
		# businesses owned
		var owns: Array = f.get("owns", [])
		if not owns.is_empty():
			var bc := FrozenKit.card(box, "Businesses owned")
			for bid in owns:
				var b: Dictionary = RecData.biz(e)[int(bid)]
				var bi := int(bid)
				bc.add_child(FrozenKit.row(RecData.biz_title(e, b).capitalize(), RecData.biz_state(b), RecData.staff_text(b) + ", till " + _m(RecData.till(b)),
					func(): scr.open_business(t, bi)))
		# life
		var hc := FrozenKit.card(box, "Life", "Newest first.")
		for l in Backstory.recent_life(t, e, f):
			FrozenKit.line(hc, String(l), "Small")
		var hist: Array = f.get("hist", []) if f.get("ev", []).is_empty() else f.get("extra_history", [])
		for i in range(hist.size() - 1, -1, -1):
			FrozenKit.line(hc, String(hist[i]), "Small")
		# the census: the family's dead with their causes
		var dead := []
		for d in Census._book(e)["deaths"]:
			if d.size() > 7 and int(d[7]) == fid:
				dead.append(d)
		if not dead.is_empty():
			var kc := FrozenKit.card(box, "Deaths in the family (census)")
			for d in dead:
				FrozenKit.line(kc, "%s: %s, %s%s" % [FrozenTown._day_word(float(d[0])), String(d[2]) if String(d[2]) != "" else "an elder", String(d[5]),
					(" (" + String(d[6]) + ")") if String(d[6]) != "" else ""], "Small")
	
	# ================================================================== person
	static func person(scr, t: Dictionary, fid: int, pid: int, box: VBoxContainer) -> void:
		var e := RecData.econ(t)
		var f := RecData.fam(e, fid)
		var p: Array = Persons.any(f, pid) if not f.is_empty() else []
		if p.is_empty():
			FrozenKit.line(box, "No record of this person.", "Muted")
			return
		var race := Persons.race_of(e)
		var day := float(Game.day)
		var alive := not Persons.by_pid(f, pid).is_empty()
		var c := FrozenKit.card(box, Persons.name_of(f, p, race))
		FrozenKit.kv(c, "Sex", ["man", "woman"][int(p[2])] if int(p[2]) in [0, 1] else "?")
		FrozenKit.kv(c, "Age", "%d" % Persons.age_of(p, day) if alive else departure_text(e, p))
		c.add_child(FrozenKit.row("The %s family" % String(f.get("name", "?")), RecData.tname(String(t["id"])), ("her household" if int(p[2]) == 1 else "his household"), func(): scr.open_family(t, fid)))
		if alive:
			var h := Persons.head_of(f)
			FrozenKit.kv(c, "Kin", Persons.kin_of(e, f, p, h))
			for m in Persons.household(e, f, day):
				if int(m["pid"]) == pid:
					FrozenKit.kv(c, "Work", String(m["work"]) + ((", %s a day" % _m(int(m["wage"]) / 7.0)) if int(m["wage"]) >= 0 and String(m["work"]) != "child" else ""))
			var st := String(p[4])
			FrozenKit.kv(c, "Now", String(Persons.SERVICE_WORDS.get(st, st)))
			var sk := Sickness.person_text(f, pid, day)
			var cs := Sickness.case_of(f, pid)
			FrozenKit.kv(c, "Sick", (sk + ("; remedy given" if int(cs[Sickness.C_REM]) == 1 else "; no remedy") + ("; bed-ridden" if int(cs[Sickness.C_BED]) == 1 else "")) if sk != "" else "no")
		else:
			var died := []
			for d in Census._book(e)["deaths"]:
				if int(d[1]) == pid:
					died = d
			if not died.is_empty():
				FrozenKit.kv(c, "Died", "%s, aged %d: %s%s" % [FrozenTown._day_word(float(died[0])), int(died[3]), String(died[5]), (" (" + String(died[6]) + ")") if String(died[6]) != "" else ""])
			else:
				FrozenKit.kv(c, "Gone", "dead or departed (the family remembers; when and how: %s)" % FrozenKit.NT)
		# rosters: his unit on the map, if any
		var u := _unit(int(p[5]))
		if u != null:
			var rc := FrozenKit.card(box, "Rosters")
			var rr := Persons.roster_row(Game, u, String(p[4]))
			FrozenKit.line(rc, "%s: %s%s, %s, %s years served, %s a day" % [String(Persons.SERVICE_WORDS.get(String(p[4]), String(p[4]))).capitalize(),
				String(rr["rank"]), "" if String(rr["rank"]) == "" else ",", String(rr["weapon"]), FrozenKit.num(float(rr["years_served"])), _m(float(rr["pay_day"]))])
			_skills(u, rc)
		else:
			FrozenKit.nt(box, "Skills from work")
		# his own past
		var lc := FrozenKit.card(box, "Life history", "Places held, service, wounds; newest first.")
		var spans := Persons.life_spans(p)
		if spans.is_empty():
			FrozenKit.line(lc, "Nothing recorded.", "Muted")
		if Legends.made_by(p) > 0:   # v0.014
			FrozenKit.kv(c, "Legendary pieces made", "%d (at most %d in a life)" % [Legends.made_by(p), Legends.CAP])
		for s in spans:
			var to := float(s["to"])
			if String(s["code"]) == "legend":   # v0.014: a legendary piece he made
				FrozenKit.line(lc, "made %s (%s)" % [String(s["arg"]), FrozenTown._day_word(float(s["from"]))], "Small")
				continue
			FrozenKit.line(lc, "%s: %s (from %s%s)" % [String(s["code"]), Backstory.job_words(String(s["arg"])) if String(s["code"]) == "job" else String(s["arg"]),
				FrozenTown._day_word(float(s["from"])), (" to " + FrozenTown._day_word(to)) if to >= 0.0 else ", still"], "Small")
	
	static func _skills(u: Unit, box: VBoxContainer) -> void:
		var ks := UnitSheet.known_skills(u)
		var sk := ks.map(func(s): return UnitSheet.skill_line(u, s))
		FrozenKit.kv(box, "Skills", ", ".join(PackedStringArray(sk)) if not sk.is_empty() else "nothing to speak of")
		FrozenKit.kv(box, "Battles, kills, renown", "%d, %d, %d" % [u.battles, u.kills, int(round(u.renown))])
	
	static func _unit(uid: int) -> Unit:
		if uid < 0:
			return null
		for u in Game.company:
			if u.uid == uid:
				return u
		for wid in Game.world.get("warbands", {}):
			for u in Game.world["warbands"][wid].get("units", []):
				if u is Unit and u.uid == uid:
					return u
		for tid in Game.world.get("towns", {}):
			for u in Game.world["towns"][tid].get("recruits", []):
				if u is Unit and u.uid == uid:
					return u
		return null
	
	## A unit with no register record (monsters, a world without towns).
	static func unit_page(scr, u: Unit, box: VBoxContainer) -> void:
		var c := FrozenKit.card(box, u.name)
		FrozenKit.kv(c, "What", "%s %s" % [UiWords.race_name(u), u.title])
		FrozenKit.kv(c, "Age", "%d" % u.age)
		_skills(u, c)
		FrozenKit.nt(c, "Register record (family, history)")
	
	# ================================================================== business
	static func business(scr, t: Dictionary, bid: int, box: VBoxContainer) -> void:
		var e := RecData.econ(t)
		var context := {"work": {}}
		var b: Dictionary = RecData.biz(e)[bid]
		var house := RecData.is_house(b)
		var c := FrozenKit.card(box, RecData.biz_title(e, b).capitalize())
		FrozenKit.kv(c, "Trade", RecData.biz_trade(b))
		var reason := String(b.get("why", ""))
		var state_text := RecData.biz_state(b)
		if house and not reason.is_empty():
			state_text += " - " + reason
		elif String(b.get("state", "")) == "inputs" and not reason.is_empty():
			state_text += ", no " + RecData.good_name(e, reason)
		FrozenKit.kv(c, "State", state_text)
		var owner := int(b.get("owner", -1))
		if owner >= 0:
			var of := RecData.fam(e, owner)
			c.add_child(FrozenKit.row("Owned by the %s family" % String(of.get("name", "?")), "", "tap for the household", func(): scr.open_family(t, owner)))
		elif house:
			FrozenKit.kv(c, "Funding", "State-funded research house")
		else:
			FrozenKit.kv(c, "Owner", "the town" + (" (for sale)" if b.get("for_sale", false) else ""))
		var hl: Variant = RecData.biz_health(b)
		if hl != null:
			var pf: Variant = RecData.biz_profit(b)
			FrozenKit.kv(c, "Health (the books)", "%s; profit %s a day over the last 14 days; %d loss days" % [String(hl), _m(float(pf)) if pf != null else "-", RecData.biz_loss_days(b)])
		var kp := RecData.keeper(e, b, context)
		if not kp.is_empty():
			var kf := int(kp["fid"]); var kpid := int(kp["pid"])
			c.add_child(FrozenKit.row((Academy.lead_title(e) + ": " if house else "Kept by ") + String(kp["name"]), "", "%s; tap for the person" % String(kp["how"]), func(): scr.open_person(t, kf, kpid)))
		else:
			FrozenKit.kv(c, Academy.lead_title(e) if house else "Kept by", "Head post vacant" if house else "nobody at work there")
		if b.has("p1"):
			FrozenKit.kv(c, "Profit yesterday", _m(float(b["p1"])) + (" (a day, this week)" if String(b["type"]) == "farm" else ""))
		FrozenKit.nt(c, "Address, rent")
		FrozenKit.kv(c, "Cash in the till", _m(RecData.till(b)))
		FrozenKit.kv(c, "Staff wage", _m(RecData.biz_wage(b)) + " a day")
		if house:
			FrozenKit.kv(c, "Head supplement", _m(RecData.biz_wage(b) * float(Academy.R().get("lead_pay", 1.0))) + " a day when the till can pay")
		FrozenKit.kv(c, "Owed in wages", _m(float(b.get("owed", 0.0))))
		var claims: Dictionary = b.get("wage_claims", {})
		var named_total := 0.0
		for fid in claims: named_total += float(claims[fid])
		var older := float(b.get("owed_unattributed", maxf(0.0, float(b.get("owed", 0.0)) - named_total)))
		if older > 0.005:
			FrozenKit.kv(c, "Older wages without a named recipient", _m(older))
			FrozenKit.line(c, "This balance is preserved from older records, which did not save who earned it.", "Muted")
		if not claims.is_empty():
			var wc := FrozenKit.card(box, "Wages still to pay", "Earned wages remain due after a worker leaves. Payments come from the business till.")
			for fid in claims:
				var household := RecData.fam(e, int(fid))
				var who := "the %s household" % String(household.get("name", "unidentified"))
				if household.get("extinct", false): who += " (estate)"
				elif household.has("moved"): who += " (moved away)"
				FrozenKit.kv(wc, who, _m(float(claims[fid])))
		FrozenKit.kv(c, "Inputs bought a day (smoothed)", _m(float(b.get("spend", 0.0))))
		FrozenKit.kv(c, "Tools", "%d sets; %d working hands (paid staff and keeper)" % [int(b.get("tools", 0)), int(b.get("workers", 0)) + int(b.get("kw", 0))])
		if house:   # v0.012: the state's research house - its lead, lines, materials and log
			var fid := String(t.get("faction", ""))
			var hc := FrozenKit.card(box, "Research", "Funded by the state each faction turn; staff hired by the normal rules; trials burn iron bars, flux stone and wood bought at the market.")
			for ln in RecData.research_lines(fid):
				FrozenKit.line(hc, ln, "Small")
			var lg: Array = RecData.research_log(fid)
			if not lg.is_empty():
				var lc := FrozenKit.card(box, "Log book", "The house's last events, newest last.")
				for ln in lg:
					FrozenKit.line(lc, String(ln), "Small")
		elif b.has("skill"):
			FrozenKit.kv(c, "Smith's skill", "%d of 15" % int(b["skill"]))
		FrozenKit.nt(c, "Cash chart, yesterday's ledger")
		var rc := FrozenKit.card(box, "Recipes", "Per worker-day, from the trade's data row. Cost per unit at today's prices: inputs only (labour and fuel per unit: not tracked).")
		for r in RecData.recipes(b):
			var ins := []; var outs := []; var cost := 0.0; var outn := 0.0; var sell := 0.0
			for g in r.get("in", {}):
				ins.append("%s %s" % [FrozenKit.num(float(r["in"][g])), RecData.good_name(e, g)])
				cost += float(r["in"][g]) * RecData.price(t, g)
			for g in r.get("out", {}):
				outs.append("%s %s" % [FrozenKit.num(float(r["out"][g])), RecData.good_name(e, g)])
				outn += float(r["out"][g]); sell += float(r["out"][g]) * RecData.price(t, g)
			var BB: Dictionary = Barge.B()["business"]
			var mg := ""
			if cost > 0.0:   # barge part 3 section 4: output at 0.92 x price against 1.03 x the inputs
				mg = "; margin %+d%%: %s" % [int(round(100.0 * (sell * float(BB["out_share"]) / cost - 1.0))),
					"pays" if sell * float(BB["out_share"]) >= float(BB["run_margin"]) * cost else "does not pay (at most %d%% of capacity)" % int(round(100.0 * float(BB["idle_cap"])))]
			FrozenKit.line(rc, "%s -> %s, %s a worker-day; inputs %s against %s at today's prices%s" % [", ".join(PackedStringArray(ins)) if not ins.is_empty() else "work",
				", ".join(PackedStringArray(outs)), FrozenKit.num(float(r.get("rate", 1.0))), _m(cost), _m(sell), mg], "Small")
		if RecData.recipes(b).is_empty():
			FrozenKit.line(rc, "No recipe: a service (the market, collectors, fields, works).", "Muted")
		var sc := FrozenKit.card(box, "Staff", RecData.staff_text(b))
		for s in RecData.staff(e, bid, context):
			var sfid := int(s["fid"]); var spid := int(s["pid"])
			sc.add_child(FrozenKit.row(String(s["name"]), _m(float(s["wage"])) + " a day", String(s["title"]), func(): scr.open_person(t, sfid, spid)))
		FrozenKit.nt(sc, "Hiring: open posts, hired, quit and let go this month")
		# herds' trades (addendum 1 B3): its own herds and its chain (where its beasts came from, where its output went)
		var bh := RecData.biz_herds(e, bid)
		if not bh.is_empty():
			_animals(e, bh, box, "Its herds", "Kept by its herdsmen (the staff above).")
		var ch := RecData.biz_chain(b)
		if not ch.is_empty() or b.has("kills"):
			var cc := FrozenKit.card(box, "The chain", "This season first, then last season: who it bought beasts from and where its output went.")
			if b.has("kills"):
				FrozenKit.kv(cc, "Beasts slaughtered since the books began", "%d" % int(b["kills"]))
			for r in ch:
				var what := String(r[2])
				var wword := RecData.herd_word(e, what) if RecData.animal_kinds().has(what) else RecData.good_name(e, what)
				FrozenKit.line(cc, "%s%s %s: %d %s" % ["" if bool(r[4]) else "(last season) ", "From" if String(r[0]) == "from" else "To", String(r[1]), int(r[3]), wword], "Small")
		FrozenKit.nt(box, "Last 10 events of the business")
	
	## A list of herd records: kind and head, ages, owner, herders (register persons), plots, hay, hunger.
	static func _animals(e: Dictionary, hl: Array, box: VBoxContainer, title: String, note: String) -> void:
		if hl.is_empty():
			return
		var ac := FrozenKit.card(box, title, note)
		for h in hl:
			var hh: Dictionary = h
			var nm := []
			for p in RecData.herders(e, hh).slice(0, 3):
				nm.append(String(p["name"]))
			FrozenKit.kv(ac, RecData.herd_n(e, RecData.herd_head(hh), String(hh["k"])).capitalize(), "%d young, %d grown, %d old; herded by %s; %d plots; %s bales of hay%s" % [
				int(hh["y"]), int(hh["g"]), int(hh["o"]), ", ".join(PackedStringArray(nm)) if not nm.is_empty() else "nobody named", (hh["pl"] as Array).size(),
				FrozenKit.num(float(hh["fod"])), (("; short of feed %d days" % int(hh["hun"])) if int(hh["hun"]) > 0 else "") + RecData.herd_state(hh)])
	
	# ================================================================== forces on the map
	static func force_name(wb: Dictionary) -> String:
		var kind := String(wb.get("kind", ""))
		var fid := String(wb.get("faction", ""))
		match kind:
			"caravan": return "Caravan of %s" % RecData.tname(String(wb.get("origin", wb.get("home", ""))))
			"militia": return "The militia of %s" % RecData.tname(String(wb.get("home", "")))
		var mk := Monsters.kind_text(wb)
		if mk != "":
			return mk.capitalize()
		return "%s %s" % [UiWords.faction_name(fid), kind]
	
	static func force(scr, wid: String, box: VBoxContainer) -> void:
		var w: Dictionary = Game.world
		var wb: Dictionary = w["warbands"].get(wid, {})
		if wb.is_empty():
			FrozenKit.line(box, "Gone from the map.", "Muted")
			return
		var c := FrozenKit.card(box, force_name(wb))
		var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
		FrozenKit.kv(c, "Kind", String(wb.get("kind", "")))
		FrozenKit.kv(c, "Owner", UiWords.faction_name(String(wb.get("faction", ""))))
		var home := String(wb.get("home", ""))
		if RecData.town(home).has("econ"):
			c.add_child(FrozenKit.row("Home: %s" % RecData.tname(home), "", "tap for the town", func(): scr.open_town(home)))
		FrozenKit.kv(c, "Near", CampaignWorld.nearest_town_name(w, wb["pos"]))
		FrozenKit.kv(c, "Men", "%d" % units.size())
		FrozenKit.kv(c, "Strength", FrozenKit.num(CampaignWorld.band_power(units)))
		if String(wb.get("kind", "")) == "caravan":
			FrozenKit.line(c, Caravans.describe(w, wb))
		FrozenKit.kv(c, "Doing", WarAI.mode_text(wb) if wb.has("mode") else String(wb.get("state", "")))
		var bl := ArmyPanel.band_line(wb)
		if bl != "":
			FrozenKit.line(c, bl, "Small")
		var rows := []
		var role := String({"caravan": "caravan", "militia": "militia"}.get(String(wb.get("kind", "")), "army"))
		for u in units:
			var uu: Unit = u
			var rr := Persons.roster_row(Game, uu, role)
			rows.append({"name": uu.name, "rk": uu.rank, "age": int(rr["age"]), "renown": float(uu.renown),
				"_l": ("%s %s" % [String(rr["rank"]).capitalize(), uu.name]).strip_edges(), "_r": String(rr["weapon"]),
				"_d": "%s; age %d; %s" % [("the %s of %s" % [rr["household"], rr["town"]]) if String(rr["household"]) != "" else "no register record", int(rr["age"]),
					("%s a day" % _m(float(rr["pay_day"]))) if float(rr["pay_day"]) > 0.0 else "unpaid or no pay"],
				"_s": uu.name, "_tap": func(): scr.open_unit(uu)})
		var rc := FrozenKit.card(box, "Roster")
		rc.add_child(FrozenTable.make([{"k": "rk", "t": "Rank", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
			{"k": "renown", "t": "Renown", "num": true}], rows, "rk", false, [], true))
	
	static func remembered(e: Dictionary, f: Dictionary) -> Array:
		var out := []
		var living := {}
		for family in e.get("fams", []):
			if family.get("gone", false): continue
			for p in Persons.pp(family) + Persons.kp(family): living[int(p[0])] = true
		for p in f.get("dp", []):
			if not living.has(int(p[0])): out.append(p)
		return out
	
	static func departure_text(e: Dictionary, p: Array) -> String:
		for d in Census._book(e)["deaths"]:
			if int(d[1]) == int(p[0]):
				return "died aged %d, %s: %s" % [int(d[3]), FrozenTown._day_word(float(d[0])), String(d[5])]
		return "departed; aged %d at the current date" % Persons.age_of(p, float(Game.day))
