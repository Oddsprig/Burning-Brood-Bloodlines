extends RefCounted
## Actual fresh Normal, one-day world; no injected people, coin or equipment.
## Commands use its native house, market, population and physical Units.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
var checks: int = 0
var fails: int = 0
var captures: Array = []

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		fails += 1; printerr("FAIL fresh muster world: ", text)

func frames(tree: SceneTree, number: int = 3) -> void:
	for i: int in number:
		await tree.process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func fingerprint(town: Dictionary) -> String:
	return JSON.stringify({"town": Game._serialize(town), "company": Game.company.map(func(u): return u.to_dict()),
		"mobilization": Game._serialize(Game.world.get("mobilization", {})), "purse": Game.gold,
		"provisions": Game.provisions, "day": Game.day, "rng": str(Game.rng.state),
		"unit_next": Unit._next_uid, "item_next": Item._next_uid}, "", true, true).sha256_text()

func item_ids(town: Dictionary) -> Array:
	var items: Array = town.get("shop", []).duplicate()
	items.append_array(town.get("armory_items", []))
	var people: Array = town.get("recruits", []).duplicate()
	people.append_array(Game.company); people.append_array(Mobilization.reserves(Game))
	for u: Unit in people: items.append_array(u.equip.values())
	items.append_array(Game.stash)
	for row: Dictionary in Mobilization.estate_items(Game): items.append(row["item"])
	var ids: Array = items.map(func(it): return it.uid)
	ids.sort()
	return ids

