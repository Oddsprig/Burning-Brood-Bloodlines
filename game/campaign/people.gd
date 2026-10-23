class_name People
extends RefCounted
## Every person in a non-monster force is a real person from a real family in a real settlement, paid real
## wages into that family's purse (Douglas, economy spec 1 + 2). Monsters and beasts are excluded.
##
## Generic API (economy spec 2 builds army pay and ranks on it):
##   draw(town, rng, role) -> family id    a family member goes into service (militia, caravan crew, army):
##                                          the family keeps counting them, f.serving[role] holds them off
##                                          the family's own work (Families.reassign)
##   release(town, fam, role)              back home from service
##   pay(town, fam, amount) -> paid        wages into the family purse (the caller takes the gold from its
##                                          own holder: treasury, market till, company gold: always conserved)
##   casualty(game, unit, kind, serving)   kind "dead" | "maimed": the family loses (or keeps, maimed) the
##                                          person; a history line either way
##   name_from(town, fam, rng)             a first name + the family's surname
## Company: every company unit has a family record (recruits bring theirs; others get one made in their home
## town); the company's daily wages go into those purses (pay_company).

const MILITIA_WAGE := 70.0   # coins per militiaman per day (barge rank base: recruit), from the town treasury
const CREW_WAGE := 80.0      # caravan driver/porter per day (barge pay table: porter 80), from the owner (the town's merchants)
const GUARD_WAGE := 100.0    # caravan guard per day (barge rank base: soldier 100)
const DRIVERS := 2           # drivers and porters per caravan besides the guards [ours]

# ================================================================== ages (Douglas: real ages for everyone)
static func ages(race: String) -> Dictionary:
	var A: Dictionary = TownEcon.data()["ages"]
	return A.get(race, A["_default"])

static func year_days() -> float:
	return float(4 * Calendar.DAYS_PER_SEASON)

## Age in whole years on `day` (from the birth day).
static func age_on(u: Unit, day: float) -> int:
	if u.born <= -1.0e8:
		return u.age
	return maxi(0, int(floor((day - u.born) / year_days())))

## Gives a named person a birth day: his rolled age (Factory: 17-45) mapped into his race's adult years, so an
## elf is a young adult at 60 and a goblin an old one at 20. No RNG draw (nothing else shifts). Sets u.age.
static func set_born(u: Unit, day: float) -> void:
	if u.born > -1.0e8:
		u.age = age_on(u, day)
		return
	var a := ages(u.race)
	if u.race in ["wolf", "bear", "boar"] or Monsters.is_monster_faction(u.faction):
		u.born = day - (float(u.age) + 0.5) * year_days()
		return
	var t := clampf(float(u.age - 17) / 28.0, 0.0, 1.0)
	var adult := float(a["adult"]); var elder := float(a["elder"])
	var yrs := adult + 1.0 + t * (elder - adult) * 0.75
	var frac := float(absi(hash([u.uid, u.name])) % 1000) / 1000.0
	u.born = day - (yrs + frac) * year_days()
	u.age = age_on(u, day)

## Daily: every named person's age follows the calendar (company and town pools; bands weekly).
static func tick_ages(game, d: int) -> void:
	var day := float(game.day)
	for u in game.company:
		set_born(u, day)
	for u: Unit in Mobilization.reserves(game):
		set_born(u, day)
	for tid in game.world.get("towns", {}):
		for u in game.world["towns"][tid].get("recruits", []):
			set_born(u, day)
	# (soldiers in the field get their birth day when they are bound to a register person; their age is read
	# from it when shown: no daily pass over every band)

## The town's census (the register header): population, households, children / adults / elders (the race's
## age bands: children under ages.adult, elders from ages.elder) and female / male, from the family rows; the sex
## of children and elders from their person records (every family keeps them; a record-less row splits half and
## half, the odd one by the family seed). Also homeless households, empty dwellings (houses the town estate holds
## with nobody in them) and the births and deaths of the last census season (stats.bd_last) and since.
## Company men left their family rows and are not counted.
static func census(e: Dictionary) -> Dictionary:
	var c := {"population": 0, "households": 0, "children": 0, "adults": 0, "elders": 0, "female": 0, "male": 0,
		"homeless": 0, "empty_homes": int(e["fams"][0].get("homes", 0)) if not (e["fams"] as Array).is_empty() else 0,
		"births_last": 0, "deaths_last": 0, "births": int(e.get("stats", {}).get("births", 0)), "deaths": int(e.get("stats", {}).get("deaths", 0))}
	var bd: Array = e.get("stats", {}).get("bd_last", [0, 0])
	c["births_last"] = int(bd[0]); c["deaths_last"] = int(bd[1])
	for f in e["fams"]:
		if f.get("gone", false) or f.has("estate"):
			continue
		var k := int(f["kids"]); var o := int(f["old"])
		c["households"] += 1
		c["population"] += Families.people(f)
		if int(f["homes"]) <= 0:
			c["homeless"] += int(f.get("households", 1))
		c["children"] += k; c["elders"] += o; c["adults"] += int(f["m"]) + int(f["f"])
		c["male"] += int(f["m"]); c["female"] += int(f["f"])
		if f.has("pp"):
			var kf := 0; var of := 0
			for p in Persons.kp(f):
				kf += int(p[2])
			for p in Persons.pp(f):
				if int(p[6]) == 1 and not Persons.AWAY.has(String(p[4])):
					of += int(p[2])
			kf = mini(kf, k); of = mini(of, o)
			c["female"] += kf + of
			c["male"] += k - kf + o - of
		else:
			var odd := int(f.get("seed", 0)) & 1
			c["male"] += k / 2 + o / 2 + (odd if k % 2 == 1 else 0) + ((1 - odd) if o % 2 == 1 else 0)
			c["female"] += k / 2 + o / 2 + ((1 - odd) if k % 2 == 1 else 0) + (odd if o % 2 == 1 else 0)
	var totals := Population.summary(e)
	for key in totals: c[key] = totals[key]
	return c

