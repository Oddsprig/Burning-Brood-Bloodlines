extends Control
## Read-only results. Native settlement, loot and growth have already run.
const PAGE_SIZE := 18
const SECTIONS := ["fallen", "wounded", "lessons", "loot", "log"]
var result: Dictionary = {}
var summary: Dictionary = {}
var sections: Dictionary = {}
var active_section: String = ""
var frame: VBoxContainer
var body_scroll: ScrollContainer
var continue_button: Button
var receipt_rows_formatted: int = 0

func _ready() -> void:
	var started: int = Time.get_ticks_usec()
	Perf.set_stage("Battle results")
	theme = UiTheme.get_theme()
	result = Game.last_result
	var history: Variant = result.get("combat_journal")
	Perf.record_combat_history(history.call("stats") if history is RefCounted and history.has_method("stats") else {})
	var summary_start: int = Time.get_ticks_usec()
	summary = BattleResultSummary.build(result)
	Perf.record_us("Battle result summary", Time.get_ticks_usec() - summary_start)
	var bg := ColorRect.new()
	bg.color = UiTheme.WOOD
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	frame = UiKit.vbox(8)
	frame.name = "ResultsFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	body_scroll = UiKit.scroll()
	body_scroll.name = "ResultsScroll"
	frame.add_child(body_scroll)
	var content := UiKit.vbox(10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(content)
	var assault: Dictionary = result.get("assault_outcome", {})
	if not assault.is_empty():
		var banner := UiKit.panel("Card")
		var line := UiKit.label(str(assault.get("text", "")), "H2", true)
		line.add_theme_font_size_override("font_size", 22)
		line.add_theme_color_override("font_color", UiTheme.GOOD if bool(assault.get("won", false)) else UiTheme.WARN)
		banner.add_child(line)
		content.add_child(banner)
	_build_overview(content)
	var tabs := GridContainer.new()
	tabs.name = "ResultDetailTabs"; tabs.columns = 2
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	content.add_child(tabs)
	for key: String in SECTIONS: _build_section(content, key, tabs)
	continue_button = UiKit.button("Continue", func(): Game.goto("map"), "", 180)
	continue_button.name = "ResultsContinue"
	continue_button.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 22)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(continue_button)
	resized.connect(_layout)
	_layout()
	Perf.record_us("Battle result interface", Time.get_ticks_usec() - started)

func _layout() -> void:
	if frame == null: return
	var safe := UiKit.safe_area_margins(get_viewport())
	frame.offset_left = 24 + int(safe["left"])
	frame.offset_top = 16 + int(safe["top"])
	frame.offset_bottom = -(16 + int(safe["bottom"]))
	frame.offset_right = -(24 + int(safe["right"]) + UiKit.diagnostics_lane(get_viewport_rect().size.x))

