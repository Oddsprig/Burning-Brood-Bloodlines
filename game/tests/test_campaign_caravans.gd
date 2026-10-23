extends RefCounted
## Caravans: spawn with real cargo (Items out of the origin shop, goods out of its supply), travel by road,
## unload into the destination; destroyed by a hostile band; escort contract success and failure; player
## raid loots the actual cargo; every force has a home town; save/load; per-frame cost of on_time.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

## Goods dict as sorted "k:v" (saves sort keys).
func _gs(d: Dictionary) -> String:
	var ks := d.keys()
	ks.sort()
	return ",".join(PackedStringArray(ks.map(func(k): return "%s:%d" % [k, int(d[k])])))

func _clear_bands(w: Dictionary) -> void:
	for wid in w["warbands"].keys():
		CampaignWorld.remove_warband(Game, wid)
	w["work"] = []

## Capture identities before the isolated loss fixture raises its force. No people or money are added.
func _loss_people(w: Dictionary, fid: String) -> Dictionary:
	var people := {}
	for tid in w["towns"]:
		var town: Dictionary = w["towns"][tid]
		if town.get("faction", "") != fid:
			continue
		for f in town.get("econ", {}).get("fams", []):
			for p in f.get("pp", []):
				people["%s:%d:%d" % [tid, int(f["id"]), int(p[0])]] = true
	return people

## A speculative trip on this pair loses about 2,200 to a 15-day crew even though the
## sticker gap is wide. v0.048 stays home unless expected net is positive, so the
## delivery and raid fixtures open a linen gap that clears that payroll, then the
## travelling case puts prices and the destination's stock back.
func _fund_linen(origin: Dictionary, dest: Dictionary) -> Dictionary:
	var qty := 80
	var snap := {
		"on": float(origin["econ"]["need"].get("linen", 0.0)),
		"op": float(origin["econ"]["price"].get("linen", 0.0)),
		"os": int(origin["econ"]["stock"].get("linen", 0)),
		"dn": float(dest["econ"]["need"].get("linen", 0.0)),
		"dp": float(dest["econ"]["price"].get("linen", 0.0)),
		"ds": int(dest["econ"]["stock"].get("linen", 0)),
	}
	origin["econ"]["need"]["linen"] = 10.0
	var funded := int(Goods.target(origin, "linen") * 1.1) + qty
	snap["funded"] = funded
	origin["econ"]["stock"]["linen"] = funded
	origin["econ"]["price"]["linen"] = 20.0
	dest["econ"]["need"]["linen"] = float(qty + 50)
	dest["econ"]["stock"]["linen"] = 0
	dest["econ"]["price"]["linen"] = 250.0
	return snap

func _unfund_linen(origin: Dictionary, dest: Dictionary, snap: Dictionary) -> void:
	var taken := int(snap["funded"]) - int(origin["econ"]["stock"].get("linen", 0))
	origin["econ"]["stock"]["linen"] = maxi(0, int(snap["os"]) - taken)
	origin["econ"]["need"]["linen"] = snap["on"]
	origin["econ"]["price"]["linen"] = snap["op"]
	dest["econ"]["need"]["linen"] = snap["dn"]
	dest["econ"]["price"]["linen"] = snap["dp"]
	dest["econ"]["stock"]["linen"] = snap["ds"]

## A town with a trade partner, and the partner.
func _pair(w: Dictionary) -> Array:
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] != "middle_kingdom":
			continue
		var p := Caravans.trade_partners(w, t)
		if not p.is_empty():
			return [tid, p[0]["id"]]
	return []

