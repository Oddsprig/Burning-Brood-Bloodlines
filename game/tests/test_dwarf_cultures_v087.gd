extends RefCounted
## UNRUN: root owns runtime verification. Normal, one history day, isolated save.
## --test=res://tests/test_dwarf_cultures_v087.gd --watchdog=180
## Driven stock/price/liquidity fixtures exercise native paid transactions;
## they do not claim that an unmodified campaign has reached trade equilibrium.
var checks := 0
var fails := 0
var holds: Array = []
var humans := {}
var moved_uids: Array = []
var wedding_uids: Array = []
var expected_people := {}
var expected_links := {}
var exported_arm_uid := -1
var exported_arm_town := ""

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL v087: ", message)

func near(a: float, b: float, message: String) -> void:
	check(absf(a - b) < 0.001, "%s (%.9f / %.9f)" % [message, a, b])

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	var old_path: String = Game.SAVE_PATH
	var old_steppe := WorldGen.steppe_enabled
	var old_size := WorldGen.gen_size
	var old_stretch := WorldGen.gen_stretch
	var old_days := CampaignWorld.presim_span_days
	var old_creatures := Monsters.new_world_creatures
	var old_town_scale = EconGen.town_scale_override
	Game.wait_save()
	Game.SAVE_PATH = "user://test_dwarf_cultures_v087_%d.json" % OS.get_process_id()
	WorldGen.gen_size = "normal"
	WorldGen.gen_stretch = WorldGen.STRETCH
	WorldGen.steppe_enabled = true
	CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = false
	EconGen.town_scale_override = null
	var generation := Game.new_game_begin(87087)
	while not Game.new_game_slice(generation, 8000): await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	check(DevTools.choose_house(Game, func(c): return Game.world["towns"][c["town_id"]]["culture"] == "middle") != "", "a native Middle house is selected")
	_geography()
	_ore_and_flat_controls()
	_production()
	if not holds.is_empty() and humans.has("middle"):
		_trade(holds[0], humans["middle"])
		_recruit_rules(holds[0])
	if humans.size() == 3 and not holds.is_empty():
		_movement()
		_marriages()
	_round_trip()
	WorldGen.steppe_enabled = old_steppe
	WorldGen.gen_size = old_size
	WorldGen.gen_stretch = old_stretch
	CampaignWorld.presim_span_days = old_days
	Monsters.new_world_creatures = old_creatures
	EconGen.town_scale_override = old_town_scale
	Game.SAVE_PATH = old_path
	print("v087 dwarves/cultures: %d checks, %d failures, %d ms" % [checks, fails, Time.get_ticks_msec() - started])
	return fails

func _geography() -> void:
	var w: Dictionary = Game.world
	check(WorldGen.gen_size == "normal" and CampaignWorld.presim_span_days == 1, "Normal with one-day history is used")
	for t: Dictionary in w["towns"].values():
		var e: Dictionary = t["econ"]
		var culture := str(t["culture"])
		if culture in ["middle", "northern", "eastern"]:
			if not humans.has(culture) or int(t["size"]) > int(humans[culture]["size"]): humans[culture] = t
		if culture == "eastern":
			var c := WorldGen.cell_of(t["pos"])
			check(str(t["faction"]) == "eastern_khanate" and str(e["culture"]) == "eastern" and Persons.race_of(e) == "human", "Eastern towns use the existing human culture/faction")
			check(w["terrain"][WorldGen.idx(c.x, c.y)] in ["g", "h", "b"] and WorldGen.dryness_at(t["pos"]) >= float(TownEcon.data()["dry_min"]), "every Eastern settlement is on dry open land")
			check(e["climate"] == "dry", "the Eastern economy uses the native dry climate; crop rotation may display mixed crops")
		if culture != "dwarf": continue
		holds.append(t)
		check(str(t["specialty"]) == "mining" and str(t["region"]) == "holds", "a hold remains the existing mining settlement")
		check(float(e["deposits"].get("iron_ore", 0.0)) >= 1.0, "each generated hold has good iron")
		var c := WorldGen.cell_of(t["pos"])
		var peaks := 0
		var rr := roundi(4 * WorldGen.K)
		for y in range(maxi(0, c.y - rr), mini(WorldGen.H, c.y + rr + 1)):
			for x in range(maxi(0, c.x - rr), mini(WorldGen.W, c.x + rr + 1)):
				if w["terrain"][WorldGen.idx(x, y)] == "m": peaks += 1
		check(float(peaks) / (WorldGen.K * WorldGen.K) >= WorldGen.HOLD_MIN_PEAKS, "the hold is surrounded by real mountain terrain")
		check(not (t.get("road_links", []) as Array).is_empty(), "the hold joins the native road network")
		check(not Caravans.trade_partners(w, t).is_empty(), "a generated hold has a diplomatically open road partner")
		for fid in w["factions"]:
			if str(fid) == str(t["faction"]): continue
			if bool(DB.factions.get(fid, {}).get("wild", false)): continue # beasts/outlaws have no political diplomacy row
			check(w["diplo"]["pairs"].has(Diplomacy.pair_key(str(t["faction"]), str(fid))), "the hold has ordinary diplomacy with %s" % fid)
		check(not CampaignWorld.is_hostile(Game, str(t["faction"])), "dwarves are not automatically hostile to the selected Middle house")
		var acres := 0.0
		for f in e["fams"]:
			if not f.get("gone", false): acres += float(f["land"].get("grain", 0))
		var annual := acres * CropRotation.mean_yield(e) * float(TownEcon.data()["climates"][e["climate"]]["grain_yield"])
		var mouths := EconGen.food_eaters(e) * float(Barge.diet(e)["grain"]) * EconGen.YEAR_DAYS
		check(annual < mouths, "the hold's actual fields cannot cover annual grain meals, before brewing")
		# Observe the natural opening separately, before any trade fixtures. Base
		# prices after one day need not yet fund a profitable caravan.
		var profitable := 0
		for link in Caravans.trade_partners(w, t):
			if Caravans.trade_value(t, w["towns"][link["id"]], w) > 0.0: profitable += 1
		print("v087 natural opening: %s, grain acres %.0f, annual meals %.0f / %.0f, profitable road quotes %d" % [t["name"], acres, annual, mouths, profitable])
		var trades := {}
		for b in e["biz"]:
			trades[str(b["type"])] = true
			if b["type"] == "mine" and b.get("ore", "") == "iron_ore":
				check(float(b["rich"]) >= 1.0, "the real iron mine works the hold's rich seam")
		for kind in ["mine", "smelter", "carpenter", "weaponsmith", "armorsmith", "quarry", "builder"]:
			check(trades.has(kind), "the hold uses an ordinary %s business" % kind)
		check(Businesses.kh_of(e, "steel") == 100.0 and Persons.race_of(e) == "dwarf", "existing dwarf biology and full steel knowledge remain native")
		var P := Plots.of(t)
		check(not (P.get("bld", []) as Array).is_empty(), "the hold has real state building plots")
	check(not holds.is_empty() and holds.size() <= maxi(1, roundi(WorldGen.HOLDS_PER_TF * WorldGen.TF)), "holds exist within their existing size-scaled count")
	check(humans.size() == 3, "all three human cultures are present with Eastern generation enabled")
	check(int(People.ages("dwarf")["lifespan"]) >= 150, "dwarf life expectancy uses the long-lived race row")
	var db := Persons.bearing("dwarf")
	var hb := Persons.bearing("human")
	check(float(db[0]) + float(db[1]) + float(db[2]) > float(hb[0]) + float(hb[1]) + float(hb[2]), "dwarf birth intervals follow slower native biology")
	var materials: Dictionary = TownEcon.data()["cultures"]["dwarf"]["home"]["materials"]
	check(float(materials.get("stone", 0)) > float(materials.get("wood", 0)), "existing dwarf homes are predominantly stone")

