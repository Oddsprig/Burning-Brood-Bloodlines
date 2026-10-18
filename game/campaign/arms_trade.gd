class_name ArmsTrade
extends RefCounted
## Real battle recovery, paid market/forge procurement and stored garrison reserves.
## v0.024: internal redistribution every ten days; special arms contracts retired.
## Existing merchant caravans remain ordinary trade. Items and coins are never created
## by procurement or internal supply. Reserves exclude equipment already issued.

const RESERVE_MULTIPLIER := 2.5
const SUPPLY_EVERY := 10
const ARMORY_EVERY := 3
const ORDER_SHARE := 0.75
const FENCE_SHARE := 0.5       # [ours] what a head pays a man of another realm for the kit he brings home

const CLS_WORDS := {"w_sword": "swords", "w_spear": "spears", "w_axe": "axes", "w_mace": "maces", "w_dagger": "daggers",
	"w_hammer": "hammers", "w_polearm": "polearms", "w_bow": "bows", "a_body": "body armour", "a_helm": "helms",
	"a_legs": "greaves", "a_shield": "shields", "a_hands": "bracers", "a_feet": "boots"}

## Ledger of the dead men's kit (tests): looted (kept by the winners in the field), rekit (re-armed men), home (into a
## home armory or hoard), scrapped, lost (left on the field), fenced (handed in for coin), bought (stalls -> armory).
static var ledger: Dictionary = {}

static func led(k: String, n: int = 1) -> void:
	ledger[k] = int(ledger.get(k, 0)) + n

# ================================================================== item classes
static var _cls: Dictionary = {}
## The armory class of a template: "w_<skill>" for weapons and bows, "a_<slot>" for metal armour and shields; "" for
## clothing and cloth/leather gear (tailors' work, outside the armory).
static func cls(tid: String) -> String:
	if _cls.has(tid):
		return _cls[tid]
	var c := ""
	var t := DB.template(tid)
	if not t.is_empty():
		if DB.is_bow(tid):
			c = "w_bow"
		elif DB.is_weapon(tid):
			c = "w_" + String(t.get("skill", "weapon"))
		else:
			var mats: Array = t.get("materials", [])
			var slot := String(t.get("slot", ""))
			if mats.has("copper") or mats.has("tin") or mats.has("bronze") or slot == "shield":
				c = "a_" + slot
	_cls[tid] = c
	return c

## The role a piece fills (slot equivalence, Douglas): one-handed or two-handed weapon, bow, or the armour's slot.
static func role(tid: String) -> String:
	var t := DB.template(tid)
	if DB.is_bow(tid):
		return "ranged"
	if DB.is_weapon(tid):
		return "main_hand_2h" if t.get("two_handed", false) else "main_hand_1h"
	var s := String(t.get("slot", ""))
	return "off_hand" if s == "shield" else s

## Coarse role of a class for the armory's shortfall count (weapons: any melee weapon).
static func cls_role(c: String) -> String:
	if c == "w_bow":
		return "ranged"
	if c.begins_with("w_"):
		return "main_hand"
	return c.substr(2)

static func cls_word(c: String) -> String:
	return String(CLS_WORDS.get(c, c.substr(2).replace("_", " ")))

static func class_counts(items: Array) -> Dictionary:
	var out := {}
	for it in items:
		var c := cls(it.tid)
		if c != "":
			out[c] = int(out.get(c, 0)) + 1
	return out

static func armory(town: Dictionary) -> Array:
	if not town.has("armory_items"):
		town["armory_items"] = []
	return town["armory_items"]

static func race_of_town(town: Dictionary) -> String:
	if TownEcon.has_econ(town):
		return String(TownEcon.culture_of(town["econ"]).get("race", ""))
	var c := String(town.get("culture", ""))
	return String(TownEcon.data()["cultures"].get(c, {}).get("race", ""))

# ================================================================== maker's marks
## A smith's (or bowyer's) mark on a new piece: the business, the town, the race of its makers.
static func mark(it: Item, town: Dictionary, b: Dictionary) -> void:
	var who := ""
	if TownEcon.has_econ(town) and not b.is_empty():
		who = Businesses.title(town["econ"], b)
	it.mark = {"n": who, "b": int(b.get("id", -1)), "t": String(town.get("id", "")), "tn": String(town.get("name", "")),
		"r": race_of_town(town)}

## Pre-history pieces of a town's own style (opening stalls, world-gen kit): marked with the town's first forge.
static func mark_old(it: Item, town: Dictionary) -> void:
	if not it.mark.is_empty():
		return
	var style := String(it.tmpl().get("culture", ""))
	if style != String(town.get("culture", "")):
		return   # imported before anyone kept count: maker unknown
	var kind := "bowyer" if DB.is_bow(it.tid) else ("weaponsmith" if it.is_weapon() else "armorsmith")
	var b: Dictionary = {}
	if TownEcon.has_econ(town):
		for r in town["econ"]["biz"]:
			if r["type"] == kind:
				b = r
				break
	mark(it, town, b)

# ================================================================== troop kit
static var _lo: Dictionary = {}
## The armory part of a man's troop loadout: {slot: {"tids": [..], "opt": bool}} (opt: the template may leave it empty).
static func loadout_of(u: Unit) -> Dictionary:
	var key := u.faction + "|" + u.title
	if _lo.has(key):
		return _lo[key]
	var out := {}
	var f: Dictionary = DB.factions.get(u.faction, {})
	var tn := u.title.trim_prefix("militia ")
	for t in f.get("troops", []):
		if String(t.get("name", "")) != tn:
			continue
		out = troop_loadout(t)
		break
	_lo[key] = out
	return out

## The armory part of a troop template's loadout (loadout_of).
static func troop_loadout(t: Dictionary) -> Dictionary:
	var out := {}
	var lo: Dictionary = t.get("loadout", {})
	for slot in lo:
		var ch := []
		var opt := false
		for tid in lo[slot]:
			if String(tid) == "":
				opt = true
			elif cls(String(tid)) != "":
				ch.append(String(tid))
		if not ch.is_empty():
			out[slot] = {"tids": ch, "opt": opt}
	return out

## v0.014 (Douglas 23:02: "some caravans get naked people guarding them"): the most guards a caravan of this town
## takes on the road (Caravans.spawn: 2 + 0-2 + wealth / 2).
static func max_guards(town: Dictionary) -> int:
	return 4 + int(town.get("wealth", 2)) / 2

static var _gk: Dictionary = {}
## Armory pieces one man of the realm's troops carries when fully kitted, by class (his troop picked by the troops'
## weights, as Factory.pick_troop does; every armory slot of his loadout counts, the optional ones too: the town kits
## its own men out). A two-handed weapon leaves no hand for a shield.
static func kit_per_man(fid: String) -> Dictionary:
	if _gk.has(fid):
		return _gk[fid]
	var out := {}
	var troops: Array = DB.factions.get(fid, {}).get("troops", [])
	var tot := 0.0
	for t in troops:
		tot += float(t.get("w", 1))
	for t in troops:
		var wt := float(t.get("w", 1)) / maxf(1.0, tot)
		var lo := troop_loadout(t)
		var two := false
		if lo.has("main_hand"):
			two = bool(DB.template(String(lo["main_hand"]["tids"][0])).get("two_handed", false))
		for slot in lo:
			if slot == "off_hand" and two:
				continue
			var c := cls(String(lo[slot]["tids"][0]))
			out[c] = float(out.get(c, 0.0)) + wt
	_gk[fid] = out
	return out

## The armory slots a man of a town force lacks (full: the optional ones too), by class.
static func gaps_of(units: Array, full: bool = true) -> Dictionary:
	var out := {}
	for u in units:
		if not _is_person(u):
			continue
		var lo := loadout_of(u)
		for slot in lo:
			if u.equip.has(slot) or (bool(lo[slot]["opt"]) and not full):
				continue
			if slot == "off_hand" and u.weapon() != null and u.weapon().tmpl().get("two_handed", false):
				continue
			var c := cls(String(lo[slot]["tids"][0]))
			out[c] = int(out.get(c, 0)) + 1
	return out

static func _is_person(u) -> bool:
	return u is Unit and not u.dead and not u.race_def().get("creature", false)

static var _cen_key := ""
static var _cen: Dictionary = {}
static var _cen_cv: Dictionary = {}
## Kit the forces of each home town carry, by class: {town id: {class: men}} (an optional slot counts half). Militia
## and every people band with that home (caravans, camps, dens and beasts aside). Cached per day.
## v0.014: also the armory pieces this town's caravan guards have out on the road ({town id: {class: pieces}},
## _cen_cv): the guards' kit is the armory's, only away for the trip (targets()).
static func census(game) -> Dictionary:
	var w: Dictionary = game.world
	var key := "%d|%d" % [int(game.day), int(w.get("seed", 0))]
	if key == _cen_key:
		return _cen
	var out := {}
	var cv := {}
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		var k := String(wb.get("kind", ""))
		if k == "caravan" and wb.get("outfitted", false):
			var row2: Dictionary = cv.get(String(wb.get("origin", "")), {})
			for u in wb["units"]:
				if _is_person(u):
					for s in u.equip:
						var c2 := cls(u.equip[s].tid)
						if c2 != "":
							row2[c2] = int(row2.get(c2, 0)) + 1
			cv[String(wb.get("origin", ""))] = row2
			continue
		if k in ["caravan", "camp", "den", "beasts", "bandit"] or wb.get("deserter", false):
			continue
		var home := String(wb.get("home", ""))
		if not w["towns"].has(home):
			continue
		var row: Dictionary = out.get(home, {})
		for u in wb["units"]:
			if not _is_person(u):
				continue
			var lo := loadout_of(u)
			for slot in lo:
				var c := cls(String(lo[slot]["tids"][0]))
				row[c] = float(row.get(c, 0.0)) + (0.5 if lo[slot]["opt"] else 1.0)
		out[home] = row
	_cen = out
	_cen_cv = cv
	_cen_key = key
	return out

