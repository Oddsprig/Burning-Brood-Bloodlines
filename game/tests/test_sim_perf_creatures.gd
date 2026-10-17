extends RefCounted
## Performance gate with creatures (monsters wave 1): 50 men vs 50 wolves in packs, then 50 men vs a mixed
## pack (wolves, boars, bears), on 64x36, full logging. Same method and gates as tests/test_sim_perf.gd:
## every tick's cost is the minimum of two deterministic runs; mean < 1 ms, worst tick < 2 ms.

const MEAN_GATE_MS := 1.0
const WORST_GATE_MS := 2.0

func _beasts(rng: RandomNumberGenerator, n: int, mixed: bool) -> Array:
	var out := []
	var kinds := ["wolf", "wolf", "boar", "wolf", "bear"] if mixed else ["wolf"]
	var i := 0
	while out.size() < n:
		var cid: String = kinds[i % kinds.size()]
		i += 1
		out.append_array(Creatures.make_group(rng, cid, mini(n - out.size(), 5 if cid == "wolf" else (3 if cid == "boar" else 1))))
	return out

func _times(seed: int, mixed: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var a := Factory.make_warband(rng, "middle_kingdom", 50)
	var b := _beasts(rng, 50, mixed)
	var sim := BattleSim.new()
	sim.setup(a, b, seed, {"w": 64, "h": 36, "log_moves": true})
	var times := PackedFloat64Array()
	while not sim.is_over():
		var t0 := Time.get_ticks_usec()
		sim.step()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	return {"t": times, "sim": sim}

func run(_tree: SceneTree) -> int:
	var fails := 0
	var worst_mean := 0.0
	var worst_tick := 0.0
	for cfg in [[60, false], [61, false], [62, true]]:
		var r1 := _times(cfg[0], cfg[1])
		var r2 := _times(cfg[0], cfg[1])
		var t1: PackedFloat64Array = r1["t"]
		var t2: PackedFloat64Array = r2["t"]
		var sim: BattleSim = r1["sim"]
		if t1.size() != t2.size():
			print("FAIL: creature battle not deterministic"); fails += 1
		var total := 0.0
		var worst := 0.0
		var wi := 0
		for i in mini(t1.size(), t2.size()):
			var t := minf(t1[i], t2[i])
			total += t
			if t > worst:
				worst = t
				wi = i + 1
		var wc := {}
		for e in sim.events:
			if e["tick"] == wi:
				wc[e["type"]] = int(wc.get(e["type"], 0)) + 1
		print("  worst tick %d: %s" % [wi, str(wc)])
		var mean := total / maxf(1.0, float(t1.size()))
		var dead := sim.fighters.filter(func(f): return f.state == "dead").size()
		print("50 men vs 50 %s seed %d: %d ticks, winner %d, %d dead | mean %.3f ms/tick, worst %.3f" % [
			"mixed beasts" if cfg[1] else "wolves", cfg[0], sim.tick, sim.winner, dead, mean, worst])
		worst_mean = maxf(worst_mean, mean)
		worst_tick = maxf(worst_tick, worst)
	print("creature 50v50 gate: mean %.3f ms (gate %.1f), worst tick %.3f ms (gate %.1f)" % [worst_mean, MEAN_GATE_MS, worst_tick, WORST_GATE_MS])
	if worst_mean >= MEAN_GATE_MS:
		print("FAIL: mean ms/tick over the gate"); fails += 1
	if worst_tick >= WORST_GATE_MS:
		print("FAIL: worst tick over the gate"); fails += 1
	return fails
