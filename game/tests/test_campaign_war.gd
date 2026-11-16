extends RefCounted
const NativeForces = preload("res://tests/class_d_registered_forces.gd")
var _part: String = ""
var _budget_failed: bool = false
var _deadline_msec: int = 0
const PARTS: Array[String] = ["intercept", "avoid", "tracks", "word", "call_and_home", "militia", "peace", "determinism", "perf"]
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
		print("FAIL: war ", _part, ": ", msg)
		fails += 1

func _within_budget() -> bool:
	if Time.get_ticks_msec() < _deadline_msec: return true
	if not _budget_failed:
		check(false, "whole selected war part exceeded 150 seconds; incomplete work is a failure")
		_budget_failed = true
	return false

func _release_band(w: Dictionary, id: String) -> void:
	if not w["warbands"].has(id): return
	var band: Dictionary = w["warbands"][id]
	if str(band.get("kind", "")) == "caravan":
		if not Caravans._come_home(Game, band): Caravans._consign_unpaid(Game, band)
		CampaignWorld.remove_warband(Game, id)
		return
	if str(band.get("kind", "")) in ["militia", "guard"]:
		for unit: Unit in band["units"]:
			if unit.dead: continue
			var town: Dictionary = w["towns"].get(unit.home_town, {})
			var family: Dictionary = People.fam_of(town, unit.family)
			var person: Array = Persons.by_uid(family, unit.uid) if not family.is_empty() else []
			if not person.is_empty():
				Horses.return_mount(Game, unit)
				ArmsTrade.kit_home(Game, unit)
				People.release(town, unit.family, str(person[4]), unit.uid)
		CampaignWorld.remove_warband(Game, id)
		return
	for unit: Unit in (band["units"] as Array).duplicate():
		if not unit.dead and not Creatures.is_creature(unit.race):
			Army.release(Game, unit, "fled")
	CampaignWorld.remove_warband(Game, id)

func _fund_faction(w: Dictionary, faction: String, target: float) -> bool:
	var fac: Dictionary = w["factions"].get(faction, {})
	check(not fac.is_empty(), "native funding needs a real faction " + faction)
	if fac.is_empty(): return false
	var before: float = Barge.holdings(Game)
	for town: Dictionary in w["towns"].values():
		if not TownEcon.has_econ(town) or town["faction"] != faction: continue
		var amount: float = minf(maxf(0.0, target - float(fac["treasury"])), maxf(0.0, float(town["econ"]["treasury"])))
		town["econ"]["treasury"] = float(town["econ"]["treasury"]) - amount
		fac["treasury"] = float(fac["treasury"]) + amount
	var funded: bool = float(fac["treasury"]) >= target and absf(Barge.holdings(Game) - before) < 0.01
	check(funded, faction + ": native fixture needs sufficient actual transferred coin")
	return funded

## Budget actual live wages, native sign-on multipliers, and priced rations for this part.
## Transfers conserve real town/faction coin; a short treasury fails the fixture.
func _support_scene(w: Dictionary, faction: String) -> bool:
	var days: float = float({"intercept": 6, "avoid": 2, "tracks": 3, "word": 1,
		"call_and_home": 4, "militia": 2, "peace": 1, "perf": 5}.get(_part, 1))
	var members: Array = Army.members(Game, faction)
	var low: int = Army.low_officer(members, "army")
	var signing: Array = Army.A().get("sign_on", [1.5, 2.5])
	var sign_days: float = maxf(float(signing[0]), float(signing[1]))
	var need: float = 0.0
	for unit: Unit in members:
		if not unit.dead:
			need += Army.wage("army", unit.rank, low, unit) * days
			need += Army.wage("army", unit.rank, -1, unit) * sign_days
	for band: Dictionary in w["warbands"].values():
		if str(band["faction"]) != faction or not Army.is_field(band): continue
		var town: Dictionary = w["towns"].get(str(band["home"]), {})
		check(TownEcon.has_econ(town), "native supply bill needs a real home economy")
		if not TownEcon.has_econ(town): return false
		var food_price: float = 0.0
		var drink_price: float = 0.0
		for good: String in Supplies.FOOD:
			food_price = maxf(food_price, float(town["econ"]["price"].get(good, 1.0)))
		for good: String in Supplies.DRINK:
			drink_price = maxf(drink_price, float(town["econ"]["price"].get(good, 1.0)))
		var ration_days: float = days + float(Supplies.A()["store_days"])
		need += (2.0 * Supplies.meal_shares(band) * food_price + float(Supplies.men(band)) * drink_price) * ration_days
		need += float(Horses.count(band["units"])) * float(Horses.GRAIN_DAY) * ration_days * float(town["econ"]["price"].get("grain", 1.0))
	return _fund_faction(w, faction, ceilf(need))

