extends Control
## Court ("court"): your house as a family tree. Generations are rows, couples sit together, lines run from parents
## to children. Each portrait shows relation, age and status at a glance; click it to open the person (match-making,
## betrothal). A short "what needs doing" line leads; alliances and claims sit in a compact strip below.

const NODE_W := 150.0
var body: VBoxContainer
var tree_view: FamilyTree
var notice := ""
var ruler_uid := ""

func _ready() -> void:
	var frame := UiKit.screen_frame(self, "Court")
	frame["bar"].add_child(UiKit.button("Back", func(): Game.goto(String(Game.screen_params.get("back", "map"))), "Row", 96))
	var scroll := UiKit.scroll()
	frame["root"].add_child(scroll)
	body = UiKit.vbox(14)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(body)
	_refresh()

# ------------------------------------------------------------------ relations
static func relation(row: Dictionary, ruler: Dictionary, gen: int, is_spouse_of_ruler: bool, in_law: bool) -> String:
	var f := int(row.get("sex", 0)) == 1
	if str(row.get("person_uid", "")) == str(ruler.get("person_uid", "")): return str(ruler.get("title", "Ruler"))
	if is_spouse_of_ruler: return "Wife" if f else "Husband"
	if in_law: return ("Daughter-in-law" if f else "Son-in-law") if gen == 2 else ("Sister-in-law" if f else "Brother-in-law")
	match gen:
		0: return "Mother" if f else "Father"
		1: return "Sister" if f else "Brother"
		2: return "Daughter" if f else "Son"
		3: return "Granddaughter" if f else "Grandson"
	return "Kinswoman" if f else "Kinsman"

## {uid: {row, gen, rel, parents:[uids], spouse_uid}} for every living member of the house plus married-in spouses.
func _layout_data() -> Dictionary:
	var ruler := Dynasty.ruler(Game)
	ruler_uid = str(ruler.get("person_uid", ""))
	var fam: Array = Marriage.family(Game)
	var by_uid := {}
	for row: Dictionary in fam: by_uid[str(row["person_uid"])] = row
	# spouses who are not house members (married in) are shown beside their partner
	for row: Dictionary in fam:
		var sp: Dictionary = row.get("spouse", {})
		if not sp.is_empty() and bool(sp.get("alive", false)) and not by_uid.has(str(sp.get("person_uid", ""))):
			var r2: Dictionary = sp.duplicate(); r2["married"] = true; r2["married_in"] = true
			by_uid[str(sp["person_uid"])] = r2
	var gen := {}
	if by_uid.has(ruler_uid): gen[ruler_uid] = 1
	var changed := true
	var guard := 0
	while changed and guard < 8:
		changed = false; guard += 1
		for uid in by_uid:
			var row: Dictionary = by_uid[uid]
			for puid in [str(row.get("mother_uid", "")), str(row.get("father_uid", ""))]:
				if gen.has(puid) and not gen.has(uid): gen[uid] = int(gen[puid]) + 1; changed = true
				if gen.has(uid) and by_uid.has(puid) and not gen.has(puid): gen[puid] = int(gen[uid]) - 1; changed = true
			var sp_uid := str(row.get("spouse_uid", ""))
			if gen.has(sp_uid) and not gen.has(uid): gen[uid] = gen[sp_uid]; changed = true
			if gen.has(uid) and by_uid.has(sp_uid) and not gen.has(sp_uid): gen[sp_uid] = gen[uid]; changed = true
	var ruler_parents := [str(ruler.get("mother_uid", "")), str(ruler.get("father_uid", ""))]
	for uid in by_uid:
		var row: Dictionary = by_uid[uid]
		if not gen.has(uid):
			# siblings of the ruler share a parent who may be dead (not in the tree)
			if str(row.get("mother_uid", "")) in ruler_parents or str(row.get("father_uid", "")) in ruler_parents: gen[uid] = 1
			else: gen[uid] = 9   # wider family
	var out := {}
	for uid in by_uid:
		var row: Dictionary = by_uid[uid]
		var g := int(gen[uid])
		var sp_uid := str(row.get("spouse_uid", ""))
		var in_law := bool(row.get("married_in", false)) and sp_uid != ruler_uid
		out[uid] = {"row": row, "gen": g, "spouse_uid": sp_uid,
			"parents": [str(row.get("mother_uid", "")), str(row.get("father_uid", ""))].filter(func(p): return by_uid.has(p)),
			"rel": relation(row, ruler, g, sp_uid == ruler_uid and uid != ruler_uid, in_law)}
	return out

