extends RefCounted
## Focused independent v0.044 regression. Frozen delivered v0.043 supplies every
## row, lane, lazy detail and action oracle. Raw live ledgers independently check
## active mine last-wins selection, merchant sums, business staffing and cash.
## Native 16 ms tests remain unchanged; this adds correctness/fit coverage.
const BASELINE := preload("res://tests/fixtures/records_v044_baseline.gd")
const WORLD_TABS := ["Mines & land", "Census", "Merchants", "Towns", "On the move", "Food flows"]
const TOWN_TABS := ["Businesses", "Register"]
var tree: SceneTree
var checks := 0
var fails := 0
var fit
var native_probe := false

class Probe extends Control:
	var events := []
	var pages := []
	var preset := {}
	func page(title: String, fill: Callable) -> void:
		events.append(["page", title])
		pages.append(fill)
	func open_town(id: String) -> void: events.append(["town", id])
	func open_faction(id: String) -> void: events.append(["faction", id])
	func open_force(id: String) -> void: events.append(["force", id])
	func open_family(t: Dictionary, id: int) -> void: events.append(["family", String(t["id"]), id])
	func open_business(t: Dictionary, id: int) -> void: events.append(["business", String(t["id"]), id])
	func open_person(t: Dictionary, fid: int, pid: int) -> void: events.append(["person", String(t["id"]), fid, pid])
	func open_unit(unit: Unit) -> void: events.append(["unit", unit.uid])
	func show_tab(tab: String) -> void: events.append(["tab", tab])

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func run(st: SceneTree) -> int:
	tree = st
	native_probe = OS.get_cmdline_user_args().has("--records-v044-native-probe")
	check(FileAccess.get_file_as_string("res://ui/rec_pages.gd").replace("\r\n", "\n").sha256_text() == BASELINE.LIVE_PAGES_SHA256, "live RecPages source exactly matches frozen delivered v043 dependency")
	await tree.process_frame
	Game.new_game(11)
	CampaignWorld.presim_step(Game, 40)
	var tid := ""
	for key in Game.world["towns"]:
		if not (Game.world["towns"][key].get("recruits", []) as Array).is_empty() and Militia.units_of(Game, key).size() > 0:
			tid = String(key)
			break
	check(tid != "", "exact original seed11+40days world has a recruited/militia town")
	if tid == "": return fails
	Game.location = tid
	var all: Array = Game.world["towns"].keys().filter(func(id): return TownEcon.has_econ(Game.world["towns"][id]))
	all.sort_custom(func(a, b): return RecData.tname(a) < RecData.tname(b))
	var fid := String(Game.world["towns"][tid]["faction"])
	var scoped: Array = all.filter(func(id): return String(Game.world["towns"][id].get("faction", "")) == fid)
	if not native_probe:
		for tab in WORLD_TABS:
			_contract(all, "", tab, "original evolved whole world")
			_contract(scoped, fid, tab, "original evolved faction")
		for tab in TOWN_TABS: _town_contract(tid, tab, "original evolved town")
	fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	for size in [Vector2i(1280, 720), Vector2i(720, 1280)]: await _native(size, tid, fid)
	if not native_probe: _same_frame(tid, fid)
	Game.location = ""
	if native_probe:
		print("RECORDS V044 native_probe checks=", checks, " failures=", fails, " fit_failures=", fit.fails)
	else:
		print("RECORDS V044 correctness checks=", checks, " failures=", fails, " fit_failures=", fit.fails)
	return fails + int(fit.fails)

func _pure(before: Dictionary, state: int, context: String) -> void:
	var after := Game._save_tree()
	var saved_data_equal := before == after
	var rng_equal := state == Game.rng.state
	if not saved_data_equal or not rng_equal:
		print("RECORDS V044 PURITY DIFFERENCE context=", context, " saved_data_equal=", saved_data_equal, " rng_equal=", rng_equal, " rng_before=", state, " rng_after=", Game.rng.state, " first_saved_difference=", _first_saved_difference(before, after, "$"))
	check(saved_data_equal and rng_equal, "campaign save + RNG purity: " + context)

