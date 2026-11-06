extends RefCounted
## SOURCE ONLY until the controller runs this through PinnedTest/TestBridge.
const M = preload("res://tests/economy_stability_v094.gd")
const SCHEMA: String = "economy_stability_v094/1"
const ROOT: String = "user://economy_stability_v094"
const META: String = "_economy_stability_v094"
const RACES: Array = ["human", "orc", "goblin", "moon_elf", "dwarf", "high_elf", "dark_elf"]
const SOFT_MS: int = 40000
const DAY_MS: int = 70000
const DRAIN_END_MS: int = 115000
const ABSOLUTE_MS: int = 135000
const ZERO_SHA: String = "0000000000000000000000000000000000000000000000000000000000000000"

var _started: int = 0
var _opts: Dictionary = {}
var _params: Dictionary = {}
var _source: Dictionary = {}
var _error: Dictionary = {}
var _evidence: Dictionary = {}
var _phase: String = ""
var _scratch: String = ""
var _completed: int = 0
var _origin: float = 1.0


func _bad(kind: String, detail: String) -> bool:
	if _error.is_empty(): _error = {"kind": kind, "detail": detail}
	return false


func _elapsed() -> int:
	return Time.get_ticks_msec() - _started


func _integer(value) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))


func _sha(value) -> bool:
	if not value is String or value.length() != 64: return false
	for c in value:
		if not c in "0123456789abcdef": return false
	return true


