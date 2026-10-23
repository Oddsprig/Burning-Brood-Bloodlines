class_name TownEconTab
extends RefCounted
## Town screen, "Town" tab (economy spec 1, section 12): days of food, beer, wine and firewood; ore and bars
## with days of smithing; wood and stone; the arms stock; businesses with their state; prices with an arrow
## and the reason; treasury, tax, wages, population trend; specialties; the head. Tap a family for its record.
## View over town.econ; Orders exposes ruler-authorized purchases. Tap targets >= 48 px.

const SECTIONS := ["Overview", "People", "Work", "Stores", "Land", "Accounts", "Prices", "Orders", "Research"]

static func build(host: Control, t: Dictionary) -> Control:
	if not TownEcon.has_econ(t):
		var empty := UiKit.vbox()
		empty.add_child(UiKit.label("Nobody here keeps accounts.", "Muted"))
		return empty
	var e: Dictionary = t["econ"]
	var root := UiKit.vbox(8)
	root.name = "TownDashboard"
	UiKit.expand(root, true, true)
	var metrics := GridContainer.new()
	metrics.name = "TownMetrics"
	metrics.columns = 1 if host.size.x < 600 else 3
	root.resized.connect(func(): metrics.columns = 1 if host.size.x < 600 else 3)
	metrics.add_theme_constant_override("h_separation", 8)
	metrics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(metrics)
	var supply := TownEcon.supply_level(t)
	var tone: Color = {"well": UiTheme.GOOD, "short": UiTheme.WARN, "starving": UiTheme.BAD}.get(supply, UiTheme.WOOD_3)
	metrics.add_child(_metric("Supply reserve", "%d food days" % int(TownEcon.days_food(t)), TownEcon.supply_word(supply), tone))
	var population: Dictionary = Population.summary(e)
	metrics.add_child(_metric("Residents", UiKit.thousands(int(population["population"])), "%d tracked families · %d households" % [int(population["tracked_families"]), int(population["households"])], UiTheme.BLUE))
	metrics.add_child(_metric("Treasury", UiKit.thousands(int(e["treasury"])) + " coins", "Town wages %d/day" % int(round(float(e["stats"].get("town_wages", 0.0)))), UiTheme.WOOD_3))
	var current := String(host.get_meta("town_econ_section", "Overview"))
	if not current in SECTIONS:
		current = "Overview"
	metrics.visible = current != "Research"
	var body := UiKit.vbox(6)
	body.name = "TownSection"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nav := UiKit.tab_strip(SECTIONS, current, func(section): _select_section(host, t, body, String(section)))
	nav.name = "TownSections"
	for child in nav.get_children():
		var button := child as Button
		button.custom_minimum_size = Vector2(64, 48)
		button.add_theme_font_size_override("font_size", 18)
	var navigation := ScrollContainer.new()
	navigation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	navigation.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(navigation)
	navigation.add_child(nav)
	var scroll := UiKit.scroll()
	scroll.name = "TownSectionScroll"
	root.add_child(scroll)
	scroll.add_child(body)
	_render_section(host, t, body, current)
	return root

static func _metric(title: String, value: String, detail: String, tone: Color) -> PanelContainer:
	var card := UiKit.panel("Card")
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.WOOD_3, tone, 2, 6, 10, 6))
	var v := UiKit.vbox(1)
	card.add_child(v)
	v.add_child(UiKit.label(title, "Muted"))
	var number := UiKit.label(value, "H2", true)
	number.add_theme_font_size_override("font_size", 24)
	v.add_child(number)
	var small := UiKit.label(detail, "Small", true)
	small.add_theme_color_override("font_color", UiTheme.INK_SOFT if tone.get_luminance() < 0.25 else tone)
	v.add_child(small)
	return card

static func _render_section(host: Control, t: Dictionary, body: VBoxContainer, section: String) -> void:
	UiKit.clear(body)
	var e: Dictionary = t["econ"]
	match section:
		"People": _people(host, t, body)
		"Work": _work(host, t, body)
		"Stores": _stores(t, body)
		"Land": _land(host, t, body)
		"Accounts": _accounts(t, body)
		"Prices": _prices(host, t, body)
		"Orders": TownOrdersTab.build(host, t, body)
		"Research": TownResearchTab.build(host, t, body)
		_: _overview_panel(host, t, body)
	var scroll := body.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = 0

static func _select_section(host: Control, t: Dictionary, body: VBoxContainer, section: String) -> void:
	if not section in SECTIONS:
		return
	host.set_meta("town_econ_section", section)
	_render_section(host, t, body, section)
	var scroll := body.get_parent() as ScrollContainer
	var root: Node = scroll.get_parent() if scroll != null else null
	var metrics: Control = root.get_node_or_null("TownMetrics") as Control if root != null else null
	if metrics != null:
		metrics.visible = section != "Research"
	var nav: Node = root.find_child("TownSections", true, false) if root != null else null
	if nav != null:
		for child in nav.get_children():
			var button := child as Button
			button.theme_type_variation = "TabOn" if button.text == section else "Tab"

