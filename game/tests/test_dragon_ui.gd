extends RefCounted
const Observations = preload("res://tests/class_d_observations.gd")
var failed_assertions: Array[String] = []
var failed_fits: Array[Dictionary] = []
var _deadline_msec: int = 0
var _budget_failed: bool = false
## Native tiny economies, additive portraits and real orders. Desktop only.
var tree: SceneTree
var checks := 0
var fails := 0
var fit_cases := 0
const DESKTOP := Vector2i(1280, 720)

func run(scene_tree: SceneTree) -> int:
	_deadline_msec = Time.get_ticks_msec() + 150000
	_budget_failed = false
	var result: int = await _run(scene_tree)
	if not _within_budget(): result = maxi(1, result)
	return result

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	if not _budget_failed:
		_budget_failed = true
		_assert(false, "dragon UI exceeded 150 seconds; incomplete coverage is a failure")
	return false

func _run(scene_tree: SceneTree) -> int:
	checks = 0; fails = 0; fit_cases = 0
	failed_assertions.clear(); failed_fits.clear()
	tree = scene_tree
	await tree.process_frame
	var section: String = "all"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--section="): section = argument.trim_prefix("--section=")
	if not section in ["all", "pictures", "controls"]:
		push_error("Unknown dragon UI test section"); tree = null; return 1
	print("Dragon UI section: " + section)
	if not await _native_campaign(): tree = null; return maxi(1, fails)
	var book: Dictionary = Game.world["dragons"].duplicate(true)
	var seat: String = DevTools.choose_house(Game, _house_ready)
	_assert(seat != "", "native generated house needs its actual three holdings, existing adult heir and different recipient")
	if seat == "": tree = null; return maxi(1, fails)
	var recipient: Dictionary = _recipient(seat)
	_assert(not recipient.is_empty(), "native different-town recipient remains available after onboarding")
	if recipient.is_empty(): tree = null; return maxi(1, fails)
	_assert(Game.world["dragons"] == book, "selection does not regenerate holdings")
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var fit = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	Game.location = str(recipient["town_id"])
	Game.screen_params = {"back": "house", "back_params": {"origin": "dragon_check"}}
	var origin := Game.location
	var position: Vector2 = Game.world["party"]["pos"]
	var viewport := SubViewport.new(); viewport.size = DESKTOP
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var page: DragonsView = (load("res://ui/dragons.tscn") as PackedScene).instantiate()
	var before := _snapshot()
	viewport.add_child(page)
	await _settle()
	_fit(fit, viewport, "dragon house roster")
	var own: Array = Dragons.records(Game, String(Dynasty.selected(Game)["house_uid"]))
	_assert(page.roster == own and own.size() == 3, "default roster is actual house's three holdings")
	_assert(not own.is_empty() and Dragons.type_label(own[0]) in _labels(page), "roster names each holding's gem type and body form")
	_assert(_snapshot() == before, "roster reads and images preserve world, RNG and identities")
	_assert(Game.location == origin and Game.world["party"]["pos"] == position, "entry does not move campaign context or party")
	var heading: Label = page.find_child("Title", true, false)
	_assert(heading != null and heading.text == "Dragons & eggs", "full dragon view title")
	if heading != null:
		_assert(heading.size.x >= heading.get_theme_font("font").get_string_size(heading.text, HORIZONTAL_ALIGNMENT_LEFT, -1, heading.get_theme_font_size("font_size")).x, "dragon title fits all glyphs")
	if section != "controls": await _pictures(page, viewport, fit)
	if section == "pictures":
		viewport.queue_free(); page = null; viewport = null
		await _settle()
		_assert(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_baseline, "catalog controls leave no orphan nodes")
		_report_failures(fit, section)
		var picture_result: int = fails + int(fit.fails)
		print("Dragon UI: %d assertions, %d failures; %d desktop fit cases, %d fit failures." % [checks, fails, fit_cases, int(fit.fails)])
		fit.tree = null; fit = null; tree = null
		return picture_result
	var egg := {}
	var adult := {}
	for row: Dictionary in own:
		if row["stage"] == "egg": egg = row
		else: adult = row
	_assert(not egg.is_empty() and not adult.is_empty(), "real egg and adult fixtures available")
	if not egg.is_empty():
		page._open_dragon(String(egg["id"]))
		await _settle()
		_fit(fit, viewport, "actual egg details")
		var labels := _labels(page)
		for label in ["Owner:", "Owning household:", "Custodian:", "Location:", "Estate:", "Shell:", "Laid ", "days ago", "Unbonded", "Mother:", "Father:"]:
			_assert(label in labels, "actual detail exposes " + label)
		_assert("Laid %d days ago" % int(floor(maxf(0, Game.day - float(egg["laid_day"])))) in labels, "egg elapsed time comes from actual laid date")
		_assert("Gem colour:" not in labels and String(DragonCard.catalog_entry("sizes", String(egg["size_class"]))["name"]) not in labels, "egg details do not claim an adult body size")
		_assert("Physical profile" not in labels and "Bite force:" not in labels and "Body form:" not in labels, "egg detail makes no active force or adult form claims")
		_assert(not bool(Dragons.physical_profile(Game, egg).get("active", true)) and DragonsView.physical_text(Dragons.physical_profile(Game, egg)) == "", "inactive egg profile has no adult force text")
		_assert(String(egg["name"]) in labels and String(egg["name"]) == String(DragonCard.catalog_entry("gems", String(egg["gem_id"]))["name"]) + " Egg", "egg name is canonical gem name")
		var mother := _button(page, "View mother")
		_assert(mother != null, "recorded mother has a reachable detail link")
		if mother != null: mother.pressed.emit()
		await _settle()
		_fit(fit, viewport, "actual mother details")
		_assert(page.detail_uid == String(egg["mother_uid"]) and String(Dragons.get_record(Game, String(egg["mother_uid"]))["name"]) in _labels(page), "parent navigation resolves exact registered dragon")
		_profiles(page, Dragons.get_record(Game, String(egg["mother_uid"])))
		await _orders(page, viewport, fit, egg, recipient)
	if not adult.is_empty():
		await _sprite_controls(page, viewport, fit, adult)
		await _stale_ruler(page, viewport, fit, adult, recipient)
	page._back()
	_assert(Game.location == origin and Game.world["party"]["pos"] == position, "Back does not teleport or change location")
	_assert(Game.screen_params == {"origin": "dragon_check"}, "Back restores caller parameters")
	viewport.queue_free(); page = null; viewport = null
	await _settle()
	_assert(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_baseline, "dragon controls and cancelled sheets leave no orphan nodes")
	Game.wait_save()
	_report_failures(fit, section)
	var result: int = fails + int(fit.fails)
	print("Dragon UI: %d assertions, %d failures; %d desktop fit cases, %d fit failures." % [checks, fails, fit_cases, int(fit.fails)])
	fit.tree = null; fit = null
	book.clear(); own.clear(); egg.clear(); adult.clear()
	await _settle()
	tree = null
	return result

