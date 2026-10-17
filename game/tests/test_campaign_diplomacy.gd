extends RefCounted
## Diplomacy (docs/specs/diplomacy.md): 1000 simulated days keep relations in -100..100, goblins never reach
## NEUTRAL, wars and peaces happen with the default data; the day step costs < 0.1 ms; no caravan route
## between WAR or HOSTILE pairs; band make-up offset within +-20 with officers weighing double; standing
## <= -50 blocks trade and contracts; standing effects and moves; war contracts with the taking-sides bonus;
## save/load round trip and migration of pre-diplomacy saves; the truce after a peace (war pick 2); the relations
## screen; a short full-world run.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _force(w: Dictionary, a: String, b: String, st: String, rel: float) -> void:
	var p: Dictionary = w["diplo"]["pairs"][Diplomacy.pair_key(a, b)]
	p["state"] = st
	p["rel"] = rel
	p["past"] = 0
	p["held"] = 0
	Diplomacy._sync_wars(w)

func _set_standing(fid: String, s: int) -> void:
	var p: Dictionary = Game.world["diplo"]["player"][fid]
	p["earned"] = float(s - int(p["comp"]))
	Diplomacy._mirror(Game, fid)

func run(tree: SceneTree) -> int:
	_sim_1000()
	_routes()
	_composition()
	_standing_effects()
	_war_contract()
	_save_load()
	_truce()
	await _screen(tree)
	_full_world()
	return fails

# ---------------------------------------------------------------- 1000 days
func _sim_1000() -> void:
	Game.new_game(2024)
	var w: Dictionary = Game.world
	var dp: Dictionary = w["diplo"]
	check(dp["factions"].size() == 5 and dp["pairs"].size() == 10, "expected 5 factions and 10 pairs")
	print("start: ", _grid(w))
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var total := 0
	var worst := 0
	var weekly_total := 0
	var bad_range := 0
	var gob_neutral := 0
	var war_days := 0
	for d in range(1, 1001):
		Game.day = float(d)
		# stand-in for the map: bands of factions at war meet and one side is destroyed now and then
		for k in dp["pairs"]:
			var p: Dictionary = dp["pairs"][k]
			if p["state"] == Diplomacy.WAR:
				war_days += 1
				if rng.randf() < 0.35:
					var win: String = p["a"] if rng.randf() < 0.5 else p["b"]
					Diplomacy.on_army_destroyed(w, p["b"] if win == p["a"] else p["a"], win, rng.randi_range(3, 10))
		var t0 := Time.get_ticks_usec()
		Diplomacy.daily(Game, d)
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		if d % 7 == 0:
			weekly_total += dt
		w["work"] = []   # war assaults are exercised by the full-world run below
		for k in dp["pairs"]:
			var p: Dictionary = dp["pairs"][k]
			if float(p["rel"]) < -100.0 or float(p["rel"]) > 100.0:
				bad_range += 1
			if "goblin_warren" in [p["a"], p["b"]] and (Diplomacy.ORDER[p["state"]] >= 2 or float(p["rel"]) >= -10.0):
				gob_neutral += 1
	var st: Dictionary = dp["stats"]
	var mean_ms := total / 1000.0 / 1000.0
	print("1000 days: %d war declarations, %d peaces, %d trade pacts, %d alliances; pair-days at war %d of 10000" % [
		int(st["wars"]), int(st["peaces"]), int(st["pacts"]), int(st["alliances"]), war_days])
	print("diplomacy day step: mean %.4f ms, worst %.3f ms, weekly-roll days mean %.4f ms" % [mean_ms, worst / 1000.0, weekly_total / 142.0 / 1000.0])
	print("end:   ", _grid(w))
	print("news tail: ", (dp["news"] as Array).slice(-4).map(func(n): return n["text"]))
	check(bad_range == 0, "relation left -100..100 (%d times)" % bad_range)
	check(gob_neutral == 0, "goblins reached NEUTRAL or better (%d pair-days)" % gob_neutral)
	check(int(st["wars"]) >= 1, "no war declared in 1000 days")
	check(int(st["peaces"]) >= 1, "no peace made in 1000 days")
	check(mean_ms < 0.1, "diplomacy day step too slow: %.4f ms" % mean_ms)

