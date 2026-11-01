class_name Prisoners
extends RefCounted
## v0.033 prisoner ransom and exchange. v0.077 adds daily upkeep and AI bargains.
## Battles fill world["prisoners"] (enemy men your army took) and world["captives"] (your men the enemy
## took); see BattleRounds._take_prisoners. Each record keeps the actual Unit, so a freed person goes
## home with their own body, wounds and kit: your people as home reserves (Mobilization.return_freed),
## enemy soldiers through Army.release. Coin moves between real purses (your house purse, their house
## purse, a realm treasury, or a town's market till); none is created.
## Actions: ransom (they pay you for one of theirs), release (free, for standing), pay (you pay for one
## of yours), exchange (one for one, of no lesser worth), execute and sell (relations; sale coin comes
## from a realm that can pay).
## Upkeep: one meal and one coin a day from the captor. The meal leaves the holding army's stores, or
## else the holding town's market. The coin leaves the captor's purse or treasury and enters that town's
## market till. If the meal or the coin is short, that prisoner is released. Nothing is invented.
## AI, once someone has been held AI_HOLD_DAYS: one fair exchange a realm per day, else one ransom of
## their dearest kin they can pay, else one ransom demand for a captive they hold. They accept a player's
## ransom, payment or fair exchange only when the coin or the trade is really there.
const PRICE := {"common": 6, "officer": 20, "noble": 60, "ruler": 150}   # coins (x Item.COIN)
const KIND_WORDS := {"common": "soldier", "officer": "officer", "noble": "noble", "ruler": "ruler"}
const LOG_LIMIT := 60
const RATION := 1
const UPKEEP_COINS := 1
const SALE_COINS := 4
const AI_HOLD_DAYS := 10
const FOODS := ["grain", "fruit", "meat"]

static func held(game) -> Array:
	if not game.world.has("prisoners"): game.world["prisoners"] = []
	return game.world["prisoners"]

static func captives(game) -> Array:
	if not game.world.has("captives"): game.world["captives"] = []
	return game.world["captives"]

static func state(game) -> Dictionary:
	if not game.world.has("ransom"): game.world["ransom"] = {"log": [], "day": -1}
	return game.world["ransom"]

## JSON floats back to ints. Records from before v0.033 carry no Unit: they stay listed until the person
## is gone, but nobody can bargain for them.
static func after_load(game) -> void:
	for rec: Dictionary in held(game) + captives(game):
		for key in ["uid", "family"]:
			if rec.has(key): rec[key] = int(rec[key])
	var st := state(game)
	st["day"] = int(st.get("day", -1))
	for key in st.get("standing", {}): st["standing"][key] = int(st["standing"][key])
	for entry: Dictionary in st["log"]:
		entry["day"] = int(entry["day"])
	for offer: Dictionary in st.get("offers", []):
		offer["uid"] = int(offer.get("uid", -1))
		offer["other"] = int(offer.get("other", -1))
		offer["price"] = int(offer.get("price", 0))
		offer["day"] = int(offer.get("day", -1))
	if st.has("upkeep"):
		for key in ["day", "fed", "released", "coins", "meals"]:
			if st["upkeep"].has(key): st["upkeep"][key] = int(st["upkeep"][key])

# ------------------------------------------------------------------ lookups
## The held Unit of one of your people in enemy hands, or null.
static func captive_unit(game, uid: int) -> Unit:
	for rec: Dictionary in game.world.get("captives", []):
		var u = rec.get("unit")
		if u is Unit and u.uid == uid and not u.dead: return u
	return null

## Every held Unit on both sides (the weekly sweeps must not take them for dead).
static func units(game) -> Array:
	var out: Array = []
	for rec: Dictionary in game.world.get("prisoners", []) + game.world.get("captives", []):
		var u = rec.get("unit")
		if u is Unit and not u.dead: out.append(u)
	return out

static func _find(list: Array, uid: int) -> Dictionary:
	for rec: Dictionary in list:
		if int(rec.get("uid", -1)) == uid: return rec
	return {}

## The register address of a record's person, or {} (men without a family record have none).
static func _address(game, rec: Dictionary) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(str(rec.get("home_town", "")), {})
	if town.is_empty() or int(rec.get("family", -1)) < 0: return {}
	var f: Dictionary = People.fam_of(town, int(rec["family"]))
	if f.is_empty(): return {}
	var p: Array = Persons.by_uid(f, int(rec["uid"]))
	if p.is_empty(): return {}
	return {"town": town, "econ": town.get("econ", {}), "family": f, "person": p}

