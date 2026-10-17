class_name Census
extends RefCounted
## Deaths by cause and people coming and going (town screen spec part 2 section 7; world screen part 2 Census).
## Shared entry point: every system that kills or moves a register person calls in here, so the Census tab,
## the world Census and the balance line (births - deaths + arrived - left = change) read one record.
##
## Lives in the town economy dict: e["census"] = {
##   "deaths": [[day, pid, name, age, sex, cause, detail, fam, job, counted], ...]  newest DEATHS_MAX
##             cause: one of CAUSES, never blank; counted 1 = he was one of the town's people (company men
##             left the town's count when they signed on, so their deaths are 0 here but still listed)
##   "moves":  [[day, pid, dir ("in"/"out"), other_town, why, n], ...]   newest MOVES_MAX (n people)
##   "births": int (running count, all time), "bdays": [[day, pid]] newest BIRTHS_MAX
##   "cur":    the season so far: {from, births, deaths {cause: n}, away {cause: n}, left {why: n},
##             arrived {why: n}, to {town: n}, from_t {town: n}}
##   "rows":   one per season's census (newest ROWS_MAX): {day, stamp, people, families, children, adults, elders,
##             female, male, homeless, empty_homes, soldiers, births, deaths {cause: n}, away {cause: n},
##             left {why: n}, arrived {why: n}, to, from_t}; a row's counters are the season that ENDED at it,
##             so rows[i].people - rows[i-1].people = births - deaths + arrived - left of rows[i].
##   "buf":    60-day daily buffers {d, pop, tre, food, grain, bt, dt} (bt / dt: running births / deaths)
##   "wbuf":   weekly samples over 60 days {d, hungry, homeless, destitute, debt, poorhouse, fams, hard}
##             (hard: families at or past the recruit-pool hardship line) }
## Balance: births - deaths + arrived - left = people now - people at the last census. Exact, because every
## change to a family row's people counts goes through one of the record_* calls below (tests/test_campaign_census.gd).
## The town-screen helper owns this file; others only call record_death / record_move / record_birth / note_fate.

const CAUSES := ["battle", "wounds", "starved", "sickness", "frozen", "old age", "childbirth", "executed",
	"accident", "murdered"]
const DEATHS_MAX := 400
const MOVES_MAX := 300
const BIRTHS_MAX := 200
const ROWS_MAX := 40
const BUF_DAYS := 60

static var _ctx: Array = []   # [cause, detail] while a fight resolves (deaths during it take this cause)

static func _book(e: Dictionary) -> Dictionary:
	if not e.has("census"):
		e["census"] = {"deaths": [], "moves": [], "births": 0}
	var b: Dictionary = e["census"]
	if not b.has("cur"):
		b["cur"] = _blank_cur(float(e.get("day", 0)))
		b["rows"] = []
		b["bdays"] = []
		b["bt"] = int(b.get("births", 0))
		b["dt"] = 0
	if not b.has("death_ids"): b["death_ids"] = {}
	return b

static func _blank_cur(day: float) -> Dictionary:
	return {"from": day, "births": 0, "deaths": {}, "away": {}, "left": {}, "arrived": {}, "to": {}, "from_t": {}}

static func _add(d: Dictionary, k: String, n: int = 1) -> void:
	d[k] = int(d.get(k, 0)) + n

static func sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n

# ================================================================== the record calls (every site that kills or moves people)
## cause must be one of CAUSES; detail names the fight or the disease ("the flux", "Ashford raid d131").
## counted: the dead man was in the town's people count (false for company men, who left it when hired).
static func record_death(e: Dictionary, pid: int, pname: String, age: int, sex: int, day: float, cause: String,
		detail: String = "", counted: bool = true, fam: int = -1, job: String = "", stable_uid: String = "", unit_uid: int = -1) -> void:
	assert(cause in CAUSES, "Census: unknown death cause '%s'" % cause)
	if not cause in CAUSES:
		cause = "accident" if cause == "" else cause   # (release builds: never blank)
	var b := _book(e)
	var key := stable_uid if stable_uid != "" else ("pid:%s:%d" % [e.get("identity_scope", ""), pid] if pid >= 0 else "")
	var ukey := "unit:%d" % unit_uid if unit_uid >= 0 else ""
	if (key != "" and b["death_ids"].has(key)) or (ukey != "" and b["death_ids"].has(ukey)): return
	if key != "": b["death_ids"][key] = day
	if ukey != "": b["death_ids"][ukey] = day
	b["deaths"].append([day, pid, pname, age, sex, cause, detail, fam, job, 1 if counted else 0])
	while (b["deaths"] as Array).size() > DEATHS_MAX:
		(b["deaths"] as Array).pop_front()
	_add(b["cur"]["deaths" if counted else "away"], cause)
	if counted:
		b["dt"] = int(b.get("dt", 0)) + 1

