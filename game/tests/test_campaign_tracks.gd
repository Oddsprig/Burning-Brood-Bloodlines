extends RefCounted
## Tracks and sightings (campaign/tracks.gd, campaign/map_tracks.gd):
## - a moving force leaves breadcrumbs (time, count, heading) on the time step, and they expire after Tracks.LIFE
## - the company notices tracks only inside sight + Tracker range
## - reading a track (the tap query) gives age / count / kind / heading text, vaguer for a poor tracker
## - a bounty target is hidden out of sight; the contract shows a last-seen circle that grows with age and moves
##   when a town reports him; the company's own eyes and his tracks inside the circle mark his trail
## - save/load round trip of tracks and sightings
## - per-frame cost of the tracks system on a 30-band map (step + layer) stays < 0.1 ms mean

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _advance(days: float, step: float = 0.05) -> void:
	var w: Dictionary = Game.world
	var n := int(round(days / step))
	for i in n:
		w["party"]["safe_until"] = Game.day + 10.0
		w["encounter"] = ""
		Game.advance_time(step, false)
		w["encounter"] = ""

func _skill_all(lvl: int) -> void:
	for u in Game.company:
		u.skills["tracker"] = 0
	if lvl > 0:
		Game.company[0].skills["tracker"] = lvl

## Passable point far from every town and from the party.
func _lonely_point(w: Dictionary, avoid: Vector2) -> Vector2:
	var best := Vector2.ZERO; var bd := -1.0
	for cy in range(2, WorldGen.H - 2, 3):
		for cx in range(2, WorldGen.W - 2, 3):
			var p := WorldGen.cell_center(Vector2i(cx, cy))
			if not CampaignWorld.passable(w, p) or p.distance_to(avoid) < CampaignWorld.PARTY_SIGHT + 150.0:
				continue
			var md := INF
			for tid in w["towns"]:
				md = minf(md, (w["towns"][tid]["pos"] as Vector2).distance_to(p))
			if md > bd:
				bd = md; best = p
	return best

