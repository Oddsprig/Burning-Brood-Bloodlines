class_name Metallurgy
extends RefCounted
## Counted market inputs feed the native smelters. Issued and legendary gear
## retains its individual identity, damage, material and battle history.

static func bronze_unlocked(e: Dictionary) -> bool:
	return Businesses.kh_of(e, "bronze") > 0.0

static func equipment_metal_allowed(e: Dictionary, metal: String) -> bool:
	return not (bronze_unlocked(e) and metal in ["copper", "tin"])

static func metal_mass(it: Item) -> float:
	var t := it.tmpl()
	var volume := float(t.get("head_cm3", 0.0)) if it.is_weapon() else float(t.get("cm3", 0.0))
	return maxf(0.0, volume * float(it.mat().get("density", 0.0)) / 1.0e6)

## The market already owns its shop stock. Recycling transfers that SAME metal
## into its counted scrap bins; it creates no sale, coin, replacement or kit.
## Fractions remain owned in a carry bin rather than rounding into extra bars.
static func recycle_stock(town: Dictionary, limit: int = 24) -> int:
	var e: Dictionary = town.get("econ", {})
	if e.is_empty() or not bronze_unlocked(e): return 0
	var shop: Array = town.get("shop", [])
	var carry: Dictionary = e.get("recycling_carry", {})
	var stats: Dictionary = e.get("stats", {})
	var count := 0
	for i in range(shop.size() - 1, -1, -1):
		if count >= maxi(0, limit): break
		var it: Item = shop[i]
		if it.material not in ["copper", "tin"] or it.is_legend(): continue
		var mass := metal_mass(it)
		if mass <= 0.0: continue
		var good := "scrap_" + it.material
		var total := float(carry.get(good, 0.0)) + mass
		var whole := int(floor(total + 0.000000001))
		carry[good] = maxf(0.0, total - float(whole))
		e["stock"][good] = int(e["stock"].get(good, 0)) + whole
		TownEcon.led(e, "made", good, whole)
		TownEcon.led(e, "used", "arms", 1)
		stats["recycled_kg"] = float(stats.get("recycled_kg", 0.0)) + mass
		stats["recycled_items"] = int(stats.get("recycled_items", 0)) + 1
		WorldAudit.lose_item(it, "-recycled into a town's scrap stock")   # v0.075 r6: melted, its metal booked made
		shop.remove_at(i)
		count += 1
	e["recycling_carry"] = carry
	e["stats"] = stats
	return count

## Recipe selection gives a feasible alloy batch precedence over making more
## feedstock bars. Missing copper/tin still lets the smelter refine real inputs.
static func alloy_recipe(e: Dictionary, recipes: Array) -> Dictionary:
	if not bronze_unlocked(e): return {}
	var stock: Dictionary = e.get("stock", {})
	for recipe in recipes:
		if not recipe.get("out", {}).has("bronze_bars") or not recipe.get("in", {}).has("copper_bars") or not recipe.get("in", {}).has("tin_bars"): continue
		var enough := true
		for good in recipe["in"]:
			if float(stock.get(good, 0.0)) < float(recipe["in"][good]): enough = false; break
		if enough: return recipe
	return {}

## Two iron bars finish as two steel bars: one becomes pig iron, the other
## joins it in the final heat. Keep those pairs together instead of turning
## the entire iron bin into pig iron that this furnace can no longer finish.
static func _pig_iron_batches(e: Dictionary) -> int:
	var stock: Dictionary = e.get("stock", {})
	return maxi(0, int(floor((float(stock.get("iron_bars", 0)) - float(stock.get("pig_iron", 0))) / 2.0)))

## Finish wanted steel before refining more feedstock or casting bronze.
## Each selected step still uses the normal paid, whole-batch transaction.
## Full/resting outputs and missing inputs retain the ordinary market rules.
static func _steel_recipe(e: Dictionary, recipes: Array) -> Dictionary:
	if Businesses.kh_of(e, "steel") <= 0.0: return {}
	var stock: Dictionary = e.get("stock", {})
	var resting: Dictionary = e.get("_aimrest", {})
	if resting.has("steel_bars") or float(stock.get("steel_bars", 0)) >= Businesses.stock_cap(e, "steel_bars"): return {}
	for output in ["steel_bars", "pig_iron", "iron_bars"]:
		if output == "pig_iron" and _pig_iron_batches(e) <= 0: continue
		if output == "iron_bars" and int(stock.get("iron_bars", 0)) >= maxi(2, int(stock.get("pig_iron", 0))): continue
		if resting.has(output) or float(stock.get(output, 0)) >= Businesses.stock_cap(e, output): continue
		for recipe in recipes:
			if not recipe.get("out", {}).has(output): continue
			if recipe.has("knowhow") and Businesses.kh_of(e, String(recipe["knowhow"])) <= 0.0: continue
			var enough := true
			for good in recipe["in"]:
				if float(stock.get(good, 0)) < float(recipe["in"][good]): enough = false; break
			if enough: return recipe
	return {}

static func summary(e: Dictionary) -> Dictionary:
	var stock: Dictionary = e.get("stock", {})
	var carried: Dictionary = e.get("recycling_carry", {})
	var stats: Dictionary = e.get("stats", {})
	return {"bronze_unlocked": bronze_unlocked(e),
		"copper_bars": int(stock.get("copper_bars", 0)), "tin_bars": int(stock.get("tin_bars", 0)),
		"bronze_bars": int(stock.get("bronze_bars", 0)),
		"recycled_items": int(stats.get("recycled_items", 0)), "recycled_kg": float(stats.get("recycled_kg", 0.0)),
		"scrap_kg": float(stock.get("scrap_copper", 0)) + float(stock.get("scrap_tin", 0)) + float(carried.get("scrap_copper", 0.0)) + float(carried.get("scrap_tin", 0.0)),
		"bronze_made": int(e.get("led", {}).get("made", {}).get("bronze_bars", 0)),
		"policy": "Bronze and advanced metal equipment; copper and tin become alloy inputs." if bronze_unlocked(e) else "Copper and tin equipment; bronze knowledge required."}
