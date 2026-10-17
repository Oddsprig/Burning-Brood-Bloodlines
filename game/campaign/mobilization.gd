class_name Mobilization
extends RefCounted
## Player service uses native company AWAY counts. Home reserves retain the actual
## Unit/body, work as native reserve residents, and never enter the public Army roll.
const LIMIT := 1000   # rounds (battle_rounds.gd) keep the field at 100 v 100
const MEALS := 6 # Three days at the native normal ration, per departing person.
const GROUP := 24
## v0.029 levy armour: the equip slots a raised levy is issued (core/item.gd Item.slot /
## DB.EQUIP_SLOTS: body armour is "body", a helmet is "helm"), and the small fee [ours] for a
## newly made padded fallback piece when the town stocks no body armour for a man.
const BODY_SLOT := "body"
const HELM_SLOT := "helm"
const PADDED_FEE := 20   # = Item.COIN: one old gold piece, from the army purse

static func _state(game) -> Dictionary:
	if not game.world.has("mobilization"):
		game.world["mobilization"] = {"v": 1, "reserve": [], "enlisted": {}, "estate_items": [], "history": []}
	return game.world["mobilization"]

static func reserves(game) -> Array:
	return game.world.get("mobilization", {}).get("reserve", [])

static func estate_items(game) -> Array:
	return game.world.get("mobilization", {}).get("estate_items", [])

static func reserve_unit(game, uid: int, tid: String = "", fid: int = -1) -> Unit:
	for u in reserves(game):
		if u is Unit and u.uid == uid and (tid == "" or u.home_town == tid) and (fid < 0 or u.family == fid): return u
	return null

static func _address(game, u: Unit) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	var f: Dictionary = People.fam_of(town, u.family)
	var p: Array = Persons.by_uid(f, u.uid) if not f.is_empty() else []
	if p.is_empty() or not ServiceIdentity.unit_person(town.get("econ", {}), f, p, u): return {}
	return {"town": town, "econ": town["econ"], "family": f, "person": p}

static func manages(game, u: Unit) -> bool:
	if u == null: return false
	var a: Dictionary = _address(game, u)
	return not a.is_empty() and ((game.company.has(u) and str(a["person"][4]) == "company") or reserves(game).has(u))

static func _here(game, tid: String) -> bool:
	# A paused remote records page is never proof of physical presence.
	if str(game.location) != tid: return false
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	var pos: Vector2 = game.world.get("party", {}).get("pos", Vector2(INF, INF))
	return not town.is_empty() and pos.distance_to(town.get("pos", Vector2.ZERO)) <= 48.0   # the party camps on the nearest passable ground (up to ~1.5 cells away)

static func _gate(game, tid: String, market: bool = true) -> String:
	if game.get("_save_capture") != null: return "Wait for the consistent save snapshot to finish."
	if Dynasty.selected(game).is_empty(): return "Choose an existing house first."
	if not Feudal.can_act(game, tid): return "This settlement is outside your authority."
	if not _here(game, tid): return "Travel to this settlement before raising or standing down."
	if not game.world.get("work", []).is_empty(): return "Let the pending settlement work finish first."
	var e: Dictionary = game.world.get("towns", {}).get(tid, {}).get("econ", {})
	var index := int(e.get("mkt", -1))
	if market and (index < 0 or index >= e.get("biz", []).size() or not e.has("price") or not e.has("stock")): return "The settlement has no functioning market."
	return ""

static func status(game) -> Dictionary:
	var selected: Dictionary = Dynasty.selected(game)
	var tid := str(game.location) if str(game.location) != "" else str(selected.get("town_id", ""))
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	var payer: Dictionary = Feudal._payer(game)
	var alive := 0
	for u in game.company:
		if not u.dead: alive += 1
	var home := 0
	for u in reserves(game):
		if not u.dead: home += 1
	return {"town_id": tid, "town_name": str(town.get("name", tid)), "at_home": _here(game, tid),
		"company": game.company.size(), "alive": alive, "reserve": home, "daily_pay": game.daily_wages(),
		"army_gold": game.gold, "payer_name": str(payer.get("name", "")), "payer_household_uid": str(payer.get("household_uid", "")),
		"payer_purse": float(payer.get("purse", 0.0)), "food_units": Food.stock(game, "meal"),
		"food_days": float(Food.stock(game, "meal")) / maxf(1.0, 2.0 * alive), "can_act": _gate(game, tid) == "", "reason": _gate(game, tid)}

static func _draft_pool(town: Dictionary) -> Array:
	# The native ordered draft policy without Persons.sync (a quote must not age,
	# materialize, reconcile counts, or consume either RNG/UID sequence).
	var out: Array = []
	var e: Dictionary = town["econ"]
	var day := float(e.get("day", 0.0))
	var ages := People.draft_ages(Persons.race_of(e))
	for f in e.get("fams", []):
		var left := Population.spare(f)
		if left <= 0: continue
		var rows: Array = []
		if Population.is_cohort(f):
			var casual := 0
			for key in f.get("cj", {}): casual += int(f["cj"][key])
			for i in Population.eligible_slots(e, f, day, true):
				rows.append([0 if i < int(f.get("idle", 0)) else (1 if i < int(f.get("idle", 0)) + casual else 2), -Families.hardship(f), int(f["id"]), -1])
		var work: Dictionary = People._work_kinds(f)
		for p in f.get("pp", []):
			if int(p[6]) != 0 or str(p[4]) != "" or int(p[5]) >= 0: continue
			if str(Persons.g(p, Persons.PERSON_UID, "")) == str(e.get("head", {}).get("person_uid", "")): continue
			var age := Persons.age_of(p, day)
			var tier := int(People.DRAFT_TIER.get(str(work.get(int(p[0]), "")), -1))
			if age >= ages.x and age <= ages.y and tier >= 0: rows.append([tier, -Families.hardship(f), int(f["id"]), int(p[0])])
		rows.sort_custom(_draft_less)
		out.append_array(rows.slice(0, left))
	out.sort_custom(_draft_less)
	return out

