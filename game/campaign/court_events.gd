class_name CourtEvents
extends RefCounted
## Raw purse units are bronze cash: Barge.day_wage is normally 100/day.
## Integration hooks belong to the lead: Families.turn -> weekly; load -> after_load.
## Reviews are detached quotes, rechecked before any payment. No reader allocates state.
const BASE = {"feast": 2000, "wedding": 50000, "parade": 12000,
	"display": 15000, "monument": 120000, "statue": 60000}
const TREASURE = {"gold": 10000, "silver": 2000, "gems": 5000, "art": 8000}

static func _loc(game, uid: String) -> Dictionary:
	return Dynasty._household(game, uid)

static func _state(f: Dictionary) -> Dictionary:
	if not f.has("court"):
		f["court"] = {"earned": 0.0, "serial": 0, "last_week": -999,
			"last_event": {}, "weddings": [], "monuments": []}
	if not f.has("hoard"): f["hoard"] = []
	return f["court"]

static func _folk(town: Dictionary, uid: String) -> Array:
	var out: Array = []
	for f: Dictionary in town.get("econ", {}).get("fams", []):
		if not f.get("gone", false) and not f.get("estate", false) and str(f.get("household_uid", "")) != uid:
			out.append(f)
	return out

static func _income(f: Dictionary) -> float:
	# Native f.inc is NET coin income normalized to seven days (families.gd:858).
	return maxf(0.0, float(f.get("inc", 0.0))) * 120.0 / 7.0

static func safe_keep(game, uid: String) -> int:
	var loc: Dictionary = _loc(game, uid)
	if loc.is_empty(): return 0
	var f: Dictionary = loc["family"]
	var e: Dictionary = loc["town"].get("econ", {})
	var wage: float = Barge.day_wage(e)
	var food: float = EconomyRules.essential_food_cost(e, float(Families.daily_rates(e, f)["food"]) * 30.0)
	var pay: float = 0.0
	if str(game.world.get("player_house", {}).get("household_uid", "")) == uid:
		pay = float(game.daily_wages()) * 14.0
	var war: bool = not Diplomacy.enemies_at_war(game.world, str(loc["town"].get("faction", ""))).is_empty()
	return int(ceil((maxf(wage * 200.0, _income(f) * 0.25) + food + pay) * (1.5 if war else 1.0) + maxf(0.0, float(f.get("debt", 0.0)))))

static func expected_yearly_cost(game, uid: String) -> int:
	var loc: Dictionary = _loc(game, uid)
	if loc.is_empty(): return 0
	var f: Dictionary = loc["family"]
	var surplus: float = maxf(0.0, float(f.get("purse", 0.0)) - safe_keep(game, uid))
	return int(floor(_income(f) * 0.55 + surplus * 0.90))

static func _matching(game, uid: String, gem: String) -> bool:
	for d: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		if bool(d.get("alive", false)) and str(d.get("owner_household_uid", "")) == uid and str(d.get("gem_id", "")) == gem:
			return true
	return false

static func _treasure_prestige(game, uid: String, row: Dictionary) -> float:
	var value: float = float(row.get("unit_cost", 0)) * int(row.get("quantity", 0))
	var extra: float = 1.2 if str(row.get("category", "")) == "gems" and _matching(game, uid, str(row.get("gem_id", ""))) else 1.0
	return value / 5000.0 * extra

static func _refresh(game, uid: String, f: Dictionary) -> void:
	var st: Dictionary = _state(f)
	var value: float = float(st.get("earned", 0.0))
	for row: Dictionary in f["hoard"]: value += _treasure_prestige(game, uid, row)
	for row: Dictionary in st["monuments"]:
		if bool(row.get("complete", false)): value += float(row.get("prestige", 0.0))
	# Preserve prestige contributed by other systems.
	f["prestige"] = maxf(0.0, float(f.get("prestige", 0.0)) - float(f.get("court_prestige", 0.0)) + value)
	f["court_prestige"] = value

