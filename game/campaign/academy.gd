class_name Academy
extends RefCounted
## The state research house (v0.012; docs/specs/next/02-steel-assay-house.md with its CHANGE; data economy.json
## "research"). One in every faction's capital, every race (Douglas 13:23). It is a real business: a town-owned row
## (type "academy") in the capital's economy with real staff hired by the normal hiring rules and paid out of its
## till, which the state fills each faction turn from the realm's treasury (then the capital's chest above its short
## line). Its name and its lead's title come from the culture row (research_name / research_lead; data
## research.names when a culture has none): the Academy and its Master, the Lorehall's Loremaster, the Athenaeum's
## Sage, the Blood Forge's Forge-Boss, the Pit's Pit-Master ...
##
## The lead is a real register person: b.lead = [family id, pid] (he holds one of the house's places; Persons.work
## shows him under his title). When he dies, retires (an elder), goes into service, loses his place or his family
## leaves the town, the post stands empty and output stops until the state appoints a successor at its next faction
## turn: the best-skilled eligible staff member or an idle grown-up of the town. Training stays on the person.
##
## Research is a LIST of lines (data research.lines): each names the races that may take it and the know-how it raises.
## A line is active for a faction whose race may take it and whose know-how is under 100. Budget and staff split
## across the active lines by weight. A house with no active line keeps only its lead (orcs and goblins never take
## steel; dwarves hold it whole). Know-how belongs to the faction: w.research[fid] = {kh {key: 0-100}, pts {key},
## interest, budget, places, paid, out (this week's research), hist [[day, research a week]], log [lines]}; every
## town of the faction mirrors it in e.fkh (Businesses.kh_of reads it), refreshed each faction turn.

static func R() -> Dictionary:
	return TownEcon.data()["research"]

# ================================================================== names
## [house name, lead title] for a culture (and its race when the culture row has none).
static func names_of(culture: String, race: String) -> Array:
	var C: Dictionary = TownEcon.data()["cultures"].get(culture, {})
	var N: Dictionary = R()["names"]
	var fb: Array = N.get(culture, N["_race"].get(race, N["_default"])) if culture != "_race" else N["_default"]
	return [String(C.get("research_name", fb[0])), String(C.get("research_lead", fb[1]))]

static func house_name(e: Dictionary) -> String:
	return String(names_of(String(e.get("culture", "middle")), Persons.race_of(e))[0])

static func lead_title(e: Dictionary) -> String:
	return String(names_of(String(e.get("culture", "middle")), Persons.race_of(e))[1])

## "the Academy", "the Blood Forge", "The Pit" (a name that already has its article keeps it).
static func the_name(e: Dictionary) -> String:
	var n := house_name(e)
	return n if n.to_lower().begins_with("the ") else "the " + n

static func biz_of(e: Dictionary) -> Dictionary:
	var bi := int(e.get("academy", -1))
	if bi < 0 or bi >= (e.get("biz", []) as Array).size():
		return {}
	var b: Dictionary = e["biz"][bi]
	return b if String(b.get("type", "")) == "academy" else {}

# ================================================================== faction state
static func faction_race(fid: String) -> String:
	return String(DB.factions.get(fid, {}).get("race", "human"))

## The research line that raises this know-how ({} when none).
static func line_of(key: String) -> Dictionary:
	for L in R()["lines"]:
		if String(L["knowhow"]) == key:
			return L
	return {}

## May this race ever take (learn) the line? (v0.014: bronze never orcs or goblins; iron every race.)
static func race_may(key: String, race: String) -> bool:
	var L := line_of(key)
	return not L.is_empty() and (L["races"] as Array).has(race)

## The know-how a faction starts with: factions.json "<key>_knowhow", else the line's start for the faction's race
## (v0.014, data research.lines[].start), else (steel) the dwarf holds 100, else 0.
static func start_kh(fid: String, key: String) -> float:
	var F: Dictionary = DB.factions.get(fid, {})
	var race := faction_race(fid)
	if key == "steel":
		if race in ["orc", "goblin"]: return 0.0
		if race == "dwarf": return 100.0
	if F.has(key + "_knowhow"):
		return clampf(float(F[key + "_knowhow"]), 0.0, 100.0)
	var Ls: Dictionary = line_of(key).get("start", {})
	if Ls.has(race):
		return clampf(float(Ls[race]), 0.0, 100.0)
	if key == "steel" and fid == String(R().get("start_dwarf_faction", "dwarf_holds")):
		return 100.0
	return 0.0

static func state(w: Dictionary, fid: String) -> Dictionary:
	if not w.has("research"):
		w["research"] = {}
	var RS: Dictionary = w["research"]
	if not RS.has(fid):
		RS[fid] = {"kh": {}, "pts": {}, "interest": 0.0, "budget": 0.0, "places": 0, "paid": 0.0, "out": 0.0, "hist": [], "log": []}
	var S: Dictionary = RS[fid]
	# A new data line or a missing points key is independent of dictionary size.
	for L in R()["lines"]:
		var k := String(L["knowhow"])
		if not S["kh"].has(k) or not race_may(k, faction_race(fid)):
			S["kh"][k] = start_kh(fid, k)
		if not S["pts"].has(k):
			S["pts"][k] = 0.0
	return S

## The lines this faction's house works now (its race may take them, its know-how under 100).
static func active_lines(w: Dictionary, fid: String) -> Array:
	var race := faction_race(fid)
	var S := state(w, fid)
	var out := []
	for L in R()["lines"]:
		if (L["races"] as Array).has(race) and float(S["kh"].get(String(L["knowhow"]), 0.0)) < 100.0:
			out.append(L)
	return out

## Every line with whether this faction can take it at all (the screens list them).
static func lines_for(fid: String) -> Array:
	var race := faction_race(fid)
	var out := []
	for L in R()["lines"]:
		out.append([L, (L["races"] as Array).has(race)])
	return out

