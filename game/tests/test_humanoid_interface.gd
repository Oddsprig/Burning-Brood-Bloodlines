extends RefCounted
## Desktop-only native CPU preview. No creatures, dragons, worldgen or UI input.
## Root runs through tests/runner.tscn with --capture-dir=<absolute output folder>.
const RACES: Array[String] = ["human", "orc", "high_elf", "moon_elf", "dark_elf", "dwarf", "goblin", "troll"]
var checks: int = 0
var fails: int = 0
var renders: int = 0
var started: int = 0
var out_dir: String = ""
var labels: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func _unit(race: String, sex: int = 0, variant: int = 0) -> Unit:
	var u := Unit.new()
	u.race = race; u.faction = "middle_kingdom"; u.sex = sex; u.age = 35
	var sp: Dictionary = FigurePainter.spec_generic(race, Color("#32836a"), Color("#aa84c9"), 246)
	u.look = {"seed": 246, "skin": sp["skin"].to_html(), "hair": sp["hair"].to_html(), "beard": sex == 0 and race in ["human", "orc", "dwarf"], "female_set": variant, "beard_style": variant}
	return u

func _board(cols: int, rows: int, cell: Vector2i = Vector2i(128, 160)) -> Image:
	var img := Image.create(cols * cell.x, rows * cell.y, false, Image.FORMAT_RGBA8)
	img.fill(Color("#201c2b"))
	return img

func _put(board: Image, image: Image, col: int, row: int, cell: Vector2i = Vector2i(128, 160)) -> void:
	check(image != null and not image.is_empty(), "native image is populated")
	if image == null or image.is_empty(): return
	var copy := image.duplicate() as Image
	var scale: float = minf(float(cell.x - 12) / copy.get_width(), float(cell.y - 12) / copy.get_height())
	copy.resize(maxi(1, roundi(copy.get_width() * scale)), maxi(1, roundi(copy.get_height() * scale)), Image.INTERPOLATE_NEAREST)
	board.blend_rect(copy, Rect2i(Vector2i.ZERO, copy.get_size()), Vector2i(col * cell.x + (cell.x - copy.get_width()) / 2, row * cell.y + (cell.y - copy.get_height()) / 2))

func _save(img: Image, name: String) -> void:
	if out_dir != "": check(img.save_png(out_dir.path_join(name + ".png")) == OK, "save " + name)

func _body(sp: Dictionary) -> Image:
	renders += 1
	return FigurePainter.render(sp, "idle", 0.0)

func _bust(sp: Dictionary) -> Image:
	renders += 1
	return FigurePainter.render_bust(sp)

func _deadline() -> bool:
	var ok: bool = Time.get_ticks_msec() - started < 40000
	check(ok, "preview stays below 40-second internal budget")
	return ok

func _races() -> void:
	var board := _board(8, 6)
	for i in RACES.size():
		if not _deadline(): break
		var race: String = RACES[i]
		var sp: Dictionary = FigurePainter.spec_for_unit(_unit(race, 0, 3))
		_put(board, _body(sp), i, 0); _put(board, _bust(sp), i, 3)
		for set_id in 2:
			var woman: Unit = _unit(race, 1, set_id)
			var before: Dictionary = woman.look.duplicate(true)
			var female: Dictionary = FigurePainter.spec_for_unit(woman)
			check(int(female.get("female_set", -1)) == set_id and not bool(female["beard"]), race + " actual female selector")
			check(woman.look == before, "appearance reader leaves saved identity untouched")
			_put(board, _body(female), i, set_id + 1); _put(board, _bust(female), i, set_id + 4)
		labels.append("race_models column %d: %s; rows male body, Original woman body, Refined woman body, same three busts" % [i, race])
	_save(board, "race_models")
	var beards := _board(8, 3, Vector2i(104, 104))
	for i in 3:
		var race: String = ["human", "orc", "dwarf"][i]
		for style in FigurePainter.BEARD_STYLES.size():
			var sp: Dictionary = FigurePainter.spec_for_unit(_unit(race, 0, style))
			check(int(sp.get("beard_style", -1)) == style, "actual " + race + " beard selector")
			_put(beards, _bust(sp), style, i, Vector2i(104, 104))
		labels.append("beard_styles row %d: %s; columns %s" % [i, race, ", ".join(FigurePainter.BEARD_STYLES)])
	_save(beards, "beard_styles")

