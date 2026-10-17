extends RefCounted
## Native tiny economies, additive portraits and real orders. Desktop only.
var tree: SceneTree
var checks := 0
var fails := 0
var fit_cases := 0
const DESKTOP := Vector2i(1280, 720)

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree
	await tree.process_frame
	var section: String = "all"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--section="): section = argument.trim_prefix("--section=")
	if not section in ["all", "pictures", "controls"]:
		push_error("Unknown dragon UI test section"); tree = null; return 1
	print("Dragon UI section: " + section)
	var fixture = load("res://tests/test_dynasty_foundation.gd").new()
	fixture.fixture(); Feudal.prepare_world(Game); Dragons.init_world(Game)
	var book: Dictionary = Game.world["dragons"].duplicate(true)
	_assert(Dynasty.select_city(Game, "city_a"), "actual registered house selected")
	_assert(Game.world["dragons"] == book, "selection does not regenerate holdings")
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var fit = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	Game.location = "city_b"
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
	_assert(Dragons.type_label(own[0]) in _labels(page), "roster names each holding's gem type and body form")
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
		var picture_result: int = fails + int(fit.fails)
		print("Dragon UI: %d assertions, %d failures; %d desktop fit cases, %d fit failures." % [checks, fails, fit_cases, int(fit.fails)])
		fit.tree = null; fit = null; fixture = null; tree = null
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
		var recipient: Dictionary = Dynasty.person(Game, String(Dynasty.town_office(Game, "city_b")["person_uid"]))
		await _orders(page, viewport, fit, egg, recipient)
	if not adult.is_empty():
		await _sprite_controls(page, viewport, fit, adult)
		await _stale_ruler(page, viewport, fit, adult)
	page._back()
	_assert(Game.location == origin and Game.world["party"]["pos"] == position, "Back does not teleport or change location")
	_assert(Game.screen_params == {"origin": "dragon_check"}, "Back restores caller parameters")
	viewport.queue_free(); page = null; viewport = null
	await _settle()
	_assert(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_baseline, "dragon controls and cancelled sheets leave no orphan nodes")
	Game.wait_save()
	var result: int = fails + int(fit.fails)
	print("Dragon UI: %d assertions, %d failures; %d desktop fit cases, %d fit failures." % [checks, fails, fit_cases, int(fit.fails)])
	fit.tree = null; fit = null; fixture = null
	book.clear(); own.clear(); egg.clear(); adult.clear()
	await _settle()
	tree = null
	return result

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
		var record := {"stage": "egg", "gem_id": gem["id"], "appearance_seed": 15}
		var image := DragonCard.image_for(record)
		var bytes := image.get_data()
		images[bytes.hex_encode().sha256_text()] = true
		_assert(bytes == DragonCard.image_for(record).get_data(), "egg image deterministic: " + String(gem["name"]))
	_assert(images.size() == gems.size(), "every gem egg has a distinct actual palette/pattern image")
	images.clear()
	for morph: Dictionary in morphs:
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
	page._choose_holdings("realm")
	_assert(page.roster.size() == Dragons.records(Game).size(), "same-faction estate filter includes actual realm holdings")
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
		var custody: Dictionary = Dragons.set_custodian_preview(Game, uid, keeper_uid)
		var result: Dictionary = page._apply_action(uid, "set_custodian", keeper_uid, custody)
		var kept: Dictionary = Dragons.get_record(Game, uid)
		_assert(bool(result.get("ok", false)) and kept["custodian_person_uid"] == keeper_uid and kept["owner_person_uid"] == egg["owner_person_uid"] and kept["location_town_id"] == egg["location_town_id"], "custody order changes only actual keeper and history")
		_assert(page.notice == "Custodian appointed.", "native successful order is visible")
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
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	_assert(saved is Dictionary and saved.get("world", {}).get("dragons", {}).get("records", {}).get(uid, {}).get("owner_person_uid", "") == recipient_uid, "successful user command reaches native isolated autosave")

func _stale_ruler(page: DragonsView, viewport: SubViewport, fit, adult: Dictionary) -> void:
	var uid := String(adult["id"])
	var recipient_uid := String(Dynasty.town_office(Game, "city_b")["person_uid"])
	page._open_dragon(uid)
	page._request_action(uid, "transfer", recipient_uid)
	await _settle()
	var review_button := _button(page.find_child("Modal", true, false), "Confirm")
	_assert(review_button != null, "living owner reviewed adult gift")
	# Native registered heir, native death and explicit succession; no mock ruler.
	var owner: Dictionary = Dynasty.ruler(Game)
	var loc: Dictionary = Dynasty._person(Game, String(owner["person_uid"]))
	var fixture = load("res://tests/test_feudal_succession.gd").new()
	var child: Array = fixture.child(loc["econ"], loc["family"], int(loc["econ"]["next_pid"]), 0, 25, loc["person"], "Registered dragon heir")
	if int(loc["person"][2]) == 1:
		child[Persons.MOTHER_UID] = loc["person"][Persons.PERSON_UID]; child[Persons.FATHER_UID] = ""
	Persons.remove(loc["family"], loc["person"], loc["econ"])
	Dynasty.succession_day(Game)
	_assert(String(Dynasty.ruler(Game)["person_uid"]) != String(owner["person_uid"]), "actual selected ruler changed through native succession")
	var record: Dictionary = Dragons.get_record(Game, uid)
	var before := _snapshot()
	if review_button != null: review_button.pressed.emit()
	await _settle()
	_fit(fit, viewport, "changed ruler stale order")
	_assert(_snapshot() == before and Dragons.get_record(Game, uid) == record, "stale current-ruler confirmation cannot change the original asset")
	_assert(page.notice != "" and "owner" in page.notice, "stale authority rejection explains ownership")
	fixture = null

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
	for _i in 5: await tree.process_frame

func _fit(fit, viewport: SubViewport, label: String) -> void:
	fit_cases += 1
	fit._check(viewport, Vector2(DESKTOP), label)

func _assert(ok: bool, label: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("dragon UI: ", label)
