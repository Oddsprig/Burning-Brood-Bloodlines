class_name MonsterContracts
extends RefCounted
## Monsters wave 1, section D: contract types on the existing board, map and pay formulas (campaign/contracts.gd
## calls in through small hooks: generate_offers, accept, daily_check, fail, KIND_INFO).
##   hunt    : a wolf pack or boar sounder plaguing the village; it appears on accept and roams near the village.
##   lair    : clear a lair (bear den, wolf den, boar wallow, bandit camp); the fight uses lair terrain with choke
##             points (Lairs.battle_tiles via Monsters.battle_extras).
##   bounty  : a named target (pack leader, great bear, bandit chief); the reward grows the longer it lives and
##             scales with rarity.
##   bandits : a bandit gang or band of deserters on the roads.
## Pay: humanoid targets keep the faction/size pay formula (Contracts.pay_for) plus the gear-value loot rule;
## creatures carry no gear: pay = this fee + trophies auto-sold in the aftermath (Creatures.trophies).
## Offers use their own RNG (seeded from town and day) so the board's other offers are unchanged.

const KINDS := ["hunt", "lair", "bounty", "bandits"]
const RANGE := 650.0            # [ours] px: targets within this distance of the town are offered there
const BOUNTY_RANGE := 950.0     # [ours]
const FEE_BASE := 40.0 * TownEcon.COIN          # [ours] coins (40 gold x20)
const FEE_PER_POWER := 55.0 * TownEcon.COIN     # [ours] coins per unit of map power of the target
const LAIR_MULT := 1.3          # [ours] clearing a lair pays more than a hunt

static func handles(c: Dictionary) -> bool:
	return KINDS.has(String(c.get("kind", "")))

## Creature contract fee: (base + per power of the beasts) x rarity x town wealth.
static func creature_fee(units: Array, cid: String, town_wealth: int) -> int:
	var p := 0.0
	for u in units:
		p += Creatures.power(u)
	var r := float(Creatures.rarity_info(Creatures.rarity(cid)).get("bounty", 1.0))
	return int(round((FEE_BASE + FEE_PER_POWER * p) * r * (0.85 + 0.08 * town_wealth) / 5.0)) * 5

static func _fee_for(wb: Dictionary, town: Dictionary) -> int:
	if Monsters.is_monster_band(wb):
		return creature_fee(wb["units"], String(wb.get("creature", "wolf")), int(town["wealth"]))
	return Contracts.pay_for(wb["faction"], (wb["units"] as Array).size(), int(town["wealth"]))

static func bounty_pay(base: int, wb: Dictionary, day: float) -> int:
	var g := float(Creatures.tun("bounty_growth_per_day", 0.04))
	return int(round(base * (1.0 + g * maxf(0.0, day - float(wb.get("since", day)))) / 5.0)) * 5

static func _mk(town: Dictionary, day: float, kind: String, n: int, wb: Dictionary, pay: int, title: String, desc: String, dur: int) -> Dictionary:
	return {"id": "%s_m%d_%d" % [town["id"], int(day), n], "kind": kind, "employer": town["faction"], "town_id": town["id"],
		"target_faction": wb.get("faction", "beasts"), "target_id": wb.get("id", ""), "lair_id": wb.get("lair", ""),
		"creature": wb.get("creature", ""), "size": (wb.get("units", []) as Array).size(), "pay": pay, "base_pay": pay,
		"state": "offered", "offered_day": day, "accepted_day": -1.0, "deadline_day": -1.0, "duration": dur,
		"title": title, "desc": desc}