func _native_campaign() -> bool:
	var old_size: String = WorldGen.gen_size
	var old_history: int = CampaignWorld.presim_span_days
	var old_creatures: bool = Monsters.new_world_creatures
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = false
	var ok: bool = await _generate_native()
	WorldGen.gen_size = old_size; CampaignWorld.presim_span_days = old_history
	Monsters.new_world_creatures = old_creatures
	return ok

func _generate_native() -> bool:
	var generation: Dictionary = Game.new_game_begin(DevTools.WORLD_SEED)
	while not Game.new_game_slice(generation, 8000):
		if not _within_budget(): return false
		await tree.process_frame
	var history: Dictionary = {}
	while CampaignWorld.presim_left(Game) > 0:
		if not _within_budget(): return false
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game); Feudal.prepare_world(Game); Dragons.init_world(Game)
	Game.new_game_finalize()
	return _within_budget()

func _recipient(seat: String) -> Dictionary:
	var office: Dictionary = Dynasty.town_office(Game, seat)
	var town: Dictionary = Game.world["towns"][seat]
	var ids: Array = Game.world["towns"].keys(); ids.sort()
	for id: String in ids:
		if id == seat or str(Game.world["towns"][id]["faction"]) != str(town["faction"]): continue
		var other: Dictionary = Dynasty.town_office(Game, id)
		var person: Dictionary = Dynasty.person(Game, str(other.get("person_uid", "")))
		if not person.is_empty() and str(person["person_uid"]) != str(office.get("person_uid", "")): return person
	return {}

