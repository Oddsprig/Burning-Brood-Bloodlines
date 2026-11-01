extends RefCounted
## v0.077: prisoner upkeep and AI ransom on a real generated world. Battles use the live capture path.
## Later days call Prisoners.daily directly, so only this feature moves coin. Godot is not run from the
## work that wrote this file.
## Run: godot --path game --headless res://tests/runner.tscn -- --test=res://tests/test_ransom_upkeep_v077.gd
const NativeFixture = preload("res://tests/test_feudal_succession.gd")
var checks := 0
var fails := 0
var previous_save_path := ""
var _band_id := ""
var _enemy := ""
var _pool: Array = []
var _ransomed: Unit = null

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL ransom077: ", what)

func _finish() -> int:
	Game.wait_save()
	if previous_save_path != "": Game.SAVE_PATH = previous_save_path
	print("ransom077: %d checks, %d failures" % [checks, fails])
	return fails

func _purse() -> float:
	return float(Feudal._payer(Game).get("purse", 0.0))

func _treasury(fid: String) -> float:
	return float(Game.world.get("factions", {}).get(fid, {}).get("treasury", 0.0))

func _person(u: Unit) -> Array:
	var town: Dictionary = Game.world["towns"].get(u.home_town, {})
	var f: Dictionary = People.fam_of(town, u.family) if not town.is_empty() else {}
	return Persons.by_uid(f, u.uid) if not f.is_empty() else []

func _coin_sum() -> float:
	var n := 0.0
	var payer := Feudal._payer(Game)
	var seen := false
	for town in Game.world.get("towns", {}).values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		n += float(e.get("treasury", 0.0)) + float(e.get("farm_till", 0.0)) + float(e.get("land_fund", 0.0))
		for b in e.get("biz", []):
			if b is Dictionary: n += float((b as Dictionary).get("till", 0.0))
		for f in e.get("fams", []):
			if f is Dictionary:
				if is_same(f, payer): seen = true
				n += float((f as Dictionary).get("purse", 0.0))
	if not seen and not payer.is_empty(): n += float(payer.get("purse", 0.0))
	for fac in Game.world.get("factions", {}).values():
		n += float((fac as Dictionary).get("treasury", 0.0))
	return n

func _set_food(stock: Dictionary, grain: int) -> void:
	for g in Prisoners.FOODS:
		stock[g] = grain if str(g) == "grain" else 0

func _zero_town_food(town: Dictionary) -> void:
	if town.is_empty() or not TownEcon.has_econ(town): return
	var e: Dictionary = town["econ"]
	_set_food(e["stock"], 0)
	if e.has("barn"): _set_food(e["barn"], 0)
	e["granary"] = 0

func _zero_band_food(fid: String) -> void:
	for band in Game.world.get("warbands", {}).values():
		if str(band.get("faction", "")) != fid: continue
		if not band.has("stores") or not band["stores"] is Dictionary: band["stores"] = {}
		_set_food(band["stores"], 0)

func _stock_player(grain: int, coins: int) -> Dictionary:
	var town: Dictionary = Prisoners._player_town(Game)
	if town.is_empty() or not TownEcon.has_econ(town): return {}
	_set_food(town["econ"]["stock"], grain)
	Feudal._payer(Game)["purse"] = float(coins * Item.COIN)
	return town

func _stock_enemy(grain: int, coins: int) -> Dictionary:
	var town: Dictionary = Prisoners._faction_town(Game, _enemy)
	if town.is_empty() or not TownEcon.has_econ(town): return {}
	_set_food(town["econ"]["stock"], grain)
	_zero_band_food(_enemy)
	Game.world["factions"][_enemy]["treasury"] = float(coins * Item.COIN)
	return town

func _zero_houses(units: Array) -> void:
	for u in units:
		var rec: Dictionary = Prisoners._find(Prisoners.held(Game), u.uid)
		if rec.is_empty(): continue
		var a := Prisoners._address(Game, rec)
		if not a.is_empty(): a["family"]["purse"] = 0.0

func _bump() -> void:
	Game.day += 1.0
	Prisoners.daily(Game, int(Game.day))

func _age(rec: Dictionary) -> void:
	rec["day"] = float(int(Game.day) - Prisoners.AI_HOLD_DAYS)

func _clash(winner: int, units: Array, states: Array) -> void:
	Game.pending_battle = {"warband_id": _band_id}
	BattleRounds.take_one_clash(Game, {"winner": winner, "fighter_units": units, "fighter_states": states,
		"enemy_units": units.filter(func(u): return not Game.company.has(u))})
	Game.pending_battle = {}

func _take_foes(units: Array) -> bool:
	var band: Array = Game.world["warbands"][_band_id]["units"]
	var states: Array = []
	for u in units:
		if not band.has(u): return false
		states.append("unconscious")
	_clash(0, units, states)
	for u in units:
		if Prisoners._find(Prisoners.held(Game), u.uid).is_empty(): return false
	return true

func _take_one_of_ours() -> Unit:
	for u in Game.company.duplicate():
		if not u is Unit or (u as Unit).dead or u.family < 0 or _person(u).is_empty(): continue
		if Prisoners.kind_of(Game, {"uid": u.uid, "unit": u, "home_town": u.home_town, "family": u.family}) == "ruler": continue
		_clash(1, [u], ["unconscious"])
		if not Prisoners._find(Prisoners.captives(Game), u.uid).is_empty(): return u
	return null

func _house_purse(u: Unit) -> float:
	var town: Dictionary = Game.world["towns"].get(u.home_town, {})
	var f: Dictionary = People.fam_of(town, u.family) if not town.is_empty() else {}
	return float(f.get("purse", 0.0)) if not f.is_empty() else 0.0

func _till(town: Dictionary) -> float:
	var stall := Prisoners._market_till(town)
	return float(stall.get("till", 0.0)) if not stall.is_empty() else -1.0

func _count_item(it, uids: Dictionary, where: Dictionary = {}, holder: String = "") -> int:
	if not it is Item: return 0
	var item: Item = it
	if item.uid > 0:
		uids[item.uid] = int(uids.get(item.uid, 0)) + 1
		if holder != "":
			where[item.uid] = holder if not where.has(item.uid) else str(where[item.uid]) + "+" + holder
	else:
		uids[0] = int(uids.get(0, 0)) + 1
	return 1

func _count_unit_items(u, seen_units: Dictionary, uids: Dictionary, where: Dictionary = {}, holder: String = "") -> int:
	if not u is Unit: return 0
	var unit: Unit = u
	var id := unit.get_instance_id()
	if seen_units.has(id): return 0
	seen_units[id] = true
	var n := 0
	for slot in unit.equip:
		n += _count_item(unit.equip[slot], uids, where, holder)
	return n

