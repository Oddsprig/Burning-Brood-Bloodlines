extends RefCounted
## v0.105 Clear battles, without the fear-circle clutter.
## Verifies:
## 1) "battle_markers" setting has 3 values (light, full, off; default light), is saved and loaded,
##    and old settings JSON without "battle_markers" loads and defaults to "light".
## 2) Off draws no fear circles or floating FEAR/ROUT words.
## 3) Light draws no fear circles, no floating FEAR/ROUT words, at most one marker per man, and throttles mass breaks.
## 4) Full keeps today's behaviour (fear circles + floating FEAR/ROUT words + unthrottled markers).
## 5) v0.105: Light strictly reduces 100-on-100 draw calls; wall time has a slack catastrophe guard.
const U := preload("res://tests/sim_util.gd")
const Cues := preload("res://battle/readability_fx.gd")
const Screen := preload("res://battle/battle.gd")
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL clear battles v105: " + why)
	else:
		print("ok   " + why)

func _make_dragon_unit() -> Unit:
	Game.world["dragons"] = {"schema": 1, "next_id": 1, "records": {}, "pairs": {}, "initialized": true}
	var owner := {"person_uid": "p:v105", "house_uid": "h:v105", "household_uid": "hh:v105", "town_id": "t:v105", "state": "hire"}
	var row := Dragons._make(Game, "adult", "t:v105", owner, "v105:dragon", 0, "female")
	DragonCombat.prepare_world(Game)
	return DragonCombat._unit(Game, str(row["id"]))

func _clone_army(template: Unit, count: int) -> Array:
	var base := template.to_dict()
	var out: Array = []
	for i in count:
		var d := base.duplicate(true)
		d["uid"] = 10000 + i
		d["name"] = "%s %d" % [template.name, i + 1]
		out.append(Unit.from_dict(d))
	return out

