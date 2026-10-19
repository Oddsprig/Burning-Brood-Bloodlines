class_name Persons
extends RefCounted
## The register's people (Douglas: "the recruits are using fake people in town"; "ages and kinship come from real
## births, marriages and deaths"). Every family keeps a persistent record for each member: adults and elders in
## f.pp, children in f.kp. The family-row counts (m, f, old, kids) stay the economy's numbers and follow the records:
##   - a child is born to a mother of fertile age (race data: ages.mother_max) and her husband (birth());
##   - children come of age, adults grow old and elders past the race's lifespan die by their birth days (age_up(),
##     weekly in the family turn); the weekly roll still lets an elder die before that (the oldest first);
##   - unmarried grown-ups marry across families of the town now and then (marriages(), the town turn): the bride
##     moves into her husband's house and takes his name;
##   - every named person in a force or a recruit pool IS one of these records (state, unit uid);
##   - work(): who in the family holds which of its real places (own land and herds, jobs, casual work) and the wage
##     that place pays; household() the register in family order with kinship, age, work and wage.
##
## person = [pid, first-name index, sex (0 m / 1 f), birth day, state, unit uid (-1 none), kind (0 adult / 1 elder /
##   2 child), own name ("" = given name + family name), spouse pid, mother pid, father pid, job, history]
## (-1 = none or unknown). The first-name index points into data person_names[race][m|f]. Older saves' records keep
## the name they had (written into the own-name field on load). Compact arrays (JSON-friendly).
## states:
##   ""         at home (working the family's land and jobs)
##   "hire"     in the town's recruit pool (for hire at the tavern)
##   "company"  hired by the player's company (left the family row's counts; the family keeps his record)
##   "militia", "caravan", "army", "bandit", "deserter"  in service (counted in the row and in f.serve)

const AWAY := ["company", "captive"]   # states not counted in the family row (v0.033: a captive is held away, not at home)
const SERVICE_WORDS := {"reserve": "militia reserve, working at home", "guard": "a professional town guard", "": "at home", "hire": "for hire at the tavern", "company": "with your company", "militia": "in the militia",
	"caravan": "with a caravan", "army": "with the army", "bandit": "with an outlaw band", "deserter": "a deserter"}
const SP := 8
const MO := 9
const FA := 10
const JOB := 11
const HIST := 12
const SIZE := 13
## v0.014: legendary pieces he has made in his life (an optional 14th field, appended by Legends.forge; read with
## g(p, LEG, 0)). At most Legends.CAP.
const LEG := 13
const SERVICE_MEMORY := 14
## Bloodlines identities supplement town-local PIDs and economic household rows.
## Initial house affiliation survives marriage/migration; v0.001 newborns use the
## current birth household's founding lineage, pending later membership laws.
const PERSON_UID := 15
const HOUSE_UID := 16
const SPOUSE_UID := 17
const MOTHER_UID := 18
const FATHER_UID := 19

static func _identity_pad(p: Array) -> void:
	while p.size() <= FATHER_UID:
		var field := p.size()
		if field >= PERSON_UID or field == JOB: p.append("")
		elif field == HIST: p.append([])
		elif field == SERVICE_MEMORY: p.append({})
		else: p.append(0)

static func identity(e: Dictionary, f: Dictionary, p: Array) -> void:
	if String(e.get("identity_scope", "")) == "" or f.get("estate", false): return
	Families.identity(e, f)
	_identity_pad(p)
	if str(p[PERSON_UID]) in ["", "0"]:
		p[PERSON_UID] = "person:%s:%d" % [e["identity_scope"], int(p[0])]
	if str(p[HOUSE_UID]) in ["", "0"]: p[HOUSE_UID] = f["founding_house_uid"]
	for field in [SPOUSE_UID, MOTHER_UID, FATHER_UID]:
		if str(p[field]) == "0": p[field] = ""

## Capture known local kin once alongside their native links. These stable links
## remain meaningful when migration renumbers PIDs or marriage changes household.
static func identity_kin(e: Dictionary, p: Array) -> void:
	if p.size() <= FATHER_UID: return
	for pair in [[SP, SPOUSE_UID], [MO, MOTHER_UID], [FA, FATHER_UID]]:
		var pid := int(g(p, pair[0], -1))
		if pid < 0 or str(p[pair[1]]) not in ["", "0"]: continue
		for family in e.get("fams", []):
			var kin := by_pid(family, pid)
			if not kin.is_empty() and str(g(kin, PERSON_UID, "")) not in ["", "0"]:
				p[pair[1]] = str(kin[PERSON_UID])
				break

static func remember_unpaid(p: Array, role: String, days: float, day: float, served_days: float = -1) -> void:
	while p.size() <= SERVICE_MEMORY: p.append(0)
	if not p[SERVICE_MEMORY] is Dictionary: p[SERVICE_MEMORY] = {}
	p[SERVICE_MEMORY][role] = {"days": days, "returned": day, "served_days": maxf(days, served_days)}
	log_life(p, day, "unpaid", role)

static func unpaid_memory(p: Array, role: String) -> Dictionary:
	var memory: Variant = g(p, SERVICE_MEMORY, {})
	return memory.get(role, {}) if memory is Dictionary else {}

static func pp(f: Dictionary) -> Array:
	if not f.has("pp"):
		f["pp"] = []
	return f["pp"]

## The children's records (born here, not yet of age).
static func kp(f: Dictionary) -> Array:
	if not f.has("kp"):
		f["kp"] = []
	return f["kp"]

static func g(p: Array, i: int, d: Variant) -> Variant:
	return p[i] if p.size() > i else d

## Older saves' given names (one mixed list per race): only to keep the names records already had.
static func firsts(race: String) -> Array:
	return DB.names.get(race, DB.names.get("human", {})).get("first", ["Ann"])

## Given names for a race and sex (data person_names).
## v0.012: humans of every culture share one list (person_names.human, then the human cultures' own lists joined in
## HUMAN_CULTURE_NAMES order), so a person's name index means the same name in any human town he moves to.
const HUMAN_CULTURE_NAMES := ["eastern"]
static var _joined := {}
static func names_for(race: String, sex: int) -> Array:
	var N: Dictionary = TownEcon.data().get("person_names", {})
	var key := race
	if not N.has(key):
		key = "elf" if race.ends_with("_elf") else "human"
	var sk := "f" if sex == 1 else "m"
	if key == "human":
		if not _joined.has(sk):
			var all: Array = (N.get("human", {}).get(sk, []) as Array).duplicate()
			for c in HUMAN_CULTURE_NAMES:
				all.append_array(N.get(c, {}).get(sk, []))
			_joined[sk] = all
		var jl: Array = _joined[sk]
		return jl if not jl.is_empty() else firsts(race)
	var row: Dictionary = N.get(key, N.get("human", {}))
	var l: Array = row.get(sk, [])
	return l if not l.is_empty() else firsts(race)

## [from, to) of names_for(race, sex) a baby of this family takes its name from: a human family of a culture with its
## own list (its own culture f.cul, else the town's) draws from that part, the other humans from the plain human list.
static func name_range(e: Dictionary, f: Dictionary, race: String, sex: int) -> Array:
	var all := names_for(race, sex)
	if race != "human":
		return [0, all.size()]
	var N: Dictionary = TownEcon.data().get("person_names", {})
	var sk := "f" if sex == 1 else "m"
	var cul := String(f.get("cul", e.get("culture", "middle")))
	var at := (N.get("human", {}).get(sk, []) as Array).size()
	if not HUMAN_CULTURE_NAMES.has(cul):
		return [0, maxi(1, mini(at, all.size()))]
	for c in HUMAN_CULTURE_NAMES:
		var n := (N.get(c, {}).get(sk, []) as Array).size()
		if c == cul and n > 0:
			return [at, at + n]
		at += n
	return [0, all.size()]

static func first_of(e: Dictionary, p: Array) -> String:
	var own := String(g(p, 7, ""))
	if own != "":
		return own.split(" ")[0]
	var fl := names_for(race_of(e), int(p[2]))
	return String(fl[int(p[1]) % fl.size()])

static func name_of(f: Dictionary, p: Array, race: String) -> String:
	var own := String(g(p, 7, ""))
	if own != "":
		return own
	var fl := names_for(race, int(p[2]))
	return "%s %s" % [fl[int(p[1]) % fl.size()], f["name"]]

static func age_of(p: Array, day: float) -> int:
	return maxi(0, int(floor((day - float(p[3])) / People.year_days())))

static func race_of(e: Dictionary) -> String:
	return String(TownEcon.culture_of(e)["race"])

static func by_pid(f: Dictionary, pid: int) -> Array:
	if pid < 0:
		return []
	for p in pp(f):
		if int(p[0]) == pid:
			return p
	for p in kp(f):
		if int(p[0]) == pid:
			return p
	return []

