class_name Population
extends RefCounted
## Anonymous residents are slots of native economic rows, never a second economy.
## f.m/f/kids/old INCLUDE promoted resident people; bins contain anonymous slots only.
const TRACKED_HOUSEHOLDS := 15
const POOLS := 8
const INITIAL_SCALE := 5

static func is_cohort(f: Dictionary) -> bool:
	return bool(f.get("cohort", false))

static func households(f: Dictionary) -> int:
	if f.get("gone", false) or f.get("estate", false): return 0
	return maxi(1, int(f.get("households", 1))) if is_cohort(f) else 1

static func household_purse(f: Dictionary) -> float:
	return float(f.get("purse", 0.0)) / maxf(1.0, float(households(f)))

## Read weekly classifications as represented households, not owner rows.
static func household_stats(e: Dictionary) -> Dictionary:
	var out := {"households": 0, "rich": 0, "poor": 0, "poor_hungry": 0}
	var rich_line := float(TownEcon.data()["family"]["rich_purse"])
	for f in e.get("fams", []):
		var n := households(f)
		if n <= 0: continue
		out["households"] = int(out["households"]) + n
		if household_purse(f) > rich_line: out["rich"] = int(out["rich"]) + n
		if int(f.get("cls", 0)) == 0:
			out["poor"] = int(out["poor"]) + n
			if int(f.get("hungry", 0)) > 0: out["poor_hungry"] = int(out["poor_hungry"]) + n
	return out

static func anonymous(f: Dictionary, cat: int) -> int:
	if not is_cohort(f): return 0
	var n := int(f[["m", "f", "old", "kids"][cat]])
	for p in f.get("pp", []) + f.get("kp", []):
		if not Persons.AWAY.has(String(p[4])) and category(p) == cat: n -= 1
	return maxi(0, n)

static func category(p: Array) -> int:
	return 3 if int(p[6]) == 2 else (2 if int(p[6]) == 1 else int(p[2]))

static func available(town: Dictionary) -> int:
	var n := 0
	for f in town.get("econ", {}).get("fams", []): n += spare(f)
	return n

static func spare(f: Dictionary) -> int:
	if f.get("gone", false) or f.get("estate", false): return 0
	return maxi(0, Families.adults(f) - Families.serving(f) - maxi(2, int(f.get("hands", 0)) + f.get("keeps", []).size()))

static func initialize(e: Dictionary, f: Dictionary) -> void:
	f["cohort"] = true
	f["race"] = Persons.race_of(e)
	f["pp"] = []; f["kp"] = []
	f["age_bins"] = {}
	f["population_year"] = 0
	var ages := People.ages(String(f["race"]))
	var lo := [int(ages["adult"]), int(ages["adult"]), int(ages["elder"]), 0]
	var hi := [int(ages["elder"]), int(ages["elder"]), int(ages["lifespan"]), int(ages["adult"])]
	for cat in 4:
		var count := int(f[["m", "f", "old", "kids"][cat]])
		for i in count:
			var age: int = int(lo[cat]) + i % maxi(1, int(hi[cat]) - int(lo[cat]))
			var sex: int = cat if cat < 2 else (i & 1)
			var key := "%d:%d" % [sex, -age]
			f["age_bins"][key] = int(f["age_bins"].get(key, 0)) + 1

static func bin_category(e: Dictionary, f: Dictionary, key: String, day: float) -> int:
	var parts := key.split(":")
	var age := int(floor(day / People.year_days())) - int(parts[1])
	var ab := People.ages(String(f.get("race", Persons.race_of(e))))
	return 3 if age < int(ab["adult"]) else (2 if age >= int(ab["elder"]) else int(parts[0]))

static func eligible_slots(e: Dictionary, f: Dictionary, day: float, draft_only: bool = false) -> int:
	if not is_cohort(f): return 0
	var n := 0
	var ar := People.draft_ages(String(f.get("race", Persons.race_of(e))))
	for key in f.get("age_bins", {}):
		if bin_category(e, f, String(key), day) >= 2: continue
		var age := int(floor(day / People.year_days())) - int(String(key).split(":")[1])
		if not draft_only or (age >= ar.x and age <= ar.y): n += int(f["age_bins"][key])
	return mini(n, spare(f))

