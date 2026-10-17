extends RefCounted
## Short introductions use the offered person's records, including older saved
## verbose backstories. Family assets and another person's service stay in Details.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	for culture in ["middle", "orc", "moon_elf", "dwarf"]:
		for sex in [0, 1]:
			_check_record(culture, sex)
	_check_legacy()
	return fails

func _fixture(culture: String, sex: int) -> Dictionary:
	var u := Unit.new()
	u.uid = 501
	u.name = "Recorded Worker"
	u.sex = sex
	u.born = -2000.0
	u.family = 0
	u.home_town = "brief_test"
	u.title = "out of work"
	u.ambition = "buy land and settle"
	u.backstory = "The family keeps 400 acres and 99 sheep. A lengthy saved family account."
	var p := [21, 0, sex, u.born, "hire", u.uid, 0, u.name, -1, -1, -1, "", []]
	Persons.log_life(p, 10.0, "job", "tanner's hand@Recorded Tannery")
	Persons.log_life(p, 40.0, "serve", "guard")
	Persons.log_life(p, 70.0, "home", "")
	Persons.remember_unpaid(p, "guard", 12.0, 70.0, 30.0)
	var other := [22, 0, 1 - sex, -2100.0, "", -1, 0, "Other Worker", -1, -1, -1, "", []]
	Persons.log_life(other, 20.0, "serve", "army")
	var f := {"id": 0, "name": "Record", "pp": [p, other], "homes": 1, "m": 1, "f": 1, "old": 0, "kids": 0,
		"purse": 100.0, "land": {"barley": 400}, "herd": {"sheep": 99}, "hungry": 1, "unpaid": 0, "debt": 98765.0, "idle": 1}
	var town := {"id": u.home_town, "name": "Recorded Town", "culture": culture,
		"econ": {"culture": culture, "day": 90.0, "stock": {}, "fams": [f]}}
	return {"unit": u, "person": p, "family": f, "town": town}

func _check_record(culture: String, sex: int) -> void:
	var x := _fixture(culture, sex)
	var u: Unit = x["unit"]
	var t: Dictionary = x["town"]
	var before := t.duplicate(true)
	var stored := u.backstory
	var st := RecruitBrief.story_data(u, t)
	var text := String(st["text"])
	check(text.contains("Recorded Tannery") and text.contains("town watch") and text.contains("returned unpaid"), "own work and unpaid service missing: " + text)
	check(text.contains("food short at home") and text.contains(u.ambition), "current reason or ambition missing: " + text)
	check(not text.contains("army") and not text.contains("400") and not text.contains("99") and not text.contains("98765"), "brief borrowed another life or inventories: " + text)
	check(text.contains("she ") if sex == 1 else text.contains("he "), "wrong personal pronoun: " + text)
	check(st["parts"].size() <= 3 and text.split(" ", false).size() < 80, "brief is too long: " + text)
	check(RecruitBrief.story(u, t) == text, "brief is not deterministic")
	check(RecruitBrief.full_story(u, t) == stored and u.backstory == stored and t == before, "presentation changed stored records")
	var last := -1.0
	for part in st["parts"]:
		check(not part["facts"].is_empty(), "sentence lacks a source")
		for must in part["must"]:
			check(String(part["s"]).contains(String(must)), "sentence dropped its source fact")
		for day in part["days"]:
			check(float(day) >= last, "own life told out of order")
			last = float(day)
	# An older saved recruit lost its uid link; name, sex and birth still identify it.
	x["person"][5] = -1
	check(RecruitBrief.story(u, t) == text, "old saved recruit ignored living register")
	check(RecruitBrief.family_index(u, t) == 0, "legacy identity resolves its actual family link")
	# A moved household keeps its authoritative uid despite the stale family index.
	x["person"][5] = u.uid
	t["econ"]["fams"] = [{"id": 0, "name": "Empty", "pp": []}, x["family"]]
	check(RecruitBrief.story(u, t) == text, "moved household lost personal history")
	check(RecruitBrief.family_index(u, t) == 1 and u.family == 0, "Family link follows the moved person's uid rather than stale saved index")
	var foreign: Dictionary = t.duplicate()
	foreign["id"] = "foreign_town"
	check(RecruitBrief.family_index(u, foreign) == -1, "foreign town rejects even a matching person uid")
	var unknown := Unit.new()
	unknown.uid = 999
	unknown.name = "Unregistered Person"
	unknown.home_town = u.home_town
	unknown.family = 1
	check(RecruitBrief.family_index(unknown, t) == -1, "unknown person gets no Family link from a plausible saved index")
	# State changes affect the reason, without parsing the old saved narrative.
	x["family"]["hungry"] = 0
	x["family"]["debt"] = 0.0
	x["family"]["unpaid"] = 2
	check(RecruitBrief.story(u, t).contains("household wages unpaid"), "current unpaid hardship missing")

func _check_legacy() -> void:
	var u := Unit.new()
	u.name = "Legacy Recruit"
	u.title = "carpenter's hand"
	u.ambition = "see the world"
	u.backstory = "A long old household account of 99 sheep and 400 acres."
	var text := RecruitBrief.story(u, {"name": "Old Town"})
	check(text.contains(u.title) and text.contains(u.ambition) and text.contains("steady pay"), "legacy unit facts missing")
	check(not text.contains("99") and not text.contains("400"), "legacy inventory leaked into brief")
	check(RecruitBrief.full_story(u, {}) == u.backstory, "legacy full details were discarded")
	var before := {"id": "other", "name": "Other Town", "econ": {"stock": {}, "fams": []}}
	u.home_town = "home"
	check(not RecruitBrief.story(u, before).contains("Other Town"), "visitor given wrong home town")