func _ore_and_flat_controls() -> void:
	for seed_v in range(87, 103):
		var w := {"seed": seed_v, "tin_belts": []}
		var t := {"id": "ore-control", "culture": "dwarf", "pos": Vector2(1200, 900)}
		var a := EconGen._deposits(w, t, 12, "mining")
		check(float(a.get("iron_ore", 0.0)) >= 1.0 and a == EconGen._deposits(w, t, 12, "mining"), "hold iron is rich and deterministic at seed %d" % seed_v)
	var n := WorldGen.W * WorldGen.H
	var flat := {"terrain": "g".repeat(n), "region": "0".repeat(n)}
	var land := PackedByteArray(); land.resize(n); land.fill(1)
	var towns := {}
	var rng := RandomNumberGenerator.new(); rng.seed = 87
	WorldGen.place_holds(flat, rng, land, towns, [], {}, 0)
	check(towns.is_empty(), "flat land never receives a forced or fabricated mountain hold")
	var enabled := WorldGen.steppe_enabled
	WorldGen.steppe_enabled = false
	check(WorldGen.region_faction("southeast") == "goblin_warren", "the existing optional Eastern-world toggle is retained")
	WorldGen.steppe_enabled = enabled

func _production() -> void:
	var D := TownEcon.data()
	var e := {"culture": "dwarf", "fams": [Families._blank(0)], "biz": [], "stock": {}, "price": {}, "need": {},
		"knowhow": {}, "fkh": {"iron": 100.0, "steel": 100.0}, "stats": {"sales": 0.0}, "led": {"made": {}, "used": {}, "spoil": {}}}
	for g in D["goods"]:
		e["stock"][g] = 0; e["price"][g] = float(D["goods"][g]["price"]); e["need"][g] = 1000.0
	var market := Businesses._row(e, "market", 0, 1, D)
	e["mkt"] = market["id"]
	var burner := Businesses._row(e, "charcoal_burner", 0, 1, D)
	var smelter := Businesses._row(e, "smelter", 0, 1, D)
	var carpenter := Businesses._row(e, "carpenter", 0, 1, D)
	var builder := Businesses._row(e, "builder", 0, 1, D)
	market["till"] = 100000.0; burner["till"] = 10000.0; smelter["till"] = 10000.0
	carpenter["till"] = 10000.0; builder["till"] = 10000.0
	var share := float(D["market"]["buy_share"])
	var coin := _business_cash(e)
	var demand := {}
	Businesses._recipes(e, D, burner, D["businesses"]["charcoal_burner"], 1.0, 1.0, 1.0, market, share, demand)
	check(int(e["stock"]["charcoal"]) == 0, "a charcoal burner without wood makes nothing")
	check(float(demand.get("wood", 0.0)) > 0.0, "missing kiln inputs enter the ordinary market demand")
	e["stock"]["wood"] = 24
	var spent := Businesses._recipes(e, D, burner, D["businesses"]["charcoal_burner"], 1.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["charcoal"]) == 12 and int(e["stock"]["wood"]) == 0 and spent > 0.0, "counted charcoal consumes two real wood loads per sack and pays for inputs")
	check(int(e["led"]["used"].get("wood", 0)) == 24 and int(e["led"]["made"].get("charcoal", 0)) == 12, "charcoal conversion is recorded in the existing production ledger")
	near(_business_cash(e), coin, "charcoal production conserves coin")
	e["stock"]["iron_ore"] = 6
	Businesses._recipes(e, D, smelter, D["businesses"]["smelter"], 1.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["iron_ore"]) == 0 and int(e["stock"]["charcoal"]) == 9 and int(e["stock"]["iron_bars"]) == 3, "an ordinary furnace can pay for ore and charcoal when wood is absent")
	check(int(e["led"]["used"].get("iron_ore", 0)) == 6 and int(e["led"]["used"].get("charcoal", 0)) == 3, "smelting debits both counted inputs in the native ledger")
	near(_business_cash(e), coin, "charcoal smelting conserves coin")
	e["stock"]["wood"] = 1
	spent = Businesses._recipes(e, D, carpenter, D["businesses"]["carpenter"], 1.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["iron_bars"]) == 2 and int(e["stock"]["wood"]) == 0 and int(e["stock"]["tools"]) == 1 and spent > 0.0, "the existing tool trade pays for real smelted iron and wood without copper, tin or bronze")
	near(_business_cash(e), coin, "iron tool production conserves coin")
	e["stock"]["wood"] = 1; e["stock"]["iron_bars"] = 0
	Businesses._recipes(e, D, carpenter, D["businesses"]["carpenter"], 1.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["tools"]) == 1 and int(e["stock"]["wood"]) == 1, "wood without metal cannot create another tool")
	e["stock"]["wood"] = 0
	e["stock"]["charcoal"] = 0; e["stock"]["iron_bars"] = 0; e["stock"]["iron_ore"] = 6
	demand = {}
	Businesses._recipes(e, D, smelter, D["businesses"]["smelter"], 1.0, 1.0, 1.0, market, share, demand)
	check(int(e["stock"]["iron_bars"]) == 0 and int(e["stock"]["iron_ore"]) == 6, "ore alone cannot create metal without either fuel")
	check(float(demand.get("charcoal", 0.0)) > 0.0, "a fuel-starved furnace creates native charcoal demand for prices and caravans")
	e["stock"]["charcoal"] = 3; smelter["till"] = 0.0
	Businesses._recipes(e, D, smelter, D["businesses"]["smelter"], 1.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["iron_bars"]) == 0 and int(e["stock"]["charcoal"]) == 3, "an unfunded furnace cannot consume unpaid materials")
	# Driven price fixture: both fuels are physically present. The cheaper
	# equivalent batch must win independently of its order in the data file.
	e["stock"]["wood"] = 6; e["price"]["wood"] = 100.0; e["price"]["charcoal"] = 5.0
	smelter["till"] = 10000.0; smelter["carry"] = 0.0
	coin = _business_cash(e)
	Businesses._recipes(e, D, smelter, D["businesses"]["smelter"], 1.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["wood"]) == 6 and int(e["stock"]["charcoal"]) == 0 and int(e["stock"]["iron_bars"]) == 3, "a paid furnace actually burns cheaper charcoal while firewood is available")
	near(_business_cash(e), coin, "fuel substitution conserves coin")
	e["stock"]["charcoal"] = 3; e["stock"]["iron_ore"] = 6
	e["price"]["wood"] = 1.0; e["price"]["charcoal"] = 100.0
	var choice := Businesses._recipe_choice(e, D, smelter, D["businesses"]["smelter"], 1.0, {}, false)
	check((choice["best"]["in"] as Dictionary).has("wood"), "the same furnace prefers wood when that fuel is cheaper")
	e["stock"]["wood"] = 1; e["stock"]["iron_bars"] = 1; e["fkh"]["iron"] = 0.0
	Businesses._recipes(e, D, carpenter, D["businesses"]["carpenter"], 1.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["tools"]) == 1 and int(e["stock"]["iron_bars"]) == 1, "iron tools retain the existing iron know-how gate")
	e["fkh"]["iron"] = 100.0
	# Native construction uses the culture's existing material bill, not a
	# free home or a new dwarf-only building resolver.
	e["stock"]["stone"] = 50; e["stock"]["wood"] = 5
	spent = Businesses._recipes(e, D, builder, D["businesses"]["builder"], 25.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["home"]) == 1 and int(e["stock"]["stone"]) == 0 and int(e["stock"]["wood"]) == 0 and spent > 0.0, "an ordinary builder pays the existing 50-stone, 5-wood bill for a dwarf hall")
	near(_business_cash(e), coin, "stone hall construction conserves coin")
	e["stock"]["wood"] = 5
	Businesses._recipes(e, D, builder, D["businesses"]["builder"], 25.0, 1.0, 1.0, market, share, {})
	check(int(e["stock"]["home"]) == 1 and int(e["stock"]["wood"]) == 5, "a dwarf hall cannot be built without stone")