func _grid(w: Dictionary) -> String:
	var parts := []
	for k in w["diplo"]["pairs"]:
		var p: Dictionary = w["diplo"]["pairs"][k]
		parts.append("%s %s %d" % [k, p["state"], int(round(float(p["rel"])))])
	return ", ".join(parts)

# ---------------------------------------------------------------- caravan routes
func _routes() -> void:
	var w: Dictionary = Game.world
	var rng := RandomNumberGenerator.new(); rng.seed = 8
	# every faction pair in turn at WAR, then HOSTILE: no caravan route or escort between them
	var fl: Array = w["diplo"]["factions"]
	var bad := 0
	var checked := 0
	var foreign := 0
	for st in [Diplomacy.WAR, Diplomacy.HOSTILE, Diplomacy.NEUTRAL]:
		for i in fl.size():
			for j in range(i + 1, fl.size()):
				_force(w, fl[i], fl[j], st, -80.0 if st == Diplomacy.WAR else (-30.0 if st == Diplomacy.HOSTILE else 0.0))
		for tid in w["towns"]:
			var t: Dictionary = w["towns"][tid]
			for l in Caravans.trade_partners(w, t):
				checked += 1
				if l["faction"] != t["faction"]:
					foreign += 1 if st == Diplomacy.NEUTRAL else 0
				if Diplomacy.fights(w, t["faction"], l["faction"]):
					bad += 1
	check(bad == 0, "caravan route between fighting factions")
	check(foreign > 0, "no foreign routes even when everyone is at peace")
	# now a mix: one pair at war, one hostile, the rest neutral; spawn caravans everywhere
	var a: String = "middle_kingdom"; var b: String = "northern_clans"; var c: String = "moon_court"
	_force(w, a, b, Diplomacy.WAR, -70.0)
	_force(w, a, c, Diplomacy.HOSTILE, -30.0)
	for wid in w["warbands"].keys():
		CampaignWorld.remove_warband(Game, wid)
	var spawned := 0
	for k in 3:
		for tid in w["towns"]:
			var cid := Caravans.spawn(Game, tid, rng)
			if cid != "":
				spawned += 1
				var car: Dictionary = w["warbands"][cid]
				var df: String = w["towns"][car["dest"]]["faction"]
				check(not Diplomacy.fights(w, car["faction"], df), "caravan %s routed %s -> %s between %s" % [cid, car["faction"], df, Diplomacy.state(w, car["faction"], df)])
				CampaignWorld.remove_warband(Game, cid)
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		for i in 10:
			var e := Contracts.escort_offer(t, Game.day, rng)
			if not e.is_empty():
				check(not Diplomacy.fights(w, t["faction"], w["towns"][e["dest_id"]]["faction"]), "escort offered toward a hostile town")
	print("routes: %d partner links checked, %d caravans spawned, none between WAR/HOSTILE pairs" % [checked, spawned])
	# trade pact weighting: partners of a pact are picked ~1.5x as often
	var tp := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		var parts := Caravans.trade_partners(w, t)
		var facs := {}
		for l in parts:
			facs[l["faction"]] = true
		if facs.size() >= 2 and not facs.has(t["faction"]):
			tp = t
			break
	if not tp.is_empty():
		var parts := Caravans.trade_partners(w, tp)
		var pf: String = parts[0]["faction"]
		_force(w, tp["faction"], pf, Diplomacy.TRADE_PACT, 45.0)
		var hits := 0
		var n_pf := parts.filter(func(l): return l["faction"] == pf).size()
		for i in 2000:
			var dest := Caravans.pick_partner(w, tp, parts, rng)
			if w["towns"][dest]["faction"] == pf:
				hits += 1
		var expect := 1.5 * n_pf / (1.5 * n_pf + (parts.size() - n_pf))
		print("trade pact weighting: %.2f of caravans to the partner (expected %.2f)" % [hits / 2000.0, expect])
		check(absf(hits / 2000.0 - expect) < 0.05, "trade pact destination weight off")

