extends RefCounted
## Genuine native market receipts; UI never repeats settlement/result/loot.
const SummaryFixture = preload("res://tests/test_battle_result_summary_v014.gd")
const WINDOWS := [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440)]
var tree: SceneTree
var checks: int = 0
var fails: int = 0
var fit_cases: int = 0
var report_dir: String = ""
var captures: Array = []

class RouteProbe extends Node:
	var path: String = ""
	func show_screen(value: String) -> void: path = value

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL salvage receipts UI: ",reason)

func settle() -> void:
	for _i in 5: await tree.process_frame

static func labels(node: Node) -> String:
	var text: String = (node as Label).text+"\n" if node is Label else ""
	for child: Node in node.get_children(): text += labels(child)
	return text

static func fingerprint(result: Dictionary) -> String:
	return JSON.stringify({"world":Game._save_tree(),"result":Game._serialize(result),"rng":str(Game.rng.state),"unit":Unit._next_uid,"item":Item._next_uid},"",true,true).sha256_text()

func fit_check(fit: RefCounted, viewport: SubViewport, view: Control, size: Vector2i, state: String) -> void:
	fit_cases += 1
	var context: String = "%dx%d %s" % [size.x,size.y,state]
	fit._check(viewport,Vector2(size),"v020 "+context)
	check(view.size.is_equal_approx(Vector2(size)),context+" native results scene fills viewport")
	check(view.frame.get_global_rect().end.x <= size.x-UiKit.diagnostics_lane(size.x)+1,context+" actual diagnostics lane stays free")
	check(view.continue_button.get_global_rect().end.y <= size.y and view.continue_button.size.y >= 48,context+" native Continue stays reachable")
	if view.active_section == "loot":
		var rows: VBoxContainer = view.find_child("LootRows",true,false)
		var detail: PanelContainer = view.sections["loot"]["detail"]
		var scroll_rect: Rect2 = view.body_scroll.get_global_rect()
		for name: String in ["LootPrevious","LootNext"]:
			var button: Button = view.find_child(name,true,false)
			check(button != null and scroll_rect.encloses(button.get_global_rect()),context+" full "+name+" is inside the actual scroll viewport after layout")
		var buyer_header: PanelContainer = view.find_child("SalvageBuyerSummary",true,false)
		check(buyer_header != null and scroll_rect.encloses(buyer_header.get_global_rect()),context+" complete buyer header is visible when the receipt page opens")
		var available: float = detail.size.x-detail.get_theme_stylebox("panel").get_minimum_size().x
		check(rows.size.x >= available-2 and rows.size.x >= 700,context+" receipt column uses full actual detail width")
		for card: Control in rows.get_children():
			if not card.has_meta("salvage_receipt_row"): continue
			check(card.size.x >= rows.size.x-2,context+" receipt card is full width")
			for node: Node in card.find_children("*","",true,false):
				if not node is Label: continue
				var label: Label = node
				check(label.size.x >= card.size.x-50,context+" actual payment story has usable width")
				check(label.get_theme_font("font") == UiTheme.regular_font(),context+" receipt resolves actual bundled body font")
				var surface: Color = (card.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
				check(UiTheme.contrast(label.get_theme_color("font_color"),surface) >= 4.5,context+" payment story uses readable dark-surface contrast")
		check(int(view.detail_stats()["sections"]["loot"]["rows"]) <= 18,context+" at most18 visible result entries")

func capture(viewport: SubViewport, size: Vector2i, state: String) -> void:
	if report_dir == "": return
	for node: Node in viewport.find_children("*","",true,false):
		if node is PerformancePanel: (node as PerformancePanel)._refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path: String = report_dir.path_join("salvage_%dx%d_%s.png" % [size.x,size.y,state])
	var image: Image = viewport.get_texture().get_image()
	check(image != null and image.get_size() == size,"native salvage image dimensions "+state)
	var saved: bool = image != null and image.save_png(path) == OK
	check(saved,"private native salvage PNG "+state)
	captures.append({"path":path,"sha256":FileAccess.get_sha256(path) if saved else "","size":[size.x,size.y],"state":state})

func make_result(fixture: RefCounted, till: float, with_buyer: bool, large: bool = false) -> Dictionary:
	var native: Dictionary = fixture.fixture(till,with_buyer)
	var result: Dictionary = SummaryFixture.fixture(8)
	# Additional genuine native physical pieces exercise paging; no authored payments.
	if large:
		for _i in 24:
			var item: Item = Item.make("arming_sword","bronze",1); item.broken = true
			native["records"].append(Salvage.record(item,"scrap","enemy"))
	var receipt: Dictionary = Salvage.finalize(Game,result,native["records"],native["pos"])
	result["loot_gold"] = int(receipt["paid"]); result["loot_coin"] = 0
	if large:
		var camp_records: Array = []
		for _i in 3:
			var item: Item = Item.make("arming_sword","bronze",1); item.broken = true
			camp_records.append(Salvage.record(item,"scrap","camp"))
		var camp: Dictionary = Salvage.finalize(Game,result,camp_records,native["pos"],"camp_salvage_receipt","camp_hoard")
		result["camp_coin"] = 0; result["camp_sale_paid"] = int(camp["paid"]); result["camp_loot"] = int(camp["paid"])
		result["loot_gold"] += int(camp["paid"])
	result["loot_items"] = Game.stash.duplicate()
	result["fallen_gear"] = 0
	result["supplies_taken"] = {}
	result["preserve_marker"] = {"nested":[1,{"receipt_is_settled":true}]}
	return result

func verify_rows(view: Control, receipts: Array) -> void:
	var actual: Array = (view.sections["loot"]["source"] as Array).slice(int(view.sections["loot"]["page"])*18,(int(view.sections["loot"]["page"])+1)*18)
	var expected: Array = actual.filter(func(row): return row.has("salvage_sale"))
	check(view.receipt_rows_formatted == expected.size(),"only the current visible receipt page is formatted")
	var rows: VBoxContainer = view.find_child("LootRows",true,false)
	var rendered: Array = rows.get_children().filter(func(row): return row.has_meta("salvage_receipt_row"))
	check(rendered.size() == expected.size(),"rendered receipt count equals detached settled page")
	for i in rendered.size():
		var card: Control = rendered[i]
		var sale: Dictionary = card.get_meta("salvage_receipt_row")
		var receipt: Dictionary = card.get_meta("salvage_receipt_context")
		check(sale == expected[i]["salvage_sale"] and receipts.has(receipt) and (receipt["rows"] as Array).has(sale),"row metadata is the actual immutable sale and buyer transaction")
		var text: String = labels(card)
		check(String(sale["item_name"]) in text and String(sale["material_name"]) in text,"actual item/material identity visible")
		check("Paid: %s coins" % RecKit.num(float(sale["paid"])) in text,"actual payment is separate from quoted piece price")
		check("Piece quote: %s coins" % RecKit.num(float(sale["price"])) in text,"actual offered price visible")
		if String(receipt["buyer_town_id"]) != "":
			check(String(receipt["buyer_town_name"]) in text and String(receipt["buyer_business_name"]) in text and String(receipt["buyer_owner_name"]) in text and String(receipt["recipient_name"]) in text,"each piece names its own actual buyer/owner/receiving purse")
		if bool(sale["retained"]):
			check("Unpaid · retained" in text and "company stash" in text and "Paid" not in (card.find_child("SalvageHeading",true,false) as Label).text,"unpaid exact piece is never described as sold/paid")
			check(Game.stash.any(func(item): return item is Item and item.uid == int(sale["item_uid"])),"displayed retained UID remains a real owned Item")
		elif String(sale["destination"]) == "market_stock":
			check("buyer's stock" in text and "Fractional market metal" in text and "Counted stock" in text,"physical mass, counted market stock and fractional metal remain distinct")
		else: check("buyer's inventory" in text,"nonmetal piece displays actual market inventory destination")

func run(scene_tree: SceneTree) -> int:
	tree = scene_tree; await tree.process_frame; Game.wait_save()
	var started: int = Time.get_ticks_usec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report-dir="): report_dir = arg.trim_prefix("--report-dir=").replace("\\","/").simplify_path()
	if report_dir != "":
		check(report_dir.is_absolute_path() and report_dir.to_lower().begins_with("c:/users/bligh/documents/codex/2026-10-10/you/work/v020-ui-render/"),"private salvage report path")
		check(DisplayServer.get_name() != "headless","requested captures use actual native renderer")
		if fails > 0: tree = null; return fails
		check(DirAccess.make_dir_recursive_absolute(report_dir) == OK and not FileAccess.file_exists(report_dir.path_join("salvage-receipts-ui.json")),"fresh private salvage directory")
		if fails > 0: tree = null; return fails
		tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.visible = true
	check(ResourceLoader.exists("res://tests/test_salvage_v020.gd"),"actual settled market fixture exists")
	if fails > 0: tree = null; return fails
	var original: Dictionary = {"world":Game.world,"company":Game.company,"stash":Game.stash,"squads":Game.squads,"gold":Game.gold,"day":Game.day,
		"location":Game.location,"contract":Game.contract,"pending":Game.pending_battle,"result":Game.last_result,"params":Game.screen_params,"main":Game.main,
		"screen":Game._active_screen,"provisions":Game.provisions,"rations":Game.rations,"clock":Game.food_clock,"rng":Game.rng.state,
		"unit":Unit._next_uid,"item":Item._next_uid,"size":tree.root.size,"deploy_rev":Game._deploy_rev,"deploy_key":Game._deploy_key,"deploy_cache":Game._deploy_cache,
		"wg":[WorldGen.W,WorldGen.H,WorldGen.K,WorldGen.TF,WorldGen.KD]}
	Game.world = {}; Game.company = []; Game.stash = []; Game.squads = {}; Game.contract = {}; Game.pending_battle = {}; Game.last_result = {}
	Game.provisions = {"meal":[],"beer":[],"wine":[]}; Game.food_clock = {}; Game.rations = {"food":"normal","drink":"ration"}; Game._deploy_key = []; Game._deploy_cache = []
	var probe := RouteProbe.new(); tree.root.add_child(probe); Game.main = probe
	var fixture: RefCounted = load("res://tests/test_salvage_v020.gd").new()
	var fit: RefCounted = load("res://tests/test_ui_fit.gd").new(); fit.tree = tree
	var orphan_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for size: Vector2i in WINDOWS:
		if report_dir != "": tree.root.size = size
		for scenario: String in ["funded","insufficient_till","no_buyer"]:
			var result: Dictionary = make_result(fixture,100000.0 if scenario == "funded" else 0.0,scenario != "no_buyer",scenario == "funded")
			Game.last_result = result; Game._active_screen = "aftermath"
			var receipt: Dictionary = result["salvage_receipt"]
			var receipts: Array = result["salvage_receipts"]
			var before: String = fingerprint(result)
			var viewport := SubViewport.new(); viewport.size = size
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if report_dir != "" else SubViewport.UPDATE_DISABLED
			tree.root.add_child(viewport)
			var layer := CanvasLayer.new(); layer.layer = 100; viewport.add_child(layer)
			var performance := PerformancePanel.new(); performance.setup(Perf); layer.add_child(performance)
			var view: Control = (load("res://battle/aftermath.tscn") as PackedScene).instantiate(); viewport.add_child(view); await settle()
			check(view.active_section == "" and view.receipt_rows_formatted == 0 and view.find_child("SalvageBuyerSummary",true,false) == null,"default results remain compact with no hidden receipt rows")
			for key: String in ["fallen","wounded","lessons","loot","log"]:
				var toggle: Button = view.find_child(key.capitalize()+"Toggle",true,false)
				check(view.body_scroll.get_global_rect().encloses(toggle.get_global_rect()),"closed "+key+" toggle stays visible at "+str(size))
			if scenario == "funded":
				check(int(receipt["paid"]) > 0 and (receipt["rows"] as Array).size() > 18,"genuine funded transaction supplies a multi-page native receipt")
				fit_check(fit,viewport,view,size,"closed"); await capture(viewport,size,"closed")
			view.toggle_section("loot"); await settle()
			check(view.active_section == "loot" and view.find_child("SalvageBuyerSummary",true,false) != null,"Loot expands actual settled receipt")
			var buyer: Label = view.find_child("SalvageBuyer",true,false)
			var payment: Label = view.find_child("SalvagePayment",true,false)
			var total_paid: float = 0.0; var total_retained: int = 0; var total_rows: int = 0
			for transaction: Dictionary in receipts:
				total_paid += float(transaction["paid"]); total_retained += int(transaction["retained_items"]); total_rows += (transaction["rows"] as Array).size()
			check("Payment received: %s coins" % RecKit.num(total_paid) in payment.text and "Retained: %d pieces" % total_retained in payment.text,"header reads all actual payments and retained counts")
			check((view.sections["loot"]["source"] as Array).filter(func(row): return row.has("salvage_sale")).size() == total_rows,"primary receipt alias is not duplicated when reading all transactions")
			if scenario == "no_buyer":
				check(String(receipt["buyer_town_id"]) == "" and "No market buyer" in buyer.text and view.find_child("SalvagePaymentPath",true,false) == null,"no buyer invents no market/payer path")
			else:
				check(String(receipt["buyer_town_name"]) in buyer.text and String(receipt["buyer_business_name"]) in buyer.text and String(receipt["buyer_owner_name"]) in buyer.text,"actual settlement/business/owner named")
				if receipts.size() == 1:
					var path: Label = view.find_child("SalvagePaymentPath",true,false)
					check("market till → Army purse" in path.text and RecKit.num(float(receipt["till_before"])) in path.text and RecKit.num(float(receipt["till_after"])) in path.text,"actual payer and receiving purse shown")
				else: check(view.find_child("SalvageTransactions",true,false) != null and "2 transactions" in payment.text,"battle/camp transactions remain visibly separate")
			if scenario == "funded":
				var source: Array = view.sections["loot"]["source"]
				check(source.any(func(row): return String(row.get("text","")).begins_with("Camp cash taken: 0")) and source.any(func(row): return String(row.get("text","")).begins_with("Camp market payment received:")),"actual camp cash and market payment are distinct original receipt fields")
			if scenario != "funded": check(int(receipt["paid"]) == 0 and int(receipt["retained_items"]) > 0,"unfunded/no-buyer UI receives genuinely unpaid retained Items")
			verify_rows(view,receipts)
			fit_check(fit,viewport,view,size,scenario); await capture(viewport,size,scenario)
			if scenario == "funded":
				var first: Array = (view.sections["loot"]["source"] as Array).slice(0,18)
				view.turn_page("loot",1); await settle()
				check(int(view.sections["loot"]["page"]) == 1 and view.detail_stats()["sections"]["loot"]["rows"] <= 18,"Next shows one bounded later native receipt page")
				var later: Array = (view.sections["loot"]["source"] as Array).slice(18,36)
				check(later.any(func(row): return row.has("salvage_sale") and not first.has(row)),"later page exposes actual previously unseen sales")
				verify_rows(view,receipts)
				fit_check(fit,viewport,view,size,"receipt_page2"); await capture(viewport,size,"receipt_page2")
				var camp_index: int = 0
				for row_index in (view.sections["loot"]["source"] as Array).size():
					var row: Dictionary = view.sections["loot"]["source"][row_index]
					if String(row.get("salvage_context",{}).get("transaction","")) == "camp_hoard": camp_index = row_index; break
				var camp_page: int = int(camp_index/18)
				view.turn_page("loot",camp_page-int(view.sections["loot"]["page"])); await settle()
				verify_rows(view,receipts)
				check("Camp buyer:" in labels(view.find_child("LootRows",true,false)),"camp page exposes actual camp buyer/payment independently")
				fit_check(fit,viewport,view,size,"camp_receipt_page"); await capture(viewport,size,"camp_receipt_page")
			check(fingerprint(result) == before,"open/paging never reruns sale/result/growth or mutates world/stock/coin/body/RNG/UIDs")
			view.toggle_section("loot"); await settle()
			check(view.receipt_rows_formatted == 0 and view.sections["loot"]["source"].is_empty() and view.find_child("SalvageBuyerSummary",true,false) == null,"closing releases rows and derived receipt source")
			check(fingerprint(result) == before,"closing detail preserves complete native receipt/result")
			view.continue_button.pressed.emit()
			check(Game.last_result.is_empty() and Game._active_screen == "map" and probe.path == Game.SCREENS["map"],"Continue releases native result and routes to map")
			viewport.queue_free(); view = null; viewport = null; performance = null; layer = null; result = {}; receipt = {}; receipts = []; await settle()
	Game.world = original["world"]; Game.company = original["company"]; Game.stash = original["stash"]; Game.squads = original["squads"]
	Game.gold = original["gold"]; Game.day = original["day"]; Game.location = original["location"]; Game.contract = original["contract"]
	Game.pending_battle = original["pending"]; Game.last_result = original["result"]; Game.screen_params = original["params"]; Game.main = original["main"]; Game._active_screen = original["screen"]
	Game.provisions = original["provisions"]; Game.rations = original["rations"]; Game.food_clock = original["clock"]; Game.rng.state = original["rng"]
	Game._deploy_rev = original["deploy_rev"]; Game._deploy_key = original["deploy_key"]; Game._deploy_cache = original["deploy_cache"]
	Unit._next_uid = original["unit"]; Item._next_uid = original["item"]
	WorldGen.W = original["wg"][0]; WorldGen.H = original["wg"][1]; WorldGen.K = original["wg"][2]; WorldGen.TF = original["wg"][3]; WorldGen.KD = original["wg"][4]
	if report_dir != "": tree.root.size = original["size"]
	probe.queue_free(); probe = null; fixture = null; original = {}
	var fit_failures: int = int(fit.fails); fit.tree = null; fit = null; await settle()
	check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_before,"receipt result controls leave no new orphan nodes")
	if report_dir != "":
		check(captures.size() == 18,"six receipt/default states captured at three actual desktop sizes")
		var file: FileAccess = FileAccess.open(report_dir.path_join("salvage-receipts-ui.json"),FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"checks":checks,"failures":fails+fit_failures,"desktop_fit_cases":fit_cases,"captures":captures,"duration_us":Time.get_ticks_usec()-started,
				"sizes":[[1280,720],[1920,1080],[2560,1440]],"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x<0,"no_phone_qa":true,"performance_panel":true,"actual_market_receipts":true},"\t",true,true)); file.close()
		else: check(false,"private salvage report writable")
	print("Salvage receipts UI v020: ",checks," assertions, ",fit_cases," desktop fit cases; failures=",fails+fit_failures)
	tree = null
	return fails+fit_failures
