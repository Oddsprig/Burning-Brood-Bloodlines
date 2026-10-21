class_name TownEconViews
extends RefCounted
## Read-only UI/text/report/ledger view queries split from TownEcon (game/campaign/town_econ.gd)
## to keep each file focused and under the size threshold.
## Structure only; all TownEcon.* entry points delegate here with identical behavior.

const SINGULAR := TownEcon.SINGULAR

# ================================================================== text & land summaries
## "barley", "apples", "flax" (the town's own variety for a crop).
static func variety_word(e: Dictionary, crop: String) -> String:
	return String(e.get("crops", {}).get(crop, crop))

## "barley ale", "cider", "mutton": the label a good rides with in this town.
static func label(e: Dictionary, g: String) -> String:
	var V: Dictionary = TownEcon.data()["varieties"]
	match g:
		"grain": return V.get(e["crops"]["grain"], {}).get("food", "grain")
		"fruit": return V.get(e["crops"]["fruit"], {}).get("food", "fruit")
		"beer": return V.get(e["crops"]["grain"], {}).get("drink", "beer")
		"wine": return V.get(e["crops"]["fruit"], {}).get("drink", "wine")
		"meat":
			var hk: Array = e.get("herd_kinds", [])
			return V.get(hk[0], {}).get("food", "meat") if not hk.is_empty() else "meat"
	return TownEcon.data()["goods"].get(g, {}).get("name", g)

## "1 acre", "12 acres", "a cow" -> "1 cow", "3 cattle", "1 pig": counts in running text.
static func n_of(n: int, plural: String) -> String:
	return ("one " + SINGULAR.get(plural, plural)) if n == 1 else "%d %s" % [n, plural]

## Acres in the town's land pool (every crop; families and the town estate).
static func land_total(e: Dictionary) -> int:
	var n := 0
	for c in e.get("land", {}):
		n += int(e["land"][c])
	return n

## {territory, families, estate, common}: territory is stored at world gen (the land pool then); land only moves
## between families and the estate, so common (unclaimed) is whatever of the territory nobody holds.
static func land_split(e: Dictionary) -> Dictionary:
	var fam := 0
	for f in e["fams"]:
		if not f.get("gone", false) and not f.has("estate"):
			fam += Families.acres(f)
	var est := Families.acres(e["fams"][0])
	var terr := int(e.get("territory", fam + est))
	return {"territory": terr, "families": fam, "estate": est, "common": maxi(0, terr - fam - est)}

## The town's land for the Town screen: land_split plus acres by crop for the resident families and for the
## estate, and herds by animal: {territory, families, estate, common, fam_crops {crop: acres}, est_crops,
## herds {animal: head}, fam_herd, est_herd}. Residents = families not gone.
static func land_summary(e: Dictionary) -> Dictionary:
	var s := land_split(e)
	var fl := {}; var fh := {}; var all_h := {}
	var fhn := 0; var ehn := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false):
			continue
		for c in f["land"]:
			fl[c] = int(fl.get(c, 0)) + int(f["land"][c])
		for a in f["herd"]:
			fh[a] = int(fh.get(a, 0)) + int(f["herd"][a])
			fhn += int(f["herd"][a])
	var est: Dictionary = e["fams"][0]
	all_h = fh.duplicate()
	for a in est["herd"]:
		ehn += int(est["herd"][a])
		all_h[a] = int(all_h.get(a, 0)) + int(est["herd"][a])
	s["fam_crops"] = fl
	s["est_crops"] = (est["land"] as Dictionary).duplicate()
	s["herds"] = all_h
	s["fam_herd"] = fhn
	s["est_herd"] = ehn
	return s

# ================================================================== demand & producer views
## Daily household use of each good (people, adults, homes, season, climate): the opening demand, and the
## town screen's days-of-supply.
static func household_use(e: Dictionary, si: int, goods: Array = []) -> Dictionary:
	var D := TownEcon.data()
	var nd: Dictionary = D["needs"]
	var clim: Dictionary = D["climates"][e["climate"]]
	var pop := float(e["pop"]); var ad := float(e["adults"]); var homes := float(e["homes"])
	var bs := EconGen.beer_share_of(e)
	var wd: Dictionary = nd["wear_days"]
	var room := float(D["cultures"][e["culture"]]["home"]["room"])
	var out := {"beer": ad * float(nd["drink_adult"]) * bs, "wine": ad * float(nd["drink_adult"]) * (1.0 - bs),
		"wood": homes * float(nd["firewood_home"]) * float(nd["firewood_season"][si]) * float(clim["firewood"]),
		"clothing": pop / float(wd["clothing"]), "blankets": homes / float(wd["blankets"]), "tools": ad / float(wd["tools"]),
		"furniture": homes / float(wd["furniture"]), "jewelry": float(e.get("rich", 0)) / float(wd["jewelry"]),
		"home": maxf(0.0, pop - homes * room) / room / 14.0 + 0.02}
	if goods.is_empty() or goods.has("grain") or goods.has("fruit") or goods.has("meat"):
		var dt := Barge.diet(e)
		var meal_shares := Barge.household_eaters(e, float(e.get("day", 0)), false)
		var food := {}
		for good in ["grain", "fruit", "meat"]:
			food[good] = meal_shares * float(dt[good])
		food.merge(out)
		out = food
	if not goods.is_empty():
		for good in out.keys():
			if not goods.has(good): out.erase(good)
	return out

