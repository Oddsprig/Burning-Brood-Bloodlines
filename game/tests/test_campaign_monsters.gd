extends RefCounted
## Monsters wave 1 on the campaign map (docs/specs/monsters-wave1.md, blocking tests):
## - militia spawns per town with home town and faction, sized by the town, rebuilds after losses,
##   auto-fights threats near town, and joins a defend battle as allies (pay bonus for sparing them)
## - every non-monster map unit has a home (town, or a bandit camp for outlaws) and a faction; deserters keep theirs
## - a bandit camp re-equips from its stock (and its gangs bring raided cargo home)
## - spawn density scales with wild area; rarity weights spawns and new types start rare
## - lair / hunt / bounty contracts: lair battle terrain, trophies auto-sold, lair cleared, contract paid
## - save/load round trip of the new world state; on_time per map frame stays cheap

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _homes_ok(w: Dictionary) -> int:
	var bad := 0
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.is_monster_band(wb):
			check(wb["faction"] == "beasts", "monster band %s faction %s" % [wid, wb["faction"]])
			continue
		var fid: String = wb["faction"]
		var home: String = wb["home"]
		var ok := DB.factions.has(fid)
		if w["towns"].has(home):
			ok = ok and w["towns"][home]["faction"] == fid
		elif w["lairs"].has(home):
			ok = ok and w["lairs"][home]["kind"] == "bandit_camp" and fid == "outlaws"
		else:
			ok = false
		for u in wb["units"]:
			# economy spec 2: an outlaw's band lives at its camp, the man himself comes from a family in a town
			var uh: bool = u.home_town == home or (fid == "outlaws" and w["towns"].has(u.home_town))
			ok = ok and uh and u.faction == fid
		if not ok:
			bad += 1
			print("  bad home: %s %s %s home '%s'" % [wid, wb["kind"], fid, home])
	return bad

func _fake_win(units: Array) -> Dictionary:
	for u in units:
		u.dead = true
	return {"winner": 0, "player_units": Game.deployed_units(), "enemy_units": units, "enemy_fallen": units, "events": []}

