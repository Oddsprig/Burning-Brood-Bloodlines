class_name TownOrdersTab
extends RefCounted
## Shared by Town -> Orders and Records -> Treasury. All actions re-fetch live
## records and recheck authority; opening the view never initializes an order book.

static func build(host: Control, town: Dictionary, body: VBoxContainer) -> void:
	var section := UiKit.vbox(8)
	section.name = "TownSupplyOrders"
	body.add_child(section)
	_render(host, str(town["id"]), section)

static func _field(parent: Container, title: String, control: Control) -> void:
	var box := UiKit.vbox(2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UiKit.label(title, "Small", true))
	control.custom_minimum_size = Vector2(120, 48)
	box.add_child(control)
	parent.add_child(box)

static func _number(value: float, maximum: float, whole: bool = false) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 1.0 if whole else 0.01
	spin.max_value = maximum
	spin.step = 1.0 if whole else 0.01
	spin.value = maxf(spin.min_value, value)
	return spin

static func _changed(host: Control, tid: String, body: VBoxContainer, result: Dictionary) -> void:
	if not result.get("ok", false):
		UiKit.message(host, "Supply order", [str(result.get("reason", "Order could not be changed."))])
		return
	Game.changed.emit()
	_render(host, tid, body)
	# Refresh the containing town's treasury metrics as well as this order list.
	if host.has_method("refresh"): host.call_deferred("refresh")

static func _render(host: Control, tid: String, body: VBoxContainer) -> void:
	UiKit.clear(body)
	var town: Dictionary = Game.world.get("towns", {}).get(tid, {})
	if not TownEcon.has_econ(town): return
	var e: Dictionary = town["econ"]
	body.add_child(UiKit.label("Orders", "H2"))
	body.add_child(UiKit.label("Treasury available: %.2f coins; reserved: %.2f." % [
		float(e["treasury"]), SupplyOrders.reserved(e)], "Small", true))
	body.add_child(UiKit.label("The cap includes goods and a fixed freight fee. Partial shipments are allowed. Cancelling releases unused funds; paid cargo still travels to town and can be lost to raiders.", "Muted", true))
	var manage := SupplyOrders.can_manage(Game, tid)
	if manage:
		var form := UiKit.flow(8)
		body.add_child(form)
		var good := OptionButton.new()
		good.name = "SupplyGood"
		for g in SupplyOrders.GOODS:
			good.add_item(("Metal: " if str(g).ends_with("_bars") else "") + Goods.good_name(str(g)) + " (" + Goods.unit_of(str(g)) + ")")
		_field(form, "Good", good)
		var quantity := _number(100.0, 1000000.0, true)
		quantity.name = "SupplyQuantity"
		_field(form, "Quantity", quantity)
		var unit := _number(Goods.price_f(town, "grain") * 1.5, 1000000000.0)
		unit.name = "SupplyUnitCap"
		_field(form, "Max coins per unit", unit)
		var cap := _number(minf(Caravans.PURSE_MAX, maxf(1.0, float(e["treasury"]) * 0.25)), 1000000000.0)
		cap.name = "SupplyCap"
		_field(form, "Total cap (coins)", cap)
		var source := OptionButton.new()
		source.name = "SupplySource"
		source.add_item("Best reachable source")
		var ids := ["best"]
		for sid in SupplyOrders.sources(Game.world, town):
			ids.append(sid)
			source.add_item(str(Game.world["towns"][sid].get("name", sid)))
		_field(form, "Source", source)
		var place := UiKit.button("Place order", func():
			_changed(host, tid, body, SupplyOrders.place(Game, tid, str(SupplyOrders.GOODS[good.selected]),
				int(quantity.value), unit.value, cap.value, str(ids[source.selected]))), "Row", 140)
		place.name = "SupplyPlace"
		body.add_child(place)
	else:
		body.add_child(UiKit.label("Only this town's player ruler can manage its orders.", "Muted", true))
	var rows := SupplyOrders.orders(town)
	if rows.is_empty(): body.add_child(UiKit.label("No supply orders recorded.", "Muted"))
	for i in range(rows.size() - 1, -1, -1):
		var order: Dictionary = rows[i]
		var card := UiKit.panel("Card")
		card.name = "SupplyOrder_" + str(order["id"])
		body.add_child(card)
		var box := UiKit.vbox(4)
		card.add_child(box)
		var state := str(order["state"]).capitalize()
		if state == "Delivered" and int(order["delivered"]) < int(order["quantity"]): state += " (partial)"
		box.add_child(UiKit.label("%s - %s: %d/%d delivered" % [state,
			Goods.good_name(str(order["good"])), int(order["delivered"]), int(order["quantity"])], "", true))
		var sid := str(order["actual_source"]) if str(order["actual_source"]) != "" else str(order["source"])
		var source_name := "Best reachable source" if sid == "best" else str(Game.world["towns"].get(sid, {}).get("name", sid))
		box.add_child(UiKit.label("Source: %s; loaded %d. Spent %.2f; reserved %.2f; released %.2f coins." % [
			source_name, int(order["loaded"]), float(order["spent"]), float(order["reserved"]), float(order["refunded"])], "Small", true))
		if str(order["reason"]) != "": box.add_child(UiKit.label(str(order["reason"]), "Muted", true))
		if manage and not order.get("closed", false):
			var oid := str(order["id"])
			box.add_child(UiKit.button("Cancel remainder" if int(order["loaded"]) > 0 else "Cancel order", func():
				_changed(host, tid, body, SupplyOrders.cancel(Game, tid, oid)), "Row", 150))