func _business_cash(e: Dictionary) -> float:
	var coin := 0.0
	for b in e["biz"]: coin += float(b["till"])
	return coin

func _market(t: Dictionary) -> Dictionary:
	return t["econ"]["biz"][int(t["econ"]["mkt"])]

func _pair_goods(a: Dictionary, b: Dictionary, cargo: Dictionary, g: String) -> int:
	return int(a["econ"]["stock"].get(g, 0)) + int(b["econ"]["stock"].get(g, 0)) + int(cargo.get("goods", {}).get(g, 0))

func _trade(hold: Dictionary, outside: Dictionary) -> void:
	# Driven stock/price/liquidity fixture. Spawn, crew, purchases, duties,
	# return purchases and settlement are native. Arrival events skip travel
	# time; this is not a natural-equilibrium or road movement benchmark.
	check(Diplomacy.trade_ok(Game.world, str(hold["faction"]), str(outside["faction"])), "the trade fixture uses the hold's ordinary peaceful diplomacy")
	for t in [hold, outside]:
		var e: Dictionary = t["econ"]
		for g in Goods.ids(): e["need"][g] = float(e["stock"].get(g, 0)) + 100.0
		e["arms_short"] = {}
		e["treasury"] = 100000.0
		_market(t)["till"] = 1000000.0
	for g in ["iron_bars", "tools"]:
		hold["econ"]["stock"][g] = 40; hold["econ"]["need"][g] = 1.0; hold["econ"]["price"][g] = 10.0
		outside["econ"]["stock"][g] = 0; outside["econ"]["need"][g] = 100.0; outside["econ"]["price"][g] = 1000.0
	for g in ["grain", "wood", "charcoal"]:
		hold["econ"]["stock"][g] = 0; hold["econ"]["need"][g] = 20.0; hold["econ"]["price"][g] = 100.0
		outside["econ"]["stock"][g] = 100; outside["econ"]["need"][g] = 1.0; outside["econ"]["price"][g] = 1.0
	var arm: Item = null
	for it: Item in hold["shop"]:
		if ArmsTrade.cls(it.tid) != "" and (arm == null or Economy.base_value(hold, it) < Economy.base_value(hold, arm)): arm = it
	check(arm != null, "the hold has an existing individual arm to export")
	if arm != null:
		# Keep the trade's identity proof deterministic, retaining every other
		# existing Item in the town's real armory before the conservation boundary.
		for it in (hold["shop"] as Array).duplicate():
			if it != arm:
				(hold["shop"] as Array).erase(it)
				ArmsTrade.armory(hold).append(it)
		outside["econ"]["arms_short"][ArmsTrade.cls(arm.tid)] = 1
	var rng := RandomNumberGenerator.new(); rng.seed = 87087
	var quote := Caravans.quote_trip(Game.world, hold, outside, rng)
	check(bool(quote["ready"]) and float(quote["expected"]["net"]) > 0.0, "the native road/crew/cash quote admits a profitable unforced exchange")
	var before := JSON.stringify(Game._serialize([hold["econ"]["stock"], hold["shop"], _market(hold)["till"]]))
	var unfunded := Caravans.load_cargo(hold, outside, rng, false, 0.0)
	check(Caravans.cargo_empty(unfunded) and before == JSON.stringify(Game._serialize([hold["econ"]["stock"], hold["shop"], _market(hold)["till"]])), "without a purse the caravan buys no goods or arms")
	var totals := {}
	for g in ["iron_bars", "tools", "grain", "wood", "charcoal"]: totals[g] = _pair_goods(hold, outside, {}, g)
	var coin := Barge.holdings(Game)
	var population := int(hold["econ"]["pop"]) + int(outside["econ"]["pop"])
	var trade_out := float(hold["econ"]["stats"].get("trade_out", 0.0))
	var wid := Caravans.spawn(Game, str(hold["id"]), rng, str(outside["id"]))
	check(wid != "" and Game.world["warbands"].has(wid), "an unforced native caravan actually sails with the staged profitable market")
	if wid == "" or not Game.world["warbands"].has(wid): return
	var wb: Dictionary = Game.world["warbands"][wid]
	var cargo: Dictionary = wb["cargo"]
	check(int(cargo["goods"].get("iron_bars", 0)) > 0 and int(cargo["goods"].get("tools", 0)) > 0, "unforced caravan buys the hold's counted metal and tools")
	check(arm != null and (cargo["items"] as Array).has(arm) and not (hold["shop"] as Array).has(arm), "the same individual arm leaves the hold on paid wagons")
	near(float(hold["econ"]["stats"]["trade_out"]) - trade_out, float(wb["receipt"]["realized"]["buy_cost"]), "origin trade records exactly the native loading purchase cost")
	check(not (wb.get("crew", []) as Array).is_empty() and not (wb["units"] as Array).is_empty(), "the caravan hires actual native drivers and guards")
	for u: Unit in wb["units"]:
		var f := People.fam_of(hold, u.family)
		var p := Persons.by_uid(f, u.uid)
		check(not p.is_empty() and str(p[4]) == "caravan" and u.race == "dwarf" and u.faction == hold["faction"], "each guard is a real dwarf resident serving his native faction")
	near(Barge.holdings(Game), coin, "loading conserves world coin")
	var buyer := float(_market(outside)["till"])
	_market(outside)["till"] = 0.0
	var held := JSON.stringify(Game._serialize(cargo))
	check(Caravans.sell_cargo(outside, cargo, str(hold["name"])) == 0.0 and held == JSON.stringify(Game._serialize(cargo)), "a dry destination till leaves every good and arm on the wagons")
	_market(outside)["till"] = buyer
	wb["pos"] = outside["pos"]
	Caravans.arrive(Game, wid)
	check(str(wb["leg"]) == "home" and arm != null and (outside["shop"] as Array).has(arm), "native destination arrival pays for the existing exported arm and starts the return leg")
	near(Barge.holdings(Game), coin, "native sale, duties and return purchases conserve coin")
	for g in ["grain", "wood", "charcoal"]:
		check(int(cargo["goods"].get(g, 0)) > 0 and int(outside["econ"]["stock"][g]) < 100, "return leg buys real %s for the hold" % g)
	People.pay_crews(Game)
	check(float(wb["receipt"]["realized"]["crew"]) > 0.0, "the native payroll transfers real merchant coin to the actual crew")
	near(Barge.holdings(Game), coin, "crew wages conserve world coin")
	wb["pos"] = hold["pos"]
	Caravans.arrive(Game, wid)
	check(not Game.world["warbands"].has(wid) and Caravans.cargo_empty(cargo) and bool(wb.get("crew_home", false)), "native homecoming pays for the imports, returns the crew and retires the caravan")
	for g in ["grain", "wood", "charcoal"]:
		check(int(hold["econ"]["stock"][g]) == 20 and int(hold["econ"]["stats"].get("cargo_in", {}).get(g, 0)) >= 20, "the hold receives all 20 paid %s units through its normal cargo ledger" % g)
	near(Barge.holdings(Game), coin, "the complete paid exchange conserves world coin")
	for g in totals: check(_pair_goods(hold, outside, cargo, str(g)) == int(totals[g]), "exchange conserves every %s unit" % g)
	check(int(hold["econ"]["pop"]) + int(outside["econ"]["pop"]) == population, "native caravan hiring and return preserve actual residents")
	if arm != null:
		exported_arm_uid = arm.uid; exported_arm_town = str(outside["id"])

