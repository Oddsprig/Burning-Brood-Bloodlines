class_name NaturalAttacks
extends RefCounted
## Monsters wave 1: creature natural attacks on the existing tissue sim (no HP, no special-case combat).
## Called from BattleSim through small hooks (_attacks_of, _swing_for, _deliver, _decide, _finish_special).
##
## - Attacks come from the creature's data (data/creatures.json "attacks"): bite, claw, gore, charge.
##   An attack "needs" a part (head for bites/gores, a front paw for claws) that is still attached.
## - Bite/claw/gore momentum: base p x sqrt(torque ratio x mass ratio), exactly like punch/kick/bite in
##   Formulas.natural_swing, so a 200 kg bear hits ~3x a man's bite and a 40 kg wolf ~0.65x.
## - Charge: momentum = CHARGE_K x body mass x run speed (from the creature's sprint gait and its tempo), only
##   after a run-up (it moved as its last action). Blunt; it staggers (attack "stagger").
## - Latch (bite-and-hold) reuses the wrestling grab: a bite that gets through the coat rolls the grab contest; the
##   latched creature then "drags" (the takedown contest, pack mass counts: every packmate holding the same victim
##   adds its mass) and "shakes" (bites again; the victim is held and cannot defend, exactly as a grabbed man).
## Tags: [DF] mechanics shaped after DF, [ours] our numbers.

const CHARGE_K := 0.1                 # [ours] kg m/s of charge per kg of body per m/s of run speed
const CHARGE_RUNUP_TICKS := 14        # [ours] a charge needs a move within this many ticks (the run-up)
const RUN_SPEED_K := 1300.0           # m/s = 1300 / sprint gait (1 tile = 1 m; ticks/tile = gait/65; 1 tick = 0.05 s)
const DRAG_TICKS := 4                 # [ours] like the takedown
const SHAKE_PREP_MULT := 0.7          # [ours] a latched bite needs no new opening

static func is_creature(f: Fighter) -> bool:
	return bool(f.unit.race_def().get("creature", false))

## Is any part with this id prefix still attached ("foot_front" = either front paw)?
static func part_ok(f: Fighter, prefix: String) -> bool:
	if prefix == "":
		return true
	for pid in f.unit.body.defs():   # every part of the plan (the body stores only wounded parts)
		if String(pid).begins_with(prefix) and not f.lost.has(pid):
			return true
	return false

static func run_speed(f: Fighter) -> float:
	var gaits: Array = f.unit.race_def().get("gait", Formulas.GAIT_DEFAULT)
	return RUN_SPEED_K / maxf(50.0, float(gaits[0])) / maxf(0.5, f.tempo)

## Deterministic charge momentum: mass x speed (scales linearly with both).
static func charge_momentum(mass_kg: float, speed_mps: float) -> float:
	return CHARGE_K * mass_kg * speed_mps

static func charge_ready(sim, f: Fighter) -> bool:
	return not f.prone and f.grabbing < 0 and sim.tick - f.last_move_tick <= CHARGE_RUNUP_TICKS

## Per race (cached, read-only, shared by every fighter): [[attack, needed part ids], ...], the shake variant of
## the latching bite, and the feeble fallback. Attack dicts are never mutated by the sim.
static var _cache: Dictionary = {}

static func _table(race: String, rd: Dictionary) -> Dictionary:
	if _cache.has(race):
		return _cache[race]
	var plan: Dictionary = DB.bodies.get(String(rd.get("body", "quadruped")), {})
	var rows := []
	var shake: Array = []
	for a in rd.get("attacks", []):
		var need := String(a.get("needs", ""))
		var pids := []
		if need != "":
			for p in plan.get("parts", []):
				if String(p["id"]).begins_with(need):
					pids.append(p["id"])
		var c: Dictionary = a.duplicate(true)
		c["creature"] = true
		rows.append([c, pids])
		if a.get("latch", false) and shake.is_empty():
			var s: Dictionary = c.duplicate(true)
			s["verb"] = "shake"
			s["shake"] = true
			s["prep"] = float(a.get("prep", 3)) * SHAKE_PREP_MULT
			shake = [s, pids]
	var all: Array = rd.get("attacks", [])
	var fb: Dictionary = (all[0] if not all.is_empty() else Formulas.NATURAL["bite"]).duplicate(true)
	fb["creature"] = true
	fb["charge"] = false
	fb["latch"] = false
	fb["p"] = float(fb.get("p", 3.0)) * 0.3
	fb["v"] = float(fb.get("v", 6.0))
	var tb := {"rows": rows, "shake": shake, "fallback": [fb]}
	_cache[race] = tb
	return tb

static func _have(f: Fighter, pids: Array) -> bool:
	if pids.is_empty():
		return true
	for pid in pids:
		if not f.lost.has(pid):
			return true
	return false