## The same from a register person (f.pp / f.kp record): name, age, sex, family and his place read from it.
static func person_died(e: Dictionary, f: Dictionary, p: Array, day: float, cause: String, detail: String = "",
		counted: bool = true) -> void:
	if p.is_empty():
		record_death(e, -1, "", -1, -1, day, cause, detail, counted, int(f.get("id", -1)))
		return
	Dynasty.record_person(e, f, p, false)
	var job := String(Persons.g(p, Persons.JOB, ""))
	if job == "" and String(p[4]) != "":
		job = String(Persons.SERVICE_WORDS.get(String(p[4]), String(p[4])))
	record_death(e, int(p[0]), Persons.name_of(f, p, Persons.race_of(e)), Persons.age_of(p, day), int(p[2]), day, cause,
		detail, counted, int(f.get("id", -1)), job, str(Persons.g(p, Persons.PERSON_UID, "")), int(p[5]))

## dir "in" or "out"; why: hunger, debt, war, work, married, called up, seizure, refugee. n people move.
static func record_move(e: Dictionary, pid: int, dir: String, other_town: String, day: float, why: String, n: int = 1) -> void:
	if n <= 0:
		return
	var b := _book(e)
	b["moves"].append([day, pid, dir, other_town, why, n])
	while (b["moves"] as Array).size() > MOVES_MAX:
		(b["moves"] as Array).pop_front()
	var cur: Dictionary = b["cur"]
	if dir == "in":
		_add(cur["arrived"], why, n)
		_add(cur["from_t"], other_town if other_town != "" else "-", n)
	else:
		_add(cur["left"], why, n)
		_add(cur["to"], other_town if other_town != "" else "-", n)

static func record_birth(e: Dictionary, day: float = -1.0, pid: int = -1) -> void:
	var b := _book(e)
	b["births"] = int(b["births"]) + 1
	b["bt"] = int(b.get("bt", 0)) + 1
	b["cur"]["births"] = int(b["cur"]["births"]) + 1
	if day >= 0.0:
		b["bdays"].append([day, pid])
		while (b["bdays"] as Array).size() > BIRTHS_MAX:
			(b["bdays"] as Array).pop_front()

## Bounded anonymous mortality: one cause row carries its exact number of slots.
static func record_population_deaths(e: Dictionary, fam: int, n: int, day: float, cause: String, detail: String = "") -> void:
	if n <= 0: return
	assert(cause in CAUSES)
	var b := _book(e)
	b["deaths"].append([day, -1, "", -1, -1, cause, detail, fam, "", 1, n])
	while b["deaths"].size() > DEATHS_MAX: b["deaths"].pop_front()
	_add(b["cur"]["deaths"], cause, n)
	b["dt"] = int(b.get("dt", 0)) + n

static func deaths_by_cause(e: Dictionary, from_day: float = -INF, to_day: float = INF) -> Dictionary:
	var out := {}
	for d in _book(e)["deaths"]:
		if float(d[0]) >= from_day and float(d[0]) < to_day:
			out[d[5]] = int(out.get(d[5], 0)) + (int(d[10]) if d.size() > 10 else 1)
	return out

# ================================================================== how a man in a force died
## A fight that kills men right now (their families learn of it at once): deaths recorded until ctx_end take this
## cause and detail.
static func ctx(cause: String, detail: String) -> void:
	_ctx = [cause, detail]

static func ctx_end() -> void:
	_ctx = []

## A man fell in a fight whose dead leave their families later (the army sweep, the weekly register sweep): his
## unit uid keeps the cause until his death is recorded.
static func note_fate(w: Dictionary, uid: int, cause: String, detail: String) -> void:
	if uid < 0:
		return
	if not w.has("census_fate"):
		w["census_fate"] = {}
	w["census_fate"][str(uid)] = [cause, detail, int(w.get("last_day", 0))]

static func note_fates(w: Dictionary, units: Array, cause: String, detail: String) -> void:
	for u in units:
		if u is Unit:
			note_fate(w, (u as Unit).uid, cause, detail)

## [cause, detail] for a man of `role` dying now: the fight in progress, else the fate noted for his unit, else his
## service (every man of a force who dies off the company's field died fighting with it).
static func fate_for(w: Dictionary, uid: int, role: String, town_name: String) -> Array:
	if not _ctx.is_empty():
		return _ctx.duplicate()
	var fd: Dictionary = w.get("census_fate", {})
	if uid >= 0 and fd.has(str(uid)):
		var r: Array = fd[str(uid)]
		fd.erase(str(uid))
		return [String(r[0]), String(r[1])]
	match role:
		"company": return ["battle", "with the company"]
		"militia": return ["battle", "with the militia of %s" % town_name]
		"army": return ["battle", "with the army"]
		"caravan": return ["battle", "guarding a caravan"]
		"bandit": return ["battle", "with an outlaw band"]
		"deserter": return ["battle", "with a deserter band"]
	return ["battle", "in a fight"]

