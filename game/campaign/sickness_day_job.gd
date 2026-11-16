class_name SicknessDayJob
extends CampaignDayJob
## Exact continuation of one native sick/sick_w header. Only the queue head
## owns this object; later headers remain plain save data. Coroutine locals
## retain iterators, pending event buckets and RNG objects without replay.
## Requires the shared CampaignDayJob hold/save protocol from combined r6.
signal resume_work
const SLICE_USEC: int = 750
var town_id: String = ""
var effect_day: int = 0
var town_part: int = 0
var yields: int = 0
var boundary: String = "start"
var rng_states: Array = []
var _rngs: Array = []
var _started: bool = false
var _finished: bool = false
var _deadline_usec: int = 0
var _suspended_usec: int = 0
var _game: Variant = null

func _init(tid: String, day: int, part: int) -> void:
	town_id = tid
	effect_day = day
	town_part = part

## One resume per dispatcher slice, including the finishing slice.
func step(game: Variant) -> bool:
	if done:
		return true
	# Prepared heads bypass the dispatcher's fresh-owner hold. Acquire it once,
	# even when this frame cannot admit a kernel; preserve the original pause.
	if not holds_tree:
		hold(game)
	if budgeted and game.has_method("_day_job_frame_remaining_usec") and game._day_job_frame_remaining_usec() < NATIVE_RESERVE_USEC:
		return false
	var started_usec: int = Time.get_ticks_usec()
	_deadline_usec = started_usec + SLICE_USEC
	_game = game
	if not _started:
		_started = true
		_run(game)
	else:
		resume_work.emit()
	done = _finished
	var elapsed_usec: int = Time.get_ticks_usec() - started_usec
	CampaignDayJob.step_worst_usec["sickness " + boundary] = maxi(int(CampaignDayJob.step_worst_usec.get("sickness " + boundary, 0)), elapsed_usec)
	Perf.record_us("Day kernel sickness " + boundary, elapsed_usec)
	if Sickness.prof_on:
		Sickness.us += elapsed_usec
		Sickness.job_worst = maxi(Sickness.job_worst, elapsed_usec)
	return done

func _run(game: Variant) -> void:
	Sickness.data()
	if town_part < 0:
		await _world_day(game, effect_day)
	else:
		var town: Dictionary = game.world.get("towns", {}).get(town_id, {})
		if not town.is_empty():
			await town_day(game, town, effect_day, town_part)
	for generator: RandomNumberGenerator in _rngs:
		rng_states.append([generator.seed, generator.state])
	_finished = true
	_game = null

func _checkpoint(label: String) -> void:
	boundary = label
	if not budgeted:
		return
	if Time.get_ticks_usec() < _deadline_usec and (not _game.has_method("_day_job_frame_remaining_usec") or _game._day_job_frame_remaining_usec() >= NATIVE_RESERVE_USEC):
		return
	yields += 1
	var suspended_at: int = Time.get_ticks_usec()
	await resume_work
	_suspended_usec += Time.get_ticks_usec() - suspended_at

func _active_usec() -> int:
	return Time.get_ticks_usec() - _suspended_usec

## Native phase counters exclude wall time spent waiting for the next frame.
func _pf(key: String, started_usec: int) -> int:
	var now_usec: int = _active_usec()
	if Sickness.prof_parts:
		Sickness.prof[key] = int(Sickness.prof.get(key, 0)) + now_usec - started_usec
	return now_usec

func town_day(game: Variant, t: Dictionary, d: int, part: int = 0) -> void:
	await _checkpoint("town_day:enter")
	if not TownEcon.has_econ(t):
		return
	var e: Dictionary = t["econ"]
	var b: Variant = Sickness.book(e)
	if not b.has("hb"):
		await ensure_herbalist(t, e)
	if not b.has("stag"):
		b["stag"] = absi(hash(String(t["id"]))) % 7   # towns start their sickness weeks on different days
	var rng: Variant = RandomNumberGenerator.new()
	_rngs.append(rng)
	rng.seed = hash([int(game.world.get("seed", 0)), String(t["id"]), d, "skt", part])
	var t0: Variant = _active_usec() if Sickness.prof_on else 0
	if part >= 2:   # the run's later jobs: each draws half the new cases over the days the first one covered
		await _roll_town(game, t, e, b, d, rng, int(b.get("span", 1)), 0.5)
		if Sickness.prof_on: _pf("roll", t0)
		return
	# the days this run covers: every day since the town's last run (CADENCE in play; 1 for a town run daily)
	var span: Variant = clampi(d - int(b.get("ld", d - Sickness.CADENCE)), 1, 30)
	b["ld"] = d
	b["span"] = span
	if int(b["qd"]) < d:
		await _run_queue(game, t, e, b, d, rng)
	if Sickness.prof_on: t0 = _pf("queue", t0)
	if part == 0:
		await _roll_town(game, t, e, b, d, rng, span)
		if Sickness.prof_on: t0 = _pf("roll", t0)
	# v0.034: the common folk (cohort rows), as counts, once per run (in play: job part 1, with the queue)
	await _pool_day(game, t, e, b, d, rng, span)
	if Sickness.prof_on: t0 = _pf("pools", t0)
	await _outbreak_news(game, t, b, d)
	# counters for the screen: 60 days of open cases, 8 days per disease, the week's new cases (one entry per day
	# covered)
	var act: Dictionary = b["act"]
	var n: Variant = 0
	for dis: Variant in act:
		await _checkpoint("town_day:loop")
		n += int(act[dis])
	var h: Array = b["h60"]
	var hd: Dictionary = b["hd"]
	for dis: Variant in act:
		await _checkpoint("town_day:loop")
		if not hd.has(dis):
			hd[dis] = []
	for s: Variant in span:
		await _checkpoint("town_day:loop")
		h.append(n)
		for dis: Variant in hd:
			await _checkpoint("town_day:loop")
			(hd[dis] as Array).append(int(act.get(dis, 0)))
	while h.size() > 60:
		await _checkpoint("town_day:loop")
		h.pop_front()
	for dis: Variant in hd.keys():
		await _checkpoint("town_day:loop")
		var a: Array = hd[dis]
		while a.size() > 8:
			await _checkpoint("town_day:loop")
			a.pop_front()
		if a.max() == 0:
			hd.erase(dis)
	var nw: Array = b["new"]
	while not nw.is_empty() and int(nw[0][0]) <= d - 7:
		await _checkpoint("town_day:loop")
		nw.pop_front()

func _world_day(game: Variant, d: int) -> void:
	await _checkpoint("_world_day:enter")
	var w: Dictionary = game.world
	var t0: Variant = _active_usec() if Sickness.prof_on else 0
	Sickness.data()
	var rng: Variant = RandomNumberGenerator.new()
	_rngs.append(rng)
	rng.seed = hash([int(w.get("seed", 0)), d, "sk"])
	await _edge(game, d, rng)
	var t1: Variant = _active_usec() if Sickness.prof_on else 0
	for wid: Variant in w.get("warbands", {}).keys():
		await _checkpoint("_world_day:loop")
		if (absi(hash(String(wid))) + d) % 7 == 0 and w["warbands"].has(wid):
			await _force_turn(game, w["warbands"][wid], d)
	if Sickness.prof_on: t1 = _pf("forces", t1)
	await _company_day(game, d)
	if Sickness.prof_on:
		_pf("company", t1)

