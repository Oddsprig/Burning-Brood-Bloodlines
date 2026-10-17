class_name Formulas
extends RefCounted
## Every tunable constant and formula of the combat sim, in one place.
## Tags on constants:
##   # src: df_wiki   taken from (or shaped exactly like) a mechanic documented on dwarffortresswiki.org
##   # src: survey    from the DF combat-mechanics survey / Douglas spec threads ([DF] items are DF, [OURS] ours)
##   # tuned          our own number, tuned against the batch / harness tests (tests/test_sim_*.gd)
##
## RANDOMNESS RULE (survey): "roll the person, not the metal". Everything between the rolls is deterministic:
## momentum/energy, every layer penetration test, wound size, pain, bleeding, stagger, timing, exertion, XP.
## Randomness lives ONLY in the named roll_* functions at the bottom. Each returns {"n": name, "r", "p", "ok"};
## the calc log renders it as "[roll:dodge] 0.62 vs 0.41 -> fails" (see roll_text), so where the dice sit can be
## changed in one place.

const TICK_SECONDS := 0.05            # src: survey [OURS] 1 tick = 0.05 s

# =====================================================================================================
# Movement and tempo
# =====================================================================================================
const GAIT_TICKS_DIV := 65.0          # src: survey/integrator: DF gait (ticks per 100 tiles) / 65 = ticks per tile
const GAIT_INDEX_ADVANCE := 2         # tuned: soldiers close at a jog (races.gait = [sprint, run, jog])
const GAIT_INDEX_FLEE := 1            # tuned: routers run
const GAIT_DEFAULT := [225, 450, 675]  # src: df_wiki human gait (fallback)
const AGI_TEMPO_K := 0.25             # src: survey "AGI multiplies speed" (DF); size of effect tuned
const ENC_FREE_RATIO := 0.2           # tuned: gear up to 20% of carry capacity costs nothing
const ENC_TEMPO_K := 0.5              # tuned
const CARRY_CAPACITY_K := 0.35        # tuned: capacity kg = STR/1000 * body mass * 0.35
const ARMOR_USER_RELIEF := 0.05       # src: survey [DF] (Grand Master armor user moves 2x a dabbler in heavy armor); 5%/level tuned
const ARMOR_USER_RELIEF_MAX := 0.75   # tuned
const FATIGUE_TEMPO_K := 0.3          # tuned: fully exerted -> +30% action time
const WOUND_LEG_TEMPO_K := 0.6        # tuned: worst leg-muscle damage 1.0 -> +60%
const WOUND_PAIN_TEMPO_DIV := 400.0   # tuned: effective pain 100 -> +25%
const WOUND_BLOOD_TEMPO_K := 1.5      # tuned: 20% blood lost -> +30%
const PRONE_MOVE_MULT := 2.0          # src: survey [DF] prone or stunned halves speed
const ROUGH_MOVE_MULT := 2.0          # tuned: rough tiles
const TERRAIN_MOVE := {"plains": 1.0, "road": 0.9, "hills": 1.2, "forest": 1.3, "marsh": 1.5, "mud": 1.5, "snow": 1.4}  # tuned
const RECOVER_TICK_MULT := 1.5        # tuned: raw ATTACK_PREPARE_AND_RECOVER recover ticks x1.5 x tempo
const TEMPO_CACHE_TICKS := 10        # tuned (perf): tempo recomputed at most every 10 ticks unless invalidated
const MAX_ACTION_DELAY := 1.0         # an action can be pushed back by stagger/stun at most its own length (no stun-lock)
const STUN_TICKS := 10                # tuned
const KNOCKDOWN_TICKS := 30           # tuned: knocked down -> lies prone this long before standing
const LEG_LEN_GAIT_K := 1.0           # src: integrator (Unit.leg_len % -> gait)

static func carry_capacity(strength: float, body_mass: float) -> float:
	return maxf(5.0, strength / 1000.0 * body_mass * CARRY_CAPACITY_K)

static func effective_gear_mass(armor_mass: float, other_mass: float, armor_user: int) -> float:
	return armor_mass * (1.0 - minf(ARMOR_USER_RELIEF_MAX, armor_user * ARMOR_USER_RELIEF)) + other_mass

static func encumbrance_ratio(eff_mass: float, strength: float, body_mass: float) -> float:
	return eff_mass / carry_capacity(strength, body_mass)

## Tempo multiplier on action time (1.0 = unhindered average; higher = slower), with every factor for the logs.
## "speed" is reported DF-style as the effective gait value (ticks per 100 tiles).
static func tempo_breakdown(gait: float, agi: float, enc_ratio: float, leg_impair: float, pain_eff: float,
		blood_frac: float, ex_ratio: float) -> Dictionary:
	var agi_f := clampf(1.0 - AGI_TEMPO_K * (agi - 1000.0) / 1000.0, 0.6, 1.4)
	var enc_f := 1.0 + ENC_TEMPO_K * maxf(0.0, enc_ratio - ENC_FREE_RATIO)
	var wound_f := 1.0 + WOUND_LEG_TEMPO_K * leg_impair + pain_eff / WOUND_PAIN_TEMPO_DIV \
		+ WOUND_BLOOD_TEMPO_K * maxf(0.0, 1.0 - blood_frac)
	var fat_f := 1.0 + FATIGUE_TEMPO_K * clampf(ex_ratio, 0.0, 1.0)
	var tempo := agi_f * enc_f * wound_f * fat_f
	return {"tempo": tempo, "speed": gait * tempo, "gait": gait, "agi": agi_f, "enc": enc_f, "wound": wound_f, "fatigue": fat_f}

static func speed_text(b: Dictionary) -> String:
	if b.is_empty():
		return ""
	return "speed %d = gait %d x agi %.2f x enc %.2f x wounds %.2f x fatigue %.2f (tempo %.2f)" % [
		int(b["speed"]), int(b["gait"]), b["agi"], b["enc"], b["wound"], b["fatigue"], b["tempo"]]

static func move_ticks(speed: float, terrain_mult: float, prone: bool) -> float:
	return speed / GAIT_TICKS_DIV * terrain_mult * (PRONE_MOVE_MULT if prone else 1.0)

static func recover_ticks(raw: float, tempo: float) -> float:
	return raw * RECOVER_TICK_MULT * tempo

# =====================================================================================================
# Exertion (survey: from swings AND defences; recovers only while nobody is attacking the unit; END slows gain)
# =====================================================================================================
const EX_PER_JOULE := 0.05            # src: survey [OURS] exertion per swing = E/END (scale tuned)
const EX_MOVE := 1.0                  # tuned
const EX_MOVE_PER_KG := 0.1           # tuned
const EX_DEFEND := 4.0                # tuned: per defence attempt
const EX_RECOVER_PER_TICK := 0.5      # tuned
const EX_RECOVER_QUIET_TICKS := 20    # src: survey [OURS] recovers when nobody has attacked the unit for a while
const EX_BREATH_MULT := 2.0           # tuned: damaged lung/airway doubles exertion gain

static func exertion_swing(energy: float, endurance: float, breath_bad: bool) -> float:
	return energy * EX_PER_JOULE * 1000.0 / maxf(endurance, 100.0) * (EX_BREATH_MULT if breath_bad else 1.0)

static func exertion_move(eff_mass: float, endurance: float, breath_bad: bool) -> float:
	return (EX_MOVE + EX_MOVE_PER_KG * eff_mass) * 1000.0 / maxf(endurance, 100.0) * (EX_BREATH_MULT if breath_bad else 1.0)

static func exertion_defend(endurance: float, breath_bad: bool) -> float:
	return EX_DEFEND * 1000.0 / maxf(endurance, 100.0) * (EX_BREATH_MULT if breath_bad else 1.0)

# =====================================================================================================
# Effective levels (survey item 2): level + SUM g*(attr-1000)/250, g = 1 / 0.5 / 0.25 for DF A/B/C attributes,
# then x (1 - pain) x (1 - exertion). STR is never counted where swing physics already uses it.
# =====================================================================================================
const ATTR_DIV := 250.0               # src: survey [OURS]
const CHECK_ATTRS := {
	"hit": {"FOC": 1.0, "SPA": 1.0, "KIN": 0.5, "AGI": 0.25},          # to-hit: weapon skill, FOC, SPA (STR in physics)
	"dodge": {"AGI": 1.0, "KIN": 1.0, "TOU": 0.5, "END": 0.25},        # DF dodger
	"block": {"STR": 1.0, "KIN": 1.0, "AGI": 0.5, "WIL": 0.5},         # DF shield user
	"parry": {"SPA": 1.0, "KIN": 1.0, "AGI": 0.5},                     # weapon skill + SPA
	"grab": {"STR": 1.0, "AGI": 1.0, "KIN": 0.5},                      # wrestler
	"quality": {"FOC": 1.0},                                           # strike quality mean = skill + FOC
	"spot": {"SPA": 1.0, "INT": 0.5},                                  # observer
	"aim": {"AGI": 1.0, "SPA": 1.0, "KIN": 0.5, "WIL": 0.25},          # bows: DF Bowman (AGI + spatial A, KIN B, WIL C)
}
const FIGHTER_SHARE := 0.25           # tuned: fighter skill adds to every combat check
const PAIN_EFF_MAX := 0.8             # tuned: (1 - pain) where pain = min(0.8, pain/PAIN_KO)
const EXERT_EFF_K := 0.5              # tuned: (1 - 0.5 * min(1, exertion/END))
const BLOOD_EFF_K := 1.5              # tuned: x (1 - 1.5 * blood lost fraction)
const PRONE_SKILL_MULT := 0.5         # tuned
const BLIND_SKILL_PEN := 4.0          # tuned
const QUALITY_HIT_LEVELS := 2.5       # src: survey [DF] quality to-hit multiplier 1.0..2.0; as +2.5 levels per +1.0 (tuned)
const SHORT_BLADE_CLOSE_BONUS := 1.5  # src: survey O5 [OURS] short blades (reach < 60) bonus up close; tuned

