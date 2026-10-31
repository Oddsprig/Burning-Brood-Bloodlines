extends Control
## The selected real household, its people and its separately owned accounts.
var body: VBoxContainer
var back := "map"
var member: Dictionary = {}
var accounts_grid: GridContainer
var budget: Dictionary = {}
var notice := ""
var _refresh_pending := false
var margin: MarginContainer

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(PRESET_FULL_RECT)
	back = String(Game.screen_params.get("back", "map"))
	var bg := ColorRect.new()
	bg.color = UiTheme.WOOD
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	margin = MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := UiKit.vbox(10)
	margin.add_child(root)
	var heading := UiKit.hbox()
	heading.add_child(UiKit.label("Your bloodline", "H2", true))
	heading.add_child(UiKit.button("Back", _back, "Row", 72))
	root.add_child(heading)
	var scroll := UiKit.scroll()
	root.add_child(scroll)
	body = UiKit.vbox(10)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(body)
	resized.connect(_fit_layout)
	Game.changed.connect(_queue_refresh)
	_refresh()

func _queue_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true
	call_deferred("_refresh")

func _refresh() -> void:
	_refresh_pending = false
	UiKit.clear(body)
	accounts_grid = null
	if not member.is_empty():
		member = Dynasty.person(Game, String(member.get("person_uid", "")))
		_person_page(member)
		return
	var selected: Dictionary = Dynasty.selected(Game)
	if selected.is_empty():
		body.add_child(UiKit.label("Choose a settlement and a local house to begin your bloodline.", "", true))
		body.add_child(UiKit.button("Choose settlement", func(): Game.goto("house_select")))
		return
	var ruler: Dictionary = Dynasty.ruler(Game)
	var tid := String(selected.get("town_id", ""))
	var office: Dictionary = Dynasty.selected_office(Game)
	var commands_settlement := Dynasty.holds_office(Game)
	if notice != "": body.add_child(UiKit.label(notice, "", true))
	var card := UiKit.panel("Card")
	body.add_child(card)
	var content := UiKit.vbox(8)
	card.add_child(content)
	var identity_row := UiKit.hbox(10)
	content.add_child(identity_row)
	var standard := HouseBanner.new()
	standard.name = "HouseStandard"
	standard.custom_minimum_size = Vector2(84, 100)
	standard.set_style(selected.get("customization", {}))
	identity_row.add_child(standard)
	var house_title := UiKit.label("House " + String(selected.get("house_name", "Your house")), "H2", true)
	house_title.add_theme_font_size_override("font_size", 34)
	house_title.size_flags_vertical = SIZE_SHRINK_CENTER
	identity_row.add_child(house_title)
	var face := DynastyCard.new()
	face.compact = true
	face.size_flags_horizontal = SIZE_SHRINK_BEGIN
	face.pressed.connect(_show_person.bind(ruler))
	content.add_child(face)
	content.add_child(UiKit.label("%s of %s" % [selected.get("title", "House leader"), selected.get("town_name", "")], "", true))
	if not commands_settlement:
		content.add_child(UiKit.label("Local household · Settlement taxes and public forces belong to the ruling house.", "Muted", true))
	if not bool(ruler.get("alive", false)):
		content.add_child(UiKit.label("Your last ruler has died. The family remains; the current office and succession are shown in Laws.", "Bad", true))
	if bool(office.get("regency", false)):
		var regent: Dictionary = Dynasty.person(Game, String(office.get("regent_uid", "")))
		content.add_child(UiKit.label("Minor ruler · Regent: " + String(regent.get("name", "No regent appointed")), "", true))
	var actions := UiKit.flow()
	content.add_child(actions)
	actions.add_child(UiKit.button("Campaign map", func(): Game.goto("map")))
	actions.add_child(UiKit.button("Army", func(): Game.goto("muster", {"back": "house", "back_params": {"back": back}}), "Row"))
	var laws := UiKit.button("Laws", func(): Game.goto("laws", {"town_id": tid, "back": "house", "back_params": {"back": back}}), "Row")
	laws.name = "HouseLawsButton"
	actions.add_child(laws)
	actions.add_child(UiKit.button("Court & marriages", func(): Game.goto("court", {"back": "house"}), "Row"))
	actions.add_child(UiKit.button("Dragons & eggs", func(): Game.goto("dragons", {"back": "house", "back_params": {"back": back}}), "Row"))
	var treasure := UiKit.button("Treasure room", func(): Game.goto("treasure", {"back": "house", "back_params": {"back": back}}), "Row")
	treasure.name = "TreasureRoomButton"
	actions.add_child(treasure)
	actions.add_child(UiKit.button("City records", _records.bind(String(selected["town_id"])), "Row"))
	actions.add_child(UiKit.button("Politics", func(): PoliticsView.open_view("politics", tid, "house"), "Row"))
	actions.add_child(UiKit.button("Population", func(): PoliticsView.open_view("population", tid, "house"), "Row"))
	# What needs doing now, in one line.
	var todo := ""
	if Dynasty.selected_heir(Game).is_empty(): todo = "No heir: open Court and arrange a marriage."
	elif Game.company.is_empty(): todo = "Your army is not raised. Fund it below, then raise troops in Army."
	elif Game.unpaid_count() > 0: todo = "%d soldiers are unpaid: fund the army wallet." % Game.unpaid_count()
	if todo != "":
		var tp := UiKit.panel("Inset"); var tl := UiKit.label(todo, "", true); tl.add_theme_font_size_override("font_size", 22); tl.add_theme_color_override("font_color", UiTheme.WARN); tp.add_child(tl); body.add_child(tp)
	var accounts: Dictionary = Dynasty.accounts(Game)
	var arms := UiKit.label("House arms (your common soldiers): %s" % ArmsPool.summary(Game, "player"), "", true)
	arms.mouse_filter = MOUSE_FILTER_PASS
	arms.tooltip_text = "Each pool runs 0-100 and is applied to every commoner you raise. Skill grows each day the army is mustered (drill), experience with every round fought (more for a win), conditioning with each day on campaign. Skilled commoners who die drain all three. Commoners never rise in rank; only house members can be officers."
	body.add_child(arms)
	body.add_child(UiKit.label("Treasury", "H2"))
	accounts_grid = GridContainer.new()
	accounts_grid.add_theme_constant_override("h_separation", 10)
	accounts_grid.add_theme_constant_override("v_separation", 10)
	accounts_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(accounts_grid)
	_account("House purse", float(accounts.get("house_purse", 0.0)), "Registered household savings", true)
	_account("City treasury", float(accounts.get("city_treasury", 0.0)), String(selected.get("town_name", "City")), false)
	var faction: Dictionary = DB.factions.get(String(accounts.get("faction_id", "")), {})
	_account("Faction treasury", float(accounts.get("faction_treasury", 0.0)), String(faction.get("name", accounts.get("faction_id", "Realm"))), false)
	_account("Army wallet", float(accounts.get("company_wallet", 0.0)), "Your raised army's pay and supplies", false)
	var town_stats: Dictionary = Game.world.get("towns", {}).get(tid, {}).get("econ", {}).get("stats", {})
	var feudal: Dictionary = Feudal.summary(Game, tid)
	accounts_grid.tooltip_text = "Each purse has its own owner; viewing never moves coin. %s%s" % [PoliticsView.levy_text(town_stats), (" Last tribute to your liege: %.2f coins." % float(feudal["tribute"])) if feudal.has("tribute") else ""]
	var fund_button := UiKit.button("Fund army from house", _fund_army, "Row")
	fund_button.disabled = not commands_settlement
	if fund_button.disabled: fund_button.tooltip_text = "Your household does not hold settlement command."
	body.add_child(fund_button)
	budget = Feudal.budget(Game, tid)
	if not budget.is_empty():
		var finances := UiKit.panel("Card")
		body.add_child(finances)
		var words := UiKit.vbox(6)
		finances.add_child(words)
		words.add_child(UiKit.label("Income & defence" if commands_settlement else "Settlement income & defence", "H2", true))
		words.add_child(UiKit.label(PoliticsView.tax_text(budget), "", true))
		words.add_child(UiKit.label(PoliticsView.defence_text(budget), "", true))
		words.add_child(UiKit.label("Field army unraised · No field payroll" if Game.company.is_empty() else "Field army: %d soldiers · Pay %d coins/day from army wallet · %d unpaid" % [Game.company.filter(func(u): return not u.dead).size(), Game.daily_wages(), Game.unpaid_count()], "", true))
		var warning := PoliticsView.budget_warnings(budget)
		if warning != "": words.add_child(UiKit.label(warning, "Bad", true))
		var manage_button := UiKit.button("Manage taxes & defence", func(): PoliticsView.open_view("politics", tid, "house"), "Row")
		manage_button.disabled = not commands_settlement
		words.add_child(manage_button)
	# Family at a glance: portraits only; the full tree and match-making live in Court.
	var members: Array = Dynasty.living_members(Game)
	var fam_head := UiKit.flow(10); body.add_child(fam_head)
	fam_head.add_child(UiKit.label("Family (%d living)" % members.size(), "H2"))
	fam_head.add_child(UiKit.button("Open family tree", func(): Game.goto("court", {"back": "house"}), "", 220))
	var strip := UiKit.flow(10); body.add_child(strip)
	for person: Dictionary in members.slice(0, 14):
		var pb := Button.new(); pb.custom_minimum_size = Vector2(96, 120); pb.focus_mode = FOCUS_NONE
		pb.tooltip_text = "%s, %d" % [person.get("name", ""), int(person.get("age", 0))]
		pb.add_theme_stylebox_override("normal", StyleBoxEmpty.new()); pb.add_theme_stylebox_override("hover", UiTheme.sb(Color(1, 1, 1, 0.06), UiTheme.BRASS, 1))
		var col := UiKit.vbox(2); col.set_anchors_preset(PRESET_FULL_RECT); col.mouse_filter = MOUSE_FILTER_IGNORE; pb.add_child(col)
		var pt := Portrait.new(); pt.custom_minimum_size = Vector2(0, 90); pt.mouse_filter = MOUSE_FILTER_IGNORE; pt.set_spec(Dynasty.portrait_for(Game, person)); col.add_child(pt)
		var nl := UiKit.label(String(person.get("name", "")).split(" ")[0], "Small"); nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; nl.mouse_filter = MOUSE_FILTER_IGNORE; col.add_child(nl)
		pb.pressed.connect(_show_person.bind(person))
		strip.add_child(pb)
	_fit_layout()