func _reinforce(band: Dictionary, rng: RandomNumberGenerator) -> bool:
	var w: Dictionary = Game.world
	var id: String = _ai_band(str(band["faction"]), band["pos"], 1, str(band["kind"]), rng, {"home": band["home"]})
	if id == "" or fails > 0: return false
	var reinforcement: Dictionary = w["warbands"][id]
	(band["units"] as Array).append_array(reinforcement["units"])
	reinforcement["units"] = []
	var supplied: Dictionary = Supplies.stores(reinforcement).duplicate()
	var taken: Dictionary = Supplies.take(band, reinforcement)
	check(taken == supplied, "native reinforcement must transfer every purchased ration")
	CampaignWorld.remove_warband(Game, id)
	var valid: Dictionary = NativeForces.registered(Game, band)
	check(bool(valid["ok"]), "native reinforcement: " + str(valid.get("reason", "")))
	return fails == 0 and bool(valid["ok"])

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
	if not _within_budget(): return {}
	Game.new_game(seed_v)
	if not _within_budget(): return {}
	var w: Dictionary = Game.world
	for id: String in w["warbands"].keys(): _release_band(w, id)
	for unit: Unit in CampaignWorld.mustering_units(w):
		if not unit.dead and not Creatures.is_creature(unit.race): Army.release(Game, unit, "fled")
	w["work"] = []
	check(w["warbands"].is_empty(), "native removal must release the old scene's actual forces")
	for faction: String in ["middle_kingdom", "orc_horde", "goblin_warren", "northern_clans", "moon_court"]:
		check(not _town_of(w, faction).is_empty(), "native war fixture needs an existing town of " + faction)
	if fails > 0: return {}
	w["party"]["safe_until"] = 1.0e9
	return w

func _purge(w: Dictionary, keep: Array) -> void:
	for wid in w["warbands"].keys():
		if not keep.has(wid):
			_release_band(w, str(wid))
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
	var home_id: String = WorldWarbands.nearest_faction_town(w, fid, pos)
	var home: Dictionary = w["towns"].get(home_id, {})
	check(TownEcon.has_econ(home) and not dest.is_empty() and home_id != str(dest.get("id", "")), "caravan fixture needs distinct actual origin/destination economies")
	if fails > 0 or not _within_budget(): return ""
	# Native sail hires the real guards/drivers and kits them; raw spawn alone does not enlist caravan people.
	var cid: String = CampaignWorld.spawn_warband(Game, fid, pos, n, "caravan", rng, {"home": home_id, "origin": home_id,
		"dest": dest["id"], "leg": "out", "cargo": {"items": [], "goods": {}}, "gold": 0.0, "escort": "", "away": 0.0,
		"state": "travel", "depart_day": Game.day})
	check(cid != "" and w["warbands"].has(cid), "native caravan fixture needs a live force ID")
	if cid == "" or not w["warbands"].has(cid): return ""
	var car: Dictionary = w["warbands"][cid]
	var path: Array = Caravans.way(w, car, home_id, str(dest["id"]))
	check(not path.is_empty(), "native caravan needs an actual usable route before hiring")
	if path.is_empty(): _release_band(w, cid); return ""
	var bill: float = People.crew_bill(n, Caravans.trip_days(car["pos"], path))
	var economy: Dictionary = home["econ"]
	var market: Dictionary = economy["biz"][int(economy["mkt"])]
	var total_coin: float = Barge.holdings(Game)
	var amount: float = minf(maxf(0.0, bill - float(market["till"])), maxf(0.0, float(economy["treasury"])))
	economy["treasury"] = float(economy["treasury"]) - amount
	market["till"] = float(market["till"]) + amount
	check(float(market["till"]) >= bill and absf(Barge.holdings(Game) - total_coin) < 0.01, "native caravan owner needs the actual conserved crew bill")
	if fails > 0: _release_band(w, cid); return ""
	var sailed: String = Caravans.sail(Game, cid, rng)
	check(sailed == cid and w["warbands"].has(cid), "native caravan sail must actually recruit and equip the crew")
	if sailed != cid or not w["warbands"].has(cid): return ""
	check((car["units"] as Array).size() == n, "native caravan must retain exactly the requested guards")
	var valid: Dictionary = NativeForces.registered(Game, car)
	check(bool(valid["ok"]), "native caravan people: " + str(valid.get("reason", "")))
	check((car.get("crew", []) as Array).size() == n + People.DRIVERS, "native caravan must recruit every guard and driver")
	if fails > 0: return ""
	return cid