func _recruit_rules(hold: Dictionary) -> void:
	# Isolate one existing land-owning household, without creating people or
	# promoting anonymous slots. Restore the fixture and all bindings below.
	var e: Dictionary = hold["econ"]
	var family := {}
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false) or Population.is_cohort(f): continue
		if (f["land"] as Dictionary).is_empty() and (f["herd"] as Dictionary).is_empty(): continue
		var free := false
		var in_pool := false
		for p in Persons.pp(f):
			if str(p[4]) == "hire": in_pool = true
			if str(p[4]) == "" and int(p[5]) < 0: free = true
		if free and not in_pool: family = f; break
	check(not family.is_empty(), "a real dwarf household is available for the desperation control")
	if family.is_empty(): return
	var gone: Array = []
	for f in e["fams"]:
		gone.append(bool(f.get("gone", false)))
		if not is_same(f, family): f["gone"] = true
	var fields := ["unpaid", "hungry", "idle", "purse", "debt", "homes", "ruined", "destitute", "lost", "ln"]
	var kept := {}
	for key in fields:
		if family.has(key): kept[key] = family[key]
	family["unpaid"] = 0; family["hungry"] = 0; family["idle"] = 0; family["debt"] = 0.0
	family["purse"] = 1000000.0; family["homes"] = maxi(1, int(family["homes"]))
	family["ruined"] = false; family["destitute"] = false; family.erase("lost"); family["ln"] = {}
	var rng := RandomNumberGenerator.new(); rng.seed = 870871
	check(Recruits.desperation(family) == 0.0 and Recruits.generate_pool(hold, rng).is_empty(), "a prosperous dwarf family sends nobody to the ordinary recruit pool")
	family["hungry"] = 2
	var pool := Recruits.generate_pool(hold, rng)
	check(not pool.is_empty() and Recruits.desperation(family) > 0.0, "the same real dwarves become available under normal desperation rules")
	for u: Unit in pool:
		var p := Persons.by_uid(family, u.uid)
		check(not p.is_empty() and str(p[4]) == "hire" and u.race == "dwarf" and u.faction == hold["faction"] and u.home_town == hold["id"], "each dwarf recruit is bound to an existing home person and allegiance")
		if not p.is_empty():
			check(u.name == Persons.name_of(family, p, "dwarf") and u.born == float(p[3]), "recruiting retains the person's real name and birth day")
			Persons.set_home(p)
	for key in fields:
		if kept.has(key): family[key] = kept[key]
		else: family.erase(key)
	for i in gone.size(): e["fams"][i]["gone"] = gone[i]

