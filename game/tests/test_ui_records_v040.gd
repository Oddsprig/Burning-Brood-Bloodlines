extends RefCounted
## Compact Records retain actual saved totals, complete lists and native links.
## A generated one-day capital supplies real goods, arms, people and defenders.

const SECTIONS := ["Overview", "Market", "Businesses", "Register", "Land & Homes", "Census", "Treasury", "Hardship", "Garrison", "Roads", "Sickness", "Books"]
var fails := 0
var checks := 0
var tree: SceneTree
var fit

class LinkProbe extends RefCounted:
	var units := []
	var families := []
	var preset := {}
	func open_unit(unit: Unit) -> void:
		units.append(unit)
	func open_family(town: Dictionary, fid: int) -> void:
		families.append([String(town["id"]), fid])

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func run(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	Game.new_game(40040)
	CampaignWorld.presim_step(Game, 1)
	var tid := String(Game.world["factions"]["middle_kingdom"]["capital"])
	var town: Dictionary = Game.world["towns"][tid]
	check(TownEcon.has_econ(town), "real capital has Records")
	if not TownEcon.has_econ(town):
		return fails
	Game.location = tid
	fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	for size in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		await _screen(size, town)
	_legacy_market(town)
	_issued_quality_fixture(town)
	Game.location = ""
	print("RECORDS v040 checks=", checks, " failures=", fails, " fit_failures=", fit.fails)
	return fails + int(fit.fails)

func _screen(size: Vector2i, town: Dictionary) -> void:
	Game.screen_params = {"view": "town", "id": town["id"], "tab": "Overview", "back": "town"}
	var before := Game._save_tree()
	var random_state := Game.rng.state
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var screen: Control = load("res://ui/records.tscn").instantiate()
	viewport.add_child(screen)
	await _settle()
	check(screen.TOWN_TABS == SECTIONS, "every existing town section and deep-link key remains available")
	check(Game._save_tree() == before and Game.rng.state == random_state, "initial Records view leaves serialized campaign and random stream unchanged")
	for section in SECTIONS:
		var navigation := _button(screen.tabs_box, section)
		check(navigation != null, "wrapped navigation retains its native " + section + " action")
		if navigation != null:
			navigation.pressed.emit()
		else:
			screen.show_tab(section)
		await _settle()
		check(String(screen.tab) == section, "native section action selects " + section)
		fit._check(viewport, Vector2(size), "Records " + section)
		_check_native(screen, size, section)
		check(Game._save_tree() == before and Game.rng.state == random_state, "browsing " + section + " leaves actual saved campaign unchanged")
		var disclosure_before := Game._save_tree() if section == "Overview" else {}
		await _open_disclosures(screen.list_box, viewport, size, section)
		if section == "Overview":
			var disclosure_after := Game._save_tree()
			if disclosure_after != disclosure_before:
				var changes := []
				_changed_paths(disclosure_before, disclosure_after, "save", changes)
				for change in changes:
					printerr("RECORDS READ MUTATION Overview disclosure: ", change)
		match section:
			"Overview": await _overview(screen, town, viewport, size)
			"Market": await _market(screen, town, viewport, size)
			"Garrison": await _garrison(screen, town, viewport, size)
			"Register": await _register(screen, town, viewport, size)
		check(Game._save_tree() == before and Game.rng.state == random_state, "read-only links and disclosures in " + section + " preserve saved world")
	viewport.queue_free()
	await tree.process_frame

func _register(screen: Control, town: Dictionary, viewport: SubViewport, size: Vector2i) -> void:
	var table := _table(screen.list_box)
	check(table != null, "Register retains sortable real-family table")
	if table == null:
		return
	check(table.rows.size() == RecData.fams(town["econ"]).size(), "Register retains every live household")
	var people := 0
	for row in table.rows:
		people += int(row["people"])
	check(people == Census.people(town["econ"]), "Register row people agree with the town's actual census")
	table.sort_by("purse")
	var shown := table.shown()
	for i in range(1, shown.size()):
		check(float(shown[i - 1]["purse"]) >= float(shown[i]["purse"]), "native Register numeric sorting keeps actual purse order")
	var option := RecData.state(RecData.fams(town["econ"])[0])
	table.set_filter("State", option)
	table.search = String(table.shown()[0]["name"]).substr(0, 3).to_lower()
	table.limit = 30
	table._refresh()
	var expected := table.ui_state().duplicate(true)
	var names := table.shown().map(func(row): return row["name"])
	# A read-only page exercises the real page/Back machinery without intentionally
	# marking a household named. Exact family actions are checked independently below.
	screen.page("Register definitions", func(box): RecKit.line(box, "Existing Register state"))
	await _settle()
	var back := _button(screen.page_box, "Back")
	check(back != null, "Register detail has its native Back action")
	if back != null:
		back.pressed.emit()
	await _settle()
	var restored := _table(screen.list_box)
	check(restored != null and restored.ui_state() == expected and restored.shown().map(func(row): return row["name"]) == names, "Back preserves Register sort, filter, search, page limit and matching households")
	fit._check(viewport, Vector2(size), "Records filtered Register Back")
	var probe := LinkProbe.new()
	var holder := VBoxContainer.new()
	RecTown.register(probe, town, town["econ"], holder)
	var families := _table(holder)
	if families != null and not families.rows.is_empty():
		var index: int = families.rows.find(families.shown()[0])
		(families._rows_box.get_child(0) as Button).pressed.emit()
		check(probe.families == [[String(town["id"]), int(RecData.fams(town["econ"])[index]["id"])]], "native compact Register link keeps the exact household identity")
	holder.free()

func _overview(screen: Control, town: Dictionary, viewport: SubViewport, size: Vector2i) -> void:
	var e: Dictionary = town["econ"]
	var metrics := _metadata(screen.list_box, "rec_metric")
	var people := _metric(metrics, "People")
	var food := _metric(metrics, "Food")
	var treasury := _metric(metrics, "Treasury")
	check(not people.is_empty() and _number(String(people.get("value", ""))) == float(Census.people(e)), "Overview People metric shows actual live census total")
	check(not food.is_empty() and _number(String(food.get("value", ""))) == float(int(RecData.days_food(town))), "Overview Food metric shows actual days of supply")
	check(not treasury.is_empty() and String(treasury.get("value", "")) == RecData.money(RecData.treasury(e)), "Overview Treasury metric shows actual saved coffer")
	var conditions := _cells(screen.list_box, "Condition")
	var families := 0
	var residents := 0
	for row in conditions:
		var values: Array = row.get_meta("rec_values")
		families += int(values[1])
		residents += int(values[2])
	check(conditions.size() == RecData.STATES.size() and families == RecData.fams(e).size() and residents == Census.people(e), "Overview condition table counts each real household and person exactly once")
	var granary := _metric(_metadata(screen.list_box, "rec_meter"), "Public granary")
	check(float(granary.get("value", -1)) == float(RecData.granary(e)) and float(granary.get("target", -1)) == float(RecData.granary_target(e)), "granary bar reads actual stored food and target")
	await _open_disclosures(screen.list_box, viewport, size, "Overview")
	# Both links must retain their exact list filter; counts come from the same families.
	for pair in [["Class", "poor"], ["State", RecData.state(RecData.fams(e)[0])]]:
		if String(screen.tab) != "Overview":
			screen.show_tab("Overview")
			await _settle()
			await _open_disclosures(screen.list_box, viewport, size, "Overview")
		var filter_title := String(pair[0])
		var option := String(pair[1])
		var link := _grid_link(screen.list_box, filter_title, option.capitalize())
		check(link != null, "Overview exposes a real " + filter_title + " filter link")
		if link == null:
			continue
		link.pressed.emit()
		await _settle()
		var table := _table(screen.list_box)
		check(String(screen.tab) == "Register" and table != null, "Overview classification action opens the actual Register")
		if table != null:
			check(String(table.fsel.get(filter_title, "")) == option, "Overview passes the selected " + filter_title + " preset")
			var expected := 0
			for f in RecData.fams(e):
				var actual := RecData.wealth_class(f) if filter_title == "Class" else RecData.state(f)
				if actual == option:
					expected += 1
			check(table.shown().size() == expected, "Overview filter retains exactly its actual household count")

func _market(screen: Control, town: Dictionary, viewport: SubViewport, size: Vector2i) -> void:
	var e: Dictionary = town["econ"]
	var metrics := _metadata(screen.list_box, "rec_metric")
	check(_number(String(_metric(metrics, "Equipment on sale").get("value", "-1"))) == town.get("shop", []).size(), "Market equipment count is the actual stall inventory")
	check(_number(String(_metric(metrics, "Stored reserve").get("value", "-1"))) == town.get("armory_items", []).size(), "Market reserve count is the separate physical armory")
	var kinds := _cells(screen.list_box, "Kind")
	for category in RecTown.CATS:
		var found := false
		var stock := 0
		var demand := 0.0
		for good in Goods.ids():
			if RecData.goods_cat(good) == String(category[0]):
				stock += RecData.stock(e, good)
				demand += RecData.demand(e, good)
		for row in kinds:
			var values: Array = row.get_meta("rec_values")
			if String(values[0]) == String(category[1]):
				found = true
				check(int(values[1]) == stock and String(values[2]) == (RecKit.num(stock / demand) if demand > 0.0 else "-"), "Market category uses actual goods stock and demand")
		check(found, "Market retains the existing " + String(category[1]) + " category link")
	var actual := {}
	for item in town.get("shop", []):
		var key := String(item.material).capitalize() + "|" + _quality(int(item.quality))
		var group: Array = actual.get(key, [0, 0.0])
		group[0] += 1
		group[1] += float(Market.price(town, item))
		actual[key] = group
	var total := 0
	var seen := {}
	for row in _cells(screen.list_box, "Material"):
		var values: Array = row.get_meta("rec_values")
		var key := String(values[0]) + "|" + String(values[1])
		check(not seen.has(key), "equipment grid lists each recorded material/quality once")
		seen[key] = true
		var expected: Array = actual.get(key, [0, 0.0])
		check(int(values[2]) == int(expected[0]) and int(expected[0]) > 0, "equipment grid preserves exact count for each real material and named quality")
		if int(expected[0]) > 0:
			check(float(values[3]) == float(RecKit.num(float(expected[1]) / int(expected[0]))), "equipment grid shows the real average buying price in its own column")
		total += int(values[2])
	check(total == town.get("shop", []).size() and seen.size() == actual.size(), "equipment matrix accounts for every physical item on sale")
	var material := _material_picker(screen.list_box)
	check(material != null or actual.is_empty(), "equipment grid offers its real material filter")
	if material != null and material.item_count > 1:
		material.select(1)
		material.item_selected.emit(1)
		await _settle()
		var subset := 0
		for row in _cells(screen.list_box, "Material"):
			var values: Array = row.get_meta("rec_values")
			check(String(values[0]) == material.get_item_text(1), "material filter shows only the selected recorded material")
			subset += int(values[2])
		var expected := 0
		for item in town.get("shop", []):
			if String(item.material).capitalize() == material.get_item_text(1): expected += 1
		check(subset == expected, "material filter retains every matching physical piece")
		fit._check(viewport, Vector2(size), "Records material filter")
		material.select(0)
		material.item_selected.emit(0)
		await _settle()
	_armory(screen.list_box, town)
	# Category's native action opens its actual goods; Back keeps the Market section.
	var food := _grid_link(screen.list_box, "Kind", "Food")
	check(food != null, "food category has a native detail action")
	if food != null:
		food.pressed.emit()
		await _settle()
		var table := _table(screen.page_box)
		check(screen.stack.size() == 1 and table != null, "food category opens its real sortable goods page")
		if table != null:
			check(table.rows.size() == RecTown._goods_in("food").size(), "food detail keeps every real food good")
		fit._check(viewport, Vector2(size), "Records market goods detail")
		screen.go_back()
		await _settle()
		check(screen.stack.is_empty() and String(screen.tab) == "Market", "goods Back returns to Market")

func _garrison(screen: Control, town: Dictionary, _viewport: SubViewport, _size: Vector2i) -> void:
	var units: Array = TownDefence.garrison(Game, String(town["id"]))
	check(not units.is_empty(), "generated capital supplies actual defenders")
	var metrics := _metadata(screen.list_box, "rec_metric")
	check(_number(String(_metric(metrics, "Defenders").get("value", "-1"))) == units.size(), "garrison count includes its actual militia and professional guards")
	var table := _table(screen.list_box)
	check(table != null and table.rows.size() == units.size(), "garrison retains every actual defender in its first roster table")
	if table != null:
		for i in table.rows.size():
			var row: Dictionary = table.rows[i]
			var real := Persons.roster_row(Game, units[i], "militia")
			check(String(row["name"]) == units[i].name and int(row["rk"]) == units[i].rank and float(row["pay"]) == snappedf(units[i].last_pay, 0.01), "roster keeps exact identity, rank and current paid rate")
			check(int((row["age"] as Callable).call()) == int(real["age"]) and float((row["years"] as Callable).call()) == float(real["years_served"]), "roster lazy age and service come from the actual registered defender")
			check(String((row["_d"] as Callable).call()).contains(String(real["weapon"])), "compact roster keeps full weapon detail available")
	var issued := {}
	var quality_sum := 0.0
	var equipped := 0
	for unit in units:
		var item: Variant = unit.equip.get("main_hand", unit.equip.get("ranged", null))
		if item == null:
			continue
		var key: String = _expected_weapon_name(item) + "|" + _quality(int(item.quality))
		var counts: Array = issued.get(key, [0, 0])
		counts[0] += 1
		if item.broken:
			counts[1] += 1
		issued[key] = counts
		quality_sum += float(item.quality)
		equipped += 1
	var seen := 0
	var groups := {}
	for row in _cells(screen.list_box, "Weapon"):
		var values: Array = row.get_meta("rec_values")
		var key := String(values[0]) + "|" + String(values[1])
		check(not groups.has(key), "issued equipment lists each actual weapon/quality group once")
		groups[key] = true
		var expected: Array = issued.get(key, [-1, -1])
		check(int(values[2]) == int(expected[0]) and int(values[3]) == int(expected[1]), "issued weapons keep actual quality, equipped count and broken count")
		seen += int(values[2])
	check(seen == equipped and groups.size() == issued.size(), "issued weapon counts include each equipped defender exactly once")
	if equipped > 0:
		var average_ok := false
		for text in _text(screen.list_box):
			if String(text).begins_with("Average quality"):
				var numbers := _numbers(String(text))
				average_ok = not numbers.is_empty() and numbers[0] == float("%.1f" % (quality_sum / equipped))
		check(average_ok, "issued average quality comes from actual equipped weapons")
	_armory(screen.list_box, town)
	# Verify native roster action identity without opening a family or marking it named.
	var probe := LinkProbe.new()
	var holder := VBoxContainer.new()
	RecMarket.garrison(probe, town, town["econ"], holder)
	var roster := _table(holder)
	if roster != null and not roster.rows.is_empty():
		var index: int = roster.rows.find(roster.shown()[0])
		(roster._rows_box.get_child(0) as Button).pressed.emit()
		check(probe.units == [units[index]], "native compact roster row opens its exact real Unit")
	holder.free()

func _legacy_market(town: Dictionary) -> void:
	var legacy := town.duplicate(true)
	legacy.erase("armory_items")
	var before := legacy.duplicate(true)
	var campaign := Game._save_tree()
	var holder := VBoxContainer.new()
	RecMarket.market(LinkProbe.new(), legacy, legacy["econ"], holder)
	check(legacy == before and not legacy.has("armory_items"), "legacy Market read never creates an absent physical armory container")
	check(Game._save_tree() == campaign, "legacy Market fallback leaves actual campaign save data unchanged")
	holder.free()

func _issued_quality_fixture(town: Dictionary) -> void:
	var before := Game._save_tree()
	var actual: Array = TownDefence.garrison(Game, String(town["id"]))
	var source: Unit = null
	var weapon: Item = null
	for defender: Unit in actual:
		var item: Variant = defender.equip.get("main_hand", defender.equip.get("ranged", null))
		if item is Item:
			source = defender
			weapon = item
			break
	check(source != null and weapon != null, "real defender supplies a weapon template for quality presentation")
	if source == null or weapon == null:
		return
	var units := []
	var items := []
	for quality in [0, 0, 1, DB.LEGEND]:
		# Copies retain a real registered person's identity and actual weapon template.
		var defender := Unit.from_dict(source.to_dict())
		var item := Item.new()
		item.tid = weapon.tid
		item.material = weapon.material
		item.quality = quality
		item.broken = quality == 1
		if quality == DB.LEGEND:
			item.legend = {"nm": "Recorded legend"}
		defender.equip = {"main_hand": item}
		units.append(defender)
		items.append(item)
	var holder := VBoxContainer.new()
	RecMarket._issued_weapons(units, holder)
	var rows := _cells(holder, "Weapon")
	check(rows.size() == 3, "same base weapon keeps separate ordinary, crafted and legendary quality groups")
	for row in rows:
		var values: Array = row.get_meta("rec_values")
		var quality := String(values[1])
		if quality == _quality(0):
			check(String(values[0]) == _expected_weapon_name(items[0]) and int(values[2]) == 2 and int(values[3]) == 0, "ordinary issued lane has a clean name and actual count")
		elif quality == _quality(1):
			check(String(values[0]) == _expected_weapon_name(items[2]) and int(values[2]) == 1 and int(values[3]) == 1, "crafted quality appears in its own lane, with broken count and no quality punctuation in name")
		elif quality == _quality(DB.LEGEND):
			check(String(values[0]) == items[3].display_name() and String(values[0]).contains("Recorded legend") and int(values[2]) == 1, "named legendary piece preserves its complete proper name")
		else:
			check(false, "issued quality fixture has no invented quality group")
	check(Game._save_tree() == before, "quality presentation fixtures leave the actual saved world unchanged")
	holder.free()

func _expected_weapon_name(item: Item) -> String:
	if item.is_legend():
		return item.display_name()
	var template := item.tmpl()
	var name := String(template.get("name", item.tid))
	return name if template.get("plain_name", false) else "%s %s" % [item.material, name]

func _armory(node: Node, town: Dictionary) -> void:
	var e: Dictionary = town["econ"]
	var have := ArmsTrade.class_counts(town.get("armory_items", []))
	var targets: Dictionary = e.get("arms_tgt", {})
	var stored_roles := {}
	var wanted_roles := {}
	for key in have:
		var role := ArmsTrade.cls_role(String(key))
		stored_roles[role] = int(stored_roles.get(role, 0)) + int(have[key])
	for key in targets:
		var role := ArmsTrade.cls_role(String(key))
		wanted_roles[role] = int(wanted_roles.get(role, 0)) + int(targets[key])
	var meters := _metadata(node, "rec_meter")
	var roles: Array = stored_roles.keys()
	for role in wanted_roles:
		if not roles.has(role): roles.append(role)
	for role in roles:
		var title := "Melee weapons" if role == "main_hand" else ("Bows" if role == "ranged" else String(role).replace("_", " ").capitalize())
		var meter := _metric(meters, title)
		check(float(meter.get("value", -1)) == float(stored_roles.get(role, 0)) and float(meter.get("target", -1)) == float(wanted_roles.get(role, 0)), "reserve meter counts stored pieces separately from issued kit and real target")
	for row in _cells(node, "Equipment"):
		var values: Array = row.get_meta("rec_values")
		var found := false
		for key in have.keys() + targets.keys():
			if ArmsTrade.cls_word(String(key)).capitalize() == String(values[0]):
				found = true
				check(int(values[1]) == int(have.get(key, 0)) and int(values[2]) == int(targets.get(key, 0)), "reserve disclosure keeps exact stored and target class counts")
		check(found, "reserve disclosure refers to a real recorded class")
	var history: Array = ArmsTrade.armory_log(town)
	for line in history:
		check(_text(node).has(String(line)), "armory disclosure preserves its exact historical log text")

func _quality(q: int) -> String:
	return "Ordinary" if q == 0 else (String(DB.QUALITY_NAMES[q]).capitalize() if q >= 0 and q < DB.QUALITY_NAMES.size() else "Quality %d" % q)

func _numbers(value: String) -> Array:
	var out := []
	var expression := RegEx.create_from_string("[0-9]+(?:\\.[0-9]+)?")
	for hit in expression.search_all(value):
		out.append(hit.get_string().to_float())
	return out

func _material_picker(node: Node) -> OptionButton:
	if node is OptionButton and node.item_count > 0 and node.get_item_text(0) == "All materials":
		return node
	for child in node.get_children():
		var found := _material_picker(child)
		if found != null: return found
	return null

func _cells(node: Node, heading: String) -> Array:
	var out := []
	if node is RecCells and not node.header and not node.headings.is_empty() and String(node.headings[0]) == heading:
		out.append(node)
	for child in node.get_children():
		out.append_array(_cells(child, heading))
	return out

func _open_disclosures(node: Node, viewport: SubViewport, size: Vector2i, section: String) -> void:
	var disclosures := _nodes_with_meta(node, "rec_disclosure")
	for disclosure in disclosures:
		check(disclosure.get_child_count() >= 2 and disclosure.get_child(0) is Button, "disclosure uses a real native action")
		if disclosure.get_child_count() < 2 or not disclosure.get_child(0) is Button:
			continue
		var body := disclosure.get_child(1) as Control
		if body == null:
			continue
		var button := disclosure.get_child(0) as Button
		if not body.visible:
			button.pressed.emit()
			await _settle()
		check(body.visible and body.has_meta("built"), "opening disclosure reveals its built real records: " + String(disclosure.get_meta("rec_disclosure")))
		fit._check(viewport, Vector2(size), "Records " + section + " disclosure")
		var children := body.get_children()
		button.pressed.emit()
		button.pressed.emit()
		check(body.visible and body.get_children() == children, "disclosure reopens existing records without duplicating rows")

func _metric(entries: Array, title: String) -> Dictionary:
	for entry in entries:
		if entry is Dictionary and String(entry.get("title", "")) == title:
			return entry
	return {}

func _number(value: String) -> float:
	# Values expose their displayed integer before the descriptive unit, without punctuation coupling.
	return value.replace(",", "").replace("\u2009", "").split(" ")[0].to_float()

func _grid_link(node: Node, heading: String, value: String) -> Button:
	var actual_heading := "Condition" if heading == "State" else heading
	if node is RecCells and not node.header and node.headings.has(actual_heading):
		var index: int = node.headings.find(actual_heading)
		var values: Array = node.get_meta("rec_values")
		if index < values.size() and String(values[index]).to_lower() == value.to_lower():
			return node
	if heading == "Class" and node is RecRow and String(node.get_meta("rec_row")[0]).to_lower() == value.to_lower():
		return node
	for child in node.get_children():
		var found := _grid_link(child, heading, value)
		if found != null:
			return found
	return null

func _nodes_with_meta(node: Node, key: String) -> Array:
	var out := []
	if node.has_meta(key):
		out.append(node)
	for child in node.get_children():
		out.append_array(_nodes_with_meta(child, key))
	return out

func _check_native(node: Node, size: Vector2i, section: String) -> void:
	if node is CanvasItem and not node.visible:
		return
	if node is ScrollContainer:
		check(node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "Records " + section + " requires no sideways scrolling")
	if node is Button:
		check(node.size.y >= 46.5, "Records action keeps a 48 px target")
	if node.has_meta("rec_row"):
		check(node.size.y >= 62.5, "Records detail row keeps a 64 px target")
	for child in node.get_children():
		_check_native(child, size, section)

func _table(node: Node) -> RecTable:
	if node is RecTable:
		return node
	for child in node.get_children():
		var found := _table(child)
		if found != null:
			return found
	return null

func _text(node: Node) -> Array:
	var out := []
	if node is Label or node is Button:
		out.append(String(node.text))
	if node.has_meta("rec_row"):
		out.append_array(node.get_meta("rec_row"))
	for child in node.get_children():
		out.append_array(_text(child))
	return out

func _metadata(node: Node, key: String) -> Array:
	var out := []
	if node.has_meta(key):
		out.append(node.get_meta(key))
	for child in node.get_children():
		out.append_array(_metadata(child, key))
	return out

func _button(node: Node, title: String) -> Button:
	if node is Button and node.text == title:
		return node
	for child in node.get_children():
		var found := _button(child, title)
		if found != null:
			return found
	return null

func _settle() -> void:
	for i in 3:
		await tree.process_frame

## First three changed paths locate a read mutation without dumping a generated world.
func _changed_paths(before: Variant, after: Variant, path: String, changes: Array, depth: int = 0) -> void:
	if changes.size() >= 3 or before == after:
		return
	if depth >= 32:
		changes.append(path + ": changed below diagnostic depth limit")
		return
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key in after:
			if not keys.has(key): keys.append(key)
		for key in keys:
			if changes.size() >= 3: return
			var next := path + "." + str(key)
			if not before.has(key):
				changes.append(next + ": absent -> " + _changed_value(after[key]))
			elif not after.has(key):
				changes.append(next + ": " + _changed_value(before[key]) + " -> absent")
			else:
				_changed_paths(before[key], after[key], next, changes, depth + 1)
	elif before is Array and after is Array:
		if before.size() != after.size():
			changes.append(path + ".size: %d -> %d" % [before.size(), after.size()])
		for i in mini(before.size(), after.size()):
			if changes.size() >= 3: return
			_changed_paths(before[i], after[i], path + "[%d]" % i, changes, depth + 1)
	else:
		changes.append(path + ": " + _changed_value(before) + " -> " + _changed_value(after))

func _changed_value(value: Variant) -> String:
	if value is Dictionary:
		return "Dictionary(%d keys)" % value.size()
	if value is Array:
		return "Array(%d values)" % value.size()
	return JSON.stringify(value).substr(0, 120)