## A race's learning factor on a line (the line's own race_factor, else the block's; others 1.0).
static func race_factor(fid: String, key: String = "") -> float:
	var race := faction_race(fid)
	var RF: Dictionary = line_of(key).get("race_factor", R()["race_factor"]) if key != "" else R()["race_factor"]
	return float(RF.get(race, 1.0))

## Know-how from accumulated research: 0 below p0, then rising to 100 at p100 (curve power); a line's own p0 / p100 /
## curve when it has them (key), else the block's.
static func kh_from(pts: float, factor: float, key: String = "") -> float:
	var L := line_of(key) if key != "" else {}
	var eff := pts * factor
	var p0 := float(L.get("p0", R()["p0"])); var p100 := float(L.get("p100", R()["p100"]))
	if eff <= p0:
		return 0.0
	return clampf(100.0 * pow((eff - p0) / maxf(1.0, p100 - p0), float(L.get("curve", R()["curve"]))), 0.0, 100.0)

## A faction's know-how after research: never under its start, never for a line its race may not take.
static func kh_after(fid: String, key: String, pts: float) -> float:
	if not race_may(key, faction_race(fid)):
		return start_kh(fid, key)
	return maxf(start_kh(fid, key), kh_from(pts, race_factor(fid, key), key))

## The best quality (0 poor .. 5) a faction's smiths can give steel at this know-how; -1 = none.
static func best_quality(kh: float) -> int:
	if kh <= 0.0:
		return -1
	return clampi(int(floor(kh / (100.0 / 6.0))), 0, 5)

## Every town of the faction mirrors its know-how (e.fkh). v0.014: a line with "teach" (bronze) whose research the
## house has begun keeps the capital's smiths' own practice (e.knowhow) at least min(know-how, teach), so a realm that
## learns a metal late (the elves' bronze) has smiths who can start on it; caravans spread it from there.
static func sync_towns(w: Dictionary, fid: String) -> void:
	var S := state(w, fid)
	var cap_id := String(w["factions"].get(fid, {}).get("capital", ""))
	for tid in w["factions"].get(fid, {}).get("towns", []):
		var t: Dictionary = w["towns"].get(tid, {})
		if TownEcon.has_econ(t) and String(t.get("faction", t["econ"].get("faction", ""))) == fid:
			t["econ"]["fkh"] = (S["kh"] as Dictionary).duplicate()
			if String(tid) == cap_id:
				for L in R()["lines"]:
					var k := String(L["knowhow"])
					if L.has("teach") and float(S["pts"].get(k, 0.0)) > 0.0 and float(S["kh"].get(k, 0.0)) > 0.0:
						var kn: Dictionary = t["econ"]["knowhow"]
						kn[k] = maxf(float(kn.get(k, 0.0)), minf(float(S["kh"][k]), float(L["teach"])))

static func _log(S: Dictionary, day: float, text: String) -> void:
	var lg: Array = S["log"]
	lg.append("Year %d, %s: %s" % [Calendar.year(day), Calendar.season(day), text])
	while lg.size() > 12:
		lg.pop_front()

# ================================================================== world gen and loading
## World gen (EconGen.generate, after the mint): the capital's house, a town row with one place (its lead's).
static func gen_town(town: Dictionary, e: Dictionary) -> void:
	if not town.get("capital", false) or e.has("academy"):
		return
	var D := TownEcon.data()
	var b: Dictionary = Businesses._row(e, "academy", -1, 1, D)
	b["till"] = float(b["wage"]) * 14.0 * (1.0 + float(R()["lead_pay"]))   # pre-history: two weeks of the lead's pay
	b["skill"] = float(R()["new_skill"])
	b["lead"] = []
	e["academy"] = int(b["id"])

## World gen (after the register and before the coin ledger): each faction's state, its towns' mirrors, the leads.
static func init_world(game) -> void:
	var w: Dictionary = game.world
	for fid in w.get("factions", {}):
		state(w, fid)
		sync_towns(w, fid)
		var cap: Dictionary = w["towns"].get(String(w["factions"][fid].get("capital", "")), {})
		if TownEcon.has_econ(cap) and not biz_of(cap["econ"]).is_empty():
			var b := biz_of(cap["econ"])
			_state_owner(cap["econ"], b)
			_release_unregistered(cap["econ"], b)
			if active_lines(w, fid).is_empty():
				_idle_house(cap["econ"], b)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([int(w.get("seed", 0)), fid, "academy"])
			appoint(w, fid, cap["econ"], b, 0.0, rng)

## Older saves: the new goods get today's base prices, each capital its house (an empty till: the next faction turn
## funds it), each faction its state and mirrors.
static func after_load(game) -> void:
	var w: Dictionary = game.world
	var G: Dictionary = TownEcon.data()["goods"]
	for tid in w.get("towns", {}):
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		for g in G:
			if not String(g).begins_with("_") and not (e["price"] as Dictionary).has(g):
				e["price"][g] = float(G[g]["price"]) * Barge.pl(e)
		if t.get("capital", false) and not e.has("academy"):
			gen_town(t, e)
			biz_of(e)["till"] = 0.0
			Businesses.rebuild_open(e)
		if e.has("academy"):
			e["academy"] = int(e["academy"])
			var b := biz_of(e)
			if b.is_empty():
				continue
			_state_owner(e, b)
			_release_unregistered(e, b)
			# Loaded blocked/completed houses obey the same unpaid-post rule as
			# newly generated ones, before another wage day or building bill.
			if active_lines(w, String(t.get("faction", e.get("faction", "")))).is_empty():
				_idle_house(e, b)
			var L: Array = b.get("lead", [])
			b["lead"] = [int(L[0]), int(L[1])] if L.size() >= 2 else []
			if L.size() >= 2 and not b.has("lead_uid") and int(L[0]) >= 0 and int(L[0]) < (e["fams"] as Array).size():
				var p := Persons.by_pid(e["fams"][int(L[0])], int(L[1]))
				b["lead_uid"] = String(Persons.g(p, Persons.PERSON_UID, ""))
	for fid in w.get("factions", {}):
		state(w, fid)
		sync_towns(w, fid)