## Identical column weights in every row keep the figures aligned at all window sizes.
## Wrapping cells, rather than a minimum-width sidebar, keep even long names within the page.
static func _table_row(parent: VBoxContainer, values: Array, weights: Array, header: bool = false) -> HBoxContainer:
	var panel := UiKit.panel()
	panel.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.PARCH_2 if header else UiTheme.WOOD_3, UiTheme.PARCH_3, 1, 3, 8, 6))
	parent.add_child(panel)
	var row := UiKit.hbox(10)
	panel.add_child(row)
	for i in values.size():
		var cell: Control
		if values[i] is Control:
			cell = values[i]
		else:
			cell = UiKit.label(String(values[i]), "Muted" if header else "Small", true)
			if header:
				cell.add_theme_font_override("font", UiTheme.bold())
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = float(weights[i])
		cell.custom_minimum_size.x = 80.0 * float(weights[i])
		row.add_child(cell)
	return row

static func _heading(body: VBoxContainer, text: String) -> void:
	body.add_child(UiKit.label(text, "H2", true))

## Facts in a row flow into compact tiles (label over value) instead of full-width two-column rows.
static func _fact(body: VBoxContainer, key: String, value: String) -> void:
	var flow: HFlowContainer = null
	if body.get_child_count() > 0 and body.get_child(-1).has_meta("facts"): flow = body.get_child(-1)
	if flow == null:
		flow = HFlowContainer.new(); flow.set_meta("facts", true)
		flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow.add_theme_constant_override("h_separation", 8); flow.add_theme_constant_override("v_separation", 8)
		body.add_child(flow)
	var tile := UiKit.panel("Card")
	tile.custom_minimum_size.x = 260
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_child(tile)
	var v := UiKit.vbox(0)
	tile.add_child(v)
	v.add_child(UiKit.label(key, "Muted", true))
	var val := UiKit.label(value, "", true)
	val.add_theme_font_size_override("font_size", 22)
	v.add_child(val)

static func _badge(text: String, tone: Color) -> Control:
	# A wrapping badge remains readable for "market can't pay" on a small window.
	var p := UiKit.panel()
	p.add_theme_stylebox_override("panel", UiTheme.sb(tone, tone.darkened(0.25), 1, 4, 6, 3))
	var label := UiKit.label(text, "Small", true)
	label.add_theme_color_override("font_color", UiTheme.WOOD if tone.get_luminance() > 0.45 else UiTheme.LIGHT)
	p.add_child(label)
	return p

static func _overview_panel(host: Control, t: Dictionary, body: VBoxContainer) -> void:
	var e: Dictionary = t["econ"]
	var actions := UiKit.flow()
	body.add_child(actions)
	actions.add_child(UiKit.button("Land map", func(): LandMap.open(host, t), "Row"))
	actions.add_child(UiKit.button("Family register", func(): families_picker(host, t), "Row"))
	var office: Dictionary = Dynasty.town_office(Game, String(t.get("id", "")))
	_heading(body, "%s %s" % [office.get("title", "Ruler"), office.get("name", "")] if bool(office.get("alive", false)) else "Vacant ruling office")
	_fact(body, "Climate", String(e["climate"]).capitalize())
	_fact(body, "Field crops", "%s / %s" % [TownEcon.variety_word(e, "grain").capitalize(), TownEcon.variety_word(e, "fruit").capitalize()])
	_fact(body, "Herd kinds", " / ".join(PackedStringArray(e["herd_kinds"])))
	var deposits := []
	for ore in e["deposits"]:
		deposits.append(TownEcon.label(e, String(ore)).capitalize())
	_fact(body, "Ore deposits", "None" if deposits.is_empty() else " / ".join(PackedStringArray(deposits)))
	for specialty in e["specialties"]:
		_fact(body, "Known for", String(TownEcon.data()["specialties"][specialty]["text"]))
	_fact(body, "Bronze know-how", "%d / 100 · smiths' practice %d" % [int(Businesses.kh_of(e, "bronze")), int(float(e["knowhow"].get("bronze", 0.0)))])
	_fact(body, "Iron know-how", "%d / 100" % int(Businesses.kh_of(e, "iron")))
	_fact(body, "Famine stage", String(Barge.STAGES[clampi(int(e.get("fstage", 0)), 0, 5)]).capitalize())
	_fact(body, "Harvest this year", "×%.2f" % float(e.get("hf", 1.0)))
	_heading(body, "Lately")
	if (e["hist"] as Array).is_empty():
		body.add_child(UiKit.label("No recent entries.", "Muted"))
	for line in (e["hist"] as Array).slice(-5):
		body.add_child(UiKit.label(String(line), "Small", true))
		body.add_child(HSeparator.new())

