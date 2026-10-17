extends Control
## Company screen: roster as squads (left), unit sheet with tabs (right), squad uniform editor,
## move / promote / dismiss. Back returns to Game.screen_params["back"] (default: town if inside one, else map).

var selected_uid: int = -1
var tab: String = "Overview"
var list_box: GridContainer   # the roster: one compact tile per unit (kept name: tests iterate its children)
var page: VBoxContainer
var tabs_box: HBoxContainer
var actions: HFlowContainer
var bar: HBoxContainer
var purse: Label
var provisions: VBoxContainer
var next_line: Label           # the one thing to do next, in a single line at the top
var summary: Label             # short company total; the detail lives in its tooltip
var _wounded := 0              # counted while the tiles are built (one health report per unit)
var _unassigned := 0
const BAGGAGE := "res://ui/baggage.tscn"
var columns: BoxContainer
var roster_panel: PanelContainer
var roster_scroll: ScrollContainer

func _ready() -> void:
	var f := UiKit.screen_frame(self, "The Company")
	bar = f["bar"]
	var outer := UiKit.scroll()
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	f["root"].add_child(outer)
	var content := UiKit.vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(content)
	bar.add_child(UiKit.spacer())
	# first thing on the page: the one thing to do next, in a single line (detail in its tooltip)
	var next_panel := UiKit.panel("Card")
	next_panel.name = "CompanyNextPanel"
	content.add_child(next_panel)
	next_line = UiKit.label("", "H2")
	next_line.name = "CompanyNext"
	next_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	next_panel.add_child(next_line)
	purse = UiKit.purse(Game)   # its own row under the bar: the whole sum always shows (a million coins and more)
	content.add_child(purse)
	var army := UiKit.button("Army", _open_muster, "Row", 96)
	army.name = "CompanyArmy"
	army.tooltip_text = "Muster: raise or stand down the field army, and review manpower, equipment, food and funding."
	bar.add_child(army)
	var relations := UiKit.button("Relations", func(): Game.goto(Relations.SCENE, {"back": Game.screen_params.get("back", "")}), "Row", 150)
	relations.tooltip_text = "Standing with each faction and the world's wars."
	bar.add_child(relations)
	var baggage := UiKit.button("Baggage", func(): Game.goto(BAGGAGE, {"back": Game.screen_params.get("back", "")}), "Row", 140)
	baggage.tooltip_text = "Everything the company carries: gear, stash, food and drink, goods and coin."
	bar.add_child(baggage)
	bar.add_child(UiKit.button("Back", _back, "", 140))
	provisions = UiKit.vbox(4)
	content.add_child(provisions)
	var body := BoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.vertical = true   # roster tiles across the full width, the selected unit's sheet underneath
	columns = body
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	# roster: compact tiles in a grid
	var lp := UiKit.panel()
	roster_panel = lp
	body.add_child(lp)
	var lv := UiKit.vbox(6)
	lp.add_child(lv)
	summary = UiKit.label("", "Small")
	summary.name = "CompanySummary"
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lv.add_child(summary)
	var sc := UiKit.scroll()
	roster_scroll = sc
	lv.add_child(sc)
	list_box = GridContainer.new()
	list_box.name = "UnitGrid"
	list_box.add_theme_constant_override("h_separation", 8)
	list_box.add_theme_constant_override("v_separation", 8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_box)
	# below: sheet for the selected unit
	var right := UiKit.vbox(0)
	UiKit.expand(right, true, true)
	body.add_child(right)
	tabs_box = UiKit.hbox(6)
	var tab_scroll := ScrollContainer.new()
	tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tab_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(tab_scroll)
	tab_scroll.add_child(tabs_box)
	var rp := UiKit.panel()
	UiKit.expand(rp, true, true)
	right.add_child(rp)
	var rv := UiKit.vbox(8)
	rp.add_child(rv)
	page = UiKit.vbox(8)
	page.custom_minimum_size.y = 330
	UiKit.expand(page, true, true)
	rv.add_child(page)
	actions = UiKit.flow(8)
	rv.add_child(actions)
	var cap := Game.lead_officer()
	if Game.screen_params.has("unit"):
		selected_uid = int(Game.screen_params["unit"])
	elif cap != null:
		selected_uid = cap.uid
	elif not Game.company.is_empty():
		selected_uid = Game.company[0].uid
	resized.connect(_fit_layout)
	_fit_layout()
	refresh()

