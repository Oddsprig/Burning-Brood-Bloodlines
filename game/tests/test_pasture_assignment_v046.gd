extends RefCounted
## Focused native event regression. Integrate only after the root's serial queue.
## Generated cultures, households, labour, businesses and herds are untouched.
## The fixture stages a wolf raid's route and native supporting forces' positions,
## as test_pasture_raids does; real HerdRaids.step must muster and settle it.
## No call to Families.reassign or replacement of household/business counters.
## Defaults: Normal, seeds 713 and 2026, prefer a mixed farm/employer household.
## Optional PASTURE_TEST_SIZE, PASTURE_TEST_SEEDS (comma-separated integers),
## PASTURE_TEST_WORKLOAD=any|mixed|land, PASTURE_TEST_MIN_HERDERS=1..4.

const CIVILIAN_STATES := ["", "hire", "reserve"]
const MAX_BATTLE_CALLS := 1000
var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String, detail: Dictionary = {}) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label, " ", JSON.stringify(detail))

func run(_tree: SceneTree) -> int:
	var size: String = OS.get_environment("PASTURE_TEST_SIZE")
	if size.is_empty():
		size = "normal"
	check(WorldGen.SIZES.has(size), "valid native world size", {"size": size})
	if not WorldGen.SIZES.has(size):
		return failures
	var workload: String = OS.get_environment("PASTURE_TEST_WORKLOAD")
	if workload.is_empty():
		workload = "any"
	check(workload in ["any", "mixed", "land"], "valid workload selector", {"workload": workload})
	if not workload in ["any", "mixed", "land"]:
		return failures
	var minimum: int = 1
	var minimum_text: String = OS.get_environment("PASTURE_TEST_MIN_HERDERS")
	if not minimum_text.is_empty():
		minimum = minimum_text.to_int()
	check(minimum >= 1 and minimum <= 4, "bounded herder count", {"minimum": minimum})
	if minimum < 1 or minimum > 4:
		return failures
	var seeds: Array = [713, 2026]
	var seed_text: String = OS.get_environment("PASTURE_TEST_SEEDS")
	if not seed_text.is_empty():
		seeds = []
		for part: String in seed_text.split(",", false):
			check(part.strip_edges().is_valid_int(), "integer scenario seed", {"seed": part})
			if part.strip_edges().is_valid_int():
				seeds.append(part.strip_edges().to_int())
	check(not seeds.is_empty() and seeds.size() <= 4, "one to four bounded generated worlds")
	if seeds.is_empty() or seeds.size() > 4:
		return failures
	var keep_size: String = WorldGen.gen_size
	WorldGen.gen_size = size
	for seed_value: int in seeds:
		_scenario(seed_value, workload, minimum)
	WorldGen.gen_size = keep_size
	print("PASTURE_ASSIGNMENT_AGGREGATE ", JSON.stringify({"checks": checks, "failures": failures,
		"seeds": seeds, "size": size, "workload": workload, "minimum_herders": minimum,
		"native_arrival_and_return": true, "synthetic_economy": false}))
	return failures

func _herder_pids(e: Dictionary, f: Dictionary) -> Array:
	var jobs: Dictionary = Persons.work(e, f)
	var out: Array = []
	for p: Array in f.get("pp", []):
		var place: Dictionary = jobs.get(int(p[0]), {})
		if int(p[5]) < 0 and String(p[4]) == "" and String(place.get("kind", "")) == "herd":
			out.append(int(p[0]))
	out.sort()
	return out

