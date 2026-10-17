extends RefCounted
## Small registered-person fixtures exercise the real battle handoff and save protection.
## No world generation, tactical simulation or player save is needed.

var fails := 0
var checks := 0
var routes: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func _person(pid: int, uid: String, house_uid: String) -> Array:
	return [pid, 0, 0, -5000, "", -1, 0, "", -1, -1, -1, "", [], 0, {}, uid, house_uid, "", "", ""]

func _family(id: int, name: String, people: Array, house_uid: String) -> Dictionary:
	return {"id": id, "name": name, "household_uid": "household:test:%d" % id,
		"founding_house_uid": house_uid, "gone": false, "pp": people, "kp": [],
		"purse": 77.0, "hist": [], "ev": []}

func _fixture() -> Dictionary:
	var family := _family(1, "Native", [_person(1, "person:ruler", "house:test"),
		_person(2, "person:relative", "house:test")], "house:test")
	var soldier_family := _family(2, "Soldier", [_person(3, "person:soldier", "house:other")], "house:other")
	Game.world = {"towns": {"t": {"id": "t", "name": "Test City", "faction": "middle_kingdom",
		"culture": "middle", "pos": Vector2.ZERO, "econ": {"culture": "middle", "stock": {},
		"fams": [{"id": 0, "estate": true, "pp": [], "kp": []}, family, soldier_family]}}},
		"warbands": {}, "party": {"pos": Vector2.ZERO}, "player_house": {"town_id": "t",
		"house_uid": "house:test", "household_uid": "household:test:1", "ruler_uid": "person:ruler",
		"house_name": "Native", "title": "Lord"}}
	Game.company = []; Game.stash = []; Game.squads = {}; Game.pending_battle = {}; Game.last_result = {}
	Game.contract = {}; Game.location = ""; Game.gold = 123; Game.day = 10.0
	Game.provisions = {"meal": [], "beer": [], "wine": []}; Game.food_clock = {}
	Game.invalidate_deploy()
	return family

func _unit(family: Dictionary, person: Array, dead: bool) -> Unit:
	var u := Unit.create("human", "player")
	u.family = int(family["id"]); u.home_town = "t"
	u.name = Persons.name_of(family, person, "human")
	u.born = float(person[3]); u.dead = dead
	person[4] = "company"; person[5] = u.uid
	return u

