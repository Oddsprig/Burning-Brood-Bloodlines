class_name RecMarket
extends RefCounted
## Records presentation only. Market stock, stored reserves and issued kit stay
## separate; every link uses the existing Records detail/navigation paths.

static func _m(value: float) -> String:
	return RecData.money(value)

static func _quality(q: int) -> String:
	if q == 0: return "ordinary"
	return String(DB.QUALITY_NAMES[q]) if q >= 0 and q < DB.QUALITY_NAMES.size() else "quality %d" % q

## Quality has its own lane. Preserve a legendary piece's real name, and use
## Item.display_name's unmarked template/material base for ordinary equipment.
static func _weapon_name(item: Item) -> String:
	if item.is_legend(): return item.display_name()
	var template := item.tmpl()
	var name := String(template.get("name", item.tid))
	return name if template.get("plain_name", false) else "%s %s" % [item.material, name]

static func market(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var food_days := RecData.days_food(t)
	var supply := TownEcon.supply_level(t, food_days)
	var food_tone := UiTheme.BAD if supply == "starving" else (UiTheme.WARN if supply == "short" else UiTheme.GOOD)
	RecKit.metrics(v, [
		{"title": "Equipment on sale", "value": str((t.get("shop", []) as Array).size()), "note": "Physical pieces on the stalls", "color": UiTheme.BLUE},
		{"title": "Stored reserve", "value": str((t.get("armory_items", []) as Array).size()), "note": "Separate from issued equipment", "color": UiTheme.COPPER},
		{"title": "Town food", "value": "%s days" % RecKit.num(food_days), "note": "At the town's food use", "color": food_tone}])
	var c := RecKit.card(v, "Market by kind")
	var rows := []
	for cat in RecTown.CATS:
		var ck := String(cat[0])
		var title := String(cat[1])
		var gs := RecTown._goods_in(ck)
		var totals := RecData.market_totals(e, gs)
		var stock := int(totals[0])
		var demand := float(totals[1])
		var mover := ""
		var move := 0.0
		for g in gs:
			var old: Variant = RecData.price_week_ago(e, g)
			if old != null and float(old) > 0.0:
				var change := RecData.price(t, g) / float(old) - 1.0
				if absf(change) > absf(move): move = change; mover = String(g)
		var move_text := "%s %+d%%" % [RecData.good_name(e, mover), int(round(move * 100.0))] if mover != "" else "—"
		rows.append({"values": [title, str(stock), RecKit.num(stock / demand) if demand > 0.0 else "—",
			{"text": move_text, "color": UiTheme.BAD if move > 0.05 else (UiTheme.GOOD if move < -0.05 else UiTheme.INK_SOFT)}],
			"tap": func(): scr.page(title, func(b): _goods_page(scr, t, e, ck, b))})
		if ck == "raw":
			var week := RecData.animals_week(e)
			var offered := 0; var sold := 0; var head := 0
			for n in week.get("offered", {}).values(): offered += int(n)
			for n in week.get("sold", {}).values(): sold += int(n)
			for n in RecData.herds(e).values(): head += int(n)
			rows.append({"values": ["Live animals", str(head), "—", "%d offered · %d sold" % [offered, sold]],
				"tap": func(): scr.page("Raw", func(b): _goods_page(scr, t, e, "raw", b))})
	RecKit.grid(c, ["Kind", "Stock units", "Market days", "Week record"], rows, [1.5, 0.8, 0.8, 2.1])
	arms_grid(scr, t, e, v)

static func _goods_page(scr, t: Dictionary, e: Dictionary, cat: String, box: VBoxContainer) -> void:
	RecTown._goods_page(scr, t, e, cat, box)
	_compact_goods(box)

static func _compact_goods(node: Node) -> void:
	if node is RecTable:
		var table := node as RecTable
		if not table._col("good").is_empty():
			table.display_cells([{"k": "good", "t": "Good", "w": 2.2},
				{"k": "price", "t": "Coins", "format": func(x): return _m(float(x))},
				{"k": "stock", "t": "Stock"}, {"k": "days", "t": "Days", "format": func(x): return RecKit.num(float(x)) if x != null else "—"},
				{"k": "chg", "t": "7-day %", "format": func(x): return "%+d%%" % int(round(float(x))) if x != null else "—"}])
		elif not table._col("kind").is_empty():
			table.display_cells([{"k": "kind", "t": "Animal", "w": 1.8}, {"k": "head", "t": "Head"},
				{"k": "price", "t": "Coins", "format": func(x): return _m(float(x))}, {"k": "off", "t": "Offered"}, {"k": "sold", "t": "Sold"}])
	for child in node.get_children(): _compact_goods(child)

static func arms_grid(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var c := RecKit.card(v, "Equipment on the market", "Physical pieces by material and quality. Average buying price in coins.")
	var cells := {}; var mats := []; var qualities := [0, 1, 2, 3, 4, 5]
	for it in t.get("shop", []):
		var mat := String(it.material); var q := int(it.quality)
		if not mats.has(mat): mats.append(mat)
		if not qualities.has(q): qualities.append(q)
		var key := "%s|%d" % [mat, q]
		var cell: Array = cells.get(key, [0, 0.0])
		cell[0] = int(cell[0]) + 1
		cell[1] = float(cell[1]) + float(Market.price(t, it))
		cells[key] = cell
	mats.sort(); qualities.sort()
	if mats.is_empty():
		RecKit.line(c, "The stalls are bare.", "Muted")
	else:
		var tools := UiKit.hbox(8)
		c.add_child(tools)
		tools.add_child(UiKit.label("Material", "Small"))
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(180, UiKit.touch_min(48))
		picker.add_theme_font_size_override("font_size", UiTheme.MOBILE_FONT_SIZE if UiTheme.is_mobile() else 18)
		picker.add_item("All materials")
		for mat in mats: picker.add_item(String(mat).capitalize())
		tools.add_child(picker)
		var body := UiKit.vbox(2)
		c.add_child(body)
		_draw_quality(body, cells, mats, qualities)
		picker.item_selected.connect(func(index: int):
			UiKit.clear(body)
			_draw_quality(body, cells, mats if index == 0 else [mats[index - 1]], qualities))
	_armory(scr, t, e, v)

static func _draw_quality(parent: Control, cells: Dictionary, mats: Array, qualities: Array) -> void:
	var rows := []
	for mat in mats:
		for q in qualities:
			var cell: Array = cells.get("%s|%d" % [mat, q], [0, 0.0])
			var n := int(cell[0])
			if n <= 0: continue
			rows.append({"values": [String(mat).capitalize(), _quality(q).capitalize(),
				{"text": str(n), "color": UiTheme.BLUE}, RecKit.num(float(cell[1]) / n)]})
	RecKit.grid(parent, ["Material", "Quality", "Count", "Avg coins"], rows, [1.3, 2.0, 0.6, 1.0])

static func _armory(_scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var c := RecKit.card(v, "Stored armory reserve", "%s× supported troop equipment, beyond issued kit. Internal supply is checked every %d days." % [
		RecKit.num(ArmsTrade.RESERVE_MULTIPLIER), ArmsTrade.SUPPLY_EVERY])
	# Read the real containers directly. ArmsTrade.armory() initializes a missing
	# container; a presentation read must not create it on a legacy town.
	var have := ArmsTrade.class_counts(t.get("armory_items", []))
	var target: Dictionary = e.get("arms_tgt", {})
	var classes := {}
	for key in have: classes[key] = true
	for key in target: classes[key] = true
	var keys: Array = classes.keys(); keys.sort()
	if keys.is_empty(): RecKit.line(c, "Empty; no reserve target recorded.", "Muted")
	var stored_roles := ArmsTrade.role_counts(have)
	var target_roles := ArmsTrade.role_counts(target)
	var roles := {}
	for key in stored_roles: roles[key] = true
	for key in target_roles: roles[key] = true
	var role_keys: Array = roles.keys(); role_keys.sort()
	for role in role_keys:
		var label := "Melee weapons" if role == "main_hand" else ("Bows" if role == "ranged" else String(role).replace("_", " ").capitalize())
		RecKit.meter(c, label, float(stored_roles.get(role, 0)), float(target_roles.get(role, 0)), "", UiTheme.COPPER)
	if not keys.is_empty():
		RecKit.disclosure(c, "Reserve by equipment class", func(b):
			var rows := []
			for key in keys:
				rows.append({"values": [ArmsTrade.cls_word(key).capitalize(), str(int(have.get(key, 0))), str(int(target.get(key, 0))),
					str(int(e.get("arms_short", {}).get(key, 0))), str(int(e.get("arms_sd", {}).get(key, 0)))]})
			RecKit.grid(b, ["Equipment", "Stored", "Target", "Short", "Short days"], rows, [2.0, 1.0, 1.0, 1.0, 1.0]))
	var arrow_have := ArmsTrade.arrow_stock(t)
	var arrow_target := int(e.get("arrow_reserve", 0))
	if arrow_have > 0 or arrow_target > 0:
		RecKit.meter(c, "Stored arrows", arrow_have, arrow_target, "", UiTheme.BLUE)
	RecKit.disclosure(c, "Armory log", func(b):
		var log := ArmsTrade.armory_log(t)
		if log.is_empty(): RecKit.line(b, "Nothing recorded.", "Muted")
		for line in log: RecKit.line(b, String(line), "Small"))

static func garrison(scr, t: Dictionary, e: Dictionary, v: VBoxContainer) -> void:
	var tid := String(t["id"])
	var wb := Militia.band_of(Game, tid)
	var units: Array = TownDefence.garrison(Game, tid)
	var st := RecData.stats(e)
	var tier := Army.town_tier(t)
	var bill := Army.town_bill(Game, t)
	var militia_n := Militia.units_of(Game, tid).size()
	var guard_n := TownDefence.guards(Game, tid).size()
	var status := "mustered" if wb.get("mustered", false) else ("drilling" if wb.get("drill_today", false) else "at civilian work")
	RecKit.metrics(v, [
		{"title": "Defenders", "value": str(units.size()), "note": "%d militia · %d guards" % [militia_n, guard_n], "color": UiTheme.BLUE},
		{"title": "Militia bill / day", "value": _m(bill), "note": "Militia's existing pay bill", "color": UiTheme.COPPER},
		{"title": "Treasury pay days", "value": str(int(RecData.treasury(e) / bill)) if bill > 0.0 else "No bill", "note": "Treasury divided by militia bill", "color": (UiTheme.BAD if RecData.treasury(e) < bill else UiTheme.BLUE) if bill > 0.0 else UiTheme.INK_SOFT}])
	RecKit.notice(v, "Civilian militia: %s" % status)
	# Keep the original roster data contract and lazy person lookups. This must
	# remain the first RecTable in Garrison for existing navigation/tests.
	var rows := []
	var view := RecTown._records_read(t, e)
	for u in units:
		var uu: Unit = u
		var rt := Army.rank_title(uu)
		var roster := func(): return Persons.roster_row(view, uu, "militia")
		var it2: Variant = uu.equip.get("main_hand", uu.equip.get("ranged", null))
		var sk := String(DB.weapons.get(it2.tid, {}).get("skill", "")) if it2 != null else ""
		var lvl := int(uu.skills.get(sk, 0)) if sk != "" else 0
		rows.append({"name": uu.name, "rank": rt, "rk": uu.rank, "age": func(): return int(roster.call()["age"]), "skill": lvl,
			"years": func(): return float(roster.call()["years_served"]), "pay": snappedf(uu.last_pay, 0.01), "renown": float(uu.renown),
			"_l": "%s %s" % [rt.capitalize(), uu.name], "_r": "%s a day" % _m(snappedf(uu.last_pay, 0.01)),
			"_d": func():
				var rr: Dictionary = roster.call()
				return "the %s; age %d; %s, %s (%d)%s; %s years served; renown %d; XP to next level: %s" % [String(rr["household"]) if String(rr["household"]) != "" else "?",
					int(rr["age"]), String(rr["weapon"]), UiWords.skill_level(lvl) if sk != "" else "-", lvl, "", RecKit.num(float(rr["years_served"])),
					int(round(uu.renown)), RecKit.NT],
			"_s": uu.name, "_tap": func(): scr.open_unit(uu)})
	var tc := RecKit.card(v, "Roster")
	var table := RecTable.make([{"k": "rk", "t": "Rank", "num": true}, {"k": "name", "t": "Name"}, {"k": "age", "t": "Age", "num": true},
		{"k": "skill", "t": "Skill", "num": true}, {"k": "years", "t": "Years", "num": true}, {"k": "pay", "t": "Pay", "num": true},
		{"k": "renown", "t": "Renown", "num": true}], rows, "rk", false, [], true)
	table.display_cells([{"k": "name", "t": "Name", "w": 2.3}, {"k": "rank", "t": "Rank", "w": 1.3},
		{"k": "skill", "t": "Skill"}, {"k": "age", "t": "Age"}, {"k": "pay", "t": "Pay/day", "format": func(x): return _m(float(x))}])
	tc.add_child(table)
	for band in [wb, TownDefence.guard_band(Game, tid)]:
		if band.is_empty(): continue
		var wid := String(band["id"])
		v.add_child(RecKit.row("The band on the map", "%d men" % (band.get("units", []) as Array).size(), RecPages.force_name(band), func(): scr.open_force(wid)))
	RecKit.disclosure(v, "Pay, ranks and defence records", func(b): _defence_records(t, e, units, wb, st, tier, b))
	_issued_weapons(units, v)
	_armory(scr, t, e, v)

static func _defence_records(t: Dictionary, e: Dictionary, units: Array, wb: Dictionary, st: Dictionary, tier: String, v: VBoxContainer) -> void:
	var war := Diplomacy.enemies_at_war(Game.world, String(t.get("faction", "")))
	RecKit.grid(v, ["Record", "Value"], [
		{"values": ["Militia paid last recorded day", _m(float(st.get("militia_wages", 0.0)))]},
		{"values": ["Guards paid last recorded day", _m(float(st.get("guard_wages", 0.0)))]},
		{"values": ["Militia unpaid", str(int(st.get("militia_unpaid", 0)))]},
		{"values": ["War footing", "At war with " + ", ".join(PackedStringArray(war.map(func(x): return UiWords.faction_name(String(x))))) if not war.is_empty() else "No"]},
		{"values": ["Drill days", str(wb.get("drill_days", 0))]},
		{"values": ["Barracks beds", str(e.get("barracks_beds", 0))]}], [1.5, 2.0])
	var by_rank := {}
	for u in units:
		var rt := Army.rank_title(u)
		by_rank[rt] = int(by_rank.get(rt, 0)) + 1
	var names := Army.ranks(TownEcon.culture_of(e), tier)
	var rows := []
	for i in range(names.size() - 1, -1, -1):
		var name := String(names[i])
		rows.append({"values": [name.capitalize(), str(int(by_rank.get(name, 0))), _m(Army.wage(tier, i))]})
	RecKit.notice(v, "Defender ranks · militia base-pay reference +%s per weapon skill grade" % _m(float(Army.A().get("per_grade", 5.0))))
	RecKit.grid(v, ["Militia rank", "Defenders", "Militia base/day"], rows, [2.0, 1.0, 1.0])
	RecKit.disclosure(v, "Other records", func(b):
		var records := RecKit.card(b, "")
		for key in ["Morale", "Kit %", "Deserted this year", "Promotion tests this month", "Sleeping in barracks vs at home"]: RecKit.nt(records, key))

static func _issued_weapons(units: Array, v: VBoxContainer) -> void:
	var c := RecKit.card(v, "Issued weapons", "Held by these defenders; excluded from stored reserves. Main-hand weapon, otherwise ranged.")
	var groups := {}; var sum := 0.0; var count := 0
	for u in units:
		var item: Variant = u.equip.get("main_hand", u.equip.get("ranged", null))
		if item == null: continue
		var name := _weapon_name(item)
		var key := "%s|%d" % [name, int(item.quality)]
		var group: Dictionary = groups.get(key, {"name": name, "q": int(item.quality), "n": 0, "broken": 0})
		group["n"] = int(group["n"]) + 1
		if item.broken: group["broken"] = int(group["broken"]) + 1
		groups[key] = group
		sum += float(item.quality); count += 1
	var keys: Array = groups.keys(); keys.sort()
	var rows := []
	for key in keys:
		var group: Dictionary = groups[key]
		rows.append({"values": [String(group["name"]), _quality(int(group["q"])).capitalize(), str(int(group["n"])),
			{"text": str(int(group["broken"])), "color": UiTheme.BAD if int(group["broken"]) > 0 else UiTheme.INK_SOFT}]})
	if rows.is_empty(): RecKit.line(c, "No weapons equipped.", "Muted")
	else: RecKit.grid(c, ["Weapon", "Quality", "Issued", "Broken"], rows, [2.8, 1.5, 0.7, 0.7])
	var average := RecKit.line(c, "Average quality: %.1f" % (sum / count) if count > 0 else "Average quality: —", "Small")
	average.tooltip_text = "0 ordinary · 1 well-crafted · 2 finely-crafted · 3 superior · 4 exceptional · 5 masterful · 6 legendary"
