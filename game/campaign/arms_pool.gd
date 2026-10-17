class_name ArmsPool
extends RefCounted
## A house's arms pools: what its common soldiers have between them. Commoners never rise in rank, but the house's
## rank and file improve or degrade automatically with three pools (0-100 each), applied to every commoner it fields:
##   skill        - weapon skill level. Grows with drill: every day the army stays mustered.
##   experience   - battle-hardening (veteran status). Grows with every round fought, more for a win.
##   conditioning - strength, toughness and endurance. Grows with every day on campaign.
## The death of commoners drains all three, in proportion to how skilled the dead were.
## world["arms_pool"][key] = {"skill": f, "experience": f, "conditioning": f}; key "player" or a faction id.
const MAX := 100.0
const KINDS := ["skill", "experience", "conditioning"]
const DRILL_PER_DAY := 0.08
const MARCH_PER_DAY := 0.05
const PER_ROUND := 0.6
const PER_WIN := 1.5
const PER_DEAD_GRADE := 0.04   # pool lost per weapon grade (0-10) of each commoner who dies
const BODY := ["STR", "TOU", "END"]

static func key_for_units(game, units: Array) -> String:
	for u in units:
		if u is Unit and u.faction != "":
			return "player" if u.faction == "player" else u.faction
	return ""

static func pools(game, key: String) -> Dictionary:
	var all: Dictionary = game.world.get("arms_pool", {})
	var p = all.get(key, {})
	if p is float or p is int: p = {"skill": float(p), "experience": float(p), "conditioning": 0.0}   # older form
	return p

static func value(game, key: String, kind: String = "skill") -> float:
	return float(pools(game, key).get(kind, 0.0))

static func _add(game, key: String, kind: String, amount: float) -> void:
	if key == "": return
	if not game.world.has("arms_pool"): game.world["arms_pool"] = {}
	var p := pools(game, key)
	p[kind] = clampf(float(p.get(kind, 0.0)) + amount, 0.0, MAX)
	game.world["arms_pool"][key] = p

static func level(game, key: String, kind: String = "skill") -> int:
	return int(floor(value(game, key, kind) / MAX * 8.0))

static func level_word(game, key: String, kind: String = "skill") -> String:
	return UiWords.skill_level(level(game, key, kind))

## One line for the house screen.
static func summary(game, key: String) -> String:
	return "skill %d · experience %d · conditioning %d" % [int(value(game, key, "skill")), int(value(game, key, "experience")), int(value(game, key, "conditioning"))]

## Commoners under this house take the pools' levels (never below what they were raised with), so as the pools
## rise or fall the rank and file improve or degrade with them.
static func apply(game, units: Array) -> void:
	var key := key_for_units(game, units)
	var sk_lv := level(game, key, "skill")
	var xp_lv := level(game, key, "experience")
	var body := int(floor(value(game, key, "conditioning") / MAX * 6.0))   # up to +6 to each body attribute
	for u in units:
		if not u is Unit or u.dead or DragonCombat.is_dragon_unit(game, u) or Army.house_born(u): continue
		var wpn = u.weapon() if u.has_method("weapon") else null
		var sk := String(wpn.tmpl().get("skill", "")) if wpn != null else ""
		if sk != "":
			if not u.has_meta("arms_base"): u.set_meta("arms_base", u.skill(sk))
			u.skills[sk] = maxi(int(u.get_meta("arms_base")), sk_lv)
		if not u.has_meta("arms_battles"): u.set_meta("arms_battles", u.battles)
		u.battles = maxi(int(u.get_meta("arms_battles")), xp_lv)
		if u.rank == 0 and u.battles >= 1: u.rank = 1   # blooded / veteran status rank, never an officer rank
		if not u.has_meta("arms_body"):
			var base := {}
			for a in BODY: base[a] = int(u.attrs.get(a, 0))
			u.set_meta("arms_body", base)
		var b: Dictionary = u.get_meta("arms_body")
		for a in BODY:
			if u.attrs.has(a): u.attrs[a] = int(b[a]) + body

## After a round or clash: the side learns; skilled commoners who died take their worth out of every pool.
static func after_fight(game, key: String, fought: int, won: bool, dead_commoners: Array) -> void:
	if key == "": return
	var gain := PER_ROUND * minf(1.0, float(fought) / 100.0) + (PER_WIN if won else 0.0)
	var loss := 0.0
	for u in dead_commoners:
		if u is Unit: loss += PER_DEAD_GRADE * float(Army.skill_grade(u))
	_add(game, key, "experience", gain - loss)
	_add(game, key, "skill", gain * 0.25 - loss)
	_add(game, key, "conditioning", -loss)

## Off-screen clash: counts only (the dead are average men of that pool).
static func after_clash(game, key: String, fought: int, won: bool, dead: int) -> void:
	if key == "": return
	var grade := float(level(game, key, "skill")) * 10.0 / 15.0
	var loss := PER_DEAD_GRADE * grade * float(dead)
	var gain := PER_ROUND * minf(1.0, float(fought) / 100.0) + (PER_WIN if won else 0.0)
	_add(game, key, "experience", gain - loss)
	_add(game, key, "skill", gain * 0.25 - loss)
	_add(game, key, "conditioning", -loss)

## A day passing with an army in the field: drill (skill) and campaigning (conditioning). marching: it moved today.
static func day(game, key: String, marching: bool) -> void:
	_add(game, key, "skill", DRILL_PER_DAY)
	if marching: _add(game, key, "conditioning", MARCH_PER_DAY)
