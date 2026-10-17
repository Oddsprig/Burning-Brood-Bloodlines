extends RefCounted
## bows (docs/specs/bows.md): the archer's power and skill model, flight, defences, pass-through, quivers and the
## kiting AI. Gates are mechanical (Douglas: outcomes are whatever the mechanics produce): the energy rule, skill
## never adding energy, no friendly fire, the x2 shield block, the boss, wood tips vs copper mail, pass-through,
## the quiver cap and consumption, sidearm switching. Rates are printed as TRACKED.

const U = preload("res://tests/sim_util.gd")

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

## An archer: bow (template, quality), sidearm, clothes, bow skill and a quiver.
static func archer(bow: String, q: int = 0, skill: int = 5, arrows: Dictionary = {"arrow_copper_bodkin": 30}, strength: int = 1000,
		armour: Array = []) -> Unit:
	var g := [[bow, "wood", q], ["arming_sword", "copper"], ["tunic", "linen"], ["trousers", "linen"], ["shoes", "leather"]]
	g.append_array(armour)
	var u := U.make("human", g, {"bow": skill, "sword": 2, "dodger": 2, "fighter": 2}, "Archer")
	u.attrs["STR"] = strength
	for k in arrows:
		u.quiver[k] = int(arrows[k])
	return u

static func target(gear: Array = [], skills: Dictionary = {}) -> Unit:
	var g := [["tunic", "linen"], ["trousers", "linen"], ["shoes", "leather"]]
	g.append_array(gear)
	return U.make("human", g, skills, "Target")

static func sim_of(a: Array, b: Array, seed: int, opts: Dictionary = {}) -> BattleSim:
	var sim := BattleSim.new()
	var o := {"w": 24, "h": 9, "log_moves": false, "verbose": true}
	o.merge(opts, true)
	sim.setup(a, b, seed, o)
	return sim

func run(_tree: SceneTree) -> int:
	_test_energy()
	_test_skill_spread()
	_test_quiver()
	_test_no_friendly_fire()
	_test_shield()
	_test_wood_vs_mail()
	_test_pass_through()
	_test_sidearm_switch()
	_test_log_lines()
	return fails

