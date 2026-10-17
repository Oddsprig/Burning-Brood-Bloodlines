class_name Contracts
extends RefCounted
## Town contracts. Shipped kinds: "battle" (destroy a specific warband, spawned on accept), "defend"
## (a warband marches on the town by the deadline) and "escort" (guard a caravan to dest_id; target_id is
## the caravan; see caravans.gd). "raid" exists as data only (KIND_INFO).
## Diplomacy (campaign/diplomacy.gd): "war" (employer X pays to break a war band of Y while X and Y are at
## WAR; hunt plumbing; void on peace); every faction hires; offers_for() filters by the company's standing.
##
## contract = {id, kind, employer, town_id, target_faction, target_id, size, pay, desc, title,
##             deadline_day, state: offered|active|done|failed|void, offered_day, accepted_day}
## Pay scales with the target faction's wealth and the band size: the same numbers that set the
## enemies' gear (Factory.make_warband uses faction wealth), so pay tracks difficulty.

const KIND_INFO := {
	"battle": {"name": "Hunt", "offered": true},
	"defend": {"name": "Defend", "offered": true},
	"escort": {"name": "Escort", "offered": true},
	"war": {"name": "War", "offered": true},   # diplomacy: employer X vs a band of Y while X and Y are at WAR
	"raid": {"name": "Raid", "offered": false, "note": "stub: burn an enemy camp or village"},
	# monsters wave 1 (campaign/monster_contracts.gd)
	"hunt": {"name": "Hunt", "offered": true},
	"lair": {"name": "Clear the lair", "offered": true},
	"bounty": {"name": "Bounty", "offered": true},
	"bandits": {"name": "Bandits", "offered": true},
}
## Standing moves now live in Diplomacy (contract done +3..+8 by size, failed -5, abandoned -8).
const REP_SUCCESS := Diplomacy.CONTRACT_DONE_MAX
const REP_FAIL := Diplomacy.CONTRACT_FAILED
const WAR_PAY := 1.3      # war contracts pay more than hunts [ours]
const TIER_PAY := 1.35    # veteran's contracts (standing > +50) [ours]

static func pay_for(target_faction: String, size: int, town_wealth: int) -> int:
	var fw := int(DB.factions.get(target_faction, {}).get("wealth", 2))
	var per_unit := (60.0 + 40.0 * fw) * TownEcon.COIN   # coins
	return int(round(size * per_unit * (0.85 + 0.08 * town_wealth) / 5.0)) * 5

static func _band_word(fid: String) -> String:
	return DB.races.get(DB.factions[fid]["race"], {}).get("plural", "warriors")

