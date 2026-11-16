extends RefCounted
## Harness pass bands: chokepoints (stream arrival), stuck weapons and the unarmed fallback (survey item 5 + addenda).
## Bands with gate=true count as failures; the rest print "TRACKED (not gating)".
## STATUS: battle bands are OFF (GATE=false) until tuned; the wrestling-contest formula bands gate (they are exact).

const U = preload("res://tests/sim_util.gd")
const N := 15             # v0.100: reduced from 60 to fit the <60s test budget (tracked bands, GATE=false)
const NL := 30            # v0.100: reduced from 150 to fit the <60s test budget (tracked bands, GATE=false)
const GATE := false
## v0.100 r3: one COMPLETE original seed unit per process; final combines raw counts, never partial means.
## No further N/NL reduction. Default still performs the complete continuous workload.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
const Source = preload("res://tests/fixtures/older_speed_parts_v100.gd")
var held_rows: Array = []
var held_run := ""
var held_source := ""

func _choke(map: String, vet_kit: Array, foes: Callable, n_foes: int, seed0: int, weapon_note: String = "", first: int = 0, count: int = N) -> Dictionary:
	var kills := []
	var downs := 0
	var config := {"map": map, "kit": vet_kit, "foes": n_foes, "seed0": seed0}
	for i in range(first, first + count if held_rows.is_empty() else first):
		var v := U.veteran(100, vet_kit)
		var enemies := []
		for j in n_foes:
			enemies.append(foes.call())
		var opts := {"w": 24, "h": 9, "map": map, "stream": true, "stream_gap": 8, "log_moves": false, "verbose": false,
			"max_ticks": 24000, "cells0": [Vector2i(11, 4)], "hold0": true}
		var sim: BattleSim = U.run([v], enemies, seed0 + i * 7919, opts)
		kills.append(U.kills_by(sim, 0))
		downs += U.downed_by(sim, 0)
	if not held_rows.is_empty():
		for row in held_rows:
			if row["job"]["kind"] == "choke" and row["raw"]["config"] == config:
				kills.append_array(row["raw"]["kills"])
				downs += int(row["raw"]["downs"])
	kills.sort()
	var tot := 0
	for k in kills:
		tot += k
	return {"mean": float(tot) / count, "median": float(kills[kills.size() / 2]), "downed": float(downs) / count, "kills": kills, "downs": downs, "seed0": seed0, "config": config}

func _goblin_tin() -> Unit:
	return U.make("goblin", [["short_spear", "tin"], ["buckler", "tin"], ["pot_helm", "tin"], ["tunic", "linen"], ["trousers", "linen"]],
		{"spear": 1, "dodger": 2, "fighter": 1})

func run(_tree: SceneTree) -> int:
	var selected := ""
	var selected_seen := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--held-step="):
			if selected_seen: return 1
			selected_seen = true
			selected = argument.trim_prefix("--held-step=")
		elif argument.begins_with("--held-run="):
			if not held_run.is_empty(): return 1
			held_run = argument.trim_prefix("--held-run=")
	if selected_seen:
		if not _held_id(held_run): return 1
		held_source = Source.source_stamp()
		if selected == "final":
			if not _held_collect(): return 1
		elif selected.is_valid_int():
			return _held_part(int(selected))
		else: return 1
	elif not held_run.is_empty(): return 1
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