static func _people(host: Control, t: Dictionary, body: VBoxContainer) -> void:
	var e: Dictionary = t["econ"]
	var c := People.census(e)
	var ages := People.ages(String(TownEcon.culture_of(e)["race"]))
	_heading(body, "People & homes")
	var population: Dictionary = Population.summary(e)
	body.add_child(UiKit.button("Population by race", func(): PoliticsView.open_view("population", String(t["id"]), "town", {"tab": "Town", "econ_section": "People"}), "Row"))
	_fact(body, "Tracked families / common folk groups", "%d / %d" % [int(population["tracked_families"]), int(population["cohorts"])])
	_fact(body, "Common folk private savings", "%.2f coins" % float(population["common_wealth"]))
	_fact(body, "Available to recruit", str(Population.available(t)))
	body.add_child(UiKit.button("Open family register (%d families)" % _live(e), func(): families_picker(host, t), "Row"))
	var history: Array = e["stats"].get("pop_hist", [])
	if history.size() >= 2:
		var delta := int(e["pop"]) - int(history[-2])
		_fact(body, "Population change", "%+d since last season" % delta)
	else:
		_fact(body, "Population change", "No previous season recorded")
	_table_row(body, ["Age group", "People", "Age range"], [2, 1, 2], true)
	_table_row(body, ["Children", str(c["children"]), "Under %d" % int(ages["adult"])], [2, 1, 2])
	_table_row(body, ["Adults", str(c["adults"]), "%d–%d" % [int(ages["adult"]), int(ages["elder"]) - 1]], [2, 1, 2])
	_table_row(body, ["Elders", str(c["elders"]), "%d and older" % int(ages["elder"])], [2, 1, 2])
	_fact(body, "Census", "%d people in %d households" % [int(c["population"]), int(c["households"])])
	_fact(body, "Female / male", "%d / %d" % [int(c["female"]), int(c["male"])])
	_fact(body, "Homeless households", str(c["homeless"]))
	_fact(body, "Empty dwellings", str(c["empty_homes"]))
	_table_row(body, ["Last season", "Births", "Deaths"], [2, 1, 1], true)
	_table_row(body, ["Census events", str(c["births_last"]), str(c["deaths_last"])], [2, 1, 1])
	_fact(body, "Poorhouse places", "%d occupied / %d total" % [int(e.get("shel_n", 0)), Shelter.cap(t)])

static func _work(host: Control, t: Dictionary, body: VBoxContainer) -> void:
	var e: Dictionary = t["econ"]
	_heading(body, "Businesses")
	body.add_child(UiKit.label("Paid places exclude keepers. Academy places include its paid head. Staff offers are coins per day; the head's additional rate is shown in Research.", "Muted", true))
	var rows: Array = (e["biz"] as Array).filter(func(b): return not b.get("closed", false) and (int(b["cap"]) > 0 or int(b["workers"]) > 0 or int(b.get("kw", 0)) > 0 or String(b["type"]) == "academy"))
	rows.sort_custom(func(a, b): return String(a["type"]) < String(b["type"]))
	var weights := [2.6, 1.3, 1.8, 1.2, 2]
	_table_row(body, ["Business", "Paid / places", "Keeper / lead", "Staff offer/day", "State"], weights, true)
	for b in rows:
		var state := String(b["state"])
		var tone: Color = {"busy": UiTheme.GOOD, "hands": UiTheme.WARN, "inputs": UiTheme.BAD, "wages": UiTheme.BAD, "nopay": UiTheme.WARN}.get(state, UiTheme.WOOD_3)
		var keeper := "Working (%d)" % int(b.get("kw", 0)) if int(b.get("kw", 0)) > 0 else ("Absent" if int(b.get("owner", -1)) >= 0 and not String(b["type"]) in ["farm", "estate"] else "-")
		var business := UiKit.vbox(3)
		business.add_child(UiKit.button(Businesses.title(e, b).capitalize(), _business_record.bind(t, int(b["id"])), "Row"))
		var owner_id := int(b.get("owner", -1))
		if owner_id >= 0 and owner_id < e["fams"].size():
			var owner: Dictionary = e["fams"][owner_id]
			business.add_child(UiKit.label("Owner: " + String(owner.get("name", "")), "Small", true))
			business.add_child(UiKit.button("View owner", _family_record.bind(t, owner_id), "Row"))
		if String(b["type"]) == "academy":
			var head_name := Academy.lead_name(e, b)
			keeper = "%s\n%s" % [Academy.lead_title(e), head_name if head_name != "" else "Post vacant"]
			business.add_child(UiKit.label("State-funded", "Muted", true))
			var research := UiKit.button("Research", func(): _select_section(host, t, body, "Research"), "Row")
			research.name = "AcademyResearch"
			research.add_theme_font_size_override("font_size", 17)
			business.add_child(research)
		var status := UiKit.vbox(2)
		status.add_child(_badge(Businesses.state_word(b), tone))
		var why := String(b.get("why", ""))
		if String(b["type"]) == "academy" and why != "":
			status.add_child(UiKit.label(why.capitalize(), "Small", true))
		elif state == "inputs" and why != "":
			status.add_child(UiKit.label("No " + TownEcon.label(e, why), "Small", true))
		var row := _table_row(body, [business, "%d / %d" % [int(b["workers"]), int(b["cap"])], keeper, str(int(round(float(b["wage"])))), status], weights)
		row.tooltip_text = RecData.staff_text(b)
	if rows.is_empty():
		body.add_child(UiKit.label("No active businesses with staff places or working keepers.", "Muted", true))

