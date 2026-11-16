extends RefCounted
## Same-input comparison against the v0.035 methods, including dictionary order.
## The fixtures keep the original (slow) algorithms, with the intended post-v0.035
## design rules synced into their helpers: the labour-market/farm-cash-flow pass
## (commit 98a752c: staff_left_day, grain-backed farm places, the owner's food
## reserve in fund_farm, per-worker field hands), domestic-animal draught
## (v0.086, commit 11c0add) and Academy named-researcher places (v0.089,
## commits 5aa9bac and bc028fa). The exact-equality check is unchanged.
const OLD_BIZ := preload("res://tests/fixtures/businesses_v035_hiring.gd")
const OLD_FAM := preload("res://tests/fixtures/families_v035_hiring.gd")
var fails := 0
var checks := 0
var reported_cases := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", label)

func encoded(value: Variant) -> String:
	return JSON.stringify(value, "", false, true)

# v0.100: report one leaf (including dictionary insertion order), never a town dump.
func difference_values(expected: Variant, actual: Variant, path: String) -> String:
	return "%s expected=%s actual=%s" % [path, encoded(expected).left(160), encoded(actual).left(160)]

func first_difference(expected: Variant, actual: Variant, path: String = "$") -> String:
	if encoded(expected) == encoded(actual): return ""
	if expected is Dictionary and actual is Dictionary:
		var expected_keys: Array = expected.keys()
		var actual_keys: Array = actual.keys()
		for i in mini(expected_keys.size(), actual_keys.size()):
			if str(expected_keys[i]) != str(actual_keys[i]):
				return difference_values(str(expected_keys[i]), str(actual_keys[i]), "%s.keys()[%d]" % [path, i])
			var diff := first_difference(expected[expected_keys[i]], actual[actual_keys[i]], "%s[%s]" % [path, encoded(str(expected_keys[i]))])
			if not diff.is_empty(): return diff
		if expected_keys.size() != actual_keys.size():
			var i := mini(expected_keys.size(), actual_keys.size())
			return difference_values(str(expected_keys[i]) if i < expected_keys.size() else "<missing>", str(actual_keys[i]) if i < actual_keys.size() else "<missing>", "%s.keys()[%d]" % [path, i])
	elif (expected is Array or typeof(expected) >= TYPE_PACKED_BYTE_ARRAY) and (actual is Array or typeof(actual) >= TYPE_PACKED_BYTE_ARRAY):
		for i in mini(expected.size(), actual.size()):
			var diff := first_difference(expected[i], actual[i], "%s[%d]" % [path, i])
			if not diff.is_empty(): return diff
		if expected.size() != actual.size():
			var i := mini(expected.size(), actual.size())
			return difference_values(expected[i] if i < expected.size() else "<missing>", actual[i] if i < actual.size() else "<missing>", "%s[%d]" % [path, i])
	return difference_values(expected, actual, path)

func operate(e: Dictionary, original: bool, mode: String) -> int:
	var start := Time.get_ticks_usec()
	if mode == "refresh":
		for repeat_i in 20:
			if original: OLD_BIZ.refresh_hiring(e)
			else: Businesses.refresh_hiring(e)
	else:
		for f in e["fams"]:
			if original: OLD_FAM.reassign(e, f)
			else: Families.reassign(e, f)
	return Time.get_ticks_usec() - start

# v0.100: continue raw post-operation copies through a same-day head change,
# v0.100: then persist work names before any explicit cache normalization.
func continuation(e: Dictionary) -> Dictionary:
	for f in e["fams"]:
		if f.get("estate", false) or not f.has("pp"): continue
		var head := Persons.head_of(f)
		if head.is_empty() or int(head[6]) != 0: continue
		var successor := false
		for p in Persons.pp_read(f):
			if int(p[0]) != int(head[0]) and int(p[6]) == 0 and not Persons.AWAY.has(String(p[4])):
				successor = true
		if not successor: continue
		head[6] = 1
		var sex: String = ["m", "f"][int(head[2])]
		f[sex] = int(f[sex]) - 1; f["old"] = int(f["old"]) + 1
	for f in e["fams"]:
		# v0.100: force the next work-history observation even if job counts stayed put.
		f.erase("wsig")
		Persons.track_jobs(e, f, float(e.get("day", 0)))
	var titles := []
	for b in e["biz"]: titles.append(Businesses.title(e, b))
	return {"titles": titles, "town": e}

