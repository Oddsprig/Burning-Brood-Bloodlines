class_name PoliticsView
extends Control
## Pure political reads; all paid actions go through Feudal's native gates.
var body: VBoxContainer
var town_id := ""
var faction_id := ""
var back := "map"
var return_location := ""
var back_params: Dictionary = {}
var query := ""
var notice := ""
var hierarchy_rows: Array = []
var selected_summary: Dictionary = {}
var budget: Dictionary = {}
var _refresh_pending := false

static func open_view(view: String, tid: String, previous: String, previous_params: Dictionary = {}) -> void:
	var origin := Game.location
	Game.location = tid
	Game.goto(view, {"town_id": tid, "back": previous, "return_location": origin, "back_params": previous_params})

static func law_text(law: String) -> String:
	match law:
		"male_preference": return "Sons' lines first; daughters as fallback"
		"absolute": return "Eldest child's line, regardless of sex"
		"strength": return "Chosen by combat contests"
		_: return "Local succession custom"

static func town_name(tid: String) -> String:
	return String(Game.world.get("towns", {}).get(tid, {}).get("name", "No liege" if tid == "" else tid))

func _ready() -> void:
	town_id = String(Game.screen_params.get("town_id", Game.location))
	if town_id == "": town_id = String(Dynasty.selected(Game).get("town_id", ""))
	back = String(Game.screen_params.get("back", "map"))
	return_location = String(Game.screen_params.get("return_location", Game.location))
	back_params = Game.screen_params.get("back_params", {}).duplicate(true)
	var frame := UiKit.screen_frame(self, "Realm politics")
	var heading: Label = frame["title"]
	heading.add_theme_font_size_override("font_size", 24)
	heading.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	heading.custom_minimum_size.x = 0
	frame["bar"].add_child(UiKit.button("Back", _back, "Row", 72))
	var root: VBoxContainer = frame["root"]
	var search := LineEdit.new()
	search.placeholder_text = "Search settlements or lords"
	search.custom_minimum_size.y = 48
	search.text_changed.connect(func(value): query = String(value).to_lower(); _queue_refresh())
	root.add_child(search)
	var scroll := UiKit.scroll()
	root.add_child(scroll)
	body = UiKit.vbox(10)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(body)
	Game.changed.connect(_queue_refresh)
	_refresh()

func _queue_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true
	call_deferred("_refresh")

func _context() -> Dictionary:
	return {"town_id": town_id, "back": back, "return_location": return_location, "back_params": back_params}

func _refresh() -> void:
	_refresh_pending = false
	UiKit.clear(body)
	var town: Dictionary = Game.world.get("towns", {}).get(town_id, {})
	if town.is_empty():
		body.add_child(UiKit.label("No settlement selected.", "Muted", true))
		return
	faction_id = String(town.get("faction", ""))
	selected_summary = Feudal.summary(Game, town_id)
	hierarchy_rows = Feudal.hierarchy(Game, faction_id)
	if notice != "": body.add_child(UiKit.label(notice, "", true))
	var actions := UiKit.flow()
	body.add_child(actions)
	actions.add_child(UiKit.button("Choose realm", _choose_realm, "Row"))
	actions.add_child(UiKit.button("Population", func(): open_view("population", town_id, "politics", _context()), "Row"))
	actions.add_child(UiKit.button("City records", _records, "Row"))
	body.add_child(UiKit.label(UiWords.faction_name(faction_id), "H2", true))
	_governance_card()
	_selected_card()
	body.add_child(UiKit.label("Every settlement · %d" % hierarchy_rows.size(), "H2", true))
	var shown := 0
	# A compact grid: each settlement is one clickable tile (name, lord, loyalty bar), not a full-width card.
	var grid := GridContainer.new(); grid.columns = 4 if get_viewport_rect().size.x >= 1400 else (3 if get_viewport_rect().size.x >= 1000 else 2)
	grid.add_theme_constant_override("h_separation", 10); grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(grid)
	for row: Dictionary in hierarchy_rows:
		var office: Dictionary = row.get("office", {})
		var text := "%s %s %s" % [row.get("town_name", ""), office.get("name", ""), row.get("tier", "")]
		if query != "" and not text.to_lower().contains(query): continue
		shown += 1
		var tile := Button.new(); tile.focus_mode = FOCUS_NONE; tile.theme_type_variation = "Row"
		tile.custom_minimum_size = Vector2(0, 104); tile.size_flags_horizontal = SIZE_EXPAND_FILL
		tile.tooltip_text = "Liege: %s" % town_name(String(row.get("liege_town_id", "")))
		tile.pressed.connect(_select.bind(String(row["town_id"])))
		var col := UiKit.vbox(2); col.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 10); col.mouse_filter = MOUSE_FILTER_IGNORE; tile.add_child(col)
		var nm := UiKit.label(String(row.get("town_name", "")), "H2"); nm.mouse_filter = MOUSE_FILTER_IGNORE; nm.add_theme_font_size_override("font_size", 21); col.add_child(nm)
		var lord := UiKit.label(_office_name(office), "Small"); lord.mouse_filter = MOUSE_FILTER_IGNORE; lord.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; col.add_child(lord)
		var loyal := float(row.get("loyalty", 0))
		var bar := ProgressBar.new(); bar.max_value = 100; bar.value = loyal; bar.show_percentage = false; bar.custom_minimum_size = Vector2(0, 10); bar.mouse_filter = MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("fill", UiTheme.sb(UiTheme.GOOD if loyal >= 50 else (UiTheme.WARN if loyal >= 25 else UiTheme.BAD), UiTheme.WOOD, 0, 4, 0, 0))
		col.add_child(bar)
		var ll := UiKit.label("%s · loyalty %d" % [String(row.get("tier", "")).capitalize(), int(loyal)], "Muted"); ll.mouse_filter = MOUSE_FILTER_IGNORE; col.add_child(ll)
		grid.add_child(tile)
	if shown == 0: body.add_child(UiKit.label("No matching settlements or lords.", "Muted", true))