func _select(workload: String, minimum: int) -> Dictionary:
	var selected: Dictionary = {}
	var best_score: int = -1
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	for tid: String in ids:
		var town: Dictionary = Game.world["towns"][tid]
		if not TownEcon.has_econ(town):
			continue
		var e: Dictionary = town["econ"]
		var plots: Dictionary = e.get("plots", {})
		var herds: Dictionary = Herds.herds(e)
		for h: Dictionary in herds.values():
			if not Herds.GRAZE.has(String(h["k"])) or Herds.head(h) <= 0:
				continue
			var fid: int = Herds.grazer(e, h)
			if fid <= 0 or fid >= (e["fams"] as Array).size():
				continue
			var f: Dictionary = e["fams"][fid]
			if bool(f.get("gone", false)) or bool(f.get("estate", false)):
				continue
			var expected: Array = _herder_pids(e, f)
			if expected.size() < minimum or int(f.get("serve", {}).get("pasture", 0)) != 0:
				continue
			var jobs_n: int = Families.job_total(f)
			if workload == "mixed" and jobs_n <= 0:
				continue
			if workload == "land" and Families.acres(f) <= 0:
				continue
			# Prefer existing employer obligations without inventing extra workers.
			var score: int = 100 * mini(1, jobs_n) + 10 * mini(1, Families.acres(f)) + expected.size()
			if score <= best_score:
				continue
			for pi: int in h.get("pl", []):
				if pi >= 0 and pi < Plots.count(plots) and int(plots["use"][pi]) == Plots.PASTURE:
					selected = {"town": town, "herd": h, "family": f, "pids": expected,
						"goal": HerdRaids.plot_pos(town, plots, pi), "plot": pi}
					best_score = score
					break
	return selected

func _labour(e: Dictionary, f: Dictionary, label: String) -> void:
	if bool(f.get("gone", false)) or bool(f.get("estate", false)):
		return
	var actual: Dictionary = {"own": 0, "keepers": 0, "idle": 0, "jobs": {}, "casual": {}}
	var services: Dictionary = {}
	var civil: int = 0
	var registered: int = (f.get("kp", []) as Array).size()
	var places: Dictionary = Persons.work(e, f)
	for p: Array in f.get("pp", []):
		var state: String = String(p[4])
		if not Persons.AWAY.has(state):
			registered += 1
		if int(p[6]) != 0:
			continue
		if not state in CIVILIAN_STATES and not Persons.AWAY.has(state):
			services[state] = int(services.get(state, 0)) + 1
		if not state in CIVILIAN_STATES:
			continue
		civil += 1
		var pid: int = int(p[0])
		check(places.has(pid), label + ": every civilian has its actual work place", {"family": f["id"], "pid": pid})
		var place: Dictionary = places.get(pid, {})
		var kind: String = String(place.get("kind", "none"))
		if kind in ["land", "herd"]:
			actual["own"] = int(actual["own"]) + 1
		elif kind == "job" and bool(place.get("keeper", false)):
			actual["keepers"] = int(actual["keepers"]) + 1
		elif kind == "job":
			var bid: String = str(int(place.get("biz", -1)))
			actual["jobs"][bid] = int(actual["jobs"].get(bid, 0)) + 1
		elif kind == "casual":
			var job: String = String(place.get("cj", ""))
			actual["casual"][job] = int(actual["casual"].get(job, 0)) + 1
		else:
			actual["idle"] = int(actual["idle"]) + 1
	var available: int = maxi(0, Families.adults(f) - Families.serving(f))
	var assigned: int = int(f.get("hands", 0)) + (f.get("keeps", []) as Array).size() + Families.job_total(f) + int(f.get("idle", 0))
	for n: Variant in f.get("cj", {}).values():
		assigned += int(n)
	check(civil == available and assigned == civil, label + ": civilian assignments equal actual available adults",
		{"family": f["id"], "assigned": assigned, "civilian_register": civil, "available": available, "serve": f.get("serve", {})})
	check(registered == Families.people(f), label + ": population retains real person records", {"family": f["id"]})
	check(int(actual["own"]) == int(f.get("hands", 0)) and int(actual["keepers"]) == (f.get("keeps", []) as Array).size()
		and int(actual["idle"]) == int(f.get("idle", 0)), label + ": own work, keepers and idle each belong to real civilians",
		{"family": f["id"], "actual": actual, "hands": f.get("hands", 0), "keeps": f.get("keeps", []), "idle": f.get("idle", 0)})
	check(actual["jobs"] == f.get("jobs", {}) and actual["casual"] == f.get("cj", {}), label + ": every paid adult place belongs to a real civilian",
		{"family": f["id"], "actual_jobs": actual["jobs"], "recorded_jobs": f.get("jobs", {})})
	var recorded_services: Dictionary = {}
	for role: String in f.get("serve", {}):
		var count: int = int(f["serve"][role])
		check(count >= 0, label + ": every service count remains nonnegative", {"family": f["id"], "role": role, "count": count})
		if count > 0:
			recorded_services[role] = count
	check(services == recorded_services, label + ": service counts equal exactly the actual serving people (zero entries allowed)",
		{"family": f["id"], "actual_services": services, "recorded_services": recorded_services})