# ================================================================== the head's armory (daily town pass)
## Existing supported population: living garrison plus the largest active origin
## caravan. Field armies are not silently included. Return a fresh array.
static func supported_units(game, town: Dictionary) -> Array:
	if game == null: return []
	var units := TownDefence.garrison(game, String(town["id"]))
	var caravan := []
	var ids: Array = game.world.get("warbands", {}).keys()
	ids.sort()
	for wid in ids:
		var wb: Dictionary = game.world["warbands"][wid]
		if String(wb.get("kind", "")) != "caravan" or String(wb.get("origin", "")) != String(town["id"]): continue
		var alive: Array = (wb.get("units", []) as Array).filter(func(u): return u is Unit and not u.dead and not u.race_def().get("creature", false))
		if alive.size() > caravan.size(): caravan = alive
	units.append_array(caravan)
	return units.filter(func(u): return u is Unit and not u.dead and not u.race_def().get("creature", false))

static func requirements(game, town: Dictionary) -> Dictionary:
	var units := supported_units(game, town)
	return _levy(_requirements_of(units), units.size(), town)

## Claude Edition: the armory also keeps kit for a levy the lord (or a player house) can raise, 30 + 40 per size
## step people (30..190), in the same mix as the town's reserve, now that the standing reserve itself is small.
static func _levy(need: Dictionary, n: int, town: Dictionary) -> Dictionary:
	var levy := 30 + 40 * clampi(int(town.get("size", 1)), 0, 4)
	if n <= 0 or n >= levy: return need
	var f := float(levy) / float(n)
	var out := {}
	for c in need: out[c] = int(ceil(float(need[c]) * f))
	return out

static func _requirements_of(units: Array) -> Dictionary:
	var need := {}
	for u in units:
		var loadout := loadout_of(u)
		for slot in loadout:
			var c := cls(String(loadout[slot]["tids"][0]))
			if c != "": need[c] = int(need.get(c, 0)) + 1
	return need

static func reserve_amount(n: int) -> int:
	return int(ceil(float(n) * RESERVE_MULTIPLIER))

static func role_counts(counts: Dictionary) -> Dictionary:
	var out := {}
	for c in counts:
		var r := cls_role(String(c))
		out[r] = int(out.get(r, 0)) + int(counts[c])
	return out

## Round once per interchangeable role, then apportion class preferences. Foreign
## melee substitutes cover the same reserve; rounding each class would inflate it.
static func targets(game, town: Dictionary) -> Dictionary:
	return _targets_of(requirements(game, town))

static func _targets_of(need: Dictionary) -> Dictionary:
	var role_need := role_counts(need)
	var groups := {}
	var tgt := {}
	var assigned := {}
	var classes: Array = need.keys(); classes.sort()
	for c in classes:
		var r := cls_role(String(c))
		if not groups.has(r): groups[r] = []
		(groups[r] as Array).append(c)
		tgt[c] = int(floor(float(need[c]) * RESERVE_MULTIPLIER))
		assigned[r] = int(assigned.get(r, 0)) + int(tgt[c])
	for r in groups:
		var left := reserve_amount(int(role_need[r])) - int(assigned[r])
		for c in groups[r]:
			if left <= 0: break
			if int(need[c]) % 2 == 1:
				tgt[c] = int(tgt[c]) + 1
				left -= 1
	return tgt

static func arrow_requirement(game, town: Dictionary) -> int:
	return _arrow_requirement_of(supported_units(game, town))

static func _arrow_requirement_of(units: Array) -> int:
	var n := 0
	for u in units:
		if u.equip.has("ranged"): n += DB.QUIVER_MAX
	return n

static func arrow_target(game, town: Dictionary) -> int:
	return reserve_amount(arrow_requirement(game, town))

static func arrow_stock(town: Dictionary) -> int:
	var n := 0
	var stock: Dictionary = town.get("econ", {}).get("armory", {})
	for k in DB.arrows: n += int(stock.get(k, 0))
	return n

static func refresh_equipment(game, town: Dictionary) -> void:
	var e: Dictionary = town["econ"]
	e["arms_tgt"] = targets(game, town)
	e["arms_have"] = class_counts(armory(town))
	e["arms_short"] = _short(e["arms_tgt"], e["arms_have"])

static func refresh_reserve(game, town: Dictionary) -> void:
	# No roster or issued gear changes between these two native reserve reads.
	# Keep this fresh supported set local to this one synchronous refresh.
	var units := supported_units(game, town)
	var e: Dictionary = town["econ"]
	e["arms_tgt"] = _targets_of(_levy(_requirements_of(units), units.size(), town))
	e["arms_have"] = class_counts(armory(town))
	e["arms_short"] = _short(e["arms_tgt"], e["arms_have"])
	e["arrow_reserve"] = reserve_amount(_arrow_requirement_of(units))

## TownEcon.daily_pass: targets, the militia's re-kit, the head buys short classes off his own stalls (local first),
## days short per class (contracts look at those).
static func econ_daily(game, town: Dictionary, e: Dictionary, day: int = -1, every: bool = true) -> void:
	var phase_started := Time.get_ticks_usec()
	var stock := armory(town)
	for i in range(stock.size() - 1, -1, -1):
		if cls(stock[i].tid) == "" and not stock[i].is_legend():
			(town["shop"] as Array).append(stock[i])
			stock.remove_at(i)
	var tid := String(town["id"])
	if every and ((day if day >= 0 else int(e.get("day", 0))) + absi(tid.hash())) % ARMORY_EVERY != 0:
		return   # the head looks at his armory every few days (towns staggered)
	var mil: Array = TownDefence.garrison(game, tid) if game != null else []
	if game != null:
		# Stock only shrinks within this pass: identical missing slots stay missing.
		rekit_units(game, town, mil, false, {}, true)   # first what the armory already holds
	Perf.record_us("Equipment existing issue", Time.get_ticks_usec() - phase_started)
	phase_started = Time.get_ticks_usec()
	var tgt := targets(game, town)
	var arm := armory(town)
	var have := class_counts(arm)
	var short := _short(tgt, have)
	Perf.record_us("Equipment targets", Time.get_ticks_usec() - phase_started)
	phase_started = Time.get_ticks_usec()
	var purchase_usec := 0
	var purchased_issue_usec := 0
	var cant_pay := 0.0   # stall pieces of a short class the treasury could not pay for (their value, how many)
	var cant_n := 0
	var bought := 0
	var budget := 0.0
	if not short.is_empty():
		# The arms bill stays above the treasury's whole short line (arms_reserve). One
		# look spends at most a tenth of that excess, so a restock cannot empty the chest.
		var excess := maxf(0.0, float(e["treasury"]) - arms_reserve(game, town, e))
		budget = excess * 0.10
		var shop: Array = town.get("shop", [])
		var mkt: Dictionary = e["biz"][int(e["mkt"])]
		var i := 0
		while i < shop.size() and not short.is_empty():
			var it: Item = shop[i]
			var c := cls(it.tid)
			var wanted := shortage_class(short, c)
			if wanted != "":
				var p := Economy.base_value(town, it)
				if p <= budget and float(e["treasury"]) >= p:
					shop.remove_at(i)
					arm.append(it)
					budget -= p
					bought += 1
					e["treasury"] = float(e["treasury"]) - p
					note_arms_spend(e, p)
					mkt["till"] = float(mkt["till"]) + p
					e["stats"]["sales"] = float(e["stats"]["sales"]) + p
					have[c] = int(have.get(c, 0)) + 1
					short[wanted] = int(short[wanted]) - 1
					if int(short[wanted]) <= 0:
						short.erase(wanted)
					led("bought")
					continue
				cant_pay += p
				cant_n += 1
			i += 1
		purchase_usec = Time.get_ticks_usec() - phase_started
		if bought > 0 and game != null:
			phase_started = Time.get_ticks_usec()
			# Purchases invalidate every earlier miss; start an independent pass.
			rekit_units(game, town, mil, false, {}, true)   # the new pieces to the men who lack them
			# Issuing the purchased gear changes held stock and native wages,
			# not the supported people's troop-template requirements.
			have = class_counts(arm)
			short = _short(tgt, have)
			purchased_issue_usec = Time.get_ticks_usec() - phase_started
	Perf.record_us("Equipment market purchases", purchase_usec)
	Perf.record_us("Equipment purchased issue", purchased_issue_usec)
	phase_started = Time.get_ticks_usec()
	e["arms_tgt"] = tgt
	e["arms_short"] = short
	_arms_note(game, town, e, short, cant_pay, cant_n)
	# Retain unmatched physical surplus. The ten-day own-faction pass gets it;
	# ordinary commercial trade still uses the market's goods and smith output.
	var sd: Dictionary = e.get("arms_sd", {})
	for c in sd.keys():
		if not short.has(c):
			sd.erase(c)
	for c in short:
		sd[c] = int(sd.get(c, 0)) + ARMORY_EVERY
	e["arms_sd"] = sd
	e["arms_short"] = short
	e["arms_have"] = have
	Perf.record_us("Equipment cost notes", Time.get_ticks_usec() - phase_started)

