class_name HouseSelectView
extends Control
## Pure staged previews. Begin is the only command boundary.
const PAGE_SIZE := 8
const STAGES := ["Choose a settlement","Choose a local house","Customize House","Design your ruler","Review your beginning"]
const STAGE_CUSTOM := 2
const STAGE_DESIGN := 3
const STAGE_REVIEW := 4
var stage: int = 0
var settlement_rows: Array = []
var house_rows: Array = []
var selected_town: String = ""
var selected_house: String = ""
var custom: Dictionary = {}
var current_preview: Dictionary = {}
var review: Dictionary = {}
var page_index: int = 0
var filtered_rows: Array = []
var notice: String = ""
var map_view: SettlementSelectMap
var banner: HouseBanner
var portrait: Portrait
var workspace: GridContainer
var stage_label: Label
var map_name: Label
var person_label: Label
var role_label: Label
var purse_label: Label
var rights_label: Label
var status: Label
var search: LineEdit
var list: VBoxContainer
var editor: VBoxContainer
var paging: HBoxContainer
var page_label: Label
var previous_button: Button
var following_button: Button
var next_button: Button
var back_button: Button
var name_input: LineEdit
var emblem_input: OptionButton
var primary_input: OptionButton
var secondary_input: OptionButton
var design_name: LineEdit
var design_focus: OptionButton
var design_focus_note: Label
var design_portrait: Portrait
var design_picks: Dictionary = {}
var _design_leader: String = ""
var _design_ready: bool = false
var _portrait_key: int = 0
var _content: VBoxContainer
var _map_card: VBoxContainer
var _side_card: VBoxContainer
var _last_columns: int = 0

func _ready() -> void:
	var frame: Dictionary = UiKit.screen_frame(self,"Begin your bloodline")
	_content = frame["root"]
	stage_label = UiKit.label("","H2",true); stage_label.name = "OnboardingStage"; _content.add_child(stage_label)
	workspace = GridContainer.new(); workspace.name = "OnboardingWorkspace"; workspace.columns = 2
	workspace.add_theme_constant_override("h_separation",12); workspace.add_theme_constant_override("v_separation",8)
	UiKit.expand(workspace,true,true); _content.add_child(workspace)
	_map_card = _card(workspace)
	map_name = UiKit.label("World map","",true); map_name.name = "SelectedSettlement"; _map_card.add_child(map_name)
	map_view = SettlementSelectMap.new(); map_view.name = "SettlementMap"; map_view.custom_minimum_size = Vector2(240,220)
	UiKit.expand(map_view,true,true); _map_card.add_child(map_view)
	map_view.settlement_chosen.connect(select_settlement)
	var identity := UiKit.hbox(10); identity.name = "HouseIdentity"; _map_card.add_child(identity)
	portrait = Portrait.new(); portrait.name = "SelectedPersonPortrait"; portrait.custom_minimum_size = Vector2(84,96); identity.add_child(portrait)
	banner = HouseBanner.new(); banner.name = "HouseBannerPreview"; banner.custom_minimum_size = Vector2(72,96); identity.add_child(banner)
	var words := UiKit.vbox(2); UiKit.expand(words); identity.add_child(words)
	person_label = UiKit.label("","",true); person_label.name = "SelectedPerson"; words.add_child(person_label)
	role_label = UiKit.label("","Small",true); role_label.name = "SelectedHouseRole"; words.add_child(role_label)
	purse_label = UiKit.label("","Small",true); purse_label.name = "SelectedHousePurse"; words.add_child(purse_label)
	_side_card = _card(workspace)
	search = LineEdit.new(); search.name = "OnboardingSearch"; search.custom_minimum_size.y = UiKit.touch_min(48)
	search.text_changed.connect(func(_text): page_index = 0; _refresh_list())
	# List pages sit beside the search box, away from the step's Continue button.
	var top_row := UiKit.hbox(8); _side_card.add_child(top_row)
	UiKit.expand(search); top_row.add_child(search)
	paging = UiKit.hbox(4); paging.name = "OnboardingPaging"; top_row.add_child(paging)
	previous_button = UiKit.button("‹",func(): turn_page(-1),"Row",52); previous_button.tooltip_text = "Previous page"; paging.add_child(previous_button)
	page_label = UiKit.label("","Small"); page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; page_label.custom_minimum_size.x = 96; paging.add_child(page_label)
	following_button = UiKit.button("›",func(): turn_page(1),"Row",52); following_button.tooltip_text = "Next page"; paging.add_child(following_button)
	var scroll := UiKit.scroll(); scroll.name = "OnboardingListScroll"; _side_card.add_child(scroll)
	list = UiKit.vbox(4); list.name = "OnboardingRows"; UiKit.expand(list); scroll.add_child(list)
	editor = UiKit.vbox(8); editor.name = "OnboardingEditor"; UiKit.expand(editor); list.add_child(editor)
	rights_label = UiKit.label("","Small",true); rights_label.name = "OnboardingRights"; _side_card.add_child(rights_label)
	var footer := UiKit.hbox(10); footer.name = "OnboardingFooter"; _content.add_child(footer)
	back_button = UiKit.button("Back",previous_stage,"Row",80); back_button.name = "OnboardingBack"; footer.add_child(back_button)
	status = UiKit.label("","Small",true); status.name = "OnboardingStatus"; UiKit.expand(status); footer.add_child(status)
	next_button = UiKit.button("Continue",next_stage,"",180); next_button.name = "OnboardingNext"; footer.add_child(next_button)
	settlement_rows = HouseOnboarding.settlements(Game)
	map_view.setup(Game.world,settlement_rows)
	resized.connect(_fit_layout); _content.resized.connect(_fit_layout)
	Perf.set_stage("Choose a house")
	_refresh()

