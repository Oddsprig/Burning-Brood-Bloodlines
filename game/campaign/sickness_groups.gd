class_name SicknessGroups
extends RefCounted
## Group, carrier, force/company, unit, herbalist, and read/report helpers split from Sickness
## (game/campaign/sickness.gd) to keep each file focused and under the size threshold.
## Structure only; all public Sickness.* entry points delegate here with identical behavior.

const HOME := Sickness.HOME
const SERVICE := Sickness.SERVICE
const NMAX := Sickness.NMAX
const NONE := Sickness.NONE
const C_DIS := Sickness.C_DIS
const C_T0 := Sickness.C_T0
const C_ON := Sickness.C_ON
const C_END := Sickness.C_END
const C_DIE := Sickness.C_DIE
const C_SRC := Sickness.C_SRC
const C_BED := Sickness.C_BED
const C_REM := Sickness.C_REM
const C_U := Sickness.C_U
const C_Q := Sickness.C_Q
const C_BIZ := Sickness.C_BIZ
const C_CNT := Sickness.C_CNT
const C_BON := Sickness.C_BON
const C_SHED := Sickness.C_SHED

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
	Sickness._yr(b, day, slot)
	b["yr"][str(Calendar.year(day))][slot] = int(b["yr"][str(Calendar.year(day))][slot]) + n - 1

static func _act_less(b: Dictionary, dis: String, n: int) -> void:
	if n <= 0: return
	var left := int(b["act"].get(dis, 0)) - n
	if left > 0: b["act"][dis] = left
	else: b["act"].erase(dis)

## One town run (part 0 of town_day): the cohorts' cases due end or kill, then new cases over the run's days.
static func _pool_day(_game, t: Dictionary, e: Dictionary, b: Dictionary, d: int, rng: RandomNumberGenerator, span: int) -> void:
	var tf := Sickness._tf(e, b, d)
	var pop := maxf(1.0, float(e["pop"]))
	var act: Dictionary = b["act"]
	var room := float(tf["room"])
	var cloth := float(tf["cloth"])
	for f in e["fams"]:
		if not Population.is_cohort(f): continue
		var tp := Time.get_ticks_usec() if Sickness.prof_parts else 0
		if f.has("psk"): _pool_resolve(e, b, f, d, rng)
		if Sickness.prof_parts: tp = Sickness._pf("pools resolve", tp)
		if f.get("gone", false): continue
		var people := _pool_people(f)
		var total := int(people["workers"]) + int(people["children"]) + int(people["elders"])
		if total <= 0: continue
		var mates := maxf(0.0, float(Families.people(f)) / float(Population.households(f)) - 1.0)   # housemates per person
		var bc: Dictionary = f.get("pool_condition", {})
		var open := _pool_open(f)   # the row's open cases by disease and by "disease|band", counted once
		for i in Sickness.ids.size():
			var dis: String = Sickness.ids[i]
			var r := Sickness.row(dis)
			var town := float(r.get("town", 0.0)) * float(act.get(dis, 0)) * float(tf["sf"][i]) / pop
			var cond := float(tf["T"][i])
			if cond > 0.0: cond *= Sickness.cond_k(e, f, r, room, cloth)
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
				var catch := float(r["catch"][bnd]) * (1.0 + Sickness.BODY_CATCH * (1.0 - float(bc.get(group, 1.0))))
				catches[group] = catch
				left[group] = s
				if s < 1.0: continue
				var n := mini(int(s), Sickness._poisson(rng, s * rate * catch * float(span)))
				if n <= 0: continue
				if src == "":
					src = "cond:" + Sickness.cond_words(e, f, r, room, cloth)
					if town > cond: src = "town:caught from the town's sick in %s" % t["name"]
				_pool_infect(e, b, f, dis, bnd, group, n, d, rng, src)
				left[group] = s - float(n)
				first += n
			if first > 0 and float(r.get("home", 0.0)) > 0.0 and mates > 0.0:
				_pool_household(e, b, f, dis, r, first, mates, left, catches, float(tf["rm"][i]), d, rng)
		if Sickness.prof_parts: Sickness._pf("pools roll", tp)

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
				CampaignWorld.log_event(game, "Sickness: %s has taken hold in %s (%d sick)." % [Sickness.dname(dis), t["name"], int(b["act"][dis])])
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
		var m := mini(int(s), Sickness._poisson(rng, float(first) * mates * (s / all) * P))
		if m > 0: _pool_infect(e, b, f, dis, POOL_GROUPS[group], group, m, d, rng, "home:their own households", delay)

