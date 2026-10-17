class_name RecRegions
extends RefCounted
## World/faction presentation over RecWorld's original live tables. Row dictionaries,
## sort keys, lazy values, filters and tap callbacks stay owned by that source.
## legacy is the unchanged account renderer, built only when its disclosure opens.

class ArmyRead:
	extends RefCounted
	var world: Dictionary

static func _money(value: Variant) -> String:
	return RecKit.NT if value == null else RecData.money(float(value))

static func _number(value: Variant) -> String:
	return RecKit.NT if value == null else RecKit.num(float(value))

static func _sum(rows: Array, key: String) -> float:
	var total := 0.0
	for row: Dictionary in rows:
		var value: Variant = row.get(key)
		if value is Callable: value = (value as Callable).call()
		if value != null: total += float(value)
	return total

static func _table(v: VBoxContainer, title: String, table: RecTable, columns: Array) -> void:
	if table.display_columns != columns: table.display_cells(columns)
	RecKit.card(v, title).add_child(table)

static func town_columns() -> Array:
	return [
		{"k": "name", "t": "Town", "w": 1.7}, {"k": "faction", "t": "Realm", "w": 1.6},
		{"k": "people", "t": "People", "w": 0.8}, {"k": "food", "t": "Food days", "w": 0.8},
		{"k": "tre", "t": "Town chest", "w": 1.1, "format": _money}]

static func move_columns() -> Array:
	return [
		{"k": "_l", "t": "Force", "w": 1.65}, {"k": "kind", "t": "Kind", "w": 0.8},
		{"k": "faction", "t": "Owner", "w": 1.45}, {"k": "men", "t": "Living members", "w": 0.8},
		{"k": "near", "t": "Near", "w": 1.4}]

static func _details(v: VBoxContainer, title: String, legacy: Callable) -> void:
	if legacy.is_valid(): RecKit.disclosure(v, title, legacy)

static func towns(scr, tids: Array, fid: String, v: VBoxContainer, table: RecTable, legacy: Callable) -> void:
	var short := 0
	var starving := 0
	for i in mini(tids.size(), table.rows.size()):
		var town := RecData.town(String(tids[i]))
		var level := TownEcon.supply_level(town, float(table.rows[i]["food"]))
		if level == "short": short += 1
		elif level == "starving": starving += 1
	RecKit.metrics(v, [
		{"title": "Towns", "value": str(table.rows.size()), "note": "%d people" % int(_sum(table.rows, "people")), "color": UiTheme.BLUE},
		{"title": "Average food days", "value": _number(_sum(table.rows, "food") / float(table.rows.size())) if not table.rows.is_empty() else "-", "note": "Unweighted town average", "color": UiTheme.COPPER},
		{"title": "Short / starving", "value": "%d / %d" % [short, starving], "note": "Current town supply status", "color": UiTheme.BAD if starving > 0 else (UiTheme.WARN if short > 0 else UiTheme.GOOD)}])
	_table(v, "Towns", table, town_columns())
	v.add_child(UiKit.button("View town price and wealth spreads", func(): scr.page("Asymmetry at a glance", func(box): RecWorld._town_spreads(tids, box)), "Row"))
	if fid != "": research(scr, fid, v)
	_details(v, "Town accounts, harvests and price comparisons", legacy)

static func factions(scr, _tids: Array, _fid: String, v: VBoxContainer, table: RecTable, legacy: Callable) -> void:
	RecKit.metrics(v, [
		{"title": "Factions", "value": str(table.rows.size()), "note": "All recorded factions", "color": UiTheme.BLUE},
		{"title": "People in their towns", "value": str(int(_sum(table.rows, "people"))), "note": "%d towns with an economy" % int(_sum(table.rows, "towns")), "color": UiTheme.COPPER},
		{"title": "Field soldiers", "value": str(int(_sum(table.rows, "men"))), "note": "%s total daily army bill" % _money(_sum(table.rows, "bill")), "color": UiTheme.BLUE}])
	_table(v, "Faction accounts", table, [
		{"k": "name", "t": "Faction", "w": 2.0}, {"k": "towns", "t": "Towns", "w": 0.65},
		{"k": "people", "t": "People", "w": 0.9}, {"k": "tre", "t": "War chest", "w": 1.15, "format": _money},
		{"k": "days", "t": "Pay days", "w": 0.85, "format": _number}])
	_details(v, "Diplomacy, pay and retained knowledge accounts", legacy)