func _finish(units: Array, winner: int) -> void:
	Game.pending_battle = {"seed": 31}
	Game.finish_battle({"winner": winner, "player_units": units, "enemy_units": [],
		"enemy_fallen": [], "enemy_fled": [], "events": [], "fighter_units": units})

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null:
			return found
	return null

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var previous_main: Node = Game.main
	var previous_save: String = Game.SAVE_PATH
	Game.wait_save()
	Game.main = null
	Game.SAVE_PATH = "user://test_dynasty_defeat_%d.json" % OS.get_process_id()
	var route_listener := func(screen: String): routes.append(screen)
	Game.screen_changed.connect(route_listener)

	var family := _fixture()
	Game.world.erase("player_house")
	check(not Game.is_game_over(), "onboarding survives an empty army before selecting a house")
	Game.world["player_house"] = {}
	check(not Game.is_game_over(), "empty selection marker is still onboarding")
	Game.world = {}
	check(Game.is_game_over(), "standalone combat retains empty-company fallback")

	family = _fixture()
	var soldier_family: Dictionary = Game.world["towns"]["t"]["econ"]["fams"][2]
	var soldier := _unit(soldier_family, soldier_family["pp"][0], true)
	Game.company = [soldier]
	_finish([soldier], 1)
	check(Game.company.is_empty() and not Game.is_game_over(), "a troop wipe leaves the registered family playable")
	check(routes[-1] == "aftermath" and Game.pending_battle.is_empty(), "loss reaches aftermath after clearing the handoff")
	check(soldier_family["pp"].is_empty() and soldier_family["dp"].size() == 1, "native reconciliation records the dead soldier once")
	check(Dynasty.living_members(Game).size() == 2 and Game.gold == 123, "ordinary casualty preserves dynasty members and money")
	var aftermath: Node = load("res://battle/aftermath.tscn").instantiate()
	tree.root.add_child(aftermath)
	var continue_button := _button(aftermath, "Continue")
	check(continue_button != null, "defeat aftermath offers Continue with no army")
	if continue_button != null:
		continue_button.pressed.emit()
		check(routes[-1] == "map", "defeat aftermath continues to the native map")
	aftermath.queue_free()
	await tree.process_frame

	# Even an accidentally opened ending screen must preserve the current empty-army save.
	Game.save_game_async()
	var ending: Node = load("res://ui/gameover.tscn").instantiate()
	tree.root.add_child(ending)
	Game.wait_save()
	check(Game.has_save(), "stale gameover screen preserves living-family autosave")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	check(saved is Dictionary and saved["company"].is_empty() and
		saved["world"]["player_house"]["house_uid"] == "house:test", "isolated save retains the selected house and actual empty army")
	check(_button(ending, "Continue") != null, "living-family ending screen offers recovery")
	ending.queue_free()
	await tree.process_frame

	# A shared household/name does not imply the same founding dynasty or person.
	family = _fixture()
	var living_ruler: Array = family["pp"][0]
	var namesake: Array = family["pp"][1]
	namesake[Persons.HOUSE_UID] = "house:other"
	var fallen_namesake := _unit(family, namesake, true)
	check(fallen_namesake.name == Persons.name_of(family, living_ruler, "human"), "collision fixture has actual same-name people")
	Game.company = [fallen_namesake]
	_finish([fallen_namesake], 1)
	check(family["pp"] == [living_ruler] and int(family["dp"][0][0]) == 2,
		"UnitUID reconciliation removes the actual namesake casualty instead of the selected ruler")
	check(bool(Dynasty.ruler(Game).get("alive", false)) and not Game.is_game_over(),
		"same-name troop death preserves the living selected dynasty member")
	var econ: Dictionary = Game.world["towns"]["t"]["econ"]
	var deaths_before: int = Census._book(econ)["deaths"].size()
	People.casualty(Game, fallen_namesake, "dead", "company")
	check(family["pp"] == [living_ruler] and family["dp"].size() == 1 and
		Census._book(econ)["deaths"].size() == deaths_before, "repeated actual casualty reports neither kill a namesake nor duplicate Census death")

	family = _fixture()
	var ruler := _unit(family, family["pp"][0], true)
	Game.company = [ruler]
	_finish([ruler], 1)
	var remembered_ruler := Dynasty.ruler(Game)
	check(not bool(remembered_ruler.get("alive", true)) and Dynasty.living_members(Game).size() == 1,
		"native ruler death preserves the deceased office reference and actual living relative")
	check(remembered_ruler.get("person_uid", "") == "person:ruler" and int(remembered_ruler.get("pid", -1)) == 1,
		"native death memory retains the actual registered ruler identity")
	check(not Game.is_game_over() and routes[-1] == "aftermath", "ruler death alone does not end a living dynasty")
	check(Game.world["player_house"]["ruler_uid"] == "person:ruler", "ruler death invents no successor")

	var relative := _unit(family, family["pp"][0], true)
	var survivor := Unit.create("human", "player")
	Game.company = [relative, survivor]
	_finish([relative, survivor], 1)
	check(Game.is_game_over() and routes[-1] == "gameover", "actual family extinction ends the campaign despite surviving troops")
	check(Game.company == [survivor] and family["pp"].is_empty(), "extinction is evaluated after native casualty removal")
	Game.save_game_async()
	ending = load("res://ui/gameover.tscn").instantiate()
	tree.root.add_child(ending)
	check(not Game.has_save(), "confirmed extinction clears only the isolated ending save")
	ending.queue_free()
	await tree.process_frame

	family = _fixture()
	var living := Unit.create("human", "player")
	var original_body := living.body
	var wound: Dictionary = living.body.wound_part("arm_upper_r")["layers"][0]
	wound["dmg"] = 0.2; wound["kind"] = "cut"; wound["bleed"] = 0.3
	Game.company = [living]
	_finish([living], -1)
	check(routes[-1] == "aftermath" and Game.company == [living], "ordinary undecided battle keeps its surviving army and aftermath")
	check(living.battles == 1 and not Game.is_game_over(), "ordinary handoff still applies native battle participation")
	check(living.body == original_body and float(wound["dmg"]) == 0.2 and float(wound["bleed"]) == 0.0,
		"native aftermath preserves the original body and wound while bandaging external bleeding")
	Game.wait_save()
	if FileAccess.file_exists(Game.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	Game.SAVE_PATH = previous_save
	Game.screen_changed.disconnect(route_listener)
	Game.main = previous_main
	print("dynasty defeat: %d checks" % checks)
	return fails