# ---------------------------------------------------------------- band composition
func _composition() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 21
	var races := ["human", "orc", "goblin", "moon_elf"]
	var worst := 0
	for n in 300:
		var units := []
		for i in rng.randi_range(1, 30):
			var u := Unit.create(races[rng.randi() % races.size()], "player")
			u.role = "officer" if rng.randf() < 0.25 else "troop"
			units.append(u)
		for fid in Diplomacy.data()["factions"]:
			var c := Diplomacy.comp_offset_for(units, fid)
			worst = maxi(worst, absi(c))
			check(absi(c) <= 20, "comp offset %d out of +-20" % c)
	var orc_off := Unit.create("orc", "player"); orc_off.role = "officer"
	var man := Unit.create("human", "player"); man.role = "troop"
	var c1 := Diplomacy.comp_offset_for([orc_off, man], "moon_court")
	print("comp: worst |offset| over 300 random rosters %d; orc officer + human troop with the moon elves %d" % [worst, c1])
	check(c1 == -12, "officer should weigh double: expected -12, got %d" % c1)
	var orcs := []
	for i in 6:
		orcs.append(Unit.create("orc", "player"))
	check(Diplomacy.comp_offset_for(orcs, "moon_court") == -20, "all-orc band should be -20 with the moon elves")
	check(Diplomacy.comp_offset_for([], "moon_court") == 0, "empty roster offset")
	# the real company: humans only -> +10 with the human realms, -6 with the goblins
	Game.new_game(31)
	check(Diplomacy.comp_offset(Game, "middle_kingdom") == 10, "human company with the March: %d" % Diplomacy.comp_offset(Game, "middle_kingdom"))
	# Douglas: orcs and goblins start hostile to a human band (the default company) at -60 standing
	check(Diplomacy.company_race(Game) == "human", "the default company is a human band (%s)" % Diplomacy.company_race(Game))
	for hf in ["orc_horde", "goblin_warren"]:
		check(Diplomacy.standing(Game, hf) == -60 and Diplomacy.player_hostile(Game, hf) and int(Game.rep[hf]) == -60,
			"%s start standing -60 and hostile to a human band: %d" % [hf, Diplomacy.standing(Game, hf)])
	check(Diplomacy.standing(Game, "middle_kingdom") == 10, "the March starts at its make-up only: %d" % Diplomacy.standing(Game, "middle_kingdom"))
	# any other band keeps the normal start: start_earned (goblins -15, orcs 0) + its make-up
	var saved_company: Array = Game.company
	var band := []
	for i in 6:
		var ou := Unit.create("orc", "player")
		ou.role = "officer" if i < 2 else "troop"
		band.append(ou)
	Game.company = band
	Diplomacy.init_world(Game)
	check(Diplomacy.company_race(Game) == "orc", "an orc band's race")
	var se: Dictionary = Diplomacy.data().get("start_earned", {})
	for hf in ["orc_horde", "goblin_warren"]:
		var want := int(se.get(hf, 0)) + Diplomacy.comp_offset(Game, hf)
		check(Diplomacy.standing(Game, hf) == want and not Diplomacy.player_hostile(Game, hf),
			"an orc band with %s: standing %d, want %d (start_earned + make-up), not hostile" % [hf, Diplomacy.standing(Game, hf), want])
	print("orc band start: orcs %d, goblins %d, March %d" % [Diplomacy.standing(Game, "orc_horde"), Diplomacy.standing(Game, "goblin_warren"), Diplomacy.standing(Game, "middle_kingdom")])
	Game.company = saved_company
	Diplomacy.init_world(Game)
	print("company comp line: ", Diplomacy.comp_line(Game, "goblin_warren"))
	# hiring an orc officer changes the offset (roster change)
	var off := Factory.make_troop(rng, "orc_horde", DB.factions["orc_horde"]["troops"][0], 1)
	off.role = "officer"; off.faction = "player"
	Game.company.append(off)
	Diplomacy.roster_changed(Game)
	print("after an orc officer joins: ", Diplomacy.comp_line(Game, "moon_court"))
	check(Diplomacy.comp_offset(Game, "moon_court") < 8, "orc officer did not sour the moon elves")
	check(int(Game.rep["moon_court"]) == Diplomacy.standing(Game, "moon_court"), "Game.rep does not mirror standing")

