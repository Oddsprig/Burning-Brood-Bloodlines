extends RefCounted
const Parts201 = preload("res://tests/fixtures/older_201_parts_v100.gd")
## Screen switch times on the default (Large) world, through the real root scene (main.tscn) and Game.goto, so a slow
## switch cannot quietly come back (Douglas v0.014 playtest: "pretty long loading screen between menus. and map
## screen to town screen"; it matters more on the phone). A short stretch of the years before (PRESIM_DAYS) keeps
## the run quick; DEV_NOTES "Screen switch times" has the full numbers (diagnostic: tests/diag_screen_load.gd).
## Checks:
##  - map -> town (arrival autosave) -> map (the Leave button's autosave) -> company -> tab -> back, each under a gate
##    generous enough for a loaded PC (GATE_* ms); the times are printed
##  - the map layer's decor is drawn once per world and reused (same canvas items after the round trip)
##  - the background autosave writes a save that loads, and the faster save walk writes the same JSON as the old one
##    (and the faster load walk rebuilds the same world)

const PRESIM_DAYS := 20
const GATE_MAP_TO_TOWN := 1500.0    # ms: ~1.8 s at this size before v0.014 (the old save alone, 2.9 s a year in), now ~0.6 s
const GATE_TOWN_TO_MAP := 1500.0
const GATE_SCREEN := 600.0          # company / records / back to the town
const GATE_TAB := 60.0              # a tab switch on the company screen (was ~85 ms, now under 15)

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		fails += 1
		printerr("FAIL: ", msg)

func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0

