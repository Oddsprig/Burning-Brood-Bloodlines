class_name TownHealerTab
extends RefCounted
## Presentation only. Quotes and actions use the town's existing care helpers.

static func snapshot(scr: Control, t: Dictionary) -> Dictionary:
	var skill: int = scr._healer_skill(t)
	var queue: Array = scr._treat_queue(t)
	var quotes := {}
	var total := 0
	for entry: Dictionary in queue:
		var u: Unit = entry["unit"]
		var cost := int(entry["cost"])
		quotes[u.uid] = cost
		total += cost
	var patients := []
	for u: Unit in Game.company:
		var report := HealthReport.describe(u)
		if String(report.get("status", "healthy")) == "healthy" and String(report.get("fitness", "")) == "fit to fight" and not u.body.is_wounded():
			continue
		patients.append({"unit": u, "uid": u.uid, "report": report,
			"cost": int(quotes.get(u.uid, 0)), "status": String(report.get("status", "wounded")),
			"fitness": String(report.get("fitness", "")),
			"heal_days": maxf(float(report.get("heal_days", 0.0)), u.body.days_to_heal()),
			"recovery": String(report.get("recovery", ""))})
	return {"skill": skill, "patients": patients, "treatable": queue.size(),
		"quote": total, "wages": Game.daily_wages()}

static func build(scr: Control, t: Dictionary) -> Control:
	var data := snapshot(scr, t)
	var sc := UiKit.scroll()
	sc.name = "HealerView"
	sc.set_meta("healer_snapshot", data)
	var box := UiKit.vbox(8)
	UiKit.expand(box)
	sc.add_child(box)
	_summary(box, t, data)
	_actions(scr, t, box, data)
	if data["patients"].is_empty():
		var ready := RecKit.notice(box, "Everyone in the company is fit to fight.")
		ready.add_theme_color_override("font_color", UiTheme.GOOD)
	else:
		for patient: Dictionary in data["patients"]:
			_patient(scr, t, box, patient, int(data["skill"]))
	return sc

static func _summary(parent: Control, t: Dictionary, data: Dictionary) -> void:
	var healer: Dictionary = t.get("healer", {})
	var identity := String(healer.get("name", "?")) if not healer.is_empty() else "No healer here"
	var rank := (String(healer.get("rank", "")) + " " + String(healer.get("title", ""))).strip_edges()
	var skill := int(data["skill"])
	RecKit.metrics(parent, [
		{"title": "Town healer", "value": identity,
			"note": "%s · skill %d" % [rank, skill] if rank != "" else "Skill %d" % skill,
			"color": UiTheme.BLUE if skill > 0 else UiTheme.WARN},
		{"title": "Treatable now", "value": str(data["treatable"]),
			"note": "%d company health records" % data["patients"].size(),
			"color": UiTheme.WARN if int(data["treatable"]) > 0 else UiTheme.BLUE},
		{"title": "Treatment quote", "value": "%d coins" % int(data["quote"]),
			"note": "%d coins available" % Game.gold,
			"color": UiTheme.WARN if int(data["quote"]) > Game.gold else UiTheme.BLUE},
	])

static func _actions(scr: Control, t: Dictionary, parent: Control, data: Dictionary) -> void:
	var care := RecKit.card(parent, "Care & rest")
	var actions := UiKit.flow(8)
	care.add_child(actions)
	var treat := UiKit.button("Treat all (%d) · %d coins" % [int(data["treatable"]), int(data["quote"])],
		func(): scr._treat_all_confirm(t), "", 230)
	treat.name = "TreatAll"
	treat.add_theme_font_size_override("font_size", 18)
	treat.disabled = int(data["treatable"]) == 0
	treat.tooltip_text = "Review the existing treatment quote. Most critical wounds are treated first; treatment stops if coins run short."
	actions.add_child(treat)
	var wages := int(data["wages"])
	for days: int in [1, 3, 7]:
		var rest := UiKit.button("Rest %d day%s\n%d coins wage quote" % [days, "" if days == 1 else "s", days * wages],
			func(): scr._rest(days), "Row", 168)
		rest.name = "Rest%d" % days
		rest.custom_minimum_size.y = 64
		rest.add_theme_font_size_override("font_size", 18)
		rest.tooltip_text = "Current company wages: %d coins per day. Rest uses the existing time, wages and healing rules." % wages
		rest.set_meta("rest_quote", {"days": days, "wages_day": wages, "wages_quote": days * wages})
		actions.add_child(rest)
	if int(data["quote"]) > Game.gold:
		var shortfall := RecKit.line(care, "Treatment quote exceeds available coins by %d; the rest wait if coins run short." % (int(data["quote"]) - Game.gold), "Small")
		shortfall.add_theme_color_override("font_color", UiTheme.WARN)

