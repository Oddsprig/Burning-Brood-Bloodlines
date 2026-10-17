class_name TownContractsTab
extends RefCounted
## Presentation over the existing offers. Keep actual dictionaries for acceptance.

const SORTS := ["Job A–Z", "Pay: highest first", "Time: shortest first"]
const WEIGHTS := [2.8, 1.0, 1.0]

static func kind_name(contract: Dictionary) -> String:
	var kind := String(contract.get("kind", "battle"))
	return String(Contracts.KIND_INFO.get(kind, {}).get("name", kind.capitalize()))

static func _tone(contract: Dictionary) -> Color:
	return {"battle": UiTheme.BAD, "escort": UiTheme.BLUE, "raid": UiTheme.WARN,
		"arms_raid": UiTheme.WARN, "defend": UiTheme.GOOD, "war": UiTheme.BAD,
		"hunt": UiTheme.WARN, "lair": UiTheme.WARN, "bounty": UiTheme.COPPER,
		"bandits": UiTheme.WARN}.get(String(contract.get("kind", "battle")), UiTheme.WOOD_3)

static func _party(id: String) -> String:
	return UiWords.faction_name(id) if DB.factions.has(id) else id

static func _parties(contract: Dictionary) -> String:
	var parts := []
	var employer := String(contract.get("employer", ""))
	if employer != "": parts.append("For " + _party(employer))
	var target := String(contract.get("target_faction", ""))
	if target != "": parts.append("Against " + _party(target))
	var destination := String(contract.get("dest_id", ""))
	if destination != "":
		var town: Dictionary = Game.world.get("towns", {}).get(destination, {})
		parts.append("To " + String(town.get("name", "unknown town")))
	return " · ".join(PackedStringArray(parts))

static func _limit(contract: Dictionary) -> String:
	return "%s days" % RecKit.num(float(contract["duration"])) if contract.has("duration") else "-"

static func _state(scr: Control) -> Dictionary:
	if not scr.has_meta("contracts_view"):
		scr.set_meta("contracts_view", {"kind": "All", "query": "", "sort": 0})
	return scr.get_meta("contracts_view")

## Sort/filter the same eligible offers. Quotes read the existing negotiated pay.
static func visible_offers(t: Dictionary, state: Dictionary) -> Array:
	var rows := []
	var needle := String(state.get("query", "")).strip_edges().to_lower()
	var selected := String(state.get("kind", "All"))
	var index := 0
	for contract: Dictionary in Contracts.offers_for(Game, t):
		var type := kind_name(contract)
		var text := "%s %s %s %s" % [type, String(contract.get("title", "Contract")), _parties(contract), String(contract.get("desc", ""))]
		if (selected == "All" or selected == type) and (needle == "" or text.to_lower().contains(needle)):
			rows.append({"contract": contract, "pay": Contracts.offered_pay(Game, contract), "index": index})
		index += 1
	var order := int(state.get("sort", 0))
	rows.sort_custom(func(a: Dictionary, b: Dictionary):
		if order == 1 and a["pay"] != b["pay"]: return int(a["pay"]) > int(b["pay"])
		if order == 2:
			var at := float(a["contract"].get("duration", INF))
			var bt := float(b["contract"].get("duration", INF))
			if at != bt: return at < bt
		var an := String(a["contract"].get("title", "Contract")).to_lower()
		var bn := String(b["contract"].get("title", "Contract")).to_lower()
		return an < bn if an != bn else int(a["index"]) < int(b["index"]))
	return rows

