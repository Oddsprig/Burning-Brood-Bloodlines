class_name Monsters
extends RefCounted
## Monsters wave 1 on the campaign map: creature lairs and packs, gradual unlocks, militia and outlaws glue.
## CampaignWorld (world.gd) calls these hooks (each a one-line, commented call there):
##   generate(game, rng)              initial lairs + residents, bandit camps, militia
##   on_time(game, days)              cheap per-call checks: militia auto-fights (every MILITIA_CHECK days), lair sighting
##   daily(game, day, rng)            queues work jobs (new lairs/camps, lair restock, militia rebuild, bandit bands,
##                                    deserters), unlock bookkeeping, bounty growth
##   do_work(game, job, rng)          one heavy job per map frame (job[0] in WORK_JOBS)
##   step_band(game, wid, wb, dt, t, rng) -> bool   movement for militia / beasts / den / camp bands
##   band_hostile(game, wb), battle_extras(game, wb, params), on_battle_result(game, wid, wb, result) -> bool
##   after_load(game)
## Kinds of warband added: "beasts" (a creature pack roaming near its lair, or near the village it plagues),
## "den" (a big creature that stays in its lair), "camp" (a bandit camp's garrison), "bandit" (a band from a camp),
## "deserter" (keeps its town and faction, flagged deserter), "militia" (a town's own militia).
## Every non-monster force has a home (town, or for bandits their camp) and a faction; monsters belong to a lair or none.

const WORK_JOBS := ["lair", "camp", "lair_fill", "militia", "bandits", "deserters"]
const MONSTER_KINDS := ["beasts", "den"]
const NO_CLASH := ["militia", "beasts", "den", "camp"]   # resolved by Militia.tick, not CampaignWorld._warband_clashes
const PACK_SPEED := 0.75     # x WARBAND_SPEED while roaming
const SIGHT_LAIR := 300.0    # px: lairs the company passes this close become known
## Temporary v0.002 campaign suspension. Creature data/body combat remains available for later milestones.
const CAMPAIGN_CREATURES_ENABLED := false

static func campaign_creatures_enabled() -> bool:
	return CAMPAIGN_CREATURES_ENABLED

static func creature_units(units: Array) -> bool:
	var checked := {}
	for u in units:
		if not u is Unit: continue
		# Each race definition is identical for all members of this call. No
		# persistent cache: mixed/replaced/transformed units are still observed.
		var race: String = u.race
		if checked.has(race): continue
		checked[race] = true
		if u.race_def().get("creature", false): return true
	return false

## Creature check per band, reused for up to 30 frames while the roster size holds (a 1000-man army was
## rescanned several times every frame); any roster change or half a second rechecks the actual units.
static var _creature_seen: Dictionary = {}
static func suspended_band(wb: Dictionary) -> bool:
	if campaign_creatures_enabled(): return false
	if is_monster_band(wb) or is_monster_faction(String(wb.get("faction", ""))): return true
	var units: Array = wb.get("units", [])
	if units.size() < 64: return creature_units(units)
	var key := str(wb.get("id", ""))
	var now := Engine.get_process_frames()
	var c: Array = _creature_seen.get(key, [])
	if c.size() == 3 and int(c[1]) == units.size() and now - int(c[0]) < 30 and now >= int(c[0]):
		return bool(c[2])
	var res := creature_units(units)
	if _creature_seen.size() > 512: _creature_seen.clear()
	_creature_seen[key] = [now, units.size(), res]
	return res

static func suspended_lair(lair: Dictionary) -> bool:
	return not campaign_creatures_enabled() and not lair.is_empty() and lair.get("kind", "") != "bandit_camp"

static func suspended_contract(contract: Dictionary, world: Dictionary) -> bool:
	if campaign_creatures_enabled() or contract.is_empty(): return false
	return contract.get("kind", "") == "hunt" or is_monster_faction(String(contract.get("target_faction", ""))) or \
		suspended_band(world.get("warbands", {}).get(String(contract.get("target_id", "")), {})) or \
		suspended_lair(world.get("lairs", {}).get(String(contract.get("lair_id", "")), {}))