static func recruitable(e: Dictionary, f: Dictionary, day: float) -> int:
	if f.get("gone", false) or f.get("estate", false): return 0
	var n := eligible_slots(e, f, day, true)
	var ar := People.draft_ages(String(f.get("race", Persons.race_of(e))))
	var kinds := People._work_kinds(f)
	for p in f.get("pp", []):
		if int(p[6]) != 0 or String(p[4]) != "" or int(p[5]) >= 0: continue
		var age := Persons.age_of(p, day)
		if age >= ar.x and age <= ar.y and People.DRAFT_TIER.has(String(kinds.get(int(p[0]), ""))): n += 1
	return mini(n, spare(f))

static func promote(e: Dictionary, f: Dictionary, day: float, rng: RandomNumberGenerator, draft_only: bool = false) -> Array:
	if eligible_slots(e, f, day, draft_only) <= 0: return []
	var ar := People.draft_ages(String(f.get("race", Persons.race_of(e))))
	var keys: Array = f["age_bins"].keys(); keys.sort()
	var start := rng.randi() % maxi(1, keys.size())
	for i in keys.size():
		var key := String(keys[(start + i) % keys.size()])
		var cat := bin_category(e, f, key, day)
		var parts := key.split(":")
		var age := int(floor(day / People.year_days())) - int(parts[1])
		if cat >= 2 or int(f["age_bins"][key]) <= 0 or (draft_only and (age < ar.x or age > ar.y)): continue
		var p := Persons._new(e, f, String(f["race"]), int(parts[0]), float(parts[1].to_int()) * People.year_days(), 0, rng)
		# Collective workforce labels are economic owners, never a person's
		# surname. Materialize his native cultural surname with his identity.
		var culture: Dictionary = TownEcon.data()["cultures"].get(String(f.get("cul", e.get("culture", "middle"))), TownEcon.culture_of(e))
		var names: Dictionary = DB.names.get(String(culture.get("names", f["race"])), DB.names.get(String(f["race"]), DB.names.get("human", {})))
		var surnames: Array = names.get("last", ["Smith"])
		p[7] = "%s %s" % [Persons.first_of(e, p), surnames[rng.randi() % surnames.size()]]
		f["age_bins"][key] = int(f["age_bins"][key]) - 1
		if int(f["age_bins"][key]) == 0: f["age_bins"].erase(key)
		Persons.pp(f).append(p)
		# Naming a resident never refills the body condition already lost to
		# hunger. This is the existing person-local native condition account.
		var group := "workers" if cat < 2 else ("elders" if cat == 2 else "children")
		var condition := clampf(float(f.get("pool_condition", {}).get(group, 1.0)), 0.0, 1.0)
		if condition < 1.0:
			if not f.has("bc"): f["bc"] = {}
			f["bc"][str(int(p[0]))] = condition
		return p
	return []

static func child_older(f: Dictionary, e: Dictionary, day: float) -> int:
	var n := 0
	var ab := People.ages(String(f.get("race", Persons.race_of(e))))
	var from_age := float(Barge.B()["labour"]["kid_from"]) * float(ab["adult"]) / 16.0
	for key in f.get("age_bins", {}):
		var age := int(floor(day / People.year_days())) - int(String(key).split(":")[1])
		if age >= from_age and age < int(ab["adult"]): n += int(f["age_bins"][key])
	return n