func _card(parent: Control) -> VBoxContainer:
	var panel := UiKit.panel("Card"); UiKit.expand(panel,true,true); parent.add_child(panel)
	var box := UiKit.vbox(8); UiKit.expand(box,true,true); panel.add_child(box)
	return box

func _fit_layout() -> void:
	if workspace == null: return
	var columns: int = 2 if _content.size.x >= 860 else 1
	if columns != _last_columns:
		workspace.columns = columns; _last_columns = columns
		(_side_card.get_parent() as Control).custom_minimum_size.x = 360 if columns == 2 else 0
		(_map_card.get_parent() as Control).custom_minimum_size.x = 440 if columns == 2 else 0
	map_view.queue_redraw()

func select_settlement(town_id: String) -> void:
	if not settlement_rows.any(func(row): return String(row["town_id"]) == town_id): return
	selected_town = town_id; selected_house = ""; custom = {}; review = {}; current_preview = {}; notice = ""; _design_leader = ""
	house_rows = HouseOnboarding.houses(Game,town_id)
	if stage > 0: stage = 1
	page_index = 0; search.text = ""
	map_view.select_town(town_id)
	_refresh()

func select_house(household_uid: String) -> void:
	# The list cached at a rejected Begin can still name the stand-in leader.
	if selected_town != "": house_rows = HouseOnboarding.houses(Game,selected_town)
	var row: Dictionary = {}
	for candidate: Dictionary in house_rows:
		if String(candidate["household_uid"]) == household_uid: row = candidate; break
	if row.is_empty(): return
	selected_house = household_uid; custom = {}; review = {}; notice = ""; _design_leader = ""
	current_preview = HouseOnboarding.preview(Game,selected_town,selected_house,custom)
	if bool(current_preview.get("ok",false)): custom = current_preview["customization"].duplicate(true)
	_refresh()

