class_name TownMarketTab
extends RefCounted
## Presentation only: groups retain the actual shop Items; transactions use Market/Economy.

const CATEGORIES := ["All", "Weapons", "Bows", "Shields", "Armor", "Clothing", "Other"]
const WEAR := ["Fine", "Worn", "Battered", "Tattered"]

static func category(it: Item) -> String:
	if DB.is_weapon(it.tid):
		return "Weapons"
	if DB.is_bow(it.tid):
		return "Bows"
	if it.slot() == "off_hand":
		return "Shields"
	if it.slot() in ["clothing", "legs_under"]:
		return "Clothing"
	return "Armor" if DB.armor.has(it.tid) else "Other"

## Canonical nested metadata keeps different marks/origins and physical damage separate.
static func _canonical(value: Variant) -> String:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts := PackedStringArray()
		for key in keys:
			parts.append(JSON.stringify(key) + ":" + _canonical(value[key]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts := PackedStringArray()
		for entry in value:
			parts.append(_canonical(entry))
		return "[" + ",".join(parts) + "]"
	return JSON.stringify(value)

static func variant_key(it: Item) -> String:
	var data := it.to_dict()
	data.erase("uid")
	# A named piece has its own carrier/history identity, even if its visible stats match.
	if it.is_legend():
		data["identity"] = it.uid
	return _canonical(data)

static func grouped_stock(t: Dictionary, selected: String = "All", query: String = "") -> Array:
	var groups := []
	var lookup := {}
	var needle := query.strip_edges().to_lower()
	for it in t.get("shop", []):
		if selected != "All" and category(it) != selected:
			continue
		var search := "%s %s %s %s" % [it.display_name(), it.maker_text(), category(it), UiWords.slot_name(it.slot())]
		if needle != "" and not search.to_lower().contains(needle):
			continue
		var price := Market.price(t, it)
		var key := variant_key(it) + ":" + str(price)
		if not lookup.has(key):
			lookup[key] = groups.size()
			groups.append({"item": it, "items": [], "price": price, "category": category(it)})
		groups[int(lookup[key])]["items"].append(it)
	groups.sort_custom(func(a, b):
		var ai: Item = a["item"]
		var bi: Item = b["item"]
		if a["category"] != b["category"]:
			return CATEGORIES.find(a["category"]) < CATEGORIES.find(b["category"])
		if ai.display_name() != bi.display_name():
			return ai.display_name() < bi.display_name()
		if ai.quality != bi.quality:
			return ai.quality > bi.quality
		return int(a["price"]) < int(b["price"]))
	return groups

static func _state(host: Control) -> Dictionary:
	if not host.has_meta("market_view"):
		host.set_meta("market_view", {"category": "All", "query": "", "member": -1})
	return host.get_meta("market_view")

static func _heading(box: Control, text: String, color: Color) -> void:
	var row := UiKit.hbox(8)
	row.add_child(UiKit.chip(text, color))
	row.add_child(UiKit.expand(HSeparator.new()))
	box.add_child(row)

static func build(host: Control, t: Dictionary) -> Control:
	var state := _state(host)
	var root := UiKit.vbox(8)
	UiKit.expand(root, true, true)
	var tools := UiKit.hbox(8)
	root.add_child(tools)
	var category_picker := OptionButton.new()
	category_picker.custom_minimum_size = Vector2(140, UiKit.tap_height())
	for label in CATEGORIES:
		category_picker.add_item(label)
	category_picker.select(maxi(0, CATEGORIES.find(state["category"])))
	tools.add_child(category_picker)
	var search := LineEdit.new()
	search.placeholder_text = "Search items, makers or origins"
	search.text = state["query"]
	search.custom_minimum_size = Vector2(100, UiKit.tap_height())
	UiKit.expand(search)
	tools.add_child(search)
	tools.add_child(UiKit.button("Clear", func(): search.text = "", "Row", 72))
	var sc := UiKit.scroll()
	root.add_child(sc)
	var content := UiKit.vbox(8)
	UiKit.expand(content)
	sc.add_child(content)
	_actions(host, t, content, state)
	_heading(content, "Local stock", UiTheme.COPPER_LO)
	var stock := UiKit.vbox(4)
	content.add_child(stock)
	var redraw := func(): _stock(host, t, stock, state)
	category_picker.item_selected.connect(func(index):
		state["category"] = CATEGORIES[index]
		redraw.call())
	search.text_changed.connect(func(value):
		state["query"] = value
		redraw.call())
	redraw.call()
	_goods(host, t, content)
	return root

static func _actions(host: Control, t: Dictionary, box: Control, state: Dictionary) -> void:
	var toolbar := UiKit.panel("Inset")
	var actions := UiKit.flow(6)
	toolbar.add_child(actions)
	box.add_child(toolbar)
	var members := OptionButton.new()
	members.custom_minimum_size = Vector2(230, UiKit.tap_height())
	members.tooltip_text = "Company member for Buy best and Equip best"
	members.fit_to_longest_item = false
	members.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var live: Array = Game.company.filter(func(u): return not u.dead)
	var picked := 0
	for i in live.size():
		members.add_item("%s · %s" % [live[i].name, live[i].title])
		if live[i].uid == int(state["member"]):
			picked = i
	if not live.is_empty():
		members.select(picked)
		state["member"] = live[picked].uid
	else:
		members.add_item("No living company members")
		members.disabled = true
		state["member"] = -1
	members.item_selected.connect(func(index): state["member"] = live[index].uid)
	actions.add_child(members)
	var buy := UiKit.button("Buy best…", func(): _buy_preview(host, t, _member(state)), "", 160)
	buy.tooltip_text = "Preview upgrades and exact cost for the selected member; follows uniforms and overrides."
	buy.disabled = live.is_empty()
	actions.add_child(buy)
	var equip := UiKit.button("Equip best", func(): _equip_best(host, _member(state)), "Row", 135)
	equip.tooltip_text = "Use the best matching company items. Uniforms and individual overrides still apply."
	equip.disabled = live.is_empty()
	actions.add_child(equip)
	var sell := UiKit.button("Sell stash (%d)" % Game.stash.size(), func(): host.call("_sell", t), "Row", 145)
	sell.disabled = Game.stash.is_empty()
	actions.add_child(sell)
	var need := Outfit.shortfall(Game.squads, Game.company, Game.stash)
	var count := 0
	for n in need:
		count += int(n["count"])
	var uniforms := UiKit.button("Fill uniforms (%d)" % count, func(): _fill_uniforms(host, t), "Row", 190)
	uniforms.tooltip_text = "%d missing uniform pieces; buy matching stock and apply squad uniforms" % count
	uniforms.disabled = count == 0
	actions.add_child(uniforms)
	actions.add_child(UiKit.button("Smiths...", func(): _smiths(host, t), "Row", 115))

static func _smiths(host: Control, t: Dictionary) -> void:
	var options := []
	for kind in ["weaponsmith", "armorsmith"]:
		var crafter: Dictionary = t.get("crafters", {}).get(kind, {})
		options.append({"text": "%s: %s" % [kind.capitalize(), crafter.get("name", "None")],
			"value": {"kind": kind, "crafter": crafter}, "disabled": crafter.is_empty()})
	UiKit.picker(host, "Local smiths", options, func(pick): host.call("_smith", pick["kind"], pick["crafter"]))

static func _member(state: Dictionary) -> Unit:
	for u in Game.company:
		if u.uid == int(state["member"]) and not u.dead:
			return u
	return null

static func _condition(it: Item) -> String:
	if it.broken:
		return "Broken"
	var text: String = WEAR[clampi(it.wear, 0, WEAR.size() - 1)]
	if it.dull > 0.0:
		text += " · dull %.0f%%" % (it.dull * 100.0)
	return text

static func _quality_name(it: Item) -> String:
	return "ordinary" if it.quality == 0 else String(DB.QUALITY_NAMES[it.quality])

static func _stock(host: Control, t: Dictionary, box: Control, state: Dictionary) -> void:
	UiKit.clear(box)
	var groups := grouped_stock(t, state["category"], state["query"])
	var quantity := 0
	for group in groups:
		quantity += group["items"].size()
	box.add_child(UiKit.label("%d pieces · %d variants" % [quantity, groups.size()], "Muted"))
	if groups.is_empty():
		box.add_child(UiKit.label("The stalls are bare." if t.get("shop", []).is_empty() else "No items match these filters.", "Muted"))
		return
	var header := UiKit.panel("Inset")
	header.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.PARCH_3, UiTheme.BORDER, 1, 4, 12, 4))
	var columns := UiKit.hbox(8)
	header.add_child(columns)
	var item_heading := _table_cell("Item", 100, UiTheme.INK)
	UiKit.expand(item_heading)
	columns.add_child(item_heading)
	columns.add_child(VSeparator.new())
	columns.add_child(_table_cell("Quality", 135, UiTheme.COPPER_LO))
	columns.add_child(_table_cell("Condition", 100, UiTheme.INK))
	var qty_heading := _table_cell("Qty", 45, UiTheme.BLUE)
	qty_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	columns.add_child(qty_heading)
	var coins_heading := _table_cell("Coins", 90, UiTheme.COPPER_LO)
	coins_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	columns.add_child(coins_heading)
	columns.add_child(_table_cell("", 70, UiTheme.INK))
	columns.add_child(_table_cell("", 80, UiTheme.INK))
	box.add_child(header)
	for group in groups:
		var it: Item = group["item"]
		var card := UiKit.panel("Card")
		var card_style: StyleBox = UiTheme.get_theme().get_stylebox("panel", "Card").duplicate()
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8
		card.add_theme_stylebox_override("panel", card_style)
		var row := UiKit.hbox(8)
		card.add_child(row)
		var item_cell := UiKit.hbox(6)
		UiKit.expand(item_cell)
		row.add_child(item_cell)
		item_cell.add_child(UiKit.icon(ItemIcon.for_item(it), 36))
		var name := _table_cell(it.display_name(), 58, UiTheme.INK)
		name.add_theme_font_size_override("font_size", 18)
		name.tooltip_text = "%s\n%s\n%s" % [it.display_name(), UiWords.slot_name(it.slot()), it.maker_text()]
		UiKit.expand(name)
		item_cell.add_child(name)
		row.add_child(VSeparator.new())
		row.add_child(_table_cell(_quality_name(it), 135, UiTheme.COPPER_LO if it.quality > 0 else UiTheme.INK_SOFT))
		var condition := "Broken" if it.broken else String(WEAR[clampi(it.wear, 0, WEAR.size() - 1)])
		if it.dull > 0.0 and not it.broken:
			condition += ", dull"
		var condition_label := _table_cell(condition, 100, UiTheme.BAD if it.broken else (UiTheme.GOOD if it.wear == 0 and it.dull == 0.0 else UiTheme.WARN))
		condition_label.tooltip_text = _condition(it)
		row.add_child(condition_label)
		var qty := _table_cell(str(group["items"].size()), 45, UiTheme.BLUE)
		qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(qty)
		var price: int = group["price"]
		var coins := _table_cell(str(price), 90, UiTheme.COPPER_LO if price <= Game.gold else UiTheme.BAD)
		coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		coins.tooltip_text = "%d coins per physical piece" % price
		row.add_child(coins)
		var buy := UiKit.button("Buy", func():
			var error := Market.buy(Game, t, it)
			UiKit.toast(host, "Bought %s" % it.display_name() if error == "" else error, error == "")
			host.call("refresh"), "", 70)
		buy.add_theme_font_size_override("font_size", 17)
		buy.tooltip_text = "Buy one %s for %d coins" % [it.display_name(), price]
		buy.disabled = price > Game.gold or it.broken
		row.add_child(buy)
		var detail := UiKit.button("Details", func(): _details(host, it, group["items"]), "Row", 80)
		detail.add_theme_font_size_override("font_size", 17)
		for style in ["normal", "hover", "pressed", "disabled"]:
			var detail_style: StyleBox = UiTheme.get_theme().get_stylebox(style, "Row").duplicate()
			detail_style.content_margin_left = 6
			detail_style.content_margin_right = 6
			detail.add_theme_stylebox_override(style, detail_style)
		row.add_child(detail)
		box.add_child(card)

