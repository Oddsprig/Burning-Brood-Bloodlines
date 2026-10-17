extends RefCounted
## Arms trade (docs/specs/arms-trade.md): gear of the dead leaves the forces (AI loot through Loot.spoils, the player's
## own function: kept + scrapped + fled-with == the kit in play; items conserved world-wide), spoils gold split half to
## the victors' pay and half to their coffer (gold conserved), foreign loot issued from the home armory by role, the
## armory re-kits, local smiths refill through paid orders, ordinary trade carries
## real pieces, and maker's marks survive trade and save/load. Retired special
## contracts are covered by the migration matrix in test_military_supply.gd.

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

## Every Item the world holds: stalls, armories, camp hoards, men's kit, cargo, contract batches, the company.
func _items(w: Dictionary) -> int:
	var n := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		n += (t.get("shop", []) as Array).size() + (t.get("armory_items", []) as Array).size()
	for lid in w.get("lairs", {}):
		n += (w["lairs"][lid].get("stock", []) as Array).size()
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		for u in wb["units"]:
			n += u.equip.size()
		n += (wb.get("cargo", {}).get("items", []) as Array).size()
	for cid in w.get("arms", {}).get("c", {}):
		n += (w["arms"]["c"][cid]["staged"] as Array).size()
	for u in Game.company:
		n += u.equip.size()
	return n + Game.stash.size()

func _gold(w: Dictionary) -> float:
	var g := 0.0
	for tid in w["towns"]:
		if TownEcon.has_econ(w["towns"][tid]):
			g += TownEcon.town_gold(w["towns"][tid]["econ"])
	for fid in w["factions"]:
		g += float(w["factions"][fid].get("treasury", 0.0))
	for wid in w["warbands"]:
		g += float(w["warbands"][wid].get("gold", 0.0))
	return g

func _town_of(w: Dictionary, fid: String) -> Dictionary:
	var ids: Array = w["towns"].keys()
	ids.sort()
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] == fid and TownEcon.has_econ(t):
			return t
	return {}

func _quiet(w: Dictionary) -> void:
	for wid in w["warbands"].keys():
		if w["warbands"][wid]["kind"] != "militia":
			CampaignWorld.remove_warband(Game, wid)
	w["work"] = []
	w["party"]["safe_until"] = 1.0e9

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_save_arms_%d.json" % OS.get_process_id()
	Game.new_game(5150)
	var w: Dictionary = Game.world
	_quiet(w)
	_test_generation(w)
	_test_clash_loot(w)
	_test_militia_and_raid(w)
	_test_foreign_rekit(w)
	_test_smiths_first(w)
	_test_marks_save(w)
	_test_market(w)
	_test_full_world()
	return fails

## Market trade: a caravan carries the pieces the destination's armory is short of first.
func _make_surplus(t: Dictionary, c: String, n: int) -> void:
	var pool := []
	for tid in Businesses.gear_pool(String(t["culture"]), "weapon"):
		if ArmsTrade.cls(String(tid)) == c: pool.append(tid)
	for i in n:
		var it := Item.make(pool[i % pool.size()], "copper", 1)
		ArmsTrade.mark_old(it, t)
		(t["shop"] as Array).append(it)
	t["econ"]["arms_short"] = {}

func _test_market(_w0: Dictionary) -> void:
	var w: Dictionary = Game.world
	var o := _town_of(w, "moon_court")
	var d := _town_of(w, "middle_kingdom")
	_make_surplus(o, "w_sword", 4)
	d["econ"]["arms_short"] = {"w_sword": 3}
	var picks := ArmsTrade.export_picks(o, d, 6)
	var ok := picks.size() == 3
	for it in picks:
		ok = ok and ArmsTrade.cls(it.tid) == "w_sword"
	check(ok, "caravans pick what the destination's armory is short of (%d picked)" % picks.size())