func _first_saved_difference(before: Variant, after: Variant, path: String) -> String:
	if typeof(before) != typeof(after): return "%s type %d -> %d; %s -> %s" % [path, typeof(before), typeof(after), str(before).left(220), str(after).left(220)]
	if before is Dictionary:
		for key in before:
			if not after.has(key): return "%s[%s] removed; before=%s" % [path, str(key), str(before[key]).left(220)]
			var difference := _first_saved_difference(before[key], after[key], "%s[%s]" % [path, str(key)])
			if difference != "": return difference
		for key in after:
			if not before.has(key): return "%s[%s] added; after=%s" % [path, str(key), str(after[key]).left(220)]
	elif before is Array:
		if before.size() != after.size(): return "%s length %d -> %d" % [path, before.size(), after.size()]
		for i in before.size():
			var difference := _first_saved_difference(before[i], after[i], "%s[%d]" % [path, i])
			if difference != "": return difference
	elif before != after: return "%s: %s -> %s" % [path, str(before).left(220), str(after).left(220)]
	return ""

func _contract(tids: Array, fid: String, tab: String, context: String) -> void:
	var before := Game._save_tree()
	var state: int = Game.rng.state
	var old_probe := Probe.new()
	var new_probe := Probe.new()
	var old: Control = BASELINE.build(old_probe, tids, fid, tab)
	var current: Control = RecWorld.build(new_probe, tids, fid, tab)
	_compare(old, current, old_probe, new_probe, context + "/" + tab)
	_world_facts(current, tids, tab, context)
	_pure(before, state, context + "/" + tab)
	old.free()
	current.free()
	old_probe.free()
	new_probe.free()

func _town_contract(tid: String, tab: String, context: String) -> void:
	var before := Game._save_tree()
	var state: int = Game.rng.state
	var old_probe := Probe.new()
	var new_probe := Probe.new()
	var town := RecData.town(tid)
	var old: Control = BASELINE.town_build(old_probe, town, tab)
	var current: Control = RecTown.build(new_probe, town, tab)
	_compare(old, current, old_probe, new_probe, context + "/" + tab)
	if tab == "Businesses": _business_facts(current, town, context)
	_pure(before, state, context + "/" + tab)
	old.free()
	current.free()
	old_probe.free()
	new_probe.free()

func _compare(old: Node, current: Node, a: Probe, b: Probe, context: String) -> void:
	check(_digest(old) == _digest(current), "all closed rows, resolved lazy values, visible cells, tooltips and accessibility match delivered v043: " + context)
	_actions(old, current, a, b, context)
	_open_sync(old)
	_open_sync(current)
	check(_digest(old) == _digest(current), "all expanded disclosures retain original full content: " + context)
	_actions(old, current, a, b, context + " expanded")

func _actions(old: Node, current: Node, a: Probe, b: Probe, context: String) -> void:
	var old_tables := _tables(old)
	var tables := _tables(current)
	check(old_tables.size() == tables.size(), "full original table count: " + context)
	for i in mini(old_tables.size(), tables.size()):
		var original = old_tables[i]
		var actual = tables[i]
		a.events.clear(); b.events.clear(); a.pages.clear(); b.pages.clear()
		for row: Dictionary in original.rows:
			var tap: Callable = row.get("_tap", Callable())
			if tap.is_valid(): tap.call()
		for row: Dictionary in actual.rows:
			var tap: Callable = row.get("_tap", Callable())
			if tap.is_valid(): tap.call()
		check(a.events == b.events, "every row retains original native identity/action: " + context)
		check(a.pages.size() == b.pages.size(), "same lazy detail page count: " + context)
		for j in mini(a.pages.size(), b.pages.size()):
			var old_box := VBoxContainer.new()
			var current_box := VBoxContainer.new()
			(a.pages[j] as Callable).call(old_box)
			(b.pages[j] as Callable).call(current_box)
			check(_digest(old_box) == _digest(current_box), "actual row callback builds original complete detail page: " + context + "/" + str(j))
			old_box.free(); current_box.free()
		if not actual.shown().is_empty():
			var tap: Callable = actual.shown()[0].get("_tap", Callable())
			if tap.is_valid():
				b.events.clear(); tap.call()
				var expected := b.events.duplicate(true)
				b.events.clear()
				(actual._rows_box.get_child(0) as Button).pressed.emit()
				check(b.events == expected, "displayed native row signal keeps current target: " + context)
		a.pages.clear(); b.pages.clear()

