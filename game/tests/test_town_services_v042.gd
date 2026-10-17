extends RefCounted
## Real service quotes, native callbacks, browsing purity and four native canvas sizes.
const H = preload("res://tests/health_util.gd")
const SIZES := [Vector2i(960, 640), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(720, 1280)]
var fails := 0
var checks := 0
var tree: SceneTree
var fit

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

## Deliberately mild-first roster: a batch must use medical severity, not display order.
static func patients() -> Array:
	var men := [H.human("Bruised scout"), H.human("Wounded guard"), H.human("Broken-legged veteran")]
	var wounds := [[0, "leg_upper_r", "skin", "bruised", 0.3, 0.0],
		[1, "arm_upper_r", "muscle", "torn", 0.6, 0.02],
		[2, "leg_lower_l", "bone", "broken", 0.8, 0.02],
		[2, "arm_upper_l", "bone", "fractured", 0.6, 0.0]]
	for wound in wounds:
		var u: Unit = men[int(wound[0])]
		u.body.wound_part(String(wound[1]))
		H.wound(u, String(wound[1]), String(wound[2]), String(wound[3]), float(wound[4]), float(wound[5]))
	for i in men.size():
		var u: Unit = men[i]
		u.wage = 11 + i * 7
		Healing.update_heal_days(u)
		Healing.treatment_cost(u, 8) # existing assessment is deliberately before the purity boundary
	return men

## A destroyed bone heals closed through the real healing rule with guaranteed lasting damage.
static func lasting_injury() -> Unit:
	var u: Unit = H.human("Veteran with a badly mended leg")
	u.body.wound_part("leg_lower_l")
	H.wound(u, "leg_lower_l", "bone", "destroyed", 1.0)
	Healing.update_heal_days(u)
	Healing.heal(u, 1000.0, true, 0)
	Healing.treatment_cost(u, 8)
	return u

static func fixture(seed: int = 40042, presim: bool = false) -> Dictionary:
	Game.new_game(seed)
	if presim: CampaignWorld.presim_step(Game, 1)
	var town: Dictionary = Game.world["towns"][Game.world["factions"]["middle_kingdom"]["capital"]]
	Game.location = String(town["id"])
	Game.screen_params = {"tab": "Healer"}
	town["healer"] = {"skill": 8, "name": "Town physician"}
	Game.company = patients()
	Game.gold = 100000
	# Real generated offers, including several kinds, with their original IDs and terms.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42077
	var seen := {}
	var offers := []
	for c in town.get("contracts", []):
		if not seen.has(c["id"]):
			seen[c["id"]] = true
			offers.append(c)
	for day_offset in 6:
		for c in Contracts.generate_offers(town, Game.day + day_offset + 1, rng):
			if not seen.has(c["id"]):
				seen[c["id"]] = true
				offers.append(c)
	town["contracts"] = offers
	return town

func run(t: SceneTree) -> int:
	tree = t
	await tree.process_frame # runner invokes run while its parent is entering the tree
	fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	var town := fixture()
	check(TownEcon.has_econ(town), "actual registered capital economy")
	check(Contracts.offers_for(Game, town).size() >= 3, "real generated eligible contracts")
	for size in SIZES:
		if not await _browse(size, town):
			printerr("Town services setup failed; stopping before dependent actions")
			return maxi(1, fails)
	await _actions(town)
	fails += int(fit.fails)
	print("Town services v042: ", checks, " checks, ", fails, " failures; fit failures=", fit.fails)
	return fails

func _settle() -> void:
	for i in 3: await tree.process_frame