func _fund_army() -> void:
	var accounts: Dictionary = Dynasty.accounts(Game)
	var modal := UiKit.modal(self, "Fund army from house", 440)
	modal.add_child(UiKit.label("House purse: %.2f coins\nArmy wallet: %.2f coins" % [float(accounts.get("house_purse", 0)), float(accounts.get("company_wallet", 0))], "", true))
	modal.add_child(UiKit.label("Choose how much to transfer. City and faction treasuries have separate owners.", "Muted", true))
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = maxf(1, floor(float(accounts.get("house_purse", 0))))
	amount.step = 1
	amount.value = minf(100, amount.max_value)
	amount.custom_minimum_size = Vector2(0, UiKit.touch_min(48))
	modal.add_child(amount)
	var controls := UiKit.flow()
	modal.add_child(controls)
	controls.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row"))
	controls.add_child(UiKit.button("Review transfer", func():
		var coins := amount.value
		UiKit.close_modal(modal)
		var tid := String(Dynasty.selected(Game).get("town_id", ""))
		var preview: Dictionary = Feudal.action_preview(Game, tid, "fund_army", "", coins)
		if not bool(preview.get("ok", false)):
			notice = String(preview.get("reason", "")); _refresh(); return
		UiKit.confirm(self, "Transfer %.2f coins from your house purse to the army wallet?" % coins, "Transfer", _apply_funding.bind(coins)), "Row"))

