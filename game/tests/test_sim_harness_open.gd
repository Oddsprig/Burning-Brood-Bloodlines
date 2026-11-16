extends RefCounted
## Harness pass bands, open ground (Douglas / survey item 5). Kit: "good copper" (copper helm + copper mail over a
## gambeson + round shield + copper arming sword). R = median recruit, V25/V50/V100 = veteran at 25/50/100 battles.
## Each band prints its value; bands with gate=true count as failures, the rest print "TRACKED (not gating)".
## Douglas: outcomes are whatever the DF mechanics produce. Only mechanical-correctness checks gate (R vs R symmetry);
## every veteran band is informational (printed, TRACKED, never tuned toward).

const Parts201 = preload("res://tests/fixtures/older_201_parts_v100.gd")
var _part_begin: int = 0
var _part_end: int = -1
var _part_raw: Dictionary = {}
var _aggregate: Dictionary = {}
var _aggregate_call: int = 0
var _runplan_keys: Array = []
var _runplan_started: int = 0
const VS_NAMES: Array = ["rr", "v25", "v50", "v100", "v5", "v1", "un", "sup"]
const BAND_NAMES: Array = ["rr", "v25", "v50", "v100", "v5", "v1", "vv", "un", "sup", "wounded", "waves"]

const U = preload("res://tests/sim_util.gd")
const N := 300            # seeds per band (aim ~1000 when time allows)
const GATE := false
const OPTS := {"w": 20, "h": 10, "log_moves": false, "verbose": false, "max_ticks": 12000}

## One side of V (or R) vs k recruits. Returns {"win", "die", "ticks", "ctx": {death_ctx: n}, "xp": main weapon xp}.
func _vs(make_a: Callable, k: int, seed0: int, n: int = N) -> Dictionary:
	if not _aggregate.is_empty():
		var cached: Dictionary = _aggregate[VS_NAMES[_aggregate_call]]
		_aggregate_call += 1
		return cached
	var st := {"win": 0, "die": 0, "ticks": 0.0, "ctx": {}, "xp": 0.0}
	for i: int in range(_part_begin, n if _part_end < 0 else mini(n, _part_end)):
		var a: Unit = make_a.call()
		var xp0 := _xp_total(a, "sword")
		var foes := []
		for j in k:
			foes.append(U.recruit())
		var sim: BattleSim = U.run([a], foes, seed0 + i * 7919, OPTS)
		if sim.winner == 0:
			st["win"] += 1
		var f: Fighter = sim.fighters[0]
		if f.state == "dead":
			st["die"] += 1
			st["ctx"][f.death_ctx] = int(st["ctx"].get(f.death_ctx, 0)) + 1
		st["ticks"] += sim.tick
		st["xp"] += _xp_total(a, "sword") - xp0
	st["win_pct"] = 100.0 * st["win"] / n
	st["die_pct"] = 100.0 * st["die"] / n
	st["xp_avg"] = st["xp"] / n
	st["samples"] = n if _part_end < 0 else _part_end - _part_begin
	return st

func _xp_total(u: Unit, s: String) -> float:
	var lvl := u.skill(s)
	var t: float = float(u.skill_xp.get(s, 0.0))
	for l in lvl:
		t += Learning.xp_to_next(l)
	return t

