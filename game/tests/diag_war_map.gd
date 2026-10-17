extends RefCounted
## DIAGNOSTIC (not a regression test): map size, march days between rival towns, and the years before (seed 2026)
## run sub-step by sub-step exactly as CampaignWorld.on_time(1 day, in_town) does, detecting every fight (bands
## removed or losing men), who started it (WarAI orders, contact, assault march, militia), by faction pair and year;
## wars (start, end, length); deaths by faction; pathfinding cost at 1x / 1.5x / 2x map size.
## DIAG_DAYS (default 600).

const WARAI_MODES := ["intercept", "join", "shadow", "track", "hunt"]
var ev := {}        # year -> key "type|pairA-pairB" -> [events, men]
var deaths := {}    # year -> faction -> deaths not by old age
var wars := []      # [pair, start, end, rel_end]
var open_war := {}  # pair key -> start day
var state_days := {}  # pair -> {WAR: n, HOSTILE: n, ...}
var paths := 0
var by_state := {}  # diplomatic state of the pair when a fight happened (n/a = outlaws, beasts, caravans of no pair)
var t_part := {"move": 0, "monsters": 0, "daily": 0, "jobs": 0}
var mil_lost := {}  # year -> militia men lost (their own side only)

func run(_tree: SceneTree) -> int:
	var days := int(OS.get_environment("DIAG_DAYS")) if OS.get_environment("DIAG_DAYS") != "" else CampaignWorld.presim_days(CampaignWorld.PRESIM_YEARS)
	Game.new_game(2026)
	var w: Dictionary = Game.world
	w["presim"] = {"total": days, "done": 0, "from": Game.day}
	_map(w)
	_pathcost(w)
	_fd_last = _fdeaths(w)
	var fams0 := 0
	for tid in w["towns"]:
		fams0 += (w["towns"][tid]["econ"]["fams"] as Array).size()
	var t0 := Time.get_ticks_msec()
	for d in days:
		_one_day(Game)
		w["presim"]["done"] = int(w["presim"]["done"]) + 1
		_track_wars(w, int(Game.day))
		if (d + 1) % 120 == 0:
			var pp := 0; var ad := 0
			for tid in w["towns"]:
				pp += int(w["towns"][tid]["econ"]["pop"]); ad += int(w["towns"][tid]["econ"]["adults"])
			print("  end of year %d: pop %d, adults %d" % [(d + 1) / 120, pp, ad])
	var ms := Time.get_ticks_msec() - t0
	print("SIM %d days in %.1f s (%.1f ms/day): move+clash+WarAI %.1f s, monsters/militia %.1f s, daily %.1f s, jobs %.1f s; paths found ~%d (%.1f/day)" % [
		days, ms / 1000.0, float(ms) / days, t_part["move"] / 1e6, t_part["monsters"] / 1e6, t_part["daily"] / 1e6, t_part["jobs"] / 1e6, paths, float(paths) / days])
	_report(w)
	var fams1 := 0
	for tid in w["towns"]:
		fams1 += (w["towns"][tid]["econ"]["fams"] as Array).size()
	print("FAMILY ROWS made up during the run (no one to draw: Army._new_family): %d" % (fams1 - fams0))
	return 0

# ---------------------------------------------------------------- map
func _march_days(w: Dictionary, a: Vector2, b: Vector2) -> Array:
	var p := CampaignWorld.find_path(w, a, b)
	if p.is_empty():
		return [INF, INF]
	var len := 0.0; var tdays := 0.0
	var cur := a
	for q in p:
		var seg: float = cur.distance_to(q)
		var n := maxi(1, int(seg / 6.0))
		for i in n:
			var pt := cur.lerp(q, (i + 0.5) / n)
			tdays += (seg / n) / (CampaignWorld.WARBAND_SPEED * CampaignWorld.speed_mult(w, pt))
		len += seg
		cur = q
	return [len, tdays]

