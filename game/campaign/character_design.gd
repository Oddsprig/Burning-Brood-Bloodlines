class_name CharacterDesign
extends RefCounted
## Roadmap v0.039: Character designer (logic only) for the player's starting ruler.
##
## Look keys match the exact fields read by FigurePainter (art/figure_painter.gd):
##   - "skin": hex colour string from DB.races[race]["skin"]
##   - "hair": hex colour string from DB.races[race]["hair"]
##   - "seed": int hairstyle index (HumanArt/ElfArt: 0..5, OrcArt: 0..9, DwarfArt: 0..4, generic: RACE_ART hair_styles)
##   - "female_set": int 0..1 (FigurePainter.FEMALE_SETS), read only when sex == 1
##   - "beard": bool and "beard_style": int 0..7 (FigurePainter.BEARD_STYLES), read only when sex == 0
##     and race in ["human", "orc", "dwarf"]
##
## Focus bonus documentation:
##   Register person rows (p in f.pp) have fixed positional slots and no skill field (do not add person slots).
##   Real skills live on Unit.skills (core/unit.gd, core/db.gd UTILITY_SKILLS) and are queried by Unit.skill(),
##   Game.best_skill(), and Intrigue._skill(). Each focus maps to an existing utility skill:
##     - "martial"     -> "tactician"
##     - "stewardship" -> "appraiser"
##     - "diplomacy"   -> "negotiator"
##     - "intrigue"    -> "judge_of_intent"
##   Applying a focus records the one-time +2 bonus on player_house.design and applies it to the ruler's bound
##   Unit immediately if already bound, or on first binding in Persons.bind.

const FOCUS_BONUS: int = 2
const FOCUS_SKILLS: Dictionary = {
	"martial": "tactician",
	"stewardship": "appraiser",
	"diplomacy": "negotiator",
	"intrigue": "judge_of_intent",
}
const BEARD_RACES: Array = ["human", "orc", "dwarf"]
const ALLOWED_DESIGN_KEYS: Array = [
	"first_name", "name", "look", "focus",
	"skin", "hair", "seed", "female_set", "beard", "beard_style",
]

const HAIR_STYLE_LABELS: Dictionary = {
	"human": ["Short crop", "Long locks", "Tousled", "Shaved", "Ponytail", "Parted"],
	"high_elf": ["Long straight", "Crown braid", "Swept back", "Twin braids", "High tail", "Flowing"],
	"moon_elf": ["Long straight", "Crown braid", "Swept back", "Twin braids", "High tail", "Flowing"],
	"dark_elf": ["Long straight", "Crown braid", "Swept back", "Twin braids", "High tail", "Flowing"],
	"orc": ["Topknot", "Shaved", "Mohawk", "Dreadlocks", "Wild mane", "Scalp lock", "Twin tails", "Side-shaved", "Spiked crest", "Bone-braided"],
	"dwarf": ["Braided", "Long mane", "Bald crown", "Swept back", "Twin tails"],
}

static func _hair_style_choices(race: String) -> Array:
	var out: Array = []
	if HAIR_STYLE_LABELS.has(race):
		var labels: Array = HAIR_STYLE_LABELS[race]
		for i in labels.size():
			out.append({"value": int(i), "label": str(labels[i])})
		return out
	var ra: Dictionary = FigurePainter.RACE_ART.get(race, FigurePainter.RACE_ART["human"])
	var styles: Array = ra.get("hair_styles", ["short"])
	for i in styles.size():
		out.append({"value": int(i), "label": str(styles[i]).capitalize()})
	return out