## The seated rulers and their houses ({"people": {uid: true}, "houses": {uid: true}}); build once per list.
static func ruling(game) -> Dictionary:
	var out := {"people": {}, "houses": {}}
	for town in game.world.get("towns", {}).values():
		var head: Dictionary = town.get("econ", {}).get("head", {})
		if str(head.get("person_uid", "")) != "": out["people"][str(head["person_uid"])] = true
		if str(head.get("house_uid", "")) != "": out["houses"][str(head["house_uid"])] = true
	return out

## ruler (holds a town's seat), noble (of a ruling house, or named as one in battle), officer, or common.
## Every family has a founding house id; only the houses that hold a seat are noble.
static func kind_of(game, rec: Dictionary, seats: Dictionary = {}) -> String:
	var a := _address(game, rec)
	if not a.is_empty():
		if seats.is_empty(): seats = ruling(game)
		if seats["people"].has(str(Persons.g(a["person"], Persons.PERSON_UID, ""))): return "ruler"
		if seats["houses"].has(str(Persons.g(a["person"], Persons.HOUSE_UID, ""))): return "noble"
	if bool(rec.get("noble", false)) or bool(rec.get("household", false)): return "noble"
	var u = rec.get("unit")
	if u is Unit and (u.is_officer() or u.role in ["captain", "officer"]): return "officer"
	return "common"

static func price(game, rec: Dictionary, seats: Dictionary = {}) -> int:
	return int(PRICE[kind_of(game, rec, seats)]) * Item.COIN

## "the Kingdom of the Middle March ..." -> "The Kingdom of the Middle March ..." (capitalize() would title-case every word).
static func _sentence(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1)

static func _coins(amount: int) -> int:
	return int(round(float(amount) / Item.COIN))

## Who would pay the ransom for a prisoner you hold: a noble's own house first, then their realm.
static func _payer(game, rec: Dictionary, amount: int) -> Dictionary:
	var kind := kind_of(game, rec)
	var fid := str(rec.get("faction", ""))
	if kind in ["noble", "ruler"]:
		var a := _address(game, rec)
		if not a.is_empty() and not a["family"].get("gone", false) and float(a["family"].get("purse", 0.0)) >= amount:
			return {"account": a["family"], "field": "purse", "name": "House %s" % str(a["family"].get("name", "?"))}
	var realm: Dictionary = game.world.get("factions", {}).get(fid, {})
	if not realm.is_empty() and float(realm.get("treasury", 0.0)) >= amount:
		return {"account": realm, "field": "treasury", "name": CampaignWorld.faction_the(fid)}
	return {}

## One display row per record, for the Court screen.
static func row(game, rec: Dictionary, mine: bool, seats: Dictionary = {}) -> Dictionary:
	var fid := str(rec.get("held_by", "") if mine else rec.get("faction", ""))
	var kind := kind_of(game, rec, seats)
	var u = rec.get("unit")
	return {"uid": int(rec.get("uid", -1)), "name": str(rec.get("name", "?")), "kind": kind, "kind_text": str(KIND_WORDS[kind]),
		"faction_id": fid, "faction_name": CampaignWorld.faction_name(fid), "price": int(PRICE[kind]) * Item.COIN,
		"days": int(float(game.day) - float(rec.get("day", game.day))), "legacy": not u is Unit,
		"health": str(HealthReport.describe(u).get("fitness", "")) if u is Unit else ""}

# ------------------------------------------------------------------ bargaining
static func _gate(game) -> String:
	if game.get("_save_capture") != null: return "Wait for the save to finish."
	if Dynasty.selected(game).is_empty() or not Dynasty.ruler(game).get("alive", false): return "Choose a living house leader first."
	return ""

