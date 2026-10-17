class_name CombatText
extends RefCounted
## Lazy renderer for BattleSim log entries. The sim stores numbers + template keys only; text is built here on
## first read and cached into the entry:
##   CombatText.render(entry) -> {"tick", "text": short story line, "detail": Array[String] (one line per tissue
##   layer reached, functional losses, cut path), "calc": the numbers (rolls, physics, layer tests, pain, timing)}
## Templates: res://data/combat_text.json. Variants are picked from a per-fighter offset and counter
## (deterministic, never the same variant twice in a row for the same fighter and outcome).

static var _tpl: Dictionary = {}

const STATE_RANK := {"obliterated": 9, "destroyed": 9, "severed": 8, "cut through": 8, "pulped": 7, "smashed": 7,
	"shattered": 6, "run through": 5, "sliced through": 5, "torn open": 5, "pierced": 5, "torn": 4, "fractured": 4,
	"chipped": 3, "cut": 2, "nicked": 2, "bruised": 1}
## Event templates whose {his} belongs to the target ({d} keeps {his} feet), not the actor.
const DEFENDER_HIS := ["takedown_fail", "drag_ok", "drag_fail"]
const NATURAL_WORD := {"punch": "fist", "kick": "foot", "bite": "teeth", "claw": "claws", "gore": "tusks", "charge": "charge", "shake": "jaws"}

static func templates() -> Dictionary:
	if _tpl.is_empty():
		var txt := FileAccess.get_file_as_string("res://data/combat_text.json")
		var d = JSON.parse_string(txt)
		_tpl = d if d is Dictionary else {"strike": {}, "ev": {}}
	return _tpl

static func _pick(arr: Array, vk: int, vc: int) -> String:
	var n := arr.size()
	if n == 0:
		return ""
	if n == 1:
		return arr[0]
	var step := 1 + (vk % (n - 1))
	return arr[(vk + vc * step) % n]

static func _fill(s: String, p: Dictionary) -> String:
	# perf (same result as replacing every key in order): a placeholder that is not in the text is skipped, and once
	# no "{" is left no later replacement can match
	for k in p:
		if not s.contains("{"):
			break
		var ph: String = "{" + k + "}"
		if s.contains(ph):
			s = s.replace(ph, str(p[k]))
	return s

static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s

static func render(entry: Dictionary) -> Dictionary:
	if entry.has("text"):
		return entry
	var d: Dictionary = entry.get("d", {})
	var k: String = entry.get("k", "")
	var out := {"text": "", "detail": [], "calc": ""}
	match k:
		"strike":
			out = _render_strike(d)
		"move":
			out["text"] = "%s %s to (%d,%d)." % [_cap(String(d.get("al", ""))), "crawls" if d.get("prone", false) else ("runs" if d.get("run", false) else "moves"), d["x"], d["y"]]
			out["calc"] = "move %.1f ticks -> %d = %s / %.0f x terrain %.2f%s" % [d["mt"], d["ticks"], Formulas.speed_text(d.get("sp", {})),
				Formulas.GAIT_TICKS_DIV, d["tm"], " x prone 2" if d.get("prone", false) else ""] \
				+ (" x stuffed %.2f" % float(d["wk"]) if float(d.get("wk", 1.0)) != 1.0 else "")
		"ev":
			out = _render_ev(d)
		"event":
			out = _render_event(d)
	entry["text"] = out["text"]
	entry["detail"] = out["detail"]
	entry["calc"] = out["calc"]
	return entry

## Presentation-only events without a strike entry retain their actual emit-time context.
static func _render_event(d: Dictionary) -> Dictionary:
	var event: Dictionary = d.get("event", {})
	var context: Dictionary = d.get("context", {})
	var actor := _cap(String(context.get("al", "A combatant")))
	var target := String(context.get("dl", "an opponent"))
	var part := String(context.get("pname", event.get("part", "")))
	var text := String(event.get("text", ""))
	if text == "":
		match String(event.get("type", "")):
			"prepare": text = "%s prepares to %s %s with %s." % [actor, String(context.get("verb", "strike")), target, String(context.get("weapon", "bare hands"))]
			"attack": text = "%s attacks %s with %s." % [actor, target, String(context.get("weapon", "bare hands"))]
			"move":
				var cell: Vector2i = context.get("cell", Vector2i.ZERO)
				text = "%s moves to (%d, %d)." % [actor, cell.x, cell.y]
			"enter": text = "%s enters the battlefield." % actor
			"wound": text = "%s wounds %s in the %s." % [actor, target, part]
			"snap": text = "%s's %s breaks on the blow." % [actor, String(context.get("weapon", "weapon"))]
			_: text = "%s: %s%s." % [actor, String(event.get("type", "event")).replace("_", " "), " · " + part if part != "" else ""]
	return {"text": text, "detail": [], "calc": ""}

