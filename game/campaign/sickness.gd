class_name Sickness
extends RefCounted
## Sickness (docs/specs/barge/06-sickness.md, with 6b starvation). Real diseases in real register people:
## every case is one person record (Persons) with a disease, the day he caught it, his onset, his end and the
## outcome rolled at infection (recovers, or dies on day X); every case keeps its source (conditions at home, a
## sick person he lived or worked with, the town's sick, a carrier, the camp, a wound, the map edge, a relapse).
## Disease rows are data (data/sickness.json; adding a disease = one row).
##
## Storage (all plain values, saved with the world):
##   f.sk {pid: case}            the family's open cases (the authoritative record, also for men away in a force,
##                                a caravan or the company: their family keeps the case)
##     case = [disease, t0 (caught), onset, end, death day (-1 = recovers), source, bed (1 = bed-ridden), remedy
##             (1 = given), death roll u, death chance per sick day q, business id he works at (-1), counted in the
##             town (1 = he was at home), bed counted on the business (1), sheds from (day he passes it on)]
##   f.im {pid: {disease: until day}}   immunity after recovery (1e12 = for life)
##   f.bc {pid: 0..1}            body condition below full (6b); absent = 1.0 (well fed)
##   f.skd {business: bed days}  bed-ridden days of cases that ended since the family's last turn (wage query)
##   f.skw {business: bed days}  this turn's bed-ridden worker-days per job (Families.turn's wage code reads it)
##   b.sick                      bed-ridden staff of a business today (businesses.gd runs short-handed)
##   e.sk  (town book)           counters updated on each change: act {disease: open cases of people at home},
##                                cases / deaths {disease: total}, starved, new [[day, disease]] (7 days), first
##                                {disease: [day, where the outbreak came from]}, h60 (60 days of open cases),
##                                hd {disease: last 8 days}, yr {year: [cases, sickness deaths, starved]}, q (event
##                                queue {day: [[day, kind, fid, pid, disease, source]]}: 0 end or death, 1 exposure,
##                                2 bed-ridden starts), qd (last day run), lowbc (people below full condition), bcw /
##                                bcl (lowest condition this week / last), nmax (largest household), news {town id:
##                                [day, {disease: open cases}]} (outbreaks heard of from caravans), tf (cached town
##                                factors), stag (the town's week offset), hb (herbalist row present)
##   Unit.sick / sick_shed / sick_on / sick_to / sick_bed   the case mirrored on a man's Unit (company, forces,
##                                militia, recruit pool) for battle effects, the unit card and band power
##
## Cadence (Douglas's gate: mean <= 6 ms a campaign day, worst single job <= 4 ms at 20 towns x 150 families; he
## allowed a person to be counted every two days):
##   - every 2 days per town (half the towns each day), three work jobs per run (queue_day from
##     CampaignWorld._daily; do_job), a run covering every day since the last: due events from the day-bucketed
##     queue (deaths, recoveries, exposures, bed-ridden starts: exact days from the stamps), and new cases from
##     conditions and the town's sick drawn as a thinned Poisson process over the register (a candidate person is
##     picked uniformly from nmax slots per family and accepted with his real risk / the town's bound: the same
##     per-person risk as rolling everyone, at the cost of the candidates); one more job for the world (the edge
##     event, the forces whose week it is, the company);
##   - household, workplace and garrison contacts are rolled once when a case starts, over his shedding window;
##   - the weekly family turn (Families.turn -> family_turn): the body-condition meter from the family's own food,
##     starvation, remedies bought, the bed-ridden days its wage code subtracts;
##   - forces on the map once a week each (camp sickness, contact in the force, a camp near a town), the company
##     daily (in town: the town's risk; in the field: camp sickness; wound rot on untreated wounds).

const HOME := ["", "hire", "militia", "reserve", "guard", "pasture"]   # person states that live at home in the town
const SERVICE := ["militia", "guard", "caravan", "army", "bandit", "deserter", "pasture"]
const YR_KEEP := 30   # [ours] years of the per-town sickness book (cases, deaths, starved) kept in long histories
const NMAX := 16  # register slots per family for the candidate draw (bigger households: the 17th+ never picked)
const NONE := 1.0e12
const C_DIS := 0
const C_T0 := 1
const C_ON := 2
const C_END := 3
const C_DIE := 4
const C_SRC := 5
const C_BED := 6
const C_REM := 7
const C_U := 8
const C_Q := 9
const C_BIZ := 10
const C_CNT := 11
const C_BON := 12
const C_SHED := 13