# ---------------------------------------------------------------- 1. power: min(archer draw, bow limit) x efficiency
func _test_energy() -> void:
	print("-- energy (anchors: hunting bow ~50 J, war bow ~100-130 J; not targets)")
	for b in ["hunting_bow", "self_bow", "goblin_shortbow", "ash_war_bow", "march_longbow", "orc_slab_bow", "moon_recurve", "moon_longbow"]:
		var bt: Dictionary = DB.bows[b]
		var line := "  %-16s %3d N x %.2f m stores %5.1f J |" % [b, int(bt["draw_n"]), float(bt["draw_m"]), Formulas.bow_store(float(bt["draw_n"]), float(bt["draw_m"]))]
		for st in [800, 1000, 1500, 2500]:
			var pull := Formulas.pull_force(float(st), 70.0, 1000.0, 0.0, 0.0, 1.0)
			var sol := Formulas.bow_shot(pull, Formulas.draw_length(1.0, 100.0), bt, 1.0, 1.0, DB.arrows["arrow_copper_bodkin"]["mass"])
			line += " STR %d: %5.1f J%s" % [st, float(sol["E"]), "*" if sol["partial"] else " "]
		print(line)
	var war := Formulas.bow_shot(Formulas.pull_force(2500.0, 80.0, 1500.0, 0.0, 0.0, 1.0), Formulas.draw_length(1.0, 104.0),
		DB.bows["march_longbow"], DB.quality_mult(5), 1.05, DB.arrows["arrow_copper_war"]["mass"])
	print("  master's masterwork longbow, heavy war bodkin (%.0f g): %.1f J at %.1f m/s, p %.2f   (* = partial draw)" % [
		float(war["m"]) * 1000.0, float(war["E"]), float(war["v0"]), float(war["p"])])
	# the rule itself: E = min(what the archer can draw into this bow, what the bow stores) x efficiency
	var bt2: Dictionary = DB.bows["march_longbow"]
	var m := float(DB.arrows["arrow_copper_bodkin"]["mass"])
	for st in [600, 1000, 1400, 2000, 3000, 4000]:
		var pull := Formulas.pull_force(float(st), 70.0, 1000.0, 0.0, 0.0, 1.0)
		var reach := Formulas.draw_length(1.0, 100.0)
		var s := Formulas.bow_shot(pull, reach, bt2, 1.0, 1.0, m)
		var expect := minf(Formulas.archer_draw_energy(pull, reach, float(bt2["draw_n"]), float(bt2["draw_m"])),
			Formulas.bow_store(float(bt2["draw_n"]), float(bt2["draw_m"]))) * float(s["eff"])
		check(absf(float(s["E"]) - expect) < 0.001, "STR %d: E %.3f != min(draw, limit) x eff %.3f" % [st, float(s["E"]), expect])
	var strong := Formulas.bow_shot(Formulas.pull_force(2500.0, 70.0, 1000.0, 0.0, 0.0, 1.0), 0.75, DB.bows["self_bow"], 1.0, 1.0, m)
	var stronger := Formulas.bow_shot(Formulas.pull_force(4000.0, 70.0, 1000.0, 0.0, 0.0, 1.0), 0.75, DB.bows["self_bow"], 1.0, 1.0, m)
	check(absf(float(strong["E"]) - float(stronger["E"])) < 0.0001, "extra STR added energy to a fully drawn bow (%.2f vs %.2f)" % [strong["E"], stronger["E"]])
	check(float(stronger["strain"]) < float(strong["strain"]), "extra STR should steady the hold (lower strain)")
	var weak := Formulas.bow_shot(Formulas.pull_force(600.0, 70.0, 1000.0, 0.0, 0.0, 1.0), 0.75, DB.bows["march_longbow"], 1.0, 1.0, m)
	check(weak["partial"] and float(weak["E"]) < float(weak["e_bow"]) * float(weak["eff"]), "a weak archer partly draws a heavy bow")
	print("  weak archer (STR 600) on the longbow: partial draw %.0f%%, %.1f J of %.1f" % [float(weak["x"]) * 100.0, float(weak["E"]), float(weak["e_bow"]) * float(weak["eff"])])

# ---------------------------------------------------------------- 2. skill narrows the spread, never adds energy
func _test_skill_spread() -> void:
	var novice := archer("self_bow", 0, 0)
	var master := archer("self_bow", 0, 15)
	var dummy := target()
	var sim := sim_of([novice, master], [dummy], 1)
	var sn := Archery.solution(sim, sim.fighters[0], "arrow_copper_bodkin", true)
	var sm := Archery.solution(sim, sim.fighters[1], "arrow_copper_bodkin", true)
	check(absf(float(sn["E"]) - float(sm["E"])) < 0.0001, "bow skill changed the arrow's energy (%.2f vs %.2f)" % [sn["E"], sm["E"]])
	var sdn := Formulas.aim_sd(float(sn["lvl"]), float(sn["strain"]), 1.0, 50.0, false, false, 0)
	var sdm := Formulas.aim_sd(float(sm["lvl"]), float(sm["strain"]), 1.0, 50.0, false, false, 0)
	check(sdm < sdn, "skill should narrow the aim spread (%.2f vs %.2f)" % [sdm, sdn])
	check(Formulas.aim_ticks(float(sm["lvl"])) < Formulas.aim_ticks(float(sn["lvl"])), "skill should shorten the aim")
	var sdq := Formulas.aim_sd(float(sn["lvl"]), float(sn["strain"]), DB.quality_mult(5), 50.0, false, false, 0)
	check(sdq < sdn, "a better bow should steady aim")
	print("-- skill: E %.1f J for both; aim sd novice %.2f deg, master %.2f deg, novice with a masterwork bow %.2f deg; aim %.0f vs %.0f ticks" % [
		sn["E"], sdn, sdm, sdq, Formulas.aim_ticks(float(sn["lvl"])), Formulas.aim_ticks(float(sm["lvl"]))])
	# empirical hit rate at 10 tiles on a still target (one aim roll per shot, real flight)
	for who in [["novice", 0], ["master", 15]]:
		var hits := 0
		var n := 120
		for i in n:
			var a := archer("self_bow", 0, who[1], {"arrow_wood": 1})
			var t := target()
			var s2 := sim_of([a], [t], 100 + i, {"cells0": [Vector2i(2, 4)], "cells1": [Vector2i(12, 4)], "hold0": true, "hold1": true, "shot_log": true})
			Archery.loose(s2, s2.fighters[0], {"t": 1, "kind": "arrow_wood"})
			for k in 40:
				if s2.projectiles.is_empty():
					break
				Archery.step_projectiles(s2)
			for sl in s2.shot_log:
				if (sl["hit"] as Array).has(1):
					hits += 1
		print("   %s at 10 tiles (15 m): %d/%d arrows reach the man (dodges included)  [TRACKED]" % [who[0], hits, n])

