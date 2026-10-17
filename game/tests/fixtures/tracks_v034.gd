extends RefCounted
## Tracks and sightings on the campaign map (Douglas: "for the bounty how do I know where he is, could you give
## me tracks to him").
##
## Tracks: every moving force (factions, caravans, bandits, monsters) drops a breadcrumb every DROP_EVERY days on
## the world's own time step (CampaignWorld.on_time calls step() once per sub-step; it returns at once between
## drops). A crumb = position, time, head count and heading. Crumbs fade over LIFE days; each force keeps at most
## PER_FORCE crumbs (ring buffer) and the whole map at most GLOBAL_CAP. The company notices crumbs inside its sight
## (PARTY_SIGHT + TRACKER_PX per level of its best Tracker); noticed crumbs stay on the map until they fade.
##
## Sightings: hunted contract targets (HUNTED_KINDS) are not shown on the map unless the company sees them. The
## contract keeps a last-seen report {pos, day, place}: first the employer's word, then towns that see the target
## pass (TOWN_SIGHT) report after REPORT_DELAY days, the company's own eyes, and the target's own trail once it is
## identified (seen by the company, or tracks picked up inside the last-seen circle).
##
## State (saved with the world): w["tracks"] = {next, ver, disc (Vector2), forces: {wid: {f, k, r, mark, c: flat
## [x, y, t, n, ang, seen] * k}}, sight: {wid: {pos, day, place, src, eyes}}, pending: [{wid, pos, day, place, at}]}.
## Drawn by campaign/map_tracks.gd, which redraws only when ver changes.

const DROP_EVERY := 0.125      # [ours, tunable] days between crumbs (3 h)
const LIFE := 2.0              # [ours, tunable] days a crumb stays readable (rain later)
const PER_FORCE := 20          # ring buffer per force (20 x 3 h = 2.5 days > LIFE)
const GLOBAL_CAP := 2400       # crumbs on the whole map
const MIN_MOVE := 10.0         # px: a force that has not moved this far since its last crumb leaves none
const STRIDE := 6              # x, y, t, n, ang, seen
const TRACKER_PX := 18.0       # [ours] extra px of track sight per Tracker level (20 -> +360)
const DISC_MOVE := 30.0        # px the party walks before it looks for tracks again (between drops)
const TOWN_SIGHT := 230.0      # [ours] px: a town sees a target passing this close
const REPORT_DELAY := 0.5      # [ours] days for a town's word to reach the company
const CIRCLE_BASE := 70.0      # [ours] px radius of a fresh last-seen circle
const CIRCLE_PER_DAY := 110.0  # [ours] px the circle grows per day of age (~ a roaming band's daily wander)
const CIRCLE_MAX := 700.0
const NOWHERE := Vector2(-1.0e6, -1.0e6)   # "not looked yet" (the state is saved as JSON: no INF in it)
const HUNTED_KINDS := ["bounty", "hunt", "bandits", "battle", "war"]   # contracts whose target must be found
const STATIC_KINDS := ["den", "camp"]   # targets that sit in their lair: always shown, no circle growth

static var usec := 0   # profiling: microseconds spent in step() (tests read it)

# ================================================================== state
static func state(w: Dictionary) -> Dictionary:
	if not w.has("tracks"):
		w["tracks"] = {"next": 0.0, "ver": 1, "disc": NOWHERE, "forces": {}, "sight": {}, "pending": []}
	return w["tracks"]

static func version(w: Dictionary) -> int:
	var st: Dictionary = w.get("tracks", {})
	return int(st.get("ver", 0))

static func _bump(st: Dictionary) -> void:
	st["ver"] = int(st["ver"]) + 1

## Px around the party in which tracks are noticed.
static func sight_range(game) -> float:
	return CampaignWorld.PARTY_SIGHT + TRACKER_PX * clampi(game.best_skill("tracker"), 0, 20)

