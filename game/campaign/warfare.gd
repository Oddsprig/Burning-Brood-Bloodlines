class_name Warfare
extends RefCounted
## Player warfare against settlements, dragons marching with the field army, and the dynasty's ambitions.
##
## Raid: the army falls on a foreign settlement. Its garrison (militia + guards) fights; if the army wins, it
##   carries off coin from the treasury and from common households, burns stored grain, kills some residents,
##   and leaves grievance behind: the town's loyalty to its own lord falls, its realm turns hostile.
## Siege: the army assaults the walls. Defenders hold their ground (they never leave the walls). If the army
##   wins, the settlement swears to the player's realm: forces of that town change sides, the old realm becomes
##   an enemy, and the conquered town starts resentful (low loyalty, high grievance) and can rebel later.
## Every person, coin and piece of gear stays in the same native records as everywhere else.
const NEAR := 90.0
const RAID_COOLDOWN := 30
const TREASURY_TAKE := 0.35
const PURSE_TAKE := 0.12
const GRAIN_BURN := 0.4
const KILL_SHARE := 0.03

static func _state(game) -> Dictionary:
	if not game.world.has("warfare"):
		game.world["warfare"] = {"raids": {}, "conquests": [], "battles_won": 0, "battles_lost": 0, "raided_coin": 0.0,
			"ambitions_done": {}, "victory_seen": false, "dragon_kills": 0}
	return game.world["warfare"]

static func player_faction(game) -> String:
	var tid := str(Dynasty.selected(game).get("town_id", ""))
	return str(game.world.get("towns", {}).get(tid, {}).get("faction", ""))

## Guards first, then militia. The whole garrison does not man one stretch of wall: at most 1.25x the attacking
## army (never fewer than 12, never more than 200) takes the field; the rest hold elsewhere and are unharmed.
static func _defenders(game, tid: String) -> Array:
	var guards: Array = TownDefence.guards(game, tid).filter(func(u): return u is Unit and not u.dead)
	var militia: Array = Militia.units_of(game, tid)
	var all: Array = guards + militia
	var cap := clampi(int(ceil(float(game.deployed_units().size()) * 1.25)), 12, 200)
	return all.slice(0, mini(all.size(), cap))

## {ok, reason, defenders} for kind "raid" | "siege".
static func preview(game, tid: String, kind: String) -> Dictionary:
	var w: Dictionary = game.world
	var town: Dictionary = w.get("towns", {}).get(tid, {})
	if town.is_empty(): return {"ok": false, "reason": "Unknown settlement."}
	if Dynasty.selected(game).is_empty(): return {"ok": false, "reason": "Choose your house first."}
	var mine := player_faction(game)
	if str(town.get("faction", "")) == mine: return {"ok": false, "reason": "%s is sworn to your own realm." % town["name"]}
	if Diplomacy.peace_bound(w, mine, str(town.get("faction", ""))):
		return {"ok": false, "reason": "Your alliance or non-aggression pact forbids attacking this realm."}
	if game.deployed_units().is_empty(): return {"ok": false, "reason": "Raise a field army before attacking a settlement."}
	if (w["party"]["pos"] as Vector2).distance_to(town["pos"]) > NEAR: return {"ok": false, "reason": "March your army up to %s first." % town["name"]}
	if w.get("encounter", "") != "": return {"ok": false, "reason": "Deal with the enemy in front of you first."}
	var st := _state(game)
	if kind == "raid" and int(st["raids"].get(tid, -999)) + RAID_COOLDOWN > int(game.day):
		return {"ok": false, "reason": "%s was raided recently; nothing worth taking is left yet." % town["name"]}
	var defenders := _defenders(game, tid)
	var diplomatic := ""
	if not CampaignWorld.is_hostile(game, str(town["faction"])):
		diplomatic = " %s is not at war with you: attacking will make them an enemy." % CampaignWorld.faction_the(str(town["faction"])).capitalize()
	var what := "Plunder its treasury, households and granary." if kind == "raid" else "Storm the walls; a victory brings the settlement into your realm."
	if kind == "siege" and Marriage.has_claim(game, tid): what += " Your house holds a marriage claim here: the town will accept you."
	return {"ok": true, "kind": kind, "town_id": tid, "defenders": defenders.size(), "fit": game.deployed_units().size(),
		"reason": "%s %d defenders hold %s against your %d.%s" % [what, defenders.size(), town["name"], game.deployed_units().size(), diplomatic],
		"dragon_meat": Supplies.dragon_meat_plan(game)}