static func census_line(e: Dictionary) -> String:
	var c := census(e)
	var a := ages(String(TownEcon.culture_of(e)["race"]))
	return ("Census: %d people in %d households: %d children (under %d), %d adults, %d elders (%d and older); %d female, %d male. " +
		"%d households homeless, %d empty dwellings. Last season: %d born, %d died.") % [int(c["population"]), int(c["households"]),
		int(c["children"]), int(a["adult"]), int(c["adults"]), int(c["elders"]), int(a["elder"]), int(c["female"]), int(c["male"]),
		int(c["homeless"]), int(c["empty_homes"]), int(c["births_last"]), int(c["deaths_last"])]


## The family register: every grown-up of the family from its person records (Persons): name, sex, age, state
## ("for hire at the tavern", "with your company", "in the militia", "at home"), the same people the recruit pool
## and the forces use; children are counts with seeded names. [{name, role, age, state, pid}]
static func register(game, town: Dictionary, fid: int) -> Array:
	var e := _e(town)
	var f := fam_of(town, fid)
	if f.is_empty() or f.has("estate"):
		return []
	var day := float(game.day)
	Persons.sync(e, f, day)
	var out := Persons.household(e, f, day)   # family order, kinship, work and wage (Persons.person_line)
	for m in out:
		m["role"] = {"boy": "child", "girl": "child"}.get(m["kind"], m["kind"])
		m["state"] = Persons.SERVICE_WORDS.get(String(m["state"]), String(m["state"]))
	return out

static func _e(town: Dictionary) -> Dictionary:
	return town.get("econ", {}) if TownEcon.has_econ(town) else {}

static func fam_of(town: Dictionary, fid: int) -> Dictionary:
	var e := _e(town)
	if e.is_empty() or fid < 0 or fid >= (e["fams"] as Array).size():
		return {}
	return e["fams"][fid]

## A person from the town's register goes into service: idle hands and hard-up families first; never a family's
## last free adult. The chosen person record is marked with the role (People.last_person); the caller binds his
## Unit to it with bind(). Returns the family id, -1 when nobody can be spared.
static var last_person: Array = []

static func draw(town: Dictionary, rng: RandomNumberGenerator, role: String, offer: Dictionary = {}) -> int:
	if role in ["bandit", "deserter"]:
		return draw_outlaw(town, rng, role, offer)
	last_person = []
	var e := _e(town)
	if e.is_empty():
		return -1
	var fams: Array = e["fams"]
	var best: Dictionary = {}
	var bv := -1.0
	var start := rng.randi() % maxi(1, fams.size())
	var tries := 0
	var day := float(e.get("day", 0))
	for j in fams.size():
		var f: Dictionary = fams[(start + j) % fams.size()]
		if f["gone"] or f.has("estate"):
			continue
		if Population.spare(f) <= 0:
			continue
		var v := float(f["idle"]) + Families.hardship(f) + rng.randf() * 0.5
		if v > bv:
			Persons.sync(e, f, day)
			if Population.eligible_slots(e, f, day) <= 0 and free_volunteer(e, f, rng).is_empty():
				continue
			bv = v; best = f
		tries += 1
		if tries >= 24 and bv >= 1.0:
			break   # good enough: no need to look at every family
	if best.is_empty():
		return -1
	var p := free_volunteer(e, best, rng)
	if p.is_empty() and Population.is_cohort(best): p = Population.promote(e, best, day, rng)
	if p.is_empty():
		return -1
	Persons.log_life(p, float(e.get("day", 0)), "serve", role)   # his own history: the day he joined
	p[4] = role
	last_person = p
	var sv: Dictionary = best["serve"]
	sv[role] = int(sv.get(role, 0)) + 1
	Families.reassign(e, best)
	return int(best["id"])