func run(tree: SceneTree) -> int:
	Game.new_game(777)
	Game.contract = {}
	var w: Dictionary = Game.world
	_skill_all(0)
	# ---------------------------------------------------------------- breadcrumbs
	_advance(1.0)
	var st: Dictionary = w["tracks"]
	var wid := ""
	for k in st["forces"]:
		if w["warbands"].has(k) and (st["forces"][k]["c"] as Array).size() >= 4 * Tracks.STRIDE:
			wid = k; break
	check(wid != "", "no moving force left a trail of 4+ crumbs in a day (%d forces)" % st["forces"].size())
	if wid != "":
		var c: Array = st["forces"][wid]["c"]
		var S := Tracks.STRIDE
		var ok_t := true; var ok_dir := true
		for i in range(S, c.size(), S):
			var dt := float(c[i + 2]) - float(c[i + 2 - S])
			if dt < Tracks.DROP_EVERY - CampaignWorld.STEP - 0.001:   # drops land on the sub-step grid
				ok_t = false
			var mv := Vector2(c[i], c[i + 1]) - Vector2(c[i - S], c[i + 1 - S])
			if absf(angle_difference(mv.angle(), float(c[i + 4]))) > 0.01:
				ok_dir = false
		check(ok_t, "crumbs closer together than the drop interval")
		check(ok_dir, "crumb heading is not the direction actually walked")
		check(int(c[3]) == (w["warbands"][wid]["units"] as Array).size(), "crumb head count")
		var last := Vector2(c[c.size() - S], c[c.size() - S + 1])
		check(last.distance_to(w["warbands"][wid]["pos"]) < 120.0, "last crumb far from the force (%.0f px)" % last.distance_to(w["warbands"][wid]["pos"]))
		print("force %s (%s): %d crumbs over a day" % [wid, w["warbands"][wid]["kind"], c.size() / S])
		CampaignWorld.remove_warband(Game, wid)
		_advance(Tracks.LIFE + 0.5)
		check(not st["forces"].has(wid), "a dead force's trail did not expire")
		var oldest := INF
		for k in st["forces"]:
			var cc: Array = st["forces"][k]["c"]
			if not cc.is_empty():
				oldest = minf(oldest, float(cc[2]))
			check(cc.size() <= Tracks.PER_FORCE * S, "ring buffer over its cap")
		check(Game.day - oldest <= Tracks.LIFE + Tracks.DROP_EVERY + 0.01, "a crumb outlived Tracks.LIFE (%.2f days)" % (Game.day - oldest))
	# ---------------------------------------------------------------- noticed only inside sight + tracker range
	w.erase("tracks")
	st = Tracks.state(w)
	var P: Vector2 = w["party"]["pos"]
	var info := {"f": "orc_horde", "k": "raider", "r": "orc"}
	Tracks.add_crumb(w, "tA", info, P + Vector2(CampaignWorld.PARTY_SIGHT - 20.0, 0), Game.day - 0.1, 5, 0.0)
	Tracks.add_crumb(w, "tB", info, P + Vector2(0, CampaignWorld.PARTY_SIGHT + 120.0), Game.day - 0.1, 5, PI / 2.0)
	Tracks.discover(Game)
	check(float(st["forces"]["tA"]["c"][5]) == 1.0, "track inside sight not noticed")
	check(float(st["forces"]["tB"]["c"][5]) == 0.0, "track beyond sight noticed with no tracker")
	check(Tracks.track_at(Game, P + Vector2(0, CampaignWorld.PARTY_SIGHT + 120.0), 12.0).is_empty(), "unnoticed track tappable")
	_skill_all(10)
	Tracks.discover(Game)
	check(float(st["forces"]["tB"]["c"][5]) == 1.0, "Tracker 10 should extend track sight by %.0f px" % (Tracks.TRACKER_PX * 10))
	# ---------------------------------------------------------------- reading a track (tap query)
	var hit := Tracks.track_at(Game, P + Vector2(CampaignWorld.PARTY_SIGHT - 25.0, 3.0), 12.0)
	check(hit.size() == 2 and hit[0] == "tA", "tap near a noticed track should hit it")
	var d := Tracks.describe(Game, "tA", 0)
	print("tracker 10: ", d.get("text", ""))
	check(d.get("dir_text", "") == "east" and d.get("what_text", "") == "orcs" and d.get("count_text", "") == "about 5", "skilled read: %s" % str(d))
	check(String(d.get("age_text", "")).contains("hours"), "skilled age: %s" % d.get("age_text", ""))
	var dB := Tracks.describe(Game, "tB", 0)
	check(dB.get("dir_text", "") == "south", "heading PI/2 should read south, got %s" % dB.get("dir_text", ""))
	_skill_all(0)
	var d0 := Tracks.describe(Game, "tA", 0)
	print("tracker 0: ", d0.get("text", ""))
	check(d0.get("what_text", "") == "two-legged walkers" and d0.get("count_text", "") == "several", "unskilled read is vaguer: %s" % str(d0))
	check(String(d0.get("text", "")).contains("heading east"), "text names the heading")
	# ---------------------------------------------------------------- bounty: last seen circle, town reports
	w.erase("tracks")
	_skill_all(0)
	P = w["party"]["pos"]
	var lonely := _lonely_point(w, P)
	var tw := CampaignWorld.spawn_warband(Game, "orc_horde", lonely, 4, "contract", RandomNumberGenerator.new(), {"named": "Wulf Gallowsbird"})
	var tb: Dictionary = w["warbands"][tw]
	tb["pos"] = lonely
	tb["rest_until"] = 1.0e9   # frozen: the test moves him by hand
	var home: String = w["start_town"]
	Game.contract = {"id": "tc1", "kind": "bounty", "state": "active", "target_id": tw, "town_id": home,
		"employer": w["towns"][home]["faction"], "title": "Bounty: Wulf Gallowsbird", "pay": 100, "base_pay": 100,
		"deadline_day": Game.day + 20.0, "accepted_day": Game.day}
	check(not CampaignWorld.visible_warbands(Game).has(tw), "a bounty target out of sight should be hidden")
	var ls := Tracks.last_seen(Game)
	check(not ls.is_empty() and (ls["pos"] as Vector2).distance_to(lonely) < 1.0, "employer's last-seen spot")
	var st_text := Contracts.status_text(Game)
	print(st_text)
	check(st_text.contains("last seen near"), "status line has no last-seen text")
	check(Tracks.focus_point(Game).distance_to(lonely) < 1.0, "tapping the contract line should centre on the last-seen spot")
	var r0: float = ls["radius"]
	_advance(0.5)
	var r1: float = Tracks.last_seen(Game)["radius"]
	check(r1 > r0 + 30.0, "circle should grow with age (%.0f -> %.0f)" % [r0, r1])
	# he passes a town far from the company: word arrives after the delay
	var far_town := ""
	var bestd := 0.0
	for tid in w["towns"]:
		var dd: float = (w["towns"][tid]["pos"] as Vector2).distance_to(w["party"]["pos"])
		if dd > bestd:
			bestd = dd; far_town = tid
	var tpos: Vector2 = w["towns"][far_town]["pos"]
	tb["pos"] = CampaignWorld.nearest_passable(w, tpos + Vector2(60, 0))
	var seen_day := float(Game.day)
	_advance(0.2)
	check(Tracks.last_seen(Game)["pos"].distance_to(lonely) < 1.0, "the town's word arrived without delay")
	_advance(0.6)
	var ls2 := Tracks.last_seen(Game)
	print(Contracts.status_text(Game))
	check(ls2["place"] == w["towns"][far_town]["name"], "sighting place should be the town that saw him (%s)" % ls2["place"])
	check((ls2["pos"] as Vector2).distance_to(tpos) < Tracks.TOWN_SIGHT, "sighting moved to the town")
	check(float(Game.day) - float(ls2["age"]) >= seen_day - 0.01, "sighting is newer")
	check(float(ls2["radius"]) < r1 + 200.0, "a fresh report shrinks the circle again")
	var lg: Array = w["log"]
	check(String(lg[-1]).contains("Word from") or "\n".join(lg).contains("Word from %s" % ls2["place"]), "town report not logged")
	# the company sees him: exact sighting, trail marked
	tb["rest_until"] = 0.0
	tb["pos"] = lonely
	tb["path"] = []
	w["party"]["pos"] = CampaignWorld.nearest_passable(w, lonely + Vector2(80, 0))
	_advance(0.05)
	check(CampaignWorld.visible_warbands(Game).has(tw), "target in sight should show")
	check(Tracks.status_suffix(Game).contains("in sight"), "status says in sight")
	for i in 12:
		w["party"]["pos"] = CampaignWorld.nearest_passable(w, (tb["pos"] as Vector2) + Vector2(60, 0))
		_advance(0.05)
	var trec: Dictionary = w["tracks"]["forces"].get(tw, {})
	check(not trec.is_empty() and trec["mark"], "trail of a target the company has seen should be marked")
	if not trec.is_empty():
		var hidx := (trec["c"] as Array).size() / Tracks.STRIDE - 1
		var dm := Tracks.describe(Game, tw, hidx)
		print(dm.get("title", ""), ": ", dm.get("text", ""))
		check(dm.get("mark", false) and String(dm.get("title", "")).contains("Wulf"), "marked track names him")
	# tracks picked up inside the circle mark a trail the company never saw
	trec["mark"] = false
	w["tracks"]["sight"][tw]["eyes"] = false
	var sp: Vector2 = w["tracks"]["sight"][tw]["pos"]
	Tracks.add_crumb(w, tw, {"f": "orc_horde", "k": "contract", "r": "orc"}, sp + Vector2(10, 0), Game.day, 4, 0.0)
	w["party"]["pos"] = sp + Vector2(40, 0)
	tb["pos"] = sp + Vector2(CampaignWorld.PARTY_SIGHT + 400.0, 0)   # out of sight: only his tracks
	Tracks.discover(Game)
	check(trec["mark"], "his tracks inside the last-seen circle should mark his trail")
	# ---------------------------------------------------------------- the map screen: contract-line tap, track tap
	CampaignWorld.stop_travel(Game)
	var map: Node = load("res://campaign/world_map.tscn").instantiate()
	tree.root.add_child.call_deferred(map)
	await tree.process_frame
	await tree.process_frame
	var fp: Vector2 = map.tracks_layer.center_on_contract()
	check(fp != Vector2.INF and (map.cam.position as Vector2).distance_to(fp) < 1.0, "contract-line tap should centre the camera")
	map._tap(sp + Vector2(10, 0))
	check(map.selected.get("kind", "") == "track" and String(map.info_body.text).contains("heading"), "tapping a track shows its reading: %s" % map.info_body.text)
	print("map tap: ", map.info_title.text, " / ", map.info_body.text.replace("\n", " "))
	map.queue_free()
	await tree.process_frame
	w["encounter"] = ""
	# ---------------------------------------------------------------- save / load
	var n_before := 0
	for k in w["tracks"]["forces"]:
		n_before += (w["tracks"]["forces"][k]["c"] as Array).size()
	var sight_before: Dictionary = w["tracks"]["sight"][tw].duplicate()
	Game.save_game()
	Game.world = {}
	Game.contract = {}
	check(Game.load_game(), "load")
	w = Game.world
	var n_after := 0
	for k in w["tracks"]["forces"]:
		n_after += (w["tracks"]["forces"][k]["c"] as Array).size()
	check(n_after == n_before and n_before > 0, "crumbs lost in save/load (%d -> %d)" % [n_before, n_after])
	var sa: Dictionary = w["tracks"]["sight"].get(tw, {})
	check(not sa.is_empty() and sa["pos"] is Vector2 and (sa["pos"] as Vector2).distance_to(sight_before["pos"]) < 0.01 \
		and absf(float(sa["day"]) - float(sight_before["day"])) < 0.0001, "sighting not restored")
	check(typeof(w["tracks"]["forces"][tw]["mark"]) == TYPE_BOOL and w["tracks"]["forces"][tw]["mark"], "mark flag not restored")
	check(Tracks.last_seen(Game).get("wid", "") == tw, "contract last-seen after load")
	_advance(0.3)
	# ---------------------------------------------------------------- per-frame cost, 30 bands
	Game.new_game(31337)
	Game.contract = {}
	w = Game.world
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var fids := ["middle_kingdom", "orc_horde", "goblin_warren", "northern_clans", "moon_court"]
	while w["warbands"].size() < 30:
		CampaignWorld.spawn_faction_band(Game, fids[w["warbands"].size() % fids.size()], rng)
	_skill_all(20)
	var far := ""
	bestd = 0.0
	for tid in w["towns"]:
		var dd2: float = (w["towns"][tid]["pos"] as Vector2).distance_to(w["party"]["pos"])
		if dd2 > bestd:
			bestd = dd2; far = tid
	CampaignWorld.set_travel(Game, w["towns"][far]["pos"])
	var layer: Node2D = load("res://campaign/map_tracks.gd").new()
	tree.root.add_child.call_deferred(layer)   # the runner is still inside its own _ready
	await tree.process_frame
	layer.setup(null)
	_advance(1.0)   # a day of trails first
	for mult in [1, 4]:
		Tracks.usec = 0
		layer.usec = 0
		var frames := 600
		var fd: float = mult / 300.0   # map at 60 fps, 5 s per day, speed x1 / x4
		var draws0: int = layer.draws
		for i in frames:
			w["party"]["safe_until"] = Game.day + 10.0
			w["encounter"] = ""
			Game.day += fd
			CampaignWorld.on_time(Game, fd, false)
			await tree.process_frame
		var crumbs := 0
		for k in w["tracks"]["forces"]:
			crumbs += (w["tracks"]["forces"][k]["c"] as Array).size() / Tracks.STRIDE
		var mean_ms: float = (Tracks.usec + layer.usec) / float(frames) / 1000.0
		print("tracks per frame x%d: mean %.4f ms (step %.4f, layer %.4f), %d bands, %d crumbs, %d redraws in %d frames" % [mult, mean_ms,
			Tracks.usec / float(frames) / 1000.0, layer.usec / float(frames) / 1000.0, w["warbands"].size(), crumbs, layer.draws - draws0, frames])
		check(mean_ms < 0.1, "tracks system too slow per frame at x%d (%.4f ms)" % [mult, mean_ms])
	layer.queue_free()
	return fails
