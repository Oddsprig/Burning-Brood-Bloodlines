extends RefCounted
## v0.014 bronze and iron (Douglas 22:19-22:27): the smelter's bronze recipe (22 copper + 3 tin bars + fuel -> 25 bronze:
## 88% / 12% by mass) and the iron recipe (ore + fuel); weaponsmiths' and armourers' standing want for bronze and iron
## bars as real market demand; the bronze and iron research lines (bronze never orcs or goblins, elves slower than
## humans; iron every race at one rate); races without the know-how never smelt or work the metal but hold, sell and use
## the goods; coin conserved with it all running; deposits by city (each city its own mix, all four a rarity).
##   METAL_ONLY=deposits tools/test.sh tests/test_metal_tech.gd   (the deposits report alone)

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_metal_%d.json" % OS.get_process_id()
	if OS.get_environment("METAL_ONLY") == "deposits":
		_test_deposits()
		return fails
	_test_recipe_data()
	Game.new_game(2026)
	_quiet(Game.world)
	_test_smelting()
	_test_smith_targets()
	_test_race_rules()
	_test_hold_and_use()
	_test_screens()
	_test_coin()
	_test_deposits()
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

## The first town (by id) of a faction of this race.
func _town_of_race(race: String) -> Dictionary:
	var w: Dictionary = Game.world
	for tid in _ids(w):
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t) and Academy.faction_race(String(t.get("faction", ""))) == race:
			return t
	return {}

func _fid_of_race(race: String) -> String:
	for fid in Game.world["factions"]:
		if Academy.faction_race(String(fid)) == race:
			return String(fid)
	return ""

# ---------------------------------------------------------------- the recipes
func _bronze_recipe() -> Dictionary:
	for r in TownEcon.data()["businesses"]["smelter"]["recipes"]:
		if (r["out"] as Dictionary).has("bronze_bars") and (r["in"] as Dictionary).has("tin_bars"):
			return r
	return {}

func _test_recipe_data() -> void:
	var r := _bronze_recipe()
	check(not r.is_empty(), "no bronze recipe at the smelter")
	if r.is_empty():
		return
	var cu := float(r["in"].get("copper_bars", 0.0)); var sn := float(r["in"].get("tin_bars", 0.0))
	var out := float(r["out"]["bronze_bars"])
	check(absf(cu / (cu + sn) - 0.88) < 0.005 and absf(sn / (cu + sn) - 0.12) < 0.005, "bronze is not 88%% copper, 12%% tin by mass (%s copper, %s tin)" % [cu, sn])
	check(absf(cu + sn - out) < 0.001, "bronze bars out (%s) differ from the metal in (%s)" % [out, cu + sn])
	check(float(r["in"].get("wood", 0.0)) > 0.0, "bronze is cast without fuel")
	check(String(r.get("knowhow", "")) == "bronze", "bronze smelting not gated by bronze know-how")
	# one bronze path from copper and tin (no duplicate); scrap remelting is the only other way to bronze bars
	var n := 0
	for bt in TownEcon.data()["businesses"]:
		if String(bt).begins_with("_"):
			continue
		for r2 in TownEcon.data()["businesses"][bt]["recipes"]:
			if (r2.get("out", {}) as Dictionary).has("bronze_bars") and (r2.get("in", {}) as Dictionary).has("copper_bars"):
				n += 1
	check(n == 1, "%d recipes make bronze from copper (want one)" % n)
	var iron := {}
	for r3 in TownEcon.data()["businesses"]["smelter"]["recipes"]:
		if (r3["in"] as Dictionary).has("iron_ore"):
			iron = r3
	check(not iron.is_empty() and (iron["out"] as Dictionary).has("iron_bars") and float(iron["in"].get("wood", 0.0)) > 0.0, "no iron ore + fuel -> iron bars recipe")
	check(String(iron.get("knowhow", "")) == "iron", "iron smelting not gated by iron know-how")
	print("  bronze: %d copper + %d tin bars + %d wood -> %d bronze bars; iron: %d ore + %d wood -> %d bar" % [int(cu), int(sn),
		int(r["in"]["wood"]), int(out), int(iron["in"]["iron_ore"]), int(iron["in"]["wood"]), int(iron["out"]["iron_bars"])])