static func generate_offers(town: Dictionary, day: float, rng: RandomNumberGenerator) -> Array:
	var fid: String = town["faction"]
	# diplomacy: every faction hires (orcs and goblins too); hunt/defend targets are the factions it is at
	# WAR with plus monster factions (player_hostile) it is HOSTILE with. Standing filters offers at display
	# time (offers_for) because towns refresh without the company in view.
	var w: Dictionary = Game.world
	var enemies := []
	for other in DB.factions:
		if other == fid or DB.factions[other].get("wild", false):   # monsters wave 1: beasts/outlaws come through MonsterContracts
			continue
		var st := Diplomacy.state(w, fid, other)
		if st == Diplomacy.WAR or (st == Diplomacy.HOSTILE and DB.factions[other].get("player_hostile", false)):
			enemies.append(other)
	if enemies.is_empty():
		return []
	var monsters_hire: bool = DB.factions[fid].get("player_hostile", false)
	var n := rng.randi_range(1, 1 + int(int(town["size"]) >= 2) + int(int(town["size"]) >= 4))
	var out := []
	for i in n:
		var target: String = enemies[rng.randi() % enemies.size()]
		var kind := "defend" if rng.randf() < 0.3 else "battle"
		var size := clampi(rng.randi_range(4, 9) + int(day / 12.0), 3, 18)
		if kind == "defend":
			size += 2
		var pay := pay_for(target, size, int(town["wealth"]))
		var words := _band_word(target)
		var tname := CampaignWorld.faction_the(target)
		var c := {"id": "%s_c%d_%d" % [town["id"], int(day), i], "kind": kind, "employer": fid, "town_id": town["id"],
			"target_faction": target, "target_id": "", "size": size, "pay": pay, "base_pay": pay, "state": "offered",
			"offered_day": day, "accepted_day": -1.0, "deadline_day": -1.0}
		if kind == "battle":
			var days := rng.randi_range(8, 12)
			c["duration"] = days
			c["title"] = "Hunt down %s" % words
			c["desc"] = "A band of %s %s from %s has been preying on the roads around %s. Find them and destroy them within %d days." % [
				CampaignWorld.approx_count(size).split(" (")[0], words, tname, town["name"], days]
			if monsters_hire:   # diplomacy: orc and goblin employers pay for heads
				c["title"] = "Bring back %s heads" % DB.races.get(DB.factions[target]["race"], {}).get("name", "enemy")
				c["desc"] = "The chief of %s wants the heads of a band of %s %s from %s roaming nearby. Kill them all within %d days and the chief pays in coin." % [
					town["name"], CampaignWorld.approx_count(size).split(" (")[0], words, tname, days]
		else:
			var days := rng.randi_range(4, 7)
			c["duration"] = days
			c["title"] = "Defend %s" % town["name"]
			c["desc"] = "Scouts say %s of %s are massing to strike %s within %d days. Stop them before they reach the walls." % [
				words.capitalize(), tname, town["name"], days]
		out.append(c)
	# diplomacy: war contracts against factions at WAR with the employer
	for target in enemies:
		if Diplomacy.state(w, fid, target) == Diplomacy.WAR and rng.randf() < 0.6:
			out.append(war_offer(town, target, day, rng, out.size()))
	out.append_array(MonsterContracts.offers(town, day, rng))   # monsters wave 1: hunt / lair / bounty / bandits (own RNG)
	var esc := escort_offer(town, day, rng)
	if not esc.is_empty():
		out.append(esc)
	# diplomacy: one veteran's contract, shown only above +50 standing (kept last so plain offers come first)
	var vt: String = enemies[rng.randi() % enemies.size()]
	var vsize := clampi(rng.randi_range(7, 11) + int(day / 12.0), 5, 20)
	var vpay := int(round(pay_for(vt, vsize, int(town["wealth"])) * TIER_PAY / 5.0)) * 5
	var vdays := rng.randi_range(9, 13)
	out.append({"id": "%s_c%d_v" % [town["id"], int(day)], "kind": "battle", "tier": 1, "employer": fid, "town_id": town["id"],
		"target_faction": vt, "target_id": "", "size": vsize, "pay": vpay, "base_pay": vpay, "state": "offered",
		"offered_day": day, "accepted_day": -1.0, "deadline_day": -1.0, "duration": vdays,
		"title": "Veteran's contract: break %s" % _band_word(vt),
		"desc": "The lords of %s only offer this to companies they trust: a strong band of %s from %s is loose in the country. Destroy it within %d days." % [
			town["name"], _band_word(vt), CampaignWorld.faction_the(vt), vdays]})
	return out

## War contract: the employer pays the company to break a war band of an enemy it is at WAR with.
## Same plumbing as a hunt (a "contract" warband spawns on accept); void if peace comes first.
static func war_offer(town: Dictionary, target: String, day: float, rng: RandomNumberGenerator, i: int) -> Dictionary:
	var size := clampi(rng.randi_range(6, 11) + int(day / 12.0), 4, 20)
	var pay := int(round(pay_for(target, size, int(town["wealth"])) * WAR_PAY / 5.0)) * 5
	var days := rng.randi_range(9, 14)
	var tname := CampaignWorld.faction_the(target)
	var ename := CampaignWorld.faction_the(town["faction"])
	return {"id": "%s_c%d_w%d" % [town["id"], int(day), i], "kind": "war", "employer": town["faction"], "town_id": town["id"],
		"target_faction": target, "target_id": "", "size": size, "pay": pay, "base_pay": pay, "state": "offered",
		"offered_day": day, "accepted_day": -1.0, "deadline_day": -1.0, "duration": days,
		"title": "War: break a war band of %s" % _band_word(target),
		"desc": "%s is at war with %s. A war band of %s is marching through the borderlands near %s; break it within %d days. Taking a side in a war earns friends and enemies both." % [
			Diplomacy.cap(ename), tname, _band_word(target), town["name"], days]}

## Offers this company actually sees in a town (diplomacy): none below -30 standing with the employer (or
## when hostile), fewer below 0, veteran's contracts only above +50, war contracts only while the war lasts.
static func offers_for(game, town: Dictionary) -> Array:
	var cs: Array = town.get("contracts", [])
	var fid: String = town.get("faction", "")
	if not Diplomacy.contracts_allowed(game, fid):
		return []
	var s := Diplomacy.standing(game, fid)
	var plain := []
	var extra := []
	for c in cs:
		if int(c.get("tier", 0)) > 0:
			if Diplomacy.better_tier(game, fid):
				extra.append(c)
			continue
		if c.get("kind", "") == "war" and not Diplomacy.at_war(game.world, fid, c.get("target_faction", "")):
			continue
		plain.append(c)
	if s < 0 and not plain.is_empty():
		plain = plain.slice(0, maxi(1, int(ceil(plain.size() * (1.0 + s / 60.0)))))
	return plain + extra