static func outlaw_value(e: Dictionary, f: Dictionary, p: Array, job: Dictionary, role: String, offer: Dictionary) -> float:
	if int(p[6]) != 0 or String(p[4]) != "" or int(p[5]) >= 0 or job.get("keeper", false): return -INF
	var rate := float(Families.daily_rates(e, f)["food"])
	var food_cost := rate * float(e["price"].get("grain", 1))
	var food_days := float(f["store"]["food"]) + float(f["purse"]) / maxf(0.01, food_cost)
	var homeless := int(f["homes"]) <= 0
	# Poverty and hunger belong to this household. A wealthy, fed idle adult has no reason to become an outlaw.
	if food_days >= 7 and not homeless: return -INF
	if float(f["purse"]) >= food_cost * 7: return -INF
	var current := float(job.get("wage", 0))
	var funded := maxf(0, float(offer.get("pay_day", 0)))
	var meals := minf(7, float(offer.get("food_days", 0)))
	var food_gain := maxf(0, meals - float(f["store"]["food"])) * food_cost / 7
	var memory := Persons.unpaid_memory(p, role)
	if not memory.is_empty():
		# The observed unpaid share persists after discharge. It reduces the value of another promise.
		var served := maxf(1, float(memory.get("served_days", memory["days"])))
		funded *= maxf(0, 1 - float(memory["days"]) / served)
	var savings_at_risk := float(f["purse"]) / maxf(1, Families.adults(f)) / 7
	return funded + food_gain - current - savings_at_risk

static func draw_outlaw(town: Dictionary, rng: RandomNumberGenerator, role: String, offer: Dictionary) -> int:
	last_person = []
	var e := _e(town)
	if e.is_empty(): return -1
	var best_f: Dictionary = {}
	var best_p: Array = []
	var best := 0.0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or Population.spare(f) <= 0: continue
		Persons.sync(e, f, float(e.get("day", 0)))
		var jobs := Persons.work(e, f)
		if Population.eligible_slots(e, f, float(e.get("day", 0))) > 0:
			var probe := [-1, 0, 0, 0.0, "", -1, 0]
			var current := 0.0
			if int(f.get("idle", 0)) <= 0:
				current = INF
				for key in f.get("jobs", {}): current = minf(current, float(e["biz"][int(key)]["wage"]))
				for key in f.get("cj", {}): current = minf(current, Barge.casual_wage(e, String(key)))
				if current == INF: current = 0.0
			var value := outlaw_value(e, f, probe, {"wage": current}, role, offer)
			if value > best: best = value; best_f = f; best_p = []
		for p in Persons.pp(f):
			var value := outlaw_value(e, f, p, jobs.get(int(p[0]), {}), role, offer)
			if value > best or (value == best and value > 0 and rng.randi_range(0, 1) == 1):
				best = value; best_f = f; best_p = p
	if best_p.is_empty() and not best_f.is_empty(): best_p = Population.promote(e, best_f, float(e.get("day", 0)), rng)
	if best_p.is_empty(): return -1
	Persons.log_life(best_p, float(e.get("day", 0)), "serve", role)
	best_p[4] = role
	last_person = best_p
	best_f["serve"][role] = int(best_f["serve"].get(role, 0)) + 1
	Families.reassign(e, best_f)
	return int(best_f["id"])

# ---------------------------------------------------------------- the army draft (war pick 4)
## Douglas's war pick 4 (barge-4 section 8, FIX-4): an army is raised only from real people of its home town. A
## soldier is a free grown-up at home (no service, no unit, not in the recruit pool) of draft age, from a family that
## keeps at least two grown-ups at home (as draw), labourers first: out of work, then casual day labour, then wage
## jobs. Never a hand the family's land or herd needs (Persons.work gives those places first). Nobody to spare: the
## band is smaller, or not raised; no family is ever made up for it.
const DRAFT_TIER := {"none": 0, "casual": 1, "job": 2}   # "land" and "herd" hands are never drafted
const DRAFT_LO := 17   # human years; other races at the same stage of life (draft_ages)
const DRAFT_HI := 30

## [youngest, oldest] draft age for a race: 17-30 for men, mapped into the race's adult years the way set_born maps a
## rolled troop age (adult + 1 .. a share of the adult span), so an orc drafts at 13-21 and an elf at 41-131.
static func draft_ages(race: String) -> Vector2i:
	var a := ages(race)
	var adult := float(a["adult"]); var elder := float(a["elder"])
	var lo := adult + 1.0
	var hi := lo + float(DRAFT_HI - DRAFT_LO) / 28.0 * (elder - adult) * 0.75
	return Vector2i(int(lo), int(floor(hi)))

