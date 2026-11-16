extends RefCounted
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief. A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.
## Current 0.099 protocol controls and shared read-only validators; never a 240-day run.
const M: GDScript = preload("res://tests/economy_stability_v094.gd")
const SCHEMA: String = "economy_stability_current/1"
const APPLICATION_VERSION: String = "0.099"
const ROOT: String = "user://economy_current_0099_r2"
const RACES: Array = ["human", "orc", "goblin", "moon_elf", "dwarf", "high_elf", "dark_elf"]
# Historical timing parameters remain synthetic contract data, not runnable long modes.
const SOFT_MS: int = 40000
const DAY_MS: int = 70000
const DRAIN_END_MS: int = 115000
const ABSOLUTE_MS: int = 135000
const LIMIT_MS: int = 50000
const ZERO_SHA: String = "0000000000000000000000000000000000000000000000000000000000000000"
var _started: int = 0
var _opts: Dictionary = {"mode": "contract", "phase": "current_0099_r2", "checkpoint": 0, "batch-days": 15, "years": 2, "input-save": "", "input-sha": ""}
var _params: Dictionary = {}
var _source: Dictionary = {}
var _error: Dictionary = {}
var _evidence: Dictionary = {}

func _bad(kind: String, detail: String) -> bool:
	if _error.is_empty(): _error = {"kind": kind, "detail": detail}
	return false


func _elapsed() -> int:
	return Time.get_ticks_msec() - _started


func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