## Older public-service rows could acquire a private operator. The Academy belongs
## to the state; release only that operator's keeper place, retaining cash/debts.
static func _state_owner(e: Dictionary, b: Dictionary) -> void:
	var owner := int(b.get("owner", -1))
	b["owner"] = -1
	b["public_funding"] = "realm"
	b["kw"] = 0
	b["for_sale"] = false
	if owner < 0 or owner >= (e["fams"] as Array).size():
		return
	var f: Dictionary = e["fams"][owner]
	var bid := int(b["id"])
	f["owns"] = (f["owns"] as Array).filter(func(id): return int(id) != bid)
	var kept := (f.get("keeps", []) as Array).any(func(id): return int(id) == bid)
	f["keeps"] = (f.get("keeps", []) as Array).filter(func(id): return int(id) != bid)
	if kept:
		Families.reassign(e, f)

# ================================================================== the lead
## Is the lead still at his post? "" = yes; else why he is gone (for the log).
static func lead_gone(e: Dictionary, b: Dictionary) -> String:
	var L: Array = b.get("lead", [])
	if L.size() < 2:
		return "none"
	var fams: Array = e["fams"]
	if int(L[0]) < 0 or int(L[0]) >= fams.size():
		return "left the town"
	var f: Dictionary = fams[int(L[0])]
	if f.get("gone", false):
		return "left the town"
	# The register reader may initialize missing legacy arrays; keep a lookup read-only.
	var p := Persons.by_pid(f.duplicate(), int(L[1]))
	if p.is_empty():
		return "died"
	if String(b.get("lead_uid", "")) != "" and String(Persons.g(p, Persons.PERSON_UID, "")) != String(b["lead_uid"]):
		return "left the town"
	if int(p[6]) != 0:
		return "retired, grown old"
	if not String(p[4]) in ["", "hire"]:
		return "left for %s" % Persons.SERVICE_WORDS.get(String(p[4]), String(p[4]))
	# An idle house retains a named, unpaid post, not a fictitious employee.
	if not bool(b.get("research_idle", false)) and int((f["jobs"] as Dictionary).get(str(int(b["id"])), 0)) <= 0:
		return "left the house"
	if not bool(b.get("research_idle", false)):
		var job: Dictionary = Persons.work(e, f.duplicate()).get(int(L[1]), {})
		if int(job.get("biz", -1)) != int(b["id"]) or bool(job.get("keeper", false)):
			return "left the house"
	return ""

static func lead_name(e: Dictionary, b: Dictionary) -> String:
	var L: Array = b.get("lead", [])
	if L.size() < 2 or lead_gone(e, b) != "":
		return ""
	var f: Dictionary = e["fams"][int(L[0])]
	return Persons.name_of(f, Persons.by_pid(f.duplicate(), int(L[1])), Persons.race_of(e))

## The post is empty: the log says why and output stops (Academy.day) until appoint() fills it.
static func vacate(w: Dictionary, fid: String, e: Dictionary, b: Dictionary, why: String, day: float) -> void:
	var L: Array = b.get("lead", [])
	if L.size() < 2:
		return
	var nm := ""
	var f: Dictionary = e["fams"][int(L[0])] if int(L[0]) >= 0 and int(L[0]) < (e["fams"] as Array).size() else {}
	if not f.is_empty():
		nm = String(f.get("name", ""))
	_log(state(w, fid), day, "the %s of %s (of the %s family) %s; the post stands empty." % [lead_title(e), house_name(e), nm, why])
	b["lead"] = []
	b["lead_uid"] = ""
	b["vac"] = day

## Read existing personal training without changing the register (also used by appointments and reports).
static func _skill(p: Array, fallback: float) -> float:
	var training: Variant = Persons.g(p, Persons.RESEARCH, {})
	return clampf(float(training.get("skill", fallback)) if training is Dictionary else fallback, 0.0, 15.0)

static func _training(p: Array, fallback: float) -> Dictionary:
	Persons._identity_pad(p)
	if p.size() <= Persons.RESEARCH or not p[Persons.RESEARCH] is Dictionary:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([Persons.g(p, Persons.PERSON_UID, ""), int(p[0]), float(p[3]), "research aptitude"])
		var initial := {"skill": clampf(fallback, 0.0, 15.0), "aptitude": rng.randf_range(0.9, 1.1)}
		if p.size() <= Persons.RESEARCH: p.append(initial)
		else: p[Persons.RESEARCH] = initial
	var training: Dictionary = p[Persons.RESEARCH]
	training["skill"] = _skill(p, fallback)
	training["aptitude"] = clampf(float(training.get("aptitude", 1.0)), 0.9, 1.1)
	return training

## Actual named employees; a private operator's unpaid keeper place is not research staff.
static func _staff(e: Dictionary, b: Dictionary, working_only: bool = false) -> Array:
	var out := []
	var bid := int(b["id"])
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or int(f["jobs"].get(str(bid), 0)) <= 0:
			continue
		var work := Persons.work(e, f)
		for pid in work:
			if int(work[pid].get("biz", -1)) != bid or bool(work[pid].get("keeper", false)):
				continue
			var p := Persons.by_pid(f, int(pid))
			if p.is_empty() or int(p[6]) != 0 or not String(p[4]) in ["", "hire", "reserve"]:
				continue
			if working_only:
				var sc := Sickness.case_of(f, int(pid))
				var day := float(e.get("day", 0))
				if not sc.is_empty() and int(sc[Sickness.C_BED]) == 1 and day >= float(sc[Sickness.C_ON]) and day < Sickness._stop(sc):
					continue
			out.append([f, p])
	return out

