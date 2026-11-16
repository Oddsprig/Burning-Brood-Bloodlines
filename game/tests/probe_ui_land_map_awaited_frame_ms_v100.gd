extends "res://tests/test_ui_land_map.gd"
## Diagnostic for the existing #91 pan/zoom workload, not a replacement acceptance suite.
## Reuses its seed, _big_town, both 1280x720 hosts, six immediate overlay changes,
## 30 motions and six zooms. Every awaited frame is retained, including frame zero.
## Reports a CPU UI phase and the complete next-frame interval; BOTH retain
## the 16.7 ms gate. Headless idle sleep is disabled only for these samples,
## then restored, so deletion/final flush work remains inside the interval.
## Prints after sampling so console I/O cannot hide in a later measured frame.
## The small map starts in the same USE/no-selection state as #91's pan section;
## the unrelated small-town tap/pixel assertions remain in the original test.
##
## Testing rules: run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief. A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.
## Every test aims for under 60 s wall time.

func run(tree: SceneTree) -> int:
	var started: int = Time.get_ticks_msec()
	Game.new_game(5150)
	print("LAND_MAP_SETUP world_ms=", Time.get_ticks_msec() - started)
	if Time.get_ticks_msec() - started >= 55000:
		check(false, "land-map diagnostic exceeded its 55-second setup budget")
		return fails
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	var town: Dictionary = Game.world["towns"][ids[0]]
	var host: Control = Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child.call_deferred(host)
	await tree.process_frame
	var root: Control = LandMap.mount(host, town)
	await tree.process_frame
	var first_view: Variant = _find_view(root)
	check(first_view != null, "the first map is mounted")
	if first_view == null:
		host.queue_free()
		await tree.process_frame
		return fails
	var big: Dictionary = _big_town(town)
	var plots: Dictionary = Plots.of(big)
	check(Plots.count(plots) >= 1500, "diagnostic retains at least 1,500 real plots")
	var host2: Control = Control.new()
	host2.size = Vector2(1280, 720)
	tree.root.add_child(host2)
	check(first_view.is_inside_tree(), "the first map stays in the scene tree")
	var root2: Control = LandMap.mount(host2, big)
	await tree.process_frame
	var view: Variant = _find_view(root2)
	check(view != null, "the big map is mounted")
	if view == null:
		host.queue_free()
		host2.queue_free()
		await tree.process_frame
		return fails
	# Print environment before the overlays; do not consume a settling frame afterward.
	print("LAND_MAP_FRAME_ENV ", JSON.stringify({
		"plots": Plots.count(plots), "grid": [int(plots["gw"]), int(plots["gh"])],
		"host_size": [1280, 720], "display": DisplayServer.get_name(),
		"max_fps": Engine.max_fps, "low_processor_mode": OS.low_processor_usage_mode,
		"low_processor_sleep_usec": OS.low_processor_usage_mode_sleep_usec,
		"window_can_draw": DisplayServer.window_can_draw(),
		"project_vsync_mode": int(ProjectSettings.get_setting("display/window/vsync/vsync_mode", 1)),
		"project_frame_delay_msec": int(ProjectSettings.get_setting("application/run/frame_delay_msec", 0)),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"max_physics_steps_per_frame": Engine.max_physics_steps_per_frame,
		"physics_jitter_fix": Engine.physics_jitter_fix,
		"fixed_fps_requested": "--fixed-fps" in OS.get_cmdline_args(),
		"retained_texture_node": view.get_node_or_null("LandMapTexture") != null}))
	var compose_worst: float = 0.0
	var compose_times: PackedFloat64Array = PackedFloat64Array()
	for overlay: String in LandMap.OVERLAYS:
		view.set_overlay(overlay)
		compose_times.append(float(view.compose_ms))
		compose_worst = maxf(compose_worst, float(view.compose_ms))
	# No settling frame: sample zero retains the pending overlay redraw/layout work.
	var frames: PackedFloat64Array = PackedFloat64Array()
	var works: PackedFloat64Array = PackedFloat64Array()
	var same_frames: PackedByteArray = PackedByteArray()
	var consecutive_frames: PackedByteArray = PackedByteArray()
	var inputs: PackedFloat64Array = PackedFloat64Array()
	var processes: PackedFloat64Array = PackedFloat64Array()
	var physics: PackedFloat64Array = PackedFloat64Array()
	var worst: float = 0.0
	var work_worst: float = 0.0
	var idle_sleep_usec: int = OS.low_processor_usage_mode_sleep_usec
	var headless_samples: bool = DisplayServer.get_name() == "headless"
	var idle_sleep_scope: HeadlessIdleSleepScope = HeadlessIdleSleepScope.new()
	if headless_samples:
		check(Engine.max_fps == 0, "headless full-frame samples require max_fps=0")
		idle_sleep_scope.disable()
	var sampling_sleep_usec: int = OS.low_processor_usage_mode_sleep_usec
	check(not headless_samples or sampling_sleep_usec == 0, "headless samples disable only idle sleep")
	for k: int in 30:
		var work_end: SceneTreeTimer = tree.create_timer(0.0, true, false, true)
		var engine_frame: int = Engine.get_process_frames()
		var t1: int = Time.get_ticks_usec()
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		view._down = true
		motion.relative = Vector2(7, 3)
		view._gui_input(motion)
		if k % 5 == 0:
			view.zoom_at(Vector2(400, 300), 1.05)
		var input_done: int = Time.get_ticks_usec()
		await work_end.timeout
		var work_ms: float = float(Time.get_ticks_usec() - t1) / 1000.0
		same_frames.append(1 if Engine.get_process_frames() == engine_frame else 0)
		await tree.process_frame
		var frame_ms: float = float(Time.get_ticks_usec() - t1) / 1000.0
		consecutive_frames.append(1 if Engine.get_process_frames() == engine_frame + 1 else 0)
		frames.append(frame_ms)
		works.append(work_ms)
		inputs.append(float(input_done - t1) / 1000.0)
		processes.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		worst = maxf(worst, frame_ms)
		work_worst = maxf(work_worst, work_ms)
	view._down = false
	idle_sleep_scope.restore()
	check(OS.low_processor_usage_mode_sleep_usec == idle_sleep_usec, "diagnostic restores idle sleep")
	print("LAND_MAP_FRAME_PACING headless=%s sample_idle_sleep_usec=%d restored_idle_sleep_usec=%d full_interval_gate=true" %
		[str(headless_samples), sampling_sleep_usec, OS.low_processor_usage_mode_sleep_usec])
	for k: int in compose_times.size():
		print("LAND_MAP_OVERLAY overlay=%s compose_ms=%.3f; synchronous, before pan sample zero" %
			[LandMap.OVERLAYS[k], compose_times[k]])
	for k: int in frames.size():
		print("LAND_MAP_AWAITED_FRAME index=%02d zoom=%s awaited_ms=%.3f work_ms=%.3f input_ms=%.3f same_frame=%s consecutive=%s published_engine_process_max_ms=%.3f published_engine_physics_max_ms=%.3f" %
			[k, str(k % 5 == 0), frames[k], works[k], inputs[k], str(same_frames[k] == 1),
			str(consecutive_frames[k] == 1), processes[k], physics[k]])
		check(same_frames[k] == 1, "sample %d work timer closes in the same engine frame" % k)
		check(consecutive_frames[k] == 1, "sample %d awaits exactly the next engine frame" % k)
	print("LAND_MAP_FRAME_DIAGNOSTIC frames=%d interval_worst_ms=%.3f work_worst_ms=%.3f compose_worst_ms=%.3f elapsed_ms=%d; no samples skipped; corrected #91 remains required" %
		[frames.size(), worst, work_worst, compose_worst, Time.get_ticks_msec() - started])
	check(frames.size() == 30 and works.size() == 30, "all 30 pan/zoom intervals and work samples retained")
	check(compose_worst < 120.0, "original 120 ms overlay budget remains in the diagnostic")
	check(work_worst < 16.7, "16.7 ms CPU phase work budget on the unchanged workload (%.3f)" % work_worst)
	check(worst < 16.7, "16.7 ms complete frame interval budget on the unchanged workload (%.3f)" % worst)
	check(Time.get_ticks_msec() - started < 55000, "diagnostic finishes within its 55-second work budget")
	host.queue_free()
	host2.queue_free()
	await tree.process_frame
	return fails