func _fit_layout() -> void:
	if columns == null: return
	columns.vertical = true
	roster_panel.custom_minimum_size.x = 0
	roster_scroll.custom_minimum_size.y = 220
	if list_box != null:
		list_box.columns = maxi(1, int(size.x / 300))

func _back() -> void:
	var dest: String = Game.screen_params.get("back", "town" if Game.location != "" else "map")
	Game.goto(dest, Game.screen_params.get("back_params", {}))

func _open_muster() -> void:
	if String(Game.screen_params.get("back", "")) == "muster":
		Game.goto("muster", Game.screen_params.get("back_params", {}))
		return
	Game.goto("muster", {"back": "company", "back_params": Game.screen_params.duplicate(true)})

func select(uid: int) -> void:
	selected_uid = uid
	var u := Game.unit_by_uid(uid)
	if tab == "Squad" and (u == null or not u.is_officer()):
		tab = "Overview"
	refresh()

## A tab switch rebuilds the sheet only (v0.014: the roster list beside it took a health report per man, ~70 ms).
func show_tab(t: String) -> void:
	tab = t
	_build_sheet()

func refresh() -> void:
	purse.text = UiKit.purse_text(Game)
	purse.tooltip_text = "Day, coins on hand (%s in short; the full sum is shown) and daily wages." % UiKit.compact_coins(Game.gold)
	_build_provisions()
	_build_list()
	_build_sheet()
	_update_next()
	var raised := not Game.company.is_empty()
	provisions.visible = raised
	if columns != null and columns.get_child_count() > 1: (columns.get_child(1) as Control).visible = raised

## The single line at the top: the one thing the player should do next. Reads state only.
func _update_next() -> void:
	if next_line == null: return
	var text := ""
	var tip := ""
	var bad := false
	var warn := Food.warning(Game)
	var unpaid: int = Game.unpaid_count() if Game.has_method("unpaid_count") else 0
	if Game.company.is_empty():
		text = "Your army is not raised yet. Press Raise an army to muster troops."
		tip = "Use the Army button to review manpower, equipment, food and funding and raise field troops. Your household and city garrison have their own records."
		bad = true
	elif warn != "":
		text = warn
		tip = "Food and drink stock and rations are set in the row below; buy more in a town's Provisions."
		bad = true
	elif _wounded > 0:
		text = "%d unit%s wounded - select one to check Health" % [_wounded, "" if _wounded == 1 else "s"]
		tip = "A wounded unit's tile says so. Select it and open the Health tab for wounds and recovery time; badly wounded units may stay in camp."
		bad = true
	elif _unassigned > 0:
		text = "%d unit%s unassigned - move %s to a squad" % [_unassigned, "" if _unassigned == 1 else "s", "it" if _unassigned == 1 else "them"]
		tip = "Select an unassigned unit below and use Move to squad. Unassigned troops have no officer and no squad uniform."
	elif unpaid > 0:
		text = "%d men unpaid - the purse cannot cover wages" % unpaid
		tip = "Coins on hand and daily wages are in the purse line below. Unpaid men lose heart and may desert."
		bad = true
	elif Mobilization.medics(Game).is_empty():
		text = "No battle medics: pick a few commoners to tend the wounded"
		tip = "Select a commoner below and use Make battle medic. Medics skip the fighting and bandage the downed after every clash you win; they grow more skilled with each man they tend."
	else:
		text = "Company ready - %d strong" % Game.company.size()
		tip = "Nothing urgent: no wounded, nobody unassigned, food and wages covered. Select a unit below to inspect or re-equip it."
	next_line.text = text
	next_line.theme_type_variation = "Bad" if bad else "H2"
	next_line.tooltip_text = tip

