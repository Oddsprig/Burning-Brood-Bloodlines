extends RefCounted
## Bounded keeper fixtures; no world generation, presim or battle.
const EconomyFixture = preload("res://tests/test_population_economy_controls.gd")
var fails: int = 0

func check(ok: bool, message: String) -> void:
	if not ok: fails += 1; printerr("FAIL: ", message)

func snapshot(e: Dictionary, f: Dictionary) -> Array:
	return [e["pop"], e["adults"], f["m"], f["f"], f["kids"], f["old"], f["hands"], f["idle"],
		f["serve"].duplicate(true), f["jobs"].duplicate(true), f.get("keeps", []).duplicate(),
		f["purse"], e["treasury"], e["biz"].map(func(b): return [b["workers"], b["wage"], b["till"], b.get("owed", 0.0)])]

func pool_fixture(adults: int) -> Dictionary:
	var helper: Variant = EconomyFixture.new()
	var e: Dictionary = helper.fixture([1])
	var f: Dictionary = e["fams"][3]
	f["m"] = adults; f["f"] = 0; f["kids"] = 0; f["old"] = 0
	f["age_bins"] = {"0:-20": adults}; f["population_year"] = 0
	e["pop"] = adults + 4; e["adults"] = adults + 4
	return e

func zero_spare() -> void:
	var e: Dictionary = pool_fixture(1)
	var f: Dictionary = e["fams"][3]
	var b: Dictionary = Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	b["wage"] = 7.25; b["workers"] = 1; f["jobs"][str(int(b["id"]))] = 1
	f["idle"] = 0; f["pool_condition"] = {"workers": 0.4}
	var before: Array = snapshot(e, f)
	check(Population.spare(f) == 0, "fixture has no recruitment spare")
	check(RecData.keeper(e, b).is_empty(), "anonymous-only input reproduces the missing keeper")
	Population.staff(e, f)
	check(snapshot(e, f) == before, "naming preserves population, workforce, service, jobs, coins and exact pay")
	check(f["age_bins"].is_empty() and Persons.pp_read(f).size() == 1, "one bin debit becomes one real register person")
	var keeper: Dictionary = RecData.keeper(e, b)
	check(not keeper.is_empty(), "zero-spare staffed business names a keeper")
	if keeper.is_empty(): return
	var p: Array = Persons.by_pid(f, int(keeper["pid"]))
	check(int(p[2]) == 0 and float(p[3]) == -20.0 * People.year_days() and Persons.family_race(e, f) == "human",
		"resident retains the exact sex, birth bin and race")
	check(absf(float(f["bc"][str(int(p[0]))]) - 0.4) < 0.00001, "naming cannot heal body condition")
	var job: Dictionary = Persons.work(e, f)[int(p[0])]
	check(int(job["biz"]) == int(b["id"]) and float(job["wage"]) == 7.25 and not bool(job.get("keeper", false)),
		"staff representative retains the paid place and exact wage")
	check(People._work_kinds(e, f)[int(p[0])] == "job", "recruitment and Records use one assignment")
	var saved: String = JSON.stringify(e)
	RecData.keeper(e, b); RecData.staff(e, int(b["id"])); People._work_kinds(e, f)
	check(JSON.stringify(e) == saved, "Records and recruitment reads are mutation-free")
	var loaded: Dictionary = JSON.parse_string(saved)
	var loaded_f: Dictionary = loaded["fams"][3]
	var loaded_b: Dictionary = loaded["biz"][int(b["id"])]
	var resumed: String = JSON.stringify(loaded)
	Population.staff(loaded, loaded_f)
	check(JSON.stringify(loaded) == resumed and int(RecData.keeper(loaded, loaded_b)["pid"]) == int(p[0]),
		"existing-field JSON round trip preserves identity and staffing is idempotent")

func distinct_places() -> void:
	var e: Dictionary = pool_fixture(4)
	var f: Dictionary = e["fams"][3]
	var shop: Dictionary = Businesses._row(e, "carpenter", 3, 0, TownEcon.data())
	var a: Dictionary = Businesses._row(e, "bowyer", -1, 1, TownEcon.data())
	var b: Dictionary = Businesses._row(e, "fletcher", -1, 1, TownEcon.data())
	f["keeps"] = [int(shop["id"])]; shop["kw"] = 1
	f["hands"] = 1; f["idle"] = 0
	f["jobs"] = {str(int(a["id"])): 1, str(int(b["id"])): 1}
	a["workers"] = 1; b["workers"] = 1
	var before: Array = snapshot(e, f)
	Population.staff(e, f)
	var seen: Dictionary = {}
	for business: Dictionary in [shop, a, b]:
		var keeper: Dictionary = RecData.keeper(e, business)
		check(not keeper.is_empty(), "every staffed business names a responsible resident")
		if keeper.is_empty(): continue
		check(not seen.has(int(keeper["pid"])), "one person cannot keep two businesses")
		seen[int(keeper["pid"])] = true
	var rng: RandomNumberGenerator = RandomNumberGenerator.new(); rng.seed = 88441
	Population._from_bins(e, f, 0.0, rng, false, true)
	var work: Dictionary = Persons.work(e, f)
	var land: int = 0
	for job: Dictionary in work.values():
		if String(job["kind"]) == "land": land += 1
	check(land == 1 and work.size() == 4 and f["age_bins"].is_empty(), "keeper, land and hired slots cover distinct residents")
	check(snapshot(e, f) == before, "several named responsibilities preserve aggregate accounts")
	var saved: String = JSON.stringify(e)
	Population.staff(e, f)
	check(JSON.stringify(e) == saved, "completed staffing creates no repeated identities")

