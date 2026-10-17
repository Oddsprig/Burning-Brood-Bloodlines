class_name BattleRounds
extends RefCounted
## Large battles are fought in literal rounds: one unit of up to ROUND fit men from each army meets the other
## and they fight until that clash is finished; then the next pair goes into the fray. Survivors fall back to
## their army; the wounded sit out every later round; the round's loser leaves its downed men to the winner as
## prisoners. Each army's morale (and its officers' nerve) decides when it breaks and quits the field.
## State lives in Game.pending_battle["rounds"] between rounds (the battle scene reloads for each round).
const ROUND := 100
const START_MORALE := 70.0
const BREAK_MORALE := 25.0
const BREAK_LOSS := 0.6       # an army that has lost this share of its starting men is beaten
const MAX_ROUNDS := 20
const REMUSTER_DAYS := 5.0    # a beaten army regroups at its owner's seat this long before it can march

## True when this battle is big enough to be fought in rounds.
static func wanted(side0: Array, side1: Array) -> bool:
	return side0.size() > ROUND or side1.size() > ROUND

static func active(game) -> bool:
	return not (game.pending_battle.get("rounds", {}) as Dictionary).is_empty()

## Sets up the pools and the first round's two units. side0: the player's whole force (company, allies, dragons).
static func begin(game, side0: Array, side1: Array) -> void:
	var st := {"pool": [side0.duplicate(), side1.duplicate()], "round": 0, "morale": [START_MORALE, START_MORALE],
		"start": [side0.size(), side1.size()], "dead": [0, 0], "wounded": [0, 0], "captured": [0, 0], "fled": [0, 0],
		"captives": [[], []], "fought": {}, "household": {}, "log": [], "broke": -1, "winner": -1, "over": false,
		"last_fought": [[], []], "commander": [_commander(game, side0, true), _commander(game, side1, false)]}
	game.pending_battle["rounds"] = st
	_pick_round(game)

## Each army's commander: the player's ruler or senior house member riding with it, else its highest-ranked officer.
static func _commander(game, pool: Array, player: bool) -> int:
	var best: Unit = null
	var ruler := str(game.world.get("player_house", {}).get("ruler_uid", ""))
	for u in pool:
		if not u is Unit or DragonCombat.is_dragon_unit(game, u): continue
		if player:
			var p := _person(game, u)
			if not p.is_empty() and str(Persons.g(p, Persons.PERSON_UID, "")) == ruler: return u.uid
			if best == null or (is_household(game, u) and not is_household(game, best)): best = u
		elif best == null or u.rank > best.rank or (u.rank == best.rank and u.is_officer() and not best.is_officer()):
			best = u
	return best.uid if best != null else -1

## Fit men waiting in a pool: alive, not taken, not too hurt to fight.
static func fit(game, pool: Array, captives: Array) -> Array:
	return pool.filter(func(u): return u is Unit and not u.dead and not captives.has(u) and _can_fight(game, u))

static func _can_fight(game, u: Unit) -> bool:
	if DragonCombat.is_dragon_unit(game, u): return not u.dead
	return str(HealthReport.describe(u).get("fitness", "")) != "cannot fight"

## The next pair of units: fresh men first; those who just fought fall to the back of the line.
static func _pick_round(game) -> void:
	var st: Dictionary = game.pending_battle["rounds"]
	st["round"] = int(st["round"]) + 1
	var picks := [[], []]
	for side in 2:
		var ready := fit(game, st["pool"][side], st["captives"][side])
		var rested := ready.filter(func(u): return not (st["last_fought"][side] as Array).has(u))
		var tired := ready.filter(func(u): return (st["last_fought"][side] as Array).has(u))
		picks[side] = (rested + tired).slice(0, ROUND)
	game.pending_battle["round_side0"] = picks[0]
	game.pending_battle["enemy"] = picks[1]
	game.pending_battle["seed"] = int(game.pending_battle.get("seed", 1)) + 7919
	st["last_fought"] = picks

static func _household_uid(game) -> String:
	return str(game.world.get("player_house", {}).get("house_uid", ""))

## The register row of a unit's person, or {} (dragons and men without a family record have none).
static func _person(game, u: Unit) -> Array:
	if u.family < 0: return []
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	if town.is_empty(): return []
	var f: Dictionary = People.fam_of(town, u.family)
	if f.is_empty(): return []
	return Persons.by_uid(f, u.uid)