static func _table_cell(text: String, width: float, color: Color) -> Label:
	var label := UiKit.label(text)
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", color)
	label.custom_minimum_size.x = width
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.tooltip_text = text
	return label

static func _details(host: Control, it: Item, items: Array) -> void:
	var lines := [UiWords.slot_name(it.slot()), "%s · %s · %s" % [_quality_name(it), _condition(it), UiWords.kg(it.mass())], it.maker_text()]
	if Outfit.is_two_handed(it.tid):
		lines.append("Two-handed; cannot carry a shield.")
	if DB.is_bow(it.tid):
		lines.append("Bow variance: %.3f" % it.vr)
	lines.append("%d matching physical pieces; Buy takes one." % items.size())
	lines.append_array(it.legend_lines())
	UiKit.message(host, it.display_name(), lines)

static func _buy_preview(host: Control, t: Dictionary, u: Unit) -> void:
	if u == null:
		return
	var plan := Market.plan_best_for_unit(Game, t, u)
	if plan["buys"].is_empty():
		UiKit.message(host, "Buy best · " + u.name, ["No affordable matching upgrades are available."])
		return
	plan["variants"] = []
	for buy in plan["buys"]:
		plan["variants"].append(variant_key(buy["item"]))
	var v := UiKit.modal(host, "Buy best · " + u.name, 720)
	v.add_child(UiKit.label("%d pieces · %d coins total" % [plan["buys"].size(), plan["total"]], "H2"))
	var sc := UiKit.scroll()
	sc.custom_minimum_size.y = mini(76 * plan["buys"].size(), 380)
	v.add_child(sc)
	var list := UiKit.vbox(6)
	UiKit.expand(list)
	sc.add_child(list)
	for b in plan["buys"]:
		var item: Item = b["item"]
		var row := UiKit.hbox(8)
		row.add_child(UiKit.icon(ItemIcon.for_item(item), 40))
		var text := UiKit.label("%s · %s\n%s · %s · %d coins" % [UiWords.slot_name(b["slot"]), item.display_name(), _quality_name(item), _condition(item), b["price"]], "", true)
		text.tooltip_text = item.maker_text()
		row.add_child(text)
		list.add_child(row)
	var buttons := UiKit.hbox(8)
	buttons.add_child(UiKit.spacer())
	buttons.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(v), "Row", 120))
	buttons.add_child(UiKit.button("Buy & equip · %d" % plan["total"], func():
		UiKit.close_modal(v)
		if not _valid_plan(Game, t, u, plan):
			UiKit.toast(host, "Stock, coins or equipment changed. Preview Buy best again.", false)
			return
		var bought := Market.buy_best_for_unit(Game, t, u, plan)
		UiKit.toast(host, "%s: bought and equipped %d pieces" % [u.name, bought], bought > 0)
		host.call("refresh"), "", 210))
	v.add_child(buttons)

