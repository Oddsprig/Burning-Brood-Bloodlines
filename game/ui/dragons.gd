class_name DragonsView
extends Control
## Holdings, pure care quotes and native orders with fresh registry review.
var body: VBoxContainer
var roster: Array = []
var detail_uid := ""
var holdings := "house"
var catalog_open := false
const PAGE := 9
var page := 0
var notice := ""
var back := "house"
var back_params: Dictionary = {}
var _refresh_pending := false
var roster_grid: GridContainer
var gem_grid: GridContainer
var model_card: DragonCard
var model_pose: String = "idle"
var model_state: Dictionary = {}
var model_rider: Dictionary = {}
var model_zoom: bool = false
var model_play: bool = false
const BOND_PAGE_SIZE := 8
var _bond_picker: Dictionary = {}
var _mate_list: Node = null

func _ready() -> void:
	Perf.set_stage("Dragon holdings")
	back = String(Game.screen_params.get("back", "house"))
	back_params = Game.screen_params.get("back_params", {}).duplicate(true)
	detail_uid = String(Game.screen_params.get("dragon_uid", ""))
	holdings = String(Game.screen_params.get("holdings", "house"))
	var frame := UiKit.screen_frame(self, "Dragons & eggs")
	var heading: Label = frame["title"]
	heading.add_theme_font_size_override("font_size", 24)
	heading.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	UiKit.fit_title(heading)
	frame["bar"].add_child(UiKit.button("Back", _back, "Row", 72))
	var scroll := UiKit.scroll()
	frame["root"].add_child(scroll)
	body = UiKit.vbox(10)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(body)
	Game.changed.connect(_queue_refresh)
	resized.connect(_fit)
	_refresh()

func _queue_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true
	call_deferred("_refresh")

func _exit_tree() -> void:
	_bond_picker.clear()
	_mate_list = null

func _context() -> Dictionary:
	return {"back": back, "back_params": back_params, "dragon_uid": detail_uid, "holdings": holdings}

func _refresh() -> void:
	_refresh_pending = false
	UiKit.clear(body)
	model_card = null
	roster_grid = null; gem_grid = null
	if notice != "": body.add_child(UiKit.label(notice, "", true))
	if detail_uid != "":
		var row: Dictionary = Dragons.get_record(Game, detail_uid)
		if not row.is_empty():
			_detail(row)
			return
		detail_uid = ""
	var controls := UiKit.flow()
	body.add_child(controls)
	for choice in [["Your house", "house"], ["Your realm", "realm"], ["All holdings", "all"]]:
		var button := UiKit.button(String(choice[0]), _choose_holdings.bind(String(choice[1])), "Row")
		button.disabled = holdings == String(choice[1])
		controls.add_child(button)
	controls.add_child(UiKit.button("Hide varieties" if catalog_open else "Gem types & body forms", _toggle_catalog, "Row"))
	var selected: Dictionary = Dynasty.selected(Game)
	roster = Dragons.records(Game, String(selected.get("house_uid", ""))) if holdings == "house" else Dragons.records(Game)
	if holdings == "house" and selected.is_empty(): roster = []
	if holdings == "realm":
		var faction := String(Game.world.get("towns", {}).get(String(selected.get("town_id", "")), {}).get("faction", ""))
		roster = roster.filter(func(row): return faction != "" and String(Game.world.get("towns", {}).get(String(row.get("estate_town_id", "")), {}).get("faction", "")) == faction)
		body.add_child(UiKit.label("Holdings whose estate lies in " + UiWords.faction_name(faction), "Muted", true))
	body.add_child(UiKit.label("%d holdings" % roster.size(), "H2", true))
	if roster.is_empty(): body.add_child(UiKit.label("No dragons or eggs registered for this view.", "Muted", true))
	roster_grid = GridContainer.new(); roster_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	roster_grid.add_theme_constant_override("h_separation", 10); roster_grid.add_theme_constant_override("v_separation", 10)
	body.add_child(roster_grid)
	# Pages of 9 cards: a large world has 80+ holdings and every card paints a dragon.
	var pages := maxi(1, ceili(float(roster.size()) / PAGE))
	page = clampi(page, 0, pages - 1)
	for row: Dictionary in roster.slice(page * PAGE, (page + 1) * PAGE): _roster_card(row)
	if pages > 1:
		var nav := UiKit.hbox(8); body.add_child(nav)
		var prev := UiKit.button("Previous", func(): page -= 1; _refresh(), "Row", 120); prev.disabled = page == 0; nav.add_child(prev)
		nav.add_child(UiKit.label("Page %d of %d" % [page + 1, pages], "Muted"))
		var nxt := UiKit.button("Next", func(): page += 1; _refresh(), "Row", 120); nxt.disabled = page >= pages - 1; nav.add_child(nxt)
	if catalog_open: _catalog()
	_fit()

func _fit() -> void:
	var width := get_viewport_rect().size.x
	if roster_grid != null: roster_grid.columns = 3 if width >= 1100 else (2 if width >= 750 else 1)
	if gem_grid != null: gem_grid.columns = maxi(1, mini(4, int(maxf(1, width - 32) / 250)))

func _choose_holdings(value: String) -> void:
	holdings = value; detail_uid = ""; page = 0; _refresh()

func _toggle_catalog() -> void:
	catalog_open = not catalog_open; _refresh()

func _open_dragon(uid: String) -> void:
	detail_uid = uid; _refresh()

func _roster_card(row: Dictionary) -> void:
	var panel := UiKit.panel("Card")
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	roster_grid.add_child(panel)
	var content := UiKit.vbox(6)
	panel.add_child(content)
	content.add_child(UiKit.label(String(row.get("name", "Unnamed dragon")), "H2", true))
	var visual := DragonCard.new()
	visual.custom_minimum_size = Vector2(0, 160)
	visual.set_record(row)
	content.add_child(visual)
	# Three short lines: what it is, who rides it, what it is doing. Everything else is in the holding view.
	var egg := String(row.get("stage","")) == "egg"
	var kind := UiKit.label(Dragons.type_label(row) + ("" if egg else " · %s · %s" % [String(row.get("size_class","")).capitalize(), String(row.get("stage","")).capitalize()]), "", true)
	content.add_child(kind)
	var bond: Dictionary = DragonBond.status(Game,String(row.get("id","")))
	var who := "Rider: %s" % String(bond.get("rider",{}).get("name","?")) if bool(bond.get("bonded",false)) else ("Hatches after %d more days of care" % maxi(0, int(DragonLife.HATCH_DAYS) - int(row.get("incubation",0.0))) if egg else "No rider yet")
	content.add_child(UiKit.label(who, "Muted", true))
	if not egg:
		var marching: bool = bool(row.get("campaign_march",{}).get("enabled",false))
		var defending: bool = bool(row.get("combat_order",{}).get("enabled",false))
		var doing := UiKit.label("Marching with your army" if marching else ("Defending %s" % _town_name(String(row.get("location_town_id","")))) if defending else "At rest in %s" % _town_name(String(row.get("location_town_id",""))), "Small", true)
		if marching: doing.add_theme_color_override("font_color", UiTheme.WARN)
		content.add_child(doing)
	_breeding_bits(content, row)
	content.add_child(UiKit.button("Open", _open_dragon.bind(String(row.get("id", ""))), "Row"))

