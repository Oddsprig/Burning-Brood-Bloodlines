extends Control
## Company baggage screen: everything the company carries (core/baggage.gd), in four tabs: Weapons, Armour,
## Food and drink, Other items (goods and coin). Each row: icon, name, quantity, quality, material, weight,
## wear, who has it; filter (all / in use / stash), sort (name / weight / value / quality), totals for the tab
## and for the whole baggage. Actions call the code that already does them: Equip from the stash
## (Outfit.equip_item), To stash (Outfit.unequip), Sell in a town (Market.sell, Goods.sell).
## Opened from the company screen; Back returns there. Game.screen_params: {back (the company screen's back)}.

const SCENE := "res://ui/baggage.tscn"

var cat := "weapons"
var where := "all"
var sort_key := "name"
var back := ""
var tabs_box: HBoxContainer
var ctl_box: HFlowContainer
var totals_l: Label
var list_box: VBoxContainer
var purse: Label

func _ready() -> void:
	back = String(Game.screen_params.get("back", ""))
	if Game.screen_params.has("cat"):
		cat = String(Game.screen_params["cat"])
	var f := UiKit.screen_frame(self, "Company Baggage")
	var bar: HBoxContainer = f["bar"]
	bar.add_child(UiKit.spacer())
	bar.add_child(UiKit.button("Back", _back, "", 140))
	var root: VBoxContainer = f["root"]
	purse = UiKit.purse(Game)   # its own row: the whole sum always shows
	root.add_child(purse)
	tabs_box = UiKit.hbox(6)
	root.add_child(tabs_box)
	ctl_box = UiKit.flow(8)
	root.add_child(ctl_box)
	totals_l = UiKit.label("", "H2", true)
	totals_l.name = "Totals"
	root.add_child(totals_l)
	var pp := UiKit.panel()
	UiKit.expand(pp, true, true)
	root.add_child(pp)
	var sc := UiKit.scroll()
	pp.add_child(sc)
	list_box = UiKit.vbox(6)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_box)
	refresh()

func _back() -> void:
	Game.goto("company", {"back": back} if back != "" else {})

func town() -> Dictionary:
	return Game.world.get("towns", {}).get(Game.location, {}) if Game.location != "" else {}

func show_tab(t: String) -> void:
	for k in Baggage.CAT_NAMES:
		if Baggage.CAT_NAMES[k] == t or k == t:
			cat = k
	refresh()

func set_where(w: String) -> void:
	where = w
	refresh()

func set_sort(s: String) -> void:
	sort_key = s
	refresh()

## The rows on screen now (tests).
func shown() -> Array:
	return Baggage.view(Baggage.rows(Game), cat, where if cat in ["weapons", "armour"] else "all", sort_key)

func refresh() -> void:
	purse.text = UiKit.purse_text(Game)
	UiKit.clear(tabs_box)
	var names := []
	for k in Baggage.CATS:
		names.append(Baggage.CAT_NAMES[k])
	tabs_box.add_child(UiKit.tab_strip(names, Baggage.CAT_NAMES[cat], show_tab))
	UiKit.clear(ctl_box)
	if cat in ["weapons", "armour"]:
		ctl_box.add_child(UiKit.label("Show:", "Muted"))
		for w in [["all", "All"], ["in_use", "In use"], ["stash", "Stash"]]:
			ctl_box.add_child(UiKit.button(w[1], set_where.bind(w[0]), "RowOn" if where == w[0] else "Row", 96))
	ctl_box.add_child(UiKit.label("Sort:", "Muted"))
	for s in Baggage.SORTS:
		ctl_box.add_child(UiKit.button(String(s).capitalize(), set_sort.bind(s), "RowOn" if sort_key == s else "Row", 96))
	var all := Baggage.rows(Game)
	var rows := shown()
	var tt := Baggage.totals(rows)
	var ta := Baggage.totals(all)
	totals_l.text = "%s: %d rows, %s, worth %d coins.   All baggage: %s, worth %d coins." % [Baggage.CAT_NAMES[cat], rows.size(),
		UiWords.kg(float(tt["kg"])), int(tt["value"]), UiWords.kg(float(ta["kg"])), int(ta["value"])]
	UiKit.clear(list_box)
	if rows.is_empty():
		list_box.add_child(UiKit.label("Nothing here.", "Muted"))
	for r in rows:
		list_box.add_child(_row(r))

func _row(r: Dictionary) -> Control:
	var card := UiKit.panel("Card")
	var h := UiKit.hbox(10)
	card.add_child(h)
	h.add_child(UiKit.icon(Baggage.icon(r), 44))
	var info := UiKit.vbox(0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = 120
	var nl := UiKit.label(String(r["name"]), "H2")
	nl.name = "RowName"
	info.add_child(UiKit.shrink(nl, 80))
	info.add_child(UiKit.wrap(UiKit.label(Baggage.detail(r), "Muted"), 80))
	h.add_child(info)
	var vl := UiKit.label("%d coins" % int(r["value"]), "H2")
	vl.add_theme_color_override("font_color", UiTheme.COPPER_LO)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(vl)
	var t := town()
	match String(r["kind"]):
		"item":
			var it: Item = r["item"]
			if r["unit"] != null:
				var u: Unit = r["unit"]
				var slot := String(r["slot"])
				h.add_child(UiKit.button("To stash", func():
					Outfit.unequip(u, slot, Game.stash)
					refresh(), "Row", 120))
			else:
				h.add_child(UiKit.button("Equip", func(): _pick_man(it), "", 110))
				if not t.is_empty():
					h.add_child(UiKit.button("Sell %d" % Market.sell_price(t, it), func():
						var p := Market.sell_price(t, it)
						var err := Market.sell(Game, t, it)
						UiKit.toast(self, ("Sold %s for %d coins" % [it.display_name(), p]) if err == "" else err, err == "")
						refresh(), "Row", 120))
		"good":
			var g := String(r["id"])
			var have := int(r["qty"])
			if not t.is_empty() and have > 0:
				h.add_child(UiKit.button("Sell all", func():
					var got := Goods.sell(Game, t, g, have)
					UiKit.toast(self, "Sold %s for %d coins" % [Goods.good_name(g), got])
					refresh(), "Row", 120))
	return card

## Equip a stash piece: pick the man (Outfit.equip_item; what he wore there goes to the stash).
func _pick_man(it: Item) -> void:
	var opts := []
	for u in Game.company:
		if u.dead:
			continue
		var cur: Item = u.equip.get(it.slot(), null)
		opts.append({"text": "%s, %s" % [u.name, u.title], "value": u, "detail": ("has " + cur.display_name()) if cur != null else "nothing there",
			"icon": ItemIcon.for_item(cur) if cur != null else null})
	UiKit.picker(self, "Who takes the %s?" % it.display_name(), opts, func(u):
		var err := Outfit.equip_item(u, it, Game.stash)
		if err != "":
			UiKit.toast(self, err, false)
		refresh())
