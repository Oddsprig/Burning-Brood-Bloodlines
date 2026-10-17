extends RefCounted
## 1v1 log sanity: a copper duel produces lazily rendered entries (story line + per-layer detail + calc) for
## both fighters, with named rolls, swing physics and layer tests; strike entries are shared; the duel ends.

const U = preload("res://tests/sim_util.gd")

func run(_tree: SceneTree) -> int:
	var fails := 0
	var a := U.soldier("copper")
	var b := U.soldier("copper", "bearded_axe")
	a.name = "Bram Kettle"
	b.name = "Osric Vane"
	var sim: BattleSim = U.run([a], [b], 12345, {"log_moves": true})
	var fa: Fighter = sim.fighters[0]
	var fb: Fighter = sim.fighters[1]
	print("duel over at tick %d (%.1f s), winner %d, exchanges %d" % [sim.tick, sim.tick * Formulas.TICK_SECONDS, sim.winner, U.exchanges(sim)])
	print("--- %s log (%d entries) ---" % [a.name, fa.log.size()])
	var shown := 0
	for e in fa.log:
		var r := BattleSim.render_entry(e)
		if e["k"] == "strike" and not r["detail"].is_empty() and shown < 2:
			print("[t%d] %s\n    %s\n%s\n" % [e["tick"], r["text"], "\n    ".join(r["detail"]), r["calc"]])
			shown += 1
	print("--- story view ---")
	for e in fa.log:
		if e["k"] != "move":
			print("[t%d] %s" % [e["tick"], BattleSim.render_entry(e)["text"]])
	print("states: %s blood %.0f / %s blood %.0f" % [fa.state, a.body.blood, fb.state, b.body.blood])
	if fa.log.is_empty() or fb.log.is_empty():
		print("FAIL: empty logs"); fails += 1
	var has := {"roll": false, "swing": false, "layer": false, "speed": false, "detail": false}
	for e in fa.log + fb.log:
		var r := BattleSim.render_entry(e)
		var calc: String = r["calc"]
		has["roll"] = has["roll"] or calc.contains("[roll:")
		has["swing"] = has["swing"] or calc.contains("SWING") or calc.contains("THRUST")
		has["layer"] = has["layer"] or calc.contains("EDGE") or calc.contains("BLUNT")
		has["speed"] = has["speed"] or calc.contains("speed ")
		has["detail"] = has["detail"] or not r["detail"].is_empty()
		if String(r["text"]).contains("{"):
			print("FAIL: unfilled template: ", r["text"]); fails += 1
	for k in has:
		if not has[k]:
			print("FAIL: logs never show ", k); fails += 1
	# Shared entries: every strike in the attacker's log also appears in the defender's.
	for e in fa.log:
		if e["k"] == "strike" and int(e["d"]["a"]) == 0 and not fb.log.has(e):
			print("FAIL: strike entry missing from defender log"); fails += 1
			break
	# Event text accessor works for strike events.
	for ev in sim.events:
		if ev["type"] == "hit" and BattleSim.event_text(ev) == "":
			print("FAIL: event_text empty for a hit"); fails += 1
			break
	if not sim.is_over():
		fails += 1
	return fails
