extends RefCounted
## Bounded native BattleSim survey; runner entry point is run(tree).
## --balance-suite=race|unit|mount|roster_matrix|sweep|campaign --balance-samples=2
## --balance-shard=0/8 --balance-phase=before --balance-disabled (informational)
const U = preload("res://tests/sim_util.gd")
const RACES := ["human", "orc", "goblin", "moon_elf", "dwarf"]
const DISABLED := ["high_elf", "dark_elf", "troll"]
const ROLES := ["sword", "spear", "archer"]
const OUT := "res://../test-results/balance_v070"
const MAX_UNITS := 16
const TARGET_COST := 32000.0
const MAX_TICKS := 6000
const MAX_GAP := 0.05
const WALL_MS := 45000

static func spec(race: String, role: String, mount: String = "foot") -> Dictionary:
	return {"id": "%s/%s/%s" % [race, role, mount], "race": race, "unit": role, "mount": mount}

static func cases_for(suite: String, samples: int, disabled: bool = false) -> Array:
	if suite == "sweep":
		var combined: Array = []
		for family in ["race", "unit", "mount", "roster_matrix"]:
			combined.append_array(cases_for(family, samples, disabled))
		return combined
	var races: Array = RACES.duplicate()
	if disabled: races.append_array(DISABLED)
	var pairs: Array = []
	if suite == "race":
		for i in races.size():
			for j in range(i, races.size()):
				for role in ROLES: pairs.append([spec(races[i], role), spec(races[j], role)])
	elif suite == "unit":
		for race in races:
			for i in ROLES.size():
				for j in range(i, ROLES.size()): pairs.append([spec(race, ROLES[i]), spec(race, ROLES[j])])
	elif suite == "mount":
		for race in races:
			if not Horses.can_mount_race(race): continue
			for role in ROLES:
				pairs.append([spec(race, role), spec(race, role, "horse")])
				pairs.append([spec(race, role, "horse"), spec(race, role, "horse")])
	elif suite in ["roster", "roster_matrix"]:
		var reference := {"id": "middle_kingdom/man-at-arms/foot", "race": "human", "unit": "middle_kingdom/man-at-arms", "mount": "foot", "faction": "middle_kingdom", "troop": 1}
		var factions: Array = DB.factions.keys(); factions.sort()
		var profiles: Array = []
		for faction in factions:
			var f: Dictionary = DB.factions[faction]
			if str(f.get("race", "")) not in RACES or bool(f.get("wild", false)): continue
			var troops: Array = f.get("troops", [])
			for i in troops.size():
				var row := {"id": "%s/%s/foot" % [faction, troops[i]["name"]], "race": str(f["race"]), "unit": "%s/%s" % [faction, troops[i]["name"]], "mount": "foot", "faction": faction, "troop": i}
				profiles.append(row)
				if suite == "roster":
					pairs.append([row, reference]); pairs.append([row, row])
		if suite == "roster_matrix":
			for i in profiles.size():
				for j in range(i, profiles.size()): pairs.append([profiles[i], profiles[j]])
	var cases: Array = []
	for pair_index in pairs.size():
		var pair: Array = pairs[pair_index]
		for sample in samples:
			cases.append({"a": pair[0], "b": pair[1], "seed": 70000 + sample * 7919 + pair_index * 101, "sample": sample, "suite": suite})
	return cases

static func make_unit(profile: Dictionary, rng: RandomNumberGenerator) -> Unit:
	var u: Unit
	if profile.has("faction"):
		u = Factory.make_troop(rng, profile["faction"], DB.factions[profile["faction"]]["troops"][int(profile["troop"])])
	else:
		var role: String = profile["unit"]
		var gear := U.good_copper(0, true, "boar_spear" if role == "spear" else "arming_sword")
		if role == "archer":
			gear = [["self_bow", "wood"], ["seax", "copper"], ["tunic", "linen"], ["trousers", "linen"], ["shoes", "leather"]]
		u = U.make(profile["race"], gear, {"sword": 4, "spear": 4, "dagger": 4, "bow": 4, "fighter": 3, "shield_user": 3, "armor_user": 3, "dodger": 2})
		Factory.roll_attrs(rng, u); Factory.roll_size(rng, u); Factory.roll_personality(rng, u)
		if role == "archer": u.quiver = {"arrow_copper_broad": 40}
	if profile["mount"] == "horse":
		u.horse = Unit.create("horse", u.faction, false)
		Factory.roll_attrs(rng, u.horse); Factory.roll_size(rng, u.horse)
		u.horse_care = {"fed": true, "paid": true, "purchase": int(Herds.kind("horses")["price"])}
	return u

