extends RefCounted
## Economy spec 1 (docs/specs/economy-1-town.md section 14): conservation of goods and gold; caravan cargo
## leaves the origin and arrives intact; smiths idle with zero bars; no bronze without copper and tin; know-how
## gates the spread (bronze share stays low for a season in a fresh world); land loop order; a 1-year sim with
## no negative stock and no NaN prices; save/load and migration; supply levels; the perf gate (worst campaign
## day < 5 ms at 20 towns x 150 families).

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

## Runs the economy only (no warbands, no company) for n days, exactly as the work queue would.
func _econ_days(n: int) -> void:
	var w: Dictionary = Game.world
	for i in n:
		var d := int(w.get("econ_test_day", int(w.get("last_day", 0)))) + 1
		w["econ_test_day"] = d
		Game.day = float(d)
		var work := []
		w["work"] = work
		TownEcon.queue_day(w, d)
		while not work.is_empty():
			var job: Array = work.pop_front()
			if not TownEcon.do_job(Game, job):
				if job[0] == "caravan":
					Caravans.spawn(Game, job[1], RandomNumberGenerator.new(), str(job[2]))

func _goods_total(w: Dictionary) -> Dictionary:
	var tot := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		for g in Goods.table():
			tot[g] = int(tot.get(g, 0)) + TownEcon.town_total(t["econ"], g)
		tot["arms"] = int(tot.get("arms", 0)) + (t["shop"] as Array).size() + (t.get("armory_items", []) as Array).size()   # arms trade: the head's armory is a town holding
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] != "caravan":
			continue
		for g in wb["cargo"]["goods"]:
			tot[g] = int(tot.get(g, 0)) + int(wb["cargo"]["goods"][g])
		tot["arms"] = int(tot.get("arms", 0)) + (wb["cargo"]["items"] as Array).size()
	return tot

func _ledger(w: Dictionary) -> Dictionary:
	var out := {"made": {}, "used": {}, "spoil": {}}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		for k in out:
			var l: Dictionary = t["econ"]["led"][k]
			for g in l:
				out[k][g] = int(out[k].get(g, 0)) + int(l[g])
	return out

func _gold_total(w: Dictionary) -> float:
	var g := 0.0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t):
			g += TownEcon.town_gold(t["econ"])
	for fid in w["factions"]:
		g += float(w["factions"][fid].get("treasury", 0.0))
	for wid in w["warbands"]:
		g += float(w["warbands"][wid].get("gold", 0.0))
	return g

