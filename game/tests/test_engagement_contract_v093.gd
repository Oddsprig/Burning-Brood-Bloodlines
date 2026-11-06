extends RefCounted
## Native runtime UNRUN by author. Controller executes this test separately from the 108 measured trials.
const S = preload("res://tests/balance_engagements_v093.gd")
var checks := 0
var fails := 0
var failures: Array = []

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1; failures.append(why); printerr("FAIL engagement093: ", why)

func manifest_contract() -> void:
	var all := S.manifest()
	check(all.size() == 108, "84 race + 24 dragon physical-side trials")
	var ids: Dictionary = {}; var pairs: Dictionary = {}; var race_roles: Dictionary = {}
	var races := 0; var dragons := 0; var mirrors := 0
	for i in all.size():
		var trial: Dictionary = all[i]
		check(int(trial["index"]) == i and not ids.has(trial["id"]), "stable unique physical trial index/id")
		ids[trial["id"]] = true
		check(int(trial["seed"]) in S.SEEDS and int(trial["subject_side"]) in [0, 1], "fixed seed and deployment side")
		var key := str(trial["id"]).left(str(trial["id"]).length() - 3)
		if not pairs.has(key): pairs[key] = []
		pairs[key].append(int(trial["subject_side"]))
		if trial["kind"] == "race":
			races += 1
			if trial["mirror"]: mirrors += 1
			var rr := "%s/%s" % [trial["race"], trial["role"]]
			race_roles[rr] = int(race_roles.get(rr, 0)) + 1
		else:
			dragons += 1
			check(trial["size"] in ["small", "large"] and int(trial["opponents"]) in [8, 16, 32], "declared native size/opponent prefixes")
	check(races == 84 and dragons == 24 and mirrors == 12 and race_roles.size() == 21, "all seven races/three roles, human mirrors separate")
	for race in S.B.RACES:
		for role in S.B.ROLES: check(int(race_roles.get("%s/%s" % [race, role], 0)) == 4, "two seeds x both sides per race/role")
	for sides: Array in pairs.values(): check(sides == [0, 1], "fresh side swaps are distinct manifest trials")
	for count in [1, 7, 108]:
		var seen: Dictionary = {}
		for shard in count:
			for trial: Dictionary in S.partition(all, shard, count):
				check(not seen.has(trial["id"]), "partition cannot duplicate a physical side")
				seen[trial["id"]] = true
		check(seen.size() == 108, "partition union covers exactly the manifest")
	check(S.partition(all, 0, 1, all[0]["id"]) == [all[0]], "single-trial pilot is explicitly filtered coverage")

func costs_contract() -> void:
	var fixture := S.NativeFixture.new(); fixture.fixture(S.SEEDS[0])
	var a := S.B.candidates(S.B.spec("orc", "spear"), S.SEEDS[0] * 3 + 1, S.LIMIT)
	var b := S.B.candidates(S.B.spec("human", "spear"), S.SEEDS[0] * 3 + 2, S.LIMIT)
	var before := S.digest({"a": a["units"], "b": b["units"], "gold": Game.gold, "rng": str(Game.rng.state), "unit": Unit._next_uid, "item": Item._next_uid})
	var matched := S.match_prefixes(a, b)
	for pool: Dictionary in [a, b]:
		var total := 0.0
		for i in pool["units"].size():
			total += S.B.body_cost(pool["units"][i])
			check(is_equal_approx(total, float(pool["costs"][i + 1])), "actual gear/quiver/seven-day wages are cumulative")
	check(before == S.digest({"a": a["units"], "b": b["units"], "gold": Game.gold, "rng": str(Game.rng.state), "unit": Unit._next_uid, "item": Item._next_uid}), "cost reads and prefix matching are pure")
	check(not matched.is_empty(), "native same-role seed has a bounded match")
	if not matched.is_empty():
		check(float(matched["gap"]) <= S.B.MAX_GAP, "actual <=5% spend gap")
		for count: int in matched["counts"]: check(count > S.ROUND_SIZE and count <= S.LIMIT, "both ordinary pools exceed the round size, within 32")
	var low := {"costs": [0.0, 1.0, 2.0, 3.0, 4.0, 5.0]}
	var high := {"costs": [0.0, 1000.0, 2000.0, 3000.0, 4000.0, 5000.0]}
	check(S.match_prefixes(low, high).is_empty(), "unmatched prefixes stay explicit; no invented equal cost")
	var equal := {"costs": [0.0]}
	for i in 32: equal["costs"].append(float(i + 1) * 100.0)
	var preferred := S.match_prefixes(equal, equal)
	check(preferred["search"] == [9, 16] and preferred["counts"] == [12, 12], "prefer reproducible modest prefixes before fallback")