## The real world for 120 days: wars, clashes, re-kits, contracts. Numbers for the change notes.
func _test_full_world() -> void:
	ArmsTrade.ledger = {}
	ArmsTrade.spoils_gold = {"soldiers": 0.0, "coffer": 0.0}
	Game.new_game(6061)
	var w: Dictionary = Game.world
	var worst := 0
	var t0 := Time.get_ticks_msec()
	for i in 120:
		var a := Time.get_ticks_usec()
		Game.advance_time(1.0, false)
		worst = maxi(worst, Time.get_ticks_usec() - a)
	var st: Dictionary = w["arms"]["stats"]
	var short_n := 0; var arm_n := 0; var tgt_n := 0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid].get("econ", {})
		for c in e.get("arms_short", {}):
			short_n += int(e["arms_short"][c])
		arm_n += ArmsTrade.armory(w["towns"][tid]).size()
		for c in e.get("arms_tgt", {}):
			tgt_n += int(e["arms_tgt"][c])
	print("-- 120 days (%.1f s, worst day %.1f ms): contracts %s; armories %d pieces vs targets %d, %d short; dead men's kit %s; spoils gold to the men %.0f, to the coffers %.0f" % [
		(Time.get_ticks_msec() - t0) / 1000.0, worst / 1000.0, str(st), arm_n, tgt_n, short_n, str(ArmsTrade.ledger),
		float(ArmsTrade.spoils_gold["soldiers"]), float(ArmsTrade.spoils_gold["coffer"])])
	for l in (w["arms"]["hist"] as Array).slice(-6):
		print("   ", l)
	check((w["arms"]["c"] as Dictionary).is_empty(), "new campaigns create no special arms contracts")
	check(int(w["arms"].get("supply_day", -1)) >= 110, "ten-day internal supply runs during the campaign")
	check(not (w["work"] as Array).any(func(j): return String(j[0]) in ["arms_day", "arms_week", "arms_spawn"]), "retired contract jobs are never scheduled")
	check(int(ArmsTrade.ledger.get("scrapped", 0)) + int(ArmsTrade.ledger.get("looted", 0)) > 0, "AI fights put the dead men's kit somewhere")

func _test_generation(w: Dictionary) -> void:
	var n := 0; var arm := 0; var marked := 0; var shop := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		n += 1
		arm += ArmsTrade.armory(t).size()
		for it in t["shop"]:
			shop += 1
			if not it.mark.is_empty():
				marked += 1
	var t0 := _town_of(w, "middle_kingdom")
	print("-- %d towns, %d pieces in the heads' armories, %d of %d stall pieces marked; %s armory: %s" % [n, arm, marked, shop, t0["name"],
		"; ".join(PackedStringArray(ArmsTrade.armory_lines(t0)))])
	check(arm > 0, "armories open at their targets")
	check(marked > 0, "the opening stalls carry their makers' marks")

