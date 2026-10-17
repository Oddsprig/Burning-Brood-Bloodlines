extends RefCounted
## Isolated controlled v0.043/candidate measurements. Timing is diagnostic;
## existing native tests retain their original strict 16 ms gate.
const BASELINE := preload("res://tests/fixtures/records_v044_baseline.gd")
const SAMPLES := 7
const WORLD_TABS := ["Mines & land", "Census", "Merchants", "Towns", "On the move", "Food flows"]
const TOWN_TABS := ["Businesses", "Register"]
var tree: SceneTree
var samples := {}
var recording := false
var failures := 0

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
		printerr("FAIL: evolved seed 11 has no original recruited/militia town")
		return 1
	Game.location = tid
	Game.screen_params = {"view": "town", "id": tid, "tab": "Overview", "back": "town"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 1280)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var before := Game._save_tree()
	var random_state: int = Game.rng.state
	var screen: Node = load("res://ui/records.tscn").instantiate()
	viewport.add_child(screen)
	await _settle()
	screen.set_view("world", "", "Towns")
	await _settle()
	var tids: Array = screen.tids()
	print("RECORDS V044 BASELINE commit=", BASELINE.COMMIT, " source_blobs=", BASELINE.SOURCE_BLOBS)
	_counts(tids, tid)
	print("RECORDS V044 METHOD one discarded warmup; ", SAMPLES, " recorded alternating pairs on SAME seed=11 +40days world. Full = unchanged primary closed tab, population header, all metrics/tables and closed Scope totals; synchronous UI construction only. Disposal, equality, callbacks and layout outside timing. No persistent cache or artificial world copies between pairs, save/RNG edits or 16ms-gate changes. Existing read isolation still copies its local containers.")
	for iteration in range(-1, SAMPLES):
		recording = iteration >= 0
		for tab in WORLD_TABS:
			for candidate in ([false, true] if iteration % 2 == 0 else [true, false]):
				var tag := "candidate" if candidate else "baseline v043"
				_node_sample(tag + " world " + tab + " full", func(): return RecWorld.build(screen, tids, "", tab) if candidate else BASELINE.build(screen, tids, "", tab), iteration)
		for tab in TOWN_TABS:
			for candidate in ([false, true] if iteration % 2 == 0 else [true, false]):
				var tag := "candidate" if candidate else "baseline v043"
				_node_sample(tag + " town " + tab + " full", func(): return RecTown.build(screen, RecData.town(tid), tab) if candidate else BASELINE.town_build(screen, RecData.town(tid), tab), iteration)
		# Split attribution preserves the real native builder and its old row reads.
		for candidate in ([false, true] if iteration % 2 == 0 else [true, false]):
			var tag := "candidate" if candidate else "baseline v043"
			_node_sample(tag + " mines table native+rows", func(): return RecWorld.mines_table(screen, tids) if candidate else BASELINE.FrozenWorld.mines_table(screen, tids), iteration)
			_node_sample(tag + " towns table native+rows", func(): return RecWorld.towns_table(screen, tids) if candidate else BASELINE.FrozenWorld.towns_table(screen, tids), iteration)
			_node_sample(tag + " move table native+rows", func(): return RecWorld.move_table(screen, "") if candidate else BASELINE.FrozenWorld.move_table(screen, ""), iteration)
		for tab in WORLD_TABS:
			screen.set_view("world", "", "Goods")
			await _settle()
			var start := Time.get_ticks_usec()
			screen.show_tab(tab)
			_record("candidate navigation world " + tab + " synchronous", _elapsed(start))
			_record("candidate navigation world " + tab + " body only", float(screen.tab_ms))
			start = Time.get_ticks_usec()
			screen.show_tab(tab)
			_record("candidate same-frame world " + tab + " synchronous", _elapsed(start))
			_record("candidate same-frame world " + tab + " body only", float(screen.tab_ms))
			await _settle()
		for tab in TOWN_TABS:
			screen.set_view("town", tid, "Overview")
			await _settle()
			var start := Time.get_ticks_usec()
			screen.show_tab(tab)
			_record("candidate navigation town " + tab + " synchronous", _elapsed(start))
			_record("candidate navigation town " + tab + " body only", float(screen.tab_ms))
			await _settle()
	_pure(before, random_state, "paired core and native navigation")
	# Independent functional checks run after timing; all callback values are
	# resolved and all row targets/details tested by the focused regression.
	var regression = load("res://tests/test_ui_records_v044.gd").new()
	for tab in WORLD_TABS: regression._contract(tids, "", tab, "diagnostic fixed world")
	for tab in TOWN_TABS: regression._town_contract(tid, tab, "diagnostic fixed town")
	failures += int(regression.fails)
	_pure(before, random_state, "full independent equality and native callbacks")
	for phase in samples: _report(String(phase), samples[phase])
	print("RECORDS V044 independent_checks=", regression.checks, " failures=", failures)
	viewport.queue_free()
	await tree.process_frame
	Game.location = ""
	return failures

func _counts(tids: Array, tid: String) -> void:
	var families := 0
	var businesses := 0
	var deposits := 0
	var people := 0
	for id in tids:
		var e := RecData.econ(RecData.town(id))
		families += (e.get("fams", []) as Array).size()
		businesses += (e.get("biz", []) as Array).size()
		deposits += (e.get("deposits", {}) as Dictionary).size()
		people += Census.people(e)
	print("RECORDS V044 WORLD day=", Game.day, " towns=", tids.size(), " families=", families, " businesses=", businesses, " people=", people, " deposits=", deposits, " forces=", Game.world.get("warbands", {}).size(), " town=", tid, " town_businesses=", RecData.biz(RecData.econ(RecData.town(tid))).size())

func _pure(before: Dictionary, state: int, context: String) -> void:
	var save_equal := before == Game._save_tree()
	var rng_equal := state == Game.rng.state
	print("RECORDS V044 PURITY ", context, " saved_data_equal=", save_equal, " rng_equal=", rng_equal)
	if not save_equal or not rng_equal: failures += 1

func _node_sample(phase: String, fn: Callable, iteration: int) -> void:
	var start := Time.get_ticks_usec()
	var node: Node = fn.call()
	_record(phase, _elapsed(start))
	if iteration == 0:
		var shape := {"nodes": 0, "tables": 0, "available_rows": 0, "built_rows": 0}
		_shape(node, shape)
		print("RECORDS V044 SHAPE ", phase, " ", shape)
	node.free()

func _shape(node: Node, shape: Dictionary) -> void:
	shape["nodes"] += 1
	if node is RecTable or node is BASELINE.FrozenTable:
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
	print("RECORDS V044 ", phase, " n=", values.size(), " min_ms=", ordered[0], " median_ms=", ordered[ordered.size() / 2], " max_ms=", ordered[-1], " samples_ms=", values)

func _elapsed(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0

func _settle() -> void:
	for i in 2: await tree.process_frame