static func summary(e: Dictionary) -> Dictionary:
	var out := {"population": 0, "households": 0, "tracked_families": 0, "cohorts": 0, "anonymous": 0, "detailed": 0, "children": 0, "adults": 0, "elders": 0, "female": 0, "male": 0, "away": 0, "common_wealth": 0.0, "common_jobs": 0, "private_wealth": 0.0, "jobs": 0, "recruitable": 0}
	for f in e.get("fams", []):
		if f.get("gone", false) or f.get("estate", false): continue
		out["population"] += Families.people(f)
		out["private_wealth"] += float(f["purse"])
		out["jobs"] += Families.job_total(f)
		out["recruitable"] += recruitable(e, f, float(e.get("day", 0)))
		out["households"] += int(f.get("households", 1))
		out["cohorts" if is_cohort(f) else "tracked_families"] += 1
		out["children"] += int(f["kids"]); out["elders"] += int(f["old"]); out["adults"] += Families.adults(f)
		out["male"] += int(f["m"]); out["female"] += int(f["f"])
		var kf := 0; var of := 0
		for p in f.get("pp", []) + f.get("kp", []):
			if Persons.AWAY.has(String(p[4])): out["away"] += 1; continue
			out["detailed"] += 1
			if int(p[6]) == 2: kf += int(p[2])
			elif int(p[6]) == 1: of += int(p[2])
		if is_cohort(f):
			out["common_wealth"] += float(f["purse"])
			out["common_jobs"] += Families.job_total(f)
			for cat in 4: out["anonymous"] += anonymous(f, cat)
			for key in f.get("age_bins", {}):
				if int(String(key).split(":")[0]) != 1: continue
				var cat := bin_category(e, f, String(key), float(e.get("day", 0)))
				if cat == 3: kf += int(f["age_bins"][key])
				elif cat == 2: of += int(f["age_bins"][key])
		elif not f.has("pp"):
			kf = int(f["kids"]) / 2; of = int(f["old"]) / 2
		kf = mini(kf, int(f["kids"])); of = mini(of, int(f["old"]))
		out["female"] += kf + of; out["male"] += int(f["kids"]) - kf + int(f["old"]) - of
	return out

static func named_work(e: Dictionary, f: Dictionary, home: Array) -> Dictionary:
	var out := {}
	var offset := anonymous(f, 0) + anonymous(f, 1)
	for i in home.size():
		var place := offset + i
		var job := {"kind": "none", "title": "out of work", "where": "", "wage": 0.0}
		for key in f.get("jobs", {}):
			var n := int(f["jobs"][key])
			if place < n:
				var b: Dictionary = e["biz"][int(key)]
				job = {"kind": "job", "title": Recruits.job_title(e, b), "where": Businesses.title(e, b), "wage": float(b["wage"]), "biz": int(key)}
				break
			place -= n
		if String(job["kind"]) == "none":
			for key in f.get("cj", {}):
				var n := int(f["cj"][key])
				if place < n:
					job = {"kind": "casual", "title": String(TownEcon.data()["casual_jobs"][key]["name"]), "where": "casual work", "wage": Barge.casual_wage(e, String(key)), "cj": key}
					break
				place -= n
		out[int(home[i][0])] = job
	return out

static func race_rows(e: Dictionary) -> Array:
	var by_race := {}
	for f in e.get("fams", []):
		if f.get("gone", false) or f.get("estate", false): continue
		var race := String(f.get("race", Persons.race_of(e)))
		if not by_race.has(race): by_race[race] = []
		by_race[race].append(f)
	var out := []
	for race in by_race:
		var row := summary({"fams": by_race[race], "culture": e.get("culture", "middle"), "day": e.get("day", 0)})
		row["race"] = race; out.append(row)
	return out

static func generated_business_owners(e: Dictionary) -> void:
	var tracked: Array = e["fams"].filter(func(f): return not is_cohort(f) and not f.get("estate", false) and not f.get("gone", false))
	if tracked.is_empty(): return
	for b in e.get("biz", []):
		if b.get("closed", false) or b.get("for_sale", false): continue
		var old := int(b["owner"])
		if old >= 0 and not is_cohort(e["fams"][old]) and not e["fams"][old].get("estate", false): continue
		tracked.sort_custom(func(a, c): return a["owns"].size() < c["owns"].size())
		var owner: Dictionary = tracked[0]
		if old >= 0: e["fams"][old]["owns"].erase(int(b["id"]))
		b["owner"] = int(owner["id"]); owner["owns"].append(int(b["id"]))
		if String(b["type"]) == "farm": owner["farm"] = int(b["id"])

