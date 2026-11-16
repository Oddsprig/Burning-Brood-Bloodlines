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
	var sweep_row: Dictionary = TownSweep.row(f)
	if not sweep_row.is_empty(): return maxi(0, int(f[["m", "f", "old", "kids"][cat]]) - int(sweep_row["resident"][cat]))
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
	var n: int = 0
	var race: String = String(f.get("race", Persons.race_of(e)))
	var ar: Vector2i = People.draft_ages(race)
	# Every bin in this read uses the same day and racial age limits. Keep the
	# native bin order and arithmetic; only the repeated lookup/split is gone.
	var ab: Dictionary = People.ages(race)
	var adult: int = int(ab["adult"])
	var elder: int = int(ab["elder"])
	var year: int = int(floor(day / People.year_days()))
	for key: Variant in f.get("age_bins", {}):
		var parts: PackedStringArray = String(key).split(":")
		var age: int = year - int(parts[1])
		var cat: int = 3 if age < adult else (2 if age >= elder else int(parts[0]))
		if cat >= 2: continue
		if not draft_only or (age >= ar.x and age <= ar.y): n += int(f["age_bins"][key])
	return mini(n, spare(f))

static func recruitable(e: Dictionary, f: Dictionary, day: float) -> int:
	if f.get("gone", false) or f.get("estate", false): return 0
	# The result is capped by spare: a full or empty cap needs no named job records.
	var cap: int = spare(f)
	if cap <= 0: return 0
	var n := eligible_slots(e, f, day, true)
	var ar := People.draft_ages(String(f.get("race", Persons.race_of(e))))
	if n >= cap: return cap
	var kinds: Dictionary = {}
	var kinds_ready: bool = false
	for p in f.get("pp", []):
		if int(p[6]) != 0 or String(p[4]) != "" or int(p[5]) >= 0: continue
		var age := Persons.age_of(p, day)
		if age < ar.x or age > ar.y: continue
		if not kinds_ready:
			kinds = People._work_kinds(e, f)
			kinds_ready = true
		if People.DRAFT_TIER.has(String(kinds.get(int(p[0]), ""))): n += 1
	return mini(n, spare(f))

static func promote(e: Dictionary, f: Dictionary, day: float, rng: RandomNumberGenerator, draft_only: bool = false) -> Array:
	if eligible_slots(e, f, day, draft_only) <= 0: return []
	return _from_bins(e, f, day, rng, draft_only)

## Staffing names an adult already occupying a place; it never uses recruitment spare.
static func _from_bins(e: Dictionary, f: Dictionary, day: float, rng: RandomNumberGenerator, draft_only: bool = false, assigned: bool = false) -> Array:
	var race: String = Persons.family_race(e, f)
	var ar: Vector2i = People.draft_ages(race)
	var keys: Array = f["age_bins"].keys(); keys.sort()
	var start: int = rng.randi() % maxi(1, keys.size())
	for i in keys.size():
		var key: String = String(keys[(start + i) % keys.size()])
		var cat: int = bin_category(e, f, key, day)
		var parts: PackedStringArray = key.split(":")
		var age: int = int(floor(day / People.year_days())) - int(parts[1])
		if cat >= 2 or int(f["age_bins"][key]) <= 0 or (draft_only and (age < ar.x or age > ar.y)): continue
		# A resident named before this row's staggered year turn already has
		# today's detailed age. Move just that slot out of its stored category.
		var counted_epoch: float = float(f.get("population_year", floor(day / People.year_days()))) * People.year_days()
		var counted_cat: int = bin_category(e, f, key, counted_epoch)
		# A staffing identity cannot advance the row's pending age/category turn.
		if assigned and counted_cat != cat: continue
		if counted_cat != cat:
			f[["m", "f", "old", "kids"][counted_cat]] -= 1
			f[["m", "f", "old", "kids"][cat]] += 1
			if counted_cat >= 2: e["adults"] += 1
		var p: Array = Persons._new(e, f, race, int(parts[0]), float(parts[1].to_int()) * People.year_days(), 0, rng)
		# Collective workforce labels are economic owners, never a person's
		# surname. Materialize his native cultural surname with his identity.
		var culture: Dictionary = TownEcon.data()["cultures"].get(String(f.get("cul", e.get("culture", "middle"))), TownEcon.culture_of(e))
		var names: Dictionary = DB.names.get(String(culture.get("names", race)), DB.names.get(race, DB.names.get("human", {})))
		var surnames: Array = names.get("last", ["Smith"])
		p[7] = "%s %s" % [Persons.first_of(e, p), surnames[rng.randi() % surnames.size()]]
		f["age_bins"][key] = int(f["age_bins"][key]) - 1
		if int(f["age_bins"][key]) == 0: f["age_bins"].erase(key)
		Persons.pp(f).append(p)
		TownSweep.appended(e, f, p)
		# Naming a resident never refills the body condition already lost to
		# hunger. This is the existing person-local native condition account.
		var group: String = "workers" if cat < 2 else ("elders" if cat == 2 else "children")
		var condition: float = clampf(float(f.get("pool_condition", {}).get(group, 1.0)), 0.0, 1.0)
		if condition < 1.0:
			if not f.has("bc"): f["bc"] = {}
			f["bc"][str(int(p[0]))] = condition
		return p
	return []

