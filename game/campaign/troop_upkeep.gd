class_name TroopUpkeep
extends RefCounted
## Household troop wages and weapons/armour upkeep. Coin is conserved: wages move from the
## ruling house purse into the retainers' real family or cohort purses, and repairs are bought
## from the town smith (TownEcon.pay_market, then the same coins move into the smith's till).
##
## Already charged — this file does not call these paths and does not spend the army purse
## (game.gold), a faction treasury, or a town treasury:
##   campaign/mobilization.gd:390 muster — hire fees, shop weapons, food and v0.029 armour
##     (body/helm, padded fallback) all leave the army purse (game.gold) at 425, 441, 455-462, 467-468.
##   campaign/mobilization.gd:478 refit_quote / :511 refit — missing body armour and helms
##     bought from the town, still the army purse (535), with three days of field pay held back (487).
##   campaign/army.gd:596 pay_chunk / :703 pay_units — raised-army payroll from the faction
##     treasury into soldiers' family purses. :813 pay_town — garrison/militia from the town
##     treasury when the band is mustered or drilling (823), not from the house purse.
##   campaign/army.gd:448 fight_pay — a day's field wage from the faction treasury after a battle
##     (campaign/world.gd:1689). campaign/people.gd:673 pay_company is what Game.pay_wages
##     (core/game.gd:160) pays through CampaignWorld.wages_paid (world.gd:1542). :695 pay_militia
##     is pay_town. :701 pay_crews pays caravan crews from the market till.
##   campaign/arms_trade.gd:354 econ_daily — militia re-kit; the treasury buys short classes
##     off the stalls (401). :477 arms_reserve holds the garrison wage bill back from that
##     purchase. :610 order_buy — the treasury pays a smith for an armory order.
##   campaign/arms_pool.gd — skill, experience and conditioning only; no coin.
##   Item.wear (core/item.gd:9) is already dented in the fight (sim/battle_sim.gd gear_wear)
##     and read by loot (core/loot.gd battle_wear). Neither charges a purse. Battle results
##     land in CampaignWorld.on_battle_result (world.gd:1634); the lead wires on_battle_end
##     beside that. Wear here is raised only up to the damage taken, so a sim that already
##     set the same wear is not charged twice, and refit is never called.
##
## Standing retinue: the ruling house's own guards (the town head's household). Not the
## treasury garrison and not men on the company roll. Size follows feudal rank plus purse.
## Unpaid weeks, men leave. The count never goes below zero.

const WAGE_WEEK: float = 180.0       # coins per retainer per week, from the house purse
const KEEP_WEEK: float = 32.0        # peacetime kit maintenance per retainer per week
const WEEKS_YEAR: float = 52.0
const WEALTH_STEP: float = 40000.0   # one extra man per this much purse
const WEALTH_CAP: int = 24
const MAX_MEN: int = 60
const PEACE_DROP: float = 4.0        # kit condition lost each week before maintenance
const REPAIR_PER: float = 55.0       # coins per wear step the smith beats back out
const BASE_SOVEREIGN: int = 30
const BASE_COUNTY: int = 14
const BASE_VILLAGE: int = 6

static var _live: Dictionary = {}   # uid -> Unit, this session only (not saved)

static func _state(game) -> Dictionary:
	if game == null or not (game.world is Dictionary):
		return {"v": 1, "houses": {}, "units": {}}
	if not game.world.has("troop_upkeep"):
		game.world["troop_upkeep"] = {"v": 1, "houses": {}, "units": {}}
	return game.world["troop_upkeep"]

static func _houses(game) -> Dictionary:
	var st: Dictionary = _state(game)
	if not st.has("houses"):
		st["houses"] = {}
	return st["houses"]

static func _units(game) -> Dictionary:
	var st: Dictionary = _state(game)
	if not st.has("units"):
		st["units"] = {}
	return st["units"]

static func _house(game, uid: String) -> Dictionary:
	var houses: Dictionary = _houses(game)
	if uid == "":
		return {"n": 0, "target": 0, "unpaid": 0, "men": [], "kit": 100.0, "repair": 0.0}
	if not houses.has(uid):
		houses[uid] = {"n": 0, "target": 0, "unpaid": 0, "men": [], "kit": 100.0, "repair": 0.0}
	return houses[uid]

static func _rules(e: Dictionary, f: Dictionary) -> bool:
	if f.is_empty() or f.get("gone", false) or f.has("estate"):
		return false
	var head: Dictionary = e.get("head", {})
	if head.is_empty():
		return false
	return int(head.get("fam", -999)) == int(f.get("id", -998))