func _roll_town(game: Variant, t: Dictionary, e: Dictionary, b: Dictionary, d: int, rng: RandomNumberGenerator, span: int = 1, share: float = 1.0) -> void:
	await _checkpoint("_roll_town:enter")
	var tf: Variant = (await _tf(e, b, d))
	var ec: Array = tf["ec"]
	var comps: Variant = []
	var tot: Variant = 0.0
	for i: Variant in ec.size():
		await _checkpoint("_roll_town:loop")
		if float(ec[i]) > 0.0:
			comps.append([i, 0, float(ec[i])])
			tot += float(ec[i])
	var act: Dictionary = b["act"]
	if not act.is_empty():
		var pop: Variant = maxf(1.0, float(e["pop"]))
		for dis: Variant in act:
			await _checkpoint("_roll_town:loop")
			var bt: Variant = float(Sickness.row(dis).get("town", 0.0))
			if bt <= 0.0 or int(act[dis]) <= 0:
				continue
			var i: Variant = Sickness.ids.find(dis)
			var ex: Variant = bt * float(act[dis]) * float(tf["sf"][i]) / pop * float(tf["mm"][i]) * float(tf["slots"])
			comps.append([i, 1, ex])
			tot += ex
	if tot <= 0.0:
		return
	var rms: Array = tf["rm"]
	var mms: Array = tf["mm"]
	var k: Variant = Sickness._poisson(rng, tot * float(span) * share)   # (two halves = one Poisson draw of the whole)
	if Sickness.prof_parts:
		Sickness.prof["#cand"] = int(Sickness.prof.get("#cand", 0)) + k
	for j: Variant in k:
		await _checkpoint("_roll_town:loop")
		var day: Variant = float(d - rng.randi() % span)   # the day of the covered span he catches it
		var x: Variant = rng.randf() * tot
		var cp: Array = comps[-1]
		for cc: Variant in comps:
			await _checkpoint("_roll_town:loop")
			x -= float(cc[2])
			if x <= 0.0:
				cp = cc
				break
		var pk: Variant = (await _pick_reg(e, b, rng))
		if pk.is_empty():
			continue
		var f: Dictionary = pk[0]
		var p: Array = pk[1]
		var i: int = cp[0]
		var dis: String = Sickness.ids[i]
		# accepted with his catch / the bound, then (conditions) with his home's K / its bound: two independent draws,
		# the same chance as one draw on the product, and the home is looked at only for those still in
		var acc: Variant = Sickness.catch_m(f, p, dis, {}, day) * float(rms[i]) / float(mms[i])
		if acc <= 0.0 or rng.randf() >= acc:
			continue
		var r: Variant = Sickness.row(dis)
		if int(cp[1]) == 0 and rng.randf() >= Sickness._k_reg(e, pk[3], int(pk[2]), r, float(tf["cloth"])) / float(tf["km"][i]):
			continue
		var src: Variant = "town:caught from the town's sick in %s" % t["name"]
		if int(cp[1]) == 0:
			src = "cond:" + Sickness.cond_words(e, f, r, float(tf["room"]), float(tf["cloth"]))
		await infect(game, t, f, p, dis, day, src, rng)

func _run_queue(game: Variant, t: Dictionary, e: Dictionary, b: Dictionary, d: int, rng: RandomNumberGenerator) -> void:
	await _checkpoint("_run_queue:enter")
	var q: Dictionary = b["q"]
	var k0: Variant = int(b["qd"]) + 1
	if q.is_empty():
		b["qd"] = d
		return
	for k: Variant in range(k0, d + 1):
		await _checkpoint("_run_queue:loop")
		b["qd"] = k   # events pushed while this day runs wait for the next
		var ks: Variant = str(k)
		if not q.has(ks):
			continue
		var due: Array = q[ks]
		q.erase(ks)
		if Sickness.prof_parts:
			Sickness.prof["#ev"] = int(Sickness.prof.get("#ev", 0)) + due.size()
		for ev: Variant in due:   # (in the order they were queued: deterministic)
			await _checkpoint("_run_queue:loop")
			if Sickness.prof_parts:
				var te: Variant = _active_usec()
				await _event(game, t, e, b, ev, d, rng)
				_pf("ev kind %d" % int(ev[1]), te)
				Sickness.prof["#ev%d" % int(ev[1])] = int(Sickness.prof.get("#ev%d" % int(ev[1]), 0)) + 1
			else:
				await _event(game, t, e, b, ev, d, rng)

func _event(game: Variant, t: Dictionary, e: Dictionary, b: Dictionary, ev: Array, d: int, rng: RandomNumberGenerator) -> void:
	await _checkpoint("_event:enter")
	var fams: Array = e["fams"]
	var fid: Variant = int(ev[2])
	if fid < 0 or fid >= fams.size():
		return
	var f: Dictionary = fams[fid]
	var pid: Variant = int(ev[3])
	var key: Variant = str(pid)
	var dis: Variant = String(ev[4])
	var c: Array = Sickness.case_of(f, pid)
	match int(ev[1]):
		0:
			if c.is_empty() or String(c[Sickness.C_DIS]) != dis:
				return
			if f["gone"]:
				Sickness._drop_case(e, b, f, key, c, Sickness._stop(c))
				return
			var nxt: Variant = Sickness._stop(c)
			if nxt > float(d):
				Sickness._push(b, [nxt, 0, fid, pid, dis, ""])
				return
			if float(c[Sickness.C_DIE]) < 0.0:
				Sickness._recover(e, b, f, key, c, rng)
				return
			var p: Variant = Persons.by_pid(f, pid)
			if p.is_empty():
				Sickness._drop_case(e, b, f, key, c, nxt)
			else:
				await kill(game, t, f, p, float(c[Sickness.C_DIE]), "sickness", Sickness.dname(dis))
		1:
			if f["gone"]:
				return
			var p2: Variant = Persons.by_pid(f, pid)
			var src: Variant = String(ev[5])
			if p2.is_empty() or (not src.begins_with("relapse") and not (String(p2[4]) in Sickness.HOME)):
				return
			await infect(game, t, f, p2, dis, float(ev[0]), src, rng)
		2:
			if c.is_empty() or String(c[Sickness.C_DIS]) != dis or int(c[Sickness.C_BON]) == 1 or int(c[Sickness.C_BIZ]) < 0 or Sickness._stop(c) <= float(d):
				return
			var bz: Dictionary = e["biz"][int(c[Sickness.C_BIZ])]
			bz["sick"] = int(bz.get("sick", 0)) + 1
			c[Sickness.C_BON] = 1

func infect(game: Variant, t: Dictionary, f: Dictionary, p: Array, dis: String, day: float, src: String, rng: RandomNumberGenerator, u: Unit = null) -> bool:
	await _checkpoint("infect:enter")
	if not Sickness.prof_parts:
		return (await _infect(game, t, f, p, dis, day, src, rng, u))
	var t0: Variant = _active_usec()
	var ok: Variant = (await _infect(game, t, f, p, dis, day, src, rng, u))
	_pf("infect (nested)", t0)
	Sickness.prof["#inf"] = int(Sickness.prof.get("#inf", 0)) + 1
	return ok