func _refresh() -> void:
	stage_label.text = "%d / %d   %s" % [stage+1,STAGES.size(),STAGES[stage]]
	map_name.text = "World map"
	for row: Dictionary in settlement_rows:
		if String(row["town_id"]) == selected_town: map_name.text = String(row["town_name"])+" · "+String(row["faction_name"])
	search.visible = stage <= 1; paging.visible = stage <= 1
	rights_label.visible = stage != STAGE_REVIEW # The review contains this statement once.
	search.placeholder_text = "Search settlements or realms" if stage == 0 else "Search local houses or people"
	next_button.text = "Begin" if stage == STAGE_REVIEW else ("Review" if stage == STAGE_DESIGN else "Continue")
	next_button.name = "OnboardingBegin" if stage == STAGE_REVIEW else "OnboardingNext"
	if stage == 0: next_button.disabled = selected_town == ""
	elif stage == STAGE_REVIEW: next_button.disabled = not bool(review.get("ok",false))
	elif stage == STAGE_DESIGN: next_button.disabled = true
	else: next_button.disabled = selected_house == "" or not bool(current_preview.get("ok",false))
	status.text = notice if notice != "" else (["Pick a settlement on the map or in the list.","Pick the household you will lead.","Name your house and design its banner.","Name your ruler and choose their look and focus.","Check your choice, then begin."][stage])
	portrait.visible = selected_house != ""; banner.visible = selected_house != ""
	if selected_house != "":
		var row: Dictionary = current_preview.get("house",{})
		person_label.text = String(row.get("leader_name","Unavailable person"))
		role_label.text = "%s · %s" % [String(custom.get("display_name",row.get("house_name",""))),String(row.get("title","House leader"))]
		purse_label.text = "House purse: %s coins" % RecKit.num(float(row.get("house_purse",0)))
		rights_label.text = String(current_preview.get("rights_text",current_preview.get("reason","")))
		if stage >= STAGE_DESIGN:
			_paint_ruler(_design_look())
		else:
			var spec: Dictionary = current_preview.get("portrait_spec",{})
			var key: int = hash(spec)
			if key != _portrait_key: _portrait_key = key; portrait.set_spec(spec)
		banner.set_style(custom)
	else:
		person_label.text = ""; role_label.text = ""; purse_label.text = ""
		rights_label.text = ""
	_refresh_list()
	_fit_layout()

func _refresh_list() -> void:
	_design_ready = false
	if editor.get_parent() == list: list.remove_child(editor)
	UiKit.clear(list); list.add_child(editor); UiKit.clear(editor)
	name_input = null; emblem_input = null; primary_input = null; secondary_input = null
	design_name = null; design_focus = null; design_focus_note = null; design_portrait = null; design_picks = {}
	editor.visible = stage >= STAGE_CUSTOM
	if stage >= STAGE_CUSTOM:
		if stage == STAGE_CUSTOM: _build_customization()
		elif stage == STAGE_DESIGN: _build_design()
		else: _build_review()
		return
	var query: String = search.text.strip_edges().to_lower()
	filtered_rows = (settlement_rows if stage == 0 else house_rows).filter(func(row):
		var text: String = String(row.get("town_name",""))+" "+String(row.get("faction_name","")) if stage == 0 else String(row.get("house_name",""))+" "+String(row.get("leader_name",""))
		return query == "" or text.to_lower().contains(query))
	var pages: int = maxi(1,int(ceil(float(filtered_rows.size())/PAGE_SIZE)))
	page_index = clampi(page_index,0,pages-1)
	for row: Dictionary in filtered_rows.slice(page_index*PAGE_SIZE,(page_index+1)*PAGE_SIZE):
		var uid: String = String(row["town_id"] if stage == 0 else row["household_uid"])
		var chosen: bool = uid == (selected_town if stage == 0 else selected_house)
		var heading: String = String(row["town_name"] if stage == 0 else row["house_name"])
		var detail: String = "%s · %d people · %d houses" % [row["faction_name"],row["population"],row["house_count"]] if stage == 0 else "%s · %s · %s coins" % [row["leader_name"],row["title"],RecKit.num(float(row["house_purse"]))]
		var button: Button = RecKit.row(heading,"",detail,select_settlement.bind(uid) if stage == 0 else select_house.bind(uid))
		button.name = "SettlementRow" if stage == 0 else "LocalHouseRow"; button.set_meta("onboarding_uid",uid)
		if chosen: button.theme_type_variation = "RowOn"
		list.add_child(button)
	if filtered_rows.is_empty(): list.add_child(UiKit.label("No matching settlements." if stage == 0 else "No matching available local houses.","Muted",true))
	page_label.text = "%d–%d of %d" % [mini(page_index*PAGE_SIZE+1,filtered_rows.size()),mini((page_index+1)*PAGE_SIZE,filtered_rows.size()),filtered_rows.size()]
	previous_button.disabled = page_index == 0; following_button.disabled = page_index >= pages-1

func turn_page(direction: int) -> void:
	page_index += direction; _refresh_list()

