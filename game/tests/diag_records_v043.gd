extends RefCounted
## Isolated, non-gating Goods cost attribution on test_ui_records' exact
## generated/evolved world. No world copies, counter overrides, RNG edits,
## save writes, synthetic towns, or production instrumentation.
const BASELINE = preload("res://tests/fixtures/records_v043_baseline.gd")
const SAMPLES := 5
var tree: SceneTree
var samples := {}
var sink: Variant
var recording := true

func run(st: SceneTree) -> int:
	tree = st
	await tree.process_frame
	Game.new_game(11)
	CampaignWorld.presim_step(Game, 40)
	var tid := ""
	for key in Game.world["towns"]:
		if not (Game.world["towns"][key].get("recruits", []) as Array).is_empty() and Militia.units_of(Game, key).size() > 0:
			tid = String(key)
			break
	if tid == "":
		printerr("FAIL: seed 11 evolved world has no town with recruits and militia")
		return 1
	Game.location = tid
	Game.screen_params = {"back": "town"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	var start := Time.get_ticks_usec()
	var screen: Node = (load("res://ui/records.tscn") as PackedScene).instantiate()
	viewport.add_child(screen)
	print("RECORDS V043 initial town screen synchronous ms=", _elapsed(start))
	await _settle()
	# First Goods navigation precedes all diagnostic Goods reads/builds.
	var cold := _navigation(screen, true)
	var immediate := _navigation(screen, false)
	print("RECORDS V043 first world Goods navigation ms=", cold, " immediate same-frame rebuild ms=", immediate,
		" (sync_ms and body_ms captured separately)")
	await _settle()
	var tids: Array = screen.tids()
	_counts(tids)
	_definitions()
	for iteration in range(-1, SAMPLES):
		recording = iteration >= 0
		_sample("category totals equivalent reads", func(): return _categories(tids))
		_sample("v042 herd counts equivalent reads", func(): return _heads(tids, false))
		_sample("candidate herd counts equivalent reads", func(): return _heads(tids, true))
		_sample("fodder one read per town", func(): return _fodder(tids))
		_sample("v042 herds row data only", func(): return BASELINE.herd_rows(screen, tids))
		# Split native phase has the exact frozen row data prepared outside timing.
		var rows: Array = BASELINE.herd_rows(screen, tids)
		_node_sample("v042 herds native build only", func(): return RecTable.make([{"k": "town", "t": "Town"}], rows, "town", true, [], true, 8), iteration)
		# Alternate candidate/baseline order, on this exact unchanged world.
		for candidate in ([false, true] if iteration % 2 == 0 else [true, false]):
			var tag := "candidate" if candidate else "baseline v042"
			_node_sample(tag + " RecWorld.herds_table full", func():
				return RecWorld.herds_table(screen, tids) if candidate else BASELINE.herds_table(screen, tids), iteration)
			_node_sample(tag + " RecFlows.goods full", func(): return _flows(screen, tids, candidate), iteration)
			_node_sample(tag + " RecWorld.build Goods full", func():
				return RecWorld.build(screen, tids, "", "Goods") if candidate else BASELINE.build(screen, tids), iteration)
		screen.show_tab("Towns")
		await _settle()
		var navigation := _navigation(screen, true)
		var repeated := _navigation(screen, false)
		_nav_records("world Goods navigation after Towns", navigation)
		_nav_records("world Goods immediate same-frame rebuild", repeated)
		await _settle()
	recording = true
	print("RECORDS V043 CORE PURITY saved_data_equal=", before == Game._save_tree(), " rng_equal=", random_state == Game.rng.state)
	await _post_navigation(screen, false)
	# Open real native disclosures only after all core paired samples.
	for section in screen._disclosures(screen.list_box):
		if not (section.get_child(1) as Control).visible: (section.get_child(0) as Button).pressed.emit()
	await _settle()
	await _post_navigation(screen, true)
	print("RECORDS V043 FINAL PURITY saved_data_equal=", before == Game._save_tree(), " rng_equal=", random_state == Game.rng.state)
	for phase in samples: _report(String(phase), samples[phase])
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	return 0

func _definitions() -> void:
	print("RECORDS V043 PHASES: category totals = CATS order, _goods_in then market_totals for every town; no UI.")
	print("RECORDS V043 PHASES: herd counts = frozen v042 or candidate herds per town, per-kind/global/town accumulation as Goods; no UI.")
	print("RECORDS V043 PHASES: fodder = one RecData.fodder_days read per town; no UI.")
	print("RECORDS V043 PHASES: row data = frozen v042 herds_table loop, including herd/fodder reads and lazy callbacks.")
	print("RECORDS V043 PHASES: native = RecTable.make on prebuilt frozen rows, sorting, controls and first 8 native rows.")
	print("RECORDS V043 PHASES: herds full = actual builder; flows full = all Goods UI, closed disclosures, no world header.")
	print("RECORDS V043 PHASES: world full = Goods wrapper including population header and closed Scope totals.")
	print("RECORDS V043 PHASES: navigation = synchronous set_view/show_tab with state capture/restore and control rebuilding.")
	print("RECORDS V043 PHASES: disposal, counts and two-frame layout settles excluded; no timing assertions.")
	print("RECORDS V043 PHASES: one unreported warmup lap, then ", SAMPLES, " recorded pairs; fixed world; alternating order.")
	print("RECORDS V043 PHASES: post-core through-first-process-frame includes wait/layout; sync/body exclude it; no render claim.")

func _counts(tids: Array) -> void:
	var families := 0
	var businesses := 0
	var records := 0
	var heads := 0
	for id in tids:
		var e := RecWorld._e(id)
		families += RecData.fams(e).size()
		businesses += RecData.biz(e).size()
		records += RecData.herd_records(e).size()
		for n in RecData.herds(e).values(): heads += int(n)
	print("RECORDS V043 WORLD seed=11 presim_days=40 day=", Game.day, " towns=", tids.size(),
		" families=", families, " businesses=", businesses, " herd_records=", records, " heads=", heads)

func _categories(tids: Array) -> Array:
	var result := []
	for category in RecTown.CATS:
		var goods_in := RecTown._goods_in(String(category[0]))
		var stock := 0
		var demand := 0.0
		for id in tids:
			var totals := RecData.market_totals(RecWorld._e(id), goods_in)
			stock += int(totals[0])
			demand += float(totals[1])
		result.append([String(category[0]), stock, demand])
	return result

func _heads(tids: Array, candidate: bool) -> Dictionary:
	var herds := {}
	var heads := 0
	var town_heads := {}
	for id in tids:
		var town_herds := RecData.herds(RecWorld._e(id)) if candidate else BASELINE.herd_heads(RecWorld._e(id))
		var town_total := 0
		for kind in town_herds:
			var n := int(town_herds[kind])
			herds[kind] = int(herds.get(kind, 0)) + n
			heads += n
			town_total += n
		town_heads[String(id)] = town_total
	return {"herds": herds, "heads": heads, "town_heads": town_heads}

func _fodder(tids: Array) -> Array:
	var result := []
	for id in tids: result.append(RecData.fodder_days(RecWorld._e(id)))
	return result

func _flows(screen: Node, tids: Array, candidate: bool) -> VBoxContainer:
	var box := UiKit.vbox(8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var legacy := func(b): RecWorld.goods(screen, tids, b)
	if candidate: RecFlows.goods(screen, tids, box, legacy)
	else: BASELINE.goods(screen, tids, box, legacy)
	return box

func _navigation(screen: Node, change_view: bool) -> Dictionary:
	var start := Time.get_ticks_usec()
	if change_view: screen.set_view("world", "", "Goods")
	else: screen.show_tab("Goods")
	return {"sync_ms": _elapsed(start), "body_ms": float(screen.tab_ms)}

func _nav_records(phase: String, values: Dictionary) -> void:
	_record(phase + " synchronous", float(values["sync_ms"]))
	_record(phase + " body only", float(values["body_ms"]))

func _post_navigation(screen: Node, restored: bool) -> void:
	var tag := "restored-open-disclosures" if restored else "closed-disclosures"
	for iteration in range(-1, SAMPLES):
		recording = iteration >= 0
		screen.show_tab("Towns")
		await _settle()
		var start := Time.get_ticks_usec()
		var timing := _navigation(screen, true)
		await tree.process_frame
		_record(tag + " navigation through first process_frame", _elapsed(start))
		_nav_records(tag + " navigation", timing)
		await _settle()
	recording = true

func _sample(phase: String, fn: Callable) -> void:
	var start := Time.get_ticks_usec()
	sink = fn.call()
	_record(phase, _elapsed(start))
	# Release retained rows outside the measured read/construct phase.
	sink = null

func _node_sample(phase: String, fn: Callable, iteration: int) -> void:
	var start := Time.get_ticks_usec()
	var node: Node = fn.call()
	_record(phase, _elapsed(start))
	if iteration == 0:
		var shape := {"nodes": 0, "tables": 0, "available_rows": 0, "built_rows": 0}
		_shape(node, shape)
		print("RECORDS V043 SHAPE ", phase, " ", shape)
	node.free()

func _shape(node: Node, shape: Dictionary) -> void:
	shape["nodes"] += 1
	if node is RecTable:
		shape["tables"] += 1
		shape["available_rows"] += node.rows.size()
	if node.has_meta("rec_row"): shape["built_rows"] += 1
	for child in node.get_children(): _shape(child, shape)

func _record(phase: String, value: float) -> void:
	if not recording: return
	if not samples.has(phase): samples[phase] = []
	(samples[phase] as Array).append(value)

func _report(phase: String, values: Array) -> void:
	var ordered := values.duplicate()
	ordered.sort()
	var mid := ordered.size() / 2
	print("RECORDS V043 ", phase, " n=", ordered.size(), " min_ms=", ordered[0],
		" median_ms=", ordered[int(mid)], " max_ms=", ordered[-1], " samples_ms=", values)

func _elapsed(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0

func _settle() -> void:
	for i in 2: await tree.process_frame