static func _pool_infect(e: Dictionary, b: Dictionary, f: Dictionary, dis: String, bnd: String, group: String, n: int, d: int, rng: RandomNumberGenerator, src: String, delay: int = 0) -> void:
	var r := Sickness.row(dis)
	var on := d + delay + rng.randi_range(int(r["inc"][0]), int(r["inc"][1]))
	var sd := rng.randi_range(int(r["sick"][0]), int(r["sick"][1]))
	var bc := float(f.get("pool_condition", {}).get(group, 1.0))
	var q := minf(0.9, float(r["death"][bnd]) * (1.0 + Sickness.BODY_DEATH * (1.0 - bc)) * Sickness.deadliness)
	# Remedies as the register buys them (_buy_remedy): the herbalist's real stock, the row's coin, two weeks of
	# grain kept back; a remedied case is sick remedy.days as long at remedy.death the daily risk.
	var R: Dictionary = Sickness.data()["remedy"]
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
	if was == 0: b["first"][dis] = [d, Sickness.origin_text(src, float(d))]

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
	var R: Dictionary = Sickness.data()["remedy"]
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
				b["deaths"][Sickness.dname(dis)] = int(b["deaths"].get(Sickness.dname(dis), 0)) + killed
				_yr_n(b, float(c[4]), 1, killed)
				died += killed
		if int(c[5]) <= d:
			var well := int(c[2]) - int(c[3])
			_act_less(b, dis, well)
			var imm := float(Sickness.row(dis).get("immune", 0))
			if imm != 0.0 and well > 0:
				if not f.has("pim"): f["pim"] = {}
				var until := NONE if imm < 0.0 else float(c[5]) + imm * Sickness.year_days()
				var had: Array = f["pim"].get(dis, [0, 0.0])
				f["pim"][dis] = [int(had[0]) + well, maxf(float(had[1]), until)]
			continue
		keep.append(c)
	if keep.is_empty(): f.erase("psk")
	else: f["psk"] = keep
	if died > 0 and not gone:
		var tr := Time.get_ticks_usec() if Sickness.prof_parts else 0
		if Families.people(f) <= 0: Families.extinct(e, f, float(d))
		else: Families.reassign(e, f)
		if Sickness.prof_parts: Sickness._pf("pools reassign", tr)

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
				Population.kill_slots(e, f, String(key), 1, day, "sickness", Sickness.dname(dis))
				killed += 1
				break
	return killed

