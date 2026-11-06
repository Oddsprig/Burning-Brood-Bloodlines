extends RefCounted
## Driven native production/transactions only. Normal + one-day settings;
## no generated world, elapsed campaign, real save, or battle is needed.
## Runtime status: UNRUN; root owns the isolated headless Test Bridge run.

class FixtureGame:
	extends RefCounted
	signal changed
	var world: Dictionary = {}
	var rep: Dictionary = {}
	var gold := 100000000
	var stash: Array = []
	var location := "forge088"
	var day := 1.0

var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", why)

func near(a: float, b: float) -> bool:
	return absf(a - b) < 0.000001

func run(_tree: SceneTree) -> int:
	var saved_world: Dictionary = Game.world
	var saved_rep: Dictionary = Game.rep
	var saved_size := WorldGen.gen_size
	var saved_history := CampaignWorld.presim_span_days
	var saved_gold_gone := TownEcon.gold_gone
	Game.world = {}; Game.rep = {}
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	_data_and_starts()
	_ladder_and_reservation()
	_missing_inputs_and_money()
	_market_limits_and_quotes()
	_fuel_alternatives()
	_manufacture_rules()
	_quality_and_skill()
	_saved_continuation()
	_import_trade_use_repair()
	Game.world = saved_world; Game.rep = saved_rep
	WorldGen.gen_size = saved_size
	CampaignWorld.presim_span_days = saved_history
	TownEcon.gold_gone = saved_gold_gone
	print("Steel smelting v088: %d checks, %d failures" % [checks, fails])
	return fails

func _recipe(output: String, input: String) -> Dictionary:
	for r in TownEcon.data()["businesses"]["smelter"]["recipes"]:
		if r["out"].has(output) and r["in"].has(input): return r
	return {}

func _fixture(kh: float = 100.0, fid: String = "dwarf_holds", culture: String = "middle") -> Dictionary:
	var d := TownEcon.data()
	var e := {"v": 1, "faction": fid, "culture": culture, "day": 1, "knowhow": {"bronze": 100.0},
		"fkh": {"steel": kh, "iron": 100.0, "bronze": 100.0}, "stock": {}, "barn": {}, "price": {}, "need": {},
		"stats": {"sales": 0.0}, "led": {"made": {}, "used": {}}, "treasury": 123.0, "fams": [], "specialties": []}
	for g in d["goods"]:
		e["stock"][g] = 0; e["price"][g] = float(d["goods"][g]["price"]); e["need"][g] = 10000.0
	var b := {"id": 0, "type": "smelter", "owner": -1, "workers": 1, "kw": 0, "cap": 1,
		"wage": 95.0, "till": 100000000.0, "tools": 1, "tw": 0.0, "closed": false, "carry": 0.0, "oc": {}, "state": "busy", "why": ""}
	var m := {"id": 1, "type": "market", "till": 100000000.0, "spend": 0.0}
	e["biz"] = [b, m]; e["mkt"] = 1
	var town := {"id": "forge088", "name": "Driven forge", "faction": fid, "culture": culture,
		"size": 1, "wealth": 3, "pos": Vector2.ZERO, "econ": e, "shop": [], "armory_items": []}
	return {"town": town, "e": e, "b": b, "m": m}

func _stock(x: Dictionary, amounts: Dictionary) -> void:
	for g in amounts: x["e"]["stock"][g] = int(amounts[g])

func _coins(x: Dictionary) -> float:
	var total := float(x["e"]["treasury"])
	for b in x["e"]["biz"]: total += float(b["till"])
	for f in x["e"]["fams"]: total += float(f["purse"])
	return total

func _smelt(x: Dictionary, wd: float = 12.0, only: Dictionary = {}) -> void:
	var d := TownEcon.data()
	var t: Dictionary = d["businesses"]["smelter"] if only.is_empty() else {"recipes": [only]}
	Businesses._recipes(x["e"], d, x["b"], t, wd, 1.0, 1.0, x["m"], float(d["market"]["buy_share"]), {})