# ---------------------------------------------------------------- strikes
static func _render_strike(d: Dictionary) -> Dictionary:
	var T := templates()
	var verb: String = d.get("verb", "strike")
	var words := verb.split(" ", false, 1)
	var v0: String = words[0]
	var rest: String = words[1] if words.size() > 1 else ""
	var v3 := v0 + ("es" if v0.ends_with("sh") or v0.ends_with("ch") or v0.ends_with("s") or v0.ends_with("x") else "s")
	var natural: bool = d.get("natural", false)
	var wname: String = NATURAL_WORD.get(v0, "fist") if natural else String(d.get("w", ""))
	var apr := String(d.get("apr", "his"))
	var dpr := String(d.get("dpr", "his"))
	var vw := ""
	if not natural:
		vw = ("%s of %s %s" % [rest, apr, wname]) if rest != "" else "with %s %s" % [apr, wname]
	elif rest != "":
		vw = rest
	var arm := ""
	for a in d.get("armor", []):
		arm = a[0]
	if String(d.get("stop", "")) != "":
		arm = d["stop"]
	var layers: Array = d.get("layers", [])
	var p := {"A": _cap(String(d.get("al", ""))), "a": d.get("al", ""), "D": _cap(String(d.get("dl", ""))), "d": d.get("dl", ""),
		"W": wname, "WN": String(d.get("wn", "")) if String(d.get("wn", "")) != "" else wname, "V": v3, "v": v0 if rest == "" or natural else verb,
		"VW": vw, "P": d.get("pname", ""), "ARM": arm,
		"SH": d.get("sh", "shield"), "DW": d.get("dw", "weapon"), "R": _result(layers, T, int(d.get("vk", 0)) + int(d.get("vc", 0))),
		# {his}: the defender's on defences (block/parry/dodge ...), the attacker's on hits (monsters wave 1: "its" for animals)
		"his": apr if String(d.get("out", "hit")) in ["hit", "sever", "decap"] else dpr,
		# v0.014: both sides' pronouns, always (the register's sex; "its" for beasts)
		"ahis": apr, "ahe": SUBJ.get(apr, "he"), "ahim": OBJ.get(apr, "him"), "dhis": dpr, "dhim": OBJ.get(dpr, "him"), "dhe": SUBJ.get(dpr, "he"), "PIECE": "", "THRU": ""}
	var out := String(d.get("out", "hit"))
	var vk := int(d.get("vk", 0))
	var vc := int(d.get("vc", 0))
	var arr: Array
	var shot := d.has("shot")   # bows: an arrow's strike has its own lines
	if shot:
		var AT: Dictionary = T.get("arrow", {})
		var akey := "via" if out == "hit" and d.has("via") else out
		arr = AT.get(akey, AT.get("hit", []))
		p["SH"] = d.get("via", d.get("sh", "shield"))
	elif not out in ["hit", "sever", "decap"]:
		arr = _g(T, "strike", out)
		if arr.is_empty():
			arr = _g(T, "strike", "harmless")
	var text := ""
	var shown := {}   # funcs already told in the story line (kept out of the detail)
	if not shot and out in ["hit", "sever", "decap"]:
		text = _hit_line(d, p, T, natural, rest, vk, vc, shown)   # v0.014: the vivid line, built from the wound only
	else:
		text = _fill(_pick(arr, vk, vc), p)
		if shot and out == "hit" and String(d.get("kill", "")) != "":
			text = text.trim_suffix("!").trim_suffix(".") + _fill(_pick(_g(T, "kill", "any"), vk, vc + 3), p)
	var art := float(d.get("art", 0.0))
	if art > 0.0:
		var key := "nick" if art < Formulas.BLEED_WORDS[0] else ("artery" if art < Formulas.BLEED_WORDS[1] else "major")
		text += " " + _fill(_pick(_g(T, "artery", key), vk, vc), {"ART": d.get("artname", "artery"), "d": p["d"], "D": p["D"], "P": p["P"], "dhis": p["dhis"]})
	if shot:
		if d.get("lodged", false):
			text += " " + _fill(_pick(T["arrow"]["lodged"], vk, vc), p)
		elif d.get("exit", false):
			text += " " + _fill(_pick(T["arrow"]["exit"], vk, vc), p)
	elif d.get("lodged", false):
		text += " " + _fill(_pick(T["lodged"], vk, vc), p)
	# v0.014: the defender's armour damage, told only when the wound does not already show it (nothing got through)
	var ad: Array = d.get("ad", [])
	if not ad.is_empty() and layers.is_empty():
		var worst: Array = []
		for x in ad:   # (clothes are not armour worth a sentence)
			if x.size() > 2 and String(x[2]) == "cloth":
				continue
			if worst.is_empty() or int(ARMOR_DMG_RANK.get(x[1], 0)) > int(ARMOR_DMG_RANK.get(worst[1], 0)):
				worst = x
		if not worst.is_empty():
			p["ARM"] = worst[0]
			text += " " + _fill(_pick(_g(T, "armor_dmg", String(worst[1])), vk, vc), p)
	# v0.014: the attacker's own weapon failing is never obvious: always told (metal, kind, what it struck)
	var wd: Array = d.get("wd", [])
	if not wd.is_empty() and not natural:
		p["PIECE"] = "%s's %s" % [p["d"], wd[1]]   # "Grushnak's steel gauntlet" / "Grushnak's skull"
		text += " " + _fill(_pick(_g(T, "weapon_dmg", String(wd[0])), vk, vc), p)
	# v0.014: the victim's reaction from the sim's real pain (stuns, vomiting, falls and fainting have their own lines)
	if String(d.get("rx", "")) != "" and String(d.get("kill", "")) == "":
		text += " " + _fill(_pick(_g(T, "rx", String(d["rx"])), vk, vc), p)
	text = _tidy(text)
	# detail: one line per tissue layer reached, functional losses, cut path
	var detail := []
	var lt: Array = T.get("layer", ["{L}: {S}{DEPTH}."])
	for i in layers.size():
		var l: Array = layers[i]
		var depth := ""
		if float(l[4]) > 0.0 and float(l[4]) < 0.999:
			depth = " (%d%% deep)" % int(float(l[4]) * 100.0)
		detail.append(_fill(lt[i % lt.size()], {"L": _cap(String(l[0])), "l": l[0], "S": l[2], "DEPTH": depth}))
	for fl in d.get("funcs", []):
		var ft: Dictionary = _g(T, "func")
		if ft.has(fl) and not shown.has(fl):
			detail.append(_fill(_pick(ft[fl], vk, vc), p))
	for x in ad:
		detail.append("%s: %s%s." % [_cap(String(x[0])), x[1], " (scrap after the battle)" if String(x[1]) in ["split", "cracked", "shattered"] else (" (a quality step lost)" if String(x[1]) != "" else "")])
	if not wd.is_empty():
		detail.append("%s: %s%s." % [_cap(String(d.get("w", ""))), {"snap": "snapped", "bend": "bent", "chip": "edge chipped"}.get(String(wd[0]), wd[0]),
			" (scrap after the battle)" if String(wd[0]) == "snap" else (" (bent back after, a quality step or two lost)" if String(wd[0]) == "bend" else "")])
	var path: String = d.get("path", "")
	if path != "" and T.get("path", {}).has(path):
		var thru := "across the %s" % p["P"]
		for l in layers:
			if String(l[2]) in ["cut through", "sliced through", "severed", "run through"] and not String(l[1]) in ["skin", "fat"]:
				thru = "through the %s" % l[0]
		detail.append(_fill(_pick(T["path"][path], vk, vc), {"THRU": thru, "DEEP": str(int(_depth_mm(d)))}))
	return {"text": text, "detail": detail, "calc": _calc(d)}