## Pieces short of target by class; foreign or other makes for the same role count against the shortfall (Douglas:
## looted orc axes arm a sword hand).
static func _short(tgt: Dictionary, have: Dictionary) -> Dictionary:
	var short := {}
	for c in tgt:
		var s := int(tgt[c]) - int(have.get(c, 0))
		if s > 0:
			short[c] = s
	var spare_role := {}
	for c in have:
		var x := int(have[c]) - int(tgt.get(c, 0))
		if x > 0:
			spare_role[cls_role(c)] = int(spare_role.get(cls_role(c), 0)) + x
	var short_classes: Array = short.keys(); short_classes.sort()
	for c in short_classes:
		var cov := mini(int(short[c]), int(spare_role.get(cls_role(c), 0)))
		if cov > 0:
			short[c] = int(short[c]) - cov
			spare_role[cls_role(c)] = int(spare_role[cls_role(c)]) - cov
			if int(short[c]) <= 0:
				short.erase(c)
	return short

## An offered foreign or different melee make can satisfy the same role.
static func shortage_class(short: Dictionary, offered: String) -> String:
	if offered == "": return ""
	if int(short.get(offered, 0)) > 0: return offered
	var classes: Array = short.keys(); classes.sort()
	for c in classes:
		if int(short[c]) > 0 and cls_role(String(c)) == cls_role(offered): return String(c)
	return ""

## What the head holds back from the arms bill: the treasury's whole short line, plus the militia's wages until
## the next look. Army.pay_town still pays above its own quarter of that line.
static func arms_reserve(game, town: Dictionary, e: Dictionary) -> float:
	var r := float(Barge.treasury_lines(e)["short"])
	if game != null:
		r += Army.town_bill(game, town) * float(ARMORY_EVERY)
	return r

## Coin the treasury paid for arms (diagnostic column; not a second balance).
static func note_arms_spend(e: Dictionary, paid: float) -> void:
	if paid <= 0.0 or not e.get("stats") is Dictionary:
		return
	e["stats"]["arms_spend"] = float(e["stats"].get("arms_spend", 0.0)) + paid

const LOG_MAX := 8
## The town's armory log (e.arms_log, the newest LOG_MAX lines; the town screen shows it under the armory): why its
## men go short. A reason is written again only when it changes or after a month.
static func log_line(e: Dictionary, key: String, text: String) -> void:
	var day := int(e.get("day", 0))
	if String(e.get("arms_lk", "")) == key and day - int(e.get("arms_ld", -999)) < 30:
		return
	e["arms_lk"] = key
	e["arms_ld"] = day
	if not e.has("arms_log"):
		e["arms_log"] = []
	var lg: Array = e["arms_log"]
	lg.append("Day %d: %s" % [day + 1, text])
	while lg.size() > LOG_MAX:
		lg.pop_front()

static func _words(short: Dictionary) -> String:
	var ks: Array = short.keys()
	ks.sort()
	var ws := []
	for c in ks:
		ws.append("%d %s" % [int(short[c]), cls_word(c)])
	return ", ".join(PackedStringArray(ws))

## After the head's look: what the armory still lacks, why, and what it would cost (e.arms_due, which the month's
## budget raises taxes for: Barge.treasury_month). cant_pay / cant_n: the stall pieces he could not pay for.
static func _arms_note(game, town: Dictionary, e: Dictionary, short: Dictionary, cant_pay: float, cant_n: int) -> void:
	var n := 0
	for c in short:
		n += int(short[c])
	if n <= 0:
		e["arms_due"] = 0.0
		if String(e.get("arms_lk", "")) != "" and String(e.get("arms_lk", "")) != "ok":
			log_line(e, "ok", "The armory is full again.")
		return
	var ref := cant_pay / float(cant_n) if cant_n > 0 else 0.0
	if ref <= 0.0:
		var vs := 0.0; var k := 0
		var values := {}
		for it in armory(town):
			vs += _note_value(town, it, values); k += 1
		ref = vs / float(k) if k > 0 else 0.0
	e["arms_due"] = ref * float(n)
	var gaps := 0
	if game != null:
		for c in gaps_of(TownDefence.garrison(game, String(town["id"]))).values():
			gaps += int(c)
	var men := (" %d pieces missing on the militia." % gaps) if gaps > 0 else ""
	if cant_n > 0:
		log_line(e, "money", "The armory is short of %s; the treasury (%d coins, %d held back for the garrison's pay) cannot pay for them.%s" % [
			_words(short), int(e["treasury"]), int(arms_reserve(game, town, e)), men])
	else:
		var smiths := []   # why the smiths are not making them
		for b in e["biz"]:
			var kind := "weapon" if b["type"] == "weaponsmith" else ("armor" if b["type"] == "armorsmith" else "")
			if kind == "" or b.get("closed", false) or not has_orders(e, kind):
				continue
			var who := "the weaponsmith" if kind == "weapon" else "the armourer"
			if int(b["workers"]) + int(b.get("kw", 0)) <= 0:
				smiths.append("%s has nobody working" % who)
			elif String(b.get("state", "")) in ["inputs", "wages"]:
				smiths.append("%s is short of %s" % [who, String(b.get("why", "")) if String(b.get("why", "")) != "" else "money"])
		var why := ("; " + ", ".join(PackedStringArray(smiths))) if not smiths.is_empty() else ", the smiths are asked for them"
		log_line(e, "none", "The armory is short of %s; there are none on the stalls%s.%s" % [_words(short), why, men])

## Only this unchanged-town note read may reuse prices. Purchase loops shrink
## stalls (including bow scarcity), so their native prices are always fresh.
static func _note_value(town: Dictionary, it: Item, values: Dictionary) -> float:
	# These are every per-item input used by Item.value/Economy.base_value.
	# Array keys retain exact float/quality/gem boundaries without formatting.
	var gem := String(it.legend.get("gem", "")) if it.is_legend() else ""
	var key: Array = [it.tid, it.material, it.quality, it.vr, gem]
	if not values.has(key): values[key] = Economy.base_value(town, it)
	return float(values[key])

## Smiths' pick (Businesses._arms): ORDER_SHARE of the time a template of a class the armory is short of.
static func pick_tid(e: Dictionary, pool: Array, rng: RandomNumberGenerator) -> String:
	var short: Dictionary = e.get("arms_short", {})
	if not short.is_empty() and rng.randf() < ORDER_SHARE:
		var cands := []
		var tot := 0.0
		for tid in pool:
			var c := cls(String(tid))
			if short.has(c):
				cands.append([tid, float(short[c])])
				tot += float(short[c])
		if not cands.is_empty():
			var r := rng.randf() * tot
			for x in cands:
				r -= float(x[1])
				if r <= 0.0:
					return x[0]
			return cands[-1][0]
	return pool[rng.randi() % pool.size()]

## v0.014: the head's ORDERS to his smiths. The armory's shortfall is an order book: a smith whose market stalls are
## full (Businesses._arms "market full") still works the pieces his armory is short of, and the head buys each one
## straight off the smith at the market's buying price (TownEcon market.arms_buy_share), the treasury paying, above
## arms_reserve. Before, a full market stopped the smiths outright: stalls packed with pieces the armory did not
## want, the smiths idle, their hands gone, and the armory and the militia short for years.
static func _kind_makes(kind: String, c: String) -> bool:
	if kind == "weapon":
		return c.begins_with("w_") and c != "w_bow"
	if kind == "armor":
		return c.begins_with("a_")
	return false

static func has_orders(e: Dictionary, kind: String) -> bool:
	for c in e.get("arms_short", {}):
		if _kind_makes(kind, c):
			return true
	return false

## The templates of the pool the armory has orders for.
static func order_pool(e: Dictionary, pool: Array) -> Array:
	var short: Dictionary = e.get("arms_short", {})
	return pool.filter(func(tid): return short.has(cls(String(tid))))

## The head buys a new piece off his smith for his armory when it fills an order and the treasury can pay p above
## its reserve. Returns true when he took it (p paid into the smith's till by the caller's books: the treasury's side
## is done here).
static func order_buy(game, town: Dictionary, e: Dictionary, it: Item, p: float, forge_pass: Variant = null) -> bool:
	if game != null:
		if forge_pass == null:
			refresh_equipment(game, town)
		else:
			_refresh_forge_order(game, town, forge_pass)
	var short: Dictionary = e.get("arms_short", {})
	var c := cls(it.tid)
	var wanted := shortage_class(short, c)
	if wanted == "":
		return false
	var reserve := 0.0
	if game != null and forge_pass != null:
		if not forge_pass.has("reserve"): forge_pass["reserve"] = arms_reserve(game, town, e)
		reserve = float(forge_pass["reserve"])
	else:
		reserve = arms_reserve(game, town, e)
	if float(e["treasury"]) - p < reserve:
		return false
	e["treasury"] = float(e["treasury"]) - p
	note_arms_spend(e, p)
	armory(town).append(it)
	if game != null and forge_pass != null:
		var have: Dictionary = forge_pass["have"]
		have[c] = int(have.get(c, 0)) + 1
	short[wanted] = int(short[wanted]) - 1
	if int(short[wanted]) <= 0:
		short.erase(wanted)
	led("ordered")
	return true

