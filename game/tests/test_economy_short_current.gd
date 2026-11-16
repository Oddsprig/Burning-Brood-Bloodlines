extends RefCounted
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief. A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.
## Source-only current-version port. The lead submits each part separately through Test Bridge.
const M: GDScript = preload("res://tests/economy_stability_v094.gd")
const Protocol: GDScript = preload("res://tests/test_economy_stability_current.gd")
const SCHEMA: String = "economy_short_current/1"
const LIMIT_MS: int = 50000
var h: Protocol = Protocol.new()
var _started: int = 0
var _root: String = ""
var _part: String = ""
var _source: Dictionary = {}
var _params: Dictionary = {}
var _opts: Dictionary = {}
var _failed: Array = []
var _checks: int = 0
var _previous: Dictionary = {}
var _previous_sha: String = Protocol.ZERO_SHA
var _data: Dictionary = {}
var _live_manifest: Dictionary = {}

# Observe every actual dispatch, including work performed inside advance_time().
# Nested profiler labels cannot count as completions. Native calculations are untouched.
class TreasuryTrace extends PerformanceTracker:
	var recording: bool = false
	var pending: Dictionary = {}
	var rows: Array = []
	var samples: int = 0
	var invalid: bool = false
	var negative: bool = false
	var mint_seen: bool = false

	func set_stage(stage: String) -> void:
		super.set_stage(stage)
		if not recording: return
		var work: Array = Game.world.get("work", [])
		if work.is_empty(): return
		var head: Array = work[0]
		var kind: String = String(head[0])
		var label: String = String(CampaignWorld.WORK_LABELS.get(kind, kind.replace("_", " ").capitalize()))
		if stage != label: return
		if not pending.is_empty(): invalid = true
		var header: Array = head.slice(0, head.size() - (1 if head[-1] is CampaignDayJob else 0))
		var totals: Array = CampaignWorld.job_total.get(kind, [0, 0])
		pending = {"head": head, "header": M.plain(header), "kind": kind, "label": label,
			"count": int(totals[1]), "treasury": float(Game.world["towns"]["t23"]["econ"]["treasury"])}

	func record_us(label: String, elapsed_us: int, overall: bool = false) -> void:
		super.record_us(label, elapsed_us, overall)
		if not recording or overall or pending.is_empty() or label != String(pending["label"]): return
		var totals: Array = CampaignWorld.job_total.get(String(pending["kind"]), [0, 0])
		if int(totals[1]) == int(pending["count"]): return
		if int(totals[1]) != int(pending["count"]) + 1: invalid = true
		var head: Array = pending["head"]
		var header: Array = pending["header"]
		var complete: bool = not head[-1] is CampaignDayJob or (head[-1] as CampaignDayJob).done
		var before: float = float(pending["treasury"])
		var after: float = float(Game.world["towns"]["t23"]["econ"]["treasury"])
		var target: bool = header.size() > 1 and header[0] == "bday" and header[1] == "t23"
		if before != after or target:
			rows.append({"day": Game.day, "job": header, "before": before, "after": after, "complete": complete})
		samples += 1
		if not is_finite(before) or not is_finite(after) or before < 0.0 or after < 0.0: negative = true
		if Game.day == 53.0 and target and complete: mint_seen = true
		pending = {}


func _check(ok: bool, label: String) -> bool:
	_checks += 1
	if not ok:
		_failed.append(label)
		printerr("FAIL short current: ", label)
	return ok


func _time() -> bool:
	return _check(Time.get_ticks_msec() - _started < LIMIT_MS, "entire selected part stays within 50 seconds")


func _path(day: int, suffix: String) -> String:
	return _root.path_join("day%02d.%s" % [day, suffix])


func _wire(value: Variant) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(value))


func _unwire(value: String) -> Dictionary:
	var decoded: Variant = bytes_to_var(Marshalls.base64_to_raw(value))
	if not _check(decoded is Dictionary, "typed read-only audit state decodes"): return {}
	return decoded


func _native_hash(value: Variant) -> String:
	# Exact native types, float bits, packed arrays and dictionary order, including int Item keys.
	return var_to_bytes(value).hex_encode().sha256_text()