func service_and_sale() -> void:
	var e: Dictionary = pool_fixture(1)
	var owner: Dictionary = e["fams"][1]
	var buyer: Dictionary = e["fams"][2]
	Persons.generate(e, owner, 0.0); Persons.generate(e, buyer, 0.0)
	var a: Dictionary = Businesses._row(e, "carpenter", 1, 0, TownEcon.data())
	var b: Dictionary = Businesses._row(e, "bowyer", 1, 0, TownEcon.data())
	owner["owns"] = [int(a["id"]), int(b["id"])]
	check(Families._keep(e, owner, 2) == 2, "two registered adults can keep two shops")
	var home: Array = Population.home_workers(owner)
	var departed: Array = home[0]
	departed[4] = "army"; owner["serve"] = {"army": 1}
	check(Families._keep(e, owner, 1) == 1 and int(b["kw"]) == 0, "service departure removes the absent keeper")
	var remaining: Array = Population.home_workers(owner)
	remaining[0][4] = "reserve"; remaining[0][5] = 77
	check(Families._keep(e, owner, 1) == 1 and not RecData.keeper(e, a).is_empty(), "home reserve remains a real civilian keeper")
	People.release({"econ": e}, 1, "army")
	check(String(departed[4]) == "" and int(a["kw"]) == 1 and int(b["kw"]) == 1, "return marks the person home before reassignment")
	a["owner"] = 2; owner["owns"].erase(int(a["id"])); buyer["owns"] = [int(a["id"])]
	Families._keep(e, buyer, 2)
	Families._keep(e, owner, 2)
	check(int(a["kw"]) == 1 and int(RecData.keeper(e, a).get("fid", -1)) == 2, "old-owner cleanup preserves the new keeper")

func academy_guard() -> void:
	var e: Dictionary = pool_fixture(2)
	var f: Dictionary = e["fams"][3]
	var shop: Dictionary = Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	var academy: Dictionary = Businesses._row(e, "academy", -1, 1, TownEcon.data())
	e["academy"] = int(academy["id"])
	f["jobs"] = {str(int(shop["id"])): 1}; shop["workers"] = 1; f["idle"] = 1
	Population.staff(e, f)
	check(Persons.pp_read(f).size() == 1 and Academy.hiring_places(e, f, academy) == 0,
		"naming a responsible worker cannot offer the same person as a scientist")
	f["jobs"] = {str(int(academy["id"])): 1}; academy["workers"] = 1
	var saved: String = JSON.stringify(e)
	Population.staff(e, f)
	check(JSON.stringify(e) == saved, "staffing never materializes anonymous Academy places")

func academy_reserve_swap() -> void:
	var e: Dictionary = pool_fixture(2)
	var f: Dictionary = e["fams"][3]
	var academy: Dictionary = Businesses._row(e, "academy", -1, 1, TownEcon.data())
	e["academy"] = int(academy["id"])
	f["hands"] = 0; f["keeps"] = []; f["jobs"] = {}
	var reserve: Array = [901, 0, 0, -8000, "reserve", 77, 0]
	var hire: Array = [902, 0, 0, -7000, "hire", -1, 0]
	f["pp"] = [reserve, hire]
	var places: Array = [{"kind": "job", "biz": int(academy["id"]), "keeper": false, "title": "apprentice", "where": "", "wage": 1.0}]
	var counts: Array[int] = [1]
	var work: Dictionary = Population.named_work(e, f, [reserve, hire], places, counts)
	var hire_job: Dictionary = work[902]
	var reserve_job: Dictionary = work[901]
	check(int(hire_job.get("biz", -1)) == int(academy["id"]), "cohort Academy place swaps to a lead-eligible home adult")
	check(String(reserve_job.get("kind", "")) == "none", "reserve keeps no second Academy place after the swap")
	check(String(reserve[4]) == "reserve" and String(hire[4]) == "hire", "the swap changes assignments, not service states")