func _town_accounts(town: Dictionary, label: String) -> void:
	var e: Dictionary = town["econ"]
	var worker_counts: Dictionary = {}
	var own: int = 0
	var idle: int = 0
	for f: Dictionary in e["fams"]:
		if bool(f.get("gone", false)):
			continue
		own += int(f.get("hands", 0))
		if bool(f.get("estate", false)):
			continue
		_labour(e, f, label)
		idle += int(f.get("idle", 0))
		for bid: String in f.get("jobs", {}):
			worker_counts[bid] = int(worker_counts.get(bid, 0)) + int(f["jobs"][bid])
	for b: Dictionary in e["biz"]:
		var bid: String = str(int(b["id"]))
		check(int(b["workers"]) == int(worker_counts.get(bid, 0)), label + ": employer workers equal real household jobs",
			{"business": b["id"], "workers": b["workers"], "actual_jobs": worker_counts.get(bid, 0)})
		check(int(b["workers"]) >= 0 and float(b.get("till", 0)) >= -0.000001, label + ": employer workers and funds remain nonnegative", {"business": b["id"]})
	check(own == int(e.get("hands", 0)), label + ": town own-hands total equals real household assignments")
	check(idle == int(e.get("idle_n", 0)), label + ": town idle total equals actual idle households")
	check(Census.people(e) == int(e["pop"]) and Census.adds_up(Census.balance(e)), label + ": population and actual Census events balance")
	for h: Dictionary in Herds.herds(e).values():
		check(Herds.head(h) >= 0 and Herds.head(h) == Herds.ledger_head(h), label + ": real livestock and event ledger balance", {"herd": h["id"]})
	var coins: Dictionary = Game.world.get("coin", {})
	var expected_coins: float = float(coins.get("cast", 0)) - float(coins.get("melted", 0)) - float(coins.get("drained", 0))
	check(not coins.is_empty() and absf(Barge.holdings(Game) - expected_coins) < 1.0, label + ": funding and employer settlement conserve global currency")

