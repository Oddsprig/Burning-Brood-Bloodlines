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

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: fails += 1; printerr("FAIL: ", label)

func encoded(value: Variant) -> String:
	return JSON.stringify(value, "", false, true)

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

func pair(e: Dictionary, mode: String, lap: int, label: String) -> Array:
	var before: Dictionary = e.duplicate(true)
	var after: Dictionary = e.duplicate(true)
	var old_us := 0; var new_us := 0
	if lap % 2 == 0:
		old_us = operate(before, true, mode); new_us = operate(after, false, mode)
	else:
		new_us = operate(after, false, mode); old_us = operate(before, true, mode)
	check(encoded(before) == encoded(after), label + ": exact full town economy, cash, work, wage facts and insertion order")
	return [old_us, new_us]

func median(samples: Array) -> float:
	var ordered := samples.duplicate(); ordered.sort()
	var m := ordered.size() / 2
	return float(ordered[m]) if ordered.size() % 2 else (float(ordered[m - 1]) + float(ordered[m])) / 2.0

func run(_tree: SceneTree) -> int:
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