## Everyone the town could send to the army right now, best first: [[tier, -hardship, family id, person id]].
static func draft_pool(town: Dictionary) -> Array:
	var out := []
	var e := _e(town)
	if e.is_empty():
		return out
	var day := float(e.get("day", 0))
	var ar := draft_ages(Persons.race_of(e))
	for f in e["fams"]:
		if f["gone"] or f.has("estate") or Population.spare(f) <= 0:
			continue
		Persons.sync(e, f, day)
		if Population.is_cohort(f):
			var casual := 0
			for key in f.get("cj", {}): casual += int(f["cj"][key])
			for i in Population.eligible_slots(e, f, day, true):
				var tier := 0 if i < int(f.get("idle", 0)) else (1 if i < int(f.get("idle", 0)) + casual else 2)
				out.append([tier, -Families.hardship(f), int(f["id"]), -1])
		var young := false
		for p in Persons.pp(f):
			if int(p[6]) == 0 and String(p[4]) == "" and int(p[5]) < 0:
				var age0 := Persons.age_of(p, day)
				if age0 >= ar.x and age0 <= ar.y:
					young = true
					break
		if not young:
			continue
		var wk := _work_kinds(f)
		var hard := Families.hardship(f)
		for p in Persons.pp(f):
			if int(p[6]) != 0 or String(p[4]) != "" or int(p[5]) >= 0:
				continue
			var age := Persons.age_of(p, day)
			if age < ar.x or age > ar.y:
				continue
			var tier := int(DRAFT_TIER.get(String(wk.get(int(p[0]), "")), -1))
			if tier < 0:
				continue
			out.append([tier, -hard, int(f["id"]), int(p[0])])
	out.sort_custom(func(x, y):
		for i in 4:
			if x[i] != y[i]:
				return x[i] < y[i]
		return false)
	return out

## pid -> the kind of place Persons.work gives him (land/herd, job, casual, none), by the same rule and order
## (grown-ups at home oldest first: the family's land and herd hands, then its jobs, then casual work), without
## building the titles and wages (the draft runs as a map-frame job).
static func _work_kinds(f: Dictionary) -> Dictionary:
	var home := []
	for p in Persons.pp(f):
		if int(p[6]) == 0 and (String(p[4]) == "" or String(p[4]) == "hire"):
			home.append(p)
	home.sort_custom(func(x, y): return float(x[3]) < float(y[3]) if float(x[3]) != float(y[3]) else int(x[0]) < int(y[0]))
	var hands := maxi(0, int(f.get("hands", 0)))
	var keeps: int = f.get("keeps", []).size()
	var jobs := 0
	for k in f["jobs"]:
		jobs += int(f["jobs"][k])
	var cas := 0
	for j in f.get("cj", {}):
		cas += int(f["cj"][j])
	var out := {}
	for i in home.size():
		var k := "none"
		if i < keeps:
			k = "keeper"
		elif i < keeps + hands:
			k = "land"
		elif i < keeps + hands + jobs:
			k = "job"
		elif i < keeps + hands + jobs + cas:
			k = "casual"
		out[int(home[i][0])] = k
	return out

## Takes the first in the pool who can still go (his family keeps two grown-ups at home); marks him for the role
## like draw (bind then makes the unit that person). Returns the family id, or -1 when nobody is left.
static func draft(town: Dictionary, pool: Array, role: String) -> int:
	last_person = []
	var e := _e(town)
	while not pool.is_empty():
		var r: Array = pool.pop_front()
		var f := fam_of(town, int(r[2]))
		if f.is_empty() or f["gone"] or Population.spare(f) <= 0:
			continue
		var p := Persons.by_pid(f, int(r[3]))
		if int(r[3]) == -1 and Population.is_cohort(f):
			var rng := RandomNumberGenerator.new(); rng.seed = hash([e.get("identity_scope", ""), e.get("next_pid", 1), role])
			p = Population.promote(e, f, float(e.get("day", 0)), rng, true)
		if p.is_empty() or String(p[4]) != "" or int(p[5]) >= 0 or int(p[6]) != 0:
			continue
		Persons.log_life(p, float(e.get("day", 0)), "serve", role)
		p[4] = role
		last_person = p
		var sv: Dictionary = f["serve"]
		sv[role] = int(sv.get(role, 0)) + 1
		Families.reassign(e, f)
		return int(f["id"])
	return -1

## The unit IS the person drawn (or, when the caller passes none, a person of that family already marked for the
## role without a unit, or one at home): his name, birth day and age. keep_name: a named chief keeps his name.
static func bind(town: Dictionary, fid: int, u: Unit, role: String, keep_name: bool = false) -> void:
	var e := _e(town)
	var f := fam_of(town, fid)
	if f.is_empty():
		return
	var p: Array = last_person if not last_person.is_empty() and Persons.pp(f).has(last_person) else []
	if p.is_empty():
		for q in Persons.pp(f):
			if String(q[4]) == role and int(q[5]) < 0:
				p = q
				break
	if p.is_empty():
		Persons.sync(e, f, float(e.get("day", 0)))
		var r := RandomNumberGenerator.new()
		r.seed = hash([u.uid, fid, role])
		p = Persons.pick_home(f, r, true)
	if p.is_empty():
		return
	last_person = []
	if keep_name:
		Persons.bind_keep_name(e, f, p, u, role, float(Game.day))
	else:
		Persons.bind(e, f, p, u, role, float(Game.day))
	u.home_town = town["id"]

