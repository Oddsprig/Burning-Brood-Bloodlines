extends RefCounted
## Native registered owners, market business and concrete Item references.
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL salvage: ", message)

## Reusable UI fixture. It creates the actual offer, not a fictional receipt.
## Call Salvage.finalize(Game, fx.result, fx.records, fx.pos) to settle it.
func fixture(till: float = 100000.0, with_buyer: bool = true, piece_count: int = 24) -> Dictionary:
	var native = NativeFixture.new(); native.fixture()
	Game.gold = 71; Game.stash.clear(); Game.world["lairs"] = {}
	var town: Dictionary = Game.world["towns"]["seat"]; var e: Dictionary = town["econ"]
	var market: Dictionary = Businesses._row(e, "market", 0, 1, TownEcon.data())
	market["name"] = "Seat exchange"; market["till"] = till
	e["mkt"] = int(market["id"]); e["price"] = {}; e["led"] = {"made": {}}; e["stats"]["sales"] = 0.0
	for good in Goods.table(): e["price"][good] = float(Goods.table()[good].get("price", 1.0))
	var items: Array = []; var records: Array = []
	for i in piece_count:
		var tid := "tunic" if i % 4 == 3 else ("seax" if i % 4 == 2 else "arming_sword")
		var material := "linen" if tid == "tunic" else ("tin" if i % 4 == 2 else "copper")
		var item: Item = Item.make(tid, material, 1)
		items.append(item); records.append(Salvage.record(item, "rags" if tid == "tunic" else "scrap", "enemy", 19 if tid == "tunic" else 0))
	if not with_buyer:
		for t in Game.world["towns"].values(): t["econ"].erase("stock")
	return {"town": town, "market": market, "items": items, "records": records, "result": {"winner": 0}, "pos": town["pos"]}

func coins() -> float:
	var total := float(Game.gold)
	for t in Game.world["towns"].values():
		var e: Dictionary = t["econ"]; total += float(e.get("treasury", 0.0))
		for f in e.get("fams", []): total += float(f.get("purse", 0.0))
		for b in e.get("biz", []): total += float(b.get("till", 0.0))
	for f in Game.world.get("factions", {}).values(): total += float(f.get("treasury", 0.0)) + float(f.get("loot", 0.0))
	for l in Game.world.get("lairs", {}).values(): total += float(l.get("gold", 0.0))
	return total

func native_state() -> String:
	return JSON.stringify(Game._save_tree()) + "|%s|%s|%s" % [str(Game.rng.state), str(Unit._next_uid), str(Item._next_uid)]

func plain(value) -> bool:
	if value is Object: return false
	if value is Dictionary:
		for key in value:
			if not plain(key) or not plain(value[key]): return false
	elif value is Array:
		for child in value:
			if not plain(child): return false
	return true