static func options(game, person_uid: String) -> Dictionary:
	if game == null or not (game.world is Dictionary) or person_uid == "":
		return {}
	var loc: Dictionary = Dynasty._person(game, person_uid)
	if loc.is_empty():
		return {}
	var e: Dictionary = loc["econ"]
	var f: Dictionary = loc["family"]
	var p: Array = loc["person"]
	var race: String = Persons.race_of(e)
	var sex: int = int(p[2])
	var rd: Dictionary = DB.races.get(race, DB.races["human"])
	var choices: Dictionary = {}
	var skins: Array = rd.get("skin", ["#e8c4a0"])
	var skin_list: Array = []
	for i in skins.size():
		var s_hex: String = str(skins[i])
		skin_list.append({"value": s_hex, "label": "Skin %d (%s)" % [i + 1, s_hex]})
	if not skin_list.is_empty():
		choices["skin"] = skin_list
	var hairs: Array = rd.get("hair", ["#3a2a1a"])
	var hair_list: Array = []
	for i in hairs.size():
		var h_hex: String = str(hairs[i])
		hair_list.append({"value": h_hex, "label": "Hair %d (%s)" % [i + 1, h_hex]})
	if not hair_list.is_empty():
		choices["hair"] = hair_list
	var seed_list: Array = _hair_style_choices(race)
	if not seed_list.is_empty():
		choices["seed"] = seed_list
	if sex == 1:
		var fsets: Array = []
		for i in FigurePainter.FEMALE_SETS.size():
			fsets.append({"value": int(i), "label": str(FigurePainter.FEMALE_SETS[i])})
		choices["female_set"] = fsets
	elif BEARD_RACES.has(race):
		choices["beard"] = [
			{"value": false, "label": "Clean-shaven"},
			{"value": true, "label": "Bearded"},
		]
		var bstyles: Array = []
		for i in FigurePainter.BEARD_STYLES.size():
			bstyles.append({"value": int(i), "label": str(FigurePainter.BEARD_STYLES[i])})
		choices["beard_style"] = bstyles
	return {
		"person_uid": person_uid,
		"name": Persons.name_of(f, p, race),
		"first_name": Persons.first_of(e, p),
		"family_name": str(f.get("name", "")),
		"sex": sex,
		"race": race,
		"choices": choices,
		"focuses": [
			{"value": "martial", "label": "Martial"},
			{"value": "stewardship", "label": "Stewardship"},
			{"value": "diplomacy", "label": "Diplomacy"},
			{"value": "intrigue", "label": "Intrigue"},
		],
	}

static func _validate_first_name(raw_name: String) -> Dictionary:
	var trimmed: String = raw_name.strip_edges()
	var collapsed: String = ""
	for i in trimmed.length():
		var ch: String = trimmed.substr(i, 1)
		if ch == " ":
			if collapsed != "" and not collapsed.ends_with(" "):
				collapsed += " "
		else:
			collapsed += ch
	if collapsed.length() < 2 or collapsed.length() > 20:
		return {"ok": false, "reason": "First name must be between 2 and 20 characters.", "first_name": ""}
	var first_ch: String = collapsed.substr(0, 1)
	var last_ch: String = collapsed.substr(collapsed.length() - 1, 1)
	if first_ch in [" ", "'", "-"] or last_ch in [" ", "'", "-"]:
		return {"ok": false, "reason": "First name must start and end with a letter.", "first_name": ""}
	var has_letter: bool = false
	for i in collapsed.length():
		var ch: String = collapsed.substr(i, 1)
		var code: int = collapsed.unicode_at(i)
		var is_letter: bool = (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 192 and code <= 687)
		if is_letter:
			has_letter = true
		elif not (ch in [" ", "'", "-"]):
			return {"ok": false, "reason": "First name may contain only letters, spaces, apostrophes and hyphens.", "first_name": ""}
	if not has_letter:
		return {"ok": false, "reason": "First name must include letters.", "first_name": ""}
	return {"ok": true, "reason": "", "first_name": collapsed}

