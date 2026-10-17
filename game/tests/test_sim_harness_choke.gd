extends RefCounted
## Harness pass bands: chokepoints (stream arrival), stuck weapons and the unarmed fallback (survey item 5 + addenda).
## Bands with gate=true count as failures; the rest print "TRACKED (not gating)".
## STATUS: battle bands are OFF (GATE=false) until tuned; the wrestling-contest formula bands gate (they are exact).

const U = preload("res://tests/sim_util.gd")
const N := 60             # choke seeds (aim ~500)
const NL := 150           # lodge / unarmed seeds
const GATE := false

func _choke(map: String, vet_kit: Array, foes: Callable, n_foes: int, seed0: int, weapon_note: String = "") -> Dictionary:
	var kills := []
	var downs := 0
	for i in N:
		var v := U.veteran(100, vet_kit)
		var enemies := []
		for j in n_foes:
			enemies.append(foes.call())
		var opts := {"w": 24, "h": 9, "map": map, "stream": true, "stream_gap": 8, "log_moves": false, "verbose": false,
			"max_ticks": 24000, "cells0": [Vector2i(11, 4)], "hold0": true}
		var sim: BattleSim = U.run([v], enemies, seed0 + i * 7919, opts)
		kills.append(U.kills_by(sim, 0))
		downs += U.downed_by(sim, 0)
	kills.sort()
	var tot := 0
	for k in kills:
		tot += k
	return {"mean": float(tot) / N, "median": float(kills[N / 2]), "downed": float(downs) / N}

func _goblin_tin() -> Unit:
	return U.make("goblin", [["short_spear", "tin"], ["buckler", "tin"], ["pot_helm", "tin"], ["tunic", "linen"], ["trousers", "linen"]],
		{"spear": 1, "dodger": 2, "fighter": 1})

