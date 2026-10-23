extends RefCounted
## v014 actual 2560x1440 Windows/OpenGL battle frames, automatic slow motion OFF.
## A native Factory force fixture controls army size; it is never saved or
## handed back to campaign accounting. Baseline runs measure, not pass FPS gates.
const PRIVATE_WORK := "C:/Users/bligh/Documents/Codex/2026-10-10/you/work/"
var checks := 0
var fails := 0

class RenderedBattle:
	extends "res://battle/battle.gd"
	var close_contact := false
	var active_seconds := 0.0
	var paused_seconds := 0.0
	var slowmo_seconds := 0.0
	var expected_ticks := 0.0
	var chosen_speed_expected_ticks: float = 0.0
	func battle_opts(pb: Dictionary, n0: int, n1: int) -> Dictionary:
		var opts := super.battle_opts(pb, n0, n1)
		if close_contact:
			var rows := int(opts["h"]) - 2
			var middle := int(opts["w"]) / 2
			for side in 2:
				var cells := []
				for i in n0 if side == 0 else n1:
					cells.append(Vector2i(middle - 1 - i / rows if side == 0 else middle + i / rows, 1 + i % rows))
				opts["cells%d" % side] = cells
		return opts
	func _process_battle(delta: float) -> void:
		if sim != null and not sim.is_over():
			if paused: paused_seconds += delta
			else:
				active_seconds += delta
				var slow := maxf(0.0, _slowmo - delta) > 0.0
				if slow: slowmo_seconds += delta
				expected_ticks += delta * TICKS_PER_SEC * speed * (SLOWMO_FACTOR if slow else 1.0)
				chosen_speed_expected_ticks += delta * TICKS_PER_SEC * speed
		super._process_battle(delta)

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL battle render: ", what)

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * fraction)) - 1)])

