extends Control
## New Campaign world size and history span: one day through 100 years, using
## the existing integer-day simulation. The slider gives short histories room:
## individual days to 30, then 60/90 days, then whole years. Begin opens the
## visible generation/history screen; Back returns to the title.

const SLIDER_MAX := 131
const PRESETS := [[1, "1 day"], [7, "1 week"], [30, "1 month"],
	[120, "1 year"], [600, "5 years"], [2400, "20 years"], [12000, "100 years"]]

var size_key := WorldGen.WORLD_SIZE
var history_days := CampaignWorld.PRESIM_DEFAULT_DAYS
var size_row: HFlowContainer
var size_info: Label
var slider: HSlider
var span_lbl: Label
var est: Label
var steppe_check: CheckButton
var house_cap_spin: SpinBox
var sick_slider: HSlider
var sick_lbl: Label

func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_preset(PRESET_FULL_RECT)
	size_key = WorldGen.gen_size if WorldGen.SIZES.has(WorldGen.gen_size) else WorldGen.WORLD_SIZE
	history_days = CampaignWorld.presim_span_days
	var bg := ColorRect.new()
	bg.color = UiTheme.WOOD
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var sc := UiKit.scroll()
	margin.add_child(sc)
	var p := UiKit.panel()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	var top := UiKit.hbox()
	var t := UiKit.label("New bloodline", "H2", true)
	t.add_theme_font_size_override("font_size", 28)
	top.add_child(t)
	top.add_child(UiKit.button("Back", _back, "Row", 72))
	v.add_child(top)
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label("Build a living world, then choose one of its cities and the family that rules it.", "Muted", true))
	# ------------------------------------------------------------------ world size
	v.add_child(UiKit.label("World size", "H2"))
	size_row = UiKit.flow(10)
	v.add_child(size_row)
	size_info = UiKit.label("", "Muted", true)
	v.add_child(size_info)
	# ------------------------------------------------------------------ history before arrival
	v.add_child(UiKit.label("History before you arrive", "H2"))
	v.add_child(UiKit.label("Families, trades, loans, wars, births and deaths unfold before you arrive.", "Muted", true))
	var yr := UiKit.hbox(10)
	v.add_child(yr)
	yr.add_child(UiKit.button("-", func(): _step_span(-1), "Row", 56))
	slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = SLIDER_MAX
	slider.step = 1
	slider.value = span_index(history_days)
	slider.tooltip_text = "1–30 days · 60 and 90 days · 1–100 years"
	slider.custom_minimum_size = Vector2(80, UiKit.TAP)
	slider.focus_mode = Control.FOCUS_NONE
	UiKit.expand(slider)
	slider.value_changed.connect(func(x: float): _set_days(span_days(int(x))))
	yr.add_child(slider)
	yr.add_child(UiKit.button("+", func(): _step_span(1), "Row", 56))
	span_lbl = UiKit.label("", "H2")
	span_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	span_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	v.add_child(span_lbl)
	var steps := HFlowContainer.new()
	steps.add_theme_constant_override("h_separation", 8)
	steps.add_theme_constant_override("v_separation", 8)
	v.add_child(steps)
	for preset in PRESETS:
		var n := int(preset[0])
		var b := UiKit.button(String(preset[1]), _set_days.bind(n), "Row", 0)
		b.tooltip_text = "%d simulation day%s; a year has %d days" % [n, "" if n == 1 else "s", CampaignWorld.PRESIM_YEAR_DAYS]
		steps.add_child(b)
	# ------------------------------------------------------------------ peoples
	v.add_child(UiKit.label("Peoples", "H2"))
	steppe_check = CheckButton.new()
	steppe_check.text = "Steppe peoples (the Dust-Wind Khanate)"
	steppe_check.tooltip_text = "Off: the south-east is settled by the Warrens instead; no steppe houses or towns."
	steppe_check.button_pressed = bool(Game.settings.get("steppe_enabled", false))
	steppe_check.custom_minimum_size = Vector2(80, UiKit.TAP)
	steppe_check.focus_mode = Control.FOCUS_NONE
	v.add_child(steppe_check)
	var cap_row := UiKit.hbox(10); v.add_child(cap_row)
	var cap_l := UiKit.label("Most noble houses alive at once (0 = the starting houses plus 60)", "", true)
	cap_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap_l.tooltip_text = "Each battle won raises the commoner with the greatest contribution to found a house. At this cap nobody new is raised until a house dies out."
	cap_l.mouse_filter = Control.MOUSE_FILTER_PASS
	cap_row.add_child(cap_l)
	house_cap_spin = SpinBox.new(); house_cap_spin.min_value = 0; house_cap_spin.max_value = 5000; house_cap_spin.step = 10
	house_cap_spin.value = int(Game.settings.get("house_cap", 0)); house_cap_spin.custom_minimum_size = Vector2(140, UiKit.TAP)
	cap_row.add_child(house_cap_spin)
	# ------------------------------------------------------------------ sickness (v0.034)
	v.add_child(UiKit.label("Sickness", "H2"))
	var sick_row := UiKit.hbox(10); v.add_child(sick_row)
	sick_lbl = UiKit.label("", "", false)
	sick_lbl.custom_minimum_size.x = 300
	sick_row.add_child(sick_lbl)
	sick_slider = HSlider.new()
	sick_slider.name = "SicknessDeadliness"
	sick_slider.min_value = 0; sick_slider.max_value = Sickness.DEADLINESS_STEPS.size() - 1; sick_slider.step = 1
	var chosen := Sickness.DEADLINESS_STEPS.find(float(Game.settings.get("sickness_deadliness", 1.0)))
	sick_slider.value = chosen if chosen >= 0 else Sickness.DEADLINESS_STEPS.find(1.0)
	sick_slider.tooltip_text = "How deadly sickness is: each sick person's daily risk of dying x this. How often people fall sick does not change."
	sick_slider.custom_minimum_size = Vector2(80, UiKit.TAP)
	sick_slider.focus_mode = Control.FOCUS_NONE
	UiKit.expand(sick_slider)
	sick_slider.value_changed.connect(func(_x: float): _sick_text())
	sick_row.add_child(sick_slider)
	_sick_text()
	# ------------------------------------------------------------------ the estimate and Begin
	v.add_child(HSeparator.new())
	est = UiKit.label("", "", true)
	v.add_child(est)
	var go := UiKit.button("Create world", _begin, "", 0)
	go.custom_minimum_size.y = 64
	v.add_child(go)
	_refresh()