## Pure: what an action would do. action: "ransom" | "release" | "execute" | "sell" (a prisoner you hold, uid),
## "pay" (one of yours held by others, uid), "exchange" (one of yours, uid, for a prisoner of the same realm).
static func preview(game, action: String, uid: int, other: int = -1) -> Dictionary:
	var out := {"ok": false, "action": action, "uid": uid, "other": other, "text": "", "price": 0}
	var mine := action in ["pay", "exchange"]
	var rec := _find(captives(game) if mine else held(game), uid)
	if rec.is_empty(): out["text"] = "That prisoner is no longer held."; return out
	out["name"] = str(rec.get("name", "?"))
	var reason := _gate(game)
	if reason != "": out["text"] = reason; return out
	if not rec.get("unit") is Unit or (rec["unit"] as Unit).dead:
		out["text"] = "%s was taken before ransoms were kept on record; no one can find them now." % str(rec.get("name", "?")); return out
	var fid := str(rec.get("held_by", "") if mine else rec.get("faction", ""))
	out["faction_id"] = fid; out["kind"] = kind_of(game, rec)
	var realm: Dictionary = game.world.get("factions", {}).get(fid, {})
	var purse := Feudal._payer(game)
	match action:
		"ransom":
			var cost := price(game, rec)
			var payer := _payer(game, rec, cost)
			out["price"] = cost
			if payer.is_empty():
				out["text"] = "They decline. Neither their house nor %s can pay %d coins for %s." % [CampaignWorld.faction_the(fid), _coins(cost), out["name"]]; return out
			out["payer_name"] = payer["name"]
			out["text"] = _sentence("%s pays %d coins into your house purse; %s goes home." % [payer["name"], _coins(cost), out["name"]]) + _standing_text(game, "ransom", fid, Diplomacy.RANSOM) + " They accept."
		"release":
			out["text"] = "%s goes home freely." % out["name"] + _standing_text(game, "release", fid, Diplomacy.RELEASE)
		"pay":
			var cost := price(game, rec)
			out["price"] = cost
			if realm.is_empty(): out["text"] = "They decline. No one in %s will bargain for %s." % [CampaignWorld.faction_name(fid), out["name"]]; return out
			if purse.is_empty() or float(purse.get("purse", 0.0)) < cost:
				out["text"] = "They decline. Your house purse cannot cover the %d coin ransom." % (_coins(cost)); return out
			out["text"] = "They accept. Pay %d coins from your house purse to %s; %s comes home." % [_coins(cost), CampaignWorld.faction_the(fid), out["name"]]
		"exchange":
			var theirs := _find(held(game), other)
			if theirs.is_empty() or not theirs.get("unit") is Unit: out["text"] = "Choose a prisoner you hold to trade."; return out
			if str(theirs.get("faction", "")) != fid:
				out["text"] = "They decline. %s can only be traded for a prisoner of %s." % [out["name"], CampaignWorld.faction_the(fid)]; return out
			if price(game, theirs) < price(game, rec):
				out["text"] = "They decline. " + _sentence("%s will not trade a %s for a %s." % [CampaignWorld.faction_the(fid), KIND_WORDS[kind_of(game, rec)], KIND_WORDS[kind_of(game, theirs)]]); return out
			out["other_name"] = str(theirs.get("name", "?"))
			out["text"] = "They accept. %s goes home to %s; %s comes home to you." % [out["other_name"], CampaignWorld.faction_name(fid), out["name"]]
		"execute":
			out["text"] = "Execute %s. Standing with %s falls by %d for each head, and stops after %d heads in one day." % [out["name"], CampaignWorld.faction_name(fid), -Diplomacy.EXECUTE_PER_HEAD, -Diplomacy.EXECUTE_CAP]
		"sell":
			var cost_s := SALE_COINS * Item.COIN
			var buyer := _slaver_buyer(game, fid, float(cost_s))
			out["price"] = cost_s
			if buyer.is_empty():
				out["text"] = "They decline. No realm can pay %d coins for %s, so nobody is sold and no coin is invented." % [SALE_COINS, out["name"]]; return out
			out["payer_name"] = str(buyer["name"])
			out["text"] = "%s pays %d coins from its treasury into your house purse. %s is sold. Realms that oppose slavery lose standing." % [str(buyer["name"]), SALE_COINS, out["name"]]
		_:
			out["text"] = "Unknown action."; return out
	out["ok"] = true
	out["review"] = {"action": action, "uid": uid, "other": other, "price": out["price"], "payer": str(out.get("payer_name", "")), "day": int(game.day)}
	return out