## An exceptional office holder becomes a real one-person household; his pool
## never becomes a dynasty. The registered person and battle Unit remain the same.
static func promote_ruler(game, u: Unit) -> Dictionary:
	if u == null or u.dead: return {}
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	var e: Dictionary = town.get("econ", {})
	if e.is_empty() or u.family < 0 or u.family >= e["fams"].size(): return {}
	var source: Dictionary = e["fams"][u.family]
	var p := Persons.by_uid(source, u.uid)
	if p.is_empty() or source.get("gone", false): return {}
	if not is_cohort(source): return source
	var state := String(p[4])
	var cat := category(p)
	var field: String = ["m", "f", "old", "kids"][cat]
	if not Persons.AWAY.has(state) and int(source[field]) <= 0: return {}
	Persons.identity(e, source, p)
	var household := Families._blank(e["fams"].size())
	household["name"] = u.name.split(" ")[-1]
	household["cul"] = source.get("cul", e.get("culture", "middle"))
	household["race"] = source.get("race", Persons.race_of(e))
	household["named"] = true
	household["seed"] = absi(hash([str(Persons.g(p, Persons.PERSON_UID, "")), "office-household"]))
	household["last"] = float(game.day)
	household["tax_season"] = source.get("tax_season", -1)
	household["cond"] = float(source["cond"])
	household["store"] = source["store"].duplicate(true)
	# Days of food are shares of the same native household goods pool. Moving
	# one mouth with the same days conserves its physical food/drink/fuel claim.
	var members := maxi(1, Families.people(source))
	var purse_share := maxf(0, float(source["purse"])) / float(members)
	source["purse"] = float(source["purse"]) - purse_share
	household["purse"] = purse_share
	if int(source["homes"]) > 0:
		source["homes"] = int(source["homes"]) - 1
		household["homes"] = 1
		if source.has("landlord"):
			household["landlord"] = source["landlord"]
	source["households"] = maxi(0, int(source.get("households", 1)) - 1)
	if not Persons.AWAY.has(state):
		source[field] = int(source[field]) - 1
		household[field] = 1
	if int(source["serve"].get(state, 0)) > 0:
		source["serve"][state] = int(source["serve"][state]) - 1
		if int(source["serve"][state]) == 0: source["serve"].erase(state)
		household["serve"][state] = 1
	# Person-local body condition, infection/immunity, wage and lifetime fields
	# move with the exact registered person, with no fresh body or age roll.
	var pid_key := str(int(p[0]))
	for map_key in ["bc", "sk", "im", "child_cj"]:
		if source.get(map_key, {}).has(pid_key):
			household[map_key] = {pid_key: source[map_key][pid_key]}
			source[map_key].erase(pid_key)
			if source[map_key].is_empty(): source.erase(map_key)
	Persons.pp(source).erase(p)
	Persons.pp(household).append(p)
	p[7] = u.name   # changing economic household must never change his personal name
	e["fams"].append(household)
	Families.identity(e, household)
	p[Persons.HOUSE_UID] = household["founding_house_uid"]
	u.family = int(household["id"])
	var roll: Dictionary = game.world.get("army", {}).get("roll", {})
	if roll.has(str(u.uid)): roll[str(u.uid)][1] = u.family
	Families.reassign(e, source)
	Families.reassign(e, household)
	Families.add_hist(household, "%s founded this household on taking office." % u.name, float(game.day))
	return household

