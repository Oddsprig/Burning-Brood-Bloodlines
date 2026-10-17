class_name WarAI
extends RefCounted
## War interception (Douglas: "factions at war should intercept each other's forces").
##
## Field bands (patrols, raiders; a marching war band only for what it sees) of a faction at WAR (diplomacy)
## seek out enemy forces: armies, war bands, caravans and arms-contract convoys (not town militia: they hold the
## walls unless they outnumber the enemy 1.25x, militia.gd).
## - Truce (war pick 2): a pair in the truce after a peace is not at WAR, so nothing here; Diplomacy.fights is false.
## - What a band knows: forces in its SIGHT; fresh enemy tracks it crosses (campaign/tracks.gd breadcrumbs, the
##   trail is read to its newest crumb); word of the enemy: sightings by its faction's towns (TOWN_SIGHT) and by
##   its other bands, reaching the faction REPORT_DELAY later and stale after INTEL_LIFE.
## - What it does: weighs its power (CampaignWorld.band_power, cached) plus the bands that would join the clash
##   against the target's; attacks (intercept) when favourable, shadows and calls nearby allied bands (same
##   faction or ALLIANCE, also at war with the target) when close, avoids a much stronger enemy army; goes home
##   when beaten down below HOME_SHARE of the men it set out with, or when most of its men are unpaid (army.gd).
## - Interception leads the target: the band heads for the first point of the target's own path it can reach
##   before the target does (lead_point), not the target's current spot. It gives up after GIVE_UP_DAYS or LEASH px.
## - Peace: nothing. HOSTILE (not war): nothing here, the old fight-on-contact rule only.
## - Fights resolve through CampaignWorld._warband_clashes as before (Loot.spoils via ArmsTrade.field, etc.);
##   bands committed to the same target close by add their power there (pack_power), like Diplomacy.ally_power.
## - The company is not a faction: bands hostile to it (standing <= -50) chase it with the same lead
##   (CampaignWorld._move_warbands "chase").
##
## Cost (test_campaign_war: 40 hunting bands, every realm at war, ~0.08 ms per map frame at x1):
## - decisions per band every THINK days (staggered by id), at most _budget per world sub-step (the rest wait a
##   sub-step), over the bands in a coarse grid around it (GRID, rebuilt every GRID_AGE); band power counted once
##   and cached (power); a band without orders and no decision due costs two lookups a frame;
## - steering on a STEER timer: lead_point, then the old path's end is bent or extended when the line is clear;
##   a grid path (grid_path: the A* with a cheap string-pull) only when that fails. No per-frame pathfinding.
## - town watch: one town per WATCH / towns days. CampaignWorld walks the band (WarAI returns the pace).
## State (saved): wb["war"] = {m, tgt, t0, p0, aim, steer, called, lead, wait}, wb["war_next"], wb["n0"],
## wb["pw"]/["pw_n"]/["pw_t"] (power count); w["war"] = {intel {fid: {wid: [x, y, day, n, hx, hy, at]}}, wnext, wi,
## stats, news [{day, text}], avg {fid: power per man}}.

const THINK := 0.25          # [ours] days between a band's decisions (6 h; ~45 px of marching), staggered per band
const MIN_THINKS := 2         # [ours] decisions per world sub-step at least (more at big time steps: bands x dt / THINK x 1.5)
const STEER := 0.05          # [ours] days between re-aims while closing (1.2 h); a third of that when close
const SIGHT := 320.0         # [ours] px a field band sees enemy forces (WARBAND_SIGHT is 300 for the company)
const HEARD := 900.0         # [ours] px: word of an enemy worth marching on
const TRACK_FRESH := 0.6     # [ours] days: tracks younger than this are followed
const TRACK_LEAD := 80.0     # px past the newest crumb, along its heading (as Tracks.follow_point)
const INTEL_LIFE := 1.25     # [ours] days a sighting stays worth acting on
const WATCH := 0.25          # [ours] days for every town to look around once (one town at a time)
const TOWN_SIGHT := 230.0    # px: a town sees forces passing this close (= Tracks.TOWN_SIGHT)
const REPORT_DELAY := 0.25   # [ours] days for word to reach the faction's bands
const ATTACK := 1.25         # [ours] attack when own power (+ bands joining) >= ATTACK x theirs (clash odds ~61%, not a coin toss)
const SHADOW := 0.6          # [ours] ATTACK > ratio >= SHADOW: shadow and call allies; below: avoid armies
const SHADOW_DIST := 190.0   # [ours] px a shadowing band keeps from its target
const AVOID_DIST := 260.0    # [ours] px: a stronger enemy army closer than this is avoided
const AVOID_RUN := 260.0     # [ours] px a band falls back when avoiding
const CALL_RADIUS := 550.0   # [ours] px: allied bands called to a target
const CALL_MAX := 2          # [ours] bands called per target
const JOIN_RADIUS := 120.0   # px: bands this close join a clash (= Diplomacy.ally_power default)
const GIVE_UP_DAYS := 3.0    # [ours] (a band walks ~175 px a day: a long chase is days)
const LEASH := 800.0         # [ours] px from where the chase began
const MARCH_LEASH := 350.0   # [ours] a war band marching on a town strays this far at most
const HOME_SHARE := 0.5      # [ours] below half the men it set out with -> home
const UNPAID_SHARE := 0.5    # [ours] at least half its men unpaid -> home
const HEARD_MAX := 2.0       # [ours] word of a force more than 2x our head count is not followed
const TERRAIN := 1.15        # [ours] own path vs straight line (lead time estimate)
const GRID := 470.0          # px: band grid cell (>= SIGHT + JOIN_RADIUS + drift between rebuilds)
const GRID_AGE := 0.05       # days between grid rebuilds
const POWER_AGE := 3.0       # [ours] days a band's own counted power is trusted (in between: scaled by head count)
const VALUE := {"caravan": 1.4, "assault": 1.3}   # [ours] target weights, others 1.0
const ARMY_KINDS := ["patrol", "raider", "assault", "contract"]
## Not town militia (war pick 3): a militia comes out only against a force it outnumbers 1.25x (Militia.sallies),
## so a band strong enough to attack it (ATTACK) never finds it outside the walls.
const TARGET_KINDS := ["patrol", "raider", "assault", "contract", "caravan"]
const CHASE_MODES := ["intercept", "join", "shadow"]
const OBJECTIVES := {"hold_capital": "Hold near capital", "defend": "Defend town", "march": "March on target", "raid": "Raid"}
const _NONE := {}            # "no orders" (read only)
const ADJ := {"middle_kingdom": "March", "northern_clans": "Northern", "moon_court": "moon elf", "orc_horde": "orc",
	"goblin_warren": "goblin", "eastern_khanate": "Eastern", "dwarf_holds": "dwarf"}

