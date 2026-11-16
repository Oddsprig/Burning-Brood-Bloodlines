extends RefCounted
## v0.100: alternate the delivered v0.043 Towns presentation and candidate; retain every v0.033 native row.
## v0.100: shared live helpers isolate Towns reads; diagnostic times never replace exact snapshots or the records gate.

const V033_WORLD := preload("res://tests/fixtures/records_v033_world.gd")
## v0.100: commit 33265175d0274084aff69a47020059e9310ac63f deliberately has metrics, lanes and account disclosures.
const V043_WORLD := preload("res://tests/fixtures/records_v044_baseline.gd")

var checks := 0
var fails := 0

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", text)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(11)
	var tid := ""
	for id in Game.world["towns"]:
		if TownEcon.has_econ(Game.world["towns"][id]): tid = id; break
	check(tid != "", "generated world has records")
	if tid == "": return fails
	Game.location = tid
	Game.screen_params = {"view": "town", "id": tid, "tab": "Overview", "back": "town"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var screen: Node = (load("res://ui/records.tscn") as PackedScene).instantiate()
	viewport.add_child(screen)
	await tree.process_frame
	screen.view = "world"
	var tids: Array = screen.tids()
	var holder := VBoxContainer.new()
	viewport.add_child(holder)
	# v0.100: keep the original independent data oracle as well as the updated full presentation oracle.
	var legacy: Control = V033_WORLD.build(screen, tids, "", "Towns")
	var original_rows := _table_rows(_snapshot(legacy))
	check(original_rows.size() == 1 and not original_rows[0].is_empty(), "frozen v033 Towns oracle contains its full native table")
	legacy.free()
	var times := {"v043": [], "candidate": []}
	for lap in 5:
		var order := ["v043", "candidate"] if lap % 2 == 0 else ["candidate", "v043"]
		var snapshots := {}
		var expanded := {}
		var pair := {}
		for version in order:
			var start := Time.get_ticks_usec()
			var page: Control = V043_WORLD.build(screen, tids, "", "Towns") if version == "v043" else RecWorld.build(screen, tids, "", "Towns")
			holder.add_child(page)
			pair[version] = (Time.get_ticks_usec() - start) / 1000.0
			snapshots[version] = _snapshot(page)
			_compare(original_rows, _table_rows(snapshots[version]), "paired " + version + " retains every original v033 resolved Towns row and description", "native rows lap=%d version=%s" % [lap, version])
			# v0.100: the deliberate disclosures retain the old account labels and scope totals; check them opened too.
			_open_disclosures(page)
			expanded[version] = _snapshot(page)
			page.free()
			await tree.process_frame
		_compare(snapshots["v043"], snapshots["candidate"], "paired world Towns retains every resolved full row, label and native row description", "closed Towns lap=%d" % lap)
		_compare(expanded["v043"], expanded["candidate"], "paired expanded Towns retains every account row, label and native row description", "expanded Towns lap=%d" % lap)
		if lap > 0:
			times["v043"].append(pair["v043"])
			times["candidate"].append(pair["candidate"])
		print("RECORDS PAIRED Towns lap=", lap, " order=", order, " v043_ms=", pair["v043"], " candidate_ms=", pair["candidate"])
	for version in times:
		var mean := 0.0
		for ms in times[version]: mean += float(ms)
		print("RECORDS PAIRED Towns warm_mean ", version, " ms=", mean / times[version].size())
	_population_pairs(tids)
	_supply_reads(tids)
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	print("RECORDS PAIRED checks=", checks, " failures=", fails)
	return fails

func _population_pairs(tids: Array) -> void:
	for lap in 4:
		var order := ["v033", "candidate"] if lap % 2 == 0 else ["candidate", "v033"]
		var counts := {}
		var times := {}
		for version in order:
			var count := 0
			var start := Time.get_ticks_usec()
			for tid in tids:
				var e := RecData.econ(RecData.town(tid))
				count += _v033_people(e) if version == "v033" else Census.people(e)
			times[version] = (Time.get_ticks_usec() - start) / 1000.0
			counts[version] = count
		check(counts["v033"] == counts["candidate"], "alternating population reads preserve every family and actual count")
		print("RECORDS PAIRED population lap=", lap, " order=", order, " v033_ms=", times["v033"], " candidate_ms=", times["candidate"])

func _v033_people(e: Dictionary) -> int:
	var n := 0
	for f in e.get("fams", []):
		if f.get("gone", false) or f.get("estate", false): continue
		n += Families.people(f)
	return n

func _supply_reads(tids: Array) -> void:
	for tid in tids:
		var t := RecData.town(tid)
		check(TownEcon.supply_level(t, TownEcon.days_food(t)) == TownEcon.supply_level(t), "shared fresh food days preserve each town's authoritative supply level")
	check(TownEcon.supply_level({}, 0.0) == TownEcon.supply_level({}), "towns without an economy keep the original supply fallback")
	var denominator := maxf(1.0, 10.0 * float(TownEcon.data()["needs"]["food"]))
	var fixture := {"econ": {"stock": {}, "barn": {}, "hh": {}, "granary": 0.0, "pop": 10, "adults": 10}}
	for food_days in [0.0, float(TownEcon.data()["supply_short"]), float(TownEcon.data()["supply_well"]), 50.0]:
		fixture["econ"]["granary"] = food_days * denominator
		check(TownEcon.supply_level(fixture, TownEcon.days_food(fixture)) == TownEcon.supply_level(fixture), "zero and exact supply boundaries retain the authoritative comparison")

func _snapshot(page: Node) -> Array:
	var values := []
	_walk(page, values)
	return values

# v0.100: retain hash equality, but report the first differing label, table row/key or native description.
func _compare(expected: Array, actual: Array, why: String, context: String) -> void:
	var same := JSON.stringify(expected).sha256_text() == JSON.stringify(actual).sha256_text()
	if not same:
		printerr("RECORDS PAIRED FIRST DIFFERENCE ", context, ": ", _first_difference(expected, actual, "$"))
	check(same, why)

func _first_difference(expected: Variant, actual: Variant, path: String) -> String:
	if typeof(expected) != typeof(actual):
		return "%s type %d -> %d; expected=%s actual=%s" % [path, typeof(expected), typeof(actual), str(expected).left(500), str(actual).left(500)]
	if expected is Dictionary:
		if expected.has("name"): path += " (row %s)" % String(expected["name"])
		for key in expected:
			if not actual.has(key): return "%s[%s] missing; expected=%s" % [path, str(key), str(expected[key]).left(500)]
			var difference := _first_difference(expected[key], actual[key], "%s[%s]" % [path, str(key)])
			if difference != "": return difference
		for key in actual:
			if not expected.has(key): return "%s[%s] unexpected; actual=%s" % [path, str(key), str(actual[key]).left(500)]
	elif expected is Array:
		var common := mini(expected.size(), actual.size())
		for i in common:
			var difference := _first_difference(expected[i], actual[i], "%s[%d]" % [path, i])
			if difference != "": return difference
		if expected.size() != actual.size(): return "%s length expected=%d actual=%d; first unmatched expected=%s actual=%s" % [path, expected.size(), actual.size(), str(expected.slice(common, common + 1)).left(500), str(actual.slice(common, common + 1)).left(500)]
	elif expected != actual:
		return "%s expected=%s actual=%s" % [path, str(expected).left(500), str(actual).left(500)]
	return ""

func _table_rows(snapshot: Array) -> Array:
	var tables := []
	for entry in snapshot:
		if entry[0] == "all rows": tables.append(entry[1])
	return tables

func _open_disclosures(node: Node) -> void:
	if node.has_meta("rec_disclosure") and not (node.get_child(1) as Control).visible:
		(node.get_child(0) as Button).pressed.emit()
	for child in node.get_children(): _open_disclosures(child)

func _walk(node: Node, values: Array) -> void:
	if node is Label: values.append(["label", node.text])
	if node is Button:
		# v0.100: aligned cells store visible text in metadata; keep headings and all native row descriptions too.
		values.append(["button", node.text, node.get_meta("rec_values", []), node.get_meta("rec_row", []), node.tooltip_text, node.accessibility_name, node.accessibility_description])
	if node is RecTable or node is V043_WORLD.FrozenTable:
		var rows := []
		for row in node.rows:
			var resolved := {}
			for key in row:
				if key == "_tap": continue
				var value: Variant = row[key]
				if value is Callable: value = value.call()
				if value is Color: value = value.to_html(true)
				resolved[key] = value
			rows.append(resolved)
		values.append(["all rows", rows])
	for child in node.get_children(): _walk(child, values)
