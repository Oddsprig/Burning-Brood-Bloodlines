class_name HouseLaws
extends Control
## Read-only native office/kin view. Browsing never changes physical location.
var town_id := ""
var back := "house"
var back_params: Dictionary = {}
var return_location := ""
var body: VBoxContainer
var heading: Label
var scroll: ScrollContainer
var data: Dictionary = {}
var notice := ""
var _refresh_pending := false
var people_row: HBoxContainer

static func read_data(game, tid: String) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	var econ: Dictionary = town.get("econ", {})
	if town.is_empty() or not TownEcon.data()["cultures"].has(str(econ.get("culture", ""))): return {}
	var selected: Dictionary = Dynasty.selected(game)
	var household_view := str(selected.get("town_id", "")) == tid and str(selected.get("selection_kind", "office")) == "household"
	var office: Dictionary = Dynasty.selected_office(game) if household_view else Dynasty.town_office(game, tid)
	var heir: Dictionary = Dynasty.selected_heir(game) if household_view else Dynasty.heir(game, tid)
	var regent: Dictionary = Dynasty.person(game, str(office.get("regent_uid", "")))
	if not bool(regent.get("alive", false)): regent = {}
	# Native heir() revalidates current live identities, including rightful minors.
	if not bool(heir.get("alive", false)): heir = {}
	var race := Persons.race_of(econ)
	return {"town_id": tid, "town_name": str(town.get("name", tid)), "race": race,
		"race_name": str(DB.races.get(race, {}).get("name", race.capitalize())), "law": Dynasty.leadership_law(game) if household_view else Dynasty.law(game, tid),
		"ruler": office, "heir": heir, "regent": regent,
		"household_view": household_view,
		"house_name": str(selected.get("house_name", "House")) if household_view else str(office.get("family_name", selected.get("house_name", "House")))}

static func law_name(law: String) -> String:
	match law:
		"male_preference": return "Sons' lines first"
		"absolute": return "Eldest child's line"
		"strength": return "Strength contests"
		"household_head": return "Household head"
		_: return "Local succession custom"

static func description(law: String) -> String:
	match law:
		"male_preference": return "The eldest son's line comes first, followed by younger sons' lines and then daughters' lines. A deceased child's descendants keep that branch's place."
		"absolute": return "The eldest child's line comes first, regardless of sex. A deceased child's descendants keep that branch's place before younger children."
		"strength": return "Rulers follow the realm's strength contests. No hereditary heir is named."
		"household_head": return "This family's leader follows its existing household register. The realm's rulers still follow strength contests."
		_: return "This settlement follows its existing local succession custom. No hereditary heir is named by this view."

func _ready() -> void:
	town_id = str(Game.screen_params.get("town_id", Dynasty.selected(Game).get("town_id", "")))
	back = str(Game.screen_params.get("back", "house"))
	back_params = Game.screen_params.get("back_params", {}).duplicate(true)
	return_location = str(Game.screen_params.get("return_location", Game.location))
	var frame: Dictionary = UiKit.screen_frame(self, "House Laws")
	heading = frame["title"]; heading.name = "LawsTitle"
	var close := UiKit.button("Back to house" if back == "house" else "Back", _back, "Row", 130)
	close.name = "LawsBack"; frame["bar"].add_child(close)
	scroll = UiKit.scroll(); scroll.name = "LawsScroll"; frame["root"].add_child(scroll)
	body = UiKit.vbox(12); body.name = "LawsBody"; body.size_flags_horizontal = SIZE_EXPAND_FILL; scroll.add_child(body)
	Game.changed.connect(_queue_refresh)
	_refresh()

func _queue_refresh() -> void:
	if _refresh_pending: return
	_refresh_pending = true; call_deferred("_refresh")

func _card(title: String, node_name: String) -> VBoxContainer:
	var card := UiKit.panel("Card")
	card.name = node_name
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var is_person_card := node_name != "LawsRuleCard" and people_row != null
	if is_person_card:
		people_row.add_child(card)
	else:
		body.add_child(card)
	var words := UiKit.vbox(8)
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	if is_person_card:
		var content := UiKit.hbox(12)
		content.size_flags_horizontal = SIZE_EXPAND_FILL
		card.add_child(content)
		content.add_child(words)
	else:
		card.add_child(words)
	if title != "":
		words.add_child(UiKit.label(title, "Muted" if is_person_card else "H2", true))
	return words