static func rulers(_scr, _tids: Array, v: VBoxContainer, table: RecTable, legacy: Callable) -> void:
	RecKit.metrics(v, [
		{"title": "Town heads", "value": str(table.rows.size()), "note": "Recorded town leadership", "color": UiTheme.BLUE},
		{"title": "People governed", "value": str(int(_sum(table.rows, "people"))), "color": UiTheme.COPPER},
		{"title": "Faction heads & traits", "value": RecKit.NT, "note": "Town-head household links remain available", "color": UiTheme.BLUE}])
	_table(v, "Town heads and rules", table, [
		{"k": "name", "t": "Town", "w": 1.5}, {"k": "head", "t": "Recorded head", "w": 2.0},
		{"k": "people", "t": "People", "w": 0.8}, {"k": "gran", "t": "Granary days", "w": 1.0}])
	_details(v, "Taxes, loan rates and unrecorded rules", legacy)

static func on_the_move(_scr, _tids: Array, fid: String, v: VBoxContainer, table: RecTable, legacy: Callable) -> void:
	var caravans := 0
	var fields := 0
	var gold := 0.0
	for force: Dictionary in RecWorld._forces(fid):
		if String(force.get("kind", "")) == "caravan":
			caravans += 1
			gold += float(force.get("gold", 0.0))
		if Army.is_field(force): fields += 1
	RecKit.metrics(v, [
		{"title": "Caravans on the road", "value": str(caravans), "note": "%s carried in coin" % _money(gold), "color": UiTheme.COPPER},
		{"title": "Field armies", "value": str(fields), "note": "%d forces in this view" % table.rows.size(), "color": UiTheme.BLUE},
		{"title": "Interceptions", "value": str(int(Game.world.get("war", {}).get("stats", {}).get("intercepts", 0))), "note": "Whole world, since it began", "color": UiTheme.WARN}])
	_table(v, "Forces on the map", table, move_columns())
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
		RecKit.line(RecKit.card(v, "Army"), "Pick a faction for its army.", "Muted")
		return
	var faction: Dictionary = Game.world.get("factions", {}).get(fid, {})
	var bill := Army.bill(Game, fid)
	var days := Army.days_of_pay(Game, fid)
	var members := Army.members(Game, fid)
	RecKit.metrics(v, [
		{"title": "Living field soldiers", "value": str(members.size()), "color": UiTheme.BLUE},
		{"title": "Army bill / day", "value": _money(bill), "color": UiTheme.COPPER},
		{"title": "War chest", "value": _money(float(faction.get("treasury", 0.0))), "note": ("%s days of pay" % _number(days)) if days < 1.0e9 else "No current wage bill", "color": UiTheme.WARN if days < 1.0 else UiTheme.BLUE}])
	var ranks := []
	for rank: Dictionary in Army.tree_rows(_army_read(), fid):
		var cap := int(rank["cap"])
		ranks.append({"values": [String(rank["title"]).capitalize(), str(int(rank["count"])), str(cap) if cap >= 0 else "No cap", _money(Army.wage("army", int(rank["rank"])))]})
	RecKit.grid(v, ["Rank", "Serving", "Cap", "Rate / day"], ranks, [2, 1, 1, 1.4])
	var rows := []
	for force: Dictionary in RecWorld._forces(fid):
		if not Army.is_field(force): continue
		var lead: Unit = null
		for unit: Unit in force["units"]:
			if not unit.dead and (lead == null or unit.rank > lead.rank): lead = unit
		var wid := String(force["id"])
		rows.append({"name": RecPages.force_name(force), "men": (force["units"] as Array).size(), "commander": "%s %s" % [Army.rank_title(lead), lead.name] if lead != null else "No leader",
			"_l": RecPages.force_name(force), "_r": "%d men" % (force["units"] as Array).size(), "_s": RecPages.force_name(force),
			"_d": "Recorded force roster; commander is its highest-ranking living member.", "_tap": func(): scr.open_force(wid)})
	var table := RecTable.make([{"k": "name", "t": "Army"}, {"k": "men", "t": "Roster", "num": true}, {"k": "commander", "t": "Commander"}], rows, "name", true, [], true, 8)
	_table(v, "Armies and their commanders", table, [{"k": "name", "t": "Army", "w": 1.6}, {"k": "men", "t": "Recorded roster", "w": 0.8}, {"k": "commander", "t": "Commander", "w": 2.0}])
	_details(v, "Rank rules, officers and promotions", legacy)

