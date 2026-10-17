class_name Baggage
extends RefCounted
## Everything the company carries, as rows for the baggage screen (ui/baggage.gd): gear worn by its men and
## gear in the stash, arrows in the quivers, food and drink, trade goods and coin. Read-only: the screen's
## actions call the code that already does them (Outfit.equip_item / unequip, Market.sell, Goods.sell).
##
## Row: {cat, kind ("item" | "arrow" | "food" | "good" | "coin"), id, name, qty, quality (-1 = none),
## material ("" = none), kg (all of them), value (coins, all of them), wear (-1 = none), where ("stash" or the
## man's name), unit (Unit or null), slot, item (Item or null)}.
## Weights: gear Item.mass(); arrows DB.arrows mass; named foods, drinks and goods their economy weight
## (the same rule as Supplies.company_take). Unidentified meals retain the old grain weight. Coin is not weighed.
## Values: gear Item.value(); named foods, arrows and goods their base price; unidentified meals Food.BASE_PRICE.

const CATS := ["weapons", "armour", "food", "other"]
const CAT_NAMES := {"weapons": "Weapons", "armour": "Armour", "food": "Food and drink", "other": "Other items"}
const WEAR_WORDS := ["fine", "worn", "battered", "tattered"]
const FOOD_GOOD := {"meal": "grain", "beer": "beer", "wine": "wine"}
const FOOD_NAMES := {"meal": "meals", "beer": "beer (mugs)", "wine": "wine (cups)"}
const SORTS := ["name", "weight", "value", "quality"]
const WHERE := ["all", "in_use", "stash"]

static func cat_of_item(it: Item) -> String:
	return "weapons" if it.is_weapon() or DB.is_bow(it.tid) else "armour"

## Every row, in a stable order: men's gear (company order, slot order), arrows, stash, food, goods, coin.
static func rows(game) -> Array:
	var out := []
	for u in game.company:
		if u.dead:
			continue
		for slot in DB.EQUIP_SLOTS:
			if u.equip.has(slot):
				out.append(_item_row(u.equip[slot], u, slot))
		for k in u.quiver:
			var n := int(u.quiver[k])
			if n > 0:
				out.append(_arrow_row(String(k), n, u))
	for it in game.stash:
		out.append(_item_row(it, null, ""))
	var gt: Dictionary = Goods.table()
	for food in Food.packed_food(game):
		var n := int(food["qty"])
		if n <= 0:
			continue
		var good := String(food["good"])
		var legacy := good == ""
		var data: Dictionary = gt.get("grain" if legacy else good, {})
		out.append({"cat": "food", "kind": "food", "id": "meal" if legacy else good, "name": String(food["name"]), "qty": n, "quality": -1, "material": "",
			"kg": n * float(data.get("weight", 0.5)), "value": int(round(n * (float(Food.BASE_PRICE["meal"]) if legacy else float(data.get("price", 0.0))))),
			"wear": -1, "where": "stash", "unit": null, "slot": "", "item": null})
	for k in ["beer", "wine"]:
		var n := Food.stock(game, k)
		if n <= 0:
			continue
		out.append({"cat": "food", "kind": "food", "id": k, "name": FOOD_NAMES[k], "qty": n, "quality": -1, "material": "",
			"kg": n * float(gt.get(FOOD_GOOD[k], {}).get("weight", 0.5)), "value": int(round(n * float(Food.BASE_PRICE[k]))),
			"wear": -1, "where": "stash", "unit": null, "slot": "", "item": null})
	var cg := Goods.company_goods(game)
	var gids: Array = cg.keys()
	gids.sort()
	for g in gids:
		var q := float(cg[g])
		if q < 0.01:
			continue
		var t: Dictionary = gt.get(g, {})
		out.append({"cat": "other", "kind": "good", "id": String(g), "name": Goods.good_name(g), "qty": int(floor(q + 0.0001)), "quality": -1,
			"material": "", "kg": q * float(t.get("weight", 0.5)), "value": int(round(q * float(t.get("price", 0.0)))),
			"wear": -1, "where": "stash", "unit": null, "slot": "", "item": null})
	if int(game.gold) > 0:
		out.append({"cat": "other", "kind": "coin", "id": "coin", "name": "coins", "qty": int(game.gold), "quality": -1, "material": "",
			"kg": 0.0, "value": int(game.gold), "wear": -1, "where": "purse", "unit": null, "slot": "", "item": null})
	return out