func pair(e: Dictionary, mode: String, lap: int, label: String) -> Array:
	var before: Dictionary = e.duplicate(true)
	var after: Dictionary = e.duplicate(true)
	var old_us := 0; var new_us := 0
	if lap % 2 == 0:
		old_us = operate(before, true, mode); new_us = operate(after, false, mode)
	else:
		new_us = operate(after, false, mode); old_us = operate(before, true, mode)
	# v0.100: preserve cache timing until titles and saved job histories observe it.
	var before_next := continuation(before.duplicate(true))
	var after_next := continuation(after.duplicate(true))
	var next_equal := encoded(before_next) == encoded(after_next)
	check(next_equal, label + ": exact same-day head-change continuation, titles and job histories")
	var case_key := "%s|%s|%s" % [label, e.get("identity_scope", e.get("culture", "?")), encoded(e.get("day", 0))]
	if not next_equal and not reported_cases.has(case_key + "|continuation"):
		reported_cases[case_key + "|continuation"] = true
		printerr("HIRING CONTINUATION DIFF ", case_key, " lap=", lap)
		printerr("  ", first_difference(before_next, after_next))
	# v0.100: e._who is Businesses' derived business-name cache
	# v0.100: (businesses.gd _who: built from fams, validated by d/n/p/h).
	# v0.100: Its names are observable above. The fixture's slow _best_places
	# v0.100: probes every open Academy place (Academy.hiring_places ->
	# v0.100: Persons.work -> Businesses.title), refreshing it; the fast game
	# v0.100: path skips probes that cannot win, leaving its copy stale.
	# v0.100: After that continuation, refresh both originals: all fields still compare exactly.
	if before.has("_who") and after.has("_who"):
		Businesses._who(before); Businesses._who(after)
	var equal := encoded(before) == encoded(after)
	check(equal, label + ": exact full town economy, cash, work, wage facts and insertion order")
	# v0.100: repeated timing laps share a case; each town/day still gets its own first mismatch.
	if not equal and not reported_cases.has(case_key):
		reported_cases[case_key] = true
		printerr("HIRING DIFF ", case_key, " lap=", lap)
		printerr("  ", first_difference(before, after))
	return [old_us, new_us]

# v0.100: reproduce the fixture's current-day cache versus the skipped probe's
# v0.100: yesterday cache, then change heads before either observes the new name.
func same_day_head_change() -> void:
	var owner := Families._blank(0)
	owner["name"] = "Cache"; owner["m"] = 2; owner["homes"] = 1
	owner["pp"] = [[100, 0, 0, -100.0, "", -1, 0, "Aldric Cache", -1, -1, -1, "", []],
		[101, 0, 0, -50.0, "", -1, 0, "Bram Cache", -1, -1, -1, "", []]]
	var worker := Families._blank(1)
	worker["name"] = "Worker"; worker["m"] = 1; worker["homes"] = 1; worker["jobs"] = {"0": 1}
	worker["pp"] = [[102, 0, 0, -25.0, "", -1, 0, "Corin Worker", -1, -1, -1, "", []]]
	var e := {"culture": "middle", "day": 0, "fams": [owner, worker],
		"biz": [{"id": 0, "type": "woodcutter", "owner": 0, "wage": 1.0}]}
	Businesses._who(e)
	e["day"] = 1
	var before: Dictionary = e.duplicate(true)
	var after: Dictionary = e.duplicate(true)
	Businesses._who(before)
	check(int(before["_who"]["d"]) == 1 and int(after["_who"]["d"]) == 0, "head-change fixture starts with different cache ages")
	var expected := continuation(before)
	var actual := continuation(after)
	var title := "Bram Cache's %s" % String(TownEcon.data()["businesses"]["woodcutter"]["name"])
	check(expected["titles"][0] == title and actual["titles"][0] == title, "same-day head change reaches both business titles")
	var job := "%s@%s" % [Recruits.job_title(after, after["biz"][0]), title]
	check(before["fams"][1]["pp"][0][Persons.JOB] == job and after["fams"][1]["pp"][0][Persons.JOB] == job
		and before["fams"][1]["pp"][0][Persons.HIST][-1][2] == job and after["fams"][1]["pp"][0][Persons.HIST][-1][2] == job, "same-day head change reaches both saved jobs and life histories")
	check(encoded(expected) == encoded(actual), "head-change fixture has exact full continuation equality")

func median(samples: Array) -> float:
	var ordered := samples.duplicate(); ordered.sort()
	var m := ordered.size() / 2
	return float(ordered[m]) if ordered.size() % 2 else (float(ordered[m - 1]) + float(ordered[m])) / 2.0