## The campaign house pays its own kit bill. That household is often the head person's
## family, not the econ head.fam row that stands the retinue.
static func _is_player_house(game, f: Dictionary) -> bool:
	if game == null or not (game.world is Dictionary) or f.is_empty():
		return false
	var p_uid: String = str(game.world.get("player_house", {}).get("household_uid", ""))
	var f_uid: String = str(f.get("household_uid", ""))
	return p_uid != "" and f_uid != "" and p_uid == f_uid

static func _target_n(game, town: Dictionary, f: Dictionary) -> int:
	var tid: String = str(town.get("id", ""))
	var tier: String = str(game.world.get("feudal", {}).get("towns", {}).get(tid, {}).get("tier", ""))
	var base: int = BASE_COUNTY
	if tier == "sovereign" or bool(town.get("capital", false)):
		base = BASE_SOVEREIGN
	elif tier == "village" or int(town.get("size", 1)) < 2:
		base = BASE_VILLAGE
	var extra: int = mini(WEALTH_CAP, int(float(f.get("purse", 0.0)) / WEALTH_STEP))
	return mini(MAX_MEN, maxi(0, base + extra))

static func _count_men(men: Array) -> int:
	var n: int = 0
	for row in men:
		if row is Dictionary:
			n += maxi(0, int((row as Dictionary).get("n", 0)))
	return n

static func _men_of(row: Dictionary) -> Array:
	var raw: Variant = row.get("men", [])
	if raw is Array:
		return raw
	return []

static func _shrink(row: Dictionary, by: int) -> void:
	var left: int = maxi(0, by)
	var men: Array = _men_of(row)
	while left > 0 and not men.is_empty():
		var last: Dictionary = men[men.size() - 1]
		var have: int = maxi(0, int(last.get("n", 0)))
		var cut: int = mini(have, left)
		last["n"] = have - cut
		left -= cut
		if int(last["n"]) <= 0:
			men.pop_back()
	row["men"] = men
	row["n"] = _count_men(men)

static func _held(men: Array, fid: int) -> int:
	var n: int = 0
	for row in men:
		if row is Dictionary and int((row as Dictionary).get("fid", -1)) == fid:
			n += int((row as Dictionary).get("n", 0))
	return n

static func _push_men(men: Array, tid: String, fid: int, add: int) -> void:
	if add <= 0:
		return
	for row in men:
		if row is Dictionary and int((row as Dictionary).get("fid", -1)) == fid:
			(row as Dictionary)["n"] = int((row as Dictionary).get("n", 0)) + add
			return
	men.append({"tid": tid, "fid": fid, "n": add})

static func _assign(town: Dictionary, e: Dictionary, row: Dictionary, want: int) -> void:
	var men: Array = []
	var left: int = maxi(0, want)
	var head: int = int(e.get("head", {}).get("fam", -1))
	var fams: Array = e.get("fams", [])
	var tid: String = str(town.get("id", ""))
	var pass_n: int = 0
	while left > 0 and pass_n < 2:
		for i in fams.size():
			if left <= 0:
				break
			if i == head:
				continue
			var fam: Dictionary = fams[i]
			if fam.get("gone", false) or fam.has("estate"):
				continue
			var free: int = maxi(0, Families.adults(fam) - Families.serving(fam) - _held(men, i))
			if pass_n == 0:
				free = mini(free, maxi(0, Population.spare(fam) - _held(men, i)))
			if free <= 0:
				continue
			var take: int = mini(left, mini(free, 6))
			_push_men(men, tid, i, take)
			left -= take
		pass_n += 1
	row["men"] = men
	row["n"] = _count_men(men)

static func _credit(game, men: Array, amount: float) -> Dictionary:
	var out: Dictionary = {"paid": 0.0, "families": 0}
	var total_n: int = _count_men(men)
	if total_n <= 0 or amount <= 0.0 or game == null:
		return out
	var counted: int = 0
	for row in men:
		if row is Dictionary and int((row as Dictionary).get("n", 0)) > 0:
			counted += 1
	var sent: float = 0.0
	var seen: int = 0
	var families: int = 0
	for row in men:
		if not (row is Dictionary):
			continue
		var m: Dictionary = row
		var n: int = int(m.get("n", 0))
		if n <= 0:
			continue
		seen += 1
		var share: float = amount * float(n) / float(total_n)
		if seen == counted:
			share = amount - sent
		var town: Dictionary = game.world.get("towns", {}).get(str(m.get("tid", "")), {})
		var fam: Dictionary = People.fam_of(town, int(m.get("fid", -1)))
		if fam.is_empty() or fam.get("gone", false):
			continue
		fam["purse"] = float(fam.get("purse", 0.0)) + share
		sent += share
		families += 1
	out["paid"] = sent
	out["families"] = families
	return out

