extends RefCounted
## One short headless batch for the three v0.095 fixes; native registers, no presimulation.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0

class RouteProbe extends Node:
	var current: Node = null
	func show_screen(_path: String) -> void: pass

class PoliticsProbe extends PoliticsView:
	func _refresh() -> void: pass   # Exercise the real route handlers without building presentation.

class RecordsProbe:
	extends "res://ui/records.gd"
	func _draw_body() -> void: pass

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v095: ", message)

func politics_page() -> PoliticsProbe:
	var page := PoliticsProbe.new()
	var p: Dictionary = Game.screen_params
	page.town_id = str(p["town_id"])
	page.back = str(p["back"])
	page.return_location = str(p["return_location"])
	page.back_params = p.get("back_params", {}).duplicate(true)
	return page

func records_page() -> RecordsProbe:
	var page := RecordsProbe.new()
	var p: Dictionary = Game.screen_params
	page.view = str(p["view"])
	page.sel = str(p["id"])
	page.tab = str(p.get("tab", "Overview"))
	page.back = str(p["back"])
	page.back_params = p.get("back_params", {}).duplicate(true)
	return page

func snapshot_at(origin: String, party: String, label: String) -> void:
	var snapshot := SaveSnapshot.new()
	snapshot.begin(Game)
	while not snapshot.step(0): pass
	check(str(snapshot.data["location"]) == origin and Game.location == origin,
		label + ": snapshot retains the real location")
	check(JSON.stringify(Game._serialize(Game.world["party"])) == party,
		label + ": browsing does not move the party")

func lifecycle_save(origin: String, label: String, pause: bool) -> void:
	if pause:
		check(MobileApp.autosave(), label + ": pause autosave is admitted")
		Game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	else:
		Game._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	var saved = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	check(bool(Game._save_status["last_ok"]) and saved is Dictionary and saved.get("location") == origin,
		label + ": native lifecycle writer stores the origin")

func navigation() -> void:
	var previous_main = Game.main
	var previous_ready: bool = Game._save_ready
	var probe := RouteProbe.new()
	Game.main = probe
	Game._save_ready = true
	for origin in ["", "seat"]:
		NativeFixture.new().fixture()
		Game.location = origin
		var party := JSON.stringify(Game._serialize(Game.world["party"]))
		PoliticsView.open_view("politics", "county", "map" if origin == "" else "town", {"tab": "Town"})
		var page := politics_page()
		check(page.town_id == "county" and page.return_location == origin, "Politics opens the requested town with its real origin")
		snapshot_at(origin, party, "Politics entry")
		page._select("foreign")
		check(page.town_id == "foreign", "realm/settlement selection changes the viewed town")
		snapshot_at(origin, party, "Politics selected foreign town")
		lifecycle_save(origin, "Quit in Politics", false)
		page._records()
		var records := records_page()
		check(records.sel == "foreign" and records.back == "politics", "City records retain the viewed settlement")
		snapshot_at(origin, party, "City records")
		records.page("Person", func(_box): pass)
		snapshot_at(origin, party, "Records detail page")
		records.go_back()
		check(records.stack.is_empty(), "Records detail Back returns to its list")
		lifecycle_save(origin, "Pause in Records", true)
		# A Records civic link can nest another Politics screen before Close returns.
		records._open_civic("politics")
		var nested := politics_page()
		nested._select("county")
		snapshot_at(origin, party, "Records nested Politics")
		nested._back()
		var returned_records := records_page()
		check(returned_records.sel == "foreign", "nested Politics Back restores the Records selection")
		returned_records.close()
		var returned_politics := politics_page()
		check(returned_politics.town_id == "foreign" and returned_politics.return_location == origin,
			"Records Close restores Politics view and original return context")
		for route in [["town", "foreign", "Garrison"], ["faction", "moon_court", "Army"], ["town", "foreign", "Businesses"]]:
			page._budget_records(route[0], route[1], route[2])
			snapshot_at(origin, party, "Budget Records " + route[2])
		page._person_record({"town_id": "county", "family_id": 0, "pid": 0})
		snapshot_at(origin, party, "Person record route")
		PoliticsView.open_view("population", page.town_id, "politics", page._context())
		var population := PopulationView.new()
		population.town_id = str(Game.screen_params["town_id"])
		population.back = str(Game.screen_params["back"])
		population.return_location = str(Game.screen_params["return_location"])
		population.back_params = Game.screen_params["back_params"].duplicate(true)
		snapshot_at(origin, party, "Population from Politics")
		population._records("Register")
		snapshot_at(origin, party, "Population family register")
		var population_records := records_page()
		population_records.close()
		check(Game._active_screen == "population" and Game.screen_params["return_location"] == origin,
			"Population Records Close preserves origin and return route")
		PoliticsView.open_view("politics", population.town_id, "population", population._context())
		var population_politics := politics_page()
		population_politics._back()
		population._back()
		page._back()
		check(Game._active_screen == ("map" if origin == "" else "town") and Game.screen_params.get("tab") == "Town",
			"normal Back returns to the original screen with its parameters")
		snapshot_at(origin, party, "normal Back")
		for node in [page, records, nested, returned_records, returned_politics, population, population_records, population_politics]:
			node.free()
	Game.wait_save()
	Game.main = previous_main
	Game._save_ready = previous_ready
	probe.free()

