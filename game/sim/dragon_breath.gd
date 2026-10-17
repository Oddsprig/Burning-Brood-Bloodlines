class_name DragonBreath
extends RefCounted
## Dragon breath: a cone attack an adult dragon uses a few times per battle. Each gem line breathes one element:
##   fire  - burns skin, fat and muscle; heavy pain; wood/leather/cloth armour gives little protection
##   frost - frostbite on outer layers; numbed, slowed victims (tempo), metal armour conducts the cold
##   venom - caustic spray that eats armour and opens bleeding sores
##   storm - lightning: deep burns, knockdown, metal armour draws the bolt
## Damage goes into the same BodyState layers as every other wound (pain, bleeding, death checks), so healing,
## logs, aftermath and saves treat breath injuries like any other. Allies in the cone are burned too, so a
## dragon holds its breath while its own side would take more of the blast than the enemy.
const ELEMENT := {
	"ruby": "fire", "garnet": "fire", "topaz": "fire", "citrine": "fire", "black_diamond": "fire", "onyx": "fire",
	"sapphire": "frost", "aquamarine": "frost", "diamond": "frost", "moonstone": "frost", "pearl": "frost",
	"emerald": "venom", "jade": "venom", "tourmaline": "venom",
	"amethyst": "storm", "opal": "storm",
}
const RANGE := 6                # tiles
const COOLDOWN := 90            # ticks between breaths (4.5 s at 1x)
const WINDUP := 14              # ticks of drawing breath (the visible inhale)
const MAX_TARGETS := 9
const OUTER := ["head", "neck", "torso_upper", "torso_lower", "arm_upper_l", "arm_upper_r", "arm_lower_l", "arm_lower_r",
	"hand_l", "hand_r", "leg_upper_l", "leg_upper_r", "leg_lower_l", "leg_lower_r", "foot_l", "foot_r"]
const WOUND_WORD := {"fire": "burned", "frost": "frostbitten", "venom": "corroded", "storm": "burned"}

static func element_of(f: Fighter) -> String:
	var src: Array = f.dragon_profile.get("source", [])
	var gem := str(src[2]) if src.size() > 2 else "ruby"
	return ELEMENT.get(gem, "fire")

## Charges per battle from the dragon's growth: juveniles cannot breathe; a grown adult breathes 3-5 times.
static func charges_of(f: Fighter) -> int:
	var linear := float(f.dragon_profile.get("linear_scale", 1.0))
	if linear < 0.55: return 0
	return clampi(2 + int(round(linear * 2.0)), 2, 5)

## Cells of the cone in front of the dragon. Returns [enemies, allies] fighters in it, nearest first.
static func cone(sim, f: Fighter) -> Array:
	var foes: Array = []
	var friends: Array = []
	for o: Fighter in sim.fighters:
		if o == f or o.waiting or not o.alive() or o.state == "fled": continue
		var dx: int = (o.cell.x - f.cell.x) * f.facing
		if dx < 1 or dx > RANGE: continue
		if absi(o.cell.y - f.cell.y) > 1 + dx / 2: continue
		if o.side == f.side: friends.append(o)
		else: foes.append(o)
	var by_dist := func(a: Fighter, b: Fighter) -> bool: return sim._d2(a.cell, f.cell) < sim._d2(b.cell, f.cell)
	foes.sort_custom(by_dist); friends.sort_custom(by_dist)
	return [foes, friends]

## Called from BattleSim._decide for dragons. Starts the breath wind-up when worthwhile; true = action taken.
static func _no(sim, why: String) -> bool:
	sim.breath_debug[why] = int(sim.breath_debug.get(why, 0)) + 1
	return false