# ================================================================== time step
## Called by CampaignWorld.on_time once per sub-step (t = sub-step time). Cheap between drops.
static func step(game, t: float) -> void:
	var t0 := Time.get_ticks_usec()
	var w: Dictionary = game.world
	var st := state(w)
	if t >= float(st["next"]):
		st["next"] = (floor(t / DROP_EVERY) + 1.0) * DROP_EVERY
		_drop(w, st, t)
		_expire(w, st, t)
		_sightings(game, st, t)
		_bump(st)
		discover(game)
	elif game.location == "":
		var disc: Vector2 = st["disc"]
		var ppos: Vector2 = w["party"]["pos"]
		if disc.distance_squared_to(ppos) > DISC_MOVE * DISC_MOVE:
			discover(game)
	usec += Time.get_ticks_usec() - t0

static func _race_of(wb: Dictionary) -> String:
	var units: Array = wb["units"]
	if Monsters.is_monster_band(wb) and not units.is_empty():
		return String(units[0].race)
	return String(DB.factions.get(wb["faction"], {}).get("race", "human"))

## Adds one crumb for force wid (also used by tests). info = {f, k, r}.
static func add_crumb(w: Dictionary, wid: String, info: Dictionary, pos: Vector2, t: float, n: int, ang: float) -> void:
	var forces: Dictionary = state(w)["forces"]
	var rec: Dictionary = forces.get(wid, {})
	if rec.is_empty():
		rec = {"f": info.get("f", ""), "k": info.get("k", ""), "r": info.get("r", "human"), "mark": false, "c": []}
		forces[wid] = rec
	var c: Array = rec["c"]
	c.append_array([pos.x, pos.y, t, float(n), ang, 0.0])
	if c.size() > PER_FORCE * STRIDE:
		rec["c"] = c.slice(STRIDE)

static func _drop(w: Dictionary, st: Dictionary, t: float) -> void:
	var forces: Dictionary = st["forces"]
	for wid in w["warbands"]:
		var wb: Dictionary = w["warbands"][wid]
		if wb["kind"] in STATIC_KINDS:
			continue
		var units: Array = wb["units"]
		if units.is_empty():
			continue
		var pos: Vector2 = wb["pos"]
		var rec: Dictionary = forces.get(wid, {})
		var ang := 0.0
		if not rec.is_empty() and not (rec["c"] as Array).is_empty():
			var c: Array = rec["c"]
			var last := Vector2(c[c.size() - STRIDE], c[c.size() - STRIDE + 1])
			if last.distance_squared_to(pos) < MIN_MOVE * MIN_MOVE:
				continue
			ang = (pos - last).angle()
		else:
			var path: Array = wb["path"]
			if path.is_empty():
				continue   # not moving: no trail yet
			ang = ((path[0] as Vector2) - pos).angle()
		add_crumb(w, wid, {"f": wb["faction"], "k": wb["kind"], "r": _race_of(wb)}, pos, t, units.size(), ang)

static func _expire(w: Dictionary, st: Dictionary, t: float) -> void:
	var forces: Dictionary = st["forces"]
	var total := 0
	for wid in forces.keys():
		var rec: Dictionary = forces[wid]
		var c: Array = rec["c"]
		var cut := 0
		while cut < c.size() and t - float(c[cut + 2]) > LIFE:
			cut += STRIDE
		if cut > 0:
			c = c.slice(cut)
			rec["c"] = c
		if c.is_empty() and not w["warbands"].has(wid):
			forces.erase(wid)
			continue
		total += c.size() / STRIDE
	# global cap: drop the oldest crumbs on the map first (rare: only with very many forces)
	while total > GLOBAL_CAP:
		var oldest := ""; var ot := INF
		for wid in forces:
			var c: Array = forces[wid]["c"]
			if not c.is_empty() and float(c[2]) < ot:
				ot = float(c[2]); oldest = wid
		if oldest == "":
			break
		forces[oldest]["c"] = (forces[oldest]["c"] as Array).slice(STRIDE)
		total -= 1