func _build_overview(parent: Control) -> void:
	var card := UiKit.panel("Card")
	card.name = "OutcomeCard"
	parent.add_child(card)
	var box := UiKit.vbox(6)
	card.add_child(box)
	var winner: int = int(result.get("winner", -1))
	var title := UiKit.label("Victory" if winner == 0 else ("Defeat" if winner == 1 else "The field is undecided"), "Title", true)
	title.name = "ResultsOutcome"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiTheme.GOOD if winner == 0 else (UiTheme.BAD if winner == 1 else UiTheme.BRASS))
	box.add_child(title)
	var loot := UiKit.label("Loot: %s coins · Kept: %d items · Returned gear: %d pieces · Army wallet: %s coins" % [UiKit.thousands(int(result.get("loot_gold", 0))), (result.get("loot_items", []) as Array).size(), int(result.get("fallen_gear", 0)), UiKit.thousands(Game.gold)], "", true)
	loot.name = "ResultsLootTotal"
	loot.add_theme_font_size_override("font_size", 18)
	box.add_child(loot)
	var supplies: Dictionary = result.get("supplies_taken", {})
	var supply_label := UiKit.label("Supplies taken: " + (Supplies.text(supplies) if not supplies.is_empty() else "none"), "Muted", true)
	supply_label.name = "ResultsSupplies"
	supply_label.add_theme_font_size_override("font_size", 17)
	box.add_child(supply_label)
	var table := GridContainer.new()
	table.name = "BothSideTotals"
	table.columns = 6
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 14)
	table.add_theme_constant_override("v_separation", 6)
	var table_scroll := ScrollContainer.new()
	table_scroll.name = "TotalsScroll"
	table_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	table_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(table_scroll)
	table_scroll.add_child(table)
	for heading: String in ["Side", "Slain", "Seriously\nwounded", "Other\nwounded", "Unhurt", "Retreated*"]:
		var head := UiKit.label(heading, "Muted", true)
		head.add_theme_font_size_override("font_size", 17)
		head.custom_minimum_size.x = 245 if heading == "Side" else 85
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.add_child(head)
	var officers: Array[String] = []
	for index: int in (summary.get("sides", []) as Array).size():
		var side: Dictionary = summary["sides"][index]
		var name_label := UiKit.label("%s (%d)" % [side["name"], int(side["total"])], "", true)
		name_label.name = "Side%dName" % index
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.custom_minimum_size.x = 245
		table.add_child(name_label)
		for key: String in ["slain", "seriously_wounded", "other_wounded", "unhurt", "fled"]:
			var metric := UiKit.label(str(int(side.get(key, 0))))
			metric.name = "Side%d_%s" % [index, key]
			metric.add_theme_font_size_override("font_size", 20)
			metric.add_theme_color_override("font_color", UiTheme.BAD if key == "slain" else UiTheme.INK)
			table.add_child(metric)
		var losses: Array[String] = []
		for row: Dictionary in side.get("rows", {}).get("fallen", []):
			if bool(row.get("officer", false)) and losses.size() < 3: losses.append(String(row["name"]))
		var officer_count: int = int(side.get("officers_slain", 0))
		if officer_count > 0:
			officers.append("%s: %s%s" % [side["name"], ", ".join(losses), " (+%d more)" % (officer_count - losses.size()) if officer_count > losses.size() else ""])
	var overlap := UiKit.label("*Retreated counts living survivors and overlaps their wound/unhurt totals.", "Small", true)
	overlap.name = "RetreatOverlap"
	box.add_child(overlap)
	var important := UiKit.label("Officers slain: " + (" · ".join(officers) if not officers.is_empty() else "none"), "", true)
	important.name = "ResultsOfficerLosses"
	important.add_theme_font_size_override("font_size", 17)
	important.add_theme_color_override("font_color", UiTheme.BRASS)
	box.add_child(important)
	for rider: Dictionary in result.get("rider_outcomes", []):
		var danger := UiKit.label(str(rider["text"]), "", true)
		danger.name = "RiderDanger%d" % box.get_child_count()
		danger.add_theme_color_override("font_color", UiTheme.BAD if str(rider["outcome"]) == "killed" else UiTheme.BRASS)
		box.add_child(danger)
	# v0.033: men downed on a field the other side holds are taken (BattleRounds); bargain for them at Court.
	var taken: Array = result.get("captured", result.get("battle_summary", {}).get("captured", []))
	if taken.size() == 2 and int(taken[0]) + int(taken[1]) > 0:
		var prisoners := UiKit.label("Taken prisoner: %d of yours · %d of theirs. Ransom or exchange them at Court." % [int(taken[0]), int(taken[1])], "", true)
		prisoners.name = "ResultsPrisoners"
		prisoners.add_theme_font_size_override("font_size", 17)
		prisoners.add_theme_color_override("font_color", UiTheme.BRASS)
		box.add_child(prisoners)

func _build_section(parent: Control, key: String, tabs: Control) -> void:
	var box := UiKit.vbox(6)
	box.name = key.capitalize() + "Section"
	box.visible = false
	parent.add_child(box)
	var title: String = {"fallen": "Fallen", "wounded": "Wounded · status & recovery", "lessons": "Lessons learned", "loot": "Loot & supplies", "log": "Combat log"}[key]
	var toggle := UiKit.button(title + "  ▶", func(): toggle_section(key), "Tab", 0)
	toggle.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 20)
	toggle.custom_minimum_size.y = UiKit.touch_min(48)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle.name = key.capitalize() + "Toggle"
	tabs.add_child(toggle)
	var detail := UiKit.panel("Inset")
	detail.name = key.capitalize() + "Details"
	detail.visible = false
	box.add_child(detail)
	sections[key] = {"title": title, "toggle": toggle, "detail": detail, "holder": box, "source": [], "page": 0, "open": false}