func _explicit_reviews() -> void:
	var humans := _board(8, 2)
	for i in 8:
		var u: Unit = _unit("human", 0 if i < 6 else 1, 3 if i < 6 else i - 6)
		var seed: int = i * 13 + 11 if i < 6 else 424
		var generic: Dictionary = FigurePainter.spec_generic("human", Color("#32836a"), Color("#aa84c9"), seed)
		u.look["seed"] = seed; u.look["skin"] = generic["skin"].to_html(); u.look["hair"] = generic["hair"].to_html()
		u.look["beard"] = i < 6 and i % 2 == 0
		var sp: Dictionary = FigurePainter.spec_for_unit(u)
		_put(humans, _body(sp), i, 0); _put(humans, _bust(sp), i, 1)
		labels.append("human_variants column %d: %s seed %d; body then same-identity portrait" % [i, "male" if i < 6 else FigurePainter.FEMALE_SETS[i - 6] + " woman", seed])
	_save(humans, "human_variants")
	var moon: Unit = _unit("moon_elf")
	moon.equip["main_hand"] = Item.make("glaive", "bronze", 3)
	moon.equip["helm"] = Item.make("crescent_helm", "bronze", 3)
	for it in moon.equip.values(): it.mark = {"r": "moon_elf"}
	var sp: Dictionary = FigurePainter.spec_for_unit(moon)
	check(not bool(sp["weapon"]["two"]), "released Moon glaive keeps actual one-handed item definition")
	check(FigurePainter.helm_maker(sp["helm"]) == "moon_elf", "actual crescent helmet maker")
	var moon_board := _board(3, 2)
	for i in 3:
		var pose: String = ["idle", "prepare", "strike"][i]
		renders += 1
		_put(moon_board, FigurePainter.render(sp, pose, 0.5), i, 0)
	_put(moon_board, _bust(sp), 0, 1)
	_put(moon_board, ItemIcon.for_item(moon.equip["main_hand"]).get_image(), 1, 1)
	_put(moon_board, ItemIcon.for_item(moon.equip["helm"]).get_image(), 2, 1)
	_save(moon_board, "moon_elf_glaive_crescent")
	labels.append("moon_elf_glaive_crescent row0: idle, wind-up, strike .5; row1: same portrait, glaive icon, crescent helm icon; all actual Moon-made items")
	var helmets := _board(4, 2)
	var cases: Array = [["human", "orc", "nasal_helm"], ["human", "moon_elf", "crescent_helm"], ["dwarf", "dwarf", "dwarf_helm"], ["human", "human", "closed_helm"]]
	for i in cases.size():
		var c: Array = cases[i]
		var wearer: Unit = _unit(String(c[0]))
		var helm: Item = Item.make(String(c[2]), "bronze", 3)
		helm.mark = {"r": String(c[1])}; wearer.equip["helm"] = helm
		var worn: Dictionary = FigurePainter.spec_for_unit(wearer)
		check(FigurePainter.helm_maker(worn["helm"]) == String(c[1]), "actual traded helmet style stays with maker")
		_put(helmets, _body(worn), i, 0); _put(helmets, _bust(worn), i, 1)
		labels.append("maker_helmets column %d: %s wearer / %s maker / %s actual item" % [i, c[0], c[1], c[2]])
	_save(helmets, "maker_helmets")