func _world_facts(page: Node, tids: Array, tab: String, context: String) -> void:
	if tab == "Census": _census_facts(page, tids, context)
	if tab == "Mines & land":
		_land_facts(page, tids, context)
		var table = _with_key(page, "rich")
		check(table != null, "ore table present: " + context)
		if table == null: return
		var expected := []
		for tid in tids:
			var town: Dictionary = Game.world["towns"][tid]
			var e: Dictionary = town["econ"]
			for ore in e.get("deposits", {}):
				var last := {}
				for biz: Dictionary in e.get("biz", []):
					if String(biz["type"]) == "mine" and String(biz.get("ore", "copper_ore")) == String(ore) and not biz.get("closed", false): last = biz
				expected.append([String(town["name"]), Goods.good_name(String(ore)), float(e["deposits"][ore]), int(last.get("workers", 0)), not last.is_empty()])
		check(expected.size() == table.rows.size(), "one row for every actual deposit: " + context)
		for i in mini(expected.size(), table.rows.size()):
			var row: Dictionary = table.rows[i]
			check([row["town"], row["ore"], row["rich"], row["workers"], (row["_tap"] as Callable).is_valid()] == expected[i], "raw deposited ore + last open matching mine staffing/action oracle: " + context)
	elif tab == "Merchants":
		var table = _with_key(page, "gold")
		if table == null:
			check(false, "merchant table present: " + context)
			return
		for i in tids.size():
			var count := 0; var coins := 0.0
			for force: Dictionary in Game.world.get("warbands", {}).values():
				if String(force.get("kind", "")) == "caravan" and String(force.get("origin", force.get("home", ""))) == String(tids[i]):
					count += 1; coins += float(force.get("gold", 0.0))
			var row: Dictionary = table.rows[i]
			check(row["cars"] == count and row["gold"] == coins and row["out"] == float(Game.world["towns"][tids[i]]["econ"].get("stats", {}).get("trade_out", 0.0)), "merchant values equal independent origin/purse/trade ledgers: " + context)

func _metric_entry(node: Node, title: String) -> Dictionary:
	if node.has_meta("rec_metric") and String(node.get_meta("rec_metric").get("title", "")) == title: return node.get_meta("rec_metric")
	for child in node.get_children():
		var found := _metric_entry(child, title)
		if not found.is_empty(): return found
	return {}

func _land_facts(page: Node, tids: Array, context: String) -> void:
	# Read each saved crop value directly. Skip the presence of estate (even
	# false), count fams[0] independently, and clamp common per town before sum.
	var family_total := 0; var estate_total := 0; var common_total := 0
	for tid in tids:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		var families := 0; var estate := 0
		for family: Dictionary in e["fams"]:
			if family.get("gone", false) or family.has("estate"): continue
			for value in family["land"].values(): families += int(value)
		for value in e["fams"][0]["land"].values(): estate += int(value)
		var territory := int(e.get("territory", families + estate))
		family_total += families; estate_total += estate
		common_total += maxi(0, territory - families - estate)
	check(_metric(page, "Family land") == "%d acres" % family_total, "primary family acres equal per-crop integer sums for real residents without estate key: " + context)
	var town_metric := _metric_entry(page, "Town land")
	check(town_metric.get("value", "") == "%d acres" % estate_total and town_metric.get("note", "") == "%d acres common or unclaimed" % common_total, "primary estate/common acres equal fams[0], missing territory fallback and per-town zero clamp: " + context)

