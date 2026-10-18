extends RefCounted
## Roadmap v0.039 character designer logic tests.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks: int = 0
var fails: int = 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func fixture() -> Dictionary:
	var native = NativeFixture.new()
	native.fixture()
	Game.world.erase("player_house")
	Game.gold = 0
	Game.location = ""
	Game.company.clear()
	Game.stash.clear()
	Game.squads.clear()
	Game.provisions = {"meal": [], "beer": [], "wine": []}
	Game.world["party"] = {"pos": Vector2(9, 11), "target": Vector2(9, 11), "path": [], "dest_town": "", "arrived": "", "waiting": false}
	var town: Dictionary = Game.world["towns"]["seat"]
	var e: Dictionary = town["econ"]
	var ruling: Dictionary = e["fams"][0]
	var king: Array = ruling["pp"][0]
	var ordinary: Dictionary = Families._blank(1)
	ordinary["name"] = "Native Cadet"
	ordinary["purse"] = 417.0
	ordinary["homes"] = 1
	ordinary["land"] = {"wheat": 2}
	ordinary["pp"] = []
	ordinary["kp"] = []
	e["fams"].append(ordinary)
	Families.identity(e, ordinary)
	var leader: Array = native.person(e, ordinary, int(e["next_pid"]), 0, 42, "Cadet father")
	leader[Persons.HOUSE_UID] = king[Persons.HOUSE_UID]
	leader[Persons.FATHER_UID] = king[Persons.PERSON_UID]
	ordinary["pp"].append(leader)
	ordinary["m"] = 1
	var daughter: Array = native.child(e, ordinary, int(e["next_pid"]), 1, 25, leader, "Elder daughter")
	var son: Array = native.child(e, ordinary, int(e["next_pid"]), 0, 22, leader, "Younger son")
	e["pop"] = int(e["pop"]) + 3
	e["adults"] = int(e["adults"]) + 3
	Dynasty.prepare_world(Game)
	return {"town_id": "seat", "ordinary": ordinary, "ruling": ruling, "leader": leader, "son": son, "daughter": daughter}

func fingerprint() -> String:
	return JSON.stringify(Game._save_tree()) + "|%s|%s|%s" % [str(Game.rng.state), str(Unit._next_uid), str(Item._next_uid)]

func test_options_and_validation() -> void:
	var fx: Dictionary = fixture()
	var leader: Array = fx["leader"]
	var daughter: Array = fx["daughter"]
	var leader_uid: String = str(leader[Persons.PERSON_UID])
	var daughter_uid: String = str(daughter[Persons.PERSON_UID])
	var m_opts: Dictionary = CharacterDesign.options(Game, leader_uid)
	var m_choices: Dictionary = m_opts.get("choices", {})
	check(not m_opts.is_empty() and not m_choices.is_empty(), "options for male human ruler are non-empty")
	check(m_choices.has("skin") and m_choices.has("hair") and m_choices.has("seed") and m_choices.has("beard") and m_choices.has("beard_style") and not m_choices.has("female_set"), "male human options expose only male/human look keys")
	var f_opts: Dictionary = CharacterDesign.options(Game, daughter_uid)
	var f_choices: Dictionary = f_opts.get("choices", {})
	check(f_choices.has("skin") and f_choices.has("hair") and f_choices.has("seed") and f_choices.has("female_set") and not f_choices.has("beard") and not f_choices.has("beard_style"), "female human options expose female_set and omit beard keys")
	var elf_town: Dictionary = Game.world["towns"]["foreign"]
	var elf_p: Array = elf_town["econ"]["fams"][0]["pp"][0]
	var elf_choices: Dictionary = CharacterDesign.options(Game, str(elf_p[Persons.PERSON_UID])).get("choices", {})
	check(elf_choices.has("skin") and elf_choices.has("hair") and elf_choices.has("seed") and not elf_choices.has("beard") and not elf_choices.has("female_set"), "male moon_elf options omit beard and female_set")
	var before: String = fingerprint()
	for bad_name in ["", "A", "X".repeat(21), "Sir123", "Bad!Name", "-Aldric", "Aldric-"]:
		var res: Dictionary = CharacterDesign.preview(Game, leader_uid, {"first_name": bad_name})
		check(not bool(res.get("ok", true)), "bad first name '%s' is refused" % bad_name)
	check(not bool(CharacterDesign.preview(Game, leader_uid, {"look": {"female_set": 1}}).get("ok", true)), "female_set on male character is refused")
	check(not bool(CharacterDesign.preview(Game, leader_uid, {"focus": "sorcery"}).get("ok", true)), "invalid focus is refused")
	var skins: Array = m_choices["skin"]
	var hairs: Array = m_choices["hair"]
	var skin_val: String = str((skins[1] as Dictionary)["value"])
	var hair_val: String = str((hairs[2] as Dictionary)["value"])
	var pre: Dictionary = CharacterDesign.preview(Game, leader_uid, {
		"first_name": "Aldric",
		"look": {"skin": skin_val, "hair": hair_val, "seed": 3, "beard": true, "beard_style": 4},
		"focus": "martial",
	})
	check(bool(pre.get("ok", false)) and str(pre.get("name", "")) == "Aldric Native Cadet", "preview computes full name with family surname")
	check(fingerprint() == before, "preview and invalid checks mutate nothing")