func _build_customization() -> void:
	editor.add_child(UiKit.label("Customize House","H2",true))
	editor.add_child(UiKit.label("Keep your household, people, property and role. Choose how your house is displayed.","Small",true))
	editor.add_child(UiKit.label("House name","Small"))
	name_input = LineEdit.new(); name_input.name = "HouseDisplayName"; name_input.max_length = 40; name_input.custom_minimum_size.y = UiKit.touch_min(48)
	name_input.text = String(custom.get("display_name","")); editor.add_child(name_input)
	name_input.text_changed.connect(func(value): update_customization({"display_name":value}))
	emblem_input = _picker("Emblem",HouseOnboarding.EMBLEMS.map(func(value): return String(value).capitalize()))
	emblem_input.name = "HouseEmblem"
	var emblem_index: int = HouseOnboarding.EMBLEMS.find(String(custom.get("emblem","star")))
	emblem_input.select(maxi(0,emblem_index)); emblem_input.item_selected.connect(func(index): update_customization({"emblem":HouseOnboarding.EMBLEMS[index]}))
	primary_input = _palette_picker("Banner field","primary_color"); primary_input.name = "HousePrimaryColor"
	secondary_input = _palette_picker("Emblem colour","secondary_color"); secondary_input.name = "HouseSecondaryColor"

func _picker(title: String, choices: Array) -> OptionButton:
	editor.add_child(UiKit.label(title,"Small"))
	var button := OptionButton.new(); button.custom_minimum_size.y = UiKit.touch_min(48); button.size_flags_horizontal = SIZE_EXPAND_FILL
	for choice in choices: button.add_item(String(choice))
	editor.add_child(button)
	return button

func _palette_picker(title: String, key: String) -> OptionButton:
	var button: OptionButton = _picker(title,HouseOnboarding.PALETTE.map(func(value): return String(value["name"])))
	for i in HouseOnboarding.PALETTE.size():
		if String(HouseOnboarding.PALETTE[i]["color"]).to_lower() == String(custom.get(key,"")).to_lower(): button.select(i)
	button.item_selected.connect(func(index):
		var change: Dictionary = {}; change[key] = HouseOnboarding.PALETTE[index]["color"]
		update_customization(change))
	return button

func update_customization(changes: Dictionary) -> void:
	# Customize widgets are freed when the design step opens. Ignore a late signal so it cannot disable Review.
	if stage != STAGE_CUSTOM: return
	custom.merge(changes,true); review = {}
	current_preview = HouseOnboarding.preview(Game,selected_town,selected_house,custom)
	next_button.disabled = not bool(current_preview.get("ok",false))
	status.text = String(current_preview.get("reason","")) if next_button.disabled else "House name and banner only."
	banner.set_style(custom)
	role_label.text = "%s · %s" % [String(custom.get("display_name","")),String(current_preview.get("house",{}).get("title","House leader"))]
	if bool(current_preview.get("ok",false)):
		var spec: Dictionary = current_preview.get("portrait_spec",{})
		var key: int = hash(spec)
		if key != _portrait_key: _portrait_key = key; portrait.set_spec(spec)
	# Do not rebuild controls while typing: retain real caret/focus.

func _leader_uid() -> String:
	# Same leader HouseOnboarding.preview will accept. house_rows is only a fallback if that house is gone.
	if selected_town != "" and selected_house != "":
		for candidate in HouseOnboarding.houses(Game,selected_town):
			if String(candidate.get("household_uid","")) == selected_house: return String(candidate.get("leader_uid",""))
	for row: Dictionary in house_rows:
		if String(row.get("household_uid","")) == selected_house: return String(row.get("leader_uid",""))
	return String(current_preview.get("house",{}).get("leader_uid",review.get("leader_uid","")))

