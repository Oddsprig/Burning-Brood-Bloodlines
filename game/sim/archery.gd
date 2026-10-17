class_name Archery
extends RefCounted
## bows (docs/specs/bows.md): archers in the tick sim. Static helpers over a BattleSim (like NaturalAttacks).
## Nothing here runs in a battle without bows: BattleSim only calls in when a fighter carries a bow or quiver,
## or an arrow is in flight.
##
## POWER = draw (Formulas.bow_shot: the weaker of the archer's pull and the bow's limit; extra STR adds nothing).
## SKILL = accuracy: one aim-error roll per shot (Formulas.roll_aim); flight is deterministic after it.
## Flight: one projectile per arrow on the tile grid, sampled every PROBE tiles; it strikes the first ENEMY silhouette
## on its path (no friendly fire, also after a pass-through); flat shots are low the whole way, long shots arc over
## the ranks and come down in the last ARC_FALL_TILES. Defences in order: dodge, shield (x2 vs projectiles, the
## block roll decides boss/body/rim), armour; impact runs through BattleSim._strike like a thrust (arrow branches).
## AI: archers keep their distance and shoot, back off as enemies close, go to the sidearm when an enemy is inside
## min range, will reach them before the next draw finishes, or the quiver is empty (drop the bow when panicked or
## pressed, else sling it); back to the bow when the enemy is past min range + margin, picking it up if dropped.

const PROBE := 0.34   # tiles between line-test samples (coarse grid; a man is a tile)

# =====================================================================================================
# setup
# =====================================================================================================
static func init_fighter(sim, f: Fighter) -> void:
	var u := f.unit
	var qm := 0.0
	for k in u.quiver:
		qm += float(DB.arrows.get(k, {}).get("mass", 0.05)) * int(u.quiver[k])
	f.other_mass += qm
	var b: Item = u.equip.get("ranged", null)
	if b != null and DB.is_bow(b.tid) and b.wear < 3:
		f.bow = b
		f.bow_state = "hand" if u.arrows() > 0 else "slung"
		f.bow_hand = f.bow_state == "hand"
		sim._bows_on = true

static func arrow_kind(u: Unit) -> String:
	var best := ""
	var bn := 0
	for k in u.quiver:
		var n := int(u.quiver[k])
		if n > bn:
			best = k
			bn = n
	return best

## Shot solution for the archer and arrow kind, cached with the tempo (exertion/pain drift slowly).
static func solution(sim, f: Fighter, kind: String, fresh: bool = false) -> Dictionary:
	if not fresh and kind == f.bsol_kind and sim.tick - f.bsol_tick < Formulas.TEMPO_CACHE_TICKS and not f.bsol.is_empty():
		return f.bsol
	var u := f.unit
	var b := u.body
	var pull := Formulas.pull_force(float(u.attr("STR")), u.mass(), float(u.attr("END")),
		b.exertion / maxf(100.0, float(u.attr("END"))), b.pain, b.blood / maxf(1.0, b.blood_max))
	var reach := Formulas.draw_length(float(f.rdef.get("height", 1.0)) * float(u.size_h) / 100.0, float(u.arm_len))
	var bt: Dictionary = sim._tmpl(f.bow)
	var ad: Dictionary = DB.arrows.get(kind, {})
	var sol := Formulas.bow_shot(pull, reach, bt, DB.quality_mult(f.bow.quality), f.bow.vr, float(ad.get("mass", 0.055)))
	var lvl: float = sim._eff(f, "bow", "aim")
	sol["lvl"] = lvl
	sol["draw_t"] = Formulas.draw_ticks(float(sol["strain"]))
	sol["aim_t"] = Formulas.aim_ticks(lvl)
	sol["flat"] = Formulas.flat_range_tiles(float(sol["v0"]))
	sol["range"] = Formulas.max_range_tiles(float(sol["v0"]))
	sol["kind"] = kind
	f.bsol = sol
	f.bsol_kind = kind
	f.bsol_tick = sim.tick
	return sol

# =====================================================================================================
# decisions
# =====================================================================================================
## Nearest standing enemy that is not running: [fighter or null, Chebyshev distance].
static func nearest_enemy(sim, f: Fighter) -> Array:
	var best: Fighter = null
	var bd := 1 << 30
	for e in sim._targets[1 - f.side]:
		if not e.standing() or e.routed:
			continue
		var d: int = maxi(absi(e.cell.x - f.cell.x), absi(e.cell.y - f.cell.y))
		if d < bd:
			bd = d
			best = e
	return [best, bd]