func _infect(game: Variant, t: Dictionary, f: Dictionary, p: Array, dis: String, day: float, src: String, rng: RandomNumberGenerator, u: Unit = null) -> bool:
	await _checkpoint("_infect:enter")
	if f.get("gone", false) or src == "":
		return false
	var key: Variant = str(p[0])
	if f.has("sk") and (f["sk"] as Dictionary).has(key):
		return false
	if Sickness.immune(f, int(p[0]), dis, day):
		return false
	var e: Dictionary = t["econ"]
	var r: Variant = Sickness.row(dis)
	if r.is_empty():
		return false
	var b: Variant = Sickness.book(e)
	var inc: Variant = float(rng.randi_range(int(r["inc"][0]), int(r["inc"][1])))
	var sd: Variant = float(rng.randi_range(int(r["sick"][0]), int(r["sick"][1])))
	var on: Variant = day + inc
	var end: Variant = on + sd
	var q: Variant = minf(0.9, float(r["death"][Sickness.band(p)]) * Sickness._bc_death(f, key) * Sickness.deadliness)
	var uu: Variant = rng.randf()
	var die: Variant = Sickness._death_day(on, end, q, uu)
	var bed: Variant = 1 if rng.randf() < float(r["bed"]) else 0
	var st: Variant = String(p[4])
	var counted: Variant = 1 if st in Sickness.HOME else 0
	var biz: Variant = -1
	if counted == 1 and int(p[6]) == 0:
		biz = (await _job_biz(e, f, p))
	var shed: Variant = day + inc * (1.0 - float(r.get("shed", 0.5)))
	var c: Variant = [dis, day, on, end, die, src, bed, 0, uu, q, biz, counted, 0, shed]
	if not f.has("sk"):
		f["sk"] = {}
	f["sk"][key] = c
	Sickness._yr(b, day, 0)
	b["cases"][dis] = int(b["cases"].get(dis, 0)) + 1
	if counted == 1:
		var was: Variant = int(b["act"].get(dis, 0))
		b["act"][dis] = was + 1
		(b["new"] as Array).append([int(day), dis])
		if was == 0:
			b["first"][dis] = [int(day), Sickness.origin_text(src, day)]
	Sickness._push(b, [Sickness._stop(c), 0, int(f["id"]), int(p[0]), dis, ""])
	if bed == 1 and biz >= 0:
		Sickness._push(b, [on, 2, int(f["id"]), int(p[0]), dis, ""])
	if u == null and int(p[5]) >= 0:
		u = (await _find_unit(game, t, p))
	if u != null:
		Sickness.mirror(u, c)
	if Sickness.log_cases:
		Sickness.case_log.append([String(t.get("id", "")), int(p[0]), dis, src, day])
	if counted == 1:
		var t0: Variant = _active_usec() if Sickness.prof_parts else 0
		await _household(game, t, e, b, f, p, c, rng)
		if Sickness.prof_parts: t0 = _pf("inf household", t0)
		if biz >= 0:
			await _workplace(game, t, e, b, f, p, c, rng)
		if Sickness.prof_parts: t0 = _pf("inf work", t0)
		if st == "militia":
			await _garrison(game, t, e, b, f, p, c, rng)
		if Sickness.prof_parts: t0 = _pf("inf garrison", t0)
	return true

func _job_biz(e: Dictionary, f: Dictionary, p: Array) -> int:
	await _checkpoint("_job_biz:enter")
	var jobs: Dictionary = f["jobs"]
	if jobs.is_empty():
		return -1
	var born: Variant = float(p[3])
	var pid: Variant = int(p[0])
	var idx: Variant = -int(f.get("hands", 0))
	for q: Variant in Persons.pp(f):
		await _checkpoint("_job_biz:loop")
		if int(q[6]) == 0 and (String(q[4]) == "" or String(q[4]) == "hire"):
			var bq: Variant = float(q[3])
			if bq < born or (bq == born and int(q[0]) < pid):
				idx += 1
	if idx < 0:
		return -1
	if jobs.size() == 1:
		for kk: Variant in jobs:
			await _checkpoint("_job_biz:loop")
			return int(kk) if idx < int(jobs[kk]) else -1
	for kk: Variant in Sickness._job_keys(e, f):
		await _checkpoint("_job_biz:loop")
		var n: Variant = int(jobs[kk])
		if idx < n:
			return int(kk)
		idx -= n
	return -1

func _household(_game: Variant, _t: Dictionary, e: Dictionary, b: Dictionary, f: Dictionary, p: Array, c: Array, rng: RandomNumberGenerator) -> void:
	await _checkpoint("_household:enter")
	var dis: Variant = String(c[Sickness.C_DIS])
	var r: Variant = Sickness.row(dis)
	var bh: Variant = float(r["home"])
	if bh <= 0.0:
		return
	var from: Variant = maxf(float(c[Sickness.C_SHED]), float(e.get("day", 0)))
	var to: Variant = Sickness._stop(c)
	if to <= from:
		return
	var bhr: Variant = bh * Sickness._rm_town(e, b, dis, r)
	var nm: Variant = ""
	var w: Variant = to - from
	var pid: Variant = int(p[0])
	var cc: PackedFloat64Array = Sickness.CATCH[dis]
	var sk: Dictionary = f.get("sk", {})
	var im: Dictionary = f.get("im", {})
	var bcd: Dictionary = f.get("bc", {})
	for lst: Variant in [f["pp"], f.get("kp", [])]:
		await _checkpoint("_household:loop")
		for q: Variant in lst:
			await _checkpoint("_household:loop")
			if int(q[0]) == pid or not (String(q[4]) in Sickness.HOME):
				continue
			# his catch (catch_m inlined: sick already or immune = 0; age band; body condition)
			var k: Variant = str(q[0])
			if sk.has(k) or (im.has(k) and float(im[k].get(dis, -1.0)) > from):
				continue
			var lam: Variant = bhr * cc[int(q[6])]
			if bcd.has(k):
				lam *= 1.0 + Sickness.BODY_CATCH * (1.0 - float(bcd[k]))
			if lam <= 0.0:
				continue
			var P: Variant = 1.0 - exp(-lam * w)
			if rng.randf() < P:
				var dt: Variant = -log(1.0 - rng.randf() * P) / lam
				if nm == "":
					nm = Persons.name_of(f, p, Persons.race_of(e))
				Sickness._push(b, [ceilf(from + dt), 1, int(f["id"]), int(q[0]), dis, "home:%s (household)" % nm])

func _workplace(_game: Variant, _t: Dictionary, e: Dictionary, b: Dictionary, f: Dictionary, p: Array, c: Array, rng: RandomNumberGenerator) -> void:
	await _checkpoint("_workplace:enter")
	var dis: Variant = String(c[Sickness.C_DIS])
	var r: Variant = Sickness.row(dis)
	var bw: Variant = float(r["work"])
	var biz: Variant = int(c[Sickness.C_BIZ])
	if bw <= 0.0 or biz < 0 or biz >= (e["biz"] as Array).size():
		return
	var bz: Dictionary = e["biz"][biz]
	var staff: Variant = int(bz["workers"]) - 1
	var from: Variant = maxf(float(c[Sickness.C_SHED]), float(e.get("day", 0)))
	var to: Variant = Sickness._stop(c)
	if staff <= 0 or to <= from:
		return
	var tf: Dictionary = b.get("tf", {})   # (the catch bound does not change with the season: last made is fine)
	if not tf.has("mm"):
		tf = (await _tf(e, b, int(e.get("day", 0))))
	var i: Variant = Sickness.ids.find(dis)
	var mx: Variant = float(tf["mm"][i])
	var k: Variant = Sickness._poisson(rng, bw * (to - from) * float(staff) * mx)
	if k <= 0:
		return
	var key: Variant = str(biz)
	var wk: Variant = int(e.get("day", 0)) / 7
	# one pass over the town's families a week: every business's job-holding families (a family that took a place
	# there since is missed until the next week's list; one that left is skipped: its place there counts 0 and the
	# person drawn must hold a place there now)
	# v0.074: the week's list lives in the town's economy as family ids (e["_hc"]), so it is saved with the town.
	# It was a static cache keyed by the town's name: a reload mid-week drew from a list made after the load, and a
	# second load in the same process drew from the families of the world it replaced.
	var hc: Dictionary = e.get("_hc", {}) if e.get("_hc") is Dictionary else {}
	if int(hc.get("wk", -1)) != wk or not hc.get("b") is Dictionary:
		var all: Variant = {}
		for f3: Variant in e["fams"]:
			await _checkpoint("_workplace:loop")
			if f3["gone"]:
				continue
			var jb: Dictionary = f3["jobs"]
			for kk: Variant in jb:
				await _checkpoint("_workplace:loop")
				if not all.has(kk):
					all[kk] = [[], 0]
				all[kk][0].append(int(f3["id"]))
				all[kk][1] = int(all[kk][1]) + int(jb[kk])
		hc = {"wk": wk, "b": all}
		e["_hc"] = hc
	var by: Dictionary = hc["b"]
	if not by.has(key):
		return
	var holders: Array = by[key][0]
	var tot: int = int(by[key][1])
	if tot <= 0 or holders.is_empty():
		return
	var fams: Array = e["fams"]
	var nm: Variant = ""
	var rm: Variant = Sickness._rm_town(e, b, dis, r)
	for j: Variant in k:
		await _checkpoint("_workplace:loop")
		var x: Variant = rng.randi() % tot
		var f2: Dictionary = fams[int(holders[0])]
		for hi: Variant in holders:
			await _checkpoint("_workplace:loop")
			var h: Dictionary = fams[int(hi)]
			x -= int(h["jobs"].get(key, 0))   # (a place left since the day's list was made counts 0)
			if x < 0:
				f2 = h
				break
		if f2["gone"]:
			continue
		# one of the family's people at that business: a random grown-up at home until one holds a place there
		var a2: Array = f2["pp"]
		var q: Array = []
		for tries: Variant in 8:
			await _checkpoint("_workplace:loop")
			var cq: Array = a2[rng.randi() % a2.size()] if not a2.is_empty() else []
			if not cq.is_empty() and int(cq[6]) == 0 and (String(cq[4]) == "" or String(cq[4]) == "hire") and (await _job_biz(e, f2, cq)) == biz:
				q = cq
				break
		if q.is_empty() or int(q[0]) == int(p[0]):
			continue
		var m: Variant = Sickness.catch_m(f2, q, dis, r, from) * rm
		if rng.randf() < m / mx:
			if nm == "":
				nm = "%s at %s" % [Persons.name_of(f, p, Persons.race_of(e)), Businesses.title(e, bz)]
			Sickness._push(b, [ceilf(from + rng.randf() * (to - from)), 1, int(f2["id"]), int(q[0]), dis, "work:" + nm])