func _default_design(opts: Dictionary) -> Dictionary:
	var look: Dictionary = {}
	var uid: String = String(opts.get("person_uid",_leader_uid()))
	var person: Dictionary = Dynasty.person(Game,uid)
	var spec: Dictionary = Dynasty.portrait_for(Game,person,custom)
	var choices: Dictionary = opts.get("choices",{})
	for key in choices:
		var k: String = String(key)
		var items: Array = choices[key]
		if items.is_empty(): continue
		var picked: Variant = (items[0] as Dictionary)["value"]
		if not spec.is_empty():
			if k in ["skin","hair"] and spec.has(k):
				var raw_col: Variant = spec[k]
				var target_col: Color = raw_col if raw_col is Color else Color(String(raw_col))
				var best_dist: float = INF
				for item in items:
					var entry: Dictionary = item
					var c: Color = Color(String(entry["value"]))
					var d: float = (c.r-target_col.r)*(c.r-target_col.r)+(c.g-target_col.g)*(c.g-target_col.g)+(c.b-target_col.b)*(c.b-target_col.b)
					if d < best_dist:
						best_dist = d
						picked = entry["value"]
			elif k == "beard":
				var want_beard: bool = bool(spec.get("beard",false))
				for item in items:
					var entry: Dictionary = item
					if bool(entry["value"]) == want_beard:
						picked = entry["value"]
						break
			elif k in ["seed","female_set","beard_style"]:
				var want_int: int = 0
				if k == "seed":
					want_int = posmod(int(spec.get("seed",0)),items.size())
				elif k == "female_set":
					want_int = int(spec.get("female_set",FigurePainter.female_variant(spec)))
				else:
					want_int = int(spec.get("beard_style",FigurePainter.beard_style(spec)))
				var best_diff: int = 0x7fffffff
				for item in items:
					var entry: Dictionary = item
					var diff: int = absi(int(entry["value"])-want_int)
					if diff < best_diff:
						best_diff = diff
						picked = entry["value"]
		look[k] = picked
	var focus := ""
	var focuses: Array = opts.get("focuses",[])
	if not focuses.is_empty(): focus = String((focuses[0] as Dictionary).get("value",""))
	return {"first_name":String(opts.get("first_name","")),"look":look,"focus":focus}

func _focus_effect(focus: String) -> String:
	var skill := String(CharacterDesign.FOCUS_SKILLS.get(focus,""))
	if focus == "" or skill == "": return "No focus: this ruler gains no starting skill bonus."
	return "%s: one-time +%d %s on this ruler." % [focus.capitalize(),CharacterDesign.FOCUS_BONUS,skill.replace("_"," ")]

func _design_look() -> Dictionary:
	if not custom.get("design") is Dictionary: return {}
	var pre := CharacterDesign.preview(Game,_leader_uid(),custom["design"])
	if not bool(pre.get("ok",false)): return {}
	return pre.get("look",{})

func _ruler_spec(look: Dictionary) -> Dictionary:
	var person := Dynasty.person(Game,_leader_uid())
	var spec := Dynasty.portrait_for(Game,person,custom)
	CharacterDesign.merge_into_spec(spec,look)
	return spec

func _paint_ruler(look: Dictionary) -> void:
	var spec := _ruler_spec(look)
	_portrait_key = hash(spec)
	if portrait != null: portrait.set_spec(spec)
	if design_portrait != null: design_portrait.set_spec(spec)
	var pre := CharacterDesign.preview(Game,_leader_uid(),custom["design"]) if custom.get("design") is Dictionary else {}
	if bool(pre.get("ok",false)) and person_label != null and stage >= STAGE_DESIGN:
		person_label.text = String(pre.get("name",person_label.text))

func _select_design_value(button: OptionButton, key: String, want: Variant) -> void:
	var values: Array = button.get_meta("design_values") if button.has_meta("design_values") else []
	if values.is_empty(): return
	var idx := 0
	for i in values.size():
		var value: Variant = values[i]
		var matched := false
		if want == null: matched = i == 0
		elif key == "beard": matched = bool(value) == bool(want)
		elif key in ["skin","hair","focus"]: matched = str(value).to_lower() == str(want).to_lower()
		else: matched = int(value) == int(want)
		if matched: idx = i; break
	button.select(idx)

func _design_from_controls() -> Dictionary:
	var look: Dictionary = {}
	for key in design_picks:
		var button: OptionButton = design_picks[key]
		var values: Array = button.get_meta("design_values") if button.has_meta("design_values") else []
		if button.selected >= 0 and button.selected < values.size(): look[String(key)] = values[button.selected]
	var focus := ""
	if design_focus != null:
		var focuses: Array = design_focus.get_meta("design_values") if design_focus.has_meta("design_values") else []
		if design_focus.selected >= 0 and design_focus.selected < focuses.size(): focus = String(focuses[design_focus.selected])
	return {"first_name":design_name.text if design_name != null else "","look":look,"focus":focus}