func _office_name(office: Dictionary) -> String:
	if office.is_empty() or bool(office.get("vacant", true)): return "Vacant office"
	return "%s %s" % [office.get("title", "Ruler"), office.get("name", "")]

func _selected_card() -> void:
	if selected_summary.is_empty():
		body.add_child(UiKit.label("This settlement has no political record yet.", "Muted", true))
		return
	var row: Dictionary = selected_summary
	var office: Dictionary = row.get("office", {})
	var heir: Dictionary = row.get("heir", {})
	var panel := UiKit.panel("Card")
	body.add_child(panel)
	var words := UiKit.vbox(6)
	panel.add_child(words)
	words.add_child(UiKit.label(String(row["town_name"]), "H2", true))
	words.add_child(UiKit.label(_office_name(office), "", true))
	words.add_child(UiKit.label("Succession: " + law_text(String(row.get("law", ""))), "Muted", true))
	if not office.is_empty() and bool(office.get("alive", false)):
		words.add_child(UiKit.button("View ruler", _person_record.bind(office), "Row"))
		if String(office.get("town_id", "")) != town_id:
			words.add_child(UiKit.label("Ruler lives in " + String(office.get("town_name", "")), "Muted", true))
	if not heir.is_empty():
		words.add_child(UiKit.label("Heir: " + String(heir.get("name", "")), "", true))
		words.add_child(UiKit.button("View heir", _person_record.bind(heir), "Row"))
	else:
		words.add_child(UiKit.label("Heir: combat contest decides" if row.get("law", "") == "strength" else "No eligible heir recorded", "Muted", true))
	if bool(office.get("regency", false)):
		var regent: Dictionary = Dynasty.person(Game, String(office.get("regent_uid", "")))
		words.add_child(UiKit.label("Minor ruler · Regent: " + String(regent.get("name", "No regent appointed")), "", true))
	var links := UiKit.flow()
	words.add_child(links)
	for entry in [["Liege", String(row.get("liege_town_id", ""))], ["Sovereign", String(row.get("sovereign_town_id", ""))]]:
		var tid := String(entry[1])
		if tid != "" and tid != town_id:
			words.add_child(UiKit.label(String(entry[0]) + ": " + town_name(tid), "Muted", true))
			links.add_child(UiKit.button("View " + String(entry[0]).to_lower(), _select.bind(tid), "Row"))
	words.add_child(UiKit.label("Loyalty %.0f / 100 · Grievance %.0f / 100" % [float(row.get("loyalty", 0)), float(row.get("grievance", 0))], "", true))
	if row.has("tribute"): pass
	var stats: Dictionary = Game.world.get("towns", {}).get(town_id, {}).get("econ", {}).get("stats", {})
	var controls := UiKit.flow()
	words.add_child(controls)
	for action in [["Grant", "grant"], ["Apply pressure", "pressure"]]:
		var code := String(action[1])
		var preview: Dictionary = Feudal.action_preview(Game, town_id, code)
		var button := UiKit.button(String(action[0]), _request_action.bind(code), "Row")
		button.disabled = not bool(preview.get("ok", false))
		controls.add_child(button)
		words.add_child(UiKit.label("%s: %s" % [action[0], preview.get("reason", "")], "Small", true))
	var swear := UiKit.button("Swear to another realm", _choose_oath, "Row")
	swear.disabled = not bool(row.get("can_act", false))
	controls.add_child(swear)
	if not bool(row.get("can_act", false)):
		words.add_child(UiKit.label("You can act only in your own settlement and its vassals.", "Muted", true))
	for event: Dictionary in row.get("history", []).slice(-4):
		words.add_child(UiKit.label("Day %d · %s" % [int(event.get("day", 0)), event.get("text", "")], "Small", true))

