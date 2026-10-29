extends RefCounted
## Fast deterministic screening bands, separate from the multi-shard tuning survey.
const B = preload("res://tests/balance_v070.gd")
const SCORE_LOW := 0.10
const SCORE_HIGH := 0.90
const NATIVE_LOW := 0.05
const NATIVE_HIGH := 0.95

func cross_cases(suite: String) -> Array:
	var selected: Array = []
	for case: Dictionary in B.cases_for(suite, 1):
		if case["a"]["id"] != case["b"]["id"]: selected.append(case)
	return selected

func native_cases() -> Array:
	var all_cases: Array = B.cases_for("roster_matrix", 1)
	var ids: Array = []
	for case: Dictionary in all_cases:
		if not ids.has(case["a"]["id"]): ids.append(case["a"]["id"])
	ids.sort()
	var selected: Array = []
	for case: Dictionary in all_cases:
		var distance := absi(ids.find(case["a"]["id"]) - ids.find(case["b"]["id"]))
		if distance in [1, 3, 7, 9] or ids.size() - distance in [1, 3, 7, 9]: selected.append(case)
	return selected

func run(tree: SceneTree) -> int:
	var started := Time.get_ticks_msec()
	var fails := 0
	var reports: Dictionary = {}
	for suite in ["race", "unit"]:
		var report: Dictionary = await B.survey(tree, cross_cases(suite), started + B.WALL_MS)
		reports[suite] = report
		if not bool(report["complete"]):
			printerr("FAIL balance070: incomplete %s survey: %s" % [suite, report["errors"]])
			fails += 1
			break
		var category: Dictionary = report["summary"][suite]
		var expected: Array = B.RACES if suite == "race" else B.ROLES
		for id in expected:
			if not category.has(id):
				printerr("FAIL balance070: missing %s %s" % [suite, id]); fails += 1
				continue
			var st: Dictionary = category[id]
			var rate := float(st["score_rate"])
			print("balance070 %s %s: n=%d score=%.3f kills=%d efficiency=%.3f" % [suite, id, st["n"], rate, st["kills"], st["cost_efficiency"]])
			# All opponents and both deployment sides are represented. Draws count half.
			if st["n"] < (24 if suite == "race" else 20) or not is_finite(rate) or rate < SCORE_LOW or rate > SCORE_HIGH:
				printerr("FAIL balance070: %s %s outside [%.2f, %.2f] or undersampled" % [suite, id, SCORE_LOW, SCORE_HIGH]); fails += 1
			if float(st["draw"]) / st["n"] > 0.25:
				printerr("FAIL balance070: too many unresolved %s %s trials" % [suite, id]); fails += 1
		for row: Dictionary in report["rows"]:
			if float(row["cost_match"]["gap"]) > B.MAX_GAP:
				printerr("FAIL balance070: unequal replacement spend"); fails += 1
	if Time.get_ticks_msec() < started + B.WALL_MS:
		var native: Dictionary = await B.survey(tree, native_cases(), started + B.WALL_MS)
		reports["roster_matrix"] = native
		if not bool(native["complete"]):
			printerr("FAIL balance070: incomplete native roster screen"); fails += 1
		else:
			var units: Dictionary = native["summary"]["unit"]
			if units.size() != 20:
				printerr("FAIL balance070: expected all 20 native troop templates"); fails += 1
			for id in units:
				var st: Dictionary = units[id]
				var rate := float(st["score_rate"])
				print("balance070 native %s: n=%d score=%.3f efficiency=%.3f" % [id, st["n"], rate, st["cost_efficiency"]])
				if st["n"] < 16 or not is_finite(rate) or rate < NATIVE_LOW or rate > NATIVE_HIGH or float(st["draw"]) / st["n"] > 0.25:
					printerr("FAIL balance070: native %s outside screen bands or undersampled" % id); fails += 1
	else:
		printerr("FAIL balance070: no wall budget left for native roster"); fails += 1
	if Time.get_ticks_msec() < started + B.WALL_MS:
		var mounted: Dictionary = await B.survey(tree, cross_cases("mount"), started + B.WALL_MS)
		reports["mount"] = mounted
		if not bool(mounted["complete"]):
			printerr("FAIL balance070: incomplete mount screen"); fails += 1
		else:
			for id in ["foot", "horse"]:
				var st: Dictionary = mounted["summary"]["mount"].get(id, {})
				var rate := float(st.get("score_rate", -1.0))
				print("balance070 mount %s: n=%d score=%.3f" % [id, st.get("n", 0), rate])
				if int(st.get("n", 0)) < 30 or not is_finite(rate) or rate < SCORE_LOW or rate > SCORE_HIGH or float(st["draw"]) / st["n"] > 0.25:
					printerr("FAIL balance070: mount %s outside screen bands or undersampled" % id); fails += 1
	else:
		printerr("FAIL balance070: no wall budget left for mounts"); fails += 1
	var evidence := {"schema": "balance_v070/1", "phase": "regression", "complete": fails == 0, "reports": reports, "score_band": [SCORE_LOW, SCORE_HIGH], "native_score_band": [NATIVE_LOW, NATIVE_HIGH], "data_sha256": B.fingerprint(), "elapsed_ms": Time.get_ticks_msec() - started, "failures": fails}
	if B.write_result(evidence, "regression") == "": fails += 1
	if Time.get_ticks_msec() - started >= 55000:
		printerr("FAIL balance070: exceeded 55-second regression budget"); fails += 1
	return fails
