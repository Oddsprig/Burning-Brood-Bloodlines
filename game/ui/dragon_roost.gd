class_name DragonRoost
extends Control
## A still, read-only household comparison in native art units (a human is 24).
## Only copied display records and existing DragonCard/Paperdoll caches are used.
signal selected(uid: String)

const GAP := 12.0
# Eggs have no linear growth profile. Use a half-human shell, never their adult size.
const EGG_HEIGHT := 12.0

class Yard extends Control:
	var roost
	func _draw() -> void:
		if roost != null: roost._paint(self)
	func _get_tooltip(at: Vector2) -> String:
		return roost._tooltip(at) if roost != null else ""

var selected_uid := ""
var _entries: Array = []
var _yard: Yard
var _panel: PanelContainer
var _selector: OptionButton
var _facts: VBoxContainer
var _scale := 1.0
var _origin := Vector2.ZERO
var _native_bounds := Rect2()

func _ready() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	_yard = Yard.new()
	_yard.name = "RoostYard"
	_yard.roost = self
	_yard.clip_contents = true
	_yard.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_yard.gui_input.connect(_yard_input)
	add_child(_yard)
	_panel = UiKit.panel("Card")
	_panel.name = "RoostDetails"
	add_child(_panel)
	var column := UiKit.vbox(8)
	_panel.add_child(column)
	column.add_child(UiKit.label("The dragon roost", "H2", true))
	_selector = OptionButton.new()
	_selector.name = "RoostSelection"
	_selector.custom_minimum_size.y = UiKit.TAP
	_selector.fit_to_longest_item = false
	_selector.clip_text = true
	_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selector.item_selected.connect(func(index: int): select(str(_entries[index]["row"]["id"])))
	column.add_child(_selector)
	var scroll := UiKit.scroll()
	column.add_child(scroll)
	_facts = UiKit.vbox(8)
	_facts.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_facts)
	resized.connect(_layout)
	set_process(false)
	_layout()

func set_records(rows: Array, uid: String = "") -> void:
	UiKit.clear(_yard)
	_entries.clear()
	_selector.clear()
	selected_uid = ""
	var left := 0.0
	var top := 0.0
	var bottom := 0.0
	for source: Dictionary in rows:
		var row := source.duplicate(true)
		var entry := {"row": row, "model": {}, "egg": {}, "people": [], "factor": 1.0,
			"offset": Vector2(left, 0), "model_origin": Vector2.ZERO}
		var dragon_bounds: Rect2
		if str(row.get("stage", "")) == "egg":
			entry["egg"] = DragonCard.egg_visual(row)
			var shell: Rect2 = entry["egg"]["source"]
			dragon_bounds = Rect2(0, -EGG_HEIGHT, EGG_HEIGHT * shell.size.x / maxf(1, shell.size.y), EGG_HEIGHT)
		else:
			var model := DragonCard.cached_model(row, "rest" if bool(row.get("alive", true)) else "dead")
			if not bool(model.get("valid", false)): continue
			var factor := DragonView.physical_ppu(row, model) / DragonView.NATIVE_PPU
			if factor <= 0.0: continue
			entry["model"] = model
			entry["factor"] = factor
			var bounds: Rect2 = model["bounds"]
			entry["model_origin"] = Vector2(-bounds.position.x, -float(model["ground_y"])) * factor
			dragon_bounds = Rect2(bounds.position * factor + entry["model_origin"], bounds.size * factor)
		entry["dragon_bounds"] = dragon_bounds
		var group := dragon_bounds
		var right := dragon_bounds.end.x + GAP
		for role: Array in [["Keeper", "custodian_person_uid"], ["Rider", "rider_person_uid"]]:
			var person_uid := str(row.get(role[1], ""))
			if person_uid == "": continue
			var already := false
			for shown: Dictionary in entry["people"]:
				if str(shown["uid"]) == person_uid:
					shown["role"] += " / " + str(role[0])
					already = true
			if already: continue
			var person := Dynasty.person(Game, person_uid)
			if person.is_empty() or not bool(person.get("alive", false)): continue
			var spec := Dynasty.portrait_for(Game, person)
			var doll := Paperdoll.new()
			doll.set_spec(spec.duplicate(true))
			_yard.add_child(doll)
			var race := str(spec.get("race", "human"))
			var dimensions := FigurePainter.dims(race)
			var raster := FigurePainter.raster_scale(race)
			var person_bounds := Rect2(-Vector2(dimensions["anchor"]) / raster, Vector2(dimensions["size"]) / raster)
			var feet := Vector2(right - person_bounds.position.x, 0)
			var placed := Rect2(person_bounds.position + feet, person_bounds.size)
			entry["people"].append({"uid": person_uid, "name": str(person.get("name", "")),
				"role": str(role[0]), "doll": doll, "feet": feet, "bounds": placed})
			group = group.merge(placed)
			right = placed.end.x + GAP
		entry["bounds"] = group
		_entries.append(entry)
		_selector.add_item("%d. %s" % [_entries.size(), str(row.get("name", "Unnamed holding"))])
		left += group.size.x + GAP
		top = minf(top, group.position.y)
		bottom = maxf(bottom, group.end.y)
	_native_bounds = Rect2(0, top, maxf(1, left - GAP), maxf(1, bottom - top))
	_selector.disabled = _entries.is_empty()
	_layout()
	if _entries.is_empty():
		UiKit.clear(_facts)
		_facts.add_child(UiKit.label("No dragons or eggs belong to this household.", "Muted", true))
	else:
		var found := false
		for entry: Dictionary in _entries:
			if str(entry["row"]["id"]) == uid: found = true
		select(uid if found else str(_entries[0]["row"]["id"]))