func _map(w: Dictionary) -> void:
	print("MAP %d x %d cells, %d px/cell = %d x %d px; towns %d; band speed %d px/day grass (x0.6 forest/hills, x1.5 road)" % [
		WorldGen.W, WorldGen.H, WorldGen.CELL, WorldGen.W * WorldGen.CELL, WorldGen.H * WorldGen.CELL, w["towns"].size(), int(CampaignWorld.WARBAND_SPEED)])
	var byf := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		if not byf.has(t["faction"]):
			byf[t["faction"]] = []
		byf[t["faction"]].append(t)
	for f in byf:
		var names := []
		for t in byf[f]:
			names.append("%s%s(sz%d)" % [t["name"], "*" if t["capital"] else "", int(t["size"])])
		print("  %s: %s" % [f, ", ".join(PackedStringArray(names))])
	var fl: Array = byf.keys(); fl.sort()
	var dp: Dictionary = w["diplo"]
	print("  pair: nearest towns straight px / path px / march days | capitals straight / path / days | start state (rel, baseline)")
	for i in fl.size():
		for j in range(i + 1, fl.size()):
			var a: String = fl[i]; var b: String = fl[j]
			var best := []; var bd := INF
			for ta in byf[a]:
				for tb in byf[b]:
					var dd: float = (ta["pos"] as Vector2).distance_to(tb["pos"])
					if dd < bd:
						bd = dd; best = [ta, tb]
			var m := _march_days(w, best[0]["pos"], best[1]["pos"])
			var ca: Dictionary = byf[a].filter(func(t): return t["capital"])[0]
			var cb: Dictionary = byf[b].filter(func(t): return t["capital"])[0]
			var mc := _march_days(w, ca["pos"], cb["pos"])
			var p: Dictionary = dp["pairs"][Diplomacy.pair_key(a, b)]
			print("    %-30s %4d / %4d / %.1f d (%s-%s) | %4d / %4d / %.1f d | %s (%d, %d)" % [a + "-" + b, int(bd), int(m[0]), m[1], best[0]["name"], best[1]["name"],
				int((ca["pos"] as Vector2).distance_to(cb["pos"])), int(mc[0]), mc[1], p["state"], int(p["rel"]), int(p["base"])])

## A* cost at 1x, 1.5x, 2x: the same terrain upscaled (nearest cell), same weights, corner-to-corner-ish paths.
func _pathcost(w: Dictionary) -> void:
	var terr: String = w["terrain"]; var road: String = w["road"]
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	for k in [1.0, 1.5, 2.0]:
		var W2 := int(WorldGen.W * k); var H2 := int(WorldGen.H * k)
		var a := AStarGrid2D.new()
		a.region = Rect2i(0, 0, W2, H2)
		a.cell_size = Vector2(WorldGen.CELL, WorldGen.CELL)
		a.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		a.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
		a.update()
		var open := []
		for y in H2:
			for x in W2:
				var i := WorldGen.idx(int(x / k), int(y / k))
				var sp: float = WorldGen.TERRAIN_SPEED.get(terr[i], 0.0)
				if sp <= 0.0:
					a.set_point_solid(Vector2i(x, y), true)
					continue
				if road[i] == "1":
					sp *= WorldGen.ROAD_SPEED
				a.set_point_weight_scale(Vector2i(x, y), 1.0 / sp)
				open.append(Vector2i(x, y))
		var n := 0; var us := 0; var far := 0; var us_far := 0; var nf := 0
		for r in 300:
			var p0: Vector2i = open[rng.randi() % open.size()]
			var p1: Vector2i = open[rng.randi() % open.size()]
			var t0 := Time.get_ticks_usec()
			var pts := a.get_point_path(p0, p1)
			var dt := Time.get_ticks_usec() - t0
			if pts.is_empty():
				continue
			n += 1; us += dt
			if Vector2(p0).distance_to(Vector2(p1)) > 0.5 * W2:
				nf += 1; us_far += dt
		print("PATHS %.1fx (%dx%d cells): %.2f ms per random path, %.2f ms per path across half the map or more (%d paths)" % [k, W2, H2, us / 1000.0 / maxf(1, n), us_far / 1000.0 / maxf(1, nf), n])

# ---------------------------------------------------------------- the day
func _bands(w: Dictionary) -> Dictionary:
	var out := {}
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		var alive := 0
		for u in wb["units"]:
			if not u.dead:
				alive += 1
		out[wid] = {"f": String(wb["faction"]), "kind": String(wb["kind"]), "n": alive, "pos": wb["pos"],
			"m": String(wb.get("war", {}).get("m", "")), "wa": bool(wb.get("war_assault", false)), "path": wb.get("path", []),
			"tgt_town": String(wb.get("target_town", ""))}
	return out

