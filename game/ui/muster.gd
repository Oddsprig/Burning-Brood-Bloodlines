class_name MusterView
extends Control
## Native mobilisation quotes; only confirmed commands change people or accounts.
var town_id: String = ""
var back: String = "map"
var back_params: Dictionary = {}
var current_status: Dictionary = {}
var current_quote: Dictionary = {}
var down_quote: Dictionary = {}
var refit_current: Dictionary = {}
var notice: String = ""
var body: VBoxContainer
var count_input: SpinBox
var fund_input: SpinBox
var fund_button: Button
var state_label: Label
var wallet_label: Label
var town_label: Label
var people_label: Label
var limits_label: Label
var cost_label: Label
var payer_label: Label
var reason_label: Label
var notice_label: Label
var raise_button: Button
var down_button: Button
var refit_button: Button
var house_flow: HFlowContainer
var mounts_flow: VBoxContainer
var _house_key: String = "?"
var _refresh_pending: bool = false

func _ready() -> void:
	Perf.set_stage("Army management")
	town_id = String(Game.screen_params.get("town_id", Mobilization.status(Game).get("town_id", "")))
	back = String(Game.screen_params.get("back", "map"))
	back_params = (Game.screen_params.get("back_params", {}) as Dictionary).duplicate(true)
	var frame: Dictionary = UiKit.screen_frame(self, "Army")
	(frame["title"] as Label).add_theme_font_size_override("font_size", 28)
	(frame["title"] as Label).custom_minimum_size.x = 100
	(frame["bar"] as Node).add_child(UiKit.button("Roster & gear", _roster, "Row", 140))
	var close := UiKit.button("Back", _back, "Row", 80); close.name = "MusterBack"
	(frame["bar"] as Node).add_child(close)
	var scroll := UiKit.scroll(); scroll.name = "MusterScroll"
	(frame["root"] as Node).add_child(scroll)
	body = UiKit.vbox(10); body.name = "MusterBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var status := _card("ArmyStatusCard")
	state_label = _line(status, "MusterState", "H2")
	wallet_label = _line(status, "MusterWallet")
	var funding := UiKit.flow(8); status.add_child(funding)
	funding.add_child(UiKit.label("Move coin from your house purse:", "", true))
	fund_input = SpinBox.new(); fund_input.name = "MusterFundingAmount"
	fund_input.min_value = 0; fund_input.max_value = 999999999; fund_input.step = 1
	fund_input.custom_minimum_size = Vector2(170,48)
	fund_input.value_changed.connect(func(_value: float): _queue_refresh())
	funding.add_child(fund_input)
	fund_button = UiKit.button("Review transfer",request_funding,"Row",160); fund_button.name = "MusterFund"
	funding.add_child(fund_button)
	var house := _card("MusterHouseCard")
	var house_heading := UiKit.label("Your house", "H2"); house_heading.name = "MusterHouseHeading"
	house_heading.tooltip_text = "Family members who ride with the army fight in the rounds: they gain experience, can be wounded, captured or killed, and the commander's fall shakes the whole army."
	house.add_child(house_heading)
	house_flow = UiKit.flow(10); house_flow.name = "MusterHouseFlow"
	house.add_child(house_flow)
	var settlement := _card("MusterSettlementCard")
	town_label = _line(settlement, "MusterTown", "H2")
	people_label = _line(settlement, "MusterPeople")
	limits_label = _line(settlement, "MusterLimits", "Muted")
	var selection := UiKit.flow(8); settlement.add_child(selection)
	selection.add_child(UiKit.label("How many to raise:", "", true))
	count_input = SpinBox.new(); count_input.name = "MusterCount"
	count_input.min_value = 1; count_input.max_value = 200; count_input.step = 1; count_input.value = 100
	count_input.custom_minimum_size = Vector2(150,48)
	count_input.value_changed.connect(func(_value: float): _queue_refresh())
	selection.add_child(count_input)
	cost_label = _line(settlement, "MusterCost")
	payer_label = _line(settlement, "MusterPayer", "Muted")
	reason_label = _line(settlement, "MusterReason", "Muted")
	var actions := UiKit.flow(8); settlement.add_child(actions)
	raise_button = UiKit.button("Review raising", request_raise, "Row", 160); raise_button.name = "MusterRaise"
	actions.add_child(raise_button)
	down_button = UiKit.button("Review stand-down", request_stand_down, "Row", 190); down_button.name = "MusterStandDown"
	actions.add_child(down_button)
	down_button.tooltip_text = "Stand down at home: the same people return to work with their injuries and gear."
	refit_button = UiKit.button("Refit army", request_refit, "Row", 160); refit_button.name = "MusterRefit"
	actions.add_child(refit_button)
	refit_button.tooltip_text = "Refit at home: body armour and helmets from this town's armory or stalls for soldiers who lack them."
	mounts_flow = _card("MusterMounts")
	notice_label = _line(body, "MusterNotice")
	Game.changed.connect(_queue_refresh)
	_refresh()

