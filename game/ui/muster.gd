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
var borrow_button: Button
var funding_label: Label # v0.102: keep the next funding step visible beside disabled controls.
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
# v0.102: action refusals also have wrapping text for touch users.
var down_reason_label: Label
var refit_reason_label: Label
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
	(frame["title"] as Label).add_theme_font_size_override("font_size", UiTheme.px(28))
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
	fund_input.custom_minimum_size = Vector2(170, UiKit.touch_min(48))
	fund_input.value_changed.connect(func(_value: float): _queue_refresh())
	funding.add_child(fund_input)
	fund_button = UiKit.button("Review transfer",request_funding,"Row",160); fund_button.name = "MusterFund"
	funding.add_child(fund_button)
	# v0.102: allow a small house to borrow coin from the settlement treasury where the house purse is shown.
	borrow_button = UiKit.button("Borrow coin", request_borrow, "Row", 140); borrow_button.name = "MusterBorrow"
	funding.add_child(borrow_button)
	# v0.102: funding refusals must be readable without hovering a disabled button.
	funding_label = _line(status, "MusterFundingReason", "Muted")
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
	count_input.custom_minimum_size = Vector2(150, UiKit.touch_min(48))
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
	# v0.102: keep reasons below the action row, using the card's full width.
	down_reason_label = _line(settlement, "MusterStandDownReason", "Muted")
	refit_reason_label = _line(settlement, "MusterRefitReason", "Muted")
	mounts_flow = _card("MusterMounts")
	notice_label = _line(body, "MusterNotice")
	# v0.102: default the funding spinbox to an affordable positive amount when the house already has coin.
	var init_purse := floorf(float(Mobilization.status(Game).get("payer_purse", 0.0)))
	if init_purse >= 1.0:
		var init_need := float(Mobilization.quote(Game, town_id, int(count_input.value)).get("required_funding", 0.0))
		fund_input.value = minf(init_purse, ceilf(init_need) if init_need >= 1.0 else 100.0)
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
	var borrow_q: Dictionary = Mobilization.borrow_quote(Game)
	var C := func(v): return UiKit.compact_coins(float(v))
	state_label.text = "Your army is not raised yet" if raised == 0 else "%d soldiers in the field (of %d)" % [int(current_status.get("alive",0)), Mobilization.LIMIT]
	var days: String = Food.days_text(float(current_status.get("food_days",0))) if int(current_status.get("alive",0)) > 0 else "no troops eating"
	wallet_label.text = "Army purse %s · pay %s a day · food %s     House purse %s" % [C.call(current_status.get("army_gold",0)), C.call(current_status.get("daily_pay",0)), days, C.call(current_status.get("payer_purse",0))]
	town_label.text = "Raise troops at " + String(current_quote.get("town_name", "your home"))
	# v0.102: never show zeros from a quote that exited at _gate before counting people, kits or food.
	if not bool(current_quote.get("can_act", false)):
		people_label.text = "Raising is unavailable here: " + String(current_quote.get("reason", ""))
		people_label.tooltip_text = String(current_quote.get("reason", ""))
		limits_label.text = String(current_quote.get("reason", ""))
		cost_label.text = ""
		cost_label.visible = false
	else:
		people_label.text = "You can raise %d of the %d you ask for" % [int(current_quote.get("planned",current_quote.get("available",0))), int(current_quote.get("requested",0))]
		people_label.tooltip_text = "Manpower %d (available %d) · home reserves %d · new recruits %d · kits %d · food %d meals" % [int(current_quote.get("eligible",0)),int(current_quote.get("available",0)),int(current_quote.get("reserve_available",0)),int(current_quote.get("new_available",0)),int(current_quote.get("kit_available",0)),int(current_quote.get("food_available",0))]
		limits_label.text = "Limited by: people %d (ready %d) · kits %d · food %d meals" % [int(current_quote.get("eligible",0)), int(current_quote.get("available",0)), int(current_quote.get("kit_available",0)), int(current_quote.get("food_available",0))]
		cost_label.text = "Raising costs %s now, then %s a day in pay and %.0f meals a day" % [C.call(current_quote.get("raise_cost",0)), C.call(current_quote.get("daily_pay",0)), float(current_quote.get("food_per_day",0))]
		cost_label.visible = true
	payer_label.text = ("Short by %s: fund the army purse or borrow coin first." % C.call(current_quote.get("required_funding",0))) if float(current_quote.get("required_funding",0)) > 0.0 else ""
	payer_label.visible = payer_label.text != ""
	reason_label.text = String(current_quote.get("reason",""))
	raise_button.disabled = not bool(current_quote.get("ok",false))
	raise_button.tooltip_text = String(current_quote.get("reason", ""))
	down_button.disabled = not bool(down_quote.get("ok",false))
	down_button.tooltip_text = "Stand down at home: the same people return to work. " + String(down_quote.get("reason",""))
	refit_button.disabled = not bool(refit_current.get("ok",false))
	refit_button.tooltip_text = "Refit at home: body armour and helmets for soldiers who lack them. " + String(refit_current.get("reason",""))
	# v0.102: show only the native refusal, without the tooltip's extra description.
	down_reason_label.text = "Stand-down: " + String(down_quote.get("reason", "")) if down_button.disabled else ""
	down_reason_label.visible = down_reason_label.text != ""
	refit_reason_label.text = "Refit: " + String(refit_current.get("reason", "")) if refit_button.disabled else ""
	refit_reason_label.visible = refit_reason_label.text != ""
	fund_button.disabled = fund_input.value <= 0 or not bool(current_status.get("can_act",false)) or fund_input.value > float(current_status.get("payer_purse",0))
	fund_button.tooltip_text = fund_refusal(current_status, floorf(fund_input.value)) if fund_button.disabled else "Transfer house coin into the army purse for raising, pay and supplies."
	if borrow_button != null:
		borrow_button.disabled = not bool(borrow_q.get("ok", false))
		borrow_button.tooltip_text = String(borrow_q.get("reason", ""))
	# v0.102: show the blocked transfer/loan and the route from coin to raised troops.
	funding_label.text = fund_button.tooltip_text if fund_button.disabled else "Transfer coin, then use Review raising below. You can march without a family rider or horses."
	if not bool(borrow_q.get("ok", false)):
		funding_label.text += " " + String(borrow_q.get("reason", ""))
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
	# v0.102: refresh absent members' duties/dates even while there are still no candidates.
	if candidates.is_empty() and riding.is_empty(): key = no_riders_text(Dynasty.living_members(Game))
	if key == _house_key: return
	_house_key = key
	UiKit.clear(house_flow)
	if candidates.is_empty() and riding.is_empty():
		house_flow.add_child(UiKit.label(key, "Muted", true))
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

