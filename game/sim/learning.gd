class_name Learning
extends RefCounted
## DF-style learning by doing. Deterministic (no rolls).
## Skills: XP to reach level n = 400 + 100*n (src: survey [DF]; i.e. 500 + 100*L from level L to L+1, df_wiki).
##   XP per event (src: survey [OURS]): swing 2, hit +2, dodge/block/parry 3, armor hit 2; scaled by the race's
##   "learn" % and per-skill "skill_learn" %. Target: Novice in ~5 fights, Competent in 15-20.
## Attributes (src: survey [OURS]): the battle records how much each attribute was used; at the end
##   apply_battle_growth closes ~2.7% of the gap to the unit's own ceiling (Unit.attr_cap) per battle, scaled by
##   use (a busy front-liner closes about half the gap in 25 battles) and by race (attr_cost: human 400 -> x1.25,
##   troll 700 -> x0.71). Never past Unit.attr_cap, never past DB.ATTR_HARD_CAP.

const XP_BASE := 400.0              # src: survey [DF]
const XP_PER_LEVEL := 100.0         # src: survey [DF]
const MAX_LEVEL := 20               # src: df_wiki

const XP_SWING := 2.0               # src: survey [OURS]
const XP_HIT := 2.0                 # src: survey [OURS]
const XP_DEFEND := 3.0              # src: survey [OURS] dodge/block/parry success
const XP_DEFEND_TRY := 1.0          # tuned: attempted defence
const XP_ARMOR_HIT := 2.0           # src: survey [OURS]
const XP_FIGHTER := 1.0             # tuned: fighter per combat action
const XP_DISCIPLINE := 3.0          # tuned: per morale check survived

const ATTR_GAP_PER_BATTLE := 0.027  # src: survey [OURS]
const ATTR_COST_REF := 500.0        # tuned: race attr_cost 500 = x1.0
const ATTR_USE_FULL := 40.0         # tuned: weighted uses in one battle that count as "fully used"
## Which attributes an action exercises (src: survey [DF] skill-attribute weights; A 1.0, B 0.5, C 0.25).
const ATTR_LINKS := {
	"weapon": {"STR": 1.0, "KIN": 1.0, "AGI": 0.5, "WIL": 0.5, "TOU": 0.25},
	"wrestler": {"STR": 1.0, "KIN": 1.0, "AGI": 0.5, "WIL": 0.5, "TOU": 0.25},
	"dodger": {"AGI": 1.0, "KIN": 1.0, "TOU": 0.5, "END": 0.25},
	"shield_user": {"STR": 1.0, "KIN": 1.0, "AGI": 0.5, "WIL": 0.5},
	"armor_user": {"STR": 1.0, "KIN": 1.0, "TOU": 0.5, "WIL": 0.5, "END": 0.25},
	"fighter": {"AGI": 1.0, "KIN": 1.0, "STR": 0.5},
	"discipline": {"WIL": 1.0, "FOC": 0.5},
	"march": {"END": 0.5, "STR": 0.15},
	"pain": {"WIL": 0.5, "TOU": 0.5},
	"bow": {"AGI": 1.0, "SPA": 1.0, "KIN": 0.5, "WIL": 0.25},   # bows: DF Bowman attributes (shooting trains them)
	"draw": {"STR": 0.5, "END": 0.25},                       # bows: drawing a heavy bow builds the arms
}

const _HARD_CAP: int = preload("res://core/db.gd").ATTR_HARD_CAP   # perf: DB.ATTR_HARD_CAP without the autoload lookup

static func xp_to_reach(level: int) -> float:
	return XP_BASE + XP_PER_LEVEL * level

static func xp_to_next(level: int) -> float:
	return xp_to_reach(level + 1)

static func learn_mult(u: Unit, skill: String) -> float:
	var r := u.race_def()
	var m := float(r.get("learn", 100)) / 100.0
	var sl: Dictionary = r.get("skill_learn", {})
	return m * float(sl.get(skill, 100)) / 100.0

## Adds skill XP (race learn rate applied); returns the new level if it rose, else -1.
static func add_skill_xp(u: Unit, skill: String, xp: float) -> int:
	return add_skill_xp_mult(u, skill, xp, learn_mult(u, skill))

## add_skill_xp with the learn multiplier already known (BattleSim caches it per fighter and skill).
static func add_skill_xp_mult(u: Unit, skill: String, xp: float, mult: float) -> int:
	var skills := u.skills
	var lvl := int(skills.get(skill, 0))
	if lvl >= MAX_LEVEL:
		return -1
	var sxp := u.skill_xp
	var cur: float = float(sxp.get(skill, 0.0)) + xp * mult
	var rose := -1
	while lvl < MAX_LEVEL and cur >= XP_BASE + XP_PER_LEVEL * (lvl + 1):   # = xp_to_next(lvl), inlined (perf)
		cur -= XP_BASE + XP_PER_LEVEL * (lvl + 1)
		lvl += 1
		rose = lvl
	skills[skill] = lvl
	sxp[skill] = cur if lvl < MAX_LEVEL else 0.0
	return rose

## Records attribute use for this battle (use: Dictionary attr -> float, owned by the Fighter).
static func note_use(use: Dictionary, link: String, mult: float = 1.0) -> void:
	if not ATTR_LINKS.has(link):   # (no empty default dictionary built per call)
		return
	var w: Dictionary = ATTR_LINKS[link]
	for a in w:
		use[a] = float(use.get(a, 0.0)) + float(w[a]) * mult

static func attr_ceiling(u: Unit, a: String) -> int:
	var cap := DB.ATTR_HARD_CAP
	if u.attr_cap.has(a):
		cap = int(u.attr_cap[a])
	else:
		var base := int(u.attr_base.get(a, u.attrs.get(a, 1000)))
		cap = DB.attr_ceiling(base)
	return mini(cap, DB.ATTR_HARD_CAP)

## End-of-battle attribute growth. Returns {attr: points gained}.
static func apply_growth(u: Unit, use: Dictionary, rd: Dictionary = {}) -> Dictionary:
	var gained := {}
	if u.dead:
		return gained
	var race_mult := ATTR_COST_REF / maxf(100.0, float((rd if not rd.is_empty() else u.race_def()).get("attr_cost", ATTR_COST_REF)))   # rd: the race def when the caller has it
	# perf (same results): the unit's dictionaries hoisted; attr_ceiling's stored-cap path inlined
	var attrs := u.attrs
	var caps := u.attr_cap
	var xp := u.attr_xp
	for a in use:
		var used := clampf(float(use[a]) / ATTR_USE_FULL, 0.0, 1.0)
		if used <= 0.0:
			continue
		var cur := int(attrs.get(a, 1000))
		var c = caps.get(a)
		var cap := mini(int(c), _HARD_CAP) if c != null else attr_ceiling(u, a)
		if cur >= cap:
			continue
		# Fractional progress carries over in attr_xp so small gaps still close eventually.
		var gain: float = float(cap - cur) * ATTR_GAP_PER_BATTLE * used * race_mult + float(xp.get(a, 0.0))
		var pts := int(floor(gain))
		xp[a] = gain - pts
		if pts > 0:
			var nv := mini(cap, cur + pts)
			attrs[a] = nv
			gained[a] = nv - cur
	return gained