static func hoard_view(game, uid: String) -> Array:
	var loc: Dictionary = _loc(game, uid)
	var out: Array = []
	if loc.is_empty(): return out
	for row: Dictionary in loc["family"].get("hoard", []):
		var copy: Dictionary = row.duplicate(true)
		copy["value"] = int(row.get("unit_cost", 0)) * int(row.get("quantity", 0))
		copy["sale_value"] = int(floor(float(row.get("unit_cost", 0)) * 0.6)) * int(row.get("quantity", 0))
		copy["prestige"] = _treasure_prestige(game, uid, row)
		copy["gem_match"] = str(row.get("category", "")) == "gems" and _matching(game, uid, str(row.get("gem_id", "")))
		out.append(copy)
	return out

static func _wedding(game, uid: String, args: Dictionary) -> Dictionary:
	var loc: Dictionary = _loc(game, uid)
	if loc.is_empty(): return {}
	var used: Array = loc["family"].get("court", {}).get("weddings", [])
	# Marriage.wed records the original spouse household BEFORE moving the spouse.
	for other_uid in game.world.get("marriage", {}).get("alliances", {}):
		var al: Dictionary = game.world["marriage"]["alliances"][other_uid]
		var member: String = str(al.get("member_uid", ""))
		var spouse: String = str(al.get("spouse_uid", ""))
		var token: String = member + "|" + spouse
		if token in used or int(game.day) - int(al.get("day", -999)) not in range(0, 8): continue
		if args.has("member_uid") and str(args["member_uid"]) != member: continue
		if not Marriage.alliance_holds(game, al): continue
		var person: Dictionary = Dynasty._person(game, member)
		if person.is_empty() or str(person["family"].get("household_uid", "")) != uid: continue
		return {"token": token, "to_house": str(other_uid)}
	return {}

static func _target(game, house: String) -> Dictionary:
	if house == "": return {}
	# Accept an exact ruling household UID, seat town ID, birth-house UID or realm ID.
	var exact: Dictionary = _loc(game, house)
	if not exact.is_empty():
		var t: Dictionary = exact["town"]
		return exact if str(Feudal.tax_recipient(game, str(t["id"])).get("household_uid", "")) == house else {}
	for t: Dictionary in game.world.get("towns", {}).values():
		var f: Dictionary = Feudal.tax_recipient(game, str(t["id"]))
		if f.is_empty(): continue
		if house == str(t["id"]) or house == str(t.get("econ", {}).get("head", {}).get("house_uid", "")):
			return {"town": t, "family": f}
		if house == str(t.get("faction", "")) and str(game.world.get("factions", {}).get(house, {}).get("capital", "")) == str(t["id"]):
			return {"town": t, "family": f}
	return {}

static func _kind(kind: String) -> String:
	return str({"party": "feast", "grand_wedding": "wedding", "display_of_wealth": "display"}.get(kind, kind))