## Diplomacy check before taking a contract: "" or the reason it is refused.
static func refusal(game, c: Dictionary) -> String:
	var fid: String = c.get("employer", "")
	if DB.factions.has(fid) and not Diplomacy.contracts_allowed(game, fid):
		return "%s will not hire you" % Diplomacy.cap(CampaignWorld.faction_the(fid))
	if int(c.get("tier", 0)) > 0 and not Diplomacy.better_tier(game, fid):
		return "they offer this only to companies they trust"
	if c.get("kind", "") == "war" and not Diplomacy.at_war(game.world, fid, c.get("target_faction", "")):
		return "that war is over"
	return ""

## Escort: guard a merchant caravan to a road-linked town (same faction or not at war). Pay grows with
## road distance and with how dangerous the road is (wars and monster raiders on either side).
static func escort_offer(town: Dictionary, day: float, rng: RandomNumberGenerator) -> Dictionary:
	if rng.randf() > 0.55:
		return {}
	var fid: String = town["faction"]
	var links := []
	for l in town.get("road_links", []):
		if Diplomacy.trade_ok(Game.world, fid, l["faction"]):   # diplomacy: no caravans to HOSTILE/WAR towns
			links.append(l)
	if links.is_empty():
		return {}
	var l: Dictionary = links[rng.randi() % links.size()]
	var dist := float(l["dist"])
	var travel_days := dist / (CampaignWorld.WARBAND_SPEED * Caravans.SPEED * 1.2)
	var danger := 1.0 + 0.1 * int(day / 10.0)
	var pay := int(round((120.0 + dist * 0.9) * TownEcon.COIN * danger * (0.85 + 0.08 * int(town["wealth"])) / 5.0)) * 5
	var dur := int(ceil(travel_days * 2.0 + 3.0))
	return {"id": "%s_c%d_e" % [town["id"], int(day)], "kind": "escort", "employer": fid, "town_id": town["id"],
		"dest_id": l["id"], "target_faction": "", "target_id": "", "size": 0, "pay": pay, "base_pay": pay, "state": "offered",
		"offered_day": day, "accepted_day": -1.0, "deadline_day": -1.0, "duration": dur,
		"title": "Escort a caravan", "desc": "Merchants of %s need guards for a caravan on the road to the next town, about %.0f days away. The caravan waits for you at the gate; stay close to it. Deliver it within %d days." % [
			town["name"], maxf(1.0, round(travel_days)), dur]}

## Pay this company would get for an offer: the best Negotiator adds 1.5% per level (tuned).
## Menus show this number; accept() locks it in as c.pay.
static func offered_pay(game, c: Dictionary) -> int:
	var neg: int = game.best_skill("negotiator") if game.has_method("best_skill") else 0
	var dm := Diplomacy.pay_mult(game, c.get("employer", "")) if DB.factions.has(c.get("employer", "")) else 1.0   # diplomacy: x(1 + standing/200)
	return int(round(float(c.get("base_pay", c.get("pay", 0))) * (1.0 + 0.015 * clampi(neg, 0, 20)) * dm / 5.0)) * 5

## Accept an offered contract: it becomes Game.contract and its target warband appears on the map.
## War pick 4: the enemy's town could spare no men for the force this contract is about; the offer is withdrawn.
static func _no_force(game, town: Dictionary, c: Dictionary) -> bool:
	c.erase("accepted_day")
	c.erase("deadline_day")
	c.erase("target_id")
	town["contracts"].erase(c)
	CampaignWorld.log_event(game, "The force in %s's contract never gathered: the offer is withdrawn." % town["name"])
	return false