# ------------------------------------------------------------------ food and drink (core/food.gd)
## Ration toggles (company-wide), days of food and drink at these rations, and one warning banner.
func _build_provisions() -> void:
	UiKit.clear(provisions)
	var p := UiKit.panel("Inset")
	provisions.add_child(p)
	var h := UiKit.flow(8)
	p.add_child(h)
	var fl := UiKit.label("Food: %s" % Food.days_text(Food.food_days(Game)), "H2")
	fl.custom_minimum_size.x = 170
	fl.tooltip_text = "Days of food at these rations. Stock: %d meals." % Food.stock(Game, "meal")
	h.add_child(fl)
	for r in Food.FOOD_RATIONS:
		var fb := UiKit.button(Food.RATION_LABELS[r], set_ration.bind("food", r), "RowOn" if Game.rations.get("food") == r else "Row", 96)
		fb.tooltip_text = "Serve %s food rations to the whole company." % String(Food.RATION_LABELS[r]).to_lower()
		h.add_child(fb)
	h.add_child(UiKit.spacer())
	var dl := UiKit.label("Drink: %s" % ("none served" if Game.rations.get("drink") == "dry" else Food.days_text(Food.drink_days(Game))), "H2")
	dl.custom_minimum_size.x = 190
	dl.tooltip_text = "Days of drink at these rations. Stock: %d mugs of beer, %d cups of wine." % [Food.stock(Game, "beer"), Food.stock(Game, "wine")]
	h.add_child(dl)
	for r in Food.DRINK_RATIONS:
		var db := UiKit.button(Food.RATION_LABELS[r], set_ration.bind("drink", r), "RowOn" if Game.rations.get("drink") == r else "Row", 96)
		db.tooltip_text = "Serve %s drink rations to the whole company." % String(Food.RATION_LABELS[r]).to_lower()
		h.add_child(db)
	var warn := Food.warning(Game)
	if warn != "":
		var chip := UiKit.chip(warn, UiTheme.BAD)
		chip.name = "FoodWarning"
		chip.tooltip_text = warn
		h.add_child(chip)

func set_ration(kind: String, value: String) -> void:
	Game.rations[kind] = value
	refresh()

# ------------------------------------------------------------------ roster: compact tiles in the grid
func _build_list() -> void:
	UiKit.clear(list_box)
	_wounded = 0
	_unassigned = 0
	if Game.company.is_empty():
		var card := UiKit.panel("Card")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_box.add_child(card)
		var cv := UiKit.vbox(6)
		card.add_child(cv)
		var unraised := UiKit.label("Field army unraised", "H2", true)
		unraised.name = "CompanyUnraised"
		unraised.tooltip_text = "Your household and city garrison have their own records."
		cv.add_child(unraised)
		var muster := UiKit.button("Raise an army", _open_muster, "Row")
		muster.name = "CompanyRaiseArmy"
		muster.tooltip_text = "Review manpower, equipment, food and funding in Army (Muster)."
		cv.add_child(muster)
	var leaders := Roster.leaders(Game)
	for l in leaders:
		var troops := Roster.troops_of(Game, l.uid)
		var count := "%d/%d" % [troops.size(), Roster.MAX_TROOPS]
		list_box.add_child(_row(l, count, true))
		for t in troops:
			list_box.add_child(_row(t, count, false))
	var un := Roster.unassigned(Game)
	_unassigned = un.size()
	for t in un:
		list_box.add_child(_row(t, "Unassigned", false))
	# totals stay one short line; the detail that used to sit under the list is its tooltip
	if summary != null:
		summary.text = "%d strong · %d officers" % [Game.company.size(), Roster.officer_count(Game)]
		var tip := "%d in the company, %d officers. Stash: %d items. Coins: %s." % [Game.company.size(), Roster.officer_count(Game), Game.stash.size(), UiKit.compact_coins(Game.gold)]
		if Game.has_method("best_skill"):
			var best := []
			for s in DB.UTILITY_SKILLS_V1:
				var lv: int = Game.best_skill(s)
				if lv > 0:
					best.append("%s %s" % [UiWords.skill_level(lv), UiWords.skill_name(s).to_lower()])
			tip += " Company's best: " + (", ".join(PackedStringArray(best)) if not best.is_empty() else "no utility skills") + "."
			if Game.has_method("loot_fraction"):
				tip += " Loot share %d%%." % int(round(Game.loot_fraction() * 100))
		summary.tooltip_text = tip

