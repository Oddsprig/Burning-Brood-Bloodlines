extends RefCounted
## DIAGNOSTIC (not a regression test): what a world of each size costs (Douglas 12:27, "a large battlebrothers map,
## minimum"; 12:28, "it needs to run on a phone - think of what a google 10 can handle").
##   DIAG_SIZE  normal | large | huge (default normal)     DIAG_SEED (default 2026)
##   DIAG_YEARS years before to run (1-100, default CampaignWorld.PRESIM_YEARS); DIAG_DAYS days instead (overrides)
##   DIAG_REPORT_YEARS every this many years (default 5): people, coin (the coin ledger's drift), staple grain
##              price, the census balance (births - deaths + arrived - left = the change), memory, save size, and
##              the record sizes that could grow (gone family rows, their person records, family and town histories)
##   DIAG_FRAMES map frames to run after it at x1 and at x4 (default 3000 each; 0 skips them)
## The long-history check (Douglas 12:55, up to 100 years): DIAG_SIZE=normal DIAG_YEARS=20 (then 100), alone.
## Prints: map, towns by size, people; world gen ms; the years before (mean and worst day, wall); map frames
## (on_time per frame at x1 and x4: mean, worst, the work queue); memory (static, after gen and after the years);
## save size and time; the map screen's terrain layer build; a long path; roads reaching every town.
## Run alone (timings): TEST_TIMEOUT=1500 tools/test.sh tests/diag_world_size.gd

func _mem_mb() -> float:
	return Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0

func run(_tree: SceneTree) -> int:
	var size := OS.get_environment("DIAG_SIZE") if OS.get_environment("DIAG_SIZE") != "" else "normal"
	var seed_v := int(OS.get_environment("DIAG_SEED")) if OS.get_environment("DIAG_SEED") != "" else 2026
	var frames := int(OS.get_environment("DIAG_FRAMES")) if OS.get_environment("DIAG_FRAMES") != "" else 3000
	WorldGen.gen_size = size
	var m0 := _mem_mb()
	var t0 := Time.get_ticks_msec()
	Game.new_game(seed_v)
	var gen_ms := Time.get_ticks_msec() - t0
	var w: Dictionary = Game.world
	var days := CampaignWorld.presim_days(int(OS.get_environment("DIAG_YEARS"))) if OS.get_environment("DIAG_YEARS") != "" else CampaignWorld.presim_total(Game)
	if OS.get_environment("DIAG_DAYS") != "":
		days = int(OS.get_environment("DIAG_DAYS"))
	var rep_days := 4 * Calendar.DAYS_PER_SEASON * (int(OS.get_environment("DIAG_REPORT_YEARS")) if OS.get_environment("DIAG_REPORT_YEARS") != "" else 5)
	var c_start := _census_cum(w)
	var m1 := _mem_mb()
	print("SIZE %s: %d x %d cells = %d x %d px; towns %d; world gen %d ms; memory %.0f MB -> %.0f MB" % [size, WorldGen.W, WorldGen.H,
		WorldGen.W * WorldGen.CELL, WorldGen.H * WorldGen.CELL, w["towns"].size(), gen_ms, m0, m1])
	_census(w, "at world gen")
	_roads(w)
	_paths(w)
	# ------------------------------------------------------------------ the years before
	w["presim"] = {"total": days, "done": 0, "from": Game.day}
	var worst := 0; var tot := 0
	var worst_day := 0
	var profile := OS.get_environment("DIAG_PROFILE") != ""   # where the years before spend their time (adds timer calls)
	CampaignWorld.job_total = {}; CampaignWorld.job_worst = {}; CampaignWorld.steps_total = 0; CampaignWorld.step_parts = {}
	CampaignWorld.daily_total = {}
	TownEcon.prof = {}; TownEcon.prof_on = profile
	Sickness.prof = {}; Sickness.prof_parts = profile; Sickness.prof_on = profile
	t0 = Time.get_ticks_msec()
	for d in days:
		var f0 := Time.get_ticks_usec()
		CampaignWorld.presim_step(Game, 1)
		var us := Time.get_ticks_usec() - f0
		tot += us
		if us > worst:
			worst = us; worst_day = d + 1
		if (d + 1) % 120 == 0:
			print("  year %d: %.1f s so far, %d people, memory %.0f MB" % [(d + 1) / 120, (Time.get_ticks_msec() - t0) / 1000.0, _people(w), _mem_mb()])
		if (d + 1) % rep_days == 0:
			_long_report(w, (d + 1) / 120, c_start)
	var pre_ms := Time.get_ticks_msec() - t0
	CampaignWorld.presim_finish(Game, pre_ms)
	print("PRESIM %s: %d days in %.1f s; mean day %.1f ms, worst day %.1f ms (day %d)" % [size, days, pre_ms / 1000.0,
		float(tot) / maxi(1, days) / 1000.0, worst / 1000.0, worst_day])
	_presim_profile(pre_ms)
	TownEcon.prof_on = false; Sickness.prof_parts = false; Sickness.prof_on = false
	var m2 := _mem_mb()
	_census(w, "after the years before")
	# ------------------------------------------------------------------ map frames
	if frames > 0:
		for spd in [1, 4]:
			_frames(w, spd, frames)
	# ------------------------------------------------------------------ save
	t0 = Time.get_ticks_msec()
	Game.save_game()
	var save_ms := Time.get_ticks_msec() - t0
	var sz := FileAccess.open(Game.SAVE_PATH, FileAccess.READ).get_length()
	t0 = Time.get_ticks_msec()
	Game.load_game()
	var load_ms := Time.get_ticks_msec() - t0
	print("SAVE %s: %.1f MB, save %d ms, load %d ms" % [size, sz / 1048576.0, save_ms, load_ms])
	print("MEMORY %s: %.0f MB static before gen, %.0f after gen, %.0f after the years before, %.0f after load" % [size, m0, m1, m2, _mem_mb()])
	# ------------------------------------------------------------------ the map screen's static layer
	t0 = Time.get_ticks_msec()
	var terr: Node2D = Node2D.new()
	terr.set_script(load("res://campaign/map_terrain.gd"))
	terr.setup(Game.world)
	var tms := Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	var terr2: Node2D = Node2D.new()
	terr2.set_script(load("res://campaign/map_terrain.gd"))
	terr2.setup(Game.world)
	print("MAP LAYER %s: first build %d ms, again (back from a town) %d ms, %d decor pieces in %d chunks" % [size, tms,
		Time.get_ticks_msec() - t0, terr.decor_count(), terr.chunk_count()])
	terr.free(); terr2.free()
	return 0