## Older records (before kinship): pad to the full size; their given name is kept as their own name.
static func upgrade(e: Dictionary, f: Dictionary) -> void:
	var race := race_of(e)
	for p in pp(f):
		if p.size() >= SIZE:
			continue
		if p.size() <= 7 or String(p[7]) == "":
			var fl := firsts(race)
			var nm := "%s %s" % [fl[int(p[1]) % fl.size()], f["name"]]
			while p.size() < 8:
				p.append("")
			p[7] = nm
		while p.size() < SIZE:
			p.append([] if p.size() == HIST else ("" if p.size() == JOB else -1))

# ================================================================== a household made at world gen
## The family's people from its row: a couple of plausible ages, their children born when the mother was of
## fertile age, grown sons and daughters (or the head's brothers and sisters), the head's parents as the elders.
static func generate(e: Dictionary, f: Dictionary, day: float) -> void:
	if f.get("estate", false) or f.get("gone", false) or Population.is_cohort(f):
		return
	var race := race_of(e)
	var ab := People.ages(race)
	var A := float(ab["adult"]); var E := float(ab["elder"]); var L := float(ab["lifespan"])
	var M := float(ab.get("mother_max", E - 10.0))
	var yd := People.year_days()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f.get("seed", 0)), "household"])
	var a := pp(f); a.clear()
	var k := kp(f); k.clear()
	var men := int(f["m"]); var women := int(f["f"]); var kids := int(f["kids"]); var old := int(f["old"])
	var extra := maxi(0, men - 1) + maxi(0, women - 1)
	# the mother's age bounds: her children (kids under age, grown ones over it) were born while she was fertile
	var w_hi := minf(E - 1.0, L - A - 1.0)
	if kids > 0:
		w_hi = minf(w_hi, M + A - 1.0)
	var grown := extra > 0 and rng.randf() < 0.75 and 2.0 * A <= w_hi
	var w_lo := 2.0 * A if grown else A
	var ref := _rand(rng, w_lo, w_hi)   # the mother's age (or the lone parent's)
	var wife: Array = []; var hus: Array = []
	if women > 0:
		wife = _new(e, f, race, 1, day - ref * yd, 0, rng)
		a.append(wife)   # listed at once: the next given name avoids it
	if men > 0:
		var h_age := clampf(ref + rng.randf_range(0.0, 8.0), A, minf(E - 1.0, L - A - 1.0))
		if women == 0:
			h_age = ref
		hus = _new(e, f, race, 0, day - h_age * yd, 0, rng)
		a.append(hus)
	if not hus.is_empty() and not wife.is_empty():
		hus[SP] = int(wife[0]); wife[SP] = int(hus[0])
	var head: Array = hus if not hus.is_empty() else wife
	# elders: the head's parents (born when they were of age to have him)
	var olds := []
	if old > 0:
		var h_age2: float = (day - float(head[3])) / yd if not head.is_empty() else _rand(rng, A, E - 1.0)
		for i in old:
			var sex := rng.randi() % 2 if i == 0 else 1 - int(olds[0][2])
			var lo := maxf(E, h_age2 + A)
			var hi := minf(L - 1.0, h_age2 + (M - 8.0 if sex == 1 else E))
			var p := _new(e, f, race, sex, day - _rand(rng, lo, maxf(lo, hi)) * yd, 1, rng)
			olds.append(p)
			a.append(p)
		if olds.size() >= 2:
			olds[0][SP] = int(olds[1][0]); olds[1][SP] = int(olds[0][0])
		if not head.is_empty():
			for p in olds.slice(0, 2):
				head[MO if int(p[2]) == 1 else FA] = int(p[0])
	# family order: the elders, then the couple
	a.clear()
	a.append_array(olds)
	if not hus.is_empty():
		a.append(hus)
	if not wife.is_empty():
		a.append(wife)
	# the other adults: grown sons and daughters of the couple, else the head's brothers and sisters
	var mother: Array = wife
	var father: Array = hus
	var m_age: float = ref
	for i in extra:
		var sex := 0 if i < maxi(0, men - 1) else 1
		var p: Array
		if grown:
			var lo := maxf(A, m_age - M)
			p = _new(e, f, race, sex, day - _rand(rng, lo, maxf(lo, m_age - A)) * yd, 0, rng)
			p[MO] = int(mother[0]) if not mother.is_empty() else -1
			p[FA] = int(father[0]) if not father.is_empty() else -1
		else:
			var hh: float = (day - float(head[3])) / yd if not head.is_empty() else A + 5.0
			p = _new(e, f, race, sex, day - clampf(hh - rng.randf_range(0.0, 8.0), A, E - 1.0) * yd, 0, rng)
			if not head.is_empty():
				p[MO] = head[MO]; p[FA] = head[FA]
		a.append(p)
	# children under age, born to the mother while she was fertile (oldest first)
	var ages := []
	var k_lo := maxf(0.0, m_age - M) if not mother.is_empty() or not father.is_empty() else 0.0
	var k_hi := minf(A - 0.2, m_age - A) if not mother.is_empty() or not father.is_empty() else A - 0.2
	for i in kids:
		ages.append(_rand(rng, k_lo, maxf(k_lo, k_hi)))
	ages.sort()
	ages.reverse()
	for ag in ages:
		var p := _new(e, f, race, rng.randi() % 2, day - float(ag) * yd, 2, rng)
		p[MO] = int(mother[0]) if not mother.is_empty() else -1
		p[FA] = int(father[0]) if not father.is_empty() else -1
		k.append(p)
	for p in a + k: identity_kin(e, p)

static func _rand(rng: RandomNumberGenerator, lo: float, hi: float) -> float:
	return lo if hi <= lo else rng.randf_range(lo, hi)

# ================================================================== the records follow the row
## Brings the person records in line with the row's counts (men, women, elders, children) where other code moved
## the counts (deaths in service, people leaving, older saves): adults who aged become elders (the oldest at home),
## children of the wanted sex come of age, surplus records at home leave, missing people get a record (a child
## born to a mother of the family when there is one). Named people in service are never dropped here.
static func sync(e: Dictionary, f: Dictionary, day: float) -> void:
	if Population.is_cohort(f): return
	if f.get("estate", false):
		return
	var a: Array = pp(f)
	if f.get("gone", false):
		return
	if not a.is_empty() and (a[0] as Array).size() < SIZE:
		upgrade(e, f)
	var k: Array = kp(f)
	var race := race_of(e)
	var ab := People.ages(race)
	var yd := People.year_days()
	var want := [int(f["m"]), int(f["f"]), int(f["old"]), int(f["kids"])]
	var have := [0, 0, 0, k.size()]
	for p in a:
		if AWAY.has(String(p[4])):
			continue
		have[_cat(p)] += 1
	# adults grown old: the oldest adult at home becomes an elder
	while have[2] < want[2] and (have[0] > want[0] or have[1] > want[1]):
		var best: Array = []
		for p in a:
			if int(p[6]) == 0 and String(p[4]) == "" and have[int(p[2])] > want[int(p[2])] and (best.is_empty() or float(p[3]) < float(best[3])):
				best = p
		if best.is_empty():
			break
		have[int(best[2])] -= 1
		best[6] = 1
		have[2] += 1
	# children come of age: the oldest child of the sex the row is missing
	while have[3] > want[3]:
		var kid: Array = []
		for p in k:
			if have[int(p[2])] < want[int(p[2])] and (kid.is_empty() or float(p[3]) < float(kid[3])):
				kid = p
		if kid.is_empty():
			break
		k.erase(kid)
		kid[6] = 0
		a.append(kid)
		f.erase("nxa")
		have[3] -= 1
		have[int(kid[2])] += 1
	# surplus records at home leave (the row counted them out already)
	for c in 3:
		var i := a.size() - 1
		while have[c] > want[c] and i >= 0:
			var p: Array = a[i]
			if _cat(p) == c and String(p[4]) == "":
				forget(e, f, p)
				a.remove_at(i)
				have[c] -= 1
			i -= 1
	while have[3] > want[3] and not k.is_empty():   # children who left: the oldest went
		var old_k: Array = k[0]
		for p in k:
			if float(p[3]) < float(old_k[3]):
				old_k = p
		forget(e, f, old_k)
		k.erase(old_k)
		have[3] -= 1
	# missing records: an elder or adult nobody named yet (older saves, arrivals), a child born
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f.get("seed", 0)), int(day), a.size(), k.size(), "pp"])
	for c in 3:
		while have[c] < want[c]:
			var sex := c if c < 2 else rng.randi() % 2
			var age := rng.randf_range(float(ab["adult"]), float(ab["elder"]) - 1.0) if c < 2 else rng.randf_range(float(ab["elder"]), float(ab["lifespan"]) - 1.0)
			a.append(_new(e, f, race, sex, day - age * yd, 1 if c == 2 else 0, rng))
			f.erase("nxa")
			have[c] += 1
	while have[3] < want[3]:
		var mo := mother_for(e, f, day)
		var p := _new(e, f, race, rng.randi() % 2, day - (0.0 if not mo.is_empty() else rng.randf() * float(ab["adult"]) * 0.8) * yd, 2, rng)
		if not mo.is_empty():
			p[MO] = int(mo[0]); p[FA] = int(mo[SP])
		k.append(p)
		f.erase("nxa")
		have[3] += 1
	for p in a + k: identity_kin(e, p)

