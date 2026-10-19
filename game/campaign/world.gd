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

# ================================================================== generation
static var generation_parts_total_usec := 0   # diagnostics only; never saved
static var generation_part_worst_usec := 0
static var generation_part_count := 0
const GENERATION_STAGES := ["Land and sea", "Towns and holds", "Roads", "Realms and road links",
	"Town households and markets", "Company arrival", "Realm patrols", "Lairs, camps and militia",
	"Company families", "Army rolls and ranks", "Armories", "Research houses", "Coin ledger",
	"Town plots and initial jobs", "Opening census", "World complete"]

static func generate(game, rng: RandomNumberGenerator) -> void:
	var run := generate_begin(game, rng)
	while not generate_part(game, run):
		pass

## Both callers perform the same ordered operations. This context belongs to
## its caller and is never part of the world/save. No observer uses the partial world.
static func generate_begin(game, _rng_unused: RandomNumberGenerator) -> Dictionary:
	HerdRaids.reset()
	var w: Dictionary = game.world
	w.clear()
	WarAI.new_world()   # caches of the world that was there before (the band grid) go
	var seed_v := int(game.seed_value)
	var grng := RandomNumberGenerator.new()
	grng.seed = seed_v
	w["version"] = 1
	w["seed"] = seed_v
	WorldGen.set_size(WorldGen.gen_stretch_now())   # war pick 5: new worlds are 1.5x the old map; world size: larger
	w["w"] = WorldGen.W; w["h"] = WorldGen.H; w["cell"] = WorldGen.CELL
	w["steppe_enabled"] = WorldGen.steppe_enabled
	w["sickness_deadliness"] = Sickness.new_world_deadliness   # the New Campaign slider
	Sickness.use_world_deadliness(w)
	w["creatures_enabled"] = Monsters.new_world_creatures   # v0.035: the New Bloodline choice
	Monsters.use_world(w)
	if WorldGen.TF != 1.0:
		w["size"] = WorldGen.gen_size; w["tf"] = WorldGen.TF   # world size (the normal map saves neither: as before)
	generation_parts_total_usec = 0
	generation_part_worst_usec = 0
	generation_part_count = 0
	return {"rng": grng, "seed": seed_v, "phase": 0, "i": 0}

static func generate_part(game, run: Dictionary) -> bool:
	var begin := Time.get_ticks_usec()
	var done := _generate_part(game, run)
	var elapsed := Time.get_ticks_usec() - begin
	generation_parts_total_usec += elapsed
	generation_part_worst_usec = maxi(generation_part_worst_usec, elapsed)
	generation_part_count += 1
	return done

static func _generate_part(game, run: Dictionary) -> bool:
	var w: Dictionary = game.world
	var grng: RandomNumberGenerator = run["rng"]
	var phase: int = run["phase"]
	match phase:
		0:
			WorldGen.gen_terrain(w, int(run["seed"]), grng)
		1:
			WorldGen.place_towns(w, grng)
		2:
			WorldGen.build_roads(w, grng)
		3:
			_generate_realms(game)
			run["towns"] = w["towns"].keys()   # original insertion order, not sorted
		4:
			var ids: Array = run["towns"]
			var i: int = run["i"]
			if i < ids.size():
				_generate_town(game, String(ids[i]), int(run["seed"]), grng)
				run["i"] = i + 1
			if int(run["i"]) < ids.size(): return false
		5:
			_generate_party(game)
			run["patrols"] = PATROLS.keys()
			run["band_i"] = 0
		6:
			if not (w.get("work", []) as Array).is_empty():
				var job: Array = (w["work"] as Array).pop_front()
				muster_step(game, job, grng)
				return false
			var fids: Array = run["patrols"]
			var i: int = run["i"]
			if i < fids.size():
				var fid := String(fids[i])
				if int(run["band_i"]) == 0:
					run["band_count"] = desired_bands(w, fid)
				if int(run["band_i"]) < int(run["band_count"]):
					spawn_faction_band(game, fid, grng, false, false, ["generate_patrol", fid])
					run["band_i"] = int(run["band_i"]) + 1
				if int(run["band_i"]) >= int(run["band_count"]):
					run["i"] = i + 1; run["band_i"] = 0
			if not (w.get("work", []) as Array).is_empty(): return false
			if int(run["i"]) < fids.size(): return false
		7:
			if not run.has("monsters"):
				var mrng := RandomNumberGenerator.new()
				mrng.seed = int(run["seed"]) + 4242
				run["monsters"] = Monsters.generate_begin(game, mrng)
			if not Monsters.generate_part(game, run["monsters"]): return false
			run.erase("monsters")
		8:
			People.adopt_company(game)
			People.tick_ages(game, 0)
		9:
			if not run.has("army_init"):
				run["army_init"] = Army.init_begin(game)
			if not Army.init_part(game, run["army_init"]): return false
			run.erase("army_init")
		10:
			if not run.has("arms_init"):
				run["arms_init"] = ArmsTrade.init_begin(game)
			if not ArmsTrade.init_part(game, run["arms_init"]): return false
			run.erase("arms_init")
		11:
			Academy.init_world(game)
		12:
			Barge.init_world(game)
		13:
			if not run.has("plot_towns"):
				var plot_ids: Array = w.get("towns", {}).keys()
				plot_ids.sort()   # Plots.init_world's original order
				run["plot_towns"] = plot_ids
			var ids: Array = run["plot_towns"]
			var i: int = run["i"]
			if i < ids.size():
				Plots.init_town(game, String(ids[i]))
				run["i"] = i + 1
			if int(run["i"]) < ids.size(): return false
		14:
			Census.init_world(game)
		15:
			for town in w["towns"].values():
				if TownEcon.has_econ(town):
					Population.generated_business_owners(town["econ"])
					for f in town["econ"]["fams"]:
						if not Population.is_cohort(f) and not f.get("estate", false) and not f.get("gone", false): Families.reassign(town["econ"], f)
			Dynasty.prepare_world(game)
			Feudal.prepare_world(game)
			Settlement.after_load(game)
			w["rng_state"] = str(grng.state)
			return true
	run["phase"] = phase + 1
	run["i"] = 0
	return false

## A soft frame allowance: complete at least one original indivisible part.
## Completion clears the caller's context only after the final RNG state exists.
static func generate_slice(game, state: Dictionary, budget_usec: int) -> bool:
	if state.is_empty(): return true
	var begin := Time.get_ticks_usec()
	var first := true
	while first or Time.get_ticks_usec() - begin < maxi(0, budget_usec):
		first = false
		if generate_part(game, state):
			state.clear()
			return true
	return false