## The census since world gen, kept by this diagnostic from each season's row as it appears (a town keeps only
## its newest Census.ROWS_MAX rows, 10 years, so a long run cannot sum them at the end) plus the season so far.
var _seen := {}   # tid -> {stamp: true}
var _sum := {"births": 0, "deaths": 0, "arrived": 0, "left": 0}

func _census_cum(w: Dictionary) -> Dictionary:
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		if not _seen.has(tid):
			_seen[tid] = {}
		for r in Census.rows(e):
			var s := int(r["stamp"])
			if _seen[tid].has(s):
				continue
			_seen[tid][s] = true
			_sum["births"] += int(r["births"]); _sum["deaths"] += Census.sum(r["deaths"])
			_sum["arrived"] += Census.sum(r["arrived"]); _sum["left"] += Census.sum(r["left"])
	var out := _sum.duplicate()
	var people := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var c: Dictionary = Census.current(t["econ"])
		out["births"] += int(c["births"]); out["deaths"] += Census.sum(c["deaths"])
		out["arrived"] += Census.sum(c["arrived"]); out["left"] += Census.sum(c["left"])
		people += Census.people(t["econ"])
	out["people"] = people
	return out

## Every DIAG_REPORT_YEARS: people, coin, grain, the census balance since world gen, memory, save size, records.
func _long_report(w: Dictionary, year: int, c0: Dictionary) -> void:
	var c := _census_cum(w)
	var bal := int(c["births"]) - int(c["deaths"]) + int(c["arrived"]) - int(c["left"])
	var chg := int(c["people"]) - int(c0["people"])
	var coin := Barge.holdings(Game)
	var drift := 0.0
	if w.has("coin"):
		var L: Dictionary = w["coin"]
		drift = coin - (float(L["cast"]) - float(L["melted"]) - float(L["drained"]))
	var gp := 0.0; var pop := 0.0
	var gone := 0; var gone_pp := 0; var live := 0; var dp := 0; var fh := 0; var th := 0; var life := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		gp += float(e["price"]["grain"]) * float(e["pop"]); pop += float(e["pop"])
		th += (e.get("hist", []) as Array).size()
		for f in e["fams"]:
			fh += (f.get("hist", []) as Array).size()
			dp += (f.get("dp", []) as Array).size()
			if f.get("gone", false):
				gone += 1
				gone_pp += (f.get("pp", []) as Array).size() + (f.get("kp", []) as Array).size()
			else:
				live += 1
			for p in f.get("pp", []):
				if p.size() > Persons.HIST:
					life += (p[Persons.HIST] as Array).size()
	var sz := -1
	var tmp := Game.SAVE_PATH
	Game.save_game()
	var fa := FileAccess.open(tmp, FileAccess.READ)
	if fa != null:
		sz = fa.get_length()
	print("LONG year %d: people %d (at gen %d); census since gen births %d - deaths %d + arrived %d - left %d = %d vs change %d: %s" % [
		year, int(c["people"]), int(c0["people"]), int(c["births"]), int(c["deaths"]), int(c["arrived"]), int(c["left"]), bal, chg,
		"adds up" if bal == chg else "DOES NOT ADD UP"])
	print("     coin %.0f (ledger drift %.0f), grain %.2f a unit (pop-weighted), memory %.0f MB, save %.2f MB" % [
		coin, drift, gp / maxf(1.0, pop), _mem_mb(), sz / 1048576.0])
	print("     records: families %d live, %d gone rows (%d person records in them); dead remembered %d; family history lines %d, town %d; life-history entries %d" % [
		live, gone, gone_pp, dp, fh, th, life])