func full_and_once() -> void:
	var fx: Dictionary = fixture(); var before := coins(); var rng := Game.rng.state
	var unit_uid := Unit._next_uid; var item_uid := Item._next_uid; var mass := {}; var prices := {}
	for entry in fx["records"]:
		var it: Item = entry["item"]
		if it.material == "linen": continue
		mass[it.material] = float(mass.get(it.material, 0.0)) + it.mass()
		prices[it.material] = Goods.sell_price(fx["town"], "scrap_" + it.material)
	var receipt: Dictionary = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(receipt["rows"].size() == 24 and receipt["retained_items"] == 0 and receipt["paid"] > 0, "all funded native pieces produce actual paid rows")
	check(absf(coins() - before) < 0.000001 and Game.gold == 71 + receipt["paid"], "actual market debit equals exact company credit across all owners")
	check(receipt["till_before"] - receipt["till_after"] == float(receipt["paid"]), "receipt proves till payment, not an estimated loot grant")
	check(receipt["buyer_town_id"] == "seat" and receipt["buyer_business_id"] == 0 and receipt["buyer_business_name"] == "Seat exchange", "receipt identifies actual town and business")
	check(receipt["buyer_owner_household_uid"] == fx["town"]["econ"]["fams"][0]["household_uid"], "buyer ownership follows real household reference")
	check(receipt["scrap_paid"] + receipt["rags_paid"] == receipt["paid"] and fx["result"]["scrap_gold"] == receipt["scrap_paid"], "metal and whole-item proceeds have distinct truthful totals")
	for material in mass:
		var e: Dictionary = fx["town"]["econ"]; var good := "scrap_" + str(material)
		check(absf(float(e["stock"][good]) + float(e["scrap_residue_kg"][material]) - float(mass[material])) < 0.0000001, "whole native kg plus owned fraction conserves exact metal mass")
		check(e["stock"][good] == int(floor(float(mass[material]))) and float(e["scrap_residue_kg"][material]) < 1.0, "scrap conversion floors accumulated mass rather than rounding each piece")
	for i in receipt["rows"].size():
		var row: Dictionary = receipt["rows"][i]; var it: Item = fx["items"][i]
		check(row["item_uid"] == it.uid and row["mass_kg"] == it.mass() and row["paid"] == row["price"], "sale row traces exact Item quantity, physical mass and price")
		if it.material == "linen": check(fx["town"]["shop"].has(it) and row["destination"] == "market_inventory", "nonmetal handoff retains exact native Item at buyer inventory")
		else: check(row["unit_price"] == prices[it.material] and row["price"] == int(round(it.mass() * prices[it.material])), "native per-kg quote rounds coins, never material mass")
	check(plain(receipt) and Game.stash.is_empty(), "receipt owns no Item/Unit simulation references")
	check(Game.rng.state == rng and Unit._next_uid == unit_uid and Item._next_uid == item_uid, "settlement consumes no RNG or Item/Unit allocations")
	var state := native_state(); receipt["rows"][0]["paid"] = -1
	var repeated: Dictionary = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(repeated["rows"][0]["paid"] > 0 and native_state() == state and fx["result"]["salvage_receipts"].size() == 1, "repeat finalization returns detached receipt and never repeats payment/stock")
	var loaded: Dictionary = Game._deserialize(JSON.parse_string(JSON.stringify(Game._save_tree()))["world"])
	for material in mass:
		check(absf(float(loaded["towns"]["seat"]["econ"]["scrap_residue_kg"][material]) - float(fx["town"]["econ"]["scrap_residue_kg"][material])) < 0.000001, "native JSON world snapshot preserves owned fractional metal")

func poor_missing_and_aliases() -> void:
	var fx: Dictionary = fixture(0.0, true, 3); var stock := JSON.stringify(fx["town"]["econ"]["stock"]); var before := coins()
	var receipt: Dictionary = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(receipt["paid"] == 0 and receipt["retained_items"] == 3 and Game.stash.size() == 3, "empty till retains every exact unpaid Item")
	check(coins() == before and JSON.stringify(fx["town"]["econ"]["stock"]) == stock and not fx["town"]["econ"].has("scrap_residue_kg"), "unpaid scrap creates no stock, residue or currency")
	for it in fx["items"]: check(Game.stash.has(it), "unpaid piece preserves original physical identity")
	fx = fixture(100000.0, false, 2); before = coins()
	receipt = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(receipt["paid"] == 0 and receipt["buyer_town_id"] == "" and receipt["retained_items"] == 2 and coins() == before, "absent economy buyer never mints estimated proceeds")
	fx = fixture(100000.0, true, 2); fx["town"]["econ"]["mkt"] = 999; before = coins()
	receipt = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(receipt["paid"] == 0 and receipt["retained_items"] == 2 and coins() == before, "invalid nearest business fails closed instead of using another owner's cash")
	fx = fixture(100000.0, true, 2); fx["market"]["owner"] = -1; before = coins()
	receipt = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(receipt["paid"] == 0 and receipt["retained_items"] == 2 and receipt["buyer_owner_name"] == "Owner unrecorded" and coins() == before, "unrecorded owner cannot become an invented municipal payer")
	fx = fixture(100000.0, true, 2)
	var first: Item = fx["items"][0]; var second: Item = fx["items"][1]
	second.uid = first.uid # Different instances with duplicate persisted UID still represent two physical pieces.
	fx["records"].append(fx["records"][0]); before = coins()
	receipt = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(receipt["rows"].size() == 2 and coins() == before, "instance identity deduplicates aliases without merging distinct duplicate-UID Items")
	fx = fixture(100000.0, true, 2)
	var cost := int(round((fx["items"][0] as Item).mass() * Goods.sell_price(fx["town"], "scrap_copper")))
	fx["market"]["till"] = float(cost); before = coins()
	receipt = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
	check(receipt["paid"] == cost and receipt["retained_items"] == 1 and Game.stash.has(fx["items"][1]), "partial funding buys whole affordable pieces and retains the rest")
	check(coins() == before and fx["market"]["till"] == 0.0, "partial sale conserves coin without overdrawing till")