static var _D: Dictionary = {}
static var ids: Array = []          # disease ids in row order
static var U_END := 0.75
static var U_STR := 0.85
static var U_FAT := 1.3
static var U_FOC := -0.10
static var CATCH: Dictionary = {}   # disease -> catch by person kind [adult, elder, child]
static var BODY_CATCH := 2.0
static var BODY_DEATH := 2.0
## The world's sickness deadliness (New Campaign slider, kept in the world as "sickness_deadliness"): every case's
## daily death risk x this. 1 = the rates as designed; 0 = sickness never kills. Set at world creation and load.
const DEADLINESS_STEPS := [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
static var new_world_deadliness := 1.0   # what the next new world uses (the New Campaign screen sets it)
static var deadliness := 1.0

static func use_world_deadliness(w: Dictionary) -> void:
	deadliness = clampf(float(w.get("sickness_deadliness", 1.0)), 0.0, 2.0)

## Perf gate and tests: time spent in sickness (us) since the last reset when prof_on; every new case logged.
static var prof_on := false
static var us := 0
static var prof: Dictionary = {}   # dev: us by part (prof_parts; off for the gate so it measures plain code)
static var prof_parts := false

static func _pf(k: String, t0: int) -> int:
	var t1 := Time.get_ticks_usec()
	if prof_parts:
		prof[k] = int(prof.get(k, 0)) + t1 - t0
	return t1
static var log_cases := false
static var case_log: Array = []

# ================================================================== data
static func data() -> Dictionary:
	if _D.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/sickness.json"))
		if d is Dictionary:
			_D = d
			ids = []
			for k in d["diseases"]:
				ids.append(String(k))
			CATCH = {}
			for k in ids:
				var cr: Dictionary = d["diseases"][k]["catch"]
				CATCH[k] = PackedFloat64Array([float(cr["adult"]), float(cr["elder"]), float(cr["child"])])   # by person kind
			BODY_CATCH = float(d["body"]["catch"])
			BODY_DEATH = float(d["body"]["death"])
			var un: Dictionary = d.get("unit", {})
			U_END = float(un.get("END", U_END)); U_STR = float(un.get("STR", U_STR))
			U_FAT = float(un.get("fatigue", U_FAT)); U_FOC = float(un.get("focus", U_FOC))
	return _D

static func row(dis: String) -> Dictionary:
	if _D.is_empty():
		data()
	return _D["diseases"].get(dis, {})

static func dname(dis: String) -> String:
	return String(row(dis).get("name", dis))

static func year_days() -> float:
	return float(4 * Calendar.DAYS_PER_SEASON)

static func book(e: Dictionary) -> Dictionary:
	if not e.has("sk"):
		e["sk"] = {"act": {}, "cases": {}, "deaths": {}, "starved": 0, "new": [], "first": {}, "h60": [], "hd": {}, "yr": {},
			"q": {}, "qd": int(e.get("day", 0)) - 1, "lowbc": 0, "news": {}, "tf": {}}
	return e["sk"]

static func case_of(f: Dictionary, pid: int) -> Array:
	if not f.has("sk"):
		return []
	return f["sk"].get(str(pid), [])

static func band(p: Array) -> String:
	match int(p[6]):
		2: return "child"
		1: return "elder"
	return "adult"

static func race_mult(r: Dictionary, race: String) -> float:
	var rm: Dictionary = r.get("race", {})
	var m := 1.0
	if rm.has(race):
		m = float(rm[race])
	elif race.ends_with("_elf") and rm.has("elf"):
		m = float(rm["elf"])
	var ra: Dictionary = data().get("race_all", {})
	if ra.has(race):
		m *= float(ra[race])
	return m

static func immune(f: Dictionary, pid: int, dis: String, day: float) -> bool:
	if not f.has("im"):
		return false
	return float(f["im"].get(str(pid), {}).get(dis, -1.0)) > day

## Day he stops being sick (death or recovery).
static func _stop(c: Array) -> float:
	return float(c[C_DIE]) if float(c[C_DIE]) >= 0.0 else float(c[C_END])

static func shedding(c: Array, day: float) -> bool:
	return day >= float(c[C_SHED]) and day < _stop(c)

static func sick_phase(c: Array, day: float) -> bool:
	return day >= float(c[C_ON]) and day < _stop(c)

## Share of an open case's days that pass it on (for the town's counters: open cases x this = shedding).
static func _shed_share(r: Dictionary) -> float:
	var inc := (float(r["inc"][0]) + float(r["inc"][1])) * 0.5
	var sk := (float(r["sick"][0]) + float(r["sick"][1])) * 0.5
	return (sk + inc * float(r.get("shed", 0.5))) / maxf(1.0, sk + inc)

# ================================================================== the family's food (spec 6b): THE one read
## Days of full rations the family went without since its last turn (0 .. days). Read at the start of the family
## turn, before the turn runs its stores down: the stores hold the days of food it laid by; a town whose household
## pool ran short (e.food_short) leaves that share of its families' meals uneaten; homeless families in the
## poorhouse eat its broth, those sleeping rough go short while they are hungry. When the economy's per-family
## hunger lands, this is the only function to change.
## (Barge economy: the family turn works out the family's own hunger - its larder, the poorhouse broth or sleeping rough,
## the gruel kitchen, the town pool's shortfall - and keeps the days short in f.fshort; Barge.family_stage reads the same
## number. This is that one number.)
static func food_short_days(_e: Dictionary, f: Dictionary, _day: float, days: float) -> float:
	return clampf(float(f.get("fshort", 0.0)), 0.0, days)

## The family is going hungry (condition factor of the disease rows).
static func hungry(_e: Dictionary, f: Dictionary) -> float:
	return 1.0 if int(f.get("hungry", 0)) > 0 else 0.0

# ================================================================== risk
## His catch multiplier for a disease today: 0 when he is sick already or immune; age band x body condition.
## (Race: the caller multiplies.)
static func catch_m(f: Dictionary, p: Array, dis: String, _r: Dictionary, day: float) -> float:
	if CATCH.is_empty():
		data()
	var m: float = CATCH[dis][int(p[6])]
	if f.has("sk") or f.has("im") or f.has("bc"):
		var k := str(p[0])
		if f.has("sk") and (f["sk"] as Dictionary).has(k):
			return 0.0
		if f.has("im") and float(f["im"].get(k, {}).get(dis, -1.0)) > day:
			return 0.0
		if f.has("bc"):
			m *= 1.0 + BODY_CATCH * (1.0 - float(f["bc"].get(k, 1.0)))
	return m

## The household's condition factor K (1 = a fed, warm, uncrowded home).
static func cond_k(e: Dictionary, f: Dictionary, r: Dictionary, room: float, cloth: float) -> float:
	var homes := int(f["homes"])
	if f.has("lodging"): room = float(f.get("lodging_rooms", 1)) * TownHousing.PEOPLE_PER_ROOM / maxi(1, homes)
	var crowd := 1.5
	var poor := 1.0
	var cold := 1.0
	if homes > 0:
		crowd = clampf(float(Families.people(f)) / (float(homes) * room) - 1.0, 0.0, 1.5)
		poor = 1.0 if f.get("shel", false) else 0.0
		cold = 1.0 if float(f["store"].get("wood", 1.0)) <= 0.0 else 0.0
	return 1.0 + float(r["crowd"]) * crowd + float(r["poor"]) * poor + float(r["hunger"]) * hungry(e, f) + float(r["cold"]) * (cold + cloth) + TownSanitation.exposure(e, r)

## The conditions in words (a case's source).
static func cond_words(e: Dictionary, f: Dictionary, r: Dictionary, room: float, cloth: float) -> String:
	var w := []
	var homes := int(f["homes"])
	if f.has("lodging"): room = float(f.get("lodging_rooms", 1)) * TownHousing.PEOPLE_PER_ROOM / maxi(1, homes)
	if homes <= 0:
		w.append("the poorhouse" if f.get("shel", false) else "sleeping rough")
	else:
		if float(Families.people(f)) > float(homes) * room * 1.2 and float(r["crowd"]) > 0.0:
			w.append("a crowded home")
		if f.get("shel", false) and float(r["poor"]) > 0.0:
			w.append("the poorhouse")
		if float(f["store"].get("wood", 1.0)) <= 0.0 and float(r["cold"]) > 0.0:
			w.append("no firewood")
	if hungry(e, f) > 0.0 and float(r["hunger"]) > 0.0:
		w.append("hunger")
	if cloth > 0.0 and float(r["cold"]) > 0.0:
		w.append("too few clothes in town")
	return String(r.get("spread", "")) + ("; " + ", ".join(PackedStringArray(w)) if not w.is_empty() else "")

## Town factors, cached in the town book (recomputed each week, each season and when hunger appears or goes):
## T (rate per person-day before the household's K), km (bound of K), mm (bound of the person multiplier, race
## included), ec (expected candidates a day from conditions), sf (shedding share), slots, room, cloth, race.
static func _tf(e: Dictionary, b: Dictionary, d: int) -> Dictionary:
	var si := Calendar.season_index(float(d))
	var wk := (d + int(b.get("stag", 0))) / 7
	var stamp := si * 1000000 + wk
	var tf: Dictionary = b.get("tf", {})
	if int(tf.get("st", -1)) == stamp:
		return tf
	if prof_parts:
		prof["#tf"] = int(prof.get("#tf", 0)) + 1
	data()
	if int(tf.get("wk", -1)) != wk:
		# a new week: the body-condition bound of the week before (every family below full condition has had its
		# turn since) and the largest household (the candidate draw's slots per family)
		b["bcl"] = minf(float(b.get("bcw", 1.0)), 1.0)
		b["bcw"] = 1.0
		_reg_build(e, b, wk)
	var race := Persons.race_of(e)
	var cl := String(e.get("climate", "temperate"))
	var water := bool(e.get("terrain", {}).get("water", false))
	var room := float(TownEcon.culture_of(e)["home"]["room"])
	var pop := maxf(1.0, float(e.get("pop", 1)))
	var cloth := 0.5 if float(e.get("hh", {}).get("clothing", 0)) / pop < 0.3 else 0.0
	var nmax := int(b.get("nmax", NMAX))
	if not b.has("nreg"):
		_reg_build(e, b, wk)
	var slots := float(b["nreg"])
	var bcmin := minf(float(b.get("bcl", 1.0)), float(b.get("bcw", 1.0)))
	var bcb := 1.0 + float(data()["body"]["catch"]) * (1.0 - bcmin)
	var T := []; var km := []; var mm := []; var ec := []; var sf := []; var rms := []
	for dis in ids:
		var r := row(dis)
		var cm := 0.0
		for k in r["catch"]:
			cm = maxf(cm, float(r["catch"][k]))
		rms.append(race_mult(r, race))
		var mx := cm * float(rms[-1]) * bcb
		var tv := 0.0
		var kx := 1.0
		if String(r["where"]) == "town":
			tv = float(r["base"]) * float(r["season"][si]) * float(r["climate"].get(cl, 1.0)) * float(r["water"][0 if water else 1])
			# K's bound from the week's register index (the homes' conditions as the index saw them: the draw reads
			# them from the same index, so no home is ever above the bound)
			var kxm: Array = b.get("kx", [1.5, 1.0, 1.0, 1.0])
			kx = 1.0 + float(r["crowd"]) * float(kxm[0]) + float(r["poor"]) * float(kxm[1]) + float(r["hunger"]) * float(kxm[2]) \
				+ float(r["cold"]) * (float(kxm[3]) + cloth) + TownSanitation.exposure(e, r)
		T.append(tv); km.append(kx); mm.append(mx); ec.append(tv * kx * mx * slots); sf.append(_shed_share(r))
	tf = {"st": stamp, "wk": wk, "T": T, "km": km, "mm": mm, "ec": ec, "sf": sf, "slots": slots, "nmax": nmax, "room": room, "cloth": cloth,
		"race": race, "bcmin": bcmin, "rm": rms}
	b["tf"] = tf
	return tf

## Someone's body condition fell below the bound the town's factors were made with: the catch bound (mm) and the
## expected candidates (ec) grow by the ratio, in place (no full recompute).
static func _lower_bc_bound(tf: Dictionary, v: float) -> void:
	if not tf.has("mm"):
		return
	var old := 1.0 + BODY_CATCH * (1.0 - float(tf["bcmin"]))
	var nw := 1.0 + BODY_CATCH * (1.0 - v)
	var k := nw / old
	tf["bcmin"] = v
	var mm: Array = tf["mm"]
	var ec: Array = tf["ec"]
	for i in mm.size():
		mm[i] = float(mm[i]) * k
		ec[i] = float(ec[i]) * k

static func _poisson(rng: RandomNumberGenerator, lam: float) -> int:
	if lam <= 0.0:
		return 0
	if lam > 30.0:
		return maxi(0, int(round(rng.randfn(lam, sqrt(lam)))))
	var term := exp(-lam)
	var s := term
	var u := rng.randf()
	var k := 0
	while u > s and k < 200:
		k += 1
		term *= lam / float(k)
		s += term
	return k

## The town's register index for the candidate draw, made once a week (with the town factors): the families' sizes
## added up (cum[i] = people in the families before the i-th), so a draw over [0, nreg) names one person record.
## Kept outside the save ({town name: [week, cum, family ids]}; remade after a load). People born since the week
## began are not drawn until it is remade (a week's lag; a family that shrank has empty slots, drawn as nobody).
static var _reg: Dictionary = {}

static func _reg_build(e: Dictionary, b: Dictionary, wk: int) -> void:
	if prof_parts:
		prof["#reg"] = int(prof.get("#reg", 0)) + 1
	var cum := PackedInt32Array()
	var fid := PackedInt32Array()
	var xs := PackedFloat32Array()   # each home's conditions [crowding above room 0..1.5, poor, hungry, cold]
	var xm := [0.0, 0.0, 0.0, 0.0]
	var room := float(TownEcon.culture_of(e)["home"]["room"])
	var n := 0
	var nm := 1
	for f in e["fams"]:
		if f["gone"] or not f.has("pp"):
			continue
		var s := (f["pp"] as Array).size() + (f.get("kp", []) as Array).size()
		if s <= 0:
			continue
		cum.append(n)
		fid.append(int(f["id"]))
		n += s
		nm = maxi(nm, s)
		var x := _home_x(e, f, room)
		for c in 4:
			xs.append(x[c])
			xm[c] = maxf(float(xm[c]), x[c])
	b["nreg"] = n
	b["nmax"] = mini(nm + 1, 40)
	b["kx"] = xm
	_reg_n += 1
	b["rid"] = _reg_n   # which index belongs to this book (another world may have a town of the same name)
	_reg[String(e["fams"][0]["name"])] = [wk, cum, fid, n, _reg_n, xs]

## A home's condition values for K: [crowding above its room (0..1.5), poor (homeless or poorhouse), hungry, cold
## (no firewood or homeless)] (cond_k's terms; the town's clothing is added per draw).
static func _home_x(e: Dictionary, f: Dictionary, room: float) -> Array:
	var homes := int(f["homes"])
	if f.has("lodging"): room = float(f.get("lodging_rooms", 1)) * TownHousing.PEOPLE_PER_ROOM / maxi(1, homes)
	var hg := 1.0 if int(f.get("hungry", 0)) > 0 else 0.0   # (= hungry(e, f), inlined: the weekly scan of every home)
	if homes <= 0:
		return [1.5, 1.0, hg, 1.0]
	var ppl := int(f["m"]) + int(f["f"]) + int(f["kids"]) + int(f["old"])
	return [clampf(float(ppl) / (float(homes) * room) - 1.0, 0.0, 1.5), 1.0 if f.get("shel", false) else 0.0,
		hg, 1.0 if float(f["store"].get("wood", 1.0)) <= 0.0 else 0.0]

static var _reg_n := 0

## A uniform draw over the register index: one person record, [] when the slot is empty now or he is away.
static func _pick_reg(e: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> Array:
	var tn := String(e["fams"][0]["name"])
	if not _reg.has(tn) or int(_reg[tn][4]) != int(b.get("rid", -1)):
		_reg_build(e, b, int(b.get("tf", {}).get("wk", 0)))
		b["tf"]["st"] = -1   # (a remade index after a load: the factors follow it)
	var rg: Array = _reg[tn]
	var total: int = rg[3]
	if total <= 0:
		return []
	var x := rng.randi() % total
	var cum: PackedInt32Array = rg[1]
	var i := cum.bsearch(x, false) - 1   # the last family starting at or before x
	var f: Dictionary = e["fams"][rg[2][i]]
	var j := x - cum[i]
	if f["gone"]:
		return []
	var a: Array = f["pp"]
	var k: Array = f.get("kp", [])
	if j >= a.size() + k.size():
		return []
	var p: Array = a[j] if j < a.size() else k[j - a.size()]
	if not (String(p[4]) in HOME):
		return []
	return [f, p, i, rg[5]]   # (the home's index and the index's conditions: its K for the draw)

## The home's K for disease row r from the register index (the conditions it was made with; cloth: the town's).
static func _k_reg(e: Dictionary, xs: PackedFloat32Array, i: int, r: Dictionary, cloth: float) -> float:
	var o := i * 4
	return 1.0 + float(r["crowd"]) * xs[o] + float(r["poor"]) * xs[o + 1] + float(r["hunger"]) * xs[o + 2] + float(r["cold"]) * (xs[o + 3] + cloth) + TownSanitation.exposure(e, r)

## A uniform draw over the register: a random family, a random one of nmax slots in it (nmax: the town's largest
## household this week, +1). [] = an empty slot, a family gone or a person away from home (thinned away).
static func _pick(e: Dictionary, rng: RandomNumberGenerator, nmax: int) -> Array:
	var fams: Array = e["fams"]
	var n := fams.size()
	if n < 2:
		return []
	var f: Dictionary = fams[1 + rng.randi() % (n - 1)]
	var slot := rng.randi() % nmax
	if f["gone"] or not f.has("pp"):
		return []
	var a: Array = f["pp"]
	var k: Array = f.get("kp", [])
	if slot >= a.size() + k.size():
		return []
	var p: Array = a[slot] if slot < a.size() else k[slot - a.size()]
	if not (String(p[4]) in HOME):
		return []
	return [f, p]

# ================================================================== a case starts
## Starts a case in person p of family f (town t holds the family's register). src is the source ("kind:words":
## cond, home, town, work, garrison, crew, carrier, came, camp, wound, edge, relapse); u: his Unit when the
## caller has it. Returns false when he is sick already or immune.
static func infect(game, t: Dictionary, f: Dictionary, p: Array, dis: String, day: float, src: String, rng: RandomNumberGenerator, u: Unit = null) -> bool:
	if not prof_parts:
		return _infect(game, t, f, p, dis, day, src, rng, u)
	var t0 := Time.get_ticks_usec()
	var ok := _infect(game, t, f, p, dis, day, src, rng, u)
	_pf("infect (nested)", t0)
	prof["#inf"] = int(prof.get("#inf", 0)) + 1
	return ok

static func _infect(game, t: Dictionary, f: Dictionary, p: Array, dis: String, day: float, src: String, rng: RandomNumberGenerator, u: Unit = null) -> bool:
	if f.get("gone", false) or src == "":
		return false
	var key := str(p[0])
	if f.has("sk") and (f["sk"] as Dictionary).has(key):
		return false
	if immune(f, int(p[0]), dis, day):
		return false
	var e: Dictionary = t["econ"]
	var r := row(dis)
	if r.is_empty():
		return false
	var b := book(e)
	var inc := float(rng.randi_range(int(r["inc"][0]), int(r["inc"][1])))
	var sd := float(rng.randi_range(int(r["sick"][0]), int(r["sick"][1])))
	var on := day + inc
	var end := on + sd
	var q := minf(0.9, float(r["death"][band(p)]) * _bc_death(f, key) * deadliness)
	var uu := rng.randf()
	var die := _death_day(on, end, q, uu)
	var bed := 1 if rng.randf() < float(r["bed"]) else 0
	var st := String(p[4])
	var counted := 1 if st in HOME else 0
	var biz := -1
	if counted == 1 and int(p[6]) == 0:
		biz = _job_biz(e, f, p)
	var shed := day + inc * (1.0 - float(r.get("shed", 0.5)))
	var c := [dis, day, on, end, die, src, bed, 0, uu, q, biz, counted, 0, shed]
	if not f.has("sk"):
		f["sk"] = {}
	f["sk"][key] = c
	_yr(b, day, 0)
	b["cases"][dis] = int(b["cases"].get(dis, 0)) + 1
	if counted == 1:
		var was := int(b["act"].get(dis, 0))
		b["act"][dis] = was + 1
		(b["new"] as Array).append([int(day), dis])
		if was == 0:
			b["first"][dis] = [int(day), origin_text(src, day)]
	_push(b, [_stop(c), 0, int(f["id"]), int(p[0]), dis, ""])
	if bed == 1 and biz >= 0:
		_push(b, [on, 2, int(f["id"]), int(p[0]), dis, ""])
	if u == null and int(p[5]) >= 0:
		u = _find_unit(game, t, p)
	if u != null:
		mirror(u, c)
	if log_cases:
		case_log.append([String(t.get("id", "")), int(p[0]), dis, src, day])
	if counted == 1:
		var t0 := Time.get_ticks_usec() if prof_parts else 0
		_household(game, t, e, b, f, p, c, rng)
		if prof_parts: t0 = _pf("inf household", t0)
		if biz >= 0:
			_workplace(game, t, e, b, f, p, c, rng)
		if prof_parts: t0 = _pf("inf work", t0)
		if st == "militia":
			_garrison(game, t, e, b, f, p, c, rng)
		if prof_parts: t0 = _pf("inf garrison", t0)
	return true

## The day he dies (onset + k, the first whole sick day by which 1 - (1 - q)^k reaches his roll u), -1 = recovers.
static func _death_day(on: float, end: float, q: float, u: float) -> float:
	if q <= 0.0:
		return -1.0
	var k := maxf(1.0, ceilf(log(1.0 - u) / log(1.0 - q)))
	return on + k if on + k <= end else -1.0

static func _bc_death(f: Dictionary, key: String) -> float:
	if not f.has("bc"):
		return 1.0
	return 1.0 + BODY_DEATH * (1.0 - float(f["bc"].get(key, 1.0)))

## The business he works at (-1: the family land, casual work or none): Persons.work's order without its words
## (the eldest at home take the family's land first, then its jobs: its own business first, then the best wage).
static func _job_biz(e: Dictionary, f: Dictionary, p: Array) -> int:
	var jobs: Dictionary = f["jobs"]
	if jobs.is_empty():
		return -1
	var born := float(p[3])
	var pid := int(p[0])
	var idx := -int(f.get("hands", 0))
	for q in Persons.pp(f):
		if int(q[6]) == 0 and (String(q[4]) == "" or String(q[4]) == "hire"):
			var bq := float(q[3])
			if bq < born or (bq == born and int(q[0]) < pid):
				idx += 1
	if idx < 0:
		return -1
	if jobs.size() == 1:
		for kk in jobs:
			return int(kk) if idx < int(jobs[kk]) else -1
	for kk in _job_keys(e, f):
		var n := int(jobs[kk])
		if idx < n:
			return int(kk)
		idx -= n
	return -1

static func _job_keys(e: Dictionary, f: Dictionary) -> Array:
	var keys: Array = (f["jobs"] as Dictionary).keys()
	if keys.size() < 2:
		return keys
	var biz: Array = e["biz"]
	var fid := int(f["id"])
	keys.sort_custom(func(x, y):
		var bx: Dictionary = biz[int(x)]; var by: Dictionary = biz[int(y)]
		var ox := int(bx["owner"]) == fid; var oy := int(by["owner"]) == fid
		if ox != oy:
			return ox
		if float(bx["wage"]) != float(by["wage"]):
			return float(bx["wage"]) > float(by["wage"])
		return int(x) < int(y))
	return keys

## The people of family f who hold its places at business biz (pids).
static func _job_holders(e: Dictionary, f: Dictionary, biz: int) -> Array:
	var home := []
	for q in Persons.pp(f):
		if int(q[6]) == 0 and (String(q[4]) == "" or String(q[4]) == "hire"):
			home.append(q)
	home.sort_custom(func(x, y): return float(x[3]) < float(y[3]) if float(x[3]) != float(y[3]) else int(x[0]) < int(y[0]))
	var out := []
	var i := int(f.get("hands", 0))
	for kk in _job_keys(e, f):
		var n := int(f["jobs"][kk])
		if int(kk) == biz:
			for j in range(i, mini(i + n, home.size())):
				out.append(int(home[j][0]))
			return out
		i += n
	return out

static func _yr(b: Dictionary, day: float, slot: int) -> void:
	var yk := str(Calendar.year(day))
	if not b["yr"].has(yk):
		b["yr"][yk] = [0, 0, 0]
		while (b["yr"] as Dictionary).size() > YR_KEEP:   # long histories: the newest YR_KEEP years
			var old := -1
			for k in b["yr"]:
				if old < 0 or int(k) < old:
					old = int(k)
			b["yr"].erase(str(old))
	b["yr"][yk][slot] = int(b["yr"][yk][slot]) + 1

## Queues an event in its day's bucket (an event due on a day already run waits for the next).
static func _push(b: Dictionary, ev: Array) -> void:
	var k := maxi(int(ceilf(float(ev[0]))), int(b["qd"]) + 1)
	var q: Dictionary = b["q"]
	var ks := str(k)
	if not q.has(ks):
		q[ks] = []
	(q[ks] as Array).append(ev)

## "came with the wool caravan from Ashford, day 131" (the town's first case of an outbreak).
static func origin_text(src: String, day: float) -> String:
	var kind := src.get_slice(":", 0)
	var txt := src.substr(kind.length() + 1)
	match kind:
		"cond":
			return "began here (%s), day %d" % [txt, int(day) + 1]
		"town":
			return "%s, day %d" % [txt, int(day) + 1]
		"home", "work", "garrison", "crew":
			return "caught from %s, day %d" % [txt, int(day) + 1]
	return txt

## The race multiplier of a disease for the town's people (from the cached town factors when made, else worked out).
static func _rm_town(e: Dictionary, b: Dictionary, dis: String, r: Dictionary) -> float:
	var tf: Dictionary = b.get("tf", {})
	if tf.has("rm"):
		return float(tf["rm"][ids.find(dis)])
	return race_mult(r, Persons.race_of(e))

## Household members he passes it on to over his shedding window (rolled now, each exposure queued for its day).
static func _household(_game, _t: Dictionary, e: Dictionary, b: Dictionary, f: Dictionary, p: Array, c: Array, rng: RandomNumberGenerator) -> void:
	var dis := String(c[C_DIS])
	var r := row(dis)
	var bh := float(r["home"])
	if bh <= 0.0:
		return
	var from := maxf(float(c[C_SHED]), float(e.get("day", 0)))
	var to := _stop(c)
	if to <= from:
		return
	var bhr := bh * _rm_town(e, b, dis, r)
	var nm := ""
	var w := to - from
	var pid := int(p[0])
	var cc: PackedFloat64Array = CATCH[dis]
	var sk: Dictionary = f.get("sk", {})
	var im: Dictionary = f.get("im", {})
	var bcd: Dictionary = f.get("bc", {})
	for lst in [f["pp"], f.get("kp", [])]:
		for q in lst:
			if int(q[0]) == pid or not (String(q[4]) in HOME):
				continue
			# his catch (catch_m inlined: sick already or immune = 0; age band; body condition)
			var k := str(q[0])
			if sk.has(k) or (im.has(k) and float(im[k].get(dis, -1.0)) > from):
				continue
			var lam := bhr * cc[int(q[6])]
			if bcd.has(k):
				lam *= 1.0 + BODY_CATCH * (1.0 - float(bcd[k]))
			if lam <= 0.0:
				continue
			var P := 1.0 - exp(-lam * w)
			if rng.randf() < P:
				var dt := -log(1.0 - rng.randf() * P) / lam
				if nm == "":
					nm = Persons.name_of(f, p, Persons.race_of(e))
				_push(b, [ceilf(from + dt), 1, int(f["id"]), int(q[0]), dis, "home:%s (household)" % nm])

static var _hc_day := -1   # (the week of _hc)
static var _hc: Dictionary = {}   # a week's job-holding families per business ({town: {business: [families, places]}})

## Workmates at his business: a thinned draw over its staff (the job holders of every family working there).
static func _workplace(_game, _t: Dictionary, e: Dictionary, b: Dictionary, f: Dictionary, p: Array, c: Array, rng: RandomNumberGenerator) -> void:
	var dis := String(c[C_DIS])
	var r := row(dis)
	var bw := float(r["work"])
	var biz := int(c[C_BIZ])
	if bw <= 0.0 or biz < 0 or biz >= (e["biz"] as Array).size():
		return
	var bz: Dictionary = e["biz"][biz]
	var staff := int(bz["workers"]) - 1
	var from := maxf(float(c[C_SHED]), float(e.get("day", 0)))
	var to := _stop(c)
	if staff <= 0 or to <= from:
		return
	var tf: Dictionary = b.get("tf", {})   # (the catch bound does not change with the season: last made is fine)
	if not tf.has("mm"):
		tf = _tf(e, b, int(e.get("day", 0)))
	var i := ids.find(dis)
	var mx := float(tf["mm"][i])
	var k := _poisson(rng, bw * (to - from) * float(staff) * mx)
	if k <= 0:
		return
	var key := str(biz)
	var tn := String(e["fams"][0]["name"])   # (families[0], the town estate, carries the town's name)
	var wk := int(e.get("day", 0)) / 7
	if _hc_day != wk:
		_hc_day = wk
		_hc = {}
	# one pass over the town's families a week: every business's job-holding families (a family that took a place
	# there since is missed until the next week's list; one that left is skipped: its place there counts 0 and the
	# person drawn must hold a place there now)
	if not _hc.has(tn):
		var all := {}
		for f3 in e["fams"]:
			if f3["gone"]:
				continue
			var jb: Dictionary = f3["jobs"]
			for kk in jb:
				if not all.has(kk):
					all[kk] = [[], 0]
				all[kk][0].append(f3)
				all[kk][1] = int(all[kk][1]) + int(jb[kk])
		_hc[tn] = all
	if not _hc[tn].has(key):
		return
	var holders: Array = _hc[tn][key][0]
	var tot: int = _hc[tn][key][1]
	if tot <= 0:
		return
	var nm := ""
	var rm := _rm_town(e, b, dis, r)
	for j in k:
		var x := rng.randi() % tot
		var f2: Dictionary = holders[0]
		for h in holders:
			x -= int(h["jobs"].get(key, 0))   # (a place left since the day's list was made counts 0)
			if x < 0:
				f2 = h
				break
		if f2["gone"]:
			continue
		# one of the family's people at that business: a random grown-up at home until one holds a place there
		var a2: Array = f2["pp"]
		var q: Array = []
		for tries in 8:
			var cq: Array = a2[rng.randi() % a2.size()] if not a2.is_empty() else []
			if not cq.is_empty() and int(cq[6]) == 0 and (String(cq[4]) == "" or String(cq[4]) == "hire") and _job_biz(e, f2, cq) == biz:
				q = cq
				break
		if q.is_empty() or int(q[0]) == int(p[0]):
			continue
		var m := catch_m(f2, q, dis, r, from) * rm
		if rng.randf() < m / mx:
			if nm == "":
				nm = "%s at %s" % [Persons.name_of(f, p, Persons.race_of(e)), Businesses.title(e, bz)]
			_push(b, [ceilf(from + rng.randf() * (to - from)), 1, int(f2["id"]), int(q[0]), dis, "work:" + nm])

## The garrison: a sick militiaman's fellows (the town's militia band).
static func _garrison(game, t: Dictionary, e: Dictionary, b: Dictionary, f: Dictionary, p: Array, c: Array, rng: RandomNumberGenerator) -> void:
	if game == null or not game.world.has("militia"):
		return
	var dis := String(c[C_DIS])
	var r := row(dis)
	var bw := float(r["work"])
	var from := maxf(float(c[C_SHED]), float(e.get("day", 0)))
	var to := _stop(c)
	if bw <= 0.0 or to <= from:
		return
	var rm := race_mult(r, Persons.race_of(e))
	var nm := "%s of the militia" % Persons.name_of(f, p, Persons.race_of(e))
	for u2 in Militia.units_of(game, String(t["id"])):
		if u2.uid == int(p[5]) or u2.family < 0 or u2.family >= (e["fams"] as Array).size():
			continue
		var f2: Dictionary = e["fams"][u2.family]
		var q := Persons.by_uid(f2, u2.uid)
		if q.is_empty():
			continue
		var lam := bw * catch_m(f2, q, dis, r, from) * rm
		if lam > 0.0 and rng.randf() < 1.0 - exp(-lam * (to - from)):
			_push(b, [ceilf(from + rng.randf() * (to - from)), 1, int(f2["id"]), int(q[0]), dis, "garrison:" + nm])

# ================================================================== the daily pass
## Daily (CampaignWorld._daily): every town's due events and new cases, the edge world event, the forces whose
## weekly turn it is, the company.
static func daily(game, d: int) -> void:
	var w: Dictionary = game.world
	if not w.has("towns"):
		return
	for tid in w["towns"]:
		if town_due(String(tid), d):
			do_job(game, ["sick", tid, d])
	do_job(game, ["sick_w", d])

## Douglas (00:17): "keep every sick person real yes, you can even count each person every two days if it impacts
## performance". Each town runs its sickness every CADENCE days (towns staggered: half of them each day); a run
## covers every day since the town's last run (draws scaled to the days, stamps resolve the days between).
const CADENCE := 2

static func town_due(tid: String, d: int) -> bool:
	return (d + absi(hash(tid))) % CADENCE == 0

## The day's sickness as work jobs (CampaignWorld._daily; one job a map frame, like the economy's): three per
## town whose turn it is (its due events and counters, then its new cases in two halves), then one for the edge event, the forces
## and the company.
static func queue_day(w: Dictionary, d: int) -> void:
	if not w.has("towns"):
		return
	if not w.has("work"):
		w["work"] = []
	var work: Array = w["work"]
	for tid in w["towns"]:
		if town_due(String(tid), d):
			work.append(["sick", tid, d, 1])
			work.append(["sick", tid, d, 2])
			work.append(["sick", tid, d, 3])
	work.append(["sick_w", d])

## Runs one queued sickness job; false when the job is not one.
static func do_job(game, job: Array) -> bool:
	match String(job[0]):
		"sick":
			var t0 := Time.get_ticks_usec() if prof_on else 0
			var t: Dictionary = game.world["towns"].get(job[1], {})
			if not t.is_empty():
				data()
				town_day(game, t, int(job[2]), int(job[3]) if job.size() > 3 else 0)
			if prof_on:
				var dt := Time.get_ticks_usec() - t0
				us += dt
				job_worst = maxi(job_worst, dt)
		"sick_w":
			_world_day(game, int(job[1]))
		_:
			return false
	return true

static var job_worst := 0   # perf: the worst single sickness job (one map frame)

static func _world_day(game, d: int) -> void:
	var w: Dictionary = game.world
	var t0 := Time.get_ticks_usec() if prof_on else 0
	data()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), d, "sk"])
	_edge(game, d, rng)
	var t1 := Time.get_ticks_usec() if prof_on else 0
	for wid in w.get("warbands", {}).keys():
		if (absi(hash(String(wid))) + d) % 7 == 0 and w["warbands"].has(wid):
			_force_turn(game, w["warbands"][wid], d)
	if prof_on: t1 = _pf("forces", t1)
	_company_day(game, d)
	if prof_on:
		_pf("company", t1)
		us += Time.get_ticks_usec() - t0
		job_worst = maxi(job_worst, Time.get_ticks_usec() - t0)