func _data_and_starts() -> void:
	var iron := _recipe("iron_bars", "iron_ore")
	var pig := _recipe("pig_iron", "iron_bars")
	var steel := _recipe("steel_bars", "pig_iron")
	check(not iron.is_empty() and not pig.is_empty() and not steel.is_empty(), "the three native furnace steps exist")
	if iron.is_empty() or pig.is_empty() or steel.is_empty(): return
	check(iron["in"] == {"iron_ore": 2.0, "wood": 1.0} and iron["out"] == {"iron_bars": 1.0}, "iron uses real ore and fuel")
	check(pig["in"] == {"iron_bars": 1.0, "flux": 1.0, "wood": 1.0} and pig["out"] == {"pig_iron": 1.0}, "pig iron uses counted iron, flux and fuel")
	check(steel["in"] == {"pig_iron": 1.0, "iron_bars": 1.0, "flux": 1.0, "wood": 1.0} and steel["out"] == {"steel_bars": 2.0}, "the final heat conserves its two kilograms of iron")
	check(iron.get("knowhow", "") == "iron" and pig.get("knowhow", "") == "steel" and steel.get("knowhow", "") == "steel", "each stage uses its native knowledge gate")
	check(Academy.start_kh("dwarf_holds", "steel") == 100.0, "dwarves start at full steel mastery")
	for fid in ["middle_kingdom", "northern_clans", "eastern_khanate", "moon_court", "orc_horde", "goblin_warren"]:
		check(Academy.start_kh(fid, "steel") == 0.0, fid + " starts without steel manufacture")
	for fid in ["orc_horde", "goblin_warren"]:
		check(Academy.kh_after(fid, "steel", 1.0e12) == 0.0, fid + " cannot research steel even with arbitrary accumulated points")
	check(Academy.best_quality(0.0) == -1 and Academy.best_quality(100.0) == 5, "zero knowledge makes no steel; mastery unlocks six ordinary qualities")

func _ladder_and_reservation() -> void:
	var x := _fixture()
	_stock(x, {"iron_ore": 40, "wood": 200, "flux": 40, "copper_ore": 100, "copper_bars": 44, "tin_bars": 6})
	var coins := _coins(x)
	_smelt(x, 2.0)
	var st: Dictionary = x["e"]["stock"]
	check(int(st["iron_bars"]) == 6 and int(st["iron_ore"]) == 28, "steel-capable furnace starts with real iron despite feasible bronze and copper")
	_smelt(x)
	check(int(st["pig_iron"]) == 3 and int(st["iron_bars"]) == 3, "pig heat reserves matching iron instead of consuming the whole iron bin")
	_smelt(x)
	check(int(st["steel_bars"]) == 6 and int(st["pig_iron"]) == 0 and int(st["iron_bars"]) == 0, "the next heat completes the reserved steel pairs")
	check(int(st["wood"]) == 188 and int(st["flux"]) == 34, "six steel kg from ore burn twelve fuel and six flux: twice iron's fuel per kg")
	check(int(st["copper_bars"]) == 44 and int(st["tin_bars"]) == 6 and int(st["copper_ore"]) == 100, "steel heats do not consume unrelated metal inputs")
	var led: Dictionary = x["e"]["led"]
	check(int(led["made"].get("iron_bars", 0)) == 6 and int(led["made"].get("pig_iron", 0)) == 3 and int(led["made"].get("steel_bars", 0)) == 6, "all three actual outputs enter the native ledger")
	check(int(led["used"].get("iron_ore", 0)) == 12 and int(led["used"].get("iron_bars", 0)) == 6 and int(led["used"].get("pig_iron", 0)) == 3 and int(led["used"].get("wood", 0)) == 12 and int(led["used"].get("flux", 0)) == 6, "every intermediate and fuel debit is booked exactly once")
	check(near(coins, _coins(x)), "all three owner/market transactions conserve coin")
	var short := _fixture()
	_stock(short, {"iron_bars": 1, "wood": 10, "flux": 10})
	_smelt(short, 12.0, _recipe("pig_iron", "iron_bars"))
	check(int(short["e"]["stock"]["iron_bars"]) == 1 and int(short["e"]["stock"]["pig_iron"]) == 0, "one unpaired iron bar waits instead of becoming stranded pig iron")