static func release(town: Dictionary, fid: int, role: String, uid: int = -1) -> void:
	var f := fam_of(town, fid)
	if f.is_empty():
		return
	var sv: Dictionary = f["serve"]
	if int(sv.get(role, 0)) > 0:
		sv[role] = int(sv[role]) - 1
		if int(sv[role]) <= 0:
			sv.erase(role)
		if not f["gone"]:
			Families.reassign(_e(town), f)
	# the person comes home
	var p: Array = Persons.by_uid(f, uid) if uid >= 0 else []
	if p.is_empty():
		for q in Persons.pp(f):
			if String(q[4]) == role:
				p = q
				break
	if not p.is_empty():
		Persons.set_home(p)
		Sickness.came_home(town, f, p)   # sickness: his open case comes home with him

## Wages into the family purse. Returns what was paid (0 when the family is gone or the town has no economy:
## the caller then keeps its gold).
static func pay(town: Dictionary, fid: int, amount: float) -> float:
	var f := fam_of(town, fid)
	if f.is_empty() or f["gone"] or amount <= 0.0:
		return 0.0
	f["purse"] = float(f["purse"]) + amount
	return amount

static func name_from(town: Dictionary, fid: int, rng: RandomNumberGenerator, race: String) -> String:
	var f := fam_of(town, fid)
	if f.is_empty():
		return Factory.random_name(rng, race)
	return Families.person_name(f, rng, race)

## A casualty flows back to the family: the dead leave the family row (and the service count when serving);
## the maimed come home (history line; lasting effects arrive with the retirement/aftermath pick).
static func casualty(game, u: Unit, kind: String, role: String = "") -> void:
	if u == null or u.family < 0:
		return
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	var f := fam_of(town, u.family)
	var person := Persons.by_uid(f, u.uid)
	if kind == "dead":
		# Remove only the saved physical reserve owner; the ordinary native
		# casualty below remains the single person/census death path.
		Mobilization.reserve_died(game, u)
	casualty_rec(game, u.home_town, u.family, u.name, kind, role, person, u.uid)

