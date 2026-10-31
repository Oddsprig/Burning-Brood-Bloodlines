extends Control
## The records screen (docs/specs/barge 08-12, addendum 13): one frame for a town, a faction or the whole world.
## Top bar: name, day and season, crest, the selector (world / factions / towns, with search), Close.
## Tab bar: 48 px chips that scroll sideways (the only thing that does); the last tab is remembered per view.
## Body: a vertical scroll of cards; tap any person, family, business, town or force for its own page, Back returns.
## Wide windows show a page beside the list (PC: list left, detail right); narrow ones replace the list.
## Builders: ui/rec_town.gd (12 town tabs), ui/rec_world.gd (world and faction tabs), ui/rec_pages.gd (pages).
## RULE: every number shown reads a real sim field; what the sim lacks reads "not tracked" (listed in DEV_NOTES).
##
## Game.screen_params: {view: "town"|"faction"|"world", id, tab, back, force_id (optional)}. Default view: the town the company is in,
## else the last town it visited.

const TOWN_TABS := ["Overview", "Market", "Businesses", "Register", "Land & Homes", "Census", "Treasury", "Hardship",
	"Garrison", "Roads", "Sickness", "Books"]
const WORLD_TABS := ["Towns", "Factions", "Rulers", "On the move", "Goods", "Food flows", "Fights", "Mines & land",
	"Merchants", "Census"]
const FACTION_TABS := ["Towns", "Army", "Factions", "Rulers", "On the move", "Goods", "Food flows", "Fights",
	"Mines & land", "Merchants", "Census"]
const WIDE := 1500.0
const TOWN_GROUPS := [
	{"name":"Overview","tabs":["Overview"]},
	{"name":"People","tabs":["Register","Census","Hardship","Sickness"]},
	{"name":"Economy","tabs":["Market","Businesses","Treasury","Books"]},
	{"name":"Land & defence","tabs":["Land & Homes","Garrison","Roads"]}]
const REALM_GROUPS := [
	{"name":"Places","tabs":["Towns","Factions","Mines & land"]},
	{"name":"People","tabs":["Rulers","Census"]},
	{"name":"Economy","tabs":["Goods","Food flows","Merchants"]},
	{"name":"Military","tabs":["Army","On the move","Fights"]}]

static var last_tab := {"town": "Overview", "faction": "Towns", "world": "Towns"}
static var last_town := ""

var view := "town"
var sel := ""
var tab := "Overview"
var back := "map"
var back_params: Dictionary = {}
var stack: Array = []        # open pages: [{title, fn: Callable(box)}]
var preset := {}             # a filter for the next list built ({filter title: option})
var title_l: Label
var day_l: Label
var crest: Control
var bar: HBoxContainer
var tabs_box: HFlowContainer
var groups_box: HFlowContainer
var tabs_sc: ScrollContainer
var list_sc: ScrollContainer
var list_box: VBoxContainer
var page_sc: ScrollContainer
var page_box: VBoxContainer
var tab_ms := 0.0            # last tab build time (tests: tab switch < 16 ms)
var list_states := {}
var _body_key := ""