static func levy_text(stats: Dictionary) -> String:
	if not stats.has("estate_tax_received"):
		return "No private estate levy recorded yet. City treasury is separate."
	return "Local lord's household received %.2f coins in the latest estate levy (day %d). Total private levies: %.2f coins. City treasury is separate." % [float(stats["estate_tax_received"]), int(stats.get("estate_tax_day", 0)), float(stats.get("lord_tax", 0))]

static func tax_text(values: Dictionary) -> String:
	var quote: Dictionary = values.get("tax_quote", {})
	var receipt := "No levy recorded yet" if int(values.get("estate_tax_day", -1)) < 0 else "Last receipt %.2f coins · day %d" % [float(values.get("estate_tax_received", 0)), int(values["estate_tax_day"])]
	return "Common folk estate tax: %.0f%% · Current monthly estimate %.2f coins\nProtected food reserve %.2f coins · Taxable savings %.2f coins\n%s → %s's house purse" % [float(quote.get("rate", 0)) * 100, float(quote.get("monthly_due", 0)), float(quote.get("food_reserve", 0)), float(quote.get("taxable_wealth", 0)), receipt, values.get("lord_name", "Local lord")]

static func defence_text(values: Dictionary) -> String:
	var policy := String(values.get("defence_policy", "auto_defence"))
	var order := {"muster": "Militia on duty", "stand_down": "Militia stood down", "auto_defence": "Automatic defence"}
	return "%s · %d militia · %d guards\nGarrison pay %.2f coins/day from city treasury · Realm field army %d, pay %.2f coins/day from faction treasury\nSettlement food reserve: %d days" % [order.get(policy, policy), int(values.get("militia_count", 0)), int(values.get("guard_count", 0)), float(values.get("garrison_wages_daily", 0)), int(values.get("realm_army_count", 0)), float(values.get("realm_army_wages_daily", 0)), int(values.get("food_days", 0))]

static func budget_warnings(values: Dictionary) -> String:
	var lines: Array[String] = []
	if float(values.get("food_short", 0)) > 0:
		lines.append("Food shortage recorded in this settlement.")
	if float(values.get("garrison_wages_daily", 0)) > float(values.get("town_treasury", 0)):
		lines.append("City treasury cannot cover one day's current garrison pay.")
	if float(values.get("realm_army_wages_daily", 0)) > float(values.get("faction_treasury", 0)):
		lines.append("Faction treasury cannot cover one day's current field army pay.")
	return "\n".join(lines)

static func tribute_text(values: Dictionary) -> String:
	var sent := "No private tribute recorded"
	if int(values.get("tribute_day", -1)) >= 0 and String(values.get("liege_town_id", "")) != "":
		sent = "Sent %.2f coins to %s's house · day %d" % [float(values.get("tribute_sent", 0)), values.get("liege_name", "the liege"), int(values["tribute_day"])]
	var received := "No vassal tribute recorded"
	if int(values.get("tribute_received_day", -1)) >= 0:
		received = "Received %.2f coins from vassal houses · day %d" % [float(values.get("tribute_received", 0)), int(values["tribute_received_day"])]
	return sent + "\n" + received

