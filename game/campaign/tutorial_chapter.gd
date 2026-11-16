class_name TutorialChapter
extends RefCounted
## v0.104: glue for the data chapter. All money, people and travel stay in native commands.

static func host_of(screen: Node) -> Control:
	if screen is Control:
		return screen as Control
	if is_instance_valid(screen) and screen.has_method("tutorial_host"):
		return screen.call("tutorial_host") as Control
	return null

static func screen_now() -> Node:
	# v0.104: keep the null guard separate from the cast for the first script parse.
	if not is_instance_valid(Game.main):
		return null
	return Game.main.get("current") as Node

static func resume() -> void:
	if not Game.tutorial_chapter or Game.tutorial_done:
		return
	if Game._active_screen not in ["house_select", "house", "muster", "map"]:
		return
	var screen := screen_now()
	var host := host_of(screen)
	if not is_instance_valid(host) or host.get_node_or_null("TutorialOverlay") != null:
		return
	var pending: Variant = host.get_meta("tutorial_pending") if host.has_meta("tutorial_pending") else null
	if is_instance_valid(pending) and not pending.is_queued_for_deletion():
		return # v0.104: several deferred Game.goto callbacks must not attach duplicate overlays.
	# Pre-Begin selections are unsaved UI drafts. Resume them at the settlement list.
	if Game.world.get("player_house", {}).is_empty():
		Game.tutorial_step = 0
	var steps := Tutorial.load_steps()
	if steps.is_empty():
		return
	var at := clampi(Game.tutorial_step, 0, steps.size() - 1)
	# v0.104: modal inputs are UI drafts. Resume at their editable review boundary.
	if String(steps[at]["id"]) in ["borrow_coin", "confirm_borrow"]:
		# v0.104: UI drafts are not saved; enough real House coin skips a second loan.
		var first := at if String(steps[at]["id"]) == "borrow_coin" else at - 1
		at = first if borrowing_needed() else first + 2
	elif String(steps[at]["id"]) == "confirm_funding":
		var quote := Mobilization.quote(Game, String(Dynasty.selected(Game).get("town_id", "")), 1)
		at = at + 1 if Game.gold > 0 and bool(quote.get("ok", false)) else at - 1
	elif String(steps[at]["id"]) == "confirm_muster":
		at = at + 1 if Game.company.any(func(unit): return not unit.dead) else at - 1
	Game.tutorial_step = at
	var wanted := String(steps[at].get("host", ""))
	if wanted != Game._active_screen:
		_go(wanted)
		return
	var tutorial := Tutorial.new()
	tutorial.setup(steps)
	tutorial.bind_game(Game)
	tutorial.start_saved()
	# v0.104: explicit lambdas avoid bare static Callables without capturing the RefCounted tutorial.
	tutorial.step_changed.connect(func(index: int): TutorialChapter._prepare_step(index))
	var view := TutorialOverlay.open(host, tutorial)
	host.set_meta("tutorial_pending", view)
	view.state_of = func(key: String) -> Variant: return TutorialChapter.state_of(key)
	tutorial.completed.connect(func(skipped: bool): TutorialChapter._completed(skipped))
	_prepare_step(tutorial.index, tutorial)

static func _go(screen: String) -> void:
	Game.goto(screen, {"back": "house", "back_params": {"back": "map"}} if screen == "muster" else {"back": "map"})

# v0.104: use the native one-soldier shortfall; a loan never funds the Army wallet.
static func borrowing_needed() -> bool:
	var home := String(Dynasty.selected(Game).get("town_id", ""))
	var quote := Mobilization.quote(Game, home, 1)
	var purse := int(floor(float(Mobilization.status(Game).get("payer_purse", 0.0))))
	return int(quote.get("required_funding", 0)) > purse

static func _loan_state() -> Dictionary:
	# v0.104: observe the selected native account; only the screen's Borrow command writes it.
	var uid := String(Dynasty.selected(Game).get("household_uid", ""))
	var family: Dictionary = Dynasty._household(Game, uid).get("family", {})
	return {"household_uid": uid, "purse": float(family.get("purse", 0.0)),
		"debt": float(family.get("debt", 0.0)), "lent": float(family.get("ln", {}).get("lent", 0.0)),
		"army": Game.gold}

static func _review_is(screen: Node, order: String) -> bool:
	# v0.104: borrowing and raising must never satisfy the Army-transfer review.
	var modal := screen.find_child("MusterReview", true, false)
	return is_instance_valid(modal) and not modal.is_queued_for_deletion() and String(modal.get_meta("tutorial_order", "")) == order

static func _cancelled_borrow() -> void:
	# v0.104: native Cancel returns to the button, without opening or executing a loan.
	var host := host_of(screen_now())
	if not is_instance_valid(host): return
	var view := host.get_node_or_null("TutorialOverlay") as TutorialOverlay
	if view != null and String(view.tutorial.current().get("id", "")) == "confirm_borrow":
		view.call_deferred("_on_back") # v0.104: never change steps reentrantly inside the overlay poll.