func _house_ready(choice: Dictionary) -> bool:
	var seat: String = str(choice["town_id"])
	var heir: Dictionary = Dynasty.heir(Game, seat)
	var loc: Dictionary = Dynasty._person(Game, str(heir.get("person_uid", "")))
	if loc.is_empty() or int(loc["person"][6]) == 2 or _recipient(seat).is_empty(): return false
	var holdings: Array = Dragons.records(Game, str(choice["house_uid"]))
	var eggs: int = 0; var adults: int = 0
	for row: Dictionary in holdings:
		if str(row["stage"]) == "egg": eggs += 1
		else: adults += 1
	return holdings.size() == 3 and eggs == 1 and adults == 2

func _pictures(page: DragonsView, viewport: SubViewport, fit) -> void:
	var before := _snapshot()
	var gems: Array = Dragons.catalogs()["gems"]
	var morphs: Array = Dragons.catalogs()["morphs"]
	var sizes: Array = Dragons.catalogs()["sizes"]
	_assert(gems.size() >= 16 and morphs.size() >= 6 and sizes.size() >= 5, "real sixteen gems/six forms/five sizes available")
	var selector = load("res://tests/test_dragon_models.gd").new()
	morphs = selector._selected_forms(morphs)
	_assert(selector.fails == 0 and not morphs.is_empty(), "picture batch uses validated known unique form IDs")
	if morphs.is_empty(): return
	var selected_names: Array[String] = []
	for form: Dictionary in morphs: selected_names.append(String(form["id"]))
	print("Dragon UI picture forms: " + ",".join(selected_names))
	var images := {}
	for gem: Dictionary in gems:
		if not _within_budget(): return
		var record := {"stage": "egg", "gem_id": gem["id"], "appearance_seed": 15}
		var image := DragonCard.image_for(record)
		var bytes := image.get_data()
		images[bytes.hex_encode().sha256_text()] = true
		_assert(bytes == DragonCard.image_for(record).get_data(), "egg image deterministic: " + String(gem["name"]))
	_assert(images.size() == gems.size(), "every gem egg has a distinct actual palette/pattern image")
	images.clear()
	for morph: Dictionary in morphs:
		if not _within_budget(): return
		var record := {"stage": "adult", "gem_id": "emerald", "morph_id": morph["id"], "size_class": "large", "appearance_seed": 20}
		var anatomy := DragonCard.silhouette(record)
		_assert(anatomy["hind_legs"] == 2 and anatomy["wing_forelimbs"] == 2 and anatomy["front_legs"] == 0, "wyvern geometry: " + String(morph["name"]))
		var bytes := DragonCard.image_for(record).get_data()
		images[bytes.hex_encode().sha256_text()] = true
		_assert(bytes == DragonCard.image_for(record).get_data(), "adult image deterministic: " + String(morph["name"]))
	_assert(images.size() == morphs.size(), "all selected original forms have different rendered silhouettes")
	images.clear()
	var previous_bounds: float = 0.0
	for size: Dictionary in sizes:
		if not _within_budget(): return
		var model: Dictionary = DragonArt.model({"stage": "adult", "gem_id": "ruby", "morph_id": "broadmantle", "size_class": size["id"], "appearance_seed": 9}, "rest")
		var model_bounds: Rect2 = model["bounds"]
		_assert(model_bounds.size.length() > previous_bounds and float(model["rider_height"]) == 24.0, "size class enlarges the actual animal while the person stays native-sized")
		previous_bounds = model_bounds.size.length()
	_assert(_snapshot() == before, "catalog portraits consume no RNG, Units, Items, coin or population")
	page._toggle_catalog()
	await _settle()
	_fit(fit, viewport, "expanded gem/form catalog")
	var labels := _labels(page)
	for name in ["Ruby Egg", "Sapphire Egg", "Black Diamond Egg"]: _assert(name in labels, "canonical catalog egg reachable: " + name)
	for gem: Dictionary in gems: _assert(String(gem["name"]) + " Dragon" in labels and String(gem["name"]) + " Egg" in labels, "catalog exposes gem type and egg: " + String(gem["name"]))
	_assert("Body forms" in labels and "Gem types & eggs" in labels, "catalog keeps gem types separate from body forms")
	_assert(_snapshot() == before, "expanded type/form catalog remains a pure view")
	for size: Dictionary in sizes: _assert(String(size["name"]) in labels, "actual size label reachable: " + String(size["name"]))
	# The generated campaign has several realms; the old two-town fixture
	# put every estate in the selected faction.
	var selected: Dictionary = Dynasty.selected(Game)
	var towns: Dictionary = Game.world["towns"]
	var faction: String = str(towns[str(selected["town_id"])]["faction"])
	var realm: Array = []
	var foreign: int = 0
	var other_house: bool = false
	for row: Dictionary in Dragons.records(Game):
		if str(towns[str(row["estate_town_id"])]["faction"]) != faction:
			foreign += 1
			continue
		realm.append(row)
		if str(row["owner_house_uid"]) != str(selected["house_uid"]): other_house = true
	_assert(faction != "" and not realm.is_empty() and foreign > 0,
		"native realm fixture contains same-faction and foreign estates")
	_assert(other_house, "native realm fixture includes another house's actual holding")
	page._choose_holdings("realm")
	_assert(page.roster == realm, "same-faction estate filter includes exactly the actual sorted realm holdings")
	page._choose_holdings("all")
	_assert(page.roster == Dragons.records(Game), "all-holdings view preserves actual sorted records")
	page.catalog_open = false; page._choose_holdings("house")
	await _settle()

