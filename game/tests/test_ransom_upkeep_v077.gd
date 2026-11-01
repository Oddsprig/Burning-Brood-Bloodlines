extends RefCounted
## v0.077: prisoner upkeep and AI ransom on a real generated world. Battles use the live capture path.
## Later days call Prisoners.daily directly, so only this feature moves coin. Godot is not run from the
## work that wrote this file.
## Run: godot --path game --headless res://tests/runner.tscn -- --test=res://tests/test_ransom_upkeep_v077.gd
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

func _count_item(it, uids: Dictionary) -> int:
	if not it is Item: return 0
	var item: Item = it
	if item.uid > 0:
		uids[item.uid] = int(uids.get(item.uid, 0)) + 1
	return 1

func _count_unit_items(u, seen_units: Dictionary, uids: Dictionary) -> int:
	if not u is Unit: return 0
	var unit: Unit = u
	var id := unit.get_instance_id()
	if seen_units.has(id): return 0
	seen_units[id] = true
	var n := 0
	for slot in unit.equip:
		n += _count_item(unit.equip[slot], uids)
	return n

func _accounted_items() -> Dictionary:
	var uids := {}
	var seen_units := {}
	var n := 0
	for it in Game.stash:
		n += _count_item(it, uids)
	for u in Game.company:
		n += _count_unit_items(u, seen_units, uids)
	for u2 in Mobilization.reserves(Game):
		n += _count_unit_items(u2, seen_units, uids)
	for wb in Game.world.get("warbands", {}).values():
		for u3 in (wb as Dictionary).get("units", []):
			n += _count_unit_items(u3, seen_units, uids)
	for rec in Prisoners.held(Game) + Prisoners.captives(Game):
		n += _count_unit_items((rec as Dictionary).get("unit"), seen_units, uids)
	for town in Game.world.get("towns", {}).values():
		var td: Dictionary = town
		for it2 in td.get("shop", []):
			n += _count_item(it2, uids)
		for it3 in ArmsTrade.armory(td):
			n += _count_item(it3, uids)
	for lair in Game.world.get("lairs", {}).values():
		for it4 in (lair as Dictionary).get("stock", []):
			n += _count_item(it4, uids)
	return {"count": n, "uids": uids}

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

func _arrow_sum() -> int:
	var seen_units := {}
	var n := 0
	for u in Game.company:
		n += _unit_arrows(u, seen_units)
	for u2 in Mobilization.reserves(Game):
		n += _unit_arrows(u2, seen_units)
	for wb in Game.world.get("warbands", {}).values():
		var wbd: Dictionary = wb
		for u3 in wbd.get("units", []):
			n += _unit_arrows(u3, seen_units)
		var st: Dictionary = wbd.get("stores", {})
		for ak in BowsEcon.ARROWS:
			n += maxi(0, int(st.get(ak, 0)))
	for rec in Prisoners.held(Game) + Prisoners.captives(Game):
		n += _unit_arrows((rec as Dictionary).get("unit"), seen_units)
	for town in Game.world.get("towns", {}).values():
		var td: Dictionary = town
		n += _town_arrows(td)
		if TownEcon.has_econ(td):
			var stock: Dictionary = td["econ"].get("stock", {})
			for ak2 in BowsEcon.ARROWS:
				n += maxi(0, int(stock.get(ak2, 0)))
	return n

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
		var ak := "arrows_bodkin"
		if int(arm_arrows.get(ak, 0)) < 6:
			arm_arrows[ak] = int(arm_arrows.get(ak, 0)) + 6
		arm_arrows[ak] = int(arm_arrows.get(ak, 0)) - 6
		u.quiver[ak] = 6
	var arrows := 0
	for k in u.quiver:
		arrows += maxi(0, int(u.quiver.get(k, 0)))
	return {"uids": uids, "arrows": arrows, "sample": first_item}

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.wait_save()
	previous_save_path = Game.SAVE_PATH
	check(str(ProjectSettings.get_setting("application/config/version")) == "0.077", "project version is 0.077")
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
	var pre_save_items := _accounted_items()
	var pre_save_arrows := _arrow_sum()
	var pre_save_coins := _coin_sum()
	Game.save_game(); Game.wait_save()
	Game.world = {}; Game.rep = {}
	check(Game.load_game(), "real save reloads after execute and sell")
	seat_town = Prisoners._player_town(Game)
	fed_town = seat_town
	var post_load_items := _accounted_items()
	check(int(post_load_items["count"]) == int(pre_save_items["count"]) and _arrow_sum() == pre_save_arrows,
		"save/load preserves total accounted items (%d) and arrows (%d)" % [int(post_load_items["count"]), _arrow_sum()])
	var loaded_kit_ok := true
	for uid3 in (exec_kit["uids"] as Array) + (sale_kit["uids"] as Array):
		if not _town_has_uid(seat_town, int(uid3)) or int(post_load_items["uids"].get(int(uid3), 0)) != 1:
			loaded_kit_ok = false
	check(loaded_kit_ok, "executed and sold prisoners' exact Item uids survive save/load in the holding town")
	check(Prisoners._find(Prisoners.held(Game), stay.uid).is_empty() and Prisoners._find(Prisoners.held(Game), _pool[3].uid).is_empty(),
		"executed and sold prisoners stay off the held list after save/load")
	check(is_equal_approx(_coin_sum(), pre_save_coins), "save/load preserves total world coin")

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
	return _finish()