static func attr_levels(check: String, attrs: Dictionary) -> float:
	var w: Dictionary = CHECK_ATTRS.get(check, {})
	var s := 0.0
	for a in w:
		s += float(w[a]) * (float(attrs.get(a, 1000)) - 1000.0) / ATTR_DIV
	return s

static func condition_mult(pain_eff: float, ex_ratio: float, blood_frac: float) -> float:
	return (1.0 - minf(PAIN_EFF_MAX, pain_eff / PAIN_KO)) * (1.0 - EXERT_EFF_K * clampf(ex_ratio, 0.0, 1.0)) \
		* maxf(0.1, 1.0 - BLOOD_EFF_K * maxf(0.0, 1.0 - blood_frac))

static func effective_level(level: float, attr_lv: float, fighter: float, cond: float) -> float:
	return maxf(0.0, (level + attr_lv + FIGHTER_SHARE * fighter) * cond)

# =====================================================================================================
# One defence per attack (survey item 1): block if in the shield arc, else parry, else dodge.
# Contest: P(attack gets through) = clamp(0.5 + 0.05*(att_eff - def_eff), .0001, .9999). Douglas (2026-10-04):
# floor 0.01% per swing, not 5%, because the game calculates so many swings; never exactly 0 or 1.
# Saturation: -5% to the defence per defence attempted in the last 20 ticks, cap -30%.
# =====================================================================================================
const CONTEST_SLOPE := 0.05           # src: survey [OURS]
const CONTEST_MIN := 0.0001           # Douglas: 0.01% floor (was 0.05)
const CONTEST_MAX := 0.9999           # Douglas: mirror of the floor (was 0.95)
const SATURATION_PER := 0.05          # src: survey [OURS]
const SATURATION_MAX := 0.30          # src: survey [OURS]
const SATURATION_WINDOW := 20         # src: survey [OURS] ticks
const DEF_BASE := {"block": 2.0, "parry": 0.0, "dodge": 0.0}  # tuned: level bonus of each defence kind
const DODGE_ENC_LEVELS := 6.0         # tuned: dodge -6 levels at encumbrance ratio 1.0 (armor user offsets it)
const PARRY_LEN_LEVELS := 2.0         # tuned: + per metre of parrying weapon over 0.8 m
const PARRY_P_LEVELS := 1.5           # tuned: - per 20 kg m/s of incoming momentum over 20
const RAGE_DEF_MULT := 0.7            # src: survey [OURS] rage: -30% dodge/parry
const HELD_VICTIM_DODGE := 0.5        # src: survey [OURS] lodged-weapon victim dodge -50%
const HELD_WIELDER_DODGE := 0.75      # src: survey [OURS] wielder with a stuck weapon dodge -25%
const SPOT_BASE_SIDE := 0.6           # tuned: chance to see a flank attack
const SPOT_BASE_REAR := 0.25          # tuned: chance to see a rear attack
const SPOT_PER_LEVEL := 0.04          # tuned: + per observer level (+ SPA)
const OBSERVER_ARC_LEVEL := 5         # tuned: observer >= 5 widens the shield arc to the flanks
const REAR_ATT_BONUS := 2.0           # tuned: attacks from flank/rear +2 levels; minus the target's observer

static func contest_through(att_eff: float, def_eff: float) -> float:
	return clampf(0.5 + CONTEST_SLOPE * (att_eff - def_eff), CONTEST_MIN, CONTEST_MAX)

static func saturation(recent_defences: int) -> float:
	return minf(SATURATION_MAX, SATURATION_PER * recent_defences)

static func spot_chance(rear: bool, observer: float, spot_lv: float) -> float:
	return clampf((SPOT_BASE_REAR if rear else SPOT_BASE_SIDE) + SPOT_PER_LEVEL * (observer + spot_lv), 0.05, 0.95)

# =====================================================================================================
# Swing physics: survey O1 inertia/torque model + per-weapon air drag (Douglas: both, drag always on)
#   I = m_arm*a^2/3 + m*(a+b)^2 + m*k^2;  tau = tau0*(STR/1000)*(mass/70)^(2/3)*grip*(1+skill/40)*(1-fatigue)*(1-pain)
#   E = tau*theta;  omega = sqrt(2E/I);  v = omega*(a+s) (capped by AGI/skill);  m_eff = I/(a+s)^2;  p = m_eff*v
#   prepare time = 2*theta/omega.  Thrusts (O4 minimal): v = sqrt(2E/(m+m_arm)), p = (m + 0.05*body)*v.
# =====================================================================================================
const TAU0 := 70.0                    # tuned: N*m, average human one-handed
const ARM_LEN := 0.65                 # src: survey [OURS] m, scales with (mass/70)^(1/3) and Unit.arm_len %
const ARM_MASS_FRAC := 0.05           # tuned: arm mass = 5% of body mass
const GRIP_1H := 1.0                  # src: survey [OURS]
const GRIP_2H := 1.6                  # src: survey [OURS]
const GRIP_2H_ONE_HAND := 0.6         # src: survey [OURS] two-hander swung with one working arm
const SKILL_TORQUE_DIV := 40.0        # src: survey [OURS] "skill: half to torque efficiency" (1 + skill/40)
const FATIGUE_TORQUE_K := 0.45        # src: handoff (1 - 0.45 * min(1, exertion/END))
const PAIN_TORQUE_DIV := 300.0        # tuned: (1 - min(0.5, pain_eff/300))
const RAGE_TORQUE := 1.15             # src: survey [OURS] rage +15% torque
const THETA_QUICK := 1.2              # src: survey [OURS] arc radians
const THETA_NORMAL := 2.0             # src: survey [OURS]
const THETA_HEAVY := 2.8              # src: survey [OURS]
const THETA_THRUST := 1.2             # tuned: a thrust spends a quick swing's energy
const THRUST_BODY_FRAC := 0.05        # src: survey O4 [OURS] arm-only thrust couples 5% of body mass
const THRUST_STROKE_M := 0.5          # tuned: thrust travel for prepare time
const V_CAP_BASE := 30.0              # tuned: m/s
const VEL_MULT_EXP := 0.5             # tuned: DF attack velocity multiplier applied as vel^0.5 (physics already models mass)
const DRAG_K := 0.05                  # Douglas: per-weapon air drag always on, on top of O1; tuned: v *= 1 - min(0.15, 0.05*drag)
const DRAG_MAX := 0.15                # src: handoff
const PRONE_TARGET_MOMENTUM := 2.0    # src: df_wiki ("Attacking a prone opponent in melee doubles momentum")
const PRONE_ATTACKER_MOMENTUM := 0.6  # tuned

## Weapon geometry in metres: s (length), b (balance point from grip), k (radius of gyration about the CoM).
## Derived from the template unless it carries "len"/"bal"/"gyr": hafted weapons put the head at 0.9 s.
static func weapon_geometry(t: Dictionary, head_mass: float, haft_mass: float) -> Dictionary:
	var s: float = float(t.get("len", float(t.get("reach", 80)) / 100.0))
	var b: float
	var k: float
	if haft_mass > 0.05:
		var m := head_mass + haft_mass
		b = (head_mass * 0.9 * s + haft_mass * 0.5 * s) / maxf(m, 0.01)
		var i_cm := head_mass * pow(0.9 * s - b, 2) + haft_mass * (s * s / 12.0 + pow(0.5 * s - b, 2))
		k = sqrt(i_cm / maxf(m, 0.01))
	else:
		b = 0.2 * s     # blade: balance just past the guard
		k = 0.25 * s
	return {"s": s, "b": float(t.get("bal", b)), "k": float(t.get("gyr", k))}

static func torque(strength: float, body_mass: float, grip: float, skill: float, ex_ratio: float, pain_eff: float) -> float:
	return TAU0 * (strength / 1000.0) * pow(body_mass / 70.0, 2.0 / 3.0) * grip * (1.0 + skill / SKILL_TORQUE_DIV) \
		* (1.0 - FATIGUE_TORQUE_K * clampf(ex_ratio, 0.0, 1.0)) * (1.0 - minf(0.5, pain_eff / PAIN_TORQUE_DIV))

## Continuous attribute effects use (attr/1000)^0.5 (survey item 2).
static func v_cap(agi: float, skill: float) -> float:
	return V_CAP_BASE * sqrt(maxf(agi, 200.0) / 1000.0) * (1.0 + skill / SKILL_TORQUE_DIV)

static func arm_length(body_mass: float, arm_len_pct: float) -> float:
	return ARM_LEN * pow(body_mass / 70.0, 1.0 / 3.0) * arm_len_pct / 100.0