static func _cat(p: Array) -> int:
	return 2 if int(p[6]) == 1 else int(p[2])

## Records at home (state "") in a category: 0 men, 1 women, 2 elders.
static func home_n(f: Dictionary, cat: int) -> int:
	var n := Population.anonymous(f, cat)
	for p in pp(f):
		if String(p[4]) == "" and _cat(p) == cat:
			n += 1
	return n

## The row may lose someone of this category (0 men, 1 women, 2 elders): the row has one and (when the family
## keeps records) one of them is at home, not in service or for hire.
static func can_lose(f: Dictionary, cat: int) -> bool:
	var row := int(f[["m", "f", "old"][cat]])
	if row <= 0:
		return false
	return not f.has("pp") or home_n(f, cat) > 0

## A new person: pid, a given name for the sex that nobody of this surname in the town has, the birth day.
static func _new(e: Dictionary, f: Dictionary, race: String, sex: int, born: float, kind: int, rng: RandomNumberGenerator) -> Array:
	var pid := int(e.get("next_pid", 1))
	e["next_pid"] = pid + 1
	var fl := names_for(race, sex)
	var taken := {}
	for gf in e["fams"]:   # no two people of one surname in a town share a given name (two houses may share a surname)
		if String(gf.get("name", "")) == String(f["name"]):
			for p in gf.get("pp", []):
				if int(p[2]) == sex:
					taken[int(p[1])] = true
			for p in gf.get("kp", []):
				if int(p[2]) == sex:
					taken[int(p[1])] = true
	var rg := name_range(e, f, race, sex)   # v0.012: the family's culture's part of the list
	var lo := int(rg[0]); var span := maxi(1, int(rg[1]) - lo)
	var fi := lo + rng.randi() % span
	for _t in span:
		if not taken.has(fi):
			break
		fi = lo + (fi - lo + 1) % span
	if taken.has(fi):   # every name is taken in the clan (orc and goblin towns): at least not one of this house's
		var home := {}
		for p in pp(f) + kp(f):
			if int(p[2]) == sex:
				home[int(p[1])] = true
		for _t in span:
			if not home.has(fi):
				break
			fi = lo + (fi - lo + 1) % span
	var p := [pid, fi, sex, int(round(born)), "", -1, kind, "", -1, -1, -1, "", []]
	identity(e, f, p)
	return p

# ================================================================== births, ageing, deaths, marriages
## A married woman of the family at home, of an age to bear a child (race ages: adult .. mother_max), whose husband
## is alive. [] when there is none.
static func mother_for(e: Dictionary, f: Dictionary, day: float) -> Array:
	var ab := People.ages(race_of(e))
	var lo := float(ab["adult"]); var hi := float(ab.get("mother_max", float(ab["elder"]) - 10.0))
	var yd := People.year_days()
	for p in pp(f):
		if int(p[2]) != 1 or int(p[6]) != 0 or not (String(p[4]) in ["", "hire", "militia"]):
			continue
		var age := (day - float(p[3])) / yd
		if age < lo or age >= hi:
			continue
		var h := by_pid(f, int(g(p, SP, -1)))
		if not h.is_empty() and String(h[4]) != "company":
			return p
	return []

## A child is born to this mother and her husband today (father: the husband who fathered it, when known; -2 = her
## husband now). Returns the child's record.
static func birth(e: Dictionary, f: Dictionary, mother: Array, day: float, father: int = -2, nth: int = 0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f.get("seed", 0)), int(day), int(mother[0]), "born"]) if nth == 0 else hash([int(f.get("seed", 0)), int(day), int(mother[0]), "born", nth])
	var p := _new(e, f, race_of(e), rng.randi() % 2, day, 2, rng)
	p[MO] = int(mother[0]); p[FA] = int(g(mother, SP, -1)) if father == -2 else father
	kp(f).append(p)
	identity_kin(e, p)
	var maternal_house := Dynasty.birth_house(e, f, mother)
	if maternal_house != "": p[HOUSE_UID] = maternal_house
	Dynasty.record_person(e, f, p, true)
	return p

# ---------------------------------------------------------------- childbearing (Douglas: "a natural birthrate")
## Where a woman or her husband must be for a child to be conceived: at home in the town (for hire at the tavern and the
## town militia sleep at home); in the company, the army, a caravan or an outlaw band they are away.
const AT_HOME := ["", "hire", "militia", "reserve"]

## The race's childbearing in its own years: [gestation (years carrying), nurse (years a nursing mother does not
## conceive after a birth), conceive (mean years to conceive once she can)]. One rule for every race, read from its
## ages (data "bearing", the human numbers for a human's fertile years): a woman of any race has about as many
## children in her fertile years (adult .. mother_max), so her birth interval is the human one x her fertile years /
## the human's; she carries the child the human time x her race's pace of growing up (adult / the human adult); the
## nursing years follow the fertile years; the wait to conceive is the rest of the interval.
static func bearing(race: String) -> Array:
	var ab := People.ages(race)
	var Bd: Dictionary = TownEcon.data().get("bearing", {})
	var own: Dictionary = Bd.get("races", {}).get(race, {})
	if own.has("gestation"):   # a race with its own body (data bearing.races: orcs, goblins)
		return [float(own["gestation"]), float(own["nurse"]), float(own["conceive"])]
	var span := float(ab.get("mother_max", float(ab["elder"]) - 10.0)) - float(ab["adult"])
	var ks := span / float(Bd.get("span", 29.0))
	var gest := float(Bd.get("gestation", 0.75)) * float(ab["adult"]) / float(Bd.get("adult", 16.0))
	var nurse := float(Bd.get("nurse", 1.5)) * ks
	var interval := (float(Bd.get("gestation", 0.75)) + float(Bd.get("nurse", 1.5)) + float(Bd.get("conceive", 0.5))) * ks
	return [gest, nurse, maxf(0.05 * ks, interval - gest - nurse)]

## How many children a birth brings: the race's litter (data bearing.races[race].litter, else bearing.litter: the
## chance of 1, 2, 3 ... children), rolled on the mother and the day.
static func litter(race: String, rng: RandomNumberGenerator) -> int:
	var Bd: Dictionary = TownEcon.data().get("bearing", {})
	var L: Array = Bd.get("races", {}).get(race, {}).get("litter", Bd.get("litter", [1.0]))
	var r := rng.randf()
	for i in L.size():
		r -= float(L[i])
		if r < 0.0:
			return i + 1
	return 1

## f.preg = [[mother pid, due day, father pid], ...]: the family's women with child.
static func preg_of(f: Dictionary, pid: int) -> int:
	var pr: Array = f.get("preg", [])
	for i in pr.size():
		if int(pr[i][0]) == pid:
			return i
	return -1

## Can this woman conceive today? A married woman of the family at home, her husband at home, of an age to bear the
## child before mother_max, not with child, not nursing (her youngest child older than the race's nurse years).
static func can_conceive(f: Dictionary, p: Array, day: float, ab: Dictionary, bear: Array, yd: float) -> bool:
	if int(p[2]) != 1 or int(p[6]) != 0 or not (String(p[4]) in AT_HOME):
		return false
	var age := (day - float(p[3])) / yd
	if age < float(ab["adult"]) or age + float(bear[0]) > float(ab.get("mother_max", float(ab["elder"]) - 10.0)):
		return false
	var h := by_pid(f, int(g(p, SP, -1)))
	if h.is_empty() or not (String(h[4]) in AT_HOME):
		return false
	if preg_of(f, int(p[0])) >= 0:
		return false
	var pid := int(p[0])
	var nurse := float(bear[1]) * yd
	for k in kp(f):
		if int(k[MO]) == pid and day - float(k[3]) < nurse:
			return false
	return true