func _pact(a: Dictionary, b: Dictionary, state_name: String = Diplomacy.TRADE_PACT) -> void:
	var row: Dictionary = Game.world["diplo"]["pairs"][Diplomacy.pair_key(str(a["faction"]), str(b["faction"]))]
	row["state"] = state_name; row["rel"] = 90.0 if state_name == Diplomacy.TRADE_PACT else -90.0
	row["dynasty"] = false; row["pact_until"] = 0

func _live_count(uid: String) -> int:
	var n := 0
	for t in Game.world["towns"].values():
		for f in t["econ"]["fams"]:
			if f.get("gone", false) or f.get("estate", false): continue
			for p in f.get("pp", []) + f.get("kp", []):
				if str(Persons.g(p, Persons.PERSON_UID, "")) == uid and str(p[4]) not in ["gone", "dead"]: n += 1
	return n

func _movement() -> void:
	for origin in ["middle", "northern", "eastern"]:
		for target in ["middle", "northern", "eastern"]:
			if origin == target: continue
			_tracked_move(humans[origin], humans[target], origin)
			_cohort_move(humans[origin], humans[target])

func _free_family(source: Dictionary, culture: String, dest: Dictionary) -> Dictionary:
	for f in source["econ"]["fams"]:
		if f.get("estate", false) or f.get("gone", false) or Population.is_cohort(f) or Families.serving(f) > 0 or Barge._away(f): continue
		if str(f.get("cul", "")) != culture or Persons.family_race(source["econ"], f) != "human": continue
		var hh := str(f.get("household_uid", ""))
		if hh == str(source["econ"]["head"].get("household_uid", "")) or hh == str(Game.world.get("player_house", {}).get("household_uid", "")): continue
		# Recruit-pool and bound militia members are not free households. Keep
		# the existing service admission rather than mistaking it for culture.
		if not bool(ServiceIdentity.reserve_move(Game, source, f, dest)["ok"]): continue
		if not Persons.pp(f).is_empty(): return f
	return {}

func _property_totals(t: Dictionary) -> Dictionary:
	var e: Dictionary = t["econ"]
	var totals := {"land": {}, "herds": {}, "homes": int(e["stock"].get("home", 0))}
	for f in e["fams"]:
		totals["homes"] += int(f.get("homes", 0))
		for crop in f["land"]: totals["land"][crop] = int(totals["land"].get(crop, 0)) + int(f["land"][crop])
	for h in Herds.herds(e).values():
		for age in Herds.AGES:
			var key := "%s:%s" % [h["k"], age]
			totals["herds"][key] = int(totals["herds"].get(key, 0)) + int(h[age])
	return totals

func _remember_person(t: Dictionary, f: Dictionary, p: Array) -> void:
	expected_people[str(p[Persons.PERSON_UID])] = _person_state(t, f, p)

func _person_state(t: Dictionary, f: Dictionary, p: Array) -> Dictionary:
	return {"town": str(t["id"]), "household": str(f["household_uid"]),
		"culture": str(f["cul"]), "faction": str(t["faction"]), "race": Persons.family_race(t["econ"], f),
		"first": Persons.first_of(t["econ"], p), "born": float(p[3]), "house": str(p[Persons.HOUSE_UID]),
		"spouse": str(p[Persons.SPOUSE_UID]), "mother": str(p[Persons.MOTHER_UID]), "father": str(p[Persons.FATHER_UID])}