static func _catalog_name(group: String, id: String) -> String:
	return String(DragonCard.catalog_entry(group, id).get("name", id.replace("_", " ").capitalize()))

static func _town_name(id: String) -> String:
	return String(Game.world.get("towns", {}).get(id, {}).get("name", "Unknown location" if id == "" else id))

static func _person_name(uid: String) -> String:
	if uid == "": return "None"
	var person: Dictionary = Dynasty.person(Game, uid)
	return String(person.get("name", "Unrecorded person")) + (" (deceased)" if not person.is_empty() and not bool(person.get("alive", false)) else "")

static func _household_name(uid: String) -> String:
	for town: Dictionary in Game.world.get("towns", {}).values():
		for family: Dictionary in town.get("econ", {}).get("fams", []):
			if String(family.get("household_uid", "")) == uid: return String(family.get("name", "Household"))
	return "Unrecorded household"

static func _stage(row: Dictionary) -> String:
	return String(row.get("stage", "egg")).capitalize() + (" · deceased" if not bool(row.get("alive", true)) else "")

static func appearance_text(row: Dictionary) -> String:
	if String(row.get("stage", "egg")) == "egg":
		var gem: Dictionary = DragonCard.catalog_entry("gems", String(row.get("gem_id", "")))
		return "%s · Shell: %s · %s" % [_stage(row), gem.get("name", "Unknown colour"), String(gem.get("pattern", "")).capitalize()]
	return "Type: %s\nBody form: %s · Size: %s · %s" % [Dragons.type_label(row), _catalog_name("morphs", String(row.get("morph_id", ""))), _catalog_name("sizes", String(row.get("size_class", ""))), _stage(row)]

static func physical_text(profile: Dictionary) -> String:
	if not bool(profile.get("active", false)): return ""
	return "Tooth & claw hardness: %.0f/100\nMass: %.1f kg · Strength: %.1f · Bite force: %.0f N\nTeeth: %.1f cm long · Tip area: %.2f cm² · Penetration: %.1f cm\nClaws: %.1f cm long · Tip area: %.2f cm² · Penetration: %.1f cm" % [float(profile.get("hardness_index", 0)), float(profile.get("body_mass_kg", 0)), float(profile.get("strength", 0)), float(profile.get("bite_force_n", 0)), float(profile.get("tooth_length_cm", 0)), float(profile.get("tooth_contact_cm2", 0)), float(profile.get("tooth_penetration_cm", 0)), float(profile.get("claw_length_cm", 0)), float(profile.get("claw_contact_cm2", 0)), float(profile.get("claw_penetration_cm", 0))]

static func care_condition_text(row: Dictionary, quote: Dictionary) -> String:
	if not bool(row.get("alive", true)): return "Deceased · No daily care charge"
	var health: float = clampf(float(quote.get("health", 1.0)), 0.0, 1.0)
	var condition: String = "Egg condition" if String(row.get("stage", "egg")) == "egg" else "Health"
	var state: String = "Care interrupted"
	if bool(quote.get("care_active", false)):
		var enough: bool = float(quote.get("food_possible_units", 0.0)) >= float(quote.get("food_need_units", 0.0)) and float(quote.get("upkeep_possible_units", 0.0)) >= float(quote.get("upkeep_need_units", 0.0))
		state = "Care ready" if enough else "Supplies short"
	return "%s: %.0f%% · %s" % [condition, health * 100.0, state]

static func care_quote_text(row: Dictionary, quote: Dictionary) -> String:
	var egg: bool = String(row.get("stage", "egg")) == "egg"
	var health: float = clampf(float(quote.get("health", 1.0)), 0.0, 1.0)
	var lines: Array[String] = ["%s: %.0f%%" % ["Egg condition" if egg else "Health", health * 100.0]]
	if not egg:
		var growth: float = maxf(0.0, float(quote.get("growth_points", 0.0)))
		var last_size: int = maxi(0, Dragons.catalogs().get("sizes", []).size() - 1)
		lines[0] += " · Maximum size reached" if growth >= last_size else " · Growth toward next size: %.2f%%" % (fposmod(growth, 1.0) * 100.0)
	if not bool(row.get("alive", true)):
		lines.append("No daily feed or upkeep charge.")
		return "\n".join(lines)
	lines.append("Payer: %s · Household purse: %s · Spendable: %s" % [String(quote.get("payer_name", "Unrecorded household")), RecData.money(float(quote.get("payer_purse", 0.0))), RecData.money(float(quote.get("spendable", 0.0)))])
	var keeper: String = String(quote.get("keeper_name", ""))
	lines.append("Keeper: %s · %s" % [keeper if keeper != "" else "None present", "Care available" if bool(quote.get("care_active", false)) else "Care interrupted"])
	var reason: String = String(quote.get("reason", ""))
	if reason != "": lines.append(reason)
	lines.append("Next daily care · Current market quote at " + _town_name(String(row.get("location_town_id", ""))))
	if egg:
		lines.append("No meat required.")
	else:
		lines.append("Food need: %.2f kg / %.2f market units · Available: %.2f units at %s each" % [float(quote.get("food_need_kg", 0.0)), float(quote.get("food_need_units", 0.0)), float(quote.get("food_available_units", 0.0)), RecData.money(float(quote.get("food_unit_price", 0.0)))])
		lines.append("Food affordable now: %.2f units · Estimated food cost: %s" % [float(quote.get("food_possible_units", 0.0)), RecData.money(float(quote.get("feed_cost_estimate", 0.0)))])
	lines.append("Shelter supplies (wood): %.2f of %.2f bundles affordable · Estimated cost: %s" % [float(quote.get("upkeep_possible_units", 0.0)), float(quote.get("upkeep_need_units", 0.0)), RecData.money(float(quote.get("upkeep_cost_estimate", 0.0)))])
	lines.append("Quotes are not payments. Automatic daily care buys locally from this household after protecting its food reserve.")
	lines.append("Shelter shortages lower egg condition. Care needs a present keeper." if egg else "Healthy growth needs enough feed and care. Food or shelter shortages lower condition.")
	lines.append(DragonCare.priority_line(str(quote.get("priority", "normal"))))
	return "\n".join(lines)