## The cheapest prisoner of the captor's realm you hold who is worth at least as much as your captive.
static func exchange_pick(game, uid: int, seats: Dictionary = {}) -> int:
	var rec := _find(captives(game), uid)
	if rec.is_empty(): return -1
	if seats.is_empty(): seats = ruling(game)
	var want := price(game, rec, seats)
	var best := -1; var best_price := 0
	for theirs: Dictionary in held(game):
		if str(theirs.get("faction", "")) != str(rec.get("held_by", "")) or not theirs.get("unit") is Unit: continue
		var p := price(game, theirs, seats)
		if p >= want and (best < 0 or p < best_price): best = int(theirs["uid"]); best_price = p
	return best

## Confirmation rechecks everything and rejects a changed review.
static func confirm(game, action: String, uid: int, other: int = -1, review: Dictionary = {}) -> Dictionary:
	var offer := preview(game, action, uid, other)
	if not offer.get("ok", false): return offer
	if not review.is_empty() and review != offer["review"]: return {"ok": false, "text": "The terms changed. Review them again."}
	var fid := str(offer["faction_id"])
	var text := ""
	match action:
		"ransom":
			var rec := _find(held(game), uid)
			var payer := _payer(game, rec, int(offer["price"]))
			var account: Dictionary = payer["account"]
			account[payer["field"]] = float(account[payer["field"]]) - float(offer["price"])
			var purse := Feudal._payer(game)
			purse["purse"] = float(purse.get("purse", 0.0)) + float(offer["price"])
			_free_enemy(game, rec, "ransomed")
			if _first_today(game, "ransom", fid): Diplomacy.on_ransom(game, fid)
			text = "%s ransomed %s for %d coins." % [payer["name"], offer["name"], _coins(int(offer["price"]))]
		"release":
			_free_enemy(game, _find(held(game), uid), "released")
			if _first_today(game, "release", fid): Diplomacy.on_release(game, fid)
			text = "You released %s to %s." % [offer["name"], CampaignWorld.faction_name(fid)]
		"pay":
			var rec := _find(captives(game), uid)
			if not _free_mine(game, rec): return {"ok": false, "text": "%s can no longer come home." % offer["name"]}
			var purse := Feudal._payer(game)
			purse["purse"] = float(purse["purse"]) - float(offer["price"])
			var realm: Dictionary = game.world["factions"][fid]
			realm["treasury"] = float(realm.get("treasury", 0.0)) + float(offer["price"])
			text = "You paid %d coins to %s; %s is home." % [_coins(int(offer["price"])), CampaignWorld.faction_the(fid), offer["name"]]
		"exchange":
			var rec := _find(captives(game), uid)
			if not _free_mine(game, rec): return {"ok": false, "text": "%s can no longer come home." % offer["name"]}
			_free_enemy(game, _find(held(game), other), "exchanged")
			_drop_offer(game, uid, "demand")
			text = "Exchanged %s for %s with %s." % [offer["other_name"], offer["name"], CampaignWorld.faction_the(fid)]
		"execute":
			var rec_x := _find(held(game), uid)
			_lose_prisoner(game, rec_x, "executed", "executed in captivity")
			_standing_execute(game, fid, 1)
			text = "You executed %s." % offer["name"]
		"sell":
			var rec_s := _find(held(game), uid)
			var buyer := _slaver_buyer(game, fid, float(offer["price"]))
			if buyer.is_empty(): return {"ok": false, "text": "No realm can pay. Nothing was sold."}
			var account: Dictionary = buyer["account"]
			account["treasury"] = float(account.get("treasury", 0.0)) - float(offer["price"])
			var purse_s := Feudal._payer(game)
			if purse_s.is_empty() or not purse_s.has("purse"):
				account["treasury"] = float(account["treasury"]) + float(offer["price"])
				return {"ok": false, "text": "Your house has no purse. Nothing was sold."}
			purse_s["purse"] = float(purse_s.get("purse", 0.0)) + float(offer["price"])
			_lose_prisoner(game, rec_s, "sold", "sold to slavers")
			Diplomacy.on_sell_to_slavers(game, 1)
			text = "Sold %s to slavers. %s paid %d coins." % [offer["name"], str(buyer["name"]), _coins(int(offer["price"]))]
	_log(game, _sentence(text))
	game.changed.emit()
	return {"ok": true, "text": _sentence(text)}

## Standing for ransoms and releases counts once per realm per day (a mass release is one gesture, not fifty).
static func _first_today(game, kind: String, fid: String) -> bool:
	if _granted_today(game, kind, fid): return false
	var st := state(game)
	if not st.has("standing"): st["standing"] = {}
	st["standing"][kind + ":" + fid] = int(game.day)
	return true

