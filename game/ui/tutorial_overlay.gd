class_name TutorialOverlay
extends Control
## Guided tutorial overlay (v0.103): dims the screen, cuts out the highlighted control, and
## points at it with an arrow and a small text box (Back / Next / Skip tutorial).
## The dim is four blocker rects around the cut-out, so the highlighted control itself stays
## live and receives the player's real input: mouse clicks, and touch through Godot's
## emulate_mouse_from_touch (project setting, on for this game). The engine is
## campaign/tutorial.gd; this overlay only draws and reports the player's actions to it.
##
## Use: `TutorialOverlay.open(host_control, tutorial)` after tutorial.setup(...)/start(...).
## Anchors resolve under the host: a node path ("Panel/OkButton"), a Control named after the
## anchor, or a Control carrying a "tutorial_anchor" meta with that value. A step whose
## anchor is not on screen shows its text box over a full dim until the control appears.
## "state" steps poll state_of (set by the host screen): state_of.call(key) -> value.

const PAD := 6.0   # the cut-out grows past the control by this much, the border sits on it
const DIM := Color(0.03, 0.02, 0.01, 0.72)
const MARK := Color(1.0, 0.84, 0.35)
const POLL := 0.12   # seconds between target re-checks (controls appear on screen changes)

var tutorial = null   # campaign/tutorial.gd instance (duck-typed, set by open())
var search_root: Node = null   # anchors resolve under this node (the host, set by open())
var state_of: Callable   # optional host hook for "state" steps: key -> value
var auto_free := true   # free the overlay when the tutorial ends

var _blockers: Array = []   # 4 ColorRects: the dim around the cut-out
var _box: PanelContainer
var _text: Label
var _counter: Label
var _back_button: Button
var _next_button: Button
var _target: Control = null
var _rect := Rect2()   # the cut-out, in overlay-local coordinates (empty: no target)
var _wired: Array = []   # buttons already connected to _on_target_pressed
var _poll := 0.0
enum TouchOwner { TUTORIAL, MODAL }
var _touch_owners: Dictionary = {}   # v0.103: each finger keeps its press owner until release.
var _touches: Dictionary = {}   # v0.103: keep an allowed gesture's release alive when its action changes steps.

## Builds the overlay over host and starts showing the tutorial's current step.
## v0.103: attachment is deferred; configure the returned overlay now, await ready before using its children.
static func open(host: Control, p_tutorial) -> TutorialOverlay:
	var overlay: TutorialOverlay = load("res://ui/tutorial_overlay.gd").new()
	overlay.tutorial = p_tutorial
	overlay.search_root = host
	# v0.103: Settings can resume from _ready() while its ancestors are still setting up children.
	host.add_child.call_deferred(overlay)
	return overlay

func _ready() -> void:
	name = "TutorialOverlay"
	theme = UiTheme.get_theme()
	# v0.103: anchors alone preserve this new Control's zero-size rect via offsets; fill the host too.
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE   # drawing only; the blockers and the box take input
	for i in 4:
		var blocker := ColorRect.new()
		blocker.color = DIM
		blocker.mouse_filter = MOUSE_FILTER_STOP
		blocker.show_behind_parent = true   # the arrow and border are drawn by the overlay, over the dim
		add_child(blocker)
		_blockers.append(blocker)
	_box = UiKit.panel()
	_box.mouse_filter = MOUSE_FILTER_STOP
	add_child(_box)
	_box.minimum_size_changed.connect(_layout)   # v0.103: wrapped text and phone fonts change the real size.
	var v := UiKit.vbox(8)
	_box.add_child(v)
	_text = UiKit.label("", "", true)
	_text.name = "TutorialText"
	v.add_child(_text)
	var footer := UiKit.hbox(8)
	v.add_child(footer)
	_counter = UiKit.label("", "Muted")
	footer.add_child(_counter)
	footer.add_child(UiKit.spacer())
	_back_button = UiKit.button("Back", _on_back, "Row", 84)
	_back_button.name = "TutorialBack"
	footer.add_child(_back_button)
	_next_button = UiKit.button("Next", _on_next, "", 96)
	_next_button.name = "TutorialNext"
	footer.add_child(_next_button)
	var skip_button := UiKit.button("Skip tutorial", _on_skip, "Row", 140)
	skip_button.name = "TutorialSkip"
	footer.add_child(skip_button)
	resized.connect(_layout)
	visibility_changed.connect(_clear_touches)   # Retained overlays start each visible session with fresh fingers.
	var game_node: Node = get_tree().root.get_node_or_null("Game")
	if game_node != null and game_node.has_signal("screen_changed"):
		game_node.screen_changed.connect(_on_screen_changed)
	if tutorial != null:
		tutorial.step_changed.connect(_on_step_changed)
		tutorial.completed.connect(_on_completed)
	_show_step()