func _ready() -> void:
	var f := UiKit.screen_frame(self, "Records")
	bar = f["bar"]
	title_l = f["title"]
	var root: VBoxContainer = f["root"]
	var p: Dictionary = Game.screen_params
	back = String(p.get("back", "town" if Game.location != "" else "map"))
	back_params = p.get("back_params", {}).duplicate(true)
	view = String(p.get("view", "town"))
	sel = String(p.get("id", ""))
	if view == "town" and not RecData.town(sel).has("econ"):
		sel = default_town()
	if view == "town" and sel == "":
		view = "world"
	day_l = UiKit.label("", "Header")
	day_l.add_theme_font_size_override("font_size", 18)
	day_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiKit.shrink(day_l, 60)
	bar.add_child(day_l)
	bar.add_child(UiKit.button("View", open_selector, "Row", 96))
	bar.add_child(UiKit.button("Close", close, "Danger", 96))
	tabs_sc = ScrollContainer.new()
	tabs_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# every tab reachable (Douglas 10-06: "the menu cuts off u cant scroll to right"): a scrollbar shows when the row
	# is wider than the window, the mouse wheel scrolls it sideways, and a mouse drag pans it like a finger
	tabs_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs_sc.custom_minimum_size = Vector2(0, 48)
	tabs_sc.gui_input.connect(_tabs_input)
	tabs_sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_sc.resized.connect(_fit_navigation)
	root.add_child(tabs_sc)
	var navigation := UiKit.vbox(6)
	navigation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs_sc.add_child(navigation)
	groups_box = UiKit.flow(6); groups_box.name = "RecordsCategories"
	groups_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(groups_box)
	tabs_box = UiKit.flow(6); tabs_box.name = "RecordsTabs"
	tabs_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(tabs_box)
	var body := UiKit.hbox(10)
	UiKit.expand(body, true, true)
	root.add_child(body)
	list_sc = UiKit.scroll()
	list_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(list_sc)
	list_box = UiKit.vbox(8)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_sc.add_child(list_box)
	page_sc = UiKit.scroll()
	page_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_sc.visible = false
	body.add_child(page_sc)
	page_box = UiKit.vbox(8)
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_sc.add_child(page_box)
	tab = String(p.get("tab", last_tab.get(view, tabs()[0])))
	if not tabs().has(tab):
		tab = tabs()[0]
	if view == "town":
		last_town = sel
	var person: Dictionary = Dynasty.person(Game,String(p.get("person_uid",""))) if p.has("person_uid") else {}
	if not person.is_empty():
		view = "town"; sel = String(person.get("town_id",sel)); tab = "Register"
	refresh()
	if not person.is_empty():
		open_person(RecData.town(sel),int(person.get("family_id",-1)),int(person.get("pid",-1)))
	elif p.has("family_id") and p.has("pid") and view == "town":
		open_person(RecData.town(sel),int(p["family_id"]),int(p["pid"]))
	elif p.has("force_id"):
		open_force(String(p["force_id"]))

## The town the company is in, else the last it visited (the map's "arrived"), else the start town.
static func default_town() -> String:
	var w: Dictionary = Game.world
	for c in [Game.location, String(w.get("party", {}).get("arrived", "")), last_town, String(w.get("start_town", ""))]:
		if String(c) != "" and RecData.town(String(c)).has("econ"):
			return String(c)
	for tid in w.get("towns", {}):
		if RecData.town(tid).has("econ"):
			return tid
	return ""

func tabs() -> Array:
	return {"town": TOWN_TABS, "faction": FACTION_TABS, "world": WORLD_TABS}[view]

func close() -> void:
	Game.goto(back if back in ["town", "map", "company", "house", "politics", "population", "laws", "muster"] else "map", back_params)

## The towns in view: one town, a faction's towns, or every town.
func tids() -> Array:
	var w: Dictionary = Game.world
	var out := []
	for tid in w.get("towns", {}):
		if not RecData.town(tid).has("econ"):
			continue
		if view == "faction" and String(w["towns"][tid].get("faction", "")) != sel:
			continue
		if view == "town" and tid != sel:
			continue
		out.append(tid)
	out.sort_custom(func(a, b): return RecData.tname(a) < RecData.tname(b))
	return out