func _screen(size: Vector2i, tab: String) -> Array:
	Game.screen_params = {"tab": tab}
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child.call_deferred(viewport)
	await tree.process_frame
	var scene: PackedScene = load("res://ui/town.tscn")
	if scene == null:
		check(false, "town scene loads successfully")
		viewport.queue_free()
		await tree.process_frame
		return []
	var screen: Control = scene.instantiate()
	if not screen.has_method("show_tab") or not screen.has_method("_treat_queue"):
		check(false, "town script and service dependencies compile successfully")
		screen.free()
		viewport.queue_free()
		await tree.process_frame
		return []
	viewport.add_child(screen)
	await _settle()
	if not screen.is_node_ready() or screen.find_child("HealerView" if tab == "Healer" else "TownContracts", true, false) == null:
		check(false, "town %s builds and enters the scene tree" % tab)
		viewport.queue_free()
		await tree.process_frame
		return []
	return [viewport, screen]

func _purity(before: Dictionary, random_state: int, label: String) -> void:
	check(Game._save_tree() == before and Game.rng.state == random_state, label + " leaves the entire saved campaign and RNG unchanged")

func _layout(viewport: SubViewport, size: Vector2i, label: String) -> void:
	fit._check(viewport, Vector2(size), label)
	var service: Node = viewport.find_child("HealerView", true, false)
	if service == null: service = viewport.find_child("TownContracts", true, false)
	if service != null:
		for node in _nodes(service):
			if node is ScrollContainer:
				check(node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, label + " never hides service content in horizontal scrolling")

func _browse(size: Vector2i, town: Dictionary) -> bool:
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	var pair := await _screen(size, "Healer")
	if pair.is_empty(): return false
	var viewport: SubViewport = pair[0]
	var screen: Control = pair[1]
	_healer_facts(screen, town)
	_layout(viewport, size, "Healer wounded")
	_open_disclosures(screen, "Wound details")
	await _settle()
	check(_texts(screen).to_lower().contains("fractured") or _texts(screen).to_lower().contains("broken"), "expanded wound details display actual injuries")
	_layout(viewport, size, "Healer wound details")
	_purity(before, random_state, "Healer quotes and wound disclosure")
	var company: Array = Game.company
	var healer: Dictionary = town["healer"]
	Game.company = [H.human("Fit guard")]
	before = Game._save_tree()
	screen.refresh()
	await _settle()
	check((screen.find_child("TreatAll", true, false) as Button).disabled, "healthy company cannot buy treatment")
	check(_texts(screen).contains("Everyone in the company is fit"), "healthy company has truthful empty state")
	_layout(viewport, size, "Healer healthy")
	_purity(before, random_state, "Healthy healer browsing")
	var impaired := lasting_injury()
	var impairment_report := HealthReport.describe(impaired)
	check(not impaired.body.is_wounded() and impairment_report["status"] == "healthy" and impairment_report["fitness"] != "fit to fight" and not impaired.body.permanent.is_empty(), "real healed bone leaves lasting impairment without an open wound")
	Game.company = [impaired]
	before = Game._save_tree()
	screen.refresh()
	await _settle()
	var impairment_card := screen.find_child("Patient_%d" % impaired.uid, true, false)
	check(impairment_card != null and _texts(impairment_card).contains(String(impairment_report["fitness"])), "lasting impairment has a visible health card with actual fitness")
	check((screen.find_child("TreatAll", true, false) as Button).disabled and screen.find_child("Treat_%d" % impaired.uid, true, false) == null, "lasting impairment cannot be charged for needless treatment")
	check(not _texts(screen).contains("Everyone in the company is fit"), "lasting impairment never produces false everyone-fit message")
	_open_disclosures(screen, "Wound details")
	await _settle()
	check(_texts(screen).contains(String(impaired.body.permanent[0])), "lasting injury details preserve actual permanent injury record")
	_layout(viewport, size, "Healer lasting impairment")
	_purity(before, random_state, "Lasting impairment browsing and details")
	Game.company = company
	town["healer"] = {}
	before = Game._save_tree()
	screen.refresh()
	await _settle()
	check((screen.find_child("TreatAll", true, false) as Button).disabled, "no healer cannot offer treatment")
	check(_texts(screen).contains("No healer here"), "missing healer displayed explicitly")
	_layout(viewport, size, "Healer absent")
	_purity(before, random_state, "No healer browsing")
	town["healer"] = healer
	Game.gold = 0
	before = Game._save_tree()
	screen.refresh()
	await _settle()
	check(not (screen.find_child("TreatAll", true, false) as Button).disabled, "zero coin can still review critical-first batch quote")
	for u: Unit in Game.company:
		check((screen.find_child("Treat_%d" % u.uid, true, false) as Button).disabled, "unaffordable individual treatment disabled")
	_layout(viewport, size, "Healer zero coins")
	_purity(before, random_state, "Unfunded healer browsing")
	Game.gold = 100000
	screen.show_tab("Contracts")
	await _settle()
	before = Game._save_tree()
	await _contract_controls(screen, town)
	_layout(viewport, size, "Contracts filtered and detailed")
	_purity(before, random_state, "Contract sorting searching and details")
	var offers: Array = town["contracts"]
	town["contracts"] = []
	before = Game._save_tree()
	screen.refresh()
	await _settle()
	check(_offer_nodes(screen).is_empty() and _texts(screen).contains("No one here has work"), "empty board cannot invent jobs")
	_layout(viewport, size, "Contracts empty")
	_purity(before, random_state, "Empty contract board")
	town["contracts"] = offers
	var fid := String(town["faction"])
	var player: Dictionary = Game.world["diplo"]["player"][fid]
	var saved_player := player.duplicate(true)
	player["earned"] = -80.0
	player["comp"] = 0
	before = Game._save_tree()
	screen.refresh()
	await _settle()
	check(not Diplomacy.contracts_allowed(Game, fid) and _offer_nodes(screen).is_empty(), "refused standing hides actual ineligible jobs")
	check(_texts(screen).contains("standing -80"), "refused board gives actual standing")
	_layout(viewport, size, "Contracts refused standing")
	_purity(before, random_state, "Refused contract board")
	Game.world["diplo"]["player"][fid] = saved_player
	viewport.queue_free()
	await tree.process_frame
	return true

