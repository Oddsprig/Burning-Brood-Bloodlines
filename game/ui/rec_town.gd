class_name RecTown
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
		RecKit.line(v, "Nobody here keeps accounts.", "Muted")
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
	RecKit.metrics(v, [
		{"title": "People", "value": UiKit.thousands(Census.people(e)), "note": "%d families" % families.size(), "color": UiTheme.BLUE},
		{"title": "Food", "value": "%d days" % int(supply), "note": "Last famine stage: " + RecData.stage_word(RecData.town_stage(e)).capitalize(), "color": UiTheme.BAD if supply_level == "starving" else (UiTheme.WARN if supply_level == "short" else UiTheme.GOOD)},
		{"title": "Treasury", "value": _m(RecData.treasury(e)), "note": "Town chest", "color": UiTheme.COPPER}])
	var c := RecKit.card(v, "At a glance")
	var dw: Variant = RecData.day_wage(e)
	var ls := RecData.land(e)
	RecKit.grid(c, ["Measure", "Now", "Context"], [
		{"values": ["Adults working", "%d / %d" % [adults - idle, adults], "%d without work" % idle], "tap": func(): scr.show_tab("Hardship")},
		{"values": ["Day wage", _m(float(dw)) if dw != null else RecKit.NT, "Labourer's day"]},
		{"values": ["Price level", "x%.2f" % RecData.price_level(e), "%s coin shortage" % RecKit.pct(RecData.coin_short(e), 1.0)]},
		{"values": ["Territory", "%d acres" % int(ls["territory"]), "%d family-owned" % int(ls["families"])], "tap": func(): scr.show_tab("Land & Homes")}
	], [1.5, 1.1, 1.5])
	var hd := RecData.head(e)
	c.add_child(RecKit.row("%s %s" % [String(hd.get("title", "head")).capitalize(), String(hd.get("name", "?"))], "Household", "Town head · open family record", func(): scr.open_family(t, int(hd.get("fam", 0)))))
	var reserves := RecKit.card(v, "Supply reserves")
	RecKit.grid(reserves, ["Supply", "Days", "Where"], [
		{"values": ["Food", str(int(supply)), "Market + barns + homes + granary"]},
		{"values": [RecData.good_name(e, "beer").capitalize(), str(int(RecData.days_of(e, "beer"))), "Market + homes"]},
		{"values": [RecData.good_name(e, "wine").capitalize(), str(int(RecData.days_of(e, "wine"))), "Market + homes"]},
		{"values": ["Firewood", str(int(RecData.days_of(e, "wood"))), "Market + homes"]}
	], [1.5, 0.6, 2.0])
	RecKit.meter(reserves, "Public granary", RecData.granary(e), RecData.granary_target(e), "Food equivalents · stored / target", UiTheme.COPPER)
	var homes := RecKit.card(v, "Household condition", "Each family appears once, under its most serious condition. Select a row to open the Register.")
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
		rows.append({"values": [key.capitalize(), str(fs.size()), str(ppl), _m(purse / fs.size()) if not fs.is_empty() else "—", RecKit.pct(hungry, fs.size())],
			"color": RecData.state_color(key) if not fs.is_empty() else RecKit.GREY, "tap": func(): scr.goto_tab("Register", {"State": key})})
	RecKit.grid(homes, ["Condition", "Families", "People", "Avg purse", "Hungry"], rows, [1.7, 0.8, 0.8, 1.3, 0.8])
	var links := RecKit.card(v, "Town services")
	links.add_child(RecKit.row("Sick now", RecPages.sick_count(t), "Open Sickness", func(): scr.show_tab("Sickness")))
	links.add_child(RecKit.row("Garrison", "%d defenders" % TownDefence.garrison(Game, String(t["id"])).size(), "Guards, militia and stored equipment", func(): scr.show_tab("Garrison")))
	RecKit.disclosure(v, "Full town accounts, classes, herds & stories", func(box): overview_details(scr, t, e, box))

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
	var c := RecKit.card(v, "The town")
	RecKit.kv(c, "People", "%d in %d families" % [Census.people(e), fams.size()])
	RecKit.kv(c, "Adults working", "%s (%d of %d; %d without work)" % [RecKit.pct(adults - idle, adults), adults - idle, adults, idle])
	var dw: Variant = RecData.day_wage(e)
	RecKit.kv(c, "Day wage (a labourer's day)", _m(float(dw)) if dw != null else RecKit.NT)
	RecKit.kv(c, "Price level", "x%.2f (the realm's money: x1.00 = as the world began); coin short %s" % [RecData.price_level(e), RecKit.pct(RecData.coin_short(e), 1.0)])
	RecKit.kv(c, "Famine stage", RecData.stage_word(RecData.town_stage(e)))
	var ls := RecData.land(e)
	RecKit.kv(c, "Land", "%d acres in the territory (families %d, the town %d, unclaimed %d)" % [int(ls["territory"]), int(ls["families"]), int(ls["estate"]), int(ls["common"])])
	RecKit.kv(c, "Treasury", _m(RecData.treasury(e)))
	c.add_child(RecKit.row("Sick now", RecPages.sick_count(t), "bed-ridden, new this week, the diseases: tap for the Sickness tab", func(): scr.show_tab("Sickness")))
	var hd := RecData.head(e)
	c.add_child(RecKit.row("%s %s" % [String(hd.get("title", "head")).capitalize(), String(hd.get("name", "?"))], "head of the town",
		"of the %s family: tap for the household" % String(RecData.fam(e, int(hd.get("fam", 0))).get("name", "?")), func(): scr.open_family(t, int(hd.get("fam", 0)))))
	RecKit.kv(c, "Food price index", "x%.2f (x1.00 = normal; grain, fruit and meat by the diet)" % RecData.food_index(t))
	RecKit.kv(c, "Staple index (grain)", "x%.2f" % RecData.staple_index(t))
	var hfv: Variant = RecData.harvest_factor(e)
	RecKit.kv(c, "This year's harvest factor (weather)", ("x%.2f (x1.00 = a normal year)" % float(hfv)) if hfv != null else RecKit.NT)
	RecKit.kv(c, "Grain held in barns", "%d meals' worth" % RecData.barn(e, "grain"))
	# families by class (real purses)
	var cc := RecKit.card(v, "Families by class", "The town's own classes (by savings and holdings, each week).")
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
		cc.add_child(RecKit.row(cls.capitalize(), "%d families" % fs.size(),
			"%d people, income %s a day per person, savings %s on average, hungry %s, food share: %s" % [ppl,
			_m(inc / incn) if incn > 0 else "-", _m(sav / fs.size()) if not fs.is_empty() else "-", RecKit.pct(hung, fs.size()), RecKit.NT],
			func(): scr.goto_tab("Register", {"Class": cls})))
	# days of supply
	var sc := RecKit.card(v, "Days of supply")
	RecKit.kv(sc, "Food", "%d days" % int(RecData.days_food(t)))
	for g in ["beer", "wine"]:
		RecKit.kv(sc, RecData.good_name(e, g).capitalize(), "%d days" % int(RecData.days_of(e, g)))
	RecKit.kv(sc, "Firewood", "%d days" % int(RecData.days_of(e, "wood")))
	RecKit.kv(sc, "Granary", "%d of a %d target (meals' worth)" % [RecData.granary(e), RecData.granary_target(e)])
	var gt := RecData.granary_today(e)
	if gt.is_empty() or int(gt[0]) != int(e.get("day", -1)):
		RecKit.kv(sc, "Granary today", "neither buying nor selling")
	elif int(gt[1]) < 0:
		RecKit.kv(sc, "Granary today", "selling %d meals' worth at %s a meal (relief price)" % [-int(gt[1]), _m(float(gt[2]))])
	elif int(gt[1]) > 0:
		RecKit.kv(sc, "Granary today", "buying %d meals' worth at %s a meal" % [int(gt[1]), _m(float(gt[2]))])
	else:
		RecKit.kv(sc, "Granary today", "neither buying nor selling")
	for line in TownEconTab.stores_lines(t):
		if String(line).contains("bars"):
			RecKit.line(sc, String(line))
	RecKit.kv(sc, "Wood", "%d loads in the market, %s burned a day by the homes" % [RecData.stock(e, "wood"), RecKit.num(RecData.household_use(e, "wood"))])
	RecKit.nt(sc, "Wood cut a day")
	RecKit.nt(sc, "Timber held for building")
	# families by state
	var stc := RecKit.card(v, "Families by state", "The worst real state of each family. Tap a row for the Register filtered to it.")
	for s in RecData.STATES:
		var fs2: Array = by_state[s]
		var ppl2 := 0; var sav2 := 0.0; var h2 := 0
		for f in fs2:
			ppl2 += RecData.people(f); sav2 += RecData.purse(f)
			if RecData.hungry_weeks(f) > 0: h2 += 1
		var ss := String(s)
		stc.add_child(RecKit.row(ss.capitalize(), "%d" % fs2.size(), "%d people, purse %s on average, hungry %s" % [ppl2,
			_m(sav2 / fs2.size()) if not fs2.is_empty() else "-", RecKit.pct(h2, fs2.size())], func(): scr.goto_tab("Register", {"State": ss}),
			RecData.state_color(ss)))
	# herds (addendum 1, B4): the records
	_herds_card(scr, t, e, v)
	# town buildings (addendum 1, A)
	_buildings(scr, t, e, v)
	# forces
	var fc := RecKit.card(v, "Forces")
	var mil := Militia.units_of(Game, String(t["id"]))
	fc.add_child(RecKit.row("The %s" % Army.town_tier(t), "%d men" % mil.size(), "paid from the treasury: tap the Garrison tab", func(): scr.show_tab("Garrison")))
	RecKit.kv(fc, "Recruits on offer at the tavern", "%d" % (t.get("recruits", []) as Array).size())
	var cars := _caravans_of(String(t["id"]))
	RecKit.kv(fc, "Caravans of this town on the road today", "%d" % cars.size())
	RecKit.nt(fc, "Caravans sent this week")
	# latest stories
	var st := RecKit.card(v, "Latest stories", "The town's own record of what befell it, newest first.")
	var hist: Array = e.get("hist", [])
	if hist.is_empty():
		RecKit.line(st, "Nothing noted yet.", "Muted")
	for i in range(hist.size() - 1, maxi(-1, hist.size() - 11), -1):
		var txt := String(hist[i])
		st.add_child(RecKit.row(txt.substr(0, 60), "", txt, func(): scr.page("A story of %s" % t["name"], func(b): RecKit.line(b, txt))))
	var lost: Array = e.get("legends_lost", [])   # v0.014: the town never forgets a legendary piece it lost
	if not lost.is_empty():
		var lc := RecKit.card(v, "Legendary pieces lost", "Carried by its people and taken by the enemy when they fell.")
		for x in lost:
			RecKit.line(lc, "%s: %s, when %s fell (taken by %s)" % [RecTown._day_word(float(x[0])), String(x[1]), String(x[2]), String(x[3])], "Small")

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
	var hc := RecKit.card(v, "Herds", "Every beast is counted in a herd with an owner; tap for the herds.")
	var fd: Variant = RecData.fodder_days(e)
	hc.add_child(RecKit.row("Herds", "%d herds" % RecData.herd_records(e).size(), "%s; fodder days left: %s" % [herd_text(e, RecData.herds(e)),
		("%d (own hay, the barns' and the market's hay and straw at the herds' feed)" % int(float(fd))) if fd != null else "no grazing beasts"],
		func(): scr.page("Herds of %s" % t["name"], func(b): herds_page(scr, t, e, b))))
	var bk := RecData.herd_book(e, "yr")
	RecKit.kv(hc, "This year", _book_text(bk))
	RecKit.kv(hc, "Manure on the fields", "x%.3f field yield" % RecData.manure_factor(e))

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
	var c := RecKit.card(box, "By kind", "Young, grown and old; the price of a grown head; offered, wanted and sold last week.")
	var ages := RecData.herd_ages(e)
	var wk := RecData.animals_week(e)
	for k in HERD_ORDER:
		if not ages.has(k):
			continue
		var a: Array = ages[k]
		RecKit.kv(c, RecData.herd_word(e, k).capitalize(), "%d young, %d grown, %d old; %s a head; offered %d, wanted %d, sold %d" % [int(a[0]), int(a[1]), int(a[2]),
			_m(RecData.animal_price(e, k)), int(wk.get("offered", {}).get(k, 0)), int(wk.get("wanted", {}).get(k, 0)), int(wk.get("sold", {}).get(k, 0))])
	var bc := RecKit.card(box, "The herd book")
	RecKit.kv(bc, "This year", _book_text(RecData.herd_book(e, "yr")))
	RecKit.kv(bc, "Last year", _book_text(RecData.herd_book(e, "ly")))
	RecKit.kv(bc, "Since the records began", _book_text(RecData.herd_book(e, "tot")))
	var rows := []
	for h in RecData.herd_records(e):
		var hh: Dictionary = h
		var fid := RecData.herd_owner_fid(e, hh)
		rows.append({"kind": RecData.herd_word(e, String(hh["k"])), "head": RecData.herd_head(hh), "owner": RecData.herd_owner(e, hh),
			"_l": "%s %s" % [RecData.herd_head(hh), RecData.herd_word(e, String(hh["k"]))], "_r": RecData.herd_owner(e, hh),
			"_d": func(): return _herd_details(e, hh),
			"_tap": (func(): scr.open_family(t, fid)) if fid > 0 else Callable()})
	box.add_child(RecTable.make([{"k": "kind", "t": "Kind"}, {"k": "head", "t": "Head", "num": true}, {"k": "owner", "t": "Owner"}], rows, "head", false))
	var lc := RecKit.card(box, "The latest changes", "Every change to a herd: births, deaths with their cause, slaughter, sales and theft.")
	var lg := RecData.herd_log(e)
	for i in range(lg.size() - 1, maxi(-1, lg.size() - 31), -1):
		var r: Array = lg[i]
		RecKit.line(lc, "%s: %s %+d %s%s" % [_day_word(float(r[0])), String(r[4]), int(r[3]), RecData.herd_word(e, String(r[2])),
			(" (" + String(r[5]) + ")") if String(r[5]) != "" else ""])
	if lg.is_empty():
		RecKit.line(lc, "Nothing yet.", "Muted")