static func _business_record(t: Dictionary, bid: int) -> void:
	Game.goto("res://ui/records.tscn", {"view": "town", "id": String(t["id"]), "tab": "Businesses", "back": "town", "back_params": {"tab": "Town", "econ_section": "Work"}})
	if Game.main != null and Game.main.current != null:
		Game.main.current.call_deferred("open_business", t, bid)

static func _family_record(t: Dictionary, fid: int) -> void:
	Game.goto("res://ui/records.tscn", {"view": "town", "id": String(t["id"]), "tab": "Register", "back": "town", "back_params": {"tab": "Town", "econ_section": "Work"}})
	if Game.main != null and Game.main.current != null:
		Game.main.current.call_deferred("open_family", t, fid)

static func _stores(t: Dictionary, body: VBoxContainer) -> void:
	var e: Dictionary = t["econ"]
	_heading(body, "Reserve coverage")
	var metal: Dictionary = Metallurgy.summary(e)
	_heading(body, "Metalworking")
	body.add_child(UiKit.label(String(metal["policy"]), "", true))
	_fact(body, "Recycled market equipment", "%d items · %.2f kg" % [int(metal["recycled_items"]), float(metal["recycled_kg"])])
	_fact(body, "Owned copper/tin scrap", "%.2f kg" % float(metal["scrap_kg"]))
	_fact(body, "Bronze bars", "%d in stock · %d made in the current ledger" % [int(metal["bronze_bars"]), int(metal["bronze_made"])])
	body.add_child(UiKit.label("Issued and legendary equipment stays with its owner. Recycling uses unissued market gear and keeps the recovered material in stock.", "Muted", true))
	var use := TownEcon.household_use(e, Calendar.season_index(float(e["day"])), ["beer", "wine", "wood"])
	_table_row(body, ["Supply", "Days", "Basis"], [2, 1, 3], true)
	_table_row(body, ["Food", str(int(TownEcon.days_food(t))), "Market + barns + households + granary"], [2, 1, 3])
	for g in ["beer", "wine", "wood"]:
		var have := float(e["stock"].get(g, 0)) + float(e["hh"].get(g, 0))
		_table_row(body, [TownEcon.label(e, g).capitalize() if g != "wood" else "Firewood", str(int(have / maxf(0.1, float(use.get(g, 0.1))))), "Market + households / seasonal daily use"], [2, 1, 3])
	_heading(body, "Physical stocks")
	body.add_child(UiKit.label("Stocks stay separate by holder; quantities use each good's own unit.", "Muted", true))
	var weights := [2.5, 1.5, 1, 1, 1]
	_table_row(body, ["Good", "Unit", "Market", "Barns", "Households"], weights, true)
	for g in Goods.ids():
		_table_row(body, [TownEcon.label(e, g).capitalize(), Goods.unit_of(g), str(int(e["stock"].get(g, 0))), str(int(e["barn"].get(g, 0))), str(int(e["hh"].get(g, 0)))], weights)
	_fact(body, "Granary food", "%d meals' worth" % int(e["granary"]))
	var smith := 0.0
	for b in e["biz"]:
		if b["type"] in ["weaponsmith", "armorsmith"] and not b.get("closed", false):
			smith += float(b["workers"]) * float(TownEcon.data()["businesses"][b["type"]]["rate"]) * 4.0
	_heading(body, "Bars for smithing")
	if smith <= 0.0:
		body.add_child(UiKit.label("No current paid smithing work to estimate days against.", "Muted", true))
	else:
		for g in ["copper_bars", "tin_bars", "bronze_bars", "iron_bars", "steel_bars"]:
			_fact(body, Goods.good_name(g).capitalize(), "About %d days at current smithing rate" % int(float(e["stock"].get(g, 0)) / smith))
	_heading(body, "Arms on the stalls · %d pieces" % (t.get("shop", []) as Array).size())
	var counts := {}
	for item in t.get("shop", []):
		var key := "%s %s" % [item.material, item.tmpl().get("name", item.tid)]
		counts[key] = int(counts.get(key, 0)) + 1
	for key in counts:
		_fact(body, String(key).capitalize(), str(counts[key]))
	if counts.is_empty():
		body.add_child(UiKit.label("The stalls are bare.", "Muted"))
	_heading(body, "The %s's armory" % String(e["head"]["title"]))
	var armory := ArmsTrade.armory_lines(t)
	if armory.is_empty():
		body.add_child(UiKit.label("Empty, and nothing wanted.", "Muted"))
	for line in armory:
		body.add_child(UiKit.label(String(line), "Small", true))
		body.add_child(HSeparator.new())
	for line in ArmsTrade.armory_log(t).slice(-3):
		body.add_child(UiKit.label(String(line), "Small", true))

