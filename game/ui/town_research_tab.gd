class_name TownResearchTab
extends RefCounted
## Read-only view of the realm's existing research accounts and actual work snapshot.

static func build(host: Control, t: Dictionary, body: VBoxContainer) -> void:
	build_report(host, t, body, Academy.report(Game.world, _realm(t)))

static func _realm(t: Dictionary) -> String:
	return String(t.get("faction", t.get("econ", {}).get("faction", "")))

static func build_report(host: Control, t: Dictionary, body: VBoxContainer, report: Dictionary) -> void:
	var snapshot := house_state(report)
	var top := UiKit.hbox(10)
	body.add_child(top)
	var location := UiKit.vbox(2)
	location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(location)
	location.add_child(UiKit.label("Research - %s" % CampaignWorld.faction_name(_realm(t)), "H2", true))
	var where := "%s in %s" % [String(report.get("name", "Research house")), String(report.get("town", ""))] if bool(report.get("has", false)) else "No owned capital research house"
	location.add_child(UiKit.label(where, "Small", true))
	var status := TownEconTab._badge(String(snapshot["text"]), snapshot["color"])
	status.custom_minimum_size.x = 190
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.tooltip_text = "House activity shows the last recorded production state. Planned allocations do not measure output."
	top.add_child(status)
	var details := UiKit.button("Details", func(): _history(host, t, report), "Row", 96)
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(details)
	if bool(report.get("has", false)):
		_summary(report, body)
	var weights := [1.5, 2.1, 2.1, 1.3, 1.3]
	var header := TownEconTab._table_row(body, ["Line", "Status", "Know-how", "Research points", "Planned share"], weights, true)
	header.tooltip_text = "Know-how includes starting knowledge. Saved research points can accumulate before know-how rises. Planned share is allocation, not measured output."
	for line: Dictionary in report.get("lines", []):
		var state := line_state(report, line)
		var progress := _knowledge(line, state)
		var share := "%.1f%%" % (100.0 * float(line.get("share", 0.0))) if bool(line.get("active", false)) else "-"
		var row := TownEconTab._table_row(body, [String(line["name"]).capitalize(), TownEconTab._badge(String(state["text"]), state["color"]), progress, "%.1f" % float(line.get("pts", 0.0)), share], weights)
		row.tooltip_text = "Planned allocation: %.1f coins/day; %.2f supporting staff. This is an allocation, not measured output." % [float(line.get("budget_on", 0.0)), float(line.get("staff_on", 0.0))]
	if (report.get("lines", []) as Array).is_empty():
		body.add_child(UiKit.label("No research lines recorded.", "Muted"))
	var funding := HBoxContainer.new()
	funding.add_theme_constant_override("separation", 8)
	body.add_child(funding)
	_funding_cell(funding, "Planned budget", "%.1f coins/day" % float(report.get("budget", 0.0)), "The state's planned daily funding, separate from the last actual transfer.")
	var funding_day := int(report.get("funding_day", -1))
	var transfer_date := "Day %d" % (funding_day + 1) if funding_day >= 0 else "date not recorded"
	_funding_cell(funding, "Last state transfer", "%.1f coins (%s)" % [float(report.get("paid", 0.0)), transfer_date], "A zero last transfer can leave a funded till. Cash and actual activity are shown separately.")
	_funding_cell(funding, "Current week output", "%.1f research points" % float(report.get("current_week_output", 0.0)), "Recorded research output across all lines together. No per-line output or completion date is tracked.")

static func _funding_cell(row: HBoxContainer, title: String, value: String, help: String) -> void:
	var panel := UiKit.panel("Card")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	panel.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.PARCH_2, UiTheme.PARCH_3, 1, 3, 8, 6))
	panel.tooltip_text = help
	row.add_child(panel)
	var cell := UiKit.vbox(2)
	panel.add_child(cell)
	cell.add_child(UiKit.label(title, "Muted", true))
	cell.add_child(UiKit.label(value, "Small", true))