static func _draft_less(a: Array, b: Array) -> bool:
	for i in 4:
		if a[i] != b[i]: return a[i] < b[i]
	return false

static func _weapon(it) -> bool:
	return it is Item and it.is_weapon() and not DB.is_bow(it.tid) and not it.broken

static func _kit(town: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for it in town.get("armory_items", []):
		if _weapon(it) and not seen.has(it.get_instance_id()):
			seen[it.get_instance_id()] = true; out.append({"item": it, "source": "armory", "cost": 0})
	var shop: Array = town.get("shop", []).filter(_weapon)
	shop.sort_custom(func(a, b): return a.quality > b.quality if a.quality != b.quality else a.material < b.material)
	for it in shop:
		if seen.has(it.get_instance_id()): continue
		seen[it.get_instance_id()] = true
		out.append({"item": it, "source": "market", "cost": Economy.price(town, it)})
	return out

## v0.029: one serviceable (unbroken, unworn-out is still worn) armour piece for an equip slot.
static func _armour(it, slot_name: String) -> bool:
	return it is Item and not it.is_weapon() and not it.broken and it.slot() == slot_name

## v0.029: the town's issuable pieces for one armour slot, under the same rules as _kit weapons:
## armory pieces first (borrowed, no charge), then shop pieces best-first at Economy.price (bought).
static func _armour_kit(town: Dictionary, slot_name: String) -> Array:
	var out: Array = []
	var seen := {}
	for it in town.get("armory_items", []):
		if _armour(it, slot_name) and not seen.has(it.get_instance_id()):
			seen[it.get_instance_id()] = true; out.append({"item": it, "source": "armory", "cost": 0})
	var shop: Array = town.get("shop", []).filter(func(it): return _armour(it, slot_name))
	shop.sort_custom(func(a, b): return a.quality > b.quality if a.quality != b.quality else a.material < b.material)
	for it in shop:
		if seen.has(it.get_instance_id()): continue
		seen[it.get_instance_id()] = true
		out.append({"item": it, "source": "market", "cost": Economy.price(town, it)})
	return out

## Item.value() of a plain quality-0 piece of a template, without making an Item (a quote must
## not consume the Item UID sequence); only orders the padded fallback candidates.
static func _template_value(tid: String) -> int:
	var t: Dictionary = DB.template(tid)
	if t.is_empty(): return 1 << 30
	if t.has("value"): return int(round(float(t["value"]) * Item.COIN))
	var mats: Array = t.get("materials", ["copper"])
	var mat: Dictionary = DB.materials.get(str(mats[0]) if not mats.is_empty() else "copper", {})
	var mass := float(t.get("cm3", 0)) * float(mat.get("density", 1000)) / 1.0e6
	return int(round((float(mat.get("value", 1)) * maxf(mass, 0.2) * 6.0 + 4.0) * Item.COIN))

## v0.029 fallback body piece: the cheapest padded/gambeson-style torso template in the item
## data (data/armor.json "gambeson": padded linen, slot "clothing", torso coverage), else the
## cheapest "body"-slot template; "" when the data has neither (the caller then skips silently).
static func _padded_tid() -> String:
	var best := ""; var best_value := 1 << 30
	var ids: Array = DB.armor.keys(); ids.sort()
	for tid in ids:
		var t: Dictionary = DB.armor[tid]
		var nm := str(t.get("name", tid)).to_lower()
		if not (bool(t.get("padded", false)) or nm.contains("gambeson") or nm.contains("padded") or str(tid).contains("gambeson")): continue
		if not (t.get("coverage", {}) as Dictionary).has("torso_upper"): continue
		var v := _template_value(str(tid))
		if v < best_value: best_value = v; best = str(tid)
	if best != "": return best
	for tid in ids:
		if str(DB.armor[tid].get("slot", "")) != BODY_SLOT: continue
		var v := _template_value(str(tid))
		if v < best_value: best_value = v; best = str(tid)
	return best

static func _food(town: Dictionary) -> Array:
	var e: Dictionary = town["econ"]
	var stock := 0; var hh := 0
	for good in Goods.FOODS:
		stock += maxi(0, int(e["stock"].get(good, 0))); hh += maxi(0, int(e.get("hh", {}).get(good, 0)))
	var free := maxi(0, stock - maxi(0, int(ceil(Barge.household_eaters(e, float(e.get("day", 0.0)), false) * 6.0)) - hh))
	var goods: Array = Goods.FOODS.duplicate()
	goods.sort_custom(func(a, b): return Goods.price_f(town, a) < Goods.price_f(town, b))
	var out: Array = []
	for good in goods:
		var n := mini(free, maxi(0, int(e["stock"].get(good, 0))))
		out.append({"good": good, "quantity": n, "price": Goods.price_f(town, good)}); free -= n
	return out

static func _food_order(food: Array, quantity: int) -> Dictionary:
	var out: Array = []; var cost := 0; var remaining := quantity
	for row in food:
		var n := mini(remaining, int(row["quantity"]))
		if n > 0:
			var coins := maxi(1, int(ceil(float(row["price"]) * n - 0.0001)))
			out.append({"good": row["good"], "quantity": n, "cost": coins}); cost += coins; remaining -= n
	return {"orders": out, "cost": cost, "quantity": quantity - remaining}

static func quote(game, town_id: String, count: int = 100) -> Dictionary:
	var s: Dictionary = status(game)
	var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
	var out := {"ok": false, "reason": _gate(game, town_id), "town_id": town_id, "town_name": str(town.get("name", town_id)),
		"requested": clampi(count, 1, LIMIT), "eligible": 0, "available": 0, "planned": 0, "reserve_available": 0, "new_available": 0,
		"kit_available": 0, "body_available": 0, "helm_available": 0, "food_available": 0, "food_units": 0, "raise_cost": 0, "daily_pay": 0, "food_per_day": 0,
		"payer_name": s["payer_name"], "payer_household_uid": s["payer_household_uid"], "payer_purse": s["payer_purse"],
		"army_gold": game.gold, "required_funding": 0, "can_act": _gate(game, town_id) == "", "review": {}}
	if not out["can_act"]: return out
	var candidates: Array = []; var native_pool: Array = _draft_pool(town)
	for u in reserves(game):
		var a: Dictionary = _address(game, u)
		if u.dead or u.home_town != town_id or a.is_empty() or str(a["person"][4]) != "reserve" or game.deploy_block_reason(u) != "": continue
		candidates.append({"source": "reserve", "unit": u, "fid": u.family, "person_uid": str(a["person"][Persons.PERSON_UID]), "fee": 0,
			"wage": int(game.world.get("mobilization", {}).get("enlisted", {}).get(str(a["person"][Persons.PERSON_UID]), {}).get("wage", Army.wage("army", 0)))})
	for u in Diplomacy.visible_recruits(game, town):
		var a: Dictionary = _address(game, u)
		if u.dead or a.is_empty() or str(a["person"][4]) != "hire" or game.deploy_block_reason(u) != "": continue
		var offer: Dictionary = Recruits.offer(game, u)
		candidates.append({"source": "recruit", "unit": u, "fid": u.family, "person_uid": str(a["person"][Persons.PERSON_UID]), "fee": int(offer["hire_cost"]), "wage": int(offer["wage"])})
	for row in native_pool:
		candidates.append({"source": "draft", "row": row, "fid": int(row[2]), "fee": 5 * Item.COIN, "wage": int(Army.wage("army", 0))})
	out["reserve_available"] = candidates.filter(func(x): return x["source"] == "reserve").size()
	out["new_available"] = candidates.size() - int(out["reserve_available"]); out["eligible"] = candidates.size()
	var kit: Array = _kit(town); var food: Array = _food(town); var stock := 0
	var body_kit: Array = _armour_kit(town, BODY_SLOT); var helm_kit: Array = _armour_kit(town, HELM_SLOT); var padded_tid := _padded_tid()
	var padded_slot := str(DB.armor.get(padded_tid, {}).get("slot", "")) if padded_tid != "" else ""   # "clothing" for the gambeson
	for row in food: stock += int(row["quantity"])
	out["kit_available"] = kit.size(); out["food_available"] = stock
	out["body_available"] = body_kit.size(); out["helm_available"] = helm_kit.size()
	var plan: Array = []; var kit_used := 0; var body_used := 0; var helm_used := 0; var fees := 0; var daily := 0; var total := 0; var review_rows: Array = []; var family_used := {}
	var desired := mini(int(out["requested"]), maxi(0, LIMIT - game.company.size()))
	for candidate in candidates:
		if plan.size() >= desired: break
		var borrowed: Dictionary = {}
		var u: Unit = candidate.get("unit", null)
		var fid := int(candidate["fid"])
		if int(family_used.get(fid, 0)) >= Population.spare(People.fam_of(town, fid)): continue
		# A retained bow/private broken weapon remains owned by this exact Unit;
		# replacing it must not silently destroy its existing equipment.
		if u != null and u.weapon() != null and not _weapon(u.weapon()): continue
		if u == null or u.weapon() == null or not _weapon(u.weapon()):
			if kit_used >= kit.size(): continue
			borrowed = kit[kit_used]
		# v0.029: one body piece and one helmet for a man who lacks them, from the same
		# armory (borrowed) / shop (bought) pools as the weapon; a padded fallback piece
		# made new for PADDED_FEE once the town's body armour is used up.
		var body_piece: Dictionary = {}
		if u == null or not u.equip.has(BODY_SLOT):
			if body_used < body_kit.size(): body_piece = body_kit[body_used]
			elif padded_tid != "" and (u == null or not u.equip.has(padded_slot)): body_piece = {"source": "padded", "tid": padded_tid, "cost": PADDED_FEE}
		var helm_piece: Dictionary = {}
		if (u == null or not u.equip.has(HELM_SLOT)) and helm_used < helm_kit.size(): helm_piece = helm_kit[helm_used]
		var next_fees := fees + int(candidate["fee"]) + int(borrowed.get("cost", 0)) + int(body_piece.get("cost", 0)) + int(helm_piece.get("cost", 0))
		var order: Dictionary = _food_order(food, (plan.size() + 1) * MEALS)
		if int(order["quantity"]) < (plan.size() + 1) * MEALS: break
		var next_total := next_fees + int(order["cost"])
		var reserve_pay: int = (int(game.daily_wages()) + daily + int(candidate["wage"])) * 3
		if next_total + reserve_pay > int(game.gold):
			out["required_funding"] = maxi(int(out["required_funding"]), next_total + reserve_pay - int(game.gold)); break
		var row: Dictionary = candidate.duplicate(); row["kit"] = borrowed; row["body_kit"] = body_piece; row["helm_kit"] = helm_piece; plan.append(row)
		if not borrowed.is_empty(): kit_used += 1
		if body_piece.has("item"): body_used += 1
		if not helm_piece.is_empty(): helm_used += 1
		fees = next_fees; total = next_total; daily += int(candidate["wage"])
		family_used[fid] = int(family_used.get(fid, 0)) + 1
		review_rows.append([candidate["source"], candidate.get("person_uid", ""), candidate.get("row", []),
			int(u.uid) if u != null else -1, borrowed.get("item", null).uid if not borrowed.is_empty() else -1, candidate["fee"], borrowed.get("cost", 0), candidate["wage"],
			(body_piece["item"] as Item).uid if body_piece.has("item") else -1, int(body_piece.get("cost", 0)),
			(helm_piece["item"] as Item).uid if helm_piece.has("item") else -1, int(helm_piece.get("cost", 0)),
			str(body_piece.get("tid", "")) if str(body_piece.get("source", "")) == "padded" else ""])
	out["available"] = plan.size(); out["planned"] = plan.size(); out["food_units"] = plan.size() * MEALS
	out["food_per_day"] = plan.size() * 2; out["raise_cost"] = total; out["daily_pay"] = daily
	out["ok"] = not plan.is_empty()
	out["reason"] = "Raise %d of %d requested; actual manpower, weapons, meals and army funds limit the muster." % [plan.size(), out["requested"]] if out["ok"] else "No funded, equipped and supplied people can depart."
	var families: Array = []
	for fid in family_used:
		var family: Dictionary = People.fam_of(town, int(fid))
		families.append([fid, str(family.get("household_uid", "")), family.get("age_bins", {}).duplicate(true),
			family.get("pp", []).map(func(p): return [p[0], Persons.g(p, Persons.PERSON_UID, ""), p[2], p[3], p[4], p[5], p[6]])])
	out["review"] = {"town_id": town_id, "requested": out["requested"], "day": game.day, "payer": out["payer_household_uid"], "gold": game.gold,
		"company": game.company.map(func(x): return x.uid), "rows": review_rows, "food": _food_order(food, int(out["food_units"])), "cost": total}
	out["review"]["families"] = families
	out["review"]["ruler_uid"] = str(game.world.get("player_house", {}).get("ruler_uid", ""))
	return out

static func fund(game, amount: float) -> Dictionary:
	if game.get("_save_capture") != null: return {"ok": false, "reason": "Wait for the consistent save snapshot to finish."}
	if not is_finite(amount) or amount <= 0.0 or amount != floor(amount): return {"ok": false, "reason": "Choose a positive whole amount of house coin."}
	return Feudal.fund_army(game, amount)

static func _category(p: Array) -> String:
	return "old" if int(p[6]) == 1 else ("kids" if int(p[6]) == 2 else ("m" if int(p[2]) == 0 else "f"))

static func _entry(game, u: Unit, a: Dictionary) -> Dictionary:
	var state: Dictionary = _state(game); var key := str(a["person"][Persons.PERSON_UID])
	if not state["enlisted"].has(key):
		state["enlisted"][key] = {"unit_uid": u.uid, "person_uid": key, "household_uid": a["family"]["household_uid"],
			"home_town_id": u.home_town, "family_id": u.family, "wage": u.wage, "borrowed": []}
	return state["enlisted"][key]

static func _away(game, u: Unit, a: Dictionary) -> void:
	var p: Array = a["person"]; var f: Dictionary = a["family"]; var e: Dictionary = a["econ"]
	var category := _category(p)
	f[category] = int(f[category]) - 1; e["pop"] = int(e["pop"]) - 1
	if category in ["m", "f"]: e["adults"] = int(e["adults"]) - 1
	p[4] = "company"; p[5] = u.uid
	f.get("player_reserve_uids", {}).erase(str(u.uid))
	Persons.log_life(p, float(game.day), "serve", "company")
	Census.record_move(e, int(p[0]), "out", "", float(game.day), "raised with the house army")
	Families.reassign(e, f)

static func _new_unit(game, town: Dictionary) -> Unit:
	var source := str(town["faction"]); var race := Persons.race_of(town["econ"])
	if str(DB.factions[source]["race"]) != race:
		for fid in DB.factions:
			if str(DB.factions[fid].get("race", "")) == race and not Monsters.is_monster_faction(fid): source = fid; break
	var troop: Dictionary = Factory.pick_troop(game.rng, source).duplicate(true)
	troop["loadout"] = {}; troop["arrows"] = {}
	return Factory.make_troop(game.rng, source, troop, int(town.get("wealth", 2)))

## Battle medics: commoners assigned to tend the wounded. They do not fight in the rounds; after each clash your
## side wins they go onto the field (battle.gd aftermath). Skill "surgeon" grows with every man they tend.
static func is_medic(game, u: Unit) -> bool:
	return u != null and not game.world.is_empty() and _state(game).get("medics", {}).has(str(u.uid))

static func set_medic(game, u: Unit, on: bool) -> Dictionary:
	if u == null or u.dead or not game.company.has(u): return {"ok": false, "reason": "Only living members of the army can be medics."}
	if on and (is_house_rider(game, u) or Army.house_born(u)): return {"ok": false, "reason": "House members lead; medics are drawn from the common ranks."}
	var st := _state(game)
	if not st.has("medics"): st["medics"] = {}
	if on: st["medics"][str(u.uid)] = true
	else: st["medics"].erase(str(u.uid))
	if on: u.squad = -1
	command_plan(game); game.invalidate_deploy(); game.changed.emit()
	return {"ok": true, "reason": ("%s now serves as a battle medic." if on else "%s returns to the fighting ranks.") % u.name}

static func medics(game) -> Array:
	return game.company.filter(func(u): return not u.dead and is_medic(game, u))

## Household members who can ride with the army: living adults of the player's house, at home, not already serving.
static func household_candidates(game) -> Array:
	var out: Array = []
	for row in Dynasty.living_members(game):
		if int(row.get("unit_uid", -1)) >= 0: continue
		if str(row.get("state", "")) in ["company", "reserve", "captive"]: continue
		if int(row.get("age", 0)) < int(People.ages(str(row.get("race", "human")))["adult"]): continue
		out.append(row)
	return out

## A unit that is a member of the player's house (survives save/load: read from the person's register row).
static func is_house_rider(game, u: Unit) -> bool:
	if u == null or u.dead: return false
	if u.has_meta("house_member"): return true
	var a: Dictionary = _address(game, u)
	return not a.is_empty() and str(Persons.g(a["person"], Persons.HOUSE_UID, "")) == str(game.world.get("player_house", {}).get("house_uid", ""))

## One household member joins the field army as an officer: the person IS the unit (their name, age, family),
## so wounds, capture, death and experience in battle are theirs (campaign/battle_rounds.gd).
static func enlist_household(game, person_uid: String) -> Dictionary:
	var row: Dictionary = Dynasty.person(game, person_uid)
	if row.is_empty() or not bool(row.get("alive", false)): return {"ok": false, "reason": "This person is not a living member of your house."}
	var tid := str(row.get("town_id", ""))
	var reason := _gate(game, tid, false)
	if reason != "": return {"ok": false, "reason": reason}
	if game.company.size() >= LIMIT: return {"ok": false, "reason": "The army is at its full size."}
	var town: Dictionary = game.world["towns"][tid]
	var fid := int(row.get("family_id", -1))
	var f: Dictionary = People.fam_of(town, fid)
	if f.is_empty(): return {"ok": false, "reason": "This person's family record is missing."}
	var p: Array = Persons.by_pid(f, int(row.get("pid", -1)))
	if p.is_empty() or int(p[5]) >= 0 or str(p[4]) in ["company", "reserve", "captive"]: return {"ok": false, "reason": "%s is already serving." % str(row.get("name", ""))}
	if int(row.get("age", 0)) < int(People.ages(str(row.get("race", "human")))["adult"]): return {"ok": false, "reason": "%s is too young to ride with the army." % str(row.get("name", ""))}
	var u := _new_unit(game, town)
	People.last_person = p
	p[4] = "company"
	People.bind(town, fid, u, "company")   # the unit takes the person's own name, age and sex
	var a: Dictionary = _address(game, u)
	if a.is_empty(): return {"ok": false, "reason": "This person could not be enlisted."}
	_entry(game, u, a)
	_away(game, u, a)
	game.company.append(u)
	u.faction = "player"; u.wage = int(Army.wage("army", 0)) * 2; u.role = "officer"
	u.set_meta("house_member", true)
	command_plan(game); Diplomacy.roster_changed(game); game.invalidate_deploy()
	_history(game, "%s rides with the house army." % u.name); game.changed.emit()
	return {"ok": true, "reason": "%s rides with the army as an officer." % u.name, "unit": u}

static func muster(game, town_id: String, count: int = 100, review: Dictionary = {}) -> Dictionary:
	var q: Dictionary = quote(game, town_id, count)
	if not q["ok"]: return q
	if not review.is_empty() and review != q["review"]: return {"ok": false, "reason": "The muster changed. Review the current people, stock and price again."}
	var town: Dictionary = game.world["towns"][town_id]; var raised := 0; var cost := 0
	var initial_food: Array = _food(town)
	# Rebuild exact selected identities from the detached review; no Unit creation in quotes.
	for row in q["review"]["rows"]:
		var u: Unit = null; var fid := int(row[2][2]) if row[0] == "draft" else -1
		if row[0] == "reserve": u = reserve_unit(game, int(row[3]), town_id)
		elif row[0] == "recruit":
			for candidate in town.get("recruits", []):
				if candidate.uid == int(row[3]): u = candidate; break
		else:
			var single: Array = [row[2].duplicate()]
			fid = People.draft(town, single, "company")
			if fid < 0: break
			u = _new_unit(game, town)
			People.bind(town, fid, u, "company") # last_person consumed atomically
			var f: Dictionary = People.fam_of(town, fid)
			var serving: Dictionary = f["serve"]
			serving["company"] = maxi(0, int(serving.get("company", 0)) - 1)
			if int(serving["company"]) == 0: serving.erase("company")
		if u == null: break
		var a: Dictionary = _address(game, u)
		if a.is_empty(): break
		var entry: Dictionary = _entry(game, u, a)
		var accepted_fee := int(row[5])
		if row[0] == "recruit":
			var before_hire := int(game.gold)
			if not Recruits.hire(game, town, u): break
			accepted_fee = before_hire - int(game.gold)
		else:
			reserves(game).erase(u)
			_away(game, u, a)
			game.gold -= int(row[5]); a["family"]["purse"] = float(a["family"]["purse"]) + int(row[5])
			if int(row[5]) > 0: TownEcon.gold_out(-float(row[5]))
			game.company.append(u)
		cost += accepted_fee
		if row[0] != "recruit": u.wage = int(row[7])
		entry["wage"] = u.wage; u.faction = "player"
		if int(row[4]) >= 0:
			var item: Item = null; var owner := ""
			for stock_name in ["armory_items", "shop"]:
				for candidate in town.get(stock_name, []):
					if candidate.uid == int(row[4]): item = candidate; owner = stock_name; break
				if item != null: break
			if item != null:
				town[owner].erase(item); u.equip["main_hand"] = item
				if owner == "armory_items": entry["borrowed"].append({"item_uid": item.uid, "town_id": town_id})
				else:
					game.gold -= int(row[6]); cost += int(row[6]); Goods.pay_market(town, float(row[6])); TownEcon.led(town["econ"], "used", "arms", 1)
		# v0.029: the body piece (row 8/9) and helmet (row 10/11) the quote planned, issued
		# under the weapon's rules; row 12 is a padded fallback template made new for its fee.
		if row.size() > 11:
			for spec in [[8, 9, BODY_SLOT], [10, 11, HELM_SLOT]]:
				if int(row[int(spec[0])]) < 0 or u.equip.has(str(spec[2])): continue
				var piece: Item = null; var piece_owner := ""
				for stock_name in ["armory_items", "shop"]:
					for candidate in town.get(stock_name, []):
						if candidate.uid == int(row[int(spec[0])]): piece = candidate; piece_owner = stock_name; break
					if piece != null: break
				if piece != null:
					town[piece_owner].erase(piece); u.equip[str(spec[2])] = piece
					if piece_owner == "armory_items": entry["borrowed"].append({"item_uid": piece.uid, "town_id": town_id})
					else:
						game.gold -= int(row[int(spec[1])]); cost += int(row[int(spec[1])]); Goods.pay_market(town, float(row[int(spec[1])])); TownEcon.led(town["econ"], "used", "arms", 1)
		if row.size() > 12 and str(row[12]) != "":
			var padded := Item.make(str(row[12]))
			var padded_slot := padded.slot()
			if padded_slot != "" and not u.equip.has(padded_slot):
				u.equip[padded_slot] = padded
				game.gold -= int(row[9]); cost += int(row[9]); Goods.pay_market(town, float(row[9]))
		raised += 1
	# Actual accepted people, not requested quota, determine food and receipts.
	var order: Dictionary = _food_order(initial_food, raised * MEALS)
	for purchase in order["orders"]:
		var n := int(purchase["quantity"]); var coins := int(purchase["cost"])
		Goods.take(town, str(purchase["good"]), n); Goods.pay_market(town, coins); game.gold -= coins; cost += coins
		Food.add_stock(game, "meal", n, 0, str(purchase["good"]), Food.food_name(town, str(purchase["good"])))
	command_plan(game); Food.sync(game); Diplomacy.roster_changed(game); game.invalidate_deploy()
	_history(game, "Raised %d people at %s for %d coins." % [raised, town["name"], cost]); game.changed.emit()
	return {"ok": raised > 0, "reason": "Raised %d of %d requested." % [raised, q["requested"]], "requested": q["requested"],
		"raised": raised, "partial": raised < int(q["requested"]), "cost": cost, "food_units": int(order["quantity"])}

## v0.029 "Refit army": at the home town, plan one body piece ("body") and one helmet ("helm")
## for every living company unit missing them, from that town's armory (borrowed) or shop
## (bought, best affordable first), keeping three days of pay in hand as quote() does.
static func refit_quote(game, town_id) -> Dictionary:
	var tid := str(town_id)
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	var out := {"ok": false, "reason": _gate(game, tid), "town_id": tid, "town_name": str(town.get("name", tid)),
		"fitted": 0, "pieces": 0, "cost": 0, "army_gold": game.gold, "review": {}}
	if str(out["reason"]) != "": return out
	var kits := {}
	kits[BODY_SLOT] = _armour_kit(town, BODY_SLOT); kits[HELM_SLOT] = _armour_kit(town, HELM_SLOT)
	var used := {}
	var reserve_pay := int(game.daily_wages()) * 3
	var rows: Array = []; var total := 0; var fitted := {}
	for u in game.company:
		if u == null or u.dead: continue
		for slot_name in [BODY_SLOT, HELM_SLOT]:
			if u.equip.has(slot_name): continue
			var pick: Dictionary = {}
			for piece in kits[slot_name]:
				var it: Item = piece["item"]
				if used.has(it.get_instance_id()): continue
				if int(piece["cost"]) > 0 and total + int(piece["cost"]) + reserve_pay > int(game.gold): continue
				pick = piece; break
			if pick.is_empty(): continue
			used[(pick["item"] as Item).get_instance_id()] = true
			rows.append([u.uid, slot_name, (pick["item"] as Item).uid, int(pick["cost"])])
			total += int(pick["cost"]); fitted[u.uid] = true
	out["fitted"] = fitted.size(); out["pieces"] = rows.size(); out["cost"] = total
	out["ok"] = not rows.is_empty()
	out["reason"] = "Fit %d people with %d armour pieces for %d coins." % [fitted.size(), rows.size(), total] if out["ok"] else "No living soldier here lacks body armour or a helmet that this town can supply and the army purse can pay for."
	out["review"] = {"town_id": tid, "day": game.day, "gold": game.gold,
		"company": game.company.map(func(x): return x.uid), "rows": rows, "cost": total,
		"ruler_uid": str(game.world.get("player_house", {}).get("ruler_uid", ""))}
	return out

static func refit(game, town_id, review) -> Dictionary:
	var tid := str(town_id)
	var q: Dictionary = refit_quote(game, tid)
	if not q["ok"]: return q
	if review is Dictionary and not (review as Dictionary).is_empty() and review != q["review"]:
		return {"ok": false, "reason": "The refit changed. Review the current roster, stock and price again.", "fitted": 0, "cost": 0, "review": q["review"]}
	var town: Dictionary = game.world["towns"][tid]
	var fitted := {}; var pieces := 0; var cost := 0
	for row in q["review"]["rows"]:
		var u: Unit = null
		for candidate in game.company:
			if candidate.uid == int(row[0]): u = candidate; break
		if u == null or u.dead or u.equip.has(str(row[1])): continue
		var item: Item = null; var owner := ""
		for stock_name in ["armory_items", "shop"]:
			for candidate in town.get(stock_name, []):
				if candidate.uid == int(row[2]): item = candidate; owner = stock_name; break
			if item != null: break
		if item == null: continue
		town[owner].erase(item); u.equip[str(row[1])] = item
		if owner == "armory_items":
			var a: Dictionary = _address(game, u)
			if not a.is_empty(): _entry(game, u, a)["borrowed"].append({"item_uid": item.uid, "town_id": tid})
		else:
			game.gold -= int(row[3]); cost += int(row[3]); Goods.pay_market(town, float(row[3])); TownEcon.led(town["econ"], "used", "arms", 1)
		fitted[u.uid] = true; pieces += 1
	game.invalidate_deploy()
	_history(game, "Refitted %d people with %d armour pieces at %s for %d coins." % [fitted.size(), pieces, town["name"], cost]); game.changed.emit()
	return {"ok": pieces > 0, "reason": "Fitted %d people with %d armour pieces for %d coins." % [fitted.size(), pieces, cost],
		"fitted": fitted.size(), "pieces": pieces, "cost": cost, "review": q["review"]}

static func command_plan(game) -> void:
	# Real enlisted officers: one per25 living people, up to eight at200. Native
	# Fighter/Officer rally consumes these actual UID squad links unchanged.
	var living: Array = game.company.filter(func(u): return not u.dead and not is_medic(game, u))   # medics stay out of the squads
	# Only house members lead: commoners stay in the ranks; with no house member free, a group goes unled.
	var noble := func(u): return is_house_rider(game, u) or Army.house_born(u)
	var leaders: Array = living.filter(func(u): return u.is_officer() and noble.call(u))
	var need := int(ceil(float(living.size()) / (GROUP + 1)))
	for u in living:
		if leaders.size() >= need: break
		if not leaders.has(u) and noble.call(u): leaders.append(u)
	var configs: Dictionary = {}
	for leader in leaders:
		configs[leader.uid] = game.squads.get(leader.uid, {"uniform": {}, "material": "any"})
	game.squads = configs
	for u in living:
		u.role = "officer" if leaders.has(u) else "troop"; u.squad = -1
	var index := 0
	for u in living:
		if leaders.has(u) or leaders.is_empty(): continue   # no house member to lead them: unassigned
		u.squad = leaders[mini(index / GROUP, leaders.size() - 1)].uid; index += 1

static func stand_down_quote(game, town_id: String = "") -> Dictionary:
	if town_id == "": town_id = str(game.location)
	var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
	var rows: Array = []; var away := 0; var dead := 0
	for u in game.company:
		if u.dead: dead += 1; continue
		if u.home_town != town_id: away += 1; continue
		var a: Dictionary = _address(game, u)
		if not a.is_empty() and str(a["person"][4]) == "company": rows.append([u.uid, str(a["person"][Persons.PERSON_UID]), str(a["family"]["household_uid"])])
	var reason := _gate(game, town_id, false)
	if reason == "" and rows.is_empty(): reason = "No living enlisted people can return to this home."
	return {"ok": reason == "", "reason": reason if reason != "" else "Return %d living people to their actual home households; retained wounds remain." % rows.size(),
		"town_id": town_id, "town_name": str(town.get("name", town_id)), "eligible": rows.size(), "company": game.company.size(),
		"away": away, "dead": dead, "daily_pay": game.daily_wages(), "army_gold": game.gold,
		"review": {"town_id": town_id, "day": game.day, "rows": rows, "ruler_uid": str(game.world.get("player_house", {}).get("ruler_uid", "")),
			"payer": str(game.world.get("player_house", {}).get("household_uid", ""))}}

static func _return(game, u: Unit) -> bool:
	var a: Dictionary = _address(game, u)
	if a.is_empty() or not game.company.has(u) or u.dead or str(a["person"][4]) != "company": return false
	if not Families.restore_returned(a["econ"], a["family"]): return false
	var entry: Dictionary = _entry(game, u, a); var p: Array = a["person"]; var f: Dictionary = a["family"]; var e: Dictionary = a["econ"]
	_return_loans(game, entry)
	entry["wage"] = u.wage; u.wage = 0; u.unpaid_days = 0; u.squad = -1
	game.company.erase(u); reserves(game).append(u)
	p[4] = "reserve"; p[5] = u.uid; var category := _category(p)
	f[category] = int(f[category]) + 1; e["pop"] = int(e["pop"]) + 1
	if category in ["m", "f"]: e["adults"] = int(e["adults"]) + 1
	if not f.has("player_reserve_uids"): f["player_reserve_uids"] = {}
	f["player_reserve_uids"][str(u.uid)] = true
	Persons.log_life(p, float(game.day), "serve", "reserve"); Census.record_move(e, int(p[0]), "in", "", float(game.day), "stood down from the house army")
	Families.reassign(e, f)
	return true

static func _return_loans(game, entry: Dictionary) -> void:
	for loan in entry["borrowed"]:
		var owner: Dictionary = game.world.get("towns", {}).get(str(loan["town_id"]), {})
		if owner.is_empty(): continue # keep unresolved estate reference, never mint a replacement
		var actual: Item = null
		for holder in game.company + reserves(game):
			for slot in holder.equip.keys():
				var it: Item = holder.equip[slot]
				if it.uid == int(loan["item_uid"]): actual = it; holder.equip.erase(slot); break
			if actual != null: break
		if actual == null:
			for it in game.stash:
				if it.uid == int(loan["item_uid"]): actual = it; game.stash.erase(it); break
		if actual != null: ArmsTrade.armory(owner).append(actual)
	entry["borrowed"] = entry["borrowed"].filter(func(loan): return not game.world.get("towns", {}).has(str(loan["town_id"])))

static func stand_down(game, town_id: String = "", review: Dictionary = {}) -> Dictionary:
	var q: Dictionary = stand_down_quote(game, town_id)
	if not q["ok"]: return q
	if not review.is_empty() and review != q["review"]: return {"ok": false, "reason": "The returning roster changed. Review it again."}
	var count := 0
	for u in game.company.duplicate():
		if u.home_town == q["town_id"] and _return(game, u): count += 1
	command_plan(game); game.invalidate_deploy(); Diplomacy.roster_changed(game)
	_history(game, "%d living people stood down at %s." % [count, q["town_name"]]); game.changed.emit()
	return {"ok": count > 0, "reason": "%d people returned home; no field wages are owed while in reserve." % count,
		"returned": count, "raised": 0, "requested": q["eligible"], "partial": count < game.company.size() + count, "cost": 0, "food_units": 0}

static func dismiss(game, u: Unit) -> Dictionary:
	if u == null or u.dead or not manages(game, u): return {"ok": false, "reason": "No living registered enlistment can return."}
	var reason := _gate(game, u.home_town, false)
	if reason != "": return {"ok": false, "reason": reason}
	if not _return(game, u): return {"ok": false, "reason": "This person has already returned home."}
	command_plan(game); game.invalidate_deploy(); Diplomacy.roster_changed(game); game.changed.emit()
	return {"ok": true, "reason": ""}

## Native hire/desertion integration: no second departure, pay or fabricated person.
static func register_company(game, u: Unit) -> bool:
	var a: Dictionary = _address(game, u)
	if a.is_empty() or not game.company.has(u) or str(a["person"][4]) != "company": return false
	_entry(game, u, a)
	return true

## Actual deserters travel home through the existing native return consequence.
## Caller owns the desertion decision; this only transfers the exact enlistment.
static func return_home(game, u: Unit) -> bool:
	if not _return(game, u): return false
	command_plan(game); game.invalidate_deploy(); Diplomacy.roster_changed(game)
	return true

## Call only for an actual natural-death holder BEFORE the native sickness
## erasure. The caller retains the sole person/census/population death path.
static func natural_death(game, u: Unit) -> void:
	if u == null or (not game.company.has(u) and not reserves(game).has(u)): return
	var a: Dictionary = _address(game, u)
	if a.is_empty() or str(a["person"][4]) not in ["company", "reserve"]: return
	_settle_private_gear(game, u, a)
	reserve_died(game, u)

static func _settle_private_gear(game, u: Unit, a: Dictionary) -> void:
	var state: Dictionary = _state(game); var entry: Dictionary = _entry(game, u, a)
	_return_loans(game, entry)
	if not state.has("estate_items"): state["estate_items"] = []
	var moved := 0
	for slot in u.equip.keys():
		var it: Item = u.equip[slot]
		var record := {"item": it, "person_uid": str(a["person"][Persons.PERSON_UID]),
			"household_uid": str(a["family"]["household_uid"]), "home_town_id": u.home_town, "day": game.day}
		for loan in entry["borrowed"]:
			if int(loan["item_uid"]) == it.uid: record["loan_town_id"] = str(loan["town_id"])
		state["estate_items"].append(record); u.equip.erase(slot); moved += 1
	if not u.quiver.is_empty():
		if not state.has("estate_quivers"): state["estate_quivers"] = []
		state["estate_quivers"].append({"goods": u.quiver.duplicate(), "person_uid": str(a["person"][Persons.PERSON_UID]),
			"household_uid": str(a["family"]["household_uid"]), "home_town_id": u.home_town, "day": game.day})
		u.quiver.clear(); moved += 1
	if moved > 0: _history(game, "%s's retained private equipment awaits household estate settlement." % u.name)

static func reserve_died(game, u: Unit) -> void:
	if u == null: return
	var a: Dictionary = _address(game, u)
	# Only a home-held reserve has private gear without the native field loot
	# owner. Company battlefield casualties already use that real loot pathway.
	if reserves(game).has(u) and not a.is_empty():
		_settle_private_gear(game, u, a)
	if not a.is_empty(): a["family"].get("player_reserve_uids", {}).erase(str(u.uid))
	reserves(game).erase(u)
	var enlisted: Dictionary = game.world.get("mobilization", {}).get("enlisted", {})
	for key in enlisted.keys():
		if int(enlisted[key].get("unit_uid", -1)) == u.uid: enlisted.erase(key)

## Actual census death notification, including native missing-unit sweeps which
## have no physical Unit to release. Only retire exact ID bookkeeping here;
## natural deaths and battle outcomes keep their distinct physical gear owners.
static func retire_person(game, e: Dictionary, f: Dictionary, p: Array) -> void:
	var uid := str(Persons.g(p, Persons.PERSON_UID, ""))
	var enlisted: Dictionary = game.world.get("mobilization", {}).get("enlisted", {})
	var row: Dictionary = enlisted.get(uid, {})
	if row.is_empty() or str(row.get("household_uid", "")) != str(f.get("household_uid", "")): return
	var town: Dictionary = game.world.get("towns", {}).get(str(row.get("home_town_id", "")), {})
	if not is_same(town.get("econ", {}), e) or not is_same(People.fam_of(town, int(row.get("family_id", -1))), f): return
	# record_person(false) is also native forget/sync/packing, not necessarily
	# death. A real live holder with this exact person identity remains enlisted.
	for u in game.company + reserves(game):
		if u is Unit and not u.dead and u.uid == int(row.get("unit_uid", -1)) and u.home_town == str(row.get("home_town_id", "")) and u.family == int(row.get("family_id", -1)):
			if ServiceIdentity.unit_person(e, f, p, u): return
	enlisted.erase(uid)

static func _history(game, line: String) -> void:
	var state: Dictionary = _state(game)
	state["history"].append({"day": game.day, "text": line})
	while state["history"].size() > 40: state["history"].pop_front()
	CampaignWorld.log_event(game, line)
