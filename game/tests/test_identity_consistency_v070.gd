extends RefCounted
## Compare the inputs of actual screen builders, without screenshots, world generation or simulation.
## MapToken badges and the prisoner table contain symbols/text, not invented character portraits.
const NativeFixture := preload("res://tests/test_feudal_succession.gd")
const CompanyScreen := preload("res://ui/company.gd")
const CourtScreen := preload("res://ui/court.gd")
const BattleView := preload("res://battle/unit_view.gd")
const APPEARANCE := ["race", "skin", "hair", "beard", "seed", "female_set", "beard_style",
	"sex", "age", "prim", "sec", "dead", "lost", "dmg", "wk", "gore", "bleed", "blood"]
const GEAR := ["weapon", "shield", "body", "helm", "clothing", "legs", "hands", "feet", "legs_under"]
var checks := 0
var fails := 0
var samples := 0
var native := NativeFixture.new()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL identity070: ", message)

func same_spec(label: String, actual: Dictionary, expected: Dictionary) -> void:
	for key: String in APPEARANCE + GEAR:
		check(actual.get(key) == expected.get(key), "%s: %s differs (%s / %s)" % [label, key, actual.get(key), expected.get(key)])

func portraits(node: Node) -> Array:
	var out: Array = []
	if node is Portrait: out.append(node)
	for child: Node in node.get_children(): out.append_array(portraits(child))
	return out

func screen_spec(label: String, node: Node, expected: Dictionary) -> void:
	var found := portraits(node)
	check(found.size() == 1, label + ": exactly one actual character portrait")
	if found.size() == 1: same_spec(label, found[0]._spec, expected)

func snapshot() -> PackedByteArray:
	return var_to_bytes(Game._serialize({"world": Game.world, "company": Game.company,
		"gold": Game.gold, "day": Game.day, "squads": Game.squads, "stash": Game.stash}))

func fixture(race: String, sex: int, age: int, kit: int) -> Unit:
	native.fixture()
	var town: Dictionary = Game.world["towns"]["seat"]
	var econ: Dictionary = town["econ"]
	for culture: String in TownEcon.data()["cultures"]:
		if str(TownEcon.data()["cultures"][culture]["race"]) == race:
			econ["culture"] = culture
			break
	var family: Dictionary = econ["fams"][0]
	var person: Array = family["pp"][0]
	person[2] = sex; person[3] = -age * People.year_days()
	var unit := Unit.create(race, "middle_kingdom")
	unit.home_town = "seat"; unit.role = "officer"
	var rd: Dictionary = DB.races[race]
	unit.look = {"seed": 71 + samples * 131, "skin": rd["skin"][samples % rd["skin"].size()],
		"hair": rd["hair"][samples % rd["hair"].size()], "beard": sex == 0 and race in ["human", "dwarf", "orc"],
		"female_set": samples % 2, "beard_style": samples % FigurePainter.BEARD_STYLES.size()}
	if kit > 0:
		unit.equip["clothing"] = Item.make("tunic", "linen", 0)
		unit.equip["legs_under"] = Item.make("trousers", "linen", 0)
		unit.equip["feet"] = Item.make("shoes", "leather", 0)
		unit.equip["main_hand"] = Item.make("arming_sword", "bronze", 2)
		unit.equip["off_hand"] = Item.make("round_shield", "bronze", 1)
	if kit == 2:
		unit.equip["body"] = Item.make("lamellar_cuirass", "steel", 3)
		unit.equip["helm"] = Item.make("closed_helm", "iron", 1)
		unit.equip["legs"] = Item.make("splint_greaves", "iron", 1)
		unit.equip["hands"] = Item.make("crude_bracers", "bronze", 2)
		unit.equip["main_hand"] = Item.make("glaive" if samples % 2 else "boar_spear", "steel", 2)
		unit.equip["ranged"] = Item.make("hunting_bow", "wood", 2)
		unit.equip["helm"].mark = {"r": "orc"}
		unit.equip["helm"].wear = 0.25
		var wound: Dictionary = unit.body.wound_part("head")
		wound["layers"][0]["dmg"] = 0.4; wound["layers"][0]["kind"] = "cut"; wound["layers"][0]["bleed"] = 0.1
	Persons.bind(econ, family, person, unit, "company", Game.day)
	Game.company.append(unit)
	Mobilization._state(Game)
	return unit

