extends RefCounted
## Actual registered holdings and native markets. Desktop-only read/fit checks.
const DESKTOP := Vector2i(1280, 720)
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL dragon care UI: ", why)

func snapshot() -> String:
	return JSON.stringify({"world": Game._serialize(Game.world), "gold": Game.gold, "unit": Unit._next_uid, "item": Item._next_uid, "rng": str(Game.rng.state)})

func labels(node: Node) -> String:
	if node == null: return ""
	var words: String = String(node.text) + "\n" if node is Label else ""
	for child in node.get_children(): words += labels(child)
	return words

func button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found: Button = button(child, text)
		if found != null: return found
	return null

func settle() -> void:
	for _i in 5: await tree.process_frame

func fit_check(fit: RefCounted, viewport: SubViewport, why: String) -> void:
	fit_cases += 1
	fit._check(viewport, Vector2(DESKTOP), why)

func patch_markets() -> void:
	for town: Dictionary in Game.world["towns"].values():
		var e: Dictionary = town["econ"]
		e["stock"]["fresh_meat"] = 50000
		e["stock"]["wood"] = 200
		e["price"]["fresh_meat"] = 3.0
		e["price"]["wood"] = 2.0
		e["mkt"] = e["biz"].size()
		e["biz"].append({"id": e["mkt"], "kind": "market", "owner": 0, "till": 0.0})
		e["stats"] = {"sales": 0.0}; e["req"] = {}; e["led"] = {"used": {}}
		for family: Dictionary in e["fams"]: family["purse"] = 100000.0

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var fixture: RefCounted = load("res://tests/test_dragon_identities.gd").new()
	fixture.fixture(); patch_markets(); Dragons.init_world(Game)
	check(Dynasty.select_city(Game, "a"), "select actual native ruling house")
	var own: Array = Dragons.records(Game, String(Dynasty.selected(Game)["house_uid"]))
	var adult: Dictionary = {}
	var egg: Dictionary = {}
	for row: Dictionary in own:
		if String(row["stage"]) == "egg": egg = row
		else: adult = row
	check(not adult.is_empty() and not egg.is_empty(), "registered adult and egg exist")
	if adult.is_empty() or egg.is_empty(): fixture = null; tree = null; return fails
	var before: String = snapshot()
	var quote: Dictionary = DragonCare.status(Game, adult)
	check(snapshot() == before, "care status is pure")
	check(float(quote["food_need_kg"]) > 0 and float(quote["food_available_units"]) > 0, "quote uses real feeding need and stocked market")
	check(String(quote["payer_household_uid"]) == String(adult["owner_household_uid"]), "owning household pays rather than company or city")
	var origin: String = "b"
	Game.location = origin
	var party_pos: Vector2 = Game.world["party"]["pos"]
	Game.screen_params = {"back": "house", "back_params": {"origin": "care_ui"}}
	var orphan_baseline: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var viewport := SubViewport.new()
	viewport.size = DESKTOP; viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var page: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate()
	before = snapshot()
	viewport.add_child(page)
	await settle()
	fit_check(fit, viewport, "care roster desktop")
	check("Health:" in labels(page) and "Egg condition:" in labels(page), "roster shows actual adult/egg condition")
	check(snapshot() == before, "roster reads do not feed, charge, grow or create identities")
	page._open_dragon(String(adult["id"]))
	await settle()
	fit_check(fit, viewport, "adult care desktop")
	var words: String = labels(page)
	for label: String in ["Care & growth", "Health:", "Payer:", "Household purse:", "Spendable:", "Keeper:", "Next daily care", "Current market quote", "Food need:", "Estimated food cost:", "Shelter supplies (wood):", "Quotes are not payments."]:
		check(label in words, "adult care exposes " + label)
	check(String(quote["payer_name"]) in words, "actual payer name is visible")
	check(RecData.money(float(quote["payer_purse"])) in words, "actual private purse is visible")
	check("Healthy growth needs enough feed and care" in words and "shortages lower condition" in words, "growth/shortage explanation is clear")
	check("Growth toward next size:" in words or "Maximum size reached" in words, "growth uses player progress rather than internal points")
	check("points" not in labels(page.find_child("CareGrowth", true, false)), "care hides internal growth scalar")
	check("No daily care payment recorded yet." in words, "unpaid quote is not a fabricated receipt")
	check(button(page, "Choose custodian") != null, "existing real keeper order remains reachable")
	check(button(page, "Feed now") == null and button(page, "Fund care") == null, "care panel adds no fake feeding/funding actions")
	check(snapshot() == before, "opening details is pure")
	page._open_dragon(String(egg["id"]))
	await settle()
	fit_check(fit, viewport, "egg care desktop")
	var egg_panel: Node = page.find_child("CareGrowth", true, false)
	check(egg_panel != null, "egg care card exists")
	var egg_words: String = labels(egg_panel) if egg_panel != null else ""
	check("Egg condition:" in egg_words and "No meat required." in egg_words, "egg needs shelter rather than meat")
	check("Food need:" not in egg_words and "Growth toward" not in egg_words and "hatch" not in egg_words.to_lower(), "egg quote makes no adult feeding or hatching claims")
	check("Laid " in labels(page) and "days ago" in labels(page), "actual laid age remains visible")
	check(snapshot() == before, "egg care reads are pure")
	page._open_dragon(String(adult["id"]))
	await settle()
	Game.day = 1.0
	DragonCare.daily(Game, int(floor(Game.day)))
	adult = Dragons.get_record(Game, String(adult["id"]))
	quote = DragonCare.status(Game, adult)
	var receipt: Dictionary = quote["last"]
	check(not receipt.is_empty() and int(receipt.get("day", -1)) == 1, "actual daily charge produces receipt")
	check(float(receipt.get("food_cost", 0.0)) > 0 and float(receipt.get("upkeep_cost", 0.0)) > 0, "real stocked market supplies food and shelter")
	before = snapshot()
	Game.changed.emit()
	await settle()
	fit_check(fit, viewport, "actual daily receipt desktop")
	words = labels(page)
	check("Last daily care · Day 1" in words and "No daily care payment recorded yet." not in words, "signal refresh exposes actual receipt")
	check("Food bought:" in words and "Shelter supplies bought:" in words, "actual purchases are separate from next quote")
	check(RecData.money(float(receipt["food_cost"])) in words and RecData.money(float(receipt["upkeep_cost"])) in words, "receipt shows exact charged amounts")
	check("Grew this day" in words if float(receipt["growth_after"]) > float(receipt["growth_before"]) else "No growth this day" in words, "growth receipt reflects actual daily result")
	check(snapshot() == before, "receipt refresh does not run care or charge again")
	# Remove the actual keeper reference only in a copied display input.
	var no_keeper: Dictionary = adult.duplicate(true); no_keeper["custodian_person_uid"] = ""
	var interrupted: Dictionary = DragonCare.status(Game, no_keeper)
	check(not bool(interrupted["care_active"]) and int(interrupted["food_possible_units"]) == 0 and int(interrupted["upkeep_possible_units"]) == 0, "missing keeper prevents actual quoted purchases")
	check(String(interrupted["reason"]) in DragonsView.care_quote_text(no_keeper, interrupted), "keeper interruption shows authoritative reason")
	var local: Dictionary = Game.world["towns"][adult["location_town_id"]]["econ"]
	local["stock"]["fresh_meat"] = 0; local["stock"]["meat"] = 0; local["stock"]["wood"] = 0
	var shortage: Dictionary = DragonCare.status(Game, adult)
	check("Supplies short" in DragonsView.care_condition_text(adult, shortage), "roster condition reflects actual market shortage")
	Game.day = 2.0
	DragonCare.daily(Game, int(floor(Game.day)))
	adult = Dragons.get_record(Game, String(adult["id"]))
	quote = DragonCare.status(Game, adult); receipt = quote["last"]
	check(float(receipt["health_after"]) < float(receipt["health_before"]), "actual food/shelter shortage lowers recorded condition")
	before = snapshot()
	Game.changed.emit()
	await settle()
	fit_check(fit, viewport, "shortage care desktop")
	words = labels(page)
	check("Health: %.0f%%" % (float(quote["health"]) * 100.0) in words, "refresh displays actual lowered health")
	check(String(quote["reason"]) in words and "Last daily care · Day 2" in words, "shortage reason and actual latest receipt remain distinct")
	check(snapshot() == before, "shortage refresh is pure")
	# Registry copies are display inputs only; never write a fake death or keeper.
	var dead: Dictionary = adult.duplicate(true); dead["alive"] = false
	var dead_words: String = DragonsView.care_quote_text(dead, DragonCare.status(Game, dead))
	check("No daily feed or upkeep charge." in dead_words and "Next daily care" not in dead_words, "dead display has no next-day costs")
	check(DragonsView.care_condition_text(dead, {}) == "Deceased · No daily care charge", "dead roster does not promise care")
	var enemy: Dictionary = {}
	for row: Dictionary in Dragons.records(Game):
		if String(row["owner_house_uid"]) != String(adult["owner_house_uid"]): enemy = row; break
	check(not enemy.is_empty(), "actual foreign holding exists")
	if not enemy.is_empty():
		page._open_dragon(String(enemy["id"]))
		await settle()
		fit_check(fit, viewport, "foreign care desktop")
		var order: Button = button(page, "Choose custodian")
		check(order != null and order.disabled, "care view does not grant orders over foreign holdings")
	check(snapshot() == before, "foreign and deceased display helpers remain pure")
	check(Game.location == origin and Game.world["party"]["pos"] == party_pos, "browsing care never teleports party")
	page._back()
	check(Game.screen_params == {"origin": "care_ui"}, "Back restores existing caller context")
	check(Game.location == origin and Game.world["party"]["pos"] == party_pos, "Back does not move campaign location")
	viewport.queue_free(); page = null; viewport = null
	await settle()
	DragonRigArt.clear_texture_cache()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_baseline, "care view/refresh leaves no orphan controls")
	print("Dragon care UI: %d assertions, %d failures; %d desktop fit cases, %d fit failures." % [checks, fails, fit_cases, int(fit.fails)])
	var result: int = fails + int(fit.fails)
	fit.tree = null; fit = null; fixture = null; tree = null
	return result