func academy_reserved_swap() -> void:
	var e: Dictionary = pool_fixture(2)
	var f: Dictionary = e["fams"][3]
	var rng: RandomNumberGenerator = RandomNumberGenerator.new(); rng.seed = 100903
	var reserve: Array = Persons._new(e, f, "human", 0, -30.0 * People.year_days(), 0, rng)
	var hire: Array = Persons._new(e, f, "human", 0, -25.0 * People.year_days(), 0, rng)
	reserve[4] = "reserve"; reserve[5] = 77; hire[4] = "hire"
	f["pp"] = [reserve, hire]; f["age_bins"] = {}
	f["hands"] = 0; f["keeps"] = []; f["jobs"] = {}; f["idle"] = 0
	var academy: Dictionary = Businesses._row(e, "academy", -1, 1, TownEcon.data())
	var shop: Dictionary = Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	e["academy"] = int(academy["id"])
	academy["lead"] = []; academy["lead_uid"] = ""
	# Both adults are reserved: the first Academy place and one shop representative.
	Families.set_job(e, f, int(academy["id"]), 1)
	Families.set_job(e, f, int(shop["id"]), 1)
	var saved: String = JSON.stringify(e)
	var work: Dictionary = Persons.work(e, f)
	var research: Dictionary = Academy._research_work(e, f)
	var reserve_pid: int = int(reserve[0]); var hire_pid: int = int(hire[0])
	check(int(work[hire_pid].get("biz", -1)) == int(academy["id"]), "a reserved shop representative can exchange places with a reserve researcher")
	check(int(work[reserve_pid].get("biz", -1)) == int(shop["id"]), "the reserve takes the shop place so its named responsibility remains covered")
	check(int(research[hire_pid].get("biz", -1)) == int(academy["id"]) and int(research[reserve_pid].get("biz", -1)) == int(shop["id"]), "Academy eligibility and Records use the same exchanged places")
	check(Persons.work(e, f) == work and JSON.stringify(e) == saved, "repeated mapping preserves the register, service counts, jobs, wages and save fields")
	var world: Dictionary = {}
	check(Academy.appoint(world, "keeper_fixture", e, academy, 0.0, rng), "a full one-place Academy appoints its real eligible staff member")
	check(Academy.lead_gone(e, academy) == "" and not RecData.keeper(e, academy).is_empty(), "the appointed Academy lead is present and nameable in Records")
	check(int(academy["workers"]) == 1 and int(shop["workers"]) == 1 and String(reserve[4]) == "reserve" and String(hire[4]) == "hire", "appointment retains counted places and civilian service states")
	# No lead-eligible adult: preserve honest reserve staff and the empty post.
	hire[4] = "reserve"; academy["lead"] = []; academy["lead_uid"] = ""
	work = Persons.work(e, f)
	check(int(work[reserve_pid].get("biz", -1)) == int(academy["id"]) and int(work[hire_pid].get("biz", -1)) == int(shop["id"]), "an all-reserve household keeps its original two places")
	check(not Academy.appoint(world, "keeper_fixture", e, academy, 0.0, rng) and RecData.keeper(e, academy).is_empty(), "reserve staff cannot impersonate an eligible Academy lead")
	# The positional Academy holder is already eligible: leave the mapping alone.
	reserve[4] = ""
	work = Persons.work(e, f)
	check(int(work[reserve_pid].get("biz", -1)) == int(academy["id"]) and int(work[hire_pid].get("biz", -1)) == int(shop["id"]), "an already eligible Academy holder is not displaced")

