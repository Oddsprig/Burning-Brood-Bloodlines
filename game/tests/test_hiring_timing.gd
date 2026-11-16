extends RefCounted

var fails := 0
var checks := 0
func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", msg)

# Real generated households; IDs/names are never selection conditions.
func fixture() -> Array:
	for t in Game.world["towns"].values():
		if not TownEcon.has_econ(t): continue
		var e: Dictionary = t["econ"]
		for f in e["fams"]:
			# v0.100: v0.034 (TRACKED_HOUSEHOLDS = 15) rarely generates a 1-adult, 0-kid household;
			# pick a real non-cohort household with a civilian adult and trim it to 1 adult at home.
			if f.get("gone", false) or f.get("estate", false) or Population.is_cohort(f) or Families.serving(f) != 0: continue
			var elder_age := int(People.ages(Persons.family_race(e, f))["elder"])
			var adult: Array = []
			for p: Array in f.get("pp", []):
				if int(p[6]) == 0 and String(p[4]) == "" and int(p[5]) < 0 and Persons.age_of(p, float(e.get("day", 0)) + 30.0) < elder_age:
					adult = p; break
			if adult.is_empty(): continue
			for family in e["fams"]:
				for k in family["jobs"].keys(): Families.set_job(e, family, int(k), 0)
				Shelter.release_casual(e, family)
			for b in e["biz"]: b["closed"] = true
			f["pp"] = [adult]; f["kp"] = []
			f["m"] = 1 if int(adult[2]) == 0 else 0; f["f"] = 1 if int(adult[2]) == 1 else 0
			f["kids"] = 0; f["old"] = 0; f["serve"] = {}
			f["owns"] = []; f["keeps"] = []; f["land"] = {}; f["herd"] = {}; f["farm"] = -1
			f["hands"] = 0; f["idle"] = 1; f["unpaid"] = 0; f["hungry"] = 0; f["debt"] = 0.0
			f["purse"] = 100000.0; f["homes"] = 1; f["cond"] = 1.0
			f["store"] = {"food": 100.0, "drink": 100.0, "wood": 100.0}
			# v0.100: clear plot/herd records in e["plots"] and e["hd"] plus leftover household/person work state.
			if e.has("plots"):
				# v0.100: e["plots"]["own"] is a PackedInt32Array; mutate in place via P["own"][pi].
				var P: Dictionary = e["plots"]
				for pi in Plots.count(P):
					if int(P["own"][pi]) == int(f["id"]): P["own"][pi] = 0
				P.get("crop_work_acres", {}).erase(str(int(f["id"])))
			if e.has("hd"):
				for h in Herds.herds(e).values():
					if String(h.get("ow", "")) == "f" and int(h.get("oi", -1)) == int(f["id"]):
						h["ow"] = "s"; h["oi"] = 0
				e["hd"]["ver"] = int(e["hd"].get("ver", 0)) + 1
			for key in ["hl", "rent", "landlord", "cjearned", "preg", "sk", "nxa", "wsig", "ox", "assigned_need", "work_need"]: f.erase(key)
			if adult.size() > Persons.JOB: adult[Persons.JOB] = ""
			if adult.size() > Persons.HIST: adult[Persons.HIST] = []
			Persons.sync(e, f, float(e.get("day", 0)))
			Persons.track_jobs(e, f, float(e.get("day", 0)))
			e["cjcap"] = {}; e["cjused"] = {}; e["treasury"] = 1000000.0
			var b := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
			b["wage"] = 100.0; b["till"] = 100000.0
			return [t, e, f, b]
	return []

func ordinary_turn(t: Dictionary, e: Dictionary, f: Dictionary) -> void:
	var day := float(f["last"]) + 7.0
	# Advance the actual employer days rather than asking a payday to invent
	# a preceding week at today's advertised wage. Expected pay stays 700.
	for d in range(int(e["day"]) + 1, int(day) + 1):
		e["day"] = d
		WageClaims.accrue_day(e, d)
	e["day"] = int(day); Game.day = day
	var rng := RandomNumberGenerator.new(); rng.seed = 9981
	Families.turn(Game, t, e, f, day, rng)