func _ai_band(fid: String, pos: Vector2, count: int, kind: String, rng: RandomNumberGenerator, extra: Dictionary = {}) -> String:
	# Native drafting consumes only available registered residents.
	extra.erase("staged")
	if not _within_budget(): return ""
	var w: Dictionary = Game.world
	var id: String = CampaignWorld.spawn_warband(Game, fid, pos, count, kind, rng, extra)
	check(id != "" and w["warbands"].has(id), "native %s/%s spawn returned no force ID" % [fid, kind])
	if id == "" or not w["warbands"].has(id): return ""
	var band: Dictionary = w["warbands"][id]
	check((band["units"] as Array).size() == count, "native %s/%s must actually accept all %d requested people" % [fid, kind, count])
	var valid: Dictionary = NativeForces.registered(Game, band)
	check(bool(valid["ok"]), "native war roster: " + str(valid.get("reason", "")))
	if fails > 0 or not _support_scene(w, fid): return ""
	Supplies.provision(Game, band, {"kind": "faction", "fac": w["factions"][fid]})
	check(Supplies.days(band) > 0.0, "native war actor needs actual purchased provisions")
	return id

func _think_now(wb: Dictionary) -> void:
	wb["war_next"] = 0.0

func _step(w: Dictionary, keep: Array, days: float) -> bool:
	if not _within_budget() or fails > 0: return false
	Game.advance_time(days, false)
	_purge(w, keep)
	return _within_budget() and fails == 0

func run(tree: SceneTree) -> int:
	fails = 0
	_part = ""
	_budget_failed = false
	var selected: bool = false
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--war-part="): continue
		check(not selected, "select exactly one war part per invocation")
		selected = true
		_part = argument.trim_prefix("--war-part=")
	check(selected, "select exactly one war part per invocation: --war-part=<part>; no-argument invocation is incomplete")
	check(_part in PARTS, "unknown war part: " + _part)
	if fails > 0: return fails
	_deadline_msec = Time.get_ticks_msec() + 150000
	match _part:
		"intercept": _intercept()
		"avoid": _avoid()
		"tracks": _tracks()
		"word": _word()
		"call_and_home": _call_and_home()
		"militia": _militia()
		"peace": _peace()
		"determinism": _determinism()
		"perf": await _perf(tree)
	if fails == 0: _within_budget()
	return fails