## The archer's turn. Returns true when it set an action (shoot, kite, switch weapons, fetch the bow).
static func decide(sim, f: Fighter) -> bool:
	if f.bow == null or f.bow_state == "broken":
		return false
	var u := f.unit
	var ne := nearest_enemy(sim, f)
	var near: Fighter = ne[0]
	var dn: int = ne[1]
	var bt: Dictionary = sim._tmpl(f.bow)
	var min_r := int(bt.get("min_range", Formulas.BOW_MIN_RANGE))
	if not f.bow_hand:
		# sidearm in hand: back to the bow once the enemy is gone or pushed past min range + margin
		if u.arrows() <= 0 or f.prone or f.grabbing >= 0 or f.grabbed_by >= 0 or not f.lodged.is_empty():
			return false
		if near != null and dn <= min_r + Formulas.BOW_SWITCH_MARGIN:
			return false
		if f.bow_state == "slung":
			sim._begin_special(f, "unsling", Formulas.BOW_UNSLING_TICKS, {})
			return true
		if f.bow_state == "dropped":
			var db: int = maxi(absi(f.bow_cell.x - f.cell.x), absi(f.bow_cell.y - f.cell.y))
			if db <= 1:
				sim._begin_special(f, "pickup_bow", Formulas.RETRIEVE_TICKS, {})
				return true
			if db <= Formulas.BOW_FETCH_TILES and not f.hold:
				var before := f.cell
				sim._move_toward(f, f.bow_cell)
				return f.cell != before or f.action_ticks > 0
		return false
	# the bow is in his hands
	if f.grabbed_by >= 0:
		to_melee(sim, f, true, "grabbed")
		return true
	if u.arrows() <= 0:
		to_melee(sim, f, near != null and dn <= 1, "out of arrows")
		return true
	if near == null:
		sim._set_action(f, sim._idle_state(f), sim._ticks(f, 5.0))
		return true
	if dn <= min_r:
		to_melee(sim, f, dn <= 1 or f.morale < Formulas.BOW_PANIC_MORALE, "too close")
		return true
	var kind := arrow_kind(u)
	var sol := solution(sim, f, kind)
	var shoot_t := (float(sol["draw_t"]) + float(sol["aim_t"])) * f.tempo
	var tpt: float = Formulas.move_ticks(near.speed, sim._terrain_mult, near.prone) * near.walk_mult
	var reach_t := float(maxi(0, dn - near.reach_tiles)) * tpt
	var pressed := reach_t < shoot_t
	if (dn <= Formulas.BOW_KITE_TILES or pressed) and not f.hold and f.grabbed_by < 0:
		if kite(sim, f, near):
			return true
	if pressed:
		to_melee(sim, f, dn <= 2 or f.morale < Formulas.BOW_PANIC_MORALE, "too close")
		return true
	# a target: the nearest-ish enemy (DF-dumb), kept while it is still worth shooting
	var t: Fighter = sim.fighters[f.target] if f.target >= 0 else null
	f.retarget_count += 1
	if t == null or not t.alive() or t.state == "fled" or t.waiting or t.state == "unconscious" or f.retarget_count % 4 == 0:
		sim._pick_target(f)
		t = sim.fighters[f.target] if f.target >= 0 else null
	if t == null:
		sim._set_action(f, sim._idle_state(f), sim._ticks(f, 5.0))
		return true
	if t.cell.x != f.cell.x:
		f.facing = 1 if t.cell.x > f.cell.x else -1
	var dist := Vector2(t.cell - f.cell).length()
	if dist > float(sol["range"]):
		if f.hold:
			sim._set_action(f, sim._idle_state(f), sim._ticks(f, 3.0))
		else:
			sim._move_toward(f, t.cell)
		return true
	sim._begin_special(f, "shoot", int(round(float(sol["draw_t"]) + float(sol["aim_t"]))), {"t": t.idx, "kind": kind})
	return true

## One step away from the threat (edges, walls and other men block the retreat). False when cornered.
static func kite(sim, f: Fighter, threat: Fighter) -> bool:
	var fc := f.cell
	var cur: int = maxi(absi(fc.x - threat.cell.x), absi(fc.y - threat.cell.y))
	var best := Vector2i(-1, -1)
	var bs := -INF
	for n in BattleSim.NEIGHBORS:
		var p: Vector2i = fc + n
		if p.x < 0 or p.y < 0 or p.x >= sim.grid_w or p.y >= sim.grid_h:
			continue
		var ci: int = p.y * sim.grid_w + p.x
		if sim.tiles[ci] == BattleSim.T_BLOCKED or sim.occ[ci] != -1 or not sim._diag_ok(fc, p):
			continue
		var gx := absi(p.x - threat.cell.x)
		var gy := absi(p.y - threat.cell.y)
		var dd := maxi(gx, gy)
		if dd <= cur:
			continue
		var sc := dd * 1000.0 + gx * gx + gy * gy - (500.0 if sim.tiles[ci] == BattleSim.T_ROUGH else 0.0)
		if sc > bs:
			bs = sc
			best = p
	if best.x < 0:
		return false
	sim._do_move(f, best)
	return true