func academy_retained_lead() -> void:
	var e: Dictionary = pool_fixture(3)
	var f: Dictionary = e["fams"][3]
	var rng := RandomNumberGenerator.new(); rng.seed = 100904
	var elder: Array = Persons._new(e, f, "human", 0, -30.0 * People.year_days(), 0, rng)
	var head: Array = Persons._new(e, f, "human", 0, -25.0 * People.year_days(), 0, rng)
	var younger: Array = Persons._new(e, f, "human", 0, -20.0 * People.year_days(), 0, rng)
	f["pp"] = [elder, head, younger]; f["age_bins"] = {}
	f["hands"] = 0; f["keeps"] = []; f["jobs"] = {}; f["idle"] = 1
	var shop: Dictionary = Businesses._row(e, "carpenter", -1, 2, TownEcon.data())
	var academy: Dictionary = Businesses._row(e, "academy", -1, 1, TownEcon.data())
	e["academy"] = int(academy["id"])
	Families.set_job(e, f, int(shop["id"]), 1)
	Families.set_job(e, f, int(academy["id"]), 1)
	check(Academy.appoint({}, "keeper_fixture", e, academy, 0.0, rng), "the original paid Academy place appoints its real holder")
	check(int(academy.get("lead", [-1, -1])[1]) == int(head[0]), "the middle adult holds the original Academy place")
	# A growing preceding job block moves the positional place to the youngest.
	# The household still holds exactly one paid Academy place for its head.
	Families.set_job(e, f, int(shop["id"]), 2); f["idle"] = 0
	var before: Array = snapshot(e, f)
	var saved: String = JSON.stringify(e)
	var rng_state: int = rng.state
	var work: Dictionary = Persons.work(e, f)
	var research: Dictionary = Academy._research_work(e, f)
	check(int(work[int(head[0])].get("biz", -1)) == int(academy["id"]) and int(research[int(head[0])].get("biz", -1)) == int(academy["id"]), "Records and research retain the same paid head after a prefix job grows")
	check(int(work[int(younger[0])].get("biz", -1)) == int(shop["id"]) and String(work[int(head[0])].get("title", "")) == Academy.lead_title(e), "the exchanged shop place and the head's actual title are retained")
	check(Academy.lead_gone(e, academy) == "" and int(RecData.keeper(e, academy).get("pid", -1)) == int(head[0]), "a retained paid head remains present and nameable")
	check(snapshot(e, f) == before and JSON.stringify(e) == saved and rng.state == rng_state, "lead mapping changes no register, counts, service, wages, cash, save fields or RNG")
	var head_uid: String = String(academy["lead_uid"])
	academy["lead_uid"] = "different-person"
	check(not Academy.lead_gone(e, academy).is_empty() and RecData.keeper(e, academy).is_empty(), "a mismatched identity cannot reclaim the paid head")
	academy["lead_uid"] = head_uid
	head[4] = "reserve"
	check(not Academy.lead_gone(e, academy).is_empty() and RecData.keeper(e, academy).is_empty(), "a reserve cannot retain the designated head")
	head[4] = ""
	Families.set_job(e, f, int(academy["id"]), 0)
	check(not Academy.lead_gone(e, academy).is_empty() and RecData.keeper(e, academy).is_empty(), "losing the counted Academy place still vacates its head")

func academy_final_jobs() -> void:
	var e: Dictionary = pool_fixture(2)
	var f: Dictionary = e["fams"][3]
	var rng := RandomNumberGenerator.new(); rng.seed = 100905
	f["pp"] = [Persons._new(e, f, "human", 0, -30.0 * People.year_days(), 0, rng), Persons._new(e, f, "human", 0, -25.0 * People.year_days(), 0, rng)]
	f["age_bins"] = {}; f["hands"] = 0; f["keeps"] = []; f["jobs"] = {}; f["idle"] = 0
	var shop: Dictionary = Businesses._row(e, "carpenter", -1, 2, TownEcon.data())
	var academy: Dictionary = Businesses._row(e, "academy", -1, 1, TownEcon.data())
	e["academy"] = int(academy["id"])
	Families.set_job(e, f, int(shop["id"]), 2)
	var game: Variant = EconomyFixture.FixtureGame.new()
	game.world = {"seed": 100905, "factions": {"middle_kingdom": {"capital": "keeper_fixture", "towns": ["keeper_fixture"]}},
		"towns": {"keeper_fixture": {"id": "keeper_fixture", "faction": "middle_kingdom", "econ": e}}}
	Academy.init_world(game)
	check((academy.get("lead", []) as Array).is_empty() and int(academy["workers"]) == 0, "early initialization cannot invent an idle or paid candidate")
	var empty_saved: String = JSON.stringify(game.world)
	Academy.finish_world(game)
	check(JSON.stringify(game.world) == empty_saved, "final generation without eligible paid staff keeps an honest vacancy")
	# Model final initial-job reconciliation supplying a real Academy employee.
	Families.set_job(e, f, int(shop["id"]), 1)
	Families.set_job(e, f, int(academy["id"]), 1)
	check(RecData.keeper(e, academy).is_empty(), "a newly staffed Academy reproduces the missed initial appointment")
	var before: Array = snapshot(e, f)
	Academy.finish_world(game)
	check(Academy.lead_gone(e, academy) == "" and not RecData.keeper(e, academy).is_empty(), "final generation appoints the actual paid staff member")
	check(snapshot(e, f) == before, "final appointment preserves all counted work, service and money")
	var saved: String = JSON.stringify(game.world)
	Academy.finish_world(game)
	check(JSON.stringify(game.world) == saved, "valid initial heads are not reappointed or logged twice")

func run(_tree: SceneTree) -> int:
	zero_spare()
	distinct_places()
	service_and_sale()
	academy_guard()
	academy_reserve_swap()
	academy_reserved_swap()
	academy_retained_lead()
	academy_final_jobs()
	return fails