func _governance_card() -> void:
	budget = Feudal.budget(Game, town_id)
	if budget.is_empty(): return
	var panel := UiKit.panel("Card")
	body.add_child(panel)
	var words := UiKit.vbox(6)
	panel.add_child(words)
	words.add_child(UiKit.label("Taxes & defence", "H2", true))
	words.add_child(UiKit.label(tax_text(budget), "", true))
	var tax_controls := UiKit.flow()
	words.add_child(tax_controls)
	for rate in [0.02, 0.05, 0.10]:
		_governance_button(tax_controls, "%d%% estate tax" % int(round(rate * 100)), "tax_policy", rate)
	words.add_child(UiKit.label("House %s · City %s · Realm %s · Army %s" % [UiKit.compact_coins(float(budget.get("payer_purse", 0))), UiKit.compact_coins(float(budget.get("town_treasury", 0))), UiKit.compact_coins(float(budget.get("faction_treasury", 0))), UiKit.compact_coins(float(budget.get("company_gold", 0)))], "", true))
	words.add_child(UiKit.label(defence_text(budget), "", true))
	var warnings := budget_warnings(budget)
	if warnings != "": words.add_child(UiKit.label(warnings, "Bad", true))
	var defence_controls := UiKit.flow()
	words.add_child(defence_controls)
	for choice in [["Muster militia", "muster"], ["Stand down", "stand_down"], ["Automatic defence", "auto_defence"]]:
		_governance_button(defence_controls, choice[0], choice[1])
	var funds := UiKit.flow()
	words.add_child(funds)
	for choice in [["Fund city treasury", "fund_garrison"], ["Fund realm treasury", "fund_realm_army"]]:
		var preview: Dictionary = Feudal.governance_preview(Game, town_id, choice[1], 1.0)
		var button := UiKit.button(choice[0], _choose_funding.bind(String(choice[1])), "Row")
		button.disabled = not bool(preview.get("ok", false))
		button.tooltip_text = String(preview.get("reason", ""))
		funds.add_child(button)
	var details := UiKit.flow()
	words.add_child(details)
	details.add_child(UiKit.button("Garrison records", _budget_records.bind("town", town_id, "Garrison"), "Row"))
	details.add_child(UiKit.button("Realm army", _budget_records.bind("faction", faction_id, "Army"), "Row"))
	details.add_child(UiKit.button("Public services", _budget_records.bind("town", town_id, "Businesses"), "Row"))

func _governance_button(row: Control, title: String, action: String, amount: float = 0.0) -> void:
	var preview: Dictionary = Feudal.governance_preview(Game, town_id, action, amount)
	var button := UiKit.button(title, _request_governance.bind(town_id, action, amount), "Row")
	button.disabled = not bool(preview.get("ok", false))
	button.tooltip_text = String(preview.get("reason", ""))
	row.add_child(button)

func _choose_funding(action: String) -> void:
	var tid := town_id
	var values: Dictionary = Feudal.budget(Game, tid)
	var modal := UiKit.modal(self, "Fund city treasury" if action == "fund_garrison" else "Fund realm treasury", 500)
	modal.add_child(UiKit.label("%s's house purse: %.2f coins\nPublic funds remain separate from your army wallet." % [values.get("payer_name", "Your ruler"), float(values.get("payer_purse", 0))], "", true))
	var amount := SpinBox.new()
	amount.min_value = 1; amount.max_value = maxf(1, floor(float(values.get("payer_purse", 0))))
	amount.step = 1; amount.value = minf(100, amount.max_value); amount.custom_minimum_size.y = 48
	modal.add_child(amount)
	var controls := UiKit.flow()
	modal.add_child(controls)
	controls.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row"))
	controls.add_child(UiKit.button("Review transfer", func():
		var coins := amount.value
		UiKit.close_modal(modal)
		_request_governance(tid, action, coins), "Row"))