func run(_tree: SceneTree) -> int:
	var fails := 0
	var t0 := Time.get_ticks_msec()
	# ---- wrestling contest formula (exact, gating)
	print("wrestling contest (formula):")
	fails += U.band("equal skill, 2x mass: heavier wins grabs %", 100.0 * Formulas.grab_chance(3, 3, 180, 90), 70, 80, true)
	fails += U.band("troll vs human at equal skill: troll grab %", 100.0 * Formulas.grab_chance(3, 3, 250 + 30, 70 + 20), 90, 96, true)
	fails += U.band("goblin vs human at equal skill: goblin grab %", 100.0 * Formulas.grab_chance(3, 3, 35 + 8, 70 + 20), 0, 30, true)
	# ---- chokepoints
	print("chokepoints (%d seeds each, 30 recruits streaming in):" % N)
	var R := func(): return U.recruit()
	var std1 := _choke("corridor1", U.good_copper(0), R, 30, 100)
	var mst1 := _choke("corridor1", U.good_copper(5), R, 30, 100)
	var std2 := _choke("corridor2", U.good_copper(0), R, 30, 200)
	var opn := _choke("open", U.good_copper(0), R, 30, 300)
	fails += U.band("1-tile vs 30R, masterful copper: kills (mean)", mst1["mean"], 15, 25, GATE)
	fails += U.band("1-tile vs 30R, standard copper: kills (mean)", std1["mean"], 10, 18, GATE)
	fails += U.band("1-tile vs 30R, standard copper: kills (median ~14)", std1["median"], 12, 16, GATE)
	fails += U.band("2-tile kills as % of 1-tile (~60%)", 100.0 * std2["mean"] / maxf(0.1, std1["mean"]), 45, 75, GATE)
	fails += U.band("open ground vs 30R: kills (mean)", opn["mean"], 4, 8, GATE)
	var g_m := _choke("corridor1", U.good_copper(5), Callable(self, "_goblin_tin"), 50, 400)
	var g_s := _choke("corridor1", U.good_copper(0), Callable(self, "_goblin_tin"), 50, 500)
	fails += U.band("1-tile vs 50 tin goblins, masterful copper: kills", g_m["mean"], 30, 50, GATE)
	fails += U.band("1-tile vs 50 tin goblins, standard copper: kills (median ~25)", g_s["median"], 18, 35, GATE)
	var sp := _choke("corridor1", U.good_copper(0, true, "boar_spear", false), R, 30, 600)
	fails += U.band("V100 spear vs sword&shield at 1-tile: extra kills %", 100.0 * (sp["mean"] - std1["mean"]) / maxf(0.1, std1["mean"]), 0, 20, GATE)
	# ---- stuck weapons
	print("stuck weapons (%d battles per weapon):" % NL)
	var lr := _lodge_rates()
	fails += U.band("penetrating stabs that lodge %", lr["stab"], 15, 25, GATE)
	fails += U.band("penetrating hacks that lodge %", lr["hack"], 5, 15, GATE)
	fails += U.band("penetrating slashes that lodge %", lr["slash"], 0, 3, GATE)
	fails += U.band("V100 (spear) disarmed by a lodge, % of fights", lr["disarmed_pct"], 0, 10, GATE)
	fails += U.band("ticks idle after letting go (worst case)", lr["idle_worst"], 0, 10, GATE, "%.0f")
	# ---- unarmed fallback
	print("unarmed fallback (%d battles):" % NL)
	var ua := _unarmed()
	fails += U.band("disarmed V100 vs armed R: V wins %", ua["v_win"], 50, 100, GATE)
	fails += U.band("unarmed R vs R lasts x armed R vs R", ua["ratio"], 2, 4, GATE)
	print("harness choke/lodge/unarmed: %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	return fails

func _lodge_rates() -> Dictionary:
	var pen := {"stab": 0, "hack": 0, "slash": 0}
	var lod := {"stab": 0, "hack": 0, "slash": 0}
	var disarmed := 0
	var idle_worst := 0
	var opts := {"w": 16, "h": 8, "log_moves": false, "verbose": false, "max_ticks": 12000}
	var kits := [["boar_spear", false], ["bearded_axe", true], ["arming_sword", true]]
	for kit in kits:
		for i in NL:
			var v := U.veteran(100, U.good_copper(0, true, kit[0], kit[1]))
			v.skills["axe"] = v.skill("sword")
			var sim: BattleSim = U.run([v], [U.recruit(), U.recruit()], 2000 + i * 7919, opts)
			var f: Fighter = sim.fighters[0]
			for e in f.log:
				if e["k"] != "strike" or int(e["d"]["a"]) != 0 or not e["d"]["edge"]:
					continue
				var D: Dictionary = e["d"]
				var vb := String(D["verb"]).split(" ")[0]
				if not pen.has(vb):
					continue
				var deep := false
				for l in D["layers"]:
					if String(l[1]) != "skin" and String(l[1]) != "fat":
						deep = true
				if deep:
					pen[vb] += 1
					if D["lodged"]:
						lod[vb] += 1
			if kit[0] == "boar_spear":
				var let_tick := -1
				for ev in sim.events:
					if ev["actor"] == 0 and ev["type"] == "drop" and ev.has("entry") and ev["entry"]["d"].get("key", "") == "let_go":
						let_tick = ev["tick"]
						disarmed += 1
						break
				if let_tick >= 0 and f.alive():
					var next := -1
					for ev in sim.events:
						if ev["actor"] == 0 and ev["tick"] > let_tick and ev["type"] in ["prepare", "move", "attack", "hit", "miss", "freed"]:
							next = ev["tick"]
							break
					if next > 0:
						idle_worst = maxi(idle_worst, next - let_tick)
	var out := {"disarmed_pct": 100.0 * disarmed / NL, "idle_worst": idle_worst}
	for k in pen:
		out[k] = 100.0 * lod[k] / maxf(1.0, float(pen[k]))
		print("    %s: %d penetrating, %d lodged" % [k, pen[k], lod[k]])
	return out

func _unarmed() -> Dictionary:
	var opts := {"w": 16, "h": 8, "log_moves": false, "verbose": false, "max_ticks": 24000}
	var v_win := 0
	var t_armed := 0.0
	var t_unarmed := 0.0
	for i in NL:
		var kit := U.good_copper(0)
		kit.remove_at(0)  # no weapon
		var sim: BattleSim = U.run([U.veteran(100, kit)], [U.recruit()], 3000 + i * 7919, opts)
		if sim.winner == 0:
			v_win += 1
		var k2 := U.good_copper(0)
		k2.remove_at(0)
		var k3 := U.good_copper(0)
		k3.remove_at(0)
		t_unarmed += U.run([U.recruit(k2)], [U.recruit(k3)], 4000 + i * 7919, opts).tick
		t_armed += U.run([U.recruit()], [U.recruit()], 4000 + i * 7919, opts).tick
	return {"v_win": 100.0 * v_win / NL, "ratio": t_unarmed / maxf(1.0, t_armed)}