## The cut-out the player sees, in overlay-local coordinates (empty when no target is found).
func highlight_rect() -> Rect2:
	return _rect

func current_target() -> Control:
	return _target

## The four dim rects (overlay-local), for tests: none of them covers the cut-out.
func blocker_rects() -> Array:
	var out: Array = []
	for blocker in _blockers:
		var b: ColorRect = blocker
		out.append(Rect2(b.position, b.size))
	return out

func _process(delta: float) -> void:
	if tutorial == null or not tutorial.active:
		hide()   # v0.103: retained/inactive overlays must never intercept another screen's input.
		return
	_poll += delta
	if _poll < POLL:
		return
	_poll = 0.0
	_check_state_step()
	var before := _target
	_resolve_target()
	var rect := _compute_rect()
	if _target != before or rect != _rect:
		_wire_target()
		_rect = rect
		_layout()

func _clear_touches() -> void:
	_touches.clear()
	_touch_owners.clear()

# v0.103: a later modal owns its input, even though tutorial _input runs before GUI dispatch.
func _modal_takes_input(point: Vector2) -> bool:
	if not is_instance_valid(MobileApp.touch_scroll):
		return false
	# Reuse the game's canvas-layer/later-sibling picker; do not special-case SaveFailureModal.
	var hit: Control = MobileApp.touch_scroll.control_at(point)
	if not is_instance_valid(hit) or hit.get_viewport() != get_viewport():
		return false
	var node: Node = hit
	while node != null:
		if node == self:
			return false
		if node.has_meta("ui_modal") and not node.is_ancestor_of(self):
			return true
		node = node.get_parent()
	return false

# v0.103: touches beginning outside the cut-out/navigation must not reach screen gestures or the list scroller.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or tutorial == null or not tutorial.active:
		return
	var touch_position: Vector2
	var finger_index: int
	if event is InputEventScreenTouch:
		touch_position = (event as InputEventScreenTouch).position
		finger_index = (event as InputEventScreenTouch).index
	elif event is InputEventScreenDrag:
		touch_position = (event as InputEventScreenDrag).position
		finger_index = (event as InputEventScreenDrag).index
	else:
		return
	var higher_modal: bool = _modal_takes_input(touch_position)
	if higher_modal:
		# Keep blocked indices: another finger's modal event must not revive their releases.
		for tracked_index: int in _touches:
			_touches[tracked_index] = false
	var allowed: bool = false
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed:
			_touch_owners[finger_index] = TouchOwner.MODAL if higher_modal else TouchOwner.TUTORIAL
			if higher_modal:
				_touches[finger_index] = false
				return # Yield the modal's press without marking it handled.
			var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * touch.position
			allowed = _rect.has_point(point) or Rect2(_box.position, _box.size).has_point(point)
			_touches[finger_index] = allowed
		else:
			var owner: int = int(_touch_owners.get(finger_index, TouchOwner.MODAL if higher_modal else TouchOwner.TUTORIAL))
			allowed = bool(_touches.get(finger_index, true)) # A press may predate this overlay.
			_touches.erase(finger_index)
			_touch_owners.erase(finger_index)
			if owner == TouchOwner.MODAL:
				if not higher_modal:
					get_viewport().set_input_as_handled() # Its modal closed; do not give the tutorial an orphan release.
				return
	elif event is InputEventScreenDrag:
		var drag_owner: int = int(_touch_owners.get(finger_index, TouchOwner.MODAL if higher_modal else TouchOwner.TUTORIAL))
		if drag_owner == TouchOwner.MODAL:
			if not higher_modal:
				get_viewport().set_input_as_handled()
			return
		allowed = bool(_touches.get(finger_index, false))
	if not allowed:
		get_viewport().set_input_as_handled()

## Arrow and highlight border (drawn under the children, so the box covers the line's end).
func _draw() -> void:
	if _rect.size.x <= 0.0 or _rect.size.y <= 0.0 or _box == null:
		return
	draw_rect(_rect, MARK, false, 3.0)
	var from_pt: Vector2 = _box.position + _box.size * 0.5
	var centre: Vector2 = _rect.get_center()
	var reach := 0.5 * minf(_rect.size.x, _rect.size.y) + 14.0
	var tip: Vector2 = centre.move_toward(from_pt, reach)
	if tip.is_equal_approx(from_pt):
		return
	var dirv: Vector2 = (tip - from_pt).normalized()
	var side := Vector2(-dirv.y, dirv.x)
	draw_line(from_pt, tip, MARK, 3.0)
	draw_line(tip, tip - dirv * 14.0 + side * 7.0, MARK, 3.0)
	draw_line(tip, tip - dirv * 14.0 - side * 7.0, MARK, 3.0)