func _missing_inputs_and_money() -> void:
	for pair in [["iron_bars", "iron_ore"], ["pig_iron", "iron_bars"], ["steel_bars", "pig_iron"]]:
		var r := _recipe(String(pair[0]), String(pair[1]))
		for missing in r["in"]:
			var x := _fixture()
			for g in r["in"]: x["e"]["stock"][g] = 20
			x["e"]["stock"][missing] = 0
			var before: Dictionary = x["e"]["stock"].duplicate()
			var coins := _coins(x)
			_smelt(x, 12.0, r)
			check(x["e"]["stock"] == before and near(coins, _coins(x)), "%s cannot run without %s, debit other materials or create output" % [pair[0], missing])
	for payer in ["b", "m"]:
		var x := _fixture()
		_stock(x, {"iron_bars": 20, "pig_iron": 20, "wood": 20, "flux": 20})
		x[payer]["till"] = 0.0
		var before: Dictionary = x["e"]["stock"].duplicate()
		var coins := _coins(x)
		_smelt(x)
		check(x["e"]["stock"] == before and near(coins, _coins(x)), "no steel or material debit when the %s cannot pay" % payer)

func _market_limits_and_quotes() -> void:
	for mode in ["rest", "full"]:
		var x := _fixture()
		_stock(x, {"iron_bars": 8, "pig_iron": 8, "wood": 100, "flux": 20, "copper_bars": 44, "tin_bars": 6})
		if mode == "rest": x["e"]["_aimrest"] = {"steel_bars": true}
		else:
			x["e"]["need"]["steel_bars"] = 0.0; x["e"]["stock"]["steel_bars"] = 20
		_smelt(x)
		check(int(x["e"]["stock"]["bronze_bars"]) > 0 and int(x["e"]["stock"]["pig_iron"]) == 8 and int(x["e"]["stock"]["iron_bars"]) == 8, "existing bronze priority resumes while steel is " + mode)
	var quoted := _fixture()
	_stock(quoted, {"iron_bars": 8, "pig_iron": 8, "wood": 100, "flux": 20, "copper_bars": 44, "tin_bars": 6})
	quoted["e"]["_aimu"] = {"steel_bars": 12.0}
	var before: Dictionary = quoted["e"].duplicate(true)
	var d := TownEcon.data()
	var choice := Businesses._recipe_choice(quoted["e"], d, quoted["b"], d["businesses"]["smelter"], 1.0, {}, false)
	var cash := Businesses.operating_cash(quoted["e"], quoted["b"], 0.0)
	check(quoted["e"] == before and cash >= Businesses._batch_cost(quoted["e"], _recipe("steel_bars", "pig_iron")["in"]), "steel choice and a funded one-batch cash quote leave the live books unchanged")
	check(choice["best"].get("out", {}).has("steel_bars"), "owner quote selects the same final steel heat as production")
	quoted["e"]["fkh"]["steel"] = 0.0
	_smelt(quoted)
	check(int(quoted["e"]["stock"]["steel_bars"]) == 0 and int(quoted["e"]["stock"]["bronze_bars"]) > 0, "a realm without steel knowledge retains working bronze production")

func _fuel_alternatives() -> void:
	for cheap_charcoal in [true, false]:
		var x := _fixture()
		_stock(x, {"iron_bars": 8, "pig_iron": 8, "wood": 40, "charcoal": 40, "flux": 40})
		x["e"]["price"]["wood"] = 100.0 if cheap_charcoal else 1.0
		x["e"]["price"]["charcoal"] = 1.0 if cheap_charcoal else 100.0
		var coin := _coins(x)
		_smelt(x, 2.0)
		var used := "charcoal" if cheap_charcoal else "wood"
		var kept := "wood" if cheap_charcoal else "charcoal"
		var produced := int(x["e"]["stock"]["steel_bars"])
		check(produced > 0 and int(x["e"]["stock"][kept]) == 40, "preferred steel heats retain the cheaper feasible fuel choice from087")
		check(40 - int(x["e"]["stock"][used]) == produced / 2 and int(x["e"]["led"]["used"].get(used, 0)) == produced / 2, "steel spends and books exactly the selected heat's fuel")
		check(near(coin, _coins(x)), "both fuel alternatives preserve finite owner/market coin")