static func _depth_mm(d: Dictionary) -> float:
	for s in d.get("steps", []):
		if s is Array and s[0] == "q":
			return float(s[10])
	return 0.0

const TISSUE_WEIGHT := {"brain": 7, "organ": 6, "vessel": 6, "bone": 5, "nerve": 4, "tendon": 4, "muscle": 3, "fat": 1, "skin": 0}

## The story names the two worst layers (state severity first, then how deep/important the tissue is), each with a
## gerund varied by `salt` (v0.014: several words per state; Reduced gore uses the milder "mild.gerund" set).
## `skip`: a layer name already told (the breach line's bone).
static func _result(layers: Array, T: Dictionary, salt: int = 0, skip: String = "") -> String:
	if layers.is_empty():
		return ""
	var ranked := layers.duplicate()
	# v0.014: skin and fat are only named when nothing deeper was hurt (they made every line read the same)
	var deep := ranked.filter(func(x): return not String(x[1]) in ["skin", "fat"])
	if not deep.is_empty():
		ranked = deep
	ranked.sort_custom(func(x, y):
		var sx := int(STATE_RANK.get(x[2], 0)) * 10 + int(TISSUE_WEIGHT.get(x[1], 2)) * 3
		var sy := int(STATE_RANK.get(y[2], 0)) * 10 + int(TISSUE_WEIGHT.get(y[1], 2)) * 3
		return sx > sy)
	var g: Dictionary = _g(T, "gerund")
	var parts := []
	for l in ranked:
		if parts.size() >= 2:
			break
		if String(l[0]) == skip:
			continue
		var w = g.get(l[2], l[2])
		if w is Array:
			w = (w as Array)[(salt + parts.size() * 7) % (w as Array).size()] if not (w as Array).is_empty() else l[2]
		parts.append("%s the %s" % [w, l[0]])
	return " and ".join(parts)

