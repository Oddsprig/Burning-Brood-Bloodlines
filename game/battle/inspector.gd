extends PanelContainer
## Unit inspector: tap a unit on the battle map to open. Stays live while the battle runs.
## Header (name, faction, title, gear), live state + speed line, and two tabs:
##   Log    - the fighter's log (BattleSim.render_entry): story line; tap for per-tissue detail, tap again for calc.
##   Health - HealthReport.describe(unit) rendered DF-health-screen style. No HP bars.

signal closed
signal history_requested(idx: int)

const WIDTH := 470.0
const SEV_COLORS := ["#d8d8d0", "#f2d64b", "#ff9a3c", "#ff4a3a"]
const STATE_WORDS := {"ready": "ready", "moving": "moving", "preparing": "preparing an attack",
	"recovering": "recovering from an attack", "prone": "lying on the ground", "unconscious": "unconscious",
	"dead": "dead", "fled": "fled the field"}

var fighter = null
var sim = null
const LOG_WINDOW := 150             # rows built when the inspector opens on a long log
var tab := "log"
var _log_count := 0
var _log_first := 0
var _log_offset := 0
var _health_age := 0.0
var _stick_bottom := true

var name_label: Label
var info_label: Label
var state_label: Label
var log_btn: Button
var health_btn: Button
var log_scroll: ScrollContainer
var log_box: VBoxContainer
var health_text: RichTextLabel

func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.07, 0.94)
	sb.border_color = Color(0.85, 0.62, 0.25)
	sb.border_width_left = 3
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	name_label = Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", Color(1, 0.88, 0.55))
	name_label.clip_text = true
	head.add_child(name_label)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(56, 56)
	close.pressed.connect(func(): closed.emit())
	head.add_child(close)
	info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 16)
	info_label.add_theme_color_override("font_color", Color(0.86, 0.84, 0.78))
	v.add_child(info_label)
	state_label = Label.new()
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_label.add_theme_font_size_override("font_size", 17)
	state_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	v.add_child(state_label)
	var tabs := HBoxContainer.new()
	v.add_child(tabs)
	var complete := Button.new()
	complete.name = "InspectorFullHistory"
	complete.text = "Full combat history · pause & read"
	complete.custom_minimum_size.y = 42
	complete.pressed.connect(func():
		if fighter != null: history_requested.emit(fighter.idx))
	v.add_child(complete)
	log_btn = _tab_button("Log", "log")
	tabs.add_child(log_btn)
	health_btn = _tab_button("Health", "health")
	tabs.add_child(health_btn)
	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(log_scroll)
	log_box = VBoxContainer.new()
	log_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_box.add_theme_constant_override("separation", 2)
	log_scroll.add_child(log_box)
	log_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	health_text = RichTextLabel.new()
	health_text.bbcode_enabled = true
	health_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	health_text.scroll_active = true
	health_text.add_theme_font_size_override("normal_font_size", 17)
	health_text.add_theme_font_size_override("bold_font_size", 18)
	v.add_child(health_text)
	_set_tab("log")

