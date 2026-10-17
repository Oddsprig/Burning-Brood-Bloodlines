class_name HealthReport
extends RefCounted
## DF-style health screen text. No HP. Read-only: never mutates the unit.
##
## describe(unit) -> {
##   "parts": [ {"part": "arm_upper_l", "name": "left upper arm",
##               "lines": ["bone fractured", "muscle torn", "bleeding"],
##               "severity": 0..3 (0 scratch, 1 minor, 2 serious, 3 critical/lost),
##               "heal_days": float, "permanent": bool,
##               # additive extras:
##               "text": "Left upper arm: bone fractured, muscle torn - bleeding",
##               "severity_word": "serious", "recovery": "6 weeks"}, ... ]   (only wounded parts)
##   "summary": ["has lost a lot of blood", "in agony", "standing", "left eye destroyed - permanent"],
##   "status": "healthy" | "wounded" | "badly wounded" | "unconscious" | "dead",
##   "heal_days": float,
##   # additive extras:
##   "fitness": "fit to fight" | "fights hurt" | "should rest" | "cannot fight",
##   "recovery": "3 weeks",
##   "flags": {"blood": ratio 0..1, "bleeding": total bleed, "pain": float, "no_grasp", "no_stance",
##             "blind", "impaired": bool (lasting damage), "limping", "unconscious"}
## }
## Parts are sorted worst first. heal_days on a part is days of town rest (see sim/healing.gd); a wound
## the healer has not assessed yet (fresh from battle) shows an estimate.
## Optional unit metas the battle inspector may set: "prone" (bool), "unconscious" (bool).

const SEVERITY_WORDS := ["scratch", "minor", "serious", "critical"]
const HEAVY_BLEED := 0.05

static func describe(unit: Unit) -> Dictionary:
	var body := unit.body
	var parts_out := []
	var plan_order := 0
	for pd in body.plan()["parts"]:
		plan_order += 1
		var pid: String = pd["id"]
		if not body.parts.has(pid):
			continue
		var e := _describe_part(unit, pid)
		if e.is_empty():
			continue
		e["_order"] = plan_order
		parts_out.append(e)
	parts_out.sort_custom(func(a, b):
		if a["severity"] != b["severity"]:
			return a["severity"] > b["severity"]
		return a["_order"] < b["_order"])
	for e in parts_out:
		e.erase("_order")

	var flags := _flags(unit)
	var summary := _summary(unit, flags)

	var heal_days := 0.0
	var open_worst := 0
	var open_any := false
	for e in parts_out:
		heal_days = maxf(heal_days, e["heal_days"])
		if e["heal_days"] > 0.0:
			open_any = true
			open_worst = maxi(open_worst, e["severity"])
	if flags["blood"] < 1.0:
		var per_day := Healing.BLOOD_REGEN / Healing.rec_mult(unit)
		heal_days = maxf(heal_days, (1.0 - flags["blood"]) / per_day)

	var status := "healthy"
	if unit.dead:
		status = "dead"
	elif flags["unconscious"]:
		status = "unconscious"
	elif open_worst >= 3 or flags["blood"] < 0.75 or flags["bleeding"] >= HEAVY_BLEED:
		status = "badly wounded"
	elif open_any or flags["blood"] < 0.97 or flags["bleeding"] > 0.0:
		status = "wounded"
	var r := {"parts": parts_out, "summary": summary, "status": status, "heal_days": heal_days,
		"flags": flags, "recovery": format_days(heal_days)}
	r["fitness"] = Healing.fitness_from_report(r)
	return r

## Whole screen as plain text (debug / tests / a simple label).
static func to_text(unit: Unit) -> String:
	var r := describe(unit)
	var out := ["%s - %s, %s" % [unit.display_name() if unit.display_name() != "" else "unit %d" % unit.uid, r["status"], r["fitness"]]]
	for s in r["summary"]:
		out.append("  " + s)
	for e in r["parts"]:
		var tail: String = "permanent" if e["permanent"] and e["heal_days"] <= 0.0 else e["recovery"]
		out.append("  %s   [%s, %s]" % [e["text"], e["severity_word"], tail])
	if r["heal_days"] > 0.0:
		out.append("  full recovery: %s of town rest" % r["recovery"])
	return "\n".join(out)

static func format_days(d: float) -> String:
	if d <= 0.0:
		return "healed"
	if d < 1.0:
		return "under a day"
	if d < 14.0:
		var n := int(ceil(d))
		return "%d day%s" % [n, "" if n == 1 else "s"]
	if d < 60.0:
		return "%d weeks" % int(round(d / 7.0))
	var m := int(round(d / 30.0))
	return "%d month%s" % [m, "" if m == 1 else "s"]