## part: 0 = the whole run (tests, daily()), 1 = its due events and counters, 2 and 3 = half its new cases each
## (three work jobs, three map frames).
static func town_day(game, t: Dictionary, d: int, part: int = 0) -> void:
	if not TownEcon.has_econ(t):
		return
	var e: Dictionary = t["econ"]
	var b := book(e)
	if not b.has("hb"):
		ensure_herbalist(t, e)
	if not b.has("stag"):
		b["stag"] = absi(hash(String(t["id"]))) % 7   # towns start their sickness weeks on different days
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(game.world.get("seed", 0)), String(t["id"]), d, "skt", part])
	var t0 := Time.get_ticks_usec() if prof_on else 0
	if part >= 2:   # the run's later jobs: each draws half the new cases over the days the first one covered
		_roll_town(game, t, e, b, d, rng, int(b.get("span", 1)), 0.5)
		if prof_on: _pf("roll", t0)
		return
	# the days this run covers: every day since the town's last run (CADENCE in play; 1 for a town run daily)
	var span := clampi(d - int(b.get("ld", d - CADENCE)), 1, 30)
	b["ld"] = d
	b["span"] = span
	if int(b["qd"]) < d:
		_run_queue(game, t, e, b, d, rng)
	if prof_on: t0 = _pf("queue", t0)
	if part == 0:
		_roll_town(game, t, e, b, d, rng, span)
		if prof_on: t0 = _pf("roll", t0)
	# v0.034: the common folk (cohort rows), as counts, once per run (in play: job part 1, with the queue)
	_pool_day(game, t, e, b, d, rng, span)
	if prof_on: t0 = _pf("pools", t0)
	_outbreak_news(game, t, b, d)
	# counters for the screen: 60 days of open cases, 8 days per disease, the week's new cases (one entry per day
	# covered)
	var act: Dictionary = b["act"]
	var n := 0
	for dis in act:
		n += int(act[dis])
	var h: Array = b["h60"]
	var hd: Dictionary = b["hd"]
	for dis in act:
		if not hd.has(dis):
			hd[dis] = []
	for s in span:
		h.append(n)
		for dis in hd:
			(hd[dis] as Array).append(int(act.get(dis, 0)))
	while h.size() > 60:
		h.pop_front()
	for dis in hd.keys():
		var a: Array = hd[dis]
		while a.size() > 8:
			a.pop_front()
		if a.max() == 0:
			hd.erase(dis)
	var nw: Array = b["new"]
	while not nw.is_empty() and int(nw[0][0]) <= d - 7:
		nw.pop_front()

# ================================================================== the common folk (v0.034)
## Anonymous residents of a cohort row (campaign/population.gd) have no person records, so their sickness is kept as
## counts, at the register's per-person rates: the town's conditions (T) x the row's own home factor K (crowding, the
## poorhouse, hunger, cold) and the town's shedding sick; then, as the register's _household does, each new case's own
## housemates (household size - 1) each catch it with 1 - exp(-home x catch x shedding days) - one round, inside
## those households only (a household's chain ends there, so household spread never seeds fresh households). Their
## cases count in the town's book (act, cases, new, yr, first) like anyone's, so they show on
## the Sickness tab and spread to the register and along caravans. Each case dies with the disease's daily risk over
## its sick days (body condition included); deaths go through Population.kill_slots (census cause "sickness", detail
## the disease). The recovered are immune as counts. No remedies or bed-ridden staff (their work is aggregate).
## f.psk: [[dis, band, n, die_n, die_day, end_day, died], ...]; f.pim: {dis: [count, until]}.
const POOL_GROUPS := {"workers": "adult", "children": "child", "elders": "elder"}

static func _pool_people(f: Dictionary) -> Dictionary:
	return {"workers": Population.anonymous(f, 0) + Population.anonymous(f, 1), "children": Population.anonymous(f, 3),
		"elders": Population.anonymous(f, 2)}

## Open cases of a cohort row (one disease, one age band, or all).
static func pool_sick(f: Dictionary, dis: String = "", bnd: String = "") -> int:
	var n := 0
	for c in f.get("psk", []):
		if (dis == "" or String(c[0]) == dis) and (bnd == "" or String(c[1]) == bnd):
			n += int(c[2]) - (int(c[3]) if bool(c[6]) else 0)
	return n