## v0.099 / v0.102: say why nobody can ride, naming who is away, when they return if known, and what to do instead.
static func no_riders_text(members: Array) -> String:
	var who: Array = []
	var field_service := false # v0.102: field service has no scheduled homecoming.
	for row in members:
		var st := str(row.get("state", ""))
		if st in ["army", "militia", "caravan"] and int(row.get("age", 0)) >= int(People.ages(str(row.get("race", "human")))["adult"]):
			var duty := "with the realm's field army" if st == "army" else ("in the town guard" if st == "militia" else "with a caravan")
			if st == "army": field_service = true
			var when := _return_day_text(row)
			var nm := str(row.get("name", "A family member")).strip_edges()
			who.append("%s (%s%s)" % [nm, duty, (", back around day %d" % when) if when > 0 else ""])
	var text := "No adult family members are free to ride with the army."
	if not who.is_empty():
		text += " Away serving: " + ", ".join(who) + "."
	# v0.102: do not promise a return from indefinite realm service or imply an officer is required.
	if field_service: text += " Field-army service has no set return date."
	text += " Raise settlement troops below, or hire men in Town Recruits. A family rider is optional."
	return text

static func _return_day_text(row: Dictionary) -> int:
	if not (Game.get("world") is Dictionary): return -1
	var w: Dictionary = Game.world
	var u_uid := int(row.get("unit_uid", -1))
	if u_uid < 0: return -1
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		for u in wb.get("units", []):
			if u is Unit and u.uid == u_uid:
				# v0.102: an outbound caravan's next arrival is not its crew's return home.
				if str(wb.get("kind", "")) == "caravan" and str(wb.get("leg", "out")) == "home" and wb.get("path", []) is Array and not (wb["path"] as Array).is_empty():
					var steps: int = (wb["path"] as Array).size()
					return int(Game.day) + maxi(1, int(ceil(float(steps) * 16.0 / maxf(1.0, CampaignWorld.WARBAND_SPEED * Caravans.SPEED))))
				return -1
	return -1

func apply_enlist_household(person_uid: String) -> Dictionary:
	var r: Dictionary = Mobilization.enlist_household(Game, person_uid)
	notice = String(r.get("reason", ""))
	if bool(r.get("ok", false)): Game.request_autosave()
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
		# v0.102: even fallback refusals name a recovery step.
		notice = String(quote.get("reason","Raising is unavailable. Return home and review people, supplies and army funds.")); _refresh(); return
	var reviewed: Dictionary = quote.get("review",{})
	_review("Raise an army",raise_text(quote),apply_raise.bind(town_id,int(count_input.value),reviewed))