## A caller-owned context for ONE synchronous forge's item loop only. Its
## supported loadouts, ranks and issued weapons cannot change in that loop.
## Build lazily at the first native order attempt: earlier template/quality
## rolls still see exactly the old shortfall. Stored items only append here.
static func _refresh_forge_order(game, town: Dictionary, forge_pass: Dictionary) -> void:
	var e: Dictionary = town["econ"]
	if not forge_pass.has("target"):
		refresh_equipment(game, town)
		forge_pass["target"] = (e["arms_tgt"] as Dictionary).duplicate()
		forge_pass["have"] = (e["arms_have"] as Dictionary).duplicate()
		return
	e["arms_tgt"] = (forge_pass["target"] as Dictionary).duplicate()
	# Publish the pre-purchase count just like refresh_equipment did. Keep the
	# increment private to the next item; the final item's saved stats match.
	e["arms_have"] = (forge_pass["have"] as Dictionary).duplicate()
	e["arms_short"] = _short(e["arms_tgt"], e["arms_have"])

static func short_of(town: Dictionary, c: String) -> int:
	return int(town.get("econ", {}).get("arms_short", {}).get(c, 0))

# ================================================================== re-kit
## Takes a piece for `slot` out of the armory: the template wanted, else one of the same class for that slot.
## opt: only from stock above the target. Returns null when there is none.
## A supplied stock dictionary belongs to one shrinking rekit pass only.
static func _fit_index(arm: Array, stock: Dictionary) -> Dictionary:
	if stock.has("fit_index"): return stock["fit_index"]
	var index := {"template": {}, "class_slot": {}, "role_slot": {}, "order": {}, "live": {}, "cursor": {}}
	var counts := {}
	var templates := {}
	var kinds: Array = ["template", "class_slot", "role_slot"]
	for i in arm.size():
		var it: Item = arm[i]
		if not templates.has(it.tid):
			var template_class := cls(it.tid)
			var slot := it.slot()
			templates[it.tid] = {"template": it.tid, "class_slot": template_class + "|" + slot,
				"role_slot": role(it.tid) + "|" + slot, "class": template_class}
		var keys: Dictionary = templates[it.tid]
		for kind in kinds:
			var key: String = keys[kind]
			if not index[kind].has(key): index[kind][key] = []
			index[kind][key].append(it)
		index["order"][it] = i
		index["live"][it] = true
		var item_class: String = keys["class"]
		counts[item_class] = int(counts.get(item_class, 0)) + 1
	stock["counts"] = counts
	stock["fit_index"] = index
	return index

## Each bucket retains original armory order. Removed Items are skipped lazily;
## no classification or full GDScript armory walk repeats for another recipient.
static func _fit_first(index: Dictionary, kind: String, key: String) -> Item:
	var bucket: Array = index[kind].get(key, [])
	var cursor_key := kind + "|" + key
	var i := int(index["cursor"].get(cursor_key, 0))
	while i < bucket.size() and not index["live"].has(bucket[i]): i += 1
	index["cursor"][cursor_key] = i
	return bucket[i] if i < bucket.size() else null

static func _take_indexed(town: Dictionary, arm: Array, tids: Array, slot: String, opt: bool, stock: Dictionary) -> Item:
	var index := _fit_index(arm, stock)
	var c := cls(String(tids[0]))
	if opt and int(stock["counts"].get(c, 0)) <= int(town.get("econ", {}).get("arms_tgt", {}).get(c, 0)): return null
	var got: Item = null
	# Template-array order is not a preference: the earliest exact Item in the
	# original armory wins, even when an earlier class/role substitute exists.
	for tid in tids:
		var candidate := _fit_first(index, "template", str(tid))
		if candidate != null and (got == null or int(index["order"][candidate]) < int(index["order"][got])): got = candidate
	if got == null: got = _fit_first(index, "class_slot", c + "|" + slot)
	if got == null and not opt: got = _fit_first(index, "role_slot", role(String(tids[0])) + "|" + slot)
	if got == null: return null
	arm.erase(got)
	index["live"].erase(got)
	var taken_class := cls(got.tid)
	stock["counts"][taken_class] = int(stock["counts"].get(taken_class, 0)) - 1
	if TownEcon.has_econ(town): TownEcon.led(town["econ"], "used", "arms", 1)
	return got

static func _take_fit(town: Dictionary, tids: Array, slot: String, opt: bool, stock = null) -> Item:
	var arm := armory(town)
	if arm.is_empty():
		return null
	if stock != null: return _take_indexed(town, arm, tids, slot, opt, stock)
	var c := cls(String(tids[0]))
	if opt:
		var target := int(town.get("econ", {}).get("arms_tgt", {}).get(c, 0))
		var have := 0
		for it in arm:
			if cls(it.tid) == c:
				have += 1
				if have > target:
					break
		if have <= target:
			return null
	var pick := -1
	var alt := -1
	var r := role(String(tids[0]))
	for i in arm.size():
		var it: Item = arm[i]
		if tids.has(it.tid):
			pick = i
			break
		if pick < 0 and cls(it.tid) == c and it.slot() == slot:
			pick = i
		elif not opt and pick < 0 and alt < 0 and it.slot() == slot and role(it.tid) == r:
			alt = i
	if pick < 0 and not opt:
		pick = alt   # Douglas: own make short -> any piece for the same role (a looted orc axe for a sword arm)
	if pick < 0:
		return null
	var got: Item = arm[pick]
	arm.remove_at(pick)
	if TownEcon.has_econ(town):
		TownEcon.led(town["econ"], "used", "arms", 1)
	return got

## Arms the men's missing slots from the town's armory (use_shop: then from its stalls, the treasury paying).
## miss (world size): a cache of the slots of a loadout ("faction|title|slot") this town had nothing for in this pass,
## so the next man of the same troop does not search the armory and the stalls again (they only shrink in a pass).
## full (v0.014: the town's own men, militia and caravan guards): the optional slots too, from any stock (the target
## counts them: targets()); field bands fill an optional slot only from stock above the target.
static func rekit_units(_game, town: Dictionary, units: Array, use_shop: bool, miss = null, full: bool = false, stock = null) -> int:
	var n := 0
	var pass_stock: Dictionary = {} if stock == null else stock
	for u in units:
		if not _is_person(u):
			continue
		var lo := loadout_of(u)
		for slot in lo:
			if u.equip.has(slot):
				continue
			if slot == "off_hand" and u.weapon() != null and u.weapon().tmpl().get("two_handed", false):
				continue
			var mk := ""
			if miss != null:
				mk = u.faction + "|" + u.title + "|" + String(slot)
				if (miss as Dictionary).has(mk):
					continue
			var row: Dictionary = lo[slot]
			var opt := bool(row["opt"]) and not full
			var it := _take_fit(town, row["tids"], slot, opt, pass_stock)
			var none := it == null   # nothing in the armory, nor (below) on the stalls
			if it == null and use_shop and not opt and TownEcon.has_econ(town):
				var got := TownEcon.take_arms(town, 1, 0, "", String(row["tids"][0]))
				if got.is_empty():
					got = TownEcon.take_arms(town, 1, 0, slot)
				if not got.is_empty():
					none = false
					if (got[0] as Item).slot() == slot:
						it = got[0]
					else:
						(town["shop"] as Array).append(got[0])
			if none and miss != null:
				miss[mk] = true
			if it != null:
				u.equip[slot] = it
				n += 1
				led("rekit")
	return n

## Army.faction_day: every field band of the realm re-arms from its home town.
static func rekit_bands(game, fid: String) -> void:
	for tid in rekit_towns(game, fid):
		rekit_town(game, fid, tid)

## World size: the realm's re-arming a town at a time (Army.faction_day queues a work job per town). The home towns
## of its field bands, in the order of their first band on the map. Towns do not share armories, stalls or treasuries,
## so a town at a time (its bands in map order) re-arms every man exactly as the one pass over all bands did.
static func rekit_towns(game, fid: String) -> Array:
	var w: Dictionary = game.world
	var out := []
	var seen := {}
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] != fid or not Army.is_field(wb):
			continue
		var tid := String(wb.get("home", ""))
		var town: Dictionary = w["towns"].get(tid, {})
		if not seen.has(tid) and TownEcon.has_econ(town) and town["faction"] == fid:
			seen[tid] = true
			out.append(tid)
	return out

static func rekit_town(game, fid: String, tid: String) -> void:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"].get(tid, {})
	if not TownEcon.has_econ(town) or town["faction"] != fid:
		return
	var miss := {}   # one town's armory and stalls only shrink here: a piece not found stays not found
	var stock := {}  # live class counts shared only by this town's shrinking re-kit pass
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if wb["faction"] == fid and String(wb.get("home", "")) == tid and Army.is_field(wb):
			rekit_units(game, town, wb["units"], true, miss, false, stock)

## TownEcon.outfit_units: a piece of this template (or class, same slot) from the armory for a new man.
static func take_for(town: Dictionary, tid: String, slot: String) -> Item:
	if cls(tid) == "":
		return null
	return _take_fit(town, [tid], slot, false)