## Full swing/thrust solution. Returns every intermediate for the calc log.
static func swing(body_mass: float, arm_pct: float, tau: float, theta: float, m: float, geo: Dictionary, thrust: bool,
		vel_mult: float, drag: float, agi: float, skill: float) -> Dictionary:
	var a := arm_length(body_mass, arm_pct)
	var m_arm := ARM_MASS_FRAC * body_mass
	var e := tau * theta
	var out := {"a": a, "m_arm": m_arm, "tau": tau, "theta": theta, "m": m, "thrust": thrust, "omega": 0.0, "I": 0.0}
	var v: float
	if thrust:
		v = sqrt(2.0 * e / (m + m_arm))
		out["m_eff"] = m + THRUST_BODY_FRAC * body_mass
	else:
		var s: float = geo["s"]
		var inertia := m_arm * a * a / 3.0 + m * pow(a + float(geo["b"]), 2) + m * pow(float(geo["k"]), 2)
		var omega := sqrt(2.0 * e / inertia)
		v = omega * (a + s)
		out["I"] = inertia
		out["omega"] = omega
		out["m_eff"] = inertia / pow(a + s, 2)
	var cap := v_cap(agi, skill)
	out["v_raw"] = v
	out["capped"] = v > cap
	v = minf(v, cap)
	var t_prep: float
	if thrust:
		t_prep = 2.0 * THRUST_STROKE_M / maxf(v, 0.1)
	else:
		t_prep = 2.0 * theta / (v / (a + float(geo["s"])))
	var dragf := 1.0 - minf(DRAG_MAX, DRAG_K * drag)
	var vm := pow(maxf(vel_mult, 0.1), VEL_MULT_EXP)
	v = v * dragf * vm
	out["drag"] = dragf
	out["vel"] = vm
	out["v"] = v
	out["p"] = float(out["m_eff"]) * v
	out["E"] = e * dragf * dragf
	out["prep_s"] = t_prep
	out["prep_ticks"] = t_prep / TICK_SECONDS
	return out

static func swing_text(s: Dictionary) -> String:
	if s.get("natural", false):
		return "NATURAL %s: base p %.1f x sqrt(torque x mass ratio %.2f) + gear %.2f kg -> p %.1f, v %.1f m/s, E %.0f J" % [
			s.get("verb", ""), s.get("base_p", 0.0), s.get("ratio", 1.0), s.get("gear", 0.0), s["p"], s["v"], s["E"]]
	if s["thrust"]:
		return "THRUST: tau %.1f Nm x theta %.1f -> E %.0f J; v = sqrt(2E/(m %.2f + arm %.1f)) = %.1f m/s%s; drag x%.2f, vel x%.2f -> v %.1f; p = (m + %.0f%% body) %.2f x v = %.1f; prepare %.2f s" % [
			s["tau"], s["theta"], s["E"], s["m"], s["m_arm"], s["v_raw"], " (capped)" if s["capped"] else "", s["drag"], s["vel"], s["v"],
			THRUST_BODY_FRAC * 100.0, s["m_eff"], s["p"], s["prep_s"]]
	return "SWING: tau %.1f Nm x theta %.1f -> E %.0f J; I = %.2f kgm2 (arm %.2fm/%.1fkg, weapon %.2fkg); omega %.1f -> v %.1f m/s%s; drag x%.2f, vel x%.2f -> v %.1f; m_eff %.2f -> p %.1f; prepare %.2f s" % [
		s["tau"], s["theta"], s["E"], s["I"], s["a"], s["m_arm"], s["m"], s["omega"], s["v_raw"], " (capped)" if s["capped"] else "",
		s["drag"], s["vel"], s["v"], s["m_eff"], s["p"], s["prep_s"]]

# =====================================================================================================
# Natural attacks (unarmed addendum): punch, kick, bite. Momentum scales with sqrt(torque ratio x mass ratio)
# (orc x1.58, goblin x0.53, troll x3.2 vs a median human). Gauntlets/boots add mass.
# =====================================================================================================
const NATURAL := {
	"punch": {"verb": "punch", "type": "blunt", "contact": 100, "prep": 2, "rec": 2, "p": 13.0, "v": 10.0, "gear_slot": "hands", "skill": "brawler"},
	"kick": {"verb": "kick", "type": "blunt", "contact": 400, "prep": 4, "rec": 4, "p": 32.0, "v": 8.0, "gear_slot": "feet", "skill": "brawler", "stagger": 1.5},
	"bite": {"verb": "bite", "type": "edge", "contact": 10, "penetration": 1500, "prep": 3, "rec": 3, "p": 3.0, "v": 6.0, "skill": "brawler"},
}  # src: survey unarmed addendum [OURS]
const KICK_STR_MIN := 1200            # src: survey: kick instead of punch if STR >= 1200

static func natural_swing(kind: String, strength: float, body_mass: float, skill: float, gear_kg: float, race_mult: float,
		ex_ratio: float, pain_eff: float) -> Dictionary:
	var n: Dictionary = NATURAL[kind]
	var tau_ratio := (strength / 1000.0) * pow(body_mass / 70.0, 2.0 / 3.0) * (1.0 + skill / SKILL_TORQUE_DIV) \
		* (1.0 - FATIGUE_TORQUE_K * clampf(ex_ratio, 0.0, 1.0)) * (1.0 - minf(0.5, pain_eff / PAIN_TORQUE_DIV))
	var ratio := sqrt(maxf(0.01, tau_ratio * body_mass / 70.0))
	var v := float(n["v"])
	var p := float(n["p"]) * ratio * race_mult + gear_kg * v
	return {"natural": true, "verb": kind, "base_p": n["p"], "ratio": ratio, "gear": gear_kg, "p": p, "v": v, "E": 0.5 * p * v,
		"prep_ticks": float(n["prep"]) * 1.5, "thrust": false, "capped": false}

# =====================================================================================================
# Layer tests (deterministic). DF forms, src: df_wiki (Weapon) / survey [DF]:
#   edged cut-through:  M >= (rSY + (A+1)*rSF) * (10+2Qa) / (Sha*Qw)    -- we test ENERGY x quality (survey O2)
#   blunt deflect:      2*w_size*IYw < A*armor_density -> glances off
#   blunt break:        M >= (2*IF - IY) * (2+0.4Qa) * A                  -- momentum
#   after a pass: -5%; edge stopped -> blunt for that layer; blunt stopped -> momentum x strain_at_yield/50000
#   (O7 via flags: rigid ~0.02, semi-rigid 0.35, padded 0.6, flexible mail/cloth 1.0).
# DF's raw contact areas (20..50000) make its linear A explode in this simplified model, so A is compressed by a
# power and the scale constants are tuned. Quality (10+2Qa) == DB.quality_mult.
# =====================================================================================================
const EDGE_C_ARMOR := 20.0            # tuned
const EDGE_C_TISSUE := 10.0           # tuned: flesh is cut far more easily than worked metal
const BONE_EDGE_MULT := 1.0           # tuned: copper edges bite bone poorly (DF bone shear yield 115k > copper 70k); x sqrt(t/10mm)
const EDGE_CONTACT_EXP := 0.2         # tuned: A_eff = contact^0.2 (stab 50 -> 2.2, slash 20000 -> 7.2)
const BLUNT_C_ARMOR := 1.4            # tuned
const BLUNT_C_TISSUE := 3.0           # tuned
const BLUNT_CONTACT_EXP := 0.3        # tuned: A_eff = contact^0.3 (mace 20 -> 2.5, slash-as-blunt 20000 -> 19.5)
const BLUNT_UNIT := 100000.0          # tuned: kPa -> abstract
const ARMOR_THICK_REF := 2.0          # tuned: armor resistance x sqrt(thickness/2mm)
const BONE_THICK_REF := 10.0          # tuned: bone x sqrt(thickness/10mm)
const SHARPNESS_FLOOR := 0.5          # tuned: material Sha = 0.5 + 0.5*MAX_EDGE/10000 (copper 1.0, tin 0.7); DF uses 1.0 for all metals
const PASS_KEEP := 0.95               # src: df_wiki (~5% momentum lost per layer penetrated)
const PENETRATION_MM_PER_UNIT := 0.01 # tuned: attack "penetration" 4000 -> 40 mm of cutting depth (x strike quality)
const TRANSMIT_RIGID := 0.02          # src: survey [DF] rigid metal keeps 1-2%
const TRANSMIT_SEMI := 0.35           # tuned: scale/lamellar middle (O7)
const TRANSMIT_PADDED := 0.6          # tuned: padded cloth damps blunt force (O7)
const TRANSMIT_FLEX := 1.0            # src: df_wiki/survey: mail and cloth keep 100%
const STRAIN_REF := 50000.0           # src: df_wiki strain_at_yield / 50000
const STR_MUSCLE_EXP := 0.5           # src: survey item 2 "STR thickens muscle": thickness x (STR/1000)^0.5
const THRUST_GAP_PER_LEVEL := 0.75    # src: survey item 2 [OURS] armor gap roll: thrusts -0.75% coverage per skill level x KIN/1000
const ARMOR_USER_COVER := 0.5         # src: survey item 2 [OURS] wearer +0.5% coverage per armor_user level
const FACE_FRACTION := 0.35           # tuned: share of head blows that land on the face (survey: faces never covered by helms)

