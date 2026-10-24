extends RefCounted
## Battle screen smoke test (headless, REAL BattleSim): builds the battle scene from Game.pending_battle,
## steps a whole battle with full presentation, opens the inspector on a unit (log rows with detail/calc
## expansion, health tab, synthetic tap), checks severed-part decals, the settings overlay pausing playback,
## reaches Game.finish_battle and builds the aftermath screen. Also: the 2x2 map for big battles (skip to end)
## and a chokepoint map whose blocked tiles come from the sim.

func run(tree: SceneTree) -> int:
	var fails := 0
	await tree.process_frame   # runner calls run() from _ready; root is busy until the next frame
	var t0 := Time.get_ticks_msec()
	fails += await _small_battle(tree)
	print("  small: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	t0 = Time.get_ticks_msec()
	fails += await _large_battle(tree)
	print("  large: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	t0 = Time.get_ticks_msec()
	fails += await _choke_battle(tree)
	print("  choke: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	return fails

func _check(cond: bool, what: String) -> int:
	if not cond:
		printerr("FAIL: ", what)
		return 1
	return 0

func _make(tree: SceneTree, enemies: int, s: int, extra: Dictionary = {}) -> Node:
	var loaded := await DevTools.start_world(tree, Game.SAVE_PATH)
	assert(loaded, "Normal one-day battle fixture loads")
	var town := DevTools.choose_house(Game, func(choice: Dictionary):
		return str(Dynasty.person(Game, str(choice["ruler_uid"])).get("race", "")) == "human")
	var raised := DevTools.raise_army(Game, town, 2)
	assert(raised == 2, "two native residents muster for every battle case")
	var rng := RandomNumberGenerator.new(); rng.seed = s
	Game.pending_battle = {"enemy": Factory.make_warband(rng, "orc_horde", enemies), "allies": [], "seed": s,
		"terrain": "forest"}
	Game.pending_battle.merge(extra, true)
	var b: Node = (load("res://battle/battle.tscn") as PackedScene).instantiate()
	tree.root.add_child(b)
	b.set_speed(0.0)   # pause before the first frame; the test drives ticks
	await tree.process_frame
	return b

func _small_battle(tree: SceneTree) -> int:
	var fails := 0
	var b := await _make(tree, 10, 11)
	var n_player := Game.deployed_units().size()
	fails += _check(n_player == 2, "two native residents mustered for a real battle")
	fails += _check(b.sim is BattleSim, "real BattleSim")
	fails += _check(b.sim.fighters.size() == n_player + 10, "fighter count")
	fails += _check(b.views.size() == b.sim.fighters.size(), "one view per fighter")
	fails += _check(b.sim.grid_w == 32 and b.sim.grid_h == 18, "small grid 32x18")
	var rough := 0
	for y in b.sim.grid_h:
		for x in b.sim.grid_w:
			if b.sim.tile_at(Vector2i(x, y)) != "open":
				rough += 1
	fails += _check(rough > 0, "forest dressing gave rough/blocked tiles (%d)" % rough)
	b.step_ticks(120)
	fails += _check(b.sim.tick == 120 or b.sim.is_over(), "stepped 120 ticks")
	# tap a living player unit through the same path a real tap takes
	var pick := 0
	for f in b.sim.fighters:
		if f.side == 0 and f.alive():
			pick = f.idx
			break
	b.tap_screen(b.screen_pos_of(pick))
	fails += _check(b.selected == pick and b.inspector.visible, "tap opens inspector")
	b.step_ticks(200)
	await tree.process_frame
	var f = b.sim.fighters[pick]
	var rows: int = b.inspector.entry_row_count()
	fails += _check(rows > 0, "log rows built (%d rows, %d entries)" % [rows, f.log.size()])
	fails += _check(rows == f.log.size() - b.inspector._log_first, "log tab live: rows match entries (%d vs %d)" % [rows, f.log.size() - b.inspector._log_first])
	var first_row := 1 if b.inspector._log_first > 0 else 0
	if rows > 0:
		fails += _check(b.inspector.expand_entry(first_row) == 1, "first tap shows detail")
		fails += _check(b.inspector.expand_entry(first_row) == 2, "second tap shows calc")
		fails += _check(b.inspector.expand_entry(first_row) == 0, "third tap collapses")
	b.inspector.show_tab("health")
	fails += _check(b.inspector.health_text.visible and b.inspector.health_text.text != "", "health tab renders")
	fails += _check(b.inspector.state_label.text.contains("Speed"), "speed shown")
	# settings overlay pauses playback and restores it when closed
	b.set_speed(1.0)
	var gear: Button = null
	for c in b.ui.get_child(0).get_children():
		if c is Button and c.text == "Settings":
			gear = c
	fails += _check(gear != null, "settings button present")
	if gear:
		gear.pressed.emit()
		await tree.process_frame
		fails += _check(b.paused and b.settings_open, "settings overlay pauses")
		b._settings_overlay.queue_free()
		await tree.process_frame
		await tree.process_frame
		fails += _check(not b.paused, "closing settings resumes")
	b.set_speed(0.0)
	# play out the rest with presentation
	var guard := 0
	while not b.sim.is_over() and guard < 30000:
		b.step_ticks(50)
		guard += 50
	fails += _check(b.sim.is_over() and b.sim.tick > 0, "nonempty native battle ends")
	var severs: int = b.sim.events.filter(func(e): return e["type"] == "sever" and e["part"] != "").size()
	fails += _check(b.gore_pieces.size() == severs, "one ground decal per sever (%d vs %d)" % [b.gore_pieces.size(), severs])
	var before: int = b.gore_pieces.size()
	b._drop_piece(pick, "head")   # decal path even if this seed had no sever
	fails += _check(b.gore_pieces.size() == before + 1 and b.gore_pieces[-1]["node"] is Node2D, "severed-piece decal placed")
	var feed_ok := true
	for e in b.sim.events:
		if e["decisive"] and BattleSim.event_text(e) == "":
			feed_ok = false
	fails += _check(feed_ok, "every decisive event has feed text")
	b.show_result()
	fails += _check(b.result_shown, "result shown")
	var deaths: int = b.sim.events.filter(func(e): return e["type"] == "death").size()
	print("small battle: %d ticks, winner %d, %d deaths, %d severs, %d events" % [b.sim.tick, b.sim.winner, deaths, severs, b.sim.events.size()])
	var company_before := Game.company.size()
	var dead_players := 0
	for u in Game.company:
		if u.dead: dead_players += 1
	var main_before = Game.main
	Game.main = null   # keep finish_battle from switching screens in the test
	b.finish()
	Game.main = main_before
	var r: Dictionary = Game.last_result
	for k in ["winner", "player_units", "enemy_units", "enemy_fallen", "events", "loot_gold", "growth"]:
		fails += _check(r.has(k), "result has " + k)
	fails += _check(Game.company.size() == company_before - dead_players, "dead removed from company")
	fails += _check(Game.pending_battle.is_empty(), "pending battle cleared")
	b.queue_free()
	await tree.process_frame
	var a: Node = (load("res://battle/aftermath.tscn") as PackedScene).instantiate()
	tree.root.add_child(a)
	await tree.process_frame
	fails += _check(a.get_child_count() > 0, "aftermath builds")
	a.queue_free()
	await tree.process_frame
	return fails

func _large_battle(tree: SceneTree) -> int:
	var fails := 0
	var b := await _make(tree, 30, 23, {"terrain": "grassland"})
	fails += _check(b.sim.grid_w == 64 and b.sim.grid_h == 36, "large grid 64x36 for 30 enemies")
	b.select(b.views.size() - 1)
	b.skip_to_end()
	fails += _check(b.sim.is_over(), "skip reaches the end")
	# Finish the native medic/bleeding phase before expecting its result card.
	for _frame in b.AFTER_STEPS + 2:
		b._process(b.AFTER_STEP_SECS)
		await tree.process_frame
	fails += _check(b.result_shown, "result after skip")
	print("large battle: %d ticks, winner %d" % [b.sim.tick, b.sim.winner])
	Game.main = null
	b.finish()
	fails += _check(Game.last_result.has("loot_gold"), "large battle finished")
	b.queue_free()
	await tree.process_frame
	return fails

func _choke_battle(tree: SceneTree) -> int:
	var fails := 0
	var b := await _make(tree, 8, 31, {"terrain": "hills", "choke": "corridor1", "stream": true})
	var blocked := 0
	for y in b.sim.grid_h:
		for x in b.sim.grid_w:
			if b.sim.tile_at(Vector2i(x, y)) == "blocked":
				blocked += 1
	fails += _check(blocked > 10, "corridor map has walls (%d)" % blocked)
	b.step_ticks(1)
	for v in b.views:
		v.update_visual(0.0, 0.0)
		if v.fighter.waiting and v.visible:
			fails += _check(false, "waiting (streaming) unit is hidden")
	b.skip_to_end()
	fails += _check(b.sim.is_over(), "choke battle ends")
	print("choke battle: %d ticks, winner %d" % [b.sim.tick, b.sim.winner])
	b.queue_free()
	await tree.process_frame
	return fails