static func _granted_today(game, kind: String, fid: String) -> bool:
	return int(state(game).get("standing", {}).get(kind + ":" + fid, -1)) == int(game.day)

static func _standing_text(game, kind: String, fid: String, amount: int) -> String:
	if _granted_today(game, kind, fid): return " Standing with %s already rose for this today." % CampaignWorld.faction_name(fid)
	return " Standing with %s +%d." % [CampaignWorld.faction_name(fid), amount]

## An enemy prisoner goes home: a soldier on his realm's roll through the native release (his kit goes to
## the home armory, his family takes him back); anyone else straight to their family.
static func _free_enemy(game, rec: Dictionary, why: String) -> void:
	held(game).erase(rec)
	var u: Unit = rec["unit"]
	Horses.return_mount(game, u)
	if Army.state(game.world)["roll"].has(str(u.uid)):
		Army.release(game, u, why)
		return
	var a := _address(game, rec)
	if a.is_empty(): return
	ArmsTrade.kit_home(game, u)
	People.release(a["town"], int(a["family"]["id"]), str(rec.get("role", a["person"][4])), u.uid)
	Families.add_hist(a["family"], "%s came home, %s from captivity." % [u.name, why], float(game.day))

## One of your people comes home: a registered person as a home reserve, a hired man back to the company.
static func _free_mine(game, rec: Dictionary) -> bool:
	var u: Unit = rec["unit"]
	if u.family >= 0 and game.world.get("towns", {}).has(u.home_town):
		if not Mobilization.return_freed(game, u): return false
		var a := _address(game, rec)
		if not a.is_empty(): Families.add_hist(a["family"], "%s came home from captivity." % u.name, float(game.day))
	else:
		u.squad = -1
		game.company.append(u)
		game.invalidate_deploy()
	captives(game).erase(rec)
	return true

# ------------------------------------------------------------------ daily
## Records of people who died while held (old age, sickness, a sweep) leave the lists. The optional day lets
## Warfare's multi-day advances run once per midnight; repeated calls for a day are harmless.
static func daily(game, day: int = -1) -> void:
	if day < 0: day = int(game.day)
	var st := state(game)
	if day <= int(st.get("day", -1)): return
	st["day"] = day
	_upkeep_day(game, day)
	for list: Array in [held(game), captives(game)]:
		for rec: Dictionary in list.duplicate():
			var u = rec.get("unit")
			var legacy: bool = not u is Unit
			var gone: bool = not legacy and u.dead
			# Your people's families stay put while one is held (Persons.AWAY), so a missing register row means
			# they are gone. An enemy family may move away; their man is still held until he dies or is freed.
			if not gone and (legacy or is_same(list, captives(game))) and int(rec.get("family", -1)) >= 0 \
					and game.world.get("towns", {}).has(str(rec.get("home_town", ""))):
				var a := _address(game, rec)
				gone = a.is_empty() or str(a["person"][4]) in ["gone", "dead"]
			if gone:
				if u is Unit: Horses.return_mount(game, u)
				list.erase(rec)
				_log(game, "%s died in captivity." % str(rec.get("name", "?")), day)
	_ai_day(game, day)

static func offers(game) -> Array:
	var live := {}
	for rec: Dictionary in held(game) + captives(game):
		live[int(rec.get("uid", -1))] = true
	var kept: Array = []
	for offer: Dictionary in _offer_list(game):
		if live.has(int(offer.get("uid", -2))): kept.append(offer)
	var st := state(game)
	st["offers"] = kept
	return kept

## The player turns down one AI demand. The captive stays. No coin moves.
static func decline(game, uid: int, kind: String) -> Dictionary:
	var kept: Array = []
	var found := false
	for offer: Dictionary in _offer_list(game):
		if int(offer.get("uid", -2)) == uid and str(offer.get("kind", "")) == kind:
			found = true
			continue
		kept.append(offer)
	state(game)["offers"] = kept
	var text := "You decline." if found else "That offer is already gone."
	if found: _log(game, text)
	game.changed.emit()
	return {"ok": found, "text": text}

static func _offer_list(game) -> Array:
	var st := state(game)
	if not st.has("offers"): st["offers"] = []
	return st["offers"]