## One compact unit tile, at most 3 lines: name (big), "count · type · condition", optional camp tag.
## Kept name/signature: count_text is the squad strength ("3/24") or "Unassigned".
func _row(u: Unit, count_text: String, leader: bool) -> Button:
	var rep := HealthReport.describe(u)   # one health report per tile (v0.014 speed)
	var st: String = rep.get("status", "healthy")
	if st in ["wounded", "badly wounded", "unconscious"]:
		_wounded += 1
	var b := UiKit.button("", select.bind(u.uid), "RowOn" if u.uid == selected_uid else "Row")
	b.custom_minimum_size = Vector2(0, 84)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind: String = u.title if u.title != "" else u.role
	b.tooltip_text = "%s, %s - %s. Select for the full sheet." % [u.name, kind, st] + (" Leads this squad." if leader else "")
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UiKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var p := UiKit.portrait(u, 64 if leader else 56)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(p)
	h.add_child(col)
	var l := UiKit.label(u.name, "H2")
	l.name = "RosterName"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 60
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	var medic_now := Mobilization.is_medic(Game, u)
	var detail := UiKit.label(("medic · %s · %s" % [UiWords.skill_level(u.skill("surgeon")).to_lower(), st]) if medic_now else ("%s · %s · %s" % [count_text, kind, st]), "Bad" if st in ["badly wounded", "unconscious", "dead"] else "Small")
	if medic_now: detail.add_theme_color_override("font_color", UiTheme.BLUE)
	detail.name = "RosterDetail"
	if st == "wounded":
		detail.add_theme_color_override("font_color", UiTheme.WARN)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.custom_minimum_size.x = 60
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.tooltip_text = detail.text
	col.add_child(detail)
	var why: String = Game.deploy_block_reason(u, rep)
	if why != "" and why != "dead":
		b.custom_minimum_size.y = 108
		var tr := UiKit.hbox(4)
		tr.name = "RosterTags"
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(tr)
		tr.add_child(_tag("stays in camp" + ("" if why == st else ": " + why), UiTheme.BAD))
	b.add_child(m)
	return b

