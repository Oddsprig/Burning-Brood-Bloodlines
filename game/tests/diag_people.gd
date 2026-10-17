extends "res://tests/diag_barge_years.gd"
## DIAGNOSTIC (not a regression test): diag_barge_years plus, per race and year, why the births, the orc towns and
## the coin come out as they do, read from the people and the books themselves:
##   PEOPLE   the age / sex pyramid (bands by the race's own ages), women of an age to bear (adult .. mother_max)
##            and how many are married, their husband at home, the family hungry or crowded, nursing a baby;
##            census births per 1,000 a year
##   WEDDINGS the singles of an age to marry, what keeps them single, the wedding calls and how many hit the cap
##   TREASURY treasuries against their lines, and the treasury's flows by work job (per race)
##   MINTS    each mint's days by state, its bars, its cast this year; coin per head by faction
## DIAG_DAYS, DIAG_SEED, DIAG_SCALE as diag_barge_years.

var wed := {}   # race -> {calls, weds, capped, no_men, no_women}
var tre_job := {}   # race -> {job: treasury change}
var mint_days := {}   # tid -> {state: days}
var cast0 := {}   # tid -> cast at the last report
var births0 := {}   # race -> census births at the last report
var deaths0 := {}   # race -> {cause: census deaths} at the last report
var pop_sum := {}   # race -> sum of daily pop (for the year's mean)
var pop_n := 0

func _race_of_e(e: Dictionary) -> String:
	return String(TownEcon.culture_of(e).get("race", "?"))

func _tre_by_race(w: Dictionary) -> Dictionary:
	var out := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var r := _race_of_e(t["econ"])
		out[r] = float(out.get(r, 0.0)) + float(t["econ"]["treasury"])
	return out

func _one_day(game) -> void:
	game.day += 1.0
	var w: Dictionary = game.world
	var rng := CampaignWorld._rng(w)
	var t0: float = game.day - 1.0
	var steps := maxi(1, ceili(1.0 / CampaignWorld.STEP))
	var dt := 1.0 / steps
	var s0 := _snap(w)
	var r0 := _tre_by_race(w)
	for i in steps:
		var t := t0 + dt * (i + 1)
		WarAI.tick(game, t, dt)
		CampaignWorld._move_warbands(game, dt, t, rng)
		CampaignWorld._warband_clashes(game, t, rng)
		Tracks.step(game, t)
	Monsters.on_time(game, 1.0)
	var whole := int(floor(game.day))
	while int(w.get("last_day", 0)) < whole:
		w["last_day"] = int(w.get("last_day", 0)) + 1
		CampaignWorld._daily(game, int(w["last_day"]), rng)
	_add("map+daily", s0, _snap(w))
	_tre_add("map+daily", r0, _tre_by_race(w))
	while not (w.get("work", []) as Array).is_empty():
		var job: Array = w["work"][0]
		var k := String(job[0])
		var a := _snap(w)
		var ra := _tre_by_race(w)
		var wed_e: Dictionary = {}
		var wed_pre := []
		if k == "wed" and w["towns"].has(job[1]) and TownEcon.has_econ(w["towns"][job[1]]):
			wed_e = w["towns"][job[1]]["econ"]
			wed_pre = _singles(wed_e, float(job[2]))
		CampaignWorld._do_work(game, rng)
		_add(k, a, _snap(w))
		_tre_add(k, ra, _tre_by_race(w))
		if not wed_e.is_empty():
			var r := _race_of_e(wed_e)
			var row: Dictionary = wed.get(r, {"calls": 0, "weds": 0, "capped": 0, "no_men": 0, "no_women": 0})
			var post := _singles(wed_e, float(job[2]))
			var n := int(post[0]) - int(wed_pre[0])
			row["calls"] += 1
			row["weds"] += n
			if n >= 2:
				row["capped"] += 1
			if int(wed_pre[1]) == 0:
				row["no_men"] += 1
			if int(wed_pre[2]) == 0:
				row["no_women"] += 1
			wed[r] = row
	# the mints' day
	for tid in w["towns"]:
		var t2: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t2) or not t2["econ"].has("mint_biz"):
			continue
		var b: Dictionary = t2["econ"]["biz"][int(t2["econ"]["mint_biz"])]
		var s := String(b.get("state", "?")) + ("/" + String(b.get("why", "")) if String(b.get("state", "")) == "inputs" else "")
		if not mint_days.has(tid):
			mint_days[tid] = {}
		mint_days[tid][s] = int(mint_days[tid].get(s, 0)) + 1
	for tid in w["towns"]:
		var t3: Dictionary = w["towns"][tid]
		if TownEcon.has_econ(t3):
			var r3 := _race_of_e(t3["econ"])
			pop_sum[r3] = int(pop_sum.get(r3, 0)) + Census.people(t3["econ"])
	pop_n += 1
	w["rng_state"] = str(rng.state)
	w["encounter"] = ""