# ================================================================== census rows and the 60-day buffers
## The town's people right now: every member of every family still in town (the row counts), the same sum
## TownEcon.recount takes. Company men are not in it.
static func people(e: Dictionary) -> int:
	var n := 0
	var families: Array = e.get("fams", [])
	for f: Dictionary in families:
		if f.get("gone", false) or f.get("estate", false):
			continue
		# The same four counters as Families.people, without one dynamic call per household.
		n += int(f["m"]) + int(f["f"]) + int(f["kids"]) + int(f["old"])
	return n

static func stamp_of(day: float) -> int:
	return Calendar.day_index(day) / Calendar.DAYS_PER_SEASON

## Cuts this season's census row: the people now and the counters since the last row.
static func cut(e: Dictionary, day: float) -> Dictionary:
	var b := _book(e)
	var c := People.census(e)
	var soldiers := 0
	for f in e.get("fams", []):
		if f.get("gone", false):
			continue
		for p in f.get("pp", []):
			if String(p[4]) in ["militia", "army"]:
				soldiers += 1
	var cur: Dictionary = b["cur"]
	var row := {"day": day, "stamp": stamp_of(day), "people": people(e), "families": int(c["households"]),
		"children": int(c["children"]), "adults": int(c["adults"]), "elders": int(c["elders"]), "female": int(c["female"]),
		"male": int(c["male"]), "homeless": int(c["homeless"]), "empty_homes": int(c["empty_homes"]), "soldiers": soldiers,
		"births": int(cur["births"]), "deaths": cur["deaths"], "away": cur["away"], "left": cur["left"], "arrived": cur["arrived"],
		"to": cur["to"], "from_t": cur["from_t"], "since": float(cur["from"])}
	(b["rows"] as Array).append(row)
	while (b["rows"] as Array).size() > ROWS_MAX:
		(b["rows"] as Array).pop_front()
	b["cur"] = _blank_cur(day)
	return row

## World gen and older saves: the first census of every town (the balance counts from here).
static func init_world(game) -> void:
	var w: Dictionary = game.world
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t) and (_book(t["econ"])["rows"] as Array).is_empty():
			cut(t["econ"], float(game.day))
			_sample(t, t["econ"], float(game.day), true)

static func after_load(game) -> void:
	var w: Dictionary = game.world
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t) or not t["econ"].has("census"):
			continue
		var b: Dictionary = t["econ"]["census"]
		for k in ["births", "bt", "dt"]:
			if b.has(k):
				b[k] = int(b[k])
		for r in b.get("rows", []):
			for k in ["stamp", "people", "families", "children", "adults", "elders", "female", "male", "homeless", "empty_homes", "soldiers", "births"]:
				if r.has(k):
					r[k] = int(r[k])
	init_world(game)

## Daily (CampaignWorld._daily): a new season cuts each town's census row; the 60-day buffers take today's
## numbers (the family-wide counts once a week per town, staggered).
static func daily(game, d: int) -> void:
	var w: Dictionary = game.world
	var i := 0
	for tid in w.get("towns", {}):
		i += 1
		town_day(game, String(tid), d, i, float(game.day))
	fates_day(w, d)

## One town's part of daily (i = its place in the towns, from 1; day = the midnight it belongs to). World size: the
## map runs these as work jobs, one town a frame (CampaignWorld._daily), not every town at midnight.
static func town_day(game, tid: String, d: int, i: int, day: float) -> void:
	var t: Dictionary = game.world["towns"].get(tid, {})
	if not TownEcon.has_econ(t):
		return
	var e: Dictionary = t["econ"]
	var b := _book(e)
	var rows: Array = b["rows"]
	if rows.is_empty() or int(rows[-1]["stamp"]) < stamp_of(day):
		cut(e, day)
	_sample(t, e, day, (d + i) % 7 == 0)

static func fates_day(w: Dictionary, d: int) -> void:
	# fates of men who never died after all (they fled home) fade after a month
	var fd: Dictionary = w.get("census_fate", {})
	if fd.size() > 300:
		for k in fd.keys():
			if int(fd[k][2]) < d - 30:
				fd.erase(k)

static func _push(buf: Dictionary, k: String, v: Variant) -> void:
	if not buf.has(k):
		buf[k] = []
	(buf[k] as Array).append(v)

static func _trim(buf: Dictionary, day: float) -> void:
	var ds: Array = buf.get("d", [])
	var cut_n := 0
	while cut_n < ds.size() and float(ds[cut_n]) < day - float(BUF_DAYS):
		cut_n += 1
	if cut_n > 0:
		for k in buf:
			buf[k] = (buf[k] as Array).slice(cut_n)