## Equal replacement budgets: native gear + one week's ordinary retainer wages.
## Mounts are priced separately so a rider/horse death cannot count the horse twice.
static func body_cost(u: Unit) -> float:
	var cost := float(u.gear_value()) + TroopUpkeep.wage_week({})
	for arrow in u.quiver:
		cost += int(u.quiver[arrow]) * float(Goods.table()[arrow]["price"])
	return cost

static func horse_cost() -> float:
	return float(Herds.kind("horses")["price"]) + 7.0 * (Horses.COIN_DAY + Horses.GRAIN_DAY * float(Goods.table()["grain"]["price"]))

static func candidates(profile: Dictionary, seed_value: int, limit: int = MAX_UNITS) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var units: Array = []; var costs: Array = [0.0]; var prices: Dictionary = {}
	for i in limit:
		var u := make_unit(profile, rng)
		units.append(u); prices[str(u.uid)] = body_cost(u)
		var cost := body_cost(u)
		if u.horse != null:
			var mount_cost := horse_cost()
			cost += mount_cost; prices[str(u.horse.uid)] = mount_cost
		costs.append(float(costs[-1]) + cost)
	return {"units": units, "costs": costs, "prices": prices}

static func equal_cost(a: Dictionary, b: Dictionary) -> Dictionary:
	var best := INF; var out: Dictionary = {}
	for i in range(1, a["costs"].size()):
		for j in range(1, b["costs"].size()):
			var ca := float(a["costs"][i]); var cb := float(b["costs"][j])
			var gap := absf(ca - cb) / maxf(ca, cb)
			var average := (ca + cb) * 0.5
			# Prefer near-equal spend, then armies near the stated target budget.
			var score := gap * 10.0 + absf(average - TARGET_COST) / TARGET_COST
			if gap <= MAX_GAP and score < best:
				best = score; out = {"n0": i, "n1": j, "cost0": ca, "cost1": cb, "gap": gap}
	return out

static func injury(u: Unit) -> float:
	var total := 0.0
	for part: Dictionary in u.body.parts.values():
		for layer: Dictionary in part.get("layers", []): total += float(layer.get("dmg", 0.0))
	return total

static func measure(sim: BattleSim, prices: Dictionary) -> Array:
	var sides: Array = []
	for side in 2:
		sides.append({"won": int(sim.winner == side), "draw": int(sim.winner < 0), "damage_taken": 0.0, "damage_dealt": 0.0, "kills": 0, "value_killed": 0.0, "cost_spent": 0.0, "bodies": 0, "horse_deaths": 0})
	for f: Fighter in sim.fighters:
		var value := float(prices[str(f.unit.uid)])
		sides[f.side]["cost_spent"] += value
		sides[f.side]["damage_taken"] += injury(f.unit)
		sides[1 - f.side]["damage_dealt"] += injury(f.unit)
		sides[f.side]["kills"] += f.kills
		sides[f.side]["bodies"] += 1
		if f.state == "dead" or f.unit.dead:
			sides[1 - f.side]["value_killed"] += value
			if f.mount_rider_idx >= 0: sides[f.side]["horse_deaths"] += 1
	return sides