func _card(node_name: String) -> VBoxContainer:
	var card := UiKit.panel("Card"); card.name = node_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(card)
	var column := UiKit.vbox(6); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; card.add_child(column)
	return column

func _line(parent: Node, node_name: String, style: String = "") -> Label:
	var line := UiKit.label("", style, true); line.name = node_name
	parent.add_child(line)
	return line

static func coins(amount: Variant) -> String:
	return "%.2f" % float(amount)

func _queue_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true
	call_deferred("_refresh")

func _refresh() -> void:
	_refresh_pending = false
	if not is_node_ready(): return
	var started: int = Time.get_ticks_usec()
	current_status = Mobilization.status(Game)
	var raised: int = int(current_status.get("company",0))
	var places: int = maxi(0,Mobilization.LIMIT - raised)
	count_input.max_value = maxi(1,places)
	count_input.editable = places > 0
	current_quote = Mobilization.quote(Game, town_id, int(count_input.value))
	down_quote = Mobilization.stand_down_quote(Game, town_id)
	refit_current = Mobilization.refit_quote(Game, town_id)
	var C := func(v): return UiKit.compact_coins(float(v))
	state_label.text = "Your army is not raised yet" if raised == 0 else "%d soldiers in the field (of %d)" % [int(current_status.get("alive",0)), Mobilization.LIMIT]
	var days: String = Food.days_text(float(current_status.get("food_days",0))) if int(current_status.get("alive",0)) > 0 else "no troops eating"
	wallet_label.text = "Army purse %s · pay %s a day · food %s     House purse %s" % [C.call(current_status.get("army_gold",0)), C.call(current_status.get("daily_pay",0)), days, C.call(current_status.get("payer_purse",0))]
	town_label.text = "Raise troops at " + String(current_quote.get("town_name", "your home"))
	people_label.text = "You can raise %d of the %d you ask for" % [int(current_quote.get("planned",current_quote.get("available",0))), int(current_quote.get("requested",0))]
	people_label.tooltip_text = "Manpower %d (available %d) · home reserves %d · new recruits %d · kits %d · food %d meals" % [int(current_quote.get("eligible",0)),int(current_quote.get("available",0)),int(current_quote.get("reserve_available",0)),int(current_quote.get("new_available",0)),int(current_quote.get("kit_available",0)),int(current_quote.get("food_available",0))]
	limits_label.text = "Limited by: people %d · kits %d · food %d meals" % [int(current_quote.get("available",0)), int(current_quote.get("kit_available",0)), int(current_quote.get("food_available",0))]
	cost_label.text = "Raising costs %s now, then %s a day in pay and %.0f meals a day" % [C.call(current_quote.get("raise_cost",0)), C.call(current_quote.get("daily_pay",0)), float(current_quote.get("food_per_day",0))]
	payer_label.text = ("Short by %s: fund the army purse first." % C.call(current_quote.get("required_funding",0))) if float(current_quote.get("required_funding",0)) > 0.0 else ""
	payer_label.visible = payer_label.text != ""
	reason_label.text = String(current_quote.get("reason",""))
	raise_button.disabled = not bool(current_quote.get("ok",false))
	down_button.disabled = not bool(down_quote.get("ok",false))
	down_button.tooltip_text = "Stand down at home: the same people return to work. " + String(down_quote.get("reason",""))
	refit_button.disabled = not bool(refit_current.get("ok",false))
	refit_button.tooltip_text = "Refit at home: body armour and helmets for soldiers who lack them. " + String(refit_current.get("reason",""))
	fund_button.disabled = fund_input.value <= 0 or not bool(current_status.get("can_act",false)) or fund_input.value > float(current_status.get("payer_purse",0))
	_refresh_house()
	_refresh_mounts()
	notice_label.text = notice
	Perf.record_us("Army interface",Time.get_ticks_usec()-started)