static func generation_stage_name(state: Dictionary) -> String:
	if state.is_empty(): return "World complete"
	return String(GENERATION_STAGES[clampi(int(state["phase"]), 0, GENERATION_STAGES.size() - 1)])

## Phase progress, rather than an estimate of elapsed time. Town passes retain
## their original orders; inspecting progress never draws random numbers.
static func generation_progress(state: Dictionary) -> float:
	if state.is_empty(): return 1.0
	var phase: int = state["phase"]
	var fraction := 0.0
	if phase == 4:
		fraction = float(state["i"]) / maxf(1.0, float((state["towns"] as Array).size()))
	elif phase == 6:
		fraction = float(state["i"]) / maxf(1.0, float((state["patrols"] as Array).size()))
	elif phase == 7 and state.has("monsters"):
		var m: Dictionary = state["monsters"]
		var mi: int = m["i"]
		match String(m["phase"]):
			"lairs": fraction = float(mi) / maxf(1.0, float(m["lairs"])) / 3.0
			"camps": fraction = (1.0 + float(mi) / maxf(1.0, float(m["camps"]))) / 3.0
			"militia": fraction = (2.0 + float(mi) / maxf(1.0, float((m["towns"] as Array).size()))) / 3.0
	elif phase in [9, 10]:
		var init: Dictionary = state.get("army_init" if phase == 9 else "arms_init", {})
		if not init.is_empty():
			var phases: Array = ["bands", "factions", "militia"] if phase == 9 else ["bands", "towns", "finish"]
			var part := float(init["i"]) / maxf(1.0, float((init["ids"] as Array).size()))
			fraction = (float(phases.find(String(init["phase"]))) + part) / 3.0
	elif phase == 13 and state.has("plot_towns"):
		fraction = float(state["i"]) / maxf(1.0, float((state["plot_towns"] as Array).size()))
	return clampf((float(phase) + fraction) / float(GENERATION_STAGES.size()), 0.0, 1.0)

static func _generate_realms(game) -> void:
	var w: Dictionary = game.world
	w["warbands"] = {}
	w["work"] = []
	w["next_id"] = 1
	w["log"] = []
	w["encounter"] = ""
	w["last_day"] = 0
	w["factions"] = {}
	for fid in DB.factions:
		var towns := []
		var capital := ""
		for tid in w["towns"]:
			if w["towns"][tid]["faction"] == fid:
				towns.append(tid)
				if w["towns"][tid]["capital"]:
					capital = tid
		w["factions"][fid] = {"strength": 1.0, "towns": towns, "capital": capital}
	Diplomacy.init_world(game)   # diplomacy: relations at baseline +-10, company standings; sets w["wars"]
	compute_road_links(w)

static func _generate_town(game, tid: String, seed_v: int, grng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var t: Dictionary = w["towns"][tid]
	var others := []
	for oid in w["towns"]:
		var o: Dictionary = w["towns"][oid]
		if o["culture"] != t["culture"]:
			others.append([t["pos"].distance_to(o["pos"]), o["culture"]])
	others.sort_custom(func(a, b): return a[0] < b[0])
	var neigh := []
	for o in others:
		if not neigh.has(o[1]):
			neigh.append(o[1])
		if neigh.size() >= 2:
			break
	t["neighbours"] = neigh
	Economy.make_crafters(t, grng)
	Economy.roll_prices(t, grng)
	# economy spec 1: families, land, businesses, stocks (own rng so the rest of world gen is unchanged)
	var erng := RandomNumberGenerator.new()
	erng.seed = hash([seed_v, tid, "econ"])
	EconGen.generate(w, t, erng)
	Economy.refresh_town(t, 0.0, grng)
	t["next_refresh"] = Economy.REFRESH_DAYS + grng.randf_range(-1.0, 1.0)

static func _generate_party(game) -> void:
	var w: Dictionary = game.world
	var start := ""
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] == "middle_kingdom" and (start == "" or not t["capital"]):
			start = tid
	var spos: Vector2 = w["towns"][start]["pos"] if start != "" else Vector2(WorldGen.W, WorldGen.H) * WorldGen.CELL * 0.5
	w["party"] = {"pos": nearest_passable(w, spos + Vector2(36, 30)), "target": spos, "path": [], "dest_town": "",
		"arrived": "", "safe_until": 0.0, "waiting": false, "objective": "hold_capital"}
	w["start_town"] = start

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

# ================================================================== strength / scouting
## Rough fighting value of one unit; gear counts heavily because gear IS difficulty.
static func unit_power(u: Unit) -> float:
	if u.dead or (u.sick_bed and u.bedridden(float(Game.day))):   # sickness: a bed-ridden man is off duty
		return 0.0
	if u.race_def().get("creature", false):   # monsters wave 1: creatures carry no gear
		return Creatures.power(u)
	var a := (u.attr("STR") + u.attr("AGI") + u.attr("TOU") + u.attr("END")) / 4000.0
	var best := 0
	for s in DB.WEAPON_SKILLS:
		best = maxi(best, u.skill(s))
	var sk := best * 0.06 + u.skill("fighter") * 0.03 + u.skill("dodger") * 0.02 + u.skill("shield_user") * 0.02 + u.skill("armor_user") * 0.02
	var gear := 0.0
	for slot in u.equip:
		var it: Item = u.equip[slot]
		if it.mat().get("kind", "") != "metal":
			continue
		var m := 1.0 if it.material == "copper" else 0.6
		gear += (0.35 if slot == "main_hand" else 0.15) * m * DB.quality_mult(it.quality)
	return a * (1.0 + sk) * (1.0 + gear)

static func band_power(units: Array) -> float:
	var p := 0.0
	for u in units:
		p += unit_power(u)
	return p

static func party_power(game) -> float:
	return band_power(game.deployed_units())

static func approx_count(n: int) -> String:
	if n <= 2: return "one or two"
	if n <= 5: return "a handful (3-5)"
	if n <= 9: return "under a dozen (6-9)"
	if n <= 14: return "about a dozen"
	if n <= 20: return "a score or so"
	return "a horde"

## "lightly armoured, mostly tin, crude work"
static func gear_impression(units: Array) -> String:
	var n := 0; var armour := 0; var metal := 0; var tin := 0; var q := 0
	for u in units:
		if u.dead:
			continue
		n += 1
		for slot in u.equip:
			var it: Item = u.equip[slot]
			if it.mat().get("kind", "") != "metal":
				continue
			metal += 1
			q += it.quality
			if it.material == "tin":
				tin += 1
			if slot != "main_hand":
				armour += 1
	if n == 0:
		return "nothing left"
	var parts := []
	var apu := float(armour) / n
	parts.append("heavily armoured" if apu >= 2.5 else ("lightly armoured" if apu >= 0.8 else "barely armoured"))
	if metal > 0:
		var tf := float(tin) / metal
		parts.append("mostly dull tin" if tf > 0.65 else ("mixed tin and copper" if tf > 0.3 else "bright copper"))
		var aq := float(q) / metal
		parts.append("masterwork" if aq >= 3.0 else ("fine work" if aq >= 2.0 else ("decent work" if aq >= 1.0 else "crude work")))
	else:
		parts.append("no metal to speak of")
	return ", ".join(parts)