## The owned capital house is a recorded snapshot, not activity inferred from budget.
static func research(scr, fid: String, v: VBoxContainer) -> void:
	var report := Academy.report(Game.world, fid)
	var state := TownResearchTab.house_state(report)
	var card := RecKit.card(v, "Research - %s" % String(report.get("name", "Research house")))
	var capital: Dictionary = {"faction": fid}
	if not bool(report.get("has", false)):
		RecKit.line(card, String(state["text"]), "Muted")
	else:
		var tid := String(report["tid"])
		capital = RecData.town(tid)
		var bid := int(report["bid"])
		var lead := String(report.get("lead", ""))
		RecKit.grid(card, ["Location", String(report.get("title", "Head")), "Recorded work"], [
			{"values": [String(report.get("town", "")), lead if lead != "" else "Post vacant", String(state["text"])], "color": state["color"], "tap": func():
				var live := Academy.report(Game.world, fid)
				if bool(live.get("has", false)) and String(live.get("tid", "")) == tid and int(live.get("bid", -1)) == bid:
					scr.open_business(RecData.town(tid), bid)}], [1.4, 1.8, 1.8])
	var rows := []
	for line: Dictionary in report.get("lines", []):
		var status := TownResearchTab.line_state(report, line)
		rows.append({"values": [String(line["name"]).capitalize(), String(status["text"]), "%.1f%%" % float(line.get("kh", 0.0)), "%.1f" % float(line.get("pts", 0.0))], "color": status["color"]})
	RecKit.grid(card, ["Research line", "Status", "Know-how", "Saved points"], rows, [1.3, 1.7, 0.8, 0.8])
	RecKit.disclosure(card, "Research funding, allocations, history and people", func(content):
		_research_account(scr, capital, fid, report, content)
		RecKit.grid(content, ["Recorded research account", "Value"], [
			{"values": ["State interest", "%.1f%%" % (100.0 * float(report.get("interest", 0.0)))]},
			{"values": ["Supporting staff skill", "%.1f / 15" % float(report.get("skill", 0.0)) if bool(report.get("has", false)) else RecKit.NT]},
			{"values": ["Steel pieces in its towns", str(int(report.get("met", 0)))]}], [2, 1])
		var rules := []
		for line: Dictionary in report.get("lines", []):
			var quality := int(line.get("best_q", -1))
			var limit := "No steel" if quality < 0 else ("Ordinary" if quality == 0 else String(DB.QUALITY_NAMES[clampi(quality, 0, DB.QUALITY_NAMES.size() - 1)]).capitalize()) + " at best"
			if not bool(line.get("caps", true)):
				limit = "May smelt and work %s" % String(line["name"]) if float(line.get("kh", 0.0)) > 0.0 else "Cannot smelt or work; bought, looted and repaired pieces are used"
			rules.append({"values": [String(line["name"]).capitalize(), "x%s" % RecKit.num(float(line.get("factor", 1.0))) if bool(line.get("open", false)) else "Unavailable", limit]})
		RecKit.grid(content, ["Line", "Learning factor", "Recorded use / quality limit"], rules, [1.2, 1, 2.8]))

## Records uses flexible cells; the town report's fixed funding/header rows do not
## fit inside an expanded Records card on a narrow window. Read the same snapshot.
static func _research_account(scr, capital: Dictionary, fid: String, report: Dictionary, content: VBoxContainer) -> void:
	if bool(report.get("has", false)):
		var lead := String(report.get("lead", ""))
		var till := float(report.get("till", 0.0))
		RecKit.metrics(content, [
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
	RecKit.grid(content, ["Funding and actual output", "Recorded value"], account, [1.4, 2])
	var allocations := []
	for line: Dictionary in report.get("lines", []):
		var share := "%.1f%%" % (100.0 * float(line.get("share", 0.0))) if bool(line.get("active", false)) else "-"
		allocations.append({"values": [String(line["name"]).capitalize(), share, "%.1f" % float(line.get("budget_on", 0.0)), "%.2f" % float(line.get("staff_on", 0.0))]})
	RecKit.grid(content, ["Line", "Planned share", "Coins/day", "Staff allocation"], allocations, [1.4, 1, 1, 1.2])
	RecKit.disclosure(content, "How to read the accounts", func(box):
		for text in [
			"Supporting staff excludes the head; paid places include the head.",
			"Know-how includes starting knowledge. Saved points may accumulate before know-how rises.",
			"House activity is the last recorded production state. Planned shares, coins and staff are allocations, not measured per-line output.",
			"A zero transfer can leave a funded till. Output covers all lines together; per-line speed and completion dates are not tracked."]:
			RecKit.line(box, text, "Small"))
	var weeks := []
	for entry in history:
		weeks.append({"values": ["Day %d" % (int(entry[0]) + 1), "%.1f" % float(entry[1])]})
	if weeks.is_empty(): RecKit.line(content, "No completed weeks recorded.", "Muted")
	else: RecKit.grid(content, ["Completed week, oldest first", "Research points"], weeks, [1.6, 1])
	var events := []
	for entry in report.get("log", []):
		var text := String(entry)
		events.append({"values": [text], "tap": func(): scr.page("Research event", func(box): RecKit.line(box, text))})
	if events.is_empty(): RecKit.line(content, "No research events recorded.", "Muted")
	else: RecKit.grid(content, ["Log book, oldest first"], events)