# ================================================================== gear of the dead
## holder: {"band": warband} | {"town": town} | {} (nobody holds the field). Every piece of the fallen is looted,
## scrapped or left; their quivers go with the looters. The men's equip is emptied.
## Douglas: AI winners loot with the SAME chance as the player: the fallen go through Loot.spoils (weighted by real
## condition and quality; coin on the bodies by the 5% / 10% last-of-house / 500 rules). Kept pieces go to the winners
## (to_holder) in that condition; the rest is scrap entering the nearest town's stock, whose market pays its scrap gold.
## Scrap gold + the fallen's coin: half into the victorious soldiers' pay (by their rank wages, into their families'
## purses), half into the winning realm's coffer (share_spoils). Nobody holding the field: everything is left.
static func field(game, dead: Array, holder: Dictionary, pos: Vector2) -> Dictionary:
	var out := {"kept": 0, "scrapped": 0, "lost": 0, "coin": 0, "gold": 0.0}
	var people := dead.filter(func(u): return u is Unit and not u.race_def().get("creature", false))
	if people.is_empty():
		return out
	var w: Dictionary = game.world
	if holder.is_empty():
		for u in people:
			for s in u.equip.keys():   # v0.014: beasts take no legendary piece: the nearest town's people pick it up
				var lit: Item = u.equip[s]
				if lit.is_legend():
					u.equip.erase(s)
					_legend_found(game, lit, u, pos)
			out["lost"] = int(out["lost"]) + u.equip.size()
			led("lost", u.equip.size())
			u.equip.clear()
			u.quiver.clear()
		return out
	var custody: Dictionary = _salvage_custody(game, holder)
	if custody.is_empty():
		out["reason"] = "No actual victorious custody destination; field gear and carried cash remain untouched."
		return out
	var seed := hash([int(w.get("seed", 0)), int(float(game.day) * 1000.0), int(pos.x), int(pos.y), people.size(), "arms-field"])
	var harvest_started := Time.get_ticks_usec()
	var sp := Loot.spoils(people, [], seed, Game.LOOT_FRACTION, holder_name(holder))   # Douglas: the same function and odds as the player
	Perf.record_us("AI loot harvest", Time.get_ticks_usec() - harvest_started)
	last_spoils = sp
	for it in sp["items"]:
		led("looted")
		to_holder(game, holder, it)
	out["kept"] = (sp["items"] as Array).size()
	out["offered_scrap"] = int(sp["scrapped"])
	out["coin"] = int(sp["coin"])
	var town := _holder_town(game, holder)
	if TownEcon.has_econ(town):
		var arm: Dictionary = town["econ"].get("armory", {})
		for k in sp["arrows"]:
			arm[k] = int(arm.get(k, 0)) + int(sp["arrows"][k])
		town["econ"]["armory"] = arm
	var receipt: Dictionary = Salvage.trade(game, sp["salvage"], pos, custody["items"], holder_name(holder), "soldier_purses_and_coffer", str(custody["destination"]))
	receipt["transaction"] = "ai_field_salvage"; receipt["custody_town_id"] = custody.get("town_id", "")
	receipt["custody_camp_id"] = custody.get("camp_id", "")
	out["salvage_receipt"] = receipt
	var converted := 0; var surviving := 0
	for row in receipt["rows"]:
		if row["destination"] == "market_stock" and int(row["paid"]) > 0: converted += 1
		else: surviving += 1
		if row["retained"] and custody.has("town_id"):
			TownEcon.led(w["towns"][custody["town_id"]]["econ"], "made", "arms", 1)
	led("scrapped", converted); led("looted", surviving)
	led("home", int(receipt["retained_items"]))
	out["scrapped"] = converted; out["kept"] = int(out["kept"]) + surviving
	var paid := float(receipt["paid"])
	out["gold"] = paid
	TownEcon.gold_out(-float(sp["coin"]) - paid)   # market payment is credited to native inside recipients by share_spoils
	share_spoils(game, holder, paid + float(sp["coin"]))
	return out

## Unpaid exact Items need real uncapped ownership before the field is harvested.
## This bypasses to_holder's autoequipping and outlaw overflow-loss policy.
static func _salvage_custody(game, holder: Dictionary) -> Dictionary:
	var home: Dictionary = _holder_town(game, holder)
	if TownEcon.has_econ(home): return {"items": armory(home), "destination": "town_armory", "town_id": str(home["id"])}
	var band: Dictionary = holder.get("band", {})
	var lid := str(band.get("home", "")); var camp: Dictionary = Bandits.camp(game, lid)
	if not camp.is_empty() and band.get("faction", "") == "outlaws" and camp.has("stock"):
		return {"items": camp["stock"], "destination": "outlaw_hoard", "camp_id": lid}
	return {}

## The last Loot.spoils result an AI field used (tests: the AI goes through the player's loot function).
static var last_spoils: Dictionary = {}

## Ledger of AI spoils gold (tests): soldiers' half and coffer half.
static var spoils_gold: Dictionary = {"soldiers": 0.0, "coffer": 0.0}

## Half the spoils gold into the victors' pay (split by their rank wages, into their families' purses), half into
## the winning realm's coffer. Outlaws: the coffer half goes to their camp. No coffer: all to the men; no men with a
## family: all to the coffer. Gold already counted inside the ledgers (callers book coin back in).
static func share_spoils(game, holder: Dictionary, pot: float) -> void:
	if pot <= 0.0:
		return
	var w: Dictionary = game.world
	var men := []
	var fid := ""
	var hb: Dictionary = holder.get("band", {})
	var tier := "army"
	if not hb.is_empty():
		fid = String(hb["faction"])
		men = hb["units"]
		if String(hb.get("kind", "")) == "militia":
			tier = Army.town_tier(w["towns"].get(String(hb.get("home", "")), {"size": 0}))
		elif String(hb.get("kind", "")) in ["bandit", "camp"]:
			tier = "bandit"
	elif holder.has("town"):
		fid = String(holder["town"]["faction"])
		men = Militia.units_of(game, String(holder["town"]["id"]))
		tier = Army.town_tier(holder["town"])
	var paid_to := []
	var wsum := 0.0
	var lo := Army.low_officer(men, tier)
	for u in men:
		if not _is_person(u):
			continue
		var f := People.fam_of(w["towns"].get(u.home_town, {}), u.family)
		if f.is_empty() or f.get("gone", false):
			continue
		var wg := Army.wage(tier, u.rank, lo)
		paid_to.append([f, wg])
		wsum += wg
	var coffer: Dictionary = w.get("factions", {}).get(fid, {})
	var camp: Dictionary = w.get("lairs", {}).get(String(hb.get("home", "")), {}) if not hb.is_empty() else {}
	var men_half := pot * 0.5 if not paid_to.is_empty() else 0.0
	if coffer.is_empty() and camp.is_empty():
		men_half = pot if not paid_to.is_empty() else 0.0
	for p in paid_to:
		var f: Dictionary = p[0]
		f["purse"] = float(f["purse"]) + men_half * float(p[1]) / maxf(0.0001, wsum)
	var rest := pot - men_half
	if rest > 0.0:
		if not camp.is_empty():
			camp["gold"] = float(camp.get("gold", 0.0)) + rest
			TownEcon.gold_out(rest)   # the camp sits outside the town ledgers
		elif not coffer.is_empty():
			coffer["treasury"] = float(coffer.get("treasury", 0.0)) + rest
		else:
			TownEcon.gold_out(rest)   # nobody to hold it (should not happen): lost on the field
			Barge.drained(w, rest)
	spoils_gold["soldiers"] = float(spoils_gold["soldiers"]) + men_half
	spoils_gold["coffer"] = float(spoils_gold["coffer"]) + rest

static func _holder_town(game, holder: Dictionary) -> Dictionary:
	var w: Dictionary = game.world
	if holder.has("town"):
		return holder["town"]
	var hb: Dictionary = holder.get("band", {})
	if hb.is_empty():
		return {}
	var t: Dictionary = w.get("towns", {}).get(String(hb.get("home", "")), {})
	if not t.is_empty() and t["faction"] == hb["faction"]:
		return t
	return {}

## v0.014: who holds the field, in words (a legendary piece's history).
static func holder_name(holder: Dictionary) -> String:
	var hb: Dictionary = holder.get("band", {})
	if not hb.is_empty():
		var k := String(hb.get("kind", "band"))
		return "%s %s" % [CampaignWorld.faction_the(String(hb.get("faction", ""))), {"bandit": "outlaws", "camp": "outlaws",
			"militia": "militia", "caravan": "caravan guards"}.get(k, "band")]
	if holder.has("town"):
		return "the militia of %s" % String(holder["town"].get("name", "?"))
	return ""

## v0.014: a legendary piece left on a field nobody held (beasts won): the nearest town's people find it.
static func _legend_found(game, it: Item, u: Unit, pos: Vector2) -> void:
	var w: Dictionary = game.world
	var town: Dictionary = w.get("towns", {}).get(CampaignWorld.nearest_town(w, pos), {})
	if u != null:
		Legends.fell(it, u, "the beasts")
	if TownEcon.has_econ(town):
		if cls(it.tid) == "": (town["shop"] as Array).append(it)
		else: armory(town).append(it)
		TownEcon.led(town["econ"], "made", "arms", 1)
		Legends.note(it, float(game.day), "Found on the field and taken to the armory of %s." % String(town.get("name", "?")))
		led("home")
	else:
		game.stash.append(it)   # no town at all (a test world): the company's people find it [never happens in play]
		Legends.note(it, float(game.day), "Found on the field by your company.")