# ---------------------------------------------------------------- v0.014: vivid hit lines and the Gore setting
## Gore setting (Game "gore": "full" | "reduced"): Reduced takes the "mild" template set wherever it has one (milder
## words, no spraying or spilling); Full uses the main set. Set by Game.load_settings/set_setting; tests flip it.
static var gore_full := true

const SUBJ := {"his": "he", "her": "she", "its": "it"}
const OBJ := {"his": "him", "her": "her", "its": "it"}
const ARMOR_DMG_RANK := {"dented": 1, "torn": 2, "punctured": 2, "burst": 3, "split": 4, "cracked": 4, "shattered": 5}
## Main-text order of the functional losses (the first two found are told in the story line; the rest stay in the detail).
const FUNC_STORY := ["guts", "drown", "spine", "airway", "lung", "eye", "tooth"]
const BREACH_BONE := ["shattered", "cut through", "sliced through", "smashed", "pulped", "obliterated", "destroyed", "severed"]

## A template group: T[a][b] (or T[a] when b == ""), from the "mild" set first when gore is Reduced.
static func _g(T: Dictionary, a: String, b: String = "") -> Variant:
	if not gore_full:
		var m: Dictionary = T.get("mild", {})
		if m.has(a):
			var v = m[a]
			if b == "":
				return v
			if v is Dictionary and (v as Dictionary).has(b):
				return v[b]
	var v2 = T.get(a, {})
	if b == "":
		return v2
	if v2 is Dictionary:
		return (v2 as Dictionary).get(b, [])
	return []

static func _tidy(s: String) -> String:
	s = s.replace("  ", " ").replace(" ,", ",").replace(" ;", ";").replace(" !", "!").replace(" .", ".").replace("!.", "!").replace(".!", "!").replace("!!", "!")
	return s.strip_edges()

