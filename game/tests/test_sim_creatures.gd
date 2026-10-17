extends RefCounted
## Monsters wave 1 on the tissue sim (docs/specs/monsters-wave1.md, blocking tests):
## - creature data: quadruped plan with coat layers (fur, thick hide), relsize targeting, rarity on every type
## - a wolf's latching bite takes hold through the wrestling grab code and drags a man down
## - a bear bite can penetrate copper mail (a wolf's cannot: metal stops teeth)
## - a boar's charge momentum scales with body mass x run speed
## - mixed battles run to completion; logs render; health report reads a creature body

const U = preload("res://tests/sim_util.gd")

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _sim(a: Array, b: Array, seed: int) -> BattleSim:
	var sim := BattleSim.new()
	sim.setup(a, b, seed, {"w": 10, "h": 5, "cells0": [Vector2i(4, 2)], "cells1": [Vector2i(5, 2)]})
	return sim

func run(_tree: SceneTree) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# ---------------------------------------------------------------- data
	for cid in ["wolf", "bear", "boar"]:
		var d := Creatures.def(cid)
		check(not d.is_empty(), "%s missing" % cid)
		check(Creatures.RARITIES.has(String(d.get("rarity", ""))), "%s has no rarity" % cid)
		var u := Creatures.make(rng, cid)
		var plan := u.body.plan()
		check(u.body.parts.has("leg_front_upper_l") and u.body.parts.has("tail"), "%s is not a quadruped" % cid)
		var outer: String = u.body.parts["torso_upper"]["layers"][0]["tissue"]
		check(outer == "fur", "%s coat: outer layer %s" % [cid, outer])
		print("%s: %s, %.0f kg, rarity %s, %d parts, torso layers %s" % [cid, u.title, u.mass(), Creatures.rarity(cid), plan["parts"].size(),
			str(u.body.parts["torso_upper"]["layers"].map(func(l): return "%s %.0fmm" % [l["tissue"], l["t"]]))])
	for cid in Creatures.ids(true):
		check(Creatures.RARITIES.has(Creatures.rarity(cid)), "rarity field on every creature type (%s)" % cid)
	# ---------------------------------------------------------------- wolf latch pulls a man down (grab code)
	var latched := 0
	var dragged := 0
	for s in 6:
		var man := U.soldier("copper", "arming_sword", "mail_shirt", "nasal_helm", "kite_shield")
		var wolf := Creatures.make(rng, "wolf")
		var sim := _sim([man], [wolf], 100 + s)
		var m: Fighter = sim.fighters[0]
		var w: Fighter = sim.fighters[1]
		var bite: Dictionary = {}
		for a in NaturalAttacks.attacks_for(sim, w, m):
			if a.get("latch", false):
				bite = a
		check(not bite.is_empty(), "wolf has no latching bite")
		var tries := 0
		while w.grabbing < 0 and tries < 60 and m.alive():
			tries += 1
			w.target = m.idx
			sim._force_part = "leg_lower_r"   # unarmoured shin: trousers only
			sim._force_land = true
			sim._strike(w, m, bite, sim._swing_for(w, bite), {})
			sim._force_part = ""
			sim._force_land = false
			NaturalAttacks.after_strike(sim, w, m, bite)
		if w.grabbing == m.idx and m.grabbed_by == w.idx:
			latched += 1
		var dt := 0
		while w.grabbing == m.idx and not m.prone and dt < 40 and m.alive():
			dt += 1
			NaturalAttacks.drag(sim, w, m.idx)
		if m.prone and w.grabbing == m.idx:
			dragged += 1
		if s == 0:
			print("latch after %d bites, man down after %d drags (drag chance %.2f); log: %s" % [tries, dt,
				NaturalAttacks.drag_chance(sim, w, m), str(m.log.slice(-3).map(func(e): return BattleSim.render_entry(e)["text"]))])
	print("wolf latch: %d/6 latched, %d/6 dragged the man down" % [latched, dragged])
	check(latched >= 5, "wolf bites rarely latch through the grab code")
	check(dragged >= 4, "a latched wolf should drag a man down")
	# pack drag: two wolves holding the same man pull harder than one
	var man2 := U.soldier("copper")
	var w1 := Creatures.make(rng, "wolf")
	var w2 := Creatures.make(rng, "wolf")
	var sim2 := BattleSim.new()
	sim2.setup([man2], [w1, w2], 7, {"w": 10, "h": 5, "cells0": [Vector2i(4, 2)], "cells1": [Vector2i(5, 2), Vector2i(4, 3)]})
	var m2: Fighter = sim2.fighters[0]
	var f1: Fighter = sim2.fighters[1]
	var f2: Fighter = sim2.fighters[2]
	sim2._targets = [[m2], [f1, f2]]
	f1.grabbing = m2.idx; m2.grabbed_by = f1.idx
	var one := NaturalAttacks.drag_chance(sim2, f1, m2)
	f2.grabbing = m2.idx
	var two := NaturalAttacks.drag_chance(sim2, f1, m2)
	print("drag chance: one wolf %.2f, two wolves %.2f" % [one, two])
	check(two > one, "pack mass should add to the drag")
	# ---------------------------------------------------------------- bear bite vs copper mail
	var res := {}
	for cid in ["bear", "wolf"]:
		var covered := 0
		var through := 0
		for i in 150:
			var man3 := U.soldier("copper")
			var c := Creatures.make(rng, cid)
			var sim3 := _sim([man3], [c], 500 + i)
			var b3: Fighter = sim3.fighters[1]
			var bite3: Dictionary = NaturalAttacks.attacks_for(sim3, b3, sim3.fighters[0])[0]
			check(bite3.get("verb", "") == "bite", "%s first attack should be the bite" % cid)
			b3.target = 0
			sim3._force_part = "torso_upper"
			sim3._force_land = true
			sim3._strike(b3, sim3.fighters[0], bite3, sim3._swing_for(b3, bite3), {})
			var ls: Dictionary = sim3.last_strike
			for a in ls.get("armor", []):
				if String(a["name"]).contains("mail"):
					covered += 1
					if a["result"] == "cut":
						through += 1
		res[cid] = [through, covered]
		print("%s bites on the copper-mailed chest: mail covered %d, bitten through %d (%.0f%%)" % [cid, covered, through, 100.0 * through / maxf(1.0, covered)])
	check(res["bear"][0] > 0 and float(res["bear"][0]) / maxf(1.0, res["bear"][1]) >= 0.25, "a bear bite should be able to punch through copper mail")
	check(float(res["wolf"][0]) / maxf(1.0, res["wolf"][1]) < float(res["bear"][0]) / maxf(1.0, res["bear"][1]), "metal should stop wolf teeth better than bear teeth")
	# ---------------------------------------------------------------- boar charge momentum = mass x speed
	check(is_equal_approx(NaturalAttacks.charge_momentum(120.0, 5.0), 2.0 * NaturalAttacks.charge_momentum(60.0, 5.0)), "charge p not linear in mass")
	check(is_equal_approx(NaturalAttacks.charge_momentum(60.0, 8.0), 2.0 * NaturalAttacks.charge_momentum(60.0, 4.0)), "charge p not linear in speed")
	var small := Creatures.make(rng, "boar")
	var big := Creatures.make(rng, "boar")
	small.size_h = 90; small.size_b = 90
	big.size_h = 120; big.size_b = 120
	var sim4 := BattleSim.new()
	sim4.setup([U.soldier("copper")], [small, big], 3, {"w": 10, "h": 5})
	var fs: Fighter = sim4.fighters[1]
	var fb: Fighter = sim4.fighters[2]
	fs.tempo = 1.0; fb.tempo = 1.0
	fs.last_move_tick = sim4.tick; fb.last_move_tick = sim4.tick
	var charge: Dictionary = {}
	for a in NaturalAttacks.attacks_for(sim4, fs, sim4.fighters[0]):
		if a.get("charge", false):
			charge = a
	check(not charge.is_empty(), "a boar after a run-up should be able to charge")
	var ps := float(NaturalAttacks.swing(fs, charge, 1000.0, 0.0)["p"])
	var pb := float(NaturalAttacks.swing(fb, charge, 1000.0, 0.0)["p"])
	print("boar charge: %.0f kg -> p %.1f, %.0f kg -> p %.1f (mass ratio %.2f, p ratio %.2f)" % [small.mass(), ps, big.mass(), pb, big.mass() / small.mass(), pb / ps])
	check(absf(pb / ps - big.mass() / small.mass()) < 0.01, "charge momentum should scale with mass")
	fb.tempo = 2.0   # half as fast (wounded, tired)
	var pslow := float(NaturalAttacks.swing(fb, charge, 1000.0, 0.0)["p"])
	check(absf(pslow / pb - 0.5) < 0.01, "charge momentum should scale with speed")
	fs.last_move_tick = -1000
	var no_charge := true
	for a in NaturalAttacks.attacks_for(sim4, fs, sim4.fighters[0]):
		if a.get("charge", false):
			no_charge = false
	check(no_charge, "no charge without a run-up")
	# ---------------------------------------------------------------- full battles: packs vs men, logs render
	var counts := {}
	var wins := [0, 0]
	for s in 8:
		var r2 := RandomNumberGenerator.new(); r2.seed = 40 + s
		var men := Factory.make_warband(r2, "middle_kingdom", 3)
		var beasts: Array = Creatures.make_group(r2, ["wolf", "boar", "bear", "wolf"][s % 4], [5, 3, 1, 6][s % 4])
		var sim5 := BattleSim.new()
		sim5.setup(men, beasts, 900 + s, {"w": 24, "h": 12})
		while not sim5.is_over():
			sim5.step()
		if sim5.winner >= 0:
			wins[sim5.winner] += 1
		for e in sim5.events:
			var k := String(e.get("entry", {}).get("d", {}).get("key", ""))
			if k in ["latch_ok", "drag_ok", "drag_fail"]:
				counts[k] = int(counts.get(k, 0)) + 1
			if e.has("entry") or e["decisive"]:
				var txt := BattleSim.event_text(e)
				check(txt != "" and not txt.contains("{"), "unrendered log line: %s" % txt)
		for f in sim5.fighters:
			if f.side == 1 and f.unit.body.is_wounded():
				var rep := HealthReport.describe(f.unit)
				check(rep is Dictionary and rep.has("status"), "health report of a creature")
		if s < 4:
			var lines := []
			for e in sim5.events:
				if e["type"] in ["hit", "sever", "death", "fall", "rout"] and lines.size() < 4 and e["actor"] >= 0 and sim5.fighters[e["actor"]].side == 1:
					lines.append(BattleSim.event_text(e))
			print("  %s pack vs 3 men: winner %d after %d ticks; %s" % [beasts[0].race, sim5.winner, sim5.tick, " | ".join(lines)])
	print("packs vs men: men won %d, beasts won %d; latch/drag events %s (TRACKED)" % [wins[0], wins[1], str(counts)])
	check(int(counts.get("latch_ok", 0)) > 0, "no latch in eight beast battles")
	return fails