static func start(game, tid: String, kind: String) -> Dictionary:
	var p := preview(game, tid, kind)
	if not p.get("ok", false): return p
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"][tid]
	var fid := str(town["faction"])
	Diplomacy.on_fight(game, fid, false)
	Diplomacy.on_town_attacked(w, fid, player_faction(game), kind == "siege")
	CampaignWorld.change_rep(game, fid, -20 if kind == "raid" else -30, "You %s %s." % ["raided" if kind == "raid" else "besieged", town["name"]])
	var defenders := _defenders(game, tid)
	if defenders.is_empty():
		var res := resolve(game, tid, kind, true, {})
		return {"ok": true, "battle": false, "reason": str(res.get("text", ""))}
	TownDefence.set_muster(game, town, true)
	var band_id := str(w.get("militia", {}).get(tid, ""))
	if band_id == "" or not w["warbands"].has(band_id): band_id = str(w.get("town_guards", {}).get(tid, ""))
	var params := {"enemy": defenders, "allies": [], "map": "large" if defenders.size() + game.deployed_units().size() > 10 else "small",
		"terrain": CampaignWorld.terrain_at(w, town["pos"]), "warband_id": band_id, "caravan_id": "", "ally_bands": [],
		"enemy_supply": "well", "ally_supply": "well", "assault": {"kind": kind, "town_id": tid}}
	if kind == "siege": params["hold1"] = true
	game.start_battle(params)
	return {"ok": true, "battle": true}

## After the battle (or at once when nobody defends). won = the player's army holds the field.
static func resolve(game, tid: String, kind: String, won: bool, result: Dictionary) -> Dictionary:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"].get(tid, {})
	var st := _state(game)
	if town.is_empty(): return {}
	var out := {"kind": kind, "town_id": tid, "won": won}
	if not won:
		out["text"] = "The assault on %s was thrown back." % town["name"] if kind == "siege" else "The raid on %s was beaten off." % town["name"]
		CampaignWorld.log_event(game, out["text"])
		result["assault_outcome"] = out
		return out
	if kind == "raid": out.merge(_plunder(game, tid))
	else: out.merge(_conquer(game, tid))
	Migration.note_attack(w, tid, float(game.day))   # v0.034: raided or taken, its people fear for their lives
	result["assault_outcome"] = out
	CampaignWorld.log_event(game, str(out.get("text", "")))
	game.changed.emit()
	return out

static func _plunder(game, tid: String) -> Dictionary:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"][tid]
	var st := _state(game)
	st["raids"][tid] = int(game.day)
	var coin := 0.0
	var killed := 0
	var burned := 0
	if TownEcon.has_econ(town):
		var e: Dictionary = town["econ"]
		var take := maxf(0.0, float(e.get("treasury", 0.0))) * TREASURY_TAKE
		e["treasury"] = float(e["treasury"]) - take
		coin += take
		for f in e.get("fams", []):
			if f.get("gone", false) or f.get("estate", false): continue
			var purse := maxf(0.0, float(f.get("purse", 0.0)))
			var grab := purse * PURSE_TAKE
			f["purse"] = purse - grab
			coin += grab
		var stock: Dictionary = e.get("stock", {})
		if stock.has("grain"):
			burned = int(float(stock["grain"]) * GRAIN_BURN)
			stock["grain"] = int(stock["grain"]) - burned
		var to_kill := int(round(float(e.get("pop", 0)) * KILL_SHARE))
		var rng := RandomNumberGenerator.new(); rng.seed = hash([w.get("seed", 0), tid, int(game.day), "raid"])
		for f in e.get("fams", []):
			if to_kill <= 0: break
			if not Population.is_cohort(f) or f.get("gone", false): continue
			var keys: Array = (f.get("age_bins", {}) as Dictionary).keys()
			if keys.is_empty(): continue
			var key = keys[rng.randi() % keys.size()]
			var n := mini(to_kill, maxi(1, int(f["age_bins"][key]) / 3))
			var before := int(e.get("pop", 0))
			Population.kill_slots(e, f, key, n, float(game.day), "battle")
			killed += before - int(e.get("pop", 0))
			to_kill -= n
		e["unrest"] = minf(1.0, float(e.get("unrest", 0.0)) + 0.3)
		TownEcon.town_event(e, "sacked", [Dynasty.selected(game).get("house_name", "raiders")], float(game.day))
	var gained := int(floor(coin))
	game.gold = int(game.gold) + gained
	st["raided_coin"] = float(st["raided_coin"]) + gained
	var row: Dictionary = w.get("feudal", {}).get("towns", {}).get(tid, {})
	if not row.is_empty():
		row["loyalty"] = clampf(float(row["loyalty"]) - 12.0, 0.0, 100.0)
		row["grievance"] = clampf(float(row["grievance"]) + 20.0, 0.0, 100.0)
	town["wealth"] = maxi(1, int(town.get("wealth", 1)) - 1)
	var text := "Your army raided %s: %s carried off, %d grain burned, %d residents killed. Its people blame their lord." % [
		town["name"], _coin_text(gained), burned, killed]
	return {"coin": gained, "grain_burned": burned, "killed": killed, "text": text}