# ================================================================== drawing
func refresh() -> void:
	var w: Dictionary = Game.world
	var nm := "The whole world"
	if view == "town":
		nm = RecData.tname(sel)
	elif view == "faction":
		nm = UiWords.faction_name(sel)
	title_l.text = nm
	UiKit.fit_title(title_l)
	day_l.text = "Day %d, %s, year %d" % [Calendar.day_of_season(Game.day), Calendar.season(Game.day), Calendar.year(Game.day)]
	if crest != null:
		crest.queue_free()
		crest = null
	var fid := sel if view == "faction" else (String(w.get("towns", {}).get(sel, {}).get("faction", "")) if view == "town" else "")
	if fid != "":
		crest = UiKit.chip(UiWords.faction_name(fid), UiWords.faction_color(fid))
		var crest_name := crest.get_child(0) as Label
		crest_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		crest_name.custom_minimum_size.x = 100
		crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_child(crest)
		bar.move_child(crest, 2)
	UiKit.clear(groups_box); UiKit.clear(tabs_box)
	var selected_group: Dictionary = {}
	for group: Dictionary in categories():
		if (group["tabs"] as Array).has(tab): selected_group = group
	for group: Dictionary in categories():
		var group_name: String = String(group["name"])
		var button := RecKit.chip_button(group_name,group_name == selected_group.get("name",""),func(): select_category(group_name),96)
		button.set_meta("records_category",group_name)
		groups_box.add_child(button)
	var visible_tabs: Array = selected_group.get("tabs",[])
	tabs_box.visible = visible_tabs.size() > 1
	for tn in visible_tabs:
		var tname := String(tn)
		var b := RecKit.chip_button(tname, tname == tab, func(): show_tab(tname), 96)
		b.add_theme_font_size_override("font_size", 18)
		b.set_meta("records_tab",tname)
		tabs_box.add_child(b)
	_fit_navigation()
	_draw_body()

func _fit_navigation() -> void:
	if tabs_box == null or tabs_sc == null: return
	var width := maxf(1.0, tabs_sc.size.x)
	var height: float = _flow_height(groups_box,width)
	if tabs_box.visible: height += 6.0+_flow_height(tabs_box,width)
	var cap := 162.0
	if UiTheme.is_mobile():
		cap = float(UiKit.MOBILE_TAP) * 2.0 + 6.0
	tabs_sc.custom_minimum_size.y = minf(height, cap)
	tabs_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

static func _flow_height(flow: HFlowContainer, width: float) -> float:
	var used := 0.0
	var lines := 1
	var line_h := 48.0
	for child: Control in flow.get_children():
		var ms := child.get_combined_minimum_size()
		var w := ms.x
		if UiTheme.is_mobile() and ms.y > line_h:
			line_h = ms.y
		if used > 0.0 and used + 6.0 + w > width:
			lines += 1
			used = 0.0
		used += w + (6.0 if used > 0 else 0.0)
	return float(lines) * line_h + float(maxi(0, lines - 1)) * 6.0

func categories() -> Array:
	var result: Array = []
	var all_tabs: Array = tabs()
	var definitions: Array = TOWN_GROUPS if view == "town" else REALM_GROUPS
	for group: Dictionary in definitions:
		var visible: Array = (group["tabs"] as Array).filter(func(value): return all_tabs.has(value))
		if not visible.is_empty(): result.append({"name":group["name"],"tabs":visible})
	return result

func select_category(group_name: String) -> void:
	for group: Dictionary in categories():
		if String(group["name"]) == group_name:
			if not (group["tabs"] as Array).has(tab): show_tab(String(group["tabs"][0]))
			return

func show_tab(t: String) -> void:
	tab = t
	last_tab[view] = t
	stack.clear()
	refresh()

## Switch the view (selector, or a tap on a town / faction anywhere).
func set_view(v: String, id: String = "", t: String = "") -> void:
	view = v
	sel = id
	if view == "town":
		last_town = sel
	tab = t if t != "" else String(last_tab.get(view, tabs()[0]))
	if not tabs().has(tab):
		tab = tabs()[0]
	stack.clear()
	refresh()