func _show_step() -> void:
	visible = tutorial != null and tutorial.active   # v0.103: open-before-start is harmless.
	if not visible:
		_target = null
		_rect = Rect2()
		return
	var step: Dictionary = tutorial.current()
	_text.text = String(step.get("text", ""))
	_counter.text = "%d / %d" % [tutorial.index + 1, tutorial.step_count()]
	_back_button.disabled = tutorial.index <= 0 or not bool(step.get("back", true)) # v0.104: campaign commit boundaries.
	_next_button.disabled = not tutorial.can_advance()
	_next_button.text = "Done" if tutorial.index >= tutorial.step_count() - 1 else "Next"
	_target = null
	_raise_overlay.call_deferred() # v0.104: keep the dim above reviews, after the parent's ready/add-child work.
	_resolve_target()
	_reveal_target.call_deferred()   # v0.103: reveal scrolled Settings anchors after container layout.
	_wire_target()
	_rect = _compute_rect()
	_layout()

func _raise_overlay() -> void:
	if is_inside_tree() and not is_queued_for_deletion():
		get_parent().move_child(self, get_parent().get_child_count() - 1)

## Places the four dim rects around the cut-out and the text box near it, on screen.
func _layout() -> void:
	if _box == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_rect = _compute_rect()   # v0.103: resizing must move the hole immediately, without waiting for POLL.
	var full := Rect2(Vector2.ZERO, size)
	if _rect.size.x <= 0.0 or _rect.size.y <= 0.0:
		_place(_blockers[0], full)
		for i in range(1, 4):
			_place(_blockers[i], Rect2())
	else:
		_place(_blockers[0], Rect2(0.0, 0.0, size.x, _rect.position.y))
		_place(_blockers[1], Rect2(0.0, _rect.end.y, size.x, size.y - _rect.end.y))
		_place(_blockers[2], Rect2(0.0, _rect.position.y, _rect.position.x, _rect.size.y))
		_place(_blockers[3], Rect2(_rect.end.x, _rect.position.y, size.x - _rect.end.x, _rect.size.y))
	_box.custom_minimum_size.x = 0.0 # v0.103: measure content, not last layout's forced width
	var box_w := minf(maxf(440.0, _box.get_minimum_size().x), maxf(240.0, size.x - 32.0))
	_box.custom_minimum_size.x = box_w
	_box.size = Vector2(box_w, _box.get_combined_minimum_size().y)
	var box_size: Vector2 = _box.size   # v0.103: Control clamps to its themed minimum; place the actual box.
	var bx := clampf(size.x * 0.5 - box_size.x * 0.5, 16.0, maxf(16.0, size.x - box_size.x - 16.0))
	var by := size.y - box_size.y - 24.0
	if _rect.size.x > 0.0:
		bx = clampf(_rect.get_center().x - box_size.x * 0.5, 16.0, maxf(16.0, size.x - box_size.x - 16.0))
		if _rect.end.y + 28.0 + box_size.y <= size.y - 16.0:
			by = _rect.end.y + 28.0
		elif _rect.position.y - 28.0 - box_size.y >= 16.0:
			by = _rect.position.y - 28.0 - box_size.y
		elif _rect.end.x + 28.0 + box_size.x <= size.x - 16.0:
			bx = _rect.end.x + 28.0   # v0.103: a central control may leave room only to one side.
		elif _rect.position.x - 28.0 - box_size.x >= 16.0:
			bx = _rect.position.x - 28.0 - box_size.x
	_box.position = Vector2(bx, clampf(by, 16.0, maxf(16.0, size.y - box_size.y - 16.0)))
	queue_redraw()

func _place(blocker: ColorRect, rect: Rect2) -> void:
	blocker.position = rect.position
	blocker.size = Vector2(maxf(0.0, rect.size.x), maxf(0.0, rect.size.y))
	blocker.visible = blocker.size.x > 0.0 and blocker.size.y > 0.0