static func care_receipt_text(row: Dictionary, receipt: Dictionary) -> String:
	if receipt.is_empty(): return "No daily care payment recorded yet."
	if str(receipt.get("source", "market")) == "army":
		var march_lines: Array[String] = ["Last daily care · Day %d · Meat drawn from the army's packed stores" % int(receipt.get("day", 0))]
		if String(row.get("stage", "egg")) != "egg":
			march_lines.append("Meat drawn: %.2f units · Coins spent: %s · Feed achieved: %.0f%%" % [float(receipt.get("food_units", 0.0)), RecData.money(0.0), float(receipt.get("food_ratio", 0.0)) * 100.0])
		march_lines.append("The march is the shelter. No household coin was spent.")
		march_lines.append("Condition: %.0f%% → %.0f%%" % [float(receipt.get("health_before", 1.0)) * 100.0, float(receipt.get("health_after", 1.0)) * 100.0])
		if String(row.get("stage", "egg")) != "egg": march_lines[-1] += " · Grew this day" if float(receipt.get("growth_after", 0.0)) > float(receipt.get("growth_before", 0.0)) else " · No growth this day"
		var march_reason: String = String(receipt.get("reason", ""))
		if march_reason != "": march_lines.append(march_reason)
		return "\n".join(march_lines)
	var lines: Array[String] = ["Last daily care · Day %d · Paid by %s" % [int(receipt.get("day", 0)), _household_name(String(receipt.get("payer_household_uid", "")))]]
	if String(row.get("stage", "egg")) != "egg":
		lines.append("Food bought: %.2f units · Paid: %s · Feed achieved: %.0f%%" % [float(receipt.get("food_units", 0.0)), RecData.money(float(receipt.get("food_cost", 0.0))), float(receipt.get("food_ratio", 0.0)) * 100.0])
	lines.append("Shelter supplies bought: %.2f wood bundles · Paid: %s · Care achieved: %.0f%%" % [float(receipt.get("upkeep_units", 0.0)), RecData.money(float(receipt.get("upkeep_cost", 0.0))), float(receipt.get("care_ratio", 0.0)) * 100.0])
	lines.append("Condition: %.0f%% → %.0f%%" % [float(receipt.get("health_before", 1.0)) * 100.0, float(receipt.get("health_after", 1.0)) * 100.0])
	if String(row.get("stage", "egg")) != "egg": lines[-1] += " · Grew this day" if float(receipt.get("growth_after", 0.0)) > float(receipt.get("growth_before", 0.0)) else " · No growth this day"
	var reason: String = String(receipt.get("reason", ""))
	if reason != "": lines.append(reason)
	return "\n".join(lines)

func _care_panel(row: Dictionary) -> void:
	var quote: Dictionary = DragonCare.status(Game, row)
	var panel: PanelContainer = UiKit.panel("Card")
	panel.name = "CareGrowth"
	body.add_child(panel)
	var facts: VBoxContainer = UiKit.vbox(6)
	panel.add_child(facts)
	facts.add_child(UiKit.label("Care & growth", "H2", true))
	facts.add_child(UiKit.label(care_quote_text(row, quote), "", true))
	facts.add_child(UiKit.label(care_receipt_text(row, quote.get("last", {})), "Muted", true))
	if bool(row.get("alive", false)):
		var priority := str(quote.get("priority", "normal"))
		var rights := bool(Dragons.authority(Game, row).get("ok", false))
		var flow := UiKit.flow()
		facts.add_child(flow)
		for choice in [["first", "Feed first"], ["normal", "Normal"], ["last", "Last"]]:
			var key := str(choice[0])
			var button := UiKit.button(str(choice[1]), _set_feed_priority.bind(str(row.get("id", "")), key), "Row")
			button.disabled = (not rights) or key == priority
			button.tooltip_text = DragonCare.priority_line(priority)
			flow.add_child(button)

func _set_feed_priority(uid: String, priority: String) -> void:
	var live: Dictionary = Game.world.get("dragons", {}).get("records", {}).get(uid, {})
	if live.is_empty(): return
	var result := DragonCare.set_priority(Game, live, priority)
	notice = str(result.get("reason", ""))
	if bool(result.get("ok", false)):
		Game.changed.emit()
		Game.save_game_async()
	_queue_refresh()

func _detail(row: Dictionary) -> void:
	body.add_child(UiKit.button("Back to holdings", func(): detail_uid = ""; _refresh(), "Row"))
	body.add_child(UiKit.label(String(row.get("name", "Dragon")), "H2", true))
	_bond_panel(row)
	_combat_panel(row)
	_breeding_panel(row)
	var visual := DragonCard.new()
	visual.custom_minimum_size = Vector2(0, 230)
	visual.set_record(row)
	body.add_child(visual)
	if String(row.get("stage", "egg")) != "egg":
		model_card = visual
		model_pose = "idle" if bool(row.get("alive", true)) else "dead"
		model_state = {}; model_rider = {}; model_zoom = false; model_play = false
		_model_controls(row)
	body.add_child(UiKit.label(appearance_text(row), "", true))
	if String(row.get("stage", "egg")) != "egg":
		var morph: Dictionary = DragonCard.catalog_entry("morphs", String(row.get("morph_id", "")))
		body.add_child(UiKit.label(String(morph.get("description", "")), "Muted", true))
	var age := "Laid %d days ago" % int(floor(maxf(0, Game.day - float(row.get("laid_day", Game.day))))) if row.get("stage", "egg") == "egg" else "Age: %.2f years" % Dragons.age_years(Game, row)
	body.add_child(UiKit.label("%s · Sex: %s" % [age, String(row.get("sex", "unknown")).capitalize()], "Muted", true))
	_care_panel(row)
	var profile: Dictionary = Dragons.physical_profile(Game, row)
	if bool(profile.get("active", false)):
		var panel := UiKit.panel("Card")
		body.add_child(panel)
		var facts := UiKit.vbox(4)
		panel.add_child(facts)
		facts.add_child(UiKit.label("Physical profile", "H2", true))
		facts.add_child(UiKit.label(physical_text(profile), "", true))
	body.add_child(UiKit.label("Owner: %s\nOwning household: %s\nCustodian: %s\nLocation: %s · Estate: %s" % [_person_name(String(row.get("owner_person_uid", ""))), _household_name(String(row.get("owner_household_uid", ""))), _person_name(String(row.get("custodian_person_uid", ""))), _town_name(String(row.get("location_town_id", ""))), _town_name(String(row.get("estate_town_id", "")))], "", true))
	if String(row.get("owner_status", "claimed")) == "unclaimed": body.add_child(UiKit.label("Unclaimed inheritance · Previous owner retained in the register.", "Muted", true))
	var controls := UiKit.flow()
	body.add_child(controls)
	var authority: bool = bool(Dragons.authority(Game,row).get("ok",false))
	for action in [["Gift ownership", "transfer"], ["Choose custodian", "set_custodian"]]:
		var button := UiKit.button(String(action[0]), _choose_person.bind(String(row["id"]), String(action[1])), "Row")
		button.disabled = not authority
		button.tooltip_text = "Only the current leader of the actual owning household may give orders." if not authority else "Review the actual person and current holding before confirming."
		controls.add_child(button)
	var owner := String(row.get("owner_person_uid", ""))
	if owner != "": controls.add_child(UiKit.button("Owner's person record", _person_record.bind(owner), "Row"))
	var custodian := String(row.get("custodian_person_uid", ""))
	if custodian != "": controls.add_child(UiKit.button("Custodian's person record", _person_record.bind(custodian), "Row"))
	body.add_child(UiKit.label("Ownership is separate from custody and location.", "Muted", true))
	var parents := UiKit.flow()
	body.add_child(parents)
	for parent in [["Mother", "mother_uid"], ["Father", "father_uid"]]:
		var parent_uid := String(row.get(parent[1], ""))
		var known: Dictionary = Dragons.get_record(Game, parent_uid) if parent_uid != "" else {}
		body.add_child(UiKit.label("%s: %s" % [parent[0], known.get("name", "Not recorded")], "Muted", true))
		if not known.is_empty(): parents.add_child(UiKit.button("View " + String(parent[0]).to_lower(), _open_dragon.bind(parent_uid), "Row"))
	var founders: Array[String] = []
	for relative: Dictionary in Dragons.records(Game):
		if relative.get("bloodline_uid", "") == row.get("bloodline_uid", "") and relative.get("stage", "egg") != "egg" and relative.get("mother_uid", "") == "" and relative.get("father_uid", "") == "": founders.append(String(relative.get("name", "")))
	if not founders.is_empty(): body.add_child(UiKit.label("Bloodline founders: " + ", ".join(founders), "Small", true))
	for event in row.get("history", []).slice(-6):
		if event is Dictionary: body.add_child(UiKit.label("Day %d · %s" % [int(event.get("day", 0)), _history_text(event)], "Small", true))
		else: body.add_child(UiKit.label(String(event), "Small", true))