static func _sample(t: Dictionary, e: Dictionary, day: float, weekly: bool) -> void:
	var b := _book(e)
	if not b.has("buf"):
		b["buf"] = {}
	var buf: Dictionary = b["buf"]
	var ds: Array = buf.get("d", [])
	if not ds.is_empty() and float(ds[-1]) >= day:
		return
	_push(buf, "d", day)
	_push(buf, "pop", int(e.get("pop", 0)))
	_push(buf, "tre", snappedf(float(e.get("treasury", 0.0)), 0.1))
	_push(buf, "food", snappedf(TownEcon.days_food(t), 0.1))
	_push(buf, "grain", snappedf(float(e.get("price", {}).get("grain", 0.0)), 0.01))
	_push(buf, "bt", int(b.get("bt", 0)))
	_push(buf, "dt", int(b.get("dt", 0)))
	_trim(buf, day)
	if not weekly:
		return
	if not b.has("wbuf"):
		b["wbuf"] = {}
	var wb: Dictionary = b["wbuf"]
	var n := {"hungry": 0, "homeless": 0, "destitute": 0, "debt": 0, "poorhouse": 0, "fams": 0, "hard": 0}
	var hard_line := float(TownEcon.data()["family"]["recruit_hardship"])
	for f in e.get("fams", []):
		if f.get("gone", false) or f.get("estate", false):
			continue
		n["fams"] += 1
		if Families.hardship(f) >= hard_line: n["hard"] += 1
		if int(f.get("hungry", 0)) > 0: n["hungry"] += 1
		if int(f.get("homes", 1)) <= 0:
			n["homeless"] += 1
			if Shelter.destitute(f): n["destitute"] += 1
		if float(f.get("debt", 0.0)) > 0.0: n["debt"] += 1
		if f.get("shel", false): n["poorhouse"] += 1
	_push(wb, "d", day)
	for k in n:
		_push(wb, k, n[k])
	_trim(wb, day)

# ================================================================== reading (town, faction, world)
static func rows(e: Dictionary) -> Array:
	return _book(e)["rows"]

static func current(e: Dictionary) -> Dictionary:
	return _book(e)["cur"]

## The balance since the last census: {births, deaths, arrived, left, change, people, last} with
## change = people now - people at the last census; it adds up when births - deaths + arrived - left == change.
static func balance(e: Dictionary) -> Dictionary:
	var b := _book(e)
	var cur: Dictionary = b["cur"]
	var rs: Array = b["rows"]
	var last := int(rs[-1]["people"]) if not rs.is_empty() else people(e)
	var now := people(e)
	return {"births": int(cur["births"]), "deaths": sum(cur["deaths"]), "arrived": sum(cur["arrived"]), "left": sum(cur["left"]),
		"people": now, "last": last, "change": now - last}

## The balance of one census row against the one before it ({} for the first row).
static func row_balance(rs: Array, i: int) -> Dictionary:
	if i <= 0 or i >= rs.size():
		return {}
	var r: Dictionary = rs[i]
	return {"births": int(r["births"]), "deaths": sum(r["deaths"]), "arrived": sum(r["arrived"]), "left": sum(r["left"]),
		"people": int(r["people"]), "last": int(rs[i - 1]["people"]), "change": int(r["people"]) - int(rs[i - 1]["people"])}

static func adds_up(bal: Dictionary) -> bool:
	return bal.is_empty() or int(bal["births"]) - int(bal["deaths"]) + int(bal["arrived"]) - int(bal["left"]) == int(bal["change"])

## Sums balances over towns (a faction, the world).
static func balance_of(w: Dictionary, tids: Array) -> Dictionary:
	var out := {"births": 0, "deaths": 0, "arrived": 0, "left": 0, "people": 0, "last": 0, "change": 0}
	for tid in tids:
		var t: Dictionary = w["towns"].get(tid, {})
		if not TownEcon.has_econ(t):
			continue
		var bl := balance(t["econ"])
		for k in out:
			out[k] = int(out[k]) + int(bl[k])
	return out

## Deaths by cause over towns, this season so far (counted) and the last finished season.
static func causes_of(w: Dictionary, tids: Array) -> Dictionary:
	var now := {}; var last := {}
	for tid in tids:
		var t: Dictionary = w["towns"].get(tid, {})
		if not TownEcon.has_econ(t):
			continue
		var b := _book(t["econ"])
		for c in b["cur"]["deaths"]:
			_add(now, c, int(b["cur"]["deaths"][c]))
		var rs: Array = b["rows"]
		if rs.size() >= 2:
			for c in rs[-1]["deaths"]:
				_add(last, c, int(rs[-1]["deaths"][c]))
	return {"now": now, "last": last}
