class_name TownProvisionsTab
extends RefCounted
## Road stores use the existing Food lot ledger and actual market goods.

static func build(host: Control, town: Dictionary) -> Control:
	var root := UiKit.vbox(10)
	UiKit.expand(root, true, true)
	var metrics := UiKit.flow(10)
	metrics.add_child(_metric("FOOD", Food.days_text(Food.food_days(Game)), "%d portions packed" % Food.stock(Game, "meal"), UiTheme.GOOD if Food.food_days(Game) >= Food.WARN_DAYS else UiTheme.BAD))
	metrics.add_child(_metric("DRINK", "Not served" if Game.rations.get("drink") == "dry" else Food.days_text(Food.drink_days(Game)), "%d mugs / %d cups" % [Food.stock(Game, "beer"), Food.stock(Game, "wine")], UiTheme.BLUE))
	metrics.add_child(_metric("RATIONS", String(Food.RATION_LABELS[Game.rations.get("food", "normal")]), "Change rations in Company", UiTheme.COPPER_LO))
	root.add_child(metrics)
	var current := String(host.get_meta("provisions_section", "Food & drink"))
	root.add_child(UiKit.tab_strip(["Food & drink", "Arrows", "Care & tavern"], current, func(section):
		host.set_meta("provisions_section", section)
		host.refresh()))
	var scroll := UiKit.scroll()
	root.add_child(scroll)
	var list := UiKit.vbox(8)
	UiKit.expand(list)
	scroll.add_child(list)
	match current:
		"Arrows": host._arrow_rows(town, list)
		"Care & tavern":
			host._remedy_rows(town, list)
			list.add_child(HSeparator.new())
			list.add_child(UiKit.label("Tavern", "H2"))
			if Food.has_tavern(town):
				list.add_child(UiKit.label("A feast fills bellies and eases stress. Drink may leave sore heads.", "Muted", true))
				var coins := Food.feast_cost(Game, town)
				var feast := UiKit.button("Feast the company · %s coins" % UiKit.thousands(coins), func(): host._feast(town))
				feast.disabled = coins > Game.gold
				list.add_child(feast)
			else:
				list.add_child(UiKit.label("No tavern here.", "Muted"))
		_:
			_food(host, town, list)
	return root

static func _metric(title: String, value: String, detail: String, color: Color) -> Control:
	var panel := UiKit.panel("Card")
	panel.custom_minimum_size.x = 245
	var style := UiTheme.sb(UiTheme.PARCH_2, color, 1, 6, 14, 6)
	style.border_width_left = 5
	panel.add_theme_stylebox_override("panel", style)
	var box := UiKit.vbox(1)
	panel.add_child(box)
	box.add_child(UiKit.label(title, "Small"))
	var number := UiKit.label(value, "H2")
	number.add_theme_color_override("font_color", color)
	number.add_theme_font_size_override("font_size", 24)
	box.add_child(number)
	box.add_child(UiKit.label(detail, "Small"))
	return panel

static func _food(host: Control, town: Dictionary, list: VBoxContainer) -> void:
	var heading := UiKit.hbox()
	heading.add_child(UiKit.label("Market provisions", "H2"))
	heading.add_child(UiKit.spacer())
	heading.add_child(UiKit.button("Pack 7 days…", func(): _pack_preview(host, town), "Row", 160))
	list.add_child(heading)
	list.add_child(_columns(true))
	for good in Goods.FOODS:
		list.add_child(_stock_row(host, town, good, true))
	list.add_child(HSeparator.new())
	list.add_child(UiKit.label("Drink", "H2"))
	for good in ["beer", "wine"]:
		list.add_child(_stock_row(host, town, good, false))
	var packed := Food.packed_food(Game)
	if not packed.is_empty():
		list.add_child(HSeparator.new())
		list.add_child(UiKit.label("In the food wagon", "H2"))
		var grid := GridContainer.new()
		grid.columns = 3
		UiKit.expand(grid)
		grid.add_theme_constant_override("h_separation", 24)
		list.add_child(grid)
		for row in packed:
			grid.add_child(UiKit.wrap(UiKit.label(String(row["name"])), 80))
			grid.add_child(UiKit.label("%d portions" % int(row["qty"]), "H2"))
			grid.add_child(UiKit.label("%d days old" % int(row["oldest"]), "Muted"))
		list.add_child(UiKit.label("Oldest food is eaten first. Mixed rations are earlier supplies with no recorded ingredients.", "Small", true))
	var warning := Food.warning(Game)
	if warning != "":
		list.add_child(UiKit.label(warning, "Bad", true))

static func _columns(header: bool = false) -> HBoxContainer:
	var row := UiKit.hbox(10)
	row.add_child(UiKit.spacer())
	for field in [["FOR SALE", 95], ["PACKED", 95], ["COINS / 10", 125], ["", 210]]:
		var label := UiKit.label(field[0], "Muted")
		label.custom_minimum_size.x = field[1]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(label)
	return row