func _sprite_controls(page: DragonsView, viewport: SubViewport, fit, row: Dictionary) -> void:
	page._open_dragon(String(row["id"]))
	await _settle()
	var before: String = _snapshot()
	_assert(page.model_card != null, "actual adult has a native model preview")
	if page.model_card == null: return
	var picker: OptionButton = null
	for node: Node in page.find_children("*", "OptionButton", true, false):
		var option: OptionButton = node as OptionButton
		if option.item_count > 0 and option.get_item_text(0) == "Healthy": picker = option; break
	_assert(picker != null and picker.item_count == 6, "actual injury controls expose blood/mangle/head/chip samples")
	if picker == null: return
	var healthy_frame: Rect2 = page.model_card._bounds
	for index: int in 6:
		if not _within_budget(): return
		picker.select(index); picker.item_selected.emit(index)
		await _settle()
		var model: Dictionary = DragonArt.model(row, page.model_pose, 0, page.model_state)
		_assert(model["parts"].size() == (1 if index == 4 else 3), "only head-separated control removes source parts")
		_assert(page.model_card._bounds.is_equal_approx(healthy_frame), "injury choice preserves original body scale and framing")
		_assert(page.model_card.injury == page.model_state and page.model_card.record == row, "preview uses copied injury and actual unchanged identity")
	if page.model_play:
		var pause: Button = _button(page, "Pause")
		if pause != null: pause.pressed.emit()
	_fit(fit, viewport, "adult sprite blood and saddle controls")
	_assert(_snapshot() == before, "injury/fragment animation controls preserve campaign bodies, people, wealth, RNG and identity counters")

func _profiles(page: DragonsView, row: Dictionary) -> void:
	var before := _snapshot()
	var profile: Dictionary = Dragons.physical_profile(Game, row)
	var labels := _labels(page)
	var gem: Dictionary = DragonCard.catalog_entry("gems", String(row["gem_id"]))
	_assert(String(row["name"]) != Dragons.type_label(row) and String(row["name"]) in labels, "individual proper name stays separate from gem type")
	_assert("Type: " + String(gem["name"]) + " Dragon" in labels, "actual parent exposes canonical gem dragon type")
	_assert("Body form: " + String(DragonCard.catalog_entry("morphs", String(row["morph_id"]))["name"]) in labels, "actual parent exposes its separate body form")
	_assert(bool(profile.get("active", false)) and "Physical profile" in labels, "hatched parent has reachable active profile")
	_assert("Tooth & claw hardness: %.0f/100" % float(profile["hardness_index"]) in labels, "hardness label shows authored game rating without physical-scale claims")
	_assert("Mass: %.1f kg · Strength: %.1f · Bite force: %.0f N" % [float(profile["body_mass_kg"]), float(profile["strength"]), float(profile["bite_force_n"])] in labels, "profile displays separate actual mass, strength and bite force")
	_assert("Teeth: %.1f cm long · Tip area: %.2f cm² · Penetration: %.1f cm" % [float(profile["tooth_length_cm"]), float(profile["tooth_contact_cm2"]), float(profile["tooth_penetration_cm"])] in labels, "profile displays actual tooth geometry")
	_assert("Claws: %.1f cm long · Tip area: %.2f cm² · Penetration: %.1f cm" % [float(profile["claw_length_cm"]), float(profile["claw_contact_cm2"]), float(profile["claw_penetration_cm"])] in labels, "profile displays actual claw geometry")
	var variant: Dictionary = row.duplicate(true)
	variant["gem_id"] = "ruby" if String(row["gem_id"]) != "ruby" else "sapphire"
	var altered: Dictionary = Dragons.physical_profile(Game, variant)
	_assert(variant["name"] == row["name"] and Dragons.type_label(variant) != Dragons.type_label(row), "gem type can change without changing personal identity")
	_assert(altered["body_mass_kg"] == profile["body_mass_kg"] and altered["bite_force_n"] == profile["bite_force_n"] and altered["tooth_length_cm"] == profile["tooth_length_cm"] and altered["claw_length_cm"] == profile["claw_length_cm"], "gem hardness is separate from body force and weapon dimensions")
	variant = row.duplicate(true)
	variant["morph_id"] = "broadmantle" if String(row["morph_id"]) != "broadmantle" else "spirewing"
	_assert(Dragons.type_label(variant) == Dragons.type_label(row) and DragonsView.appearance_text(variant) != DragonsView.appearance_text(row), "body form changes independently of gem type")
	_assert(_snapshot() == before and Dragons.get_record(Game, String(row["id"])) == row, "profile and presentation reads preserve registry, RNG and population")

