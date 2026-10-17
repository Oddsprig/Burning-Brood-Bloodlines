class_name Salvage
extends RefCounted
## Native harvested Item references remain owned until a real market funds them.
## Receipt views contain plain values only; no read path repeats settlement.

static func record(item: Item, kind: String = "scrap", source: String = "own", estimated_price: int = 0) -> Dictionary:
	return {"item": item, "kind": kind, "source": source, "estimated_price": maxi(0, estimated_price)}

static func nearest(world: Dictionary, pos: Vector2) -> Dictionary:
	var buyer: Dictionary = {}; var distance := INF
	for town in world.get("towns", {}).values():
		if not TownEcon.has_econ(town): continue
		var d: float = (town["pos"] as Vector2).distance_to(pos)
		if d < distance: buyer = town; distance = d
	return buyer # Native town insertion order breaks ties; faction is unchanged.

static func _market(town: Dictionary) -> Dictionary:
	var e: Dictionary = town.get("econ", {}); var businesses: Array = e.get("biz", [])
	var index := int(e.get("mkt", -1))
	if index < 0 or index >= businesses.size() or not businesses[index] is Dictionary: return {}
	var market: Dictionary = businesses[index]
	if str(market.get("type", "")) != "market" or market.get("closed", false) or not market.has("till") or not is_finite(float(market["till"])): return {}
	var owner_id := int(market.get("owner", -1)); var families: Array = e.get("fams", [])
	if owner_id < 0 or owner_id >= families.size(): return {}
	var owner: Dictionary = families[owner_id]
	if str(owner.get("household_uid", "")) == "" or owner.get("estate", false) or Population.is_cohort(owner): return {}
	# Existing payment and stock ledgers must be real before any transfer starts.
	if not e.get("stats", {}).has("sales") or not e.get("led", {}).has("made") or not e.has("price"): return {}
	return market

static func _buyer(town: Dictionary, market: Dictionary) -> Dictionary:
	var e: Dictionary = town.get("econ", {}); var owner: Dictionary = {}
	var owner_id := int(market.get("owner", -1))
	if owner_id >= 0 and owner_id < e.get("fams", []).size(): owner = e["fams"][owner_id]
	var business_id := int(market.get("id", e.get("mkt", -1)))
	return {"buyer_town_id": str(town.get("id", "")), "buyer_town_name": str(town.get("name", "")),
		"buyer_business_id": business_id, "buyer_business_name": str(market.get("name", TownEcon.data().get("businesses", {}).get(str(market.get("type", "market")), {}).get("name", "Market"))),
		"buyer_owner_household_uid": str(owner.get("household_uid", "")), "buyer_owner_name": str(owner.get("name", "Owner unrecorded"))}

static func _members(items: Array) -> Dictionary:
	var members := {}
	for item in items:
		if item is Item:
			var instance: int = item.get_instance_id()
			members[instance] = int(members.get(instance, 0)) + 1
	return members