## Weekly (the family turn, `days` since the last): children due are born (the mother still of the family), then each
## woman who can conceive does so with the chance of her race's conceive years over these days, the family not
## hungry (no child is conceived while the family goes short: the old rule). Returns the children born.
static func childbearing(e: Dictionary, f: Dictionary, day: float, days: float, hungry: bool) -> Array:
	var born := []
	var pr: Array = f.get("preg", [])
	if not pr.is_empty():
		var i := pr.size() - 1
		while i >= 0:
			var x: Array = pr[i]
			if float(x[1]) <= day:
				pr.remove_at(i)
				var mo := by_pid(f, int(x[0]))
				if not mo.is_empty():
					var lr := RandomNumberGenerator.new()
					lr.seed = hash([int(f.get("seed", 0)), int(day), int(mo[0]), "litter"])
					for k in litter(race_of(e), lr):   # twins, triplets: the race's litter
						born.append(birth(e, f, mo, day, int(x[2]), k))
			i -= 1
		if pr.is_empty():
			f.erase("preg")
	if hungry or int(f["f"]) <= 0 or int(f["m"]) <= 0:
		return born
	var race := race_of(e)
	var ab := People.ages(race)
	var bear := bearing(race)
	var yd := People.year_days()
	var chance := 1.0 - exp(-days / maxf(0.01, float(bear[2]) * yd))
	var rng: RandomNumberGenerator = null
	for p in pp(f):
		if not can_conceive(f, p, day, ab, bear, yd):
			continue
		var sc := Sickness.case_of(f, int(p[0]))
		if not sc.is_empty() and Sickness.sick_phase(sc, day):
			continue   # a woman lying sick does not conceive (v0.011)
		if rng == null:
			rng = RandomNumberGenerator.new()
			rng.seed = hash([int(f.get("seed", 0)), int(day), "conceive"])
		if rng.randf() < chance:
			if not f.has("preg"):
				f["preg"] = []
			# conceived on a day of the week just gone; carried for the race's gestation
			f["preg"].append([int(p[0]), floorf(day - rng.randf() * days + float(bear[0]) * yd), int(g(p, SP, -1))])
	return born

## The child is born: its mother dies in childbirth with the chance data bearing.maternal per birth (every race,
## [ours] 1%, see the data note), through the one death path (Sickness.kill: her record, the row, the census once,
## cause "childbirth"); the child lives. Deaths of the newborn are sickness's (its child band). Returns true when she died.
static func childbed(game, t: Dictionary, e: Dictionary, f: Dictionary, kid: Array, day: float) -> bool:
	if kid.is_empty():
		return false
	var mo := by_pid(f, int(kid[MO]))
	if mo.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f.get("seed", 0)), int(day), int(mo[0]), "childbed"])
	if rng.randf() >= float(TownEcon.data().get("bearing", {}).get("maternal", 0.0)):
		return false
	Sickness.kill(game, t, f, mo, day, "childbirth", "childbirth")
	return true

## World gen: the women who would be with child on the first day (the steady share of a married woman's years that
## she is carrying: gestation / (gestation + conceive), among those not nursing), due within the gestation.
static func gen_preg(e: Dictionary, f: Dictionary, day: float) -> void:
	var race := race_of(e)
	var ab := People.ages(race)
	var bear := bearing(race)
	var yd := People.year_days()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(f.get("seed", 0)), "preg"])
	var share := float(bear[0]) / maxf(0.01, float(bear[0]) + float(bear[2]))
	for p in pp(f):
		if can_conceive(f, p, day, ab, bear, yd) and rng.randf() < share:
			if not f.has("preg"):
				f["preg"] = []
			f["preg"].append([int(p[0]), floorf(day + 1.0 + rng.randf() * float(bear[0]) * yd), int(g(p, SP, -1))])

## Private physical reserves live at home. Accept only their exact saved holder;
## public service/absent/forged UID records keep the inherited aging policy.
static func _private_home_reserve(e: Dictionary, f: Dictionary, p: Array) -> Unit:
	if String(p[4]) != "reserve" or int(p[5]) < 0: return null
	var uid: int = int(p[5])
	if not (f.get("player_reserve_uids", {}) as Dictionary).has(str(uid)): return null
	var u: Unit = Mobilization.reserve_unit(Game, uid, "", int(f.get("id", -1)))
	if u == null or u.dead: return null
	var town: Dictionary = Game.world.get("towns", {}).get(u.home_town, {})
	if not is_same(People.fam_of(town, u.family), f) or not is_same(by_uid(f, uid), p): return null
	if not e.is_empty() and not is_same(town.get("econ", {}), e): return null
	return u if ServiceIdentity.unit_person(town.get("econ", {}), f, p, u) else null

## Weekly (the family turn): children who reached the age of adulthood join the adults, adults at home past the
## elder age become elders (they stop working), elders at home past the lifespan die. The row follows.
## Returns true when anything changed.
static func age_up(e: Dictionary, f: Dictionary, day: float) -> bool:
	if not f.has("pp"):
		return false
	if day < float(f.get("nxa", -1.0)):
		return false   # nobody reaches an age threshold before f.nxa (the soonest, worked out last time)
	var ab := People.ages(race_of(e))
	var yd := People.year_days()
	var A := float(ab["adult"]) * yd; var E := float(ab["elder"]) * yd; var L := float(ab["lifespan"]) * yd
	var changed := false
	var nxt := INF
	var k := kp(f)
	var i := 0
	while i < k.size():
		var kid: Array = k[i]
		if day - float(kid[3]) >= A:
			k.remove_at(i)
			kid[6] = 0
			pp(f).append(kid)
			f["kids"] = maxi(0, int(f["kids"]) - 1)
			var s: String = ["m", "f"][int(kid[2])]
			f[s] = int(f[s]) + 1
			e["adults"] = int(e["adults"]) + 1
			changed = true
			continue
		nxt = minf(nxt, float(kid[3]) + A)
		i += 1
	var a := pp(f)
	i = a.size() - 1
	while i >= 0:
		var p: Array = a[i]
		i -= 1
		var age := day - float(p[3])
		var home: bool = String(p[4]) == "" or _private_home_reserve(e, f, p) != null
		if int(p[6]) == 0:
			if home and age >= E:
				var s2: String = ["m", "f"][int(p[2])]
				if int(f[s2]) > 0:
					f[s2] = int(f[s2]) - 1
					f["old"] = int(f["old"]) + 1
					e["adults"] = int(e["adults"]) - 1
					p[6] = 1
					changed = true
			nxt = minf(nxt, float(p[3]) + (E if int(p[6]) == 0 else L))
		elif int(p[6]) == 1:
			if home and age >= L and int(f["old"]) > 0:
				die_elder(e, f, p, day)
				changed = true
			else:
				nxt = minf(nxt, float(p[3]) + L)
	# someone away past a threshold is looked at again next week
	f["nxa"] = maxf(nxt, day + 1.0) if nxt < INF else day + 365.0
	return changed


## The elder dies at home: his record and his row count go, the family remembers.
static func die_elder(e: Dictionary, f: Dictionary, p: Array, day: float) -> void:
	var reserve: Unit = _private_home_reserve(e, f, p)
	if reserve != null:
		reserve.dead = true
		Mobilization.natural_death(Game, reserve) # settle physical loans/estate BEFORE census ID retirement
	Census.person_died(e, f, p, day, "old age", "", int(f["old"]) > 0)   # the census: one death, one cause
	forget(e, f, p)
	drop_im(f, int(p[0]))
	pp(f).erase(p)
	f["old"] = maxi(0, int(f["old"]) - 1)
	e["pop"] = int(e["pop"]) - 1
	e["stats"]["deaths"] = int(e["stats"].get("deaths", 0)) + 1
	Families.event(f, "elder", [name_of(f, p, race_of(e))], day)
	if f.get("named", false):
		Families.add_hist(f, "%s, an elder of the family, died." % name_of(f, p, race_of(e)), day)

## The oldest elder at home ([] when none).
static func oldest_elder(f: Dictionary) -> Array:
	var best: Array = []
	for p in pp(f):
		if int(p[6]) == 1 and (String(p[4]) == "" or _private_home_reserve({}, f, p) != null) and (best.is_empty() or float(p[3]) < float(best[3])):
			best = p
	return best