# ---------------------------------------------------------------- standing effects and moves
func _standing_effects() -> void:
	Game.new_game(44)
	var w: Dictionary = Game.world
	var town: Dictionary = {}
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == "middle_kingdom" and not w["towns"][tid]["shop"].is_empty():
			town = w["towns"][tid]
			break
	var fid := "middle_kingdom"
	Game.gold = 100000
	var item: Item = town["shop"][0]
	_set_standing(fid, 0)
	var p0 := Economy.price(town, item)
	var s0 := Economy.sell_price(town, item)
	_set_standing(fid, 50)
	var p50 := Economy.price(town, item)
	var s50 := Economy.sell_price(town, item)
	print("price at standing 0: buy %d sell %d; at +50: buy %d sell %d" % [p0, s0, p50, s50])
	check(p50 < p0 and absf(p50 - p0 * 0.9) <= 1.5, "price x(1 - standing/500) not applied")
	check(s50 >= s0, "selling got worse with better standing")
	var c: Dictionary = {}
	for x in town["contracts"]:
		if int(x.get("tier", 0)) == 0 and x["kind"] != "escort":
			c = x
			break
	if c.is_empty():
		c = Contracts.generate_offers(town, Game.day, RandomNumberGenerator.new())[0]
		town["contracts"].push_front(c)
	_set_standing(fid, 0)
	var pay0 := Contracts.offered_pay(Game, c)
	_set_standing(fid, 40)
	var pay40 := Contracts.offered_pay(Game, c)
	check(absf(pay40 - pay0 * 1.2) <= 10, "pay x(1 + standing/200): %d vs %d" % [pay40, pay0])
	# better tier above +50
	var tiers := (town["contracts"] as Array).filter(func(x): return int(x.get("tier", 0)) > 0)
	check(not tiers.is_empty(), "no veteran's contract generated")
	check(Contracts.offers_for(Game, town).filter(func(x): return int(x.get("tier", 0)) > 0).is_empty(), "veteran's contract shown at +40")
	_set_standing(fid, 60)
	check(not Contracts.offers_for(Game, town).filter(func(x): return int(x.get("tier", 0)) > 0).is_empty(), "veteran's contract hidden at +60")
	# recruits: halved below -20, none below -50 (own race only)
	var nrec: int = (town["recruits"] as Array).filter(func(r): return r.race == "human").size()
	_set_standing(fid, -25)
	var half := Diplomacy.visible_recruits(Game, town).filter(func(r): return r.race == "human").size()
	check(half == int(ceil(nrec / 2.0)), "recruits not halved below -20 (%d of %d)" % [half, nrec])
	check(Contracts.offers_for(Game, town).size() <= (town["contracts"] as Array).size(), "offers")
	# -35: no contracts, still trade
	_set_standing(fid, -35)
	check(Contracts.offers_for(Game, town).is_empty() and not Contracts.accept(Game, c), "contracts offered below -30")
	check(Diplomacy.can_trade(Game, fid), "trade blocked at -35")
	# <= -50: hostile, no trade, no contracts, no recruits of their race, gates barred, attacked on sight
	_set_standing(fid, -50)
	check(CampaignWorld.is_hostile(Game, fid), "standing -50 not hostile")
	var gold0: int = Game.gold
	check(not Economy.buy(Game, town, item) and Game.gold == gold0, "hostile town sold to the company")
	var mine := Item.make(item.tid, item.material, item.quality)
	Game.stash.append(mine)
	check(Economy.sell(Game, town, mine) == 0 and Game.stash.has(mine), "hostile town bought from the company")
	check(Market.buy(Game, town, item) != "", "Market.buy should refuse")
	check(Contracts.offers_for(Game, town).is_empty(), "hostile town offered contracts")
	check(not Contracts.accept(Game, c), "contract accepted at -50")
	check(Diplomacy.visible_recruits(Game, town).filter(func(r): return r.race == "human").is_empty(), "hostile town's people still sign")
	check(Diplomacy.disposition(Game, fid) == "hostile", "disposition")
	# moves: fighting -10 / -5, raid -12, contract done +3..+8, failed -5, abandoned -8
	_set_standing(fid, 0)
	var e0 := Diplomacy.earned(Game, fid)
	Diplomacy.on_fight(Game, fid, false)
	check(Diplomacy.earned(Game, fid) == e0 - 10, "fight -10")
	Diplomacy.on_fight(Game, fid, true)
	check(Diplomacy.earned(Game, fid) == e0 - 15, "fight when attacked -5")
	Diplomacy.on_raid(Game, fid)
	check(Diplomacy.earned(Game, fid) == e0 - 27, "raid -12")
	check(Diplomacy.contract_gain({"size": 3}) == 3 and Diplomacy.contract_gain({"size": 15}) == 8, "contract gain by size")
	var lg: Array = Diplomacy.log_of(Game, fid)
	check(lg.size() <= Diplomacy.LOG_SIZE and String(lg[-1]["text"]).contains("caravan"), "standing log")
	# prisoner moves exist (nothing calls them yet)
	var e1 := Diplomacy.earned(Game, fid)
	Diplomacy.on_execute(Game, fid, 30)
	check(Diplomacy.earned(Game, fid) == e1 - 10, "execution cap -10 per battle")
	Diplomacy.on_ransom(Game, fid)
	Diplomacy.on_release(Game, fid)
	Diplomacy.on_sell_to_slavers(Game, 2)
	check(Diplomacy.earned(Game, fid) == e1 - 10 + 4 - 6, "ransom/release/slavers")
	# drift: earned *= 0.995 per day
	_set_standing(fid, 60)
	var before := float(w["diplo"]["player"][fid]["earned"])
	Game.day = float(int(w["diplo"]["day"]) + 1)
	Diplomacy.daily(Game, int(Game.day))
	check(absf(float(w["diplo"]["player"][fid]["earned"]) - before * 0.995) < 0.001, "earned drift")
	# abandon
	_set_standing(fid, 10)
	Game.contract = {}
	c["state"] = "offered"
	town["contracts"].append(c)
	if Contracts.accept(Game, c):
		var e2 := Diplomacy.earned(Game, fid)
		Contracts.abandon(Game)
		check(Game.contract.is_empty() and Diplomacy.earned(Game, fid) == e2 - 8, "abandon -8")
	else:
		check(false, "could not accept a contract at +10")