static func sharpness(max_edge: float) -> float:
	return SHARPNESS_FLOOR + (1.0 - SHARPNESS_FLOOR) * clampf(max_edge / 10000.0, 0.0, 2.0)

static func edge_resistance(layer_mat: Dictionary, weapon_mat: Dictionary, contact: float, qa: float, qw: float,
		thickness_mm: float, is_armor: bool) -> float:
	var rsy := float(layer_mat.get("shear_yield", 20000)) / maxf(1.0, float(weapon_mat.get("shear_yield", 70000)))
	var rsf := float(layer_mat.get("shear_fracture", 20000)) / maxf(1.0, float(weapon_mat.get("shear_fracture", 220000)))
	var a := pow(maxf(contact, 1.0), EDGE_CONTACT_EXP)
	var sha := sharpness(float(weapon_mat.get("max_edge", 10000)))
	var r := (rsy + (a + 1.0) * rsf) * qa / (sha * qw)
	if is_armor:
		return r * EDGE_C_ARMOR * sqrt(maxf(thickness_mm, 0.5) / ARMOR_THICK_REF)
	if float(layer_mat.get("impact_strain", 50000)) < 1000.0:
		return r * EDGE_C_TISSUE * BONE_EDGE_MULT  # bone (stiff tissue)
	return r * EDGE_C_TISSUE

static func blunt_resistance(layer_mat: Dictionary, contact: float, qa: float, thickness_mm: float, kind: String) -> float:
	var iy := float(layer_mat.get("impact_yield", 10000))
	var iff := float(layer_mat.get("impact_fracture", 10000))
	var a := pow(maxf(contact, 1.0), BLUNT_CONTACT_EXP)
	var base := maxf(0.05, (2.0 * iff - iy) / BLUNT_UNIT) * a * qa
	if kind == "armor":
		return base * BLUNT_C_ARMOR * sqrt(maxf(thickness_mm, 0.5) / ARMOR_THICK_REF)
	if kind == "bone":
		return base * BLUNT_C_TISSUE * sqrt(maxf(thickness_mm, 1.0) / BONE_THICK_REF)
	return base * BLUNT_C_TISSUE

## DF blunt deflection: 2 * w_size(cm3) * IY_weapon < A * armor_density.
static func blunt_deflects(w_size_cm3: float, weapon_mat: Dictionary, contact: float, armor_mat: Dictionary) -> bool:
	if w_size_cm3 <= 0.0:
		return false
	return 2.0 * w_size_cm3 * float(weapon_mat.get("impact_yield", 245000)) < contact * float(armor_mat.get("density", 1000))

# ---- v0.014 gear damage (Douglas 22:52-22:58): pure material values, no per-metal multipliers.
# A weapon whose blow is STOPPED (the edge turned by armour or bone, or a blunt head on armour that holds) takes the
# reaction itself: the stopping layer pushes back with min(p, what that layer can take) (a layer that gives way at R
# pushed back with R). The weapon's own head is then tested like an armour layer of its own metal:
#   bend (yield): reaction >= C_armor x IY/1e5 x A^0.3 x Qw x sqrt(t/2mm)   -> bent back after, -1 quality step (-2 at 2x)
#   snap (fracture): reaction >= blunt_resistance(weapon metal) (the same DF form armour uses) -> broken: scrap
# t = the head's section: a blade = cube root of the head volume in mm (sword 300 cm3 -> 6.7 mm), a solid head
# (mace, hammer, club) = cube root in cm (-> mm), the whole head [tuned geometry].
# Chips: an edge stopped by a layer whose shear yield is above the blade's own yields first (copper 70k on bone 115k):
#   dull += 0.1 x min(1, SY_layer/SY_blade - 1); each 1.0 of dull is ground away for one quality step.
# Armour: blunt held but reaction >= its yield form (metal) = dented (-1 quality step); forced through (fracture form) =
#   rigid cracked / scale shattered (broken) or mail rings burst / cloth torn (a hole); an edge through = split (slash,
#   broken) or punctured (point, a hole). The struck spot is weakened for the rest of the battle (thickness x (1-0.6 w)).
const BLADE_T_K := 1.0                # tuned: blade section mm = cube root of the head cm3
const SOLID_T_K := 10.0               # tuned: solid head section mm = 10 x cube root of the head cm3 (whole head)
const BEND_SEVERE := 2.0              # tuned: reaction >= 2x the bend resistance = two quality steps
const CHIP_DULL := 0.1                # tuned: dulling per chip at a target twice as hard (or more)
const DULL_EDGE_K := 0.5              # tuned: edge (cut energy and depth) x (1 - 0.5 dull)
const SPOT_WEAKEN := 0.6              # tuned: a damaged armour spot keeps thickness x (1 - 0.6 w)
const SPOT_DENT := 0.25               # tuned: spot weakness per dent
const SPOT_HOLE := 0.5                # tuned: per puncture / burst rings / torn cloth
const SPOT_BROKEN := 1.0              # split, cracked, shattered

static func head_section_mm(head_cm3: float, solid: bool) -> float:
	return pow(maxf(head_cm3, 1.0), 1.0 / 3.0) * (SOLID_T_K if solid else BLADE_T_K)

## Yield form of the blunt test (IY in place of 2 IF - IY): what a metal piece takes before it bends or dents.
static func yield_resistance(mat: Dictionary, contact: float, q: float, thickness_mm: float) -> float:
	var iy := float(mat.get("impact_yield", 10000))
	return maxf(0.05, iy / BLUNT_UNIT) * pow(maxf(contact, 1.0), BLUNT_CONTACT_EXP) * q * BLUNT_C_ARMOR * sqrt(maxf(thickness_mm, 0.5) / ARMOR_THICK_REF)

## Chip size when an edge is stopped by a layer of `layer_mat` (0 when the layer is no harder than the blade).
static func chip_amount(layer_mat: Dictionary, weapon_mat: Dictionary) -> float:
	var r := float(layer_mat.get("shear_yield", 0)) / maxf(1.0, float(weapon_mat.get("shear_yield", 70000)))
	return CHIP_DULL * clampf(r - 1.0, 0.0, 1.0)

static func armor_transmit(rigid: bool, semi: bool, padded: bool) -> float:
	if rigid:
		return TRANSMIT_RIGID
	if semi:
		return TRANSMIT_SEMI
	if padded:
		return TRANSMIT_PADDED
	return TRANSMIT_FLEX

static func tissue_transmit(mat: Dictionary, edged: bool) -> float:
	var strain := float(mat.get("shear_strain" if edged else "impact_strain", 50000))
	return clampf(strain / STRAIN_REF, 0.0, 1.0)

static func coverage(cov_pct: float, thrust: bool, att_skill: float, att_kin: float, armor_user: float) -> float:
	var c := cov_pct + ARMOR_USER_COVER * armor_user
	if thrust:
		c -= THRUST_GAP_PER_LEVEL * att_skill * att_kin / 1000.0
	return clampf(c, 0.0, 100.0)

# =====================================================================================================
# Tissue damage (deterministic)
# =====================================================================================================
const PIERCE_CONTACT := 200.0         # tuned: contact <= 200 is a point (pierce/thrust), wider is a cut
const ORGAN_FRAGILITY := 2.0          # tuned
const SOFT_BLUNT_K := {"skin": 15.0, "fat": 15.0, "muscle": 15.0, "organ": 20.0, "brain": 9.0, "hide": 20.0}  # tuned
const SOFT_BLUNT_CAP := {"skin": 0.35, "fat": 0.35, "muscle": 0.45, "organ": 1.0, "brain": 1.0, "hide": 0.35}  # tuned
const BONE_DMG_BASE := 0.3            # tuned
const BONE_DMG_PER_LN := 0.35         # tuned
const TOU_DMG_EXP := 0.5              # src: survey item 2 continuous (TOU/1000)^0.5: tissue dmg and bleeding x (1000/TOU)^0.5
const VITAL_DESTROY := 0.9            # tuned: vital layer (heart, neck spine) destroyed -> death
const BRAIN_DEATH := 0.5              # src: survey [DF] "brain = instant death"; threshold tuned
const THINK_KO := 0.2                 # tuned: concussion knocks out
const SEVER_MIN_P := 10.0             # tuned: momentum (kg m/s) left after the last layer to sever, x body scale x relsize/100
const SEVER_MIN_CONTACT := 1000.0     # tuned: only cutting edges sever (survey: severing needs all tissues cut)
const STANCE_BONE_DISABLE := 0.6      # tuned
const STANCE_MUSCLE_DISABLE := 0.85   # tuned
const GRASP_BONE_DISABLE := 0.6       # tuned
const GRASP_MUSCLE_DISABLE := 0.85    # tuned
const TENDON_DISABLE := 0.5           # tuned: tendon torn -> grip/stance lost
const NERVE_DISABLE := 0.6            # tuned: motor nerve severed -> limb useless
const AIRWAY_CUT := 0.4               # tuned: airway cut -> struggling to breathe (suffocation)
const AIR_MAX := 600.0                # tuned: ticks of air (30 s) when the airway is fully cut
const AIR_KO := 0.5                   # tuned: unconscious below half air
const PAIN_CRY := 15.0                # tuned (log only, v0.014): a hit adding this much effective pain makes him cry out
const VOMIT_PAIN := 60.0             # tuned: a single hit adding this much effective pain makes the victim vomit (stunned)