static func _land(host: Control, t: Dictionary, body: VBoxContainer) -> void:
	var e: Dictionary = t["econ"]
	var s := TownEcon.land_summary(e)
	_heading(body, "Land ownership")
	body.add_child(UiKit.button("Open land map", func(): LandMap.open(host, t), "Row"))
	_fact(body, "Territory", "%d acres" % int(s["territory"]))
	_fact(body, "Family holdings", "%d acres" % int(s["families"]))
	_fact(body, "Town estate", "%d acres" % int(s["estate"]))
	_fact(body, "Unclaimed or common", "%d acres" % int(s["common"]))
	_table_row(body, ["Crop", "Family acres", "Estate acres"], [2, 1, 1], true)
	var crops: Array = s["fam_crops"].keys()
	for crop in s["est_crops"]:
		if not crops.has(crop): crops.append(crop)
	crops.sort()
	for crop in crops:
		_table_row(body, [TownEcon.variety_word(e, String(crop)).capitalize(), str(int(s["fam_crops"].get(crop, 0))), str(int(s["est_crops"].get(crop, 0)))], [2, 1, 1])
	_heading(body, "Herds")
	_table_row(body, ["Animal", "Total"], [2, 1], true)
	for animal in s["herds"]:
		if int(s["herds"][animal]) > 0:
			_table_row(body, [String(animal).capitalize(), str(int(s["herds"][animal]))], [2, 1])
	_fact(body, "Family / estate animals", "%d / %d" % [int(s["fam_herd"]), int(s["est_herd"])])

static func _accounts(t: Dictionary, body: VBoxContainer) -> void:
	var e: Dictionary = t["econ"]
	var stats: Dictionary = e["stats"]
	var tax: Dictionary = e["tax"]
	_heading(body, "Ruling household")
	body.add_child(UiKit.label(PoliticsView.levy_text(stats), "", true))
	var budget: Dictionary = Feudal.budget(Game, String(t.get("id", "")))
	if not budget.is_empty():
		body.add_child(UiKit.label(PoliticsView.tax_text(budget), "", true))
		body.add_child(UiKit.button("Manage taxes & defence", func(): PoliticsView.open_view("politics", String(t.get("id", "")), "town", {"tab": "Town", "econ_section": "Accounts"}), "Row"))
	var feudal: Dictionary = Feudal.summary(Game, String(t.get("id", "")))
	if feudal.has("tribute"):
		_fact(body, "Last private tribute to liege", "%.2f coins" % float(feudal["tribute"]))
	_heading(body, "Treasury & public spending")
	_fact(body, "Treasury", "%d coins" % int(e["treasury"]))
	_fact(body, "Tax collected this season", "%d coins" % int(tax.get("paid", 0.0)))
	_fact(body, "Tax lost for want of collectors", "%d%%" % int(float(tax.get("leak", 0.0)) * 100.0))
	_fact(body, "Town wages", "%d coins/day" % int(round(float(stats.get("town_wages", 0.0)))))
	var bill := Army.town_bill(Game, t)
	_fact(body, "%s wage bill" % Army.town_tier(t).capitalize(), "%d coins/day · paid %d" % [int(round(bill)), int(round(float(stats.get("militia_wages", 0.0))))])
	_fact(body, "Treasury cover for this bill", "%d days" % int(float(e["treasury"]) / bill) if bill > 0.0 else "No bill")
	_fact(body, "Poorhouse", "%d / %d places · %d coins/day" % [int(e.get("shel_n", 0)), Shelter.cap(t), int(round(float(stats.get("shelter_cost", 0.0))))])
	if float(stats.get("army_levy", 0.0)) > 0.0:
		_fact(body, "Last army levy", "%d coins" % int(stats["army_levy"]))
	_heading(body, "Loan book")
	var book := Loans.book(e)
	for pair in [["Family debt outstanding", "owed"], ["Families owing", "debtors"], ["Families in arrears", "arrears"], ["Total coins lent", "lent"], ["Interest earned", "interest"], ["Coins written off", "written_off"]]:
		_fact(body, String(pair[0]), str(int(book[pair[1]])))
	_fact(body, "Loan rate", "%.1f%% per week" % (Loans.rate(e) * 100.0))
	_heading(body, "Wages, prices & coin")
	_fact(body, "Day wage", "%d coins · field hands %d" % [int(round(Barge.day_wage(e))), int(round(Barge.day_wage(e) * float(Barge.B()["labour"]["field"])))])
	_fact(body, "Price level", "%.2f" % Barge.pl(e))
	var shortage := Barge.shortage(e)
	_table_row(body, ["Coin supply", _badge("Short (%d%%)" % int(round(shortage * 100.0)) if shortage > 0.0 else "Enough", UiTheme.WARN if shortage > 0.0 else UiTheme.GOOD)], [1, 2])
	if e.has("mint_biz"):
		_fact(body, "Coins cast by mint", str(int(float(stats.get("cast", 0.0)))))