# ------------------------------------------------------------------ screen
func _refresh() -> void:
	UiKit.clear(body)
	var ruler := Dynasty.ruler(Game)
	if ruler.is_empty():
		body.add_child(UiKit.label("Choose a house to hold court.", "Muted", true)); return
	if notice != "":
		var n := UiKit.label(notice, "", true)
		n.add_theme_color_override("font_color", UiTheme.BRASS)
		body.add_child(n)
	var data := _layout_data()
	body.add_child(_direction(data))
	tree_view = FamilyTree.new()
	tree_view.host = self
	tree_view.build(data, ruler_uid)
	body.add_child(tree_view)
	body.add_child(_politics_strip())
	body.add_child(_plots_panel())
	body.add_child(_prisoners_panel())

## One line that says what matters now.
func _direction(data: Dictionary) -> Control:
	var heir := Dynasty.selected_heir(Game)
	var can_wed := 0
	var children := 0
	for uid in data:
		var row: Dictionary = data[uid]["row"]
		if bool(row.get("can_betroth", false)): can_wed += 1
		if int(data[uid]["gen"]) >= 2: children += 1
	var text := ""
	var tone := UiTheme.INK
	if heir.is_empty():
		text = "You have no heir. Marry and have children, or your line may end with your ruler."
		tone = UiTheme.WARN
	elif can_wed > 0:
		text = "Heir: %s.  %d of your family can be matched: click anyone marked \"can marry\" to find a spouse." % [heir.get("name", "?"), can_wed]
	else:
		text = "Heir: %s.  Your family is settled." % heir.get("name", "?")
	var p := UiKit.panel("Inset")
	var l := UiKit.label(text, "", true)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", tone)
	p.add_child(l)
	return p

func _politics_strip() -> Control:
	var st: Dictionary = Marriage.state(Game)
	var box := UiKit.vbox(6)
	var parts: Array = []
	for hh in st["alliances"]:
		parts.append("House %s" % st["alliances"][hh].get("house_name", "?"))
	box.add_child(UiKit.label("Allies by marriage: " + (", ".join(parts) if not parts.is_empty() else "none yet"), "Muted", true))
	if not (st["claims"] as Dictionary).is_empty():
		var c: Array = []
		for tid in st["claims"]: c.append(str(Game.world["towns"].get(tid, {}).get("name", tid)))
		box.add_child(UiKit.label("Claims: " + ", ".join(c) + " (besiege to take them as rightful heirs)", "Muted", true))
	if not (st["betrothals"] as Array).is_empty():
		var b: Array = []
		for e: Dictionary in st["betrothals"]: b.append("%s & %s" % [Marriage.me_name(Game, str(e["a"])), str(Dynasty.person(Game, str(e["b"])).get("name", "?"))])
		box.add_child(UiKit.label("Betrothed: " + ", ".join(b), "Muted", true))
	return box

func _plots_panel() -> Control:
	var panel := UiKit.panel("Inset")
	var box := UiKit.vbox(6); panel.add_child(box)
	var heading := UiKit.hbox(8); box.add_child(heading)
	heading.add_child(UiKit.label("Plots", "H2"))
	heading.add_child(UiKit.spacer())
	heading.add_child(UiKit.button("Choose a target", _open_targets, "Row", 200))
	var plots := Intrigue.active(Game)
	if plots.is_empty(): box.add_child(UiKit.label("No active schemes.", "Muted", true))
	for plot: Dictionary in plots:
		box.add_child(UiKit.label("%s: %s — %d days left" % [plot["name"], plot["target_name"], int(plot["left"])], "", true))
	var history: Array = Intrigue.state(Game)["log"]
	for entry: Dictionary in history.slice(maxi(0, history.size() - 3)):
		box.add_child(UiKit.label(str(entry["text"]), "Muted", true))
	return panel