static func _pool_open(f: Dictionary) -> Dictionary:
	var out := {}
	for c in f.get("psk", []):
		var n := int(c[2]) - (int(c[3]) if bool(c[6]) else 0)
		out[String(c[0])] = int(out.get(String(c[0]), 0)) + n
		var k := String(c[0]) + "|" + String(c[1])
		out[k] = int(out.get(k, 0)) + n
	return out

static func _pool_immune(f: Dictionary, dis: String, day: float) -> int:
	var im: Array = f.get("pim", {}).get(dis, [])
	if im.is_empty(): return 0
	if float(im[1]) <= day:
		f["pim"].erase(dis)
		if (f["pim"] as Dictionary).is_empty(): f.erase("pim")
		return 0
	return int(im[0])

static func _yr_n(b: Dictionary, day: float, slot: int, n: int) -> void:
	if n <= 0: return
	_yr(b, day, slot)
	b["yr"][str(Calendar.year(day))][slot] = int(b["yr"][str(Calendar.year(day))][slot]) + n - 1

static func _act_less(b: Dictionary, dis: String, n: int) -> void:
	if n <= 0: return
	var left := int(b["act"].get(dis, 0)) - n
	if left > 0: b["act"][dis] = left
	else: b["act"].erase(dis)

## One town run (part 0 of town_day): the cohorts' cases due end or kill, then new cases over the run's days.
static func _pool_day(game, t: Dictionary, e: Dictionary, b: Dictionary, d: int, rng: RandomNumberGenerator, span: int) -> void:
	var tf := _tf(e, b, d)
	var pop := maxf(1.0, float(e["pop"]))
	var act: Dictionary = b["act"]
	var room := float(tf["room"])
	var cloth := float(tf["cloth"])
	for f in e["fams"]:
		if not Population.is_cohort(f): continue
		var tp := Time.get_ticks_usec() if prof_parts else 0
		if f.has("psk"): _pool_resolve(e, b, f, d, rng)
		if prof_parts: tp = _pf("pools resolve", tp)
		if f.get("gone", false): continue
		var people := _pool_people(f)
		var total := int(people["workers"]) + int(people["children"]) + int(people["elders"])
		if total <= 0: continue
		var mates := maxf(0.0, float(Families.people(f)) / float(Population.households(f)) - 1.0)   # housemates per person
		var bc: Dictionary = f.get("pool_condition", {})
		var open := _pool_open(f)   # the row's open cases by disease and by "disease|band", counted once
		for i in ids.size():
			var dis: String = ids[i]
			var r := row(dis)
			var town := float(r.get("town", 0.0)) * float(act.get(dis, 0)) * float(tf["sf"][i]) / pop
			var cond := float(tf["T"][i])
			if cond > 0.0: cond *= cond_k(e, f, r, room, cloth)
			var rate := (cond + town) * float(tf["rm"][i])
			if rate <= 0.0: continue
			var free := 1.0 - minf(1.0, float(_pool_immune(f, dis, float(d))) / float(total))
			var src := ""   # where it began: worked out only when a first case needs it
			var left := {}   # susceptible people per group after this run's outside cases
			var catches := {}
			var first := 0
			for group in POOL_GROUPS:
				var bnd: String = POOL_GROUPS[group]
				var s := maxf(0.0, float(people[group]) - float(open.get(dis + "|" + bnd, 0))) * free
				var catch := float(r["catch"][bnd]) * (1.0 + BODY_CATCH * (1.0 - float(bc.get(group, 1.0))))
				catches[group] = catch
				left[group] = s
				if s < 1.0: continue
				var n := mini(int(s), _poisson(rng, s * rate * catch * float(span)))
				if n <= 0: continue
				if src == "":
					src = "cond:" + cond_words(e, f, r, room, cloth)
					if town > cond: src = "town:caught from the town's sick in %s" % t["name"]
				_pool_infect(e, b, f, dis, bnd, group, n, d, rng, src)
				left[group] = s - float(n)
				first += n
			if first > 0 and float(r.get("home", 0.0)) > 0.0 and mates > 0.0:
				_pool_household(e, b, f, dis, r, first, mates, left, catches, float(tf["rm"][i]), d, rng)
		if prof_parts: _pf("pools roll", tp)

## v0.034: a disease takes hold in a town of your realm (OUTBREAK open cases): one campaign log line per outbreak;
## the outbreak is over when its last case ends.
const OUTBREAK := 10

static func _outbreak_news(game, t: Dictionary, b: Dictionary, d: int) -> void:
	var seen: Dictionary = b.get("outbreak", {})
	for dis in seen.keys():
		if int(b["act"].get(dis, 0)) <= 0: seen.erase(dis)
	var mine := Diplomacy.player_realm(game.world)
	if mine != "" and String(t.get("faction", "")) == mine:
		for dis in b["act"]:
			if int(b["act"][dis]) >= OUTBREAK and not seen.has(dis):
				seen[dis] = d
				CampaignWorld.log_event(game, "Sickness: %s has taken hold in %s (%d sick)." % [dname(dis), t["name"], int(b["act"][dis])])
	if seen.is_empty(): b.erase("outbreak")
	else: b["outbreak"] = seen

## One round of household spread from `first` new cases: each has `mates` housemates, a share of them still
## susceptible (left / all people), each caught with 1 - exp(-home x race x catch x shedding days) as in _household;
## they fall sick during the first cases' shedding days and pass it on no further at home.
static func _pool_household(e: Dictionary, b: Dictionary, f: Dictionary, dis: String, r: Dictionary, first: int, mates: float, left: Dictionary, catches: Dictionary, rm: float, d: int, rng: RandomNumberGenerator) -> void:
	var inc := (float(r["inc"][0]) + float(r["inc"][1])) * 0.5
	var sk := (float(r["sick"][0]) + float(r["sick"][1])) * 0.5
	var shed := sk + inc * float(r.get("shed", 0.5))   # days a case passes it on (from shedding to the end)
	var all := 0.0
	for group in left: all += maxf(0.0, float(left[group]))
	all = maxf(1.0, all + float(first))
	var delay := int(round(inc * (1.0 - float(r.get("shed", 0.5))) + shed * 0.5))
	for group in POOL_GROUPS:
		var s := float(left.get(group, 0.0))
		if s < 1.0: continue
		var P := 1.0 - exp(-float(r["home"]) * rm * float(catches[group]) * shed)
		var m := mini(int(s), _poisson(rng, float(first) * mates * (s / all) * P))
		if m > 0: _pool_infect(e, b, f, dis, POOL_GROUPS[group], group, m, d, rng, "home:their own households", delay)

static func _pool_infect(e: Dictionary, b: Dictionary, f: Dictionary, dis: String, bnd: String, group: String, n: int, d: int, rng: RandomNumberGenerator, src: String, delay: int = 0) -> void:
	var r := row(dis)
	var on := d + delay + rng.randi_range(int(r["inc"][0]), int(r["inc"][1]))
	var sd := rng.randi_range(int(r["sick"][0]), int(r["sick"][1]))
	var bc := float(f.get("pool_condition", {}).get(group, 1.0))
	var q := minf(0.9, float(r["death"][bnd]) * (1.0 + BODY_DEATH * (1.0 - bc)) * deadliness)
	# Remedies as the register buys them (_buy_remedy): the herbalist's real stock, the row's coin, two weeks of
	# grain kept back; a remedied case is sick remedy.days as long at remedy.death the daily risk.
	var R: Dictionary = data()["remedy"]
	var cured := _pool_remedies(e, f, n)
	var sd2 := maxi(1, int(ceilf(float(sd) * float(R["days"]))))
	if not f.has("psk"): f["psk"] = []
	if cured > 0:
		var die2 := _pool_deaths(rng, cured, 1.0 - pow(1.0 - q * float(R["death"]), float(sd2)))
		f["psk"].append([dis, bnd, cured, die2, on + maxi(1, sd2 / 2), on + sd2, false])
	if n > cured:
		var die := _pool_deaths(rng, n - cured, 1.0 - pow(1.0 - q, float(sd)))   # the daily risk over the sick days (as _death_day)
		f["psk"].append([dis, bnd, n - cured, die, on + maxi(1, sd / 2), on + sd, false])
	var was := int(b["act"].get(dis, 0))
	b["act"][dis] = was + n
	b["cases"][dis] = int(b["cases"].get(dis, 0)) + n
	(b["new"] as Array).append([d, dis, n])   # one entry for the batch (readers add x[2], 1 for a register case)
	_yr_n(b, float(d), 0, n)
	if was == 0: b["first"][dis] = [d, origin_text(src, float(d))]

static func _pool_deaths(rng: RandomNumberGenerator, n: int, p: float) -> int:
	if n <= 40:
		var die := 0
		for k in n:
			if rng.randf() < p: die += 1
		return die
	return clampi(int(round(rng.randfn(n * p, sqrt(n * p * (1.0 - p))))), 0, n)

## Remedies a cohort row buys for n new cases (TownEcon.family_buy: the herbalist's stock, coin to its till).
static func _pool_remedies(e: Dictionary, f: Dictionary, n: int) -> int:
	if int(e.get("stock", {}).get("remedy", 0)) <= 0: return 0
	var R: Dictionary = data()["remedy"]
	var price := float(e["price"].get("remedy", Goods.table().get("remedy", {}).get("price", 3.0 * TownEcon.COIN)))
	var reserve := float(Families.people(f)) * 2.0 * float(R["reserve_days"]) * float(e["price"].get("grain", 0.5 * TownEcon.COIN))
	var can := mini(n, int(floor((float(f["purse"]) - reserve) / maxf(0.01, price))))
	if can <= 0: return 0
	var got := TownEcon.family_buy(e, f, "remedy", can)
	if got <= 0: return 0
	e["hh"]["remedy"] = int(e["hh"].get("remedy", 0)) - got
	TownEcon.led(e, "used", "remedy", got)
	return got

## Cases due: their dead leave the row through the one population death path; the recovered become immune.
static func _pool_resolve(e: Dictionary, b: Dictionary, f: Dictionary, d: int, rng: RandomNumberGenerator) -> void:
	var keep: Array = []
	var died := 0
	var gone := bool(f.get("gone", false))
	for c in f["psk"]:
		var dis := String(c[0])
		if gone:   # the row died out or left: its open cases leave the town's counters
			_act_less(b, dis, int(c[2]) - (int(c[3]) if bool(c[6]) else 0))
			continue
		if not bool(c[6]) and int(c[4]) <= d:
			c[6] = true
			var killed := _pool_kill(e, f, String(c[1]), int(c[3]), float(c[4]), dis, rng)
			_act_less(b, dis, int(c[3]))
			if killed > 0:
				b["deaths"][dname(dis)] = int(b["deaths"].get(dname(dis), 0)) + killed
				_yr_n(b, float(c[4]), 1, killed)
				died += killed
		if int(c[5]) <= d:
			var well := int(c[2]) - int(c[3])
			_act_less(b, dis, well)
			var imm := float(row(dis).get("immune", 0))
			if imm != 0.0 and well > 0:
				if not f.has("pim"): f["pim"] = {}
				var until := NONE if imm < 0.0 else float(c[5]) + imm * year_days()
				var had: Array = f["pim"].get(dis, [0, 0.0])
				f["pim"][dis] = [int(had[0]) + well, maxf(float(had[1]), until)]
			continue
		keep.append(c)
	if keep.is_empty(): f.erase("psk")
	else: f["psk"] = keep
	if died > 0 and not gone:
		var tr := Time.get_ticks_usec() if prof_parts else 0
		if Families.people(f) <= 0: Families.extinct(e, f, float(d))
		else: Families.reassign(e, f)
		if prof_parts: _pf("pools reassign", tr)

## k of the row's anonymous residents of one age band die (bins picked by their size); returns how many died.
static func _pool_kill(e: Dictionary, f: Dictionary, bnd: String, k: int, day: float, dis: String, rng: RandomNumberGenerator) -> int:
	var want: Array = {"adult": [0, 1], "child": [3], "elder": [2]}[bnd]
	var killed := 0
	for i in k:
		var keys: Array = []
		var tot := 0
		for key in f.get("age_bins", {}):
			if want.has(Population.bin_category(e, f, String(key), day)):
				keys.append(key); tot += int(f["age_bins"][key])
		if tot <= 0: break
		var x := rng.randi() % tot
		for key in keys:
			x -= int(f["age_bins"][key])
			if x < 0:
				Population.kill_slots(e, f, String(key), 1, day, "sickness", dname(dis))
				killed += 1
				break
	return killed

## New cases from the household's conditions and from the town's sick (thinned Poisson over the register).
## span: the days this run covers (the per person-day rates x span; each case dated on one of those days).
static func _roll_town(game, t: Dictionary, e: Dictionary, b: Dictionary, d: int, rng: RandomNumberGenerator, span: int = 1, share: float = 1.0) -> void:
	var tf := _tf(e, b, d)
	var ec: Array = tf["ec"]
	var comps := []
	var tot := 0.0
	for i in ec.size():
		if float(ec[i]) > 0.0:
			comps.append([i, 0, float(ec[i])])
			tot += float(ec[i])
	var act: Dictionary = b["act"]
	if not act.is_empty():
		var pop := maxf(1.0, float(e["pop"]))
		for dis in act:
			var bt := float(row(dis).get("town", 0.0))
			if bt <= 0.0 or int(act[dis]) <= 0:
				continue
			var i := ids.find(dis)
			var ex := bt * float(act[dis]) * float(tf["sf"][i]) / pop * float(tf["mm"][i]) * float(tf["slots"])
			comps.append([i, 1, ex])
			tot += ex
	if tot <= 0.0:
		return
	var rms: Array = tf["rm"]
	var mms: Array = tf["mm"]
	var k := _poisson(rng, tot * float(span) * share)   # (two halves = one Poisson draw of the whole)
	if prof_parts:
		prof["#cand"] = int(prof.get("#cand", 0)) + k
	for j in k:
		var day := float(d - rng.randi() % span)   # the day of the covered span he catches it
		var x := rng.randf() * tot
		var cp: Array = comps[-1]
		for cc in comps:
			x -= float(cc[2])
			if x <= 0.0:
				cp = cc
				break
		var pk := _pick_reg(e, b, rng)
		if pk.is_empty():
			continue
		var f: Dictionary = pk[0]
		var p: Array = pk[1]
		var i: int = cp[0]
		var dis: String = ids[i]
		# accepted with his catch / the bound, then (conditions) with his home's K / its bound: two independent draws,
		# the same chance as one draw on the product, and the home is looked at only for those still in
		var acc := catch_m(f, p, dis, {}, day) * float(rms[i]) / float(mms[i])
		if acc <= 0.0 or rng.randf() >= acc:
			continue
		var r := row(dis)
		if int(cp[1]) == 0 and rng.randf() >= _k_reg(e, pk[3], int(pk[2]), r, float(tf["cloth"])) / float(tf["km"][i]):
			continue
		var src := "town:caught from the town's sick in %s" % t["name"]
		if int(cp[1]) == 0:
			src = "cond:" + cond_words(e, f, r, float(tf["room"]), float(tf["cloth"]))
		infect(game, t, f, p, dis, day, src, rng)

