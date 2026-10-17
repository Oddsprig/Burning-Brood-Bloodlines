extends RefCounted
## Battle scrap back into the economy (Douglas): one scrap good per metal; battle scrap lands in the nearest town's
## market stock (TownEcon.add_scrap); that town's smelter buys it and melts it into bars of the same metal, burning
## wood; the race tech rules hold (an orc smelter never remelts bronze scrap); the scrap price moves with its stock.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

const METALS := ["scrap_copper", "scrap_tin", "scrap_bronze", "scrap_iron", "scrap_steel"]
const BARS := {"scrap_copper": "copper_bars", "scrap_tin": "tin_bars", "scrap_bronze": "bronze_bars", "scrap_iron": "iron_bars", "scrap_steel": "steel_bars"}

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_scrap_%d.json" % OS.get_process_id()
	_test_recipe_data()
	Game.new_game(2026)
	_quiet(Game.world)
	_test_add_scrap()
	_test_remelt()
	_test_orc_bronze()
	_test_town_flow()
	_test_price()
	return fails

func _quiet(w: Dictionary) -> void:
	for wid in w["warbands"].keys():
		CampaignWorld.remove_warband(Game, wid)
	w["work"] = []
	w["party"]["safe_until"] = 1.0e9

func _ids(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys()
	ids.sort()
	return ids

func _town_of_race(race: String) -> Dictionary:
	var w: Dictionary = Game.world
	for tid in _ids(w):
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t) and Academy.faction_race(String(t.get("faction", ""))) == race:
			return t
	return {}

# ---------------------------------------------------------------- the recipes
func _test_recipe_data() -> void:
	var recs: Array = TownEcon.data()["businesses"]["smelter"]["recipes"]
	for g in METALS:
		check(TownEcon.data()["goods"].has(g), "no %s good" % g)
		var found := false
		for r in recs:
			if not (r["in"] as Dictionary).has(g):
				continue
			var og: String = (r["out"] as Dictionary).keys()[0]
			if og != BARS[g]:
				continue   # (steel scrap also downgrades to iron bars where only iron is known)
			found = true
			check(float(r["in"].get("wood", 0.0)) > 0.0, "%s is remelted without fuel" % g)
			check(absf(float(r["in"][g]) - float(r["out"][og])) < 0.001, "%s remelt does not give its weight back in bars" % g)
			for ig in r["in"]:
				check(absf(float(r["in"][ig]) - round(float(r["in"][ig]))) < 0.001, "%s recipe input %s is not whole (the smelter takes whole units)" % [g, ig])
			if g == "scrap_bronze":
				check(String(r.get("knowhow", "")) == "bronze", "bronze scrap remelting not gated by bronze know-how")
			if g == "scrap_iron":
				check(String(r.get("knowhow", "")) == "iron", "iron scrap remelting not gated by iron know-how")
			if g == "scrap_steel":
				check(String(r.get("knowhow", "")) == "steel", "steel scrap remelting not gated by steel know-how")
		check(found, "no smelter recipe turns %s into %s" % [g, BARS[g]])

# ---------------------------------------------------------------- battle scrap into the nearest town
func _test_add_scrap() -> void:
	var w: Dictionary = Game.world
	var t := _town_of_race("human")
	var e: Dictionary = t["econ"]
	var st0 := {}
	for g in METALS:
		st0[g] = int(e["stock"].get(g, 0))
	var near := TownEcon.add_scrap(w, {"copper": 40.4, "bronze": 9.6, "iron": 5.0, "linen": 3.0}, (t["pos"] as Vector2) + Vector2(1, 1))
	check(near == String(t["id"]), "battle scrap went to %s, not the nearest town %s" % [near, t["id"]])
	check(int(e["stock"]["scrap_copper"]) == int(st0["scrap_copper"]) + 40, "copper scrap not in the town's stock")
	check(int(e["stock"]["scrap_bronze"]) == int(st0["scrap_bronze"]) + 10, "bronze scrap not in the town's stock")
	check(int(e["stock"]["scrap_iron"]) == int(st0["scrap_iron"]) + 5, "iron scrap not in the town's stock")
	check(not e["stock"].has("scrap_linen"), "linen rags became a scrap good")
	print("  scrap from a battle by %s: copper %d -> %d, bronze %d -> %d, iron %d -> %d" % [t["name"], st0["scrap_copper"], e["stock"]["scrap_copper"],
		st0["scrap_bronze"], e["stock"]["scrap_bronze"], st0["scrap_iron"], e["stock"]["scrap_iron"]])