static func _drop_offer(game, uid: int, kind: String) -> void:
	var kept: Array = []
	for offer: Dictionary in _offer_list(game):
		if int(offer.get("uid", -2)) == uid and str(offer.get("kind", "")) == kind: continue
		kept.append(offer)
	state(game)["offers"] = kept

static func _has_meal(stock: Dictionary) -> bool:
	for g in FOODS:
		if int(stock.get(g, 0)) >= RATION: return true
	return false

static func _take_meal(stock: Dictionary) -> String:
	for g in FOODS:
		if int(stock.get(g, 0)) >= RATION:
			stock[g] = int(stock.get(g, 0)) - RATION
			return g
	return ""

static func _player_town(game) -> Dictionary:
	var tid := str(game.world.get("player_house", {}).get("town_id", ""))
	if tid == "": tid = str(game.location)
	return game.world.get("towns", {}).get(tid, {})

static func _faction_town(game, fid: String) -> Dictionary:
	var fac: Dictionary = game.world.get("factions", {}).get(fid, {})
	var tid := str(fac.get("capital", ""))
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	if not town.is_empty() and TownEcon.has_econ(town): return town
	var best: Dictionary = {}
	var best_food := -1
	for t in game.world.get("towns", {}).values():
		if str(t.get("faction", "")) != fid or not TownEcon.has_econ(t): continue
		var n := int(Goods.supply(t, "food"))
		if n > best_food:
			best = t
			best_food = n
	return best

static func _market_till(town: Dictionary) -> Dictionary:
	if town.is_empty() or not TownEcon.has_econ(town): return {}
	var e: Dictionary = town["econ"]
	if not e.has("biz"): return {}
	var biz: Array = e["biz"]
	if e.has("mkt"):
		var i := int(e["mkt"])
		if i >= 0 and i < biz.size() and biz[i] is Dictionary and (biz[i] as Dictionary).has("till"):
			return biz[i]
	for stall in biz:
		if stall is Dictionary and (stall as Dictionary).has("till"): return stall
	return {}

## Food stock and the two coin accounts for one prisoner. Empty when either side cannot be named.
static func _keeper(game, rec: Dictionary, player_holds: bool) -> Dictionary:
	var food_stock: Dictionary = {}
	var food_econ: Dictionary = {}
	var band_id := str(rec.get("hold_band", ""))
	if band_id != "" and game.world.get("warbands", {}).has(band_id):
		var wb: Dictionary = game.world["warbands"][band_id]
		if wb.has("stores") and _has_meal(wb["stores"]):
			food_stock = wb["stores"]
	var fid := str(rec.get("faction", "") if player_holds else rec.get("held_by", ""))
	var town: Dictionary = _player_town(game) if player_holds else _faction_town(game, fid)
	if food_stock.is_empty() and not town.is_empty() and TownEcon.has_econ(town):
		food_stock = town["econ"]["stock"]
		food_econ = town["econ"]
	var coin_account: Dictionary = {}
	var coin_field := ""
	if player_holds:
		coin_account = Feudal._payer(game)
		coin_field = "purse"
	else:
		coin_account = game.world.get("factions", {}).get(fid, {})
		coin_field = "treasury"
	var till := _market_till(town if not town.is_empty() else (_player_town(game) if player_holds else _faction_town(game, fid)))
	if coin_account.is_empty() or not coin_account.has(coin_field) or till.is_empty(): return {}
	if food_stock.is_empty() and food_econ.is_empty(): return {}
	return {"stock": food_stock, "econ": food_econ, "coin": coin_account, "coin_field": coin_field, "till": till}

## A meal in the chosen stock, or, for a town, in its granary or barn. The market shelf is used first.
static func _meal_available(place: Dictionary) -> bool:
	if _has_meal(place["stock"]): return true
	var econ: Dictionary = place["econ"]
	if econ.is_empty(): return false
	if int(econ.get("granary", 0)) >= RATION: return true
	return econ.has("barn") and _has_meal(econ["barn"])

static func _consume_meal(place: Dictionary) -> String:
	var good := _take_meal(place["stock"])
	if good != "": return good
	var econ: Dictionary = place["econ"]
	if econ.is_empty(): return ""
	if int(econ.get("granary", 0)) >= RATION:
		econ["granary"] = int(econ["granary"]) - RATION
		return "grain"
	if econ.has("barn"): return _take_meal(econ["barn"])
	return ""