static func _producers(e: Dictionary, g: String) -> Array:
	var D := TownEcon.data()
	var out := []
	for b in e["biz"]:
		if b.get("closed", false):
			continue
		var T: Dictionary = D["businesses"][b["type"]]
		if b["type"] == "butcher" and g in ["fresh_meat", "hides", "tallow", "bones", "horn", "sinew"]:
			out.append(b)
			continue
		if b["type"] == "mine" and b.get("ore", "") == g:
			out.append(b)
			continue
		for r in T["recipes"]:
			if (r["out"] as Dictionary).has(g):
				out.append(b)
				break
	return out

# ================================================================== supply levels (food spec hook)
static func days_food(town: Dictionary) -> float:
	if not TownEcon.has_econ(town):
		return 30.0
	var e: Dictionary = town["econ"]
	var f := float(e["granary"])
	for g in ["grain", "fruit", "meat"]:
		f += float(e["stock"].get(g, 0)) + float(e["barn"].get(g, 0)) + float(e["hh"].get(g, 0))
	f += float(e["hh"].get("fresh_meat", 0))
	return f / maxf(1.0, float(e["pop"]) * float(TownEcon.data()["needs"]["food"]))

static func days_drink(town: Dictionary) -> float:
	if not TownEcon.has_econ(town):
		return 30.0
	var e: Dictionary = town["econ"]
	var d := 0.0
	for g in ["beer", "wine"]:
		d += float(e["stock"].get(g, 0)) + float(e["hh"].get(g, 0))
	return d / maxf(1.0, float(e["adults"]) * float(TownEcon.data()["needs"]["drink_adult"]))

## "well" (> 14 days of food and drink), "short" (3-14), "starving" (< 3). Food spec reads it at battle spawn
## for armies from this town and for its militia.
static func supply_level(town: Dictionary, food_days: Variant = null) -> String:
	if not TownEcon.has_econ(town):
		return "well"
	var D := TownEcon.data()
	# A records build may already have read this exact town's food days for its totals.
	var df := days_food(town) if food_days == null else float(food_days)
	var dd := days_drink(town)
	if df < float(D["supply_short"]):
		return "starving"
	if df <= float(D["supply_well"]) or dd < float(D["supply_short"]):
		return "short"
	return "well"

static func supply_word(level: String) -> String:
	return {"well": "well supplied", "short": "short", "starving": "starving"}.get(level, level)

## Supply level of a force: its home town's (forces carry no daily sim).
static func force_supply(w: Dictionary, wb: Dictionary) -> String:
	var t: Dictionary = w.get("towns", {}).get(str(wb.get("home", "")), {})
	return supply_level(t) if not t.is_empty() else "well"

# ================================================================== arms stock reads (militia, forces, menus)
## The town's arms stock as a sparse dict {"tid|material|quality": count} (the Items themselves are town["shop"]).
static func arms_stock(town: Dictionary) -> Dictionary:
	var out := {}
	for it in town.get("shop", []):
		var k := "%s|%s|%d" % [it.tid, it.material, it.quality]
		out[k] = int(out.get(k, 0)) + 1
	return out

## Pieces in stock (optionally of one equip slot: main_hand, off_hand, helm, body, ...).
static func arms_count(town: Dictionary, slot: String = "", quality_min: int = 0) -> int:
	var n := 0
	for it in town.get("shop", []):
		if (slot == "" or it.slot() == slot) and it.quality >= quality_min:
			n += 1
	return n

# ================================================================== totals (tests, ledgers)
## Every unit of good `g` the town holds: market, barns, granary (grain), households.
static func town_total(e: Dictionary, g: String) -> int:
	var n := int(e["stock"].get(g, 0)) + int(e["barn"].get(g, 0)) + int(e["hh"].get(g, 0)) + int(e.get("gh", {}).get(g, 0))   # (gh: families' stones)
	if g == "grain":
		n += int(e["granary"])
	return n

## Every coin the town holds: treasury, land fund, tills, purses and unclaimed barn sales.
static func town_gold(e: Dictionary) -> float:
	var g := float(e["treasury"]) + float(e["farm_till"]) + float(e.get("land_fund", 0.0))
	for b in e["biz"]:
		g += float(b["till"])
	for f in e["fams"]:
		g += float(f["purse"])
	return g