func native_contract(tree: SceneTree, deadline: int) -> Dictionary:
	var row: Dictionary = await S.control(tree, deadline)
	check(row.get("status", "") == "complete_censored", "real native hold/two-tick control finishes honestly censored")
	var rounds: Array = row.get("engagements", [])
	check(rounds.size() >= 2 and int(row.get("total_rounds", 0)) == rounds.size(), "genuine native >=2 engagement series, no fabricated result rows")
	if rounds.size() < 2: return row
	check(row.get("any_tick_cap", false) and row.get("any_draw", false) and row.get("censored", false), "actual capped draws never become an uncensored valuation")
	check(row["final_result"]["winner"] == row["native_winner"] and row["battle_summary"]["rounds"] == rounds.size(), "exact final_result/summary preserve native decision and count")
	var prior: Dictionary = row["initial"]
	var original_riders: Dictionary = row["initial"]["rider_bodies"]
	check(not original_riders.is_empty(), "original adult Ruby civilian rider has a native battle body")
	var corpse_ids: Array = []
	for side: Array in row["initial"]["roster"]:
		for actor: Dictionary in side:
			if bool(actor["dead"]): corpse_ids.append(actor["uid"])
	check(corpse_ids.size() == 1, "explicit pre-battle corpse fixture present")
	for engagement: Dictionary in rounds:
		check(engagement["status"] == "complete" and engagement["aftermath_applied"] and engagement["round_applied"], "native simulation, inherited aftermath, native after_round all executed")
		check(engagement["tick_capped"] and engagement["draw"] and int(engagement["native_winner"]) == -1, "actual two-tick native draw evidence")
		check(S.all_checks(engagement["checks"]), "all native body/pool/custody/rider/seat/down transition assertions")
		check(prior["continuity_sha256"] == engagement["before"]["continuity_sha256"], "no reconstruction/healing/reset between engagements")
		for id: String in corpse_ids:
			check(not engagement["selected_uids"][0].has(id) and not engagement["selected_uids"][1].has(id), "actual native round selector excludes corpse")
		for person: String in original_riders:
			var before: Dictionary = engagement["before"]["rider_bodies"][person]
			var after: Dictionary = engagement["after"]["rider_bodies"][person]
			check(before["unit_instance"] == original_riders[person]["unit_instance"] and before["body_instance"] == original_riders[person]["body_instance"] and after["body_instance"] == before["body_instance"], "original rider Unit/BodyState identity across actual rounds")
		prior = engagement["after"]
	var st: Dictionary = Game.pending_battle["rounds"]
	var live: Array = (st["pool"][0] as Array).filter(func(u): return not u.dead and not DragonCombat.is_dragon_unit(Game, u))
	check(not live.is_empty(), "native control has a real ordinary survivor for captive exclusion")
	if not live.is_empty():
		var captive: Unit = live[0]
		check(not S.R.fit(Game, st["pool"][0], [captive]).has(captive), "native fit excludes an actual original Unit held in custody")
	check(S.json_value_equal(JSON.parse_string(JSON.stringify(row, "", true, true)), row), "JSON-safe structure and exact numeric values survive int/float normalization")
	return row

func run(tree: SceneTree) -> int:
	var old := S.save_globals(); S.R.round_size = S.ROUND_SIZE
	var started := Time.get_ticks_msec()
	manifest_contract(); costs_contract()
	var control: Dictionary = await native_contract(tree, started + S.WALL_MS)
	var report := {"schema": "engagement_contract_v093/1", "status": "complete" if fails == 0 else "failed",
		"checks": checks, "failures": failures, "fails": fails, "control": control,
		"run_id": "contract_%d_%d_%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()],
		"elapsed_ms": Time.get_ticks_msec() - started, "complete": fails == 0}
	report.merge(S.fingerprints())
	var saved := S.checkpoint(report)
	S.restore_globals(old)
	print("engagement093 contract: %d checks, %d failures; native runtime executed only by controller" % [checks, fails])
	return fails + (0 if saved else 1)
