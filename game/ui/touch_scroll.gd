class_name TouchScroll
extends Node
## v0.083 drag-anywhere scrolling on phones. One controller (a child of the MobileApp autoload) reads every touch in
## _input, before the GUI. A finger that lands on a list (ScrollContainer, ItemList, Tree, a scrolling RichTextLabel)
## and moves more than THRESHOLD_PX screen pixels scrolls the nearest list that scrolls that way: it follows the
## finger, then flings and eases to a stop, clamped at the ends. When the scroll begins, the list is sent
## NOTIFICATION_SCROLL_BEGIN (Godot's own touch-scroll cancel: a button pressed inside does not fire on release) and
## the map/battle TouchInput is reset, so the camera does not pan under the list. A finger that does not move is left
## alone, so taps and long-presses work as before. Only touches are read (screen events and the mouse events Godot
## emulates from them): a desktop mouse is unchanged. Active on phones and touchscreens only.

const THRESHOLD_PX := 14.0       # screen pixels a finger moves before its press becomes a scroll
const FRICTION := 3.2            # fling decay per second (an exponential ease to a stop)
const FLING_MIN := 60.0          # px/s: a slower release just stops
const FLING_MAX := 6000.0
const FLING_STOP := 12.0
const STOP_TAP_SPEED := 150.0    # a tap on a list still flinging faster than this only stops it
const SAMPLE_SEC := 0.1          # the fling speed is the finger's speed over its last 0.1 s
const NO_SCROLL := "touch_scroll_off"

var _down := false               # a one-finger gesture is being tracked
var _scrolling := false
var _chain: Array = []           # the lists under the press that can scroll now, innermost first
var _target: Control = null
var _bars: Array = [null, null]  # the target's [horizontal, vertical] bars that move
var _press_pos := Vector2.ZERO
var _anchor_pos := Vector2.ZERO
var _anchor_val := Vector2.ZERO
var _samples: Array = []         # [usec, position]
var _fingers: Dictionary = {}
var _stop_tap: Control = null    # the list a press stopped mid-fling: that press does not tap

var _fling_target: Control = null
var _fling_bars: Array = [null, null]
var _fling_at := Vector2.ZERO
var _fling_v := Vector2.ZERO

## Controls that pan or drag on their own (a land map) opt out: a drag that starts on them never scrolls a list.
static func opt_out(c: Control) -> void:
	c.set_meta(NO_SCROLL, true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

func active() -> bool:
	return MobileApp.is_mobile() or DisplayServer.is_touchscreen_available()

func is_scrolling() -> bool:
	return _scrolling

func is_flinging() -> bool:
	return is_instance_valid(_fling_target) and _fling_v != Vector2.ZERO

func reset() -> void:
	stop_fling()
	_end_gesture()
	_fingers.clear()

func _input(event: InputEvent) -> void:
	if not active():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_fingers[st.index] = true
			if _fingers.size() > 1:
				_end_gesture()   # a second finger: a pinch is not a list scroll
			elif not _down:
				_press(st.position)
		else:
			_fingers.erase(st.index)
			if _down:
				_release(st.position)
	elif event is InputEventScreenDrag:
		if _down and _fingers.size() <= 1 and _move((event as InputEventScreenDrag).position):
			get_viewport().set_input_as_handled()
	elif event.device != InputEvent.DEVICE_ID_EMULATION:
		return
	elif event is InputEventMouseButton:
		# Godot sends the emulated mouse press before its screen touch (and the release before the touch release).
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			if not _down and _fingers.size() <= 1:
				_press(mb.position)
		elif _down:
			_release(mb.position)
	elif event is InputEventMouseMotion:
		if _down and _move((event as InputEventMouseMotion).position):
			get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ the gesture
func _press(pos: Vector2) -> void:
	var flung: Control = _fling_target if is_flinging() else null
	var speed := _fling_v.length()
	stop_fling()
	_end_gesture()
	_down = true
	_press_pos = pos
	_sample(pos)
	var hit := control_at(pos)
	_chain = scroll_chain(hit)
	if flung != null and speed > STOP_TAP_SPEED and hit != null and (hit == flung or flung.is_ancestor_of(hit)):
		_stop_tap = flung

## True when the event is the list's: the list scrolls, or the finger is still deciding (its motion is held back
## from the list's own drag handling so nothing scrolls twice).
func _move(pos: Vector2) -> bool:
	if _chain.is_empty():
		return false
	_sample(pos)
	if not _scrolling:
		var d := pos - _press_pos
		if d.length() <= threshold():
			return true
		if not _begin(d, pos):
			return false
	_apply(pos)
	return true

func _begin(d: Vector2, pos: Vector2) -> bool:
	var axis := 1 if absf(d.y) >= absf(d.x) else 0
	var pick: Control = null
	for ax in [axis, 1 - axis]:
		for c in _chain:
			if is_instance_valid(c) and scroll_bar(c, ax) != null:
				pick = c
				break
		if pick != null:
			break
	if pick == null:
		_chain.clear()
		return false
	_target = pick
	_bars = [scroll_bar(pick, 0), scroll_bar(pick, 1)]
	_anchor_pos = pos
	_anchor_val = _bar_values(_bars)
	_scrolling = true
	_stop_tap = null
	pick.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)   # cancels the press of a button inside
	if pick is ScrollContainer:
		(pick as ScrollContainer).scroll_started.emit()
	get_tree().call_group(TouchInput.GROUP, "reset")   # the map/battle camera does not pan under the list
	return true