func _same_frame_land(tid: String, fid: String) -> void:
	var e: Dictionary = Game.world["towns"][tid]["econ"]
	var residents: Array = e["fams"].filter(func(f): return not f.get("gone", false) and not f.has("estate"))
	check(not residents.is_empty(), "real isolated town has a resident for land edits")
	if residents.is_empty(): return
	var family: Dictionary = residents[0]
	var estate: Dictionary = e["fams"][0]
	var crop: String = String(estate["land"].keys()[0]) if not (estate["land"] as Dictionary).is_empty() else "grain"
	family["land"][crop] = float(family["land"].get(crop, 0.0)) + 7.875
	estate["land"][crop] = float(estate["land"].get(crop, 0.0)) + 11.625
	e["territory"] = int(e.get("territory", 0)) + 41
	_contract([tid], fid, "Mines & land", "same-frame resident/estate fractional crops and territory edit")
	e.erase("territory")
	_contract([tid], fid, "Mines & land", "same-frame absent territory falls back to family plus estate")
	e["territory"] = 0
	_contract([tid], fid, "Mines & land", "same-frame territory below owned land clamps common to zero")
	family["gone"] = true
	_contract([tid], fid, "Mines & land", "same-frame departed household excludes all its acres")
	family["gone"] = false
	family["estate"] = false
	_contract([tid], fid, "Mines & land", "same-frame estate key presence excludes family acres even when false")
	family.erase("estate")
	family["land"] = {}; estate["land"] = {}
	_contract([tid], fid, "Mines & land", "same-frame empty resident and estate crop dictionaries")
	# fams[0] remains the estate even when its household is marked gone.
	estate["gone"] = true
	estate["land"][crop] = 9.875
	_contract([tid], fid, "Mines & land", "same-frame fams[0] estate acres remain counted when gone")

func _census_facts(page: Node, tids: Array, context: String) -> void:
	var people := 0; var last := 0; var births := 0; var deaths := 0; var arrived := 0; var left := 0
	for id in tids:
		var e: Dictionary = Game.world["towns"][id]["econ"]
		for family: Dictionary in e.get("fams", []):
			if not family.get("gone", false) and not family.get("estate", false): people += int(family["m"]) + int(family["f"]) + int(family["kids"]) + int(family["old"])
		var book: Dictionary = e.get("census", {})
		var rows: Array = book.get("rows", [])
		if not rows.is_empty(): last += int(rows[-1]["people"])
		var cur: Dictionary = book.get("cur", {})
		births += int(cur.get("births", 0))
		for n in cur.get("deaths", {}).values(): deaths += int(n)
		for n in cur.get("arrived", {}).values(): arrived += int(n)
		for n in cur.get("left", {}).values(): left += int(n)
	check(_metric(page, "People now") == str(people) and _metric(page, "Population change") == "%+d" % (people - last), "Census current population/header change equals raw live counters and saved last census: " + context)
	var rows := _cells(page, ["Since last census", "People"])
	check(rows.map(func(row): return row.get_meta("rec_values")) == [["Born", str(births)], ["Died", str(deaths)], ["Arrived", str(arrived)], ["Left", str(left)]], "Census birth/death/move lanes equal raw current ledgers: " + context)

func _business_facts(page: Node, town: Dictionary, context: String) -> void:
	var table = _with_key(page, "cash")
	check(table != null, "business table present: " + context)
	if table == null: return
	var raw: Array = town["econ"].get("biz", []).filter(func(b): return not b.get("closed", false) and (int(b.get("cap", 0)) > 0 or int(b.get("workers", 0)) > 0 or int(b.get("kw", 0)) > 0))
	check(table.rows.size() == raw.size(), "exact listed open/keeper-only business count: " + context)
	for i in mini(raw.size(), table.rows.size()):
		check(table.rows[i]["staff"] == int(raw[i].get("workers", 0)) + int(raw[i].get("kw", 0)) and table.rows[i]["cash"] == float(raw[i].get("till", 0.0)) and table.rows[i]["wage"] == float(raw[i].get("wage", 0.0)), "native lanes preserve raw workers+keeper/till/wage: " + context)