# ---------------------------------------------------------------- war contracts
func _war_contract() -> void:
	Game.new_game(61)
	var w: Dictionary = Game.world
	var x := "middle_kingdom"; var y := "northern_clans"
	_force(w, x, y, Diplomacy.WAR, -70.0)
	var town: Dictionary = {}
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == x:
			town = w["towns"][tid]
	var rng := RandomNumberGenerator.new(); rng.seed = 2
	var c: Dictionary = {}
	for i in 40:
		for o in Contracts.generate_offers(town, Game.day, rng):
			if o["kind"] == "war" and o["target_faction"] == y:
				c = o
		if not c.is_empty():
			break
	check(not c.is_empty(), "no war contract offered while at war")
	if c.is_empty():
		return
	print("war offer: ", c["title"], " - ", c["desc"], " pay ", c["pay"])
	town["contracts"].append(c)
	check(Contracts.offers_for(Game, town).has(c), "war contract not shown")
	var ex0 := Diplomacy.earned(Game, x); var ey0 := Diplomacy.earned(Game, y)
	check(Contracts.accept(Game, c), "accept war contract")
	var wid: String = Game.contract["target_id"]
	check(w["warbands"].has(wid) and w["warbands"][wid]["faction"] == y, "war contract target not spawned")
	var enemy: Array = w["warbands"][wid]["units"]
	for u in enemy:
		u.dead = true
	Game.pending_battle = {"warband_id": wid, "enemy": enemy}
	Game.finish_battle({"winner": 0, "player_units": Game.company, "enemy_units": enemy, "enemy_fallen": enemy, "events": []})
	var gx := Diplomacy.earned(Game, x) - ex0; var gy := Diplomacy.earned(Game, y) - ey0
	print("war contract done: employer %+d (contract %+d, taking sides +2), enemy %+d" % [gx, Diplomacy.contract_gain(c), gy])
	check(Game.contract.is_empty() and gx == Diplomacy.contract_gain(c) + 2 and gy == -2, "taking-sides bonus wrong (%d, %d)" % [gx, gy])
	# a second war contract goes void when peace is made
	var c2 := Contracts.war_offer(town, y, Game.day, rng, 9)
	town["contracts"].append(c2)
	check(Contracts.accept(Game, c2), "accept second war contract")
	_force(w, x, y, Diplomacy.HOSTILE, -30.0)
	var e3 := Diplomacy.earned(Game, x)
	Contracts.daily_check(Game)
	check(Game.contract.is_empty() and Diplomacy.earned(Game, x) == e3, "war contract should go void without blame on peace")
	check(not Contracts.offers_for(Game, town).has(c), "stale war contract still offered after peace")
	# a hunt against Y with no war: no taking-sides bonus
	check(Contracts.refusal(Game, c2) != "", "war contract acceptable after peace")