func _parse() -> bool:
	_opts = {"mode": "contract", "phase": "v094_p1", "checkpoint": 0, "batch-days": 15, "years": 2}
	var seen: Dictionary = {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--economy-"): continue
		var parts: PackedStringArray = arg.substr(10).split("=", true, 1)
		if parts.size() != 2 or not _opts.has(parts[0]) or seen.has(parts[0]): return _bad("cli", "unknown, duplicate, or malformed economy option: " + arg)
		seen[parts[0]] = true
		if parts[0] in ["checkpoint", "batch-days", "years"]:
			if not parts[1].is_valid_int(): return _bad("cli", "integer required: " + arg)
			_opts[parts[0]] = parts[1].to_int()
		else: _opts[parts[0]] = parts[1]
	var issue: String = _options_error(_opts)
	return _bad("cli", issue) if issue != "" else true


func _options_error(options: Dictionary) -> String:
	if not options["mode"] in ["contract", "batch", "final"]: return "mode must be contract, batch, or final"
	if int(options["checkpoint"]) < 0 or int(options["checkpoint"]) > 240: return "checkpoint out of range 0..240"
	if int(options["batch-days"]) < 1 or int(options["batch-days"]) > 15: return "batch-days out of range 1..15"
	if int(options["years"]) != 2: return "this experiment requires exactly two native years"
	var phase: String = str(options["phase"])
	if phase.is_empty() or phase.length() > 64: return "phase length must be 1..64"
	for c in phase:
		if not c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return "phase permits only ASCII letters, digits, underscore and hyphen"
	return ""


func _base_params() -> Dictionary:
	return {"phase": _opts["phase"], "application_version": "0.094", "seed": 4242, "world_schema": 1,
		"size": "normal", "width": 150, "height": 96, "cell": 24, "normal_stretch": 1.5, "area_factor": 1.0,
		"creatures": true, "history_days": 1, "years": 2, "days_per_season": 30, "seasons": 4, "target_days": 240,
		"batch_days": _opts["batch-days"], "soft_ms": SOFT_MS, "day_ms": DAY_MS, "drain_end_ms": DRAIN_END_MS,
		"absolute_ms": ABSOLUTE_MS, "item_quality_value_growth": 1.25, "quality_cap": 5,
		"races": RACES, "grouping": "native town culture race; no within-town minority estimate", "autosave": "off_in_memory"}


func _static_contract() -> bool:
	if str(ProjectSettings.get_setting("application/config/version", "")) != "0.094": return _bad("application_version", "expected native application/config/version 0.094")
	if Calendar.DAYS_PER_SEASON != 30 or Calendar.SEASONS.size() != 4: return _bad("calendar", "expected 30 days x four seasons")
	if DevTools.WORLD_SEED != 4242 or DevTools.WORLD_VERSION != 1: return _bad("fixture_contract", "DevTools seed/version differs")
	if not M.equal_json(TownEcon.data().get("item_quality_value_growth", null), 1.25): return _bad("quality_growth", "native item_quality_value_growth must be exactly 1.25")
	return true


func _source_files(path: String, out: Array) -> bool:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null: return _bad("source_read", path)
	for name in dir.get_directories():
		if name.begins_with("."): continue
		if not _source_files(path.path_join(name), out): return false
	for name in dir.get_files():
		if name == "project.godot" or name.get_extension() in ["gd", "gdshader", "gdextension", "tscn", "tres", "json", "cfg", "csv", "txt"]:
			out.append(path.path_join(name))
	return true


func _fingerprint() -> Dictionary:
	var files: Array = []
	if not _source_files("res://", files): return {}
	files.sort()
	var manifest: Dictionary = {}
	for path in files:
		var hash: String = FileAccess.get_sha256(path)
		if not _sha(hash):
			_bad("source_hash", path)
			return {}
		manifest[path] = hash
		if _elapsed() >= ABSOLUTE_MS:
			_bad("source_deadline", path)
			return {}
	return {"identity": {"sha256": M.digest(manifest), "application_version": "0.094", "file_count": manifest.size(),
		"method": "sorted resource-path to SHA256 map; code/scenes/data/config; excludes imports/caches/UID sidecars"}, "files": manifest}


func _path(index: int, suffix: String) -> String:
	return _phase.path_join("cp_%04d.%s" % [index, suffix])


func _write_new(path: String, value) -> bool:
	if FileAccess.file_exists(path): return _bad("duplicate_artifact", path)
	var bad: String = M.finite(value)
	if bad != "": return _bad("artifact_nonfinite", path + bad)
	var body: String = JSON.stringify(M.plain(value), "", true, true)
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
	return parser.data


func _reserve() -> bool:
	_phase = ROOT.path_join(str(_opts["phase"]))
	var initial: bool = _opts["mode"] == "batch" and int(_opts["checkpoint"]) == 0
	if initial:
		if DirAccess.dir_exists_absolute(_phase): return _bad("duplicate_phase", _phase)
		if DirAccess.make_dir_recursive_absolute(_phase) != OK: return _bad("phase_create", _phase)
	elif not DirAccess.dir_exists_absolute(_phase): return _bad("missing_phase", _phase)
	if FileAccess.file_exists(_phase.path_join("final.json")): return _bad("duplicate_completion", "phase already finalized")
	var existing: DirAccess = DirAccess.open(_phase)
	if existing == null: return _bad("phase_open", _phase)
	for name in existing.get_files():
		if name.begins_with("failure_"): return _bad("phase_failed", "failed evidence already seals this phase; use a new phase/profile")
	if _opts["mode"] == "batch":
		var index: int = int(_opts["checkpoint"])
		var issue: String = _request_error(index, FileAccess.file_exists(_path(index - 1, "manifest.json")),
			FileAccess.file_exists(_path(index, "manifest.json")) or FileAccess.file_exists(_path(index, "save.json")) or FileAccess.file_exists(_path(index, "rows.json")))
		if issue != "": return _bad(issue, str(index))
	var claim: String = "final.claim" if _opts["mode"] == "final" else "cp_%04d.claim" % int(_opts["checkpoint"])
	var attempt: String = _phase.path_join(claim)
	# Atomic per-invocation reservation, independent of the controller's game-test lane.
	if DirAccess.make_dir_absolute(attempt) != OK: return _bad("duplicate_invocation", attempt)
	_scratch = attempt.path_join("scratch.save.json")
	Game.SAVE_PATH = _scratch
	return _write_new(attempt.path_join("attempt.json"), {"schema": SCHEMA, "mode": _opts["mode"], "checkpoint": _opts["checkpoint"],
		"params": _params, "source": _source, "status": "reserved; not passed", "started_utc": Time.get_datetime_string_from_system(true)})


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
	if _elapsed() >= ABSOLUTE_MS: return _bad("absolute_deadline", "completed boundary exceeded 135 seconds")
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
	for race in seen:
		if not race in RACES: return _bad("race", "unknown native town culture race: " + str(race))
	if initial and seen.size() != 7: return _bad("race_coverage", "fresh seed4242 must expose all seven native culture keys")
	return _static_contract()


func _drain(tree: SceneTree, deadline: int) -> bool:
	while not Game.world.get("work", []).is_empty():
		if Time.get_ticks_msec() >= deadline: return _bad("unfinished_day_deadline", "pending ordered jobs=" + str(Game.world["work"].size()))
		CampaignWorld.work_slice(Game, 4000)
		await tree.process_frame
	if Time.get_ticks_msec() >= deadline: return _bad("day_deadline", "day drained after its absolute deadline")
	return true


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


func _groups_error(groups) -> String:
	if not groups is Dictionary or groups.size() != 8 or not groups.has("WORLD"): return "require WORLD plus all seven races"
	var sum: Dictionary = M._empty_group()
	var keys: Array = RACES.duplicate()
	keys.append("WORLD")
	for race in keys:
		if not groups.get(race) is Dictionary: return "missing race:" + str(race)
		var row: Dictionary = groups[race].duplicate(true)
		for k in M._empty_group():
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
	for key in sum:
		var exact: bool = key in ["towns", "population", "population_counter", "households", "hungry_households", "hungry_people", "famine_towns", "hunger_stages", "arable_acres", "owned_acres", "estate_acres", "census"]
		var matches: bool = M.equal_json(sum[key], world[key]) if exact else M.equal_partition(sum[key], world[key])
		if not matches:
			return "race totals do not equal WORLD " + M.difference_json(sum[key], world[key], "/" + str(key))
	if int(world.get("towns", 0)) <= 0: return "empty WORLD town coverage"
	return M.finite(groups)


func _audit_error(comparison) -> String:
	if not comparison is Dictionary or comparison.get("ok", false) != true: return "native WorldAudit.compare reported failure"
	for k in ["coin", "arms", "treasure_gate", "items"]:
		if not comparison.get(k) is Dictionary or comparison[k].get("ok", false) != true: return "missing/failing native gate:" + k
	for good in WorldAudit.GOODS:
		if comparison.get("goods", {}).get(good, {}).get("ok", false) != true: return "missing/failing goods gate:" + str(good)
	for ration in ["food", "beer", "wine"]:
		if comparison.get("rations", {}).get(ration, {}).get("ok", false) != true: return "missing/failing rations gate:" + ration
	return M.finite(comparison)


func _audit(a: Dictionary, b: Dictionary, kind: String, audits: Array) -> bool:
	var comparison: Dictionary = WorldAudit.compare(a, b)
	_evidence["last_audit"] = comparison
	var bad: String = _audit_error(comparison)
	if bad != "": return _bad("native_conservation", kind + ":" + bad)
	audits.append({"kind": kind, "from_day": a["day"], "to_day": b["day"], "comparison": M.plain(comparison)})
	return true


func _calendar(day: float) -> Dictionary:
	var whole: int = int(floor(day))
	return {"native_day": day, "season_bucket_from_day0": whole / 30, "year_bucket_from_day0": whole / 120,
		"season_name_from_day0": Calendar.SEASONS[(whole / 30) % 4], "season_boundary": whole % 30 == 0, "year_boundary": whole % 120 == 0}


func _snapshot(observation: Dictionary, offset: int, kinds: Array) -> Dictionary:
	return {"offset": offset, "day": observation["day"], "kinds": kinds, "calendar": _calendar(float(observation["day"])),
		"groups": observation["groups"], "towns": observation["towns"], "makers": observation["makers"]}


func _summary_start(groups: Dictionary) -> Dictionary:
	return {"days": 0, "origin_groups": groups, "last_groups": groups, "population_min": {}, "population_max": {}, "hungry_household_days": {}}


func _roll(summary: Dictionary, groups: Dictionary) -> void:
	summary["days"] = int(summary["days"]) + 1
	summary["last_groups"] = groups
	for key in groups:
		var pop: int = int(groups[key]["population"])
		summary["population_min"][key] = mini(int(summary["population_min"].get(key, summary["origin_groups"][key]["population"])), pop)
		summary["population_max"][key] = maxi(int(summary["population_max"].get(key, summary["origin_groups"][key]["population"])), pop)
		summary["hungry_household_days"][key] = int(summary["hungry_household_days"].get(key, 0)) + int(groups[key]["hungry_households"])


func _manifest_error(m: Dictionary, index: int, previous: Dictionary, previous_sha: String, params: Dictionary, source: Dictionary) -> String:
	if m.get("schema", "") != SCHEMA: return "schema"
	if not M.equal_json(m.get("index", -1), index): return "checkpoint_index"
	if not m.get("meta") is Dictionary: return "metadata"
	var meta: Dictionary = m["meta"]
	if meta.get("schema", "") != SCHEMA or not M.equal_json(meta.get("checkpoint", -1), index): return "metadata_schema_index"
	if not M.equal_json(meta.get("params"), params): return "parameters_seed_quality_version"
	if not M.equal_json(meta.get("source"), source): return "source"
	if index > 0:
		for k in ["observer", "observation_contract"]:
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
	for k in ["save_sha256", "rows_sha256"]:
		if not _sha(m.get(k, "")): return "bad_" + k
	if meta.get("rows_sha256", "") != m.get("rows_sha256", ""): return "metadata_rows_checksum"
	for k in ["day_chain", "baseline_sha256", "endpoint_sha256", "physical_sha256"]:
		if not _sha(meta.get(k, "")): return "bad_" + k
	return ""


func _row_error(row: Dictionary, offset: int, origin: float, chain: String, before: Dictionary) -> String:
	if not M.equal_json(row.get("offset", -1), offset) or not M.equal_json(row.get("day", null), origin + offset): return "skipped_duplicate_day"
	if row.get("clean", false) != true or not M.equal_json(row.get("pending_work", -1), 0): return "unfinished_day"
	var bad: String = _groups_error(row.get("groups"))
	if bad != "": return bad
	if not row.get("makers") is Dictionary or not M.equal_json(row.get("changes"), _changes(before, row["groups"])): return "missing_or_changed_measurements"
	if M.census_residual(before["WORLD"], row["groups"]["WORLD"]) != 0: return "native_census_residual"
	var body: Dictionary = row.duplicate(true)
	body.erase("chain")
	if row.get("chain", "") != M.digest({"previous": chain, "record": body}): return "day_hashchain"
	return M.finite(row)


func _changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for group in after:
		var a: Dictionary = before[group]
		var b: Dictionary = after[group]
		out[group] = {"cash": M.delta(b["cash"], a["cash"]), "census": M.delta(b["census"], a["census"]),
			"population": int(b["population"]) - int(a["population"]), "census_residual": M.census_residual(a, b),
			"native_made": M.delta(b["native_made_cumulative"], a["native_made_cumulative"]),
			"wage_receipts_field_signed_change": float(b["wage_receipts_snapshot"]) - float(a["wage_receipts_snapshot"])}
	return out


func _history(last: int, all_save_hashes: bool) -> Dictionary:
	var previous: Dictionary = {}
	var previous_sha: String = ZERO_SHA
	var chain: String = ""
	var summary: Dictionary = {}
	var offset: int = 0
	var baseline_sha: String = ""
	for index in range(last + 1):
		if _elapsed() >= ABSOLUTE_MS:
			_bad("validation_deadline", "checkpoint " + str(index))
			return {}
		var m: Dictionary = _read(_path(index, "manifest.json"))
		if not _error.is_empty(): return {}
		var bad: String = _manifest_error(m, index, previous, previous_sha, _params, _source)
		if bad != "":
			_bad("checkpoint_contract", "checkpoint %d: %s" % [index, bad])
			return {}
		if FileAccess.get_sha256(_path(index, "rows.json")) != m["rows_sha256"]:
			_bad("rows_checksum", str(index))
			return {}
		if all_save_hashes or index == last:
			if FileAccess.get_sha256(_path(index, "save.json")) != m["save_sha256"]:
				_bad("save_checksum", str(index))
				return {}
		var rows: Dictionary = _read(_path(index, "rows.json"))
		if not _error.is_empty(): return {}
		if rows.get("schema", "") != SCHEMA or not M.equal_json(rows.get("index", -1), index) or not rows.get("daily") is Array or not rows.get("snapshots") is Array or not rows.get("audits") is Array:
			_bad("rows_contract", str(index))
			return {}
		var snapshots: Dictionary = {}
		var required_seasons: Array = []
		for snap in rows["snapshots"]:
			if not snap is Dictionary or not _integer(snap.get("offset", null)) or snapshots.has(int(snap["offset"])):
				_bad("snapshot_duplicate_schema", str(index))
				return {}
			snapshots[int(snap["offset"])] = snap
		if index == 0:
			if not snapshots.has(0) or not "baseline" in snapshots[0].get("kinds", []):
				_bad("missing_baseline", "checkpoint0")
				return {}
			baseline_sha = M.digest(snapshots[0])
			if not M.equal_json(snapshots[0].get("day"), 1) or snapshots[0].get("towns", {}).size() != int(snapshots[0].get("groups", {}).get("WORLD", {}).get("towns", 0)):
				_bad("baseline_range_towns", "checkpoint0")
				return {}
			bad = _groups_error(snapshots[0].get("groups"))
			if bad != "":
				_bad("baseline_groups", bad)
				return {}
			summary = _summary_start(snapshots[0]["groups"])
			chain = M.digest({"schema": SCHEMA, "params": _params, "source": _source, "origin": 1, "baseline_sha256": baseline_sha})
			snapshots.erase(0)
		if rows["daily"].size() != int(m["meta"]["completed"]) - int(m["meta"]["from"]):
			_bad("range_row_count", str(index))
			return {}
		for row in rows["daily"]:
			offset += 1
			if not row is Dictionary:
				_bad("day_schema", str(offset))
				return {}
			bad = _row_error(row, offset, 1.0, chain, summary["last_groups"])
			if bad != "":
				_bad("daily_contract", "offset %d: %s" % [offset, bad])
				return {}
			chain = row["chain"]
			_roll(summary, row["groups"])
			var boundary: bool = int(row["day"]) % 30 == 0
			if boundary: required_seasons.append(row["day"])
			if boundary or offset == 240:
				if not snapshots.has(offset) or not M.equal_json(snapshots[offset].get("groups"), row["groups"]) or snapshots[offset].get("towns", {}).size() != int(row["groups"]["WORLD"]["towns"]):
					_bad("missing_boundary_snapshot", str(offset))
					return {}
				var kinds: Array = snapshots[offset].get("kinds", [])
				if (boundary and not "season" in kinds) or (int(row["day"]) % 120 == 0 and not "year" in kinds) or (offset == 240 and not "end" in kinds):
					_bad("boundary_snapshot_kind", str(offset))
					return {}
				snapshots.erase(offset)
		if not snapshots.is_empty():
			_bad("unexpected_snapshot", str(index))
			return {}
		var batch_audits: int = 0
		var season_from: float = float(m["meta"]["start_day"])
		var season_count: int = 0
		for audit in rows["audits"]:
			if not audit is Dictionary or _audit_error(audit.get("comparison")) != "":
				_bad("saved_audit", str(index))
				return {}
			if audit.get("kind", "") == "batch":
				batch_audits += 1
				if not M.equal_json(audit.get("from_day"), m["meta"]["start_day"]) or not M.equal_json(audit.get("to_day"), m["meta"]["end_day"]):
					_bad("audit_range", str(index))
					return {}
			elif audit.get("kind", "") == "season":
				if season_count >= required_seasons.size() or not M.equal_json(audit.get("from_day"), season_from) or not M.equal_json(audit.get("to_day"), required_seasons[season_count]):
					_bad("season_audit_range", str(index))
					return {}
				season_from = float(audit["to_day"])
				season_count += 1
			else:
				_bad("unknown_audit_kind", str(index))
				return {}
		if batch_audits != 1 or season_count != required_seasons.size() or baseline_sha != m["meta"]["baseline_sha256"] or chain != m["meta"]["day_chain"] or offset != int(m["meta"]["completed"]) or not M.equal_json(summary, m["meta"].get("summary")):
			_bad("coverage_summary_chain", str(index))
			return {}
		previous = m
		previous_sha = FileAccess.get_sha256(_path(index, "manifest.json"))
	return {"manifest": previous, "manifest_sha256": previous_sha, "summary": summary, "day_chain": chain, "baseline_sha256": baseline_sha, "completed": offset}


func _load_exact(index: int, manifest: Dictionary) -> bool:
	var path: String = _path(index, "save.json")
	if FileAccess.get_sha256(path) != manifest["save_sha256"]: return _bad("save_checksum", path)
	Game.SAVE_PATH = path
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = _scratch  # No process-frame yield while an immutable save is the destination.
	if not loaded: return _bad("native_load", path)
	if FileAccess.get_sha256(path) != manifest["save_sha256"]: return _bad("save_changed_on_load", path)
	if not M.equal_json(M.plain(Game.world.get(META, {})), manifest["meta"]): return _bad("native_metadata", "loaded metadata differs structurally from committed manifest")
	if not _world_contract(false) or not _clean(float(manifest["meta"]["end_day"])): return false
	var house: Dictionary = Game.world.get("player_house", {})
	if str(house.get("household_uid", "")) != str(manifest["meta"].get("observer", {}).get("household_uid", "")): return _bad("observer_identity", "native household changed on load")
	return true


func _source_record(fingerprint: Dictionary, initial: bool) -> bool:
	var path: String = _phase.path_join("source.json")
	if initial:
		if not _write_new(path, {"schema": SCHEMA, "identity": fingerprint["identity"], "params": _params, "files": fingerprint["files"]}): return false
	else:
		var record: Dictionary = _read(path)
		if not _error.is_empty(): return false
		if record.get("schema", "") != SCHEMA or not M.equal_json(record.get("identity"), fingerprint["identity"]) or not M.equal_json(record.get("params"), _params) or not M.equal_json(record.get("files"), fingerprint["files"]): return _bad("source_or_parameters_changed", "source.json differs from this invocation")
	_source["manifest_sha256"] = FileAccess.get_sha256(path)
	return _sha(_source["manifest_sha256"]) or _bad("source_record_hash", path)


func _unchanged_source() -> bool:
	var fingerprint: Dictionary = _fingerprint()
	if not _error.is_empty(): return false
	if fingerprint["identity"]["sha256"] != _source["sha256"] or FileAccess.get_sha256(_phase.path_join("source.json")) != _source["manifest_sha256"]: return _bad("source_changed_during_job", "source must remain fixed for the entire experiment")
	return true


func _capture_matches(observation: Dictionary, census: Dictionary, meta: Dictionary, types: Dictionary) -> bool:
	if M.digest(observation) != meta.get("endpoint_sha256", ""): return _bad("load_observation_continuity", "native measured fields changed across saved/load boundary")
	if M.digest(M.plain(M.physical_signature(census))) != meta.get("physical_sha256", ""): return _bad("load_physical_rng_continuity", "holdings, Item identities, or native RNG changed on load")
	if not M.equal_json(meta.get("observation_contract"), {"races": RACES, "maker_types_sha256": M.digest(types)}): return _bad("metric_contract", "race/type definitions differ on resume")
	return true


func _save_checkpoint(index: int, meta: Dictionary, rows: Dictionary, previous: Dictionary) -> bool:
	if not _clean(float(meta["end_day"])) or not _unchanged_source(): return false
	if FileAccess.file_exists(_path(index, "save.json")) or FileAccess.file_exists(_path(index, "manifest.json")): return _bad("duplicate_checkpoint", str(index))
	if not _write_new(_path(index, "rows.json"), rows): return false
	var rows_sha: String = FileAccess.get_sha256(_path(index, "rows.json"))
	meta["rows_sha256"] = rows_sha
	Game.world[META] = M.plain(meta)
	Game.wait_save()
	var before: Dictionary = Game.save_stats()
	Game.SAVE_PATH = _path(index, "save.json")
	Game.save_game()
	Game.wait_save()
	Game.SAVE_PATH = _scratch
	var stats: Dictionary = Game.save_stats()
	if stats.get("last_ok", false) != true or int(stats.get("completed", 0)) <= int(before.get("completed", 0)) or bool(stats.get("pending", true)) or int(stats.get("active_snapshots", -1)) != 0: return _bad("native_save_receipt", JSON.stringify(stats))
	if not FileAccess.file_exists(_path(index, "save.json")): return _bad("missing_native_save", str(index))
	var saved: Dictionary = _read(_path(index, "save.json"))
	if not _error.is_empty(): return false
	if not M.equal_json(saved.get("world", {}).get(META), meta) or not M.equal_json(saved.get("day"), meta["end_day"]) or not saved.get("world", {}).get("work", []).is_empty() or str(saved.get("rng_state", "")) != meta["rng"]["game"] or str(saved.get("world", {}).get("rng_state", "")) != meta["rng"]["world"]: return _bad("native_saved_payload", "saved day/metadata/queue/RNG differs from complete boundary")
	var manifest: Dictionary = {"schema": SCHEMA, "index": index, "meta": meta, "rows_sha256": rows_sha,
		"save_sha256": FileAccess.get_sha256(_path(index, "save.json")), "previous_manifest_sha256": meta["previous_manifest_sha256"]}
	var previous_sha: String = str(meta["previous_manifest_sha256"])
	var bad: String = _manifest_error(manifest, index, previous, previous_sha, _params, _source)
	if bad != "": return _bad("new_checkpoint_contract", bad)
	if index > 0 and FileAccess.get_sha256(_path(index - 1, "save.json")) != previous["save_sha256"]: return _bad("previous_save_rewritten", str(index - 1))
	if not _clean(float(meta["end_day"])): return false
	# Commit marker is last. An orphan rows/save file is evidence, never a checkpoint.
	return _write_new(_path(index, "manifest.json"), manifest)


func _batch(tree: SceneTree, types: Dictionary) -> Dictionary:
	var index: int = int(_opts["checkpoint"])
	var previous: Dictionary = {}
	var previous_sha: String = ZERO_SHA
	var baseline_sha: String = ""
	var chain: String = ""
	var summary: Dictionary = {}
	var observation: Dictionary = {}
	var snapshots: Array = []
	var audits: Array = []
	var observer: Dictionary = {}
	var audit_start: Dictionary = {}
	if index == 0:
		# A version-keyed cache is insufficient evidence: this phase requires fresh generation.
		if FileAccess.file_exists(DevTools.world_path(true)):
			_bad("nonfresh_fixture_cache", "use a fresh isolated persistent profile; do not delete/reuse its cache")
			return {}
		if not await DevTools.start_world(tree, _scratch, true):
			_bad("native_start", "DevTools.start_world failed")
			return {}
		Game.SAVE_PATH = _scratch
		if not _world_contract(true): return {}
		var tid: String = DevTools.choose_house(Game)
		if tid == "":
			_bad("native_observer", "no eligible existing household")
			return {}
		DevTools.stand_at(Game, tid)  # Initial onboarding only; never clear encounters again.
		if not await _drain(tree, _started + DRAIN_END_MS) or not _clean(1.0): return {}
		_origin = float(Game.day)
		observer = {"household_uid": str(Game.world.get("player_house", {}).get("household_uid", "")), "origin_town": tid}
		if observer["household_uid"] == "":
			_bad("native_observer", "chosen house has no native household identity")
			return {}
		observation = _observe(types)
		if not _error.is_empty(): return {}
		var baseline: Dictionary = _snapshot(observation, 0, ["baseline"])
		snapshots.append(baseline)
		baseline_sha = M.digest(baseline)
		chain = M.digest({"schema": SCHEMA, "params": _params, "source": _source, "origin": _origin, "baseline_sha256": baseline_sha})
		summary = _summary_start(observation["groups"])
		audit_start = WorldAudit.census(Game)
	else:
		var history: Dictionary = _history(index - 1, false)
		if not _error.is_empty(): return {}
		previous = history["manifest"]
		_completed = int(history["completed"])
		if _completed >= 240:
			_bad("duplicate_completion", "240 days already committed; use final mode with the last checkpoint")
			return {}
		previous_sha = history["manifest_sha256"]
		baseline_sha = history["baseline_sha256"]
		chain = history["day_chain"]
		summary = history["summary"]
		observer = previous["meta"]["observer"]
		if not _load_exact(index - 1, previous): return {}
		observation = _observe(types)
		if not _error.is_empty(): return {}
		audit_start = WorldAudit.census(Game)  # New process, new local audit anchor.
		if not _capture_matches(observation, audit_start, previous["meta"], types): return {}
	var from: int = _completed
	var start_day: float = float(Game.day)
	var daily: Array = []
	var season_anchor: Dictionary = audit_start
	_evidence = {"status": "in progress; not passed", "checkpoint": index, "daily": daily, "snapshots": snapshots, "audits": audits}
	while _completed < 240 and daily.size() < int(_params["batch_days"]) and _elapsed() < SOFT_MS:
		if not _clean(_origin + _completed): return {}
		var before: Dictionary = observation
		var deadline: int = mini(_started + DRAIN_END_MS, Time.get_ticks_msec() + DAY_MS)
		Game.advance_time(1.0, false, 0, 1000)  # Native payroll/meals/war/creatures; ordered native work only.
		if not await _drain(tree, deadline) or not _clean(_origin + _completed + 1): return {}
		observation = _observe(types)
		if not _error.is_empty(): return {}
		var next: int = _completed + 1
		_evidence["attempted_complete_offset"] = next
		var row: Dictionary = {"offset": next, "day": Game.day, "calendar": _calendar(Game.day), "clean": true, "pending_work": 0,
			"groups": observation["groups"], "changes": {}, "makers": M.maker_changes(before["makers"], observation["makers"]),
			"native_encounter": str(Game.world.get("encounter", ""))}
		row["changes"] = _changes(before["groups"], observation["groups"])
		if int(row["changes"]["WORLD"]["census_residual"]) != 0:
			_evidence["failed_daily_observation"] = row
			_bad("native_census", "world population change is not booked by cumulative native births/deaths/migration")
			return {}
		var kinds: Array = []
		if int(Game.day) % 30 == 0:
			var season_end: Dictionary = WorldAudit.census(Game)
			if not _audit(season_anchor, season_end, "season", audits): return {}
			season_anchor = season_end
			kinds.append("season")
			if int(Game.day) % 120 == 0: kinds.append("year")
		if next == 240: kinds.append("end")
		if not kinds.is_empty(): snapshots.append(_snapshot(observation, next, kinds))
		row["chain"] = M.digest({"previous": chain, "record": row})
		var bad: String = _row_error(row, next, _origin, chain, before["groups"])
		if bad != "":
			_bad("new_daily_contract", bad)
			return {}
		chain = row["chain"]
		daily.append(row)
		_completed = next
		_roll(summary, observation["groups"])
	if index > 0 and _completed == from:
		_bad("no_progress_budget", "load/validation consumed the soft budget; no later checkpoint was committed")
		return {}
	if not _clean(_origin + _completed): return {}
	var audit_end: Dictionary = WorldAudit.census(Game)
	if not _audit(audit_start, audit_end, "batch", audits): return {}
	var meta: Dictionary = {"schema": SCHEMA, "checkpoint": index, "params": _params, "source": _source,
		"origin_day": _origin, "from": from, "completed": _completed, "start_day": start_day, "end_day": Game.day,
		"clean": true, "pending_work": 0, "previous_manifest_sha256": previous_sha, "day_chain": chain,
		"baseline_sha256": baseline_sha, "summary": summary, "observer": observer,
		"observation_contract": {"races": RACES, "maker_types_sha256": M.digest(types)},
		"endpoint_sha256": M.digest(observation), "physical_sha256": M.digest(M.plain(M.physical_signature(audit_end))),
		"rng": {"game": str(Game.rng.state), "world": str(Game.world.get("rng_state", ""))}}
	var rows: Dictionary = {"schema": SCHEMA, "index": index, "daily": daily, "snapshots": snapshots, "audits": audits}
	if not _save_checkpoint(index, meta, rows, previous): return {}
	return {"ok": true, "finished": true, "mode": "batch", "mechanicalBatchPass": true, "overallComplete": false,
		"allGroupsVerified": true, "checkpoint": index, "actualCompleteDays": _completed - from, "completed": _completed,
		"remaining": 240 - _completed, "nextCheckpoint": index + 1 if _completed < 240 else null,
		"nextMode": "batch" if _completed < 240 else "final", "finalCheckpoint": index if _completed == 240 else null,
		"source_sha256": _source["sha256"], "elapsed_ms": _elapsed()}


func _final(types: Dictionary) -> Dictionary:
	var index: int = int(_opts["checkpoint"])
	if FileAccess.file_exists(_path(index + 1, "manifest.json")):
		_bad("not_last_checkpoint", "final must name the exact last committed checkpoint")
		return {}
	var history: Dictionary = _history(index, true)
	if not _error.is_empty(): return {}
	_completed = int(history["completed"])
	if _completion_error(_completed, int(history["summary"]["days"])) != "":
		_bad("incomplete_target", "final requires exactly 240 consecutive complete daily records")
		return {}
	var manifest: Dictionary = history["manifest"]
	if not _load_exact(index, manifest): return {}
	var observation: Dictionary = _observe(types)
	if not _error.is_empty(): return {}
	var census: Dictionary = WorldAudit.census(Game)
	if not _capture_matches(observation, census, manifest["meta"], types) or not _clean(241.0) or not _unchanged_source(): return {}
	if FileAccess.get_sha256(_path(index, "save.json")) != manifest["save_sha256"]:
		_bad("final_save_rewritten", str(index))
		return {}
	var result: Dictionary = {"schema": SCHEMA, "ok": true, "finished": true, "mode": "final", "overallComplete": true,
		"allGroupsVerified": true, "completed": 240, "remaining": 0, "origin_day": 1, "end_day": Game.day,
		"last_checkpoint": index, "checkpoint_count": index + 1, "day_chain": history["day_chain"],
		"last_manifest_sha256": history["manifest_sha256"], "source": _source, "params": _params,
		"summary": history["summary"], "nativeRuntime": "240 complete daily steps validated", "elapsed_ms": _elapsed()}
	if not _write_new(_phase.path_join("final.json"), result): return {}
	return result


func _completion_error(completed: int, observed: int) -> String:
	return "" if completed == 240 and observed == 240 else "incomplete_or_excess_coverage"


func _execute(tree: SceneTree) -> Dictionary:
	if not _static_contract(): return {}
	_params = _base_params()
	var fingerprint: Dictionary = _fingerprint()
	if not _error.is_empty(): return {}
	_source = fingerprint["identity"].duplicate()
	if not _reserve(): return {}
	var initial: bool = _opts["mode"] == "batch" and int(_opts["checkpoint"]) == 0
	if not _source_record(fingerprint, initial): return {}
	var types: Dictionary = M.maker_types()
	if types.is_empty():
		_bad("maker_definitions", "native businesses table exposes no nonempty arms definitions")
		return {}
	if not _write_new(_scratch.get_base_dir().path_join("metric_contract.json"), {"schema": SCHEMA, "maker_types": types, "race_keys": RACES,
		"profit": "native active p1 BOOK-profit snapshot; p14 smoothed snapshot; never summed as fresh daily realized profit",
		"receipts": "rolling14 NET production till change per working person; repeated windows are observations, not new sales",
		"spend": "90/10 smoothed input estimate; never summed as actual input payments",
		"paid_wages": "native household wage_receipts snapshots and signed field changes; all employers, reset/turn effects LIMITED; t_paid also contains owner adjustments",
		"gross_sales": "UNAVAILABLE", "exact_input_expense": "UNAVAILABLE", "individual_throughput": "UNAVAILABLE"}): return {}
	if _opts["mode"] == "batch": return await _batch(tree, types)
	return _final(types)


func _safe_failure(value):
	if value is float and not is_finite(value): return str(value)
	if value is Dictionary:
		var out: Dictionary = {}
		for k in value: out[str(k)] = _safe_failure(value[k])
		return out
	if value is Array:
		var out: Array = []
		for x in value: out.append(_safe_failure(x))
		return out
	return value


func _persist_failure() -> void:
	if _phase == "" or not DirAccess.dir_exists_absolute(_phase): return
	var name: String = "failure_%s_%s.json" % [str(Time.get_unix_time_from_system()).replace(".", "_"), str(Time.get_ticks_usec())]
	var payload: Dictionary = {"schema": SCHEMA, "ok": false, "overallComplete": false, "status": "FAILED/PARTIAL; not a passed checkpoint",
		"error": _error, "options": _opts, "last_accepted_offset_in_process": _completed, "actual_native_day": str(Game.day),
		"pending_work": Game.world.get("work", []).size(), "elapsed_ms": _elapsed(), "evidence": _safe_failure(_evidence)}
	_write_new(_phase.path_join(name), payload)


func _toy_groups() -> Dictionary:
	var groups: Dictionary = {"WORLD": M._empty_group()}
	for race in RACES: groups[race] = M._empty_group()
	groups["human"]["towns"] = 1
	groups["human"]["population"] = 10
	groups["human"]["population_counter"] = 10
	for race in RACES: M._add(groups["WORLD"], groups[race])
	for row in groups.values():
		row["day_wage_population_mean"] = 0.0 if row["population"] > 0 else null
		row["food_price_population_mean"] = {}
	return groups


func _contract() -> int:
	# These are synthetic protocol controls, NOT a native campaign measurement or load test.
	_params = _base_params()
	var source: Dictionary = {"sha256": "a".repeat(64), "application_version": "0.094"}
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
	for pair in [["checkpoint", -1], ["batch-days", 0], ["batch-days", 16], ["years", 1], ["phase", "../escape"], ["mode", "unknown"]]:
		var options: Dictionary = _opts.duplicate(true)
		options[pair[0]] = pair[1]
		cases.append(["reject_option_" + str(pair), _options_error(options) != ""])
	for bound in [1, 15]:
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
	for field in ["seed", "batch_days", "years", "item_quality_value_growth", "application_version"]:
		changed = manifest.duplicate(true)
		changed["meta"]["params"][field] = "wrong"
		cases.append(["reject_changed_parameter_" + field, _manifest_error(changed, 0, {}, ZERO_SHA, _params, source) != ""])
	for pair in [["schema", "wrong"], ["source", {}], ["from", 1], ["completed", 241], ["completed", 16], ["end_day", 3], ["pending_work", 1], ["clean", false], ["day_chain", "bad"], ["previous_manifest_sha256", "f".repeat(64)]]:
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
	for pair in [["offset", 0], ["offset", 2], ["day", 3], ["pending_work", 1], ["chain", "f".repeat(64)]]:
		var bad_row: Dictionary = row.duplicate(true)
		bad_row[pair[0]] = pair[1]
		cases.append(["reject_daily_" + str(pair), _row_error(bad_row, 1, 1.0, ZERO_SHA, groups) != ""])
	for race in RACES:
		var bad_groups: Dictionary = groups.duplicate(true)
		bad_groups.erase(race)
		cases.append(["reject_missing_group_" + race, _groups_error(bad_groups) != ""])
	var fractional_groups: Dictionary = groups.duplicate(true)
	fractional_groups["human"]["food_price_population_sum"]["grain"] = 221689.89817786598
	fractional_groups["WORLD"]["food_price_population_sum"]["grain"] = 221689.898177866
	cases.append(["valid_native_one_ulp_partition", _groups_error(M.plain(fractional_groups)) == ""])
	fractional_groups["WORLD"]["food_price_population_sum"]["grain"] += 0.000001
	cases.append(["reject_non_rounding_partition_error", _groups_error(fractional_groups) != ""])
	var bad_counts: Dictionary = groups.duplicate(true)
	bad_counts["WORLD"]["population"] += 1
	cases.append(["reject_population_partition_error", _groups_error(bad_counts) != ""])
	cases.append(["metadata_still_rejects_one_ulp_error", not M.equal_json(221689.89817786598, 221689.898177866)])
	cases.append(["valid_physical", M.physical({"food": 0.0, "cash": 1}, "synthetic") == ""])
	cases.append(["reject_negative_physical", M.physical({"food": -1}, "synthetic") != ""])
	cases.append(["reject_nonfinite_cash", M.physical({"cash": INF}, "synthetic") != ""])
	cases.append(["reject_nonfinite_stock", M.physical({"food": NAN}, "synthetic") != ""])
	cases.append(["valid_lawful_debt_negative_profit_flow", M.finite({"debt": -50.0, "owed": 50.0, "profit": -3.0, "net_receipts": [-2.0]}) == ""])
	cases.append(["reject_failed_native_audit", _audit_error({"ok": false}) != ""])
	cases.append(["reject_incomplete_audit_groups", _audit_error({"ok": true}) != ""])
	var failed: Array = []
	for test in cases:
		if test[1] != true: failed.append(test[0])
	var passed: bool = failed.is_empty() and _static_contract()
	print("ECONOMY_V094 " + JSON.stringify({"ok": passed, "mode": "contract", "overallComplete": false, "controls": cases.size(),
		"failed_controls": failed, "nativeRuntime": "UNRUN", "native_days_advanced": 0, "scope": "synthetic protocol/JSON/physical controls, not native 240-day data or saved/load proof", "error": _error}))
	return 0 if passed else 1


func run(tree: SceneTree) -> int:
	_started = Time.get_ticks_msec()
	if not _parse():
		print("ECONOMY_V094 " + JSON.stringify({"ok": false, "overallComplete": false, "error": _error}))
		return 1
	if _opts["mode"] == "contract": return _contract()
	# Authorized isolated-process override only. No set_setting(), no settings-file writes.
	Game.settings["autosave"] = "off"
	Game.wait_save()
	var result = await _execute(tree)
	Game.wait_save()
	if not result is Dictionary or result.get("finished", false) != true or result.get("ok", false) != true or result.get("allGroupsVerified", false) != true or not _error.is_empty():
		if _error.is_empty(): _bad("aborted_runner", "no explicit finished/ok/all-groups result; refusing implicit success")
		_persist_failure()
		print("ECONOMY_V094 " + JSON.stringify({"ok": false, "overallComplete": false, "error": _error, "completed": _completed, "elapsed_ms": _elapsed()}))
		return 1
	print("ECONOMY_V094 " + JSON.stringify(result, "", true, true))
	return 0
