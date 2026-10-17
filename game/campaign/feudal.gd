class_name Feudal
extends RefCounted
## Authoritative political ownership; native people, private purses and public
## treasuries remain their own records. No new wallet or population lives here.
const COOLDOWN := 60
const ACTION_DAYS := 7
const TRIBUTE_RATE := 0.001
const HOUSE_RESERVE := 100.0

static func _state(w: Dictionary) -> Dictionary:
	if not w.has("feudal"): w["feudal"] = {"v": 2, "towns": {}, "roots": {}, "day": -1, "history": []}
	return w["feudal"]

static func _ids(w: Dictionary, fid: String) -> Array:
	var ids := []
	for tid in w.get("towns", {}):
		if str(w["towns"][tid].get("faction", "")) == fid: ids.append(str(tid))
	ids.sort_custom(func(a, b):
		var sa := int(w["towns"][a].get("size", 0)); var sb := int(w["towns"][b].get("size", 0))
		return sa > sb if sa != sb else str(a) < str(b))
	return ids

## Capital-office holder is the sovereign. Existing capitals survive; if their
## ownership changes the largest remaining native settlement becomes the seat.
static func prepare_world(game) -> void:
	var w: Dictionary = game.world; var s := _state(w)
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]; var ids := _ids(w, str(fid))
		fac["towns"] = ids
		var cap := str(fac.get("capital", ""))
		if not ids.has(cap): cap = str(ids[0]) if not ids.is_empty() else ""
		fac["capital"] = cap; s["roots"][str(fid)] = cap
		for tid in ids:
			var town: Dictionary = w["towns"][tid]; town["capital"] = tid == cap
			var row: Dictionary = s["towns"].get(tid, {})
			if row.is_empty():
				row = {"loyalty": 65.0, "grievance": 0.0, "last_defection": -COOLDOWN,
					"last_action": -ACTION_DAYS, "history": [], "tribute_day": -1}
			var parent := cap
			if tid == cap: parent = ""
			elif int(town.get("size", 0)) < 2:
				var distance := INF
				for candidate in ids:
					if candidate == tid or int(w["towns"][candidate].get("size", 0)) < 2: continue
					var d := (town["pos"] as Vector2).distance_squared_to(w["towns"][candidate]["pos"])
					if d < distance or (d == distance and str(candidate) < parent): distance = d; parent = str(candidate)
			row["faction_id"] = str(fid); row["liege_town_id"] = parent
			row["sovereign_town_id"] = cap; row["tier"] = "sovereign" if tid == cap else ("county" if int(town.get("size", 0)) >= 2 else "village")
			s["towns"][tid] = row
			if not town.get("econ", {}).is_empty(): town["econ"]["faction"] = str(fid)
			var head: Dictionary = town.get("econ", {}).get("head", {})
			if not head.is_empty():
				if not head.has("settlement_title"): head["settlement_title"] = str(TownEcon.culture_of(town["econ"]).get("head_title", head.get("title", "Lord")))
				if tid != cap: head["title"] = str(head["settlement_title"])
		if cap != "":
			var e: Dictionary = w["towns"][cap].get("econ", {})
			var h: Dictionary = e.get("head", {})
			if not h.is_empty() and Dynasty.law(game, cap) != "strength":
				h["title"] = "King" if Persons.race_of(e) in ["human", "dwarf"] else ("Emperor" if Persons.race_of(e) == "moon_elf" else str(TownEcon.culture_of(e).get("capital_title", "Sovereign")))
			elif not h.is_empty(): h["title"] = "Warlord"
	for tid in s["towns"].keys():
		if not w.get("towns", {}).has(tid): s["towns"].erase(tid)
	var player: Dictionary = w.get("player_house", {})
	var ph: Dictionary = w.get("towns", {}).get(str(player.get("town_id", "")), {}).get("econ", {}).get("head", {})
	if not player.is_empty() and str(player.get("ruler_uid", "")) == str(ph.get("person_uid", "")): player["title"] = str(ph.get("title", "Ruler"))

static func after_load(game) -> void:
	Dynasty.prepare_world(game)
	prepare_world(game)