func _refresh_house() -> void:
	if house_flow == null: return
	var candidates: Array = Mobilization.household_candidates(Game)
	var riding: Array = []
	for u in Game.company:
		if u != null and Mobilization.is_house_rider(Game, u): riding.append(u)
	var key := ""
	for u in riding: key += "r:%d:%s;" % [int(u.uid), String(u.name)]
	for row in candidates: key += "c:%s:%s:%d;" % [str(row.get("person_uid", "")), String(row.get("name", "")), int(row.get("age", 0))]
	if key == _house_key: return
	_house_key = key
	UiKit.clear(house_flow)
	if candidates.is_empty() and riding.is_empty():
		house_flow.add_child(UiKit.label("No adult family members are free to ride with the army.", "Muted", true))
		return
	for u in riding:
		var card := UiKit.panel("Card"); card.name = "MusterHouseRiding"
		card.custom_minimum_size = Vector2(250, 0)
		var col := UiKit.vbox(4); card.add_child(col)
		col.add_child(UiKit.label(String(u.name), "", true))
		var tag := UiKit.label("riding", "Small"); tag.add_theme_color_override("font_color", UiTheme.GOOD)
		col.add_child(tag)
		house_flow.add_child(card)
	for row in candidates:
		var card := UiKit.panel("Card"); card.name = "MusterHouseCandidate"
		card.custom_minimum_size = Vector2(250, 0)
		var col := UiKit.vbox(6); card.add_child(col)
		var top := UiKit.hbox(8); col.add_child(top)
		var p := Portrait.new(); p.custom_minimum_size = Vector2(72, 72); p.mouse_filter = MOUSE_FILTER_IGNORE; p.set_spec(Dynasty.portrait_for(Game, row))
		top.add_child(p)
		var words := UiKit.vbox(2); words.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(words)
		words.add_child(UiKit.label(String(row.get("name", "")), "", true))
		var detail := "age %d" % int(row.get("age", 0))
		if String(row.get("title", "")) != "": detail += " · " + String(row.get("title", ""))
		words.add_child(UiKit.label(detail, "Muted", true))
		var ride := UiKit.button("Ride with the army", apply_enlist_household.bind(str(row.get("person_uid", ""))), "Row", 0); ride.name = "MusterRideWithArmy"
		ride.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(ride)
		house_flow.add_child(card)

func apply_enlist_household(person_uid: String) -> Dictionary:
	var r: Dictionary = Mobilization.enlist_household(Game, person_uid)
	notice = String(r.get("reason", ""))
	if bool(r.get("ok", false)): Game.save_game_async()
	_refresh()
	return r

static func raise_text(quote: Dictionary) -> String:
	return "Raise %d of %d additional troops in %s?\nPay %s coins from the army purse, including %d deployment meals. Daily pay: %s coins; daily food: %.1f meals. Three days of pay remain reserved.\nHouse purse: %s (%s coins), not charged by this order. Army purse: %s coins.\nOnly actual eligible people and available equipment/food are raised; shortages can limit the number." % [int(quote.get("planned",quote.get("available",0))),int(quote.get("requested",0)),String(quote.get("town_name","this settlement")),coins(quote.get("raise_cost",0)),int(quote.get("food_units",0)),coins(quote.get("daily_pay",0)),float(quote.get("food_per_day",0)),String(quote.get("payer_name","Unavailable")),coins(quote.get("payer_purse",0)),coins(quote.get("army_gold",0))]

