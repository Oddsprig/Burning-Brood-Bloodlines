class_name PopulationView
extends Control
## Authoritative native census, private owners and current recruiting capacity.
var body: VBoxContainer
var race_grid: GridContainer
var fact_grid: GridContainer
var town_id := ""
var back := "town"
var return_location := ""
var back_params: Dictionary = {}
var population_summary: Dictionary = {}
var races: Array = []
var budget: Dictionary = {}

func _ready() -> void:
	town_id = String(Game.screen_params.get("town_id", Game.location))
	if town_id == "": town_id = String(Dynasty.selected(Game).get("town_id", ""))
	back = String(Game.screen_params.get("back", "town"))
	return_location = String(Game.screen_params.get("return_location", Game.location))
	back_params = Game.screen_params.get("back_params", {}).duplicate(true)
	var frame := UiKit.screen_frame(self, "Population")
	var heading: Label = frame["title"]
	heading.add_theme_font_size_override("font_size", 24)
	heading.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	heading.custom_minimum_size.x = 0
	frame["bar"].add_child(UiKit.button("Back", _back, "Row", 72))
	var scroll := UiKit.scroll()
	frame["root"].add_child(scroll)
	body = UiKit.vbox(10)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(body)
	resized.connect(_fit)
	_refresh()

func _context() -> Dictionary:
	return {"town_id": town_id, "back": back, "return_location": return_location, "back_params": back_params}

func _refresh() -> void:
	UiKit.clear(body)
	race_grid = null
	var town: Dictionary = Game.world.get("towns", {}).get(town_id, {})
	var econ: Dictionary = town.get("econ", {})
	if econ.is_empty():
		body.add_child(UiKit.label("No population record for this settlement.", "Muted", true))
		return
	population_summary = Population.summary(econ)
	races = Population.race_rows(econ)
	body.add_child(UiKit.label(String(town.get("name", town_id)), "H2", true))
	var links := UiKit.flow()
	body.add_child(links)
	links.add_child(UiKit.button("Politics", func(): PoliticsView.open_view("politics", town_id, "population", _context()), "Row"))
	links.add_child(UiKit.button("Family register", _records.bind("Register"), "Row"))
	links.add_child(UiKit.button("Businesses", _records.bind("Businesses"), "Row"))
	budget = Feudal.budget(Game, town_id)
	var people := int(population_summary.get("population", 0))
	var food := int(TownEcon.days_food(town))
	var recruit := Population.available(town)
	var lead := "Food runs out in %d days." % food if food < 30 else "%s people live here; %d could be recruited." % [UiKit.thousands(people), recruit]
	body.add_child(UiKit.label(lead, "Bad" if food < 30 else "H2", true))
	fact_grid = _grid()
	_fact("People", UiKit.thousands(people), "Everyone who lives here, named or not.")
	_fact("Can recruit", str(recruit), "Adults who could be called up now.")
	_fact("Food", "%d days" % food, "How long the stores last at the current rate.")
	_fact("Households", str(int(population_summary.get("households", 0))), "")
	_fact("Named", str(int(population_summary.get("detailed", 0))), "Named residents include soldiers and ruling families.")
	_fact("Common folk", str(int(population_summary.get("anonymous", 0))), "Residents tracked as groups rather than by name.")
	_fact("Away in service", str(int(population_summary.get("away", 0))), "Named people serving elsewhere; counted separately.")
	_fact("Working", str(int(population_summary.get("common_jobs", 0))), "Common folk with a job.")
	_fact("Common savings", UiKit.compact_coins(float(population_summary.get("common_wealth", 0))), "Private savings of the common folk; not yours to spend.")
	_fact("All savings", UiKit.compact_coins(float(population_summary.get("private_wealth", 0))), "Private savings of every household.")
	_fact("Families", str(int(population_summary.get("tracked_families", 0))), "Families in the register.")
	_fact("Folk groups", str(int(population_summary.get("cohorts", 0))), "")
	body.add_child(_health_card())
	if not budget.is_empty():
		var service := UiKit.panel("Card")
		body.add_child(service)
		var words := UiKit.vbox(6)
		service.add_child(words)
		words.add_child(UiKit.label("People in service", "H2", true))
		words.add_child(UiKit.label(PoliticsView.defence_text(budget), "", true))
		words.tooltip_text = "Militia are existing residents; calling them up takes hands away from civilian work. Realm army totals cover the whole faction."
		words.add_child(UiKit.label(PoliticsView.tax_text(budget), "", true))
		var warning := PoliticsView.budget_warnings(budget)
		if warning != "": words.add_child(UiKit.label(warning, "Bad", true))
		var service_links := UiKit.flow()
		words.add_child(service_links)
		service_links.add_child(UiKit.button("Garrison records", _records.bind("Garrison"), "Row"))
		service_links.add_child(UiKit.button("Public services", _records.bind("Businesses"), "Row"))
		service_links.tooltip_text = "Collectors, the estate, works and mint draw on city funds; the academy draws on realm funds."
	body.add_child(UiKit.label("Residents by race", "H2"))
	race_grid = GridContainer.new()
	race_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	race_grid.add_theme_constant_override("h_separation", 10)
	race_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(race_grid)
	for row: Dictionary in races:
		var panel := UiKit.panel("Card")
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		race_grid.add_child(panel)
		var words := UiKit.vbox(5)
		panel.add_child(words)
		words.add_child(UiKit.label(String(row.get("race", "")).replace("_", " ").capitalize(), "H2", true))
		var n := UiKit.label(UiKit.thousands(int(row.get("population", 0))), "H2")
		n.add_theme_font_size_override("font_size", 26)
		words.add_child(n)
		words.add_child(UiKit.label("%d children · %d adults · %d elders" % [int(row.get("children", 0)), int(row.get("adults", 0)), int(row.get("elders", 0))], "", true))
		words.add_child(UiKit.label("%d can recruit · %d at work" % [int(row.get("recruitable", 0)), int(row.get("common_jobs", 0))], "Muted", true))
		panel.tooltip_text = "%d common folk, %d named, %d away in service, %d families in the register. Savings %.2f coins." % [int(row.get("anonymous", 0)), int(row.get("detailed", 0)), int(row.get("away", 0)), int(row.get("tracked_families", 0)), float(row.get("common_wealth", 0))]
		panel.mouse_filter = MOUSE_FILTER_PASS
	_fit()