static func relative_strength(game, units: Array) -> String:
	var r := band_power(units) / maxf(0.01, party_power(game))
	if r < 0.5: return "much weaker than us"
	if r < 0.85: return "weaker than us"
	if r < 1.2: return "an even match"
	if r < 1.8: return "stronger than us"
	return "far stronger than us"

## What the player sees when tapping a warband.
static func scout_report(game, wid: String) -> Dictionary:
	var wb: Dictionary = game.world["warbands"].get(wid, {})
	if wb.is_empty():
		return {}
	var units: Array = wb["units"]
	var alive := units.filter(func(u): return not u.dead)
	var fid: String = wb["faction"]
	var disp := Diplomacy.disposition(game, fid)   # hostile | neutral | friendly
	if wb.get("deserter", false):   # monsters wave 1: deserters are hostile whatever their old faction thinks
		disp = "hostile"
	var kind_txt: String = {"patrol": "patrol", "raider": "raiding party", "contract": "contract target",
		"assault": "assault force", "caravan": "merchant caravan"}.get(wb["kind"], "warband")
	var mk := Monsters.kind_text(wb)   # monsters wave 1: packs, dens, camps, gangs, deserters, militia
	if mk != "":
		kind_txt = mk
	var race: String = alive[0].race if not alive.is_empty() and Monsters.is_monster_band(wb) else DB.factions[fid]["race"]
	var fname := faction_name(fid) if not Monsters.is_monster_band(wb) else ""
	return {"id": wid, "faction": fid, "faction_name": fname, "kind": wb["kind"], "kind_text": kind_txt,
		"title": (kind_txt.substr(0, 1).to_upper() + kind_txt.substr(1) + "!") if fname == "" else "%s %s!" % [fname, kind_txt],
		"count_text": approx_count(alive.size()), "gear_text": gear_impression(alive) if not Monsters.is_monster_band(wb) else "teeth and claws",
		"disposition": disp, "strength_text": relative_strength(game, alive), "race": race,
		"is_contract_target": game.contract.get("target_id", "") == wid,
		"home": wb.get("home", ""), "home_text": home_text(game.world, wb),
		"cargo_text": Caravans.cargo_text(wb.get("cargo", {}), float(wb.get("gold", 0.0))) if wb["kind"] == "caravan" else "",
		"supply": TownEcon.supply_word(TownEcon.force_supply(game.world, wb))}

## "from Fengate, the Kingdom of the Middle March"
static func home_text(w: Dictionary, wb: Dictionary) -> String:
	var mh := Monsters.home_text(w, wb)   # monsters wave 1: lair / camp homes
	if mh != "":
		return mh
	var t: Dictionary = w["towns"].get(str(wb.get("home", "")), {})
	return "from %s, %s" % [t.get("name", "the wilds"), faction_the(wb["faction"])]

# ================================================================== warbands
static func spawn_warband(game, fid: String, pos: Vector2, count: int, kind: String, rng: RandomNumberGenerator, extra: Dictionary = {}) -> String:
	if Monsters.suspended_band({"faction": fid, "kind": kind, "units": extra.get("units", [])}): return ""
	var w: Dictionary = game.world
	var id := new_id(w, "wb")
	# monsters wave 1: extra["units"] = ready-made units (creatures, militia, armed outlaws)
	var _t0 := Time.get_ticks_usec()
	var units: Array = extra.get("units", [])
	if not extra.has("units"):
		var native_home := String(extra.get("home", ""))
		if not w["towns"].has(native_home): native_home = nearest_faction_town(w, fid, pos)
		for i in maxi(1, count):
			units.append(make_resident_troop(rng, fid, w["towns"].get(native_home, {})))
	if TownEcon.prof_on: _t0 = TownEcon._prof("sw_make_" + kind, _t0)
	var p := nearest_passable(w, pos)
	var wb := {"id": id, "faction": fid, "pos": p, "units": units, "kind": kind, "home": "", "anchor": p,
		"path": [], "rest_until": 0.0, "idle_until": 0.0, "repath_at": 0.0, "mode": "wander",
		"march_day": 0.0, "target_town": "", "contract_id": ""}
	wb.merge(extra, true)
	WarAI.sync_objective(wb, float(game.day))
	# every force belongs to a home town of its faction (Douglas), and so do its people
	# (monsters wave 1: bandits' home is their camp; monsters belong to a lair or to none)
	if not w["towns"].has(wb["home"]) and not w.get("lairs", {}).has(wb["home"]) and not Monsters.is_monster_faction(fid):
		wb["home"] = nearest_faction_town(w, fid, p)
	for u in units:
		u.home_town = wb["home"]
	w["warbands"][id] = wb
	if w.has("army"):
		_t0 = Time.get_ticks_usec()
		Army.enlist(game, wb)   # economy spec 2: every person in the force is a real family member (not monsters)
		if TownEcon.prof_on: TownEcon._prof("sw_enlist_" + kind, _t0)
		if (wb["units"] as Array).is_empty():
			w["warbands"].erase(id)   # war pick 4: the town could spare nobody: not raised
			return ""
	return id

## Nearest town of a faction to pos (any town when the faction has none).
static func nearest_faction_town(w: Dictionary, fid: String, pos: Vector2) -> String:
	var best := ""; var bd := INF
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if t["faction"] != fid:
			continue
		var d: float = (t["pos"] as Vector2).distance_to(pos)
		if d < bd:
			bd = d; best = tid
	return best if best != "" else nearest_town(w, pos)

## from_stock (economy spec 11): a band raised during the campaign takes its gear out of its home town's arms
## stock (the treasury pays the market); the bands of world generation keep their rolled gear (pre-history).
## staged: tests' perf scenes only (Army.enlist: the band is put on the map whole, not drafted).
## muster_head (world size): the band is raised over several work jobs (see muster_start); returns "" (the band goes
## on the map when its last job runs).
static func field_target(w: Dictionary, day: float = 0.0) -> int:
	return mini(FIELD_LIMIT, int(BAND_SIZE.get(String(w.get("size", "normal")), 100)) +
		maxi(0, int(day / 7.0)) * FIELD_WEEKLY_GROWTH)