func _open_targets() -> void:
	var v := UiKit.modal(self, "Other houses", 900)
	v.add_child(UiKit.label("Choose a ruler to view their person and plan a scheme.", "Muted", true))
	var sc := UiKit.scroll(); sc.custom_minimum_size = Vector2(0, 480); v.add_child(sc)
	var rows := UiKit.vbox(8); rows.size_flags_horizontal = SIZE_EXPAND_FILL; sc.add_child(rows)
	var count := 0
	for choice: Dictionary in Dynasty.choices(Game):
		if str(choice["house_uid"]) == str(Game.world.get("player_house", {}).get("house_uid", "")): continue
		var person := Dynasty.person(Game, str(choice["ruler_uid"]))
		if not person.get("alive", false): continue
		person["adult"] = int(person["age"]) >= int(People.ages(str(person["race"]))["adult"])
		person["spouse"] = Dynasty.person(Game, str(person.get("spouse_uid", "")))
		person["married"] = bool(person["spouse"].get("alive", false))
		var node := {"row": person, "rel": "House %s" % choice["house_name"]}
		rows.add_child(UiKit.button("%s — House %s, %s" % [person["name"], choice["house_name"], choice["town_name"]], func():
			UiKit.close_modal(v); open_person(node), "Row", 0))
		count += 1
	if count == 0: rows.add_child(UiKit.label("No other living ruling houses.", "Muted", true))
	v.add_child(UiKit.button("Close", func(): UiKit.close_modal(v), "Row", 120))

func _open_scheme(uid: String, kind: String) -> void:
	var offer := Intrigue.preview(Game, uid, kind)
	var v := UiKit.modal(self, "%s: %s" % [Intrigue.SCHEMES[kind]["name"], Dynasty.person(Game, uid).get("name", "?")], 760)
	if offer.has("cost"):
		v.add_child(UiKit.label("Target town: %s" % offer["town_name"], "H2", true))
		v.add_child(UiKit.label(str(Intrigue.SCHEMES[kind]["effect"]), "", true))
		v.add_child(UiKit.label("Cost: %d coins from your house purse.  Duration: %d days." % [int(float(offer["cost"]) / Item.COIN), int(offer["days"])], "", true))
		v.add_child(UiKit.label("Success chance: %.0f%%.  Discovery risk: %.0f%%." % [float(offer["chance"]) * 100.0, float(offer["discovery"]) * 100.0], "", true))
		v.add_child(UiKit.label("Discovery costs %d standing with %s, even if the scheme fails." % [Intrigue.DISCOVERY_LOSS, CampaignWorld.faction_name(str(offer["faction_id"]))], "Muted", true))
	if not offer.get("ok", false): v.add_child(UiKit.label(str(offer.get("text", "")), "Muted", true))
	var footer := UiKit.hbox(8); v.add_child(footer)
	footer.add_child(UiKit.spacer())
	if offer.get("ok", false):
		footer.add_child(UiKit.button("Confirm scheme", func():
			var result := Intrigue.start(Game, uid, kind, offer["review"])
			notice = str(result.get("text", ""))
			UiKit.close_modal(v)
			if result.get("ok", false): Game.save_game_async()
			_refresh(), "", 200))
	footer.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(v), "Row", 120))

# ------------------------------------------------------------------ prisoners (v0.033)
const PRISONER_ROWS := 40   # rows listed per side in one realm's window; the rest are counted