static func _run_queue(game, t: Dictionary, e: Dictionary, b: Dictionary, d: int, rng: RandomNumberGenerator) -> void:
	var q: Dictionary = b["q"]
	var k0 := int(b["qd"]) + 1
	if q.is_empty():
		b["qd"] = d
		return
	for k in range(k0, d + 1):
		b["qd"] = k   # events pushed while this day runs wait for the next
		var ks := str(k)
		if not q.has(ks):
			continue
		var due: Array = q[ks]
		q.erase(ks)
		if prof_parts:
			prof["#ev"] = int(prof.get("#ev", 0)) + due.size()
		for ev in due:   # (in the order they were queued: deterministic)
			if prof_parts:
				var te := Time.get_ticks_usec()
				_event(game, t, e, b, ev, d, rng)
				_pf("ev kind %d" % int(ev[1]), te)
				prof["#ev%d" % int(ev[1])] = int(prof.get("#ev%d" % int(ev[1]), 0)) + 1
			else:
				_event(game, t, e, b, ev, d, rng)

static func _event(game, t: Dictionary, e: Dictionary, b: Dictionary, ev: Array, d: int, rng: RandomNumberGenerator) -> void:
	var fams: Array = e["fams"]
	var fid := int(ev[2])
	if fid < 0 or fid >= fams.size():
		return
	var f: Dictionary = fams[fid]
	var pid := int(ev[3])
	var key := str(pid)
	var dis := String(ev[4])
	var c: Array = case_of(f, pid)
	match int(ev[1]):
		0:
			if c.is_empty() or String(c[C_DIS]) != dis:
				return
			if f["gone"]:
				_drop_case(e, b, f, key, c, _stop(c))
				return
			var nxt := _stop(c)
			if nxt > float(d):
				_push(b, [nxt, 0, fid, pid, dis, ""])
				return
			if float(c[C_DIE]) < 0.0:
				_recover(e, b, f, key, c, rng)
				return
			var p := Persons.by_pid(f, pid)
			if p.is_empty():
				_drop_case(e, b, f, key, c, nxt)
			else:
				kill(game, t, f, p, float(c[C_DIE]), "sickness", dname(dis))
		1:
			if f["gone"]:
				return
			var p2 := Persons.by_pid(f, pid)
			var src := String(ev[5])
			if p2.is_empty() or (not src.begins_with("relapse") and not (String(p2[4]) in HOME)):
				return
			infect(game, t, f, p2, dis, float(ev[0]), src, rng)
		2:
			if c.is_empty() or String(c[C_DIS]) != dis or int(c[C_BON]) == 1 or int(c[C_BIZ]) < 0 or _stop(c) <= float(d):
				return
			var bz: Dictionary = e["biz"][int(c[C_BIZ])]
			bz["sick"] = int(bz.get("sick", 0)) + 1
			c[C_BON] = 1

static func _recover(e: Dictionary, b: Dictionary, f: Dictionary, key: String, c: Array, rng: RandomNumberGenerator) -> void:
	var dis := String(c[C_DIS])
	var r := row(dis)
	var end := float(c[C_END])
	_drop_case(e, b, f, key, c, end)
	var rel: Array = r.get("relapse", [])
	if not rel.is_empty() and rng.randf() < float(rel[0]):
		_push(b, [end + float(rng.randi_range(int(rel[1]), int(rel[2]))), 1, int(f["id"]), int(key), dis, "relapse:a new bout of %s" % dname(dis)])
		return
	var imm := float(r["immune"])
	if imm != 0.0:
		if not f.has("im"):
			f["im"] = {}
		if not f["im"].has(key):
			f["im"][key] = {}
		f["im"][key][dis] = NONE if imm < 0.0 else end + imm * year_days()

## The case is over: the town's counters, the business's bed-ridden staff, the bed days his wage misses.
static func _drop_case(e: Dictionary, b: Dictionary, f: Dictionary, key: String, c: Array, upto: float) -> void:
	var dis := String(c[C_DIS])
	if int(c[C_CNT]) == 1:
		var n := int(b["act"].get(dis, 0)) - 1
		if n > 0:
			b["act"][dis] = n
		else:
			b["act"].erase(dis)
	var biz := int(c[C_BIZ])
	if int(c[C_BON]) == 1 and biz >= 0 and biz < (e["biz"] as Array).size():
		var bz: Dictionary = e["biz"][biz]
		bz["sick"] = maxi(0, int(bz.get("sick", 0)) - 1)
	if int(c[C_BED]) == 1 and biz >= 0:
		var wage_start := maxf(float(c[C_ON]), float(e.get("wage_day", e.get("day", 0))))
		var wage_stop := minf(_stop(c), upto)
		if wage_stop > wage_start:
			if not f.has("wage_bed"): f["wage_bed"] = []
			f["wage_bed"].append([biz, wage_start, wage_stop])
		var ov := minf(_stop(c), upto) - maxf(float(c[C_ON]), float(f["last"]))
		if ov > 0.0:
			if not f.has("skd"):
				f["skd"] = {}
			f["skd"][str(biz)] = float(f["skd"].get(str(biz), 0.0)) + ov
	f["sk"].erase(key)
	if (f["sk"] as Dictionary).is_empty():
		f.erase("sk")

# ================================================================== deaths
## He dies: the existing death rules (his record leaves the register, his row count with him, the service count,
## the family's memory and history, the house dies out with the last of it: property to the state), his own life
## history, the census. cause "sickness" (detail = the disease), "starved", or "childbirth" (Persons.childbed: a mother
## who dies bearing her child; the same death path, the census once).
static func kill(game, t: Dictionary, f: Dictionary, p: Array, day: float, cause: String, detail: String) -> void:
	var t0 := Time.get_ticks_usec() if prof_parts else 0
	_kill(game, t, f, p, day, cause, detail)
	if prof_parts: _pf("kill (nested) " + cause, t0)

static func _kill(game, t: Dictionary, f: Dictionary, p: Array, day: float, cause: String, detail: String) -> void:
	var e: Dictionary = t["econ"]
	var b := book(e)
	var race := Persons.race_of(e)
	var pid := int(p[0])
	var key := str(pid)
	var nm := Persons.name_of(f, p, race)
	var age := Persons.age_of(p, day)
	var sex := int(p[2])
	var st := String(p[4])
	var c := case_of(f, pid)
	if not c.is_empty():
		_drop_case(e, b, f, key, c, day)
	var why := ("died of " + detail) if cause == "sickness" else ("died in childbirth" if cause == "childbirth" else "starved to death")
	if int(p[5]) >= 0:
		_remove_unit(game, t, f, p, st, int(p[5]), "%s %s." % [nm, why])
	Persons.log_life(p, day, "died", why)
	if int(p[6]) == 2:
		Persons.forget(e, f, p)
		Persons.kp(f).erase(p)
		f["kids"] = maxi(0, int(f["kids"]) - 1)
		e["pop"] = int(e["pop"]) - 1
	else:
		var s := "old" if int(p[6]) == 1 else ("m" if sex == 0 else "f")
		Persons.forget(e, f, p)
		Persons.pp(f).erase(p)
		if st != "company" and int(f[s]) > 0:
			f[s] = int(f[s]) - 1
			e["pop"] = int(e["pop"]) - 1
			if s != "old":
				e["adults"] = int(e["adults"]) - 1
		if st in SERVICE:
			var sv: Dictionary = f["serve"]
			if int(sv.get(st, 0)) > 0:
				sv[st] = int(sv[st]) - 1
				if int(sv[st]) <= 0:
					sv.erase(st)
	if f.has("dp") and not (f["dp"] as Array).is_empty() and int(f["dp"][-1][0]) == pid:
		f["dp"][-1].append(cause + ": " + detail)   # the remembered dead keep the cause
	if f.has("bc"):
		if (f["bc"] as Dictionary).has(key):
			b["lowbc"] = maxi(0, int(b.get("lowbc", 0)) - 1)
		f["bc"].erase(key)
		if (f["bc"] as Dictionary).is_empty():
			f.erase("bc")
	if f.has("im"):
		f["im"].erase(key)
	if st != "company":
		e["stats"]["deaths"] = int(e["stats"].get("deaths", 0)) + 1
	f["named"] = true
	Families.add_hist(f, "%s %s." % [nm, why], day)
	Families.event(f, {"sickness": "sick_died", "childbirth": "childbed"}.get(cause, "starved"), [nm, detail, "f" if sex == 1 else "m"], day)
	Census.person_died(e, f, p, day, cause, detail, st != "company")
	if cause == "sickness":
		b["deaths"][detail] = int(b["deaths"].get(detail, 0)) + 1
		_yr(b, day, 1)
	elif cause == "starved":
		b["starved"] = int(b.get("starved", 0)) + 1
		_yr(b, day, 2)
	if st != "company":
		Families.reassign(e, f)
		if Families.people(f) <= 0:
			Families.extinct(e, f, day)

## His Unit leaves wherever it serves (the company, the recruit pool, the militia, a force or a caravan).
static func _remove_unit(game, t: Dictionary, _f: Dictionary, p: Array, st: String, uid: int, line: String) -> void:
	if game == null:
		return
	var w: Dictionary = game.world
	if st == "reserve":
		var reserve: Unit = Mobilization.reserve_unit(game, uid, String(t.get("id", "")), int(_f.get("id", -1)))
		if reserve != null and is_same(Persons.by_uid(_f, uid), p):
			reserve.dead = true
			Mobilization.reserve_died(game, reserve)
			return
	match st:
		"company":
			var u: Unit = game.unit_by_uid(uid)
			if u != null:
				Mobilization.natural_death(game, u)
				u.dead = true
				game.company.erase(u)
				game.squads.erase(uid)
				for x in game.company:
					if x.squad == uid:
						x.squad = -1
				game.invalidate_deploy()
				CampaignWorld.log_event(game, line)
			return
		"hire":
			var rec: Array = t.get("recruits", [])
			for i in rec.size():
				if rec[i] is Unit and rec[i].uid == uid:
					rec.remove_at(i)
					return
			return
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		var units: Array = wb["units"]
		for i in units.size():
			if units[i].uid != uid:
				continue
			units[i].dead = true
			units.remove_at(i)
			if wb.has("crew"):
				var crew: Array = wb["crew"]
				for j in crew.size():
					if crew[j].size() > 3 and int(crew[j][3]) == uid:
						crew.remove_at(j)
						break
			if w.has("army"):
				Army.state(w)["roll"].erase(str(uid))
			return
	p[5] = -1

# ================================================================== the weekly family turn (Families.turn)
## Called at the start of the family's weekly turn (before its stores run down and its wages are paid): remedies,
## the bed-ridden days the wage code subtracts (paid_days). Returns true when the family is gone (the turn stops).
## (The body meter runs later in the turn, once the family's hunger is known: body_turn.)
static func family_turn(game, town: Dictionary, e: Dictionary, f: Dictionary, day: float) -> bool:
	if not f.has("pp"):
		return false
	var t0 := Time.get_ticks_usec() if prof_on else 0
	var days := clampf(day - float(f["last"]), 1.0, 60.0)
	if not f["gone"] and (f.has("sk") or f.has("skd")):
		_cases_turn(game, town, e, f, day, days)
	elif f.has("skw"):
		f.erase("skw")
	if prof_on:
		if prof_parts:
			_pf("fam cases", t0)
		us += Time.get_ticks_usec() - t0
	return bool(f["gone"])

## The body meter (6b) over the family's turn, from its hunger this turn (food_short_days: the family turn has just set
## f.fshort). The only place anyone dies "starved". Returns true when the family is gone.
static func body_turn(game, town: Dictionary, e: Dictionary, f: Dictionary, day: float, days: float) -> bool:
	if not f.has("pp"):
		return false
	var t0 := Time.get_ticks_usec() if prof_on else 0
	var short := food_short_days(e, f, day, days)
	if short > 0.0 or f.has("bc"):
		_body(game, town, e, f, day, days, short)
	if prof_on:
		if prof_parts:
			_pf("fam body", t0)
		us += Time.get_ticks_usec() - t0
	return bool(f["gone"])

## Worker-days the wage code pays for the family's job at business k: wd less his bed-ridden days (a bed-ridden
## man draws no wage; the family's income drops by exactly that wage).
static func paid_days(f: Dictionary, k, wd: float) -> float:
	if not f.has("skw"):
		return wd
	return maxf(0.0, wd - float(f["skw"].get(str(k), 0.0)))

static func _cases_turn(game, town: Dictionary, e: Dictionary, f: Dictionary, day: float, days: float) -> void:
	var last := day - days
	var skw := {}
	if f.has("skd"):
		skw = (f["skd"] as Dictionary).duplicate()
		f.erase("skd")
	# a remedy only when the market has one and the family can afford it after reserve_days of food (checked once)
	var stock := int(e["stock"].get("remedy", 0)) > 0
	if stock:
		var reserve := float(Families.people(f)) * 2.0 * float(data()["remedy"]["reserve_days"]) * float(e["price"].get("grain", 0.5 * TownEcon.COIN))
		stock = float(f["purse"]) - float(e["price"].get("remedy", 3.0 * TownEcon.COIN)) >= reserve
	if f.has("sk"):
		for key in (f["sk"] as Dictionary).keys():
			var c: Array = f["sk"][key]
			var biz := int(c[C_BIZ])
			if int(c[C_BED]) == 1 and biz >= 0:
				var ov := minf(_stop(c), day) - maxf(float(c[C_ON]), last)
				if ov > 0.0:
					skw[str(biz)] = float(skw.get(str(biz), 0.0)) + ov
			if stock and int(c[C_REM]) == 0 and int(c[C_CNT]) == 1 and sick_phase(c, day):
				var p := Persons.by_pid(f, int(key))
				if not p.is_empty() and String(p[4]) in HOME:
					_buy_remedy(game, town, e, f, int(key), c, day)
	if skw.is_empty():
		f.erase("skw")
	else:
		f["skw"] = skw

## A family buys a remedy for its sick (if it can afford one after reserve_days of food); used at once.
static func _buy_remedy(game, town: Dictionary, e: Dictionary, f: Dictionary, pid: int, c: Array, day: float) -> bool:
	if int(e["stock"].get("remedy", 0)) <= 0:
		return false
	var R: Dictionary = data()["remedy"]
	var price := float(e["price"].get("remedy", Goods.table().get("remedy", {}).get("price", 3.0 * TownEcon.COIN)))
	var reserve := float(Families.people(f)) * 2.0 * float(R["reserve_days"]) * float(e["price"].get("grain", 0.5 * TownEcon.COIN))
	if float(f["purse"]) - price < reserve:
		return false
	var n := TownEcon.family_buy(e, f, "remedy", 1)
	if n <= 0:
		return false
	e["hh"]["remedy"] = int(e["hh"].get("remedy", 0)) - n
	TownEcon.led(e, "used", "remedy", n)
	var p := Persons.by_pid(f, pid)
	apply_remedy(e, f, pid, c, day, _find_unit(game, town, p) if not p.is_empty() else null)
	return true