func _draw_body() -> void:
	var t0 := Time.get_ticks_usec()
	if _body_key != "" and list_sc.visible:
		var states := []
		for table: RecTable in _tables(list_box): states.append(table.ui_state())
		var open_sections := []
		for section: VBoxContainer in _disclosures(list_box):
			if (section.get_child(1) as Control).visible: open_sections.append(String(section.get_meta("rec_disclosure")))
		list_states[_body_key] = {"tables": states, "scroll": list_sc.scroll_vertical, "open": open_sections}
	UiKit.clear(list_box)
	UiKit.clear(page_box)
	var wide := size.x >= WIDE
	var have_page := not stack.is_empty()
	list_sc.visible = wide or not have_page
	page_sc.visible = have_page
	if list_sc.visible:
		if view == "town":
			var links := UiKit.flow()
			list_box.add_child(links)
			links.add_child(UiKit.button("Politics", _open_civic.bind("politics"), "Row"))
			links.add_child(UiKit.button("Population", _open_civic.bind("population"), "Row"))
		var c: Control
		if view == "town":
			c = RecTown.build(self, RecData.town(sel), tab)
		else:
			c = RecWorld.build(self, tids(), sel if view == "faction" else "", tab)
		list_box.add_child(c)
		_body_key = view + ":" + sel + ":" + tab
		var state: Dictionary = list_states.get(_body_key, {}) if preset.is_empty() else {}
		_restore_disclosures(state.get("open", []))
		var tables := _tables(list_box)
		var remembered: Array = state.get("tables", [])
		for i in mini(tables.size(), remembered.size()): tables[i].restore_ui(remembered[i])
		list_sc.set_deferred("scroll_vertical", int(state.get("scroll", 0)))
	if have_page:
		var top: Dictionary = stack[-1]
		var hb := UiKit.hbox(8)
		hb.add_child(UiKit.button("Back", go_back, "Row", 110))
		var tl := UiKit.label(String(top["title"]), "H2", true)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(tl)
		page_box.add_child(hb)
		(top["fn"] as Callable).call(page_box)
		page_sc.scroll_vertical = 0
	preset = {}
	tab_ms = float(Time.get_ticks_usec() - t0) / 1000.0

func _open_civic(screen: String) -> void:
	PoliticsView.open_view(screen, sel, "records", {"view": view, "id": sel, "tab": tab, "back": back, "back_params": back_params})

func _tables(node: Node) -> Array[RecTable]:
	var found: Array[RecTable] = []
	if node is RecTable: found.append(node)
	for child in node.get_children(): found.append_array(_tables(child))
	return found

func _disclosures(node: Node) -> Array[VBoxContainer]:
	var found: Array[VBoxContainer] = []
	if node is VBoxContainer and node.has_meta("rec_disclosure"): found.append(node)
	for child in node.get_children(): found.append_array(_disclosures(child))
	return found

func _restore_disclosures(open_sections: Array) -> void:
	# Restoring an outer section can reveal another named lazy section.
	for depth in 8:
		var opened := false
		for section: VBoxContainer in _disclosures(list_box):
			if open_sections.has(String(section.get_meta("rec_disclosure"))) and not (section.get_child(1) as Control).visible:
				(section.get_child(0) as Button).pressed.emit()
				opened = true
		if not opened: break

## A detail page: fn(box) fills it. Back returns to what was open before.
func page(title: String, fn: Callable) -> void:
	stack.append({"title": title, "fn": fn})
	_draw_body()

func go_back() -> void:
	if not stack.is_empty():
		stack.pop_back()
	_draw_body()

## A tab opened with a list filter set (Overview "families by state" -> Register filtered).
func goto_tab(t: String, filter: Dictionary) -> void:
	tab = t
	last_tab[view] = t
	stack.clear()
	preset = filter
	refresh()

# ================================================================== the selector
## The whole world; each faction; then every town under its faction (the current town first). Search box on top.
## The tab row: the mouse wheel scrolls it sideways; a drag on its empty space pans it.
func _tabs_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := 80 * (-1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		tabs_sc.scroll_horizontal = maxi(0, tabs_sc.scroll_horizontal + step)
		tabs_sc.accept_event()
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		tabs_sc.scroll_horizontal = maxi(0, tabs_sc.scroll_horizontal - int(ev.relative.x))
		tabs_sc.accept_event()

func open_selector() -> void:
	var v := UiKit.modal(self, "View", 680)
	var le := LineEdit.new()
	le.placeholder_text = "Search towns and factions"
	le.custom_minimum_size = Vector2(0, UiKit.touch_min(52))
	v.add_child(le)
	var sc := UiKit.scroll()
	sc.custom_minimum_size = Vector2(0, 470)
	v.add_child(sc)
	var list := UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var fill := func(q: String) -> void:
		UiKit.clear(list)
		for o in selector_entries(q):
			var oo: Dictionary = o
			var b := UiKit.button(String(oo["text"]), func():
				UiKit.close_modal(v)
				set_view(String(oo["view"]), String(oo["id"])), "RowOn" if oo["view"] == view and oo["id"] == sel else "Row")
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			list.add_child(b)
	fill.call("")
	le.text_changed.connect(func(s): fill.call(String(s)))
	var row := UiKit.hbox()
	row.add_child(UiKit.spacer())
	row.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(v), "", 160))
	v.add_child(row)