func _test_setting_save_load_and_ui(tree: SceneTree) -> void:
	var old_path := Game.SETTINGS_PATH
	var old_settings := Game.settings.duplicate(true)
	var tmp_path := "user://test_clear_battles_v105_settings.json"
	Game.SETTINGS_PATH = tmp_path
	Game.settings = Game.DEFAULT_SETTINGS.duplicate(true)

	check(String(Game.DEFAULT_SETTINGS.get("battle_markers", "")) == "light", "default battle_markers setting is light")
	check(Game.battle_markers_mode() == "light", "battle_markers_mode() defaults to light")
	check(Game.SETTING_CHOICES.has("battle_markers"), "SETTING_CHOICES includes battle_markers")
	var opts: Array = Game.SETTING_CHOICES.get("battle_markers", {}).get("options", [])
	var vals: Array = []
	for pair in opts:
		vals.append(String(pair[0]))
	check(opts.size() == 3 and vals.has("light") and vals.has("full") and vals.has("off"),
		"battle_markers has exactly 3 values: light, full, off")

	for mode_val: String in ["full", "off", "light"]:
		Game.set_setting("battle_markers", mode_val)
		Game.settings["battle_markers"] = "light" if mode_val != "light" else "full"
		Game.load_settings()
		check(Game.battle_markers_mode() == mode_val and String(Game.setting("battle_markers")) == mode_val,
			"battle_markers saves and reloads value: " + mode_val)

	# Old settings file without "battle_markers" key must load cleanly and default to "light".
	var legacy := {"gore": "full", "autosave": "week", "music_volume": 0.5}
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(legacy))
		f.close()
	Game.settings["battle_markers"] = "full"
	Game.load_settings()
	check(Game.battle_markers_mode() == "light" and String(Game.setting("battle_markers")) == "light",
		"legacy settings without battle_markers load and default to light")

	# Settings UI button cycles through Light -> Full -> Off -> Light.
	var ui_scene: Control = (load("res://ui/settings.tscn") as PackedScene).instantiate()
	ui_scene.overlay = true
	tree.root.add_child.call_deferred(ui_scene)
	await tree.process_frame
	await tree.process_frame
	var btn: Button = ui_scene.find_child("Choice_battle_markers", true, false)
	check(btn != null and btn.text == "Light", "settings screen shows Choice_battle_markers at Light")
	if btn != null:
		btn.pressed.emit()
		check(Game.battle_markers_mode() == "full", "settings button cycles Light -> Full")
		btn = ui_scene.find_child("Choice_battle_markers", true, false)
		if btn != null:
			btn.pressed.emit()
		check(Game.battle_markers_mode() == "off", "settings button cycles Full -> Off")
		btn = ui_scene.find_child("Choice_battle_markers", true, false)
		if btn != null:
			btn.pressed.emit()
		check(Game.battle_markers_mode() == "light", "settings button cycles Off -> Light")
	ui_scene.queue_free()
	await tree.process_frame

	if FileAccess.file_exists(tmp_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	Game.SETTINGS_PATH = old_path
	Game.settings = old_settings

func _force_draw_frame(tree: SceneTree, fx: Node2D) -> void:
	# v0.105: _push re-enables processing; keep these manually driven fixtures free of wall-clock aging.
	fx.set_process(false)
	var before := int(fx.get("draw_pass_count"))
	fx.queue_redraw()
	await tree.process_frame
	if int(fx.get("draw_pass_count")) == before and fx.is_inside_tree():
		fx.notification(CanvasItem.NOTIFICATION_DRAW)

func _test_modes_and_mass_break_throttling(tree: SceneTree) -> void:
	var left_tmpl := U.soldier("copper")
	var right_tmpl := U.make("orc", [["hacking_cleaver", "copper"], ["tunic", "linen"]], {"axe": 3, "fighter": 2})
	Food.roll_fav_drink(left_tmpl, 101)
	Food.roll_fav_drink(right_tmpl, 202)
	var side0 := _clone_army(left_tmpl, 4)
	var side1 := _clone_army(right_tmpl, 20)
	var s := BattleSim.new()
	s.setup(side0, side1, 105, {"w": 32, "h": 18, "max_ticks": 400, "log_moves": false, "combat_journal": false})

	# v0.105: put ReadabilityFx in the scene tree so queue_redraw + process_frame executes real _draw passes.
	var fx := Cues.new()
	fx.set_process(false)
	tree.root.add_child.call_deferred(fx)
	await tree.process_frame
	await tree.process_frame
	check(fx.is_inside_tree(), "ReadabilityFx node is in the scene tree for mode contract checks")

	# 1) Off mode: no fear circles, no words, no morale markers.
	fx.setup(s, 40.0, true, [], "off")
	fx.set_process(false)
	for i in range(4, 24):
		var f: Fighter = s.fighters[i]
		f.morale = maxf(0.0, f.morale - 18.0)
	var rout_events: Array = []
	for i in range(4, 12):
		s.fighters[i].routed = true
		rout_events.append({"type": "rout", "actor": i})
	fx.observe(s, rout_events)
	await _force_draw_frame(tree, fx)
	check(fx.draw_pass_count > 0 and fx.fear_circle_count() == 0 and fx.fear_rout_word_count() == 0 and fx.morale_marker_count() == 0,
		"Off mode draws no fear circles, no FEAR/ROUT words, and no morale markers")
	fx.end_battle()

	# 2) Light mode: single man repeated shocks + rout stays at most 1 marker per man, 0 fear circles, 0 words.
	for f: Fighter in s.fighters:
		f.morale = 80.0
		f.routed = false
	fx.setup(s, 40.0, true, [], "light")
	fx.set_process(false)
	var target_idx := 4
	var tf: Fighter = s.fighters[target_idx]
	tf.morale = 60.0
	s.tick = 10
	fx.observe(s)
	await _force_draw_frame(tree, fx)
	check(fx.markers_for_actor(target_idx) == 1 and fx.drawn_morale_marker_count() == 1,
		"Light mode emits and draws 1 small marker when a man takes morale shock")
	check(fx.fear_circle_count() == 0 and fx.fear_rout_word_count() == 0,
		"Light mode draws 0 fear circles and 0 floating FEAR/ROUT words")
	tf.morale = 35.0
	s.tick = 60
	fx.observe(s)
	await _force_draw_frame(tree, fx)
	check(fx.markers_for_actor(target_idx) == 1 and fx.max_markers_per_actor() == 1,
		"Light mode keeps at most 1 marker per man across repeated fear shocks")
	tf.routed = true
	s.tick = 65
	fx.observe(s, [{"type": "rout", "actor": target_idx}])
	await _force_draw_frame(tree, fx)
	check(fx.markers_for_actor(target_idx) == 1 and fx.max_markers_per_actor() == 1,
		"Light mode upgrades a man's fear marker in-place on rout (at most 1 marker per man)")
	# v0.105: when a fighter dies or leaves the field, observe() cleans up its morale marker.
	tf.state = "dead"
	s.tick = 66
	fx.observe(s)
	check(fx.markers_for_actor(target_idx) == 0, "dead/fled fighter morale marker is cleaned up on observe")
	tf.state = "ready" # v0.105: restore Fighter's actual default state.
	fx.end_battle()

	# 3) Light mode mass break: 20 men breaking at once are throttled/aggregated.
	for f: Fighter in s.fighters:
		f.morale = 80.0
		f.routed = false
	fx.setup(s, 40.0, true, [], "light")
	fx.set_process(false)
	s.tick = 50
	var mass_routs: Array = []
	for i in range(4, 24):
		var f: Fighter = s.fighters[i]
		f.cell = Vector2i(20 + (i - 4) % 10, 2 + ((i - 4) / 2) * 3)
		f.morale = 40.0
		f.routed = (i % 2 == 0)
		if f.routed:
			mass_routs.append({"type": "rout", "actor": i})
	fx.observe(s, mass_routs)
	await _force_draw_frame(tree, fx)
	var light_mass_markers := fx.morale_marker_count()
	check(light_mass_markers >= 1 and light_mass_markers <= Cues.LIGHT_MAX_BREAK_PER_TICK,
		"Light mode throttles 20 simultaneous breaks to %d markers (cap %d)" % [light_mass_markers, Cues.LIGHT_MAX_BREAK_PER_TICK])
	check(fx.throttled_breaks >= 20 - Cues.LIGHT_MAX_BREAK_PER_TICK,
		"Light mode records aggregated/throttled mass breaks (%d throttled)" % fx.throttled_breaks)
	check(fx.max_markers_per_actor() <= 1 and fx.fear_circle_count() == 0 and fx.fear_rout_word_count() == 0,
		"Light mode mass break draws 0 fear circles, 0 words, and <= 1 marker per man")
	fx.end_battle()

	# 4) Full mode: keeps today's behaviour (fear circles, floating FEAR/ROUT words, unthrottled markers).
	for f: Fighter in s.fighters:
		f.morale = 80.0
		f.routed = false
	fx.setup(s, 40.0, true, [], "full")
	fx.set_process(false)
	s.tick = 50
	for i in range(4, 24):
		var f: Fighter = s.fighters[i]
		f.morale = 40.0
		f.routed = (i % 2 == 0)
	fx.observe(s, mass_routs)
	await _force_draw_frame(tree, fx)
	var full_mass_markers := fx.morale_marker_count()
	check(full_mass_markers == 20 and full_mass_markers > light_mass_markers,
		"Full mode keeps all 20 markers on mass break (%d vs Light %d)" % [full_mass_markers, light_mass_markers])
	check(fx.fear_circle_count() == 20 and fx.fear_rout_word_count() == 20,
		"Full mode draws fear circles (%d) and floating FEAR/ROUT words (%d)" % [fx.fear_circle_count(), fx.fear_rout_word_count()])
	fx.end_battle()
	fx.queue_free()
	await tree.process_frame

func _test_live_battle_screen_wiring(tree: SceneTree) -> void:
	var old_mode := Game.battle_markers_mode()
	var left := U.soldier("copper")
	var right := U.soldier("copper")
	Food.roll_fav_drink(left, 11)
	Food.roll_fav_drink(right, 22)
	Game.set_setting("battle_markers", "light")
	Game.pending_battle = {"seed": 105, "round_side0": [left], "enemy": [right], "terrain": "plains", "max_ticks": 120}
	var b := Screen.new()
	b.paused = true
	tree.root.add_child.call_deferred(b)
	await tree.process_frame
	await tree.process_frame
	b.set_process(false)
	check(b.readability != null and b.readability.current_mode() == "light", "Battle screen initializes ReadabilityFx in light mode")
	# v0.105: custom rout batches must bind even a not-yet-routed fighter for later cleanup.
	b.sim.fighters[1].routed = false
	b.readability.observe(b.sim, [{"type": "rout", "actor": 1}])
	check(b.readability.morale_marker_count() == 1 and b.readability.markers_for_actor(1) == 1, "seeded one actor-bound live marker before live switch")
	Game.set_setting("battle_markers", "off")
	check(b.readability.current_mode() == "off" and b.readability.morale_marker_count() == 0, "live Off prunes live markers")
	Game.set_setting("battle_markers", "full")
	check(b.readability.current_mode() == "full", "Battle screen updates ReadabilityFx live when set to full")
	b.sim.fighters[1].routed = true
	b.readability.observe(b.sim, [{"type": "rout", "actor": 1}, {"type": "rout", "actor": 1}])
	check(b.readability.morale_marker_count() == 2, "Full mode allows multiple markers on an actor before switching to Light")
	Game.set_setting("battle_markers", "light")
	check(b.readability.current_mode() == "light" and b.readability.morale_marker_count() == 1 and b.readability.max_markers_per_actor() <= 1,
		"Battle screen updates ReadabilityFx live when set back to light and prunes duplicate actor markers")
	b.queue_free()
	await tree.process_frame
	Game.set_setting("battle_markers", old_mode)

static func _median_float(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[mid])
	return (float(sorted[mid - 1]) + float(sorted[mid])) * 0.5

func _build_100v100_sim(dragon: Unit, left_tmpl: Unit, right_tmpl: Unit) -> BattleSim:
	var side0 := [Unit.from_dict(dragon.to_dict().duplicate(true))]
	side0.append_array(_clone_army(left_tmpl, 99))
	var side1 := _clone_army(right_tmpl, 100)
	var grid := BattleSim.formation_grid(100, 100, Screen.LARGE_GRID)
	var s := BattleSim.new()
	s.setup(side0, side1, 1050, {"w": grid.x, "h": grid.y, "terrain": "plains", "max_ticks": 600,
		"verbose": false, "log_moves": false, "combat_journal": false, "history_events": 256, "history_log": 16})
	for f: Fighter in s.fighters:
		f.morale = 80.0
	return s

## v0.105: puts ReadabilityFx in the scene tree, drives a 100v100 battle state across `steps` real frames,
## forces real CanvasItem._draw passes, and records per-frame time and actual CanvasItem draw calls.
func _measure_100v100_mode(tree: SceneTree, mode_name: String, dragon: Unit, left_tmpl: Unit, right_tmpl: Unit, steps: int) -> Dictionary:
	var s := _build_100v100_sim(dragon, left_tmpl, right_tmpl)
	var fx := Cues.new()
	fx.setup(s, 40.0, true, ["charge", "line"], mode_name)
	fx.set_process(false)
	tree.root.add_child.call_deferred(fx)
	await tree.process_frame
	await tree.process_frame
	var inside_tree := fx.is_inside_tree()
	var warmup := 8
	var band_count := 23
	var band_size := 8
	var frame_us_samples: Array = []
	var draw_us_samples: Array = []
	var draw_call_samples: Array = []
	var drawn_frames := 0
	var max_circles := 0
	var max_words := 0
	var max_morale := 0
	for f_idx in warmup + steps:
		s.step()
		# Restore the upcoming band so fx.observe records baseline morale=80 before that band is shocked next frame.
		var next_base := 8 + (((f_idx + 1) % band_count) * band_size)
		for j in range(next_base, next_base + band_size):
			var nf: Fighter = s.fighters[j]
			if nf.present():
				nf.routed = false
				nf.morale = 80.0
		# Shock 6 fighters and rout 2 fighters in the current rotating band (revisited every 23 ticks >= cooldown 20).
		var cur_base := 8 + ((f_idx % band_count) * band_size)
		for k in band_size:
			var j := cur_base + k
			var cf: Fighter = s.fighters[j]
			if not cf.present():
				continue
			if k < 6:
				cf.routed = false
				cf.morale = 50.0
			else:
				cf.routed = true
				s.new_events.append({"tick": s.tick, "type": "rout", "actor": j, "target": -1, "text": "", "decisive": true, "part": ""})
		var draws_before := fx.draw_pass_count
		var t0 := Time.get_ticks_usec()
		fx.observe(s)
		fx.set_process(false) # v0.105: _push re-enables _process; age only by the manual tick below.
		fx.advance(Formulas.TICK_SECONDS)
		var obs_us := Time.get_ticks_usec() - t0
		await _force_draw_frame(tree, fx)
		if f_idx >= warmup:
			if fx.draw_pass_count > draws_before:
				drawn_frames += 1
				# v0.105: sample only a fresh draw; stalled frames still fail the drawn_frames assertion.
				frame_us_samples.append(obs_us + fx.last_draw_usec)
				draw_us_samples.append(fx.last_draw_usec)
				draw_call_samples.append(fx.draw_call_count())
				max_circles = maxi(max_circles, fx.fear_circle_count())
				max_words = maxi(max_words, fx.fear_rout_word_count())
				max_morale = maxi(max_morale, fx.morale_marker_count())
	fx.end_battle()
	fx.queue_free()
	await tree.process_frame
	return {
		"inside_tree": inside_tree,
		"drawn_frames": drawn_frames,
		"median_us": _median_float(frame_us_samples),
		"median_draw_us": _median_float(draw_us_samples),
		"median_calls": _median_float(draw_call_samples),
		"max_circles": max_circles,
		"max_words": max_words,
		"max_morale": max_morale,
	}

func _test_frame_time_guard_100v100(tree: SceneTree) -> void:
	var prev_world := Game.world.duplicate(true)
	var dragon := _make_dragon_unit()
	var left_tmpl := U.soldier("copper")
	var right_tmpl := U.make("orc", [["hacking_cleaver", "copper"], ["tunic", "linen"]], {"axe": 3, "fighter": 2})
	Food.roll_fav_drink(left_tmpl, 301)
	Food.roll_fav_drink(right_tmpl, 402)
	var steps := 64
	var full_a := await _measure_100v100_mode(tree, "full", dragon, left_tmpl, right_tmpl, steps)
	var light_a := await _measure_100v100_mode(tree, "light", dragon, left_tmpl, right_tmpl, steps)
	var us_full := float(full_a["median_us"])
	var us_light := float(light_a["median_us"])
	var draw_us_full := float(full_a["median_draw_us"])
	var draw_us_light := float(light_a["median_draw_us"])
	var calls_full := float(full_a["median_calls"])
	var calls_light := float(light_a["median_calls"])
	print("100v100 marker work (median over %d real frames): Light %.1f us/frame (%.1f us _draw, %.1f draw calls, max morale %d) vs Full %.1f us/frame (%.1f us _draw, %.1f draw calls, max morale %d)" % [
		steps, us_light, draw_us_light, calls_light, int(light_a["max_morale"]), us_full, draw_us_full, calls_full, int(full_a["max_morale"])])
	check(bool(full_a["inside_tree"]) and bool(light_a["inside_tree"]) and int(full_a["drawn_frames"]) == steps and int(light_a["drawn_frames"]) == steps,
		"100v100 ReadabilityFx nodes are in the scene tree and _draw executes on all %d measured frames" % steps)
	# v0.105: non-morale cues cannot stand in for an absent Light morale marker.
	check(int(light_a["max_morale"]) >= 1 and int(light_a["max_morale"]) <= Cues.LIGHT_MAX_MORALE_ACTIVE and int(light_a["max_morale"]) < int(full_a["max_morale"]),
		"100v100 Light active markers (%d) present, under cap and below Full (%d)" % [int(light_a["max_morale"]), int(full_a["max_morale"])])
	check(calls_light > 0.0 and calls_light < calls_full,
		"100v100 median CanvasItem draw calls per frame at Light (%.1f) is lower than Full (%.1f)" % [calls_light, calls_full])
	# v0.105: microsecond medians are noisy; draw calls above stay strict and time only guards catastrophe.
	check(us_light <= us_full * 1.5 + 100.0 and draw_us_light <= draw_us_full * 1.5 + 50.0,
		"100v100 median per-frame marker time at Light (%.1f us total, %.1f us _draw) is within slack of Full (%.1f us total, %.1f us _draw)" % [us_light, draw_us_light, us_full, draw_us_full])
	check(int(light_a["max_circles"]) == 0 and int(light_a["max_words"]) == 0 and int(full_a["max_circles"]) > 0 and int(full_a["max_words"]) > 0,
		"100v100 Light draws 0 fear circles and 0 morale words while Full draws both")
	Game.world = prev_world

func run(tree: SceneTree) -> int:
	var t0 := Time.get_ticks_msec()
	await tree.process_frame
	await _test_setting_save_load_and_ui(tree)
	await _test_modes_and_mass_break_throttling(tree)
	await _test_live_battle_screen_wiring(tree)
	await _test_frame_time_guard_100v100(tree)
	var elapsed_ms := Time.get_ticks_msec() - t0
	check(elapsed_ms < 60000, "test_clear_battles_v105 finishes well under 3-minute budget (%d ms)" % elapsed_ms)
	print("clear_battles_v105: %d checks, %d failures (%d ms)" % [checks, fails, elapsed_ms])
	return fails