static func bond_status_text(status: Dictionary) -> String:
	if not bool(status.get("bonded",false)): return "Unbonded · No rider"
	var rider: Dictionary = status.get("rider",{})
	return "Rider: %s · %s" % [String(rider.get("name","Unrecorded person")),"Bond active" if bool(status.get("active",false)) else "Bond inactive"]

static func combat_order_text(status: Dictionary) -> String:
	var text: String = "Settlement defence: Ordered" if bool(status.get("enabled",false)) else "Settlement defence: Off"
	var reason: String = String(status.get("reason",""))
	return text+(" · "+reason if reason != "" else "")

func _combat_panel(row: Dictionary) -> void:
	var uid: String = String(row["id"])
	var status: Dictionary = DragonCombat.combat_status(Game,uid)
	var panel := UiKit.panel("Card"); panel.name = "DragonCombatPanel"; body.add_child(panel)
	var facts := UiKit.vbox(4); panel.add_child(facts)
	var label := UiKit.label(combat_order_text(status),"Small",true); label.name = "DragonCombatStatus"; facts.add_child(label)
	var controls := UiKit.flow(); facts.add_child(controls)
	var defend := UiKit.button("Defend this settlement",_request_combat.bind(uid,true),"Row"); defend.name = "DragonDefendSettlement"
	defend.disabled = not bool(status.get("can_enable",false)); defend.tooltip_text = String(status.get("reason","")); controls.add_child(defend)
	var withdraw := UiKit.button("Withdraw",_request_combat.bind(uid,false),"Row"); withdraw.name = "DragonWithdraw"
	withdraw.disabled = not bool(status.get("can_withdraw",false)); controls.add_child(withdraw)
	# Campaign deployment: march with the field army wherever it goes (campaign/warfare.gd).
	var march: Dictionary = Warfare.march_status(Game,uid)
	var march_label := UiKit.label(("War: " if bool(march.get("marching",false)) else "Campaign: ")+String(march.get("reason","")),"Small",true); facts.add_child(march_label)
	var go := UiKit.button("Recall home" if bool(march.get("marching",false)) else "March with army",func():
		var r: Dictionary = Warfare.set_march(Game,uid,not bool(march.get("marching",false)))
		notice = String(r.get("reason",""))
		if bool(r.get("ok",false)): Game.changed.emit(); Game.save_game_async()
		_queue_refresh(),"Row"); go.name = "DragonMarch"
	go.disabled = not (bool(march.get("marching",false)) or bool(march.get("can_march",false))); go.tooltip_text = String(march.get("reason",""))
	controls.add_child(go)

func _player_adult(row: Dictionary) -> bool:
	if String(row.get("stage", "")) != "adult" or not bool(row.get("alive", false)): return false
	var house := String(Game.world.get("player_house", {}).get("house_uid", ""))
	return house != "" and String(row.get("owner_house_uid", "")) == house

func pair_status_text(row: Dictionary) -> String:
	var partner := String(row.get("paired_with_uid", ""))
	if partner == "": return ""
	var mate: Dictionary = Dragons.get_record(Game, partner)
	var name := String(mate.get("name", ""))
	if name == "" or not bool(mate.get("alive", false)): return ""
	var mother_uid := String(row.get("id", "")) if String(row.get("sex", "")) == "female" else partner
	var entry: Dictionary = DragonBreeding.pairs(Game).get(mother_uid, {})
	if entry.is_empty(): return "Paired with %s" % name
	var due := int(entry.get("due_day", 0))
	if int(entry.get("clutches", 0)) > 0 and due > int(Game.day) + 20:
		return "Paired with %s; resting after a clutch until day %d" % [name, due]
	return "Paired with %s; a clutch is expected around day %d" % [name, due]

func parent_line(row: Dictionary) -> String:
	if String(row.get("stage", "")) != "egg": return ""
	var mother_name := String(Dragons.get_record(Game, String(row.get("mother_uid", ""))).get("name", ""))
	var father_name := String(Dragons.get_record(Game, String(row.get("father_uid", ""))).get("name", ""))
	if mother_name == "" or father_name == "": return ""
	return "Mother: %s, Father: %s" % [mother_name, father_name]

func _breeding_panel(row: Dictionary) -> void:
	if pair_status_text(row) == "" and parent_line(row) == "" and not _player_adult(row): return
	var panel := UiKit.panel("Card"); panel.name = "DragonBreedingPanel"; body.add_child(panel)
	var facts := UiKit.vbox(4); panel.add_child(facts)
	_breeding_bits(facts, row)

func _breeding_bits(box: Node, row: Dictionary) -> void:
	var paired := pair_status_text(row)
	if paired != "":
		var status := UiKit.label(paired, "", true); status.name = "DragonPairStatus"; box.add_child(status)
	var parents := parent_line(row)
	if parents != "":
		var line := UiKit.label(parents, "Muted", true); line.name = "DragonParentLine"; box.add_child(line)
	if _player_adult(row):
		var button := UiKit.button("Choose a mate", _open_mate_list.bind(String(row.get("id", ""))), "Row")
		button.name = "DragonPairButton"
		box.add_child(button)

func _open_mate_list(uid: String) -> void:
	_close_mate_list()
	var row: Dictionary = Dragons.get_record(Game, uid)
	if row.is_empty(): return
	var sex := String(row.get("sex", ""))
	var want := "male" if sex == "female" else ("female" if sex == "male" else "")
	var town := String(row.get("location_town_id", ""))
	var modal := UiKit.modal(self, "Choose a mate", 700); modal.name = "DragonMateList"
	modal.add_child(UiKit.label("Opposite-sex adults at %s." % _town_name(town), "Small", true))
	var scroll := UiKit.scroll(); scroll.custom_minimum_size.y = 240; modal.add_child(scroll)
	var rows := UiKit.vbox(6); rows.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(rows)
	var found := false
	for other: Dictionary in Dragons.records(Game):
		var other_id := String(other.get("id", ""))
		if other_id == "" or other_id == uid: continue
		if String(other.get("stage", "")) != "adult" or String(other.get("sex", "")) != want: continue
		if String(other.get("location_town_id", "")) != town: continue
		var mother_uid := uid if sex == "female" else other_id
		var father_uid := other_id if sex == "female" else uid
		var preview: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
		var ok := bool(preview.get("ok", false))
		var reason := String(preview.get("reason", preview.get("message", "")))
		var block := UiKit.vbox(2); block.size_flags_horizontal = SIZE_EXPAND_FILL; rows.add_child(block)
		var choice := UiKit.button(String(other.get("name", "Dragon")), _pick_mate.bind(mother_uid, father_uid), "Row")
		choice.name = "DragonMateChoice"
		choice.set_meta("mate_uid", other_id)
		choice.alignment = HORIZONTAL_ALIGNMENT_LEFT
		choice.tooltip_text = reason
		choice.disabled = not ok
		if not ok: block.modulate = Color(0.68, 0.68, 0.68)
		block.add_child(choice)
		if not ok:
			var why := UiKit.label(reason, "Muted", true); why.name = "DragonMateReason"; why.set_meta("mate_uid", other_id); block.add_child(why)
		found = true
	if not found: rows.add_child(UiKit.label("No opposite-sex adult shares this roost.", "Muted", true))
	var cancel := UiKit.button("Cancel", _close_mate_list, "Row", 100); cancel.name = "DragonMateCancel"; modal.add_child(cancel)
	_mate_list = modal

