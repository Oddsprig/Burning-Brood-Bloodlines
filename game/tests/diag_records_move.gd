extends RefCounted
## Diagnostic, not a replacement for test_ui_records' unchanged 16 ms gate or 368-section golden.
## Accepted gate scenario: seed 11 + 40 presim days; 720x1280 rendering-disabled viewport, two draws.
## Frozen v034 and current builder share helpers: paired timing isolates this builder only.
const V034 := preload("res://tests/fixtures/records_v034_move.gd")

class TapProbe extends RefCounted:
	var ids := []
	func open_force(id: String) -> void: ids.append(id)

var checks := 0
var fails := 0
var tree: SceneTree

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func run(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	Game.new_game(11)
	CampaignWorld.presim_step(Game, 40)
	var tid := ""
	for id in Game.world["towns"]:
		if not (Game.world["towns"][id].get("recruits", []) as Array).is_empty() and Militia.units_of(Game, id).size() > 0:
			tid = id
			break
	check(tid != "", "accepted fixture has recruits and militia")
	if tid == "": return fails
	Game.location = tid
	Game.screen_params = {"back": "town"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var screen: Node = (load("res://ui/records.tscn") as PackedScene).instantiate()
	viewport.add_child(screen)
	await _settle()
	# Warm the same tab builders preceding On the move in test_ui_records, without advancing the sim.
	for tab in screen.TOWN_TABS:
		for repeat in 2:
			screen.show_tab(tab)
			await _settle()
	screen.set_view("world")
	for tab in ["Towns", "Factions", "Rulers"]:
		for repeat in 2:
			screen.show_tab(tab)
			await _settle()
	var gate := []
	for repeat in 2:
		screen.show_tab("On the move")
		await _settle()
		gate.append(float(screen.tab_ms))
	print("MOVE GATE scenario=seed11+40days day=", Game.day, " draws_ms=", gate, " min_ms=", minf(gate[0], gate[1]), " towns=", Game.world["towns"].size(), " forces=", Game.world["warbands"].size())
	var tids: Array = screen.tids()
	var holder := VBoxContainer.new()
	viewport.add_child(holder)
	var times := {"v034": [], "candidate": []}
	V034.profiling = false
	for lap in 10:
		var pair := {}
		var hashes := {}
		var order := ["v034", "candidate"] if lap % 2 == 0 else ["candidate", "v034"]
		for version in order:
			var start := Time.get_ticks_usec()
			var page: Control = V034.build(screen, tids, "", "On the move") if version == "v034" else RecWorld.build(screen, tids, "", "On the move")
			holder.add_child(page)
			pair[version] = (Time.get_ticks_usec() - start) / 1000.0
			hashes[version] = _digest(page)
			page.free()
			await _settle()
		check(hashes["v034"] == hashes["candidate"], "all resolved rows, controls, colors and accessible text match")
		if lap >= 2:
			for version in times: times[version].append(pair[version])
		print("MOVE PAIRED lap=", lap, " order=", order, " ms=", pair, " sha256=", hashes)
	for version in times:
		var total := 0.0
		for ms in times[version]: total += float(ms)
		print("MOVE PAIRED warm_mean version=", version, " ms=", total / times[version].size())
	_filter_pairs()
	V034.profiling = true
	for lap in 3:
		var start := Time.get_ticks_usec()
		UiKit.clear(screen.list_box)
		UiKit.clear(screen.page_box)
		screen.list_sc.visible = true
		screen.page_sc.visible = false
		var cleared := Time.get_ticks_usec()
		var current_tids: Array = screen.tids()
		var prepared := Time.get_ticks_usec()
		var page: Control = V034.build(screen, current_tids, "", "On the move")
		var built := Time.get_ticks_usec()
		screen.list_box.add_child(page)
		screen.list_sc.scroll_vertical = 0
		screen.preset = {}
		var attached := Time.get_ticks_usec()
		print("MOVE PHASE lap=", lap, " body_ms=", (attached-start)/1000.0, " clear_visibility_ms=", (cleared-start)/1000.0, " tids_ms=", (prepared-cleared)/1000.0, " build_ms=", (built-prepared)/1000.0, " attach_ms=", (attached-built)/1000.0, " phases=", V034.phases)
		_components(_table(page), current_tids, lap)
		await _settle()
	V034.profiling = false
	for fid in ["", String(Game.world["towns"][tid]["faction"])]:
		screen.view = "world" if fid == "" else "faction"
		screen.sel = fid
		var scoped_tids: Array = screen.tids()
		var before := TapProbe.new()
		var after := TapProbe.new()
		var base_page: Control = V034.build(before, scoped_tids, fid, "On the move")
		var candidate_page: Control = RecWorld.build(after, scoped_tids, fid, "On the move")
		var base_table := _table(base_page)
		var candidate_table := _table(candidate_page)
		check(_digest(base_page) == _digest(candidate_page), "world/faction full page matches")
		check(_exercise(base_table) == _exercise(candidate_table), "sort/reverse/filter/search/all show-more states match")
		for row in base_table.rows: (row["_tap"] as Callable).call()
		for row in candidate_table.rows: (row["_tap"] as Callable).call()
		var expected := []
		for wb in RecWorld._forces(fid): expected.append(String(wb["id"]))
		check(before.ids == expected and after.ids == expected, "every row callback preserves force identity and source order")
		print("MOVE OUTPUT fid=", fid, " rows=", base_table.rows.size(), " callbacks=", before.ids.size())
		base_page.free()
		candidate_page.free()
		await _settle()
	# A real native row signal must still open the correct page and Back must return.
	screen.set_view("world", "", "On the move")
	await _settle()
	var first: Button = _table(screen.list_box)._rows_box.get_child(0)
	var first_name := String(first.get_meta("rec_row")[0])
	first.pressed.emit()
	check(screen.stack.size() == 1 and String(screen.stack[0]["title"]) == first_name, "native force row opens named real detail")
	screen.go_back()
	check(screen.stack.is_empty() and screen.tab == "On the move", "force Back returns to On the move")
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	print("MOVE CHECKS checks=", checks, " failures=", fails)
	return fails

func _filter_pairs() -> void:
	var forces := RecWorld._forces("")
	var times := {"v034": [], "typed": []}
	var wins := 0
	const REPEATS := 16
	for lap in 12:
		var order := ["v034", "typed"] if lap % 2 == 0 else ["typed", "v034"]
		var pair := {}
		var snapshots := {}
		for version in order:
			var last := []
			var start := Time.get_ticks_usec()
			for repeat in REPEATS: last = _alive_arrays(forces, version == "typed")
			pair[version] = (Time.get_ticks_usec()-start)/1000.0/REPEATS
			snapshots[version] = last
		check(snapshots["v034"] == snapshots["typed"], "alternating block retains every alive object and source order")
		if lap >= 2:
			for version in times: times[version].append(pair[version])
			if float(pair["typed"]) < float(pair["v034"]): wins += 1
		print("MOVE FILTER PAIRED lap=", lap, " repeats=", REPEATS, " order=", order, " mean_ms=", pair)
	var means := {}
	for version in times:
		var total := 0.0
		for ms in times[version]: total += float(ms)
		means[version] = total / times[version].size()
	print("MOVE FILTER SUMMARY warm_blocks=10 repeats_per_block=", REPEATS, " means_ms=", means, " typed_faster_blocks=", wins, " saved_ms=", float(means["v034"])-float(means["typed"]))

func _alive_arrays(forces: Array, typed: bool) -> Array:
	var out := []
	if typed:
		for wb: Dictionary in forces:
			var units: Array = []
			for unit: Unit in wb["units"]:
				if not unit.dead: units.append(unit)
			out.append(units)
	else:
		for wb in forces: out.append((wb["units"] as Array).filter(func(u): return not u.dead))
	return out

func _components(table: RecTable, tids: Array, lap: int) -> void:
	var start := Time.get_ticks_usec()
	for tid in tids: RecData.live_people(RecData.econ(RecData.town(tid)))
	var population_ms := (Time.get_ticks_usec()-start)/1000.0
	var forces := RecWorld._forces("")
	var alive := []
	start = Time.get_ticks_usec()
	for wb in forces: alive.append((wb["units"] as Array).filter(func(u): return not u.dead))
	var filter_ms := (Time.get_ticks_usec()-start)/1000.0
	var typed := []
	start = Time.get_ticks_usec()
	for wb: Dictionary in forces:
		var units := []
		for unit: Unit in wb["units"]:
			if not unit.dead: units.append(unit)
		typed.append(units)
	var typed_ms := (Time.get_ticks_usec()-start)/1000.0
	check(alive == typed, "diagnostic typed filter retains exact alive object identity and ordering")
	start = Time.get_ticks_usec()
	var shown := table.shown()
	var sorting_ms := (Time.get_ticks_usec()-start)/1000.0
	start = Time.get_ticks_usec()
	for row in shown.slice(0, 6): (row["near"] as Callable).call()
	var near_ms := (Time.get_ticks_usec()-start)/1000.0
	start = Time.get_ticks_usec()
	for row in shown.slice(0, 6): (row["_d"] as Callable).call()
	var details_ms := (Time.get_ticks_usec()-start)/1000.0
	var visible := shown.slice(0, 6)
	start = Time.get_ticks_usec()
	for row in visible:
		var index: int = table.rows.find(row)
		if String(forces[index].get("kind", "")) != "caravan": CampaignWorld.band_power(alive[index])
	var power_ms := (Time.get_ticks_usec()-start)/1000.0
	start = Time.get_ticks_usec()
	for row in visible: TownEcon.force_supply(Game.world, forces[table.rows.find(row)])
	var supply_ms := (Time.get_ticks_usec()-start)/1000.0
	print("MOVE COMPONENT lap=", lap, " population_ms=", population_ms, " filter_ms=", filter_ms, " typed_filter_ms=", typed_ms, " sorting_ms=", sorting_ms, " first6_near_ms=", near_ms, " first6_details_ms=", details_ms, " first6_power_ms=", power_ms, " first6_supply_ms=", supply_ms)

func _exercise(table: RecTable) -> String:
	var states := [_state(table)]
	for column in table.cols:
		for reverse in 2:
			table.sort_by(String(column["k"]))
			states.append(_state(table))
	for filter in table.filters:
		for option in filter["opts"]:
			table.set_filter(String(filter["t"]), String(option))
			states.append(_state(table))
		table.set_filter(String(filter["t"]), String(filter["opts"][0]))
	for search in [String(table.rows[0]["_s"]).substr(0, 3).to_lower() if not table.rows.is_empty() else "", "no matching force 035", ""]:
		table.search = search
		table._refresh()
		states.append(_state(table))
	while table.shown().size() > table.limit:
		(table._rows_box.get_child(table._rows_box.get_child_count()-1) as Button).pressed.emit()
		states.append(_state(table))
	return JSON.stringify(states).sha256_text()

func _state(table: RecTable) -> Array:
	return [_digest(table, false), table.shown().map(func(row): return table.rows.find(row))]

func _digest(node: Node, full_rows: bool = true) -> String:
	var values := []
	_walk(node, values, full_rows)
	return JSON.stringify(values).sha256_text()

func _walk(node: Node, values: Array, full_rows: bool) -> void:
	if node is Label: values.append(["label", node.text])
	if node is Button:
		values.append(["row", node.get_meta("rec_row"), node.tooltip_text, node.accessibility_name, node.accessibility_description, node.right_color.to_html(true)] if node is RecRow else ["button", node.text])
	if node is RecTable:
		values.append(["columns", node.cols, "filters", node.filters.map(func(f): return [f["t"], f["opts"]])])
		var rows: Array = node.rows if full_rows else []
		for row in rows:
			var resolved := {}
			for key in row:
				if key == "_tap": continue
				var value: Variant = row[key]
				if value is Callable: value = value.call()
				if value is Color: value = value.to_html(true)
				resolved[key] = value
			values.append(["full row", resolved])
	for child in node.get_children(): _walk(child, values, full_rows)

func _table(node: Node) -> RecTable:
	if node is RecTable: return node
	for child in node.get_children():
		var table := _table(child)
		if table != null: return table
	return null

func _settle() -> void:
	for i in 2: await tree.process_frame
