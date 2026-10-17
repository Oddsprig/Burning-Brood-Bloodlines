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
## turn: the eldest of the staff (he keeps the staff's skill) or an idle grown-up of the town (a new lead's skill).
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
	return e["biz"][bi]

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
	if F.has(key + "_knowhow"):
		return clampf(float(F[key + "_knowhow"]), 0.0, 100.0)
	var Ls: Dictionary = line_of(key).get("start", {})
	var race := faction_race(fid)
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
	if (S["kh"] as Dictionary).size() < (R()["lines"] as Array).size():   # a line added later is just a data row
		for L in R()["lines"]:
			var k := String(L["knowhow"])
			if not S["kh"].has(k):
				S["kh"][k] = start_kh(fid, k)
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
		if TownEcon.has_econ(t):
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
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([int(w.get("seed", 0)), fid, "academy"])
			appoint(w, fid, cap["econ"], biz_of(cap["econ"]), 0.0, rng)

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
			var L: Array = b.get("lead", [])
			b["lead"] = [int(L[0]), int(L[1])] if L.size() >= 2 else []
	for fid in w.get("factions", {}):
		state(w, fid)
		sync_towns(w, fid)

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
	if int(p[6]) == 1:
		return "retired, grown old"
	if not String(p[4]) in ["", "hire"]:
		return "left for %s" % Persons.SERVICE_WORDS.get(String(p[4]), String(p[4]))
	if int((f["jobs"] as Dictionary).get(str(int(b["id"])), 0)) <= 0:
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
	b["vac"] = day

## The state names a lead: the eldest of the staff (he keeps the staff's skill), else an out-of-work grown-up of the
## town (a new lead's skill), who takes one of the house's places. False when nobody can be found.
static func appoint(w: Dictionary, fid: String, e: Dictionary, b: Dictionary, day: float, rng: RandomNumberGenerator) -> bool:
	var bid := int(b["id"])
	var best: Array = []   # [family, person]
	for f in e["fams"]:
		if f.get("gone", false) or int((f["jobs"] as Dictionary).get(str(bid), 0)) <= 0:
			continue
		var wk := Persons.work(e, f)
		for pid in wk:
			if int(wk[pid].get("biz", -1)) != bid:
				continue
			var p := Persons.by_pid(f, int(pid))
			if not p.is_empty() and (best.is_empty() or float(p[3]) < float(best[1][3])):
				best = [f, p]
	var from_staff := not best.is_empty()
	if best.is_empty():
		var fams: Array = e["fams"]
		var n := fams.size()
		var start := rng.randi_range(0, maxi(0, n - 1))
		for i in n:
			var f: Dictionary = fams[(start + i) % n]
			if f.get("gone", false) or f.get("estate", false):
				continue
			var wk2 := Persons.work(e, f)
			for pid in wk2:
				if String(wk2[pid].get("kind", "")) == "none":
					best = [f, Persons.by_pid(f, int(pid))]
					break
			if not best.is_empty() and not (best[1] as Array).is_empty():
				break
			best = []
		if best.is_empty():
			return false
		var f2: Dictionary = best[0]
		if int(b["workers"]) >= int(b["cap"]):
			b["cap"] = int(b["workers"]) + 1
		Families.set_job(e, f2, bid, int((f2["jobs"] as Dictionary).get(str(bid), 0)) + 1)
		var nl: Array = R()["new_lead"]
		b["lskill"] = rng.randf_range(float(nl[0]), float(nl[1]))
	else:
		b["lskill"] = maxf(float(b.get("skill", 1.0)), float(R()["new_skill"]))
	var ff: Dictionary = best[0]
	var pp: Array = best[1]
	b["lead"] = [int(ff["id"]), int(pp[0])]
	b.erase("vac")
	var nm := Persons.name_of(ff, pp, Persons.race_of(e))
	_log(state(w, fid), day, "%s is named %s of %s (skill %d of 15%s)." % [nm, lead_title(e), house_name(e), int(b["lskill"]),
		", from its staff" if from_staff else ", from the town"])
	Families.add_hist(ff, "%s was named %s of %s." % [nm, lead_title(e), house_name(e)], day)
	return true

## Persons.work: the lead holds one of the house's places of his family, under his title.
static func mark_lead(e: Dictionary, f: Dictionary, out: Dictionary) -> void:
	var b := biz_of(e)
	var L: Array = b.get("lead", [])
	if L.size() < 2 or int(L[0]) != int(f["id"]) or not out.has(int(L[1])):
		return
	var bid := int(b["id"])
	var lp := int(L[1])
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