## Now and then (the weekly town turn, once in four weeks per town): unmarried grown-ups at home marry across the
## town's families; the bride moves into her husband's house (the rows move with her) and takes his name.
## Every single the rules match marries (one bride from a house a call); `most` >= 0 caps the weddings of a call (the
## old cap of 2 a town in four weeks left most singles unwed: v0.011). Returns the number of weddings.
static func marriages(e: Dictionary, day: float, most: int = -1) -> int:
	var race := race_of(e)
	var ab := People.ages(race)
	var yd := People.year_days()
	var A := float(ab["adult"]); var M := float(ab.get("mother_max", float(ab["elder"]) - 10.0))
	var men := []; var women := []
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or not f.has("pp"):
			continue
		var is_house: bool = not f.get("cohort", false) and not f.get("estate", false) and not f.get("gone", false) and str(f.get("household_uid", "")) != ""
		# (v0.011: no "the house cannot spare her": a daughter or widow whose house would keep fewer than 2 grown-ups at
		# home stayed single, 30-60 women a year. She marries and moves to her husband's house; a house left with no
		# grown-up at work falls to the hardship rules like any other: casual work, the poorhouse, the coping ladder.)
		for p in f["pp"]:
			# A promoted noble retains his Unit's full-name override and local
			# militia/reserve service. Neither makes a resident groom absent.
			# Brides keep the existing eligibility/movement rules below.
			var home_groom: bool = is_house and int(p[2]) == 0 and String(p[4]) in AT_HOME
			if int(p[6]) != 0 or (String(p[4]) != "" and not home_groom) or (p as Array).size() < SIZE or (String(p[7]) != "" and not home_groom):
				continue
			if not by_pid(f, int(p[SP])).is_empty():
				continue
			if home_groom:
				var spouse_uid: String = str(g(p, SPOUSE_UID, ""))
				if spouse_uid != "" and not Dynasty._person(Game, spouse_uid).is_empty(): continue
			var age := (day - float(p[3])) / yd
			if int(p[2]) == 0 and age >= A + 2.0:
				men.append([f, p, age, is_house])
			elif int(p[2]) == 1 and age >= A and age < M - 5.0:
				women.append([f, p, age, is_house])
	if men.is_empty() or women.is_empty():
		return 0
	men.sort_custom(func(x, y): return int(x[1][0]) < int(y[1][0]))
	women.sort_custom(func(x, y): return int(x[1][0]) < int(y[1][0]))
	# house grooms choose first, so house brides meet house grooms before any commoner does
	var ordered_men := []
	for mm0 in men:
		if bool(mm0[3]):
			ordered_men.append(mm0)
	for mm0 in men:
		if not bool(mm0[3]):
			ordered_men.append(mm0)
	men = ordered_men
	var n := 0
	var used := {}
	var touched := {}
	var taken := {}   # surname -> {given-name index of its women}
	var by_age := {}   # women by whole year of age: a man looks only at brides 11 years younger to 5 older
	for ww in women:
		var k := int(ww[2])
		if not by_age.has(k):
			by_age[k] = []
		by_age[k].append(ww)
	for mm in men:
		if most >= 0 and n >= most:
			break
		var hf: Dictionary = mm[0]
		var hp: Array = mm[1]
		var groom_house: bool = bool(mm[3])
		var near := []
		for a in range(int(mm[2]) - 11, int(mm[2]) + 6):
			near.append_array(by_age.get(a, []))
		if groom_house:   # a house groom tries every house bride before any commoner
			var house_near := []
			var common_near := []
			for ww0 in near:
				if bool(ww0[3]):
					house_near.append(ww0)
				else:
					common_near.append(ww0)
			near = house_near + common_near
		for ww in near:
			var wf: Dictionary = ww[0]
			var wp: Array = ww[1]
			var bride_house: bool = bool(ww[3])
			# a house member may marry a commoner only once 2+ years past adult age with no house match
			if groom_house != bride_house and float(mm[2] if groom_house else ww[2]) < A + 2.0:
				continue
			if used.has(int(wp[0])) or touched.has(int(wf["id"])) or int(wf["id"]) == int(hf["id"]) or absf(float(mm[2]) - float(ww[2]) - 3.0) > 8.0:
				continue
			var sur := String(hf["name"])
			if String(wf["name"]) == sur:
				continue
			# a given name nobody of the husband's surname has
			if not taken.has(sur):
				var t := {}
				for gf in e["fams"]:
					if String(gf.get("name", "")) == sur:
						for q in gf.get("pp", []) + gf.get("kp", []):
							if int(q[2]) == 1:
								t[int(q[1])] = true
				taken[sur] = t
			if taken[sur].has(int(wp[1])) and (taken[sur] as Dictionary).size() < names_for(race, 1).size():
				continue   # (a clan that has used every name: only the house itself must not repeat one)
			var dup := false
			for q in pp(hf) + kp(hf):
				if int(q[2]) == 1 and int(q[1]) == int(wp[1]):
					dup = true
			if dup:
				continue
			taken[sur][int(wp[1])] = true
			touched[int(wf["id"])] = true   # her family has one woman fewer now: its other daughters wait
			var bride_was := name_of(wf, wp, race)
			forget(e, wf, wp)
			pp(wf).erase(wp)
			wf["f"] = int(wf["f"]) - 1
			hf["f"] = int(hf["f"]) + 1
			pp(hf).append(wp)
			var pi := preg_of(wf, int(wp[0]))   # a widow with child carries it into her new house
			if pi >= 0:
				if not hf.has("preg"):
					hf["preg"] = []
				hf["preg"].append(wf["preg"][pi])
				wf["preg"].remove_at(pi)
			Sickness.moved(e, wf, hf, int(wp[0]))   # sickness: her open case, immunity and condition move with her
			hf.erase("nxa")
			wp[SP] = int(hp[0]); hp[SP] = int(wp[0])
			if wp.size() > FATHER_UID and hp.size() > FATHER_UID:
				wp[SPOUSE_UID] = str(hp[PERSON_UID]); hp[SPOUSE_UID] = str(wp[PERSON_UID])
			Families.event(hf, "married", [name_of(hf, hp, race), bride_was], day)
			Families.event(wf, "wed_away", [bride_was, String(hf["name"])], day)
			if groom_house != bride_house:
				if groom_house:
					hf["prestige"] = float(hf.get("prestige", 0.0)) - 5.0
					Families.add_hist(hf, "%s married beneath the house." % name_of(hf, hp, race), day)
				else:
					wf["prestige"] = float(wf.get("prestige", 0.0)) - 5.0
					Families.add_hist(wf, "%s married beneath the house." % bride_was, day)
			Families.reassign(e, wf)
			Families.reassign(e, hf)
			used[int(wp[0])] = true
			n += 1
			break
	return n

# ================================================================== service
## A grown-up person at home for a role (recruit pool, service): rng picks among those at home, elders only when
## `elders` is true. Returns the person array or [].
static func pick_home(f: Dictionary, rng: RandomNumberGenerator, elders: bool = false) -> Array:
	var c := []
	for p in pp(f):
		if String(p[4]) == "" and int(p[5]) < 0 and (elders or int(p[6]) == 0):
			c.append(p)
	if c.is_empty():
		return []
	return c[rng.randi() % c.size()]

static func by_uid(f: Dictionary, uid: int) -> Array:
	for p in pp(f):
		if int(p[5]) == uid:
			return p
	return []

static func by_name(e: Dictionary, f: Dictionary, uname: String) -> Array:
	var race := race_of(e)
	for p in pp(f):
		if name_of(f, p, race) == uname:
			return p
	return []

## By name among the living (grown-ups, children) and the remembered dead (f.dp). [] when unknown.
static func by_name_any(e: Dictionary, f: Dictionary, uname: String) -> Array:
	var p := by_name(e, f, uname)
	if not p.is_empty():
		return p
	var race := race_of(e)
	for q in kp(f):
		if name_of(f, q, race) == uname:
			return q
	for q in f.get("dp", []):
		if String(q[7]) == uname:
			return q
	return []

## The Unit takes the person's identity: his name, his birth day (and age).
static func bind(e: Dictionary, f: Dictionary, p: Array, u: Unit, state: String, day: float) -> void:
	if String(p[4]) != state and state != "hire":
		log_life(p, day, "serve", state)   # his own life history: when he joined which service
	p[4] = state
	p[5] = u.uid
	u.name = name_of(f, p, race_of(e))
	u.born = float(p[3])
	u.sex = int(p[2])   # v0.014: the combat log's he/she follows the register
	u.age = age_of(p, day)
	u.family = int(f["id"])
	Sickness.on_bind(f, p, u)   # sickness: he carries his open case into the force (or clears a stale one)
	CharacterDesign.apply_to_unit(Game, str(g(p, PERSON_UID, "")), u)

## A named unit keeps its own name (a bounty chief): the person takes it.
static func bind_keep_name(e: Dictionary, f: Dictionary, p: Array, u: Unit, state: String, day: float) -> void:
	while p.size() < 8:
		p.append("")
	p[7] = u.name
	bind(e, f, p, u, state, day)

## Back home: state "" and no unit.
static func set_home(p: Array) -> void:
	if String(p[4]) != "" and String(p[4]) != "hire":
		log_life(p, float(Game.day), "home", String(p[4]))
	p[4] = ""
	p[5] = -1