# ------------------------------------------------------------------ parts

static func _describe_part(unit: Unit, pid: String) -> Dictionary:
	var body := unit.body
	var part: Dictionary = body.parts[pid]
	var pname: String = Healing.part_name(body, pid)
	if body.is_lost(body.part_def(pid).get("parent", "")):
		return {}   # gone with a severed ancestor; the ancestor's entry covers it
	var bleed := 0.0
	for l in part["layers"]:
		bleed += float(l.get("bleed", 0.0))
	var lines := []
	var severity := 0
	var heal_days := 0.0
	var permanent := false
	if part.get("severed", false):
		lines.append("knocked out" if part.get("knocked", false) else "severed")
		severity = 1 if part.get("knocked", false) else 3   # a lost tooth is nothing more (DF)
		permanent = true
		if part.get("stump_assessed", false):
			heal_days = float(part["layers"][0].get("heal_days", 0.0)) if not part["layers"].is_empty() else 0.0
		else:
			heal_days = Healing.STUMP_DAYS * Healing.rec_mult(unit)
	else:
		var items := []   # [rank, depth, phrase, severity]
		var only_fat := []
		var depth := 0
		var single: bool = part["layers"].size() == 1
		for l in part["layers"]:
			depth += 1
			var dmg: float = l.get("dmg", 0.0)
			var kind: String = l.get("kind", "")
			var stored: float = l.get("heal_days", 0.0)
			var perm: bool = l.get("permanent", false) or (kind == "destroyed" and Healing.is_permanent_wound(pid, l, body))
			if dmg <= 0.0 and kind == "":
				continue
			if kind == "":
				kind = "bruised" if dmg < 0.3 else "torn"
			var hd := stored
			if stored <= 0.0 and not l.get("permanent", false):
				hd = Healing.wound_days(unit, l)
			heal_days = maxf(heal_days, hd)
			if perm:
				permanent = true
			var sev := _layer_severity(l, kind, dmg)
			var phrase := _phrase(pid, l, kind, single)
			var total: float = l.get("heal_total", 0.0)
			if not perm and total > 0.0 and stored > 0.0 and stored < total * 0.5:
				phrase += " (mending)"
				sev = maxi(0, sev - 1)
			if perm:
				sev = 3
			if l.get("tissue", "") == "fat":
				only_fat.append([kind_rank(kind), depth, phrase, sev])
			else:
				items.append([kind_rank(kind), depth, phrase, sev])
		# v0.013 marks: severed nerves (DF HAS_NERVES; they do not regrow), a punctured lung
		if part.get("nerve_m", false):
			items.append([7, 99, "motor nerve severed - limp", 3])
			permanent = true
		if part.get("nerve_s", false):
			items.append([6, 98, "sensory nerve severed - numb", 2])
			permanent = true
		if part.get("punct", false):
			items.append([5, 97, "punctured", 3])
		if items.is_empty():
			items = only_fat
		else:
			for f in only_fat:
				severity = maxi(severity, f[3])
		if items.is_empty() and bleed <= 0.0:
			return {}
		items.sort_custom(func(a, b):   # worst first: severity, then wound kind, then deeper layer
			if a[3] != b[3]:
				return a[3] > b[3]
			if a[0] != b[0]:
				return a[0] > b[0]
			return a[1] > b[1])
		for it in items:
			lines.append(it[2])
			severity = maxi(severity, it[3])
	if bleed >= HEAVY_BLEED:
		lines.append("heavy bleeding")
		severity = 3
	elif bleed > 0.0:
		lines.append("bleeding")
		severity = maxi(severity, 2 if bleed >= 0.01 else 1)
	var text := "%s: %s" % [_cap(pname), ", ".join(lines.filter(func(s): return not s.ends_with("bleeding")))]
	if lines.size() > 0 and lines[-1].ends_with("bleeding"):
		text += (" - " if lines.size() > 1 else "") + lines[-1]
	return {"part": pid, "name": pname, "lines": lines, "severity": severity, "heal_days": heal_days,
		"permanent": permanent, "text": text, "severity_word": SEVERITY_WORDS[severity],
		"recovery": "permanent" if permanent and heal_days <= 0.0 else format_days(heal_days)}

static func kind_rank(kind: String) -> int:
	return int(Healing.KIND_RANK.get(kind, 1))

