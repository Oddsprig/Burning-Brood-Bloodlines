class_name TreasureRoom
extends Control
## A household hoard: value, the 60% sale price, and prestige. The player's house can buy and sell.
var body: VBoxContainer
var heading: Label
var back := "house"
var back_params: Dictionary = {}
var household_uid := ""
var read_only := false
var notice := ""
var _refresh_pending := false
const ORDER := ["gold", "silver", "gems", "art"]

func _ready() -> void:
	back = str(Game.screen_params.get("back", "house"))
	back_params = Game.screen_params.get("back_params", {}).duplicate(true)
	var player := str(Game.world.get("player_house", {}).get("household_uid", ""))
	household_uid = str(Game.screen_params.get("household_uid", player))
	if Game.screen_params.has("read_only"):
		read_only = bool(Game.screen_params["read_only"])
	else:
		read_only = household_uid != player
	var frame := UiKit.screen_frame(self, "Treasure room")
	heading = frame["title"]
	frame["bar"].add_child(UiKit.button("Back", _back, "Row", 72))
	var scroll := UiKit.scroll()
	frame["root"].add_child(scroll)
	body = UiKit.vbox(10)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(body)
	Game.changed.connect(_queue_refresh)
	_refresh()

func _queue_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true
	call_deferred("_refresh")

func _back() -> void:
	Game.goto(back, back_params)

func _refresh() -> void:
	_refresh_pending = false
	if body == null: return
	UiKit.clear(body)
	var loc: Dictionary = Dynasty._household(Game, household_uid)
	var house_name := str(loc["family"].get("name", "House")) if not loc.is_empty() else "Unknown house"
	if heading != null:
		heading.text = "Treasure room · " + house_name
		UiKit.fit_title(heading)
	if notice != "":
		var note := UiKit.label(notice, "", true)
		note.add_theme_color_override("font_color", UiTheme.BRASS)
		body.add_child(note)
	if loc.is_empty():
		body.add_child(UiKit.label("No such household.", "Muted", true))
		return
	var rows: Array = CourtEvents.hoard_view(Game, household_uid)
	var hoard_value := 0
	var prestige := 0.0
	for row: Dictionary in rows:
		hoard_value += int(row.get("value", 0))
		prestige += float(row.get("prestige", 0.0))
	var purse := float(loc["family"].get("purse", 0.0))
	var totals := UiKit.panel("Card")
	totals.name = "HoardTotals"
	body.add_child(totals)
	var words := UiKit.vbox(4)
	totals.add_child(words)
	var hv := UiKit.label("Hoard value: %s coins" % UiKit.thousands(hoard_value), "H2", true)
	hv.name = "HoardValue"
	words.add_child(hv)
	var purse_label := UiKit.label("Purse: %s coins" % UiKit.thousands(int(floor(purse))), "", true)
	purse_label.name = "PurseTotal"
	words.add_child(purse_label)
	var prestige_label := UiKit.label("Prestige from treasure: %.2f" % prestige, "", true)
	prestige_label.name = "TreasurePrestige"
	words.add_child(prestige_label)
	if read_only:
		words.add_child(UiKit.label("Read only. This hoard belongs to another house.", "Muted", true))
	else:
		var buy := UiKit.button("Buy treasure", _open_buy, "Row", 180)
		buy.name = "BuyTreasureButton"
		words.add_child(buy)
	if rows.is_empty():
		body.add_child(UiKit.label("The hoard is empty.", "Muted", true))
		return
	var grouped := {}
	for row: Dictionary in rows:
		var category := str(row.get("category", ""))
		if not grouped.has(category): grouped[category] = []
		grouped[category].append(row)
	var seen: Array = []
	for category in ORDER:
		if grouped.has(category):
			_category(category, grouped[category])
			seen.append(category)
	for category in grouped:
		if category not in seen:
			_category(str(category), grouped[category])