func _one_day(game) -> void:
	game.day += 1.0
	var w: Dictionary = game.world
	var rng := CampaignWorld._rng(w)
	var dd := 1.0
	var steps := maxi(1, ceili(dd / CampaignWorld.STEP))
	var dt := dd / steps
	var t0: float = game.day - dd
	for i in steps:
		var t := t0 + dt * (i + 1)
		var b0 := _bands(w)
		var c0 := Time.get_ticks_usec()
		WarAI.tick(game, t, dt)
		CampaignWorld._move_warbands(game, dt, t, rng)
		CampaignWorld._warband_clashes(game, t, rng)
		Tracks.step(game, t)
		t_part["move"] += Time.get_ticks_usec() - c0
		_diff(w, b0, _bands(w), "field")
	var b1 := _bands(w)
	var c1 := Time.get_ticks_usec()
	Monsters.on_time(game, dd)
	t_part["monsters"] += Time.get_ticks_usec() - c1
	_diff(w, b1, _bands(w), "monsters")
	var whole := int(floor(game.day))
	var c2 := Time.get_ticks_usec()
	while int(w.get("last_day", 0)) < whole:
		w["last_day"] = int(w.get("last_day", 0)) + 1
		CampaignWorld._daily(game, int(w["last_day"]), rng)
	t_part["daily"] += Time.get_ticks_usec() - c2
	var c3 := Time.get_ticks_usec()
	while not (w.get("work", []) as Array).is_empty():
		var k := String(w["work"][0][0])
		var d0 := _fdeaths(w) if k == "fam" else {}
		CampaignWorld._do_work(game, rng)
		if k == "fam":   # old age (and hunger-era deaths at the family turn): not war deaths
			var d1 := _fdeaths(w)
			for f in d1:
				_add_death(f, -(int(d1[f]) - int(d0.get(f, 0))))
	t_part["jobs"] += Time.get_ticks_usec() - c3
	var dend := _fdeaths(w)
	for f in dend:
		_add_death(f, int(dend[f]) - int(_fd_last.get(f, dend[f])))
	_fd_last = dend
	w["rng_state"] = str(rng.state)
	w["encounter"] = ""

var _fd_last := {}
func _fdeaths(w: Dictionary) -> Dictionary:
	var out := {}
	for tid in w["towns"]:
		var t: Dictionary = w["towns"][tid]
		out[t["faction"]] = int(out.get(t["faction"], 0)) + int(t["econ"]["stats"].get("deaths", 0))
	return out

func _add_death(f: String, n: int) -> void:
	if n == 0:
		return
	var y := _year()
	if not deaths.has(y):
		deaths[y] = {}
	deaths[y][f] = int(deaths[y].get(f, 0)) + n

func _year() -> int:
	return int((Game.day - 1.0) / 120.0) + 1

func _tally(kind: String, fa: String, fb: String, men: int) -> void:
	var y := _year()
	if not ev.has(y):
		ev[y] = {}
	var pr := [fa, fb]; pr.sort()
	var key := "%s|%s-%s" % [kind, pr[0], pr[1]]
	var r: Array = ev[y].get(key, [0, 0])
	r[0] += 1; r[1] += men
	ev[y][key] = r

## Bands removed or short of men between two snapshots: one fight per beaten/losing band, the opponent the nearest
## band it fights (militia within its radius). Also deaths outside jobs (militia, clashes) by town faction.
func _diff(w: Dictionary, a: Dictionary, b: Dictionary, where: String) -> void:
	for wid in b:
		if a.has(wid) and not is_same(a[wid]["path"], b[wid]["path"]) and not (b[wid]["path"] as Array).is_empty():
			paths += 1
	var seen := {}
	for wid in a:
		var was: Dictionary = a[wid]
		var now_n := int(b[wid]["n"]) if b.has(wid) else 0
		var lost := int(was["n"]) - now_n
		if was["kind"] == "militia" and lost > 0:
			mil_lost[_year()] = int(mil_lost.get(_year(), 0)) + lost   # the militia's own men off the field
		# assault arrival: war_assault flag dropped
		if was["wa"] and (not b.has(wid) or not b[wid]["wa"]):
			var town: Dictionary = w["towns"].get(was["tgt_town"], {})
			if not town.is_empty() and (was["pos"] as Vector2).distance_to(town["pos"]) < 60.0:
				_tally("assault-arrives", was["f"], String(town["faction"]), maxi(0, lost))
				seen[wid] = true
				continue
		if lost <= 0 or seen.has(wid) or was["kind"] == "caravan" and b.has(wid):
			continue
		if not b.has(wid) and lost == 0:
			continue
		# opponent: nearest other band that fights it
		var best := ""; var bd := INF
		for oid in a:
			if oid == wid:
				continue
			var o: Dictionary = a[oid]
			if o["f"] == was["f"]:
				continue
			var dd: float = (o["pos"] as Vector2).distance_to(was["pos"])
			var reach := 130.0 if (o["kind"] == "militia" or was["kind"] == "militia") else 60.0
			if dd < reach and dd < bd:
				bd = dd; best = oid
		if best == "":
			continue   # deserted, disbanded, starved: not a fight
		var o2: Dictionary = a[best]
		var olost := int(o2["n"]) - (int(b[best]["n"]) if b.has(best) else 0)
		seen[wid] = true; seen[best] = true
		var kind := "contact"
		if was["kind"] == "caravan" or o2["kind"] == "caravan":
			kind = "caravan-raid"
		elif was["kind"] == "militia" or o2["kind"] == "militia":
			kind = "militia" + ("-caughtByWarAI" if (String(was["m"]) in WARAI_MODES or String(o2["m"]) in WARAI_MODES) else "")
		elif String(was["m"]) in WARAI_MODES or String(o2["m"]) in WARAI_MODES:
			kind = "warai-" + (String(was["m"]) if String(was["m"]) in WARAI_MODES else String(o2["m"]))
		elif was["kind"] == "assault" or o2["kind"] == "assault" or was["wa"] or o2["wa"]:
			kind = "assault-band-met"
		_tally(kind, was["f"], o2["f"], lost + maxi(0, olost))
		var stt := "n/a"
		if (w["diplo"]["pairs"] as Dictionary).has(Diplomacy.pair_key(was["f"], o2["f"])):
			stt = String(w["diplo"]["pairs"][Diplomacy.pair_key(was["f"], o2["f"])]["state"])
		var r: Array = by_state.get(stt, [0, 0])
		r[0] += 1; r[1] += lost + maxi(0, olost)
		by_state[stt] = r

