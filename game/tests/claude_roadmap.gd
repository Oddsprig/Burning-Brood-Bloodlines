extends RefCounted
## Roadmap check (v0.023-v0.028) on a copy of the packaged build, built from the integrated campaign test through the real screens (main.tscn): fresh world, house, muster, dragon bond and
## march, siege + raid of foreign settlements with real battles, aftermath, ambitions, dragon lifecycle over
## campaign time, save, reload. Prints a timing/receipt summary. -- --test=res://tests/claude_campaign.gd [--out=dir]
var checks := 0
var fails := 0
var main: Node = null
var out := ""
var lines: Array = []
## v0.100 r3: setup -> siege -> raid -> day01..day50 -> finish, with a fresh --chain=<id>.
## Continuous/default and legacy war/time workloads remain available, but legacy parts are partial coverage.
## Each battle is kept whole (up to its original 120s loop); use the <180s lane for siege/raid.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
const Handoff = preload("res://tests/fixtures/older_speed_checkpoint_v100.gd")
const Source = preload("res://tests/fixtures/older_speed_parts_v100.gd")
var chain := ""
var part := ""

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL campaign: ", what)
	lines.append(("ok   " if ok else "FAIL ") + what)

## v0.100: an autosave copies the world over many frames and holds campaign time meanwhile.
## The test calls game code directly (no paused UI in the way), so it waits for that copy first.
func settle_save(tree: SceneTree) -> void:
	while Game._save_capture != null: await tree.process_frame

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
	var riders := 0
	for v in b.views:
		if v.doll is DragonView and str(v.doll.get("_rider_uid")) != "": riders += 1
	print("ROADMAP %s: dragons with a seated rider drawn: %d" % [label, riders])
	b.skip_to_end()
	var breaths := 0
	while is_instance_valid(b) and main.current == b and Time.get_ticks_usec() - t0 < 120000000:
		await tree.process_frame
		if is_instance_valid(b) and "sim" in b and b.sim != null:
			for e in b.sim.new_events:
				if str(e.get("type", "")) in ["breath", "breath_hit"]: breaths += 1
		if b.result_shown and not b.finished:
			b.finish()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("ROADMAP %s: breath events seen during the battle: %d" % [label, breaths])
	await frames(tree, 5)
	check(main.current != null and str(main.current.scene_file_path).contains("aftermath"), label + ": aftermath opened (%.0f ms)" % ms)
	await shot(tree, label + "_aftermath")
	var res: Dictionary = Game.last_result
	return {"ms": ms, "winner": int(res.get("winner", -1)), "outcome": res.get("assault_outcome", {})}


func _stage() -> int:
	if part == "setup": return 0
	if part == "siege": return 1
	if part == "raid": return 2
	if part == "finish": return 53
	if part.begins_with("day") and part.length() == 5 and part.substr(3).is_valid_int():
		var day := int(part.substr(3))
		if day >= 1 and day <= 50: return day + 2
	return -1

func _publish(tree: SceneTree, cp: RefCounted, stage: int, state: Dictionary) -> int:
	await settle_save(tree)
	# Original assertion failures and failed native round trips NEVER publish a successor.
	if fails != 0: return fails
	var path: String = str(cp.call("_path", stage))
	check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".expected") and not FileAccess.file_exists(path + ".complete.json"), "fresh append-only roadmap stage")
	if fails != 0: return fails
	state["checks"] = checks; state["fails"] = fails; state["lines"] = lines.duplicate()
	state["stage"] = stage; state["passed"] = true; state["run"] = chain
	cp.set("context", state)
	if not bool(cp.call("save_step", stage)):
		check(false, "native roadmap handoff and exact round trip succeed")
		return fails
	var receipt := {"stage": stage, "run": chain, "passed": true, "fails": 0,
		"source": Source.source_stamp(), "save_sha256": FileAccess.get_sha256(path),
		"expected_sha256": FileAccess.get_sha256(path + ".expected")}
	var file := FileAccess.open(path + ".complete.json", FileAccess.WRITE)
	check(file != null, "successful roadmap completion receipt opens")
	if file == null: return fails
	file.store_string(JSON.stringify(receipt, "", true, true)); file.flush()
	var error := file.get_error(); file.close()
	check(error == OK, "successful roadmap completion receipt writes")
	if fails == 0: print("ROADMAP PARTIAL stage=", stage, " chain=", chain, "; finish and all predecessors required")
	return fails