static func span_days(index: int) -> int:
	index = clampi(index, 0, SLIDER_MAX)
	if index < 30:
		return index + 1
	if index <= 32:
		return (index - 28) * Calendar.DAYS_PER_SEASON
	return (index - 31) * CampaignWorld.PRESIM_YEAR_DAYS

static func span_index(days: int) -> int:
	days = clampi(days, CampaignWorld.PRESIM_DAYS_MIN, CampaignWorld.PRESIM_DAYS_MAX)
	if days <= 30:
		return days - 1
	if days < CampaignWorld.PRESIM_YEAR_DAYS:
		return clampi(roundi(float(days) / Calendar.DAYS_PER_SEASON) + 28, 29, 32)
	return clampi(roundi(float(days) / CampaignWorld.PRESIM_YEAR_DAYS) + 31, 32, SLIDER_MAX)

func _step_span(direction: int) -> void:
	_set_days(span_days(span_index(history_days) + direction))

func _set_days(n: int) -> void:
	history_days = clampi(n, CampaignWorld.PRESIM_DAYS_MIN, CampaignWorld.PRESIM_DAYS_MAX)
	if slider != null:
		slider.set_value_no_signal(span_index(history_days))
	_refresh()

func _set_years(n: int) -> void:
	_set_days(CampaignWorld.presim_days(n))

func _pick_size(k: String) -> void:
	size_key = k
	_refresh()

func _refresh() -> void:
	UiKit.clear(size_row)
	for k in WorldGen.SIZE_ORDER:
		var row: Dictionary = WorldGen.SIZES[k]
		var b := UiKit.button(String(row["label"]), _pick_size.bind(k), "RowOn" if k == size_key else "Row", 0)
		size_row.add_child(b)
	size_info.text = "%s: %s.%s" % [String(WorldGen.SIZES[size_key]["label"]), String(WorldGen.SIZES[size_key].get("towns", "")),
		"  (the default)" if size_key == WorldGen.WORLD_SIZE else ""]
	span_lbl.text = CampaignWorld.presim_span_text(history_days)
	est.text = "Startup will build a %s world and simulate %s. Larger worlds and longer histories take longer." % [
		String(WorldGen.SIZES[size_key]["label"]).to_lower(), CampaignWorld.presim_span_text(history_days)]

func deadliness() -> float:
	return float(Sickness.DEADLINESS_STEPS[clampi(int(sick_slider.value), 0, Sickness.DEADLINESS_STEPS.size() - 1)])

func _sick_text() -> void:
	var x := deadliness()
	sick_lbl.text = "Deadliness: %d%%%s" % [int(round(x * 100.0)), "  (as designed)" if x == 1.0 else ("  (sickness never kills)" if x == 0.0 else "")]

## The chosen options for the next new world (Create world applies them, then builds it).
func _apply() -> void:
	WorldGen.gen_size = size_key
	WorldGen.steppe_enabled = steppe_check.button_pressed
	Game.settings["steppe_enabled"] = steppe_check.button_pressed
	Game.settings["house_cap"] = int(house_cap_spin.value)
	Game.settings["sickness_deadliness"] = deadliness()
	Sickness.new_world_deadliness = deadliness()
	CampaignWorld.presim_span_days = history_days

func _begin() -> void:
	_apply()
	Game.goto("presim", {"new_world": true})   # visible generation, the years before, then the map

func _back() -> void:
	Game.goto(String(Game.screen_params.get("back", "title")))