## AI clash: both bands' fallen through Loot.spoils; kept + scrapped + fled-with == the kit of the fallen and fled;
## items conserved world-wide; spoils gold half to the victors' pay, half to the coffer, gold conserved.
func _test_clash_loot(w: Dictionary) -> void:
	_force(w, "middle_kingdom", "orc_horde", Diplomacy.WAR, -80.0)
	var rng := RandomNumberGenerator.new(); rng.seed = 77
	var ta := _town_of(w, "middle_kingdom")
	var tb := _town_of(w, "orc_horde")
	var pos: Vector2 = ta["pos"] + Vector2(200, 0)
	var a := CampaignWorld.spawn_warband(Game, "middle_kingdom", pos, 12, "patrol", rng, {"home": ta["id"]})
	var b := CampaignWorld.spawn_warband(Game, "orc_horde", pos + Vector2(3, 0), 9, "raider", rng, {"home": tb["id"]})
	var all_units: Array = w["warbands"][a]["units"] + w["warbands"][b]["units"]
	var kit0 := 0
	for u in all_units:
		kit0 += u.equip.size()
	var items0 := _items(w)
	var led0: Dictionary = ArmsTrade.ledger.duplicate()
	var sg0: Dictionary = ArmsTrade.spoils_gold.duplicate()
	var gold0 := _gold(w); var gone0 := TownEcon.gold_gone
	ArmsTrade.last_spoils = {}
	CampaignWorld._warband_clashes(Game, Game.day, rng)
	var winner := a if w["warbands"].has(a) else b
	check(not (w["warbands"].has(a) and w["warbands"].has(b)), "the clash had a loser")
	var d := func(k: String) -> int: return int(ArmsTrade.ledger.get(k, 0)) - int(led0.get(k, 0))
	var surv := 0
	for u in w["warbands"].get(winner, {}).get("units", []):
		surv += u.equip.size()
	var items1 := _items(w)
	var acc: int = surv - d.call("rekit") + d.call("looted") + d.call("scrapped") + d.call("lost") + d.call("fled") + d.call("fenced") + d.call("fled_lost")
	print("-- clash: %s won; kit in play %d: survivors keep %d (+%d looted on), kept %d, scrapped %d, left %d, fled home with %d (+%d handed in, %d lost on the road)" % [
		w["warbands"][winner]["faction"], kit0, surv - d.call("rekit"), d.call("rekit"), d.call("looted"), d.call("scrapped"), d.call("lost"), d.call("fled"), d.call("fenced"), d.call("fled_lost")])
	check(not ArmsTrade.last_spoils.is_empty() and ArmsTrade.last_spoils.has("scrapped"), "AI loot goes through Loot.spoils")
	check(acc == kit0, "kept + scrapped + fled-with + survivors' kit == kit in play (%d vs %d)" % [acc, kit0])
	check(items1 + d.call("scrapped") + d.call("lost") + d.call("fled_lost") == items0, "items conserved (%d + %d scrapped + %d left vs %d)" % [items1, d.call("scrapped"), d.call("lost") + d.call("fled_lost"), items0])
	var men := float(ArmsTrade.spoils_gold["soldiers"]) - float(sg0["soldiers"])
	var cof := float(ArmsTrade.spoils_gold["coffer"]) - float(sg0["coffer"])
	var gold1 := _gold(w); var gone := TownEcon.gold_gone - gone0
	print("   spoils gold: %.1f to the victors' pay, %.1f to their coffer; gold %.1f -> %.1f (+%.1f out)" % [men, cof, gold0, gold1, gone])
	check(men + cof > 0.0, "the victors take scrap gold and coin")
	check(absf(men - cof) < 0.01, "half to the men, half to the coffer (%.2f vs %.2f)" % [men, cof])
	check(absf(gold1 + gone - gold0) < 0.5, "gold conserved through the spoils (%.2f + %.2f vs %.2f)" % [gold1, gone, gold0])
	# the beaten realm's forces lost kit: the loser's home armory did not grow from the dead
	CampaignWorld.remove_warband(Game, winner)