static var enabled := true   # profiling and A/B tests only: false = the old world without war interception
static var usec := 0   # profiling: microseconds spent here (tests read it)
static var _budget := MIN_THINKS   # decisions left this sub-step (tick refills it)
static var _counts := 1000   # first power counts of other bands left in this decision (see power)
static var _unit_avg := {}   # faction -> last counted power per man (the guess for a band never counted yet); w["war"]["avg"] during a decision
static var think_usec := 0   # of which decisions
static var astar_usec := 0   # of which grid paths
static var astar_n := 0
static var _grid := {}       # Vector2i cell -> [band dicts] (see _nearby); a cache, never saved
static var _grid_t := INF
static var _grid_n := -1
static var prof := {}        # finer profile: section -> usec (tests print it)

static func _prof(k: String, t0: int) -> void:
	var d := Time.get_ticks_usec() - t0
	prof[k] = int(prof.get(k, 0)) + d
	if d > int(prof.get(k + "_worst", 0)):
		prof[k + "_worst"] = d

# ================================================================== state
static func state(w: Dictionary) -> Dictionary:
	if not w.has("war"):
		w["war"] = {"intel": {}, "wnext": 0.0, "wi": 0, "news": [],
			"stats": {"thinks": 0, "intercepts": 0, "shadows": 0, "avoids": 0, "calls": 0, "tracks": 0, "word": 0,
				"home": 0, "caught": 0, "beaten": 0, "gave_up": 0}}
	return w["war"]

static func _stat(w: Dictionary, k: String) -> void:
	var s: Dictionary = state(w)["stats"]
	s[k] = int(s.get(k, 0)) + 1

## Can this band hunt? Patrols and raiders of a faction in diplomacy; a war band (sight only) once it marches.
static func hunter(w: Dictionary, wb: Dictionary, t: float) -> bool:
	var k := String(wb["kind"])
	if wb.get("deserter", false) or not Diplomacy.takes_part(w, wb["faction"]):
		return false
	if k == "patrol" or k == "raider":
		return true
	return k == "assault" and wb.get("war_assault", false) and t >= float(wb.get("march_day", 0.0))

static func target_kind(o: Dictionary) -> bool:
	return String(o["kind"]) in TARGET_KINDS and not o.get("deserter", false) and not (o["units"] as Array).is_empty()

## Band power (CampaignWorld.band_power), cached on the band: counted once, recounted when older than POWER_AGE
## (fresh: the thinking band itself), in between scaled by the head count (men lost or gained). Counting is the
## costly part of a decision (unit_power per man), so a decision counts at most one band it never counted (the
## rest: a guess from the faction's last count per man, w.war.avg) besides its own stale count.
static func power(wb: Dictionary, t: float, fresh: bool = false) -> float:
	var n := (wb["units"] as Array).size()
	var pn := int(wb.get("pw_n", -1)) if wb.has("pw") else -1   # a split band keeps pw_n but loses pw (feudal.gd)
	if pn < 0 and not fresh and _counts <= 0:
		return n * float(_unit_avg.get(wb["faction"], 1.0))   # never counted, no count left this decision: a guess
	if pn < 0 or (fresh and (t - float(wb.get("pw_t", -INF)) > POWER_AGE or t < float(wb.get("pw_t", 0.0)))):
		if not fresh:
			_counts -= 1
		wb["pw"] = CampaignWorld.band_power(wb["units"])
		wb["pw_n"] = n
		wb["pw_t"] = t
		if n > 0:
			_unit_avg[wb["faction"]] = float(wb["pw"]) / n
		return float(wb["pw"])
	if pn != n:
		return float(wb["pw"]) * n / maxf(1.0, pn)   # men lost or gained since the count: scaled until recounted
	return float(wb["pw"])

## Map speed (px/day) a force is moving at along its path right now (0 when halted).
static func speed_of(o: Dictionary, t: float) -> float:
	if float(o.get("rest_until", 0.0)) > t or (o.get("path", []) as Array).is_empty():
		return 0.0
	var war: Dictionary = o.get("war", {})
	if bool(war.get("wait", false)) or (o["kind"] == "assault" and t < float(o.get("march_day", 0.0))):
		return 0.0
	var base := CampaignWorld.travel_speed(CampaignWorld.WARBAND_SPEED, (o["units"] as Array).size())
	var spd := float(o.get("spd", 1.0))
	match String(o["kind"]):
		"caravan":
			return 0.0 if String(o.get("state", "travel")) != "travel" else base * Caravans.SPEED * spd
		"militia":
			return base * (1.0 if o.get("professional", false) else 0.5) * spd
	var m := 1.0
	match String(war.get("m", "")):
		"home": m = 0.85
		"avoid": m = 0.95
		"track", "hunt": m = 0.9
		_:
			if war.is_empty() and o["kind"] != "assault":
				m = 0.95 if o.get("mode", "wander") == "flee" else 0.8 if o.get("mode", "wander") == "wander" else 1.0
	return base * m * spd

