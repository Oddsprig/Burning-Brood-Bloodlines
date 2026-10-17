extends RefCounted
## v0.028 dragon fear: siege a foreign town with a marching dragon; the town and a
## neighbour gain fear; a frightened, disloyal town then defects to the player's
## faction. Modelled on tests/claude_campaign.gd. -- --test=res://tests/claude_dragonfear.gd
var checks := 0
var fails := 0
var main: Node = null

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL dragonfear: ", what)
	print(("ok   " if ok else "FAIL ") + what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame

func fight(tree: SceneTree, label: String) -> Dictionary:
	await frames(tree, 5)
	var b: Node = main.current
	check(b != null and "sim" in b, label + ": battle screen opened")
	if b == null or not ("sim" in b): return {}
	var t0 := Time.get_ticks_usec()
	b.skip_to_end()
	while is_instance_valid(b) and main.current == b and Time.get_ticks_usec() - t0 < 120000000:
		await tree.process_frame
		if b.result_shown and not b.finished:
			b.finish()
	await frames(tree, 5)
	var res: Dictionary = Game.last_result
	return {"winner": int(res.get("winner", -1)), "outcome": res.get("assault_outcome", {})}

func run(tree: SceneTree) -> int:
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(1280, 720)
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var generation := Game.new_game_begin(4242)
	while not Game.new_game_slice(generation, 8000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000); await tree.process_frame
	CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	# Choose a ruling house that owns an adult dragon at home (as claude_campaign).
	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult" or not dragon.get("alive", false): continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]): continue
		if HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false):
			tid = str(owner["town_id"]); break
	check(tid != "", "house with a dragon chosen")
	if tid == "":
		print("dragonfear: %d checks, %d failures" % [checks, fails]); return fails
	Game.goto("map"); await frames(tree, 5)
	Game.location = tid
	var purse0 := float(Feudal._payer(Game).get("purse", 0.0))
	var fund := Mobilization.fund(Game, int(floor(purse0 * 0.6)))
	var quote := Mobilization.quote(Game, tid, 200)
	check(fund.get("ok", false) and quote.get("ok", false), "army funded from the real house purse")
	Mobilization.muster(Game, tid, 200, quote.get("review", {}))
	check(Game.company.size() > 50, "raised %d real residents" % Game.company.size())
	var marched := 0
	for dragon: Dictionary in Dragons.records(Game):
		var uid := str(dragon["id"])
		if dragon.get("stage", "") != "adult" or str(dragon.get("location_town_id", "")) != tid: continue
		var cands: Array = DragonBond.candidates(Game, uid)
		if cands.is_empty(): continue
		var pid := str(cands[0]["person_uid"])
		DragonBond.bind(Game, uid, pid, DragonBond.bind_preview(Game, uid, pid))
		if Warfare.set_march(Game, uid, true).get("ok", false): marched += 1
	check(marched >= 1, "%d bonded dragon(s) march with the army" % marched)
	if marched < 1:
		print("dragonfear: %d checks, %d failures" % [checks, fails]); return fails
	# Nearest foreign town that has a same-faction neighbour within 400 px.
	var mine := Warfare.player_faction(Game)
	var home_pos: Vector2 = Game.world["towns"][tid]["pos"]
	var targets: Array = []
	var rows: Dictionary = Feudal._state(Game.world)["towns"]
	for t2 in Game.world["towns"]:
		if str(Game.world["towns"][t2]["faction"]) != mine: targets.append(str(t2))
	targets.sort_custom(func(a, b): return (Game.world["towns"][a]["pos"] as Vector2).distance_to(home_pos) < (Game.world["towns"][b]["pos"] as Vector2).distance_to(home_pos))
	var target := ""
	var neighbour := ""
	for cand in targets:
		var fid := str(Game.world["towns"][cand]["faction"])
		var cpos: Vector2 = Game.world["towns"][cand]["pos"]
		for other in targets:
			if other == cand or str(Game.world["towns"][other]["faction"]) != fid: continue
			if str(rows.get(str(other), {}).get("tier", "")) == "sovereign": continue
			if (Game.world["towns"][other]["pos"] as Vector2).distance_to(cpos) <= 400.0:
				target = cand; neighbour = other; break
		if target != "": break
	check(target != "", "foreign town with a same-faction neighbour within 400 px exists")
	if target == "":
		print("dragonfear: %d checks, %d failures" % [checks, fails]); return fails
	var faction_before := str(Game.world["towns"][target]["faction"])
	Game.location = ""
	Game.world["party"]["pos"] = Game.world["towns"][target]["pos"]
	Game.world["encounter"] = ""
	Game.goto("map"); await frames(tree, 4)
	var p := Warfare.preview(Game, target, "siege")
	check(p.get("ok", false), "siege preview at %s: %s" % [Game.world["towns"][target]["name"], p.get("reason", "")])
	var r := Warfare.start(Game, target, "siege")
	check(r.get("ok", false), "siege started")
	if r.get("battle", false):
		await fight(tree, "siege")
	Game.goto("map"); await frames(tree, 4)
	check(DragonFear.fear(Game, target) > 0.0, "assaulted town fears dragons (%.1f)" % DragonFear.fear(Game, target))
	check(DragonFear.fear(Game, neighbour) > 0.0, "neighbouring town fears dragons (%.1f)" % DragonFear.fear(Game, neighbour))
	# A still-foreign, non-sovereign frightened town defects when loyalty is low.
	var flip := neighbour
	# After the siege a realm may have moved its seat; pick a still-foreign, non-seat town of the same realm.
	for t3 in Game.world["towns"]:
		var r3: Dictionary = Feudal._state(Game.world)["towns"].get(str(t3), {})
		if str(Game.world["towns"][t3]["faction"]) == faction_before and str(r3.get("tier", "")) != "sovereign":
			flip = str(t3)
			if str(t3) == neighbour: break
	check(str(Game.world["towns"][flip]["faction"]) == faction_before, "defection candidate %s still foreign" % Game.world["towns"][flip]["name"])
	# The siege resolves through Feudal.finish/prepare_world; use the live row, not the pre-siege reference.
	var row: Dictionary = Feudal._state(Game.world)["towns"][flip]
	check(str(row.get("tier", "")) != "sovereign", "defection candidate %s is not its realm's seat after the siege" % Game.world["towns"][flip]["name"])
	row["loyalty"] = 25.0
	DragonFear.add(Game, flip, 90.0 - DragonFear.fear(Game, flip), mine)
	check(is_equal_approx(DragonFear.fear(Game, flip), 90.0) and str(row.get("fear_of", "")) == mine, "candidate set to loyalty 25, fear 90 of the player's faction")
	var day0 := int(floor(Game.day))
	for step in 2:
		Game.advance_time(1.0, false, 0, 0)
		while not Game.world.get("work", []).is_empty():
			CampaignWorld.work_slice(Game, 20000); await tree.process_frame
		await tree.process_frame
		if str(Game.world["towns"][flip]["faction"]) == mine: break
		if int(floor(Game.day)) > day0 + 1: break
	if str(Game.world["towns"][flip]["faction"]) != mine:
		var live: Dictionary = Feudal._state(Game.world)["towns"].get(flip, {})
		print("dragonfear diag: feudal day %d, game day %.2f, loyalty %.1f, fear %.1f, fear_of %s, tier %s, gate: %s" % [int(Feudal._state(Game.world).get("day", -1)), float(Game.day), float(live.get("loyalty", -1.0)), DragonFear.fear(Game, flip), str(live.get("fear_of", "")), str(live.get("tier", "")), str(Feudal._defect_check(Game, flip, mine).get("reason", ""))])
	check(str(Game.world["towns"][flip]["faction"]) == mine, "%s defected to the player's faction out of fear of dragons" % Game.world["towns"][flip]["name"])
	print("dragonfear: %d checks, %d failures" % [checks, fails])
	return fails