## Militia sally and an AI raid on a caravan: conserved too; the raiders carry part of the arms cargo home.
func _test_militia_and_raid(w: Dictionary) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 91
	var ta := _town_of(w, "middle_kingdom")
	var tb := _town_of(w, "orc_horde")
	var mid := String(w["militia"].get(ta["id"], ""))
	var mil: Dictionary = w["warbands"].get(mid, {})
	check(not mil.is_empty(), "the town has a militia")
	var x := CampaignWorld.spawn_warband(Game, "orc_horde", ta["pos"], 3, "raider", rng, {"home": tb["id"]})
	var items0 := _items(w)
	var led0: Dictionary = ArmsTrade.ledger.duplicate()
	Militia._fight(Game, ta["id"], mil, w["warbands"][x], rng)
	var d := func(k: String) -> int: return int(ArmsTrade.ledger.get(k, 0)) - int(led0.get(k, 0))
	check(_items(w) + d.call("scrapped") + d.call("lost") + d.call("fled_lost") == items0, "militia fight: items conserved")
	print("-- militia fight: kept %d, scrapped %d, left %d, fled home %d" % [d.call("looted"), d.call("scrapped"), d.call("lost"), d.call("fled")])
	if w["warbands"].has(x):
		CampaignWorld.remove_warband(Game, x)
	# an orc band takes a human caravan
	var car := Caravans.spawn(Game, ta["id"], rng, "", "", {"items": [Item.make("arming_sword", "copper", 2), Item.make("nasal_helm", "tin", 1)], "goods": {}})
	if car == "":
		print("   (no caravan could leave: raid part skipped)")
		return
	var cw: Dictionary = w["warbands"][car]
	var r := CampaignWorld.spawn_warband(Game, "orc_horde", cw["pos"], 10, "raider", rng, {"home": tb["id"]})
	cw["pos"] = w["warbands"][r]["pos"]
	var arm0 := ArmsTrade.armory(tb).size()
	items0 = _items(w)
	var lost0 := int(TownEcon.goods_lost.get("arms", 0))
	led0 = ArmsTrade.ledger.duplicate()
	var led1: Dictionary = led0
	d = func(k: String) -> int: return int(ArmsTrade.ledger.get(k, 0)) - int(led1.get(k, 0))
	for i in 6:
		if not w["warbands"].has(car):
			break
		CampaignWorld._warband_clashes(Game, Game.day, rng)
	if w["warbands"].has(car):
		print("   (the guards beat the orcs off)")
	else:
		var cargo_lost := int(TownEcon.goods_lost.get("arms", 0)) - lost0
		check(_items(w) + d.call("scrapped") + d.call("lost") + cargo_lost == items0, "caravan raid: items conserved")
		print("-- caravan raid: orc armory %d -> %d, cargo lost %d" % [arm0, ArmsTrade.armory(tb).size(), cargo_lost])
	if w["warbands"].has(r):
		CampaignWorld.remove_warband(Game, r)

## Douglas: looted foreign gear goes into the winner's home armory with its marks and is issued like home-made kit:
## a human spearman with no spear in his armory takes the looted orc cleaver for his weapon hand.
func _test_foreign_rekit(w: Dictionary) -> void:
	var ta := _town_of(w, "middle_kingdom")
	var arm := ArmsTrade.armory(ta)
	var keep := arm.duplicate()
	arm.clear()
	var tb := _town_of(w, "orc_horde")
	var axe := Item.make("hacking_cleaver", "copper", 1)
	ArmsTrade.mark(axe, tb, (tb["econ"]["biz"] as Array).filter(func(bz): return bz["type"] == "weaponsmith")[0])
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var u := Factory.make_troop(rng, "middle_kingdom", DB.factions["middle_kingdom"]["troops"][0], 2)
	u.faction = "middle_kingdom"
	var band := {"id": "x", "faction": "middle_kingdom", "home": ta["id"], "units": [], "kind": "patrol"}
	ArmsTrade.to_holder(Game, {"band": band}, axe)
	check(arm.has(axe), "looted foreign gear goes into the home armory")
	var lo := ArmsTrade.loadout_of(u)
	u.equip.erase("main_hand")
	var n := ArmsTrade.rekit_units(Game, ta, [u], false)
	var got: Item = u.equip.get("main_hand", null)
	print("-- foreign kit: %s's spearman re-armed with %s (%s); wanted %s" % [ta["name"], got.display_name() if got else "nothing",
		got.maker_text() if got else "-", str(lo.get("main_hand", {}).get("tids", []))])
	check(n >= 1 and got == axe and got.maker_race() == "orc", "the armory issues a looted orc cleaver for a weapon hand")
	check(not arm.has(axe), "re-kit lowers the armory")
	arm.clear()
	arm.append_array(keep)