func _garrison(game: Variant, t: Dictionary, e: Dictionary, b: Dictionary, f: Dictionary, p: Array, c: Array, rng: RandomNumberGenerator) -> void:
	await _checkpoint("_garrison:enter")
	if game == null or not game.world.has("militia"):
		return
	var dis: Variant = String(c[Sickness.C_DIS])
	var r: Variant = Sickness.row(dis)
	var bw: Variant = float(r["work"])
	var from: Variant = maxf(float(c[Sickness.C_SHED]), float(e.get("day", 0)))
	var to: Variant = Sickness._stop(c)
	if bw <= 0.0 or to <= from:
		return
	var rm: Variant = Sickness.race_mult(r, Persons.race_of(e))
	var nm: Variant = "%s of the militia" % Persons.name_of(f, p, Persons.race_of(e))
	for u2: Variant in Militia.units_of(game, String(t["id"])):
		await _checkpoint("_garrison:loop")
		if u2.uid == int(p[5]) or u2.family < 0 or u2.family >= (e["fams"] as Array).size():
			continue
		var f2: Dictionary = e["fams"][u2.family]
		var q: Variant = Persons.by_uid(f2, u2.uid)
		if q.is_empty():
			continue
		var lam: Variant = bw * Sickness.catch_m(f2, q, dis, r, from) * rm
		if lam > 0.0 and rng.randf() < 1.0 - exp(-lam * (to - from)):
			Sickness._push(b, [ceilf(from + rng.randf() * (to - from)), 1, int(f2["id"]), int(q[0]), dis, "garrison:" + nm])

func _tf(e: Dictionary, b: Dictionary, d: int) -> Dictionary:
	await _checkpoint("_tf:enter")
	var si: Variant = Calendar.season_index(float(d))
	var wk: Variant = (d + int(b.get("stag", 0))) / 7
	var stamp: Variant = si * 1000000 + wk
	var tf: Dictionary = b.get("tf", {})
	if int(tf.get("st", -1)) == stamp:
		return tf
	if Sickness.prof_parts:
		Sickness.prof["#tf"] = int(Sickness.prof.get("#tf", 0)) + 1
	Sickness.data()
	if int(tf.get("wk", -1)) != wk:
		# a new week: the body-condition bound of the week before (every family below full condition has had its
		# turn since) and the largest household (the candidate draw's slots per family)
		b["bcl"] = minf(float(b.get("bcw", 1.0)), 1.0)
		b["bcw"] = 1.0
		await _reg_build(e, b, wk)
	var race: Variant = Persons.race_of(e)
	var cl: Variant = String(e.get("climate", "temperate"))
	var water: Variant = bool(e.get("terrain", {}).get("water", false))
	var room: Variant = float(TownEcon.culture_of(e)["home"]["room"])
	var pop: Variant = maxf(1.0, float(e.get("pop", 1)))
	var cloth: Variant = 0.5 if float(e.get("hh", {}).get("clothing", 0)) / pop < 0.3 else 0.0
	var nmax: Variant = int(b.get("nmax", Sickness.NMAX))
	if not b.has("nreg"):
		await _reg_build(e, b, wk)
	var slots: Variant = float(b["nreg"])
	var bcmin: Variant = minf(float(b.get("bcl", 1.0)), float(b.get("bcw", 1.0)))
	var bcb: Variant = 1.0 + float(Sickness.data()["body"]["catch"]) * (1.0 - bcmin)
	var T: Variant = []; var km: Variant = []; var mm: Variant = []; var ec: Variant = []; var sf: Variant = []; var rms: Variant = []
	for dis: Variant in Sickness.ids:
		await _checkpoint("_tf:loop")
		var r: Variant = Sickness.row(dis)
		var cm: Variant = 0.0
		for k: Variant in r["catch"]:
			await _checkpoint("_tf:loop")
			cm = maxf(cm, float(r["catch"][k]))
		rms.append(Sickness.race_mult(r, race))
		var mx: Variant = cm * float(rms[-1]) * bcb
		var tv: Variant = 0.0
		var kx: Variant = 1.0
		if String(r["where"]) == "town":
			tv = float(r["base"]) * float(r["season"][si]) * float(r["climate"].get(cl, 1.0)) * float(r["water"][0 if water else 1])
			# K's bound from the week's register index (the homes' conditions as the index saw them: the draw reads
			# them from the same index, so no home is ever above the bound)
			var kxm: Array = b.get("kx", [1.5, 1.0, 1.0, 1.0])
			kx = 1.0 + float(r["crowd"]) * float(kxm[0]) + float(r["poor"]) * float(kxm[1]) + float(r["hunger"]) * float(kxm[2]) \
				+ float(r["cold"]) * (float(kxm[3]) + cloth) + TownSanitation.exposure(e, r)
		T.append(tv); km.append(kx); mm.append(mx); ec.append(tv * kx * mx * slots); sf.append(Sickness._shed_share(r))
	tf = {"st": stamp, "wk": wk, "T": T, "km": km, "mm": mm, "ec": ec, "sf": sf, "slots": slots, "nmax": nmax, "room": room, "cloth": cloth,
		"race": race, "bcmin": bcmin, "rm": rms}
	b["tf"] = tf
	return tf

