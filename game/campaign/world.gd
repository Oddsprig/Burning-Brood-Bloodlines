class_name CampaignWorld
extends RefCounted
## Strategy layer: owns Game.world. Generation, time passing (party travel, warband AI, faction
## clashes, daily spawns, town refresh, contract deadlines), encounters and battle results.
##
## Hooks called by core/game.gd: generate(game, rng), on_battle_result(game, result),
## on_time(game, days, in_town) (from advance_time), after_load(game) (from load_game).
## The map screen drives time with Game.advance_time(days, false) while the party travels.

const MAP_PACE := 0.65         # v0.031: all forces travel 35% slower
const PARTY_SPEED := 200.0 * MAP_PACE   # world px per day on grassland, before army size
const WARBAND_SPEED := 175.0 * MAP_PACE
const STEP := 0.05             # simulation sub-step in days
const CONTACT := 22.0          # px: contact radius party <-> warband
const PARTY_SIGHT := 380.0     # px: warbands visible to the player
const WARBAND_SIGHT := 300.0   # px: hostile warbands notice the party
const HOSTILE_REP := -50          # diplomacy: standing <= this = hostile (Diplomacy.HOSTILE_STANDING)
const HOSTILE_REP_LEGACY := -30   # old Game.rep threshold, still used for factions outside diplomacy
const PLAYER_COLOR := "#e0a526"

## Legacy fixed war list (pre-diplomacy). campaign/diplomacy.gd now decides wars; this list only applies to
## factions outside data/diplomacy.json. w["wars"] mirrors the current WAR pairs.
const WARS := [["middle_kingdom", "orc_horde"], ["middle_kingdom", "goblin_warren"], ["northern_clans", "orc_horde"],
	["moon_court", "goblin_warren"], ["orc_horde", "goblin_warren"]]
## v0.012 [ours]: the Eastern khanate patrols like the North; the dwarves keep 1 patrol per area unit (few holds, a
## small people) in small bands.
const PATROLS := {"middle_kingdom": 3, "northern_clans": 2, "moon_court": 2, "orc_horde": 3, "goblin_warren": 3,
	"eastern_khanate": 2, "dwarf_holds": 1}
const BAND_SIZE := {"normal": 100, "large": 150, "huge": 200}
const FIELD_LIMIT := 1000
const FIELD_WEEKLY_GROWTH := 50

static var job_worst := {}   # diagnostics: work job kind -> worst single run in microseconds (never saved)
static var steps_worst := 0   # diagnostics: worst movement + clashes + war AI of one on_time call (microseconds)
static var daily_worst := 0   # diagnostics: worst midnight bookkeeping (_daily) in microseconds
static var daily_parts := {}   # diagnostics: part of _daily -> worst microseconds
static var path_worst := 0   # diagnostics: worst find_path (microseconds)
static var job_total := {}   # diagnostics: work job kind -> [total microseconds, runs] (never saved)
static var steps_total := 0   # diagnostics: total movement + clashes + war AI (microseconds)
static var step_parts := {}   # diagnostics: war_ai / move / clashes / tracks -> total microseconds
static var daily_total := {}   # diagnostics: part of _daily -> total microseconds
static var _astar: AStarGrid2D = null
static var _astar_terrain: String = ""
static var _astar_seed := 0

# ================================================================== generation (campaign/world_presim.gd)
static var generation_parts_total_usec := 0   # diagnostics only; never saved
static var generation_part_worst_usec := 0
static var generation_part_count := 0
const GENERATION_STAGES := ["Land and sea", "Towns and holds", "Roads", "Realms and road links",
	"Town households and markets", "Company arrival", "Realm patrols", "Lairs, camps and militia",
	"Company families", "Army rolls and ranks", "Armories", "Research houses", "Coin ledger",
	"Town plots and initial jobs", "Opening census", "World complete"]

static func generate(game, rng: RandomNumberGenerator) -> void: WorldPresim.generate(game, rng)
static func generate_begin(game, rng: RandomNumberGenerator) -> Dictionary: return WorldPresim.generate_begin(game, rng)
static func generate_part(game, run: Dictionary) -> bool: return WorldPresim.generate_part(game, run)
static func _generate_part(game, run: Dictionary) -> bool: return WorldPresim._generate_part(game, run)
static func generate_slice(game, state: Dictionary, budget_usec: int) -> bool: return WorldPresim.generate_slice(game, state, budget_usec)
static func generation_stage_name(state: Dictionary) -> String: return WorldPresim.generation_stage_name(state)
static func generation_progress(state: Dictionary) -> float: return WorldPresim.generation_progress(state)
static func _generate_realms(game) -> void: WorldPresim._generate_realms(game)
static func _generate_town(game, tid: String, seed_v: int, grng: RandomNumberGenerator) -> void: WorldPresim._generate_town(game, tid, seed_v, grng)
static func _generate_party(game) -> void: WorldPresim._generate_party(game)

# ================================================================== small helpers
static func new_id(w: Dictionary, prefix: String) -> String:
	var n := int(w.get("next_id", 1))
	w["next_id"] = n + 1
	return "%s%d" % [prefix, n]

static func log_event(game, text: String) -> void:
	var lg: Array = game.world.get("log", [])
	lg.append("Day %d: %s" % [int(game.day) + 1, text])
	while lg.size() > 30:
		lg.pop_front()
	game.world["log"] = lg

static func _rng(w: Dictionary) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = int(w.get("seed", 1)) + 99
	var st: String = str(w.get("rng_state", ""))
	if st != "" and st.is_valid_int():
		r.state = st.to_int()
	return r

static func faction_name(fid: String) -> String:
	return DB.factions.get(fid, {}).get("name", fid)

## "the Warrens of Skrag", "the Kingdom of the Middle March" (for running text).
static func faction_the(fid: String) -> String:
	var n := faction_name(fid)
	if n.begins_with("The "):
		n = n.substr(4)
	return "the " + n

static func faction_color(fid: String) -> Color:
	if fid == "player":
		return Color(PLAYER_COLOR)
	return Color(DB.factions.get(fid, {}).get("colors", {}).get("primary", "#888888"))

# Thin wrappers onto campaign/diplomacy.gd (kept for older callers).
## Factions at WAR with fid.
static func enemies_of(w: Dictionary, fid: String) -> Array:
	return Diplomacy.enemies_at_war(w, fid)

static func at_war(w: Dictionary, a: String, b: String) -> bool:
	return Diplomacy.at_war(w, a, b)

## The company's standing with fid is hostile (<= -50): gates barred, their armies attack on sight.
static func is_hostile(game, fid: String) -> bool:
	return Diplomacy.player_hostile(game, fid)

## Earned standing change with a reason for the relations screen (Game.rep mirrors the standing).
static func change_rep(game, fid: String, delta: int, why: String = "") -> void:
	if not DB.factions.has(fid):
		return
	Diplomacy.add_earned(game, fid, delta, why)

