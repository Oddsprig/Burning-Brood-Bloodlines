class_name BattleMorale
extends RefCounted
## Morale, leadership aura, panic propagation, rage, officer rally, and routing helpers split from BattleSim
## (game/sim/battle_sim.gd) to keep each file focused and under the size threshold.
## Structure only; all BattleSim.* entry points delegate here with identical behavior.

const NEIGHBORS := BattleSim.NEIGHBORS
const T_BLOCKED := BattleSim.T_BLOCKED

static func _trait(_sim, f: Fighter, t: String) -> float:
	var c = f.trait_cache.get(t)   # perf: personality and race are fixed during a battle
	if c != null:
		return c
	var rp = f.unit.race_def().get("personality", {})
	var dflt := 50.0
	if rp is Dictionary and rp.has(t) and not (rp[t] is Array):
		dflt = float(rp[t])
	var v := float(f.unit.personality.get(t, dflt))
	f.trait_cache[t] = v
	return v

static func _init_morale(sim) -> void:
	sim._officers = [[], []]
	var commands: Array = [{}, {}]
	for f in sim.fighters:
		if f.unit.is_officer():
			sim._officers[f.side].append(f)
			var uid: int = f.unit.uid
			if uid > 0:
				# Duplicate native UID claims are ambiguous, never first-match leaders.
				commands[f.side][uid] = -2 if commands[f.side].has(uid) else f.idx
	for f: Fighter in sim.fighters:
		f.commander_idx = -1
		f.commander_uid = -1
		var uid: int = f.unit.squad
		var idx: int = int(commands[f.side].get(uid, -1))
		if uid > 0 and idx >= 0 and idx != f.idx and f.unit.uid != uid:
			f.commander_idx = idx
			f.commander_uid = uid
	for f in sim.fighters:
		# perf: the battle traits as fields (personality is fixed during a battle; same values as _trait)
		f.tr_nerve = sim._trait(f, "nerve")
		f.tr_temper = sim._trait(f, "temper")
		f.tr_prot = sim._trait(f, "protectiveness")
		f.tr_courage = sim._trait(f, "courage")
		f.tr_loyalty = sim._trait(f, "loyalty")
		f.tr_cohesion = sim._trait(f, "cohesion")
	for f in sim.fighters:
		# Unclamped intrinsic component; clamp only after adding the native aura.
		f.morale_base = Formulas.MORALE_START + (f.tr_courage - 50.0) / 2.0 + Food.morale_mod(f.unit)
		f.morale_start = Formulas.morale_start(sim._trait(f, "courage"), sim._leader_near(f), Food.morale_mod(f.unit))
		f.morale = f.morale_start

## Actual assigned same-side officer within the existing native command radius.
## Cached indices make support/rally O(1), with live incapacity/identity checks.
static func _commander_near(sim, f: Fighter) -> Fighter:
	if f.commander_idx < 0 or f.commander_idx >= sim.fighters.size(): return null
	var o: Fighter = sim.fighters[f.commander_idx]
	if o == f or o.unit == f.unit or o.side != f.side or o.unit.uid != f.commander_uid or \
			f.unit.squad != f.commander_uid or f.unit.uid == f.commander_uid or not o.unit.is_officer():
		return null
	if o.unit.dead or not o.standing() or o.state not in ["ready", "moving", "preparing", "recovering"] or o.routed or o.stance_lost:
		return null
	if sim._dist(o.cell, f.cell) > Formulas.LEADER_RADIUS: return null
	return o

static func _leader_near(sim, f: Fighter) -> float:
	var o: Fighter = sim._commander_near(f)
	return float(o.unit.skill("leader")) if o != null else 0.0

static func _flee_step(sim, f: Fighter) -> void:
	var edge_x: int = 0 if f.side == 0 else sim.grid_w - 1
	if f.cell.x == edge_x:
		f.state = "fled"
		if sim.occ[sim._ci(f.cell)] == f.idx:
			sim.occ[sim._ci(f.cell)] = -1
		sim._ev_simple("flee", f.idx, -1, "flee", {})
		return
	var fc := f.cell
	var cur := absi(fc.x - edge_x)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	# perf (same result): the cheap edge-distance filter first, then the inlined passable/occupancy tests, corners last
	for n in NEIGHBORS:
		var p: Vector2i = fc + n
		var ax := absi(p.x - edge_x)
		if ax >= cur:
			continue
		var dd := ax * 10 + absi(n.y)
		if dd >= best_d:
			continue
		if p.x < 0 or p.y < 0 or p.x >= sim.grid_w or p.y >= sim.grid_h:
			continue
		var ci: int = p.y * sim.grid_w + p.x
		if sim.tiles[ci] == T_BLOCKED or sim.occ[ci] != -1 or not sim._diag_ok(fc, p):
			continue
		best = p
		best_d = dd
	if best.x < 0:
		for n in NEIGHBORS:  # sidestep
			var p: Vector2i = fc + n
			if absi(p.x - edge_x) == cur and sim._passable(p) and sim.occ[sim._ci(p)] == -1 and sim._diag_ok(fc, p):
				best = p
				break
	if best.x < 0:
		sim._set_action(f, sim._idle_state(f), sim._ticks(f, 3.0))
		return
	sim._do_move(f, best)

