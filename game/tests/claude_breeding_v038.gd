extends RefCounted
## Roadmap v0.038 dragon hatching and breeding verification test.
var checks := 0
var fails := 0
var main: Node = null

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL breeding038: ", what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame

func step_day(n: int = 1) -> void:
	for i in n:
		Game.day = float(int(floor(float(Game.day))) + 1)
		var d: int = int(floor(float(Game.day)))
		DragonCare.daily(Game, d)
		DragonLife.daily(Game, d)

func run(tree: SceneTree) -> int:
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = Vector2i(1280, 720)
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	if not await DevTools.start_world(tree, "user://claude_breeding_v038-test.json"):
		printerr("FAIL: the start world did not load")
		return 1

	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if str(dragon.get("stage", "")) != "adult" or not bool(dragon.get("alive", false)):
			continue
		var owner: Dictionary = Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]):
			continue
		var res: Dictionary = HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"]))
		if bool(res.get("ok", false)):
			tid = str(owner["town_id"])
			break
	check(tid != "", "ruling house with founder dragons selected")
	if tid == "":
		print("breeding038: %d checks, %d failures" % [checks, fails])
		return fails

	var town_econ: Dictionary = Game.world["towns"][tid]["econ"]
	var stock: Dictionary = town_econ.get("stock", {})
	stock["grain"] = int(stock.get("grain", 0)) + 100000
	stock["meat"] = int(stock.get("meat", 0)) + 50000
	stock["wood"] = int(stock.get("wood", 0)) + 50000
	town_econ["stock"] = stock
	for fam: Dictionary in town_econ.get("fams", []):
		fam["purse"] = float(fam.get("purse", 0.0)) + 100000.0

	var player_house: String = str(Game.world.get("player_house", {}).get("house_uid", ""))
	var registry: Dictionary = Game.world["dragons"]["records"]
	var mother_uid := ""
	var father_uid := ""
	var foreign_uid := ""
	var remove_ids: Array = []
	for uid_key in registry.keys():
		var uid: String = str(uid_key)
		var row: Dictionary = registry[uid]
		if str(row.get("owner_house_uid", "")) == player_house:
			if str(row.get("stage", "")) == "adult" and str(row.get("sex", "")) == "female" and mother_uid == "":
				mother_uid = uid
			elif str(row.get("stage", "")) == "adult" and str(row.get("sex", "")) == "male" and father_uid == "":
				father_uid = uid
			else:
				remove_ids.append(uid)
		elif str(row.get("stage", "")) == "adult" and str(row.get("sex", "")) == "male" and foreign_uid == "":
			foreign_uid = uid
	for uid in remove_ids:
		registry.erase(uid)

	check(mother_uid != "" and father_uid != "" and foreign_uid != "", "found player mother, player father, and foreign male dragon")
	if mother_uid == "" or father_uid == "":
		print("breeding038: %d checks, %d failures" % [checks, fails])
		return fails

	var mother: Dictionary = registry[mother_uid]
	var father: Dictionary = registry[father_uid]
	mother["location_town_id"] = tid
	father["location_town_id"] = tid
	mother["care"]["health"] = 1.0
	father["care"]["health"] = 1.0

	# 1. Refused pairs: same sex, juvenile, other house, low health, marching, cooldown.
	father["sex"] = "female"
	var same_sex_res: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	check(not bool(same_sex_res.get("ok", true)), "refuses same-sex pair")
	father["sex"] = "male"

	var swapped_sex_res: Dictionary = DragonBreeding.pair_preview(Game, father_uid, mother_uid)
	check(not bool(swapped_sex_res.get("ok", true)), "refuses male-as-mother pair")

	father["stage"] = "juvenile"
	var juv_res: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	check(not bool(juv_res.get("ok", true)), "refuses juvenile dragon")
	father["stage"] = "adult"

	var other_house_res: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, foreign_uid)
	check(not bool(other_house_res.get("ok", true)), "refuses dragon from another house")

	mother["care"]["health"] = 0.5
	var low_health_res: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	check(not bool(low_health_res.get("ok", true)), "refuses unhealthy dragon (< 0.7)")
	mother["care"]["health"] = 1.0

	mother["campaign_march"] = {"enabled": true}
	var march_res: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	check(not bool(march_res.get("ok", true)), "refuses marching dragon")
	mother["campaign_march"] = {"enabled": false}

	# 2. Valid pair preview & pairing.
	var preview: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	check(bool(preview.get("ok", false)), "valid pair_preview succeeds (%s)" % str(preview.get("reason", "")))
	var est: int = int(preview.get("clutch_estimate", 0))
	check(est >= 1 and est <= 3, "clutch_estimate in 1..3 (got %d)" % est)
	var traits_prev: Dictionary = preview.get("traits_preview", {})
	check(traits_prev.has("possible_gems") and traits_prev.has("variation_average"), "traits_preview includes gems and variation_average")

	var pair_res: Dictionary = DragonBreeding.pair(Game, mother_uid, father_uid, preview)
	check(bool(pair_res.get("ok", false)), "DragonBreeding.pair establishes chosen pair")
	var pairs_state: Dictionary = Game.world["dragons"].get("pairs", {})
	check(pairs_state.has(mother_uid), "chosen pair recorded in Game.world.dragons.pairs")

	# UI: clear that pair, then store it again through Choose a mate → confirm.
	await ui_pair(tree, mother_uid, father_uid, foreign_uid, tid)

	# 3. Simulate up to 25 days; chosen pair lays 1-3 eggs.
	var laid_eggs: Array = []
	for d in 25:
		step_day(1)
		laid_eggs.clear()
		for row: Dictionary in registry.values():
			if bool(row.get("alive", false)) and str(row.get("owner_house_uid", "")) == player_house and str(row.get("stage", "")) == "egg":
				laid_eggs.append(row)
		if not laid_eggs.is_empty():
			break

	check(laid_eggs.size() >= 1 and laid_eggs.size() <= 3, "chosen pair laid %d egg(s) within 25 days" % laid_eggs.size())
	if laid_eggs.is_empty():
		print("breeding038: %d checks, %d failures" % [checks, fails])
		return fails

	await ui_egg_parents(tree, str((laid_eggs[0] as Dictionary).get("id", "")), str(mother.get("name", "")), str(father.get("name", "")))

	# Mother should now be on cooldown.
	var cd_res: Dictionary = DragonBreeding.pair_preview(Game, mother_uid, father_uid)
	check(not bool(cd_res.get("ok", true)), "mother on BREED_COOLDOWN after laying clutch")

	# 4. Inheritance checks on laid eggs.
	var first_egg: Dictionary = laid_eggs[0]
	var egg_uid: String = str(first_egg["id"])
	var parent_gems: Array = [str(mother["gem_id"]), str(father["gem_id"])]
	var parent_morphs: Array = [str(mother["morph_id"]), str(father["morph_id"])]
	var egg_gem: String = str(first_egg.get("gem_id", ""))
	var egg_morph: String = str(first_egg.get("morph_id", ""))
	check(str(first_egg.get("mother_uid", "")) == mother_uid and str(first_egg.get("father_uid", "")) == father_uid,
		"egg records both mother_uid and father_uid")
	check(egg_gem in parent_gems or DragonBreeding.is_rare_gem(egg_gem),
		"egg inherited gem (%s) from parents or rare catalog" % egg_gem)
	check(egg_morph in parent_morphs, "egg inherited morph (%s) from a parent" % egg_morph)
	var egg_var: Variant = first_egg.get("variation", {})
	check(egg_var is Dictionary and (egg_var as Dictionary).size() == DragonBreeding.VARIATION_CHANNELS.size(),
		"egg stores inherited variation channels")
	var mass_v: float = Dragons._variation(first_egg, "mass")
	var parent_mass_avg: float = 0.5 * (Dragons._variation(mother, "mass") + Dragons._variation(father, "mass"))
	check(absf(mass_v - parent_mass_avg) <= 0.025,
		"Dragons._variation reads inherited variation near parent average (%.4f vs %.4f)" % [mass_v, parent_mass_avg])

	# 5. Save and reload keeps pairs and casts int fields.
	Game.save_game()
	Game.wait_save()
	check(Game.load_game(), "save reloads")
	var reloaded_pairs: Dictionary = Game.world["dragons"].get("pairs", {})
	check(reloaded_pairs.has(mother_uid), "save/load preserves chosen pairs")
	if reloaded_pairs.has(mother_uid):
		var rp: Dictionary = reloaded_pairs[mother_uid]
		check(rp.get("paired_day") is int and rp.get("due_day") is int and rp.get("clutch_estimate") is int,
			"Dragons.after_load casts pair int fields after JSON load")

	# 6. Hatching & no-keeper half-speed incubation comparison.
	registry = Game.world["dragons"]["records"]
	mother = registry[mother_uid]
	father = registry[father_uid]
	var kept_egg: Dictionary = registry[egg_uid]
	var nokeeper_egg: Dictionary = DragonBreeding.spawn_egg(Game, mother, father, int(floor(float(Game.day))), 99)
	var nokeeper_uid: String = str(nokeeper_egg["id"])
	var owner_uid: String = str(mother.get("owner_person_uid", ""))
	kept_egg["custodian_person_uid"] = owner_uid
	kept_egg["incubation"] = 0.0
	kept_egg["care"]["health"] = 1.0
	nokeeper_egg["custodian_person_uid"] = ""
	nokeeper_egg["incubation"] = 0.0
	nokeeper_egg["care"]["health"] = 1.0
	# Laying spends the household down to its human-food reserve, so shelter for the
	# egg cannot be paid (care_ratio 0, incubation 0.25/day) even with wood in stock.
	# Refill above that reserve so this window is full care and hatches at HATCH_DAYS.
	var payer := str(kept_egg.get("owner_household_uid", ""))
	var hatch_econ: Dictionary = Game.world["towns"][str(kept_egg.get("location_town_id", ""))].get("econ", {})
	for fam: Dictionary in hatch_econ.get("fams", []):
		if str(fam.get("household_uid", "")) == payer:
			fam["purse"] = float(fam.get("purse", 0.0)) + 50000000.0
	step_day(int(DragonLife.HATCH_DAYS))
	kept_egg = registry[egg_uid]
	nokeeper_egg = registry[nokeeper_uid]
	check(str(kept_egg.get("stage", "")) == "juvenile", "egg with keeper hatched after HATCH_DAYS (%d days)" % int(DragonLife.HATCH_DAYS))
	check(str(nokeeper_egg.get("stage", "")) == "egg" and float(nokeeper_egg.get("incubation", 0.0)) > 0.0 and float(nokeeper_egg.get("incubation", 0.0)) <= DragonLife.HATCH_DAYS * 0.5 + 0.01,
		"no-keeper egg incubated at half speed (%.1f / %.1f)" % [float(nokeeper_egg.get("incubation", 0.0)), DragonLife.HATCH_DAYS])

	var hatch_event := {}
	for ev: Dictionary in kept_egg.get("history", []):
		if str(ev.get("kind", "")) == "hatched":
			hatch_event = ev
	check(str(hatch_event.get("mother_uid", "")) == mother_uid and str(hatch_event.get("father_uid", "")) == father_uid,
		"hatched history entry notes both parents")
	var prof: Dictionary = Dragons.physical_profile(Game, kept_egg)
	check(bool(prof.get("active", false)) and bool(prof.get("valid", false)),
		"hatched juvenile has valid physical_profile using inherited traits")

	print("breeding038: %d checks, %d failures" % [checks, fails])
	return fails