func _manufacture_rules() -> void:
	for fid in ["middle_kingdom", "moon_court", "orc_horde", "goblin_warren"]:
		var x := _fixture(0.0, fid)
		_stock(x, {"iron_bars": 20, "pig_iron": 20, "wood": 20, "flux": 20, "steel_bars": 100})
		if fid in ["orc_horde", "goblin_warren"]: x["e"]["fkh"]["steel"] = 100.0
		var before: Dictionary = x["e"]["stock"].duplicate()
		_smelt(x, 12.0, _recipe("steel_bars", "pig_iron"))
		_smelt(x, 12.0, _recipe("pig_iron", "iron_bars"))
		check(Businesses.kh_of(x["e"], "steel") == 0.0 and x["e"]["stock"] == before, fid + " cannot manufacture pig iron or steel, including from a stale full mirror")
		x["e"]["stock"]["iron_bars"] = 0
		x["b"]["type"] = "weaponsmith"
		_forge(x, 8, 15.0)
		check((x["town"]["shop"] as Array).is_empty() and int(x["e"]["stock"]["steel_bars"]) == 100, fid + " cannot forge new gear out of imported steel bars")
	var maker := _fixture(100.0, "dwarf_holds", "orc")
	_stock(maker, {"iron_bars": 2, "wood": 2, "flux": 2})
	_smelt(maker); _smelt(maker)
	check(int(maker["e"]["stock"]["steel_bars"]) == 2, "manufacturing knowledge follows the faction rather than a captured town's old culture")

func _forge(x: Dictionary, count: int, skill: float) -> void:
	var d := TownEcon.data()
	var t: Dictionary = d["businesses"]["weaponsmith"]
	x["b"]["type"] = "weaponsmith"; x["b"]["skill"] = skill
	var rng := RandomNumberGenerator.new(); rng.seed = 880123
	Businesses._arms(null, x["town"], x["e"], d, x["b"], t, (float(count) + 0.01) / float(t["rate"]), 1.0, 1.0, rng, x["m"], {})

func _quality_and_skill() -> void:
	var high_total := 0
	for cap in range(6):
		var kh := float(cap) * (100.0 / 6.0) + 1.0
		check(Academy.best_quality(kh) == cap, "knowledge unlocks ordinary steel tier %d" % cap)
		var x := _fixture(kh, "middle_kingdom")
		_stock(x, {"steel_bars": 10000, "wood": 10000})
		var coins := _coins(x)
		_forge(x, 64, 15.0)
		var items: Array = x["town"]["shop"]
		check(items.size() == 64, "steel forge completes counted pieces at tier %d" % cap)
		var best := -1
		var inputs := {}
		for it in items:
			check(it.material == "steel" and it.quality <= cap, "actual skill roll respects faction's tier-%d steel ceiling" % cap)
			best = maxi(best, it.quality)
			if cap == 5: high_total += it.quality
			for g in Businesses.gear_inputs(it.tid, it.material):
				inputs[g] = int(inputs.get(g, 0)) + int(Businesses.gear_inputs(it.tid, it.material)[g])
		check(best == cap, "a skilled smith can reach unlocked steel tier %d" % cap)
		for g in inputs: check(int(x["e"]["stock"][g]) == 10000 - int(inputs[g]), "actual steel gear spends each native %s input" % g)
		check(near(coins, _coins(x)), "steel gear production conserves coin at tier %d" % cap)
	var novice := _fixture(100.0, "middle_kingdom")
	_stock(novice, {"steel_bars": 10000, "wood": 10000})
	_forge(novice, 64, 0.0)
	var low_total := 0
	for it in novice["town"]["shop"]: low_total += it.quality
	check(low_total < high_total, "full faction knowledge does not replace the smith's own skill")

func _same_whole_counts(a: Dictionary, b: Dictionary) -> bool:
	# JSON numbers load as floats. Validate whole, finite physical counts before
	# comparing their exact values; a fractional or missing count must still fail.
	if a.size() != b.size(): return false
	for key in a:
		if not b.has(key): return false
		var av := float(a[key]); var bv := float(b[key])
		if not is_finite(av) or not is_finite(bv) or av < 0 or bv < 0: return false
		if av != float(int(av)) or bv != float(int(bv)) or int(av) != int(bv): return false
	return true