# ---------------------------------------------------------------- 3. quivers: max 50, real consumption
func _test_quiver() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var troop := {"name": "bowman", "skills": {"bow": [2, 4]}, "arrows": {"arrow_copper_bodkin": 40, "arrow_copper_broad": 40},
		"loadout": {"ranged": ["self_bow"], "main_hand": ["arming_sword"], "clothing": ["tunic"]}}
	var u := Factory.make_troop(rng, "middle_kingdom", troop, 2)
	check(u.arrows() == DB.QUIVER_MAX, "a quiver holds at most %d arrows (has %d)" % [DB.QUIVER_MAX, u.arrows()])
	check(u.bow() != null and u.bow().slot() == "ranged", "the bow sits in the ranged slot")
	check(absf(u.bow().vr - 1.0) <= 0.05 + 0.0001, "bow variance within +-5%% (%.3f)" % u.bow().vr)
	var before := u.arrows()
	var foes := []
	for i in 4:
		foes.append(U.soldier("copper", "arming_sword", "", "", ""))
	var sim := sim_of([u], foes, 9, {"w": 30, "h": 9})
	while not sim.is_over():
		sim.step()
	var shots: int = sim.fighters[0].shots
	check(u.arrows() == before - shots, "spent shots must leave the quiver (%d - %d != %d)" % [before, shots, u.arrows()])
	check(u.arrows() <= DB.QUIVER_MAX, "quiver over the cap after battle")
	var landed := 0
	for k in sim.arrow_field:
		for w in sim.arrow_field[k]:
			landed += int(sim.arrow_field[k][w])
	check(landed == shots, "every loosed arrow ends somewhere on the field (%d of %d)" % [landed, shots])
	print("-- quiver: %d arrows, shot %d, %d left; field %s; recovered %s" % [before, shots, u.arrows(), str(sim.arrow_field), str(Archery.recovered(sim.arrow_field))])

# ---------------------------------------------------------------- 4. no friendly fire (also after pass-through)
func _test_no_friendly_fire() -> void:
	var own := []
	var cells0 := []
	for i in 4:
		own.append(archer("march_longbow", 3, 3, {"arrow_copper_war": 50}, 2200))
		cells0.append(Vector2i(1, 2 + i))
	for i in 5:
		own.append(U.soldier("copper", "boar_spear"))
		cells0.append(Vector2i(6, 2 + i))   # the front rank right in the line of fire
	var foes := []
	var cells1 := []
	for i in 6:
		foes.append(U.soldier("tin", "arming_sword", "", "nasal_helm", ""))
		cells1.append(Vector2i(14, 1 + i))
	var sim := sim_of(own, foes, 21, {"w": 24, "h": 9, "cells0": cells0, "cells1": cells1, "hold0": true, "shot_log": true})
	while not sim.is_over():
		sim.step()
	var ff := 0
	var arrows := 0
	for sl in sim.shot_log:
		arrows += 1
		for h in sl["hit"]:
			if sim.fighters[int(h)].side == sim.fighters[int(sl["a"])].side:
				ff += 1
	for f in sim.fighters:
		for le in f.log:
			var d: Dictionary = le["d"]
			if le["k"] == "strike" and d.has("shot") and sim.fighters[int(d["a"])].side == sim.fighters[int(d["d"])].side:
				ff += 1
	check(arrows > 10, "the archers should have shot (%d arrows)" % arrows)
	check(ff == 0, "friendly fire: %d arrows struck their own side" % ff)
	print("-- no friendly fire: %d arrows over their own front rank, 0 struck a friend; winner %d at tick %d" % [arrows, sim.winner, sim.tick])