static func accept(game, c: Dictionary) -> bool:
	if MonsterContracts.handles(c):   # monsters wave 1
		return MonsterContracts.accept(game, c)
	if ArmsTrade.special_job(c): return false   # retired offers cannot resurrect special arms jobs
	if not game.contract.is_empty() and game.contract.get("state", "") == "active":
		return false
	if refusal(game, c) != "":   # diplomacy: standing too low, veteran's terms, or the war is over
		return false
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"].get(c["town_id"], {})
	if town.is_empty():
		return false
	if c["kind"] == "escort":
		var erng := RandomNumberGenerator.new()
		erng.seed = hash([int(w.get("seed", 0)), c["id"]])
		var cid := Caravans.spawn(game, town["id"], erng, c.get("dest_id", ""), c["id"])
		if cid == "":
			return false
		var dest: Dictionary = w["towns"][c["dest_id"]]
		c["target_id"] = cid
		c["title"] = "Escort a caravan to %s" % dest["name"]
		c["accepted_day"] = game.day
		c["deadline_day"] = game.day + float(c.get("duration", 8))
		c["pay"] = offered_pay(game, c)
		c["state"] = "active"
		town["contracts"].erase(c)
		game.contract = c
		CampaignWorld.log_event(game, "Contract taken in %s: %s." % [town["name"], c["title"]])
		game.changed.emit()
		return true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), c["id"]])
	var target: String = c["target_faction"]
	# march from the direction of the enemy's homeland
	var cap: String = w["factions"].get(target, {}).get("capital", "")
	var toward: Vector2 = w["towns"][cap]["pos"] if cap != "" else town["pos"] + Vector2(300, 0)
	var dir: Vector2 = (toward - town["pos"]).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	dir = dir.rotated(rng.randf_range(-0.5, 0.5))
	var dur := float(c.get("duration", 8))
	c["accepted_day"] = game.day
	c["deadline_day"] = game.day + dur
	if c["kind"] in ["battle", "war"]:   # a war contract spawns its target like a hunt
		var pos: Vector2 = town["pos"] + dir * rng.randf_range(260.0, 440.0)
		c["target_id"] = CampaignWorld.spawn_warband(game, target, pos, int(c["size"]), "contract", rng, {"contract_id": c["id"]})
		if c["target_id"] == "":
			return _no_force(game, town, c)
	else:
		var pos: Vector2 = town["pos"] + dir * rng.randf_range(420.0, 620.0)
		var wid := CampaignWorld.spawn_warband(game, target, pos, int(c["size"]), "assault", rng,
			{"contract_id": c["id"], "target_town": town["id"]})
		if wid == "":
			return _no_force(game, town, c)
		var wb: Dictionary = w["warbands"][wid]
		var path := CampaignWorld.find_path(w, wb["pos"], town["pos"])
		var eta := CampaignWorld.path_length(wb["pos"], path) / (CampaignWorld.WARBAND_SPEED * 0.85)
		wb["march_day"] = maxf(game.day, c["deadline_day"] - eta)
		c["target_id"] = wid
	c["pay"] = offered_pay(game, c)
	c["state"] = "active"
	town["contracts"].erase(c)
	game.contract = c
	CampaignWorld.log_event(game, "Contract taken in %s: %s." % [town["name"], c["title"]])
	game.changed.emit()
	return true

static func complete(game) -> void:
	var c: Dictionary = game.contract
	if c.is_empty():
		return
	c["state"] = "done"
	var paid := _draw_pay(game, c)   # economy: the employer's town treasury pays (its faction's purse tops it up)
	game.gold += paid
	Diplomacy.on_contract_done(game, c)   # diplomacy: +3..+8 by size, plus taking sides in a war
	if paid < int(c["pay"]):
		CampaignWorld.log_event(game, "Contract fulfilled: %s. %d of %d coins paid; the rest is owed." % [c.get("title", ""), paid, int(c["pay"])])
	else:
		CampaignWorld.log_event(game, "Contract fulfilled: %s. %d coins paid." % [c.get("title", ""), int(c["pay"])])
	game.world["contracts_done"] = int(game.world.get("contracts_done", 0)) + 1
	game.contract = {}

## Real coin for the pay: out of the contract town's treasury, then the faction's. A broke employer owes the rest
## (the shortfall is the employer's debt, logged on the town) [ours]; the company gets only coin that exists
## (coinage: no coin from nothing). Returns the coins paid (a town without an economy pays in full).
static func _draw_pay(game, c: Dictionary) -> int:
	var t: Dictionary = game.world.get("towns", {}).get(c.get("payer_town", c.get("town_id", "")), {})   # arms trade: the buyer pays escorts
	if not TownEcon.has_econ(t):
		return int(c.get("pay", 0))
	var e: Dictionary = t["econ"]
	var pay := float(c.get("pay", 0))
	var a := minf(pay, maxf(0.0, float(e["treasury"])))
	e["treasury"] = float(e["treasury"]) - a
	pay -= a
	var fac: Dictionary = game.world.get("factions", {}).get(t["faction"], {})
	if pay > 0.0 and not fac.is_empty():
		var b := minf(pay, maxf(0.0, float(fac.get("treasury", 0.0))))
		fac["treasury"] = float(fac.get("treasury", 0.0)) - b
		pay -= b
	var drawn := float(c.get("pay", 0)) - pay
	var paid := floorf(drawn)
	e["treasury"] = float(e["treasury"]) + (drawn - paid)   # the fraction of a coin the floor left goes back
	pay = float(c.get("pay", 0)) - paid
	TownEcon.gold_out(paid)   # treasury coin out to the company
	if pay > 0.0:
		e["debt_to_company"] = float(e.get("debt_to_company", 0.0)) + pay   # paid on credit
	e["stats"]["contracts_paid"] = float(e["stats"].get("contracts_paid", 0.0)) + paid
	return int(paid)