## Where the years before went: work jobs by kind (total s, runs, mean and worst ms), the sub-steps (movement, clashes,
## war AI, tracks), the midnight parts; with DIAG_PROFILE set also the parts inside the jobs (TownEcon.prof, Sickness).
func _presim_profile(pre_ms: int) -> void:
	var jt: Dictionary = CampaignWorld.job_total
	var ks := jt.keys()
	ks.sort_custom(func(a, b): return int(jt[a][0]) > int(jt[b][0]))
	var sum := 0
	for k in ks:
		sum += int(jt[k][0])
	print("  JOBS in the years before: %.1f s of %.1f s" % [sum / 1e6, pre_ms / 1000.0])
	for k in ks:
		print("    %-12s %7.2f s  %7d runs  mean %6.2f ms  worst %6.1f ms" % [k, int(jt[k][0]) / 1e6, int(jt[k][1]),
			float(jt[k][0]) / maxi(1, int(jt[k][1])) / 1000.0, int(CampaignWorld.job_worst.get(k, 0)) / 1000.0])
	var sp := []
	for k in CampaignWorld.step_parts:
		sp.append("%s %.2f s" % [k, int(CampaignWorld.step_parts[k]) / 1e6])
	print("  STEPS (movement etc.): %.2f s: %s" % [CampaignWorld.steps_total / 1e6, ", ".join(PackedStringArray(sp))])
	var dp := []
	for k in CampaignWorld.daily_total:
		dp.append("%s %.2f s" % [k, int(CampaignWorld.daily_total[k]) / 1e6])
	print("  MIDNIGHT parts: %s" % ", ".join(PackedStringArray(dp)))
	for pr in [["TownEcon", TownEcon.prof], ["Sickness", Sickness.prof]]:
		var d: Dictionary = pr[1]
		if d.is_empty():
			continue
		var pk := d.keys()
		pk.sort_custom(func(a, b): return int(d[a]) > int(d[b]))
		var parts := []
		for k in pk:
			parts.append("%s %.2f" % [k, int(d[k]) / 1e6])
		print("  PARTS %s (s): %s" % [pr[0], ", ".join(PackedStringArray(parts))])

func _people(w: Dictionary) -> int:
	var n := 0
	for tid in w["towns"]:
		if TownEcon.has_econ(w["towns"][tid]):
			n += Census.people(w["towns"][tid]["econ"])
	return n

func _census(w: Dictionary, when: String) -> void:
	var by := [0, 0, 0, 0, 0]
	var fams := 0
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		by[clampi(int(t["size"]), 0, 4)] += 1
		if TownEcon.has_econ(t):
			fams += (t["econ"]["fams"] as Array).size()
	var kinds := {}
	for wid in w["warbands"]:
		var k := String(w["warbands"][wid]["kind"])
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("  %s: %d people in %d family rows; towns by size (hamlet, village, town, large town, city) %s; forces %d %s; lairs %d" % [
		when, _people(w), fams, by, w["warbands"].size(), kinds, w.get("lairs", {}).size()])

## Every town reachable from the first by road links.
func _roads(w: Dictionary) -> void:
	var ids: Array = w["towns"].keys()
	var seen := {ids[0]: true}
	var q := [ids[0]]
	while not q.is_empty():
		var t: String = q.pop_back()
		for l in w["towns"][t].get("road_links", []):
			if not seen.has(l["id"]):
				seen[l["id"]] = true
				q.append(l["id"])
	var deg := 0
	for tid in ids:
		deg += (w["towns"][tid].get("road_links", []) as Array).size()
	print("  roads: %d, towns reached by road %d of %d, mean links a town %.1f" % [(w["roads"] as Array).size(), seen.size(), ids.size(), float(deg) / ids.size()])

