class_name ArmyPanel
extends RefCounted
## Economy spec 2, section 6: a faction's rank tree (names and counts against the caps, top-down; the status
## ranks below), its wage bill and days of pay, the latest promotions and successions. Tap an officer for his
## record and his family. Opened from the map's force panel and the relations screen. Read-only.

static func open(host: Control, fid: String) -> void:
	var v := UiKit.modal(host, "Ranks of %s" % CampaignWorld.faction_the(fid).trim_prefix("the "), 760)
	var sc := UiKit.scroll()
	sc.custom_minimum_size = Vector2(0, minf(430, maxf(100, host.get_viewport_rect().size.y - 160)))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(sc)
	var list := UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var w: Dictionary = Game.world
	var fac: Dictionary = w["factions"].get(fid, {})
	var cul := Army.cul_of_faction(fid)
	var n := Army.members(Game, fid).size()
	var bill := Army.bill(Game, fid)
	var dleft := Army.days_of_pay(Game, fid)
	list.add_child(UiKit.label("%d men under arms. Wage bill %d coins a day; war chest %d coins (%s of pay); loot chest %d. Rank rule: %s." % [n, int(round(bill)),
		int(fac.get("treasury", 0.0)), ("%d days" % int(dleft)) if dleft < 9999.0 else "no bill", int(fac.get("loot", 0.0)), String(cul.get("rank_rule", ""))], "", true))
	for row in Army.tree_rows(Game, fid):
		var cap := int(row["cap"])
		var head := "%s: %d%s" % [String(row["title"]).capitalize(), int(row["count"]), (" of %d" % cap) if cap >= 0 else ""]
		list.add_child(UiKit.label(head, "H2", true))
		if not (row["officers"] as Array).is_empty():
			var fl := UiKit.flow(6)
			for u in row["officers"]:
				var uu: Unit = u
				fl.add_child(UiKit.button("%s (renown %d)" % [uu.name, int(round(uu.renown))], func(): record(host, uu), "Row"))
			list.add_child(fl)
	var hist: Array = Army.rec(w, fid).get("hist", [])
	if not hist.is_empty():
		list.add_child(UiKit.label("Lately", "H2"))
		for i in range(hist.size() - 1, maxi(-1, hist.size() - 7), -1):
			list.add_child(UiKit.label(String(hist[i]), "Small", true))
	var r := UiKit.hbox()
	r.add_child(UiKit.spacer())
	r.add_child(UiKit.button("Close", func(): UiKit.close_modal(v), "", 160))
	v.add_child(r)

## An officer's record and his family's.
static func record(host: Control, u: Unit) -> void:
	var lines := []
	var rt := Army.rank_title(u)
	lines.append("%s %s, %s. Age %d. Battles %d, kills %d." % [UiWords.race_name(u).capitalize(), u.title, rt if rt != "" else "soldier", u.age, u.battles, u.kills])
	lines.append_array(Renown.lines(u))
	if u.unpaid_days > 0:
		lines.append("Unpaid for %d days." % u.unpaid_days)
	var town: Dictionary = Game.world["towns"].get(u.home_town, {})
	var f := People.fam_of(town, u.family)
	if not f.is_empty():
		lines.append("Family, %s:" % town.get("name", "?"))
		lines.append_array(Families.describe(town, town["econ"], f))
	UiKit.message(host, u.name, lines)

## One line for a force panel: "Stores: 5 days. 3 men unpaid." ("" when nothing to say).
static func band_line(wb: Dictionary) -> String:
	if not Army.is_people_band(wb):
		return ""
	var parts := []
	if wb.has("stores"):
		parts.append("Stores: %d days of food" % int(Supplies.days(wb)))
	if int(wb.get("unpaid_n", 0)) > 0:
		parts.append("%d unpaid" % int(wb["unpaid_n"]))
	var offs := []
	for u in wb["units"]:
		if not u.dead and u.is_officer():
			var t := Army.rank_title(u)
			if t != "":
				offs.append("%s %s" % [t, u.name])
	if not offs.is_empty():
		parts.append("Led by " + ", ".join(PackedStringArray(offs.slice(0, 3))))
	return ". ".join(PackedStringArray(parts)) + ("." if not parts.is_empty() else "")