## The normal household matcher bounds Academy offers by registered adults.
static func hiring_places(_e: Dictionary, f: Dictionary, b: Dictionary) -> int:
	if String(b["type"]) != "academy":
		return maxi(0, int(b["cap"]) - int(b["workers"]))
	if bool(b.get("research_idle", false)) or f.get("gone", false) or f.get("estate", false):
		return 0
	var named := 0
	for p in Persons.pp_read(f):
		if int(p[6]) == 0 and String(p[4]) in ["", "hire", "reserve"]:
			named += 1
	# Named households can change from worse-paid jobs through the ordinary
	# matcher. A cohort's unnamed jobs cannot be turned into named scientists.
	var held := int(f["jobs"].get(str(int(b["id"])), 0))
	var assigned := int(f.get("hands", 0)) + (f.get("keeps", []) as Array).size() + held
	if Population.is_cohort(f):
		assigned += Families.job_total(f) - held
	return maxi(0, named - assigned)

## Existing anonymous places cannot impersonate registered scientists. Retain
## earned claims through the ordinary job setter; do not invent register people.
static func _release_unregistered(e: Dictionary, b: Dictionary) -> void:
	var named := {}
	for pair in _staff(e, b):
		var family := int(pair[0]["id"])
		named[family] = int(named.get(family, 0)) + 1
	for f in e["fams"]:
		var held := int(f["jobs"].get(str(int(b["id"])), 0))
		if held > int(named.get(int(f["id"]), 0)):
			Families.set_job(e, f, int(b["id"]), int(named.get(int(f["id"]), 0)))
			var casual := 0
			for count in f.get("cj", {}).values(): casual += int(count)
			var old_idle := int(f.get("idle", 0))
			f["idle"] = maxi(0, Families.adults(f) - Families.serving(f) - int(f.get("hands", 0)) - (f.get("keeps", []) as Array).size() - Families.job_total(f) - casual)
			e["idle_n"] = maxi(0, int(e.get("idle_n", 0)) + int(f["idle"]) - old_idle)

static func _better(p: Array, skill: float, best: Array, best_skill: float) -> bool:
	return best.is_empty() or skill > best_skill or (skill == best_skill and (float(p[3]) < float(best[1][3]) or (float(p[3]) == float(best[1][3]) and int(p[0]) < int(best[1][0]))))

## Best-skilled staff first, else the best-trained idle adult. An idle house's honorary head takes no paid job.
static func appoint(w: Dictionary, fid: String, e: Dictionary, b: Dictionary, day: float, rng: RandomNumberGenerator) -> bool:
	var bid := int(b["id"])
	var best: Array = []   # [family, person]
	var best_skill := -1.0
	var idle := bool(b.get("research_idle", false))
	for pair in _staff(e, b):
		var p: Array = pair[1]
		if not String(p[4]) in ["", "hire"]:
			continue
		var skill := _skill(p, float(R()["new_skill"]) if bool(b.get("personal_training", false)) else float(b.get("skill", R()["new_skill"])))
		if _better(p, skill, best, best_skill):
			best = pair
			best_skill = skill
	var from_staff := not best.is_empty()
	if best.is_empty():
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false):
				continue
			var wk2 := Persons.work(e, f)
			for pid in wk2:
				var p := Persons.by_pid(f, int(pid))
				if p.is_empty() or int(p[6]) != 0 or not String(p[4]) in ["", "hire"]:
					continue
				if not idle and String(wk2[pid].get("kind", "")) != "none":
					continue
				var skill := _skill(p, float(R()["new_skill"]))
				if _better(p, skill, best, best_skill):
					best = [f, p]
					best_skill = skill
		if best.is_empty():
			return false
		var f2: Dictionary = best[0]
		if not idle:
			if int(b["workers"]) >= int(b["cap"]):
				return false
			Families.set_job(e, f2, bid, int((f2["jobs"] as Dictionary).get(str(bid), 0)) + 1)
		var nl: Array = R()["new_lead"]
		b["lskill"] = _skill(best[1], rng.randf_range(float(nl[0]), float(nl[1])))
	else:
		b["lskill"] = best_skill
	var ff: Dictionary = best[0]
	var pp: Array = best[1]
	b["lead"] = [int(ff["id"]), int(pp[0])]
	b["lead_uid"] = String(Persons.g(pp, Persons.PERSON_UID, ""))
	b.erase("vac")
	var nm := Persons.name_of(ff, pp, Persons.race_of(e))
	_log(state(w, fid), day, "%s is named %s of %s (skill %d of 15%s)." % [nm, lead_title(e), house_name(e), int(b["lskill"]),
		", from its staff" if from_staff else ", from the town"])
	Families.add_hist(ff, "%s was named %s of %s." % [nm, lead_title(e), house_name(e)], day)
	return true

## Persons.work: the lead holds one of the house's places of his family, under his title.
static func mark_lead(e: Dictionary, f: Dictionary, out: Dictionary) -> void:
	var b := biz_of(e)
	if bool(b.get("research_idle", false)):
		return
	var L: Array = b.get("lead", [])
	if L.size() < 2 or int(L[0]) != int(f["id"]) or not out.has(int(L[1])):
		return
	var bid := int(b["id"])
	var lp := int(L[1])
	var person := Persons.by_pid(f, lp)
	if person.is_empty() or not String(person[4]) in ["", "hire"]:
		return
	if String(b.get("lead_uid", "")) != "" and String(Persons.g(person, Persons.PERSON_UID, "")) != String(b["lead_uid"]):
		return
	if bool(out[lp].get("keeper", false)):
		return   # the state cannot turn an unpaid private operator into a paid researcher
	if int(out[lp].get("biz", -1)) != bid:
		for q in out:
			if int(out[q].get("biz", -1)) == bid:
				var tmp: Dictionary = out[q]
				out[q] = out[lp]
				out[lp] = tmp
				break
	if int(out[lp].get("biz", -1)) == bid:
		var pl: Dictionary = (out[lp] as Dictionary).duplicate()
		pl["title"] = lead_title(e)
		out[lp] = pl