func _compute_rect() -> Rect2:
	if _target == null or not is_instance_valid(_target) or not _target.is_visible_in_tree():
		return Rect2()
	if size.x <= 0.0 or size.y <= 0.0:
		return Rect2()
	# v0.103: use viewport coordinates, including canvas transforms, and respect every clipping ancestor.
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var local: Rect2 = inverse * (_target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _target.size))
	var clip := Rect2(Vector2.ZERO, size)
	var ancestor: Node = _target.get_parent()
	while ancestor != null:
		if ancestor is Control and ancestor.clip_contents:
			var control: Control = ancestor
			clip = clip.intersection(inverse * (control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)))
		ancestor = ancestor.get_parent()
	if not local.intersects(clip):
		return Rect2()
	return local.grow(PAD).intersection(clip)

# v0.103: reveal a newly selected anchor once; leave subsequent user scrolling alone.
func _reveal_target() -> void:
	if not is_instance_valid(_target):
		return
	var ancestor: Node = _target.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(_target)
		ancestor = ancestor.get_parent()
	_layout()

## Finds the step's control: node path from the host, then by name, then by meta.
func _resolve_target() -> void:
	if is_instance_valid(_target) and _target.is_inside_tree() and _target.is_visible_in_tree() and not _target.is_queued_for_deletion():
		return
	_target = null
	if tutorial == null:
		return
	var anchor := String(tutorial.current_anchor())
	if anchor == "":
		return
	var root: Node = search_root if search_root != null else get_tree().root
	if anchor.contains("/"):
		var by_path: Node = root.get_node_or_null(NodePath(anchor))
		if by_path is Control and by_path.is_visible_in_tree() and not by_path.is_queued_for_deletion():
			_target = by_path
			return
	var queue: Array = [root]
	while not queue.is_empty():
		var node: Node = queue.pop_front()
		if node == self:
			continue   # never highlight the overlay's own controls
		if node is Control:
			var c: Control = node
			if not c.is_visible_in_tree() or c.is_queued_for_deletion():
				continue   # v0.103: hidden/retiring screens must not shadow the visible anchor.
			if c.name == anchor or (c.has_meta("tutorial_anchor") and String(c.get_meta("tutorial_anchor")) == anchor):
				_target = c
				return
		for child in node.get_children():
			queue.append(child)

## A "button" step completes when its control is really pressed (mouse or touch).
func _wire_target() -> void:
	if tutorial == null or tutorial.done_kind() != "button":
		return
	if not _target is BaseButton or _wired.has(_target):
		return
	var button: BaseButton = _target
	button.pressed.connect(_on_target_pressed.bind(_target))
	_wired.append(_target)

func _on_target_pressed(button: BaseButton) -> void:
	if tutorial == null or button != _target:
		return
	tutorial.notify_button(String(tutorial.current_anchor()))   # v0.103: report the control actually pressed.

func _check_state_step() -> void:
	if tutorial == null or tutorial.done_kind() != "state" or not state_of.is_valid():
		return
	var done: Dictionary = tutorial.current().get("done", {})
	var key := String(done.get("key", ""))
	tutorial.notify_state(key, state_of.call(key))

func _on_screen_changed(screen: String) -> void:
	# v0.103: Game.goto() retires the old screen before emitting this signal. Carry the overlay to the new host.
	var ancestor: Node = search_root
	var retiring := false
	while is_instance_valid(ancestor):
		if ancestor.is_queued_for_deletion(): retiring = true; break
		ancestor = ancestor.get_parent()
	if retiring: # v0.104: a map HUD's parent Node2D retires, rather than the HUD itself.
		var game: Node = get_tree().root.get_node_or_null("Game")
		var main: Node = game.get("main") if game != null else null
		var destination: Node = (main.get("current") as Node) if is_instance_valid(main) else null
		var host: Control = destination as Control
		if host == null and is_instance_valid(destination) and destination.has_method("tutorial_host"):
			host = destination.call("tutorial_host") as Control # v0.104: the Node2D map hosts overlays on its HUD canvas.
		if is_instance_valid(host):
			search_root = host
			reparent(host, false)
			set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if tutorial != null:
		tutorial.notify_screen(screen)
		_show_step.call_deferred()   # v0.103: let a navigating button finish its pressed callbacks first.

func _on_step_changed(_index: int) -> void:
	_show_step()

func _on_completed(_skipped: bool) -> void:
	_clear_touches()
	hide()   # v0.103: release input immediately, including when auto_free is false.
	if auto_free:
		queue_free()

func _on_back() -> void:
	if tutorial != null and bool(tutorial.current().get("back", true)): # v0.104: match the disabled button.
		tutorial.back_step()

func _on_next() -> void:
	if tutorial != null:
		tutorial.next_step()

func _on_skip() -> void:
	if tutorial != null:
		tutorial.skip()