static func preview(game, person_uid: String, design: Dictionary) -> Dictionary:
	if game == null or not (game.world is Dictionary):
		return {"ok": false, "reason": "No active campaign world.", "look": {}, "name": ""}
	if float(game.day) > 1.0:
		return {"ok": false, "reason": "Character design is only allowed on day 1.", "look": {}, "name": ""}
	var ph: Dictionary = game.world.get("player_house", {})
	if not ph.is_empty() and str(ph.get("ruler_uid", "")) != person_uid:
		return {"ok": false, "reason": "Character design is only allowed for the player's ruler.", "look": {}, "name": ""}
	var opts: Dictionary = options(game, person_uid)
	if opts.is_empty():
		return {"ok": false, "reason": "This person is not a living registered character.", "look": {}, "name": ""}
	if not (design is Dictionary):
		return {"ok": false, "reason": "Character design must be a dictionary.", "look": {}, "name": ""}
	for k in design:
		if not ALLOWED_DESIGN_KEYS.has(str(k)):
			return {"ok": false, "reason": "Unknown character design option: %s." % str(k), "look": {}, "name": ""}
	var first: String = str(opts["first_name"])
	if design.has("first_name") or design.has("name"):
		var raw_first: String = str(design.get("first_name", design.get("name", "")))
		var nv: Dictionary = _validate_first_name(raw_first)
		if not bool(nv["ok"]):
			return {"ok": false, "reason": str(nv["reason"]), "look": {}, "name": ""}
		first = str(nv["first_name"])
	var raw_look: Dictionary = {}
	if design.has("look"):
		if not (design["look"] is Dictionary):
			return {"ok": false, "reason": "Character look must be a dictionary.", "look": {}, "name": ""}
		var dl: Dictionary = design["look"]
		for k in dl:
			raw_look[str(k)] = dl[k]
	for k in ["skin", "hair", "seed", "female_set", "beard", "beard_style"]:
		if design.has(k) and not raw_look.has(k):
			raw_look[k] = design[k]
	var choices: Dictionary = opts["choices"]
	var clean_look: Dictionary = {}
	for k in raw_look:
		var key: String = str(k)
		if not choices.has(key):
			return {"ok": false, "reason": "Look key '%s' is not valid for this character's race and sex." % key, "look": {}, "name": ""}
		var allowed: Array = choices[key]
		var val: Variant = raw_look[key]
		if key in ["skin", "hair"]:
			if not (val is String):
				return {"ok": false, "reason": "Look '%s' must be a colour string." % key, "look": {}, "name": ""}
			var matched: String = ""
			for item in allowed:
				var entry: Dictionary = item
				if str(entry["value"]).to_lower() == str(val).to_lower():
					matched = str(entry["value"])
					break
			if matched == "":
				return {"ok": false, "reason": "Look '%s' value is not in this race's palette." % key, "look": {}, "name": ""}
			clean_look[key] = matched
		elif key == "beard":
			if not (val is bool):
				return {"ok": false, "reason": "Look 'beard' must be a boolean.", "look": {}, "name": ""}
			clean_look["beard"] = bool(val)
		elif key in ["seed", "female_set", "beard_style"]:
			if not (val is int or (val is float and float(val) == floor(float(val)))):
				return {"ok": false, "reason": "Look '%s' must be an integer." % key, "look": {}, "name": ""}
			var iv: int = int(val)
			var ok_val: bool = false
			for item in allowed:
				var entry: Dictionary = item
				if int(entry["value"]) == iv:
					ok_val = true
					break
			if not ok_val:
				return {"ok": false, "reason": "Look '%s' value %d is out of range." % [key, iv], "look": {}, "name": ""}
			clean_look[key] = iv
	if clean_look.has("beard_style") and not clean_look.has("beard"):
		clean_look["beard"] = true
	var focus: String = str(design.get("focus", "")).strip_edges().to_lower()
	if focus != "" and not FOCUS_SKILLS.has(focus):
		return {"ok": false, "reason": "Focus must be one of martial, stewardship, diplomacy or intrigue.", "look": {}, "name": ""}
	var fam_name: String = str(opts["family_name"])
	var full_name: String = (first + " " + fam_name) if fam_name != "" else first
	return {
		"ok": true,
		"reason": "",
		"look": clean_look,
		"name": full_name,
		"first_name": first,
		"focus": focus,
	}

