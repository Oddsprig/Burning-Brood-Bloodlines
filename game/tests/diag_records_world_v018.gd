extends RefCounted
## Real fresh one-day world and native UI, with no injected economy or people.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
const TABS := ["Overview", "Register", "Businesses", "Census", "Treasury", "Garrison"]
var checks: int = 0
var fails: int = 0
var captures: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL fresh records world: ", message)

func frames(tree: SceneTree, count: int = 4) -> void:
	for i: int in count:
		await tree.process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func fingerprint(town: Dictionary) -> String:
	return JSON.stringify({"town":Game._serialize(town),"dynasty":Game._serialize(Game.world.get("dynasty",{})),
		"mobilization":Game._serialize(Game.world.get("mobilization",{})),"company":Game.company.map(func(u):return u.to_dict()),
		"purse":Game.gold,"day":Game.day,"rng":str(Game.rng.state),"unit_next":Unit._next_uid,"item_next":Item._next_uid},"",true,true).sha256_text()

func capture(tree: SceneTree, view: Control, state: String, directory: String) -> void:
	await frames(tree)
	check(view.is_inside_tree() and view.size.x >= tree.root.size.x-1 and view.size.y >= tree.root.size.y-1,state+" native scene fills viewport")
	if directory == "" or DisplayServer.get_name() == "headless": return
	var pixels: Image = tree.root.get_texture().get_image()
	var path: String = directory.path_join("fresh_records_"+state+".png")
	check(pixels.save_png(path) == OK,state+" actual native PNG saved")
	captures.append({"state":state,"path":path,"sha256":FileAccess.get_sha256(path),"width":pixels.get_width(),"height":pixels.get_height()})

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var directory: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): directory=arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	check(directory=="" or directory.to_lower().begins_with(PRIVATE_WORK.to_lower()),"private report directory")
	if directory != "":
		check(not DirAccess.dir_exists_absolute(directory),"fresh private report directory")
		DirAccess.make_dir_recursive_absolute(directory)
	check(DisplayServer.get_name()!="headless","actual rendered native display")
	if fails>0:return fails
	tree.root.set_flag(Window.FLAG_NO_FOCUS,true)
	tree.root.position=Vector2i(-20000,-20000)
	tree.root.size=Vector2i(2560,1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=60
	WorldGen.gen_size="normal"
	CampaignWorld.presim_span_days=1
	var started: int = Time.get_ticks_usec()
	var generation: Dictionary = Game.new_game_begin(777)
	check(Game.company.is_empty() and Game.gold==0 and Food.stock(Game,"meal")==0,"startup remains unraised without free army coin or meals")
	var generated: bool = false
	for i: int in 25000:
		generated=Game.new_game_slice(generation,4000)
		if generated or Time.get_ticks_usec()-started>90000000:break
		await tree.process_frame
	check(generated,"native Normal generation completed")
	if not generated:return fails
	var history: Dictionary = {}
	while CampaignWorld.presim_left(Game)>0 and Time.get_ticks_usec()-started<120000000:
		CampaignWorld.presim_slice(Game,history,4000)
		await tree.process_frame
	check(CampaignWorld.presim_left(Game)==0,"native one history day completed")
	if CampaignWorld.presim_left(Game)>0:return fails
	CampaignWorld.presim_finish(Game,0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	Game._save_pending=false
	Game.wait_save()
	Game.set_process(false)
	var world_ms: float = float(Time.get_ticks_usec()-started)/1000.0
	check(Game.day==1.0 and Game.world.get("work",[]).is_empty(),"settled EXACT one-day world")
	var choices: Array = Dynasty.choices(Game)
	var tid: String = ""
	for row: Dictionary in choices:
		if Persons.race_of(Game.world["towns"][row["town_id"]]["econ"])=="human":tid=str(row["town_id"]);break
	if tid=="" and not choices.is_empty():tid=str(choices[0]["town_id"])
	check(tid!="" and Dynasty.select_city(Game,tid),"actual existing house selected")
	if tid=="":return fails
	var town: Dictionary = Game.world["towns"][tid]
	var before: String = fingerprint(town)
	Game.goto("res://ui/records.tscn",{"view":"town","id":tid,"tab":"Overview","back":"house"})
	var records: Variant = (load("res://ui/records.tscn") as PackedScene).instantiate()
	tree.root.add_child(records)
	await frames(tree)
	var tab_costs: Dictionary = {}
	for tab: String in TABS:
		var read_start: int = Time.get_ticks_usec()
		records.tab=tab
		records.refresh()
		tab_costs[tab]=float(Time.get_ticks_usec()-read_start)/1000.0
		await capture(tree,records,tab.to_lower(),directory)
		check(records.view=="town" and records.sel==tid and records.tab==tab,tab+" displays actual selected town")
		check(records.list_box.size.x>=850,tab+" has real readable list width beside diagnostics")
		check(fingerprint(town)==before,tab+" reads preserve actual economy/people/kin/RNG/UIDs")
	# A real tracked owner opens the existing native business record.
	if not town["econ"].get("biz",[]).is_empty():
		records.open_business(town,0)
		await capture(tree,records,"business_detail",directory)
		check(not records.stack.is_empty(),"actual native business detail opens")
		check(fingerprint(town)==before,"actual business detail is read-only")
	records.queue_free()
	await frames(tree)
	Game.goto("laws",{"town_id":tid,"back":"house","back_params":{"back":"map"}})
	var laws: Control = (load("res://ui/house_laws.tscn") as PackedScene).instantiate()
	tree.root.add_child(laws)
	await capture(tree,laws,"laws",directory)
	check(fingerprint(town)==before,"actual native Laws/ruler/heir reads preserve the complete ownership fingerprint")
	check(Game.company.is_empty() and Game.gold==0 and Game.daily_wages()==0,"records/Laws never create player troops/pay/army coin")
	laws.queue_free()
	await frames(tree)
	check(captures.size()==8,"six actual records categories, native business detail and Laws captured")
	var report: Dictionary = {"version":ProjectSettings.get_setting("application/config/version"),"world_size":"normal","history_days":1,"seed":777,"day":Game.day,
		"town_id":tid,"town_name":town["name"],"race":Persons.race_of(town["econ"]),"house":Dynasty.selected(Game).get("house_name",""),
		"injected_people_coin_kit":false,"world_ready_ms":world_ms,"tab_build_ms":tab_costs,"captures":captures,"checks":checks,"failures":fails,
		"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x<0,"scope":"Actual fresh one-day native city records, owner detail and Laws; no simulation or law changes. Focused3desktop and performance/log probes are separate."}
	var file: FileAccess = FileAccess.open(directory.path_join("fresh-records-world.json"),FileAccess.WRITE)
	check(file!=null,"actual private records report opens")
	report["checks"]=checks
	report["failures"]=fails
	if file!=null:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("Fresh records world v018: %d checks, %d failures" % [checks,fails])
	return fails