func native_harvest_ai_and_camp() -> void:
	var fx: Dictionary = fixture(0.0, true, 0)
	var enemy: Unit = Unit.create("human", "middle_kingdom", false); enemy.dead = true
	var item: Item = Item.make("arming_sword", "copper", 1); item.broken = true; enemy.equip["main_hand"] = item
	var sp: Dictionary = Loot.spoils([enemy], [], 2080, Game.loot_fraction())
	check(enemy.equip.is_empty() and sp["salvage"].size() == 1 and sp["salvage"][0]["item"] == item, "native loot harvest retains exact previously discarded Item without changing rolls")
	Salvage.finalize(Game, fx["result"], sp["salvage"], fx["pos"])
	check(Game.stash.has(item), "actual unpaid native battle salvage survives in owned stash")
	var own: Unit = Unit.create("human", "player", false); own.equip["main_hand"] = Item.make("arming_sword", "tin", 1); own.equip["main_hand"].broken = true
	var own_item: Item = own.equip["main_hand"]; var records := []; var kg: Dictionary = Loot.strip_broken([own], records)
	check(own.equip.is_empty() and records[0]["item"] == own_item and kg["tin"] == own_item.mass(), "native broken own gear collector preserves exact mass and original Item")
	fx = fixture(0.0, true, 0); enemy.equip["main_hand"] = Item.make("arming_sword", "copper", 1); enemy.equip["main_hand"].broken = true
	item = enemy.equip["main_hand"]; var before := coins()
	var scrapped_before := int(ArmsTrade.ledger.get("scrapped", 0))
	var out: Dictionary = ArmsTrade.field(Game, [enemy], {"town": fx["town"]}, fx["pos"])
	check(out["gold"] == 0.0 and ArmsTrade.armory(fx["town"]).has(item) and coins() == before, "unfunded AI salvage remains exact victorious armory property without autoequip or coin")
	check(int(ArmsTrade.ledger.get("scrapped", 0)) == scrapped_before and out["scrapped"] == 0 and out["kept"] == 1, "retained actual Item is not falsely counted as destroyed scrap")
	fx = fixture(100000.0, true, 0); enemy.equip["main_hand"] = Item.make("arming_sword", "copper", 1); enemy.equip["main_hand"].broken = true
	before = coins(); out = ArmsTrade.field(Game, [enemy], {"town": fx["town"]}, fx["pos"])
	check(out["gold"] > 0.0 and absf(coins() - before) < 0.000001 and Game.gold == 71, "paid AI market transfer uses existing soldiers/coffer rather than company wallet")
	fx = fixture(100000.0, true, 0); enemy.equip["main_hand"] = Item.make("arming_sword", "copper", 1); enemy.equip["main_hand"].broken = true
	item = enemy.equip["main_hand"]; before = coins()
	out = ArmsTrade.field(Game, [enemy], {"band": {"home": "seat", "faction": "moon_court", "units": [], "kind": "patrol"}}, fx["pos"])
	check(enemy.equip.get("main_hand") == item and out["gold"] == 0.0 and coins() == before and out.has("reason"), "no legitimate AI custody cannot harvest or donate to hostile home armory")
	fx = fixture(0.0, true, 0); var hoard: Array = []
	for i in Bandits.STOCK_MAX: hoard.append(Item.make("seax", "tin", 1))
	Game.world["lairs"]["camp_test"] = {"kind": "bandit_camp", "stock": hoard, "pos": fx["pos"], "gold": 0.0}
	enemy.equip["main_hand"] = Item.make("arming_sword", "copper", 1); enemy.equip["main_hand"].broken = true; item = enemy.equip["main_hand"]
	out = ArmsTrade.field(Game, [enemy], {"band": {"home": "camp_test", "faction": "outlaws", "units": [], "kind": "camp"}}, fx["pos"])
	check(hoard.size() == Bandits.STOCK_MAX + 1 and hoard.has(item) and out["salvage_receipt"]["rows"][0]["destination"] == "outlaw_hoard", "actual outlaw custody does not discard unpaid gear at old hoard cap")
	fx = fixture(0.0, true, 2); var result: Dictionary = fx["result"]
	Game.world["lairs"]["camp_test"] = {"kind": "bandit_camp", "stock": fx["items"].duplicate(), "pos": fx["pos"], "gold": 83.0}
	before = coins(); var loot := Bandits.clear_camp(Game, "camp_test", result)
	check(loot == 83 and result["camp_coin"] == 83 and result["camp_sale_paid"] == 0 and coins() == before, "camp cash is actual hoard coin; unfunded sale does not add estimates")
	check(Game.stash.has(fx["items"][0]) and Game.stash.has(fx["items"][1]) and result["salvage_receipts"].size() == 1, "destroyed camp's unpaid exact gear stays company property with distinct receipt")
	var state := native_state()
	check(Bandits.clear_camp(Game, "camp_test", result) == 0 and native_state() == state, "repeat camp clearing cannot debit/credit or move items again")
	fx = fixture(100000.0, true, 2); result = fx["result"]
	var first_sale: Dictionary = Salvage.finalize(Game, result, [fx["records"][0]], fx["pos"])
	var camp_item: Item = fx["items"][1]
	Game.world["lairs"]["camp_test"] = {"kind": "bandit_camp", "stock": [camp_item], "pos": fx["pos"], "gold": 83.0}
	before = coins(); loot = Bandits.clear_camp(Game, "camp_test", result)
	check(result["salvage_receipts"].size() == 2 and result["salvage_receipt"]["paid"] == first_sale["paid"] and result["camp_salvage_receipt"]["paid"] > 0, "main and camp each retain one accountable independent receipt")
	check(fx["town"]["shop"].has(camp_item) and result["camp_salvage_receipt"]["rows"][0]["destination"] == "market_inventory", "paid intact camp gear transfers exact Item to actual buyer without scrapping its identity")
	check(loot == 83 + result["camp_sale_paid"] and coins() == before, "funded camp sale and owned camp coin are conserved independent transfers")