static func _layer_severity(l: Dictionary, kind: String, dmg: float) -> int:
	var rank := kind_rank(kind)
	var tissue: String = l.get("tissue", "")
	if rank >= 6:
		return 3
	if (tissue == "organ" or tissue == "brain") and rank >= 3 and dmg >= 0.5:
		return 3
	if tissue == "organ" or tissue == "brain":
		return 2
	if tissue == "bone" and rank >= 4:
		return 2
	# throat artery: any opening is life-threatening
	if tissue == "vessel" and rank >= 2:
		return 3
	if tissue == "vessel":
		return 2
	# a cut tendon or nerve disables the limb's grip/stance/motion until mended
	if (tissue == "tendon" or tissue == "nerve") and rank >= 2:
		return 2
	if tissue == "muscle" and rank >= 3 and dmg >= 0.4:
		return 2
	if rank >= 2 or tissue == "muscle" or tissue == "bone":
		return 1
	return 0

## "scalp cut", "skull fractured", "heart pierced", "ribs broken", "bone shattered".
static func _phrase(pid: String, l: Dictionary, kind: String, single: bool) -> String:
	var tissue: String = l.get("tissue", "")
	var lname: String = l.get("name", tissue)
	var noun := lname
	var verb := kind
	match tissue:
		"skin":
			noun = "scalp" if pid == "head" else "skin"
			verb = {"pierced": "punctured", "fractured": "split", "broken": "torn", "destroyed": "flayed"}.get(kind, kind)
		"fat":
			noun = "fat"
			verb = {"fractured": "torn", "broken": "torn", "destroyed": "torn away"}.get(kind, kind)
		"muscle":
			noun = "muscle"
			verb = {"fractured": "torn", "broken": "torn", "destroyed": "torn apart"}.get(kind, kind)
		"bone":
			noun = "bone" if lname == "bone" or lname == "" else lname
			verb = {"cut": "chipped", "pierced": "chipped", "torn": "cracked", "mangled": "shattered", "destroyed": "smashed"}.get(kind, kind)
		"organ":
			verb = {"fractured": "torn", "broken": "ruptured"}.get(kind, kind)
			if lname == "guts":
				verb = {"cut": "cut open", "torn": "torn open", "mangled": "spilled"}.get(kind, verb)
			elif lname == "airway":
				noun = "windpipe"
				verb = {"cut": "slit", "pierced": "punctured", "torn": "torn", "fractured": "crushed", "broken": "crushed",
					"mangled": "crushed", "destroyed": "torn out"}.get(kind, verb)
		"tendon":
			noun = "tendon"
			verb = {"cut": "severed", "pierced": "nicked", "torn": "torn", "fractured": "torn", "broken": "ruptured",
				"mangled": "shredded", "destroyed": "severed"}.get(kind, kind)
		"nerve":
			noun = "nerve" if lname == "" or lname == "nerve" else lname
			verb = {"bruised": "bruised", "cut": "severed", "pierced": "nicked", "torn": "torn", "fractured": "crushed",
				"broken": "crushed", "mangled": "crushed", "destroyed": "severed"}.get(kind, kind)
		"vessel":
			noun = lname if lname != "" and lname != "vessel" else "artery"
			verb = {"bruised": "bruised", "cut": "opened", "pierced": "pierced", "torn": "torn open", "fractured": "torn open",
				"broken": "torn open", "mangled": "torn apart", "destroyed": "severed"}.get(kind, kind)
		"brain":
			verb = {"fractured": "torn", "broken": "torn", "mangled": "crushed"}.get(kind, kind)
	if single:
		return verb
	return "%s %s" % [noun, verb]

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

# ------------------------------------------------------------------ functions / summary

## A part does its job right now (not lost, not crippled by an open wound or lasting damage).
static func _part_usable(body: BodyState, pid: String) -> bool:
	if body.is_lost(pid):
		return false
	var part: Dictionary = body.parts.get(pid, {})
	if float(part.get("impair", 0.0)) >= 0.8 or part.get("nerve_m", false):
		return false
	for l in part.get("layers", []):
		var rank := kind_rank(l.get("kind", "")) if l.get("kind", "") != "" else 0
		var tissue: String = l.get("tissue", "")
		if tissue == "bone" and rank >= 5:
			return false
		if tissue == "muscle" and rank >= 6:
			return false
		if float(l.get("dmg", 0.0)) >= 0.9 and not l.get("permanent", false):
			return false
	return true

