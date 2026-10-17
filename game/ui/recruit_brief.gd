class_name RecruitBrief
extends RefCounted
## The tavern's short introduction. The stored Backstory stays available in Details;
## old saves get the same introduction from their living register, without rewriting it.

const FORCES := {"guard": "on the town watch", "reserve": "in the militia reserve",
	"militia": "in the militia", "army": "with the army", "caravan": "with a caravan",
	"bandit": "with an outlaw band", "deserter": "as an army deserter", "company": "with your company"}

static func story(u: Unit, town: Dictionary) -> String:
	return String(story_data(u, town)["text"])

## The Family link follows the same registered identity as the story, including
## saved recruits whose household index is stale. Unknown or foreign people have no link.
static func family_index(u: Unit, town: Dictionary) -> int:
	var record := _record(u, town)
	if record.is_empty():
		return -1
	var families: Array = town["econ"].get("fams", [])
	return families.find(record["family"])

## Sentence facts and dates make the brief auditable like the full Backstory.
## Presentation reads records only: no regeneration, binding, or change to saved text.
static func story_data(u: Unit, town: Dictionary) -> Dictionary:
	var record := _record(u, town)
	var p: Array = record.get("person", [])
	var f: Dictionary = record.get("family", {})
	var e: Dictionary = town.get("econ", {})
	var pro := "she" if u.sex == 1 else "he"
	var pos := "her" if u.sex == 1 else "his"
	var now := float(e.get("day", Game.day))
	var parts := []
	var life := _own_beats(p, pro, now)
	var place := String(town.get("name", "")) if u.home_town == "" or u.home_town == String(town.get("id", "")) else ""
	if not life.is_empty():
		for i in life.size():
			var beat: Dictionary = life[i]
			if i == 0 and place != "":
				beat["s"] = "From %s, %s" % [place, beat["s"]]
				beat["facts"].append("home_town")
				beat["must"].append(place)
			parts.append(_close(beat))
	else:
		var intro := pro + (" comes from " + place if place != "" else "")
		var title := u.title.strip_edges()
		var facts := ["home_town"] if place != "" else ["for_hire"]
		var must := [place] if place != "" else []
		if title != "":
			match title:
				"out of work", "in the poorhouse", "past working age":
					intro += (" and is " if place != "" else " is ") + title
				_:
					var article := "an " if title.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a "
					intro += (", " if place != "" else " is ") + article + title
			facts.append("unit:title")
			must.append(title)
		elif place == "":
			intro += " is looking for paid service"
		parts.append(_close({"s": intro, "facts": facts, "days": [], "must": must}))
	var reason := _reason(f)
	var ending := (String(reason["lead"]) + ", " if reason["lead"] != "" else "") + pro + " seeks steady pay"
	var facts := ["for_hire", "reason:" + String(reason["key"])]
	var ambition := u.ambition.strip_edges().replace("their", pos)
	if ambition != "":
		ending += " and hopes to " + ambition
		facts.append("unit:ambition")
	parts.append(_close({"s": ending, "facts": facts, "days": [], "must": [ambition] if ambition != "" else []}))
	return {"text": " ".join(PackedStringArray(parts.map(func(part): return String(part["s"])))), "parts": parts}

## Full narrative is deliberately separate from the tavern brief.
static func full_story(u: Unit, town: Dictionary) -> String:
	if u.backstory != "":
		return u.backstory
	var record := _record(u, town)
	if record.is_empty():
		return story(u, town)
	var e: Dictionary = town["econ"]
	var f: Dictionary = record["family"]
	var p: Array = record["person"]
	return Backstory.recruit_text(town, e, f, Persons.first_of(e, p), u.name, {}, u)

static func _record(u: Unit, town: Dictionary) -> Dictionary:
	if not TownEcon.has_econ(town) or (u.home_town != "" and u.home_town != String(town.get("id", ""))):
		return {}
	var e: Dictionary = town["econ"]
	var families: Array = e.get("fams", [])
	var ordered := []
	if u.family >= 0 and u.family < families.size():
		ordered.append(families[u.family])
	for f in families:
		if ordered.is_empty() or f != ordered[0]:
			ordered.append(f)
	# A uid remains authoritative when a household or name has changed.
	for f in ordered:
		for p in f.get("pp", []):
			if u.uid > 0 and int(p[5]) == u.uid:
				return {"family": f, "person": p}
	# Older saves can retain the name and birth day without the uid link.
	for f in ordered:
		for p in f.get("pp", []):
			if Persons.name_of(f, p, Persons.race_of(e)) != u.name or int(p[2]) != u.sex:
				continue
			if u.born > -1.0e8 and not is_equal_approx(float(p[3]), u.born):
				continue
			return {"family": f, "person": p}
	return {}