static func _summary(report: Dictionary, body: VBoxContainer) -> void:
	var cards := GridContainer.new()
	cards.columns = 3
	cards.add_theme_constant_override("h_separation", 8)
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cards)
	var name := String(report.get("lead", ""))
	var title := String(report.get("title", "Head"))
	cards.add_child(TownEconTab._metric(title, name if name != "" else "Post vacant", "Skill %.1f / 15" % float(report.get("lskill", 0.0)) if name != "" else "Awaiting appointment", UiTheme.BLUE if name != "" else UiTheme.WARN))
	var staff := TownEconTab._metric("Supporting staff", str(int(report.get("staff", 0))), "%d / %d paid places" % [int(report.get("workers", 0)), int(report.get("cap", 0))], UiTheme.BLUE)
	staff.tooltip_text = "Supporting staff excludes the designated head; paid places include the head."
	cards.add_child(staff)
	var till := float(report.get("till", 0.0))
	cards.add_child(TownEconTab._metric("Cash in till", "%.1f coins" % till, "Wages & materials", UiTheme.BLUE if till > 0.0 else UiTheme.WARN))

## Pure classification helpers shared by the view and focused native UI checks.
## A planned allocation or an old transfer alone never establishes current production.
static func house_state(report: Dictionary) -> Dictionary:
	if not bool(report.get("has", false)):
		return {"text": "No owned research house", "color": UiTheme.WOOD_3}
	if bool(report.get("closed", false)):
		return {"text": "Closed", "color": UiTheme.WARN}
	if String(report.get("lead", "")) == "":
		return {"text": "Head post vacant", "color": UiTheme.WARN}
	if int(report.get("workers", 0)) <= 0:
		return {"text": "Awaiting staff", "color": UiTheme.WARN}
	var code := String(report.get("state_code", ""))
	var why := String(report.get("why", ""))
	if code == "busy":
		return {"text": "Researching" + (" (materials limited)" if why == "materials" else (" - " + why if why != "" else "")), "color": UiTheme.GOOD}
	var text: String = {"hands": "Awaiting staff", "wages": "Can't pay wages", "inputs": "Short of inputs", "nopay": "Market can't pay", "full": "Market full", "idle": "Idle"}.get(code, "Awaiting research")
	var color: Color = {"wages": UiTheme.BAD, "inputs": UiTheme.BAD, "hands": UiTheme.WARN, "nopay": UiTheme.WARN}.get(code, UiTheme.WOOD_3)
	if why != "":
		text += " - " + why
	return {"text": text, "color": color}

static func line_state(report: Dictionary, line: Dictionary) -> Dictionary:
	if float(line.get("kh", 0.0)) >= 100.0:
		return {"text": "Completed", "color": UiTheme.BLUE}
	if not bool(line.get("open", false)):
		return {"text": "Unavailable", "color": UiTheme.WOOD_3}
	if not bool(line.get("active", false)):
		return {"text": "Awaiting allocation", "color": UiTheme.WOOD_3}
	return house_state(report)

static func _knowledge(line: Dictionary, state: Dictionary) -> Control:
	var value := clampf(float(line.get("kh", 0.0)), 0.0, 100.0)
	var box := UiKit.vbox(3)
	box.name = "Knowledge_" + String(line.get("key", "line"))
	var label := UiKit.label("%.1f%%" % value, "Small", true)
	label.add_theme_color_override("font_color", state["color"])
	box.add_child(label)
	# Unavailable lines have a number, not a learning bar. Completed bars represent actual
	# retained knowledge, are static and use the neutral blue rather than activity green.
	if bool(line.get("open", false)):
		var progress := ProgressBar.new()
		progress.name = "KnowHow_" + String(line.get("key", "line"))
		progress.min_value = 0.0
		progress.max_value = 100.0
		progress.step = 0.0
		progress.value = value
		progress.show_percentage = false
		progress.custom_minimum_size = Vector2(0, 14)
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		progress.add_theme_stylebox_override("background", UiTheme.sb(UiTheme.PARCH_3, UiTheme.PARCH_3.darkened(0.2), 1, 3, 0, 0))
		progress.add_theme_stylebox_override("fill", UiTheme.sb(state["color"], state["color"], 0, 3, 0, 0))
		box.add_child(progress)
	return box

