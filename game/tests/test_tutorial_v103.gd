extends RefCounted
## Verification for v0.103: the guided tutorial (campaign/tutorial.gd + ui/tutorial_overlay.gd
## + data/tutorial.json + Game.tutorial_step/tutorial_done + Settings "Replay tutorial").
## Drives a 3-step sample tutorial (button / screen / state done-kinds) over three plain
## buttons and checks: the highlight sits on the right control at 1280x720, 1920x1080 and a
## phone landscape size (2340x1080); each step waits for its action; Back works; Skip and
## Replay work; progress survives save and load (and an old save without the field loads);
## Settings shows Replay tutorial and it opens the overlay.
## Target: alone, headless, under 3 minutes (duration unverified until run).
## Save checks use the cached Normal/one-day campaign; cold setup generates it once.
##   godot --headless --path game res://tests/runner.tscn -- --block=tutorial_v103
## Testing rules (verbatim, user rule): "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."

var fails := 0
var _save_fixture: Dictionary = {}

# v0.103: catch raw touches leaking past the dim into a screen's unhandled gestures.
class InputProbe extends Control:
	var touches := 0
	var touch_downs := 0
	var touch_ups := 0
	func _input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			if event.pressed:
				touch_downs += 1
			else:
				touch_ups += 1
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			touches += 1

# v0.103: exercise the real Game.goto()/queue_free lifecycle without building a campaign.
class ScreenDriver extends Node:
	var current: Control
	func show_screen(_path: String) -> void:
		current.queue_free()
		current = Control.new()
		current.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(current)
		var button := Button.new()
		button.name = "NextScreen"
		button.position = Vector2(24, 24)
		button.size = Vector2(160, 52)
		current.add_child(button)

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2340, 1080)]   # desktop, desktop, phone landscape
const SAMPLE := [
	{"id": "one", "anchor": "StepOne", "text": "Press the first button.", "done": {"kind": "button"}},
	{"id": "two", "anchor": "StepTwo", "text": "Now the map opens.", "done": {"kind": "screen", "screen": "map"}},
	{"id": "three", "anchor": "StepThree", "text": "Wait until ready.", "done": {"kind": "state", "key": "ready", "equals": true}},
]

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", msg)

func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame

# v0.103: every missing prerequisite is a failure before a guard can stop dependent work.
func _in_tree(node, what: String) -> bool:
	if not is_instance_valid(node):
		check(false, what + " is missing or freed")
		return false
	if not node.is_inside_tree() or not node.is_node_ready():
		check(false, what + " is not ready inside the scene tree")
		return false
	return true

func _control(parent, name: String) -> Control:
	if not _in_tree(parent, "parent of " + name):
		return null
	var control := parent.find_child(name, true, false) as Control
	if not _in_tree(control, name):
		return null
	return control

func _button(parent, name: String) -> Button:
	var button := _control(parent, name) as Button
	if not is_instance_valid(button):
		check(false, name + " must be a Button")
	return button

# v0.103: failed setup still releases our fixtures and restores the tutorial/theme globals.
func _finish(viewport: SubViewport, settings_viewport: SubViewport = null) -> int:
	if not _save_fixture.is_empty():
		Game.wait_save()
		Game._active_screen = String(_save_fixture["screen"])
		WorldGen.gen_size = String(_save_fixture["size"])
		CampaignWorld.presim_span_days = int(_save_fixture["history"])
		Monsters.new_world_creatures = bool(_save_fixture["creatures"])
		_save_fixture.clear()
	if is_instance_valid(viewport):
		viewport.queue_free()
	if is_instance_valid(settings_viewport):
		settings_viewport.queue_free()
	UiTheme.set_mobile_override(null)
	Game.tutorial_step = 0
	Game.tutorial_done = false
	print("test_tutorial_v103: %d failure(s)" % fails)
	return fails