# ---------------------------------------------------------------- 5. shields: x2 block vs projectiles; the boss stops
func _test_shield() -> void:
	var blocks := 0
	var tries := 0
	var x2_ok := true
	var spots := {}
	var n := 500
	var pdefs := 0.0
	for i in n:
		var a := archer("self_bow", 0, 2, {"arrow_copper_bodkin": 5})
		var t := target([["kite_shield", "copper"]], {"shield_user": 6, "dodger": 0})
		var sim := sim_of([a], [t], 7000 + i, {"cells0": [Vector2i(2, 4)], "cells1": [Vector2i(10, 4)]})
		sim.fighters[1].facing = -1
		var r := Archery.debug_shot(sim, 0, 1, "arrow_copper_bodkin", 8.0)
		var steps: Array = []
		var le: Dictionary = {}
		var lg: Array = sim.fighters[1].log
		for li in range(lg.size() - 1, -1, -1):
			if lg[li]["k"] == "strike":
				le = lg[li]
				break
		steps = le["d"].get("steps", [])
		for s in steps:
			if s is Array and s[0] == "def" and String(s[1]).begins_with("block"):
				tries += 1
				var pt: float = s[3]
				var sat: float = s[4]
				var expect := 1.0 - minf(Formulas.CONTEST_MAX, maxf(0.0, 1.0 - pt - sat) * Formulas.PROJECTILE_BLOCK_MULT)
				pdefs += 1.0 - float(s[5])
				if absf(float(s[5]) - expect) > 0.0001:
					x2_ok = false
		if r["defence"] == "block":
			blocks += 1
			var sp := String(le["d"].get("spot", "?")) + ":" + String(le["d"].get("out", "?"))
			spots[sp] = int(spots.get(sp, 0)) + 1
	check(tries > 0 and x2_ok, "the block against an arrow must use the projectile x%.0f (tries %d)" % [Formulas.PROJECTILE_BLOCK_MULT, tries])
	check(absf(float(blocks) - pdefs) <= 4.0 * sqrt(maxf(pdefs, 1.0)) + 3.0, "blocks %d far from the x2 expectation %.1f" % [blocks, pdefs])
	print("-- shield: %d/%d arrows met the shield after the dodge, %d blocked (expected %.1f from the logged x2 chances); spots %s" % [tries, n, blocks, pdefs, str(spots)])
	# the boss: a copper boss stops the master's heavy bodkin (layer test at the boss thickness, domed)
	var sh := Item.make("kite_shield", "copper", 0)
	var war := Formulas.bow_shot(Formulas.pull_force(2600.0, 70.0, 1000.0, 0.0, 0.0, 1.0), 0.75, DB.bows["march_longbow"], DB.quality_mult(5), 1.0,
		DB.arrows["arrow_copper_war"]["mass"])
	var th := float(sh.tmpl()["thickness"]) * Formulas.SHIELD_BOSS_THICK
	var R := Formulas.edge_resistance(sh.mat(), DB.materials["copper"], 5.0, 1.0, 1.0, th, true)
	var e_boss := float(war["E"]) * Formulas.SHIELD_BOSS_SQUARE
	check(e_boss < R, "a copper boss should stop the heavy bodkin (%.1f J vs R %.1f)" % [e_boss, R])
	var Rb := Formulas.edge_resistance(sh.mat(), DB.materials["copper"], 5.0, 1.0, 1.0, float(sh.tmpl()["thickness"]), true)
	print("   heavy bodkin %.1f J: copper boss R %.1f (stops), copper plate R %.1f (%s)" % [war["E"], R, Rb, "through" if float(war["E"]) >= Rb else "stops"])