func _orders(page: DragonsView, viewport: SubViewport, fit, egg: Dictionary, recipient: Dictionary) -> void:
	var uid := String(egg["id"])
	var recipient_uid := String(recipient["person_uid"])
	page._open_dragon(uid)
	var review: Dictionary = Dragons.transfer_preview(Game, uid, recipient_uid)
	_assert(bool(review.get("ok", false)), "actual owner can preview another tracked person")
	var text := DragonsView.review_text("transfer", review)
	_assert(String(recipient["name"]) in text and "Custodian remains" in text and "Location remains" in text, "gift confirmation names recipient and independent custody/location")
	var before := _snapshot()
	page._request_action(uid, "transfer", recipient_uid)
	await _settle()
	_fit(fit, viewport, "actual gift confirmation")
	var cancel := _button(page.find_child("Modal", true, false), "Cancel")
	_assert(cancel != null, "gift has reachable Cancel")
	if cancel != null: cancel.pressed.emit()
	await _settle()
	_assert(_snapshot() == before, "preview/Cancel preserves registry, money, population and RNG")
	var keeper := {}
	for person: Dictionary in Dragons.people(Game):
		if bool(Dragons.set_custodian_preview(Game, uid, String(person["person_uid"])).get("ok", false)):
			keeper = person; break
	_assert(not keeper.is_empty(), "actual present tracked custodian available")
	if not keeper.is_empty():
		page._choose_person(uid, "set_custodian")
		await _settle()
		_fit(fit, viewport, "native custodian picker")
		cancel = _button(page.find_child("Modal", true, false), "Cancel")
		if cancel != null: cancel.pressed.emit()
		await _settle()
		var keeper_uid := String(keeper["person_uid"])
		Game.wait_save()
		var custody_day: float = Game.day
		var custody_before: Dictionary = Game.save_stats()
		_assert(Game.autosave_due(), "native first custody order is naturally due for an autosave")
		if fails > 0: return
		var custody: Dictionary = Dragons.set_custodian_preview(Game, uid, keeper_uid)
		var result: Dictionary = page._apply_action(uid, "set_custodian", keeper_uid, custody)
		var kept: Dictionary = Dragons.get_record(Game, uid)
		_assert(bool(result.get("ok", false)) and kept["custodian_person_uid"] == keeper_uid and kept["owner_person_uid"] == egg["owner_person_uid"] and kept["location_town_id"] == egg["location_town_id"], "custody order changes only actual keeper and history")
		_assert(page.notice == "Custodian appointed.", "native successful order is visible")
		Game.wait_save()
		var custody_after: Dictionary = Game.save_stats()
		_assert(Game.day == custody_day and int(custody_after.get("started", -1)) == int(custody_before.get("started", -1)) + 1
			and int(custody_after.get("completed", -1)) == int(custody_before.get("completed", -1)) + 1
			and int(custody_after.get("failed", -1)) == int(custody_before.get("failed", -1))
			and bool(custody_after.get("last_ok", false)), "naturally due custody order completes exactly one successful autosave")
		if fails > 0: return
		var custody_saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
		_assert(custody_saved is Dictionary, "due custody autosave contains a real serialized campaign")
		if fails > 0: return
		var saved_custody: Dictionary = custody_saved.get("world", {}).get("dragons", {}).get("records", {}).get(uid, {})
		for field: String in ["id", "owner_person_uid", "owner_house_uid", "owner_household_uid", "custodian_person_uid", "location_town_id", "estate_town_id", "rider_person_uid", "mother_uid", "father_uid", "appearance_seed"]:
			_assert(saved_custody.has(field) and saved_custody[field] == kept[field],
				"due custody autosave preserves the actual new keeper and independent " + field)
		if fails > 0: return
	# Capture the policy verdict immediately before the gift. A same-day custody
	# autosave can already own this interval; the gift must then coalesce.
	Game.wait_save()
	var gift_before: Dictionary = Game.save_stats()
	var gift_due: bool = Game.autosave_due()
	_assert(not gift_due, "native second order on the same day exercises autosave coalescing")
	_assert(gift_before.has("started") and gift_before.has("completed") and gift_before.has("failed") and gift_before.has("last_ok"),
		"gift requires native save receipt keys before the order")
	if fails > 0: return
	var state: Dictionary = Dragons.get_record(Game, uid)
	review = Dragons.transfer_preview(Game, uid, recipient_uid)
	var result: Dictionary = page._apply_action(uid, "transfer", recipient_uid, review)
	var gifted: Dictionary = Dragons.get_record(Game, uid)
	_assert(bool(result.get("ok", false)) and gifted["owner_person_uid"] == recipient_uid and gifted["owner_house_uid"] == recipient["house_uid"] and gifted["owner_household_uid"] == recipient["household_uid"], "gift updates true person, house and household owner")
	for field in ["id", "custodian_person_uid", "location_town_id", "estate_town_id", "rider_person_uid", "mother_uid", "father_uid", "appearance_seed"]:
		_assert(gifted[field] == state[field], "gift preserves independent " + field)
	await _settle()
	_fit(fit, viewport, "gifted holding readback")
	_assert(String(recipient["name"]) in _labels(page) and "Owner:" in _labels(page) and "Custodian:" in _labels(page), "readback separates actual new owner from existing keeper")
	var gift := _button(page, "Gift ownership")
	var care := _button(page, "Choose custodian")
	_assert(gift != null and gift.disabled and care != null and care.disabled, "non-owner orders are disabled after real gift")
	Game.wait_save()
	var gift_after: Dictionary = Game.save_stats()
	_assert(gift_after.has("started") and gift_after.has("completed") and gift_after.has("failed") and gift_after.has("last_ok"),
		"gift requires native save receipt keys after the order")
	if fails > 0: return
	_assert(int(gift_after.get("started", -1)) == int(gift_before.get("started", -1)) + (1 if gift_due else 0),
		"gift requests exactly one due autosave or coalesces inside the native interval")
	_assert(int(gift_after.get("completed", -1)) == int(gift_before.get("completed", -1)) + (1 if gift_due else 0)
		and int(gift_after.get("failed", -1)) == int(gift_before.get("failed", -1)),
		"gift autosave has the exact native completed/failed receipt")
	if gift_due:
		_assert(bool(gift_after.get("last_ok", false)), "due gift autosave completed successfully")
		var autosaved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
		_assert(autosaved is Dictionary and autosaved.get("world", {}).get("dragons", {}).get("records", {}).get(uid, {}).get("owner_person_uid", "") == recipient_uid,
			"an eligible gift reaches the native isolated autosave")
	# Coalescing deliberately leaves the last snapshot intact; an explicit save
	# must still persist the exact new owner, household and independent references.
	_assert(Game.save_game(), "explicit native save accepts the actual gifted holding")
	Game.wait_save()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	_assert(bool(Game.save_stats().get("last_ok", false)) and saved is Dictionary
		and saved.get("world", {}).get("dragons", {}).get("records", {}).get(uid, {}).get("owner_person_uid", "") == recipient_uid,
		"successful user command reaches native isolated save")
	if saved is Dictionary:
		var saved_dragon: Dictionary = saved.get("world", {}).get("dragons", {}).get("records", {}).get(uid, {})
		for field: String in ["id", "owner_person_uid", "owner_house_uid", "owner_household_uid", "custodian_person_uid", "location_town_id", "estate_town_id", "rider_person_uid", "mother_uid", "father_uid"]:
			_assert(saved_dragon.get(field, null) == gifted.get(field, null), "native gift save preserves exact " + field)