func _sha(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for c: Variant in value:
		if not c in "0123456789abcdef": return false
	return true


func _options_error(options: Dictionary) -> String:
	if not options["mode"] in ["contract", "batch", "final", "diagnostic", "purse-diagnostic", "items-diagnostic", "census-diagnostic"]: return "unknown economy mode"
	if options["mode"] in ["diagnostic", "purse-diagnostic", "items-diagnostic", "census-diagnostic"]:
		if str(options["input-save"]) == "" or not _sha(str(options["input-sha"])): return "diagnostic requires an exact input save and SHA256"
	elif str(options["input-save"]) != "" or str(options["input-sha"]) != "": return "input save is diagnostic-only"
	if int(options["checkpoint"]) < 0 or int(options["checkpoint"]) > 240: return "checkpoint out of range 0..240"
	if int(options["batch-days"]) < 1 or int(options["batch-days"]) > 15: return "batch-days out of range 1..15"
	if int(options["years"]) != 2: return "this experiment requires exactly two native years"
	var phase: String = str(options["phase"])
	if phase.is_empty() or phase.length() > 64: return "phase length must be 1..64"
	for c: Variant in phase:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return "phase permits only ASCII letters, digits, underscore and hyphen"
	return ""


func _base_params() -> Dictionary:
	return {"phase": _opts["phase"], "application_version": "0.099", "seed": 4242, "world_schema": 1, "save_schema": 2,
		"size": "normal", "width": 150, "height": 96, "cell": 24, "normal_stretch": 1.5, "area_factor": 1.0,
		"creatures": true, "history_days": 1, "years": 2, "days_per_season": 30, "seasons": 4, "target_days": 240,
		"batch_days": _opts["batch-days"], "soft_ms": SOFT_MS, "day_ms": DAY_MS, "drain_end_ms": DRAIN_END_MS,
		"absolute_ms": ABSOLUTE_MS, "item_quality_value_growth": 1.25, "quality_cap": 5,
		"races": RACES, "grouping": "native town culture race; no within-town minority estimate", "autosave": "off_in_memory",
		"artifact_float_codec": "existing native v074 save_text/restore_exact with detached frozen containers", "fractional_hash_codec": "IEEE754 float64 hex",
		"cash_roundoff_abs": M.CASH_ROUNDOFF_ABS, "cash_roundoff_policy": "record exact values; no mutation; quantities and counts remain strict"}


func _static_contract() -> bool:
	if str(ProjectSettings.get_setting("application/config/version", "")) != "0.099": return _bad("application_version", "expected native application/config/version 0.099")
	if Calendar.DAYS_PER_SEASON != 30 or Calendar.SEASONS.size() != 4: return _bad("calendar", "expected 30 days x four seasons")
	if DevTools.WORLD_SEED != 4242 or DevTools.WORLD_VERSION != 1: return _bad("fixture_contract", "DevTools seed/version differs")
	if not M.equal_json(TownEcon.data().get("item_quality_value_growth", null), 1.25): return _bad("quality_growth", "native item_quality_value_growth must be exactly 1.25")
	if Game.SAVE_VERSION != 2: return _bad("save_schema", "expected separate native save schema2; world schema stays1")
	return true


func _source_files(path: String, out: Array) -> bool:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null: return _bad("source_read", path)
	for name: Variant in dir.get_directories():
		if name.begins_with("."): continue
		if not _source_files(path.path_join(name), out): return false
	for name: Variant in dir.get_files():
		if name == "project.godot" or name.get_extension() in ["gd", "gdshader", "gdextension", "tscn", "tres", "json", "cfg", "csv", "txt"]:
			out.append(path.path_join(name))
	return true


func _fingerprint() -> Dictionary:
	var files: Array = []
	if not _source_files("res://", files): return {}
	files.sort()
	var manifest: Dictionary = {}
	for path: Variant in files:
		var hash: String = FileAccess.get_sha256(path)
		if not _sha(hash):
			_bad("source_hash", path)
			return {}
		manifest[path] = hash
		if _elapsed() >= LIMIT_MS:
			_bad("source_deadline", path)
			return {}
	return {"identity": {"sha256": M.digest(manifest), "application_version": "0.099", "file_count": manifest.size(),
		"method": "sorted resource-path to SHA256 map; code/scenes/data/config; excludes imports/caches/UID sidecars"}, "files": manifest}


func _write_new(path: String, value: Variant) -> bool:
	if FileAccess.file_exists(path): return _bad("duplicate_artifact", path)
	var bad: String = M.finite(value)
	if bad != "": return _bad("artifact_nonfinite", path + bad)
	var body: String = M.text(value)
	if body == "": return _bad("artifact_encode", path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _bad("artifact_open", path + ":" + str(FileAccess.get_open_error()))
	file.store_string(body)
	file.flush()
	var code: Error = file.get_error()
	file.close()
	if code != OK: return _bad("artifact_write", path + ":" + str(code))
	if FileAccess.get_file_as_string(path) != body: return _bad("artifact_readback", path)
	return true


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_bad("missing_artifact", path)
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		_bad("artifact_json", path + ":" + parser.get_error_message())
		return {}
	Game.restore_exact(parser.data)
	if parser.data.get("_economy_artifact_v094", "") == "native074-frozen":
		if not parser.data.get("payload") is Dictionary:
			_bad("artifact_payload", path)
			return {}
		return parser.data["payload"]
	return parser.data


func _request_error(index: int, previous_exists: bool, target_exists: bool, previous_completed: int = -1) -> String:
	if target_exists: return "duplicate_checkpoint"
	if index > 0 and not previous_exists: return "missing_previous_checkpoint"
	if previous_completed >= 240: return "duplicate_completion"
	return ""


func _clean(expected_day: float) -> bool:
	if not M.equal_json(Game.day, expected_day): return _bad("day_continuity", "expected %s, actual %s" % [str(expected_day), str(Game.day)])
	if not Game.world.get("work", []).is_empty(): return _bad("unfinished_work", "ordered campaign queue is nonempty")
	if int(Game.world.get("last_day", -1)) != int(floor(Game.day)): return _bad("unfinished_midnight", "world.last_day differs from Game.day")
	if not Game.pending_battle.is_empty(): return _bad("observer_requires_input", "native pending battle; no encounter was cleared")
	var stats: Dictionary = Game.save_stats()
	if bool(stats.get("pending", true)) or int(stats.get("active_snapshots", -1)) != 0: return _bad("pending_save", JSON.stringify(stats))
	if _elapsed() >= LIMIT_MS: return _bad("absolute_deadline", "completed boundary exceeded 50 seconds")
	return true


func _world_contract(initial: bool) -> bool:
	var w: Dictionary = Game.world
	if Game.seed_value != 4242 or int(w.get("seed", -1)) != 4242: return _bad("world_seed", "both native game/world seeds must be 4242")
	if int(w.get("version", -1)) != 1: return _bad("world_schema", "native world.version must be 1")
	if str(w.get("size", "normal")) != "normal" or int(w.get("w", 0)) != 150 or int(w.get("h", 0)) != 96 or int(w.get("cell", 0)) != 24 or not M.equal_json(w.get("tf", 1.0), 1.0): return _bad("world_size", "expected Normal 150x96, cell24, area factor1 (Normal may omit size/tf); geometric stretch1.5 is separate")
	if w.get("creatures_enabled", false) != true or not Monsters.creatures_on: return _bad("creatures", "native saved and active creatures must both be enabled")
	var history: Dictionary = w.get("presim", {})
	if not M.equal_json(history.get("total", -1), 1) or not M.equal_json(history.get("done", -1), 1) or history.get("finished", false) != true: return _bad("history", "native presim must contain total1,done1,finished=true")
	if not M.equal_json(history.get("from", -1), 0): return _bad("history_origin", "one-day history must begin at native day0")
	if initial and not M.equal_json(Game.day, 1): return _bad("initial_day", "native one-history-day start must be day1")
	if str(Game.setting("autosave")) != "off": return _bad("autosave", "isolated process autosave must remain off")
	var seen: Array = M.races()
	for race: Variant in seen:
		if not race in RACES: return _bad("race", "unknown native town culture race: " + str(race))
	if initial and seen.size() != 7: return _bad("race_coverage", "fresh seed4242 must expose all seven native culture keys")
	return _static_contract()


func _observe(types: Dictionary) -> Dictionary:
	var bad: String = M.validate_physical()
	if bad != "":
		_bad("physical_holdings", bad)
		return {}
	var observation: Dictionary = M.capture(RACES, types)
	if observation.has("error"):
		_bad("observation", str(observation["error"]))
		return {}
	bad = M.finite(observation)
	if bad != "":
		_bad("nonfinite_observation", bad)
		return {}
	observation = M.plain(observation)
	bad = _groups_error(observation["groups"])
	if bad != "":
		_evidence["failed_groups"] = observation["groups"]
		_bad("group_coverage", bad)
		return {}
	return observation


func _groups_error(groups: Variant) -> String:
	if not groups is Dictionary or groups.size() != 8 or not groups.has("WORLD"): return "require WORLD plus all seven races"
	var sum: Dictionary = M._empty_group()
	var keys: Array = RACES.duplicate()
	keys.append("WORLD")
	for race: Variant in keys:
		if not groups.get(race) is Dictionary: return "missing race:" + str(race)
		var row: Dictionary = groups[race].duplicate(true)
		for k: Variant in M._empty_group():
			if not row.has(k): return "missing metric:" + str(race) + "/" + str(k)
		if not row.has("day_wage_population_mean") or not row.get("food_price_population_mean") is Dictionary: return "missing price/wage means:" + str(race)
		if not _integer(row["population"]) or row["population"] < 0 or not _integer(row["towns"]) or row["towns"] < 0: return "bad population/town count:" + str(race)
		row.erase("day_wage_population_mean")
		row.erase("food_price_population_mean")
		var bad: String = M.numeric(row)
		if bad != "": return str(race) + bad
		if race != "WORLD": M._add(sum, row)
	var world: Dictionary = groups["WORLD"].duplicate(true)
	world.erase("day_wage_population_mean")
	world.erase("food_price_population_mean")
	for key: Variant in sum:
		var exact: bool = key in ["towns", "population", "population_counter", "households", "hungry_households", "hungry_people", "famine_towns", "hunger_stages", "arable_acres", "owned_acres", "estate_acres", "census"]
		var matches: bool = M.equal_json(sum[key], world[key]) if exact else M.equal_partition(sum[key], world[key])
		if not matches:
			return "race totals do not equal WORLD " + M.difference_json(sum[key], world[key], "/" + str(key))
	if int(world.get("towns", 0)) <= 0: return "empty WORLD town coverage"
	return M.finite(groups)


func _audit_error(comparison: Variant) -> String:
	if not comparison is Dictionary or comparison.get("ok", false) != true: return "native WorldAudit.compare reported failure"
	for k: Variant in ["coin", "arms", "treasure_gate", "items"]:
		if not comparison.get(k) is Dictionary or comparison[k].get("ok", false) != true: return "missing/failing native gate:" + k
	for good: Variant in WorldAudit.GOODS:
		if comparison.get("goods", {}).get(good, {}).get("ok", false) != true: return "missing/failing goods gate:" + str(good)
	for ration: Variant in ["food", "beer", "wine"]:
		if comparison.get("rations", {}).get(ration, {}).get("ok", false) != true: return "missing/failing rations gate:" + ration
	return M.finite(comparison)


func _manifest_error(m: Dictionary, index: int, previous: Dictionary, previous_sha: String, params: Dictionary, source: Dictionary) -> String:
	if m.get("schema", "") != SCHEMA: return "schema"
	if not M.equal_json(m.get("index", -1), index): return "checkpoint_index"
	if not m.get("meta") is Dictionary: return "metadata"
	var meta: Dictionary = m["meta"]
	if meta.get("schema", "") != SCHEMA or not M.equal_json(meta.get("checkpoint", -1), index): return "metadata_schema_index"
	if not M.equal_json(meta.get("params"), params): return "parameters_seed_quality_version"
	if not M.equal_json(meta.get("source"), source): return "source"
	if index > 0:
		for k: Variant in ["observer", "observation_contract"]:
			if not M.equal_json(meta.get(k), previous.get("meta", {}).get(k)): return "changed_" + k
	if m.get("previous_manifest_sha256", "") != previous_sha or meta.get("previous_manifest_sha256", "") != previous_sha: return "previous_hash"
	var from: int = int(previous.get("meta", {}).get("completed", 0))
	if not _integer(meta.get("from", null)) or not _integer(meta.get("completed", null)): return "range_type"
	var completed: int = int(meta["completed"])
	if int(meta["from"]) != from or completed < from or completed > int(params["target_days"]) or completed - from > int(params["batch_days"]): return "range"
	if index > 0 and completed <= from: return "duplicate_or_empty_progress"
	if index > 0 and from >= int(params["target_days"]): return "duplicate_completion"
	if not M.equal_json(meta.get("origin_day", null), 1): return "origin"
	if not M.equal_json(meta.get("start_day", null), 1 + from) or not M.equal_json(meta.get("end_day", null), 1 + completed): return "day_range"
	if meta.get("clean", false) != true or not M.equal_json(meta.get("pending_work", -1), 0): return "unfinished_work"
	for k: Variant in ["save_sha256", "rows_sha256"]:
		if not _sha(m.get(k, "")): return "bad_" + k
	if meta.get("rows_sha256", "") != m.get("rows_sha256", ""): return "metadata_rows_checksum"
	for k: Variant in ["day_chain", "baseline_sha256", "endpoint_sha256", "physical_sha256"]:
		if not _sha(meta.get(k, "")): return "bad_" + k
	return ""


func _row_error(row: Dictionary, offset: int, origin: float, chain: String, before: Dictionary) -> String:
	if not M.equal_json(row.get("offset", -1), offset) or not M.equal_json(row.get("day", null), origin + offset): return "skipped_duplicate_day"
	if row.get("clean", false) != true or not M.equal_json(row.get("pending_work", -1), 0): return "unfinished_day"
	var bad: String = _groups_error(row.get("groups"))
	if bad != "": return bad
	if not row.get("makers") is Dictionary: return "missing_maker_measurements"
	var expected_changes: Dictionary = _changes(before, row["groups"])
	if not M.equal_json(row.get("changes"), expected_changes): return "changed_measurements " + M.difference_json(expected_changes, row.get("changes"))
	if M.census_residual(before["WORLD"], row["groups"]["WORLD"]) != 0: return "native_census_residual"
	var body: Dictionary = row.duplicate(true)
	body.erase("chain")
	if row.get("chain", "") != M.digest({"previous": chain, "record": body}): return "day_hashchain"
	return M.finite(row)


func _changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for group: Variant in after:
		var a: Dictionary = before[group]
		var b: Dictionary = after[group]
		out[group] = {"cash": M.delta(b["cash"], a["cash"]), "census": M.delta(b["census"], a["census"]),
			"population": int(b["population"]) - int(a["population"]), "census_residual": M.census_residual(a, b),
			"native_made": M.delta(b["native_made_cumulative"], a["native_made_cumulative"]),
			"wage_receipts_field_signed_change": float(b["wage_receipts_snapshot"]) - float(a["wage_receipts_snapshot"])}
	# Store the same decimal-normalized derived numbers that a reader recomputes.
	return M.plain(out)


func _completion_error(completed: int, observed: int) -> String:
	return "" if completed == 240 and observed == 240 else "incomplete_or_excess_coverage"


func _toy_groups() -> Dictionary:
	var groups: Dictionary = {"WORLD": M._empty_group()}
	for race: Variant in RACES: groups[race] = M._empty_group()
	groups["human"]["towns"] = 1
	groups["human"]["population"] = 10
	groups["human"]["population_counter"] = 10
	for race: Variant in RACES: M._add(groups["WORLD"], groups[race])
	for row: Variant in groups.values():
		row["day_wage_population_mean"] = 0.0 if row["population"] > 0 else null
		row["food_price_population_mean"] = {}
	return groups


func _contract() -> int:
	# These are synthetic protocol controls, NOT a native campaign measurement or load test.
	_params = _base_params()
	var source: Dictionary = {"sha256": "a".repeat(64), "application_version": "0.099"}
	var meta: Dictionary = {"schema": SCHEMA, "checkpoint": 0, "params": _params, "source": source,
		"origin_day": 1, "from": 0, "completed": 1, "start_day": 1, "end_day": 2, "clean": true, "pending_work": 0,
		"previous_manifest_sha256": ZERO_SHA, "day_chain": "b".repeat(64), "baseline_sha256": "b".repeat(64),
		"endpoint_sha256": "b".repeat(64), "physical_sha256": "b".repeat(64), "rows_sha256": "c".repeat(64), "observer": {"household_uid": "synthetic"}, "observation_contract": {"races": RACES}}
	var manifest: Dictionary = {"schema": SCHEMA, "index": 0, "meta": meta, "rows_sha256": "c".repeat(64), "save_sha256": "d".repeat(64), "previous_manifest_sha256": ZERO_SHA}
	var cases: Array = []
	cases.append(["valid_initial_checkpoint", _manifest_error(manifest, 0, {}, ZERO_SHA, _params, source) == ""])
	var changed: Dictionary = manifest.duplicate(true)
	changed["meta"]["completed"] = 0
	changed["meta"]["end_day"] = 1
	cases.append(["valid_origin_only_initial_checkpoint", _manifest_error(changed, 0, {}, ZERO_SHA, _params, source) == ""])
	changed = manifest.duplicate(true)
	changed["index"] = 1
	changed["meta"].merge({"checkpoint": 1, "from": 1, "completed": 2, "start_day": 2, "end_day": 3, "previous_manifest_sha256": "e".repeat(64)}, true)
	changed["previous_manifest_sha256"] = "e".repeat(64)
	cases.append(["valid_resumed_range", _manifest_error(changed, 1, manifest, "e".repeat(64), _params, source) == ""])
	cases.append(["valid_json_numeric_metadata", _manifest_error(M.plain(manifest), 0, {}, ZERO_SHA, _params, source) == ""])
	cases.append(["json_nested_int_float_equivalence", M.equal_json([1, {"x": [2.0, -3]}], M.plain([1.0, {"x": [2, -3.0]}]))])
	cases.append(["json_numeric_inequality", not M.equal_json([1, 2], [1.0, 2.01])])
	cases.append(["json_large_integer_not_rounded_equal", not M.equal_json(9007199254740993, 9007199254740992.0)])
	cases.append(["native_integer_producer_id", M.contains_id([1, 11, 12], 11)])
	cases.append(["loaded_json_producer_id", M.contains_id(M.plain([1, 11, 12]), 11)])
	cases.append(["reject_fractional_producer_id", not M.contains_id([11.25], 11)])
	cases.append(["reject_boolean_producer_id", not M.contains_id([true], 1)])
	for pair: Variant in [["checkpoint", -1], ["batch-days", 0], ["batch-days", 16], ["years", 1], ["phase", "../escape"], ["mode", "unknown"]]:
		var options: Dictionary = _opts.duplicate(true)
		options[pair[0]] = pair[1]
		cases.append(["reject_option_" + str(pair), _options_error(options) != ""])
	for bound: Variant in [1, 15]:
		var options: Dictionary = _opts.duplicate(true)
		options["batch-days"] = bound
		cases.append(["valid_batch_bound_" + str(bound), _options_error(options) == ""])
	cases.append(["missing_previous_checkpoint", _request_error(1, false, false) != ""])
	cases.append(["duplicate_checkpoint", _request_error(1, true, true) != ""])
	cases.append(["duplicate_completion", _request_error(1, true, false, 240) != ""])
	cases.append(["valid_checkpoint_request", _request_error(1, true, false, 15) == ""])
	cases.append(["valid_target_guard_synthetic_only", _completion_error(240, 240) == ""])
	cases.append(["reject_partial_target", _completion_error(239, 239) != ""])
	cases.append(["reject_excess_target", _completion_error(241, 241) != ""])
	cases.append(["reject_missing_observed_day", _completion_error(240, 239) != ""])
	for field: Variant in ["seed", "batch_days", "years", "item_quality_value_growth", "application_version", "save_schema", "world_schema"]:
		changed = manifest.duplicate(true)
		changed["meta"]["params"][field] = "wrong"
		cases.append(["reject_changed_parameter_" + field, _manifest_error(changed, 0, {}, ZERO_SHA, _params, source) != ""])
	for pair: Variant in [["schema", "wrong"], ["source", {}], ["from", 1], ["completed", 241], ["completed", 16], ["end_day", 3], ["pending_work", 1], ["clean", false], ["day_chain", "bad"], ["previous_manifest_sha256", "f".repeat(64)]]:
		changed = manifest.duplicate(true)
		changed["meta"][pair[0]] = pair[1]
		cases.append(["reject_metadata_" + str(pair[0]) + "_" + str(pair[1]), _manifest_error(changed, 0, {}, ZERO_SHA, _params, source) != ""])
	changed = manifest.duplicate(true)
	changed["schema"] = "wrong"
	cases.append(["reject_outer_schema", _manifest_error(changed, 0, {}, ZERO_SHA, _params, source) != ""])
	cases.append(["reject_skipped_checkpoint_index", _manifest_error(manifest, 1, {}, ZERO_SHA, _params, source) != ""])
	var groups: Dictionary = _toy_groups()
	var row: Dictionary = {"offset": 1, "day": 2, "clean": true, "pending_work": 0, "groups": groups,
		"changes": _changes(groups, groups), "makers": {"synthetic": {"opening_till": 2.0, "closing_till": 1.0, "cash_delta": -1.0, "bookprofit": -1.0}}}
	row["chain"] = M.digest({"previous": ZERO_SHA, "record": row})
	cases.append(["valid_day_and_negative_profit", _row_error(row, 1, 1.0, ZERO_SHA, groups) == ""])
	for pair: Variant in [["offset", 0], ["offset", 2], ["day", 3], ["pending_work", 1], ["chain", "f".repeat(64)]]:
		var bad_row: Dictionary = row.duplicate(true)
		bad_row[pair[0]] = pair[1]
		cases.append(["reject_daily_" + str(pair), _row_error(bad_row, 1, 1.0, ZERO_SHA, groups) != ""])
	for race: Variant in RACES:
		var bad_groups: Dictionary = groups.duplicate(true)
		bad_groups.erase(race)
		cases.append(["reject_missing_group_" + race, _groups_error(bad_groups) != ""])
	var fractional_groups: Dictionary = groups.duplicate(true)
	var weighted: float = 221689.898177866
	fractional_groups["human"]["food_price_population_sum"]["grain"] = weighted
	fractional_groups["WORLD"]["food_price_population_sum"]["grain"] = weighted + pow(2.0, -35.0)
	cases.append(["valid_native_one_ulp_partition", _groups_error(M.plain(fractional_groups)) == ""])
	fractional_groups["WORLD"]["food_price_population_sum"]["grain"] += 0.000001
	cases.append(["reject_non_rounding_partition_error", _groups_error(fractional_groups) != ""])
	var bad_counts: Dictionary = groups.duplicate(true)
	bad_counts["WORLD"]["population"] += 1
	cases.append(["reject_population_partition_error", _groups_error(bad_counts) != ""])
	# Construct adjacent doubles; the decimal lexer may round two spellings alike.
	cases.append(["metadata_still_rejects_one_ulp_error", not M.equal_json(1.0, 1.0 + pow(2.0, -52.0))])
	var fractional_before: Dictionary = _toy_groups()
	var fractional_after: Dictionary = _toy_groups()
	for group: Variant in ["human", "WORLD"]:
		fractional_before[group]["cash"]["treasury"] = 349669.79960372526
		fractional_after[group]["cash"]["treasury"] = 350699.35634799715
	fractional_before = M.plain(fractional_before)
	fractional_after = M.plain(fractional_after)
	var fractional_row: Dictionary = M.plain({"offset": 1, "day": 2, "clean": true, "pending_work": 0,
		"groups": fractional_after, "changes": _changes(fractional_before, fractional_after),
		"makers": {"synthetic": {"cash_delta": 350699.35634799715 - 349669.79960372526}}})
	fractional_row["chain"] = M.digest({"previous": ZERO_SHA, "record": fractional_row})
	cases.append(["valid_native_fractional_day_roundtrip", _row_error(M.plain(fractional_row), 1, 1.0, ZERO_SHA, fractional_before) == ""])
	var wrong_change: Dictionary = fractional_row.duplicate(true)
	wrong_change["changes"]["WORLD"]["cash"]["treasury"] += 0.01
	cases.append(["reject_changed_fractional_day_measurement", _row_error(wrong_change, 1, 1.0, ZERO_SHA, fractional_before) != ""])
	var exact_values: Array = [1.0 / 17.0, 1.0 / 7.0, pow(2.0, -52.0), 1e-90, -0.079975,
		53.736691176034476, 349669.79960372526, 350699.35634799715,
		350699.35634799715 - 349669.79960372526, 221689.898177866, 0.00000010001, -3710.0881063894967]
	for i: Variant in exact_values.size():
		var value: float = exact_values[i]
		var sample: Dictionary = {"value": value, "packed": PackedFloat64Array([value, value / 7.0])}
		var original: Dictionary = {"value": value, "packed": [value, value / 7.0]}
		var normalized: Dictionary = M.plain(sample)
		var decoded: Dictionary = M.parse_exact(M.text(normalized))
		cases.append(["bit_exact_native_artifact_" + str(i), M.equal_json(original, normalized) and M.equal_json(normalized, decoded)
			and M.equal_json(normalized, M.plain(M.plain(normalized))) and M.digest(original) == M.digest(decoded)])
	cases.append(["valid_physical", M.physical({"food": 0.0, "cash": 1}, "synthetic") == ""])
	cases.append(["reject_negative_physical", M.physical({"food": -1}, "synthetic") != ""])
	cases.append(["valid_recorded_cash_roundoff", M.physical(-8.881784197001252e-16, "synthetic/purse", true) == ""
		and M.cash_roundoff[-1]["value"] == -8.881784197001252e-16])
	cases.append(["reject_cash_beyond_roundoff_bound", M.physical(-2e-12, "synthetic/purse", true) != ""])
	cases.append(["reject_tiny_negative_physical_quantity", M.physical(-8.881784197001252e-16, "synthetic/food") != ""])
	cases.append(["reject_negative_cash_integer", M.physical(-1, "synthetic/purse", true) != ""])
	cases.append(["reject_real_native_treasury_overdraft", M.physical(-197.59569512111216, "synthetic/treasury", true) != ""])
	cases.append(["reject_nonfinite_cash", M.physical(INF, "synthetic/purse", true) != ""])
	cases.append(["reject_nonfinite_stock", M.physical({"food": NAN}, "synthetic") != ""])
	cases.append(["valid_lawful_debt_negative_profit_flow", M.finite({"debt": -50.0, "owed": 50.0, "profit": -3.0, "net_receipts": [-2.0]}) == ""])
	cases.append(["reject_failed_native_audit", _audit_error({"ok": false}) != ""])
	cases.append(["reject_incomplete_audit_groups", _audit_error({"ok": true}) != ""])
	var failed: Array = []
	for test: Variant in cases:
		if test[1] != true: failed.append(test[0])
	var passed: bool = failed.is_empty() and _static_contract() and _elapsed() < LIMIT_MS
	print("ECONOMY_CURRENT " + M.text({"schema": SCHEMA, "application_version": APPLICATION_VERSION, "source": _source, "save_schema": 2, "world_schema": 1,"ok": passed, "mode": "contract", "overallComplete": false, "controls": cases.size(),
		"failed_controls": failed, "nativeRuntime": "UNRUN", "native_days_advanced": 0, "scope": "synthetic protocol/JSON/physical controls, not native 240-day data or saved/load proof", "error": _error}))
	return 0 if passed else 1

func run(_tree: SceneTree) -> int:
	_started = Time.get_ticks_msec()
	# Only the original default zero-day controls are runnable. Cancelled modes stay closed.
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--economy-") or argument.begins_with("--short-"):
			printerr("FAIL economy current: this entry accepts only its zero-day default")
			return 1
	var fingerprint: Dictionary = _fingerprint()
	if not _error.is_empty() or not fingerprint.has("identity") or _elapsed() >= LIMIT_MS: return 1
	_source = fingerprint["identity"]
	return _contract()