func run(_tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	Game.new_game(777)
	var w: Dictionary = Game.world
	# ---------------------------------------------------------------- militia per town
	var n_mil := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		var wb := Militia.band_of(Game, tid)
		check(not wb.is_empty(), "town %s has no militia" % t["name"])
		if wb.is_empty():
			continue
		n_mil += 1
		check(wb["kind"] == "militia" and wb["home"] == tid and wb["faction"] == t["faction"], "militia of %s: home/faction" % t["name"])
		check((wb["units"] as Array).size() == Militia.target_size(t), "militia of %s sized %d, want %d" % [t["name"], (wb["units"] as Array).size(), Militia.target_size(t)])
		for u in wb["units"]:
			check(u.home_town == tid and u.faction == t["faction"], "militiaman without home/faction")
	print("militia: %d towns, %d bands; e.g. %s" % [w["towns"].size(), n_mil, CampaignWorld.scout_report(Game, w["militia"].values()[0])])
	# ---------------------------------------------------------------- lairs and camps at start
	var lairs: Dictionary = w["lairs"]
	var wild := Lairs.wild_count(w)
	print("wild cells %d -> target lairs %d, camps %d; placed %d lairs/camps: %s" % [wild, Lairs.target_lairs(wild), Lairs.target_camps(wild),
		lairs.size(), str(lairs.values().map(func(l): return "%s@%s" % [l["kind"], CampaignWorld.terrain_at(w, l["pos"])]))])
	check(Lairs.count(w, true) >= 1, "no bandit camp")
	check(Lairs.count(w, false) >= 1, "no creature lair")
	for lid in lairs:
		var l: Dictionary = lairs[lid]
		check(CampaignWorld.terrain_char_at(w, l["pos"]) in ["f", "s", "h", "b"], "lair %s not in the wilds" % lid)
		var tdist := INF
		for tid in w["towns"]:
			tdist = minf(tdist, (w["towns"][tid]["pos"] as Vector2).distance_to(l["pos"]))
		check(tdist > WorldGen.CELL * 5, "lair %s too close to a town (%.0f px)" % [lid, tdist])
	# ---------------------------------------------------------------- spawn density scales with wild area
	var w2 := {"seed": w["seed"], "terrain": (w["terrain"] as String).replace("f", "g").replace("s", "g"), "towns": w["towns"]}
	var wild2 := Lairs.wild_count(w2)
	var t1 := Lairs.target_lairs(wild)
	var t2 := Lairs.target_lairs(wild2)
	print("density: wild %d -> %d lairs; forests cleared, wild %d -> %d lairs" % [wild, t1, wild2, t2])
	check(wild2 < wild and t2 < t1, "fewer wilds should mean fewer lairs")
	check(Lairs.target_lairs(wild * 2) >= t1 and Lairs.target_lairs(0) == 0, "lair target not monotonic in wild area")
	Lairs.wild_count(w)   # restore the cache for the real map
	# rarity weights spawns, new types start rare
	var st := Monsters.state(w)
	st["unlocked"]["bear"] = Game.day
	check(is_equal_approx(Monsters.weight(w, "bear", Game.day), float(Creatures.rarity_info("rare")["weight"])), "a new type should start rare")
	check(Monsters.weight(w, "wolf", Game.day + 100.0) > Monsters.weight(w, "bear", Game.day + 100.0), "common should outweigh uncommon")
	# ---------------------------------------------------------------- simulate: homes, gradual lairs, militia fights
	Game.gold = 100000   # economy spec 2: unpaid company men walk home after 10 days; keep the company paid
	for i in 60:
		Game.advance_time(0.25, false)
		w["encounter"] = ""
	print("after 15 days: %d warbands, %d lairs (target %d), log tail %s" % [w["warbands"].size(), lairs.size(), t1 + Lairs.target_camps(wild), w["log"].slice(-4)])
	check(Lairs.count(w, false) <= t1 and Lairs.count(w, true) <= Lairs.target_camps(wild), "more lairs than the density allows")
	var kinds := {}
	for wid in w["warbands"]:
		kinds[w["warbands"][wid]["kind"]] = int(kinds.get(w["warbands"][wid]["kind"], 0)) + 1
	print("warband kinds: ", kinds)
	check(_homes_ok(w) == 0, "every non-monster map unit needs a home and a faction")
	var did := Bandits.spawn_deserters(Game, rng)
	var dwb: Dictionary = w["warbands"][did]
	check(dwb["deserter"] and w["towns"][dwb["home"]]["faction"] == dwb["faction"], "deserters keep town and faction")
	check(Monsters.band_hostile(Game, dwb) and not CampaignWorld.is_hostile(Game, dwb["faction"]), "deserters hostile while their faction is not")
	check(_homes_ok(w) == 0, "deserter homes")
	# ---------------------------------------------------------------- bandit camp re-equips from its stock
	var camp_id := ""
	for lid in lairs:
		if lairs[lid]["kind"] == "bandit_camp" and w["warbands"].has(String(lairs[lid]["resident"])):
			camp_id = lid
	check(camp_id != "", "no bandit camp with a garrison")
	if camp_id != "":
		var l: Dictionary = lairs[camp_id]
		var garrison: Dictionary = w["warbands"][l["resident"]]
		var prize := Item.make("mail_shirt", "copper", 5)
		var blade := Item.make("arming_sword", "copper", 5)
		(l["stock"] as Array).append_array([prize, blade])
		Bandits.daily(Game)
		var worn := false
		var wielded := false
		for u in garrison["units"]:
			worn = worn or u.equip.get("body", null) == prize
			wielded = wielded or u.equip.get("main_hand", null) == blade
		check(worn and wielded, "camp did not re-arm from its stock")
		check(not (l["stock"] as Array).has(prize), "the piece is still in the stock")
		# a gang that plunders a caravan brings the cargo home
		var gang := {"kind": "bandit", "home": camp_id}
		var cargo_item := Item.make("kite_shield", "copper", 1)
		var before := (l["stock"] as Array).size()
		Bandits.on_plunder(Game, gang, {"cargo": {"items": [cargo_item], "goods": {}}})
		check((l["stock"] as Array).has(cargo_item) and (l["stock"] as Array).size() == before + 1, "raided cargo did not reach the camp")
		var gid := Bandits.spawn_band(Game, camp_id, rng)
		check(w["warbands"].has(gid) and w["warbands"][gid]["home"] == camp_id and w["warbands"][gid]["faction"] == "outlaws", "camp gang home")
	# ---------------------------------------------------------------- militia auto-fights and rebuilds
	var town_id: String = w["start_town"]
	var town: Dictionary = w["towns"][town_id]
	var mil := Militia.band_of(Game, town_id)
	var pack := CampaignWorld.spawn_warband(Game, "beasts", town["pos"] + Vector2(30, 0), 3, "beasts", rng,
		{"units": Creatures.make_group(rng, "wolf", 3), "creature": "wolf", "anchor": town["pos"], "roam": 50.0})
	var mil_n0 := (mil["units"] as Array).size()
	Militia.tick(Game, rng)
	check(not w["warbands"].has(pack) or (mil["units"] as Array).size() < mil_n0, "militia ignored wolves at the gate")
	print("militia vs wolves at %s: pack %s, militia %d -> %d; %s" % [town["name"], "gone" if not w["warbands"].has(pack) else "won", mil_n0, (mil["units"] as Array).size(), w["log"][-1]])
	if w["warbands"].has(pack):
		CampaignWorld.remove_warband(Game, pack)
	mil["units"] = (mil["units"] as Array).slice(0, 1)
	var peak := 1
	for d in 12:
		Game.advance_time(1.0, true)
		peak = maxi(peak, (mil["units"] as Array).size())   # (it may lose men to fights meanwhile)
	check(peak >= 4, "militia did not rebuild")
	print("militia rebuilt to a peak of %d of %d in 12 days (now %d)" % [peak, Militia.target_size(town), (mil["units"] as Array).size()])
	# ---------------------------------------------------------------- lair contract: choke-point map, trophies, cleared lair, pay
	var den := ""
	for lid in lairs:
		# (a lair near a town that hires the company: orcs and goblins start hostile to it, -60, Douglas)
		var nt: Dictionary = w["towns"][CampaignWorld.nearest_town(w, lairs[lid]["pos"])]
		if lairs[lid]["kind"] != "bandit_camp" and w["warbands"].has(String(lairs[lid]["resident"])) \
				and Diplomacy.contracts_allowed(Game, nt["faction"]):
			den = lid
	if den == "":
		den = Monsters.new_lair(Game, rng)
	var dl: Dictionary = lairs[den]
	var resident: String = dl["resident"]
	var near_town := CampaignWorld.nearest_town(w, dl["pos"])
	var c := MonsterContracts._mk(w["towns"][near_town], Game.day, "lair", 9, w["warbands"][resident], 200, "Clear it", "test", 8)
	(w["towns"][near_town]["contracts"] as Array).append(c)
	Game.contract = {}
	var why := Contracts.refusal(Game, c)
	check(Contracts.accept(Game, c), "lair contract not accepted (%s; employer %s, resident %s)" % [why, c.get("employer", "?"), str(w["warbands"].has(resident))])
	check(dl["known"], "accepted lair not marked on the map")
	w["party"]["pos"] = dl["pos"] + Vector2(10, 0)
	CampaignWorld.engage(Game, resident)
	var pb: Dictionary = Game.pending_battle
	check(pb.has("tiles") and (pb["tiles"] as Array).size() > 0, "lair battle without lair terrain")
	if pb.has("tiles"):
		var rows: Array = pb["tiles"]
		print("lair map (%s):\n  %s" % [dl["kind"], "\n  ".join(rows)])
		var blocked := 0
		for r in rows:
			blocked += String(r).count("#") + String(r).count(",")   # rough tiles are chokes too (thicket lairs are mostly rough; lairs.gd)
		check(blocked > 10, "lair map has no choke points")
		var opts := BattleSim.new()
		opts.setup(Game.deployed_units(), pb["enemy"], 1, {"tiles": rows})
		var steps := 0
		while not opts.is_over() and steps < 4000:
			opts.step()
			steps += 1
		print("lair battle in the sim: winner %d after %d ticks" % [opts.winner, opts.tick])
		for u in Game.company:   # undo the trial fight
			u.dead = false
	var gold0: int = Game.gold
	var pay: int = int(Game.contract.get("pay", 0))
	var enemy: Array = pb["enemy"]
	Game.finish_battle(_fake_win(enemy))
	var res: Dictionary = Game.last_result
	print("lair cleared: trophies %s, gold %d -> %d (contract %d), log %s" % [res.get("trophies", []), gold0, Game.gold, pay, w["log"][-1]])
	if Creatures.is_creature(enemy[0].race):
		check(int(res.get("trophy_gold", 0)) > 0, "no trophies from slain beasts")
	check(not w["warbands"].has(resident), "lair resident survived")
	check(Game.contract.is_empty() and Game.gold >= gold0 + pay, "lair contract not paid")
	if lairs.has(den):
		check(lairs[den]["resident"] == "" and float(lairs[den]["cleared_until"]) > Game.day, "lair not cleared")
	# ---------------------------------------------------------------- hunt: a pack plagues the village
	var hc := {}
	for i in 30:
		var offers := MonsterContracts.offers(town, Game.day + i, rng)
		for o in offers:
			if o["kind"] == "hunt":
				hc = o
		if not hc.is_empty():
			break
	check(not hc.is_empty(), "no hunt offers")
	if not hc.is_empty():
		(town["contracts"] as Array).append(hc)
		check(Contracts.accept(Game, hc), "hunt not accepted")
		var hp: Dictionary = w["warbands"].get(String(hc["target_id"]), {})
		check(not hp.is_empty() and (hp["pos"] as Vector2).distance_to(town["pos"]) < 400.0, "hunt pack not near the village")
		print("hunt: %s, pay %d, pack of %d %s" % [hc["title"], int(hc["pay"]), (hp.get("units", []) as Array).size(), hc["creature"]])
		Contracts.fail(Game, "test")
		check(w["warbands"].has(String(hc["target_id"])) and w["warbands"][hc["target_id"]]["kind"] == "beasts", "a failed hunt's pack should stay a pack")
	# ---------------------------------------------------------------- bounty grows the longer the target lives
	var named_rng := RandomNumberGenerator.new(); named_rng.seed = 5
	var boss := Creatures.make_named(named_rng, "bear")
	var bwid := CampaignWorld.spawn_warband(Game, "beasts", town["pos"] + Vector2(300, 0), 1, "den", rng,
		{"units": [boss], "creature": "bear", "named": boss.name, "since": Game.day})
	var bwb: Dictionary = w["warbands"][bwid]
	var p0 := MonsterContracts.bounty_pay(500, bwb, Game.day)
	var p30 := MonsterContracts.bounty_pay(500, bwb, Game.day + 30.0)
	print("bounty on %s: %d now, %d in 30 days" % [boss.name, p0, p30])
	check(p30 > p0, "bounty should grow while the target lives")
	check(MonsterContracts.creature_fee([boss], "bear", 3) > MonsterContracts.creature_fee([Creatures.make(rng, "wolf")], "wolf", 3), "rarity/power should scale the fee")
	CampaignWorld.remove_warband(Game, bwid)
	# ---------------------------------------------------------------- defend: militia fights beside the company
	Game.contract = {}
	var dc := {}
	var dtown := ""
	for tid in w["towns"]:
		var tt: Dictionary = w["towns"][tid]
		if DB.factions[tt["faction"]].get("player_hostile", false):
			continue
		for i in 20:
			for o in Contracts.generate_offers(tt, Game.day, rng):
				if o["kind"] == "defend":
					dc = o
			if not dc.is_empty():
				break
		if not dc.is_empty():
			dtown = tid
			break
	check(not dc.is_empty(), "no defend offer")
	if not dc.is_empty():
		(w["towns"][dtown]["contracts"] as Array).append(dc)
		Militia.ensure(Game, dtown, rng)
		var mb := Militia.band_of(Game, dtown)
		while (mb["units"] as Array).size() < Militia.target_size(w["towns"][dtown]):
			(mb["units"] as Array).append(Militia.make_unit(w["towns"][dtown], rng))
		check(Contracts.accept(Game, dc), "defend not accepted")
		# coinage: the employer pays only coin it holds; this town can pay the contract and the bonus
		w["towns"][dtown]["econ"]["treasury"] = maxf(float(w["towns"][dtown]["econ"]["treasury"]), 10.0 * float(dc["pay"]))
		var awid: String = Game.contract["target_id"]
		w["party"]["pos"] = w["warbands"][awid]["pos"]
		CampaignWorld.engage(Game, awid)
		var allies: Array = Game.pending_battle.get("allies", [])
		var mil_units := Militia.units_of(Game, dtown)
		check(allies.size() == mil_units.size() and allies.size() > 0 and allies[0] == mil_units[0], "militia not deployed as allies")
		allies[0].dead = true
		var pay0 := int(Game.contract["pay"])
		var g0: int = Game.gold
		Game.finish_battle(_fake_win(Game.pending_battle["enemy"]))
		var bonus := int(Game.last_result.get("militia_bonus", 0))
		print("defend %s with %d militia: 1 fell, bonus %d on %d, militia now %d" % [w["towns"][dtown]["name"], allies.size(), bonus, pay0, Militia.units_of(Game, dtown).size()])
		check(bonus > 0 and Game.gold >= g0 + pay0 + bonus, "no militia bonus")
		check(Militia.units_of(Game, dtown).size() == allies.size() - 1, "dead militia not removed")
	# ---------------------------------------------------------------- save/load round trip of the new state
	for i in 8:
		Game.advance_time(0.25, false)
		w["encounter"] = ""
	var fp := _fingerprint(w)
	Game.save_game()
	Game.world = {}
	Game.load_game()
	w = Game.world
	var fp2 := _fingerprint(w)
	if fp != fp2:
		var a := fp.split("\n")
		var b := fp2.split("\n")
		for i in mini(a.size(), b.size()):
			if a[i] != b[i]:
				print("  first diff: ", a[i], " | ", b[i])
				break
	check(fp == fp2, "monster world state changed in save/load")
	for lid in w["lairs"]:
		for it in w["lairs"][lid].get("stock", []):
			check(it is Item, "camp stock not Items after load")
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.is_monster_band(wb):
			check(wb["units"][0] is Unit and wb["units"][0].body.plan_id.begins_with("quadruped_"), "creature lost its body plan in save/load")
	for i in 8:
		Game.advance_time(0.25, false)   # keeps running after load
		w["encounter"] = ""
	check(_homes_ok(w) == 0, "homes after load")
	# ---------------------------------------------------------------- per-frame cost
	w["party"]["safe_until"] = Game.day + 100.0
	var frame_days := (1.0 / 60.0) / 5.0
	var total := 0
	var worst := 0
	for i in 600:
		var t0 := Time.get_ticks_usec()
		Game.day += frame_days
		CampaignWorld.on_time(Game, frame_days, false)
		var dtu := Time.get_ticks_usec() - t0
		total += dtu
		worst = maxi(worst, dtu)
		w["encounter"] = ""
	print("on_time per map frame with monsters: mean %.3f ms, worst %.2f ms, %d warbands" % [total / 600.0 / 1000.0, worst / 1000.0, w["warbands"].size()])
	check(total / 600.0 / 1000.0 < 0.5, "on_time too slow per frame")
	# a save from before monsters wave 1 gets its lairs, camps and militia on load
	for wid in w["warbands"].keys():
		var k: String = w["warbands"][wid]["kind"]
		if k in ["militia", "beasts", "den", "camp", "bandit", "deserter"]:
			CampaignWorld.remove_warband(Game, wid)
	for k in ["lairs", "militia", "monsters"]:
		w.erase(k)
	CampaignWorld.after_load(Game)
	check(w.has("lairs") and not w["lairs"].is_empty() and w["militia"].size() == w["towns"].size(), "old save not upgraded")
	check(_homes_ok(w) == 0, "homes after an old-save upgrade")
	return fails

func _fingerprint(w: Dictionary) -> String:
	var parts := []
	var lids: Array = w["lairs"].keys()
	lids.sort()
	for lid in lids:
		var l: Dictionary = w["lairs"][lid]
		parts.append("%s %s %s %s %s %s %.2f %s" % [lid, l["kind"], str((l["pos"] as Vector2).round()), l["resident"], l["known"], l["creature"],
			float(l["cleared_until"]), str(l.get("stock", []).map(func(it): return "%d/%s/%d" % [it.uid, it.tid, it.quality]))])
	var mids: Array = w["militia"].keys()
	mids.sort()
	for tid in mids:
		parts.append("militia %s %s" % [tid, w["militia"][tid]])
	parts.append("monsters %d %s" % [int(w["monsters"]["fights"]), str(w["monsters"]["unlocked"].keys())])
	var wids: Array = w["warbands"].keys()
	wids.sort()
	for wid in wids:
		var wb: Dictionary = w["warbands"][wid]
		parts.append("%s %s %s %s %s %s %s" % [wid, wb["kind"], wb["faction"], wb["home"], wb.get("lair", ""), wb.get("named", ""),
			str(wb["units"].map(func(u): return "%d %s %s %s %d" % [u.uid, u.race, u.title, u.home_town, u.equip.size()]))])
	return "\n".join(parts)