## The same by record (the army sweep keeps [town, family, role, name] for men no longer on the map).
static func casualty_rec(game, tid: String, fid: int, uname: String, kind: String, role: String = "", pdirect: Array = [], unit_uid: int = -1) -> void:
	var town: Dictionary = game.world.get("towns", {}).get(tid, {})
	var f := fam_of(town, fid)
	if f.is_empty(): return
	var death_book := Census._book(_e(town))
	if kind == "dead" and unit_uid >= 0 and death_book["death_ids"].has("unit:%d" % unit_uid): return
	if pdirect.is_empty() and unit_uid >= 0: pdirect = Persons.by_uid(f, unit_uid)
	if pdirect.is_empty() and unit_uid >= 0: return
	if not pdirect.is_empty() and kind == "dead":
		var key := str(Persons.g(pdirect, Persons.PERSON_UID, ""))
		if key != "" and death_book["death_ids"].has(key): return
	if f.is_empty() or f["gone"]:
		if not f.is_empty() and kind == "dead":   # the census: a man of a house that is gone still has one cause (not in the count)
			var pg: Array = pdirect if not pdirect.is_empty() else Persons.by_name(_e(town), f, uname)
			_census_death(_e(town), f, pg, uname, float(game.day), Census.fate_for(game.world, int(pg[5]) if not pg.is_empty() else -1, role, String(town.get("name", ""))), false)
		return
	var e := _e(town)
	var day := float(game.day)
	f["named"] = true
	var p: Array = pdirect if not pdirect.is_empty() else Persons.by_name(e, f, uname)   # the register's own person record
	if p.is_empty() and role != "company":
		for q in Persons.pp(f):   # no record by that name (older saves): someone of that service without a unit of his own, else at home
			if String(q[4]) == role and int(q[5]) < 0:
				p = q
				break
		if p.is_empty():
			for q in Persons.pp(f):
				if String(q[4]) == "":
					p = q
					break
	# the census: one cause per death (the fight in progress, the fate noted for his unit, else his service)
	var fate: Array = Census.fate_for(game.world, int(p[5]) if not p.is_empty() else -1, role, String(town.get("name", ""))) if kind == "dead" else []
	var murdered := kind == "dead" and String(fate[0]) == "murdered"
	if role == "company":
		# company men already left the family row's counts when hired: the family keeps the memory and the record
		var service_text := ("%s fell in battle with the company." if kind == "dead" else "%s came home maimed from the company.") % uname
		Families.add_hist(f, "%s was murdered." % uname if murdered else service_text, day)
		Families.event(f, "died" if kind == "dead" else "maimed", [uname, "company"], day)
		if kind == "dead":
			_census_death(e, f, p, uname, day, fate, false)
		if kind == "dead" and not p.is_empty():
			Persons.remove(f, p, e)
		return
	if kind == "dead":
		e["stats"]["deaths"] = int(e["stats"].get("deaths", 0)) + 1
		var before := Families.people(f)
		if role != "":
			var sv: Dictionary = f["serve"]
			if int(sv.get(role, 0)) > 0:
				sv[role] = int(sv[role]) - 1
				if int(sv[role]) <= 0:
					sv.erase(role)
		var s := "m"
		if not p.is_empty():
			# the dead man's own record leaves the register, and his own row count with him
			s = "kids" if int(p[6]) == 2 else ("old" if int(p[6]) == 1 else ("m" if int(p[2]) == 0 else "f"))
			if s == "kids":
				Persons.forget(e, f, p)
				Persons.drop_im(f, int(p[0]))
				Persons.kp(f).erase(p)
			else:
				Persons.remove(f, p, e)
			if int(f[s]) > 0:
				f[s] = int(f[s]) - 1
				e["pop"] = int(e["pop"]) - 1
				if s not in ["old", "kids"]:
					e["adults"] = int(e["adults"]) - 1
		elif Persons.can_lose(f, 0) or Persons.can_lose(f, 1):   # no record of him: someone at home stands for him
			s = "m" if Persons.can_lose(f, 0) else "f"
			f[s] = int(f[s]) - 1
			e["pop"] = int(e["pop"]) - 1
			e["adults"] = int(e["adults"]) - 1
		_census_death(e, f, p, uname, day, fate, Families.people(f) < before)
		var death_text := "%s was murdered." % uname if murdered else "%s died %s." % [uname, String(Backstory.data()["how"].get(role, "in battle"))]
		Families.add_hist(f, death_text, day)
		Families.event(f, "died", [uname, role, ("f" if not p.is_empty() and int(p[2]) == 1 else ("f" if s == "f" else "m"))], day)
		Families.reassign(e, f)
		if Families.people(f) <= 0:
			Families.extinct(e, f, day)
	else:
		if not p.is_empty():
			Persons.log_life(p, day, "wound", role)   # his own history
		Families.add_hist(f, "%s came home maimed." % uname, day)
		Families.event(f, "maimed", [uname, role], day)

## The census row for a death in service: his own record when the register has one, else his name.
static func _census_death(e: Dictionary, f: Dictionary, p: Array, uname: String, day: float, fate: Array, counted: bool) -> void:
	if not p.is_empty():
		Census.person_died(e, f, p, day, String(fate[0]), String(fate[1]), counted)
	else:
		Census.record_death(e, -1, uname, -1, -1, day, String(fate[0]), String(fate[1]), counted, int(f["id"]))

# ================================================================== company
## Every company unit gets a family record: a recruit brings his own; others (the starting company, old
## saves) get one made in their home town (or the start town).
static func adopt_company(game) -> void:
	var w: Dictionary = game.world
	if not w.has("towns"):
		return
	for u in game.company:
		var have := fam_of(w["towns"].get(u.home_town, {}), u.family) if u.family >= 0 else {}
		if not have.is_empty():
			if Population.is_cohort(have): continue   # saved cohort identities are never fabricated on load
			if Persons.by_uid(have, u.uid).is_empty():   # older saves: his own record in the register
				_company_person(_e(w["towns"][u.home_town]), have, u, float(game.day))
			continue
		var has_pools := false
		for source in w["towns"].values():
			for f in _e(source).get("fams", []):
				if Population.is_cohort(f): has_pools = true; break
			if has_pools: break
		if has_pools:
			_adopt_resident_company(game, u)
			continue
		var tid: String = u.home_town if w["towns"].has(u.home_town) else _town_for(w, u)
		var town: Dictionary = w["towns"].get(tid, {})
		var e := _e(town)
		if e.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([u.name, u.title, tid])
		var cul: Dictionary = TownEcon.culture_of(e)
		var f := Families.make_family((e["fams"] as Array).size(), u.race, cul, rng, {})
		var parts: PackedStringArray = String(u.name).split(" ")
		if parts.size() > 1:
			f["name"] = parts[-1]
		f["named"] = true
		f["store"] = {"food": 10.0, "drink": 5.0, "wood": 5.0}
		f["last"] = float(game.day)
		f["tax_season"] = int(e["tax"]["season"])
		(e["fams"] as Array).append(f)
		e["pop"] = int(e["pop"]) + Families.people(f)
		e["adults"] = int(e["adults"]) + Families.adults(f)
		e["homes"] = int(e["homes"]) + int(f["homes"])
		Census.record_move(e, -1, "in", "", float(game.day), "family of a company man", Families.people(f))   # the census: arrivals
		Families.add_hist(f, "%s serves with a mercenary company." % u.name, float(game.day))
		u.home_town = tid
		u.family = int(f["id"])
		Persons.generate(e, f, float(game.day))
		_company_person(e, f, u, float(game.day))
		Families.reassign(e, f)
		Persons.track_jobs(e, f, float(game.day))