func _apply_design_state() -> void:
	if not _design_ready or stage != STAGE_DESIGN or design_name == null: return
	var design := _design_from_controls()
	custom["design"] = design
	review = {}
	var pre := CharacterDesign.preview(Game,_leader_uid(),design)
	var payload := custom.duplicate(true)
	current_preview = HouseOnboarding.preview(Game,selected_town,selected_house,payload)
	var design_ok := bool(pre.get("ok",false))
	var house_ok := bool(current_preview.get("ok",false))
	next_button.disabled = not (design_ok and house_ok)
	if not design_ok: status.text = String(pre.get("reason","Invalid character design."))
	elif not house_ok: status.text = String(current_preview.get("reason","Unavailable house"))
	else: status.text = "Name, look and focus only."
	if design_focus_note != null: design_focus_note.text = _focus_effect(String(design.get("focus","")))
	if design_ok: _paint_ruler(pre.get("look",{}))
	if house_ok:
		var row: Dictionary = current_preview.get("house",{})
		role_label.text = "%s · %s" % [String(custom.get("display_name","")),String(row.get("title","House leader"))]
		banner.set_style(custom)

func _build_design() -> void:
	var leader := _leader_uid()
	var opts := CharacterDesign.options(Game,leader)
	editor.add_child(UiKit.label("Design your ruler","H2",true))
	editor.add_child(UiKit.label("The household, property and role stay. Choose this ruler's name, appearance and focus.","Small",true))
	if opts.is_empty():
		next_button.disabled = true
		status.text = "This person is not a living registered character."
		return
	# A design left by another ruler, or one that this ruler cannot wear, is replaced before the widgets exist.
	var design_ok := leader != "" and leader == _design_leader and custom.get("design") is Dictionary and bool(CharacterDesign.preview(Game,leader,custom["design"]).get("ok",false))
	if not design_ok:
		custom["design"] = _default_design(opts)
		_design_leader = leader
	design_portrait = Portrait.new(); design_portrait.name = "DesignPortrait"; design_portrait.custom_minimum_size = Vector2(96,112)
	editor.add_child(design_portrait)
	editor.add_child(UiKit.label("First name","Small"))
	design_name = LineEdit.new(); design_name.name = "DesignFirstName"; design_name.max_length = 20; design_name.custom_minimum_size.y = UiKit.touch_min(48)
	design_name.text = String((custom["design"] as Dictionary).get("first_name",""))
	editor.add_child(design_name)
	design_name.text_changed.connect(func(_value): _apply_design_state())
	var look: Dictionary = (custom["design"] as Dictionary).get("look",{}) if (custom["design"] as Dictionary).get("look") is Dictionary else {}
	var choices: Dictionary = opts.get("choices",{})
	for key in choices:
		var button := _design_picker(String(key),choices[key])
		_select_design_value(button,String(key),look.get(key,null))
		button.item_selected.connect(func(_index): _apply_design_state())
	editor.add_child(UiKit.label("Focus","Small"))
	design_focus = OptionButton.new(); design_focus.name = "DesignFocus"; design_focus.custom_minimum_size.y = UiKit.touch_min(48)
	design_focus.size_flags_horizontal = SIZE_EXPAND_FILL
	var focus_values: Array = []
	for item in opts.get("focuses",[]):
		var entry: Dictionary = item
		design_focus.add_item(String(entry.get("label",entry.get("value",""))))
		focus_values.append(entry.get("value"))
	design_focus.set_meta("design_values",focus_values)
	editor.add_child(design_focus)
	_select_design_value(design_focus,"focus",(custom["design"] as Dictionary).get("focus",""))
	design_focus.item_selected.connect(func(_index): _apply_design_state())
	design_focus_note = UiKit.label("","Small",true); design_focus_note.name = "DesignFocusEffect"; editor.add_child(design_focus_note)
	_design_ready = true
	_apply_design_state()

