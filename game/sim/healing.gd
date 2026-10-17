class_name Healing
extends RefCounted
## Wound recovery: timers, bandaging, town healers, and lasting effects. No HP anywhere.
##
## Reads and writes BodyState layers (see core/body_state.gd). Extra per-layer keys this file owns:
##   "heal_days"  float  days of town rest left (the timer shown on the medical screen)
##   "heal_total" float  the timer when the wound was assessed (progress -> "mending")
##   "heal_dmg"   float  dmg the timer was computed for (a fresh hit above this re-assesses)
##   "heal_rank"  int    kind rank the timer was computed for
##   "treated"    int    best healer skill that treated this wound (0 = untreated)
##   "permanent"  bool   this layer will never heal back (destroyed eye, stump); dmg is not reduced
## Per-part key (parts[id]):
##   "impair" float 0..1  PERMANENT loss of that part's function (0 normal, 1 useless/lost).
##       Set when a part is severed (1.0), an eye/lung is destroyed, or a bad wound heals badly
##       (badly mended bone 0.15-0.7, ruined muscle 0.1-0.5, scarred organ 0.3-0.5).
##       Suggested sim use: stance parts -> move speed / balance, grasp chain -> attack and block,
##       sight -> to-hit, lung (upper body) -> exertion gain, head brain -> reaction time.
## Body-level: body.permanent gets human-readable strings ("left eye destroyed", "left hand lost",
##   "left lower leg bone badly mended - limps"). The report adds " - permanent".
##
## Timers follow DF's ordering (skin and fat heal fast, muscle slower, bone slowest and needs setting,
## nervous tissue/eyes do not regrow) and DF's REC (recuperation) attribute. The day counts themselves
## are our own tuning (DF does not document wall-clock times); flagged as estimated.
## A timer is in days of town rest. Out of town (marching, camping) wounds heal at FIELD_RATE.

const KIND_RANK := {"": 0, "bruised": 1, "cut": 2, "pierced": 3, "torn": 3, "fractured": 4, "broken": 5,
	"mangled": 6, "destroyed": 7}

## Base days for a wound of that tissue and kind at dmg 0.5; scaled by lerp(0.6, 1.4, dmg). (estimated)
const BASE_DAYS := {
	"skin":   {"bruised": 3, "cut": 6, "pierced": 6, "torn": 9, "fractured": 6, "broken": 9, "mangled": 14, "destroyed": 21},
	"fat":    {"bruised": 3, "cut": 6, "pierced": 6, "torn": 9, "fractured": 6, "broken": 9, "mangled": 14, "destroyed": 21},
	"muscle": {"bruised": 5, "cut": 12, "pierced": 14, "torn": 24, "fractured": 24, "broken": 24, "mangled": 40, "destroyed": 60},
	"bone":   {"bruised": 7, "cut": 20, "pierced": 20, "torn": 30, "fractured": 35, "broken": 56, "mangled": 80, "destroyed": 100},
	"organ":  {"bruised": 8, "cut": 20, "pierced": 24, "torn": 28, "fractured": 28, "broken": 28, "mangled": 50, "destroyed": 14},
	"brain":  {"bruised": 10, "cut": 30, "pierced": 35, "torn": 35, "fractured": 35, "broken": 35, "mangled": 60, "destroyed": 60},
}
const STUMP_DAYS := 21.0        # a severed limb's stump closing over
const FIELD_RATE := 0.75        # healing speed on the road / in camp (town rest = 1.0)
const TOWN_RATE := 1.0
const TREATED_BASE := 1.2       # treated wounds heal x(1.2 + 0.04 * healer skill)
const TREATED_PER_SKILL := 0.04
const CAMP_HEALER_PER_SKILL := 0.02   # heal(..., healer_skill): a company surgeon on the road
const BLOOD_REGEN := 0.25       # fraction of blood_max regained per day of town rest
const INTERNAL_BLEED_PER_DAY := 150.0  # blood lost per day per unit of (organ) bleed left after bandaging
## Pain thresholds in body.pain units (the sim owns pain gain), from the DF survey: stun 50, knockdown 100, KO 150.
const PAIN_SOME := 20.0
const PAIN_PAIN := 50.0     # DF: stun
const PAIN_AGONY := 100.0   # DF: knockdown
const PAIN_KO := 150.0      # DF: unconscious
## Blood thresholds as fractions of blood_max left (DF: weak at 15% lost, collapse at 30%, dead at 40-50%).
const BLOOD_WEAK := 0.85
const BLOOD_COLLAPSE := 0.70
const BLOOD_DEAD := 0.50
## DF pain receptors by tissue (skin/fat/muscle 5, bone 50; organs ours), x1 bruise, x2 partial, x3 broken.
## Resting (out-of-battle) pain from open wounds = receptors * kind mult * dmg * RESTING_PAIN.
const TISSUE_PAIN := {"skin": 5.0, "fat": 5.0, "muscle": 5.0, "bone": 50.0, "organ": 10.0, "brain": 0.0}
const KIND_PAIN := {"bruised": 1.0, "cut": 2.0, "pierced": 2.0, "torn": 2.0, "fractured": 2.0, "broken": 3.0, "mangled": 3.0, "destroyed": 3.0}
const RESTING_PAIN := 0.5