static func build(scr: Control, t: Dictionary) -> Control:
	var state := _state(scr)
	var root := UiKit.vbox(8)
	root.name = "TownContracts"
	UiKit.expand(root, true, true)
	var tools := UiKit.flow(8)
	tools.name = "ContractTools"
	root.add_child(tools)
	var types := ["All"]
	for contract: Dictionary in Contracts.offers_for(Game, t):
		var type := kind_name(contract)
		if not types.has(type): types.append(type)
	if not types.has(String(state["kind"])): state["kind"] = "All"
	var category := OptionButton.new()
	category.name = "ContractCategory"
	category.custom_minimum_size = Vector2(140, UiKit.TAP)
	for type in types: category.add_item(String(type))
	category.select(types.find(String(state["kind"])))
	tools.add_child(category)
	var sort := OptionButton.new()
	sort.name = "ContractSort"
	sort.custom_minimum_size = Vector2(160, UiKit.TAP)
	for title in SORTS: sort.add_item(title)
	state["sort"] = clampi(int(state["sort"]), 0, SORTS.size() - 1)
	sort.select(int(state["sort"]))
	tools.add_child(sort)
	var search := LineEdit.new()
	search.name = "ContractSearch"
	search.placeholder_text = "Search jobs, employers or targets"
	search.text = String(state["query"])
	search.custom_minimum_size = Vector2(100, UiKit.TAP)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_stylebox_override("normal", UiTheme.sb(UiTheme.PARCH, UiTheme.PARCH_3, 1, 3, 10, 6))
	search.add_theme_stylebox_override("focus", UiTheme.sb(UiTheme.PARCH, UiTheme.COPPER, 2, 3, 10, 6))
	search.add_theme_color_override("font_color", UiTheme.INK)
	search.add_theme_color_override("font_placeholder_color", UiTheme.INK_SOFT)
	search.add_theme_color_override("caret_color", UiTheme.INK)
	root.add_child(search)
	var clear := UiKit.button("Clear", func():
		search.text = ""
		search.text_changed.emit(""), "Row", 72)
	clear.name = "ContractClear"
	tools.add_child(clear)
	var scroll := UiKit.scroll()
	scroll.name = "ContractsScroll"
	root.add_child(scroll)
	var body := UiKit.vbox(6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	_active(scr, body)
	var offers := UiKit.vbox(6)
	offers.name = "ContractOffers"
	body.add_child(offers)
	var redraw := func(): _offers(scr, t, offers, state)
	category.item_selected.connect(func(i): state["kind"] = types[i]; redraw.call())
	sort.item_selected.connect(func(i): state["sort"] = i; redraw.call())
	search.text_changed.connect(func(value): state["query"] = String(value); redraw.call())
	redraw.call()
	return root

static func _cells(parent: Control, values: Array, header: bool = false) -> void:
	var row := UiKit.hbox(10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	for i in values.size():
		var label := UiKit.label(String(values[i]), "Muted" if header else "Small", true)
		label.tooltip_text = String(values[i])
		label.custom_minimum_size.x = 20
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = float(WEIGHTS[i])
		if i > 0: label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if i == 2 and not header: label.add_theme_color_override("font_color", UiTheme.COPPER)
		if header: label.add_theme_font_override("font", UiTheme.bold())
		row.add_child(label)

static func _offers(scr: Control, t: Dictionary, body: VBoxContainer, state: Dictionary) -> void:
	UiKit.clear(body)
	var available := Contracts.offers_for(Game, t)
	var rows := visible_offers(t, state)
	var count := UiKit.label("%d shown · %d offers" % [rows.size(), available.size()], "Muted", true)
	count.name = "ContractCount"
	body.add_child(count)
	if rows.is_empty():
		var message := "No matching jobs."
		if available.is_empty():
			message = "No one here has work for sellswords." if Diplomacy.contracts_allowed(Game, t.get("faction", "")) else "Nobody here will hire a company with your name (standing %d)." % Diplomacy.standing(Game, t.get("faction", ""))
		body.add_child(UiKit.label(message, "Muted", true))
		return
	var heading := UiKit.panel()
	heading.name = "ContractHeading"
	heading.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.PARCH_2, UiTheme.PARCH_3, 1, 4, 8, 6))
	body.add_child(heading)
	_cells(heading, ["Job", "Time limit", "Offered coins"], true)
	for entry: Dictionary in rows:
		var contract: Dictionary = entry["contract"]
		var panel := UiKit.panel("Card")
		panel.name = "ContractOffer"
		panel.set_meta("contract_offer", {"id": String(contract.get("id", "")), "kind": String(contract.get("kind", "battle")), "pay": int(entry["pay"]), "duration": contract.get("duration", null)})
		panel.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.LIGHT, _tone(contract), 1, 4, 8, 6))
		body.add_child(panel)
		var content := UiKit.vbox(4)
		panel.add_child(content)
		_cells(content, [String(contract.get("title", "Contract")), _limit(contract), str(int(entry["pay"]))])
		var parties := _parties(contract)
		if parties != "": content.add_child(UiKit.label(parties, "Muted", true))
		var actions := UiKit.flow(8)
		content.add_child(actions)
		actions.add_child(UiKit.chip(kind_name(contract), _tone(contract)))
		var accept := UiKit.button("Accept", func(): scr._accept(t, contract), "Row", 96)
		accept.name = "AcceptContract"
		var refusal := Contracts.refusal(Game, contract)
		accept.disabled = scr._has_active_contract() or refusal != ""
		accept.tooltip_text = "Finish the active contract before taking another." if scr._has_active_contract() else refusal
		accept.set_meta("contract_id", String(contract.get("id", "")))
		actions.add_child(accept)
		var details := UiKit.vbox(4)
		details.name = "ContractDetailsBody"
		details.visible = false
		content.add_child(details)
		var detail_button := UiKit.button("Details", func():
			if not details.has_meta("built"):
				details.add_child(UiKit.label(String(contract.get("desc", "")), "Small", true))
				details.set_meta("built", true)
			details.visible = not details.visible, "Row", 96)
		detail_button.name = "ContractDetails"
		actions.add_child(detail_button)

static func _active(scr: Control, body: VBoxContainer) -> void:
	if Game.contract.is_empty(): return
	var contract: Dictionary = Game.contract
	var state := String(contract.get("state", "active"))
	var active: bool = bool(scr._has_active_contract())
	var card := RecKit.card(body, "Active contract" if active else "Last contract")
	card.name = "CurrentContract"
	card.set_meta("contract_state", state)
	card.add_child(UiKit.label(Contracts.status_text(Game) if active else String(contract.get("title", "Contract")), "Small", true))
	var actions := UiKit.flow(8)
	card.add_child(actions)
	var tone := UiTheme.BLUE if active else (UiTheme.GOOD if state == "done" else UiTheme.WARN)
	actions.add_child(UiKit.chip(state.capitalize(), tone))
	if active:
		var abandon := UiKit.button("Abandon", func(): UiKit.confirm(scr, "Abandon the contract? %s will think less of you (%d)." % [
			Diplomacy.cap(CampaignWorld.faction_the(Game.contract.get("employer", ""))), Diplomacy.CONTRACT_ABANDONED], "Abandon", func():
				Contracts.abandon(Game)
				scr.refresh()), "Danger", 120)
		abandon.name = "AbandonContract"
		actions.add_child(abandon)
		card.add_child(UiKit.label("Finish this contract before taking another.", "Muted", true))
	RecKit.disclosure(card, "Contract details", func(box):
		box.add_child(UiKit.label(String(contract.get("desc", "")), "Small", true))
		var parties := _parties(contract)
		if parties != "": box.add_child(UiKit.label(parties, "Small", true))
		box.add_child(UiKit.label("Agreed pay: %d coins" % int(contract.get("pay", 0)), "Small", true)))