## A smelter row working on stocks we set (as tests/test_metal_tech.gd _smelt); returns the stock change and what the
## market's till took in (the smelter paying for its scrap and wood, less what the market paid for its bars).
func _smelt(t: Dictionary, stock: Dictionary, days: int) -> Dictionary:
	var e: Dictionary = t["econ"]
	var D := TownEcon.data()
	var st: Dictionary = e["stock"]
	for g in METALS + ["copper_ore", "tin_ore", "iron_ore", "iron_bars", "pig_iron", "flux", "copper_bars", "tin_bars", "wood", "bronze_bars", "steel_bars"]:
		st[g] = 0
	for g in stock:
		st[g] = int(stock[g])
	for g in BARS.values():
		e["need"][g] = 100000.0   # (room in the market: the output is never "full")
	e.erase("_aimu"); e.erase("_aimrest"); e.erase("_nomargin")
	var b := Businesses._row(e, "smelter", -1, 1, D)
	(e["biz"] as Array).pop_back()
	b["till"] = 1.0e7
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var mt := float(mkt["till"])
	mkt["till"] = 1.0e7
	var before := st.duplicate()
	var spent := 0.0
	for i in days:
		spent += Businesses._recipes(e, D, b, D["businesses"]["smelter"], 10.0, 1.0, 1.0, mkt, float(D["market"]["buy_share"]), {})
	mkt["till"] = mt
	var d := {}
	for g in st:
		if int(st[g]) != int(before.get(g, 0)):
			d[g] = int(st[g]) - int(before.get(g, 0))
	d["_spent"] = spent
	return d

# ---------------------------------------------------------------- remelting: same metal, real fuel
func _test_remelt() -> void:
	var h := _town_of_race("human")
	var e: Dictionary = h["econ"]
	e["knowhow"]["bronze"] = 100.0
	if not e.has("fkh"):
		e["fkh"] = {}
	var fk: Dictionary = e["fkh"]
	var had_steel := fk.has("steel")
	var steel0 := float(fk.get("steel", 0.0))
	fk["steel"] = 100.0   # (a realm that has learned steel: its steel scrap goes back to steel bars)
	for g in METALS:
		var key: String = {"scrap_bronze": "bronze", "scrap_iron": "iron", "scrap_steel": "steel"}.get(g, "")
		if key != "" and Businesses.kh_of(e, key) <= 0.0:
			print("  %s: %s has no %s know-how, skipped" % [g, h["name"], key])
			continue
		var d := _smelt(h, {g: 200, "wood": 200}, 2)
		var bars: String = BARS[g]
		var used := -int(d.get(g, 0))
		var made := int(d.get(bars, 0))
		var wood := -int(d.get("wood", 0))
		print("  %s remelts %d kg %s with %d wood into %d %s (paid %.0f)" % [h["name"], used, g, wood, made, bars, float(d["_spent"])])
		check(used > 0 and made == used, "%s: %d kg scrap in, %d %s out (want the same weight)" % [g, used, made, bars])
		check(wood > 0, "%s remelted without burning wood" % g)
		check(float(d["_spent"]) > 0.0, "the smelter did not pay the market for its %s" % g)
		for other in BARS.values():
			if other != bars:
				check(int(d.get(other, 0)) == 0, "%s came out as %s" % [g, other])
		# no fuel, no remelting
		var dn := _smelt(h, {g: 200}, 2)
		check(int(dn.get(g, 0)) == 0 and int(dn.get(bars, 0)) == 0, "%s remelted with no wood (%s)" % [g, str(dn)])
	if had_steel:
		fk["steel"] = steel0
	else:
		fk.erase("steel")