func _accounted_items() -> Dictionary:
	var uids := {}
	var where := {}
	var buckets := {"stash": 0, "company": 0, "reserve": 0, "warbands": 0, "prisoners": 0, "town_shop": 0, "town_armory": 0, "lairs": 0}
	var seen_units := {}
	var n := 0
	for it in Game.stash:
		var c := _count_item(it, uids, where, "stash")
		n += c; buckets["stash"] += c
	for u in Game.company:
		var c := _count_unit_items(u, seen_units, uids, where, "company")
		n += c; buckets["company"] += c
	for u2 in Mobilization.reserves(Game):
		var c := _count_unit_items(u2, seen_units, uids, where, "reserve")
		n += c; buckets["reserve"] += c
	for wid in Game.world.get("warbands", {}):
		var wb: Dictionary = Game.world["warbands"][wid]
		for u3 in wb.get("units", []):
			var c := _count_unit_items(u3, seen_units, uids, where, "warband:" + str(wid))
			n += c; buckets["warbands"] += c
	for list in Prisoners.custody_lists(Game):
		for rec in list:
			var c := _count_unit_items((rec as Dictionary).get("unit"), seen_units, uids, where, "prisoners")
			n += c; buckets["prisoners"] += c
	for tid in Game.world.get("towns", {}):
		var td: Dictionary = Game.world["towns"][tid]
		for it2 in td.get("shop", []):
			var c := _count_item(it2, uids, where, "town:%s:shop" % str(tid))
			n += c; buckets["town_shop"] += c
		for it3 in ArmsTrade.armory(td):
			var c := _count_item(it3, uids, where, "town:%s:armory" % str(tid))
			n += c; buckets["town_armory"] += c
	for lid in Game.world.get("lairs", {}):
		var lair: Dictionary = Game.world["lairs"][lid]
		for it4 in lair.get("stock", []):
			var c := _count_item(it4, uids, where, "lair:" + str(lid))
			n += c; buckets["lairs"] += c
	return {"count": n, "uids": uids, "where": where, "buckets": buckets}

func _item_delta_diag(pre: Dictionary, post: Dictionary) -> String:
	var pre_uids: Dictionary = pre.get("uids", {})
	var post_uids: Dictionary = post.get("uids", {})
	var pre_where: Dictionary = pre.get("where", {})
	var post_where: Dictionary = post.get("where", {})
	var all_keys := {}
	for k in pre_uids: all_keys[int(k)] = true
	for k2 in post_uids: all_keys[int(k2)] = true
	var sorted_keys: Array = all_keys.keys()
	sorted_keys.sort()
	var missing_uids := 0
	var added_uids := 0
	var missing_sample: Array = []
	var added_sample: Array = []
	var holder_deltas := {}
	for uid in sorted_keys:
		var a := int(pre_uids.get(uid, 0))
		var b := int(post_uids.get(uid, 0))
		if b < a:
			missing_uids += a - b
			var h := str(pre_where.get(uid, "uid0" if int(uid) == 0 else "?"))
			holder_deltas[h] = int(holder_deltas.get(h, 0)) - (a - b)
			if missing_sample.size() < 10:
				missing_sample.append("%d@%s" % [int(uid), h])
		elif b > a:
			added_uids += b - a
			var h2 := str(post_where.get(uid, "uid0" if int(uid) == 0 else "?"))
			holder_deltas[h2] = int(holder_deltas.get(h2, 0)) + (b - a)
			if added_sample.size() < 10:
				added_sample.append("%d@%s" % [int(uid), h2])
	var b_parts: Array = []
	var pre_b: Dictionary = pre.get("buckets", {})
	var post_b: Dictionary = post.get("buckets", {})
	for bk in ["stash", "company", "reserve", "warbands", "prisoners", "town_shop", "town_armory", "lairs"]:
		var d := int(post_b.get(bk, 0)) - int(pre_b.get(bk, 0))
		if d != 0:
			b_parts.append("%s:%d->%d(%+d)" % [bk, int(pre_b.get(bk, 0)), int(post_b.get(bk, 0)), d])
	var h_keys: Array = holder_deltas.keys()
	h_keys.sort()
	var h_parts: Array = []
	for hk in h_keys.slice(0, 10):
		h_parts.append("%s:%+d" % [str(hk), int(holder_deltas[hk])])
	return "missing_uids=%d added_uids=%d buckets=[%s] holders=[%s] missing_sample=[%s] added_sample=[%s]" % [
		missing_uids, added_uids, ", ".join(PackedStringArray(b_parts)), ", ".join(PackedStringArray(h_parts)),
		", ".join(PackedStringArray(missing_sample)), ", ".join(PackedStringArray(added_sample))]

func _town_has_uid(town: Dictionary, item_uid: int) -> bool:
	for it in ArmsTrade.armory(town) + (town.get("shop", []) as Array):
		if it is Item and (it as Item).uid == item_uid:
			return true
	return false

func _town_arrows(town: Dictionary) -> int:
	if town.is_empty() or not TownEcon.has_econ(town): return 0
	var arm: Dictionary = town["econ"].get("armory", {})
	var n := 0
	for k in arm:
		n += maxi(0, int(arm.get(k, 0)))
	return n

func _unit_arrows(u, seen_units: Dictionary) -> int:
	if not u is Unit: return 0
	var unit: Unit = u
	var id := unit.get_instance_id()
	if seen_units.has(id): return 0
	seen_units[id] = true
	var n := 0
	for k in unit.quiver:
		n += maxi(0, int(unit.quiver.get(k, 0)))
	return n

func _arrow_buckets() -> Dictionary:
	var seen_units := {}
	var b := {"company": 0, "reserve": 0, "warband_units": 0, "warband_stores": 0, "prisoners": 0, "town_armory": 0, "town_stock": 0}
	for u in Game.company:
		b["company"] += _unit_arrows(u, seen_units)
	for u2 in Mobilization.reserves(Game):
		b["reserve"] += _unit_arrows(u2, seen_units)
	for wb in Game.world.get("warbands", {}).values():
		var wbd: Dictionary = wb
		for u3 in wbd.get("units", []):
			b["warband_units"] += _unit_arrows(u3, seen_units)
		var st: Dictionary = wbd.get("stores", {})
		for ak in BowsEcon.arrow_ids():
			b["warband_stores"] += maxi(0, int(st.get(ak, 0)))
	for list2 in Prisoners.custody_lists(Game):
		for rec in list2:
			b["prisoners"] += _unit_arrows((rec as Dictionary).get("unit"), seen_units)
	for town in Game.world.get("towns", {}).values():
		var td: Dictionary = town
		b["town_armory"] += _town_arrows(td)
		if TownEcon.has_econ(td):
			var stock: Dictionary = td["econ"].get("stock", {})
			for ak2 in BowsEcon.arrow_ids():
				b["town_stock"] += maxi(0, int(stock.get(ak2, 0)))
	var total := 0
	for k in b: total += int(b[k])
	b["total"] = total
	return b

func _arrow_sum() -> int:
	return int(_arrow_buckets()["total"])

func _arrow_delta_diag(pre_b: Dictionary, post_b: Dictionary) -> String:
	var parts: Array = []
	for bk in ["company", "reserve", "warband_units", "warband_stores", "prisoners", "town_armory", "town_stock"]:
		var d := int(post_b.get(bk, 0)) - int(pre_b.get(bk, 0))
		if d != 0:
			parts.append("%s:%d->%d(%+d)" % [bk, int(pre_b.get(bk, 0)), int(post_b.get(bk, 0)), d])
	return "buckets=unchanged" if parts.is_empty() else "buckets=[%s]" % ", ".join(PackedStringArray(parts))

