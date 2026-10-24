class_name Prisoners
extends RefCounted
## v0.033 prisoner ransom and exchange. Battles fill world["prisoners"] (enemy men your army took) and
## world["captives"] (your men the enemy took); see BattleRounds._take_prisoners. Each record keeps the
## actual Unit, so a freed person goes home with their own body, wounds and kit: your people as home
## reserves (Mobilization.return_freed), enemy soldiers through Army.release. Coin moves between real
## purses (your house purse, their house purse or their realm treasury); none is created.
## Actions: ransom (they pay you for one of theirs), release (free, for standing), pay (you pay for one
## of yours) and exchange (one of theirs you hold for one of yours they hold, of no lesser worth).
const PRICE := {"common": 6, "officer": 20, "noble": 60, "ruler": 150}   # coins (x Item.COIN)
const KIND_WORDS := {"common": "soldier", "officer": "officer", "noble": "noble", "ruler": "ruler"}
const LOG_LIMIT := 60

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

## Pure: what an action would do. action: "ransom" | "release" (a prisoner you hold, uid), "pay" (one of yours
## held by others, uid), "exchange" (one of yours, uid, for a prisoner of the same realm you hold, other).
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
				out["text"] = "Neither their house nor %s can pay %d coins for %s." % [CampaignWorld.faction_the(fid), _coins(cost), out["name"]]; return out
			out["payer_name"] = payer["name"]
			out["text"] = _sentence("%s pays %d coins into your house purse; %s goes home." % [payer["name"], _coins(cost), out["name"]]) + _standing_text(game, "ransom", fid, Diplomacy.RANSOM)
		"release":
			out["text"] = "%s goes home freely." % out["name"] + _standing_text(game, "release", fid, Diplomacy.RELEASE)
		"pay":
			var cost := price(game, rec)
			out["price"] = cost
			if realm.is_empty(): out["text"] = "No one in %s will bargain for %s." % [CampaignWorld.faction_name(fid), out["name"]]; return out
			if purse.is_empty() or float(purse.get("purse", 0.0)) < cost:
				out["text"] = "Your house purse cannot cover the %d coin ransom." % (_coins(cost)); return out
			out["text"] = "Pay %d coins from your house purse to %s; %s comes home." % [_coins(cost), CampaignWorld.faction_the(fid), out["name"]]
		"exchange":
			var theirs := _find(held(game), other)
			if theirs.is_empty() or not theirs.get("unit") is Unit: out["text"] = "Choose a prisoner you hold to trade."; return out
			if str(theirs.get("faction", "")) != fid:
				out["text"] = "%s can only be traded for a prisoner of %s." % [out["name"], CampaignWorld.faction_the(fid)]; return out
			if price(game, theirs) < price(game, rec):
				out["text"] = _sentence("%s will not trade a %s for a %s." % [CampaignWorld.faction_the(fid), KIND_WORDS[kind_of(game, rec)], KIND_WORDS[kind_of(game, theirs)]]); return out
			out["other_name"] = str(theirs.get("name", "?"))
			out["text"] = "%s goes home to %s; %s comes home to you." % [out["other_name"], CampaignWorld.faction_name(fid), out["name"]]
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
			text = "Exchanged %s for %s with %s." % [offer["other_name"], offer["name"], CampaignWorld.faction_the(fid)]
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

static func _log(game, text: String, day: int = -1) -> void:
	var st := state(game)
	st["log"].append({"day": int(game.day) if day < 0 else day, "text": text})
	while st["log"].size() > LOG_LIMIT: st["log"].pop_front()
	CampaignWorld.log_event(game, text)