static func try(sim, f: Fighter) -> bool:
	if not f.dragon or f.routed or f.prone: return _no(sim, "r1")
	var st: Dictionary = sim.breath_state.get(f.idx, {})
	if st.is_empty():
		st = {"left": charges_of(f), "next": 20 + (f.idx * 7) % 30, "element": element_of(f)}
		sim.breath_state[f.idx] = st
	if int(st["left"]) <= 0 or sim.tick < int(st["next"]): return _no(sim, "r2")
	if f.lost.has("head") or f.lost.has("neck") or f.lost.has("jaw") or f.suffocating or f.breath_bad: return _no(sim, "r3")
	if f.unit.body.blood < f.unit.body.blood_max * 0.55: return _no(sim, "r4")
	# Face the thickest nearby enemy group before judging the cone.
	var left := 0
	var right := 0
	for o: Fighter in sim._targets[1 - f.side]:
		if o.alive() and absi(o.cell.y - f.cell.y) <= RANGE and absi(o.cell.x - f.cell.x) <= RANGE:
			if o.cell.x >= f.cell.x: right += 1
			else: left += 1
	if left + right == 0: return _no(sim, "r5")
	f.facing = 1 if right >= left else -1
	var c: Array = cone(sim, f)
	var foes: int = mini(c[0].size(), MAX_TARGETS)
	var friends: int = c[1].size()
	if foes < 2 and not (foes >= 1 and sim.side_total[f.side] < sim.side_total[1 - f.side]): return _no(sim, "r6")
	if friends > foes: return _no(sim, "r7")
	sim.breath_debug["tries"] = int(sim.breath_debug.get("tries", 0)) + 1
	st["next"] = sim.tick + COOLDOWN
	sim._begin_special(f, "dragon_breath", WINDUP, {"element": st["element"]})
	sim._ev_simple("breath_draw", f.idx, -1, "dbreath_draw_" + str(st["element"]), {})
	return true

## The wind-up finished: breathe into the cone as it is NOW (targets may have moved).
static func release(sim, f: Fighter, data: Dictionary) -> void:
	var st: Dictionary = sim.breath_state.get(f.idx, {})
	if st.is_empty() or int(st["left"]) <= 0: return
	st["left"] = int(st["left"]) - 1
	var element := str(data.get("element", "fire"))
	var c: Array = cone(sim, f)
	var hit: Array = []
	for o: Fighter in c[0]:
		if hit.size() >= MAX_TARGETS: break
		hit.append(o)
	var allies: Array = []
	for o: Fighter in c[1]:
		if allies.size() >= 3: break
		allies.append(o)   # friendly fire: the nearest allies in the cone are caught at reduced strength
	var power := float(f.dragon_profile.get("linear_scale", 1.0)) * clampf(f.unit.body.blood / f.unit.body.blood_max, 0.5, 1.0)
	var cells: Array = []
	for dx in range(1, RANGE + 1):
		cells.append(Vector2i(f.cell.x + dx * f.facing, f.cell.y))
	var e: Dictionary = sim._ev_simple("breath", f.idx, -1, "dbreath_" + element, {"n": str(hit.size())}, true)
	e["element"] = element
	e["origin"] = f.cell
	e["facing"] = f.facing
	e["range"] = RANGE
	for o: Fighter in hit:
		var dist := maxi(1, sim._dist(o.cell, f.cell))
		_burn(sim, f, o, element, power * (1.15 - 0.12 * dist), e)
	for o: Fighter in allies:
		_burn(sim, f, o, element, power * 0.35, e)
	# Dragon fear: every enemy that saw the blast loses heart.
	for o: Fighter in sim._targets[1 - f.side]:
		if o.alive() and not o.routed and sim._dist(o.cell, f.cell) <= RANGE + 3:
			sim._shock(o, 6.0 * power, "dragonfear", false)