static func is_monster_band(wb: Dictionary) -> bool:
	return wb.get("kind", "") in MONSTER_KINDS

static func is_monster_faction(fid: String) -> bool:
	return bool(DB.factions.get(fid, {}).get("monster", false))

static func state(w: Dictionary) -> Dictionary:
	if not w.has("monsters"):
		w["monsters"] = {"fights": 0, "unlocked": {}, "militia_next": 0.05}   # off the day boundary (daily work runs there)
	return w["monsters"]

# ================================================================== unlocks and spawn weights
## Creature types unlocked now: unlock.day and unlock.fights (x unlock_pace) reached. Records the unlock day.
static func available(w: Dictionary, day: float) -> Array:
	if not campaign_creatures_enabled(): return []
	var st := state(w)
	var pace := float(Creatures.tun("unlock_pace", 1.0))
	var out := []
	for cid in Creatures.ids():
		var u: Dictionary = Creatures.def(cid).get("unlock", {})
		if day >= float(u.get("day", 0)) * pace and int(st["fights"]) >= int(round(float(u.get("fights", 0)) * pace)):
			if not st["unlocked"].has(cid):
				st["unlocked"][cid] = day
			out.append(cid)
	return out

## Spawn weight: rarity weight, but a newly unlocked type starts at "rare" and ramps up over ramp_days.
static func weight(w: Dictionary, cid: String, day: float) -> float:
	var full := float(Creatures.rarity_info(Creatures.rarity(cid)).get("weight", 1))
	var rare := minf(full, float(Creatures.rarity_info("rare").get("weight", 10)))
	var since := day - float(state(w)["unlocked"].get(cid, day))
	var ramp := maxf(0.01, float(Creatures.tun("ramp_days", 20.0)))
	return lerpf(rare, full, clampf(since / ramp, 0.0, 1.0))

static func pick_creature(w: Dictionary, day: float, rng: RandomNumberGenerator, roaming_only: bool = false) -> String:
	var ids := available(w, day)
	if roaming_only:
		ids = ids.filter(func(c): return int(Creatures.def(c).get("roam", 0)) > 0)
	if ids.is_empty():
		return ""
	var ws := []
	for cid in ids:
		ws.append(weight(w, cid, day))
	return ids[Formulas.roll_weighted(rng, "spawn", ws, ids)["i"]]

# ================================================================== generation
static func generate(game, rng: RandomNumberGenerator) -> void:
	var run := generate_begin(game, rng)
	while not generate_part(game, run):
		pass

## Caller-local generation state: each original lair, camp and town is completed
## in the same order before the next one starts. Nothing partial is saved.
static func generate_begin(game, rng: RandomNumberGenerator) -> Dictionary:
	var w: Dictionary = game.world
	w["lairs"] = {}
	w["militia"] = {}
	state(w)
	var wild := Lairs.wild_count(w)
	return {"rng": rng, "phase": "lairs", "i": 0,
		"lairs": int(ceil(Lairs.target_lairs(wild) * 0.5)) if campaign_creatures_enabled() else 0, "camps": Lairs.target_camps(wild)}

static func generate_part(game, run: Dictionary) -> bool:
	var rng: RandomNumberGenerator = run["rng"]
	var i: int = run["i"]
	match String(run["phase"]):
		"lairs":
			# The wilds start half-settled, exactly as synchronous generation.
			if i < int(run["lairs"]):
				new_lair(game, rng)
				run["i"] = i + 1
			else:
				run["phase"] = "camps"; run["i"] = 0
		"camps":
			if i < int(run["camps"]):
				Bandits.new_camp(game, rng)
				run["i"] = i + 1
			else:
				run["phase"] = "militia"; run["i"] = 0
				var ids: Array = game.world["towns"].keys()
				ids.sort()   # Militia.ensure_all's original order
				run["towns"] = ids
		"militia":
			var ids: Array = run["towns"]
			if i < ids.size():
				Militia.ensure(game, String(ids[i]), rng)
				run["i"] = i + 1
			return int(run["i"]) >= ids.size()
	return false