## One line per realm: what you hold of theirs and what they hold of yours, with the latest bargains.
func _prisoners_panel() -> Control:
	var panel := UiKit.panel("Inset")
	var box := UiKit.vbox(6); panel.add_child(box)
	box.add_child(UiKit.label("Prisoners", "H2"))
	var held := Prisoners.held(Game)
	var caps := Prisoners.captives(Game)
	if held.is_empty() and caps.is_empty():
		box.add_child(UiKit.label("No prisoners on either side. Men downed on a field the other side holds are taken prisoner.", "Muted", true))
	var realms: Array = []
	for rec: Dictionary in held:
		if not realms.has(str(rec.get("faction", ""))): realms.append(str(rec.get("faction", "")))
	for rec: Dictionary in caps:
		if not realms.has(str(rec.get("held_by", ""))): realms.append(str(rec.get("held_by", "")))
	for fid: String in realms:
		var ours := held.filter(func(r): return str(r.get("faction", "")) == fid).size()
		var theirs := caps.filter(func(r): return str(r.get("held_by", "")) == fid).size()
		var line := UiKit.hbox(8); box.add_child(line)
		var l := UiKit.label("%s: you hold %d of theirs; they hold %d of yours." % [CampaignWorld.faction_name(fid), ours, theirs], "", true)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(l)
		line.add_child(UiKit.button("Bargain", func(): _open_prisoners(fid), "Row", 140))
	var history: Array = Prisoners.state(Game)["log"]
	for entry: Dictionary in history.slice(maxi(0, history.size() - 3)):
		box.add_child(UiKit.label(str(entry["text"]), "Muted", true))
	return panel

func _prisoner_line(r: Dictionary) -> String:
	var hurt := " (%s)" % r["health"] if str(r["health"]) in ["should rest", "cannot fight"] else ""
	if bool(r["legacy"]): return "%s, %s — record only, taken before ransoms were kept" % [r["name"], r["kind_text"]]
	return "%s, %s%s — worth %d coins, held %d days" % [r["name"], r["kind_text"], hurt, Prisoners._coins(int(r["price"])), int(r["days"])]

func _open_prisoners(fid: String) -> void:
	var v := UiKit.modal(self, "Prisoners: %s" % CampaignWorld.faction_name(fid), 980)
	v.add_child(UiKit.label("Ransoms move real coin between your house purse and their house or realm. An exchange trades one for one: they give back no one worth more than the prisoner you return.", "Muted", true))
	var sc := UiKit.scroll(); sc.custom_minimum_size = Vector2(0, 480); v.add_child(sc)
	var rows := UiKit.vbox(8); rows.size_flags_horizontal = SIZE_EXPAND_FILL; sc.add_child(rows)
	var caps := Prisoners.captives(Game).filter(func(r): return str(r.get("held_by", "")) == fid)
	var held := Prisoners.held(Game).filter(func(r): return str(r.get("faction", "")) == fid)
	var seats := Prisoners.ruling(Game)
	rows.add_child(UiKit.label("Your people they hold (%d)" % caps.size(), "H2"))
	if caps.is_empty(): rows.add_child(UiKit.label("None.", "Muted", true))
	for rec: Dictionary in caps.slice(0, PRISONER_ROWS):
		var r := Prisoners.row(Game, rec, true, seats)
		var line := UiKit.hbox(8); rows.add_child(line)
		var l := UiKit.label(_prisoner_line(r), "", true); l.size_flags_horizontal = SIZE_EXPAND_FILL; line.add_child(l)
		if bool(r["legacy"]): continue
		var uid := int(r["uid"])
		line.add_child(UiKit.button("Pay ransom", func(): _bargain(v, "pay", uid), "Row", 160))
		var pick := Prisoners.exchange_pick(Game, uid, seats)
		if pick >= 0: line.add_child(UiKit.button("Exchange", func(): _bargain(v, "exchange", uid, pick), "Row", 140))
	if caps.size() > PRISONER_ROWS: rows.add_child(UiKit.label("and %d more" % (caps.size() - PRISONER_ROWS), "Muted", true))
	rows.add_child(UiKit.label("Their people you hold (%d)" % held.size(), "H2"))
	if held.is_empty(): rows.add_child(UiKit.label("None.", "Muted", true))
	for rec: Dictionary in held.slice(0, PRISONER_ROWS):
		var r := Prisoners.row(Game, rec, false, seats)
		var line := UiKit.hbox(8); rows.add_child(line)
		var l := UiKit.label(_prisoner_line(r), "", true); l.size_flags_horizontal = SIZE_EXPAND_FILL; line.add_child(l)
		if bool(r["legacy"]): continue
		var uid := int(r["uid"])
		line.add_child(UiKit.button("Ransom", func(): _bargain(v, "ransom", uid), "Row", 130))
		line.add_child(UiKit.button("Release", func(): _bargain(v, "release", uid), "Row", 130))
	if held.size() > PRISONER_ROWS: rows.add_child(UiKit.label("and %d more" % (held.size() - PRISONER_ROWS), "Muted", true))
	var footer := UiKit.hbox(8); v.add_child(footer)
	if held.size() > 1:
		footer.add_child(UiKit.button("Ransom all", func(): _bargain_all(v, fid, "ransom"), "Row", 160))
		footer.add_child(UiKit.button("Release all", func(): _bargain_all(v, fid, "release"), "Row", 160))
	footer.add_child(UiKit.spacer())
	footer.add_child(UiKit.button("Close", func(): UiKit.close_modal(v), "Row", 120))