static func _armour_factor(o: Fighter, pid: String, element: String) -> float:
	var worn: Array = o.armor_for.get(pid, [])
	if worn.is_empty(): return 1.0
	var keep := 1.0
	for item: Dictionary in worn:
		var mat: Dictionary = item["mat"]
		var metal := float(mat.get("density", 1.0)) > 4.0 or bool(mat.get("metal", false))
		var cov := float(item["cov"]) / 100.0 if float(item["cov"]) > 1.0 else float(item["cov"])
		var block := 0.0
		match element:
			"fire": block = 0.55 if metal else 0.25
			"frost": block = 0.15 if metal else 0.45
			"venom": block = 0.5 if metal else 0.3
			"storm": block = -0.25 if metal else 0.2
		keep *= 1.0 - block * clampf(cov, 0.0, 1.0)
	return clampf(keep, 0.1, 1.4)

static func _burn(sim, a: Fighter, o: Fighter, element: String, power: float, ev: Dictionary) -> void:
	if power <= 0.05 or not o.alive(): return
	var body: BodyState = o.unit.body
	var size_k := clampf(pow(70.0 / maxf(10.0, o.unit.mass()), 0.33), 0.25, 1.6)   # big bodies soak more
	var rng: RandomNumberGenerator = sim.rng
	var n_parts := 2 + rng.randi_range(0, 2)
	var pain := 0.0
	var worst := 0.0
	var worst_pid := ""
	var plan_parts: Dictionary = body.defs()
	for i in n_parts:
		var pid: String = OUTER[rng.randi_range(0, OUTER.size() - 1)]
		if not plan_parts.has(pid) or body.is_lost(pid): continue
		var heat := power * size_k * _armour_factor(o, pid, element) * rng.randf_range(0.55, 1.0)
		var part: Dictionary = body.wound_part(pid)
		var depth := heat
		for L: Dictionary in part["layers"]:
			if depth <= 0.03: break
			if L["tissue"] in ["bone", "organ", "brain"]: break
			var add := minf(1.0 - float(L["dmg"]), depth)
			if add > 0.0:
				L["dmg"] = float(L["dmg"]) + add
				L["kind"] = "destroyed" if float(L["dmg"]) >= 1.0 else WOUND_WORD[element]
				L["heal_days"] = maxf(float(L.get("heal_days", 0.0)), 4.0 + 18.0 * float(L["dmg"]))
				if element == "venom" and L["tissue"] in ["skin", "muscle"]:
					sim._add_bleed(o, pid, L, 0.04 * add, Formulas.CLOT_MINOR)
			depth *= 0.45
		pain += heat * (48.0 if element in ["fire", "storm"] else 30.0)
		if heat > worst:
			worst = heat; worst_pid = pid
		if element == "venom":
			for item: Dictionary in o.armor_for.get(pid, []):
				var it: Item = item.get("item")
				if it != null and not it.broken and rng.randf() < 0.25 * power:
					it.broken = true
	if worst_pid == "": return
	body.pain += pain
	o.pain_floor_src += pain * 0.5
	o.last_attacker = a.idx
	o.last_attacked_tick = sim.tick
	sim._ev_simple("breath_hit", a.idx, o.idx, "dbreath_hit_" + element, {"part": sim._pdef(body, worst_pid).get("name", worst_pid)}, false, worst_pid)
	if element == "frost":
		o.tempo = minf(o.tempo * 1.35, 3.0)
		o.tempo_tick = sim.tick + 40
	sim._update_functions(o, true, worst_pid)
	if not o.alive(): return
	# Grievous whole-body burns kill outright; small creatures die faster.
	if worst * (1.0 + float(n_parts) * 0.15) > 1.55 and worst_pid in ["head", "neck", "torso_upper"]:
		sim._kill(o, a.idx, "burned to death" if element != "frost" else "froze to death")
		return
	sim._shock(o, pain / Formulas.SHOCK_WOUND_DIV + 5.0, "breath", pain >= Formulas.PAIN_STUN)
	if o.state != "unconscious" and o.alive():
		if body.pain > Formulas.PAIN_KO:
			sim._knock_out(o, "pain")
		elif element == "storm" and not o.prone:
			sim._fall(o, "knocked", Formulas.KNOCKDOWN_TICKS)