## A staff place's title: chemists once the staff have learned the trade, apprentices before.
static func staff_title(b: Dictionary) -> String:
	return "chemist" if float(b.get("skill", 0.0)) >= 3.0 else "apprentice"

## Completed/blocked houses keep the named post and saved cash, with no employees or purchases.
## Earned wages still settle through set_job; no claim is erased by a research pause.
static func _idle_house(e: Dictionary, b: Dictionary) -> void:
	b["research_idle"] = true
	b["cap"] = 0
	var affected := {}
	_lay_off(e, b, int(b["workers"]), affected)
	Businesses.rebuild_open(e)
	for family in affected:
		Families.reassign(e, e["fams"][int(family)])
	b["state"] = "idle"
	b["why"] = "no line it can take"

# ================================================================== the working day
## v0.087 supplies charcoal. Keep the older research data row usable after that
## predecessor is merged without adding another fuel good or charcoal recipe.
static func materials() -> Dictionary:
	var mats: Dictionary = (R()["mats"] as Dictionary).duplicate()
	if mats.has("wood"):
		mats["charcoal"] = float(mats.get("charcoal", 0.0)) + float(mats["wood"])
		mats.erase("wood")
	return mats

## Trial fractions are prepaid: an integer purchase is recorded as used once,
## with its unused trial capacity retained in the business. Legacy mc/mgot are
## unpaid demand/smoothing and never become material credit.
static func _trials(e: Dictionary, b: Dictionary, work: float, reserve: float, mkt: Dictionary, demand: Dictionary) -> Array:
	var mats := materials()
	var credit: Dictionary = b.get("trial_credit", {})
	var stock: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var fraction := 1.0
	for good in mats:
		var need := float(mats[good]) * work
		demand[good] = float(demand.get(good, 0.0)) + need
		if need <= 0.0: continue
		if float(price.get(good, 0.0)) <= 0.0:
			fraction = 0.0
		else:
			fraction = minf(fraction, (maxf(0.0, float(credit.get(good, 0.0))) + maxi(0, int(stock.get(good, 0)))) / need)
	var cost := 0.0
	var buys := {}
	for good in mats:
		var need := float(mats[good]) * work * fraction
		var whole := maxi(0, int(ceil(need - float(credit.get(good, 0.0)) - 0.000000001)))
		buys[good] = whole
		cost += float(whole) * float(price.get(good, 0.0))
	if fraction <= 0.0:
		return [0.0, 0.0, "inputs"]
	if cost > maxf(0.0, float(b["till"]) - reserve):
		return [0.0, 0.0, "wages"]
	var used := {}
	for good in mats:
		var whole := int(buys[good])
		if whole > 0:
			stock[good] = int(stock[good]) - whole
			TownEcon.led(e, "used", String(good), whole)
			used[good] = whole
		credit[good] = maxf(0.0, float(credit.get(good, 0.0)) + whole - float(mats[good]) * work * fraction)
	b["trial_credit"] = credit
	b["research_materials"] = used
	b["till"] = float(b["till"]) - cost
	mkt["till"] = float(mkt["till"]) + cost
	e["stats"]["sales"] = float(e["stats"]["sales"]) + cost
	return [fraction, cost, ""]