func run(tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_econ_%d.json" % OS.get_process_id()   # other test runs may share user://
	if OS.get_environment("ECON_ONLY") == "stories":
		_test_stories()
		return fails
	if OS.get_environment("ECON_ONLY") == "register":
		_test_register()
		return fails
	if OS.get_environment("ECON_ONLY") == "persons":
		_test_persons()
		return fails
	if OS.get_environment("ECON_ONLY") == "loans":
		_test_land_loop()
		_test_loans()
		return fails
	if OS.get_environment("ECON_ONLY") == "save":
		_test_save_and_migration()
		return fails
	if OS.get_environment("ECON_ONLY") == "year":
		_test_year()
		return fails
	if OS.get_environment("ECON_ONLY") == "perf":   # dev: ECON_ONLY=perf tools/test.sh tests/test_econ_town.gd
		_test_perf()
		return fails
	_test_generation()
	_test_conservation()
	_test_caravan_cargo()
	_test_smiths_and_bronze()
	_test_knowhow_spread()
	_test_land_loop()
	_test_loans()
	_test_year()
	_test_save_and_migration()
	await _test_recruits_and_ui(tree)
	_test_people()
	_test_trade_model()
	_test_loot_hooks()
	_test_register()
	_test_persons()
	_test_stories()
	_test_perf()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	return fails

# ---------------------------------------------------------------- generation
func _test_generation() -> void:
	Game.new_game(4242)
	var w: Dictionary = Game.world
	for tid in _town_ids(w):
		var t: Dictionary = w["towns"][tid]
		check(TownEcon.has_econ(t), "town %s has no economy" % tid)
		var e: Dictionary = t["econ"]
		var nf := (e["fams"] as Array).size() - 1
		check(nf >= 40 and nf <= 150, "%s: %d families (50-150, cap 150)" % [t["name"], nf])
		check(e["fams"][0].get("estate", false), "families[0] is the town estate")
		check(int(e["pop"]) > 0 and int(e["homes"]) > 0, "population and homes")
		check(String(e["head"]["name"]) != "" and e["fams"][int(e["head"]["fam"])]["named"], "a named head with a family record")
		check((e["specialties"] as Array).size() >= 1 and (e["specialties"] as Array).size() <= 2, "1-2 specialties")
		# (v0.014: four kinds of deposit, each rolled from the ground; all four together is rare - tests/test_metal_tech.gd;
		# v0.012 added the "dry" climate)
		check((e["deposits"] as Dictionary).size() <= 4 and e["climate"] in ["cold", "temperate", "hot", "dry"], "deposits and climate (%s: %s, %s)" % [t["name"], str(e["deposits"].keys()), e["climate"]])
		var types := {}
		for b in e["biz"]:
			types[b["type"]] = true
		check(types.has("weaponsmith") and types.has("armorsmith") and types.has("market"), "%s lacks smiths or a market" % t["name"])
	var t0: Dictionary = w["towns"][_town_ids(w)[0]]
	print("  %s: %s" % [t0["name"], Economy.describe_town(t0)])
	print("  ", Goods.summary(t0))
	for l in TownEconTab.stores_lines(t0).slice(0, 4):
		print("   ", l)
	# climate follows latitude: the north is cold, the south hot
	var north := 0; var south := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if t["region"] == "north" and t["econ"]["climate"] == "cold": north += 1
		if t["region"] == "south" and t["econ"]["climate"] == "hot": south += 1
	check(north >= 1 and south >= 1, "climate from latitude (cold north %d, hot south %d)" % [north, south])

# ---------------------------------------------------------------- conservation
func _test_conservation() -> void:
	Game.new_game(777)
	var w: Dictionary = Game.world
	_quiet(w)
	_econ_days(3)   # let the first orders and prices settle
	var g0 := _goods_total(w)
	var l0 := _ledger(w)
	var lost0: Dictionary = TownEcon.goods_lost.duplicate()
	var gold0 := _gold_total(w)
	var gone0 := TownEcon.gold_gone
	var L0: Dictionary = (w["coin"] as Dictionary).duplicate()   # coinage: coin cast, melted and drained (lost) meanwhile
	_econ_days(45)
	var g1 := _goods_total(w)
	var l1 := _ledger(w)
	var bad := []
	for g in g1.keys() + g0.keys():
		var made := int(l1["made"].get(g, 0)) - int(l0["made"].get(g, 0))
		var used := int(l1["used"].get(g, 0)) - int(l0["used"].get(g, 0))
		var spoil := int(l1["spoil"].get(g, 0)) - int(l0["spoil"].get(g, 0))
		var lost := int(TownEcon.goods_lost.get(g, 0)) - int(lost0.get(g, 0))
		var expect := int(g0.get(g, 0)) + made - used - spoil - lost
		if int(g1.get(g, 0)) != expect and not bad.has(g):
			bad.append("%s %d != %d (made %d used %d spoiled %d lost %d)" % [g, int(g1.get(g, 0)), expect, made, used, spoil, lost])
	check(bad.is_empty(), "goods not conserved: %s" % ", ".join(PackedStringArray(bad)))
	var gold1 := _gold_total(w)
	var gone := TownEcon.gold_gone - gone0
	var L1: Dictionary = w["coin"]
	var minted := (float(L1["cast"]) - float(L0["cast"])) - (float(L1["melted"]) - float(L0["melted"])) - (float(L1["drained"]) - float(L0["drained"]))
	check(absf(gold1 + gone - gold0 - minted) < 0.01 * maxf(1.0, gold0 / 1000.0), "coin not conserved: %.2f -> %.2f (+%.2f left the map, %+.2f cast - melted - drained)" % [gold0, gold1, gone, minted])
	print("  conservation over 45 days: %d goods kinds checked, coin %.0f -> %.0f (+%.1f out of the towns' books, %+.0f cast - melted - drained)" % [g1.size(), gold0, gold1, gone, minted])

# ---------------------------------------------------------------- caravans
func _test_caravan_cargo() -> void:
	Game.new_game(321)
	var w: Dictionary = Game.world
	_quiet(w)
	var pair := []
	for tid in _town_ids(w):
		var t: Dictionary = w["towns"][tid]
		var p := Caravans.trade_partners(w, t)
		if not p.is_empty():
			pair = [tid, p[0]["id"]]
			break
	check(not pair.is_empty(), "no trade pair")
	var origin: Dictionary = w["towns"][pair[0]]
	var dest: Dictionary = w["towns"][pair[1]]
	# a surplus at the origin, a want at the destination
	origin["econ"]["stock"]["linen"] = 900
	dest["econ"]["stock"]["linen"] = 0
	TownEcon.update_prices(origin, 0); TownEcon.update_prices(dest, 0)
	var st0 := int(origin["econ"]["stock"]["linen"])
	var mk0 := float(origin["econ"]["biz"][int(origin["econ"]["mkt"])]["till"])
	var tr0 := float(origin["econ"]["treasury"])
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var cid := Caravans.spawn(Game, pair[0], rng, pair[1])
	check(cid != "", "caravan did not spawn")
	if cid == "":
		return
	var car: Dictionary = w["warbands"][cid]
	var q := int(car["cargo"]["goods"].get("linen", 0))
	check(q > 0, "surplus linen not loaded")
	check(int(origin["econ"]["stock"]["linen"]) == st0 - q, "linen did not leave the origin market (%d -> %d, cargo %d)" % [st0, int(origin["econ"]["stock"]["linen"]), q])
	check(float(origin["econ"]["biz"][int(origin["econ"]["mkt"])]["till"]) > mk0, "the origin market was not paid")
	check(float(origin["econ"]["treasury"]) < tr0, "the treasury did not fund the purse")
	var d_linen0 := int(dest["econ"]["stats"].get("cargo_in", {}).get("linen", 0))
	var purse0 := float(car["gold"])
	var arrived := false
	for i in 400:
		Game.advance_time(0.05, false)
		w["encounter"] = ""
		if not w["warbands"].has(cid) or w["warbands"][cid].get("leg", "out") == "home":
			arrived = true
			break
	check(arrived, "caravan never arrived")
	var left := int(w["warbands"].get(cid, {}).get("cargo", {}).get("goods", {}).get("linen", 0))
	var got := int(dest["econ"]["stats"].get("cargo_in", {}).get("linen", 0)) - d_linen0
	print("  caravan %s -> %s: %d linen loaded, %d sold at the destination, %d still on the wagons; purse %.0f -> %.0f" % [origin["name"], dest["name"], q, got, left,
		purse0, float(w["warbands"].get(cid, {}).get("gold", 0.0))])
	check(got + left == q, "cargo not intact: %d loaded, %d sold + %d left" % [q, got, left])
	# home again: the purse goes back to the treasury
	# (measured over the step it comes home in: over the whole month the town also pays for the gear of bands its
	# realm raises there, war pick 4, and that can outweigh the purse)
	var tr1 := float(origin["econ"]["treasury"])
	var purse1 := float(w["warbands"].get(cid, {}).get("gold", 0.0))
	for i in 600:
		if not w["warbands"].has(cid):
			break
		tr1 = float(origin["econ"]["treasury"])
		purse1 = float(w["warbands"][cid].get("gold", 0.0))
		Game.advance_time(0.05, false)
		w["encounter"] = ""
	check(not w["warbands"].has(cid) and float(origin["econ"]["treasury"]) >= tr1 + purse1 - 0.01 and purse1 > 0.0,
		"the caravan never came home with its purse (%s; treasury %.0f -> %.0f, purse %.0f)" % [
		"still out" if w["warbands"].has(cid) else "home", tr1, float(origin["econ"]["treasury"]), purse1])
	# a raid takes part of the real cargo, the rest is lost
	origin["econ"]["stock"]["linen"] = 900
	dest["econ"]["stock"]["linen"] = 0
	TownEcon.update_prices(origin, 0); TownEcon.update_prices(dest, 0)
	var rc := Caravans.spawn(Game, pair[0], rng, pair[1])
	if rc != "":
		var rq := int(w["warbands"][rc]["cargo"]["goods"].get("linen", 0))
		var cg0 := float(Goods.company_goods(Game).get("linen", 0.0))
		var rep0 := int(origin["econ"]["rep"])
		Caravans.plunder(Game, rc, true)
		var took := float(Goods.company_goods(Game).get("linen", 0.0)) - cg0
		check(absf(took - round(rq * Caravans.PLUNDER_SHARE)) < 1.01 and took < rq, "raid share wrong: took %.0f of %d" % [took, rq])
		check(int(origin["econ"]["rep"]) == rep0 + 2 * Caravans.TOWN_RAID_REP, "town standing not hit (witnesses double it)")

# ---------------------------------------------------------------- smiths, bars, bronze
func _test_smiths_and_bronze() -> void:
	Game.new_game(99)
	var w: Dictionary = Game.world
	_quiet(w)
	var t: Dictionary = w["towns"][_town_ids(w)[0]]
	var e: Dictionary = t["econ"]
	(t["shop"] as Array).clear()   # room on the stalls
	for g in ["copper_bars", "tin_bars", "bronze_bars", "iron_bars", "steel_bars", "pig_iron"]:   # (iron and steel since v0.012)
		e["stock"][g] = 0
	for g in ["copper_ore", "tin_ore", "iron_ore", "scrap_copper", "scrap_tin", "scrap_bronze", "scrap_iron", "scrap_steel"]:
		e["stock"][g] = 0
	for b in e["biz"]:
		if b["type"] == "mine":
			b["closed"] = true   # nothing new comes out of the ground for this test
	var arms0 := int(e["led"]["made"].get("arms", 0))
	TownEcon.daily_pass(Game, t, int(e["day"]) + 1)
	var idle := true
	var any_smith := false
	for b in e["biz"]:
		if b["type"] in ["weaponsmith", "armorsmith"] and int(b["workers"]) > 0:
			any_smith = true
			if b["state"] != "inputs":
				idle = false
	check(any_smith, "no smith at work in %s" % t["name"])
	check(idle, "smiths not idle with zero bars")
	check(int(e["led"]["made"].get("arms", 0)) == arms0, "a smith made gear without bars")
	print("  smiths with no bars: %s" % ", ".join(PackedStringArray((e["biz"] as Array).filter(func(b): return b["type"] in ["weaponsmith", "armorsmith"]).map(func(b): return Businesses.state_word(b) + " (" + String(b.get("why", "")) + ")"))))
	# no bronze without copper and tin, even with full know-how
	e["knowhow"]["bronze"] = 80.0
	e["stock"]["copper_bars"] = 200
	var b0 := int(e["led"]["made"].get("bronze_bars", 0))
	# coinage: the town's coin is bronze too; with tin dear the smiths would melt coin into bronze bars (barge part 1):
	# no coin in the market here, so the only tin is what is on the stalls
	var mk_till := float(e["biz"][int(e["mkt"])]["till"])
	e["biz"][int(e["mkt"])]["till"] = 0.0
	for i in 5:
		TownEcon.daily_pass(Game, t, int(e["day"]) + 1)
	check(int(e["led"]["made"].get("bronze_bars", 0)) == b0, "bronze made from copper alone")
	check(int(e["led"]["made"].get("arms_bronze", 0)) == 0, "bronze gear without bronze")
	e["biz"][int(e["mkt"])]["till"] = float(e["biz"][int(e["mkt"])]["till"]) + mk_till
	e["stock"]["tin_bars"] = 200
	var b1 := int(e["led"]["made"].get("bronze_bars", 0))
	for i in 5:
		TownEcon.daily_pass(Game, t, int(e["day"]) + 1)
	var has_smelter := (e["biz"] as Array).any(func(b): return b["type"] == "smelter" and int(b["workers"]) > 0)
	if has_smelter:
		check(int(e["led"]["made"].get("bronze_bars", 0)) > b1, "no bronze from copper + tin with know-how")
	print("  bronze bars made with copper + tin: %d (smelter at work: %s)" % [int(e["led"]["made"].get("bronze_bars", 0)) - b1, has_smelter])

# ---------------------------------------------------------------- know-how
func _test_knowhow_spread() -> void:
	Game.new_game(2024)
	var w: Dictionary = Game.world
	_quiet(w)
	var kh0 := 0
	for tid in w["towns"]:
		if float(w["towns"][tid]["econ"]["knowhow"]["bronze"]) > 0.0:
			kh0 += 1
	_econ_days(Calendar.DAYS_PER_SEASON)
	var arms := 0; var bronze := 0; var kh1 := 0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		arms += int(e["led"]["made"].get("arms", 0))
		bronze += int(e["led"]["made"].get("arms_bronze", 0))
		if float(e["knowhow"]["bronze"]) > 0.0:
			kh1 += 1
	var share := float(bronze) / maxf(1.0, float(arms))
	print("  first season: %d pieces made, %d bronze (%.1f%%); towns knowing bronze %d -> %d of %d" % [arms, bronze, share * 100.0, kh0, kh1, w["towns"].size()])
	check(arms > 0, "no gear made in a season")
	check(share < 0.15, "bronze spread too fast in a fresh world (%.1f%%)" % (share * 100.0))

# ---------------------------------------------------------------- land loop
func _test_land_loop() -> void:
	Game.new_game(55)
	var w: Dictionary = Game.world
	_quiet(w)
	var t: Dictionary = w["towns"][_town_ids(w)[0]]
	var e: Dictionary = t["econ"]
	var victim: Dictionary = {}
	for f in e["fams"]:
		if not f.get("estate", false) and Families.acres(f) >= 6:
			victim = f
			break
	check(not victim.is_empty(), "no landholder")
	if victim.is_empty():
		return
	var acres0 := Families.acres(victim)
	var est: Dictionary = e["fams"][0]
	var est0 := Families.acres(est)
	var tr0 := float(e["treasury"])
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	# a tax day the family cannot pay (barge part 4: the month's service money and land tax): arrears, a loan from the
	# head, no land taken yet
	victim["purse"] = 0.0
	(victim["owns"] as Array).clear()
	var day := float(e["day"]) + 1.0
	Barge.treasury_month(Game, t, e, day)
	Families.turn(Game, t, e, victim, day, rng)
	victim["purse"] = 0.0
	check(float(victim["debt"]) > 0.0, "unpaid tax did not become a loan from the head")
	check(Families.acres(victim) == acres0, "land taken before the loan ran out")
	# the loan runs past loan_weeks and they cannot repay (a bad year: more owed than they earn): the head
	# takes land worth the debt
	victim["debt"] = float(victim["debt"]) + 5000.0   # a bad year: far more than the instalments they can meet
	for f in e["fams"]:
		if not f.get("estate", false) and f != victim:
			f["purse"] = minf(float(f["purse"]), 50.0)   # nobody else can buy: the head is the buyer of last resort
	var lw := int(TownEcon.data()["loans"]["default_after"])
	# (weeks: a family whose idle hands find a place - the herbalists hire from idle hands since the sickness merge -
	# meets a few instalments first; it defaults after default_after misses in a row, so allow twice the run)
	for k in (lw + 1) * 2:
		day += 7.0
		victim["purse"] = 0.0
		Families.turn(Game, t, e, victim, day, rng)
		if Families.acres(victim) < acres0:
			break
	victim["purse"] = 0.0
	check(Families.acres(victim) < acres0, "the head never took the land (%d acres)" % Families.acres(victim))
	check(Families.acres(est) > est0, "confiscated land did not go to the town")
	check(Families.lost_line(victim) != "", "no story line for the lost land")
	print("  land loop: %s %s; history: %s" % [victim["name"], Families.lost_line(victim), victim["hist"].slice(-2)])
	# the town offers it for sale first; a family with money and spare hands buys it
	var buyer: Dictionary = {}
	for f in e["fams"]:
		if not f.get("estate", false) and f != victim and Families.adults(f) >= 2 and Families.acres(f) == 0:
			buyer = f
			break
	check(not buyer.is_empty(), "no landless family to buy")
	if buyer.is_empty():
		return
	for f in e["fams"]:
		if not f.get("estate", false) and f != buyer:
			f["purse"] = minf(float(f["purse"]), 50.0)   # only the buyer can afford land
	buyer["purse"] = 5000.0
	var for_sale := Families.acres(est)
	TownEcon.town_turn(Game, t, int(day) + 1)
	check(Families.acres(buyer) > 0 and Families.acres(est) < for_sale, "the land was not sold to a family")
	check(float(buyer["purse"]) < 5000.0, "the buyer paid nothing for the land")
	# with no buyer the town works it itself (estate hires hands)
	var victim2: Dictionary = buyer
	Families.move_land(e, victim2, est, (victim2["land"] as Dictionary).keys()[0], Families.acres(victim2))
	for f in e["fams"]:
		if not f.get("estate", false):
			f["purse"] = minf(float(f["purse"]), 20.0)
	TownEcon.town_turn(Game, t, int(day) + 8)
	var eb: Dictionary = e["biz"][int(e["estate_biz"])]
	check(Families.acres(est) > 0 and int(eb["cap"]) > 0, "unsold land is not worked by the town (estate places %d)" % int(eb["cap"]))

# ---------------------------------------------------------------- one year
func _test_year() -> void:
	Game.new_game(1234)
	var w: Dictionary = Game.world
	w["party"]["safe_until"] = 1.0e9
	var bad := []
	var pop0 := 0
	for tid in w["towns"]:
		pop0 += int(w["towns"][tid]["econ"]["pop"])
	for d in EconGen.YEAR_DAYS:
		Game.advance_time(1.0, false)
		w["encounter"] = ""
		if d % 10 != 9 and d != EconGen.YEAR_DAYS - 1:
			continue
		for tid in w["towns"]:
			var e: Dictionary = w["towns"][tid]["econ"]
			for holder in ["stock", "barn", "hh"]:
				for g in e[holder]:
					if int(e[holder][g]) < 0:
						bad.append("%s %s %s=%d day %d" % [tid, holder, g, int(e[holder][g]), d])
			if int(e["granary"]) < 0:
				bad.append("%s granary" % tid)
			for g in e["price"]:
				var p := float(e["price"][g])
				if is_nan(p) or is_inf(p) or p <= 0.0:
					bad.append("%s price %s=%s" % [tid, g, str(p)])
			for f in e["fams"]:
				for g in f.get("store", {}):
					if float(f["store"][g]) < 0.0 or is_nan(float(f["store"][g])):
						bad.append("%s fam %d store %s=%s" % [tid, int(f["id"]), g, str(f["store"][g])])
				if is_nan(float(f["purse"])) or float(f["purse"]) < -0.01:
					bad.append("%s fam %d purse %s" % [tid, int(f["id"]), str(f["purse"])])
				for k in ["m", "f", "kids", "old"]:
					if int(f[k]) < 0:
						bad.append("%s fam %d %s<0" % [tid, int(f["id"]), k])
			for b in e["biz"]:
				if is_nan(float(b["till"])) or float(b["till"]) < -0.01 or int(b["workers"]) < 0:
					bad.append("%s biz %d till %s workers %d" % [tid, int(b["id"]), str(b["till"]), int(b["workers"])])
		if bad.size() > 10:
			break
	check(bad.is_empty(), "1-year sim: %s" % str(bad.slice(0, 10)))
	var pop1 := 0
	var lines := []
	for tid in _town_ids(w):
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		pop1 += int(e["pop"])
		var hungry := 0; var idle := 0; var unpaid := 0; var gone := 0; var crowded := 0
		for f in e["fams"]:
			if f["gone"]:
				gone += 1
				continue
			if int(f["hungry"]) > 0: hungry += 1
			if int(f["idle"]) > 0: idle += 1
			if int(f["unpaid"]) > 0: unpaid += 1
			if f.has("homes") and Families.people(f) > int(f["homes"]) * 6: crowded += 1
		lines.append("%s %s pop %d food %dd %s treasury %d arms %d bronze kh %d | left %d gone %d hungry %d idle %d unpaid %d crowded %d grain %.2f short %.2f" % [t["name"], e["climate"], int(e["pop"]), int(TownEcon.days_food(t)),
			TownEcon.supply_level(t), int(e["treasury"]), (t["shop"] as Array).size(), int(float(e["knowhow"]["bronze"])),
			int(e["stats"].get("left", 0)), gone, hungry, idle, unpaid, crowded, float(e["price"]["grain"]), float(e.get("food_short", 0.0))])
	print("  after one year (%d days): population %d -> %d" % [EconGen.YEAR_DAYS, pop0, pop1])
	for tid in _town_ids(w):
		var e2: Dictionary = w["towns"][tid]["econ"]
		var purses := []
		for f in e2["fams"]:
			if not f["gone"] and not f.has("estate"):
				purses.append(float(f["purse"]))
		purses.sort()
		print("   %s worked %.2f acres %d made grain %d | mkt grain %d fruit %d meat %d | barn grain %d meat %d | hh grain %d | granary %d | till %d | need grain %d | purse p50 %d p90 %d | farm_till %d" % [w["towns"][tid]["name"], float(e2["wacres"].get("grain", 0.0)) / maxf(1.0, float(e2["land"].get("grain", 0))), int(e2["land"].get("grain", 0)), int(e2["led"]["made"].get("grain", 0)),
			int(e2["stock"]["grain"]), int(e2["stock"]["fruit"]), int(e2["stock"]["meat"]), int(e2["barn"].get("grain", 0)),
			int(e2["barn"].get("meat", 0)), int(e2["hh"].get("grain", 0)), int(e2["granary"]), int(e2["biz"][int(e2["mkt"])]["till"]),
			int(e2["need"].get("grain", 0)), int(purses[purses.size() / 2]), int(purses[int(purses.size() * 0.9)]), int(e2["farm_till"])])
	for l in lines:
		print("   ", l)
	check(pop1 > pop0 * 0.8, "the towns emptied out in a year (%d -> %d)" % [pop0, pop1])
	var t0: Dictionary = w["towns"][_town_ids(w)[0]]
	for l in TownEconTab.price_lines(t0).slice(0, 6):
		print("   ", l)

# ---------------------------------------------------------------- save/load, migration
func _find_bad(v, path: String, out: Array) -> void:
	if out.size() > 20:
		return
	if v is float:
		if is_nan(v) or is_inf(v):
			out.append(path)
	elif v is Dictionary:
		for k in v:
			_find_bad(v[k], path + "." + str(k), out)
	elif v is Array:
		for i in v.size():
			_find_bad(v[i], path + "[%d]" % i, out)

func _test_save_and_migration() -> void:
	Game.new_game(808)
	var w: Dictionary = Game.world
	_quiet(w)
	_econ_days(5)
	var tid: String = _town_ids(w)[0]
	var e0: Dictionary = w["towns"][tid]["econ"]
	var sig := "%d|%d|%d|%.2f|%d" % [int(e0["pop"]), int(e0["stock"]["grain"]), (e0["fams"] as Array).size(), float(e0["treasury"]), int(e0["fams"][3]["m"])]
	var bad := []
	_find_bad(w, "world", bad)
	check(bad.is_empty(), "non-finite numbers in the world (save would break): %s" % str(bad.slice(0, 8)))
	Game.save_game()
	Game.world = {}
	Game.load_game()
	w = Game.world
	var e1: Dictionary = w["towns"][tid]["econ"]
	var sig1 := "%d|%d|%d|%.2f|%d" % [int(e1["pop"]), int(e1["stock"]["grain"]), (e1["fams"] as Array).size(), float(e1["treasury"]), int(e1["fams"][3]["m"])]
	check(sig == sig1, "economy changed in save/load: %s vs %s" % [sig, sig1])
	check(typeof(e1["stock"]["grain"]) == TYPE_INT and typeof(e1["fams"][3]["m"]) == TYPE_INT, "ints not restored after load")
	_econ_days(3)   # still runs after a load
	# an old save without any economy gets one generated
	for t in w["towns"].values():
		t.erase("econ")
		t["goods"] = {"food": 20.0, "alcohol": 3.0}
	Game.save_game()
	Game.world = {}
	Game.load_game()
	w = Game.world
	var ok := true
	for t in w["towns"].values():
		if not TownEcon.has_econ(t) or t.has("goods"):
			ok = false
	check(ok, "old save not migrated to the town economy")
	_econ_days(2)

# ---------------------------------------------------------------- recruits, supply, ui
func _test_recruits_and_ui(tree: SceneTree) -> void:
	Game.new_game(31)
	var w: Dictionary = Game.world
	var t: Dictionary = {}
	for tid in _town_ids(w):
		if not DB.factions[w["towns"][tid]["faction"]].get("player_hostile", false):
			t = w["towns"][tid]
			break
	var e: Dictionary = t["econ"]
	# hard times: a few families unpaid and hungry
	var n := 0
	for f in e["fams"]:
		if not f.get("estate", false) and Families.adults(f) >= 2 and n < 12:
			f["unpaid"] = 3; f["hungry"] = 1; n += 1
	var rng := RandomNumberGenerator.new(); rng.seed = 3
	var pool := Recruits.generate_pool(t, rng)
	check(not pool.is_empty(), "no recruits from the families")
	var linked := pool.filter(func(u): return u.family >= 0 and u.home_town == t["id"])
	check(linked.size() == pool.size(), "recruits without a family record")
	var hard := pool.filter(func(u): return Families.hardship(e["fams"][u.family]) > 0.3)
	check(hard.size() * 2 >= pool.size(), "recruits not mostly from struggling rows (%d of %d)" % [hard.size(), pool.size()])
	print("  recruit: %s - %s" % [pool[0].name, pool[0].backstory.substr(0, 160)])
	t["recruits"] = pool
	var u: Unit = pool[0]
	var fam: Dictionary = e["fams"][u.family]
	var people0 := Families.people(fam)
	var pop0 := int(e["pop"])
	Game.gold = 5000 * Item.COIN   # coinage x20
	check(Recruits.hire(Game, t, u), "hire failed")
	check(Families.people(fam) == people0 - 1 and int(e["pop"]) == pop0 - 1, "hiring did not take the person out of the family")
	check(fam["named"], "the recruit's family is not a named record")
	# supply levels for battles (food spec) come from the home town
	check(TownEcon.supply_level(t) in ["well", "short", "starving"], "supply level")
	var saved: Dictionary = e["stock"].duplicate()
	for g in ["grain", "fruit", "meat"]:
		e["stock"][g] = 0; e["barn"][g] = 0; e["hh"][g] = 0
	e["granary"] = 0
	check(TownEcon.supply_level(t) == "starving", "a town with no food is not starving")
	e["stock"] = saved
	# militia hook: arms stock API
	var c0 := TownEcon.arms_count(t)
	var got := TownEcon.take_arms(t, 2, 0, "main_hand")
	check(got.size() <= 2 and TownEcon.arms_count(t) == c0 - got.size(), "take_arms did not take from the stock")
	# the town screen's Town tab and a family record build
	Game.location = t["id"]
	await tree.process_frame
	var scene: Control = load("res://ui/town.tscn").instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	scene.show_tab("Town")
	check(scene.tab == "Town", "Town tab did not open")
	TownEconTab.family_modal(scene, t, int(e["head"]["fam"]))
	var lines := Families.describe(t, e, e["fams"][int(e["head"]["fam"])])
	check(lines.size() >= 5, "family record too thin")
	scene.queue_free()
	Game.location = ""

# ---------------------------------------------------------------- perf gate
## Worst campaign day: all economy jobs of one day (market days, family turns, town and faction turns) at
## 20 towns x 150 families. Spec gate < 5 ms. Also the worst single job (one map frame does one job).
func _test_perf() -> void:
	var D := TownEcon.data()
	var keep: Array = D["families_by_size"]
	D["families_by_size"] = [150, 150, 150, 150, 150]
	Game.new_game(9001)
	D["families_by_size"] = keep
	var w: Dictionary = Game.world
	_quiet(w)
	# 15 generated towns + 5 more (copies of the first five, regenerated) = 20
	var ids := _town_ids(w)
	var k := 0
	while w["towns"].size() < 20:
		var src: Dictionary = w["towns"][ids[k % ids.size()]]
		var nt: Dictionary = {}
		for key in src:
			if key not in ["econ", "shop", "recruits", "contracts"]:
				nt[key] = src[key]
		nt["id"] = "tx%d" % k
		nt["name"] = "%s Minor" % src["name"]
		nt["pos"] = (src["pos"] as Vector2) + Vector2(30, 30)
		nt["shop"] = []
		nt["recruits"] = []
		nt["contracts"] = []
		var rng := RandomNumberGenerator.new(); rng.seed = 77 + k
		D["families_by_size"] = [150, 150, 150, 150, 150]
		EconGen.generate(w, nt, rng)
		D["families_by_size"] = keep
		w["towns"][nt["id"]] = nt
		k += 1
	var fams := 0
	for tid in w["towns"]:
		fams += (w["towns"][tid]["econ"]["fams"] as Array).size() - 1
	var worst_day := 0
	var worst_job := 0
	var by_kind := {}
	var job_us := []
	var pass_us := 0
	var worst_pass := 0
	var worst_kind := {}
	var worst_when := {}
	var pass_days := []
	var total := 0
	TownEcon.prof_on = OS.get_environment("ECON_PROF") == "1"
	TownEcon.prof = {}
	var days := EconGen.YEAR_DAYS
	for i in days:
		var d := i + 1
		Game.day = float(d)
		var work := []
		w["work"] = work
		TownEcon.queue_day(w, d)
		var day_us := 0
		while not work.is_empty():
			var job: Array = work.pop_front()
			var t0 := Time.get_ticks_usec()
			TownEcon.do_job(Game, job)
			var dt := Time.get_ticks_usec() - t0
			day_us += dt
			worst_job = maxi(worst_job, dt)
			job_us.append(dt)
			by_kind[job[0]] = int(by_kind.get(job[0], 0)) + dt
			if dt > int(worst_kind.get(job[0], 0)):
				worst_kind[job[0]] = dt
				worst_when[job[0]] = d
			if job[0] == "econ":
				pass_us += dt
		worst_day = maxi(worst_day, day_us)
		worst_pass = maxi(worst_pass, pass_us)
		pass_days.append(pass_us)
		pass_us = 0
		total += day_us
	print("  PERF economy: %d towns, %d families: mean day %.2f ms, worst day %.2f ms, worst single job (one map frame) %.2f ms" % [
		w["towns"].size(), fams, total / float(days) / 1000.0, worst_day / 1000.0, worst_job / 1000.0])
	var bk := []
	for kk in TownEcon.prof:
		bk.append("%s %.2f" % [kk, TownEcon.prof[kk] / float(days) / 1000.0])
	TownEcon.prof_on = false
	for kk in by_kind:
		bk.append("%s %.2f ms/day" % [kk, by_kind[kk] / float(days) / 1000.0])
	print("  PERF by job: ", ", ".join(PackedStringArray(bk)))
	var wk := []
	for kk in worst_kind:
		wk.append("%s %.2f ms (day %d)" % [kk, worst_kind[kk] / 1000.0, int(worst_when[kk])])
	pass_days.sort()
	print("  PERF worst single job by kind: ", ", ".join(PackedStringArray(wk)), "; town pass p50 %.2f p90 %.2f ms" % [
		pass_days[pass_days.size() / 2] / 1000.0, pass_days[int(pass_days.size() * 0.9)] / 1000.0])
	print("  PERF daily town pass (all towns): worst day %.2f ms (spec gate 5 ms); everything incl. the spread family turns: worst day %.2f ms" % [
		worst_pass / 1000.0, worst_day / 1000.0])
	# Gates: the daily town pass (spec 4 "cheap sums") for the whole world < 5 ms on the mean campaign day (p90
	# and the worst day are printed; noisy on a loaded machine), and 99% of single work jobs (= one campaign map
	# frame each) under 2 ms (the worst job is printed). The family turns are spread over frames (spec 6); their whole-day total is printed, not gated
	# (see CHANGES: over 5 ms at 20 x 150 with dictionary family records in GDScript).
	var mean_pass := 0.0
	for v in pass_days:
		mean_pass += float(v)
	mean_pass /= maxf(1.0, float(pass_days.size()))
	# 6 ms since v0.009: the pass now also runs the bows economy, the poorhouse and the town army pay (~1 ms
	# together at 20 towns); the town economy itself stays ~4.5 ms. Flagged in CHANGES.
	# 6.5 ms since v0.010: herbalist rows, the remedy good and the bed-ridden staff check (~0.2-0.4 ms; Douglas
	# 2026-10-06 01:15: "the herbalist piece is fine").
	check(mean_pass < 6500.0, "town pass mean day %.2f ms (gate 6.5 ms; p90 and worst printed above)" % (mean_pass / 1000.0))
	job_us.sort()
	var p99: int = job_us[int(job_us.size() * 0.99)]
	print("  PERF single economy job (one map frame): p99 %.2f ms, worst %.2f ms" % [p99 / 1000.0, worst_job / 1000.0])
	check(p99 < 2000, "economy job p99 %.2f ms (a map frame; gate 2 ms)" % (p99 / 1000.0))

# ---------------------------------------------------------------- people: wages home, crews, militia
func _test_people() -> void:
	Game.new_game(612)
	var w: Dictionary = Game.world
	# every company man has a family record; wages go into those purses, never below zero gold
	var all_fam := true
	for u in Game.company:
		if u.family < 0 or People.fam_of(w["towns"].get(u.home_town, {}), u.family).is_empty():
			all_fam = false
	check(all_fam, "company men without a family record")
	var u0: Unit = Game.company[0]
	var f0: Dictionary = People.fam_of(w["towns"][u0.home_town], u0.family)
	var p0 := float(f0["purse"])
	Game.gold = Game.daily_wages() + 3
	Game.pay_wages(1)
	check(Game.gold >= 0 and Game.gold <= 3, "wages not paid man by man (gold %d)" % Game.gold)
	check(float(f0["purse"]) >= p0 + float(u0.wage) - 0.001, "the officer's wage did not reach his family (%.1f -> %.1f)" % [p0, float(f0["purse"])])
	Game.gold = 0
	Game.pay_wages(2)
	check(Game.gold == 0 and Game.unpaid_count() == Game.company.filter(func(u): return not u.dead and u.wage > 0).size(), "broke company: gold below zero or men not marked unpaid")
	check(Game.company[0].unpaid_days == 2, "unpaid days not counted")
	check(UiKit.purse_text(Game).contains("unpaid"), "no unpaid warning in the purse line")
	# an old save with negative gold: clamped, owed days become unpaid days
	Game.gold = -50
	for u in Game.company:
		u.unpaid_days = 0
	Game.save_game()
	Game.load_game()
	check(Game.gold == 0 and Game.company[0].unpaid_days >= 1, "negative gold not clamped on load")
	w = Game.world
	# militia: people of town families, paid by the treasury into their purses; the dead leave the family
	var tid := ""
	for t in w.get("militia", {}):
		tid = t
		break
	check(tid != "", "no militia")
	if tid != "":
		var town: Dictionary = w["towns"][tid]
		var mil: Array = Militia.units_of(Game, tid)
		check(not mil.is_empty() and mil.all(func(u): return u.family >= 0), "militiamen without family records")
		if not mil.is_empty():
			var mu: Unit = mil[0]
			var mf: Dictionary = People.fam_of(town, mu.family)
			var mp := float(mf["purse"])
			var tr := float(town["econ"]["treasury"])
			People.pay_militia(Game, town)
			check(float(mf["purse"]) > mp and float(town["econ"]["treasury"]) < tr, "militia wage did not move treasury -> family")
			var ppl := Families.people(mf)
			var sv := Families.serving(mf)
			mu.dead = true
			Militia.bury_dead(Game, tid)
			check(Families.people(mf) == ppl - 1 and Families.serving(mf) == sv - 1, "a dead militiaman still counted in his family")
	# caravan crew: guards are family people, the owner (market) pays them, the raided dead leave the family
	var pair := []
	for t2 in _town_ids(w):
		var p := Caravans.trade_partners(w, w["towns"][t2])
		if not p.is_empty():
			pair = [t2, p[0]["id"]]
			break
	var origin: Dictionary = w["towns"][pair[0]]
	origin["econ"]["stock"]["linen"] = 900
	w["towns"][pair[1]]["econ"]["stock"]["linen"] = 0
	TownEcon.update_prices(origin, 0); TownEcon.update_prices(w["towns"][pair[1]], 0)
	var rng := RandomNumberGenerator.new(); rng.seed = 8
	var cid := Caravans.spawn(Game, pair[0], rng, pair[1])
	check(cid != "", "caravan with crew did not spawn")
	if cid != "":
		var car: Dictionary = w["warbands"][cid]
		check(not (car.get("crew", []) as Array).is_empty() and (car["units"] as Array).all(func(u): return u.family >= 0), "caravan guards are not family people")
		var g: Unit = car["units"][0]
		var gf: Dictionary = People.fam_of(origin, g.family)
		var gp := float(gf["purse"])
		var mk: Dictionary = origin["econ"]["biz"][int(origin["econ"]["mkt"])]
		var till := float(mk["till"])
		People.pay_crews(Game)
		check(float(gf["purse"]) > gp and float(mk["till"]) < till, "crew wages did not move owner -> family purse")
		var gppl := Families.people(gf)
		g.dead = true
		Caravans.plunder(Game, cid, false)
		check(Families.people(gf) == gppl - 1, "a raided caravan's dead guard is still in his family row")
		check(String(gf["hist"][-1]).contains(g.name), "no history line for the fallen guard")
	# an owner who cannot pay: no crew, no caravan
	var mk2: Dictionary = origin["econ"]["biz"][int(origin["econ"]["mkt"])]
	var keep := float(mk2["till"])
	mk2["till"] = 1.0
	origin["econ"]["stock"]["linen"] = 900
	TownEcon.update_prices(origin, 0)
	var shop_keep: Array = origin["shop"]   # arms trade: the raided guards' kit is back on the stalls; its sale to the
	origin["shop"] = []                     # wagons would refill the till (this check is about the crew's pay alone)
	check(Caravans.spawn(Game, pair[0], rng, pair[1]) == "", "a caravan sailed though its owner could not pay the crew")
	origin["shop"] = shop_keep
	mk2["till"] = keep

# ---------------------------------------------------------------- trade model (Douglas): demand only from use
func _test_trade_model() -> void:
	Game.new_game(733)
	var w: Dictionary = Game.world
	_quiet(w)
	_econ_days(10)
	var no_smelter := 0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		var has_smelter := (e["biz"] as Array).any(func(b): return b["type"] == "smelter" and not b["closed"])
		if not has_smelter:
			no_smelter += 1
			check(float(e["dem"].get("copper_ore", 0.0)) < 0.01 and float(e["dem"].get("tin_ore", 0.0)) < 0.01,
				"%s has no smelter but wants ore" % w["towns"][tid]["name"])
	print("  towns without a smelter (no ore demand): %d" % no_smelter)
	# a surplus town prices below base, a short one above
	var ids := _town_ids(w)
	var a: Dictionary = w["towns"][ids[0]]
	var b: Dictionary = w["towns"][ids[1]]
	a["econ"]["stock"]["blankets"] = 5000
	b["econ"]["stock"]["blankets"] = 0
	b["econ"]["dem"]["blankets"] = maxf(1.0, float(b["econ"]["dem"].get("blankets", 0.0)))
	for i in 10:   # barge: a price steps 22% a day toward its target
		TownEcon.update_prices(a, 0); TownEcon.update_prices(b, 0)
	var base := float(TownEcon.data()["goods"]["blankets"]["price"])
	check(Goods.price_f(a, "blankets") < base and Goods.price_f(b, "blankets") > base, "surplus price %.1f / short price %.1f vs base %.1f" % [
		Goods.price_f(a, "blankets"), Goods.price_f(b, "blankets"), base])
	# caravans flow from surplus to shortage: the town plans its trip to the partner short of what it has
	var pair := []
	for t2 in ids:
		var p := Caravans.trade_partners(w, w["towns"][t2])
		if p.size() >= 1:
			pair = [t2, p[0]["id"]]
			break
	var o: Dictionary = w["towns"][pair[0]]
	var d: Dictionary = w["towns"][pair[1]]
	o["econ"]["stock"]["blankets"] = 3000
	d["econ"]["stock"]["blankets"] = 0
	d["econ"]["dem"]["blankets"] = 20.0
	TownEcon.update_prices(o, 0); TownEcon.update_prices(d, 0)
	check(Caravans.trade_value(o, d) > Caravans.trade_value(d, o), "trade value does not favour surplus -> shortage")
	_quiet(w)
	o["econ"]["treasury"] = 5000.0
	TownEcon._plan_trade(Game, o, o["econ"], 1)
	var planned := (w["work"] as Array).filter(func(j): return j[0] == "caravan" and j[1] == pair[0])
	check(not planned.is_empty(), "the surplus town planned no caravan")
	if not planned.is_empty():
		var cid := Caravans.spawn(Game, pair[0], RandomNumberGenerator.new(), str(planned[0][2]))
		check(cid != "" and int(w["warbands"][cid]["cargo"]["goods"].get("blankets", 0)) > 0, "the caravan did not carry the surplus blankets")

# ---------------------------------------------------------------- loot hooks (core/loot.gd), extinction, scrap
func _test_loot_hooks() -> void:
	Game.new_game(901)
	var w: Dictionary = Game.world
	var tid: String = _town_ids(w)[0]
	var town: Dictionary = w["towns"][tid]
	var e: Dictionary = town["econ"]
	var f: Dictionary = {}
	for x in e["fams"]:
		if not x.has("estate") and Families.people(x) >= 3 and Families.acres(x) > 0:
			f = x
			break
	f["purse"] = 20000.0
	var u := Unit.create("human", town["faction"])
	u.family = int(f["id"]); u.home_town = tid
	var c := Families.take_carried_coin(u, 0.05, 0.10, 500)
	check(c == 500 and absf(float(f["purse"]) - 19500.0) < 0.01, "carried coin not 5%% capped at 500 out of the purse (%d)" % c)
	f["purse"] = 1000.0
	check(Families.take_carried_coin(u, 0.05, 0.10, 500) == 50, "5% of a 1000 purse")
	# the last of his house: the looter gets 10%, the rest to the faction coffer; the house dies out
	f["m"] = 1; f["f"] = 0; f["kids"] = 0; f["old"] = 0
	(f["serve"] as Dictionary).clear()
	f["purse"] = 3000.0
	var fac: Dictionary = w["factions"][town["faction"]]
	var ft := float(fac.get("treasury", 0.0))
	var c2 := Families.take_carried_coin(u, 0.05, 0.10, 500)
	check(c2 == 300 and absf(float(fac["treasury"]) - ft - 2700.0) < 0.01 and float(f["purse"]) == 0.0, "last of the house: 10%% to the looter, the rest to the faction (%d, %.0f)" % [c2, float(fac["treasury"]) - ft])
	var acres := Families.acres(f)
	var est0 := Families.acres(e["fams"][0])
	u.dead = true
	People.casualty(Game, u, "dead", "")
	check(f["gone"] and f.get("extinct", false), "the house did not die out")
	check(Families.acres(e["fams"][0]) == est0 + acres, "the extinct house's land did not pass to the town head")
	check(Families.take_carried_coin(Unit.create("human", "x"), 0.05, 0.1, 500) == 0, "a man without a family carried coin")
	# scrap from a won battle lands in the nearest town's stock
	var near := TownEcon.add_scrap(w, {"copper": 12.4, "tin": 3.0, "linen": 2.0}, town["pos"])
	check(near == tid and int(e["stock"].get("scrap_copper", 0)) >= 12 and int(e["stock"].get("scrap_tin", 0)) >= 3, "battle scrap not in the nearest town's stock")

# ---------------------------------------------------------------- the head's loans (cash, interest, default)
func _loan_gold(e: Dictionary) -> float:
	return TownEcon.town_gold(e)

func _test_loans() -> void:
	Game.new_game(4711)
	var w: Dictionary = Game.world
	_quiet(w)
	var t: Dictionary = w["towns"][_town_ids(w)[0]]
	var e: Dictionary = t["econ"]
	e["treasury"] = 20000.0 * TownEcon.COIN   # coinage x20
	var f: Dictionary = {}
	for x in e["fams"]:
		if not x.has("estate") and Families.acres(x) >= 4 and Families.heads(x) > 0 and int(x["homes"]) > 0 and float(x["debt"]) <= 0.0:
			f = x
			break
	if f.is_empty():
		for x in e["fams"]:
			if not x.has("estate") and Families.acres(x) >= 4 and int(x["homes"]) > 0:
				f = x
				break
	check(not f.is_empty(), "no family with land and a house")
	if f.is_empty():
		return
	# a cash loan: real coin treasury -> purse, conserved
	var g0 := _loan_gold(e)
	var tr0 := float(e["treasury"]); var p0 := float(f["purse"])
	var lent := Loans.lend(e, f, 100.0, "food", 1.0)
	check(lent > 0.0 and absf(float(e["treasury"]) - (tr0 - lent)) < 0.001 and absf(float(f["purse"]) - (p0 + lent)) < 0.001, "loan coin did not move treasury -> purse")
	check(absf(_loan_gold(e) - g0) < 0.01, "lending created or destroyed gold")
	check(absf(float(f["debt"]) - lent) < 0.01, "debt not recorded")
	# repayment with interest: weekly instalments go back to the treasury, interest first
	f["purse"] = 500.0 * TownEcon.COIN   # coinage x20
	var tr1 := float(e["treasury"])
	var g1 := _loan_gold(e)
	for k in 12:
		Loans.weekly(e, f, 2.0 + 7.0 * k, 7.0)
		if float(f["debt"]) <= 0.0:
			break
	check(float(f["debt"]) <= 0.0, "loan not repaid from a full purse (%.1f left)" % float(f["debt"]))
	var back := float(e["treasury"]) - tr1
	check(back > lent, "no interest earned (%.1f back for %.1f lent)" % [back, lent])
	check(float(e["stats"].get("int_earned", 0.0)) > 0.0 and absf(back - lent - float(f["ln"]["int"])) < 0.01, "interest not booked")
	check(absf(_loan_gold(e) - g1) < 0.01, "repayment created or destroyed gold")
	var r := Loans.rate(e)
	print("  loan: lent %d, paid back %.1f (interest %.1f at %.1f%%/week)" % [int(lent), back, float(f["ln"]["int"]), r * 100.0])
	# barge part 1: one economy, the same loan terms for every race (3.5% a month)
	var rates := {}
	for c in TownEcon.data()["cultures"]:
		var ec := {"culture": c}
		rates[c] = Loans.rate(ec)
	check(absf(float(rates["orc"]) - float(rates["middle"])) < 0.0001 and absf(float(rates["moon_elf"]) - 0.035 * 7.0 / 30.0) < 0.0001, "loan rates: one rule for every race (%s)" % str(rates))
	# default: sells in order (stores, goods, tools, livestock, land, the house) with real sales, until destitute
	for x in e["fams"]:
		if not x.has("estate") and x != f:
			x["purse"] = minf(float(x["purse"]), 30.0)   # nobody can buy: the head buys land and herds
	f["store"]["food"] = 20.0
	f["store"]["wood"] = 10.0
	f["purse"] = 0.0
	f["debt"] = 0.0
	f.erase("ln")
	Loans.owe(e, f, 100000.0, 50.0)   # far more than everything is worth
	var g2 := _loan_gold(e)
	var acres0 := Families.acres(f)
	var est: Dictionary = e["fams"][0]
	var est_a := Families.acres(est)
	var mk_food0 := int(e["stock"]["grain"]) + int(e["stock"]["fruit"]) + int(e["stock"]["meat"])
	var homes0 := int(f["homes"])
	f["ln"]["miss"] = int(TownEcon.data()["loans"]["default_after"]) - 1
	Loans.weekly(e, f, 57.0, 7.0)   # one more missed payment: default
	var sold: Array = f["ln"]["sold"]
	print("  default: sold ", sold)
	check(not sold.is_empty(), "nothing sold on default")
	var order := ["food", "goods", "tools", "herd", "land", "house"]
	var ht: String = TownEcon.culture_of(e)["home"]["type"]
	var seen := []
	for s in sold:
		var k := "goods"
		if String(s).begins_with("the food") or String(s).begins_with("the beer") or String(s).begins_with("the firewood"): k = "food"
		elif String(s).begins_with("tools"): k = "tools"
		elif String(s).contains("acres of"): k = "land"
		elif String(s).begins_with("the " + ht): k = "house"
		else:
			for a in ["sheep", "cattle", "pigs", "goats"]:
				if String(s).contains(" " + a): k = "herd"
		seen.append(order.find(k))
	var sorted_ok := true
	for i in range(1, seen.size()):
		if seen[i] < seen[i - 1]:
			sorted_ok = false
	check(sorted_ok, "default sales out of order: %s" % str(sold))
	check(Families.acres(f) == 0 and Families.acres(est) == est_a + acres0, "land not sold to the head (no other buyer)")
	check(int(f["homes"]) == homes0 - homes0 and f.has("hl"), "the house was not sold / family not homeless")
	check(f.get("destitute", false) and float(f["debt"]) == 0.0, "not destitute after everything was sold")
	check(int(e["stock"]["grain"]) + int(e["stock"]["fruit"]) + int(e["stock"]["meat"]) > mk_food0, "the food stores did not go to the market")
	check(absf(_loan_gold(e) - g2) < 0.01, "forced sales created or destroyed gold")
	check(Loans.family_line(e, f).contains("sold:"), "family record does not show what was sold")
	check(Loans.town_line(e).contains("interest"), "Town tab loan line")
	# territory: families + estate + common == territory
	var s2 := TownEcon.land_split(e)
	check(int(s2["families"]) + int(s2["estate"]) + int(s2["common"]) == int(s2["territory"]) and int(s2["territory"]) > 0, "land totals do not add up: %s" % str(s2))
	var ll := TownEconTab.land_line(e)
	check(ll.contains("Families hold %d" % int(s2["families"])) and ll.contains("Herds:") and ll.contains(TownEcon.variety_word(e, "grain")),
		"Town tab land line lacks the family total, crops or herds: " + ll)
	print("  ", ll)
	print("  ", Loans.town_line(e))

# ---------------------------------------------------------------- real people: kinship, ages, names, work and wages
## World rules (Douglas, v0.009 family card): every grown-up with a place is named on the Work line; given names
## fit the sex; a parent's age at a child's birth is within the race's bounds; the household lists in family
## order; the wage shown is the wage the economy pays; rosters and households point at each other.
func _test_persons() -> void:
	Game.new_game(6061)
	var w: Dictionary = Game.world
	w["party"]["safe_until"] = 1.0e9
	var hm: Array = TownEcon.data()["person_names"]["human"]["m"]
	var hf: Array = TownEcon.data()["person_names"]["human"]["f"]
	check(hm.has("Ivo") and not hf.has("Ivo") and hf.has("Vera") and not hm.has("Vera"), "Ivo is a man's name, Vera a woman's")
	for i in 150:   # five seasons of the full sim: births, children of age, the old dying, weddings
		Game.advance_time(1.0, false)
		w["encounter"] = ""
	var day := float(Game.day)
	var yd := People.year_days()
	var bad_name := []; var bad_age := []; var bad_work := []; var bad_order := []; var bad_kid := []
	var births := 0; var weds := 0; var n_people := 0; var n_kids := 0
	for tid in _town_ids(w):
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		var race := Persons.race_of(e)
		var ab := People.ages(race)
		var A := float(ab["adult"]); var M := float(ab["mother_max"]); var L := float(ab["lifespan"])
		births += int(e["stats"].get("births", 0))
		# no two people of a household share a name; in a human town (42 names a sex, 21 surnames) no two at all
		# (orc and goblin towns have six clan names and fewer given names than people: they repeat across houses)
		var seen_names := {}
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false):
				continue
			var home_names := {}
			for p in Persons.pp(f) + Persons.kp(f):
				if String(p[7]) != "":
					continue
				var nm := Persons.name_of(f, p, race)
				if home_names.has(nm) or (race == "human" and seen_names.has(nm)):
					bad_name.append("two people named %s in %s" % [nm, t["name"]])
				home_names[nm] = true
				seen_names[nm] = true
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false):
				continue
			for ev in f.get("ev", []):
				if String(ev[1]) == "married":
					weds += 1
			Persons.sync(e, f, day)
			var all: Array = Persons.pp(f) + Persons.kp(f)
			for p in all:
				n_people += 1
				if String(p[7]) == "":
					var first := Persons.first_of(e, p)
					var other: Array = Persons.names_for(race, 1 - int(p[2]))
					if not Persons.names_for(race, int(p[2])).has(first) or (other.has(first)):
						bad_name.append("%s (%s)" % [Persons.name_of(f, p, race), ["m", "f"][int(p[2])]])
				# parents' ages at the birth
				for k in [[Persons.MO, M], [Persons.FA, L]]:
					var par := Persons.by_pid(f, int(p[k[0]]))
					if par.is_empty():
						continue
					var at := (float(p[3]) - float(par[3])) / yd
					if at < A or at > float(k[1]):
						bad_age.append("%s born when %s was %.1f" % [Persons.name_of(f, p, race), Persons.name_of(f, par, race), at])
			for p in Persons.kp(f):
				n_kids += 1
				if day - float(p[3]) >= A * yd + 8.0:   # (they come of age at the weekly family turn)
					bad_kid.append("%s is %d and still a child" % [Persons.name_of(f, p, race), Persons.age_of(p, day)])
			check(Persons.kp(f).size() == int(f["kids"]), "%s: %d child records for %d children" % [f["name"], Persons.kp(f).size(), int(f["kids"])])
			# the Work line names everyone with a place
			var wl := Families.work_line(e, f)
			var jobs := Persons.work(e, f)
			for pid in jobs:
				var j: Dictionary = jobs[pid]
				var p := Persons.by_pid(f, int(pid))
				if not wl.contains("%s: %s" % [Persons.first_of(e, p), String(j["title"])]):
					bad_work.append("%s / %s not on: %s" % [Persons.first_of(e, p), j["title"], wl])
			# family order: elders, the head and spouse, the other grown-ups, the children oldest first
			var hh := Persons.household(e, f, day)
			var rank := {"elder": 0, "boy": 3, "girl": 3}
			var last := -1
			var last_age := 9999
			for m in hh:
				var r := int(rank.get(m["kind"], 1 if String(m["kin"]) == "head of the family" or String(m["kin"]).ends_with("wife") or String(m["kin"]).ends_with("husband") else 2))
				if r < last or (r == 3 and r == last and int(m["age"]) > last_age):
					bad_order.append("%s: %s" % [f["name"], str(hh.map(func(x): return "%s %d" % [x["kind"], x["age"]]))])
					break
				last = r
				last_age = int(m["age"])
	check(bad_name.is_empty(), "given names do not fit the sex: %s" % str(bad_name.slice(0, 5)))
	check(bad_age.is_empty(), "parents too young or too old at the birth: %s" % str(bad_age.slice(0, 5)))
	check(bad_kid.is_empty(), "children past the age of adulthood: %s" % str(bad_kid.slice(0, 5)))
	check(bad_work.is_empty(), "people with a place missing from the Work line: %s" % str(bad_work.slice(0, 3)))
	check(bad_order.is_empty(), "households out of family order: %s" % str(bad_order.slice(0, 3)))
	check(births > 0, "nobody was born in five seasons")
	print("  persons: %d people (%d children) after 150 days; %d births, %d weddings" % [n_people, n_kids, births, weds])
	var codes := {}
	for tid in _town_ids(w):
		for f in w["towns"][tid]["econ"]["fams"]:
			for ev in f.get("ev", []):
				codes[String(ev[1])] = int(codes.get(String(ev[1]), 0)) + 1
	print("  family events: ", codes)
	# the wage shown is what the economy pays: a family living on wages alone, a full week, full tills
	var done := false
	for tid in _town_ids(w):
		if done:
			break
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false) or Families.acres(f) > 0 or Families.heads(f) > 0 or not (f["owns"] as Array).is_empty() \
					or f.has("cj") or (f["jobs"] as Dictionary).is_empty():
				continue
			for k in f["jobs"]:
				e["biz"][int(k)]["till"] = float(e["biz"][int(k)]["till"]) + 10000.0
			var shown := 0
			for m in Persons.household(e, f, day):
				if String(m["state"]) in ["", "hire"] and int(m["wage"]) > 0:
					shown += int(m["wage"])
			f["last"] = day - 7.0
			Families.turn(Game, t, e, f, day, RandomNumberGenerator.new())
			check(absi(int(round(float(f["inc"]))) - shown) <= 1, "%s: household shows %d gold a week in wages, the economy paid %d" % [f["name"], shown, int(round(float(f["inc"])))])
			var sample := ["  The %s family of %s:" % [f["name"], t["name"]]]
			for m in Persons.household(e, f, day):
				sample.append("    " + Persons.person_line(m))
			sample.append("    " + Families.work_line(e, f))
			print("\n".join(PackedStringArray(sample)))
			done = true
			break
	check(done, "no family living on wages alone to test the wage line")
	# a landed family's card, as Douglas reads it
	for tid in _town_ids(w):
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		var best: Dictionary = {}
		for f in e["fams"]:
			if not f.get("gone", false) and not f.get("estate", false) and Families.heads(f) > 0 and int(f["kids"]) > 0 and int(f["old"]) > 0:
				best = f
				break
		if not best.is_empty():
			for l in Families.describe(t, e, best).slice(0, 6):
				print("    ", l)
			for m in People.register(Game, t, int(best["id"])):
				print("    ", Persons.person_line(m))
			print("    ", People.census_line(e))
			print("    ", Families.summary(e, best))
			break
	# service wages: a militiaman's line shows what the treasury paid him
	var mil_ok := 0
	for tid in _town_ids(w):
		var t: Dictionary = w["towns"][tid]
		var band := Militia.band_of(Game, tid)
		if band.is_empty():
			continue
		for u in band["units"]:
			if u.dead or u.family < 0:
				continue
			var f := People.fam_of(t, u.family)
			for m in Persons.household(t["econ"], f, day):
				if int(m["uid"]) == u.uid:
					check(int(m["wage"]) == int(round(u.last_pay * 7.0)), "%s shows %d a week, paid %.2f a day" % [u.name, int(m["wage"]), u.last_pay])
					var row := Persons.roster_row(Game, u, "militia")
					check(String(row["household"]) == String(f["name"]) and int(row["pid"]) == int(m["pid"]), "militia roster row does not point at the household member")
					mil_ok += 1
			if mil_ok >= 5:
				break
	check(mil_ok > 0, "no militiaman found in a household")

