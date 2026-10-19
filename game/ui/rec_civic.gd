class_name RecCivic
extends RefCounted
## Compact civic records. Original detailed records remain lazy and retain their links.

static func _m(value: float) -> String:
	return RecData.money(value)

## Legacy read helpers may create missing books. Initialize only an isolated top-level
## view, and isolate incomplete census books and missing person-array slots too.
static func _read_town(t: Dictionary, e: Dictionary) -> Dictionary:
	var read := e.duplicate()
	var census: Dictionary = e.get("census", {})
	if not census.has_all(["cur", "deaths", "moves", "rows", "bdays", "births"]):
		read["census"] = census.duplicate(true)
		for key in ["deaths", "moves", "bdays", "rows"]:
			if not read["census"].has(key): read["census"][key] = []
		if not read["census"].has("births"): read["census"]["births"] = 0
	Census._book(read)
	Sickness.book(read)
	var families: Array = e.get("fams", [])
	read["fams"] = families.map(func(f: Dictionary): return f if f.has("pp") and f.has("kp") else f.duplicate())
	var town := t.duplicate()
	town["econ"] = read
	return town

static func _read_world(t: Dictionary, e: Dictionary) -> Dictionary:
	var world := Game.world.duplicate()
	var towns: Dictionary = Game.world.get("towns", {}).duplicate()
	towns[String(t["id"])] = _read_town(t, e)
	world["towns"] = towns
	return world