## Review one bargain, then confirm it.
func _bargain(parent: Control, action: String, uid: int, other: int = -1) -> void:
	var offer := Prisoners.preview(Game, action, uid, other)
	var titles := {"ransom": "Ransom", "release": "Release", "pay": "Pay ransom", "exchange": "Exchange"}
	var v := UiKit.modal(self, "%s: %s" % [titles.get(action, action), str(offer.get("name", "?"))], 720)
	v.add_child(UiKit.label(str(offer.get("text", "")), "" if offer.get("ok", false) else "Muted", true))
	var footer := UiKit.hbox(8); v.add_child(footer)
	footer.add_child(UiKit.spacer())
	if offer.get("ok", false):
		footer.add_child(UiKit.button("Confirm", func():
			var result := Prisoners.confirm(Game, action, uid, other, offer["review"])
			notice = str(result.get("text", ""))
			UiKit.close_modal(v); UiKit.close_modal(parent)
			if result.get("ok", false): Game.save_game_async()
			_refresh(), "", 160))
	footer.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(v), "Row", 120))

## Every prisoner of one realm, one bargain at a time (each pays from whoever can still afford it).
func _bargain_all(parent: Control, fid: String, action: String) -> void:
	var uids: Array = Prisoners.held(Game).filter(func(r): return str(r.get("faction", "")) == fid and r.get("unit") is Unit).map(func(r): return int(r["uid"]))
	var v := UiKit.modal(self, "%s all: %s" % ["Ransom" if action == "ransom" else "Release", CampaignWorld.faction_name(fid)], 720)
	v.add_child(UiKit.label(("Offer each of the %d prisoners for ransom; those their house or realm cannot pay for stay with you." if action == "ransom"
		else "Free all %d prisoners. Standing with their realm rises once.") % uids.size(), "", true))
	var footer := UiKit.hbox(8); v.add_child(footer)
	footer.add_child(UiKit.spacer())
	footer.add_child(UiKit.button("Confirm", func():
		var done := 0; var coin := 0
		for uid: int in uids:
			var offer := Prisoners.preview(Game, action, uid)
			if offer.get("ok", false) and Prisoners.confirm(Game, action, uid, -1, offer["review"]).get("ok", false):
				done += 1; coin += int(offer.get("price", 0))
		notice = ("Ransomed %d of %d for %d coins." % [done, uids.size(), Prisoners._coins(coin)]) if action == "ransom" else ("Released %d prisoners." % done)
		UiKit.close_modal(v); UiKit.close_modal(parent)
		if done > 0: Game.save_game_async()
		_refresh(), "", 160))
	footer.add_child(UiKit.button("Cancel", func(): UiKit.close_modal(v), "Row", 120))