func _reg_build(e: Dictionary, b: Dictionary, wk: int) -> void:
	await _checkpoint("_reg_build:enter")
	if Sickness.prof_parts:
		Sickness.prof["#reg"] = int(Sickness.prof.get("#reg", 0)) + 1
	var cum: Variant = PackedInt32Array()
	var fid: Variant = PackedInt32Array()
	var xs: Variant = PackedFloat32Array()   # each home's conditions [crowding above room 0..1.5, poor, hungry, cold]
	var xm: Variant = [0.0, 0.0, 0.0, 0.0]
	var room: Variant = float(TownEcon.culture_of(e)["home"]["room"])
	var n: Variant = 0
	var nm: Variant = 1
	for f: Variant in e["fams"]:
		await _checkpoint("_reg_build:loop")
		if f["gone"] or not f.has("pp"):
			continue
		var s: Variant = (f["pp"] as Array).size() + (f.get("kp", []) as Array).size()
		if s <= 0:
			continue
		cum.append(n)
		fid.append(int(f["id"]))
		n += s
		nm = maxi(nm, s)
		var x: Variant = Sickness._home_x(e, f, room)
		for c: Variant in 4:
			await _checkpoint("_reg_build:loop")
			xs.append(x[c])
			xm[c] = maxf(float(xm[c]), x[c])
	b["nreg"] = n
	b["nmax"] = mini(nm + 1, 40)
	b["kx"] = xm
	b.erase("rid")   # (the old static index's process counter)
	b["reg"] = {"wk": wk, "cum": cum, "fid": fid, "n": n, "xs": xs}

