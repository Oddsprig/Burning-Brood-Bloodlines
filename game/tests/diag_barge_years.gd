extends RefCounted
## DIAGNOSTIC (not a regression test): the years before on seed 2026 (DIAG_SEED overrides), day by day exactly as
## CampaignWorld.presim_step / on_time(1 day, in_town) does, with a year-end report (every 120 days): world
## population, births, deaths by cause, leavers (and where they went), people who appeared without a birth
## (invented), land worked, day wage, staple price, hunger, coin per head, treasuries; the same per race.
## Money shows in the build's own unit (before the coinage: gold, x20 = coins). DIAG_DAYS (default the default years before, 600), or DIAG_YEARS (1-100).
## DIAG_SCALE (1, 1.5, 2) runs the larger-towns world-gen lever (barge: EconGen.TOWN_SCALE) when the build has it.

var acc := {}
var t_job := {}
var cen0 := {}   # the census totals at the last report (the year's numbers are the difference)
var cen_start := {}

## The census of the whole world, summed since world gen: every season's row plus the season so far.
## Herds (addendum 1 B, herds-2): head by kind, the plough oxen, the herd book so far, meat made and spoiled, hay meadows.
func _herd_lines(year: int) -> void:
	var w: Dictionary = Game.world
	var heads := {}; var bk := {"died": {}}
	var mk_f := 0; var sp_f := 0; var mk_m := 0; var sp_m := 0; var meadow := 0; var sick_h := 0
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid].get("econ", {})
		if not e.has("hd"):
			continue
		var th := Herds.town_heads(e)
		for k in th:
			heads[k] = int(heads.get(k, 0)) + int(th[k])
		var b := Herds.book(e, "tot")
		for k in b:
			if k == "died":
				for c in b["died"]:
					bk["died"][c] = int(bk["died"].get(c, 0)) + int(b["died"][c])
			else:
				bk[k] = int(bk.get(k, 0)) + int(b[k])
		mk_f += int(e["led"]["made"].get("fresh_meat", 0)); sp_f += int(e["led"]["spoil"].get("fresh_meat", 0))
		mk_m += int(e["led"]["made"].get("meat", 0)); sp_m += int(e["led"]["spoil"].get("meat", 0))
		meadow += int(e.get("land", {}).get("fodder", 0))
		for hid in e["hd"]["h"]:
			sick_h += int(round(Herds.sick(e["hd"]["h"][hid]) * float(Herds.head(e["hd"]["h"][hid]))))
	print("   HERDS year %d: %s (plough oxen %d, sick now %d); hay meadows %d acres" % [year, str(heads), int(heads.get("oxen", 0)), sick_h, meadow])
	print("   HERD BOOK so far: born %d, slaughtered %d, sold %d, stolen %d, died %s" % [int(bk.get("born", 0)), int(bk.get("slaughtered", 0)),
		int(bk.get("sold", 0)), int(bk.get("stolen", 0)), str(bk["died"])])
	print("   MEAT so far: fresh meat made %d, spoiled %d; keeping meat made %d, spoiled %d" % [mk_f, sp_f, mk_m, sp_m])

func _census_cum(w: Dictionary) -> Dictionary:
	var out := {"people": 0, "births": 0, "deaths": {}, "away": {}, "left": {}, "arrived": {}, "to": {}}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		out["people"] += Census.people(e)
		var rs: Array = Census.rows(e)
		var parts: Array = rs.slice(1)
		parts.append(Census.current(e))
		for r in parts:
			out["births"] += int(r["births"])
			for k in ["deaths", "away", "left", "arrived", "to"]:
				for c in r[k]:
					out[k][c] = int(out[k].get(c, 0)) + int(r[k][c])
	return out

func _cdiff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for c in a:
		var v := int(a[c]) - int(b.get(c, 0))
		if v != 0:
			out[c] = v
	return out

func _csum(d: Dictionary) -> int:
	var n := 0
	for c in d:
		n += int(d[c])
	return n