## A person's own life history (record field HIST): [[day, code, arg], ...], oldest first, at most LIFE_MAX
## (the oldest drop). Codes: serve <state> (joined a force), home <state> (came back), job <title> (took a place),
## lost_job <title>, wound <what>, legend <the legendary piece he made> (v0.014).
const LIFE_MAX := 16
const REJOIN_DAYS := 7.0   # [ours] home and back in the same service within this many days = one spell
static func log_life(p: Array, day: float, code: String, arg: String) -> void:
	if p.size() <= HIST:
		return
	var h: Array = p[HIST]
	if code == "serve" and not h.is_empty() and String(h[-1][1]) == "home" and String(h[-1][2]) == arg and day - float(h[-1][0]) <= REJOIN_DAYS:
		h.pop_back()   # back in the same service within days of coming home: one spell (gangs that scatter and
		return         # gather again would otherwise push his whole past out of the LIFE_MAX entries)
	h.append([int(day), code, arg])
	while h.size() > LIFE_MAX:
		# the oldest entry goes, but never the place he still holds (his last "job" entry): a man in and out of
		# service keeps his trade on record
		var drop := 0
		if String(h[0][1]) == "job" and String(p[JOB]) == String(h[0][2]):
			var later := false
			for i in range(1, h.size()):
				if String(h[i][1]) == "job":
					later = true
					break
			if not later:
				drop = 1
		h.remove_at(drop)

## The day he last joined this service (the "serve" entry of his history), or -1.
static func served_since(p: Array, state: String) -> float:
	if p.size() <= HIST:
		return -1.0
	var h: Array = p[HIST]
	for i in range(h.size() - 1, -1, -1):
		if String(h[i][1]) == "serve" and String(h[i][2]) == state:
			return float(h[i][0])
	return -1.0

## One row of a force's roster (militia, guard, army, caravan crew, outlaws, the company): the unit is a register
## person; {name, household, town, age, rank, weapon, years_served, pay_day, uid, pid}. household "" = a unit with no
## family record (monsters, the starting company in a world without towns).
static func roster_row(game, u: Unit, state: String) -> Dictionary:
	var town: Dictionary = game.world.get("towns", {}).get(u.home_town, {})
	var f := People.fam_of(town, u.family)
	var p: Array = by_uid(f, u.uid) if not f.is_empty() else []
	var since := served_since(p, state) if not p.is_empty() else -1.0
	var wpn: Variant = u.equip.get("main_hand", u.equip.get("ranged", null))
	return {"name": u.name, "household": String(f.get("name", "")), "town": String(town.get("name", "")),
		"age": age_of(p, float(game.day)) if not p.is_empty() else u.age, "rank": Army.rank_title(u),
		"weapon": wpn.display_name() if wpn != null else "unarmed",
		"years_served": snappedf((float(game.day) - since) / People.year_days(), 0.1) if since >= 0.0 else 0.0,
		"pay_day": snappedf(u.last_pay, 0.01), "uid": u.uid, "pid": int(p[0]) if not p.is_empty() else -1,
		"sick": Sickness.unit_text(u)}   # sickness: "the flux, day 3 of 7 (bed-ridden)" or ""

static func remove(f: Dictionary, p: Array, e: Dictionary = {}) -> void:
	if not e.is_empty():
		forget(e, f, p)
	drop_im(f, int(p[0]))
	pp(f).erase(p)

## Long histories (Douglas 12:55: up to 100 years before): a family row that is gone stays in e.fams (rows are
## numbered by place: businesses, units and the census point at them), but a year after it went (GONE_PACK_DAYS,
## counted from the first weekly sweep that saw it gone: f.gone_at) its person records are packed. A row that moved
## to another town (f.moved) drops them: those people live on, renumbered, in their new town's row. A row that died
## out or left the map remembers them in f.dp like any departed (the newest DP_MAX, as every family's dead; the
## census keeps each town's deaths) and drops them. A record still bound to a live unit (a man still serving in a
## force) stays until his unit is gone. Without this every move left a full copy of the house (each person with
## his life history) behind for good: over a century, thousands of dead rows per world.
const GONE_PACK_DAYS := 120.0   # [ours] a year: the town screen's recent moves can still open the old house
static func pack_gone(e: Dictionary, f: Dictionary, day: float) -> void:
	if not f.has("gone_at"):
		f["gone_at"] = int(day)
		return
	if day - float(f["gone_at"]) < GONE_PACK_DAYS:
		return
	if f.get("packed", false) and (f.get("pp", []) as Array).is_empty() and (f.get("kp", []) as Array).is_empty():
		return
	var moved := String(f.get("moved", "")) != ""
	for key in ["pp", "kp"]:
		var l: Array = f.get(key, [])
		if l.is_empty():
			continue
		var keep := []
		for p in l:
			if int(p[5]) >= 0:
				keep.append(p)   # still serving somewhere: his record stays while his unit lives
			else:
				if not moved:
					forget(e, f, p)
				drop_im(f, int(p[0]))
		f[key] = keep
	if moved:   # the new row carries its own copies of these (barge.gd move_family)
		f.erase("ev"); f.erase("preg")
	# what only a living house uses (its loan book, wear on its goods, its claims on the town's crops); the row keeps
	# its name, history, remembered dead and the empty holdings the family page reads (Families.describe)
	f.erase("ln")
	f["wear"] = {}
	f["cum"] = {}
	f["packed"] = true

## Every unit uid that exists anywhere (company, forces, recruit pools).
static func live_uids(game) -> Dictionary:
	var out := {}
	for u in game.company:
		if not u.dead:
			out[u.uid] = true
	for wid in game.world.get("warbands", {}):
		for u in game.world["warbands"][wid].get("units", []):
			if u is Unit and not u.dead:
				out[u.uid] = true
	for tid in game.world.get("towns", {}):
		for u in game.world["towns"][tid].get("recruits", []):
			if u is Unit:
				out[u.uid] = true
	for u in CampaignWorld.mustering_units(game.world):
		if u is Unit and not u.dead: out[u.uid] = true
	for u: Unit in Mobilization.reserves(game):
		if not u.dead: out[u.uid] = true
	for u: Unit in Prisoners.units(game):   # v0.033: held prisoners on both sides are alive, not lost with a force
		out[u.uid] = true
	return out

## Weekly: a person whose unit is gone from every force and pool without word (killed in an AI clash, a
## recruit pool refreshed) is settled: recruits not hired go home, the rest died with their force.
static func sweep(game) -> void:
	var live := live_uids(game)
	for tid in game.world.get("towns", {}):
		sweep_town(game, game.world["towns"][tid], live)

static func sweep_town(game, t: Dictionary, live: Dictionary) -> void:
	if not TownEcon.has_econ(t):
		return
	var e: Dictionary = t["econ"]
	for f in e["fams"]:
		if not f.has("pp"):
			continue
		if f.get("gone", false):
			for p in f["pp"]:   # a house that is gone keeps its records; the dead just lose their unit
				if int(p[5]) >= 0 and not live.has(int(p[5])):
					p[5] = -1
			pack_gone(e, f, float(game.day))
			continue
		for p in (f["pp"] as Array).duplicate():
			var uid := int(p[5])
			if uid < 0 or live.has(uid):
				continue
			var st := String(p[4])
			if st == "hire" or st == "":
				set_home(p)
			else:
				People.casualty_rec(game, String(t["id"]), int(f["id"]), name_of(f, p, race_of(e)), "dead", st, p)