func screen_sample(tree: SceneTree, unit: Unit) -> void:
	var label := "%s %s age %d" % [unit.race, "female" if unit.sex == 1 else "male", unit.age]
	var expected := FigurePainter.spec_for_unit(unit)
	var row := Dynasty.ruler(Game)
	var before := snapshot()
	var next_unit := Unit._next_uid; var next_item := Item._next_uid; var rng_state := Game.rng.state
	var company := CompanyScreen.new()
	var roster: Control = company._row(unit, "Fixture", true)
	screen_spec(label + " roster", roster, expected)
	var header := UnitSheet.header(unit)
	screen_spec(label + " character card", header, expected)
	var fighter := Fighter.new(); fighter.unit = unit; fighter.side = samples % 2
	var battle := BattleView.new(); battle.setup(fighter, 32.0)
	same_spec(label + " battle", battle.doll.current_spec(), expected)
	if unit.bow() != null:
		# Drawing an equipped bow is a pose change, with the same saved sidearm/kit.
		battle.doll.bow_hand = true
		var drawn := expected.duplicate(true)
		drawn["weapon"] = FigurePainter._item_spec(unit.bow()); drawn["shield"] = {}
		same_spec(label + " battle holding its equipped bow", battle.doll.current_spec(), drawn)
	var card := DynastyCard.new(); tree.root.add_child(card)
	screen_spec(label + " campaign ruler card", card, expected)
	var icon := PartyIcon.new()
	icon.leader = unit; icon.race = unit.race
	icon.color = FigurePainter.faction_colors(unit.faction)[0]
	same_spec(label + " campaign leader figure", icon._leader_spec(), expected)
	var court := CourtScreen.new(); court.ruler_uid = str(row["person_uid"])
	court.open_person({"row": row, "rel": "Fixture"})
	screen_spec(label + " court popup", court, expected)
	var family_tree := CourtScreen.FamilyTree.new()
	family_tree.host = court
	family_tree.data = {row["person_uid"]: {"row": row, "rel": "Fixture"}}
	var tile: Control = family_tree._node(str(row["person_uid"]))
	screen_spec(label + " court family tile", tile, expected)
	var riding := MountedRiderArt.spec_for_unit(unit)
	same_spec(label + " mounted rider", riding, expected)
	check(snapshot() == before and Game.rng.state == rng_state and Unit._next_uid == next_unit and Item._next_uid == next_item,
		label + ": screen builders preserve saved identity, equipment, campaign and RNG")
	# Sound's label-contrast callbacks must finish before their Controls leave the tree.
	await tree.process_frame
	for node: Node in [roster, header, battle, card, icon, court, tile, family_tree, company]: node.free()

func holder_transitions(unit: Unit) -> void:
	var expected := FigurePainter.spec_for_unit(unit)
	var row := Dynasty.ruler(Game)
	Game.company.clear()
	for holder: String in ["reserve", "recruit", "warband", "prisoners", "captives"]:
		match holder:
			"reserve": Game.world["mobilization"]["reserve"] = [unit]
			"recruit": Game.world["towns"]["seat"]["recruits"] = [unit]
			"warband": Game.world["warbands"]["fixture"] = {"units": [unit]}
			_: Game.world[holder] = [{"uid": unit.uid, "unit": unit, "home_town": unit.home_town, "family": unit.family}]
		check(Dynasty.bound_unit(Game, row) == unit, holder + ": registered portrait finds the exact physical holder")
		same_spec(holder + " registered portrait", Dynasty.portrait_for(Game, row), expected)
		var court := CourtScreen.new(); court.open_person({"row": row, "rel": "Fixture"})
		screen_spec(holder + " actual court popup", court, expected)
		court.free()
		Game.world["mobilization"]["reserve"] = []
		Game.world["towns"]["seat"]["recruits"] = []
		Game.world["warbands"] = {}; Game.world["prisoners"] = []; Game.world["captives"] = []
	# Same numerical UID in another family must never borrow somebody else's face/kit.
	unit.family = 99; Game.world["prisoners"] = [{"uid": unit.uid, "unit": unit}]
	check(Dynasty.bound_unit(Game, row) == null, "prisoner lookup rejects a wrong-family UID")
	unit.family = int(row["family_id"]); unit.home_town = "foreign"
	check(Dynasty.bound_unit(Game, row) == null, "prisoner lookup rejects a wrong-home UID")
	unit.home_town = "seat"; Game.world["prisoners"] = []; Game.company.append(unit)