## Residence determines the body/template; allegiance does not change a person's race.
static func make_resident_troop(rng: RandomNumberGenerator, fid: String, town: Dictionary, wealth: int = -1) -> Unit:
	var race := Persons.race_of(town["econ"]) if TownEcon.has_econ(town) else String(DB.factions[fid]["race"])
	var source := fid
	if String(DB.factions[fid].get("race", "")) != race:
		for candidate in DB.factions:
			if String(DB.factions[candidate].get("race", "")) == race and not Monsters.is_monster_faction(candidate):
				source = candidate; break
	var u := Factory.make_troop(rng, source, Factory.pick_troop(rng, source), wealth)
	u.faction = fid
	return u

## Replacements reserve household food at home and must be able to buy a three-day mess plus wages.
static func supported_field_count(game, fid: String, town: Dictionary, target: int) -> int:
	if not TownEcon.has_econ(town): return 0
	var n := mini(target, Population.available(town))
	var e: Dictionary = town["econ"]
	var stock: Dictionary = e.get("stock", {})
	var meals := 0
	var cheapest := INF
	for good in Supplies.FOOD:
		var q := maxi(0, int(stock.get(good, 0)))
		meals += q
		if q > 0: cheapest = minf(cheapest, float(e.get("price", {}).get(good, 1.0)))
	n = mini(n, meals / 12)   # half stays in the home market; six meals per departing soldier
	var cash := float(game.world.get("factions", {}).get(fid, {}).get("treasury", 0.0))
	var reserve := Army.bill(game, fid) * 3.0
	var cost := Army.wage("army", 0) * float(Army.A()["desert_days"]) + 6.0 * maxf(0.01, cheapest)
	if n > 0: n = mini(n, maxi(0, int((cash - reserve) / cost)))
	return n if n > 0 and Army.can_raise(game, fid, n) else 0

static func spawn_faction_band(game, fid: String, rng: RandomNumberGenerator, from_stock: bool = false, staged: bool = false,
		muster_head: Array = []) -> String:
	var w: Dictionary = game.world
	var towns: Array = w["factions"].get(fid, {}).get("towns", [])
	if towns.is_empty():
		return ""
	var home: String = towns[rng.randi() % towns.size()]
	var pools := {}   # the pool looked at here is the one the draft takes from (built once per raising)
	if not staged and TownEcon.has_econ(w["towns"][home]):
		var pl := People.draft_pool(w["towns"][home])
		if not pl.is_empty():
			pools[home] = pl
		else:
			for tid2 in towns:   # war pick 4: that town has no one to spare; the realm raises the band where men can go
				if tid2 == home or not TownEcon.has_econ(w["towns"][tid2]):
					continue
				var pl2 := People.draft_pool(w["towns"][tid2])
				if not pl2.is_empty():
					home = tid2
					pools[home] = pl2
					break
	var n := field_target(w, float(game.day) if from_stock else 0.0)
	if not staged:
		if pools.is_empty(): return ""
		n = mini(n, (pools[home] as Array).size())
		if from_stock: n = supported_field_count(game, fid, w["towns"][home], n)
		else: n = mini(n, Population.available(w["towns"][home]))
		if n <= 0: return ""
	var kind := "raider" if DB.factions[fid].get("player_hostile", false) else "patrol"
	var pos: Vector2 = w["towns"][home]["pos"] + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
	var extra := {"home": home, "staged": true} if staged else {"home": home}
	if not muster_head.is_empty():
		muster_start(game, muster_head, fid, pos, n, kind, extra, rng, false,
			{"then": "band", "outfit": from_stock and TownEcon.has_econ(w["towns"][home]), "pools": pools})
		return ""
	var wid := spawn_warband(game, fid, pos, n, kind, rng, extra)
	if wid != "" and from_stock and TownEcon.has_econ(w["towns"][home]):   # ("": nobody to spare, war pick 4)
		TownEcon.outfit_units(w["towns"][home], w["warbands"][wid]["units"])
	return wid

# ================================================================== the muster (world size)
## A force raised over several work jobs, so no single map frame makes a whole band (a unit is a big record: making
## one, drafting him from his family and outfitting him from the stalls was 46 ms a band on a large world). Each job
## makes MUSTER_STEP men, then drafts MUSTER_STEP (Army.enlist_some), then outfits MUSTER_STEP; the force goes on the
## map when its last job runs, exactly as one spawn would have left it. The next job goes to the FRONT of the queue:
## a big time jump (the years before, resting in town) runs the jobs back to back, with the same random draws in the
## same order as the single job they replace; on the map one job a frame, and the war, the clashes and the other jobs
## of the frames between see no half-raised force (it is not in w.warbands until done).
## The state m rides on the queue entry (muster_head + [m]): plain data and the men made so far, saved like the
## warbands. own_rng: the force draws from its own seeded generator (arms convoys), its state kept in m; else
## from the world's generator of the frame (on_time's).
const MUSTER_STEP := 3

static func muster_start(game, head: Array, fid: String, pos: Vector2, count: int, kind: String, extra: Dictionary,
		rng: RandomNumberGenerator, own_rng: bool, then: Dictionary) -> void:
	if Monsters.suspended_band({"faction": fid, "kind": kind, "units": extra.get("units", [])}): return
	var w: Dictionary = game.world
	var m := {"id": new_id(w, "wb"), "fid": fid, "pos": pos, "n": maxi(1, count), "kind": kind, "extra": extra, "units": [],
		"stage": "make"}
	m.merge(then, true)
	if own_rng:
		m["rs"] = str(rng.state)
	muster_step(game, head + [m], rng)

## The forces being raised: their men (Army.sweep must not count them dead; Caravans.count counts the caravans).
static func mustering(w: Dictionary) -> Array:
	var out := []
	for j in w.get("work", []):
		if (j as Array).size() > 2 and j[-1] is Dictionary and (j[-1] as Dictionary).has("stage"):
			out.append(j[-1])
	return out

static func mustering_units(w: Dictionary) -> Array:
	var out := []
	for m in mustering(w):
		if m.has("wb"):
			out.append_array(m["wb"]["units"])
		else:
			out.append_array(m["units"])
	return out

