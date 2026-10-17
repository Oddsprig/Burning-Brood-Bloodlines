extends RefCounted
## "Not invincible" (Douglas): every loss-relevant probability in the strike chain must stay strictly above zero even
## for an extreme skill gap (a scrub attacking a maxed veteran). Mechanical check of the formulas; no outcomes counted.

const U = preload("res://tests/sim_util.gd")

func _check(name: String, p: float) -> int:
	var ok := p > 0.0
	print("  %-62s %.4f  %s" % [name, p, "ok" if ok else "FAIL (clamped to 0)"])
	return 0 if ok else 1

func run(_tree: SceneTree) -> int:
	var fails := 0
	print("scrub (effective level 0) vs maxed defender (effective level 60):")
	fails += _check("attack gets through the one defence (contest)", Formulas.contest_through(0.0, 60.0))
	fails += _check("contest at an absurd gap (0 vs 1000) is still above 0", Formulas.contest_through(0.0, 1000.0))
	if absf(Formulas.contest_through(7.0, 7.0) - 0.5) > 1e-9 or Formulas.contest_through(1000.0, 0.0) >= 1.0 or absf(Formulas.contest_through(0.0, 60.0) - 0.0001) > 1e-9:
		print("  contest must be 0.5 at even odds, 0.0001 at a huge gap, and below 1"); fails += 1
	var p_def := maxf(0.0, 1.0 - Formulas.contest_through(0.0, 60.0) - Formulas.saturation(0))
	fails += _check("defence fails (1 - P(defend))", 1.0 - p_def)
	fails += _check("rear attack unseen (1 - spot chance, observer 20)", 1.0 - Formulas.spot_chance(true, 20.0, 12.0))
	fails += _check("strike quality > 0 (minimum quality)", Formulas.SQ_MIN)
	fails += _check("artery roll on a cut (shallowest cut)", Formulas.ARTERY_CHANCE * 0.01)
	fails += _check("morale: rout chance at max courage/discipline below 25", Formulas.rout_chance(24.0, 100.0, 20.0))
	# Armor: every part of a fully kitted veteran must leave a gap or be uncovered somewhere (coverage < 100 or parts bare),
	# and a thrust's coverage roll never reaches exactly 100 for every piece at once.
	var v := U.veteran(100, U.good_copper(5))
	var sim := BattleSim.new()
	sim.setup([v], [U.recruit()], 1, {"w": 8, "h": 4})
	var f: Fighter = sim.fighters[0]
	var exposed := 0.0
	var total := 0.0
	for p in v.body.plan()["parts"]:
		var pid: String = p["id"]
		var rel := float(p.get("relsize", 100))
		total += rel
		var miss := 1.0
		for it in f.armor_for.get(pid, []):
			if String(it["mat"].get("kind", "")) == "metal":
				miss *= 1.0 - Formulas.coverage(it["cov"], false, 0.0, 1000.0, float(v.skill("armor_user"))) / 100.0
		exposed += rel * miss
	fails += _check("chance a blow lands where no metal covers (relsize-weighted)", exposed / total)
	# Body part roll: every attached part keeps weight > 0.
	var minw := INF
	for p in v.body.plan()["parts"]:
		minw = minf(minw, float(p.get("relsize", 100)))
	fails += _check("smallest body-part target weight (relsize)", minw)
	# A scrub's blow on bare flesh can still cut (copper sword vs skin: energy at minimum quality vs resistance).
	var r := U.recruit()
	var sim2 := BattleSim.new()
	sim2.setup([r], [v], 2, {"w": 8, "h": 4})
	var sw := sim2._swing_for(sim2.fighters[0], DB.weapons["arming_sword"]["attacks"][0])
	var e_min: float = float(sw["E"]) * Formulas.SQ_MIN
	var r_skin := Formulas.edge_resistance(DB.materials["skin"], DB.materials["copper"], 20000.0, 1.0, 1.0, 2.0, false)
	fails += _check("scrub's weakest slash cuts skin (E_min / R_skin capped at 1)", minf(1.0, e_min / r_skin) if e_min >= r_skin else 0.0)
	return fails
