class_name Relations
extends Control
## Relations screen (diplomacy, docs/specs/diplomacy.md), opened from the company screen.
## "Company" tab: one card per faction with the standing bar, what the standing does, the band make-up line
## kept separate, the realm's own wars and pacts, and the last five standing events.
## "World" tab: the 5x5 grid of faction-to-faction states (colour per state) and recent declarations.
## Back returns to the company screen (passing on where the company screen itself returns to).

const SCENE := "res://ui/relations.tscn"

var tab: String = "Company"
var page: VBoxContainer
var tabs_box: HBoxContainer
var notice := ""

func _ready() -> void:
	if Game.world.has("diplo"):
		Diplomacy.sync_dynasty(Game)
		Diplomacy.sync_comp(Game)
	var f := UiKit.screen_frame(self, "Relations")
	var bar: HBoxContainer = f["bar"]
	bar.add_child(UiKit.spacer())
	bar.add_child(UiKit.purse(Game))
	bar.add_child(UiKit.button("Back", _back, "", 140))
	var root: VBoxContainer = f["root"]
	tabs_box = UiKit.hbox(6)
	root.add_child(tabs_box)
	var pp := UiKit.panel()
	UiKit.expand(pp, true, true)
	root.add_child(pp)
	page = UiKit.vbox(8)
	UiKit.expand(page, true, true)
	pp.add_child(page)
	if Game.screen_params.has("tab"):
		tab = String(Game.screen_params["tab"])
	refresh()

func _back() -> void:
	var back: String = String(Game.screen_params.get("back", ""))
	Game.goto("company", {"back": back} if back != "" else {})

func show_tab(t: String) -> void:
	tab = t
	refresh()

func refresh() -> void:
	UiKit.clear(tabs_box)
	UiKit.clear(page)
	tabs_box.add_child(UiKit.tab_strip(["Company", "World"], tab, show_tab))
	if not Game.world.has("diplo"):
		page.add_child(UiKit.label("No campaign under way.", "Muted"))
		return
	if notice != "": page.add_child(UiKit.label(notice, "Small", true))
	if tab == "World":
		page.add_child(_world_page())
	else:
		page.add_child(_company_page())

static func short_name(fid: String) -> String:
	return String(Diplomacy.data().get("short_names", {}).get(fid, UiWords.faction_name(fid)))