## Reusable actual buyer transaction. retained is the caller's existing owned
## Item array (company stash, legitimate armory or hoard), never a new wallet.
## The caller credits paid into its existing recipient account exactly once.
static func trade(game, records: Array, pos: Vector2, retained: Array, recipient_name: String = "Army purse", recipient_account: String = "company_wallet", retained_destination: String = "company_stash") -> Dictionary:
	var started := Time.get_ticks_usec()
	var town: Dictionary = nearest(game.world, pos); var market: Dictionary = _market(town)
	var out: Dictionary = _buyer(town, market)
	out.merge({"finalized": true, "payer_account": "market_till", "recipient_account": recipient_account,
		"recipient_name": recipient_name, "till_before": float(market.get("till", 0.0)), "till_after": float(market.get("till", 0.0)),
		"paid": 0, "scrap_paid": 0, "rags_paid": 0, "estimated": 0, "retained_items": 0, "reason": "", "rows": []})
	var unavailable := "No economy-enabled buyer is available." if town.is_empty() else "The nearest market has no valid payment ledger."
	var seen := {}
	var retained_members := {}; var retained_indexed := false
	var shop_members := {}; var shop_indexed := false
	var fraction := 0.0; var fraction_read := false
	for entry in records:
		if not entry is Dictionary or not entry.get("item") is Item: continue
		if entry.get("settled", false): continue
		var it: Item = entry["item"]; var instance := it.get_instance_id()
		entry["settled"] = true
		if seen.has(instance): continue # Aliases are one physical piece; distinct instances are not merged by UID.
		seen[instance] = true
		var mass := it.mass(); var good := "scrap_" + it.material
		var metal: bool = str(entry.get("kind", "scrap")) == "scrap" and it.mat().get("kind", "") == "metal" and Goods.table().has(good)
		var estimate := maxi(0, int(entry.get("estimated_price", 0)))
		if estimate == 0 and (not metal or market.is_empty()):
			if not fraction_read: fraction = float(game.loot_fraction()); fraction_read = true
			estimate = int(round(it.value() * fraction * (0.5 if str(entry.get("kind", "")) == "rags" else 1.0)))
		var unit_price := Goods.sell_price(town, good) if metal and not market.is_empty() else (0 if metal else estimate)
		var price := int(round(mass * unit_price)) if metal and not market.is_empty() else estimate
		var row := {"item_uid": it.uid, "item_name": it.display_name(), "material": it.material,
			"material_name": str(it.mat().get("name", it.material)), "kind": str(entry.get("kind", "scrap")), "source": str(entry.get("source", "")),
			"quantity": 1, "mass_kg": mass, "stock_good": good if metal else "", "stock_units": 0,
			"unit_price": unit_price, "price": price, "paid": 0, "retained": true, "destination": retained_destination, "reason": "",
			"residual_kg_before": 0.0, "residual_kg_after": 0.0}
		out["estimated"] = int(out["estimated"]) + maxi(0, price)
		if market.is_empty(): row["reason"] = unavailable
		elif not is_finite(mass) or mass <= 0.0 or price <= 0: row["reason"] = "This piece has no payable native salvage quote."
		elif float(market["till"]) < price: row["reason"] = "The market cannot fund this whole piece."
		else:
			# No stock, equipment or till mutation occurs before full affordability.
			Goods.pay_market(town, -float(price))
			if metal:
				var e: Dictionary = town["econ"]
				if not e.has("scrap_residue_kg"): e["scrap_residue_kg"] = {}
				var residue: Dictionary = e["scrap_residue_kg"]
				var before := float(residue.get(it.material, 0.0)); var combined := before + mass
				var units := int(floor(combined)); var remainder := combined - units
				e["stock"][good] = int(e["stock"].get(good, 0)) + units
				residue[it.material] = remainder
				if units > 0: TownEcon.led(e, "made", good, units)
				row["stock_units"] = units; row["residual_kg_before"] = before; row["residual_kg_after"] = remainder
				row["destination"] = "market_stock"
			else:
				if not town.has("shop"): town["shop"] = []
				if not shop_indexed:
					shop_members = retained_members if retained_indexed and is_same(town["shop"], retained) else _members(town["shop"])
					shop_indexed = true
				if int(shop_members.get(instance, 0)) == 0:
					town["shop"].append(it); shop_members[instance] = 1
				row["destination"] = "market_inventory"
			if not retained_indexed:
				retained_members = shop_members if shop_indexed and is_same(town.get("shop", []), retained) else _members(retained)
				retained_indexed = true
			var copies := int(retained_members.get(instance, 0))
			if copies > 0: retained.erase(it); retained_members[instance] = copies - 1
			row["retained"] = false; row["paid"] = price
			out["paid"] = int(out["paid"]) + price
			out["scrap_paid" if metal else "rags_paid"] = int(out["scrap_paid" if metal else "rags_paid"]) + price
		if row["retained"]:
			if not retained_indexed:
				retained_members = shop_members if shop_indexed and is_same(town.get("shop", []), retained) else _members(retained)
				retained_indexed = true
			if int(retained_members.get(instance, 0)) == 0:
				retained.append(it); retained_members[instance] = 1
			out["retained_items"] = int(out["retained_items"]) + 1
		out["rows"].append(row)
	out["till_after"] = float(market.get("till", 0.0))
	out["reason"] = unavailable if market.is_empty() else ("Unpaid pieces remain owned by the recipient." if int(out["retained_items"]) > 0 else "Every offered piece was paid by this market.")
	Perf.record_us("Salvage settlement", Time.get_ticks_usec() - started)
	return out

static func finalize(game, result: Dictionary, records: Array, pos: Vector2, receipt_key: String = "salvage_receipt", transaction: String = "battle_salvage") -> Dictionary:
	if result.has(receipt_key): return result[receipt_key].duplicate(true)
	var before := int(game.gold)
	var receipt: Dictionary = trade(game, records, pos, game.stash)
	game.gold += int(receipt["paid"])
	receipt["wallet_before"] = before; receipt["wallet_after"] = int(game.gold)
	receipt["transaction"] = transaction
	result[receipt_key] = receipt
	if not result.has("salvage_receipts"): result["salvage_receipts"] = []
	result["salvage_receipts"].append(receipt)
	if receipt_key == "salvage_receipt":
		result["scrap_paid"] = int(receipt["scrap_paid"]); result["scrap_gold"] = int(receipt["scrap_paid"])
		result["rags_paid"] = int(receipt["rags_paid"])
	return receipt.duplicate(true)