# ------------------------------------------------------------------ timers

static func rec_mult(unit: Unit) -> float:
	var rec := maxf(100.0, float(unit.attr("REC")))
	return clampf(pow(1000.0 / rec, 0.6), 0.5, 2.0)

## Days of town rest this wound needs from scratch (pure; does not read the stored timer).
static func wound_days(unit: Unit, layer: Dictionary) -> float:
	var kind: String = layer.get("kind", "")
	var dmg: float = layer.get("dmg", 0.0)
	if dmg <= 0.0 and kind == "":
		return 0.0
	if kind == "":
		kind = "bruised" if dmg < 0.3 else "torn"
	var tissue: String = layer.get("tissue", "skin")
	var table: Dictionary = BASE_DAYS.get(tissue, BASE_DAYS["muscle"])
	var base: float = float(table.get(kind, 10))
	return base * lerpf(0.6, 1.4, clampf(dmg, 0.0, 1.0)) * rec_mult(unit)

## Layers that will never heal back as soon as they are assessed.
static func is_permanent_wound(part_id: String, layer: Dictionary, body: BodyState) -> bool:
	if layer.get("kind", "") != "destroyed":
		return false
	var fns: Array = layer.get("functions", [])
	if fns.is_empty():
		fns = _layer_functions(body, part_id, layer)
	return "sight" in fns or "breathe" in fns or layer.get("tissue", "") == "brain"

static func _layer_functions(body: BodyState, part_id: String, layer: Dictionary) -> Array:
	var pd := body.part_def(part_id)
	for l in pd.get("layers", []):
		if l.get("tissue", "") == layer.get("tissue", "") and l.get("name", l.get("tissue", "")) == layer.get("name", ""):
			return l.get("functions", [])
	return []

## Sets each damaged layer's heal_days. Idempotent; never shortens a timer. Re-assesses a layer only
## when it took new damage (dmg or kind above what the timer was computed for).
static func update_heal_days(unit: Unit) -> void:
	var body := unit.body
	for pid in body.parts:
		var part: Dictionary = body.parts[pid]
		if body.is_lost(pid):
			_assess_lost(unit, pid)
			continue
		# v0.013 (DF): severed nerves do not regrow. Motor: the part hangs limp for good; sensory: it is numb.
		if part.get("nerve_m", false) and not part.get("nerve_assessed", false):
			part["nerve_assessed"] = true
			_set_impair(body, pid, 1.0)
			_add_permanent(body, "%s motor nerve severed - limp" % part_name(body, pid))
			if part.get("nerve_s", false):
				_add_permanent(body, "%s numb" % part_name(body, pid))
		var layers: Array = part["layers"]
		for li in layers.size():
			var l: Dictionary = layers[li]
			var dmg: float = l.get("dmg", 0.0)
			var kind: String = l.get("kind", "")
			if dmg <= 0.0 and kind == "":
				continue
			var rank: int = KIND_RANK.get(kind, 1)
			var fresh: bool = dmg > float(l.get("heal_dmg", 0.0)) + 0.001 or rank > int(l.get("heal_rank", 0)) \
				or (float(l.get("heal_days", 0.0)) <= 0.0 and not l.get("permanent", false))
			if not fresh:
				continue
			var d := wound_days(unit, l)
			l["heal_days"] = maxf(float(l.get("heal_days", 0.0)), d)
			l["heal_total"] = maxf(float(l.get("heal_total", 0.0)), l["heal_days"])
			l["heal_dmg"] = dmg
			l["heal_rank"] = rank
			if is_permanent_wound(pid, l, body) and not l.get("permanent", false):
				l["permanent"] = true
				_set_impair(body, pid, 1.0 if l.get("name", "") == "eye" else 0.5)
				var pname := part_name(body, pid)
				var what: String = l.get("name", l["tissue"])
				var s := "%s destroyed" % pname if what == "eye" else "%s destroyed" % what
				if "breathe" in _layer_functions(body, pid, l):
					s = "%s destroyed - short of breath" % what
				_add_permanent(body, s)
			# v0.013: the spinal cord cut does not mend (DF nervous tissue): paralysed below it
			if "cord" in _layer_functions(body, pid, l) and dmg >= Formulas.NERVE_DISABLE and not l.get("permanent", false):
				l["permanent"] = true
				_add_permanent(body, "%s cut - paralysed below it" % part_name(body, pid))