func run(_tree: SceneTree) -> int:
	if _aggregate.is_empty():
		var required: Array = ["setup", "verify"]
		for band: String in BAND_NAMES:
			for index: int in (N * 2 if band == "v1" else N): required.append("%s:%d" % [band, index])
		var batch_requested: bool = false
		for argument: String in OS.get_cmdline_user_args():
			if argument == "--speed-parts" or argument.begins_with("--speed-parts="): batch_requested = true
		var batch: String = Parts201.option("--speed-parts")
		if batch_requested:
			if batch.is_empty(): return 1
			if Parts201.option("--speed-part", "all") != "all": return 1
			var endpoints: PackedStringArray = batch.split("..", true)
			if endpoints.size() != 2: return 1
			var first: int = required.find(endpoints[0])
			var last: int = required.find(endpoints[1])
			# Setup and verification are independent invocations; every selected sample is complete.
			if first < 2 or last < first or last - first >= 64: return 1
			_runplan_keys = required.slice(first, last + 1)
			_runplan_started = Time.get_ticks_usec()
			return _split_harness(_tree, "runplan-batch")
		var part: String = Parts201.select(required)
		if part.is_empty(): return 1
		if part != "all": return _split_harness(_tree, part)
	var fails := 0
	var t0 := Time.get_ticks_msec()
	print("open-ground harness, %d seeds per band" % N)
	var rr := _vs(func(): return U.recruit(), 1, 100)
	fails += U.band("R vs R: side A wins % (symmetry, GATING)", rr["win_pct"], 45, 55, true)
	fails += U.band("XP per battle on the main weapon (R vs R)", rr["xp_avg"], 80, 140, GATE)
	var v25 := _vs(func(): return U.veteran(25), 1, 200)
	fails += U.band("V25 vs 1R: V wins %", v25["win_pct"], 80, 90, GATE)
	var v50 := _vs(func(): return U.veteran(50), 2, 300)
	fails += U.band("V50 vs 2R: V wins %", v50["win_pct"], 70, 80, GATE)
	fails += U.band("V50 vs 2R: V dies %", v50["die_pct"], 0, 15, GATE)
	var v100 := _vs(func(): return U.veteran(100), 3, 400)
	fails += U.band("V100 vs 3R (headline): V wins %", v100["win_pct"], 70, 80, GATE)
	fails += U.band("V100 vs 3R (headline): V dies %", v100["die_pct"], 10, 20, GATE)
	print("    V100 vs 3R causes of death: %s" % str(v100["ctx"]))
	var d := maxf(1.0, float(v100["die"]))
	fails += U.band("  deaths after exhaustion/stun/knockdown (helpless) %", 100.0 * int(v100["ctx"].get("helpless", 0)) / d, 40, 100, GATE)
	fails += U.band("  deaths from a lucky lethal blow %", 100.0 * int(v100["ctx"].get("lucky", 0)) / d, 30, 50, GATE)
	var v5 := _vs(func(): return U.veteran(100), 5, 500)
	fails += U.band("V100 vs 5R: V wins %", v5["win_pct"], 0, 35, GATE)
	fails += U.band("V100 vs 5R: V dies %", v5["die_pct"], 50, 100, GATE)
	var v1 := _vs(func(): return U.veteran(100), 1, 600, N * 2)
	fails += U.band("V100 vs 1R: V dies % (informational; non-zero chance is checked mechanically in test_sim_nonzero)", v1["die_pct"], 0.5, 5, false)
	var vv := _vs_vv()
	fails += U.band("V100 vs V100: side A wins %", vv, 45, 55, GATE)
	var un := _vs(func(): return U.veteran(100, U.good_copper(0, false)), 3, 700)
	fails += U.band("V100 unarmored vs 3R: V wins %", un["win_pct"], 0, 50, GATE)
	var sup := _vs(func(): return U.veteran(100, U.good_copper(3)), 3, 400)
	fails += U.band("superior kit gain vs 3R (pts over standard)", sup["win_pct"] - v100["win_pct"], 5, 10, GATE)
	var wk := _wounded_next_day()
	fails += U.band("wounds kept next day: win rate drop (pts)", v100["win_pct"] - wk, 15, 100, GATE)
	var waves := _waves()
	fails += U.band("3 waves of 3R, no rest: survives the third wave %", waves, 0, 50, GATE)
	print("harness open ground: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	return fails

func _vs_vv() -> float:
	if not _aggregate.is_empty(): return 100.0 * int(_aggregate["vv"]["win"]) / N
	var win := 0
	for i: int in range(_part_begin, N if _part_end < 0 else mini(N, _part_end)):
		var sim: BattleSim = U.run([U.veteran(100)], [U.veteran(100)], 800 + i * 7919, OPTS)
		if sim.winner == 0:
			win += 1
	_part_raw = {"win": win, "samples": N if _part_end < 0 else _part_end - _part_begin}
	return 100.0 * win / N

## V100 survives a first 3R fight, keeps the wounds through one day of rest, then fights a fresh 3R.
func _wounded_next_day() -> float:
	if not _aggregate.is_empty(): return 100.0 * int(_aggregate["wounded"]["win"]) / maxf(1.0, float(_aggregate["wounded"]["fights"]))
	var fights := 0
	var win := 0
	for i: int in range(_part_begin, N if _part_end < 0 else mini(N, _part_end)):
		var v := U.veteran(100)
		var s1: BattleSim = U.run([v], [U.recruit(), U.recruit(), U.recruit()], 900 + i * 7919, OPTS)
		if v.dead or s1.winner != 0:
			continue
		Healing.after_battle(v)
		Healing.heal(v, 1.0, false)
		v.body.exertion = 0.0
		v.body.pain = Healing.wound_pain(v)
		fights += 1
		var s2: BattleSim = U.run([v], [U.recruit(), U.recruit(), U.recruit()], 950 + i * 7919, OPTS)
		if s2.winner == 0:
			win += 1
	_part_raw = {"win": win, "fights": fights, "samples": N if _part_end < 0 else _part_end - _part_begin}
	return 100.0 * win / maxf(1.0, float(fights))

## Three waves of 3R with no rest in between (wounds, blood, pain and exertion carry over).
func _waves() -> float:
	if not _aggregate.is_empty(): return 100.0 * int(_aggregate["waves"]["survived"]) / N
	var reached := 0
	var survived := 0
	for i: int in range(_part_begin, N if _part_end < 0 else mini(N, _part_end)):
		var v := U.veteran(100)
		var ok := true
		for w in 3:
			if w == 2:
				reached += 1
			var s: BattleSim = U.run([v], [U.recruit(), U.recruit(), U.recruit()], 1000 + i * 7919 + w, OPTS)
			if v.dead or s.winner != 0:
				ok = false
				break
		if ok:
			survived += 1
	_part_raw = {"survived": survived, "reached": reached, "samples": N if _part_end < 0 else _part_end - _part_begin}
	return 100.0 * survived / maxf(1.0, float(N))

## One complete original sample, including every conditional continuation, per short process.
func _allocation_state() -> Array:
	return [Unit._next_uid, Item._next_uid, str(Game.rng.state)]

func _sample(band: String, index: int) -> Dictionary:
	_part_begin = index; _part_end = index + 1
	match band:
		"rr": return _vs(func() -> Unit: return U.recruit(), 1, 100)
		"v25": return _vs(func() -> Unit: return U.veteran(25), 1, 200)
		"v50": return _vs(func() -> Unit: return U.veteran(50), 2, 300)
		"v100": return _vs(func() -> Unit: return U.veteran(100), 3, 400)
		"v5": return _vs(func() -> Unit: return U.veteran(100), 5, 500)
		"v1": return _vs(func() -> Unit: return U.veteran(100), 1, 600, N * 2)
		"vv": _vs_vv()
		"un": return _vs(func() -> Unit: return U.veteran(100, U.good_copper(0, false)), 3, 700)
		"sup": return _vs(func() -> Unit: return U.veteran(100, U.good_copper(3)), 3, 400)
		"wounded": _wounded_next_day()
		"waves": _waves()
	return _part_raw

func _split_harness(tree: SceneTree, part: String) -> int:
	var completed: int = 0
	var runner: Node = tree.current_scene
	var counter: Object = null
	if not _runplan_keys.is_empty():
		if runner == null: return 1
		counter = runner.get("script_errors")
		if counter == null or not counter.has_method("total"): return 1
	var io: RefCounted = Parts201.new("harness_open")
	if io.fails > 0: return 1
	if part == "setup":
		return 0 if io.write_record("setup", {"chain": "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()], "after": _allocation_state()}) else 1
	var setup: Dictionary = io.read_record("setup")
	if setup.is_empty(): return 1
	var previous: String = "setup"
	var preceding: Dictionary = setup
	for band: String in BAND_NAMES:
		var total: int = N * 2 if band == "v1" else N
		var sum: Dictionary = {"win": 0, "die": 0, "ticks": 0.0, "xp": 0.0, "ctx": {}, "fights": 0, "survived": 0, "reached": 0, "samples": 0}
		for index: int in total:
			var key: String = "%s:%d" % [band, index]
			if part == key or _runplan_keys.has(key):
				if not _runplan_keys.is_empty() and Time.get_ticks_usec() - _runplan_started >= 40000000:
					io.fail("batch deadline; incomplete or overdue sample batch fails"); return 1
				var errors_before: int = 0 if counter == null else int(counter.call("total"))
				# Restore real predecessor allocation cursors, never arbitrary fresh UIDs.
				Unit._next_uid = int(preceding["after"][0]); Item._next_uid = int(preceding["after"][1])
				Game.rng.state = int(preceding["after"][2])
				var before: Array = _allocation_state()
				var raw: Dictionary = _sample(band, index)
				if int(raw.get("samples", -1)) != 1: return 1
				if counter != null and int(counter.call("total")) != errors_before: return 1
				var written: bool = io.write_record(key, {"chain": setup["chain"], "previous": FileAccess.get_sha256(io.path(previous)),
					"before": before, "after": _allocation_state(), "raw": raw})
				if not written: return 1
				if part == key: return 0
				completed += 1
				print("RUNPLAN_SAMPLE key=", key, " samples=1 parent=PARTIAL")
			# Only visit the prefix needed for this selector; verification requires all samples.
			var record: Dictionary = io.read_record(key)
			if record.is_empty(): return 1
			if record.get("chain") != setup["chain"] or record.get("previous") != FileAccess.get_sha256(io.path(previous)) or record.get("before") != preceding["after"]:
				io.fail("missing, reordered or mixed sample: " + key); return 1
			var raw: Dictionary = record.get("raw", {})
			if int(raw.get("samples", -1)) != 1: return 1
			for field: String in ["win", "die", "ticks", "xp", "fights", "survived", "reached", "samples"]:
				sum[field] += raw.get(field, 0)
			for cause: String in raw.get("ctx", {}): sum["ctx"][cause] = int(sum["ctx"].get(cause, 0)) + int(raw["ctx"][cause])
			previous = key; preceding = record
			if part == "runplan-batch" and key == str(_runplan_keys.back()):
				if Time.get_ticks_usec() - _runplan_started >= 40000000:
					io.fail("batch deadline; overdue sample batch fails"); return 1
				print("RUNPLAN_HARNESS first=", _runplan_keys.front(), " last=", key, " complete_samples=", completed, " body_wall_usec=", Time.get_ticks_usec() - _runplan_started, " parent=PARTIAL")
				return 0 if completed == _runplan_keys.size() and io.fails == 0 else 1
		if part == "verify":
			if int(sum["samples"]) != total: return 1
			sum["win_pct"] = 100.0 * int(sum["win"]) / total
			sum["die_pct"] = 100.0 * int(sum["die"]) / total
			sum["xp_avg"] = float(sum["xp"]) / total
			_aggregate[band] = sum
	if part != "verify": return 1
	# The untouched original band expressions apply only to the complete raw aggregate.
	var result: int = run(tree)
	if result != 0: return result
	return 0 if io.write_record("verify", {"chain": setup["chain"], "last": FileAccess.get_sha256(io.path(previous)), "bands": _aggregate, "failures": result}) else 1