func apply_raise(tid: String, amount: int, review: Dictionary) -> Dictionary:
	var outcome: Dictionary = Mobilization.muster(Game,tid,amount,review)
	notice = String(outcome.get("reason",""))
	if bool(outcome.get("ok",false)):
		notice = "%d of %d requested troops raised%s. Cost: %s coins. %s" % [int(outcome.get("raised",0)),int(outcome.get("requested",amount))," · partial raising" if bool(outcome.get("partial",false)) else "",coins(outcome.get("cost",0)),notice]
		Game.request_autosave()
	_refresh()
	return outcome

func request_stand_down() -> void:
	var quote: Dictionary = Mobilization.stand_down_quote(Game,town_id)
	if not bool(quote.get("ok",false)):
		# v0.102: stand-down requires the soldiers' actual home settlement.
		notice = String(quote.get("reason","Stand-down is unavailable here. Travel to your soldiers' home and review again.")); _refresh(); return
	_review("Stand down the field army","Return %d eligible living troops to their home households or reserves in %s?\n%d remain away from their home; %d are dead and cannot return. Injuries and owned equipment remain; returned troops' field payroll stops." % [int(quote.get("eligible",0)),String(quote.get("town_name","this settlement")),int(quote.get("away",0)),int(quote.get("dead",0))],apply_stand_down.bind(town_id,quote.get("review",{})))

func apply_stand_down(tid: String, review: Dictionary) -> Dictionary:
	var outcome: Dictionary = Mobilization.stand_down(Game,tid,review)
	notice = String(outcome.get("reason",outcome.get("message","")))
	if bool(outcome.get("ok",false)):
		notice = "%d living troops stood down. %s" % [int(outcome.get("returned",0)),notice]
		Game.request_autosave()
	_refresh()
	return outcome

func request_refit() -> void:
	var quote: Dictionary = Mobilization.refit_quote(Game,town_id)
	if not bool(quote.get("ok",false)):
		# v0.102: a failed refit still points to stock and funding.
		notice = String(quote.get("reason","Refitting is unavailable. Return home and review armour stock and army funds.")); _refresh(); return
	_review("Refit army","Fit %d living troops with %d armour pieces (body armour and helmets) from %s?\nPay %s coins from the army purse (%s coins). Armory pieces are borrowed and returned on stand-down; stall pieces are bought. Three days of pay remain reserved." % [int(quote.get("fitted",0)),int(quote.get("pieces",0)),String(quote.get("town_name","this settlement")),coins(quote.get("cost",0)),coins(quote.get("army_gold",0))],apply_refit.bind(town_id,quote.get("review",{})))

func apply_refit(tid: String, review: Dictionary) -> Dictionary:
	var outcome: Dictionary = Mobilization.refit(Game,tid,review)
	notice = String(outcome.get("reason",""))
	if bool(outcome.get("ok",false)):
		notice = "%d living troops refitted. Cost: %s coins. %s" % [int(outcome.get("fitted",0)),coins(outcome.get("cost",0)),notice]
		Game.request_autosave()
	_refresh()
	return outcome

## v0.102: explain why the army funding transfer is refused and name a next step.
static func fund_refusal(source: Dictionary, amount: float) -> String:
	if not bool(source.get("can_act", false)):
		var r := String(source.get("reason", ""))
		return r if r != "" else "House funding is unavailable here. Travel to your home settlement first."
	var purse := float(source.get("payer_purse", 0.0))
	if purse < 1.0:
		return "Your house purse has no coin to transfer. Borrow coin from the settlement or earn coin first."
	if amount <= 0.0:
		return "No transfer amount is set. Enter at least one coin to move into the army purse."
	if amount > purse:
		return "Your house purse has only %s coins. Choose a smaller amount or borrow coin first." % coins(purse)
	return ""

func request_funding() -> void:
	var source: Dictionary = Mobilization.status(Game)
	var amount: float = floorf(fund_input.value)
	var why := fund_refusal(source, amount)
	if why != "":
		notice = why; _refresh(); return
	var review: Dictionary = {"payer_household_uid":source.get("payer_household_uid",""),"authority_person_uid":Dynasty.ruler(Game).get("person_uid","")}
	_review("Fund the army","Transfer %s coins from %s's house purse to the army purse? These funds pay raising, wages and supplies." % [coins(amount),String(source.get("payer_name","your house"))],apply_funding.bind(amount,review))

