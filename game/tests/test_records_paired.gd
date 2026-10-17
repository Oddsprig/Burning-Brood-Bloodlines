extends RefCounted
## Same-process alternating comparison of the frozen v0.033 World Towns builder and candidate builder.
## Both use current shared helpers: this isolates the deferred/shared Towns reads, not an entire old release.
## Diagnostic times never replace the unchanged records gate or the full baseline/candidate snapshot.

const V033_WORLD := preload("res://tests/fixtures/records_v033_world.gd")

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
	var times := {"v033": [], "candidate": []}
	for lap in 5:
		var order := ["v033", "candidate"] if lap % 2 == 0 else ["candidate", "v033"]
		var hashes := {}
		var pair := {}
		for version in order:
			var start := Time.get_ticks_usec()
			var page: Control = V033_WORLD.build(screen, tids, "", "Towns") if version == "v033" else RecWorld.build(screen, tids, "", "Towns")
			holder.add_child(page)
			pair[version] = (Time.get_ticks_usec() - start) / 1000.0
			hashes[version] = _digest(page)
			page.free()
			await tree.process_frame
		check(hashes["v033"] == hashes["candidate"], "paired world Towns retains every resolved full row, label and native row description")
		if lap > 0:
			times["v033"].append(pair["v033"])
			times["candidate"].append(pair["candidate"])
		print("RECORDS PAIRED Towns lap=", lap, " order=", order, " v033_ms=", pair["v033"], " candidate_ms=", pair["candidate"])
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

func _digest(page: Node) -> String:
	var values := []
	_walk(page, values)
	return JSON.stringify(values).sha256_text()

func _walk(node: Node, values: Array) -> void:
	if node is Label: values.append(["label", node.text])
	if node is Button:
		values.append(["row", node.get_meta("rec_row"), node.tooltip_text, node.accessibility_name, node.accessibility_description] if node.has_meta("rec_row") else ["button", node.text])
	if node is RecTable:
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
