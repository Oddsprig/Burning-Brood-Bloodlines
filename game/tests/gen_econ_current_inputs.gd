extends RefCounted
## Produces current-build inputs, never an economy acceptance receipt.
## No fixture cache, edited clocks, quiet worlds, grants or repaired loaded state.
const SCHEMA: String = "economy_current_inputs_v100/1"
const ROOT: String = "user://econ_inputs_v100"
const APP_VERSION: String = "0.099"
const BUDGET_MS: int = 135000
const DAYS_PER_CHUNK: int = 5
const LAST_CHUNK: int = 9
const ZERO_SHA: String = "0000000000000000000000000000000000000000000000000000000000000000"
const RACES: Array = ["human", "orc", "goblin", "moon_elf", "dwarf", "high_elf", "dark_elf"]
const M = preload("res://tests/economy_stability_v094.gd")
const Protocol = preload("res://tests/test_economy_stability_v094.gd")

var _started: int = 0
var _error: String = ""
var _root: String = ""
var _claim: String = ""
var _scratch: String = ""
var _identity: Dictionary = {}
var _source_files: Dictionary = {}
var _provenance: Dictionary = {}
var _provenance_path: String = ""
var _provenance_sha: String = ""
var _protocol: Variant = Protocol.new()
var _types: Dictionary = {}

func _bad(detail: String) -> bool:
	if _error.is_empty():
		_error = detail
		printerr("FAIL ECON_INPUTS: " + detail)
	return false

func _budget() -> bool:
	return Time.get_ticks_msec() - _started < BUDGET_MS or _bad("135-second internal deadline")

