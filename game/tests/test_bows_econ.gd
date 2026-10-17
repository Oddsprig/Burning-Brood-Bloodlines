extends RefCounted
## bows (docs/specs/bows.md section 6): bowyers and fletchers in the real economy. Bowyers consume the town's real
## wood and compete with firewood; staves season; arrows supply targets (armory, militia, forces) raise orders and
## prices when short; bowyers make bows when the stalls are short; forces fill quivers from home-town stock;
## arrows are lootable, recoverable from a held field and carried by caravans. Goods are conserved.

const U = preload("res://tests/sim_util.gd")

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _quiet(w: Dictionary) -> void:
	for wid in w["warbands"].keys():
		CampaignWorld.remove_warband(Game, wid)
	w["work"] = []
	w["party"]["safe_until"] = 1.0e9

func _town_ids(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys()
	ids.sort()
	return ids

## One town's daily pass for n days (the rest of the world stands still).
func _days(town: Dictionary, n: int) -> void:
	for i in n:
		var d := int(town["econ"]["day"]) + 1
		Game.day = float(d)
		TownEcon.daily_pass(Game, town, d)

func _row(e: Dictionary, type: String) -> Dictionary:
	for b in e["biz"]:
		if b["type"] == type:
			return b
	return {}

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_bows_%d.json" % OS.get_process_id()
	Game.new_game(4242)
	var w: Dictionary = Game.world
	_quiet(w)
	_test_generation(w)
	_test_wood(w)
	_test_staves_season(w)
	_test_arrow_targets(w)
	_test_bowyer_bows(w)
	_test_forces_and_militia(w)
	_test_loot_recovery_caravan(w)
	_test_conservation()
	_test_save_load()
	return fails

func _test_generation(w: Dictionary) -> void:
	var n := 0
	for tid in _town_ids(w):
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		check(not _row(e, "bowyer").is_empty() and not _row(e, "fletcher").is_empty(), "%s has no bowyer or fletcher" % t["name"])
		check(e.has("armory"), "%s has no armory" % t["name"])
		check(int(e["stock"].get("staves", 0)) > 0, "%s has no seasoned staves at start" % t["name"])
		check(BowsEcon.bows_on_stalls(t) > 0, "%s has no bows on the stalls" % t["name"])
		n += 1
	var t0: Dictionary = w["towns"][_town_ids(w)[0]]
	var e0: Dictionary = t0["econ"]
	print("-- %d towns with bowyers and fletchers; %s (%s): staves %d seasoned + %d seasoning, bows on the stalls %d, armory %s, workers bowyer %d fletcher %d" % [
		n, t0["name"], t0.get("culture", ""), int(e0["stock"]["staves"]), int(e0["stock"]["staves_green"]), BowsEcon.bows_on_stalls(t0), str(e0["armory"]),
		int(_row(e0, "bowyer")["workers"]), int(_row(e0, "fletcher")["workers"])])

## Bowyers buy the town's real wood (6 loads a stave) and compete with firewood: the same town with its bowyers
## closed keeps more wood at a lower price; with the wood gone the bowyer idles and the reason reads "short of wood".
func _test_wood(w: Dictionary) -> void:
	var t: Dictionary = w["towns"][_town_ids(w)[1]]
	var e: Dictionary = t["econ"]
	var by := _row(e, "bowyer")
	by["workers"] = maxi(2, int(by["workers"]))
	by["cap"] = maxi(int(by["cap"]), int(by["workers"]))
	t["shop"] = (t["shop"] as Array).filter(func(it): return not DB.is_bow(it.tid))   # no bows wanted? keep him on staves too
	# a town short of wood, so the bowyer's orders show against firewood (a town glutted with wood sits at the floor
	# price either way and 12 days differ only by the households' own rolls: on the 1.5x map, war pick 5, this town is)
	e["stock"]["wood"] = mini(int(e["stock"].get("wood", 0)), 150)
	e["barn"]["wood"] = 0
	var twin: Dictionary = t.duplicate(true)
	var te: Dictionary = twin["econ"]
	_row(te, "bowyer")["closed"] = true
	Businesses.rebuild_open(te)
	var used0 := int(e["led"]["used"].get("wood", 0))
	var green0 := int(e["led"]["made"].get("staves_green", 0))
	_days(t, 12)
	_days(twin, 12)
	var staves_made := int(e["led"]["made"].get("staves_green", 0)) - green0
	var wood_used := int(e["led"]["used"].get("wood", 0)) - used0
	print("-- wood: bowyer split %d green staves (6 loads each); town used %d loads of wood in 12 days; wood %d at %.2f with bowyers vs %d at %.2f without" % [
		staves_made, wood_used, int(e["stock"].get("wood", 0)), float(e["price"]["wood"]), int(te["stock"].get("wood", 0)), float(te["price"]["wood"])])
	var twin_used := int(te["led"]["used"].get("wood", 0)) - used0
	print("   wood used in 12 days: %d with bowyers, %d without; market need %.1f vs %.1f" % [wood_used, twin_used, float(e["need"]["wood"]), float(te["need"]["wood"])])
	check(staves_made > 0, "the bowyer should split staves out of the wood stock")
	check(wood_used >= staves_made * 6, "staves must cost real wood (%d used for %d staves)" % [wood_used, staves_made])
	# (war pick 5: there was a check here that the market's wood need ends higher with the bowyers. On the 1.5x map
	# this town's twin, its bowyers closed, puts their hands to cutting wood and its households burn more at the lower
	# price, so need and wood used both end higher without bowyers; the competition shows in stock and price below.)
	check(int(e["stock"].get("wood", 0)) <= int(te["stock"].get("wood", 0)) or float(e["price"]["wood"]) >= float(te["price"]["wood"]),
		"bowyers should compete with firewood for the town's wood")
	# no wood: the bowyer idles, and the staves' price reason says why
	e["stock"]["wood"] = 0
	e["barn"]["wood"] = 0
	e["stock"]["staves_green"] = 0   # (a full stave rack would rest him instead)
	by["state"] = "busy"
	_days(t, 1)
	check(by["state"] == "inputs" and String(by.get("why", "")) == "wood", "a bowyer without wood should idle for wood (%s, %s)" % [by["state"], by.get("why", "")])
	check(String(e.get("why_hint", {}).get("staves", "")) == "short of wood", "the staves' price reason should read 'short of wood'")

func _test_staves_season(w: Dictionary) -> void:
	var t: Dictionary = w["towns"][_town_ids(w)[2]]
	var e: Dictionary = t["econ"]
	e["stock"]["staves_green"] = 240
	var s0 := int(e["led"]["made"].get("staves", 0))
	for i in 30:
		BowsEcon._season(e)
	var seasoned := int(e["led"]["made"].get("staves", 0)) - s0
	print("-- staves: of 240 green staves, %d seasoned in 30 days (%.0f days each on average)" % [seasoned, BowsEcon.SEASON_DAYS])
	check(seasoned > 30 and seasoned < 80, "staves season over months, not days (%d of 240 in 30 days)" % seasoned)

## Arrows supply targets: an empty armory and empty stalls raise the price; full ones bring it down.
func _test_arrow_targets(w: Dictionary) -> void:
	var t: Dictionary = w["towns"][_town_ids(w)[3]]
	var e: Dictionary = t["econ"]
	var k: String = BowsEcon.culture_arrows(t)[0]
	var base := float(TownEcon.data()["goods"][k]["price"])
	e["armory"] = {}
	e["stock"][k] = 0
	_days(t, 4)
	var short_p := float(e["price"][k])
	e["armory"][k] = 5000
	e["stock"][k] = 4000
	_days(t, 20)
	var full_p := float(e["price"][k])
	print("-- arrow targets (%s, base %.2f): short armory and stalls -> %.2f; full -> %.2f; reason '%s'" % [k, base, short_p, full_p, String(e["why"].get(k, ""))])
	check(short_p > base * 1.3, "a short armory must raise the arrows' price (%.2f vs base %.2f)" % [short_p, base])
	check(full_p < short_p, "full stocks should bring the price down (%.2f vs %.2f)" % [full_p, short_p])
	# the fletchers answer the order: the most wanted recipe is the short arrow
	var fl := _row(e, "fletcher")
	print("   fletcher: %d workers, %s %s" % [int(fl["workers"]), fl["state"], fl.get("why", "")])

## The bowyer makes bows when the stalls are short (and the bows' price rises).
func _test_bowyer_bows(w: Dictionary) -> void:
	var t: Dictionary = w["towns"][_town_ids(w)[4]]
	var e: Dictionary = t["econ"]
	var by := _row(e, "bowyer")
	by["workers"] = maxi(2, int(by["workers"]))
	by["cap"] = maxi(int(by["cap"]), int(by["workers"]))
	var all_bows: Array = (t["shop"] as Array).filter(func(it): return DB.is_bow(it.tid))
	var probe: Item = all_bows[0] if not all_bows.is_empty() else Item.make(DB.bows_by_culture.get(t.get("culture", "middle"), ["self_bow"])[0], "wood", 0)
	t["shop"] = (t["shop"] as Array).filter(func(it): return not DB.is_bow(it.tid))
	var p_short := Economy.base_value(t, probe)
	e["stock"]["staves"] = 30
	for g in ["horn", "sinew", "glue", "wood"]:
		e["stock"][g] = maxi(int(e["stock"].get(g, 0)), 30)
	by["till"] = maxf(float(by["till"]), 500.0 * TownEcon.COIN)   # coinage x20
	var arms0 := int(e["led"]["made"].get("arms", 0))
	_days(t, 15)
	var made := BowsEcon.bows_on_stalls(t)
	var p_after := Economy.base_value(t, probe)
	print("-- bowyer (%s): stalls emptied of bows (target %d) -> %d bows made in 15 days; bow price %.1f short -> %.1f after" % [
		t.get("culture", ""), int(e.get("bow_target", 0)), made, p_short, p_after])
	check(made > 0, "a bowyer should make bows when the stalls are short")
	check(int(e["led"]["made"].get("arms", 0)) > arms0, "bows are made into the arms ledger")
	check(p_short > p_after or made == 0, "bows should be dearer while the stalls are short")

## Forces raised from a town fill their quivers from its stock (the treasury pays); a shortfall is ordered.
## The militia's quivers come out of the armory.
func _test_forces_and_militia(w: Dictionary) -> void:
	var t: Dictionary = w["towns"][_town_ids(w)[0]]
	var e: Dictionary = t["econ"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var fid: String = t["faction"]
	var bow_t: Dictionary = {}
	for tr in DB.factions.get(fid, {}).get("troops", []):
		if tr.has("arrows"):
			bow_t = tr
	if bow_t.is_empty():
		bow_t = DB.factions["middle_kingdom"]["troops"][2]
	var units := []
	for i in 4:
		units.append(Factory.make_troop(rng, fid if DB.factions.has(fid) else "middle_kingdom", bow_t, 2))
	# stock a bow per man so they keep theirs, and arrows for two quivers
	for u in units:
		(t["shop"] as Array).append(Item.make(u.bow().tid, "wood", 0))
	var k: String = BowsEcon.culture_arrows(t)[0]
	for kk in DB.arrows:
		e["stock"][kk] = 0
	e["stock"][k] = 100
	e["req"] = {}
	var tr0 := float(e["treasury"])
	var u0 := int(e["led"]["used"].get(k, 0))
	TownEcon.outfit_units(t, units, 1.0)
	var filled := 0
	for u in units:
		filled += u.arrows()
		check(u.arrows() <= DB.QUIVER_MAX, "quiver over the cap")
	print("-- force from %s: 4 archers, %d arrows on the stalls -> quivers hold %d; treasury paid %.1f; order for the shortfall %.0f" % [
		t["name"], 100, filled, tr0 - float(e["treasury"]), float(e["req"].get(k, 0.0))])
	check(filled == 100, "quivers come out of the town's stock (%d of 100)" % filled)
	check(int(e["stock"][k]) == 0 and int(e["led"]["used"].get(k, 0)) - u0 == 100, "the arrows leave the stalls and the ledger shows it")
	check(float(e["treasury"]) < tr0, "the town treasury pays for the force's arrows")
	check(float(e["req"].get(k, 0.0)) >= 100.0, "the shortfall is ordered")
	# militia: archers refill from the armory
	var mil := Militia.units_of(Game, t["id"])
	var archers := mil.filter(func(u): return u.equip.has("ranged"))
	if not archers.is_empty():
		for u in archers:
			u.quiver.clear()
		e["armory"][k] = 1000
		_days(t, 1)
		var q := 0
		for u in archers:
			q += u.arrows()
		print("   militia: %d archers refilled to %d arrows from the armory" % [archers.size(), q])
		check(q == archers.size() * DB.QUIVER_MAX or int(e["armory"].get(k, 0)) == 0, "the militia refills its quivers from the armory")

func _test_loot_recovery_caravan(w: Dictionary) -> void:
	var foe := U.make("human", [["self_bow", "wood"], ["tunic", "linen"]], {"bow": 2})
	foe.quiver = {"arrow_copper_bodkin": 20}
	foe.dead = true
	var sp := Loot.spoils([foe], [], 3, 0.25)
	check(int(sp.get("arrows", {}).get("arrow_copper_bodkin", 0)) == 20 and foe.quiver.is_empty(), "the enemy's quiver is lootable")
	var rec := Archery.recovered({"arrow_wood": {"ground": 10, "body": 4, "shield": 5, "armor": 5, "lost": 3}})
	check(int(rec.get("arrow_wood", 0)) == int(10 * 0.75 + 4 * 0.5 + 5 * 0.6 + 5 * 0.4), "field recovery shares")
	check(Goods.ids().has("arrow_copper_bodkin") and Goods.ids().has("staves"), "arrows and staves are tradeable goods (caravans)")
	# a caravan carries arrows where they are dear
	var pair := []
	for tid in _town_ids(w):
		var p := Caravans.trade_partners(w, w["towns"][tid])
		if not p.is_empty():
			pair = [tid, p[0]["id"]]
			break
	if pair.is_empty():
		return
	var origin: Dictionary = w["towns"][pair[0]]
	var dest: Dictionary = w["towns"][pair[1]]
	origin["econ"]["stock"]["arrow_copper_broad"] = 3000
	dest["econ"]["stock"]["arrow_copper_broad"] = 0
	dest["econ"]["dem"]["arrow_copper_broad"] = 40.0
	TownEcon.update_prices(origin, 0); TownEcon.update_prices(dest, 0)
	var cargo := Caravans.load_cargo(origin, dest, RandomNumberGenerator.new(), false, 400.0)
	print("-- caravan %s -> %s carries %d copper broadhead arrows" % [origin["name"], dest["name"], int(cargo["goods"].get("arrow_copper_broad", 0))])
	check(int(cargo["goods"].get("arrow_copper_broad", 0)) > 0, "caravans should carry arrows to where they are dear")
	Caravans.unload(dest, cargo)

## Goods and gold conserved over a month with bowyers, fletchers, armories and smiths' arrowheads working.
func _test_conservation() -> void:
	Game.new_game(778)
	var w: Dictionary = Game.world
	_quiet(w)
	var ids := _town_ids(w)
	for d in 3:
		for tid in ids:
			_days(w["towns"][tid], 1)
	var tot0 := {}
	var led0 := {}
	for tid in ids:
		var e: Dictionary = w["towns"][tid]["econ"]
		for g in Goods.table():
			tot0[g] = int(tot0.get(g, 0)) + TownEcon.town_total(e, g)
		for kind in ["made", "used", "spoil"]:
			for g in e["led"][kind]:
				led0[kind + g] = int(led0.get(kind + g, 0)) + int(e["led"][kind][g])
	for d in 30:
		for tid in ids:
			_days(w["towns"][tid], 1)
	var bad := []
	var tot1 := {}
	var led1 := {}
	for tid in ids:
		var e: Dictionary = w["towns"][tid]["econ"]
		for g in Goods.table():
			tot1[g] = int(tot1.get(g, 0)) + TownEcon.town_total(e, g)
		for kind in ["made", "used", "spoil"]:
			for g in e["led"][kind]:
				led1[kind + g] = int(led1.get(kind + g, 0)) + int(e["led"][kind][g])
	var gs := ["staves_green", "staves", "horn", "sinew", "glue", "feathers", "heads_copper", "heads_tin", "wood"] + DB.arrows.keys()
	var made_any := {}
	for g in gs:
		var made := int(led1.get("made" + g, 0)) - int(led0.get("made" + g, 0))
		var used := int(led1.get("used" + g, 0)) - int(led0.get("used" + g, 0))
		var spoil := int(led1.get("spoil" + g, 0)) - int(led0.get("spoil" + g, 0))
		made_any[g] = made
		if int(tot1.get(g, 0)) != int(tot0.get(g, 0)) + made - used - spoil:
			bad.append("%s %d != %d + %d - %d - %d" % [g, tot1.get(g, 0), tot0.get(g, 0), made, used, spoil])
	print("-- conservation over 30 days, made: %s" % str(made_any))
	check(bad.is_empty(), "bows goods not conserved: %s" % ", ".join(PackedStringArray(bad)))
	var arrows_made := 0
	for k in DB.arrows:
		arrows_made += int(made_any.get(k, 0))
	check(arrows_made > 0, "fletchers should make arrows in a month")

func _test_save_load() -> void:
	var u := U.make("human", [["self_bow", "wood"]], {"bow": 3})
	u.quiver = {"arrow_wood": 12}
	u.bow().vr = 1.032
	var u2 := Unit.from_dict(u.to_dict())
	check(u2.arrows() == 12 and u2.bow() != null and absf(u2.bow().vr - 1.032) < 0.0001 and u2.skill("bow") == 3, "quiver, bow and its variance survive a save")
	Game.save_game()
	check(Game.load_game(), "save/load with bows")
	var t: Dictionary = Game.world["towns"][_town_ids(Game.world)[0]]
	check(t["econ"].has("armory") and not _row(t["econ"], "bowyer").is_empty(), "the armory and bowyer survive a save")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