func _stale_ruler(page: DragonsView, viewport: SubViewport, fit, adult: Dictionary, recipient: Dictionary) -> void:
	var uid := String(adult["id"])
	var recipient_uid: String = str(recipient["person_uid"])
	page._open_dragon(uid)
	page._request_action(uid, "transfer", recipient_uid)
	await _settle()
	var review_button := _button(page.find_child("Modal", true, false), "Confirm")
	_assert(review_button != null, "living owner reviewed adult gift")
	# The heir existed before this scenario; never create/age/reparent a person.
	var owner: Dictionary = Dynasty.ruler(Game)
	var heir: Dictionary = Dynasty.selected_heir(Game)
	var loc: Dictionary = Dynasty._person(Game, str(owner.get("person_uid", "")))
	var heir_loc: Dictionary = Dynasty._person(Game, str(heir.get("person_uid", "")))
	_assert(not loc.is_empty() and not heir_loc.is_empty() and int(heir_loc["person"][6]) != 2,
		"native dragon UI succession needs the existing registered adult heir")
	if fails > 0: return
	var heir_before: Array = (heir_loc["person"] as Array).duplicate(true)
	Sickness.kill(Game, loc["town"], loc["family"], loc["person"], Game.day, "battle", "dragon UI succession scenario")
	Dynasty.succession_day(Game)
	_assert(str(Dynasty.ruler(Game).get("person_uid", "")) == str(heir["person_uid"])
		and str(heir["person_uid"]) != str(owner["person_uid"]), "actual registered heir succeeds the actual ruler")
	var heir_after: Dictionary = Dynasty._person(Game, str(heir["person_uid"]))
	_assert(not heir_after.is_empty() and float(heir_after["person"][3]) == float(heir_before[3])
		and heir_after["person"][Persons.MOTHER_UID] == heir_before[Persons.MOTHER_UID]
		and heir_after["person"][Persons.FATHER_UID] == heir_before[Persons.FATHER_UID], "succession preserves real heir birthdate and parents")
	if fails > 0: return
	var record: Dictionary = Dragons.get_record(Game, uid)
	var before := _snapshot()
	if review_button != null: review_button.pressed.emit()
	await _settle()
	_fit(fit, viewport, "changed ruler stale order")
	_assert(_snapshot() == before and Dragons.get_record(Game, uid) == record, "stale current-ruler confirmation cannot change the original asset")
	_assert(page.notice != "" and "owner" in page.notice, "stale authority rejection explains ownership")