static func _can_feed(place: Dictionary) -> bool:
	if place.is_empty(): return false
	return _meal_available(place) and float(place["coin"].get(place["coin_field"], 0.0)) + 0.001 >= float(UPKEEP_COINS * Item.COIN)

## Someone the death pass is about to drop is not fed and not freed for hunger.
static func _upkeep_skipped(game, rec: Dictionary, player_holds: bool) -> bool:
	var u = rec.get("unit")
	if not u is Unit or (u as Unit).dead: return true
	if player_holds: return false
	if int(rec.get("family", -1)) < 0: return false
	if not game.world.get("towns", {}).has(str(rec.get("home_town", ""))): return false
	var a := _address(game, rec)
	return a.is_empty() or str(a["person"][4]) in ["gone", "dead"]

static func _release_unfed(game, rec: Dictionary, player_holds: bool) -> void:
	if player_holds:
		if rec.get("unit") is Unit and not (rec["unit"] as Unit).dead and held(game).has(rec):
			_free_enemy(game, rec, "unfed")
		else:
			held(game).erase(rec)
	else:
		var freed := false
		if rec.get("unit") is Unit and not (rec["unit"] as Unit).dead:
			freed = _free_mine(game, rec)
		if not freed: captives(game).erase(rec)

static func _upkeep_day(game, day: int) -> void:
	var rows: Array = []
	for rec: Dictionary in held(game):
		if not _upkeep_skipped(game, rec, true):
			rows.append({"rec": rec, "player_holds": true, "worth": price(game, rec)})
	for rec2: Dictionary in captives(game):
		if not _upkeep_skipped(game, rec2, false):
			rows.append({"rec": rec2, "player_holds": false, "worth": price(game, rec2)})
	if rows.is_empty(): return
	rows.sort_custom(func(a, b): return int(a["worth"]) > int(b["worth"]))
	var fed := 0
	var released := 0
	var cost := float(UPKEEP_COINS * Item.COIN)
	for row: Dictionary in rows:
		var rec: Dictionary = row["rec"]
		var player_holds: bool = bool(row["player_holds"])
		var place := _keeper(game, rec, player_holds)
		if not _can_feed(place):
			_release_unfed(game, rec, player_holds)
			released += 1
			continue
		var good := _consume_meal(place)
		if good == "":
			_release_unfed(game, rec, player_holds)
			released += 1
			continue
		var account: Dictionary = place["coin"]
		account[place["coin_field"]] = float(account[place["coin_field"]]) - cost
		var till: Dictionary = place["till"]
		till["till"] = float(till["till"]) + cost
		var econ: Dictionary = place["econ"]
		if not econ.is_empty() and econ.has("led") and (econ["led"] as Dictionary).has("used"):
			TownEcon.led(econ, "used", good, RATION)
		fed += 1
	state(game)["upkeep"] = {"day": day, "fed": fed, "released": released, "coins": fed * UPKEEP_COINS, "meals": fed * RATION}
	if released > 0:
		_log(game, "Stores ran out: released %d prisoner%s. No food or coin was invented." % [released, "" if released == 1 else "s"], day)

static func _held_long(game, rec: Dictionary) -> bool:
	return int(game.day) - int(float(rec.get("day", game.day))) >= AI_HOLD_DAYS

static func _ready(game, fid: String, player_holds: bool) -> Array:
	var out: Array = []
	var list: Array = held(game) if player_holds else captives(game)
	for rec: Dictionary in list:
		var id := str(rec.get("faction", "") if player_holds else rec.get("held_by", ""))
		if id != fid or not rec.get("unit") is Unit or (rec["unit"] as Unit).dead: continue
		if not _held_long(game, rec): continue
		out.append(rec)
	out.sort_custom(func(a, b): return price(game, a) > price(game, b))
	return out

static func _ai_day(game, day: int) -> void:
	var realms: Array = []
	for rec: Dictionary in held(game):
		var fid := str(rec.get("faction", ""))
		if fid != "" and not realms.has(fid): realms.append(fid)
	for rec2: Dictionary in captives(game):
		var fid2 := str(rec2.get("held_by", ""))
		if fid2 != "" and not realms.has(fid2): realms.append(fid2)
	for fid3: String in realms:
		if _ai_exchange(game, fid3): continue
		if _ai_ransom(game, fid3): continue
		_ai_demand(game, fid3, day)