static func _prices(host: Control, t: Dictionary, body: VBoxContainer) -> void:
	_heading(body, "Market prices")
	body.add_child(UiKit.label("Coins per unit. Trends compare with the last recorded weekly price; select Details for the reason.", "Muted", true))
	var filters := UiKit.hbox(8)
	body.add_child(filters)
	var search := LineEdit.new()
	search.name = "PriceSearch"
	search.placeholder_text = "Search goods or price reasons"
	search.text = String(host.get_meta("town_price_search", ""))
	search.custom_minimum_size.y = 48
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	var category := OptionButton.new()
	category.name = "PriceCategory"
	category.custom_minimum_size = Vector2(150, 48)
	var categories := [""]
	for g in Goods.ids():
		var key := String(Goods.table()[g].get("cat", "other"))
		if not categories.has(key): categories.append(key)
	categories.sort()
	var current := String(host.get_meta("town_price_category", ""))
	for key in categories:
		category.add_item("All categories" if key == "" else {"raw": "Raw materials", "made": "Made goods", "bars": "Metal bars", "arms": "Arms"}.get(key, String(key).capitalize()))
		category.set_item_metadata(category.item_count - 1, key)
	category.select(maxi(0, categories.find(current)))
	filters.add_child(category)
	var list := UiKit.vbox(3)
	list.name = "PriceRows"
	body.add_child(list)
	var refill := func():
		var selected := String(category.get_item_metadata(category.selected))
		host.set_meta("town_price_search", search.text)
		host.set_meta("town_price_category", selected)
		_price_rows(host, t, list, search.text, selected)
	search.text_changed.connect(func(_text): refill.call())
	category.item_selected.connect(func(_index): refill.call())
	refill.call()

static func _price_rows(host: Control, t: Dictionary, list: VBoxContainer, query: String, category: String) -> void:
	UiKit.clear(list)
	var e: Dictionary = t["econ"]
	var weights := [3, 1.5, 1.2, 1.2, 1.2]
	_table_row(list, ["Good / unit", "Coins", "Trend", "Market stock", "Reason"], weights, true)
	var count := 0
	for g in Goods.ids():
		var label := TownEcon.label(e, g).capitalize()
		var why := String(e["why"].get(g, ""))
		if category != "" and String(Goods.table()[g].get("cat", "other")) != category:
			continue
		if query.strip_edges() != "" and not (label + " " + why).to_lower().contains(query.strip_edges().to_lower()):
			continue
		count += 1
		var price := Goods.price_f(t, g)
		var previous := float(e.get("pweek", {}).get(g, price))
		var trend := "↑ Up" if price > previous * 1.05 else ("↓ Down" if price < previous * 0.95 else "= Steady")
		var detail := UiKit.button("Details", func():
			UiKit.message(host, label + " · price details", ["Current price: %.1f coins per %s" % [price, Goods.unit_of(g)], "Last weekly price: %.1f coins" % previous, "Market stock: %d %s" % [int(Goods.supply(t, g)), Goods.unit_of(g)], "Reason: " + why if why != "" else "No price reason recorded."]), "Row")
		detail.tooltip_text = why if why != "" else "No price reason recorded."
		detail.add_theme_font_size_override("font_size", 17)
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var row := _table_row(list, [label + "\n" + Goods.unit_of(g), "%.1f" % price, _badge(trend, UiTheme.BLUE if trend != "= Steady" else UiTheme.WOOD_3), str(int(Goods.supply(t, g))), detail], weights)
		row.tooltip_text = why
	if count == 0:
		list.add_child(UiKit.label("No goods match these filters.", "Muted", true))

## Land at the top of the Town tab, summed from the records: "Land: 1240 acres in the territory. Families hold
## 1190 (barley 920, apples 270); the town estate 50 (barley 50); unclaimed or common 0. / Herds: 140 cattle, 60 pigs
## (families 190, estate 10)." Families are the resident (not gone) households; the estate is the head's.
static func land_line(e: Dictionary) -> String:
	var s := TownEcon.land_summary(e)
	var herds := []
	for a in s["herds"]:
		if int(s["herds"][a]) > 0:
			herds.append(TownEcon.n_of(int(s["herds"][a]), String(a)))
	return "Land: %d acres in the territory. Families hold %d%s; the town estate %d%s; unclaimed or common %d.\nHerds: %s." % [
		int(s["territory"]), int(s["families"]), _by_crop(e, s["fam_crops"]), int(s["estate"]), _by_crop(e, s["est_crops"]), int(s["common"]),
		("none" if herds.is_empty() else ", ".join(PackedStringArray(herds)) + " (families %d, estate %d)" % [int(s["fam_herd"]), int(s["est_herd"])])]

## " (barley 420, apples 90)" from {crop: acres}; "" when empty.
static func _by_crop(e: Dictionary, land: Dictionary) -> String:
	var parts := []
	for c in land:
		if int(land[c]) > 0:
			parts.append("%s %d" % [TownEcon.variety_word(e, String(c)), int(land[c])])
	return "" if parts.is_empty() else " (%s)" % ", ".join(PackedStringArray(parts))