func _books() -> Dictionary:
	return {"tracking": WorldAudit.tracking, "items_gone": WorldAudit.items_gone.duplicate(true),
		"gone_by": WorldAudit.gone_by.duplicate(true), "rations": WorldAudit.rations.duplicate(true),
		"treasure_book": WorldAudit.treasure_book.duplicate(true), "unmade_ids": WorldAudit.unmade_ids.duplicate(true),
		"unmade_by": WorldAudit.unmade_by.duplicate(true), "made_log": WorldAudit.made_log.duplicate(true),
		"rolled_ids": WorldAudit.rolled_ids.duplicate(true), "site": WorldAudit.site}


func _restore_books(value: Dictionary) -> bool:
	if not _check(value.size() == 10 and value.get("tracking") is bool and value.get("items_gone") is Array and value.get("site") is String, "complete observation-only audit books"): return false
	for key: String in ["gone_by", "rations", "treasure_book", "unmade_ids", "unmade_by", "made_log", "rolled_ids"]:
		if not _check(value.get(key) is Dictionary, "native audit book " + key): return false
	# These are measurement logs only. No Game/world/economy field or tolerance is assigned.
	WorldAudit.tracking = bool(value["tracking"])
	WorldAudit.items_gone = value["items_gone"]
	WorldAudit.gone_by = value["gone_by"]
	WorldAudit.rations = value["rations"]
	WorldAudit.treasure_book = value["treasure_book"]
	WorldAudit.unmade_ids = value["unmade_ids"]
	WorldAudit.unmade_by = value["unmade_by"]
	WorldAudit.made_log = value["made_log"]
	WorldAudit.rolled_ids = value["rolled_ids"]
	WorldAudit.site = String(value["site"])
	return _check(_native_hash(_books()) == _native_hash(value), "exact observation log handoff; native int identity keys retained")


func _snapshot() -> Dictionary:
	var observation: Dictionary = h._observe(M.maker_types())
	if not _check(h._error.is_empty() and not observation.is_empty(), "physical holdings and all measurement groups"): return {}
	var census: Dictionary = WorldAudit.census(Game)
	return {"observation": observation, "physical": M.plain(M.physical_signature(census))}


func _clean(day: float) -> bool:
	return _check(h._clean(day) and h._world_contract(false) and not Game._day_job_transaction_active() and not Game._day_job_fence_pending(), "complete native day, released owner/fence, original seed/size/history/creatures contract")


