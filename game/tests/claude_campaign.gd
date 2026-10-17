extends RefCounted
## Integrated campaign test through the real screens (main.tscn): fresh world, house, muster, dragon bond and
## march, siege + raid of foreign settlements with real battles, aftermath, ambitions, dragon lifecycle over
## campaign time, save, reload. Prints a timing/receipt summary. -- --test=res://tests/claude_campaign.gd [--out=dir]
var checks := 0
var fails := 0
var main: Node = null
var out := ""
var lines: Array = []

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL campaign: ", what)
	lines.append(("ok   " if ok else "FAIL ") + what)

func frames(tree: SceneTree, n: int = 3) -> void:
	for i in n:
		await tree.process_frame

func shot(tree: SceneTree, name: String) -> void:
	if out == "": return
	await frames(tree, 3)
	await RenderingServer.frame_post_draw
	tree.root.get_texture().get_image().save_png(out.path_join(name + ".png"))

func fight(tree: SceneTree, label: String) -> Dictionary:
	await frames(tree, 5)
	var b: Node = main.current
	check(b != null and "sim" in b, label + ": battle screen opened")
	if b == null or not ("sim" in b): return {}
	await shot(tree, label + "_battle")
	var t0 := Time.get_ticks_usec()
	b.skip_to_end()
	while is_instance_valid(b) and main.current == b and Time.get_ticks_usec() - t0 < 120000000:
		await tree.process_frame
		if b.result_shown and not b.finished:
			b.finish()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	await frames(tree, 5)
	check(main.current != null and str(main.current.scene_file_path).contains("aftermath"), label + ": aftermath opened (%.0f ms)" % ms)
	await shot(tree, label + "_aftermath")
	var res: Dictionary = Game.last_result
	return {"ms": ms, "winner": int(res.get("winner", -1)), "outcome": res.get("assault_outcome", {})}