func _pick_reg(e: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> Array:
	await _checkpoint("_pick_reg:enter")
	if not (b.get("reg") is Dictionary) or not (b["reg"].get("cum") is PackedInt32Array):
		# a save from before v0.074 (no index in the book): made now, and the factors follow it
		await _reg_build(e, b, int(b.get("tf", {}).get("wk", 0)))
		b["tf"]["st"] = -1
	var rg: Dictionary = b["reg"]
	var total: int = int(rg["n"])
	if total <= 0:
		return []
	var x: Variant = rng.randi() % total
	var cum: PackedInt32Array = rg["cum"]
	var i: Variant = cum.bsearch(x, false) - 1   # the last family starting at or before x
	var fid: PackedInt32Array = rg["fid"]
	var f: Dictionary = e["fams"][fid[i]]
	var j: Variant = x - cum[i]
	if f["gone"]:
		return []
	var a: Array = f["pp"]
	var k: Array = f.get("kp", [])
	if j >= a.size() + k.size():
		return []
	var p: Array = a[j] if j < a.size() else k[j - a.size()]
	if not (String(p[4]) in Sickness.HOME):
		return []
	return [f, p, i, rg["xs"]]   # (the home's index and the index's conditions: its K for the draw)

func kill(game: Variant, t: Dictionary, f: Dictionary, p: Array, day: float, cause: String, detail: String) -> void:
	await _checkpoint("kill:enter")
	var t0: Variant = _active_usec() if Sickness.prof_parts else 0
	await _kill(game, t, f, p, day, cause, detail)
	if Sickness.prof_parts: _pf("kill (nested) " + cause, t0)

func _kill(game: Variant, t: Dictionary, f: Dictionary, p: Array, day: float, cause: String, detail: String) -> void:
	await _checkpoint("_kill:enter")
	var e: Dictionary = t["econ"]
	var b: Variant = Sickness.book(e)
	var race: Variant = Persons.race_of(e)
	var pid: Variant = int(p[0])
	var key: Variant = str(pid)
	var nm: Variant = Persons.name_of(f, p, race)
	var age: Variant = Persons.age_of(p, day)
	var sex: Variant = int(p[2])
	var st: Variant = String(p[4])
	var c: Variant = Sickness.case_of(f, pid)
	if not c.is_empty():
		Sickness._drop_case(e, b, f, key, c, day)
	var why: Variant = ("died of " + detail) if cause == "sickness" else ("died in childbirth" if cause == "childbirth" else "starved to death")
	if int(p[5]) >= 0:
		await _remove_unit(game, t, f, p, st, int(p[5]), "%s %s." % [nm, why])
	Persons.log_life(p, day, "died", why)
	if int(p[6]) == 2:
		Persons.forget(e, f, p)
		Persons.kp(f).erase(p)
		f["kids"] = maxi(0, int(f["kids"]) - 1)
		e["pop"] = int(e["pop"]) - 1
	else:
		var s: Variant = "old" if int(p[6]) == 1 else ("m" if sex == 0 else "f")
		Persons.forget(e, f, p)
		Persons.pp(f).erase(p)
		if st != "company" and int(f[s]) > 0:
			f[s] = int(f[s]) - 1
			e["pop"] = int(e["pop"]) - 1
			if s != "old":
				e["adults"] = int(e["adults"]) - 1
		if st in Sickness.SERVICE:
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
		Sickness._yr(b, day, 1)
	elif cause == "starved":
		b["starved"] = int(b.get("starved", 0)) + 1
		Sickness._yr(b, day, 2)
	if st != "company":
		Families.reassign(e, f)
		if Families.people(f) <= 0:
			Families.extinct(e, f, day)

func _remove_unit(game: Variant, t: Dictionary, _f: Dictionary, p: Array, st: String, uid: int, line: String) -> void:
	await _checkpoint("_remove_unit:enter")
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
				for x: Variant in game.company:
					await _checkpoint("_remove_unit:loop")
					if x.squad == uid:
						x.squad = -1
				game.invalidate_deploy()
				CampaignWorld.log_event(game, line)
			return
		"hire":
			var rec: Array = t.get("recruits", [])
			for i: Variant in rec.size():
				await _checkpoint("_remove_unit:loop")
				if rec[i] is Unit and rec[i].uid == uid:
					WorldAudit.lose_items((rec[i] as Unit).equip.values(), "-kit of a recruit who died naturally")
					rec.remove_at(i)
					return
			return
	for wid: Variant in w.get("warbands", {}):
		await _checkpoint("_remove_unit:loop")
		var wb: Dictionary = w["warbands"][wid]
		var units: Array = wb["units"]
		for i: Variant in units.size():
			await _checkpoint("_remove_unit:loop")
			if units[i].uid != uid:
				continue
			units[i].dead = true
			WorldAudit.lose_items((units[i] as Unit).equip.values(), "-kit of a force member who died naturally")
			units.remove_at(i)
			if wb.has("crew"):
				var crew: Array = wb["crew"]
				for j: Variant in crew.size():
					await _checkpoint("_remove_unit:loop")
					if crew[j].size() > 3 and int(crew[j][3]) == uid:
						crew.remove_at(j)
						break
			if w.has("army"):
				Army.state(w)["roll"].erase(str(uid))
			return
	p[5] = -1

func _pool_day(_game: Variant, t: Dictionary, e: Dictionary, b: Dictionary, d: int, rng: RandomNumberGenerator, span: int) -> void:
	await _checkpoint("_pool_day:enter")
	var tf: Variant = (await _tf(e, b, d))
	var pop: Variant = maxf(1.0, float(e["pop"]))
	var act: Dictionary = b["act"]
	var room: Variant = float(tf["room"])
	var cloth: Variant = float(tf["cloth"])
	for f: Variant in e["fams"]:
		await _checkpoint("_pool_day:loop")
		if not Population.is_cohort(f): continue
		var tp: Variant = _active_usec() if Sickness.prof_parts else 0
		if f.has("psk"): (await _pool_resolve(e, b, f, d, rng))
		if Sickness.prof_parts: tp = _pf("pools resolve", tp)
		if f.get("gone", false): continue
		var people: Variant = SicknessGroups._pool_people(f)
		var total: Variant = int(people["workers"]) + int(people["children"]) + int(people["elders"])
		if total <= 0: continue
		var mates: Variant = maxf(0.0, float(Families.people(f)) / float(Population.households(f)) - 1.0)   # housemates per person
		var bc: Dictionary = f.get("pool_condition", {})
		var open: Variant = (await _pool_open(f))   # the row's open cases by disease and by "disease|band", counted once
		for i: Variant in Sickness.ids.size():
			await _checkpoint("_pool_day:loop")
			var dis: String = Sickness.ids[i]
			var r: Variant = Sickness.row(dis)
			var town: Variant = float(r.get("town", 0.0)) * float(act.get(dis, 0)) * float(tf["sf"][i]) / pop
			var cond: Variant = float(tf["T"][i])
			if cond > 0.0: cond *= Sickness.cond_k(e, f, r, room, cloth)
			var rate: Variant = (cond + town) * float(tf["rm"][i])
			if rate <= 0.0: continue
			var free: Variant = 1.0 - minf(1.0, float(Sickness._pool_immune(f, dis, float(d))) / float(total))
			var src: Variant = ""   # where it began: worked out only when a first case needs it
			var left: Variant = {}   # susceptible people per group after this run's outside cases
			var catches: Variant = {}
			var first: Variant = 0
			for group: Variant in SicknessGroups.POOL_GROUPS:
				await _checkpoint("_pool_day:loop")
				var bnd: String = SicknessGroups.POOL_GROUPS[group]
				var s: Variant = maxf(0.0, float(people[group]) - float(open.get(dis + "|" + bnd, 0))) * free
				var catch: Variant = float(r["catch"][bnd]) * (1.0 + Sickness.BODY_CATCH * (1.0 - float(bc.get(group, 1.0))))
				catches[group] = catch
				left[group] = s
				if s < 1.0: continue
				var n: Variant = mini(int(s), Sickness._poisson(rng, s * rate * catch * float(span)))
				if n <= 0: continue
				if src == "":
					src = "cond:" + Sickness.cond_words(e, f, r, room, cloth)
					if town > cond: src = "town:caught from the town's sick in %s" % t["name"]
				Sickness._pool_infect(e, b, f, dis, bnd, group, n, d, rng, src)
				left[group] = s - float(n)
				first += n
			if first > 0 and float(r.get("home", 0.0)) > 0.0 and mates > 0.0:
				SicknessGroups._pool_household(e, b, f, dis, r, first, mates, left, catches, float(tf["rm"][i]), d, rng)
		if Sickness.prof_parts: _pf("pools roll", tp)

func _pool_resolve(e: Dictionary, b: Dictionary, f: Dictionary, d: int, rng: RandomNumberGenerator) -> void:
	await _checkpoint("_pool_resolve:enter")
	var keep: Array = []
	var died: Variant = 0
	var gone: Variant = bool(f.get("gone", false))
	for c: Variant in f["psk"]:
		await _checkpoint("_pool_resolve:loop")
		var dis: Variant = String(c[0])
		if gone:   # the row died out or left: its open cases leave the town's counters
			Sickness._act_less(b, dis, int(c[2]) - (int(c[3]) if bool(c[6]) else 0))
			continue
		if not bool(c[6]) and int(c[4]) <= d:
			c[6] = true
			var killed: Variant = (await _pool_kill(e, f, String(c[1]), int(c[3]), float(c[4]), dis, rng))
			Sickness._act_less(b, dis, int(c[3]))
			if killed > 0:
				b["deaths"][Sickness.dname(dis)] = int(b["deaths"].get(Sickness.dname(dis), 0)) + killed
				SicknessGroups._yr_n(b, float(c[4]), 1, killed)
				died += killed
		if int(c[5]) <= d:
			var well: Variant = int(c[2]) - int(c[3])
			Sickness._act_less(b, dis, well)
			var imm: Variant = float(Sickness.row(dis).get("immune", 0))
			if imm != 0.0 and well > 0:
				if not f.has("pim"): f["pim"] = {}
				var until: Variant = Sickness.NONE if imm < 0.0 else float(c[5]) + imm * Sickness.year_days()
				var had: Array = f["pim"].get(dis, [0, 0.0])
				f["pim"][dis] = [int(had[0]) + well, maxf(float(had[1]), until)]
			continue
		keep.append(c)
	if keep.is_empty(): f.erase("psk")
	else: f["psk"] = keep
	if died > 0 and not gone:
		var tr: Variant = _active_usec() if Sickness.prof_parts else 0
		if Families.people(f) <= 0: Families.extinct(e, f, float(d))
		else: Families.reassign(e, f)
		if Sickness.prof_parts: _pf("pools reassign", tr)

func _pool_kill(e: Dictionary, f: Dictionary, bnd: String, k: int, day: float, dis: String, rng: RandomNumberGenerator) -> int:
	await _checkpoint("_pool_kill:enter")
	var want: Array = {"adult": [0, 1], "child": [3], "elder": [2]}[bnd]
	var killed: Variant = 0
	for i: Variant in k:
		await _checkpoint("_pool_kill:loop")
		var keys: Array = []
		var tot: Variant = 0
		for key: Variant in f.get("age_bins", {}):
			await _checkpoint("_pool_kill:loop")
			if want.has(Population.bin_category(e, f, String(key), day)):
				keys.append(key); tot += int(f["age_bins"][key])
		if tot <= 0: break
		var x: Variant = rng.randi() % tot
		for key: Variant in keys:
			await _checkpoint("_pool_kill:loop")
			x -= int(f["age_bins"][key])
			if x < 0:
				Population.kill_slots(e, f, String(key), 1, day, "sickness", Sickness.dname(dis))
				killed += 1
				break
	return killed

func _pool_open(f: Dictionary) -> Dictionary:
	await _checkpoint("_pool_open:enter")
	var out: Variant = {}
	for c: Variant in f.get("psk", []):
		await _checkpoint("_pool_open:loop")
		var n: Variant = int(c[2]) - (int(c[3]) if bool(c[6]) else 0)
		out[String(c[0])] = int(out.get(String(c[0]), 0)) + n
		var k: Variant = String(c[0]) + "|" + String(c[1])
		out[k] = int(out.get(k, 0)) + n
	return out

func pool_sick(f: Dictionary, dis: String = "", bnd: String = "") -> int:
	await _checkpoint("pool_sick:enter")
	var n: Variant = 0
	for c: Variant in f.get("psk", []):
		await _checkpoint("pool_sick:loop")
		if (dis == "" or String(c[0]) == dis) and (bnd == "" or String(c[1]) == bnd):
			n += int(c[2]) - (int(c[3]) if bool(c[6]) else 0)
	return n

func _edge(game: Variant, d: int, rng: RandomNumberGenerator) -> void:
	await _checkpoint("_edge:enter")
	var w: Dictionary = game.world
	if w.get("sk_isolated", false):
		return
	var ED: Dictionary = Sickness.data().get("edge", {})
	for dis: Variant in ED:
		await _checkpoint("_edge:loop")
		if rng.randf() >= float(ED[dis]):
			continue
		var t: Variant = (await edge_town(w))
		if t.is_empty():
			continue
		var e: Dictionary = t["econ"]
		var src: Variant = "edge:a traveller from beyond the map edge, day %d" % (d + 1)
		for tries: Variant in 64:
			await _checkpoint("_edge:loop")
			var pk: Variant = Sickness._pick(e, rng, Sickness.NMAX)
			if pk.is_empty() or int(pk[1][6]) != 0:
				continue
			if (await infect(game, t, pk[0], pk[1], String(dis), float(d), src, rng)):
				CampaignWorld.log_event(game, "A traveller from beyond the edge of the map brought %s to %s." % [Sickness.dname(String(dis)), t["name"]])
				TownEcon.town_hist(e, "A traveller from beyond the map's edge brought %s." % Sickness.dname(String(dis)), float(d))
				break

func edge_town(w: Dictionary) -> Dictionary:
	await _checkpoint("edge_town:enter")
	var mw: Variant = float(w.get("w", WorldGen.W)) * float(w.get("cell", WorldGen.CELL))
	var mh: Variant = float(w.get("h", WorldGen.H)) * float(w.get("cell", WorldGen.CELL))
	var best: Dictionary = {}
	var bd: Variant = INF
	for tid: Variant in w["towns"]:
		await _checkpoint("edge_town:loop")
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var pos: Vector2 = t["pos"]
		var dd: Variant = minf(minf(pos.x, mw - pos.x), minf(pos.y, mh - pos.y))
		if dd < bd:
			bd = dd
			best = t
	return best

func _force_turn(game: Variant, wb: Dictionary, d: int) -> void:
	await _checkpoint("_force_turn:enter")
	if not Army.is_people_band(wb) or String(wb.get("kind", "")) in ["militia", "caravan"]:
		return
	var w: Dictionary = game.world
	if not w.has("army"):
		return
	var roll: Dictionary = Army.state(w)["roll"]
	var men: Variant = []
	for u: Variant in wb["units"]:
		await _checkpoint("_force_turn:loop")
		if not u.dead and roll.has(str(u.uid)):
			men.append(u)
	if men.is_empty():
		return
	var day: Variant = float(d)
	var rng: Variant = RandomNumberGenerator.new()
	_rngs.append(rng)
	rng.seed = hash([int(w.get("seed", 0)), String(wb["id"]), d, "skf"])
	var short: Variant = clampf(1.0 - Supplies.days(wb) / 3.0, 0.0, 1.0)
	var near: Variant = (await _near_town(w, wb))
	var cl: Variant = String(near.get("econ", {}).get("climate", "temperate")) if not near.is_empty() else "temperate"
	var fw: Variant = Army.force_word(w, wb)
	await _group_turn(game, men, day, 7.0, rng, "camp", short, cl, "camp:the camp of %s in the field" % fw, "camp:the sick of %s" % fw, roll)
	if not near.is_empty():
		var stay: Variant = float(Sickness.data()["carrier"]["stay"])
		var src: Variant = "carrier:came with %s's soldiers, day %d" % [CampaignWorld.faction_the(String(wb["faction"])), d + 1]
		for u: Variant in men:
			await _checkpoint("_force_turn:loop")
			if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
				await seed_town(game, near, u.sick, stay, rng, src)
		for u: Variant in men:
			await _checkpoint("_force_turn:loop")
			var pr: Variant = Sickness._person_of(w, u, roll)
			if not pr.is_empty():
				await catch_in_town(game, pr[0], pr[1], pr[2], near, stay, rng, u)

func _near_town(w: Dictionary, wb: Dictionary) -> Dictionary:
	await _checkpoint("_near_town:enter")
	var px: Variant = float(Sickness.data()["carrier"]["near_px"])
	var pos: Vector2 = wb.get("pos", Vector2.ZERO)
	for tid: Variant in w["towns"]:
		await _checkpoint("_near_town:loop")
		var t: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t) and (t["pos"] as Vector2).distance_to(pos) <= px:
			return t
	return {}