## A small status tag that gives up width (ellipsis) instead of pushing the row wider.
func _tag(text: String, bg: Color) -> Control:
	var c := UiKit.chip(text, bg)
	var cl := c.get_child(0) as Label
	cl.add_theme_font_size_override("font_size", 15)
	cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cl.custom_minimum_size.x = 24
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = maxf(1.0, text.length() / 8.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.tooltip_text = text
	return c

# ------------------------------------------------------------------ sheet
func _build_sheet() -> void:
	UiKit.clear(tabs_box)
	UiKit.clear(page)
	UiKit.clear(actions)
	var u := Game.unit_by_uid(selected_uid)
	if u == null:
		page.add_child(UiKit.label("No field troops are raised. Review manpower, equipment, food and funding in Army." if Game.company.is_empty() else "No army member selected. Your household and city troops have their own records.", "Muted", true))
		return
	var names := ["Overview", "Mind", "Skills", "Gear", "Health"]
	if u.is_officer():
		names.append("Squad")
	tabs_box.add_child(UiKit.tab_strip(names, tab, show_tab))
	match tab:
		"Mind": page.add_child(UnitSheet.mind(u))
		"Skills": page.add_child(UnitSheet.skills(u))
		"Gear": page.add_child(UnitSheet.gear(u, Game, self, refresh))
		"Health": page.add_child(UnitSheet.health(u))
		"Squad": page.add_child(_squad_page(u))
		_: page.add_child(UnitSheet.overview(u))
	_build_actions(u)

func _build_actions(u: Unit) -> void:
	if not u.is_officer():
		actions.add_child(UiKit.button("Move to squad", func(): _pick_squad(u), "", 0))
		var pr := UiKit.button("Promote to officer", func():
			var err := Roster.promote(Game, u)
			if err != "":
				UiKit.toast(self, err, false)
			else:
				UiKit.toast(self, "%s now leads a squad" % u.name)
			refresh(), "", 0)
		var noble := Mobilization.is_house_rider(Game, u) or Army.house_born(u)
		pr.disabled = Roster.officer_count(Game) >= Roster.MAX_OFFICERS or not noble
		if not noble: pr.tooltip_text = "Only house members can hold rank; commoners stay in the ranks."
		actions.add_child(pr)
		if not noble:
			var medic := Mobilization.is_medic(Game, u)
			actions.add_child(UiKit.button("Return to the ranks" if medic else "Make battle medic", func():
				var r: Dictionary = Mobilization.set_medic(Game, u, not medic)
				UiKit.toast(self, String(r.get("reason", "")), bool(r.get("ok", false)))
				refresh(), "", 0))
	actions.add_child(UiKit.spacer())
	if u.role != "captain":
		var dismiss := UiKit.button("Dismiss", _request_dismiss.bind(u), "Danger", 140)
		dismiss.name = "CompanyDismiss"
		actions.add_child(dismiss)

static func dismissal_text(u: Unit) -> String:
	var town: Dictionary = Game.world.get("towns",{}).get(u.home_town,{})
	var family: Dictionary = People.fam_of(town,u.family)
	if Mobilization.manages(Game,u) or not Persons.by_uid(family,u.uid).is_empty():
		return "Return %s to their actual home in %s? This requires being at the permitted home. Their identity, injuries and owned kit remain; borrowed equipment returns to the settlement." % [u.name,String(town.get("name",u.home_town))]
	return "Dismiss %s? Their gear goes to the stash.%s" % [u.name," Their troops become unassigned." if u.is_officer() else ""]

func _request_dismiss(u: Unit) -> void:
	UiKit.confirm(self,dismissal_text(u),"Dismiss",_dismiss.bind(u))

func _dismiss(u: Unit) -> String:
	var error: String = Roster.dismiss(Game,u)
	if error != "":
		UiKit.toast(self,error,false)
		return error
	var lead: Unit = Game.lead_officer()
	selected_uid = lead.uid if lead != null else -1
	tab = "Overview"
	refresh()
	Game.save_game_async()
	return ""

func _pick_squad(u: Unit) -> void:
	var opts := []
	for l in Roster.leaders(Game):
		var n := Roster.troops_of(Game, l.uid).size()
		opts.append({"text": "%s's squad" % l.name, "value": l.uid, "detail": "%d/%d" % [n, Roster.MAX_TROOPS],
			"disabled": l.uid == u.squad or n >= Roster.MAX_TROOPS})
	opts.append({"text": "Unassigned", "value": -1, "disabled": u.squad == -1})
	UiKit.picker(self, "Move %s to..." % u.name, opts, func(uid):
		var err := Roster.move_troop(Game, u, uid)
		if err != "":
			UiKit.toast(self, err, false)
		refresh())

# ------------------------------------------------------------------ squad uniform
func _squad_page(off: Unit) -> Control:
	Roster.ensure_squad(Game, off.uid)
	var rule: Dictionary = Game.squads[off.uid]
	if not rule.has("uniform"):
		rule["uniform"] = {}
	var sc := UiKit.scroll()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.custom_minimum_size.y = 330
	var v := UiKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var top := UiKit.flow(10)
	top.add_child(UiKit.label("%s's squad uniform" % off.name, "H2"))
	top.add_child(UiKit.spacer())
	top.add_child(UiKit.label("Metal:", "Muted"))
	for m in ["any", "copper", "tin"]:
		var cur: String = rule.get("material", "any")
		top.add_child(UiKit.button(m, func():
			rule["material"] = m
			refresh(), "RowOn" if cur == m else "Row", 96))
	v.add_child(top)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var uni: Dictionary = rule["uniform"]
	var two := Outfit.is_two_handed(String(uni.get("main_hand", "")))
	for slot in DB.EQUIP_SLOTS:
		var row := UiKit.hbox(8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sl := UiKit.label(UiWords.slot_name(slot), "Muted")
		sl.custom_minimum_size.x = 118
		row.add_child(sl)
		var txt := Outfit.template_name(uni[slot]) if uni.has(slot) and uni[slot] != "" else "(free choice)"
		if slot == "off_hand" and two:
			txt = "(none: two-handed)"
		var b := UiKit.button(txt, func(): _pick_uniform(off, slot), "Row")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.disabled = slot == "off_hand" and two
		row.add_child(b)
		grid.add_child(row)
	var acts := UiKit.flow(8)
	acts.add_child(UiKit.button("Apply uniform", func():
		var r := Outfit.apply_uniform(Game.squads, Game.company, off.uid, Game.stash)
		refresh()
		UnitSheet._report(self, r["missing"], r["equipped"]), "", 0))
	acts.add_child(UiKit.button("Apply all squads", func():
		var miss := []
		var n := 0
		for l in Roster.leaders(Game):
			var r := Outfit.apply_uniform(Game.squads, Game.company, l.uid, Game.stash)
			miss.append_array(r["missing"])
			n += int(r["equipped"])
		refresh()
		UnitSheet._report(self, miss, n), "Row", 0))
	v.add_child(acts)
	v.add_child(UiKit.label("Troops", "H2"))
	var troops := Roster.troops_of(Game, off.uid)
	if troops.is_empty():
		v.add_child(UiKit.label("No troops yet. Hire in town or move troops here.", "Muted"))
	for t in troops:
		var miss := []
		var want := Outfit.wanted(Game.squads, t)
		for slot in want:
			if want[slot] != "" and (not t.equip.has(slot) or t.equip[slot].tid != want[slot]):
				miss.append(Outfit.template_name(want[slot]))
		var line := "%s: %s" % [t.name, "fully outfitted" if miss.is_empty() else "lacks " + ", ".join(miss)]
		var l := UiKit.label(line, "Good" if miss.is_empty() else "Bad", true)
		v.add_child(l)
	return sc

func _pick_uniform(off: Unit, slot: String) -> void:
	var opts := [{"text": "(free choice: keep whatever they have)", "value": "__free"}]
	for tid in Outfit.templates_for_slot(slot):
		opts.append({"text": Outfit.template_name(tid) + (" (two-handed)" if Outfit.is_two_handed(tid) else ""),
			"value": tid, "detail": UiWords.faction_name(UnitSheet._culture_faction(tid))})
	UiKit.picker(self, "Uniform %s for %s's squad" % [UiWords.slot_name(slot).to_lower(), off.name], opts, func(val):
		var uni: Dictionary = Game.squads[off.uid]["uniform"]
		if val == "__free":
			uni.erase(slot)
		else:
			uni[slot] = val
			if slot == "main_hand" and Outfit.is_two_handed(val):
				uni.erase("off_hand")
		refresh())