func _apply_funding(amount: float) -> Dictionary:
	var result: Dictionary = Feudal.fund_army(Game, amount)
	notice = String(result.get("reason", ""))
	_refresh()
	return result

func _account(title: String, amount: float, owner: String, private: bool) -> void:
	var panel := UiKit.panel("Card" if private else "Inset")
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	accounts_grid.add_child(panel)
	var words := UiKit.vbox(4)
	panel.add_child(words)
	words.add_child(UiKit.label(title, "Small", true))
	var value := UiKit.label("%s coins" % UiKit.thousands(int(floor(amount))), "H2", true)
	value.tooltip_text = "Recorded balance: %.2f coins" % amount
	value.add_theme_color_override("font_color", UiTheme.PURPLE_TEXT if private else UiTheme.GOOD)
	words.add_child(value)
	words.add_child(UiKit.label(owner, "Muted", true))

func _fit_layout() -> void:
	if margin != null:
		UiKit.apply_safe_area(margin, 16, 16, 16, 16)
		margin.offset_right = -UiKit.diagnostics_lane(size.x)
	if accounts_grid != null:
		accounts_grid.columns = 1 if size.x < 600 else (2 if size.x < 1200 else 4)

func _show_person(person: Dictionary) -> void:
	member = person
	_refresh()

