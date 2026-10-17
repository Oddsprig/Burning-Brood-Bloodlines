extends RefCounted
## Shared helpers for tests/test_sim_*.gd (not a test itself: the runner only picks up test_*.gd).

## A unit of `race` with race-baseline attributes, the given skills and gear [[template, material, quality], ...].
static func make(race: String, gear: Array, skills: Dictionary = {}, name: String = "") -> Unit:
	var u := Unit.create(race, "test")
	u.name = name if name != "" else "%s %d" % [race.capitalize(), u.uid]
	u.title = "warrior"
	for s in skills:
		u.skills[s] = int(skills[s])
	for g in gear:
		var it := Item.make(String(g[0]), String(g[1]) if g.size() > 1 else "", int(g[2]) if g.size() > 2 else 0)
		u.equip[it.slot()] = it
	return u

static func soldier(mat: String, weapon: String = "arming_sword", body: String = "mail_shirt", helm: String = "nasal_helm",
		shield: String = "kite_shield", skill_lvl: int = 4) -> Unit:
	var g := [[weapon, mat], ["tunic", "linen"], ["trousers", "linen"], ["shoes", "leather"]]
	if body != "":
		g.append([body, mat])
	if helm != "":
		g.append([helm, mat])
	if shield != "":
		g.append([shield, mat])
	var wskill: String = DB.weapons[weapon].get("skill", "sword")
	return make("human", g, {wskill: skill_lvl, "fighter": 3, "shield_user": 3, "armor_user": 3, "dodger": 2})

# ---------------------------------------------------------------- harness kits and units (survey item 5)
## "Good copper" kit: copper helm + copper mail over a gambeson + round shield + copper arming sword.
static func good_copper(q: int = 0, armored: bool = true, weapon: String = "arming_sword", shield: bool = true) -> Array:
	var g := [[weapon, "copper", q], ["trousers", "linen"], ["shoes", "leather"]]
	if shield:
		g.append(["round_shield", "copper", q])
	if armored:
		g.append_array([["nasal_helm", "copper", q], ["mail_shirt", "copper", q], ["gambeson", "linen"]])
	else:
		g.append(["tunic", "linen"])
	return g

## R = median recruit (race median attributes, novice skills).
static func recruit(kit: Array = []) -> Unit:
	var u := make("human", kit if not kit.is_empty() else good_copper(),
		{"sword": 1, "spear": 1, "shield_user": 1, "armor_user": 1, "dodger": 1, "fighter": 1}, "")
	u.name = "Recruit %d" % u.uid
	return u

## V = veteran at 25 / 50 / 100 battles: skill 4 / 6 / 11, attribute gap to the ceiling closed 47 / 72 / 92%.
const VET := {25: [4, 0.47], 50: [6, 0.72], 100: [11, 0.92]}

static func veteran(battles: int, kit: Array = []) -> Unit:
	var v: Array = VET[battles]
	var s: int = v[0]
	var u := make("human", kit if not kit.is_empty() else good_copper(),
		{"sword": s, "spear": s, "shield_user": s, "armor_user": s, "dodger": maxi(0, s - 1), "fighter": s,
		"discipline": s / 2, "observer": s / 2, "brawler": s / 2, "wrestler": s / 2}, "")
	u.name = "Veteran %d" % u.uid
	for a in DB.ATTRS:
		var base := int(u.attr_base.get(a, u.attrs[a]))
		var cap := int(u.attr_cap.get(a, DB.attr_ceiling(base)))
		u.attrs[a] = int(round(base + float(v[1]) * (cap - base)))
	return u

## Runs a battle to the end; returns the sim.
static func run(a: Array, b: Array, seed: int, opts: Dictionary = {}) -> BattleSim:
	var sim := BattleSim.new()
	var o := {"w": 16, "h": 8, "log_moves": false}
	for k in opts:
		o[k] = opts[k]
	sim.setup(a, b, seed, o)
	while not sim.is_over():
		sim.step()
	return sim

static func count(sim: BattleSim, type: String) -> int:
	var n := 0
	for e in sim.events:
		if e["type"] == type:
			n += 1
	return n

## Number of strike resolutions (attack events).
static func exchanges(sim: BattleSim) -> int:
	return count(sim, "attack")

static func kills_by(sim: BattleSim, idx: int) -> int:
	return (sim.fighters[idx] as Fighter).kills

## Enemies dead or unconscious at the end whose last attacker was fighter idx (kills + knockouts).
static func downed_by(sim: BattleSim, idx: int) -> int:
	var n := 0
	var me: Fighter = sim.fighters[idx]
	for f in sim.fighters:
		if f.side != me.side and (f.state == "dead" or f.state == "unconscious") and f.last_attacker == idx:
			n += 1
	return n

## Prints and returns a band check. gate=false -> "TRACKED (not gating)".
static func band(name: String, value: float, lo: float, hi: float, gate: bool, fmt: String = "%.1f") -> int:
	var ok := value >= lo and value <= hi
	print("  %-58s %s  band [%s, %s]  %s" % [name, fmt % value, fmt % lo, fmt % hi,
		("PASS" if ok else "FAIL") if gate else ("ok (tracked)" if ok else "MISS - TRACKED (not gating)")])
	return 0 if ok or not gate else 1
