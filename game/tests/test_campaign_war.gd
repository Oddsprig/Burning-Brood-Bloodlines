extends RefCounted
## War interception (campaign/war_ai.gd): a war band in sight of a moving enemy caravan heads for a point ahead
## on the caravan's route (lead, not pursuit) and catches it; a weaker band avoids a stronger enemy army (which
## goes for it); a band picks up fresh enemy tracks and follows them to the enemy; town word sends a band
## hunting; a band too weak alone shadows and calls its neighbours; beaten-down and unpaid bands fall back home;
## a town militia holds the walls unless it outnumbers the enemy 1.25x (war pick 3); peace, HOSTILE and ALLIANCE = no interception; the same seed
## gives the same war, and war orders survive save/load; per-frame cost of the war AI on a 40-band map with every
## realm at war < 0.1 ms mean at x1 (x4 printed).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _force(w: Dictionary, a: String, b: String, st: String, rel: float) -> void:
	var p: Dictionary = w["diplo"]["pairs"][Diplomacy.pair_key(a, b)]
	p["state"] = st
	p["rel"] = rel
	p["past"] = 0
	p["held"] = 0
	Diplomacy._sync_wars(w)

## Every pair NEUTRAL, then the given pairs at their state.
func _diplo(w: Dictionary, pairs: Array) -> void:
	for k in w["diplo"]["pairs"]:
		var p: Dictionary = w["diplo"]["pairs"][k]
		p["state"] = Diplomacy.NEUTRAL; p["rel"] = 0.0; p["past"] = 0; p["held"] = 0
	for q in pairs:
		_force(w, q[0], q[1], q[2], -80.0 if q[2] == Diplomacy.WAR else -30.0)

## Fresh world, no forces on the map but the ones a test makes; the company parked out of the way.
func _world(seed_v: int) -> Dictionary:
	Game.new_game(seed_v)
	var w: Dictionary = Game.world
	w["warbands"] = {}
	w["militia"] = {}
	w["work"] = []
	w["party"]["safe_until"] = 1.0e9
	return w

func _purge(w: Dictionary, keep: Array) -> void:
	for wid in w["warbands"].keys():
		if not keep.has(wid):
			w["warbands"].erase(wid)
	w["encounter"] = ""
	w["party"]["safe_until"] = Game.day + 100.0

func _town_of(w: Dictionary, fid: String) -> Dictionary:
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == fid:
			return w["towns"][tid]
	return {}

## Point `d` px along a path from `start`.
func _along(start: Vector2, path: Array, d: float) -> Vector2:
	var p := start
	for q in path:
		var s := p.distance_to(q)
		if s >= d:
			return p.lerp(q, d / s)
		d -= s
		p = q
	return p

func _seg_dist(x: Vector2, start: Vector2, path: Array) -> float:
	var best := INF
	var p := start
	for q in path:
		best = minf(best, Geometry2D.get_closest_point_to_segment(x, p, q).distance_to(x))
		p = q
	return best

func _caravan(w: Dictionary, fid: String, pos: Vector2, dest: Dictionary, n: int, rng: RandomNumberGenerator) -> String:
	var home := _town_of(w, fid)
	var cid := _ai_band( fid, pos, n, "caravan", rng, {"home": home["id"], "origin": home["id"],
		"dest": dest["id"], "leg": "out", "cargo": {"items": [], "goods": {}}, "gold": 0.0, "escort": "", "away": 0.0,
		"state": "travel", "depart_day": Game.day})
	var car: Dictionary = w["warbands"][cid]
	car["path"] = CampaignWorld.find_path(w, car["pos"], dest["pos"])
	return cid

func _ai_band(fid: String, pos: Vector2, count: int, kind: String, rng: RandomNumberGenerator, extra: Dictionary = {}) -> String:
	if kind != "caravan": extra["staged"] = true
	return CampaignWorld.spawn_warband(Game, fid, pos, count, kind, rng, extra)

func _think_now(wb: Dictionary) -> void:
	wb["war_next"] = 0.0

func _step(w: Dictionary, keep: Array, days: float) -> void:
	Game.advance_time(days, false)
	_purge(w, keep)