## v0.014: a battle cry or taunt in the speaker's log (lazy text, CombatText "say"): cry (first blow), kill, maim;
## goblins striking from behind have their own backstab gloats.
static func _say(sim, a: Fighter, d: Fighter, kind: String, rel: String = "front") -> void:
	if a.cul == "":
		return
	if kind != "cry" and a.cul == "goblin" and rel != "front":
		kind = "back"
	var ck := "say:" + kind
	var vc := int(a.vcount.get(ck, 0))
	a.vcount[ck] = vc + 1
	sim._log(a, "ev", {"key": "say", "say": kind, "cul": a.cul, "al": a.label, "dl": d.label, "apr": a.pron, "dpr": d.pron,
		"w": sim._item_name(a.wielded) if sim._has_weapon(a) else "fists", "vk": a.voff, "vc": vc})

static func _knock_out(sim, f: Fighter, why: String) -> void:
	if f.state == "unconscious" or f.state == "dead":
		return
	if sim.occ[sim._ci(f.cell)] == f.idx:
		sim.occ[sim._ci(f.cell)] = -1
	f.state = "unconscious"
	f.prone = true
	f.action_ticks = 0
	f.pending_action = {}
	f.ko_cause = why
	sim._rip_free(f)
	if f.grabbing >= 0:
		sim._release_grab(f)
	if not f.routed:
		sim.side_down[f.side] += 1
	sim._ev_simple("unconscious", f.idx, -1, "ko_" + why, {"pain": f.unit.body.pain, "blood": sim._blood_frac(f), "brain": f.think_dmg})
	if not f.routed:
		sim._ally_down(f, false)

static func _kill(sim, f: Fighter, killer: int, why: String) -> void:
	if f.state == "dead":
		return
	if sim.occ[sim._ci(f.cell)] == f.idx:
		sim.occ[sim._ci(f.cell)] = -1
	var was_down := f.state == "unconscious" or f.routed
	# harness classification of how the end came (survey item 5)
	if why in ["bled to death", "suffocated"]:
		f.death_ctx = "bled"
	elif f.state == "unconscious" or f.prone:
		f.death_ctx = "helpless"
	elif f.last_hit_rel != "front":
		f.death_ctx = "flanked"
	else:
		f.death_ctx = "lucky"
	f.state = "dead"
	f.action_ticks = 0
	f.pending_action = {}
	f.death_cause = why
	f.unit.dead = true
	if f.grabbing >= 0:
		sim._release_grab(f)
	if f.grabbed_by >= 0:
		sim._release_grab(sim.fighters[f.grabbed_by])
	if not f.lodged.is_empty():
		sim._let_go(f, false)
	if not was_down:
		sim.side_down[f.side] += 1
	var kl := ""
	var kidx := -1
	if killer >= 0 and killer < sim.fighters.size():
		var k: Fighter = sim.fighters[killer]
		if k.side != f.side:
			kidx = killer
			k.kills += 1
			k.unit.kills += 1
			sim.kill_pairs.append([k.unit, f.unit])
			k.unit.kill_list.append(f.unit.name)
			while k.unit.kill_list.size() > Unit.KILL_LIST_MAX:   # long lives: the newest names (u.kills keeps the count)
				k.unit.kill_list.pop_front()
			Renown.on_kill(k.unit, f.unit)   # economy spec 2: kill renown (campaign/renown.gd)
			kl = k.label
			k.morale = minf(100.0, k.morale + Formulas.MORALE_KILL)
			if k.unit.skill("intimidator") > 0:
				for o in sim.fighters:
					if o.side == f.side and o != f and o.present() and sim._dist(o.cell, k.cell) <= Formulas.LEADER_RADIUS:
						sim._shock(o, Formulas.SHOCK_INTIMIDATE_PER * k.unit.skill("intimidator"), "intimidated", false)
	sim._ev_simple("death", kidx, f.idx, "death", {"why": why, "killer": kl}, true)
	if not was_down:
		sim._ally_down(f, true)

## Allies near a fallen or routed unit take a morale shock; an officer falling shakes his squad (the captain, everyone).
## Panic spreads one step per tick: the shock of a fall/rout reaches nearby allies on the next tick.
static func _ally_down(sim, f: Fighter, died: bool) -> void:
	sim._downs.append([f, died])