func _close_mate_list() -> void:
	if _mate_list == null or not is_instance_valid(_mate_list):
		_mate_list = null
		return
	var modal := _mate_list
	_mate_list = null
	UiKit.close_modal(modal)

func _pick_mate(mother_uid: String, father_uid: String) -> void:
	_close_mate_list()
	var preview: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	if not bool(preview.get("ok", false)):
		notice = String(preview.get("reason", "This pair cannot breed."))
		_queue_refresh()
		return
	_show_pair_confirm(mother_uid, father_uid, preview)

func _clutch_estimate_text(preview: Dictionary) -> String:
	return "Clutch estimate: %d (between %d and %d), within %d days." % [int(preview.get("clutch_estimate", 0)), int(preview.get("clutch_min", 1)), int(preview.get("clutch_max", 1)), int(preview.get("lay_days", 0))]

func _traits_preview_text(preview: Dictionary) -> String:
	var traits: Dictionary = preview.get("traits_preview", {})
	var gem_names: Array[String] = []
	for gem_id in traits.get("possible_gems", []):
		gem_names.append(_catalog_name("gems", String(gem_id)))
	var morph_names: Array[String] = []
	for morph_id in traits.get("possible_morphs", []):
		morph_names.append(_catalog_name("morphs", String(morph_id)))
	var gems := "unknown"
	if not gem_names.is_empty():
		gems = " or ".join(gem_names)
	var forms := "unknown"
	if not morph_names.is_empty():
		forms = " or ".join(morph_names)
	var rare := int(round(float(traits.get("rare_gem_chance", 0.0)) * 100.0))
	var lines: Array[String] = ["Traits preview: gems %s; body forms %s; rare gem chance %d%%." % [gems, forms, rare]]
	var avg: Dictionary = traits.get("variation_average", {})
	var bits: Array[String] = []
	for channel in DragonBreeding.VARIATION_CHANNELS:
		var key := String(channel)
		if avg.has(key):
			bits.append("%s %.2f" % [key.replace("_", " "), float(avg[key])])
	if not bits.is_empty():
		lines.append("Variation averages: " + ", ".join(bits) + ".")
	return "\n".join(lines)

func _show_pair_confirm(mother_uid: String, father_uid: String, preview: Dictionary) -> void:
	var modal := UiKit.modal(self, "Confirm breeding pair", 680); modal.name = "DragonPairReview"
	var clutch := UiKit.label(_clutch_estimate_text(preview), "", true); clutch.name = "DragonClutchEstimate"; modal.add_child(clutch)
	var traits := UiKit.label(_traits_preview_text(preview), "", true); traits.name = "DragonTraitsPreview"; modal.add_child(traits)
	var footer := UiKit.hbox(8); modal.add_child(footer)
	var cancel := UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row", 100); cancel.name = "DragonPairCancel"; footer.add_child(cancel)
	footer.add_child(UiKit.spacer())
	var confirm := UiKit.button("Confirm", func(): UiKit.close_modal(modal); _apply_pair(mother_uid, father_uid, preview), "", 140)
	confirm.name = "DragonPairConfirm"; footer.add_child(confirm)

func _apply_pair(mother_uid: String, father_uid: String, review: Dictionary) -> void:
	var result: Dictionary = DragonBreeding.pair(Game, mother_uid, father_uid, review)
	notice = String(result.get("message", result.get("reason", "")))
	if bool(result.get("ok", false)):
		Game.changed.emit()
		Game.save_game_async()
	_queue_refresh()

func _request_combat(uid: String, enabled: bool) -> void:
	var review: Dictionary = DragonCombat.participation_preview(Game,uid,enabled)
	if not bool(review.get("ok",false)): notice = String(review.get("reason","Order unavailable.")); _queue_refresh(); return
	var row: Dictionary = Dragons.get_record(Game,uid)
	var modal := UiKit.modal(self,"Review settlement defence",680); modal.name = "DragonCombatReview"
	var text: String = "Order %s to defend %s? It may join automatic battles while eligible here. The rider bond, owner and keeper stay unchanged." % [row.get("name","this dragon"),_town_name(String(row.get("location_town_id","")))] if enabled else "Withdraw %s from settlement defence? Its rider bond, owner and keeper stay unchanged." % row.get("name","this dragon")
	modal.add_child(UiKit.label(text,"",true))
	var footer := UiKit.hbox(8); modal.add_child(footer)
	var cancel := UiKit.button("Cancel",func(): UiKit.close_modal(modal),"Row",100); cancel.name = "DragonCombatCancel"; footer.add_child(cancel)
	footer.add_child(UiKit.spacer())
	var confirm := UiKit.button("Defend settlement" if enabled else "Withdraw",func(): UiKit.close_modal(modal); _apply_combat(uid,enabled,review),"",140)
	confirm.name = "DragonCombatConfirm"; footer.add_child(confirm)

func _apply_combat(uid: String, enabled: bool, review: Dictionary) -> Dictionary:
	var result: Dictionary = DragonCombat.participation_order(Game,uid,enabled,review)
	notice = String(result.get("reason",result.get("message","")))
	if bool(result.get("ok",false)): Game.changed.emit(); Game.save_game_async()
	_queue_refresh()
	return result

func _bond_panel(row: Dictionary) -> void:
	var uid: String = String(row["id"])
	var status: Dictionary = DragonBond.status(Game,uid)
	var panel := UiKit.panel("Card"); panel.name = "DragonBondPanel"; body.add_child(panel)
	var facts := UiKit.vbox(6); facts.size_flags_horizontal = SIZE_EXPAND_FILL; panel.add_child(facts)
	var identity := UiKit.hbox(10); facts.add_child(identity)
	var rider: Dictionary = status.get("rider",{})
	if not rider.is_empty():
		var portrait := Portrait.new(); portrait.name = "BondedPersonPortrait"; portrait.custom_minimum_size = Vector2(72,80)
		portrait.set_spec(Dynasty.portrait_for(Game,rider)); identity.add_child(portrait)
	var words := UiKit.vbox(3); words.size_flags_horizontal = SIZE_EXPAND_FILL; identity.add_child(words)
	var label := UiKit.label(bond_status_text(status),"",true); label.name = "DragonRiderStatus"; words.add_child(label)
	words.add_child(UiKit.label("Owner: %s · Custodian: %s · Location: %s" % [_person_name(String(row.get("owner_person_uid",""))),_person_name(String(row.get("custodian_person_uid",""))),_town_name(String(row.get("location_town_id","")))],"Small",true))
	var reason: String = String(status.get("reason",""))
	if reason != "":
		label = UiKit.label(reason,"Muted",true); label.name = "DragonBondReason"; words.add_child(label)
	var controls := UiKit.flow(); facts.add_child(controls)
	var bind_button := UiKit.button("Choose rider",_open_bond_picker.bind(uid),"Row"); bind_button.name = "DragonBindRider"
	bind_button.disabled = not bool(status.get("can_bind",false)); bind_button.tooltip_text = reason; controls.add_child(bind_button)
	var release_button := UiKit.button("Release bond",_request_bond.bind(uid,"release",""),"Row"); release_button.name = "DragonReleaseBond"
	release_button.disabled = not bool(status.get("can_release",false)); release_button.tooltip_text = String(status.get("release_reason","")); controls.add_child(release_button)
	if not rider.is_empty(): controls.add_child(UiKit.button("Rider's person record",_person_record.bind(String(rider["person_uid"])),"Row"))