static func width_factor(contact: float) -> float:
	return clampf(0.3 + 0.17 * log(maxf(contact, 1.0)) / log(10.0), 0.3, 1.0)

static func tou_mult(tou: float) -> float:
	return clampf(pow(1000.0 / maxf(tou, 100.0), TOU_DMG_EXP), 0.4, 1.6)

static func is_fragile(tissue: String) -> bool:
	return tissue == "organ" or tissue == "brain" or tissue == "vessel" or tissue == "nerve"

## DF wound kind stored on the layer (health system reads it).
static func edge_kind(tissue: String, contact: float, dmg: float) -> String:
	var point := contact <= PIERCE_CONTACT
	match tissue:
		"skin", "fat", "hide", "fur", "thick_hide", "scale":   # fur/thick_hide/scale: monsters wave 1 coats
			return "pierced" if point else "cut"
		"muscle", "tendon", "nerve", "vessel":
			return "torn"
		"bone":
			return "broken" if dmg >= 0.5 else "fractured"
		_:
			if dmg >= VITAL_DESTROY:
				return "destroyed"
			return "pierced" if point else "torn"

## Blunt bruising saturates: repeated bruises approach but never exceed the cap.
static func soft_blunt_dmg(tissue: String, p: float, r: float, thickness_mm: float, old: float) -> float:
	var k: float = SOFT_BLUNT_K.get(tissue, 15.0)
	var cap: float = SOFT_BLUNT_CAP.get(tissue, 0.4)
	var raw := clampf((p - r) / (k * (1.0 + thickness_mm / 20.0)), 0.0, cap)
	if cap < 1.0:
		raw *= maxf(0.0, 1.0 - old)
	return raw

static func bone_blunt_dmg(p: float, r: float) -> float:
	return clampf(BONE_DMG_BASE + BONE_DMG_PER_LN * log(maxf(p / r, 1.0)), 0.2, 1.0)

static func blunt_kind(tissue: String, dmg: float) -> String:
	if tissue == "bone":
		if dmg >= 0.9:
			return "mangled"
		return "broken" if dmg >= 0.5 else "fractured"
	if (tissue == "organ" or tissue == "brain") and dmg >= VITAL_DESTROY:
		return "destroyed"
	return "bruised"

## Log state word for a layer (survey item 6 register): edged cut/torn/severed/sliced through,
## blunt bruised/fractured/shattered/smashed/pulped/obliterated. Derived only from the computed result.
static func state_word(tissue: String, edged: bool, through: bool, dmg_total: float, point: bool) -> String:
	if edged:
		match tissue:
			"bone":
				return "cut through" if through else "chipped"
			"tendon", "nerve", "vessel":
				return "severed" if through else "nicked"
			"organ", "brain":
				if dmg_total >= VITAL_DESTROY:
					return "destroyed"
				return "pierced" if point else "torn open"
			"muscle":
				return ("run through" if point else "sliced through") if through else "torn"
			_:
				return ("pierced" if point else "sliced through") if through else "cut"
	match tissue:
		"bone":
			if dmg_total >= 0.8:
				return "smashed"
			return "shattered" if dmg_total >= 0.5 else "fractured"
		"organ", "brain", "vessel", "nerve":
			if dmg_total >= 0.95:
				return "obliterated"
			if dmg_total >= 0.6:
				return "pulped"
			return "bruised"
	return "bruised"

const KIND_RANK := {"": 0, "bruised": 1, "cut": 2, "pierced": 2, "torn": 3, "fractured": 3, "broken": 4, "mangled": 5, "destroyed": 6}

static func worse_kind(a: String, b: String) -> String:
	return a if int(KIND_RANK.get(a, 0)) >= int(KIND_RANK.get(b, 0)) else b

# =====================================================================================================
# Pain, bleeding, consciousness
# =====================================================================================================
## src: survey [DF] pain receptors: skin/fat/muscle 5, bone 50; x1 bruise, x2 partial, x3 broken/through.
const PAIN_RECEPTORS := {"skin": 5.0, "fat": 5.0, "muscle": 5.0, "bone": 50.0, "organ": 10.0, "brain": 0.0, "hide": 5.0,
	"tendon": 10.0, "nerve": 30.0, "vessel": 5.0}  # organ/tendon/nerve/vessel values ours
const PAIN_SCALE := 0.3               # tuned master knob: DF receptor numbers x0.3 (DF values made every fracture a knockdown)
const PAIN_SEVER := 50.0              # tuned
const PAIN_PERSIST := 0.4             # tuned: pain decays toward 40% of the pain of wounds taken
const PAIN_DECAY_PER_TICK := 0.006    # tuned
const PAIN_STUN := 50.0               # src: survey [OURS] stun ~50
const PAIN_KNOCKDOWN := 100.0         # src: survey [OURS] knockdown ~100
const PAIN_KO := 150.0                # src: survey [DF] 150 pain = unconscious
const PAIN_WAKE := 0.6                # tuned: wake when effective pain < 60% of PAIN_KO
const DISCIPLINE_PAIN := 0.03         # src: survey item 2 [OURS] pain tolerance: WIL + END + Discipline (3%/level)
## src: survey [DF] tissue vascular: skin 1, fat 3, muscle 5, bone 3 -> minor bleed per tick per unit dmg (scale tuned)
const BLEED_VASCULAR := {"skin": 1.0, "fat": 3.0, "muscle": 5.0, "bone": 3.0, "organ": 5.0, "brain": 2.0, "hide": 1.0,
	"tendon": 1.0, "nerve": 1.0, "vessel": 5.0}
const BLEED_MINOR_SCALE := 0.004      # tuned: muscle fully cut -> 0.02 blood/tick
const BLEED_ARTERY_MULT := 1.5        # tuned: bodies.json artery value x1.5 per tick
const ARTERY_CHANCE := 0.25           # tuned: x cut depth; thrusts x1.5 (survey O4: thrusts roll arteries up)
const BLEED_SEVER_PER_RELSIZE := 0.0012  # tuned: severed arm (relsize 200) bleeds 0.24/tick
const CLOT_ARTERY := 0.0004           # tuned
const CLOT_MINOR := 0.004             # tuned
const BLOOD_WEAK := 0.85              # src: survey [OURS] weak at 15% lost
const BLOOD_FAINT := 0.70             # src: survey [OURS] collapse at 30% lost
const BLOOD_DEATH := 0.55             # src: survey [OURS] dead at 40-50% lost (45%)
const HEAD_STUN_P := 30.0             # tuned: blunt momentum reaching the skull for a certain stun (head-blow stun roll)
const BLEED_WORDS := [0.03, 0.15]     # tuned: < nicked vessel, < artery opened, >= major artery (log wording)

static func pain_kind_mult(kind: String, through: bool) -> float:
	if kind == "bruised":
		return 1.0
	if through or kind in ["broken", "mangled", "destroyed"]:
		return 3.0
	return 2.0

## src: survey [OURS] pain tolerance: pain * 1000 / ((WIL + END) / 2), Discipline helps.
static func pain_mult(wil: float, endu: float, discipline: float) -> float:
	return PAIN_SCALE * clampf(1000.0 / maxf(100.0, (wil + endu) / 2.0), 0.3, 3.0) / (1.0 + DISCIPLINE_PAIN * discipline)

# =====================================================================================================
# Stagger (survey O6 [OURS]): p / stability adds ticks; above ~2x = knockdown.
# stability = (mass + gear) x legs x sqrt(AGI/1000) x shield brace (survey item 2)
# =====================================================================================================
const STAGGER_STAB_K := 0.4           # tuned
const STAGGER_TICKS_PER := 5.0        # tuned: ticks added per 1.0 of stagger ratio
const STAGGER_KNOCKDOWN := 2.0        # src: survey [OURS]
const STAGGER_PRONE_STAB := 0.3       # tuned
const STAGGER_SHIELD_BRACE := 1.15    # tuned

static func stability(body_mass: float, gear_mass: float, leg_impair: float, prone: bool, shield: bool, agi: float) -> float:
	return (body_mass + gear_mass) * STAGGER_STAB_K * (1.0 - 0.5 * leg_impair) * (STAGGER_PRONE_STAB if prone else 1.0) \
		* (STAGGER_SHIELD_BRACE if shield else 1.0) * sqrt(maxf(agi, 200.0) / 1000.0)