func _review(title: String, text: String, action: Callable) -> void:
	var modal := UiKit.modal(self, title, 560)
	modal.add_child(UiKit.label(text,"",true))
	var actions := UiKit.flow(8); modal.add_child(actions)
	var cancel := UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row", 120); cancel.name = "MusterCancel"
	var confirm := UiKit.button("Confirm", func(): UiKit.close_modal(modal); action.call(), "Row", 120); confirm.name = "MusterConfirm"
	actions.add_child(cancel); actions.add_child(confirm)

func request_raise() -> void:
	var quote: Dictionary = Mobilization.quote(Game,town_id,int(count_input.value))
	if not bool(quote.get("ok",false)):
		notice = String(quote.get("reason","Raising unavailable.")); _refresh(); return
	var reviewed: Dictionary = quote.get("review",{})
	_review("Raise an army",raise_text(quote),apply_raise.bind(town_id,int(count_input.value),reviewed))

func apply_raise(tid: String, amount: int, review: Dictionary) -> Dictionary:
	var outcome: Dictionary = Mobilization.muster(Game,tid,amount,review)
	notice = String(outcome.get("reason",""))
	if bool(outcome.get("ok",false)):
		notice = "%d of %d requested troops raised%s. Cost: %s coins. %s" % [int(outcome.get("raised",0)),int(outcome.get("requested",amount))," · partial raising" if bool(outcome.get("partial",false)) else "",coins(outcome.get("cost",0)),notice]
		Game.save_game_async()
	_refresh()
	return outcome

func request_stand_down() -> void:
	var quote: Dictionary = Mobilization.stand_down_quote(Game,town_id)
	if not bool(quote.get("ok",false)):
		notice = String(quote.get("reason","Stand-down unavailable.")); _refresh(); return
	_review("Stand down the field army","Return %d eligible living troops to their home households or reserves in %s?\n%d remain away from their home; %d are dead and cannot return. Injuries and owned equipment remain; returned troops' field payroll stops." % [int(quote.get("eligible",0)),String(quote.get("town_name","this settlement")),int(quote.get("away",0)),int(quote.get("dead",0))],apply_stand_down.bind(town_id,quote.get("review",{})))

func apply_stand_down(tid: String, review: Dictionary) -> Dictionary:
	var outcome: Dictionary = Mobilization.stand_down(Game,tid,review)
	notice = String(outcome.get("reason",outcome.get("message","")))
	if bool(outcome.get("ok",false)):
		notice = "%d living troops stood down. %s" % [int(outcome.get("returned",0)),notice]
		Game.save_game_async()
	_refresh()
	return outcome

func request_refit() -> void:
	var quote: Dictionary = Mobilization.refit_quote(Game,town_id)
	if not bool(quote.get("ok",false)):
		notice = String(quote.get("reason","Refit unavailable.")); _refresh(); return
	_review("Refit army","Fit %d living troops with %d armour pieces (body armour and helmets) from %s?\nPay %s coins from the army purse (%s coins). Armory pieces are borrowed and returned on stand-down; stall pieces are bought. Three days of pay remain reserved." % [int(quote.get("fitted",0)),int(quote.get("pieces",0)),String(quote.get("town_name","this settlement")),coins(quote.get("cost",0)),coins(quote.get("army_gold",0))],apply_refit.bind(town_id,quote.get("review",{})))

func apply_refit(tid: String, review: Dictionary) -> Dictionary:
	var outcome: Dictionary = Mobilization.refit(Game,tid,review)
	notice = String(outcome.get("reason",""))
	if bool(outcome.get("ok",false)):
		notice = "%d living troops refitted. Cost: %s coins. %s" % [int(outcome.get("fitted",0)),coins(outcome.get("cost",0)),notice]
		Game.save_game_async()
	_refresh()
	return outcome

