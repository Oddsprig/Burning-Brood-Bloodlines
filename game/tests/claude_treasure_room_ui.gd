extends RefCounted
## Player hoard: rows, totals, a sale that raises the purse. Another house is read-only.
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL treasure room: ", label)

func labels(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text + "\n"
	if node is Button:
		text += (node as Button).text + "\n"
	for child in node.get_children():
		text += labels(child)
	return text

func buttons_named(node: Node, text: String) -> Array:
	var out: Array = []
	if node is Button and (node as Button).text == text:
		out.append(node)
	for child in node.get_children():
		out.append_array(buttons_named(child, text))
	return out

func buy(uid: String, args: Dictionary) -> bool:
	var quote: Dictionary = CourtEvents.preview(Game, uid, "treasure", args)
	if not quote.get("ok", false):
		check(false, "buy quote %s: %s" % [str(args.get("category", "")), str(quote.get("reason", ""))])
		return false
	var held: Dictionary = CourtEvents.hold(Game, uid, "treasure", args, quote)
	check(held.get("ok", false), "bought " + str(args.get("category", "")))
	return bool(held.get("ok", false))

func run(tree: SceneTree) -> int:
	if not await DevTools.start_world(tree, "user://claude_treasure_room_ui.json"):
		check(false, "start world")
		print("treasure room: %d checks, %d failures" % [checks, failures])
		return failures
	var uid := ""
	for choice: Dictionary in Dynasty.choices(Game):
		Game.world["player_house"] = {}
		if not HouseOnboarding.begin(Game, str(choice["town_id"]), str(choice["household_uid"])).get("ok", false):
			continue
		var trial: Dictionary = Dynasty._household(Game, str(choice["household_uid"]))
		if trial.is_empty():
			continue
		trial["family"]["purse"] = 5000000.0
		var quote: Dictionary = CourtEvents.preview(Game, str(choice["household_uid"]), "treasure", {"category": "gold", "quantity": 1})
		if quote.get("ok", false):
			uid = str(choice["household_uid"])
			break
	check(uid != "", "player house can buy treasure")
	if uid == "":
		print("treasure room: %d checks, %d failures" % [checks, failures])
		return failures
	var loc: Dictionary = Dynasty._household(Game, uid)
	var family: Dictionary = loc["family"]
	var econ: Dictionary = loc["town"]["econ"]
	family["purse"] = 5000000.0
	var market: Dictionary = econ["biz"][int(econ["mkt"])]
	market["till"] = 1000000.0
	var gem := str(Dragons.catalogs()["gems"][0]["id"])
	var matched := false
	for dragon: Dictionary in Game.world.get("dragons", {}).get("records", {}).values():
		if dragon.get("alive", false):
			dragon["owner_household_uid"] = uid
			dragon["gem_id"] = gem
			matched = true
			break
	check(buy(uid, {"category": "gold", "quantity": 2}), "gold hoard row bought")
	check(buy(uid, {"category": "gems", "gem_id": gem, "quantity": 1}), "gem hoard row bought")
	var rows: Array = CourtEvents.hoard_view(Game, uid)
	var hoard_value := 0
	var prestige := 0.0
	var gold_row: Dictionary = {}
	var gem_row: Dictionary = {}
	for row: Dictionary in rows:
		hoard_value += int(row["value"])
		prestige += float(row["prestige"])
		if str(row.get("category", "")) == "gold":
			gold_row = row
		if str(row.get("category", "")) == "gems":
			gem_row = row
	check(not gold_row.is_empty() and int(gold_row["quantity"]) == 2, "gold row quantity 2")
	check(not gem_row.is_empty(), "gem row present")
	if matched and not gem_row.is_empty():
		check(bool(gem_row.get("gem_match", false)), "gem matches a house dragon")
	var purse_before := float(family["purse"])
	var sale := int(gold_row.get("sale_value", 0))
	Game.screen_params = {"back": "house", "back_params": {"back": "map"}, "household_uid": uid}
	var page: TreasureRoom = (load("res://ui/treasure_room.tscn") as PackedScene).instantiate()
	# The runner may still be inside _ready, which blocks add_child on the root.
	tree.root.add_child.call_deferred(page)
	for _i in 6:
		await tree.process_frame
	var shown := labels(page)
	check(shown.contains("Gold"), "gold category shown")
	check(shown.contains("Gems") or shown.contains("Ruby"), "gem category shown")
	var hv: Label = page.find_child("HoardValue", true, false)
	var purse_label: Label = page.find_child("PurseTotal", true, false)
	var prestige_label: Label = page.find_child("TreasurePrestige", true, false)
	check(hv != null and hv.text.contains(UiKit.thousands(hoard_value)), "hoard value total shown")
	check(purse_label != null and purse_label.text.contains(UiKit.thousands(int(floor(purse_before)))), "purse total shown")
	check(prestige_label != null and prestige_label.text.contains("%.2f" % prestige), "treasure prestige shown")
	if matched:
		check(shown.contains("Matches a dragon"), "matching gem is marked")
	var sell_btn: Button = null
	for button in buttons_named(page, "Sell"):
		if str(button.get_meta("treasure_id", "")) == str(gold_row.get("id", "")):
			sell_btn = button
	check(sell_btn != null, "player gold row has Sell")
	if sell_btn != null:
		sell_btn.pressed.emit()
		await tree.process_frame
		var modal := page.find_child("Modal", true, false)
		check(modal != null and labels(modal).contains(UiKit.thousands(sale)), "sell confirm shows the sale value")
		var yes: Button = null
		if modal != null:
			var found: Array = buttons_named(modal, "Sell")
			if not found.is_empty():
				yes = found[0]
		check(yes != null, "sell confirm button")
		if yes != null:
			yes.pressed.emit()
		for _i in 4:
			await tree.process_frame
	check(is_equal_approx(float(family["purse"]) - purse_before, float(sale)), "purse rose by the sale value (+%s)" % sale)
	check(labels(page).contains("Received %s coins" % UiKit.thousands(sale)), "screen shows coin received")
	page.queue_free()
	var other_uid := ""
	for choice: Dictionary in Dynasty.choices(Game):
		if str(choice["household_uid"]) == uid:
			continue
		var other_loc: Dictionary = Dynasty._household(Game, str(choice["household_uid"]))
		if other_loc.is_empty():
			continue
		other_loc["family"]["purse"] = 5000000.0
		var other_quote: Dictionary = CourtEvents.preview(Game, str(choice["household_uid"]), "treasure", {"category": "silver", "quantity": 1})
		if other_quote.get("ok", false):
			CourtEvents.hold(Game, str(choice["household_uid"]), "treasure", {"category": "silver", "quantity": 1}, other_quote)
			other_uid = str(choice["household_uid"])
			break
		if other_uid == "":
			other_uid = str(choice["household_uid"])
	check(other_uid != "", "another house exists")
	if other_uid != "":
		Game.screen_params = {"household_uid": other_uid, "read_only": true, "back": "court"}
		var other: TreasureRoom = (load("res://ui/treasure_room.tscn") as PackedScene).instantiate()
		tree.root.add_child(other)
		for _i in 4:
			await tree.process_frame
		check(buttons_named(other, "Sell").is_empty(), "other house has no Sell buttons")
		check(other.find_child("BuyTreasureButton", true, false) == null, "other house has no Buy treasure")
		check(labels(other).contains("Read only"), "other house says read only")
		other.queue_free()
	Game.screen_params = {"back": "map"}
	var house: Control = (load("res://ui/house.tscn") as PackedScene).instantiate()
	tree.root.add_child(house)
	for _i in 4:
		await tree.process_frame
	var treasure_button: Button = house.find_child("TreasureRoomButton", true, false)
	check(treasure_button != null and treasure_button.text == "Treasure room", "house screen TreasureRoomButton")
	if treasure_button != null:
		treasure_button.pressed.emit()
		check(Game._active_screen == "treasure" and Game.screen_params.get("back") == "house", "TreasureRoomButton opens the treasure screen")
	house.queue_free()
	Game.screen_params = {"back": "map"}
	var court: Control = (load("res://ui/court.tscn") as PackedScene).instantiate()
	tree.root.add_child(court)
	for _i in 4:
		await tree.process_frame
	court.call("_open_targets")
	await tree.process_frame
	var other_button: Button = court.find_child("TreasureRoomOtherButton", true, false)
	check(other_button != null and other_button.text == "Treasure room", "court lists TreasureRoomOtherButton")
	if other_button != null:
		other_button.pressed.emit()
		check(bool(Game.screen_params.get("read_only", false)), "other-house button opens read-only")
		check(str(Game.screen_params.get("household_uid", "")) != uid, "other-house button is not the player hoard")
	court.queue_free()
	print("treasure room: %d checks, %d failures" % [checks, failures])
	return failures