## A smelter row working one recipe on stocks we set; returns the stock change.
func _smelt(t: Dictionary, stock: Dictionary, days: int) -> Dictionary:
	var e: Dictionary = t["econ"]
	var D := TownEcon.data()
	var st: Dictionary = e["stock"]
	for g in ["copper_ore", "tin_ore", "iron_ore", "scrap_copper", "scrap_tin", "scrap_bronze", "scrap_iron", "scrap_steel",
			"iron_bars", "pig_iron", "flux", "copper_bars", "tin_bars", "wood", "bronze_bars", "steel_bars"]:
		st[g] = 0
	for g in stock:
		st[g] = int(stock[g])
	for g in ["bronze_bars", "iron_bars"]:
		e["need"][g] = 100000.0   # (room in the market: the output is never "full")
	e.erase("_aimu"); e.erase("_aimrest"); e.erase("_nomargin")
	var b := Businesses._row(e, "smelter", -1, 1, D)
	(e["biz"] as Array).pop_back()   # (a row outside the town's lists: only this test works it)
	b["till"] = 1.0e7
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var mt := float(mkt["till"])
	mkt["till"] = 1.0e7
	var before := st.duplicate()
	for i in days:
		Businesses._recipes(e, D, b, D["businesses"]["smelter"], 10.0, 1.0, 1.0, mkt, float(D["market"]["buy_share"]), {})
	mkt["till"] = mt
	var d := {}
	for g in st:
		if int(st[g]) != int(before.get(g, 0)):
			d[g] = int(st[g]) - int(before.get(g, 0))
	return d

func _test_smelting() -> void:
	var h := _town_of_race("human")
	var o := _town_of_race("orc")
	var g := _town_of_race("goblin")
	check(not h.is_empty() and not o.is_empty() and not g.is_empty(), "no human, orc or goblin town")
	if h.is_empty() or o.is_empty() or g.is_empty():
		return
	h["econ"]["knowhow"]["bronze"] = 100.0
	var d := _smelt(h, {"copper_bars": 500, "tin_bars": 500, "wood": 500}, 3)
	var made := int(d.get("bronze_bars", 0))
	print("  human smelter, 3 days of 10 hands: %s" % str(d))
	check(made > 0 and made % 25 == 0, "human smelter made %d bronze bars (want whole batches of 25)" % made)
	check(-int(d.get("copper_bars", 0)) * 25 == made * 22 and -int(d.get("tin_bars", 0)) * 25 == made * 3, "bronze used copper %d, tin %d for %d bars (want 22:3 per 25)" % [-int(d.get("copper_bars", 0)), -int(d.get("tin_bars", 0)), made])
	check(-int(d.get("wood", 0)) * 25 == made * 10, "bronze burned %d wood for %d bars (want 10 a batch)" % [-int(d.get("wood", 0)), made])
	# orcs and goblins: whatever their towns have heard of bronze, their smelters never make it
	for t in [o, g]:
		t["econ"]["knowhow"]["bronze"] = 100.0
		var d2 := _smelt(t, {"copper_bars": 500, "tin_bars": 500, "wood": 500}, 3)
		check(int(d2.get("bronze_bars", 0)) == 0 and int(d2.get("copper_bars", 0)) == 0, "%s smelted bronze (%s)" % [t["name"], str(d2)])
		check(Businesses.kh_of(t["econ"], "bronze") <= 0.0, "%s can use bronze know-how" % t["name"])
	# iron: every race smelts it at the start; a realm without iron know-how does not
	var di := _smelt(o, {"iron_ore": 100, "wood": 100}, 2)
	check(int(di.get("iron_bars", 0)) > 0, "orc smelter made no iron from ore (%s)" % str(di))
	var fk: Dictionary = h["econ"]["fkh"]
	var keep := float(fk.get("iron", 100.0))
	fk["iron"] = 0.0
	var dn := _smelt(h, {"iron_ore": 100, "wood": 100}, 2)
	check(int(dn.get("iron_bars", 0)) == 0, "iron smelted without iron know-how (%s)" % str(dn))
	fk["iron"] = keep