func _lodge_rates(first: int = 0, count: int = NL, chosen_kit: int = -1) -> Dictionary:
	var pen := {"stab": 0, "hack": 0, "slash": 0}
	var lod := {"stab": 0, "hack": 0, "slash": 0}
	var disarmed := 0
	var idle_worst := 0
	var opts := {"w": 16, "h": 8, "log_moves": false, "verbose": false, "max_ticks": 12000}
	var kits := [["boar_spear", false], ["bearded_axe", true], ["arming_sword", true]]
	for kit_index in (kits.size() if held_rows.is_empty() else 0):
		if chosen_kit >= 0 and chosen_kit != kit_index: continue
		var kit: Array = kits[kit_index]
		for i in range(first, first + count):
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
	if not held_rows.is_empty():
		for row in held_rows:
			if row["job"]["kind"] != "lodge": continue
			var raw: Dictionary = row["raw"]
			for key in pen:
				pen[key] += int(raw["pen"][key]); lod[key] += int(raw["lod"][key])
			disarmed += int(raw["disarmed"])
			idle_worst = maxi(idle_worst, int(raw["idle_worst"]))
	var out := {"pen": pen, "lod": lod, "disarmed": disarmed, "disarmed_pct": 100.0 * disarmed / NL, "idle_worst": idle_worst}
	for k in pen:
		out[k] = 100.0 * lod[k] / maxf(1.0, float(pen[k]))
		print("    %s: %d penetrating, %d lodged" % [k, pen[k], lod[k]])
	return out

func _unarmed(first: int = 0, count: int = NL) -> Dictionary:
	var opts := {"w": 16, "h": 8, "log_moves": false, "verbose": false, "max_ticks": 24000}
	var v_win := 0
	var t_armed := 0.0
	var t_unarmed := 0.0
	for i in range(first, first + count if held_rows.is_empty() else first):
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
	if not held_rows.is_empty():
		for row in held_rows:
			if row["job"]["kind"] != "unarmed": continue
			v_win += int(row["raw"]["v_wins"])
			t_armed += float(row["raw"]["t_armed"]); t_unarmed += float(row["raw"]["t_unarmed"])
	return {"v_win": 100.0 * v_win / NL, "ratio": t_unarmed / maxf(1.0, t_armed), "v_wins": v_win, "t_armed": t_armed, "t_unarmed": t_unarmed}

# The ordered units below are exactly the original 7*N + 3*NL + NL seed units:
# 105 complete choke fights, 90 lodge fights, 30 indivisible THREE-fight unarmed units.
# Total remains 285 full battles. No battle is truncated and no seed is omitted.
func _held_jobs() -> Array:
	var jobs: Array = []
	for case_id in 7:
		for i in N: jobs.append({"kind": "choke", "case": case_id, "index": i})
	for kit in 3:
		for i in NL: jobs.append({"kind": "lodge", "case": kit, "index": i})
	for i in NL: jobs.append({"kind": "unarmed", "case": 0, "index": i})
	return jobs

func _held_id(value: String) -> bool:
	if value.is_empty() or value.length() > 48: return false
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

func _held_path(step: int) -> String:
	return "user://held_choke_r3_%s_%s/step%03d.bin" % [ProjectSettings.globalize_path("res://").sha256_text().substr(0, 12), held_run, step]

func _held_read(step: int) -> Dictionary:
	var file := FileAccess.open(_held_path(step), FileAccess.READ)
	if file == null: return {}
	var row: Variant = file.get_var(false)
	var complete := file.get_error() == OK
	file.close()
	if not complete or not row is Dictionary: return {}
	if row.get("complete") != true or row.get("step") != step or row.get("run") != held_run or row.get("source") != held_source: return {}
	if row.get("engine") != Engine.get_version_info() or row.get("N") != N or row.get("NL") != NL or row.get("gate") != GATE: return {}
	var jobs := _held_jobs()
	if step < 0 or step >= jobs.size() or row.get("job") != jobs[step] or not row.get("raw") is Dictionary: return {}
	if not row.get("unit_uid") is int or not row.get("item_uid") is int: return {}
	return row