## A remedy given on `day`: the rest of his sick days x remedy.days, his death chance per day x remedy.death from
## now on (same death roll: a remedy never makes it worse).
static func apply_remedy(e: Dictionary, f: Dictionary, pid: int, c: Array, day: float, u: Unit = null) -> void:
	var R: Dictionary = data()["remedy"]
	c[C_REM] = 1
	var on := float(c[C_ON])
	var start := maxf(day, on)
	var end := float(c[C_END])
	var new_end := start + ceilf((end - start) * float(R["days"]))
	var q := float(c[C_Q])
	var uu := float(c[C_U])
	var die := -1.0
	if q > 0.0:
		var a := start - on
		var surv := pow(1.0 - q, a)
		if 1.0 - surv >= uu:
			die = start + 1.0
		else:
			var q2 := q * float(R["death"])
			var k := maxf(ceilf(a), ceilf(a + log((1.0 - uu) / surv) / log(1.0 - q2)))
			k = maxf(1.0, k)
			if on + k <= new_end:
				die = on + k
	c[C_END] = new_end
	c[C_DIE] = die
	if not e.is_empty():
		_push(book(e), [_stop(c), 0, int(f["id"]), pid, String(c[C_DIS]), ""])
	if u != null:
		mirror(u, c)

# ------------------------------------------------------------------ 6b: the body-condition meter
## Each day the family goes short, its people's condition falls (children, elders, the sick and nursing mothers
## faster); fed days refill it; the family shares what it has in its culture's order (default: workers, then
## children, then elders). At 0 he dies, "starved".
static func _body(game, town: Dictionary, e: Dictionary, f: Dictionary, day: float, days: float, short: float) -> void:
	var B: Dictionary = data()["body"]
	var b := book(e)
	if short <= 0.0:   # a fed family: everyone below full condition refills (no shares to work out)
		var bc0: Dictionary = f["bc"]
		var add := float(B["refill"]) * days
		for key in bc0.keys():
			var v0 := float(bc0[key]) + add
			if v0 >= 1.0:
				bc0.erase(key)
				b["lowbc"] = maxi(0, int(b.get("lowbc", 0)) - 1)
			else:
				bc0[key] = v0
		if bc0.is_empty():
			f.erase("bc")
		return
	var groups := {"workers": [], "children": [], "elders": []}
	for p in Persons.pp(f):
		if String(p[4]) in HOME:
			(groups["elders"] if int(p[6]) == 1 else groups["workers"]).append(p)
	for p in Persons.kp(f):
		groups["children"].append(p)
	var n := float(groups["workers"].size() + groups["children"].size() + groups["elders"].size())
	if n <= 0.0:
		return
	var food := (1.0 - short / days) * n
	var EO: Dictionary = data()["eat_order"]
	var order: Array = EO.get(String(e.get("culture", "")), EO["_default"])
	var fed := {}
	for g in order:
		var need := float((groups[g] as Array).size())
		var got := clampf(food, 0.0, need)
		fed[g] = got / need if need > 0.0 else 1.0
		food -= got
	var old: Dictionary = f.get("bc", {})
	var bc := {}
	var dead := []
	var fall := float(B["fall"]); var refill := float(B["refill"]); var weak := float(B["weak"])
	for g in groups:
		var x := float(fed.get(g, 1.0))
		for p in groups[g]:
			var key := str(p[0])
			var v := float(old.get(key, 1.0))
			if x >= 0.999:
				v += refill * days
			else:
				var m := weak if g != "workers" or _weak(f, p, day) else 1.0
				v -= fall * m * (1.0 - x) * days
			if v <= 0.0:
				dead.append(p)
			elif v < 1.0:
				bc[key] = v
				if v < float(b.get("bcw", 1.0)):
					b["bcw"] = v
					if v < float(b.get("tf", {}).get("bcmin", 1.0)):
						_lower_bc_bound(b["tf"], v)   # the town's catch bound must cover him
	b["lowbc"] = maxi(0, int(b.get("lowbc", 0)) + bc.size() - old.size())
	if bc.is_empty():
		f.erase("bc")
	else:
		f["bc"] = bc
	for p in dead:
		if f["gone"]:
			break
		if f.has("bc"):
			f["bc"][str(p[0])] = 0.0
			b["lowbc"] = int(b["lowbc"]) + 1
		else:
			f["bc"] = {str(p[0]): 0.0}
			b["lowbc"] = int(b["lowbc"]) + 1
		kill(game, town, f, p, day, "starved", "hunger")

## A worker who falls faster: sick now, or a nursing mother (a child of hers under a year old).
static func _weak(f: Dictionary, p: Array, day: float) -> bool:
	var c := case_of(f, int(p[0]))
	if not c.is_empty() and sick_phase(c, day):
		return true
	if int(p[2]) != 1:
		return false
	for k in Persons.kp(f):
		if int(Persons.g(k, Persons.MO, -1)) == int(p[0]) and day - float(k[3]) < year_days():
			return true
	return false

static func body_condition(f: Dictionary, pid: int) -> float:
	return float(f.get("bc", {}).get(str(pid), 1.0))

# ================================================================== carriers
## A caravan reaches a market (Caravans.arrive): its shedding crew pass their diseases to the town, the crew catch
## what the town has, the crew pass it among themselves over the trip, and the town hears of the outbreaks back
## where the caravan came from (Roads: from caravan word, not omniscient).
static func caravan_at(game, wb: Dictionary, dest: Dictionary) -> void:
	if not TownEcon.has_econ(dest):
		return
	var t0 := Time.get_ticks_usec() if prof_on else 0
	data()
	var w: Dictionary = game.world
	var origin: Dictionary = w["towns"].get(String(wb.get("origin", "")), {})
	if not TownEcon.has_econ(origin):
		return
	var day := float(game.day)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(wb.get("id", "")), int(day), "skc"])
	var ob: Dictionary = book(origin["econ"])["act"]
	var db := book(dest["econ"])
	if not ob.is_empty():
		db["news"][String(origin["id"])] = [int(day), ob.duplicate()]
	elif db["news"].has(String(origin["id"])):
		db["news"].erase(String(origin["id"]))
	var crew := _crew(wb, origin)
	if crew.is_empty():
		return
	var stay := float(data()["carrier"]["stay"])
	var good := _main_good(wb)
	for cr in crew:
		var c := case_of(cr[1], int(cr[2][0]))
		if not c.is_empty() and shedding(c, day):
			seed_town(game, dest, String(c[C_DIS]), stay, rng, "carrier:came with the %scaravan from %s, day %d" % [good, origin["name"], int(day) + 1])
	for cr in crew:
		catch_in_town(game, cr[0], cr[1], cr[2], dest, stay, rng, cr[3])
	var trip := clampf(day - float(wb.get("depart_day", day)), 1.0, 30.0)
	for cr in crew:
		var c2 := case_of(cr[1], int(cr[2][0]))
		if c2.is_empty() or not shedding(c2, day):
			continue
		var r := row(String(c2[C_DIS]))
		var bw := float(r["work"])
		if bw <= 0.0:
			continue
		for cr2 in crew:
			if cr2 == cr:
				continue
			var lam := bw * catch_m(cr2[1], cr2[2], String(c2[C_DIS]), r, day) * race_mult(r, Persons.race_of(cr2[0]["econ"]))
			if lam > 0.0 and rng.randf() < 1.0 - exp(-lam * trip):
				infect(game, cr2[0], cr2[1], cr2[2], String(c2[C_DIS]), day, "crew:%s of the caravan crew" % Persons.name_of(cr[1], cr[2], Persons.race_of(cr[0]["econ"])), rng, cr2[3])
	if prof_on:
		us += Time.get_ticks_usec() - t0

static func _main_good(wb: Dictionary) -> String:
	var gd: Dictionary = wb.get("cargo", {}).get("goods", {})
	var best := ""
	var most := 0
	for g in gd:
		if int(gd[g]) > most:
			most = int(gd[g])
			best = String(g)
	return (Goods.good_name(best) + " ") if best != "" else ""

## The crew of a caravan as register people: [[home town, family, person, unit or null]].
static func _crew(wb: Dictionary, origin: Dictionary) -> Array:
	var out := []
	var used := {}
	for cw in wb.get("crew", []):
		var f := People.fam_of(origin, int(cw[0]))
		if f.is_empty() or f["gone"]:
			continue
		var uid := int(cw[3]) if cw.size() > 3 else -1
		var p: Array = []
		if uid >= 0:
			p = Persons.by_uid(f, uid)
		else:
			for q in Persons.pp(f):
				if String(q[4]) == "caravan" and int(q[5]) < 0 and not used.has(int(q[0])):
					p = q
					break
		if p.is_empty():
			continue
		used[int(p[0])] = true
		var u: Unit = null
		if uid >= 0:
			for x in wb.get("units", []):
				if x.uid == uid:
					u = x
		out.append([origin, f, p, u])
	return out

## A carrier of `dis` spends stay days in town t: the town's people meet him (a thinned draw over the register,
## each at his own catch). The town's first case of an outbreak records src. Returns the cases started.
static func seed_town(game, t: Dictionary, dis: String, stay: float, rng: RandomNumberGenerator, src: String) -> int:
	if not TownEcon.has_econ(t):
		return 0
	var e: Dictionary = t["econ"]
	var b := book(e)
	var r := row(dis)
	var bt := float(r.get("town", 0.0))
	if bt <= 0.0:
		return 0
	var day := float(game.day) if game != null else float(e.get("day", 0))
	var tf := _tf(e, b, int(day))
	var i := ids.find(dis)
	var mx := float(tf["mm"][i])
	var k := _poisson(rng, bt * stay / maxf(1.0, float(e["pop"])) * mx * float(tf["slots"]))
	var n := 0
	var rm := race_mult(r, String(tf["race"]))
	for j in k:
		var pk := _pick_reg(e, b, rng)
		if pk.is_empty():
			continue
		if rng.randf() < catch_m(pk[0], pk[1], dis, r, day) * rm / mx:
			if infect(game, t, pk[0], pk[1], dis, day, src, rng):
				n += 1
	return n

## A visitor (crew, soldier, company man: person p of family f, register in home town ht) catches what town t has
## over stay days (the town's share of people passing it on).
static func catch_in_town(game, ht: Dictionary, f: Dictionary, p: Array, t: Dictionary, stay: float, rng: RandomNumberGenerator, u: Unit = null) -> bool:
	if not TownEcon.has_econ(t):
		return false
	var b := book(t["econ"])
	var act: Dictionary = b["act"]
	if act.is_empty():
		return false
	var day := float(game.day) if game != null else float(t["econ"].get("day", 0))
	var pop := maxf(1.0, float(t["econ"]["pop"]))
	var race := Persons.race_of(ht["econ"])
	for dis in act:
		var r := row(dis)
		var lam := float(r.get("town", 0.0)) * float(act[dis]) * _shed_share(r) / pop * catch_m(f, p, dis, r, day) * race_mult(r, race)
		if lam > 0.0 and rng.randf() < 1.0 - exp(-lam * stay):
			return infect(game, ht, f, p, dis, day, "town:caught in %s" % t["name"], rng, u)
	return false

## A man back home from service (People.release): an open case now counts in his town, and his household is
## exposed for the rest of it. A town with no case of it yet records where it came from.
static func came_home(town: Dictionary, f: Dictionary, p: Array) -> void:
	if not f.has("sk") or not TownEcon.has_econ(town):
		return
	var c := case_of(f, int(p[0]))
	if c.is_empty() or int(c[C_CNT]) == 1:
		return
	var e: Dictionary = town["econ"]
	var day := float(e.get("day", 0))
	if _stop(c) <= day:
		return
	c[C_CNT] = 1
	var b := book(e)
	var dis := String(c[C_DIS])
	var was := int(b["act"].get(dis, 0))
	b["act"][dis] = was + 1
	if was == 0:
		b["first"][dis] = [int(day), "came home with %s from service (%s), day %d" % [Persons.name_of(f, p, Persons.race_of(e)), origin_text(String(c[C_SRC]), float(c[C_T0])), int(day) + 1]]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(p[0]), int(day), "skh"])
	_household(null, town, e, b, f, p, c, rng)

## A person moves from family a to family b of the same town (a bride, Persons.marriages): her open case, her
## immunity and her body condition go with her (her case's end is queued under her new family).
static func moved(e: Dictionary, a: Dictionary, b: Dictionary, pid: int) -> void:
	var key := str(pid)
	for k in ["sk", "im", "bc"]:
		if not a.has(k) or not (a[k] as Dictionary).has(key):
			continue
		if not b.has(k):
			b[k] = {}
		b[k][key] = a[k][key]
		a[k].erase(key)
		if (a[k] as Dictionary).is_empty():
			a.erase(k)
	var c := case_of(b, pid)
	if not c.is_empty():
		_push(book(e), [_stop(c), 0, int(b["id"]), pid, String(c[C_DIS]), ""])

## A whole family walks to another town (Barge.move_family; its people re-numbered there, remap old pid -> new pid):
## the old town's book lets its open cases go (counters, bed-ridden staff, the bed days the old wage code missed), the
## new family takes its cases, immunities and body condition under the new numbers, and the new town's book counts
## the open cases and queues their ends (they left their jobs: no business is short of them now).
static func family_moved(e: Dictionary, e2: Dictionary, f: Dictionary, nf: Dictionary, remap: Dictionary, day: float) -> void:
	var b := book(e)
	if f.has("sk"):
		for key in (f["sk"] as Dictionary).keys():
			_drop_case(e, b, f, key, f["sk"][key], day)
	if f.has("bc"):
		b["lowbc"] = maxi(0, int(b.get("lowbc", 0)) - (f["bc"] as Dictionary).size())
	for k in ["sk", "im", "bc", "skw", "skd"]:
		f.erase(k)
	nf.erase("skw"); nf.erase("skd")
	for k in ["im", "bc"]:
		if not nf.has(k):
			continue
		var out := {}
		for key in nf[k]:
			if remap.has(int(key)):
				out[str(int(remap[int(key)]))] = nf[k][key]
		if out.is_empty():
			nf.erase(k)
		else:
			nf[k] = out
	var b2 := book(e2)
	if nf.has("bc"):
		b2["lowbc"] = int(b2.get("lowbc", 0)) + (nf["bc"] as Dictionary).size()
		for key in nf["bc"]:
			var v := float(nf["bc"][key])
			if v < float(b2.get("bcw", 1.0)):
				b2["bcw"] = v
				if b2.has("tf") and v < float(b2["tf"].get("bcmin", 1.0)):
					_lower_bc_bound(b2["tf"], v)   # the town's catch bound must cover him
	if not nf.has("sk"):
		return
	var sk := {}
	for key in nf["sk"]:
		var c: Array = nf["sk"][key]
		if not remap.has(int(key)) or _stop(c) <= day:
			continue
		var pid := int(remap[int(key)])
		c[C_BIZ] = -1
		c[C_BON] = 0
		sk[str(pid)] = c
		if int(c[C_CNT]) == 1:
			var dis := String(c[C_DIS])
			b2["act"][dis] = int(b2["act"].get(dis, 0)) + 1
		_push(b2, [_stop(c), 0, int(nf["id"]), pid, String(c[C_DIS]), ""])
	if sk.is_empty():
		nf.erase("sk")
	else:
		nf["sk"] = sk