func _apply(pos: Vector2) -> void:
	if not is_instance_valid(_target):
		_end_gesture()
		return
	var off := _anchor_pos - pos
	for ax in 2:
		var sb: ScrollBar = _bars[ax]
		if sb != null and is_instance_valid(sb):
			sb.value = _anchor_val[ax] + off[ax]

func _release(pos: Vector2) -> void:
	if _scrolling and is_instance_valid(_target):
		_sample(pos)
		var v := -_finger_velocity()
		var bars := _bars.duplicate()
		for ax in 2:
			if bars[ax] == null or absf(v[ax]) < FLING_MIN:
				v[ax] = 0.0
		if v != Vector2.ZERO:
			_fling_target = _target
			_fling_bars = bars
			_fling_at = _bar_values(bars)
			_fling_v = v
			set_process(true)
		elif _target is ScrollContainer:
			(_target as ScrollContainer).scroll_ended.emit()
	elif is_instance_valid(_stop_tap):
		_stop_tap.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)   # this tap only stopped the fling
	_end_gesture()

func _end_gesture() -> void:
	_down = false
	_scrolling = false
	_chain.clear()
	_target = null
	_bars = [null, null]
	_samples.clear()
	_stop_tap = null

func threshold() -> float:
	var s := absf(get_viewport().get_screen_transform().get_scale().x) if is_inside_tree() else 1.0
	return THRESHOLD_PX / (s if s > 0.01 else 1.0)

func _sample(pos: Vector2) -> void:
	var now := Time.get_ticks_usec()
	_samples.append([now, pos])
	while _samples.size() > 2 and now - int(_samples[0][0]) > int(SAMPLE_SEC * 1000000.0):
		_samples.pop_front()

func _finger_velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var first: Array = _samples[0]
	var last: Array = _samples[-1]
	var dt := maxf(float(int(last[0]) - int(first[0])) / 1000000.0, 1.0 / 120.0)
	return (((last[1] as Vector2) - (first[1] as Vector2)) / dt).limit_length(FLING_MAX)

static func _bar_values(bars: Array) -> Vector2:
	var out := Vector2.ZERO
	for ax in 2:
		if bars[ax] != null:
			out[ax] = (bars[ax] as ScrollBar).value
	return out

# ------------------------------------------------------------------ fling
func _process(delta: float) -> void:
	if not is_flinging():
		stop_fling()
		return
	var moving := false
	for ax in 2:
		var sb: ScrollBar = _fling_bars[ax]
		if sb == null or not is_instance_valid(sb) or absf(_fling_v[ax]) < FLING_STOP:
			_fling_v[ax] = 0.0
			continue
		var lo := sb.min_value
		var hi := maxf(lo, sb.max_value - sb.page)
		_fling_at[ax] += _fling_v[ax] * delta
		if _fling_at[ax] <= lo or _fling_at[ax] >= hi:   # clamped at the end: the fling stops there
			_fling_at[ax] = clampf(_fling_at[ax], lo, hi)
			_fling_v[ax] = 0.0
		else:
			_fling_v[ax] *= exp(-FRICTION * delta)
			moving = moving or absf(_fling_v[ax]) >= FLING_STOP
		sb.value = _fling_at[ax]
	if not moving:
		stop_fling()