static func desired_bands(w: Dictionary, fid: String) -> int:
	var st := float(w["factions"].get(fid, {}).get("strength", 1.0))
	if w["factions"].get(fid, {}).get("towns", []).is_empty():
		return 0
	return int(round(PATROLS.get(fid, 2) * WorldGen.tf_of(w) * st))   # world size: patrols per area of the realm

# ================================================================== terrain queries
static func terrain_char_at(w: Dictionary, pos: Vector2) -> String:
	var c := WorldGen.cell_of(pos)
	return (w["terrain"] as String)[WorldGen.idx(c.x, c.y)]

## Terrain name for battle maps: grassland, forest, hills, mountains, water, badlands, silverwood.
static func terrain_at(w: Dictionary, pos: Vector2) -> String:
	return WorldGen.TERRAIN_NAMES.get(terrain_char_at(w, pos), "grassland")

static func region_at(w: Dictionary, pos: Vector2) -> String:
	var c := WorldGen.cell_of(pos)
	return WorldGen.REGIONS[int((w["region"] as String)[WorldGen.idx(c.x, c.y)])]

static func on_road(w: Dictionary, pos: Vector2) -> bool:
	var c := WorldGen.cell_of(pos)
	return (w["road"] as String)[WorldGen.idx(c.x, c.y)] == "1"

static func speed_mult(w: Dictionary, pos: Vector2) -> float:
	var c := WorldGen.cell_of(pos)
	var idx := WorldGen.idx(c.x, c.y)
	var s: float = WorldGen.TERRAIN_SPEED.get((w["terrain"] as String)[idx], 1.0)
	if s <= 0.0:
		s = 0.5   # standing on a coast/impassable edge: let them walk off it
	if (w["road"] as String)[idx] == "1":
		s *= WorldGen.ROAD_SPEED
	return s

## Terrain/road speed eased over ~an hour of game time, so movers glide between ground types instead of
## jumping speed at every cell edge (Douglas: army movement was jittery).
static func smooth_speed(w: Dictionary, mover: Dictionary, dt: float) -> float:
	var target := speed_mult(w, mover["pos"])
	var cur: float = mover.get("spd", target)
	cur += (target - cur) * minf(1.0, dt / 0.04)
	mover["spd"] = cur
	return cur

static func passable(w: Dictionary, pos: Vector2) -> bool:
	if pos.x < 0 or pos.y < 0 or pos.x >= WorldGen.W * WorldGen.CELL or pos.y >= WorldGen.H * WorldGen.CELL:
		return false
	return WorldGen.passable_char(terrain_char_at(w, pos))

static func astar(w: Dictionary) -> AStarGrid2D:
	# Strings share their backing storage; comparing the unchanged terrain avoids hashing the entire map for
	# each path/line query. Keep content equality so replacing terrain still invalidates the cached grid.
	var terrain: String = w["terrain"]
	var seed_v := int(w.get("seed", 0))
	if _astar == null or _astar_seed != seed_v or _astar_terrain != terrain:
		_astar = WorldGen.make_astar(w, false)
		_astar_seed = seed_v
		_astar_terrain = terrain
	return _astar

## Nearest passable point (cell centre) to pos, searching outward on the grid.
static func nearest_passable(w: Dictionary, pos: Vector2) -> Vector2:
	if passable(w, pos):
		return pos
	var c := WorldGen.cell_of(pos)
	var a := astar(w)
	for r in range(1, 30):
		var best := Vector2.INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cc := c + Vector2i(dx, dy)
				if cc.x < 0 or cc.y < 0 or cc.x >= WorldGen.W or cc.y >= WorldGen.H:
					continue
				if not a.is_point_solid(cc):
					var p := WorldGen.cell_center(cc)
					if best == Vector2.INF or p.distance_to(pos) < best.distance_to(pos):
						best = p
		if best != Vector2.INF:
			return best
	return pos

## Path of world positions from a to b (both snapped to passable ground). Empty if unreachable.
static func find_path(w: Dictionary, from: Vector2, to: Vector2) -> Array:
	var f0 := Time.get_ticks_usec()
	var out := _find_path(w, from, to)
	path_worst = maxi(path_worst, Time.get_ticks_usec() - f0)
	return out

static func _find_path(w: Dictionary, from: Vector2, to: Vector2) -> Array:
	var a := astar(w)
	var fc := WorldGen.cell_of(nearest_passable(w, from))
	var tp := nearest_passable(w, to)
	var tc := WorldGen.cell_of(tp)
	if fc == tc:
		return [tp]
	var pts: PackedVector2Array = a.get_point_path(fc, tc)
	if pts.is_empty():
		return []
	var out := []
	for i in range(1, pts.size()):
		out.append(pts[i])
	# finish exactly on the requested point when it is passable
	if passable(w, to) and WorldGen.cell_of(to) == tc:
		out[-1] = to
	return _smooth_path(w, from, out)

## String-pulls a cell path: skips corners when the straight line between points stays on passable
## ground, so movers walk smooth lines instead of grid zig-zags. Runs once per path.
static func _smooth_path(w: Dictionary, from: Vector2, path: Array) -> Array:
	if path.size() < 3:
		return path
	var out := []
	var anchor := from
	var last := 0
	for j in range(1, path.size()):
		if not _clear_line(w, anchor, path[j]):
			out.append(path[j - 1])
			anchor = path[j - 1]
		last = j
	out.append(path[last])
	return out

static func _clear_line(w: Dictionary, a: Vector2, b: Vector2) -> bool:
	# Stay on ground at least as fast as the slower end, so shortcuts never leave a road.
	var floor_speed := minf(speed_mult(w, a), speed_mult(w, b)) * 0.99
	var n := int(ceil(a.distance_to(b) / (WorldGen.CELL * 0.34)))
	var last := Vector2i(-1, -1)
	var terrain: String = w["terrain"]
	var road: String = w["road"]
	var mx := WorldGen.W * WorldGen.CELL
	var my := WorldGen.H * WorldGen.CELL
	for k in range(1, n):
		var p := a.lerp(b, float(k) / n)
		var c := WorldGen.cell_of(p)
		if c == last:
			continue   # same cell as the previous sample: same answer (perf: ~3x fewer lookups)
		last = c
		# Read this cell once. The previous helper chain repeated the cell conversion for passability,
		# terrain speed and road speed on every sample of every growing string-pull segment.
		if p.x < 0.0 or p.y < 0.0 or p.x >= mx or p.y >= my:
			return false
		var idx := WorldGen.idx(c.x, c.y)
		var speed: float = WorldGen.TERRAIN_SPEED.get(terrain[idx], 0.0)
		if speed <= 0.0:
			return false
		if road[idx] == "1":
			speed *= WorldGen.ROAD_SPEED
		if speed < floor_speed:
			return false
	return true

static func path_length(start: Vector2, path: Array) -> float:
	var d := 0.0
	var p := start
	for q in path:
		d += p.distance_to(q); p = q
	return d