# ------------------------------------------------------------------ person panel
func open_person(node: Dictionary) -> void:
	var row: Dictionary = node["row"]
	var v := UiKit.modal(self, str(row.get("name", "?")), 760)
	var h := UiKit.hbox(16); v.add_child(h)
	var p := Portrait.new(); p.custom_minimum_size = Vector2(150, 150); p.set_spec(Dynasty.portrait_for(Game, row)); h.add_child(p)
	var col := UiKit.vbox(6); col.size_flags_horizontal = SIZE_EXPAND_FILL; h.add_child(col)
	col.add_child(UiKit.label("%s · %s, %d" % [node["rel"], "woman" if int(row.get("sex", 0)) == 1 else "man", int(row.get("age", 0))], "H2", true))
	col.add_child(UiKit.label(_status_text(row), "", true))
	var mo := Dynasty.person(Game, str(row.get("mother_uid", "")))
	var fa := Dynasty.person(Game, str(row.get("father_uid", "")))
	if not mo.is_empty() or not fa.is_empty():
		col.add_child(UiKit.label("Child of %s and %s" % [fa.get("name", "unknown"), mo.get("name", "unknown")], "Muted", true))
	col.add_child(UiKit.label("Lives at %s" % row.get("town_name", "?"), "Muted", true))
	var uid := str(row.get("person_uid", ""))
	var house := str(row.get("house_uid", ""))
	if bool(row.get("alive", false)) and house != "" and house != str(Game.world.get("player_house", {}).get("house_uid", "")):
		var schemes := UiKit.hbox(8); v.add_child(schemes)
		for spec in [["assassinate", "Plot assassination"], ["sway", "Sway"], ["fabricate_claim", "Fabricate claim"]]:
			var kind := str(spec[0])
			schemes.add_child(UiKit.button(str(spec[1]), func():
				UiKit.close_modal(v); _open_scheme(uid, kind), "Row", 0))
	var footer := UiKit.hbox(8); v.add_child(footer)
	footer.add_child(UiKit.spacer())
	if bool(row.get("can_betroth", false)) and not bool(row.get("married_in", false)):
		footer.add_child(UiKit.button("Find a spouse" if bool(row.get("adult", false)) else "Arrange betrothal", func():
			UiKit.close_modal(v); _open_matches(uid, str(row.get("name", ""))), "", 220))
	footer.add_child(UiKit.button("Close", func(): UiKit.close_modal(v), "Row", 120))

func _status_text(row: Dictionary) -> String:
	if bool(row.get("married_in", false)): return "Married into your house"
	if bool(row.get("married", false)):
		var sp: Dictionary = row.get("spouse", {})
		return "Married to %s" % sp.get("name", "?") if not sp.is_empty() else "Married"
	if bool(row.get("betrothed", false)): return "Betrothed"
	if bool(row.get("adult", false)): return "Unmarried"
	return "Not yet of age (adult at %d)" % int(People.ages(str(row.get("race", "human")))["adult"])

func _open_matches(member_uid: String, member_name: String) -> void:
	var list: Array = Marriage.candidates(Game, member_uid)
	var v := UiKit.modal(self, "A match for %s" % member_name, 1100)
	v.add_child(UiKit.label("Green: their house would say yes. A gift from your purse can win over a doubtful house.", "Muted", true))
	if list.is_empty(): v.add_child(UiKit.label("No unmarried nobles of a suitable age right now.", "", true))
	var sc := UiKit.scroll(); sc.custom_minimum_size = Vector2(0, 560); v.add_child(sc)
	var rows := UiKit.vbox(8); rows.size_flags_horizontal = SIZE_EXPAND_FILL; sc.add_child(rows)
	for o: Dictionary in list.slice(0, 12):
		var card := UiKit.panel("Card"); rows.add_child(card)
		var h := UiKit.hbox(12); card.add_child(h)
		var pt := Portrait.new(); pt.custom_minimum_size = Vector2(84, 84); pt.set_spec(Dynasty.portrait_for(Game, o["row"])); h.add_child(pt)
		var col := UiKit.vbox(2); col.size_flags_horizontal = SIZE_EXPAND_FILL; col.custom_minimum_size.x = 360; h.add_child(col)
		var name := UiKit.label("%s of House %s" % [o["name"], o["house_name"]], "H2", true)
		name.add_theme_font_size_override("font_size", 21)
		col.add_child(name)
		col.add_child(UiKit.label("%s, %d · %s" % ["woman" if int(o["sex"]) == 1 else "man", int(o["age"]), o["town_name"]], "Muted", true))
		var yes: bool = o["accepts"]
		var best := ""
		var worst := ""
		var hi := -999.0; var lo := 999.0
		for r: Array in o["reasons"]:
			if float(r[1]) > hi: hi = float(r[1]); best = str(r[0])
			if float(r[1]) < lo: lo = float(r[1]); worst = str(r[0])
		var verdict := UiKit.label(("Would accept" if yes else "Would refuse") + (" · helped by: %s" % best if hi > 0 else "") + (" · against: %s" % worst if lo < 0 else ""), "", true)
		verdict.add_theme_color_override("font_color", UiTheme.GOOD if yes else UiTheme.WARN)
		col.add_child(verdict)
		if str(o["egg_name"]) != "": col.add_child(UiKit.label("Dowry includes the " + str(o["egg_name"]), "", true))
		var cuid := str(o["person_uid"])
		var buttons := UiKit.vbox(6); h.add_child(buttons)
		for tier in Marriage.GIFTS.size():
			var t := tier
			var label := "Propose" if tier == 0 else ("With a modest gift" if tier == 1 else "With a generous gift")
			buttons.add_child(UiKit.button(label, func():
				var r := Marriage.propose(Game, member_uid, cuid, t)
				notice = str(r.get("text", ""))
				UiKit.close_modal(v)
				if bool(r.get("accepted", false)):
					Sound.sfx("event_fanfare", 0.8, 0.0, 0)
					Game.save_game_async()
				_refresh(), "Row" if tier > 0 else "", 230))
	v.add_child(UiKit.button("Close", func(): UiKit.close_modal(v), "Row", 120))