func _saved_continuation() -> void:
	var original := _fixture(35.5, "middle_kingdom")
	_stock(original, {"iron_bars": 8, "wood": 20, "flux": 20})
	_smelt(original)
	var decoded: Variant = JSON.parse_string(JSON.stringify(original["e"]))
	check(decoded is Dictionary, "mid-ladder economy serializes as native plain data")
	if not (decoded is Dictionary): return
	var loaded := _fixture()
	loaded["e"] = decoded
	loaded["town"]["econ"] = decoded
	loaded["b"] = decoded["biz"][0]; loaded["m"] = decoded["biz"][1]
	_smelt(original); _smelt(loaded)
	check(_same_whole_counts(original["e"]["stock"], loaded["e"]["stock"]) and _same_whole_counts(original["e"]["led"]["made"], loaded["e"]["led"]["made"]) and _same_whole_counts(original["e"]["led"]["used"], loaded["e"]["led"]["used"]), "restoring between pig iron and steel preserves exact stocks and ledger continuation")
	check(near(_coins(original), _coins(loaded)) and near(float(original["b"]["carry"]), float(loaded["b"]["carry"])), "restored final heat preserves cash and fractional work")
	check(near(Businesses.kh_of(loaded["e"], "steel"), 35.5), "restored furnace retains the faction knowledge mirror")

func _import_trade_use_repair() -> void:
	for fid in ["orc_horde", "goblin_warren"]:
		var x := _fixture(0.0, fid)
		x["b"]["type"] = "weaponsmith"
		var it := Item.make("arming_sword", "steel", 4)
		it.mark = {"n": "Dwarf smith", "b": 7, "t": "hold088", "r": "dwarf"}
		it.wear = 2; it.dull = 0.375
		x["town"]["shop"] = [it]
		var game := FixtureGame.new()
		game.rep[fid] = 0; Game.rep[fid] = 0
		game.world = {"towns": {"forge088": x["town"]}, "wars": []}
		var coins := float(game.gold) + _coins(x)
		check(Economy.buy(game, x["town"], it) and game.stash == [it] and (x["town"]["shop"] as Array).is_empty(), fid + " can buy the exact imported steel item")
		check(Economy.sell(game, x["town"], it) > 0 and x["town"]["shop"] == [it] and game.stash.is_empty(), fid + " can sell that same steel identity")
		check(near(coins, float(game.gold) + _coins(x)), "imported steel trade conserves payer and market coins")
		var restored := Item.from_dict(JSON.parse_string(JSON.stringify(it.to_dict())))
		check(restored.uid == it.uid and restored.material == "steel" and restored.quality == 4 and restored.mark == it.mark and restored.wear == 2 and near(restored.dull, 0.375), "steel identity, provenance and battle damage survive native item save restoration")
		var u := Unit.new(); u.uid = 880001; u.race = Academy.faction_race(fid); u.equip["main_hand"] = it
		check(u.weapon() == it and TroopUpkeep._kit_item(it), fid + " can wield imported steel through the native equipment API")
		var family := Families._blank(0)
		family["m"] = 1; family["homes"] = 1; family["purse"] = 1000000.0
		family["house_budget"] = {"yearly": 100000000.0, "troops": [], "spent": 0.0}
		x["e"]["fams"] = [family]
		game.world["troop_upkeep"] = {"v": 1, "houses": {}, "units": {str(u.uid): {"wear": 2, "slots": {"main_hand": 0}}}}
		var saved_live: Dictionary = TroopUpkeep._live
		TroopUpkeep._live = {str(u.uid): u}
		var row := {"repair": 110.0}
		coins = _coins(x)
		var paid := TroopUpkeep._pay_due(game, x["town"], x["e"], family, row)
		check(near(paid, 110.0) and near(float(row["repair"]), 0.0) and it.wear == 0, fid + " pays its ordinary smith to repair the existing steel piece")
		check(u.weapon() == it and it.quality == 4 and near(it.dull, 0.375) and int(x["e"]["stock"]["steel_bars"]) == 0 and near(coins, _coins(x)), "repair preserves item identity, native damage fields, stock and coin conservation")
		check(TroopUpkeep._pay_due(game, x["town"], x["e"], family, row) == 0.0, "paid repair cannot charge for the same damage twice")
		TroopUpkeep._live = saved_live