func _group_turn(game: Variant, men: Array, day: float, days: float, rng: RandomNumberGenerator, mode: String, short: float, cl: String,
		src_cond: String, src_contact: String, roll: Dictionary = {}, town: Dictionary = {}) -> void:
	await _checkpoint("_group_turn:enter")
	var w: Dictionary = game.world
	var si: Variant = Calendar.season_index(day)
	var n: Variant = float(men.size())
	var shed: Variant = {}
	for u: Variant in men:
		await _checkpoint("_group_turn:loop")
		if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
			shed[u.sick] = int(shed.get(u.sick, 0)) + 1
	var lam: Variant = []   # per disease: [cond rate, contact rate] per man-day before his own multiplier
	var any: Variant = false
	var tf: Dictionary = {}
	var tact: Dictionary = {}
	var tpop: Variant = 1.0
	if not town.is_empty():
		tf = (await _tf(town["econ"], Sickness.book(town["econ"]), int(day)))
		tact = Sickness.book(town["econ"])["act"]
		tpop = maxf(1.0, float(town["econ"]["pop"]))
	for i: Variant in Sickness.ids.size():
		await _checkpoint("_group_turn:loop")
		var r: Variant = Sickness.row(Sickness.ids[i])
		var lc: Variant = 0.0
		if String(r["where"]) == mode:
			lc = float(r["base"]) * float(r["season"][si]) * float(r["climate"].get(cl, 1.0)) * (1.0 + float(r["hunger"]) * short)
		elif not tf.is_empty() and String(r["where"]) == "town":
			lc = float(tf["T"][i])   # lodging in town: the town's conditions at an ordinary roof (K = 1)
		var lk: Variant = float(r["camp"]) * float(shed.get(Sickness.ids[i], 0)) / n
		if not tact.is_empty():
			lk += float(r.get("town", 0.0)) * float(tact.get(Sickness.ids[i], 0)) * float(tf["sf"][i]) / tpop
		lam.append([lc, lk])
		if lc > 0.0 or lk > 0.0:
			any = true
	if not any:
		return
	var by_race: Variant = {}   # a man's risk by disease depends only on his race here: [parts, total, chance] per race
	for u: Variant in men:
		await _checkpoint("_group_turn:loop")
		if u.sick != "" and day < u.sick_to:
			continue
		if not by_race.has(u.race):
			var tt: Variant = 0.0
			var pp2: Variant = []
			for i: Variant in Sickness.ids.size():
				await _checkpoint("_group_turn:loop")
				var l: Array = lam[i]
				if float(l[0]) <= 0.0 and float(l[1]) <= 0.0:
					pp2.append(0.0)
					continue
				var r2: Variant = Sickness.row(Sickness.ids[i])
				var v: Variant = (float(l[0]) + float(l[1])) * float(Sickness.CATCH[Sickness.ids[i]][0]) * Sickness.race_mult(r2, u.race)
				pp2.append(v)
				tt += v
			by_race[u.race] = [pp2, tt, 1.0 - exp(-tt * days)]
		var rr: Array = by_race[u.race]
		var parts: Array = rr[0]
		var tot: float = rr[1]
		if tot <= 0.0 or rng.randf() >= float(rr[2]):
			continue
		var x: Variant = rng.randf() * tot
		var i2: Variant = 0
		for i: Variant in parts.size():
			await _checkpoint("_group_turn:loop")
			x -= float(parts[i])
			if x <= 0.0:
				i2 = i
				break
		var pr: Variant = Sickness._person_of(w, u, roll)
		if pr.is_empty():
			continue
		var l2: Array = lam[i2]
		var src: Variant = src_cond if rng.randf() * (float(l2[0]) + float(l2[1])) < float(l2[0]) else src_contact
		if src == src_cond and not town.is_empty() and String(Sickness.row(Sickness.ids[i2])["where"]) == "town":
			src = "cond:%s; lodging in %s" % [String(Sickness.row(Sickness.ids[i2]).get("spread", "")), town["name"]]
		elif src == src_contact and not tact.is_empty() and float(Sickness.row(Sickness.ids[i2]).get("town", 0.0)) * float(tact.get(Sickness.ids[i2], 0)) > 0.0 and rng.randf() < 0.5:
			src = "town:caught in %s" % town["name"]
		await infect(game, pr[0], pr[1], pr[2], Sickness.ids[i2], day, src, rng, u)