func _refresh() -> void:
	_refresh_pending = false
	if body == null: return
	people_row = null
	UiKit.clear(body)
	data = read_data(Game, town_id)
	if data.is_empty():
		body.add_child(UiKit.label("Choose an existing house to view its laws.", "Muted", true)); return
	if notice != "": body.add_child(UiKit.label(notice, "Muted", true))
	var words := _card("", "LawsRuleCard")
	var name_label := UiKit.label("Succession: " + law_name(str(data["law"])), "H2", true)
	name_label.name = "LawsPolicy"
	name_label.mouse_filter = MOUSE_FILTER_PASS
	name_label.tooltip_text = description(str(data["law"]))
	if data["law"] in ["male_preference", "absolute"]:
		name_label.tooltip_text += "\n\nA minor may inherit. A recorded regent serves during the minority. If descendants are exhausted, the next eligible branch follows real family kin."
	name_label.tooltip_text += "\n\nCurrent laws are read-only."
	words.add_child(name_label)
	people_row = UiKit.hbox(12)
	people_row.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(people_row)
	_person_card("Current house leader" if data.get("household_view", false) else "Current ruler", data["ruler"], "LawsRuler", "View leader" if data.get("household_view", false) else "View ruler")
	var next := _card("Next in line", "LawsHeirCard")
	var heir: Dictionary = data["heir"]
	if heir.is_empty():
		next.add_child(UiKit.label("No hereditary heir · strength contests decide" if data["law"] == "strength" else "The current household register selects the next leader" if data["law"] == "household_head" else "No eligible living heir recorded", "Muted", true))
	else:
		_person_words(next, heir, "LawsHeir", "View heir")
		if int(heir.get("age", 0)) < int(People.ages(str(heir.get("race", "human")))["adult"]):
			var minor := UiKit.label("Minor heir · a regent rules until of age", "Small", true)
			minor.add_theme_color_override("font_color", UiTheme.WARN)
			next.add_child(minor)
	if bool(data["ruler"].get("regency", false)):
		var regent: Dictionary = data["regent"]
		if regent.is_empty():
			body.add_child(UiKit.label("Minor ruler · No living regent recorded", "Muted", true))
		else: _person_card("Recorded regent", regent, "LawsRegent", "View regent")

func _person_card(title: String, person: Dictionary, node_name: String, button_text: String) -> void:
	var words := _card(title, node_name + "Card")
	if person.is_empty() or not bool(person.get("alive", false)):
		words.add_child(UiKit.label("Office vacant" + (" · Last ruler: " + str(person["name"]) if person.get("name", "") != "" else ""), "Muted", true)); return
	_person_words(words, person, node_name, button_text)

func _person_words(words: VBoxContainer, person: Dictionary, node_name: String, button_text: String) -> void:
	var pr: Dictionary = Dynasty.person(Game, str(person.get("person_uid", "")))
	if not pr.is_empty():
		var p := Portrait.new()
		p.custom_minimum_size = Vector2(140, 140)
		p.mouse_filter = MOUSE_FILTER_IGNORE
		p.set_spec(Dynasty.portrait_for(Game, pr))
		var content := words.get_parent() as HBoxContainer
		content.add_child(p)
		content.move_child(p, 0)
	var label := UiKit.label(str(person.get("name", "")), "H2", true); label.name = node_name + "Name"; words.add_child(label)
	words.add_child(UiKit.label("Age %d · %s" % [int(person.get("age", 0)), str(person.get("town_name", ""))], "Muted", true))
	var link := UiKit.button(button_text, _person_record.bind(str(person.get("person_uid", ""))), "Row")
	link.name = node_name + "Detail"
	link.size_flags_horizontal = SIZE_SHRINK_BEGIN
	words.add_child(link)

func _context() -> Dictionary:
	return {"town_id": town_id, "back": back, "back_params": back_params.duplicate(true), "return_location": return_location}

func _person_record(uid: String) -> void:
	# Re-resolve stable identity at click time; a stale page must not open a
	# different person who later occupied an old town-local PID/house index.
	var person: Dictionary = Dynasty.person(Game, uid)
	if person.is_empty() or not bool(person.get("alive", false)):
		notice = "This person is no longer a living eligible record."; _refresh(); return
	var tid := str(person["town_id"])
	Game.goto("res://ui/records.tscn", {"view": "town", "id": tid, "tab": "Register", "person_uid": uid,
		"family_id": int(person["family_id"]), "pid": int(person["pid"]), "back": "laws", "back_params": _context()})

func _back() -> void:
	Game.goto(back, back_params.duplicate(true))