## One muster job: a step of the force's raising. Queues the next at the front of the queue unless it is done.
static func muster_step(game, job: Array, frame_rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var m: Dictionary = job[-1]
	var rng := frame_rng
	if m.has("rs"):
		rng = RandomNumberGenerator.new()
		rng.state = String(m["rs"]).to_int()
	var more := _muster_part(game, m, rng)
	if m.has("rs"):
		m["rs"] = str(rng.state)
	if more:
		(w["work"] as Array).push_front(job)

## Returns true while there is more to do.
static func _muster_part(game, m: Dictionary, rng: RandomNumberGenerator) -> bool:
	var w: Dictionary = game.world
	var fid := String(m["fid"])
	if Monsters.suspended_band({"faction": fid, "kind": m.get("kind", ""), "units": m.get("units", [])}): return false
	match String(m["stage"]):
		"make":   # Factory.make_warband, MUSTER_STEP men a job
			var units: Array = m["units"]
			for _k in MUSTER_STEP:
				if units.size() >= int(m["n"]):
					break
				var town: Dictionary = w["towns"].get(String(m["extra"].get("home", "")), {})
				units.append(make_resident_troop(rng, fid, town))
			if units.size() < int(m["n"]):
				return true
			# the rest of spawn_warband up to the draft
			var p := nearest_passable(w, m["pos"])
			var wb := {"id": m["id"], "faction": fid, "pos": p, "units": units, "kind": m["kind"], "home": "", "anchor": p,
				"path": [], "rest_until": 0.0, "idle_until": 0.0, "repath_at": 0.0, "mode": "wander",
				"march_day": 0.0, "target_town": "", "contract_id": ""}
			wb.merge(m["extra"], true)
			WarAI.sync_objective(wb, float(game.day))
			if not w["towns"].has(wb["home"]) and not w.get("lairs", {}).has(wb["home"]) and not Monsters.is_monster_faction(fid):
				wb["home"] = nearest_faction_town(w, fid, p)
			for u in units:
				u.home_town = wb["home"]
			m.erase("units"); m.erase("extra")
			m["wb"] = wb
			var ctx := Army.enlist_begin(game, wb, m.get("pools", {})) if w.has("army") else {}
			m.erase("pools")
			if ctx.is_empty():
				m["stage"] = "drafted"
				return _muster_part(game, m, rng)
			m["ctx"] = ctx
			m["stage"] = "draft"
			return true
		"draft":   # Army.enlist, MUSTER_STEP men a job
			var wb: Dictionary = m["wb"]
			if not Army.enlist_some(game, wb, m["ctx"], MUSTER_STEP):
				return true
			Army.enlist_end(game, wb, m["ctx"])
			m.erase("ctx")
			m["stage"] = "drafted"
			return _muster_part(game, m, rng)
		"drafted":
			var wb: Dictionary = m["wb"]
			if (wb["units"] as Array).is_empty():   # war pick 4: the town could spare nobody: not raised
				return _muster_done(game, m, "", rng)
			if String(m.get("then", "")) == "band" and m.get("outfit", false):
				m["stage"] = "outfit"
				m["oi"] = 0
				m["ob"] = int(floor(float((w["towns"][wb["home"]].get("shop", []) as Array).size()) * 0.5))
				return true
			w["warbands"][m["id"]] = wb
			return _muster_done(game, m, String(m["id"]), rng)
		"outfit":   # TownEcon.outfit_units from the home town's stock, MUSTER_STEP men a job (one share for the band)
			var wb: Dictionary = m["wb"]
			var town: Dictionary = w["towns"][wb["home"]]
			var units: Array = wb["units"]
			var i0 := int(m["oi"])
			var i1 := mini(units.size(), i0 + MUSTER_STEP)
			m["ob"] = int(m["ob"]) - TownEcon.outfit_units(town, units.slice(i0, i1), 0.5, true, int(m["ob"]), false)
			m["oi"] = i1
			if i1 < units.size():
				return true
			BowsEcon.fill_quivers(town, units)   # bows: quivers from the town's arrows (the whole band at once, as before)
			w["warbands"][m["id"]] = wb
			return _muster_done(game, m, String(m["id"]), rng)
	return false

## The force is on the map (wid; "" when nobody could be raised): what its raiser does next.
static func _muster_done(game, m: Dictionary, wid: String, rng: RandomNumberGenerator) -> bool:
	match String(m.get("then", "")):
		"caravan":
			if wid != "":
				wid = Caravans.sail(game, wid, rng)
	m["stage"] = "done"
	return false

static func remove_warband(game, wid: String) -> void:
	game.world["warbands"].erase(wid)
	if game.world.get("encounter", "") == wid:
		game.world["encounter"] = ""

static func _wander_target(game, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var w: Dictionary = game.world
	var base: Vector2 = wb["anchor"]
	var radius := 260.0
	match wb["kind"]:
		"patrol":
			if w["towns"].has(wb["home"]):
				base = w["towns"][wb["home"]]["pos"]
			# diplomacy: at WAR, patrols sometimes go after enemy caravans and prowl enemy towns
			if rng.randf() < 0.35 and not Diplomacy.enemies_at_war(w, wb["faction"]).is_empty():
				var prey := _war_prey(w, wb, rng)
				if prey != Vector2.INF:
					return prey
		"raider":
			# prowl near enemy towns (or the home region)
			var targets := []
			for tid in w["towns"]:
				var t: Dictionary = w["towns"][tid]
				if at_war(w, wb["faction"], t["faction"]) and t["pos"].distance_to(wb["pos"]) < 900:
					targets.append(t["pos"])
			# caravans in reach are the best prey
			for cid in w["warbands"]:
				var car: Dictionary = w["warbands"][cid]
				if car["kind"] == "caravan" and (car["pos"] as Vector2).distance_to(wb["pos"]) < 450.0 and Caravans.is_prey(w, wb, car):
					var ahead: Array = car["path"]
					return ahead[mini(2, ahead.size() - 1)] if not ahead.is_empty() else car["pos"]
			if not targets.is_empty() and rng.randf() < 0.6:
				base = targets[rng.randi() % targets.size()]
				radius = 180.0
			elif w["towns"].has(wb["home"]):
				base = w["towns"][wb["home"]]["pos"]
				radius = 380.0
		"contract":
			radius = 110.0
		"bandit":   # monsters wave 1
			return Bandits.wander_target(game, wb, rng)
		"deserter":
			return Bandits.deserter_target(game, wb, rng)
	return base + Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))