static func _smith(e: Dictionary) -> Dictionary:
	var fallback: Dictionary = {}
	for b in e.get("biz", []):
		if not (b is Dictionary):
			continue
		var biz: Dictionary = b
		var typ: String = str(biz.get("type", ""))
		if typ != "armorsmith" and typ != "weaponsmith":
			continue
		if typ == "armorsmith":
			return biz
		if fallback.is_empty():
			fallback = biz
	return fallback

## House purse -> market (the household purchase helper) -> smith till. Market nets zero.
static func _buy_smith(e: Dictionary, f: Dictionary, smith: Dictionary, cost: float) -> float:
	if cost <= 0.0 or smith.is_empty() or f.is_empty() or not e.has("mkt"):
		return 0.0
	var biz: Array = e.get("biz", [])
	var idx: int = int(e.get("mkt", -1))
	if idx < 0 or idx >= biz.size():
		return 0.0
	var afford: float = maxf(0.0, float(f.get("purse", 0.0)) - 1.0)
	var pay: float = minf(cost, afford)
	if pay <= 0.01:
		return 0.0
	TownEcon.pay_market(e, f, pay)
	var mkt: Dictionary = biz[idx]
	mkt["till"] = float(mkt.get("till", 0.0)) - pay
	smith["till"] = float(smith.get("till", 0.0)) + pay
	return pay

static func _can_repair(game, town: Dictionary) -> bool:
	if town.is_empty() or _smith(town.get("econ", {})).is_empty():
		return false
	var tid: String = str(town.get("id", ""))
	if str(game.location) == tid:
		return true
	var pos: Vector2 = game.world.get("party", {}).get("pos", Vector2(999999.0, 999999.0))
	var at: Vector2 = town.get("pos", Vector2.ZERO)
	return pos.distance_to(at) <= 48.0

static func _kit_item(it: Item) -> bool:
	if it == null or it.broken:
		return false
	if it.is_weapon() or DB.is_bow(it.tid):
		return true
	var slot: String = str(it.tmpl().get("slot", ""))
	return slot == "body" or slot == "helm" or slot == "legs" or slot == "hands" or slot == "feet" or slot == "shield"

static func _hurt(u: Unit, result: Dictionary) -> float:
	var raw: Variant = result.get("gear_damage", null)
	if raw is Dictionary and (raw as Dictionary).has(str(u.uid)):
		return clampf(float((raw as Dictionary)[str(u.uid)]), 0.0, 1.0)
	if u.body != null and u.body.blood_max > 1.0:
		var lost: float = (u.body.blood_max - u.body.blood) / u.body.blood_max
		if lost > 0.02:
			return clampf(lost, 0.0, 1.0)
	return 0.0

static func _want_wear(hurt: float) -> int:
	if hurt <= 0.02:
		return 0
	return clampi(int(ceil(hurt * 3.0 - 0.0001)), 1, 3)

static func _wear_unit(game, u: Unit, hurt: float) -> int:
	var want: int = _want_wear(hurt)
	if want <= 0:
		return 0
	var book: Dictionary = _units(game)
	var rec: Dictionary = {}
	if book.has(str(u.uid)) and book[str(u.uid)] is Dictionary:
		rec = book[str(u.uid)]
	else:
		rec = {"cond": 100.0, "wear": 0, "steps": 0}
		book[str(u.uid)] = rec
	_live[str(u.uid)] = u
	var applied: int = 0
	var worst: int = 0
	var any_kit: bool = false
	if not rec.has("slots") or not (rec["slots"] is Dictionary):
		rec["slots"] = {}
	var slots: Dictionary = rec["slots"]
	for key in u.equip.keys():
		var it: Item = u.equip[key] as Item
		if not _kit_item(it):
			continue
		any_kit = true
		var slot_name: String = str(key)
		if not slots.has(slot_name):
			slots[slot_name] = int(it.wear)
		var before: int = int(it.wear)
		if before < want:
			it.wear = want
			applied += want - before
		worst = maxi(worst, int(it.wear))
	if not any_kit:
		var cond: float = float(rec.get("cond", 100.0))
		rec["cond"] = maxf(0.0, cond - float(want) * 25.0)
		applied += want
		worst = mini(3, int(ceil((100.0 - float(rec["cond"])) / 25.0)))
	else:
		rec["cond"] = maxf(0.0, 100.0 - float(worst) * 25.0)
	rec["wear"] = worst
	rec["steps"] = int(rec.get("steps", 0)) + applied
	return applied