func _company_day(game: Variant, d: int) -> void:
	await _checkpoint("_company_day:enter")
	if game.company.is_empty():
		return
	var w: Dictionary = game.world
	if w.has("presim") and not w["presim"].get("finished", false):
		return
	var men: Array = []
	for member: Unit in game.company:
		await _checkpoint("_company_day:filter")
		if not member.dead:
			men.append(member)
	if men.is_empty():
		return
	var day: Variant = float(d)
	var rng: Variant = RandomNumberGenerator.new()
	_rngs.append(rng)
	rng.seed = hash([int(w.get("seed", 0)), d, "skco"])
	var town: Dictionary = w["towns"].get(String(game.location), {}) if String(game.location) != "" else {}
	if not TownEcon.has_econ(town):
		town = {}
	var short: Variant = 0.0
	for u: Variant in men:
		await _checkpoint("_company_day:loop")
		match Food.belly_state(u.belly):
			"hungry": short += 0.5
			"starving": short += 1.0
	short /= float(men.size())
	var cl: Variant = String(town.get("econ", {}).get("climate", "temperate")) if not town.is_empty() else "temperate"
	(await _group_turn(game, men, day, 1.0, rng, "town_lodging" if not town.is_empty() else "camp", short, cl,
		"camp:the company's camp in the field", "camp:the company's own sick", {}, town))
	if not town.is_empty():
		var stay: Variant = float(Sickness.data()["carrier"]["stay"])
		for u: Variant in men:
			await _checkpoint("_company_day:loop")
			if u.sick != "" and day >= u.sick_shed and day < u.sick_to:
				await seed_town(game, town, u.sick, stay, rng, "carrier:came with the mercenary company, day %d" % (d + 1))
	# wound rot: open wounds no healer has treated (a town healer's treatment cleans and binds them)
	var R: Variant = Sickness.row("wound_rot")
	if R.is_empty():
		return
	for u: Variant in men:
		await _checkpoint("_company_day:loop")
		if (u.uid + d) % 7 != 0 or (u.sick != "" and day < u.sick_to):
			continue
		var nw: Variant = Sickness.open_wounds(u)
		if nw <= 0:
			continue
		if rng.randf() < 1.0 - pow(1.0 - float(R["base"]), 7.0 * float(nw)):
			var pr: Variant = Sickness._person_of(w, u)
			if not pr.is_empty():
				await infect(game, pr[0], pr[1], pr[2], "wound_rot", day, "wound:%d untreated open wound%s" % [nw, "" if nw == 1 else "s"], rng, u)

func seed_town(game: Variant, t: Dictionary, dis: String, stay: float, rng: RandomNumberGenerator, src: String) -> int:
	await _checkpoint("seed_town:enter")
	if not TownEcon.has_econ(t):
		return 0
	var e: Dictionary = t["econ"]
	var b: Variant = Sickness.book(e)
	var r: Variant = Sickness.row(dis)
	var bt: Variant = float(r.get("town", 0.0))
	if bt <= 0.0:
		return 0
	var day: Variant = float(game.day) if game != null else float(e.get("day", 0))
	var tf: Variant = (await _tf(e, b, int(day)))
	var i: Variant = Sickness.ids.find(dis)
	var mx: Variant = float(tf["mm"][i])
	var k: Variant = Sickness._poisson(rng, bt * stay / maxf(1.0, float(e["pop"])) * mx * float(tf["slots"]))
	var n: Variant = 0
	var rm: Variant = Sickness.race_mult(r, String(tf["race"]))
	for j: Variant in k:
		await _checkpoint("seed_town:loop")
		var pk: Variant = (await _pick_reg(e, b, rng))
		if pk.is_empty():
			continue
		if rng.randf() < Sickness.catch_m(pk[0], pk[1], dis, r, day) * rm / mx:
			if (await infect(game, t, pk[0], pk[1], dis, day, src, rng)):
				n += 1
	return n

func catch_in_town(game: Variant, ht: Dictionary, f: Dictionary, p: Array, t: Dictionary, stay: float, rng: RandomNumberGenerator, u: Unit = null) -> bool:
	await _checkpoint("catch_in_town:enter")
	if not TownEcon.has_econ(t):
		return false
	var b: Variant = Sickness.book(t["econ"])
	var act: Dictionary = b["act"]
	if act.is_empty():
		return false
	var day: Variant = float(game.day) if game != null else float(t["econ"].get("day", 0))
	var pop: Variant = maxf(1.0, float(t["econ"]["pop"]))
	var race: Variant = Persons.race_of(ht["econ"])
	for dis: Variant in act:
		await _checkpoint("catch_in_town:loop")
		var r: Variant = Sickness.row(dis)
		var lam: Variant = float(r.get("town", 0.0)) * float(act[dis]) * Sickness._shed_share(r) / pop * Sickness.catch_m(f, p, dis, r, day) * Sickness.race_mult(r, race)
		if lam > 0.0 and rng.randf() < 1.0 - exp(-lam * stay):
			return (await infect(game, ht, f, p, dis, day, "town:caught in %s" % t["name"], rng, u))
	return false

func _find_unit(game: Variant, t: Dictionary, p: Array) -> Unit:
	await _checkpoint("_find_unit:enter")
	var uid: Variant = int(p[5])
	if game == null or uid < 0:
		return null
	match String(p[4]):
		"company":
			return game.unit_by_uid(uid)
		"hire":
			for u: Variant in t.get("recruits", []):
				await _checkpoint("_find_unit:loop")
				if u is Unit and u.uid == uid:
					return u
			return null
		"militia", "reserve":
			if String(p[4]) == "reserve":
				var reserve: Unit = Mobilization.reserve_unit(game, uid, String(t.get("id", "")))
				if reserve != null and is_same(Persons.by_uid(People.fam_of(t, reserve.family), uid), p):
					return reserve
			for u: Variant in Militia.units_of(game, String(t["id"])):
				await _checkpoint("_find_unit:loop")
				if u.uid == uid:
					return u
			return null
	return null

func _outbreak_news(game: Variant, t: Dictionary, b: Dictionary, d: int) -> void:
	await _checkpoint("_outbreak_news:enter")
	var seen: Dictionary = b.get("outbreak", {})
	for dis: Variant in seen.keys():
		await _checkpoint("_outbreak_news:loop")
		if int(b["act"].get(dis, 0)) <= 0: seen.erase(dis)
	var mine: Variant = Diplomacy.player_realm(game.world)
	if mine != "" and String(t.get("faction", "")) == mine:
		for dis: Variant in b["act"]:
			await _checkpoint("_outbreak_news:loop")
			if int(b["act"][dis]) >= SicknessGroups.OUTBREAK and not seen.has(dis):
				seen[dis] = d
				CampaignWorld.log_event(game, "Sickness: %s has taken hold in %s (%d sick)." % [Sickness.dname(dis), t["name"], int(b["act"][dis])])
	if seen.is_empty(): b.erase("outbreak")
	else: b["outbreak"] = seen

func gen_businesses(town: Dictionary, e: Dictionary, D: Dictionary, migrate: bool = false) -> void:
	await _checkpoint("gen_businesses:enter")
	Sickness.book(e)["hb"] = true
	if not D["businesses"].has("herbalist"):
		return
	for bz: Variant in e.get("biz", []):
		await _checkpoint("gen_businesses:loop")
		if String(bz["type"]) == "herbalist":
			return
	var hc: Array = Sickness.data()["herbalist_cap"]
	var cap: Variant = int(hc[0]) + int(float(hc[1]) * float(town.get("size", 0)))
	var fams: Array = e["fams"]
	var rng: Variant = RandomNumberGenerator.new()
	_rngs.append(rng)
	rng.seed = hash([String(town.get("id", "")), "herbalist"])
	var owner: Variant = -1
	var n: Variant = fams.size()
	if n > 1:
		var start: Variant = rng.randi() % (n - 1)
		for j: Variant in n - 1:
			await _checkpoint("gen_businesses:loop")
			var f: Dictionary = fams[1 + (start + j) % (n - 1)]
			if not f["gone"] and (f["owns"] as Array).is_empty():
				owner = int(f["id"])
				break
	var bz2: Variant = Businesses._row(e, "herbalist", owner, cap, D)
	if migrate:
		bz2["till"] = 0.0   # an older save: no money from nothing (the owner puts some in at his turn)

func ensure_herbalist(town: Dictionary, e: Dictionary) -> void:
	await _checkpoint("ensure_herbalist:enter")
	await gen_businesses(town, e, TownEcon.data(), true)
	Businesses.rebuild_open(e)