## Bow out of the hands: drop it (fast; panic or an enemy on him) or sling it (slower, composed).
static func to_melee(sim, f: Fighter, drop: bool, why: String) -> void:
	var side := sidearm_name(sim, f)
	if drop:
		f.bow_state = "dropped"
		f.bow_hand = false
		f.bow_cell = f.cell
		sim._bows_down += 1
		var m := f.bow.mass()
		f.other_mass -= m
		f.gear_mass -= m
		f.tempo_tick = -1000
		f.reach_tiles = sim._reach_of(f)
		sim._ev_simple("drop", f.idx, -1, "drop_bow", {"w": sim._item_name(f.bow), "s": side, "why": why})
		sim._set_action(f, sim._idle_state(f), sim._ticks(f, float(Formulas.BOW_DROP_TICKS)))
	else:
		sim._begin_special(f, "sling", Formulas.BOW_SLING_TICKS, {"why": why})

static func sidearm_name(sim, f: Fighter) -> String:
	if f.wielded != null and not f.weapon_dropped:
		return sim._item_name(f.wielded)
	return "fists"

## The end of a bow action (BattleSim._finish_special). Returns the recover ticks.
static func finish(sim, f: Fighter, kind: String, pa: Dictionary) -> int:
	match kind:
		"shoot":
			loose(sim, f, pa)
			return int(round(Formulas.NOCK_TICKS * Formulas.RECOVER_TICK_MULT))
		"sling":
			if f.bow_hand:
				f.bow_state = "slung"
				f.bow_hand = false
				f.reach_tiles = sim._reach_of(f)
				sim._ev_simple("drop", f.idx, -1, "sling_bow", {"w": sim._item_name(f.bow), "s": sidearm_name(sim, f), "why": pa.get("why", "")})
		"unsling":
			if f.bow_state == "slung" and f.bow != null:
				f.bow_state = "hand"
				f.bow_hand = true
				sim._ev_simple("freed", f.idx, -1, "unsling_bow", {"w": sim._item_name(f.bow)})
		"pickup_bow":
			if f.bow_state == "dropped" and maxi(absi(f.bow_cell.x - f.cell.x), absi(f.bow_cell.y - f.cell.y)) <= 1:
				f.bow_state = "hand"
				f.bow_hand = true
				sim._bows_down -= 1
				var m := f.bow.mass()
				f.other_mass += m
				f.gear_mass += m
				f.tempo_tick = -1000
				sim._ev_simple("freed", f.idx, -1, "pickup_bow", {"w": sim._item_name(f.bow)})
	return 1

## Someone steps where a bow lies: it breaks under a heavy man (deterministic; never its owner).
static func trample(sim, f: Fighter, p: Vector2i) -> void:
	for g in sim.fighters:
		if g == f or g.bow_state != "dropped" or g.bow_cell != p:
			continue
		if f.unit.mass() + f.gear_mass >= Formulas.BOW_TRAMPLE_KG:
			g.bow_state = "broken"
			g.bow.wear = 3   # broken: scrap after the battle
			sim._bows_down -= 1
			sim._ev_simple("drop", f.idx, g.idx, "bow_trampled", {"w": sim._item_name(g.bow)})

