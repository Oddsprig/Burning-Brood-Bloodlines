class_name Tutorial
extends RefCounted
## Guided tutorial engine (v0.103): steps are data (data/tutorial.json), this class only tracks
## where the player is. ui/tutorial_overlay.gd draws the dim, the cut-out, the arrow and the
## text box, and feeds the engine the player's actions (notify_button / notify_screen /
## notify_state). A step is done by pressing Next ("next"), pressing its button ("button"),
## opening a screen ("screen") or reaching a host state ("state"); action steps advance on
## their own when the action happens, Next stays disabled until then.
##
## Progress mirrors onto the bound game (Game.tutorial_step / Game.tutorial_done, saved with
## the campaign), so a half-finished tutorial resumes where it left off after a reload.

signal step_changed(index: int)
signal completed(skipped: bool)

const DATA_PATH := "res://data/tutorial.json"
const DONE_KINDS := ["next", "button", "screen", "state"]

var steps: Array = []   # Array of Dictionary: {id, anchor, text, done: {kind, anchor, screen, key, equals}}
var index: int = 0
var active: bool = false
var is_finished: bool = false
var was_skipped: bool = false
var _game = null   # the Game autoload when bound (duck-typed: tutorial_step / tutorial_done)

## Steps from a data file (a {"steps": [...]} object or a bare array); [] when missing or unreadable.
static func load_steps(path: String = DATA_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var raw: Array = []
	if parsed is Dictionary:
		var d: Dictionary = parsed
		if d.get("steps") is Array:
			raw = d["steps"]
	elif parsed is Array:
		raw = parsed
	return validate_steps(raw)

## Keeps only usable steps and fills every field, so the overlay never has to guess.
## A step needs text; an unknown done kind becomes "next". done may be a plain string
## ("next") or a dictionary; its anchor defaults to the step's own anchor.
static func validate_steps(raw: Array) -> Array:
	var out: Array = []
	for entry in raw:
		if not entry is Dictionary:
			continue
		var s: Dictionary = entry
		var text := String(s.get("text", "")).strip_edges()
		if text == "":
			continue
		var anchor := String(s.get("anchor", ""))
		var done: Dictionary = {"kind": "next", "anchor": anchor, "screen": "", "key": "", "equals": true}
		var raw_done: Variant = s.get("done", "next")
		if raw_done is Dictionary:
			var rd: Dictionary = raw_done
			done["kind"] = String(rd.get("kind", "next"))
			done["anchor"] = String(rd.get("anchor", anchor))
			done["screen"] = String(rd.get("screen", ""))
			done["key"] = String(rd.get("key", ""))
			if rd.has("equals"):
				done["equals"] = rd["equals"]
		elif raw_done is String:
			done["kind"] = String(raw_done)
		if not DONE_KINDS.has(String(done["kind"])):
			done["kind"] = "next"
		out.append({
			"id": String(s.get("id", "step_%d" % out.size())),
			"anchor": anchor,
			"text": text,
			"done": done,
		})
	return out

func setup(p_steps: Array) -> void:
	steps = validate_steps(p_steps)
	index = 0
	active = false
	is_finished = false
	was_skipped = false

## Mirrors progress onto game.tutorial_step / game.tutorial_done (core/game.gd saves both).
func bind_game(game) -> void:
	_game = game
	# v0.103: binding a fresh engine must preserve the save until start_saved() reads it.
	if active or is_finished:
		_sync_progress()

func step_count() -> int:
	return steps.size()

func start(from_step: int = 0) -> void:
	if steps.is_empty():
		return
	index = clampi(from_step, 0, steps.size() - 1)
	active = true
	is_finished = false
	was_skipped = false
	_sync_progress()
	step_changed.emit(index)

func replay() -> void:
	start(0)

## Resumes at the saved step; does nothing once the tutorial was finished or skipped.
func start_saved() -> void:
	var at := 0
	if _game != null and "tutorial_step" in _game:
		if bool(_game.get("tutorial_done")):
			active = false   # v0.103: reflect completed saves without starting them again.
			is_finished = true
			return
		at = int(_game.get("tutorial_step"))
	start(at)

func current() -> Dictionary:
	if steps.is_empty() or index < 0 or index >= steps.size():
		return {}
	var s: Dictionary = steps[index]
	return s

func current_anchor() -> String:
	return String(current().get("anchor", ""))

func done_kind() -> String:
	var d: Dictionary = current().get("done", {})
	return String(d.get("kind", "next"))

## Next is offered on "next" steps only; action steps advance through notify_* instead.
func can_advance() -> bool:
	return active and done_kind() == "next"

func next_step() -> bool:
	if not can_advance():
		return false
	return _advance()

func back_step() -> bool:
	if not active or index <= 0:
		return false
	index -= 1
	_sync_progress()
	step_changed.emit(index)
	return true

func skip() -> void:
	if active:
		_finish(true)

## The anchored button was pressed. True when that completed the current step.
func notify_button(anchor: String) -> bool:
	if not active or done_kind() != "button":
		return false
	var d: Dictionary = current().get("done", {})
	if String(d.get("anchor", "")) != anchor:
		return false
	return _advance()

## A screen opened (Game.screen_changed). True when that completed the current step.
func notify_screen(screen: String) -> bool:
	if not active or done_kind() != "screen":
		return false
	var d: Dictionary = current().get("done", {})
	if String(d.get("screen", "")) != screen:
		return false
	return _advance()

## A host state value (the overlay polls its state_of callable). True on completion.
func notify_state(key: String, value: Variant) -> bool:
	if not active or done_kind() != "state":
		return false
	var d: Dictionary = current().get("done", {})
	if String(d.get("key", "")) != key or value != d.get("equals"):
		return false
	return _advance()

func _advance() -> bool:
	if not active:
		return false
	if index >= steps.size() - 1:
		_finish(false)
		return true
	index += 1
	_sync_progress()
	step_changed.emit(index)
	return true

func _finish(skipped: bool) -> void:
	active = false
	is_finished = true
	was_skipped = skipped
	_sync_progress()
	completed.emit(skipped)

func _sync_progress() -> void:
	if _game != null and "tutorial_step" in _game:
		_game.set("tutorial_step", index)
		_game.set("tutorial_done", is_finished)