static func governance_text(tid: String, preview: Dictionary) -> String:
	var action := String(preview.get("action", ""))
	if action.begins_with("fund_"):
		var account := "city treasury" if preview.get("recipient_account", "") == "town_treasury" else "faction treasury"
		return "Transfer %.2f coins from %s's house purse to %s's %s?\nThis funds shared public costs." % [float(preview.get("cost", 0)), preview.get("payer_name", "Your ruler"), preview.get("recipient_name", ""), account]
	var text := town_name(tid) + "\n" + String(preview.get("reason", ""))
	if action == "tax_policy":
		text += "\nCommon folk pay %.0f%% → %.0f%% of taxable savings to %s's house purse after their protected food reserve." % [float(preview.get("current_tax_rate", 0)) * 100, float(preview.get("proposed_tax_rate", 0)) * 100, preview.get("recipient_name", "the local lord")]
	return text

func _request_governance(tid: String, action: String, amount: float = 0.0) -> void:
	var preview: Dictionary = Feudal.governance_preview(Game, tid, action, amount)
	if not bool(preview.get("ok", false)):
		notice = String(preview.get("reason", "Order unavailable.")); _refresh(); return
	UiKit.confirm(self, governance_text(tid, preview), "Confirm order", _apply_governance.bind(tid, action, amount))

func _apply_governance(tid: String, action: String, amount: float = 0.0) -> Dictionary:
	# Bind the reviewed seat, then ask the authority to revalidate every command.
	var result: Dictionary = Feudal.governance(Game, tid, action, amount)
	notice = String(result.get("reason", ""))
	_refresh()
	return result

func _budget_records(view: String, id: String, tab: String) -> void:
	Game.goto("res://ui/records.tscn", {"view": view, "id": id, "tab": tab, "back": "politics", "back_params": _context()})

func _select(tid: String) -> void:
	town_id = tid
	Game.location = tid
	notice = ""
	_refresh()

func _choose_realm() -> void:
	var options := []
	var fids: Array = Game.world.get("factions", {}).keys()
	fids.sort()
	for fid in fids:
		var rows: Array = Feudal.hierarchy(Game, String(fid))
		if not rows.is_empty(): options.append({"text": UiWords.faction_name(String(fid)), "value": String(rows[0]["town_id"]), "detail": "%d settlements" % rows.size()})
	UiKit.picker(self, "Choose realm", options, func(tid): _select(String(tid)))

func _choose_oath() -> void:
	var options := []
	var fids: Array = Game.world.get("factions", {}).keys()
	fids.sort()
	for fid in fids:
		if String(fid) == faction_id or Monsters.is_monster_faction(String(fid)): continue
		var preview: Dictionary = Feudal.action_preview(Game, town_id, "swear", String(fid))
		options.append({"text": UiWords.faction_name(String(fid)), "value": String(fid), "detail": String(preview.get("reason", ""))})
	# Ineligible destinations remain inspectable, so their real reason is reachable.
	UiKit.picker(self, "Swear to another realm", options, func(fid): _request_action("swear", String(fid)))

func _request_action(action: String, target_fid: String = "") -> void:
	var preview: Dictionary = Feudal.action_preview(Game, town_id, action, target_fid)
	if not bool(preview.get("ok", false)):
		notice = String(preview.get("reason", "Action unavailable."))
		_refresh()
		return
	var label := "Swear oath" if action == "swear" else ("Grant" if action == "grant" else "Apply pressure")
	var text := "%s\n%s\nHouse purse pays %.2f coins." % [town_name(town_id), preview.get("reason", ""), float(preview.get("cost", 0))]
	if target_fid != "": text += "\nNew realm: " + UiWords.faction_name(target_fid)
	UiKit.confirm(self, text, label, _apply_action.bind(action, target_fid))

func _apply_action(action: String, target_fid: String = "") -> Dictionary:
	var result: Dictionary = Feudal.intrigue(Game, town_id, action, target_fid)
	notice = String(result.get("reason", ""))
	_refresh()
	return result

func _records() -> void:
	Game.goto("res://ui/records.tscn", {"view": "town", "id": town_id, "back": "politics", "back_params": _context()})

func _person_record(person: Dictionary) -> void:
	var tid := String(person.get("town_id", ""))
	Game.goto("res://ui/records.tscn", {"view": "town", "id": tid, "back": "politics", "back_params": _context()})
	if Game.main != null and Game.main.current != null:
		Game.main.current.call_deferred("open_person", Game.world.get("towns", {}).get(tid, {}), int(person.get("family_id", -1)), int(person.get("pid", -1)))

func _back() -> void:
	Game.location = return_location
	Game.goto(back, back_params)