## Marks crumbs inside the company's track sight as noticed. Identifies the hunted target's trail and follows it.
static func discover(game) -> void:
	var w: Dictionary = game.world
	var st := state(w)
	var ppos: Vector2 = w["party"]["pos"]
	st["disc"] = ppos
	if game.location != "":
		return
	var r := sight_range(game)
	var r2 := r * r
	var tgt := hunted_target(game)
	var changed := _company_watch(game, st, float(game.day))
	var sight: Dictionary = st["sight"].get(tgt, {}) if tgt != "" else {}
	for wid in st["forces"]:
		var rec: Dictionary = st["forces"][wid]
		var c: Array = rec["c"]
		var i := 0
		while i < c.size():
			if float(c[i + 5]) == 0.0:
				var p := Vector2(c[i], c[i + 1])
				if p.distance_squared_to(ppos) <= r2:
					c[i + 5] = 1.0
					changed = true
					if wid == tgt:
						if not rec["mark"] and not sight.is_empty() and (bool(sight.get("eyes", false)) \
								or p.distance_to(sight["pos"]) <= circle_radius(game, sight)):
							rec["mark"] = true   # seen him, or his tracks picked up inside the last-seen circle
						if rec["mark"] and float(c[i + 2]) > float(sight.get("day", -INF)):
							sight = _set_sight(st, wid, p, float(c[i + 2]), CampaignWorld.nearest_town_name(w, p), "tracks")
			i += STRIDE
	if changed:
		_bump(st)

## The company sees the hunted target itself: exact report, trail identified.
static func _company_watch(game, st: Dictionary, t: float) -> bool:
	var w: Dictionary = game.world
	var tgt := hunted_target(game)
	if tgt == "" or game.location != "":
		return false
	var wb: Dictionary = w["warbands"][tgt]
	if (wb["pos"] as Vector2).distance_to(w["party"]["pos"]) >= CampaignWorld.PARTY_SIGHT:
		return false
	_set_sight(st, tgt, wb["pos"], t, CampaignWorld.nearest_town_name(w, wb["pos"]), "company")
	st["sight"][tgt]["eyes"] = true
	var rec: Dictionary = st["forces"].get(tgt, {})
	if not rec.is_empty():
		rec["mark"] = true
	return true

static func _set_sight(st: Dictionary, wid: String, pos: Vector2, day: float, place: String, src: String) -> Dictionary:
	var old: Dictionary = st["sight"].get(wid, {})
	var s := {"pos": pos, "day": day, "place": place, "src": src, "eyes": bool(old.get("eyes", false))}
	st["sight"][wid] = s
	return s

# ================================================================== sightings
## Active contract's target id when it is a hunted kind and the target band exists, else "".
static func hunted_target(game) -> String:
	var c: Dictionary = game.contract
	if c.is_empty() or c.get("state", "") != "active" or not String(c.get("kind", "")) in HUNTED_KINDS:
		return ""
	var tgt := String(c.get("target_id", ""))
	return tgt if game.world.get("warbands", {}).has(tgt) else ""

## True when the map should not show warband wid unless the company can see it (CampaignWorld.visible_warbands).
static func hides_target(game, wid: String) -> bool:
	if wid != hunted_target(game):
		return false
	return not String(game.world["warbands"][wid]["kind"]) in STATIC_KINDS