static func _conquer(game, tid: String) -> Dictionary:
	var w: Dictionary = game.world
	var town: Dictionary = w["towns"][tid]
	var old := str(town["faction"])
	var target := player_faction(game)
	if target == "" or target == old: return {"text": "%s is already yours." % town["name"]}
	var was_capital := str(w["factions"].get(old, {}).get("capital", "")) == tid
	town["faction"] = target
	if town.has("econ") and town["econ"] is Dictionary: town["econ"]["faction"] = target
	Feudal._transfer_forces(game, tid, old, target)
	var row: Dictionary = Feudal._state(w)["towns"].get(tid, {})
	var claimed := Marriage.has_claim(game, tid)
	if not row.is_empty():
		row["loyalty"] = 60.0 if claimed else 30.0; row["grievance"] = 10.0 if claimed else 45.0
		row["last_defection"] = int(game.day); row["last_action"] = int(game.day)
	Feudal.prepare_world(game)
	Academy.sync_towns(w, old); Academy.sync_towns(w, target)
	Diplomacy._push(w, old, target, -50.0)
	if w.has("diplo"): w["diplo"]["size"] = {}
	if w.has("war"): w["war"]["intel"] = {}; w["war"]["avg"] = {}
	var st := _state(game)
	st["conquests"].append({"town_id": tid, "day": int(game.day), "from": old})
	var text := "%s has fallen! It now swears to %s.%s %s" % [town["name"], CampaignWorld.faction_name(target),
		" %s has lost its seat." % CampaignWorld.faction_the(old).capitalize() if was_capital else "",
		"Your house's marriage claim makes the conquest a rightful one; the town accepts you." if claimed else "Its people resent the conquest."]
	Feudal._history(game, tid, text)
	if w["factions"].get(old, {}).get("towns", []).is_empty():
		var gone := "%s has no settlements left and is broken." % CampaignWorld.faction_the(old).capitalize()
		CampaignWorld.log_event(game, gone)
		text += " " + gone
	return {"text": text, "from": old, "to": target}

## Game.finish_battle hook: records the battle, settles a pending assault.
static func after_battle(game, result: Dictionary, assault: Dictionary) -> void:   # assault = the pending battle
	if game.world.is_empty() or Dynasty.selected(game).is_empty(): return
	var st := _state(game)
	var won := int(result.get("winner", -1)) == 0
	if won: st["battles_won"] = int(st["battles_won"]) + 1
	if won and not assault.get("dragon_units", []).is_empty(): st["dragon_victories"] = int(st.get("dragon_victories", 0)) + 1
	else: st["battles_lost"] = int(st["battles_lost"]) + 1
	var pending: Dictionary = assault.get("assault", {})
	if not pending.is_empty():
		DragonFear.after_battle(game, result, assault)
		resolve(game, str(pending.get("town_id", "")), str(pending.get("kind", "raid")), won, result)
	Ambitions.check(game)