func _tracked_move(source: Dictionary, dest: Dictionary, culture: String) -> void:
	var family := _free_family(source, culture, dest)
	check(not family.is_empty(), "a real free %s household is available to migrate to %s" % [culture, dest["culture"]])
	if family.is_empty(): return
	_pact(source, dest)
	var subset := {"towns": {source["id"]: source, dest["id"]: dest}, "diplo": Game.world["diplo"]}
	check(Barge._refuge(subset, source).get("id", "") == dest["id"], "native refuge accepts %s -> %s humans" % [culture, dest["culture"]])
	var household := str(family["household_uid"])
	var founding := str(family["founding_house_uid"])
	var uid_rows := {}
	for p in family.get("pp", []) + family.get("kp", []):
		var uid := str(p[Persons.PERSON_UID])
		uid_rows[uid] = [Persons.first_of(source["econ"], p), float(p[3]), str(p[Persons.HOUSE_UID]), str(p[Persons.MOTHER_UID]), str(p[Persons.FATHER_UID])]
		moved_uids.append(uid)
	var property_from := _property_totals(source)
	var property_to := _property_totals(dest)
	var owners: Array = (family["owns"] as Array).duplicate()
	var old_id := int(family["id"])
	var pop := int(source["econ"]["pop"]) + int(dest["econ"]["pop"])
	var coin := Barge.holdings(Game)
	var admission := ServiceIdentity.reserve_move(Game, source, family, dest)
	var moved := Barge.move_family(Game, source, family, dest, "work", float(Game.day))
	check(not moved.is_empty(), "native household actually moves %s -> %s (%s)" % [culture, dest["culture"], admission])
	if moved.is_empty(): return
	check(str(moved["household_uid"]) == household and str(moved["founding_house_uid"]) == founding and str(moved["cul"]) == culture and Persons.family_race(dest["econ"], moved) == "human", "migration keeps the household's real identity, lineage, culture and biology")
	check(bool(family.get("gone", false)) and str(family.get("moved", "")) != "", "the original household row records its departure")
	check(is_same(People.fam_of(dest, int(moved["id"])), moved) and str(dest["econ"]["faction"]) == str(dest["faction"]), "the migrated household belongs to the destination's native register and allegiance")
	for uid in uid_rows:
		var loc := Dynasty._person(Game, str(uid))
		check(_live_count(str(uid)) == 1 and not loc.is_empty(), "each migrant has exactly one living identity")
		if loc.is_empty(): continue
		var p: Array = loc["person"]
		check(loc["town"]["id"] == dest["id"] and is_same(loc["family"], moved), "each migrant lives in the actual destination household")
		check([Persons.first_of(dest["econ"], p), float(p[3]), str(p[Persons.HOUSE_UID]), str(p[Persons.MOTHER_UID]), str(p[Persons.FATHER_UID])] == uid_rows[uid], "migration preserves the person's name, birth, birth house and parent identities")
		_remember_person(dest, moved, p)
	for bid in owners:
		var b: Dictionary = source["econ"]["biz"][int(bid)]
		check(int(b["owner"]) != old_id or bool(b.get("closed", false)), "a departed household does not keep operating a source business")
	check(_property_totals(source) == property_from and _property_totals(dest) == property_to, "migration changes native property owners without teleporting or creating land, homes or animals")
	check(int(source["econ"]["pop"]) + int(dest["econ"]["pop"]) == pop, "tracked migration conserves actual residents")
	near(Barge.holdings(Game), coin, "cross-culture household migration conserves coin")
	check(Barge.move_family(Game, dest, moved, holds[0], "work", Game.day).is_empty(), "culture freedom does not turn a human household into dwarves")

func _cohort_pair(a: Dictionary, b: Dictionary) -> Dictionary:
	var totals := {"bins": {}, "goods": {}}
	for t in [a, b]:
		for f in t["econ"]["fams"]:
			if not Population.is_cohort(f) or f.get("gone", false): continue
			for key in f["age_bins"]: totals["bins"][key] = int(totals["bins"].get(key, 0)) + int(f["age_bins"][key])
		for g in t["econ"]["hh"]: totals["goods"][g] = int(totals["goods"].get(g, 0)) + int(t["econ"]["hh"][g])
	return totals

func _cohort_move(source: Dictionary, dest: Dictionary) -> void:
	var cohort := Migration._row_for(source["econ"], "human")
	var receiving := Migration._row_for(dest["econ"], "human")
	check(not cohort.is_empty() and not receiving.is_empty(), "native common rows exist for %s -> %s" % [source["culture"], dest["culture"]])
	if cohort.is_empty() or receiving.is_empty(): return
	var all_towns: Dictionary = Game.world["towns"]
	_pact(source, dest, Diplomacy.WAR)
	Game.world["towns"] = {source["id"]: source, dest["id"]: dest}
	check(Migration.destination(Game, source, cohort, "hunger", Game.day, {dest["id"]: ""}).is_empty(), "native war gate still rejects the foreign destination")
	_pact(source, dest)
	check(Migration.destination(Game, source, cohort, "hunger", Game.day, {dest["id"]: ""}).get("id", "") == dest["id"], "cohort migration also accepts another human culture")
	Game.world["towns"] = all_towns
	var pop := int(source["econ"]["pop"]) + int(dest["econ"]["pop"])
	var coin := Barge.holdings(Game)
	var counts := _cohort_pair(source, dest)
	var left := Population.households(cohort)
	var arrived := Population.households(receiving)
	var property_from := _property_totals(source)
	var property_to := _property_totals(dest)
	check(Migration.move_households(Game, source, cohort, dest, 1, "hunger", float(Game.day)) > 0, "native common households actually move %s -> %s" % [source["culture"], dest["culture"]])
	check(Population.households(cohort) == left - 1 and Population.households(receiving) == arrived + 1, "exactly one common household changes its native town register")
	check(int(source["econ"]["pop"]) + int(dest["econ"]["pop"]) == pop, "cohort migration conserves actual residents")
	check(_cohort_pair(source, dest) == counts, "cohort migration conserves every age bin and household good")
	check(_property_totals(source) == property_from and _property_totals(dest) == property_to, "cohort migration preserves physical property while changing its owners")
	near(Barge.holdings(Game), coin, "cohort migration conserves coin including paid houses")