static func _part_hampered(body: BodyState, pid: String) -> bool:
	var part: Dictionary = body.parts.get(pid, {})
	if float(part.get("impair", 0.0)) >= 0.1:
		return true
	for l in part.get("layers", []):
		var rank := kind_rank(l.get("kind", "")) if l.get("kind", "") != "" else 0
		var tissue: String = l.get("tissue", "")
		if tissue == "bone" and rank >= 4:
			return true
		if tissue == "muscle" and rank >= 3 and float(l.get("dmg", 0.0)) >= 0.4:
			return true
	return false

## The part and its severable ancestors (hand -> lower arm -> upper arm).
static func _chain(body: BodyState, pid: String) -> Array:
	var out := [pid]
	var id: String = body.part_def(pid).get("parent", "")
	var guard := 0
	while id != "" and body.part_def(id).get("severable", false) and guard < 8:
		out.append(id)
		id = body.part_def(id).get("parent", "")
		guard += 1
	return out

static func _parts_with(body: BodyState, fn: String) -> Array:
	var out := []
	for pd in body.plan()["parts"]:
		if fn in pd.get("functions", []):
			out.append(pd["id"])
	return out

## Leaves of a function: parts with the function whose children don't have it (feet, hands).
static func _leaves(body: BodyState, fn: String) -> Array:
	var all := _parts_with(body, fn)
	var out := []
	for pid in all:
		var has_child := false
		for other in all:
			if body.part_def(other).get("parent", "") == pid:
				has_child = true
		if not has_child:
			out.append(pid)
	return out

static func _side(pid: String) -> String:
	if pid.ends_with("_l"):
		return "left"
	if pid.ends_with("_r"):
		return "right"
	return ""

static func _flags(unit: Unit) -> Dictionary:
	var body := unit.body
	var f := {}
	f["blood"] = clampf(body.blood / maxf(body.blood_max, 0.001), 0.0, 1.0)
	f["bleeding"] = body.total_bleed()
	var wil := 1.0   # pain thresholds are already in sim units (no WIL scaling here)
	f["pain_mult"] = wil
	f["pain"] = maxf(body.pain, minf(Healing.wound_pain(unit), Healing.PAIN_KO * 0.95 * wil))
	f["unconscious"] = not unit.dead and (body.pain >= Healing.PAIN_KO * wil or (f["blood"] < Healing.BLOOD_COLLAPSE)
		or unit.get_meta("unconscious", false))
	# stance: legs (chains above each stance leaf), plus the lower spine
	var legs_ok := 0
	var limping := false
	var leaves := _leaves(body, "stance")
	for leaf in leaves:
		var ok := true
		for pid in _chain(body, leaf):
			if not _part_usable(body, pid):
				ok = false
			elif _part_hampered(body, pid):
				limping = true
		if ok:
			legs_ok += 1
	var spine_ok := true
	var arms_spine := false
	for pid in body.parts:
		if body.is_lost(pid):
			continue
		for l in body.parts[pid]["layers"]:
			if l.get("tissue", "") == "bone" and l.get("name", "") == "spine" and pid != "neck" \
					and kind_rank(l.get("kind", "")) >= 5 and l.get("kind", "") != "":
				spine_ok = false   # (saves from before v0.013)
			if l.get("name", "") == "spinal cord" and float(l.get("dmg", 0.0)) >= Formulas.NERVE_DISABLE:
				spine_ok = false   # v0.013: the cord cut: paralysed below it
				if String(body.part_def(pid).get("spine", "")) == "upper":
					arms_spine = true
	f["no_stance"] = legs_ok < leaves.size() or not spine_ok
	f["limping"] = limping
	# grasp
	var hands := _leaves(body, "grasp")
	var hands_ok := []
	var hands_bad := []
	var hands_weak := []
	for h in hands:
		var ok := not arms_spine
		var weak := false
		for pid in _chain(body, h):
			if not _part_usable(body, pid):
				ok = false
			elif _part_hampered(body, pid):
				weak = true
		# v0.013 fingers: none left that close = no grip; some gone = a weak grip
		var fw := 0.0
		var fok := 0.0
		for fid in body.defs():
			var fd: Dictionary = body.defs()[fid]
			if String(fd.get("parent", "")) == h and fd.has("digit"):
				fw += float(fd.get("relsize", 0))
				if _part_usable(body, fid):
					fok += float(fd.get("relsize", 0))
		if fw > 0.0 and fok <= 0.0:
			ok = false
		elif fok < fw:
			weak = true
		if ok:
			hands_ok.append(h)
			if weak:
				hands_weak.append(h)
		else:
			hands_bad.append(h)
	f["no_grasp"] = hands_ok.is_empty() and not hands.is_empty()
	f["hands_bad"] = hands_bad
	f["hands_weak"] = hands_weak
	# sight
	var eyes := []
	for pd in body.plan()["parts"]:
		for l in pd.get("layers", []):
			if "sight" in l.get("functions", []):
				eyes.append(pd["id"])
	var eyes_bad := []
	for e in eyes:
		var ok := not body.is_lost(e) and float(body.part(e).get("impair", 0.0)) < 0.8
		for l in body.layers_of(e):
			if l.get("kind", "") == "destroyed" or float(l.get("dmg", 0.0)) >= 0.6:
				ok = false
		if not ok:
			eyes_bad.append(e)
	f["blind"] = not eyes.is_empty() and eyes_bad.size() == eyes.size()
	f["eyes_bad"] = eyes_bad
	# breathing
	var breath := ""
	for pid in body.parts:
		if body.is_lost(pid):
			continue
		var lung: bool = body.part_def(pid).get("internal", false) and not body.part_def(pid).get("layers", []).is_empty() \
			and "breathe" in body.part_def(pid)["layers"][0].get("functions", [])
		for l in body.parts[pid]["layers"]:
			if l.get("name", "") == "lung" or lung:
				if l.get("kind", "") == "destroyed" or float(body.parts[pid].get("impair", 0.0)) >= 0.5 or body.parts[pid].get("punct", false):
					breath = "struggling to breathe" if float(l.get("heal_days", 1.0)) > 0.0 else "short of breath"
				elif float(l.get("dmg", 0.0)) >= 0.4 or float(body.parts[pid].get("impair", 0.0)) > 0.0:
					breath = "short of breath"
	f["breath"] = breath
	var impaired := not body.permanent.is_empty()
	for pid in body.parts:
		if float(body.parts[pid].get("impair", 0.0)) > 0.0:
			impaired = true
	f["impaired"] = impaired
	return f