## Diplomacy: an enemy town nearby to prowl; Vector2.INF when none. (Enemy forces, caravans included, are hunted
## by campaign/war_ai.gd: sight, tracks, word, lead interception.)
static func _war_prey(w: Dictionary, wb: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if (t["pos"] as Vector2).distance_to(wb["pos"]) < 700.0 and at_war(w, wb["faction"], t["faction"]):
			return t["pos"] + Vector2(rng.randf_range(-120, 120), rng.randf_range(-120, 120))
	return Vector2.INF

## Size is O(1): field rosters remove casualties; never scan individual soldiers during movement.
static func travel_speed(base: float, men: int) -> float:
	return base * clampf(1.0 - 0.35 * log(maxf(1.0, float(men) / 100.0)) / log(10.0), 0.45, 1.0)

static func _step_along(w: Dictionary, obj: Dictionary, dist: float) -> bool:
	## All band walkers pass their base distance here; apply army size exactly once, including militia/convoys.
	## The party has no units array, so _move_party supplies its size-adjusted distance.
	if obj.has("units"):
		dist = travel_speed(dist, (obj["units"] as Array).size())
	var path: Array = obj["path"]
	while dist > 0.0 and not path.is_empty():
		var p: Vector2 = obj["pos"]
		var q: Vector2 = path[0]
		var d := p.distance_to(q)
		if d <= dist:
			obj["pos"] = q
			dist -= d
			path.pop_front()
		else:
			obj["pos"] = p + (q - p) / d * dist
			dist = 0.0
	return path.is_empty()

static func _move_warbands(game, dt: float, t: float, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var party: Dictionary = w["party"]
	var ppow := -1.0
	for wid in w["warbands"].keys():
		var wb: Dictionary = w["warbands"].get(wid, {})
		if wb.is_empty() or Monsters.suspended_band(wb) or wid == w.get("encounter", ""):
			continue
		WarAI.sync_objective(wb, t)
		if float(wb["rest_until"]) > t:
			continue
		if wb["kind"] == "caravan":
			Caravans.step(game, wid, wb, dt)
			continue
		if Monsters.step_band(game, wid, wb, dt, t, rng, true):   # identical suspension check already completed above
			continue
		if wb["kind"] == "assault":
			if t < float(wb["march_day"]):
				continue
			var wm := WarAI.control(game, wid, wb, t)   # war: a war band falls on enemy forces it sees on the march
			if wm >= 0.0:
				_step_along(w, wb, WARBAND_SPEED * wm * smooth_speed(w, wb, dt) * dt)
				continue
			var town: Dictionary = w["towns"].get(wb["target_town"], {})
			if town.is_empty():
				wb["kind"] = "raider"
				continue
			if (wb["path"] as Array).is_empty():
				wb["path"] = find_path(w, wb["pos"], town["pos"])
			_step_along(w, wb, WARBAND_SPEED * smooth_speed(w, wb, dt) * dt)
			if (wb["pos"] as Vector2).distance_to(town["pos"]) < 20.0:
				_assault_arrives(game, wid)
			continue
		var mode := "wander"
		# The geometry is unused while the company is protected or in town.
		if float(party["safe_until"]) <= t and game.location == "" \
				and (wb["pos"] as Vector2).distance_to(party["pos"]) < WARBAND_SIGHT and Monsters.band_hostile(game, wb):
			if ppow < 0.0:
				ppow = party_power(game)
			var bp := band_power(wb["units"])
			if bp >= ppow * 1.0:
				mode = "chase"
			elif bp < ppow * 0.6 and wb["kind"] != "contract":
				mode = "flee"
		if mode != wb["mode"]:
			wb["mode"] = mode
			wb["path"] = []
			wb["repath_at"] = 0.0
			WarAI.sync_objective(wb, t)
		var speed := WARBAND_SPEED * smooth_speed(w, wb, dt)
		match mode:
			"chase":
				if t >= float(wb["repath_at"]):
					# war interception: head for where the company will be along its route, not where it is
					var aim := WarAI.lead_point(wb["pos"], travel_speed(WARBAND_SPEED, (wb["units"] as Array).size()) * maxf(0.5, float(wb.get("spd", 1.0))), party["pos"],
						party["path"], travel_speed(PARTY_SPEED, game.company.size()) * float(party.get("spd", 1.0)) if game.location == "" else 0.0)
					wb["path"] = find_path(w, wb["pos"], aim)
					wb["repath_at"] = t + 0.15
				_step_along(w, wb, speed * dt)
			"flee":
				if t >= float(wb["repath_at"]) or (wb["path"] as Array).is_empty():
					var away: Vector2 = ((wb["pos"] as Vector2) - party["pos"]).normalized()
					wb["path"] = find_path(w, wb["pos"], wb["pos"] + away * 250.0)
					wb["repath_at"] = t + 0.3
				_step_along(w, wb, speed * 0.95 * dt)
			_:
				var wm := WarAI.control(game, wid, wb, t)   # war: hunt, shadow, avoid, fall back home (decisions amortised)
				if wm >= 0.0:
					if wm > 0.0:
						_step_along(w, wb, speed * wm * dt)
					continue
				if (wb["path"] as Array).is_empty():
					if float(wb["idle_until"]) > t:
						continue
					wb["path"] = find_path(w, wb["pos"], _wander_target(game, wb, rng))
					if (wb["path"] as Array).is_empty():
						wb["idle_until"] = t + 0.5
						continue
				if _step_along(w, wb, speed * 0.8 * dt):
					wb["idle_until"] = t + rng.randf_range(0.2, 0.9)

## Warbands of factions at war fight when they meet (auto-resolved).
static func _warband_clashes(game, t: float, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	var ids: Array = []
	for k in w["warbands"]:   # monsters wave 1: militia/packs/dens/camps fight through Militia.tick instead
		# These native kinds never enter this resolver. Reject them before an
		# otherwise unused full-roster creature scan; both predicates are pure.
		if not w["warbands"][k]["kind"] in Monsters.NO_CLASH and not Monsters.suspended_band(w["warbands"][k]):
			ids.append(k)
	var enc: String = w.get("encounter", "")
	var pairs := _clash_pairs(w, ids)
	for pr in pairs:
		var i: int = pr.x; var j: int = pr.y
		var a: Dictionary = w["warbands"].get(ids[i], {})
		var b: Dictionary = w["warbands"].get(ids[j], {})
		if a.is_empty() or b.is_empty():
			continue
		if ids[i] == enc or ids[j] == enc:
			continue
		var car: Dictionary = a if a["kind"] == "caravan" else (b if b["kind"] == "caravan" else {})
		if not car.is_empty():
			var att: Dictionary = b if car["id"] == a["id"] else a
			if not Caravans.is_prey(w, att, car) or float(att["rest_until"]) > t:
				continue
			if Caravans.escort_near(game, car):
				# the company stands with the caravan it escorts: battle, guards as allies
				if enc == "":
					att["escort_fight"] = car["id"]
					w["encounter"] = att["id"]
					enc = att["id"]
					w["party"]["path"] = []
					w["party"]["dest_town"] = ""
				continue
		elif not Diplomacy.fights(w, a["faction"], b["faction"]) and not Monsters.extra_fight(a, b):
			continue   # diplomacy: WAR or HOSTILE fight on contact; monsters wave 1: outlaws vs all, deserters vs their old faction
		var pa := band_power(a["units"]); var pb := band_power(b["units"])
		if car.is_empty():   # diplomacy: allied bands close by join the fight (only computed on contact)
			pa += Diplomacy.ally_power(w, a["faction"], b["faction"], a["pos"], [ids[i], ids[j]])
			pb += Diplomacy.ally_power(w, b["faction"], a["faction"], b["pos"], [ids[i], ids[j]])
		pa += WarAI.pack_power(w, a, b["id"], [ids[i], ids[j]])   # war: own bands closing on the same target join in
		pb += WarAI.pack_power(w, b, a["id"], [ids[i], ids[j]])
		# Rounds (campaign/clash_rounds.gd): 100 v 100 until one army's morale or numbers break.
		var na := (a["units"] as Array).size(); var nb := (b["units"] as Array).size()
		var cr := ClashRounds.resolve(na, nb, pa / maxf(1.0, float(na)), pb / maxf(1.0, float(nb)), _officer_count(a), _officer_count(b), rng,
			70.0, 70.0, terrain_at(w, a["pos"]), BattleTactics.commander_tactician(game, a["units"], 0), BattleTactics.commander_tactician(game, b["units"], 1))
		var win := a if str(cr["winner"]) == "a" else b
		var lose := b if win == a else a
		var wrep: Dictionary = cr["a"] if win == a else cr["b"]
		var lrep: Dictionary = cr["b"] if win == a else cr["a"]
		var fought_n := mini(na, nb) * int(cr["rounds"])
		ArmsPool.after_clash(game, str(win["faction"]), fought_n, true, int(wrep["dead"]))
		ArmsPool.after_clash(game, str(lose["faction"]), fought_n, false, int(lrep["dead"]))
		# the census: the men who die in this clash (now, or later when the army sweep finds them gone) died here
		var cwhere := nearest_town_name(w, lose["pos"])
		var cdetail := ("%s raided a caravan of %s near %s" if lose["kind"] == "caravan" else "%s beat %s near %s") % [
			faction_the(win["faction"]), faction_the(lose["faction"]), cwhere]
		Census.ctx("battle", cdetail)
		var told := WarAI.on_clash(game, a, b, win)   # war: news line when one side ran the other down
		var losses := int(wrep["dead"])
		if lose["kind"] != "caravan":   # diplomacy: grievance -4 and the men lost count toward war weariness
			Diplomacy.on_army_destroyed(w, lose["faction"], win["faction"], losses + int(lrep["dead"]) + int(lrep["captured"]))
		var fallen := []   # arms trade: the winners' dead (their kit stays with whoever holds the field)
		for k in losses:
			if (win["units"] as Array).size() > 1:
				fallen.append((win["units"] as Array).pop_at(rng.randi() % (win["units"] as Array).size()))
		win["rest_until"] = t + 0.5
		Army.survived(win)   # economy spec 2: a battle survived (veteran / blooded at the faction's day)
		var holder := {} if Monsters.is_monster_band(win) else {"band": win}
		Census.note_fates(w, fallen, "battle", cdetail)
		if lose["kind"] == "caravan":
			ArmsTrade.field(game, fallen, holder, lose["pos"])
			if not holder.is_empty():
				ArmsTrade.plunder_cargo(game, win, lose)   # arms trade: the guards' kit and a share of the arms cargo
			Bandits.on_plunder(game, win, lose)   # monsters wave 1: a gang carries the cargo to its camp
			Army.on_plunder(w, win, lose)   # economy spec 2: food and drink into the winner's stores, the purse to its chest
			Caravans.lost(game, lose["id"], win["faction"])
			Census.ctx_end()
			continue
		Supplies.take(win, lose)   # the winner takes the beaten force's stores, up to what it can carry
		Army.fight_pay(game, lose, 1.0)
		var ldead := []
		for k in int(lrep["dead"]):
			if (lose["units"] as Array).is_empty(): break
			ldead.append((lose["units"] as Array).pop_at(rng.randi() % (lose["units"] as Array).size()))
		for k in int(lrep["captured"]):   # taken, then ransomed home by their families
			if (lose["units"] as Array).is_empty(): break
			Army.release(game, (lose["units"] as Array).pop_at(rng.randi() % (lose["units"] as Array).size()), "fled")
		Census.note_fates(w, ldead, "battle", cdetail)
		ArmsTrade.field(game, fallen + ldead, holder, lose["pos"])   # arms trade: the dead's kit to the victors (Loot.spoils)
		if win["kind"] == "caravan":
			win["rest_until"] = t   # merchants keep moving
		weaken_faction(w, lose["faction"], ldead.size() + int(lrep["captured"]))
		var where := nearest_town_name(w, lose["pos"])
		if BattleRounds.retreat_band(game, lose):
			if not told:
				log_event(game, "A band of %s beat a band of %s near %s in %d rounds; the beaten fell back home to regroup." % [faction_the(win["faction"]), faction_the(lose["faction"]), where, int(cr["rounds"])])
		else:
			if not told:
				log_event(game, "A band of %s destroyed a band of %s near %s." % [faction_the(win["faction"]), faction_the(lose["faction"]), where])
			remove_warband(game, lose["id"])
		Census.ctx_end()

static func _officer_count(wb: Dictionary) -> int:
	var n := 0
	for u in wb["units"]:
		if u is Unit and u.role in ["captain", "officer"]: n += 1
	return n

static func _clash_pairs(w: Dictionary, ids: Array) -> Array:
	# The pairs in contact, found by a sweep along x (bands are sorted by x once; a pair further apart in x than
	# CONTACT is never in contact), then resolved in the same (i, j) order the plain double loop used: same fights,
	# same rolls, a fraction of the distance tests on the 1.5x map with its many bands (war pick 5)
	var xs := []
	var positions := []   # these positions cannot change until all pairs have been collected
	for i in ids.size():
		var pos: Vector2 = w["warbands"][ids[i]]["pos"]
		positions.append(pos)
		xs.append(Vector2(pos.x, i))
	xs.sort()   # native Vector2 order: x, then band index (pair resolution is sorted below)
	var pairs := []
	for m in xs.size():
		var mi := int(xs[m].y)
		var pm: Vector2 = positions[mi]
		for q in range(m + 1, xs.size()):
			if float(xs[q].x) - pm.x > CONTACT:
				break
			var qi := int(xs[q].y)
			if pm.distance_squared_to(positions[qi]) <= CONTACT * CONTACT:
				pairs.append(Vector2i(mini(mi, qi), maxi(mi, qi)))
	pairs.sort()
	return pairs

static func weaken_faction(w: Dictionary, fid: String, size: int) -> void:
	var f: Dictionary = w["factions"].get(fid, {})
	if f.is_empty():
		return
	f["strength"] = clampf(float(f["strength"]) - 0.06 - 0.015 * size, 0.2, 1.5)

## town.road_links = [{id, faction, dist}] for every town joined to it by a road (caravans, escort offers).
static func compute_road_links(w: Dictionary) -> void:
	for tid in w["towns"]:
		w["towns"][tid]["road_links"] = []
	for r in w.get("roads", []):
		var a: Dictionary = w["towns"].get(r["a"], {})
		var b: Dictionary = w["towns"].get(r["b"], {})
		if a.is_empty() or b.is_empty():
			continue
		var pts: Array = r["pts"]
		var d := path_length(pts[0], pts) if not pts.is_empty() else (a["pos"] as Vector2).distance_to(b["pos"])
		(a["road_links"] as Array).append({"id": b["id"], "faction": b["faction"], "dist": d})
		(b["road_links"] as Array).append({"id": a["id"], "faction": a["faction"], "dist": d})

static func nearest_town(w: Dictionary, pos: Vector2) -> String:
	var best := ""; var bd := INF
	for tid in w["towns"]:
		var d: float = w["towns"][tid]["pos"].distance_to(pos)
		if d < bd:
			bd = d; best = tid
	return best

static func nearest_town_name(w: Dictionary, pos: Vector2) -> String:
	var t := nearest_town(w, pos)
	return w["towns"][t]["name"] if t != "" else "the wilds"

static func _assault_arrives(game, wid: String) -> void:
	var w: Dictionary = game.world
	var wb: Dictionary = w["warbands"][wid]
	var town: Dictionary = w["towns"][wb["target_town"]]
	var party: Dictionary = w["party"]
	if wb.get("war_assault", false):   # diplomacy: a faction's own war band, no contract: militia vs raiders
		Diplomacy.war_assault_arrives(game, wid)
		return
	if (party["pos"] as Vector2).distance_to(town["pos"]) < 70.0 or game.location == town["id"]:
		w["encounter"] = wid     # the company stands with the town: battle
		party["path"] = []
		return
	# the town falls to the raid
	town["wealth"] = maxi(1, int(town["wealth"]) - 1)
	Diplomacy.on_town_attacked(w, town["faction"], wb["faction"], true)   # diplomacy: sacked -25
	Migration.note_attack(w, String(town["id"]), float(game.day))   # v0.034: its people fear for their lives
	log_event(game, "%s was sacked by %s." % [town["name"], faction_the(wb["faction"])])
	var c: Dictionary = game.contract
	if c.get("target_id", "") == wid:
		Contracts.fail(game, "%s was sacked before you arrived." % town["name"])
	wb["kind"] = "raider"
	wb["path"] = []
	wb["rest_until"] = game.day + 1.0

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

static func presim_days(years: int) -> int:
	return clampi(years, PRESIM_YEARS_MIN, PRESIM_YEARS_MAX) * PRESIM_YEAR_DAYS

## Years of this world's years before (the chosen length; the default for a world that has not begun them).
static func presim_years_of(game) -> float:
	return float(presim_total(game)) / PRESIM_YEAR_DAYS

static func presim_span_text(days: int) -> String:
	if days < PRESIM_YEAR_DAYS:
		return "%d day%s" % [days, "" if days == 1 else "s"]
	var years := days / PRESIM_YEAR_DAYS
	var rest := days % PRESIM_YEAR_DAYS
	var text := "%d year%s" % [years, "" if years == 1 else "s"]
	return text if rest == 0 else "%s, %d day%s" % [text, rest, "" if rest == 1 else "s"]

static func presim_total(game) -> int:
	return int(game.world.get("presim", {}).get("total", presim_span_days))

static func presim_left(game) -> int:
	var p: Dictionary = game.world.get("presim", {})
	if p.get("finished", false):
		return 0
	return presim_total(game) - int(p.get("done", 0))

## Runs up to n more days. Returns the days still to run.
static func presim_step(game, n: int) -> int:
	var w: Dictionary = game.world
	if not w.has("presim"):
		w["presim"] = {"total": presim_span_days, "done": 0, "from": game.day}
	var p: Dictionary = w["presim"]
	var k := mini(n, presim_left(game))
	for i in k:
		game.day += 1.0
		on_time(game, 1.0, true)
		w["encounter"] = ""
	p["done"] = int(p["done"]) + k
	return presim_left(game)

## A startup frame resumes the original day, rather than calling on_time with
## a smaller dt. Stop at each complete-day boundary so the chronicle cannot read
## partial same-day records. The budget is soft: one indivisible job may exceed it.
static func presim_slice(game, state: Dictionary, budget_usec: int) -> int:
	var w: Dictionary = game.world
	if presim_left(game) <= 0:
		return 0
	if state.is_empty():
		if not w.has("presim"):
			w["presim"] = {"total": presim_span_days, "done": 0, "from": game.day}
		game.day += 1.0
		state["run"] = _time_begin(game, 1.0, true)
	var start := Time.get_ticks_usec()
	var first := true
	while first or Time.get_ticks_usec() - start < maxi(0, budget_usec):
		first = false
		if _time_part(game, state["run"]):
			w["encounter"] = ""
			var p: Dictionary = w["presim"]
			p["done"] = int(p["done"]) + 1
			state.clear()
			break
	return presim_left(game)

## The player arrives: the company was made at the start and has not aged or eaten through the years before
## (its birth days and food clock move up to today); the run's length and wall time are kept for the record.
static func presim_finish(game, wall_ms: int = 0) -> void:
	var w: Dictionary = game.world
	var p: Dictionary = w.get("presim", {})
	var d := float(p.get("done", 0))
	for u in game.company:
		if u.born > -1.0e8:
			u.born += d
		var town: Dictionary = w.get("towns", {}).get(u.home_town, {})
		var f := People.fam_of(town, u.family)
		var rec := Persons.by_uid(f, u.uid) if not f.is_empty() else []
		if not rec.is_empty():
			rec[3] = int(round(u.born))
		u.age = People.age_on(u, game.day) if u.born > -1.0e8 else u.age
	game.food_clock = {"next": Food.next_tick_after(game.day), "last": game.day, "march": 0.0}
	p["finished"] = true
	p["wall_ms"] = wall_ms
	(w["party"] as Dictionary)["safe_until"] = game.day + 0.5
	w["encounter"] = ""
	# Initial dragon holdings belong to the living seats at the end of history.
	# Init is idempotent; visiting/choosing a city never mints another egg.
	Feudal.finish(game)
	Dragons.init_world(game)
	DragonCombat.prepare_world(game)