## Side-swapped replications regenerate identical armies; no wounds/XP leak to another battle.
static func battle(tree: SceneTree, case: Dictionary, swap: bool, deadline: int) -> Dictionary:
	var seed_value := int(case["seed"])
	var a := candidates(case["a"], seed_value * 3 + 1)
	var b := candidates(case["b"], seed_value * 3 + 2)
	var match_cost := equal_cost(a, b)
	if match_cost.is_empty():
		# A rare high-quality guard can exceed sixteen lightly equipped recruits.
		# Preserve the same seeded prefixes and widen only that bounded match.
		a = candidates(case["a"], seed_value * 3 + 1, 32)
		b = candidates(case["b"], seed_value * 3 + 2, 32)
		match_cost = equal_cost(a, b)
	if match_cost.is_empty(): return {"error": "No <=5% cost match within 32 bodies", "case": case, "costs_a": a["costs"], "costs_b": b["costs"]}
	var au: Array = a["units"].slice(0, match_cost["n0"])
	var bu: Array = b["units"].slice(0, match_cost["n1"])
	var sim := BattleSim.new()
	sim.setup(bu if swap else au, au if swap else bu, seed_value, {"w": 16, "h": 8, "max_ticks": MAX_TICKS, "log_moves": false, "verbose": false, "combat_journal": false})
	while not sim.is_over():
		sim.step()
		if sim.tick % 128 == 0:
			if Time.get_ticks_msec() >= deadline: return {"error": "Wall budget exceeded; split this shard", "case": case}
			await tree.process_frame
	var prices: Dictionary = a["prices"].duplicate(); prices.merge(b["prices"])
	var sides := measure(sim, prices)
	if swap: sides.reverse()
	return {"a": case["a"], "b": case["b"], "seed": seed_value, "sample": case["sample"], "suite": case.get("suite", ""), "swap": swap, "mirror": case["a"]["id"] == case["b"]["id"], "ticks": sim.tick, "tick_capped": sim.tick >= MAX_TICKS, "cost_match": match_cost, "sides": sides}

static func summarize(rows: Array, mirrors: bool = false) -> Dictionary:
	var groups := {"race": {}, "unit": {}, "mount": {}, "profile": {}}
	for row: Dictionary in rows:
		if bool(row["mirror"]) != mirrors: continue
		for side in 2:
			var profile: Dictionary = row["a" if side == 0 else "b"]
			var stats: Dictionary = row["sides"][side]
			for category in groups:
				var id: String = str(profile["id" if category == "profile" else category])
				if not groups[category].has(id): groups[category][id] = {"n": 0, "won": 0, "draw": 0, "damage_taken": 0.0, "damage_dealt": 0.0, "kills": 0, "value_killed": 0.0, "cost_spent": 0.0}
				var st: Dictionary = groups[category][id]; st["n"] += 1
				for key in ["won", "draw", "damage_taken", "damage_dealt", "kills", "value_killed", "cost_spent"]: st[key] += stats[key]
	for group: Dictionary in groups.values():
		for st: Dictionary in group.values():
			st["win_rate"] = float(st["won"]) / st["n"]
			st["score_rate"] = (float(st["won"]) + 0.5 * st["draw"]) / st["n"]
			st["cost_efficiency"] = float(st["value_killed"]) / maxf(1.0, st["cost_spent"])
	return groups

static func survey(tree: SceneTree, cases: Array, deadline: int) -> Dictionary:
	var rows: Array = []; var errors: Array = []
	for case: Dictionary in cases:
		for swap in [false, true]:
			var row: Dictionary = await battle(tree, case, swap, deadline)
			if row.has("error"):
				errors.append(row)
				return {"complete": false, "rows": rows, "errors": errors, "summary": summarize(rows), "mirrors": summarize(rows, true)}
			rows.append(row)
	return {"complete": true, "rows": rows, "errors": errors, "summary": summarize(rows), "mirrors": summarize(rows, true)}

static func fingerprint() -> Dictionary:
	var out: Dictionary = {}
	for path in ["factions", "weapons", "armor", "bows", "materials", "creatures", "economy"]:
		out[path] = FileAccess.get_sha256("res://data/%s.json" % path)
	return out