func _expect_visited_family(expected_save: Dictionary, town_id: String, table: RecTable, row: Dictionary, context: String) -> String:
	var state: int = Game.rng.state
	# The frozen Register row's native callback supplies the exact observed
	# identity independently of displayed names, which need not be unique.
	var probe := Probe.new()
	var reference: Control = BASELINE.town_build(probe, RecData.town(town_id), "Register")
	var original = _with_key(reference, "purse")
	var index: int = table.rows.find(row)
	check(original != null and index >= 0 and index < original.rows.size(), "visited family has an exact frozen native row: " + context)
	var expected_title := ""
	if original != null and index >= 0 and index < original.rows.size():
		var frozen_row: Dictionary = original.rows[index]
		check(_resolved([frozen_row]) == _resolved([row]), "visited family row retains original resolved identity/content: " + context)
		(frozen_row["_tap"] as Callable).call()
		check(probe.events.size() == 1 and probe.events[0][0] == "family" and probe.events[0][1] == town_id, "frozen native action identifies the exact visited town/family: " + context)
		if probe.events.size() == 1 and probe.events[0][0] == "family":
			var family_id := int(probe.events[0][2])
			var found := false
			for family: Dictionary in expected_save["world"]["towns"][town_id]["econ"]["fams"]:
				if int(family["id"]) != family_id: continue
				expected_title = "Town land" if family.get("estate", false) else "The %s family" % String(family["name"])
				found = true
				break
			check(found, "exact visited family exists in independent expected save: " + context)
			if found:
				_pure(expected_save, state, "frozen native identity callback leaves live save and RNG unchanged " + context)
				var observed := _frozen_family_save(town_id, family_id, context)
				expected_save.clear()
				expected_save.merge(observed, true)
				print("RECORDS V044 EXPECTED FAMILY DETAIL context=", context, " town=", town_id, " family_id=", family_id, " oracle=frozen_v043_pages effect_contract=exact_saved_state")
	reference.free()
	probe.free()
	return expected_title

func _frozen_family_save(town_id: String, family_id: int, context: String) -> Dictionary:
	# Run the exact delivered page against isolated dictionaries. This predicts
	# named, person reconciliation, town-wide remembered defaults and ledgers
	# exactly; no keys or values are exempted from the subsequent full-save check.
	var live_world: Dictionary = Game.world
	var live_save := Game._save_tree()
	var state: int = Game.rng.state
	var story_e: Dictionary = Backstory._k_e
	var story_me: Array = Backstory._k_me
	var probe := Probe.new()
	var detail := VBoxContainer.new()
	Game.world = live_world.duplicate(true)
	BASELINE.FrozenPages.family(probe, Game.world["towns"][town_id], family_id, detail)
	var observed := Game._save_tree()
	Game.world = live_world
	Backstory._k_e = story_e
	Backstory._k_me = story_me
	detail.free()
	probe.free()
	_pure(live_save, state, "frozen full detail oracle leaves live campaign and RNG unchanged " + context)
	return observed