# ================================================================== carriers
## A caravan reaches a market (Caravans.arrive): its shedding crew pass their diseases to the town, the crew catch
## what the town has, the crew pass it among themselves over the trip, and the town hears of the outbreaks back
## where the caravan came from (Roads: from caravan word, not omniscient).
static func caravan_at(game, wb: Dictionary, dest: Dictionary) -> void:
	if not TownEcon.has_econ(dest):
		return
	var t0 := Time.get_ticks_usec() if Sickness.prof_on else 0
	Sickness.data()
	var w: Dictionary = game.world
	var origin: Dictionary = w["towns"].get(String(wb.get("origin", "")), {})
	if not TownEcon.has_econ(origin):
		return
	var day := float(game.day)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(w.get("seed", 0)), String(wb.get("id", "")), int(day), "skc"])
	var ob: Dictionary = Sickness.book(origin["econ"])["act"]
	var db := Sickness.book(dest["econ"])
	if not ob.is_empty():
		db["news"][String(origin["id"])] = [int(day), ob.duplicate()]
	elif db["news"].has(String(origin["id"])):
		db["news"].erase(String(origin["id"]))
	var crew := _crew(wb, origin)
	if crew.is_empty():
		return
	var stay := float(Sickness.data()["carrier"]["stay"])
	var good := _main_good(wb)
	for cr in crew:
		var c := Sickness.case_of(cr[1], int(cr[2][0]))
		if not c.is_empty() and Sickness.shedding(c, day):
			seed_town(game, dest, String(c[C_DIS]), stay, rng, "carrier:came with the %scaravan from %s, day %d" % [good, origin["name"], int(day) + 1])
	for cr in crew:
		catch_in_town(game, cr[0], cr[1], cr[2], dest, stay, rng, cr[3])
	var trip := clampf(day - float(wb.get("depart_day", day)), 1.0, 30.0)
	for cr in crew:
		var c2 := Sickness.case_of(cr[1], int(cr[2][0]))
		if c2.is_empty() or not Sickness.shedding(c2, day):
			continue
		var r := Sickness.row(String(c2[C_DIS]))
		var bw := float(r["work"])
		if bw <= 0.0:
			continue
		for cr2 in crew:
			if cr2 == cr:
				continue
			var lam := bw * Sickness.catch_m(cr2[1], cr2[2], String(c2[C_DIS]), r, day) * Sickness.race_mult(r, Persons.race_of(cr2[0]["econ"]))
			if lam > 0.0 and rng.randf() < 1.0 - exp(-lam * trip):
				Sickness.infect(game, cr2[0], cr2[1], cr2[2], String(c2[C_DIS]), day, "crew:%s of the caravan crew" % Persons.name_of(cr[1], cr[2], Persons.race_of(cr[0]["econ"])), rng, cr2[3])
	if Sickness.prof_on:
		Sickness.us += Time.get_ticks_usec() - t0

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
	var b := Sickness.book(e)
	var r := Sickness.row(dis)
	var bt := float(r.get("town", 0.0))
	if bt <= 0.0:
		return 0
	var day := float(game.day) if game != null else float(e.get("day", 0))
	var tf := Sickness._tf(e, b, int(day))
	var i := Sickness.ids.find(dis)
	var mx := float(tf["mm"][i])
	var k := Sickness._poisson(rng, bt * stay / maxf(1.0, float(e["pop"])) * mx * float(tf["slots"]))
	var n := 0
	var rm := Sickness.race_mult(r, String(tf["race"]))
	for j in k:
		var pk := Sickness._pick_reg(e, b, rng)
		if pk.is_empty():
			continue
		if rng.randf() < Sickness.catch_m(pk[0], pk[1], dis, r, day) * rm / mx:
			if Sickness.infect(game, t, pk[0], pk[1], dis, day, src, rng):
				n += 1
	return n

## A visitor (crew, soldier, company man: person p of family f, register in home town ht) catches what town t has
## over stay days (the town's share of people passing it on).
static func catch_in_town(game, ht: Dictionary, f: Dictionary, p: Array, t: Dictionary, stay: float, rng: RandomNumberGenerator, u: Unit = null) -> bool:
	if not TownEcon.has_econ(t):
		return false
	var b := Sickness.book(t["econ"])
	var act: Dictionary = b["act"]
	if act.is_empty():
		return false
	var day := float(game.day) if game != null else float(t["econ"].get("day", 0))
	var pop := maxf(1.0, float(t["econ"]["pop"]))
	var race := Persons.race_of(ht["econ"])
	for dis in act:
		var r := Sickness.row(dis)
		var lam := float(r.get("town", 0.0)) * float(act[dis]) * Sickness._shed_share(r) / pop * Sickness.catch_m(f, p, dis, r, day) * Sickness.race_mult(r, race)
		if lam > 0.0 and rng.randf() < 1.0 - exp(-lam * stay):
			return Sickness.infect(game, ht, f, p, dis, day, "town:caught in %s" % t["name"], rng, u)
	return false