## A new creature lair with its residents. Returns the lair id or "".
static func new_lair(game, rng: RandomNumberGenerator) -> String:
	if not campaign_creatures_enabled(): return ""
	var w: Dictionary = game.world
	var cid := pick_creature(w, float(game.day), rng)
	if cid == "":
		return ""
	var lid := Lairs.place(game, String(Creatures.def(cid).get("lair", "wolf_den")), rng)
	if lid == "":
		return ""
	fill_lair(game, lid, rng)
	return lid

## Residents for an empty creature lair (a pack, or one big beast that stays in its den). Some get a named leader:
## a bounty target whose price grows the longer it lives.
static func fill_lair(game, lid: String, rng: RandomNumberGenerator) -> String:
	if not campaign_creatures_enabled(): return ""
	var w: Dictionary = game.world
	var l: Dictionary = w["lairs"].get(lid, {})
	if l.is_empty() or l["kind"] == "bandit_camp" or w["warbands"].has(String(l.get("resident", ""))):
		return ""
	var cid: String = l["creature"]
	var units := Creatures.make_group(rng, cid)
	var named := ""
	if rng.randf() < float(Creatures.tun("named_chance", 0.25)):
		var boss := Creatures.make_named(rng, cid)
		units[0] = boss
		named = boss.name
	var roam := int(Creatures.def(cid).get("roam", 0))
	var wid := CampaignWorld.spawn_warband(game, "beasts", l["pos"], units.size(), "beasts" if roam > 0 else "den", rng,
		{"units": units, "home": lid, "lair": lid, "creature": cid, "anchor": l["pos"], "roam": float(roam),
		"named": named, "since": float(game.day)})
	l["resident"] = wid
	return wid

## A pack plaguing a village (hunt contracts): roams around the village, belongs to no lair.
static func spawn_plague(game, town: Dictionary, cid: String, rng: RandomNumberGenerator) -> String:
	if not campaign_creatures_enabled(): return ""
	var w: Dictionary = game.world
	var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
	var pos: Vector2 = town["pos"] + dir * rng.randf_range(160.0, 260.0)
	var units := Creatures.make_group(rng, cid)
	return CampaignWorld.spawn_warband(game, "beasts", pos, units.size(), "beasts", rng,
		{"units": units, "home": "", "lair": "", "creature": cid, "anchor": town["pos"], "roam": 200.0, "named": "",
		"since": float(game.day), "plague": town["id"]})

# ================================================================== time
static func on_time(game, _days: float) -> void:
	var w: Dictionary = game.world
	if not w.has("lairs"):
		return
	var st := state(w)
	if float(game.day) >= float(st.get("militia_next", 0.0)):
		st["militia_next"] = (floor(float(game.day) / Militia.CHECK_DAYS) + 1.5) * Militia.CHECK_DAYS   # mid-grid: never on a day boundary
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([int(w.get("seed", 0)), int(game.day * 100.0)])
		var started := Time.get_ticks_usec()
		Militia.tick(game, rng)
		Perf.record_us("Militia threat check", Time.get_ticks_usec() - started)
	var pp: Vector2 = w["party"]["pos"]
	for lid in w["lairs"]:
		var l: Dictionary = w["lairs"][lid]
		if suspended_lair(l): continue
		if not l["known"] and (l["pos"] as Vector2).distance_squared_to(pp) < SIGHT_LAIR * SIGHT_LAIR:
			l["known"] = true
			CampaignWorld.log_event(game, "Scouts found a %s." % Lairs.near_text(w, l))