static func apply(game, person_uid: String, design: Dictionary) -> Dictionary:
	if game == null or not (game.world is Dictionary):
		return {"ok": false, "reason": "No active campaign world."}
	if float(game.day) > 1.0:
		return {"ok": false, "reason": "Character design can only be applied on day 1."}
	var ph: Dictionary = game.world.get("player_house", {})
	if ph.is_empty() or str(ph.get("ruler_uid", "")) != person_uid:
		return {"ok": false, "reason": "Character design is only allowed for the player's ruler."}
	var pre: Dictionary = preview(game, person_uid, design)
	if not bool(pre.get("ok", false)):
		return {"ok": false, "reason": str(pre.get("reason", "Invalid character design."))}
	var loc: Dictionary = Dynasty._person(game, person_uid)
	if loc.is_empty():
		return {"ok": false, "reason": "This person is not a living registered character."}
	var e: Dictionary = loc["econ"]
	var p: Array = loc["person"]
	var first: String = str(pre["first_name"])
	var full_name: String = str(pre["name"])
	var look: Dictionary = (pre["look"] as Dictionary).duplicate(true)
	var focus: String = str(pre.get("focus", ""))
	p[7] = full_name
	ph["ruler_name"] = full_name
	var head: Dictionary = e.get("head", {})
	if str(head.get("person_uid", "")) == person_uid:
		head["name"] = full_name
	var row: Dictionary = Dynasty.person(game, person_uid)
	var u: Unit = Dynasty.bound_unit(game, row)
	var prev_design: Dictionary = ph.get("design", {}) if ph.get("design") is Dictionary else {}
	var prev_skill: String = str(prev_design.get("focus_skill", FOCUS_SKILLS.get(str(prev_design.get("focus", "")), "")))
	var prev_bonus: int = int(prev_design.get("focus_bonus", FOCUS_BONUS if prev_skill != "" else 0))
	var already_applied: bool = bool(prev_design.get("focus_applied", false))
	var focus_unit: int = int(prev_design.get("focus_unit", -1))
	var skill_key: String = str(FOCUS_SKILLS.get(focus, ""))
	if already_applied and prev_skill != "" and prev_skill != skill_key:
		var prev_u: Unit = u if (u != null and (focus_unit == int(u.uid) or focus_unit < 0)) else null
		if prev_u == null and focus_unit >= 0:
			var prev_row: Dictionary = row.duplicate()
			prev_row["unit_uid"] = focus_unit
			prev_u = Dynasty.bound_unit(game, prev_row)
		if prev_u != null and prev_bonus > 0:
			var restored: int = maxi(0, int(prev_u.skills.get(prev_skill, 0)) - prev_bonus)
			if restored > 0:
				prev_u.skills[prev_skill] = restored
			else:
				prev_u.skills.erase(prev_skill)
		already_applied = false
		focus_unit = -1
	var record: Dictionary = {
		"person_uid": person_uid,
		"first_name": first,
		"look": look.duplicate(true),
		"focus": focus,
		"focus_skill": skill_key,
		"focus_bonus": FOCUS_BONUS if skill_key != "" else 0,
		"focus_applied": already_applied,
		"focus_unit": focus_unit,
	}
	ph["design"] = record
	if u != null:
		u.name = full_name
		for k in look:
			u.look[str(k)] = look[k]
		if skill_key != "" and (not already_applied or focus_unit != int(u.uid)):
			u.skills[skill_key] = int(u.skills.get(skill_key, 0)) + FOCUS_BONUS
			record["focus_applied"] = true
			record["focus_unit"] = int(u.uid)
	return {
		"ok": true,
		"reason": "",
		"name": full_name,
		"look": look.duplicate(true),
		"focus": focus,
	}

static func look_for(game, person_uid: String) -> Dictionary:
	if game == null or not (game.world is Dictionary) or person_uid == "":
		return {}
	var ph: Dictionary = game.world.get("player_house", {})
	if not (ph.get("design") is Dictionary):
		return {}
	var d: Dictionary = ph["design"]
	if str(d.get("person_uid", "")) != person_uid:
		return {}
	var look: Dictionary = d.get("look", {}) if d.get("look") is Dictionary else {}
	return look.duplicate(true)

static func apply_to_unit(game, person_uid: String, u: Unit) -> void:
	if u == null or game == null or not (game.world is Dictionary) or person_uid == "":
		return
	var look: Dictionary = look_for(game, person_uid)
	if not look.is_empty():
		for k in look:
			u.look[str(k)] = look[k]
	var ph: Dictionary = game.world.get("player_house", {})
	if not (ph.get("design") is Dictionary):
		return
	var d: Dictionary = ph["design"]
	if str(d.get("person_uid", "")) != person_uid:
		return
	var focus: String = str(d.get("focus", ""))
	var skill_key: String = str(FOCUS_SKILLS.get(focus, ""))
	var focus_unit: int = int(d.get("focus_unit", -1))
	if skill_key != "" and (not bool(d.get("focus_applied", false)) or focus_unit != int(u.uid)):
		u.skills[skill_key] = int(u.skills.get(skill_key, 0)) + FOCUS_BONUS
		d["focus_applied"] = true
		d["focus_unit"] = int(u.uid)

static func merge_into_spec(spec: Dictionary, look: Dictionary) -> void:
	if look.is_empty():
		return
	for k in look:
		var key: String = str(k)
		if key in ["skin", "hair"] and look[key] is String:
			spec[key] = Color(str(look[key]))
		else:
			spec[key] = look[key]

static func after_load(game) -> void:
	if game == null or not (game.world is Dictionary):
		return
	var ph: Dictionary = game.world.get("player_house", {})
	if not (ph.get("design") is Dictionary):
		return
	var d: Dictionary = ph["design"]
	if d.has("focus_bonus"):
		d["focus_bonus"] = int(d["focus_bonus"])
	if d.has("focus_applied"):
		d["focus_applied"] = bool(d["focus_applied"])
	if d.has("focus_unit"):
		d["focus_unit"] = int(d["focus_unit"])
	if d.get("look") is Dictionary:
		var look: Dictionary = d["look"]
		for k in ["seed", "female_set", "beard_style"]:
			if look.has(k):
				look[k] = int(look[k])
		if look.has("beard"):
			look["beard"] = bool(look["beard"])