## [{text, view, id}] in selector order; every town once, under its current faction.
func selector_entries(q: String = "") -> Array:
	var w: Dictionary = Game.world
	var out := []
	var ql := q.strip_edges().to_lower()
	var cur := default_town() if view != "town" else sel
	if cur != "" and (ql == "" or RecData.tname(cur).to_lower().contains(ql)):
		out.append({"text": "Here: %s" % RecData.tname(cur), "view": "town", "id": cur})
	if ql == "" or "the whole world".contains(ql):
		out.append({"text": "The whole world", "view": "world", "id": ""})
	var fids: Array = w.get("factions", {}).keys()
	fids.sort()
	for fid in fids:
		var fts: Array = []
		for tid in w.get("towns", {}):
			if String(w["towns"][tid].get("faction", "")) == fid and RecData.town(tid).has("econ"):
				fts.append(tid)
		if fts.is_empty():
			continue
		fts.sort_custom(func(a, b): return RecData.tname(a) < RecData.tname(b))
		var fname := UiWords.faction_name(fid)
		if ql == "" or fname.to_lower().contains(ql):
			out.append({"text": fname, "view": "faction", "id": fid})
		for tid in fts:
			if ql == "" or RecData.tname(tid).to_lower().contains(ql) or fname.to_lower().contains(ql):
				out.append({"text": "      %s" % RecData.tname(tid), "view": "town", "id": tid})
	return out

# ================================================================== navigation for the builders
func open_town(tid: String) -> void:
	if RecData.town(tid).has("econ"):
		set_view("town", tid)

func open_faction(fid: String) -> void:
	set_view("faction", fid)

func open_family(t: Dictionary, fid: int) -> void:
	var e := RecData.econ(t)
	var f := RecData.fam(e, fid)
	if f.is_empty():
		return
	page("The %s family" % String(f.get("name", "?")) if not f.get("estate", false) else "Town land", func(box): RecPages.family(self, t, fid, box))

func open_person(t: Dictionary, fid: int, pid: int) -> void:
	var e := RecData.econ(t)
	var f := RecData.fam(e, fid)
	var p := Persons.any(f, pid) if not f.is_empty() else []
	page(Persons.name_of(f, p, Persons.race_of(e)) if not p.is_empty() else "A person", func(box): RecPages.person(self, t, fid, pid, box))

func open_business(t: Dictionary, bid: int) -> void:
	var e := RecData.econ(t)
	if bid < 0 or bid >= RecData.biz(e).size():
		return
	page(RecData.biz_title(e, RecData.biz(e)[bid]).capitalize(), func(box): RecPages.business(self, t, bid, box))

func open_force(wid: String) -> void:
	if not Game.world.get("warbands", {}).has(wid):
		return
	page(RecPages.force_name(Game.world["warbands"][wid]), func(box): RecPages.force(self, wid, box))

## A person by unit (a roster row): his register record when he has one.
func open_unit(u: Unit) -> void:
	var t := RecData.town(u.home_town)
	var f := People.fam_of(t, u.family) if not t.is_empty() else {}
	var p: Array = Persons.by_uid(f, u.uid) if not f.is_empty() else []
	if not p.is_empty():
		open_person(t, int(f["id"]), int(p[0]))
	else:
		page(u.name, func(box): RecPages.unit_page(self, u, box))
