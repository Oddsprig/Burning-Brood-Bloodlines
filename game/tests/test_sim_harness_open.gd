extends RefCounted
## Harness pass bands, open ground (Douglas / survey item 5). Kit: "good copper" (copper helm + copper mail over a
## gambeson + round shield + copper arming sword). R = median recruit, V25/V50/V100 = veteran at 25/50/100 battles.
## Each band prints its value; bands with gate=true count as failures, the rest print "TRACKED (not gating)".
## Douglas: outcomes are whatever the DF mechanics produce. Only mechanical-correctness checks gate (R vs R symmetry);
## every veteran band is informational (printed, TRACKED, never tuned toward).

const U = preload("res://tests/sim_util.gd")
const N := 300            # seeds per band (aim ~1000 when time allows)
const GATE := false
const OPTS := {"w": 20, "h": 10, "log_moves": false, "verbose": false, "max_ticks": 12000}

## One side of V (or R) vs k recruits. Returns {"win", "die", "ticks", "ctx": {death_ctx: n}, "xp": main weapon xp}.
func _vs(make_a: Callable, k: int, seed0: int, n: int = N) -> Dictionary:
	var st := {"win": 0, "die": 0, "ticks": 0.0, "ctx": {}, "xp": 0.0}
	for i in n:
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
	return st

func _xp_total(u: Unit, s: String) -> float:
	var lvl := u.skill(s)
	var t: float = float(u.skill_xp.get(s, 0.0))
	for l in lvl:
		t += Learning.xp_to_next(l)
	return t

func run(_tree: SceneTree) -> int:
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
	var win := 0
	for i in N:
		var sim: BattleSim = U.run([U.veteran(100)], [U.veteran(100)], 800 + i * 7919, OPTS)
		if sim.winner == 0:
			win += 1
	return 100.0 * win / N

## V100 survives a first 3R fight, keeps the wounds through one day of rest, then fights a fresh 3R.
func _wounded_next_day() -> float:
	var fights := 0
	var win := 0
	for i in N:
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
	return 100.0 * win / maxf(1.0, float(fights))

## Three waves of 3R with no rest in between (wounds, blood, pain and exertion carry over).
func _waves() -> float:
	var reached := 0
	var survived := 0
	for i in N:
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
	return 100.0 * survived / maxf(1.0, float(N))