func _hex(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true

func _params() -> Dictionary:
	return {"seed": 4242, "application_version": APP_VERSION, "save_schema": 2, "world_schema": 1,
		"size": "normal", "width": 150, "height": 96, "cell": 24, "history_days": 1, "creatures": true,
		"origin_day": 1, "target_day": 46, "days_per_chunk": DAYS_PER_CHUNK, "last_chunk": LAST_CHUNK,
		"days_per_season": 30, "seasons": 4, "item_quality_value_growth": 1.25, "races": RACES,
		"observer": "native DevTools.choose_house (HouseOnboarding.begin), with no post-onboarding state writes", "autosave": "off_in_memory"}

func _static_contract() -> bool:
	var engine: Dictionary = Engine.get_version_info()
	if int(engine.get("major", -1)) != 4 or int(engine.get("minor", -1)) != 7:
		return _bad("requires Godot 4.7")
	if str(ProjectSettings.get_setting("application/config/version", "")) != APP_VERSION:
		return _bad("application version differs from reviewed 0.099")
	if Game.SAVE_VERSION != 2 or DevTools.WORLD_VERSION != 1 or DevTools.WORLD_SEED != 4242:
		return _bad("native save/world/seed contract changed")
	if Calendar.DAYS_PER_SEASON != 30 or Calendar.SEASONS.size() != 4:
		return _bad("calendar contract changed")
	if not M.equal_json(TownEcon.data().get("item_quality_value_growth"), 1.25):
		return _bad("quality-growth contract changed")
	return _budget()

func _collect(path: String, files: Array) -> bool:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return _bad("cannot enumerate source: " + path)
	for name: String in directory.get_directories():
		if not name.begins_with(".") and not _collect(path.path_join(name), files):
			return false
	for name: String in directory.get_files():
		if name == "project.godot" or name.get_extension() in ["gd", "gdshader", "gdextension", "tscn", "tres", "json", "cfg", "csv", "txt"]:
			files.append(path.path_join(name))
	return _budget()

func _fingerprint() -> Dictionary:
	var paths: Array = []
	if not _collect("res://", paths):
		return {}
	paths.sort()
	var files: Dictionary = {}
	for path: String in paths:
		var checksum: String = FileAccess.get_sha256(path)
		if not _hex(checksum, 64) or not _budget():
			_bad("source hash failed: " + path)
			return {}
		files[path] = checksum
	return files

func _source_sha(files: Dictionary) -> String:
	var paths: Array = files.keys()
	paths.sort()
	var records: String = ""
	for path: String in paths:
		records += path + "\t" + str(files[path]) + "\n"
	return records.sha256_text()

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_bad("missing artifact: " + path)
		return {}
	var parsed: Variant = M.parse_exact(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_bad("invalid exact JSON artifact: " + path)
		return {}
	return parsed

func _write_new(path: String, value: Dictionary, enforce_budget: bool = true) -> bool:
	if FileAccess.file_exists(path):
		return _bad("refuse artifact overwrite: " + path)
	var issue: String = M.finite(value)
	if not issue.is_empty():
		return _bad("nonfinite artifact: " + path + issue)
	var body: String = M.text(value)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _bad("cannot create artifact: " + path)
	file.store_string(body)
	file.flush()
	var code: Error = file.get_error()
	file.close()
	if code != OK or FileAccess.get_file_as_string(path) != body:
		return _bad("artifact write/readback failed: " + path)
	return _budget() if enforce_budget else true

func _build() -> bool:
	_provenance_path = OS.get_environment("ECON_INPUT_PROVENANCE")
	_provenance_sha = OS.get_environment("ECON_INPUT_PROVENANCE_SHA256")
	if not _hex(_provenance_sha, 64) or FileAccess.get_sha256(_provenance_path) != _provenance_sha:
		return _bad("missing or unpinned controller build provenance")
	_provenance = _read(_provenance_path)
	if _provenance.get("schema", "") != "econ_build_provenance_v100/1" or not _hex(_provenance.get("git_commit"), 40):
		return _bad("provenance needs schema and actual full Git commit")
	var diffs: Variant = _provenance.get("applied_diffs")
	if not diffs is Array or diffs.is_empty():
		return _bad("provenance needs the complete applied-diff inventory, including this generator")
	var seen: Dictionary = {}
	var generator_listed: bool = false
	for entry: Variant in diffs:
		if not entry is Dictionary:
			return _bad("invalid applied-diff entry")
		var path: String = str(entry.get("path", ""))
		var checksum: Variant = entry.get("sha256")
		if not path.is_absolute_path() or seen.has(path) or not _hex(checksum, 64) or FileAccess.get_sha256(path) != checksum:
			return _bad("missing/duplicate/changed applied diff: " + path)
		seen[path] = true
		if path.get_file() == "gen_econ_inputs.diff":
			generator_listed = true
	if not generator_listed:
		return _bad("generator diff must be included in the controller inventory")
	_source_files = _fingerprint()
	if not _error.is_empty() or not M.equal_json(_provenance.get("source_files"), _source_files):
		return _bad("live source differs from controller's frozen integrated source map")
	_identity = {"schema": SCHEMA, "git_commit": _provenance["git_commit"], "applied_diffs": diffs,
		"source_sha256": _source_sha(_source_files), "source_file_count": _source_files.size(),
		"provenance_sha256": _provenance_sha, "engine": Engine.get_version_info(), "params": _params()}
	return _budget()

func _unchanged() -> bool:
	if FileAccess.get_sha256(_provenance_path) != _provenance_sha:
		return _bad("controller provenance changed during invocation")
	for entry: Dictionary in _identity["applied_diffs"]:
		if FileAccess.get_sha256(str(entry["path"])) != entry["sha256"]:
			return _bad("applied-diff bytes changed during invocation")
	if not M.equal_json(_fingerprint(), _source_files):
		return _bad("source changed during invocation")
	return _error.is_empty() and _budget()

func _shape(value: Variant) -> Array:
	var out: Array = [typeof(value)]
	if value is Dictionary:
		out.append([value.get_typed_key_builtin(), value.get_typed_key_class_name(),
			value.get_typed_value_builtin(), value.get_typed_value_class_name()])
		for key: Variant in value:
			out.append([_shape(key), _shape(value[key])])
	elif value is Array:
		out.append([value.get_typed_builtin(), value.get_typed_class_name()])
		for child: Variant in value:
			out.append(_shape(child))
	elif value is Unit:
		out.append("Unit")
	elif value is Item:
		out.append("Item")
	return out

func _live_shape() -> Array:
	return [_shape(Game.world), _shape(Game.contract), _shape(Game.company), _shape(Game.stash),
		_shape(Game.squads), _shape(Game.provisions), _shape(Game.rations), _shape(Game.food_clock)]

func _same_snapshot(expected: Dictionary, shape: Array) -> bool:
	var actual: Dictionary = Game._save_tree()
	if var_to_bytes(expected) != var_to_bytes(actual):
		return _bad("lossless native snapshot mismatch (includes float bits, field order, RNG, Items and cursors)")
	if var_to_bytes(shape) != var_to_bytes(_live_shape()):
		return _bad("native runtime type/container mismatch")
	return _budget()

func _clean(day: float) -> bool:
	var world: Dictionary = Game.world
	if Game.day != day or world.get("last_day", -1) != int(day) or not world.get("work") is Array or not world["work"].is_empty():
		return _bad("wrong day, missing cursor or unfinished ordered campaign work")
	if not Game.pending_battle.is_empty():
		return _bad("native pending battle requires input; never clear it")
	if Game.seed_value != 4242 or world.get("seed", -1) != 4242 or world.get("version", -1) != 1:
		return _bad("native seed/world schema mismatch")
	if str(world.get("size", "normal")) != "normal" or world.get("w", -1) != 150 or world.get("h", -1) != 96 or world.get("cell", -1) != 24 or not M.equal_json(world.get("tf", 1.0), 1.0):
		return _bad("native Normal world dimensions mismatch")
	var history: Dictionary = world.get("presim", {})
	if history.get("total", -1) != 1 or history.get("done", -1) != 1 or history.get("finished", false) != true or history.get("from", -1) != 0:
		return _bad("native one-day prehistory is not complete")
	if world.get("creatures_enabled", false) != true or not Monsters.creatures_on or Game.setting("autosave") != "off":
		return _bad("creatures/autosave policy mismatch")
	if str(world.get("player_house", {}).get("household_uid", "")).is_empty():
		return _bad("native observer household is missing")
	if not world.get("towns") is Dictionary or world["towns"].is_empty() or not world["towns"].has("t23"):
		return _bad("required native towns, including Ithilspire t23, are missing")
	for town: Dictionary in world["towns"].values():
		if not TownEcon.has_econ(town):
			return _bad("a native town lost its economy")
		var economy: Dictionary = town["econ"]
		for key: String in ["day", "wage_day", "fams", "sk"]:
			if not economy.has(key):
				return _bad("required economy cursor missing: " + key)
		if not economy["sk"] is Dictionary or not economy["sk"].has("q") or not economy["sk"].has("qd"):
			return _bad("required sickness cursor missing")
		for family: Dictionary in economy["fams"]:
			if not family.has("last"):
				return _bad("required household turn cursor missing")
	var stats: Dictionary = Game.save_stats()
	if bool(stats.get("pending", true)) or int(stats.get("active_snapshots", -1)) != 0:
		return _bad("native save still pending")
	return _budget()

func _observe() -> Dictionary:
	var issue: String = M.validate_physical()
	if not issue.is_empty():
		_bad("physical holdings: " + issue)
		return {}
	var observation: Dictionary = M.capture(RACES, _types)
	if observation.has("error"):
		_bad("observation: " + str(observation["error"]))
		return {}
	issue = _protocol._groups_error(observation.get("groups"))
	if not issue.is_empty() or not M.finite(observation).is_empty():
		_bad("strict observation groups/nonfinite: " + issue)
		return {}
	return {"observation": M.plain(observation), "physical": M.plain(M.physical_signature(WorldAudit.census(Game)))}

func _drain(tree: SceneTree) -> bool:
	var town: Variant = Game.world.get("towns", {}).get("t23")
	if not town is Dictionary or not TownEcon.has_econ(town):
		return _bad("required Ithilspire town missing before native work drain")
	var slices: int = 0
	while not Game.world.get("work", []).is_empty():
		if not _budget():
			return false
		CampaignWorld.work_slice(Game, 1)
		var treasury: float = float(Game.world["towns"]["t23"]["econ"]["treasury"])
		if not is_finite(treasury) or treasury < 0.0:
			return _bad("Ithilspire treasury negative/nonfinite after native ordered work slice")
		slices += 1
		if slices % 64 == 0:
			await tree.process_frame
	return _budget()

func _new_world(tree: SceneTree) -> bool:
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = true
	var generation: Dictionary = Game.new_game_begin(4242)
	while not Game.new_game_slice(generation, 8000):
		if not _budget():
			return false
		await tree.process_frame
	var history: Dictionary = {}
	while CampaignWorld.presim_left(Game) > 0:
		if not _budget():
			return false
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	var town: String = DevTools.choose_house(Game)
	if town.is_empty():
		return _bad("native onboarding found no eligible existing house")
	var seen: Array = M.races()
	if seen.size() != RACES.size():
		return _bad("fresh seed4242 must contain all seven native town cultures")
	for race: String in RACES:
		if not race in seen:
			return _bad("fresh world is missing native culture: " + race)
	return await _drain(tree) and _clean(1.0)

func _path(index: int, suffix: String) -> String:
	return _root.path_join("cp_%04d.%s" % [index, suffix])

func _load(index: int, manifest: Dictionary, endpoint: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(_path(index, "expected.bin"), FileAccess.READ)
	if file == null:
		return _bad("cannot read independent expected snapshot")
	var expected: Variant = file.get_var(false)
	var shape: Variant = file.get_var(false)
	var read_error: Error = file.get_error()
	var at_end: bool = file.get_position() == file.get_length()
	file.close()
	if read_error != OK or not at_end or not expected is Dictionary or not shape is Array:
		return _bad("invalid independent expected snapshot/type records")
	Game.SAVE_PATH = _path(index, "save.json")
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = _scratch # No frame yield while an immutable input is the destination.
	if not loaded or FileAccess.get_sha256(_path(index, "save.json")) != manifest["save_sha256"]:
		return _bad("native load failed or changed immutable save")
	if not _same_snapshot(expected, shape) or not _clean(float(1 + index * DAYS_PER_CHUNK)):
		return false
	var actual: Dictionary = _observe()
	if not _error.is_empty() or not M.equal_json(actual, endpoint):
		return _bad("reloaded observations, holdings, Item IDs or RNG differ from live endpoint")
	return _budget()

func _endpoint_contract(endpoint: Dictionary, day: int) -> bool:
	if not endpoint.get("observation") is Dictionary or not endpoint.get("physical") is Dictionary:
		return _bad("missing observation/physical endpoint")
	var observation: Dictionary = endpoint["observation"]
	if observation.get("day", -1) != day or endpoint["physical"].get("day", -1) != day:
		return _bad("observation/physical endpoint day differs from checkpoint")
	var issue: String = _protocol._groups_error(observation.get("groups"))
	if not issue.is_empty() or not M.finite(endpoint).is_empty():
		return _bad("invalid endpoint groups/nonfinite: " + issue)
	if not observation.get("towns") is Dictionary or observation["towns"].size() != observation["groups"]["WORLD"]["towns"]:
		return _bad("endpoint town coverage differs from WORLD")
	return true

func _history(last: int) -> Dictionary:
	var previous_sha: String = ZERO_SHA
	var previous_endpoint: Dictionary = {}
	var final_manifest: Dictionary = {}
	for index: int in range(last + 1):
		var manifest: Dictionary = _read(_path(index, "manifest.json"))
		if not _error.is_empty():
			return {}
		if manifest.get("schema") != SCHEMA or manifest.get("index", -1) != index or manifest.get("previous_manifest_sha256") != previous_sha or not M.equal_json(manifest.get("build"), _identity):
			_bad("checkpoint schema/index/build/hash-chain mismatch: " + str(index))
			return {}
		var start_day: int = 1 if index == 0 else 1 + (index - 1) * DAYS_PER_CHUNK
		var end_day: int = 1 + index * DAYS_PER_CHUNK
		if manifest.get("start_day", -1) != start_day or manifest.get("end_day", -1) != end_day or manifest.get("status") != "complete":
			_bad("checkpoint range/completion mismatch: " + str(index))
			return {}
		for suffix: String in ["save.json", "expected.bin", "rows.json"]:
			var key: String = {"save.json": "save_sha256", "expected.bin": "expected_sha256", "rows.json": "rows_sha256"}[suffix]
			if not _hex(manifest.get(key), 64) or FileAccess.get_sha256(_path(index, suffix)) != manifest[key]:
				_bad("immutable artifact checksum mismatch: " + _path(index, suffix))
				return {}
		var rows: Dictionary = _read(_path(index, "rows.json"))
		var daily: Variant = rows.get("daily")
		if not daily is Array or daily.size() != (0 if index == 0 else DAYS_PER_CHUNK) or not rows.get("endpoint") is Dictionary:
			_bad("checkpoint daily coverage/endpoint missing")
			return {}
		if not _endpoint_contract(rows["endpoint"], end_day):
			return {}
		if rows.get("schema") != SCHEMA or rows.get("index", -1) != index or not M.equal_json(rows.get("opening"), previous_endpoint):
			_bad("checkpoint opening endpoint continuity mismatch")
			return {}
		for offset: int in daily.size():
			var row: Variant = daily[offset]
			if not row is Dictionary or row.get("day", -1) != start_day + offset + 1 or row.get("clean") != true or not row.get("endpoint") is Dictionary:
				_bad("skipped/duplicate/unfinished native day")
				return {}
			var audit_issue: String = _protocol._audit_error(row.get("audit"))
			var endpoint: Dictionary = row["endpoint"]
			if not _endpoint_contract(endpoint, start_day + offset + 1) or not audit_issue.is_empty():
				_bad("invalid saved daily audit/endpoint: " + audit_issue)
				return {}
			var before: Dictionary = previous_endpoint.get("observation", {}).get("groups", {})
			var after: Dictionary = endpoint["observation"].get("groups", {})
			if not _protocol._groups_error(after).is_empty():
				_bad("saved daily group contract")
				return {}
			for race: String in RACES + ["WORLD"]:
				if not before.get(race) is Dictionary or M.census_residual(before[race], after[race]) != 0:
					_bad("saved daily native census mismatch: " + race)
					return {}
			previous_endpoint = endpoint
		if index == 0:
			previous_endpoint = rows["endpoint"]
		if not M.equal_json(previous_endpoint, rows["endpoint"]) or M.digest(previous_endpoint) != manifest.get("endpoint_sha256"):
			_bad("checkpoint endpoint hash/last daily row mismatch")
			return {}
		previous_sha = FileAccess.get_sha256(_path(index, "manifest.json"))
		final_manifest = manifest
		if not _budget():
			return {}
	return {"manifest": final_manifest, "manifest_sha256": previous_sha, "endpoint": previous_endpoint}

func _checkpoint(index: int, previous: Dictionary, daily: Array, endpoint: Dictionary) -> bool:
	var day: int = 1 + index * DAYS_PER_CHUNK
	if not _clean(float(day)):
		return false
	var expected: Dictionary = Game._save_tree()
	var shape: Array = _live_shape()
	if expected.get("version", -1) != 2:
		return _bad("current native snapshot is not schema 2")
	var expected_path: String = _path(index, "expected.bin")
	if FileAccess.file_exists(expected_path) or FileAccess.file_exists(_path(index, "save.json")):
		return _bad("refuse independent expected/native checkpoint overwrite")
	var file: FileAccess = FileAccess.open(expected_path, FileAccess.WRITE)
	if file == null:
		return _bad("cannot create independent expected snapshot")
	file.store_var(expected)
	file.store_var(shape)
	file.flush()
	var code: Error = file.get_error()
	file.close()
	if code != OK or not _budget():
		return _bad("expected snapshot write/deadline failure")
	Game.SAVE_PATH = _path(index, "save.json")
	var written: bool = Game.save_game()
	Game.SAVE_PATH = _scratch
	var receipt: Dictionary = Game.save_stats()
	if not written or receipt.get("last_ok", false) != true or receipt.get("last_stage", "") != "complete" or int(receipt.get("last_error", -1)) != OK or int(receipt.get("serialized_bytes", 0)) <= 0:
		return _bad("native save writer did not complete: " + JSON.stringify(receipt))
	var rows: Dictionary = {"schema": SCHEMA, "index": index, "opening": previous.get("endpoint", {}), "daily": daily, "endpoint": endpoint}
	if not _write_new(_path(index, "rows.json"), rows):
		return false
	var manifest: Dictionary = {"schema": SCHEMA, "index": index, "build": _identity,
		"start_day": 1 if index == 0 else 1 + (index - 1) * DAYS_PER_CHUNK, "end_day": day,
		"previous_manifest_sha256": previous.get("manifest_sha256", ZERO_SHA),
		"save_sha256": FileAccess.get_sha256(_path(index, "save.json")),
		"expected_sha256": FileAccess.get_sha256(expected_path), "rows_sha256": FileAccess.get_sha256(_path(index, "rows.json")),
		"endpoint_sha256": M.digest(endpoint), "writer_receipt": receipt, "status": "complete",
		"elapsed_ms": Time.get_ticks_msec() - _started, "created_utc": Time.get_datetime_string_from_system(true)}
	# Check the independent on-disk records AND the pre-writer live expectation.
	if not _load(index, manifest, endpoint) or not _same_snapshot(expected, shape) or not _unchanged():
		return false
	# Publication is last. Orphan data/claim files never authorize another chunk.
	return _write_new(_path(index, "manifest.json"), manifest)

func _reserve(selector: String, index: int) -> bool:
	var run_id: String = OS.get_environment("ECON_INPUT_RUN")
	if run_id.is_empty() or run_id.length() > 80:
		return _bad("ECON_INPUT_RUN must be a fresh nonempty identifier, at most 80 characters")
	for character: String in run_id:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return _bad("invalid ECON_INPUT_RUN character")
	_root = ROOT.path_join(run_id)
	if selector == "0":
		if DirAccess.make_dir_recursive_absolute(ROOT) != OK or DirAccess.make_dir_absolute(_root) != OK:
			return _bad("fresh run directory already exists or cannot be created")
	else:
		var build: Dictionary = _read(_root.path_join("build.json"))
		if not _error.is_empty() or not M.equal_json(build.get("identity"), _identity) or not M.equal_json(build.get("source_files"), _source_files) or not M.equal_json(build.get("provenance"), _provenance):
			return _bad("run build identity/source/provenance mismatch")
		var directory: DirAccess = DirAccess.open(_root)
		if directory == null:
			return _bad("missing run directory")
		for name: String in directory.get_directories():
			if not name.ends_with(".claim"):
				continue
			var prior_claim: String = _root.path_join(name)
			if FileAccess.file_exists(prior_claim.path_join("failure.json")) or not FileAccess.file_exists(prior_claim.path_join("result.json")):
				return _bad("prior claim is incomplete/failed; stop the lane and preserve evidence")
			var prior_result: Dictionary = _read(prior_claim.path_join("result.json"))
			if not _error.is_empty() or prior_result.get("ok", false) != true or prior_result.get("selector") != name.trim_suffix(".claim") or not M.equal_json(prior_result.get("build"), _identity):
				return _bad("prior invocation result is invalid or failed")
	_claim = _root.path_join(selector + ".claim")
	if DirAccess.make_dir_absolute(_claim) != OK:
		return _bad("duplicate invocation; use a new run ID, never overwrite evidence")
	_scratch = _claim.path_join("quit-scratch.json")
	Game.SAVE_PATH = _scratch
	if selector == "0" and not _write_new(_root.path_join("build.json"), {"identity": _identity, "source_files": _source_files, "provenance": _provenance}):
		return false
	if not selector.begins_with("verify"):
		for suffix: String in ["save.json", "expected.bin", "rows.json", "manifest.json"]:
			if FileAccess.file_exists(_path(index, suffix)):
				return _bad("checkpoint artifact already exists")
	return _write_new(_claim.path_join("attempt.json"), {"schema": SCHEMA, "selector": selector, "build": _identity,
		"status": "reserved; not passed", "created_utc": Time.get_datetime_string_from_system(true)})

func _execute(tree: SceneTree, selector: String, index: int) -> Dictionary:
	var previous: Dictionary = {}
	var current: Dictionary = {}
	if selector.begins_with("verify"):
		previous = _history(index)
		if not _error.is_empty() or not _load(index, previous["manifest"], previous["endpoint"]) or not _unchanged():
			return {}
		return {"verified_day": Game.day, "manifest_sha256": previous["manifest_sha256"], "fresh_process_reload": true}
	if index == 0:
		if not await _new_world(tree):
			return {}
		current = _observe()
		if not _error.is_empty():
			return {}
	else:
		previous = _history(index - 1)
		if not _error.is_empty() or not _load(index - 1, previous["manifest"], previous["endpoint"]):
			return {}
		current = previous["endpoint"]
	var daily: Array = []
	for offset: int in (0 if index == 0 else DAYS_PER_CHUNK):
		if not _clean(float(1 + (index - 1) * DAYS_PER_CHUNK + offset)):
			return {}
		var anchor: Dictionary = WorldAudit.census(Game)
		var before: Dictionary = current
		var expected_day: float = Game.day + 1.0
		Game.advance_time(1.0, false, 0, 1000)
		if not await _drain(tree) or not _clean(expected_day):
			return {}
		current = _observe()
		if not _error.is_empty():
			return {}
		var audit: Dictionary = WorldAudit.compare(anchor, WorldAudit.census(Game))
		var issue: String = _protocol._audit_error(audit)
		if not issue.is_empty():
			_bad("native daily conservation: " + issue)
			return {}
		for race: String in RACES + ["WORLD"]:
			if M.census_residual(before["observation"]["groups"][race], current["observation"]["groups"][race]) != 0:
				_bad("native daily census residual: " + race)
				return {}
		daily.append({"day": Game.day, "clean": true, "endpoint": current, "audit": M.plain(audit)})
		print("ECON_INPUTS_DAY ", int(Game.day), " elapsed_ms=", Time.get_ticks_msec() - _started)
	if not _checkpoint(index, previous, daily, current):
		return {}
	return {"checkpoint": index, "day": Game.day, "native_days_generated": daily.size(),
		"manifest": ProjectSettings.globalize_path(_path(index, "manifest.json")),
		"manifest_sha256": FileAccess.get_sha256(_path(index, "manifest.json")),
		"save": ProjectSettings.globalize_path(_path(index, "save.json")),
		"save_sha256": FileAccess.get_sha256(_path(index, "save.json"))}

func run(tree: SceneTree) -> int:
	_started = Time.get_ticks_msec()
	var selector: String = OS.get_environment("ECON_INPUT_CHUNK")
	var index: int = -1
	if selector in ["verify1", "verify46"]:
		index = 0 if selector == "verify1" else LAST_CHUNK
	elif selector.is_valid_int() and str(selector.to_int()) == selector:
		index = selector.to_int()
	if index < 0 or index > LAST_CHUNK:
		_bad("select ECON_INPUT_CHUNK=0..9|verify1|verify46; no aggregate/default run")
		return 1
	if not _static_contract() or not _build() or not _reserve(selector, index):
		return 1
	Game.settings["autosave"] = "off" # Process memory only; never save_settings().
	Game.wait_save()
	_types = M.maker_types()
	var result: Dictionary = await _execute(tree, selector, index)
	if result.is_empty() and _error.is_empty():
		_bad("empty generator result")
	result.merge({"schema": SCHEMA, "selector": selector, "ok": _error.is_empty(), "error": _error,
		"build": _identity, "elapsed_ms": Time.get_ticks_msec() - _started,
		"inputGenerationOnly": true, "shortAcceptancePass": false, "longCampaignComplete": false})
	if _error.is_empty():
		if not _write_new(_claim.path_join("result.json"), result):
			result["ok"] = false
			result["error"] = _error
	if not _error.is_empty() and not _claim.is_empty() and not FileAccess.file_exists(_claim.path_join("failure.json")):
		result["ok"] = false
		result["error"] = _error
		_write_new(_claim.path_join("failure.json"), result, false)
	print("ECON_CURRENT_INPUTS " + M.text(result))
	return 0 if _error.is_empty() else 1