# ---------------------------------------------------------------- save / load
func _save_load() -> void:
	Game.new_game(77)
	var w: Dictionary = Game.world
	for d in range(1, 60):
		Game.day = float(d)
		Diplomacy.on_army_destroyed(w, "middle_kingdom", "orc_horde", 5)
		Diplomacy.daily(Game, d)
	Diplomacy.add_earned(Game, "moon_court", 12, "Saved a grove")
	var fp := _diplo_fp(Game)
	Game.save_game()
	Game.world = {}
	Game.rep = {}
	check(Game.load_game(), "load")
	var fp2 := _diplo_fp(Game)
	check(fp == fp2, "diplomacy differs after load:\n%s\n%s" % [fp, fp2])
	check(typeof(Game.world["diplo"]["day"]) == TYPE_INT, "diplo day not an int after load")
	# the day keeps stepping after load
	Game.day += 1.0
	Diplomacy.daily(Game, int(Game.day))
	check(int(Game.world["diplo"]["day"]) == int(Game.day), "daily step after load")
	# migration: a save from before diplomacy (no world.diplo) keeps the old reputation as earned standing
	Game.world.erase("diplo")
	Game.world["wars"] = CampaignWorld.WARS.duplicate(true)
	Game.rep = {"middle_kingdom": 23, "northern_clans": 0, "orc_horde": -40, "goblin_warren": -40, "moon_court": 5}
	Game.save_game()
	Game.world = {}
	Game.rep = {}
	Game.load_game()
	var dp: Dictionary = Game.world.get("diplo", {})
	check(not dp.is_empty() and dp["pairs"].size() == 10, "old save not migrated")
	if not dp.is_empty():
		check(Diplomacy.earned(Game, "middle_kingdom") == 23 and Diplomacy.earned(Game, "orc_horde") == -40, "old rep not carried over as earned")
		check(Diplomacy.standing(Game, "middle_kingdom") == 33, "migrated standing = old rep + make-up (got %d)" % Diplomacy.standing(Game, "middle_kingdom"))
		print("migrated: ", _diplo_fp(Game).split("\n")[0])
	# a save with no stored standing for a faction takes the default (orcs and goblins: -60); stored ones are kept
	Game.world.erase("diplo")
	Game.rep = {"middle_kingdom": 23, "orc_horde": -10}
	Game.save_game()
	Game.world = {}
	Game.rep = {}
	Game.load_game()
	check(Diplomacy.earned(Game, "orc_horde") == -10, "a stored orc standing was not kept (%d)" % Diplomacy.earned(Game, "orc_horde"))
	check(Diplomacy.standing(Game, "goblin_warren") == -60, "a save without a goblin standing does not start at -60 (%d)" % Diplomacy.standing(Game, "goblin_warren"))