static func preview(game, uid: String, kind: String, args: Dictionary = {}) -> Dictionary:
	kind = _kind(kind)
	var out: Dictionary = {"ok": false, "reason": "", "cost": 0, "effects": {},
		"household_uid": uid, "kind": kind, "args": args.duplicate(true), "day": int(game.day)}
	var loc: Dictionary = _loc(game, uid)
	if loc.is_empty(): out["reason"] = "A living household is required."; return out
	var f: Dictionary = loc["family"]
	var town: Dictionary = loc["town"]
	var cost: int = 0
	var effects: Dictionary = {}
	if kind == "gift":
		var target: Dictionary = _target(game, str(args.get("to_house", "")))
		if target.is_empty() or is_same(target["family"], f):
			out["reason"] = "Choose another ruling household."; return out
		cost = int(args.get("amount", 0))
		effects = {"to_house": str(target["family"]["household_uid"]), "relations": minf(12.0, float(cost) / 5000.0)}
	elif kind == "treasure":
		var category: String = str(args.get("category", "gold"))
		if not TREASURE.has(category): out["reason"] = "Unknown treasure."; return out
		var quantity: int = int(args.get("quantity", 1))
		if quantity < 1 or quantity > 1000: out["reason"] = "Choose 1 to 1000 pieces."; return out
		var gem: String = str(args.get("gem_id", ""))
		if category == "gems":
			var valid: bool = false
			for row: Dictionary in Dragons.catalogs()["gems"]:
				if str(row["id"]) == gem: valid = true
			if not valid: out["reason"] = "Choose a dragon-catalog gem."; return out
		cost = int(TREASURE[category]) * quantity
		effects = {"category": category, "gem_id": gem, "quantity": quantity, "unit_cost": int(TREASURE[category])}
	else:
		if not BASE.has(kind): out["reason"] = "Unknown court event."; return out
		cost = maxi(int(BASE[kind]), int(args.get("amount", BASE[kind])))
		var scale: float = minf(4.0, sqrt(float(cost) / float(BASE[kind])))
		effects = {"prestige": (1.0 if kind == "feast" else 6.0) * scale}
		if kind == "feast": effects["opinion"] = 3.0 * scale
		if kind == "wedding":
			var wedding: Dictionary = _wedding(game, uid, args)
			if wedding.is_empty(): out["reason"] = "A new actual Marriage.wed marriage is required."; return out
			effects.merge(wedding); effects["relations"] = 8.0; effects["prestige"] = 20.0 * scale
		if kind == "parade":
			var recent: bool = int(game.day) - int(f.get("court", {}).get("victory_day", -999)) in range(0, 8)
			effects["recent_victory"] = recent
			effects["prestige"] = 12.0 * scale if recent else 6.0 * scale
			effects["morale"] = 10.0 if recent else 5.0
		if kind == "display": effects["relations"] = 2.0 * scale
		if kind in ["monument", "statue"]:
			var tid: String = str(args.get("town_id", town["id"]))
			if tid != str(town["id"]): out["reason"] = "Build at this household's town or seat."; return out
			for row: Dictionary in f.get("court", {}).get("monuments", []):
				if str(row.get("town_id", "")) == tid and str(row.get("kind", "")) == kind:
					out["reason"] = "This monument is already commissioned."; return out
			effects = {"town_id": tid, "build_days": 28 if kind == "monument" else 14,
				"prestige": 30.0 * scale, "grievance_relief": 8.0}
		else:
			var last: int = int(f.get("court", {}).get("last_event", {}).get(kind, -999))
			if int(game.day) - last < (7 if kind == "feast" else 28):
				out["reason"] = "The court needs time between celebrations."; return out
	if cost <= 0: out["reason"] = "The amount must be positive."; return out
	out["cost"] = cost; out["effects"] = effects
	if float(f.get("purse", 0.0)) < cost: out["reason"] = "Not enough coin."; return out
	if kind != "gift" and _folk(town, uid).is_empty():
		out["reason"] = "No local households can supply the work."; return out
	out["ok"] = true; out["reason"] = "Real household payments; no debt."
	return out

static func _relations(game, town: Dictionary, target: Dictionary, amount: float) -> void:
	var a: String = str(town.get("faction", ""))
	var b: String = str(target.get("faction", ""))
	Diplomacy._push(game.world, a, b, amount)
	if a == b:
		var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(str(target.get("id", "")), {})
		if not row.is_empty():
			row["loyalty"] = minf(100.0, float(row.get("loyalty", 0.0)) + amount)
			row["grievance"] = maxf(0.0, float(row.get("grievance", 0.0)) - amount)

static func _relief(game, tid: String, amount: float) -> void:
	var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(tid, {})
	if not row.is_empty(): row["grievance"] = maxf(0.0, float(row.get("grievance", 0.0)) - amount)