## Reject the complete stale plan before any purchase; execution still uses real Economy transfers.
static func _valid_plan(game, t: Dictionary, u: Unit, preview: Dictionary) -> bool:
	if u.dead or not game.company.has(u) or int(preview["total"]) > game.gold:
		return false
	var current := Market.plan_best_for_unit(game, t, u)
	if int(current["total"]) != int(preview["total"]) or current["buys"].size() != preview["buys"].size():
		return false
	for i in preview["buys"].size():
		var old: Dictionary = preview["buys"][i]
		var now: Dictionary = current["buys"][i]
		if old["item"] != now["item"] or old["slot"] != now["slot"] or int(old["price"]) != int(now["price"]):
			return false
		if not t.get("shop", []).has(old["item"]) or old["item"].broken:
			return false
		if preview.has("variants") and variant_key(old["item"]) != preview["variants"][i]:
			return false
	return true

static func stash_plan(game, u: Unit) -> Dictionary:
	var wanted := Outfit.wanted(game.squads, u)
	# Unspecified slots upgrade their existing template; an explicit empty override stays empty.
	for slot in DB.EQUIP_SLOTS:
		var cur: Item = u.equip.get(slot, null)
		if not wanted.has(slot) and cur != null:
			wanted[slot] = cur.tid
	var avail: Array = game.stash.filter(func(it): return not it.broken)
	return Outfit.plan_unit(u, wanted, String(Outfit.rule_of(game.squads, u).get("material", "any")), avail)