# ------------------------------------------------------------------ tree control
class FamilyTree:
	extends Control
	var host
	var rows_box: VBoxContainer
	var nodes := {}      # uid -> Control
	var data := {}

	func build(d: Dictionary, ruler_uid: String) -> void:
		data = d
		size_flags_horizontal = SIZE_EXPAND_FILL
		rows_box = VBoxContainer.new()
		rows_box.add_theme_constant_override("separation", 46)
		rows_box.set_anchors_preset(PRESET_TOP_WIDE)
		add_child(rows_box)
		var gens := {}
		for uid in d:
			var g := int(d[uid]["gen"])
			if not gens.has(g): gens[g] = []
			gens[g].append(uid)
		var keys: Array = gens.keys(); keys.sort()
		for g in keys:
			if g == 9:
				var cap := UiKit.label("Wider family", "Muted"); cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				rows_box.add_child(cap)
			var row := HFlowContainer.new()
			row.alignment = FlowContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("h_separation", 18)
			row.add_theme_constant_override("v_separation", 18)
			rows_box.add_child(row)
			for uid in _ordered(gens[g], ruler_uid):
				var n := _node(uid)
				nodes[uid] = n
				row.add_child(n)
		rows_box.resized.connect(_fit)
		rows_box.sort_children.connect(func(): queue_redraw())
		_fit.call_deferred()

	## Couples side by side; the ruler's couple first; children grouped by parents.
	func _ordered(uids: Array, ruler_uid: String) -> Array:
		var out: Array = []
		var used := {}
		var sorted := uids.duplicate()
		sorted.sort_custom(func(a, b):
			var ka := "%s|%03d" % [",".join(data[a]["parents"]), 200 - int(data[a]["row"].get("age", 0))]
			var kb := "%s|%03d" % [",".join(data[b]["parents"]), 200 - int(data[b]["row"].get("age", 0))]
			if a == ruler_uid: return true
			if b == ruler_uid: return false
			return ka < kb)
		for uid in sorted:
			if used.has(uid): continue
			used[uid] = true
			if bool(data[uid]["row"].get("married_in", false)) and uids.has(data[uid]["spouse_uid"]) and not used.has(data[uid]["spouse_uid"]):
				out.append(data[uid]["spouse_uid"]); used[data[uid]["spouse_uid"]] = true
			out.append(uid)
			var sp: String = data[uid]["spouse_uid"]
			if uids.has(sp) and not used.has(sp): out.append(sp); used[sp] = true
		return out

	func _node(uid: String) -> Control:
		var d: Dictionary = data[uid]
		var row: Dictionary = d["row"]
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 214)
		b.focus_mode = FOCUS_NONE
		b.theme_type_variation = "Row"
		var heir_uid := str(Dynasty.selected_heir(Game).get("person_uid", ""))
		var is_ruler: bool = uid == host.ruler_uid
		var border := UiTheme.BRASS if is_ruler else (Color("b7dc8f") if uid == heir_uid else UiTheme.BORDER)
		for s in ["normal", "hover", "pressed"]:
			var sb := UiTheme.sb(UiTheme.WOOD_3.lightened(0.06 if s == "hover" else 0.0), border, 3 if is_ruler or uid == heir_uid else 2, 10, 6, 6)
			b.add_theme_stylebox_override(s, sb)
		var v := VBoxContainer.new(); v.set_anchors_preset(PRESET_FULL_RECT); v.mouse_filter = MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		b.add_child(v)
		var p := Portrait.new(); p.custom_minimum_size = Vector2(0, 118); p.mouse_filter = MOUSE_FILTER_IGNORE
		p.set_spec(Dynasty.portrait_for(Game, row)); v.add_child(p)
		var first := str(row.get("name", "?")).split(" ")[0]
		var nm := _l(first, 20, UiTheme.BRASS if is_ruler else UiTheme.LIGHT, true); v.add_child(nm)
		var rel := str(d["rel"])
		if uid == heir_uid and not is_ruler: rel += " · Heir"
		v.add_child(_l(rel, 16, UiTheme.INK_SOFT))
		var status := "married" if bool(row.get("married", false)) or bool(row.get("married_in", false)) else ("betrothed" if bool(row.get("betrothed", false)) else ("can marry" if bool(row.get("can_betroth", false)) else ""))
		if str(row.get("state", "")) == "company": status = "with the army"
		if str(row.get("state", "")) == "captive": status = "held captive"
		v.add_child(_l("%d%s" % [int(row.get("age", 0)), (" · " + status) if status != "" else ""], 16, UiTheme.GOOD if status == "can marry" else (UiTheme.BAD if status == "held captive" else UiTheme.INK)))
		b.tooltip_text = "%s · %s" % [row.get("name", "?"), host._status_text(row)]
		b.pressed.connect(func(): host.open_person(d))
		return b

	func _l(t: String, size: int, col: Color, bold := false) -> Label:
		var l := Label.new(); l.text = t; l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; l.clip_text = true
		l.mouse_filter = MOUSE_FILTER_IGNORE
		if bold: l.add_theme_font_override("font", UiTheme.bold())
		return l

	func _fit() -> void:
		rows_box.size.x = size.x
		custom_minimum_size.y = rows_box.get_combined_minimum_size().y + 10
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED and rows_box != null: _fit()

	## Lines: couples joined side to side; from each couple (or single parent) down to their children.
	func _draw() -> void:
		var gold := Color(UiTheme.BORDER, 0.9)
		var me := get_global_rect().position
		for uid in nodes:
			var n: Control = nodes[uid]
			var r := Rect2(n.get_global_rect().position - me, n.size)
			var sp: String = data[uid]["spouse_uid"]
			if nodes.has(sp) and uid < sp:
				var r2 := Rect2((nodes[sp] as Control).get_global_rect().position - me, (nodes[sp] as Control).size)
				var y := r.position.y + r.size.y * 0.42
				var a := Vector2(r.end.x if r.position.x < r2.position.x else r.position.x, y)
				var c := Vector2(r2.position.x if r.position.x < r2.position.x else r2.end.x, y)
				draw_line(a, c, UiTheme.BRASS, 3.0)
			for puid in data[uid]["parents"]:
				if not nodes.has(puid): continue
				var pr := Rect2((nodes[puid] as Control).get_global_rect().position - me, (nodes[puid] as Control).size)
				var start := Vector2(pr.get_center().x, pr.end.y)
				var psp: String = data[puid]["spouse_uid"]
				if nodes.has(psp):
					var sr := Rect2((nodes[psp] as Control).get_global_rect().position - me, (nodes[psp] as Control).size)
					start = Vector2((pr.get_center().x + sr.get_center().x) * 0.5, maxf(pr.end.y, sr.end.y))
				var end := Vector2(r.get_center().x, r.position.y)
				var mid := (start.y + end.y) * 0.5
				draw_polyline(PackedVector2Array([start, Vector2(start.x, mid), Vector2(end.x, mid), end]), gold, 2.0)
				break