static func hold(game, uid: String, kind: String, args: Dictionary = {}, review: Dictionary = {}) -> Dictionary:
	kind = _kind(kind)
	var quote: Dictionary = preview(game, uid, kind, args)
	if not bool(quote["ok"]): return quote
	if review.is_empty() or JSON.stringify(review) != JSON.stringify(quote):
		return {"ok": false, "reason": "Review the current court quote.", "cost": 0, "effects": {}}
	var loc: Dictionary = _loc(game, uid)
	var f: Dictionary = loc["family"]
	var town: Dictionary = loc["town"]
	var st: Dictionary = _state(f)
	var cost: int = int(quote["cost"])
	var fx: Dictionary = quote["effects"]
	if kind == "gift":
		var target: Dictionary = _loc(game, str(fx["to_house"]))
		f["purse"] = float(f["purse"]) - cost
		target["family"]["purse"] = float(target["family"].get("purse", 0.0)) + cost
		_relations(game, town, target["town"], float(fx["relations"]))
	else:
		var recipients: Array = _folk(town, uid)
		# Entertainment, catering, craft and building commissions pay native purses.
		# Integer apportionment, including the remainder, conserves every coin.
		f["purse"] = float(f["purse"]) - cost
		var per: int = int(cost / recipients.size())
		var remainder: int = cost - per * recipients.size()
		for i in recipients.size():
			recipients[i]["purse"] = float(recipients[i].get("purse", 0.0)) + per + (1 if i < remainder else 0)
	if kind == "treasure":
		st["serial"] = int(st.get("serial", 0)) + 1
		var row: Dictionary = fx.duplicate(true)
		row["id"] = "%s:treasure:%d" % [uid, int(st["serial"])]
		f["hoard"].append(row)
	elif kind in ["monument", "statue"]:
		var row: Dictionary = fx.duplicate(true)
		row["kind"] = kind; row["due_day"] = int(game.day) + int(fx["build_days"]); row["complete"] = false
		st["monuments"].append(row)
	elif kind != "gift":
		st["earned"] = float(st.get("earned", 0.0)) + float(fx.get("prestige", 0.0))
		st["last_event"][kind] = int(game.day)
		if kind == "wedding":
			st["weddings"].append(str(fx["token"]))
			var spouse_house: Dictionary = _loc(game, str(fx["to_house"]))
			if not spouse_house.is_empty(): _relations(game, town, spouse_house["town"], float(fx["relations"]))
		if kind == "feast":
			f["court_opinion"] = minf(100.0, float(f.get("court_opinion", 0.0)) + float(fx["opinion"]))
			_relief(game, str(town["id"]), float(fx["opinion"]))
			for tid in Feudal._vassals(game.world, str(town["id"])):
				var target: Dictionary = game.world["towns"].get(tid, {})
				if not target.is_empty(): _relations(game, town, target, float(fx["opinion"]))
		if kind == "parade":
			_relief(game, str(town["id"]), float(fx["morale"]))
			for u in game.company:
				if not u.dead and str(u.home_town) == str(town["id"]):
					Food.add_stress(u, -float(fx["morale"])); u.merry_day = float(game.day)
		if kind == "display":
			var seen: Dictionary = {}
			for target: Dictionary in game.world.get("towns", {}).values():
				if str(target["id"]) == str(town["id"]): continue
				var key: String = str(target["id"]) if str(target.get("faction", "")) == str(town.get("faction", "")) else str(target.get("faction", ""))
				if not seen.has(key): _relations(game, town, target, float(fx["relations"])); seen[key] = true
	_refresh(game, uid, f)
	return quote

static func gift(game, from_household_uid: String, to_house: String, amount: int) -> Dictionary:
	var args: Dictionary = {"to_house": to_house, "amount": amount}
	return hold(game, from_household_uid, "gift", args, preview(game, from_household_uid, "gift", args))