## Offers for a town board (called from Contracts.generate_offers). Up to two.
static func offers(town: Dictionary, day: float, _rng: RandomNumberGenerator) -> Array:
	var w: Dictionary = Game.world
	if w.is_empty() or not w.has("lairs") or not w.has("warbands"):
		return []
	# every faction hires (diplomacy); Contracts.offers_for filters by the company's standing
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), town["id"], int(day), "monsters"])
	var out := []
	var tpos: Vector2 = town["pos"]
	var lairs := []
	var bands := []
	var bounties := []
	var ids: Array = w["warbands"].keys()
	ids.sort()
	for wid in ids:
		var wb: Dictionary = w["warbands"][wid]
		if Monsters.suspended_band(wb): continue
		var d := (wb["pos"] as Vector2).distance_to(tpos)
		var k := String(wb["kind"])
		if String(wb.get("named", "")) != "" and d < BOUNTY_RANGE:
			bounties.append(wb)
		elif k in ["den", "camp"] or (k == "beasts" and String(wb.get("lair", "")) != ""):
			if d < RANGE:
				lairs.append(wb)
		elif k in ["bandit", "deserter"] and d < RANGE:
			bands.append(wb)
	var n := 0
	# a pack plaguing the village (spawned on accept)
	if rng.randf() < 0.45:
		var cid := Monsters.pick_creature(w, day, rng, true)
		if cid != "":
			var cd := Creatures.def(cid)
			var g: Array = cd.get("group", [2, 4])
			var size := int(round((float(g[0]) + float(g[1])) * 0.5))
			var est := []
			var r := float(Creatures.rarity_info(Creatures.rarity(cid)).get("bounty", 1.0))
			var pay := int(round((FEE_BASE + FEE_PER_POWER * float(cd.get("power", 1.0)) * size) * r * (0.85 + 0.08 * int(town["wealth"])) / 5.0)) * 5
			var dur := rng.randi_range(6, 9)
			var c := _mk(town, day, "hunt", n, {"faction": "beasts", "creature": cid, "units": est}, pay,
				"Hunt the %s" % cd.get("plural", cid),
				"%s are killing livestock and worse around %s. Hunt them down within %d days. They roam near the village; pelts and trophies are yours to sell." % [
					String(cd.get("plural", cid)).capitalize(), town["name"], dur], dur)
			c["size"] = size
			out.append(c)
			n += 1
	if not bounties.is_empty() and rng.randf() < 0.6:
		var wb: Dictionary = bounties[rng.randi() % bounties.size()]
		var base := _fee_for(wb, town) * 2
		if Monsters.is_monster_band(wb):
			base = int(round(base * float(Creatures.rarity_info(Creatures.rarity(String(wb.get("creature", "")))).get("bounty", 1.0)) / 5.0)) * 5
		var dur2 := rng.randi_range(10, 14)
		var c2 := _mk(town, day, "bounty", n, wb, bounty_pay(base, wb, day), "Bounty: %s" % wb["named"],
			"A price is on the head of %s, %s %s. The longer it lives, the more %s pays. %d days." % [wb["named"], Monsters.kind_text(wb).split(", ")[-1] if Monsters.is_monster_band(wb) else "chief of the outlaws",
				Monsters.home_text(w, wb), town["name"], dur2], dur2)
		c2["base_pay"] = base
		c2["pay"] = bounty_pay(base, wb, day)
		out.append(c2)
		n += 1
	elif not lairs.is_empty() and rng.randf() < 0.6:
		var wb2: Dictionary = lairs[rng.randi() % lairs.size()]
		var l: Dictionary = w["lairs"].get(String(wb2.get("lair", "")), {})
		if not l.is_empty():
			var pay2 := int(round(_fee_for(wb2, town) * LAIR_MULT / 5.0)) * 5
			var dur3 := rng.randi_range(8, 12)
			out.append(_mk(town, day, "lair", n, wb2, pay2, "Clear the %s" % l["name"],
				"Clear out the %s. Expect to fight at the mouth of the place: narrow ground. %d days." % [Lairs.near_text(w, l), dur3], dur3))
			n += 1
	elif not bands.is_empty() and rng.randf() < 0.6:
		var wb3: Dictionary = bands[rng.randi() % bands.size()]
		var dur4 := rng.randi_range(6, 10)
		var deserter := bool(wb3.get("deserter", false))
		out.append(_mk(town, day, "bandits", n, wb3, _fee_for(wb3, town),
			"Hunt down %s" % ("deserters" if deserter else "bandits"),
			"%s are robbing travellers on the roads near %s. Destroy them within %d days." % [
				"Deserters from %s" % CampaignWorld.faction_the(wb3["faction"]) if deserter else "Bandits", town["name"], dur4], dur4))
		n += 1
	return out

## Accept one of these contracts (from Contracts.accept).
static func accept(game, c: Dictionary) -> bool:
	if Monsters.suspended_contract(c, game.world): return false
	if not game.contract.is_empty() and game.contract.get("state", "") == "active":
		return false
	if Contracts.refusal(game, c) != "":   # diplomacy: standing too low with the employer
		return false
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"].get(c["town_id"], {})
	if town.is_empty():
		return false
	if c["kind"] == "hunt":
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(w.get("seed", 0)), c["id"]])
		var wid := Monsters.spawn_plague(game, town, String(c.get("creature", "wolf")), rng)
		if wid == "":
			return false
		c["target_id"] = wid
	elif not w["warbands"].has(String(c.get("target_id", ""))):
		town["contracts"].erase(c)   # someone else already dealt with it
		return false
	var lid := String(c.get("lair_id", ""))
	if w.get("lairs", {}).has(lid):
		w["lairs"][lid]["known"] = true
	c["accepted_day"] = game.day
	c["deadline_day"] = game.day + float(c.get("duration", 8))
	c["pay"] = Contracts.offered_pay(game, c)
	c["state"] = "active"
	town["contracts"].erase(c)
	game.contract = c
	CampaignWorld.log_event(game, "Contract taken in %s: %s." % [town["name"], c["title"]])
	game.changed.emit()
	return true

## Daily: bounty prices grow while the target lives (offers on boards and the active contract).
static func daily(game) -> void:
	var w: Dictionary = game.world
	for tid in w["towns"]:
		for c in w["towns"][tid].get("contracts", []):
			if Monsters.suspended_contract(c, w): continue
			if c.get("kind", "") == "bounty":
				var wb: Dictionary = w["warbands"].get(String(c.get("target_id", "")), {})
				if not wb.is_empty():
					c["pay"] = bounty_pay(int(c["base_pay"]), wb, float(game.day))
	var a: Dictionary = game.contract
	if Monsters.suspended_contract(a, w): return
	if a.get("kind", "") == "bounty" and a.get("state", "") == "active":
		var wb2: Dictionary = w["warbands"].get(String(a.get("target_id", "")), {})
		if not wb2.is_empty():
			a["pay"] = maxi(int(a["pay"]), bounty_pay(Contracts.offered_pay(game, {"base_pay": a["base_pay"]}), wb2, float(game.day)))

## Right before Contracts.complete: the bounty pays its grown price.
static func before_complete(game, wb: Dictionary) -> void:
	if Monsters.suspended_band(wb) or Monsters.suspended_contract(game.contract, game.world): return
	var a: Dictionary = game.contract
	if a.get("kind", "") == "bounty":
		a["pay"] = maxi(int(a["pay"]), bounty_pay(Contracts.offered_pay(game, {"base_pay": a["base_pay"]}), wb, float(game.day)))