# ---------------------------------------------------------------- race tech rules
func _test_orc_bronze() -> void:
	var o := _town_of_race("orc")
	check(not o.is_empty(), "no orc town")
	if o.is_empty():
		return
	o["econ"]["knowhow"]["bronze"] = 100.0   # whatever the town has heard, orcs never work bronze
	var d := _smelt(o, {"scrap_bronze": 200, "wood": 200}, 3)
	print("  orc smelter (%s) given bronze scrap and wood: %s" % [o["name"], str(d)])
	check(int(d.get("scrap_bronze", 0)) == 0 and int(d.get("bronze_bars", 0)) == 0, "an orc smelter remelted bronze scrap (%s)" % str(d))
	check(int(o["econ"]["stock"].get("scrap_bronze", 0)) == 200,"the orc town's bronze scrap did not stay in its stock")
	var dc := _smelt(o, {"scrap_copper": 200, "wood": 200}, 2)
	check(int(dc.get("copper_bars", 0)) > 0, "the orc smelter did not remelt copper scrap (%s)" % str(dc))

# ---------------------------------------------------------------- the whole town: market stock -> smelter -> bars
func _test_town_flow() -> void:
	var w: Dictionary = Game.world
	var t := {}
	for tid in _ids(w):
		var c: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(c) or Academy.faction_race(String(c.get("faction", ""))) != "human":
			continue
		if (c["econ"]["biz"] as Array).any(func(b): return b["type"] == "smelter" and not b["closed"] and int(b["workers"]) + int(b.get("kw", 0)) > 0):
			t = c
			break
	check(not t.is_empty(), "no human town with a working smelter")
	if t.is_empty():
		return
	var e: Dictionary = t["econ"]
	for b in e["biz"]:
		if b["type"] == "mine":
			b["closed"] = true
	for g in METALS + ["copper_ore", "tin_ore", "iron_ore", "copper_bars"]:
		e["stock"][g] = 0
	e["stock"]["wood"] = maxi(int(e["stock"].get("wood", 0)), 400)
	TownEcon.add_scrap(w, {"copper": 300.0}, t["pos"])
	var used0 := int(e["led"]["used"].get("scrap_copper", 0))
	var made0 := int(e["led"]["made"].get("copper_bars", 0))
	var wood0 := int(e["led"]["used"].get("wood", 0))
	for i in 6:
		TownEcon.daily_pass(Game, t, int(e["day"]) + 1)
	var used := int(e["led"]["used"].get("scrap_copper", 0)) - used0
	var made := int(e["led"]["made"].get("copper_bars", 0)) - made0
	print("  %s over 6 days: smelter bought %d kg copper scrap, %d copper bars made (%d left in stock), wood used by the town %d" % [t["name"], used, made,
		int(e["stock"]["scrap_copper"]), int(e["led"]["used"].get("wood", 0)) - wood0])
	check(used > 0, "%s's smelter never bought the battle scrap" % t["name"])
	check(made >= used, "copper scrap used %d but only %d copper bars made" % [used, made])

# ---------------------------------------------------------------- the scrap price follows its stock
func _price_after(t: Dictionary, g: String, stock: int) -> float:
	var e: Dictionary = t["econ"]
	for i in 15:
		e["stock"][g] = stock
		e["dem"][g] = 5.0
		e["req"].erase(g)
		e["bdem"][g] = 5.0
		TownEcon.update_prices(t, 0)
	return float(e["price"][g])

func _test_price() -> void:
	var t := _town_of_race("human")
	if not t["econ"].has("bdem"):
		t["econ"]["bdem"] = {}
	var lo := _price_after(t, "scrap_copper", 5)
	var hi := _price_after(t, "scrap_copper", 2000)
	print("  copper scrap price in %s: %.1f with 5 kg in stock, %.1f with 2000 kg" % [t["name"], lo, hi])
	check(hi < lo, "copper scrap no cheaper with more in stock (%.1f vs %.1f)" % [hi, lo])