## Interception point: the first point of the target's path (from tpos) the hunter can reach no later than the
## target does; the end of its path when the hunter is too slow; tpos when the target stands still.
static func lead_point(from: Vector2, my_speed: float, tpos: Vector2, tpath: Array, tspeed: float) -> Vector2:
	if tpath.is_empty() or tspeed <= 0.0 or my_speed <= 0.0:
		return tpos
	# slack(x) = target's time to x - hunter's time to x; the first path point where it turns >= 0. Checked at the
	# path's corners, then bisected inside the segment where it turns (a few steps: ~5 px).
	var k := TERRAIN / my_speed
	var along := 0.0
	var p := tpos
	for q in tpath:
		var seg := p.distance_to(q)
		if from.distance_to(q) * k <= (along + seg) / tspeed:
			var lo := 0.0; var hi := 1.0
			for _i in 6:
				var mid := (lo + hi) * 0.5
				if from.distance_to(p.lerp(q, mid)) * k <= (along + seg * mid) / tspeed:
					hi = mid
				else:
					lo = mid
			return p.lerp(q, hi)
		along += seg
		p = q
		if along > 2400.0:
			break
	return p

# ================================================================== per sub-step
## A re-think soon, spread per band (bands that lose the same target do not all think in the same frame).
static func _soon(wb: Dictionary, t: float) -> float:
	return t + STEER * (0.5 + float(absi(hash(String(wb["id"]))) % 1000) / 1000.0)

## Once per world sub-step, before the bands move: the decision budget, the town watch (one town at a time).
static func tick(game, t: float, dt: float = 0.0) -> void:
	var w: Dictionary = game.world
	if not enabled:
		return
	_budget = maxi(MIN_THINKS, ceili((w.get("warbands", {}) as Dictionary).size() * dt / THINK * 1.5))
	if not w.has("diplo"):
		return
	var t0 := Time.get_ticks_usec()
	var st := state(w)
	if t >= float(st["wnext"]):
		var ids: Array = w["towns"].keys()
		if not ids.is_empty():
			st["wnext"] = t + WATCH / ids.size()
			var i := int(st["wi"]) % ids.size()
			st["wi"] = i + 1
			_town_watch(w, w["towns"][ids[i]], t)
	usec += Time.get_ticks_usec() - t0

static func _town_watch(w: Dictionary, town: Dictionary, t: float) -> void:
	var fid: String = town["faction"]
	if not Diplomacy.takes_part(w, fid):
		return
	var en := _enemy_set(w, fid)
	if en.is_empty():
		return
	var tp: Vector2 = town["pos"]
	var r2 := TOWN_SIGHT * TOWN_SIGHT
	for oid in w["warbands"]:
		var o: Dictionary = w["warbands"][oid]
		if en.has(o["faction"]) and (o["pos"] as Vector2).distance_squared_to(tp) <= r2 and target_kind(o):
			_note(w, fid, oid, o, t)

static func _enemy_set(w: Dictionary, fid: String) -> Dictionary:
	var en := {}
	for e in Diplomacy.enemies_at_war(w, fid):
		en[e] = true
	return en

## Word of enemy force o reaches faction fid's bands REPORT_DELAY from now (one report in flight at a time).
static func _note(w: Dictionary, fid: String, oid: String, o: Dictionary, t: float) -> void:
	var intel: Dictionary = state(w)["intel"]
	if not intel.has(fid):
		intel[fid] = {}
	var mine: Dictionary = intel[fid]
	var old: Array = mine.get(oid, [])
	if not old.is_empty() and float(old[6]) > t:
		return
	var pos: Vector2 = o["pos"]
	var h := Vector2.ZERO
	var path: Array = o.get("path", [])
	if not path.is_empty():
		h = ((path[0] as Vector2) - pos).normalized()
	mine[oid] = [pos.x, pos.y, t, float((o["units"] as Array).size()), h.x, h.y, t + REPORT_DELAY]

# ================================================================== per band
## Called by CampaignWorld._move_warbands for a band that is not chasing or fleeing the company. Thinks on its
## cadence and steers the band when it has war orders. Returns the speed multiplier the band walks its path at
## (the caller walks it: map movement), 0 = hold, -1 = no war orders (the caller wanders).
static func control(game, wid: String, wb: Dictionary, t: float) -> float:
	sync_objective(wb, t)
	if not enabled:
		return -1.0
	var nx = wb.get("war_next")
	var war: Dictionary = wb.get("war", _NONE)
	# a decision is due; past the sub-step's budget it waits a sub-step (never many decisions in one frame)
	var think: bool = nx == null or (t >= float(nx) and _budget > 0)
	if not think and war.is_empty():
		return -1.0   # the common case: no orders, no decision due (two lookups a frame)
	var w: Dictionary = game.world
	var t0 := Time.get_ticks_usec()
	if not wb.has("n0"):
		wb["n0"] = (wb["units"] as Array).size()   # the men it set out with
	if think:
		if not w.has("diplo") or not hunter(w, wb, t):
			wb["war_next"] = t + THINK
			clear(wb)
			sync_objective(wb, t)
			usec += Time.get_ticks_usec() - t0
			return -1.0
		if nx == null:
			wb["war_next"] = t + float(absi(hash(wid)) % 1000) / 1000.0 * THINK   # staggered: bands never think together
		else:
			_budget -= 1
			wb["war_next"] = t + THINK
			var t1 := Time.get_ticks_usec()
			var st := state(w)
			if not st.has("avg"):
				st["avg"] = {}
			_unit_avg = st["avg"]   # saved with the world: the same seed guesses the same
			_counts = 1
			_think(game, wid, wb, t)
			_counts = 1000
			_unit_avg = {}
			var dtk := Time.get_ticks_usec() - t1
			think_usec += dtk
			if dtk > int(prof.get("think_worst", 0)):
				prof["think_worst"] = dtk
		war = wb.get("war", _NONE)
	var mult := -1.0
	if not war.is_empty():
		mult = _drive(game, wb, war, t)
	sync_objective(wb, t)
	usec += Time.get_ticks_usec() - t0
	return mult