static func daily(game, d: int, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	if not w.has("lairs"):
		return
	if not w.has("work"):
		w["work"] = []
	var work: Array = w["work"]
	# the monster jobs already queued, read once (world size: work.has per lair and town scanned the whole queue)
	var queued := {}
	for j in work:
		if String(j[0]) in WORK_JOBS:
			queued[j] = true
	available(w, float(d))
	var wild := Lairs.wild_count(w)
	var every := maxi(1, int(Creatures.tun("respawn_check_days", 2.0)))
	if d % every == 0:
		if campaign_creatures_enabled() and Lairs.count(w, false) < Lairs.target_lairs(wild) and not queued.has(["lair"]):
			work.append(["lair"])
		if Lairs.count(w, true) < Lairs.target_camps(wild) and not queued.has(["camp"]):
			work.append(["camp"])
	for lid in w["lairs"]:
		var l: Dictionary = w["lairs"][lid]
		if suspended_lair(l): continue
		if l["kind"] == "bandit_camp":
			if Bandits.wants_band(game, lid) and not queued.has(["bandits", lid]):
				work.append(["bandits", lid])
		elif not w["warbands"].has(String(l["resident"])) and float(d) >= float(l["cleared_until"]):
			if not queued.has(["lair_fill", lid]):
				work.append(["lair_fill", lid])
	for tid in w["towns"]:
		if Militia.wants_recruit(game, tid, d) and not queued.has(["militia", tid]):
			work.append(["militia", tid])
	if Bandits.wants_deserters(game, rng) and not queued.has(["deserters"]):
		work.append(["deserters"])
	Bandits.daily(game)
	MonsterContracts.daily(game)

static func do_work(game, job: Array, rng: RandomNumberGenerator) -> bool:
	if not campaign_creatures_enabled() and String(job[0]) in ["lair", "lair_fill"]:
		return true   # Consume suspended work without spawning, restocking or rolling randomness.
	match String(job[0]):
		"lair":
			new_lair(game, rng)
		"camp":
			Bandits.new_camp(game, rng)
		"lair_fill":
			fill_lair(game, String(job[1]), rng)
		"militia":
			Militia.recruit(game, String(job[1]), rng)
		"bandits":
			Bandits.spawn_band(game, String(job[1]), rng)
		"deserters":
			Bandits.spawn_deserters(game, rng)
		_:
			return false
	return true

# ================================================================== movement
## Movement for the new static-ish kinds. Returns true when handled (CampaignWorld skips its own logic).
static func step_band(game, wid: String, wb: Dictionary, dt: float, t: float, rng: RandomNumberGenerator, suspension_checked: bool = false) -> bool:
	# Campaign movement has just checked this exact, unchanged roster. Other
	# callers retain the native suspension guard; no cache survives the call.
	if not suspension_checked and suspended_band(wb): return true
	if wb.has("raid"): return HerdRaids.step(game, wb, dt, t, rng)
	match String(wb.get("kind", "")):
		"den", "camp":
			return true   # big beasts and camp garrisons stay put
		"militia":
			Militia.step(game, wb, dt, t, rng)
			return true
		"beasts":
			_roam(game, wb, dt, t, rng)
			return true
	return false

static func _roam(game, wb: Dictionary, dt: float, t: float, rng: RandomNumberGenerator) -> void:
	if suspended_band(wb): return
	var w: Dictionary = game.world
	if (wb["path"] as Array).is_empty():
		if float(wb["idle_until"]) > t:
			return
		var r := float(wb.get("roam", 150.0))
		var goal: Vector2 = wb["anchor"] + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
		wb["path"] = CampaignWorld.find_path(w, wb["pos"], goal)
		if (wb["path"] as Array).is_empty():
			wb["idle_until"] = t + 0.5
			return
	if CampaignWorld._step_along(w, wb, CampaignWorld.WARBAND_SPEED * PACK_SPEED * CampaignWorld.smooth_speed(w, wb, dt) * dt):
		wb["idle_until"] = t + rng.randf_range(0.3, 1.2)

# ================================================================== disposition, scouting
## Hostile to the company: a wild faction (beasts, outlaws: always), a deserter band (hostile to everyone), or a
## faction diplomacy says is hostile to the company.
static func band_hostile(game, wb: Dictionary) -> bool:
	if suspended_band(wb): return false
	return is_wild_faction(wb["faction"]) or bool(wb.get("deserter", false)) or CampaignWorld.is_hostile(game, wb["faction"])

## Wild factions (data/creatures.json, wild: true) stand outside diplomacy: hostile to everyone.
static func is_wild_faction(fid: String) -> bool:
	return bool(DB.factions.get(fid, {}).get("wild", false))

## Fights on contact beyond diplomacy's WAR/HOSTILE rule: outlaws against any other faction, deserters against
## their old faction (CampaignWorld._warband_clashes).
static func extra_fight(a: Dictionary, b: Dictionary) -> bool:
	if suspended_band(a) or suspended_band(b): return false
	if a["faction"] != b["faction"]:
		return is_wild_faction(a["faction"]) or is_wild_faction(b["faction"])
	return bool(a.get("deserter", false)) != bool(b.get("deserter", false))

static func kind_text(wb: Dictionary) -> String:
	match String(wb.get("kind", "")):
		"beasts", "den":
			var cid := String(wb.get("creature", ""))
			var n := (wb["units"] as Array).size()
			var d := Creatures.def(cid)
			if String(wb.get("named", "")) != "":
				return "%s, a great %s" % [wb["named"], d.get("name", cid)]
			if n <= 1:
				return String(d.get("name", cid))
			return {"wolf": "wolf pack", "boar": "sounder of wild boar", "bear": "pair of bears"}.get(cid, "pack of %s" % d.get("plural", cid))
		"camp":
			return "bandit camp"
		"bandit":
			return "bandit gang"
		"deserter":
			return "band of deserters"
		"militia":
			return "town militia"
	return ""

static func home_text(w: Dictionary, wb: Dictionary) -> String:
	var l: Dictionary = w.get("lairs", {}).get(String(wb.get("home", "")), {})
	if not l.is_empty():
		return "from the %s" % Lairs.near_text(w, l)
	if is_monster_band(wb):
		return "roaming near %s" % CampaignWorld.nearest_town_name(w, wb["pos"])
	return ""

# ================================================================== battles
## Extra battle parameters: militia allies on a defend contract, lair terrain with choke points.
static func battle_extras(game, wb: Dictionary, params: Dictionary) -> void:
	if suspended_band(wb): return
	var w: Dictionary = game.world
	var c: Dictionary = game.contract
	if c.get("kind", "") == "defend" and c.get("target_id", "") == wb["id"]:
		var tid := String(c.get("town_id", ""))
		var town: Dictionary = w["towns"].get(tid, {})
		var mil: Array = [] if TownDefence.defence_policy(game, town) == "stand_down" else Militia.units_of(game, tid)
		if not mil.is_empty():
			TownDefence.set_muster(game, town, true)
			var allies: Array = params.get("allies", []).duplicate()
			allies.append_array(mil)
			params["allies"] = allies
			params["militia_town"] = c["town_id"]
			params["militia_start"] = mil.size()
			# economy: the militia eats from its own town (food spec: "Militia: their town's supply level")
			params["ally_supply"] = TownEcon.supply_level(w["towns"].get(String(c["town_id"]), {}))
	var lid := String(wb.get("lair", ""))
	if lid != "" and w["lairs"].has(lid):
		var l: Dictionary = w["lairs"][lid]
		# fought at the lair: dens and camps always; a pack when the contract is to clear its lair or it is caught at home
		var at_lair: bool = wb["kind"] in ["den", "camp"] or (c.get("kind", "") == "lair" and c.get("target_id", "") == wb["id"]) \
			or (w["party"]["pos"] as Vector2).distance_to(l["pos"]) < 100.0
		if not at_lair:
			return
		var n: int = (params["enemy"] as Array).size() + (params.get("allies", []) as Array).size() + game.deployed_units().size()
		var grid := Vector2i(32, 18) if n <= 40 else Vector2i(64, 36)
		params["tiles"] = Lairs.battle_tiles(l["kind"], grid, int(hash([w.get("seed", 0), lid])))
		params["terrain"] = CampaignWorld.terrain_at(w, l["pos"])
		params["lair_id"] = lid

## After a company battle against warband wid. Returns true when it fully handled a victory (CampaignWorld then
## skips its generic win path). Trophies, lair clearing, camp loot, deserters, militia losses and pay bonus.
static func on_battle_result(game, wid: String, wb: Dictionary, result: Dictionary) -> bool:
	if suspended_band(wb): return true
	var w: Dictionary = game.world
	var won := int(result.get("winner", -1)) == 0
	var pb: Dictionary = game.pending_battle
	# militia that fought beside the company: the fallen are gone; fewer deaths, bigger bonus
	var mt := String(pb.get("militia_town", ""))
	if mt != "":
		var lost := Militia.bury_dead(game, mt)
		var start := maxi(1, int(pb.get("militia_start", 1)))
		if won and game.contract.get("target_id", "") == wid:
			var bonus := int(round(float(game.contract.get("pay", 0)) * Militia.PAY_BONUS * float(start - lost) / start / 5.0)) * 5
			if bonus > 0:
				game.contract["pay"] = int(game.contract["pay"]) + bonus
				result["militia_bonus"] = bonus
				CampaignWorld.log_event(game, "%s's militia lost %d of %d; the town adds %d coins for sparing them." % [
					w["towns"][mt]["name"], lost, start, bonus])
	if not won:
		return false
	var kind := String(wb.get("kind", ""))
	if is_monster_band(wb):
		var tro := Creatures.trophies(wb["units"])
		var g := 0
		for x in tro:
			g += int(x["gold"])
		# coinage: the trophies are sold at the nearest town's market, which pays what its till holds
		var tt: Dictionary = w["towns"].get(CampaignWorld.nearest_town(w, wb["pos"]), {})
		if TownEcon.has_econ(tt):
			g = mini(g, int(Goods.market_gold(tt)))
			Goods.pay_market(tt, -float(g))
		game.gold += g
		result["trophies"] = tro
		result["trophy_gold"] = g
		state(w)["fights"] = int(state(w)["fights"]) + 1
		_clear_lair_of(game, wb)
		var what := kind_text(wb)
		CampaignWorld.remove_warband(game, wid)
		CampaignWorld.log_event(game, "The company killed the %s near %s%s." % [what, CampaignWorld.nearest_town_name(w, wb["pos"]),
			(" (trophies sold for %d coins)" % g) if g > 0 else ""])
		_complete_if_target(game, wid, wb)
		return true
	if kind == "camp":
		var loot := Bandits.clear_camp(game, String(wb.get("lair", "")), result)
		CampaignWorld.remove_warband(game, wid)
		CampaignWorld.log_event(game, "The company stormed the bandit camp near %s%s." % [CampaignWorld.nearest_town_name(w, wb["pos"]),
			(" and sold its hoard for %d coins" % loot) if loot > 0 else ""])
		_complete_if_target(game, wid, wb)
		return true
	if kind == "bandit" or kind == "deserter":
		CampaignWorld.remove_warband(game, wid)
		if kind == "deserter":
			CampaignWorld.change_rep(game, wb["faction"], 3)   # their old lords are glad of it
		CampaignWorld.log_event(game, "The company destroyed a %s near %s." % [kind_text(wb), CampaignWorld.nearest_town_name(w, wb["pos"])])
		_complete_if_target(game, wid, wb)
		return true
	return false

static func _complete_if_target(game, wid: String, wb: Dictionary) -> void:
	if game.contract.get("target_id", "") != wid or game.contract.get("state", "") != "active":
		return
	MonsterContracts.before_complete(game, wb)
	Contracts.complete(game)

static func _clear_lair_of(game, wb: Dictionary) -> void:
	var w: Dictionary = game.world
	var l: Dictionary = w.get("lairs", {}).get(String(wb.get("lair", "")), {})
	if l.is_empty():
		return
	l["resident"] = ""
	l["known"] = true
	l["cleared_until"] = float(game.day) + float(Creatures.tun("cleared_days", 15.0))

## A band was destroyed off-screen (militia): free its lair.
static func band_destroyed(game, wb: Dictionary) -> void:
	if suspended_band(wb): return
	if is_monster_band(wb):
		_clear_lair_of(game, wb)
	elif wb.get("kind", "") == "camp":
		Bandits.clear_camp(game, String(wb.get("lair", "")), {})

# ================================================================== load fix-up
static func after_load(game) -> void:
	var w: Dictionary = game.world
	if not w.has("lairs"):
		# saves from before monsters wave 1: settle the wilds now
		var rng := RandomNumberGenerator.new()
		rng.seed = int(w.get("seed", 1)) + 4242
		generate(game, rng)
		return
	var st := state(w)
	st["fights"] = int(st.get("fights", 0))
	for lid in w["lairs"]:
		var l: Dictionary = w["lairs"][lid]
		if l.has("gold"):
			l["gold"] = int(l["gold"])