func _gear(ids: Array, name: String) -> void:
	var chosen: Array[String] = []
	var seen: Dictionary = {}
	ids.sort()
	for tid in ids:
		var tm: Dictionary = DB.template(String(tid))
		var key: String = String(tm.get("slot", "weapon")) + ":" + String(tm.get("sprite", ""))
		if seen.has(key): continue
		seen[key] = true; chosen.append(String(tid))
	var rows: int = ceili(float(chosen.size()) / 8.0)
	var board := _board(8, rows * 3)
	for i in chosen.size():
		if not _deadline(): break
		var u: Unit = _unit("human")
		var tm: Dictionary = DB.template(chosen[i])
		var mats: Array = tm.get("materials", ["copper"])
		var material: String = "bronze" if "copper" in mats or "tin" in mats else String(mats[0])
		var maker: String = String(tm.get("culture", ""))
		if maker not in RACES: maker = "human"
		var it: Item = Item.make(chosen[i], material, 3)
		it.mark = {"r": maker, "n": "Preview forge", "t": "preview", "tn": "Preview town"}
		u.equip[it.slot()] = it
		var before: Dictionary = it.to_dict().duplicate(true)
		var sp: Dictionary = FigurePainter.spec_for_unit(u)
		var item_sp: Dictionary = FigurePainter._item_spec(it)
		check(String(item_sp["maker_race"]) == maker, "actual maker reaches equipped art")
		check(it.to_dict() == before, "drawing spec leaves real item unchanged")
		if it.slot() == "helm": check(FigurePainter.helm_maker(item_sp) == maker, "wearer never replaces actual maker")
		var col: int = i % 8
		var row: int = (i / 8) * 3
		_put(board, _body(sp), col, row)
		_put(board, _bust(sp), col, row + 1)
		_put(board, ItemIcon.for_item(it).get_image(), col, row + 2)
		labels.append("%s cell %d: %s / %s / %s maker; rows body, portrait, item icon" % [name, i, chosen[i], material, maker])
	_save(board, name)