# ---------------------------------------------------------------- truce (war pick 2)
## Peace brings a truce of 60-120 days (seeded per treaty): the pair neither fights (clashes, militia, caravan raids)
## nor declares war until it runs out, and it is saved; after it the old rules again (HOSTILE fights, war can come).
func _truce() -> void:
	Game.new_game(91)
	var w: Dictionary = Game.world
	var a := "middle_kingdom"; var b := "orc_horde"
	_force(w, a, b, Diplomacy.WAR, -80.0)
	var p: Dictionary = w["diplo"]["pairs"][Diplomacy.pair_key(a, b)]
	var d0 := int(w["diplo"]["day"]) + 1
	Game.day = float(d0)
	w["diplo"]["day"] = d0
	Diplomacy._set_state(Game, p, Diplomacy.HOSTILE)   # the peace (the weekly roll's path)
	Diplomacy._sync_wars(w)
	var n := Diplomacy.truce_left(w, a, b)
	print("truce: %d days; %s; news: %s" % [n, Diplomacy.truce_text(w, a, b), String(w["diplo"]["news"][-1]["text"])])
	check(n >= Diplomacy.TRUCE_MIN and n <= Diplomacy.TRUCE_MAX, "truce of %d days, want 60-120" % n)
	check(n == Diplomacy.roll_truce(w, Diplomacy.pair_key(a, b), d0), "truce length not the seeded roll")
	check(Diplomacy.truce_text(w, a, b) == "truce, %d days left" % n, "truce text")
	check(String(w["diplo"]["news"][-1]["text"]).contains("truce of %d days" % n), "the peace news does not tell the truce")
	var lens := {}
	for d in range(1, 40):
		lens[Diplomacy.roll_truce(w, "x|y", d)] = true
	check(lens.size() > 10, "truce lengths do not vary between treaties")
	# no fighting: contact clash, militia threat, caravan raid
	check(not Diplomacy.fights(w, a, b) and not Diplomacy.fights(w, b, a), "the pair fights in a truce")
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var town: Dictionary = {}
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == a:
			town = w["towns"][tid]
	var spot := CampaignWorld.nearest_passable(w, (town["pos"] as Vector2) + Vector2(300, 0))
	var keep: Array = []
	var pa := CampaignWorld.spawn_warband(Game, a, spot, 6, "patrol", rng, {"home": town["id"]})
	var ob := CampaignWorld.spawn_warband(Game, b, spot + Vector2(4, 0), 6, "raider", rng)
	var car := CampaignWorld.spawn_warband(Game, a, spot + Vector2(0, 4), 2, "caravan", rng, {"home": town["id"], "origin": town["id"],
		"dest": town["id"], "leg": "out", "cargo": {"items": [], "goods": {}}, "gold": 0.0, "escort": "", "away": 0.0, "state": "travel"})
	keep = [pa, ob, car]
	for wid in w["warbands"].keys():
		if not keep.has(wid):
			w["warbands"].erase(wid)
	w["encounter"] = ""
	w["party"]["safe_until"] = 1.0e9
	for wid in keep:
		w["warbands"][wid]["rest_until"] = 0.0
	var mil := {"faction": a, "id": "m"}
	check(not Militia.is_threat(Game, mil, w["warbands"][ob]), "a militia sees a band in truce as a threat")
	check(not Caravans.is_prey(w, w["warbands"][ob], w["warbands"][car]), "raiders prey on a caravan in a truce")
	CampaignWorld._warband_clashes(Game, Game.day, rng)
	check(w["warbands"].has(pa) and w["warbands"].has(ob) and w["warbands"].has(car)
		and (w["warbands"][pa]["units"] as Array).size() == 6 and (w["warbands"][ob]["units"] as Array).size() == 6, "a clash in the truce")
	# no war for the truce's length, even with the relation deep in the war band; then it expires
	var war_day := -1
	var first_after := -1
	for d in range(d0 + 1, d0 + 600):
		p["rel"] = -90.0
		Game.day = float(d)
		Diplomacy.daily(Game, d)
		if d < d0 + n:
			if p["state"] == Diplomacy.WAR or Diplomacy.fights(w, a, b) or not Diplomacy.in_truce(w, a, b):
				check(false, "truce broken on day %d (%d of %d): %s" % [d, d - d0, n, p["state"]])
				break
		elif first_after < 0:
			first_after = d
			check(not Diplomacy.in_truce(w, a, b) and Diplomacy.truce_text(w, a, b) == "", "the truce did not run out on day %d" % d)
			check(p["state"] == Diplomacy.WAR or Diplomacy.fights(w, a, b), "HOSTILE pair does not fight after the truce")
		if p["state"] == Diplomacy.WAR:
			war_day = d
			break
	print("truce: war declared on day %d (truce ran out on day %d)" % [war_day, d0 + n])
	check(war_day >= d0 + n, "no war after the truce ran out (600 days at relation -90)")
	# a new peace, a new truce; saved and loaded
	Diplomacy._set_state(Game, p, Diplomacy.HOSTILE)
	Diplomacy._sync_wars(w)
	var left := Diplomacy.truce_left(w, a, b)
	Game.save_game()
	Game.world = {}
	check(Game.load_game(), "load")
	check(Diplomacy.truce_left(Game.world, a, b) == left and left > 0 and typeof(Game.world["diplo"]["pairs"][Diplomacy.pair_key(a, b)]["truce"]) == TYPE_INT,
		"truce not kept through save/load (%d vs %d)" % [Diplomacy.truce_left(Game.world, a, b), left])