static func _ai_exchange(game, fid: String) -> bool:
	var caps := _ready(game, fid, false)
	var theirs := _ready(game, fid, true)
	if caps.is_empty() or theirs.is_empty(): return false
	for cap: Dictionary in caps:
		var want := price(game, cap)
		var pick := -1
		var pick_price := 0
		for th: Dictionary in theirs:
			var p := price(game, th)
			if p >= want and (pick < 0 or p < pick_price):
				pick = int(th.get("uid", -1))
				pick_price = p
		if pick < 0: continue
		var uid := int(cap.get("uid", -1))
		var offer := preview(game, "exchange", uid, pick)
		if offer.get("ok", false) and confirm(game, "exchange", uid, pick, offer.get("review", {})).get("ok", false):
			return true
	return false

static func _ai_ransom(game, fid: String) -> bool:
	for rec: Dictionary in _ready(game, fid, true):
		var uid := int(rec.get("uid", -1))
		var offer := preview(game, "ransom", uid)
		if offer.get("ok", false) and confirm(game, "ransom", uid, -1, offer.get("review", {})).get("ok", false):
			return true
	return false

static func _ai_demand(game, fid: String, day: int) -> void:
	if _granted_today(game, "demand", fid): return
	var caps := _ready(game, fid, false)
	if caps.is_empty(): return
	var rec: Dictionary = caps[0]
	var uid := int(rec.get("uid", -1))
	for offer: Dictionary in _offer_list(game):
		if str(offer.get("kind", "")) == "demand" and int(offer.get("uid", -2)) == uid: return
	var cost := price(game, rec)
	var text := "%s demands %d coins for %s." % [_sentence(CampaignWorld.faction_the(fid)), _coins(cost), str(rec.get("name", "?"))]
	_offer_list(game).append({"kind": "demand", "uid": uid, "other": -1, "fid": fid, "price": cost, "day": day, "text": text})
	_first_today(game, "demand", fid)
	_log(game, text, day)

## The richest realm that does not oppose slavery and is neither the prisoner's realm nor the player's.
static func _slaver_buyer(game, prisoner_fid: String, amount: float) -> Dictionary:
	var oppose: Array = Diplomacy.data().get("opposes_slavery", [])
	var mine := Diplomacy.player_realm(game.world)
	var best_fid := ""
	var best_coin := -1.0
	for fid in game.world.get("factions", {}):
		var id := str(fid)
		if id == "" or id == prisoner_fid or id == mine or oppose.has(id): continue
		var realm: Dictionary = game.world["factions"][id]
		var coin := float(realm.get("treasury", 0.0))
		if coin + 0.001 < amount or coin <= best_coin: continue
		best_coin = coin
		best_fid = id
	if best_fid == "": return {}
	return {"fid": best_fid, "account": game.world["factions"][best_fid], "name": CampaignWorld.faction_name(best_fid)}

static func _standing_execute(game, fid: String, heads: int) -> void:
	var st := state(game)
	if int(st.get("execute_day", -2)) != int(game.day):
		st["execute_day"] = int(game.day)
		st["execute_heads"] = {}
	var done := int(st["execute_heads"].get(fid, 0))
	var room := maxi(0, -Diplomacy.EXECUTE_CAP - done)
	var apply := mini(heads, room)
	st["execute_heads"][fid] = done + heads
	if apply > 0: Diplomacy.on_execute(game, fid, apply)

## Execution or sale: the person leaves the rolls through the ordinary casualty settlement, with the real cause.
## An execution is a census death; a sale is a census leaving ("sold to slavers"), since a sold prisoner is not dead.
static func _lose_prisoner(game, rec: Dictionary, cause: String, detail: String) -> void:
	held(game).erase(rec)
	var u: Unit = rec["unit"]
	Horses.return_mount(game, u)
	u.dead = true
	Census.note_fate(game.world, u.uid, cause, detail)
	var roll: Dictionary = Army.state(game.world)["roll"]
	var role := str(rec.get("role", "army"))
	if roll.has(str(u.uid)):
		var r: Array = roll[str(u.uid)]
		if r.size() > 2: role = str(r[2])
		roll.erase(str(u.uid))
	People.casualty(game, u, "dead", role)

static func _log(game, text: String, day: int = -1) -> void:
	var st := state(game)
	st["log"].append({"day": int(game.day) if day < 0 else day, "text": text})
	while st["log"].size() > LOG_LIMIT: st["log"].pop_front()
	CampaignWorld.log_event(game, text)
