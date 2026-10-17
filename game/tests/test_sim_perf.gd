extends RefCounted
## Performance gate (Douglas: phones). 50v50 on a 64x36 map, no rendering, full calc logging on.
## Prints ticks/sec, mean and worst ms per tick. Gate: mean < 1 ms, worst tick < 2 ms on the dev laptop.
## The battle is deterministic, so each seed is run twice and every tick's cost is the minimum of the two runs:
## that filters one-off OS/GC spikes on a shared machine while keeping genuinely heavy ticks.
## Also runs a 5v5 to completion.

const U = preload("res://tests/sim_util.gd")
const MEAN_GATE_MS := 1.0
const WORST_GATE_MS := 2.0

## bows: n a side of which `archers` are bowmen (March bowmen vs northern fell hunters, the rest their melee troops).
static func _with_archers(rng: RandomNumberGenerator, fid: String, archer_name: String, n: int, archers: int) -> Array:
	var troops: Array = DB.factions[fid]["troops"]
	var bow_t: Dictionary = {}
	var melee := []
	for t in troops:
		if t["name"] == archer_name:
			bow_t = t
		else:
			melee.append(t)
	var out := []
	var k := maxi(1, n / maxi(1, archers))
	var nb := 0
	for i in n:
		if i % k == 0 and nb < archers:
			out.append(Factory.make_troop(rng, fid, bow_t))
			nb += 1
		else:
			out.append(Factory.make_troop(rng, fid, melee[i % melee.size()]))
	return out

func _times(n: int, seed: int, w: int, h: int, archers: int = 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a: Array
	var b: Array
	if archers > 0:
		a = _with_archers(rng, "middle_kingdom", "March bowman", n, archers)
		b = _with_archers(rng, "northern_clans", "fell hunter", n, archers)
	else:
		a = Factory.make_warband(rng, "middle_kingdom", n)
		b = Factory.make_warband(rng, "orc_horde", n)
	var sim := BattleSim.new()
	sim.setup(a, b, seed, {"w": w, "h": h, "log_moves": true})
	var times := PackedFloat64Array()
	while not sim.is_over():
		var t0 := Time.get_ticks_usec()
		sim.step()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var dead := 0
	var fled := 0
	for f in sim.fighters:
		if f.state == "dead":
			dead += 1
		elif f.state == "fled" or f.routed:
			fled += 1
	return {"t": times, "sim": sim, "dead": dead, "fled": fled}

func _run(n: int, seed: int, w: int, h: int, label: String, archers: int = 0) -> Dictionary:
	var r1 := _times(n, seed, w, h, archers)
	var r2 := _times(n, seed, w, h, archers)
	var t1: PackedFloat64Array = r1["t"]
	var t2: PackedFloat64Array = r2["t"]
	var sim: BattleSim = r1["sim"]
	var times := PackedFloat64Array()
	var total := 0.0
	var worst_raw := 0.0
	for i in mini(t1.size(), t2.size()):
		times.append(minf(t1[i], t2[i]))
		total += times[i]
		worst_raw = maxf(worst_raw, maxf(t1[i], t2[i]))
	var sorted := times.duplicate()
	sorted.sort()
	var worst: float = sorted[-1] if sorted.size() > 0 else 0.0
	var wi := 0
	for i in times.size():
		if times[i] == worst:
			wi = i + 1
	var wc := {}
	for e in sim.events:
		if e["tick"] == wi:
			wc[e["type"]] = int(wc.get(e["type"], 0)) + 1
	var shots := 0
	for f in sim.fighters:
		shots += f.shots
	print("  worst tick %d: %s%s" % [wi, str(wc), (" | %d arrows shot" % shots) if shots > 0 else ""])
	var p99: float = sorted[int(sorted.size() * 0.99)] if sorted.size() > 0 else 0.0
	var mean := total / maxf(1.0, float(times.size()))
	print("%s: %d ticks (%.1f s game time), winner %d, %d dead, %d fled/routed, %d events | %.0f ticks/s, mean %.3f ms/tick, p99 %.3f, worst %.3f (raw single-run worst %.3f)" % [
		label, sim.tick, sim.tick * Formulas.TICK_SECONDS, sim.winner, r1["dead"], r1["fled"], sim.events.size(), 1000.0 / maxf(mean, 0.0001), mean, p99, worst, worst_raw])
	return {"mean": mean, "worst": worst, "p99": p99, "over": sim.is_over() and t1.size() == t2.size()}

func run(_tree: SceneTree) -> int:
	var fails := 0
	var s5 := _run(5, 5, 32, 18, "5v5 32x18")
	if not s5["over"]:
		fails += 1
	var worst_mean := 0.0
	var worst_tick := 0.0
	var worst_p99 := 0.0
	for seed in [50, 51, 52]:
		var r := _run(50, seed, 64, 36, "50v50 64x36 seed %d" % seed)
		worst_mean = maxf(worst_mean, r["mean"])
		worst_tick = maxf(worst_tick, r["worst"])
		worst_p99 = maxf(worst_p99, r["p99"])
		if not r["over"]:
			print("FAIL: battle did not end or the two runs diverged"); fails += 1
	# bows (spec 7): the same gate with ~15 archers a side (arrows in flight, line tests on the coarse grid)
	for seed in [53, 54]:
		var ra := _run(50, seed, 64, 36, "50v50 64x36 with 15 archers a side, seed %d" % seed, 15)
		worst_mean = maxf(worst_mean, ra["mean"])
		worst_tick = maxf(worst_tick, ra["worst"])
		worst_p99 = maxf(worst_p99, ra["p99"])
		if not ra["over"]:
			print("FAIL: battle did not end or the two runs diverged"); fails += 1
	print("50v50 gate: mean %.3f ms (gate %.1f), p99 %.3f, worst tick %.3f ms (gate %.1f)" % [worst_mean, MEAN_GATE_MS, worst_p99, worst_tick, WORST_GATE_MS])
	if worst_mean >= MEAN_GATE_MS:
		print("FAIL: mean ms/tick over the gate"); fails += 1
	if worst_tick >= WORST_GATE_MS:
		print("FAIL: worst tick over the gate"); fails += 1
	return fails