# ---------------------------------------------------------------- 6. wood tips vs copper mail mostly fail
func _test_wood_vs_mail() -> void:
	var a := archer("march_longbow", 0, 5, {"arrow_wood": 50, "arrow_copper_bodkin": 50}, 1500)
	var t := target([["mail_shirt", "copper"]], {"dodger": 0})
	var sim := sim_of([a], [t], 11, {"cells0": [Vector2i(2, 4)], "cells1": [Vector2i(10, 4)]})
	var res := {}
	for kind in ["arrow_wood", "arrow_copper_bodkin", "arrow_tin_bodkin", "arrow_copper_broad"]:
		var met := 0
		var through := 0
		for i in 400:
			var r := Archery.debug_shot(sim, 0, 1, kind, 6.0, "torso_upper", true)
			for am in r["armor"]:
				if String(am["name"]).contains("mail"):
					met += 1
					if String(am["result"]) == "cut":
						through += 1
		res[kind] = [through, met]
	print("-- copper mail over the upper body, longbow (STR 1500) at 9 m: wood %d/%d through, copper bodkin %d/%d, tin bodkin %d/%d, copper broadhead %d/%d" % [
		res["arrow_wood"][0], res["arrow_wood"][1], res["arrow_copper_bodkin"][0], res["arrow_copper_bodkin"][1], res["arrow_tin_bodkin"][0], res["arrow_tin_bodkin"][1],
		res["arrow_copper_broad"][0], res["arrow_copper_broad"][1]])
	check(int(res["arrow_wood"][1]) > 50 and float(res["arrow_wood"][0]) / float(res["arrow_wood"][1]) < 0.1, "wood tips should mostly fail against copper mail")

# ---------------------------------------------------------------- 7. pass-through: a strong master's heavy bodkin hits a second enemy
func _test_pass_through() -> void:
	var twice := 0
	var exits := 0
	var n := 60
	for i in n:
		var a := archer("march_longbow", 5, 15, {"arrow_copper_war": 1}, 2600)
		a.bow().vr = 1.05
		var t1 := target()
		var t2 := target()
		var sim := sim_of([a], [t1, t2], 500 + i, {"cells0": [Vector2i(2, 4)], "cells1": [Vector2i(7, 4), Vector2i(8, 4)], "hold0": true, "hold1": true, "shot_log": true})
		sim.fighters[1].facing = -1
		sim.fighters[2].facing = -1
		Archery.loose(sim, sim.fighters[0], {"t": 1, "kind": "arrow_copper_war"})
		for k in 40:
			if sim.projectiles.is_empty():
				break
			Archery.step_projectiles(sim)
		for sl in sim.shot_log:
			if (sl["hit"] as Array).size() >= 2:
				twice += 1
		for f in sim.fighters:
			for le in f.log:
				if le["k"] == "strike" and le["d"].get("exit", false):
					exits += 1
	exits /= 2   # a strike entry sits in both the archer's and the victim's log
	print("-- pass-through: masterwork longbow, STR 2600 master, heavy bodkins at two unarmoured men in a file: %d/%d shots exit, %d/%d strike the man behind" % [exits, n, twice, n])
	check(twice > 0, "a heavy bodkin from a strong master with a high-quality bow should sometimes pass through and hit the next enemy")

