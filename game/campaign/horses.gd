class_name Horses
extends RefCounted
## Mounted livestock bridge. Herds owns market head, prices and ledgers; Unit owns
## each purchased horse's native quadruped body. Never a second town horse stock.
const GRAIN_DAY := 3 # [ours] counted grain portions, through the existing army stores
const COIN_DAY := 20 # [ours] groom/farrier payment in native coins
const COATS := ["bay", "chestnut", "black", "grey"]

static func can_field(u: Unit) -> bool:
	return u != null and not u.dead and u.horse != null and not u.horse.dead \
		and u.horse.race == "horse" and bool(u.horse_care.get("fed", false)) and bool(u.horse_care.get("paid", false))

static func count(units: Array) -> int:
	var n := 0
	for u: Unit in units:
		if u.horse != null and not u.horse.dead: n += 1
	return n

static func offered(e: Dictionary) -> int:
	var n := 0
	var seen := {}
	for offer: Array in Herds.H(e)["of"]:
		var h: Dictionary = Herds.herds(e).get(str(int(offer[0])), {})
		if h.is_empty() or str(h["k"]) != "horses" or str(offer[1]) != "g": continue
		if Herds.sick(h) > float(Herds.A()["disease_no_sale"]): continue
		var key := str(int(h["id"]))
		var q := mini(maxi(0, int(offer[2])), maxi(0, int(h["g"]) - int(seen.get(key, 0))))
		seen[key] = int(seen.get(key, 0)) + q
		n += q
	return n

static func price(town: Dictionary) -> int:
	return maxi(1, ceili(Herds.price(town["econ"], "horses"))) if TownEcon.has_econ(town) else 0

static func quote(game, town: Dictionary, u: Unit) -> Dictionary:
	var cost := price(town)
	var reason := ""
	if not TownEcon.has_econ(town): reason = "No livestock market."
	elif not Mobilization._here(game, str(town["id"])): reason = "Visit this settlement to trade horses."
	elif u == null or not game.company.has(u) or u.dead: reason = "Select a living field soldier."
	elif u.race not in FigurePainter.DETAILED_RACES: reason = "This body cannot ride."
	elif u.horse != null: reason = "This soldier already owns a mount."
	elif Mobilization.is_medic(game, u) or _dragon_rider(game, u): reason = "This soldier has another assignment."
	elif offered(town["econ"]) < 1: reason = "No grown horses are offered."
	elif game.gold < cost: reason = "Fund the army purse first."
	return {"ok": reason == "", "reason": reason, "cost": cost}

static func _dragon_rider(game, u: Unit) -> bool:
	for row: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		var uid := str(row.get("rider_person_uid", ""))
		if uid == "": continue
		var person: Unit = Dynasty.bound_unit(game, Dynasty.person(game, uid))
		if person == u and bool(row.get("alive", false)): return true
	return false

static func buy(game, town: Dictionary, u: Unit) -> Dictionary:
	var q := quote(game, town, u)
	if not bool(q["ok"]): return q
	var result := buy_for(game, town, u, {"kind": "company", "game": game})
	if bool(result["ok"]):
		game.invalidate_deploy()
		game.changed.emit()
	return result

## AI supply provisioning and player purchases share this one native stock transfer.
static func buy_for(game, town: Dictionary, u: Unit, payer: Dictionary, purchase_day: int = -1) -> Dictionary:
	var trade_day := int(game.day) if purchase_day < 0 else purchase_day
	if u == null or u.dead or u.horse != null or not TownEcon.has_econ(town):
		return {"ok": false, "reason": "No eligible rider or market."}
	var e: Dictionary = town["econ"]
	var cost := price(town)
	if offered(e) < 1 or Army._funds(payer) < cost:
		return {"ok": false, "reason": "No affordable grown horse."}
	var healthy: Array = []
	for row: Array in Herds.H(e)["of"]:
		var h: Dictionary = Herds.herds(e).get(str(int(row[0])), {})
		if not h.is_empty() and Herds.sick(h) <= float(Herds.A()["disease_no_sale"]): healthy.append(row)
	var offer := Herds._take_offer(e, "horses", ["g"], -1, -1, {"horses": {"g": healthy}})
	if offer.is_empty(): return {"ok": false, "reason": "The offer has sold."}
	var seller: Dictionary = Herds.herds(e)[str(int(offer[0]))]
	var saved: Array = seller.get("mount_bodies", [])
	var horse: Unit
	if not saved.is_empty(): horse = Unit.from_dict(saved.pop_back())
	else:
		var local := RandomNumberGenerator.new()
		local.seed = hash([int(game.world.get("seed", 0)), str(town["id"]), int(seller["id"]), u.uid, int(Herds.H(e).get("mount_sales", 0))])
		horse = Unit.create("horse", u.faction, false)
		Factory.roll_attrs(local, horse)
		Factory.roll_size(local, horse)
		horse.look = {"coat": COATS[local.randi_range(0, COATS.size() - 1)], "seed": local.randi()}
		horse.born = float(game.day) - 3.0 * Herds.year_days()
	horse.faction = u.faction
	horse.name = u.name + "'s horse"
	Herds.change(e, seller, "g", -1, "sold", "army mount %d" % horse.uid, float(trade_day))
	Army._spend(payer, cost)
	Herds._add_coin(e, seller, cost)
	if str(payer["kind"]) == "company": TownEcon.gold_out(-cost)
	var hd := Herds.H(e)
	hd["mount_sales"] = int(hd.get("mount_sales", 0)) + 1
	if not hd.has("bk"): hd["bk"] = {}
	hd["bk"]["horses"] = int(hd["bk"].get("horses", 0)) + 1
	hd["sok"]["horses"] = int(hd["sok"].get("horses", 0)) + 1
	u.horse = horse
	u.horse_care = {"last_day": trade_day, "hungry": 0, "fed": true, "paid": true,
		"purchase": cost, "source_town": str(town["id"])}
	return {"ok": true, "reason": "Bought a mount for %d coins." % cost, "cost": cost, "horse_uid": horse.uid}