func test_begin_portrait_bind_and_save() -> void:
	var fx: Dictionary = fixture()
	var f: Dictionary = fx["ordinary"]
	var leader: Array = fx["leader"]
	var son: Array = fx["son"]
	var leader_uid: String = str(leader[Persons.PERSON_UID])
	var m_choices: Dictionary = CharacterDesign.options(Game, leader_uid)["choices"]
	var skin_val: String = str(((m_choices["skin"] as Array)[1] as Dictionary)["value"])
	var hair_val: String = str(((m_choices["hair"] as Array)[2] as Dictionary)["value"])
	var custom: Dictionary = {
		"display_name": "Copper Oath",
		"emblem": "wolf",
		"primary_color": "#294A76",
		"secondary_color": "#E4C47D",
		"design": {
			"first_name": "Aldric",
			"look": {"skin": skin_val, "hair": hair_val, "seed": 4, "beard": true, "beard_style": 5},
			"focus": "martial",
		},
	}
	var before_preview: String = fingerprint()
	var pre_onboard: Dictionary = HouseOnboarding.preview(Game, "seat", str(f["household_uid"]), custom)
	check(bool(pre_onboard.get("ok", false)) and fingerprint() == before_preview, "HouseOnboarding.preview with custom.design changes nothing")
	var begun: Dictionary = HouseOnboarding.begin(Game, "seat", str(f["household_uid"]), custom, leader_uid)
	check(bool(begun.get("ok", false)), "HouseOnboarding.begin with custom.design succeeds")
	check(str(leader[7]) == "Aldric Native Cadet" and leader.size() <= Persons.FATHER_UID + 1, "apply writes p[7] = first + family name without adding person slots")
	check(str(Dynasty.ruler(Game).get("name", "")) == "Aldric Native Cadet" and str(Game.world["player_house"].get("ruler_name", "")) == "Aldric Native Cadet", "ruler name updated in Dynasty and player_house")
	var saved_design: Dictionary = Game.world["player_house"].get("design", {})
	check(str(saved_design.get("person_uid", "")) == leader_uid and str(saved_design.get("first_name", "")) == "Aldric" and str(saved_design.get("focus", "")) == "martial", "player_house.design stores person_uid, first_name and focus")
	var look_over: Dictionary = CharacterDesign.look_for(Game, leader_uid)
	check(str(look_over.get("skin", "")) == skin_val and str(look_over.get("hair", "")) == hair_val and int(look_over.get("seed", -1)) == 4 and int(look_over.get("beard_style", -1)) == 5, "look_for returns ruler overrides")
	check(CharacterDesign.look_for(Game, str(son[Persons.PERSON_UID])).is_empty(), "look_for returns empty dictionary for non-designed person")
	var spec: Dictionary = Dynasty.portrait_for(Game, Dynasty.ruler(Game), Game.world["player_house"]["customization"])
	check(spec.get("skin") == Color(skin_val) and spec.get("hair") == Color(hair_val) and int(spec.get("seed", -1)) == 4 and bool(spec.get("beard", false)) == true and int(spec.get("beard_style", -1)) == 5, "Dynasty.portrait_for for the ruler includes look overrides")
	var e: Dictionary = Game.world["towns"]["seat"]["econ"]
	var u: Unit = Unit.create("human", "middle_kingdom", false)
	u.home_town = "seat"
	var base_tactician: int = int(u.skills.get("tactician", 0))
	Persons.bind(e, f, leader, u, "company", float(Game.day))
	check(str(u.look.get("skin", "")) == skin_val and str(u.look.get("hair", "")) == hair_val and int(u.look.get("seed", -1)) == 4 and int(u.look.get("beard_style", -1)) == 5, "Persons.bind merges CharacterDesign.look_for into u.look")
	check(int(u.skills.get("tactician", 0)) == base_tactician + CharacterDesign.FOCUS_BONUS, "martial focus gives one-time bonus to existing tactician skill on bound unit")
	Persons.bind(e, f, leader, u, "company", float(Game.day))
	check(int(u.skills.get("tactician", 0)) == base_tactician + CharacterDesign.FOCUS_BONUS, "focus skill bonus is applied only once")
	check(not bool(CharacterDesign.apply(Game, str(son[Persons.PERSON_UID]), {"first_name": "Bram"}).get("ok", true)), "apply refused for non-ruler person")
	Game.day = 2.0
	check(not bool(CharacterDesign.apply(Game, leader_uid, {"first_name": "Cedric"}).get("ok", true)), "apply refused when Game.day > 1")
	check(str(leader[7]) == "Aldric Native Cadet", "refused apply after day 1 leaves ruler name unchanged")
	var raw_save: Variant = JSON.parse_string(JSON.stringify(Game._save_tree()))
	var saved_dict: Dictionary = raw_save if raw_save is Dictionary else {}
	var restored_world: Dictionary = Game._deserialize(saved_dict["world"])
	Game.world = restored_world
	CharacterDesign.after_load(Game)
	var after_look: Dictionary = CharacterDesign.look_for(Game, leader_uid)
	check(str(after_look.get("skin", "")) == skin_val and typeof(after_look.get("seed")) == TYPE_INT and int(after_look["seed"]) == 4 and typeof(after_look.get("beard_style")) == TYPE_INT and int(after_look["beard_style"]) == 5, "save/load and CharacterDesign.after_load preserve design and cast int look fields")

func run(_tree: SceneTree) -> int:
	test_options_and_validation()
	test_begin_portrait_bind_and_save()
	print("designer039: %d checks, %d failures" % [checks, fails])
	return fails