func request_funding() -> void:
	var source: Dictionary = Mobilization.status(Game)
	var amount: float = floorf(fund_input.value)
	if amount <= 0 or not bool(source.get("can_act",false)) or amount > float(source.get("payer_purse",0)):
		notice = "The current ruling household cannot fund this amount."; _refresh(); return
	var review: Dictionary = {"payer_household_uid":source.get("payer_household_uid",""),"authority_person_uid":Dynasty.ruler(Game).get("person_uid","")}
	_review("Fund the army","Transfer %s coins from %s's house purse to the army purse? These funds pay raising, wages and supplies." % [coins(amount),String(source.get("payer_name","the ruling house"))],apply_funding.bind(amount,review))

func apply_funding(amount: float, review: Dictionary) -> Dictionary:
	var source: Dictionary = Mobilization.status(Game)
	if source.get("payer_household_uid","") != review.get("payer_household_uid","") or Dynasty.ruler(Game).get("person_uid","") != review.get("authority_person_uid",""):
		notice = "The ruling household changed. Review the transfer again."; _refresh()
		return {"ok":false,"reason":notice}
	var outcome: Dictionary = Mobilization.fund(Game,amount)
	notice = String(outcome.get("reason",outcome.get("message","")))
	if bool(outcome.get("ok",false)): Game.save_game_async()
	_refresh()
	return outcome

func _roster() -> void:
	Game.goto("company",{"back":"muster","back_params":{"town_id":town_id,"back":back,"back_params":back_params}})

func _back() -> void:
	Game.goto(back,back_params)


func _refresh_mounts() -> void:
	UiKit.clear(mounts_flow)
	var town: Dictionary = Game.world.get("towns", {}).get(Game.location, {})
	var n := Horses.count(Game.company)
	mounts_flow.add_child(UiKit.label("Mounts: %d; upkeep %d grain + %d coins daily" % [n, n * Horses.GRAIN_DAY, n * Horses.COIN_DAY], "H2", true))
	if not TownEcon.has_econ(town):
		mounts_flow.add_child(UiKit.label("Visit a settlement to buy horses and pack grain.", "Muted", true))
		return
	mounts_flow.add_child(UiKit.label("Grown horses: %d offered at %d coins each. An unfed or unpaid mount cannot field cavalry." % [Horses.offered(town["econ"]), Horses.price(town)], "Muted", true))
	var pack := UiKit.button("Pack 7 days of horse grain", func():
		var r := Supplies.pack_horse_grain(Game, town)
		notice = str(r.get("reason", ""))
		_queue_refresh(), "Row", 250)
	pack.disabled = n == 0
	mounts_flow.add_child(pack)
	var riders: Array = Game.company.filter(func(u: Unit): return not u.dead)
	if riders.is_empty(): return
	var row := UiKit.flow(6)
	mounts_flow.add_child(row)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(260, 48)
	for u: Unit in riders:
		var text := "cavalry" if Horses.can_field(u) else ("mount needs care" if u.horse != null else "on foot")
		picker.add_item("%s: %s" % [u.name, text])
	row.add_child(picker)
	var buy := UiKit.button("Buy mount", func():
		var r := Horses.buy(Game, town, riders[picker.selected])
		notice = str(r.get("reason", ""))
		_queue_refresh(), "Row", 130)
	var sell := UiKit.button("Sell mount", func():
		var r := Horses.sell(Game, town, riders[picker.selected])
		notice = str(r.get("reason", ""))
		_queue_refresh(), "Row", 130)
	row.add_child(buy)
	row.add_child(sell)
	var select_rider := func(i: int):
		var q := Horses.quote(Game, town, riders[i])
		buy.disabled = not bool(q["ok"])
		buy.tooltip_text = str(q["reason"])
		sell.disabled = riders[i].horse == null
	picker.item_selected.connect(select_rider)
	select_rider.call(0)