static func clear(wb: Dictionary) -> void:
	if not (wb.get("war", {}) as Dictionary).is_empty():
		wb["war"] = {}
		wb["path"] = []

## New war orders. keep = the old orders: the chase clock and origin carry over while the target stays the same.
static func _order(wb: Dictionary, m: String, tgt: String, aim: Vector2, t: float, keep: Dictionary = {}) -> Dictionary:
	var same: bool = tgt != "" and String(keep.get("tgt", "")) == tgt
	var war := {"m": m, "tgt": tgt, "aim": aim, "steer": 0.0, "called": same and bool(keep.get("called", false)),
		"t0": float(keep["t0"]) if same else t, "p0": keep["p0"] if same else wb["pos"], "lead": ""}
	wb["war"] = war
	wb["path"] = []
	sync_objective(wb, t)
	return war

static func _think(game, wid: String, wb: Dictionary, t: float) -> void:
	var w: Dictionary = game.world
	_stat(w, "thinks")
	var fid: String = wb["faction"]
	var war: Dictionary = wb.get("war", {})
	var n := (wb["units"] as Array).size()
	if n == 0:
		return
	if String(war.get("m", "")) == "home":
		return
	# beaten down or unpaid: home
	var unpaid := int(wb.get("unpaid_n", 0))
	if n < float(wb.get("n0", n)) * HOME_SHARE or (unpaid > 0 and unpaid >= n * UNPAID_SHARE):
		_go_home(w, wb, t)
		return
	var en := _enemy_set(w, fid)
	if en.is_empty():
		clear(wb)   # peace: leave them alone
		return
	var pos: Vector2 = wb["pos"]
	var marching: bool = wb["kind"] == "assault"
	var cur := String(war.get("tgt", ""))
	# give up a chase that ran too long or too far
	if not war.is_empty() and String(war["m"]) != "avoid":
		var leash := MARCH_LEASH if marching else LEASH
		if t - float(war["t0"]) > GIVE_UP_DAYS or pos.distance_to(war["p0"]) > leash:
			_stat(w, "gave_up")
			clear(wb)
			wb["war_next"] = t + THINK * 2.0   # catch breath before the next hunt
			return
	# ---------------------------------------------------------------- what it sees
	var ts := Time.get_ticks_usec()
	var my := power(wb, t, true)   # its own strength counted afresh (others: the last count, scaled by heads)
	var cands := []   # [score, oid]
	var seen := {}
	var threat := ""; var td := INF
	var s2 := SIGHT * SIGHT
	var n2 := (SIGHT + JOIN_RADIUS) * (SIGHT + JOIN_RADIUS)
	var near := []   # every band that can matter to a fight in sight (ratio)
	var enc: String = w.get("encounter", "")
	var bands: Dictionary = w["warbands"]
	for o in _nearby(w, pos, t):
		var d2 := pos.distance_squared_to(o["pos"])
		if d2 > n2:
			continue
		var oid: String = o["id"]
		if not bands.has(oid):
			continue   # gone since the grid was built
		near.append(o)
		if d2 > s2 or not en.has(o["faction"]) or not target_kind(o) or oid == enc:
			continue
		_note(w, fid, oid, o, t)   # word goes home to the faction
		seen[oid] = true
		var d := sqrt(d2)
		var op := power(o, t)
		var committed: bool = oid == cur and String(war.get("m", "")) in ["join", "shadow"]
		if String(o["kind"]) in ARMY_KINDS and my < op * SHADOW and d < AVOID_DIST and d < td and not committed:
			threat = oid; td = d
		var v := float(VALUE.get(o["kind"], 1.0))
		var sc := v / (1.0 + d / SIGHT)
		if oid == cur:
			sc *= 1.5
		cands.append([sc, oid])
	_prof("scan", ts)
	ts = Time.get_ticks_usec()
	if threat != "" and not marching:
		var tb: Dictionary = w["warbands"][threat]
		if ratio(w, wb, tb, t, near) < SHADOW:
			if String(war.get("m", "")) == "avoid" and cur == threat and (wb["path"] as Array).size() > 0:
				return   # still getting away from it
			var away := (pos - (tb["pos"] as Vector2)).normalized()
			if away == Vector2.ZERO:
				away = Vector2.RIGHT
			_order(wb, "avoid", threat, _reach(w, pos, pos + away * AVOID_RUN), t)
			_stat(w, "avoids")
			return
	if not cands.is_empty():
		cands.sort_custom(func(a, b): return a[0] > b[0])
		var shadow := ""
		for k in mini(3, cands.size()):
			var oid: String = cands[k][1]
			var o: Dictionary = w["warbands"][oid]
			var r := ratio(w, wb, o, t, near)
			if r >= ATTACK:
				if cur != oid or String(war.get("m", "")) != "intercept":
					_order(wb, "intercept", oid, o["pos"], t, war)
					_stat(w, "intercepts")
				return
			if shadow == "" and (r >= SHADOW or (oid == cur and String(war.get("m", "")) in ["join", "shadow"])):
				shadow = oid   # (a band answering a call, or shadowing already, stays on it while the others come)
		if shadow != "" and not marching:
			if cur != shadow or not String(war.get("m", "")) in ["join", "shadow"]:
				war = _order(wb, "shadow", shadow, w["warbands"][shadow]["pos"], t, war)
				_stat(w, "shadows")
			if not bool(war["called"]):
				war["called"] = true
				_call_allies(w, wid, wb, shadow, t)
			return
	_prof("decide", ts)
	if marching:
		clear(wb)   # back to the march
		return
	# ---------------------------------------------------------------- what it has heard of
	var m := String(war.get("m", ""))
	if m == "join" and w["warbands"].has(cur):
		return   # called to a fight it cannot see yet: keep going
	if m in ["track", "hunt"] and w["warbands"].has(cur) and not (wb["path"] as Array).is_empty():
		return   # still on its way
	ts = Time.get_ticks_usec()
	var tr := _fresh_trail(w, wb, en, t, n, seen)
	_prof("trail", ts)
	if not tr.is_empty():
		_order(wb, "track", tr[0], tr[1], t, war if m in CHASE_MODES or m == "track" else {})
		_stat(w, "tracks")
		return
	ts = Time.get_ticks_usec()
	var wd := _word(w, wb, fid, en, t, n, seen)
	_prof("word", ts)
	if not wd.is_empty():
		_order(wb, "hunt", wd[0], wd[1], t, war if m in CHASE_MODES or m == "hunt" else {})
		_stat(w, "word")
		return
	clear(wb)