func labels(node: Node) -> String:
	var text := ""
	if node is Label: text = (node as Label).text + "\n"
	for child in node.get_children(): text += labels(child)
	return text

func ui_pair(tree: SceneTree, mother_uid: String, father_uid: String, foreign_uid: String, tid: String) -> void:
	var records: Dictionary = Game.world["dragons"]["records"]
	var state_pairs: Dictionary = Game.world["dragons"]["pairs"]
	state_pairs.erase(mother_uid)
	if records.has(mother_uid): (records[mother_uid] as Dictionary).erase("paired_with_uid")
	if records.has(father_uid): (records[father_uid] as Dictionary).erase("paired_with_uid")
	var foreign_town := ""
	var moved := false
	if foreign_uid != "" and records.has(foreign_uid):
		foreign_town = str(records[foreign_uid].get("location_town_id", ""))
		records[foreign_uid]["location_town_id"] = tid
		moved = true
	Game.screen_params = {"dragon_uid": mother_uid, "holdings": "house", "back": "map"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var page: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate()
	viewport.add_child(page)
	await frames(tree, 4)
	var button: Button = page.find_child("DragonPairButton", true, false)
	check(button != null and button.text == "Choose a mate" and not button.disabled, "DragonPairButton on the adult dragon")
	if button != null: button.pressed.emit()
	await frames(tree, 2)
	var refused: Button = null
	var mate: Button = null
	for node in page.find_children("DragonMateChoice", "Button", true, false):
		var choice: Button = node
		var id := str(choice.get_meta("mate_uid", ""))
		if id == foreign_uid: refused = choice
		elif id == father_uid: mate = choice
	var why := ""
	if foreign_uid != "":
		for node in page.find_children("DragonMateReason", "Label", true, false):
			if str(node.get_meta("mate_uid", "")) == foreign_uid:
				why = (node as Label).text
		check(refused != null and refused.disabled and why != "", "refused mate at the roost is greyed with the reason")
	if moved and records.has(foreign_uid):
		records[foreign_uid]["location_town_id"] = foreign_town
	check(mate != null and not mate.disabled, "eligible father can be chosen")
	if mate != null: mate.pressed.emit()
	await frames(tree, 2)
	var shown := labels(page)
	check(shown.contains("Clutch estimate:"), "confirm step shows the clutch estimate")
	check(shown.contains("Traits preview:"), "confirm step shows the traits preview")
	var confirm: Button = page.find_child("DragonPairConfirm", true, false)
	check(confirm != null and confirm.text == "Confirm", "confirm button is present")
	if confirm != null: confirm.pressed.emit()
	Game.wait_save()
	await frames(tree, 3)
	var stored: Dictionary = Game.world["dragons"].get("pairs", {})
	check(stored.has(mother_uid) and str(stored[mother_uid].get("father_uid", "")) == father_uid, "confirm stored the chosen pair")
	var father_name := str(records[father_uid].get("name", ""))
	check(labels(page).contains("Paired with %s; a clutch is expected around day" % father_name), "paired dragon names its mate")
	page.queue_free()
	viewport.queue_free()
	await frames(tree, 2)

func ui_egg_parents(tree: SceneTree, egg_uid: String, mother_name: String, father_name: String) -> void:
	Game.screen_params = {"dragon_uid": egg_uid, "holdings": "house", "back": "map"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var page: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate()
	viewport.add_child(page)
	await frames(tree, 3)
	check(labels(page).contains("Mother: %s, Father: %s" % [mother_name, father_name]), "egg shows Mother and Father when known")
	page.queue_free()
	viewport.queue_free()
	await frames(tree, 2)