## The armory falls short; the head's own smiths make what it lacks first (and he buys it off his stalls).
func _test_smiths_first(w: Dictionary) -> void:
	var t := _town_of(w, "middle_kingdom")
	var e: Dictionary = t["econ"]
	var arm := ArmsTrade.armory(t)
	var c := "w_spear"
	for it in arm.duplicate():
		if ArmsTrade.cls(it.tid) == c or ArmsTrade.cls_role(ArmsTrade.cls(it.tid)) == "main_hand":
			arm.erase(it)
	(t["shop"] as Array).clear()
	e["stock"]["copper_bars"] = 400
	e["stock"]["tin_bars"] = 400
	e["stock"]["wood"] = int(e["stock"].get("wood", 0)) + 200
	for b in e["biz"]:
		if b["type"] == "weaponsmith":
			b["workers"] = maxi(2, int(b["workers"]))
			b["cap"] = maxi(int(b["cap"]), int(b["workers"]))
			b["till"] = maxf(float(b["till"]), 2000.0 * TownEcon.COIN)   # coinage x20
	e["treasury"] = maxf(float(e["treasury"]), 3000.0 * TownEcon.COIN)
	var have0 := int(ArmsTrade.class_counts(arm).get(c, 0))
	for i in 12:
		var dd := int(e["day"]) + 1
		Game.day = float(dd)
		TownEcon.daily_pass(Game, t, dd)
		ArmsTrade.econ_daily(Game, t, e, dd)   # the "arms_town" work job for this town
	var have1 := int(ArmsTrade.class_counts(arm).get(c, 0))
	var local := 0
	for it in arm:
		if ArmsTrade.cls(it.tid) == c and String(it.mark.get("t", "")) == String(t["id"]):
			local += 1
	print("-- smiths first: %s armory %s %d -> %d of target %d (%d marked by its own smiths); short %s, days short %s" % [t["name"], c, have0, have1,
		int(e["arms_tgt"].get(c, 0)), local, str(e.get("arms_short", {})), str(e.get("arms_sd", {}))])
	check(have1 > have0 and local > 0, "the town's own smiths refill a short armory")

func _test_marks_save(w: Dictionary) -> void:
	var t := _town_of(w, "middle_kingdom")
	var smith: Dictionary = {}
	for bz in t["econ"]["biz"]:
		if bz["type"] == "armorsmith":
			smith = bz
	var it := Item.make("nasal_helm", "copper", 2)
	ArmsTrade.mark(it, t, smith)
	ArmsTrade.armory(t).append(it)
	var uid := it.uid
	var txt := it.maker_text()
	# a caravan sells it into a foreign town: the mark travels
	var tb := _town_of(w, "moon_court")
	tb["econ"]["biz"][int(tb["econ"]["mkt"])]["till"] = 99999.0
	var it2 := Item.make("arming_sword", "tin", 1)
	ArmsTrade.mark(it2, t, smith)
	Caravans.sell_cargo(tb, {"items": [it2], "goods": {}}, t["name"])
	check((tb["shop"] as Array).has(it2) and it2.maker_text().find(t["name"]) >= 0, "the mark survives trade")
	var old := Item.from_dict({"uid": 999999, "tid": "mail_shirt", "mat": "tin", "q": 0})
	check(old.mark.is_empty() and old.maker_text().begins_with("maker unknown"), "old saves: maker unknown")
	Game.save_game()
	Game.load_game()
	var w2: Dictionary = Game.world
	var t2: Dictionary = w2["towns"][t["id"]]
	var found: Item = null
	for x in ArmsTrade.armory(t2):
		if x.uid == uid:
			found = x
	print("-- marks: '%s'; after load '%s'; contracts kept %d" % [txt, found.maker_text() if found else "-", (w2.get("arms", {}).get("c", {}) as Dictionary).size()])
	check(found != null and found.maker_text() == txt, "the mark survives save/load")
	check((w2["arms"]["c"] as Dictionary).size() == (w["arms"]["c"] as Dictionary).size(), "arms contracts survive save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