func toggle_section(key: String) -> void:
	var started: int = Time.get_ticks_usec()
	if not sections.has(key): return
	if active_section == key:
		_close_section(key)
		active_section = ""
		return
	if active_section != "": _close_section(active_section)
	active_section = key
	var section: Dictionary = sections[key]
	section["source"] = _detail_source(key) if key != "log" else []
	section["page"] = 0; section["open"] = true
	(section["toggle"] as Button).text = String(section["title"]) + "  ▼"
	(section["detail"] as Control).visible = true
	(section["holder"] as Control).visible = true
	if key == "log":
		UiKit.clear(section["detail"])
		var browser := CombatLogBrowser.new()
		browser.name = "ResultCombatLog"
		var journal: Variant = result.get("combat_journal")
		browser.begin(journal if journal is RefCounted else null, result.get("side_names", []))
		(section["detail"] as Node).add_child(browser)
	else: _build_page(key)
	call_deferred("_focus_section", key)
	Perf.record_us("Battle result detail", Time.get_ticks_usec() - started)

func _focus_section(key: String) -> void:
	if active_section != key or not is_inside_tree(): return
	# Deferred label/container sorting can still be pending after building a page.
	# Measure its actual detail position only after those native layout passes.
	var tree: SceneTree = get_tree()
	for _pass in 2:
		await tree.process_frame
		if active_section != key or not is_inside_tree(): return
	var target: Control = sections[key]["detail"]
	body_scroll.scroll_vertical += int(floor(target.get_global_rect().position.y - body_scroll.get_global_rect().position.y)) - 4

func _close_section(key: String) -> void:
	var section: Dictionary = sections[key]
	UiKit.clear(section["detail"])
	(section["detail"] as Control).visible = false
	(section["holder"] as Control).visible = false
	(section["toggle"] as Button).text = String(section["title"]) + "  ▶"
	section["source"] = []; section["page"] = 0; section["open"] = false
	if key == "loot": receipt_rows_formatted = 0

func turn_page(key: String, delta: int) -> void:
	var started: int = Time.get_ticks_usec()
	if active_section != key: return
	var section: Dictionary = sections[key]
	if key == "log":
		var browser: CombatLogBrowser = (section["detail"] as Node).get_node_or_null("ResultCombatLog")
		if browser != null: browser.turn_page(delta)
		return
	var count: int = (section["source"] as Array).size()
	var last_page: int = maxi(0, ceili(float(count) / PAGE_SIZE) - 1)
	section["page"] = clampi(int(section["page"]) + delta, 0, last_page)
	_build_page(key)
	call_deferred("_focus_section", key)
	Perf.record_us("Battle result detail", Time.get_ticks_usec() - started)