## Complete queued native population/death work before this office reconciliation.
static func finish(game) -> void:
	var started := Time.get_ticks_usec()
	Dynasty.succession_day(game)
	Perf.record_us("Native office reconciliation", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	prepare_world(game)
	Perf.record_us("Feudal hierarchy", Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	Dragons.reconcile(game)
	Perf.record_us("Dragon ownership", Time.get_ticks_usec() - started)

static func _vassals(w: Dictionary, tid: String) -> Array:
	var out := []
	for id in w.get("feudal", {}).get("towns", {}):
		if str(w["feudal"]["towns"][id].get("liege_town_id", "")) == tid: out.append(str(id))
	out.sort(); return out

static func can_act(game, town_id: String) -> bool:
	var selected := Dynasty.selected(game)
	# A collateral household may share the ruling dynasty's birth-house UID.
	# Settlement command follows the actual current office holder, not that UID.
	if selected.is_empty() or not Dynasty.holds_office(game) or not Dynasty.ruler(game).get("alive", false): return false
	var mine := str(selected.get("town_id", "")); var office := Dynasty.town_office(game, mine)
	if str(office.get("house_uid", "")) != str(selected.get("house_uid", "")) or office.get("vacant", true): return false
	var towns: Dictionary = game.world.get("towns", {})
	var faction := str(towns.get(mine, {}).get("faction", ""))
	if faction == "" or str(towns.get(town_id, {}).get("faction", "")) != faction: return false
	var current := town_id; var seen := {}
	while current != "" and not seen.has(current):
		if str(towns.get(current, {}).get("faction", "")) != faction: return false
		if current == mine: return true
		seen[current] = true
		current = str(game.world.get("feudal", {}).get("towns", {}).get(current, {}).get("liege_town_id", ""))
	return false

static func summary(game, town_id: String) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
	var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(town_id, {})
	if town.is_empty() or row.is_empty(): return {}
	var out := row.duplicate(true)
	out["town_id"] = town_id; out["town_name"] = str(town.get("name", town_id))
	out["office"] = Dynasty.town_office(game, town_id); out["heir"] = Dynasty.heir(game, town_id)
	out["law"] = Dynasty.law(game, town_id); out["vassals"] = _vassals(game.world, town_id)
	out["can_act"] = can_act(game, town_id)
	out["house_tax_received"] = float(town.get("econ", {}).get("stats", {}).get("estate_tax_received", 0.0))
	out["house_tax_day"] = int(town.get("econ", {}).get("stats", {}).get("estate_tax_day", -1))
	return out

static func hierarchy(game, faction_id: String) -> Array:
	var out := []
	for tid in _ids(game.world, faction_id): out.append(summary(game, str(tid)))
	return out

## This is a native private owner, suitable for the one common-pool tax debit.
## The old economic head.fam remains authoritative for old loans and property.
static func tax_recipient(game, town_id: String) -> Dictionary:
	var h: Dictionary = game.world.get("towns", {}).get(town_id, {}).get("econ", {}).get("head", {})
	var loc := Dynasty._person(game, str(h.get("person_uid", "")))
	return loc.get("family", {})

## Pure fiscal view. Estimates never book revenue or borrow another wallet.
static func budget(game, town_id: String) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
	var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(town_id, {})
	if town.is_empty() or row.is_empty(): return {}
	var e: Dictionary = town.get("econ", {})
	var fid := str(town.get("faction", ""))
	var fac: Dictionary = game.world.get("factions", {}).get(fid, {})
	var lord: Dictionary = tax_recipient(game, town_id)
	var payer: Dictionary = _payer(game)
	var parent := str(row.get("liege_town_id", ""))
	var liege: Dictionary = tax_recipient(game, parent)
	var lord_office: Dictionary = Dynasty.town_office(game, town_id)
	var liege_office: Dictionary = Dynasty.town_office(game, parent)
	var mil: Dictionary = Militia.band_of(game, town_id)
	var militia: Array = Militia.units_of(game, town_id)
	var guards: Array = TownDefence.guards(game, town_id).filter(func(u): return not u.dead)
	var active: bool = bool(mil.get("mustered", false)) or bool(mil.get("drill_today", false))
	var wages := 0.0
	var guard_lo := Army.low_officer(guards, "guard")
	var militia_lo := Army.low_officer(militia, "militia")
	for u in guards: wages += Army.wage("guard", int(u.rank), guard_lo, u)
	if active:
		for u in militia: wages += Army.wage("militia", int(u.rank), militia_lo, u)
	var received := 0.0; var received_day := -1
	for child in _vassals(game.world, town_id):
		var v: Dictionary = game.world["feudal"]["towns"][child]
		var paid_day := int(v.get("tribute_day", -1))
		if paid_day > received_day: received_day = paid_day; received = 0.0
		if paid_day == received_day: received += float(v.get("tribute", 0.0))
	return {"town_id": town_id, "town_name": str(town.get("name", town_id)), "faction_id": fid,
		"can_act": can_act(game, town_id), "can_fund_realm_army": _sovereign_authority(game, town_id),
		"lord_name": str(lord_office.get("name", "Vacant")), "lord_household_uid": str(lord.get("household_uid", "")), "lord_purse": float(lord.get("purse", 0.0)),
		"payer_name": str(Dynasty.ruler(game).get("name", "")), "payer_household_uid": str(payer.get("household_uid", "")), "payer_purse": float(payer.get("purse", 0.0)),
		"liege_town_id": parent, "liege_name": str(liege_office.get("name", "")), "liege_household_uid": str(liege.get("household_uid", "")), "liege_purse": float(liege.get("purse", 0.0)),
		"tax_quote": Barge.common_tax_budget(e), "estate_tax_received": float(e.get("stats", {}).get("estate_tax_received", 0.0)), "estate_tax_day": int(e.get("stats", {}).get("estate_tax_day", -1)),
		"tribute_sent": float(row.get("tribute", 0.0)), "tribute_day": int(row.get("tribute_day", -1)), "tribute_received": received, "tribute_received_day": received_day,
		"town_treasury": float(e.get("treasury", 0.0)), "faction_treasury": float(fac.get("treasury", 0.0)), "company_gold": float(game.gold),
		"realm_army_count": Army.members(game, fid).size(), "realm_army_wages_daily": Army.bill(game, fid),
		"militia_count": militia.size(), "guard_count": guards.size(), "garrison_count": militia.size() + guards.size(), "garrison_wages_daily": wages,
		"mustered": bool(mil.get("mustered", false)), "drill_today": bool(mil.get("drill_today", false)),
		"defence_policy": TownDefence.defence_policy(game, town), "defence_order_day": int(row.get("defence_order_day", -1)),
		"food_days": TownEcon.days_food(town), "food_short": float(e.get("food_short", 0.0)), "tax_policy_day": int(row.get("tax_policy_day", -ACTION_DAYS))}

static func _sovereign_authority(game, town_id: String) -> bool:
	if not can_act(game, town_id): return false
	var fid := str(game.world.get("towns", {}).get(town_id, {}).get("faction", ""))
	var cap := str(game.world.get("factions", {}).get(fid, {}).get("capital", ""))
	return cap != "" and str(Dynasty.selected(game).get("town_id", "")) == cap

## Positive funding amounts use native coin units, as the company action does.
## Tax amount is a rate; orders have no monetary charge or invented troop quota.
static func governance_preview(game, town_id: String, action: String, amount: float = 0.0) -> Dictionary:
	var out: Dictionary = _result(false, "This settlement is outside your authority.")
	out.merge({"town_id": town_id, "action": action, "amount": amount, "payer_name": "", "payer_household_uid": "",
		"recipient_name": "", "recipient_account": "", "recipient_id": "", "defence_policy": "auto_defence", "current_tax_rate": 0.0, "proposed_tax_rate": 0.0})
	if not can_act(game, town_id): return out
	var town: Dictionary = game.world["towns"][town_id]
	var e: Dictionary = town.get("econ", {})
	var row: Dictionary = game.world["feudal"]["towns"][town_id]
	var payer: Dictionary = _payer(game)
	if e.is_empty() or payer.is_empty() or Dynasty.town_office(game, town_id).get("vacant", true):
		out["reason"] = "A living ruling household and native settlement accounts are required."; return out
	out["payer_name"] = str(Dynasty.ruler(game).get("name", "")); out["payer_household_uid"] = str(payer.get("household_uid", ""))
	out["defence_policy"] = TownDefence.defence_policy(game, town)
	out["current_tax_rate"] = Barge.common_tax_rate(e); out["proposed_tax_rate"] = out["current_tax_rate"]
	match action:
		"tax_policy":
			if not is_finite(amount) or not amount in [0.02, 0.05, 0.10]: out["reason"] = "Choose an estate tax rate of two, five or ten percent."; return out
			if is_equal_approx(amount, float(out["current_tax_rate"])): out["reason"] = "This estate tax rate is already in force."; return out
			if int(game.day) - int(row.get("tax_policy_day", -ACTION_DAYS)) < ACTION_DAYS: out["reason"] = "An estate tax decree can change once per week."; return out
			out["proposed_tax_rate"] = amount
			out["recipient_name"] = str(Dynasty.town_office(game, town_id).get("name", "")); out["recipient_account"] = "ruling_house"; out["recipient_id"] = str(tax_recipient(game, town_id).get("household_uid", ""))
			out["reason"] = "Set future monthly common-folk estate tax after their protected food reserve. Actual payments affect local grievance; the quote is not new income."
		"fund_garrison", "fund_realm_army":
			if amount <= 0.0 or not is_finite(amount): out["reason"] = "Choose a positive amount of house coin."; return out
			out["cost"] = amount
			if action == "fund_realm_army":
				if not _sovereign_authority(game, town_id): out["reason"] = "Only this realm's reigning sovereign may fund its field army."; return out
				var fid := str(town.get("faction", ""))
				if not game.world.get("factions", {}).has(fid): out["reason"] = "This realm has no native treasury."; return out
				out["recipient_name"] = str(DB.factions.get(fid, {}).get("name", fid)); out["recipient_account"] = "faction_treasury"; out["recipient_id"] = fid
				out["reason"] = "Transfer private house coin into the existing realm treasury for native troops, food and other public obligations."
			else:
				out["recipient_name"] = str(town.get("name", town_id)); out["recipient_account"] = "town_treasury"; out["recipient_id"] = town_id
				out["reason"] = "Transfer private house coin into the city treasury for native guards, militia and public obligations, including existing realm levies."
			if float(payer.get("purse", 0.0)) < amount: out["reason"] = "The ruling house purse cannot afford this transfer."; return out
		"muster", "stand_down", "auto_defence":
			if str(out["defence_policy"]) == action: out["reason"] = "This defence order is already in force."; return out
			if action == "muster" and Militia.units_of(game, town_id).is_empty(): out["reason"] = "This settlement has no existing living militia to muster."; return out
			out["defence_policy"] = action
			out["reason"] = "Keep the existing militia on duty; native wages and food remain due, and civilian work loses those hands." if action == "muster" else ("Stand down militia and drill, returning their civilian hands; automatic militia defence is suspended. Guards keep their native duty." if action == "stand_down" else "Restore native threat callups and weekly militia drill.")
		_:
			out["reason"] = "Unknown governance action."; return out
	out["ok"] = true
	return out

static func governance(game, town_id: String, action: String, amount: float = 0.0) -> Dictionary:
	var out: Dictionary = governance_preview(game, town_id, action, amount)
	if not bool(out["ok"]): return out
	var town: Dictionary = game.world["towns"][town_id]
	var e: Dictionary = town["econ"]
	var row: Dictionary = game.world["feudal"]["towns"][town_id]
	match action:
		"tax_policy":
			e["lord_tax_rate"] = amount; row["tax_policy_day"] = int(game.day)
		"fund_garrison", "fund_realm_army":
			var payer: Dictionary = _payer(game)
			payer["purse"] = float(payer["purse"]) - amount
			if action == "fund_garrison": e["treasury"] = float(e["treasury"]) + amount
			else:
				var fac: Dictionary = game.world["factions"][str(town["faction"])]
				fac["treasury"] = float(fac.get("treasury", 0.0)) + amount
		_:
			row["defence_policy"] = action; row["defence_order_day"] = int(game.day)
			var mil: Dictionary = Militia.band_of(game, town_id)
			if not mil.is_empty():
				if action == "auto_defence":
					# Forget forced duty; the next ordinary threat check determines callup.
					TownDefence.set_muster(game, town, false, false)
				else: TownDefence.set_muster(game, town, action == "muster", false)
	var detail := "%d%% estate tax" % int(round(amount * 100.0)) if action == "tax_policy" else ("%s (%.2f coins)" % [action.replace("_", " "), amount] if action.begins_with("fund_") else action.replace("_", " "))
	_history(game, town_id, "%s: %s." % [str(town.get("name", town_id)), detail])
	game.changed.emit()
	return out

static func _payer(game) -> Dictionary:
	var state: Dictionary = game.world.get("player_house", {})
	return Dynasty._household(game, str(state.get("household_uid", ""))).get("family", {})

static func _history(game, tid: String, line: String) -> void:
	var s := _state(game.world); var entry := {"day": int(game.day), "town_id": tid, "text": line}
	s["history"].append(entry)
	while s["history"].size() > 100: s["history"].pop_front()
	var row: Dictionary = s["towns"].get(tid, {})
	if not row.is_empty():
		row["history"].append(entry.duplicate())
		while row["history"].size() > 12: row["history"].pop_front()
	CampaignWorld.log_event(game, line)

static func _result(ok: bool, reason: String, cost: float = 0.0) -> Dictionary:
	return {"ok": ok, "reason": reason, "cost": cost}

static func _defect_check(game, tid: String, target: String) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	var fac: Dictionary = game.world.get("factions", {}).get(target, {})
	var row: Dictionary = game.world.get("feudal", {}).get("towns", {}).get(tid, {})
	if town.is_empty() or row.is_empty(): return _result(false, "Unknown settlement.")
	if target == str(town.get("faction", "")): return _result(false, "Already sworn to this realm.")
	if fac.is_empty() or not DB.factions.has(target) or fac.get("towns", []).is_empty(): return _result(false, "The destination has no existing realm seat.")
	if Dynasty.town_office(game, str(fac.get("capital", ""))).get("vacant", true): return _result(false, "The destination has no living sovereign.")
	if int(game.day) - int(row.get("last_defection", -COOLDOWN)) < COOLDOWN: return _result(false, "This settlement must honour its new oath for sixty days.")
	if Dynasty.town_office(game, tid).get("vacant", true): return _result(false, "A vacant office cannot swear a new oath.")
	return _result(true, "Ownership, local soldiers and future taxes will follow the new liege; residents and their property remain.")

static func action_preview(game, town_id: String, action: String, target_fid: String = "", amount: float = 0.0) -> Dictionary:
	var out := _result(false, "This settlement is outside your authority.")
	out["action"] = action; out["target_fid"] = target_fid
	if not can_act(game, town_id): return out
	var row: Dictionary = game.world["feudal"]["towns"][town_id]
	var payer := _payer(game)
	if payer.is_empty(): out["reason"] = "The ruling house has no living private account."; return out
	if action != "fund_army" and int(game.day) - int(row.get("last_action", -ACTION_DAYS)) < ACTION_DAYS:
		out["reason"] = "This settlement can receive one political action per week."; return out
	match action:
		"grant":
			out["cost"] = 25.0 * TownEcon.COIN
			var recipient := tax_recipient(game, town_id)
			if recipient.is_empty() or str(recipient.get("household_uid", "")) == str(payer.get("household_uid", "")):
				out["reason"] = "A grant requires a different living vassal household."; return out
			out["reason"] = "Give the vassal house a real grant; loyalty rises and grievance falls."
		"pressure":
			out["cost"] = 10.0 * TownEcon.COIN
			if str(town_id) == str(Dynasty.selected(game).get("town_id", "")): out["reason"] = "Pressure requires a vassal."; return out
			if tax_recipient(game, town_id).is_empty(): out["reason"] = "A vacant office cannot receive an intrigue payment."; return out
			out["reason"] = "Pay the vassal household to impose stronger oath terms; loyalty rises and lasting grievance rises."
		"swear":
			var gate := _defect_check(game, town_id, target_fid)
			out["reason"] = gate["reason"]
			if not gate["ok"]: return out
			if float(row["loyalty"]) > 35.0: out["reason"] = "The local oath is too strong; loyalty must fall to thirty-five."; return out
		"fund_army":
			out["cost"] = amount
			if amount <= 0.0 or not is_finite(amount): out["reason"] = "Choose a positive amount of house coin."; return out
			if amount != floor(amount): out["reason"] = "The company wallet accepts whole coins."; return out
			out["reason"] = "Transfer real house coin into the company wallet for native recruiting, food and wages."
		_:
			out["reason"] = "Unknown political action."; return out
	if float(payer.get("purse", 0.0)) < float(out["cost"]): out["reason"] = "The house purse cannot afford this action."; return out
	out["ok"] = true
	return out

static func intrigue(game, town_id: String, action: String, target_fid: String = "", amount: float = 0.0) -> Dictionary:
	var out := action_preview(game, town_id, action, target_fid, amount)
	if not out["ok"]: return out
	if action == "swear": return defect(game, town_id, target_fid, "the player's oath")
	var payer := _payer(game); var row: Dictionary = game.world["feudal"]["towns"][town_id]
	var cost := float(out["cost"]); payer["purse"] = float(payer["purse"]) - cost
	if action == "fund_army":
		game.gold = int(game.gold) + int(cost)
	else:
		var recipient := tax_recipient(game, town_id)
		recipient["purse"] = float(recipient["purse"]) + cost
		row["last_action"] = int(game.day)
		row["loyalty"] = minf(100.0, float(row["loyalty"]) + (12.0 if action == "grant" else 8.0))
		row["grievance"] = clampf(float(row["grievance"]) + (-10.0 if action == "grant" else 15.0), 0.0, 100.0)
	_history(game, town_id, "%s: %s (%d coins)." % [game.world["towns"][town_id]["name"], action.replace("_", " "), int(cost)])
	game.changed.emit(); return out

static func fund_army(game, amount: float) -> Dictionary:
	return intrigue(game, str(Dynasty.selected(game).get("town_id", "")), "fund_army", "", amount)

## Private estate tribute is booked once per payer/day. Public military levies
## and the existing public treasury tribute retain their distinct native books.
static func _tribute(game, day: int) -> void:
	var s := _state(game.world)
	var paid := {}
	for tid in s["towns"]:
		var row: Dictionary = s["towns"][tid]
		if int(row.get("tribute_day", -1)) >= day: continue
		row["tribute_day"] = day
		row["tribute"] = 0.0
		var parent := str(row.get("liege_town_id", ""))
		if parent == "": continue
		var payer := tax_recipient(game, str(tid)); var recipient := tax_recipient(game, parent)
		var uid := str(payer.get("household_uid", "")); var rid := str(recipient.get("household_uid", ""))
		if payer.is_empty() or recipient.is_empty() or uid == rid or paid.has(uid): continue
		paid[uid] = true
		var due := maxf(0.0, float(payer.get("purse", 0.0)) - HOUSE_RESERVE * TownEcon.COIN) * TRIBUTE_RATE
		payer["purse"] = float(payer["purse"]) - due; recipient["purse"] = float(recipient["purse"]) + due
		row["tribute"] = due

static func _protection(w: Dictionary, fid: String, town: Dictionary) -> float:
	var power := 0.0
	for band in w.get("warbands", {}).values():
		if str(band.get("faction", "")) == fid and (band.get("pos", Vector2.ZERO) as Vector2).distance_squared_to(town["pos"]) <= 400.0 * 400.0:
			power += CampaignWorld.band_power(band.get("units", []))
	return power

## Only actual booked common-folk tax creates burden, once per owner/month.
## Wealth left after the same food reserve and real shortages shape grievance;
## changing a decree or reading a quote cannot produce coin or distress.
static func _tax_distress(e: Dictionary, row: Dictionary, town_id: String) -> float:
	if not row.has("tax_burden_seen"): row["tax_burden_seen"] = {}
	var seen: Dictionary = row["tax_burden_seen"]
	var paid := 0.0; var base := 0.0
	for f in e.get("fams", []):
		if not f.get("cohort", false) or f.get("gone", false): continue
		if str(f.get("lord_tax_town_id", town_id)) != town_id: continue
		var uid := str(f.get("household_uid", "")); var month := int(f.get("lord_tax_month", -1))
		if month < 0 or int(seen.get(uid, -1)) >= month: continue
		seen[uid] = month
		var levy := maxf(0.0, float(f.get("lord_tax_last", 0.0)))
		paid += levy
		base += maxf(levy, float(f.get("purse", 0.0)) + levy - float(f.get("lord_tax_reserve", 0.0)))
	if paid <= 0.0: return 0.0
	var hunger := clampf(float(e.get("food_short", 0.0)), 0.0, 1.0)
	return minf(1.0, 4.0 * paid / maxf(1.0, base) * (1.0 + hunger))

static func daily(game, day: int) -> void:
	var s := _state(game.world)
	if int(s.get("day", -1)) >= day: return
	s["day"] = day
	DragonFear.daily(game)
	Dynasty.succession_day(game)
	_tribute(game, day)
	var ids: Array = s["towns"].keys(); ids.sort()
	for tid in ids:
		var row: Dictionary = s["towns"][tid]; var town: Dictionary = game.world["towns"][tid]
		var e: Dictionary = town.get("econ", {})
		var tax_distress := _tax_distress(e, row, str(tid))
		row["tax_distress"] = tax_distress
		var distress := float(e.get("unrest", 0.0)) * 0.6 + float(e.get("fstage", 0)) * 0.15 + (0.25 if int(e.get("stats", {}).get("militia_unpaid", 0)) > 0 else 0.0) + tax_distress
		row["grievance"] = clampf(float(row["grievance"]) + distress - 0.1, 0.0, 100.0)
		row["loyalty"] = clampf(float(row["loyalty"]) + 0.05 - distress - float(row["grievance"]) * 0.002, 0.0, 100.0)
		var dfear := DragonFear.fear(game, str(tid))
		var dlimit := 15.0 + dfear * 0.3 if dfear >= 50.0 else 15.0
		if float(row["loyalty"]) > dlimit or str(row.get("tier", "")) == "sovereign": continue
		if dfear >= 50.0:
			var fear_of := str(row.get("fear_of", ""))
			if fear_of != "" and _defect_check(game, str(tid), fear_of)["ok"]:
				defect(game, str(tid), fear_of, "fear of dragons", true); continue
		var best := ""; var protection := _protection(game.world, str(town["faction"]), town)
		var strongest := maxf(1.0, protection) * 1.5
		var targets: Array = game.world.get("factions", {}).keys(); targets.sort()
		for target in targets:
			if not _defect_check(game, str(tid), str(target))["ok"]: continue
			var power := _protection(game.world, str(target), town)
			if power > strongest: strongest = power; best = str(target)
		if best != "": defect(game, str(tid), best, "a broken oath and stronger local protection", true)

## Caller authorization is explicit: players need domain authority; AI uses the
## bounded daily loyalty/protection gate above rather than a random flip roll.
static func defect(game, town_id: String, target_fid: String, reason: String = "a new oath", ai: bool = false) -> Dictionary:
	if not ai and not can_act(game, town_id): return _result(false, "This settlement is outside your authority.")
	var gate := _defect_check(game, town_id, target_fid)
	if not gate["ok"]: return gate
	var w: Dictionary = game.world; var s := _state(w); var row: Dictionary = s["towns"][town_id]
	var dfear := DragonFear.fear(game, town_id)
	var feared := ai and dfear >= 50.0 and str(row.get("fear_of", "")) == target_fid
	if (not ai and float(row["loyalty"]) > 35.0) or (ai and float(row["loyalty"]) > (15.0 + dfear * 0.3 if feared else 15.0)): return _result(false, "The local oath is too strong.")
	var town: Dictionary = w["towns"][town_id]; var old := str(town["faction"])
	if ai and not feared and _protection(w, target_fid, town) <= maxf(1.0, _protection(w, old, town)) * 1.5: return _result(false, "The destination cannot provide stronger local protection.")
	var was_capital := str(w["factions"].get(old, {}).get("capital", "")) == town_id
	town["faction"] = target_fid; town["econ"]["faction"] = target_fid
	_transfer_forces(game, town_id, old, target_fid)
	row["loyalty"] = 55.0; row["grievance"] = 20.0
	row["last_defection"] = int(game.day); row["last_action"] = int(game.day)
	prepare_world(game)
	if was_capital:
		var seat := str(w["factions"].get(old, {}).get("capital", ""))
		if seat != "": _history(game, seat, "%s became the seat of %s after its former sovereign broke the realm's oath." % [w["towns"][seat]["name"], CampaignWorld.faction_name(old)])
	Academy.sync_towns(w, old); Academy.sync_towns(w, target_fid)
	# A broken oath is a real diplomatic grievance; let native daily hysteresis
	# choose war/hostility, respecting its existing truce rules.
	Diplomacy._push(w, old, target_fid, -35.0)
	if w.has("diplo"):
		var pair: Dictionary = w["diplo"].get("pairs", {}).get(Diplomacy.pair_key(old, target_fid), {})
		if not pair.is_empty():
			pair["past"] = 0
			if str(pair.get("state", "")) != Diplomacy.WAR:
				pair["rel"] = minf(float(pair["rel"]), -30.0)
				Diplomacy._set_state(game, pair, Diplomacy.HOSTILE)
				Diplomacy._sync_wars(w)
		w["diplo"]["size"] = {}
	if w.has("war"): w["war"]["intel"] = {}; w["war"]["avg"] = {}
	_history(game, town_id, "%s swore to %s: %s." % [town["name"], CampaignWorld.faction_name(target_fid), reason])
	game.changed.emit(); return _result(true, "Settlement allegiance changed; native population and wealth were preserved.")

static func _transfer_forces(game, tid: String, old: String, target: String) -> void:
	var w: Dictionary = game.world; var moved := {}
	for m in CampaignWorld.mustering(w):
		var pending: Dictionary = m.get("wb", m.get("extra", {}))
		if str(m.get("fid", "")) != old or str(pending.get("home", "")) != tid: continue
		if str(m.get("kind", "")) == "caravan": continue
		m["fid"] = target
		if m.has("wb"): m["wb"]["faction"] = target
		for u in m.get("wb", {}).get("units", m.get("units", [])):
			u.faction = target; moved[str(u.uid)] = true
	for wid in w.get("warbands", {}).keys():
		var wb: Dictionary = w["warbands"][wid]
		if str(wb.get("faction", "")) != old or not (Army.is_field(wb) or str(wb.get("kind", "")) == "militia"): continue
		var men := []; var stay := []
		for u in wb.get("units", []):
			if not u.dead and u.home_town == tid: men.append(u); moved[str(u.uid)] = true; u.faction = target; u.rank = 1 if u.battles > 0 else 0; u.role = "troop"
			else: stay.append(u)
		if men.is_empty(): continue
		if stay.is_empty():
			wb["faction"] = target; wb["home"] = tid; wb["posts"] = []; wb["path"] = []; wb["target_town"] = ""; wb.erase("war")
		else:
			# Split only existing objects; split owned stock/coin by actual manpower.
			var split: Dictionary = wb.duplicate(false); var id := CampaignWorld.new_id(w, "wb")
			split["id"] = id; split["faction"] = target; split["units"] = men; split["home"] = tid
			split["posts"] = []; split["path"] = []; split["target_town"] = ""; split.erase("war")
			var fraction := float(men.size()) / float(men.size() + stay.size())
			for key in ["gold", "loot"]:
				if wb.has(key): split[key] = float(wb[key]) * fraction; wb[key] = float(wb[key]) - float(split[key])
			for key in ["stores", "stock"]:
				if wb.get(key) is Dictionary:
					split[key] = {}
					for good in wb[key]:
						var take := floori(float(wb[key][good]) * fraction)
						split[key][good] = take; wb[key][good] = int(wb[key][good]) - take
			# Caches/orders must not retain an old friendly target or shared post array.
			wb["path"] = []; wb["target_town"] = ""; wb.erase("war"); wb.erase("pw")
			split.erase("pw"); split.erase("pw_n"); split.erase("pw_t")
			wb["units"] = stay; w["warbands"][id] = split
			wb["n0"] = stay.size(); split["n0"] = men.size()
	for u in w.get("towns", {}).get(tid, {}).get("recruits", []): u.faction = target
	for fid in [old, target]:
		var r: Dictionary = w.get("army", {}).get("f", {}).get(fid, {})
		if r.is_empty(): continue
		for i in r.get("posts", []).size():
			if moved.has(str(r["posts"][i])): r["posts"][i] = -1
		for contest in r.get("fights", []):
			contest["c"] = (contest["c"] as Array).filter(func(uid): return not moved.has(str(uid)))
		r["bill"] = 0.0
		var fac: Dictionary = w.get("factions", {}).get(fid, {})
		if moved.has(str(fac.get("war_leader", {}).get("uid", -1))): fac.erase("war_leader")