func _native(size: Vector2i, tid: String, fid: String) -> void:
	Game.screen_params = {"view": "town", "id": tid, "tab": "Register", "back": "town"} if native_probe else {"view": "world", "tab": "Mines & land", "back": "town"}
	var before := Game._save_tree()
	var expected_save := before.duplicate(true)
	var state: int = Game.rng.state
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var screen: Control = load("res://ui/records.tscn").instantiate()
	viewport.add_child(screen)
	await _settle()
	var tabs: Array = ["Register"] if native_probe else WORLD_TABS + TOWN_TABS
	for tab in tabs:
		var town_view: bool = tab in TOWN_TABS
		screen.set_view("town" if town_view else "world", tid if town_view else "", tab)
		await _settle()
		var context: String = str(size) + "/" + String(tab)
		fit._check(viewport, Vector2(size), "v044 " + context)
		var tables := _tables(screen.list_box)
		for table: RecTable in tables:
			for column: Dictionary in table.cols:
				var picker := _option(table, String(column["t"]))
				check(picker != null, "native sort picker for every final column: " + context)
				if picker == null: continue
				var index := _option_index(picker, String(column["t"]))
				picker.select(index); picker.item_selected.emit(index)
				check(table.sort_k == String(column["k"]), "sort signal selects exact final column: " + context)
				var old_asc: bool = table.asc
				var direction := _button(table, "Ascending" if old_asc else "Descending")
				if direction != null: direction.pressed.emit()
				check(table.asc != old_asc, "native direction reverses current column: " + context)
			for filter: Dictionary in table.filters:
				for option in filter["opts"]:
					# Class/State/Only each contain All, and State/Only may both
					# contain Hungry. Identify the picker by its native label.
					var picker := _filter_option(table, String(filter["t"]))
					check(picker != null, "exact native filter picker retained: " + context + "/" + String(filter["t"]))
					if picker == null: continue
					var index := _option_index(picker, String(option).capitalize())
					picker.select(index); picker.item_selected.emit(index)
					check(String(table.fsel.get(String(filter["t"]), "")) == String(option) and _same_members(table.shown(), _matching_rows(table, table.search)), "actual named filter signal keeps every independently eligible row: " + context)
				table.set_filter(String(filter["t"]), String(filter["opts"][0]))
			if table._search_box != null and not table.rows.is_empty():
				var eligible := _matching_rows(table, "")
				check(_same_members(table.shown(), eligible), "pre-search rows equal independent active-filter oracle: " + context)
				if not table.shown().is_empty():
					var visible: Dictionary = table.shown()[0]
					var query := String(visible.get("_s", visible.get("_l", ""))).substr(0, 3).to_lower()
					var expected := _matching_rows(table, query)
					table._search_box.text = query; table._search_box.text_changed.emit(query)
					check(not expected.is_empty() and table.search == query and _same_members(table.shown(), expected), "native name search retains all exact matches under active filters: " + context)
					table._search_box.text = ""; table._search_box.text_changed.emit("")
					check(_same_members(table.shown(), eligible), "native clear search restores every eligible row: " + context)
			if table.shown().size() > table.limit:
				var prior_limit: int = table.limit
				var first := table._rows_box.get_child(0)
				var more := _button(table, "Show %d more" % mini(RecTable.LIMIT, table.shown().size() - table.limit))
				check(more != null, "native original page increment retained: " + context)
				if more != null: more.pressed.emit()
				check(table.limit == prior_limit + RecTable.LIMIT and table._rows_box.get_child(0) == first, "Show more preserves prior cells and adds fifteen: " + context)
		_open_sync(screen.list_box)
		await _settle()
		fit._check(viewport, Vector2(size), "v044 expanded " + context)
		var saved_states := _tables(screen.list_box).map(func(table): return table.ui_state().duplicate(true))
		var rows := _tables(screen.list_box).map(func(table): return _resolved(table.shown()))
		var opened := _open_titles(screen.list_box)
		screen.list_sc.scroll_vertical = 70
		await _settle()
		var scroll: int = screen.list_sc.scroll_vertical
		# Actual native actionable cell, including mines, business/family detail,
		# force/season records and world town targets; Back uses its real button.
		_pure(expected_save, state, "strict native list/build/sort/filter/search/page/disclosure purity before detail " + context)
		var expected_family_title := ""
		var acted := false
		for table: RecTable in _tables(screen.list_box):
			for index in mini(table.shown().size(), table.limit):
				if not (table.shown()[index].get("_tap", Callable()) as Callable).is_valid(): continue
				if tab == "Register" and table.cols.any(func(column): return String(column["k"]) == "purse"):
					expected_family_title = _expect_visited_family(expected_save, tid, table, table.shown()[index], context)
				(table._rows_box.get_child(index) as Button).pressed.emit()
				acted = true
				break
			if acted: break
		if acted:
			await _settle()
			if expected_family_title != "":
				check(not screen.stack.is_empty() and String(screen.stack[-1]["title"]) == expected_family_title, "native family signal opens the exact observed family/estate title: " + context)
			_pure(expected_save, state, "native detail save equals exact frozen v043 family observation; RNG unchanged " + context)
			if not screen.stack.is_empty():
				check(not screen.page_box.get_children().is_empty(), "real row opens complete native detail: " + context)
				fit._check(viewport, Vector2(size), "v044 detail " + context)
				var back := _button(screen.page_box, "Back")
				check(back != null, "native details expose Back: " + context)
				if back != null: back.pressed.emit()
				await _settle()
			else:
				check(screen.view == "town" and screen.sel != "", "real world town row opens its town identity: " + context)
				screen.set_view("town" if town_view else "world", tid if town_view else "", tab)
				await _settle()
			check(screen.stack.is_empty() and screen.tab == tab, "Back/return restores original list: " + context)
			check(_tables(screen.list_box).map(func(table): return table.ui_state()) == saved_states and _tables(screen.list_box).map(func(table): return _resolved(table.shown())) == rows, "Back/return restores sort/filter/search/page and full row data: " + context)
			check(_open_titles(screen.list_box) == opened and abs(screen.list_sc.scroll_vertical - scroll) <= 1, "Back/return restores disclosures and vertical scroll: " + context)
		screen.set_view("faction", fid, tab if not town_view else "Towns")
		await _settle()
		check(screen.tids().all(func(id): return String(Game.world["towns"][id]["faction"]) == fid), "actual faction navigation scopes every town: " + context)
	_pure(expected_save, state, "all native list/Back state and details equal exact frozen v043 family observations; RNG unchanged " + str(size))
	viewport.queue_free()
	await tree.process_frame