func _healer_facts(screen: Control, town: Dictionary) -> void:
	var view := screen.find_child("HealerView", true, false)
	check(view != null and view.has_meta("healer_snapshot"), "native healer summary available")
	if view == null or not view.has_meta("healer_snapshot"): return
	var data: Dictionary = view.get_meta("healer_snapshot")
	var total := 0
	for u: Unit in Game.company:
		var cost := Healing.treatment_cost(u, int(town["healer"]["skill"]))
		total += cost
		var card := screen.find_child("Patient_%d" % u.uid, true, false)
		check(card != null, "every wounded unit gets its own native card")
		if card == null: continue
		var patient: Dictionary = card.get_meta("healer_patient")
		var report := HealthReport.describe(u)
		check(patient["uid"] == u.uid and patient["cost"] == cost and patient["report"] == report, "patient facts match body and existing treatment quote")
		check(patient["fitness"] == report["fitness"] and is_equal_approx(float(patient["heal_days"]), maxf(float(report["heal_days"]), u.body.days_to_heal())), "patient fitness and recovery estimate come from actual health")
		check(_texts(card).contains(str(cost) + " coins") and _texts(card).contains(u.name), "actual patient and price rendered visibly")
	check(data["quote"] == total and data["treatable"] == 3 and data["wages"] == Game.daily_wages(), "summary sums real individual quotes and wages")
	check(_texts(view).contains("%d coins" % total), "batch total visibly rendered")
	for days in [1, 3, 7]:
		var button := screen.find_child("Rest%d" % days, true, false) as Button
		check(button != null and button.get_meta("rest_quote")["wages_quote"] == Game.daily_wages() * days and button.text.contains(str(Game.daily_wages() * days)), "rest displays exact current wage quote for %d days" % days)

