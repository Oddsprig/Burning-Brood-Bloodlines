extends RefCounted
## DIAGNOSTIC (not a regression test): runs the years before (seed 2026) day by day exactly as
## CampaignWorld.presim_step / on_time(1 day, in_town) does, but drains the work queue one job at a time and
## attributes every change in food, gold, people to the job type that made it. Prints per-season tables.
## DIAG_DAYS (default 240) limits the run; DIAG_TOWNS=1 prints per-town lines.

const FOOD := ["grain", "fruit", "meat"]

var acc := {}      # per-season accumulators
var fam_acc := {}  # hunger causes at family turns
var led0 := {}

func run(_tree: SceneTree) -> int:
	var days := int(OS.get_environment("DIAG_DAYS")) if OS.get_environment("DIAG_DAYS") != "" else 240
	var per_town := OS.get_environment("DIAG_TOWNS") == "1"
	Game.new_game(2026)
	var w: Dictionary = Game.world
	w["presim"] = {"total": days, "done": 0, "from": Game.day}
	var ids: Array = w["towns"].keys()
	ids.sort()
	print("towns: %d" % ids.size())
	_static(w, ids)
	_season_report(w, ids, -1, per_town)
	_reset()
	var t0 := Time.get_ticks_msec()
	for d in days:
		_one_day(Game)
		w["presim"]["done"] = int(w["presim"]["done"]) + 1
		if (d + 1) % 30 == 0:
			_season_report(w, ids, (d + 1) / 30 - 1, per_town)
			_reset()
	print("wall %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	return 0

func _reset() -> void:
	acc = {"by_job": {}, "mil_paid": 0.0, "mil_bill": 0.0, "shel_cost": 0.0, "food_short_days": 0.0, "fs_sum": 0.0, "fs_n": 0}
	fam_acc = {"turns": 0, "hungry_own": 0, "hungry_flag_only": 0, "hungry_homeless": 0, "flag_turns": 0, "want": 0, "cant_afford_week": 0, "cant_afford_fill": 0, "stall_thin": 0}
	led0 = _led_by_good(Game.world)

# ---------------------------------------------------------------- one day, as on_time(game, 1.0, true)
func _one_day(game) -> void:
	game.day += 1.0
	var w: Dictionary = game.world
	var rng := CampaignWorld._rng(w)
	var dd := 1.0
	var steps := maxi(1, ceili(dd / CampaignWorld.STEP))
	var dt := dd / steps
	var t0: float = game.day - dd
	var s0 := _snap(w)
	for i in steps:
		var t := t0 + dt * (i + 1)
		WarAI.tick(game, t, dt)
		CampaignWorld._move_warbands(game, dt, t, rng)
		CampaignWorld._warband_clashes(game, t, rng)
		Tracks.step(game, t)
	Monsters.on_time(game, dd)
	var whole := int(floor(game.day))
	while int(w.get("last_day", 0)) < whole:
		w["last_day"] = int(w.get("last_day", 0)) + 1
		CampaignWorld._daily(game, int(w["last_day"]), rng)
	_add("map+daily", s0, _snap(w))
	while not (w.get("work", []) as Array).is_empty():
		var job: Array = w["work"][0]
		var k := String(job[0])
		if k == "fam":
			_pre_fam(w, job)
		var a := _snap(w)
		CampaignWorld._do_work(game, rng)
		_add(k, a, _snap(w))
		if k == "econ" and w["towns"].has(job[1]):
			var st: Dictionary = w["towns"][job[1]]["econ"]["stats"]
			acc["mil_paid"] += float(st.get("militia_wages", 0.0))
			acc["mil_bill"] += float(st.get("militia_bill", 0.0))
			acc["shel_cost"] += float(st.get("shelter_cost", 0.0))
			acc["fs_sum"] += float(w["towns"][job[1]]["econ"].get("food_short", 0.0))
			acc["fs_n"] += 1
	w["rng_state"] = str(rng.state)
	w["encounter"] = ""

## Hunger causes for the families whose turn it is (before the turn runs).
func _pre_fam(w: Dictionary, job: Array) -> void:
	if not w["towns"].has(job[1]):
		return
	var e: Dictionary = w["towns"][job[1]]["econ"]
	var day := int(job[2])
	var fams: Array = e["fams"]
	var i := day % 7
	var flag: bool = float(e.get("food_short", 0.0)) > 0.15
	while i < fams.size():
		var f: Dictionary = fams[i]
		i += 7
		if f["gone"] or f.has("estate"):
			continue
		var dys := clampf(float(day) - float(f["last"]), 1.0, 60.0)
		fam_acc["turns"] += 1
		if flag:
			fam_acc["flag_turns"] += 1
		if int(f["homes"]) <= 0:
			fam_acc["hungry_homeless"] += 1 if float(f["store"]["food"]) - dys < 0.0 else 0
			continue
		var own: bool = float(f["store"]["food"]) - dys < 0.0
		var sf := float(f["store"]["food"]) - dys
		if sf < 18.0:
			var fr := float(Families.people(f)) * 2.0
			var want := (30.0 - maxf(0.0, sf)) * fr
			var pm := 0.65 * float(e["price"]["grain"]) + 0.15 * float(e["price"]["fruit"]) + 0.2 * float(e["price"]["meat"])
			var purse := float(f["purse"]) + maxf(0.0, float(f.get("inc", 0.0)))
			var onstall := float(e["stock"].get("grain", 0)) + float(e["stock"].get("fruit", 0)) + float(e["stock"].get("meat", 0))
			fam_acc["want"] += 1
			if purse < 7.0 * fr * pm:
				fam_acc["cant_afford_week"] += 1
			if purse < want * pm:
				fam_acc["cant_afford_fill"] += 1
			if onstall < want * 5.0:
				fam_acc["stall_thin"] += 1
		if own:
			fam_acc["hungry_own"] += 1
		elif flag:
			fam_acc["hungry_flag_only"] += 1

func _snap(w: Dictionary) -> Dictionary:
	var s := {"used": 0.0, "made": 0.0, "spoil": 0.0, "hold": 0.0, "hh": 0.0, "stock": 0.0, "barn": 0.0, "gran": 0.0,
		"tre": 0.0, "fac": 0.0, "pop": 0, "deaths": 0, "lefth": 0, "births": 0, "mkt": 0.0, "loot": 0.0, "army_st": 0.0}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not t.has("econ"):
			continue
		var e: Dictionary = t["econ"]
		var L: Dictionary = e["led"]
		for g in FOOD:
			s["used"] += float(L["used"].get(g, 0))
			s["made"] += float(L["made"].get(g, 0))
			s["spoil"] += float(L["spoil"].get(g, 0))
			s["hh"] += float(e["hh"].get(g, 0))
			s["stock"] += float(e["stock"].get(g, 0))
			s["barn"] += float(e["barn"].get(g, 0))
		s["gran"] += float(e["granary"])
		s["tre"] += float(e["treasury"])
		s["pop"] += int(e["pop"])
		s["deaths"] += int(e["stats"].get("deaths", 0))
		s["lefth"] += int(e["stats"].get("left_hunger", 0))
		s["births"] += int(e["stats"].get("births", 0))
		s["mkt"] += float(e["biz"][int(e["mkt"])]["till"])
	s["hold"] = s["hh"] + s["stock"] + s["barn"] + s["gran"]
	for fid in w["factions"]:
		s["fac"] += float(w["factions"][fid].get("treasury", 0.0))
	for wid in w["warbands"]:
		var st: Dictionary = w["warbands"][wid].get("stores", {})
		for g in FOOD:
			s["army_st"] += float(st.get(g, 0))
	return s

func _add(k: String, a: Dictionary, b: Dictionary) -> void:
	var bj: Dictionary = acc["by_job"]
	if not bj.has(k):
		bj[k] = {}
	var r: Dictionary = bj[k]
	for key in a:
		r[key] = float(r.get(key, 0.0)) + float(b[key]) - float(a[key])

# ---------------------------------------------------------------- reports
func _static(w: Dictionary, ids: Array) -> void:
	var D := TownEcon.data()
	print("STATIC: needs %.1f meals/person/day, year %d days -> %d meals/person/year; grain yield %d/acre/yr, %d acres/hand" % [
		float(D["needs"]["food"]), EconGen.YEAR_DAYS, int(float(D["needs"]["food"]) * EconGen.YEAR_DAYS), int(D["land"]["yield"]["grain"]), int(D["land"]["acres_per_hand"])])
	var pop := 0; var acres := {}; var herd := 0; var hunters := 0; var fish := 0; var hunt_cap := 0; var fish_cap := 0
	for tid in ids:
		var e: Dictionary = w["towns"][tid]["econ"]
		pop += int(e["pop"])
		for c in e["land"]:
			acres[c] = int(acres.get(c, 0)) + int(e["land"][c])
		for a in e["herd"]:
			herd += int(e["herd"][a])
		for b in e["biz"]:
			if b["type"] == "hunter":
				hunters += int(b["workers"]); hunt_cap += int(b["cap"])
			if b["type"] == "fishery":
				fish += int(b["workers"]); fish_cap += int(b["cap"])
	print("  world pop %d, acres %s, head %d, hunters %d/%d, fishers %d/%d" % [pop, str(acres), herd, hunters, hunt_cap, fish, fish_cap])
	var need_h := 0.0; var cap_trade := 0; var cap_farm := 0; var ad := 0; var kids := 0; var old := 0; var ppl_room := 0; var fams := 0
	for tid in ids:
		var e: Dictionary = w["towns"][tid]["econ"]
		var room := float(TownEcon.culture_of(e)["home"]["room"])
		for f in e["fams"]:
			if f.has("estate"):
				continue
			fams += 1
			need_h += Families.need_hands(f)
			ad += Families.adults(f); kids += int(f["kids"]); old += int(f["old"])
			if float(Families.people(f)) >= float(f["homes"]) * room * (0.6 + 0.4 * float(f["cond"])):
				ppl_room += 1
		for b in e["biz"]:
			if b["type"] == "farm":
				cap_farm += int(b["cap"])
			elif b["type"] != "estate":
				cap_trade += int(b["cap"])
	# land left unworked by the hands rounding (own = ceil(need - 0.3)) even with adults to spare, and by too few adults
	var lost_round := 0.0; var lost_adults := 0.0; var zero_fams := 0; var zero_acres := 0.0; var tot_ac := 0.0
	for tid in ids:
		var e: Dictionary = w["towns"][tid]["econ"]
		for f in e["fams"]:
			if f.has("estate"):
				continue
			var nh := Families.need_hands(f)
			if nh <= 0.0:
				continue
			var ac := float(Families.acres(f)) + float(Families.heads(f)) / 25.0 * 8.0   # herds in acre-equivalents of hands
			tot_ac += ac
			var r_own := float(int(ceil(nh - 0.3)))
			if r_own <= 0.0:
				zero_fams += 1; zero_acres += ac
			lost_round += ac * (1.0 - minf(1.0, r_own / nh))
			lost_adults += ac * (minf(1.0, r_own / nh) - float(f["worked"]))
	print("  LAND: of %.0f hand-acres, %.0f (%.0f%%) unworked by the ceil(need-0.3) rounding alone (%d families with < 0.3 hands of land work none of it: %.0f acres); %.0f more unworked for want of hands" % [
		tot_ac, lost_round, 100.0 * lost_round / maxf(1, tot_ac), zero_fams, zero_acres, lost_adults])
	print("  LABOUR: adults %d (kids %d, elders %d); land+herds need %.0f hands; trade/service places %d; hired-farm places %d; families with no room for a birth %d of %d" % [
		ad, kids, old, need_h, cap_trade, cap_farm, ppl_room, fams])
	var gy := float(acres.get("grain", 0)) * 200.0
	var fy := float(acres.get("fruit", 0)) * 160.0
	print("  annual capacity (full work, no tools loss, temperate): grain %d, fruit %d meals; need %d meals (grain share %d)" % [
		int(gy), int(fy), int(pop * 240), int(pop * 240 * 0.65)])

func _season_report(w: Dictionary, ids: Array, s: int, per_town: bool) -> void:
	var D := TownEcon.data()
	var pop := 0; var ad := 0; var fams := 0; var hungry := 0; var homeless := 0; var shel := 0
	var purse := 0.0; var broke := 0; var cant_week := 0; var inc_lt := 0; var inc_sum := 0.0
	var hands := 0; var idle := 0; var serve := {}; var jobs := {}; var tills := 0.0; var farm_till := 0.0
	var debt := 0.0; var land_w := 0.0; var land_t := 0.0
	var pg := 0.0; var pf := 0.0; var pm := 0.0
	var stock := {}; var barn := {}; var hh := {}; var gran := 0
	var tre := 0.0; var est_acres := 0; var est_workers := 0
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		pop += int(e["pop"]); ad += int(e["adults"])
		pg += float(e["price"]["grain"]) * int(e["pop"]); pf += float(e["price"]["fruit"]) * int(e["pop"]); pm += float(e["price"]["meat"]) * int(e["pop"])
		var wk_cost_pp := 14.0 * (0.65 * float(e["price"]["grain"]) + 0.15 * float(e["price"]["fruit"]) + 0.2 * float(e["price"]["meat"]))
		for g in FOOD:
			stock[g] = int(stock.get(g, 0)) + int(e["stock"].get(g, 0))
			barn[g] = int(barn.get(g, 0)) + int(e["barn"].get(g, 0))
			hh[g] = int(hh.get(g, 0)) + int(e["hh"].get(g, 0))
		gran += int(e["granary"])
		tre += float(e["treasury"])
		farm_till += float(e["farm_till"])
		for c in e["land"]:
			land_t += float(e["land"][c])
			land_w += float(e["wacres"].get(c, 0.0))
		est_acres += Families.acres(e["fams"][0])
		for b in e["biz"]:
			tills += float(b["till"])
			jobs[b["type"]] = int(jobs.get(b["type"], 0)) + int(b["workers"])
			if b["type"] == "estate":
				est_workers += int(b["workers"])
		var th := 0; var tfam := 0
		for f in e["fams"]:
			if f["gone"] or f.has("estate"):
				continue
			fams += 1; tfam += 1
			if int(f["hungry"]) > 0:
				hungry += 1; th += 1
			if int(f["homes"]) <= 0:
				homeless += 1
			if f.get("shel", false):
				shel += 1
			purse += float(f["purse"])
			debt += float(f["debt"])
			hands += int(f["hands"]); idle += int(f["idle"])
			for k in f["serve"]:
				serve[k] = int(serve.get(k, 0)) + int(f["serve"][k])
			var cost := wk_cost_pp * Families.people(f)
			if float(f["purse"]) < 10.0:
				broke += 1
			if float(f["purse"]) < cost:
				cant_week += 1
			if f.has("inc"):
				inc_sum += float(f["inc"])
				if float(f["inc"]) < cost:
					inc_lt += 1
		if per_town and (s < 0 or s % 2 == 1 or s < 8):
			var c := People.census(e)
			print("    %-14s %-8s sz%d pop %4d ad %3d fam %3d hungry %3d | gr %.2f fr %.2f mt %.2f | stock g%5d f%4d m%4d barn g%6d f%5d m%4d hh %5d gran %5d | short %.2f | tre %6d mkt %6d | worked %.2f est %d ac" % [
				t["name"], e["climate"], int(t["size"]), int(e["pop"]), int(e["adults"]), tfam, th,
				float(e["price"]["grain"]), float(e["price"]["fruit"]), float(e["price"]["meat"]),
				int(e["stock"].get("grain", 0)), int(e["stock"].get("fruit", 0)), int(e["stock"].get("meat", 0)),
				int(e["barn"].get("grain", 0)), int(e["barn"].get("fruit", 0)), int(e["barn"].get("meat", 0)),
				int(e["hh"].get("grain", 0)) + int(e["hh"].get("fruit", 0)) + int(e["hh"].get("meat", 0)), int(e["granary"]),
				float(e.get("food_short", 0.0)), int(e["treasury"]), int(e["biz"][int(e["mkt"])]["till"]),
				float(_wk(e)), Families.acres(e["fams"][0])])
	var fac := []
	var men := 0
	for fid in w["factions"]:
		var f: Dictionary = w["factions"][fid]
		var m := Army.members(Game, fid).size()
		men += m
		if m > 0 or float(f.get("treasury", 0.0)) > 1.0:
			fac.append("%s %d (%d men, bill %d/d)" % [fid.substr(0, 8), int(float(f.get("treasury", 0.0))), m, int(Army.bill(Game, fid))])
	var st: Dictionary = w.get("diplo", {}).get("stats", {})
	var p := float(maxi(1, pop))
	var label := "START" if s < 0 else "Y%d %s" % [s / 4 + 1, Calendar.SEASONS[s % 4]]
	print("== %s  pop %d (adults %d), fams %d, hungry %d, homeless %d (shelter %d)" % [label, pop, ad, fams, hungry, homeless, shel])
	print("   food held: stock %s barn %s hh %s granary %d (= %.1f days for pop)" % [str(stock), str(barn), str(hh), gran,
		(float(stock.values().reduce(func(a, b): return a + b, 0)) + float(barn.values().reduce(func(a, b): return a + b, 0)) + float(hh.values().reduce(func(a, b): return a + b, 0)) + gran) / (2.0 * p)])
	var dm := {}; var hu := {}
	for tid in ids:
		var e: Dictionary = w["towns"][tid]["econ"]
		var u := TownEcon.household_use(e, Calendar.season_index(Game.day))
		for g in ["grain", "fruit", "meat", "beer"]:
			dm[g] = float(dm.get(g, 0.0)) + float(e["dem"].get(g, 0.0))
			hu[g] = float(hu.get(g, 0.0)) + float(u.get(g, 0.0))
	var dl := []
	for g in dm:
		dl.append("%s %.0f/%.0f (x%.1f)" % [g, dm[g], hu[g], float(dm[g]) / maxf(1.0, float(hu[g]))])
	print("   price demand (smoothed orders/day) vs households' daily use: " + ", ".join(PackedStringArray(dl)))
	print("   prices (pop-weighted): grain %.2f fruit %.2f meat %.2f (base .5/.6/1.2); week of food per person %.1f gold" % [pg / p, pf / p, pm / p, 14.0 * (0.65 * pg + 0.15 * pf + 0.2 * pm) / p])
	print("   purses %d (%.1f/fam), broke(<10) %d, purse < a week of food %d, weekly income < week of food %d (avg inc %.1f/wk), debt %d" % [
		int(purse), purse / maxf(1, fams), broke, cant_week, inc_lt, inc_sum / maxf(1, fams), int(debt)])
	print("   labour: adults %d, on own land %d, idle %d, serving %s; land worked %.0f/%.0f acres (%.0f%%), estate holds %d acres with %d hands" % [
		ad, hands, idle, str(serve), land_w, land_t, 100.0 * land_w / maxf(1, land_t), est_acres, est_workers])
	print("   jobs: %s" % str(jobs))
	print("   gold: treasuries %d, purses %d, tills %d, farm_till %d, gold_gone %d; factions: %s" % [int(tre), int(purse), int(tills), int(farm_till), int(TownEcon.gold_gone), ", ".join(PackedStringArray(fac))])
	print("   war: wars %d peaces %d, field men %d" % [int(st.get("wars", 0)), int(st.get("peaces", 0)), men])
	if s < 0:
		return
	var bj: Dictionary = acc["by_job"]
	var lines := []
	var tot := {}
	for k in bj:
		var r: Dictionary = bj[k]
		for kk in r:
			tot[kk] = float(tot.get(kk, 0.0)) + float(r[kk])
		var parts := []
		for kk in ["made", "used", "spoil", "hold", "army_st", "tre", "fac", "mkt", "pop", "deaths", "lefth", "births"]:
			if absf(float(r.get(kk, 0.0))) >= 0.5:
				parts.append("%s %+d" % [kk, int(r[kk])])
		if not parts.is_empty():
			lines.append("      %-10s %s" % [k, " ".join(PackedStringArray(parts))])
	print("   season flows by job (food in meals):")
	for l in lines:
		print(l)
	print("   season food: made %d, used %d, spoiled %d (need of pop %d); militia paid %d of bill %d; shelter %d; avg town food_short %.2f" % [
		int(tot.get("made", 0)), int(tot.get("used", 0)), int(tot.get("spoil", 0)), int(p * 2.0 * 30.0), int(acc["mil_paid"]), int(acc["mil_bill"]), int(acc["shel_cost"]),
		float(acc["fs_sum"]) / maxf(1, acc["fs_n"])])
	print("   restock: %d family turns wanted food; purse (+last week's income) < 7 days of food %d, < the fill %d; stalls thin (< 5 families' fill) %d" % [
		fam_acc["want"], fam_acc["cant_afford_week"], fam_acc["cant_afford_fill"], fam_acc["stall_thin"]])
	var l1 := _led_by_good(w)
	var parts2 := []
	for k in l1:
		var dv := int(l1[k]) - int(led0.get(k, 0))
		if dv != 0:
			parts2.append("%s %d" % [k, dv])
	print("   ledger by good: " + ", ".join(PackedStringArray(parts2)))
	print("   family turns %d: hungry by own store %d, hungry ONLY by the town-wide food_short flag %d (turns with flag %d), homeless hungry %d" % [
		fam_acc["turns"], fam_acc["hungry_own"], fam_acc["hungry_flag_only"], fam_acc["flag_turns"], fam_acc["hungry_homeless"]])

func _led_by_good(w: Dictionary) -> Dictionary:
	var out := {}
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		for kind in ["made", "used", "spoil"]:
			for g in ["grain", "fruit", "meat", "beer", "wine"]:
				var k: String = kind + "_" + g
				out[k] = int(out.get(k, 0)) + int(e["led"][kind].get(g, 0))
	return out

func _wk(e: Dictionary) -> float:
	var t := 0.0; var wv := 0.0
	for c in e["land"]:
		t += float(e["land"][c]); wv += float(e["wacres"].get(c, 0.0))
	return wv / maxf(1.0, t)