func apply_funding(amount: float, review: Dictionary) -> Dictionary:
	var source: Dictionary = Mobilization.status(Game)
	if source.get("payer_household_uid","") != review.get("payer_household_uid","") or Dynasty.ruler(Game).get("person_uid","") != review.get("authority_person_uid",""):
		notice = "The household changed. Review the transfer again."; _refresh()
		return {"ok":false,"reason":notice}
	var outcome: Dictionary = Mobilization.fund(Game,amount)
	notice = String(outcome.get("reason",outcome.get("message","")))
	if bool(outcome.get("ok",false)): Game.request_autosave()
	_refresh()
	return outcome

func request_borrow() -> void:
	var q: Dictionary = Mobilization.borrow_quote(Game)
	if not bool(q.get("ok", false)):
		notice = String(q.get("reason", "Borrowing unavailable. Wait for town income or earn coin instead.")); _refresh(); return
	var need := float(current_quote.get("required_funding", 0.0)) - float(current_status.get("payer_purse", 0.0))
	var default_amt := clampf(ceilf(need) if need >= 1.0 else float(q.get("max_borrow", 100.0)), 1.0, float(q.get("max_borrow", 1.0)))
	var modal := UiKit.modal(self, "Borrow coin for your house", 480)
	modal.add_child(UiKit.label("Borrow real coin from the %s of %s into your house purse.\nCredit left: %s coins · Current debt: %s coins · Weekly interest: %.0f%%" % [
		String(q.get("head_title", "head")), String(q.get("town_name", "this settlement")),
		coins(q.get("credit_left", 0.0)), coins(q.get("debt", 0.0)), float(q.get("rate", 0.0)) * 100.0], "", true))
	var amount := SpinBox.new(); amount.name = "MusterBorrowAmount"
	amount.min_value = 1; amount.max_value = maxf(1.0, floorf(float(q.get("max_borrow", 1.0)))); amount.step = 1
	amount.value = default_amt
	amount.custom_minimum_size = Vector2(170, UiKit.touch_min(48))
	modal.add_child(amount)
	var actions := UiKit.flow(8); modal.add_child(actions)
	actions.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(modal), "Row", 120))
	actions.add_child(UiKit.button("Borrow", func():
		var req := floorf(amount.value)
		UiKit.close_modal(modal)
		apply_borrow(req), "Row", 120))

func apply_borrow(amount: float) -> Dictionary:
	var outcome: Dictionary = Mobilization.borrow(Game, amount)
	notice = String(outcome.get("reason", ""))
	if bool(outcome.get("ok", false)):
		if fund_input != null and fund_input.value <= 0:
			fund_input.value = float(outcome.get("amount", 0.0))
		Game.request_autosave()
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
	# v0.096: a short heading, then the numbers in reading text (no sentence in capitals).
	mounts_flow.add_child(UiKit.label("Mounts", "H2", true))
	mounts_flow.add_child(UiKit.label("Mounts: %d; upkeep %d grain + %s coins daily" % [n, n * Horses.GRAIN_DAY, UiKit.thousands(n * Horses.COIN_DAY)], "", true))
	if not TownEcon.has_econ(town):
		mounts_flow.add_child(UiKit.label("Visit a settlement to buy horses and pack grain.", "Muted", true))
		return
	mounts_flow.add_child(UiKit.label("Grown horses: %d offered at %s coins each. An unfed or unpaid mount cannot field cavalry." % [Horses.offered(town["econ"]), UiKit.thousands(Horses.price(town))], "Muted", true))
	var pack := UiKit.button("Pack 7 days of horse grain", func():
		var r := Supplies.pack_horse_grain(Game, town)
		notice = str(r.get("reason", ""))
		_queue_refresh(), "Row", 250)
	pack.disabled = n == 0
	# v0.102: explain optional horse supplies even when their control is disabled.
	pack.tooltip_text = "Your army has no living horses. Buy a mount first, or march on foot without horse grain." if pack.disabled else "Buy grain from this market using the army purse; one day's soldier meals stay reserved."
	mounts_flow.add_child(pack)
	var riders: Array = Game.company.filter(func(u: Unit): return not u.dead)
	if riders.is_empty():
		mounts_flow.add_child(UiKit.label("No living soldiers can ride. Raise troops above or hire men in Town Recruits first.", "Muted", true))
		return
	var row := UiKit.flow(6)
	mounts_flow.add_child(row)
	var picker := OptionButton.new()
	picker.custom_minimum_size = Vector2(260, UiKit.touch_min(48))
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
		# v0.102: name the missing mount behind a disabled sale button.
		sell.tooltip_text = "This soldier has no mount to sell. Choose a mounted soldier instead." if sell.disabled else "Sell this soldier's living mount to the town treasury."
	picker.item_selected.connect(select_rider)
	select_rider.call(0)