static func _restore_units(game) -> void:
	var book: Dictionary = _units(game)
	for uid in book.keys():
		if not (book[uid] is Dictionary):
			continue
		var rec: Dictionary = book[uid]
		var slots_raw: Variant = rec.get("slots", {})
		if not (slots_raw is Dictionary):
			rec["cond"] = 100.0
			rec["wear"] = 0
			continue
		var slots: Dictionary = slots_raw
		var u: Variant = _live.get(str(uid), null)
		if u is Unit:
			for slot_name in slots.keys():
				if (u as Unit).equip.has(str(slot_name)):
					var it: Item = (u as Unit).equip[str(slot_name)] as Item
					if it != null:
						it.wear = int(slots[slot_name])
		rec["cond"] = 100.0
		rec["wear"] = 0
		rec["steps"] = 0
		rec.erase("slots")

static func _pay_due(game, town: Dictionary, e: Dictionary, f: Dictionary, row: Dictionary) -> float:
	var due: float = float(row.get("repair", 0.0))
	if due <= 0.01 or not _can_repair(game, town):
		return 0.0
	var paid: float = _buy_smith(e, f, _smith(e), due)
	row["repair"] = maxf(0.0, due - paid)
	if float(row["repair"]) <= 0.5:
		row["repair"] = 0.0
		_restore_units(game)
	return paid

static func weekly(game, town: Dictionary, e: Dictionary, f: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": false, "retinue": 0, "target": 0, "left": 0, "wages_paid": 0.0,
		"wage_bill": 0.0, "maintenance_paid": 0.0, "repair_paid": 0.0, "recipients": 0, "household_uid": ""}
	if game == null or town.is_empty() or e.is_empty() or f.is_empty():
		return out
	# Retinue wages stay with the town head. Battle wear is booked on the player house
	# (on_battle_end) and is paid here once that house is home, even when it does not rule.
	if not _rules(e, f):
		if _is_player_house(game, f):
			var home_uid: String = str(f.get("household_uid", ""))
			if home_uid == "":
				return out
			out["household_uid"] = home_uid
			var home_paid: float = _pay_due(game, town, e, f, _house(game, home_uid))
			out["repair_paid"] = home_paid
			out["ok"] = home_paid > 0.0
		return out
	var uid: String = str(f.get("household_uid", ""))
	if uid == "":
		return out
	out["household_uid"] = uid
	var row: Dictionary = _house(game, uid)
	var want: int = _target_n(game, town, f)
	row["target"] = want
	var unpaid: int = int(row.get("unpaid", 0))
	var n_now: int = maxi(0, int(row.get("n", 0)))
	if unpaid == 0 and float(f.get("purse", 0.0)) >= float(want) * WAGE_WEEK:
		_assign(town, e, row, want)
	elif unpaid == 0 and n_now > want:
		_shrink(row, n_now - want)
	elif n_now > 0 and _count_men(_men_of(row)) <= 0:
		_assign(town, e, row, n_now)
	var n: int = maxi(0, int(row.get("n", 0)))
	var bill: float = float(n) * WAGE_WEEK
	var credited: Dictionary = {"paid": 0.0, "families": 0}
	var afford: float = maxf(0.0, float(f.get("purse", 0.0)) - 1.0)
	var wage_pay: float = minf(bill, afford)
	if wage_pay > 0.0:
		credited = _credit(game, _men_of(row), wage_pay)
		var got: float = float(credited.get("paid", 0.0))
		f["purse"] = float(f.get("purse", 0.0)) - got
		wage_pay = got
	if bill > 0.01 and wage_pay + 0.01 < bill and n > 0:
		var cut: int = maxi(1, int(float(n) / 5.0))
		_shrink(row, cut)
		row["unpaid"] = unpaid + 1
	else:
		row["unpaid"] = 0
	n = maxi(0, int(row.get("n", 0)))
	row["n"] = n
	var kit: float = float(row.get("kit", 100.0))
	if n > 0:
		kit = maxf(0.0, kit - PEACE_DROP)
	var keep_bill: float = float(n) * KEEP_WEEK
	var keep_paid: float = 0.0
	if keep_bill > 0.0 and _can_repair(game, town):
		keep_paid = _buy_smith(e, f, _smith(e), keep_bill)
		if keep_paid > 0.0:
			kit = minf(100.0, kit + PEACE_DROP * keep_paid / keep_bill)
	row["kit"] = kit
	var repair_paid: float = _pay_due(game, town, e, f, row)
	out["ok"] = true
	out["retinue"] = n
	out["target"] = want
	out["left"] = n
	out["wage_bill"] = bill
	out["wages_paid"] = wage_pay
	out["maintenance_paid"] = keep_paid
	out["repair_paid"] = repair_paid
	out["recipients"] = int(credited.get("families", 0))
	return out

