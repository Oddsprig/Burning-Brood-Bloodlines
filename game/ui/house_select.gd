class_name HouseSelectView
extends Control
## Pure staged previews. Begin is the only command boundary.
const PAGE_SIZE := 8
const STAGES := ["Choose a settlement","Choose a local house","Customize House","Review your beginning"]
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
	search = LineEdit.new(); search.name = "OnboardingSearch"; search.custom_minimum_size.y = 48
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
	selected_town = town_id; selected_house = ""; custom = {}; review = {}; current_preview = {}; notice = ""
	house_rows = HouseOnboarding.houses(Game,town_id)
	if stage > 0: stage = 1
	page_index = 0; search.text = ""
	map_view.select_town(town_id)
	_refresh()

func select_house(household_uid: String) -> void:
	var row: Dictionary = {}
	for candidate: Dictionary in house_rows:
		if String(candidate["household_uid"]) == household_uid: row = candidate; break
	if row.is_empty(): return
	selected_house = household_uid; custom = {}; review = {}; notice = ""
	current_preview = HouseOnboarding.preview(Game,selected_town,selected_house,custom)
	if bool(current_preview.get("ok",false)): custom = current_preview["customization"].duplicate(true)
	_refresh()

func _refresh() -> void:
	stage_label.text = "%d / 4   %s" % [stage+1,STAGES[stage]]
	map_name.text = "World map"
	for row: Dictionary in settlement_rows:
		if String(row["town_id"]) == selected_town: map_name.text = String(row["town_name"])+" · "+String(row["faction_name"])
	search.visible = stage <= 1; paging.visible = stage <= 1
	rights_label.visible = stage != 3 # The review contains this statement once.
	search.placeholder_text = "Search settlements or realms" if stage == 0 else "Search local houses or people"
	next_button.text = "Begin" if stage == 3 else ("Review" if stage == 2 else "Continue")
	next_button.name = "OnboardingBegin" if stage == 3 else "OnboardingNext"
	next_button.disabled = selected_town == "" if stage == 0 else (selected_house == "" or not bool(current_preview.get("ok",false)))
	if stage == 3: next_button.disabled = not bool(review.get("ok",false))
	status.text = notice if notice != "" else (["Pick a settlement on the map or in the list.","Pick the household you will lead.","Name your house and design its banner.","Check your choice, then begin."][stage])
	portrait.visible = selected_house != ""; banner.visible = selected_house != ""
	if selected_house != "":
		var row: Dictionary = current_preview.get("house",{})
		person_label.text = String(row.get("leader_name","Unavailable person"))
		role_label.text = "%s · %s" % [String(custom.get("display_name",row.get("house_name",""))),String(row.get("title","House leader"))]
		purse_label.text = "House purse: %s coins" % RecKit.num(float(row.get("house_purse",0)))
		rights_label.text = String(current_preview.get("rights_text",current_preview.get("reason","")))
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
	if editor.get_parent() == list: list.remove_child(editor)
	UiKit.clear(list); list.add_child(editor); UiKit.clear(editor)
	name_input = null; emblem_input = null; primary_input = null; secondary_input = null
	editor.visible = stage >= 2
	if stage >= 2:
		if stage == 2: _build_customization()
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
	name_input = LineEdit.new(); name_input.name = "HouseDisplayName"; name_input.max_length = 40; name_input.custom_minimum_size.y = 48
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
	var button := OptionButton.new(); button.custom_minimum_size.y = 48; button.size_flags_horizontal = SIZE_EXPAND_FILL
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

func _build_review() -> void:
	editor.add_child(UiKit.label(String(review.get("customization",{}).get("display_name","Your house")),"H2",true))
	var row: Dictionary = review.get("house",{})
	for line: String in ["Settlement: "+String(row.get("town_name","")),"Person: "+String(row.get("leader_name","")),"Role: "+String(row.get("title","House leader")),
		"House purse: %s coins" % RecKit.num(float(row.get("house_purse",0))),"Household: %d existing members" % int(row.get("member_count",0))]:
		editor.add_child(UiKit.label(line,"",true))
	editor.add_child(UiKit.label(String(review.get("rights_text","")),"Small",true))
	editor.add_child(UiKit.label("Field army starts unraised. Raising people and funding the army are separate orders." if review.get("holds_office",false) else "Field army starts unraised. The local lord commands settlement levies.","Small",true))
	editor.add_child(UiKit.label("Your house name and banner change presentation. The household's people, property and funds stay with their actual owners.","Muted",true))

func next_stage() -> void:
	if next_button.disabled: return
	if stage == 3: begin_review(); return
	if stage == 2:
		review = HouseOnboarding.preview(Game,selected_town,selected_house,custom)
		if not bool(review.get("ok",false)): notice = String(review.get("reason","Unavailable house")); _refresh(); return
		custom = review["customization"].duplicate(true); current_preview = review.duplicate(true)
	stage += 1; page_index = 0; search.text = ""; notice = ""; _refresh()

func previous_stage() -> void:
	if stage == 0: Game.goto("title"); return
	stage -= 1; review = {}; page_index = 0; search.text = ""; notice = ""; _refresh()

func begin_review() -> Dictionary:
	if stage != 3 or not bool(review.get("ok",false)): return {"ok":false,"reason":"Review a house before beginning."}
	var person_uid: String = String(review.get("house",{}).get("leader_uid",""))
	var result: Dictionary = HouseOnboarding.begin(Game,selected_town,selected_house,review["customization"],person_uid)
	if not bool(result.get("ok",false)):
		notice = String(result.get("reason","That choice changed. Review a house again.")); review = {}; stage = 1
		house_rows = HouseOnboarding.houses(Game,selected_town); current_preview = HouseOnboarding.preview(Game,selected_town,selected_house,custom); _refresh()
		return result
	Game.save_game_async()
	Game.goto("house",{"back":"map","start":true})
	return result