## Keep the most recent substantial job and one distinguishing experience. A family
## member's service, a household inventory, or a town event is never his own life.
static func _own_beats(p: Array, pro: String, now: float) -> Array:
	var work := {}
	var experience := {}
	var experience_weight := -1
	for span in Persons.life_spans(p):
		var code := String(span["code"])
		if code in ["job", "idle"] and float(span["to"]) >= 0.0 and float(span["to"]) - float(span["from"]) < Backstory.MIN_SPAN:
			continue
		var beat := _life(span, p, pro, now)
		if beat.is_empty():
			continue
		if code == "job":
			if work.is_empty():
				work = beat
		else:
			var weight := int({"legend": 4, "wound": 3, "serve": 2, "idle": 1}.get(code, 0))
			if weight > experience_weight:
				experience_weight = weight
				experience = beat
	var out := []
	if not work.is_empty():
		out.append(work)
	if not experience.is_empty():
		out.append(experience)
	out.sort_custom(func(a, b): return float(a["days"][0]) < float(b["days"][0]))
	return out

static func _life(span: Dictionary, p: Array, pro: String, now: float) -> Dictionary:
	var code := String(span["code"])
	var arg := String(span["arg"])
	var open := float(span["to"]) < 0.0
	var duration := Backstory.span_words((now if open else float(span["to"])) - float(span["from"]))
	var clause := ""
	var must := []
	match code:
		"job":
			clause = pro + (" works as " if open else " worked as ") + Backstory.job_words(arg)
			if not open:
				clause += " for " + duration
			must.append(String(arg.split("@")[0]))
			if arg.contains("@") and String(arg.split("@")[1]) != "":
				must.append(String(arg.split("@")[1]))
		"serve":
			if not FORCES.has(arg):
				return {}
			clause = pro + (" serves " if open else " served ") + String(FORCES[arg])
			if not open:
				clause += " for " + duration
				var memory := Persons.unpaid_memory(p, arg)
				if not memory.is_empty() and float(memory.get("returned", -1.0)) >= float(span["from"]) and is_equal_approx(float(memory.get("returned", -1.0)), float(span["to"])):
					clause += " and returned unpaid"
			must.append(String(FORCES[arg]))
		"idle":
			var state := String({"idle": "without work", "poorhouse": "in the poorhouse", "homeless": "sleeping rough"}.get(arg, ""))
			if state == "":
				return {}
			clause = pro + (" has been " if open else " spent " + duration + " ") + state
			must.append(state)
		"wound":
			clause = pro + " came home maimed"
		"legend":
			clause = pro + " made the legendary " + arg
			must.append(arg)
		_:
			return {}
	return {"s": clause, "facts": ["person:" + code], "days": [float(span["from"])], "must": must}

static func _reason(f: Dictionary) -> Dictionary:
	if f.is_empty():
		return {"key": "unknown", "lead": ""}
	if Shelter.destitute(f) or f.get("destitute", false):
		return {"key": "destitute", "lead": "With nothing left at home"}
	if int(f.get("homes", 1)) <= 0:
		return {"key": "sheltered" if f.get("shel", false) else "homeless", "lead": "With the household in the poorhouse" if f.get("shel", false) else "Without a roof at home"}
	if int(f.get("hungry", 0)) > 0:
		return {"key": "hungry", "lead": "With food short at home"}
	if int(f.get("unpaid", 0)) > 0:
		return {"key": "unpaid", "lead": "With household wages unpaid"}
	if float(f.get("debt", 0.0)) > 0.5:
		return {"key": "debt", "lead": "With debts weighing on the household"}
	if f.get("ruined", false):
		return {"key": "ruined", "lead": "With the household ruined"}
	if int(f.get("idle", 0)) > 0:
		return {"key": "idle", "lead": "With work scarce at home"}
	return {"key": "none", "lead": ""}

static func _close(part: Dictionary) -> Dictionary:
	part["s"] = Backstory._tidy(Backstory._cap(String(part["s"])) + ".")
	return part