func _scenario(seed_value: int, workload: String, minimum: int) -> void:
	Game.new_game(seed_value)
	var picked: Dictionary = _select(workload, minimum)
	check(not picked.is_empty(), "generated world has the requested real herd-worker household", {"seed": seed_value, "workload": workload, "minimum": minimum})
	if picked.is_empty():
		return
	var town: Dictionary = picked["town"]
	var e: Dictionary = town["econ"]
	var family: Dictionary = picked["family"]
	var herd: Dictionary = picked["herd"]
	var expected_pids: Array = picked["pids"]
	var goal: Vector2 = picked["goal"]
	var initial_pop: int = int(e["pop"])
	var initial_deaths: int = int(Census._book(e).get("dt", 0))
	var initial_heads: int = Herds.head(herd)
	var family_payday: float = float(family["last"])
	print("PASTURE_FIXTURE ", JSON.stringify({"seed": seed_value, "town": town["id"], "family": family["id"], "culture": e["culture"],
		"herd": herd["id"], "kind": herd["k"], "plot": picked["plot"], "expected_defender_pids": expected_pids,
		"adults": Families.adults(family), "hands": family["hands"], "jobs": family["jobs"], "keepers": family.get("keeps", [])}))
	_town_accounts(town, "before pasture muster")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value + 88046
	var wolves: Array = []
	for i: int in 8:
		wolves.append(Unit.create("wolf", "beasts"))
	var wid: String = CampaignWorld.spawn_warband(Game, "beasts", goal + Vector2(40, 0), wolves.size(), "beasts", rng, {"units": wolves})
	check(not wid.is_empty(), "native creature force is on the map")
	if wid.is_empty():
		return
	var wb: Dictionary = Game.world["warbands"][wid]
	# spawn_warband snaps to the terrain. Stage an unambiguous travel distance;
	# native _step_along still performs the arrival, without touching resources.
	wb["pos"] = goal + Vector2(40, 0)
	wb["raid"] = {"town": town["id"], "herd": herd["id"], "goal": goal, "wolves": true, "phase": "travelling", "day": Game.day}
	wb["path"] = [goal]
	# Real registered town defenders support return coverage; only position changes.
	for force: Dictionary in [Militia.band_of(Game, String(town["id"])), TownDefence.guard_band(Game, String(town["id"]))]:
		if not force.is_empty():
			force["pos"] = goal
	HerdRaids.step(Game, wb, 0.001, Game.day, rng)
	check(wb.has("raid") and String(wb.get("raid", {}).get("phase", "")) == "travelling", "distant native step cannot muster prematurely")
	check(_herder_pids(e, family) == expected_pids and Herds.head(herd) == initial_heads, "travel retains original civilian workers and livestock")
	var arrival_dt: float = (wb["pos"] as Vector2).distance_to(goal) / CampaignWorld.WARBAND_SPEED + 0.001
	HerdRaids.step(Game, wb, arrival_dt, Game.day, rng)
	var asynchronous: bool = wb.has("raid") and HerdRaids.fights.has(wid)
	check(asynchronous, "native arrival leaves an observable asynchronous battle; coverage must not be skipped", {"seed": seed_value})
	if not asynchronous:
		_town_accounts(town, "immediate completed raid")
		return
	var actual_pids: Array = []
	for p: Array in family.get("pp", []):
		if String(p[4]) == "pasture":
			actual_pids.append(int(p[0]))
			check(int(p[5]) >= 0, "mustered pasture person has an actual unit", {"pid": p[0]})
	actual_pids.sort()
	check(actual_pids == expected_pids, "every pre-muster actual herder remains selected despite workload changes", {"expected": expected_pids, "actual": actual_pids})
	var hid: String = String(wb["raid"].get("herders", ""))
	var temporary: Dictionary = Game.world["warbands"].get(hid, {})
	check(not temporary.is_empty() and bool(temporary.get("pasture_defence", false)), "native temporary force holds the registered herders")
	for u: Unit in temporary.get("units", []):
		var p: Array = Persons.by_uid(family, u.uid)
		check(not p.is_empty() and expected_pids.has(int(p[0])) and String(p[4]) == "pasture", "temporary defender is the selected real person", {"uid": u.uid})
	check(int(e["pop"]) == initial_pop and Herds.head(herd) == initial_heads, "pending battle cannot remove town people or livestock before settlement")
	check(float(family["last"]) == family_payday, "event reassignment does not advance household wages or payday")
	_town_accounts(town, "immediately after native pasture arrival")
	var calls: int = 0
	var observed_pending: bool = false
	while wb.has("raid") and calls < MAX_BATTLE_CALLS:
		HerdRaids.step(Game, wb, 0.01, Game.day, rng)
		calls += 1
		if wb.has("raid") and not observed_pending:
			observed_pending = true
			_town_accounts(town, "subsequent asynchronous battle step")
	check(observed_pending, "another native call exposes the live asynchronous service interval")
	check(not wb.has("raid"), "bounded native pasture battle completes", {"calls": calls})
	if wb.has("raid"):
		return
	check(not HerdRaids.fights.has(wid) and not Game.world["warbands"].has(hid), "combat releases its simulation and temporary herd force")
	var returned: int = 0
	var died: int = 0
	for pid: int in expected_pids:
		var p: Array = Persons.by_pid(family, pid)
		if not p.is_empty():
			returned += 1
			check(String(p[4]) == "" and int(p[5]) == -1 and Persons.work(e, family).has(pid), "surviving defender returns to a real civilian place", {"pid": pid})
		else:
			died += 1
			var recorded: int = 0
			for row: Array in Census._book(e)["deaths"]:
				if int(row[1]) == pid:
					recorded += 1
			check(recorded == 1, "fallen defender leaves exactly one actual Census death", {"pid": pid, "rows": recorded})
	check(returned > 0, "fixture covers at least one actual surviving herder's return", {"returned": returned, "died": died})
	check(int(family.get("serve", {}).get("pasture", 0)) == 0, "all pasture service slots leave through real return or casualty")
	check(initial_pop - int(e["pop"]) == int(Census._book(e).get("dt", 0)) - initial_deaths, "all real defender casualties reconcile town population")
	_town_accounts(town, "after native pasture settlement and return")
	print("PASTURE_SCENARIO ", JSON.stringify({"seed": seed_value, "town": town["id"], "family": family["id"],
		"arrival_pids": actual_pids, "expected_pids": expected_pids, "returned": returned, "died": died,
		"battle_calls": calls, "asynchronous": asynchronous, "second_pending_step": observed_pending}))
