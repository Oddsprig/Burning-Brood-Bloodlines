extends "res://tests/diag_battle_render_v016.gd"
## Explicit native stress forces, never campaign recruitment/save/result handback.
const WARM_SECONDS := 4.0
const MEASURE_SECONDS := 18.0

func observer_digest(sim: BattleSim, measurements: Array, label: String) -> String:
	var started: int = Time.get_ticks_usec()
	var result: String = digest(sim)
	var elapsed: int = Time.get_ticks_usec()-started
	measurements.append({"phase":label,"elapsed_ms":float(elapsed)/1000.0})
	Perf.record_us("QA state fingerprints",elapsed)
	return result

func ui_action_window(tree: SceneTree, measurements: Array, label: String, action: Callable) -> void:
	var started: int = Time.get_ticks_usec()
	action.call()
	var call_ms: float = float(Time.get_ticks_usec()-started)/1000.0
	await tree.process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var elapsed_ms: float = float(Time.get_ticks_usec()-started)/1000.0
	measurements.append({"action":label,"call_ms":call_ms,"through_draw_ms":elapsed_ms})
	check(elapsed_ms <= 150.0,"actual log "+label+" through native draw stays<=150ms")

class DragonContactBattle extends "res://battle/battle.gd":
	var active_seconds: float = 0.0
	var expected_ticks: float = 0.0
	var dragon_attacks: int = 0
	var dragon_hits: int = 0
	func _do_tick() -> void:
		super._do_tick()
		# Count fresh native emissions, not the bounded presentation event tail.
		for event: Dictionary in sim.new_events:
			var actor: int = int(event.get("actor",-1))
			if actor < 0 or actor >= sim.fighters.size() or sim.fighters[actor].unit.dragon_uid == "": continue
			if event.get("type","") == "attack": dragon_attacks += 1
			if event.get("type","") == "hit": dragon_hits += 1
	func battle_opts(pb: Dictionary,n0: int,n1: int) -> Dictionary:
		var opts: Dictionary = super.battle_opts(pb,n0,n1)
		opts["combat_journal"] = true
		var rows: int = int(opts["h"])-2; var middle: int = int(opts["w"])/2
		for side: int in 2:
			var cells: Array = []
			for i: int in n0 if side == 0 else n1:
				cells.append(Vector2i(middle-1-i/rows if side == 0 else middle+i/rows,1+i%rows))
			# The actual dragon replaces a front-row humanoid's cell; move that
			# person into the vacated rear cell, preserving native occupancy.
			var front: int = mini(cells.size()-2,int(rows/2))
			var previous: Vector2i = cells[front]; cells[front] = cells[-1]; cells[-1] = previous
			opts["cells%d" % side] = cells
		return opts
	func _process_battle(delta: float) -> void:
		if sim != null and not sim.is_over() and not paused:
			active_seconds += delta
			expected_ticks += delta*TICKS_PER_SEC*speed
		super._process_battle(delta)
	func finish() -> void:
		pass # No Game.finish_battle, loot, growth or campaign handback in stress QA.