## Tracked household members on either side (the player's house, and any named house of the enemy).
static func is_household(game, u: Unit) -> bool:
	var st: Dictionary = game.pending_battle.get("rounds", {})
	if not st.is_empty() and (st.get("commander", []) as Array).has(u.uid): return true   # each army's commander is always named
	var p := _person(game, u)
	if p.is_empty(): return false
	return str(Persons.g(p, Persons.HOUSE_UID, "")) == _household_uid(game) or u.has_meta("house_member")

static func _officer(u: Unit) -> bool:
	return u.role in ["captain", "officer"]

const FATE_RANK := {"unhurt": 0, "fled": 1, "wounded": 2, "captured": 3, "dead": 4}

## Applies one finished round (r = battle.gd build_result) and returns its summary for the round panel.
static func after_round(game, r: Dictionary) -> Dictionary:
	var st: Dictionary = game.pending_battle["rounds"]
	var units: Array = r.get("fighter_units", [])
	var states: Array = r.get("fighter_states", [])
	var w := int(r.get("winner", -1))
	var d := {"round": int(st["round"]), "winner": w, "names": r.get("side_names", ["Your army", "Enemy"]),
		"fought": [0, 0], "dead": [0, 0], "wounded": [0, 0], "captured": [0, 0], "fled": [0, 0], "household": []}
	if not st.has("deeds"): st["deeds"] = {}
	Ennoble.tally(game, r, st["commander"], st["deeds"])
	var officers_lost := [0, 0]
	var officers_in := [0, 0]
	var captain_lost := [false, false]
	for i in units.size():
		var u: Unit = units[i]
		var side := 0 if (st["pool"][0] as Array).has(u) else 1
		d["fought"][side] += 1
		st["fought"][u] = true
		var s := str(states[i]) if i < states.size() else ""
		var fate := "unhurt"
		if u.dead or s == "dead":
			fate = "dead"
		elif (s == "unconscious" or s == "prone") and w >= 0 and side != w and not DragonCombat.is_dragon_unit(game, u):
			fate = "captured"   # downed on a field the other side holds
			(st["captives"][side] as Array).append(u)
		elif s == "fled":
			fate = "fled"
		elif not _can_fight(game, u):
			fate = "wounded"
		if _officer(u): officers_in[side] += 1
		if fate != "unhurt" and fate != "fled" and _officer(u):
			officers_lost[side] += 1
			if int(st["commander"][side]) == u.uid: captain_lost[side] = true
		if fate in ["dead", "captured", "fled", "wounded"]: d[fate][side] += 1
		if is_household(game, u):
			var rel := _relation(game, u)
			if rel in ["commander", "officer"]: rel = ("your " if side == 0 else "enemy ") + rel
			var row := {"name": u.name, "side": side, "fate": fate, "relation": rel}
			d["household"].append(row)
			var prev: Dictionary = st["household"].get(u.uid, {})
			if prev.is_empty() or int(FATE_RANK.get(fate, 0)) > int(FATE_RANK.get(str(prev.get("fate", "unhurt")), 0)):
				st["household"][u.uid] = row
	for side in 2:   # house arms experience: the side learns; skilled commoners who fell take theirs with them
		var mine: Array = units.filter(func(x): return (st["pool"][side] as Array).has(x))
		var dead_c: Array = mine.filter(func(x): return x.dead and not Army.house_born(x) and not DragonCombat.is_dragon_unit(game, x))
		ArmsPool.after_fight(game, ArmsPool.key_for_units(game, mine), mine.size(), w == side, dead_c)
	for side in 2:
		for k in ["dead", "wounded", "captured", "fled"]:
			st[k][side] = int(st[k][side]) + int(d[k][side])
	# Morale: the round's loser takes the blow; every man lost and every officer lost costs nerve.
	var change := [0.0, 0.0]
	for side in 2:
		var sent := maxf(1.0, float(d["fought"][side]))
		var lost := float(int(d["dead"][side]) + int(d["captured"][side]) + int(d["wounded"][side]))
		var share := lost / sent
		# Officers: the share of this unit's officers lost, and the commander himself, shake the whole army.
		var nerve := 15.0 * float(officers_lost[side]) / maxf(1.0, float(officers_in[side])) + (10.0 if captain_lost[side] else 0.0)
		if w == side:
			change[side] = 4.0 - 8.0 * share - nerve * 0.5
		elif w == 1 - side:
			change[side] = -8.0 - 20.0 * share - nerve - 0.05 * float(d["fled"][side])
		else:
			change[side] = -4.0 - 12.0 * share - nerve * 0.75
		st["morale"][side] = clampf(float(st["morale"][side]) + change[side], 0.0, 100.0)
	d["morale"] = (st["morale"] as Array).duplicate()
	d["morale_change"] = [roundi(change[0]), roundi(change[1])]
	var left := [fit(game, st["pool"][0], st["captives"][0]).size(), fit(game, st["pool"][1], st["captives"][1]).size()]
	d["fresh_left"] = left
	# Break: low morale, nobody left to send, or too many of its men lost.
	var broke := -1
	for side in 2:
		var gone := int(st["dead"][side]) + int(st["captured"][side])
		if left[side] == 0 or float(st["morale"][side]) < BREAK_MORALE or float(gone) > BREAK_LOSS * float(st["start"][side]):
			if broke == -1 or float(st["morale"][side]) < float(st["morale"][broke]): broke = side
	if broke == -1 and int(st["round"]) >= MAX_ROUNDS:
		broke = 0 if float(st["morale"][0]) < float(st["morale"][1]) else 1
	d["broke"] = broke
	st["broke"] = broke
	if broke >= 0:
		st["over"] = true
		st["winner"] = 1 - broke
		var raised := Ennoble.grant(game, int(st["winner"]), st["deeds"])   # a great deed: raised to the nobility
		if not raised.is_empty():
			st["household"][-1] = raised
			(d["household"] as Array).append(raised)
	(st["log"] as Array).append(d)
	return d