func _snapshot() -> String:
	return JSON.stringify({"world": Game._serialize(Game.world), "gold": Game.gold, "unit_uid": Unit._next_uid, "item_uid": Item._next_uid, "rng": str(Game.rng.state)})

func _button(node: Node, text: String) -> Button:
	if node == null: return null
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _labels(node: Node) -> String:
	var text: String = node.text + "\n" if node is Label else ""
	for child in node.get_children(): text += _labels(child)
	return text

func _settle() -> void:
	for _i: int in 5:
		if not _within_budget(): return
		await tree.process_frame

func _fit(fit, viewport: SubViewport, label: String) -> void:
	if not _within_budget(): return
	fit_cases += 1
	var previous: int = int(fit.fails)
	fit._check(viewport, Vector2(DESKTOP), label)
	if int(fit.fails) > previous:
		var offenders: Array = []
		for child: Node in viewport.get_children():
			fit._walk(child, [0.0, 0.0, float(DESKTOP.x), float(DESKTOP.y)], offenders)
		failed_fits.append({"label": label, "width": DESKTOP.x, "height": DESKTOP.y,
			"failures": int(fit.fails) - previous, "offenders": offenders})

func _assert(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		failed_assertions.append(label)
		printerr("FAIL: dragon UI: ", label)

func _report_failures(fit: Variant, section: String) -> void:
	if fails == 0 and int(fit.fails) == 0: return
	var payload: Dictionary = {"section": section, "width": DESKTOP.x, "height": DESKTOP.y,
		"assertions": checks, "failures": failed_assertions.duplicate(), "fit_cases": fit_cases,
		"fit_failures": int(fit.fails), "fit_details": failed_fits.duplicate(true)}
	print("DRAGON_UI_FAILURES ", JSON.stringify(payload))
	_assert(Observations.write("dragon_ui", payload), "failed assertion and fit observations persisted")