## A man back home from service (People.release): an open case now counts in his town, and his household is
## exposed for the rest of it. A town with no case of it yet records where it came from.
static func came_home(town: Dictionary, f: Dictionary, p: Array) -> void:
	if not f.has("sk") or not TownEcon.has_econ(town):
		return
	var c := Sickness.case_of(f, int(p[0]))
	if c.is_empty() or int(c[C_CNT]) == 1:
		return
	var e: Dictionary = town["econ"]
	var day := float(e.get("day", 0))
	if Sickness._stop(c) <= day:
		return
	c[C_CNT] = 1
	var b := Sickness.book(e)
	var dis := String(c[C_DIS])
	var was := int(b["act"].get(dis, 0))
	b["act"][dis] = was + 1
	if was == 0:
		b["first"][dis] = [int(day), "came home with %s from service (%s), day %d" % [Persons.name_of(f, p, Persons.race_of(e)), Sickness.origin_text(String(c[C_SRC]), float(c[C_T0])), int(day) + 1]]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(p[0]), int(day), "skh"])
	Sickness._household(null, town, e, b, f, p, c, rng)

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
	var c := Sickness.case_of(b, pid)
	if not c.is_empty():
		Sickness._push(Sickness.book(e), [Sickness._stop(c), 0, int(b["id"]), pid, String(c[C_DIS]), ""])

## A whole family walks to another town (Barge.move_family; its people re-numbered there, remap old pid -> new pid):
## the old town's book lets its open cases go (counters, bed-ridden staff, the bed days the old wage code missed), the
## new family takes its cases, immunities and body condition under the new numbers, and the new town's book counts
## the open cases and queues their ends (they left their jobs: no business is short of them now).
static func family_moved(e: Dictionary, e2: Dictionary, f: Dictionary, nf: Dictionary, remap: Dictionary, day: float) -> void:
	var b := Sickness.book(e)
	if f.has("sk"):
		for key in (f["sk"] as Dictionary).keys():
			Sickness._drop_case(e, b, f, key, f["sk"][key], day)
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
	var b2 := Sickness.book(e2)
	if nf.has("bc"):
		b2["lowbc"] = int(b2.get("lowbc", 0)) + (nf["bc"] as Dictionary).size()
		for key in nf["bc"]:
			var v := float(nf["bc"][key])
			if v < float(b2.get("bcw", 1.0)):
				b2["bcw"] = v
				if b2.has("tf") and v < float(b2["tf"].get("bcmin", 1.0)):
					Sickness._lower_bc_bound(b2["tf"], v)   # the town's catch bound must cover him
	if not nf.has("sk"):
		return
	var sk := {}
	for key in nf["sk"]:
		var c: Array = nf["sk"][key]
		if not remap.has(int(key)) or Sickness._stop(c) <= day:
			continue
		var pid := int(remap[int(key)])
		c[C_BIZ] = -1
		c[C_BON] = 0
		sk[str(pid)] = c
		if int(c[C_CNT]) == 1:
			var dis := String(c[C_DIS])
			b2["act"][dis] = int(b2["act"].get(dis, 0)) + 1
		Sickness._push(b2, [Sickness._stop(c), 0, int(nf["id"]), pid, String(c[C_DIS]), ""])
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
	var ED: Dictionary = Sickness.data().get("edge", {})
	for dis in ED:
		if rng.randf() >= float(ED[dis]):
			continue
		var t := edge_town(w)
		if t.is_empty():
			continue
		var e: Dictionary = t["econ"]
		var src := "edge:a traveller from beyond the map edge, day %d" % (d + 1)
		for tries in 64:
			var pk := Sickness._pick(e, rng, NMAX)
			if pk.is_empty() or int(pk[1][6]) != 0:
				continue
			if Sickness.infect(game, t, pk[0], pk[1], String(dis), float(d), src, rng):
				CampaignWorld.log_event(game, "A traveller from beyond the edge of the map brought %s to %s." % [Sickness.dname(String(dis)), t["name"]])
				TownEcon.town_hist(e, "A traveller from beyond the map's edge brought %s." % Sickness.dname(String(dis)), float(d))
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
		var stay := float(Sickness.data()["carrier"]["stay"])
		var src := "carrier:came with %s's soldiers, day %d" % [CampaignWorld.faction_the(String(wb["faction"])), d + 1]
		for u in men:
			if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
				seed_town(game, near, u.sick, stay, rng, src)
		for u in men:
			var pr := _person_of(w, u, roll)
			if not pr.is_empty():
				catch_in_town(game, pr[0], pr[1], pr[2], near, stay, rng, u)