# Runtime-only: never add derived counts to a household or its save. A value
# snapshot detects in-place bin edits as well as replacements, without a hash.
static var _child_counts: Dictionary = {}

static func child_older(f: Dictionary, e: Dictionary, day: float) -> int:
	var ab: Dictionary = People.ages(String(f.get("race", Persons.race_of(e))))
	var adult: int = int(ab["adult"])
	var from_age: float = float(Barge.B()["labour"]["kid_from"]) * float(ab["adult"]) / 16.0
	var year: int = int(floor(day / People.year_days()))
	var bins: Dictionary = f.get("age_bins", {})
	var key: String = "%s:%d" % [e.get("identity_scope", ""), int(f.get("id", -1))]
	var cached: Array = _child_counts.get(key, [])
	if cached.size() == 5 and int(cached[0]) == year and float(cached[1]) == from_age and int(cached[2]) == adult and cached[3] == bins:
		return int(cached[4])
	var n: int = 0
	for bin_key: Variant in bins:
		var age: int = year - int(String(bin_key).split(":")[1])
		if age >= from_age and age < adult: n += int(bins[bin_key])
	if _child_counts.size() >= 1024: _child_counts.clear()
	_child_counts[key] = [year, from_age, adult, bins.duplicate(), n]
	return n

static func summary(e: Dictionary, rows: Array = []) -> Dictionary:
	var out := {"population": 0, "households": 0, "tracked_families": 0, "cohorts": 0, "anonymous": 0, "detailed": 0, "children": 0, "adults": 0, "elders": 0, "female": 0, "male": 0, "away": 0, "common_wealth": 0.0, "common_jobs": 0, "private_wealth": 0.0, "jobs": 0, "recruitable": 0}
	for f in (rows if not rows.is_empty() else e.get("fams", [])):
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

## The same civilian roster is used by staffing, Records and recruitment.
static func home_worker_count(f: Dictionary) -> int:
	var count: int = 0
	var sweep_row: Dictionary = TownSweep.row(f)
	if not sweep_row.is_empty(): return int(sweep_row["home_n"])
	for p: Array in Persons.pp_read(f):
		if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]: count += 1
	return count

static func home_workers(f: Dictionary) -> Array:
	var sweep_row: Dictionary = TownSweep.row(f)
	if not sweep_row.is_empty(): return TownSweep.home_workers(sweep_row)
	var home: Array = []
	for p: Array in Persons.pp_read(f):
		if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]: home.append(p)
	home.sort_custom(func(x, y): return float(x[3]) < float(y[3]) if float(x[3]) != float(y[3]) else int(x[0]) < int(y[0]))
	return home

## One responsible person per kept shop or held paid-business block. Academy
## places retain their anonymous-first eligibility and are never materialized here.
static func _staff_targets(e: Dictionary, f: Dictionary) -> Dictionary:
	var targets: Dictionary = {}
	for bid in f.get("keeps", []): targets[int(bid)] = true
	for key in f.get("jobs", {}):
		var bid: int = int(key)
		if int(f["jobs"][key]) > 0 and not targets.has(bid) and String(e["biz"][bid]["type"]) != "academy":
			targets[bid] = false
	return targets