# =====================================================================================================
# Morale (survey item 3). Morale 0..100: start 50 + (courage-50)/2 + officer Leader aura.
# shock = base x (1.5 - nerve/100) x (1 - min(0.75, hardness/100)). Below 25: roll vs courage + Discipline to rout.
# =====================================================================================================
const MORALE_START := 50.0            # src: survey [OURS]
const LEADER_AURA_PER_LEVEL := 1.0    # tuned: + per leader level of the best officer within LEADER_RADIUS
const LEADER_RADIUS := 6              # tuned
const SHOCK_ALLY_DIES := 8.0          # src: survey [OURS]
const STRESS_RADIUS := 6              # tuned: allies this close feel a death or rout
const DOWNS_PER_TICK := 1             # perf/mechanics: fall/rout shocks spread to nearby allies one source per tick (panic travels)
const SHOCK_ALLY_KO := 5.0            # tuned: an ally knocked out nearby
const SHOCK_ALLY_ROUTS := 1.0         # tuned: an ally running away nearby
const FLANK_SHOCK_COOLDOWN := 40      # tuned: the flanked shock lands at most once per 40 ticks
const SHOCK_OFFICER_FALLS := 25.0     # src: survey [OURS] x (0.5 + loyalty/100)
const SHOCK_WOUND_DIV := 10.0         # src: survey [OURS] wound: -pain/10
const SHOCK_FLANKED := 5.0            # src: survey [OURS]
const SHOCK_OUTNUMBERED := 10.0       # src: survey [OURS] outnumbered 2:1 (checked every MORALE_TICK)
const SHOCK_INTIMIDATE_PER := 1.0     # tuned: enemy intimidator kill nearby: + per intimidator level
const SHOCK_SEVER := 10.0             # tuned
const HARDNESS_MAX_CUT := 0.75        # src: survey [OURS]
const COHESION_GAIN_RADIUS := 3       # src: survey [OURS]
const MORALE_GAIN_PER_ALLY := 1.0     # tuned: per MORALE_TICK, per ally within 3 tiles (max cohesion/20 allies)
const MORALE_KILL := 3.0              # src: survey [OURS]
const MORALE_ROUT_BELOW := 25.0       # src: survey [OURS]
const MORALE_TICK := 20               # tuned: periodic morale update (outnumbered, cohesion, rally)
const ROUT_BASE := 0.45               # tuned: rout chance at courage 0, discipline 0
const ROUT_COURAGE := 0.006           # tuned: - per courage point
const ROUT_DISCIPLINE := 0.04         # tuned: - per discipline level
const ROUT_DEPTH := 0.02              # tuned: + per morale point below 25
const RALLY_BASE := 0.02              # tuned: per MORALE_TICK while routed
const RALLY_LOYALTY := 0.001          # tuned: + per loyalty point
const RALLY_LEADER := 0.02            # tuned: + per leader level within range
const RALLY_MORALE := 35.0            # tuned
const RAGE_TICKS := 200               # tuned
const RAGE_CHANCE_K := 0.25           # tuned: survey rage chance = temper/100; scaled x0.25 per trigger (a trigger is every serious wound or nearby death)
const MORALE_OUTNUMBER_RACE := 1.5    # tuned: races with outnumber_morale take x1.5 outnumbered shock

## food: start-of-battle modifier from belly, buzz and favourite drink (core/food.gd; 0 = no change).
static func morale_start(courage: float, leader_lv: float, food: float = 0.0) -> float:
	return clampf(MORALE_START + (courage - 50.0) / 2.0 + LEADER_AURA_PER_LEVEL * leader_lv + food, 5.0, 100.0)

static func shock(base: float, nerve: float, hardness: float) -> float:
	return base * (1.5 - nerve / 100.0) * (1.0 - minf(HARDNESS_MAX_CUT, hardness / 100.0))

static func rout_chance(morale: float, courage: float, discipline: float) -> float:
	return clampf(ROUT_BASE - ROUT_COURAGE * courage - ROUT_DISCIPLINE * discipline + ROUT_DEPTH * (MORALE_ROUT_BELOW - morale), 0.02, 0.95)

# =====================================================================================================
# Stuck weapons (survey lodge rules [OURS])
# =====================================================================================================
const LODGE_BASE := {"stab": 0.30, "thrust": 0.30, "hack": 0.20, "slash": 0.04}  # src: survey [OURS]; other verbs by motion
const LODGE_BONE_MULT := 1.5          # src: survey [OURS] stopped by bone
const TWIST_MOMENTUM := 0.3           # src: survey [OURS]
const TWIST_PAIN_MULT := 2.0          # src: survey [OURS]
const TWIST_BLEED_MULT := 1.5         # src: survey [OURS]
const PULL_BASE_TICKS := 4            # src: survey [OURS] 4 + 1/layer, -1 per 500 STR above 1000, min 3
const PULL_MIN_TICKS := 3             # src: survey [OURS]
const VICTIM_PULL_BASE := 6           # src: survey [OURS] 6 + 1/layer
const EXIT_TEAR := 0.15               # src: survey [OURS] exit tear 0.15x momentum
const LET_GO_LIMIT := 6               # src: survey [OURS] pull out only if <= 6 ticks when threatened, else let go
const LEFT_IN_BLEED := 0.5            # src: survey [OURS] weapon left in: bleed x0.5
const LEFT_IN_PAIN := 3.0             # tuned: pain per action with a weapon left in the wound
const RETRIEVE_TICKS := 4             # src: survey [OURS] retrieve = move + 4 (+1/layer from a body)
const RETRIEVE_RADIUS := 2            # src: survey [OURS]

static func lodge_base(verb: String, thrust: bool) -> float:
	var v := verb.split(" ")[0]
	if LODGE_BASE.has(v):
		return LODGE_BASE[v]
	return LODGE_BASE["stab"] if thrust else LODGE_BASE["slash"]

static func pull_ticks(layers: int, strength: float) -> int:
	return maxi(PULL_MIN_TICKS, PULL_BASE_TICKS + layers - int(maxf(0.0, strength - 1000.0) / 500.0))

# =====================================================================================================
# Wrestling contest (unarmed addendum): P = clamp(.5 + .05*(Wrestler eff diff) + .25*log2(my mass/their mass), .05, .95)
# =====================================================================================================
const GRAB_MASS_LOG := 0.25           # src: survey [OURS]

static func grab_chance(my_eff: float, their_eff: float, my_mass: float, their_mass: float) -> float:
	return clampf(0.5 + CONTEST_SLOPE * (my_eff - their_eff) + GRAB_MASS_LOG * log(maxf(my_mass, 1.0) / maxf(their_mass, 1.0)) / log(2.0), 0.05, 0.95)

# =====================================================================================================
# Targeting
# =====================================================================================================
const TARGET_NOISE := 2.5             # tuned: "nearest-ish"
const TARGET_ROUTED_PENALTY := 4.0    # tuned
const TARGET_HELPLESS_PENALTY := 2.0  # tuned
const HELPLESS_HEAD_WEIGHT := 10.0    # src: survey [DF] vs helpless: head (weight tuned)
const POLEARM_MIN_REACH := 220.0      # src: survey O5 [OURS] weapons this long (glaive 230) hit with the haft when adjacent

# =====================================================================================================
# Strike quality (survey: the main variance; mean = skill + FOC, KIN narrows the spread; 2% tail = max quality)
# =====================================================================================================
const SQ_MEAN_BASE := 0.85            # tuned
const SQ_MEAN_SKILL := 0.15           # tuned: + at effective level 20
const SQ_SD_BASE := 0.25              # tuned
const SQ_MIN := 0.3                   # tuned
const SQ_MAX := 1.6                   # tuned
const SQ_TAIL := 0.02                 # src: survey [OURS] 2% of strikes roll max quality

static func strike_quality_params(level: float, kin: float) -> Array:
	var mean := SQ_MEAN_BASE + SQ_MEAN_SKILL * clampf(level / 20.0, 0.0, 1.0)
	var sd := clampf(SQ_SD_BASE * (1.0 - 0.5 * clampf(level / 20.0, 0.0, 1.0)) * sqrt(1000.0 / maxf(kin, 200.0)), 0.05, 0.45)
	return [mean, sd]