func _candidate(t: Dictionary, sex: int) -> Dictionary:
	var e: Dictionary = t["econ"]
	var heir_uid := str(Dynasty.heir(Game, str(t["id"])).get("person_uid", ""))
	var fallback := {}
	for f in e["fams"]:
		if f.get("estate", false) or f.get("gone", false) or Population.is_cohort(f): continue
		if str(f.get("cul", "")) != str(t["culture"]): continue
		if str(f.get("household_uid", "")) == str(Game.world.get("player_house", {}).get("household_uid", "")): continue
		for p in Persons.pp(f):
			var uid := str(p[Persons.PERSON_UID])
			if wedding_uids.has(uid) or Marriage._is_player_side(Game, f, p): continue
			if int(p[2]) != sex or int(p[6]) != 0 or str(p[4]) != "" or int(p[5]) >= 0: continue
			if sex == 1 and Persons.preg_of(f, int(p[0])) >= 0: continue
			if uid == heir_uid or uid == str(e["head"].get("person_uid", "")) or Marriage._betrothed(Game, uid): continue
			var who := {"town": t, "econ": e, "family": f, "person": p, "uid": uid}
			if not Marriage._married({"person": p, "family": f}): return who
			if fallback.is_empty(): fallback = who
	if not fallback.is_empty():
		# Driven fixture: free an existing adult, clearing both old links. The
		# causal marriage check must not depend on a lucky unmarried start roll.
		var p: Array = fallback["person"]
		var old := Dynasty._person(Game, str(Persons.g(p, Persons.SPOUSE_UID, "")))
		var other: Array = old["person"] if not old.is_empty() else Persons.by_pid(fallback["family"], int(p[Persons.SP]))
		if not other.is_empty():
			other[Persons.SP] = -1; other[Persons.SPOUSE_UID] = ""
			if not old.is_empty() and expected_people.has(str(other[Persons.PERSON_UID])):
				_remember_person(old["town"], old["family"], other)
		p[Persons.SP] = -1; p[Persons.SPOUSE_UID] = ""
	return fallback

func _marriages() -> void:
	for pair in [["middle", "northern"], ["middle", "eastern"], ["northern", "eastern"]]:
		var groom := _candidate(humans[pair[0]], 0)
		var bride := _candidate(humans[pair[1]], 1)
		var label := "%s/%s" % [pair[0], pair[1]]
		check(not groom.is_empty() and not bride.is_empty(), "real unmarried %s adults are available" % label)
		if groom.is_empty() or bride.is_empty(): continue
		# Equal adult ages and a friendly relation isolate culture from political/age scoring.
		for who in [groom, bride]: who["person"][3] = float(Game.day) - 30.0 * People.year_days()
		_pact(groom["town"], bride["town"], Diplomacy.WAR)
		check(not bool(Marriage.try_ai_match(Game, str(groom["uid"]), str(bride["uid"])).get("ok", false)), "the native political refusal still applies to %s houses at war" % label)
		_pact(groom["town"], bride["town"])
		var race := str(bride["family"].get("race", "human"))
		bride["family"]["race"] = "dwarf"
		check(not bool(Marriage.try_ai_match(Game, str(groom["uid"]), str(bride["uid"])).get("ok", false)), "the existing cross-race marriage boundary remains")
		bride["family"]["race"] = race
		var birth_house := str(bride["person"][Persons.HOUSE_UID])
		var given := Persons.first_of(bride["econ"], bride["person"])
		var mother := str(bride["person"][Persons.MOTHER_UID])
		var father := str(bride["person"][Persons.FATHER_UID])
		# Liquidity fixture makes a positive native dowry observable.
		# Reassignment legitimately settles accrued wages on a departing bride.
		# Pay those existing claims before isolating the two-purse dowry boundary.
		WageClaims.pay_family(bride["econ"], bride["family"])
		WageClaims.pay_family(groom["econ"], groom["family"])
		bride["family"]["purse"] = maxf(10000.0, float(bride["family"]["purse"]))
		var bride_coin := float(bride["family"]["purse"])
		var groom_coin := float(groom["family"]["purse"])
		var dowry := floorf(bride_coin * Marriage.DOWRY_SHARE)
		var bride_pop := int(bride["econ"]["pop"])
		var groom_pop := int(groom["econ"]["pop"])
		var coin := Barge.holdings(Game)
		var before_purses := {}
		for f in bride["econ"]["fams"]: before_purses["f:" + str(f["id"])] = float(f["purse"])
		for b in bride["econ"]["biz"]: before_purses["b:" + str(b["id"])] = float(b["till"])
		var offer := Marriage.try_ai_match(Game, str(groom["uid"]), str(bride["uid"]))
		check(bool(offer.get("ok", false)), "%s humans marry through the native AI proposal (%s)" % [label, offer.get("reason", "")])
		if not bool(offer.get("ok", false)): continue
		wedding_uids.append(str(groom["uid"])); wedding_uids.append(str(bride["uid"]))
		var moved := Dynasty._person(Game, str(bride["uid"]))
		check(not moved.is_empty() and is_same(moved["family"], groom["family"]), "the same bride joins the groom's real household")
		if moved.is_empty(): continue
		check(str(moved["person"][Persons.HOUSE_UID]) == birth_house and Persons.first_of(moved["econ"], moved["person"]) == given, "marriage preserves birth lineage and native given name")
		check(str(moved["person"][Persons.MOTHER_UID]) == mother and str(moved["person"][Persons.FATHER_UID]) == father, "cross-town marriage preserves stable parent identities")
		check(moved["town"]["id"] == groom["town"]["id"] and str(moved["econ"]["faction"]) == str(groom["town"]["faction"]) and not (bride["family"]["pp"] as Array).has(moved["person"]), "the bride leaves her source register and takes the receiving town's native allegiance")
		check(str(moved["person"][Persons.SPOUSE_UID]) == str(groom["uid"]) and str(groom["person"][Persons.SPOUSE_UID]) == str(bride["uid"]), "the same people hold reciprocal spouse identities")
		check(int(moved["person"][Persons.SP]) == int(groom["person"][0]) and int(groom["person"][Persons.SP]) == int(moved["person"][0]), "native local spouse PIDs are rebound together")
		check(int(bride["econ"]["pop"]) == bride_pop - 1 and int(groom["econ"]["pop"]) == groom_pop + 1 and _live_count(str(bride["uid"])) == 1, "exactly the existing bride changes residence")
		near(float(bride["family"]["purse"]), bride_coin - dowry, "the bride's household actually pays its dowry")
		if absf(float(bride["family"]["purse"]) - (bride_coin - dowry)) > 0.001:
			print("v087 dowry quote ", offer.get("dowry", -1), " expected ", dowry)
			for f in bride["econ"]["fams"]:
				var key := "f:" + str(f["id"])
				if float(f["purse"]) != float(before_purses[key]): print("v087 dowry ", key, " delta ", float(f["purse"]) - float(before_purses[key]))
			for b in bride["econ"]["biz"]:
				var key := "b:" + str(b["id"])
				if float(b["till"]) != float(before_purses[key]): print("v087 dowry ", key, " delta ", float(b["till"]) - float(before_purses[key]))
		near(float(groom["family"]["purse"]), groom_coin + dowry, "the receiving household gets exactly that dowry")
		near(Barge.holdings(Game), coin, "cross-culture dowry conserves real coin")
		_remember_person(moved["town"], moved["family"], moved["person"])
		_remember_person(groom["town"], groom["family"], groom["person"])
		var key := str(offer["key"])
		expected_links[key] = _link_state(Marriage.state(Game)["ai_links"][key])