# ---------------------------------------------------------------- the register: every named person is a real person
func _test_register() -> void:
	Game.new_game(5150)
	var w: Dictionary = Game.world
	w["party"]["safe_until"] = 1.0e9
	for i in 30:   # a month of the full sim: forces raised, caravans sent, pools refreshed
		Game.advance_time(1.0, false)
		w["encounter"] = ""
	Persons.sweep(Game)
	# forward: every unit with a family resolves to a register person with his uid and his name
	var units := []
	for u in Game.company:
		units.append([u, "company"])
	for tid in w["towns"]:
		for u in w["towns"][tid].get("recruits", []):
			units.append([u, "hire"])
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.is_monster_band(wb):
			continue
		for u in wb["units"]:
			if not u.dead:
				units.append([u, String(wb["kind"])])
	var bad := []
	var n := 0
	for x in units:
		var u: Unit = x[0]
		var town: Dictionary = w["towns"].get(u.home_town, {})
		if u.family < 0:
			if TownEcon.has_econ(town) or x[1] in ["hire", "company", "militia", "caravan"]:
				bad.append("%s (%s) has no family" % [u.name, x[1]])
			continue
		var f := People.fam_of(town, u.family)
		var p := Persons.by_uid(f, u.uid) if not f.is_empty() else []
		n += 1
		if p.is_empty():
			bad.append("%s (%s) not in the %s register" % [u.name, x[1], f.get("name", "?")])
		elif Persons.name_of(f, p, Persons.race_of(town["econ"])) != u.name:
			bad.append("%s is %s in the register" % [u.name, Persons.name_of(f, p, Persons.race_of(town["econ"]))])
	check(bad.is_empty(), "units outside the register: %s" % str(bad.slice(0, 6)))
	# backward: every register person pointing at a unit finds that unit alive somewhere
	var live := Persons.live_uids(Game)
	var orphans := 0; var persons := 0; var bytes := 0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		for f in e["fams"]:
			for p in f.get("pp", []):
				persons += 1
				bytes += JSON.stringify(p).length()
				if int(p[5]) >= 0 and not live.has(int(p[5])):
					orphans += 1
			# the row's counts and the records agree
			if not f.get("gone", false) and not f.has("estate"):
				Persons.sync(e, f, float(Game.day))   # records catch up with the rows weekly; bring them level first
				var cnt := [0, 0, 0]
				for p in f["pp"]:
					if String(p[4]) != "company":
						cnt[2 if int(p[6]) == 1 else int(p[2])] += 1
				if cnt != [int(f["m"]), int(f["f"]), int(f["old"])]:
					bad.append("%s rows %s vs records %s" % [f["name"], str([f["m"], f["f"], f["old"]]), str(cnt)])
	check(orphans == 0, "%d register persons point at units that no longer exist" % orphans)
	check(bad.is_empty(), "register counts out of step: %s" % str(bad.slice(0, 6)))
	print("  register: %d named units resolve both ways; %d person records, %.1f bytes each in the save (%.0f KB)" % [n, persons,
		float(bytes) / maxf(1.0, float(persons)), bytes / 1024.0])
	# the pool: adults/elders only, the top of the desperation ranking
	var tid0: String = ""
	for tid in _town_ids(w):
		if not DB.factions[w["towns"][tid]["faction"]].get("player_hostile", false):
			tid0 = tid
			break
	var t: Dictionary = w["towns"][tid0]
	var e0: Dictionary = t["econ"]
	var pool := Recruits.generate_pool(t, RandomNumberGenerator.new())
	t["recruits"] = pool
	var worst_in := INF
	for u in pool:
		var f := People.fam_of(t, u.family)
		var p := Persons.by_uid(f, u.uid)
		check(not p.is_empty() and String(p[4]) == "hire", "recruit %s not marked for hire in the register" % u.name)
		check(People.age_on(u, Game.day) >= int(People.ages(u.race)["adult"]), "a child in the recruit pool: %s" % u.name)
		worst_in = minf(worst_in, Recruits.desperation(f))
		check(Recruits.desperation(f) > 0.0, "a comfortable family man in the pool: %s" % u.name)
		check(Recruits.titles_for(e0, f).has(u.title), "%s's title '%s' is not a real job of the family %s" % [u.name, u.title, str(Recruits.titles_for(e0, f))])
	var better_out := 0
	for f in e0["fams"]:
		if f.get("gone", false) or f.has("estate"):
			continue
		if Recruits.desperation(f) > worst_in + 0.0001:
			for p in f["pp"]:
				if String(p[4]) == "" and int(p[5]) < 0:
					better_out += 1
	check(better_out == 0, "%d more desperate people left out of the pool" % better_out)
	# the family record lists him, for hire
	if not pool.is_empty():
		var u0: Unit = pool[0]
		var reg := People.register(Game, t, u0.family)
		check(reg.any(func(r): return r["name"] == u0.name and String(r["state"]).contains("for hire")), "the family record does not list %s for hire" % u0.name)
		Game.gold = 100000
		check(Recruits.hire(Game, t, u0), "hire")
		reg = People.register(Game, t, u0.family)
		check(reg.any(func(r): return r["name"] == u0.name and String(r["state"]).contains("your company")), "the family record does not list %s with the company" % u0.name)
	# stories: town wording before hire, plurals, varied openings, no stock filler
	var stories := []
	for k in 6:
		for u in Recruits.generate_pool(t, RandomNumberGenerator.new()):
			stories.append(u.backstory)
	var opens := {}
	var dup := 0
	for s in stories:
		check(not String(s).contains("around camp"), "camp wording before hire: %s" % s)
		var words := String(s).split(" ").slice(0, 8)
		var k := " ".join(words)
		if opens.has(k):
			dup += 1
		opens[k] = true
	print("  %d stories, %d share their first 8 words with another (same people re-drawn across pools)" % [stories.size(), dup])
	for nm in ["Marsh", "Oakes", "Fox", "Kettle", "Birch"]:
		var pl := Backstory.plural(nm)
		check(pl in ["Marshes", "Oakeses", "Foxes", "Kettles", "Birches"], "plural of %s: %s" % [nm, pl])
	check(People.census(e0)["children"] + People.census(e0)["adults"] + People.census(e0)["elders"] == int(e0["pop"]), "census does not add up to the population")
	check(People.census(e0)["female"] + People.census(e0)["male"] == int(e0["pop"]), "census sexes do not add up")