func _person_page(person: Dictionary) -> void:
	body.add_child(UiKit.label(String(person.get("name", "Person")), "H2", true))
	var sex := "Woman" if int(person.get("sex", 0)) == 1 else "Man"
	body.add_child(UiKit.label("%s · age %d · %s" % [sex, int(person.get("age", 0)), person.get("state", "")], "Muted", true))
	body.add_child(UiKit.label("Residence: %s\nHousehold: %s" % [person.get("town_name", ""), person.get("family_name", "")], "", true))
	var title := String(person.get("title", ""))
	if title != "":
		body.add_child(UiKit.label("Office: " + title, "", true))
	var kin := String(person.get("kin", ""))
	if kin != "":
		body.add_child(UiKit.label(kin, "Muted", true))
	for relation in [["Spouse", "spouse_uid"], ["Mother", "mother_uid"], ["Father", "father_uid"]]:
		var uid := String(person.get(relation[1], ""))
		var relative: Dictionary = Dynasty.person(Game, uid) if uid != "" else {}
		if not relative.is_empty():
			body.add_child(UiKit.label("%s: %s" % [relation[0], relative.get("name", "")], "Muted", true))
			body.add_child(UiKit.button("View " + String(relation[0]).to_lower(), _show_person.bind(relative), "Row"))
	body.add_child(UiKit.button("Full person record", _person_record.bind(person), "Row"))
	body.add_child(UiKit.button("City records", _records.bind(String(person.get("town_id", ""))), "Row"))
	body.add_child(UiKit.button("Back to house", func(): member = {}; _refresh()))

func _records(town_id: String) -> void:
	Game.goto("res://ui/records.tscn", {"view": "town", "id": town_id, "back": "house"})

func _person_record(person: Dictionary) -> void:
	var town_id := String(person.get("town_id", ""))
	var town: Dictionary = Game.world.get("towns", {}).get(town_id, {})
	_records(town_id)
	if Game.main != null and Game.main.current != null:
		Game.main.current.call_deferred("open_person", town, int(person.get("family_id", -1)), int(person.get("pid", -1)))

func _back() -> void:
	if not member.is_empty():
		member = {}
		_refresh()
	else:
		Game.goto(back)