func _open_bond_picker(uid: String) -> void:
	var status: Dictionary = DragonBond.status(Game,uid)
	if not bool(status.get("can_bind",false)): notice = String(status.get("reason","Binding unavailable.")); _queue_refresh(); return
	var modal := UiKit.modal(self,"Choose a rider",700); modal.name = "BondPickerContent"; modal.add_theme_constant_override("separation",6)
	modal.add_child(UiKit.label("Choose a living adult present here. Review before binding.","Small",true))
	var search := LineEdit.new(); search.name = "BondPersonSearch"; search.placeholder_text = "Search name, household or settlement"; search.custom_minimum_size.y = 48; modal.add_child(search)
	var count := UiKit.label("","Small",true); count.name = "BondCandidateCount"; modal.add_child(count)
	var scroll := UiKit.scroll(); scroll.name = "BondCandidatesScroll"; scroll.custom_minimum_size.y = 180; modal.add_child(scroll)
	var rows := UiKit.vbox(4); rows.name = "BondCandidates"; rows.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(rows)
	var selected := UiKit.panel("Inset"); modal.add_child(selected)
	var selected_row := UiKit.hbox(8); selected.add_child(selected_row)
	var portrait := Portrait.new(); portrait.name = "BondCandidatePortrait"; portrait.custom_minimum_size = Vector2(72,72); portrait.visible = false; selected_row.add_child(portrait)
	var description := UiKit.label("Choose a person to review.","Small",true); description.name = "BondCandidateDescription"; selected_row.add_child(description)
	var paging := UiKit.hbox(6); modal.add_child(paging)
	var previous := UiKit.button("Previous",_turn_bond_page.bind(-1),"Row",92); previous.name = "BondCandidatesPrevious"; paging.add_child(previous)
	var page := UiKit.label("","Small",true); page.name = "BondCandidatePage"; UiKit.expand(page); paging.add_child(page)
	var next := UiKit.button("Next page",_turn_bond_page.bind(1),"Row",92); next.name = "BondCandidatesNext"; paging.add_child(next)
	var footer := UiKit.hbox(8); modal.add_child(footer)
	footer.add_child(UiKit.button("Cancel",_close_bond_picker,"Row",100)); footer.get_child(0).name = "BondPickerCancel"
	footer.add_child(UiKit.spacer())
	var review_button := UiKit.button("Review bond",_review_bond_candidate,"",132); review_button.name = "BondReviewPerson"; review_button.disabled = true; footer.add_child(review_button)
	_bond_picker = {"uid":uid,"modal":modal,"search":search,"rows":rows,"count":count,"portrait":portrait,"description":description,
		"previous":previous,"next":next,"page_label":page,"page":0,"people":DragonBond.candidates(Game,uid),"matched":[],"review":{},"review_button":review_button}
	search.text_changed.connect(func(_value):
		_bond_picker["page"] = 0; _bond_picker["review"] = {}
		portrait.visible = false; description.text = "Choose a person to review."; review_button.disabled = true
		_fill_bond_picker())
	_fill_bond_picker()

func _fill_bond_picker() -> void:
	if _bond_picker.is_empty(): return
	var rows: VBoxContainer = _bond_picker["rows"]; UiKit.clear(rows)
	var term: String = (_bond_picker["search"] as LineEdit).text.strip_edges().to_lower()
	var matched: Array = (_bond_picker["people"] as Array).filter(func(person): return term == "" or ("%s %s %s" % [person.get("name",""),person.get("family_name",""),person.get("town_name","")]).to_lower().contains(term))
	_bond_picker["matched"] = matched
	var pages: int = maxi(1,ceili(float(matched.size())/BOND_PAGE_SIZE))
	var page: int = clampi(int(_bond_picker["page"]),0,pages-1); _bond_picker["page"] = page
	(_bond_picker["count"] as Label).text = "%d eligible people · %s" % [matched.size(),_town_name(String(Dragons.get_record(Game,String(_bond_picker["uid"])).get("location_town_id","")))]
	(_bond_picker["page_label"] as Label).text = "Page %d / %d" % [page+1,pages]
	(_bond_picker["previous"] as Button).disabled = page == 0; (_bond_picker["next"] as Button).disabled = page+1 >= pages
	for person: Dictionary in matched.slice(page*BOND_PAGE_SIZE,(page+1)*BOND_PAGE_SIZE):
		var button: Button = RecKit.row(String(person["name"]),"", "%s · %s · Age %d" % [person.get("family_name",""),person.get("town_name",""),int(person.get("age",0))],_pick_bond_candidate.bind(String(person["person_uid"])))
		button.name = "BondCandidate"; button.set_meta("bond_person_uid",person["person_uid"]); rows.add_child(button)
	if matched.is_empty(): rows.add_child(UiKit.label("No eligible person matches this search.","Muted",true))

func _turn_bond_page(delta: int) -> void:
	if _bond_picker.is_empty(): return
	_bond_picker["page"] = int(_bond_picker["page"])+delta; _fill_bond_picker()

func _pick_bond_candidate(person_uid: String) -> void:
	if _bond_picker.is_empty(): return
	var uid: String = String(_bond_picker["uid"])
	var review: Dictionary = DragonBond.bind_preview(Game,uid,person_uid)
	_bond_picker["review"] = review
	var person: Dictionary = review.get("recipient",{})
	if person.is_empty(): person = Dynasty.person(Game,person_uid)
	var portrait: Portrait = _bond_picker["portrait"]
	portrait.visible = not person.is_empty()
	if portrait.visible: portrait.set_spec(Dynasty.portrait_for(Game,person))
	(_bond_picker["description"] as Label).text = "Selected: %s · Age %d\n%s · %s\n%s" % [person.get("name","Unavailable person"),int(person.get("age",0)),person.get("family_name",""),person.get("town_name",""),"Eligible · Review this bond." if bool(review.get("ok",false)) else String(review.get("reason",""))]
	(_bond_picker["review_button"] as Button).disabled = not bool(review.get("ok",false))

func _close_bond_picker() -> void:
	if _bond_picker.is_empty(): return
	var modal: Node = _bond_picker["modal"]; _bond_picker = {}; UiKit.close_modal(modal)