## Bands in the 3x3 grid cells around pos (cells of GRID px >= SIGHT + JOIN_RADIUS + drift, so every band within
## SIGHT + JOIN_RADIUS is in them). The grid is rebuilt every GRID_AGE days (bands move ~15 px in that time);
## bands spawned since then are missed for that long, removed ones are skipped by the caller.
static func _nearby(w: Dictionary, pos: Vector2, t: float) -> Array:
	if t >= _grid_t + GRID_AGE or t < _grid_t or _grid_n != int(w.get("next_id", 0)) and t >= _grid_t + GRID_AGE * 0.25:
		_grid.clear()
		for wid in w["warbands"]:
			var o: Dictionary = w["warbands"][wid]
			var op: Vector2 = o["pos"]
			var c := Vector2i(int(floor(op.x / GRID)), int(floor(op.y / GRID)))
			if not _grid.has(c):
				_grid[c] = []
			(_grid[c] as Array).append(o)
		_grid_t = t
		_grid_n = int(w.get("next_id", 0))
	var out := []
	var cx := int(floor(pos.x / GRID)); var cy := int(floor(pos.y / GRID))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell = _grid.get(Vector2i(cx + dx, cy + dy))
			if cell != null:
				out.append_array(cell)
	return out

## Own power + the bands that would join the clash, over the target's: the same sides as
## CampaignWorld._warband_clashes (Diplomacy.ally_power for allied realms, pack_power for committed own bands).
## near: the bands close enough to matter (a think collects them; empty = every band).
static func ratio(w: Dictionary, wb: Dictionary, o: Dictionary, t: float, near: Array = []) -> float:
	if near.is_empty():
		near = w["warbands"].values()
	var mine := power(wb, t) + _side(w, near, wb, o, t)
	var theirs := power(o, t) + _side(w, near, o, wb, t)
	return mine / maxf(0.001, theirs)

## Power of the bands that join band a's clash with band b (see ratio).
static func _side(w: Dictionary, near: Array, a: Dictionary, b: Dictionary, t: float) -> float:
	var p := 0.0
	var r2 := JOIN_RADIUS * JOIN_RADIUS
	var ap: Vector2 = a["pos"]
	var fa: String = a["faction"]; var fb: String = b["faction"]
	var allies_join: bool = a["kind"] != "caravan" and b["kind"] != "caravan"
	for x in near:
		if x["id"] == a["id"] or x["id"] == b["id"] or x["kind"] == "caravan" or (x["pos"] as Vector2).distance_squared_to(ap) > r2:
			continue
		var fx: String = x["faction"]
		if fx == fa:
			var war: Dictionary = x.get("war", {})
			if not war.is_empty() and String(war.get("tgt", "")) == b["id"] and String(war["m"]) in CHASE_MODES:
				p += power(x, t)
		elif allies_join and fx != fb and Diplomacy.allied(w, fx, fa) and Diplomacy.fights(w, fx, fb):
			p += power(x, t)
	return p

## Power of a's own faction's bands committed to the same target (war orders on tgt_id) within JOIN_RADIUS of a:
## they join a's clash with that target (allied realms' bands come in through Diplomacy.ally_power).
static func pack_power(w: Dictionary, a: Dictionary, tgt_id: String, exclude: Array) -> float:
	var p := 0.0
	var r2 := JOIN_RADIUS * JOIN_RADIUS
	var fid: String = a["faction"]
	for oid in w["warbands"]:
		var o: Dictionary = w["warbands"][oid]
		var war: Dictionary = o.get("war", {})
		if war.is_empty() or String(war.get("tgt", "")) != tgt_id or exclude.has(oid) or not String(war["m"]) in CHASE_MODES:
			continue
		if (o["pos"] as Vector2).distance_squared_to(a["pos"]) > r2:
			continue
		if o["faction"] == fid:   # allied realms' bands come in through Diplomacy.ally_power already
			p += power(o, 0.0)   # its last count (scaled by heads), as its own decisions see it
	return p

static func _call_allies(w: Dictionary, wid: String, wb: Dictionary, tgt: String, t: float) -> void:
	var tf: String = w["warbands"][tgt]["faction"]
	var pos: Vector2 = wb["pos"]
	var got := []   # [d, oid]
	for oid in w["warbands"]:
		if oid == wid:
			continue
		var o: Dictionary = w["warbands"][oid]
		if not (o["kind"] == "patrol" or o["kind"] == "raider") or o.get("deserter", false):
			continue
		var d := pos.distance_to(o["pos"])
		if d > CALL_RADIUS:
			continue
		if o["faction"] != wb["faction"] and not Diplomacy.allied(w, o["faction"], wb["faction"]):
			continue
		if not Diplomacy.at_war(w, o["faction"], tf):
			continue
		var ow: Dictionary = o.get("war", {})
		if not ow.is_empty() and not String(ow["m"]) in ["track", "hunt"]:
			continue   # busy
		got.append([d, oid])
	got.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(CALL_MAX, got.size()):
		var o: Dictionary = w["warbands"][got[k][1]]
		var ow := _order(o, "join", tgt, w["warbands"][tgt]["pos"], t)
		ow["lead"] = wid   # gather on the caller first
		ow["called"] = true   # it answers a call; it does not call others in turn
		o["war_next"] = _soon(o, t)
		_stat(w, "calls")