static func on_battle_end(game, result: Dictionary) -> Dictionary:
	var out: Dictionary = {"wear_steps": 0, "repair_due": 0.0, "repair_paid": 0.0, "units": 0}
	if game == null or result.is_empty() or game.world.is_empty():
		return out
	var home: Dictionary = Dynasty._household(game, str(game.world.get("player_house", {}).get("household_uid", "")))
	var town: Dictionary = home.get("town", {}) if home.get("town", {}) is Dictionary else {}
	var fam: Dictionary = home.get("family", {}) if home.get("family", {}) is Dictionary else {}
	var uid: String = str(fam.get("household_uid", ""))
	var row: Dictionary = _house(game, uid) if uid != "" else {}
	var steps: int = 0
	var seen: int = 0
	for u in result.get("player_units", []):
		if not (u is Unit) or (u as Unit).dead or str((u as Unit).race) == "dragon":
			continue
		var got: int = _wear_unit(game, u, _hurt(u, result))
		if got > 0:
			steps += got
			seen += 1
	for u2 in result.get("allies", []):
		if not (u2 is Unit) or (u2 as Unit).dead or str((u2 as Unit).race) == "dragon":
			continue
		var got2: int = _wear_unit(game, u2, _hurt(u2, result))
		if got2 > 0:
			steps += got2
			seen += 1
	var cost: float = float(steps) * REPAIR_PER
	if uid != "" and cost > 0.0:
		row["repair"] = float(row.get("repair", 0.0)) + cost
		var e: Dictionary = town.get("econ", {}) if town.get("econ", {}) is Dictionary else {}
		if not e.is_empty() and not fam.is_empty():
			out["repair_paid"] = _pay_due(game, town, e, fam, row)
		out["repair_due"] = float(row.get("repair", 0.0))
	out["wear_steps"] = steps
	out["units"] = seen
	return out

static func after_load(game) -> void:
	_live = {}
	if game == null or game.world.is_empty() or not game.world.has("troop_upkeep"):
		return
	var st: Dictionary = game.world["troop_upkeep"]
	st["v"] = int(st.get("v", 1))
	if not st.has("houses") or not (st["houses"] is Dictionary):
		st["houses"] = {}
	if not st.has("units") or not (st["units"] is Dictionary):
		st["units"] = {}
	var houses: Dictionary = st["houses"]
	for hid in houses.keys():
		if not (houses[hid] is Dictionary):
			continue
		var row: Dictionary = houses[hid]
		row["target"] = int(row.get("target", 0))
		row["unpaid"] = int(row.get("unpaid", 0))
		row["kit"] = float(row.get("kit", 100.0))
		row["repair"] = float(row.get("repair", 0.0))
		var men: Array = _men_of(row)
		for i in men.size():
			if not (men[i] is Dictionary):
				continue
			var m: Dictionary = men[i]
			m["fid"] = int(m.get("fid", -1))
			m["n"] = maxi(0, int(m.get("n", 0)))
			m["tid"] = str(m.get("tid", ""))
		row["men"] = men
		row["n"] = maxi(0, _count_men(men))
	var units: Dictionary = st["units"]
	for k in units.keys():
		if not (units[k] is Dictionary):
			continue
		var rec: Dictionary = units[k]
		rec["wear"] = int(rec.get("wear", 0))
		rec["cond"] = float(rec.get("cond", 100.0))
		rec["steps"] = int(rec.get("steps", 0))
		if rec.get("slots", {}) is Dictionary:
			var slots: Dictionary = rec["slots"]
			for s in slots.keys():
				slots[s] = int(slots[s])

static func expected_yearly_cost(game, household_uid: String) -> float:
	if game == null or str(household_uid) == "" or game.world.is_empty():
		return 0.0
	var home: Dictionary = Dynasty._household(game, str(household_uid))
	if home.is_empty():
		return 0.0
	var town: Dictionary = home.get("town", {}) if home.get("town", {}) is Dictionary else {}
	var fam: Dictionary = home.get("family", {}) if home.get("family", {}) is Dictionary else {}
	var e: Dictionary = town.get("econ", {}) if town.get("econ", {}) is Dictionary else {}
	if town.is_empty() or fam.is_empty() or e.is_empty() or not _rules(e, fam):
		return 0.0
	var men: int = _target_n(game, town, fam)
	return float(men) * (WAGE_WEEK + KEEP_WEEK) * WEEKS_YEAR