## Businesses.daily, the house's day (w = staff at work, the lead among them). Returns coin spent on materials.
static func day(game, town: Dictionary, e: Dictionary, b: Dictionary, w: float, mkt: Dictionary, bdem: Dictionary) -> float:
	var world: Dictionary = game.world
	var fid := String(town.get("faction", e.get("faction", "")))
	var d := float(e.get("day", 0))
	var RR := R()
	if int(b.get("research_day", -1)) >= int(d):
		return 0.0
	b["research_out_day"] = 0.0
	b["research_materials"] = {}
	if String(world.get("factions", {}).get(fid, {}).get("capital", "")) != String(town.get("id", "")):
		_idle_house(e, b)
		b["why"] = "not the faction capital"
		return 0.0
	var act := active_lines(world, fid)
	if act.is_empty():
		if not bool(b.get("research_idle", false)) or int(b["workers"]) > 0:
			_idle_house(e, b)
		b["state"] = "idle"
		b["why"] = "no line it can take"
		return 0.0
	b["research_idle"] = false
	var why := lead_gone(e, b)
	if why != "":
		if why != "none":
			vacate(world, fid, e, b, why, d)
		b["state"] = "hands"
		b["why"] = "no %s" % lead_title(e)
		return 0.0
	if b.get("closed", false) or w <= 0.0:
		b["state"] = "hands"
		b["why"] = "no working staff"
		return 0.0
	# Resolve real working people, including the head's own sickness rather than a count-only substitute.
	var L: Array = b["lead"]
	var lf: Dictionary = e["fams"][int(L[0])]
	var crew := _staff(e, b, true)
	var head: Array = []
	for pair in crew:
		if int(pair[0]["id"]) == int(L[0]) and int(pair[1][0]) == int(L[1]):
			head = pair[1]
	if head.is_empty():
		b["state"] = "hands"
		b["why"] = "%s not at work" % lead_title(e)
		return 0.0
	w = minf(w, float(crew.size()))
	# Reserve earned claims and the next day of basic wages before paying the head or buying trials.
	var wage_reserve := maxf(0.0, float(b.get("owed", 0.0))) + float(b["wage"]) * float(b["workers"])
	var lp := float(RR["lead_pay"]) * float(b["wage"])
	if float(b["till"]) < wage_reserve + lp:
		b["state"] = "wages"
		b["why"] = "research wages unfunded"
		return 0.0
	# One queued town day must not pay, burn materials or teach twice.
	b["research_day"] = int(d)
	b["till"] = float(b["till"]) - lp
	lf["purse"] = float(lf["purse"]) + lp
	lf["wage_receipts"] = float(lf.get("wage_receipts", 0.0)) + lp
	b["t_paid"] = float(b.get("t_paid", 0.0)) + lp
	var trial := _trials(e, b, w, wage_reserve, mkt, bdem)
	var matf := float(trial[0])
	var spent := float(trial[1])
	if matf <= 0.0:
		b["state"] = String(trial[2])
		b["why"] = "trial materials" if b["state"] == "inputs" else "money for trial materials"
		return spent
	var lead_training := _training(head, float(b.get("lskill", 1.0)))
	var lsk := float(lead_training["skill"])
	var aptitude := clampf(float(lead_training.get("aptitude", 1.0)), 0.9, 1.1)
	var sum_skill := 0.0
	var staff := []
	for pair in crew:
		var p: Array = pair[1]
		if int(pair[0]["id"]) == int(L[0]) and int(p[0]) == int(L[1]):
			continue
		var training := _training(p, float(RR["new_skill"]) if bool(b.get("personal_training", false)) else float(b.get("skill", RR["new_skill"])))
		staff.append(training)
		sum_skill += float(training["skill"])
	var ssk := sum_skill / staff.size() if not staff.is_empty() else float(RR["new_skill"])
	var sn := maxf(0.0, w - 1.0)
	var pts := (lsk * float(RR["lead_k"]) * aptitude + ssk * sn * float(RR["staff_k"])) * matf
	var S := state(world, fid)
	var wsum := 0.0
	for Ln in act:
		wsum += float(Ln.get("weight", 1.0))
	for Ln in act:
		var k := String(Ln["knowhow"])
		S["pts"][k] = float(S["pts"].get(k, 0.0)) + pts * float(Ln.get("weight", 1.0)) / maxf(0.001, wsum)
		S["kh"][k] = kh_after(fid, k, float(S["pts"][k]))
	S["out"] = float(S.get("out", 0.0)) + pts
	if not e.has("fkh"):
		e["fkh"] = {}
	sync_towns(world, fid)
	# learning by working; the lead's skill sets how well the staff learn
	var lrn := float(RR["learn"]) * (0.5 + lsk / 10.0) * aptitude * matf
	var staff_share := minf(1.0, sn / staff.size()) if not staff.is_empty() else 0.0
	for training in staff:
		training["skill"] = minf(15.0, float(training["skill"]) + lrn * staff_share)
	lead_training["skill"] = minf(15.0, lsk + float(RR["learn_lead"]) * matf)
	b["personal_training"] = true
	b["skill"] = minf(15.0, ssk + lrn * staff_share)
	b["lskill"] = float(lead_training["skill"])
	b["research_out_day"] = pts
	b["state"] = "busy"
	b["why"] = "" if matf >= 0.999 else "materials"
	if active_lines(world, fid).is_empty():
		_idle_house(e, b)
	return spent