func _review_bond_candidate() -> void:
	if _bond_picker.is_empty() or not bool(_bond_picker.get("review",{}).get("ok",false)): return
	var uid: String = String(_bond_picker["uid"]); var review: Dictionary = _bond_picker["review"]
	_close_bond_picker(); _show_bond_review(uid,"bind",String(review.get("recipient_person_uid","")),review)

func _request_bond(uid: String, action: String, person_uid: String) -> void:
	var review: Dictionary = DragonBond.release_preview(Game,uid) if action == "release" else DragonBond.bind_preview(Game,uid,person_uid)
	if not bool(review.get("ok",false)): notice = String(review.get("reason","Bond order unavailable.")); _queue_refresh(); return
	_show_bond_review(uid,action,person_uid,review)

static func bond_review_text(action: String, review: Dictionary) -> String:
	var source: Dictionary = review.get("source",{})
	var person: Dictionary = review.get("recipient",{})
	var name: String = String(person.get("name",_person_name(String(source.get("rider_person_uid","")))))
	var order: String = "Release %s's bond with %s?" % [source.get("name","this dragon"),name] if action == "release" else "Bind %s with %s · %s · %s?" % [source.get("name","this dragon"),name,person.get("family_name",""),person.get("town_name","")]
	return order+"\nOne active bond per person and dragon.\nOwner remains %s. Custodian remains %s. Location remains %s." % [_person_name(String(source.get("owner_person_uid",""))),_person_name(String(source.get("custodian_person_uid",""))),_town_name(String(source.get("location_town_id","")))]

func _show_bond_review(uid: String, action: String, person_uid: String, review: Dictionary) -> void:
	var modal := UiKit.modal(self,"Review rider bond",680); modal.name = "BondReviewContent"
	modal.add_child(UiKit.label(bond_review_text(action,review),"",true))
	var footer := UiKit.hbox(8); modal.add_child(footer)
	var cancel := UiKit.button("Cancel",func(): UiKit.close_modal(modal),"Row",100); cancel.name = "BondReviewCancel"; footer.add_child(cancel)
	footer.add_child(UiKit.spacer())
	var confirm := UiKit.button("Release bond" if action == "release" else "Bind rider",func(): UiKit.close_modal(modal); _apply_bond(uid,action,person_uid,review),"",132)
	confirm.name = "BondConfirmRelease" if action == "release" else "BondConfirmBind"; footer.add_child(confirm)

func _apply_bond(uid: String, action: String, person_uid: String, review: Dictionary) -> Dictionary:
	var result: Dictionary = DragonBond.release(Game,uid,review) if action == "release" else DragonBond.bind(Game,uid,person_uid,review)
	notice = String(result.get("reason",result.get("message","")))
	if bool(result.get("ok",false)): Game.changed.emit(); Game.save_game_async()
	_queue_refresh()
	return result

func _update_model() -> void:
	if model_card != null:
		model_card.set_preview(model_pose, model_state, model_rider, model_zoom, model_play)

func _model_controls(row: Dictionary) -> void:
	model_card.custom_minimum_size.y = 340
	body.add_child(UiKit.label("Model preview", "H2", true))
	var controls: HFlowContainer = UiKit.flow()
	body.add_child(controls)
	controls.add_child(UiKit.button("Full dragon", func(): model_card.set_mode("model"); _update_model(), "Row"))
	controls.add_child(UiKit.button("Head portrait", func(): model_card.set_mode("portrait"); _update_model(), "Row"))
	if DragonConcepts.matches(row):
		controls.add_child(UiKit.button("Type portrait", func(): model_card.set_mode("concept"), "Row"))
	var poses: Array[String] = ["idle", "prepare", "strike", "recover", "hit", "prone"]
	var pose_picker: OptionButton = OptionButton.new()
	for name: String in ["Idle", "Wind-up", "Bite", "Recovery", "Recoil", "Fallen"]: pose_picker.add_item(name)
	pose_picker.custom_minimum_size = Vector2(132, 42)
	pose_picker.item_selected.connect(func(index: int): model_pose = poses[index]; model_card.set_mode("model"); _update_model())
	controls.add_child(pose_picker)
	var play: Button = UiKit.button("Play", func(): pass, "Row", 78)
	play.pressed.connect(func(): model_play = not model_play; play.text = "Pause" if model_play else "Play"; model_card.set_mode("model"); _update_model())
	controls.add_child(play)
	var damage: OptionButton = OptionButton.new()
	for name: String in ["Healthy", "Bloody", "Mangled wing", "Mangled hind leg", "Head separated", "Tooth / claw chips"]: damage.add_item(name)
	damage.custom_minimum_size = Vector2(148, 42)
	var examples: Array[Dictionary] = [{}, {"dmg":{"torso":0.7,"wing_upper_r":0.8,"leg_lower_r":0.7},"wk":{"torso":"c","wing_upper_r":"m","leg_lower_r":"c"},"bleed":{"torso":true,"wing_upper_r":true,"leg_lower_r":true},"blood":0.9}, {"lost":["wing_upper_r"],"blood":0.9}, {"lost":["leg_upper_r"],"blood":0.9}, {"lost":["head"],"blood":0.9}, {"dmg":{"jaw":0.6,"foot_r":0.6},"wk":{"jaw":"c","foot_r":"c"},"bleed":{"jaw":true,"foot_r":true},"blood":0.7,"fragments":[{"region_id":"jaw","kind":"tooth","count":3},{"region_id":"foot_r","kind":"claw","count":2}]}]
	damage.item_selected.connect(func(index: int):
		model_state = examples[index].duplicate(true)
		if index == 5: model_play = true; play.text = "Pause"
		model_card.set_mode("model"); _update_model())
	controls.add_child(damage)
	body.add_child(UiKit.label("Preview artwork: movement and sample injuries. This preview does not change health or rider bonds.", "Muted", true))
	_update_model()

static func _history_text(event: Dictionary) -> String:
	match String(event.get("kind", "")):
		"registered": return "Registered as %s · Owner: %s" % [String(event.get("stage", "holding")), _person_name(String(event.get("owner_person_uid", "")))]
		"gifted": return "Ownership given to " + _person_name(String(event.get("owner_person_uid", "")))
		"custodian_assigned": return "Custodian appointed: " + _person_name(String(event.get("custodian_person_uid", "")))
		"custodian_died": return "Custodian died: " + _person_name(String(event.get("prior_custodian_person_uid", "")))
		"custodian_unavailable": return "Custodian left local care: " + _person_name(String(event.get("prior_custodian_person_uid", "")))
		"owner_refs": return "Owner's household record updated."
		"inherited": return "Inherited by " + _person_name(String(event.get("owner_person_uid", "")))
		"unclaimed": return "Inheritance remains unclaimed."
		"bonded": return "Rider bonded: "+_person_name(String(event.get("rider_person_uid","")))
		"bond_released": return "Rider bond released: "+_person_name(String(event.get("prior_rider_person_uid","")))
		"bond_ended": return "Rider bond ended: %s · %s" % [_person_name(String(event.get("prior_rider_person_uid",""))),String(event.get("reason","")).replace("_"," ").capitalize()]
		_: return String(event.get("text", event.get("message", String(event.get("kind", "Holding recorded")).replace("_", " ").capitalize())))