static func _item_row(it: Item, u: Unit, slot: String) -> Dictionary:
	return {"cat": cat_of_item(it), "kind": "item", "id": it.tid, "name": it.display_name(), "qty": 1, "quality": it.quality,
		"material": it.material, "kg": it.mass(), "value": it.value(), "wear": it.wear,
		"where": u.name if u != null else "stash", "unit": u, "slot": slot, "item": it}

static func _arrow_row(k: String, n: int, u: Unit) -> Dictionary:
	var a: Dictionary = DB.arrows.get(k, {})
	return {"cat": "weapons", "kind": "arrow", "id": k, "name": DB.arrow_name(k) + "s", "qty": n, "quality": -1,
		"material": String(a.get("tip", "wood")), "kg": n * float(a.get("mass", 0.05)),
		"value": int(round(n * float(Goods.table().get(k, {}).get("price", 0.0)))), "wear": -1,
		"where": u.name, "unit": u, "slot": "quiver", "item": null}

static func icon(r: Dictionary) -> Texture2D:
	match String(r["kind"]):
		"item": return ItemIcon.for_item(r["item"])
		"arrow": return ItemIcon.for_thing(String(r["id"]))
	return ItemIcon.for_thing(String(r["id"]))

## Rows of one category ("" = all), where ("all" | "in_use" | "stash"), sorted by "name" | "weight" | "value"
## | "quality" (heaviest, dearest and best first; then by name).
static func view(all_rows: Array, cat: String = "", where: String = "all", sort_key: String = "name") -> Array:
	var out := all_rows.filter(func(r):
		if cat != "" and String(r["cat"]) != cat:
			return false
		match where:
			"in_use": return r["unit"] != null
			"stash": return r["unit"] == null
		return true)
	out.sort_custom(func(a, b):
		match sort_key:
			"weight":
				if not is_equal_approx(float(a["kg"]), float(b["kg"])):
					return float(a["kg"]) > float(b["kg"])
			"value":
				if int(a["value"]) != int(b["value"]):
					return int(a["value"]) > int(b["value"])
			"quality":
				if int(a["quality"]) != int(b["quality"]):
					return int(a["quality"]) > int(b["quality"])
		return String(a["name"]) < String(b["name"]))
	return out

## {"kg", "value", "count"} of a list of rows (count = pieces: every arrow, meal and coin counts).
static func totals(list: Array) -> Dictionary:
	var kg := 0.0
	var v := 0
	var n := 0
	for r in list:
		kg += float(r["kg"])
		v += int(r["value"])
		n += int(r["qty"])
	return {"kg": kg, "value": v, "count": n}

## "x40, finely-crafted, copper, 2.4 kg, worn, worn by Petra Coldwater"
static func detail(r: Dictionary) -> String:
	var parts := []
	if int(r["qty"]) != 1 or String(r["kind"]) != "item":
		parts.append("x%d" % int(r["qty"]))
	if int(r["quality"]) > 0:
		parts.append(DB.QUALITY_NAMES[int(r["quality"])])
	if String(r["material"]) != "" and String(r["kind"]) == "item":
		parts.append(String(r["material"]))
	elif String(r["kind"]) == "arrow":
		parts.append("%s tips" % String(r["material"]))
	if float(r["kg"]) > 0.0:
		parts.append(UiWords.kg(float(r["kg"])))
	if int(r["wear"]) >= 0:
		parts.append(WEAR_WORDS[clampi(int(r["wear"]), 0, 3)])
	match String(r["kind"]):
		"item":
			parts.append(("worn by " + String(r["where"])) if r["unit"] != null else "in the stash")
		"arrow":
			parts.append("in %s's quiver" % String(r["where"]))
		"food":
			parts.append("in the wagons")
		"good":
			parts.append("in the wagons")
	return ", ".join(PackedStringArray(parts))