func _contract_controls(screen: Control, town: Dictionary) -> void:
	var available := Contracts.offers_for(Game, town)
	var expected := {}
	var types := {}
	for c: Dictionary in available:
		expected[String(c["id"])] = c
		types[String(Contracts.KIND_INFO.get(c["kind"], {}).get("name", String(c["kind"]).capitalize()))] = true
	check(_offer_nodes(screen).size() == available.size(), "initial board includes every eligible real offer")
	for panel in _offer_nodes(screen):
		var entry: Dictionary = panel.get_meta("contract_offer")
		var c: Dictionary = expected.get(entry["id"], {})
		check(not c.is_empty(), "native offer ID resolves to actual town offer")
		if c.is_empty(): continue
		check(entry["pay"] == Contracts.offered_pay(Game, c) and entry["duration"] == c.get("duration", null), "offer quotes reflect negotiation and actual duration")
		check(_texts(panel).contains(String(c["title"])) and _texts(panel).contains(str(Contracts.offered_pay(Game, c))), "real title and negotiated coins visible")
		var details: Control = panel.find_child("ContractDetailsBody", true, false)
		check(details != null and not details.visible and details.get_child_count() == 0, "description remains lazy until requested")
		(panel.find_child("ContractDetails", true, false) as Button).pressed.emit()
		check(details.visible and _texts(details).contains(String(c.get("desc", ""))), "Details opens original description")
		break
	var category := screen.find_child("ContractCategory", true, false) as OptionButton
	check(category != null and category.item_count == types.size() + 1, "type selector groups actual available job kinds")
	if category != null and category.item_count > 1:
		category.select(1)
		category.item_selected.emit(1)
		await _settle()
		var selected := category.get_item_text(1)
		var matching := 0
		for c: Dictionary in available:
			if String(Contracts.KIND_INFO.get(c["kind"], {}).get("name", String(c["kind"]).capitalize())) == selected: matching += 1
		check(_offer_nodes(screen).size() == matching, "native type selection filters every matching offer")
		category.select(0)
		category.item_selected.emit(0)
	var sort := screen.find_child("ContractSort", true, false) as OptionButton
	for index in [0, 1, 2]:
		sort.select(index)
		sort.item_selected.emit(index)
		await _settle()
		var previous_pay := 2147483647
		var previous_time := -INF
		var previous_name := ""
		for panel in _offer_nodes(screen):
			var entry: Dictionary = panel.get_meta("contract_offer")
			var c: Dictionary = expected[entry["id"]]
			var title := String(c["title"]).to_lower()
			if index == 0: check(previous_name <= title, "native job sort alphabetical")
			if index == 1: check(previous_pay >= int(entry["pay"]), "native pay sort descending actual quotes")
			if index == 2: check(previous_time <= float(c.get("duration", INF)), "native time sort ascending actual durations")
			previous_name = title
			previous_pay = int(entry["pay"])
			previous_time = float(c.get("duration", INF))
	var search := screen.find_child("ContractSearch", true, false) as LineEdit
	search.text = "a deliberately absent contract phrase 42042"
	search.text_changed.emit(search.text) # assigning text does not simulate the native edit signal
	await _settle()
	check(_offer_nodes(screen).is_empty() and _texts(screen).contains("No matching jobs"), "native search distinguishes no match from no offers")
	(screen.find_child("ContractClear", true, false) as Button).pressed.emit()
	await _settle()
	check(search.text == "" and _offer_nodes(screen).size() == available.size(), "Clear restores all eligible offers")
	if not available.is_empty():
		search.text = String(available[0]["title"]).to_upper()
		search.text_changed.emit(search.text)
		await _settle()
		check(not _offer_nodes(screen).is_empty(), "native search matches actual job title without case sensitivity")
		for panel in _offer_nodes(screen):
			var c: Dictionary = expected[panel.get_meta("contract_offer")["id"]]
			check((String(c["title"]) + " " + String(c.get("desc", ""))).to_lower().contains(search.text.to_lower()), "search results genuinely match entered title")
		(screen.find_child("ContractClear", true, false) as Button).pressed.emit()
		await _settle()
	var panels := _offer_nodes(screen)
	if not panels.is_empty():
		(panels[0].find_child("ContractDetails", true, false) as Button).pressed.emit()
		await _settle()