static func _equip_best(host: Control, u: Unit) -> void:
	if u == null:
		return
	var plan := stash_plan(Game, u)
	var equipped := Outfit.execute(u, plan["take"], Game.stash)
	UiKit.toast(host, "%s: equipped %d pieces%s" % [u.name, equipped, " · %d still missing" % plan["missing"].size() if not plan["missing"].is_empty() else ""])
	host.call("refresh")

static func _fill_uniforms(host: Control, t: Dictionary) -> void:
	var result := Market.buy_to_fill(Game, t)
	host.call("refresh")
	var lines := ["%d pieces bought · %d coins spent · uniforms applied" % [result["bought"].size(), result["spent"]]]
	for name in result["bought"]:
		lines.append("Bought " + name)
	for missing in result["short"]:
		lines.append("Missing: " + missing)
	UiKit.message(host, "Fill uniforms", lines)

static func _goods(host: Control, t: Dictionary, box: Control) -> void:
	_heading(box, "Trade goods", UiTheme.GOOD)
	var goods := Goods.company_goods(Game)
	if goods.is_empty():
		box.add_child(UiKit.label("No company trade goods. Town stores are shown in the Town tab.", "Muted", true))
	for good in goods:
		var have := int(floor(float(goods[good])))
		var row := UiKit.hbox(8)
		row.add_child(UiKit.label(Goods.good_name(good).capitalize(), "H2", true))
		row.add_child(UiKit.chip("%d carried" % have, UiTheme.WOOD_3))
		var level := Goods.level_word(t, good)
		var level_color: Color = {"scarce": UiTheme.BAD, "short": UiTheme.WARN, "enough": UiTheme.GOOD, "plenty": UiTheme.BLUE}.get(level, UiTheme.WOOD_3)
		row.add_child(UiKit.chip(level, level_color))
		var button := UiKit.button("Sell all · %d each" % Goods.sell_price(t, good), func():
			var got := Goods.sell(Game, t, good, have)
			UiKit.toast(host, "Sold %s for %d coins" % [Goods.good_name(good), got])
			host.call("refresh"), "Row", 180)
		button.disabled = have <= 0
		row.add_child(button)
		box.add_child(row)
