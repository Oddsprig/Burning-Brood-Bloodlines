extends RefCounted
## Round-based battles through main.tscn: a raised army of just over one round against a real enemy band padded to just over one round,
## one round. Each round must field at most round_size a side; wounded sit out; prisoners change hands; the loser goes home.
## Test time budget: DevTools.set_round_size(10) makes a round 10 a side (the game's is 100), so the armies are ~14 a side.
## -- --test=res://tests/claude_rounds.gd [--out=<dir>] [--size=WxH]
var fails := 0
var checks := 0
var out := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func shot(tree: SceneTree, name: String) -> void:
	if out == "": return
	await frames(tree, 4)
	tree.root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func run(tree: SceneTree) -> int:
	var size := Vector2i(1600, 900)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
		if a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x"); size = Vector2i(int(p[0]), int(p[1]))
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 6)
	if not await DevTools.start_world(tree, "user://claude_rounds-test.json"):
		printerr("FAIL: the start world did not load")
		return 1
	DevTools.set_round_size(10)
	var want := BattleRounds.round_size + 4   # just over one round a side: the battle goes in rounds
	# The most populous ruling house.
	var best := ""; var best_pop := 0
	for tid in Game.world["towns"]:
		var t: Dictionary = Game.world["towns"][tid]
		if int(t.get("econ", {}).get("pop", 0)) > best_pop:
			var office := Dynasty.town_office(Game, str(tid))
			if bool(office.get("alive", false)) and HouseOnboarding.begin(Game, str(tid), str(office.get("household_uid", ""))).get("ok", false):
				best = str(tid); best_pop = int(t["econ"]["pop"])
				break
	check(best != "", "a ruling house was chosen")
	if best == "": return 1
	Game.settings["guide_seen"] = true
	Game.goto("map"); await frames(tree, 4)
	Game.location = best
	Mobilization.fund(Game, int(floor(float(Feudal._payer(Game).get("purse", 0.0)) * 0.9)))
	var riders := 0
	for row in Mobilization.household_candidates(Game).slice(0, 3):
		var er: Dictionary = Mobilization.enlist_household(Game, str(row["person_uid"]))
		print("rounds: enlist ", row.get("name", ""), " ", er.get("ok", false), " ", er.get("reason", ""))
		if er.get("ok", false): riders += 1
	check(riders > 0, "family members can ride with the army")
	var quote := Mobilization.quote(Game, best, want)
	print("rounds: quote ", quote.get("ok", false), " ", quote.get("reason", ""), " planned ", quote.get("planned", 0))
	if quote.get("ok", false): Mobilization.muster(Game, best, want, quote["review"])
	var raised := Game.company.size()
	var made := 0
	for u in Game.company:
		if made >= 3: break
		if Mobilization.set_medic(Game, u, true).get("ok", false): made += 1
	print("rounds: medics ", made)
	check(made > 0 and Game.deployed_units().size() == raised - made, "medics stay out of the fighting")
	print("rounds: raised ", raised)
	check(raised - made > BattleRounds.round_size, "more than one round's worth raised (%d)" % raised)
	# A real enemy band, padded with that faction's own troops.
	var enemy_id := ""
	for key in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][key]
		if band.get("faction", "") != Game.world["towns"][best].get("faction", "") and Army.is_people_band(band) and not band.get("units", []).is_empty() and not Monsters.suspended_band(band) and str(band.get("kind", "")) != "caravan":
			enemy_id = str(key); break
	check(enemy_id != "", "an enemy band exists")
	if enemy_id == "": return 1
	var wb: Dictionary = Game.world["warbands"][enemy_id]
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var extra: Array = Factory.make_warband(rng, str(wb["faction"]), maxi(0, want - (wb["units"] as Array).size()))
	for u in extra: u.home_town = str(wb.get("home", ""))
	(wb["units"] as Array).append_array(extra)
	var enemy_total := (wb["units"] as Array).size()
	print("rounds: enemy ", enemy_total)
	Game.start_battle({"enemy": (wb["units"] as Array).duplicate(), "allies": [], "warband_id": enemy_id, "seed": 31, "terrain": "grassland", "map": "small"})
	await frames(tree, 10)
	check(BattleRounds.active(Game), "a battle bigger than one round is fought in rounds")
	if BattleRounds.active(Game):   # one round proves the rounds: both armies start just above breaking, so the round's loser breaks
		Game.pending_battle["rounds"]["morale"] = [BattleRounds.BREAK_MORALE + 1.0, BattleRounds.BREAK_MORALE + 1.0]
	var rounds_seen := 0
	var max_side := [0, 0]
	var guard := 0
	while guard < 40:
		guard += 1
		var b: Node = main.current
		if not ("sim" in b) or b.sim == null: break
		max_side[0] = maxi(max_side[0], int(b.sim.side_total[0])); max_side[1] = maxi(max_side[1], int(b.sim.side_total[1]))
		if rounds_seen == 0: await shot(tree, "round_fight")
		b.skip_to_end()
		var waited := 0
		while not b.result_shown and waited < 6000:
			await tree.process_frame; waited += 1
		check(b.result_shown, "round %d ended" % (rounds_seen + 1))
		if not b.result_shown: break
		rounds_seen += 1
		var st: Dictionary = Game.pending_battle["rounds"]
		var d: Dictionary = st["log"][-1]
		print("rounds: round ", d["round"], " winner ", d["winner"], " fought ", d["fought"], " dead ", d["dead"], " wounded ", d["wounded"], " captured ", d["captured"], " fled ", d["fled"], " morale ", d["morale"], " left ", d["fresh_left"], " household ", d["household"].size())
		if rounds_seen == 1: await shot(tree, "round_summary")
		var over := bool(st.get("over", false))
		b._after_round_panel(over)
		await frames(tree, 6)
		if over:
			await shot(tree, "battle_summary")
			b.finish()
			await frames(tree, 6)
			break
	var named := 0
	for d2 in Game.pending_battle.get("rounds", {}).get("log", []): named += (d2["household"] as Array).size()
	if Game.pending_battle.has("rounds"): check(named > 0, "household members appear in the round summaries")
	var kl: Array = Game.last_result.get("battle_summary", {}).get("kills", [])
	var top := 0
	var hist := {}
	for n in kl: top = maxi(top, int(n)); hist[int(n)] = int(hist.get(int(n), 0)) + 1
	print("rounds: most kills by one man in the battle ", top, " kill histogram ", hist, " raised ", Game.world.get("ennoble", {}).get("raised", []))
	check(rounds_seen >= 1 and int(Game.last_result.get("battle_summary", {}).get("start", [0, 0])[0]) > BattleRounds.round_size, "a battle of %d rounds over more than one round a side" % rounds_seen)
	check(max_side[0] <= BattleRounds.round_size and max_side[1] <= BattleRounds.round_size, "no round fields more than one round a side (%s)" % str(max_side))
	var r: Dictionary = Game.last_result
	print("rounds: winner ", r.get("winner", -9), " rounds ", (r.get("rounds", []) as Array).size(), " summary ", r.get("battle_summary", {}).get("retreat", ""))
	check(not r.is_empty() and r.has("battle_summary"), "the battle result carries its own summary")
	var w := int(r.get("winner", -1))
	if w == 0:
		var still: Dictionary = Game.world["warbands"].get(enemy_id, {})
		if not still.is_empty():
			var home: Dictionary = Game.world["towns"].get(str(still.get("home", "")), {})
			check(not home.is_empty() and (still["pos"] as Vector2).distance_to(home["pos"]) < 1.0, "the beaten band stands at its home to regroup")
			check(float(still.get("regroup_until", 0.0)) > float(Game.day), "the beaten band must regroup before marching")
	elif w == 1:
		var seat: Dictionary = Game.world["towns"].get(str(Game.world["player_house"]["town_id"]), {})
		check((Game.world["party"]["pos"] as Vector2).distance_to(seat["pos"]) < 1.0, "the beaten player army stands at the house seat")
		check(Game.company.filter(func(u): return not u.dead).is_empty(), "the beaten army's survivors went home to remuster")
	for c in Game.world.get("captives", []):
		check(not Game.company.any(func(u): return u.uid == int(c["uid"])), "a captive is no longer in the company")
		check(c.get("unit") is Unit and int(c["unit"].uid) == int(c["uid"]), "v0.033: a captive record keeps the actual Unit for ransom")
	for c in Game.world.get("prisoners", []):
		check(c.get("unit") is Unit and int(c["unit"].uid) == int(c["uid"]), "v0.033: a prisoner record keeps the actual Unit for ransom")
	print("rounds: prisoners ", (Game.world.get("prisoners", []) as Array).size(), " captives ", (Game.world.get("captives", []) as Array).size())
	await frames(tree, 10)
	await shot(tree, "aftermath")
	print("Rounds test: %d checks, %d failures" % [checks, fails])
	return fails