func _census_lines(w: Dictionary) -> void:
	var now := _census_cum(w)
	var dd := _cdiff(now["deaths"], cen0.get("deaths", {}))
	var la := _cdiff(now["left"], cen0.get("left", {}))
	var ar := _cdiff(now["arrived"], cen0.get("arrived", {}))
	var to := _cdiff(now["to"], cen0.get("to", {}))
	var off_map := int(to.get("-", 0))
	var to_town := _csum(to) - off_map
	print("   CENSUS year: births %d, deaths %d by cause %s (company men away %d), left %d by why %s -> to other towns %d, off the map %d; arrived %d by why %s" % [
		int(now["births"]) - int(cen0.get("births", 0)), _csum(dd), str(dd), _csum(_cdiff(now["away"], cen0.get("away", {}))),
		_csum(la), str(la), to_town, off_map, _csum(ar), str(ar)])
	var bal := int(now["births"]) - _csum(now["deaths"]) + _csum(now["arrived"]) - _csum(now["left"])
	print("   CENSUS since start: people %d -> %d (change %d); births - deaths + arrived - left = %d: %s" % [
		int(cen_start["people"]), int(now["people"]), int(now["people"]) - int(cen_start["people"]), bal,
		"adds up" if bal == int(now["people"]) - int(cen_start["people"]) else "DOES NOT ADD UP"])
	cen0 = now

func run(_tree: SceneTree) -> int:
	var days := int(OS.get_environment("DIAG_DAYS")) if OS.get_environment("DIAG_DAYS") != "" else CampaignWorld.presim_days(
		int(OS.get_environment("DIAG_YEARS")) if OS.get_environment("DIAG_YEARS") != "" else CampaignWorld.PRESIM_YEARS)
	var seed_v := int(OS.get_environment("DIAG_SEED")) if OS.get_environment("DIAG_SEED") != "" else 2026
	var scale := float(OS.get_environment("DIAG_SCALE")) if OS.get_environment("DIAG_SCALE") != "" else 1.0
	var tg0 := Time.get_ticks_msec()
	if scale != 1.0:
		EconGen.town_scale_override = scale   # world-gen lever: families and acreage per town x scale (land per head the same)
	Game.new_game(seed_v)
	var w: Dictionary = Game.world
	print("world gen %.1f s, seed %d, town scale %.2f" % [(Time.get_ticks_msec() - tg0) / 1000.0, seed_v, scale])
	w["presim"] = {"total": days, "done": 0, "from": Game.day}
	var ids: Array = w["towns"].keys()
	ids.sort()
	_reset()
	cen_start = _census_cum(w)
	cen0 = cen_start
	_report(w, ids, 0)
	var t0 := Time.get_ticks_msec()
	var worst_day := 0
	for d in days:
		var d0 := Time.get_ticks_usec()
		_one_day(Game)
		worst_day = maxi(worst_day, Time.get_ticks_usec() - d0)
		w["presim"]["done"] = int(w["presim"]["done"]) + 1
		if (d + 1) % 120 == 0:
			_report(w, ids, (d + 1) / 120)
			_reset()
	print("wall %.1f s for %d days; worst campaign day %.1f ms" % [(Time.get_ticks_msec() - t0) / 1000.0, days, worst_day / 1000.0])
	for line in Sickness.report_lines(w).slice(-6):
		print("   SICKNESS " + String(line))
	var tl := []
	for k in t_job:
		tl.append("%s %.1f s" % [k, t_job[k] / 1.0e6])
	print("time by job: " + ", ".join(PackedStringArray(tl)))
	return 0

func _reset() -> void:
	acc = {"by_job": {}}

func _one_day(game) -> void:
	game.day += 1.0
	var w: Dictionary = game.world
	var rng := CampaignWorld._rng(w)
	var t0: float = game.day - 1.0
	var steps := maxi(1, ceili(1.0 / CampaignWorld.STEP))
	var dt := 1.0 / steps
	var s0 := _snap(w)
	var tm := Time.get_ticks_usec()
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
	t_job["map+daily"] = int(t_job.get("map+daily", 0)) + Time.get_ticks_usec() - tm
	_add("map+daily", s0, _snap(w))
	while not (w.get("work", []) as Array).is_empty():
		var job: Array = w["work"][0]
		var k := String(job[0])
		var a := _snap(w)
		var tj := Time.get_ticks_usec()
		CampaignWorld._do_work(game, rng)
		t_job[k] = int(t_job.get(k, 0)) + Time.get_ticks_usec() - tj
		_add(k, a, _snap(w))
	w["rng_state"] = str(rng.state)
	w["encounter"] = ""

func _snap(w: Dictionary) -> Dictionary:
	var s := {"pop": 0, "deaths": 0, "births": 0, "left": 0, "tre": 0, "coin": 0}
	if OS.get_environment("DIAG_COIN") == "1" and w.has("coin"):
		var L: Dictionary = w["coin"]
		s["coin"] = int(round(Barge.holdings(Game) - (float(L["cast"]) - float(L["melted"]) - float(L["drained"]))))
	for tid in w["towns"]:
		var e: Dictionary = w["towns"][tid]["econ"]
		s["pop"] += int(e["pop"])
		s["tre"] += int(e["treasury"])
		var st: Dictionary = e["stats"]
		s["deaths"] += int(st.get("deaths", 0))
		s["births"] += int(st.get("births", 0))
		s["left"] += int(st.get("left", 0)) - int(st.get("moved_in", 0))   # movers between towns are not leavers of the world
	return s