func _tre_add(k: String, a: Dictionary, b: Dictionary) -> void:
	for r in b:
		var d := float(b[r]) - float(a.get(r, 0.0))
		if absf(d) < 0.5:
			continue
		if not tre_job.has(r):
			tre_job[r] = {}
		tre_job[r][k] = float(tre_job[r].get(k, 0.0)) + d

## [married couples (women with a husband in the house), eligible men, eligible women] as Persons.marriages sees them.
func _singles(e: Dictionary, day: float) -> Array:
	var ab := People.ages(_race_of_e(e))
	var yd := People.year_days()
	var A := float(ab["adult"]); var M := float(ab.get("mother_max", float(ab["elder"]) - 10.0))
	var married := 0; var men := 0; var women := 0
	for f in e["fams"]:
		if f.get("gone", false) or f.get("estate", false) or not f.has("pp"):
			continue
		for p in f["pp"]:
			if int(p[2]) == 1 and not Persons.by_pid(f, int(p[Persons.SP])).is_empty():
				married += 1
			if int(p[6]) != 0 or String(p[4]) != "" or (p as Array).size() < Persons.SIZE or String(p[7]) != "":
				continue
			if not Persons.by_pid(f, int(p[Persons.SP])).is_empty():
				continue
			var age := (day - float(p[3])) / yd
			if int(p[2]) == 0 and age >= A + 2.0:
				men += 1
			elif int(p[2]) == 1 and age >= A and age < M - 5.0:
				women += 1
	return [married, men, women]