## Frozen delivery rules use original linear Array.has/erase, independently of
## production's query-local membership index. Only plain predicted books change.
func linear_delivery(fx: Dictionary) -> Dictionary:
	var town: Dictionary = fx["town"]; var e: Dictionary = town["econ"]
	var retained: Array = Game.stash.duplicate(); var shop: Array = town["shop"].duplicate()
	var stock: Dictionary = e["stock"].duplicate(); var residue: Dictionary = e.get("scrap_residue_kg", {}).duplicate()
	var till := float(fx["market"]["till"]); var paid := 0; var seen := {}; var rows := []
	for entry in fx["records"]:
		var it: Item = entry["item"]; var instance: int = it.get_instance_id()
		if seen.has(instance): continue
		seen[instance] = true
		var good := "scrap_" + it.material
		var metal: bool = entry["kind"] == "scrap" and it.mat().get("kind", "") == "metal" and Goods.table().has(good)
		var estimate := int(entry["estimated_price"])
		if estimate == 0: estimate = int(round(it.value() * Game.loot_fraction() * (0.5 if entry["kind"] == "rags" else 1.0)))
		var price := int(round(it.mass() * Goods.sell_price(town, good))) if metal else estimate
		var row := {"item_uid": it.uid, "price": price, "paid": 0, "stock_units": 0, "destination": "company_stash", "residual_kg_before": 0.0, "residual_kg_after": 0.0}
		if till >= price and price > 0:
			till -= price; paid += price; row["paid"] = price
			if metal:
				var before := float(residue.get(it.material, 0.0)); var combined := before + it.mass(); var units := int(floor(combined))
				residue[it.material] = combined - units; stock[good] = int(stock.get(good, 0)) + units
				row["stock_units"] = units; row["residual_kg_before"] = before; row["residual_kg_after"] = combined - units; row["destination"] = "market_stock"
			else:
				if not shop.has(it): shop.append(it)
				row["destination"] = "market_inventory"
			retained.erase(it)
		elif not retained.has(it): retained.append(it)
		rows.append(row)
	return {"retained": retained, "shop": shop, "stock": stock, "residue": residue, "paid": paid, "till": till, "rows": rows}