# =====================================================================================================
# loosing an arrow
# =====================================================================================================
static func loose(sim, f: Fighter, pa: Dictionary) -> void:
	var u := f.unit
	if not f.bow_hand or f.bow == null:
		return
	var ti := int(pa.get("t", -1))
	var t: Fighter = sim.fighters[ti] if ti >= 0 else null
	if t == null or not t.alive() or t.state == "fled" or t.waiting:
		t = nearest_enemy(sim, f)[0]
	if t == null:
		return
	var kind := String(pa.get("kind", ""))
	if int(u.quiver.get(kind, 0)) <= 0:
		kind = arrow_kind(u)
	if kind == "":
		return
	var sol := solution(sim, f, kind, true)
	var ad: Dictionary = DB.arrows[kind]
	# the arrow leaves the quiver: spent shots are spent
	u.quiver[kind] = int(u.quiver[kind]) - 1
	if int(u.quiver[kind]) <= 0:
		u.quiver.erase(kind)
	f.other_mass -= float(ad["mass"])
	f.gear_mass -= float(ad["mass"])
	f.shots += 1
	var qm := DB.quality_mult(f.bow.quality)
	var recent := 0
	for t0 in t.defence_ticks:
		if sim.tick - int(t0) <= Formulas.SATURATION_WINDOW:
			recent += 1
	var tmov: bool = sim.tick - t.last_move_tick < Formulas.AIM_MOVE_TICKS
	var smov: bool = sim.tick - f.last_move_tick < Formulas.AIM_MOVE_TICKS
	var sd := Formulas.aim_sd(float(sol["lvl"]), float(sol["strain"]), qm, f.morale, tmov, smov, recent)
	var ar := Formulas.roll_aim(sim.rng, sd)
	# the draw: END, XP, attribute use (the hold costs more near the archer's limit)
	var strain := float(sol["strain"])
	u.body.exertion += Formulas.exertion_swing(float(sol["e_drawn"]) * (1.0 + Formulas.HOLD_EXERT_K * strain * strain),
		float(u.attr("END")), f.breath_bad) * f.fatigue_mult
	sim._learn(f, "bow", Learning.XP_SWING)
	sim._learn(f, "fighter", Learning.XP_FIGHTER)
	sim._use(f, "bow")
	Learning.note_use(f.attr_use, "draw", strain)
	# geometry (tile coordinates; a cell's centre is its integer position)
	var ox := float(f.cell.x)
	var oy := float(f.cell.y)
	var to := Vector2(float(t.cell.x) - ox, float(t.cell.y) - oy)
	var dist := to.length()
	var dir := to.normalized().rotated(deg_to_rad(float(ar["lat"])))
	var flat := dist <= float(sol["flat"])
	var elev_rad := deg_to_rad(float(ar["elev"]))
	var land: float
	if flat:
		land = dist + Formulas.FLAT_OVERRUN_TILES
		if elev_rad < 0.0:   # aimed low: it meets the ground before the overrun
			land = minf(land, Formulas.AIM_HEIGHT_M / tan(-elev_rad) / Formulas.TILE_M)
	else:
		land = dist * (1.0 + Formulas.ELEV_RANGE_K * elev_rad)
	land = clampf(land, 1.0, float(sol["range"]))
	if t.cell.x != f.cell.x:
		f.facing = 1 if t.cell.x > f.cell.x else -1
	var att := float(sol["lvl"]) + float(sol["v0"]) / Formulas.ARROW_SPEED_LEVELS
	var proj := {"id": sim._proj_next, "a": f.idx, "side": f.side, "kind": kind, "x": ox, "y": oy, "ox": ox, "oy": oy,
		"dx": dir.x, "dy": dir.y, "s": 0.0, "L": land, "flat": flat, "tan_e": tan(elev_rad), "v": float(sol["v0"]),
		"m": float(sol["m"]), "hit": [], "last": f.cell.y * sim.grid_w + f.cell.x, "att": att}
	sim._proj_next += 1
	sim.projectiles.append(proj)
	sim._ev_simple("shoot", f.idx, t.idx, "shoot", {"w": DB.arrow_name(kind), "roll": ar, "sol": [sol["pull"], sol["reach"],
		sol["draw_n"], sol["draw_m"], sol["e_bow"], sol["e_arch"], sol["e_drawn"], sol["eff"], sol["E"], sol["m"], sol["v0"],
		sol["strain"], sol["lvl"], sol["flat"], sol["range"]], "dist": dist, "land": land, "flat": flat,
		"left": u.arrows(), "tm": tmov, "sm": smov, "sat": recent})
	if u.arrows() == 0:
		sim._ev_simple("drop", f.idx, -1, "out_of_arrows", {"w": sim._item_name(f.bow)})

# =====================================================================================================
# flight
# =====================================================================================================
static func step_projectiles(sim) -> void:
	var down := {}
	var keep := []
	var ps: Array = sim.projectiles
	for p in ps:
		if fly(sim, p, down):
			keep.append(p)
		elif sim.keep_shot_log:
			sim.shot_log.append({"id": p["id"], "a": p["a"], "hit": (p["hit"] as Array).duplicate(), "s": p["s"], "L": p["L"]})
	sim.projectiles = keep

static func _field(sim, kind: String, where: String) -> void:
	var f: Dictionary = sim.arrow_field.get(kind, {})
	f[where] = int(f.get(where, 0)) + 1
	sim.arrow_field[kind] = f