func _track_wars(w: Dictionary, d: int) -> void:
	var dp: Dictionary = w["diplo"]
	for k in dp["pairs"]:
		var p: Dictionary = dp["pairs"][k]
		if not state_days.has(k):
			state_days[k] = {}
		state_days[k][p["state"]] = int(state_days[k].get(p["state"], 0)) + 1
		if p["state"] == Diplomacy.WAR and not open_war.has(k):
			open_war[k] = d
		elif p["state"] != Diplomacy.WAR and open_war.has(k):
			wars.append([k, int(open_war[k]), d, float(p["rel"])])
			open_war.erase(k)

# ---------------------------------------------------------------- report
func _report(w: Dictionary) -> void:
	print("FIGHTS by year (events / men off the field = dead + fled, both sides):")
	var types := {}
	for y in ev.keys():
		var keys: Array = ev[y].keys(); keys.sort()
		var tot := [0, 0]
		print("  year %d:" % y)
		var bytype := {}
		var bypair := {}
		for k in keys:
			var r: Array = ev[y][k]
			var parts: PackedStringArray = String(k).split("|")
			bytype[parts[0]] = [int(bytype.get(parts[0], [0, 0])[0]) + r[0], int(bytype.get(parts[0], [0, 0])[1]) + r[1]]
			bypair[parts[1]] = [int(bypair.get(parts[1], [0, 0])[0]) + r[0], int(bypair.get(parts[1], [0, 0])[1]) + r[1]]
			tot[0] += r[0]; tot[1] += r[1]
			types[parts[0]] = [int(types.get(parts[0], [0, 0])[0]) + r[0], int(types.get(parts[0], [0, 0])[1]) + r[1]]
		print("    total %d fights, %d men; by type %s" % [tot[0], tot[1], str(bytype)])
		var pk: Array = bypair.keys(); pk.sort_custom(func(x, z): return int(bypair[x][1]) > int(bypair[z][1]))
		var pl := []
		for p in pk.slice(0, 12):
			pl.append("%s %d/%d" % [p, bypair[p][0], bypair[p][1]])
		print("    by pair (fights/men): " + ", ".join(PackedStringArray(pl)))
		if deaths.has(y):
			print("    deaths not by old age (job-side: army sweep, town sweep, casualties), by town faction: %s" % str(deaths[y]))
	print("  5-year by type: %s" % str(types))
	var ml := 0
	for y in mil_lost:
		ml += int(mil_lost[y])
	print("  militia men lost (own side, any fight): %d; by year %s" % [ml, str(mil_lost)])
	print("  fights by the pair's state at the time (fights, men): %s" % str(by_state))
	# wars
	for k in open_war:
		wars.append([k, int(open_war[k]), -1, float(w["diplo"]["pairs"][k]["rel"])])
	var durs := []
	var per := {}
	for x in wars:
		var dur := (int(x[2]) if int(x[2]) >= 0 else int(Game.day)) - int(x[1])
		durs.append(dur)
		per[x[0]] = int(per.get(x[0], 0)) + 1
	durs.sort()
	var avg := 0.0
	for x in durs:
		avg += x
	print("WARS %d (still open %d): length days min %d / median %d / mean %.1f / max %d; per pair %s" % [wars.size(), open_war.size(),
		durs[0] if not durs.is_empty() else 0, durs[durs.size() / 2] if not durs.is_empty() else 0, avg / maxf(1, durs.size()), durs[-1] if not durs.is_empty() else 0, str(per)])
	print("  every war ends the one way the code allows: relation back above -50 (weariness + drift) for 7 days, then a weekly 30% roll -> HOSTILE (which still fights on contact)")
	print("DAYS IN EACH STATE per pair over the run:")
	for k in state_days:
		print("  %-32s %s (baseline %d)" % [k, str(state_days[k]), int(w["diplo"]["pairs"][k]["base"])])
	print("diplo stats: %s" % str(w["diplo"]["stats"]))
	print("WarAI stats: %s" % str(w.get("war", {}).get("stats", {})))