static func _process_downs(sim) -> void:
	# at most DOWNS_PER_TICK shocks spread per tick (panic travels; also keeps rout cascades off a single tick)
	var n := mini(sim._downs.size(), Formulas.DOWNS_PER_TICK)
	var batch: Array = sim._downs.slice(0, n)
	sim._downs = sim._downs.slice(n)
	for x in batch:
		sim._ally_down_now(x[0], x[1])

static func _ally_down_now(sim, f: Fighter, died: bool) -> void:
	var officer := f.unit.is_officer()
	var fx := f.cell.x
	var fy := f.cell.y
	for o in sim._targets[f.side]:
		# perf (same set): a plain ally out of STRESS_RADIUS is skipped before the state checks
		if not officer:
			var oc: Vector2i = o.cell
			if absi(oc.x - fx) > Formulas.STRESS_RADIUS or absi(oc.y - fy) > Formulas.STRESS_RADIUS:
				continue
		if o.side != f.side or o == f or not o.present() or o.routed:
			continue
		if officer and (o.unit.squad == f.unit.uid or f.unit.role == "captain"):
			sim._shock(o, Formulas.SHOCK_OFFICER_FALLS * (0.5 + o.tr_loyalty / 100.0), "officer_falls", died)
		elif absi(o.cell.x - f.cell.x) <= Formulas.STRESS_RADIUS and absi(o.cell.y - f.cell.y) <= Formulas.STRESS_RADIUS:   # = _dist, inlined (perf)
			if died:
				o.unit.hardness = mini(100, o.unit.hardness + 1)
			sim._shock(o, Formulas.SHOCK_ALLY_DIES if died else (Formulas.SHOCK_ALLY_ROUTS if f.routed else Formulas.SHOCK_ALLY_KO), "ally_down", died)

## Morale shock (survey item 3). Rage may trigger; below 25 the unit rolls to hold or rout.
static func _shock(sim, f: Fighter, base: float, why: String, rage_trigger: bool) -> void:
	if not f.present() or f.routed or base <= 0.0:
		return
	if f.nofear:
		return
	var amount := Formulas.shock(base, f.tr_nerve, float(f.unit.hardness))
	f.morale = maxf(0.0, f.morale - amount)
	if rage_trigger and f.rage_ticks <= 0:
		var ch := f.tr_temper / 100.0 * Formulas.RAGE_CHANCE_K
		if why == "ally_down":
			ch *= f.tr_prot / 100.0
		if Formulas.roll_rage_ok(sim.rng, ch):   # (roll_rage; the record is not kept)
			f.rage_ticks = Formulas.RAGE_TICKS
			sim._ev_simple("rage", f.idx, -1, "rage", {"why": why})
	if f.morale < Formulas.MORALE_ROUT_BELOW:
		var ch2 := Formulas.rout_chance(f.morale, f.tr_courage, f.unit.skill("discipline"))
		var mr_r := Formulas.roll_morale_draw(sim.rng)   # roll_morale; its record is built only when the unit breaks
		if mr_r < ch2:
			sim._rout(f, why, Formulas.roll_record("morale", mr_r, ch2), amount)
		else:
			sim._learn(f, "discipline", Learning.XP_DISCIPLINE)
			sim._use(f, "discipline")

static func _rout(sim, f: Fighter, why: String, roll: Dictionary, amount: float) -> void:
	f.routed = true
	f.tempo_tick = -1000
	f.target = -1
	f.pending_action = {}
	if f.grabbing >= 0:
		sim._release_grab(f)
	if not f.lodged.is_empty():
		sim._let_go(f, false)
	sim.side_down[f.side] += 1
	sim._ev_simple("rout", f.idx, -1, "rout", {"why": why, "morale": f.morale, "shock": amount, "roll": roll}, true)
	sim._ally_down(f, false)

## Packed x/y copies of the _targets cells, built on first use in a tick and kept current by _do_move
## (Fighter.tslot = the fighter's index in its side's _targets).
static func _build_tcells(sim) -> void:
	sim._tx0 = PackedInt32Array()
	sim._ty0 = PackedInt32Array()
	sim._tx1 = PackedInt32Array()
	sim._ty1 = PackedInt32Array()
	for s in 2:
		var arr: Array = sim._targets[s]
		var n := arr.size()
		var xs := PackedInt32Array()
		var ys := PackedInt32Array()
		xs.resize(n)
		ys.resize(n)
		for i in n:
			var o: Fighter = arr[i]
			var c: Vector2i = o.cell
			xs[i] = c.x
			ys[i] = c.y
			o.tslot = i
		if s == 0:
			sim._tx0 = xs
			sim._ty0 = ys
		else:
			sim._tx1 = xs
			sim._ty1 = ys
	sim._tcells_ok = true