static func _assess_lost(unit: Unit, pid: String) -> void:
	var body := unit.body
	var part: Dictionary = body.parts[pid]
	var layers: Array = part["layers"]
	if not part.get("severed", false) or body.is_lost(body.part_def(pid).get("parent", "")):
		# lost with an ancestor: nothing left to heal here
		for l in layers:
			l["heal_days"] = 0.0
			l["bleed"] = 0.0
		return
	part["impair"] = 1.0
	if not part.get("stump_assessed", false):
		part["stump_assessed"] = true
		for li in layers.size():
			var l: Dictionary = layers[li]
			l["heal_days"] = STUMP_DAYS * rec_mult(unit) if li == 0 else 0.0
			l["heal_total"] = l["heal_days"]
			l["permanent"] = true
		_add_permanent(body, "%s lost" % part_name(body, pid))

# ------------------------------------------------------------------ battle aftermath

## Bandaging after a battle: stops external bleeding, slows internal bleeding, assesses timers.
static func after_battle(unit: Unit) -> void:
	if unit.dead:
		return
	_bandage(unit, 0.25)
	update_heal_days(unit)

static func _bandage(unit: Unit, internal_keep: float) -> void:
	for pid in unit.body.parts:
		for l in unit.body.parts[pid]["layers"]:
			if l.get("bleed", 0.0) <= 0.0:
				continue
			if l.get("tissue", "") in ["organ", "brain"]:
				l["bleed"] = l["bleed"] * internal_keep
			else:
				l["bleed"] = 0.0

# ------------------------------------------------------------------ healing over time

## Advances recovery by `days`. Town rest is faster than the road; treated wounds and a company
## healer (healer_skill) speed it further. Permanent losses stay. Deterministic.
static func heal(unit: Unit, days: float, in_town: bool, healer_skill: int = 0) -> void:
	if unit.dead or days <= 0.0:
		return
	var body := unit.body
	_bandage(unit, 1.0)
	update_heal_days(unit)
	var rate := (TOWN_RATE if in_town else FIELD_RATE) * (1.0 + CAMP_HEALER_PER_SKILL * maxi(healer_skill, 0))
	# internal bleeding: slows on its own, costs blood meanwhile
	var internal := 0.0
	for pid in body.parts:
		for l in body.parts[pid]["layers"]:
			if l.get("bleed", 0.0) > 0.0:
				var b0: float = l["bleed"]
				var b1 := b0 * exp(-3.0 * days)
				internal += (b0 - b1) / 3.0
				l["bleed"] = b1 if b1 > 0.0005 else 0.0
	body.blood = maxf(body.blood - internal * INTERNAL_BLEED_PER_DAY, minf(body.blood, body.blood_max * (BLOOD_COLLAPSE + 0.02)))
	for pid in body.parts:
		var part: Dictionary = body.parts[pid]
		var layers: Array = part["layers"]
		for li in layers.size():
			var l: Dictionary = layers[li]
			var hd: float = l.get("heal_days", 0.0)
			if hd <= 0.0:
				continue
			var r := rate
			var t: int = int(l.get("treated", 0))
			if t > 0 or l.has("treated"):
				r *= TREATED_BASE + TREATED_PER_SKILL * t
			var nd := maxf(0.0, hd - days * r)
			if l.get("permanent", false):
				l["heal_days"] = nd
				if nd <= 0.0:
					l["bleed"] = 0.0
				continue
			l["dmg"] = float(l.get("dmg", 0.0)) * (nd / hd)
			l["heal_dmg"] = l["dmg"]
			l["heal_days"] = nd
			if nd <= 0.0:
				_finish_wound(unit, pid, li, l)
	# blood, pain, fatigue
	var per_day := BLOOD_REGEN * (TOWN_RATE if in_town else FIELD_RATE) / rec_mult(unit)
	body.blood = minf(body.blood_max, body.blood + body.blood_max * per_day * days)
	body.pain = body.pain * exp(-1.5 * days)
	if body.pain < 0.5:
		body.pain = 0.0
	body.exertion = body.exertion * exp(-4.0 * days)
	if body.exertion < 0.5:
		body.exertion = 0.0
	body.compact()   # v0.013 sparse body: parts that healed clean are no longer stored