# v0.100: three adults leave for service; field output must retain every ordered
# v0.100: set_job update, not just the same final worker count (a418609).
func field_departures() -> void:
	var estate := Families.make_estate({"name": "Field departure fixture"})
	estate["land"] = {"grain": 67}; estate["herd"] = {"sheep": 1}; estate["ox"] = 0; estate["farm"] = 0
	var worker := Families._blank(1)
	worker["m"] = 8; worker["serve"] = {"militia": 3}; worker["jobs"] = {"0": 8}
	var business := {"id": 0, "type": "estate", "owner": -1, "workers": 8, "cap": 8, "wage": 1.0, "till": 0.0, "closed": false}
	var e := {"identity_scope": "field-departures", "day": 0, "fams": [estate, worker], "biz": [business],
		"estate_biz": 0, "hands": 0, "idle_n": 0, "open_n": 0, "cjcap": {}, "cjused": {}, "wacres": {}, "wherd": {}}
	estate["worked"] = 8.0 / Families.need_hands(estate, e)
	e["wacres"] = {"grain": 67.0 * float(estate["worked"])}
	e["wherd"] = {"sheep": float(estate["worked"])}
	pair(e, "reassign", 0, "field departures retain per-hand worked totals")

func run(_tree: SceneTree) -> int:
	reported_cases.clear()
	var saved := OS.get_environment("PERF_SAVE")
	WorldGen.gen_size = "normal"
	if saved.is_empty():
		Game.new_game(2026)
	else:
		var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		check(file != null, "isolated save writable")
		if file == null: return fails
		file.store_string(FileAccess.get_file_as_string(saved)); file.close()
		check(Game.load_game(), "real saved campaign loads")
		if fails: return fails
	TownEcon.prof_on = false
	var towns := []; var cultures := {}
	for town in Game.world["towns"].values():
		if TownEcon.has_econ(town):
			towns.append(town)
			cultures[String(town["econ"]["culture"])] = true
	check(not towns.is_empty(), "real towns available")
	print("HIRING PAIRED saved=", not saved.is_empty(), " towns=", towns.size(), " cultures=", cultures.keys())
	field_departures()
	same_day_head_change()
	var timed_modes := [] if OS.get_environment("HIRING_EDGES_ONLY") == "1" else ["refresh", "reassign"]
	for mode in timed_modes:
		var old_times := []; var new_times := []
		for lap in 8:
			var old_us := 0; var new_us := 0
			for town in towns:
				var times := pair(town["econ"], mode, lap, mode)
				old_us += times[0]; new_us += times[1]
			if lap > 0: old_times.append(old_us); new_times.append(new_us)
			print("HIRING PAIRED ", mode, " lap=", lap, " original_us=", old_us, " candidate_us=", new_us)
		print("HIRING PAIRED ", mode, " median_original_us=", median(old_times), " median_candidate_us=", median(new_times))
	# An equal-wage mixture preserves the original unstable sort's input and
	# full array. Capacity/funding/closure changes are observed on every call.
	for town in towns:
		var e: Dictionary = town["econ"].duplicate(true)
		for b in e["biz"]:
			b["wage"] = 10.0
			b["cap"] = int(b["workers"]) + (int(b["id"]) % 4)
			b["closed"] = int(b["id"]) % 7 == 0
			b["till"] = 0.0 if int(b["id"]) % 3 else 100.0
		pair(e, "refresh", 0, "ties/capacity/funding/closure")
		for b in e["biz"]:
			b["closed"] = false; b["cap"] = int(b["workers"])
		pair(e, "refresh", 1, "no vacancies")
	var tested_cultures := {}
	var original_day := Game.day
	for town in towns:
		var culture := String(town["econ"]["culture"])
		if tested_cultures.has(culture): continue
		tested_cultures[culture] = true
		for day in [0.0, float(Calendar.DAYS_PER_SEASON), float(EconGen.YEAR_DAYS)]:
			var e: Dictionary = town["econ"].duplicate(true)
			e["day"] = day; Game.day = day
			var plots: Dictionary = e.get("plots", {})
			plots.erase("crop_work_acres"); plots["crop_count"] = -1
			if e.has("hd"):
				e["hd"].erase("_labour"); e["hd"]["_labour_ver"] = -1
			pair(e, "reassign", int(day), "cold crop/herd caches and season/year boundary")
	# v0.100: cohort holds two anonymous jobs then two named Academy jobs; when
	# the prefix employer closes with no replacement offers, reassignment must
	# drop the now-anonymous Academy places instead of keeping them on early return.
	var acad_town: Dictionary = {}
	for town in towns:
		if not Academy.biz_of(town["econ"]).is_empty():
			acad_town = town
			break
	if acad_town.is_empty() and not towns.is_empty():
		acad_town = towns[0]
	if not acad_town.is_empty():
		var e: Dictionary = acad_town["econ"].duplicate(true)
		e["day"] = 0.0; Game.day = 0.0
		if Academy.biz_of(e).is_empty():
			Academy.gen_town({"capital": true}, e)
		var academy_b: Dictionary = Academy.biz_of(e)
		var academy_bid := int(academy_b["id"])
		var prefix_b: Dictionary = {}
		for b in e["biz"]:
			if int(b["id"]) != academy_bid and String(b["type"]) != "farm":
				prefix_b = b
				break
		var cohort: Dictionary = {}
		for f in e["fams"]:
			if not f.get("estate", false) and Population.is_cohort(f):
				cohort = f
				break
		if cohort.is_empty():
			for f in e["fams"]:
				if not f.get("estate", false):
					cohort = f
					break
		check(not prefix_b.is_empty() and not cohort.is_empty(), "cohort prefix-closure fixture ready")
		if not prefix_b.is_empty() and not cohort.is_empty():
			var prefix_bid := int(prefix_b["id"])
			e["cjcap"] = {}; e["cjused"] = {}; e["barn"] = {}; e.erase("harvest_book")
			# v0.100: clear physical work too, so the source cohort's plots and
			# herds cannot consume the four adults or open a replacement farm.
			e.erase("plots"); e.erase("hd")
			e["hands"] = 0; e["idle_n"] = 0
			for f in e["fams"]:
				if not is_same(f, cohort) and not f.get("estate", false):
					f["gone"] = true; f["jobs"] = {}; f["owns"] = []; f["keeps"] = []
			for b in e["biz"]:
				b["workers"] = 0; b["cap"] = 0; b["till"] = 0.0; b["owed"] = 0.0; b["closed"] = false
			cohort["gone"] = false; cohort["owns"] = []; cohort["keeps"] = []
			cohort["land"] = {}; cohort["herd"] = {}; cohort["ox"] = 0; cohort["farm"] = -1
			cohort["hands"] = 0; cohort["serve"] = {}; cohort["unpaid"] = 0
			cohort.erase("hl"); cohort.erase("cj")
			cohort["m"] = 2; cohort["f"] = 2; cohort["old"] = 0; cohort["kids"] = 0
			Population.initialize(e, cohort)
			var rng := RandomNumberGenerator.new(); rng.seed = 20260100
			Population.promote(e, cohort, 0.0, rng)
			Population.promote(e, cohort, 0.0, rng)
			prefix_b["cap"] = 2; prefix_b["workers"] = 2; prefix_b["wage"] = 12.0; prefix_b["till"] = 240.0
			academy_b["cap"] = 2; academy_b["workers"] = 2; academy_b["wage"] = 10.0; academy_b["till"] = 240.0; academy_b["research_idle"] = false
			cohort["jobs"] = {str(prefix_bid): 2, str(academy_bid): 2}; cohort["idle"] = 0
			TownEcon.recount(e)
			check(Population.anonymous(cohort, 0) + Population.anonymous(cohort, 1) == 2
				and Academy._named_places(Persons.work(e, cohort), academy_bid) == 2, "two anonymous prefix jobs precede two named Academy jobs")
			pair(e, "reassign", 1, "cohort retains valid named Academy jobs before prefix closure")
			prefix_b["closed"] = true
			Businesses.refresh_hiring(e)
			check((e["open"] as Array).is_empty() and (e["cjcap"] as Dictionary).is_empty(), "prefix closure has no replacement regular or casual offers")
			pair(e, "reassign", 0, "cohort prefix closure invalidates retained Academy jobs")
			var after_e: Dictionary = e.duplicate(true)
			Families.reassign(after_e, after_e["fams"][int(cohort["id"])])
			var after_cohort: Dictionary = after_e["fams"][int(cohort["id"])]
			check((after_cohort["jobs"] as Dictionary).is_empty() and int(after_e["biz"][prefix_bid]["workers"]) == 0
				and int(after_e["biz"][academy_bid]["workers"]) == 0 and int(after_cohort["idle"]) == 4
				and int(after_e["idle_n"]) == 4 and not Families.assignments_stale(after_cohort), "cohort prefix closure drops now-anonymous Academy jobs and leaves all four adults idle")
	Game.day = original_day
	print("HIRING PAIRED checks=", checks, " failures=", fails)
	return fails