static func _sightings(game, st: Dictionary, t: float) -> void:
	var w: Dictionary = game.world
	var tgt := hunted_target(game)
	# forget reports about bands that are gone
	for wid in st["sight"].keys():
		if wid != tgt and not w["warbands"].has(wid):
			st["sight"].erase(wid)
	if tgt == "":
		st["pending"] = []
		return
	var wb: Dictionary = w["warbands"][tgt]
	var pos: Vector2 = wb["pos"]
	if not st["sight"].has(tgt):
		_employer_word(game, st, tgt, t)
	if wb["kind"] in STATIC_KINDS:
		_set_sight(st, tgt, pos, t, CampaignWorld.nearest_town_name(w, pos), "lair")
		return
	_company_watch(game, st, t)
	# towns that see him pass send word (one report per REPORT_DELAY at most)
	var pend: Array = st["pending"]
	var last_rep := -INF
	for p in pend:
		if p["wid"] == tgt:
			last_rep = maxf(last_rep, float(p["day"]))
	if t - last_rep >= REPORT_DELAY:
		var best := ""; var bd := TOWN_SIGHT
		for tid in w["towns"]:
			var d: float = (w["towns"][tid]["pos"] as Vector2).distance_to(pos)
			if d < bd:
				bd = d; best = tid
		if best != "":
			pend.append({"wid": tgt, "pos": pos, "day": t, "place": w["towns"][best]["name"], "at": t + REPORT_DELAY})
	# reports that have arrived
	var keep := []
	for p in pend:
		if float(p["at"]) > t:
			keep.append(p)
			continue
		if p["wid"] != tgt:
			continue
		var cur: Dictionary = st["sight"].get(tgt, {})
		if float(p["day"]) > float(cur.get("day", -INF)):
			_set_sight(st, tgt, p["pos"], float(p["day"]), p["place"], "town")
			CampaignWorld.log_event(game, "Word from %s: %s was seen nearby %s." % [p["place"], target_name(game), age_words(t - float(p["day"]))])
	st["pending"] = keep

## First report, from the employer: where the target was about half a day ago (its oldest crumb when it has one).
static func _employer_word(game, st: Dictionary, tgt: String, t: float) -> void:
	var w: Dictionary = game.world
	var pos: Vector2 = w["warbands"][tgt]["pos"]
	var day := t
	var rec: Dictionary = st["forces"].get(tgt, {})
	if not rec.is_empty() and not (rec["c"] as Array).is_empty():
		var c: Array = rec["c"]
		var i := 0
		while i + STRIDE < c.size() and t - float(c[i + 2]) > 0.5:
			i += STRIDE
		pos = Vector2(c[i], c[i + 1]); day = float(c[i + 2])
	_set_sight(st, tgt, pos, day, CampaignWorld.nearest_town_name(w, pos), "employer")

## Makes sure the active hunted contract has a last-seen report (called from the status text too).
static func ensure_sighting(game) -> void:
	var tgt := hunted_target(game)
	if tgt == "":
		return
	var st := state(game.world)
	if not st["sight"].has(tgt):
		_employer_word(game, st, tgt, float(game.day))
		_bump(st)

static func circle_radius(game, s: Dictionary) -> float:
	var age := maxf(0.0, float(game.day) - float(s.get("day", game.day)))
	if String(s.get("src", "")) == "lair":
		return CIRCLE_BASE
	return minf(CIRCLE_MAX, CIRCLE_BASE + CIRCLE_PER_DAY * age)

## {pos, radius, age, place, src} for the active hunted target, {} when none.
static func last_seen(game) -> Dictionary:
	var tgt := hunted_target(game)
	if tgt == "":
		return {}
	ensure_sighting(game)
	var s: Dictionary = state(game.world)["sight"].get(tgt, {})
	if s.is_empty():
		return {}
	return {"pos": s["pos"], "radius": circle_radius(game, s), "age": float(game.day) - float(s["day"]),
		"place": s["place"], "src": s["src"], "wid": tgt}

## True when the company can see the hunted target right now.
static func target_in_sight(game) -> bool:
	var tgt := hunted_target(game)
	if tgt == "" or game.location != "":
		return false
	var w: Dictionary = game.world
	return (w["warbands"][tgt]["pos"] as Vector2).distance_to(w["party"]["pos"]) < CampaignWorld.PARTY_SIGHT