static func _patient(scr: Control, t: Dictionary, parent: Control, patient: Dictionary, skill: int) -> void:
	var u: Unit = patient["unit"]
	var report: Dictionary = patient["report"]
	var panel := UiKit.panel("Card")
	panel.name = "Patient_%d" % u.uid
	panel.set_meta("healer_patient", patient)
	UiKit.expand(panel)
	parent.add_child(panel)
	var body := UiKit.vbox(5)
	panel.add_child(body)
	var heading := UiKit.hbox(10)
	body.add_child(heading)
	heading.add_child(UiKit.portrait(u, 56))
	var names := UiKit.vbox(0)
	UiKit.expand(names)
	heading.add_child(names)
	names.add_child(UiKit.wrap(UiKit.label(u.name, "H2")))
	if u.title != "": names.add_child(UiKit.wrap(UiKit.label(u.title, "Small")))
	var status := String(patient["status"])
	if status == "healthy": status = "Injury record"
	var recovery := String(patient["recovery"])
	if recovery == "": recovery = HealthReport.format_days(float(patient["heal_days"]))
	# A report's duration is an estimate, not a promise that lasting damage heals.
	var rest_text := "Not applicable" if u.dead else (recovery if float(patient["heal_days"]) > 0.0 else "No recovery time quoted")
	var facts := RecKit.grid(body, ["Condition", "Fitness", "Rest estimate"], [
		{"values": [{"text": status, "color": UiTheme.WARN if status == "Injury record" else UnitSheet.status_color(status)},
			{"text": String(patient["fitness"]), "color": _fitness_color(String(patient["fitness"]))}, rest_text]}], [1.0, 1.0, 1.15])
	facts.tooltip_text = "Reported recovery in town rest. Permanent injury and individual wound details remain below."
	var actions := UiKit.flow(8)
	body.add_child(actions)
	var cost := int(patient["cost"])
	if skill > 0 and cost > 0:
		var treat := UiKit.button("Treat · %d coins" % cost, func(): scr._treat(t, u, cost), "", 170)
		treat.name = "Treat_%d" % u.uid
		treat.disabled = cost > Game.gold
		treat.tooltip_text = "Existing healer quote for this patient." if not treat.disabled else "Not enough coins for this treatment."
		actions.add_child(treat)
	else:
		var quote := UiKit.label("Treatment unavailable" if skill <= 0 or u.dead else "No further treatment quoted", "Small", true)
		quote.custom_minimum_size = Vector2(120, 48)
		actions.add_child(quote)
	var sheet := UiKit.button("Sheet", func(): Game.goto("company", {"back": "town", "unit": u.uid}), "Row", 100)
	sheet.name = "Sheet_%d" % u.uid
	actions.add_child(sheet)
	var detail := RecKit.disclosure(body, "Wound details", func(content: VBoxContainer):
		for part: Dictionary in report.get("parts", []):
			content.add_child(UnitSheet.part_card(part))
		for line in report.get("summary", []):
			RecKit.line(content, String(line), "Small"))
	detail.name = "WoundDetails_%d" % u.uid
static func _fitness_color(fitness: String) -> Color:
	if fitness == "fit to fight": return UiTheme.GOOD
	if fitness == "cannot fight": return UiTheme.BAD
	return UiTheme.WARN