## The creature's usable attacks against t. Latched onto t: only the held bite ("shake").
static func attacks_for(sim, f: Fighter, t: Fighter) -> Array:
	if f.dragon:
		var usable: Array = []
		for row: Array in f.dragon_attacks:
			if str(row[0].get("verb", "")) == "claw" and f.prone: continue
			var ok: bool = false
			for pid: String in row[1]:
				# Use the already native-computed function loss thresholds; no new
				# injury calculation and no fallback bite from a missing head.
				var part: String = pid
				var intact: bool = true
				for _depth: int in 16:
					if part == "": break
					var status: Array = f.pstat.get(part, [])
					if f.lost.has(part) or (not status.is_empty() and bool(status[2])):
						intact = false; break
					part = str(f.unit.body.part_def(part).get("parent", ""))
				if intact:
					# Teeth/claws use this same native loss/function cache. With no
					# surviving tips there is no authored gem-edged strike to deliver.
					for tip: String in row[2].get(pid, []):
						var tip_status: Array = f.pstat.get(tip, [])
						if not f.lost.has(tip) and (tip_status.is_empty() or not bool(tip_status[2])):
							ok = true; break
				if ok: break
			if ok: usable.append(row[0])
		return usable
	var tb: Dictionary = _cache[f.unit.race] if _cache.has(f.unit.race) else _table(f.unit.race, f.unit.race_def())   # perf: no race lookup once cached
	if t != null and f.grabbing == t.idx and not (tb["shake"] as Array).is_empty() and _have(f, tb["shake"][1]):
		return [tb["shake"][0]]
	var out := []
	for row in tb["rows"]:
		var a: Dictionary = row[0]
		if not _have(f, row[1]):
			continue
		if a.get("charge", false) and not charge_ready(sim, f):
			continue
		out.append(a)
	if out.is_empty():
		return tb["fallback"]   # maimed past every natural weapon: a feeble bite with what is left
	return out

## Swing solution for a creature attack (same keys as Formulas.natural_swing).
static func swing(f: Fighter, atk: Dictionary, strength: float, ex_ratio: float) -> Dictionary:
	var u := f.unit
	var m := u.mass()
	if atk.get("charge", false):
		var v := run_speed(f)
		var p := charge_momentum(m, v)
		return {"natural": true, "verb": atk.get("verb", "charge"), "base_p": p, "ratio": 1.0, "gear": 0.0, "p": p, "v": v,
			"E": 0.5 * p * v, "prep_ticks": float(atk.get("prep", 2)) * 1.5, "thrust": false, "capped": false, "charge": true, "mass": m}
	var skill := float(u.skill("brawler"))
	var tau_ratio := (strength / 1000.0) * pow(m / 70.0, 2.0 / 3.0) * (1.0 + skill / Formulas.SKILL_TORQUE_DIV) \
		* (1.0 - Formulas.FATIGUE_TORQUE_K * clampf(ex_ratio, 0.0, 1.0)) * (1.0 - minf(0.5, u.body.pain / Formulas.PAIN_TORQUE_DIV))
	var ratio := sqrt(maxf(0.01, tau_ratio * m / 70.0))
	var v2 := float(atk.get("v", 8.0))
	var p2 := float(atk.get("p", 5.0)) * ratio
	return {"natural": true, "verb": atk.get("verb", "bite"), "base_p": atk.get("p", 5.0), "ratio": ratio, "gear": 0.0, "p": p2,
		"v": v2, "E": 0.5 * p2 * v2, "prep_ticks": float(atk.get("prep", 3)) * 1.5, "thrust": false, "capped": false}

## After a delivered creature attack: a charge spends the run-up; a latching bite that got through the coat
## rolls the grab contest (the wrestling code) and holds on.
static func after_strike(sim, f: Fighter, t: Fighter, atk: Dictionary) -> void:
	if atk.get("charge", false):
		f.last_move_tick = -1000
		return
	if not atk.get("latch", false) or atk.get("shake", false) or t == null or not t.present() or f.grabbing >= 0:
		return
	var ls: Dictionary = sim.last_strike
	if not ls.get("landed", false) or int(ls.get("defender", -1)) != t.idx:
		return
	var through := false
	for tl in ls.get("tissue", []):
		if not String(tl.get("tissue", "")) in ["fur", "thick_hide", "scale", "hide"]:
			through = true
	if not through:
		return
	var rr := Formulas.roll_grab(sim.rng, sim._grab_chance(f, t))
	if rr["ok"]:
		f.grabbing = t.idx
		t.grabbed_by = f.idx
		t.last_attacked_tick = sim.tick
		sim._ev_simple("hit", f.idx, t.idx, "latch_ok", {"roll": rr, "part": ls.get("part", "")})

## Creature decisions before the ordinary attack/move choice. Returns true if an action was started.
static func decide(sim, f: Fighter) -> bool:
	if f.grabbing < 0:
		return false
	var t: Fighter = sim.fighters[f.grabbing]
	if not t.present() or sim._dist(f.cell, t.cell) > 1:
		sim._release_grab(f)
		return false
	f.target = t.idx
	if not t.prone and not f.prone:
		sim._begin_special(f, "drag", DRAG_TICKS, {"t": t.idx})
		return true
	return false   # victim down: shake (the held bite) through the normal attack path

## Pack drag: the latched creature (and every packmate holding the same victim) pulls against the victim:
## the takedown contest (Formulas.grab_chance) with the holders' summed mass.
static func drag_chance(sim, f: Fighter, t: Fighter) -> float:
	var mass: float = sim._contest_mass(f)
	for o in sim._targets[f.side]:
		if o != f and o.grabbing == t.idx and o.present():
			mass += sim._contest_mass(o)
	return Formulas.grab_chance(sim._eff(f, "wrestler", "grab"), sim._eff(t, "wrestler", "grab"), mass, sim._contest_mass(t))

static func drag(sim, f: Fighter, ti: int) -> void:
	var t: Fighter = sim.fighters[ti] if ti >= 0 else null
	if t == null or not t.present() or f.grabbing != ti or t.prone:
		return
	var rr := Formulas.roll_grab(sim.rng, drag_chance(sim, f, t))
	sim._learn(f, "wrestler", Learning.XP_SWING)
	t.unit.body.exertion += Formulas.exertion_defend(t.unit.attr("END"), t.breath_bad)
	if rr["ok"]:
		sim._ev_simple("hit", f.idx, t.idx, "drag_ok", {"roll": rr})
		sim._fall(t, "dragged", Formulas.KNOCKDOWN_TICKS)
	else:
		sim._ev_simple("miss", f.idx, t.idx, "drag_fail", {"roll": rr})
