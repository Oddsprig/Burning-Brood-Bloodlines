class_name ArmsSalvage
extends RefCounted
## Battlefield dead gear recovery, spoils sharing, soldier/guard kit return, caravan plunder,
## and 10-day internal faction supply redistribution split from ArmsTrade (game/campaign/arms_trade.gd)
## to keep each file focused and under the size threshold.
## Structure only; all ArmsTrade.* entry points delegate here with identical behavior.

const SUPPLY_EVERY := ArmsTrade.SUPPLY_EVERY
const ARMORY_EVERY := ArmsTrade.ARMORY_EVERY
const FENCE_SHARE := ArmsTrade.FENCE_SHARE

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
	# AI clashes remove fallen Units before Army.sweep can see their bodies.
	for u: Unit in people: Horses.return_mount(game, u)
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
			ArmsTrade.led("lost", u.equip.size())
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
	ArmsTrade.last_spoils = sp
	for it in sp["items"]:
		ArmsTrade.led("looted")
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
	ArmsTrade.led("scrapped", converted); ArmsTrade.led("looted", surviving)
	ArmsTrade.led("home", int(receipt["retained_items"]))
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
	if TownEcon.has_econ(home): return {"items": ArmsTrade.armory(home), "destination": "town_armory", "town_id": str(home["id"])}
	var band: Dictionary = holder.get("band", {})
	var lid := str(band.get("home", "")); var camp: Dictionary = Bandits.camp(game, lid)
	if not camp.is_empty() and band.get("faction", "") == "outlaws" and camp.has("stock"):
		return {"items": camp["stock"], "destination": "outlaw_hoard", "camp_id": lid}
	return {}

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
		if not ArmsTrade._is_person(u):
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
	ArmsTrade.spoils_gold["soldiers"] = float(ArmsTrade.spoils_gold["soldiers"]) + men_half
	ArmsTrade.spoils_gold["coffer"] = float(ArmsTrade.spoils_gold["coffer"]) + rest

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
		if ArmsTrade.cls(it.tid) == "": (town["shop"] as Array).append(it)
		else: ArmsTrade.armory(town).append(it)
		TownEcon.led(town["econ"], "made", "arms", 1)
		Legends.note(it, float(game.day), "Found on the field and taken to the armory of %s." % String(town.get("name", "?")))
		ArmsTrade.led("home")
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
			ArmsTrade.led("rekit")
			for o in [r[1], r[2]]:
				if o != null:
					to_holder(game, holder, o)
			return
		var l0: Dictionary = w.get("lairs", {}).get(String(hb.get("home", "")), {}) if not hb.is_empty() else {}
		if not l0.is_empty() and l0.has("stock"):
			(l0["stock"] as Array).append(it)
			Legends.note(it, float(game.day), "Carried to an outlaw hoard.")
			ArmsTrade.led("home")
			return
		var t0 := _holder_town(game, holder)
		if not TownEcon.has_econ(t0):
			t0 = w.get("towns", {}).get(String(hb.get("home", "")), {})
		if TownEcon.has_econ(t0):
			ArmsTrade.armory(t0).append(it)
			TownEcon.led(t0["econ"], "made", "arms", 1)
			Legends.note(it, float(game.day), "Carried to the armory of %s." % String(t0.get("name", "?")))
			ArmsTrade.led("home")
			return
		_legend_found(game, it, null, hb.get("pos", Vector2.ZERO))
		return
	if not hb.is_empty():
		var slot := it.slot()
		for u in hb["units"]:
			if not ArmsTrade._is_person(u) or u.equip.has(slot):
				continue
			if not ArmsTrade.loadout_of(u).has(slot):
				continue
			if slot == "off_hand" and u.weapon() != null and u.weapon().tmpl().get("two_handed", false):
				continue
			u.equip[slot] = it
			ArmsTrade.led("rekit")
			return
		var l: Dictionary = w.get("lairs", {}).get(String(hb.get("home", "")), {})
		if not l.is_empty() and l.has("stock"):
			if (l["stock"] as Array).size() < Bandits.STOCK_MAX:
				(l["stock"] as Array).append(it)
				ArmsTrade.led("home")
				return
			ArmsTrade.led("lost")
			return
	var town := _holder_town(game, holder)
	if TownEcon.has_econ(town):
		ArmsTrade.armory(town).append(it)
		TownEcon.led(town["econ"], "made", "arms", 1)   # an inflow from the field into the town's holdings
		ArmsTrade.led("home")
		return
	ArmsTrade.led("lost")

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
			ArmsTrade.led("fled_lost")
		u.equip.clear()
		return
	var e: Dictionary = town["econ"]
	var own: bool = town["faction"] == u.faction
	var f := People.fam_of(town, u.family)
	for slot in u.equip.keys():
		var it: Item = u.equip[slot]
		u.equip.erase(slot)
		if it.is_legend():   # v0.014: never left by the road: into his home town's armory, fee or no fee
			ArmsTrade.armory(town).append(it)
			TownEcon.led(e, "made", "arms", 1)
			Legends.note(it, float(game.day), "Handed in at the armory of %s by %s." % [String(town.get("name", "?")), u.name])
			ArmsTrade.led("fled")
			continue
		if ArmsTrade.cls(it.tid) == "":
			(town["shop"] as Array).append(it)
			TownEcon.led(e, "made", "arms", 1)
			ArmsTrade.led("fled")
			continue
		if not own:
			var p := Economy.base_value(town, it) * FENCE_SHARE
			if f.is_empty() or float(e["treasury"]) < p:
				ArmsTrade.led("fled_lost")
				continue
			e["treasury"] = float(e["treasury"]) - p
			f["purse"] = float(f["purse"]) + p
			ArmsTrade.led("fenced")
		else:
			ArmsTrade.led("fled")
		ArmsTrade.armory(town).append(it)
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
	ArmsTrade.rekit_units(game, town, units, true, null, true)   # the empty armory slots (optional ones too)
	wb["outfitted"] = true   # arms trade: their kit is real now (it comes home with them)
	var gaps := ArmsTrade.gaps_of(units)
	var n := 0
	for c in gaps:
		n += int(gaps[c])
	if n > 0 and TownEcon.has_econ(town):
		var e: Dictionary = town["econ"]
		var stall := false
		for it in town.get("shop", []):
			if gaps.has(ArmsTrade.cls(it.tid)):
				stall = true
				break
		if stall:
			ArmsTrade.log_line(e, "guards_money", "A caravan's %d guards left without %s: the armory had none and the treasury (%d coins) could not buy them off the stalls." % [
				units.size(), ArmsTrade._words(gaps), int(e["treasury"])])
		else:
			ArmsTrade.log_line(e, "guards_none", "A caravan's %d guards left without %s: none in the armory nor on the stalls." % [units.size(), ArmsTrade._words(gaps)])
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
				if ArmsTrade.cls(it.tid) != "" and town["faction"] == u.faction:
					ArmsTrade.armory(town).append(it)
					TownEcon.led(e, "made", "arms", 1)   # back into the town's holdings
					ArmsTrade.led("guards")
					continue
				var p := minf(Economy.base_value(town, it) * share, maxf(0.0, float(mkt["till"])))
				mkt["till"] = float(mkt["till"]) - p
				e["treasury"] = float(e["treasury"]) + p
				(town["shop"] as Array).append(it)
				TownEcon.led(e, "made", "arms", 1)   # back into the market's count
				ArmsTrade.led("guards")
		else:
			for s in u.equip:
				ArmsTrade.led("guards_lost")
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
		ArmsTrade.armory(town).append(it)
		ArmsTrade.led("cargo_looted")