# ================================================================== strength, scouting & warbands (campaign/world_warbands.gd)
const MUSTER_STEP := 3

static func unit_power(u: Unit) -> float: return WorldWarbands.unit_power(u)
static func band_power(units: Array) -> float: return WorldWarbands.band_power(units)
static func party_power(game) -> float: return WorldWarbands.party_power(game)
static func approx_count(n: int) -> String: return WorldWarbands.approx_count(n)
static func gear_impression(units: Array) -> String: return WorldWarbands.gear_impression(units)
static func relative_strength(game, units: Array) -> String: return WorldWarbands.relative_strength(game, units)
static func scout_report(game, wid: String) -> Dictionary: return WorldWarbands.scout_report(game, wid)
static func home_text(w: Dictionary, wb: Dictionary) -> String: return WorldWarbands.home_text(w, wb)
static func spawn_warband(game, fid: String, pos: Vector2, count: int, kind: String, rng: RandomNumberGenerator, extra: Dictionary = {}) -> String: return WorldWarbands.spawn_warband(game, fid, pos, count, kind, rng, extra)
static func nearest_faction_town(w: Dictionary, fid: String, pos: Vector2) -> String: return WorldWarbands.nearest_faction_town(w, fid, pos)
static func field_target(w: Dictionary, day: float = 0.0) -> int: return WorldWarbands.field_target(w, day)
static func make_resident_troop(rng: RandomNumberGenerator, fid: String, town: Dictionary, wealth: int = -1) -> Unit: return WorldWarbands.make_resident_troop(rng, fid, town, wealth)
static func supported_field_count(game, fid: String, town: Dictionary, target: int) -> int: return WorldWarbands.supported_field_count(game, fid, town, target)
static func spawn_faction_band(game, fid: String, rng: RandomNumberGenerator, from_stock: bool = false, staged: bool = false, muster_head: Array = []) -> String: return WorldWarbands.spawn_faction_band(game, fid, rng, from_stock, staged, muster_head)
static func muster_start(game, head: Array, fid: String, pos: Vector2, count: int, kind: String, extra: Dictionary, rng: RandomNumberGenerator, own_rng: bool, then: Dictionary) -> void: WorldWarbands.muster_start(game, head, fid, pos, count, kind, extra, rng, own_rng, then)
static func mustering(w: Dictionary) -> Array: return WorldWarbands.mustering(w)
static func mustering_units(w: Dictionary) -> Array: return WorldWarbands.mustering_units(w)
static func muster_step(game, job: Array, frame_rng: RandomNumberGenerator) -> void: WorldWarbands.muster_step(game, job, frame_rng)
static func _muster_part(game, m: Dictionary, rng: RandomNumberGenerator) -> bool: return WorldWarbands._muster_part(game, m, rng)
static func _muster_done(game, m: Dictionary, wid: String, rng: RandomNumberGenerator) -> bool: return WorldWarbands._muster_done(game, m, wid, rng)
static func remove_warband(game, wid: String) -> void: WorldWarbands.remove_warband(game, wid)
static func _wander_target(game, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2: return WorldWarbands._wander_target(game, wb, rng)
static func _war_prey(w: Dictionary, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2: return WorldWarbands._war_prey(w, wb, rng)
static func travel_speed(base: float, men: int) -> float: return WorldWarbands.travel_speed(base, men)
static func _step_along(w: Dictionary, obj: Dictionary, dist: float) -> bool: return WorldWarbands._step_along(w, obj, dist)
static func _move_warbands(game, dt: float, t: float, rng: RandomNumberGenerator) -> void: WorldWarbands._move_warbands(game, dt, t, rng)
static func _warband_clashes(game, t: float, rng: RandomNumberGenerator) -> void: WorldWarbands._warband_clashes(game, t, rng)
static func _officer_count(wb: Dictionary) -> int: return WorldWarbands._officer_count(wb)
static func _clash_pairs(w: Dictionary, ids: Array) -> Array: return WorldWarbands._clash_pairs(w, ids)
static func weaken_faction(w: Dictionary, fid: String, size: int) -> void: WorldWarbands.weaken_faction(w, fid, size)
static func compute_road_links(w: Dictionary) -> void: WorldWarbands.compute_road_links(w)
static func nearest_town(w: Dictionary, pos: Vector2) -> String: return WorldWarbands.nearest_town(w, pos)
static func nearest_town_name(w: Dictionary, pos: Vector2) -> String: return WorldWarbands.nearest_town_name(w, pos)
static func _assault_arrives(game, wid: String) -> void: WorldWarbands._assault_arrives(game, wid)

# ================================================================== party travel
## Order the party to travel to a point (or into a town). Returns false if unreachable.
static func set_travel(game, target: Vector2, town_id: String = "") -> bool:
	var w: Dictionary = game.world
	var party: Dictionary = w["party"]
	var path := find_path(w, party["pos"], target)
	if path.is_empty():
		return false
	party["path"] = path
	party["target"] = path[-1]
	party["dest_town"] = town_id
	party["arrived"] = ""
	if party.get("objective", "hold_capital") == "hold_capital":
		party["objective"] = "march"   # an explicit move replaces a hold order
	return true

static func stop_travel(game) -> void:
	var party: Dictionary = game.world["party"]
	party["path"] = []
	party["dest_town"] = ""

static func is_travelling(game) -> bool:
	return not (game.world.get("party", {}).get("path", []) as Array).is_empty()

static func _move_party(game, dt: float) -> void:
	var w: Dictionary = game.world
	var party: Dictionary = w["party"]
	if (party["path"] as Array).is_empty():
		return
	var done := _step_along(w, party, travel_speed(PARTY_SPEED, game.company.size()) * smooth_speed(w, party, dt) * dt)
	if done and party["dest_town"] != "":
		party["arrived"] = party["dest_town"]
		party["dest_town"] = ""

static func _check_contact(game, t: float) -> void:
	var w: Dictionary = game.world
	var party: Dictionary = w["party"]
	if float(party["safe_until"]) > t or w.get("encounter", "") != "":
		return
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] == "caravan" or not Monsters.band_hostile(game, wb) or float(wb["rest_until"]) > t or (wb["units"] as Array).is_empty():
			continue
		if wb["kind"] == "assault" and t < float(wb["march_day"]) and wid != game.contract.get("target_id", ""):
			continue
		if (wb["pos"] as Vector2).distance_to(party["pos"]) < CONTACT:
			w["encounter"] = wid
			party["path"] = []
			party["dest_town"] = ""
			return

## Warbands the player can currently see (within sight of the party; contract target always).
static func visible_warbands(game) -> Array:
	var w: Dictionary = game.world
	var out := []
	var ppos: Vector2 = w["party"]["pos"]
	var tgt: String = game.contract.get("target_id", "")
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] == "militia" and not wb.get("mustered", false) and not wb.get("marching", false): continue
		if Monsters.suspended_band(wb): continue
		# tracks: a hunted target (bounty, hunt...) shows only when in sight; the contract gives its last-seen spot
		if (wid == tgt and not Tracks.hides_target(game, wid)) or (wb["pos"] as Vector2).distance_to(ppos) < PARTY_SIGHT:
			out.append(wid)
	return out

