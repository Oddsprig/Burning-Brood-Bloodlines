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

## Enemy treasury plus the family purses of these men (the accounts a ransom can leave).
func _kin_pot(units: Array) -> float:
	var n := _treasury(_enemy)
	var seen: Array = []
	for u in units:
		if not u is Unit: continue
		var town: Dictionary = Game.world["towns"].get((u as Unit).home_town, {})
		var f: Dictionary = People.fam_of(town, (u as Unit).family) if not town.is_empty() else {}
		if f.is_empty(): continue
		var already := false
		for s in seen:
			if is_same(s, f): already = true
		if already: continue
		seen.append(f)
		n += float(f.get("purse", 0.0))
	return n

func _till(town: Dictionary) -> float:
	var stall := Prisoners._market_till(town)
	return float(stall.get("till", 0.0)) if not stall.is_empty() else -1.0

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
	var pot := _kin_pot([_pool[0], _pool[1]])
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
	check(is_equal_approx(_kin_pot([_pool[0], _pool[1]]), pot - float(gone_price)), "the ransom leaves their house purse or their treasury")
	check(int(fed_town["econ"]["stock"]["grain"]) == grain - 2, "both prisoners were fed before the ransom")
	check(is_equal_approx(_coin_sum(), coins), "the ransom moves coin and does not mint it")
	check(Diplomacy.earned(Game, _enemy) == mini(100, standing + Diplomacy.RANSOM), "their ransom improves standing")

	# --- Execute the one they did not buy. Further heads the same day stop changing standing at the cap.
	var stay: Unit = _pool[0] if left_uid == _pool[0].uid else _pool[1]
	var stay_rec: Dictionary = Prisoners._find(Prisoners.held(Game), stay.uid)
	var stay_fam: Dictionary = Prisoners._address(Game, stay_rec).get("family", {})
	coins = _coin_sum()
	standing = Diplomacy.earned(Game, _enemy)
	var executed := Prisoners.preview(Game, "execute", stay.uid)
	check(executed.get("ok", false), "execute can be reviewed")
	check(Prisoners.confirm(Game, "execute", stay.uid, -1, executed.get("review", {})).get("ok", false), "execute is confirmed")
	check(Prisoners.held(Game).is_empty() and stay.dead, "the executed prisoner is dead and off the list")
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
	purse = _purse(); var buyer_coin := _treasury(buyer); coins = _coin_sum()
	var sale := Prisoners.preview(Game, "sell", _pool[3].uid)
	check(sale.get("ok", false) and int(sale.get("price", 0)) == sale_price, "the sale price is the small fixed price")
	check(Prisoners.confirm(Game, "sell", _pool[3].uid, -1, sale.get("review", {})).get("ok", false), "the sale is confirmed")
	check(Prisoners._find(Prisoners.held(Game), _pool[3].uid).is_empty() and _pool[3].dead, "the sold prisoner is dead and off the list")
	check(is_equal_approx(_purse(), purse + float(sale_price)) and is_equal_approx(_treasury(buyer), buyer_coin - float(sale_price)), "the buyer's treasury pays your purse")
	check(is_equal_approx(_coin_sum(), coins), "the sale mints nothing")
	for f2 in oppose:
		check(Diplomacy.earned(Game, str(f2)) == maxi(-100, int(before_opp[str(f2)]) + Diplomacy.SLAVERS_PER_HEAD), "selling costs %s %d standing" % [str(f2), Diplomacy.SLAVERS_PER_HEAD])
	if not sale_fam.is_empty(): check(str(sale_fam.get("hist", [])).contains("sold to slavers"), "the family is told they were sold")

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