func _diplo_fp(game) -> String:
	var dp: Dictionary = game.world["diplo"]
	var parts := []
	var ks: Array = dp["pairs"].keys(); ks.sort()
	for k in ks:
		var p: Dictionary = dp["pairs"][k]
		parts.append("%s %s %.3f %d %d %.2f" % [k, p["state"], float(p["rel"]), int(p["past"]), int(p["held"]), float(p["losses"])])
	for f in dp["factions"]:
		var pl: Dictionary = dp["player"][f]
		parts.append("%s %.4f %d %d %s %d" % [f, float(pl["earned"]), int(pl["comp"]), Diplomacy.standing(game, f), str((pl["log"] as Array).map(func(e): return e["text"])), int(game.rep.get(f, 999))])
	for s in ["wars", "peaces", "pacts", "alliances"]:
		parts.append("%s %d" % [s, int(dp["stats"][s])])
	return "\n".join(parts)

# ---------------------------------------------------------------- relations screen
func _screen(tree: SceneTree) -> void:
	Game.new_game(12)
	Diplomacy.add_earned(Game, "orc_horde", -30, "Attacked a band of theirs")
	Diplomacy.news(Game, "Test news line.")
	await tree.process_frame
	var s: Node = (load(Relations.SCENE) as PackedScene).instantiate()
	tree.root.add_child(s)
	await tree.process_frame
	for t in ["World", "Company"]:
		s.show_tab(t)
		await tree.process_frame
	s.queue_free()
	await tree.process_frame
	print("relations screen instanced (Company, World)")
	# the company screen still builds with its new Relations button
	var cs: Node = (load("res://ui/company.tscn") as PackedScene).instantiate()
	tree.root.add_child(cs)
	await tree.process_frame
	cs.queue_free()
	await tree.process_frame

# ---------------------------------------------------------------- full world
func _full_world() -> void:
	Game.new_game(909)
	var w: Dictionary = Game.world
	w["party"]["safe_until"] = 1e9
	var t0 := Time.get_ticks_msec()
	for d in 70:
		Game.advance_time(1.0, false)
		w["encounter"] = ""
	var dp: Dictionary = w["diplo"]
	var assaults := 0; var sacks := 0
	for line in w["log"]:
		if String(line).contains("marches on"): assaults += 1
		if String(line).contains("sacked") or String(line).contains("beat back"): sacks += 1
	print("70 days full world in %d ms: %s; stats %s; last log %s" % [Time.get_ticks_msec() - t0, _grid(w), str(dp["stats"]), w["log"].slice(-3)])
	check(int(dp["day"]) == int(Game.day), "diplomacy did not step every day (%d vs %d)" % [int(dp["day"]), int(Game.day)])
	for k in dp["pairs"]:
		var r := float(dp["pairs"][k]["rel"])
		check(r >= -100.0 and r <= 100.0, "relation out of range in the full run")
	var wars: Array = w["wars"]
	for pair in wars:
		check(Diplomacy.at_war(w, pair[0], pair[1]), "w.wars out of sync")