## A fresh enemy trail crossing this band's sight: [wid, aim] (the trail read to its newest crumb), or [].
static func _fresh_trail(w: Dictionary, wb: Dictionary, en: Dictionary, t: float, n: int, seen: Dictionary) -> Array:
	var forces: Dictionary = w.get("tracks", {}).get("forces", {})
	var pos: Vector2 = wb["pos"]
	var s2 := SIGHT * SIGHT
	var reach := (SIGHT + 200.0) * (SIGHT + 200.0)   # a fresh trail is shorter than 200 px: its newest crumb is this close
	var best := []; var bt := -INF
	for fwid in forces:
		var rec: Dictionary = forces[fwid]
		# Faction and already-seen checks are independent of the crumb positions. Most trails belong to
		# friendly or neutral forces; they cannot be selected, so avoid reading their geometry.
		if not en.has(rec["f"]) or seen.has(fwid):
			continue
		var c: Array = rec["c"]
		var top := c.size() - Tracks.STRIDE
		if top < 0 or t - float(c[top + 2]) > TRACK_FRESH or float(c[top + 2]) <= bt:
			continue
		if pos.distance_squared_to(Vector2(c[top], c[top + 1])) > reach:
			continue
		if float(c[top + 3]) > n * HEARD_MAX:
			continue
		var o: Dictionary = w["warbands"].get(fwid, {})
		if o.is_empty() or not target_kind(o):
			continue
		var i := top
		while i >= 0 and t - float(c[i + 2]) <= TRACK_FRESH:
			if pos.distance_squared_to(Vector2(c[i], c[i + 1])) <= s2:
				bt = float(c[top + 2])
				best = [fwid, Vector2(c[top], c[top + 1]) + Vector2.from_angle(float(c[top + 4])) * TRACK_LEAD]
				break
			i -= Tracks.STRIDE
	if not best.is_empty():
		best[1] = _reach(w, pos, best[1])
	return best

## The nearest enemy force the faction has word of (towns' and bands' sightings): [wid, aim], or [].
static func _word(w: Dictionary, wb: Dictionary, fid: String, en: Dictionary, t: float, n: int, seen: Dictionary) -> Array:
	var mine: Dictionary = state(w)["intel"].get(fid, {})
	if mine.is_empty():
		return []
	var pos: Vector2 = wb["pos"]
	var best := []; var bd := HEARD
	for oid in mine.keys():
		var r: Array = mine[oid]
		var o: Dictionary = w["warbands"].get(oid, {})
		var age := t - float(r[2])
		if o.is_empty() or age > INTEL_LIFE or not en.has(o["faction"]):
			mine.erase(oid)
			continue
		if float(r[6]) > t or float(r[3]) > n * HEARD_MAX or seen.has(oid):
			continue
		var at := Vector2(r[0], r[1]) + Vector2(r[4], r[5]) * minf(200.0, age * CampaignWorld.WARBAND_SPEED * 0.6)
		var d := pos.distance_to(at)
		if d < bd:
			bd = d; best = [oid, at]
	if not best.is_empty():
		best[1] = _reach(w, pos, best[1])
	return best

static func _go_home(w: Dictionary, wb: Dictionary, t: float) -> void:
	var home: Dictionary = w["towns"].get(String(wb.get("home", "")), {})
	if home.is_empty() or home["faction"] != wb["faction"]:
		var hid := CampaignWorld.nearest_faction_town(w, wb["faction"], wb["pos"])
		home = w["towns"].get(hid, {})
		if home.is_empty():
			return
		wb["home"] = hid
	if (wb["pos"] as Vector2).distance_to(home["pos"]) < 60.0:
		clear(wb)
		wb["rest_until"] = t + THINK   # at home already: stay until paid / regrouped
		return
	_order(wb, "home", "", home["pos"], t)
	_stat(w, "home")

# ================================================================== driving
static func _drive(game, wb: Dictionary, war: Dictionary, t: float) -> float:
	var w: Dictionary = game.world
	var m := String(war["m"])
	var tgt := String(war.get("tgt", ""))
	var mult := 1.0
	match m:
		"home":
			mult = 0.85
			if (wb["path"] as Array).is_empty():
				if (wb["pos"] as Vector2).distance_to(war["aim"]) < 40.0:
					_arrive_home(w, wb, t)
					return 0.0
				_set_path(w, wb, war["aim"])
				if (wb["path"] as Array).is_empty():
					_arrive_home(w, wb, t)   # cannot get there: settle where it is
					return 0.0
		"intercept", "join", "shadow":
			var o: Dictionary = w["warbands"].get(tgt, _NONE)
			if o.is_empty():
				clear(wb)
				wb["war_next"] = minf(float(wb.get("war_next", t)), _soon(wb, t))
				return -1.0
			if t >= float(war["steer"]):
				if not Diplomacy.at_war(w, wb["faction"], o["faction"]):
					clear(wb)   # peace was made
					return -1.0
				var d := (wb["pos"] as Vector2).distance_to(o["pos"])
				# re-aim often when close, seldom when far (the aim moves little against the distance)
				war["steer"] = t + (STEER / 3.0 if d < 150.0 else STEER * clampf(d / 400.0, 1.0, 3.0))
				war["wait"] = m == "shadow" and d < SHADOW_DIST * 0.8   # close enough: wait for the others
				var aim: Vector2
				var lead := _lead_band(w, war, tgt)
				if m == "join" and not lead.is_empty():
					aim = lead["pos"]   # gather on the band that called first
					if (wb["pos"] as Vector2).distance_to(aim) < JOIN_RADIUS * 0.6:
						war["wait"] = true   # gathered: the next decision attacks together
				elif m == "shadow":
					var back := ((wb["pos"] as Vector2) - (o["pos"] as Vector2)).normalized()
					aim = (o["pos"] as Vector2) + back * SHADOW_DIST
				else:
					aim = lead_point(wb["pos"], CampaignWorld.travel_speed(CampaignWorld.WARBAND_SPEED, (wb["units"] as Array).size()) * maxf(1.0, float(wb.get("spd", 1.0))),
						o["pos"], o.get("path", []), speed_of(o, t))
				var path: Array = wb["path"]
				var end: Vector2 = path[-1] if not path.is_empty() else Vector2.INF
				var slack := maxf(30.0, 0.2 * (wb["pos"] as Vector2).distance_to(aim))
				if end.distance_to(aim) > (8.0 if path.is_empty() else slack):
					war["aim"] = aim
					var tr := Time.get_ticks_usec()
					_retarget(w, wb, aim)
					_prof("retarget", tr)
			if (wb["path"] as Array).is_empty() or bool(war.get("wait", false)):
				return 0.0   # at the aim, or waiting for the others: hold until the next re-aim
		"avoid", "track", "hunt":
			mult = 0.95 if m == "avoid" else 0.9
			if (wb["path"] as Array).is_empty():
				if float(war["steer"]) > 0.0:   # walked it: done
					clear(wb)
					wb["war_next"] = minf(float(wb.get("war_next", t)), _soon(wb, t))
					return -1.0
				war["steer"] = t
				_set_path(w, wb, war["aim"])
				if (wb["path"] as Array).is_empty():
					clear(wb)
					return -1.0
		_:
			clear(wb)
			return -1.0
	return mult

