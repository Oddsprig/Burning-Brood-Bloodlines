extends RefCounted
## Focused Goods regression: frozen v042 presentation, independent saved-data
## totals, real native actions and same-frame refresh. Existing timing gates stay
## in test_ui_records/test_ui_load_times; this test never replaces or relaxes them.
const BASELINE := preload("res://tests/fixtures/records_v043_baseline.gd")
var tree: SceneTree
var checks := 0
var fails := 0
var fit

class Probe extends Control:
	var events := []
	var pages := []
	var preset := {}
	func open_town(id: String) -> void: events.append(["town", id])
	func page(title: String, fill: Callable) -> void:
		events.append(["page", title])
		pages.append(fill)

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func run(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	Game.new_game(40043)
	CampaignWorld.presim_step(Game, 1)
	var fid := "middle_kingdom"
	var tid := String(Game.world["factions"][fid]["capital"])
	Game.location = tid
	fit = load("res://tests/test_ui_fit.gd").new()
	fit.tree = tree
	var all: Array = Game.world["towns"].keys().filter(func(id): return TownEcon.has_econ(Game.world["towns"][id]))
	all.sort_custom(func(a, b): return RecData.tname(a) < RecData.tname(b))
	var scoped: Array = all.filter(func(id): return String(Game.world["towns"][id].get("faction", "")) == fid)
	check(all.size() > RecTable.LIMIT and not scoped.is_empty(), "real world supports Goods paging and faction scope")
	_contract(all, "", "whole world")
	_contract(scoped, fid, "faction")
	for size in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		await _native(size, tid, fid)
	_same_frame(tid)
	Game.location = ""
	print("RECORDS v043 Goods checks=", checks, " failures=", fails, " fit_failures=", fit.fails)
	return fails + int(fit.fails)

func _pure(before: Dictionary, random_state: int, context: String) -> void:
	check(Game._save_tree() == before and Game.rng.state == random_state, "saved campaign and RNG unchanged: " + context)

func _contract(tids: Array, fid: String, context: String) -> void:
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	var old_probe := Probe.new()
	var new_probe := Probe.new()
	var original: Control = BASELINE.build(old_probe, tids, fid)
	var current: Control = RecWorld.build(new_probe, tids, fid, "Goods")
	check(_digest(original) == _digest(current), "closed Goods retains every resolved row, visible cell, tooltip and accessibility field: " + context)
	_facts(current, tids, context)
	_compare_actions(original, current, old_probe, new_probe, context)
	_open_sync(original)
	_open_sync(current)
	check(_digest(original) == _digest(current), "expanded Goods retains full record, animal totals and drovers: " + context)
	_compare_actions(original, current, old_probe, new_probe, context + " disclosures")
	_pure(before, random_state, context + " frozen/full resolution/native callbacks")
	original.free()
	current.free()
	old_probe.pages.clear()
	new_probe.pages.clear()
	old_probe.free()
	new_probe.free()

## Raw saved ledgers and actual age counters form the oracle, independent of
## the candidate's market_totals/herds/prepared-table helpers and their caches.
func _heads(e: Dictionary) -> Dictionary:
	if not e.has("hd"): return (e.get("herd", {}) as Dictionary).duplicate()
	var out := {}
	for record: Dictionary in e["hd"].get("h", {}).values():
		var n := int(record.get("y", 0)) + int(record.get("g", 0)) + int(record.get("o", 0))
		if n > 0:
			var kind := String(record["k"])
			out[kind] = int(out.get(kind, 0)) + n
	return out

func _category_goods(category: String) -> Array:
	var out := []
	for good in (TownEcon.data()["goods"] as Dictionary):
		var entry: Dictionary = TownEcon.data()["goods"][good]
		if not entry.get("no_trade", false) and String(entry.get("cat", "")) == category: out.append(good)
	out.sort()
	return out

func _facts(page: Node, tids: Array, context: String) -> void:
	var market_units := 0
	var total_heads := 0
	var category_rows := _cells(page, ["Kind", "Stock units", "Market days"])
	check(category_rows.size() == RecTown.CATS.size(), "every original category has one visible lane: " + context)
	for category in RecTown.CATS:
		var stock := 0
		var demand := 0.0
		for id in tids:
			var saved: Dictionary = Game.world["towns"][id].get("econ", {})
			var e: Dictionary = saved if saved.has("stock") else {}
			for good in _category_goods(String(category[0])):
				stock += int(e.get("stock", {}).get(good, 0))
				demand += float(e.get("dem", {}).get(good, 0.0))
		market_units += stock
		var expected := [String(category[1]), str(stock), RecKit.num(stock / demand) if demand > 0.0 else "-"]
		check(category_rows.any(func(row): return row.get_meta("rec_values") == expected), "visible category keeps exact stock/fractional demand semantics: " + context + "/" + String(category[0]))
	var table := _with_key(page, "head")
	check(table != null, "structured herd table retains final sort columns: " + context)
	if table == null: return
	check(table.rows.size() == tids.size() and table.limit == 8, "all towns retained with original eight-row first page: " + context)
	for row: Dictionary in table.rows:
		var id := String(row["tid"])
		var saved: Dictionary = Game.world["towns"][id].get("econ", {})
		var e: Dictionary = saved if saved.has("stock") else {}
		var heads := _heads(e)
		var n := 0
		for count in heads.values(): n += int(count)
		total_heads += n
		var fodder: Variant = float(e["hd"].get("fodd", 0.0)) if e.has("hd") and float(e["hd"].get("fneed", 0.0)) > 0.0 else null
		if fodder != null and float(fodder) < 0.0: fodder = null
		check(int(row["head"]) == n and row["fodder"] == fodder, "row head/fodder equals raw records, including missing grazing beasts: " + context + "/" + id)
		var details := RecTown.herd_text(e, heads) + (" (fodder %d days)" % int(float(fodder)) if fodder != null else "")
		check(String((row["_d"] as Callable).call()) == details, "full herd details retain every species and recorded fodder: " + context + "/" + id)
	check(_metric(page, "Towns covered") == str(tids.size()), "town scope metric uses actual scope: " + context)
	check(_metric(page, "Market stock units") == str(market_units), "market metric equals independent category ledgers: " + context)
	check(_metric(page, "Animals in town herds") == str(total_heads), "animal metric equals independent raw age sums: " + context)
	_rendered(table, context)

func _rendered(table: RecTable, context: String) -> void:
	var shown := table.shown()
	for i in mini(shown.size(), table.limit):
		var row: Dictionary = shown[i]
		var cell := table._rows_box.get_child(i) as RecCells
		check(cell != null, "visible herd row is a native structured cell: " + context)
		if cell == null: continue
		var expected := [String(row["town"]), str(int(row["head"])), RecKit.num(float(row["fodder"])) if row["fodder"] != null else "-"]
		var details := String((row["_d"] as Callable).call())
		check(cell.get_meta("rec_values") == expected and cell.get_meta("rec_row")[2] == details, "visible lanes/full details agree with sorted row: " + context)
		check(cell.tooltip_text.contains(details) and cell.accessibility_description.contains(details) and cell.accessibility_name == " · ".join(PackedStringArray(expected)), "native cells expose full current details and visible values: " + context)
	check(table._count.text == "%d shown of %d" % [mini(shown.size(), table.limit), table.rows.size()], "page count agrees with filter/search/sort state: " + context)

func _compare_actions(original: Node, current: Node, old_probe: Probe, new_probe: Probe, context: String) -> void:
	var old_tables := _tables(original)
	var new_tables := _tables(current)
	check(old_tables.size() == new_tables.size(), "same number of original Goods tables: " + context)
	for i in mini(old_tables.size(), new_tables.size()):
		var old: RecTable = old_tables[i]
		var actual: RecTable = new_tables[i]
		old_probe.events.clear()
		new_probe.events.clear()
		for row in old.rows:
			var tap: Callable = row.get("_tap", Callable())
			if tap.is_valid(): tap.call()
		for row in actual.rows:
			var tap: Callable = row.get("_tap", Callable())
			if tap.is_valid(): tap.call()
		check(old_probe.events == new_probe.events, "every full Goods row retains its exact native target: " + context)
		if not actual.shown().is_empty():
			new_probe.events.clear()
			var row: Dictionary = actual.shown()[0]
			var tap: Callable = row.get("_tap", Callable())
			if tap.is_valid():
				tap.call()
				var expected := new_probe.events.duplicate(true)
				new_probe.events.clear()
				(actual._rows_box.get_child(0) as Button).pressed.emit()
				check(new_probe.events == expected, "real displayed row signal retains current target: " + context)

func _native(size: Vector2i, tid: String, fid: String) -> void:
	Game.screen_params = {"view": "world", "id": "", "tab": "Goods", "back": "town"}
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var screen: Control = load("res://ui/records.tscn").instantiate()
	viewport.add_child(screen)
	await _settle()
	var context := str(size)
	check(screen.view == "world" and screen.tab == "Goods", "native saved Goods deep link opens: " + context)
	fit._check(viewport, Vector2(size), "v043 Goods " + context)
	var table := _with_key(screen.list_box, "head")
	check(table != null, "native Goods has actual head/fodder table: " + context)
	if table != null:
		var first := table._rows_box.get_child(0)
		var more := _button(table, "Show %d more" % mini(RecTable.LIMIT, table.shown().size() - table.limit))
		check(more != null, "original first page exposes native Show more: " + context)
		if more != null:
			more.pressed.emit()
			check(table.limit == 23 and table._rows_box.get_child(0) == first, "Show more adds fifteen and retains identical existing cell: " + context)
		_rendered(table, context + " more")
		var sort := _option(table, "Head")
		check(sort != null, "native Head sort picker retained: " + context)
		if sort != null:
			var index := _option_index(sort, "Head")
			sort.select(index)
			sort.item_selected.emit(index)
		check(table.sort_k == "head" and not table.asc, "native Head picker starts numeric largest first: " + context)
		var order := table.shown()
		for i in range(1, order.size()): check(int(order[i - 1]["head"]) >= int(order[i]["head"]), "head order retains independent counts: " + context)
		var direction := _button(table, "Descending")
		check(direction != null, "native direction control retained: " + context)
		if direction != null: direction.pressed.emit()
		check(table.asc, "native direction reverses Head: " + context)
		table.sort_by("fodder")
		var missing := false
		for row in table.shown():
			if row["fodder"] == null: missing = true
			else: check(not missing, "missing fodder sorts after tracked values: " + context)
		var query := String(table.shown()[0]["town"]).substr(0, 3).to_lower()
		table._search_box.text = query
		table._search_box.text_changed.emit(query)
		check(not table.shown().is_empty() and table.shown().all(func(row): return String(row["town"]).to_lower().contains(query)), "native name query keeps exact town matches: " + context)
		_rendered(table, context + " search")
		_open_sync(screen.list_box)
		await _settle()
		var state := table.ui_state().duplicate(true)
		var rows := _resolved(table.shown())
		var opened := _open_titles(screen.list_box)
		screen.list_sc.scroll_vertical = 70
		await _settle()
		var scroll: int = screen.list_sc.scroll_vertical
		var category := _cells(screen.list_box, ["Kind", "Stock units", "Market days"])[0] as Button
		category.pressed.emit()
		await _settle()
		check(screen.stack.size() == 1, "native kind row opens the exact category page: " + context)
		var goods := _cells(screen.page_box, ["Good", "Stock", "Low coins", "High coins"])
		check(not goods.is_empty(), "category page retains actual priced goods: " + context)
		if not goods.is_empty():
			(goods[0] as Button).pressed.emit()
			await _settle()
			check(screen.stack.size() == 2 and _with_key(screen.page_box, "price") != null, "native good row opens original town price/stock table: " + context)
			var back := _button(screen.page_box, "Back")
			if back != null: back.pressed.emit()
			await _settle()
		var back := _button(screen.page_box, "Back")
		check(back != null, "category detail exposes native Back: " + context)
		if back != null: back.pressed.emit()
		await _settle()
		table = _with_key(screen.list_box, "head")
		check(screen.stack.is_empty() and table != null, "Back returns to Goods: " + context)
		if table != null:
			check(table.ui_state() == state and _resolved(table.shown()) == rows, "Back restores sort/search/page/full row data: " + context)
			_rendered(table, context + " Back")
		check(_open_titles(screen.list_box) == opened and abs(screen.list_sc.scroll_vertical - scroll) <= 1, "Back restores real disclosure state and scroll: " + context)
		fit._check(viewport, Vector2(size), "v043 Goods restored " + context)
		if table != null and not table.shown().is_empty():
			var expected := String(table.shown()[0]["tid"])
			(table._rows_box.get_child(0) as Button).pressed.emit()
			await _settle()
			check(screen.view == "town" and screen.sel == expected, "native herd cell opens its actual town identity: " + context)
			screen.set_view("faction", fid, "Goods")
			await _settle()
			_facts(screen.list_box, screen.tids(), "native faction " + context)
	_pure(before, random_state, "native Goods sorting/search/paging/details/Back/town/faction " + context)
	viewport.queue_free()
	await tree.process_frame

func _same_frame(tid: String) -> void:
	var actual: Dictionary = Game.world
	Game.world = actual.duplicate(true)
	var e: Dictionary = Game.world["towns"][tid]["econ"]
	# Cold caches first, then a normal versioned herd edit within this same frame.
	for key in ["_th", "_thk"]: e["hd"].erase(key)
	_contract([tid], "", "cold actual herd cache")
	e["stock"]["grain"] = 91
	e["dem"]["grain"] = 0.125
	e["stock"]["home"] = 99999
	e["stock"]["unknown v043 good"] = 99999
	e["dem"]["unknown v043 good"] = 500.5
	e["price"]["grain"] = 3.625
	e["pweek"] = {"grain": 2.5}
	e["hd"]["fneed"] = 1.0
	e["hd"]["fodd"] = 8.75
	var records: Dictionary = e["hd"]["h"]
	check(not records.is_empty(), "actual selected town has real herd records for same-frame change")
	if not records.is_empty():
		var record: Dictionary = records.values()[0]
		record["y"] = int(record["y"]) + 7
		e["hd"]["ver"] = int(e["hd"].get("ver", 0)) + 1
	_contract([tid], "", "same-frame stock/fractional demand/herd/fodder edit; unknown/no-trade goods excluded")
	_good_facts([tid], "grain")
	# No await separates these builds: a persistent/prepared value cache would fail.
	e["stock"]["grain"] = 7
	e["dem"]["grain"] = 0.0
	e["hd"]["fneed"] = 0.0
	_contract([tid], "", "same-frame zero demand/no grazing beasts")
	_good_facts([tid], "grain")
	e.erase("hd")
	e["herd"] = {"cattle": 2, "hens": 13, "bees": 4}
	e["stock"] = {}
	e.erase("dem")
	_contract([tid], "", "legacy herd totals with empty stock/missing demand ledger")
	e["herd"] = {}
	_contract([tid], "", "empty legacy herds and absent market goods")
	e.erase("stock")
	_contract([tid], "", "missing stock excludes incomplete economy reads")
	_contract([], "", "empty Goods scope")
	Game.world = actual

func _good_facts(tids: Array, good: String) -> void:
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	var probe := Probe.new()
	var box := VBoxContainer.new()
	RecFlows._good_towns(probe, tids, good, box)
	var table := _with_key(box, "price")
	check(table != null and table.rows.size() == tids.size(), "nested good preserves every scoped town")
	if table != null:
		for i in table.rows.size():
			var e: Dictionary = Game.world["towns"][tids[i]]["econ"]
			var row: Dictionary = table.rows[i]
			var stock := int(e.get("stock", {}).get(good, 0))
			var demand := float(e.get("dem", {}).get(good, 0.0))
			var price := float(e["price"].get(good, TownEcon.data()["goods"][good]["price"]))
			var prior: Variant = e.get("pweek", {}).get(good)
			var change: Variant = (price / float(prior) - 1.0) * 100.0 if prior != null and float(prior) > 0.0 else null
			check(row["price"] == price and int(row["stock"]) == stock and row["days"] == (stock / demand if demand > 0.0 else null) and row["chg"] == change, "nested good preserves exact fractional prices/demand/week-change from raw ledgers")
		if not table.shown().is_empty():
			var index: int = table.rows.find(table.shown()[0])
			(table._rows_box.get_child(0) as Button).pressed.emit()
			check(probe.events == [["town", String(tids[index])]], "native nested good row keeps exact actual town")
	_pure(before, random_state, "nested exact good data/actions")
	box.free()
	probe.free()

func _digest(node: Node) -> String:
	var content := []
	_walk(node, content)
	return JSON.stringify(content).sha256_text()

func _walk(node: Node, content: Array) -> void:
	if node is Label: content.append(["label", node.text])
	if node is Button:
		content.append(["button", node.text, node.get_meta("rec_values", []), node.get_meta("rec_row", []), node.tooltip_text, node.accessibility_name, node.accessibility_description])
	if node is RecCells: content.append(["cell", node.headings, node.weights, node.colors.map(func(color): return color.to_html(true))])
	if node is RecTable: content.append(["table", node.cols, _resolved(node.rows), node.ui_state()])
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
	if node is RecTable: out.append(node)
	for child in node.get_children(): out.append_array(_tables(child))
	return out

func _with_key(node: Node, key: String) -> RecTable:
	for table: RecTable in _tables(node):
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
