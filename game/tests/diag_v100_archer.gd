extends RefCounted
## v0.100 triage for test_bows_sim: why a lone archer shoots twice and then neither kites nor draws his sidearm.
## Read-only; prints the archer's state through the two scenarios that fail.
const B = preload("res://tests/test_bows_sim.gd")
const U = preload("res://tests/sim_util.gd")

func _line(sim: BattleSim, tag: String) -> String:
	var f = sim.fighters[0]
	var e = sim.fighters[1]
	return "%s t=%d act=%d a: cell=%s state=%s bow=%s hand=%s hold=%s routed=%s morale=%.0f arrows=%d shots=%d pending=%s | foe cell=%s state=%s routed=%s" % [
		tag, sim.tick, f.action_ticks, f.cell, f.state, f.bow_state, f.bow_hand, f.hold, f.routed, float(f.morale), f.unit.arrows(), f.shots,
		str(f.pending_action.get("kind", "")) if f.pending_action is Dictionary else "-", e.cell, e.state, e.routed]

func run(_tree: SceneTree) -> int:
	var c := B.archer("self_bow", 0, 6, {"arrow_copper_bodkin": 50})
	var slow := U.soldier("copper", "arming_sword", "mail_shirt", "nasal_helm", "kite_shield")
	var sim := B.sim_of([c], [slow], 8, {"w": 40, "h": 9, "cells0": [Vector2i(20, 4)], "cells1": [Vector2i(30, 4)]})
	var last := ""
	var printed := 0
	while not sim.is_over() and sim.tick < 1500:
		sim.step()
		var l := _line(sim, "KITE")
		var key := l.substr(l.find(" a:"))
		if (key != last or sim.tick % 200 == 0) and printed < 20:
			printed += 1
			print("DIAG_ARCHER ", l)
			last = key
		for ev in sim.new_events:
			var en: Dictionary = ev.get("entry", {})
			if not en.is_empty() and printed < 20:
				print("DIAG_ARCHER   event %s %s" % [en.get("k", ""), str(en.get("d", {}).get("key", ""))])
	print("DIAG_ARCHER end tick %d winner %d" % [sim.tick, sim.winner])
	# the cornered case: archer at the map edge, a swordsman coming
	var a := B.archer("self_bow", 0, 4, {"arrow_copper_bodkin": 50})
	var foe := U.soldier("copper", "arming_sword", "", "", "")
	var sim2 := B.sim_of([a], [foe], 5, {"w": 16, "h": 5, "cells0": [Vector2i(0, 2)], "cells1": [Vector2i(9, 2)]})
	last = ""
	printed = 0
	while not sim2.is_over() and sim2.tick < 3000:
		sim2.step()
		var l2 := _line(sim2, "CORNER")
		var key2 := l2.substr(l2.find(" a:"))
		if (key2 != last or sim2.tick % 200 == 0) and printed < 120:
			printed += 1
			print("DIAG_ARCHER ", l2)
			last = key2
		for ev in sim2.new_events:
			var en: Dictionary = ev.get("entry", {})
			if not en.is_empty() and printed < 120:
				print("DIAG_ARCHER   event k=%s key=%s a=%s al=%s" % [en.get("k", ""), str(en.get("d", {}).get("key", "")), str(en.get("d", {}).get("a", "")), str(en.get("d", {}).get("al", ""))])
	print("DIAG_ARCHER corner end tick %d winner %d; archer alive %s state %s" % [sim2.tick, sim2.winner, sim2.fighters[0].alive(), sim2.fighters[0].state])
	return 0
