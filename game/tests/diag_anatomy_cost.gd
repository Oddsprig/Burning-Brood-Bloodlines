extends RefCounted
## DIAGNOSTIC (not a regression test; run only when asked): what one unit costs and what a battle tick costs.
##   memory   2,000 human warband units made and held: static memory per unit, and the body's share of it
##   save     JSON of Unit.to_dict per unit (fresh, and after one 50v50 battle for the survivors)
##   battle   one 50v50 on 64x36 (seed 50, full logging): mean, p99 and worst ms per tick (one run, no min-of-two)
## Used for the v0.013 anatomy work (before / after numbers in DEV_NOTES).

func run(_tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var keep := []
	var m0 := OS.get_static_memory_usage()
	for i in 20:
		keep.append_array(Factory.make_warband(rng, "middle_kingdom", 100))
	var m1 := OS.get_static_memory_usage()
	var n := keep.size()
	var bodies := []
	var m2 := OS.get_static_memory_usage()
	for u in keep:
		var b := BodyState.new()
		b.plan_id = u.body.plan_id
		b.init_from_plan(DB.bodies[b.plan_id], u.rolled_mass())
		bodies.append(b)
	var m3 := OS.get_static_memory_usage()
	var save := 0
	var body_save := 0
	for u in keep:
		save += JSON.stringify(u.to_dict()).length()
		body_save += JSON.stringify(u.body.to_dict()).length()
	print("units %d: memory %.1f KB a unit (body alone %.1f KB); save %.2f KB a unit (body %.2f KB)" % [n,
		float(m1 - m0) / n / 1024.0, float(m3 - m2) / n / 1024.0, float(save) / n / 1024.0, float(body_save) / n / 1024.0])
	bodies.clear()
	keep.clear()
	# one battle
	rng.seed = 50
	var a := Factory.make_warband(rng, "middle_kingdom", 50)
	var b2 := Factory.make_warband(rng, "orc_horde", 50)
	var sim := BattleSim.new()
	sim.setup(a, b2, 50, {"w": 64, "h": 36, "log_moves": true})
	var times := PackedFloat64Array()
	while not sim.is_over():
		var t0 := Time.get_ticks_usec()
		sim.step()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var total := 0.0
	for t in times:
		total += t
	var sorted := times.duplicate()
	sorted.sort()
	print("50v50 seed 50: %d ticks, mean %.3f ms, p99 %.3f, worst %.3f" % [times.size(), total / maxf(1.0, times.size()),
		sorted[int(sorted.size() * 0.99)], sorted[-1]])
	var ws := 0
	var wb := 0
	var wn := 0
	for u in a + b2:
		if u.dead:
			continue
		Healing.after_battle(u)
		ws += JSON.stringify(u.to_dict()).length()
		wb += JSON.stringify(u.body.to_dict()).length()
		wn += 1
	print("survivors %d after the battle: save %.2f KB a unit (body %.2f KB)" % [wn, float(ws) / maxf(1, wn) / 1024.0, float(wb) / maxf(1, wn) / 1024.0])
	return 0