## A looted piece: one of the winners missing that slot puts it on; else it goes home with the band's baggage (the
## home town's armory; outlaws: their camp's hoard); else it is left.
## v0.014: a legendary piece goes on the winners' best fitting fighter (Legends.give, the same code for every AI
## force); what he wore goes this normal way. Nobody to carry it: the armory or hoard (no cap), never left.
static func to_holder(game, holder: Dictionary, it: Item) -> void:
	var w: Dictionary = game.world
	var hb: Dictionary = holder.get("band", {})
	if it.is_legend():
		var men: Array = hb.get("units", []) if not hb.is_empty() else (Militia.units_of(game, String(holder["town"]["id"])) if holder.has("town") else [])
		var r := Legends.give(men, it)
		if bool(r[0]):
			led("rekit")
			for o in [r[1], r[2]]:
				if o != null:
					to_holder(game, holder, o)
			return
		var l0: Dictionary = w.get("lairs", {}).get(String(hb.get("home", "")), {}) if not hb.is_empty() else {}
		if not l0.is_empty() and l0.has("stock"):
			(l0["stock"] as Array).append(it)
			Legends.note(it, float(game.day), "Carried to an outlaw hoard.")
			led("home")
			return
		var t0 := _holder_town(game, holder)
		if not TownEcon.has_econ(t0):
			t0 = w.get("towns", {}).get(String(hb.get("home", "")), {})
		if TownEcon.has_econ(t0):
			armory(t0).append(it)
			TownEcon.led(t0["econ"], "made", "arms", 1)
			Legends.note(it, float(game.day), "Carried to the armory of %s." % String(t0.get("name", "?")))
			led("home")
			return
		_legend_found(game, it, null, hb.get("pos", Vector2.ZERO))
		return
	if not hb.is_empty():
		var slot := it.slot()
		for u in hb["units"]:
			if not _is_person(u) or u.equip.has(slot):
				continue
			if not loadout_of(u).has(slot):
				continue
			if slot == "off_hand" and u.weapon() != null and u.weapon().tmpl().get("two_handed", false):
				continue
			u.equip[slot] = it
			led("rekit")
			return
		var l: Dictionary = w.get("lairs", {}).get(String(hb.get("home", "")), {})
		if not l.is_empty() and l.has("stock"):
			if (l["stock"] as Array).size() < Bandits.STOCK_MAX:
				(l["stock"] as Array).append(it)
				led("home")
				return
			led("lost")
			return
	var town := _holder_town(game, holder)
	if TownEcon.has_econ(town):
		armory(town).append(it)
		TownEcon.led(town["econ"], "made", "arms", 1)   # an inflow from the field into the town's holdings
		led("home")
		return
	led("lost")

## A man walks home alive (fled, deserted, scattered): his kit goes into his home town's armory. A man of another
## realm (outlaw, deserter of a foreign band) hands it in for coin: the head pays his family FENCE_SHARE of its value;
## a head who cannot pay does not take it (left by the road).
static func kit_home(game, u: Unit) -> void:
	if u == null or u.equip.is_empty() or u.race_def().get("creature", false):
		return
	var w: Dictionary = game.world
	var town: Dictionary = w.get("towns", {}).get(u.home_town, {})
	if not TownEcon.has_econ(town):
		for s in u.equip:
			if (u.equip[s] as Item).is_legend():   # v0.014: never lost
				_legend_found(game, u.equip[s], null, town.get("pos", Vector2.ZERO))
				continue
			led("fled_lost")
		u.equip.clear()
		return
	var e: Dictionary = town["econ"]
	var own: bool = town["faction"] == u.faction
	var f := People.fam_of(town, u.family)
	for slot in u.equip.keys():
		var it: Item = u.equip[slot]
		u.equip.erase(slot)
		if it.is_legend():   # v0.014: never left by the road: into his home town's armory, fee or no fee
			armory(town).append(it)
			TownEcon.led(e, "made", "arms", 1)
			Legends.note(it, float(game.day), "Handed in at the armory of %s by %s." % [String(town.get("name", "?")), u.name])
			led("fled")
			continue
		if cls(it.tid) == "":
			(town["shop"] as Array).append(it)
			TownEcon.led(e, "made", "arms", 1)
			led("fled")
			continue
		if not own:
			var p := Economy.base_value(town, it) * FENCE_SHARE
			if f.is_empty() or float(e["treasury"]) < p:
				led("fled_lost")
				continue
			e["treasury"] = float(e["treasury"]) - p
			f["purse"] = float(f["purse"]) + p
			led("fenced")
		else:
			led("fled")
		armory(town).append(it)
		TownEcon.led(e, "made", "arms", 1)

## v0.014 (Douglas 23:02: "some caravans get naked people guarding them"): a caravan's guards are kitted before it
## leaves (Caravans.sail, after the crew signs on), from the town's ARMORY first like its militia (every armory slot
## of their loadout, the optional ones too; the armory's target holds a caravan's guard kit), then off the stalls with
## the treasury paying. Before, they bought only off the stalls (a quarter of the stall stock for the whole caravan,
## the treasury paying full price and the market buying it back at 70% when they came home), so a town with a full
## armory and an empty chest sent its guards out naked. What they still lack, and why, goes in the town's armory log.
## Returns the armory slots left empty.
static func kit_guards(game, town: Dictionary, wb: Dictionary) -> int:
	var units: Array = wb["units"]
	TownEcon.outfit_units(town, units, 0.5, true)   # the rolled kit never existed: the armory's pieces, then the stalls
	rekit_units(game, town, units, true, null, true)   # the empty armory slots (optional ones too)
	wb["outfitted"] = true   # arms trade: their kit is real now (it comes home with them)
	var gaps := gaps_of(units)
	var n := 0
	for c in gaps:
		n += int(gaps[c])
	if n > 0 and TownEcon.has_econ(town):
		var e: Dictionary = town["econ"]
		var stall := false
		for it in town.get("shop", []):
			if gaps.has(cls(it.tid)):
				stall = true
				break
		if stall:
			log_line(e, "guards_money", "A caravan's %d guards left without %s: the armory had none and the treasury (%d coins) could not buy them off the stalls." % [
				units.size(), _words(gaps), int(e["treasury"])])
		else:
			log_line(e, "guards_none", "A caravan's %d guards left without %s: none in the armory nor on the stalls." % [units.size(), _words(gaps)])
	return n

## Caravan guards home (or fled from a raid): their kit back. v0.014: armory pieces go back into the armory they came
## from (the town's own, no gold moves); clothing and the like back on the stalls, the market buying them back.
static func guards_home(game, wb: Dictionary) -> void:
	if not wb.get("outfitted", false):
		return   # never outfitted from stock: the rolled kit never existed
	var town: Dictionary = game.world.get("towns", {}).get(String(wb.get("origin", "")), {})
	for u in wb.get("units", []):
		if not u is Unit or u.dead or u.equip.is_empty():
			continue
		if TownEcon.has_econ(town):
			# back on the stalls they were bought from; the market buys them back for the treasury (what its till holds)
			var e: Dictionary = town["econ"]
			var mkt: Dictionary = e["biz"][int(e["mkt"])]
			var share := float(TownEcon.data()["market"]["arms_buy_share"])
			for s in u.equip:
				var it: Item = u.equip[s]
				if cls(it.tid) != "" and town["faction"] == u.faction:
					armory(town).append(it)
					TownEcon.led(e, "made", "arms", 1)   # back into the town's holdings
					led("guards")
					continue
				var p := minf(Economy.base_value(town, it) * share, maxf(0.0, float(mkt["till"])))
				mkt["till"] = float(mkt["till"]) - p
				e["treasury"] = float(e["treasury"]) + p
				(town["shop"] as Array).append(it)
				TownEcon.led(e, "made", "arms", 1)   # back into the market's count
				led("guards")
		else:
			for s in u.equip:
				led("guards_lost")
		u.equip.clear()

## An AI band plundered a caravan: the guards' kit by field(), and the winners carry Caravans.PLUNDER_SHARE of the
## cargo's arms home (the rest is lost with the wagons in Caravans.lost). Outlaws: Bandits.on_plunder took it all.
static func plunder_cargo(game, win: Dictionary, car: Dictionary) -> void:
	field(game, (car["units"] as Array).filter(func(u): return u is Unit and not u.dead), {"band": win}, car["pos"])
	var items: Array = car.get("cargo", {}).get("items", [])
	# v0.014: legendary pieces in the cargo always go to the winners (outlaws too; beasts: the nearest town finds them)
	for i in range(items.size() - 1, -1, -1):
		var lit: Item = items[i]
		if not lit.is_legend():
			continue
		items.remove_at(i)
		Legends.note(lit, float(game.day), "Taken from a plundered caravan by %s." % holder_name({"band": win}) if not Monsters.is_monster_band(win) else "Its caravan was overrun by beasts.")
		if Monsters.is_monster_band(win):
			_legend_found(game, lit, null, car["pos"])
		else:
			to_holder(game, {"band": win}, lit)
	if String(win.get("kind", "")) == "bandit" or Monsters.is_monster_band(win):
		return
	var keep := int(ceil(items.size() * Caravans.PLUNDER_SHARE))
	var town := _holder_town(game, {"band": win})
	if not TownEcon.has_econ(town):
		return
	for i in keep:
		var it: Item = items.pop_front()
		armory(town).append(it)
		led("cargo_looted")

## The company's battle is over (CampaignWorld.on_battle_result, before the dead are filtered out): the AI winner
## loots the company's fallen and its own; the guards of an escorted caravan and allied bands go to whoever holds it.
static func after_company_battle(game, result: Dictionary, wb: Dictionary, car: Dictionary, ally_ids: Array) -> void:
	var won := int(result.get("winner", -1)) == 0
	var w: Dictionary = game.world
	var pos: Vector2 = wb.get("pos", w["party"]["pos"])
	if not won:
		var dead := []
		for u in result.get("player_units", []):
			if u is Unit and u.dead:
				dead.append(u)
		for u in wb.get("units", []):
			if u is Unit and u.dead:
				dead.append(u)
		field(game, dead, {"band": wb} if not Monsters.is_monster_band(wb) else {}, pos)
	if not car.is_empty():
		var cd: Array = (car["units"] as Array).filter(func(u): return u is Unit and u.dead)
		field(game, cd, {"band": car} if won else ({"band": wb} if not Monsters.is_monster_band(wb) else {}), pos)
	for bid in ally_ids:
		var ab: Dictionary = w["warbands"].get(bid, {})
		if ab.is_empty():
			continue
		var ad: Array = (ab["units"] as Array).filter(func(u): return u is Unit and u.dead)
		field(game, ad, {"band": ab} if won else ({"band": wb} if not Monsters.is_monster_band(wb) else {}), pos)