func _add(k: String, a: Dictionary, b: Dictionary) -> void:
	var bj: Dictionary = acc["by_job"]
	if not bj.has(k):
		bj[k] = {}
	for key in a:
		bj[k][key] = int(bj[k].get(key, 0)) + int(b[key]) - int(a[key])

func _race(t: Dictionary) -> String:
	return String(TownEcon.culture_of(t["econ"]).get("race", "?"))

func _report(w: Dictionary, ids: Array, year: int) -> void:
	var rows := {}   # race -> sums; "ALL"
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		var e: Dictionary = t["econ"]
		for key in ["ALL", _race(t)]:
			if not rows.has(key):
				rows[key] = {"pop": 0, "towns": 0, "births": 0, "deaths": 0, "left": 0, "moved_in": 0, "land": 0.0, "worked": 0.0,
					"wage_w": 0.0, "grain_w": 0.0, "fams": 0, "hungry": 0, "coin": 0.0, "tre": 0.0, "dc": {}, "starved": 0, "famine_t": 0}
			var r: Dictionary = rows[key]
			var st: Dictionary = e["stats"]
			r["pop"] += int(e["pop"]); r["towns"] += 1
			r["births"] += int(st.get("births", 0)); r["deaths"] += int(st.get("deaths", 0))
			r["left"] += int(st.get("left", 0)); r["moved_in"] += int(st.get("moved_in", 0))
			for c in st.get("dc", {}):
				r["dc"][c] = int(r["dc"].get(c, 0)) + int(st["dc"][c])
			for c in e["land"]:
				r["land"] += float(e["land"][c]); r["worked"] += float(e["wacres"].get(c, 0.0))
			var wage := float(e.get("dwage", -1.0))
			if wage < 0.0:   # before the barge model: the hired farmhand's wage stands for the day wage
				for b in e["biz"]:
					if b["type"] == "farm":
						wage = float(b["wage"]); break
			r["wage_w"] += wage * float(e["pop"])
			r["grain_w"] += float(e["price"]["grain"]) * float(e["pop"])
			r["coin"] += TownEcon.town_gold(e)
			r["tre"] += float(e["treasury"])
			if int(e.get("fstage", 0)) >= 3:
				r["famine_t"] += 1
			var meal := float(e["price"]["grain"]) * 1.1
			for f in e["fams"]:
				if f.get("gone", false) or f.has("estate"):
					continue
				r["fams"] += 1
				if int(f["hungry"]) > 0:
					r["hungry"] += 1
					if key == "ALL":
						var wk := 14.0 * float(Families.people(f)) * meal
						r["h_broke"] = int(r.get("h_broke", 0)) + (1 if float(f["purse"]) < wk else 0)
						r["h_homeless"] = int(r.get("h_homeless", 0)) + (1 if int(f["homes"]) <= 0 else 0)
						r["h_market_empty"] = int(r.get("h_market_empty", 0)) + (1 if int(e["stock"].get("grain", 0)) < 50 else 0)
						r["h_stage"] = int(r.get("h_stage", 0)) + int(f["hungry"])
						if OS.get_environment("DIAG_HUNGRY") == "1" and int(r.get("h_shown", 0)) < 12:
							r["h_shown"] = int(r.get("h_shown", 0)) + 1
							print("     hungry: %s %s m%d f%d k%d o%d serve%d idle%d jobs%d hands%d cj%s purse %d inc %d store %.1f homes %d cls %d stage %d hst %d debt %d acres %d" % [
								t["name"], f["name"], int(f["m"]), int(f["f"]), int(f["kids"]), int(f["old"]), Families.serving(f), int(f["idle"]),
								Families.job_total(f), int(f["hands"]), str(f.get("cj", {})), int(f["purse"]), int(f.get("inc", 0)), float(f["store"]["food"]),
								int(f["homes"]), int(f.get("cls", 0)), int(f["hungry"]), int(f.get("hst", 0)), int(f["debt"]), Families.acres(f)])
	var fac_tre := 0.0; var other := 0.0
	for fid in w["factions"]:
		fac_tre += float(w["factions"][fid].get("treasury", 0.0))
		other += float(w["factions"][fid].get("loot", 0.0))
	for wid in w["warbands"]:
		other += float(w["warbands"][wid].get("gold", 0.0))
	var A: Dictionary = rows["ALL"]
	var p := float(maxi(1, int(A["pop"])))
	var label := "START" if year == 0 else "END OF YEAR %d" % year
	print("== %s  pop %d in %d towns" % [label, int(A["pop"]), int(A["towns"])])
	_herd_lines(year)
	if year > 0:
		var bj: Dictionary = acc["by_job"]
		var war := 0; var fam := 0; var other_d := 0; var invented := 0
		var jl := []
		for k in bj:
			var r: Dictionary = bj[k]
			var dd := int(r.get("deaths", 0))
			if k in ["fam"]:
				fam += dd
			elif k in ["army_sweep", "map+daily", "army", "army_misc", "army_fight"] or k.begins_with("militia") or k.begins_with("lair") or k.begins_with("camp"):
				war += dd
			else:
				other_d += dd
			var resid := int(r.get("pop", 0)) - int(r.get("births", 0)) + dd + int(r.get("left", 0))
			if resid > 0:
				invented += resid
			if dd != 0 or resid != 0 or int(r.get("births", 0)) != 0 or absi(int(r.get("tre", 0))) > 1000 or absi(int(r.get("coin", 0))) > 0:
				jl.append("%s(d%d b%d left%d +%d tre%+d coin%+d)" % [k, dd, int(r.get("births", 0)), int(r.get("left", 0)), resid, int(r.get("tre", 0)), int(r.get("coin", 0))])
		print("   year flows by job: " + " ".join(PackedStringArray(jl)))
		print("   deaths this year: at home (old age, hunger, sickness) %d, in service / war %d, other %d; people appearing without a birth %d" % [fam, war, other_d, invented])
		_census_lines(w)
	var cc := _census_cum(w)
	print("   totals since start: births %d deaths %d (census by cause %s) leavers %d (moved in %d)" % [int(A["births"]), int(A["deaths"]),
		str(_cdiff(cc["deaths"], cen_start.get("deaths", {}))), int(A["left"]), int(A["moved_in"])])
	print("   land worked %.0f%% (%.0f / %.0f acres); day wage %.1f; staple (grain meal) %.2f; hunger %.1f%% of %d households; coin per head %.0f; town treasuries %d, realm treasuries %d, chests+caravans %d; towns in famine %d" % [
		100.0 * float(A["worked"]) / maxf(1.0, float(A["land"])), float(A["worked"]), float(A["land"]), float(A["wage_w"]) / p, float(A["grain_w"]) / p,
		100.0 * float(A["hungry"]) / maxf(1.0, float(A["fams"])), int(A["fams"]), (float(A["coin"]) + fac_tre + other) / p, int(A["tre"]), int(fac_tre), int(other), int(A["famine_t"])])
	var LC: Dictionary = w.get("coin", {})
	if not LC.is_empty():
		print("   coin ledger: cast %d, melted %d, drained %d; held %d (cast - melted - drained = %d)" % [int(LC["cast"]), int(LC["melted"]), int(LC["drained"]),
			int(Barge.holdings(Game)), int(float(LC["cast"]) - float(LC["melted"]) - float(LC["drained"]))])
		var pls := []
		for fid in w["factions"]:
			if w["factions"][fid].has("pl"):
				pls.append("%s PL %.2f idx %.2f" % [String(fid).substr(0, 8), float(w["factions"][fid]["pl"]), float(w["factions"][fid].get("mindex", 1.0))])
		print("   price level: " + ", ".join(PackedStringArray(pls)))
	print("   hungry households: %d with less than a week of staple money, %d homeless, %d in towns with grain stalls near empty; mean stage %.1f" % [
		int(A.get("h_broke", 0)), int(A.get("h_homeless", 0)), int(A.get("h_market_empty", 0)), float(A.get("h_stage", 0)) / maxf(1.0, float(A["hungry"]))])
	var races: Array = rows.keys()
	races.sort()
	for k in races:
		if k == "ALL":
			continue
		var r: Dictionary = rows[k]
		var pr := float(maxi(1, int(r["pop"])))
		print("   %-9s towns %d pop %5d births %4d deaths %4d left %4d in %4d | worked %3.0f%% wage %6.1f staple %6.2f hunger %4.1f%% coin/head %7.0f treasuries %d" % [k, int(r["towns"]), int(r["pop"]),
			int(r["births"]), int(r["deaths"]), int(r["left"]), int(r["moved_in"]), 100.0 * float(r["worked"]) / maxf(1.0, float(r["land"])),
			float(r["wage_w"]) / pr, float(r["grain_w"]) / pr, 100.0 * float(r["hungry"]) / maxf(1.0, float(r["fams"])), float(r["coin"]) / pr, int(r["tre"])])