static func target_name(game) -> String:
	var tgt := hunted_target(game)
	var wb: Dictionary = game.world.get("warbands", {}).get(tgt, {})
	if wb.is_empty():
		return "the target"
	if String(wb.get("named", "")) != "":
		return String(wb["named"])
	var k := Monsters.kind_text(wb)
	if k != "":
		return "the " + k
	return "the band of %s" % DB.races.get(_race_of(wb), {}).get("plural", "warriors")

static func age_words(age: float) -> String:
	if age < 1.0 / 24.0:
		return "within the hour"
	if age < 0.75:
		var h := maxi(1, int(round(age * 24.0)))
		return "%d hour%s ago" % [h, "" if h == 1 else "s"]
	var d := maxi(1, int(round(age)))
	return "about a day ago" if d == 1 else "about %d days ago" % d

## Suffix for Contracts.status_text: " | last seen near Redton, about 2 days ago".
static func status_suffix(game) -> String:
	var ls := last_seen(game)
	if ls.is_empty():
		return ""
	if target_in_sight(game):
		return " | in sight"
	if ls["src"] == "lair":
		return " | at its lair near %s" % ls["place"]
	return " | last seen near %s, %s" % [ls["place"], age_words(float(ls["age"]))]

## Where tapping the contract line centres the map: the target when seen, else the last-seen spot. INF if none.
static func focus_point(game) -> Vector2:
	var tgt := hunted_target(game)
	if tgt == "":
		var any := String(game.contract.get("target_id", ""))
		if game.world.get("warbands", {}).has(any):
			return game.world["warbands"][any]["pos"]   # escort / defend / lair: the target is on the map anyway
		var tid := String(game.contract.get("town_id", ""))
		return game.world["towns"][tid]["pos"] if game.world.get("towns", {}).has(tid) else Vector2.INF
	if target_in_sight(game) or not hides_target(game, tgt):
		return game.world["warbands"][tgt]["pos"]
	var ls := last_seen(game)
	return ls["pos"] if not ls.is_empty() else Vector2.INF

# ================================================================== reading a track
## Nearest noticed crumb within r px of p: [wid, index] or [].
static func track_at(game, p: Vector2, r: float) -> Array:
	var st: Dictionary = game.world.get("tracks", {})
	if st.is_empty():
		return []
	var best := []; var bd := r * r
	for wid in st["forces"]:
		var c: Array = st["forces"][wid]["c"]
		var i := 0
		while i < c.size():
			if float(c[i + 5]) != 0.0:
				var d := Vector2(c[i], c[i + 1]).distance_squared_to(p)
				if d <= bd:
					bd = d; best = [wid, i / STRIDE]
			i += STRIDE
	return best

## Index of the crumb of force wid dropped at time t (crumb indices shift as the ring buffer turns), -1 if gone.
static func index_of(game, wid: String, t: float) -> int:
	var c: Array = game.world.get("tracks", {}).get("forces", {}).get(wid, {}).get("c", [])
	var i := 0
	while i < c.size():
		if absf(float(c[i + 2]) - t) < 0.0001:
			return i / STRIDE
		i += STRIDE
	return -1

## Time a crumb was dropped (pairs with index_of).
static func crumb_time(game, wid: String, idx: int) -> float:
	var c: Array = game.world.get("tracks", {}).get("forces", {}).get(wid, {}).get("c", [])
	return float(c[idx * STRIDE + 2]) if idx * STRIDE + 2 < c.size() else -1.0