## Periodic morale: cohesion gains, outnumbered shock, rally.
static func _morale_tick(sim, f: Fighter) -> void:
	if not f.present() or f.unit.dead:
		return
	var commander: Fighter = sim._commander_near(f)
	var leader: float = float(commander.unit.skill("leader")) if commander != null else 0.0
	# A departed/incapacitated officer cannot leave a permanently inflated cap.
	f.morale_start = clampf(f.morale_base + Formulas.LEADER_AURA_PER_LEVEL * leader, 5.0, 100.0)
	if f.routed:
		if commander != null and f.standing() and not f.stance_lost:
			sim._command_rally(f, commander, leader)
			return
		var ch := Formulas.RALLY_BASE + Formulas.RALLY_LOYALTY * f.tr_loyalty + Formulas.RALLY_LEADER * leader
		if Formulas.roll_rally_ok(sim.rng, ch):   # (roll_rally; the record is not kept)
			f.routed = false
			f.morale = Formulas.RALLY_MORALE
			sim.side_down[f.side] -= 1
			sim._ev_simple("rally", f.idx, -1, "rally", {})
		return
	var allies := 0
	var enemies := 0
	# allies within 3 tiles (cohesion); enemies actually engaging this unit (adjacent or reaching it)
	# perf (same results): cheap integer distance prefilters before the function calls
	# (cells read from the packed copies of the target cells, see _build_tcells).
	# The outnumbered test runs on every 5th morale tick only: the enemies are counted then, and the allies are counted
	# in full then; otherwise only up to the cohesion cap (more allies cannot change min(allies, cap)).
	var check_out: bool = (sim.tick / Formulas.MORALE_TICK) % 5 == 0
	var cap := f.tr_cohesion / 20.0
	if not sim._tcells_ok:
		sim._build_tcells()
	var fx := f.cell.x
	var fy := f.cell.y
	var mine: Array = sim._targets[f.side]
	var xs: PackedInt32Array = sim._tx0 if f.side == 0 else sim._tx1
	var ys: PackedInt32Array = sim._ty0 if f.side == 0 else sim._ty1
	# |x - fx| <= R as a range test (same integers)
	var x0 := fx - Formulas.COHESION_GAIN_RADIUS
	var x1 := fx + Formulas.COHESION_GAIN_RADIUS
	var y0 := fy - Formulas.COHESION_GAIN_RADIUS
	var y1 := fy + Formulas.COHESION_GAIN_RADIUS
	for i in mine.size():
		var x: int = xs[i]
		if x < x0 or x > x1:
			continue
		var y: int = ys[i]
		if y < y0 or y > y1:
			continue
		var o: Fighter = mine[i]
		if o != f and o.present() and not o.routed:
			allies += 1
			if not check_out and float(allies) >= cap:
				break
	if check_out:
		var theirs: Array = sim._targets[1 - f.side]
		xs = sim._tx1 if f.side == 0 else sim._tx0
		ys = sim._ty1 if f.side == 0 else sim._ty0
		x0 = fx - 2
		x1 = fx + 2
		y0 = fy - 2
		y1 = fy + 2
		for i in theirs.size():
			var x: int = xs[i]
			if x < x0 or x > x1:
				continue
			var y: int = ys[i]
			if y < y0 or y > y1:
				continue
			var o: Fighter = theirs[i]
			if o.standing() and not o.routed and sim._in_reach(o, f):
				enemies += 1
	var gain := Formulas.MORALE_GAIN_PER_ALLY * minf(float(allies), cap)
	f.morale = minf(f.morale_start, f.morale + gain)
	if check_out and enemies >= 2 * (allies + 1):
		var mult := Formulas.MORALE_OUTNUMBER_RACE if f.rdef.get("outnumber_morale", false) else 1.0
		sim._shock(f, Formulas.SHOCK_OUTNUMBERED * mult, "outnumbered", false)

## Scheduled command changes morale/orders only, never wounds, blood or body function.
static func _command_rally(sim, f: Fighter, officer: Fighter, leader: float) -> void:
	if not f.routed or not f.present() or f.unit.dead: return
	var before: float = f.morale
	f.routed = false
	f.morale = maxf(f.morale, Formulas.RALLY_MORALE)
	f.target = -1
	f.pending_attack = {}
	f.pending_action = {}
	f.current_attack = ""
	f.prev_cell = f.cell
	f.tempo_tick = -1000
	sim._set_action(f, sim._idle_state(f), 0)
	sim.side_down[f.side] -= 1
	sim._ev_simple("rally", officer.idx, f.idx, "officer_rally", {
		"mode":"commanded", "commander_uid":officer.unit.uid, "soldier_uid":f.unit.uid,
		"morale_before":before, "morale_after":f.morale, "leader_level":leader,
		"radius":Formulas.LEADER_RADIUS, "distance":sim._dist(officer.cell, f.cell)})