# ================================================================== world gen / load
## Pre-history: every town's armory opens at its targets, made by its own smiths (marked); world-gen kit and the
## opening stalls of the town's own style get the town's marks.
static func init_world(game) -> void:
	var run := init_begin(game)
	while not init_part(game, run):
		pass

## Mark all original bands before seeding sorted towns, then outfit the company.
## Cache reset and all item allocation remain at their original stage boundaries.
static func init_begin(game) -> Dictionary:
	_cen_key = ""
	return {"phase": "bands", "i": 0, "ids": game.world.get("warbands", {}).keys()}

static func init_part(game, run: Dictionary) -> bool:
	var w: Dictionary = game.world
	var ids: Array = run["ids"]
	var i: int = run["i"]
	match String(run["phase"]):
		"bands":
			if i < ids.size():
				_init_mark_band(game, String(ids[i]))
				run["i"] = i + 1
			else:
				var tids: Array = w.get("towns", {}).keys()
				tids.sort()
				run["ids"] = tids
				run["phase"] = "towns"; run["i"] = 0
		"towns":
			if i < ids.size():
				_init_armory_town(game, String(ids[i]))
				run["i"] = i + 1
			else:
				run["phase"] = "finish"; run["i"] = 0
		"finish":
			_init_finish(game)
			return true
	return false

static func _init_mark_band(game, wid: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"][wid]
	var town: Dictionary = w["towns"].get(String(wb.get("home", "")), {})
	if town.is_empty():
		return
	for u in wb["units"]:
		if u is Unit:
			for s in u.equip:
				mark_old(u.equip[s], town)

static func _init_armory_town(game, tid: String) -> void:
	var w: Dictionary = game.world
	var t: Dictionary = w["towns"][tid]
	for it in t.get("shop", []):
		mark_old(it, t)
	seed_armory(game, t)

static func _init_finish(game) -> void:
	var w: Dictionary = game.world
	outfit_opening_kit(game)
	if not w.has("arms"):
		w["arms"] = new_state()

## v0.014: the company's opening kit was bought where it formed (the start town, by its stalls and armory): each
## metal piece takes that town's real metal mix (Factory.town_metal) and its maker's mark. Before, the kit was a
## fixed wealth roll made before the world existed (70% tin per piece), so most men began in all-tin kit beside a
## town whose smiths make mostly copper, and where tin bars cost more than copper ones. Own rng (world gen unchanged).
static func outfit_opening_kit(game) -> void:
	var w: Dictionary = game.world
	var town: Dictionary = w.get("towns", {}).get(String(w.get("start_town", "")), {})
	if town.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), "opening-kit"])
	for u in game.company:
		for s in DB.EQUIP_SLOTS:
			var it: Item = u.equip.get(s, null)
			if it == null or String(it.mat().get("kind", "")) != "metal":
				continue
			it.material = Factory.town_metal(rng, town, it.tid)
			mark_old(it, town)

static func new_state() -> Dictionary:
	return {"v": 2, "supply_day": -1, "supply_moved": 0, "next": 1, "c": {}, "offers": {}, "hist": [],
		"stats": {"signed": 0, "refused": 0, "batches": 0, "delivered": 0, "lost": 0, "done": 0, "broken": 0, "void": 0}}

static func seed_armory(game, town: Dictionary) -> void:
	if not TownEcon.has_econ(town) or town.has("armory_items"):
		return
	var arm := armory(town)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(town["id"]), "arms-armory"])
	var tgt := targets(game, town)
	var cul := String(town.get("culture", "middle"))
	var keys: Array = tgt.keys()
	keys.sort()
	for c in keys:
		var pool := []
		for kind in ["weapon", "armor", "bow"]:
			for tid in Businesses.gear_pool(cul, kind):
				if cls(String(tid)) == c:
					pool.append(tid)
		if pool.is_empty():
			continue
		for i in int(tgt[c]):
			var tid: String = pool[rng.randi() % pool.size()]
			var it: Item
			if DB.is_bow(tid):
				it = Item.make(tid, "wood", Factory.roll_quality(rng, 4.0))
				it.vr = Factory.roll_bow_variance(rng, 4.0)
			else:
				var mats: Array = ["copper", "tin"] if DB.is_weapon(tid) else DB.template(tid).get("materials", ["copper"])
				it = Item.make(tid, Factory.roll_material(rng, mats, int(town.get("wealth", 2))), Factory.roll_quality(rng, 4.0))
			mark_old(it, town)
			arm.append(it)
	town["econ"]["arms_tgt"] = tgt

static func after_load(game) -> void:
	var w: Dictionary = game.world
	if not w.has("towns"):
		return
	_cen_key = ""
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		if not t.has("armory_items"):
			seed_armory(game, t)   # older saves: the head's armory opens at its targets (their old kit stays unmarked)
		var e: Dictionary = t["econ"]
		for k in ["arms_tgt", "arms_have", "arms_short", "arms_sd"]:
			var d: Dictionary = e.get(k, {})
			for c in d:
				d[c] = int(d[c])
	if not w.has("arms"):
		w["arms"] = new_state()
	retire_contracts(game)
	for town in w["towns"].values():
		if TownEcon.has_econ(town): refresh_reserve(game, town)

# ================================================================== the market: caravans
## Pieces on the origin's stalls the destination's armory is short of (and the origin is not), up to n.
static func export_picks(origin: Dictionary, dest: Dictionary, n: int) -> Array:
	var ds: Dictionary = dest.get("econ", {}).get("arms_short", {})
	if ds.is_empty() or n <= 0:
		return []
	var os: Dictionary = origin.get("econ", {}).get("arms_short", {})
	var took := {}
	var out := []
	for it in origin.get("shop", []):
		if out.size() >= n:
			break
		var c := cls(it.tid)
		if c == "" or os.has(c) or int(took.get(c, 0)) >= int(ds.get(c, 0)):
			continue
		took[c] = int(took.get(c, 0)) + 1
		out.append(it)
	return out

## Caravans.buy_return: pieces here that the home armory is short of, bought with the caravan's purse.
static func import_buys(here: Dictionary, home: Dictionary, wb: Dictionary) -> void:
	if not TownEcon.has_econ(here):
		return
	var items: Array = wb["cargo"]["items"]
	var picks := export_picks(here, home, Caravans.MAX_ITEMS - items.size())
	var e: Dictionary = here["econ"]
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	for it in picks:
		var p := Economy.base_value(here, it) * 0.8
		if float(wb["gold"]) * 0.8 < p:
			continue
		(here["shop"] as Array).erase(it)
		items.append(it)
		wb["gold"] = float(wb["gold"]) - p
		mkt["till"] = float(mkt["till"]) + p
		e["stats"]["sales"] = float(e["stats"]["sales"]) + p

# ================================================================== scheduled internal supply
static func queue_day(w: Dictionary, d: int) -> void:
	var work: Array = w["work"]
	if d % SUPPLY_EVERY == 0: work.append(["arms_supply", d])
	var ids: Array = w["towns"].keys(); ids.sort()
	for tid in ids:
		if (d + absi(String(tid).hash())) % ARMORY_EVERY == 0 and TownEcon.has_econ(w["towns"][tid]):
			work.append(["arms_town", d, tid])

static func do_job(game, job: Array) -> bool:
	match String(job[0]):
		"arms_town":
			var t: Dictionary = game.world["towns"].get(String(job[2]), {})
			if TownEcon.has_econ(t): econ_daily(game, t, t["econ"], int(job[1]), false)
		"arms_supply":
			redistribute(game, int(job[1]))
		"arms_day", "arms_week", "arms_spawn":
			# Legacy metadata-only jobs are harmless. Stateful musters are converted
			# on load, before this dispatcher sees them.
			pass
		_: return false
	return true

## Greatest proportional shortage, with stable town-ID ties. Requirements and
## inventories are cached once per checkpoint and updated as real stock moves.
static func _supply_destination(w: Dictionary, rows: Dictionary, ids: Array, source_id: String, role_name: String) -> String:
	var source: Dictionary = w["towns"][source_id]
	var best := ""; var score := 0.0
	for tid in ids:
		if tid == source_id or not rows.has(tid): continue
		var town: Dictionary = w["towns"][tid]
		if String(source.get("faction", "")) == "" or town.get("faction", "") != source["faction"]: continue
		var row: Dictionary = rows[tid]
		var target := int(row["target"].get(role_name, 0))
		var shortage := target - int(row["have"].get(role_name, 0))
		if shortage <= 0: continue
		var ratio := float(shortage) / float(maxi(1, target))
		if ratio > score:
			best = String(tid); score = ratio
	return best

static func _supply_note(source: Dictionary, dest: Dictionary, role_name: String, n: int) -> void:
	if n <= 0: return
	var good := "arrows" if role_name == "arrows" else "arms"
	# Arrow commodity ledgers are updated by material/type at movement below.
	if good == "arms":
		TownEcon.led(source["econ"], "used", good, n)
		TownEcon.led(dest["econ"], "made", good, n)
	for pair in [[source, "out"], [dest, "in"]]:
		var stats: Dictionary = pair[0]["econ"]["stats"]
		var key := "military_supply_" + String(pair[1]) + ("_arrows" if good == "arrows" else "")
		stats[key] = int(stats.get(key, 0)) + n
	log_line(source["econ"], "supply_out_" + String(dest["id"]), "%d surplus %s transferred to our faction's garrison at %s." % [n, good, dest["name"]])
	log_line(dest["econ"], "supply_in_" + String(source["id"]), "%d %s received from our faction's armoury at %s." % [n, good, source["name"]])