static func named_work(e: Dictionary, f: Dictionary, home: Array, places: Array, counts: Array[int]) -> Dictionary:
	# Counted blocks retain the exact hired/casual/keeper/land slot order without
	# allocating titles, wages and dictionaries for every anonymous resident.
	var remaining: int = (f.get("keeps", []) as Array).size() + int(f.get("hands", 0))
	var prefix: int = 0
	while prefix < counts.size() and remaining > 0:
		remaining -= counts[prefix]
		prefix += 1
	var slots: Array = places.slice(prefix) + places.slice(0, prefix)
	var sizes: Array = counts.slice(prefix) + counts.slice(0, prefix)
	var offset: int = anonymous(f, 0) + anonymous(f, 1)
	var assigned: Array[int] = []
	var reserved: Dictionary = {}
	var covered: Dictionary = {}
	var targets: Dictionary = _staff_targets(e, f)
	var first: Dictionary = {}
	for at in slots.size():
		var job: Dictionary = slots[at]
		var bid: int = int(job.get("biz", -1))
		if targets.has(bid) and bool(job.get("keeper", false)) == bool(targets[bid]) and not first.has(bid): first[bid] = at
	var block: int = 0
	var start: int = 0
	for i in home.size():
		var place: int = offset + i
		while block < slots.size() and place >= start + int(sizes[block]):
			start += int(sizes[block])
			block += 1
		assigned.append(block if block < slots.size() else -1)
		if block >= slots.size(): continue
		var job: Dictionary = slots[block]
		var bid: int = int(job.get("biz", -1))
		if bid >= 0 and String(e["biz"][bid]["type"]) == "academy": reserved[i] = true
		if first.has(bid) and bool(job.get("keeper", false)) == bool(targets[bid]) and not covered.has(bid):
			reserved[i] = true
			covered[bid] = true
	for bid in first:
		if covered.has(bid): continue
		for i in home.size():
			if reserved.has(i): continue
			assigned[i] = int(first[bid])
			reserved[i] = true
			break
	# v0.100: a cohort Academy place is positional. A home reserve may hold it
	# as staff but can never be its lead (Academy.lead_gone), so a house whose
	# only named Academy holder is a reserve could never appoint a head while
	# that place filled its cap. Swap the first such place with a lead-eligible
	# home adult of the same household, as the responsibility swaps above do.
	var academy_holders: Dictionary = {}
	for i in home.size():
		if assigned[i] < 0: continue
		var holder_job: Dictionary = slots[assigned[i]]
		var holder_bid: int = int(holder_job.get("biz", -1))
		if holder_bid >= 0 and not bool(holder_job.get("keeper", false)) and String(e["biz"][holder_bid]["type"]) == "academy":
			if not academy_holders.has(holder_bid): academy_holders[holder_bid] = []
			academy_holders[holder_bid].append(i)
	for bid in academy_holders:
		var holders: Array = academy_holders[bid]
		if holders.any(func(i): return String(home[int(i)][4]) in ["", "hire"]): continue
		for j in home.size():
			if not String(home[j][4]) in ["", "hire"]: continue
			# Exchanging two named places preserves a shop responsibility too.
			# Only another Academy place must retain its eligible holder.
			if assigned[j] >= 0:
				var other_bid: int = int(slots[assigned[j]].get("biz", -1))
				if other_bid >= 0 and String(e["biz"][other_bid]["type"]) == "academy": continue
			var first_holder: int = int(holders[0])
			var swap_slot: int = assigned[first_holder]
			assigned[first_holder] = assigned[j]
			assigned[j] = swap_slot
			reserved[j] = true
			break
	var out: Dictionary = {}
	for i in home.size():
		out[int(home[i][0])] = (slots[assigned[i]] as Dictionary).duplicate() if assigned[i] >= 0 else {"kind": "none", "title": "out of work", "where": "", "wage": 0.0}
	# A retained paid place belongs to its appointed head even when another
	# job count shifts the positional baseline. Share this swap with all readers.
	if e.has("academy") and (f["jobs"] as Dictionary).has(str(int(e["academy"]))):
		Academy.mark_lead(e, f, out)
	return out