# =====================================================================================================
# Bows (docs/specs/bows.md, sim/archery.gd). POWER = draw: how far the archer can pull (STR, a little body mass
# and END) against the bow's draw weight; the shot's energy comes from the WEAKER of the two. SKILL = accuracy:
# it narrows the one aim-error roll per shot, picks spots and shortens the aim; it never adds energy. Flight is
# deterministic after the aim roll (drag, drop, arc). Impact goes through the same layer tests as a thrust.
# =====================================================================================================
const TILE_M := 1.5                   # tuned [ours]: metres per battle tile (flight, drop, drag, range)
const GRAVITY := 9.81
const DRAW_F0 := 300.0                # tuned: newtons a median human (STR 1000, 70 kg, END 1000) can pull and hold
const DRAW_MASS_EXP := 0.25           # tuned: "plus a little body mass" (pull x (mass/70)^0.25)
const DRAW_END_K := 0.1               # tuned: "and END" (+10% pull per +1000 END)
const DRAW_LEN_M := 0.74              # tuned: draw length of a median human, 29" (x race height x height % x arm length %)
const ARROW_REF_KG := 0.06            # bows.json efficiencies are quoted for a 60 g arrow
const BOW_QUALITY_EFF := 0.25         # tuned: each +1.0 of quality mult closes 25% of the gap from efficiency to 1
const BOW_EFF_MAX := 0.92             # tuned: no bow returns more than this of the drawn energy
const DRAW_TICKS := 14.0              # tuned: ticks to draw at a comfortable weight (x (0.6 + 0.8 strain) x tempo)
const AIM_TICKS := 16.0               # tuned: ticks to aim; skill shortens it (down to half at level 15)
const NOCK_TICKS := 10.0              # tuned: ticks to take and nock the next arrow (x recover mult x tempo)
const HOLD_EXERT_K := 0.6             # tuned: holding full draw costs more: exertion x (1 + 0.6 strain^2)
const AIM_SD0_DEG := 2.5              # tuned: aim error sd (degrees) of an effective level 0 archer at an easy draw
const AIM_LVL_HALF := 5.0             # tuned: sd / (1 + level/5)
const AIM_SHAKE_K := 0.6              # tuned: shakier hold near the archer's limit: sd x (1 + 0.6 strain^2)
const AIM_QUALITY_EXP := 0.5          # tuned: a better bow steadies aim: sd / quality_mult^0.5
const AIM_FEAR_K := 0.5               # tuned: fear: sd x (1 + 0.5 x (50 - morale)/50) below morale 50
const AIM_TARGET_MOVING := 1.4        # tuned: target moved in the last AIM_MOVE_TICKS
const AIM_SELF_MOVING := 1.3          # tuned: archer moved (kiting) in the last AIM_MOVE_TICKS
const AIM_MOVE_TICKS := 12
const AIM_SAT_PER := 0.05             # tuned: + per defence the target made recently (a target in a scrum jinks about)
const AIM_ELEV_SHARE := 0.7           # tuned: elevation error sd = 0.7 x the lateral sd
const DRAG_RHO_CDA := 1.9e-4          # tuned: air density x drag coefficient x frontal area of an arrow (kg/m)
const FLAT_DROP_M := 0.8              # tuned: a shot that drops less than this on its way is flat; beyond that it arcs
const ARC_FALL_TILES := 2.0           # tuned: the descending end of an arc that can strike a standing man
const ELEV_RANGE_K := 4.0             # tuned: landing distance error = distance x 4 x elevation error (rad), arcs
const FLAT_OVERRUN_TILES := 6.0       # tuned: a flat shot that hits nothing flies on this far before it comes down
const RANGE_K := 0.55                 # tuned: max range = v0^2/g x 0.55 (drag, real launch angles)
const SILHOUETTE_HALF_M := 0.25       # tuned: half the width a 70 kg man shows (x (mass/70)^(1/3))
const SILHOUETTE_HALF_H_M := 0.8      # tuned: half the height of a standing man's hittable zone (x race height)
const AIM_HEIGHT_M := 1.2             # tuned: height an archer looses from and aims at (flat shots)
const ARROW_ARMOR_SPEND := 0.5        # tuned: share of an armour layer's resistance an arrow spends cutting through it
const ARROW_TISSUE_SPEND := 2.0       # tuned: joules per 10 mm of tissue = the layer resistance x this (gel-like: ~2-3 J/cm of muscle)
const ARROW_EXIT_MIN_J := 3.0         # tuned: energy left after the last layer for the arrow to come out and fly on
const ARROW_STICK_FRAC := 0.35        # tuned: a stopped arrow sticks in a shield when E >= 0.35 x R, else bounces
const PROJECTILE_BLOCK_MULT := 2.0    # src: df_wiki shields block projectiles twice as well (survey [DF])
const ARROW_BUSY_DODGE := 4.0         # tuned: dodge -4 levels while an enemy has the target in reach (busy in melee)
const ARROW_SPEED_LEVELS := 20.0      # tuned: +1 attack level per 20 m/s of arrow speed (fast arrows are hard to see)
const SHIELD_BOSS_SHARE := 0.15       # tuned: share of blocks that take the arrow on the boss (squarest blocks)
const SHIELD_RIM_SHARE := 0.2         # tuned: share of blocks that only catch it on the rim (barest blocks)
const SHIELD_BOSS_THICK := 3.0        # tuned: a boss is three times the shield's plate
const SHIELD_RIM_THICK := 1.5         # tuned: the rim is folded or bound: 1.5 x
const SHIELD_RIM_SQUARE := 0.4        # tuned: a rim catch is glancing: only this share of the energy bears on it
const SHIELD_BOSS_SQUARE := 0.7       # tuned: a boss is domed: an arrow meets it obliquely
const ARROW_PULL_TEAR := 0.05         # tuned: tissue damage pulling a lodged arrow out on the field (x shape tear)
const BOW_MIN_RANGE := 2              # spec: ~2 tiles (bows.json min_range per bow)
const BOW_SWITCH_MARGIN := 2          # spec: switch back to the bow when the nearest enemy is past min range + margin
const BOW_KITE_TILES := 4             # tuned: archers back off when an enemy is this close
const BOW_PANIC_MORALE := 35.0        # tuned: below this an archer drops the bow instead of slinging it
const BOW_DROP_TICKS := 2             # spec: drop the bow (fast)
const BOW_SLING_TICKS := 10           # spec: sling it (slower)
const BOW_UNSLING_TICKS := 8          # tuned
const BOW_TRAMPLE_KG := 60.0          # tuned: a dropped bow breaks under anyone this heavy (body + gear) stepping on it
const BOW_FETCH_TILES := 6            # tuned: a dropped bow this close is fetched when the bow is wanted again
## Share of the arrows on a held field fit to shoot again (the rest is broken: scrap) [ours].
const ARROW_RECOVER := {"ground": 0.75, "body": 0.5, "shield": 0.6, "armor": 0.4}

## How hard the archer can pull and hold (N): STR, a little body mass and END, less for fatigue, pain and blood.
static func pull_force(strength: float, body_mass: float, endu: float, ex_ratio: float, pain_eff: float, blood_frac: float) -> float:
	return DRAW_F0 * (strength / 1000.0) * pow(maxf(body_mass, 5.0) / 70.0, DRAW_MASS_EXP) \
		* (1.0 + DRAW_END_K * (endu - 1000.0) / 1000.0) * (1.0 - FATIGUE_TORQUE_K * clampf(ex_ratio, 0.0, 1.0)) \
		* (1.0 - minf(0.5, pain_eff / PAIN_TORQUE_DIV)) * clampf(blood_frac / BLOOD_WEAK, 0.5, 1.0)

## How far the archer can draw (m): his height (race height x his height %) and arm length %.
static func draw_length(height: float, arm_pct: float) -> float:
	return DRAW_LEN_M * height * arm_pct / 100.0

## Energy a bow stores at full draw: ~0.5 x draw weight x draw length (spec).
static func bow_store(draw_n: float, draw_m: float) -> float:
	return 0.5 * draw_n * draw_m

## What the archer can put into this bow (J): a linear limb at the force or length he can reach.
static func archer_draw_energy(pull_n: float, reach_m: float, draw_n: float, draw_m: float) -> float:
	var x := minf(pull_n / maxf(draw_n, 1.0), reach_m / maxf(draw_m, 0.1))
	return bow_store(draw_n, draw_m) * x * x

## Efficiency with this arrow: quality raises it, item variance scales it, a heavier arrow takes more of it.
static func bow_efficiency(eff: float, qmult: float, vr: float, virt_kg: float, arrow_kg: float) -> float:
	var e := (eff + (1.0 - eff) * BOW_QUALITY_EFF * (qmult - 1.0)) * vr
	var dyn := (arrow_kg / (arrow_kg + virt_kg)) / (ARROW_REF_KG / (ARROW_REF_KG + virt_kg))
	return clampf(e * dyn, 0.05, BOW_EFF_MAX)

## The whole shot solution before the aim roll. MAXIMUM OUTPUT: energy from the WEAKER of the archer's draw and the
## bow's limit; extra STR adds nothing to the shot, only a faster, steadier, less tiring draw (strain).
static func bow_shot(pull_n: float, reach_m: float, bow: Dictionary, qmult: float, vr: float, arrow_kg: float) -> Dictionary:
	var fn := float(bow.get("draw_n", 250.0))
	var lm := float(bow.get("draw_m", 0.71))
	var e_bow := bow_store(fn, lm)
	var e_arch := archer_draw_energy(pull_n, reach_m, fn, lm)
	var e_drawn := minf(e_bow, e_arch)
	var x := sqrt(e_drawn / maxf(e_bow, 0.01))          # share of the full draw reached
	var f_held := fn * x                                 # limb force at that draw
	var strain := clampf(f_held / maxf(pull_n, 1.0), 0.0, 1.0)
	var eff := bow_efficiency(float(bow.get("eff", 0.7)), qmult, vr, float(bow.get("virt_kg", 0.025)), arrow_kg)
	var e := e_drawn * eff
	var v0 := sqrt(2.0 * e / maxf(arrow_kg, 0.005))
	return {"pull": pull_n, "reach": reach_m, "draw_n": fn, "draw_m": lm, "e_bow": e_bow, "e_arch": e_arch, "e_drawn": e_drawn,
		"x": x, "strain": strain, "eff": eff, "E": e, "m": arrow_kg, "v0": v0, "p": arrow_kg * v0,
		"partial": e_arch < e_bow}

## Draw and aim ticks (before tempo): draw grows with draw weight vs the archer's pull; skill shortens the aim.
static func draw_ticks(strain: float) -> float:
	return DRAW_TICKS * (0.6 + 0.8 * strain)

static func aim_ticks(level: float) -> float:
	return AIM_TICKS * (1.0 - 0.5 * clampf(level / 15.0, 0.0, 1.0))