# ---------------------------------------------------------------- lead interception of a caravan
func _intercept() -> void:
	var w: Dictionary = _world(4401)
	if w.is_empty(): return
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	# a long caravan route: the two towns farthest apart that a path joins (route lengths in map units: x
	# WorldGen.K, so the 1.5x map of war pick 5 picks the same class of route as the old map did)
	var ids: Array = w["towns"].keys()
	var best: Array = []; var bl: float = 0.0
	for i in ids.size():
		for j in ids.size():
			if i == j or str(w["towns"][ids[i]]["faction"]) != "orc_horde":
				continue
			var a: Vector2 = w["towns"][ids[i]]["pos"]; var b: Vector2 = w["towns"][ids[j]]["pos"]
			if a.distance_to(b) > bl and a.distance_to(b) < 1500.0 * WorldGen.K:
				var p: Array = CampaignWorld.find_path(w, a, b)
				if not p.is_empty() and CampaignWorld.path_length(a, p) > 1100.0 * WorldGen.K:
					bl = a.distance_to(b); best = [ids[i], ids[j]]
	check(not best.is_empty(), "a long route for the caravan")
	if best.is_empty():
		return
	var origin: Vector2 = w["towns"][best[0]]["pos"]
	var cid: String = _caravan(w, "orc_horde", origin, w["towns"][best[1]], 2, rng)
	if cid == "" or fails > 0: return
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
	var hid: String = _ai_band( "middle_kingdom", bpos, 10, "patrol", rng, {"home": _town_of(w, "middle_kingdom")["id"]})
	if hid == "" or fails > 0: return
	var hb: Dictionary = w["warbands"][hid]
	# barge part 4 section 8: unpaid braves go home after 3 days: this band's realm can pay it for the test's days
	if not _support_scene(w, "middle_kingdom"): return
	check(WarAI.power(hb, Game.day) > 1.25 * WarAI.power(car, Game.day), "native interceptor must actually overpower the caravan")
	check(not cpath.is_empty() and not CampaignWorld.find_path(w, bpos, ahead).is_empty(), "native interception geometry has usable target and hunter routes")
	check(w["diplo"]["pairs"][Diplomacy.pair_key("middle_kingdom", "orc_horde")]["state"] == Diplomacy.WAR, "native interception fixture has actual diplomatic WAR")
	if fails > 0: return
	# start the caravan so the band sees it (within SIGHT) after a short walk
	var keep := [cid, hid]
	var t_seen := -1.0
	var aim := Vector2.INF
	var lead_ahead := 0.0
	var caught := false
	var stats0 := int(WarAI.state(w)["stats"].get("caught", 0))
	for i in 250:   # up to 5 days
		if not _step(w, keep, 0.02): return
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
	var w: Dictionary = _world(4402)
	if w.is_empty(): return
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 8
	var mt := _town_of(w, "middle_kingdom")
	var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(150, 0))
	var weak: String = _ai_band( "middle_kingdom", p, 3, "patrol", rng, {"home": mt["id"]})
	if weak == "" or fails > 0: return
	var opos := CampaignWorld.nearest_passable(w, p + Vector2(190, 40))
	var strong: String = _ai_band( "orc_horde", opos, 30, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
	if strong == "" or fails > 0: return
	var wb: Dictionary = w["warbands"][weak]; var sb: Dictionary = w["warbands"][strong]
	sb["rest_until"] = Game.day + 0.6   # enough stationary time to measure a terrain-limited retreat
	_think_now(wb)
	var d0 := (wb["pos"] as Vector2).distance_to(sb["pos"])
	var mode := ""
	for i in 25:
		if not _step(w, [weak, strong], 0.02): return
		if not w["warbands"].has(weak):
			break
		mode = String(wb.get("war", {}).get("m", mode)) if mode == "" else mode
	var d1 := (wb["pos"] as Vector2).distance_to(sb["pos"]) if w["warbands"].has(weak) else 0.0
	print("avoid: weak band %s, %.0f -> %.0f px from the orcs (power %.1f vs %.1f)" % [mode, d0, d1, WarAI.power(wb, Game.day), WarAI.power(sb, Game.day)])
	check(mode == "avoid", "the weaker band did not avoid (mode %s)" % mode)
	check(d1 > d0 + 30.0, "the weaker band did not get away (%.0f -> %.0f)" % [d0, d1])
	# the orcs, rested, go for it
	_think_now(sb)
	if not _step(w, [weak, strong], 0.36): return
	var sm := String(sb.get("war", {}).get("m", ""))
	var st := String(sb.get("war", {}).get("tgt", ""))
	print("avoid: the strong band: %s %s" % [sm, st])
	check((sm == "intercept" and st == weak) or not w["warbands"].has(weak) or sm in ["hunt", "track"], "the stronger band does not go for the weaker one (%s)" % sm)

# ---------------------------------------------------------------- tracks and word
func _tracks() -> void:
	var w: Dictionary = _world(4403)
	if w.is_empty(): return
	_diplo(w, [["middle_kingdom", "goblin_warren", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 9
	var mt := _town_of(w, "middle_kingdom")
	var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(0, 60))
	var hid: String = _ai_band( "middle_kingdom", p, 10, "patrol", rng, {"home": mt["id"]})
	if hid == "" or fails > 0: return
	# goblins passed close by a while ago and are now ~600 px away, resting
	var dir := Vector2(1, 0.3).normalized()
	var gpos := CampaignWorld.nearest_passable(w, p + dir * 470.0)
	if (gpos - p).length() < 380.0:
		dir = -dir
		gpos = CampaignWorld.nearest_passable(w, p - Vector2(1, 0.3).normalized() * 470.0)
	var gid: String = _ai_band( "goblin_warren", gpos, 3, "raider", rng, {"home": _town_of(w, "goblin_warren")["id"], "staged": true})
	if gid == "" or fails > 0: return
	var gb: Dictionary = w["warbands"][gid]
	gb["rest_until"] = Game.day + 2.0
	var t := float(Game.day)
	for k in 5:   # crumbs from beside the patrol to the goblins, the newest 3 hours old
		var cp: Vector2 = p.lerp(gpos, 0.15 + 0.2 * k)
		Tracks.add_crumb(w, gid, {"f": "goblin_warren", "k": "raider", "r": "goblin"}, cp, t - 0.125 * (5 - k), 3, (gpos - p).angle())
	Tracks.state(w)["next"] = t + 1.0   # no fresh drops during the check (the trail is the test's)
	var hb: Dictionary = w["warbands"][hid]
	_think_now(hb)
	if not _step(w, [hid, gid], 0.01): return
	var war: Dictionary = hb.get("war", {})
	print("tracks: patrol %s on %s, aim %.0f px from the goblins" % [war.get("m", "-"), war.get("tgt", "-"), (war.get("aim", Vector2.ZERO) as Vector2).distance_to(gpos)])
	check(String(war.get("m", "")) == "track" and String(war.get("tgt", "")) == gid, "the patrol did not follow fresh enemy tracks")
	var seen := false
	for i in 125:   # up to 2.5 days
		if not _step(w, [hid, gid], 0.02): return
		if not w["warbands"].has(gid) or not w["warbands"].has(hid):
			seen = true
			break
		if String(hb.get("war", {}).get("m", "")) == "intercept":
			seen = true
			break
	check(seen, "following the tracks never brought the enemy into sight")
	# stale tracks are not followed
	var w2: Dictionary = _world(4403)
	if w2.is_empty(): return
	_diplo(w2, [["middle_kingdom", "goblin_warren", Diplomacy.WAR]])
	var h2: String = _ai_band( "middle_kingdom", p, 10, "patrol", rng, {"home": mt["id"]})
	if h2 == "" or fails > 0: return
	var g2: String = _ai_band( "goblin_warren", gpos, 3, "raider", rng, {"home": _town_of(w2, "goblin_warren")["id"]})
	if g2 == "" or fails > 0: return
	w2["warbands"][g2]["rest_until"] = Game.day + 2.0
	for k in 5:
		Tracks.add_crumb(w2, g2, {"f": "goblin_warren", "k": "raider", "r": "goblin"}, p.lerp(gpos, 0.15 + 0.2 * k), Game.day - 1.5 - 0.1 * (5 - k), 3, 0.0)
	Tracks.state(w2)["next"] = Game.day + 1.0
	_think_now(w2["warbands"][h2])
	if not _step(w2, [h2, g2], 0.01): return
	check(String(w2["warbands"][h2].get("war", {}).get("m", "")) != "track", "stale tracks followed")

func _word() -> void:
	var w: Dictionary = _world(4404)
	if w.is_empty(): return
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 10
	# orcs loiter by a March town; a March patrol 500-850 px away hears of it from the town
	var towns: Array = []
	for tid in w["towns"]:
		if w["towns"][tid]["faction"] == "middle_kingdom":
			towns.append(w["towns"][tid])
	check(not towns.is_empty(), "town-word fixture needs an actual March town")
	if towns.is_empty(): return
	var town: Dictionary = towns[0]
	var opos := CampaignWorld.nearest_passable(w, town["pos"] + Vector2(-90, 50))
	var oid: String = _ai_band( "orc_horde", opos, 3, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
	if oid == "" or fails > 0: return
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
	var hid: String = _ai_band( "middle_kingdom", hpos, 10, "patrol", rng, {"home": town["id"]})
	if hid == "" or fails > 0: return
	var hb: Dictionary = w["warbands"][hid]
	check(WarAI.power(hb, Game.day) > 1.25 * WarAI.power(w["warbands"][oid], Game.day), "native town-word hunter must actually overpower its target")
	if fails > 0: return
	hb["war_next"] = Game.day + 10.0   # no decision until the word is in
	for i in 30:   # the town watch comes round, the word travels REPORT_DELAY
		if not _step(w, [hid, oid], 0.02): return
	var intel: Dictionary = WarAI.state(w)["intel"].get("middle_kingdom", {})
	check(intel.has(oid), "the town did not send word of the orcs")
	_think_now(hb)
	if not _step(w, [hid, oid], 0.01): return
	var war: Dictionary = hb.get("war", {})
	print("word: intel %s; patrol %s on %s" % [str(intel.get(oid, [])).substr(0, 60), war.get("m", "-"), war.get("tgt", "-")])
	check(String(war.get("m", "")) == "hunt" and String(war.get("tgt", "")) == oid, "the patrol did not march on the town's word")

# ---------------------------------------------------------------- calling allies, falling back home
func _call_and_home() -> void:
	var w: Dictionary = _world(4405)
	if w.is_empty(): return
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	var mt := _town_of(w, "middle_kingdom")
	var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(120, 0))
	var a: String = _ai_band( "middle_kingdom", p, 6, "patrol", rng, {"home": mt["id"]})
	if a == "" or fails > 0: return
	var b: String = _ai_band( "middle_kingdom", CampaignWorld.nearest_passable(w, p + Vector2(-300, 60)), 6, "patrol", rng, {"home": mt["id"]})
	if b == "" or fails > 0: return
	var o: String = _ai_band( "orc_horde", CampaignWorld.nearest_passable(w, p + Vector2(250, 0)), 6, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
	if o == "" or fails > 0: return
	var ab: Dictionary = w["warbands"][a]; var bb: Dictionary = w["warbands"][b]; var ob: Dictionary = w["warbands"][o]
	ob["rest_until"] = Game.day + 1.0
	# make the orcs a bit stronger than band a alone, weaker than a + b
	var pa := WarAI.power(ab, Game.day); var pb := WarAI.power(bb, Game.day)
	while WarAI.power(ob, Game.day) < pa * 1.2 and (ob["units"] as Array).size() < 40:
		if not _reinforce(ob, rng): return
	while WarAI.power(ob, Game.day) > (pa + pb) * 0.9 and (ob["units"] as Array).size() > 1:
		var released: Unit = (ob["units"] as Array).pop_back()
		Army.release(Game, released, "fled")
	var po: float = WarAI.power(ob, Game.day)
	check(po > pa * 1.2 and po <= (pa + pb) * 0.9, "native call fixture must actually be stronger than one patrol and weaker than both")
	if fails > 0: return
	_think_now(ab)
	bb["war_next"] = Game.day + 10.0
	if not _step(w, [a, b, o], 0.01): return
	var wa: Dictionary = ab.get("war", {}); var wbb: Dictionary = bb.get("war", {})
	print("call: a %.1f + b %.1f vs orcs %.1f: a %s, b %s" % [pa, pb, po, wa.get("m", "-"), wbb.get("m", "-")])
	if po > pa:
		check(String(wa.get("m", "")) == "shadow", "a band weaker than its target does not shadow it (%s)" % wa.get("m", "-"))
		check(String(wbb.get("m", "")) == "join" and String(wbb.get("tgt", "")) == o, "the neighbour band was not called")
	# together they go in
	bb["war_next"] = 0.0
	var went := false
	for i in 125:   # up to 2.5 days
		if not _step(w, [a, b, o], 0.02): return
		if not w["warbands"].has(o) or String(ab.get("war", {}).get("m", "")) == "intercept":
			went = true
			break
	check(went, "the gathered bands never attacked")
	# beaten down: home
	var w2: Dictionary = _world(4406)
	if w2.is_empty(): return
	_diplo(w2, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var home := _town_of(w2, "middle_kingdom")
	var h: String = _ai_band( "middle_kingdom", CampaignWorld.nearest_passable(w2, home["pos"] + Vector2(400, 0)), 10, "patrol", rng, {"home": home["id"]})
	if h == "" or fails > 0: return
	var hb: Dictionary = w2["warbands"][h]
	_think_now(hb)
	if not _step(w2, [h], 0.01): return
	var released_survivors: Array = (hb["units"] as Array).slice(4)
	for unit: Unit in released_survivors: Army.release(Game, unit, "fled")
	(hb["units"] as Array).resize(4)
	_think_now(hb)
	if not _step(w2, [h], 0.01): return
	check(String(hb.get("war", {}).get("m", "")) == "home", "a band down to 4 of 10 does not fall back home (%s)" % hb.get("war", {}).get("m", "-"))
	var d0 := (hb["pos"] as Vector2).distance_to(home["pos"])
	if not _step(w2, [h], 1.0): return   # a day of real terrain-limited travel
	var d1 := (hb["pos"] as Vector2).distance_to(home["pos"])
	print("home: %.0f -> %.0f px from home, mode %s" % [d0, d1, hb.get("war", {}).get("m", "-")])
	check(d1 < d0 - 50.0, "the beaten band did not head home")
	# unpaid: home
	var u: String = _ai_band( "middle_kingdom", CampaignWorld.nearest_passable(w2, home["pos"] + Vector2(-400, 0)), 8, "patrol", rng, {"home": home["id"]})
	if u == "" or fails > 0: return
	var ub: Dictionary = w2["warbands"][u]
	_think_now(ub)
	if not _step(w2, [h, u], 0.01): return
	# Move the payer's actual coin into its own town; never assign arrears or mint/drain coin.
	var faction: Dictionary = w2["factions"]["middle_kingdom"]
	var employer: Dictionary = home["econ"]
	var total_coin: float = Barge.holdings(Game)
	var transferred: float = maxf(0.0, float(faction["treasury"]))
	faction["treasury"] = float(faction["treasury"]) - transferred
	employer["treasury"] = float(employer["treasury"]) + transferred
	check(absf(Barge.holdings(Game) - total_coin) < 0.01 and is_zero_approx(float(faction["treasury"])), "native unpaid fixture transfers every payer coin without destroying money")
	if fails > 0: return
	var days_to_payday: float = floorf(Game.day) + 1.01 - Game.day
	if not _step(w2, [h, u], days_to_payday): return
	check(w2["warbands"].has(u), "native unpaid band must survive its first missed payday")
	if not w2["warbands"].has(u): return
	var unpaid: int = 0
	for unit: Unit in ub["units"]:
		if not unit.dead and unit.unpaid_days > 0: unpaid += 1
	check(unpaid > 0 and unpaid >= (ub["units"] as Array).size() * WarAI.UNPAID_SHARE and int(ub.get("unpaid_n", 0)) == unpaid,
		"native unpaid prerequisite failed: actual missed payday and matching per-person/band arrears required; town income may have paid the band")
	if fails > 0: return
	_think_now(ub)
	if not _step(w2, [h, u], 0.01): return
	check(String(ub.get("war", {}).get("m", "")) == "home", "an unpaid band does not fall back home")

# ---------------------------------------------------------------- militia hold the walls (war pick 3)
func _militia() -> void:
	var w: Dictionary = _world(4408)
	if w.is_empty(): return
	_diplo(w, [["middle_kingdom", "orc_horde", Diplomacy.WAR]])
	var rng := RandomNumberGenerator.new(); rng.seed = 13
	var ot := _town_of(w, "orc_horde")
	w["militia"] = {}
	var mid := Militia.ensure(Game, ot["id"], rng)
	check(mid != "" and w["warbands"].has(mid), "native militia fixture needs its actual live band ID")
	if mid == "" or not w["warbands"].has(mid): return
	var mil: Dictionary = w["warbands"][mid]
	check(not (mil["units"] as Array).is_empty(), "native militia has actual mustered defenders")
	if fails > 0: return
	var n0 := (mil["units"] as Array).size()
	var pm := CampaignWorld.band_power(mil["units"])
	check(Militia.sallies(1.25, 1.0) and not Militia.sallies(1.24, 1.0), "the militia sallies at 1.25x the enemy's power, not below")
	check(not WarAI.TARGET_KINDS.has("militia"), "war bands still hunt militia in the field")
	var mk: String = _town_of(w, "middle_kingdom")["id"]
	var gate := CampaignWorld.nearest_passable(w, (ot["pos"] as Vector2) + Vector2(50, 40))
	# (1) an enemy band the militia could match at 0.6x but does not outnumber 1.25x, at the gate: it holds the walls
	var hid: String = _ai_band( "middle_kingdom", gate, 1, "patrol", rng, {"home": mk})
	if hid == "" or fails > 0: return
	var hb: Dictionary = w["warbands"][hid]
	while CampaignWorld.band_power(hb["units"]) < pm / 1.2 and (hb["units"] as Array).size() < 300:
		if not _reinforce(hb, rng): return
	var ph := CampaignWorld.band_power(hb["units"])
	check(pm >= 0.6 * ph and pm < 1.25 * ph, "test setup: militia %.1f vs band %.1f is not between 0.6x and 1.25x" % [pm, ph])
	_think_now(hb)
	var went := false
	var walls := false
	for i in 50:   # a day
		if not _step(w, [hid, mid], 0.02): return
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
	var lid: String = _ai_band( "middle_kingdom", gate, 1, "patrol", rng, {"home": mk})
	if lid == "" or fails > 0: return
	var lb: Dictionary = w["warbands"][lid]
	_purge(w, [mid, lid])
	var pl := CampaignWorld.band_power(lb["units"])
	check(Militia.sallies(pm, pl), "test setup: militia %.1f does not outnumber a lone man %.1f" % [pm, pl])
	var fought := false
	for i in 50:
		if not _step(w, [lid, mid], 0.02): return
		if not w["warbands"].has(lid) or (mil["units"] as Array).size() < n0:
			fought = true
			break
	print("militia vs a band of %d (power %.1f): fought %s; log %s" % [(lb["units"] as Array).size(), pl, fought, (w["log"] as Array).slice(-1)])
	check(fought, "a militia 1.25x stronger did not sally out")
	check(not bool(mil.get("walls", false)) or not w["warbands"].has(lid), "still behind the walls after the threat")

# ---------------------------------------------------------------- peace and HOSTILE
func _peace() -> void:
	for st in [Diplomacy.NEUTRAL, Diplomacy.HOSTILE, Diplomacy.ALLIANCE]:
		var w: Dictionary = _world(4407)
		if w.is_empty(): return
		_diplo(w, [["middle_kingdom", "orc_horde", st]] if st != Diplomacy.NEUTRAL else [])
		if st == Diplomacy.ALLIANCE:
			_force(w, "middle_kingdom", "orc_horde", st, 80.0)
		var rng := RandomNumberGenerator.new(); rng.seed = 12
		var mt := _town_of(w, "middle_kingdom")
		var p := CampaignWorld.nearest_passable(w, mt["pos"] + Vector2(150, 0))
		var h: String = _ai_band( "middle_kingdom", p, 10, "patrol", rng, {"home": mt["id"]})
		if h == "" or fails > 0: return
		var o: String = _ai_band( "orc_horde", CampaignWorld.nearest_passable(w, p + Vector2(200, 0)), 2, "raider", rng, {"home": _town_of(w, "orc_horde")["id"]})
		if o == "" or fails > 0: return
		var ot := _town_of(w, "orc_horde")
		var c: String = _caravan(w, "orc_horde", CampaignWorld.nearest_passable(w, p + Vector2(0, 150)), ot, 2, rng)
		if c == "" or fails > 0: return
		var hb: Dictionary = w["warbands"][h]
		var ever := false
		_think_now(hb)
		for i in 25:
			if not _step(w, [h, o, c], 0.02): return
			if not (hb.get("war", {}) as Dictionary).is_empty():
				ever = true
		var stats: Dictionary = WarAI.state(w)["stats"]
		print("%s: war orders %s, intercepts %d" % [st, ever, int(stats["intercepts"])])
		check(not ever and int(stats["intercepts"]) == 0, "%s: a band went hunting" % st)

# ---------------------------------------------------------------- determinism
func _sig(seed_v: int) -> String:
	if not _within_budget(): return ""
	Game.new_game(seed_v)
	if not _within_budget(): return ""
	var w: Dictionary = Game.world
	var fl: Array = w["diplo"]["factions"]
	for i in fl.size():
		for j in range(i + 1, fl.size()):
			_force(w, fl[i], fl[j], Diplomacy.WAR, -80.0)
	for i in 120:
		if not _within_budget(): return ""
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
	if fails > 0: return
	var b: String = _sig(4410)
	if fails > 0: return
	print("determinism: %s" % a.substr(0, 200))
	check(a == b, "the same seed gave a different war")
	check(int(WarAI.state(Game.world)["stats"]["intercepts"]) + int(WarAI.state(Game.world)["stats"]["shadows"]) > 0, "a 3-day all-out war had no interceptions")
	# save / load mid-war: orders survive with their types, the war goes on
	var orders := {}
	for k in Game.world["warbands"]:
		var war: Dictionary = Game.world["warbands"][k].get("war", {})
		if not war.is_empty():
			orders[k] = "%s>%s" % [war["m"], war["tgt"]]
	check(not orders.is_empty(), "native war save/load prerequisite: at least one actual live war order at the checkpoint")
	if fails > 0: return
	check(Game.save_game(), "native war save request completed successfully")
	Game.wait_save()
	check(bool(Game.save_stats().get("last_ok", false)), "native war save has a successful completion receipt")
	if fails > 0: return
	check(Game.load_game(), "load after a war")
	if fails > 0: return
	var kept := 0
	for k in orders:
		var war: Dictionary = Game.world["warbands"].get(k, {}).get("war", {})
		if not war.is_empty() and "%s>%s" % [war["m"], war["tgt"]] == orders[k] and war["aim"] is Vector2 and war["p0"] is Vector2:
			kept += 1
	print("save/load: %d of %d war orders kept" % [kept, orders.size()])
	check(kept == orders.size(), "war orders lost or mistyped in save/load")
	for i in 20:
		if not _within_budget(): return
		Game.advance_time(0.025, false)
		Game.world["encounter"] = ""

# ---------------------------------------------------------------- per-frame cost
func _perf(tree: SceneTree) -> void:
	if not _within_budget(): return
	Game.new_game(4420)
	if not _within_budget(): return
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
	# A generated world can already exceed forty hunters: release only this scene's excess.
	var excess_ids: Array = w["warbands"].keys()
	excess_ids.sort()
	for id: String in excess_ids:
		if int(hunters.call()) <= 40: break
		if w["warbands"][id]["kind"] in ["patrol", "raider"]: _release_band(w, id)
	for attempt: int in 400:
		if not _within_budget(): return
		if int(hunters.call()) >= 40: break
		var faction: String = str(fids[attempt % fids.size()])
		var id: String = CampaignWorld.spawn_faction_band(Game, faction, rng, false, true)
		check(id != "" and w["warbands"].has(id), "native perf fixture returned no actual field force")
		if id == "" or not w["warbands"].has(id): return
		var valid: Dictionary = NativeForces.registered(Game, w["warbands"][id])
		check(bool(valid["ok"]), "native perf force: " + str(valid.get("reason", "")))
		if fails > 0 or not _support_scene(w, faction): return
	check(int(hunters.call()) == 40, "perf fixture needs exactly forty actual field forces after at most 400 attempts")
	if fails > 0: return
	for i in 20:   # half a day of war first
		if not _within_budget(): return
		Game.advance_time(0.025, false)
		w["encounter"] = ""
		w["party"]["safe_until"] = Game.day + 10.0
	check(int(hunters.call()) == 40, "war performance requires exactly forty actual field forces in every timed sample")
	if fails > 0: return
	for mult in [1, 4]:
		WarAI.usec = 0; WarAI.think_usec = 0; WarAI.astar_usec = 0; WarAI.astar_n = 0; WarAI.prof = {}
		var frames := 600
		var fd: float = mult / 300.0   # map at 60 fps, 5 s per day, speed x1 / x4
		var s0: Dictionary = (WarAI.state(w)["stats"] as Dictionary).duplicate()
		var worst := 0
		var worst_txt := ""
		for i in frames:
			if not _within_budget(): return
			w["party"]["safe_until"] = Game.day + 10.0
			w["encounter"] = ""
			var u0 := WarAI.usec
			var k0 := WarAI.think_usec; var a0 := WarAI.astar_usec; var r0 := int(WarAI.prof.get("retarget", 0))
			Game.day += fd
			check(int(hunters.call()) == 40, "war performance requires exactly forty actual field forces in every timed sample")
			if fails > 0: return
			CampaignWorld.on_time(Game, fd, false)
			check(int(hunters.call()) == 40, "war performance requires exactly forty actual field forces in every timed sample")
			if fails > 0: return
			if WarAI.usec - u0 > worst:
				worst = WarAI.usec - u0
				worst_txt = "think %d us, grid paths %d us, retarget %d us" % [WarAI.think_usec - k0, WarAI.astar_usec - a0, int(WarAI.prof.get("retarget", 0)) - r0]
			if i % 60 == 0:
				await tree.process_frame
		var hn: int = hunters.call()
		var mean_ms: float = WarAI.usec / float(frames) / 1000.0
		var s1: Dictionary = WarAI.state(w)["stats"]
		check(int(s1["thinks"]) > int(s0["thinks"]), "war performance sample must execute native war decisions")
		if fails > 0: return
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