func _round_trip() -> void:
	var coin := Barge.holdings(Game)
	var stocks := {}
	var properties := {}
	var cohorts := {}
	for t in Game.world["towns"].values():
		stocks[str(t["id"])] = t["econ"]["stock"].duplicate(true)
		properties[str(t["id"])] = _property_totals(t)
		for f in t["econ"]["fams"]:
			if Population.is_cohort(f) and not f.get("gone", false):
				cohorts[str(f["household_uid"])] = _cohort_state(t, f)
	Game.save_game(); Game.wait_save()
	var loaded := Game.load_game()
	check(loaded, "the isolated synthetic campaign reloads through native restoration")
	if not loaded: return
	near(Barge.holdings(Game), coin, "save restoration preserves coin")
	var restored_cohorts := {}
	for t in Game.world["towns"].values():
		check(t["econ"]["stock"] == stocks[str(t["id"])], "save restoration preserves every counted market good")
		check(_property_totals(t) == properties[str(t["id"])], "save restoration preserves physical land, homes and animals")
		for f in t["econ"]["fams"]:
			if Population.is_cohort(f) and not f.get("gone", false):
				restored_cohorts[str(f["household_uid"])] = _cohort_state(t, f)
	check(restored_cohorts == cohorts, "save restoration keeps every common household in its exact town with its age bins")
	if restored_cohorts != cohorts: _first_diff(cohorts, restored_cohorts, "cohorts")
	for uid in expected_people:
		var loc := Dynasty._person(Game, str(uid))
		check(_live_count(str(uid)) == 1 and not loc.is_empty(), "save restoration keeps exactly one live person per moved or married UID")
		if not loc.is_empty():
			check(_person_state(loc["town"], loc["family"], loc["person"]) == expected_people[uid], "save restoration preserves exact residence, allegiance, household, culture, race, name, birth, lineage, spouse and parents")
	for key in expected_links:
		var actual_link := _link_state(Marriage.state(Game).get("ai_links", {}).get(key, {}))
		check(actual_link == expected_links[key], "the actual cross-culture marriage link survives native reload")
		if actual_link != expected_links[key]: _first_diff(expected_links[key], actual_link, "link/" + str(key))
	if exported_arm_uid >= 0:
		var copies := 0
		for it: Item in Game.world["towns"][exported_arm_town]["shop"]:
			if it.uid == exported_arm_uid: copies += 1
		check(copies == 1, "the actual paid exported arm retains exactly its Item UID at the buyer after reload")

func _cohort_state(t: Dictionary, f: Dictionary) -> Dictionary:
	var bins := {}
	for key in f["age_bins"]:
		var n = f["age_bins"][key]
		check(float(n) == float(int(n)) and int(n) >= 0, "cohort bin remains an exact nonnegative whole count")
		bins[key] = int(n)
	return {"town": str(t["id"]), "households": Population.households(f), "bins": bins}

func _link_state(link: Dictionary) -> Dictionary:
	var out := link.duplicate(true)
	if out.has("day"):
		check(float(out["day"]) == float(int(out["day"])), "marriage day remains an exact whole day")
		out["day"] = int(out["day"])
	return out

func _first_diff(a, b, path: String) -> bool:
	if typeof(a) != typeof(b):
		print("v087 first difference ", path, " type ", typeof(a), "/", typeof(b), " values ", str(a).left(120), "/", str(b).left(120))
		return true
	if a is Dictionary:
		for key in a:
			if not b.has(key): print("v087 first difference ", path, " missing ", key); return true
			if _first_diff(a[key], b[key], path + "/" + str(key)): return true
		for key in b:
			if not a.has(key): print("v087 first difference ", path, " extra ", key); return true
	elif a is Array:
		if a.size() != b.size(): print("v087 first difference ", path, " sizes ", a.size(), "/", b.size()); return true
		for i in a.size():
			if _first_diff(a[i], b[i], path + "/" + str(i)): return true
	elif a != b:
		print("v087 first difference ", path, " values ", str(a).left(120), "/", str(b).left(120))
		return true
	return false