## Starting companies consume native residents; prehistory kit/wallet remain their actual owners.
static func _adopt_resident_company(game, u: Unit) -> bool:
	var towns: Dictionary = game.world["towns"]
	var ids: Array = towns.keys(); ids.sort()
	var preferred := _town_for(game.world, u)
	if ids.has(preferred): ids.erase(preferred); ids.push_front(preferred)
	var rng := RandomNumberGenerator.new(); rng.seed = hash([u.uid, u.name, "company-resident"])
	for tid in ids:
		var town: Dictionary = towns[tid]
		var e := _e(town)
		if e.is_empty() or Persons.race_of(e) != u.race: continue
		for f in e["fams"]:
			if not Population.is_cohort(f) or String(f.get("race", Persons.race_of(e))) != u.race: continue
			var p := Population.promote(e, f, float(game.day), rng)
			if p.is_empty(): continue
			Persons.bind(e, f, p, u, "company", float(game.day))
			u.home_town = String(tid)
			var sex: String = ["m", "f"][int(p[2])]
			f[sex] = int(f[sex]) - 1; e["pop"] = int(e["pop"]) - 1; e["adults"] = int(e["adults"]) - 1
			Census.record_move(e, int(p[0]), "out", "", float(game.day), "joined the company")
			Families.reassign(e, f)
			return true
	return false

## Older saves: every named unit with a family but no person record of his own gets one (keeping his name): the
## company ("company"), recruit pools ("hire"), forces (their role, already counted in the row). Nothing else
## changes on load (the weekly town turn checks the register against the map: Persons.sweep_town).
static func rebind_all(game) -> void:
	var w: Dictionary = game.world
	var day := float(game.day)
	var todo := []
	for tid in w.get("towns", {}):
		for u in w["towns"][tid].get("recruits", []):
			if u is Unit:
				todo.append([u, "hire"])
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		var role: String = {"militia": "militia", "caravan": "caravan", "camp": "bandit", "bandit": "bandit", "deserter": "deserter"}.get(String(wb.get("kind", "")), "army")
		for u in wb.get("units", []):
			if u is Unit and not u.dead:
				todo.append([u, role])
	for x in todo:
		var u: Unit = x[0]
		if u.family < 0:
			continue
		var town: Dictionary = w["towns"].get(u.home_town, {})
		var f := fam_of(town, u.family)
		if f.is_empty() or not Persons.by_uid(f, u.uid).is_empty():
			continue
		var e := _e(town)
		Persons.sync(e, f, day)
		var p: Array = []
		for q in Persons.pp(f):
			if String(q[4]) == String(x[1]) and int(q[5]) < 0:
				p = q
				break
		if p.is_empty():
			var r := RandomNumberGenerator.new()
			r.seed = hash([u.uid, u.name])
			p = Persons.pick_home(f, r, true)
		if p.is_empty():
			continue
		Persons.bind_keep_name(e, f, p, u, String(x[1]), day)


## The company man's own person record (state "company", not in the row's counts): his name, his birth day.
static func _company_person(e: Dictionary, f: Dictionary, u: Unit, day: float) -> void:
	set_born(u, day)
	var r := RandomNumberGenerator.new()
	r.seed = hash([u.uid, u.name])
	var p := Persons._new(e, f, Persons.race_of(e), r.randi() % 2, u.born, 0, r)
	Persons.pp(f).append(p)
	Persons.bind_keep_name(e, f, p, u, "company", day)

static func _town_for(w: Dictionary, u: Unit) -> String:
	var start: String = w.get("start_town", "")
	var best := ""
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if (Persons.race_of(t["econ"]) if TownEcon.has_econ(t) else String(DB.factions.get(t["faction"], {}).get("race", ""))) == u.race:
			if best == "" or tid == start:
				best = tid
	return best if best != "" else start

## Company wages use the existing household wage destination and inheritance rules.
## Returns only accepted remittances; Game keeps rejected coins and marks that day unpaid.
static func pay_company(game, paid_list: Array) -> float:
	var w: Dictionary = game.world
	var paid := 0.0
	for p in paid_list:
		var u: Unit = p[0]
		var amount := float(p[1])
		var town: Dictionary = w.get("towns", {}).get(u.home_town, {})
		var e := _e(town)
		var f := fam_of(town, u.family)
		if amount <= 0.0 or e.is_empty() or f.is_empty():
			continue
		var target := WageClaims._recipient(e, f)
		if target.is_empty():
			continue
		target[0][target[1]] = float(target[0].get(target[1], 0.0)) + amount
		paid += amount
	TownEcon.gold_out(-paid)   # accepted company money entering the town economy
	return paid