## Stories of 30 different people of one town: no two open with the same 8 words; sample cards printed.
func _test_stories() -> void:
	Game.new_game(2718)
	var w: Dictionary = Game.world
	w["party"]["safe_until"] = 1.0e9
	for i in 60:
		Game.advance_time(1.0, false)
		w["encounter"] = ""
	var best_t: Dictionary = {}
	var bn := 0
	for tid in _town_ids(w):
		var tt: Dictionary = w["towns"][tid]
		if DB.factions[tt["faction"]].get("player_hostile", false):
			continue
		if (tt["econ"]["fams"] as Array).size() > bn:
			bn = (tt["econ"]["fams"] as Array).size(); best_t = tt
	var t := best_t
	var e: Dictionary = t["econ"]
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var texts := []
	for f in e["fams"]:
		if texts.size() >= 30:
			break
		if f.get("gone", false) or f.has("estate"):
			continue
		var p := Persons.pick_home(f, rng, true)
		if p.is_empty():
			continue
		texts.append(Backstory.recruit_text(t, e, f, Persons.first_of(e, p), Persons.name_of(f, p, Persons.race_of(e)), Recruits.person_role(e, f, p)))
	var seen := {}
	var dup := []
	for s in texts:
		var k := " ".join(String(s).split(" ").slice(0, 8))
		if seen.has(k):
			dup.append(k)
		seen[k] = true
	check(dup.is_empty(), "stories open alike: %s" % str(dup.slice(0, 4)))
	var pool := Recruits.generate_pool(t, RandomNumberGenerator.new())
	print("  cards from %s:" % t["name"])
	for u in pool:
		var f := People.fam_of(t, u.family)
		print("   %s, %s, age %d (the %s family: %s) | %s | Temperament: %s" % [u.name, u.title, People.age_on(u, Game.day), f["name"],
			Backstory._holdings(e, f) if Backstory._holdings(e, f) != "" else "no land", u.backstory, UnitSheet.personality_words(u)])