# ================================================================== the working day
## Businesses.daily, the house's day (w = staff at work, the lead among them). Returns coin spent on materials.
static func day(game, town: Dictionary, e: Dictionary, b: Dictionary, w: float, mkt: Dictionary, bdem: Dictionary) -> float:
	var world: Dictionary = game.world
	var fid := String(e.get("faction", town.get("faction", "")))
	var d := float(e.get("day", 0))
	var RR := R()
	# staff joining: a new hand starts at new_skill (those who leave take their skill with them; the rest keep theirs)
	var staff_n := maxi(0, int(b["workers"]) - (1 if (b.get("lead", []) as Array).size() >= 2 else 0))
	var prev := int(b.get("wp", staff_n))
	if staff_n > prev:
		b["skill"] = (float(b.get("skill", 1.0)) * prev + float(RR["new_skill"]) * (staff_n - prev)) / float(staff_n)
	b["wp"] = staff_n
	var why := lead_gone(e, b)
	if why != "":
		if why != "none":
			vacate(world, fid, e, b, why, d)
		b["state"] = "hands"
		b["why"] = "no %s" % lead_title(e)
		return 0.0
	# the lead's own pay on top of his place (from the house's till)
	var L: Array = b["lead"]
	var lf: Dictionary = e["fams"][int(L[0])]
	var lp := float(RR["lead_pay"]) * float(b["wage"])
	if float(b["till"]) >= lp:
		b["till"] = float(b["till"]) - lp
		lf["purse"] = float(lf["purse"]) + lp
		b["t_paid"] = float(b.get("t_paid", 0.0)) + lp
	var act := active_lines(world, fid)
	if act.is_empty():
		b["state"] = "idle"
		b["why"] = "no line it can take"
		return 0.0
	# materials for the trials: bought at market prices; shortages slow the work
	var st: Dictionary = e["stock"]
	var price: Dictionary = e["price"]
	var M: Dictionary = RR["mats"]
	if not b.has("mc"):
		b["mc"] = {}
	var mc: Dictionary = b["mc"]
	var got := 1.0
	var spent := 0.0
	for g in M:
		var q := float(M[g]) * w
		bdem[g] = float(bdem.get(g, 0.0)) + q
		var acc := float(mc.get(g, 0.0)) + q
		var whole := int(floor(acc))
		mc[g] = acc - whole
		if whole <= 0:
			continue
		var pr := float(price.get(g, 1.0))
		var have := mini(whole, int(st.get(g, 0)))
		have = mini(have, int(maxf(0.0, float(b["till"])) / maxf(0.01, pr)))
		if have > 0:
			st[g] = int(st[g]) - have
			TownEcon.led(e, "used", g, have)
			var c := float(have) * pr
			b["till"] = float(b["till"]) - c
			mkt["till"] = float(mkt["till"]) + c
			e["stats"]["sales"] = float(e["stats"]["sales"]) + c
			spent += c
		got = minf(got, float(have) / float(whole))
	if not b.has("mgot"):
		b["mgot"] = 1.0
	b["mgot"] = float(b["mgot"]) * 0.9 + got * 0.1   # the materials share, smoothed (the part-days carry)
	var matf := float(RR["mats_floor"]) + (1.0 - float(RR["mats_floor"])) * float(b["mgot"])
	var lsk := float(b.get("lskill", 1.0))
	var ssk := float(b.get("skill", 1.0))
	var sn := maxf(0.0, w - 1.0)
	var pts := (lsk * float(RR["lead_k"]) + ssk * sn * float(RR["staff_k"])) * matf
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
	for k in S["kh"]:
		e["fkh"][k] = float(S["kh"][k])
	# learning by working; the lead's skill sets how well the staff learn
	var lrn := float(RR["learn"]) * (0.5 + lsk / 10.0)
	b["skill"] = minf(15.0, ssk + lrn)
	b["lskill"] = minf(15.0, lsk + float(RR["learn_lead"]))
	b["state"] = "busy"
	b["why"] = "" if got >= 0.999 else "materials"
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
		var cap: Dictionary = w["towns"].get(String(fac.get("capital", "")), {})
		if not TownEcon.has_econ(cap) or biz_of(cap["econ"]).is_empty() or String(cap.get("faction", "")) != String(fid):
			sync_towns(w, fid)
			continue
		var e: Dictionary = cap["econ"]
		var b := biz_of(e)
		var wage := float(b["wage"])
		var act := active_lines(w, fid)
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
		var lead_day := wage * (1.0 + float(RR["lead_pay"]))
		var budget := lead_day
		var places := 1
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
		S["paid"] = snappedf(paid, 0.1)
		if paid < want * 0.5 and budget > 0.0 and int(S.get("short_wk", 0)) == 0:
			_log(S, day, "the treasury could not fund %s's budget in full." % house_name(e))
		S["short_wk"] = 1 if paid < want * 0.5 and budget > 0.0 else 0
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
	if laid < n and L.size() >= 2:   # nothing left to pay even the lead: his post goes too
		var lf: Dictionary = e["fams"][int(L[0])]
		Families.set_job(e, lf, bid, 0)
		affected[int(lf["id"])] = true
		laid += 1
	return laid

## Steel pieces in the faction's towns' stalls and armories (met in trade, in loot, from its own smiths).
static func _steel_met(w: Dictionary, fid: String) -> int:
	var n := 0
	for tid in w["factions"].get(fid, {}).get("towns", []):
		var t: Dictionary = w["towns"].get(tid, {})
		for key in ["shop", "armory_items"]:
			for it in t.get(key, []):
				if it is Item and it.material == "steel":
					n += 1
	return n

static func _study(town: Dictionary, e: Dictionary, b: Dictionary, S: Dictionary, fid: String, day: float) -> void:
	if (b.get("lead", []) as Array).size() < 2:
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
	if float(b["till"]) < cost * 2.0:
		return
	var mkt: Dictionary = e["biz"][int(e["mkt"])]
	b["till"] = float(b["till"]) - cost
	mkt["till"] = float(mkt["till"]) + cost
	shop.remove_at(pick)
	TownEcon.led(e, "used", "arms", 1)
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