## The hit line: [breach | through-armour | plain opener] + the worst tissue + the payoff (kill, sever) + up to two
## functional losses, all from the strike record (layers, armour damage, funcs, kill cause). Nothing else is said.
static func _hit_line(d: Dictionary, p: Dictionary, T: Dictionary, natural: bool, rest: String, vk: int, vc: int, shown: Dictionary) -> String:
	var out := String(d.get("out", "hit"))
	var wtype := String(d.get("wtype", "edge"))
	var layers: Array = d.get("layers", [])
	var kill := String(d.get("kill", ""))
	var text := ""
	# the armour the blow went through (cut through, or forced through by a blunt blow)
	for a in d.get("armor", []):   # (clothes are not worth naming: "through his linen trousers")
		if String(a[1]) in ["cut", "dented"] and (a.size() < 3 or String(a[2]) != "cloth"):
			p["THRU"] = a[0]
			break
	if out == "decap" or out == "sever":
		var arr: Array = _g(T, "strike", out)
		text = _fill(_pick(arr, vk, vc), p)
		if out == "sever" and kill != "":
			text += " " + _fill(_pick(_g(T, "kill", "after_sever"), vk, vc + 1), p)
	else:
		# breach: the blow broke a piece (split, cracked, shattered) AND the bone under it on the struck part
		var breach_arm := ""
		for x in d.get("ad", []):
			if String(x[1]) in ["split", "cracked", "shattered"] and (x.size() < 3 or String(x[2]) != "cloth"):
				breach_arm = x[0]
		var bone := ""
		if breach_arm != "":
			for l in layers:
				if String(l[1]) == "bone" and String(l[2]) in BREACH_BONE:
					bone = l[0]
					break
		var opener := ""
		if bone != "" and not natural and rest == "":
			p["ARM"] = breach_arm
			p["BONE"] = bone
			opener = _fill(_pick(_g(T, "breach", wtype if wtype in ["edge", "blunt", "pierce"] else "edge"), vk, vc), p)
		else:
			var key := wtype
			if natural:
				var v0 := String(d.get("verb", "")).split(" ")[0]
				key = "nat_" + v0 if (T.get("open", {}) as Dictionary).has("nat_" + v0) else "natural"
			elif rest != "":
				key = "sub"   # a pommel, shaft or beard blow: say so
			elif p["THRU"] != "":
				key = "thru_" + (wtype if wtype in ["edge", "blunt", "pierce"] else "edge")
			var arr: Array = _g(T, "open", key)
			if arr.is_empty():
				arr = _g(T, "open", "edge")
			opener = _fill(_pick(arr, vk, vc), p)
			bone = ""
		var r := _result(layers, T, vk + vc, bone)
		text = opener + (", " + r if r != "" else "")
		if kill != "":
			var kk := "any"
			if kill.contains("brain"):
				kk = "brain"
			elif kill.contains("heart"):
				kk = "heart"
			var ka: Array = _g(T, "kill", kk)
			if ka.is_empty():
				ka = _g(T, "kill", "any")
			text += _fill(_pick(ka, vk, vc + 1), p)
		else:
			var worst := 0
			for l in layers:
				worst = maxi(worst, int(STATE_RANK.get(l[2], 0)))
			text += "!" if worst >= 5 else "."
	# up to two functional losses told in the story (the rest in the detail lines)
	var told := 0
	for fl in FUNC_STORY:
		if told >= 2:
			break
		if fl in d.get("funcs", []):
			var fa: Array = _g(T, "pay", fl)
			if not fa.is_empty():
				text += " " + _fill(_pick(fa, vk, vc), p)
				shown[fl] = true
				told += 1
	return text

## Decisive-event lines told eagerly by the sim (artery opened, part severed, head off, guts out): vivid in Full,
## plain in Reduced. `v` picks the variant.
static func decisive(kind: String, p: Dictionary, _rate: float, v: int) -> String:
	var T := templates()
	var arr: Array = _g(T, "decisive", kind)
	if arr.is_empty():
		return ""
	var q := p.duplicate()
	var dp := String(p.get("his", "his"))
	q["dhis"] = dp
	q["dhim"] = OBJ.get(dp, "him")
	q["dhe"] = SUBJ.get(dp, "he")
	return _tidy(_fill(arr[absi(v) % arr.size()], q))