static func _live(e: Dictionary) -> int:
	var n := 0
	for f in e["fams"]:
		if not f.get("gone", false) and not f.get("estate", false) and not Population.is_cohort(f):
			n += 1
	return n

static func _overview(t: Dictionary, e: Dictionary) -> String:
	var D := TownEcon.data()
	var sp := []
	for s in e["specialties"]:
		sp.append(D["specialties"][s]["text"])
	var ph: Array = e["stats"].get("pop_hist", [])
	var trend := ""
	if ph.size() >= 2:
		var d := int(e["pop"]) - int(ph[-2])
		trend = " (%s%d since last season)" % ["+" if d >= 0 else "", d]
	var tx: Dictionary = e["tax"]
	var crops := "%s, %s" % [TownEcon.variety_word(e, "grain"), TownEcon.variety_word(e, "fruit")]
	var deps := []
	for o in e["deposits"]:
		deps.append(String(o).split("_")[0])
	# economy spec 2: the militia (a city's guard) by rank, out of the treasury; days of pay left
	var mbill := Army.town_bill(Game, t)
	var tier := Army.town_tier(t)
	var mil := "%s wage bill %d coins a day (paid %d), %s of pay in the treasury" % [tier, int(round(mbill)),
		int(round(float(e["stats"].get("militia_wages", 0.0)))), ("%d days" % int(float(e["treasury"]) / mbill)) if mbill > 0.0 else "no bill"]
	mil += "; poorhouse %d of %d places (%d coins a day)" % [int(e.get("shel_n", 0)), Shelter.cap(t), int(round(float(e["stats"].get("shelter_cost", 0.0))))]
	if float(e["stats"].get("army_levy", 0.0)) > 0.0:
		mil += "; last army levy %d coins" % int(e["stats"]["army_levy"])
	return "%s climate; fields of %s; herds of %s%s. Known for its %s.\nPeople: %d in %d families, %d homes%s.\nTreasury: %d coins. Tax this season: %d coins collected%s; town wages %d coins a day; %s.\nKnow-how: bronze %d of 100 (the smiths' practice %d), iron %d. Food supply: %s." % [
		String(e["climate"]).capitalize(), crops, ", ".join(PackedStringArray(e["herd_kinds"])),
		("; " + ", ".join(PackedStringArray(deps)) + " ore") if not deps.is_empty() else "",
		" and ".join(PackedStringArray(sp)), int(e["pop"]), _live(e), int(e["homes"]), trend,
		int(e["treasury"]), int(tx.get("paid", 0.0)), (", %d%% lost for want of collectors" % int(float(tx.get("leak", 0.0)) * 100.0)) if float(tx.get("leak", 0.0)) > 0.01 else "",
		int(round(float(e["stats"].get("town_wages", 0.0)))), mil,
		int(Businesses.kh_of(e, "bronze")), int(float(e["knowhow"].get("bronze", 0.0))), int(Businesses.kh_of(e, "iron")), TownEcon.supply_word(TownEcon.supply_level(t))] + "\n" + _barge_line(e)

## Barge: the day wage, the price level, the coin (shortage, the mint), the famine stage.
static func _barge_line(e: Dictionary) -> String:
	var mint := ""
	if e.has("mint_biz"):
		mint = "; the mint has cast %d coins" % int(float(e["stats"].get("cast", 0.0)))
	return "Day wage %d coins (field hands %d); price level %.2f; coin %s%s; %s; harvest this year x%.2f." % [
		int(round(Barge.day_wage(e))), int(round(Barge.day_wage(e) * float(Barge.B()["labour"]["field"]))), Barge.pl(e),
		("short (" + str(int(round(Barge.shortage(e) * 100.0))) + "%)") if Barge.shortage(e) > 0.0 else "enough", mint,
		Barge.STAGES[clampi(int(e.get("fstage", 0)), 0, 5)].capitalize(), float(e.get("hf", 1.0))]

## "Food: 34 days", "Barley ale: 12 days" ... "Copper bars: 40 (about 9 days of smithing)".
static func stores_lines(t: Dictionary) -> Array:
	var e: Dictionary = t["econ"]
	var D := TownEcon.data()
	var use := TownEcon.household_use(e, Calendar.season_index(float(e["day"])), ["beer", "wine", "wood"])
	var lines := []
	lines.append("Food: %d days (%d in the market, %d in the barns, %d in the granary)" % [int(TownEcon.days_food(t)),
		int(Goods.supply(t, "food")), int(e["barn"].get("grain", 0)) + int(e["barn"].get("fruit", 0)) + int(e["barn"].get("meat", 0)), int(e["granary"])])
	for g in ["beer", "wine", "wood"]:
		var have := float(e["stock"].get(g, 0)) + float(e["hh"].get(g, 0))
		lines.append("%s: %d days" % [TownEcon.label(e, g).capitalize() if g != "wood" else "Firewood", int(have / maxf(0.1, float(use.get(g, 0.1))))])
	var smith := 0.0
	for b in e["biz"]:
		if b["type"] in ["weaponsmith", "armorsmith"] and not b.get("closed", false):
			smith += float(b["workers"]) * float(D["businesses"][b["type"]]["rate"]) * 4.0   # ~4 bars a piece
	for g in ["copper_ore", "tin_ore", "iron_ore", "copper_bars", "tin_bars", "bronze_bars", "iron_bars", "steel_bars"]:
		var n := int(e["stock"].get(g, 0))
		if n <= 0 and g.ends_with("ore"):
			continue
		var days := ""
		if g.ends_with("bars") and smith > 0.0:
			days = " (about %d days of smithing)" % int(float(n) / smith)
		lines.append("%s: %d%s" % [Goods.good_name(g).capitalize(), n, days])
	lines.append("Wood: %d loads, stone: %d loads" % [int(e["stock"].get("wood", 0)), int(e["stock"].get("stone", 0))])
	return lines

