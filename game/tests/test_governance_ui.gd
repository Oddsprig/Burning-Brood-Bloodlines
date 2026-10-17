extends RefCounted
## Desktop-only governance UI. Native small economies; no generation or phone QA.
var tree: SceneTree
var checks := 0
var fails := 0
var fit_cases := 0
const DESKTOP := Vector2i(1280, 720)

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var fixture = load("res://tests/test_dynasty_foundation.gd").new()
	fixture.fixture()
	Feudal.prepare_world(Game)
	_assert(Dynasty.select_city(Game, "city_a"), "select existing sovereign household")
	Game.contract = {}
	var payer: Dictionary = Dynasty._household(Game, String(Dynasty.selected(Game)["household_uid"]))["family"]
	payer["purse"] = 1000.0
	var town: Dictionary = Game.world["towns"]["city_a"]
	town["econ"]["stats"]["estate_tax_received"] = 12.34
	town["econ"]["stats"]["estate_tax_day"] = 0
	# One real promoted resident, created through the ordinary native family draw.
	var rng := RandomNumberGenerator.new(); rng.seed = 843
	var soldier := Militia.make_unit(town, rng)
	_assert(soldier.family >= 0, "militia fixture binds an actual eligible resident")
	Game.world["militia"] = {"city_a": "governance_ui_militia"}
	Game.world["warbands"]["governance_ui_militia"] = {"id": "governance_ui_militia", "home": "city_a", "kind": "militia", "faction": "middle_kingdom", "units": [soldier], "pos": town["pos"], "path": [], "mustered": false, "drill_today": false}
	TownDefence.set_muster(Game, town, false)
	var fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for path in ["res://ui/politics.tscn", "res://ui/population.tscn", "res://ui/house.tscn", "res://campaign/world_map.tscn"]:
		Game.screen_params = {"town_id": "city_a", "back": "map", "return_location": "", "back_params": {"checked": true}}
		Game.location = ""
		var viewport := SubViewport.new(); viewport.size = DESKTOP
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		var page: Node = (load(path) as PackedScene).instantiate()
		viewport.add_child(page); page.set_process(false)
		await _settle()
		_fit_check(fit, viewport, "v003 desktop " + path.get_file())
		if path.ends_with("world_map.tscn"):
			for word in ["House ", "City ", "Faction ", "Army ", "Pay ", "unpaid"]:
				_assert(word in page.lbl_gold.text + "
" + page.lbl_gold.tooltip_text, "map exposes actual account/pay " + word.strip_edges())
			_assert(not page.ruler_card.get_global_rect().intersects(page.bottom_nav.get_global_rect()), "map ruler clears desktop navigation")
		else:
			var values: Dictionary = Feudal.budget(Game, "city_a")
			_assert(page.budget == values, "view reads current authoritative fiscal values")
			var text := _labels(page)
			_assert("Current monthly estimate" in text and "Last receipt 12.34" in text, "estimate is distinct from actual levy")
			_assert("house purse" in text and "city treasury" in text and "faction treasury" in text, "private levy and public military pay owners are labelled")
			_assert("1 militia" in text and "Settlement food reserve:" in text, "real service people and food reserve are visible")
			if path.ends_with("politics.tscn"):
				await _orders(page, viewport, fit, payer, soldier)
			elif path.ends_with("population.tscn"):
				_assert(page.population_summary == Population.summary(town["econ"]), "population counts remain authoritative after orders")
				_assert("Away in service" in text and "Can recruit" in text, "resident service and real recruiting capacity are distinct")
				_check_back(page)
		viewport.queue_free(); page = null; viewport = null
		await _settle()
	# Readers and UI callbacks are tested against the backend's current owner,
	# rather than a copied purse remembered before an office change.
	await _current_ruler(fit)
	_assert(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_baseline, "desktop screens and cancelled modals leave no new orphan nodes")
	load("res://campaign/map_terrain.gd").free_cache()
	MapTokens.clear_cache()
	var result: int = fails + int(fit.fails)
	print("Governance UI: %d assertions, %d assertion failures; %d desktop fit cases, %d fit failures." % [checks, fails, fit_cases, int(fit.fails)])
	fit.tree = null; fit = null; fixture = null
	payer = {}; town = {}; soldier = null
	await _settle()
	tree = null
	return result

func _orders(page, viewport: SubViewport, fit, payer: Dictionary, soldier: Unit) -> void:
	var before := _snapshot()
	var preview: Dictionary = Feudal.governance_preview(Game, "city_a", "fund_garrison", 125.5)
	_assert(bool(preview.get("ok", false)), "real city funding is available")
	_assert(preview["payer_household_uid"] == payer["household_uid"] and preview["recipient_id"] == "city_a" and preview["recipient_account"] == "town_treasury", "funding preview names actual private source and city recipient")
	_assert("city treasury" in PoliticsView.governance_text("city_a", preview), "confirmation names recipient account")
	page._request_governance("city_a", "fund_garrison", 125.5)
	await _settle()
	_fit_check(fit, viewport, "v003 desktop funding confirmation")
	var cancel := _button(page.find_child("Modal", true, false), "Cancel")
	_assert(cancel != null, "funding confirmation has reachable Cancel")
	if cancel != null: cancel.pressed.emit()
	await _settle()
	_assert(_snapshot() == before, "preview and Cancel preserve all native money, people and policy")
	# Spending after review must be caught by command-time revalidation.
	page._request_governance("city_a", "fund_garrison", 125.5)
	await _settle()
	var saved := float(payer["purse"]); payer["purse"] = 0.0
	var treasury := float(Game.world["towns"]["city_a"]["econ"]["treasury"])
	var confirm := _button(page.find_child("Modal", true, false), "Confirm order")
	_assert(confirm != null, "reviewed transfer has a concrete confirmation")
	if confirm != null: confirm.pressed.emit()
	await _settle()
	_assert(float(payer["purse"]) == 0.0 and float(Game.world["towns"]["city_a"]["econ"]["treasury"]) == treasury and "cannot afford" in page.notice, "confirmation rejects stale affordability without money creation")
	payer["purse"] = saved
	var private_before := float(payer["purse"])
	var result: Dictionary = page._apply_governance("city_a", "fund_garrison", 125.5)
	_assert(bool(result["ok"]) and is_equal_approx(float(payer["purse"]), private_before - 125.5) and is_equal_approx(float(Game.world["towns"]["city_a"]["econ"]["treasury"]), treasury + 125.5), "confirmed city transfer conserves exact native coin")
	var faction_before := float(Game.world["factions"]["middle_kingdom"]["treasury"])
	private_before = float(payer["purse"])
	result = page._apply_governance("city_a", "fund_realm_army", 45.25)
	_assert(bool(result["ok"]) and is_equal_approx(float(payer["purse"]), private_before - 45.25) and is_equal_approx(float(Game.world["factions"]["middle_kingdom"]["treasury"]), faction_before + 45.25), "sovereign realm funding conserves private/public balances")
	var quote: Dictionary = Feudal.budget(Game, "city_a")["tax_quote"]
	var rate := 0.02 if not is_equal_approx(float(quote["rate"]), 0.02) else 0.10
	before = _snapshot()
	page._request_governance("city_a", "tax_policy", rate)
	await _settle()
	cancel = _button(page.find_child("Modal", true, false), "Cancel")
	if cancel != null: cancel.pressed.emit()
	await _settle()
	_assert(_snapshot() == before, "tax preview/Cancel neither decrees nor collects")
	var coin_before := Barge.holdings(Game)
	result = page._apply_governance("city_a", "tax_policy", rate)
	_assert(bool(result["ok"]) and is_equal_approx(Barge.common_tax_rate(Game.world["towns"]["city_a"]["econ"]), rate), "tax order updates saved native rate")
	_assert(is_equal_approx(Barge.holdings(Game), coin_before), "tax decree does not book its estimate as revenue")
	result = page._apply_governance("city_a", "tax_policy", 0.05 if not is_equal_approx(rate, 0.05) else 0.10)
	_assert(not bool(result["ok"]) and "week" in String(result["reason"]), "tax command revalidates weekly decree limit")
	var uid := soldier.uid
	var next_unit := Unit._next_uid
	var residents := int(Population.summary(Game.world["towns"]["city_a"]["econ"])["population"])
	for order in ["muster", "stand_down", "auto_defence"]:
		result = page._apply_governance("city_a", order)
		_assert(bool(result["ok"]) and TownDefence.defence_policy(Game, Game.world["towns"]["city_a"]) == order, "defence command persists " + order)
		_assert(Militia.units_of(Game, "city_a").size() == 1 and Militia.units_of(Game, "city_a")[0].uid == uid and Unit._next_uid == next_unit, "defence order reuses existing individual; no invented army")
		_assert(int(Population.summary(Game.world["towns"]["city_a"]["econ"])["population"]) == residents, "defence order counts the resident once")
	# The queued action stays attached to the reviewed seat, not today's display.
	page._select("city_b")
	var target_before := float(Game.world["towns"]["city_b"]["econ"]["treasury"])
	result = page._apply_governance("city_a", "fund_garrison", 1.0)
	_assert(bool(result["ok"]) and float(Game.world["towns"]["city_b"]["econ"]["treasury"]) == target_before, "changing displayed town cannot redirect a reviewed transfer")
	# Loss of political authority after review cannot carry an old permission.
	page._select("city_a")
	page._request_governance("city_b", "fund_garrison", 2.0)
	await _settle()
	var feudal_row: Dictionary = Game.world["feudal"]["towns"]["city_b"]
	var original_liege := String(feudal_row["liege_town_id"])
	feudal_row["liege_town_id"] = ""
	before = _snapshot()
	confirm = _button(page.find_child("Modal", true, false), "Confirm order")
	_assert(confirm != null, "vassal funding was reviewable before authority changed")
	if confirm != null: confirm.pressed.emit()
	await _settle()
	_assert(_snapshot() == before and "authority" in page.notice, "confirmation revalidates current liege authority")
	feudal_row["liege_town_id"] = original_liege
	page._refresh()
	await _settle()
	_fit_check(fit, viewport, "v003 desktop governance readback")
	_check_back(page)

func _current_ruler(fit) -> void:
	var fixture = load("res://tests/test_feudal_succession.gd").new()
	fixture.fixture()
	# Supply ordinary food-store fields absent from this genealogy-only fixture.
	for town in Game.world["towns"].values():
		town["econ"]["granary"] = 0.0
		town["econ"]["barn"] = {}
	var econ: Dictionary = Game.world["towns"]["seat"]["econ"]
	var family: Dictionary = econ["fams"][0]
	var ruler: Array = family["pp"][0]
	var heir: Array = fixture.child(econ, family, 1, 0, 30, ruler, "Actual successor")
	Dynasty.prepare_world(Game)
	Persons.remove(family, ruler, econ); Dynasty.succession_day(Game)
	Game.location = "county"
	Game.screen_params = {"town_id": "seat", "back": "map", "return_location": "county"}
	var viewport := SubViewport.new(); viewport.size = DESKTOP
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var page: Node = (load("res://ui/politics.tscn") as PackedScene).instantiate()
	viewport.add_child(page)
	await _settle()
	_fit_check(fit, viewport, "v003 desktop actual successor budget")
	_assert(Dynasty.ruler(Game)["person_uid"] == heir[Persons.PERSON_UID] and page.budget["lord_name"] == "Actual successor" and "Actual successor's house purse" in _labels(page), "tax recipient and fiscal labels follow actual succession")
	var before := _snapshot()
	page._request_governance("foreign", "fund_realm_army", 10.0)
	await _settle()
	_assert(page.find_child("Modal", true, false) == null and _snapshot() == before, "foreign funding shows authoritative reason without a false confirmation")
	_check_back(page)
	viewport.queue_free(); viewport = null; page = null; fixture = null
	await _settle()

func _check_back(page) -> void:
	var origin := String(page.return_location)
	var party: Variant = Game.world.get("party", {}).get("pos")
	page._back()
	_assert(Game.location == origin and Game.world.get("party", {}).get("pos") == party, "Back restores browsing context without party teleport")

func _snapshot() -> String:
	return JSON.stringify({"world": Game._serialize(Game.world), "gold": Game.gold, "next_unit": Unit._next_uid})

func _button(node: Node, text: String) -> Button:
	if node == null: return null
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _labels(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): text += _labels(child)
	return text

func _settle() -> void:
	for _i in 5: await tree.process_frame

func _fit_check(fit, viewport: SubViewport, label: String) -> void:
	fit_cases += 1
	fit._check(viewport, Vector2(DESKTOP), label)

func _assert(ok: bool, label: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("governance UI: ", label)