## The rare world event: a traveller from beyond the map edge brings a contact-only disease into the town nearest
## the edge (logged). A world marked sk_isolated never has one (tests).
static func _edge(game, d: int, rng: RandomNumberGenerator) -> void:
	var w: Dictionary = game.world
	if w.get("sk_isolated", false):
		return
	var ED: Dictionary = data().get("edge", {})
	for dis in ED:
		if rng.randf() >= float(ED[dis]):
			continue
		var t := edge_town(w)
		if t.is_empty():
			continue
		var e: Dictionary = t["econ"]
		var src := "edge:a traveller from beyond the map edge, day %d" % (d + 1)
		for tries in 64:
			var pk := _pick(e, rng, NMAX)
			if pk.is_empty() or int(pk[1][6]) != 0:
				continue
			if infect(game, t, pk[0], pk[1], String(dis), float(d), src, rng):
				CampaignWorld.log_event(game, "A traveller from beyond the edge of the map brought %s to %s." % [dname(String(dis)), t["name"]])
				TownEcon.town_hist(e, "A traveller from beyond the map's edge brought %s." % dname(String(dis)), float(d))
				break

## The town (with an economy) nearest the map's edge.
static func edge_town(w: Dictionary) -> Dictionary:
	var mw := float(w.get("w", WorldGen.W)) * float(w.get("cell", WorldGen.CELL))
	var mh := float(w.get("h", WorldGen.H)) * float(w.get("cell", WorldGen.CELL))
	var best: Dictionary = {}
	var bd := INF
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var pos: Vector2 = t["pos"]
		var dd := minf(minf(pos.x, mw - pos.x), minf(pos.y, mh - pos.y))
		if dd < bd:
			bd = dd
			best = t
	return best

# ================================================================== forces and the company
## A force's weekly turn: camp sickness (in the field; worse on short stores), what the sick pass on inside the
## force, and a force camped near a town trades its diseases with the town. Militia live at home (the family
## turn and the garrison contact); caravans at their markets (caravan_at).
static func _force_turn(game, wb: Dictionary, d: int) -> void:
	if not Army.is_people_band(wb) or String(wb.get("kind", "")) in ["militia", "caravan"]:
		return
	var w: Dictionary = game.world
	if not w.has("army"):
		return
	var roll: Dictionary = Army.state(w)["roll"]
	var men := []
	for u in wb["units"]:
		if not u.dead and roll.has(str(u.uid)):
			men.append(u)
	if men.is_empty():
		return
	var day := float(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(wb["id"]), d, "skf"])
	var short := clampf(1.0 - Supplies.days(wb) / 3.0, 0.0, 1.0)
	var near := _near_town(w, wb)
	var cl := String(near.get("econ", {}).get("climate", "temperate")) if not near.is_empty() else "temperate"
	var fw := Army.force_word(w, wb)
	_group_turn(game, men, day, 7.0, rng, "camp", short, cl, "camp:the camp of %s in the field" % fw, "camp:the sick of %s" % fw, roll)
	if not near.is_empty():
		var stay := float(data()["carrier"]["stay"])
		var src := "carrier:came with %s's soldiers, day %d" % [CampaignWorld.faction_the(String(wb["faction"])), d + 1]
		for u in men:
			if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
				seed_town(game, near, u.sick, stay, rng, src)
		for u in men:
			var pr := _person_of(w, u, roll)
			if not pr.is_empty():
				catch_in_town(game, pr[0], pr[1], pr[2], near, stay, rng, u)

static func _near_town(w: Dictionary, wb: Dictionary) -> Dictionary:
	var px := float(data()["carrier"]["near_px"])
	var pos: Vector2 = wb.get("pos", Vector2.ZERO)
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t) and (t["pos"] as Vector2).distance_to(pos) <= px:
			return t
	return {}

## [home town, family, person] of a unit (force roll entry or his own home town and family), [] when none.
static func _person_of(w: Dictionary, u: Unit, roll: Dictionary = {}) -> Array:
	var tid := u.home_town
	var fid := u.family
	if roll.has(str(u.uid)):
		tid = String(roll[str(u.uid)][0])
		fid = int(roll[str(u.uid)][1])
	var t: Dictionary = w.get("towns", {}).get(tid, {})
	var f := People.fam_of(t, fid)
	if f.is_empty() or f["gone"]:
		return []
	var p := Persons.by_uid(f, u.uid)
	if p.is_empty():
		return []
	return [t, f, p]

## Rolls a group of men (a force, the company) over `days`: the row's "camp" conditions (where == camp: base x
## season x climate x (1 + hunger x short)), contact with the group's own shedding sick (rate "camp" x their
## share), and (in town) the town's own conditions and sick. Each man's risk is summed over the rows; one roll.
static func _group_turn(game, men: Array, day: float, days: float, rng: RandomNumberGenerator, mode: String, short: float, cl: String,
		src_cond: String, src_contact: String, roll: Dictionary = {}, town: Dictionary = {}) -> void:
	var w: Dictionary = game.world
	var si := Calendar.season_index(day)
	var n := float(men.size())
	var shed := {}
	for u in men:
		if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
			shed[u.sick] = int(shed.get(u.sick, 0)) + 1
	var lam := []   # per disease: [cond rate, contact rate] per man-day before his own multiplier
	var any := false
	var tf: Dictionary = {}
	var tact: Dictionary = {}
	var tpop := 1.0
	if not town.is_empty():
		tf = _tf(town["econ"], book(town["econ"]), int(day))
		tact = book(town["econ"])["act"]
		tpop = maxf(1.0, float(town["econ"]["pop"]))
	for i in ids.size():
		var r := row(ids[i])
		var lc := 0.0
		if String(r["where"]) == mode:
			lc = float(r["base"]) * float(r["season"][si]) * float(r["climate"].get(cl, 1.0)) * (1.0 + float(r["hunger"]) * short)
		elif not tf.is_empty() and String(r["where"]) == "town":
			lc = float(tf["T"][i])   # lodging in town: the town's conditions at an ordinary roof (K = 1)
		var lk := float(r["camp"]) * float(shed.get(ids[i], 0)) / n
		if not tact.is_empty():
			lk += float(r.get("town", 0.0)) * float(tact.get(ids[i], 0)) * float(tf["sf"][i]) / tpop
		lam.append([lc, lk])
		if lc > 0.0 or lk > 0.0:
			any = true
	if not any:
		return
	var by_race := {}   # a man's risk by disease depends only on his race here: [parts, total, chance] per race
	for u in men:
		if u.sick != "" and day < u.sick_to:
			continue
		if not by_race.has(u.race):
			var tt := 0.0
			var pp2 := []
			for i in ids.size():
				var l: Array = lam[i]
				if float(l[0]) <= 0.0 and float(l[1]) <= 0.0:
					pp2.append(0.0)
					continue
				var r2 := row(ids[i])
				var v := (float(l[0]) + float(l[1])) * float(CATCH[ids[i]][0]) * race_mult(r2, u.race)
				pp2.append(v)
				tt += v
			by_race[u.race] = [pp2, tt, 1.0 - exp(-tt * days)]
		var rr: Array = by_race[u.race]
		var parts: Array = rr[0]
		var tot: float = rr[1]
		if tot <= 0.0 or rng.randf() >= float(rr[2]):
			continue
		var x := rng.randf() * tot
		var i2 := 0
		for i in parts.size():
			x -= float(parts[i])
			if x <= 0.0:
				i2 = i
				break
		var pr := _person_of(w, u, roll)
		if pr.is_empty():
			continue
		var l2: Array = lam[i2]
		var src := src_cond if rng.randf() * (float(l2[0]) + float(l2[1])) < float(l2[0]) else src_contact
		if src == src_cond and not town.is_empty() and String(row(ids[i2])["where"]) == "town":
			src = "cond:%s; lodging in %s" % [String(row(ids[i2]).get("spread", "")), town["name"]]
		elif src == src_contact and not tact.is_empty() and float(row(ids[i2]).get("town", 0.0)) * float(tact.get(ids[i2], 0)) > 0.0 and rng.randf() < 0.5:
			src = "town:caught in %s" % town["name"]
		infect(game, pr[0], pr[1], pr[2], ids[i2], day, src, rng, u)

## The company's day: in town it lodges at the town's risk and passes its own sick on; in the field camp sickness
## and contact among the men; wound rot on untreated open wounds (each man once a week). Not during the years before.
static func _company_day(game, d: int) -> void:
	if game.company.is_empty():
		return
	var w: Dictionary = game.world
	if w.has("presim") and not w["presim"].get("finished", false):
		return
	var men: Array = game.company.filter(func(u): return not u.dead)
	if men.is_empty():
		return
	var day := float(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), d, "skco"])
	var town: Dictionary = w["towns"].get(String(game.location), {}) if String(game.location) != "" else {}
	if not TownEcon.has_econ(town):
		town = {}
	var short := 0.0
	for u in men:
		match Food.belly_state(u.belly):
			"hungry": short += 0.5
			"starving": short += 1.0
	short /= float(men.size())
	var cl := String(town.get("econ", {}).get("climate", "temperate")) if not town.is_empty() else "temperate"
	_group_turn(game, men, day, 1.0, rng, "town_lodging" if not town.is_empty() else "camp", short, cl,
		"camp:the company's camp in the field", "camp:the company's own sick", {}, town)
	if not town.is_empty():
		var stay := float(data()["carrier"]["stay"])
		for u in men:
			if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
				seed_town(game, town, u.sick, stay, rng, "carrier:came with the mercenary company, day %d" % (d + 1))
	# wound rot: open wounds no healer has treated (a town healer's treatment cleans and binds them)
	var R := row("wound_rot")
	if R.is_empty():
		return
	for u in men:
		if (u.uid + d) % 7 != 0 or (u.sick != "" and day < u.sick_to):
			continue
		var nw := open_wounds(u)
		if nw <= 0:
			continue
		if rng.randf() < 1.0 - pow(1.0 - float(R["base"]), 7.0 * float(nw)):
			var pr := _person_of(w, u)
			if not pr.is_empty():
				infect(game, pr[0], pr[1], pr[2], "wound_rot", day, "wound:%d untreated open wound%s" % [nw, "" if nw == 1 else "s"], rng, u)

const OPEN_KINDS := ["cut", "pierced", "torn", "mangled", "broken"]
## Open wounds (cut, pierced, torn, mangled skin or flesh still healing) that no healer has treated.
static func open_wounds(u: Unit) -> int:
	if u.body == null:
		return 0
	var n := 0
	for pid in u.body.parts:
		# v0.013: guts spilled (DF UNDER_PRESSURE) are an open wound until a healer treats them or they mend
		if u.body.parts[pid].get("spilled", false):
			var gl: Dictionary = u.body.parts[pid]["layers"][0]
			if not gl.has("treated") and float(gl.get("heal_days", 0.0)) > 0.0:
				n += 1
				continue
		for l in u.body.parts[pid]["layers"]:
			if float(l.get("heal_days", 0.0)) > 0.0 and float(l.get("dmg", 0.0)) > 0.0 and String(l.get("kind", "")) in OPEN_KINDS \
					and not l.has("treated") and not l.get("permanent", false) and String(l.get("tissue", "")) in ["skin", "fat", "muscle"]:
				n += 1
				break
	return n

## The company buys remedies in town for its own sick (Sickness tab / town screen). Returns {treated, cost}.
static func company_treat(game, town: Dictionary) -> Dictionary:
	var out := {"treated": 0, "cost": 0.0}
	if not TownEcon.has_econ(town):
		return out
	var e: Dictionary = town["econ"]
	var w: Dictionary = game.world
	var day := float(game.day)
	for u in game.company:
		if u.dead or not u.sick_now(day):
			continue
		var pr := _person_of(w, u)
		if pr.is_empty():
			continue
		var c := case_of(pr[1], int(pr[2][0]))
		if c.is_empty() or int(c[C_REM]) == 1:
			continue
		var price := Goods.price_f(town, "remedy")
		if int(e["stock"].get("remedy", 0)) <= 0 or float(game.gold) < price:
			break
		Goods.take(town, "remedy", 1)
		TownEcon.led(e, "used", "remedy", 1)
		game.gold -= int(ceil(price))
		Goods.pay_market(town, float(int(ceil(price))))
		apply_remedy(pr[0]["econ"], pr[1], int(pr[2][0]), c, day, u)
		out["treated"] = int(out["treated"]) + 1
		out["cost"] = float(out["cost"]) + ceilf(price)
	return out

## Read only (the town screen's button): what company_treat would do now, walking the same loop without buying.
## {sick: company men sick now, need: of them with no remedy yet, treat, cost, price, stock}.
static func company_quote(game, town: Dictionary) -> Dictionary:
	var out := {"sick": 0, "need": 0, "treat": 0, "cost": 0.0, "price": 0.0, "stock": 0}
	if not TownEcon.has_econ(town):
		return out
	var e: Dictionary = town["econ"]
	var day := float(game.day)
	var price := Goods.price_f(town, "remedy")
	var stock := int(e["stock"].get("remedy", 0))
	var gold := float(game.gold)
	var stopped := false
	out["price"] = price
	out["stock"] = stock
	for u in game.company:
		if u.dead or not u.sick_now(day):
			continue
		out["sick"] = int(out["sick"]) + 1
		var pr := _person_of(game.world, u)
		if pr.is_empty():
			continue
		var c := case_of(pr[1], int(pr[2][0]))
		if c.is_empty() or int(c[C_REM]) == 1:
			continue
		out["need"] = int(out["need"]) + 1
		if stopped or stock <= 0 or gold < price:
			stopped = true
			continue
		stock -= 1
		gold -= ceilf(price)
		out["treat"] = int(out["treat"]) + 1
		out["cost"] = float(out["cost"]) + ceilf(price)
	return out