func capture(tree: SceneTree, view: Control, label: String, directory: String) -> void:
	await frames(tree, 4)
	check(view.is_inside_tree(), label + " actual view remains live")
	check(view.size.x >= tree.root.size.x - 1 and view.size.y >= tree.root.size.y - 1, label + " native scene fills actual viewport")
	check((view as MusterView).body.size.x >= 1000, label + " actual army content has readable width")
	if directory == "" or DisplayServer.get_name() == "headless": return
	var path: String = directory.path_join("fresh_muster_" + label + ".png")
	var pixels: Image = tree.root.get_texture().get_image()
	check(pixels.save_png(path) == OK, label + " native desktop capture")
	captures.append({"state":label, "path":path, "width":pixels.get_width(), "height":pixels.get_height()})

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var directory: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): directory = arg.trim_prefix("--report-dir=").replace("\\", "/").simplify_path()
	check(directory == "" or (directory.is_absolute_path() and directory.to_lower().begins_with(PRIVATE_WORK.to_lower())), "private report destination")
	if directory != "":
		check(not DirAccess.dir_exists_absolute(directory), "fresh report directory")
		DirAccess.make_dir_recursive_absolute(directory)
	if fails > 0: return fails
	if DisplayServer.get_name() != "headless":
		tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
		tree.root.position = Vector2i(-20000, -20000)
		tree.root.size = Vector2i(2560, 1440)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 60
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	var generated_us: int = Time.get_ticks_usec()
	var generation: Dictionary = Game.new_game_begin(777)
	check(Game.company.is_empty() and Game.gold == 0 and Food.stock(Game,"meal") == 0, "actual new campaign has no free army, purse or meals")
	var finished: bool = false
	for i: int in 25000:
		finished = Game.new_game_slice(generation,4000)
		if finished: break
		if Time.get_ticks_usec() - generated_us > 90000000: break
		await tree.process_frame
	check(finished, "fresh Normal generation completes")
	if not finished: return fails
	var history: Dictionary = {}
	var history_us: int = Time.get_ticks_usec()
	while CampaignWorld.presim_left(Game) > 0 and Time.get_ticks_usec() - history_us < 90000000:
		CampaignWorld.presim_slice(Game,history,4000)
		await tree.process_frame
	check(CampaignWorld.presim_left(Game) == 0, "one history day completes")
	if CampaignWorld.presim_left(Game) > 0: return fails
	CampaignWorld.presim_finish(Game,0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	var world_ready_ms: float = float(Time.get_ticks_usec() - generated_us) / 1000.0
	check(Game.day == 1.0 and Game.world.get("work",[]).is_empty(), "settled exactly one-day world")
	check(Game.company.is_empty() and Game.gold == 0 and not Game.is_game_over(), "history creates no player field army or defeat")
	var choices: Array = Dynasty.choices(Game)
	choices.sort_custom(func(a,b): return Population.available(Game.world["towns"][a["town_id"]]) > Population.available(Game.world["towns"][b["town_id"]]))
	var tid: String = ""
	for row: Dictionary in choices:
		if str(Game.world["towns"][row["town_id"]]["econ"].get("race","")) == "human": tid = str(row["town_id"]); break
	if tid == "" and not choices.is_empty(): tid = str(choices[0]["town_id"])
	check(tid != "" and Dynasty.select_city(Game,tid), "actual existing house selected")
	if tid == "": return fails
	var town: Dictionary = Game.world["towns"][tid]
	var population_before: int = int(town["econ"]["pop"])
	var coins_before: float = Barge.holdings(Game)
	var items_before: Array = item_ids(town)
	var unchanged: String = fingerprint(town)
	for count: int in [1,100,200]:
		Mobilization.status(Game); Mobilization.quote(Game,tid,count); Mobilization.stand_down_quote(Game,tid)
	check(fingerprint(town) == unchanged, "actual world previews/cancel keep people, stocks, accounts, RNG and UID counters unchanged")
	check(Game.company.is_empty() and Game.daily_wages() == 0 and not Game.is_game_over(), "selected dynasty starts unraised with no field payroll")
	Game.goto("muster",{"town_id":tid,"back":"map"})
	var army: MusterView = (load("res://ui/muster.tscn") as PackedScene).instantiate() as MusterView
	tree.root.add_child(army)
	army.position = Vector2.ZERO
	army.size = Vector2(tree.root.size)
	await capture(tree,army,"unraised",directory)
	var payer: Dictionary = Feudal._payer(Game)
	var funded: int = int(floor(float(payer.get("purse",0.0)) * 0.8))
	check(funded > 0, "generated actual owning house has funds")
	var funding: Dictionary = Mobilization.fund(Game,funded)
	check(bool(funding.get("ok",false)), "explicit actual house-to-army transfer succeeds")
	check(absf(Barge.holdings(Game) - coins_before) < 0.001, "private transfer conserves world coin")
	var started: int = Time.get_ticks_usec()
	var q: Dictionary = Mobilization.quote(Game,tid,100)
	var quote_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	check(bool(q.get("ok",false)) and int(q.get("planned",0)) > 0, "actual generated manpower, kit, meals and funding support muster")
	if not bool(q.get("ok",false)):
		printerr("Fresh muster unavailable: ",q)
		army.queue_free(); await frames(tree); return fails
	await capture(tree,army,"funded",directory)
	started = Time.get_ticks_usec()
	var raised: Dictionary = Mobilization.muster(Game,tid,100,q["review"])
	var raise_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var number: int = int(raised.get("raised",0))
	check(bool(raised.get("ok",false)) and number > 0 and number == Game.company.size(), "real partial/full muster matches actual roster")
	check(int(town["econ"]["pop"]) + number == population_before, "departing native people are removed once from home population")
	check(absf(Barge.holdings(Game) - coins_before) < 0.001, "actual muster payments conserve native world coin")
	check(item_ids(town) == items_before, "actual kit transfers retain original Item IDs with no manufactured equipment")
	var physical: Array = Game.company.duplicate()
	var bodies: Dictionary = {}
	for u: Unit in physical:
		bodies[u.uid] = u.body
		check(Mobilization.manages(Game,u) and u.home_town == tid and Persons.by_uid(People.fam_of(town,u.family),u.uid)[4] == "company", "actual enlisted body belongs to original registered person")
	await capture(tree,army,"raised",directory)
	var request: Dictionary = Mobilization.stand_down_quote(Game,tid)
	started = Time.get_ticks_usec()
	var returned: Dictionary = Mobilization.stand_down(Game,tid,request["review"])
	var return_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	check(bool(returned.get("ok",false)) and int(returned.get("returned",0)) == number, "all actual living people stand down at their home")
	check(Game.company.is_empty() and Game.daily_wages() == 0 and not Game.is_game_over(), "stand-down stops field payroll without ending dynasty")
	check(int(town["econ"]["pop"]) == population_before and item_ids(town) == items_before, "home population and exact kit ownership restore once")
	check(absf(Barge.holdings(Game) - coins_before) < 0.001, "stand-down transfers no private/public coin")
	for u: Unit in physical:
		check(Mobilization.reserves(Game).has(u) and Mobilization.reserve_unit(Game,u.uid) == u and is_same(u.body,bodies[u.uid]), "home reserve retains exact Unit/body/UID")
	await capture(tree,army,"stood_down",directory)
	q = Mobilization.quote(Game,tid,number)
	raised = Mobilization.muster(Game,tid,number,q.get("review",{}))
	check(bool(raised.get("ok",false)) and int(raised.get("raised",0)) == number, "actual same residents can re-raise")
	for u: Unit in physical: check(Game.company.has(u) and is_same(u.body,bodies[u.uid]), "re-raise keeps physical identity")
	returned = Mobilization.stand_down(Game,tid,Mobilization.stand_down_quote(Game,tid)["review"])
	check(bool(returned.get("ok",false)) and int(town["econ"]["pop"]) == population_before, "second return does not duplicate home people")
	army.queue_free(); await frames(tree,4)
	var report: Dictionary = {"version":"0.017","world_size":"normal","seed":777,"history_days":1,"day":Game.day,
		"town_id":tid,"town_name":town["name"],"house":Dynasty.selected(Game).get("house_name",""),"funded_from_actual_house":funded,
		"requested":100,"raised":number,"actual_manpower_and_kit":true,"injected_people_coin_kit":false,
		"quote_ms":quote_ms,"raise_ms":raise_ms,"return_ms":return_ms,"world_ready_ms":world_ready_ms,"total_ms":float(Time.get_ticks_usec()-generated_us)/1000.0,
		"checks":checks,"failures":fails,"captures":captures,"scope":"Actual fresh one-day house/population/coin/gear muster and two physical return/re-raise cycles; dense battle and desktop fit fixtures separate."}
	if directory != "":
		var file: FileAccess = FileAccess.open(directory.path_join("fresh-muster-world.json"),FileAccess.WRITE)
		check(file != null,"private actual-world report opens")
		if file != null: file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	Game._save_pending = false; Game.wait_save()
	print("fresh muster world v017: %d checks, %d failures" % [checks,fails])
	return fails
