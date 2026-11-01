extends RefCounted
## Verification for v0.083: drag-anywhere scrolling on phones (ui/touch_scroll.gd). Phone input is pushed through the
## real viewport (push_input) in the order a phone sends it with emulate_mouse_from_touch: the emulated mouse event
## first, then its screen touch / drag. Checks: a drag on a list scrolls it and flings to a clamped stop, a tap on a
## row presses it without scrolling, a drag that starts on a row does not press it, a tap on a flinging list only
## stops it, the map/battle TouchInput still pans and long-presses outside lists and does not pan under one, phone
## scrollbars are slim, and the desktop (no mobile override) does not drag-scroll.

var fails := 0
var tree: SceneTree

func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		printerr("FAIL: ", msg)

func touch_down(pos: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT
	mb.pressed = true
	mb.position = pos
	mb.global_position = pos
	tree.root.push_input(mb, true)
	var st := InputEventScreenTouch.new()
	st.index = 0
	st.pressed = true
	st.position = pos
	tree.root.push_input(st, true)

func touch_move(from: Vector2, to: Vector2, steps: int = 8) -> Vector2:
	var at := from
	for i in steps:
		var nxt := from.lerp(to, float(i + 1) / float(steps))
		var mm := InputEventMouseMotion.new()
		mm.device = InputEvent.DEVICE_ID_EMULATION
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		mm.position = nxt
		mm.global_position = nxt
		mm.relative = nxt - at
		tree.root.push_input(mm, true)
		var sd := InputEventScreenDrag.new()
		sd.index = 0
		sd.position = nxt
		sd.relative = nxt - at
		tree.root.push_input(sd, true)
		at = nxt
	return at

func touch_up(pos: Vector2) -> void:
	var mb := InputEventMouseButton.new()
	mb.device = InputEvent.DEVICE_ID_EMULATION
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = false
	mb.position = pos
	mb.global_position = pos
	tree.root.push_input(mb, true)
	var st := InputEventScreenTouch.new()
	st.index = 0
	st.pressed = false
	st.position = pos
	tree.root.push_input(st, true)

func run(t: SceneTree) -> int:
	tree = t
	await t.process_frame
	var ts: TouchScroll = MobileApp.touch_scroll
	check(ts != null and ts.is_inside_tree(), "MobileApp owns the TouchScroll controller")
	if ts == null:
		return fails

	# 1. Phone scrollbars are slim; the desktop bar is unchanged.
	UiTheme.set_mobile_override(false)
	var desk_w := UiTheme.get_theme().get_stylebox("grabber", "VScrollBar").get_minimum_size().x
	UiTheme.set_mobile_override(true)
	var phone_w := UiTheme.get_theme().get_stylebox("grabber", "VScrollBar").get_minimum_size().x
	check(phone_w <= 8.0 and phone_w < desk_w, "phone scrollbar is slim (%.0f px, desktop %.0f px)" % [phone_w, desk_w])

	# A 500 x 400 list of 20 phone rows; the host ignores the mouse so presses beside the list reach _unhandled_input.
	var host := Control.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.theme = UiTheme.get_theme()
	host.size = Vector2(1600, 900)
	t.root.add_child(host)
	var sc := UiKit.scroll()
	sc.position = Vector2(100, 100)
	sc.size = Vector2(500, 400)
	host.add_child(sc)
	var list := UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var pressed: Array = []
	var rows: Array = []
	for i in 20:
		var b := UiKit.button("Row %d" % i, func(): pressed.append(i), "Row")
		list.add_child(b)
		rows.append(b)
	# The map/battle camera stand-in: a TouchInput fed from _unhandled_input, as world_map.gd and battle.gd do.
	var fwd_src := GDScript.new()
	fwd_src.source_code = "extends Node\nvar ti\nfunc _unhandled_input(e: InputEvent) -> void:\n\tif ti != null:\n\t\tti.handle_input(e)\n"
	fwd_src.reload()
	var fwd: Node = fwd_src.new()
	t.root.add_child(fwd)
	var pans: Array = []
	var long_presses: Array = []
	var ti := TouchInput.attach(fwd, func(_p: Vector2): pass, func(d: Vector2): pans.append(d),
		func(_p: Vector2, _f: float): pass, func(p: Vector2): long_presses.append(p), 8.0)
	fwd.set("ti", ti)
	await t.process_frame
	await t.process_frame
	# Headless has no pointer to hover with; a phone's emulated press hovers the row it lands on.
	for b in rows:
		(b as Button).notification(Control.NOTIFICATION_MOUSE_ENTER)
	var vbar := sc.get_v_scroll_bar()
	var max_scroll := vbar.max_value - vbar.page
	check(max_scroll > 400.0, "the test list is taller than its view (%.0f)" % max_scroll)
	check(TouchScroll.scroll_chain(rows[1]).has(sc), "a row's scroll chain finds its ScrollContainer")
	check(ts.control_at((rows[1] as Button).get_global_rect().get_center()) == rows[1], "control_at finds the row under the finger")

	# 2a. A quick tap on a row presses it and does not scroll.
	var row1: Vector2 = (rows[1] as Button).get_global_rect().get_center()
	touch_down(row1)
	touch_up(row1)
	check(pressed == [1], "a tap on a row presses it (%s)" % str(pressed))
	check(sc.scroll_vertical == 0 and not ts.is_scrolling(), "a tap does not scroll")

	# 2b. A finger that wobbles under the threshold is still a tap.
	touch_down(row1)
	var wob := touch_move(row1, row1 + Vector2(3, -5), 2)
	touch_up(wob)
	check(pressed == [1, 1], "a tap that moves under the threshold still presses (%s)" % str(pressed))
	check(sc.scroll_vertical == 0, "a wobble under the threshold does not scroll (%d)" % sc.scroll_vertical)

	# 2c. A drag that starts on a row scrolls the list, and the row does not fire on release.
	var row2: Vector2 = (rows[2] as Button).get_global_rect().get_center()
	touch_down(row2)
	var end := touch_move(row2, row2 + Vector2(0, -220))
	check(ts.is_scrolling(), "a drag past the threshold becomes a scroll")
	check(sc.scroll_vertical >= 150 and sc.scroll_vertical <= 230, "the list follows the finger (%d for 220 px)" % sc.scroll_vertical)
	check(pans.is_empty(), "the camera does not pan under a list drag (%d pans)" % pans.size())
	touch_up(end)
	check(pressed == [1, 1], "a drag that started on a row does not press it (%s)" % str(pressed))

	# 2d. Momentum: the release flings on, eases off and stops clamped at the end.
	check(ts.is_flinging(), "a fast release flings")
	var before := sc.scroll_vertical
	ts._process(0.05)
	check(sc.scroll_vertical > before, "the fling keeps scrolling (%d -> %d)" % [before, sc.scroll_vertical])

	# 2e. A tap on a list still flinging only stops it.
	var mid := sc.get_global_rect().get_center()
	touch_down(mid)
	touch_up(mid)
	check(not ts.is_flinging(), "a tap stops the fling")
	check(pressed == [1, 1], "the tap that stopped a fling does not press a row (%s)" % str(pressed))
	ts._process(30.0)
	check(not ts.is_flinging(), "a stopped fling stays stopped")

	# 2f. Clamped at both ends: a long fling stops at the bottom; dragging down past the top stops at 0.
	touch_down(mid)
	end = touch_move(mid, mid + Vector2(0, -300))
	touch_up(end)
	ts._process(30.0)
	check(absf(float(sc.scroll_vertical) - max_scroll) <= 1.0 and not ts.is_flinging(),
		"the fling stops clamped at the end (%d of %.0f)" % [sc.scroll_vertical, max_scroll])
	touch_down(mid)
	end = touch_move(mid, mid + Vector2(0, 3000), 12)
	check(sc.scroll_vertical == 0, "dragging past the top clamps at 0 (%d)" % sc.scroll_vertical)
	touch_up(end)
	ts.stop_fling()

	# 3. Outside any list the map/battle TouchInput still pans and long-presses.
	pans.clear()
	var open := Vector2(1200, 600)
	touch_down(open)
	end = touch_move(open, open + Vector2(100, 0), 4)
	touch_up(end)
	check(not pans.is_empty() and sc.scroll_vertical == 0, "a drag beside the list pans the camera (%d pans), not the list" % pans.size())
	long_presses.clear()
	touch_down(open)
	ti._process(0.6)
	touch_up(open)
	check(long_presses.size() == 1, "a held finger beside the list is a long-press (%d)" % long_presses.size())
	# A held, unmoving finger on a row is not a scroll.
	touch_down(row1)
	ts._process(0.6)
	check(not ts.is_scrolling() and sc.scroll_vertical == 0, "a held finger on a row does not scroll")
	touch_up(row1)

	# 4. Desktop: no mobile override and no touchscreen, so neither a touch nor a mouse drag scrolls through it.
	UiTheme.set_mobile_override(false)
	ts.reset()
	touch_down(mid)
	end = touch_move(mid, mid + Vector2(0, -200))
	touch_up(end)
	check(sc.scroll_vertical == 0 and not ts.is_scrolling(), "desktop: the controller is off (%d)" % sc.scroll_vertical)
	UiTheme.set_mobile_override(true)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT; mb.button_mask = MOUSE_BUTTON_MASK_LEFT; mb.pressed = true; mb.position = mid
	t.root.push_input(mb, true)
	var mm := InputEventMouseMotion.new()
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT; mm.position = mid + Vector2(0, -200); mm.relative = Vector2(0, -200)
	t.root.push_input(mm, true)
	mb.pressed = false; mb.button_mask = 0; mb.position = mm.position
	t.root.push_input(mb, true)
	check(sc.scroll_vertical == 0 and not ts.is_scrolling(), "a real mouse drag is never a touch scroll (%d)" % sc.scroll_vertical)

	ts.reset()
	host.queue_free()
	fwd.queue_free()
	UiTheme.set_mobile_override(null)
	return fails