static func sell_hoard(game, uid: String, treasure_id: String, quantity: int = 1) -> Dictionary:
	var loc: Dictionary = _loc(game, uid)
	if loc.is_empty(): return {"ok": false, "coin": 0}
	var f: Dictionary = loc["family"]
	var e: Dictionary = loc["town"].get("econ", {})
	var index: int = int(e.get("mkt", -1))
	var businesses: Array = e.get("biz", [])
	if index < 0 or index >= businesses.size(): return {"ok": false, "coin": 0}
	var buyer: Dictionary = businesses[index]
	for row: Dictionary in f.get("hoard", []):
		if str(row.get("id", "")) != treasure_id: continue
		var price: int = int(floor(float(row["unit_cost"]) * 0.6))
		if price <= 0: return {"ok": false, "coin": 0}
		var n: int = mini(maxi(0, quantity), mini(int(row["quantity"]), int(maxf(0.0, float(buyer.get("till", 0.0))) / price)))
		if n <= 0: return {"ok": false, "coin": 0}
		var stock: Dictionary = row.duplicate(true); stock["quantity"] = n
		if not buyer.has("court_stock"): buyer["court_stock"] = []
		buyer["court_stock"].append(stock)
		var paid: int = price * n
		buyer["till"] = float(buyer["till"]) - paid
		f["purse"] = float(f.get("purse", 0.0)) + paid
		row["quantity"] = int(row["quantity"]) - n
		if int(row["quantity"]) == 0: f["hoard"].erase(row)
		_refresh(game, uid, f)
		return {"ok": true, "coin": paid, "quantity": n}
	return {"ok": false, "coin": 0}

static func seize_hoard(game, uid: String, share: float) -> Array:
	# Physical whole pieces, no cash conversion. Caller MUST assign returned
	# rows to the raider's hoard/loot; this hook never invents raid proceeds.
	var loc: Dictionary = _loc(game, uid)
	var loot: Array = []
	if loc.is_empty() or not is_finite(share): return loot
	var f: Dictionary = loc["family"]
	for row: Dictionary in f.get("hoard", []).duplicate():
		var n: int = int(floor(int(row["quantity"]) * clampf(share, 0.0, 1.0)))
		if n <= 0: continue
		var taken: Dictionary = row.duplicate(true); taken["quantity"] = n
		loot.append(taken)
		row["quantity"] = int(row["quantity"]) - n
		if int(row["quantity"]) == 0: f["hoard"].erase(row)
	_refresh(game, uid, f)
	return loot

static func need_coin(game, uid: String, amount: int, reason: String) -> int:
	# amount is ADDITIONAL cash requested; return actual cash raised, not a promise.
	var raised: int = 0
	for row: Dictionary in hoard_view(game, uid):
		if raised >= amount: break
		var price: int = int(floor(float(row["unit_cost"]) * 0.6))
		if price <= 0: continue
		var n: int = mini(int(row["quantity"]), int(ceil(float(amount - raised) / price)))
		raised += int(sell_hoard(game, uid, str(row["id"]), n).get("coin", 0))
	var loc: Dictionary = _loc(game, uid)
	if not loc.is_empty() and raised > 0:
		_state(loc["family"])["last_sale"] = {"day": int(game.day), "coin": raised, "reason": reason}
	return raised

