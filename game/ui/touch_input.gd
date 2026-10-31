class_name TouchInput
extends Node
## Reusable touch + mouse camera/map input controller.
## Supports tap, one-finger drag pan, two-finger pinch zoom (InputEventMagnifyGesture
## and two-finger InputEventScreenDrag), long-press (~0.5s with little movement) as
## right-click/info, and desktop mouse/wheel/trackpad gestures without double-panning
## when emulate_mouse_from_touch is active.

const DRAG_THRESHOLD := 12.0
const LONG_PRESS_SEC := 0.5
const WHEEL_FACTOR := 1.12

var on_tap: Callable
var on_pan: Callable
var on_zoom: Callable
var on_long_press: Callable
var drag_threshold: float = DRAG_THRESHOLD
var long_press_sec: float = LONG_PRESS_SEC
var pan_gesture_scale: float = 8.0

var pressing := false
var dragging := false
var long_pressed := false
var press_pos := Vector2.ZERO

var _active_pos := Vector2.ZERO
var _press_sec := 0.0
var _press_start_usec := 0
var _touch_active := false
var _multi_touch := false
var _touches: Dictionary = {}
var _pinch_dist := 0.0
var _last_touch_usec := 0
var _right_pressing := false
var _right_dragging := false
var _right_press_pos := Vector2.ZERO

static func attach(host: Node, tap_cb: Callable, pan_cb: Callable, zoom_cb: Callable, long_press_cb: Callable = Callable(), pan_scale: float = 8.0) -> TouchInput:
	var ctrl := TouchInput.new()
	ctrl.name = "TouchInput"
	ctrl.process_mode = Node.PROCESS_MODE_ALWAYS
	ctrl.on_tap = tap_cb
	ctrl.on_pan = pan_cb
	ctrl.on_zoom = zoom_cb
	ctrl.on_long_press = long_press_cb
	ctrl.pan_gesture_scale = pan_scale
	if host != null:
		host.add_child(ctrl)
	return ctrl

func reset() -> void:
	pressing = false
	dragging = false
	long_pressed = false
	_press_sec = 0.0
	_touch_active = false
	_multi_touch = false
	_touches.clear()
	_pinch_dist = 0.0
	_right_pressing = false
	_right_dragging = false

func _process(delta: float) -> void:
	# Long-press is a touch gesture: a slow desktop click stays a click (right-click is the desktop info gesture).
	if pressing and _touch_active and not dragging and not long_pressed and not _multi_touch:
		_press_sec += delta
		var elapsed := maxf(_press_sec, float(Time.get_ticks_usec() - _press_start_usec) / 1000000.0 if _press_start_usec > 0 else 0.0)
		if elapsed >= long_press_sec:
			long_pressed = true
			_emit_long_press(_active_pos)