func run(tree: SceneTree) -> int:
	_intercept()
	_avoid()
	_tracks()
	_word()
	_call_and_home()
	_militia()
	_peace()
	_determinism()
	await _perf(tree)
	return fails

# ---------------------------------------------------------------- lead interception of a caravan
func _intercept() -> void:
	var w := _world(4401)
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	# a long caravan route: the two towns farthest apart that a path joins (route lengths in map units: x
	# WorldGen.K, so the 1.5x map of war pick 5 picks the same class of route as the old map did)
	var ids: Array = w["towns"].keys()
	var best := []; var bl := 0.0
	for i in ids.size():
		for j in ids.size():
			if i == j:
				continue
			var a: Vector2 = w["towns"][ids[i]]["pos"]; var b: Vector2 = w["towns"][ids[j]]["pos"]
			if a.distance_to(b) > bl and a.distance_to(b) < 1500.0 * WorldGen.K:
				var p := CampaignWorld.find_path(w, a, b)
				if not p.is_empty() and CampaignWorld.path_length(a, p) > 1100.0 * WorldGen.K:
					bl = a.distance_to(b); best = [ids[i], ids[j]]
	check(not best.is_empty(), "a long route for the caravan")
	if best.is_empty():
		return
	var origin: Vector2 = w["towns"][best[0]]["pos"]
	var cid := _caravan(w, "orc_horde", origin, w["towns"][best[1]], 2, rng)
	var car: Dictionary = w["warbands"][cid]
	var cpath: Array = (car["path"] as Array).duplicate()
	var cstart: Vector2 = car["pos"]
	# a March war band 260 px to the side of the route, 450 px ahead of the caravan
	var ahead := _along(cstart, cpath, 450.0)
	var nxt := _along(cstart, cpath, 470.0)
	var side := (nxt - ahead).normalized().orthogonal()
	var bpos := CampaignWorld.nearest_passable(w, ahead + side * 260.0)
	if not CampaignWorld.passable(w, ahead + side * 260.0):
		bpos = CampaignWorld.nearest_passable(w, ahead - side * 260.0)
	var hid := _ai_band( "middle_kingdom", bpos, 10, "patrol", rng, {"home": _town_of(w, "middle_kingdom")["id"]})
	var hb: Dictionary = w["warbands"][hid]
	# barge part 4 section 8: unpaid braves go home after 3 days: this band's realm can pay it for the test's days
	w["factions"]["middle_kingdom"]["treasury"] = maxf(float(w["factions"]["middle_kingdom"].get("treasury", 0.0)), 200000.0)
	# start the caravan so the band sees it (within SIGHT) after a short walk
	var keep := [cid, hid]
	var t_seen := -1.0
	var aim := Vector2.INF
	var lead_ahead := 0.0
	var caught := false
	var stats0 := int(WarAI.state(w)["stats"].get("caught", 0))
	for i in 250:   # up to 5 days
		_step(w, keep, 0.02)
		if not w["warbands"].has(cid):
			caught = true
			break
		var war: Dictionary = hb.get("war", {})
		if t_seen < 0.0 and String(war.get("m", "")) == "intercept" and String(war.get("tgt", "")) == cid:
			t_seen = Game.day
			# where it heads: on the caravan's route, ahead of the caravan (not at the caravan)
			var p: Array = hb["path"]
			aim = war["aim"]
			lead_ahead = (aim as Vector2).distance_to(car["pos"])
			var on_route := _seg_dist(aim, cstart, cpath)
			print("intercept (day %.2f): band at %.0f px from the caravan, aims %.0f px ahead of it, %.1f px off its route; path %d pts" % [
				Game.day, (hb["pos"] as Vector2).distance_to(car["pos"]), lead_ahead, on_route, p.size()])
			check(on_route < 12.0, "the interception point lies on the caravan's route (%.1f px off)" % on_route)
			check(lead_ahead > 60.0, "the band leads the caravan (aim %.0f px ahead), not chases its current spot" % lead_ahead)
	check(t_seen >= 0.0, "the war band never went for the caravan in sight")
	# the band must run the convoy down; the fight itself is a dice roll (pa^2 / (pa^2 + pb^2)): a band that ran it
	# down and lost the roll still made its interception (the world's random stream moves with every economy change)
	var ran_down := (WarAI.state(w)["news"] as Array).any(func(n): return String(n.get("text", "")).contains("ran down an orc caravan"))
	check(caught or ran_down, "the war band did not catch the caravan in 5 days")
	var st: Dictionary = WarAI.state(w)
	check(int(st["stats"]["caught"]) > stats0 or not w["warbands"].has(hid), "an interception counted")
	var news: Array = st["news"]
	print("intercept: caught=%s on day %.2f; news: %s; log tail %s" % [caught, Game.day, news.slice(-1), (w["log"] as Array).slice(-2)])
	if caught and w["warbands"].has(hid):
		check((w["log"] as Array).any(func(l): return String(l).contains("caravan") and String(l).contains("plundered")), "ordinary merchant caravan loss is recorded on the map")