static func _near_town(w: Dictionary, wb: Dictionary) -> Dictionary:
	var px := float(Sickness.data()["carrier"]["near_px"])
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
		tf = Sickness._tf(town["econ"], Sickness.book(town["econ"]), int(day))
		tact = Sickness.book(town["econ"])["act"]
		tpop = maxf(1.0, float(town["econ"]["pop"]))
	for i in Sickness.ids.size():
		var r := Sickness.row(Sickness.ids[i])
		var lc := 0.0
		if String(r["where"]) == mode:
			lc = float(r["base"]) * float(r["season"][si]) * float(r["climate"].get(cl, 1.0)) * (1.0 + float(r["hunger"]) * short)
		elif not tf.is_empty() and String(r["where"]) == "town":
			lc = float(tf["T"][i])   # lodging in town: the town's conditions at an ordinary roof (K = 1)
		var lk := float(r["camp"]) * float(shed.get(Sickness.ids[i], 0)) / n
		if not tact.is_empty():
			lk += float(r.get("town", 0.0)) * float(tact.get(Sickness.ids[i], 0)) * float(tf["sf"][i]) / tpop
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
			for i in Sickness.ids.size():
				var l: Array = lam[i]
				if float(l[0]) <= 0.0 and float(l[1]) <= 0.0:
					pp2.append(0.0)
					continue
				var r2 := Sickness.row(Sickness.ids[i])
				var v := (float(l[0]) + float(l[1])) * float(Sickness.CATCH[Sickness.ids[i]][0]) * Sickness.race_mult(r2, u.race)
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
		if src == src_cond and not town.is_empty() and String(Sickness.row(Sickness.ids[i2])["where"]) == "town":
			src = "cond:%s; lodging in %s" % [String(Sickness.row(Sickness.ids[i2]).get("spread", "")), town["name"]]
		elif src == src_contact and not tact.is_empty() and float(Sickness.row(Sickness.ids[i2]).get("town", 0.0)) * float(tact.get(Sickness.ids[i2], 0)) > 0.0 and rng.randf() < 0.5:
			src = "town:caught in %s" % town["name"]
		Sickness.infect(game, pr[0], pr[1], pr[2], Sickness.ids[i2], day, src, rng, u)

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
		var stay := float(Sickness.data()["carrier"]["stay"])
		for u in men:
			if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
				seed_town(game, town, u.sick, stay, rng, "carrier:came with the mercenary company, day %d" % (d + 1))
	# wound rot: open wounds no healer has treated (a town healer's treatment cleans and binds them)
	var R := Sickness.row("wound_rot")
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
				Sickness.infect(game, pr[0], pr[1], pr[2], "wound_rot", day, "wound:%d untreated open wound%s" % [nw, "" if nw == 1 else "s"], rng, u)

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
		var c := Sickness.case_of(pr[1], int(pr[2][0]))
		if c.is_empty() or int(c[C_REM]) == 1:
			continue
		var price := Goods.price_f(town, "remedy")
		if int(e["stock"].get("remedy", 0)) <= 0 or float(game.gold) < price:
			break
		Goods.take(town, "remedy", 1)
		TownEcon.led(e, "used", "remedy", 1)
		game.gold -= int(ceil(price))
		Goods.pay_market(town, float(int(ceil(price))))
		Sickness.apply_remedy(pr[0]["econ"], pr[1], int(pr[2][0]), c, day, u)
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
		var c := Sickness.case_of(pr[1], int(pr[2][0]))
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
	u.sick_to = Sickness._stop(c)
	u.sick_bed = int(c[C_BED]) == 1

## Persons.bind: a man bound to a Unit carries his open case with him (carriers into forces and the company).
static func on_bind(f: Dictionary, p: Array, u: Unit) -> void:
	var c := Sickness.case_of(f, int(p[0]))
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
	Sickness.data()
	m["END"] = float(m.get("END", 1.0)) * Sickness.U_END
	m["STR"] = float(m.get("STR", 1.0)) * Sickness.U_STR