## "12 pieces: 3 copper arming swords, 2 tin kite shields, ..."
static func arms_text(t: Dictionary) -> String:
	var counts := {}
	for it in t.get("shop", []):
		var k := "%s %s" % [it.material, it.tmpl().get("name", it.tid)]
		counts[k] = int(counts.get(k, 0)) + 1
	if counts.is_empty():
		return "The stalls are bare."
	var parts := []
	for k in counts:
		parts.append("%d %s" % [int(counts[k]), k])
	return "%d pieces: %s" % [(t.get("shop", []) as Array).size(), ", ".join(PackedStringArray(parts))]

## "Barley ale  1.2 gold  ^ barley ale up: brewer short-handed"
static func price_lines(t: Dictionary) -> Array:
	var e: Dictionary = t["econ"]
	var out := []
	var pweek: Dictionary = e.get("pweek", {})
	for g in Goods.ids():
		var p := Goods.price_f(t, g)
		var old := float(pweek.get(g, p))
		var arrow := "^" if p > old * 1.05 else ("v" if p < old * 0.95 else "=")
		var why: String = e["why"].get(g, "")
		out.append("%s %s: %.1f coins%s" % [arrow, TownEcon.label(e, g).capitalize(), p, ("  (" + why + ")") if why != "" else ""])
	return out

static func families_picker(host: Control, t: Dictionary) -> void:
	var e: Dictionary = t["econ"]
	var opts := []
	var fams: Array = (e["fams"] as Array).filter(func(f): return not f.get("gone", false) and not Population.is_cohort(f))
	fams.sort_custom(func(a, b):
		if a.get("estate", false) != b.get("estate", false):
			return a.get("estate", false)
		return Families.hardship(a) > Families.hardship(b) if Families.hardship(a) != Families.hardship(b) else String(a["name"]) < String(b["name"]))
	for f in fams:
		var tag := "the town's land" if f.get("estate", false) else ("%d people, %d acres, %d coins%s" % [Families.people(f), Families.acres(f), int(f["purse"]),
			", hard times" if Families.hardship(f) >= 0.35 else ""])
		opts.append({"text": ("The %s" % f["name"]) if not f.get("estate", false) else "Town land", "value": int(f["id"]), "detail": tag})
	UiKit.picker(host, "Families of %s" % t["name"], opts, func(fid): family_modal(host, t, int(fid)), 820)

static func family_modal(host: Control, t: Dictionary, fid: int) -> void:
	var e: Dictionary = t["econ"]
	var f: Dictionary = e["fams"][fid]
	f["named"] = true   # an opened family keeps its life events from now on (spec 6)
	var lines := Families.describe(t, e, f)
	var race: String = TownEcon.data()["cultures"][e["culture"]]["race"]
	if not f.get("estate", false):
		# the register: everyone by name with age and state (recruits for hire, with your company, in service, at home)
		var ppl := ["Household:"]
		for m in People.register(Game, t, fid):
			ppl.append("  " + Persons.person_line(m))
		for i in ppl.size():
			lines.insert(1 + i, ppl[i])
		var _r := race
	UiKit.message(host, "The %s family" % f["name"] if not f.get("estate", false) else "Town land of %s" % t["name"], lines)

## Named family members away from home (the company, armies, militia in the field, caravan guards, outlaws),
## found by their real Unit records so the names match the story lines. Only built when the record is opened.
static func _away_members(t: Dictionary, fid: int) -> Array:
	var out := []
	var tid: String = t.get("id", "")
	for u in Game.company:
		if not u.dead and u.home_town == tid and u.family == fid:
			out.append("%s (with your company)" % u.name)
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		var what: String = {"bandit": "with an outlaw band", "deserter": "a deserter", "caravan": "guarding a caravan",
			"militia": "in the militia"}.get(String(wb.get("kind", "")), "with a %s band" % CampaignWorld.faction_name(String(wb.get("faction", ""))))
		for u in wb.get("units", []):
			if u is Unit and not u.dead and u.home_town == tid and u.family == fid:
				out.append("%s (%s)" % [u.name, what])
	return out