# ================================================================== encounters
## Start the battle against warband wid (from the pre-battle panel or an attack order).
static func engage(game, wid: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"].get(wid, {})
	if wb.is_empty():
		return
	if Monsters.suspended_band(wb): return
	if Diplomacy.peace_bound(w, Diplomacy.player_realm(w), str(wb.get("faction", ""))):
		if w.get("encounter", "") == wid: w["encounter"] = ""
		log_event(game, "Your alliance or non-aggression pact forbids this attack.")
		return
	if game.deployed_units().is_empty():
		log_event(game, "No one is fit to fight.")
		return
	if wb["kind"] == "caravan" and not Caravans.can_raid(game, wid):
		return   # you cannot raid the caravan you escort (Caravans.can_raid)
	# diplomacy: fighting their army -10 (-5 when they attacked first: they are the encounter already);
	# raiding a caravan is its own -12, taken when the caravan is plundered or the raid is beaten off
	# (monsters wave 1: deserters have no faction to offend; beasts and outlaws stand outside diplomacy)
	var they_first: bool = w.get("encounter", "") == wid
	if wb["kind"] != "caravan" and not wb.get("deserter", false) and not Monsters.is_wild_faction(wb["faction"]):
		Diplomacy.on_fight(game, wb["faction"], they_first)
		if not they_first and not is_hostile(game, wb["faction"]) and game.contract.get("target_id", "") != wid:
			log_event(game, "You attacked a band of %s without cause." % faction_the(wb["faction"]))
	w["encounter"] = wid
	var units: Array = (wb["units"] as Array).filter(func(u): return not u.dead)
	var c: Dictionary = game.contract if game.contract.get("target_id", "") == wid else {}
	# an escorted caravan within range fights alongside the company
	var allies: Array = []
	var car := Caravans.escorted_caravan(game)
	var car_id := ""
	if not car.is_empty() and Caravans.escort_near(game, car):
		allies = (car["units"] as Array).filter(func(u): return not u.dead)
		car_id = car["id"]
		c = game.contract
	# diplomacy: patrols of factions friendly to the company (standing >= 50) close by join on its side
	var ally_bands := []
	if wb["kind"] != "caravan":
		for oid in w["warbands"]:
			var o: Dictionary = w["warbands"][oid]
			if oid == wid or oid == car_id or o["kind"] in ["caravan", "militia", "beasts", "den", "camp", "bandit", "deserter"] \
					or o["faction"] == wb["faction"]:
				continue
			if o["kind"] == "assault" and not Diplomacy.allied(w, Diplomacy.player_realm(w), o["faction"]): continue
			if Diplomacy.allied(w, o["faction"], wb["faction"]) or Diplomacy.peace_bound(w, o["faction"], wb["faction"]) or Diplomacy.in_truce(w, o["faction"], wb["faction"]): continue
			if (o["pos"] as Vector2).distance_to(w["party"]["pos"]) > 150.0 or not Diplomacy.friendly(game, o["faction"]):
				continue
			if Diplomacy.fights(w, o["faction"], wb["faction"]) or Diplomacy.player_hostile(game, wb["faction"]):
				ally_bands.append(oid)
				allies = allies + (o["units"] as Array).filter(func(u): return not u.dead)
		if not ally_bands.is_empty():
			log_event(game, "Friendly patrols join the company's fight.")
	# economy: armies eat from their home town; the food spec reads these at battle spawn
	var ally_supply := TownEcon.force_supply(w, car) if not car.is_empty() and car_id != "" else "well"
	if car_id == "" and not ally_bands.is_empty():
		ally_supply = TownEcon.force_supply(w, w["warbands"][ally_bands[0]])
	var params := {"enemy": units, "allies": allies, "contract": c, "map": "small" if units.size() + allies.size() <= 10 else "large",
		"terrain": terrain_at(w, w["party"]["pos"]), "warband_id": wid, "caravan_id": car_id, "ally_bands": ally_bands,
		"enemy_supply": TownEcon.force_supply(w, wb), "ally_supply": ally_supply}
	Monsters.battle_extras(game, wb, params)   # monsters wave 1: militia allies (defend), lair terrain with choke points
	game.start_battle(params)

## Back away from an encounter: the party steps off and is safe from contact for half a day.
static func retreat(game, wid: String) -> void:
	var w: Dictionary = game.world
	var party: Dictionary = w["party"]
	var wb: Dictionary = w["warbands"].get(wid, {})
	w["encounter"] = ""
	party["safe_until"] = game.day + 0.5
	if wb.is_empty():
		return
	wb["rest_until"] = game.day + 0.5
	# abandoning the caravan you escort: the attackers take it
	var car_id: String = wb.get("escort_fight", "")
	wb.erase("escort_fight")
	if car_id != "" and w["warbands"].has(car_id):
		Caravans.lost(game, car_id, wb["faction"])
	var away: Vector2 = ((party["pos"] as Vector2) - wb["pos"]).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	set_travel(game, party["pos"] + away * 90.0)

# ================================================================== time
static func on_time(game, days: float, in_town: bool = false, work_budget_usec: int = 0) -> void:
	var run := _time_begin(game, days, in_town)
	if run.is_empty():
		return
	run["work_budget_usec"] = maxi(0, work_budget_usec)
	while not _time_part(game, run):
		pass
	performance_queue(game)

## Map work remains resumable even while the player has stopped travelling.
## The map holds its clock until this midnight has settled, so another day
## cannot prepend work ahead of unfinished food, succession or dragon care.
static func work_slice(game, budget_usec: int = 4000) -> int:
	var w: Dictionary = game.world
	if (w.get("work", []) as Array).is_empty():
		_background_fights(game, mini(2000, budget_usec))
		performance_queue(game)
		return 0
	var rng := _rng(w)
	var started := Time.get_ticks_usec()
	var count := 0
	while not (w.get("work", []) as Array).is_empty() and (count == 0 or Time.get_ticks_usec() - started < maxi(1, budget_usec)):
		_run_job(game, rng, true)
		count += 1
	w["rng_state"] = str(rng.state)
	performance_queue(game)
	return count

## Officer succession duels, a little each frame, never holding the clock (Army._queue_fight).
static func _background_fights(game, budget_usec: int) -> void:
	var q: Array = game.world.get("fight_work", [])
	if q.is_empty(): return
	var started := Time.get_ticks_usec()
	var fid := str(q.pop_front())
	Army.fight_step(game, fid, budget_usec)
	Perf.record_us("Army battles", Time.get_ticks_usec() - started)

static func performance_queue(game) -> void:
	var work: Array = game.world.get("work", [])
	var oldest: float = float(game.day)
	for job: Array in work:
		if job.size() > 2 and job[0] in ["econ", "fam", "fam2", "bday", "refresh", "census_t", "plots_t", "sick", "herds", "tturn", "tmonth", "wed", "arms_town"] and (job[2] is int or job[2] is float):
			oldest = minf(oldest, float(job[2]))
		elif job.size() > 1 and job[0] in ["feudal", "dragon_care", "dragon_care_pay", "fturn", "coin"] and (job[1] is int or job[1] is float):
			oldest = minf(oldest, float(job[1]))
	Perf.record_queue(work.size(), maxf(0.0, float(game.day) - oldest))

const WORK_LABELS := {
	"econ": "Town economy", "fam": "Household turns", "fam2": "Household services",
	"bday": "Local wages and coin", "tturn": "Town weekly work", "tmonth": "Town monthly taxes",
	"fturn": "Realm weekly work", "wed": "Family marriages", "coin": "Coin circulation",
	"arms_town": "Town equipment", "dragon_care": "Dragon care", "feudal": "Feudal succession",
	"dragon_care_pay": "Dragon care payments", "ownership_finish": "Ownership reconciliation",
	"army": "Army pay and supply", "army_pay": "Army pay and supply", "army_rk": "Field army equipment", "army_tree": "Army command structure",
	"army_misc": "Army recruitment", "army_sweep": "Army casualty accounting", "army_fight": "Army battles",
	"census_t": "Town census", "plots_t": "Land and crops", "sick": "Local sickness", "sick_w": "Army sickness",
	"caravan": "Caravan muster", "spawn": "Force muster", "refresh": "Town market refresh",
	"war_assault": "War assault orders", "militia": "Town militia", "herds": "Herd care"
}

static func _run_job(game, rng: RandomNumberGenerator, budgeted: bool = false) -> void:
	var kind := String(game.world["work"][0][0])
	var label := String(WORK_LABELS.get(kind, kind.replace("_", " ").capitalize()))
	Perf.set_stage(label)
	var started := Time.get_ticks_usec()
	_do_work(game, rng, budgeted)
	var elapsed := Time.get_ticks_usec() - started
	job_worst[kind] = maxi(int(job_worst.get(kind, 0)), elapsed)
	var totals: Array = job_total.get(kind, [0, 0])
	job_total[kind] = [int(totals[0]) + elapsed, int(totals[1]) + 1]
	Perf.record_us(label, elapsed)
	# Finish the original final reconciliation as its own ordered operation.
	# Keeping it in the native work queue also makes pause/save/town entry wait
	# for completion. Unbudgeted callers retain their original atomic path.
	if budgeted and kind != "ownership_finish" and game.world["work"].is_empty() and game.world.has("feudal"):
		game.world["work"].append(["ownership_finish"])

## The same ordered time advance can be drained synchronously or resumed by startup.
## This context lives in its caller, never in the save. Game time and RNG do not
## advance because a frame passed; each original operation runs exactly once.
static func _time_begin(game, days: float, in_town: bool) -> Dictionary:
	var w: Dictionary = game.world
	if w.is_empty() or not w.has("towns") or days <= 0.0:
		return {}
	var steps := maxi(1, ceili(days / STEP))
	return {"rng": _rng(w), "days": days, "in_town": in_town, "steps": steps,
		"dt": days / steps, "t0": float(game.day) - days, "phase": "move", "i": 0,
		"movement_usec": 0, "whole": int(floor(game.day)), "jobs": 0, "jobs_done": 0}

## One existing movement substep, monster check, midnight pass or queued job.
## True means the entire time advance completed. The queue is fetched anew:
## midnight replaces it, and muster continuations prepend more work.
static func _time_part(game, run: Dictionary) -> bool:
	var w: Dictionary = game.world
	var rng: RandomNumberGenerator = run["rng"]
	match String(run["phase"]):
		"move":
			var begin := Time.get_ticks_usec()
			var dt: float = run["dt"]
			var i: int = run["i"]
			var t: float = float(run["t0"]) + dt * (i + 1)
			if not bool(run["in_town"]) and game.location == "" and w.get("encounter", "") == "":
				_move_party(game, dt)
			var u0 := Time.get_ticks_usec()
			WarAI.tick(game, t, dt)
			var u1 := Time.get_ticks_usec()
			_move_warbands(game, dt, t, rng)
			var u2 := Time.get_ticks_usec()
			_warband_clashes(game, t, rng)
			var u3 := Time.get_ticks_usec()
			Tracks.step(game, t)
			var u4 := Time.get_ticks_usec()
			Perf.record_us("War decisions", u1 - u0)
			Perf.record_us("Force movement", u2 - u1)
			Perf.record_us("Offscreen clashes", u3 - u2)
			Perf.record_us("Tracks and sightings", u4 - u3)
			step_parts["war_ai"] = int(step_parts.get("war_ai", 0)) + u1 - u0
			step_parts["move"] = int(step_parts.get("move", 0)) + u2 - u1
			step_parts["clashes"] = int(step_parts.get("clashes", 0)) + u3 - u2
			step_parts["tracks"] = int(step_parts.get("tracks", 0)) + u4 - u3
			if not bool(run["in_town"]) and game.location == "":
				var contact_started := Time.get_ticks_usec()
				_check_contact(game, t)
				Perf.record_us("Contact checks", Time.get_ticks_usec() - contact_started)
			run["movement_usec"] = int(run["movement_usec"]) + Time.get_ticks_usec() - begin
			run["i"] = i + 1
			if int(run["i"]) >= int(run["steps"]):
				run["phase"] = "monsters"
		"monsters":
			var begin := Time.get_ticks_usec()
			Monsters.on_time(game, float(run["days"]))
			Perf.record_us("Campaign creature checks", Time.get_ticks_usec() - begin)
			var elapsed := int(run["movement_usec"]) + Time.get_ticks_usec() - begin
			steps_worst = maxi(steps_worst, elapsed)
			steps_total += elapsed
			run["phase"] = "daily"
		"daily":
			if int(w.get("last_day", 0)) < int(run["whole"]):
				w["last_day"] = int(w.get("last_day", 0)) + 1
				var begin := Time.get_ticks_usec()
				_daily(game, int(w["last_day"]), rng)
				var elapsed := Time.get_ticks_usec() - begin
				daily_worst = maxi(daily_worst, elapsed)
				Perf.record_us("Midnight bookkeeping", elapsed)
			else:
				# Capture the original allowance once, after every crossed midnight.
				run["jobs"] = 1000000
				if int(run.get("work_budget_usec", 0)) <= 0 and float(run["days"]) < 0.25:
					run["jobs"] = maxi(1, ceili((w.get("work", []) as Array).size() * float(run["days"])))
				run["work_started"] = Time.get_ticks_usec()
				run["phase"] = "work"
		"work":
			if int(run["jobs_done"]) < int(run["jobs"]) and not (w.get("work", []) as Array).is_empty():
				run["finished_ownership"] = w["work"][0][0] == "ownership_finish"
				_run_job(game, rng, int(run.get("work_budget_usec", 0)) > 0)
				run["jobs_done"] = int(run["jobs_done"]) + 1
			var budget := int(run.get("work_budget_usec", 0))
			var budget_spent := budget > 0 and int(run["jobs_done"]) > 0 and Time.get_ticks_usec() - int(run["work_started"]) >= budget
			if budget_spent or int(run["jobs_done"]) >= int(run["jobs"]) or (w.get("work", []) as Array).is_empty():
				if (w.get("work", []) as Array).is_empty() and int(run["jobs_done"]) > 0 and w.has("feudal") and not run.get("finished_ownership", false):
					var reconciled := Time.get_ticks_usec()
					Feudal.finish(game)
					Perf.record_us("Ownership reconciliation", Time.get_ticks_usec() - reconciled)
				w["rng_state"] = str(rng.state)
				return true
	return false

## Hook from Game.pay_wages: the coins paid to the company's men go to their families (economy).
static func wages_paid(game, paid: Array) -> float:
	if game.world.has("towns"):
		return People.pay_company(game, paid)
	return 0.0

static func _daily(game, d: int, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	if not w.has("work"):
		w["work"] = []
	var raising := {}   # world size: bands still being mustered count as had (a map frame raises a few men a job)
	for m in mustering(w):
		if String(m.get("then", "")) == "band":
			raising[m["fid"]] = int(raising.get(m["fid"], 0)) + 1
	var patrols := _patrol_counts(w)   # no force changes during this faction/queue pass
	for fid in w["factions"]:
		var f: Dictionary = w["factions"][fid]
		f["strength"] = minf(1.0, float(f["strength"]) + 0.03)
		if not PATROLS.has(fid):
			continue
		var have := int(raising.get(fid, 0)) + int(patrols.get(fid, 0))
		if have < desired_bands(w, fid):
			if not (w["work"] as Array).has(["spawn", fid]):
				(w["work"] as Array).append(["spawn", fid])
	var q0 := Time.get_ticks_usec()
	var queued := {}   # towns with a refresh still queued (one pass over the queue, not one per town: world size)
	for j in w["work"]:
		if j[0] == "refresh":
			queued[j[1]] = true
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if float(d) >= float(t.get("next_refresh", 0.0)):
			if not queued.has(tid):
				(w["work"] as Array).append(["refresh", tid, d])
	TownEcon.queue_day(w, d)   # economy: market days, family turns, weekly town/faction turns (work jobs)
	Army.queue_day(w, d)   # economy spec 2: army pay, ranks, desertion, the casualty sweep, bandit camps (work jobs)
	ArmsTrade.queue_day(w, d)   # armoury purchases and ten-day own-faction supply (existing work queue)
	_dprof("queues", q0)

	var p0 := Time.get_ticks_usec()
	People.pay_crews(game)     # economy: caravan crews are paid by their owners
	People.tick_ages(game, d)  # economy: named people age with the calendar (birth days)
	p0 = _dprof("people", p0)
	# the census: a season's count per town, the 60-day buffers; and the land map: one town in seven a day (felling,
	# regrowth, clearing, homes and yards). World size: one work job per town, put at the FRONT of the queue (so they
	# still run before every other job, in the same order as the calls they replace: the nights between change no
	# family's people); a big world no longer does every town's census and plot week in the midnight frame.
	var front := []
	var ids: Array = w["towns"].keys()
	for i in ids.size():
		front.append(["census_t", ids[i], d, i + 1, float(game.day)])
	Census.fates_day(w, d)
	p0 = _dprof("census", p0)
	Caravans.daily(game, rng)
	Monsters.daily(game, d, rng)   # monsters wave 1: queues lair/camp/militia/bandit jobs, bounty growth
	p0 = _dprof("monsters", p0)
	Contracts.daily_check(game)
	Diplomacy.daily(game, d)   # diplomacy: one step per day, after the economy/day tick (weekly rolls inside)
	Settlement.daily(game, d)
	p0 = _dprof("diplomacy", p0)
	var sids: Array = w["towns"].keys()
	sids.sort()   # as Plots.daily picks its towns
	for i in sids.size():
		if (d + i) % 7 == 2:
			front.append(["plots_t", sids[i], d])
	front.append_array(w["work"])
	w["work"] = front
	p0 = _dprof("plots", p0)
	Sickness.queue_day(w, d)   # sickness: work jobs (each town's deaths, recoveries and new cases; forces, the company)
	Herds.queue_day(w, d)   # herds: each town's herd week (one in seven a day), the droves on the roads
	(w["work"] as Array).append(["feudal", d])
	(w["work"] as Array).append(["dragon_care", d])

static func _patrol_counts(w: Dictionary) -> Dictionary:
	var counts := {}
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] in ["patrol", "raider"]:
			var fid: String = wb["faction"]
			counts[fid] = int(counts.get(fid, 0)) + 1
	return counts

## Diagnostics: the worst midnight cost of each part of _daily (microseconds in daily_parts). Returns now.
static func _dprof(k: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	if t1 - t0 > int(daily_parts.get(k, 0)):
		daily_parts[k] = t1 - t0
	daily_total[k] = int(daily_total.get(k, 0)) + t1 - t0
	return t1

# ================================================================== battle result
## The census: every man who fell in the company's battle died in it (now, or when the army sweep takes the
## enemy's dead off their family rows).
static func on_battle_result(game, result: Dictionary) -> void:
	var w: Dictionary = game.world
	if w.is_empty() or not w.has("warbands"):
		return
	var battle_id := String(game.pending_battle.get("warband_id", w.get("encounter", "")))
	if Monsters.suspended_band(w["warbands"].get(battle_id, {})): return
	var cdetail := "a battle with the company near %s" % nearest_town_name(w, w["party"]["pos"])
	for us in [result.get("enemy_units", []), result.get("player_units", []), game.pending_battle.get("allies", [])]:
		for u in us:
			if u is Unit and u.dead and not DragonCombat.is_dragon_unit(game, u):
				Census.note_fate(w, u.uid, "battle", cdetail)
	Census.ctx("battle", cdetail)
	_battle_result(game, result)
	Census.ctx_end()

static func _battle_result(game, result: Dictionary) -> void:
	var w: Dictionary = game.world
	var wid: String = str(game.pending_battle.get("warband_id", w.get("encounter", "")))
	w["encounter"] = ""
	for u in result.get("player_units", []):   # economy: the company's dead are their families' loss
		if u is Unit and u.dead and not DragonCombat.is_dragon_unit(game, u):
			People.casualty(game, u, "dead", "company")
	# Game.finish_battle settled each actual piece once through Salvage. Its receipts
	# own stock/till/wallet changes; campaign reconciliation must not sell them again.
	var wb: Dictionary = w["warbands"].get(wid, {})
	var party: Dictionary = w["party"]
	if wb.is_empty():
		return
	var fid: String = wb["faction"]
	var size := (wb["units"] as Array).size()
	wb.erase("escort_fight")
	# escorted caravan: its dead guards are gone; it survives a win and is plundered on a loss
	var car_id: String = str(game.pending_battle.get("caravan_id", ""))
	var car: Dictionary = w["warbands"].get(car_id, {})
	ArmsTrade.after_company_battle(game, result, wb, car, game.pending_battle.get("ally_bands", []))   # arms trade: the fallen's kit
	if not car.is_empty():
		for u in car["units"]:
			if u.dead:
				People.crew_casualty(game, car, u)   # economy: a fallen guard is his family's loss
		car["units"] = (car["units"] as Array).filter(func(u): return not u.dead)
		if int(result.get("winner", -1)) != 0:
			Caravans.lost(game, car_id, fid)
	# diplomacy: friendly patrols that fought beside the company lose their dead; roster may have changed
	for bid in game.pending_battle.get("ally_bands", []):
		var ab: Dictionary = w["warbands"].get(bid, {})
		if not ab.is_empty():
			ab["units"] = (ab["units"] as Array).filter(func(u): return not u.dead)
			if (ab["units"] as Array).is_empty():
				remove_warband(game, bid)
	Diplomacy.roster_changed(game)
	# economy spec 2: the company holds the field -> it takes the beaten force's food and drink (up to what its men
	# can carry) and the living enemies run home to their families; beaten off -> the band's survivors count a
	# battle. An AI winner never takes the company's stores.
	if int(result.get("winner", -1)) == 0 and Army.is_people_band(wb):
		result["supplies_taken"] = Supplies.company_take(game, wb)
		Army.fight_pay(game, wb, 1.0)   # a day's wage for the fight; the survivors regroup below
	elif int(result.get("winner", -1)) != 0:
		Army.survived(wb)
	if Monsters.on_battle_result(game, wid, wb, result):   # monsters wave 1: trophies, lairs, camps, deserters, militia
		return
	if int(result.get("winner", -1)) == 0 and wb["kind"] == "caravan":
		# raid: part of the cargo itself is the prize (diplomacy -12 inside); guards still alive are witnesses
		var witnesses := (wb["units"] as Array).any(func(u): return not u.dead)
		Caravans.plunder(game, wid, witnesses)
		weaken_faction(w, fid, 0)
	elif int(result.get("winner", -1)) == 0 and Army.is_people_band(wb) and BattleRounds.retreat_band(game, wb):
		# Beaten, not destroyed: the survivors appear at their owner's seat and must regroup (battle_rounds.gd).
		weaken_faction(w, fid, size - (wb["units"] as Array).size())
		log_event(game, "The company beat a band of %s; its survivors fell back to %s to regroup." % [faction_the(fid), str(w["towns"].get(str(wb.get("home", "")), {}).get("name", "their home"))])
		if game.contract.get("target_id", "") == wid:
			Contracts.complete(game)
	elif int(result.get("winner", -1)) == 0:
		remove_warband(game, wid)
		weaken_faction(w, fid, size)
		# (old ad-hoc -4 / +2 to their enemies replaced by diplomacy: -10 on engage, taking sides on contracts)
		log_event(game, "The company destroyed a band of %s near %s." % [faction_the(fid), nearest_town_name(w, wb["pos"])])
		if game.contract.get("target_id", "") == wid:
			Contracts.complete(game)
	else:
		if wb["kind"] == "caravan":
			Diplomacy.on_raid(game, fid)   # a beaten-off raid still costs the -12
		wb["units"] = (wb["units"] as Array).filter(func(u): return not u.dead)
		if (wb["units"] as Array).is_empty():
			remove_warband(game, wid)
		else:
			wb["rest_until"] = game.day + 1.0
		party["safe_until"] = game.day + 1.0
		party["path"] = []
		var away: Vector2 = ((party["pos"] as Vector2) - wb["pos"]).normalized()
		if away == Vector2.ZERO:
			away = Vector2.LEFT
		party["pos"] = nearest_passable(w, party["pos"] + away * 70.0)
		log_event(game, "The company was driven off by a band of %s." % faction_the(fid))
		if int(result.get("winner", -1)) == 1:
			BattleRounds.retreat_player(game)   # the beaten army goes home and must remuster

# ================================================================== load fix-up
## JSON turns ints into floats; restore the int fields the menus index with.
static func after_load(game) -> void:
	HerdRaids.reset()
	var w: Dictionary = game.world
	if w.is_empty():
		return
	for k in ["version", "seed", "w", "h", "cell", "next_id", "last_day"]:
		if w.has(k):
			w[k] = int(w[k])
	WorldGen.use_world(w)   # the map grid of this save (before the 1.5x stretch: 100 x 64)
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		t["size"] = int(t["size"]); t["wealth"] = int(t["wealth"])
		for k in t.get("crafters", {}):
			t["crafters"][k]["skill"] = int(t["crafters"][k]["skill"])
		if t.get("healer", {}).has("skill"):
			t["healer"]["skill"] = int(t["healer"]["skill"])
		for c in t.get("contracts", []):
			_fix_contract(c)
	_fix_contract(game.contract)
	# every force has a home town of its faction (older saves: nearest town of that faction)
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if not w["towns"].has(str(wb.get("home", ""))) and not w.get("lairs", {}).has(str(wb.get("home", ""))) \
				and not Monsters.is_monster_faction(wb["faction"]):
			wb["home"] = nearest_faction_town(w, wb["faction"], wb["pos"])
		for u in wb["units"]:
			if u.home_town == "":
				u.home_town = wb["home"]
	if not w.get("towns", {}).is_empty() and not (w["towns"].values()[0] as Dictionary).has("road_links"):
		compute_road_links(w)   # saves from before caravans
	Barge.before_load(game)   # coinage: saves from before v0.010 count in gold: x20 into coins
	TownEcon.after_load(game)   # economy: JSON ints back; saves from before the economy get one generated
	Herds.after_load(game)   # herds: JSON ints back; older saves get records from their herd totals (and the new trades)
	Academy.after_load(game)   # v0.012: new goods' prices, a research house in each capital, the faction know-how mirrors
	Diplomacy.after_load(game)   # diplomacy: older saves get relations from baselines, old rep as earned standing
	Monsters.after_load(game)   # monsters wave 1 (older saves: lairs, camps and militia are added)
	People.adopt_company(game)  # economy: company men from older saves get a family record in their home town
	People.tick_ages(game, 0)   # economy: birth days for older saves (from their stored age)
	Militia.adopt_families(game) # economy: militiamen of older saves come from town families
	ServiceIdentity.after_load(game) # exact migration copies, before any legacy guessed binding
	People.rebind_all(game)      # economy: every named person of an older save gets his register record
	Army.after_load(game)   # economy spec 2: older saves get families for every soldier, rank trees and war chests
	ArmsTrade.after_load(game)   # arms trade: older saves get armories (their old gear keeps no maker's mark)
	Tracks.after_load(game)   # tracks and sightings: JSON types back
	WarAI.after_load(game)   # war interception: JSON types back
	if not w.has("coin"):
		Barge.init_world(game)   # coinage: older saves start their coin ledger at load
	Census.after_load(game)   # the census: JSON ints back; older saves take their first count today
	Feudal.after_load(game)
	DragonCombat.after_load(game)
	Dragons.after_load(game)
	Intrigue.after_load(game)
	CharacterDesign.after_load(game)
	Prisoners.after_load(game)
	Sickness.use_world_deadliness(w)
	Monsters.use_world(w)
	Migration.after_load(game)
	Settlement.after_load(game)
	HouseUpkeep.after_load(game)
	TroopUpkeep.after_load(game)
	CourtEvents.after_load(game)

static func _fix_contract(c: Dictionary) -> void:
	for k in ["pay", "size"]:
		if c.has(k):
			c[k] = int(c[k])

## Daily heavy jobs (warband spawns, town shop/recruit refreshes) run one per map frame instead of all at
## once at midnight, which caused a visible hitch every in-game day.
static func _do_work(game, rng: RandomNumberGenerator, budgeted: bool = false) -> void:
	var w: Dictionary = game.world
	var work: Array = w.get("work", [])
	if work.is_empty():
		return
	var job: Array = work.pop_front()
	if job[0] == "ownership_finish":
		Feudal.finish(game)
		return
	if job[0] == "dragon_care_pay":
		DragonCare.daily(game, int(job[1]))
		return
	if job[0] == "feudal":
		Feudal.daily(game, int(job[1]))
		return
	if job[0] == "dragon_care":
		# Food/work/deaths and lawful succession settle before this midnight's
		# upkeep. Load, battle and generic reconciliation never debit care.
		Feudal.finish(game)
		if budgeted:
			# Payment remains immediately after the same native reconciliation,
			# before every later job. It can resume on the next frame without
			# repeating ownership work or changing the explicit care midnight.
			work.push_front(["dragon_care_pay", job[1]])
			return
		var care_started := Time.get_ticks_usec()
		DragonCare.daily(game, int(job[1]))
		Perf.record_us("Dragon care payments", Time.get_ticks_usec() - care_started)
		return
	if job[0] == "census_t":   # world size: the census of one town for the midnight it belongs to (see _daily)
		Census.town_day(game, String(job[1]), int(job[2]), int(job[3]), float(job[4]))
		return
	if job[0] == "plots_t":   # world size: one town's plot week (Plots.daily's work, one town a job)
		var pt: Dictionary = w["towns"].get(String(job[1]), {})
		if TownEcon.has_econ(pt) and not Plots.of(pt).is_empty():
			Plots.week(game, pt, float(job[2]), 7)
		return
	if TownEcon.do_job(game, job) or Army.do_job(game, job) or ArmsTrade.do_job(game, job) or Sickness.do_job(game, job) or Herds.do_job(game, job):   # economy jobs (econ, fam, tturn, fturn; army, army_sweep, army_misc, army_fight; sickness: sick, sick_w; herds, droves)
		return
	if job[0] == "spawn":
		if job.size() > 2:
			muster_step(game, job, rng)   # world size: the band's next few men
		else:   # The raising checks the actual requested population, meals and wage reserve.
			spawn_faction_band(game, job[1], rng, true, false, ["spawn", job[1]])
	elif job[0] == "caravan":
		if job.size() > 3:
			muster_step(game, job, rng)   # world size: the caravan's next few guards
		else:
			var dest := str(job[2]) if job.size() > 2 else ""
			Caravans.spawn(game, job[1], rng, dest, "", {}, ["caravan", job[1], dest])
	elif job[0] == "war_assault":   # diplomacy: a faction at war marches on an enemy town
		Diplomacy.launch_assault(game, job[1], job[2], rng)
	elif Monsters.do_work(game, job, rng):   # monsters wave 1 jobs
		pass
	elif job[0] == "refresh" and w["towns"].has(job[1]):
		var trng := RandomNumberGenerator.new()
		trng.seed = hash([int(w["seed"]), job[1], int(job[2])])
		Economy.refresh_town(w["towns"][job[1]], float(job[2]), trng)

# ================================================================== the years before (new campaigns)
## Douglas: "simulate 5 years on startup so there's actually backgrounds". A new campaign runs the world's own
## sim (families, businesses, loans, caravans, armies, wars, weddings, births, deaths) the chosen days forward
## before the player gets the map: ui/presim.gd calls presim_step a few days per frame behind a progress bar,
## then presim_finish. The company sits outside it: no wages, food, healing or travel, no contact (on_time with
## in_town = true). Deterministic per seed: each day is exactly one on_time(1 day). Old saves never run it.
## The length is the player's choice on the New Campaign screen (ui/newgame.gd), one day to 100 years;
## PRESIM_DEFAULT_DAYS is the default (2026-10-17: one day, the setting every test uses; PRESIM_YEARS stays the
## integer-year callers' figure). The chosen length is stored in the world (presim.total, days) at the first step.
const PRESIM_YEARS := 5
const PRESIM_DEFAULT_DAYS := 1
const PRESIM_YEARS_MIN := 1
const PRESIM_YEARS_MAX := 100
const PRESIM_YEAR_DAYS := 4 * Calendar.DAYS_PER_SEASON
const PRESIM_DAYS_MIN := 1
const PRESIM_DAYS_MAX := PRESIM_YEARS_MAX * PRESIM_YEAR_DAYS
static var presim_span_days: int = PRESIM_DEFAULT_DAYS:
	set(value):
		presim_span_days = clampi(value, PRESIM_DAYS_MIN, PRESIM_DAYS_MAX)
# Compatibility for existing integer-year callers and diagnostics. Short histories
# use presim_span_days directly; they never pass fractional years through an int.
static var presim_years: int = PRESIM_YEARS:
	set(value):
		presim_span_days = presim_days(value)
	get:
		return maxi(PRESIM_YEARS_MIN, ceili(float(presim_span_days) / PRESIM_YEAR_DAYS))

static func presim_days(years: int) -> int: return WorldPresim.presim_days(years)
static func presim_years_of(game) -> float: return WorldPresim.presim_years_of(game)
static func presim_span_text(days: int) -> String: return WorldPresim.presim_span_text(days)
static func presim_total(game) -> int: return WorldPresim.presim_total(game)
static func presim_left(game) -> int: return WorldPresim.presim_left(game)
static func presim_step(game, n: int) -> int: return WorldPresim.presim_step(game, n)
static func presim_slice(game, state: Dictionary, budget_usec: int) -> int: return WorldPresim.presim_slice(game, state, budget_usec)
static func presim_finish(game, wall_ms: int = 0) -> void: WorldPresim.presim_finish(game, wall_ms)