func _resume(cp: RefCounted, previous: int) -> Dictionary:
	var path: String = str(cp.call("_path", previous))
	var receipt: Variant = JSON.parse_string(FileAccess.get_file_as_string(path + ".complete.json"))
	check(receipt is Dictionary, "successful predecessor completion receipt exists")
	if not receipt is Dictionary: return {}
	check(receipt.get("passed") == true and receipt.get("fails") == 0 and receipt.get("run") == chain and receipt.get("stage") == previous and receipt.get("source") == Source.source_stamp(), "predecessor belongs to this successful source/run/stage")
	check(receipt.get("save_sha256") == FileAccess.get_sha256(path) and receipt.get("expected_sha256") == FileAccess.get_sha256(path + ".expected"), "successful predecessor files remain unchanged")
	if fails != 0: return {}
	if not bool(cp.call("load_step", previous)):
		check(false, "successful predecessor exact native snapshot loads")
		return {}
	var state: Dictionary = cp.get("context")
	check(state.get("passed") == true and state.get("fails") == 0 and state.get("run") == chain and state.get("stage") == previous, "failed predecessor cannot become an accepted successor")
	if fails != 0: return {}
	checks += int(state["checks"])
	lines = state["lines"].duplicate()
	return state

func run(tree: SceneTree) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.trim_prefix("--out=").replace("\\", "/")
		if a.begins_with("--part="): part = a.trim_prefix("--part=")
		if a.begins_with("--chain="): chain = a.trim_prefix("--chain=")
	var stage := _stage()
	if stage < 0 and not part in ["", "war", "time"]:
		check(false, "recognized roadmap part")
		return fails
	if stage >= 0:
		check(not chain.is_empty() and chain.length() <= 48, "fresh explicit roadmap chain id")
		for character in chain:
			check(character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-", "safe roadmap chain id")
		if fails != 0: return fails
	if out != "": DirAccess.make_dir_recursive_absolute(out)
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true); tree.root.position = Vector2i(-20000, -20000); tree.root.size = Vector2i(1280, 720)
	Game.settings["guide_seen"] = true
	main = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(main)
	await frames(tree, 8)
	var state: Dictionary = {}
	var cp: RefCounted = Handoff.new("roadmap_r3_" + chain) if stage >= 0 else null
	var tid := ""; var mine := ""; var targets: Array = []; var gold_before := 0
	var report: Dictionary = {}
	if stage <= 0:
		WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
		var start := Time.get_ticks_usec()
		var generation := Game.new_game_begin(4242)
		while not Game.new_game_slice(generation, 8000): await tree.process_frame
		var history := {}
		while CampaignWorld.presim_left(Game) > 0:
			CampaignWorld.presim_slice(Game, history, 8000); await tree.process_frame
		CampaignWorld.presim_finish(Game, 0); Dynasty.prepare_world(Game); Game.new_game_finalize()
		check(Game.company.is_empty(), "fresh campaign starts with no raised army")
		# Choose a ruling house that owns an adult dragon at home.
		tid = ""
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
		var quote := Mobilization.quote(Game, tid, 200)
		check(fund.get("ok", false) and quote.get("ok", false), "army funded from the real house purse (%s / %s)" % [fund.get("reason", ""), quote.get("reason", "")])
		Mobilization.muster(Game, tid, 200, quote.get("review", {}))
		var raised := Game.company.size()
		check(raised > 50, "raised %d real residents" % raised)
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
		var feed := 0
		for row: Dictionary in Dragons.records(Game):
			if bool(row.get("campaign_march", {}).get("enabled", false)): feed += Warfare.feed_cost(row)
		var g0 := int(Game.gold); var wages := Game.daily_wages()
		Game.advance_time(1.0, false, 0, 0)
		while not Game.world.get("work", []).is_empty():
			CampaignWorld.work_slice(Game, 20000); await tree.process_frame
		print("ROADMAP march: army purse %d -> %d over one day; wages %d + dragon feed %d expected" % [g0, int(Game.gold), wages, feed])
		Ambitions.check(Game)
		check(Warfare._state(Game)["ambitions_done"].has("saddle"), "ambition 'Take the Saddle' completed by a real bond")
		Game.goto("dragons", {"back": "map"}); await shot(tree, "dragons_march")
		# Pick the nearest foreign settlements with defenders.
		mine = Warfare.player_faction(Game)
		targets = []
		for t2 in Game.world["towns"]:
			if str(Game.world["towns"][t2]["faction"]) != mine: targets.append(str(t2))
		var home_pos: Vector2 = Game.world["towns"][tid]["pos"]
		targets.sort_custom(func(a, b): return (Game.world["towns"][a]["pos"] as Vector2).distance_to(home_pos) < (Game.world["towns"][b]["pos"] as Vector2).distance_to(home_pos))
		check(targets.size() >= 2, "foreign settlements exist")
		if targets.size() < 2: return fails
		gold_before = Game.gold
	else:
		state = _resume(cp, stage - 1)
		if state.is_empty(): return maxi(1, fails)
		tid = state["tid"]; mine = state["mine"]; targets = state["targets"]; gold_before = state["gold_before"]
		report = state["report"]
		Game.goto("map"); await frames(tree, 4)
	state.merge({"tid": tid, "mine": mine, "targets": targets, "gold_before": gold_before, "report": report}, true)
	if part == "setup": return await _publish(tree, cp, 0, state)
	var tasks := [["siege", targets[0]], ["raid", targets[1]]] if part != "time" else []
	if stage >= 3: tasks = []
	elif part == "siege": tasks = [["siege", targets[0]]]
	elif part == "raid": tasks = [["raid", targets[1]]]
	for task in tasks:
		var kind: String = task[0]; var target: String = task[1]
		Game.location = ""
		Game.world["party"]["pos"] = Game.world["towns"][target]["pos"]
		Game.world["encounter"] = ""
		Game.goto("map"); await frames(tree, 4)
		await settle_save(tree)
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
		print("ROADMAP %s at %s: won %s; %s" % [kind, Game.world["towns"][target]["name"], str(outcome.get("won", false)), str(outcome.get("text", ""))])
		if kind == "siege" and bool(outcome.get("won", false)):
			var frow: Dictionary = Feudal._state(Game.world)["towns"].get(target, {})
			report["conquered"] = target
			print("ROADMAP conquest: %s loyalty %.1f grievance %.1f" % [Game.world["towns"][target]["name"], float(frow.get("loyalty", -1)), float(frow.get("grievance", -1))])
			check(str(Game.world["towns"][target]["faction"]) == mine and faction_before != mine, "won siege transfers the settlement to your realm")
		if kind == "raid" and bool(outcome.get("won", false)):
			check(Game.gold > gold_before, "won raid carried off real coin (%d -> %d)" % [gold_before, Game.gold])
		Game.goto("map"); await frames(tree, 4)

	state.merge({"tid": tid, "mine": mine, "targets": targets, "gold_before": gold_before, "report": report}, true)
	if part == "siege": return await _publish(tree, cp, 1, state)
	var eggs_before := 0
	var day0 := 0.0
	var worst := 0.0
	var autosave_was: Variant = null
	var t1 := Time.get_ticks_usec()
	if stage < 3:
		if main.current == null or not ("modal_host" in main.current):
			Game.goto("map"); await frames(tree, 4)   # --part=time skips the war, which ends on the map
		await shot(tree, "map_after_war")
		# Ambitions view and guide render.
		AmbitionsView.open(main.current.modal_host); await shot(tree, "ambitions")
		for c in main.current.modal_host.get_children(): c.queue_free()
		GuideView.open(main.current.modal_host); await shot(tree, "guide")
		# Campaign time: dragons care, eggs incubate and hatch, marching dragons eat.
		eggs_before = 0
		for row: Dictionary in Dragons.records(Game):
			if row.get("stage", "") == "egg" and row.get("alive", false): eggs_before += 1
		t1 = Time.get_ticks_usec()
		day0 = Game.day
		Game.goto("map"); await frames(tree, 2)
		Game.location = tid; Game.world["party"]["pos"] = Game.world["towns"][tid]["pos"]
		worst = 0.0
		# Each autosave holds the calendar while it copies a large world; this stretch measures the days themselves.
		await settle_save(tree)
		autosave_was = Game.settings.get("autosave", null)
		Game.settings["autosave"] = "off"
		state.merge({"eggs_before": eggs_before, "day0": day0, "worst": worst, "completed_days": 0,
			"day_usec": 0, "autosave_was": autosave_was, "report": report}, true)
		if part == "raid": return await _publish(tree, cp, 2, state)
	else:
		eggs_before = state["eggs_before"]; day0 = state["day0"]; worst = state["worst"]
		autosave_was = state["autosave_was"]
		check(int(state.get("completed_days", -1)) == mini(50, stage - 3), "every preceding native campaign day completed")
		check(Game.day == day0 + float(state["completed_days"]), "native day matches the exact successful predecessor")
		if fails != 0: return fails
		Game.settings["autosave"] = "off"
	var day_count := 0 if part == "war" else 50
	var native_days_this_part := 1 if stage >= 3 and stage <= 52 else (0 if stage == 53 else day_count)
	for d in native_days_this_part:
		await settle_save(tree)
		var s := Time.get_ticks_usec()
		Game.advance_time(1.0, false, 0, 0)
		while not Game.world.get("work", []).is_empty():
			CampaignWorld.work_slice(Game, 20000); await tree.process_frame
		worst = maxf(worst, float(Time.get_ticks_usec() - s) / 1000.0)
		await tree.process_frame
	if autosave_was == null: Game.settings.erase("autosave")
	else: Game.settings["autosave"] = autosave_was
	if stage >= 3 and stage <= 52:
		state["completed_days"] = stage - 2
		state["worst"] = worst
		state["day_usec"] = int(state.get("day_usec", 0)) + Time.get_ticks_usec() - t1
		return await _publish(tree, cp, stage, state)
	var hatched := 0
	for row: Dictionary in Dragons.records(Game):
		for e in row.get("history", []):
			if e is Dictionary and str(e.get("kind", "")) == "hatched": hatched += 1
	if report.has("conquered"):
		var ct: String = report["conquered"]
		var frow2: Dictionary = Feudal._state(Game.world)["towns"].get(ct, {})
		print("ROADMAP after 50 days: %s loyalty %.1f grievance %.1f, faction now %s (yours: %s)" % [Game.world["towns"][ct]["name"], float(frow2.get("loyalty", -1)), float(frow2.get("grievance", -1)), str(Game.world["towns"][ct]["faction"]), Warfare.player_faction(Game)])
	if day_count > 0: check(Game.day >= day0 + 49.0, "50 campaign days advanced (%.1f -> %.1f)" % [day0, Game.day])
	if day_count > 0: check(hatched >= 1, "%d egg(s) hatched after incubation (%d eggs before)" % [hatched, eggs_before])
	report["days"] = {"ms_total": float(state.get("day_usec", 0)) / 1000.0 if stage == 53 else float(Time.get_ticks_usec() - t1) / 1000.0, "worst_day_ms": worst}
	if stage == 53: report["days"]["timing_scope"] = "sum of the 50 actual native-day parts; process/handoff overhead excluded"
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