## One herd's grey line: ages, herders (register persons), hay, plots, hunger.
static func _herd_details(e: Dictionary, hh: Dictionary) -> String:
	var nm := []
	for p in RecData.herders(e, hh).slice(0, 3):
		nm.append(String(p["name"]))
	return "%d young, %d grown, %d old; herded by %s; %s bales of hay; %d plots%s" % [int(hh["y"]), int(hh["g"]), int(hh["o"]),
		", ".join(PackedStringArray(nm)) if not nm.is_empty() else "nobody named", RecKit.num(float(hh["fod"])), (hh["pl"] as Array).size(),
		(("; short of feed %d days" % int(hh["hun"])) if int(hh["hun"]) > 0 else "") + RecData.herd_state(hh)]

## Addendum 1 B4: live animals, their own row group in Raw: the price of a grown head, offered / wanted / sold last
## week, head in the town.
static func _animals_rows(scr, t: Dictionary, e: Dictionary, box: VBoxContainer) -> void:
	var c := RecKit.card(box, "Live animals", "Bought and sold between owners, butchers and drovers at the town's price (a grown head; young and old cheaper).")
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
	c.add_child(RecTable.make([{"k": "kind", "t": "Animal"}, {"k": "price", "t": "Price", "num": true}, {"k": "xbase", "t": "x base", "num": true},
		{"k": "head", "t": "Head", "num": true}, {"k": "off", "t": "Offered", "num": true}, {"k": "sold", "t": "Sold", "num": true}], rows, "kind"))