func _filter_option(table: RecTable, title: String) -> OptionButton:
	for flow: Node in table._ctl.get_children():
		var children := flow.get_children()
		for i in range(children.size() - 1):
			if children[i] is Label and children[i].text == title and children[i + 1] is OptionButton: return children[i + 1]
	return null

func _matching_rows(table: RecTable, query: String) -> Array:
	var out := []
	for row: Dictionary in table.rows:
		var eligible := true
		for filter: Dictionary in table.filters:
			var option := String(table.fsel.get(String(filter["t"]), filter["opts"][0]))
			if option != String(filter["opts"][0]) and not (filter["fn"] as Callable).call(row, option):
				eligible = false
				break
		if eligible and (query == "" or String(row.get("_s", row.get("_l", ""))).to_lower().contains(query)): out.append(row)
	return out

func _same_members(actual: Array, expected: Array) -> bool:
	return actual.size() == expected.size() and actual.all(func(row): return expected.has(row)) and expected.all(func(row): return actual.has(row))

func _same_frame(tid: String, fid: String) -> void:
	var original: Dictionary = Game.world
	Game.world = original.duplicate(true)
	var town: Dictionary = Game.world["towns"][tid]
	var e: Dictionary = town["econ"]
	# No awaits: prewarm then mutate exact existing ledgers and rebuild immediately.
	for tab in WORLD_TABS: _contract([tid], fid, tab, "same-frame before edit")
	_town_contract(tid, "Businesses", "same-frame before edit")
	e["treasury"] = float(e.get("treasury", 0.0)) + 12.375
	var stats: Dictionary = e.get("stats", {})
	e["stats"] = stats
	stats["trade_out"] = 23.625; stats["military_supply_in"] = 31
	for ore in e.get("deposits", {}): e["deposits"][ore] = float(e["deposits"][ore]) + 0.1375
	for biz: Dictionary in e.get("biz", []):
		biz["till"] = float(biz.get("till", 0.0)) + 4.125
		biz["wage"] = float(biz.get("wage", 0.0)) + 0.125
		if String(biz["type"]) == "mine": biz["workers"] = int(biz.get("workers", 0)) + 1
	for force: Dictionary in Game.world.get("warbands", {}).values():
		if String(force.get("kind", "")) == "caravan": force["gold"] = float(force.get("gold", 0.0)) + 2.75
	var census: Dictionary = e.get("census", {})
	if census.has("cur"):
		census["cur"]["births"] = int(census["cur"].get("births", 0)) + 3
		census["cur"]["deaths"]["accident"] = int(census["cur"]["deaths"].get("accident", 0)) + 2
	if not (census.get("rows", []) as Array).is_empty(): census["rows"][-1]["people"] = int(census["rows"][-1]["people"]) + 7
	for family: Dictionary in e.get("fams", []):
		if not family.get("gone", false) and not family.get("estate", false):
			family["gone"] = true
			break
	for tab in WORLD_TABS: _contract([tid], fid, tab, "same-frame fractional ledger edit")
	_town_contract(tid, "Businesses", "same-frame fractional till/wage edit")
	# The duplicate's actual existing mine array supplies duplicate ore/default
	# keys and closed/open transitions without synthetic towns or altered IDs.
	var mines: Array = e.get("biz", []).filter(func(b): return String(b["type"]) == "mine")
	if not mines.is_empty():
		var last: Dictionary = mines[-1]
		if mines.size() > 1:
			last["ore"] = mines[0].get("ore", "copper_ore")
			_contract([tid], fid, "Mines & land", "same-frame two real open mines target one ore; last wins")
		last["closed"] = true
		_contract([tid], fid, "Mines & land", "same-frame last matching mine closes")
		last["closed"] = false
		last.erase("ore")
		_contract([tid], fid, "Mines & land", "same-frame legacy default copper ore")
		_town_contract(tid, "Businesses", "same-frame business reopens")
	_same_frame_land(tid, fid)
	for tab in WORLD_TABS: _contract([], "", tab, "empty scope")
	Game.world = original