# ================================================================== work and wages
## Who holds which of the family's real places: {pid: {kind, title, where, wage}} for the grown-ups at home (and
## those for hire, who still work until hired). The family's counts decide the places (Families.reassign: own land
## and herds = f.hands, jobs f.jobs, casual work f.cj, the rest idle); the eldest take the first places. wage =
## gold a day the place pays that person (a business's wage, the casual rate; 0 for the family's own land, whose
## earnings go to the family purse and are not split).
static func work(e: Dictionary, f: Dictionary) -> Dictionary:
	var out := {}
	if not f.has("pp"):
		return out
	var home := []
	for p in pp(f):
		if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]:
			home.append(p)
	home.sort_custom(func(x, y): return float(x[3]) < float(y[3]) if float(x[3]) != float(y[3]) else int(x[0]) < int(y[0]))
	if Population.is_cohort(f): return Population.named_work(e, f, home)
	var places := []
	# v0.014: the keepers of the family's shops first (Families._keep: the eldest at home keep them)
	var biz0: Array = e.get("biz", [])
	for kb in f.get("keeps", []):
		if int(kb) < biz0.size():
			var b0: Dictionary = biz0[int(kb)]
			places.append({"kind": "job", "keeper": true, "title": "keeper of the %s" % String(TownEcon.data()["businesses"][b0["type"]]["name"]),
				"where": Businesses.title(e, b0), "wage": 0.0, "biz": int(kb)})
	# own land and herds
	var hands := int(f.get("hands", 0))
	if hands > 0:
		var ac := Families.acres(f)
		var ln := Families.crop_hands(f, e); var hn := Families.herd_hands(f, e)
		var animal := _biggest(f["herd"])
		var animal_n := int(f["herd"].get(animal, 0))
		if e.has("hd"):
			var animal_work := -1.0
			for h in Herds.of_family(e, int(f["id"])):
				var per_hand := float(Herds.kind(String(h["k"])).get("per_hand", 0))
				if per_hand <= 0.0 or Herds.head(h) <= 0: continue
				var care := Herds.ge(h) / per_hand
				if care > animal_work:
					animal_work = care; animal = String(h["k"]); animal_n = Herds.head(h)
		var herd_h := 0
		if hn > 0.0:
			herd_h = hands if ac == 0 else clampi(int(round(float(hands) * hn / maxf(0.001, ln + hn))), 1, maxi(1, hands - 1))
		var crop := _biggest(f["land"])
		for i in hands:
			if i < herd_h:
				places.append({"kind": "herd", "title": "%s on the family herd" % Recruits.HERD_TITLES.get(animal, "%s herder" % animal),
					"where": TownEcon.n_of(animal_n, animal), "wage": 0.0})
			else:
				var v := TownEcon.variety_word(e, crop)
				places.append({"kind": "land", "title": "farmhand on the family %s" % v,
					"where": "%s of %s" % [TownEcon.n_of(int(f["land"].get(crop, 0)), "acres"), v], "wage": 0.0})
	# jobs: the family's own business first, then the best wage
	var keys: Array = (f["jobs"] as Dictionary).keys()
	var biz: Array = e["biz"]
	keys.sort_custom(func(x, y):
		var bx: Dictionary = biz[int(x)]; var by: Dictionary = biz[int(y)]
		var ox := int(bx["owner"]) == int(f["id"]); var oy := int(by["owner"]) == int(f["id"])
		if ox != oy:
			return ox
		if float(bx["wage"]) != float(by["wage"]):
			return float(bx["wage"]) > float(by["wage"])
		return int(x) < int(y))
	for kk in keys:
		var b: Dictionary = biz[int(kk)]
		for i in int(f["jobs"][kk]):
			places.append({"kind": "job", "title": Recruits.job_title(e, b), "where": Businesses.title(e, b), "wage": float(b["wage"]), "biz": int(kk)})
	var CJ: Dictionary = TownEcon.data()["casual_jobs"]
	for j in f.get("cj", {}):
		for i in int(f["cj"][j]):
			places.append({"kind": "casual", "title": String(CJ[j]["name"]), "where": "casual work", "wage": Barge.casual_wage(e, String(j)), "cj": String(j)})
	for i in home.size():
		var p: Array = home[i]
		if i < places.size():
			out[int(p[0])] = places[i]
		else:
			var st := "poorhouse" if f.get("shel", false) else ("homeless" if int(f.get("homes", 1)) <= 0 else "idle")
			out[int(p[0])] = {"kind": "none", "title": {"poorhouse": "in the poorhouse, no work", "homeless": "sleeping rough, no work",
				"idle": "out of work"}[st], "where": "", "wage": 0.0}
	if e.has("academy") and (f["jobs"] as Dictionary).has(str(int(e["academy"]))):
		Academy.mark_lead(e, f, out)   # v0.012: the research house's lead holds his family's place there, under his title
	for p in kp(f):
		var job := String(f.get("child_cj", {}).get(str(int(p[0])), ""))
		if job == "" or not Shelter.cleanup_child_eligible(e, p, float(Game.day)): continue
		var share := float(Barge.B()["labour"]["kid_share"])
		out[int(p[0])] = {"kind": "casual", "title": String(CJ[job]["name"]), "where": "short child shift", "wage": Barge.casual_wage(e, job) * share, "cj": job, "share": share}
	return out

static func _biggest(d: Dictionary) -> String:
	var best := ""; var most := -1
	for k in d:
		if int(d[k]) > most:
			most = int(d[k]); best = String(k)
	return best

## The head of the household: the eldest married man (or woman) at home, else the eldest adult, else the eldest elder.
static func head_of(f: Dictionary) -> Array:
	var best: Array = []
	for pass_i in 3:
		for p in pp(f):
			if AWAY.has(String(p[4])) and pass_i < 2:
				continue
			var ok := false
			match pass_i:
				0: ok = int(p[6]) == 0 and not by_pid(f, int(g(p, SP, -1))).is_empty()
				1: ok = int(p[6]) == 0
				2: ok = true
			if ok and (best.is_empty() or int(p[2]) < int(best[2]) or (int(p[2]) == int(best[2]) and float(p[3]) < float(best[3]))):
				best = p
		if not best.is_empty():
			return best
	return best

## The family's memory of its dead and departed (kinship and stories read through them: "Wil's brother Bram died"):
## f.dp = [[pid, fi, sex, born, "gone", -1, kind, name, spouse, mother, father], ...], the newest DP_MAX.
const DP_MAX := 8
static func forget(e: Dictionary, f: Dictionary, p: Array) -> void:
	Dynasty.record_person(e, f, p, false)
	var pid := int(p[0])
	if not f.has("dp"):
		f["dp"] = []
	var d: Array = f["dp"]
	for remembered in d:
		if int(remembered[0]) == pid: return
	var remembered_row := [pid, int(p[1]), int(p[2]), int(p[3]), "gone", -1, int(p[6]), name_of(f, p, race_of(e)), int(g(p, SP, -1)), int(g(p, MO, -1)), int(g(p, FA, -1))]
	if p.size() > FATHER_UID:
		_identity_pad(remembered_row)
		for field in [PERSON_UID, HOUSE_UID, SPOUSE_UID, MOTHER_UID, FATHER_UID]: remembered_row[field] = p[field]
	d.append(remembered_row)
	while d.size() > DP_MAX:
		d.pop_front()

## A record leaves for good (died, packed, left the register): his immunities go with him (Sickness.kill and the
## moves cleared them; the old, the battle dead and packed rows leaked them). Not for a bride: hers move with her.
static func drop_im(f: Dictionary, pid: int) -> void:
	if f.has("im"):
		(f["im"] as Dictionary).erase(str(pid))
		if (f["im"] as Dictionary).is_empty():
			f.erase("im")

## A person of the family by pid, living or remembered (f.dp); [] when unknown.
static func any(f: Dictionary, pid: int) -> Array:
	if pid < 0:
		return []
	var p := by_pid(f, pid)
	if not p.is_empty():
		return p
	for q in f.get("dp", []):
		if int(q[0]) == pid:
			return q
	return []

static func _parents(p: Array) -> Array:
	var out := []
	for i in [MO, FA]:
		if int(g(p, i, -1)) >= 0:
			out.append(int(p[i]))
	return out

static func _child_of(p: Array, pid: int) -> bool:
	return pid >= 0 and (int(g(p, MO, -1)) == pid or int(g(p, FA, -1)) == pid)

static func _siblings(a: Array, b: Array) -> bool:
	for x in _parents(a):
		if _parents(b).has(x):
			return true
	return false

## Kinship to the head, in words, read from the real links (spouse, mother, father; the dead remembered in f.dp):
## "head of the family", "Doran's wife", "Doran and Vera's daughter", "Doran's stepson", "Doran's mother",
## "Doran's grandfather", "Doran's brother", "Doran's sister-in-law", "Doran's mother-in-law", "Doran's
## daughter-in-law", "Doran's grandson", "Doran's niece", or "kin" when no link is known.
static func kin_of(e: Dictionary, f: Dictionary, p: Array, h: Array) -> String:
	if h.is_empty():
		return "kin"
	if int(p[0]) == int(h[0]):
		return "head of the family"
	var hp := int(h[0]); var hs := int(g(h, SP, -1))
	var hn := first_of(e, h)
	var sex := int(p[2])
	var sp := any(f, hs)
	if int(g(p, SP, -1)) == hp or int(p[0]) == hs:
		return "%s's %s" % [hn, ["husband", "wife"][sex]]
	# children of the head (and of the spouse)
	if _child_of(p, hp):
		var live_sp := by_pid(f, hs)
		if not live_sp.is_empty() and _child_of(p, hs):
			return "%s and %s's %s" % [hn, first_of(e, live_sp), ["son", "daughter"][sex]]
		return "%s's %s" % [hn, ["son", "daughter"][sex]]
	if _child_of(p, hs):
		return "%s's %s" % [hn, ["stepson", "stepdaughter"][sex]]
	# parents and grandparents
	if _child_of(h, int(p[0])):
		return "%s's %s" % [hn, ["father", "mother"][sex]]
	for par in _parents(h):
		var pr := any(f, par)
		if not pr.is_empty() and _child_of(pr, int(p[0])):
			return "%s's %s" % [hn, ["grandfather", "grandmother"][sex]]
	if not sp.is_empty() and _child_of(sp, int(p[0])):
		return "%s's %s" % [hn, ["father-in-law", "mother-in-law"][sex]]
	# brothers and sisters, and the spouse's
	if _siblings(p, h):
		return "%s's %s" % [hn, ["brother", "sister"][sex]]
	if not sp.is_empty() and _siblings(p, sp):
		return "%s's %s" % [hn, ["brother-in-law", "sister-in-law"][sex]]
	# married to a child of the head; grandchildren; nephews and nieces
	var psp := any(f, int(g(p, SP, -1)))
	if not psp.is_empty() and (_child_of(psp, hp) or _child_of(psp, hs)):
		return "%s's %s" % [hn, ["son-in-law", "daughter-in-law"][sex]]
	for par in _parents(p):
		var pr := any(f, par)
		if pr.is_empty():
			continue
		if _child_of(pr, hp) or _child_of(pr, hs):
			return "%s's %s" % [hn, ["grandson", "granddaughter"][sex]]
		if _siblings(pr, h) or (not sp.is_empty() and _siblings(pr, sp)):
			return "%s's %s" % [hn, ["nephew", "niece"][sex]]
	return "kin"