static func turn(e: Dictionary, f: Dictionary, day: float, days: float) -> void:
	if not is_cohort(f): return
	var population_before := Families.people(f)
	var adults_before := Families.adults(f)
	var year := int(floor(day / People.year_days()))
	var prior := int(f.get("population_year", year))
	if year > prior:
		var ab := People.ages(String(f["race"]))
		for key in f["age_bins"].keys():
			var parts := String(key).split(":")
			var before := bin_category(e, f, String(key), float(prior) * People.year_days())
			var after := bin_category(e, f, String(key), day)
			var n := int(f["age_bins"][key])
			if before != after:
				f[["m", "f", "old", "kids"][before]] -= n
				f[["m", "f", "old", "kids"][after]] += n
				e["adults"] += n if before == 3 else -n
			if year - int(parts[1]) >= int(ab["lifespan"]): kill_slots(e, f, String(key), n, day, "old age")
		f["population_year"] = year
	var room := float(f["homes"]) * float(TownEcon.culture_of(e)["home"]["room"]) * (0.6 + 0.4 * float(f["cond"]))
	if int(f["hungry"]) == 0 and Families.people(f) < room:
		var due := float(f.get("birth_carry", 0)) + float(TownEcon.culture_of(e)["growth"]) * float(f.get("households", 1)) * days / 7.0
		var births := mini(int(floor(due)), maxi(0, int(room) - Families.people(f)))
		f["birth_carry"] = due - floor(due)
		for i in births:
			var key := "%d:%d" % [(int(f.get("birth_sequence", 0)) + i) & 1, year]
			f["age_bins"][key] = int(f["age_bins"].get(key, 0)) + 1
			Families.born(e, f, [], day)
		f["birth_sequence"] = int(f.get("birth_sequence", 0)) + births
	# Aggregate body-condition bands use the same native famine rates and actual unmet food days.
	var short := Sickness.food_short_days(e, f, day, days)
	var body: Dictionary = Sickness.data()["body"]
	var bc: Dictionary = f.get("pool_condition", {})
	var counts := {"workers": anonymous(f, 0) + anonymous(f, 1), "children": anonymous(f, 3), "elders": anonymous(f, 2)}
	var food := float(counts["workers"] + counts["children"] + counts["elders"]) * (1.0 - short / maxf(1, days))
	var order: Array = Sickness.data()["eat_order"].get(String(e.get("culture", "")), Sickness.data()["eat_order"]["_default"])
	for group in order:
		var count := int(counts[group])
		if count <= 0:
			bc[group] = 1.0
			continue
		var fed := minf(food, count) / maxf(1, count); food = maxf(0, food - count)
		# Match Sickness._body: a fully fed group recovers even when another
		# group in the row went short. Otherwise intermittent hunger ratchets
		# condition down forever, then kill_slots removes the whole age band.
		var value: float = float(bc.get(group, 1.0))
		if fed >= 0.999:
			value += float(body["refill"]) * days
		else:
			value -= float(body["fall"]) * (1.0 if group == "workers" else float(body["weak"])) * (1.0 - fed) * days
		bc[group] = clampf(value, 0, 1)
		if value <= 0:
			for key in f["age_bins"].keys():
				var cat := bin_category(e, f, String(key), day)
				if (group == "workers" and cat < 2) or (group == "children" and cat == 3) or (group == "elders" and cat == 2): kill_slots(e, f, String(key), int(f["age_bins"][key]), day, "starved")
	f["pool_condition"] = bc
	if Families.people(f) <= 0: Families.extinct(e, f, day)
	elif Families.people(f) != population_before or Families.adults(f) != adults_before: Families.reassign(e, f)

static func kill_slots(e: Dictionary, f: Dictionary, key: String, n: int, day: float, cause: String, detail: String = "anonymous residents") -> void:
	var cat := bin_category(e, f, key, day)
	n = mini(n, int(f["age_bins"].get(key, 0)))
	if n <= 0: return
	f["age_bins"][key] = int(f["age_bins"][key]) - n
	if int(f["age_bins"][key]) == 0: f["age_bins"].erase(key)
	f[["m", "f", "old", "kids"][cat]] = maxi(0, int(f[["m", "f", "old", "kids"][cat]]) - n)
	e["pop"] -= n
	if cat < 2: e["adults"] -= n
	e["stats"]["deaths"] = int(e["stats"].get("deaths", 0)) + n
	Census.record_population_deaths(e, int(f["id"]), n, day, cause, detail)
