extends RefCounted
## v0.014 recruit stories (Douglas: "needs to be more of a story, less of a list"): Backstory.story tells ONE short
## story in time order from recorded facts only. Checks, on real register people after 90 days of play, in every
## culture's wording (middle, northern, eastern, orc, goblin, moon_elf, dwarf):
##   - the dated beats run in time order (the parts' days, and every "year N" in the text, never go back);
##   - every sentence is built from a recorded fact (each part names its facts) and carries the words of the facts
##     it tells (the business that stopped paying, the place he worked, the force he served with, the sum owed);
##   - 2-6 sentences, no unfilled placeholder, the same person gives the same text;
##   - every town's real recruit pool gets a story without errors.

var fails := 0

const CULTURES := ["middle", "northern", "eastern", "orc", "goblin", "moon_elf", "dwarf"]

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func run(_tree: SceneTree) -> int:
	Game.new_game(4242)
	var w: Dictionary = Game.world
	w["party"]["safe_until"] = 1.0e9
	for i in 90:
		Game.advance_time(1.0, false)
		w["encounter"] = ""
	var ids: Array = w["towns"].keys()
	ids.sort()
	var by_cul := {}
	var races := {}
	var shown := {}
	var told := 0
	for tid in ids:
		var t: Dictionary = w["towns"][tid]
		if not TownEcon.has_econ(t):
			continue
		var e: Dictionary = t["econ"]
		races[Persons.race_of(e)] = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var k := 0
		for f in e["fams"]:
			if k >= 5:
				break
			if f.get("gone", false) or f.get("estate", false):
				continue
			var p := Persons.pick_home(f, rng, false)
			if p.is_empty():
				continue
			k += 1
			var role := Recruits.person_role(e, f, p)
			var u := Recruits.make_recruit(rng, t, Recruits.kit_for(role))
			var first := Persons.first_of(e, p)
			var full := Persons.name_of(f, p, Persons.race_of(e))
			for cul in CULTURES:
				var tc: Dictionary = t.duplicate()
				tc["culture"] = cul
				var st := Backstory.story(tc, e, f, first, full, role, u)
				_check_story(st, "%s/%s %s" % [t["name"], cul, full])
				check(Backstory.story(tc, e, f, first, full, role, u)["text"] == st["text"], "%s: not the same story twice" % full)
				by_cul[cul] = int(by_cul.get(cul, 0)) + 1
				told += 1
				var beats := 0
				for part in st["parts"]:
					beats += (part["days"] as Array).size()
				if cul == String(t.get("culture", "")) and beats >= 2 and int(shown.get(cul, 0)) < 2:
					shown[cul] = int(shown.get(cul, 0)) + 1
					print("  [%s, %s] %s" % [cul, Persons.race_of(e), st["text"]])
		# the real pool (recruits.gd path): every recruit has a story
		for r in Recruits.generate_pool(t, RandomNumberGenerator.new()):
			check(r.backstory.length() > 40 and not r.backstory.contains("{"), "%s: bad pool story: %s" % [r.name, r.backstory])
	for cul in CULTURES:
		check(int(by_cul.get(cul, 0)) > 0, "no story told in %s wording" % cul)
	print("  %d stories told; cultures %s; races in the world %s" % [told, str(by_cul), str(races.keys())])
	return fails

func _check_story(st: Dictionary, who: String) -> void:
	var txt := String(st["text"])
	var parts: Array = st["parts"]
	check(txt != "" and not txt.contains("{") and not txt.contains("}") and not txt.contains("  ") and not txt.contains(" ,") and not txt.contains(".."),
		"%s: malformed story: %s" % [who, txt])
	check(parts.size() >= 2 and parts.size() <= 6, "%s: %d sentences: %s" % [who, parts.size(), txt])
	check(txt == " ".join(PackedStringArray(parts.map(func(p): return String(p["s"])))), "%s: text is not its sentences" % who)
	var last := -1.0
	for part in parts:
		var s := String(part["s"])
		check(not (part["facts"] as Array).is_empty(), "%s: a sentence from no recorded fact: %s" % [who, s])
		for m in part["must"]:
			check(s.to_lower().contains(String(m).to_lower()),"%s: sentence lacks its fact '%s': %s" % [who, m, s])
		for d in part["days"]:
			check(float(d) >= last, "%s: beats out of time order: %s" % [who, txt])
			last = maxf(last, float(d))
	# the text itself: every "year N" is the same or later than the one before
	var rx := RegEx.create_from_string("year (\\d+)")
	var y := 0
	for m in rx.search_all(txt):
		var n := int(m.get_string(1))
		check(n >= y, "%s: years out of order: %s" % [who, txt])
		y = maxi(y, n)