# ================================================================== units
## The case mirrored on his Unit (battle effects, the unit card, band power).
static func mirror(u: Unit, c: Array) -> void:
	u.sick = String(c[C_DIS])
	u.sick_shed = float(c[C_SHED])
	u.sick_on = float(c[C_ON])
	u.sick_to = _stop(c)
	u.sick_bed = int(c[C_BED]) == 1

## Persons.bind: a man bound to a Unit carries his open case with him (carriers into forces and the company).
static func on_bind(f: Dictionary, p: Array, u: Unit) -> void:
	var c := case_of(f, int(p[0]))
	if c.is_empty():
		u.sick = ""
	else:
		mirror(u, c)

static func _find_unit(game, t: Dictionary, p: Array) -> Unit:
	var uid := int(p[5])
	if game == null or uid < 0:
		return null
	match String(p[4]):
		"company":
			return game.unit_by_uid(uid)
		"hire":
			for u in t.get("recruits", []):
				if u is Unit and u.uid == uid:
					return u
			return null
		"militia", "reserve":
			if String(p[4]) == "reserve":
				var reserve: Unit = Mobilization.reserve_unit(game, uid, String(t.get("id", "")))
				if reserve != null and is_same(Persons.by_uid(People.fam_of(t, reserve.family), uid), p):
					return reserve
			for u in Militia.units_of(game, String(t["id"])):
				if u.uid == uid:
					return u
			return null
	return null

## Battle (Food hooks): a sick man fights at END x0.75, STR x0.85, tires x1.3 faster, focus -10% (inside the
## food and drink focus cap).
static func unit_attr(u: Unit, m: Dictionary) -> void:
	if u.sick == "" or not u.sick_now(float(Game.day)):
		return
	data()
	m["END"] = float(m.get("END", 1.0)) * U_END
	m["STR"] = float(m.get("STR", 1.0)) * U_STR

static func unit_fatigue(u: Unit) -> float:
	if u.sick == "" or not u.sick_now(float(Game.day)):
		return 1.0
	data()
	return U_FAT

static func unit_focus(u: Unit) -> float:
	if u.sick == "" or not u.sick_now(float(Game.day)):
		return 0.0
	data()
	return U_FOC

## "the flux, day 3 of 7" for the unit card and the rosters ("" when well or still incubating unseen).
static func unit_text(u: Unit) -> String:
	if u.sick == "" or not u.sick_now(float(Game.day)):
		return ""
	var dn := int(floor(float(Game.day) - u.sick_on)) + 1
	return "%s, day %d of %d%s" % [dname(u.sick), dn, int(ceil(u.sick_to - u.sick_on)), " (bed-ridden)" if u.sick_bed else ""]

## "the flux, day 3" for a register member line ("" when well or incubating).
static func person_text(f: Dictionary, pid: int, day: float) -> String:
	var c := case_of(f, pid)
	if c.is_empty() or not sick_phase(c, day):
		return ""
	return "%s, day %d" % [dname(String(c[C_DIS])), int(floor(day - float(c[C_ON]))) + 1]

# ================================================================== the herbalist
## World gen (EconGen.generate) and older saves: the town's herbalists (business row herbalist: gather herbs
## with tools, no land; make remedies for the market).
static func gen_businesses(town: Dictionary, e: Dictionary, D: Dictionary, migrate: bool = false) -> void:
	book(e)["hb"] = true
	if not D["businesses"].has("herbalist"):
		return
	for bz in e.get("biz", []):
		if String(bz["type"]) == "herbalist":
			return
	var hc: Array = data()["herbalist_cap"]
	var cap := int(hc[0]) + int(float(hc[1]) * float(town.get("size", 0)))
	var fams: Array = e["fams"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([String(town.get("id", "")), "herbalist"])
	var owner := -1
	var n := fams.size()
	if n > 1:
		var start := rng.randi() % (n - 1)
		for j in n - 1:
			var f: Dictionary = fams[1 + (start + j) % (n - 1)]
			if not f["gone"] and (f["owns"] as Array).is_empty():
				owner = int(f["id"])
				break
	var bz2 := Businesses._row(e, "herbalist", owner, cap, D)
	if migrate:
		bz2["till"] = 0.0   # an older save: no money from nothing (the owner puts some in at his turn)

static func ensure_herbalist(town: Dictionary, e: Dictionary) -> void:
	gen_businesses(town, e, TownEcon.data(), true)
	Businesses.rebuild_open(e)

# ================================================================== reads for the Sickness tab
## Open cases of the town's people at home, in their sick phase (incubation is unseen): [[family, person, case]].
static func _sick_at_home(e: Dictionary, day: float) -> Array:
	var out := []
	for f in e["fams"]:
		if f["gone"] or not f.has("sk"):
			continue
		for key in f["sk"]:
			var c: Array = f["sk"][key]
			if int(c[C_CNT]) != 1 or not sick_phase(c, day):
				continue
			var p := Persons.by_pid(f, int(key))
			if not p.is_empty() and String(p[4]) in HOME:
				out.append([f, p, c])
	return out

static func _season_start(day: float) -> float:
	return floorf(day / float(Calendar.DAYS_PER_SEASON)) * float(Calendar.DAYS_PER_SEASON)

## Header: {sick_now, bed_now, new_week, deaths_season, share (of the town sick now), h60 (open cases, 60 days)}.
static func town_summary(town: Dictionary) -> Dictionary:
	if not TownEcon.has_econ(town):
		return {}
	var e: Dictionary = town["econ"]
	var b := book(e)
	var day := float(e.get("day", 0))
	var sick := _sick_at_home(e, day)
	var bed := 0
	for s in sick:
		bed += int(s[2][C_BED])
	var ds := 0
	for d in Census._book(e)["deaths"]:
		if float(d[0]) >= _season_start(day) and String(d[5]) in ["sickness", "starved"]:
			ds += 1
	var new_week := 0
	for x in b["new"]: new_week += int(x[2]) if (x as Array).size() > 2 else 1
	return {"sick_now": sick.size(), "bed_now": bed, "new_week": new_week, "deaths_season": ds,
		"share": float(sick.size()) / maxf(1.0, float(e["pop"])), "h60": (b["h60"] as Array).duplicate()}

## Disease rows: [{id, name, sick_now, new_week, deaths_season, trend (rising / falling / steady), origin}].
static func disease_rows(town: Dictionary) -> Array:
	if not TownEcon.has_econ(town):
		return []
	var e: Dictionary = town["econ"]
	var b := book(e)
	var day := float(e.get("day", 0))
	var now := {}
	for s in _sick_at_home(e, day):
		now[String(s[2][C_DIS])] = int(now.get(String(s[2][C_DIS]), 0)) + 1
	var nw := {}
	for x in b["new"]:
		nw[String(x[1])] = int(nw.get(String(x[1]), 0)) + (int(x[2]) if (x as Array).size() > 2 else 1)
	var dd := {}
	for d in Census._book(e)["deaths"]:
		if float(d[0]) >= _season_start(day) and String(d[5]) == "sickness":
			dd[String(d[6])] = int(dd.get(String(d[6]), 0)) + 1
	var out := []
	for dis in ids:
		var hd: Array = b["hd"].get(dis, [])
		var trend := "steady"
		if hd.size() >= 2:
			trend = "rising" if int(hd[-1]) > int(hd[0]) else ("falling" if int(hd[-1]) < int(hd[0]) else "steady")
		var o: Array = b["first"].get(dis, [])
		if int(now.get(dis, 0)) == 0 and int(nw.get(dis, 0)) == 0 and int(dd.get(dname(dis), 0)) == 0 and int(b["act"].get(dis, 0)) == 0:
			continue
		out.append({"id": dis, "name": dname(dis), "sick_now": int(now.get(dis, 0)), "new_week": int(nw.get(dis, 0)),
			"deaths_season": int(dd.get(dname(dis), 0)), "trend": trend, "origin": String(o[1]) if o.size() > 1 else ""})
	return out

## The sick: [{pid, fid, name, age, family, disease, day_n, days_m, remedy, bed, band, source}] (disease "" = all).
static func sick_people(town: Dictionary, dis: String = "") -> Array:
	if not TownEcon.has_econ(town):
		return []
	var e: Dictionary = town["econ"]
	var day := float(e.get("day", 0))
	var race := Persons.race_of(e)
	var out := []
	for s in _sick_at_home(e, day):
		var f: Dictionary = s[0]
		var p: Array = s[1]
		var c: Array = s[2]
		if dis != "" and String(c[C_DIS]) != dis:
			continue
		out.append({"pid": int(p[0]), "fid": int(f["id"]), "name": Persons.name_of(f, p, race), "age": Persons.age_of(p, day),
			"family": String(f["name"]), "disease": dname(String(c[C_DIS])), "day_n": int(floor(day - float(c[C_ON]))) + 1,
			"days_m": int(ceil(_stop(c) - float(c[C_ON]))), "remedy": int(c[C_REM]) == 1, "bed": int(c[C_BED]) == 1,
			"band": band(p), "source": origin_text(String(c[C_SRC]), float(c[C_T0]))})
	return out

## Homes hit hardest: [{fid, household, sick}] most sick first (at most n).
static func hardest_homes(town: Dictionary, n: int = 5) -> Array:
	if not TownEcon.has_econ(town):
		return []
	var e: Dictionary = town["econ"]
	var by := {}
	for s in _sick_at_home(e, float(e.get("day", 0))):
		var fid := int(s[0]["id"])
		by[fid] = int(by.get(fid, 0)) + 1
	var out := []
	for fid in by:
		out.append({"fid": fid, "household": String(e["fams"][fid]["name"]), "sick": int(by[fid])})
	out.sort_custom(func(a, b2): return int(a["sick"]) > int(b2["sick"]) if int(a["sick"]) != int(b2["sick"]) else int(a["fid"]) < int(b2["fid"]))
	return out.slice(0, n)

## Remedies: {stock, price, herbalists: [{bid, title, workers, cap, state}]}.
static func remedies(town: Dictionary) -> Dictionary:
	if not TownEcon.has_econ(town):
		return {}
	var e: Dictionary = town["econ"]
	var hb := []
	for bz in e["biz"]:
		if String(bz["type"]) == "herbalist" and not bz.get("closed", false):
			hb.append({"bid": int(bz["id"]), "title": Businesses.title(e, bz), "workers": int(bz["workers"]), "cap": int(bz["cap"]),
				"state": Businesses.state_word(bz)})
	return {"stock": int(e["stock"].get("remedy", 0)), "price": Goods.price_f(town, "remedy"), "herbalists": hb}

## Deaths this season of sickness and hunger: [{day, pid, name, age, sex, cause, detail}], newest first.
static func deaths_season(town: Dictionary) -> Array:
	if not TownEcon.has_econ(town):
		return []
	var e: Dictionary = town["econ"]
	var from := _season_start(float(e.get("day", 0)))
	var out := []
	for d in Census._book(e)["deaths"]:
		if float(d[0]) >= from and String(d[5]) in ["sickness", "starved"]:
			out.append({"day": float(d[0]), "pid": int(d[1]), "name": String(d[2]), "age": int(d[3]), "sex": int(d[4]),
				"cause": String(d[5]), "detail": String(d[6])})
	out.reverse()
	return out

## Outbreaks this town has heard of from caravans: {town id: {day, diseases {name: open cases}}}.
static func outbreak_news(town: Dictionary) -> Dictionary:
	if not TownEcon.has_econ(town):
		return {}
	var out := {}
	var news: Dictionary = book(town["econ"])["news"]
	for tid in news:
		var dd := {}
		for dis in news[tid][1]:
			dd[dname(String(dis))] = int(news[tid][1][dis])
		out[tid] = {"day": int(news[tid][0]), "diseases": dd}
	return out

# ================================================================== the record (5-year report, tests)
## Cases and deaths per town per year: {town name: {year: [cases, sickness deaths, starved]}}.
static func report(w: Dictionary) -> Dictionary:
	var out := {}
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		out[String(t["name"])] = book(t["econ"])["yr"].duplicate(true)
	return out

## Report lines: "Ashford: y1 34 cases, 3 died, 0 starved; y2 ..." and the world's totals by year.
static func report_lines(w: Dictionary) -> Array:
	var lines := []
	var tot := {}
	var ids_t: Array = w.get("towns", {}).keys()
	ids_t.sort()
	for tid in ids_t:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var yr: Dictionary = book(t["econ"])["yr"]
		var ks: Array = yr.keys()
		ks.sort_custom(func(a, b2): return int(a) < int(b2))
		var parts := []
		for y in ks:
			var v: Array = yr[y]
			parts.append("year %d: %d cases, %d died, %d starved" % [int(y), int(v[0]), int(v[1]), int(v[2])])
			if not tot.has(int(y)):
				tot[int(y)] = [0, 0, 0]
			for i in 3:
				tot[int(y)][i] += int(v[i])
		var bd := book(t["econ"])
		var by := []
		for dis in bd["cases"]:
			by.append("%s %d/%d" % [dname(String(dis)), int(bd["cases"][dis]), int(bd["deaths"].get(dname(String(dis)), 0))])
		lines.append("%s (pop %d): %s%s" % [t["name"], int(t["econ"]["pop"]), "; ".join(PackedStringArray(parts)) if not parts.is_empty() else "no cases",
			("  [cases/deaths: " + ", ".join(PackedStringArray(by)) + "]") if not by.is_empty() else ""])
	var ky: Array = tot.keys()
	ky.sort()
	for y in ky:
		lines.append("WORLD year %d: %d cases, %d died of sickness, %d starved" % [int(y), int(tot[y][0]), int(tot[y][1]), int(tot[y][2])])
	return lines

## Health of the record: every count >= 0 and finite, every case well formed (tests, the 5-year run).
static func check_counts(w: Dictionary) -> Array:
	var bad := []
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var b := book(e)
		for k in ["act", "cases", "deaths"]:
			for dis in b[k]:
				var v := float(b[k][dis])
				if v < 0.0 or is_nan(v) or is_inf(v):
					bad.append("%s %s %s = %s" % [tid, k, dis, str(v)])
		if int(b["starved"]) < 0 or int(b["lowbc"]) < 0:
			bad.append("%s starved/lowbc negative" % tid)
		for bz in e["biz"]:
			if int(bz.get("sick", 0)) < 0:
				bad.append("%s business %d sick < 0" % [tid, int(bz["id"])])
		for f in e["fams"]:
			for key in f.get("sk", {}):
				var c: Array = f["sk"][key]
				for i in [C_T0, C_ON, C_END, C_DIE, C_U, C_Q, C_SHED]:
					if is_nan(float(c[i])) or is_inf(float(c[i])):
						bad.append("%s case %s field %d not finite" % [tid, key, i])
				if String(c[C_SRC]) == "":
					bad.append("%s case %s without a source" % [tid, key])
			for key in f.get("bc", {}):
				var v2 := float(f["bc"][key])
				if v2 < 0.0 or v2 > 1.0 or is_nan(v2):
					bad.append("%s body condition %s = %s" % [tid, key, str(v2)])
	return bad
