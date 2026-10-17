class_name CombatLogBrowser
extends VBoxContainer
## Formats detached visible pages only. The shared journal belongs to its owner.
const PAGE_SIZE := 18
var journal: RefCounted
var participant: int = -1
var page_index: int = 0
var _participants: Array = []
var _side_names: Array = []
var _page_rows: Array = []
var _expanded_seq: int = -1
var _formatted_total: int = 0
var _recorded: int = 0
var _matched: int = 0
var _complete: bool = false
var _error: String = ""
var _state: Label
var _selector: OptionButton
var _search: LineEdit
var _marker: Label
var _first: Button
var _previous: Button
var _next: Button
var _last: Button
var rows_scroll: ScrollContainer
var _rows: VBoxContainer

func begin(value: RefCounted, side_names: Array = []) -> void:
	journal = null
	if value != null and value.has_method("participants") and value.has_method("page") and value.has_method("count") and value.has_method("stats"):
		journal = value
	_side_names = side_names.duplicate()
	_participants = journal.call("participants") if journal != null else []
	participant = -1; page_index = 0; _expanded_seq = -1
	_page_rows = []
	if is_node_ready():
		_search.text = ""
		_filter_people("")
		refresh()

func _ready() -> void:
	theme = UiTheme.get_theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_state = UiKit.label("", "Muted", true); _state.name = "CombatLogStatus"
	_state.add_theme_font_size_override("font_size", 16)
	add_child(_state)
	var people := UiKit.hbox(8)
	add_child(people)
	_search = LineEdit.new(); _search.name = "CombatLogSearch"
	_search.placeholder_text = "Find a name"
	_search.max_length = 64
	_search.custom_minimum_size = Vector2(150, 48)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_filter_people)
	people.add_child(_search)
	_selector = OptionButton.new(); _selector.name = "CombatLogParticipant"
	_selector.custom_minimum_size = Vector2(160, 48)
	_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_selector.item_selected.connect(func(index: int): set_participant(int(_selector.get_item_metadata(index))))
	people.add_child(_selector)
	var nav := UiKit.hbox(6)
	add_child(nav)
	_first = UiKit.button("First", func(): _set_page(0), "", 64); _first.name = "CombatLogFirst"
	_previous = UiKit.button("Previous", func(): turn_page(-1), "", 100); _previous.name = "CombatLogPrevious"
	_marker = UiKit.label("", "Muted", true); _marker.name = "CombatLogPage"
	_marker.add_theme_font_size_override("font_size", 16)
	_next = UiKit.button("Next", func(): turn_page(1), "", 72); _next.name = "CombatLogNext"
	_last = UiKit.button("Last", func(): _set_page(_page_count() - 1), "", 64); _last.name = "CombatLogLast"
	for control: Control in [_first, _previous, UiKit.expand(_marker), _next, _last]: nav.add_child(control)
	rows_scroll = UiKit.scroll(); rows_scroll.name = "CombatLogScroll"
	rows_scroll.custom_minimum_size.y = 240
	add_child(rows_scroll)
	_rows = UiKit.vbox(8); _rows.name = "CombatLogRows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_scroll.add_child(_rows)
	_filter_people("")
	refresh()

func _filter_people(query: String) -> void:
	if _selector == null: return
	_selector.clear(); _selector.add_item("All combatants"); _selector.set_item_metadata(0, -1)
	var selected_item: int = 0
	var needle: String = query.strip_edges().to_lower()
	var names: Dictionary = {}
	for row: Dictionary in _participants:
		var idx: int = int(row.get("idx", -1))
		var person_name: String = String(row.get("name", "Unnamed combatant"))
		var matches: bool = needle == "" or person_name.to_lower().contains(needle)
		if not matches and idx != participant: continue
		var side: int = int(row.get("side", -1))
		var side_name: String = String(_side_names[side]) if side >= 0 and side < _side_names.size() else ("Side %d" % (side + 1))
		var label_text: String = "%s · %s" % [person_name, side_name]
		names[label_text] = int(names.get(label_text, 0)) + 1
		var duplicate: int = int(names[label_text])
		if duplicate > 1: label_text += " (%d)" % duplicate
		# Searching names never silently switches the displayed history. An unmatched
		# selected person is explicitly identified, separate from search matches.
		if not matches: label_text = "Current: " + label_text
		var index: int = _selector.item_count
		_selector.add_item(label_text); _selector.set_item_metadata(index, idx)
		if idx == participant: selected_item = index
	_selector.select(selected_item)

func set_participant(idx: int = -1) -> void:
	var known: bool = idx == -1
	for row: Dictionary in _participants:
		if int(row.get("idx", -2)) == idx: known = true; break
	participant = idx if known else -1
	page_index = 0; _expanded_seq = -1
	if is_node_ready():
		_filter_people(_search.text)
		refresh()

func turn_page(delta: int) -> void:
	_set_page(page_index + delta)

func _set_page(index: int) -> void:
	page_index = clampi(index, 0, _page_count() - 1)
	_expanded_seq = -1
	if is_node_ready(): refresh()

func _page_count() -> int:
	return maxi(1, ceili(float(_matched) / PAGE_SIZE))