func battle_counters() -> void:
	for winner in [0, 1, -1]:
		for dragons in [false, true]:
			NativeFixture.new().fixture()
			var state := Warfare._state(Game)
			state["battles_won"] = 2
			state["battles_lost"] = 3
			state["dragon_victories"] = 4
			var rng_before := Game.rng.state
			var assault := {"dragon_units": [123] if dragons else []}
			var before_assault := JSON.stringify(assault)
			Warfare.after_battle(Game, {"winner": winner}, assault)
			check(int(state["battles_won"]) == (3 if winner == 0 else 2), "winner %d dragon %s: correct wins" % [winner, dragons])
			check(int(state["battles_lost"]) == (3 if winner == 0 else 4), "winner %d dragon %s: correct losses" % [winner, dragons])
			check(int(state["dragon_victories"]) == (5 if winner == 0 and dragons else 4), "winner %d dragon %s: correct dragon wins" % [winner, dragons])
			check(JSON.stringify(assault) == before_assault and Game.rng.state == rng_before,
				"counter hook preserves battle inputs and RNG")
	NativeFixture.new().fixture()
	Warfare.after_battle(Game, {"winner": 0}, {})
	check(int(Warfare._state(Game)["battles_lost"]) == 0 and not Warfare._state(Game).has("dragon_victories"),
		"a win with no dragon_units key does not create a loss or dragon victory")

func run(tree: SceneTree) -> int:
	# One process and one overall deadline, including the retained affected suites.
	Game.settings["music_volume"] = 0.0
	Game.settings["sfx_volume"] = 0.0
	MusicManager.apply_volume(0.0)
	var deadline := tree.create_timer(45.0, true, false, true)
	deadline.timeout.connect(func(): printerr("v095 WATCHDOG: combined batch reached 45 seconds"); tree.quit(124))
	var keep := tree.root.get_children()
	for path in ["test_house_onboarding_v019.gd", "claude_designer_v039.gd", "claude_designer_ui_v039.gd"]:
		var suite = load("res://tests/" + path).new()
		var failed: int = await suite.run(tree)
		fails += failed
		checks += int(suite.checks)
		print("v095 retained suite %s: %d checks, %d failures" % [path, int(suite.checks), failed])
		await tree.current_scene.reset_between(keep)
	navigation()
	battle_counters()
	print("v095 three-fix batch: %d checks, %d failures" % [checks, fails])
	return fails