func reopened_place(rows: Array) -> void:
	var t: Dictionary = rows[0]; var e: Dictionary = rows[1]; var f: Dictionary = rows[2]; var b: Dictionary = rows[3]
	var other: Dictionary = {}
	for family in e["fams"]:
		# v0.100: skip anonymous cohort rows when choosing a second household.
		if family != f and not Population.is_cohort(family) and not family.get("estate", false) and not family.get("gone", false) and Families.adults(family) > 0:
			other = family; break
	check(not other.is_empty(), "a second real household can vacate the funded job")
	if other.is_empty(): return
	Families.set_job(e, other, int(b["id"]), 1)
	Businesses.rebuild_open(e)
	check(not e["open"].has(int(b["id"])), "full employer is absent from the old hiring list")
	Families.set_job(e, other, int(b["id"]), 0)
	check(Businesses.takeable(b) == 1, "released job is actually funded")
	var till := float(b["till"])
	ordinary_turn(t, e, f)
	check(int(f["jobs"].get(str(int(b["id"])), 0)) == 1, "ordinary family turn sees a job reopened after the hiring list")
	check(float(f["income_parts"]["staff wages"]) == 0.0 and float(b["till"]) == till, "joining does not pay wages for the preceding unemployed week")
	ordinary_turn(t, e, f)
	check(absf(float(f["income_parts"]["staff wages"]) - 700.0) < 0.001, "the following ordinary turn pays the actual worked week")
	check(absf(till - float(b["till"]) - 700.0) < 0.001, "wages come from the employer's existing till")

func better_current_offer(rows: Array) -> void:
	var e: Dictionary = rows[1]; var f: Dictionary = rows[2]; var held: Dictionary = rows[3]
	var better := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	better["wage"] = 1000.0; better["till"] = 0.0
	Businesses.rebuild_open(e)
	check(not Families._paid_worse(e, f, e["biz"]), "unfunded higher advertised wage is not an available offer")
	better["till"] = 2000.0
	check(Families._paid_worse(e, f, e["biz"]), "new funding is visible without waiting for the weekly highest-offer cache")
	# An additional paid relative is a wage earner, separately from the keeper.
	held["owner"] = int(f["id"])
	check(Families._paid_worse(e, f, e["biz"]), "paid relatives see better external offers too")
	held["owner"] = -1
	Families.reassign(e, f)
	check(int(f["jobs"].get(str(int(better["id"])), 0)) == 1, "matching chooses the actually funded higher offer")
	check(int(held["workers"]) == 0 and int(better["workers"]) == 1, "the move releases the old place without duplicating its worker")
	better["closed"] = true
	Families.set_job(e, f, int(better["id"]), 0)

func casual_only(rows: Array) -> void:
	var t: Dictionary = rows[0]; var e: Dictionary = rows[1]; var f: Dictionary = rows[2]
	for b in e["biz"]: b["closed"] = true
	f["idle"] = 1
	e["cjcap"] = {"street_sweeper": 1}; e["cjused"] = {}
	Businesses.rebuild_open(e)
	check(int(e["open_n"]) == 0 and Shelter.available_casual(e, "street_sweeper") == 1, "only a funded cleanup vacancy exists")
	ordinary_turn(t, e, f)
	check(int(f.get("cj", {}).get("street_sweeper", 0)) == 1 and int(f["idle"]) == 0, "housed idle adult finds cleanup work through the ordinary family turn")
	var offer := Businesses._row(e, "carpenter", -1, 1, TownEcon.data())
	offer["wage"] = 1000.0; offer["till"] = 2000.0
	check(Families._paid_worse(e, f, e["biz"]), "casual worker sees a better funded ordinary job")
	Families.reassign(e, f)
	check(not f.has("cj") and int(f["jobs"].get(str(int(offer["id"])), 0)) == 1, "casual worker can change job and releases the old cleanup place")
	check(float(e["cjused"].get("street_sweeper", 0)) == 0.0, "casual occupancy releases exactly once")

func run(_tree: SceneTree) -> int:
	# v0.100: require all three seeds in separate invocations, with one generation per test.
	var selected: String = OS.get_environment("HIRING_SEED")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="): selected = arg.trim_prefix("--seed=")
	check(selected in ["713", "2026", "8801"], "v0.100: run hiring --seed=713, --seed=2026 and --seed=8801 separately")
	if fails > 0: return fails
	var previous_size: String = WorldGen.gen_size
	var previous_span: int = CampaignWorld.presim_span_days
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Game.new_game(int(selected))
	var rows: Array = fixture()
	check(rows.size() == 4, "generated labour fixture exists")
	if rows.size() == 4:
		reopened_place(rows)
		better_current_offer(rows)
		casual_only(rows)
	WorldGen.gen_size = previous_size
	CampaignWorld.presim_span_days = previous_span
	print("HIRING TIMING seed=", selected, " checks=", checks, " failures=", fails)
	return fails
