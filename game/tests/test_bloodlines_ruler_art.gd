extends RefCounted
## Real registered rulers -> imported Portrait, without Units or world generation.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0
var native: NativeFixture

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", message)

func snapshot() -> String:
	return JSON.stringify(Game._serialize({"world": Game.world, "gold": Game.gold, "day": Game.day,
		"location": Game.location, "company": Game.company, "squads": Game.squads}))

func population() -> int:
	var n := 0
	for town in Game.world["towns"].values(): n += Census.people(town["econ"])
	return n

func visible(image: Image) -> bool:
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5: n += 1
	return n > 300

func render_ruler(label: String, p: Array, sex: String, age: int, dead: bool) -> PackedByteArray:
	var before := snapshot(); var coin: float = native.total_coin(); var people := population()
	var next_unit := Unit._next_uid; var next_item := Item._next_uid
	var spec: Dictionary = Dynasty.portrait_spec(Game)
	var given: Dictionary = spec.duplicate(true)
	var uid := str(p[Persons.PERSON_UID])
	check(Dynasty.ruler(Game).get("person_uid", "") == uid and int(spec.get("seed", -1)) == (int(hash(uid)) & 0x7fffffff), label + ": real person identity sets stable portrait seed")
	check(spec.get("race", "") == "human" and spec.get("sex", "") == sex and int(spec.get("age", -1)) == age and bool(spec.get("dead", not dead)) == dead and spec.get("role", "") == "ruler", label + ": actual race, sex, age and living/dead state reach portrait spec")
	if sex == "female": check(not spec.get("beard", true), label + ": actual female ruler has no generated beard")
	var portrait := Portrait.new()
	portrait.set_spec(spec)
	check(portrait.unit == null and portrait._spec == given, label + ": native Portrait accepts civilian metadata without combat Unit")
	var image: Image = portrait.build_image()
	var bytes := PackedByteArray()
	check(image != null and image.get_size() == Vector2i(96, 96) and visible(image), label + ": imported native portrait produces visible 96px image")
	if image != null:
		bytes = image.get_data()
		var repeated: Image = portrait.build_image()
		check(repeated != null and repeated.get_data() == bytes and FigurePainter.render_bust(given).get_data() == bytes, label + ": repeated native rendering is deterministic and shares imported figure layers")
	check(spec == given and Dynasty.portrait_spec(Game) == given, label + ": drawing preserves spec and repeated ruler read")
	check(snapshot() == before and absf(native.total_coin() - coin) < 0.000001 and population() == people and Unit._next_uid == next_unit and Item._next_uid == next_item, label + ": portrait reads preserve campaign state, population, all accounts and native identities")
	portrait.free()
	return bytes

func run(_tree: SceneTree) -> int:
	native = NativeFixture.new(); native.fixture()
	var e: Dictionary = Game.world["towns"]["seat"]["econ"]
	var f: Dictionary = e["fams"][0]; var male: Array = f["pp"][0]
	var female: Array = native.child(e, f, 1, 1, 28, male, "Registered female ruler")
	var minor: Array = native.child(e, f, 2, 0, 12, male, "Registered minor successor")
	e["pop"] += 2; e["adults"] += 1
	Dynasty.prepare_world(Game)
	var next_unit := Unit._next_uid; var next_item := Item._next_uid; var coin: float = native.total_coin()
	var adult_image: PackedByteArray = render_ruler("male adult", male, "male", 50, false)
	# Explicit fixture office transitions exercise art binding, not inheritance law.
	check(Dynasty.appoint(Game, "seat", str(female[Persons.PERSON_UID])), "appoint actual registered female for portrait fixture")
	var female_image: PackedByteArray = render_ruler("female adult", female, "female", 28, false)
	check(adult_image != female_image, "distinct actual rulers produce distinct portrait images")
	Census.person_died(e, f, female, float(Game.day), "accident", "portrait fixture")
	Persons.remove(f, female, e); f["f"] -= 1; e["pop"] -= 1; e["adults"] -= 1
	var dead_image: PackedByteArray = render_ruler("remembered dead female", female, "female", 28, true)
	check(dead_image != female_image and Game.world["player_house"]["ruler_uid"] == female[Persons.PERSON_UID], "actual death changes portrait while read leaves dead ruler selected")
	check(Dynasty.appoint(Game, "seat", str(minor[Persons.PERSON_UID])), "appoint actual registered minor successor for portrait fixture")
	var minor_image: PackedByteArray = render_ruler("minor successor", minor, "male", 12, false)
	check(Dynasty.town_office(Game, "seat").get("regency", false) and minor_image != dead_image, "real minor successor replaces dead portrait with actual age and visible regency metadata")
	check(Unit._next_uid == next_unit and Item._next_uid == next_item and absf(native.total_coin() - coin) < 0.000001, "all fixture office/death transitions and portraits use no new Units, Items or money")
	print("Bloodlines ruler art: %d checks, %d failures" % [checks, fails])
	return fails