func refresh_inputs(tree: SceneTree, unit: Unit) -> void:
	var row := Dynasty.ruler(Game)
	var spec := Dynasty.portrait_for(Game, row)
	var portrait := Portrait.new(); portrait.set_spec(spec)
	portrait.refresh()
	same_spec("refresh of registered/civilian portrait", portrait._spec, spec)
	portrait.set_spec(spec)
	var saved := portrait._spec.duplicate(true)
	spec["seed"] = int(spec["seed"]) + 1
	check(portrait._spec == saved, "Portrait owns its display snapshot, not the caller's mutable dictionary")
	var preview := Paperdoll.new(); preview.team_color = Color.RED
	var preview_input := saved.duplicate(true); var original := preview_input.duplicate(true)
	preview.set_spec(preview_input)
	check(preview_input == original, "Paperdoll preview does not overwrite the caller's portrait team/appearance")
	var card := DynastyCard.new(); tree.root.add_child(card)
	var troop_portrait := Portrait.new(); troop_portrait.set_unit(unit)
	var battle := Paperdoll.new(); battle.set_unit(unit)
	var dragon := DragonView.new(); dragon._record = {"rider_person_uid": row["person_uid"]}
	dragon._resolve_rider()
	var initial_layers: Dictionary = dragon._rider_layers
	var before := FigurePainter.spec_for_unit(unit)
	# Real same-person equipment changes; cache invalidation must reach every display input.
	unit.equip["helm"] = Item.make("nasal_helm", "bronze", 2)
	unit.equip["main_hand"] = Item.make("arming_sword", "steel", 4)
	unit.look["seed"] = int(unit.look["seed"]) + 60
	var expected := FigurePainter.spec_for_unit(unit)
	check(expected["seed"] != before["seed"] and expected["helm"] != before["helm"], "refresh fixture changes face key and actual gear")
	troop_portrait.refresh(); battle.invalidate(); card.refresh(true); dragon._resolve_rider()
	same_spec("refreshed roster", troop_portrait._spec, expected)
	same_spec("refreshed battle", battle.current_spec(), expected)
	screen_spec("refreshed campaign card", card, expected)
	var rider_input = dragon.get("_rider_spec")
	same_spec("refreshed dragon rider", rider_input if rider_input is Dictionary else {}, expected)
	check(not is_same(initial_layers, dragon._rider_layers), "same rider with changed face/gear rebuilds mounted layers")
	var changed_layers: Dictionary = dragon._rider_layers
	dragon._resolve_rider()
	check(is_same(changed_layers, dragon._rider_layers), "unchanged rider reuses the cached mounted layers")
	Game.world["player_house"]["customization"] = {"primary_color": "#823744", "secondary_color": "#DAAE52"}
	card.refresh(true)
	screen_spec("bound ruler keeps actual clothing colours with a custom banner", card, expected)
	Game.day += People.year_days()
	check(int(FigurePainter.spec_for_unit(unit)["age"]) == int(Dynasty.ruler(Game)["age"]),
		"field/captive units with a cached age use the same current birthday as registered portraits")
	await tree.process_frame
	for node: Node in [portrait, preview, card, troop_portrait, battle, dragon]: node.free()

func civilian_design() -> void:
	native.fixture()
	var row := Dynasty.ruler(Game); row["sex"] = 1
	var base := Dynasty.portrait_for(Game, row)
	var changed_seed := 60 if FigurePainter.female_variant(base) == 0 else 1
	Game.world["player_house"]["design"] = {"person_uid": row["person_uid"], "look": {"seed": changed_seed}}
	var before := snapshot(); var next_unit := Unit._next_uid; var next_item := Item._next_uid
	var female := Dynasty.portrait_for(Game, row)
	check(int(female["female_set"]) == FigurePainter.female_variant({"seed": changed_seed}), "civilian designer seed selects the same female variant as a unit")
	row["sex"] = 0
	Game.world["player_house"]["design"]["look"] = {"seed": 360, "beard": true}
	var male := Dynasty.portrait_for(Game, row)
	check(int(male.get("beard_style", -1)) == FigurePainter.beard_style({"seed": 360}), "civilian designer seed selects the same beard style as a unit")
	Game.world["player_house"]["design"]["look"] = {"seed": 360, "beard": true, "beard_style": 5}
	check(int(Dynasty.portrait_for(Game, row)["beard_style"]) == 5, "explicit civilian beard style survives seed normalization")
	Game.world["player_house"]["design"]["look"] = {"seed": changed_seed}
	check(snapshot() == before and Unit._next_uid == next_unit and Item._next_uid == next_item,
		"civilian identity reads never generate units, gear or mutate saved appearance")
	Game.world["player_house"]["customization"] = {"primary_color": "#823744", "secondary_color": "#DAAE52"}
	same_spec("civilian court shares the campaign card's saved banner palette", Dynasty.portrait_for(Game, Dynasty.ruler(Game)), Dynasty.portrait_spec(Game))

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var started := Time.get_ticks_msec()
	var cultures: Dictionary = TownEcon.data()["cultures"]
	var original_cultures := cultures.duplicate(true)
	# Three supported art races have no settled economy culture. Give only this fixture
	# a copy of the native culture with that race; restore the shared table at the end.
	for race: String in FigurePainter.DETAILED_RACES:
		var culture: Dictionary = cultures["middle"].duplicate(true)
		culture["race"] = race
		cultures["identity_v070_" + race] = culture
	for race: String in FigurePainter.DETAILED_RACES:
		var ages: Dictionary = People.ages(race)
		for stage in 3:
			if Time.get_ticks_msec() - started > 45000:
				check(false, "identity sample budget exceeded 45 seconds")
				TownEcon.data()["cultures"] = original_cultures
				return fails
			var age: int = [maxi(1, int(ages["adult"]) - 2), int(ages["adult"]) + 4, int(ages["elder"]) + 4][stage]
			var unit := fixture(race, samples % 2, age, stage)
			await screen_sample(tree, unit)
			samples += 1
			await tree.process_frame
	var actual := fixture("human", 1, 35, 2)
	holder_transitions(actual)
	await refresh_inputs(tree, actual)
	civilian_design()
	TownEcon.data()["cultures"] = original_cultures
	print("IDENTITY_V070: %d samples, %d checks, %d failures, %.3f s" % [samples, checks, fails, (Time.get_ticks_msec() - started) / 1000.0])
	return fails
