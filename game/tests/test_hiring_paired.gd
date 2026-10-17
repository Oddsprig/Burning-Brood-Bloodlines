extends RefCounted
## Same-input comparison against frozen v0.035 methods, including dictionary order.
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
	Game.day = original_day
	print("HIRING PAIRED checks=", checks, " failures=", fails)
	return fails