## Aim error sd in degrees (spec 4: narrows with skill/attributes/bow quality; widens with strain, fear, movement,
## a target in a scrum). Pain and exertion come in through the effective level.
static func aim_sd(level: float, strain: float, qmult: float, morale: float, target_moving: bool, self_moving: bool,
		target_defences: int) -> float:
	var sd := AIM_SD0_DEG / (1.0 + maxf(0.0, level) / AIM_LVL_HALF)
	sd *= 1.0 + AIM_SHAKE_K * strain * strain
	sd /= pow(maxf(qmult, 1.0), AIM_QUALITY_EXP)
	sd *= 1.0 + AIM_FEAR_K * maxf(0.0, 50.0 - morale) / 50.0
	if target_moving:
		sd *= AIM_TARGET_MOVING
	if self_moving:
		sd *= AIM_SELF_MOVING
	sd *= 1.0 + AIM_SAT_PER * target_defences
	return sd

## Distance (tiles) an arrow flies flat (drops less than FLAT_DROP_M): lighter, faster arrows shoot flatter.
static func flat_range_tiles(v0: float) -> float:
	return v0 * sqrt(2.0 * FLAT_DROP_M / GRAVITY) / TILE_M

static func max_range_tiles(v0: float) -> float:
	return v0 * v0 / GRAVITY * RANGE_K / TILE_M

## Drag: v(s) = v0 exp(-s / Ld), Ld = 2 m / (rho Cd A): heavier arrows keep their speed.
static func drag_len_m(arrow_kg: float) -> float:
	return 2.0 * arrow_kg / DRAG_RHO_CDA

static func silhouette_half_tiles(body_mass: float) -> float:
	return SILHOUETTE_HALF_M * pow(maxf(body_mass, 5.0) / 70.0, 1.0 / 3.0) / TILE_M

# =====================================================================================================
# NAMED ROLLS - the only places the sim draws random numbers.
# =====================================================================================================
const ROLL_WORDS := {
	"contest": ["gets through", "defended"], "spot": ["spotted", "unseen"], "cover": ["covered", "gap"],
	"organ": ["reached", "missed"], "artery": ["OPENED", "missed"], "head_stun": ["stunned", "shrugs it off"],
	"morale": ["BREAKS", "holds"], "rally": ["RALLIES", "keeps running"], "rage": ["ENRAGED", "keeps calm"],
	"lodge": ["LODGED", "comes free"], "face": ["face", "skull"], "grab": ["grabbed", "slips free"],
	"stumble": ["STUMBLES", "keeps his feet"],
}

static func _roll(rng: RandomNumberGenerator, name: String, chance: float, sub: String = "") -> Dictionary:
	var r := rng.randf()
	return roll_record(name, r, chance, sub)

## The record of a _roll from its draw (for a roll whose record is only kept when it succeeds).
static func roll_record(name: String, r: float, chance: float, sub: String = "") -> Dictionary:
	return {"n": name, "s": sub, "r": r, "p": chance, "ok": r < chance}

## Perf variants for rolls whose record is not kept: the exact draw and test of the named roll, no dictionary.
static func roll_rage_ok(rng: RandomNumberGenerator, chance: float) -> bool:   # = roll_rage(rng, chance)["ok"]
	return rng.randf() < chance

static func roll_rally_ok(rng: RandomNumberGenerator, chance: float) -> bool:   # = roll_rally(rng, chance)["ok"]
	return rng.randf() < chance

## roll_morale in two steps: the draw (r < fail_chance = breaks), then roll_record("morale", r, fail_chance) if needed.
static func roll_morale_draw(rng: RandomNumberGenerator) -> float:
	return rng.randf()

static func roll_text(rr: Dictionary) -> String:
	if rr.has("lat"):   # bows: the aim roll
		return "[roll:aim] lateral %+.2f deg, elevation %+.2f deg (sd %.2f deg)" % [rr["lat"], rr["elev"], rr["sd"]]
	if rr.has("q"):
		return "[roll:strike_quality] z %.2f -> q %.2f (mean %.2f, sd %.2f%s)" % [rr["r"], rr["q"], rr["mean"], rr["sd"], ", TAIL: max quality" if rr["tail"] else ""]
	if rr.has("i"):
		return "[roll:%s] %.0f/%.0f -> %s" % [rr["n"], rr["r"], rr["total"], rr["label"]]
	var w: Array = ROLL_WORDS.get(rr["n"], ["yes", "no"])
	var nm: String = rr["n"] + (":" + rr["s"] if rr["s"] != "" else "")
	return "[roll:%s] %.2f vs %.2f -> %s" % [nm, rr["r"], rr["p"], w[0] if rr["ok"] else w[1]]

## The one defence contest per attack: r < p means the attack gets through.
static func roll_contest(rng: RandomNumberGenerator, p_through: float, defence: String) -> Dictionary:
	return _roll(rng, "contest", p_through, defence)

static func roll_spot(rng: RandomNumberGenerator, chance: float) -> Dictionary:
	return _roll(rng, "spot", chance)

static func roll_coverage(rng: RandomNumberGenerator, item_name: String, coverage_pct: float) -> Dictionary:
	return _roll(rng, "cover", coverage_pct / 100.0, item_name)

static func roll_face(rng: RandomNumberGenerator) -> Dictionary:
	return _roll(rng, "face", FACE_FRACTION)

static func roll_inner_layer(rng: RandomNumberGenerator, layer_name: String, chance: float) -> Dictionary:
	return _roll(rng, "organ", chance, layer_name)

static func roll_artery(rng: RandomNumberGenerator, layer_name: String, chance: float) -> Dictionary:
	return _roll(rng, "artery", chance, layer_name)

static func roll_head_stun(rng: RandomNumberGenerator, chance: float) -> Dictionary:
	return _roll(rng, "head_stun", chance)

static func roll_morale(rng: RandomNumberGenerator, fail_chance: float) -> Dictionary:
	return _roll(rng, "morale", fail_chance)

static func roll_rally(rng: RandomNumberGenerator, chance: float) -> Dictionary:
	return _roll(rng, "rally", chance)

static func roll_rage(rng: RandomNumberGenerator, chance: float) -> Dictionary:
	return _roll(rng, "rage", chance)

static func roll_lodge(rng: RandomNumberGenerator, chance: float) -> Dictionary:
	return _roll(rng, "lodge", chance)

static func roll_grab(rng: RandomNumberGenerator, chance: float) -> Dictionary:
	return _roll(rng, "grab", chance)

## Hammered men stumble over their own feet (core/food.gd: 2% per move); the move is lost.
static func roll_stumble(rng: RandomNumberGenerator, chance: float) -> Dictionary:
	return _roll(rng, "stumble", chance)

## One roll per strike: how well the blow lands (edge alignment, timing). Scales energy, momentum and depth.
static func roll_strike_quality(rng: RandomNumberGenerator, level: float, kin: float) -> Dictionary:
	var pr := strike_quality_params(level, kin)
	var tail := rng.randf() < SQ_TAIL
	var z := rng.randfn(0.0, 1.0)
	var q := SQ_MAX if tail else clampf(float(pr[0]) + z * float(pr[1]), SQ_MIN, SQ_MAX)
	return {"n": "strike_quality", "r": z, "q": q, "mean": pr[0], "sd": pr[1], "tail": tail}

## bows: the ONE aim-error roll per shot (spec 4): an angle off the line to the target (lateral) and off the
## intended elevation, both normal with the archer's sd (elevation x AIM_ELEV_SHARE). Flight is deterministic after it.
static func roll_aim(rng: RandomNumberGenerator, sd_deg: float) -> Dictionary:
	var lat := rng.randfn(0.0, 1.0) * sd_deg
	var elev := rng.randfn(0.0, 1.0) * sd_deg * AIM_ELEV_SHARE
	return {"n": "aim", "lat": lat, "elev": elev, "sd": sd_deg}

## Weighted pick; returns {"i", "r", "total", "label"}.
static func roll_weighted(rng: RandomNumberGenerator, name: String, weights: Array, labels: Array) -> Dictionary:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := rng.randf() * total
	var acc := 0.0
	var pick := weights.size() - 1
	for i in weights.size():
		acc += float(weights[i])
		if r < acc:
			pick = i
			break
	return {"n": name, "i": pick, "r": r, "total": total, "label": str(labels[pick])}

static func roll_attack_choice(rng: RandomNumberGenerator, attacks: Array) -> Dictionary:
	var ws := []
	var ls := []
	for a in attacks:
		ws.append(float(a.get("w", 1)))
		ls.append(a.get("verb", "attack"))
	return roll_weighted(rng, "attack", ws, ls)

static func roll_body_part(rng: RandomNumberGenerator, weights: Array, labels: Array) -> Dictionary:
	return roll_weighted(rng, "part", weights, labels)

## v0.013 (DF): a blow through a part's layers goes on into one of its inner parts, picked by DF relative size.
static func roll_inner_part(rng: RandomNumberGenerator, weights: Array, labels: Array) -> Dictionary:
	return roll_weighted(rng, "inner", weights, labels)

## Random preference added to each candidate's distance when picking a target.
static func roll_target_noise(rng: RandomNumberGenerator) -> float:
	return rng.randf() * TARGET_NOISE

## Initiative tie-break (same AGI+KIN): rolled once per fighter at setup.
static func roll_initiative_tiebreak(rng: RandomNumberGenerator) -> float:
	return rng.randf()