func run(tree: SceneTree) -> int:
	await tree.process_frame; Game.wait_save()
	var report_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=").replace("\\","/").simplify_path()
	check(report_path.to_lower().begins_with(PRIVATE_WORK.to_lower()) and not FileAccess.file_exists(report_path),"fresh private dragon render report path")
	check(DisplayServer.get_name() != "headless","actual native display renderer")
	check(not bool(Game.setting("battle_event_slowmo")),"actual automatic slow motion remainsOFF")
	if fails > 0: return fails
	var old: Dictionary = {"world":Game.world,"company":Game.company,"squads":Game.squads,"pending":Game.pending_battle,"result":Game.last_result,"day":Game.day,"gold":Game.gold,"location":Game.location,"rng":Game.rng.state,"unit":Unit._next_uid,"item":Item._next_uid,"deploy_rev":Game._deploy_rev,"deploy_key":Game._deploy_key,"deploy_cache":Game._deploy_cache,"screen":Game._active_screen,"fps":Engine.max_fps}
	tree.root.set_flag(Window.FLAG_NO_FOCUS,true); tree.root.position = Vector2i(-20000,-20000); tree.root.size = Vector2i(2560,1440); tree.root.visible = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps = 60
	var fixture: RefCounted = load("res://tests/test_dragon_bond_v021.gd").new(); fixture.fixture(); DragonCombat.prepare_world(Game)
	var dragon0: Unit = Game.world["dragons"]["combat_units"][fixture.dragon_uid]
	var dragon1: Unit = Game.world["dragons"]["combat_units"][fixture.other_dragon_uid]
	check(DragonCombat.is_dragon_unit(Game,dragon0) and DragonCombat.is_dragon_unit(Game,dragon1) and dragon0 != dragon1,"two actual distinct persistent registry holders")
	var random := RandomNumberGenerator.new(); random.seed = 22022
	Game.company = Factory.make_warband(random,"middle_kingdom",200)
	var enemies: Array = Factory.make_warband(random,"orc_horde",200)
	fixture_commands(Game.company); fixture_commands(enemies)
	enemies.append(dragon1)
	Game.pending_battle = {"enemy":enemies,"allies":[],"dragon_units":[dragon0],"seed":22022,"terrain":"grassland","map":"large"}
	Game.last_result = {}; Game._active_screen = "battle"; Game.invalidate_deploy()
	var setup_started: int = Time.get_ticks_usec()
	var battle := DragonContactBattle.new(); tree.root.add_child(battle)
	var layer := CanvasLayer.new(); layer.layer = 100; tree.root.add_child(layer)
	var panel := PerformancePanel.new(); panel.setup(Perf); layer.add_child(panel)
	battle.set_speed(1.0)
	check(battle.sim.fighters.size() == 402,"200humanoids and one native dragon per side")
	var dragon_indices: Array[int] = []
	for fighter: Fighter in battle.sim.fighters:
		if DragonCombat.is_dragon_unit(Game,fighter.unit): dragon_indices.append(fighter.idx)
	check(dragon_indices.size() == 2 and battle.views[dragon_indices[0]].doll is DragonView and battle.views[dragon_indices[1]].doll is DragonView,"actual native actors use coherent GPU view")
	var setup_ms: float = float(Time.get_ticks_usec()-setup_started)/1000.0
	var warm_start: int = Time.get_ticks_usec(); var cold: Array = []; var previous: int = warm_start
	while float(Time.get_ticks_usec()-warm_start)/1000000.0 < WARM_SECONDS:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec(); cold.append(float(now-previous)/1000.0); previous = now
	var samples: Array = []; var frames: Array = []; var stalled: int = 0; var max_draw_calls: int = 0
	var memory_min: int = 9223372036854775807; var memory_max: int = 0
	var phase: int = 0; var active_frames: int = 0; var log_pure: bool = false; var filtered_pure: bool = false
	var start: int = Time.get_ticks_usec(); previous = start
	while float(Time.get_ticks_usec()-start)/1000000.0 < MEASURE_SECONDS:
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec(); var elapsed: float = float(now-start)/1000000.0
		var frame_ms: float = float(now-previous)/1000.0; frames.append(frame_ms); previous = now
		if frame_ms > 150.0: stalled += 1
		if not battle.sim.is_over(): active_frames += 1
		max_draw_calls = maxi(max_draw_calls,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		var memory: int = int(Performance.get_monitor(Performance.MEMORY_STATIC)); memory_min = mini(memory_min,memory); memory_max = maxi(memory_max,memory)
		if phase == 0 and elapsed >= 3.0:
			battle.cam_zoom *= 1.25; battle.cam_pos = battle.views[dragon_indices[0]].body_center(); phase = 1
		elif phase == 1 and elapsed >= 10.0:
			battle._fit_camera(); phase = 2
		if samples.size() < 6 and elapsed >= float(samples.size())*3.0:
			var visuals: Array = []
			for index: int in dragon_indices: visuals.append((battle.views[index].doll as DragonView).cache_stats())
			samples.append({"seconds":elapsed,"tick":battle.sim.tick,"engine_static_bytes":memory,"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"dragon_views":visuals})
	# Freeze the dense measurement receipt before observer copies or UI work.
	# No full-state digest or native menu callback ran in this18-second window.
	var measured_seconds: float = float(Time.get_ticks_usec()-start)/1000000.0
	var measured_tick: int = battle.sim.tick
	var measured_accumulator: float = battle._acc
	var measured_expected: float = battle.expected_ticks
	var measured_active_seconds: float = battle.active_seconds
	var native_delivery: bool = absf(float(measured_tick)+measured_accumulator-measured_expected) <= 1.01
	var mean: float = 0.0
	for ms: float in frames: mean += ms
	mean /= maxf(1,frames.size())
	var fps: float = 1000.0/maxf(0.001,mean); var p95: float = percentile(frames,0.95); var worst: float = percentile(frames,1)
	var gate: bool = fps >= 30 and p95 <= 50 and worst <= 150
	check(frames.size() > 100 and max_draw_calls > 0,"actual native rendered frames measured")
	check(gate,"native402actor recovery floor30FPS/p95<=50/worst<=150ms")
	check(active_frames >= int(frames.size()*0.9),"measurement is actual native combat rather than idle end screen")
	check(phase == 2,"native dense pan and recenter both exercised")
	# Fingerprint copies are observer work. Pause without a frame advancing,
	# copy before/after outside timed UI windows, and restore running immediately
	# before the real open command so native pause/close restoration is exercised.
	var observer_times: Array = []; var ui_times: Array = []
	battle.paused = true
	var paused_state: String = observer_digest(battle.sim,observer_times,"before_whole_log")
	# Let the paused frame consume observer elapsed time. Otherwise the next
	# real close/resume would inherit a synthetic long Engine.delta backlog.
	await tree.process_frame; await RenderingServer.frame_post_draw
	battle.paused = false
	await ui_action_window(tree,ui_times,"open_whole",func(): battle.open_combat_log(-1))
	var browser: CombatLogBrowser = battle._log_overlay.find_child("BattleLogBrowser",true,false)
	await ui_action_window(tree,ui_times,"first_page",func(): browser._set_page(0))
	await ui_action_window(tree,ui_times,"last_page",func(): browser._set_page(maxi(0,int(ceil(float(browser.journal.count())/18))-1)))
	await ui_action_window(tree,ui_times,"return_first_page",func(): browser._set_page(0))
	log_pure = observer_digest(battle.sim,observer_times,"after_whole_log") == paused_state
	await tree.process_frame; await RenderingServer.frame_post_draw
	await ui_action_window(tree,ui_times,"filter_actual_dragon",func(): browser.set_participant(dragon_indices[0]))
	check(not browser._page_rows.is_empty(),"actual dragon filter has genuine recorded outcomes")
	if not browser._page_rows.is_empty():
		await ui_action_window(tree,ui_times,"expand_actual_detail",func(): browser._toggle_row(int(browser._page_rows[0]["seq"])))
	filtered_pure = observer_digest(battle.sim,observer_times,"after_filtered_detail") == paused_state and browser.participant == dragon_indices[0] and browser.detail_stats()["rows"] <= 18
	await tree.process_frame; await RenderingServer.frame_post_draw
	await ui_action_window(tree,ui_times,"close_restore_running",func(): battle.close_combat_log())
	var ui_gate: bool = ui_times.all(func(row: Dictionary): return float(row["through_draw_ms"]) <= 150.0)
	check(log_pure and filtered_pure,"paused whole/actual dragon individual log/detail preserves full native state/RNG")
	check(not battle.paused and battle.speed == 1.0 and battle._slowmo == 0,"pause restores native1x without automatic slowmo")
	check(native_delivery,"native1x tick budget delivered within one tick")
	var events: Dictionary = {}; var dragon_attacks: int = battle.dragon_attacks; var dragon_hits: int = battle.dragon_hits
	for event: Dictionary in battle.sim.events:
		var kind: String = String(event.get("type","unknown")); events[kind] = int(events.get(kind,0))+1
	check(dragon_attacks > 0 and dragon_hits > 0,"actual native dragon contact emitted attacks and hits")
	var journal: Dictionary = battle.sim.combat_journal.stats()
	check(bool(journal["complete"]) and int(journal["records"]) > 0,"current full native journal captures actual fight honestly")
	var visual_stats: Array = []
	for index: int in dragon_indices:
		var stats: Dictionary = battle.views[index].doll.cache_stats(); visual_stats.append(stats)
		check(int(stats["models"]) <= DragonView.MODEL_LIMIT,"native posed GPU model cache bounded per dragon")
	var screenshot: String = report_path.trim_suffix(".json")+".png"
	panel._refresh(); await RenderingServer.frame_post_draw
	var image: Image = tree.root.get_texture().get_image(); check(image != null and image.get_size() == Vector2i(2560,1440) and image.save_png(screenshot) == OK,"private actual battle viewport PNG")
	var report: Dictionary = {"version":"0.022","fixture":"Explicit native Factory stress forces; no campaign reconciliation, save or result/growth handback","resolution":[2560,1440],"force_sizes":[201,201],"humanoid_sizes":[200,200],"dragons_per_side":1,"close_contact":true,"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),"offscreen":tree.root.position.x < -10000,"performance_panel":true,"journal_enabled":true,"combat_journal":journal,"paused_log_pure":log_pure,"filtered_log_pure":filtered_pure,"native_tick_delivery":native_delivery,"chosen_speed":1.0,"expected_native_ticks":battle.expected_ticks,"sim_tick":battle.sim.tick,"active_seconds":battle.active_seconds,"active_frames":active_frames,"warmup_seconds":WARM_SECONDS,"measured_seconds":float(Time.get_ticks_usec()-start)/1000000.0,"setup_ms":setup_ms,"cold_frames":cold,"frame_samples_ms":frames,"warm_fps":fps,"mean_frame_ms":mean,"p95_ms":p95,"worst_ms":worst,"frames_over150_ms":stalled,"recovery_gate":gate,"max_draw_calls":max_draw_calls,"engine_static_min_bytes":memory_min,"engine_static_max_bytes":memory_max,"memory_note":"Godot debug static monitor, not OS working/private RAM or unique texture accounting","paperdoll_cache":Paperdoll.cache_stats(),"dragon_views":visual_stats,"samples":samples,"event_counts":events,"dragon_attacks":dragon_attacks,"dragon_hits":dragon_hits,"diagnostics":Perf.snapshot(),"screenshot":screenshot,"screenshot_sha256":FileAccess.get_sha256(screenshot),"checks":checks,"fails":fails}
	var file: FileAccess = FileAccess.open(report_path,FileAccess.WRITE); check(file != null,"private bounded native report writable")
	report["measured_seconds"] = measured_seconds
	report["sim_tick"] = measured_tick
	report["tick_accumulator"] = measured_accumulator
	report["expected_native_ticks"] = measured_expected
	report["active_seconds"] = measured_active_seconds
	report["post_ui_sim_tick"] = battle.sim.tick
	report["dense_recovery_gate"] = gate
	report["ui_action_gate"] = ui_gate
	report["recovery_gate"] = gate and ui_gate
	report["ui_action_windows"] = ui_times
	report["observer_fingerprint_ms"] = observer_times
	report["measurement_note"] = "Dense18-second render samples exclude full-state observer fingerprints. Actual log open/page/filter/detail/close is separately gated through native draw at150ms per action; fingerprints before/after remain outside those UI action windows."
	report["checks"] = checks; report["fails"] = fails
	if file != null: file.store_string(JSON.stringify(report,"\t",true,true)); file.close()
	battle.queue_free(); layer.queue_free(); battle = null; layer = null; panel = null
	for _i in 5: await tree.process_frame
	Game.world = old["world"]; Game.company = old["company"]; Game.squads = old["squads"]; Game.pending_battle = old["pending"]; Game.last_result = old["result"]; Game.day = old["day"]; Game.gold = old["gold"]; Game.location = old["location"]
	Game.rng.state = old["rng"]; Unit._next_uid = old["unit"]; Item._next_uid = old["item"]; Game._deploy_rev = old["deploy_rev"]; Game._deploy_key = old["deploy_key"]; Game._deploy_cache = old["deploy_cache"]; Game._active_screen = old["screen"]
	Engine.max_fps = old["fps"]; fixture = null; dragon0 = null; dragon1 = null; enemies = []; DragonRigArt.clear_texture_cache(); Paperdoll.clear_cache()
	print("Dragon rendered v022: ",checks," checks, ",fails," failures; ",fps," FPS p95 ",p95," ms worst ",worst," ms")
	return fails
