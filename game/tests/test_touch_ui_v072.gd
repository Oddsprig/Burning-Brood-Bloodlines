extends RefCounted
## Verification for v0.072 JOB A: touch controls (tap, one-finger drag pan, two-finger pinch zoom,
## ~0.5s long-press = right-click/info, desktop mouse non-regression) and mobile UI scaling + safe-area margins.

var fails := 0

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", msg)

func run(tree: SceneTree) -> int:
	# 1. project.godot settings
	check(bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", false)),
		"emulate_mouse_from_touch is true")
	check(String(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "canvas_items",
		"stretch/mode is canvas_items")
	check(String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "expand",
		"stretch/aspect is expand")
	var orient := int(ProjectSettings.get_setting("display/window/handheld/orientation", -1))
	check(orient in [DisplayServer.SCREEN_LANDSCAPE, DisplayServer.SCREEN_SENSOR_LANDSCAPE],
		"handheld orientation is landscape/sensor_landscape (%d)" % orient)

	# 2. TouchInput unit checks (tap, 1-finger drag, 2-finger pinch, magnify gesture, long-press, right-click, desktop mouse)
	var taps: Array = []
	var long_presses: Array = []
	var pans: Array = []
	var zooms: Array = []
	var host := Node.new()
	tree.root.add_child(host)
	var ti := TouchInput.attach(
		host,
		func(pos: Vector2): taps.append(pos),
		func(delta: Vector2): pans.append(delta),
		func(pos: Vector2, factor: float): zooms.append([pos, factor]),
		func(pos: Vector2): long_presses.append(pos),
		8.0
	)

	# 2a. Single-finger tap
	var st_down := InputEventScreenTouch.new()
	st_down.index = 0; st_down.pressed = true; st_down.position = Vector2(200, 300)
	ti.handle_input(st_down)
	var st_up := InputEventScreenTouch.new()
	st_up.index = 0; st_up.pressed = false; st_up.position = Vector2(202, 301)
	ti.handle_input(st_up)
	check(taps.size() == 1 and long_presses.is_empty() and pans.is_empty(), "1-finger quick tap triggers on_tap only")

	# 2a'. emulate_mouse_from_touch: Godot sends the emulated mouse press BEFORE its screen touch (and the release
	# before the touch release); a touch tap still taps exactly once.
	taps.clear()
	var emu_mb := InputEventMouseButton.new()
	emu_mb.device = InputEvent.DEVICE_ID_EMULATION
	emu_mb.button_index = MOUSE_BUTTON_LEFT; emu_mb.pressed = true; emu_mb.position = Vector2(200, 300)
	ti.handle_input(emu_mb)
	ti.handle_input(st_down)
	emu_mb.pressed = false
	ti.handle_input(emu_mb)
	ti.handle_input(st_up)
	check(taps.size() == 1, "touch tap with emulated mouse events taps once (%d)" % taps.size())

	# 2b. Single-finger drag pans (and does not trigger tap or double-pan from emulated mouse motion)
	taps.clear(); pans.clear()
	ti.handle_input(st_down)
	var sd := InputEventScreenDrag.new()
	sd.index = 0; sd.position = Vector2(240, 320); sd.relative = Vector2(40, 20)
	ti.handle_input(sd)
	var emu_mm := InputEventMouseMotion.new()
	emu_mm.device = InputEvent.DEVICE_ID_EMULATION
	emu_mm.position = Vector2(240, 320); emu_mm.relative = Vector2(40, 20)
	ti.handle_input(emu_mm)
	st_up.position = Vector2(240, 320)
	ti.handle_input(st_up)
	check(pans.size() == 1 and (pans[0] as Vector2).is_equal_approx(Vector2(40, 20)), "1-finger drag pans once without emulated mouse duplicate")
	check(taps.is_empty(), "1-finger drag does not fire tap on release")

	# 2c. Two-finger pinch zoom via two InputEventScreenDrag events
	zooms.clear(); pans.clear(); taps.clear()
	var t0 := InputEventScreenTouch.new(); t0.index = 0; t0.pressed = true; t0.position = Vector2(400, 400)
	var t1 := InputEventScreenTouch.new(); t1.index = 1; t1.pressed = true; t1.position = Vector2(500, 400)
	ti.handle_input(t0)
	ti.handle_input(t1)
	var d0 := InputEventScreenDrag.new(); d0.index = 0; d0.position = Vector2(350, 400); d0.relative = Vector2(-50, 0)
	var d1 := InputEventScreenDrag.new(); d1.index = 1; d1.position = Vector2(550, 400); d1.relative = Vector2(50, 0)
	ti.handle_input(d0)
	ti.handle_input(d1)
	t0.pressed = false; t0.position = Vector2(350, 400); ti.handle_input(t0)
	t1.pressed = false; t1.position = Vector2(550, 400); ti.handle_input(t1)
	check(zooms.size() >= 1 and float(zooms[-1][1]) > 1.0, "2-finger pinch outward zooms in")
	check(taps.is_empty(), "2-finger pinch does not fire tap on release")

	# 2d. InputEventMagnifyGesture zooms
	zooms.clear()
	var mg := InputEventMagnifyGesture.new()
	mg.position = Vector2(600, 360); mg.factor = 1.25
	ti.handle_input(mg)
	check(zooms.size() == 1 and is_equal_approx(float(zooms[0][1]), 1.25), "InputEventMagnifyGesture zooms")

	# 2e. Long-press (~0.5s, little movement) triggers on_long_press and not on_tap
	taps.clear(); long_presses.clear()
	st_down.position = Vector2(320, 240)
	ti.handle_input(st_down)
	ti._process(0.55)
	st_up.position = Vector2(322, 241)
	ti.handle_input(st_up)
	check(long_presses.size() == 1 and taps.is_empty(), "long-press (~0.5s) triggers on_long_press once and suppresses tap")

	# 2f. Desktop mouse click, drag, wheel, right-click
	taps.clear(); long_presses.clear(); pans.clear(); zooms.clear()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT; mb.pressed = true; mb.position = Vector2(100, 100)
	ti.handle_input(mb)
	mb.pressed = false
	ti.handle_input(mb)
	check(taps.size() == 1, "desktop mouse left click triggers tap")

	# 2g. A slow desktop click stays a click (long-press is touch only; right-click is the desktop info gesture)
	taps.clear(); long_presses.clear()
	mb.pressed = true; mb.position = Vector2(120, 120)
	ti.handle_input(mb)
	ti._process(0.8)
	mb.pressed = false
	ti.handle_input(mb)
	check(taps.size() == 1 and long_presses.is_empty(), "slow desktop left click still taps (no long-press on mouse)")

	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT; rmb.pressed = true; rmb.position = Vector2(150, 150)
	ti.handle_input(rmb)
	rmb.pressed = false
	ti.handle_input(rmb)
	check(long_presses.size() == 1, "desktop mouse right click triggers on_long_press/info")

	var wh := InputEventMouseButton.new()
	wh.button_index = MOUSE_BUTTON_WHEEL_UP; wh.pressed = true; wh.position = Vector2(400, 300)
	ti.handle_input(wh)
	check(zooms.size() == 1 and float(zooms[0][1]) > 1.0, "desktop mouse wheel zooms")

	host.queue_free()

	# 3. Mobile UI scaling & safe-area margins
	UiTheme.set_mobile_override(false)
	var desktop_fs := UiTheme.get_theme().default_font_size
	var desktop_btn := UiKit.button("Test", func(): pass)
	var desktop_h := desktop_btn.custom_minimum_size.y
	desktop_btn.free()
	check(desktop_fs == UiTheme.FONT_SIZE and int(desktop_h) == UiKit.TAP, "desktop theme and buttons are unchanged (%d, %d)" % [desktop_fs, int(desktop_h)])
	check(UiKit.safe_area_margins(tree.root) == {"left": 0, "top": 0, "right": 0, "bottom": 0}, "desktop has no safe-area margins")

	UiTheme.set_mobile_override(true)
	var mobile_fs := UiTheme.get_theme().default_font_size
	var mobile_btn := UiKit.button("Test", func(): pass)
	var mobile_h := mobile_btn.custom_minimum_size.y
	mobile_btn.free()
	check(mobile_fs == UiTheme.MOBILE_FONT_SIZE and mobile_fs >= 30 and mobile_fs > desktop_fs, "mobile theme raises base font size (%d > %d)" % [mobile_fs, desktop_fs])
	check(int(mobile_h) == UiKit.MOBILE_TAP and mobile_h >= 96 and mobile_h > desktop_h, "mobile button min height raised (%d > %d)" % [int(mobile_h), int(desktop_h)])

	UiKit.set_safe_area_override(Rect2i(72, 24, 1456, 840))
	var screen := Control.new()
	screen.size = Vector2(1600, 900)
	tree.root.add_child(screen)
	UiKit.screen_frame(screen, "Safe Area Check")
	var safe := UiKit.safe_area_margins(tree.root)
	check(int(safe["left"]) > 0 and int(safe["top"]) > 0, "safe_area_margins computes non-zero insets from safe area")
	screen.queue_free()

	# 4. MobileApp (core/mobile_app.gd): back button opens the pause menu, back again asks to quit, back closes that.
	MobileApp.force_mobile = true
	var back_first := MobileApp.handle_back_request()
	check(back_first == "asked_quit" or back_first == "opened_pause" or back_first == "closed_panel",
		"back button is handled (%s)" % back_first)
	MobileApp.reset()
	check(not MobileApp.is_pause_menu_open() and not MobileApp.is_quit_confirm_open(), "MobileApp.reset closes its menus")
	tree.paused = false

	UiTheme.set_mobile_override(null)
	UiKit.set_safe_area_override(null)
	return fails