func _digest(node: Node) -> String:
	var content := []
	_walk(node, content)
	return JSON.stringify(content).sha256_text()

func _walk(node: Node, content: Array) -> void:
	if node is Label: content.append(["label", node.text])
	if node is Button:
		content.append(["button", node.text, node.get_meta("rec_values", []), node.get_meta("rec_row", []), node.tooltip_text, node.accessibility_name, node.accessibility_description])
	if node is RecCells: content.append(["cell", node.headings, node.weights, node.colors.map(func(color): return color.to_html(true))])
	if node is RecTable or node is BASELINE.FrozenTable: content.append(["table", node.cols, _resolved(node.rows), node.ui_state()])
	for child in node.get_children(): _walk(child, content)

func _resolved(rows: Array) -> Array:
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

func _tables(node: Node) -> Array:
	var out := []
	if node is RecTable or node is BASELINE.FrozenTable: out.append(node)
	for child in node.get_children(): out.append_array(_tables(child))
	return out

func _with_key(node: Node, key: String):
	for table in _tables(node):
		if table.cols.any(func(column): return String(column["k"]) == key): return table
	return null

func _cells(node: Node, headings: Array) -> Array:
	var out := []
	if node is RecCells and not node.header and node.headings == headings: out.append(node)
	for child in node.get_children(): out.append_array(_cells(child, headings))
	return out

func _metric(node: Node, title: String) -> String:
	if node.has_meta("rec_metric") and String(node.get_meta("rec_metric").get("title", "")) == title: return String(node.get_meta("rec_metric").get("value", ""))
	for child in node.get_children():
		var found := _metric(child, title)
		if found != "": return found
	return ""

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _option_index(option: OptionButton, text: String) -> int:
	for i in option.item_count:
		if option.get_item_text(i) == text: return i
	return -1

func _option(node: Node, text: String) -> OptionButton:
	if node is OptionButton and _option_index(node, text) >= 0: return node
	for child in node.get_children():
		var found := _option(child, text)
		if found != null: return found
	return null

func _disclosures(node: Node) -> Array:
	var out := []
	if node.has_meta("rec_disclosure"): out.append(node)
	for child in node.get_children(): out.append_array(_disclosures(child))
	return out

func _open_sync(node: Node) -> void:
	for depth in 8:
		var opened := false
		for section in _disclosures(node):
			if not (section.get_child(1) as Control).visible:
				(section.get_child(0) as Button).pressed.emit()
				opened = true
		if not opened: break

func _open_titles(node: Node) -> Array:
	return _disclosures(node).filter(func(section): return (section.get_child(1) as Control).visible).map(func(section): return String(section.get_meta("rec_disclosure")))

func _settle() -> void:
	for i in 3: await tree.process_frame