## The company's battle is over (CampaignWorld.on_battle_result, before the dead are filtered out): the AI winner
## loots the company's fallen and its own; the guards of an escorted caravan and allied bands go to whoever holds it.
static func after_company_battle(game, result: Dictionary, wb: Dictionary, car: Dictionary, ally_ids: Array) -> void:
	# A player victory settles gear elsewhere; recover mounts before either side
	# filters its fallen out of the campaign band.
	for u: Unit in wb.get("units", []):
		if u.dead: Horses.return_mount(game, u)
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
			if TownEcon.has_econ(t): ArmsTrade.econ_daily(game, t, t["econ"], int(job[1]), false)
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
	ArmsTrade.log_line(source["econ"], "supply_out_" + String(dest["id"]), "%d surplus %s transferred to our faction's garrison at %s." % [n, good, dest["name"]])
	ArmsTrade.log_line(dest["econ"], "supply_in_" + String(source["id"]), "%d %s received from our faction's armoury at %s." % [n, good, source["name"]])

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
	if st.is_empty(): w["arms"] = ArmsTrade.new_state(); st = w["arms"]
	if checkpoint % SUPPLY_EVERY != 0 or checkpoint <= int(st.get("supply_day", -1)): return 0
	var ids: Array = w["towns"].keys(); ids.sort()
	var rows := {}; var moved := 0
	for tid in ids:
		var town: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(town): continue
		ArmsTrade.refresh_reserve(game, town)
		var have := ArmsTrade.role_counts(town["econ"]["arms_have"])
		var target := ArmsTrade.role_counts(town["econ"]["arms_tgt"])
		have["arrows"] = ArmsTrade.arrow_stock(town)
		target["arrows"] = int(town["econ"]["arrow_reserve"])
		rows[tid] = {"have": have, "target": target}
	var shortlists := _supply_shortlists(w, rows, ids)
	for source_id in ids:
		if not rows.has(source_id): continue
		var source: Dictionary = w["towns"][source_id]
		var candidates: Dictionary = shortlists.get(source.get("faction", ""), {})
		var row: Dictionary = rows[source_id]
		var arm := ArmsTrade.armory(source)
		var routes := {}
		for i in range(arm.size() - 1, -1, -1):
			var it: Item = arm[i]
			var c := ArmsTrade.cls(it.tid)
			if c == "": continue
			var r := ArmsTrade.cls_role(c)
			if int(row["have"].get(r, 0)) <= int(row["target"].get(r, 0)): continue
			var dest_id := _supply_destination(w, rows, candidates.get(r, []), String(source_id), r)
			if dest_id == "": continue
			var dest: Dictionary = w["towns"][dest_id]
			arm.remove_at(i); ArmsTrade.armory(dest).append(it)
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
	for tid in rows: ArmsTrade.refresh_reserve(game, w["towns"][tid])
	st["supply_day"] = checkpoint
	st["supply_moved"] = int(st.get("supply_moved", 0)) + moved
	return moved