# v0.103: do not reload an older file after a queued/refused/failed save.
func _save_checkpoint(what: String) -> bool:
	var before: Dictionary = Game.save_stats()
	# save_game() returns nothing on main: the write receipt (completed count, last_ok) is the proof.
	Game.save_game()
	Game.wait_save()
	var after: Dictionary = Game.save_stats()
	var ok: bool = bool(after.get("last_ok", false)) and int(after.get("completed", 0)) > int(before.get("completed", 0))
	check(ok, what + " receives a successful save receipt")
	return ok

# v0.103: use actual viewport picking, including the mouse events Godot emits for a touch.
# Same event order as test_touch_scroll_v083.gd; no pressed.emit() shortcuts.
func _click(viewport: Viewport, point: Vector2, touch: bool = false) -> void:
	if not _in_tree(viewport, "input viewport"):
		return
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.device = InputEvent.DEVICE_ID_EMULATION if touch else 0
	viewport.push_input(motion, true)
	for down in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.device = motion.device
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		mouse.pressed = down
		mouse.position = point
		mouse.global_position = point
		viewport.push_input(mouse, true)
		if touch:
			var finger := InputEventScreenTouch.new()
			finger.index = 0
			finger.pressed = down
			finger.position = point
			viewport.push_input(finger, true)

func _press(viewport: Viewport, button: Control, touch: bool = false) -> void:
	if not _in_tree(button, "pressed control"):
		return
	_click(viewport, button.get_global_transform_with_canvas() * (button.size * 0.5), touch)

# v0.103: every geometry failure reports actual viewport, target and hole numbers in named spaces.
func _geometry(viewport: Viewport, overlay, target) -> String:
	var target_name := "<missing or freed>"
	var target_rect := Rect2()
	var target_local := Rect2()
	var overlay_rect := Rect2()
	var overlay_position := Vector2.ZERO
	var hole := Rect2()
	if is_instance_valid(target):
		target_name = String(target.name)
		target_rect = target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)
	if is_instance_valid(overlay):
		overlay_rect = Rect2(Vector2.ZERO, overlay.size)
		overlay_position = overlay.position
		hole = overlay.highlight_rect()
		target_local = overlay.get_global_transform_with_canvas().affine_inverse() * target_rect
	return " [viewport_size=%s overlay_rect=%s overlay_position=%s target=%s target_rect(viewport)=%s target_rect(overlay)=%s hole_rect(overlay)=%s]" % [
		str(viewport.get_visible_rect().size), str(overlay_rect), str(overlay_position), target_name, str(target_rect), str(target_local), str(hole)]

# v0.103: every target, every requested size; assert a real hole, full dim coverage, and a non-overlapping box.
func _layouts(tree: SceneTree, viewport: SubViewport, overlay, target: Control, sizes: Array = SIZES) -> void:
	if not _in_tree(viewport, "layout viewport") or not _in_tree(overlay, "layout tutorial overlay") or not _in_tree(target, "highlight target"):
		return
	for sz in sizes:
		viewport.size = sz
		await _frames(tree, 4)
		await tree.create_timer(0.15).timeout
		if not _in_tree(overlay, "layout tutorial overlay") or not _in_tree(target, "highlight target"):
			return
		var geometry := _geometry(viewport, overlay, target)
		_in_tree(overlay.current_target(), "resolved highlight target for " + String(target.name) + geometry)
		var rect: Rect2 = overlay.highlight_rect()
		# v0.103: expected and reported target rects include the same canvas transform as the actual hole.
		var expected: Rect2 = overlay.get_global_transform_with_canvas().affine_inverse() * (target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size))
		check(overlay.size == viewport.get_visible_rect().size and overlay.position == Vector2.ZERO,
			"overlay fills the resized viewport at %s%s" % [str(sz), geometry])
		check(overlay.current_target() == target and rect.has_area() and rect.encloses(expected),
			"highlight encloses %s at %s%s" % [target.name, str(sz), geometry])
		check(rect.get_center().distance_to(expected.get_center()) <= 2.0 and rect.size.distance_to(expected.size) <= 18.0,
			"highlight matches only %s at %s%s" % [target.name, str(sz), geometry])
		var area := 0.0
		for blocker in overlay.blocker_rects():
			var br: Rect2 = blocker
			check(not br.intersects(rect), "dim leaves the entire cut-out open: blocker=%s%s" % [str(br), geometry])
			area += br.get_area()
		check(absf(area + rect.get_area() - overlay.size.x * overlay.size.y) < 2.0,
			"dim covers everywhere outside the hole: dim_area=%s full_area=%s%s" % [str(area), str(overlay.size.x * overlay.size.y), geometry])
		var box := overlay.get("_box") as Control
		if not _in_tree(box, "tutorial text box" + geometry):
			return
		var box_rect := Rect2(box.position, box.size)
		check(Rect2(Vector2.ZERO, overlay.size).encloses(box_rect) and not box_rect.intersects(rect),
			"text and navigation stay on screen and clear of the target: box_rect=%s%s" % [str(box_rect), geometry])
		for name in ["TutorialBack", "TutorialNext", "TutorialSkip"]:
			var button: Control = _button(overlay, name)
			var button_rect := button.get_global_rect() if is_instance_valid(button) else Rect2()
			check(button != null and box.get_global_rect().encloses(button.get_global_rect()),
				"navigation fits inside the text box: button=%s button_rect=%s box_rect=%s%s" % [name, str(button_rect), str(box.get_global_rect()), geometry])