func _category(category: String, rows: Array) -> void:
	body.add_child(UiKit.label(category.capitalize(), "H2", true))
	for row: Dictionary in rows:
		var card := UiKit.panel("Inset")
		card.size_flags_horizontal = SIZE_EXPAND_FILL
		body.add_child(card)
		var line := UiKit.hbox(10)
		card.add_child(line)
		var text := UiKit.vbox(2)
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(text)
		var title := "%s × %d" % [category.capitalize(), int(row.get("quantity", 0))]
		if category == "gems" and str(row.get("gem_id", "")) != "":
			title += " · " + _gem_name(str(row.get("gem_id", "")))
		text.add_child(UiKit.label(title, "", true))
		text.add_child(UiKit.label("Value %s · Sale %s (60%%) · Prestige %.2f" % [UiKit.thousands(int(row.get("value", 0))), UiKit.thousands(int(row.get("sale_value", 0))), float(row.get("prestige", 0.0))], "Muted", true))
		if bool(row.get("gem_match", false)):
			var mark := UiKit.label("Matches a dragon of this house", "", true)
			mark.add_theme_color_override("font_color", UiTheme.GOOD)
			text.add_child(mark)
		if not read_only:
			var sell := UiKit.button("Sell", _ask_sell.bind(row.duplicate(true)), "Row", 100)
			sell.name = "SellButton"
			sell.set_meta("treasure_id", str(row.get("id", "")))
			line.add_child(sell)

func _ask_sell(row: Dictionary) -> void:
	var qty := int(row.get("quantity", 0))
	var coin := int(row.get("sale_value", 0))
	UiKit.confirm(self, "Sell %d %s for %s coins?" % [qty, str(row.get("category", "treasure")), UiKit.thousands(coin)], "Sell", _apply_sell.bind(str(row.get("id", "")), qty))

func _apply_sell(treasure_id: String, quantity: int) -> void:
	var result: Dictionary = CourtEvents.sell_hoard(Game, household_uid, treasure_id, quantity)
	var coin := int(result.get("coin", 0))
	notice = "Received %s coins." % UiKit.thousands(coin) if result.get("ok", false) else "The market could not buy that treasure."
	_refresh()

func _open_buy() -> void:
	var modal := UiKit.modal(self, "Buy treasure", 520)
	modal.add_child(UiKit.label("Paid from the house purse. A later sale returns 60% through the town market.", "Muted", true))
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 1000
	amount.step = 1
	amount.value = 1
	amount.custom_minimum_size = Vector2(0, 48)
	modal.add_child(amount)
	var pick := {"id": str(Dragons.catalogs()["gems"][0]["id"])}
	var gem_label := UiKit.label("Gem: " + _gem_name(str(pick["id"])), "", true)
	modal.add_child(gem_label)
	var gems: Array = []
	for gem: Dictionary in Dragons.catalogs()["gems"]:
		gems.append({"text": str(gem.get("name", gem.get("id", ""))), "value": str(gem.get("id", ""))})
	modal.add_child(UiKit.button("Choose gem", func():
		UiKit.picker(self, "Dragon-catalog gems", gems, func(value):
			pick["id"] = str(value)
			gem_label.text = "Gem: " + _gem_name(str(pick["id"])))
	, "Row", 180))
	var controls := UiKit.flow()
	modal.add_child(controls)
	for category in ORDER:
		var price := int(CourtEvents.TREASURE[str(category)])
		controls.add_child(UiKit.button("Buy %s (%s)" % [str(category), UiKit.thousands(price)], _press_buy.bind(str(category), amount, pick, modal), "Row"))
	modal.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row", 120))

func _press_buy(category: String, amount: SpinBox, pick: Dictionary, modal: Node) -> void:
	var qty := int(amount.value)
	var gem := str(pick.get("id", "")) if category == "gems" else ""
	UiKit.close_modal(modal)
	_review_buy(category, qty, gem)

func _review_buy(category: String, quantity: int, gem_id: String) -> void:
	var args := {"category": category, "quantity": quantity, "gem_id": gem_id}
	var quote: Dictionary = CourtEvents.preview(Game, household_uid, "treasure", args)
	if not quote.get("ok", false):
		notice = str(quote.get("reason", "Cannot buy that treasure."))
		_refresh()
		return
	UiKit.confirm(self, "Buy %d %s for %s coins?" % [quantity, category, UiKit.thousands(int(quote["cost"]))], "Buy", _apply_buy.bind(args, quote))

func _apply_buy(args: Dictionary, quote: Dictionary) -> void:
	var result: Dictionary = CourtEvents.hold(Game, household_uid, "treasure", args, quote)
	notice = "Bought %d %s." % [int(args.get("quantity", 0)), str(args.get("category", ""))] if result.get("ok", false) else str(result.get("reason", "The purchase was not made."))
	_refresh()

static func _gem_name(gem_id: String) -> String:
	for gem: Dictionary in Dragons.catalogs()["gems"]:
		if str(gem.get("id", "")) == gem_id:
			return str(gem.get("name", gem_id))
	return gem_id