const DIRS :=["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

static func direction_word(ang: float, skill: int) -> String:
	if skill < 2:
		return ["east", "south", "west", "north"][posmod(int(round(ang / (PI / 2.0))), 4)]
	return DIRS[posmod(int(round(ang / (PI / 4.0))), 8)]

static func _what(rec: Dictionary, skill: int) -> String:
	var race := String(rec.get("r", "human"))
	var beast := DB.is_creature(race)
	var s := ""
	if skill < 3:
		s = "four-legged beasts" if beast else "two-legged walkers"
	elif skill < 9:
		if beast:
			s = "beasts"
		elif race in ["orc", "goblin", "troll"]:
			s = "greenskins"
		elif race == "dwarf":
			s = "short, heavy-booted walkers"   # v0.012
		else:
			s = "men"
	else:
		s = String(DB.races.get(race, {}).get("plural", race))
	if rec.get("k", "") == "caravan":
		s += " with wagons"
	return s

static func _age_text(age: float, skill: int) -> String:
	if skill < 4:
		return "fresh" if age < 0.33 else ("a day old at most" if age < 1.0 else "old")
	if skill < 10:
		return "a few hours old" if age < 0.25 else ("less than a day old" if age < 1.0 else "a day or two old")
	if age < 1.0:
		return "about %d hours old" % maxi(1, int(round(age * 24.0)))
	return "about %.1f days old" % age

static func _count_text(n: int, skill: int) -> String:
	if skill < 4:
		return "a few" if n <= 3 else ("several" if n <= 8 else "many")
	if skill < 10:
		return CampaignWorld.approx_count(n)
	return "about %d" % n

## What the company reads from crumb idx of force wid (its best Tracker decides how precisely):
## {age_text, count_text, what_text, dir_text, mark, text, title}.
static func describe(game, wid: String, idx: int) -> Dictionary:
	var st: Dictionary = game.world.get("tracks", {})
	var rec: Dictionary = st.get("forces", {}).get(wid, {})
	var c: Array = rec.get("c", [])
	var i := idx * STRIDE
	if i + STRIDE > c.size():
		return {}
	var skill: int = game.best_skill("tracker")
	var age := float(game.day) - float(c[i + 2])
	var out := {"age_text": _age_text(age, skill), "count_text": _count_text(int(c[i + 3]), skill),
		"what_text": _what(rec, skill), "dir_text": direction_word(float(c[i + 4]), skill),
		"mark": bool(rec.get("mark", false)) and wid == hunted_target(game), "pos": Vector2(c[i], c[i + 1])}
	out["title"] = "Tracks of %s" % target_name(game) if out["mark"] else "Tracks"
	out["text"] = "The tracks are %s. %s %s passed here, heading %s.%s" % [out["age_text"],
		String(out["count_text"]).capitalize(), out["what_text"], out["dir_text"],
		"\nThese are the tracks of %s." % target_name(game) if out["mark"] else ""]
	if skill < 4:
		out["text"] += "\n(A better tracker would read more.)"
	return out

## Where "Follow" sends the company: a little past the newest noticed crumb of that trail.
static func follow_point(game, wid: String) -> Vector2:
	var c: Array = game.world.get("tracks", {}).get("forces", {}).get(wid, {}).get("c", [])
	var i := c.size() - STRIDE
	while i >= 0:
		if float(c[i + 5]) != 0.0:
			return Vector2(c[i], c[i + 1]) + Vector2.from_angle(float(c[i + 4])) * 80.0
		i -= STRIDE
	return Vector2.INF

# ================================================================== save / load
## JSON turns ints into floats and Vector2 comes back through Game._deserialize; restore the rest.
static func after_load(game) -> void:
	var w: Dictionary = game.world
	if not w.has("tracks"):
		return
	var st: Dictionary = w["tracks"]
	st["ver"] = int(st.get("ver", 1)) + 1
	st["next"] = float(st.get("next", 0.0))
	st["disc"] = NOWHERE
	for wid in st.get("forces", {}):
		var rec: Dictionary = st["forces"][wid]
		rec["mark"] = bool(rec.get("mark", false))
	for wid in st.get("sight", {}):
		var s: Dictionary = st["sight"][wid]
		s["day"] = float(s["day"]); s["eyes"] = bool(s.get("eyes", false))
	if not st.has("pending"):
		st["pending"] = []