func _build_page(key: String) -> void:
	var section: Dictionary = sections[key]
	var detail: PanelContainer = section["detail"]
	UiKit.clear(detail)
	var box := UiKit.vbox(8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_child(box)
	if key == "loot":
		receipt_rows_formatted = 0
		_build_salvage_header(box)
	var source: Array = section["source"]
	var count: int = source.size()
	var page: int = int(section["page"])
	var pages: int = maxi(1, ceili(float(count) / PAGE_SIZE))
	var nav := UiKit.hbox(8)
	box.add_child(nav)
	var previous := UiKit.button("Previous", func(): turn_page(key, -1), "", 110)
	previous.name = key.capitalize() + "Previous"
	previous.disabled = page == 0
	nav.add_child(previous)
	var marker := UiKit.label("Page %d / %d · %d entries" % [page + 1, pages, count], "Muted", true)
	marker.name = key.capitalize() + "Page"
	nav.add_child(UiKit.expand(marker))
	var next := UiKit.button("Next", func(): turn_page(key, 1), "", 90)
	next.name = key.capitalize() + "Next"
	next.disabled = page + 1 >= pages
	nav.add_child(next)
	var rows := UiKit.vbox(8)
	rows.name = key.capitalize() + "Rows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(rows)
	if count == 0:
		rows.add_child(UiKit.label({"fallen": "No one was slain.", "wounded": "No wounds of note.", "lessons": "Nothing new was learned.", "loot": "No loot recorded."}[key], "Muted", true))
	for index: int in range(page * PAGE_SIZE, mini(count, (page + 1) * PAGE_SIZE)):
		var row: Dictionary = source[index]
		var line := UiKit.panel("Card")
		line.name = "DetailRow%d" % index
		line.set_meta("result_detail_row", true)
		rows.add_child(line)
		var text := UiKit.vbox(4)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		if key in ["fallen", "wounded"]:
			var person_text: String = "%s · %s%s" % [row["side_name"], row["name"], " · Officer" if bool(row.get("officer", false)) else ""]
			var heading := UiKit.label(person_text, "", true)
			heading.add_theme_color_override("font_color", UiTheme.BRASS if bool(row.get("officer", false)) else UiTheme.INK)
			text.add_child(heading)
			if key == "wounded":
				var status: String = str(row.get("status", "not assessed"))
				var recovery: String = str(row.get("recovery", "not assessed"))
				if status == "healthy" and bool(row.get("serious", false)):
					status = "lasting injury"
					if recovery == "healed": recovery = "open wounds healed; lasting damage remains"
				elif status == "unconscious" and recovery == "healed": recovery = "not yet assessed"
				text.add_child(UiKit.label("%s · %s · Recovery: %s%s" % [status, row.get("fitness", "not assessed"), recovery, " · Retreated" if bool(row.get("fled", false)) else ""], "Small", true))
				var notes: Array = row.get("summary", [])
				if not notes.is_empty(): text.add_child(UiKit.label(", ".join(PackedStringArray(notes.slice(0, 3))), "Muted", true))
			elif String(row.get("title", "")) != "": text.add_child(UiKit.label(String(row["title"]), "Muted", true))
		elif key == "lessons":
			text.add_child(UiKit.label(_lesson_text(row), "", true))
		elif row.has("salvage_sale"):
			var sale: Dictionary = row["salvage_sale"]
			line.set_meta("salvage_receipt_row",sale)
			line.set_meta("salvage_receipt_context",row.get("salvage_context",{}))
			receipt_rows_formatted += 1
			var words: Array[String] = _salvage_text(sale,row.get("salvage_context",{}))
			for word_index in words.size():
				var label := UiKit.label(words[word_index],"" if word_index == 0 else "Small",true)
				label.name = "SalvageHeading" if word_index == 0 else "SalvageFact%d" % word_index
				if word_index == 0: label.add_theme_color_override("font_color",UiTheme.GOOD if int(sale.get("paid",0)) > 0 else UiTheme.WARN)
				text.add_child(label)
		else:
			var item: Item = row.get("item")
			if item != null:
				var gear := UiKit.hbox(8)
				gear.add_child(UiKit.icon(ItemIcon.for_item(item), 36))
				gear.add_child(UiKit.label("%s (%s)" % [item.display_name(), Baggage.WEAR_WORDS[clampi(item.wear, 0, 3)]], "", true))
				text.add_child(gear)
			else: text.add_child(UiKit.label(String(row.get("text", "")), "", true))

func _detail_source(key: String) -> Array:
	var rows: Array = []
	if key in ["fallen", "wounded"]:
		for side: Dictionary in summary.get("sides", []):
			for original: Dictionary in side.get("rows", {}).get(key, []):
				var row: Dictionary = original.duplicate()
				row["side_name"] = side["name"]
				rows.append(row)
		return rows
	if key == "lessons":
		var units: Array = result.get("fighter_units", [])
		var player_ids: Dictionary = {}
		for unit: Unit in result.get("player_units", []): player_ids[unit.get_instance_id()] = true
		for event: Dictionary in result.get("events", []):
			if String(event.get("type", "")) != "learn": continue
			var actor: int = int(event.get("actor", -1))
			if actor >= 0 and actor < units.size() and not player_ids.has(units[actor].get_instance_id()): continue
			rows.append({"event": event})
		var growth: Dictionary = result.get("growth", {})
		for index: Variant in growth:
			var actor: int = int(index)
			if actor < 0 or actor >= units.size() or units[actor].dead or not player_ids.has(units[actor].get_instance_id()): continue
			rows.append({"unit": units[actor], "growth": growth[index]})
		return rows
	# Fields are settled receipts; opening this page never sells or transfers gear.
	var receipt: Dictionary = result.get("salvage_receipt",{})
	for transaction: Dictionary in _salvage_receipts():
		if not bool(transaction.get("finalized",false)): continue
		# Do not format unseen pieces. Their immutable receipt remains result-owned.
		for sale: Dictionary in transaction.get("rows",[]): rows.append({"salvage_sale":sale,"salvage_context":transaction})
	for pair: Array in [["loot_gold", "Total loot received"], ["loot_coin", "Coin collected"], ["scrap_gold", "Salvage payments received" if not receipt.is_empty() else "Scrap proceeds"], ["trophy_gold", "Trophy value recorded" if not receipt.is_empty() else "Trophies sold"], ["camp_loot", "Camp hoard"], ["militia_bonus", "Militia bonus"]]:
		if pair[0] == "scrap_gold" and not receipt.is_empty():
			if bool(receipt.get("finalized",false)):
				rows.append({"text":"Battle metal payment received: %s coins" % RecKit.num(float(receipt.get("scrap_paid",0)))})
				rows.append({"text":"Battle other gear payment received: %s coins" % RecKit.num(float(receipt.get("rags_paid",0)))})
			continue
		if result.has(pair[0]): rows.append({"text": "%s: %s coins" % [pair[1], UiKit.thousands(int(result[pair[0]]))]})
	if result.has("fallen_gear"): rows.append({"text": "Gear of our fallen returned: %d pieces" % int(result["fallen_gear"])})
	for item: Item in result.get("loot_items", []): rows.append({"item": item})
	for trophy: Dictionary in result.get("trophies", []): rows.append({"text": "%s · %d coins" % [trophy.get("name", "Trophy"), int(trophy.get("gold", 0))]})
	var supplies: Dictionary = result.get("supplies_taken", {})
	if not supplies.is_empty(): rows.append({"text": "Supplies taken: " + Supplies.text(supplies)})
	for pair: Array in [["scrap_kg", "Scrap recovered"], ["own_scrap_kg", "Broken company gear recovered"]]:
		for material: Variant in result.get(pair[0], {}): rows.append({"text": "%s: %.2f kg %s" % [pair[1], float(result[pair[0]][material]), material]})
	for arrow: Variant in result.get("arrows_got", {}): rows.append({"text": "Arrows recovered: %s × %d" % [arrow, int(result["arrows_got"][arrow])]})
	for pair: Array in [["camp_coin","Camp cash taken"],["camp_sale_paid","Camp market payment received"]]:
		if result.has(pair[0]): rows.append({"text":"%s: %s coins" % [pair[1],RecKit.num(float(result[pair[0]]))]})
	return rows

func _salvage_receipts() -> Array:
	# The list is authoritative; the singular key aliases its first transaction.
	var receipts: Array = result.get("salvage_receipts",[])
	if not receipts.is_empty(): return receipts
	var primary: Dictionary = result.get("salvage_receipt",{})
	return [primary] if not primary.is_empty() else []

func _build_salvage_header(parent: Control) -> void:
	var receipts: Array = _salvage_receipts()
	if receipts.is_empty(): return
	var receipt: Dictionary = receipts[0]
	var card := UiKit.panel("Card"); card.name = "SalvageBuyerSummary"; parent.add_child(card)
	var text := UiKit.vbox(4); text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.add_child(text)
	if not bool(receipt.get("finalized",false)):
		text.add_child(UiKit.label("Salvage payment not settled. No sale is claimed here.","Small",true))
		return
	var town: String = String(receipt.get("buyer_town_name",""))
	var buyer: String = String(receipt.get("buyer_business_name",""))
	var owner: String = String(receipt.get("buyer_owner_name",""))
	text.add_child(UiKit.label("Salvage receipts","H2",true))
	var label := UiKit.label("Buyer: %s · %s · Owner: %s" % [town,buyer,owner] if String(receipt.get("buyer_town_id","")) != "" else "No market buyer · unpaid pieces remain in the company stash.","Small",true)
	if receipts.size() > 1: label.text = "Battle receipt · "+label.text
	label.name = "SalvageBuyer"; text.add_child(label)
	var paid: float = 0.0; var retained: int = 0
	for transaction: Dictionary in receipts:
		if bool(transaction.get("finalized",false)): paid += float(transaction.get("paid",0)); retained += int(transaction.get("retained_items",0))
	label = UiKit.label("Payment received: %s coins · Retained: %d pieces%s" % [RecKit.num(paid),retained," · %d transactions" % receipts.size() if receipts.size() > 1 else ""],"",true)
	label.name = "SalvagePayment"; text.add_child(label)
	if receipts.size() == 1 and String(receipt.get("buyer_town_id","")) != "":
		label = UiKit.label("%s market till → Army purse · Market till: %s → %s coins" % [buyer,RecKit.num(float(receipt.get("till_before",0))),RecKit.num(float(receipt.get("till_after",0)))],"Small",true)
		label.name = "SalvagePaymentPath"; text.add_child(label)
	elif receipts.size() > 1:
		label = UiKit.label("Battle and camp payments are separate. Each piece below names its actual buyer and receiving purse.","Small",true)
		label.name = "SalvageTransactions"; text.add_child(label)
	var reason: String = String(receipt.get("reason",""))
	if reason != "":
		label = UiKit.label(("Battle salvage: " if receipts.size() > 1 else "")+reason,"Muted",true); label.name = "SalvageOutcome"; text.add_child(label)

static func _salvage_text(sale: Dictionary, receipt: Dictionary = {}) -> Array[String]:
	var paid: int = int(sale.get("paid",0))
	var retained: bool = bool(sale.get("retained",false))
	var words: Array[String] = ["%s · %s · %s" % [String(sale.get("item_name","Recorded piece")),String(sale.get("material_name",sale.get("material",""))),"Unpaid · retained" if retained else ("Paid" if paid > 0 else "No payment recorded")]]
	if not receipt.is_empty():
		var source: String = "Camp" if String(receipt.get("transaction","")) == "camp_hoard" else "Battle"
		if String(receipt.get("buyer_town_id","")) != "":
			words.append("%s buyer: %s · %s · Owner: %s" % [source,receipt.get("buyer_town_name",""),receipt.get("buyer_business_name",""),receipt.get("buyer_owner_name","")])
			words.append("Payment path: market till → %s" % String(receipt.get("recipient_name","Army purse")))
		else: words.append(source+": no market buyer · no payment")
	words.append("Quantity: %d piece · Physical mass: %.2f kg" % [int(sale.get("quantity",1)),float(sale.get("mass_kg",0))])
	var unit: String = "kg" if String(sale.get("stock_good","")).begins_with("scrap_") else "piece"
	words.append("Price: %s coins/%s · Piece quote: %s coins · Paid: %s coins" % [RecKit.num(float(sale.get("unit_price",0))),unit,RecKit.num(float(sale.get("price",0))),RecKit.num(float(paid))])
	var destination: String = String(sale.get("destination",""))
	if destination == "company_stash": words.append("Destination: company stash · This exact piece remains owned by the company.")
	elif destination == "market_stock":
		words.append("Destination: buyer's stock · Counted stock: %s %s" % [RecKit.num(float(sale.get("stock_units",0))),String(sale.get("stock_good","")).replace("_"," ")])
	elif destination == "market_inventory": words.append("Destination: buyer's inventory · %d piece" % int(sale.get("quantity",1)))
	else: words.append("Destination: not recorded")
	if sale.has("residual_kg_after") and destination == "market_stock" and not retained:
		words.append("Fractional market metal: %.2f → %.2f kg" % [float(sale.get("residual_kg_before",0)),float(sale["residual_kg_after"])])
	var reason: String = String(sale.get("reason",""))
	if reason != "": words.append(reason)
	return words

static func _lesson_text(row: Dictionary) -> String:
	if row.has("event"):
		var text: String = BattleSim.event_text(row["event"])
		return text if text != "" else "Learning recorded; no description."
	var bits: Array[String] = []
	for attribute: Variant in row.get("growth", {}): bits.append("%s +%d" % [attribute, int(row["growth"][attribute])])
	return "%s grows: %s" % [(row["unit"] as Unit).name, ", ".join(bits)]

func detail_stats() -> Dictionary:
	var counts: Dictionary = {}
	for key: String in SECTIONS:
		var section: Dictionary = sections[key]
		if key == "log":
			var browser: CombatLogBrowser = (section["detail"] as Node).get_node_or_null("ResultCombatLog")
			var log_stats: Dictionary = browser.detail_stats() if browser != null else {}
			counts[key] = {"open": section["open"], "page": log_stats.get("page", 0), "entries": log_stats.get("matched_count", 0), "rows": log_stats.get("rows", 0), "log": log_stats}
			continue
		var row_count: int = 0
		var rows: Node = (section["detail"] as Node).find_child(key.capitalize() + "Rows", true, false)
		if rows != null:
			for child: Node in rows.get_children():
				if child.get_meta("result_detail_row", false): row_count += 1
		counts[key] = {"open": section["open"], "page": section["page"], "entries": (section["source"] as Array).size(), "rows": row_count}
	return {"active": active_section, "page_size": PAGE_SIZE, "sections": counts,"receipt_rows_formatted":receipt_rows_formatted}