# ---------------------------------------------------------------- bar targets
func _test_smith_targets() -> void:
	var h := _town_of_race("human")
	var o := _town_of_race("orc")
	var e: Dictionary = h["econ"]
	e["knowhow"]["bronze"] = 60.0
	var bd := {}
	Businesses.smith_want(e, 10.0, bd)
	print("  smiths' want, 10 worker-days: human %s" % str(bd))
	check(absf(float(bd.get("bronze_bars", 0.0)) - 0.5 * 10.0 * 0.6) < 0.01, "human smiths' bronze want %.2f (want 3.0)" % float(bd.get("bronze_bars", 0.0)))
	check(float(bd.get("iron_bars", 0.0)) > 0.0, "human smiths want no iron bars")
	var bo := {}
	o["econ"]["knowhow"]["bronze"] = 60.0
	Businesses.smith_want(o["econ"], 10.0, bo)
	check(float(bo.get("bronze_bars", 0.0)) == 0.0, "orc smiths want bronze bars (%s)" % str(bo))
	check(float(bo.get("iron_bars", 0.0)) > 0.0, "orc smiths want no iron bars")
	# the want reaches the market: the day's business demand, then demand, the stockpile target (need) and the price
	var smiths := 0
	for b in e["biz"]:
		if b["type"] in ["weaponsmith", "armorsmith"] and not b.get("closed", false) and int(b["workers"]) + int(b.get("kw", 0)) > 0:
			smiths += 1
	check(smiths > 0, "no working smith in %s" % h["name"])
	e["stock"]["bronze_bars"] = 0
	e["stock"]["iron_bars"] = 0
	var p0 := float(e["price"]["bronze_bars"])
	var dem0 := float(e["dem"].get("bronze_bars", 0.0))
	for i in 6:
		TownEcon.daily_pass(Game, h, int(e["day"]) + 1)
	var bdem: Dictionary = e.get("bdem", {})
	print("  %s after 6 days: business want bronze %.2f iron %.2f; demand bronze %.2f -> %.2f, stockpile target %.1f; price %.0f -> %.0f" % [h["name"],
		float(bdem.get("bronze_bars", 0.0)), float(bdem.get("iron_bars", 0.0)), dem0, float(e["dem"].get("bronze_bars", 0.0)),
		float(e["need"].get("bronze_bars", 0.0)), p0, float(e["price"]["bronze_bars"])])
	check(float(bdem.get("bronze_bars", 0.0)) > 0.0 and float(bdem.get("iron_bars", 0.0)) > 0.0, "the smiths' bronze and iron want did not reach the market")
	check(float(e["need"].get("bronze_bars", 0.0)) > 0.0 and float(e["need"].get("iron_bars", 0.0)) > 0.0, "no stockpile target for bronze or iron bars")

# ---------------------------------------------------------------- race rules
func _test_race_rules() -> void:
	var w: Dictionary = Game.world
	var hf := _fid_of_race("human"); var ef := _fid_of_race("moon_elf"); var df := _fid_of_race("dwarf")
	var of := _fid_of_race("orc"); var gf := _fid_of_race("goblin")
	check(hf != "" and ef != "" and of != "" and gf != "", "a race's faction is missing")
	for fid in [of, gf]:
		check(float(Academy.state(w, fid)["kh"].get("bronze", -1.0)) == 0.0, "%s starts with bronze know-how" % fid)
		check(not Academy.race_may("bronze", Academy.faction_race(fid)), "%s may learn bronze" % fid)
		check(Academy.kh_after(fid, "bronze", 1.0e9) == 0.0, "%s gains bronze know-how from research" % fid)
		for L in Academy.active_lines(w, fid):
			check(String(L["knowhow"]) != "bronze", "%s's house works the bronze line" % fid)
	check(float(Academy.state(w, hf)["kh"]["bronze"]) >= 100.0, "humans do not start knowing bronze")
	if df != "":
		check(float(Academy.state(w, df)["kh"]["bronze"]) >= 100.0, "dwarves do not start knowing bronze")
	check(float(Academy.state(w, ef)["kh"]["bronze"]) == 0.0, "elves start knowing bronze")
	check(Academy.active_lines(w, ef).any(func(L): return String(L["knowhow"]) == "bronze"), "the elves' house does not work bronze")
	# equal funding = equal research points: elves get less know-how from them than humans would
	var lines := []
	for pts in [3000.0, 6000.0, 10000.0, 20000.0]:
		var kh_h := Academy.kh_from(pts, Academy.race_factor(hf, "bronze"), "bronze")
		var kh_e := Academy.kh_from(pts, Academy.race_factor(ef, "bronze"), "bronze")
		lines.append("%d pts: human %.0f, elf %.0f" % [int(pts), kh_h, kh_e])
		check(kh_e <= kh_h, "elves learn bronze faster than humans at %d research" % int(pts))
	check(Academy.race_factor(ef, "bronze") < Academy.race_factor(hf, "bronze"), "elves' bronze factor not below humans'")
	print("  bronze know-how from research: %s" % "; ".join(PackedStringArray(lines)))
	# the elves' house really researches bronze: a day of work raises its points
	var S := Academy.state(w, ef)
	var cap: Dictionary = w["towns"].get(String(w["factions"][ef].get("capital", "")), {})
	if TownEcon.has_econ(cap) and not Academy.biz_of(cap["econ"]).is_empty() and (Academy.biz_of(cap["econ"]).get("lead", []) as Array).size() >= 2:
		var p0 := float(S["pts"].get("bronze", 0.0))
		var mkt: Dictionary = cap["econ"]["biz"][int(cap["econ"]["mkt"])]
		Academy.day(Game, cap, cap["econ"], Academy.biz_of(cap["econ"]), 3.0, mkt, {})
		check(float(S["pts"].get("bronze", 0.0)) > p0, "the elves' house did no bronze research in a day")
	# a teaching floor: once the elves know a little bronze, their capital's smiths may start on it
	S["pts"]["bronze"] = 1.0e6
	S["kh"]["bronze"] = Academy.kh_after(ef, "bronze", 1.0e6)
	Academy.sync_towns(w, ef)
	if TownEcon.has_econ(cap):
		check(Businesses.kh_of(cap["econ"], "bronze") > 0.0, "an elf capital cannot work bronze after the realm learned it")
	# iron: every race, one rate, everyone starts knowing it
	var f0 := -1.0
	for fid in w["factions"]:
		if (w["factions"][fid].get("towns", []) as Array).is_empty():
			continue   # (monster bands are factions without towns or a research house)
		var race := Academy.faction_race(String(fid))
		check(Academy.race_may("iron", race), "%s may not learn iron" % race)
		var f := Academy.race_factor(String(fid), "iron")
		if f0 < 0.0:
			f0 = f
		check(f == f0, "%s learns iron at %.2f, others %.2f" % [race, f, f0])
		check(float(Academy.state(w, String(fid))["kh"].get("iron", 0.0)) >= 100.0, "%s does not start knowing iron" % fid)
	check(Academy.kh_from(5000.0, Academy.race_factor(of, "iron"), "iron") == Academy.kh_from(5000.0, Academy.race_factor(ef, "iron"), "iron"), "iron learned at different rates")