func _ruler_identity() -> void:
	var original_world: Dictionary = Game.world
	var original_company: Array = Game.company
	var original_stash: Array = Game.stash
	var original_squads: Dictionary = Game.squads
	var original_day: float = Game.day
	var original_gold: float = Game.gold
	var original_location: String = Game.location
	var original_map_w: int = WorldGen.W
	var original_map_h: int = WorldGen.H
	var original_k: float = WorldGen.K
	var original_kd: float = WorldGen.KD
	var original_tf: float = WorldGen.TF
	# The fixture clears containers, so detach the live references first.
	Game.company = []; Game.stash = []; Game.squads = {}
	var fixture: RefCounted = load("res://tests/test_dynasty_foundation.gd").new()
	fixture.fixture()
	check(Dynasty.select_city(Game, "city_a"), "select real registered ruler")
	var fallback: Dictionary = Dynasty.portrait_spec(Game)
	var office: Dictionary = Dynasty.ruler(Game)
	check(fallback["sex"] == ("female" if int(office["sex"]) == 1 else "male"), "portrait uses actual registered sex")
	var civilian_before: String = JSON.stringify(Game._serialize(Game.world))
	var next_u: int = Unit._next_uid
	var next_i: int = Item._next_uid
	var money: float = Game.gold
	check(Dynasty.portrait_spec(Game) == fallback, "civilian appearance is deterministic")
	check(JSON.stringify(Game._serialize(Game.world)) == civilian_before, "civilian fallback is pure")
	check(Unit._next_uid == next_u and Item._next_uid == next_i and Game.gold == money, "civilian portrait creates no unit/item/coin")
	var town: Dictionary = Game.world["towns"][office["town_id"]]
	var fam: Dictionary = town["econ"]["fams"][int(office["family_id"])]
	var person: Array = Persons.by_pid(fam, int(office["pid"]))
	var actual: Unit = _unit(String(office["race"]), int(office["sex"]), 1)
	actual.uid = 987654
	actual.body = BodyState.new()
	actual.body.plan_id = String(actual.race_def().get("body", "humanoid"))
	actual.body.init_from_plan(DB.bodies[actual.body.plan_id], float(actual.race_def().get("mass", 70)))
	actual.look["seed"] = 97531
	actual.look["beard_style"] = 7
	actual.home_town = String(office["town_id"])
	actual.equip["helm"] = Item.make("nasal_helm", "bronze", 2)
	actual.equip["helm"].mark = {"r": "orc"}
	Persons.bind(town["econ"], fam, person, actual, "company", Game.day)
	Game.company.append(actual)
	var bound_next_item: int = Item._next_uid
	var world_before: String = JSON.stringify(Game._serialize(Game.world))
	var bound: Dictionary = Dynasty.portrait_spec(Game)
	check(int(bound["seed"]) == 97531, "registered ruler portrait shares real unit identity")
	check(String(bound["helm"].get("maker_race", "")) == "orc", "ruler portrait shows actual traded helmet")
	check(FigurePainter.helm_maker(bound["helm"]) == "orc", "ruler culture cannot replace maker design")
	check(JSON.stringify(Game._serialize(Game.world)) == world_before, "ruler portrait is pure")
	var expected: Dictionary = FigurePainter.spec_for_unit(actual)
	expected["role"] = "ruler"
	check(bound == expected, "portrait appearance/equipment equals actual company unit spec")
	check(Unit._next_uid == next_u and Item._next_uid == bound_next_item and Game.gold == money, "bound company portrait creates no unit/item/coin")
	for sex in 2:
		person[2] = sex; actual.sex = sex
		actual.look["beard"] = sex == 0
		var styled: Dictionary = Dynasty.portrait_spec(Game)
		if sex == 1: check(int(styled.get("female_set", -1)) == 1 and not bool(styled["beard"]), "saved female set reaches ruler portrait")
		else: check(int(styled.get("beard_style", -1)) == 7, "saved beard style reaches ruler portrait")
	Game.company.clear()
	person[4] = "army"
	Game.world["warbands"]["actual"] = {"units": [actual]}
	var war_before: String = JSON.stringify(Game._serialize(Game.world))
	var war_spec: Dictionary = Dynasty.portrait_spec(Game)
	expected = FigurePainter.spec_for_unit(actual); expected["role"] = "ruler"
	check(war_spec == expected, "registered army ruler uses real warband unit spec")
	check(JSON.stringify(Game._serialize(Game.world)) == war_before, "warband portrait reader is pure")
	check(Unit._next_uid == next_u and Item._next_uid == bound_next_item and Game.gold == money, "warband portrait creates no unit/item/coin")
	actual.home_town = "unrelated"
	check(int(Dynasty.portrait_spec(Game)["seed"]) == int(fallback["seed"]), "wrong-home uid cannot hijack ruler appearance")
	actual.home_town = String(office["town_id"]); actual.family = -1
	check(int(Dynasty.portrait_spec(Game)["seed"]) == int(fallback["seed"]), "wrong-family uid cannot hijack ruler appearance")
	_save(_bust(bound), "actual_ruler_portrait")
	Game.world = original_world; Game.company = original_company; Game.stash = original_stash; Game.squads = original_squads
	Game.day = original_day; Game.gold = original_gold; Game.location = original_location
	WorldGen.W = original_map_w; WorldGen.H = original_map_h
	WorldGen.K = original_k; WorldGen.KD = original_kd; WorldGen.TF = original_tf
	check(WorldGen.W == original_map_w and WorldGen.H == original_map_h, "fixture map dimensions restored")

func run(tree: SceneTree) -> int:
	started = Time.get_ticks_msec()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): out_dir = arg.substr(14)
	if out_dir != "": check(DirAccess.make_dir_recursive_absolute(out_dir) == OK, "capture output directory")
	var next_item: int = Item._next_uid
	var next_unit: int = Unit._next_uid
	_races()
	_explicit_reviews()
	_gear(DB.weapons.keys() + DB.bows.keys(), "weapons")
	_gear(DB.armor.keys(), "armour_helmets")
	_ruler_identity()
	if out_dir != "":
		var file := FileAccess.open(out_dir.path_join("preview_labels.txt"), FileAccess.WRITE)
		check(file != null, "preview label manifest")
		if file != null: file.store_string("Columns and rows start at zero. Thumbnail framing only; native unit scale is unchanged.\n" + "\n".join(labels)); file.close()
	Paperdoll.clear_cache(); ItemIcon._cache.clear()
	Item._next_uid = next_item; Unit._next_uid = next_unit
	await tree.process_frame
	print("humanoid interface: %d checks, %d native body/bust renders, %d failures, %.3fs; desktop only" % [checks, renders, fails, float(Time.get_ticks_msec() - started) / 1000.0])
	return fails
