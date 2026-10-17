extends RefCounted
## Exact v0.042 herd-total/cache contract without world generation or timing gates.
const BASELINE := preload("res://tests/fixtures/records_v043_baseline.gd")
var fails := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", message)

func run(_tree: SceneTree) -> int:
	var cases := [
		{"label": "absent books", "econ": {}, "want": {}},
		{"label": "legacy totals retain exact signs", "econ": {"herd": {"cattle": -7, "sheep": 0}}, "want": {"cattle": -7, "sheep": 0}},
		{"label": "empty records", "econ": {"hd": {"h": {}}}, "want": {}},
		{"label": "age conversion and every owner", "econ": _economy(), "want": {"cattle": 7, "goats": 2, "7": 1}}]
	for case in cases:
		var original: Dictionary = case["econ"]
		var actual := original.duplicate(true)
		var baseline := original.duplicate(true)
		_pair(actual, baseline, String(case["label"]) + " cold", case["want"])
		_pair(actual, baseline, String(case["label"]) + " warm", case["want"])
		_read_purity(original, String(case["label"]))
	_mutations()
	_cache_hit()
	print("HERD TOTALS V043 checks=", checks, " failures=", fails)
	return fails

func _economy() -> Dictionary:
	return {"hd": {"ver": 2.75, "_thk": "obsolete", "_th": {"wrong": 99}, "h": {
		"a": {"k": "cattle", "y": 1.9, "g": 1.9, "o": 1.9, "ow": "f"},
		"b": {"k": "cattle", "y": "3", "g": 2.75, "o": -1.75, "ow": "b"},
		"c": {"k": "sheep", "y": 2, "g": -2, "o": 0, "ow": "s"},
		"d": {"k": "sheep", "y": -4, "g": 1, "o": 0, "ow": "d"},
		"e": {"k": "goats", "y": -1, "g": 4, "o": -1, "ow": "s"},
		# Saved herd kind identifiers are strings, including legacy unknown kinds.
		"f": {"k": "7", "y": 0, "g": 1, "o": 0, "ow": "d"}}}}

func _pair(actual: Dictionary, baseline: Dictionary, label: String, want: Dictionary) -> void:
	var got := Herds.town_heads(actual)
	var frozen := BASELINE.town_heads(baseline)
	check(got == want and frozen == want, label + " independent expected totals")
	check(got == frozen and got.keys() == frozen.keys(), label + " exact totals and insertion order")
	check(actual == baseline, label + " identical derived-cache keys and contents")
	if actual.has("hd"):
		var hd: Dictionary = actual["hd"]
		check(String(hd["_thk"]) == "%d|%d" % [int(hd.get("ver", 0)), (hd["h"] as Dictionary).size()], label + " exact version/size key")
		check(is_same(got, hd["_th"]), label + " returns the existing cache dictionary")
	else:
		check(not actual.has("hd"), label + " does not initialize absent books")
		if actual.has("herd"): check(is_same(got, actual["herd"]), label + " retains legacy totals reference")

func _mutations() -> void:
	var actual := _economy()
	var baseline := actual.duplicate(true)
	var old := {"cattle": 7, "goats": 2, "7": 1}
	_pair(actual, baseline, "initial versioned cache", old)
	# The contract intentionally keys by version and size, not a second content scan.
	for e in [actual, baseline]: e["hd"]["h"]["a"]["g"] = 10
	_pair(actual, baseline, "unchanged version and size retain cache", old)
	for e in [actual, baseline]: e["hd"]["ver"] = 3
	_pair(actual, baseline, "version invalidation", {"cattle": 16, "goats": 2, "7": 1})
	for e in [actual, baseline]:
		e["hd"]["h"]["g"] = {"k": "bees", "y": 0, "g": 2, "o": 1, "ow": "f"}
	_pair(actual, baseline, "record count invalidation", {"cattle": 16, "goats": 2, "7": 1, "bees": 3})
	for e in [actual, baseline]: e["hd"]["h"].erase("a")
	_pair(actual, baseline, "record removal invalidation", {"cattle": 4, "goats": 2, "7": 1, "bees": 3})
	_read_purity(actual, "warm current records")
	# Explicitly cold read through the UI wrapper owns its cache container.
	actual["hd"].erase("_th")
	actual["hd"].erase("_thk")
	_read_purity(actual, "cold current records")

func _cache_hit() -> void:
	var actual := {"hd": {"h": {"a": {"k": "cattle", "y": 0, "g": 5, "o": 0}},
		"_thk": "0|1", "_th": {"kept": 77}}}
	var baseline := actual.duplicate(true)
	var before := actual.duplicate(true)
	_pair(actual, baseline, "exact warm hit uses cached result", {"kept": 77})
	check(actual == before, "matching cache key changes no field")
	var got := Herds.town_heads(actual)
	got["kept"] = 78
	check(actual["hd"]["_th"]["kept"] == 78, "raw warm result retains original cache alias")

func _read_purity(e: Dictionary, label: String) -> void:
	var before := e.duplicate(true)
	var actual := RecData.herds(e)
	var frozen := BASELINE.herd_heads(e)
	check(actual == frozen and actual.keys() == frozen.keys(), label + " records wrapper equals frozen backend")
	check(e == before, label + " records wrapper leaves original economy and derived caches untouched")