static func _calc(d: Dictionary) -> String:
	var lines := PackedStringArray()
	for s in d.get("steps", []):
		if s is Dictionary:   # a roll record (Formulas.roll_*) is stored as the step itself (same as ["roll", record])
			lines.append(Formulas.roll_text(s))
			continue
		var t: String = s[0]
		match t:
			"shot":   # bows
				var sh: Dictionary = s[1]
				lines.append("arrow: %s (%s, contact %d) after %.1f tiles: v %.1f m/s, m %.3f kg -> E %.1f J, p %.2f; squareness x%.2f; from the %s" % [
					sh.get("name", ""), sh.get("shape", ""), int(sh.get("contact", 0)), float(sh.get("dist", 0.0)), float(sh.get("v", 0.0)),
					float(sh.get("m", 0.0)), float(sh.get("E", 0.0)), float(sh.get("p", 0.0)), float(sh.get("sq", 1.0)), sh.get("rel", "front")])
			"pre":
				var pr: Dictionary = s[1]
				if not pr.get("ch", {}).is_empty():
					lines.append(Formulas.roll_text(pr["ch"]))
				lines.append("timing: prepare %d ticks (%.1f from the swing) + recover %.1f (raw %d x %.1f x tempo %.2f); %s" % [
					pr["prep"], pr["prep_raw"], pr["rec_raw"], pr["rec"], Formulas.RECOVER_TICK_MULT, pr["tempo"], Formulas.speed_text(pr.get("sp", {}))])
			"att":
				lines.append("attacker: %s lvl %d -> effective %.1f (attributes %+.1f, fighter %d, condition x%.2f, from the %s%s)" % [
					s[1], s[2], s[3], s[4], s[5], s[6], s[7], ", lying down x0.5" if s[8] else ""])
			"help":
				lines.append({"forced": "(inspection strike: lands without a defence)", "unconscious": "defender unconscious: auto-hit, helmet off, head priority",
					"prone": "defender lying down: auto-hit, helmet off, head priority"}.get(s[1], s[1]))
			"def":
				lines.append("defence: %s eff %.1f; contest P(through) %.2f + saturation %.2f (%d recent) -> %.2f" % [s[1], s[2], s[3], s[4], s[6], s[5]])
			"roll":
				lines.append(Formulas.roll_text(s[1]))
			"swing":
				lines.append(Formulas.swing_text(s[1]) + " (STR %d eff, grip x%.1f)" % [int(s[1].get("str", 0)), s[1].get("grip", 1.0)])
			"q":
				lines.append("x quality %.2f -> p %.1f, E %.0f J; %s (%s, q x%.1f, Sha %.2f), %s contact %d%s" % [s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8], int(s[9]),
					(", cutting depth %.0f mm" % s[10]) if s[11] else ""])
			"ae":
				if s[5]:
					lines.append("  %s (%dmm): EDGE E %.0f >= R %.0f -> cut through; E %.0f, p %.1f, depth left %.0fmm" % [s[1], int(s[2]), s[3], s[4], s[6], s[7], s[8]])
				else:
					lines.append("  %s (%dmm): EDGE E %.0f < R %.0f -> edge stopped, blunt for this layer" % [s[1], int(s[2]), s[3], s[4]])
			"ad":
				lines.append("  %s: DEFLECT 2 x %.0fcm3 x IY %.0f < A %.0f x density %.0f -> glances off" % [s[1], s[2], s[3], s[4], s[5]])
			"ab":
				if s[4]:
					lines.append("  %s: BLUNT p %.1f >= R %.1f -> forced through; p %.1f" % [s[1], s[2], s[3], s[7]])
				else:
					lines.append("  %s: BLUNT p %.1f < R %.1f -> holds; %s transmits x%.2f; p %.1f" % [s[1], s[2], s[3], s[5], s[6], s[7]])
			"te":
				if s[6]:
					lines.append("  %s (%s %.0fmm): EDGE E %.0f >= R %.0f -> cut %.0f%% deep, dmg +%.2f (TOU x%.2f); E %.0f, p %.1f" % [
						s[1], s[2], s[3], s[4], s[5], float(s[7]) * 100.0, s[8], s[9], s[10], s[11]])
				else:
					lines.append("  %s (%s %.0fmm): EDGE E %.0f < R %.0f -> edge stopped, blunt" % [s[1], s[2], s[3], s[4], s[5]])
			"spent":
				lines.append("  blade depth spent -> the rest arrives as blunt force")
			"tb":
				if s[5]:
					lines.append("  %s (bone %.0fmm): BLUNT p %.1f >= R %.1f -> dmg +%.2f; p %.1f" % [s[1], s[2], s[3], s[4], s[6], s[7]])
				else:
					lines.append("  %s (bone %.0fmm): BLUNT p %.1f < R %.1f -> holds; strain %d/50000 -> p %.2f" % [s[1], s[2], s[3], s[4], s[8], s[7]])
			"ts":
				lines.append("  %s (%s %.0fmm): BLUNT p %.1f -> dmg +%.2f; p %.1f" % [s[1], s[2], s[3], s[4], s[5], s[6]])
			"sever":
				lines.append("  SEVERED: p left %.1f >= %.1f; bleed +%.2f/tick" % [s[1], s[2], s[3]])
			"pain":
				lines.append("pain +%.0f (raw %.0f x tolerance %.2f) -> %.0f; bleed +%.3f/tick (total %.3f); blood %.0f/%.0f" % [s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8]])
			"stag":
				lines.append("stagger: p %.1f / stability %.1f = %.2f" % [s[1], s[2], s[3]])
			"note":
				lines.append(String(s[1]))
	return "\n".join(lines)