## Game.goto (or a callable that switches) plus the new screen's first frame.
func _switch(tree: SceneTree, fn: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	fn.call()
	await tree.process_frame
	return _ms(t0)

func run(tree: SceneTree) -> int:
	var cases: Array = ["setup", "finish", "codec", "ui", "ui-company", "verify"]
	for day_number: int in range(1, PRESIM_DAYS + 1): cases.append("day%d" % day_number)
	var part: String = Parts201.select(cases)
	if part.is_empty(): return 1
	if part != "all": return await _split_ui(tree, part)
	await tree.process_frame
	WorldGen.gen_size = WorldGen.WORLD_SIZE
	var t0 := Time.get_ticks_usec()
	Game.new_game(2026)
	Game.world["presim"] = {"total": PRESIM_DAYS, "done": 0, "from": Game.day}
	CampaignWorld.presim_step(Game, PRESIM_DAYS)
	CampaignWorld.presim_finish(Game, 0)
	print("world %s (%d towns) and %d days before: %.1f s" % [WorldGen.WORLD_SIZE, Game.world["towns"].size(), PRESIM_DAYS, _ms(t0) / 1000.0])
	_check_walks()
	var empty_result: int = await _ui_routes(tree, false)
	if empty_result != 0: return empty_result
	return await _ui_routes(tree, true)

func _ui_routes(tree: SceneTree, with_company: bool) -> int:
	if with_company:
		var seat: String = DevTools.choose_house(Game)
		check(not seat.is_empty(), "nonempty-company route selects an actual owned house")
		if seat.is_empty(): return fails
		var raised: int = DevTools.raise_army(Game, seat, 4)
		check(raised == 4 and not Game.company.is_empty(), "four real residents join through privately funded native muster")
		if fails > 0: return fails
	var roster_uids: Array = []
	for resident: Unit in Game.company: roster_uids.append(resident.uid)
	check(not Game.company.is_empty() if with_company else Game.company.is_empty(), "both original unraised and funded nonempty routes have the intended native roster")
	var tid := ""
	for id in Game.world["towns"]:
		var t: Dictionary = Game.world["towns"][id]
		if TownEcon.has_econ(t) and not CampaignWorld.is_hostile(Game, t["faction"]):
			tid = id
			break
	check(tid != "", "a friendly town with an economy")
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.create_timer(2.0).timeout   # the title screen, while main.gd loads the big screens
	var ms := {}
	ms["title -> map"] = await _switch(tree, func(): Game.goto("map"))   # builds the map layer for this world (once)
	var MT = load("res://campaign/map_terrain.gd")
	var rids: Array = (MT._cache.get("rids", []) as Array).duplicate()
	check(not rids.is_empty(), "the map layer drew its decor chunks")
	for lap in 2:
		ms["map -> town %d" % lap] = await _switch(tree, func(): main.current._try_enter(tid))
		check(Game.location == tid and main.current.has_method("_leave"), "the town screen opened")
		ms["town -> map %d" % lap] = await _switch(tree, func(): main.current._leave())
		check(main.current.get("terrain") != null, "back on the map")
	check(MT._cache.get("rids", []) == rids, "the map layer's decor was reused, not redrawn")
	Game.location = tid
	ms["map -> town (company)"] = await _switch(tree, func(): Game.goto("town", {"arrive": true}))
	ms["town -> company"] = await _switch(tree, func(): Game.goto("company", {"back": "town"}))
	var worst_tab := 0.0
	for t in ["Mind", "Skills", "Gear", "Health", "Overview"]:
		var t1 := Time.get_ticks_usec()
		main.current.show_tab(t)
		worst_tab = maxf(worst_tab, _ms(t1))
	ms["company tab (worst)"] = worst_tab
	ms["company -> town"] = await _switch(tree, func(): main.current._back())
	ms["town -> records"] = await _switch(tree, func(): main.current.show_tab("Records"))
	ms["records -> town"] = await _switch(tree, func(): main.current.close())
	for k in ms:
		print("  %-24s %7.1f ms" % [k, ms[k]])
	for k in ms:
		var gate := GATE_TAB if k.begins_with("company tab") else (GATE_MAP_TO_TOWN if k.begins_with("map -> town") \
			else (GATE_TOWN_TO_MAP if k.begins_with("town -> map") else GATE_SCREEN))
		if k == "title -> map":
			continue   # the one-off map layer build for a new world (DEV_NOTES)
		check(ms[k] < gate, "%s took %.0f ms (gate %.0f)" % [k, ms[k], gate])
	var after_roster: Array = []
	for resident: Unit in Game.company: after_roster.append(resident.uid)
	check(after_roster == roster_uids, "all five real company tabs retain the entire native roster")
	# the background autosave: written whole, and it loads
	var day: float = Game.day
	var gold: int = Game.gold
	Game.wait_save()
	check(FileAccess.file_exists(Game.SAVE_PATH) and not FileAccess.file_exists(Game.SAVE_PATH + ".tmp"), "the autosave file is in place")
	main.queue_free()
	await tree.process_frame
	check(Game.load_game() and is_equal_approx(Game.day, day) and Game.gold == gold and Game.location == tid,
		"the autosave loads (day, gold, the town)")
	return fails

## The v0.014 save walk (Game._serialize) and load walk (Game._deserialize) give what the old ones gave.
func _check_walks() -> void:
	var t0 := Time.get_ticks_usec()
	var a := JSON.stringify(_old_serialize(Game.world))
	var old_ms := _ms(t0)
	t0 = Time.get_ticks_usec()
	var b := JSON.stringify(Game._serialize(Game.world))
	print("save walk + JSON: old %.0f ms, now %.0f ms (%.1f MB)" % [old_ms, _ms(t0), a.length() / 1048576.0])
	check(a == b, "the save walk writes the same JSON as before")
	var back_old = _old_deserialize(JSON.parse_string(a))
	var back_new = Game._deserialize(JSON.parse_string(a))
	check(JSON.stringify(_old_serialize(back_old)) == JSON.stringify(_old_serialize(back_new)), "the load walk rebuilds the same world")

func _old_serialize(v):
	if v is Unit:
		return {"__unit": v.to_dict()}
	if v is Item:
		return {"__item": v.to_dict()}
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _old_serialize(v[k])
		return o
	if v is Array:
		return v.map(func(x): return _old_serialize(x))
	if v is Vector2:
		return {"__v2": [v.x, v.y]}
	return v

func _old_deserialize(v):
	if v is Dictionary:
		if v.has("__unit"):
			return Unit.from_dict(v["__unit"])
		if v.has("__item"):
			return Item.from_dict(v["__item"])
		if v.has("__v2"):
			return Vector2(v["__v2"][0], v["__v2"][1])
		var o := {}
		for k in v:
			o[k] = _old_deserialize(v[k])
		return o
	if v is Array:
		return v.map(func(x): return _old_deserialize(x))
	return v

func _split_ui(tree: SceneTree, part: String) -> int:
	var io: RefCounted = Parts201.new("ui_load20")
	if io.fails > 0: return 1
	if part == "setup":
		WorldGen.gen_size = WorldGen.WORLD_SIZE
		Game.new_game(2026)
		Game.world["presim"] = {"total": PRESIM_DAYS, "done": 0, "from": Game.day}
		io.context = {"seed": 2026, "size": WorldGen.WORLD_SIZE, "days": PRESIM_DAYS, "from": Game.day}
		return 0 if io.save_step(0) else 1
	if part.begins_with("day"):
		var step: int = int(part.trim_prefix("day"))
		if not io.load_step(step - 1): return 1
		check(int(Game.world["presim"]["total"]) == PRESIM_DAYS and int(Game.world["presim"]["done"]) == step - 1, "UI history resumes its exact real predecessor")
		if fails > 0: return fails
		CampaignWorld.presim_step(Game, 1)
		check(Game.day == float(io.context["from"]) + step and int(Game.world["presim"]["done"]) == step, "UI setup executes every original history day exactly once")
		if fails > 0: return fails
		return 0 if io.save_step(step) else 1
	if part == "finish":
		if not io.load_step(PRESIM_DAYS): return 1
		check(CampaignWorld.presim_left(Game) == 0 and int(Game.world["presim"]["done"]) == PRESIM_DAYS, "all twenty original UI history days completed")
		if fails > 0: return fails
		CampaignWorld.presim_finish(Game, 0)
		check(Game.world["presim"].get("finished", false), "native twenty-day history finish completed")
		return 0 if fails == 0 and io.save_step(PRESIM_DAYS + 1) else maxi(1, fails)
	if part == "verify":
		if not io.verify_chain(PRESIM_DAYS + 1): return 1
		var final_proof: Dictionary = io.read_record("proof%d" % (PRESIM_DAYS + 1))
		if final_proof.is_empty(): return 1
		var preceding: String = str(final_proof["record"])
		var chain: String = str(final_proof["chain"])
		for section: String in ["codec", "ui", "ui-company"]:
			var receipt: Dictionary = io.read_record(section)
			if receipt.is_empty(): return 1
			check(receipt.get("chain") == chain and receipt.get("input") == preceding and receipt.get("failures") == 0, "complete UI/codec receipt: " + section)
		return fails
	if not io.load_step(PRESIM_DAYS + 1): return 1
	if part == "codec": _check_walks()
	else: await _ui_routes(tree, part == "ui-company")
	if fails > 0: return fails
	return 0 if io.write_record(part, {"chain": io.context["chain"], "input": FileAccess.get_sha256(io.path(str(PRESIM_DAYS + 1))), "failures": fails}) else 1
