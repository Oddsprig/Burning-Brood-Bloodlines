extends "res://tests/test_economy_stability_v094.gd"
## Separate current-source experiment; every historical control remains inherited.
const EP_SCHEMA: String = "economy_current_v099_r1/1"
const EP_ROOT: String = "user://economy_current_v099_r1"
const EP_VERSION: String = "0.099"
const EP_MS: int = 40000
var ep: Dictionary = {}
var ep_root: String = ""
var ep_source_sha: String = ""
var ep_trace: Array = []
var ep_open: Dictionary = {}
var ep_anchor: Dictionary = {}
var ep_inputs: Dictionary = {}
var ep_records: Dictionary = {} # Validated once per process; all pinned bytes are rechecked before success.

func _base_params() -> Dictionary:
	var params: Dictionary = super._base_params()
	params["application_version"] = EP_VERSION
	return params

func _static_contract() -> bool:
	if str(ProjectSettings.get_setting("application/config/version", "")) != EP_VERSION: return _bad("application_version", "this separate protocol requires exactly " + EP_VERSION)
	if Calendar.DAYS_PER_SEASON != 30 or Calendar.SEASONS.size() != 4: return _bad("calendar", "expected 30 days x four seasons")
	if DevTools.WORLD_SEED != 4242 or DevTools.WORLD_VERSION != 1: return _bad("fixture_contract", "native seed/version differs")
	if not M.equal_json(TownEcon.data().get("item_quality_value_growth", null), 1.25): return _bad("quality_growth", "expected exactly 1.25")
	if Game.SAVE_VERSION != 2 or WorldGen.STRETCH != 1.5 or WorldGen.CELL != 24: return _bad("native_schema_geometry", "save-root2, stretch1.5, cell24 required")
	return true

func ep_time() -> bool:
	return _elapsed() < EP_MS or _bad("short_deadline", "40-second internal budget exceeded; incomplete, never passed")

func ep_params() -> Dictionary:
	return {"application_version": EP_VERSION, "seed": 4242, "world_schema": 1, "save_root_schema": 2,
		"size": "normal", "width": 150, "height": 96, "cell": 24, "stretch": 1.5, "area_factor": 1.0,
		"creatures": true, "history_days": 1, "days_per_season": 30, "seasons": 4,
		"native_seeds": {"game": 4242, "world_generation": 4242, "creatures": 8484},
		"profile": {"APPDATA": OS.get_environment("APPDATA"), "LOCALAPPDATA": OS.get_environment("LOCALAPPDATA")},
		"quality_growth": 1.25, "quality_cap": 5, "cash_roundoff_abs": M.CASH_ROUNDOFF_ABS,
		"origin_day": 0, "fixture_day": 46, "saved_day": 53, "live_next_day": 54,
		"expected_derivation": "independent native sliced A / atomic B; full snapshot+type+physical+RNG equality",
		"long_campaign_complete": false, "internal_ms": EP_MS}

func ep_fingerprint() -> Dictionary:
	var fingerprint: Dictionary = super._fingerprint()
	if not _error.is_empty(): return {}
	fingerprint["identity"]["application_version"] = EP_VERSION
	fingerprint["identity"]["engine"] = Engine.get_version_info()
	return fingerprint if ep_time() else {}