func _report(w: Dictionary, ids: Array, year: int) -> void:
	super._report(w, ids, year)
	var day := float(Game.day)
	var yd := People.year_days()
	var R := {}
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var race := _race_of_e(e)
		var ab := People.ages(race)
		var A := float(ab["adult"]); var E := float(ab["elder"]); var M := float(ab.get("mother_max", E - 10.0))
		if not R.has(race):
			R[race] = {"bands": [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]], "fw": 0, "fw_married": 0, "fw_hus_home": 0, "fw_hus_away": 0,
				"fw_widow": 0, "fw_single": 0, "fw_hungry": 0, "fw_crowded": 0, "fw_baby": 0, "fw_away": 0,
				"fams": 0, "fam_mo": 0, "fam_mo_ok": 0, "fam_mo_hungry": 0, "fam_mo_crowded": 0, "fam_no_m": 0, "fam_no_f": 0,
				"sw": 0, "sw_age": 0, "sw_free": 0, "sm": 0, "sm_young": 0, "surn": 0, "towns": 0, "census_b": 0,
				"tre": 0.0, "full": 0.0, "short": 0.0, "over_full": 0, "under_short": 0, "pop": 0, "wage_bill": 0.0, "kids": 0}
		var r: Dictionary = R[race]
		r["towns"] += 1
		r["pop"] += Census.people(e)
		var L := Barge.treasury_lines(e)
		r["tre"] += float(e["treasury"]); r["full"] += float(L["full"]); r["short"] += float(L["short"])
		if float(e["treasury"]) > float(L["full"]):
			r["over_full"] += 1
		if float(e["treasury"]) < float(L["short"]):
			r["under_short"] += 1
		r["wage_bill"] += float(e["stats"].get("town_wages", 0.0))
		var rs: Array = Census.rows(e)
		var parts: Array = rs.slice(1)
		parts.append(Census.current(e))
		if not r.has("dc"):
			r["dc"] = {}
			r["food"] = {}
		for row in parts:
			r["census_b"] += int(row["births"])
			for c in row["deaths"]:
				r["dc"][c] = int(r["dc"].get(c, 0)) + int(row["deaths"][c])
			for c in row["left"]:
				r["dc"]["left:" + c] = int(r["dc"].get("left:" + c, 0)) + int(row["left"][c])
		var fd: Dictionary = r["food"]
		for g in ["grain", "meat", "fruit"]:
			fd[g + "_p"] = float(fd.get(g + "_p", 0.0)) + float(e["price"].get(g, 0.0)) / float(TownEcon.data()["goods"][g]["price"])
			fd[g + "_st"] = int(fd.get(g + "_st", 0)) + int(e["stock"].get(g, 0))
		var est: Dictionary = e["fams"][0]
		fd["est_acres"] = int(fd.get("est_acres", 0)) + Families.acres(est)
		fd["est_heads"] = int(fd.get("est_heads", 0)) + Families.heads(est)
		var hh := 0
		for f in e["fams"]:
			if not f.get("gone", false) and not f.get("estate", false):
				hh += Families.heads(f)
		fd["fam_heads"] = int(fd.get("fam_heads", 0)) + hh
		fd["granary"] = int(fd.get("granary", 0)) + int(e["granary"])
		var hm: Dictionary = TownEcon.culture_of(e)["home"]
		for m in hm["materials"]:
			fd["mat:" + m] = int(fd.get("mat:" + m, 0)) + int(e["stock"].get(m, 0))
		fd["home_stock"] = int(fd.get("home_stock", 0)) + int(e["stock"].get("home", 0))
		fd["home_p"] = float(fd.get("home_p", 0.0)) + float(e["price"].get("home", 0.0))
		fd["est_homes"] = int(fd.get("est_homes", 0)) + int(est["homes"])
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false):
				continue
			if int(f["homes"]) <= 0:
				fd["homeless"] = int(fd.get("homeless", 0)) + 1
				if int(f["hungry"]) > 0:
					fd["homeless_hungry"] = int(fd.get("homeless_hungry", 0)) + 1
			elif int(f["hungry"]) > 0:
				fd["housed_hungry"] = int(fd.get("housed_hungry", 0)) + 1
			fd["cond"] = float(fd.get("cond", 0.0)) + float(f["cond"])
			fd["nf"] = int(fd.get("nf", 0)) + 1
			for ev in f.get("ev", []):
				if String(ev[1]) == "home_ruin" and float(ev[0]) > day - 120.0:
					fd["ruins"] = int(fd.get("ruins", 0)) + 1
		fd["works"] = float(fd.get("works", 0.0)) + float(e["stats"].get("works", 0.0))
		var surn := {}
		var cul: Dictionary = TownEcon.culture_of(e)
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false) or not f.has("pp"):
				continue
			surn[String(f["name"])] = true
			r["fams"] += 1
			var room := float(f["homes"]) * float(cul["home"]["room"]) * (0.6 + 0.4 * float(f["cond"]))
			var ppl := float(Families.people(f))
			var crowded := ppl >= room
			if int(f["m"]) <= 0:
				r["fam_no_m"] += 1
			if int(f["f"]) <= 0:
				r["fam_no_f"] += 1
			var mo := Persons.mother_for(e, f, day)
			if not mo.is_empty():
				r["fam_mo"] += 1
				if int(f["hungry"]) > 0:
					r["fam_mo_hungry"] += 1
				elif crowded:
					r["fam_mo_crowded"] += 1
				else:
					r["fam_mo_ok"] += 1
			var free := Families.adults(f) - Families.serving(f)
			if free >= 2 and not Persons.can_lose(f, 1):
				free = 0
			for p in Persons.kp(f):
				r["kids"] += 1
				var ak := (day - float(p[3])) / yd
				r["bands"][0 if ak < A * 0.5 else 1][int(p[2])] += 1
			for p in Persons.pp(f):
				var age := (day - float(p[3])) / yd
				var sx := int(p[2])
				var bi := 5 if int(p[6]) == 1 else (2 if age < A + (M - A) * 0.5 else (3 if age < M else 4))
				r["bands"][bi][sx] += 1
				if sx == 1 and int(p[6]) == 0 and age >= A and age < M:
					r["fw"] += 1
					if not (String(p[4]) in ["", "hire", "militia"]):
						r["fw_away"] += 1
					var h := Persons.by_pid(f, int(Persons.g(p, Persons.SP, -1)))
					if not h.is_empty():
						r["fw_married"] += 1
						if String(h[4]) in ["", "hire", "militia"]:
							r["fw_hus_home"] += 1
						else:
							r["fw_hus_away"] += 1
						if int(f["hungry"]) > 0:
							r["fw_hungry"] += 1
						if crowded:
							r["fw_crowded"] += 1
						var baby := false
						for k in Persons.kp(f):
							if int(k[Persons.MO]) == int(p[0]) and day - float(k[3]) < 2.0 * yd:
								baby = true
						if baby:
							r["fw_baby"] += 1
					elif int(Persons.g(p, Persons.SP, -1)) >= 0:
						r["fw_widow"] += 1
					else:
						r["fw_single"] += 1
				# singles of an age to marry (Persons.marriages' rules)
				if int(p[6]) == 0 and String(p[4]) == "" and Persons.by_pid(f, int(Persons.g(p, Persons.SP, -1))).is_empty():
					if sx == 1 and age >= A and age < M:
						r["sw"] += 1
						if age >= M - 5.0:
							r["sw_age"] += 1
						elif free < 2:
							r["sw_free"] += 1
					elif sx == 0 and age >= A:
						r["sm"] += 1
						if age < A + 2.0:
							r["sm_young"] += 1
		r["surn"] += surn.size()
	var races: Array = R.keys()
	races.sort()
	for race in races:
		var r: Dictionary = R[race]
		var b: Array = r["bands"]
		var ab := People.ages(race)
		var mean_pop := float(pop_sum.get(race, 0)) / maxf(1.0, float(pop_n)) if pop_n > 0 else float(r["pop"])
		var yb := int(r["census_b"]) - int(births0.get(race, 0))
		births0[race] = int(r["census_b"])
		print("   PEOPLE %-9s ages %s: pop %d (year mean %.0f); census births this year %d = %.1f per 1,000, %.3f per woman of bearing age | pyramid m/f: child<%.0f %d/%d, child %d/%d, young adult %d/%d, older fertile %d/%d, past mother_max %d/%d, elders %d/%d" % [
			race, str(ab), int(r["pop"]), mean_pop, yb, 1000.0 * float(yb) / maxf(1.0, mean_pop), float(yb) / maxf(1.0, float(r["fw"])), float(ab["adult"]) * 0.5,
			b[0][0], b[0][1], b[1][0], b[1][1], b[2][0], b[2][1], b[3][0], b[3][1], b[4][0], b[4][1], b[5][0], b[5][1]])
		print("      women adult..mother_max %d: married %d (husband home %d, away %d), widowed %d, never married %d, away themselves %d; of the married: family hungry %d, crowded (ppl >= room) %d, a child under 2 %d" % [
			int(r["fw"]), int(r["fw_married"]), int(r["fw_hus_home"]), int(r["fw_hus_away"]), int(r["fw_widow"]), int(r["fw_single"]), int(r["fw_away"]),
			int(r["fw_hungry"]), int(r["fw_crowded"]), int(r["fw_baby"])])
		print("      families %d: no man %d, no woman %d; with a mother (mother_for) %d -> hungry %d, crowded %d, open to a birth %d" % [
			int(r["fams"]), int(r["fam_no_m"]), int(r["fam_no_f"]), int(r["fam_mo"]), int(r["fam_mo_hungry"]), int(r["fam_mo_crowded"]), int(r["fam_mo_ok"])])
		var wr: Dictionary = wed.get(race, {})
		print("      singles at home: women %d (too old to wed, >= mother_max-5: %d; her house would keep < 2 grown-ups, no longer a rule: %d), men %d (under adult+2: %d); surnames a town %.1f; weddings this year %d in %d calls (capped at 2: %d; no eligible man %d, no eligible woman %d)" % [
			int(r["sw"]), int(r["sw_age"]), int(r["sw_free"]), int(r["sm"]), int(r["sm_young"]), float(r["surn"]) / maxf(1.0, float(r["towns"])),
			int(wr.get("weds", 0)), int(wr.get("calls", 0)), int(wr.get("capped", 0)), int(wr.get("no_men", 0)), int(wr.get("no_women", 0))])
		var dd := {}
		var d0: Dictionary = deaths0.get(race, {})
		for c in r.get("dc", {}):
			var v := int(r["dc"][c]) - int(d0.get(c, 0))
			if v != 0:
				dd[c] = v
		deaths0[race] = (r.get("dc", {}) as Dictionary).duplicate()
		var fdx: Dictionary = r.get("food", {})
		var nt := maxf(1.0, float(r["towns"]))
		print("      DEATHS / LEFT this year %s; food price x base grain %.2f meat %.2f fruit %.2f, market stock grain %d meat %d fruit %d; herds: families %d, town estate %d; estate acres %d; granary %d; works spent this week %d" % [
			str(dd), float(fdx.get("grain_p", 0.0)) / nt, float(fdx.get("meat_p", 0.0)) / nt, float(fdx.get("fruit_p", 0.0)) / nt, int(fdx.get("grain_st", 0)), int(fdx.get("meat_st", 0)), int(fdx.get("fruit_st", 0)),
			int(fdx.get("fam_heads", 0)), int(fdx.get("est_heads", 0)), int(fdx.get("est_acres", 0)), int(fdx.get("granary", 0)), int(fdx.get("works", 0.0))])
		var mats := []
		for k in fdx:
			if String(k).begins_with("mat:"):
				mats.append("%s %d" % [String(k).substr(4), int(fdx[k])])
		print("      HOMES families %d: homeless %d (hungry %d), housed and hungry %d; mean condition %.2f; homes fallen to ruin this year %d; market: home materials %s, new homes %d at %.0f; empty town houses %d" % [
			int(fdx.get("nf", 0)), int(fdx.get("homeless", 0)), int(fdx.get("homeless_hungry", 0)), int(fdx.get("housed_hungry", 0)), float(fdx.get("cond", 0.0)) / maxf(1.0, float(fdx.get("nf", 0))),
			int(fdx.get("ruins", 0)), ", ".join(PackedStringArray(mats)), int(fdx.get("home_stock", 0)), float(fdx.get("home_p", 0.0)) / nt, int(fdx.get("est_homes", 0))])
		var tj: Dictionary = tre_job.get(race, {})
		var tl := []
		for k in tj:
			tl.append("%s %+d" % [k, int(tj[k])])
		print("      TREASURY %d towns: held %d (lines: short %d, full %d; over full %d towns, under short %d); town wage bill %d a day; flows this year by job: %s" % [
			int(r["towns"]), int(r["tre"]), int(r["short"]), int(r["full"]), int(r["over_full"]), int(r["under_short"]), int(r["wage_bill"]), ", ".join(PackedStringArray(tl))])
	# mints
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t) or not t["econ"].has("mint_biz"):
			continue
		var e: Dictionary = t["econ"]
		var mb: Dictionary = e["biz"][int(e["mint_biz"])]
		var cast := float(e["stats"].get("cast", 0.0))
		var st: Dictionary = e["stock"]
		print("   MINT %-14s %-8s %-10s minters %d/%d, days %s, cast this year %d; bars copper %d tin %d bronze %d wood %d; metal per 1,000 %.0f; treasury %d (short %d, full %d)" % [
			String(t["name"]).substr(0, 14), _race_of_e(e), String(t["faction"]).substr(0, 10), int(mb["workers"]), int(mb["cap"]), str(mint_days.get(tid, {})),
			int(cast - float(cast0.get(tid, 0.0))), int(st.get("copper_bars", 0)), int(st.get("tin_bars", 0)), int(st.get("bronze_bars", 0)), int(st.get("wood", 0)),
			Barge.metal_per_k(e), int(e["treasury"]), int(Barge.treasury_lines(e)["short"]), int(Barge.treasury_lines(e)["full"])])
		cast0[tid] = cast
	# the home materials' makers in each town (DIAG_MAKERS=1)
	if OS.get_environment("DIAG_MAKERS") == "1":
		for tid in ids:
			var t: Dictionary = w["towns"][tid]
			var e: Dictionary = t["econ"]
			var hm: Dictionary = TownEcon.culture_of(e)["home"]
			var bl := []
			for b in e["biz"]:
				if b.get("closed", false):
					continue
				var outs := {}
				for rc in TownEcon.data()["businesses"].get(b["type"], {}).get("recipes", []):
					for g in rc.get("out", {}):
						outs[g] = true
				var hit := false
				for m in hm["materials"]:
					if outs.has(m) or (m == "leather" and outs.has("hides")):
						hit = true
				if hit or b["type"] in ["builder", "leatherworker", "armorsmith"]:
					bl.append("%s %d/%d %s" % [b["type"], int(b["workers"]), int(b["cap"]), String(b.get("state", ""))])
			var ms := []
			for m in hm["materials"].keys() + ["hides", "home"]:
				ms.append("%s %d @%.0f" % [m, int(e["stock"].get(m, 0)), float(e["price"].get(m, 0.0))])
			print("   MAKERS %-12s %-8s %s | %s | herds %s" % [String(t["name"]).substr(0, 12), _race_of_e(e), ", ".join(PackedStringArray(ms)), "; ".join(PackedStringArray(bl)), str(e.get("herd", {}))])
	# the coin metals, world: made and used this year, held in the markets, the mean price x base
	var ml := []
	for g in ["copper_ore", "copper_bars", "tin_bars", "bronze_bars"]:
		var mk := 0; var us := 0; var stv := 0; var pr := 0.0; var n := 0
		for tid in ids:
			var e: Dictionary = w["towns"][tid]["econ"]
			mk += int(e["led"]["made"].get(g, 0)); us += int(e["led"]["used"].get(g, 0)); stv += int(e["stock"].get(g, 0))
			pr += float(e["price"].get(g, 0.0)) / float(TownEcon.data()["goods"][g]["price"]); n += 1
		var key: String = "metal:" + String(g)
		var prev: Array = cast0.get(key, [0, 0])
		ml.append("%s made %d used %d held %d price x%.1f" % [g, mk - int(prev[0]), us - int(prev[1]), stv, pr / maxf(1.0, float(n))])
		cast0[key] = [mk, us]
	print("   METALS " + "; ".join(PackedStringArray(ml)))
	# coin by faction
	for fid in w["factions"]:
		var fac: Dictionary = w["factions"][fid]
		var pop := 0; var coin := 0.0; var mints := 0; var nt := 0; var rc := ""
		for tid in fac.get("towns", []):
			var t: Dictionary = w["towns"].get(tid, {})
			if not TownEcon.has_econ(t):
				continue
			nt += 1
			pop += int(t["econ"]["pop"])
			coin += TownEcon.town_gold(t["econ"])
			rc = _race_of_e(t["econ"])
			if t["econ"].has("mint_biz"):
				mints += 1
		if nt == 0:
			continue
		print("   COIN %-12s %-8s towns %d mints %d pop %d: town coin a head %.0f, realm chest %d, PL %.2f, index %.2f" % [String(fid).substr(0, 12), rc, nt, mints, pop,
			coin / maxf(1.0, float(pop)), int(fac.get("treasury", 0.0)), float(fac.get("pl", 1.0)), float(fac.get("mindex", 1.0))])
	_labour_report(w, ids, year)
	wed = {}
	tre_job = {}
	mint_days = {}
	pop_sum = {}
	pop_n = 0

