class_name RoundSummary
extends RefCounted
## Centred summary cards shown between battle rounds and at the end of a battle.
## Side 0 is the player. All counts are [side0, side1]; "captured" counts people taken FROM that side.

const CARD_WIDTH := 900.0


static func round_panel(d: Dictionary, on_next: Callable, battle_over: bool) -> PanelContainer:
	var panel := _card()
	var v := UiKit.vbox(14)
	panel.add_child(v)

	var winner := int(d.get("winner", -1))
	var word := "Drawn"
	var colour := UiTheme.LIGHT
	if winner == 0:
		word = "Won"
		colour = UiTheme.GOOD
	elif winner == 1:
		word = "Lost"
		colour = UiTheme.BAD
	v.add_child(_title("Round %d: %s" % [int(d.get("round", 1)), word], 38, colour))

	v.add_child(_table(d, [
		["Fought", "fought"],
		["Dead", "dead"],
		["Wounded", "wounded"],
		["Taken prisoner", "captured"],
		["Fled", "fled"],
	]))

	v.add_child(HSeparator.new())
	for side in 2:
		v.add_child(_morale_row(d, side))

	var waiting := UiKit.label("Waiting to fight: %d vs %d" % [_at(d, "fresh_left", 0), _at(d, "fresh_left", 1)])
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting.add_theme_font_size_override("font_size", 26)
	waiting.add_theme_color_override("font_color", UiTheme.LIGHT)
	v.add_child(waiting)
	var am: Dictionary = d.get("aftermath", {})
	if int(am.get("medics", 0)) > 0:
		var al := UiKit.label("Aftermath: %d medics · %d of the holders' wounded bandaged · %d enemy wounded taken and tended · %d bled out" % [int(am["medics"]), int(am["tended_own"]), int(am["tended_enemy"]), int(am["bled_out"][0]) + int(am["bled_out"][1])], "", true)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		al.add_theme_font_size_override("font_size", 20)
		al.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		v.add_child(al)

	_household(v, d)

	var broke := int(d.get("broke", -1))
	if broke >= 0:
		var line := UiKit.label("%s breaks and flees the field" % _name(d, broke), "H2", true)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 30)
		line.add_theme_color_override("font_color", UiTheme.BAD if broke == 0 else UiTheme.GOOD)
		v.add_child(line)

	v.add_child(_centred_button("Battle summary" if battle_over else "Next round", func() -> void:
		if on_next.is_valid():
			on_next.call()))
	return panel


static func battle_panel(d: Dictionary, on_continue: Callable) -> PanelContainer:
	var panel := _card()
	var v := UiKit.vbox(14)
	panel.add_child(v)

	var winner := int(d.get("winner", -1))
	var word := "STALEMATE"
	var colour := UiTheme.LIGHT
	if winner == 0:
		word = "VICTORY"
		colour = UiTheme.BRASS
	elif winner == 1:
		word = "DEFEAT"
		colour = UiTheme.BAD
	v.add_child(_title(word, 56, colour))

	var rounds := int(d.get("rounds", 0))
	var sub := UiKit.label("%d round%s" % [rounds, "" if rounds == 1 else "s"], "Muted")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	v.add_child(sub)

	v.add_child(_table(d, [
		["Started", "start"],
		["Dead", "dead"],
		["Wounded", "wounded"],
		["Taken prisoner", "captured"],
		["Fled", "fled"],
		["Left standing", "left"],
	]))

	_household(v, d)

	var retreat := String(d.get("retreat", ""))
	if retreat != "":
		var line := UiKit.label(retreat, "Muted", true)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 22)
		v.add_child(line)

	v.add_child(_centred_button("Continue", func() -> void:
		if on_continue.is_valid():
			on_continue.call()))
	return panel


static func _card() -> PanelContainer:
	var p := UiKit.panel("Card")
	p.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", UiTheme.sb(Color(0.08, 0.07, 0.06, 0.95), UiTheme.BORDER, 2, 10, 24, 20))
	return p