func indexed_delivery_equivalence() -> void:
	for funded in [true, false]:
		var fx: Dictionary = fixture(100000.0 if funded else 0.0, true, 24)
		for i in 512:
			var held: Item = Item.make("arming_sword", "bronze", 1); Game.stash.append(held)
			var offered: Item = Item.make("tunic", "linen", 1); fx["town"]["shop"].append(offered)
			if i == 0:
				Game.stash.append(held); fx["town"]["shop"].append(offered) # Existing instance aliases remain ordered.
		Game.stash.append(fx["items"][0]) # Tests actual first erase of an already-owned offered piece.
		var same_uid: Item = Item.make("tunic", "linen", 1); same_uid.uid = fx["items"][3].uid
		fx["town"]["shop"].append(same_uid) # Same saved UID is not membership identity.
		fx["records"].append(fx["records"][3]); fx["records"].append(Salvage.record(fx["items"][3], "rags", "enemy", 19))
		var expected: Dictionary = linear_delivery(fx); var before := coins(); var rng := Game.rng.state
		var item_uid := Item._next_uid; var unit_uid := Unit._next_uid
		var receipt: Dictionary = Salvage.finalize(Game, fx["result"], fx["records"], fx["pos"])
		check(Game.stash == expected["retained"] and fx["town"]["shop"] == expected["shop"], "large inventory membership optimization preserves exact physical references and native insertion/erase order")
		check(fx["town"]["econ"]["stock"] == expected["stock"] and fx["town"]["econ"].get("scrap_residue_kg", {}) == expected["residue"], "indexed delivery equals frozen linear mass and fractional stock books")
		check(receipt["paid"] == expected["paid"] and fx["market"]["till"] == expected["till"] and coins() == before, "indexed delivery equals frozen linear actual payer/recipient coin")
		var projected := []
		for row in receipt["rows"]:
			var selected := {}
			for key in expected["rows"][0]: selected[key] = row[key]
			projected.append(selected)
		check(projected == expected["rows"], "indexed delivery preserves each exact receipt sequence/quantity/price/residue/destination")
		check(Item._next_uid == item_uid and Unit._next_uid == unit_uid and Game.rng.state == rng, "local lookup indexes allocate no game identities and consume no random rolls")

func run(_tree: SceneTree) -> int:
	full_and_once(); poor_missing_and_aliases(); native_harvest_ai_and_camp(); indexed_delivery_equivalence()
	print("Salvage v020: %d checks, %d failures" % [checks, fails])
	return fails
