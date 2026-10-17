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