## The household in family order (elders, the head and spouse, the other grown-ups, then the children, each group
## oldest first): [{pid, name, first, sex, kind (man, woman, elder, boy, girl), age, kin, work, wage (gold a
## week, -1 = none), state, uid}]. Display text: person_line().
static func household(e: Dictionary, f: Dictionary, day: float) -> Array:
	var out := []
	if not f.has("pp"):
		return out
	var race := race_of(e)
	var h := head_of(f)
	var jobs := work(e, f)
	var hs := by_pid(f, int(g(h, SP, -1))) if not h.is_empty() else []
	var groups := [[], [], [], []]
	for p in pp(f):
		var gi := 2
		if int(p[6]) == 1:
			gi = 0
		elif (not h.is_empty() and int(p[0]) == int(h[0])) or (not hs.is_empty() and int(p[0]) == int(hs[0])):
			gi = 1
		groups[gi].append(p)
	for p in kp(f):
		groups[3].append(p)
	for gr in groups:
		gr.sort_custom(func(x, y): return float(x[3]) < float(y[3]) if float(x[3]) != float(y[3]) else int(x[0]) < int(y[0]))
		for p in gr:
			var kind: String = "elder" if int(p[6]) == 1 else ((["boy", "girl"] if int(p[6]) == 2 else ["man", "woman"])[int(p[2])])
			var st := String(p[4])
			var w := _work_of(e, f, p, jobs)
			out.append({"pid": int(p[0]), "name": name_of(f, p, race), "first": first_of(e, p), "sex": int(p[2]), "kind": kind,
				"age": age_of(p, day), "kin": kin_of(e, f, p, h), "work": w[0], "wage": w[1], "state": st, "uid": int(p[5]),
				"sick": Sickness.person_text(f, int(p[0]), day)})   # sickness: "the flux, day 3" or ""
	return out

## [work words, wage in gold a week (-1 = no wage)] for one person: his place at home, or his service and its pay.
static func _work_of(e: Dictionary, f: Dictionary, p: Array, jobs: Dictionary) -> Array:
	if int(p[6]) == 2:
		var child_job: Dictionary = jobs.get(int(p[0]), {})
		if child_job.is_empty(): return ["child", -1]
		return ["child; %s (short cleanup shift)" % child_job["title"], int(round(float(child_job["wage"]) * 7))]
	var st := String(p[4])
	if st in ["", "hire", "reserve"]:
		if int(p[6]) == 1:
			return ["elder, past working age", -1]
		var j: Dictionary = jobs.get(int(p[0]), {})
		var extra := "; for hire at the tavern" if st == "hire" else ""
		if j.is_empty():
			return ["out of work" + extra, -1]
		if j.get("keeper", false):
			return ["%s (business profit, no fixed wage)%s" % [j["title"], extra], -1]
		match String(j["kind"]):
			"land", "herd":
				return ["%s (family land, no wage)%s" % [j["title"], extra], -1]
			"none":
				return [String(j["title"]) + extra, -1]
		return ["%s at %s%s" % [j["title"], j["where"], extra] if String(j["kind"]) == "job" else "%s (casual)%s" % [j["title"], extra],
			int(round(float(j["wage"]) * 7.0))]
	var u: Unit = _unit(int(p[5]))
	match st:
		"caravan":
			var guard := int(p[5]) >= 0
			return ["caravan %s" % ("guard" if guard else "driver"), int(round((People.GUARD_WAGE if guard else People.CREW_WAGE) * 7.0))]
		"bandit", "deserter":
			return [SERVICE_WORDS[st] + " (no wage)", -1]
	var words: String = SERVICE_WORDS.get(st, st)
	if u == null:
		return [words, -1]
	if st == "army" or st == "militia":
		var rt := Army.rank_title(u)
		if rt != "":
			words = "%s, %s" % [words, rt]
	if u.unpaid_days > 0:
		return ["%s, unpaid %d day%s" % [words, u.unpaid_days, "" if u.unpaid_days == 1 else "s"], 0]
	return [words, int(round(u.last_pay * 7.0))]

static func _unit(uid: int) -> Unit:
	if uid < 0:
		return null
	for u in Game.company:
		if u.uid == uid:
			return u
	for wid in Game.world.get("warbands", {}):
		for u in Game.world["warbands"][wid].get("units", []):
			if u is Unit and u.uid == uid:
				return u
	var reserve: Unit = Mobilization.reserve_unit(Game, uid)
	if reserve != null: return reserve
	return Prisoners.captive_unit(Game, uid)

## "Doran Blackmere (man, 31; head of the family): cattle herder on the family herd (family land, no wage)"
## "Ivo Blackmere (man, 24; Doran's son): tax collector's man at the town tax office, 21 gold a week"
static func person_line(m: Dictionary) -> String:
	var wage := int(m["wage"])
	return "%s (%s, %d; %s): %s%s" % [m["name"], m["kind"], int(m["age"]), m["kin"], m["work"], (", %d coins a week" % wage) if wage >= 0 and String(m["work"]) != "child" else ""]

## Life histories, work: after the family's turn (and at world gen) each grown-up at home who took a new place
## gets ["job", day, "title@where"] in his history and the place he left ["left_job", ...]; the current place is
## kept in the JOB field. Cheap: only when the family's places changed (a signature of its counts).
static func track_jobs(e: Dictionary, f: Dictionary, day: float) -> void:
	if not f.has("pp") or f.get("estate", false):
		return
	var sig := hash([int(f.get("hands", 0)), f["jobs"], f.get("keeps", []), f.get("cj", {}), int(f.get("idle", 0)), pp(f).size(), f.get("shel", false), int(f["homes"]) > 0])
	if sig == int(f.get("wsig", 0)):
		return
	f["wsig"] = sig
	var jobs := work(e, f)
	for p in pp(f):
		if p.size() <= HIST or int(p[6]) != 0 or not (String(p[4]) in ["", "hire"]):
			continue
		var j: Dictionary = jobs.get(int(p[0]), {})
		var now := ""
		if not j.is_empty() and String(j["kind"]) != "none":
			now = "%s@%s" % [j["title"], j["where"]] if String(j["kind"]) in ["job"] else String(j["title"])
		var was := String(p[JOB])
		if now == was:
			continue
		if was != "":
			log_life(p, day, "left_job", was)
		if now != "":
			log_life(p, day, "job", now)
		else:
			log_life(p, day, "idle", "poorhouse" if f.get("shel", false) else ("homeless" if int(f["homes"]) <= 0 else "idle"))
		p[JOB] = now

## His own past from his history, newest first: [{code, arg, from, to}] where to = -1 while it lasts. "job"
## spans (title@where) end at the next job, idle spell or service; "serve" spans end when he came home.
static func life_spans(p: Array) -> Array:
	var out := []
	if p.size() <= HIST:
		return out
	var h: Array = p[HIST]
	var open := {}
	for x in h:
		var code := String(x[1])
		var d := float(x[0])
		match code:
			"job", "idle", "serve":
				for k in ["job", "idle"]:
					if open.has(k):
						open[k]["to"] = d
						open.erase(k)
				var s := {"code": code, "arg": String(x[2]), "from": d, "to": -1.0}
				out.append(s)
				if code != "serve":
					open[code] = s
				else:
					open["serve"] = s
			"left_job":
				if open.has("job"):
					open["job"]["to"] = d
					open.erase("job")
			"home":
				if open.has("serve"):
					open["serve"]["to"] = d
					open.erase("serve")
			"wound":
				out.append({"code": "wound", "arg": String(x[2]), "from": d, "to": d})
			"legend":   # v0.014: he made a legendary piece (its name)
				out.append({"code": "legend", "arg": String(x[2]), "from": d, "to": d})
	out.reverse()
	return out