func run(tree: SceneTree) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(1280, 720)
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	if not await DevTools.start_world(tree, "user://claude_campaign-test.json"):
		printerr("FAIL: the start world did not load")
		return 1
	check(Game.company.is_empty(), "fresh campaign starts with no raised army")
	# Choose a ruling house that owns an adult dragon at home.
	var tid := ""
	for dragon: Dictionary in Dragons.records(Game):
		if dragon.get("stage", "") != "adult" or not dragon.get("alive", false): continue
		var owner := Dragons._person(Game, str(dragon.get("owner_person_uid", "")))
		if owner.is_empty() or str(dragon.get("location_town_id", "")) != str(owner["town_id"]): continue
		if HouseOnboarding.begin(Game, str(owner["town_id"]), str(owner["household_uid"])).get("ok", false):
			tid = str(owner["town_id"]); break
	check(tid != "", "house with a dragon chosen")
	if tid == "": return fails
	Game.goto("map"); await frames(tree, 5)
	Game.location = tid
	print("party ", Game.world["party"]["pos"], " town ", Game.world["towns"][tid]["pos"], " target ", Game.world["party"].get("target"))
	var purse0 := float(Feudal._payer(Game).get("purse", 0.0))
	var fund := Mobilization.fund(Game, int(floor(purse0 * 0.6)))
	var quote := Mobilization.quote(Game, tid, 40)   # small: the siege and raid stay one-clash battles
	check(fund.get("ok", false) and quote.get("ok", false), "army funded from the real house purse (%s / %s)" % [fund.get("reason", ""), quote.get("reason", "")])
	Mobilization.muster(Game, tid, 40, quote.get("review", {}))
	var raised := Game.company.size()
	check(raised >= 20, "raised %d real residents" % raised)
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
	Ambitions.check(Game)
	check(Warfare._state(Game)["ambitions_done"].has("saddle"), "ambition 'Take the Saddle' completed by a real bond")
	Game.goto("dragons", {"back": "map"}); await shot(tree, "dragons_march")
	# Pick the nearest foreign settlements with defenders.
	var mine := Warfare.player_faction(Game)
	var targets: Array = []
	for t2 in Game.world["towns"]:
		if str(Game.world["towns"][t2]["faction"]) != mine: targets.append(str(t2))
	var home_pos: Vector2 = Game.world["towns"][tid]["pos"]
	targets.sort_custom(func(a, b): return (Game.world["towns"][a]["pos"] as Vector2).distance_to(home_pos) < (Game.world["towns"][b]["pos"] as Vector2).distance_to(home_pos))
	check(targets.size() >= 2, "foreign settlements exist")
	if targets.size() < 2: return fails
	var gold_before := Game.gold
	var tasks := [["siege", targets[0]], ["raid", targets[1]]]
	var report := {}
	for task in tasks:
		var kind: String = task[0]; var target: String = task[1]
		Game.location = ""
		Game.world["party"]["pos"] = Game.world["towns"][target]["pos"]
		Game.world["encounter"] = ""
		Game.goto("map"); await frames(tree, 4)
		var p := Warfare.preview(Game, target, kind)
		check(p.get("ok", false), "%s preview at %s: %s" % [kind, Game.world["towns"][target]["name"], p.get("reason", "")])
		if not p.get("ok", false): continue
		var defenders := int(p.get("defenders", 0))
		var faction_before := str(Game.world["towns"][target]["faction"])
		var r := Warfare.start(Game, target, kind)
		check(r.get("ok", false), kind + " started")
		var f: Dictionary = {}
		if r.get("battle", false):
			f = await fight(tree, kind)
		var outcome: Dictionary = f.get("outcome", {}) if r.get("battle", false) else {"won": true}
		report[kind] = {"town": Game.world["towns"][target]["name"], "defenders": defenders, "battle_ms": f.get("ms", 0.0), "winner": f.get("winner", 0), "outcome": outcome.get("text", r.get("reason", ""))}
		if kind == "siege" and bool(outcome.get("won", false)):
			check(str(Game.world["towns"][target]["faction"]) == mine and faction_before != mine, "won siege transfers the settlement to your realm")
		if kind == "raid" and bool(outcome.get("won", false)):
			check(Game.gold > gold_before, "won raid carried off real coin (%d -> %d)" % [gold_before, Game.gold])
		Game.goto("map"); await frames(tree, 4)
	await shot(tree, "map_after_war")
	# Ambitions view and guide render.
	AmbitionsView.open(main.current.modal_host); await shot(tree, "ambitions")
	for c in main.current.modal_host.get_children(): c.queue_free()
	GuideView.open(main.current.modal_host); await shot(tree, "guide")
	# Campaign time: dragons care, eggs incubate and hatch, marching dragons eat.
	var eggs_before := 0
	for row: Dictionary in Dragons.records(Game):
		if row.get("stage", "") == "egg" and row.get("alive", false):
			eggs_before += 1
			DevTools.egg_almost_hatched(Game, str(row["id"]))   # developer tool: a day of good care from hatching
	var t1 := Time.get_ticks_usec()
	var day0 := Game.day
	Game.goto("map"); await frames(tree, 2)
	Game.location = tid; Game.world["party"]["pos"] = Game.world["towns"][tid]["pos"]
	var worst := 0.0
	var hatched := 0
	for d in 5:   # until the next day DragonCare settles
		var s := Time.get_ticks_usec()
		Game.advance_time(1.0, false, 0, 0)
		while not Game.world.get("work", []).is_empty():
			CampaignWorld.work_slice(Game, 20000); await tree.process_frame
		worst = maxf(worst, float(Time.get_ticks_usec() - s) / 1000.0)
		await tree.process_frame
		hatched = 0
		for row: Dictionary in Dragons.records(Game):
			for e in row.get("history", []):
				if e is Dictionary and str(e.get("kind", "")) == "hatched": hatched += 1
		if hatched > 0: break
	check(Game.day >= day0 + 1.0, "campaign days advanced (%.1f -> %.1f)" % [day0, Game.day])
	check(hatched >= 1, "%d egg(s) hatched after incubation (%d eggs before)" % [hatched, eggs_before])
	report["days"] = {"ms_total": float(Time.get_ticks_usec() - t1) / 1000.0, "worst_day_ms": worst}
	# Save and reload.
	var digest_keys := {"towns": Game.world["towns"].size(), "company": Game.company.size(), "gold": Game.gold, "day": Game.day,
		"conquests": (Warfare._state(Game)["conquests"] as Array).size(), "ambitions": Warfare._state(Game)["ambitions_done"].size()}
	var ts := Time.get_ticks_usec()
	Game.save_game(); Game.wait_save()
	var save_ms := float(Time.get_ticks_usec() - ts) / 1000.0
	ts = Time.get_ticks_usec()
	check(Game.load_game(), "save reloads")
	var load_ms := float(Time.get_ticks_usec() - ts) / 1000.0
	var after := {"towns": Game.world["towns"].size(), "company": Game.company.size(), "gold": Game.gold, "day": Game.day,
		"conquests": (Warfare._state(Game)["conquests"] as Array).size(), "ambitions": Warfare._state(Game)["ambitions_done"].size()}
	check(JSON.stringify(after) == JSON.stringify(digest_keys), "campaign state identical after reload %s" % JSON.stringify(after))
	Game.goto("map"); await frames(tree, 5); await shot(tree, "map_reloaded")
	report["save_ms"] = save_ms; report["load_ms"] = load_ms
	report["world_ms"] = 0.0
	report["ambitions"] = Ambitions.completed(Game)
	print("campaign report: ", JSON.stringify(report))
	for l in lines: print("  ", l)
	print("Claude campaign test: %d checks, %d failures" % [checks, fails])
	return fails