# ---------------------------------------------------------------- holding and using
func _test_hold_and_use() -> void:
	var o := _town_of_race("orc")
	var e: Dictionary = o["econ"]
	# a smith with only bronze bars stands idle for bars; he neither works them nor wastes them
	for g in ["copper_bars", "tin_bars", "iron_bars", "steel_bars"]:
		e["stock"][g] = 0
	e["stock"]["bronze_bars"] = 200
	(o["shop"] as Array).clear()
	var before := int(e["led"]["made"].get("arms_bronze", 0))
	for i in 3:
		TownEcon.daily_pass(Game, o, int(e["day"]) + 1)
	check(int(e["led"]["made"].get("arms_bronze", 0)) == before, "orc smiths worked bronze")
	for it0 in o["shop"]:
		check(it0.material != "bronze", "orc smiths put a bronze %s on the stalls" % it0.display_name())
	# bronze gear bought or looted: on the stalls, priced, sold, worn by an orc
	var pool := Businesses.gear_pool(String(o.get("culture", "orc")), "weapon")
	if not pool.is_empty():
		var it := Item.make(String(pool[0]), "bronze", 2)
		(o["shop"] as Array).append(it)
		check(Economy.base_value(o, it) > 0.0, "a bronze piece has no price in an orc town")
		TownEcon.daily_pass(Game, o, int(e["day"]) + 1)
		var kept := (o["shop"] as Array).has(it) or (o.get("armory_items", []) as Array).has(it)
		print("  a bronze %s in %s: %s" % [it.display_name(), o["name"], "still held" if kept else "bought or used up"])
	var u := Factory.make_troop(Game.rng, _fid_of_race("orc"), DB.factions[_fid_of_race("orc")]["troops"][0], 1)
	var bz := Item.make(String(pool[0]) if not pool.is_empty() else "arming_sword", "bronze", 2)
	u.equip["main_hand"] = bz
	check(u.equip["main_hand"] == bz and bz.wear == 0, "an orc cannot wear a bronze weapon")
	bz.wear = 2   # battered in battle; the gear system has no race rule on wear or mending
	check(bz.material == "bronze", "bronze piece changed material")

# ---------------------------------------------------------------- screens
func _test_screens() -> void:
	var ef := _fid_of_race("moon_elf")
	var of := _fid_of_race("orc")
	var el := "\n".join(PackedStringArray(RecData.research_lines(ef)))
	var ol := "\n".join(PackedStringArray(RecData.research_lines(of)))
	check(el.contains("Line bronze") and el.contains("Line iron"), "the elves' research card does not show the bronze and iron lines")
	check(ol.contains("Line bronze") and ol.contains("closed"), "the orcs' research card does not show bronze closed")
	print("  elf research card:\n    " + el.replace("\n", "\n    "))
	var h := _town_of_race("human")
	var got := false
	for line in TownEconTab.stores_lines(h):
		if String(line).to_lower().contains("bronze bars"):
			got = true
	check(got, "the market stores lines do not show bronze bars")
	check(RecData.goods_cat("bronze_bars") == "bars", "bronze bars not in the market's Metal goods")