static func _stock_row(host: Control, town: Dictionary, good: String, edible: bool) -> Control:
	var panel := UiKit.panel("Card")
	var row := UiKit.hbox(10)
	panel.add_child(row)
	row.add_child(UiKit.icon(ItemIcon.for_thing(good), 36))
	var name_box := UiKit.vbox(0)
	UiKit.expand(name_box)
	name_box.add_child(UiKit.wrap(UiKit.label(Food.food_name(town, good), "H2"), 80))
	name_box.add_child(UiKit.label("Road food · portions" if edible else ("Drink · mugs" if good == "beer" else "Drink · cups"), "Small"))
	row.add_child(name_box)
	var available := int(floor(Goods.supply(town, good))) if edible else Food.available(town, good)
	var carried := Food.food_stock(Game, good) if edible else Food.stock(Game, good)
	var coins := Food.food_cost(town, good, 10) if edible else Food.cost(town, good, 10)
	for field in [[str(available) if available >= 0 else "—", 95, UiTheme.INK], [str(carried), 95, UiTheme.BLUE], [str(coins), 125, UiTheme.COPPER_LO]]:
		var value := UiKit.label(field[0], "H2")
		value.custom_minimum_size.x = field[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value.add_theme_color_override("font_color", field[2])
		row.add_child(value)
	for qty in [10, 50]:
		var count: int = mini(qty, available) if available >= 0 else qty
		var price: int = Food.food_cost(town, good, count) if edible else Food.cost(town, good, count)
		var buy := UiKit.button("Buy %d" % maxi(count, 0), func():
			var now_supply := int(floor(Goods.supply(town, good))) if edible else Food.available(town, good)
			var now_price := Food.food_cost(town, good, count) if edible else Food.cost(town, good, count)
			if (now_supply >= 0 and now_supply < count) or now_price != price:
				UiKit.toast(host, "Stock or price changed. Choose again.", false)
				host.refresh()
				return
			if edible:
				var error := Food.buy_food(Game, town, good, count)
				UiKit.toast(host, ("Bought %d portions of %s" % [count, Food.food_name(town, good)]) if error == "" else error, error == "")
				host.refresh()
			else:
				host._buy_food(town, good, count), "", 100)
		buy.name = "BuyProvision_%s_%d" % [good, qty]
		buy.tooltip_text = "%d coins for %d" % [price, count]
		buy.disabled = count <= 0 or price > Game.gold
		row.add_child(buy)
	return panel

## Pure conservative reserve quote, capped to stock and purse. FIFO supplies cover
## immediate hunger first; only food that keeps through the full span counts as reserve.
static func pack_plan(game, town: Dictionary, days: int = 7) -> Dictionary:
	var target := Food.eaters(game).size() * int(Food.MEALS_PER_DAY.get(game.rations.get("food", "normal"), 2)) * days
	var hunger := Food.immediate_food_need(game)
	var hunger_unfilled := hunger
	var safe := 0
	var older := 0
	var limit := int(Food.SPOIL_DAYS["meal"])
	for lot in game.provisions.get("meal", []):
		var qty := int(lot[0])
		var eaten := mini(qty, hunger_unfilled)
		hunger_unfilled -= eaten
		qty -= eaten
		if limit < 0 or int(lot[1]) + days < limit:
			safe += qty
		else:
			older += qty
	var needed := maxi(0, target - safe) + hunger_unfilled
	var remaining := needed
	var coins := int(game.gold)
	var goods := Goods.FOODS.duplicate() if TownEcon.has_econ(town) or town.has("goods") else []
	goods.sort_custom(func(a, b): return Goods.price_f(town, a) < Goods.price_f(town, b))
	var lines := []
	var total := 0
	for good in goods:
		var qty := mini(remaining, int(floor(Goods.supply(town, good))))
		while qty > 0 and Food.food_cost(town, good, qty) > coins:
			qty -= 1
		if qty <= 0:
			continue
		var cost := Food.food_cost(town, good, qty)
		lines.append({"good": good, "qty": qty, "cost": cost})
		remaining -= qty
		coins -= cost
		total += cost
	return {"lines": lines, "total": total, "missing": remaining, "needed": needed, "hunger": hunger,
		"hunger_unfilled": hunger_unfilled, "safe": safe, "older": older}

static func _pack_preview(host: Control, town: Dictionary) -> void:
	var plan := pack_plan(Game, town)
	var box := UiKit.modal(host, "Pack food for 7 days", 680)
	box.add_child(UiKit.label("Seven-day reserve; older food is eaten first.", "Muted", true))
	box.add_child(UiKit.label("Only food that keeps for the full seven days counts toward the reserve.", "Small", true))
	if int(plan["older"]) > 0:
		box.add_child(UiKit.label("%d older portions excluded from the reserve; they remain packed and will be eaten first." % int(plan["older"]), "Small", true))
	if int(plan["hunger"]) > 0:
		box.add_child(UiKit.label("Hungry people need %d portions now; packed food covers %d." % [int(plan["hunger"]), int(plan["hunger"]) - int(plan["hunger_unfilled"])], "Small", true))
	for line in plan["lines"]:
		box.add_child(UiKit.kv("%d × %s" % [line["qty"], Food.food_name(town, line["good"])], "%d coins" % line["cost"]))
	box.add_child(HSeparator.new())
	box.add_child(UiKit.kv("Total", "%d coins" % int(plan["total"]), UiTheme.COPPER_LO))
	if int(plan["missing"]) > 0:
		box.add_child(UiKit.label("%d portions still short: limited stock or coins." % int(plan["missing"]), "Bad", true))
	elif int(plan["needed"]) == 0:
		box.add_child(UiKit.label("You already carry a full seven-day reserve.", "Good"))
	var buttons := UiKit.hbox()
	buttons.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(box), "Row", 140))
	buttons.add_child(UiKit.spacer())
	var buy := UiKit.button("Buy listed food", func():
		var current := pack_plan(Game, town)
		if current != plan:
			UiKit.close_modal(box)
			_pack_preview(host, town)
			return
		UiKit.close_modal(box)
		for line in plan["lines"]:
			var error := Food.buy_food(Game, town, line["good"], int(line["qty"]))
			if error != "":
				UiKit.toast(host, error, false)
				host.refresh()
				return
		UiKit.toast(host, "Food packed · %d coins" % int(plan["total"]))
		host.refresh(), "", 190)
	buy.disabled = plan["lines"].is_empty()
	buttons.add_child(buy)
	box.add_child(buttons)