# ================================================================== militia
## The town treasury pays its militia (a city's guard) by rank into their family purses, once a day:
## economy spec 2, campaign/army.gd Army.pay_town. Returns the gold-worth paid.
static func pay_militia(game, town: Dictionary) -> float:
	return Army.pay_town(game, town)

# ================================================================== caravan crews
## The same trip allowance used when signing on. Caravan food retains the native home-food policy
## (Barge.household_eaters); it is bought by the households receiving these wages, not charged again to the purse.
static func crew_bill(n_guards: int, trip_days: float) -> float:
	return (float(n_guards) * GUARD_WAGE + float(DRIVERS) * CREW_WAGE) * maxf(4.0, trip_days)

## Crew wages for every caravan, from its owner (the home town's merchants: the market till) into the crew's
## family purses. Once a day.
static func pay_crews(game) -> void:
	var w: Dictionary = game.world
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		if wb.get("kind", "") != "caravan" or not wb.has("crew"):
			continue
		var town: Dictionary = w["towns"].get(wb.get("origin", ""), {})
		var e := _e(town)
		if e.is_empty():
			continue
		var mkt: Dictionary = e["biz"][int(e["mkt"])]
		var unpaid := false
		for c in wb["crew"]:
			var wage := float(c[2])
			if float(mkt["till"]) < wage:
				unpaid = true
				break
			var paid := pay(town, int(c[0]), wage)
			if paid > 0.0:
				mkt["till"] = float(mkt["till"]) - paid
				Caravans.receipt_add(wb, "crew", paid)
		wb["unpaid"] = int(wb.get("unpaid", 0)) + 1 if unpaid else 0

## A new caravan's crew: guards are the caravan's units (named people of the town's families), plus drivers.
## Returns false (and releases everyone) when the owner cannot pay them for the trip or the town cannot spare them.
static func hire_crew(game, town: Dictionary, wb: Dictionary, rng: RandomNumberGenerator, trip_days: float) -> bool:
	var e := _e(town)
	if e.is_empty():
		return true
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	var n_guards := (wb["units"] as Array).size()
	var bill := crew_bill(n_guards, trip_days)
	if float(mkt["till"]) < bill:
		return false   # the owner can't pay: no crew signs on, the caravan doesn't sail
	var crew := []
	for u in wb["units"]:
		var fid := draw(town, rng, "caravan")
		if fid < 0:
			break
		bind(town, fid, u, "caravan")   # the guard IS the register person drawn
		crew.append([fid, "guard", GUARD_WAGE, u.uid])
	for i in DRIVERS:
		var fid2 := draw(town, rng, "caravan")
		if fid2 >= 0:
			crew.append([fid2, "driver", CREW_WAGE, -1])   # drivers and porters: register persons without a unit
	if crew.filter(func(c): return c[1] == "guard").size() < n_guards:
		for c in crew:
			release(town, int(c[0]), "caravan", int(c[3]))
		return false
	wb["crew"] = crew
	return true

## A guard of a caravan still on the road fell (e.g. beside the company): his family loses him, the crew
## list forgets him.
static func crew_casualty(game, wb: Dictionary, u: Unit) -> void:
	casualty(game, u, "dead", "caravan")
	var crew: Array = wb.get("crew", [])
	for i in crew.size():
		if int(crew[i][0]) == u.family and crew[i][1] == "guard":
			crew.remove_at(i)
			return

## The caravan is off the map: the living crew go home; dead guards count as casualties.
static func end_crew(game, wb: Dictionary, dead_guards: Array = []) -> void:
	var town: Dictionary = game.world.get("towns", {}).get(wb.get("origin", ""), {})
	var dead_ids := {}
	for u in dead_guards:
		casualty(game, u, "dead", "caravan")
		dead_ids[u.family] = int(dead_ids.get(u.family, 0)) + 1
	for c in wb.get("crew", []):
		var fid := int(c[0])
		if int(dead_ids.get(fid, 0)) > 0 and c[1] == "guard":
			dead_ids[fid] = int(dead_ids[fid]) - 1
			continue
		release(town, fid, "caravan", int(c[3]) if c.size() > 3 else -1)
	wb["crew"] = []

static func free_volunteer(e: Dictionary, f: Dictionary, rng: RandomNumberGenerator) -> Array:
	var jobs := Persons.work(e, f)
	var candidates := []
	for p in Persons.pp(f):
		if int(p[6]) == 0 and String(p[4]) == "" and int(p[5]) < 0 and not jobs.get(int(p[0]), {}).get("keeper", false): candidates.append(p)
	return [] if candidates.is_empty() else candidates[rng.randi_range(0, candidates.size() - 1)]
