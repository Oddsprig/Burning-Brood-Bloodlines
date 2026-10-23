class_name RecFlows
extends RefCounted
## Compact presentation of the existing world/faction trade and history records.
## Original RecWorld tables provide their rows, sorts, filters and identity links.

static func _m(value: Variant) -> String:
	return RecData.money(float(value))

static func _number(value: Variant) -> String:
	return RecKit.num(float(value)) if value != null else "-"

## Reader helpers may initialize missing legacy books; isolate only those reads.
## Navigation still receives the actual town, force, person and item identities.
static func read_world(tids: Array) -> Dictionary:
	var world := Game.world.duplicate()
	var towns: Dictionary = Game.world.get("towns", {}).duplicate()
	for tid in tids:
		var town := RecData.town(String(tid))
		if TownEcon.has_econ(town): towns[tid] = RecCivic._read_town(town, town["econ"])
	world["towns"] = towns
	return world

static func goods(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
	var categories := []
	var market_units := 0
	var grouped := {}
	for cat in RecTown.CATS: grouped[String(cat[0])] = []
	var goods_data: Dictionary = TownEcon.data()["goods"]
	for good in Goods.ids():
		var category := String(goods_data.get(good, {}).get("cat", ""))
		if grouped.has(category): (grouped[category] as Array).append(good)
	for cat in RecTown.CATS:
		var key := String(cat[0])
		var title := String(cat[1])
		var goods_in: Array = grouped[key]
		var stock := 0; var demand := 0.0
		for tid in tids:
			var totals := RecData.market_totals(RecWorld._e(tid), goods_in)
			stock += int(totals[0]); demand += float(totals[1])
		market_units += stock
		categories.append({"values": [title, {"text": str(stock), "color": UiTheme.BLUE},
			{"text": RecKit.num(stock / demand) if demand > 0.0 else "-", "color": UiTheme.COPPER}],
			"tap": func(): scr.page(title, func(box): _category(scr, tids, key, box))})
	var herds := {}; var heads := 0; var prepared := {}
	for tid in tids:
		var economy := RecWorld._e(tid)
		var town_herds := RecData.herds(economy)
		var town_total := 0
		for kind in town_herds:
			var n := int(town_herds[kind])
			herds[kind] = int(herds.get(kind, 0)) + n; heads += n
			town_total += n
		prepared[String(tid)] = {"herds": town_herds, "head": town_total, "fodder": RecData.fodder_days(economy)}
	RecKit.metrics(v, [
		{"title": "Towns covered", "value": str(tids.size()), "color": UiTheme.BLUE},
		{"title": "Market stock units", "value": str(market_units), "note": "Across the listed goods categories", "color": UiTheme.COPPER},
		{"title": "Animals in town herds", "value": str(heads), "note": "Every recorded owner", "color": UiTheme.BLUE}])
	var card := RecKit.card(v, "Goods by kind", "Market stock and days at recorded demand. Select a kind for goods and price spreads.")
	RecKit.grid(card, ["Kind", "Stock units", "Market days"], categories, [2.0, 1.0, 1.0])
	# These values belong only to this synchronous build. Detail pages and
	# disclosures still perform fresh reads when opened.
	var table := RecWorld.herds_table(scr, tids, prepared, true)
	RecKit.card(v, "Herds by town", "Select a town for its animals and owners.").add_child(table)
	RecKit.disclosure(v, "Head by animal", func(box):
		var rows := []
		var keys: Array = herds.keys(); keys.sort()
		for key in keys: rows.append({"values": [RecData.herd_word({}, key).capitalize(), str(int(herds[key]))]})
		RecKit.grid(box, ["Animal", "Head"], rows, [2, 1]))
	RecKit.disclosure(v, "Full goods record and drovers on the road", legacy)

static func _category(scr, tids: Array, category: String, v: VBoxContainer) -> void:
	var card := RecKit.card(v, "Goods and buying prices", "Stock summed over these towns; lowest and highest current price.")
	var rows := []
	for good in RecTown._goods_in(category):
		var key := String(good)
		var stock := 0; var low := INF; var high := -INF
		for tid in tids:
			stock += RecData.stock(RecWorld._e(tid), key)
			var price := RecData.price(RecWorld._t(tid), key)
			low = minf(low, price); high = maxf(high, price)
		rows.append({"values": [Goods.good_name(key).capitalize(), str(stock), _number(low), _number(high)],
			"tap": func(): scr.page(Goods.good_name(key).capitalize(), func(box): _good_towns(scr, tids, key, box))})
	RecKit.grid(card, ["Good", "Stock", "Low coins", "High coins"], rows, [2.2, 0.8, 1, 1])

static func _good_towns(scr, tids: Array, good: String, v: VBoxContainer) -> void:
	var box := RecKit.card(v, "Price and stock by town")
	RecWorld._good_towns(scr, tids, good, box)
	for child in box.get_children():
		if child is RecTable:
			child.display_cells([{"k": "name", "t": "Town", "w": 2.0}, {"k": "price", "t": "Coins", "format": _m},
				{"k": "stock", "t": "Stock"}, {"k": "days", "t": "Days", "format": _number},
				{"k": "chg", "t": "7-day %", "format": func(value): return "%+d%%" % int(round(float(value))) if value != null else "-"}])

static func _food_caravans(tids: Array) -> Array:
	var rows := []
	for band: Dictionary in RecWorld._forces(""):
		if String(band.get("kind", "")) != "caravan": continue
		var cargo: Dictionary = band.get("cargo", {}).get("goods", {})
		var food := 0
		for good in ["grain", "fruit", "meat", "beer", "wine"]: food += int(cargo.get(good, 0))
		if food <= 0: continue
		var origin := String(band.get("origin", "")); var destination := String(band.get("dest", ""))
		if not tids.has(origin) and not tids.has(destination): continue
		var start := RecWorld._t(origin); var end := RecWorld._t(destination)
		var direction := "-"
		if not start.is_empty() and not end.is_empty():
			var delta: Vector2 = (end["pos"] as Vector2) - (start["pos"] as Vector2)
			direction = ("north" if delta.y < 0 else "south") if absf(delta.y) > absf(delta.x) else ("west" if delta.x < 0 else "east")
		rows.append({"band": band, "origin": String(start.get("name", "?")), "destination": String(end.get("name", "?")), "food": food, "direction": direction})
	return rows

static func food_flows(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
	var climate_rows := []; var days_sum := 0.0; var granary := 0
	for tid in tids:
		days_sum += RecData.days_food(RecWorld._t(tid)); granary += RecData.granary(RecWorld._e(tid))
	for climate in (TownEcon.data()["climates"] as Dictionary).keys():
		var n := 0; var days := 0.0; var grain := 0
		for tid in tids:
			if String(RecWorld._e(tid).get("climate", "")) == climate:
				n += 1; days += RecData.days_food(RecWorld._t(tid)); grain += RecData.granary(RecWorld._e(tid))
		if n > 0:
			climate_rows.append({"values": [String(climate).capitalize(), str(n), {"text": RecKit.num(days / n), "color": UiTheme.COPPER}, str(grain)]})
	var caravans := _food_caravans(tids)
	var cargo_units := 0
	for route: Dictionary in caravans: cargo_units += int(route["food"])
	RecKit.metrics(v, [
		{"title": "Food days / town", "value": RecKit.num(days_sum / tids.size()) if not tids.is_empty() else "-", "note": "Average of the towns' supply days", "color": UiTheme.COPPER},
		{"title": "Public granaries", "value": str(granary), "note": "Food equivalents stored", "color": UiTheme.BLUE},
		{"title": "Food and drink on road", "value": str(cargo_units), "note": "%d caravans touching these towns" % caravans.size(), "color": UiTheme.BLUE}])
	var card := RecKit.card(v, "Supply by climate", "Food supply includes market, barns, household stores and granaries.")
	RecKit.grid(card, ["Climate", "Towns", "Avg days", "Granary food"], climate_rows, [1.7, 0.7, 1, 1.4])
	card = RecKit.card(v, "Food and drink routes", "Actual caravan cargo; select a route to open its force record.")
	var rows := []
	for route: Dictionary in caravans:
		var band: Dictionary = route["band"]; var wid := String(band["id"])
		rows.append({"origin": route["origin"], "destination": route["destination"], "food": route["food"], "direction": route["direction"],
			"_l": "%s -> %s" % [route["origin"], route["destination"]], "_r": str(route["food"]),
			"_d": "%s; %s" % [route["direction"], Caravans.cargo_text(band.get("cargo", {}))], "_tap": func(): scr.open_force(wid)})
	var table := RecTable.make([{"k": "origin", "t": "Origin"}, {"k": "destination", "t": "Destination"},
		{"k": "food", "t": "Food + drink units", "num": true}, {"k": "direction", "t": "Direction"}], rows, "food", false, [], false, RecTable.LIMIT,
		[{"k": "origin", "t": "Origin", "w": 1.8}, {"k": "destination", "t": "Destination", "w": 1.8},
		{"k": "food", "t": "Units", "w": 0.7}, {"k": "direction", "t": "Direction", "w": 1.0}])
	card.add_child(table)
	RecKit.disclosure(v, "Full food-flow record and unavailable totals", legacy)

static func _fight_log(tids: Array, faction: String) -> Array:
	var names := tids.map(func(tid): return RecData.tname(tid))
	if faction != "": names.append(CampaignWorld.faction_the(faction).trim_prefix("the "))
	var log: Array = Game.world.get("log", [])
	var lines := []
	for i in range(log.size() - 1, -1, -1):
		var line := String(log[i]); var hit := faction == ""
		if not hit:
			for name in names:
				if line.contains(String(name)): hit = true; break
		if hit:
			lines.append(line)
			if lines.size() >= 40: break
	return lines

static func fights(scr, tids: Array, fid: String, v: VBoxContainer, legacy: Callable) -> void:
	var causes := Census.causes_of(read_world(tids), tids)
	var now := int(causes["now"].get("battle", 0)); var last := int(causes["last"].get("battle", 0))
	var log := _fight_log(tids, fid)
	RecKit.metrics(v, [
		{"title": "Battle deaths", "value": str(now), "note": "This season, people of these towns", "color": UiTheme.BAD if now > 0 else UiTheme.BLUE},
		{"title": "Last season", "value": str(last), "note": "Battle deaths in the same towns", "color": UiTheme.COPPER},
		{"title": "Retained log lines", "value": str(log.size()), "note": "Latest matching records, up to 40", "color": UiTheme.BLUE}])
	var card := RecKit.card(v, "Recorded world pursuits", "All-time world totals; these are pursuits, not a count of battles in these towns.")
	var stats: Dictionary = Game.world.get("war", {}).get("stats", {})
	RecKit.grid(card, ["Outcome", "War bands"], [
		{"values": ["Ran their prey down", str(int(stats.get("caught", 0)))]},
		{"values": ["Were beaten", str(int(stats.get("beaten", 0)))]},
		{"values": ["Gave up", str(int(stats.get("gave_up", 0)))]}], [2, 1])
	card.add_child(RecKit.row("The dead in battle", str(now), "Names, ages, families and recorded fight details", func():
		scr.page("Died in battle", func(box): RecTown.dead_list(scr, Game.world, tids, "battle", box))))
	card.add_child(UiKit.button("View legendary arms", func(): scr.page("Legendary arms", func(box): RecWorld.legends_card(scr, box)), "Row"))
	card = RecKit.card(v, "Latest log", "Newest first; select a line to read the complete record.")
	var rows := []
	for line in log.slice(0, 8):
		var text := String(line)
		rows.append({"values": [text], "tap": func(): scr.page("A world record", func(box): RecKit.line(box, text))})
	if rows.is_empty(): RecKit.line(card, "Nothing on the log.", "Muted")
	else: RecKit.grid(card, ["Recorded event"], rows)
	RecKit.disclosure(v, "Full fight record, log and unavailable fields", legacy)

static func mines_land(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
	var table := RecWorld.mines_table(scr, tids, [{"k": "town", "t": "Town", "w": 1.8}, {"k": "ore", "t": "Ore", "w": 1.5},
		{"k": "rich", "t": "Richness", "format": func(value): return "%.2f" % float(value)}, {"k": "workers", "t": "Miners"}])
	var family_land := 0; var town_land := 0; var common := 0
	for tid in tids:
		# These metrics need ownership totals, not the full crop and herd account.
		var land := TownEcon.land_split(RecWorld._e(tid))
		family_land += int(land["families"]); town_land += int(land["estate"]); common += int(land["common"])
	RecKit.metrics(v, [
		{"title": "Ore deposits", "value": str(table.rows.size()), "note": "Recorded town / ore entries", "color": UiTheme.BLUE},
		{"title": "Family land", "value": "%d acres" % family_land, "color": UiTheme.COPPER},
		{"title": "Town land", "value": "%d acres" % town_land, "note": "%d acres common or unclaimed" % common, "color": UiTheme.BLUE}])
	RecKit.card(v, "Ore deposits", "Select a working mine for its business record. Richness is the recorded deposit factor.").add_child(table)
	v.add_child(UiKit.button("View land and herds", func(): scr.page("The land", func(box): RecWorld._land_card(tids, box)), "Row"))
	RecKit.disclosure(v, "Land by crop", func(box): _land_crops(tids, box))
	RecKit.disclosure(v, "Full mines and land record", legacy)

static func _land_crops(tids: Array, v: VBoxContainer) -> void:
	var family := {}; var estate := {}; var kinds := {}
	for tid in tids:
		var land := RecData.land(RecWorld._e(tid))
		for key in land["fam_crops"]:
			family[key] = int(family.get(key, 0)) + int(land["fam_crops"][key]); kinds[key] = true
		for key in land["est_crops"]:
			estate[key] = int(estate.get(key, 0)) + int(land["est_crops"][key]); kinds[key] = true
	var keys: Array = kinds.keys(); keys.sort()
	var rows := []
	for key in keys: rows.append({"values": [String(key).capitalize(), str(int(family.get(key, 0))), str(int(estate.get(key, 0)))]})
	RecKit.grid(v, ["Crop", "Family acres", "Town acres"], rows, [2, 1, 1])

static func merchants(scr, tids: Array, v: VBoxContainer, legacy: Callable) -> void:
	var table := RecWorld.merchants_table(scr, tids, [{"k": "town", "t": "Town", "w": 2.0}, {"k": "cars", "t": "Caravans", "w": 0.9},
		{"k": "gold", "t": "Coin out", "format": _m, "w": 1.3}, {"k": "out", "t": "Traded out", "format": _m, "w": 1.4}])
	var caravans := 0; var coins := 0.0; var traded := 0.0
	for row: Dictionary in table.rows:
		caravans += int(row["cars"]); coins += float(row["gold"]); traded += float(row["out"])
	RecKit.metrics(v, [
		{"title": "Caravans on road", "value": str(caravans), "note": "Originating in these towns", "color": UiTheme.BLUE},
		{"title": "Coin on road", "value": _m(coins), "note": "Actual caravan purses", "color": UiTheme.COPPER},
		{"title": "Traded out", "value": _m(traded), "note": "All-time recorded value", "color": UiTheme.BLUE}])
	RecKit.card(v, "Trade by town", "Select a town for its records. Incoming trade remains in the full row details.").add_child(table)
	var trips := RecKit.card(v, "Caravan trip receipts", "Expected and realized costs, including unsold cargo. Closed trips are kept in each town's Roads record.")
	for tid in tids:
		for wb in RecTown._caravans_of(String(tid)):
			var wid := String(wb["id"])
			var receipt: Dictionary = wb.get("receipt", {})
			if receipt.is_empty(): continue
			trips.add_child(RecKit.row(RecPages.force_name(wb), _m(float(receipt.get("realized", {}).get("net", 0.0))),
				"Expected net %s; %s" % [_m(float(receipt.get("expected", {}).get("net", 0.0))), String(wb.get("state", ""))],
				func(): scr.open_force(wid)))
	var supply := RecWorld.supply_table(scr, tids, [{"k": "town", "t": "Town", "w": 2}, {"k": "received", "t": "Received"}, {"k": "sent", "t": "Sent"}])
	RecKit.card(v, "Garrison equipment transfers", "All-time real pieces moved between own-faction armories. Issued kit is separate from reserve stock.").add_child(supply)
	RecKit.disclosure(v, "Full merchant and supply record", legacy)