## A wound closed. Bad wounds left untreated may heal into a lasting impairment (deterministic roll).
static func _finish_wound(unit: Unit, pid: String, li: int, l: Dictionary) -> void:
	var body := unit.body
	var kind: String = l.get("kind", "")
	var tissue: String = l.get("tissue", "")
	var lname: String = l.get("name", tissue)
	var treated := int(l.get("treated", -1))
	var p := 0.0
	var impair := 0.0
	var what := ""
	match tissue:
		"bone":
			match kind:
				"fractured": p = 0.15; impair = 0.15
				"broken": p = 0.45; impair = 0.3
				"mangled": p = 0.85; impair = 0.5
				"destroyed": p = 1.0; impair = 0.7
			what = "%s badly mended" % ("bone" if lname == "bone" else lname)
		"muscle":
			match kind:
				"torn": p = 0.15 if float(l.get("heal_total", 0.0)) > 30.0 else 0.0; impair = 0.1
				"mangled": p = 0.5; impair = 0.25
				"destroyed": p = 1.0; impair = 0.5
			what = "muscle scarred"
		"organ":
			match kind:
				"mangled", "destroyed": p = 0.5; impair = 0.3
			what = "%s scarred" % lname
		"brain":
			if KIND_RANK.get(kind, 0) >= 3:
				p = 0.5; impair = 0.3
			what = "brain damaged"
	if treated >= 0 and p < 1.0:
		p *= maxf(0.1, 0.5 - 0.03 * treated)   # a set bone / stitched muscle rarely goes wrong
	var roll := _roll(unit, pid, li, l)
	l["dmg"] = 0.0
	l["kind"] = ""
	l["bleed"] = 0.0
	if body.parts.has(pid):   # v0.013: a mended lung is no longer punctured; mended guts are back inside
		body.parts[pid].erase("punct")
		body.parts[pid].erase("spilled")
	for k in ["heal_total", "heal_dmg", "heal_rank", "treated"]:
		l.erase(k)
	if p > 0.0 and roll < p:
		_set_impair(body, pid, impair)
		var s := "%s %s" % [part_name(body, pid), what]
		var effect := _effect_word(body, pid, lname)
		if effect != "":
			s += " - " + effect
		_add_permanent(body, s)

static func _effect_word(body: BodyState, pid: String, lname: String) -> String:
	if lname == "brain":
		return "slow-witted"
	if lname == "eye":
		return "poor sight"
	if lname == "lung" or "breathe" in _layer_functions(body, pid, {"tissue": "organ", "name": lname}):
		return "short of breath"
	var fns: Array = body.part_def(pid).get("functions", [])
	if "stance" in fns:
		return "limps"
	if "grasp" in fns:
		return "weak grip"
	if pid.begins_with("arm"):
		return "weak arm"
	return "stiff"