static func land(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var ls := RecData.land(e)
	RecKit.metrics(v, [
		{"title": "Family land", "value": "%d acres" % int(ls["families"]), "note": "Held by households"},
		{"title": "Town land", "value": "%d acres" % int(ls["estate"]), "note": "Town estate"},
		{"title": "Common land", "value": "%d acres" % int(ls["common"]), "note": "%d acres in the territory" % int(ls["territory"])}
	])
	var crops := []
	var keys: Array = ls["fam_crops"].keys()
	for key in ls["est_crops"]:
		if not keys.has(key): keys.append(key)
	for key in keys:
		crops.append({"values": [RecData.crop_word(e, String(key)).capitalize(), str(int(ls["fam_crops"].get(key, 0))), str(int(ls["est_crops"].get(key, 0)))]})
	RecKit.grid(v, ["Crop", "Family acres", "Town acres"], crops, [2, 1, 1])
	var actions := RecKit.card(v, "Land and homes")
	actions.name = RecTown.LAND_MAP_SLOT
	actions.set_meta("town_id", String(t["id"]))
	actions.add_child(RecKit.row("Open the land map", "", "The town's recorded plots", func(): LandMap.open(scr, t)))
	actions.add_child(RecKit.row("Herds", "%d records" % RecData.herd_records(e).size(), "Animals, herders and plots", func(): scr.page("Herds of %s" % t["name"], func(box): RecTown.herds_page(scr, t, e, box))))
	RecKit.grid(v, ["Housing", "Count", "Value"], [
		{"values": ["Total recorded homes", str(int(e.get("homes", 0))), "-"]},
		{"values": ["Empty town homes", str(RecData.empty_homes(e)), "-"]},
		{"values": ["New homes for sale", str(RecData.homes_for_sale(e)), _m(RecData.price(t, "home")) + " each"]}
	], [2, 1, 2])
	RecKit.disclosure(v, "Owners, homes and full land record", func(content): RecTown.land(scr, t, e, content))

static func census(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var tids := [String(t["id"])]
	var world := _read_world(t, e)
	var balance := Census.balance_of(world, tids)
	var ok := Census.adds_up(balance)
	RecKit.metrics(v, [
		{"title": "People now", "value": str(int(balance["people"])), "note": "%d at last census" % int(balance["last"])},
		{"title": "Population change", "value": "%+d" % int(balance["change"]), "note": "Since last census", "color": UiTheme.BLUE},
		{"title": "Census balance", "value": "Adds up" if ok else "DOES NOT ADD UP", "note": "Recorded births, deaths and moves", "color": UiTheme.GOOD if ok else UiTheme.BAD}
	])
	RecKit.grid(v, ["Since last census", "People"], [
		{"values": ["Born", str(int(balance["births"]))]},
		{"values": ["Died", str(int(balance["deaths"]))]},
		{"values": ["Arrived", str(int(balance["arrived"]))]},
		{"values": ["Left", str(int(balance["left"]))]}
	], [2, 1])
	var causes := Census.causes_of(world, tids)
	var rows := []
	for cause in Census.CAUSES:
		var cs := String(cause)
		rows.append({"values": [cs.capitalize(), str(int(causes["now"].get(cs, 0))), str(int(causes["last"].get(cs, 0)))], "tap": func(): scr.page("Died of %s" % cs, func(box): RecTown.dead_list(scr, Game.world, tids, cs, box))})
	RecKit.grid(v, ["Death cause", "This season", "Last season"], rows, [2, 1, 1])
	RecKit.disclosure(v, "Season records, charts and movements", func(content): RecTown.census_cards(scr, _read_world(t, e), tids, content))

static func treasury(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var stats := RecData.stats(e)
	var loans := RecData.loans_book(e)
	var tax := RecData.tax(e)
	var lines := RecData.treasury_lines(e)
	var cash := RecData.treasury(e)
	var tone := UiTheme.WARN if not lines.is_empty() and cash < float(lines["short"]) else UiTheme.BLUE
	RecKit.metrics(v, [
		{"title": "Cash in chest", "value": _m(cash), "color": tone},
		{"title": "Loans owed", "value": _m(float(loans["owed"])), "note": "%d borrowing families" % int(loans["debtors"])},
		{"title": "Loan arrears", "value": "%d families" % int(loans["arrears"]), "color": UiTheme.WARN if int(loans["arrears"]) > 0 else UiTheme.BLUE}
	])
	var flows := [
		{"values": ["Tax collected", _m(float(tax.get("paid", 0.0))), "This season"]},
		{"values": ["Tax collected", _m(float(tax.get("last_paid", 0.0))), "Last season"]},
		{"values": ["Collector leakage", "%d%%" % int(round(float(tax.get("leak", 0.0)) * 100.0)), "This season"]}
	]
	for pair in [["tax_month", "Taxes, last tax day", "Last tax day"], ["treasury_month", "Chest change", "Last month"], ["town_wages", "Town wages", "Per day"], ["to_faction", "Sent to the realm", "Last faction turn"]]:
		var key := String(pair[0])
		flows.append({"values": [String(pair[1]), _m(float(stats[key])) if stats.has(key) else RecKit.NT, String(pair[2])]})
	RecKit.grid(v, ["Account", "Amount", "Period"], flows, [2, 1.5, 1.5])
	var rows := []
	for f: Dictionary in RecData.fams(e):
		if RecData.debt(f) <= 0.5 and not f.has("ln"): continue
		var loan: Dictionary = f.get("ln", {})
		var fid := int(f["id"])
		var miss := int(loan.get("miss", 0))
		var status := "repaid" if RecData.debt(f) <= 0.5 else ("defaulted" if not (loan.get("sold", []) as Array).is_empty() else ("late" if miss > 0 else "current"))
		rows.append({"name": String(f["name"]), "lent": float(loan.get("lent", 0.0)), "owed": RecData.debt(f), "rate": float(loan.get("rate", RecData.loan_rate(e))), "pay": float(loan.get("pay", 0.0)), "miss": miss, "status": status,
			"_l": "The %s" % f["name"], "_r": _m(RecData.debt(f)),
			"_d": "%s; lent %s, rate %.1f%% a week, %s a week, %d missed%s; kind, collateral and clerk: %s" % [status, _m(float(loan.get("lent", 0.0))), 100.0 * float(loan.get("rate", RecData.loan_rate(e))), _m(float(loan.get("pay", 0.0))), miss, ("; sold " + ", ".join(PackedStringArray(loan["sold"]))) if not (loan.get("sold", []) as Array).is_empty() else "", RecKit.NT],
			"_s": String(f["name"]), "_col": UiTheme.BAD if status in ["late", "defaulted"] else UiTheme.INK, "_tap": func(): scr.open_family(t, fid)})
	var table := RecTable.make([{"k": "name", "t": "Borrower"}, {"k": "owed", "t": "Owed", "num": true}, {"k": "pay", "t": "Pay/week", "num": true}, {"k": "status", "t": "Status"}, {"k": "lent", "t": "Lent", "num": true}, {"k": "rate", "t": "Rate", "num": true}, {"k": "miss", "t": "Missed", "num": true}], rows, "owed", false,
		[{"t": "Show", "opts": ["all", "late", "defaulted"], "fn": func(r, o): return r["status"] == o}], true, 10)
	RecKit.card(v, "Loans").add_child(table)
	table.display_cells([{"k": "name", "t": "Borrower", "w": 2}, {"k": "owed", "t": "Owed", "format": func(value): return _m(float(value))}, {"k": "pay", "t": "Pay/week", "format": func(value): return _m(float(value))}, {"k": "status", "t": "Status"}])
	var collectors := []
	for b: Dictionary in RecData.biz(e):
		if String(b["type"]) != "collector": continue
		var bid := int(b["id"])
		collectors.append({"values": [RecData.biz_title(e, b).capitalize(), "%d / %d" % [int(b["workers"]), int(b["cap"])], _m(RecData.biz_wage(b)), _m(RecData.till(b))], "tap": func(): scr.open_business(t, bid)})
	if not collectors.is_empty(): RecKit.grid(v, ["Tax collectors", "Paid places", "Wage/day", "Till"], collectors, [2, 1, 1.5, 1.5])
	RecKit.disclosure(v, "Tax rules, full accounts, loan terms and history", func(content): RecTown.treasury(scr, t, e, content))

static func hardship(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var families := RecData.fams(e)
	var counts := {"hungry": 0, "homeless": 0, "destitute": 0, "debt": 0, "idle": 0}
	for f: Dictionary in families:
		if RecData.hungry_weeks(f) > 0: counts["hungry"] += 1
		if RecData.homeless(f): counts["homeless"] += 1
		if RecData.destitute(f): counts["destitute"] += 1
		if RecData.debt(f) > 0.5: counts["debt"] += 1
		counts["idle"] += int(f.get("idle", 0))
	RecKit.metrics(v, [
		{"title": "Hungry families", "value": str(int(counts["hungry"])), "note": RecKit.pct(counts["hungry"], families.size()), "color": UiTheme.WARN if int(counts["hungry"]) > 0 else UiTheme.BLUE},
		{"title": "Homeless households", "value": str(int(counts["homeless"])), "note": "%d destitute" % int(counts["destitute"]), "color": UiTheme.WARN if int(counts["homeless"]) > 0 else UiTheme.BLUE},
		{"title": "Families in debt", "value": str(int(counts["debt"])), "color": UiTheme.BLUE}
	])
	var openings := 0
	var unfunded := 0
	for b: Dictionary in RecData.biz(e):
		if not bool(b.get("closed", false)):
			var n := maxi(0, int(b.get("cap", 0)) - int(b.get("workers", 0)))
			openings += n
			unfunded += n - Businesses.takeable(b, e)
	var wage: Variant = RecData.day_wage(e)
	RecKit.grid(v, ["Work and relief", "Current value"], [
		{"values": ["Paid places open", str(openings)]},
		{"values": ["Open places unable to fund two days' wages", str(unfunded)], "color": UiTheme.WARN if unfunded > 0 else UiTheme.INK},
		{"values": ["Adults without work", str(int(counts["idle"]))]},
		{"values": ["Day wage", _m(float(wage)) if wage != null else RecKit.NT]},
		{"values": ["Food price index", "x%.2f" % RecData.food_index(t)]}
	], [2, 1])
	RecKit.meter(RecKit.card(v, ""), "Poorhouse places", RecData.shelter_n(e), RecData.shelter_cap(t), "Occupied households / places", UiTheme.BLUE)
	var recruits := []
	for unit: Unit in t.get("recruits", []):
		var person: Unit = unit
		recruits.append({"values": [person.name, person.title], "tap": func(): scr.open_unit(person)})
	if recruits.is_empty(): RecKit.notice(v, "Nobody is for hire.", "Muted")
	else: RecKit.grid(v, ["For hire", "Current title"], recruits, [2, 1])
	RecKit.disclosure(v, "Trouble, forced sales, movements and history", func(content): RecTown.hardship(scr, t, e, content))

static func roads(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var world: Dictionary = Game.world
	var news := Sickness.outbreak_news(_read_town(t, e))
	var rows := []
	for link: Dictionary in t.get("road_links", []):
		var oid := String(link.get("id", ""))
		var other := RecData.town(oid)
		var days := float(link.get("dist", 0.0)) / (CampaignWorld.WARBAND_SPEED * Caravans.SPEED)
		var relation := "at war" if Diplomacy.at_war(world, String(t.get("faction", "")), String(other.get("faction", ""))) else Diplomacy.state(world, String(t.get("faction", "")), String(other.get("faction", ""))).to_lower().replace("_", " ")
		rows.append({"values": [String(other.get("name", oid)), RecKit.num(days), UiWords.faction_name(String(other.get("faction", ""))), relation, "Outbreak reported" if news.has(oid) else "No report"], "tap": func(): scr.open_town(oid), "color": UiTheme.WARN if news.has(oid) else UiTheme.INK})
	RecKit.grid(v, ["Neighbour", "Caravan days", "Realm", "Relations", "Sickness news"], rows, [2, 1, 1.5, 1.2, 1.8])
	RecKit.notice(v, "Sickness reports are word brought by caravans.")
	var caravans := []
	for band: Dictionary in RecTown._caravans_of(String(t["id"])):
		var wid := String(band["id"])
		caravans.append({"values": [RecData.tname(String(band.get("dest", ""))), str((band["units"] as Array).size())], "tap": func(): scr.open_force(wid)})
	if caravans.is_empty(): RecKit.notice(v, "No caravans on the road now.", "Muted")
	else: RecKit.grid(v, ["Caravan destination", "Men"], caravans, [2, 1])
	var stats := RecData.stats(e)
	RecKit.grid(v, ["Garrison supply", "Received", "Sent"], [
		{"values": ["Equipment, all time", str(int(stats.get("military_supply_in", 0))), str(int(stats.get("military_supply_out", 0)))]},
		{"values": ["Arrows, all time", str(int(stats.get("military_supply_in_arrows", 0))), str(int(stats.get("military_supply_out_arrows", 0)))]}
	], [2, 1, 1])
	RecKit.disclosure(v, "Road reports, caravans, trade totals and log", func(content): RecTown.roads(scr, t, e, content))

static func sickness(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var read_town := _read_town(t, e)
	var summary := Sickness.town_summary(read_town)
	if summary.is_empty():
		RecKit.notice(v, "Sickness: " + RecKit.NT, "Muted")
		return
	RecKit.metrics(v, [
		{"title": "Sick now: %d" % int(summary["sick_now"]), "value": "%.1f%%" % (100.0 * float(summary["share"])), "note": "Share of town population", "color": UiTheme.WARN if int(summary["sick_now"]) > 0 else UiTheme.BLUE},
		{"title": "Bed-ridden: %d" % int(summary["bed_now"]), "value": "%d new this week" % int(summary["new_week"]), "color": UiTheme.WARN if int(summary["bed_now"]) > 0 else UiTheme.BLUE},
		{"title": "Deaths this season", "value": str(int(summary["deaths_season"])), "note": "Sickness and hunger"}
	])
	var rows := []
	for disease: Dictionary in Sickness.disease_rows(read_town):
		var dis := String(disease["id"])
		var name := String(disease["name"])
		var trend := String(disease["trend"])
		rows.append({"values": [name.capitalize(), str(int(disease["sick_now"])), str(int(disease["new_week"])), str(int(disease["deaths_season"])), trend], "tap": func(): scr.page("Sick of %s" % name, func(box): RecTown.sick_list(scr, t, dis, box)), "color": UiTheme.BAD if trend == "rising" else (UiTheme.GOOD if trend == "falling" else UiTheme.INK)})
	if rows.is_empty(): RecKit.notice(v, "No disease in town.", "Muted")
	else: RecKit.grid(v, ["Disease", "Sick", "New/week", "Deaths/season", "Trend"], rows, [2, 1, 1, 1, 1])
	if int(summary["sick_now"]) > 0:
		v.add_child(RecKit.row("Everyone sick", str(int(summary["sick_now"])), "People showing sickness at home", func(): scr.page("The sick of %s" % t["name"], func(box): RecTown.sick_list(scr, t, "", box))))
	var remedies := Sickness.remedies(read_town)
	RecKit.grid(v, ["Remedies", "Value"], [
		{"values": ["Market stock", str(int(remedies.get("stock", 0)))]},
		{"values": ["Price each", _m(float(remedies.get("price", 0.0)))]}
	], [2, 1])
	RecKit.disclosure(v, "Cleanliness, homes, remedies, deaths and history", func(content): RecTown.sickness(scr, t, e, content))

static func books(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var history: Array = e.get("hist", [])
	RecKit.metrics(v, [{"title": "Town record", "value": "%d entries" % history.size(), "note": "Newest first"}])
	var events := []
	for i in range(history.size() - 1, -1, -1):
		events.append({"values": [String(history[i])]})
	if events.is_empty(): RecKit.notice(v, "Nothing yet.", "Muted")
	else: RecKit.grid(v, ["Recorded event"], events)
	var reasons := []
	for good in Goods.ids():
		var why := RecData.price_why(e, String(good))
		if why != "":
			reasons.append({"values": [RecData.good_name(e, String(good)).capitalize(), why]})
	if reasons.is_empty(): RecKit.notice(v, "No price moved enough to note.", "Muted")
	else: RecKit.grid(v, ["Good", "Price reason this week"], reasons, [1, 3])
	RecKit.disclosure(v, "Full book and unavailable records", func(content): RecTown.books(scr, t, e, content))