# ---------------------------------------------------------------- simple events
## "STR +2, AGI +1" from an attribute growth dict (the growth log line keeps the dict; text is built when read).
static func growth_text(g: Dictionary) -> String:
	var parts := []
	for a in g:
		parts.append("%s +%d" % [a, g[a]])
	return ", ".join(parts)

## Placeholders of the simple-event lines, in fill order.
const EV_KEYS := ["A", "a", "D", "d", "his", "W", "part", "killer", "why", "side", "n", "skill", "lvl", "g", "v", "S", "dhim", "dhis", "ahe"]

## Value of one simple-event placeholder.
static func _ev_val(k: String, d: Dictionary, key: String) -> Variant:
	match k:
		"A": return _cap(String(d.get("al", d.get("dl", ""))))
		"a": return d.get("al", "")
		"D": return _cap(String(d.get("dl", "")))
		"d": return d.get("dl", "")
		"his": return d.get("dpr", "his") if key in DEFENDER_HIS else d.get("apr", "his")
		"W": return d.get("w", "weapon")
		"part": return d.get("part", "")
		"killer": return d.get("killer", "")
		"why": return d.get("why", "")
		"side": return d.get("side", "")
		"n": return d.get("n", "")
		"skill": return d.get("skill", "")
		"lvl": return d.get("lvl", "")
		"g": return d.get("g", "") if not d.has("gd") else growth_text(d["gd"])
		"v": return d.get("v", "")
		"S": return d.get("s", "")   # bows: the sidearm
		"dhim": return OBJ.get(String(d.get("dpr", "his")), "him")   # v0.014
		"dhis": return d.get("dpr", "his")
		"ahe": return SUBJ.get(String(d.get("apr", "his")), "he")
	return ""

## _fill over the EV_KEYS values, computing a value only when its placeholder is in the text (perf; same result).
static func _fill_ev(s: String, d: Dictionary, key: String) -> String:
	for k in EV_KEYS:
		if not s.contains("{"):
			break
		var ph: String = "{" + k + "}"
		if s.contains(ph):
			s = s.replace(ph, str(_ev_val(k, d, key)))
	return s