# ================================================================== the faction turn (weekly)
## TownEcon.faction_turn: the state's interest and budget, the coin to the house's till, places and lay-offs, a
## successor for an empty post, the week's study piece, the towns' know-how mirrors.
static func faction_turn(game, day: float) -> void:
	var w: Dictionary = game.world
	var RR := R()
	var I: Dictionary = RR["interest"]
	for fid in w.get("factions", {}):
		var fac: Dictionary = w["factions"][fid]
		var S := state(w, fid)
		if float(S.get("turn_day", -1.0)) >= day:
			continue
		var cap: Dictionary = w["towns"].get(String(fac.get("capital", "")), {})
		if not TownEcon.has_econ(cap) or biz_of(cap["econ"]).is_empty() or String(cap.get("faction", "")) != String(fid):
			sync_towns(w, fid)
			continue
		var e: Dictionary = cap["econ"]
		var b := biz_of(e)
		S["turn_day"] = day
		var wage := float(b["wage"])
		var act := active_lines(w, fid)
		b["research_idle"] = act.is_empty()
		# interest from real conditions: the treasury against the army's keep, war, steel met, the ruler's temper
		var keep := maxf(1.0, Army.bill(game, fid) * float(I["keep_days"]))
		var tre := float(fac.get("treasury", 0.0))
		var it := float(I["base"]) + float(I["treasury"]) * clampf(tre / keep - 1.0, -1.0, 1.0)
		for pr in w.get("wars", []):
			if String(pr[0]) == fid or String(pr[1]) == fid:
				it += float(I["war"])
				break
		var met := _steel_met(w, fid)
		S["met"] = met
		it += float(I["met"]) * minf(1.0, float(met) / maxf(1.0, float(I["met_items"])))
		it += float(I["temper"].get(Barge.temper(e), 0.0))
		it = clampf(it, 0.0, 1.0)
		S["interest"] = snappedf(it, 0.01)
		# No active line: the post and unspent cash wait, without payroll or fresh transfers.
		var budget := 0.0
		var places := 0
		if not act.is_empty():
			var per := wage * (1.0 + float(RR["mat_share"]))
			budget = it * float(RR["places_full"]) * per + wage * float(RR["lead_pay"])
			places = clampi(int(floor(it * float(RR["places_full"]))), 0, int(RR["places_max"]))
			if places <= 0:
				budget = 0.0
		S["budget"] = snappedf(budget, 0.1)
		S["places"] = places
		# the coin: two weeks of the budget in the till, from the realm's treasury, then the capital's chest
		var want := budget * 14.0 - float(b["till"])
		var paid := 0.0
		if want > 0.0:
			var a := minf(want, maxf(0.0, tre) * float(RR["treasury_share"]))
			fac["treasury"] = tre - a
			paid += a
			if paid < want:
				var spare := maxf(0.0, float(e["treasury"]) - float(Barge.treasury_lines(e)["short"]))
				var a2 := minf(want - paid, spare * float(RR["treasury_share"]))
				e["treasury"] = float(e["treasury"]) - a2
				paid += a2
			b["till"] = float(b["till"]) + paid
		S["paid"] = paid   # the receipt is the exact debit, formatting belongs to the view
		if paid < want * 0.5 and budget > 0.0 and int(S.get("short_wk", 0)) == 0:
			_log(S, day, "the treasury could not fund %s's budget in full." % house_name(e))
		S["short_wk"] = 1 if paid < want * 0.5 and budget > 0.0 else 0
		# Planned interest cannot hire people on an empty treasury. Existing till money can still fund work.
		var available := maxf(0.0, float(b["till"]) - float(b.get("owed", 0.0)))
		var weekly_wage := maxf(0.01, wage * 7.0)
		var affordable := maxi(0, int(floor((available / weekly_wage - float(RR["lead_pay"])) / (1.0 + float(RR["mat_share"])))))
		places = mini(places, affordable)
		S["places"] = places
		# places: a cut lays off the staff at once (the lead keeps his place while there is one)
		var affected := {}
		var old_cap := int(b["cap"])
		b["cap"] = places
		if int(b["workers"]) > places:
			var laid := _lay_off(e, b, int(b["workers"]) - places, affected)
			if laid > 0:
				_log(S, day, "a smaller budget: %d of %s's staff laid off." % [laid, house_name(e)])
		elif places > old_cap:
			Businesses.rebuild_open(e)
		# an empty post: the state names a successor
		var why := lead_gone(e, b)
		if why != "" and why != "none":
			vacate(w, fid, e, b, why, day)
		if (b.get("lead", []) as Array).size() < 2 and places >= 1:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([int(w.get("seed", 0)), fid, "lead", int(day)])
			if not appoint(w, fid, e, b, day, rng) and not b.has("vac"):
				b["vac"] = day
		# Finish every place and lead transition before households choose again.
		# set_job settles earned claims, but their idle places need the ordinary
		# matcher even when there is no funded alternative. An idle appointee has
		# likewise gained a job since his household's last turn.
		var lead: Array = b.get("lead", [])
		if lead.size() >= 2 and Families.assignments_stale(e["fams"][int(lead[0])]):
			affected[int(lead[0])] = true
		for family in affected:
			Families.reassign(e, e["fams"][int(family)])
		Families.match_idle(e)
		# Normal matching can move a lead's last place to better paid work.
		# His departure must stop this turn's study as well as the next day.
		why = lead_gone(e, b)
		if why != "" and why != "none":
			vacate(w, fid, e, b, why, day)
		if act.is_empty():
			if (b.get("lead", []) as Array).is_empty():
				var idle_rng := RandomNumberGenerator.new()
				idle_rng.seed = hash([int(w.get("seed", 0)), fid, "idle head", int(day)])
				appoint(w, fid, e, b, day, idle_rng)
			b["state"] = "idle"
			b["why"] = "no line it can take"
		# study: one steel piece a week from the town's stalls, bought and used up
		for Ln in act:
			if String(Ln["knowhow"]) == "steel":
				_study(cap, e, b, S, fid, day)
		# the week's research
		var hist: Array = S["hist"]
		hist.append([int(day), snappedf(float(S.get("out", 0.0)), 0.1)])
		while hist.size() > 26:
			hist.pop_front()
		S["out"] = 0.0
		sync_towns(w, fid)

static func _lay_off(e: Dictionary, b: Dictionary, n: int, affected: Dictionary = {}) -> int:
	var bid := int(b["id"])
	var L: Array = b.get("lead", [])
	var laid := 0
	for f in e["fams"]:
		if laid >= n:
			break
		var k := int((f["jobs"] as Dictionary).get(str(bid), 0))
		if k <= 0:
			continue
		var keep := 1 if L.size() >= 2 and int(L[0]) == int(f["id"]) else 0
		var cut := mini(k - keep, n - laid)
		if cut > 0:
			Families.set_job(e, f, bid, k - cut)
			affected[int(f["id"])] = true
			laid += cut
	if laid < n and L.size() >= 2 and int(L[0]) >= 0 and int(L[0]) < (e["fams"] as Array).size():
		var lf: Dictionary = e["fams"][int(L[0])]
		var held := int(lf["jobs"].get(str(bid), 0))
		if held > 0:
			Families.set_job(e, lf, bid, 0)
			affected[int(lf["id"])] = true
			laid += held
	return laid

## Steel pieces in the faction's towns' stalls and armories (met in trade, in loot, from its own smiths).
static func _steel_met(w: Dictionary, fid: String) -> int:
	var n := 0
	for tid in w["factions"].get(fid, {}).get("towns", []):
		var t: Dictionary = w["towns"].get(tid, {})
		if String(t.get("faction", "")) != fid:
			continue
		for key in ["shop", "armory_items"]:
			for it in t.get(key, []):
				if it is Item and it.material == "steel":
					n += 1
	return n

static func _study(town: Dictionary, e: Dictionary, b: Dictionary, S: Dictionary, fid: String, day: float) -> void:
	if b.get("closed", false) or bool(b.get("research_idle", false)) or lead_gone(e, b) != "":
		return
	var lead: Array = b["lead"]
	if not _staff(e, b, true).any(func(pair): return int(pair[0]["id"]) == int(lead[0]) and int(pair[1][0]) == int(lead[1])):
		return
	var shop: Array = town.get("shop", [])
	var pick := -1
	for i in shop.size():
		if shop[i] is Item and shop[i].material == "steel" and not shop[i].is_legend():   # v0.014: never broken up
			pick = i
			break
	if pick < 0:
		return
	var it: Item = shop[pick]
	var cost := Economy.base_value(town, it)
	var reserve := maxf(0.0, float(b.get("owed", 0.0))) + float(b["wage"]) * (float(b["workers"]) + float(R()["lead_pay"])) * 7.0
	if float(b["till"]) < maxf(cost * 2.0, reserve + cost):
		return
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	b["till"] = float(b["till"]) - cost
	mkt["till"] = float(mkt["till"]) + cost
	shop.remove_at(pick)
	TownEcon.led(e, "used", "arms", 1)
	WorldAudit.lose_item(it, "-broken up for study at an academy")   # v0.075 r6: the piece is gone (study points)
	var add := float(R()["study_pts"]) * float(it.quality + 1)
	S["pts"]["steel"] = float(S["pts"].get("steel", 0.0)) + add
	S["kh"]["steel"] = kh_after(fid, "steel", float(S["pts"]["steel"]))
	S["out"] = float(S.get("out", 0.0)) + add
	_log(S, day, "%s bought %s and broke it up for study." % [house_name(e), it.display_name()])

