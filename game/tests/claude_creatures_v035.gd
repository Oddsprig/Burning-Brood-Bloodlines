extends RefCounted
## v0.035 creature review: a world made with creatures on (DevTools.start_world(creatures = true)) has lairs and
## creature packs; a week of campaign time runs with them; the choice is kept per world through save/load, and a
## world from before v0.035 keeps them off. Headless; run with -- --test=res://tests/claude_creatures_v035.gd
var checks := 0
var fails := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL creatures035: ", what)

func _bands(kinds: Array) -> Array:
	var out: Array = []
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		if String(wb.get("kind", "")) in kinds: out.append(wb)
	return out

func run(tree: SceneTree) -> int:
	await tree.process_frame
	if not await DevTools.start_world(tree, "user://creatures035-test.json", true):
		printerr("FAIL: the start world did not load")
		return 1
	var w: Dictionary = Game.world
	check(bool(w.get("creatures_enabled", false)) and Monsters.campaign_creatures_enabled(), "the world was made with creatures on")
	var lairs := Lairs.count(w, false)
	var packs := _bands(Monsters.MONSTER_KINDS)
	print("creatures035: %d lairs, %d creature bands (%s)" % [lairs, packs.size(), str(packs.map(func(b): return String(b.get("faction", ""))))])
	check(lairs > 0, "creature lairs exist (%d)" % lairs)
	check(not packs.is_empty(), "creature packs or dens exist (%d)" % packs.size())
	check(packs.all(func(b): return not Monsters.suspended_band(b)), "no creature band is suspended")
	check(DevTools.choose_house(Game) != "", "a house was chosen")
	var t0 := Time.get_ticks_msec()
	var worst := 0
	for d in 7:
		var s := Time.get_ticks_msec()
		DevTools.run_days(Game, 1)
		worst = maxi(worst, Time.get_ticks_msec() - s)
	print("creatures035: 7 days in %d ms (worst day %d ms); %d lairs, %d creature bands after" % [Time.get_ticks_msec() - t0, worst, Lairs.count(w, false), _bands(Monsters.MONSTER_KINDS).size()])
	check(Lairs.count(w, false) > 0, "lairs remain after a week")
	Game.save_game(); Game.wait_save()
	Game.world = {}; Game.rep = {}
	check(Game.load_game(), "real save reloads")
	check(Monsters.campaign_creatures_enabled() and bool(Game.world.get("creatures_enabled", false)), "the world keeps creatures on after a reload")
	Game.world.erase("creatures_enabled")
	Monsters.use_world(Game.world)
	check(not Monsters.campaign_creatures_enabled(), "a world from before v0.035 keeps creatures off")
	Game.wait_save()
	print("creatures035: %d checks, %d failures" % [checks, fails])
	return fails