## Moves one arrow through this tick. Returns true while it is still in the air.
static func fly(sim, p: Dictionary, down: Dictionary) -> bool:
	var v: float = p["v"]
	var s0: float = p["s"]
	var L: float = p["L"]
	var ds := v * Formulas.TICK_SECONDS / Formulas.TILE_M
	var s1 := minf(s0 + ds, L)
	var ox: float = p["ox"]
	var oy: float = p["oy"]
	var dx: float = p["dx"]
	var dy: float = p["dy"]
	var flat: bool = p["flat"]
	var side: int = p["side"]
	var gw: int = sim.grid_w
	var s := s0
	while s < s1:
		s = minf(s + PROBE, s1)
		var x := ox + dx * s
		var y := oy + dy * s
		var cx := int(round(x))
		var cy := int(round(y))
		if cx < 0 or cy < 0 or cx >= gw or cy >= sim.grid_h:
			_field(sim, p["kind"], "lost")   # off the field
			return false
		var ci := cy * gw + cx
		if ci == int(p["last"]):
			continue
		p["last"] = ci
		var low := flat or s >= L - Formulas.ARC_FALL_TILES
		if low and sim.tiles[ci] == BattleSim.T_BLOCKED:
			_field(sim, p["kind"], "ground")   # into a wall
			return false
		if not low:
			continue
		var oi: int = sim.occ[ci]
		var vic: Fighter = null
		var hw := 0.0
		if oi >= 0:
			var o: Fighter = sim.fighters[oi]
			if o.side != side and o.standing() and not (p["hit"] as Array).has(oi):
				vic = o
		elif s >= L - 1.0:   # the last tile of the fall reaches men lying on the ground
			if down.is_empty():
				down["_"] = true
				for g in sim.fighters:
					if g.alive() and g.helpless() and not g.waiting and g.state != "fled":
						down[g.cell.y * gw + g.cell.x] = g.idx
			var di: int = down.get(ci, -1)
			if di >= 0:
				var o2: Fighter = sim.fighters[di]
				if o2.side != side and o2.alive() and not (p["hit"] as Array).has(di):
					vic = o2
		if vic == null:
			continue
		hw = Formulas.silhouette_half_tiles(vic.unit.mass())
		var perp := absf((float(cx) - ox) * dy - (float(cy) - oy) * dx)
		if perp > hw:
			continue
		if flat and vic.standing():
			var along := ((float(cx) - ox) * dx + (float(cy) - oy) * dy) * Formulas.TILE_M
			var hh := Formulas.SILHOUETTE_HALF_H_M * float(vic.rdef.get("height", 1.0))
			if absf(along * float(p["tan_e"])) > hh:
				continue   # over his head or into the ground short of him
		p["s"] = s
		p["x"] = x
		p["y"] = y
		if not impact(sim, p, vic, perp, hw):
			return false
		v = p["v"]
	p["s"] = s1
	p["x"] = ox + dx * s1
	p["y"] = oy + dy * s1
	p["v"] = v * exp(-(s1 - s0) * Formulas.TILE_M / Formulas.drag_len_m(float(p["m"])))
	if s1 >= L - 0.0001:
		_field(sim, p["kind"], "ground")
		return false
	return true

## Relative direction the arrow comes from, seen by the man it reaches.
static func rel_of(p: Dictionary, o: Fighter) -> String:
	var dx: float = p["dx"]
	if absf(dx) < 0.35:
		return "side"
	return "front" if signf(-dx) == float(o.facing) else "rear"