func run(_tree: SceneTree) -> int:
	Game.new_game(321)
	var w: Dictionary = Game.world
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	# ---------------------------------------------------------------- homes
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		# monsters wave 1: monsters belong to lairs; bandits' home is their camp (tests/test_campaign_monsters.gd)
		if Monsters.is_monster_band(wb) or w.get("lairs", {}).has(wb["home"]):
			continue
		check(w["towns"].has(wb["home"]) and w["towns"][wb["home"]]["faction"] == wb["faction"], "band %s has no home town of its faction" % wid)
		check(wb["units"][0].home_town == wb["home"], "band units lack home_town")
	var any: String = w["warbands"].keys()[0]
	print("scouting: ", CampaignWorld.scout_report(Game, any)["home_text"])
	# ---------------------------------------------------------------- spawn, travel, deliver
	_clear_bands(w)
	var pair := _pair(w)
	check(not pair.is_empty(), "no trade pair")
	var origin: Dictionary = w["towns"][pair[0]]
	var dest: Dictionary = w["towns"][pair[1]]
	var linen_snap := _fund_linen(origin, dest)
	# v0.014: the guards take their kit from the town's armory first, then the stalls: count both together
	var shop0: int = origin["shop"].size() + ArmsTrade.armory(origin).size()
	var cid := Caravans.spawn(Game, pair[0], rng, pair[1])
	_unfund_linen(origin, dest, linen_snap)
	check(cid != "", "caravan did not spawn")
	var car: Dictionary = w["warbands"][cid]
	var cargo: Dictionary = car["cargo"]
	var uids: Array = cargo["items"].map(func(it): return it.uid)
	print("caravan %s -> %s carrying %s" % [origin["name"], dest["name"], Caravans.cargo_text(cargo)])
	var guard_gear := 0   # economy: the guards took their gear from the same armory and stalls
	for gu in car["units"]:
		guard_gear += gu.equip.size()
	check(not uids.is_empty() and origin["shop"].size() + ArmsTrade.armory(origin).size() == shop0 - uids.size() - guard_gear,
		"items not taken out of the origin shop and armory")
	check(cargo["goods"].has("linen"), "surplus linen not loaded")
	for it in origin["shop"]:
		check(not uids.has(it.uid), "cargo item still in origin shop")
	var food_dest0: float = Goods.supply(dest, "linen")
	var trade0: int = int(origin.get("trade", 0))
	var t_start: float = Game.day
	var arrived := false
	for i in 400:
		Game.advance_time(0.05, false)
		w["encounter"] = ""
		if not w["warbands"].has(cid) or w["warbands"][cid].get("leg", "out") == "home":
			arrived = true
			break
	check(arrived, "caravan never arrived")
	var dest_uids: Array = dest["shop"].map(func(it): return it.uid)
	for u in uids:
		check(dest_uids.has(u), "cargo item %d not unloaded at the destination" % u)
	check(int(origin.get("trade", 0)) > trade0 or int(origin["wealth"]) > 0, "origin earned no trade")
	print("arrived after %.1f days; dest linen %.1f -> %.1f" % [Game.day - t_start, food_dest0, Goods.supply(dest, "linen")])
	check(Goods.supply(dest, "linen") > food_dest0, "wool not delivered")
	print("dest goods: ", Goods.summary(dest), "; linen price ", Goods.price(dest, "linen"))
	# ---------------------------------------------------------------- destroyed by a hostile band
	_clear_bands(w)
	_fund_linen(origin, dest)
	var c2 := Caravans.spawn(Game, pair[0], rng, pair[1])
	var dest_shop0: int = dest["shop"].size()
	var dest_linen := Goods.supply(dest, "linen")
	var linen_load := int(w["warbands"][c2]["cargo"]["goods"].get("linen", 0))
	var linen_lost := int(TownEcon.goods_lost.get("linen", 0))
	check(linen_load > 0, "loss fixture carries real linen from the origin")
	var cpos: Vector2 = w["warbands"][c2]["pos"]
	# This fixture covers destruction/real cargo loss, not recruitment or pursuit.
	# Staging still draws real registered volunteers; the requested count is a cap,
	# not a promise of acceptance. Check their existing identities and the exact losing roll.
	var source_people := _loss_people(w, "orc_horde")
	var orcs := CampaignWorld.spawn_warband(Game, "orc_horde", cpos, 30, "raider", rng, {"staged": true})
	check(orcs != "" and w["warbands"].has(orcs), "loss fixture raises a real accepted attacking force")
	if orcs != "" and w["warbands"].has(orcs):
		check(w["warbands"][orcs]["home"] != "" and w["towns"][w["warbands"][orcs]["home"]]["faction"] == "orc_horde", "orc raiders without an orc home town")
		var attackers: Array = w["warbands"][orcs]["units"]
		check(not attackers.is_empty(), "loss fixture has accepted real attackers")
		var seen_people := {}
		var roll_book: Dictionary = Army.state(w)["roll"]
		for u in attackers:
			var home: Dictionary = w["towns"].get(u.home_town, {})
			var family := People.fam_of(home, u.family)
			var person := Persons.by_uid(family, u.uid) if not family.is_empty() else []
			var identity := "%s:%d:%d" % [u.home_town, u.family, int(person[0]) if not person.is_empty() else -1]
			check(source_people.has(identity) and not seen_people.has(identity), "attacker %d is one unique pre-existing registered person" % u.uid)
			seen_people[identity] = true
			var entry: Array = roll_book.get(str(u.uid), [])
			check(u.faction == "orc_horde" and home.get("faction", "") == "orc_horde" and entry.size() >= 3
				and entry[0] == u.home_town and int(entry[1]) == u.family and entry[2] == "army", "attacker %d retains actual home/family/army roll" % u.uid)
		print("loss fixture requested 30, accepted %d real registered attackers" % attackers.size())
		check(Caravans.is_prey(w, w["warbands"][orcs], w["warbands"][c2]), "staged attacker is hostile to the caravan")
		var cp := CampaignWorld.band_power(w["warbands"][c2]["units"])
		var ap := CampaignWorld.band_power(w["warbands"][orcs]["units"])
		var caravan_win := cp * cp / maxf(0.001, cp * cp + ap * ap)
		var clash_rng := RandomNumberGenerator.new(); clash_rng.seed = 42
		var clash_state := clash_rng.state
		var roll := clash_rng.randf()
		check(roll >= caravan_win, "controlled clash roll selects the attacker: %.6f >= %.6f" % [roll, caravan_win])
		clash_rng.state = clash_state
		w["encounter"] = ""
		CampaignWorld._warband_clashes(Game, Game.day, clash_rng)
		check(not w["warbands"].has(c2), "controlled hostile clash destroys the caravan")
		check(dest["shop"].size() == dest_shop0, "a lost caravan still delivered")
		check(Goods.supply(dest, "linen") == dest_linen, "destroyed cargo adds no linen at the destination")
		check(int(TownEcon.goods_lost.get("linen", 0)) - linen_lost == linen_load, "destroyed linen is recorded once in the actual goods-loss ledger")
		print("loss log: ", w["log"].slice(-1))
	# ---------------------------------------------------------------- escort success
	_clear_bands(w)
	Game.contract = {}
	var town: Dictionary = origin
	var offer := {}
	for i in 60:
		offer = Contracts.escort_offer(town, Game.day, rng)
		if not offer.is_empty():
			break
	check(not offer.is_empty(), "no escort offer")
	town["contracts"].append(offer)
	print("escort offer: ", offer["desc"], " pay ", offer["pay"])
	w["party"]["pos"] = town["pos"] + Vector2(0, 30)
	w["party"]["path"] = []
	check(Contracts.accept(Game, offer), "escort accept")
	var ecar: String = Game.contract["target_id"]
	check(w["warbands"][ecar]["state"] == "waiting", "escort caravan should wait for the company")
	var gold0: int = Game.gold
	var done := false
	for i in 600:
		Game.advance_time(0.02, false)
		w["encounter"] = ""
		if w["warbands"].has(ecar):
			w["party"]["pos"] = w["warbands"][ecar]["pos"] + Vector2(10, 0)   # the company follows the carts
		if Game.contract.is_empty():
			done = true
			break
	check(done and (not w["warbands"].has(ecar) or w["warbands"][ecar].get("leg", "") == "home"), "escort never finished (economy: the caravan then heads home)")
	check(Game.gold > gold0 - Game.daily_wages() * 20 + int(offer["pay"]) - 1, "escort pay missing (gold %d -> %d)" % [gold0, Game.gold])
	print("escort result: ", w["log"].slice(-2))
	# ---------------------------------------------------------------- escort failure: the company wanders off
	_clear_bands(w)
	var offer2 := {}
	for i in 60:
		offer2 = Contracts.escort_offer(town, Game.day, rng)
		if not offer2.is_empty():
			break
	town["contracts"].append(offer2)
	w["party"]["pos"] = town["pos"] + Vector2(0, 30)
	Contracts.accept(Game, offer2)
	var fcar: String = Game.contract["target_id"]
	for i in 10:
		Game.advance_time(0.02, false)
	check(w["warbands"][fcar]["state"] == "travel", "escort caravan did not set out")
	w["party"]["pos"] = CampaignWorld.nearest_passable(w, w["warbands"][fcar]["pos"] + Vector2(600, 0))
	var rep0: int = Game.rep["middle_kingdom"]
	for i in 60:
		Game.advance_time(0.02, false)
		w["encounter"] = ""
		if Game.contract.is_empty():
			break
	check(Game.contract.is_empty() and int(Game.rep["middle_kingdom"]) < rep0, "straying did not fail the escort")
	check(w["warbands"].has(fcar) and w["warbands"][fcar]["escort"] == "", "abandoned caravan should go on alone")
	print("escort failure: ", w["log"].slice(-1))
	# ---------------------------------------------------------------- the player raids a caravan
	_clear_bands(w)
	_fund_linen(origin, dest)
	var rc := Caravans.spawn(Game, pair[0], rng, pair[1])
	var rcargo: Dictionary = w["warbands"][rc]["cargo"]
	var r_uids: Array = rcargo["items"].map(func(it): return it.uid)
	var food_q: float = rcargo["goods"].get("linen", 0.0)
	var cg0: float = float(Goods.company_goods(Game).get("linen", 0.0))
	var rep1: int = Game.rep[origin["faction"]]
	check(Caravans.can_raid(Game, rc), "raid hook refuses an unescorted caravan")
	var guards: Array = w["warbands"][rc]["units"]
	for u in guards:
		u.dead = true
	Game.pending_battle = {"warband_id": rc, "enemy": guards}
	Game.finish_battle({"winner": 0, "player_units": Game.company, "enemy_units": guards, "enemy_fallen": guards, "events": []})
	var stash_uids: Array = Game.stash.map(func(it): return it.uid)
	var in_stash := r_uids.filter(func(u): return stash_uids.has(u)).size()
	check(in_stash == int(ceil(r_uids.size() * Caravans.PLUNDER_SHARE)), "raided items: %d of %d in the stash (economy: the company takes its share, the rest is lost)" % [in_stash, r_uids.size()])
	check(absf(float(Goods.company_goods(Game).get("linen", 0.0)) - cg0 - round(food_q * Caravans.PLUNDER_SHARE)) < 0.01, "raided linen (the company's share) not in the company goods store")
	check(int(Game.rep[origin["faction"]]) <= rep1 + Caravans.RAID_REP, "raid did not cost reputation")
	check(not w["warbands"].has(rc), "raided caravan still on the map")
	var sold := Goods.sell(Game, dest, "linen", int(round(food_q * Caravans.PLUNDER_SHARE)))
	print("raid: %d items, %.0f food; sold the food in %s for %d gold; log %s" % [r_uids.size(), food_q, dest["name"], sold, w["log"].slice(-1)])
	check(food_q < 1.0 or sold > 0, "could not sell looted food")
	# ---------------------------------------------------------------- save/load with caravans in flight
	_clear_bands(w)
	for tid in w["towns"]:
		if Caravans.count(w) < 4:
			Caravans.spawn(Game, tid, rng)
	var before := {}
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		before[wid] = "%s>%s %s %s" % [wb["origin"], wb["dest"], str(wb["cargo"]["items"].map(func(it): return it.uid)), _gs(wb["cargo"]["goods"])]
	Game.save_game()
	Game.world = {}
	Game.load_game()
	w = Game.world
	for wid in before:
		var wb: Dictionary = w["warbands"].get(wid, {})
		check(not wb.is_empty(), "caravan %s lost in save/load" % wid)
		if not wb.is_empty():
			var after := "%s>%s %s %s" % [wb["origin"], wb["dest"], str(wb["cargo"]["items"].map(func(it): return it.uid)), _gs(wb["cargo"]["goods"])]
			check(after == before[wid], "caravan %s changed: %s vs %s" % [wid, before[wid], after])
			check(wb["cargo"]["items"].is_empty() or wb["cargo"]["items"][0] is Item, "cargo items not Items after load")
	# ---------------------------------------------------------------- per-frame cost at map frame rate
	Game.new_game(321)
	w = Game.world
	for i in 40:
		Game.advance_time(0.25, false)   # let caravans and bands populate
		w["encounter"] = ""
	for tid in w["towns"]:
		if Caravans.count(w) < Caravans.MAX_CARAVANS:
			Caravans.spawn(Game, tid, rng)
	w["party"]["safe_until"] = Game.day + 100.0
	var frame_days := (1.0 / 60.0) / 5.0
	var total := 0
	var worst := 0
	var n := 600
	for i in n:
		var t0 := Time.get_ticks_usec()
		Game.day += frame_days
		CampaignWorld.on_time(Game, frame_days, false)
		var dtu := Time.get_ticks_usec() - t0
		total += dtu
		worst = maxi(worst, dtu)
		w["encounter"] = ""
	var mean := total / float(n) / 1000.0
	print("on_time per map frame: mean %.3f ms, worst %.2f ms, %d warbands (%d caravans)" % [mean, worst / 1000.0, w["warbands"].size(), Caravans.count(w)])
	check(mean < 0.5, "on_time too slow per frame: %.3f ms" % mean)
	return fails