# ---------------------------------------------------------------- 8. kiting: to the sidearm when cornered or out of arrows
func _test_sidearm_switch() -> void:
	# cornered at the map edge with a swordsman coming
	var a := archer("self_bow", 0, 4, {"arrow_copper_bodkin": 50})
	var foe := U.soldier("copper", "arming_sword", "", "", "")
	var sim := sim_of([a], [foe], 5, {"w": 16, "h": 5, "cells0": [Vector2i(0, 2)], "cells1": [Vector2i(9, 2)]})
	var switched := ""
	var sidearm_strikes := 0
	var kites := 0
	while not sim.is_over() and sim.tick < 3000:
		sim.step()
		for e in sim.new_events:
			var en: Dictionary = e.get("entry", {})
			if en.is_empty():
				continue
			var key := String(en["d"].get("key", ""))
			if key in ["drop_bow", "sling_bow"] and switched == "":
				switched = key
			if en["k"] == "strike" and int(en["d"]["a"]) == 0 and not en["d"].has("shot"):
				sidearm_strikes += 1
	print("-- cornered archer: switched by %s, %d sidearm strikes, %d arrows shot, winner %d at tick %d" % [switched if switched != "" else "-", sidearm_strikes, sim.fighters[0].shots, sim.winner, sim.tick])
	check(switched != "", "a cornered archer must switch to the sidearm")
	# out of arrows in open ground: slings the bow and fights with the sidearm
	var b := archer("self_bow", 0, 4, {"arrow_copper_bodkin": 3})
	var foe2 := U.soldier("copper", "arming_sword", "", "", "")
	var sim2 := sim_of([b], [foe2], 6, {"w": 30, "h": 9, "cells0": [Vector2i(10, 4)], "cells1": [Vector2i(26, 4)]})
	var out_seen := false
	var sw := ""
	while not sim2.is_over() and sim2.tick < 3000:
		sim2.step()
		for e in sim2.new_events:
			var en2: Dictionary = e.get("entry", {})
			if en2.is_empty():
				continue
			var k2 := String(en2["d"].get("key", ""))
			if k2 == "out_of_arrows":
				out_seen = true
			if k2 in ["drop_bow", "sling_bow"] and sw == "":
				sw = k2
	print("   archer with 3 arrows: shot %d, out of arrows %s, then %s" % [sim2.fighters[0].shots, out_seen, sw])
	check(out_seen and sw != "" and b.arrows() == 0, "out of arrows: the archer must go to the sidearm")
	# kiting: an archer in open ground backs off as a slow man approaches
	var c := archer("self_bow", 0, 6, {"arrow_copper_bodkin": 50})
	var slow := U.soldier("copper", "arming_sword", "mail_shirt", "nasal_helm", "kite_shield")
	var sim3 := sim_of([c], [slow], 8, {"w": 40, "h": 9, "cells0": [Vector2i(20, 4)], "cells1": [Vector2i(30, 4)]})
	var x0: int = sim3.fighters[0].cell.x
	var minx := x0
	while not sim3.is_over() and sim3.tick < 1500:
		sim3.step()
		minx = mini(minx, sim3.fighters[0].cell.x)
	print("   kiting in open ground: the archer backed from x=%d to x=%d while shooting %d arrows" % [x0, minx, sim3.fighters[0].shots])
	check(minx < x0, "an archer should back off (kite) as the enemy closes")

# ---------------------------------------------------------------- 9. DF-form log lines
func _test_log_lines() -> void:
	var a := archer("march_longbow", 2, 8, {"arrow_copper_bodkin": 20}, 1600)
	a.name = "Aldric"
	var foes := []
	for i in 3:
		foes.append(U.make("goblin", [["tunic", "linen"], ["short_spear", "tin"]], {"spear": 1}, "Snik %d" % i))
	var sim := sim_of([a], foes, 13, {"w": 30, "h": 9, "cells0": [Vector2i(3, 4)]})
	while not sim.is_over() and sim.tick < 3000:
		sim.step()
	var shown := 0
	var shoot_lines := 0
	for le in sim.fighters[0].log:
		var r := BattleSim.render_entry(le)
		if String(r["text"]).contains("{") or String(r["text"]) == "":
			check(false, "unfilled log line: '%s' (%s)" % [r["text"], str(le["d"].get("key", le["k"]))])
		if le["k"] == "ev" and le["d"].get("key", "") == "shoot":
			shoot_lines += 1
			check(String(r["calc"]).contains("[roll:aim]"), "the shot's calc must show the aim roll")
		if shown < 8 and (le["k"] == "strike" or le["d"].get("key", "") == "shoot"):
			print("   ", r["text"])
			shown += 1
	check(shoot_lines > 0, "the archer should have shot")