func _design_picker(key: String, items: Array) -> OptionButton:
	editor.add_child(UiKit.label(key.capitalize(),"Small"))
	var button := OptionButton.new(); button.name = "DesignPick_"+key; button.custom_minimum_size.y = UiKit.touch_min(48)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	var values: Array = []
	for item in items:
		var entry: Dictionary = item
		button.add_item(String(entry.get("label",entry.get("value",""))))
		values.append(entry.get("value"))
	button.set_meta("design_values",values)
	editor.add_child(button)
	design_picks[key] = button
	return button

func _build_review() -> void:
	editor.add_child(UiKit.label(String(review.get("customization",{}).get("display_name","Your house")),"H2",true))
	var row: Dictionary = review.get("house",{})
	var designed_name := String(row.get("leader_name",""))
	var focus_line := "Focus: none"
	var design: Dictionary = custom["design"] if custom.get("design") is Dictionary else {}
	if not design.is_empty():
		var pre := CharacterDesign.preview(Game,String(review.get("leader_uid",row.get("leader_uid",""))),design)
		if bool(pre.get("ok",false)):
			designed_name = String(pre.get("name",designed_name))
			var focus := String(pre.get("focus",""))
			focus_line = "Focus: none" if focus == "" else "Focus: %s" % _focus_effect(focus)
	for line: String in ["Settlement: "+String(row.get("town_name","")),"Person: "+String(row.get("leader_name","")),"Ruler: "+designed_name,focus_line,"Role: "+String(row.get("title","House leader")),
		"House purse: %s coins" % RecKit.num(float(row.get("house_purse",0))),"Household: %d existing members" % int(row.get("member_count",0))]:
		editor.add_child(UiKit.label(line,"",true))
	editor.add_child(UiKit.label(String(review.get("rights_text","")),"Small",true))
	editor.add_child(UiKit.label("Field army starts unraised. Raising people and funding the army are separate orders." if review.get("holds_office",false) else "Field army starts unraised. The local lord commands settlement levies.","Small",true))
	editor.add_child(UiKit.label("Your house name and banner change presentation. The household's people, property and funds stay with their actual owners.","Muted",true))

func next_stage() -> void:
	if next_button.disabled: return
	if stage == STAGE_REVIEW: begin_review(); return
	if stage == STAGE_DESIGN:
		if not custom.get("design") is Dictionary:
			notice = "Choose the ruler's name, look and focus."; _refresh(); return
		var pre := CharacterDesign.preview(Game,_leader_uid(),custom["design"])
		if not bool(pre.get("ok",false)): notice = String(pre.get("reason","Invalid character design.")); _refresh(); return
		custom["design"] = {"first_name":String(pre.get("first_name","")),"look":(pre.get("look",{}) as Dictionary).duplicate(true),"focus":String(pre.get("focus",""))}
		var payload := custom.duplicate(true)
		review = HouseOnboarding.preview(Game,selected_town,selected_house,payload)
		if not bool(review.get("ok",false)): notice = String(review.get("reason","Unavailable house")); _refresh(); return
		var design: Dictionary = (custom["design"] as Dictionary).duplicate(true)
		custom = review["customization"].duplicate(true); custom["design"] = design; current_preview = review.duplicate(true)
	stage += 1; page_index = 0; search.text = ""; notice = ""; _refresh()

func previous_stage() -> void:
	if stage == 0: Game.goto("title"); return
	stage -= 1; review = {}; page_index = 0; search.text = ""; notice = ""; _refresh()

func begin_review() -> Dictionary:
	if stage != STAGE_REVIEW or not bool(review.get("ok",false)): return {"ok":false,"reason":"Review a house before beginning."}
	var person_uid: String = String(review.get("house",{}).get("leader_uid",""))
	var payload: Dictionary = (review.get("customization",{}) as Dictionary).duplicate(true)
	if custom.get("design") is Dictionary: payload["design"] = (custom["design"] as Dictionary).duplicate(true)
	var result: Dictionary = HouseOnboarding.begin(Game,selected_town,selected_house,payload,person_uid)
	if not bool(result.get("ok",false)):
		notice = String(result.get("reason","That choice changed. Review a house again.")); review = {}; stage = 1
		custom.erase("design"); _design_leader = ""
		house_rows = HouseOnboarding.houses(Game,selected_town); current_preview = HouseOnboarding.preview(Game,selected_town,selected_house,custom); _refresh()
		return result
	Game.save_game_async()
	Game.goto("house",{"back":"map","start":true})
	return result
