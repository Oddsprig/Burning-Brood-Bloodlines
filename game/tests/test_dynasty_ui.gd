extends RefCounted
## Direct logical phone widths, rotation, real native identities and map clearance.
## Run only through the isolated native test runner. No input injection or saves.
var tree: SceneTree
var fails := 0

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var fixture = load("res://tests/test_dynasty_foundation.gd").new()
	fixture.fixture()
	Dynasty.prepare_world(Game)
	Feudal.prepare_world(Game)
	Game.contract = {}
	var choices: Array = Dynasty.choices(Game)
	if choices.is_empty():
		printerr("dynasty UI: fixture has no real registered ruling house")
		return 1
	_assert(Dynasty.select_city(Game, String(choices[0]["town_id"])), "native house selected")
	var fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var saved_world := Game.world.duplicate(true)
	for path in ["res://ui/title.tscn", "res://ui/newgame.tscn", "res://ui/presim.tscn", "res://ui/house_select.tscn", "res://ui/house.tscn", "res://ui/politics.tscn", "res://ui/population.tscn", "res://campaign/world_map.tscn", "res://ui/settings.tscn", "res://ui/company.tscn", "res://ui/records.tscn", "res://ui/town.tscn"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(390, 844)
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		tree.root.add_child(viewport)
		Game.screen_params = {"back": "map", "town_id": String(choices[0]["town_id"])}
		if path.ends_with("town.tscn"):
			Game.location = String(choices[0]["town_id"])
		var screen: Node = (load(path) as PackedScene).instantiate()
		viewport.add_child(screen)
		screen.set_process(false)
		for dimensions in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(390, 844)]:
			viewport.size = dimensions
			await _settle()
			fit._check(viewport, Vector2(dimensions), "Bloodlines " + path.get_file())
			if path.ends_with("town.tscn"):
				for town_tab in ["Market", "Provisions", "Recruits", "Healer", "Contracts", "Town"]:
					screen.show_tab(town_tab)
					await _settle()
					fit._check(viewport, Vector2(dimensions), "Bloodlines city " + town_tab)
				for section in ["People", "Work", "Stores", "Accounts"]:
					var dashboard: Node = screen.page.get_child(0)
					var section_body: VBoxContainer = dashboard.find_child("TownSection", true, false)
					TownEconTab._select_section(screen, screen.town(), section_body, section)
					await _settle()
					fit._check(viewport, Vector2(dimensions), "Bloodlines native city " + section)
			if path.ends_with("house.tscn"):
				_assert(screen.accounts_grid.columns == (1 if dimensions.x < 600 else 2), "accounts rotate")
			if path.ends_with("politics.tscn") or path.ends_with("population.tscn"):
				var heading: Label = screen.find_child("Title", true, false)
				var expected := "Realm politics" if path.ends_with("politics.tscn") else "Population"
				_assert(heading != null and heading.text == expected, "civic view retains full title")
				if heading != null:
					var font: Font = heading.get_theme_font("font")
					var font_size := heading.get_theme_font_size("font_size")
					var title_width := font.get_string_size(expected, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
					_assert(heading.size.x + 1 >= title_width, "civic header fits every title glyph after rotation")
					_assert(heading.get_global_rect().end.x <= dimensions.x + 1, "full civic title stays inside viewport")
			if path.ends_with("politics.tscn"):
				_assert(screen.hierarchy_rows.size() == Game.world["factions"][screen.faction_id]["towns"].size(), "every faction settlement remains in hierarchy")
			if path.ends_with("population.tscn"):
				var population: Dictionary = Population.summary(Game.world["towns"][screen.town_id]["econ"])
				_assert(screen.population_summary == population, "population page shows native counts and private wealth")
				_assert(screen.race_grid.columns == (1 if dimensions.x < 600 else 2), "race population cards rotate")
				var counted := 0
				for race: Dictionary in screen.races: counted += int(race["population"])
				_assert(counted == int(population["population"]), "race cards count all residents once")
			if path.ends_with("world_map.tscn"):
				_assert(not screen.lbl_contract.visible, "empty contract uses no HUD row")
				_assert(screen.lbl_contract.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "active contract wraps within viewport")
				if dimensions.x > dimensions.y:
					_assert(screen.top_panel.size.y <= 112, "landscape map keeps compact header")
					_assert(not screen.lbl_wages.visible, "landscape uses one account summary")
					for owner in ["House ", "City ", "Faction ", "Army ", " troops"]:
						_assert(owner in screen.lbl_gold.text + "
" + screen.lbl_gold.tooltip_text, "landscape summary retains " + owner.strip_edges())
				else:
					_assert("City treasury" in screen.lbl_gold.tooltip_text, "portrait keeps every separate account in reach")
				_assert(not screen.ruler_card.get_global_rect().intersects(screen.lbl_log.get_global_rect()), "ruler portrait clears log")
				_assert(not screen.ruler_card.get_global_rect().intersects(screen.bottom_nav.get_global_rect()), "ruler portrait clears navigation")
				_assert(not screen.lbl_log.get_global_rect().intersects(screen.bottom_nav.get_global_rect()), "log clears navigation")
				_assert(screen.ruler_card.portrait._spec == Dynasty.portrait_spec(Game), "portrait matches actual selected ruler")
				_assert(screen.ruler_card.custom_minimum_size.y >= 48, "portrait tap target")
				_assert(screen.info_panel.size.x <= dimensions.x - 16, "selection sheet width")
				_assert(screen.enc_panel.size.x <= dimensions.x - 16, "encounter sheet width")
				Game.world["warbands"]["suspended_ui"] = {"id": "suspended_ui", "kind": "beasts", "faction": "", "units": []}
				Game.world["encounter"] = "suspended_ui"
				screen._show_encounter("suspended_ui")
				_assert(not screen.enc_panel.visible and Game.world["encounter"] == "", "stale suspended creature encounter cannot trap map")
				Game.world["warbands"].erase("suspended_ui")
		viewport.queue_free()
		screen = null
		viewport = null
		await _settle()
	# Map entry moves the native party from its city gate; account/identity reads
	# and new pages themselves must not write household money or identity.
	var before_accounts: Dictionary = Dynasty.accounts(Game)
	var before_selection: Dictionary = Dynasty.selected(Game)
	var first_ruler: Dictionary = Dynasty.ruler(Game)
	var page = load("res://ui/house.gd").new()
	var view := SubViewport.new()
	view.size = Vector2i(390, 844)
	tree.root.add_child(view)
	view.add_child(page)
	page._show_person(first_ruler)
	await _settle()
	fit._check(view, Vector2(390, 844), "Bloodlines actual ruler detail")
	UiKit.confirm(page, "Transfer the recorded household coins? Review the true owner and exact amount before confirming.", "Confirm", func(): pass)
	await _settle()
	fit._check(view, Vector2(390, 844), "Bloodlines bounded phone confirmation")
	view.size = Vector2i(844, 390)
	await _settle()
	fit._check(view, Vector2(844, 390), "Bloodlines bounded rotated confirmation")
	_assert(before_accounts == Dynasty.accounts(Game), "UI preserves account owners and amounts")
	_assert(before_selection == Dynasty.selected(Game), "UI preserves selected native identity")
	_assert(saved_world["player_house"] == Game.world["player_house"], "rotation preserves ruling household")
	view.queue_free()
	page = null
	view = null
	await _settle()
	await _political_actions(fit)
	var orphan_final := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_assert(orphan_final <= orphan_baseline, "UI cleanup leaves no new orphan nodes (%d -> %d)" % [orphan_baseline, orphan_final])
	# Use the native cache lifecycle after all owning map screens have gone.
	# This releases legitimate cross-screen art caches before the runner quits;
	# it does not hide or filter renderer/ObjectDB diagnostics.
	load("res://campaign/map_terrain.gd").free_cache()
	MapTokens.clear_cache()
	var result: int = fails + int(fit.fails)
	fit.tree = null
	fit = null
	fixture = null
	saved_world.clear()
	choices.clear()
	before_accounts.clear()
	before_selection.clear()
	first_ruler.clear()
	await _settle()
	tree = null
	return result

func _political_actions(fit) -> void:
	# Real small register, native genealogy and mutations, no full world generation.
	var fixture = load("res://tests/test_feudal_succession.gd").new()
	fixture.fixture()
	Game.location = ""
	var view := SubViewport.new()
	view.size = Vector2i(390, 844)
	tree.root.add_child(view)
	Game.screen_params = {"town_id": "county", "back": "map", "return_location": ""}
	var politics = load("res://ui/politics.gd").new()
	view.add_child(politics)
	await _settle()
	fit._check(view, Vector2(390, 844), "Bloodlines actionable hierarchy")
	var total: float = fixture.total_coin()
	var county: Dictionary = Game.world["towns"]["county"]
	var city_coins := float(county["econ"]["treasury"])
	var population_before: Dictionary = Population.summary(county["econ"])
	var grant: Dictionary = politics._apply_action("grant")
	_assert(bool(grant.get("ok", false)), "UI grant reaches native vassal payment")
	var purse_after_grant := float(Feudal.tax_recipient(Game, "county")["purse"])
	var denied: Dictionary = politics._apply_action("pressure")
	_assert(not bool(denied.get("ok", true)) and float(Feudal.tax_recipient(Game, "county")["purse"]) == purse_after_grant, "UI rejects unavailable action without spending")
	Game.day = 8
	_assert(bool(politics._apply_action("pressure").get("ok", false)), "UI pressure reaches native intrigue")
	Game.day = 16
	Game.world["feudal"]["towns"]["county"]["loyalty"] = 30.0
	var oath: Dictionary = politics._apply_action("swear", "moon_court")
	_assert(bool(oath.get("ok", false)) and county["faction"] == "moon_court", "UI oath transfers settlement to actual destination realm")
	_assert(politics.faction_id == "moon_court" and politics.hierarchy_rows.size() == 2, "UI hierarchy reflects new allegiance")
	_assert(absf(float(county["econ"]["treasury"]) - city_coins) < 0.000001, "private political actions leave municipal treasury separate")
	_assert(absf(fixture.total_coin() - total) < 0.000001, "political UI mutations conserve actual coin")
	_assert(population_before["population"] == Population.summary(county["econ"])["population"], "defection preserves native residents")
	await _settle()
	view.size = Vector2i(844, 390)
	await _settle()
	fit._check(view, Vector2(844, 390), "Bloodlines defection result landscape")
	view.queue_free()
	politics = null
	view = null
	await _settle()
	# A real eligible minor, then native succession, updates the actual map portrait.
	var econ: Dictionary = Game.world["towns"]["seat"]["econ"]
	var family: Dictionary = econ["fams"][0]
	var parent: Array = family["pp"][0]
	var heir: Array = fixture.child(econ, family, 1, 0, 12, parent, "Young successor")
	Dynasty.prepare_world(Game)
	view = SubViewport.new()
	view.size = Vector2i(390, 844)
	tree.root.add_child(view)
	Game.screen_params = {"back": "map"}
	var house = load("res://ui/house.gd").new()
	view.add_child(house)
	Persons.remove(family, parent, econ)
	Dynasty.succession_day(Game)
	Feudal.prepare_world(Game)
	Game.changed.emit()
	await _settle()
	var card: DynastyCard = _ruler_card(house)
	_assert(card != null and card.ruler_name.text == "Young successor", "successor replaces the displayed ruler")
	_assert(card != null and card.portrait._spec == Dynasty.portrait_spec(Game), "successor portrait uses real person spec")
	_assert(card != null and card.office_state.text == "MINOR RULER", "actual regency appears on ruler card")
	_assert(Dynasty.ruler(Game).get("person_uid", "") == heir[Persons.PERSON_UID], "UI follows real succession identity")
	var accounts: Dictionary = Dynasty.accounts(Game)
	_assert(bool(house._apply_funding(100.0).get("ok", false)), "UI army funding uses authoritative real transfer")
	var funded: Dictionary = Dynasty.accounts(Game)
	_assert(absf(float(funded["house_purse"]) - float(accounts["house_purse"]) + 100) < 0.000001 and absf(float(funded["company_wallet"]) - float(accounts["company_wallet"]) - 100) < 0.000001, "army funding changes exactly the two owned purses")
	await _settle()
	fit._check(view, Vector2(390, 844), "Bloodlines inherited house and funding")
	view.queue_free()
	house = null
	card = null
	view = null
	fixture = null
	await _settle()

func _ruler_card(node: Node) -> DynastyCard:
	if node is DynastyCard: return node as DynastyCard
	for child in node.get_children():
		var card := _ruler_card(child)
		if card != null: return card
	return null

func _settle() -> void:
	for _frame in range(5):
		await tree.process_frame

func _assert(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
		printerr("dynasty UI: " + label)