# ------------------------------------------------------------------ company standing
func _company_page() -> Control:
	var sc := UiKit.scroll()
	var list := UiKit.vbox(10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for fid in Diplomacy.members(Game.world):
		list.add_child(_faction_card(fid))
	return sc

func _faction_card(fid: String) -> Control:
	var card := UiKit.panel("Card")
	var v := UiKit.vbox(4)
	card.add_child(v)
	var s := Diplomacy.standing(Game, fid)
	var top := UiKit.hbox(10)
	var chip := UiKit.chip(UiWords.faction_name(fid), UiWords.faction_color(fid))
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(chip)
	var word := UiKit.label("%s  %+d" % [Diplomacy.standing_word(s), s], "H2")
	word.add_theme_color_override("font_color", UiTheme.BAD if s <= Diplomacy.HOSTILE_STANDING else
		(UiTheme.WARN if s < Diplomacy.RECRUITS_HALVED else (UiTheme.GOOD if s >= Diplomacy.FRIENDLY_STANDING else UiTheme.INK)))
	top.add_child(word)
	top.add_child(UiKit.spacer())
	top.add_child(UiKit.label("earned %+d, company make-up %+d" % [Diplomacy.earned(Game, fid), Diplomacy.comp_offset(Game, fid)], "Muted"))
	v.add_child(top)
	var bar := StandingBar.new()
	bar.value = s
	v.add_child(bar)
	v.add_child(UiKit.label(Diplomacy.effects_text(Game, fid), "Small", true))
	v.add_child(UiKit.label(Diplomacy.comp_line(Game, fid), "Small", true))
	v.add_child(UiKit.label(_realm_line(fid), "Small", true))
	var mine := Diplomacy.player_realm(Game.world)
	if mine != "" and fid != mine:
		var treaty := Diplomacy.treaty_text(Game, fid)
		v.add_child(UiKit.label(treaty if treaty != "" else "No treaty with your realm.", "Small", true))
		var bonus := Diplomacy.dynasty_bonus(Game, fid)
		if bonus > 0:
			v.add_child(UiKit.label("Living marriage to a ruling house: standing +%d, realm relation +%d." % [bonus, int(Diplomacy.DYNASTY_RELATION)], "Small", true))
		if Diplomacy.pact_left(Game.world, mine, fid) > 0 and Diplomacy.allied(Game.world, mine, fid):
			var pair: Dictionary = Game.world["diplo"]["pairs"][Diplomacy.pair_key(mine, fid)]
			v.add_child(UiKit.label("Pact with your realm until year %d" % Calendar.year(float(pair["pact_until"])), "Small", true))
		var actions := UiKit.flow()
		for option in [["Propose alliance", "alliance"], ["Propose non-aggression pact", "pact"], ["Break alliance", "break"]]:
			var action := str(option[1])
			var preview := Diplomacy.action_preview(Game, fid, action)
			var button := UiKit.button(str(option[0]), _review_action.bind(fid, action), "Row", 190)
			button.disabled = not bool(preview.get("ok", false))
			button.tooltip_text = str(preview.get("reason", ""))
			actions.add_child(button)
		v.add_child(actions)
	# economy spec 2: the realm's army, its wage bill and how long the war chest pays it
	var ar := UiKit.hbox(8)
	ar.add_child(UiKit.wrap(UiKit.label(army_line(fid), "Small", true), 200))
	ar.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ar.add_child(UiKit.button("Ranks", func(): ArmyPanel.open(self, fid), "Row", 140))
	v.add_child(ar)
	var lg: Array = Diplomacy.log_of(Game, fid)
	if lg.is_empty():
		v.add_child(UiKit.label("No dealings with them yet.", "Muted"))
	for i in range(lg.size() - 1, -1, -1):
		var e: Dictionary = lg[i]
		var l := UiKit.label("Day %d: %+d  %s" % [int(e["day"]), int(e["delta"]), String(e["text"])], "Muted", true)
		if int(e["delta"]) != 0:
			l.add_theme_color_override("font_color", UiTheme.GOOD if int(e["delta"]) > 0 else UiTheme.BAD)
		v.add_child(l)
	return card

func _review_action(fid: String, action: String) -> void:
	var preview := Diplomacy.action_preview(Game, fid, action)
	if not preview.get("ok", false):
		notice = str(preview.get("reason", "")); refresh(); return
	var text := UiWords.faction_name(fid) + "\n" + str(preview["reason"])
	UiKit.confirm(self, text, "Confirm", _apply_action.bind(fid, action, preview["review"]))

func _apply_action(fid: String, action: String, review: Dictionary) -> Dictionary:
	var result := Diplomacy.act(Game, fid, action, review)
	notice = str(result.get("reason", ""))
	refresh()
	return result

## "Army: 24 men under Grukk (warlord); wage bill 101 gold a day; war chest 474 gold, 5 days of pay."
static func army_line(fid: String) -> String:
	var w: Dictionary = Game.world
	var fac: Dictionary = w.get("factions", {}).get(fid, {})
	var lead: Dictionary = fac.get("war_leader", {})
	var dl := Army.days_of_pay(Game, fid)
	return "Army: %d men%s; wage bill %d coins a day; war chest %d coins, %s." % [Army.members(Game, fid).size(),
		(" under %s (%s)" % [lead["name"], lead["title"]]) if not lead.is_empty() else "", int(round(Army.bill(Game, fid))),
		int(fac.get("treasury", 0.0)), ("%d days of pay" % int(dl)) if dl < 9999.0 else "nothing to pay"]

## "At war with the Red Tusk Horde; trade pact with the Silvered Court." (the faction-to-faction layer)
func _realm_line(fid: String) -> String:
	var groups := {}
	for o in Diplomacy.members(Game.world):
		if o == fid:
			continue
		var st := Diplomacy.state(Game.world, fid, o)
		if st == Diplomacy.NEUTRAL:
			continue
		if not groups.has(st):
			groups[st] = []
		var tt := Diplomacy.truce_text(Game.world, fid, o)   # war pick 2
		groups[st].append(CampaignWorld.faction_the(o) + (" (%s)" % tt if tt != "" else ""))
	var parts := []
	for st in [Diplomacy.WAR, Diplomacy.HOSTILE, Diplomacy.TRADE_PACT, Diplomacy.ALLIANCE]:
		if groups.has(st):
			var lead: String = {"WAR": "at war with", "HOSTILE": "hostile to", "TRADE_PACT": "trade pact with", "ALLIANCE": "allied with"}[st]
			parts.append("%s %s" % [lead, " and ".join(PackedStringArray(groups[st]))])
	if parts.is_empty():
		return "Their realm: at peace with everyone."
	return "Their realm: " + "; ".join(PackedStringArray(parts)) + "."

# ------------------------------------------------------------------ world grid
func _world_page() -> Control:
	var sc := UiKit.scroll()
	var v := UiKit.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var fl: Array = Diplomacy.members(Game.world)
	var grid := GridContainer.new()
	grid.columns = fl.size() + 1
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	grid.add_child(Control.new())
	for f in fl:
		grid.add_child(_head(f))
	for a in fl:
		grid.add_child(_head(a))
		for b in fl:
			grid.add_child(_cell(a, b))
	var legend := UiKit.hbox(8)
	for st in [Diplomacy.WAR, Diplomacy.HOSTILE, Diplomacy.NEUTRAL, Diplomacy.TRADE_PACT, Diplomacy.ALLIANCE]:
		legend.add_child(UiKit.chip(Diplomacy.STATE_WORDS[st], Color(Diplomacy.STATE_COLORS[st])))
	v.add_child(legend)
	v.add_child(UiKit.label("Relations drift back toward old grudges; wars wear factions down until they make peace, and a peace holds a truce of %d-%d days." % [Diplomacy.TRUCE_MIN, Diplomacy.TRUCE_MAX], "Muted", true))
	v.add_child(UiKit.label("Recent news", "H2"))
	var news: Array = Game.world["diplo"].get("news", [])
	if news.is_empty():
		v.add_child(UiKit.label("No declarations since the company took the field.", "Muted"))
	for i in range(news.size() - 1, maxi(-1, news.size() - 9), -1):
		v.add_child(UiKit.label("Day %d: %s" % [int(news[i]["day"]) + 1, String(news[i]["text"])], "Small", true))
	return sc

func _head(fid: String) -> Control:
	var p := PanelContainer.new()
	var col := UiWords.faction_color(fid)
	p.add_theme_stylebox_override("panel", UiTheme.sb(col, col.darkened(0.35), 2, 6, 8, 4))
	p.custom_minimum_size = Vector2(150, 56)
	var l := Label.new()
	l.text = short_name(fid)
	l.add_theme_color_override("font_color", UiTheme.LIGHT)
	l.add_theme_font_override("font", UiTheme.bold())
	l.add_theme_font_size_override("font_size", 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	return p

func _cell(a: String, b: String) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(150, 56)
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	if a == b:
		p.add_theme_stylebox_override("panel", UiTheme.sb(UiTheme.PARCH_3, UiTheme.PARCH_3.darkened(0.2), 1, 6, 8, 4))
		l.text = "-"
		l.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	else:
		var st := Diplomacy.state(Game.world, a, b)
		var col := Color(Diplomacy.STATE_COLORS[st])
		p.add_theme_stylebox_override("panel", UiTheme.sb(col, col.darkened(0.35), 2, 6, 8, 4))
		l.text = "%s\n%+d" % [Diplomacy.STATE_WORDS[st], int(round(Diplomacy.relation(Game.world, a, b)))]
		var tt := Diplomacy.truce_text(Game.world, a, b)   # war pick 2: "truce, 47 days left"
		if Diplomacy.pact_left(Game.world, a, b) > 0:
			var pair: Dictionary = Game.world["diplo"]["pairs"][Diplomacy.pair_key(a, b)]
			tt = "Non-aggression until year %d" % Calendar.year(float(pair["pact_until"]))
		if tt != "":
			l.text += "\n" + tt
			l.add_theme_font_size_override("font_size", 15)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", UiTheme.LIGHT)
		l.add_theme_font_override("font", UiTheme.bold())
	p.add_child(l)
	return p

## Standing -100..100 as a bar filled from the centre: green to the right, red to the left; ticks at the
## thresholds that change what a faction does (-50 hostile, -30 no contracts, -20 fewer recruits, +50 friendly).
class StandingBar extends Control:
	var value := 0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 26)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(0, 3), Vector2(size.x, size.y - 6))
		draw_rect(r, UiTheme.PARCH_3)
		var cx := r.size.x * 0.5
		var x := r.size.x * (clampi(value, -100, 100) + 100) / 200.0
		var col := UiTheme.GOOD if value >= 0 else UiTheme.BAD
		draw_rect(Rect2(Vector2(minf(cx, x), r.position.y), Vector2(absf(x - cx), r.size.y)), col)
		for t: int in [-50, -30, -20, 50]:
			var tx: float = r.size.x * (t + 100) / 200.0
			draw_line(Vector2(tx, r.position.y), Vector2(tx, r.end.y), Color(UiTheme.INK, 0.45), 1.5)
		draw_line(Vector2(cx, 0), Vector2(cx, size.y), UiTheme.INK, 2)
		draw_rect(r, UiTheme.BORDER, false, 1.5)
