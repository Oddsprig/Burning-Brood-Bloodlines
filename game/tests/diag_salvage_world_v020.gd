extends RefCounted
## Fresh native one-day world, one population-backed soldier and an existing
## broken equipment piece. Exercises the real finish/world/UI/save boundary.
## The explicit broken flag is a finance fixture, not a claim of simulated combat.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
var checks := 0
var fails := 0
var captures: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL fresh salvage world: ", message)

func frames(tree: SceneTree, count: int = 3) -> void:
	for i in count:
		await tree.process_frame
		await RenderingServer.frame_post_draw

func capture(tree: SceneTree, state: String, directory: String) -> void:
	await frames(tree)
	var path := directory.path_join("salvage_" + state + ".png")
	var image: Image = tree.root.get_texture().get_image()
	check(image.get_size() == Vector2i(2560,1440) and image.save_png(path) == OK, "actual " + state + " capture")
	captures.append({"state":state,"path":path,"sha256":FileAccess.get_sha256(path),"width":2560,"height":1440})

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var directory := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): directory = arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	check(DisplayServer.get_name() != "headless", "actual rendered native engine")
	check(directory.to_lower().begins_with(PRIVATE_WORK.to_lower()) and not DirAccess.dir_exists_absolute(directory), "fresh private report path")
	if fails > 0: return fails
	DirAccess.make_dir_recursive_absolute(directory)
	tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position=Vector2i(-20000,-20000); tree.root.size=Vector2i(2560,1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=60
	WorldGen.gen_size="normal"; CampaignWorld.presim_span_days=1
	var start := Time.get_ticks_usec()
	var generation := Game.new_game_begin(777)
	check(Game.company.is_empty() and Game.gold==0, "new world has unraised army and no army coins")
	while not Game.new_game_slice(generation,4000):
		if Time.get_ticks_usec()-start>90000000: check(false,"bounded generation"); return fails
		await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game)>0:
		if Time.get_ticks_usec()-start>120000000: check(false,"bounded one-day history"); return fails
		CampaignWorld.presim_slice(Game,history,4000); await tree.process_frame
	CampaignWorld.presim_finish(Game,0); Dynasty.prepare_world(Game); Game.new_game_finalize()
	Game._save_pending=false; Game.wait_save(); Game.set_process(false)
	var world_ms := float(Time.get_ticks_usec()-start)/1000.0
	check(Game.day==1.0 and Game.world.get("work",[]).is_empty(),"fresh settled Normal world has exactly one history day")
	var tid := ""
	for choice in Dynasty.choices(Game):
		var town: Dictionary = Game.world["towns"][choice["town_id"]]
		if Persons.race_of(town["econ"])=="human" and not Salvage._market(town).is_empty():
			tid=str(choice["town_id"]);break
	check(tid!="" and Dynasty.select_city(Game,tid),"actual existing human house with an owned market selected")
	if tid=="":return fails
	var home: Dictionary=Game.world["towns"][tid]
	var holdings := Barge.holdings(Game)
	var payer: Dictionary=Feudal._payer(Game)
	var funded := Mobilization.fund(Game,int(floor(float(payer.get("purse",0.0))*0.8)))
	check(funded.get("ok",false),"real private house funds its existing army wallet")
	var quote := Mobilization.quote(Game,tid,1)
	check(quote.get("ok",false) and quote.get("planned",0)>0,"actual population/food/kit support a one-soldier finance fixture")
	if not quote.get("ok",false):return fails
	var raised := Mobilization.muster(Game,tid,1,quote["review"])
	check(raised.get("ok",false) and Game.company.size()==1,"one real resident is enlisted through native muster")
	check(absf(Barge.holdings(Game)-holdings)<0.001,"funding and muster conserve whole native world coin")
	var soldier: Unit=Game.company[0]
	var item: Item=null
	for candidate in soldier.equip.values():
		if candidate is Item and candidate.mat().get("kind","")=="metal" and Goods.table().has("scrap_"+candidate.material):item=candidate;break
	check(item!=null,"existing enrolled soldier owns a counted metal equipment piece")
	if item==null:return fails
	item.broken=true
	var body := soldier.body
	var item_uid := item.uid
	var mass := item.mass()
	var buyer := Salvage.nearest(Game.world,Game.world["party"]["pos"])
	var good := "scrap_"+item.material
	var stock_before := int(buyer["econ"]["stock"].get(good,0))
	var residue_before := float(buyer["econ"].get("scrap_residue_kg",{}).get(item.material,0.0))
	var till_before := Goods.market_gold(buyer)
	var wallet_before := Game.gold
	var cash_before := Barge.holdings(Game)
	var rng_before := Game.rng.state
	var next_item_before := Item._next_uid
	var quoted_price := int(round(mass*Goods.sell_price(buyer,good)))
	var expected_paid := quoted_price if quoted_price>0 and till_before>=quoted_price else 0
	var result := {"winner":0,"player_units":Game.company.duplicate(),"enemy_units":[],"enemy_fallen":[],"enemy_fled":[],"events":[]}
	Game.pending_battle={"seed":9020}
	start=Time.get_ticks_usec();Game.finish_battle(result)
	var finish_ms := float(Time.get_ticks_usec()-start)/1000.0
	var receipt: Dictionary=result.get("salvage_receipt",{})
	check(receipt.get("finalized",false) and receipt.get("rows",[]).size()==1,"real finish publishes one exact broken piece receipt")
	check(int(receipt.get("paid",0))==expected_paid and Game.gold-wallet_before==int(receipt["paid"]),"army receives only an affordable actual buyer payment")
	check(absf(till_before-Goods.market_gold(buyer)-float(receipt["paid"]))<0.001,"same amount leaves actual market till")
	check(absf(Barge.holdings(Game)-cash_before)<0.001,"native finish/world hooks conserve total actual coin")
	var stock_after := int(buyer["econ"]["stock"].get(good,0))
	var residue_after := float(buyer["econ"].get("scrap_residue_kg",{}).get(item.material,0.0))
	check(absf(float(stock_after-stock_before)+residue_after-residue_before-(mass if expected_paid>0 else 0.0))<0.00001,"only paid actual kilograms move once including fractional stock residue")
	check(not soldier.equip.values().has(item) and Game.stash.has(item)==(expected_paid==0) and is_same(soldier.body,body),"original body remains; exact broken piece retires only if paid, otherwise retained")
	check(Game.rng.state==rng_before and Item._next_uid==next_item_before,"settlement creates no gear or campaign RNG draws")
	var stable := JSON.stringify({"wallet":Game.gold,"till":Goods.market_gold(buyer),"stock":stock_after,"residue":residue_after,"stash":Game.stash.size(),"body":body.to_dict(),"battles":soldier.battles})
	Game.finish_battle(result)
	CampaignWorld._battle_result(Game,result)
	check(JSON.stringify({"wallet":Game.gold,"till":Goods.market_gold(buyer),"stock":int(buyer["econ"]["stock"].get(good,0)),"residue":float(buyer["econ"].get("scrap_residue_kg",{}).get(item.material,0.0)),"stash":Game.stash.size(),"body":body.to_dict(),"battles":soldier.battles})==stable,"duplicate finish and campaign reads cannot resell or repay equipment")
	var view: Control=(load("res://battle/aftermath.tscn") as PackedScene).instantiate();tree.root.add_child(view)
	await capture(tree,"summary",directory)
	view.call("toggle_section","loot");await capture(tree,"buyer",directory)
	view.queue_free();view=null;await frames(tree)
	Game.save_game();Game.wait_save()
	var saved: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	var saved_e: Dictionary=saved.get("world",{}).get("towns",{}).get(str(buyer["id"]),{}).get("econ",{})
	check(int(saved_e.get("stock",{}).get(good,-1))==stock_after and absf(float(saved_e.get("scrap_residue_kg",{}).get(item.material,-1.0))-residue_after)<0.00001,"current native disk save retains counted buyer stock/residue")
	var report := {"version":ProjectSettings.get_setting("application/config/version"),"world_size":"normal","history_days":1,"seed":777,"day":Game.day,"town_id":tid,"town_name":home["name"],"world_ready_ms":world_ms,"finish_ms":finish_ms,"real_resident_uid":soldier.uid,"original_item_uid":item_uid,"receipt":receipt,"captures":captures,"checks":checks,"failures":fails,"scope":"Fresh one-day native muster/real broken-item finance fixture through Game.finish_battle and World reconciliation, actual buyer/till/stock/wallet and disk persistence; not a simulated full fight or FPS benchmark."}
	var file := FileAccess.open(directory.path_join("fresh-salvage-world.json"),FileAccess.WRITE)
	check(file!=null,"private actual world report opens");report["checks"]=checks;report["failures"]=fails
	if file!=null:file.store_string(JSON.stringify(report,"\t",true,true));file.close()
	print("Fresh salvage world v020: ",checks," checks, ",fails," failures")
	return fails