func _layout() -> void:
	if _yard == null: return
	var width := maxf(1, size.x)
	var height := maxf(1, size.y)
	if width >= 820:
		var panel_width := clampf(width * 0.32, 260, 360)
		_yard.position = Vector2.ZERO
		_yard.size = Vector2(width - panel_width - GAP, height)
		_panel.position = Vector2(_yard.size.x + GAP, 0)
		_panel.size = Vector2(panel_width, height)
	else:
		var yard_height := height * 0.55
		_yard.position = Vector2.ZERO
		_yard.size = Vector2(width, yard_height)
		_panel.position = Vector2(0, yard_height + GAP)
		_panel.size = Vector2(width, maxf(1, height - yard_height - GAP))
	_scale = maxf(0.00001, minf(maxf(1, _yard.size.x - 24) / maxf(1, _native_bounds.size.x),
		maxf(1, _yard.size.y - 48) / maxf(1, _native_bounds.size.y)))
	_origin = Vector2((_yard.size.x - _native_bounds.size.x * _scale) * 0.5,
		(_yard.size.y - 28 - _native_bounds.size.y * _scale) * 0.5 - _native_bounds.position.y * _scale)
	for entry: Dictionary in _entries:
		var at: Vector2 = _origin + entry["offset"] * _scale
		var bounds: Rect2 = entry["bounds"]
		entry["screen_bounds"] = Rect2(at + bounds.position * _scale, bounds.size * _scale)
		var dragon: Rect2 = entry["dragon_bounds"]
		entry["dragon_rect"] = Rect2(at + dragon.position * _scale, dragon.size * _scale)
		for person: Dictionary in entry["people"]:
			var doll: Paperdoll = person["doll"]
			doll.position = at + person["feet"] * _scale
			doll.scale = Vector2.ONE * _scale / FigurePainter.PX
	_yard.queue_redraw()