static func _history(host: Control, t: Dictionary, report: Dictionary) -> void:
	var modal := UiKit.modal(host, "Research details, history & log", 640)
	var scroll := UiKit.scroll()
	scroll.custom_minimum_size = Vector2(0, 400)
	modal.add_child(scroll)
	var content := UiKit.vbox(4)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	if bool(report.get("has", false)):
		TownEconTab._fact(content, "Staff offer", "%.1f coins/day" % float(report.get("wage", 0.0)))
		TownEconTab._fact(content, "Head's nominal rate", "%.1f coins/day including the supplement" % float(report.get("lead_wage", 0.0)))
		var live := _live_head(t, report, _realm(t))
		if not live.is_empty():
			var lead: Array = live["lead"].duplicate()
			var realm := _realm(t)
			content.add_child(UiKit.button("%s's household" % String(report["lead"]), func():
				var current := _live_head(t, report, realm)
				if host.has_method("town"):
					var host_town: Variant = host.call("town")
					if host_town is Dictionary and _realm(host_town) != realm:
						return
				if current.is_empty() or current["lead"] != lead:
					return
				TownEconTab.family_modal(host, current["capital"], int(lead[0])), "Row"))
	var history: Array = report.get("hist", [])
	TownEconTab._fact(content, "Last completed week", "No completed week recorded" if history.is_empty() else "%.1f research points" % float(report.get("last_week_output", history[-1][1])))
	var lines := [
		"Know-how is knowledge already held, including starting knowledge. Accumulated research points can be saved before know-how begins to rise.",
		"House activity shows the last production state. Planned shares, coins and staff allocations are not measured per-line output.",
		"A zero last state transfer can leave a funded till; cash and actual activity are shown separately.",
		"Recorded output covers all research lines together; no per-line speed or completion date is tracked."
	]
	lines.append("Completed weeks, newest last:" if not history.is_empty() else "No completed weeks recorded.")
	for entry in history:
		lines.append("Day %d: %.1f research points" % [int(entry[0]) + 1, float(entry[1])])
	var log: Array = report.get("log", [])
	lines.append("Log book, newest last:")
	if log.is_empty():
		lines.append("No research events recorded.")
	for entry in log:
		lines.append(String(entry))
	for line in lines:
		content.add_child(UiKit.label(String(line), "Small", true))
	var buttons := UiKit.hbox()
	buttons.add_child(UiKit.spacer())
	buttons.add_child(UiKit.button("OK", func(): UiKit.close_modal(modal), "", 160))
	modal.add_child(buttons)

## Re-resolve ownership, designated head and person validity before exposing a household.
static func _live_head(t: Dictionary, report: Dictionary, realm: String) -> Dictionary:
	if not bool(report.get("has", false)) or _realm(t) != realm or String(report.get("lead", "")) == "":
		return {}
	var tid := String(report.get("tid", ""))
	var factions: Dictionary = Game.world.get("factions", {})
	if String(factions.get(realm, {}).get("capital", "")) != tid:
		return {}
	var capital: Dictionary = Game.world.get("towns", {}).get(tid, {})
	if not TownEcon.has_econ(capital) or _realm(capital) != realm:
		return {}
	var e: Dictionary = capital["econ"]
	var business := Academy.biz_of(e)
	if business.is_empty() or int(business["id"]) != int(report.get("bid", -1)):
		return {}
	var lead: Array = business.get("lead", [])
	if lead.size() < 2 or Academy.lead_name(e, business) != String(report["lead"]):
		return {}
	return {"capital": capital, "lead": lead}