func _actions(town: Dictionary) -> void:
	if Game.company.size() != 3:
		check(false, "action fixture preserves all three preassessed patients")
		return
	var pair := await _screen(Vector2i(1280, 720), "Healer")
	if pair.is_empty(): return
	var viewport: SubViewport = pair[0]
	var screen: Control = pair[1]
	var men: Array = Game.company
	var costs := men.map(func(u): return Healing.treatment_cost(u, 8))
	Game.gold = int(costs[2]) + int(costs[1])
	screen.refresh()
	await _settle()
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	(screen.find_child("TreatAll", true, false) as Button).pressed.emit()
	await _settle()
	check(_modal(screen) != null and _texts(_modal(screen)).contains(str(int(costs[0]) + int(costs[1]) + int(costs[2]))), "native Treat all confirms full actual quote")
	_purity(before, random_state, "Treatment confirmation before approval")
	_press_text(_modal(screen), "Cancel")
	await _settle()
	_purity(before, random_state, "Cancelled treatment")
	var market_before := Goods.market_gold(town)
	(screen.find_child("TreatAll", true, false) as Button).pressed.emit()
	_press_text(_modal(screen), "Treat all")
	await _settle()
	check(Game.gold == 0 and is_equal_approx(Goods.market_gold(town) - market_before, float(costs[2] + costs[1])), "approved batch transfers exactly affordable quote to real market ledger")
	check(Healing.treatment_cost(men[2], 8) == 0 and Healing.treatment_cost(men[1], 8) == 0 and Healing.treatment_cost(men[0], 8) == costs[0], "native batch treats critical and serious before first mild roster entry")
	check(_texts(_modal(screen)).contains(men[0].name) and _texts(_modal(screen)).contains("Not treated"), "partial batch names the untreated patient")
	_press_text(_modal(screen), "OK")
	await _settle()
	Game.gold = int(costs[0]) + 1000
	market_before = Goods.market_gold(town)
	screen.refresh()
	await _settle()
	(screen.find_child("Treat_%d" % men[0].uid, true, false) as Button).pressed.emit()
	await _settle()
	check(Game.gold == 1000 and is_equal_approx(Goods.market_gold(town) - market_before, float(costs[0])) and Healing.treatment_cost(men[0], 8) == 0, "native individual treatment uses actual patient and exact quote")
	Game.gold = 100000
	var routes := []
	var on_route := func(destination: String): routes.append(destination)
	Game.screen_changed.connect(on_route)
	(screen.find_child("Sheet_%d" % men[1].uid, true, false) as Button).pressed.emit()
	Game.screen_changed.disconnect(on_route)
	check(routes == ["company"] and Game.screen_params.get("unit", -1) == men[1].uid and Game.screen_params.get("back", "") == "town", "native Sheet opens the selected wounded unit with town return route")
	Game.day = floorf(Game.day) + 0.25
	var day_before := Game.day
	var gold_before := Game.gold
	var wage := Game.daily_wages()
	var expected := []
	for u: Unit in men:
		var clone := Unit.from_dict(u.to_dict())
		Healing.heal(clone, 1.0, true, 8)
		expected.append(clone.body.days_to_heal())
	(screen.find_child("Rest1", true, false) as Button).pressed.emit()
	await _settle()
	check(is_equal_approx(Game.day, day_before + 1.0) and Game.gold == gold_before - wage, "native one-day rest advances exact time and pays one wage day")
	for i in men.size(): check(is_equal_approx(men[i].body.days_to_heal(), float(expected[i])), "rest applies existing in-town skilled healing")
	screen.show_tab("Contracts")
	await _settle()
	var chosen: Dictionary = {}
	for c: Dictionary in Contracts.offers_for(Game, town):
		if c["kind"] == "battle" and Contracts.refusal(Game, c) == "":
			chosen = c
			break
	check(not chosen.is_empty(), "real eligible hunt for native acceptance")
	if not chosen.is_empty():
		var pay := Contracts.offered_pay(Game, chosen)
		var id := String(chosen["id"])
		var accept: Button = null
		for node in _nodes(screen):
			if node is Button and node.has_meta("contract_id") and node.get_meta("contract_id") == id: accept = node
		check(accept != null and not accept.disabled, "native eligible offer acceptance enabled")
		if accept != null: accept.pressed.emit()
		await _settle()
		check(Game.contract.get("id", "") == id and Game.contract.get("state", "") == "active" and Game.contract.get("pay", -1) == pay, "native acceptance locks actual selected offer and negotiated pay")
		check(not Game.contract.get("target_id", "").is_empty() and Game.world["warbands"].has(Game.contract.get("target_id", "")), "accepted job creates real registered campaign target")
		if not Game.contract.is_empty():
			before = Game._save_tree()
			random_state = Game.rng.state
			for size in SIZES:
				viewport.size = size
				await _settle()
				_open_disclosures(screen, "Contract details")
				await _settle()
				_layout(viewport, size, "Contracts active and details")
				check(_texts(screen).contains(Contracts.status_text(Game)), "active view shows actual deadline and agreed pay")
			_purity(before, random_state, "Active contract and details browsing at all sizes")
			for node in _nodes(screen):
				if node is Button and node.name == "AcceptContract": check(node.disabled, "all other accept controls disabled while active")
			var standing := Diplomacy.standing(Game, String(town["faction"]))
			before = Game._save_tree()
			random_state = Game.rng.state
			(screen.find_child("AbandonContract", true, false) as Button).pressed.emit()
			await _settle()
			_purity(before, random_state, "Abandon confirmation before approval")
			_press_text(_modal(screen), "Cancel")
			await _settle()
			_purity(before, random_state, "Cancelled abandonment")
			var target := String(Game.contract["target_id"])
			(screen.find_child("AbandonContract", true, false) as Button).pressed.emit()
			_press_text(_modal(screen), "Abandon")
			await _settle()
			check(Game.contract.is_empty() and Diplomacy.standing(Game, String(town["faction"])) == standing + Diplomacy.CONTRACT_ABANDONED, "approved abandonment clears real contract and applies exact standing penalty")
			check(Game.world["warbands"][target]["kind"] == "raider" and Game.world["warbands"][target]["contract_id"] == "", "abandoned real hunt releases target into ordinary raiders")
	viewport.queue_free()
	await tree.process_frame

func _nodes(node: Node) -> Array:
	var out := []
	if node == null or node.is_queued_for_deletion(): return out
	out.append(node)
	for child in node.get_children(): out.append_array(_nodes(child))
	return out

func _offer_nodes(node: Node) -> Array:
	return _nodes(node).filter(func(n): return n.has_meta("contract_offer"))

func _texts(node: Node) -> String:
	var out := PackedStringArray()
	for n in _nodes(node):
		if n is RecCells:
			# These are the exact strings configured into the native drawn TextLine cells.
			for value in n.get_meta("rec_values", []): out.append(String(value))
		elif n is Label or n is Button: out.append(String(n.text))
	return "\n".join(out)

func _modal(node: Node) -> Node:
	for n in _nodes(node):
		if n.has_meta("ui_modal"): return n
	return null

func _press_text(node: Node, caption: String) -> void:
	for n in _nodes(node):
		if n is Button and n.text == caption:
			n.pressed.emit()
			return
	check(false, "native modal action exists: " + caption)

func _open_disclosures(node: Node, title: String) -> void:
	for n in _nodes(node):
		if n.has_meta("rec_disclosure") and n.get_meta("rec_disclosure") == title:
			if not n.get_child(1).visible: (n.get_child(0) as Button).pressed.emit()