func select(uid: String) -> void:
	if uid == selected_uid: return
	for index: int in _entries.size():
		var row: Dictionary = _entries[index]["row"]
		if str(row["id"]) != uid: continue
		selected_uid = uid
		_selector.select(index)
		UiKit.clear(_facts)
		_facts.add_child(UiKit.label(str(row.get("name", "Holding")), "H2", true))
		var quote := DragonCare.status(Game, row)
		_facts.add_child(UiKit.label(DragonsView.care_condition_text(row, quote), "", true))
		var growth := DragonGrowth.summary(row, quote)
		if not bool(row.get("alive", true)):
			growth = ("Size band: Unhatched" if str(row.get("stage", "")) == "egg" else growth) + "\nGrowth: deceased."
		elif str(row.get("stage", "")) == "egg":
			growth = "Size band: Unhatched\nGrowth: awaiting hatching.\nIncubation: %.1f / %d days of care" % [
				float(row.get("incubation", 0.0)), int(DragonLife.HATCH_DAYS)]
		elif not growth.contains("Growth is stalled:"):
			growth += "\nGrowth: no current stall."
		_facts.add_child(UiKit.label("Stage: %s\n%s" % [str(row.get("stage", "")).capitalize(), growth], "", true))
		var bond := DragonBond.status(Game, uid)
		var rider: Dictionary = bond.get("rider", {})
		var bond_line := "Bond: Unbonded"
		if bool(bond.get("bonded", false)):
			bond_line = "Bond: %s (%s)" % [str(rider.get("name", "Unrecorded rider")), "active" if bool(bond.get("active", false)) else "inactive"]
		_facts.add_child(UiKit.label(bond_line, "", true))
		var approach := DragonBond.approach_status(Game, uid)
		_facts.add_child(UiKit.label(str(approach.get("line", "")), "", true))
		if str(approach.get("reason", "")) != "":
			_facts.add_child(UiKit.label(str(approach["reason"]), "Muted", true))
		for person: Dictionary in _entries[index]["people"]:
			_facts.add_child(UiKit.label("%s: %s" % [person["role"], person["name"]], "Muted", true))
		_facts.add_child(UiKit.label(DragonsView.care_quote_text(row, quote), "", true))
		_facts.add_child(UiKit.label(DragonsView.care_receipt_text(row, quote.get("last", {})), "Muted", true))
		_yard.queue_redraw()
		selected.emit(uid)
		return

func _uid_at(at: Vector2) -> String:
	for entry: Dictionary in _entries:
		if (entry["screen_bounds"] as Rect2).grow(6).has_point(at):
			return str(entry["row"]["id"])
	return ""

func _yard_input(event: InputEvent) -> void:
	var at: Vector2
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		at = event.position
	elif event is InputEventScreenTouch and event.pressed:
		at = event.position
	else:
		return
	var uid := _uid_at(at)
	if uid != "":
		select(uid)
		_yard.accept_event()

func _tooltip(at: Vector2) -> String:
	var uid := _uid_at(at)
	for entry: Dictionary in _entries:
		if str(entry["row"]["id"]) != uid: continue
		var text := str(entry["row"].get("name", "Holding"))
		for person: Dictionary in entry["people"]:
			text += "\n%s: %s" % [person["role"], person["name"]]
		return text
	return ""

func _paint(canvas: Control) -> void:
	canvas.draw_style_box(UiTheme.sb(UiTheme.WOOD_3, UiTheme.PURPLE, 1), Rect2(Vector2.ZERO, canvas.size))
	if _entries.is_empty(): return
	canvas.draw_line(Vector2(12, _origin.y), Vector2(canvas.size.x - 12, _origin.y), UiTheme.PURPLE)
	for index: int in _entries.size():
		var entry: Dictionary = _entries[index]
		var row: Dictionary = entry["row"]
		var at: Vector2 = _origin + entry["offset"] * _scale
		if not (entry["egg"] as Dictionary).is_empty():
			canvas.draw_texture_rect_region(entry["egg"]["texture"], entry["dragon_rect"], entry["egg"]["source"])
		else:
			DragonRigArt.draw_canvas_model(canvas, entry["model"], at + entry["model_origin"] * _scale,
				_scale * float(entry["factor"]), int(row.get("appearance_seed", 0)))
		var area: Rect2 = entry["screen_bounds"]
		if str(row["id"]) == selected_uid:
			canvas.draw_rect(area.grow(4), UiTheme.WARN, false, 2)
		canvas.draw_string(UiTheme.regular_font(), Vector2(area.get_center().x - 5, canvas.size.y - 8),
			str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.LIGHT)

func _exit_tree() -> void:
	# Shared art caches remain bounded and reusable; drop all view-owned references.
	_entries.clear()
	if _yard != null: _yard.roost = null