static func _render_ev(d: Dictionary) -> Dictionary:
	var T := templates()
	var key: String = d.get("key", "")
	if key == "death" and String(d.get("killer", "")) == "":
		key = "death_nokiller"
	var arr: Array = _g(T, "ev", key)
	if key == "say":   # v0.014: battle cries and taunts by culture (BattleSim._say)
		var sd = _g(T, "say", String(d.get("say", "cry")))
		arr = (sd as Dictionary).get(String(d.get("cul", "middle")), (sd as Dictionary).get("middle", [])) if sd is Dictionary else []
	var text := _fill_ev(_pick(arr, int(d.get("vk", 0)), int(d.get("vc", 0))), d, key) if not arr.is_empty() else key
	if key == "officer_rally":
		text = "%s calls %s back into the fight. %s rallies and rejoins the formation." % [_cap(String(d.get("al", "The officer"))), String(d.get("dl", "the soldier")), _cap(String(d.get("dl", "The soldier")))]
	var calc := ""
	match key:
		"officer_rally":
			calc = "morale %.1f -> %.1f; assigned commander %d, leadership %.1f, distance %d / %d tiles" % [float(d.get("morale_before", 0.0)), float(d.get("morale_after", 0.0)), int(d.get("commander_uid", -1)), float(d.get("leader_level", 0.0)), int(d.get("distance", 0)), int(d.get("radius", 0))]
		"wake":
			calc = "pain %.1f < %.1f, blood %.0f%%" % [d.get("pain", 0.0), Formulas.PAIN_KO * Formulas.PAIN_WAKE, float(d.get("blood", 1.0)) * 100.0]
		"rout":
			calc = "morale %.1f after a %.1f shock (%s); %s" % [d.get("morale", 0.0), d.get("shock", 0.0), d.get("why", ""), Formulas.roll_text(d["roll"]) if d.has("roll") else ""]
		"twist":
			calc = "twist: p %.1f (0.3 x original) on the %s, dmg +%.2f, pain +%.0f (x2), bleed x1.5" % [d.get("p", 0.0), d.get("layer", ""), d.get("dmg", 0.0), d.get("pain", 0.0)]
		"grab_ok", "grab_fail", "takedown_ok", "takedown_fail", "disarm_fail", "latch_ok", "drag_ok", "drag_fail":
			if d.has("roll"):
				calc = Formulas.roll_text(d["roll"])
		"growth":
			calc = "attribute use this battle: %s" % str(d.get("use", {}))
		"shoot":   # bows: the draw and the aim roll
			var s: Array = d.get("sol", [])
			if s.size() >= 15:
				calc = "draw: pull %.0f N, reach %.2f m vs bow %.0f N x %.2f m -> stores %.1f J, archer can draw %.1f J -> drawn %.1f J%s; efficiency %.2f -> arrow %.1f J (%.3f kg at %.1f m/s); strain %.2f; aim level %.1f; flat to %.1f tiles, range %.1f\n" % [
					s[0], s[1], s[2], s[3], s[4], s[5], s[6], " (partial draw)" if float(s[5]) < float(s[4]) else "", s[7], s[8], s[9], s[10], s[11], s[12], s[13], s[14]]
			calc += "target %.1f tiles away%s%s%s; %s shot, comes down at %.1f tiles; %d arrows left" % [float(d.get("dist", 0.0)),
				", moving" if d.get("tm", false) else "", ", archer moving" if d.get("sm", false) else "",
				(", %d recent defences" % int(d.get("sat", 0))) if int(d.get("sat", 0)) > 0 else "",
				"flat" if d.get("flat", false) else "arcing", float(d.get("land", 0.0)), int(d.get("left", 0))]
			if d.has("roll"):
				calc += "\n" + Formulas.roll_text(d["roll"])
		_:
			if key.begins_with("food_"):
				calc = "belly %d (%s), buzz %d (%s)%s; fatigue gain x%.2f, focus x%.2f, pain tolerance x%.2f" % [
					int(d.get("belly", 0.0)), d.get("bs", ""), int(d.get("buzz", 0.0)), d.get("zs", ""),
					", hung over" if d.get("hung", false) else "", d.get("fat", 1.0), d.get("foc", 1.0), d.get("tol", 1.0)]
				if d.has("roll"):
					calc += "; " + Formulas.roll_text(d["roll"])
				if d.has("pain"):
					calc += "; pain +%.0f after tolerance" % float(d["pain"])
			elif key.begins_with("ko_"):
				calc = "pain %.0f (out above %.0f), blood %.0f%%, brain %.2f" % [d.get("pain", 0.0), Formulas.PAIN_KO, float(d.get("blood", 1.0)) * 100.0, d.get("brain", 0.0)]
			elif key.begins_with("stun_"):
				calc = "+%d ticks (stagger %.2f, pain %.0f)" % [int(d.get("ticks", 0)), d.get("stagger", 0.0), d.get("pain", 0.0)]
			elif key.begins_with("fall_"):
				calc = "down %d ticks" % int(d.get("ticks", 0))
	return {"text": text, "detail": [], "calc": calc}