# ---------------------------------------------------------------- coin
func _test_coin() -> void:
	Game.new_game(777)
	var worst := 0.0
	for d in 30:
		CampaignWorld.presim_step(Game, 1)
		var L: Dictionary = Game.world["coin"]
		worst = maxf(worst, absf(Barge.holdings(Game) - (float(L["cast"]) - float(L["melted"]) - float(L["drained"]))))
	var made := 0
	for tid in Game.world["towns"]:
		var e: Dictionary = Game.world["towns"][tid].get("econ", {})
		if not e.is_empty():
			made += int(e["led"]["made"].get("bronze_bars", 0))
	print("  30 days: bronze bars made %d; worst coin gap %.3f" % [made, worst])
	check(worst < 1.0, "coin not conserved with bronze smelting (gap %.2f)" % worst)

# ---------------------------------------------------------------- deposits by city
const DEP := ["copper_ore", "tin_ore", "iron_ore", "flux"]

func _test_deposits() -> void:
	var keep := WorldGen.gen_size
	for size in ["normal", "large"]:
		WorldGen.gen_size = size
		var towns := 0; var by_n := [0, 0, 0, 0, 0]; var each := {}; var combos := {}
		var tin_hill := 0; var tin_flat := 0; var tin_near := 0
		for sd in [2026, 99]:
			Game.new_game(sd)
			var w: Dictionary = Game.world
			var tins := []
			for tid in _ids(w):
				var t: Dictionary = w["towns"][tid]
				if not TownEcon.has_econ(t):
					continue
				towns += 1
				var deps: Dictionary = t["econ"]["deposits"]
				var have := []
				for k in DEP:
					if deps.has(k):
						have.append(k.replace("_ore", ""))
						each[k] = int(each.get(k, 0)) + 1
				by_n[have.size()] += 1
				var key := "+".join(PackedStringArray(have)) if not have.is_empty() else "none"
				combos[key] = int(combos.get(key, 0)) + 1
				if deps.has("tin_ore"):
					tins.append(t)
					if int(t["econ"]["terrain"]["hill_cells"]) > 0:
						tin_hill += 1
					else:
						tin_flat += 1
			# clustering: a tin town's nearest other tin town, against the average spacing of towns
			for a in tins:
				var best := INF
				for b in tins:
					if a != b:
						best = minf(best, (a["pos"] as Vector2).distance_to(b["pos"]))
				if best < 0.2 * float(WorldGen.W * WorldGen.CELL):
					tin_near += 1
		var ks: Array = combos.keys()
		ks.sort_custom(func(x, y): return int(combos[x]) > int(combos[y]))
		var cl := []
		for k in ks:
			cl.append("%s %d" % [k, int(combos[k])])
		print("  deposits, %s (2 worlds, %d cities): copper %d, tin %d, iron %d, flux %d; by count 0:%d 1:%d 2:%d 3:%d 4:%d" % [size, towns,
			int(each.get("copper_ore", 0)), int(each.get("tin_ore", 0)), int(each.get("iron_ore", 0)), int(each.get("flux", 0)),
			by_n[0], by_n[1], by_n[2], by_n[3], by_n[4]])
		print("    combinations: %s" % ", ".join(PackedStringArray(cl)))
		print("    tin cities in hills %d, on the flat %d; with another tin city within a fifth of the map %d" % [tin_hill, tin_flat, tin_near])
		for k in DEP:
			check(int(each.get(k, 0)) > 0, "%s: no city has %s" % [size, k])
			check(int(each.get(k, 0)) < towns * 0.7, "%s: %s in %d of %d cities (nearly everywhere)" % [size, k, int(each.get(k, 0)), towns])
		check(int(each.get("tin_ore", 0)) < int(each.get("copper_ore", 0)), "%s: tin not rarer than copper" % size)
		check(float(by_n[4]) <= maxf(1.0, towns * 0.03), "%s: %d of %d cities hold all four deposits (want a rarity)" % [size, by_n[4], towns])
		check(by_n[1] + by_n[2] > by_n[3] + by_n[4], "%s: more cities with three or four deposits than with one or two" % size)
		check(by_n[1] + by_n[2] >= int(towns * 0.5), "%s: only %d of %d cities have one or two deposits" % [size, by_n[1] + by_n[2], towns])
	WorldGen.gen_size = keep
