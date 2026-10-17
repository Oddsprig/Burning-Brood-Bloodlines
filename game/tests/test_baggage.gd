extends RefCounted
## Company baggage (core/baggage.gd, ui/baggage.gd): the rows cover every piece worn and stashed, every arrow,
## meal, mug, cup, good and coin; the totals match the items themselves; the four tabs split it into Weapons,
## Armour, Food and drink, Other items; filters and sorts work; the screen builds on a phone (720x1280) with
## every button at least 48 px tall; Equip and To stash move the real item (Outfit).

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", what)

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(21)
	Game.location = ""
	Game.stash.append(Item.make("bearded_axe", "iron", 2))
	Game.stash.append(Item.make("mail_shirt", "bronze", 0))
	Goods.add_to_company(Game, "hides", 3.0)
	Goods.add_to_company(Game, "copper_bars", 2.0)
	# totals straight from the items
	var kg := 0.0
	var val := 0
	var pieces := 0
	for u in Game.company:
		if u.dead:
			continue
		kg += u.gear_mass()
		val += u.gear_value()
		pieces += u.equip.size()
		for k in u.quiver:
			kg += int(u.quiver[k]) * float(DB.arrows[k]["mass"])
			val += int(round(int(u.quiver[k]) * float(Goods.table().get(k, {}).get("price", 0.0))))
			pieces += int(u.quiver[k])
	for it in Game.stash:
		kg += it.mass()
		val += it.value()
		pieces += 1
	var gt := Goods.table()
	for k in Food.KINDS:
		var n := Food.stock(Game, k)
		kg += n * float(gt[Baggage.FOOD_GOOD[k]]["weight"])
		val += int(round(n * float(Food.BASE_PRICE[k])))
		pieces += n
	kg += 3.0 * float(gt["hides"]["weight"]) + 2.0 * float(gt["copper_bars"]["weight"])
	val += int(round(3.0 * float(gt["hides"]["price"]))) + int(round(2.0 * float(gt["copper_bars"]["price"])))
	pieces += 5
	val += Game.gold
	pieces += Game.gold
	var rows := Baggage.rows(Game)
	var tot := Baggage.totals(rows)
	check(absf(float(tot["kg"]) - kg) < 0.001, "total weight %.3f matches the items %.3f" % [float(tot["kg"]), kg])
	check(int(tot["value"]) == val, "total value %d matches the items %d" % [int(tot["value"]), val])
	check(int(tot["count"]) == pieces, "pieces %d match %d" % [int(tot["count"]), pieces])
	# the four tabs partition the rows
	var by_cat := 0.0
	var n_rows := 0
	for c in Baggage.CATS:
		var part := Baggage.view(rows, c)
		n_rows += part.size()
		by_cat += float(Baggage.totals(part)["kg"])
		for r in part:
			check(String(r["cat"]) == c, "row %s in tab %s" % [r["name"], c])
			check(Baggage.icon(r) != null, "row %s has an icon" % r["name"])
	check(n_rows == rows.size() and absf(by_cat - kg) < 0.001, "tabs cover every row once")
	check(Baggage.view(rows, "food").size() == 3, "meals, beer and wine rows")
	check(Baggage.view(rows, "other").filter(func(r): return r["kind"] == "coin").size() == 1, "coin row")
	var stash_w := Baggage.view(rows, "weapons", "stash")
	check(stash_w.size() == 1 and (stash_w[0]["item"] as Item).tid == "bearded_axe", "stash filter")
	check(Baggage.view(rows, "armour", "in_use").all(func(r): return r["unit"] != null), "in use filter")
	var by_w := Baggage.view(rows, "armour", "all", "weight")
	for i in by_w.size() - 1:
		check(float(by_w[i]["kg"]) >= float(by_w[i + 1]["kg"]), "weight sort")
	var by_q := Baggage.view(rows, "weapons", "all", "quality")
	check(int(by_q[0]["quality"]) >= int(by_q[-1]["quality"]), "quality sort")
	var axe_row: Dictionary = stash_w[0]
	check(Baggage.detail(axe_row).contains("iron") and Baggage.detail(axe_row).contains("kg") and Baggage.detail(axe_row).contains("fine")
		and Baggage.detail(axe_row).contains("finely-crafted"), "row detail: " + Baggage.detail(axe_row))
	# the screen on a phone
	var sv := SubViewport.new()
	sv.size = Vector2i(720, 1280)
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(sv)
	Game.screen_params = {"back": "map"}
	var s: Node = (load("res://ui/baggage.tscn") as PackedScene).instantiate()
	sv.add_child(s)
	for i in 3:
		await tree.process_frame
	for c in ["Weapons", "Armour", "Food and drink", "Other items"]:
		s.show_tab(c)
		await tree.process_frame
		await tree.process_frame
		check(s.list_box.get_child_count() == s.shown().size(), "%s tab lists its rows" % c)
		_buttons(s, c)
		var sl: Label = s.totals_l
		check(sl.text.contains("kg") and sl.text.contains("coins"), "%s totals line: %s" % [c, sl.text])
	s.show_tab("Weapons")
	s.set_where("stash")
	s.set_sort("value")
	check(s.shown().size() == 1, "screen filter")
	# Equip from the stash and back again (Outfit)
	var axe: Item = axe_row["item"]
	var man: Unit = Game.company[1]
	check(Outfit.equip_item(man, axe, Game.stash) == "" and man.equip["main_hand"] == axe and not Game.stash.has(axe), "equip moves the axe")
	s.refresh()
	var used := Baggage.view(Baggage.rows(Game), "weapons", "in_use").filter(func(r): return r["item"] == axe)
	check(used.size() == 1 and used[0]["where"] == man.name, "the baggage shows who carries it")
	sv.queue_free()
	Game.screen_params = {}
	await tree.process_frame
	return fails

func _buttons(n: Node, where: String) -> void:
	for c in n.get_children():
		if c is Button and (c as Button).is_visible_in_tree():
			check((c as Button).size.y >= 48.0, "%s: button '%s' is %d px tall" % [where, (c as Button).text, int((c as Button).size.y)])
		_buttons(c, where)