## v0.034: sickness, homes and who came and went this season (Migration.report).
func _health_card() -> Control:
	var r := Migration.report(Game, town_id)
	var card := UiKit.panel("Card")
	card.name = "HealthHomesMovement"
	var words := UiKit.vbox(6)
	card.add_child(words)
	words.add_child(UiKit.label("Health, homes and movement", "H2", true))
	if r.is_empty(): return card
	var push := String(r["push"])
	if push != "":
		var why: String = {"war": "fear of war", "hunger": "hunger", "crowd": "crowding, with no house to be had"}[push]
		words.add_child(UiKit.label("Common households are leaving for other towns, driven by %s." % why, "Bad", true))
	var top: Array = []
	for row: Array in (r["diseases"] as Array).slice(0, 3): top.append("%s %d" % [row[0], int(row[1])])
	words.add_child(UiKit.label("Sick now: %d%s · died of sickness this year: %d" % [int(r["sick"]), (" (" + ", ".join(PackedStringArray(top)) + ")") if not top.is_empty() else "", int(r["sick_deaths"])], "", true))
	words.add_child(UiKit.label("%s households in %s homes (room for %d each) · %s without a home of their own · %d empty town houses" % [UiKit.thousands(int(r["households"])), UiKit.thousands(int(r["homes"])), int(r["room"]), UiKit.thousands(int(r["unhoused"])), int(r["empty_homes"])], "", true))
	words.add_child(UiKit.label("This season: left %s · arrived %s" % [Migration.whys(r["left"]), Migration.whys(r["arrived"])], "Muted", true))
	card.tooltip_text = "The common folk catch the same diseases as the named families. Households leave towns at war, in famine, or too crowded with no house to buy, for a town of their own people with room."
	card.mouse_filter = MOUSE_FILTER_PASS
	return card

func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.size_flags_horizontal = SIZE_EXPAND_FILL
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	body.add_child(g)
	return g

func _fact(title: String, value: String, tip: String) -> void:
	var panel := UiKit.panel("Card")
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.tooltip_text = tip
	panel.mouse_filter = MOUSE_FILTER_PASS
	fact_grid.add_child(panel)
	var words := UiKit.vbox(0)
	panel.add_child(words)
	var big := UiKit.label(value, "H2")
	big.add_theme_font_size_override("font_size", 30)
	words.add_child(big)
	words.add_child(UiKit.label(title, "Muted"))

func _fit() -> void:
	if fact_grid != null: fact_grid.columns = maxi(2, mini(6, int(size.x / 250.0)))
	if race_grid != null: race_grid.columns = maxi(1, mini(4, int(size.x / 380.0)))

func _records(tab: String) -> void:
	Game.goto("res://ui/records.tscn", {"view": "town", "id": town_id, "tab": tab, "back": "population", "back_params": _context()})

func _back() -> void:
	Game.location = return_location
	Game.goto(back, back_params)