## Candidate towns retain the original sorted-ID order. During this checkpoint only stock moves:
## targets and factions stay fixed, donors stop at target, and recipients never receive beyond it.
## Thus an initial role shortage may close, but no initially sufficient town can become deficient.
static func _supply_shortlists(w: Dictionary, rows: Dictionary, ids: Array) -> Dictionary:
	var by_faction := {}
	for tid in ids:
		if not rows.has(tid): continue
		var faction = w["towns"][tid].get("faction", "")
		if String(faction) == "": continue
		if not by_faction.has(faction): by_faction[faction] = {}
		var roles: Dictionary = by_faction[faction]
		var row: Dictionary = rows[tid]
		for r in row["target"]:
			if int(row["target"][r]) <= int(row["have"].get(r, 0)): continue
			if not roles.has(r): roles[r] = []
			(roles[r] as Array).append(tid)
	return by_faction

static func redistribute(game, checkpoint: int) -> int:
	var w: Dictionary = game.world
	var st: Dictionary = w.get("arms", {})
	if st.is_empty(): w["arms"] = new_state(); st = w["arms"]
	if checkpoint % SUPPLY_EVERY != 0 or checkpoint <= int(st.get("supply_day", -1)): return 0
	var ids: Array = w["towns"].keys(); ids.sort()
	var rows := {}; var moved := 0
	for tid in ids:
		var town: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(town): continue
		refresh_reserve(game, town)
		var have := role_counts(town["econ"]["arms_have"])
		var target := role_counts(town["econ"]["arms_tgt"])
		have["arrows"] = arrow_stock(town)
		target["arrows"] = int(town["econ"]["arrow_reserve"])
		rows[tid] = {"have": have, "target": target}
	var shortlists := _supply_shortlists(w, rows, ids)
	for source_id in ids:
		if not rows.has(source_id): continue
		var source: Dictionary = w["towns"][source_id]
		var candidates: Dictionary = shortlists.get(source.get("faction", ""), {})
		var row: Dictionary = rows[source_id]
		var arm := armory(source)
		var routes := {}
		for i in range(arm.size() - 1, -1, -1):
			var it: Item = arm[i]
			var c := cls(it.tid)
			if c == "": continue
			var r := cls_role(c)
			if int(row["have"].get(r, 0)) <= int(row["target"].get(r, 0)): continue
			var dest_id := _supply_destination(w, rows, candidates.get(r, []), String(source_id), r)
			if dest_id == "": continue
			var dest: Dictionary = w["towns"][dest_id]
			arm.remove_at(i); armory(dest).append(it)
			row["have"][r] = int(row["have"][r]) - 1
			rows[dest_id]["have"][r] = int(rows[dest_id]["have"].get(r, 0)) + 1
			routes[dest_id] = int(routes.get(dest_id, 0)) + 1
			Legends.note(it, float(game.day), "Transferred internally from %s to our faction's garrison at %s." % [source["name"], dest["name"]])
			moved += 1
		for dest_id in routes: _supply_note(source, w["towns"][dest_id], "arms", int(routes[dest_id]))
		# Arrow types remain real counted goods; distribute in type-preserving batches.
		var arrows: Dictionary = source["econ"].get("armory", {})
		var kinds: Array = DB.arrows.keys(); kinds.sort()
		for k in kinds:
			while int(arrows.get(k, 0)) > 0 and int(row["have"]["arrows"]) > int(row["target"]["arrows"]):
				var dest_id := _supply_destination(w, rows, candidates.get("arrows", []), String(source_id), "arrows")
				if dest_id == "": break
				var dest: Dictionary = w["towns"][dest_id]
				var dr: Dictionary = rows[dest_id]
				var n := mini(int(arrows[k]), mini(int(row["have"]["arrows"]) - int(row["target"]["arrows"]), int(dr["target"]["arrows"]) - int(dr["have"]["arrows"])))
				if not dest["econ"].has("armory"): dest["econ"]["armory"] = {}
				var da: Dictionary = dest["econ"]["armory"]
				arrows[k] = int(arrows[k]) - n; da[k] = int(da.get(k, 0)) + n
				row["have"]["arrows"] = int(row["have"]["arrows"]) - n; dr["have"]["arrows"] = int(dr["have"]["arrows"]) + n
				# Stored arrows already left the market/household commodity ledger
				# when bought. Reserve-to-reserve transfer is neither further use
				# nor production; record it in the physical supply movement book.
				for pair in [[source, "out"], [dest, "in"]]:
					var e: Dictionary = pair[0]["econ"]
					if not e.has("supply_ledger"): e["supply_ledger"] = {"in": {}, "out": {}}
					var book: Dictionary = e["supply_ledger"][pair[1]]
					book[k] = int(book.get(k, 0)) + n
				_supply_note(source, dest, "arrows", n); moved += n
	for tid in rows: refresh_reserve(game, w["towns"][tid])
	st["supply_day"] = checkpoint
	st["supply_moved"] = int(st.get("supply_moved", 0)) + moved
	return moved

# ================================================================== legacy contract retirement
static func special_job(c: Dictionary) -> bool:
	return c.has("arms_cid") or String(c.get("kind", "")) == "arms_raid"

static func _ordinary_caravan(wb: Dictionary, special_escort_ids: Dictionary) -> void:
	var was_special := wb.has("arms_contract")
	wb.erase("arms_contract")
	if was_special or special_escort_ids.has(String(wb.get("escort", ""))):
		wb["escort"] = ""; wb["away"] = 0.0
		if wb.get("state", "") == "waiting": wb["state"] = "travel"

## JSON Items/Units are reconstructed before this hook. Repeat loads restore no
## cargo twice. History/paid totals persist; no deposits exist in the old design.
static func retire_contracts(game) -> void:
	var w: Dictionary = game.world
	var st: Dictionary = w.get("arms", {})
	if st.is_empty(): w["arms"] = new_state(); st = w["arms"]
	var escort_ids := {}
	var contracts: Dictionary = st.get("c", {})
	for c in contracts.values():
		if String(c.get("escort_id", "")) != "": escort_ids[String(c["escort_id"])] = true
	if special_job(game.contract):
		escort_ids[String(game.contract.get("id", ""))] = true
		game.contract = {}   # neutral cancellation, no reward or diplomatic penalty
	for town in w["towns"].values():
		var offers: Array = town.get("contracts", [])
		for o in offers.duplicate():
			if special_job(o):
				escort_ids[String(o.get("id", ""))] = true
				offers.erase(o)
	for c in contracts.values():
		var seller: Dictionary = w["towns"].get(String(c.get("stown", "")), {})
		# A missing seller keeps staged items persistently in this historical entry.
		if TownEcon.has_econ(seller):
			for it in c.get("staged", []):
				armory(seller).append(it); TownEcon.led(seller["econ"], "made", "arms", 1)
			c["staged"] = []
		if String(c.get("state", "")) == "active": c["state"] = "retired"; c["ended"] = int(game.day)
		c["escort_id"] = ""; c["raids"] = []
		c.erase("mustering"); c.erase("spawn_q")
	for wb in w.get("warbands", {}).values(): _ordinary_caravan(wb, escort_ids)
	var jobs: Array = w.get("work", [])
	for i in range(jobs.size() - 1, -1, -1):
		var job: Array = jobs[i]
		if job.is_empty(): continue
		if String(job[0]) == "arms_spawn" and job.size() > 2 and job[-1] is Dictionary and job[-1].has("stage"):
			var m: Dictionary = job[-1]
			m["then"] = "caravan"; m.erase("cid"); m.erase("items")
			var wb: Dictionary = m.get("wb", m.get("extra", {}))
			if String(wb.get("escort", "")) != "": escort_ids[String(wb["escort"])] = true
			_ordinary_caravan(wb, escort_ids)
			jobs[i] = ["caravan", String(wb.get("origin", wb.get("home", ""))), String(wb.get("dest", "")), m]
		elif String(job[0]) in ["arms_spawn", "arms_day", "arms_week"]: jobs.remove_at(i)
	st["offers"] = {}; st["v"] = 2
	if not st.has("supply_day"): st["supply_day"] = int(game.day) - int(game.day) % SUPPLY_EVERY

# ------------------------------------------------------------------ views
## Lines for the town screen: the armory against its targets.
static func armory_lines(town: Dictionary) -> Array:
	var e: Dictionary = town.get("econ", {})
	var tgt: Dictionary = e.get("arms_tgt", {})
	var have := class_counts(armory(town))
	var keys := {}
	for c in tgt:
		keys[c] = true
	for c in have:
		keys[c] = true
	var ks: Array = keys.keys()
	ks.sort()
	var out := ["Stored reserve: 2.5 times supported troop equipment, beyond issued kit.", "Internal supply is checked every 10 days within our faction."]
	for c in ks:
		var h := int(have.get(c, 0)); var t := int(tgt.get(c, 0))
		var sd := int(e.get("arms_sd", {}).get(c, 0))
		out.append("%s: %d of %d%s" % [cls_word(c).capitalize(), h, t, (" (short %d days)" % sd) if h < t and sd > 0 else ""])
	return out

## v0.014: the town's armory log, newest last (log_line: why its militia and caravan guards go short).
static func armory_log(town: Dictionary) -> Array:
	return (town.get("econ", {}).get("arms_log", []) as Array).duplicate()
