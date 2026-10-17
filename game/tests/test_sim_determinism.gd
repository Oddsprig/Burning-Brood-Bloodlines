extends RefCounted
## Same seed + same units = identical events and logs; a different seed differs.

const U = preload("res://tests/sim_util.gd")

func _battle(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var a := Factory.make_warband(rng, "middle_kingdom", 6)
	var b := Factory.make_warband(rng, "orc_horde", 6)
	var sim: BattleSim = U.run(a, b, seed, {"w": 24, "h": 12, "log_moves": true})
	var sig := []
	for e in sim.events:
		sig.append("%d|%s|%d|%d|%s" % [e["tick"], e["type"], e["actor"], e["target"], BattleSim.event_text(e)])
	for f in sim.fighters:
		for le in f.log:
			var r := BattleSim.render_entry(le)
			sig.append("%d:%s:%s" % [le["tick"], r["text"], r["calc"].md5_text()])
		sig.append("%s %.4f %.4f" % [f.state, f.unit.body.blood, f.unit.body.pain])
	return [sim.winner, sim.tick, sig]

func run(_tree: SceneTree) -> int:
	var fails := 0
	var r1 := _battle(4242)
	var r2 := _battle(4242)
	var r3 := _battle(4243)
	print("seed 4242: winner %d at tick %d, %d signature lines; seed 4243: winner %d at tick %d" % [r1[0], r1[1], r1[2].size(), r3[0], r3[1]])
	if r1[0] != r2[0] or r1[1] != r2[1] or r1[2] != r2[2]:
		print("FAIL: same seed gave different results"); fails += 1
		for i in mini(r1[2].size(), r2[2].size()):
			if r1[2][i] != r2[2][i]:
				print("  first difference at line %d:\n  %s\n  %s" % [i, r1[2][i], r2[2][i]])
				break
	if r1[2] == r3[2]:
		print("FAIL: a different seed gave an identical battle"); fails += 1
	return fails