func handle_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_last_touch_usec = Time.get_ticks_usec()
		if st.pressed:
			_touches[st.index] = st.position
			_touch_active = true
			if _touches.size() == 1 and not _multi_touch:
				pressing = true
				dragging = false
				long_pressed = false
				press_pos = st.position
				_active_pos = st.position
				_press_sec = 0.0
				_press_start_usec = _last_touch_usec
			else:
				_multi_touch = true
				dragging = true
				long_pressed = false
				_pinch_dist = _calc_pinch_dist()
		else:
			var elapsed := maxf(_press_sec, float(_last_touch_usec - _press_start_usec) / 1000000.0 if _press_start_usec > 0 else 0.0)
			_touches.erase(st.index)
			if _touches.is_empty():
				if pressing and not dragging and not _multi_touch:
					if not long_pressed:
						if elapsed >= long_press_sec:
							long_pressed = true
							_emit_long_press(st.position)
						else:
							_emit_tap(st.position)
				pressing = false
				dragging = false
				long_pressed = false
				_press_sec = 0.0
				_multi_touch = false
				_touch_active = false
				_pinch_dist = 0.0
			else:
				_pinch_dist = _calc_pinch_dist()
		return true
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_last_touch_usec = Time.get_ticks_usec()
		_touch_active = true
		if not _touches.has(sd.index):
			_touches[sd.index] = sd.position - sd.relative
			if _touches.size() == 1 and not pressing:
				pressing = true
				press_pos = _touches[sd.index]
				_press_start_usec = _last_touch_usec
			elif _touches.size() >= 2:
				_multi_touch = true
				_pinch_dist = _calc_pinch_dist()
		_touches[sd.index] = sd.position
		_active_pos = sd.position
		if _touches.size() >= 2:
			_multi_touch = true
			dragging = true
			long_pressed = false
			var d := _calc_pinch_dist()
			if _pinch_dist > 1.0 and d > 1.0:
				_emit_zoom(_calc_pinch_mid(), d / _pinch_dist)
			_pinch_dist = d
		else:
			if not dragging and sd.position.distance_to(press_pos) > drag_threshold:
				dragging = true
			if dragging:
				_emit_pan(sd.relative)
		return true
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		dragging = true
		long_pressed = false
		_emit_zoom(mg.position, mg.factor)
		return true
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		dragging = true
		long_pressed = false
		_emit_pan(-pg.delta * pan_gesture_scale)
		return true
	elif event is InputEventMouseButton:
		if _is_emulated_from_active_touch(event):
			return true
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				pressing = true
				dragging = false
				long_pressed = false
				press_pos = mb.position
				_active_pos = mb.position
				_press_sec = 0.0
				_press_start_usec = Time.get_ticks_usec()
			elif pressing:
				pressing = false
				if not dragging:
					_emit_tap(mb.position)
				dragging = false
				long_pressed = false
				_press_sec = 0.0
			return true
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_pressing = true
				_right_dragging = false
				_right_press_pos = mb.position
			elif _right_pressing:
				_right_pressing = false
				if not _right_dragging:
					_emit_long_press(mb.position)
				_right_dragging = false
			return true
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_emit_zoom(mb.position, WHEEL_FACTOR)
			return true
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_emit_zoom(mb.position, 1.0 / WHEEL_FACTOR)
			return true
	elif event is InputEventMouseMotion:
		if _is_emulated_from_active_touch(event):
			return true
		var mm := event as InputEventMouseMotion
		if pressing:
			_active_pos = mm.position
			if not dragging and mm.position.distance_to(press_pos) > drag_threshold:
				dragging = true
			if dragging:
				_emit_pan(mm.relative)
			return true
		if _right_pressing:
			if not _right_dragging and mm.position.distance_to(_right_press_pos) > drag_threshold:
				_right_dragging = true
			return true
	return false

func _is_emulated_from_active_touch(event: InputEvent) -> bool:
	if _touch_active or not _touches.is_empty():
		return true
	if event.device == InputEvent.DEVICE_ID_EMULATION and _last_touch_usec > 0:
		return (Time.get_ticks_usec() - _last_touch_usec) < 100000
	return false

func _calc_pinch_dist() -> float:
	if _touches.size() < 2:
		return 0.0
	var vals: Array = _touches.values()
	return (vals[0] as Vector2).distance_to(vals[1] as Vector2)

func _calc_pinch_mid() -> Vector2:
	if _touches.is_empty():
		return _active_pos
	var vals: Array = _touches.values()
	if vals.size() < 2:
		return vals[0] as Vector2
	return ((vals[0] as Vector2) + (vals[1] as Vector2)) * 0.5

func _emit_tap(pos: Vector2) -> void:
	if on_tap.is_valid():
		on_tap.call(pos)

func _emit_long_press(pos: Vector2) -> void:
	if on_long_press.is_valid():
		on_long_press.call(pos)
	elif on_tap.is_valid():
		on_tap.call(pos)

func _emit_pan(delta: Vector2) -> void:
	if on_pan.is_valid():
		on_pan.call(delta)

func _emit_zoom(pos: Vector2, factor: float) -> void:
	if on_zoom.is_valid():
		on_zoom.call(pos, factor)