func _catalog() -> void:
	body.add_child(UiKit.label("Gem types & eggs", "H2", true))
	var grid := GridContainer.new()
	gem_grid = grid
	grid.columns = maxi(1, mini(4, int(maxf(1, get_viewport_rect().size.x - 32) / 250)))
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for gem: Dictionary in Dragons.catalogs().get("gems", []):
		var panel := UiKit.panel("Card"); panel.size_flags_horizontal = SIZE_EXPAND_FILL; grid.add_child(panel)
		var words := UiKit.vbox(4); panel.add_child(words)
		var image := DragonCard.new(); image.custom_minimum_size = Vector2(0, 140)
		image.set_record({"stage": "egg", "gem_id": gem["id"], "appearance_seed": 0})
		words.add_child(image)
		var example: Dictionary = DragonConcepts.entry(String(gem["id"]))
		var portrait: DragonCard = DragonCard.new(); portrait.custom_minimum_size = Vector2(0, 170)
		portrait.mode = "concept"
		portrait.set_record({"stage":"adult","gem_id":gem["id"],"morph_id":example["morph_id"],"size_class":"medium"})
		words.add_child(portrait)
		words.add_child(UiKit.label(String(gem["name"]) + " Dragon\n" + String(gem["name"]) + " Egg", "", true))
		words.add_child(UiKit.label(String(example["morph_name"]) + " type portrait", "Muted", true))
	body.add_child(UiKit.label("Body forms", "H2", true))
	for morph: Dictionary in Dragons.catalogs().get("morphs", []):
		var words := UiKit.vbox(4); body.add_child(words)
		var image := DragonCard.new(); image.custom_minimum_size = Vector2(0, 150)
		image.set_record({"stage": "adult", "gem_id": "emerald", "morph_id": morph["id"], "appearance_seed": 0})
		words.add_child(image)
		words.add_child(UiKit.label("%s · %s\n%s" % [morph["name"], morph.get("build", ""), morph.get("description", "")], "", true))
	var size_names: Array[String] = []
	for entry: Dictionary in Dragons.catalogs().get("sizes", []): size_names.append(String(entry["name"]))
	body.add_child(UiKit.label("Sizes: " + ", ".join(size_names), "Muted", true))

func _preview(uid: String, action: String, recipient_uid: String) -> Dictionary:
	return Dragons.transfer_preview(Game, uid, recipient_uid) if action == "transfer" else Dragons.set_custodian_preview(Game, uid, recipient_uid)

func _choose_person(uid: String, action: String) -> void:
	var modal := UiKit.modal(self, "Gift ownership" if action == "transfer" else "Choose custodian", 680)
	var search := LineEdit.new()
	search.placeholder_text = "Search name, family or city"
	search.custom_minimum_size.y = 48
	modal.add_child(search)
	var count := UiKit.label("", "Muted", true)
	modal.add_child(count)
	var scroll := UiKit.scroll(); scroll.custom_minimum_size.y = 360; modal.add_child(scroll)
	var choices := UiKit.vbox(6); choices.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(choices)
	var people: Array = Dragons.people(Game)
	search.text_changed.connect(func(value): _fill_people(choices, count, modal, people, uid, action, String(value)))
	_fill_people(choices, count, modal, people, uid, action, "")
	modal.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row"))

func _fill_people(choices: VBoxContainer, count: Label, modal: Node, people: Array, uid: String, action: String, query: String) -> void:
	UiKit.clear(choices)
	var source: Dictionary = Dragons.get_record(Game, uid)
	var matched := []
	var term := query.strip_edges().to_lower()
	for person: Dictionary in people:
		if action == "transfer" and String(person.get("person_uid", "")) == String(source.get("owner_person_uid", "")): continue
		if action == "set_custodian":
			if String(person.get("town_id", "")) != String(source.get("location_town_id", "")) or not String(person.get("state", "")) in ["", "hire", "reserve"]: continue
			if String(person.get("person_uid", "")) == String(source.get("custodian_person_uid", "")): continue
		var text := "%s %s %s" % [person.get("name", ""), person.get("family_name", ""), person.get("town_name", "")]
		if term != "" and not text.to_lower().contains(term): continue
		matched.append(person)
	count.text = "%d people match · Showing %d" % [matched.size(), mini(40, matched.size())]
	if matched.size() > 40: count.text += ". Search to narrow the list."
	if action == "set_custodian": count.text += " · Present in " + _town_name(String(source.get("location_town_id", "")))
	for person: Dictionary in matched.slice(0, 40):
		var words := UiKit.vbox(3); choices.add_child(words)
		words.add_child(UiKit.label("%s · %s · %s" % [person.get("name", ""), person.get("family_name", ""), person.get("town_name", "")], "", true))
		words.add_child(UiKit.button("Review person", _review_person.bind(modal, uid, action, String(person["person_uid"])), "Row"))
	if matched.is_empty(): choices.add_child(UiKit.label("No matching living person here." if action == "set_custodian" else "No matching living recipient.", "Muted", true))

func _review_person(modal: Node, uid: String, action: String, person_uid: String) -> void:
	UiKit.close_modal(modal)
	_request_action(uid, action, person_uid)

static func review_text(action: String, review: Dictionary) -> String:
	var source: Dictionary = review.get("source", {})
	var recipient: Dictionary = review.get("recipient", {})
	var person := "%s · %s · %s" % [recipient.get("name", ""), recipient.get("family_name", ""), recipient.get("town_name", "")]
	if action == "transfer":
		return "Gift %s from %s's household (%s) to %s?\nCustodian remains %s. Location remains %s." % [source.get("name", "this holding"), _person_name(String(source.get("owner_person_uid", ""))), _household_name(String(source.get("owner_household_uid", ""))), person, _person_name(String(source.get("custodian_person_uid", ""))), _town_name(String(source.get("location_town_id", "")))]
	return "Put %s in the care of %s?\nOwner remains %s. Location remains %s." % [source.get("name", "this holding"), person, _person_name(String(source.get("owner_person_uid", ""))), _town_name(String(source.get("location_town_id", "")))]

func _request_action(uid: String, action: String, recipient_uid: String) -> void:
	var review := _preview(uid, action, recipient_uid)
	if not bool(review.get("ok", false)):
		notice = String(review.get("reason", "Order unavailable.")); _refresh(); return
	UiKit.confirm(self, review_text(action, review), "Confirm", _apply_action.bind(uid, action, recipient_uid, review))

func _apply_action(uid: String, action: String, recipient_uid: String, review: Dictionary) -> Dictionary:
	var result: Dictionary = Dragons.transfer(Game, uid, recipient_uid, review) if action == "transfer" else Dragons.set_custodian(Game, uid, recipient_uid, review)
	if bool(result.get("ok", false)):
		Game.changed.emit()
		Game.save_game_async()
	notice = String(result.get("reason", result.get("message", ""))); _refresh()
	return result

func _person_record(uid: String) -> void:
	var person: Dictionary = Dynasty.person(Game, uid)
	if person.is_empty(): return
	Game.goto("res://ui/records.tscn", {"view": "town", "id": person.get("town_id", ""), "tab":"Register","person_uid":uid,"family_id":person.get("family_id",-1),"pid":person.get("pid",-1),"back": "dragons", "back_params": _context()})

func _back() -> void:
	Game.goto(back, back_params)
