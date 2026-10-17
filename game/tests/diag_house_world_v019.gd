extends RefCounted
## Actual fresh one-day selection, persisted customization and native House/Laws.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
var checks := 0
var fails := 0
var captures: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL fresh house world: ", message)

func frames(tree: SceneTree, count: int = 4) -> void:
	for i in count:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func fingerprint() -> String:
	return JSON.stringify({"state":Game._save_tree(),"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid},"",true,true).sha256_text()

func ownership() -> String:
	return JSON.stringify({"towns":Game._serialize(Game.world.get("towns",{})),"factions":Game._serialize(Game.world.get("factions",{})),
		"bands":Game._serialize(Game.world.get("warbands",{})),"mobilization":Game._serialize(Game.world.get("mobilization",{})),
		"company":Game._serialize(Game.company),"stash":Game._serialize(Game.stash),"gold":Game.gold,"provisions":Game.provisions,
		"day":Game.day,"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid},"",true,true).sha256_text()

func capture(tree: SceneTree, state: String, directory: String) -> void:
	await frames(tree)
	var image: Image = tree.root.get_texture().get_image()
	var path := directory.path_join("fresh_house_"+state+".png")
	check(image.get_size()==Vector2i(2560,1440) and image.save_png(path)==OK,"actual native "+state+" capture")
	captures.append({"state":state,"path":path,"sha256":FileAccess.get_sha256(path),"width":2560,"height":1440})

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): directory=arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	check(DisplayServer.get_name()!="headless","actual rendered engine")
	check(directory.to_lower().begins_with(PRIVATE_WORK.to_lower()) and not DirAccess.dir_exists_absolute(directory),"fresh private evidence directory")
	if fails>0:return fails
	DirAccess.make_dir_recursive_absolute(directory)
	tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position=Vector2i(-20000,-20000); tree.root.size=Vector2i(2560,1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=60
	WorldGen.gen_size="normal"; CampaignWorld.presim_span_days=1
	var started := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	check(Game.company.is_empty() and Game.gold==0 and Food.stock(Game,"meal")==0,"fresh start remains unraised with no army purse/food")
	var generated := false
	while Time.get_ticks_usec()-started<90000000:
		generated=Game.new_game_slice(generation,4000)
		if generated:break
		await tree.process_frame
	check(generated,"native Normal generation completed")
	if not generated:return fails
	var history := {}
	while CampaignWorld.presim_left(Game)>0 and Time.get_ticks_usec()-started<120000000:
		CampaignWorld.presim_slice(Game,history,4000); await tree.process_frame
	check(CampaignWorld.presim_left(Game)==0,"exact one-day native history completed")
	if CampaignWorld.presim_left(Game)>0:return fails
	CampaignWorld.presim_finish(Game,0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	Game._save_pending=false; Game.wait_save(); Game.set_process(false)
	var world_ms := float(Time.get_ticks_usec()-started)/1000.0
	check(Game.day==1.0 and Game.world.get("work",[]).is_empty(),"settled fresh world at day1")
	var tid := ""; var pick: Dictionary = {}; var local_houses: Array = []
	for settlement in HouseOnboarding.settlements(Game):
		if Persons.race_of(Game.world["towns"][settlement["town_id"]]["econ"])!="human":continue
		var possible: Array = HouseOnboarding.houses(Game,str(settlement["town_id"]))
		for house in possible:
			if not house["holds_office"]:tid=str(settlement["town_id"]);pick=house;local_houses=possible;break
		if tid!="":break
	check(tid!="" and local_houses.size()>8,"actual human settlement has ordinary tracked houses and native pagination")
	if tid=="":return fails
	var town: Dictionary = Game.world["towns"][tid]
	var before := fingerprint(); var owned := ownership()
	Game.goto("house_select")
	var chooser: HouseSelectView = (load("res://ui/house_select.tscn") as PackedScene).instantiate()
	tree.root.add_child(chooser)
	var layer := CanvasLayer.new(); layer.layer=100; tree.root.add_child(layer)
	var panel := PerformancePanel.new(); panel.setup(Perf); layer.add_child(panel)
	await capture(tree,"settlements",directory)
	chooser.select_settlement(tid)
	check(chooser.map_view.marker_at(chooser.map_view.position_for(town["pos"]))==tid,"actual settlement marker resolves native world coordinates")
	chooser.next_stage(); await capture(tree,"local_houses",directory)
	check(chooser.stage==1 and chooser.map_view.selected_town==tid and chooser.house_rows.size()==local_houses.size(),"native local houses and matching map highlight")
	check(chooser.list.find_children("LocalHouseRow","Button",true,false).size()<=HouseSelectView.PAGE_SIZE,"native house rows stay bounded")
	chooser.turn_page(1);await frames(tree);check(chooser.page_index==1,"actual native house page2 reachable")
	chooser.select_house(str(pick["household_uid"]));chooser.next_stage();await frames(tree)
	check(chooser.stage==2 and chooser.name_input!=null,"real Customize House controls reached")
	chooser.name_input.text="River Lantern";chooser.name_input.text_changed.emit(chooser.name_input.text)
	chooser.emblem_input.select(2);chooser.emblem_input.item_selected.emit(2)
	chooser.primary_input.select(3);chooser.primary_input.item_selected.emit(3)
	chooser.secondary_input.select(1);chooser.secondary_input.item_selected.emit(1)
	await capture(tree,"customize",directory)
	chooser.next_stage();await capture(tree,"review",directory)
	check(chooser.stage==3 and chooser.next_button.text=="Begin","explicit review before Begin")
	check(chooser.review.get("leader_uid","")==pick["leader_uid"] and not chooser.review["holds_office"],"review keeps actual ordinary-house identity and role")
	check(fingerprint()==before,"all native previews/pages/typed customization preserve entire world/people/coin/party/RNG/UIDs")
	var begin_start := Time.get_ticks_usec()
	var begun: Dictionary = chooser.begin_review()
	var begin_ms := float(Time.get_ticks_usec()-begin_start)/1000.0
	check(begun.get("ok",false) and Game._active_screen=="house","explicit Begin selects the reviewed native house")
	Game.wait_save();await frames(tree)
	check(ownership()==owned,"Begin preserves all native town/faction/band/household accounts, bodies/items/population and RNG/UIDs")
	check(Game.location==tid and Game.world["party"]["pos"].distance_to(town["pos"])<=28.0,"Begin alone moves the existing party to chosen settlement")
	check(not Feudal.can_act(Game,tid) and not Feudal.governance_preview(Game,tid,"tax",0.1).get("ok",false),"ordinary house cannot command settlement taxes or public forces")
	check(Game.company.is_empty() and Game.gold==0 and Game.daily_wages()==0,"Begin does not raise a free army or payroll")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	var style: Dictionary = Game.world["player_house"]["customization"]
	check(saved.get("world",{}).get("player_house",{}).get("customization",{})==style and style["display_name"]=="River Lantern" and style["emblem"]=="wolf","real native disk save retains chosen display name/emblem/banner colours")
	check(People.fam_of(town,int(pick["family_id"]))["name"]==pick["native_house_name"],"custom display name preserves the native fiscal owner's name")
	chooser.queue_free();chooser=null;await frames(tree)
	var selected_before := fingerprint()
	Game.goto("house",{"back":"map"})
	var house_view: Control=(load("res://ui/house.tscn") as PackedScene).instantiate();tree.root.add_child(house_view)
	await capture(tree,"house",directory)
	check(house_view.find_child("HouseStandard",true,false)!=null,"actual House displays saved heraldry")
	house_view.queue_free();house_view=null;await frames(tree)
	Game.goto("laws",{"town_id":tid,"back":"house","back_params":{"back":"map"}})
	var laws: HouseLaws=(load("res://ui/house_laws.tscn") as PackedScene).instantiate();tree.root.add_child(laws)
	await capture(tree,"laws",directory)
	check(laws.data.get("household_view",false) and laws.data["ruler"].get("person_uid","")==pick["leader_uid"] and laws.data["house_name"]=="River Lantern","actual Laws belongs to selected ordinary house and its native leader")
	check(fingerprint()==selected_before,"selected House/Laws reads preserve complete native state")
	laws.queue_free();laws=null;await frames(tree);layer.queue_free();panel=null;layer=null;await frames(tree)
	check(captures.size()==6,"six actual fresh-world selection/House/Laws captures")
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"world_size":"normal","history_days":1,"seed":777,"day":Game.day,
		"town_id":tid,"town_name":town["name"],"household_uid":pick["household_uid"],"local_house_count":local_houses.size(),"selection_kind":Game.world["player_house"]["selection_kind"],
		"world_ready_ms":world_ms,"begin_ms":begin_ms,"injected_people_coin_kit":false,"performance_panel":true,"captures":captures,"checks":checks,"failures":fails,
		"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x<0,"scope":"Actual fresh one-day local-house selection, pure previews, real private ownership, native disk persistence and House/Laws; separate scoped desktop/performance probes."}
	var file := FileAccess.open(directory.path_join("fresh-house-world.json"),FileAccess.WRITE)
	check(file!=null,"private fresh-world report opens");report["checks"]=checks;report["failures"]=fails
	if file!=null:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("Fresh house world v019: ",checks," checks, ",fails," failures")
	return fails