# ------------------------------------------------------------------ dragons on campaign
## A bonded adult dragon can march with the raised field army. Its rider rides it; it eats packed meat.
static func march_status(game, uid: String) -> Dictionary:
	var row: Dictionary = Dragons.get_record(game, uid)
	var marching := bool(row.get("campaign_march", {}).get("enabled", false))
	if row.is_empty(): return {"ok": false, "marching": false, "reason": "Unknown dragon."}
	if not bool(row.get("alive", false)): return {"ok": false, "marching": false, "reason": "This dragon is dead."}
	var reason := ""
	if marching:
		reason = _march_reason(game, row, false)
		return {"ok": true, "marching": true, "active": reason == "", "can_recall": true,
			"reason": "Marching with your army. It eats packed meat." if reason == "" else "Marching, but cannot fight: " + reason, "feed": feed_cost(row)}
	reason = _march_reason(game, row, true)
	var meat_day := DragonCare.food_need_units(game, row)
	return {"ok": true, "marching": false, "can_march": reason == "", "reason": reason if reason != "" else
		"Can march with the army (%d meat a day from the packed stores)." % meat_day, "feed": feed_cost(row)}

static func _coin_text(c: int) -> String:
	return "%d coins" % int(round(float(c) / Item.COIN))

static func _march_reason(game, row: Dictionary, ordering: bool) -> String:
	if str(row.get("stage", "")) != "adult": return "Only an adult dragon can go to war."
	var rights: Dictionary = Dragons.authority(game, row)
	if not bool(rights["ok"]): return str(rights["reason"])
	var bond: Dictionary = DragonBond.status(game, str(row["id"]))
	if not bool(bond.get("active", false)): return "It needs a bonded rider."
	if game.company.is_empty(): return "Raise a field army first."
	if ordering:
		var loc := str(row.get("location_town_id", ""))
		if not Mobilization._here(game, loc): return "Visit %s, where the dragon is kept." % str(game.world.get("towns", {}).get(loc, {}).get("name", "its home"))
	var unit: Unit = DragonCombat._unit(game, str(row["id"]))
	if unit == null or unit.dead: return "No living body."
	var health: Dictionary = HealthReport.describe(unit)
	if str(health.get("fitness", "")) == "cannot fight": return "Too badly hurt to fight."
	if float(row.get("care", {}).get("health", 1.0)) <= 0.05: return "Starving: it needs feeding."
	return ""

static func feed_cost(row: Dictionary) -> int:
	var linear := float(DragonGrowth.metrics(row).get("linear_scale", 1.0))
	return int(clampf(round(6.0 * linear * linear), 2.0, 30.0)) * Item.COIN

static func set_march(game, uid: String, on: bool) -> Dictionary:
	var st := march_status(game, uid)
	if on and not bool(st.get("can_march", false)): return {"ok": false, "reason": str(st.get("reason", ""))}
	var live: Dictionary = game.world.get("dragons", {}).get("records", {}).get(uid, {})
	if live.is_empty(): return {"ok": false, "reason": "Unknown dragon."}
	if on:
		live["campaign_march"] = {"enabled": true, "day": float(game.day), "rider_person_uid": str(live.get("rider_person_uid", ""))}
		Dragons._history(game, live, "march", {"enabled": true})
		return {"ok": true, "reason": "%s will march and fight with your army." % live.get("name", "The dragon")}
	live.erase("campaign_march")
	Dragons._history(game, live, "march", {"enabled": false})
	return {"ok": true, "reason": "%s flies home to %s." % [live.get("name", "The dragon"), str(game.world.get("towns", {}).get(str(live.get("location_town_id", "")), {}).get("name", "its roost"))]}

## Dragons marching with the army that may fight this battle (in addition to home-defence dragons).
static func marching_units(game) -> Array:
	var out: Array = []
	for row: Dictionary in game.world.get("dragons", {}).get("records", {}).values():
		if not bool(row.get("campaign_march", {}).get("enabled", false)): continue
		if _march_reason(game, row, false) != "": continue
		var unit: Unit = DragonCombat._unit(game, str(row["id"]))
		if unit != null and not out.has(unit): out.append(unit)
	return out

## Daily: marching dragons eat packed meat once, through the same care day as home. Recalled when the army stands down.
static func daily(game, days: int) -> void:
	for d in days:
		Marriage.daily(game)
		Intrigue.daily(game, int(game.day) - days + d + 1)
		Prisoners.daily(game, int(game.day) - days + d + 1)
	if not game.world.has("dragons"): return
	for row: Dictionary in game.world["dragons"].get("records", {}).values():
		if not bool(row.get("campaign_march", {}).get("enabled", false)): continue
		if game.company.is_empty() or not bool(row.get("alive", false)):
			row.erase("campaign_march")
			continue
		for d in days:
			var day := int(floor(float(game.day))) - days + d + 1
			DragonCare.settle(game, row, day)


