class_name WorldPresim
extends RefCounted
## World generation slices and pre-history ("the years before") simulation helpers
## split from CampaignWorld (game/campaign/world.gd) to keep each file focused and under the size threshold.
## Structure only; all CampaignWorld.* entry points delegate here with identical behavior.

const GENERATION_STAGES := CampaignWorld.GENERATION_STAGES
const PATROLS := CampaignWorld.PATROLS
const PRESIM_YEARS := CampaignWorld.PRESIM_YEARS
const PRESIM_DEFAULT_DAYS := CampaignWorld.PRESIM_DEFAULT_DAYS
const PRESIM_YEARS_MIN := CampaignWorld.PRESIM_YEARS_MIN
const PRESIM_YEARS_MAX := CampaignWorld.PRESIM_YEARS_MAX
const PRESIM_YEAR_DAYS := CampaignWorld.PRESIM_YEAR_DAYS
const PRESIM_DAYS_MIN := CampaignWorld.PRESIM_DAYS_MIN
const PRESIM_DAYS_MAX := CampaignWorld.PRESIM_DAYS_MAX

# ================================================================== generation
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
	CampaignWorld.generation_parts_total_usec = 0
	CampaignWorld.generation_part_worst_usec = 0
	CampaignWorld.generation_part_count = 0
	return {"rng": grng, "seed": seed_v, "phase": 0, "i": 0}

static func generate_part(game, run: Dictionary) -> bool:
	var begin := Time.get_ticks_usec()
	var done := _generate_part(game, run)
	var elapsed := Time.get_ticks_usec() - begin
	CampaignWorld.generation_parts_total_usec += elapsed
	CampaignWorld.generation_part_worst_usec = maxi(CampaignWorld.generation_part_worst_usec, elapsed)
	CampaignWorld.generation_part_count += 1
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
				CampaignWorld.muster_step(game, job, grng)
				return false
			var fids: Array = run["patrols"]
			var i: int = run["i"]
			if i < fids.size():
				var fid := String(fids[i])
				if int(run["band_i"]) == 0:
					run["band_count"] = CampaignWorld.desired_bands(w, fid)
				if int(run["band_i"]) < int(run["band_count"]):
					CampaignWorld.spawn_faction_band(game, fid, grng, false, false, ["generate_patrol", fid])
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
	CampaignWorld.compute_road_links(w)

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
	w["party"] = {"pos": CampaignWorld.nearest_passable(w, spos + Vector2(36, 30)), "target": spos, "path": [], "dest_town": "",
		"arrived": "", "safe_until": 0.0, "waiting": false, "objective": "hold_capital"}
	w["start_town"] = start

# ================================================================== the years before (new campaigns)
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
	return int(game.world.get("presim", {}).get("total", CampaignWorld.presim_span_days))

static func presim_left(game) -> int:
	var p: Dictionary = game.world.get("presim", {})
	if p.get("finished", false):
		return 0
	return presim_total(game) - int(p.get("done", 0))

## Runs up to n more days. Returns the days still to run.
static func presim_step(game, n: int) -> int:
	var w: Dictionary = game.world
	if not w.has("presim"):
		w["presim"] = {"total": CampaignWorld.presim_span_days, "done": 0, "from": game.day}
	var p: Dictionary = w["presim"]
	var k := mini(n, presim_left(game))
	for i in k:
		game.day += 1.0
		CampaignWorld.on_time(game, 1.0, true)
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
			w["presim"] = {"total": CampaignWorld.presim_span_days, "done": 0, "from": game.day}
		game.day += 1.0
		state["run"] = CampaignWorld._time_begin(game, 1.0, true)
	var start := Time.get_ticks_usec()
	var first := true
	while first or Time.get_ticks_usec() - start < maxi(0, budget_usec):
		first = false
		if CampaignWorld._time_part(game, state["run"]):
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