## The band that called this one, while it still shadows the same target ({} otherwise).
static func _lead_band(w: Dictionary, war: Dictionary, tgt: String) -> Dictionary:
	var ld: Dictionary = w["warbands"].get(String(war.get("lead", "")), {})
	if ld.is_empty():
		return {}
	var lw: Dictionary = ld.get("war", {})
	if lw.is_empty() or String(lw.get("tgt", "")) != tgt or String(lw["m"]) != "shadow":
		return {}
	return ld

static func _arrive_home(w: Dictionary, wb: Dictionary, t: float) -> void:
	clear(wb)
	var home: Dictionary = w["towns"].get(String(wb.get("home", "")), {})
	if not home.is_empty():
		wb["anchor"] = home["pos"]
	wb["n0"] = (wb["units"] as Array).size()   # regrouped: this is the band now
	wb["rest_until"] = t + 1.0
	if wb["kind"] == "assault":   # a beaten war band gives up its march
		wb["war_assault"] = false
		wb["kind"] = "raider" if DB.factions[wb["faction"]].get("player_hostile", false) else "patrol"

## A moved aim: bend the end of the current path when the new aim is in clear reach of its last turn; else a new
## path.
static func _retarget(w: Dictionary, wb: Dictionary, aim: Vector2) -> void:
	var path: Array = wb["path"]
	if not path.is_empty():
		var prev: Vector2 = path[-2] if path.size() >= 2 else wb["pos"]
		if prev.distance_to(aim) < 300.0 and _straight(w, prev, aim):
			path[-1] = aim
			return
		var end: Vector2 = path[-1]
		if end.distance_to(aim) < 120.0 and _straight(w, end, aim):
			path.append(aim)   # a short step on from the old end
			return
	_set_path(w, wb, aim)

## Straight line when short and clear (no A*), else the grid path.
static func _set_path(w: Dictionary, wb: Dictionary, aim: Vector2) -> void:
	var pos: Vector2 = wb["pos"]
	if pos.distance_to(aim) < 300.0 and _straight(w, pos, aim):
		wb["path"] = [aim]
	else:
		var t0 := Time.get_ticks_usec()
		wb["path"] = grid_path(w, pos, aim)
		astar_usec += Time.get_ticks_usec() - t0
		astar_n += 1

## CampaignWorld.find_path for war moves, cheaper: the same grid A*, but runs of cells in one direction are
## collapsed to their ends before the string-pull, so the (GDScript) line checks run over a few corners, not
## every cell (find_path's smoothing costs ~30x the A* itself on long paths).
static func grid_path(w: Dictionary, from: Vector2, to: Vector2) -> Array:
	var a := CampaignWorld.astar(w)
	var fc := WorldGen.cell_of(CampaignWorld.nearest_passable(w, from))
	var tp := CampaignWorld.nearest_passable(w, to)
	var tc := WorldGen.cell_of(tp)
	if fc == tc:
		return [tp]
	var pts: PackedVector2Array = a.get_point_path(fc, tc)
	if pts.size() < 2:
		return []
	var corners := [pts[1]]
	var dir := pts[1] - pts[0]
	for i in range(2, pts.size()):
		var d := pts[i] - pts[i - 1]
		if d.is_equal_approx(dir):
			corners[-1] = pts[i]   # same direction: the run goes on
		else:
			corners.append(pts[i])
			dir = d
	if CampaignWorld.passable(w, to) and WorldGen.cell_of(to) == tc:
		corners[-1] = to
	if corners.size() < 3:
		return corners
	# string-pull over the corners on passable ground (a war band cuts across country; it does not keep to roads)
	var out := []
	var anchor := from
	for j in range(1, corners.size()):
		if not _straight(w, anchor, corners[j]):
			out.append(corners[j - 1])
			anchor = corners[j - 1]
	out.append(corners[-1])
	return out

## `to` when it is on passable ground, else the nearest passable point back along the line toward `from`
## (cheap: CampaignWorld.nearest_passable searches rings of cells, ~1 ms when the point is deep in water/rock).
static func _reach(w: Dictionary, from: Vector2, to: Vector2) -> Vector2:
	var g := CampaignWorld.astar(w)
	var n := maxi(1, int(ceil(from.distance_to(to) / 12.0)))
	var mx := WorldGen.W * WorldGen.CELL; var my := WorldGen.H * WorldGen.CELL
	for k in range(n, 0, -1):
		var p := from.lerp(to, float(k) / n)
		if p.x >= 0.0 and p.y >= 0.0 and p.x < mx and p.y < my and not g.is_point_solid(Vector2i(int(p.x / WorldGen.CELL), int(p.y / WorldGen.CELL))):
			return p
	return from