## Addendum 1 A: the town's own buildings. Only what the sim runs today has numbers; the rest wait for state plots.
static func _buildings(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	# the town's own buildings are state plots (campaign/plots.gd); each row: what it is doing now and who runs it
	var c := RecKit.card(v, "Town buildings", "The town's own buildings on its land; tap for who runs it.")
	var view := _records_read(t, e)
	for b in Plots.buildings(view, view.world["towns"][String(t["id"])]):
		var r: Dictionary = b.get("runner", {})
		var who := String(r.get("name", "")) if not r.is_empty() else "nobody named"
		var fid := int(r.get("fid", 0)) if not r.is_empty() else -1
		c.add_child(RecKit.row(String(b["name"]).capitalize(), who, String(b.get("now", "")),
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
	var c := RecKit.card(v, "Market by kind", "Stock in the market, days of supply at today's demand, and the biggest price move in a week.")
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
		c.add_child(RecKit.row(String(cat[1]), "%d" % stock, "%s days%s%s" % [RecKit.num(stock / dem) if dem > 0.0 else "-",
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
			c.add_child(RecKit.row("Raw: live animals", "%d" % tot0, "%s; offered %d, sold %d last week" % [herd_text(e, hs0), off, sold],
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
				("%+d%%" % int(round(float(ch)))) if ch != null else "-", st, RecKit.num(st / dem) if dem > 0.0 else "-", RecKit.num(dem), RecKit.NT,
				(". " + why) if why != "" else ""],
			"_col": (UiTheme.BAD if float(ch) > 5.0 else (UiTheme.GOOD if float(ch) < -5.0 else UiTheme.INK)) if ch != null else UiTheme.INK,
			"_tap": func(): scr.page(RecData.good_name(e, gg).capitalize(), func(b): _good_page(scr, t, e, gg, b))})
	box.add_child(RecTable.make([{"k": "good", "t": "Good"}, {"k": "price", "t": "Price", "num": true}, {"k": "xbase", "t": "x base", "num": true},
		{"k": "chg", "t": "7-day %", "num": true}, {"k": "stock", "t": "Stock", "num": true}, {"k": "days", "t": "Days", "num": true},
		{"k": "dem", "t": "Demand", "num": true}], rows, "good"))

static func _good_page(scr, t: Dictionary, e: Dictionary, g: String, box: VBoxContainer) -> void:
	var c := RecKit.card(box, "Price")
	RecKit.kv(c, "Today", _m(RecData.price(t, g)))
	var pw: Variant = RecData.price_week_ago(e, g)
	RecKit.kv(c, "A week ago", _m(float(pw)) if pw != null else RecKit.NT)
	if g == "grain":
		var buf: Dictionary = e.get("census", {}).get("buf", {})
		RecKit.chart(c, "Grain price, last 60 days", buf.get("d", []), buf.get("grain", []), " " + RecData.MONEY)
	else:
		RecKit.nt(c, "Price chart (only grain keeps a 60-day buffer)")
	var why := RecData.price_why(e, g)
	if why != "":
		RecKit.kv(c, "Why it moved", why)
	var pc := RecKit.card(box, "Businesses making it")
	var any := false
	for b in RecData.biz(e):
		if b.get("closed", false):
			continue
		for r in RecData.recipes(b):
			if (r.get("out", {}) as Dictionary).has(g):
				any = true
				var bid := int(b["id"])
				pc.add_child(RecKit.row(RecData.biz_title(e, b).capitalize(), RecData.biz_state(b), RecData.staff_text(b),
					func(): scr.open_business(t, bid)))
				break
	if not any:
		RecKit.line(pc, "None in this town.", "Muted")
	var cc := RecKit.card(box, "Caravans carrying it")
	var anyc := false
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		if String(wb.get("kind", "")) == "caravan" and int(wb.get("cargo", {}).get("goods", {}).get(g, 0)) > 0 \
				and (String(wb.get("origin", "")) == String(t["id"]) or String(wb.get("dest", "")) == String(t["id"])):
			anyc = true
			var w2 := String(wid)
			cc.add_child(RecKit.row(RecPages.force_name(wb), "%d" % int(wb["cargo"]["goods"][g]), Caravans.describe(Game.world, wb), func(): scr.open_force(w2)))
	if not anyc:
		RecKit.line(cc, "None on the road to or from here.", "Muted")

## Arms on the stalls: material x quality (counts and the average price), and the armory apart.
static func _arms_grid(t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var c := RecKit.card(v, "Arms and armour by material and quality", "Counts on the market stalls, average price in brackets.")
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
		RecKit.line(c, "The stalls are bare.", "Muted")
	for mat in mats:
		var parts := []
		for q in 6:
			var cell: Array = cells.get("%s|%d" % [mat, q], [0, 0.0])
			parts.append("%s %d%s" % [DB.QUALITY_NAMES[q] if q < DB.QUALITY_NAMES.size() else str(q), int(cell[0]),
				(" (%s)" % RecKit.num(float(cell[1]) / int(cell[0]))) if int(cell[0]) > 0 else ""])
		RecKit.line(c, "%s: %s" % [String(mat).capitalize(), ", ".join(PackedStringArray(parts))])
	var al := ArmsTrade.armory_lines(t)
	RecKit.kv(c, "The %s's armory (stock vs target)" % String(RecData.head(e).get("title", "head")), "; ".join(PackedStringArray(al)) if not al.is_empty() else "empty, nothing wanted")
	for ln in ArmsTrade.armory_log(t):   # v0.014: the armory log (why the militia and guards go short)
		RecKit.line(c, String(ln))

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
	var hp := ("%s, profit %s a day over 14 days, %d loss days" % [String(hl), _m(float(pf)) if pf != null else "-", RecData.biz_loss_days(b)]) if hl != null else RecKit.NT
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
	RecKit.metrics(v, [
		{"title": "Listed businesses", "value": str(rows.size()), "note": "Including keeper-run trades", "color": UiTheme.BLUE},
		{"title": "Working", "value": str(rows.filter(func(r): return r["state"] == RecData.biz_state({"state": "busy"})).size()), "note": "Current production state", "color": UiTheme.GOOD},
		{"title": "Closed", "value": str(RecData.biz(e).filter(func(b): return b.get("closed", false)).size()), "note": "Closed ledger below", "color": UiTheme.WARN}])
	var table := RecTable.make([{"k": "name", "t": "Name"}, {"k": "trade", "t": "Trade"}, {"k": "owner", "t": "Owner"},
		{"k": "state", "t": "State"}, {"k": "staff", "t": "Staff", "num": true}, {"k": "cash", "t": "Cash", "num": true},
		{"k": "wage", "t": "Wage", "num": true}], rows, "trade", true,
		[{"t": "State", "opts": states, "fn": func(r, o): return r["state"] == o}], true, RecTable.LIMIT,
		[{"k": "name", "t": "Business", "w": 2.6}, {"k": "state", "t": "Status", "w": 1.5}, {"k": "staff", "t": "At work", "w": 0.8}, {"k": "cash", "t": "Till", "w": 1.0}, {"k": "wage", "t": "Wage/day", "w": 1.0}])
	RecKit.card(v, "Businesses").add_child(table)
	var cc := RecKit.card(v, "Closed")
	var closed := RecData.biz(e).filter(func(b): return b.get("closed", false))
	if closed.is_empty():
		RecKit.line(cc, "None.", "Muted")
	for b in closed:
		var bid2 := int(b["id"])
		cc.add_child(RecKit.row(RecData.biz_title(e, b).capitalize(), "closed", "%s; for sale: %s; when: %s" % [RecData.biz_trade(b),
			"yes" if b.get("for_sale", false) else "no", RecKit.NT], func(): scr.open_business(t, bid2)))

# ================================================================== 5. REGISTER
static func register(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var read_town := RecCivic._read_town(t, e)
	var c := People.census(read_town["econ"])
	RecKit.metrics(v, [
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
				_m(float(inc)) if inc != null else "-", RecData.stage_word(RecData.fam_stage(family)), RecKit.num(RecData.days_short(family)), ("; owes %s" % _m(RecData.debt(family))) if RecData.debt(family) > 0.5 else "",
				("; %d for hire" % hire) if hire > 0 else "", "none" if RecData.homeless(family) else ("%d, address %s" % [int(family.get("homes", 0)), RecKit.NT])],
			"_col": UiTheme.BAD if RecData.purse(f) < 0.0 else RecData.state_color(st), "_s": String(f["name"]),
			"_tap": func(): scr.open_family(t, fid)})
	var tbl := RecTable.make([{"k": "name", "t": "Family"}, {"k": "class", "t": "Class"}, {"k": "state", "t": "State"},
		{"k": "people", "t": "People", "num": true}, {"k": "purse", "t": "Purse", "num": true}, {"k": "income", "t": "Income", "num": true},
		{"k": "hungry", "t": "Hunger", "num": true}, {"k": "debt", "t": "Debt", "num": true}, {"k": "sick", "t": "Sick", "num": true}], rows, "name", true,
		[{"t": "Class", "opts": ["all", "poor", "middling", "rich"], "fn": func(r, o): return r["class"] == o},
		{"t": "State", "opts": ["all"] + RecData.STATES, "fn": func(r, o): return r["state"] == o},
		{"t": "Only", "opts": ["all", "homeless", "for hire", "in debt", "hungry", "sick"], "fn": func(r, o): return _only(r, o)}], true, RecTable.LIMIT,
		[{"k": "name", "t": "Family", "w": 1.6}, {"k": "state", "t": "Condition", "w": 1.4}, {"k": "people", "t": "People", "w": 0.7}, {"k": "purse", "t": "Purse", "w": 1.1}, {"k": "income", "t": "Income/day", "w": 1.1}])
	RecKit.card(v, "Household register").add_child(tbl)
	for k in scr.preset:
		tbl.preset(String(k), String(scr.preset[k]))
	RecKit.disclosure(v, "Register totals & definitions", func(box):
		RecKit.grid(box, ["People", "Count"], [{"values": ["Female", str(int(c["female"]))]}, {"values": ["Male", str(int(c["male"]))]}, {"values": ["Sick", RecPages.sick_count(t)]}], [2, 1])
		RecKit.nt(box, "Hunger % of the last 14 days, cold, mourning")
		RecKit.line(box, "Income is household income per day. Purse is current coin. Hunger counts consecutive hungry weeks. The condition uses each family's worst current state.", "Small"))

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
	var c := RecKit.card(v, "Land")
	RecKit.kv(c, "Owned by the families", "%d acres%s" % [int(ls["families"]), _crops(e, ls["fam_crops"])])
	RecKit.kv(c, "Held by the town (offered for sale)", "%d acres%s" % [int(ls["estate"]), _crops(e, ls["est_crops"])])
	RecKit.kv(c, "Unclaimed or common", "%d acres" % int(ls["common"]))
	c.add_child(RecKit.row("Herds", "%d herds" % RecData.herd_records(e).size(), herd_text(e, RecData.herds(e)),
		func(): scr.page("Herds of %s" % t["name"], func(b): herds_page(scr, t, e, b))))
	RecKit.nt(c, "Pasture and woodland acres")
	# ------------------------------------------------ LAND MAP SLOT: the land helper's map view (ui/land_map.gd) mounts here
	var slot := RecKit.card(v, "Land map")
	slot.name = LAND_MAP_SLOT
	slot.set_meta("town_id", String(t["id"]))
	# the map opens full screen (built on tap: keeps the tab switch fast and the tab phone-width)
	RecKit.line(slot, "Every plot on the town's land book, tile by tile.", "Muted")
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
	var oc := RecKit.card(v, "By owner")
	oc.add_child(RecTable.make([{"k": "name", "t": "Family"}, {"k": "acres", "t": "Acres", "num": true}, {"k": "head", "t": "Herd head", "num": true}],
		rows, "acres", false, [], true, 10))
	# homes
	var hc := RecKit.card(v, "Homes")
	RecKit.kv(hc, "Homes held by families", "%d" % int(e.get("homes", 0)))
	RecKit.kv(hc, "Empty (held by the town)", "%d" % RecData.empty_homes(e))
	RecKit.kv(hc, "New homes for sale in the market", "%d at %s" % [RecData.homes_for_sale(e), _m(RecData.price(t, "home"))])
	RecKit.kv(hc, "Value index", "x%.2f (market price of a new home over its base)" % (RecData.price(t, "home") / RecData.base_price("home")))
	RecKit.nt(hc, "Seized homes, rent this month, one record per home (kind, condition, mortgage)")
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
	hc.add_child(RecTable.make([{"k": "name", "t": "Household"}, {"k": "homes", "t": "Homes", "num": true}, {"k": "cond", "t": "Repair", "num": true},
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
	var bc := RecKit.card(v, "Balance since the last census")
	var ok := Census.adds_up(bal)
	var bl := RecKit.line(bc, "%d born - %d died + %d arrived - %d left = %+d; people %d at the last census, %d now (%+d)%s" % [int(bal["births"]),
		int(bal["deaths"]), int(bal["arrived"]), int(bal["left"]), int(bal["births"]) - int(bal["deaths"]) + int(bal["arrived"]) - int(bal["left"]),
		int(bal["last"]), int(bal["people"]), int(bal["change"]), "" if ok else "  DOES NOT ADD UP"])
	if not ok:
		bl.add_theme_color_override("font_color", UiTheme.BAD)
	# population chart
	var pc := RecKit.card(v, "Population at each season's census")
	var xs := []; var ys := []
	for r in seasons:
		xs.append(int(r["stamp"])); ys.append(int(r["people"]))
	RecKit.chart(pc, "People", xs, ys, "", "seasons")
	# the season table
	var tc := RecKit.card(v, "Each season's census", "The first row is the count the record starts from; its births and deaths are the world before it.")
	tc.add_child(seasons_table(scr, w, tids))
	# births and deaths
	var bd := RecKit.card(v, "Births and deaths", "Every death has one cause, set by what killed him. Tap a cause for the dead.")
	var bx := []; var by := []; var dy := []
	for r in seasons:
		bx.append(int(r["stamp"])); by.append(int(r["births"])); dy.append(Census.sum(r["deaths"]))
	RecKit.chart(bd, "Births per season", bx, by, "", "seasons")
	RecKit.chart(bd, "Deaths per season", bx, dy, "", "seasons")
	var dd := _daily(w, tids)
	RecKit.chart(bd, "Deaths a day, last 60 days", dd["d"], dd["deaths"], "")
	var causes := Census.causes_of(w, tids)
	for cause in Census.CAUSES:
		var cs := String(cause)
		var now := int(causes["now"].get(cs, 0)); var last := int(causes["last"].get(cs, 0))
		bd.add_child(RecKit.row(cs.capitalize(), "%d this season" % now, "last season %d; %s per 1,000 people this season" % [last, RecKit.per_k(now, people_now)],
			func(): scr.page("Died of %s" % cs, func(b): dead_list(scr, w, tids, cs, b))))
	var aw := 0
	for tid in tids:
		aw += Census.sum(Census.current(w["towns"][tid]["econ"])["away"])
	RecKit.kv(bd, "Company men of here who died this season (not in the count)", "%d" % aw)
	_sick_card(w, tids, v)
	# coming and going
	var cg := RecKit.card(v, "Coming and going", "This season so far. Families who move walk to a real town (named below); company recruits and men from the countryside have no town.")
	var left := {}; var arr := {}
	for tid in tids:
		var cur := Census.current(w["towns"][tid]["econ"])
		for k in cur["left"]:
			left[k] = int(left.get(k, 0)) + int(cur["left"][k])
		for k in cur["arrived"]:
			arr[k] = int(arr.get(k, 0)) + int(cur["arrived"][k])
	RecKit.kv(cg, "Left", _whys(left))
	RecKit.kv(cg, "Arrived", _whys(arr))
	var mv := []
	for tid in tids:
		for m in Census._book(w["towns"][tid]["econ"])["moves"]:
			mv.append([m, tid])
	mv.sort_custom(func(a, b): return float(a[0][0]) > float(b[0][0]))
	for i in mini(mv.size(), 12):
		var m: Array = mv[i][0]
		var other := String(m[3])
		RecKit.line(cg, "%s: %d %s %s, %s (%s %s)" % [_day_word(float(m[0])), int(m[5]) if m.size() > 5 else 1, "left" if m[2] == "out" else "arrived in",
			RecData.tname(String(mv[i][1])), String(m[4]), "to" if m[2] == "out" else "from", other if other != "" else "where: " + RecKit.NT], "Small")

## Census, sickness (06-sickness.md section 8): sick now, and cases and deaths by year from the sickness book
## (e.sk.yr {year: [cases, sickness deaths, starved]}). The season's census rows do not count the sick.
static func _sick_card(w: Dictionary, tids: Array, v: VBoxContainer) -> void:
	var sc := RecKit.card(v, "Sickness", "Open cases now, and every case and death of it by year.")
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
		RecKit.nt(sc, "Sickness")
		return
	if tids.size() == 1:   # one town: who is showing it (a wider view keeps to the counters: a tab stays fast)
		RecKit.kv(sc, "Sick now", RecPages.sick_count(w["towns"][tids[0]]))
	RecKit.kv(sc, "Open cases at home (caught, incubating or sick)", "%d" % act)
	var ks: Array = yr.keys()
	ks.sort()
	if ks.is_empty():
		RecKit.line(sc, "No case on record yet.", "Muted")
	for k in ks:
		RecKit.kv(sc, "Year %d" % int(k), "%d cases, %d died of sickness, %d starved" % [int(yr[k][0]), int(yr[k][1]), int(yr[k][2])])
	RecKit.nt(sc, "Sick at each season's census")

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
	var c := RecKit.card(box, "Deaths by cause")
	if (r["deaths"] as Dictionary).is_empty():
		RecKit.line(c, "Nobody died.", "Muted")
	for k in r["deaths"]:
		RecKit.kv(c, String(k).capitalize(), "%d" % int(r["deaths"][k]))
	var m := RecKit.card(box, "Coming and going")
	RecKit.kv(m, "Left", _whys(r["left"]))
	RecKit.kv(m, "Arrived", _whys(r["arrived"]))
	RecKit.kv(m, "Born", "%d" % int(r["births"]))

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
				"_d": "%s%s; %s; %s; %s in %s%s" % [("age %d, " % int(d[3])) if int(d[3]) >= 0 else "", ["man", "woman"][int(d[4])] if int(d[4]) in [0, 1] else "sex: " + RecKit.NT,
					("the %s family" % f["name"]) if not f.is_empty() else "family: " + RecKit.NT, String(d[8]) if d.size() > 8 and String(d[8]) != "" else "job: " + RecKit.NT,
					String(d[6]) if String(d[6]) != "" else cause, t["name"], "" if (d.size() < 10 or int(d[9]) == 1) else " (away with the company: not in the count)"],
				"_s": nm, "_tap": (func(): scr.open_family(tt, fid)) if not f.is_empty() else Callable()})
	if rows.is_empty():
		RecKit.line(box, "Nobody on record died of %s (the record keeps the newest %d deaths per town)." % [cause, Census.DEATHS_MAX], "Muted")
		return
	box.add_child(RecTable.make([{"k": "day", "t": "Date", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
		{"k": "town", "t": "Where"}], rows, "day", false, [], true))

# ================================================================== 8. TREASURY
static func treasury(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var st := RecData.stats(e)
	var c := RecKit.card(v, "The chest")
	RecKit.kv(c, "Cash", _m(RecData.treasury(e)))
	var buf: Dictionary = e.get("census", {}).get("buf", {})
	RecKit.chart(c, "Treasury, last 60 days", buf.get("d", []), buf.get("tre", []), " " + RecData.MONEY)
	RecKit.nt(c, "In and out today")
	var tx := RecData.tax(e)
	var tr := RecData.tax_rules()
	var TL := RecData.treasury_lines(e)
	if not TL.is_empty():
		var TB: Dictionary = Barge.B()["treasury"]
		var svc: Array = TB["service"]
		var sk := float(e.get("svc_scale", 1.0)) * RecData.price_level(e)
		RecKit.kv(c, "Taxes (each month)", "service money %s / %s / %s a family (poor / middling / rich); house and land tax %.2f%% of their value%s; %d%% of the grain harvest to the granary" % [
			_m(float(svc[0]) * sk), _m(float(svc[1]) * sk), _m(float(svc[2]) * sk), 100.0 * float(TB["house_tax"]) * (1.0 + float(e.get("surcharge", 0.0))),
			(" (surcharge %d%%)" % int(round(100.0 * float(e.get("surcharge", 0.0))))) if float(e.get("surcharge", 0.0)) > 0.0 else "", int(round(float(tr["grain_share"]) * 100.0))])
		RecKit.kv(c, "This month", "%s in taxes; the chest %s over the month" % [_m(float(RecData.stats(e).get("tax_month", 0.0))),
			("%+d %s" % [int(round(float(RecData.stats(e).get("treasury_month", 0.0)))), RecData.MONEY])])
		RecKit.kv(c, "The chest's lines", "short below %s, full above %s" % [_m(float(TL["short"])), _m(float(TL["full"]))])
		var ru := RecData.ruler(e)
		RecKit.kv(c, "The ruler", "%s; tribute to the realm %d%% %s" % [String(ru.get("temper", "steady")), int(round(100.0 * float(ru.get("tribute", 0.0)))),
			"in grain" if String(ru.get("kind", "coin")) == "kind" else "in coin"])
	RecKit.kv(c, "Tax this season", "%s collected (last season %s), %d%% lost for want of collectors" % [_m(float(tx.get("paid", 0.0))),
		_m(float(tx.get("last_paid", 0.0))), int(round(float(tx.get("leak", 0.0)) * 100.0))])
	var lb := RecData.loans_book(e)
	RecKit.kv(c, "Arrears", "%d families behind on their loans" % int(lb["arrears"]))
	RecKit.kv(c, "Loans out", "%s owed by %d families" % [_m(float(lb["owed"])), int(lb["debtors"])])
	RecKit.kv(c, "Sent to the realm (last faction turn)", _m(float(st.get("to_faction", 0.0))) if st.has("to_faction") else RecKit.NT)
	RecKit.kv(c, "Tribute to the realm, about a month (weekly sends, smoothed)", _m(float(st["to_faction_month"])) if st.has("to_faction_month") else RecKit.NT)
	RecKit.kv(c, "Relief", "the poorhouse holds %d of %d places, costing %s a day" % [RecData.shelter_n(e), RecData.shelter_cap(t), _m(float(st.get("shelter_cost", 0.0)))])
	for b in RecData.biz(e):
		if String(b["type"]) == "collector":
			var cbid := int(b["id"])
			c.add_child(RecKit.row("Tax collectors", "%d of %d" % [int(b["workers"]), int(b["cap"])], "places filled, %s a day each, till %s: tap for who they are" % [
				_m(RecData.biz_wage(b)), _m(RecData.till(b))], func(): scr.open_business(t, cbid)))
	RecKit.nt(c, "The company's own dues here (tolls, fees)")
	var a := RecKit.card(v, "Accounts", "Running totals the sim keeps; month by month: not tracked.")
	for k in [["tax_in", "Tax taken in (all time)"], ["tax_month", "Taxes, last tax day"], ["treasury_month", "The chest's change, last month"], ["mtax", "Market tax, last week"], ["town_wages", "Town wages a day"],
			["militia_wages", "Militia paid yesterday"], ["militia_bill", "Militia bill a day"], ["shelter_cost", "Poorhouse a day"],
			["works", "Public works, last week"], ["lent", "Lent out (all time)"], ["int_earned", "Interest earned (all time)"],
			["written_off", "Written off (all time)"], ["army_levy", "Last army levy"], ["contracts_paid", "Contracts paid"]]:
		RecKit.kv(a, String(k[1]), _m(float(st[k[0]])) if st.has(k[0]) else RecKit.NT)
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
				("; sold " + ", ".join(PackedStringArray(ln["sold"]))) if not (ln.get("sold", []) as Array).is_empty() else "", RecKit.NT],
			"_col": UiTheme.BAD if status in ["late", "defaulted"] else UiTheme.INK, "_s": String(f["name"]),
			"_tap": func(): scr.open_family(t, fid)})
	var lc := RecKit.card(v, "Loans register", "%d loans, %s out." % [rows.size(), _m(float(lb["owed"]))])
	lc.add_child(RecTable.make([{"k": "name", "t": "Borrower"}, {"k": "owed", "t": "Owed", "num": true}, {"k": "lent", "t": "Lent", "num": true},
		{"k": "rate", "t": "Rate", "num": true}, {"k": "pay", "t": "Pay", "num": true}, {"k": "miss", "t": "Missed", "num": true},
		{"k": "status", "t": "Status"}], rows, "owed", false,
		[{"t": "Show", "opts": ["all", "late", "defaulted"], "fn": func(r, o): return r["status"] == o}], true))
	RecKit.nt(v, "Ledger (last 60 entries)")

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
	var c := RecKit.card(v, "Pressure")
	RecKit.kv(c, "Families going hungry", "%d (%s)" % [n["hungry"], RecKit.pct(n["hungry"], fams.size())])
	RecKit.kv(c, "Homeless households", "%d, of them destitute %d" % [n["homeless"], n["destitute"]])
	RecKit.kv(c, "Families in debt", "%d" % n["debt"])
	RecKit.kv(c, "Poorhouse", "%d of %d places" % [RecData.shelter_n(e), RecData.shelter_cap(t)])
	RecKit.kv(c, "Labour wanted vs offered", "%d open places (%d of them its till cannot pay two days' wages for), %d adults without work" % [open, dry, n["idle"]])
	var dw: Variant = RecData.day_wage(e)
	RecKit.kv(c, "Day wage", _m(float(dw)) if dw != null else RecKit.NT)
	RecKit.kv(c, "Food price index", "x%.2f" % RecData.food_index(t))
	var wb: Dictionary = e.get("census", {}).get("wbuf", {})
	var buf: Dictionary = e.get("census", {}).get("buf", {})
	RecKit.chart(c, "Hungry families (weekly), 60 days", wb.get("d", []), wb.get("hungry", []))
	RecKit.chart(c, "Homeless households (weekly), 60 days", wb.get("d", []), wb.get("homeless", []))
	RecKit.chart(c, "Families in debt (weekly), 60 days", wb.get("d", []), wb.get("debt", []))
	RecKit.chart(c, "Food days in the market, 60 days", buf.get("d", []), buf.get("food", []))
	var dc := RecKit.card(v, "Desperate: the recruit pool", "In the order the sim keeps them, with the family's real trouble.")
	var recs: Array = t.get("recruits", [])
	if recs.is_empty():
		RecKit.line(dc, "Nobody is for hire.", "Muted")
	for u in recs:
		var uu: Unit = u
		var f := People.fam_of(t, uu.family)
		var why := Families.story_line(e, f, uu.name.split(" ")[0], "his") if not f.is_empty() else ""
		dc.add_child(RecKit.row(uu.name, "%s" % uu.title, why if why != "" else "no hardship on record", func(): scr.open_unit(uu)))
	var sc := RecKit.card(v, "Seizures and forced sales", "Everything each family had to sell for its debt (when: not tracked).")
	var anys := false
	for f in fams:
		var sold: Array = f.get("ln", {}).get("sold", [])
		if sold.is_empty():
			continue
		anys = true
		var fid := int(f["id"])
		sc.add_child(RecKit.row("The %s" % f["name"], "%d sales" % sold.size(), ", ".join(PackedStringArray(sold)), func(): scr.open_family(t, fid)))
	for f in RecData.fams(e).filter(func(x): return x.has("lost")):
		anys = true
		var fid2 := int(f["id"])
		sc.add_child(RecKit.row("The %s" % f["name"], "lost", Families.lost_line(f), func(): scr.open_family(t, fid2)))
	if not anys:
		RecKit.line(sc, "None.", "Muted")
	var cg := RecKit.card(v, "Coming and going")
	# Census.current initializes missing old-save books; isolate that read.
	# All household and recruit actions above still target the actual town.
	var cur := Census.current(RecCivic._read_town(t, e)["econ"])
	RecKit.kv(cg, "Left this season", _whys(cur["left"]))
	RecKit.kv(cg, "Arrived this season", _whys(cur["arrived"]))
	RecKit.kv(cg, "Living in the poorhouse", "%d households" % fams.filter(func(f): return RecData.poorhouse(f)).size())
	RecKit.kv(cg, "Sleeping rough", "%d households" % fams.filter(func(f): return RecData.homeless(f) and not RecData.poorhouse(f)).size())
	RecKit.kv(cg, "Where they went (this season)", _whys(cur["to"]) if not (cur["to"] as Dictionary).is_empty() else "nobody")
	RecKit.kv(cg, "Where they came from (this season)", _whys(cur["from_t"]) if not (cur["from_t"] as Dictionary).is_empty() else "nobody")

# ================================================================== 10. GARRISON
static func garrison(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var tid := String(t["id"])
	var wb := Militia.band_of(Game, tid)
	var units: Array = TownDefence.garrison(Game, tid)
	var st := RecData.stats(e)
	var tier := Army.town_tier(t)
	var bill := Army.town_bill(Game, t)
	var c := RecKit.card(v, "The %s of %s" % [tier, t["name"]])
	RecKit.kv(c, "Men paid for", "%d" % units.size())
	RecKit.kv(c, "Pay bill a day", _m(bill))
	RecKit.kv(c, "Paid yesterday", _m(float(st.get("militia_wages", 0.0))))
	RecKit.kv(c, "Days of pay in the treasury", ("%d" % int(RecData.treasury(e) / bill)) if bill > 0.0 else "no bill")
	RecKit.kv(c, "Men unpaid", "%d" % int(st.get("militia_unpaid", 0)))
	var war := Diplomacy.enemies_at_war(Game.world, String(t.get("faction", "")))
	RecKit.kv(c, "War footing", ("yes: at war with " + ", ".join(PackedStringArray(war.map(func(x): return UiWords.faction_name(String(x)))))) if not war.is_empty() else "no")
	RecKit.kv(c, "Civilian militia", "%d; %s" % [Militia.units_of(Game, tid).size(), "mustered" if wb.get("mustered", false) else ("drilling" if wb.get("drill_today", false) else "at civilian work")])
	RecKit.kv(c, "Professional guards", str(TownDefence.guards(Game, tid).size()))
	RecKit.kv(c, "Drill days", str(wb.get("drill_days", 0)))
	RecKit.kv(c, "Barracks beds", str(e.get("barracks_beds", 0)))
	for k in ["Morale", "Kit %", "Deserted this year", "Promotion tests this month", "Sleeping in barracks vs at home"]:
		RecKit.nt(c, k)
	# ranks
	var rc := RecKit.card(v, "Ranks and pay", "The culture's rank names; pay a day by rank (base), plus %s a day for each grade of skill with his weapon." % _m(float(Army.A().get("per_grade", 5.0))))
	var by_rank := {}
	for u in units:
		var rt := Army.rank_title(u)
		by_rank[rt] = int(by_rank.get(rt, 0)) + 1
	var rl := Army.ranks(TownEcon.culture_of(e), tier)
	for i in range(rl.size() - 1, -1, -1):
		var nm := String(rl[i])
		RecKit.kv(rc, nm.capitalize(), "%d men, %s a day" % [int(by_rank.get(nm, 0)), _m(Army.wage(tier, i))])
	# weapons
	var wc := RecKit.card(v, "Weapons")
	var wpn := {}
	var qsum := 0.0; var qn := 0
	for u in units:
		var it: Variant = u.equip.get("main_hand", u.equip.get("ranged", null))
		if it != null:
			wpn[it.display_name()] = int(wpn.get(it.display_name(), 0)) + 1
			qsum += float(it.quality); qn += 1
	for k in wpn:
		RecKit.line(wc, "%d %s" % [int(wpn[k]), String(k)])
	RecKit.kv(wc, "Average quality", ("%.1f of 5" % (qsum / qn)) if qn > 0 else "-")
	var al := ArmsTrade.armory_lines(t)
	RecKit.kv(wc, "Armory vs target", "; ".join(PackedStringArray(al)) if not al.is_empty() else "empty, nothing wanted")
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
					int(rr["age"]), String(rr["weapon"]), UiWords.skill_level(lvl) if sk != "" else "-", lvl, "", RecKit.num(float(rr["years_served"])),
					int(round(uu.renown)), RecKit.NT],
			"_s": uu.name, "_tap": func(): scr.open_unit(uu)})
	var tc := RecKit.card(v, "Roster")
	tc.add_child(RecTable.make([{"k": "rk", "t": "Rank", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
		{"k": "skill", "t": "Skill", "num": true}, {"k": "years", "t": "Years", "num": true}, {"k": "pay", "t": "Pay", "num": true},
		{"k": "renown", "t": "Renown", "num": true}], rows, "rk", false, [], true))
	if not wb.is_empty():
		var wid := String(wb["id"])
		v.add_child(RecKit.row("The band on the map", "%d men" % units.size(), RecPages.force_name(wb), func(): scr.open_force(wid)))

# ================================================================== 11. ROADS
static func roads(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var w: Dictionary = Game.world
	var c := RecKit.card(v, "Roads to the neighbours", "Days at a caravan's pace along the road. Sickness: word brought by caravans (not seen from here). Danger from sightings: not tracked.")
	var news := Sickness.outbreak_news(RecCivic._read_town(t, e))
	for rl in t.get("road_links", []):
		var oid := String(rl.get("id", ""))
		var days := float(rl.get("dist", 0.0)) / (CampaignWorld.WARBAND_SPEED * Caravans.SPEED)
		var o := RecData.town(oid)
		var ob := ("; SICKNESS: " + _news_text(news[oid])) if news.has(oid) else ""
		c.add_child(RecKit.row(String(o.get("name", oid)) + (" (outbreak)" if ob != "" else ""), "%s days" % RecKit.num(days), UiWords.faction_name(String(o.get("faction", ""))) + "; " +
			("at war" if Diplomacy.at_war(w, String(t.get("faction", "")), String(o.get("faction", ""))) else Diplomacy.state(w, String(t.get("faction", "")), String(o.get("faction", ""))).to_lower().replace("_", " ")) + ob,
			func(): scr.open_town(oid), UiTheme.BAD if ob != "" else null))
	var nc := RecKit.card(v, "Word of sickness elsewhere", "What the caravans last said of each town they came from (open cases then).")
	if news.is_empty():
		RecKit.line(nc, "No word of sickness.", "Muted")
	for oid2 in news:
		var o2 := String(oid2)
		nc.add_child(RecKit.row(RecData.tname(o2), "", _news_text(news[o2]), func(): scr.open_town(o2)))
	var cc := RecKit.card(v, "Caravans of this town on the road")
	var cars := _caravans_of(String(t["id"]))
	if cars.is_empty():
		RecKit.line(cc, "None on the road now.", "Muted")
	for wb in cars:
		var wid := String(wb["id"])
		cc.add_child(RecKit.row("To %s" % RecData.tname(String(wb.get("dest", ""))), "%d men" % (wb["units"] as Array).size(), Caravans.describe(w, wb), func(): scr.open_force(wid)))
	var st := RecData.stats(e)
	RecKit.kv(cc, "Trade sent out (value, all time)", _m(float(st.get("trade_out", 0.0))) if st.has("trade_out") else RecKit.NT)
	RecKit.kv(cc, "Trade come in (value, all time)", _m(float(st.get("trade_in", 0.0))) if st.has("trade_in") else RecKit.NT)
	RecKit.nt(cc, "Caravans sent, arrived and robbed this year")
	var ac := RecKit.card(v, "Garrison supply", "Internal transfers use existing stock every ten days within the same faction.")
	RecKit.kv(ac, "Equipment received (all time)", str(int(st.get("military_supply_in", 0))))
	RecKit.kv(ac, "Equipment sent (all time)", str(int(st.get("military_supply_out", 0))))
	RecKit.kv(ac, "Arrows received / sent", "%d / %d" % [int(st.get("military_supply_in_arrows", 0)), int(st.get("military_supply_out_arrows", 0))])
	var lc := RecKit.card(v, "Road log", "The world's log lines that name this town, newest first.")
	var n := 0
	var log: Array = w.get("log", [])
	for i in range(log.size() - 1, -1, -1):
		var line := String(log[i])
		if line.contains(String(t["name"])):
			RecKit.line(lc, line, "Small")
			n += 1
			if n >= 20:
				break
	if n == 0:
		RecKit.line(lc, "Nothing on the log names %s." % t["name"], "Muted")

# ================================================================== SICKNESS (06-sickness.md section 7)
## Every number from campaign/sickness.gd's reads (town_summary, disease_rows, sick_people, hardest_homes,
## remedies, deaths_season): people at home in their sick phase (a case still incubating is not seen).
static func sickness(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var read_town := RecCivic._read_town(t, e)
	var hygiene := TownSanitation.book(read_town["econ"])
	var hygiene_card := RecKit.card(v, "Town cleanliness", "Weekly totals. Solids are kg; urine and drainage are litres.")
	for key in ["filth_kg", "incoming_kg", "swept_kg", "farm_manure_kg", "decayed_kg", "urine_litres", "urine_in_l", "night_soil_l", "river_l", "rats", "food_capacity", "caught", "births", "starved", "grain_eaten_kg", "cleaners"]:
		RecKit.kv(hygiene_card, String(key).replace("_", " ").capitalize(), "%.1f" % float(hygiene.get(key, 0)))
	var s := Sickness.town_summary(read_town)
	var c := RecKit.card(v, "Sickness", "People of the town at home and showing it (a case still incubating is not seen).")
	if s.is_empty():
		RecKit.nt(c, "Sickness")
		return
	RecKit.kv(c, "Sick now", "%d" % int(s["sick_now"]))
	RecKit.kv(c, "Bed-ridden", "%d" % int(s["bed_now"]))
	RecKit.kv(c, "New this week", "%d" % int(s["new_week"]))
	RecKit.kv(c, "Deaths this season (sickness and hunger)", "%d" % int(s["deaths_season"]))
	RecKit.kv(c, "Share of the town sick", "%.1f%%" % (100.0 * float(s["share"])))
	var h60: Array = s.get("h60", [])
	if h60.is_empty():
		RecKit.nt(c, "60-day chart of the sick")
	else:
		var day := int(e.get("day", 0))
		var xs := range(day - h60.size() + 1, day + 1)
		RecKit.chart(c, "Open cases at home (caught, incubating or sick), last 60 days", xs, h60)
	# disease rows: tap -> the sick of it
	var dc := RecKit.card(v, "Diseases", "Sick now, new this week, deaths this season; the trend over 8 days; where it came from. Tap for the sick.")
	var rows := Sickness.disease_rows(read_town)
	if rows.is_empty():
		RecKit.line(dc, "No disease in town.", "Muted")
	for r in rows:
		var dis := String(r["id"])
		var nm := String(r["name"])
		var tr := String(r["trend"])
		dc.add_child(RecKit.row(nm.capitalize(), "%d sick" % int(r["sick_now"]), "%d new this week, %d died this season, %s%s" % [int(r["new_week"]),
			int(r["deaths_season"]), tr, ("; " + String(r["origin"])) if String(r["origin"]) != "" else "; where it came from: " + RecKit.NT],
			func(): scr.page("Sick of %s" % nm, func(b): sick_list(scr, t, dis, b)),
			UiTheme.BAD if tr == "rising" else (UiTheme.GOOD if tr == "falling" else null)))
	if int(s["sick_now"]) > 0:
		dc.add_child(RecKit.row("Everyone sick", "%d" % int(s["sick_now"]), "all diseases: name, age, family, day N of M, remedy",
			func(): scr.page("The sick of %s" % t["name"], func(b): sick_list(scr, t, "", b))))
	# homes hit hardest
	var hc := RecKit.card(v, "Homes hit hardest", "Households with the most sick. Tap for the family.")
	var homes := Sickness.hardest_homes(read_town)
	if homes.is_empty():
		RecKit.line(hc, "Nobody sick at home.", "Muted")
	for hh in homes:
		var fid := int(hh["fid"])
		hc.add_child(RecKit.row("The %s" % String(hh["household"]), "%d sick" % int(hh["sick"]), "%d people in the household" % RecData.people(RecData.fam(e, fid)),
			func(): scr.open_family(t, fid)))
	# remedies
	var rm := Sickness.remedies(read_town)
	var rc := RecKit.card(v, "Remedies", "A family buys one for its sick if it can after food: the poor go without.")
	RecKit.kv(rc, "In the market", "%d" % int(rm.get("stock", 0)))
	RecKit.kv(rc, "Price", _m(float(rm.get("price", 0.0))))
	var hbs: Array = rm.get("herbalists", [])
	if hbs.is_empty():
		RecKit.line(rc, "No herbalist in town.", "Muted")
	for hb in hbs:
		var bid := int(hb["bid"])
		rc.add_child(RecKit.row(String(hb["title"]).capitalize(), String(hb["state"]), "%d of %d at work" % [int(hb["workers"]), int(hb["cap"])],
			func(): scr.open_business(t, bid)))
	# this season's dead of sickness and hunger
	var drows := []
	for d in Sickness.deaths_season(read_town):
		var pid := int(d["pid"])
		var nm2 := String(d["name"]) if String(d["name"]) != "" else "someone"
		var cause := String(d["detail"]) if String(d["cause"]) == "sickness" and String(d["detail"]) != "" else String(d["cause"])
		drows.append({"name": nm2, "age": int(d["age"]) if int(d["age"]) >= 0 else null, "day": float(d["day"]), "cause": cause,
			"_l": nm2, "_r": cause, "_d": "%s%s; %s" % [("age %d, " % int(d["age"])) if int(d["age"]) >= 0 else "",
				["man", "woman"][int(d["sex"])] if int(d["sex"]) in [0, 1] else "sex: " + RecKit.NT, _day_word(float(d["day"]))],
			"_s": nm2, "_tap": func(): _open_dead(scr, t, e, pid)})
	var kc := RecKit.card(v, "Died this season of sickness and hunger", "Person, age, cause (the disease, or starved). Tap for his page.")
	if drows.is_empty():
		RecKit.line(kc, "Nobody.", "Muted")
	else:
		kc.add_child(RecTable.make([{"k": "day", "t": "Date", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
			{"k": "cause", "t": "Cause"}], drows, "day", false, [], true, 10))
	var causes := Census.causes_of(RecCivic._read_world(t, e), [String(t["id"])])
	var cc := RecKit.card(v, "By cause, this season and last", "From the census: every death has one cause. Tap for all the dead of it on record.")
	for cs in ["sickness", "starved", "frozen"]:
		var css := String(cs)
		cc.add_child(RecKit.row(css.capitalize(), "%d" % int(causes["now"].get(css, 0)), "last season %d" % int(causes["last"].get(css, 0)),
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
		RecKit.line(box, "Nobody is sick of it now.", "Muted")
		return
	box.add_child(RecTable.make([{"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true}, {"k": "family", "t": "Home"},
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
	var c := RecKit.card(v, "What the books noted", "One sentence per business event from live values: not tracked (the sim keeps no business event log yet).")
	RecKit.nt(c, "Harvest buying, shipments, hires and quits, loans and defaults, openings and closings, price swings")
	RecKit.nt(c, "Year-end line per business")
	var lc := RecKit.card(v, "The town's own record", "What the sim does note, newest first.")
	var hist: Array = e.get("hist", [])
	if hist.is_empty():
		RecKit.line(lc, "Nothing yet.", "Muted")
	for i in range(hist.size() - 1, -1, -1):
		RecKit.line(lc, String(hist[i]), "Small")
	var pc := RecKit.card(v, "Price reasons this week")
	var any := false
	for g in Goods.ids():
		var why := RecData.price_why(e, g)
		if why != "":
			any = true
			RecKit.line(pc, "%s: %s" % [RecData.good_name(e, g).capitalize(), why], "Small")
	if not any:
		RecKit.line(pc, "No price moved enough to note.", "Muted")

static func seasons_table(scr, w: Dictionary, tids: Array, display_columns: Array = []) -> RecTable:
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
				Census.sum(r["deaths"]), Census.sum(r["arrived"]), Census.sum(r["left"]), int(r["homeless"]), int(r["soldiers"]), int(r["empty_homes"]), RecKit.NT],
			"_tap": func(): scr.page("Census of %s" % _season_word(int(rr["stamp"])), func(b): _season_page(rr, b))})
	return RecTable.make([{"k": "season", "t": "Season", "num": true}, {"k": "people", "t": "People", "num": true},
		{"k": "families", "t": "Families", "num": true}, {"k": "births", "t": "Births", "num": true}, {"k": "deaths", "t": "Deaths", "num": true},
		{"k": "arrived", "t": "Arrived", "num": true}, {"k": "left", "t": "Left", "num": true}], rows, "season", false, [], false, RecTable.LIMIT, display_columns)