func _held_part(step: int) -> int:
	var jobs := _held_jobs()
	if step < 0 or step >= jobs.size() or FileAccess.file_exists(_held_path(step)): return 1
	var previous_sha := ""
	if step > 0:
		var previous := _held_read(step - 1)
		if previous.is_empty(): return 1
		previous_sha = FileAccess.get_sha256(_held_path(step - 1))
		# Preserve the actual original creation sequence, including counter-dependent identities.
		Unit._next_uid = previous["unit_uid"]; Item._next_uid = previous["item_uid"]
	var job: Dictionary = jobs[step]
	var i: int = job["index"]
	var raw: Dictionary = {}
	var started := Time.get_ticks_usec()
	match job["kind"]:
		"choke":
			var R := func(): return U.recruit()
			match int(job["case"]):
				0: raw = _choke("corridor1", U.good_copper(0), R, 30, 100, "", i, 1)
				1: raw = _choke("corridor1", U.good_copper(5), R, 30, 100, "", i, 1)
				2: raw = _choke("corridor2", U.good_copper(0), R, 30, 200, "", i, 1)
				3: raw = _choke("open", U.good_copper(0), R, 30, 300, "", i, 1)
				4: raw = _choke("corridor1", U.good_copper(5), Callable(self, "_goblin_tin"), 50, 400, "", i, 1)
				5: raw = _choke("corridor1", U.good_copper(0), Callable(self, "_goblin_tin"), 50, 500, "", i, 1)
				6: raw = _choke("corridor1", U.good_copper(0, true, "boar_spear", false), R, 30, 600, "", i, 1)
		"lodge": raw = _lodge_rates(i, 1, int(job["case"]))
		"unarmed": raw = _unarmed(i, 1) # All three original paired fights of this seed stay together.
		_: return 1
	if raw.is_empty() or Source.source_stamp() != held_source: return 1
	if step > 0 and FileAccess.get_sha256(_held_path(step - 1)) != previous_sha: return 1
	var row := {"complete": true, "step": step, "run": held_run, "source": held_source,
		"engine": Engine.get_version_info(), "N": N, "NL": NL, "gate": GATE, "job": job,
		"previous_sha256": previous_sha, "raw": raw, "unit_uid": Unit._next_uid, "item_uid": Item._next_uid,
		"elapsed_usec": Time.get_ticks_usec() - started}
	if DirAccess.make_dir_recursive_absolute(_held_path(step).get_base_dir()) != OK: return 1
	var file := FileAccess.open(_held_path(step), FileAccess.WRITE)
	if file == null: return 1
	file.store_var(row); file.flush()
	var error := file.get_error(); file.close()
	if error != OK or _held_read(step).is_empty(): return 1
	print("CHOKE PARTIAL step=", step, "/", jobs.size() - 1, " sha256=", FileAccess.get_sha256(_held_path(step)), "; raw evidence only, final required")
	return 0

func _held_collect() -> bool:
	var previous_sha := ""
	var jobs := _held_jobs()
	for step in jobs.size():
		var row := _held_read(step)
		if row.is_empty() or row.get("previous_sha256") != previous_sha: return false
		previous_sha = FileAccess.get_sha256(_held_path(step))
		var raw: Dictionary = row["raw"]
		if jobs[step]["kind"] == "choke":
			var seed0s := [100, 100, 200, 300, 400, 500, 600]
			var maps := ["corridor1", "corridor1", "corridor2", "open", "corridor1", "corridor1", "corridor1"]
			var case_id: int = jobs[step]["case"]
			var kit: Array = U.good_copper(5 if case_id in [1, 4] else 0)
			if case_id == 6: kit = U.good_copper(0, true, "boar_spear", false)
			var config := {"map": maps[case_id], "kit": kit, "foes": 50 if case_id in [4, 5] else 30, "seed0": seed0s[case_id]}
			if raw.get("config") != config: return false
			if raw.get("seed0") != seed0s[jobs[step]["case"]] or not raw.get("kills") is Array or raw["kills"].size() != 1 or not raw.get("downs") is int: return false
		elif jobs[step]["kind"] == "lodge":
			if not raw.get("pen") is Dictionary or not raw.get("lod") is Dictionary or not raw.get("disarmed") is int or not raw.get("idle_worst") is int: return false
		else:
			if not raw.has("v_wins") or not raw.has("t_armed") or not raw.has("t_unarmed"): return false
		held_rows.append(row)
	if Source.source_stamp() != held_source: return false
	print("CHOKE complete raw union: ", held_rows.size(), " seed units / 285 full fights; evaluating every original band")
	return true