static func _summary(unit: Unit, f: Dictionary) -> Array:
	var body := unit.body
	var s := []
	if unit.dead:
		s.append("dead")
	var r: float = f["blood"]
	if r <= Healing.BLOOD_DEAD:
		s.append("has bled out")
	elif r < 0.75:
		s.append("has lost a lot of blood")
	elif r < Healing.BLOOD_WEAK:
		s.append("is pale")
	if f["bleeding"] >= HEAVY_BLEED:
		s.append("bleeding heavily")
	elif f["bleeding"] > 0.0:
		s.append("bleeding")
	if not unit.dead:
		var wil: float = f["pain_mult"]
		var p: float = f["pain"] / wil
		if body.pain >= Healing.PAIN_KO * wil:
			s.append("unconscious from pain")
		elif r < Healing.BLOOD_COLLAPSE:
			s.append("unconscious from blood loss")
		elif p >= Healing.PAIN_AGONY:
			s.append("in agony")
		elif p >= Healing.PAIN_PAIN:
			s.append("in pain")
		elif p >= Healing.PAIN_SOME:
			s.append("in some pain")
		if f["unconscious"] or unit.get_meta("prone", false):
			s.append("prone" if not f["no_stance"] else "prone, unable to stand")
		elif f["no_stance"]:
			s.append("unable to stand")
		else:
			s.append("standing, limping" if f["limping"] else "standing")
		if f["no_grasp"]:
			s.append("cannot hold a weapon")
		else:
			for h in f["hands_bad"]:
				s.append("cannot use the %s hand" % _side(h) if _side(h) != "" else "cannot use %s" % Healing.part_name(body, h))
			for h in f["hands_weak"]:
				s.append("weak grip (%s)" % Healing.part_name(body, h))
		if f["blind"]:
			s.append("blind")
		else:
			for e in f["eyes_bad"]:
				s.append("blind in the %s" % Healing.part_name(body, e))
		if f["breath"] != "":
			s.append(f["breath"])
	# permanent losses: recorded ones, plus fresh ones the healer has not assessed yet
	var perm: Array = body.permanent.duplicate()
	for pid in body.parts:
		var pname := Healing.part_name(body, pid)
		if body.parts[pid].get("severed", false) and not body.is_lost(body.part_def(pid).get("parent", "")):
			if not ("%s lost" % pname in perm):
				perm.append("%s lost" % pname)
		elif not body.is_lost(pid):
			for l in body.parts[pid]["layers"]:
				if l.get("name", "") == "eye" and l.get("kind", "") == "destroyed" and not ("%s destroyed" % pname in perm):
					perm.append("%s destroyed" % pname)
	for p in perm:
		var t: String = p
		s.append(t if "permanent" in t else t + " - permanent")
	return s