static func _relation(game, u: Unit) -> String:
	var st: Dictionary = game.pending_battle.get("rounds", {})
	var cmd := not st.is_empty() and (st.get("commander", []) as Array).has(u.uid)
	var p := _person(game, u)
	if p.is_empty() or str(Persons.g(p, Persons.HOUSE_UID, "")) != _household_uid(game): return "commander" if cmd else "officer"
	if str(Persons.g(p, Persons.PERSON_UID, "")) == str(game.world.get("player_house", {}).get("ruler_uid", "")): return "your ruler, commanding" if cmd else "your ruler"
	return "of your house, commanding" if cmd else "of your house"

## Prepares the next round (call before reloading the battle scene).
static func next_round(game) -> void:
	_pick_round(game)

## The battle summary (after the last round), for the battle panel.
static func battle_summary(game) -> Dictionary:
	var st: Dictionary = game.pending_battle["rounds"]
	var names: Array = (st["log"][-1] as Dictionary).get("names", ["Your army", "Enemy"]) if not (st["log"] as Array).is_empty() else ["Your army", "Enemy"]
	var left := [0, 0]
	for side in 2:
		left[side] = (st["pool"][side] as Array).filter(func(u): return u is Unit and not u.dead and not (st["captives"][side] as Array).has(u)).size()
	var loser := 1 - int(st["winner"]) if int(st["winner"]) >= 0 else -1
	var retreat := ""
	if loser == 0:
		retreat = "%s falls back to %s to remuster" % [names[0], _seat_name(game, "")]
	elif loser == 1:
		retreat = "%s fall back to %s to remuster" % [names[1], _seat_name(game, str(game.pending_battle.get("warband_id", "")))]
	return {"winner": int(st["winner"]), "rounds": int(st["round"]), "names": names, "start": (st["start"] as Array).duplicate(),
		"dead": (st["dead"] as Array).duplicate(), "wounded": (st["wounded"] as Array).duplicate(), "captured": (st["captured"] as Array).duplicate(),
		"fled": (st["fled"] as Array).duplicate(), "left": left, "household": (st["household"] as Dictionary).values(), "retreat": retreat,
		"kills": (st.get("deeds", {}).get("kills", {}) as Dictionary).values()}

static func _seat_name(game, wid: String) -> String:
	var w: Dictionary = game.world
	if wid == "":
		var tid := str(w.get("player_house", {}).get("town_id", ""))
		return str(w.get("towns", {}).get(tid, {}).get("name", "home"))
	var wb: Dictionary = w.get("warbands", {}).get(wid, {})
	return str(w.get("towns", {}).get(str(wb.get("home", "")), {}).get("name", "their home"))