static func fail(game, reason: String) -> void:
	var c: Dictionary = game.contract
	if c.is_empty():
		return
	c["state"] = "failed"
	Diplomacy.on_contract_failed(game, c)   # diplomacy: -5
	CampaignWorld.log_event(game, "Contract failed: %s. %s" % [c.get("title", ""), reason])
	# an unfinished hunt target simply joins the raiders
	var wb: Dictionary = game.world.get("warbands", {}).get(c.get("target_id", ""), {})
	if not wb.is_empty() and wb["kind"] == "caravan":
		wb["escort"] = ""        # the merchants go on alone
		wb["state"] = "travel"
	elif not wb.is_empty() and not MonsterContracts.handles(c):   # beasts and bandits stay what they are
		wb["kind"] = "raider"
		wb["contract_id"] = ""
	game.contract = {}

## Diplomacy: walking away from an active contract costs -8 with the employer.
static func abandon(game) -> void:
	var c: Dictionary = game.contract
	if c.is_empty() or c.get("state", "") != "active":
		return
	c["state"] = "abandoned"
	Diplomacy.on_contract_abandoned(game, c)
	CampaignWorld.log_event(game, "Contract abandoned: %s." % c.get("title", ""))
	_release_target(game, c)
	game.contract = {}

static func _release_target(game, c: Dictionary) -> void:
	var wb: Dictionary = game.world.get("warbands", {}).get(c.get("target_id", ""), {})
	if not wb.is_empty() and wb["kind"] == "caravan":
		wb["escort"] = ""        # the merchants go on alone
		wb["state"] = "travel"
	elif not wb.is_empty() and not MonsterContracts.handles(c):   # monsters wave 1: beasts and bandits stay what they are
		wb["kind"] = "raider"
		wb["contract_id"] = ""
	game.contract = {}

## Called once per day: deadlines and targets destroyed by someone else.
static func daily_check(game) -> void:
	var c: Dictionary = game.contract
	if c.is_empty() or c.get("state", "") != "active":
		return
	var exists: bool = game.world["warbands"].has(c.get("target_id", ""))
	if c["kind"] == "escort":
		if not exists:
			fail(game, "The caravan was lost.")
		elif game.day > float(c["deadline_day"]):
			fail(game, "The caravan never arrived in time.")
		return
	if not exists:
		c["state"] = "void"
		CampaignWorld.log_event(game, "Contract void: someone else dealt with the target of \"%s\"." % c.get("title", ""))
		game.contract = {}
		return
	if c["kind"] == "war" and not Diplomacy.at_war(game.world, c["employer"], c["target_faction"]):
		# diplomacy: peace came first; nobody pays for a war that is over, nobody blames you either
		c["state"] = "void"
		CampaignWorld.log_event(game, "Contract void: peace was made before \"%s\" was done." % c.get("title", ""))
		_release_target(game, c)
		return
	if (c["kind"] in ["battle", "war"] or MonsterContracts.handles(c)) and game.day > float(c["deadline_day"]):
		fail(game, "The band slipped away.")

## One-line HUD/menu text for the active contract.
static func status_text(game) -> String:
	var c: Dictionary = game.contract
	if c.is_empty():
		return "No contract"
	var left: float = float(c.get("deadline_day", 0.0)) - game.day
	var town: Dictionary = game.world.get("towns", {}).get(c.get("town_id", ""), {})
	# tracks: hunted targets add " | last seen near X, about N days ago" (campaign/tracks.gd)
	return "%s (%s) - %d coins, %.1f days left" % [c.get("title", "?"), town.get("name", "?"), int(c.get("pay", 0)), maxf(left, 0.0)] \
		+ Tracks.status_suffix(game)