func refresh() -> void:
	if not is_node_ready(): return
	var started: int = Time.get_ticks_usec()
	UiKit.clear(_rows)
	_page_rows = []
	_expanded_seq = -1
	_recorded = int(journal.call("count", -1)) if journal != null else 0
	_matched = int(journal.call("count", participant)) if journal != null else 0
	var stats: Dictionary = journal.call("stats") if journal != null else {}
	_complete = bool(stats.get("complete", false)) and not bool(stats.get("disposed", false))
	_error = String(stats.get("error", ""))
	page_index = clampi(page_index, 0, _page_count() - 1)
	_state.text = "Recorded so far: %s outcomes · chronological order" % UiKit.thousands(_recorded) if _complete else "Incomplete log: %s readable outcomes%s" % [UiKit.thousands(_recorded), " · " + _error if _error != "" else " · recording unavailable"]
	if journal == null: _state.text = "No combat log recorded."
	_marker.text = "Page %d / %d · %s matching" % [page_index + 1, _page_count(), UiKit.thousands(_matched)]
	_first.disabled = page_index == 0; _previous.disabled = page_index == 0
	_last.disabled = page_index + 1 >= _page_count(); _next.disabled = _last.disabled
	if journal != null: _page_rows = journal.call("page", page_index, participant, PAGE_SIZE)
	# Direct chunk reads can expose an IO error; report that on this same refresh.
	if journal != null:
		stats = journal.call("stats")
		Perf.record_combat_history(stats)
		_recorded = int(journal.call("count", -1))
		_matched = int(journal.call("count", participant))
		_complete = bool(stats.get("complete", false)) and not bool(stats.get("disposed", false))
		_error = String(stats.get("error", ""))
		if not _complete: _state.text = "Incomplete log: %s readable outcomes%s" % [UiKit.thousands(_recorded), " · " + _error if _error != "" else " · recording unavailable"]
		page_index = clampi(page_index, 0, _page_count() - 1)
		_marker.text = "Page %d / %d · %s matching" % [page_index + 1, _page_count(), UiKit.thousands(_matched)]
		_first.disabled = page_index == 0; _previous.disabled = page_index == 0
		_last.disabled = page_index + 1 >= _page_count(); _next.disabled = _last.disabled
	else: Perf.record_combat_history()
	# Defensively bound even a malformed external reader; never build off-page controls.
	if _page_rows.size() > PAGE_SIZE: _page_rows.resize(PAGE_SIZE)
	for row: Dictionary in _page_rows: _build_row(row)
	if _page_rows.is_empty(): _rows.add_child(UiKit.label("No recorded outcomes for this selection.", "Muted", true))
	rows_scroll.scroll_vertical = 0
	Perf.record_us("Combat log page", Time.get_ticks_usec() - started)

func _build_row(row: Dictionary) -> void:
	var entry: Dictionary = (row.get("entry", {}) as Dictionary).duplicate(true)
	var rendered: Dictionary = CombatText.render(entry)
	_formatted_total += 1
	var seq: int = int(row.get("seq", -1))
	var card := UiKit.panel("Card"); card.name = "CombatLogRow%d" % seq
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("combat_log_row", true); card.set_meta("sequence", seq)
	_rows.add_child(card)
	var box := UiKit.vbox(5); card.add_child(box)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := UiKit.hbox(8); box.add_child(header)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text: String = String(rendered.get("text", ""))
	if text == "": text = "Recorded %s outcome; description unavailable." % String(row.get("event_type", "combat"))
	var line := UiKit.label("Tick %d · %s" % [int(row.get("tick", entry.get("tick", 0))), text], "", true)
	line.name = "CombatLogLine"
	line.add_theme_font_size_override("font_size", 17)
	header.add_child(line)
	var button := UiKit.button("Details", func(): _toggle_row(seq), "", 84)
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.name = "CombatLogDetails%d" % seq
	button.add_theme_font_size_override("font_size", 16)
	header.add_child(button)
	var detail := UiKit.vbox(5); detail.name = "CombatLogExpanded%d" % seq
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.visible = false; box.add_child(detail)
	# Rendered strings belong only to this visible page, never to the journal.
	card.set_meta("rendered", rendered)

func _toggle_row(seq: int) -> void:
	_expanded_seq = -1 if _expanded_seq == seq else seq
	for card: Node in _rows.get_children():
		if not card.get_meta("combat_log_row", false): continue
		var key: int = int(card.get_meta("sequence", -1))
		var detail: VBoxContainer = card.find_child("CombatLogExpanded%d" % key, true, false)
		UiKit.clear(detail)
		detail.visible = key == _expanded_seq
		var button: Button = card.find_child("CombatLogDetails%d" % key, true, false)
		button.text = "Hide" if detail.visible else "Details"
		if not detail.visible: continue
		var rendered: Dictionary = card.get_meta("rendered", {})
		var lines: Array = rendered.get("detail", [])
		if not lines.is_empty(): detail.add_child(UiKit.label("\n".join(PackedStringArray(lines)), "Small", true))
		var calc: String = String(rendered.get("calc", ""))
		if calc != "": detail.add_child(UiKit.label("Calculations: " + calc, "Muted", true))
		if lines.is_empty() and calc == "": detail.add_child(UiKit.label("No tissue or calculation detail recorded for this outcome.", "Muted", true))

func detail_stats() -> Dictionary:
	var expanded: int = 0
	if _rows != null:
		for card: Node in _rows.get_children():
			if card.get_meta("combat_log_row", false) and int(card.get_meta("sequence", -1)) == _expanded_seq: expanded += 1
	return {"page": page_index, "page_size": PAGE_SIZE, "participant": participant, "matched_count": _matched,
		"rows": _page_rows.size(), "expanded_rows": expanded, "journal_count": _recorded, "complete": _complete,
		"error": _error, "formatted_total": _formatted_total, "participant_options": _selector.item_count if _selector != null else 0}

func _exit_tree() -> void:
	journal = null; _participants = []; _page_rows = []; _side_names = []