## The longest town-to-town march and a corner-to-corner path: length, days on foot, ms.
func _paths(w: Dictionary) -> void:
	var a := Vector2(WorldGen.CELL * 4, WorldGen.CELL * 4)
	var b := WorldGen.map_px() - a
	var t0 := Time.get_ticks_usec()
	var p := CampaignWorld.find_path(w, a, b)
	var us := Time.get_ticks_usec() - t0
	var t1 := Time.get_ticks_usec()
	var g := WarAI.grid_path(w, a, b)
	var us2 := Time.get_ticks_usec() - t1
	var ids: Array = w["towns"].keys()
	var far := 0.0; var fa := ""; var fb := ""
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d: float = (w["towns"][ids[i]]["pos"] as Vector2).distance_to(w["towns"][ids[j]]["pos"])
			if d > far:
				far = d; fa = ids[i]; fb = ids[j]
	var t2 := Time.get_ticks_usec()
	var fp := CampaignWorld.find_path(w, w["towns"][fa]["pos"], w["towns"][fb]["pos"])
	var us3 := Time.get_ticks_usec() - t2
	var plen := CampaignWorld.path_length(w["towns"][fa]["pos"], fp)
	var days := 0.0
	var cur: Vector2 = w["towns"][fa]["pos"]
	for q in fp:
		var seg: float = cur.distance_to(q)
		var n := maxi(1, int(seg / 6.0))
		for i in n:
			days += (seg / n) / (CampaignWorld.PARTY_SPEED * CampaignWorld.speed_mult(w, cur.lerp(q, (i + 0.5) / n)))
		cur = q
	print("  paths: corner to corner find_path %.1f ms (%d pts), war grid_path %.1f ms; farthest towns %s-%s %.0f px apart: path %.0f px, %.1f days for the company, %.1f ms" % [
		us / 1000.0, p.size(), us2 / 1000.0, w["towns"][fa]["name"], w["towns"][fb]["name"], far, plen, days, us3 / 1000.0])

## Map frames as the map screen runs them (60 fps, SEC_PER_DAY 5 s, speed x1 / x4): on_time per frame.
func _frames(w: Dictionary, spd: int, n: int) -> void:
	var dt := 1.0 / 60.0 / 5.0 * spd
	var worst := 0; var tot := 0; var over8 := 0; var over4 := 0
	var qmax := 0
	var w0 := WarAI.usec
	var pmax := 0.0
	CampaignWorld.job_worst = {}
	CampaignWorld.steps_worst = 0
	CampaignWorld.daily_worst = 0
	CampaignWorld.daily_parts = {}
	CampaignWorld.path_worst = 0
	for i in n:
		var f0 := Time.get_ticks_usec()
		Game.advance_time(dt, false)
		var us := Time.get_ticks_usec() - f0
		tot += us
		worst = maxi(worst, us)
		if us > 8000: over8 += 1
		if us > 4000: over4 += 1
		qmax = maxi(qmax, (w.get("work", []) as Array).size())
		pmax = maxf(pmax, us)
	print("FRAMES %s x%d: %d frames (%.1f days): mean %.2f ms, worst %.2f ms, over 4 ms %d, over 8 ms %d; work queue at most %d, now %d; WarAI %.2f ms a frame" % [
		WorldGen.gen_size, spd, n, n * dt, float(tot) / n / 1000.0, worst / 1000.0, over4, over8, qmax, (w.get("work", []) as Array).size(),
		float(WarAI.usec - w0) / n / 1000.0])
	var jw: Dictionary = CampaignWorld.job_worst
	var ks := jw.keys()
	ks.sort_custom(func(a, b): return int(jw[a]) > int(jw[b]))
	var parts := []
	for k in ks.slice(0, 8):
		parts.append("%s %.1f" % [k, int(jw[k]) / 1000.0])
	print("  worst single job (ms): %s; worst movement+clashes+war AI of a frame %.1f ms; worst midnight bookkeeping %.1f ms" % [
		", ".join(PackedStringArray(parts)), CampaignWorld.steps_worst / 1000.0, CampaignWorld.daily_worst / 1000.0])
	var dp := []
	for k in CampaignWorld.daily_parts:
		dp.append("%s %.1f" % [k, int(CampaignWorld.daily_parts[k]) / 1000.0])
	print("  midnight parts, worst (ms): %s; worst find_path %.1f ms" % [", ".join(PackedStringArray(dp)), CampaignWorld.path_worst / 1000.0])