static func _prepare_step(_index: int, tutorial: Tutorial = null) -> void:
	if tutorial == null:
		var host := host_of(screen_now())
		var view: TutorialOverlay = null # v0.104: no conditional cast/type inference on a nullable host.
		if is_instance_valid(host):
			view = host.get_node_or_null("TutorialOverlay") as TutorialOverlay
		if view == null: return
		tutorial = view.tutorial as Tutorial
	var step := tutorial.current()
	var wanted := String(step.get("host", ""))
	if wanted != "" and wanted != Game._active_screen:
		_go(wanted)
	var screen := screen_now()
	if not is_instance_valid(screen):
		return
	var id := String(step.get("id", ""))
	if wanted == "house_select":
		# Back changes the native draft stage; it never re-commits a selected household.
		var last_stage := 0 if id in ["choose_settlement", "settlement_continue"] else (1 if id == "choose_house" else 3)
		while int(screen.get("stage")) > last_stage and id != "begin_house":
			screen.call("previous_stage")
	if wanted == "muster":
		# v0.104: the v0.102 Borrow form has its own anchor, separate from native order reviews.
		var borrowing := screen.find_child("MusterBorrowReview", true, false)
		if id != "confirm_borrow" and is_instance_valid(borrowing):
			UiKit.close_modal(borrowing)
		if id == "borrow_coin":
			if screen.has_meta("tutorial_loan_before"): screen.remove_meta("tutorial_loan_before")
			if not borrowing_needed():
				tutorial.start(tutorial.index + 2) # v0.104: keep stable data indices when no loan is needed.
				return
		elif id == "confirm_borrow":
			if not is_instance_valid(borrowing) or borrowing.is_queued_for_deletion():
				tutorial.back_step()
				return
			screen.set_meta("tutorial_loan_before", _loan_state())
		var modal := screen.find_child("MusterReview", true, false)
		if id in ["choose_men", "borrow_coin", "fund_army", "raise_army", "return_house"] and is_instance_valid(modal):
			UiKit.close_modal(modal)
		# Back after a transfer returns to its editable amount; it never replays the committed transfer.
		if id == "confirm_funding" and not is_instance_valid(modal):
			tutorial.back_step()
		elif id == "confirm_muster" and not is_instance_valid(modal):
			screen.call("request_raise")
			modal = screen.find_child("MusterReview", true, false)
		# v0.104: an existing wallet/company must not turn a cancelled review into a completed order.
		if id == "confirm_funding" and _review_is(screen, "Fund the army"):
			screen.set_meta("tutorial_funding_gold", Game.gold)
		elif id == "confirm_muster" and _review_is(screen, "Raise an army"):
			screen.set_meta("tutorial_muster_uids", Game.company.map(func(unit): return unit.uid))

static func state_of(key: String) -> Variant:
	var screen := screen_now()
	if not is_instance_valid(screen):
		return false
	match key:
		"settlement_selected":
			return Game._active_screen == "house_select" and String(screen.get("selected_town")) != ""
		"houses_open":
			return Game._active_screen == "house_select" and int(screen.get("stage")) >= 1
		"house_selected":
			return Game._active_screen == "house_select" and String(screen.get("selected_house")) != ""
		"review_ready":
			return Game._active_screen == "house_select" and int(screen.get("stage")) == HouseSelectView.STAGE_REVIEW
		"borrowing_review":
			var borrowing := screen.find_child("MusterBorrowReview", true, false)
			return Game._active_screen == "muster" and is_instance_valid(borrowing) and not borrowing.is_queued_for_deletion()
		"house_borrowed":
			if Game._active_screen != "muster" or not screen.has_meta("tutorial_loan_before"):
				return false
			var before: Dictionary = screen.get_meta("tutorial_loan_before")
			var after := _loan_state()
			var lent := float(after["lent"]) - float(before["lent"])
			if screen.find_child("MusterBorrowReview", true, false) != null:
				return false
			if lent <= 0.0:
				_cancelled_borrow()
				return false
			return after["household_uid"] == before["household_uid"] and after["army"] == before["army"] and is_equal_approx(float(after["purse"]) - float(before["purse"]), lent) and is_equal_approx(float(after["debt"]) - float(before["debt"]), lent)
		"funding_review":
			return Game._active_screen == "muster" and _review_is(screen, "Fund the army")
		"army_funded":
			return Game._active_screen == "muster" and screen.has_meta("tutorial_funding_gold") and Game.gold > int(screen.get_meta("tutorial_funding_gold")) and screen.find_child("MusterReview", true, false) == null
		"army_raised":
			if Game._active_screen != "muster" or not screen.has_meta("tutorial_muster_uids"):
				return false
			var before: Array = screen.get_meta("tutorial_muster_uids")
			return Game.company.any(func(unit): return not unit.dead and not before.has(unit.uid)) and screen.find_child("MusterReview", true, false) == null
		"march_started":
			var party: Dictionary = Game.world.get("party", {})
			return Game.company.any(func(unit): return not unit.dead) and CampaignWorld.is_travelling(Game) and String(party.get("dest_town", "")) != "" and String(party.get("dest_town", "")) != String(Game.world.get("start_town", ""))
	return false

static func _completed(_skipped: bool) -> void:
	Game.request_autosave() # v0.104: keep Skip/completion even if no further campaign day passes.