func stop_fling() -> void:
	if is_instance_valid(_fling_target) and _fling_target is ScrollContainer and _fling_v != Vector2.ZERO:
		(_fling_target as ScrollContainer).scroll_ended.emit()
	_fling_target = null
	_fling_bars = [null, null]
	_fling_v = Vector2.ZERO
	set_process(false)

# ------------------------------------------------------------------ what is under the finger
## The bar of `c` that scrolls along `axis` (0 = sideways, 1 = up and down) and has room to move, or null.
static func scroll_bar(c: Control, axis: int) -> ScrollBar:
	var sb: ScrollBar = null
	if c is ScrollContainer:
		var sc := c as ScrollContainer
		if (sc.horizontal_scroll_mode if axis == 0 else sc.vertical_scroll_mode) == ScrollContainer.SCROLL_MODE_DISABLED:
			return null
		sb = sc.get_h_scroll_bar() if axis == 0 else sc.get_v_scroll_bar()
	elif c is ItemList or c is Tree or (c is RichTextLabel and (c as RichTextLabel).scroll_active):
		for ch in c.get_children(true):
			if (axis == 0 and ch is HScrollBar) or (axis == 1 and ch is VScrollBar):
				sb = ch as ScrollBar if (ch as ScrollBar).visible else null
				break
	if sb == null or sb.max_value - sb.page <= sb.min_value + 0.5:
		return null
	return sb

## Controls that take a finger drag themselves: a drag that starts on them is theirs, not a list scroll.
static func blocks_scroll(c: Control) -> bool:
	return (c.has_meta(NO_SCROLL) or c is Slider or c is ScrollBar or c is SpinBox or c is LineEdit or c is TextEdit
		or (c is RichTextLabel and (c as RichTextLabel).selection_enabled))

## The lists from `hit` up that can scroll now, innermost first; it stops at a modal so the screen behind stays put.
static func scroll_chain(hit: Control) -> Array:
	var out: Array = []
	var n: Node = hit
	while n is Control:
		var c := n as Control
		if blocks_scroll(c):
			break
		if scroll_bar(c, 0) != null or scroll_bar(c, 1) != null:
			out.append(c)
		if c.has_meta("ui_modal") or c.top_level:
			break
		n = c.get_parent()
	return out

## The Control a press at `pos` (viewport coordinates) lands on, found as the Viewport finds it: canvas layers from the
## top, later siblings first, the deepest visible Control that does not ignore the mouse. Popup windows get their own
## input before _input, so they are skipped.
func control_at(pos: Vector2) -> Control:
	var roots: Array = []
	_collect_roots(get_tree().root, 0, roots)
	roots.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	for r in roots:
		var hit := _find_at(r[2] as Control, pos)
		if hit != null:
			return hit
	return null

func _collect_roots(node: Node, layer: int, out: Array) -> void:
	for ch in node.get_children():
		if ch is Window:
			continue
		if ch is CanvasLayer:
			if (ch as CanvasLayer).visible:
				_collect_roots(ch, (ch as CanvasLayer).layer, out)
		elif ch is Control:
			if (ch as Control).is_visible_in_tree():
				out.append([layer, out.size(), ch])
		else:
			_collect_roots(ch, layer, out)

func _find_at(c: Control, pos: Vector2) -> Control:
	if not c.visible:
		return null
	var local := c.get_global_transform_with_canvas().affine_inverse() * pos
	var inside := Rect2(Vector2.ZERO, c.size).has_point(local)
	# Containers lay their children out inside them, so a miss skips the whole branch.
	if inside or not (c.clip_contents or c is Container):
		for i in range(c.get_child_count(true) - 1, -1, -1):
			var ch := c.get_child(i, true) as Control
			if ch == null or ch.top_level:
				continue
			var hit := _find_at(ch, pos)
			if hit != null:
				return hit
	if inside and c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return c
	return null