func _arm_prisoner(u: Unit, town: Dictionary) -> Dictionary:
	if u.equip.is_empty():
		var arm := ArmsTrade.armory(town)
		var it: Item = arm.pop_back() if not arm.is_empty() else Item.make("arming_sword", "bronze", 1)
		u.equip[it.slot()] = it
	var uids: Array = []
	var first_item: Item = null
	for slot in u.equip:
		var it = u.equip[slot]
		if it is Item:
			var item: Item = it
			if item.uid <= 0:
				item.uid = Item._next_uid
				Item._next_uid += 1
			uids.append(item.uid)
			if first_item == null: first_item = item
	if u.quiver.is_empty():
		if not town["econ"].has("armory") or not town["econ"]["armory"] is Dictionary:
			town["econ"]["armory"] = {}
		var arm_arrows: Dictionary = town["econ"]["armory"]
		var ak := str(BowsEcon.arrow_ids()[0])
		check(DB.arrows.has(ak), "armed-prisoner fixture uses a real arrow type")
		if int(arm_arrows.get(ak, 0)) < 6:
			arm_arrows[ak] = int(arm_arrows.get(ak, 0)) + 6
		arm_arrows[ak] = int(arm_arrows.get(ak, 0)) - 6
		u.quiver[ak] = 6
	var arrows := 0
	for k in u.quiver:
		arrows += maxi(0, int(u.quiver.get(k, 0)))
	return {"uids": uids, "arrows": arrows, "sample": first_item}

func _lord_unit(tid: String) -> Unit:
	var town: Dictionary = Game.world["towns"][tid]
	var e: Dictionary = town["econ"]
	e["led"] = {"made": {}, "used": {}}
	var family: Dictionary = e["fams"][0]
	var person: Array = family["pp"][0]
	var u := Unit.create(Persons.family_race(e, family), str(town["faction"]), false)
	Persons.bind(e, family, person, u, "army", 0.0)
	u.home_town = tid
	family["serve"] = {"army": 1}
	u.equip["body"] = Item.make("tunic", "linen", 0)
	var ak := str(BowsEcon.arrow_ids()[0])
	u.quiver[ak] = 7
	Army.state(Game.world)["roll"][str(u.uid)] = [tid, int(family["id"]), "army", u.name]
	return u

