extends RefCounted
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
	await tree.process_frame
	WorldGen.gen_size = WorldGen.WORLD_SIZE
	var t0 := Time.get_ticks_usec()
	Game.new_game(2026)
	Game.world["presim"] = {"total": PRESIM_DAYS, "done": 0, "from": Game.day}
	CampaignWorld.presim_step(Game, PRESIM_DAYS)
	CampaignWorld.presim_finish(Game, 0)
	print("world %s (%d towns) and %d days before: %.1f s" % [WorldGen.WORLD_SIZE, Game.world["towns"].size(), PRESIM_DAYS, _ms(t0) / 1000.0])
	_check_walks()
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