# ---------------------------------------------------------------- a weaker band avoids a stronger enemy
func _avoid() -> void:
	var w := _world(4402)
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 8
	var mt := _town_of(w, "middle_kingdom")
	var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(150, 0))
	var weak := _ai_band( "middle_kingdom", p, 3, "patrol", rng, {"home": mt["id"]})
	var opos := CampaignWorld.nearest_passable(w, p + Vector2(190, 40))
	var strong := _ai_band( "orc_horde", opos, 30, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
	var wb: Dictionary = w["warbands"][weak]; var sb: Dictionary = w["warbands"][strong]
	sb["rest_until"] = Game.day + 0.6   # enough stationary time to measure a terrain-limited retreat
	_think_now(wb)
	var d0 := (wb["pos"] as Vector2).distance_to(sb["pos"])
	var mode := ""
	for i in 25:
		_step(w, [weak, strong], 0.02)
		if not w["warbands"].has(weak):
			break
		mode = String(wb.get("war", {}).get("m", mode)) if mode == "" else mode
	var d1 := (wb["pos"] as Vector2).distance_to(sb["pos"]) if w["warbands"].has(weak) else 0.0
	print("avoid: weak band %s, %.0f -> %.0f px from the orcs (power %.1f vs %.1f)" % [mode, d0, d1, WarAI.power(wb, Game.day), WarAI.power(sb, Game.day)])
	check(mode == "avoid", "the weaker band did not avoid (mode %s)" % mode)
	check(d1 > d0 + 30.0, "the weaker band did not get away (%.0f -> %.0f)" % [d0, d1])
	# the orcs, rested, go for it
	_think_now(sb)
	_step(w, [weak, strong], 0.36)
	var sm := String(sb.get("war", {}).get("m", ""))
	var st := String(sb.get("war", {}).get("tgt", ""))
	print("avoid: the strong band: %s %s" % [sm, st])
	check((sm == "intercept" and st == weak) or not w["warbands"].has(weak) or sm in ["hunt", "track"], "the stronger band does not go for the weaker one (%s)" % sm)

# ---------------------------------------------------------------- tracks and word
func _tracks() -> void:
	var w := _world(4403)
	_diplo(w, [["middle_kingdom", "goblin_warren", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var mt := _town_of(w, "middle_kingdom")
	var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(0, 60))
	var hid := _ai_band( "middle_kingdom", p, 10, "patrol", rng, {"home": mt["id"]})
	# goblins passed close by a while ago and are now ~600 px away, resting
	var dir := Vector2(1, 0.3).normalized()
	var gpos := CampaignWorld.nearest_passable(w, p + dir * 470.0)
	if (gpos - p).length() < 380.0:
		dir = -dir
		gpos = CampaignWorld.nearest_passable(w, p - Vector2(1, 0.3).normalized() * 470.0)
	var gid := _ai_band( "goblin_warren", gpos, 3, "raider", rng, {"home": _town_of(w, "goblin_warren")["id"], "staged": true})
	var gb: Dictionary = w["warbands"][gid]
	gb["rest_until"] = Game.day + 2.0
	var t := float(Game.day)
	for k in 5:   # crumbs from beside the patrol to the goblins, the newest 3 hours old
		var cp: Vector2 = p.lerp(gpos, 0.15 + 0.2 * k)
		Tracks.add_crumb(w, gid, {"f": "goblin_warren", "k": "raider", "r": "goblin"}, cp, t - 0.125 * (5 - k), 3, (gpos - p).angle())
	Tracks.state(w)["next"] = t + 1.0   # no fresh drops during the check (the trail is the test's)
	var hb: Dictionary = w["warbands"][hid]
	_think_now(hb)
	_step(w, [hid, gid], 0.01)
	var war: Dictionary = hb.get("war", {})
	print("tracks: patrol %s on %s, aim %.0f px from the goblins" % [war.get("m", "-"), war.get("tgt", "-"), (war.get("aim", Vector2.ZERO) as Vector2).distance_to(gpos)])
	check(String(war.get("m", "")) == "track" and String(war.get("tgt", "")) == gid, "the patrol did not follow fresh enemy tracks")
	var seen := false
	for i in 125:   # up to 2.5 days
		_step(w, [hid, gid], 0.02)
		if not w["warbands"].has(gid) or not w["warbands"].has(hid):
			seen = true
			break
		if String(hb.get("war", {}).get("m", "")) == "intercept":
			seen = true
			break
	check(seen, "following the tracks never brought the enemy into sight")
	# stale tracks are not followed
	var w2 := _world(4403)
	_diplo(w2, [["middle_kingdom", "goblin_warren", Diplomacy.WAR]])
	var h2 := _ai_band( "middle_kingdom", p, 10, "patrol", rng, {"home": mt["id"]})
	var g2 := _ai_band( "goblin_warren", gpos, 3, "raider", rng, {"home": _town_of(w2, "goblin_warren")["id"]})
	w2["warbands"][g2]["rest_until"] = Game.day + 2.0
	for k in 5:
		Tracks.add_crumb(w2, g2, {"f": "goblin_warren", "k": "raider", "r": "goblin"}, p.lerp(gpos, 0.15 + 0.2 * k), Game.day - 1.5 - 0.1 * (5 - k), 3, 0.0)
	Tracks.state(w2)["next"] = Game.day + 1.0
	_think_now(w2["warbands"][h2])
	_step(w2, [h2, g2], 0.01)
	check(String(w2["warbands"][h2].get("war", {}).get("m", "")) != "track", "stale tracks followed")

func _word() -> void:
	var w := _world(4404)
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 10
	# orcs loiter by a March town; a March patrol 500-850 px away hears of it from the town
	var towns: Array = []
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == "middle_kingdom":
			towns.append(w["towns"][tid])
	var town: Dictionary = towns[0]
	var opos := CampaignWorld.nearest_passable(w, town["pos"] + Vector2(-90, 50))
	var oid := _ai_band( "orc_horde", opos, 3, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
	w["warbands"][oid]["rest_until"] = Game.day + 3.0
	var hpos := Vector2.INF
	for a in 16:
		var c := CampaignWorld.nearest_passable(w, opos + Vector2.from_angle(a * TAU / 16.0) * 650.0)
		if c.distance_to(opos) > 500.0 and c.distance_to(opos) < 850.0 and not CampaignWorld.find_path(w, c, opos).is_empty():
			hpos = c
			break
	check(hpos != Vector2.INF, "a spot for the patrol")
	if hpos == Vector2.INF:
		return
	var hid := _ai_band( "middle_kingdom", hpos, 10, "patrol", rng, {"home": town["id"]})
	var hb: Dictionary = w["warbands"][hid]
	hb["war_next"] = Game.day + 10.0   # no decision until the word is in
	for i in 30:   # the town watch comes round, the word travels REPORT_DELAY
		_step(w, [hid, oid], 0.02)
	var intel: Dictionary = WarAI.state(w)["intel"].get("middle_kingdom", {})
	check(intel.has(oid), "the town did not send word of the orcs")
	_think_now(hb)
	_step(w, [hid, oid], 0.01)
	var war: Dictionary = hb.get("war", {})
	print("word: intel %s; patrol %s on %s" % [str(intel.get(oid, [])).substr(0, 60), war.get("m", "-"), war.get("tgt", "-")])
	check(String(war.get("m", "")) == "hunt" and String(war.get("tgt", "")) == oid, "the patrol did not march on the town's word")

# ---------------------------------------------------------------- calling allies, falling back home
func _call_and_home() -> void:
	var w := _world(4405)
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var mt := _town_of(w, "middle_kingdom")
	var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(120, 0))
	var a := _ai_band( "middle_kingdom", p, 6, "patrol", rng, {"home": mt["id"]})
	var b := _ai_band( "middle_kingdom", CampaignWorld.nearest_passable(w, p + Vector2(-300, 60)), 6, "patrol", rng, {"home": mt["id"]})
	var o := _ai_band( "orc_horde", CampaignWorld.nearest_passable(w, p + Vector2(250, 0)), 6, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
	var ab: Dictionary = w["warbands"][a]; var bb: Dictionary = w["warbands"][b]; var ob: Dictionary = w["warbands"][o]
	ob["rest_until"] = Game.day + 1.0
	# make the orcs a bit stronger than band a alone, weaker than a + b
	var pa := WarAI.power(ab, Game.day); var pb := WarAI.power(bb, Game.day)
	while WarAI.power(ob, Game.day) < pa * 1.2 and (ob["units"] as Array).size() < 40:
		(ob["units"] as Array).append(Factory.make_warband(rng, "orc_horde", 1)[0])
	while WarAI.power(ob, Game.day) > (pa + pb) * 0.9 and (ob["units"] as Array).size() > 1:
		(ob["units"] as Array).pop_back()
	var po := WarAI.power(ob, Game.day)
	_think_now(ab)
	bb["war_next"] = Game.day + 10.0
	_step(w, [a, b, o], 0.01)
	var wa: Dictionary = ab.get("war", {}); var wbb: Dictionary = bb.get("war", {})
	print("call: a %.1f + b %.1f vs orcs %.1f: a %s, b %s" % [pa, pb, po, wa.get("m", "-"), wbb.get("m", "-")])
	if po > pa:
		check(String(wa.get("m", "")) == "shadow", "a band weaker than its target does not shadow it (%s)" % wa.get("m", "-"))
		check(String(wbb.get("m", "")) == "join" and String(wbb.get("tgt", "")) == o, "the neighbour band was not called")
	# together they go in
	bb["war_next"] = 0.0
	var went := false
	for i in 125:   # up to 2.5 days
		_step(w, [a, b, o], 0.02)
		if not w["warbands"].has(o) or String(ab.get("war", {}).get("m", "")) == "intercept":
			went = true
			break
	check(went, "the gathered bands never attacked")
	# beaten down: home
	var w2 := _world(4406)
	_diplo(w2, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var home := _town_of(w2, "middle_kingdom")
	var h := _ai_band( "middle_kingdom", CampaignWorld.nearest_passable(w2, home["pos"] + Vector2(400, 0)), 10, "patrol", rng, {"home": home["id"]})
	var hb: Dictionary = w2["warbands"][h]
	_think_now(hb)
	_step(w2, [h], 0.01)
	(hb["units"] as Array).resize(4)
	_think_now(hb)
	_step(w2, [h], 0.01)
	check(String(hb.get("war", {}).get("m", "")) == "home", "a band down to 4 of 10 does not fall back home (%s)" % hb.get("war", {}).get("m", "-"))
	var d0 := (hb["pos"] as Vector2).distance_to(home["pos"])
	_step(w2, [h], 1.0)   # a day: on the 1.5x map this band starts in forest (x0.6), half a day walks only ~45 px
	var d1 := (hb["pos"] as Vector2).distance_to(home["pos"])
	print("home: %.0f -> %.0f px from home, mode %s" % [d0, d1, hb.get("war", {}).get("m", "-")])
	check(d1 < d0 - 50.0, "the beaten band did not head home")
	# unpaid: home
	var u := _ai_band( "middle_kingdom", CampaignWorld.nearest_passable(w2, home["pos"] + Vector2(-400, 0)), 8, "patrol", rng, {"home": home["id"]})
	var ub: Dictionary = w2["warbands"][u]
	_think_now(ub)
	_step(w2, [h, u], 0.01)
	ub["unpaid_n"] = 6
	_think_now(ub)
	_step(w2, [h, u], 0.01)
	check(String(ub.get("war", {}).get("m", "")) == "home", "an unpaid band does not fall back home")

# ---------------------------------------------------------------- militia hold the walls (war pick 3)
func _militia() -> void:
	var w := _world(4408)
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 13
	var ot := _town_of(w, "orc_horde")
	w["militia"] = {}
	var mid := Militia.ensure(Game, ot["id"], rng)
	var mil: Dictionary = w["warbands"][mid]
	var n0 := (mil["units"] as Array).size()
	var pm := CampaignWorld.band_power(mil["units"])
	check(Militia.sallies(1.25, 1.0) and not Militia.sallies(1.24, 1.0), "the militia sallies at 1.25x the enemy's power, not below")
	check(not WarAI.TARGET_KINDS.has("militia"), "war bands still hunt militia in the field")
	var mk: String = _town_of(w, "middle_kingdom")["id"]
	var gate := CampaignWorld.nearest_passable(w, (ot["pos"] as Vector2) + Vector2(50, 40))
	# (1) an enemy band the militia could match at 0.6x but does not outnumber 1.25x, at the gate: it holds the walls
	var hid := _ai_band( "middle_kingdom", gate, 1, "patrol", rng, {"home": mk})
	var hb: Dictionary = w["warbands"][hid]
	while CampaignWorld.band_power(hb["units"]) < pm / 1.2 and (hb["units"] as Array).size() < 300:
		(hb["units"] as Array).append(Factory.make_warband(rng, "middle_kingdom", 1)[0])
	var ph := CampaignWorld.band_power(hb["units"])
	check(pm >= 0.6 * ph and pm < 1.25 * ph, "test setup: militia %.1f vs band %.1f is not between 0.6x and 1.25x" % [pm, ph])
	_think_now(hb)
	var went := false
	var walls := false
	for i in 50:   # a day
		_step(w, [hid, mid], 0.02)
		if String(hb.get("war", {}).get("tgt", "")) == mid:
			went = true
		walls = walls or bool(mil.get("walls", false))
		if not w["warbands"].has(mid) or (mil["units"] as Array).size() < n0 or not w["warbands"].has(hid):
			break
	var n1 := (mil["units"] as Array).size() if w["warbands"].has(mid) else 0
	print("militia: %d men (power %.1f) vs a band of %d (power %.1f) at the gate: hunted %s, walls %s, militia %d -> %d, band %s" % [
		n0, pm, (hb["units"] as Array).size(), ph, went, walls, n0, n1, "there" if w["warbands"].has(hid) else "gone"])
	check(not went, "a war band went for the militia in the field")
	check(n1 == n0 and w["warbands"].has(hid), "an outnumbered militia sallied out (power %.1f vs %.1f)" % [pm, ph])
	check(walls, "the militia did not hold the walls with an enemy at the gate")
	# (2) an enemy it outnumbers 1.25x or more: it comes out and fights
	var lid := _ai_band( "middle_kingdom", gate, 1, "patrol", rng, {"home": mk})
	var lb: Dictionary = w["warbands"][lid]
	_purge(w, [mid, lid])
	var pl := CampaignWorld.band_power(lb["units"])
	check(Militia.sallies(pm, pl), "test setup: militia %.1f does not outnumber a lone man %.1f" % [pm, pl])
	var fought := false
	for i in 50:
		_step(w, [lid, mid], 0.02)
		if not w["warbands"].has(lid) or (mil["units"] as Array).size() < n0:
			fought = true
			break
	print("militia vs a band of %d (power %.1f): fought %s; log %s" % [(lb["units"] as Array).size(), pl, fought, (w["log"] as Array).slice(-1)])
	check(fought, "a militia 1.25x stronger did not sally out")
	check(not bool(mil.get("walls", false)) or not w["warbands"].has(lid), "still behind the walls after the threat")

# ---------------------------------------------------------------- peace and HOSTILE
func _peace() -> void:
	for st in [Diplomacy.NEUTRAL, Diplomacy.HOSTILE, Diplomacy.ALLIANCE]:
		var w := _world(4407)
		_diplo(w, [["middle_kingdom", "orc_horde", st]] if st != Diplomacy.NEUTRAL else [])
		if st == Diplomacy.ALLIANCE:
			_force(w, "middle_kingdom", "orc_horde", st, 80.0)
		var rng := RandomNumberGenerator.new(); rng.seed = 12
		var mt := _town_of(w, "middle_kingdom")
		var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(150, 0))
		var h := _ai_band( "middle_kingdom", p, 10, "patrol", rng, {"home": mt["id"]})
		var o := _ai_band( "orc_horde", CampaignWorld.nearest_passable(w, p + Vector2(200, 0)), 2, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
		var ot := _town_of(w, "orc_horde")
		var c := _caravan(w, "orc_horde", CampaignWorld.nearest_passable(w, p + Vector2(0, 150)), ot, 2, rng)
		var hb: Dictionary = w["warbands"][h]
		var ever := false
		_think_now(hb)
		for i in 25:
			_step(w, [h, o, c], 0.02)
			if not (hb.get("war", {}) as Dictionary).is_empty():
				ever = true
		var stats: Dictionary = WarAI.state(w)["stats"]
		print("%s: war orders %s, intercepts %d" % [st, ever, int(stats["intercepts"])])
		check(not ever and int(stats["intercepts"]) == 0, "%s: a band went hunting" % st)

# ---------------------------------------------------------------- determinism
func _sig(seed_v: int) -> String:
	Game.new_game(seed_v)
	var w: Dictionary = Game.world
	var fl: Array = w["diplo"]["factions"]
	for i in fl.size():
		for j in range(i + 1, fl.size()):
			_force(w, fl[i], fl[j], Diplomacy.WAR, -80.0)
	for i in 120:
		Game.advance_time(0.025, false)
		w["encounter"] = ""
		w["party"]["safe_until"] = Game.day + 10.0
	var parts := []
	var ks: Array = w["warbands"].keys()
	ks.sort()
	for k in ks:
		var wb: Dictionary = w["warbands"][k]
		parts.append("%s:%d,%d:%s" % [k, int(wb["pos"].x), int(wb["pos"].y), String(wb.get("war", {}).get("m", ""))])
	return "%s|%s" % [str(WarAI.state(w)["stats"]), ",".join(parts)]

func _determinism() -> void:
	var a := _sig(4410)
	var b := _sig(4410)
	print("determinism: %s" % a.substr(0, 200))
	check(a == b, "the same seed gave a different war")
	check(int(WarAI.state(Game.world)["stats"]["intercepts"]) + int(WarAI.state(Game.world)["stats"]["shadows"]) > 0, "a 3-day all-out war had no interceptions")
	# save / load mid-war: orders survive with their types, the war goes on
	var orders := {}
	for k in Game.world["warbands"]:
		var war: Dictionary = Game.world["warbands"][k].get("war", {})
		if not war.is_empty():
			orders[k] = "%s>%s" % [war["m"], war["tgt"]]
	Game.save_game()
	check(Game.load_game(), "load after a war")
	var kept := 0
	for k in orders:
		var war: Dictionary = Game.world["warbands"].get(k, {}).get("war", {})
		if not war.is_empty() and "%s>%s" % [war["m"], war["tgt"]] == orders[k] and war["aim"] is Vector2 and war["p0"] is Vector2:
			kept += 1
	print("save/load: %d of %d war orders kept" % [kept, orders.size()])
	check(kept == orders.size(), "war orders lost or mistyped in save/load")
	for i in 20:
		Game.advance_time(0.025, false)
		Game.world["encounter"] = ""

# ---------------------------------------------------------------- per-frame cost
func _perf(tree: SceneTree) -> void:
	Game.new_game(4420)
	var w: Dictionary = Game.world
	var fl: Array = w["diplo"]["factions"]
	for i in fl.size():
		for j in range(i + 1, fl.size()):
			_force(w, fl[i], fl[j], Diplomacy.WAR, -80.0)
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var fids := ["middle_kingdom", "orc_horde", "goblin_warren", "northern_clans", "moon_court"]
	var hunters := func() -> int:
		var n := 0
		for k in w["warbands"]:
			if w["warbands"][k]["kind"] in ["patrol", "raider"]:
				n += 1
		return n
	while hunters.call() < 40:   # (staged: 40 bands is more men than the towns could spare, war pick 4)
		CampaignWorld.spawn_faction_band(Game, fids[hunters.call() % fids.size()], rng, false, true)
	for i in 20:   # half a day of war first
		Game.advance_time(0.025, false)
		w["encounter"] = ""
		w["party"]["safe_until"] = Game.day + 10.0
	for mult in [1, 4]:
		WarAI.usec = 0; WarAI.think_usec = 0; WarAI.astar_usec = 0; WarAI.astar_n = 0; WarAI.prof = {}
		var frames := 600
		var fd: float = mult / 300.0   # map at 60 fps, 5 s per day, speed x1 / x4
		var s0: Dictionary = (WarAI.state(w)["stats"] as Dictionary).duplicate()
		var worst := 0
		var worst_txt := ""
		for i in frames:
			w["party"]["safe_until"] = Game.day + 10.0
			w["encounter"] = ""
			var u0 := WarAI.usec
			var k0 := WarAI.think_usec; var a0 := WarAI.astar_usec; var r0 := int(WarAI.prof.get("retarget", 0))
			Game.day += fd
			CampaignWorld.on_time(Game, fd, false)
			if WarAI.usec - u0 > worst:
				worst = WarAI.usec - u0
				worst_txt = "think %d us, grid paths %d us, retarget %d us" % [WarAI.think_usec - k0, WarAI.astar_usec - a0, int(WarAI.prof.get("retarget", 0)) - r0]
			if i % 60 == 0:
				await tree.process_frame
		var hn: int = hunters.call()
		var mean_ms: float = WarAI.usec / float(frames) / 1000.0
		var s1: Dictionary = WarAI.state(w)["stats"]
		var busy := 0
		for k in w["warbands"]:
			if not (w["warbands"][k].get("war", {}) as Dictionary).is_empty():
				busy += 1
		print("war AI per frame x%d: mean %.4f ms, worst %.3f ms; %d bands (%d hunters, %d with war orders); thinks %d, intercepts %d, shadows %d, avoids %d, tracks %d, word %d, calls %d, home %d, caught %d" % [
			mult, mean_ms, worst / 1000.0, w["warbands"].size(), hn, busy, int(s1["thinks"]) - int(s0["thinks"]),
			int(s1["intercepts"]) - int(s0["intercepts"]), int(s1["shadows"]) - int(s0["shadows"]), int(s1["avoids"]) - int(s0["avoids"]),
			int(s1["tracks"]) - int(s0["tracks"]), int(s1["word"]) - int(s0["word"]), int(s1["calls"]) - int(s0["calls"]),
			int(s1["home"]) - int(s0["home"]), int(s1["caught"]) - int(s0["caught"])])
		print("   worst frame: %s" % worst_txt)
		print("   of which decisions %.4f ms/frame, grid paths %.4f ms/frame (%d paths, %.3f ms each)" % [WarAI.think_usec / float(frames) / 1000.0,
			WarAI.astar_usec / float(frames) / 1000.0, WarAI.astar_n, WarAI.astar_usec / maxf(1.0, WarAI.astar_n) / 1000.0])
		var pr := []
		for k in WarAI.prof:
			var v: float = WarAI.prof[k] / 1000.0 if String(k).ends_with("_worst") else WarAI.prof[k] / float(frames) / 1000.0
			pr.append("%s %.4f" % [k, v])
		print("   sections ms/frame (*_worst: ms, once): %s" % ", ".join(pr))
		if mult == 1:
			check(mean_ms < 0.1, "war AI too slow per frame (%.4f ms mean)" % mean_ms)