## Simulation-only: one exact bin debit per new identity, with no population,
## service, job, wage or purse adjustment. Bounded by the existing adult bins.
static func staff(e: Dictionary, f: Dictionary) -> void:
	if not is_cohort(f) or f.get("gone", false) or f.get("estate", false): return
	var targets: Dictionary = _staff_targets(e, f)
	if targets.is_empty(): return
	var home: int = home_worker_count(f)
	var left: int = anonymous(f, 0) + anonymous(f, 1)
	var free_n: int = home
	var academy: Array[Vector2i] = []
	var at: int = 0
	# Academy slots stay reserved in the anonymous-first baseline. Every other
	# home adult can cover one responsibility through named_work's swaps.
	for key in f.get("jobs", {}):
		var count: int = maxi(0, int(f["jobs"][key]))
		if count > 0 and String(e["biz"][int(key)]["type"]) == "academy":
			academy.append(Vector2i(at, at + count))
			free_n -= maxi(0, mini(at + count, left + home) - maxi(at, left))
		at += count
	if free_n >= targets.size(): return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([e.get("identity_scope", ""), f.get("seed", 0), e.get("next_pid", 1), "staff"])
	# Each exact bin debit extends the named tail by one slot. Reuse these
	# integer ranges instead of rebuilding Persons.work after every identity.
	while left > 0 and free_n < targets.size():
		if _from_bins(e, f, float(e.get("day", 0)), rng, false, true).is_empty(): return
		left -= 1
		var academy_place: bool = false
		for span: Vector2i in academy:
			if left >= span.x and left < span.y:
				academy_place = true
				break
		if not academy_place: free_n += 1

static func race_rows(e: Dictionary) -> Array:
	var by_race := {}
	for f in e.get("fams", []):
		if f.get("gone", false) or f.get("estate", false): continue
		var race := String(f.get("race", Persons.race_of(e)))
		if not by_race.has(race): by_race[race] = []
		by_race[race].append(f)
	var out := []
	for race in by_race:
		var row: Dictionary = summary(e, by_race[race])
		row["race"] = race; out.append(row)
	return out

static func generated_business_owners(e: Dictionary) -> void:
	var tracked: Array = e["fams"].filter(func(f): return not is_cohort(f) and not f.get("estate", false) and not f.get("gone", false))
	if tracked.is_empty(): return
	for b in e.get("biz", []):
		if b.get("closed", false) or b.get("for_sale", false): continue
		# v0.100: the final generation pass must not undo Academy._state_owner.
		# v0.100: a private keeper makes load repair reassign jobs and settle wages.
		if String(b.get("type", "")) == "academy": continue
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
	var year_days: float = People.year_days()
	var year: int = int(floor(day / year_days))
	var prior: int = int(f.get("population_year", year))
	if year > prior:
		var ab: Dictionary = People.ages(String(f["race"]))
		var adult: int = int(ab["adult"])
		var elder: int = int(ab["elder"])
		# Retain the original multiply/divide/floor for the stored epoch.
		var prior_year: int = int(floor(float(prior) * year_days / year_days))
		for key in f["age_bins"].keys():
			var parts: PackedStringArray = String(key).split(":")
			var sex: int = int(parts[0])
			var born: int = int(parts[1])
			var before_age: int = prior_year - born
			var after_age: int = year - born
			var before: int = 3 if before_age < adult else (2 if before_age >= elder else sex)
			var after: int = 3 if after_age < adult else (2 if after_age >= elder else sex)
			var n := int(f["age_bins"][key])
			if before != after:
				f[["m", "f", "old", "kids"][before]] -= n
				f[["m", "f", "old", "kids"][after]] += n
				e["adults"] += n if before == 3 else -n
			if after_age >= int(ab["lifespan"]): kill_slots(e, f, String(key), n, day, "old age")
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
			var bands: Dictionary = People.ages(String(f.get("race", Persons.race_of(e))))
			var adult: int = int(bands["adult"])
			var elder: int = int(bands["elder"])
			for key in f["age_bins"].keys():
				var parts: PackedStringArray = String(key).split(":")
				var age: int = year - int(parts[1])
				var cat: int = 3 if age < adult else (2 if age >= elder else int(parts[0]))
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