static func _roll(unit: Unit, pid: String, li: int, l: Dictionary) -> float:
	var h: int = hash([unit.uid, pid, li, int(round(float(l.get("heal_total", 0.0)) * 100.0)), l.get("kind", "")])
	return float(absi(h) % 10007) / 10007.0

static func _set_impair(body: BodyState, pid: String, v: float) -> void:
	var part: Dictionary = body.wound_part(pid)
	part["impair"] = maxf(float(part.get("impair", 0.0)), v)

static func _add_permanent(body: BodyState, s: String) -> void:
	if not (s in body.permanent):
		body.permanent.append(s)

static func part_name(body: BodyState, pid: String) -> String:
	return body.part_def(pid).get("name", pid)

# ------------------------------------------------------------------ town healer

## Gold for a town healer to treat every untreated (or worse-treated) wound. 0 = nothing to treat.
static func treatment_cost(unit: Unit, healer_skill: int) -> int:
	if unit.dead:
		return 0
	update_heal_days(unit)
	var days := 0.0
	var serious := 0
	for pid in unit.body.parts:
		if unit.body.is_lost(pid) and not unit.body.parts[pid].get("severed", false):
			continue
		for l in unit.body.parts[pid]["layers"]:
			if float(l.get("heal_days", 0.0)) <= 0.0 or int(l.get("treated", -1)) >= healer_skill:
				continue
			days += float(l["heal_days"])
			if KIND_RANK.get(l.get("kind", ""), 0) >= 4 or l.get("bleed", 0.0) > 0.0:
				serious += 1
	if days <= 0.0:
		return 0
	return maxi(5 * Item.COIN, int(round((days * 0.4 + serious * 5.0) * (0.5 + 0.1 * maxi(healer_skill, 0)) * Item.COIN)))   # coins

## A town healer treats the unit: stops all bleeding, sets bones, stitches wounds. Treated wounds heal
## faster and rarely leave lasting damage. Payment is the caller's job (treatment_cost).
static func treat(unit: Unit, healer_skill: int) -> void:
	Game.invalidate_deploy()
	if unit.dead:
		return
	update_heal_days(unit)
	for pid in unit.body.parts:
		for l in unit.body.parts[pid]["layers"]:
			l["bleed"] = 0.0
			if float(l.get("heal_days", 0.0)) > 0.0:
				l["treated"] = maxi(int(l.get("treated", -1)), maxi(healer_skill, 0))

# ------------------------------------------------------------------ fitness

static func wound_pain(unit: Unit) -> float:
	var p := 0.0
	for pid in unit.body.parts:
		if unit.body.is_lost(pid) or unit.body.parts[pid].get("nerve_s", false):   # numb: no pain from it (DF)
			continue
		for l in unit.body.parts[pid]["layers"]:
			if l.get("permanent", false) and float(l.get("heal_days", 0.0)) <= 0.0:
				continue
			p += float(l.get("dmg", 0.0)) * float(TISSUE_PAIN.get(l.get("tissue", ""), 5.0)) * float(KIND_PAIN.get(l.get("kind", ""), 1.0))
	return p * RESTING_PAIN

static func is_fit(unit: Unit) -> bool:
	var t := fitness_text(unit)
	return t == "fit to fight" or t == "fights hurt"

## "fit to fight" | "fights hurt" | "should rest" | "cannot fight"
static func fitness_text(unit: Unit) -> String:
	if unit.dead:
		return "cannot fight"
	return HealthReport.describe(unit)["fitness"]

## Fitness from an already-built HealthReport (HealthReport.describe calls this).
static func fitness_from_report(r: Dictionary) -> String:
	var f: Dictionary = r["flags"]
	if r["status"] == "dead" or r["status"] == "unconscious" or f["no_grasp"] or f["no_stance"] or f["blind"] or f["blood"] < BLOOD_COLLAPSE:
		return "cannot fight"
	var worst := 0
	var hurt := false
	for p in r["parts"]:
		if p["heal_days"] > 0.0:
			worst = maxi(worst, p["severity"])
			hurt = true
	if worst >= 3:
		return "cannot fight"
	if worst >= 2 or f["blood"] < BLOOD_WEAK or f["bleeding"] > 0.0:
		return "should rest"
	if hurt or f["impaired"] or f["blood"] < 0.97:
		return "fights hurt"
	return "fit to fight"