func run(tree: SceneTree) -> int:
	UiTheme.set_mobile_override(false)   # v0.103: phone theme gets its own checks below.
	var tut_script: Script = load("res://campaign/tutorial.gd") as Script
	var overlay_script: Script = load("res://ui/tutorial_overlay.gd") as Script
	check(tut_script != null and overlay_script != null, "tutorial scripts load")
	if tut_script == null or overlay_script == null:
		return _finish(null)

	# 1. The shipped steps are valid data.
	var shipped: Array = tut_script.load_steps()
	check(not shipped.is_empty(), "data/tutorial.json loads with steps")
	for entry in shipped:
		var s: Dictionary = entry
		var d: Dictionary = s.get("done", {})
		check(String(s.get("text", "")) != "" and ["next", "button", "screen", "state"].has(String(d.get("kind", ""))),
			"shipped step '%s' has text and a known done kind" % String(s.get("id", "?")))

	# 2. A host screen with three anchored buttons, in a viewport we can resize.
	var viewport := SubViewport.new()
	viewport.size = SIZES[0]
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# v0.103: runner._ready() still has a busy root on the first test; attach after that stack unwinds.
	tree.root.add_child.call_deferred(viewport)
	await _frames(tree, 2)
	if not _in_tree(viewport, "sample viewport"):
		return _finish(viewport)
	var host := InputProbe.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE   # v0.103: raw-touch leak checks need an unhandled path.
	viewport.add_child(host)
	var presses := {"StepOne": 0, "outside": 0}
	var b1 := Button.new()
	b1.name = "StepOne"
	b1.text = "One"
	b1.position = Vector2(24, 24)
	b1.size = Vector2(160, 52)
	b1.pressed.connect(func(): presses["StepOne"] = int(presses["StepOne"]) + 1)
	host.add_child(b1)
	var b2 := Button.new()
	b2.name = "StepTwo"
	b2.text = "Two"
	b2.anchor_left = 1.0; b2.anchor_top = 1.0; b2.anchor_right = 1.0; b2.anchor_bottom = 1.0
	b2.offset_left = -184.0; b2.offset_top = -76.0; b2.offset_right = -24.0; b2.offset_bottom = -24.0
	host.add_child(b2)
	var b3 := Button.new()
	b3.name = "StepThree"
	b3.text = "Three"
	b3.set_meta("tutorial_anchor", "StepThree")
	b3.anchor_left = 0.5; b3.anchor_top = 0.5; b3.anchor_right = 0.5; b3.anchor_bottom = 0.5
	b3.offset_left = -80.0; b3.offset_top = -26.0; b3.offset_right = 80.0; b3.offset_bottom = 26.0
	host.add_child(b3)
	var outside := Button.new()   # v0.103: a live control under the dim must never receive input.
	outside.name = "Outside"
	outside.position = Vector2(400, 24)
	outside.size = Vector2(160, 52)
	outside.pressed.connect(func(): presses["outside"] = int(presses["outside"]) + 1)
	host.add_child(outside)

	# 3. Run the sample tutorial over the host.
	Game.tutorial_step = 0
	Game.tutorial_done = false
	var tut = tut_script.new()
	tut.setup(SAMPLE)
	tut.bind_game(Game)
	tut.start(0)
	var overlay = overlay_script.open(host, tut)
	var state := {"ready": false}
	await _frames(tree, 4)
	if not _in_tree(overlay, "sample tutorial overlay"):
		return _finish(viewport)
	overlay.state_of = func(key: String): return state.get(key)

	var next_button: Button = _button(overlay, "TutorialNext")
	var back_button: Button = _button(overlay, "TutorialBack")
	check(next_button != null and back_button != null, "overlay has Next and Back buttons")
	check(_button(overlay, "TutorialSkip") != null, "overlay has a Skip tutorial button")

	# 4. v0.103: geometry plus real input, with negative controls to prevent a vacuous pass.
	await _layouts(tree, viewport, overlay, b1)
	var touches_before: int = host.touches
	var downs_before: int = host.touch_downs
	var ups_before: int = host.touch_ups
	_press(viewport, outside)
	_press(viewport, outside, true)
	_click(viewport, Vector2(24, viewport.size.y - 24), true)
	check(int(presses["outside"]) == 0 and tut.index == 0, "mouse and touch outside the hole are blocked")
	check(host.touches == touches_before, "raw touch does not leak into unhandled screen gestures")
	check(host.touch_downs == downs_before and host.touch_ups == ups_before, "touches under the dim never enter the host's raw input")

	# 5. Step one waits for its button: Next is disabled and cannot advance it.
	check(tut.index == 0 and is_instance_valid(next_button) and next_button.disabled, "step 1 waits: Next disabled on a button step")
	check(not tut.next_step() and tut.index == 0, "step 1 waits: next_step() refuses before the action")
	check(not tut.notify_button("StepTwo") and tut.index == 0, "the wrong button does not complete a button step")
	_press(viewport, next_button)
	check(tut.index == 0, "the disabled Next button cannot bypass an action")
	_press(viewport, b1)
	await _frames(tree, 2)
	check(int(presses["StepOne"]) == 1, "the highlighted button itself still receives the press")
	check(tut.index == 1, "pressing the anchored button advances to step 2")
	check(Game.tutorial_step == 1 and not Game.tutorial_done, "progress mirrors onto Game (step 1, not done)")

	# 6. Back returns, the button advances again, then step two waits for its screen.
	await _layouts(tree, viewport, overlay, b2)
	_press(viewport, back_button)
	await _frames(tree, 2)
	check(tut.index == 0, "Back returns to step 1")
	downs_before = host.touch_downs
	ups_before = host.touch_ups
	_press(viewport, b1, true)
	await _frames(tree, 2)
	check(tut.index == 1 and int(presses["StepOne"]) == 2, "touch through the cut-out advances exactly once after Back")
	check(host.touch_downs == downs_before + 1 and host.touch_ups == ups_before + 1,
		"a touch release reaches the host even when the emulated click changes steps first")
	_press(viewport, b2, true)
	check(tut.index == 1, "pressing a control does not replace the required screen action")
	check(not tut.notify_button("StepOne") and not tut.next_step(), "a screen step rejects buttons and Next")
	Game.screen_changed.emit("town")
	await _frames(tree, 2)
	check(tut.index == 1, "step 2 waits: a different screen does not count")
	Game.screen_changed.emit("map")
	await _frames(tree, 2)
	check(tut.index == 2, "opening the named screen advances to step 3")
	await _layouts(tree, viewport, overlay, b3)
	check(not tut.notify_state("wrong_key", true) and not tut.next_step(), "a state step rejects the wrong state key and Next")

	# 7. Step three waits for its state, then finishes and the overlay closes.
	await tree.create_timer(0.35).timeout
	check(tut.index == 2 and tut.active, "step 3 waits while the state is not reached")
	state["ready"] = true
	await tree.create_timer(0.35).timeout
	check(tut.is_finished and not tut.was_skipped and not tut.active, "reaching the state finishes the tutorial")
	check(Game.tutorial_done, "Game.tutorial_done is set at the end")
	await _frames(tree, 3)
	check(host.get_node_or_null("TutorialOverlay") == null, "the overlay closes when the tutorial ends")
	_press(viewport, outside)
	_press(viewport, outside, true)
	_click(viewport, Vector2(24, viewport.size.y - 24), true)
	check(int(presses["outside"]) == 2, "positive control: mouse and touch work again after completion")
	check(host.touches > touches_before, "positive control: raw touches reach the screen with no active tutorial")

	# 8. Skip ends a fresh run; Replay starts it over.
	var tut2 = tut_script.new()
	tut2.setup(SAMPLE)
	tut2.bind_game(Game)
	tut2.start(0)
	var overlay2 = overlay_script.open(host, tut2)
	await _frames(tree, 3)
	if not _in_tree(overlay2, "Skip tutorial overlay"):
		return _finish(viewport)
	var skip_button: Button = _button(overlay2, "TutorialSkip")
	_press(viewport, skip_button, true)
	await _frames(tree, 3)
	check(tut2.is_finished and tut2.was_skipped, "Skip tutorial finishes the run as skipped")
	check(Game.tutorial_done, "Skip persists the completed flag")
	check(host.get_node_or_null("TutorialOverlay") == null, "the overlay closes after Skip")
	tut2.replay()
	check(tut2.active and not tut2.is_finished and tut2.index == 0, "Replay restarts at step 1")
	check(Game.tutorial_step == 0 and not Game.tutorial_done, "Replay resets saved progress")
	# v0.103: Next/Done and Back also work through real GUI input on explanatory steps.
	tut2.setup([
		{"anchor": "StepOne", "text": "Read then continue.", "done": "next"},
		{"anchor": "StepTwo", "text": "Finish.", "done": "next"},
	])
	tut2.start()
	overlay2 = overlay_script.open(host, tut2)
	await _frames(tree, 4)
	if not _in_tree(overlay2, "explanatory tutorial overlay"):
		return _finish(viewport)
	_press(viewport, _button(overlay2, "TutorialNext"))
	check(tut2.index == 1, "Next advances an explanatory step")
	_press(viewport, _button(overlay2, "TutorialBack"), true)
	check(tut2.index == 0, "touch Back returns to an explanatory step")
	_press(viewport, _button(overlay2, "TutorialNext"))
	_press(viewport, _button(overlay2, "TutorialNext"), true)
	await _frames(tree, 3)
	check(tut2.is_finished and not tut2.was_skipped and Game.tutorial_done, "Done completes an explanatory tutorial")

	# 9. Use the native finalized campaign and Begin path for the save/load checks.
	_save_fixture = {"screen": Game._active_screen, "size": WorldGen.gen_size,
		"history": CampaignWorld.presim_span_days, "creatures": Monsters.new_world_creatures}
	var campaign_ok: bool = await DevTools.start_world(tree, Game.SAVE_PATH)
	check(campaign_ok, "the Normal/one-day tutorial save campaign loads")
	if not campaign_ok:
		return _finish(viewport)
	var house_town: String = DevTools.choose_house(Game)
	check(house_town != "", "the tutorial save campaign begins with a real household")
	if house_town == "":
		return _finish(viewport)
	Game._active_screen = "settings"
	var eligible: bool = MobileApp.can_autosave()
	check(eligible, "the finalized tutorial campaign is eligible to save in Settings")
	if not eligible:
		return _finish(viewport)
	# Progress survives save/load; missing tutorial fields also default in schema 2.
	Game.tutorial_step = 1
	Game.tutorial_done = false
	if not _save_checkpoint("Tutorial progress"):
		return _finish(viewport)
	Game.tutorial_step = 0
	Game.tutorial_done = true
	check(Game.load_game(), "the save reloads")
	check(Game.tutorial_step == 1 and not Game.tutorial_done, "tutorial progress survives save and load")
	var resumed = tut_script.new()   # v0.103: use the public resume API, not just the saved scalar values.
	resumed.setup(SAMPLE)
	resumed.bind_game(Game)
	check(Game.tutorial_step == 1 and not Game.tutorial_done, "binding preserves the loaded progress")
	resumed.start_saved()
	check(resumed.active and resumed.index == 1, "a new engine resumes the loaded step")
	resumed.skip()
	if not _save_checkpoint("Skipped tutorial"):
		return _finish(viewport)
	Game.tutorial_done = false
	check(Game.load_game(), "the skipped tutorial save reloads")
	var finished = tut_script.new()
	finished.setup(SAMPLE)
	finished.bind_game(Game)
	finished.start_saved()
	check(Game.tutorial_done and not finished.active and finished.is_finished, "a skipped tutorial stays finished after load and bind")
	var old_tree: Dictionary = Game._save_tree()
	old_tree.erase("tutorial")
	var receipt: Dictionary = Game._write_save(Game.SAVE_PATH, old_tree)
	check(bool(receipt.get("ok", false)), "the old-style save (no tutorial field) writes")
	if not bool(receipt.get("ok", false)):
		return _finish(viewport)
	Game.tutorial_step = 5
	Game.tutorial_done = true
	check(Game.load_game(), "an old save without the tutorial field loads")
	check(Game.tutorial_step == 0 and not Game.tutorial_done, "missing tutorial progress defaults to step 0, not done")

	# 10. Settings has Replay tutorial, and it opens the overlay.
	var settings_viewport := SubViewport.new()
	settings_viewport.size = Vector2i(1280, 720)
	settings_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child.call_deferred(settings_viewport)   # v0.103: use the same safe fixture attachment.
	await _frames(tree, 2)
	if not _in_tree(settings_viewport, "Settings viewport"):
		return _finish(viewport, settings_viewport)
	var settings_scene := load("res://ui/settings.tscn") as PackedScene
	check(settings_scene != null, "Settings scene loads")
	if settings_scene == null:
		return _finish(viewport, settings_viewport)
	var settings_screen := settings_scene.instantiate() as Control
	settings_viewport.add_child(settings_screen)
	await _frames(tree, 4)
	if not _in_tree(settings_screen, "Settings screen"):
		return _finish(viewport, settings_viewport)
	check(settings_screen.get_node_or_null("TutorialOverlay") == null, "Settings is unobstructed with default/old-save progress")
	var replay_button: Button = _button(settings_screen, "ReplayTutorial")
	check(replay_button != null and replay_button.text == "Replay tutorial", "Settings shows Replay tutorial")
	if replay_button != null:
		_press(settings_viewport, replay_button)
		await _frames(tree, 4)
		var settings_overlay: Node = settings_screen.get_node_or_null("TutorialOverlay")
		check(settings_overlay != null, "Replay tutorial opens the tutorial overlay")
		if _in_tree(settings_overlay, "Settings Replay tutorial overlay"):
			check(Game.tutorial_step == 0 and not Game.tutorial_done, "Settings Replay resets completed progress")
			for i in shipped.size():
				if i > 0:
					_press(settings_viewport, _button(settings_overlay, "TutorialNext"))
				var anchor: String = String(shipped[i]["anchor"])
				var target: Control = _control(settings_screen, anchor)
				check(target != null, "the shipped anchor %s exists in Settings" % anchor)
				if target != null:
					await _layouts(tree, settings_viewport, settings_overlay, target)
			var s_skip: Button = _button(settings_overlay, "TutorialSkip")
			_press(settings_viewport, s_skip, true)
			await _frames(tree, 3)
			check(settings_screen.get_node_or_null("TutorialOverlay") == null, "Skip closes the replayed tutorial")
	# v0.103: an actual Settings reopen resumes loaded progress, while a finished run stays closed.
	Game.tutorial_step = 1
	Game.tutorial_done = false
	if not _save_checkpoint("Settings resume"):
		return _finish(viewport, settings_viewport)
	Game.tutorial_step = 0
	Game.tutorial_done = true
	check(Game.load_game(), "Settings resume fixture loads")
	settings_screen.queue_free()
	await _frames(tree, 2)
	settings_screen = settings_scene.instantiate() as Control
	settings_viewport.add_child(settings_screen)
	await _frames(tree, 6)
	if not _in_tree(settings_screen, "reopened Settings screen"):
		return _finish(viewport, settings_viewport)
	var resumed_overlay: Node = settings_screen.get_node_or_null("TutorialOverlay")
	check(resumed_overlay != null, "Settings reopens the unfinished saved tutorial")
	if _in_tree(resumed_overlay, "Settings resumed tutorial overlay"):
		var resumed_tutorial = resumed_overlay.get("tutorial")
		check(resumed_tutorial != null and resumed_tutorial.index == 1, "Settings resumes the correct saved step")
		_press(settings_viewport, _button(resumed_overlay, "TutorialSkip"))
		await _frames(tree, 3)
	settings_screen.queue_free()
	await _frames(tree, 2)
	settings_screen = settings_scene.instantiate() as Control
	settings_viewport.add_child(settings_screen)
	await _frames(tree, 4)
	if not _in_tree(settings_screen, "finished-tutorial Settings screen"):
		return _finish(viewport, settings_viewport)
	check(settings_screen.get_node_or_null("TutorialOverlay") == null, "a skipped tutorial does not reopen over Settings")

	# v0.103: inactive/retained overlays, clipping, hidden duplicate anchors, and honest button identity.
	var idle = tut_script.new()
	idle.setup([{"anchor": "Clipped", "text": "Visible part only.", "done": "next"}])
	var clip := Control.new()
	clip.position = Vector2(400, 200)
	clip.size = Vector2(300, 140)
	clip.clip_contents = true
	host.add_child(clip)
	var clipped := Button.new()
	clipped.name = "Clipped"
	clipped.position = Vector2(0, -20)
	clipped.size = Vector2(160, 52)
	clip.add_child(clipped)
	var retained = overlay_script.open(host, idle)
	await _frames(tree, 4)
	if not _in_tree(retained, "retained tutorial overlay"):
		return _finish(viewport, settings_viewport)
	retained.auto_free = false
	var before: int = int(presses["outside"])
	_press(viewport, outside)
	check(not retained.visible and int(presses["outside"]) == before + 1, "an unstarted overlay cannot intercept a screen")
	idle.start()
	await _frames(tree, 4)
	var clipped_rect: Rect2 = retained.highlight_rect()
	check(clipped_rect.has_area() and clip.get_global_rect().encloses(clipped_rect),
		"cut-out respects its clipping ancestor: clip_rect=%s%s" % [str(clip.get_global_rect()), _geometry(viewport, retained, clipped)])
	clipped.position.y = 160
	await tree.create_timer(0.15).timeout
	check(not retained.highlight_rect().has_area(), "a fully clipped anchor leaves no input hole" + _geometry(viewport, retained, clipped))
	clip.hide()
	var alias := Button.new()
	alias.set_meta("tutorial_anchor", "Clipped")
	alias.position = Vector2(24, 24)
	alias.size = Vector2(160, 52)
	host.add_child(alias)
	host.move_child(retained, host.get_child_count() - 1)
	await tree.create_timer(0.15).timeout
	check(retained.current_target() == alias, "hidden duplicate anchors do not shadow a visible control" + _geometry(viewport, retained, alias))
	idle.skip()
	before = int(presses["outside"])
	_press(viewport, outside, true)
	check(not retained.visible and int(presses["outside"]) == before + 1, "auto_free=false releases input on completion")
	retained.queue_free()
	alias.queue_free()
	clip.queue_free()
	await _frames(tree, 2)
	var mismatch = tut_script.new()
	mismatch.setup([{"anchor": "StepOne", "text": "Wrong done anchor.", "done": {"kind": "button", "anchor": "StepTwo"}}])
	mismatch.start()
	var mismatch_overlay = overlay_script.open(host, mismatch)
	await _frames(tree, 4)
	if not _in_tree(mismatch_overlay, "mismatched-action tutorial overlay"):
		return _finish(viewport, settings_viewport)
	check(mismatch_overlay.current_target() == b1, "the mismatched completion fixture highlights the real StepOne" + _geometry(viewport, mismatch_overlay, b1))
	before = int(presses["StepOne"])
	_press(viewport, b1)
	check(mismatch.active and int(presses["StepOne"]) == before + 1, "pressing StepOne cannot masquerade as pressing StepTwo")
	mismatch.skip()
	await _frames(tree, 2)

	# v0.103: create the overlay with the real mobile theme and 96px buttons, not just a wider desktop viewport.
	UiTheme.set_mobile_override(true)
	var phone = tut_script.new()
	phone.setup(SAMPLE)
	phone.start()
	var phone_overlay = overlay_script.open(host, phone)
	await _frames(tree, 4)
	if not _in_tree(phone_overlay, "phone tutorial overlay"):
		return _finish(viewport, settings_viewport)
	for i in SAMPLE.size():
		phone.start(i)
		await _layouts(tree, viewport, phone_overlay, [b1, b2, b3][i], [SIZES[2]])
	var phone_skip: Button = _button(phone_overlay, "TutorialSkip")
	check(is_instance_valid(phone_skip) and phone_skip.custom_minimum_size.y >= 96.0,
		"phone navigation retains the project tap target size" + _geometry(viewport, phone_overlay, phone_skip))
	_press(viewport, phone_skip, true)
	await _frames(tree, 3)
	check(phone.was_skipped, "touch Skip works with the mobile theme")
	UiTheme.set_mobile_override(null)

	# v0.103: a screen-opening action must survive the old screen being freed, for screen AND button steps.
	var old_main: Node = Game.main
	var old_screen: String = Game._active_screen
	var old_params: Dictionary = Game.screen_params
	for kind in ["screen", "button"]:
		var driver := ScreenDriver.new()
		viewport.add_child(driver)
		driver.current = Control.new()
		driver.current.set_anchors_preset(Control.PRESET_FULL_RECT)
		driver.add_child(driver.current)
		var go := Button.new()
		go.name = "Go"
		go.position = Vector2(24, 24)
		go.size = Vector2(160, 52)
		go.pressed.connect(func(): Game.goto("map"))
		driver.current.add_child(go)
		Game.main = driver
		var moving = tut_script.new()
		moving.setup([
			{"anchor": "Go", "text": "Open map.", "done": {"kind": kind, "screen": "map"}},
			{"anchor": "NextScreen", "text": "New screen.", "done": {"kind": "button"}},
		])
		moving.start()
		var moving_overlay = overlay_script.open(driver.current, moving)
		await _frames(tree, 4)
		_in_tree(moving_overlay, "%s navigation overlay before Game.goto()" % kind)
		_press(viewport, go)
		await _frames(tree, 4)
		check(moving.index == 1 and is_instance_valid(moving_overlay),
			"a %s action survives real Game.goto(): active_screen=%s%s" % [kind, Game._active_screen, _geometry(viewport, moving_overlay, go)])
		if _in_tree(moving_overlay, "%s navigation overlay after Game.goto()" % kind):
			var destination: Button = _button(driver.current, "NextScreen")
			check(is_instance_valid(destination) and moving_overlay.current_target() == destination,
				"the new screen's actual control is highlighted" + _geometry(viewport, moving_overlay, destination))
			_press(viewport, destination, true)
			check(moving.is_finished, "input reaches the destination after screen replacement" + _geometry(viewport, moving_overlay, destination))
		driver.queue_free()
		await _frames(tree, 3)
	Game.main = old_main
	Game._active_screen = old_screen
	Game.screen_params = old_params

	return _finish(viewport, settings_viewport)