func _parse() -> bool:
	_opts = {"part": "", "phase": "", "previous-sha": ""}
	var seen: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--current-"): continue
		var fields: PackedStringArray = argument.substr(10).split("=", true, 1)
		if not _check(fields.size() == 2 and _opts.has(fields[0]) and not seen.has(fields[0]), "known unique current option"): return false
		seen[fields[0]] = true
		_opts[fields[0]] = fields[1]
	_part = str(_opts["part"])
	var phase: String = str(_opts["phase"])
	if not _check(phase.length() > 0 and phase.length() <= 64, "explicit fresh task phase"): return false
	for character: String in phase:
		if not _check(character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-", "phase has no path traversal"): return false
	_root = Protocol.ROOT.path_join(phase)
	if _part in ["seed", "live", "reload"]: return true
	if not _check(_part.begins_with("day") and _part.substr(3).is_valid_int(), "part is seed, day2..day53, live or reload"): return false
	return _check(_part == "day%d" % _part.substr(3).to_int() and _part.substr(3).to_int() >= 2 and _part.substr(3).to_int() <= 53, "exact one-real-day selector")


func _reserve() -> bool:
	if _part == "seed":
		if not _check(not DirAccess.dir_exists_absolute(_root) and str(_opts["previous-sha"]) == "", "fresh phase, no inherited predecessor"): return false
		if not _check(DirAccess.make_dir_recursive_absolute(_root) == OK, "create separate current artifact root"): return false
	else:
		if not _check(DirAccess.dir_exists_absolute(_root) and h._sha(_opts["previous-sha"]), "existing phase and externally accepted predecessor SHA256"): return false
	var directory: DirAccess = DirAccess.open(_root)
	if not _check(directory != null, "phase opens"): return false
	for name: String in directory.get_files():
		if not _check(not name.begins_with("failure_"), "failed phase stays sealed"): return false
	var claim: String = _root.path_join(_part + ".claim")
	if not _check(not DirAccess.dir_exists_absolute(claim) and DirAccess.make_dir_absolute(claim) == OK, "append-only per-part claim"): return false
	Game.SAVE_PATH = claim.path_join("quit-scratch.json")
	return true

func _identity() -> bool:
	if not _check(h._static_contract(), "exact actual 0.099 application, separate save2/world1, calendar and quality"): return false
	h._opts["phase"] = _opts["phase"]
	_params = h._base_params()
	_params["protocol"] = SCHEMA
	_params["acceptance_start_day"] = 46
	_params["saved_day"] = 53
	_params["live_end_day"] = 54
	var fingerprint: Dictionary = h._fingerprint()
	if not _check(h._error.is_empty() and fingerprint.has("identity") and _time(), "complete current resource source fingerprint"): return false
	_source = fingerprint["identity"]
	if _part == "seed": return h._write_new(_root.path_join("source.json"), fingerprint)
	return _check(M.equal_json(h._read(_root.path_join("source.json")), fingerprint), "all code/scenes/data/config source hashes unchanged")


func _chain(last_day: int, expected: String) -> bool:
	var previous_sha: String = Protocol.ZERO_SHA
	for day: int in range(1, last_day + 1):
		if not _time(): return false
		var path: String = _path(day, "manifest.json")
		var manifest: Dictionary = h._read(path)
		if not _check(h._error.is_empty() and manifest.get("schema") == SCHEMA and manifest.get("part") == ("seed" if day == 1 else "day%d" % day) and M.equal_json(manifest.get("day"), day) and manifest.get("complete") == true, "consecutive authenticated native day manifest %d" % day): return false
		if not _check(M.equal_json(manifest.get("source"), _source) and M.equal_json(manifest.get("params"), _params) and manifest.get("previous_manifest_sha256") == previous_sha, "exact source/parameters and predecessor chain %d" % day): return false
		if not _check(manifest.get("save") is Dictionary and manifest.get("evidence_sha256") is String, "complete native checkpoint bindings"): return false
		var save: Dictionary = manifest["save"]
		if not _check(save.get("path") == ProjectSettings.globalize_path(_path(day, "save.json")) and h._sha(save.get("sha256")) and h._sha(save.get("native_tree_hash")), "separate current native save binding"): return false
		# Recheck every committed file, including the original day46 input. Never trust a scratch save.
		if not _check(FileAccess.get_sha256(str(save["path"])) == save["sha256"] and FileAccess.get_sha256(_path(day, "evidence.json")) == manifest["evidence_sha256"], "all committed native inputs immutable %d" % day): return false
		previous_sha = FileAccess.get_sha256(path)
		_previous = manifest
	if not _check(previous_sha == expected, "controller supplied exact successful predecessor manifest SHA256"): return false
	_previous_sha = previous_sha
	_data = h._read(_path(last_day, "evidence.json"))
	return _check(h._error.is_empty() and _data.get("endpoint") is Dictionary and _data.get("books") is String, "complete measurement and native typed observation logs")


func _load_save(save: Dictionary, expected_day: float, endpoint: Dictionary, books: String) -> bool:
	var path: String = str(save.get("path", ""))
	var expected: String = str(save.get("sha256", ""))
	if not _check(h._sha(expected) and FileAccess.get_sha256(path) == expected, "immutable native input SHA256"): return false
	var scratch: String = Game.SAVE_PATH
	Game.SAVE_PATH = path
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = scratch
	if not _check(loaded and FileAccess.get_sha256(path) == expected and _clean(expected_day) and _time(), "native load, unchanged input and complete-day boundary"): return false
	if not _check(_native_hash(Game._save_tree()) == save.get("native_tree_hash"), "exact fresh-process native save tree, types/order/float bits/Item/RNG state"): return false
	if not _restore_books(_unwire(books)): return false
	return _check(M.equal_json(endpoint, _snapshot()), "fresh-process observation, physical holdings, Item IDs and RNG parity")


func _write_save(path: String, day: float) -> Dictionary:
	if not _check(_clean(day) and not FileAccess.file_exists(path) and _time(), "never overwrite a native checkpoint"): return {}
	Game.wait_save()
	if not _time(): return {}
	var payload: Dictionary = Game._save_tree()
	if not _check(int(payload.get("version", -1)) == 2 and int(payload.get("world", {}).get("version", -1)) == 1, "save-root schema2 and separate world schema1"): return {}
	var native_hash: String = _native_hash(payload)
	for key: Variant in payload: M.freeze_containers(payload[key])
	var receipt: Dictionary = Game._write_save(path, payload)
	if not _check(receipt.get("ok", false) and int(receipt.get("error", -1)) == OK and receipt.get("stage", "") == "complete" and int(receipt.get("serialized_bytes", 0)) > 0 and _time(), "existing native writer completed within selected-part deadline"): return {}
	var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not _check(decoded is Dictionary, "native writer readback is a dictionary"): return {}
	Game.restore_exact(decoded)
	if not _check(_native_hash(decoded) == native_hash and _time(), "native writer readback preserves complete types/order/float bits"): return {}
	return {"path": ProjectSettings.globalize_path(path), "sha256": FileAccess.get_sha256(path),
		"native_tree_hash": native_hash, "receipt": receipt}


func _commit(day: int) -> bool:
	var endpoint: Dictionary = _snapshot()
	if endpoint.is_empty() or not _time(): return false
	_data["endpoint"] = endpoint
	_data["books"] = _wire(_books())
	var save: Dictionary = _write_save(_path(day, "save.json"), float(day))
	if save.is_empty() or not _time(): return false
	if not h._write_new(_path(day, "evidence.json"), _data) or not _time(): return false
	var manifest: Dictionary = {"schema": SCHEMA, "part": _part, "source": _source, "params": _params,
		"day": day, "complete": true, "producer_pid": OS.get_process_id(), "previous_manifest_sha256": _previous_sha,
		"save": save, "evidence_sha256": FileAccess.get_sha256(_path(day, "evidence.json"))}
	if not h._write_new(_path(day, "manifest.json"), manifest): return false
	return _time()


func _count_dispatches() -> int:
	var total: int = 0
	for kind: String in CampaignWorld.job_total:
		total += int(CampaignWorld.job_total[kind][1])
	return total


func _one_day(tree: SceneTree, trace: TreasuryTrace, treasury_gate: bool) -> bool:
	var expected_day: float = Game.day + 1.0
	if not _clean(Game.day) or not _time(): return false
	var before: Dictionary = _snapshot()
	var anchor: Dictionary = WorldAudit.census(Game)
	if before.is_empty(): return false
	var dispatch_start: int = _count_dispatches()
	var sample_start: int = trace.samples
	trace.recording = treasury_gate
	if treasury_gate and not _check(float(Game.world["towns"]["t23"]["econ"]["treasury"]) >= 0.0, "Ithilspire opening treasury stays nonnegative"): return false
	Game.advance_time(1.0, false, 0, 1000)
	if not _time(): return false
	if treasury_gate and not _check(not trace.invalid and not trace.negative and float(Game.world["towns"]["t23"]["econ"]["treasury"]) >= 0.0, "Ithilspire stays nonnegative through advance_time native dispatches"): return false
	while not Game.world.get("work", []).is_empty() or Game._day_job_fence_pending():
		if not _time(): return false
		await tree.process_frame
		if not _time(): return false
		if Game._day_job_fence_pending(): Game._day_job_flush_actions()
		CampaignWorld.work_slice(Game, 1)
		if not _time(): return false
		if treasury_gate and not _check(not trace.invalid and not trace.negative and float(Game.world["towns"]["t23"]["econ"]["treasury"]) >= 0.0, "Ithilspire treasury stays nonnegative after every native work dispatch"): return false
	trace.recording = false
	if not _clean(expected_day) or not _time(): return false
	if treasury_gate and not _check(trace.pending.is_empty() and trace.samples - sample_start == _count_dispatches() - dispatch_start, "independent accounting covers every actual native dispatch"): return false
	var after: Dictionary = _snapshot()
	if after.is_empty(): return false
	for race: String in h.RACES + ["WORLD"]:
		if not _check(M.census_residual(before["observation"]["groups"][race], after["observation"]["groups"][race]) == 0, "native daily census " + race): return false
	var audit: Dictionary = WorldAudit.compare(anchor, WorldAudit.census(Game))
	if not _check(h._audit_error(audit) == "", "every native daily conservation gate"): return false
	var audits: Array = _data.get("daily_audits", [])
	audits.append({"day": Game.day, "audit": M.plain(audit)})
	_data["daily_audits"] = audits
	if treasury_gate:
		var rows: Array = _data.get("treasury_trace", [])
		rows.append_array(trace.rows)
		trace.rows = []
		_data["treasury_trace"] = rows
		_data["observed_native_dispatches"] = int(_data.get("observed_native_dispatches", 0)) + trace.samples - sample_start
		_data["mint_job_seen"] = bool(_data.get("mint_job_seen", false)) or trace.mint_seen
		var observations: Array = _data.get("acceptance_observations", [])
		observations.append(after)
		_data["acceptance_observations"] = observations
	return _time()

func _seed(tree: SceneTree) -> bool:
	if not _check(not FileAccess.file_exists(DevTools.world_path(true)), "fresh isolated profile has no inherited version-keyed fixture cache"): return false
	WorldGen.gen_stretch = WorldGen.STRETCH
	if not await DevTools.start_world(tree, Game.SAVE_PATH, true): return _check(false, "existing native DevTools one-history-day start")
	if not _check(_time() and h._world_contract(true), "genuine current-source Normal 150x96 seed4242 creatures/day1 world"): return false
	var town: String = DevTools.choose_house(Game)
	if not _check(town != "", "existing native observer household selected"): return false
	DevTools.stand_at(Game, town)  # Original protocol's initial onboarding only.
	while not Game.world.get("work", []).is_empty() or Game._day_job_fence_pending():
		if not _time(): return false
		await tree.process_frame
		if Game._day_job_fence_pending(): Game._day_job_flush_actions()
		CampaignWorld.work_slice(Game, 1)
		if not _time(): return false
	if not _clean(1.0): return false
	_data = {"observer": {"household_uid": str(Game.world.get("player_house", {}).get("household_uid", "")), "origin_town": town},
		"daily_audits": [], "acceptance_observations": [], "treasury_trace": [], "observed_native_dispatches": 0, "mint_job_seen": false}
	if not _check(_data["observer"]["household_uid"] != "", "native observer identity retained"): return false
	return _commit(1)


func _advance(tree: SceneTree, trace: TreasuryTrace, day: int) -> bool:
	if not _chain(day - 1, str(_opts["previous-sha"])): return false
	if not _check(int(_previous.get("producer_pid", -1)) != OS.get_process_id(), "day handoff starts in a fresh process"): return false
	if not _load_save(_previous["save"], float(day - 1), _data["endpoint"], str(_data["books"])): return false
	if not await _one_day(tree, trace, day >= 47): return false
	if day == 46:
		var origin: Dictionary = _snapshot()
		_data["origin46"] = origin
		_data["window_anchor"] = _wire(WorldAudit.census(Game))
		_data["acceptance_observations"] = [origin]
	if day >= 47:
		var anchor: Dictionary = _unwire(str(_data.get("window_anchor", "")))
		if anchor.is_empty(): return false
		var audit: Dictionary = WorldAudit.compare(anchor, WorldAudit.census(Game))
		if not _check(h._audit_error(audit) == "", "unchanged whole-window native day46 conservation gates"): return false
		_data["window_audit"] = M.plain(audit)
	if day == 53 and not _check(bool(_data.get("mint_job_seen", false)), "original Ithilspire business job completes at native day53 overdraft point"): return false
	return _commit(day)


func _live(tree: SceneTree, trace: TreasuryTrace) -> bool:
	if not _chain(53, str(_opts["previous-sha"])): return false
	# Keep the accepted day53 checkpoint as an independent witness, never as live input.
	# Recreate native day53 from day52 so the first day53 load occurs only in reload.
	# This part advances TWO actual days (53 and 54) under the unchanged 50 s budget.
	var accepted_day53: Dictionary = _previous
	var accepted_evidence53: Dictionary = _data
	var predecessor_path: String = _path(52, "manifest.json")
	if not _check(int(accepted_day53.get("producer_pid", -1)) != OS.get_process_id() and FileAccess.get_sha256(predecessor_path) == accepted_day53.get("previous_manifest_sha256"), "fresh live process and exact authenticated day52 predecessor"): return false
	var predecessor: Dictionary = h._read(predecessor_path)
	if not _check(h._error.is_empty() and predecessor.get("schema") == SCHEMA and predecessor.get("part") == "day52" and predecessor.get("complete") == true and M.equal_json(predecessor.get("day"), 52) and M.equal_json(predecessor.get("source"), _source) and M.equal_json(predecessor.get("params"), _params), "unchanged complete native day52 manifest"): return false
	if not _check(FileAccess.get_sha256(_path(52, "evidence.json")) == predecessor.get("evidence_sha256"), "immutable day52 observations and audit books"): return false
	_data = h._read(_path(52, "evidence.json"))
	if not _check(h._error.is_empty() and _data.get("endpoint") is Dictionary and _data.get("books") is String, "complete native day52 evidence"): return false
	if not _load_save(predecessor["save"], 52.0, _data["endpoint"], str(_data["books"])): return false
	if not await _one_day(tree, trace, true): return false
	var native53: Dictionary = _snapshot()
	var native53_anchor: Dictionary = _unwire(str(_data.get("window_anchor", "")))
	if native53.is_empty() or native53_anchor.is_empty() or not _time(): return false
	var native53_audit: Dictionary = WorldAudit.compare(native53_anchor, WorldAudit.census(Game))
	if not _check(h._audit_error(native53_audit) == "", "uninterrupted native day53 whole-window conservation gates"): return false
	_data["window_audit"] = M.plain(native53_audit)
	if not _check(_native_hash(Game._save_tree()) == accepted_day53["save"].get("native_tree_hash") and M.equal_json(native53, accepted_evidence53.get("endpoint")), "uninterrupted native day53 exactly matches accepted native tree and endpoint"): return false
	if not _check(_wire(_books()) == str(accepted_evidence53.get("books", "")) and M.equal_json(_data["window_audit"], accepted_evidence53.get("window_audit")) and M.equal_json(_data["acceptance_observations"], accepted_evidence53.get("acceptance_observations")), "all day46..53 observations and whole-window audit books independently agree"): return false
	_data["endpoint"] = native53
	_data["books"] = _wire(_books())
	if not _check(bool(_data.get("mint_job_seen", false)) and _data.get("origin46") is Dictionary and _data.get("acceptance_observations", []).size() == 8, "all native day46..53 observations and actual mint job retained"): return false
	var saved_endpoint: Dictionary = _snapshot()
	var saved_books: String = _wire(_books())
	var saved_window_audit: Dictionary = _data["window_audit"]
	# This exact native writer is followed by live day54, without any intervening load.
	var save: Dictionary = _write_save(_root.path_join("live_day53.save.json"), 53.0)
	if save.is_empty(): return false
	if not _check(M.equal_json(saved_endpoint, _snapshot()), "native day53 writer leaves live observations and holdings unchanged"): return false
	if not await _one_day(tree, trace, true): return false
	var anchor: Dictionary = _unwire(str(_data["window_anchor"]))
	var audit: Dictionary = WorldAudit.compare(anchor, WorldAudit.census(Game))
	if not _check(h._audit_error(audit) == "", "live day54 full day46 conservation gates"): return false
	var live_endpoint: Dictionary = _snapshot()
	if not _check(not live_endpoint.is_empty() and _data["acceptance_observations"].size() == 9, "all original native day46..54 observations retained"): return false
	_data["day53"] = saved_endpoint
	_data["day53_books"] = saved_books
	_data["day53_audit"] = saved_window_audit
	_data["live_next"] = live_endpoint
	_data["live_continuation_audit"] = M.plain(audit)
	if not h._write_new(_root.path_join("live.evidence.json"), _data) or not _time(): return false
	_live_manifest = {"schema": SCHEMA, "part": "live", "complete": true, "source": _source, "params": _params,
		"producer_pid": OS.get_process_id(), "start_day": 46, "saved_day": 53, "live_next_day": 54,
		"previous_manifest_sha256": _previous_sha, "save": save, "evidence_sha256": FileAccess.get_sha256(_root.path_join("live.evidence.json"))}
	if not _check(FileAccess.get_sha256(str(save["path"])) == save["sha256"], "native live day53 input remains immutable"): return false
	if not h._write_new(_root.path_join("live.manifest.json"), _live_manifest): return false
	return _time()


func _reload(tree: SceneTree, trace: TreasuryTrace) -> bool:
	var path: String = _root.path_join("live.manifest.json")
	var expected: String = str(_opts["previous-sha"])
	if not _check(FileAccess.get_sha256(path) == expected, "exact successful live manifest input"): return false
	_live_manifest = h._read(path)
	if not _check(_live_manifest.get("schema") == SCHEMA and _live_manifest.get("part") == "live" and _live_manifest.get("complete") == true and M.equal_json(_live_manifest.get("source"), _source) and M.equal_json(_live_manifest.get("params"), _params), "separate current live schema/source/parameters"): return false
	if not _check(int(_live_manifest.get("producer_pid", -1)) != OS.get_process_id() and M.equal_json(_live_manifest.get("start_day"), 46) and M.equal_json(_live_manifest.get("saved_day"), 53) and M.equal_json(_live_manifest.get("live_next_day"), 54), "fresh-process native day53/day54 contract"): return false
	if not _chain(53, str(_live_manifest.get("previous_manifest_sha256", ""))): return false
	if not _check(FileAccess.get_sha256(_root.path_join("live.evidence.json")) == _live_manifest.get("evidence_sha256"), "immutable live endpoint and cumulative measurements"): return false
	var live: Dictionary = h._read(_root.path_join("live.evidence.json"))
	if not _check(h._error.is_empty() and bool(live.get("mint_job_seen", false)) and live.get("acceptance_observations", []).size() == 9 and M.equal_json(live.get("day53"), _data.get("endpoint")), "day53 original endpoint and all nine acceptance observations"): return false
	var observations: Array = live["acceptance_observations"]
	for index: int in observations.size():
		if not _check(M.equal_json(observations[index].get("observation", {}).get("day"), 46 + index), "no skipped or duplicated native acceptance day"): return false
	if not _check(h._audit_error(live.get("day53_audit")) == "" and h._audit_error(live.get("live_continuation_audit")) == "", "original mint and live whole-window conservation gates"): return false
	var save: Dictionary = _live_manifest.get("save", {})
	if not _check(save.get("path") == ProjectSettings.globalize_path(_root.path_join("live_day53.save.json")), "reload uses the exact native day53 writer output"): return false
	if not _load_save(save, 53.0, live["day53"], str(live["day53_books"])): return false
	_data = {"daily_audits": [], "treasury_trace": [], "acceptance_observations": [live["day53"]], "mint_job_seen": true}
	if not await _one_day(tree, trace, true): return false
	var resumed: Dictionary = _snapshot()
	if not _check(M.equal_json(live["live_next"], resumed), "native resumed day54 equals live day54 including all observations/holdings/Item IDs/RNG"): return false
	var anchor: Dictionary = _unwire(str(live["window_anchor"]))
	if not _check(h._audit_error(WorldAudit.compare(anchor, WorldAudit.census(Game))) == "", "reloaded day54 full day46 native conservation"): return false
	# Original reload has its own one-day audit, independently of the carried full-window gate.
	if not _check(_data["daily_audits"].size() == 1 and h._audit_error(_data["daily_audits"][0]["audit"]) == "", "reloaded day53-to54 native conservation"): return false
	if not _check(FileAccess.get_sha256(path) == expected and FileAccess.get_sha256(str(save["path"])) == save["sha256"], "live manifest and native day53 unchanged"): return false
	# Revalidate the entire authentic fixture/day chain again before accepting.
	if not _chain(53, str(_live_manifest["previous_manifest_sha256"])) or not _time(): return false
	return h._write_new(_root.path_join("acceptance.json"), {"schema": SCHEMA, "application_version": Protocol.APPLICATION_VERSION,
		"source": _source, "params": _params, "shortAcceptancePass": true, "longCampaignComplete": false,
		"fresh_process_reload": true, "saved_day": 53, "end_day": 54, "live_manifest_sha256": expected,
		"saved_endpoint_sha256": M.digest(live["day53"]), "resumed_endpoint_sha256": M.digest(resumed),
		"live_endpoint_sha256": M.digest(live["live_next"]), "elapsed_ms": Time.get_ticks_msec() - _started}) and _time()

func _finish(success: bool) -> int:
	if success: success = _time() and _failed.is_empty() and h._error.is_empty()
	var result: Dictionary = {"schema": SCHEMA, "part": _part, "ok": success,
		"componentPass": success, "shortAcceptancePass": success and _part == "reload",
		"longCampaignComplete": false, "checks": _checks, "failed_checks": _failed,
		"protocol_error": h._error, "application_version": Protocol.APPLICATION_VERSION,
		"save_schema": 2, "world_schema": 1, "source": _source,
		"native_day": Game.day, "elapsed_ms": Time.get_ticks_msec() - _started}
	if success:
		var manifest: String = _root.path_join("live.manifest.json" if _part == "live" else "acceptance.json") if _part in ["live", "reload"] else _path(1 if _part == "seed" else _part.substr(3).to_int(), "manifest.json")
		result["manifest"] = ProjectSettings.globalize_path(manifest)
		result["manifest_sha256"] = FileAccess.get_sha256(manifest)
	var encoded: String = M.text(result)
	if Time.get_ticks_msec() - _started >= LIMIT_MS:
		success = false
		result["ok"] = false
		result["componentPass"] = false
		result["shortAcceptancePass"] = false
		result["deadline_failed"] = true
		encoded = M.text(result)
	if not success and _root != "" and DirAccess.dir_exists_absolute(_root):
		# Failure evidence seals the phase; an interrupted claim is never an accepted predecessor.
		var failure: String = _root.path_join("failure_%s_%d.json" % [_part, OS.get_process_id()])
		h._write_new(failure, result)
	print("SHORT_ECONOMY_CURRENT " + encoded)
	return 0 if success and Time.get_ticks_msec() - _started < LIMIT_MS else 1


func run(tree: SceneTree) -> int:
	_started = Time.get_ticks_msec()
	h._started = _started
	if not _check(Game.world.is_empty() and Game.company.is_empty(), "isolated fresh process before campaign load") or not _parse(): return _finish(false)
	if not _reserve(): return _finish(false)
	# Authorized isolated-process setting only; no settings-file writes.
	Game.settings["autosave"] = "off"
	Game.wait_save()
	if not _time() or not _identity(): return _finish(false)
	var old_game_processing: bool = Game.is_processing()
	var old_perf_processing: bool = Perf.is_processing()
	var old_perf_script: Script = Perf.get_script() as Script
	var old_perf_state: Dictionary = {}
	for property: Dictionary in Perf.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var key: String = String(property["name"])
			old_perf_state[key] = Perf.get(key)
	Game.set_process(false)
	Perf.set_script(TreasuryTrace)
	Perf.set_process(old_perf_processing)
	var trace: TreasuryTrace = Perf as TreasuryTrace
	var success: bool = false
	if _part == "seed": success = await _seed(tree)
	elif _part == "live": success = await _live(tree, trace)
	elif _part == "reload": success = await _reload(tree, trace)
	else: success = await _advance(tree, trace, _part.substr(3).to_int())
	trace.recording = false
	Perf.set_script(old_perf_script)
	for key: String in old_perf_state: Perf.set(key, old_perf_state[key])
	Perf.set_process(old_perf_processing)
	Game.set_process(old_game_processing)
	if success:
		var fingerprint: Dictionary = h._fingerprint()
		success = _check(h._error.is_empty() and M.equal_json(fingerprint.get("identity"), _source), "source remains unchanged through the entire selected part") and _time()
	return _finish(success)
