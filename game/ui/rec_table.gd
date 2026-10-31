class_name RecTable
extends VBoxContainer
## A sortable, filterable list for the records screen (town spec part 1 section 1: "sort every list by any column").
## One layout for phone and PC: a wrapping row of column chips (tap = sort by it, tap again = reverse, the arrow
## shows which and which way), filter chips, a search box when the list has names, the shown count, then the rows
## (two lines, the whole row tappable, >= 64 px). Nothing here scrolls sideways.
##
## cols = [{k, t, num}]: the column key in each row dict, its title, numeric (sorts by value) or text.
## rows = [{<k>: value..., "_l": first-line name, "_r": main number, "_d": grey details (a String, or a Callable
##          returning one: worked out only for the rows shown), "_tap": Callable, "_col": Color, "_s": search text}]
## A column value may also be a no-argument Callable: evaluate it only when sorting that column.
## filters = [{t: title, opts: [names], fn: Callable(row, opt) -> bool}] (opts[0] is "all": everything passes)

const LIMIT := 15   # rows built at first (about a phone screen) ("Show more" adds as many again): keeps a tab switch fast

var cols: Array = []
var rows: Array = []
var filters: Array = []
var sort_k := ""
var asc := true
var fsel := {}
var search := ""
var limit := LIMIT
var _rows_box: VBoxContainer
var _count: Label
var _ctl: VBoxContainer
var display_columns: Array = []
var _heading: RecCells
var _search_box: LineEdit

## Primary visible lanes are independent of all available sort/filter keys.
func display_cells(columns: Array) -> RecTable:
	display_columns = columns
	_refresh()
	return self

func ui_state() -> Dictionary:
	return {"sort": sort_k, "asc": asc, "filters": fsel.duplicate(), "search": search, "limit": limit}

func restore_ui(state: Dictionary) -> void:
	if _col(String(state.get("sort", ""))).is_empty(): return
	sort_k = String(state["sort"])
	asc = bool(state.get("asc", true))
	fsel = state.get("filters", {}).duplicate()
	search = String(state.get("search", ""))
	limit = maxi(1, int(state.get("limit", LIMIT)))
	if _search_box != null: _search_box.set_text(search)
	_build_controls()
	_refresh()

static func make(p_cols: Array, p_rows: Array, sort_key: String = "", ascending: bool = true, p_filters: Array = [],
		searchable: bool = false, first_rows: int = LIMIT, p_display_columns: Array = []) -> RecTable:
	var t := RecTable.new()
	t.limit = first_rows
	t.cols = p_cols
	t.rows = p_rows
	t.filters = p_filters
	t.sort_k = sort_key if sort_key != "" else (String(p_cols[0]["k"]) if not p_cols.is_empty() else "")
	t.asc = ascending
	# Build the final visible lanes once when the caller already knows them.
	# Later display_cells calls still refresh current rows and lazy details.
	t.display_columns = p_display_columns
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_constant_override("separation", 6)
	t._build(searchable)
	return t

## Opens with a filter already set (e.g. Register filtered to "hungry" from the Overview).
func preset(filter_title: String, opt: String) -> void:
	fsel[filter_title] = opt
	_build_controls()
	_refresh()

func _build(searchable: bool) -> void:
	_ctl = UiKit.vbox(4)
	add_child(_ctl)
	_build_controls()
	if searchable:
		var le := LineEdit.new()
		_search_box = le
		le.placeholder_text = "Search by name"
		le.custom_minimum_size = Vector2(120, UiKit.touch_min(48))
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.add_theme_stylebox_override("normal", UiTheme.sb(UiTheme.PARCH, UiTheme.PARCH_3, 1, 3, 10, 6))
		le.add_theme_stylebox_override("focus", UiTheme.sb(UiTheme.PARCH, UiTheme.COPPER, 2, 3, 10, 6))
		le.add_theme_color_override("font_color", UiTheme.INK)
		le.add_theme_color_override("font_placeholder_color", UiTheme.INK_SOFT)
		le.add_theme_color_override("caret_color", UiTheme.INK)
		le.text_changed.connect(func(s): search = s.strip_edges().to_lower(); _refresh())
		add_child(le)
	_count = UiKit.label("", "Muted", true)
	add_child(_count)
	_rows_box = UiKit.vbox(4)
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows_box)
	_refresh()

func _build_controls() -> void:
	UiKit.clear(_ctl)
	var fl := UiKit.flow(6)
	fl.add_child(_tag("Sort"))
	var sort := OptionButton.new()
	sort.custom_minimum_size = Vector2(150, UiKit.touch_min(48))
	for i in cols.size():
		sort.add_item(String(cols[i]["t"]))
		if String(cols[i]["k"]) == sort_k: sort.select(i)
	sort.item_selected.connect(func(i): sort_by(String(cols[i]["k"])))
	fl.add_child(sort)
	fl.add_child(RecKit.chip_button("Ascending" if asc else "Descending", false, func(): sort_by(sort_k), 116))
	_ctl.add_child(fl)
	for f in filters:
		var title := String(f["t"])
		fl.add_child(_tag(title))
		var cur := String(fsel.get(title, f["opts"][0]))
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(140, UiKit.touch_min(48))
		for i in (f["opts"] as Array).size():
			pick.add_item(String(f["opts"][i]).capitalize())
			if String(f["opts"][i]) == cur: pick.select(i)
		var options: Array = f["opts"]
		pick.item_selected.connect(func(i): set_filter(title, String(options[i])))
		fl.add_child(pick)

func _tag(t: String) -> Label:
	var l := UiKit.label(t, "Small")
	l.custom_minimum_size = Vector2(0, UiKit.touch_min(48))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