# ================================================================== reads (ui/rec_data.gd)
## The faction's research for the screens.
static func report(w: Dictionary, fid: String) -> Dictionary:
	# Presentation must not create research records or repair a live saved world.
	# Reuse the normal defaults/line rules on this faction's small isolated snapshot.
	var snapshot := {"research": {}}
	var saved: Dictionary = w.get("research", {})
	if saved.has(fid):
		snapshot["research"][fid] = (saved[fid] as Dictionary).duplicate(true)
	var S := state(snapshot, fid)
	var fac: Dictionary = w.get("factions", {}).get(fid, {})
	var cap: Dictionary = w.get("towns", {}).get(String(fac.get("capital", "")), {})
	var out := {"kh": S["kh"], "interest": float(S.get("interest", 0.0)), "budget": float(S.get("budget", 0.0)), "paid": float(S.get("paid", 0.0)),
		"hist": S["hist"], "log": S["log"], "met": int(S.get("met", 0)), "has": false, "lines": [],
		"current_week_output": float(S.get("out", 0.0)), "last_week_output": 0.0, "funding_day": -1.0}
	if not (S["hist"] as Array).is_empty():
		var last: Array = S["hist"].back()
		out["funding_day"] = float(last[0])
		out["last_week_output"] = float(last[1])
	var e: Dictionary = cap.get("econ", {})
	# A former capital held by another realm must not expose that realm's house.
	var owned := String(cap.get("faction", e.get("faction", ""))) == fid
	var b := biz_of(e) if not e.is_empty() and owned else {}
	var act := active_lines(snapshot, fid)
	out["idle"] = act.is_empty()
	var wsum := 0.0
	for Ln in act:
		wsum += float(Ln.get("weight", 1.0))
	if not b.is_empty():
		out["has"] = true
		out["name"] = house_name(e)
		out["title"] = lead_title(e)
		out["town"] = String(cap.get("name", ""))
		out["tid"] = String(cap.get("id", ""))
		out["bid"] = int(b["id"])
		out["lead"] = lead_name(e, b)
		out["lskill"] = float(b.get("lskill", 0.0))
		out["skill"] = float(b.get("skill", 0.0))
		out["staff"] = maxi(0, int(b["workers"]) - (1 if out["lead"] != "" else 0))
		out["cap"] = int(b["cap"])
		out["till"] = float(b["till"])
		out["workers"] = int(b["workers"])
		out["closed"] = bool(b.get("closed", false))
		out["state_code"] = String(b.get("state", "idle"))
		out["why"] = String(b.get("why", ""))
		out["wage"] = float(b["wage"])
		out["lead_wage"] = float(b["wage"]) * (1.0 + float(R()["lead_pay"]))
		out["state"] = Businesses.state_word(b) + ((", " + String(b["why"])) if String(b.get("why", "")) != "" else "")
		# Resolve a detached register for read-only roster queries (Persons.work can
		# initialize old optional arrays). Skills and identities come from people.
		out["roster"] = []
		var view := e.duplicate(true)
		for employee in _staff(view, biz_of(view)):
			var f: Dictionary = employee[0]
			var p: Array = employee[1]
			var lead: Array = b.get("lead", [])
			var is_lead: bool = out["lead"] != "" and lead.size() >= 2 and int(f["id"]) == int(lead[0]) and int(p[0]) == int(lead[1])
			var skill := _skill(p, float(b.get("lskill", 0.0)) if is_lead else float(R()["new_skill"]) if bool(b.get("personal_training", false)) else float(b.get("skill", 0.0)))
			out["roster"].append({"family": int(f["id"]), "pid": int(p[0]), "uid": String(Persons.g(p, Persons.PERSON_UID, "")),
				"name": Persons.name_of(f, p, Persons.race_of(e)), "skill": skill,
				"title": lead_title(e) if is_lead else ("chemist" if skill >= 3.0 else "apprentice"),
				"wage": float(b["wage"]) * (1.0 + float(R()["lead_pay"]) if is_lead else 1.0)})
		out["registered_workers"] = (out["roster"] as Array).size()
		out["materials"] = materials()
		out["trial_credit"] = (b.get("trial_credit", {}) as Dictionary).duplicate()
		out["materials_bought"] = (b.get("research_materials", {}) as Dictionary).duplicate()
		out["day_output"] = float(b.get("research_out_day", 0.0))
		out["owed"] = float(b.get("owed", 0.0))
	for pair in lines_for(fid):
		var Ln: Dictionary = pair[0]
		var k := String(Ln["knowhow"])
		var on := act.has(Ln)
		var share := float(Ln.get("weight", 1.0)) / maxf(0.001, wsum) if on else 0.0
		out["lines"].append({"name": String(Ln["name"]), "key": k, "caps": bool(Ln.get("caps_quality", false)),
			"factor": race_factor(fid, k), "open": bool(pair[1]), "active": on, "pts": float(S["pts"].get(k, 0.0)),
			"kh": float(S["kh"].get(k, 0.0)), "share": share, "staff_on": share * float(out.get("staff", 0)),
			"budget_on": share * float(out["budget"]), "best_q": best_quality(float(S["kh"].get(k, 0.0)))})
	return out