## The straight line a-b stays on passable ground (sampled every 12 px against the A* grid's solid cells).
static func _straight(w: Dictionary, a: Vector2, b: Vector2) -> bool:
	var g := CampaignWorld.astar(w)
	var n := int(ceil(a.distance_to(b) / 12.0))
	var mx := WorldGen.W * WorldGen.CELL; var my := WorldGen.H * WorldGen.CELL
	for k in range(1, n + 1):
		var p := a.lerp(b, float(k) / n)
		if p.x < 0.0 or p.y < 0.0 or p.x >= mx or p.y >= my or g.is_point_solid(Vector2i(int(p.x / WorldGen.CELL), int(p.y / WorldGen.CELL))):
			return false
	return true

# ================================================================== clashes and news
## The band of the two that ran the other down (war orders on it), or {}.
static func interceptor(a: Dictionary, b: Dictionary) -> Dictionary:
	for pair in [[a, b], [b, a]]:
		var war: Dictionary = pair[0].get("war", {})
		if not war.is_empty() and String(war.get("tgt", "")) == pair[1]["id"] and String(war["m"]) in CHASE_MODES:
			return pair[0]
	return {}

## After a clash is decided (CampaignWorld._warband_clashes): a news line for an interception. Returns true when it
## logged the clash (the caller then skips its plain line).
static func on_clash(game, a: Dictionary, b: Dictionary, win: Dictionary) -> bool:
	var hunter_b := interceptor(a, b)
	if hunter_b.is_empty():
		return false
	var w: Dictionary = game.world
	var prey: Dictionary = b if hunter_b["id"] == a["id"] else a
	var where := CampaignWorld.nearest_town_name(w, prey["pos"])
	var text := ""
	if win["id"] == hunter_b["id"]:
		_stat(w, "caught")
		text = "%s caught %s near %s." % [Diplomacy.cap(band_words(hunter_b, true)), band_words(prey, false), where]
	else:
		_stat(w, "beaten")
		text = "%s ran down %s near %s and was cut to pieces." % [Diplomacy.cap(band_words(hunter_b, true)), band_words(prey, false), where]
	var st := state(w)
	var nw: Array = st["news"]
	nw.append({"day": float(game.day), "text": text})
	while nw.size() > 12:
		nw.pop_front()
	if prey["kind"] == "caravan" and win["id"] == hunter_b["id"]:
		return false   # Caravans.lost tells of a plain caravan; convoys and armies get the war line
	CampaignWorld.log_event(game, text)
	return true

static func adj(fid: String) -> String:
	if ADJ.has(fid):
		return ADJ[fid]
	return String(DB.races.get(String(DB.factions.get(fid, {}).get("race", "")), {}).get("name", fid))

## "a March war band", "an orc patrol", "a goblin convoy", "the militia of Fengate".
static func band_words(wb: Dictionary, _subject: bool) -> String:
	var k := String(wb["kind"])
	var noun := String({"patrol": "patrol", "raider": "raiding party", "assault": "war band", "contract": "war band",
		"caravan": "caravan", "militia": "militia"}.get(k, "band"))
	if k == "patrol" and not (wb.get("war", {}) as Dictionary).is_empty():
		noun = "war band"
	var a := adj(wb["faction"])
	var art := "an" if "aeiou".contains(a.substr(0, 1).to_lower()) else "a"
	return "%s %s %s" % [art, a, noun]

## Saved strategic intent derived from existing orders, including bands not eligible for interception.
static func sync_objective(wb: Dictionary, t: float = 0.0) -> void:
	var war: Dictionary = wb.get("war", {})
	var mode := String(wb.get("mode", "wander"))
	if not mode in ["chase", "flee"]:
		mode = String(war.get("m", mode))
	var objective := "defend"
	match mode:
		"home": objective = "hold_capital"
		"avoid", "shadow", "flee": objective = "defend"
		"intercept", "join", "track", "hunt", "chase": objective = "march"
		_:
			var kind := String(wb.get("kind", ""))
			if kind == "assault":
				objective = "hold_capital" if t < float(wb.get("march_day", 0.0)) else "march"
			elif kind in ["raider", "bandit", "camp"]:
				objective = "raid"
			elif not kind in ["patrol", "militia"] and not (wb.get("path", []) as Array).is_empty():
				objective = "march"
	wb["objective"] = objective

## Objective first, followed by the current tactical order when there is one.
static func mode_text(wb: Dictionary) -> String:
	var label := String(OBJECTIVES.get(String(wb.get("objective", "defend")), OBJECTIVES["defend"]))
	var war: Dictionary = wb.get("war", {})
	var detail := String({"intercept": "intercepting", "join": "answering a call", "shadow": "shadowing", "avoid": "avoiding",
		"track": "on a trail", "hunt": "hunting", "home": "falling back home"}.get(String(war.get("m", "")), ""))
	return label if detail == "" else "%s (%s)" % [label, detail]

# ================================================================== save / load
## A new world: the band grid and the decision budget of the world before go (same seed = same world).
static func new_world() -> void:
	_grid = {}
	_grid_t = INF
	_grid_n = -1
	_budget = MIN_THINKS

static func after_load(game) -> void:
	var w: Dictionary = game.world
	_grid_t = INF   # the band grid belongs to the world that was loaded over
	if w.has("war"):
		var st: Dictionary = w["war"]
		st["wi"] = int(st.get("wi", 0))
		st["wnext"] = float(st.get("wnext", 0.0))
		for k in st.get("stats", {}):
			st["stats"][k] = int(st["stats"][k])
	for wid in w.get("warbands", {}):
		var wb: Dictionary = w["warbands"][wid]
		sync_objective(wb, float(game.day))
		if wb.has("pw_n"):
			wb["pw_n"] = int(wb["pw_n"])
		var war: Dictionary = wb.get("war", {})
		if not war.is_empty():
			war["called"] = bool(war.get("called", false))
	var party: Dictionary = w.get("party", {})
	if not OBJECTIVES.has(String(party.get("objective", ""))):
		party["objective"] = "hold_capital" if (party.get("path", []) as Array).is_empty() else "march"