## Sort by a column; the same column again reverses.
func sort_by(k: String) -> void:
	if k == sort_k:
		asc = not asc
	else:
		sort_k = k
		var c := _col(k)
		asc = not bool(c.get("num", false))   # numbers start biggest first, names A-Z
	_build_controls()
	_refresh()

func set_filter(title: String, opt: String) -> void:
	fsel[title] = opt
	_build_controls()
	_refresh()

func _col(k: String) -> Dictionary:
	for c in cols:
		if String(c["k"]) == k:
			return c
	return {}

## The rows that pass the filters and search, in the current order.
func shown() -> Array:
	var out := []
	for r in rows:
		var ok := true
		for f in filters:
			var opt := String(fsel.get(String(f["t"]), f["opts"][0]))
			if opt != String(f["opts"][0]) and not bool((f["fn"] as Callable).call(r, opt)):
				ok = false
				break
		if ok and search != "" and not String(r.get("_s", r.get("_l", ""))).to_lower().contains(search):
			ok = false
		if ok:
			out.append(r)
	# decorate once, sort on plain keys: [key, name, row]. Numbers fold the direction into the key; a missing
	# ("not tracked") number sorts after every real one either way.
	var c := _col(sort_k)
	var isnum := bool(c.get("num", false))
	var dec := []
	for r in out:
		var v: Variant = r.get(sort_k, null)
		if v is Callable:
			v = (v as Callable).call()
		var key: Variant
		if isnum:
			key = INF if (v == null or v is String) else (float(v) if asc else -float(v))
		else:
			key = (str(v) if v != null else "").to_lower()
		dec.append([key, String(r.get("_l", "")).to_lower(), r])
	var up := asc or isnum
	dec.sort_custom(func(a, b):
		if a[0] != b[0]:
			return (a[0] < b[0]) == up
		return a[1] < b[1])
	return dec.map(func(x): return x[2])

func _refresh() -> void:
	if _rows_box == null:
		return
	var s := shown()
	if _heading != null:
		remove_child(_heading)
		_heading.queue_free()
		_heading = null
	if not display_columns.is_empty():
		_heading = RecCells.new()
		_heading.configure(display_columns.map(func(c): return String(c["t"])), display_columns.map(func(c): return float(c.get("w", 1.0))), display_columns.map(func(c): return String(c["t"])), true, UiTheme.INK_SOFT)
		add_child(_heading)
		move_child(_heading, _rows_box.get_index())
	_count.text = "%d shown of %d" % [mini(s.size(), limit), rows.size()] if s.size() > limit else "%d shown of %d" % [s.size(), rows.size()]
	# Re-evaluate filtering, ordering and lazy details on every refresh. Unchanged native rows keep
	# their shaped text and connections, especially when Show more adds another page.
	var previous := _rows_box.get_children()
	var keep := mini(s.size(), limit)
	for i in range(keep, previous.size()):
		_rows_box.remove_child(previous[i])
		previous[i].queue_free()
	for i in mini(s.size(), limit):
		var r: Dictionary = s[i]
		var d: Variant = r.get("_d", "")
		if d is Callable:   # details worked out only for the rows actually shown
			d = (d as Callable).call()
		var text := [String(r.get("_l", "")), String(r.get("_r", "")), String(d)]
		var tap: Callable = r.get("_tap", Callable())
		var col: Variant = r.get("_col", null)
		var color: Color = col if col is Color else UiTheme.INK
		var old: Node = previous[i] if i < previous.size() else null
		if not display_columns.is_empty():
			var values := []
			for column: Dictionary in display_columns:
				var value: Variant = r.get(String(column["k"]), null)
				if value is Callable: value = (value as Callable).call()
				var format: Callable = column.get("format", Callable())
				values.append(format.call(value) if format.is_valid() else (RecKit.NT if value == null else (RecKit.num(float(value)) if value is float else str(value))))
			if old is RecCells and old.get_meta("rec_values") == values and old.get_meta("rec_row") == text and old.get_meta("rec_tap", Callable()) == tap and old.get_meta("rec_color", UiTheme.INK) == color:
				continue
			if old != null:
				_rows_box.remove_child(old)
				old.queue_free()
			var cell := RecCells.new()
			cell.configure(values, display_columns.map(func(c): return float(c.get("w", 1.0))), display_columns.map(func(c): return String(c["t"])))
			cell.set_meta("rec_row", text)
			cell.set_meta("rec_tap", tap)
			cell.set_meta("rec_color", color)
			for ci in display_columns.size():
				if String(display_columns[ci]["k"]) in ["state", "status", "chg"]: cell.colors[ci] = color
			cell.tooltip_text += "\n" + String(d)
			cell.accessibility_description += "\n" + String(d)
			if tap.is_valid(): cell.pressed.connect(tap)
			_rows_box.add_child(cell)
			_rows_box.move_child(cell, i)
			continue
		if old is RecRow and old.get_meta("rec_row") == text and old.right_color == color and old.get_meta("rec_tap", Callable()) == tap:
			continue
		if old != null:
			_rows_box.remove_child(old)
			old.queue_free()
		var button := RecKit.row(text[0], text[1], text[2], tap, col)
		button.set_meta("rec_tap", tap)
		_rows_box.add_child(button)
		_rows_box.move_child(button, i)
	if s.size() > limit:
		_rows_box.add_child(UiKit.button("Show %d more" % mini(LIMIT, s.size() - limit), func(): limit += LIMIT; _refresh(), "Row"))
	if s.is_empty():
		_rows_box.add_child(UiKit.label("Nothing to show.", "Muted", true))