func digest(sim: BattleSim) -> String:
	var units := []
	var state := []
	for f in sim.fighters:
		units.append(f.unit.to_dict())
		state.append([f.idx, f.side, f.cell, f.prev_cell, f.state, f.action_ticks,
			f.action_total, f.facing, f.target, f.prone, f.routed, f.waiting])
	return JSON.stringify({"tick":sim.tick,"rng":str(sim.rng.state),"units":units,
		"fighters":state,"winner":sim.winner}, "", true, true).sha256_text()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	var count := 100
	var enemy_count := 100
	var seconds := 12.0
	var report_path := ""
	var enforce := false
	var fresh_world := true
	var contact := false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--count="): count = int(a.trim_prefix("--count="))
		elif a.begins_with("--enemies="): enemy_count = int(a.trim_prefix("--enemies="))
		elif a.begins_with("--seconds="): seconds = float(a.trim_prefix("--seconds="))
		elif a.begins_with("--report="): report_path = a.trim_prefix("--report=").replace("\\", "/").simplify_path()
		elif a == "--enforce-gate": enforce = true
		elif a == "--no-world": fresh_world = false
		elif a == "--contact": contact = true
	check(count in [92,100,200] and enemy_count in [100,150,200], "bounded native force sizes")
	check(seconds in [8.0,12.0], "bounded 8 or12-second measurement duration")
	check(report_path.to_lower().begins_with(PRIVATE_WORK.to_lower()), "private report path")
	check(DisplayServer.get_name() != "headless", "actual rendered display server")
	var event_slowmo_default: bool = bool(Game.DEFAULT_SETTINGS["battle_event_slowmo"])
	var event_slowmo_setting: bool = bool(Game.setting("battle_event_slowmo"))
	check(not event_slowmo_default and not event_slowmo_setting, "actual fresh setting and authored default are OFF")
	if fails > 0: return fails
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	tree.root.position = Vector2i(-20000, -20000)
	tree.root.size = Vector2i(2560, 1440)
	tree.root.visible = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	Game.SAVE_PATH = "user://render_fixture_%d.json" % OS.get_process_id()
	var started := Time.get_ticks_usec()
	if fresh_world:
		WorldGen.gen_size = "normal"
		CampaignWorld.presim_span_days = 1
		var generation: Dictionary = Game.new_game_begin(777)
		while not Game.new_game_slice(generation, 4000):
			await tree.process_frame
		var history := {}
		while CampaignWorld.presim_left(Game) > 0:
			CampaignWorld.presim_slice(Game, history, 4000)
			await tree.process_frame
		CampaignWorld.presim_finish(Game, 0)
		Dynasty.prepare_world(Game)
		check(Game.day == 1.0 and not Dynasty.choices(Game).is_empty(), "fresh one-day campaign ready")
		var choices := Dynasty.choices(Game)
		if not choices.is_empty(): check(Dynasty.select_city(Game, choices[0]["town_id"]), "native house selected")
	else:
		Game.company.clear()
		Game.world.clear()
		Dynasty.note_households_changed()
	var world_ms := float(Time.get_ticks_usec() - started) / 1000.0
	print("render fixture world ready: %.1fms" % world_ms)
	var fixture_rng := RandomNumberGenerator.new()
	fixture_rng.seed = 1010
	Game.company = Factory.make_warband(fixture_rng, "middle_kingdom", count)
	Game.invalidate_deploy()
	Game.pending_battle = {"enemy":Factory.make_warband(fixture_rng,"orc_horde",enemy_count),
		"allies":[],"seed":1010,"terrain":"grassland","map":"large"}
	started = Time.get_ticks_usec()
	var battle := RenderedBattle.new()
	battle.close_contact = contact
	tree.root.add_child(battle)
	var diagnostics_layer := CanvasLayer.new()
	diagnostics_layer.layer = 100
	tree.root.add_child(diagnostics_layer)
	var panel := PerformancePanel.new()
	panel.setup(Perf)
	diagnostics_layer.add_child(panel)
	var setup_ms := float(Time.get_ticks_usec() - started) / 1000.0
	battle.set_speed(1.0)
	check(battle.sim.fighters.size() == count + enemy_count, "all actual fighters present")
	var first_digest := digest(battle.sim)
	var frames := []
	var cold := []
	var phase := 0
	var samples := []
	var measured_started := Time.get_ticks_usec()
	var previous := measured_started
	var max_draw_calls := 0
	var maximum_memory := 0
	var min_memory := 9223372036854775807
	var ticks_at_warm := 0
	var slowmo_frames := 0
	var warm_started := measured_started
	while float(Time.get_ticks_usec() - measured_started) / 1000000.0 < seconds:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var elapsed := float(now - measured_started) / 1000000.0
		var dt := float(now - previous) / 1000.0
		previous = now
		if battle._slowmo > 0.0: slowmo_frames += 1
		if elapsed < 2.0: cold.append(dt)
		else:
			if frames.is_empty():
				warm_started = now
				ticks_at_warm = battle.sim.tick
			frames.append(dt)
		max_draw_calls = maxi(max_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		var mem := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		maximum_memory = maxi(maximum_memory, mem)
		min_memory = mini(min_memory, mem)
		if phase == 0 and elapsed >= 3.0:
			battle.cam_pos.x += 400.0
			battle.cam_zoom *= 1.25
			phase = 1
		elif phase == 1 and elapsed >= 5.0:
			battle._fit_camera()
			battle.select(0)
			phase = 2
		elif phase == 2 and elapsed >= 7.0:
			battle.set_speed(0.0)
			var paused_digest := digest(battle.sim)
			await tree.process_frame
			await RenderingServer.frame_post_draw
			check(digest(battle.sim) == paused_digest, "pause and inspector preserve native state")
			battle.set_speed(1.0)
			previous = Time.get_ticks_usec()
			phase = 3
		if samples.size() < 4 and elapsed >= 2.0 + samples.size() * 3.0:
			samples.append({"seconds":elapsed,"tick":battle.sim.tick,"memory_bytes":mem,
				"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT))})
	var measured_seconds := float(Time.get_ticks_usec() - measured_started) / 1000000.0
	var warm_seconds := float(Time.get_ticks_usec() - warm_started) / 1000000.0
	var mean := 0.0
	for value in frames: mean += float(value)
	mean /= maxf(1.0, frames.size())
	var warm_fps := 1000.0 / maxf(0.001, mean)
	var p95 := percentile(frames, 0.95)
	check(max_draw_calls > 0 and frames.size() > 3, "real renderer produced measured frames")
	check(phase == 3 and battle.sim.tick > 0, "camera, inspector, pause and1x advancement exercised")
	var cache := {}
	var cache_script = load("res://art/paperdoll.gd")
	if cache_script.has_method("cache_stats"): cache = cache_script.call("cache_stats")
	var gate := warm_fps >= 30.0 and p95 <= 50.0
	if enforce: check(gate, "rendered recovery floor30FPS/p95<=50ms")
	var native_delivery := float(battle.sim.tick) + battle._acc >= battle.expected_ticks - 1.01
	if enforce: check(native_delivery, "native1x tick budget delivered including actual pause and slowmo")
	var chosen_tick_budget: float = battle.chosen_speed_expected_ticks
	var effective_chosen_speed_ratio: float = (float(battle.sim.tick) + battle._acc) / maxf(chosen_tick_budget,0.001)
	var chosen_speed_gate: bool = chosen_tick_budget > 0.0 and battle.speed == 1.0 and \
		absf(effective_chosen_speed_ratio - 1.0) <= 1.01 / maxf(chosen_tick_budget,1.0)
	var default_off_gate: bool = not event_slowmo_default and not event_slowmo_setting and \
		not bool(Game.setting("battle_event_slowmo")) and slowmo_frames == 0 and battle.slowmo_seconds == 0.0
	check(default_off_gate, "OFF creates zero automatic slow frames/seconds during actual battle")
	if enforce: check(chosen_speed_gate, "actual selected-speed tick budget delivered within one native tick")
	var screenshot_path := report_path.trim_suffix(".json") + ".png"
	var image := tree.root.get_texture().get_image()
	check(image != null and image.get_width() == 2560 and image.get_height() == 1440, "actual2560x1440 rendered viewport readable")
	if image != null: check(image.save_png(screenshot_path) == OK, "private screenshot stored")
	var event_counts := {}
	for event: Dictionary in battle.sim.events:
		var kind := String(event.get("type", "unknown"))
		event_counts[kind] = int(event_counts.get(kind, 0)) + 1
	if contact: check(int(event_counts.get("attack", 0)) > 0 and int(event_counts.get("hit", 0)) > 0, "native contact fixture actually attacked and hit")
	var report := {"version":ProjectSettings.get_setting("application/config/version"),
		"fixture":"native Factory forces in isolated fresh one-day campaign; no campaign result handback",
		"fresh_world":fresh_world,"history_days":1 if fresh_world else 0,
		"world_ms":world_ms,"world_towns":Game.world.get("towns",{}).size(),
		"world_bands":Game.world.get("warbands",{}).size(),"world_day":Game.day,
		"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"resolution":[2560,1440],"max_fps":60,"no_focus":tree.root.get_flag(Window.FLAG_NO_FOCUS),
		"performance_panel":true,"native_nominal_ticks_per_second":battle.TICKS_PER_SEC,
		"close_contact":contact,"active_simulation_seconds":battle.active_seconds,
		"paused_simulation_seconds":battle.paused_seconds,"native_slowmo_seconds":battle.slowmo_seconds,
		"expected_native_ticks":battle.expected_ticks,"native_tick_delivery":native_delivery,
		"event_slowmo_default":event_slowmo_default,"event_slowmo_setting":bool(Game.setting("battle_event_slowmo")),
		"default_off_gate":default_off_gate,"chosen_speed":battle.speed,
		"chosen_speed_expected_ticks":chosen_tick_budget,"effective_chosen_speed_ratio":effective_chosen_speed_ratio,
		"chosen_speed_gate":chosen_speed_gate,
		"native_slowmo_frames":slowmo_frames,"tick_accumulator":battle._acc,"event_counts":event_counts,
		"force_sizes":[count,enemy_count],"setup_ms":setup_ms,"cold_frames":cold,
		"measured_seconds":measured_seconds,"warm_frames":frames.size(),"warm_fps":warm_fps,
		"mean_frame_ms":mean,"p50_ms":percentile(frames,0.5),"p95_ms":p95,
		"p99_ms":percentile(frames,0.99),"worst_ms":percentile(frames,1.0),
		"sim_tick":battle.sim.tick,"warm_ticks_per_second":float(battle.sim.tick-ticks_at_warm)/maxf(warm_seconds,0.001),
		"start_state_sha256":first_digest,"end_state_sha256":digest(battle.sim),
		"memory_min_bytes":min_memory,"memory_max_bytes":maximum_memory,
		"max_draw_calls":max_draw_calls,"samples":samples,"cache":cache,
		"diagnostics":Perf.snapshot(),"recovery_gate":gate,"checks":checks,"fails":fails,
		"screenshot":screenshot_path}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	check(file != null, "private report opens")
	report["checks"] = checks
	report["fails"] = fails
	if file != null:
		file.store_string(JSON.stringify(report,"  ",true,true))
		file.close()
	print("render %d/%d: %.2fFPS p95 %.2fms worst %.2fms ticks%d gate%s" %
		[count,enemy_count,warm_fps,p95,percentile(frames,1.0),battle.sim.tick,str(gate)])
	battle.queue_free()
	diagnostics_layer.queue_free()
	await tree.process_frame
	Game.pending_battle = {}
	Game.company.clear()
	Game.world.clear()
	Dynasty.note_households_changed()
	Paperdoll.clear_cache()
	return fails