## The arrow reaches a man: defences and the layer tests (BattleSim._strike with the shot). True = it flies on.
static func impact(sim, p: Dictionary, o: Fighter, perp: float, hw: float) -> bool:
	var a: Fighter = sim.fighters[int(p["a"])]
	var kind: String = p["kind"]
	var ad: Dictionary = DB.arrows[kind]
	var shape: Dictionary = DB.arrow_shapes.get(String(ad.get("shape", "bodkin")), {})
	var m: float = p["m"]
	var v: float = p["v"]
	var e := 0.5 * m * v * v
	var tip: String = ad.get("tip", "wood")
	var w_size := float(ad.get("w_size_cm3", ad.get("tip_cm3", 1.0)))
	var sq := clampf(1.0 - 0.5 * pow(perp / maxf(hw, 0.01), 2.0), 0.5, 1.0)   # an edge-of-the-body hit lands obliquely
	(p["hit"] as Array).append(o.idx)
	sim._shot = {"kind": kind, "name": DB.arrow_name(kind), "E": e, "p": m * v, "v": v, "m": m, "sq": sq,
		"mat": DB.materials.get(tip, DB.materials["wood"]), "w_size": w_size, "att": float(p["att"]), "rel": rel_of(p, o),
		"shape": String(ad.get("shape", "bodkin")), "dist": float(p["s"]), "contact": float(shape.get("contact", 5)),
		"pen": float(shape.get("pen", 20000))}
	sim._shot_out = {}
	var atk := {"verb": "shoot", "type": "edge", "contact": float(shape.get("contact", 5)), "penetration": float(shape.get("pen", 20000))}
	sim._strike(a, o, atk, {}, {})
	var out: Dictionary = sim._shot_out
	sim._shot = {}
	sim._shot_out = {}
	sim._force_part = ""
	if out.get("dodged", false):
		return true   # he got out of its way; it flies on
	if out.get("exit", false):
		p["v"] = sqrt(2.0 * maxf(float(out["E"]), 0.0) / m)
		return true   # out the other side: on to the next enemy behind
	var end := String(out.get("end", "body"))
	if end == "":
		end = "body"
	_field(sim, kind, end)
	return false

