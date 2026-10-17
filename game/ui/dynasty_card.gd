class_name DynastyCard
extends Button
## A real registered ruler, rendered by the existing portrait painter.
var portrait: Portrait
var ruler_name: Label
var city_name: Label
var office_state: Label
var banner: HouseBanner
var compact := false   # inside screens that already show the house banner and name
var house_name: Label
var _visual_key := 0
var _record_key := ""
const REFRESH_INTERVAL := 0.25
var _refresh_dirty := false
var _refresh_cooldown := 0.0

func _enter_tree() -> void:
	if not Game.changed.is_connected(_on_game_changed):
		Game.changed.connect(_on_game_changed)
	set_process(false)

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game_changed):
		Game.changed.disconnect(_on_game_changed)
	_refresh_dirty = false
	set_process(false)

func _on_game_changed() -> void:
	# Moving emits this every frame; same-day orders still need a forced read.
	_refresh_dirty = true
	set_process(true)

func _process(delta: float) -> void:
	if not _refresh_dirty:
		set_process(false)
		return
	_refresh_cooldown = maxf(0.0, _refresh_cooldown - delta)
	if _refresh_cooldown <= 0.0:
		refresh(true)

func _ready() -> void:
	theme = UiTheme.get_theme()
	custom_minimum_size = Vector2(300, 136)
	for st in ["normal", "hover", "pressed"]:
		add_theme_stylebox_override(st, UiTheme.sb(UiTheme.WOOD_3.lightened(0.05 if st == "hover" else 0.0), UiTheme.BRASS, 2, 10))
	var inset := MarginContainer.new()
	inset.set_anchors_preset(PRESET_FULL_RECT)
	inset.mouse_filter = MOUSE_FILTER_IGNORE
	for edge in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + edge, 8)
	add_child(inset)
	var row := UiKit.hbox(8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	inset.add_child(row)
	portrait = Portrait.new()
	portrait.custom_minimum_size = Vector2(112, 112)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	banner = HouseBanner.new()
	banner.custom_minimum_size = Vector2(46, 56)
	banner.size_flags_vertical = SIZE_SHRINK_BEGIN
	var words := UiKit.vbox(2)
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(words)
	office_state = _word("YOUR RULER", "Small")
	office_state.add_theme_color_override("font_color", UiTheme.BRASS)
	var head := UiKit.hbox(6); head.mouse_filter = MOUSE_FILTER_IGNORE; words.add_child(head)
	head.add_child(banner)
	var top := UiKit.vbox(0); top.mouse_filter = MOUSE_FILTER_IGNORE; head.add_child(top)
	top.add_child(office_state)
	house_name = _word("", "")
	house_name.add_theme_font_override("font", UiTheme.bold())
	house_name.add_theme_font_size_override("font_size", 18)
	top.add_child(house_name)
	ruler_name = _word("", "", true)
	ruler_name.add_theme_font_size_override("font_size", 19)
	ruler_name.max_lines_visible = 2
	ruler_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(ruler_name)
	city_name = _word("", "Muted", true)
	city_name.max_lines_visible = 1
	city_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(city_name)
	refresh()

func _word(value: String, style: String, wrap: bool = false) -> Label:
	var label := UiKit.label(value, style, wrap)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	return label

func refresh(force: bool = false) -> void:
	if portrait == null:
		return
	var state: Dictionary = Game.world.get("player_house", {})
	var tid := String(state.get("town_id", ""))
	var faction := String(Game.world.get("towns", {}).get(tid, {}).get("faction", ""))
	var seat_uid := String(Game.world.get("towns", {}).get(tid, {}).get("econ", {}).get("head", {}).get("person_uid", ""))
	var record_key := "%s|%s|%s|%s|%d" % [tid, state.get("ruler_uid", ""), seat_uid, faction, int(floor(Game.day))]
	if not force and record_key == _record_key:
		return
	var started := Time.get_ticks_usec()
	_refresh_dirty = false
	_refresh_cooldown = REFRESH_INTERVAL
	set_process(false)
	_record_key = record_key
	var person: Dictionary = Dynasty.ruler(Game)
	var house: Dictionary = Dynasty.selected(Game)
	office_state.text = "YOUR RULER" if bool(person.get("alive", false)) else "LAST RULER"
	if bool(person.get("alive", false)):
		var office: Dictionary = Dynasty.town_office(Game, tid)
		if String(office.get("person_uid", "")) != String(person.get("person_uid", "")):
			office_state.text = "HOUSE LEADER"
		elif bool(office.get("regency", false)):
			office_state.text = "MINOR RULER"
	ruler_name.text = String(person.get("name", "No ruler selected"))
	house_name.text = "House " + String(house.get("house_name", ""))
	banner.visible = not compact; house_name.visible = not compact
	banner.set_customization(Game.world.get("player_house", {}).get("customization", HouseBanner.DEFAULT_STYLE))
	city_name.text = String(house.get("town_name", "Choose a city"))
	var spec: Dictionary = Dynasty.portrait_spec(Game)
	var visual_key := spec.hash()
	if visual_key != _visual_key:
		_visual_key = visual_key
		portrait.set_spec(spec)
	tooltip_text = "View your ruler, family and accounts"
	Perf.record_us("Ruler information", Time.get_ticks_usec() - started)