func _tab_button(text: String, id: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(150, 54)
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	for st in [["normal", Color(0.16, 0.14, 0.12)], ["hover", Color(0.22, 0.19, 0.16)], ["pressed", Color(0.85, 0.6, 0.2)], ["hover_pressed", Color(0.92, 0.68, 0.25)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.set_corner_radius_all(6)
		b.add_theme_stylebox_override(st[0], sb)
	b.add_theme_color_override("font_pressed_color", Color(0.1, 0.06, 0.02))
	b.add_theme_color_override("font_hover_pressed_color", Color(0.1, 0.06, 0.02))
	b.pressed.connect(func(): _set_tab(id))
	return b

func _set_tab(id: String) -> void:
	tab = id
	log_btn.button_pressed = id == "log"
	health_btn.button_pressed = id == "health"
	log_scroll.visible = id == "log"
	health_text.visible = id == "health"
	if id == "health":
		_render_health()

func show_fighter(f, sim_ref) -> void:
	fighter = f
	sim = sim_ref
	_log_count = 0
	_log_first = 0
	_log_offset = 0
	_stick_bottom = true
	for c in log_box.get_children():
		c.queue_free()
	var u: Unit = f.unit
	name_label.text = u.name
	var fac: String = "Your company" if u.faction == "player" else str(DB.factions.get(u.faction, {}).get("name", u.faction))
	var role := "" if u.role == "troop" else "  (%s)" % u.role
	var lines := ["%s - %s%s" % [fac, u.title if u.title != "" else u.race, role]]
	var w: Item = u.weapon()
	lines.append("Weapon: %s   skill %s %d" % [w.display_name() if w else "bare hands", u.weapon_skill(), u.skill(u.weapon_skill())])
	if u.shield() != null:
		lines.append("Shield: " + u.shield().display_name())
	if u.bow() != null:   # bows
		var bs: String = f.bow_state if f.bow_state != "" else "slung"
		lines.append("Bow: %s (%s)   skill bow %d   quiver %d/%d" % [u.bow().display_name(), {"hand": "in hand", "slung": "slung",
			"dropped": "dropped", "broken": "broken"}.get(bs, bs), u.skill("bow"), u.arrows(), DB.QUIVER_MAX])
	var arm := []
	for s in DB.EQUIP_SLOTS:
		if s in ["main_hand", "off_hand", "ranged"] or not u.equip.has(s):
			continue
		arm.append((u.equip[s] as Item).display_name())
	lines.append("Armour: " + (", ".join(arm) if not arm.is_empty() else "none"))
	info_label.text = "\n".join(lines)
	visible = true
	refresh(true)
	if tab == "health":
		_render_health()

## Called by the battle screen after each sim tick (and every frame cheaply).
func refresh(unit_changed: bool) -> void:
	if fighter == null or not visible:
		return
	_update_state()
	_append_log()
	if tab == "health" and unit_changed:
		_render_health()

func _process(delta: float) -> void:
	if not visible or fighter == null:
		return
	_health_age += delta
	if tab == "health" and _health_age > 1.0:
		_render_health()

func _update_state() -> void:
	var f: Fighter = fighter
	var st: String = f.state
	var s: String = "State: " + STATE_WORDS.get(st, st)
	if st == "preparing" and f.current_attack != "":
		s = "State: preparing to %s" % f.current_attack
	if st in ["moving", "preparing", "recovering"]:
		s += "  (%d/%d ticks)" % [maxi(0, f.action_total - f.action_ticks), f.action_total]
	var flags := []
	if f.prone and st != "dead": flags.append("prone")
	if f.routed and st != "fled": flags.append("routing")
	if f.weapon_dropped: flags.append("weapon dropped")
	if f.blind: flags.append("blind")
	if not f.bleeding.is_empty() and st != "dead": flags.append("bleeding")
	if not flags.is_empty():
		s += "  - " + ", ".join(flags)
	if f.target >= 0 and sim != null and f.target < sim.fighters.size() and st not in ["dead", "fled"]:
		s += "\nEngaging: " + sim.fighters[f.target].unit.name
	var inhand: String = f.wielded.display_name() if f.wielded != null else "nothing (unarmed)"
	s += "\nIn hand: " + inhand
	s += "\nSpeed %d (lower is faster)   tempo x%.2f   morale %d" % [int(round(f.speed)), f.tempo, int(round(f.morale))]
	state_label.text = s

func _on_scrolled(_v: float) -> void:
	var bar := log_scroll.get_v_scroll_bar()
	_stick_bottom = bar.value >= bar.max_value - bar.page - 8.0

func _append_log() -> void:
	var entries: Array = fighter.log
	var omitted: int = int(sim.log_dropped.get(fighter.idx, 0)) if sim != null else 0
	if omitted != _log_offset:
		_log_offset = omitted; _log_count = 0; _log_first = 0
		for child in log_box.get_children():
			log_box.remove_child(child); child.queue_free()
	if entries.size() == _log_count:
		return
	var stick := _stick_bottom
	if _log_count == 0 and omitted > 0:
		var note := Label.new()
		note.text = "Latest battle entries (%d earlier entries omitted)." % omitted
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		log_box.add_child(note)
	if _log_count == 0 and entries.size() > LOG_WINDOW:
		# long logs: show the latest LOG_WINDOW entries, with a button to load the rest
		_log_first = entries.size() - LOG_WINDOW
		var more := Button.new()
		more.text = "Show %d earlier entries" % _log_first
		more.custom_minimum_size = Vector2(0, 52)
		more.focus_mode = Control.FOCUS_NONE
		more.pressed.connect(_show_earlier.bind(more))
		log_box.add_child(more)
		_log_count = _log_first
	for i in range(_log_count, entries.size()):
		log_box.add_child(_make_entry(entries[i]))
	_log_count = entries.size()
	if stick:
		_scroll_to_bottom.call_deferred()

func _show_earlier(btn: Button) -> void:
	var entries: Array = fighter.log
	var at := 0
	for i in _log_first:
		var row := _make_entry(entries[i])
		log_box.add_child(row)
		log_box.move_child(row, at)
		at += 1
	btn.queue_free()
	_log_first = 0

func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	var bar := log_scroll.get_v_scroll_bar()
	log_scroll.scroll_vertical = int(bar.max_value)
	_stick_bottom = true

## One log row. Tap cycles: story line -> + per-tissue detail lines -> + calc -> story line.
func _make_entry(entry: Dictionary) -> Control:
	var r: Dictionary = BattleSim.render_entry(entry)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 48)
	b.focus_mode = Control.FOCUS_NONE
	var detail: Array = r.get("detail", [])
	var calc_s := str(r.get("calc", ""))
	var more := "  +" if (not detail.is_empty() or calc_s != "") else ""
	b.text = "[%d] %s%s" % [int(r.get("tick", entry.get("tick", 0))), str(r.get("text", "")), more]
	b.add_theme_font_size_override("font_size", 16)
	var col := Color(0.93, 0.91, 0.85) if entry.get("k", "") != "move" else Color(0.62, 0.62, 0.58)
	b.add_theme_color_override("font_color", col)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(b)
	var det := Label.new()
	det.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	det.text = "\n".join(detail.map(func(x): return "  " + str(x))) if not detail.is_empty() else "  (no further detail)"
	det.add_theme_font_size_override("font_size", 15)
	det.add_theme_color_override("font_color", Color(1.0, 0.82, 0.55))
	det.visible = false
	box.add_child(det)
	var calc := Label.new()
	calc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	calc.text = calc_s if calc_s != "" else "(no calculation recorded)"
	calc.add_theme_font_size_override("font_size", 14)
	calc.add_theme_color_override("font_color", Color(0.6, 0.95, 0.65))
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color(0.03, 0.06, 0.04, 0.95)
	cb.set_content_margin_all(8)
	calc.add_theme_stylebox_override("normal", cb)
	calc.visible = false
	box.add_child(calc)
	box.set_meta("level", 0)
	b.pressed.connect(func():
		var lv: int = (int(box.get_meta("level")) + 1) % 3
		box.set_meta("level", lv)
		det.visible = lv >= 1
		calc.visible = lv >= 2)
	box.set_meta("button", b)
	return box

## Test/debug helper: tap log row i once; returns its expansion level (0 story, 1 detail, 2 calc).
func expand_entry(i: int) -> int:
	if i < 0 or i >= log_box.get_child_count():
		return -1
	var row := log_box.get_child(i)
	if not row.has_meta("button"):
		return -1
	(row.get_meta("button") as Button).pressed.emit()
	return int(row.get_meta("level"))

func entry_row_count() -> int:
	var n := 0
	for c in log_box.get_children():
		if c.has_meta("button") and not c.is_queued_for_deletion():
			n += 1
	return n

func show_tab(id: String) -> void:
	_set_tab(id)

func _render_health() -> void:
	_health_age = 0.0
	if fighter == null:
		return
	var r: Dictionary = HealthReport.describe(fighter.unit)
	var t := "[b]%s[/b]" % str(r.get("status", "?")).to_upper()
	var hd := float(r.get("heal_days", 0.0))
	if hd > 0.0:
		t += "   [color=#9fb8c8]heals in ~%d days[/color]" % int(ceil(hd))
	t += "\n"
	for s in r.get("summary", []):
		t += "[color=#e8c88a]%s[/color]\n" % str(s)
	var parts: Array = r.get("parts", [])
	if parts.is_empty():
		t += "\n[color=#8fd48f]No wounds.[/color]"
	else:
		t += "\n"
		for p in parts:
			var sev := clampi(int(p.get("severity", 0)), 0, 3)
			var nm := str(p.get("name", p.get("part", "?")))
			t += "[color=%s][b]%s[/b][/color]" % [SEV_COLORS[sev], nm]
			if p.get("permanent", false):
				t += " [color=#ff6a6a](permanent)[/color]"
			t += "\n"
			for line in p.get("lines", []):
				t += "    [color=%s]%s[/color]\n" % [SEV_COLORS[sev], str(line)]
	health_text.text = t