# =====================================================================================================
# defences (from BattleSim._strike): dodge, then shield (x2 vs projectiles), then armour; no parrying arrows
# =====================================================================================================
static func defend(sim, a: Fighter, d: Fighter, D: Dictionary, steps: Array, att: float, rel: String) -> bool:
	var V: bool = sim.verbose
	var du := d.unit
	var rng: RandomNumberGenerator = sim.rng
	if rel != "front":
		var sr := Formulas.roll_spot(rng, Formulas.spot_chance(rel == "rear", du.skill("observer"), sim._alv(d, "spot")))
		if V: steps.append(sr)
		if not sr["ok"]:
			if V: steps.append(["note", "arrow from the %s unseen: no defence" % rel])
			return false
	if d.grabbed_by >= 0:
		return false
	var recent := 0
	for t0 in d.defence_ticks:
		if sim.tick - int(t0) <= Formulas.SATURATION_WINDOW:
			recent += 1
	var sat := Formulas.saturation(recent)
	# ---- dodge (AGI, Dodger; worse when busy in melee or tired)
	var enc: float = sim._enc_ratio(d) * (1.0 - minf(0.75, du.skill("armor_user") * Formulas.ARMOR_USER_RELIEF))
	var def: float = sim._eff(d, "dodger", "dodge") - Formulas.DODGE_ENC_LEVELS * enc
	var busy: bool = sim._enemy_reaching_me(d) != null
	if busy:
		def -= Formulas.ARROW_BUSY_DODGE
	var pt := Formulas.contest_through(att, def)
	var p_def := maxf(0.0, 1.0 - pt - sat)
	if d.rage_ticks > 0:
		p_def *= Formulas.RAGE_DEF_MULT
	if sim._held_in_place(d):
		p_def *= Formulas.HELD_VICTIM_DODGE
	if not d.lodged.is_empty():
		p_def *= Formulas.HELD_WIELDER_DODGE
	var cr := Formulas.roll_contest(rng, 1.0 - p_def, "dodge")
	if V:
		steps.append(["def", "dodge" + (" (busy in melee)" if busy else ""), def, pt, sat, 1.0 - p_def, recent])
		steps.append(cr)
	_defended(sim, d)
	if not cr["ok"]:
		sim._learn(d, "dodger", Learning.XP_DEFEND)
		sim._learn(d, "fighter", Learning.XP_FIGHTER)
		sim._use(d, "dodger")
		D["out"] = "dodge"
		D["def"] = "dodge"
		sim.last_strike["defence"] = "dodge"
		sim._shot_out = {"dodged": true}
		sim._strike_end(a, d, D, "dodge", "", false)
		return true
	sim._learn(d, "dodger", Learning.XP_DEFEND_TRY)
	# ---- shield block, x2 against projectiles [DF]; the block roll decides the spot (boss, body, rim)
	var sh: Item = sim._shield(du)
	if sh == null or d.shield_dropped or d.bow_hand or not (rel == "front" or (rel == "side" and du.skill("observer") >= Formulas.OBSERVER_ARC_LEVEL)):
		return false
	var sht: Dictionary = sim._tmpl(sh)
	var def2: float = sim._eff(d, "shield_user", "block") + Formulas.DEF_BASE["block"] * float(sht.get("block", 1.0))
	var pt2 := Formulas.contest_through(att, def2)
	var p_def2 := minf(Formulas.CONTEST_MAX, maxf(0.0, 1.0 - pt2 - sat) * Formulas.PROJECTILE_BLOCK_MULT)
	var cr2 := Formulas.roll_contest(rng, 1.0 - p_def2, "block")
	if V:
		steps.append(["def", "block (x%.0f vs arrows)" % Formulas.PROJECTILE_BLOCK_MULT, def2, pt2, sat, 1.0 - p_def2, recent])
		steps.append(cr2)
	_defended(sim, d)
	if cr2["ok"]:
		sim._learn(d, "shield_user", Learning.XP_DEFEND_TRY)
		return false
	sim._learn(d, "shield_user", Learning.XP_DEFEND)
	sim._learn(d, "fighter", Learning.XP_FIGHTER)
	sim._use(d, "shield_user")
	var shot: Dictionary = sim._shot
	var u := clampf((float(cr2["r"]) - (1.0 - p_def2)) / maxf(p_def2, 0.000001), 0.0, 1.0)   # 1 = squarest block
	var spot := "boss" if u >= 1.0 - Formulas.SHIELD_BOSS_SHARE else ("rim" if u < Formulas.SHIELD_RIM_SHARE else "body")
	var square := Formulas.SHIELD_RIM_SQUARE if spot == "rim" else (Formulas.SHIELD_BOSS_SQUARE if spot == "boss" else 0.6 + 0.4 * u)
	var th := float(sht.get("thickness", 2)) * (Formulas.SHIELD_BOSS_THICK if spot == "boss" else (Formulas.SHIELD_RIM_THICK if spot == "rim" else 1.0))
	var smat: Dictionary = sh.mat()
	var tmat: Dictionary = shot["mat"]
	var e_in := float(shot["E"]) * float(shot["sq"]) * square
	var R := Formulas.edge_resistance(smat, tmat, float(shot["contact"]), DB.quality_mult(sh.quality), 1.0, th, true)
	var shn: String = sim._item_name(sh)
	D["sh"] = shn
	D["spot"] = spot
	D["def"] = "block"
	sim.last_strike["defence"] = "block"
	if e_in >= R:
		var left := maxf(0.0, (e_in - R * Formulas.ARROW_ARMOR_SPEND) * Formulas.PASS_KEEP)
		if V: steps.append(["note", "shield %s (%s, %.1f mm): EDGE E %.1f (square x%.2f) >= R %.1f -> through, %.1f J into the arm behind" % [shn, spot, th, e_in, square, R, left]])
		shot["E"] = left
		shot["sq"] = 1.0
		shot["p"] = float(shot["m"]) * sqrt(2.0 * left / maxf(float(shot["m"]), 0.001))
		D["via"] = shn
		var behind := "arm_lower_l" if du.body.has_part("arm_lower_l") and not d.lost.has("arm_lower_l") else "torso_upper"
		sim._force_part = behind
		return false
	var deflect := Formulas.blunt_deflects(float(shot["w_size"]), tmat, float(shot["contact"]), smat)
	var stuck := not deflect and spot != "boss" and e_in >= R * Formulas.ARROW_STICK_FRAC
	if V: steps.append(["note", "shield %s (%s, %.1f mm): EDGE E %.1f (square x%.2f) < R %.1f -> %s" % [shn, spot, th, e_in, square, R,
		"sticks in the shield" if stuck else "glances off"]])
	if stuck:
		d.shield_arrows += 1
		var m := float(shot["m"])
		d.other_mass += m   # lodged arrows make the shield heavier
		d.gear_mass += m
		D["out"] = "shield_stuck"
		sim._shot_out = {"end": "shield"}
	else:
		D["out"] = "shield_boss" if spot == "boss" else "shield_glance"
		sim._shot_out = {"end": "armor"}
	sim._strike_end(a, d, D, "block", "", false)
	return true

