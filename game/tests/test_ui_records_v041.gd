extends RefCounted
## Independent data-contract and native integration checks for every Records view.
## Frozen handlers preserve the prior row oracle while live shared readers stay pure.
const V040 := preload("res://tests/fixtures/records_v040_world.gd")
const TOWN := ["Overview", "Market", "Businesses", "Register", "Land & Homes", "Census", "Treasury", "Hardship", "Garrison", "Roads", "Sickness", "Books"]
const WORLD := ["Towns", "Factions", "Rulers", "On the move", "Goods", "Food flows", "Fights", "Mines & land", "Merchants", "Census"]
const FACTION := ["Towns", "Army", "Factions", "Rulers", "On the move", "Goods", "Food flows", "Fights", "Mines & land", "Merchants", "Census"]
var tree: SceneTree
var checks := 0
var fails := 0
var fit
var before: Dictionary
var random_state: int
var diagnostic

class NavigationProbe extends Control:
	var events := []
	var pages := []
	var preset := {}
	func open_town(id: String) -> void: events.append(["town", id])
	func open_faction(id: String) -> void: events.append(["faction", id])
	func open_force(id: String) -> void: events.append(["force", id])
	func open_family(t: Dictionary, id: int) -> void: events.append(["family", String(t["id"]), id])
	func open_business(t: Dictionary, id: int) -> void: events.append(["business", String(t["id"]), id])
	func open_person(t: Dictionary, fid: int, pid: int) -> void: events.append(["person", String(t["id"]), fid, pid])
	func open_unit(u: Unit) -> void: events.append(["unit", u.uid])
	func goto_tab(tab: String, filters: Dictionary) -> void: events.append(["tab", tab, filters.duplicate()])
	func page(title: String, fill: Callable) -> void:
		events.append(["page", title])
		pages.append({"title": title, "fill": fill})

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func run(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	Game.new_game(40041)
	CampaignWorld.presim_step(Game, 1)
	var fid := "middle_kingdom"
	var tid := String(Game.world["factions"][fid]["capital"])
	check(TownEcon.has_econ(RecData.town(tid)), "one-day seeded world contains a real capital")
	Game.location = tid
	before = Game._save_tree()
	random_state = Game.rng.state
	fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	diagnostic = load("res://tests/test_ui_records_v040.gd").new()
	for size in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		await _all_views(size, tid, fid)
	_sparse_world(tid, fid)
	_sparse_people(tid)
	_pure("all integration checks")
	Game.location = ""
	print("RECORDS v041 checks=", checks, " failures=", fails, " fit_failures=", fit.fails)
	return fails + int(fit.fails)

## Focused entry point for the exact same sparse readers used by the full matrix.
func run_sparse(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	var previous_location := Game.location
	Game.new_game(40041)
	CampaignWorld.presim_step(Game, 1)
	var fid := "middle_kingdom"
	var tid := String(Game.world["factions"][fid]["capital"])
	check(TownEcon.has_econ(RecData.town(tid)), "one-day seeded world contains a real capital")
	Game.location = tid
	before = Game._save_tree()
	random_state = Game.rng.state
	diagnostic = load("res://tests/test_ui_records_v040.gd").new()
	_sparse_world(tid, fid)
	_sparse_people(tid)
	_pure("focused sparse reader checks")
	Game.location = previous_location
	print("RECORDS sparse v041 checks=", checks, " failures=", fails)
	return fails

func _all_views(size: Vector2i, tid: String, fid: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	# Each view uses an actual saved deep link, including its non-default tab.
	for scope in [["town", tid, "Books", TOWN], ["world", "", "Merchants", WORLD], ["faction", fid, "Army", FACTION]]:
		Game.screen_params = {"view": scope[0], "id": scope[1], "tab": scope[2], "back": "map"}
		var screen: Control = load("res://ui/records.tscn").instantiate()
		viewport.add_child(screen)
		await _settle()
		check(screen.view == scope[0] and screen.sel == scope[1] and screen.tab == scope[2], "saved deep link restores exact " + String(scope[0]) + " view/id/tab")
		check(screen.tabs() == scope[3], "every original " + String(scope[0]) + " tab key remains reachable")
		for section in scope[3]:
			var action := _button(screen.tabs_box, String(section))
			check(action != null, "native wrapped navigation exposes " + String(scope[0]) + "/" + String(section))
			if action == null: continue
			action.pressed.emit()
			await _settle()
			var context := String(scope[0]) + "/" + String(section) + " " + str(size)
			check(screen.tab == section, "native navigation selects " + context)
			check(_navigation_fits(screen), "every section action fits the wrapped strip: " + context)
			fit._check(viewport, Vector2(size), context)
			_native_targets(screen, context)
			if scope[0] != "town":
				_dashboard_facts(screen.list_box, screen.tids(), fid if scope[0] == "faction" else "", String(section))
			await _open_disclosures(screen.list_box)
			fit._check(viewport, Vector2(size), context + " details")
			_native_targets(screen, context + " details")
			# One complete save snapshot covers this tab's native dashboard,
			# summary reads and all opened disclosures before any oracle runs.
			_pure("dashboard and disclosures " + context)
			if scope[0] != "town" and size == Vector2i(1280, 720):
				_compare_section(screen.tids(), fid if scope[0] == "faction" else "", String(section))
				_pure("frozen comparison " + context)
		await _back_state(screen, viewport, size, String(scope[0]))
		if scope[0] == "world":
			await _native_deep_links(screen, viewport, size, tid, fid)
		_pure("native navigation " + String(scope[0]))
		screen.queue_free()
		await tree.process_frame
	viewport.queue_free()
	await tree.process_frame

func _compare_section(tids: Array, fid: String, section: String) -> void:
	var original_probe := NavigationProbe.new()
	var candidate_probe := NavigationProbe.new()
	var original: Control = V040.build(original_probe, tids, fid, section)
	var candidate: Control = RecWorld.build(candidate_probe, tids, fid, section)
	_open_sync(original)
	_open_sync(candidate)
	_compare_tables(original, candidate, original_probe, candidate_probe, (fid if fid != "" else "world") + "/" + section)
	# These nested goods pages are a sizeable part of the original table contract.
	if section == "Goods":
		for category in RecTown.CATS:
			for good in RecTown._goods_in(String(category[0])):
				var old_box := VBoxContainer.new()
				var new_box := VBoxContainer.new()
				V040._good_towns(original_probe, tids, String(good), old_box)
				RecFlows._good_towns(candidate_probe, tids, String(good), new_box)
				_open_sync(new_box)
				_compare_tables(old_box, new_box, original_probe, candidate_probe, "goods/" + String(good) + "/" + fid)
				old_box.free()
				new_box.free()
	original.free()
	candidate.free()
	original_probe.pages.clear()
	candidate_probe.pages.clear()
	original_probe.free()
	candidate_probe.free()

func _compare_tables(original: Node, candidate: Node, old_probe: NavigationProbe, new_probe: NavigationProbe, context: String) -> void:
	var old_tables := _tables(original)
	var new_tables := _tables(candidate)
	var used := []
	for old: RecTable in old_tables:
		var current: RecTable = null
		for i in new_tables.size():
			if not used.has(i) and _contains_keys(_keys(new_tables[i]), _keys(old)):
				current = new_tables[i]
				used.append(i)
				break
		check(current != null, "complete original sortable table retained " + context + " " + str(_keys(old)))
		if current == null: continue
		check(old.cols == current.cols.filter(func(column): return _keys(old).has(String(column["k"]))), "all original sort keys, titles and numeric semantics retained " + context)
		check(_filter_options(old) == _filter_options(current), "original filter options retained " + context)
		var old_rows := _resolved_rows(old.rows)
		var new_rows := _resolved_rows(current.rows)
		# Added factual lanes may extend a row; every original field stays exact.
		for i in mini(old_rows.size(), new_rows.size()):
			for key in new_rows[i].keys():
				if not old_rows[i].has(key): new_rows[i].erase(key)
		check(old_rows == new_rows, "every original full row and lazy saved value retained " + context)
		check(old.ui_state() == current.ui_state(), "original default sorting/filter/search/page limit retained " + context)
		check(_orders(old, old.cols) == _orders(current, old.cols), "all original sort directions, filter options, name search and page limits retain source identities " + context)
		old_probe.events.clear()
		new_probe.events.clear()
		for row in old.rows:
			var tap: Callable = row.get("_tap", Callable())
			if tap.is_valid(): tap.call()
		for row in current.rows:
			var tap: Callable = row.get("_tap", Callable())
			if tap.is_valid(): tap.call()
		check(old_probe.events == new_probe.events, "every table action retains the original target identity and source order " + context)
		# Emit a real rendered row signal, not just its stored callback.
		if not current.shown().is_empty():
			var tap: Callable = current.shown()[0].get("_tap", Callable())
			if tap.is_valid():
				new_probe.events.clear()
				tap.call()
				var expected := new_probe.events.duplicate(true)
				new_probe.events.clear()
				(current._rows_box.get_child(0) as Button).pressed.emit()
				check(new_probe.events == expected, "native compact row signal opens its own actual target " + context)

func _orders(table: RecTable, columns: Array) -> Array:
	# Operate the ordering model once per distinct contract. Native state restoration
	# is checked separately; thousands of equivalent control rebuilds add no evidence.
	var saved := table.ui_state()
	var out := []
	for column in columns:
		table.sort_k = String(column["k"])
		for ascending in [true, false]:
			table.asc = ascending
			out.append([table.sort_k, ascending, _identities(table)])
	for filter in table.filters:
		for option in filter["opts"]:
			table.fsel[String(filter["t"])] = String(option)
			out.append([filter["t"], option, _identities(table)])
		table.fsel[String(filter["t"])] = String(filter["opts"][0])
	for query in [String(table.rows[0].get("_s", table.rows[0].get("_l", ""))).substr(0, 3).to_lower() if not table.rows.is_empty() else "", "no Records match v041", ""]:
		table.search = query
		out.append(["search", query, _identities(table)])
	table.restore_ui(saved)
	out.append(["page", mini(table.limit, table.shown().size()), table.rows.size()])
	if table.shown().size() > table.limit:
		var more := _button(table._rows_box, "Show %d more" % mini(RecTable.LIMIT, table.shown().size() - table.limit))
		if more != null:
			more.pressed.emit()
			out.append(["native more", table.limit, table._count.text, _identities(table).slice(0, table.limit)])
		else:
			out.append(["missing native more"])
		table.restore_ui(saved)
	return out

func _identities(table: RecTable) -> Array:
	return table.shown().map(func(row): return table.rows.find(row))

func _resolved_rows(rows: Array) -> Array:
	var out := []
	for row in rows:
		var values := {}
		for key in row:
			if key == "_tap": continue
			var value: Variant = row[key]
			if value is Callable: value = value.call()
			if value is Color: value = value.to_html(true)
			values[key] = value
		out.append(values)
	return out

func _filter_options(table: RecTable) -> Array:
	return table.filters.map(func(filter): return [filter["t"], filter["opts"]])

func _keys(table: RecTable) -> Array:
	return table.cols.map(func(column): return String(column["k"]))

func _back_state(screen: Control, viewport: SubViewport, size: Vector2i, view: String) -> void:
	screen.show_tab("Register" if view == "town" else "On the move")
	await _settle()
	await _open_disclosures(screen.list_box)
	var tables := _tables(screen.list_box)
	check(not tables.is_empty(), "Back fixture uses the actual " + view + " list")
	if tables.is_empty(): return
	var table: RecTable = tables[0]
	if table.cols.size() > 1: table.sort_by(String(table.cols[1]["k"]))
	if not table.filters.is_empty() and table.filters[0]["opts"].size() > 1:
		table.set_filter(String(table.filters[0]["t"]), String(table.filters[0]["opts"][1]))
	if not table.shown().is_empty():
		var query := String(table.shown()[0].get("_s", table.shown()[0].get("_l", ""))).substr(0, 3).to_lower()
		if table._search_box != null:
			table._search_box.text = query
			table._search_box.text_changed.emit(query)
		else:
			table.search = query
	table.limit = 30
	table._refresh()
	screen.list_sc.scroll_vertical = 70
	await _settle()
	var state := table.ui_state().duplicate(true)
	var names := _resolved_rows(table.shown())
	var opened := _open_titles(screen.list_box)
	var scroll: int = screen.list_sc.scroll_vertical
	var real_row := _force_table(screen.list_box) if view != "town" else null
	if real_row != null and not real_row.shown().is_empty():
		(real_row._rows_box.get_child(0) as Button).pressed.emit()
	else:
		screen.page("Records definitions", func(box): RecKit.line(box, "Read-only list definitions"))
	await _settle()
	check(screen.stack.size() == 1, "native detail page opens from " + view)
	fit._check(viewport, Vector2(size), view + " detail")
	var back := _button(screen.page_box, "Back")
	check(back != null, "detail exposes native Back")
	if back != null: back.pressed.emit()
	await _settle()
	var restored := _tables(screen.list_box)
	check(screen.stack.is_empty() and not restored.is_empty(), "native Back restores " + view + " list")
	if not restored.is_empty():
		check(restored[0].ui_state() == state and _resolved_rows(restored[0].shown()) == names, "Back preserves real sorting, filters, name query, page limit and matching rows " + view)
	check(_open_titles(screen.list_box) == opened and abs(screen.list_sc.scroll_vertical - scroll) <= 1, "Back restores open disclosures and actual scroll " + view)
	fit._check(viewport, Vector2(size), view + " restored Back")
	_pure("native detail and Back " + view)

func _native_deep_links(screen: Control, viewport: SubViewport, size: Vector2i, tid: String, fid: String) -> void:
	screen.set_view("world", "", "Towns")
	await _settle()
	await _open_disclosures(screen.list_box)
	var table: RecTable = _with_key(screen.list_box, "fi")
	check(table != null, "whole-world towns preserve price and wealth sort keys")
	if table != null and not table.rows.is_empty():
		var row: Dictionary = table.shown()[0]
		var expected := ""
		for id in screen.tids():
			if RecData.tname(String(id)) == String(row["name"]): expected = String(id)
		(table._rows_box.get_child(0) as Button).pressed.emit()
		await _settle()
		check(screen.view == "town" and screen.sel == expected, "world town row opens its exact current town")
	screen.set_view("world", "", "Factions")
	await _settle()
	await _open_disclosures(screen.list_box)
	table = _with_key(screen.list_box, "bill")
	check(table != null and not table.rows.is_empty(), "faction deep-link fixture retains the real account list")
	if table != null and not table.shown().is_empty():
		var name := String(table.shown()[0]["name"])
		var target := ""
		for id in Game.world["factions"]:
			if UiWords.faction_name(String(id)) == name: target = String(id)
		(table._rows_box.get_child(0) as Button).pressed.emit()
		await _settle()
		var link := _row_title(screen.page_box, "Open the faction view")
		check(link != null, "faction detail keeps its native scoped-view deep link")
		if link != null:
			link.pressed.emit()
			await _settle()
			check(screen.view == "faction" and screen.sel == target, "faction deep link selects its actual current realm")
	screen.set_view("town", tid, "Sickness")
	await _settle()
	check(screen.view == "town" and screen.sel == tid and screen.tab == "Sickness", "town civic tab remains directly addressable")
	fit._check(viewport, Vector2(size), "native deep links")
	_pure("real town and faction deep links")

func _open_sync(node: Node) -> void:
	for depth in 8:
		var opened := false
		for section in _disclosures(node):
			var body := section.get_child(1) as Control
			if not body.visible:
				(section.get_child(0) as Button).pressed.emit()
				opened = true
		if not opened: break

func _open_disclosures(node: Node) -> void:
	_open_sync(node)
	await _settle()
	for section in _disclosures(node):
		var body := section.get_child(1) as Control
		check(body.visible and body.has_meta("built"), "native disclosure reveals its actual detailed records")
		var children := body.get_children()
		(section.get_child(0) as Button).pressed.emit()
		(section.get_child(0) as Button).pressed.emit()
		check(body.visible and body.get_children() == children, "reopening disclosure retains existing rows and links")

func _open_titles(node: Node) -> Array:
	var out := []
	for section in _disclosures(node):
		if (section.get_child(1) as Control).visible: out.append(String(section.get_meta("rec_disclosure")))
	return out

func _disclosures(node: Node) -> Array:
	var out := []
	if node.has_meta("rec_disclosure"): out.append(node)
	for child in node.get_children(): out.append_array(_disclosures(child))
	return out

func _tables(node: Node) -> Array:
	var out := []
	if node is RecTable: out.append(node)
	for child in node.get_children(): out.append_array(_tables(child))
	return out

func _with_key(node: Node, key: String) -> RecTable:
	for table: RecTable in _tables(node):
		if _keys(table).has(key): return table
	return null

func _force_table(node: Node) -> RecTable:
	return _with_key(node, "near")

func _button(node: Node, title: String) -> Button:
	if node is Button and node.text == title: return node
	for child in node.get_children():
		var found := _button(child, title)
		if found != null: return found
	return null

func _row_title(node: Node, title: String) -> Button:
	if node is Button and node.has_meta("rec_row") and String(node.get_meta("rec_row")[0]) == title: return node
	for child in node.get_children():
		var found := _row_title(child, title)
		if found != null: return found
	return null

func _navigation_fits(screen: Control) -> bool:
	var bounds: Rect2 = screen.tabs_sc.get_global_rect()
	for action: Control in screen.tabs_box.get_children():
		var rect := action.get_global_rect()
		if rect.position.x < bounds.position.x - 1 or rect.end.x > bounds.end.x + 1 or rect.position.y < bounds.position.y - 1 or rect.end.y > bounds.end.y + 1:
			return false
	return true

func _native_targets(node: Node, context: String) -> void:
	if node is CanvasItem and not node.visible: return
	if node is ScrollContainer:
		check(node.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "no sideways scrolling " + context)
	if node is Button:
		check(node.size.y >= 46.5, "native action keeps 48 px target " + context)
	for child in node.get_children(): _native_targets(child, context)

func _pure(context: String) -> void:
	var after := Game._save_tree()
	if after != before:
		var changes := []
		diagnostic._changed_paths(before, after, "save", changes)
		for change in changes: printerr("RECORDS v041 READ MUTATION ", context, ": ", change)
	check(after == before and Game.rng.state == random_state, "whole saved campaign and random stream unchanged: " + context)

func _settle() -> void:
	for i in 3: await tree.process_frame

func _contains_keys(actual: Array, expected: Array) -> bool:
	for key in expected:
		if not actual.has(key): return false
	return true

func _metrics(node: Node) -> Array:
	var out := []
	if node.has_meta("rec_metric"): out.append(node.get_meta("rec_metric"))
	for child in node.get_children(): out.append_array(_metrics(child))
	return out

func _metric(node: Node, title: String) -> Dictionary:
	for entry: Dictionary in _metrics(node):
		if String(entry.get("title", "")) == title: return entry
	return {}

func _dashboard_facts(node: Node, tids: Array, fid: String, section: String) -> void:
	var expected := {}
	match section:
		"Towns":
			var people := 0
			var days := 0.0
			for tid in tids:
				people += Census.people(RecData.econ(RecData.town(String(tid))))
				days += RecData.days_food(RecData.town(String(tid)))
			expected["Towns"] = str(tids.size())
			expected["Average food days"] = RecKit.num(days / maxf(1.0, tids.size()))
			check(String(_metric(node, "Towns").get("note", "")) == "%d people" % people, "town scope summary counts its actual current people")
		"Factions":
			expected["Factions"] = str(Game.world["factions"].size())
			var people := 0
			for town in Game.world["towns"].values():
				if TownEcon.has_econ(town): people += Census.people(town["econ"])
			expected["People in their towns"] = str(people)
		"Rulers":
			expected["Town heads"] = str(tids.size())
			var people := 0
			for tid in tids: people += Census.people(RecData.econ(RecData.town(String(tid))))
			expected["People governed"] = str(people)
		"Army":
			expected["Living field soldiers"] = str(Army.members(Game, fid).size())
			expected["Army bill / day"] = RecData.money(Army.bill(Game, fid))
			expected["War chest"] = RecData.money(float(Game.world["factions"][fid].get("treasury", 0.0)))
		"On the move":
			var caravans := 0
			var fields := 0
			for force in Game.world["warbands"].values():
				if fid != "" and String(force.get("faction", "")) != fid: continue
				if String(force.get("kind", "")) == "caravan": caravans += 1
				if Army.is_field(force): fields += 1
			expected["Caravans on the road"] = str(caravans)
			expected["Field armies"] = str(fields)
			expected["Interceptions"] = str(int(Game.world.get("war", {}).get("stats", {}).get("intercepts", 0)))
		"Goods":
			var stock := 0
			var heads := 0
			for tid in tids:
				var economy := RecData.econ(RecData.town(String(tid)))
				for category in RecTown.CATS:
					for good in RecTown._goods_in(String(category[0])): stock += RecData.stock(economy, good)
				for count in RecData.herds(economy).values(): heads += int(count)
			expected["Towns covered"] = str(tids.size())
			expected["Market stock units"] = str(stock)
			expected["Animals in town herds"] = str(heads)
	for title in expected:
		check(String(_metric(node, String(title)).get("value", "")) == String(expected[title]), "primary " + section + " summary " + String(title) + " agrees with independent saved-world totals")

func _sparse_world(tid: String, fid: String) -> void:
	var actual: Dictionary = Game.world
	var sparse := actual.duplicate(true)
	for key in ["army", "war", "research"]: sparse.erase(key)
	for town: Dictionary in sparse["towns"].values():
		if not TownEcon.has_econ(town): continue
		var economy: Dictionary = town["econ"]
		for key in ["census", "sk", "cweek"]: economy.erase(key)
	Game.world = sparse
	before = Game._save_tree()
	var probe := NavigationProbe.new()
	var all: Array = sparse["towns"].keys().filter(func(id): return TownEcon.has_econ(sparse["towns"][id]))
	var scoped: Array = all.filter(func(id): return String(sparse["towns"][id].get("faction", "")) == fid)
	# Only generated data is copied. Optional containers model an old save; no
	# simulation step is permitted to repair them before the reader is tested.
	for scope in [["town", [tid], ""], ["world", all, ""], ["faction", scoped, fid]]:
		for section in (TOWN if scope[0] == "town" else (WORLD if scope[0] == "world" else FACTION)):
			var page: Control = RecTown.build(probe, sparse["towns"][tid], String(section)) if scope[0] == "town" else RecWorld.build(probe, scope[1], String(scope[2]), String(section))
			_open_sync(page)
			for table: RecTable in _tables(page): _resolved_rows(table.rows)
			_pure("sparse old state " + String(scope[0]) + "/" + String(section))
			page.free()
	check(not sparse.has("army") and not sparse.has("war") and not sparse.has("research"), "old-save browsing never materializes optional simulation state")
	probe.pages.clear()
	probe.free()
	Game.world = actual
	before = Game._save_tree()

func _sparse_people(tid: String) -> void:
	var actual: Dictionary = Game.world
	var copy := actual.duplicate(true)
	var town: Dictionary = copy["towns"][tid]
	var families: Array = town["econ"]["fams"]
	var defender: Unit = null
	var family: Dictionary = {}
	for unit: Unit in TownDefence.garrison(Game, tid):
		if unit.home_town != tid or unit.family < 0 or unit.family >= families.size(): continue
		var candidate: Dictionary = families[unit.family]
		if candidate.get("estate", false): continue
		defender = unit
		family = candidate
		break
	check(defender != null and not family.is_empty(), "sparse people fixture belongs to a real defender of the selected town")
	if defender == null or family.is_empty(): return
	family.erase("pp")
	family.erase("kp")
	Game.world = copy
	before = Game._save_tree()
	var probe := NavigationProbe.new()
	for section in ["Overview", "Garrison"]:
		var page: Control = RecTown.build(probe, RecData.town(tid), section)
		_open_sync(page)
		for table: RecTable in _tables(page): _resolved_rows(table.rows)
		check(not family.has("pp") and not family.has("kp"), "reading " + section + " details leaves the legacy household person arrays absent")
		_pure("selected town missing pp/kp " + section)
		if section == "Overview":
			var head := RecData.head(town["econ"])
			var link := _row_title(page, "%s %s" % [String(head.get("title", "head")).capitalize(), String(head.get("name", "?"))])
			check(link != null, "legacy Overview retains its actual selected-town head household link")
			if link != null:
				probe.events.clear()
				link.pressed.emit()
				check(probe.events == [["family", tid, int(head.get("fam", 0))]], "legacy Overview native head action passes the actual selected town and household")
		else:
			var roster := _with_key(page, "renown")
			check(roster != null, "missing-person household retains the actual defender roster")
			if roster != null:
				var index := -1
				for i in roster.rows.size():
					if String(roster.rows[i]["name"]) == defender.name:
						var tap: Callable = roster.rows[i].get("_tap", Callable())
						probe.events.clear()
						if tap.is_valid(): tap.call()
						if probe.events == [["unit", defender.uid]]:
							index = i
							break
				check(index >= 0, "sparse household's real defender remains an actionable roster row")
				if index >= 0:
					roster.search = defender.name.to_lower()
					var displayed: int = roster.shown().find(roster.rows[index])
					roster.limit = maxi(roster.limit, displayed + 1)
					roster._refresh()
					check(displayed >= 0, "real defender remains visible under its actual name query")
					if displayed >= 0:
						probe.events.clear()
						(roster._rows_box.get_child(displayed) as Button).pressed.emit()
						check(probe.events == [["unit", defender.uid]], "legacy Garrison native action keeps the exact actual defender identity")
		_pure("selected-town native links missing pp/kp " + section)
		page.free()
	probe.pages.clear()
	probe.free()
	Game.world = actual
	before = Game._save_tree()