static func unit_fatigue(u: Unit) -> float:
	if u.sick == "" or not u.sick_now(float(Game.day)):
		return 1.0
	Sickness.data()
	return Sickness.U_FAT

static func unit_focus(u: Unit) -> float:
	if u.sick == "" or not u.sick_now(float(Game.day)):
		return 0.0
	Sickness.data()
	return Sickness.U_FOC

## "the flux, day 3 of 7" for the unit card and the rosters ("" when well or still incubating unseen).
static func unit_text(u: Unit) -> String:
	if u.sick == "" or not u.sick_now(float(Game.day)):
		return ""
	var dn := int(floor(float(Game.day) - u.sick_on)) + 1
	return "%s, day %d of %d%s" % [Sickness.dname(u.sick), dn, int(ceil(u.sick_to - u.sick_on)), " (bed-ridden)" if u.sick_bed else ""]

## "the flux, day 3" for a register member line ("" when well or incubating).
static func person_text(f: Dictionary, pid: int, day: float) -> String:
	var c := Sickness.case_of(f, pid)
	if c.is_empty() or not Sickness.sick_phase(c, day):
		return ""
	return "%s, day %d" % [Sickness.dname(String(c[C_DIS])), int(floor(day - float(c[C_ON]))) + 1]

# ================================================================== the herbalist
## World gen (EconGen.generate) and older saves: the town's herbalists (business row herbalist: gather herbs
## with tools, no land; make remedies for the market).
static func gen_businesses(town: Dictionary, e: Dictionary, D: Dictionary, migrate: bool = false) -> void:
	Sickness.book(e)["hb"] = true
	if not D["businesses"].has("herbalist"):
		return
	for bz in e.get("biz", []):
		if String(bz["type"]) == "herbalist":
			return
	var hc: Array = Sickness.data()["herbalist_cap"]
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
			if int(c[C_CNT]) != 1 or not Sickness.sick_phase(c, day):
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
	var b := Sickness.book(e)
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
	var b := Sickness.book(e)
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
	for dis in Sickness.ids:
		var hd: Array = b["hd"].get(dis, [])
		var trend := "steady"
		if hd.size() >= 2:
			trend = "rising" if int(hd[-1]) > int(hd[0]) else ("falling" if int(hd[-1]) < int(hd[0]) else "steady")
		var o: Array = b["first"].get(dis, [])
		if int(now.get(dis, 0)) == 0 and int(nw.get(dis, 0)) == 0 and int(dd.get(Sickness.dname(dis), 0)) == 0 and int(b["act"].get(dis, 0)) == 0:
			continue
		out.append({"id": dis, "name": Sickness.dname(dis), "sick_now": int(now.get(dis, 0)), "new_week": int(nw.get(dis, 0)),
			"deaths_season": int(dd.get(Sickness.dname(dis), 0)), "trend": trend, "origin": String(o[1]) if o.size() > 1 else ""})
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
			"family": String(f["name"]), "disease": Sickness.dname(String(c[C_DIS])), "day_n": int(floor(day - float(c[C_ON]))) + 1,
			"days_m": int(ceil(Sickness._stop(c) - float(c[C_ON]))), "remedy": int(c[C_REM]) == 1, "bed": int(c[C_BED]) == 1,
			"band": Sickness.band(p), "source": Sickness.origin_text(String(c[C_SRC]), float(c[C_T0]))})
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
	var news: Dictionary = Sickness.book(town["econ"])["news"]
	for tid in news:
		var dd := {}
		for dis in news[tid][1]:
			dd[Sickness.dname(String(dis))] = int(news[tid][1][dis])
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
		out[String(t["name"])] = Sickness.book(t["econ"])["yr"].duplicate(true)
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
		var yr: Dictionary = Sickness.book(t["econ"])["yr"]
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
		var bd := Sickness.book(t["econ"])
		var by := []
		for dis in bd["cases"]:
			by.append("%s %d/%d" % [Sickness.dname(String(dis)), int(bd["cases"][dis]), int(bd["deaths"].get(Sickness.dname(String(dis)), 0))])
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
		var b := Sickness.book(e)
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