## Inspection/test hook: fighter ai's arrow of `kind` (his own draw and bow, after `dist_tiles` of flight) arrives at
## fighter di dead on (perp 0), through the normal defences unless `land`. Uses sim.rng like any shot.
## Returns last_strike + {"end", "exit", "E_in"}.
static func debug_shot(sim, ai: int, di: int, kind: String, dist_tiles: float = 8.0, part: String = "", land: bool = false) -> Dictionary:
	var a: Fighter = sim.fighters[ai]
	var d: Fighter = sim.fighters[di]
	var sol := solution(sim, a, kind, true)
	var ad: Dictionary = DB.arrows[kind]
	var shape: Dictionary = DB.arrow_shapes.get(String(ad.get("shape", "bodkin")), {})
	var m := float(sol["m"])
	var v := float(sol["v0"]) * exp(-dist_tiles * Formulas.TILE_M / Formulas.drag_len_m(m))
	var dir := 1.0 if d.cell.x >= a.cell.x else -1.0
	sim._shot = {"kind": kind, "name": DB.arrow_name(kind), "E": 0.5 * m * v * v, "p": m * v, "v": v, "m": m, "sq": 1.0,
		"mat": DB.materials.get(String(ad.get("tip", "wood")), DB.materials["wood"]), "w_size": float(ad.get("w_size_cm3", ad.get("tip_cm3", 1.0))),
		"att": float(sol["lvl"]) + v / Formulas.ARROW_SPEED_LEVELS, "rel": rel_of({"dx": dir}, d), "shape": String(ad.get("shape", "bodkin")),
		"dist": dist_tiles, "contact": float(shape.get("contact", 5)), "pen": float(shape.get("pen", 20000))}
	var e_in := float(sim._shot["E"])
	sim._shot_out = {}
	sim._force_part = part
	sim._force_land = land
	var atk := {"verb": "shoot", "type": "edge", "contact": float(shape.get("contact", 5)), "penetration": float(shape.get("pen", 20000))}
	sim._strike(a, d, atk, {}, {})
	var out: Dictionary = sim._shot_out
	sim._shot = {}
	sim._shot_out = {}
	sim._force_part = ""
	sim._force_land = false
	var r: Dictionary = sim.last_strike.duplicate(true)
	r["end"] = String(out.get("end", "dodge" if out.get("dodged", false) else ""))
	r["exit"] = bool(out.get("exit", false))
	r["E_in"] = e_in
	r["E_out"] = float(out.get("E", 0.0))
	return r

static func _defended(sim, d: Fighter) -> void:
	d.defence_ticks.append(sim.tick)
	if d.defence_ticks.size() > 8:
		d.defence_ticks.pop_front()
	d.unit.body.exertion += Formulas.exertion_defend(float(d.unit.attr("END")), d.breath_bad) * d.fatigue_mult

# =====================================================================================================
# the end of the battle
# =====================================================================================================
## Arrows still in the air come down (the sim's last tick; kept light: the pulling is pull_lodged, after it).
static func end_battle(sim) -> void:
	for p in sim.projectiles:
		_field(sim, p["kind"], "ground")
		if sim.keep_shot_log:
			sim.shot_log.append({"id": p["id"], "a": p["a"], "hit": (p["hit"] as Array).duplicate(), "s": p["s"], "L": p["L"]})
	sim.projectiles = []

## After the battle (battle screen hand-off, tests): arrows lodged in the living are pulled on the field; the exit
## tears the layer it sits in, broadheads more (bows.json shape "tear"). Idempotent.
static func pull_lodged(sim) -> void:
	for f in sim.fighters:
		if f.arrows_in.is_empty() or not f.alive():
			continue
		for ai in f.arrows_in:
			var L: Dictionary = sim._lodge_layer(f, String(ai["part"]), String(ai["layer"]))
			if L.is_empty():
				continue
			var shape: Dictionary = DB.arrow_shapes.get(String(DB.arrows.get(String(ai["kind"]), {}).get("shape", "bodkin")), {})
			var dmg := clampf(Formulas.ARROW_PULL_TEAR * float(shape.get("tear", 1.0)), 0.01, 0.3)
			var pdef: Dictionary = sim._pdef(f.unit.body, String(ai["part"]))
			sim._wound_layer(f, String(ai["part"]), pdef, L, sim._ldef(String(ai["part"]), pdef, String(ai["layer"])), dmg, "torn", true, false)
			sim._ev_simple("freed", f.idx, -1, "pull_arrow", {"w": DB.arrow_name(String(ai["kind"])), "part": String(pdef.get("name", ai["part"]))})
		f.arrows_in.clear()

## Arrows fit to shoot again from the battle's field (for the side that holds it): {arrow id: n}. The rest are
## broken (scrap wood). Deterministic shares of each place they ended up (Formulas.ARROW_RECOVER).
static func recovered(arrow_field: Dictionary) -> Dictionary:
	var out := {}
	for k in arrow_field:
		var n := 0.0
		var f: Dictionary = arrow_field[k]
		for where in Formulas.ARROW_RECOVER:
			n += float(f.get(where, 0)) * float(Formulas.ARROW_RECOVER[where])
		if int(n) > 0:
			out[k] = int(n)
	return out