func _ai_realm_custody_fixture() -> void:
	Game.stash.clear()
	var native := NativeFixture.new()
	native.fixture()
	for tid in Game.world["towns"]:
		var td: Dictionary = Game.world["towns"][tid]
		var te: Dictionary = td["econ"]
		te["led"] = {"made": {}, "used": {}}
		te["biz"] = []
		var market := Businesses._row(te, "market", -1, 0, TownEcon.data())
		market["till"] = 100.0
		te["mkt"] = int(market["id"])
		te["armory"] = {}
	Game.world["towns"]["village"]["faction"] = "orc_horde"
	Game.world["towns"]["village"]["econ"]["faction"] = "orc_horde"
	Game.world["factions"]["orc_horde"] = {"capital": "village", "towns": ["village"], "treasury": 5000.0}
	Feudal.prepare_world(Game)
	Game.world.erase("player_house")
	var selected_third := Dynasty.select_city(Game, "village") and Warfare.player_faction(Game) == "orc_horde"
	var ai_lord := _lord_unit("county")
	var ai_kit_uid: int = (ai_lord.equip["body"] as Item).uid
	Game.world["towns"]["county"]["recruits"].append(ai_lord)
	Warfare._apply_siege(Game, "county", "moon_court")
	var ai_rec := Prisoners._find(Prisoners.realm_held(Game, "moon_court"), ai_lord.uid)
	check(selected_third and not ai_rec.is_empty() and Prisoners.held(Game).is_empty() and Prisoners.captives(Game).is_empty(),
		"AI-AI siege places the captured lord in realm_prisoners[moon_court] outside player lists")
	if ai_rec.is_empty(): return

	var upkeep := float(Prisoners.UPKEEP_COINS * Item.COIN)
	_set_food(Game.world["towns"]["foreign"]["econ"]["stock"], 5)
	_set_food(Game.world["towns"]["county"]["econ"]["stock"], 0)
	_set_food(Game.world["towns"]["village"]["econ"]["stock"], 4)
	var moon_tr := _treasury("moon_court")
	var foreign_till := _till(Game.world["towns"]["foreign"])
	var player_purse := _purse()
	var player_gold := float(Game.gold)
	var all_coins := _coin_sum()
	_bump()
	check(not Prisoners._find(Prisoners.realm_held(Game, "moon_court"), ai_lord.uid).is_empty()
		and int(Game.world["towns"]["foreign"]["econ"]["stock"]["grain"]) == 4
		and int(Game.world["towns"]["foreign"]["econ"]["led"]["used"].get("grain", 0)) == 1
		and is_equal_approx(_treasury("moon_court"), moon_tr - upkeep)
		and is_equal_approx(_till(Game.world["towns"]["foreign"]), foreign_till + upkeep)
		and is_equal_approx(_coin_sum(), all_coins),
		"AI realm upkeep deducts one meal and one coin from the AI holder's town stock and treasury into its market till")
	check(Prisoners.held(Game).is_empty() and Prisoners.captives(Game).is_empty() and Prisoners.offers(Game).is_empty()
		and is_equal_approx(_purse(), player_purse) and is_equal_approx(float(Game.gold), player_gold)
		and int(Game.world["towns"]["village"]["econ"]["stock"]["grain"]) == 4,
		"AI realm upkeep never enters player lists, offers, purse, gold, or town food")
	Prisoners.daily(Game, int(Game.day))
	Prisoners._upkeep_day(Game, int(Game.day))
	check(int(Game.world["towns"]["foreign"]["econ"]["stock"]["grain"]) == 4
		and is_equal_approx(_treasury("moon_court"), moon_tr - upkeep)
		and is_equal_approx(_till(Game.world["towns"]["foreign"]), foreign_till + upkeep)
		and not Prisoners._find(Prisoners.realm_held(Game, "moon_court"), ai_lord.uid).is_empty(),
		"same-day Prisoners.daily and _upkeep_day calls are idempotent for AI realm custody")

	# Capital capture fallback + canonical owner fid + dead captive skip.
	Game.world["towns"]["foreign"]["faction"] = "middle_kingdom"
	Game.world["towns"]["foreign"]["econ"]["faction"] = "middle_kingdom"
	_set_food(Game.world["towns"]["foreign"]["econ"]["stock"], 9)
	_set_food(Game.world["towns"]["county"]["econ"]["stock"], 3)
	ai_rec["held_by"] = "middle_kingdom"
	var dead_ai := Unit.create("human", "middle_kingdom", false)
	dead_ai.dead = true
	Prisoners.realm_held(Game, "moon_court").append({"uid": dead_ai.uid, "unit": dead_ai, "name": dead_ai.name,
		"faction": "middle_kingdom", "held_by": "moon_court", "home_town": "", "family": -1, "day": 0.0})
	var foreign_till2 := _till(Game.world["towns"]["foreign"])
	var county_till2 := _till(Game.world["towns"]["county"])
	var moon_tr2 := _treasury("moon_court")
	var mid_tr2 := _treasury("middle_kingdom")
	var all_coins2 := _coin_sum()
	_bump()
	check(int(Game.world["towns"]["foreign"]["econ"]["stock"]["grain"]) == 9
		and is_equal_approx(_till(Game.world["towns"]["foreign"]), foreign_till2)
		and is_equal_approx(_treasury("middle_kingdom"), mid_tr2)
		and int(Game.world["towns"]["county"]["econ"]["stock"]["grain"]) == 2
		and is_equal_approx(_till(Game.world["towns"]["county"]), county_till2 + upkeep)
		and is_equal_approx(_treasury("moon_court"), moon_tr2 - upkeep)
		and is_equal_approx(_coin_sum(), all_coins2)
		and Prisoners._find(Prisoners.realm_held(Game, "moon_court"), dead_ai.uid).is_empty(),
		"after capital capture, canonical AI holder falls back to its own county without stealing enemy food and skips dead captives")
	ai_rec["held_by"] = "moon_court"

	# Lack of coin or lack of food releases the AI captive via release_realm (not the player's prisoner) and returns body/person/kit once.
	var player_foe := _lord_unit("seat")
	Prisoners.held(Game).append({"uid": player_foe.uid, "name": player_foe.name, "faction": "middle_kingdom",
		"home_town": "seat", "family": player_foe.family, "day": float(Game.day), "unit": player_foe,
		"role": "army", "hold_town": "village", "hold_band": ""})
	_set_food(Game.world["towns"]["village"]["econ"]["stock"], 5)
	Feudal._payer(Game)["purse"] = 500.0 * Item.COIN
	_set_food(Game.world["towns"]["county"]["econ"]["stock"], 3)
	Game.world["factions"]["moon_court"]["treasury"] = 0.0
	var no_coin_feed := Prisoners._can_feed(Prisoners._keeper(Game, ai_rec, false, "moon_court"))
	_set_food(Game.world["towns"]["county"]["econ"]["stock"], 0)
	Game.world["factions"]["moon_court"]["treasury"] = 500.0 * Item.COIN
	var no_food_feed := Prisoners._can_feed(Prisoners._keeper(Game, ai_rec, false, "moon_court"))
	var items_pre_rel := _accounted_items()
	var arrows_pre_rel := _arrow_sum()
	var coins_pre_rel := _coin_sum()
	var county_till_pre := _till(Game.world["towns"]["county"])
	var moon_tr_pre := _treasury("moon_court")
	_bump()
	var county_town: Dictionary = Game.world["towns"]["county"]
	var county_fam: Dictionary = county_town["econ"]["fams"][0]
	var county_person: Array = Persons.by_pid(county_fam, 0)
	var items_post_rel := _accounted_items()
	check(not no_coin_feed and not no_food_feed
		and Prisoners.realm_held(Game, "moon_court").is_empty()
		and not Prisoners._find(Prisoners.held(Game), player_foe.uid).is_empty()
		and is_equal_approx(_treasury("moon_court"), moon_tr_pre)
		and is_equal_approx(_till(county_town), county_till_pre)
		and is_equal_approx(_coin_sum(), coins_pre_rel),
		"lack of food or coin releases the AI realm's captive while keeping the player's fed prisoner and conserving coin")
	check(not ai_lord.dead and not Army.state(Game.world)["roll"].has(str(ai_lord.uid))
		and str(county_person[4]) == "" and int(county_person[5]) == -1
		and int(county_fam.get("serve", {}).get("army", 0)) == 0 and int(county_town["econ"]["pop"]) == 1
		and ai_lord.equip.is_empty() and ai_lord.quiver.is_empty()
		and _town_has_uid(county_town, ai_kit_uid) and _town_arrows(county_town) == 7
		and int(items_post_rel["count"]) == int(items_pre_rel["count"])
		and int(items_post_rel["uids"].get(ai_kit_uid, 0)) == 1
		and _arrow_sum() == arrows_pre_rel,
		"unfed AI realm release returns the captive's army roll, person record, exact kit UID, and quiver arrows to home town once")

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	var ver := str(ProjectSettings.get_setting("application/config/version"))
	var ver_parts := ver.split(".")
	var ver_num := int(ver_parts[0]) * 1000 + int(ver_parts[1]) if ver_parts.size() >= 2 else 0
	check(ver_num >= 77, "project version is at least 0.077 (%s)" % ver)
	if not await DevTools.start_world(tree, "user://ransom077-test.json"):
		check(false, "the shared test world loads")
		return _finish()
	var seat := DevTools.choose_house(Game)
	check(seat != "", "selected a native ruling house")
	if seat == "": return _finish()
	DevTools.stand_at(Game, seat)
	Feudal._payer(Game)["purse"] = 1000.0 * Item.COIN
	check(DevTools.raise_army(Game, seat, 12) >= 3, "raised registered soldiers (%d in the company)" % Game.company.size())
	var mine := Diplomacy.player_realm(Game.world)
	for key in Game.world["warbands"]:
		var band: Dictionary = Game.world["warbands"][key]
		if str(band.get("faction", "")) == mine or not Army.is_people_band(band) or Monsters.suspended_band(band): continue
		if str(band.get("kind", "")) in ["caravan", "militia"]: continue
		var reg: Array = []
		for u in band["units"]:
			if u is Unit and u.family >= 0 and not _person(u).is_empty() and Army.state(Game.world)["roll"].has(str(u.uid)):
				reg.append(u)
		if reg.size() >= 4:
			_band_id = str(key)
			_enemy = str(band.get("faction", ""))
			_pool = reg
			break
	check(_band_id != "" and _pool.size() >= 4, "an enemy field band with at least 4 registered soldiers (%d)" % _pool.size())
	if _band_id == "" or _pool.size() < 4: return _finish()
	var seat_town: Dictionary = Prisoners._player_town(Game)
	check(not seat_town.is_empty() and Prisoners._market_till(seat_town).size() > 0, "the player's town has a market till")
	if Prisoners._market_till(seat_town).is_empty(): return _finish()
	var kit_by_unit := {}
	for cand in [_pool[0], _pool[1], _pool[2]]:
		var cuids: Array = []
		for slot in (cand as Unit).equip:
			var cit = (cand as Unit).equip[slot]
			if cit is Item and (cit as Item).uid > 0:
				cuids.append((cit as Item).uid)
		kit_by_unit[(cand as Unit).uid] = {"town": str((cand as Unit).home_town), "uids": cuids}

	# --- Capture. Two of theirs, one of ours. Records name where they are held.
	check(_take_foes([_pool[0], _pool[1]]), "two downed enemy soldiers are taken prisoner")
	var ours: Unit = _take_one_of_ours()
	check(ours != null, "one of our downed soldiers is taken prisoner")
	if ours == null: return _finish()
	var rec0: Dictionary = Prisoners._find(Prisoners.held(Game), _pool[0].uid)
	var cap0: Dictionary = Prisoners._find(Prisoners.captives(Game), ours.uid)
	check(str(rec0.get("hold_town", "")) != "" and str(rec0.get("hold_band", "")) == "", "a prisoner you hold is fed from your town, not from a band")
	check(str(cap0.get("hold_band", "")) == _band_id and str(cap0.get("held_by", "")) == _enemy, "a captive records the enemy band that holds them")

	# --- One day: your two are fed from the town; theirs is released because their stores are empty.
	for town in Game.world["towns"].values():
		if str(town.get("faction", "")) == _enemy: _zero_town_food(town)
	_zero_band_food(_enemy)
	var fed_town := _stock_player(5, 80)
	var purse := _purse()
	var till := _till(fed_town)
	var treasury := _treasury(_enemy)
	var grain := int(fed_town["econ"]["stock"]["grain"])
	var coins := _coin_sum()
	var upkeep := float(Prisoners.UPKEEP_COINS * Item.COIN)
	_bump()
	check(Prisoners.captives(Game).is_empty() and Prisoners.held(Game).size() == 2, "the unfed captive is released and your two prisoners stay")
	check(int(fed_town["econ"]["stock"]["grain"]) == grain - 2, "two meals leave the holding town's grain")
	check(is_equal_approx(_purse(), purse - 2.0 * upkeep) and is_equal_approx(_till(fed_town), till + 2.0 * upkeep), "two coins move from your purse into that town's market")
	check(is_equal_approx(_treasury(_enemy), treasury), "an empty enemy store pays nothing")
	check(is_equal_approx(_coin_sum(), coins), "feeding creates no coin")
	var up: Dictionary = Prisoners.state(Game).get("upkeep", {})
	check(int(up.get("fed", -1)) == 2 and int(up.get("released", -1)) == 1 and int(up.get("day", -2)) == int(Game.day), "the day records who was fed and who was released")

	# --- They decline a ransom they cannot pay, then pay the dearer of the two once the hold is old enough.
	_zero_houses([_pool[0], _pool[1]])
	Game.world["factions"][_enemy]["treasury"] = 0.0
	purse = _purse()
	var broke := Prisoners.preview(Game, "ransom", _pool[0].uid)
	check(not broke.get("ok", false) and str(broke.get("text", "")).contains("They decline."), "a realm with no coin declines: " + str(broke.get("text", "")))
	check(is_equal_approx(_purse(), purse) and Prisoners.held(Game).size() == 2, "a declined ransom changes nothing")
	_stock_player(20, 400)
	_stock_enemy(30, 5000)
	_zero_houses([_pool[0], _pool[1]])
	rec0 = Prisoners._find(Prisoners.held(Game), _pool[0].uid)
	var rec1: Dictionary = Prisoners._find(Prisoners.held(Game), _pool[1].uid)
	rec0["noble"] = true
	rec1["noble"] = false
	rec1["household"] = false
	var price0 := Prisoners.price(Game, rec0)
	var price1 := Prisoners.price(Game, rec1)
	_age(rec0); _age(rec1)
	var offered := Prisoners.preview(Game, "ransom", _pool[0].uid if price0 >= price1 else _pool[1].uid)
	check(offered.get("ok", false) and str(offered.get("text", "")).contains("They accept."), "a realm that can pay accepts: " + str(offered.get("text", "")))
	purse = _purse(); coins = _coin_sum(); grain = int(fed_town["econ"]["stock"]["grain"])
	var treasury_r := _treasury(_enemy)
	var house_r := {_pool[0].uid: _house_purse(_pool[0]), _pool[1].uid: _house_purse(_pool[1])}
	var standing := Diplomacy.earned(Game, _enemy)
	_bump()
	check(Prisoners.held(Game).size() == 1, "the realm ransoms one prisoner, the dearest it can pay")
	var left: Array = Prisoners.held(Game)
	if left.size() != 1: return _finish()
	var left_uid := int(left[0]["uid"])
	var gone_uid: int = int(_pool[1].uid) if left_uid == int(_pool[0].uid) else int(_pool[0].uid)
	var gone_price: int = price1 if gone_uid == int(_pool[1].uid) else price0
	_ransomed = _pool[1] if gone_uid == _pool[1].uid else _pool[0]
	if price0 != price1: check(gone_price == maxi(price0, price1), "they ransom the dearer kin, not the cheaper one")
	check(is_equal_approx(_purse(), purse - 2.0 * upkeep + float(gone_price)), "your purse gains the ransom and pays two coins of upkeep")
	# Account by account: the ransomed man's walk home may fence his kit (ArmsSalvage.kit_home moves the home town's
	# treasury into his house purse), so a house purse can rise; it is never where an untaken ransom hides.
	var t_paid := treasury_r - _treasury(_enemy)
	var h_paid := float(house_r[gone_uid]) - _house_purse(_ransomed)
	check((is_equal_approx(t_paid, float(gone_price)) and h_paid <= 0.001) or (is_equal_approx(h_paid, float(gone_price)) and is_zero_approx(t_paid)),
		"the ransom leaves their house purse or their treasury (treasury paid %.2f, house paid %.2f, price %d)" % [t_paid, h_paid, gone_price])
	check(int(fed_town["econ"]["stock"]["grain"]) == grain - 2, "both prisoners were fed before the ransom")
	check(is_equal_approx(_coin_sum(), coins), "the ransom moves coin and does not mint it")
	check(Diplomacy.earned(Game, _enemy) == mini(100, standing + Diplomacy.RANSOM), "their ransom improves standing")

	# --- Execute the one they did not buy. Further heads the same day stop changing standing at the cap.
	var stay: Unit = _pool[0] if left_uid == _pool[0].uid else _pool[1]
	var stay_rec: Dictionary = Prisoners._find(Prisoners.held(Game), stay.uid)
	var stay_fam: Dictionary = Prisoners._address(Game, stay_rec).get("family", {})
	var exec_kit := _arm_prisoner(stay, seat_town)
	var items_before_exec := _accounted_items()
	var arrows_before_exec := _arrow_sum()
	var town_arrows_before_exec := _town_arrows(seat_town)
	check(not (exec_kit["uids"] as Array).is_empty() and int(exec_kit["arrows"]) > 0, "the prisoner to execute carries armed kit and a quiver")
	coins = _coin_sum()
	standing = Diplomacy.earned(Game, _enemy)
	var executed := Prisoners.preview(Game, "execute", stay.uid)
	check(executed.get("ok", false), "execute can be reviewed")
	check(Prisoners.confirm(Game, "execute", stay.uid, -1, executed.get("review", {})).get("ok", false), "execute is confirmed")
	check(Prisoners.held(Game).is_empty() and stay.dead, "the executed prisoner is dead and off the list")
	check(stay.equip.is_empty() and stay.quiver.is_empty(), "execution strips kit and quiver from the dead prisoner")
	if exec_kit["sample"] is Item:
		stay.equip["main_hand"] = exec_kit["sample"]
		Prisoners._settle_kit(Game, stay_rec, stay, true, "executed in captivity")
	var items_after_exec := _accounted_items()
	var exec_kept := true
	for uid in exec_kit["uids"]:
		if not _town_has_uid(seat_town, int(uid)) or int(items_after_exec["uids"].get(int(uid), 0)) != 1:
			exec_kept = false
	check(exec_kept and int(items_after_exec["count"]) == int(items_before_exec["count"]),
		"execution settles the exact kit into the holding town without losing or duplicating items")
	check(_town_arrows(seat_town) == town_arrows_before_exec + int(exec_kit["arrows"]) and _arrow_sum() == arrows_before_exec,
		"execution settles the prisoner's quiver into the holding town's armory")
	check(not Army.state(Game.world)["roll"].has(str(stay.uid)), "execution takes them off their realm's roll")
	check(Diplomacy.earned(Game, _enemy) == maxi(-100, standing + Diplomacy.EXECUTE_PER_HEAD), "one execution costs one point of standing")
	check(is_equal_approx(_coin_sum(), coins), "execution moves no coin")
	if not stay_fam.is_empty(): check(str(stay_fam.get("hist", [])).contains("executed in captivity"), "the family is told they were executed")
	var capped := Diplomacy.earned(Game, _enemy)
	if capped >= -90:
		for _i in 9:
			Prisoners._standing_execute(Game, _enemy, 1)
		check(Diplomacy.earned(Game, _enemy) == capped + 9 * Diplomacy.EXECUTE_PER_HEAD, "nine more heads still count, up to the day's cap")
		Prisoners._standing_execute(Game, _enemy, 1)
		check(Diplomacy.earned(Game, _enemy) == capped + 9 * Diplomacy.EXECUTE_PER_HEAD, "an eleventh head the same day does not move standing again")

	# --- They demand a ransom. Declining keeps the captive. A short purse is declined. Paying moves their treasury.
	if not Prisoners.held(Game).is_empty(): return _finish()
	var demanded: Unit = _take_one_of_ours()
	check(demanded != null, "a second soldier of ours can be captured for a demand")
	if demanded == null: return _finish()
	var enemy_town := _stock_enemy(20, 5000)
	check(not enemy_town.is_empty() and not Prisoners._market_till(enemy_town).is_empty(), "the captor's town has food and a market till")
	if enemy_town.is_empty() or Prisoners._market_till(enemy_town).is_empty(): return _finish()
	var demand_rec: Dictionary = Prisoners._find(Prisoners.captives(Game), demanded.uid)
	_age(demand_rec)
	_stock_player(10, 500)
	purse = _purse(); treasury = _treasury(_enemy); coins = _coin_sum()
	var enemy_grain := int(enemy_town["econ"]["stock"]["grain"])
	_bump()
	var offers: Array = Prisoners.offers(Game).filter(func(o): return str(o.get("kind", "")) == "demand" and int(o.get("uid", -1)) == demanded.uid)
	check(offers.size() == 1 and Prisoners._find(Prisoners.captives(Game), demanded.uid).size() > 0, "they demand a ransom and still hold your soldier")
	check(is_equal_approx(_purse(), purse), "a demand does not take your purse")
	check(is_equal_approx(_treasury(_enemy), treasury - upkeep) and int(enemy_town["econ"]["stock"]["grain"]) == enemy_grain - 1, "their upkeep is one coin and one meal")
	check(is_equal_approx(_coin_sum(), coins), "their upkeep moves coin into the town")
	var declined := Prisoners.decline(Game, demanded.uid, "demand")
	check(declined.get("ok", false) and Prisoners.offers(Game).filter(func(o): return int(o.get("uid", -1)) == demanded.uid).is_empty(), "declining removes the demand")
	check(not Prisoners._find(Prisoners.captives(Game), demanded.uid).is_empty() and is_equal_approx(_purse(), purse), "declining leaves the captive and the purse")
	var demand_price := Prisoners.price(Game, Prisoners._find(Prisoners.captives(Game), demanded.uid))
	Feudal._payer(Game)["purse"] = float(demand_price - 1)
	var short := Prisoners.preview(Game, "pay", demanded.uid)
	check(not short.get("ok", false) and str(short.get("text", "")).contains("They decline."), "a short purse is declined")
	Feudal._payer(Game)["purse"] = float(demand_price + 50 * Item.COIN)
	purse = _purse(); treasury = _treasury(_enemy); coins = _coin_sum()
	var pay := Prisoners.preview(Game, "pay", demanded.uid)
	check(pay.get("ok", false) and str(pay.get("text", "")).contains("They accept."), "they accept a ransom you can pay")
	check(Prisoners.confirm(Game, "pay", demanded.uid, -1, pay.get("review", {})).get("ok", false), "the ransom is paid")
	check(Prisoners.captives(Game).is_empty(), "your soldier comes home")
	check(is_equal_approx(_purse(), purse - float(demand_price)) and is_equal_approx(_treasury(_enemy), treasury + float(demand_price)), "the ransom moves from your purse to their treasury")
	check(is_equal_approx(_coin_sum(), coins), "paying the demand mints nothing")

	# --- No meal and no coin: the prisoner goes free, and nothing is invented to keep them.
	check(_take_foes([_pool[2]]), "a third enemy soldier is taken")
	_zero_town_food(fed_town)
	Feudal._payer(Game)["purse"] = 0.0
	till = _till(fed_town); coins = _coin_sum(); treasury = _treasury(_enemy)
	_bump()
	check(Prisoners.held(Game).is_empty(), "a prisoner is released when the captor has neither food nor coin")
	check(int(fed_town["econ"]["stock"].get("grain", 0)) == 0 and is_equal_approx(_purse(), 0.0), "the empty stores stay empty")
	check(is_equal_approx(_till(fed_town), till) and is_equal_approx(_treasury(_enemy), treasury) and is_equal_approx(_coin_sum(), coins), "a release for hunger moves no coin")
	check(str(Prisoners.state(Game)["log"][-1]["text"]).contains("Stores ran out"), "the release is logged")

	# --- Sale. No buyer, nothing moves. A realm that can pay does, and slavery's opponents lose standing.
	check(_take_foes([_pool[3]]), "a fourth enemy soldier is taken")
	var oppose: Array = Diplomacy.data().get("opposes_slavery", [])
	var buyer := ""
	for fid in Game.world["factions"]:
		var id := str(fid)
		if id == "" or id == _enemy or id == mine or oppose.has(id): continue
		buyer = id
		Game.world["factions"][id]["treasury"] = 0.0
	check(buyer != "", "some realm other than the prisoner's, yours, and the slavery opposition can be the buyer")
	if buyer == "": return _finish()
	purse = _purse(); coins = _coin_sum()
	var no_sale := Prisoners.preview(Game, "sell", _pool[3].uid)
	check(not no_sale.get("ok", false), "with no realm able to pay, the sale is refused: " + str(no_sale.get("text", "")))
	check(is_equal_approx(_purse(), purse) and is_equal_approx(_coin_sum(), coins) and not Prisoners._find(Prisoners.held(Game), _pool[3].uid).is_empty(), "a refused sale changes nothing")
	var top := 0.0
	for fid2 in Game.world["factions"]:
		top = maxf(top, float(Game.world["factions"][fid2].get("treasury", 0.0)))
	Game.world["factions"][buyer]["treasury"] = top + float(1000 * Item.COIN)
	var sale_price := Prisoners.SALE_COINS * Item.COIN
	var before_opp := {}
	for f in oppose: before_opp[str(f)] = Diplomacy.earned(Game, str(f))
	var sale_rec: Dictionary = Prisoners._find(Prisoners.held(Game), _pool[3].uid)
	var sale_fam: Dictionary = Prisoners._address(Game, sale_rec).get("family", {})
	var sale_econ: Dictionary = Prisoners._address(Game, sale_rec).get("econ", {})
	var sale_book: Dictionary = Census._book(sale_econ) if not sale_econ.is_empty() else {}
	var sold_left := int(sale_book.get("cur", {}).get("left", {}).get("sold to slavers", 0)) if not sale_book.is_empty() else 0
	var deaths_before := Census.sum(sale_book.get("cur", {}).get("deaths", {})) + Census.sum(sale_book.get("cur", {}).get("away", {})) if not sale_book.is_empty() else 0
	var pop_before := int(sale_econ.get("pop", 0))
	var sale_kit := _arm_prisoner(_pool[3], seat_town)
	var items_before_sale := _accounted_items()
	var arrows_before_sale := _arrow_sum()
	var town_arrows_before_sale := _town_arrows(seat_town)
	check(not (sale_kit["uids"] as Array).is_empty() and int(sale_kit["arrows"]) > 0, "the prisoner to sell carries armed kit and a quiver")
	purse = _purse(); var buyer_coin := _treasury(buyer); coins = _coin_sum()
	var sale := Prisoners.preview(Game, "sell", _pool[3].uid)
	check(sale.get("ok", false) and int(sale.get("price", 0)) == sale_price, "the sale price is the small fixed price")
	check(Prisoners.confirm(Game, "sell", _pool[3].uid, -1, sale.get("review", {})).get("ok", false), "the sale is confirmed")
	check(Prisoners._find(Prisoners.held(Game), _pool[3].uid).is_empty() and _pool[3].dead, "the sold prisoner is dead and off the list")
	check(_pool[3].equip.is_empty() and _pool[3].quiver.is_empty(), "sale settles kit and quiver off the retired prisoner")
	if sale_kit["sample"] is Item:
		_pool[3].equip["main_hand"] = sale_kit["sample"]
		Prisoners._settle_kit(Game, sale_rec, _pool[3], true, "sold to slavers")
	var items_after_sale := _accounted_items()
	var sale_kept := true
	for uid2 in sale_kit["uids"]:
		if not _town_has_uid(seat_town, int(uid2)) or int(items_after_sale["uids"].get(int(uid2), 0)) != 1:
			sale_kept = false
	check(sale_kept and int(items_after_sale["count"]) == int(items_before_sale["count"]),
		"sale settles the exact kit into the holding town without losing or duplicating items")
	check(_town_arrows(seat_town) == town_arrows_before_sale + int(sale_kit["arrows"]) and _arrow_sum() == arrows_before_sale,
		"sale settles the prisoner's quiver into the holding town's armory")
	check(is_equal_approx(_purse(), purse + float(sale_price)) and is_equal_approx(_treasury(buyer), buyer_coin - float(sale_price)), "the buyer's treasury pays your purse")
	check(is_equal_approx(_coin_sum(), coins), "the sale mints nothing")
	for f2 in oppose:
		check(Diplomacy.earned(Game, str(f2)) == maxi(-100, int(before_opp[str(f2)]) + Diplomacy.SLAVERS_PER_HEAD), "selling costs %s %d standing" % [str(f2), Diplomacy.SLAVERS_PER_HEAD])
	if not sale_fam.is_empty(): check(str(sale_fam.get("hist", [])).contains("sold to slavers"), "the family is told they were sold")
	if not sale_book.is_empty():
		var cur: Dictionary = sale_book["cur"]
		var dropped := pop_before - int(sale_econ.get("pop", 0))
		check(int(cur.get("left", {}).get("sold to slavers", 0)) == sold_left + dropped and dropped in [0, 1],
			"the census books the sold prisoner as one who left (town count fell by %d)" % dropped)
		check(Census.sum(cur.get("deaths", {})) + Census.sum(cur.get("away", {})) == deaths_before, "the census books no death for a sale")

	# --- One for one, once both have been held long enough. Upkeep still moves, the trade itself does not.
	check(_ransomed != null and not _ransomed.dead, "the ransomed soldier is alive and can be held again")
	if _ransomed == null or _ransomed.dead: return _finish()
	var traded: Unit = _take_one_of_ours()
	check(traded != null, "a third soldier of ours can be captured for an exchange")
	if traded == null: return _finish()
	var again := {"uid": _ransomed.uid, "name": _ransomed.name, "faction": _enemy, "home_town": _ransomed.home_town,
		"family": _ransomed.family, "day": float(Game.day), "unit": _ransomed, "role": "army", "noble": true, "household": false,
		"hold_town": str(seat_town.get("id", seat)), "hold_band": ""}
	Prisoners.held(Game).append(again)
	var their_price := Prisoners.price(Game, again)
	var our_price := Prisoners.price(Game, Prisoners._find(Prisoners.captives(Game), traded.uid))
	check(their_price >= our_price, "the exchange is fair (%d for %d)" % [their_price, our_price])
	if their_price < our_price: return _finish()
	_stock_player(12, 200)
	enemy_town = _stock_enemy(12, 4000)
	_zero_houses([_ransomed])
	_age(again)
	_age(Prisoners._find(Prisoners.captives(Game), traded.uid))
	purse = _purse(); treasury = _treasury(_enemy); coins = _coin_sum()
	_bump()
	check(Prisoners._find(Prisoners.held(Game), _ransomed.uid).is_empty() and Prisoners._find(Prisoners.captives(Game), traded.uid).is_empty(), "the exchange frees one on each side")
	check(is_equal_approx(_purse(), purse - upkeep), "the exchange itself adds no ransom to your purse")
	check(is_equal_approx(_treasury(_enemy), treasury - upkeep), "their treasury pays upkeep and not a second ransom")
	check(is_equal_approx(_coin_sum(), coins), "the exchange mints nothing")
	var tail := ""
	var log: Array = Prisoners.state(Game)["log"]
	for entry in log.slice(maxi(0, log.size() - 3)):
		tail += str(entry.get("text", "")) + " "
	check(tail.contains("Exchanged"), "the exchange is logged: " + tail)

	# --- A dead prisoner is not fed. The death line stays last, and no coin moves.
	var dead_u: Unit = null
	for u in Game.company:
		if u is Unit and not (u as Unit).dead:
			dead_u = u
			break
	check(dead_u != null, "someone remains to record a death in custody")
	if dead_u != null:
		dead_u.dead = true
		Prisoners.held(Game).clear()
		Prisoners.captives(Game).clear()
		Prisoners.held(Game).append({"uid": dead_u.uid, "unit": dead_u, "name": dead_u.name, "faction": _enemy,
			"home_town": dead_u.home_town, "family": dead_u.family, "day": 0.0})
		coins = _coin_sum()
		_bump()
		check(Prisoners.held(Game).is_empty(), "a prisoner who died is dropped")
		check(str(Prisoners.state(Game)["log"][-1]["text"]).contains("died in captivity"), "the death line is the last line")
		check(is_equal_approx(_coin_sum(), coins), "a death day moves no coin")

	# --- A captive already marked dead in the register is not released for hunger and is not fed.
	var marked: Unit = null
	for u2 in Game.company:
		if u2 is Unit and not (u2 as Unit).dead and _person(u2).size() > 4 and u2 != dead_u:
			marked = u2
			break
	if marked != null:
		var row: Array = _person(marked)
		row[4] = "dead"
		Prisoners.held(Game).clear()
		Prisoners.captives(Game).clear()
		Prisoners.captives(Game).append({"uid": marked.uid, "unit": marked, "name": marked.name, "home_town": marked.home_town,
			"family": marked.family, "held_by": "", "day": float(Game.day)})
		coins = _coin_sum()
		_bump()
		check(Prisoners.captives(Game).is_empty(), "a captive already dead in the register leaves the list")
		check(str(row[4]) == "dead", "hunger does not bring that captive home")
		check(is_equal_approx(_coin_sum(), coins), "that day moves no coin")
	# Reload only after every scenario using live Unit/household references has finished.
	var home_tid := str(kit_by_unit[_ransomed.uid]["town"])
	var home_town: Dictionary = Game.world["towns"].get(home_tid, {})
	ArmsTrade.refresh_reserve(Game, home_town)
	var home_tgt := 0
	for c in home_town["econ"].get("arms_tgt", {}): home_tgt += int(home_town["econ"]["arms_tgt"][c])
	var home_keep_n := maxi(home_tgt, TownDefence.militia_cap(home_town) * 4)
	var pre_home_uids: Array = []
	for hit in ArmsTrade.armory(home_town):
		if hit is Item: pre_home_uids.append((hit as Item).uid)
	var pre_home_scrap := 0
	for sk in home_town["econ"].get("stock", {}):
		if str(sk).begins_with("scrap_"): pre_home_scrap += int(home_town["econ"]["stock"][sk])
	var pre_save_items := _accounted_items()
	var pre_arrow_buckets := _arrow_buckets()
	var pre_save_arrows := int(pre_arrow_buckets["total"])
	var pre_save_coins := _coin_sum()
	Game.save_game(); Game.wait_save()
	var saved_env = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	check(saved_env is Dictionary and int((saved_env as Dictionary).get("version", 0)) == 1 and int((saved_env as Dictionary).get("militia_cap", 0)) == 1,
		"saved-envelope root metadata records version 1 and explicit militia_cap: 1")
	Game.world = {}; Game.rep = {}
	check(Game.load_game(), "real save reloads after execute and sell")
	seat_town = Prisoners._player_town(Game)
	fed_town = seat_town
	var post_load_items := _accounted_items()
	var post_arrow_buckets := _arrow_buckets()
	var post_load_arrows := int(post_arrow_buckets["total"])
	check(int(post_load_items["count"]) == int(pre_save_items["count"]) and post_load_arrows == pre_save_arrows,
		"save/load preserves total accounted items (%d -> %d, delta %+d; %s) and arrows (%d -> %d, delta %+d; %s)" % [
			int(pre_save_items["count"]), int(post_load_items["count"]), int(post_load_items["count"]) - int(pre_save_items["count"]),
			_item_delta_diag(pre_save_items, post_load_items),
			pre_save_arrows, post_load_arrows, post_load_arrows - pre_save_arrows,
			_arrow_delta_diag(pre_arrow_buckets, post_arrow_buckets)])
	var loaded_kit_ok := true
	for uid3 in (exec_kit["uids"] as Array) + (sale_kit["uids"] as Array):
		if not _town_has_uid(seat_town, int(uid3)) or int(post_load_items["uids"].get(int(uid3), 0)) != 1:
			loaded_kit_ok = false
	check(loaded_kit_ok, "executed and sold prisoners' exact Item uids survive save/load in the holding town")
	var loaded_home_town: Dictionary = Game.world["towns"].get(home_tid, {})
	var post_home_scrap := 0
	for sk2 in loaded_home_town.get("econ", {}).get("stock", {}):
		if str(sk2).begins_with("scrap_"): post_home_scrap += int(loaded_home_town["econ"]["stock"][sk2])
	var above_cap_ok := pre_home_uids.size() > home_keep_n and ArmsTrade.armory(loaded_home_town).size() == pre_home_uids.size() and post_home_scrap == pre_home_scrap
	for cand2 in [_ransomed, _pool[2]]:
		var c_tid := str(kit_by_unit[cand2.uid]["town"])
		var c_town: Dictionary = Game.world["towns"].get(c_tid, {})
		for ruid in kit_by_unit[cand2.uid]["uids"]:
			if not _town_has_uid(c_town, int(ruid)) or int(post_load_items["uids"].get(int(ruid), 0)) != 1:
				above_cap_ok = false
	for huid in pre_home_uids:
		if not _town_has_uid(loaded_home_town, int(huid)) or int(post_load_items["uids"].get(int(huid), 0)) != 1:
			above_cap_ok = false
	check(above_cap_ok, "above-cap town armory (%s: %d > %d keep_n) preserves returned prisoner kit UIDs and scrap on load" % [
		home_tid, ArmsTrade.armory(loaded_home_town).size(), home_keep_n])
	check(Prisoners._find(Prisoners.held(Game), stay.uid).is_empty() and Prisoners._find(Prisoners.held(Game), _pool[3].uid).is_empty(),
		"executed and sold prisoners stay off the held list after save/load")
	check(is_equal_approx(_coin_sum(), pre_save_coins), "save/load preserves total world coin")

	# Unmarked legacy envelope (missing militia_cap) still migrates oversized militia despite unrelated world tables, without melting armory items.
	var home_cap := TownDefence.militia_cap(loaded_home_town)
	var home_wb := Militia.band_of(Game, home_tid)
	var extra_u: Unit = null
	for _i in 8:
		if (home_wb.get("units", []) as Array).size() > home_cap: break
		var cand_u := Militia.make_unit(loaded_home_town, Game.rng, false)
		if cand_u.family < 0: continue
		cand_u.quiver.clear()
		(home_wb["units"] as Array).append(cand_u)
		extra_u = cand_u
	home_wb["n0"] = (home_wb.get("units", []) as Array).size()
	var extra_kit_uids: Array = []
	if extra_u != null:
		for slot2 in extra_u.equip:
			var eit = extra_u.equip[slot2]
			if eit is Item and (eit as Item).uid > 0:
				extra_kit_uids.append((eit as Item).uid)
	var pre_legacy_items := _accounted_items()
	var legacy_env := Game._save_tree()
	legacy_env.erase("militia_cap")
	var legacy_world: Dictionary = legacy_env.get("world", {})
	var unrelated_tables_present := legacy_world.has("creatures_enabled") and legacy_world.has("ransom") and legacy_world.has("migration") and legacy_world.has("intrigue")
	var legacy_write := Game._write_save(Game.SAVE_PATH, legacy_env)
	Game.world = {}; Game.rep = {}
	var legacy_loaded := Game.load_game()
	var post_legacy_wb := Militia.band_of(Game, home_tid)
	var post_legacy_town: Dictionary = Game.world["towns"].get(home_tid, {})
	var post_legacy_items := _accounted_items()
	var post_legacy_scrap := 0
	for sk3 in post_legacy_town.get("econ", {}).get("stock", {}):
		if str(sk3).begins_with("scrap_"): post_legacy_scrap += int(post_legacy_town["econ"]["stock"][sk3])
	var legacy_kit_kept := not extra_kit_uids.is_empty()
	for huid2 in pre_home_uids + extra_kit_uids:
		if not _town_has_uid(post_legacy_town, int(huid2)) or int(post_legacy_items["uids"].get(int(huid2), 0)) != 1:
			legacy_kit_kept = false
	check(unrelated_tables_present and not legacy_env.has("militia_cap") and bool(legacy_write.get("ok", false)) and legacy_loaded
		and extra_u != null and (post_legacy_wb.get("units", []) as Array).size() == home_cap
		and int(post_legacy_items["count"]) == int(pre_legacy_items["count"])
		and legacy_kit_kept and post_legacy_scrap == pre_home_scrap,
		"unmarked legacy envelope migrates oversized militia (%d -> %d) despite unrelated world tables while keeping exact armory gear (%d -> %d)" % [
			home_cap + 1, (post_legacy_wb.get("units", []) as Array).size(),
			int(pre_legacy_items["count"]), int(post_legacy_items["count"])])

	_ai_realm_custody_fixture()
	return _finish()