func ep_parse(entry: String) -> bool:
	ep = {"mode": "controls" if entry == "stability" else "", "run": "", "source-sha": "", "side": "",
		"day": "-1", "from-day": "-1", "previous-sha": "", "a-sha": "", "b-sha": "", "cross-previous-sha": "",
		"cross53-sha": "", "cross54-sha": "", "reload-sha": "", "controls-sha": ""}
	var seen: Dictionary = {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--short-") or (arg.begins_with("--economy-") and not arg.begins_with("--economy-protocol=")): return _bad("cli", "historical options cannot select current evidence")
		if not arg.begins_with("--ep-"): continue
		var pair: PackedStringArray = arg.substr(5).split("=", true, 1)
		if pair.size() != 2 or not ep.has(pair[0]) or seen.has(pair[0]): return _bad("cli", "unknown/duplicate/malformed current-protocol option")
		seen[pair[0]] = true
		ep[pair[0]] = pair[1]
	if not ep["mode"] in ["freeze", "controls", "generate", "history", "day", "day-batch", "mint", "cross", "cross-batch", "reload", "final"]: return _bad("cli", "explicit current protocol mode required")
	if str(ep["run"]).is_empty() or str(ep["run"]).length() > 64: return _bad("cli", "fresh run id required")
	for character: String in str(ep["run"]):
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return _bad("cli", "run id permits ASCII letters/digits/underscore/hyphen")
	if not str(ep["day"]).is_valid_int(): return _bad("cli", "integer day required")
	ep["day"] = int(ep["day"])
	ep_root = EP_ROOT.path_join(str(ep["run"]))
	if ep["mode"] != "freeze" and not _sha(ep["source-sha"]): return _bad("cli", "exact source.json SHA256 required")
	if ep["mode"] in ["generate", "history", "day", "day-batch", "mint"] and not ep["side"] in ["A", "B"]: return _bad("cli", "side A or B required")
	if ep["mode"] == "generate" and ep["day"] != 0: return _bad("cli", "generate must record day0")
	if ep["mode"] == "history" and ep["day"] != 1: return _bad("cli", "history must record day1")
	if ep["mode"] == "day" and (ep["day"] < 2 or ep["day"] > 52): return _bad("cli", "ordinary one-day parts are days2..52")
	if ep["mode"] == "day-batch":
		if not str(ep["from-day"]).is_valid_int(): return _bad("cli", "day-batch requires an integer from-day")
		var batch_first: int = int(ep["from-day"])
		if batch_first < 2 or batch_first > int(ep["day"]) or int(ep["day"]) > 52 or int(ep["day"]) - batch_first >= 5: return _bad("cli", "day-batch permits one to five ordinary days within 2..52")
	if ep["mode"] == "mint" and ep["day"] != 53: return _bad("cli", "mint records saved53 and same-live54")
	if ep["mode"] in ["history", "day", "day-batch", "mint"] and not _sha(ep["previous-sha"]): return _bad("cli", "exact predecessor manifest SHA256 required")
	if ep["mode"] in ["cross", "cross-batch"]:
		if ep["day"] < 0 or ep["day"] > 54 or not _sha(ep["a-sha"]) or not _sha(ep["b-sha"]): return _bad("cli", "cross requires exact A/B manifests and day0..54")
		var first_day: int = int(ep["day"])
		if ep["mode"] == "cross-batch":
			if not str(ep["from-day"]).is_valid_int(): return _bad("cli", "cross-batch requires an integer from-day")
			first_day = int(ep["from-day"])
			if first_day < 0 or first_day > int(ep["day"]): return _bad("cli", "cross-batch range must be within 0..54")
		if first_day > 0 and not _sha(ep["cross-previous-sha"]): return _bad("cli", "cross requires exact previous expected certificate")
	if ep["mode"] in ["reload", "final"] and (not _sha(ep["cross53-sha"]) or not _sha(ep["cross54-sha"])): return _bad("cli", "exact day53/day54 expected certificates required")
	if ep["mode"] == "final" and (not _sha(ep["reload-sha"]) or not _sha(ep["controls-sha"])): return _bad("cli", "exact controls and fresh reload receipts required")
	return true

func ep_pin(path: String, expected: String) -> bool:
	if ep_inputs.has(path) and ep_inputs[path] != expected: return _bad("input_rebound", path)
	if not _sha(expected) or FileAccess.get_sha256(path) != expected: return _bad("immutable_input", path)
	ep_inputs[path] = expected
	return true

func ep_unchanged() -> bool:
	for path: String in ep_inputs:
		if FileAccess.get_sha256(path) != ep_inputs[path]: return _bad("input_changed", path)
	var fingerprint: Dictionary = ep_fingerprint()
	return not fingerprint.is_empty() and M.equal_json(fingerprint, _source) and ep_time()

func ep_path(side: String, day: int, suffix: String) -> String:
	return ep_root.path_join("%s/day%02d.%s" % [side, day, suffix])

func ep_native_write(path: String, data: Dictionary) -> bool:
	if not data.get("trace") is Array or not ep_trace_plain(data["trace"]): return _bad("treasury_trace", "companion trace must contain only detached plain data")
	if FileAccess.file_exists(path): return _bad("duplicate_artifact", path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return _bad("native_open", path)
	file.store_var(data, false)
	file.flush()
	var code: Error = file.get_error()
	file.close()
	return code == OK or _bad("native_write", path)

func ep_native_read(path: String, expected: String) -> Dictionary:
	if not ep_pin(path, expected): return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_bad("native_open", path)
		return {}
	var value: Variant = file.get_var(false)
	var complete: bool = file.get_position() == file.get_length()
	var code: Error = file.get_error()
	file.close()
	if not complete or code != OK or not value is Dictionary:
		_bad("native_companion", path)
		return {}
	return value

func ep_source() -> bool:
	_opts = {"mode": "contract", "phase": "current_controls", "checkpoint": 0, "batch-days": 15, "years": 2, "input-save": "", "input-sha": ""}
	_source = ep_fingerprint()
	if _source.is_empty(): return false
	var path: String = ep_root.path_join("source.json")
	if ep["mode"] == "freeze":
		if DirAccess.dir_exists_absolute(ep_root): return _bad("duplicate_run", "use a new isolated profile/run; never overwrite failed evidence")
		if DirAccess.make_dir_recursive_absolute(ep_root) != OK: return _bad("create_root", ep_root)
		if not _write_new(path, {"schema": EP_SCHEMA, "params": ep_params(), "source": _source}): return false
		ep_source_sha = FileAccess.get_sha256(path)
	else:
		if not ep_pin(path, str(ep["source-sha"])): return false
		var source: Dictionary = _read(path)
		if source.get("schema") != EP_SCHEMA or not M.equal_json(source.get("params"), ep_params()) or not M.equal_json(source.get("source"), _source): return _bad("source_contract", "exact version/source/data/engine/parameters differ")
		ep_source_sha = str(ep["source-sha"])
		var directory: DirAccess = DirAccess.open(ep_root)
		if directory == null: return _bad("missing_root", ep_root)
		for name: String in directory.get_files():
			if name.begins_with("failure_"): return _bad("failed_run", "prior failure seals this run; repair and use a new run/profile")
	ep_inputs[path] = ep_source_sha
	var claim: String = "%s_%s_%02d" % [str(ep["mode"]), str(ep["side"]), int(ep["day"])]
	_scratch = ep_root.path_join(claim + ".claim").path_join("quit-scratch.json")
	if DirAccess.make_dir_absolute(ep_root.path_join(claim + ".claim")) != OK: return _bad("duplicate_invocation", claim)
	Game.SAVE_PATH = _scratch
	return true

func ep_type_script(value: Variant) -> String:
	return str(value.resource_path) if value is Script else ""

func ep_dictionary_type(value: Dictionary) -> Array:
	return [value.get_typed_key_builtin(), value.get_typed_key_class_name(), ep_type_script(value.get_typed_key_script()),
		value.get_typed_value_builtin(), value.get_typed_value_class_name(), ep_type_script(value.get_typed_value_script())]

func ep_shape(value: Variant) -> Array:
	var shape: Array = [typeof(value)]
	if value is Dictionary:
		shape.append(ep_dictionary_type(value))
		for key: Variant in value: shape.append([ep_shape(key), ep_shape(value[key])])
	elif value is Array:
		shape.append([value.get_typed_builtin(), value.get_typed_class_name(), ep_type_script(value.get_typed_script())])
		for child: Variant in value: shape.append(ep_shape(child))
	elif value is Unit:
		# BodyState.to_dict rebuilds parts; capture its live container metadata separately.
		# Do not walk omitted pristine part caches, which are intentionally not saved.
		shape.append(["Unit", ep_shape(value.to_dict()), ep_shape(value.equip), ep_shape(value.horse), ep_dictionary_type(value.body.parts)])
	elif value is Item: shape.append(["Item", ep_shape(value.to_dict())])
	return shape

func ep_books() -> Dictionary:
	return {"tracking": WorldAudit.tracking, "items_gone": WorldAudit.items_gone.duplicate(true),
		"gone_by": WorldAudit.gone_by.duplicate(true), "rations": WorldAudit.rations.duplicate(true),
		"treasure_book": WorldAudit.treasure_book.duplicate(true), "unmade_ids": WorldAudit.unmade_ids.duplicate(true),
		"unmade_by": WorldAudit.unmade_by.duplicate(true), "made_log": WorldAudit.made_log.duplicate(true),
		"rolled_ids": WorldAudit.rolled_ids.duplicate(true)}

func ep_restore_books(books: Dictionary) -> bool:
	for key: String in ["tracking", "items_gone", "gone_by", "rations", "treasure_book", "unmade_ids", "unmade_by", "made_log", "rolled_ids"]:
		if not books.has(key): return _bad("audit_books", "missing native observer book " + key)
	WorldAudit.tracking = bool(books["tracking"])
	WorldAudit.items_gone = books["items_gone"].duplicate(true)
	WorldAudit.gone_by = books["gone_by"].duplicate(true)
	WorldAudit.rations = books["rations"].duplicate(true)
	WorldAudit.treasure_book = books["treasure_book"].duplicate(true)
	WorldAudit.unmade_ids = books["unmade_ids"].duplicate(true)
	WorldAudit.unmade_by = books["unmade_by"].duplicate(true)
	WorldAudit.made_log = books["made_log"].duplicate(true)
	WorldAudit.rolled_ids = books["rolled_ids"].duplicate(true)
	return true

func ep_capture() -> Dictionary:
	var observation: Dictionary = _observe(M.maker_types())
	if not _error.is_empty(): return {}
	var census: Dictionary = WorldAudit.census(Game)
	var payload: Dictionary = Game._save_tree()
	if payload.get("version") != 2 or not payload.has("raid_state") or not payload.has("war_runtime"):
		_bad("save_root", "complete native schema2 runtime required")
		return {}
	var live_containers: Dictionary = {"world": Game.world, "contract": Game.contract, "company": Game.company,
		"stash": Game.stash, "squads": Game.squads, "rep": Game.rep, "provisions": Game.provisions,
		"rations": Game.rations, "food_clock": Game.food_clock, "goods_lost": TownEcon.goods_lost}
	return {"snapshot": payload, "shape": ep_shape(live_containers),
		"observation": observation, "physical": M.plain(M.physical_signature(census)), "census": census,
		"books": ep_books(), "window_anchor": ep_anchor.duplicate(true), "trace": ep_trace.duplicate(true)}

func ep_native_sha(value: Variant) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func ep_boundary(day: int) -> bool:
	if not _clean(float(day)) or not ep_time(): return false
	if day > 0: return _world_contract(day == 1)
	var world: Dictionary = Game.world
	return (Game.seed_value == 4242 and world.get("seed") == 4242 and world.get("version") == 1
		and world.get("w") == 150 and world.get("h") == 96 and world.get("cell") == 24
		and M.equal_json(world.get("tf", 1.0), 1.0) and world.get("creatures_enabled") == true
		and Monsters.creatures_on and world.get("player_house", {}).is_empty()
		and not world.get("presim", {}).get("finished", false)) or _bad("day0_contract", "unaltered complete native generation required")

func ep_header_error(row: Dictionary, side: String, day: int, previous: String) -> String:
	if row.get("schema") != EP_SCHEMA or row.get("run") != ep["run"]: return "schema_run"
	if row.get("source_sha256") != ep_source_sha or not M.equal_json(row.get("params"), ep_params()): return "source_parameters"
	if row.get("side") != side or not M.equal_json(row.get("day"), day) or row.get("previous_manifest_sha256") != previous: return "day_chain"
	if row.get("clean") != true or row.get("pending_work") != 0: return "incomplete_boundary"
	var treasury: Variant = row.get("t23_treasury")
	if not (treasury is int or treasury is float) or not is_finite(float(treasury)) or float(treasury) < 0.0: return "t23_treasury"
	if row.get("same_live_continuation") != (day == 54): return "same_live_continuation"
	for key: String in ["native_sha256", "save_sha256", "observation_sha256", "physical_sha256", "snapshot_sha256", "shape_sha256", "trace_sha256"]:
		if not _sha(row.get(key)): return "hash_" + key
	var receipt: Variant = row.get("native_writer_receipt")
	if not receipt is Dictionary or receipt.get("ok") != true or receipt.get("error") != OK or receipt.get("stage") != "complete" or int(receipt.get("serialized_bytes", 0)) <= 0: return "native_writer_receipt"
	if day > 0 and _audit_error(row.get("daily_audit")) != "": return "daily_audit"
	if day >= 53 and (_audit_error(row.get("window_audit")) != "" or row.get("mint_job_seen") != true): return "mint_window_audit"
	return ""

func ep_record(side: String, day: int, expected: String) -> Dictionary:
	if not ep_pin(ep_path(side, day, "json"), expected): return {}
	var record_key: String = "%s/%d" % [side, day]
	if ep_records.has(record_key): return ep_records[record_key]
	var previous: String = ZERO_SHA
	var row: Dictionary = {}
	for index: int in range(day + 1):
		var path: String = ep_path(side, index, "json")
		var key: String = "%s/%d" % [side, index]
		if ep_records.has(key):
			row = ep_records[key]
			previous = str(ep_inputs[path])
			continue
		row = _read(path)
		if not _error.is_empty(): return {}
		var issue: String = ep_header_error(row, side, index, previous)
		if issue != "":
			_bad("checkpoint_contract", "%s/%d:%s" % [side, index, issue])
			return {}
		previous = FileAccess.get_sha256(path)
		if not ep_pin(path, previous) or not ep_time(): return {}
		ep_records[key] = row
	return row

func ep_endpoint_error(row: Dictionary, data: Dictionary) -> String:
	if not data.get("snapshot") is Dictionary or not data.get("observation") is Dictionary: return "endpoint_structure"
	var saved: Dictionary = data["snapshot"]
	var observed: Dictionary = data["observation"]
	if not M.equal_json(saved.get("day"), row.get("day")) or not M.equal_json(observed.get("day"), row.get("day")): return "endpoint_day"
	var treasury: Variant = row.get("t23_treasury")
	var saved_treasury: Variant = saved.get("world", {}).get("towns", {}).get("t23", {}).get("econ", {}).get("treasury")
	var observed_treasury: Variant = observed.get("towns", {}).get("t23", {}).get("metrics", {}).get("cash", {}).get("treasury")
	if not M.equal_json(treasury, saved_treasury) or not M.equal_json(treasury, observed_treasury): return "endpoint_treasury"
	return ""

func ep_data(row: Dictionary) -> Dictionary:
	var side: String = str(row["side"])
	var day: int = int(row["day"])
	if not ep_pin(ep_path(side, day, "save.json"), str(row["save_sha256"])): return {}
	var data: Dictionary = ep_native_read(ep_path(side, day, "native"), str(row["native_sha256"]))
	if data.is_empty(): return {}
	for key: String in ["snapshot", "shape", "observation", "physical", "census", "books", "window_anchor", "trace"]:
		if not data.has(key):
			_bad("native_companion", "missing " + key)
			return {}
	if not data["snapshot"] is Dictionary or not data["shape"] is Array or not data["trace"] is Array:
		_bad("native_companion", "snapshot/type/trace structure")
		return {}
	if ep_native_sha(data["snapshot"]) != row["snapshot_sha256"] or ep_native_sha(data["shape"]) != row["shape_sha256"] or M.digest(data["observation"]) != row["observation_sha256"] or M.digest(data["physical"]) != row["physical_sha256"] or ep_native_sha(data["trace"]) != row["trace_sha256"]:
		_bad("native_companion", "independent pre-write values/hashes differ")
		return {}
	var endpoint_issue: String = ep_endpoint_error(row, data)
	if endpoint_issue != "":
		_bad("native_endpoint_metadata", endpoint_issue)
		return {}
	if day > 0 and data["trace"].is_empty():
		_bad("treasury_trace", "missing complete native work trace")
		return {}
	var trace_issue: String = ep_trace_error(data["trace"], day)
	if trace_issue != "":
		_bad("treasury_trace", trace_issue)
		return {}
	if day == 53 and not ep_mint_seen(data["trace"]):
		_bad("native_mint_boundary", "manifest must be backed by the genuine recorded t23 bday")
		return {}
	return data

func ep_same(data: Dictionary) -> bool:
	var actual: Dictionary = ep_capture()
	if actual.is_empty(): return false
	for key: String in ["snapshot", "shape"]:
		if var_to_bytes(actual[key]) != var_to_bytes(data[key]): return _bad("native_exact_parity", "all values/order/types/float bits: " + key)
	for key: String in ["observation", "physical", "census", "books"]:
		if not M.equal_json(M.plain(actual[key]), M.plain(data[key])): return _bad("native_endpoint_parity", key + ":" + M.difference_json(M.plain(data[key]), M.plain(actual[key])))
	return ep_time()

func ep_load(row: Dictionary, data: Dictionary) -> bool:
	var path: String = ep_path(str(row["side"]), int(row["day"]), "save.json")
	if not ep_pin(path, str(row["save_sha256"])): return false
	Game.SAVE_PATH = path
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = _scratch
	if not loaded or not ep_restore_books(data["books"]): return _bad("native_load", path)
	ep_anchor = data["window_anchor"].duplicate(true)
	ep_trace = data["trace"].duplicate(true)
	return ep_boundary(int(row["day"])) and ep_same(data) and ep_pin(path, str(row["save_sha256"]))

func ep_treasury() -> float:
	var town: Dictionary = Game.world.get("towns", {}).get("t23", {})
	if not TownEcon.has_econ(town):
		_bad("native_t23", "Ithilspire t23 prerequisite missing")
		return NAN
	return float(town["econ"].get("treasury", NAN))

func ep_trace_plain(value: Variant) -> bool:
	if value is Array:
		for child: Variant in value:
			if not ep_trace_plain(child): return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not ep_trace_plain(key) or not ep_trace_plain(value[key]): return false
		return true
	return typeof(value) <= TYPE_STRING

func ep_trace_copy(value: Variant) -> Variant:
	# New untyped containers own every nested value; native containers stay untouched.
	if value is Array:
		var elements: Array = []
		for child: Variant in value: elements.append(ep_trace_copy(child))
		elements.make_read_only()
		return elements
	if value is Dictionary:
		var entries: Dictionary = {}
		for key: Variant in value:
			if typeof(key) > TYPE_STRING:
				_bad("trace_plain_data", "native job dictionary key is not plain data")
				return {}
			entries[key] = ep_trace_copy(value[key])
		entries.make_read_only()
		return entries
	if typeof(value) > TYPE_STRING:
		_bad("trace_plain_data", "unsupported native job value; never retain an Object or callable")
		return null
	return value

func ep_job_snapshot(job: Array) -> Array:
	var snapshot: Array = []
	for index: int in job.size():
		var value: Variant = job[index]
		if value is CampaignDayJob:
			if index != job.size() - 1:
				_bad("trace_continuation", "continuation must follow the complete logical header")
				return []
			var run: CampaignDayJob = value
			var native_script: Script = run.get_script()
			if native_script == null or native_script.resource_path.is_empty():
				_bad("trace_continuation", "native continuation script identity is missing")
				return []
			var progress: Dictionary = {"deferred_actions": run.after.size()}
			# Only explicit data fields: no game/town references, coroutine, RNG or callbacks.
			for property: Dictionary in run.get_property_list():
				var name: String = str(property["name"])
				if name in ["done", "budgeted", "holds_tree", "was_paused", "boundary", "yields", "_started", "_finished",
						"checkpoints", "visits", "yielded_labels", "town_id", "effect_day", "town_part", "day", "rng_states"]:
					progress[name] = run.get(name)
			if run is ArmyDayJob:
				var state: Dictionary = run.get("_s")
				progress["stage"] = state.get("stage")
				progress["index"] = state.get("i")
			# Instance ID is a scalar, stable for this native owner within this process.
			snapshot.append(ep_trace_copy({"continuation_schema": "economy_job_snapshot/1",
				"instance_id": run.get_instance_id(), "script": native_script.resource_path, "progress": progress}))
		else:
			snapshot.append(ep_trace_copy(Game._serialize(value)))
	snapshot.make_read_only()
	return snapshot

func ep_trace_error(trace: Array, day: int) -> String:
	if not ep_trace_plain(trace): return "native work trace contains non-data values"
	for index: int in trace.size():
		var value: Variant = trace[index]
		if not value is Dictionary: return "native work step is not a dictionary"
		var event: Dictionary = value
		if event.get("ordinal") != index or not M.equal_json(event.get("day"), day) or not event.get("job") is Array or event["job"].is_empty() or not is_finite(float(event.get("before", NAN))) or not is_finite(float(event.get("after", NAN))) or float(event["before"]) < 0.0 or float(event["after"]) < 0.0:
			return "incomplete/nonfinite/negative native work step"
		var job: Array = event["job"]
		if job[-1] is Dictionary and job[-1].has("continuation_schema"):
			var continuation: Dictionary = job[-1]
			if continuation.size() != 4 or continuation.get("continuation_schema") != "economy_job_snapshot/1" or not continuation.get("instance_id") is int or int(continuation["instance_id"]) == 0 or not continuation.get("script") is String or not str(continuation["script"]).begins_with("res://campaign/") or not continuation.get("progress") is Dictionary:
				return "invalid native continuation descriptor"
			var progress: Dictionary = continuation["progress"]
			for name: String in ["done", "budgeted", "holds_tree", "was_paused"]:
				if not progress.get(name) is bool: return "missing native continuation flag"
			if not progress.get("deferred_actions") is int or int(progress["deferred_actions"]) < 0: return "invalid deferred-action count"
	return ""

func ep_trace_job(before: bool, game: Node, job: Variant) -> void:
	if not is_same(game, Game):
		_bad("trace_game", "unexpected game instance")
		return
	var treasury: float = ep_treasury()
	if not is_finite(treasury) or treasury < 0.0: _bad("treasury", "Ithilspire treasury negative/nonfinite after an actual native work step")
	if before:
		if not ep_open.is_empty(): _bad("trace_order", "unclosed native work step")
		ep_open = {"ordinal": ep_trace.size(), "day": Game.day, "job": ep_job_snapshot(job), "before": treasury}
		WorldAudit.site = str(job[0])
	else:
		if ep_open.is_empty():
			_bad("trace_order", "native after-step without before-step")
			return
		ep_open["after"] = treasury
		ep_open.make_read_only()
		ep_trace.append(ep_open)
		ep_open = {}

func ep_mint_seen(trace: Array) -> bool:
	for event: Dictionary in trace:
		var job: Array = event["job"]
		if event["day"] == 53 and job.size() > 1 and job[0] == "bday" and job[1] == "t23": return true
	return false

func ep_step(tree: SceneTree, side: String, before: Dictionary) -> Dictionary:
	var from: int = int(Game.day)
	if not ep_boundary(from): return {}
	ep_trace = []
	ep_open = {}
	var treasury: float = ep_treasury()
	if not is_finite(treasury) or treasury < 0.0:
		_bad("treasury", "negative/nonfinite before native day")
		return {}
	if side == "A":
		Game.advance_time(1.0, false, 0, 1000)
		var yield_at: int = Time.get_ticks_msec() + 8
		while not Game.world.get("work", []).is_empty():
			if not _error.is_empty() or not ep_time(): return {}
			CampaignWorld.work_slice(Game, 1)
			if Time.get_ticks_msec() >= yield_at:
				await tree.process_frame
				yield_at = Time.get_ticks_msec() + 8
	else:
		# Independent native synchronous execution, with the same before/after hook.
		Game.advance_time(1.0, false, 0, 0)
	if not _error.is_empty() or not ep_open.is_empty() or not ep_boundary(from + 1): return {}
	var next: Dictionary = ep_capture()
	if next.is_empty(): return {}
	for race: String in RACES + ["WORLD"]:
		if M.census_residual(before["observation"]["groups"][race], next["observation"]["groups"][race]) != 0:
			_bad("native_daily_census", race)
			return {}
	var audit: Dictionary = WorldAudit.compare(before["census"], next["census"])
	if _audit_error(audit) != "":
		_bad("native_daily_conservation", _audit_error(audit))
		return {}
	next["daily_audit"] = audit
	if from + 1 == 46:
		ep_anchor = next["census"].duplicate(true)
		next["window_anchor"] = ep_anchor.duplicate(true)
	if from + 1 >= 53:
		var window: Dictionary = WorldAudit.compare(ep_anchor, next["census"])
		if _audit_error(window) != "":
			_bad("native_whole_mint_window", _audit_error(window))
			return {}
		next["window_audit"] = window
	return next if ep_time() else {}

func ep_save(side: String, day: int, data: Dictionary, previous: String, mint_seen: bool = false) -> Dictionary:
	if not ep_boundary(day) or not ep_unchanged(): return {}
	var base: String = ep_path(side, day, "")
	if DirAccess.make_dir_recursive_absolute(ep_root.path_join(side)) != OK:
		_bad("side_directory", side)
		return {}
	for suffix: String in ["json", "save.json", "native"]:
		if FileAccess.file_exists(base + suffix):
			_bad("duplicate_checkpoint", base + suffix)
			return {}
	var trace_issue: String = ep_trace_error(data["trace"], day)
	if trace_issue != "":
		_bad("treasury_trace", trace_issue)
		return {}
	# Independent complete pre-write snapshot and live type shape, kept as native data.
	if not ep_native_write(base + "native", data): return {}
	var payload: Dictionary = data["snapshot"]
	var write: Dictionary = Game._write_save(base + "save.json", payload)
	Game.wait_save()
	var stats: Dictionary = Game.save_stats()
	if write.get("ok") != true or write.get("stage") != "complete" or write.get("error") != OK or int(write.get("serialized_bytes", 0)) <= 0 or stats.get("pending", true) or stats.get("active_snapshots", -1) != 0:
		_bad("native_writer_receipt", "native writer did not complete")
		return {}
	var saved: Dictionary = _read(base + "save.json")
	if not _error.is_empty() or saved.get("version") != 2 or saved.get("world", {}).get("version") != 1 or saved.get("day") != day or not saved.get("world", {}).get("work", []).is_empty():
		_bad("native_saved_boundary", base)
		return {}
	# Decoder output must be the entire independent pre-write tree, including order/types.
	if var_to_bytes(saved) != var_to_bytes(payload):
		_bad("native_writer_readback", "complete native saved data differs from pre-write snapshot")
		return {}
	saved = {}
	var row: Dictionary = {"schema": EP_SCHEMA, "run": ep["run"], "params": ep_params(), "source_sha256": ep_source_sha,
		"side": side, "day": day, "clean": true, "pending_work": 0, "previous_manifest_sha256": previous,
		"save_sha256": FileAccess.get_sha256(base + "save.json"), "native_sha256": FileAccess.get_sha256(base + "native"),
		"snapshot_sha256": ep_native_sha(payload), "shape_sha256": ep_native_sha(data["shape"]), "trace_sha256": ep_native_sha(data["trace"]),
		"observation_sha256": M.digest(data["observation"]), "physical_sha256": M.digest(data["physical"]),
		"native_writer_receipt": write, "daily_audit": data.get("daily_audit", {}),
		"window_audit": data.get("window_audit", {}), "mint_job_seen": mint_seen,
		"t23_treasury": ep_treasury(), "same_live_continuation": day == 54}
	var issue: String = ep_header_error(row, side, day, previous)
	if issue != "":
		_bad("new_checkpoint_contract", issue)
		return {}
	# Validate companion readback and unchanged live state BEFORE committing the manifest.
	var native: Dictionary = ep_native_read(base + "native", str(row["native_sha256"]))
	if native.is_empty(): return {}
	if var_to_bytes(native.get("trace")) != var_to_bytes(data["trace"]):
		_bad("native_trace_readback", "complete step evidence differs from the pre-write trace")
		return {}
	if not ep_same(native) or not ep_unchanged(): return {}
	if not _write_new(base + "json", row): return {}
	ep_inputs[base + "json"] = FileAccess.get_sha256(base + "json")
	ep_inputs[base + "save.json"] = row["save_sha256"]
	return row

func ep_generate(tree: SceneTree, side: String) -> Dictionary:
	if FileAccess.file_exists(DevTools.world_path(true)):
		_bad("nonfresh_fixture_cache", "fresh isolated profile required; do not delete or reuse a cache")
		return {}
	WorldGen.gen_size = "normal"
	WorldGen.gen_stretch = 1.5
	CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = true
	var generation: Dictionary = Game.new_game_begin(4242)
	if side == "A":
		while not Game.new_game_slice(generation, 8000):
			if not ep_time(): return {}
			await tree.process_frame
	else:
		while not CampaignWorld.generate_part(Game, generation):
			if not ep_time(): return {}
	# Day0 is the full native generation, not an invented late-game fixture.
	if not ep_boundary(0): return {}
	var data: Dictionary = ep_capture()
	return ep_save(side, 0, data, ZERO_SHA) if not data.is_empty() else {}

func ep_history(tree: SceneTree, side: String, before: Dictionary) -> Dictionary:
	ep_trace = []
	ep_open = {}
	if side == "A":
		var history: Dictionary = {}
		while CampaignWorld.presim_left(Game) > 0:
			CampaignWorld.presim_slice(Game, history, 8000)
			if not _error.is_empty() or not ep_time(): return {}
			await tree.process_frame
	else:
		CampaignWorld.presim_step(Game, 1)
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	var town: String = DevTools.choose_house(Game)
	if town.is_empty():
		_bad("native_observer", "no eligible existing household")
		return {}
	DevTools.stand_at(Game, town) # Original native onboarding only, never later.
	if not ep_boundary(1): return {}
	var next: Dictionary = ep_capture()
	if next.is_empty(): return {}
	for race: String in RACES + ["WORLD"]:
		if M.census_residual(before["observation"]["groups"][race], next["observation"]["groups"][race]) != 0:
			_bad("history_census", race)
			return {}
	next["daily_audit"] = WorldAudit.compare(before["census"], next["census"])
	if _audit_error(next["daily_audit"]) != "":
		_bad("history_conservation", _audit_error(next["daily_audit"]))
		return {}
	return next

func ep_produce(tree: SceneTree) -> Dictionary:
	var side: String = str(ep["side"])
	var day: int = int(ep["day"])
	if ep["mode"] == "generate": return await ep_generate(tree, side)
	var previous: Dictionary = ep_record(side, day - 1, str(ep["previous-sha"]))
	if previous.is_empty(): return {}
	var before: Dictionary = ep_data(previous)
	if before.is_empty() or not ep_load(previous, before): return {}
	if CampaignWorld.economy_protocol_observer.is_valid():
		_bad("trace_in_use", "another observer owns native work")
		return {}
	CampaignWorld.economy_protocol_observer = Callable(self, "ep_trace_job")
	var next: Dictionary = {}
	if day == 1: next = await ep_history(tree, side, before)
	else: next = await ep_step(tree, side, before)
	if next.is_empty(): return {}
	var mint_seen: bool = ep_mint_seen(ep_trace)
	if day == 53 and not mint_seen:
		_bad("native_mint_boundary", "genuine t23 bday at native day53 not reproduced; never force or skip it")
		return {}
	var row: Dictionary = ep_save(side, day, next, str(ep["previous-sha"]), mint_seen)
	if row.is_empty(): return {}
	if day == 53:
		# No load between writing53 and advancing54: this is the actual live continuation.
		var live: Dictionary = await ep_step(tree, side, next)
		if live.is_empty(): return {}
		var sha53: String = FileAccess.get_sha256(ep_path(side, 53, "json"))
		var row54: Dictionary = ep_save(side, 54, live, sha53, mint_seen)
		if row54.is_empty(): return {}
		row["live54_manifest_sha256"] = FileAccess.get_sha256(ep_path(side, 54, "json"))
	return row

func ep_day_batch(tree: SceneTree) -> Dictionary:
	# Repeat the original complete producer, including its native load and all gates.
	# _started is never reset: the SAME 40-second deadline covers the whole batch.
	var request: Dictionary = ep.duplicate(true)
	var side: String = str(ep["side"])
	var first_day: int = int(ep["from-day"])
	var last_day: int = int(ep["day"])
	var previous_sha: String = str(ep["previous-sha"])
	var checkpoints: Array = []
	for day: int in range(first_day, last_day + 1):
		ep["mode"] = "day"
		ep["day"] = day
		ep["previous-sha"] = previous_sha
		var row: Dictionary = await ep_produce(tree)
		# Match run_current cleanup before the next original ep_produce claims the hook.
		if CampaignWorld.economy_protocol_observer == Callable(self, "ep_trace_job"):
			CampaignWorld.economy_protocol_observer = Callable()
			WorldAudit.site = ""
		if row.is_empty() or not _error.is_empty() or not ep_time():
			ep = request
			return {}
		var path: String = ep_path(side, day, "json")
		previous_sha = FileAccess.get_sha256(path)
		if not ep_pin(path, previous_sha):
			ep = request
			return {}
		checkpoints.append({"day": day, "manifest_sha256": previous_sha, "elapsed_ms": _elapsed()})
	ep = request
	return {"kind": "producer_batch_complete", "side": side, "from_day": first_day, "to_day": last_day,
		"native_days_advanced": last_day - first_day + 1, "checkpoints": checkpoints}

func ep_cross_path(day: int) -> String:
	return ep_root.path_join("expected%02d.json" % day)

func ep_certificate(day: int, expected: String) -> Dictionary:
	var path: String = ep_cross_path(day)
	if not ep_pin(path, expected): return {}
	var certificate: Dictionary = _read(path)
	if certificate.get("schema") != EP_SCHEMA or certificate.get("kind") != "independently_verified_expected" or certificate.get("run") != ep["run"] or certificate.get("source_sha256") != ep_source_sha or not M.equal_json(certificate.get("params"), ep_params()) or certificate.get("day") != day:
		_bad("expected_contract", path)
		return {}
	for key: String in ["A_manifest_sha256", "B_manifest_sha256", "previous_expected_sha256"]:
		if not _sha(certificate.get(key)):
			_bad("expected_contract", key)
			return {}
	return certificate

func ep_cross() -> Dictionary:
	var day: int = int(ep["day"])
	var a: Dictionary = ep_record("A", day, str(ep["a-sha"]))
	var b: Dictionary = ep_record("B", day, str(ep["b-sha"]))
	if a.is_empty() or b.is_empty(): return {}
	var previous_sha: String = ZERO_SHA
	if day > 0:
		previous_sha = str(ep["cross-previous-sha"])
		var previous: Dictionary = ep_certificate(day - 1, previous_sha)
		if previous.is_empty(): return {}
		if previous["A_manifest_sha256"] != a["previous_manifest_sha256"] or previous["B_manifest_sha256"] != b["previous_manifest_sha256"]:
			_bad("expected_chain", "independent native predecessors differ from previous certificate")
			return {}
	var actual: Dictionary = ep_data(a)
	var oracle: Dictionary = ep_data(b)
	if actual.is_empty() or oracle.is_empty(): return {}
	for key: String in ["snapshot", "shape"]:
		if var_to_bytes(actual[key]) != var_to_bytes(oracle[key]):
			_bad("independent_native_replay", "exact values/order/types/float bits differ: " + key)
			return {}
	for key: String in ["observation", "physical"]:
		if not M.equal_json(actual[key], oracle[key]):
			_bad("independent_measurement", M.difference_json(oracle[key], actual[key], key))
			return {}
	if day >= 53 and (not b["mint_job_seen"] or not a["mint_job_seen"]):
		_bad("independent_mint_boundary", "both native runs must reproduce day53 t23 bday")
		return {}
	var certificate: Dictionary = {"schema": EP_SCHEMA, "kind": "independently_verified_expected", "run": ep["run"],
		"source_sha256": ep_source_sha, "params": ep_params(), "day": day, "previous_expected_sha256": previous_sha,
		"A_manifest_sha256": ep["a-sha"], "B_manifest_sha256": ep["b-sha"],
		"expected_native_file": ProjectSettings.globalize_path(ep_path("B", day, "native")),
		"expected_native_sha256": b["native_sha256"], "snapshot_sha256": b["snapshot_sha256"],
		"shape_sha256": b["shape_sha256"], "observation_sha256": b["observation_sha256"], "physical_sha256": b["physical_sha256"],
		"t23_treasury": b["t23_treasury"], "derivation": "separate fresh native B generation + atomic work, exact cross-check against sliced A; conservation/census independently required"}
	if not ep_unchanged() or not _write_new(ep_cross_path(day), certificate): return {}
	return certificate

func ep_cross_batch() -> Dictionary:
	# Pin both terminal producer manifests BEFORE deriving any interior hash.
	# Their checked predecessor chains authenticate every included producer day.
	var first_day: int = int(ep["from-day"])
	var last_day: int = int(ep["day"])
	if ep_record("A", last_day, str(ep["a-sha"])).is_empty() or ep_record("B", last_day, str(ep["b-sha"])).is_empty(): return {}
	var request: Dictionary = ep.duplicate(true)
	var previous: String = str(ep["cross-previous-sha"])
	var certificates: Array = []
	for day: int in range(first_day, last_day + 1):
		ep["day"] = day
		ep["a-sha"] = ep_inputs[ep_path("A", day, "json")]
		ep["b-sha"] = ep_inputs[ep_path("B", day, "json")]
		ep["cross-previous-sha"] = previous
		var certificate: Dictionary = ep_cross()
		if certificate.is_empty():
			ep = request
			return {}
		previous = FileAccess.get_sha256(ep_cross_path(day))
		certificates.append({"day": day, "expected_sha256": previous,
			"A_manifest_sha256": certificate["A_manifest_sha256"], "B_manifest_sha256": certificate["B_manifest_sha256"]})
	ep = request
	return {"kind": "expected_batch_complete", "from_day": first_day, "to_day": last_day, "certificates": certificates}

func ep_reload(tree: SceneTree) -> Dictionary:
	var cert53: Dictionary = ep_certificate(53, str(ep["cross53-sha"]))
	var cert54: Dictionary = ep_certificate(54, str(ep["cross54-sha"]))
	if cert53.is_empty() or cert54.is_empty() or cert54["previous_expected_sha256"] != ep["cross53-sha"]: return {}
	var saved: Dictionary = ep_record("A", 53, str(cert53["A_manifest_sha256"]))
	var live: Dictionary = ep_record("A", 54, str(cert54["A_manifest_sha256"]))
	if saved.is_empty() or live.is_empty(): return {}
	var expected53: Dictionary = ep_data(saved)
	var expected54: Dictionary = ep_data(live)
	if expected53.is_empty() or expected54.is_empty() or not ep_load(saved, expected53): return {}
	if CampaignWorld.economy_protocol_observer.is_valid():
		_bad("trace_in_use", "another observer owns native work")
		return {}
	CampaignWorld.economy_protocol_observer = Callable(self, "ep_trace_job")
	var next: Dictionary = await ep_step(tree, "A", expected53)
	if next.is_empty() or not ep_same(expected54): return {}
	if not ep_unchanged(): return {}
	var receipt: Dictionary = {"schema": EP_SCHEMA, "kind": "fresh_reload_pass", "run": ep["run"], "source_sha256": ep_source_sha,
		"cross53_sha256": ep["cross53-sha"], "cross54_sha256": ep["cross54-sha"], "saved_day": 53, "resumed_day": 54,
		"saved_manifest_sha256": cert53["A_manifest_sha256"], "live_manifest_sha256": cert54["A_manifest_sha256"],
		"resumed_snapshot_sha256": ep_native_sha(next["snapshot"]), "resumed_observation_sha256": M.digest(next["observation"]),
		"daily_audit": next["daily_audit"], "window_audit": next["window_audit"], "all_inputs_unchanged": true}
	if not _write_new(ep_root.path_join("reload.json"), receipt): return {}
	return receipt

func ep_trace_controls() -> bool:
	# Local constructor only: no world generation, coroutine step or RNG draw.
	var header: Array = ["tturn", "t23", 0, {"nested": [1, {"value": 2}]}]
	var run: CampaignTurnJob = CampaignTurnJob.new(header)
	run.visits = {"control": [{"count": 1}]}
	var job: Array = header.duplicate()
	job.append(run)
	var frozen_job: Array = ep_job_snapshot(job)
	var trace: Array = [{"ordinal": 0, "day": 0, "job": frozen_job, "before": 7.0, "after": 7.0}]
	var frozen: PackedByteArray = var_to_bytes(trace)
	if not _error.is_empty() or ep_trace_error(trace, 0) != "" or ep_trace_plain([run]) or ep_trace_plain([Callable()]):
		return _bad("trace_snapshot_control", "valid synthetic descriptor and rejection of live values required")
	# Change the original header, nested progress and the same native continuation.
	header[3]["nested"][1]["value"] = 99
	job[0] = "changed"
	run.boundary = "resumed"
	run.yields = 1
	run.checkpoints = 1
	run.visits["control"][0]["count"] = 99
	run.done = true
	var resumed: Array = ep_job_snapshot(job)
	var first: Dictionary = frozen_job[-1]
	var later: Dictionary = resumed[-1]
	if not _error.is_empty() or var_to_bytes(trace) != frozen or frozen_job[0] != "tturn" or frozen_job[3]["nested"][1]["value"] != 2 or first["progress"]["visits"]["control"][0]["count"] != 1 or first["progress"]["done"] != false:
		return _bad("trace_snapshot_control", "earlier step changed after its native owner resumed")
	if first["instance_id"] != later["instance_id"] or first["script"] != later["script"] or var_to_bytes(first["progress"]) == var_to_bytes(later["progress"]):
		return _bad("trace_identity_control", "same native owner must retain identity and witness changed progress")
	var path: String = ep_root.path_join("trace_snapshot_control.native")
	if not ep_native_write(path, {"trace": trace}): return false
	var restored: Dictionary = ep_native_read(path, FileAccess.get_sha256(path))
	if not restored.get("trace") is Array or ep_trace_error(restored["trace"], 0) != "" or var_to_bytes(restored["trace"]) != frozen:
		return _bad("trace_readback_control", "complete synthetic trace did not survive companion readback")
	return true

func ep_controls() -> Dictionary:
	# All original synthetic manifest/range/JSON/physical/negative controls execute unchanged.
	if _contract() != 0: return {}
	var historical: Variant = load("res://tests/test_economy_stability_v094.gd").new()
	if historical._static_contract():
		_bad("historical_pin", "original 0.094 gate must still reject this current application")
		return {}
	var toy: Dictionary = {"schema": EP_SCHEMA, "run": ep["run"], "params": ep_params(), "source_sha256": ep_source_sha,
		"side": "A", "day": 0, "clean": true, "pending_work": 0, "previous_manifest_sha256": ZERO_SHA,
		"native_sha256": ZERO_SHA, "save_sha256": ZERO_SHA, "observation_sha256": ZERO_SHA, "physical_sha256": ZERO_SHA,
		"snapshot_sha256": ZERO_SHA, "shape_sha256": ZERO_SHA, "trace_sha256": ZERO_SHA, "t23_treasury": 0.0, "same_live_continuation": false,
		"native_writer_receipt": {"ok": true, "error": OK, "stage": "complete", "serialized_bytes": 1}}
	if ep_header_error(toy, "A", 0, ZERO_SHA) != "":
		_bad("new_positive_control", "valid synthetic current manifest")
		return {}
	var header_cases: Array = [["schema", "wrong"], ["run", "wrong"], ["params", {}], ["source_sha256", "wrong"],
		["side", "B"], ["day", 1], ["clean", false], ["pending_work", 1], ["previous_manifest_sha256", "wrong"],
		["native_sha256", "bad"], ["save_sha256", "bad"], ["observation_sha256", "bad"], ["physical_sha256", "bad"],
		["snapshot_sha256", "bad"], ["shape_sha256", "bad"], ["trace_sha256", "bad"], ["native_writer_receipt", {}],
		["t23_treasury", "wrong"], ["t23_treasury", -1.0], ["t23_treasury", NAN], ["same_live_continuation", true]]
	for pair: Array in header_cases:
		var changed: Dictionary = toy.duplicate(true)
		changed[pair[0]] = pair[1]
		if ep_header_error(changed, "A", 0, ZERO_SHA) == "":
			_bad("new_negative_control", str(pair[0]))
			return {}
	var endpoint: Dictionary = {"snapshot": {"day": 0, "world": {"towns": {"t23": {"econ": {"treasury": 0.0}}}}},
		"observation": {"day": 0, "towns": {"t23": {"metrics": {"cash": {"treasury": 0.0}}}}}}
	if ep_endpoint_error(toy, endpoint) != "": return {}
	var wrong_scalar: Dictionary = toy.duplicate(true)
	wrong_scalar["t23_treasury"] = 1.0
	if ep_endpoint_error(wrong_scalar, endpoint) == "": return {}
	var wrong_snapshot: Dictionary = endpoint.duplicate(true)
	wrong_snapshot["snapshot"]["world"]["towns"]["t23"]["econ"]["treasury"] = 1.0
	if ep_endpoint_error(toy, wrong_snapshot) == "": return {}
	var wrong_observation: Dictionary = endpoint.duplicate(true)
	wrong_observation["observation"]["towns"]["t23"]["metrics"]["cash"]["treasury"] = 1.0
	if ep_endpoint_error(toy, wrong_observation) == "": return {}
	var wrong_day: Dictionary = endpoint.duplicate(true)
	wrong_day["snapshot"]["day"] = 1
	if ep_endpoint_error(toy, wrong_day) == "": return {}
	var typed_values: Array[int]
	typed_values.append(1)
	var plain_values: Array = [1]
	if var_to_bytes(ep_shape(typed_values)) == var_to_bytes(ep_shape(plain_values)):
		_bad("type_witness_control", "typed and untyped arrays must differ")
		return {}
	# Identical saved Unit values must still witness different live body-parts types.
	var typed_parts: Dictionary[String, Dictionary]
	var typed_unit: Unit = Unit.new()
	typed_unit.body = BodyState.new()
	typed_unit.body.parts = typed_parts
	var plain_unit: Unit = Unit.new()
	plain_unit.body = BodyState.new()
	if var_to_bytes(typed_unit.to_dict()) != var_to_bytes(plain_unit.to_dict()):
		_bad("body_type_control_fixture", "saved Unit values must be identical in this synthetic control")
		return {}
	if var_to_bytes(ep_shape(typed_unit)) == var_to_bytes(ep_shape(plain_unit)):
		_bad("body_type_witness_control", "typed and untyped live body.parts must differ before save normalization")
		return {}
	if not ep_trace_controls(): return {}
	var receipt: Dictionary = {"schema": EP_SCHEMA, "kind": "controls_pass", "run": ep["run"], "source_sha256": ep_source_sha,
		"all_original_synthetic_controls": true, "historical_exact_version_rejection": true, "new_manifest_controls": header_cases.size() + 1, "endpoint_binding_controls": 5, "type_witness_controls": 2,
		"trace_snapshot_controls": 3, "native_days_advanced": 0, "longCampaignComplete": false}
	if not ep_unchanged() or not _write_new(ep_root.path_join("controls.json"), receipt): return {}
	return receipt

func ep_final() -> Dictionary:
	var cert53: Dictionary = ep_certificate(53, str(ep["cross53-sha"]))
	var cert54: Dictionary = ep_certificate(54, str(ep["cross54-sha"]))
	if cert53.is_empty() or cert54.is_empty(): return {}
	if not ep_pin(ep_root.path_join("controls.json"), str(ep["controls-sha"])) or not ep_pin(ep_root.path_join("reload.json"), str(ep["reload-sha"])): return {}
	var controls: Dictionary = _read(ep_root.path_join("controls.json"))
	var reload: Dictionary = _read(ep_root.path_join("reload.json"))
	if controls.get("kind") != "controls_pass" or controls.get("all_original_synthetic_controls") != true or controls.get("trace_snapshot_controls") != 3 or reload.get("kind") != "fresh_reload_pass" or reload.get("cross53_sha256") != ep["cross53-sha"] or reload.get("cross54_sha256") != ep["cross54-sha"]:
		_bad("acceptance_union", "complete current controls and exact fresh reload required")
		return {}
	for receipt: Dictionary in [controls, reload]:
		if receipt.get("schema") != EP_SCHEMA or receipt.get("run") != ep["run"] or receipt.get("source_sha256") != ep_source_sha:
			_bad("receipt_source", "receipt from another experiment")
			return {}
	var expected: String = str(ep["cross54-sha"])
	for day: int in range(54, -1, -1):
		var certificate: Dictionary = ep_certificate(day, expected)
		if certificate.is_empty(): return {}
		for side: String in ["A", "B"]:
			var row: Dictionary = ep_record(side, day, str(certificate[side + "_manifest_sha256"]))
			if row.is_empty(): return {}
			for suffix: String in ["native", "save.json"]:
				var sha: String = str(row["native_sha256"] if suffix == "native" else row["save_sha256"])
				if not ep_pin(ep_path(side, day, suffix), sha) or not ep_time(): return {}
		expected = str(certificate["previous_expected_sha256"])
	if expected != ZERO_SHA or not ep_unchanged(): return {}
	var result: Dictionary = {"schema": EP_SCHEMA, "kind": "complete_short_acceptance", "run": ep["run"], "source_sha256": ep_source_sha,
		"controls_sha256": ep["controls-sha"], "reload_sha256": ep["reload-sha"], "expected54_sha256": ep["cross54-sha"],
		"current251ShortAcceptancePass": true, "current260ControlsPass": true, "independent_expected_days": 55,
		"native_fixture_day": 46, "saved_day": 53, "live_and_resumed_day": 54, "longCampaignComplete": false,
		"historical094": "preserved and deliberately rejects the current application"}
	if not _write_new(ep_root.path_join("acceptance.json"), result): return {}
	return result

func run_current(tree: SceneTree, entry: String) -> int:
	_started = Time.get_ticks_msec()
	var result: Dictionary = {}
	if ep_parse(entry) and _static_contract():
		Game.wait_save()
		Game.settings["autosave"] = "off" # Existing isolated-process-only override.
		if ep_source():
			match str(ep["mode"]):
				"freeze": result = {"source_sha256": ep_source_sha, "kind": "source_frozen"}
				"controls": result = ep_controls()
				"generate", "history", "day", "mint": result = await ep_produce(tree)
				"day-batch": result = await ep_day_batch(tree)
				"cross": result = ep_cross()
				"cross-batch": result = ep_cross_batch()
				"reload": result = await ep_reload(tree)
				"final": result = ep_final()
	if CampaignWorld.economy_protocol_observer == Callable(self, "ep_trace_job"):
		CampaignWorld.economy_protocol_observer = Callable()
		WorldAudit.site = ""
	var passed: bool = not result.is_empty() and _error.is_empty() and ep_time()
	if passed: passed = ep_unchanged()
	if not passed:
		if _error.is_empty(): _bad("incomplete", "no explicit complete result")
		if not ep_root.is_empty() and DirAccess.dir_exists_absolute(ep_root):
			_write_new(ep_root.path_join("failure_%s_%s_%s.json" % [str(ep.get("mode", "")), str(ep.get("side", "")), str(ep.get("day", ""))]), {"schema": EP_SCHEMA, "error": _error, "complete": false})
	var output: Dictionary = {"schema": EP_SCHEMA, "ok": passed, "mode": ep.get("mode", ""), "side": ep.get("side", ""), "day": ep.get("day", -1),
		"source_sha256": ep_source_sha, "result": result, "error": _error, "elapsed_ms": _elapsed(), "longCampaignComplete": false}
	for name: String in ["controls.json", "reload.json", "acceptance.json"]:
		if FileAccess.file_exists(ep_root.path_join(name)): output[name + "_sha256"] = FileAccess.get_sha256(ep_root.path_join(name))
	if ep.get("mode") in ["generate", "history", "day", "day-batch", "mint"]:
		for day: int in [int(ep["day"]), 54 if ep["mode"] == "mint" else int(ep["day"])]:
			var path: String = ep_path(str(ep["side"]), day, "json")
			if FileAccess.file_exists(path): output["manifest%02d_sha256" % day] = FileAccess.get_sha256(path)
	if ep.get("mode") == "cross" and FileAccess.file_exists(ep_cross_path(int(ep["day"]))):
		output["expected_sha256"] = FileAccess.get_sha256(ep_cross_path(int(ep["day"])))
	print("ECONOMY_CURRENT_V099_R1 " + M.text(output))
	return 0 if passed else 1