## The single result Game.finish_battle settles: every man who fought in any round, the battle's winner, and
## the last round's journal and growth. Prisoners leave their side here.
static func final_result(game, last: Dictionary) -> Dictionary:
	var st: Dictionary = game.pending_battle["rounds"]
	var r := last.duplicate()
	r["winner"] = int(st["winner"])
	var p: Array = []; var en: Array = []; var fallen: Array = []; var fled: Array = []
	for u in st["fought"].keys():
		if (st["pool"][0] as Array).has(u): p.append(u)
		else:
			en.append(u)
			if u.dead: fallen.append(u)
	r["player_units"] = p
	r["enemy_units"] = en.filter(func(u): return not (st["captives"][1] as Array).has(u))
	r["enemy_fallen"] = fallen
	r["enemy_fled"] = fled
	r["player_fled"] = []
	r["rounds"] = (st["log"] as Array).duplicate()
	r["battle_summary"] = battle_summary(game)
	_take_prisoners(game, st)
	return r

## Captives change hands: the player's taken men leave the company; the enemy's taken men leave their band.
static func _take_prisoners(game, st: Dictionary) -> void:
	var w: Dictionary = game.world
	if not w.has("prisoners"): w["prisoners"] = []
	if not w.has("captives"): w["captives"] = []
	var enemy_faction := ""
	var wb: Dictionary = w.get("warbands", {}).get(str(game.pending_battle.get("warband_id", "")), {})
	if not wb.is_empty(): enemy_faction = str(wb.get("faction", ""))
	for u in st["captives"][0]:
		if u.dead: continue
		(w["captives"] as Array).append({"uid": u.uid, "name": u.name, "home_town": u.home_town, "family": u.family,
			"held_by": enemy_faction, "day": float(game.day), "household": is_household(game, u)})
		game.company.erase(u)
		game.squads.erase(u.uid)
		_note_captured(game, u, enemy_faction)
	for u in st["captives"][1]:
		if u.dead: continue
		(w["prisoners"] as Array).append({"uid": u.uid, "name": u.name, "faction": u.faction, "home_town": u.home_town,
			"family": u.family, "day": float(game.day), "noble": is_household(game, u)})
		if not wb.is_empty(): (wb["units"] as Array).erase(u)
	game.invalidate_deploy()

## The family keeps the memory: the person is held, not dead; their register row says so.
static func _note_captured(game, u: Unit, held_by: String) -> void:
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	var f: Dictionary = People.fam_of(town, u.family) if not town.is_empty() else {}
	if f.is_empty(): return
	var p := Persons.by_uid(f, u.uid)
	var who := str(DB.factions.get(held_by, {}).get("name", "the enemy"))
	Families.add_hist(f, "%s was taken prisoner by %s." % [u.name, who], float(game.day))
	if not p.is_empty():
		p[4] = "captive"
		Persons.log_life(p, float(game.day), "captured", held_by)

## A beaten army goes home at once: everyone not dead or taken appears at its owner's seat as a regrouping force
## that must remuster before it can march. Player: survivors return to their homes as reserves (raise them again
## in Muster) and the party stands at the house seat. AI band: it is moved to its home town and rests.
static func retreat_player(game) -> void:
	var w: Dictionary = game.world
	for u in game.company.duplicate():
		if not u.dead and not DragonCombat.is_dragon_unit(game, u):
			Mobilization.return_home(game, u)
	var tid := str(w.get("player_house", {}).get("town_id", ""))
	var town: Dictionary = w.get("towns", {}).get(tid, {})
	if not town.is_empty():
		w["party"]["pos"] = town["pos"]
		w["party"]["path"] = []
		w["party"]["safe_until"] = float(game.day) + REMUSTER_DAYS
		CampaignWorld.log_event(game, "Your beaten army fell back to %s to remuster." % str(town.get("name", tid)))

static func retreat_band(game, wb: Dictionary) -> bool:
	var w: Dictionary = game.world
	wb["units"] = (wb["units"] as Array).filter(func(u): return not u.dead)
	if (wb["units"] as Array).is_empty(): return false
	var home: Dictionary = w.get("towns", {}).get(str(wb.get("home", "")), {})
	if home.is_empty() or str(home.get("faction", "")) != str(wb.get("faction", "")):
		var hid := CampaignWorld.nearest_faction_town(w, str(wb["faction"]), wb["pos"])
		home = w.get("towns", {}).get(hid, {})
		if home.is_empty(): return false
		wb["home"] = hid
	wb["pos"] = home["pos"]
	WarAI.clear(wb)
	wb["path"] = []
	wb["rest_until"] = float(game.day) + REMUSTER_DAYS
	wb["regroup_until"] = float(game.day) + REMUSTER_DAYS
	return true
