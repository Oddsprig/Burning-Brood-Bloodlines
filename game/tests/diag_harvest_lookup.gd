extends RefCounted
## Isolated component measurements, never a claim about whole-campaign speed.
## Clone construction, fixture production and JSON parsing are outside timing.

const HOUSEHOLDS := 150
const REPEATS := 12
const REMOVE_REPEATS := 3
const ROUNDS := 5
var old = load("res://tests/fixtures/harvest_claims_v033.gd")
var current = load("res://campaign/harvest_claims.gd")
var fails := 0
var reports := []

func fixture(dates: int, sparse: bool = false) -> Dictionary:
	var spec := []
	for _id in HOUSEHOLDS: spec.append([1, 1.0])
	var e: Dictionary = load("res://tests/test_harvest_ownership.gd").new().fixture("middle", spec)
	e["fams"] = []
	for id in HOUSEHOLDS:
		var f := Families._blank(id); f["m"] = 4; f["homes"] = 1
		e["fams"].append(f)
	old.ensure(e)
	for day in dates:
		var shares := {}
		for id in HOUSEHOLDS:
			if not sparse or id % 12 == day % 12: shares["f:%d" % id] = 1.0
		old._lot(e, "grain", shares, day, "harvest")
		e["barn"]["grain"] = int(e["barn"].get("grain", 0)) + shares.size()
	old.reserve_all(e)
	return e

func phase(core, e: Dictionary, name: String) -> int:
	var weights := {}
	for f in e["fams"]: weights["f:%d" % int(f["id"])] = 1.0
	var started := Time.get_ticks_usec()
	match name:
		"unchanged_reserve":
			for _step in REPEATS: core.reserve_all(e)
		"new_daily_reserve":
			for step in REPEATS:
				core.harvest(e, "grain", "h_grain", weights, float(weights.size()), weights.size(), 0, 0.0, 1400 + step)
				core.reserve_all(e)
		"changed_budget":
			for step in REPEATS:
				for f in e["fams"]: f["store"]["food"] = float(EconGen.YEAR_DAYS) - 0.125 if step % 2 == 0 else 0.0
				core.reserve_all(e)
		"independent_family":
			for step in REPEATS:
				for f in e["fams"]:
					f["store"]["food"] = float(EconGen.YEAR_DAYS) - 0.125 if step % 2 == 0 else 0.0
					core.reserve_food(e, f)
		"owner_filtered_take":
			for _step in REMOVE_REPEATS:
				for f in e["fams"]: core.take(e, "grain", 1, false, "f:%d" % int(f["id"]))
		"owner_keep":
			for _step in REMOVE_REPEATS:
				for f in e["fams"]: core.keep_food(e, f, 1, 8.0)
	return Time.get_ticks_usec() - started

func measure(base: Dictionary, label: String, name: String) -> void:
	var old_us := []
	var new_us := []
	var same := true
	for round_no in ROUNDS:
		var a := base.duplicate(true); var b := base.duplicate(true)
		# Alternate execution order to limit systematic warm-cache bias.
		if round_no % 2 == 0:
			old_us.append(phase(old, a, name)); new_us.append(phase(current, b, name))
		else:
			new_us.append(phase(current, b, name)); old_us.append(phase(old, a, name))
		if a != b or JSON.stringify(a, "", false, true) != JSON.stringify(b, "", false, true):
			same = false
			fails += 1; printerr("FAIL: authoritative state differs ", label, " ", name, " round ", round_no)
	var aa := old_us.duplicate(); var bb := new_us.duplicate(); aa.sort(); bb.sort()
	var result := {"fixture": label, "phase": name, "repeats": REMOVE_REPEATS if name in ["owner_filtered_take", "owner_keep"] else REPEATS, "rounds": ROUNDS,
		"baseline_us": old_us, "candidate_us": new_us, "baseline_median_us": aa[int(ROUNDS / 2)],
		"candidate_median_us": bb[int(ROUNDS / 2)], "exact_state": same}
	reports.append(result)
	print("HARVEST PERF ", JSON.stringify(result))

func late_save(phase_names: Array = []) -> void:
	var path := OS.get_environment("COPPER_HARVEST_PERF_SAVE")
	if path == "": path = ProjectSettings.globalize_path("res://../../evidence/v0.033-final-audit/checkpoint-save.json")
	if not FileAccess.file_exists(path):
		printerr("LATE SAVE unavailable: ", path); return
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var economies := []
	for t in saved["world"]["towns"].values():
		if TownEcon.has_econ(t): economies.append(t["econ"])
	print("LATE SAVE input_day=", saved["day"], " towns=", economies.size(), " path=", path)
	# Town selection is based solely on retained physical owner entries.
	economies.sort_custom(func(a, b): return entries(a) > entries(b))
	if phase_names.is_empty(): phase_names = ["unchanged_reserve", "new_daily_reserve", "changed_budget", "independent_family", "owner_filtered_take", "owner_keep"]
	for i in mini(3, economies.size()):
		var base: Dictionary = economies[i]
		var label := "authentic_day600_rank%d_lots%d_entries%d_families%d" % [i, base["harvest_book"]["lots"].get("grain", []).size(), entries(base), base["fams"].size()]
		for name in phase_names: measure(base, label, name)

func entries(e: Dictionary) -> int:
	var total := 0
	for row in e["harvest_book"]["lots"].get("grain", []): total += row["shares"].size()
	return total

func run(_tree: SceneTree) -> int:
	if OS.get_environment("COPPER_HARVEST_PERF_SCOPE") == "owner":
		var phases := ["owner_filtered_take", "owner_keep"]
		var dense := fixture(120)
		for name in phases: measure(dense, "dense_dates120", name)
		late_save(phases)
		print("HARVEST LOOKUP NARROW PERF failures=", fails)
		return fails
	for dates in [1, 60, 120, 360]:
		var base := fixture(dates)
		for name in ["unchanged_reserve", "new_daily_reserve", "changed_budget", "independent_family", "owner_filtered_take", "owner_keep"]: measure(base, "dense_dates%d" % dates, name)
	var sparse := fixture(360, true)
	for name in ["new_daily_reserve", "changed_budget", "owner_filtered_take", "owner_keep"]: measure(sparse, "sparse_dates360", name)
	late_save()
	var output := OS.get_environment("COPPER_HARVEST_PERF_OUTPUT")
	if output != "":
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file: file.store_string(JSON.stringify({"measurements": reports, "failures": fails}, "\t"))
	print("HARVEST LOOKUP PERF failures=", fails)
	return fails