var wood0 := {}   # race -> wood made at the last report

## LABOUR (per race): the grown-ups at home and where they work (own land, jobs, field hands, casual, idle), the
## hands the land needs; every trade's staff against its places and its pay; Grolruk's rows; wood made and held.
## DEATHS BY AGE (per race): this year's census deaths by cause and the race's own bands (child, adult, elder).
func _labour_report(w: Dictionary, ids: Array, _year: int) -> void:
	var day := float(Game.day)
	var R := {}
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		var race := _race_of_e(e)
		if not R.has(race):
			R[race] = {"ad": 0, "need": 0.0, "own": 0, "help": 0.0, "jobs": 0, "field": 0, "cj": 0, "idle": 0, "biz": {}, "wood_m": 0, "wood_st": 0,
				"dages": {}, "pop": 0}
		var r: Dictionary = R[race]
		r["pop"] += int(e["pop"])
		r["wood_m"] += int(e["led"]["made"].get("wood", 0))
		r["wood_st"] += int(e["stock"].get("wood", 0))
		for f in e["fams"]:
			if f.get("gone", false) or f.get("estate", false):
				continue
			r["ad"] += maxi(0, Families.adults(f) - Families.serving(f))
			r["need"] += Families.need_hands(f)
			r["own"] += int(f["hands"])
			for k in f["jobs"]:
				if String(e["biz"][int(k)]["type"]) == "farm":
					r["field"] += int(f["jobs"][k])
				else:
					r["jobs"] += int(f["jobs"][k])
			for j in f.get("cj", {}):
				r["cj"] += int(f["cj"][j])
			r["idle"] += int(f.get("idle", 0))
		var bz: Dictionary = r["biz"]
		for b in e["biz"]:
			if b.get("closed", false) or String(b["type"]) in ["market", "collector", "estate"]:
				continue
			var ty := String(b["type"])
			if not bz.has(ty):
				bz[ty] = [0, 0, 0.0, 0]
			bz[ty][0] += int(b["workers"])
			bz[ty][1] += int(b["cap"])
			bz[ty][2] += float(b["wage"])
			bz[ty][3] += 1
		if OS.get_environment("DIAG_ROWS") == "1":
			var rl := []
			for b in e["biz"]:
				if not b.get("closed", false) and String(b["type"]) in ["mine", "smelter", "woodcutter", "tanner", "builder"]:
					rl.append("%s %d/%d @%.0f till %.0f %s %s %s ld%d p14 %.0f" % [b["type"], int(b["workers"]), int(b["cap"]), float(b["wage"]), float(b["till"]),
						String(b.get("state", "")), String(b.get("why", "")), String(b.get("health", "")), int(b.get("ld", 0)), float(b.get("p14", 0.0))])
			print("   ROWS %-12s %-8s dw %.0f; ore %d @%.0f, bars %d @%.0f, wood %d @%.0f, hides %d @%.0f, leather %d @%.0f | %s" % [String(t["name"]).substr(0, 12), race, Barge.day_wage(e),
				int(e["stock"].get("copper_ore", 0)), float(e["price"].get("copper_ore", 0.0)), int(e["stock"].get("copper_bars", 0)), float(e["price"].get("copper_bars", 0.0)),
				int(e["stock"].get("wood", 0)), float(e["price"].get("wood", 0.0)), int(e["stock"].get("hides", 0)), float(e["price"].get("hides", 0.0)),
				int(e["stock"].get("leather", 0)), float(e["price"].get("leather", 0.0)), "; ".join(PackedStringArray(rl))])
		if String(t["name"]).begins_with("Grolruk"):
			var gl := []
			for b in e["biz"]:
				if b.get("closed", false) or String(b["type"]) in ["market", "collector", "farm"]:
					continue
				gl.append("%s %d/%d @%.0f %s" % [b["type"], int(b["workers"]), int(b["cap"]), float(b["wage"]), String(b.get("state", ""))])
			var ad := 0
			var own := 0
			var nd := 0.0
			for f in e["fams"]:
				if not f.get("gone", false) and not f.get("estate", false):
					ad += maxi(0, Families.adults(f) - Families.serving(f))
					own += int(f["hands"])
					nd += Families.need_hands(f)
			print("   GROLRUK grown-ups at home %d, on own land %d (land needs %.0f hands), day wage %.0f; wood %d @%.0f, leather %d; %s" % [ad, own, nd, Barge.day_wage(e),
				int(e["stock"].get("wood", 0)), float(e["price"].get("wood", 0.0)), int(e["stock"].get("leather", 0)), "; ".join(PackedStringArray(gl))])
		var ab := People.ages(race)
		for d in Census._book(e)["deaths"]:
			if float(d[0]) < day - 120.0 or int(d[9]) == 0:
				continue
			var age := int(d[3])
			var band := "?" if age < 0 else ("child" if age < int(ab["adult"]) else ("adult" if age < int(ab["elder"]) else "elder"))
			var key := "%s/%s" % [String(d[5]), band]
			r["dages"][key] = int(r["dages"].get(key, 0)) + 1
			if race.ends_with("elf") and age >= 0:
				var dec := "%s/%d0s" % [String(d[5]), age / 10] if age < 100 else "%s/%d00s" % [String(d[5]), age / 100]
				r["dages"]["~" + dec] = int(r["dages"].get("~" + dec, 0)) + 1
	var races: Array = R.keys()
	races.sort()
	for race in races:
		var r: Dictionary = R[race]
		var bl := []
		var tys: Array = (r["biz"] as Dictionary).keys()
		tys.sort()
		for ty in tys:
			var v: Array = r["biz"][ty]
			bl.append("%s %d/%d @%.0f" % [ty, int(v[0]), int(v[1]), float(v[2]) / maxf(1.0, float(v[3]))])
		var wm := int(r["wood_m"]) - int(wood0.get(race, 0))
		wood0[race] = int(r["wood_m"])
		print("   LABOUR %-9s grown-ups at home %d: own land %d (land needs %.0f hands), jobs %d, field hands %d, casual %d, idle %d; wood made this year %d, held %d" % [
			race, int(r["ad"]), int(r["own"]), float(r["need"]), int(r["jobs"]), int(r["field"]), int(r["cj"]), int(r["idle"]), wm, int(r["wood_st"])])
		print("      TRADES staff/places @wage: " + ", ".join(PackedStringArray(bl)))
		var dk: Array = (r["dages"] as Dictionary).keys()
		dk.sort()
		var dl := []
		for k in dk:
			dl.append("%s %d" % [k, int(r["dages"][k])])
		print("      DEATHS BY AGE this year (pop %d): %s" % [int(r["pop"]), ", ".join(PackedStringArray(dl))])