static func write_result(report: Dictionary, label: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var path := "%s/%s_%d_%d.json" % [OUT, label, int(Time.get_unix_time_from_system()), OS.get_process_id()]
	if FileAccess.file_exists(path): return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return ""
	file.store_string(JSON.stringify(report, "\t", true, true)); file.close()
	print("balance070 evidence: ", ProjectSettings.globalize_path(path))
	return path

static func campaign_snapshot() -> Dictionary:
	var races: Dictionary = {}
	for town: Dictionary in Game.world.get("towns", {}).values():
		var race: String = str(DB.factions.get(str(town.get("faction", "")), {}).get("race", "human"))
		if not races.has(race): races[race] = {"population": 0, "treasury": 0.0, "food_stock": 0, "towns": 0}
		var st: Dictionary = races[race]; var e: Dictionary = town.get("econ", {})
		st["towns"] += 1; st["population"] += int(e.get("pop", 0)); st["treasury"] += float(e.get("treasury", 0))
		st["food_stock"] += int(e.get("food", {}).get("stock", 0))
	return {"day": Game.day, "races": races}

static func campaign(tree: SceneTree, deadline: int) -> Dictionary:
	WorldGen.gen_size = "normal"; CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = false
	var generation: Dictionary = Game.new_game_begin(DevTools.WORLD_SEED)
	while not Game.new_game_slice(generation, 5000):
		if Time.get_ticks_msec() >= deadline: return {"complete": false, "error": "world generation exceeded wall budget"}
		await tree.process_frame
	var history: Dictionary = {}
	while CampaignWorld.presim_left(Game) > 0:
		CampaignWorld.presim_slice(Game, history, 5000)
		if Time.get_ticks_msec() >= deadline: return {"complete": false, "error": "one-day history exceeded wall budget"}
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	var snapshots: Array = [campaign_snapshot()]
	for day in 3:
		Game.advance_time(1.0, false, 0, 0)
		while not Game.world.get("work", []).is_empty():
			CampaignWorld.work_slice(Game, 5000)
			if Time.get_ticks_msec() >= deadline: return {"complete": false, "snapshots": snapshots, "error": "campaign exceeded wall budget"}
			await tree.process_frame
		snapshots.append(campaign_snapshot())
	return {"complete": true, "seed": DevTools.WORLD_SEED, "size": "normal", "history_days": 1, "turns": 3, "snapshots": snapshots}

func run(tree: SceneTree) -> int:
	var suite := "race"; var phase := "survey"; var samples := 2; var shard := 0; var shards := 8
	var disabled := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--balance-suite="): suite = arg.trim_prefix("--balance-suite=")
		elif arg.begins_with("--balance-phase="): phase = arg.trim_prefix("--balance-phase=")
		elif arg.begins_with("--balance-samples="): samples = int(arg.trim_prefix("--balance-samples="))
		elif arg.begins_with("--balance-shard="):
			var parts := arg.trim_prefix("--balance-shard=").split("/")
			if parts.size() != 2: return 1
			shard = int(parts[0]); shards = int(parts[1])
		elif arg == "--balance-disabled": disabled = true
	if samples < 1 or shards < 1 or shard < 0 or shard >= shards or suite not in ["race", "unit", "mount", "roster", "roster_matrix", "campaign", "sweep"] or not phase.is_valid_identifier(): return 1
	var started := Time.get_ticks_msec()
	var result: Dictionary
	if suite == "campaign": result = await campaign(tree, started + WALL_MS)
	else:
		var all_cases := cases_for(suite, samples, disabled)
		var selected: Array = []
		for i in all_cases.size():
			if i % shards == shard: selected.append(all_cases[i])
		if selected.is_empty(): return 1
		result = await survey(tree, selected, started + WALL_MS)
		result["selected_cases"] = selected.size(); result["total_cases"] = all_cases.size()
	result.merge({"schema": "balance_v070/1", "suite": suite, "phase": phase, "shard": shard, "shards": shards, "samples": samples, "disabled_included": disabled, "data_sha256": fingerprint(), "elapsed_ms": Time.get_ticks_msec() - started, "max_ticks": MAX_TICKS, "max_cost_gap": MAX_GAP})
	var path := write_result(result, "%s_%s_%02dof%02d" % [phase, suite, shard, shards])
	print("balance070 %s %d/%d: complete=%s elapsed=%d ms battles=%d" % [suite, shard, shards, result.get("complete", false), result["elapsed_ms"], result.get("rows", []).size()])
	return 0 if bool(result.get("complete", false)) and path != "" else 1
