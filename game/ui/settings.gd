extends Control
## Settings screen ("settings"): one toggle per Game.SETTING_LABELS entry, saved with Game.set_setting.
## As a screen: Back -> Game.screen_params["back"] (default "title").
## As an overlay (e.g. over a battle): `var s = load("res://ui/settings.tscn").instantiate(); s.overlay = true;
## add_child(s)` -- Back then just frees it, and a dim backdrop covers the scene underneath.

var overlay := false
var list: VBoxContainer

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	if overlay:
		var dim := ColorRect.new()
		dim.color = Color(0.05, 0.03, 0.01, 0.75)
		dim.set_anchors_preset(PRESET_FULL_RECT)
		add_child(dim)
	else:
		var bg := ColorRect.new()
		bg.color = UiTheme.WOOD
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.set_anchors_preset(PRESET_FULL_RECT)
		add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	add_child(margin)
	var fit_margin: Callable = func():
		UiKit.apply_safe_area(margin, 16, 16, 16, 16)
		margin.offset_right = -UiKit.diagnostics_lane(size.x)
	resized.connect(fit_margin)
	fit_margin.call()
	var scroll := UiKit.scroll()
	margin.add_child(scroll)
	var p := UiKit.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	var top := UiKit.hbox()
	var t := UiKit.label("Settings", "H2", true)
	t.add_theme_font_size_override("font_size", 32)
	top.add_child(t)
	top.add_child(UiKit.button("Back", _back, "", 72))
	v.add_child(top)
	v.add_child(HSeparator.new())
	list = UiKit.vbox(8)
	v.add_child(list)
	_build()

func _build() -> void:
	UiKit.clear(list)
	list.add_child(UiKit.label("Gameplay", "H2"))
	list.add_child(_toggle_row("battle_event_slowmo", String(Game.SETTING_LABELS["battle_event_slowmo"])))
	list.add_child(UiKit.label("Slow down briefly for severe battle injuries. OFF keeps your chosen playback speed.", "Muted", true))
	# v0.014: settings with named choices (Gore: Full / Reduced); the button shows the current one and cycles
	var choices: Dictionary = Game.SETTING_CHOICES if "SETTING_CHOICES" in Game else {}
	for key in choices:
		var c: Dictionary = choices[key]
		var opts: Array = c["options"]
		var cur: Variant = Game.setting(key)
		var idx := 0
		for i in opts.size():
			if opts[i][0] == cur:
				idx = i
		var row := UiKit.panel("Card")
		var cv := UiKit.vbox(4)
		row.add_child(cv)
		var h := UiKit.hbox(12)
		cv.add_child(h)
		var l := UiKit.label(String(c["label"]), "H2", true)
		l.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 22)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
		var nxt: Variant = opts[(idx + 1) % opts.size()][0]
		var b := UiKit.button(String(opts[idx][1]), func():
			Game.set_setting(key, nxt)
			_build(), "", 100)
		b.name = "Choice_" + key
		h.add_child(b)
		if c.has("hint"):
			var hl := UiKit.label(String(c["hint"]), "Muted")
			hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cv.add_child(hl)
		list.add_child(row)
	list.add_child(UiKit.label("Battle event animations (off by default)", "Muted", true))
	var labels: Dictionary = Game.SETTING_LABELS if "SETTING_LABELS" in Game else {}
	if labels.is_empty():
		list.add_child(UiKit.label("No settings yet.", "Muted"))
	for key in labels:
		if key == "battle_event_slowmo": continue
		list.add_child(_toggle_row(String(key), String(labels[key])))

func _toggle_row(key: String, text: String) -> PanelContainer:
	var on: bool = bool(Game.setting(key))
	var row: PanelContainer = UiKit.panel("Card")
	var h: HBoxContainer = UiKit.hbox(12)
	row.add_child(h)
	var label: Label = UiKit.label(text, "H2", true)
	label.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 22)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(label)
	var button: Button = UiKit.button("ON" if on else "OFF", func():
		Game.set_setting(key, not bool(Game.setting(key)))
		_build(), "" if on else "Row", 80)
	button.name = "Toggle_" + key
	h.add_child(button)
	return row

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_back()
		get_viewport().set_input_as_handled()

func _back() -> void:
	if overlay:
		queue_free()
		return
	Game.goto(String(Game.screen_params.get("back", "title")))