static func _put(e: Dictionary, h: Dictionary, horse: Unit, day: float, detail: String) -> void:
	Herds.change(e, h, "g", 1, "bought", detail, day)
	if not h.has("mount_bodies"): h["mount_bodies"] = []
	h["mount_bodies"].append(horse.to_dict()) # a body snapshot attached to one already-counted head

static func sell(game, town: Dictionary, u: Unit) -> Dictionary:
	if u == null or u.horse == null or u.horse.dead or not game.company.has(u) \
			or not TownEcon.has_econ(town) or not Mobilization._here(game, str(town["id"])):
		return {"ok": false, "reason": "Visit a livestock market with your living mount."}
	var e: Dictionary = town["econ"]
	var cost := price(town)
	if float(e["treasury"]) < cost: return {"ok": false, "reason": "The town cannot afford this horse."}
	var h := Herds.herd_for(e, 0, "horses", float(game.day))
	e["treasury"] = float(e["treasury"]) - cost
	game.gold += cost
	TownEcon.gold_out(cost)
	_put(e, h, u.horse, float(game.day), "bought army mount %d" % u.horse.uid)
	u.horse = null
	u.horse_care = {}
	game.invalidate_deploy()
	game.changed.emit()
	return {"ok": true, "reason": "Sold the mount for %d coins." % cost, "paid": cost}

## Stand-down/death returns the surviving owned animal, without a fictitious sale.
static func return_mount(game, u: Unit) -> void:
	if u == null or u.horse == null: return
	if u.horse.dead:
		casualty(u, u.horse)
		return
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	if not TownEcon.has_econ(town): return
	var e: Dictionary = town["econ"]
	var fid := u.family if u.family >= 0 and u.family < e["fams"].size() and not e["fams"][u.family].get("gone", false) else 0
	var h := Herds.herd_for(e, fid, "horses", float(game.day))
	_put(e, h, u.horse, float(game.day), "returned army mount %d" % u.horse.uid)
	u.horse = null
	u.horse_care = {}

## The native death event calls this once, after BattleMorale marks this exact horse dead.
static func casualty(rider: Unit, horse: Unit) -> bool:
	if rider.horse != horse or not horse.dead: return false
	rider.horse_care["lost_uid"] = horse.uid
	rider.horse_care["loss"] = "horse casualty"
	rider.horse = null
	return true

static func _care(game, u: Unit, day: int, payer: Dictionary, draw: Callable) -> void:
	if u.horse == null or day <= int(u.horse_care.get("last_day", day)): return
	if u.horse.dead:
		casualty(u, u.horse)
		return
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	var care := u.horse_care
	var paid := 0
	if TownEcon.has_econ(town) and Army._funds(payer) >= COIN_DAY:
		Army._spend(payer, COIN_DAY)
		var e: Dictionary = town["econ"]
		e["biz"][int(e["mkt"])]["till"] = float(e["biz"][int(e["mkt"])]["till"]) + COIN_DAY
		if str(payer["kind"]) == "company": TownEcon.gold_out(-COIN_DAY)
		paid = COIN_DAY
	var feed := int(draw.call(GRAIN_DAY))
	if feed == GRAIN_DAY and paid == COIN_DAY: Healing.heal(u.horse, 1.0, false, 0)
	TownEcon.goods_lost["grain"] = int(TownEcon.goods_lost.get("grain", 0)) + feed
	care["last_day"] = day
	care["fed"] = feed == GRAIN_DAY
	care["paid"] = paid == COIN_DAY
	care["hungry"] = 0 if bool(care["fed"]) else int(care.get("hungry", 0)) + 1
	care["receipt"] = {"day": day, "horse_uid": u.horse.uid, "grain": feed, "coin": paid}
	if int(care["hungry"]) > int(Herds.A()["starve_after"]):
		u.horse.dead = true
		casualty(u, u.horse)

static func company_day(game, day: int) -> void:
	for u: Unit in game.company:
		_care(game, u, day, {"kind": "company", "game": game},
			func(n: int): return Supplies.draw_horse_grain(game, n))

static func band_day(game, wb: Dictionary, payer: Dictionary, day: int) -> void:
	if day <= 0 or day <= int(wb.get("horse_supply_day", -1)): return
	wb["horse_supply_day"] = day
	var town: Dictionary = game.world.get("towns", {}).get(str(wb.get("home", "")), {})
	if TownEcon.has_econ(town) and Vector2(wb.get("pos", town["pos"])).distance_to(town["pos"]) <= Warfare.NEAR:
		var bought := 0
		for u: Unit in wb.get("units", []):
			if bought >= 2: break # bounded acquisitions through the existing army-supply turn
			if u.dead or u.horse != null or u.race not in FigurePainter.DETAILED_RACES: continue
			if not u.is_officer() and not u.title.to_lower().contains("cavalry"): continue
			if bool(buy_for(game, town, u, payer, day).get("ok", false)): bought += 1
	var st := Supplies.stores(wb)
	for u: Unit in wb.get("units", []):
		if u.dead:
			return_mount(game, u)
			continue
		_care(game, u, day, payer, func(n: int):
			var got := mini(n, maxi(0, int(st.get("grain", 0)) - 2 * Supplies.men(wb)))
			st["grain"] = int(st.get("grain", 0)) - got
			return got)