static func weekly(game, town: Dictionary, e: Dictionary, f: Dictionary) -> void:
	var uid: String = str(f.get("household_uid", ""))
	if uid == "" or f.get("gone", false) or f.get("estate", false) or f.get("cohort", false): return
	var loc: Dictionary = _loc(game, uid)
	if loc.is_empty() or not is_same(loc["family"], f) or not is_same(loc["town"], town) or not is_same(town.get("econ", {}), e): return
	var st: Dictionary = _state(f)
	# Completion is delayed, persistent, and applies grievance relief exactly once.
	for row: Dictionary in st["monuments"]:
		if not bool(row.get("complete", false)) and int(game.day) >= int(row["due_day"]):
			row["complete"] = true
			_relief(game, str(row["town_id"]), float(row["grievance_relief"]))
	_refresh(game, uid, f)
	if str(game.world.get("player_house", {}).get("household_uid", "")) == uid:
		var wins: int = int(game.world.get("warfare", {}).get("battles_won", 0))
		if st.has("wins_seen") and wins > int(st["wins_seen"]): st["victory_day"] = int(game.day)
		st["wins_seen"] = wins
	var week: int = int(floor(float(game.day) / 7.0))
	if int(st.get("last_week", -999)) == week: return
	st["last_week"] = week
	var keep: int = safe_keep(game, uid)
	if float(f.get("purse", 0.0)) < keep:
		need_coin(game, uid, int(ceil(keep - float(f.get("purse", 0.0)))), "troops, war and household reserve")
		return
	if float(f.get("debt", 0.0)) > 0.0: return
	var budget: int = mini(int(floor(float(f["purse"]) - keep)), int(floor(expected_yearly_cost(game, uid) * 7.0 / 120.0)))
	if budget < int(BASE["feast"]): return
	var wealth: float = float(f["purse"])
	var held: int = 0
	for row: Dictionary in hoard_view(game, uid): held += int(row["value"])
	var gap: int = maxi(0, int(wealth * 0.25) - held)
	if gap >= 2000:
		var category: String = "gold" if budget >= 30000 else "silver"
		var gem: String = ""
		for d: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
			if bool(d.get("alive", false)) and str(d.get("owner_household_uid", "")) == uid and budget >= 15000:
				category = "gems"; gem = str(d.get("gem_id", "")); break
		var n: int = mini(1000, int(mini(gap, int(budget / 3)) / int(TREASURE[category])))
		if n > 0:
			var args: Dictionary = {"category": category, "quantity": n, "gem_id": gem}
			var result: Dictionary = hold(game, uid, "treasure", args, preview(game, uid, "treasure", args))
			if result.get("ok", false): budget -= int(result["cost"])
	var kind: String = "feast"
	if not _wedding(game, uid, {}).is_empty() and budget >= 50000: kind = "wedding"
	elif budget >= 120000 and int(week) % 4 == 0: kind = "monument"
	elif budget >= 12000 and int(game.day) - int(st.get("victory_day", -999)) in range(0, 8): kind = "parade"
	elif budget >= 15000 and week % 4 == 2: kind = "display"
	elif budget >= 5000 and week % 4 == 3:
		for t: Dictionary in game.world.get("towns", {}).values():
			var recipient: Dictionary = Feudal.tax_recipient(game, str(t["id"]))
			if not recipient.is_empty() and str(recipient.get("household_uid", "")) != uid and not Diplomacy.at_war(game.world, str(town.get("faction", "")), str(t.get("faction", ""))):
				gift(game, uid, str(recipient["household_uid"]), budget)
				return
	var args: Dictionary = {"amount": budget}
	var quote: Dictionary = preview(game, uid, kind, args)
	if not quote.get("ok", false):
		kind = "feast"; quote = preview(game, uid, kind, args)
	hold(game, uid, kind, args, quote)

static func after_load(game) -> void:
	for town: Dictionary in game.world.get("towns", {}).values():
		for f: Dictionary in town.get("econ", {}).get("fams", []):
			if not f.has("court") and not f.has("hoard"): continue
			var st: Dictionary = _state(f)
			for key in ["serial", "last_week", "wins_seen", "victory_day"]:
				if st.has(key): st[key] = int(st[key])
			for key in st["last_event"]: st["last_event"][key] = int(st["last_event"][key])
			if st.get("last_sale") is Dictionary:
				st["last_sale"]["day"] = int(st["last_sale"]["day"])
				st["last_sale"]["coin"] = int(st["last_sale"]["coin"])
			for row: Dictionary in f["hoard"]:
				row["unit_cost"] = int(row["unit_cost"]); row["quantity"] = int(row["quantity"])
			for row: Dictionary in st["monuments"]:
				row["due_day"] = int(row["due_day"]); row["build_days"] = int(row["build_days"])
			var index: int = int(town.get("econ", {}).get("mkt", -1))
			var businesses: Array = town.get("econ", {}).get("biz", [])
			if index >= 0 and index < businesses.size():
				for row: Dictionary in businesses[index].get("court_stock", []):
					row["unit_cost"] = int(row["unit_cost"]); row["quantity"] = int(row["quantity"])
			_refresh(game, str(f.get("household_uid", "")), f)