static func _title(text: String, px: int, colour: Color) -> Label:
	var t := UiKit.label(text, "H2", true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", px)
	t.add_theme_color_override("font_color", colour)
	return t


## Grid: row label, then one wide column per side. rows = [[display, key], ...].
static func _table(d: Dictionary, rows: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 10)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(UiKit.label(""))
	for side in 2:
		var head := UiKit.label(_name(d, side), "H2", true)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_theme_font_size_override("font_size", 26)
		head.add_theme_color_override("font_color", UiTheme.BRASS if side == 0 else UiTheme.LIGHT)
		g.add_child(head)
	for r in rows:
		var row: Array = r
		var key := UiKit.label(String(row[0]), "Muted")
		key.add_theme_font_size_override("font_size", 22)
		key.add_theme_color_override("font_color", UiTheme.INK_SOFT)
		g.add_child(key)
		for side in 2:
			var val := UiKit.label(str(_at(d, String(row[1]), side)))
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			val.add_theme_font_size_override("font_size", 28)
			val.add_theme_color_override("font_color", UiTheme.LIGHT)
			g.add_child(val)
	return g


static func _morale_row(d: Dictionary, side: int) -> HBoxContainer:
	var h := UiKit.hbox(12)
	var morale := clampi(_at(d, "morale", side), 0, 100)
	var change := _at(d, "morale_change", side)

	var who := UiKit.label(_name(d, side), "Muted", true)
	who.custom_minimum_size = Vector2(220, 0)
	who.add_theme_font_size_override("font_size", 20)
	who.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	h.add_child(who)

	var bar_colour := UiTheme.GOOD
	if morale < 30:
		bar_colour = UiTheme.BAD
	elif morale < 60:
		bar_colour = UiTheme.WARN
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = morale
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UiTheme.sb(UiTheme.WOOD, UiTheme.BORDER, 1, 6, 0, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.sb(bar_colour, bar_colour.darkened(0.3), 1, 6, 0, 0))
	h.add_child(bar)

	var sign := "+" if change > 0 else ""
	var num := UiKit.label("%d (%s%d)" % [morale, sign, change])
	num.custom_minimum_size = Vector2(150, 0)
	num.add_theme_font_size_override("font_size", 26)
	var num_colour := UiTheme.LIGHT
	if change > 0:
		num_colour = UiTheme.GOOD
	elif change < 0:
		num_colour = UiTheme.BAD
	num.add_theme_color_override("font_color", num_colour)
	h.add_child(num)
	return h


static func _household(v: VBoxContainer, d: Dictionary) -> void:
	var rows: Array = d.get("household", []) if d.get("household", []) is Array else []
	if rows.is_empty():
		return
	v.add_child(HSeparator.new())
	var head := UiKit.label("Household", "H2")
	head.add_theme_font_size_override("font_size", 24)
	head.add_theme_color_override("font_color", UiTheme.BRASS)
	v.add_child(head)
	if rows.size() > 8:
		var more := UiKit.label("and %d more" % (rows.size() - 8), "Muted")
		more.set_meta("after_rows", true)
		rows = rows.slice(0, 8)
		v.set_meta("household_more", more)
	for r in rows:
		if not (r is Dictionary):
			continue
		var row: Dictionary = r
		var h := UiKit.hbox(12)
		var who := UiKit.label(String(row.get("name", "")), "", true)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_theme_font_size_override("font_size", 22)
		who.add_theme_color_override("font_color", UiTheme.LIGHT)
		h.add_child(who)
		var rel := String(row.get("relation", ""))
		if rel != "":
			var rel_l := UiKit.label(rel, "Muted")
			rel_l.add_theme_font_size_override("font_size", 20)
			rel_l.add_theme_color_override("font_color", UiTheme.INK_SOFT)
			h.add_child(rel_l)
		var fate := String(row.get("fate", ""))
		var fate_l := UiKit.label(fate.capitalize())
		fate_l.add_theme_font_size_override("font_size", 22)
		fate_l.add_theme_color_override("font_color", _fate_colour(fate))
		h.add_child(fate_l)
		v.add_child(h)
	if v.has_meta("household_more"):
		v.add_child(v.get_meta("household_more"))
		v.remove_meta("household_more")


static func _fate_colour(fate: String) -> Color:
	match fate:
		"dead":
			return UiTheme.BAD
		"wounded", "captured":
			return UiTheme.WARN
		"unhurt":
			return UiTheme.GOOD
		"raised", "honoured":
			return UiTheme.BRASS
		_:
			return UiTheme.INK_SOFT  # fled and anything unknown


static func _centred_button(text: String, cb: Callable) -> CenterContainer:
	var c := CenterContainer.new()
	var b := UiKit.button(text, cb, "Row", 340)
	b.add_theme_font_size_override("font_size", 24)
	c.add_child(b)
	return c


static func _name(d: Dictionary, side: int) -> String:
	var names: Variant = d.get("names", [])
	if names is Array and side < (names as Array).size():
		return String((names as Array)[side])
	return "Side %d" % (side + 1)


static func _at(d: Dictionary, key: String, side: int) -> int:
	var arr: Variant = d.get(key, [])
	if arr is Array and side < (arr as Array).size():
		return int((arr as Array)[side])
	return 0
