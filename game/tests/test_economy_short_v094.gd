extends RefCounted
## Owner-authorized short acceptance; the 240-day campaign remains stopped.
## (1) one Godot test at a time on this PC, headless only, never open a game window; (2) before any test, check for running Godot or Unity processes from any project, and if any are running, queue and wait; (3) every test run must finish in under 3 minutes, so split anything longer into short runs.
const M = preload("res://tests/economy_stability_v094.gd")
const Protocol = preload("res://tests/test_economy_stability_v094.gd")
const SCHEMA = "economy_short_v094/1"
const START_SHA = "8d81898815b9bf15546c6349be5822cba8b17c00f65efa0996282de1b8ac9ad9"
var h = Protocol.new()
var opts: Dictionary = {}
var checks: int = 0
var failed: Array = []
var started: int = 0

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failed.append(label)
		print("FAIL short094: ", label)
	return ok

func snapshot() -> Dictionary:
	var observation: Dictionary = h._observe(M.maker_types())
	return {"observation": observation, "physical": M.plain(M.physical_signature(WorldAudit.census(Game)))}

func load_exact(path: String, expected: String, day: float) -> bool:
	if not check(FileAccess.get_sha256(path) == expected, "immutable input SHA256"): return false
	Game.SAVE_PATH = path
	var ok: bool = Game.load_game()
	Game.SAVE_PATH = "user://economy_short_v094/quit-scratch.json"
	return check(ok and FileAccess.get_sha256(path) == expected and h._clean(day) and h._world_contract(false), "native load, unchanged input and complete-day boundary")

func step(tree: SceneTree, previous: Dictionary, trace: Array) -> Dictionary:
	var expected: float = Game.day + 1.0
	Game.advance_time(1.0, false, 0, 1000)
	while not Game.world.get("work", []).is_empty():
		if not check(Time.get_ticks_msec() - started < 100000, "short-run internal deadline"): return {}
		var job = M.plain(Game.world["work"][0])
		var before: float = float(Game.world["towns"]["t23"]["econ"]["treasury"])
		CampaignWorld.work_slice(Game, 1)
		var after: float = float(Game.world["towns"]["t23"]["econ"]["treasury"])
		if before != after or (job is Array and job.size() > 1 and job[0] == "bday" and job[1] == "t23"): trace.append({"day": Game.day, "job": job, "before": before, "after": after})
		if not check(after >= 0.0, "Ithilspire treasury stays nonnegative after native work"): return {}
		await tree.process_frame
	if not check(h._clean(expected), "one complete native day"): return {}
	var next: Dictionary = snapshot()
	if not check(h._error.is_empty(), "physical holdings and measurement groups"): return {}
	for race in h.RACES + ["WORLD"]:
		if not check(M.census_residual(previous["observation"]["groups"][race], next["observation"]["groups"][race]) == 0, "native daily census " + race): return {}
	return next

func emit(mode: String, extra: Dictionary) -> int:
	var result: Dictionary = {"schema": SCHEMA, "mode": mode, "ok": failed.is_empty() and h._error.is_empty(),
		"shortAcceptancePass": failed.is_empty() and h._error.is_empty(), "longCampaignComplete": false,
		"checks": checks, "failed_checks": failed, "protocol_error": h._error,
		"elapsed_ms": Time.get_ticks_msec() - started}
	result.merge(extra)
	print("SHORT_ECONOMY_V094 " + M.text(result))
	return 0 if result["ok"] else 1

func mint(tree: SceneTree) -> int:
	var input: String = str(opts.get("input", ""))
	if not load_exact(input, START_SHA, 46.0): return emit("mint", {})
	var origin: Dictionary = snapshot()
	var current: Dictionary = origin
	var anchor: Dictionary = WorldAudit.census(Game)
	var trace: Array = []
	for i in 7:
		current = await step(tree, current, trace)
		if current.is_empty(): return emit("mint", {})
	var audit: Dictionary = WorldAudit.compare(anchor, WorldAudit.census(Game))
	if not check(h._audit_error(audit) == "" and Game.day == 53.0, "day53 native conservation gates"): return emit("mint", {})
	var mint_job_seen: bool = false
	for row in trace:
		if row["day"] == 53 and row["job"] is Array and row["job"].size() > 1 and row["job"][0] == "bday" and row["job"][1] == "t23": mint_job_seen = true
	if not check(mint_job_seen, "the original town business job executes at the day53 overdraft point"): return emit("mint", {})
	var path: String = "user://economy_short_v094/day53.save.json"
	if not check(not FileAccess.file_exists(path), "never overwrite a short checkpoint"): return emit("mint", {})
	Game.wait_save()
	var payload: Dictionary = Game._save_tree()
	for key in payload: M.freeze_containers(payload[key])
	var receipt: Dictionary = Game._write_save(path, payload)
	payload = {}
	if not check(receipt.get("ok", false) and int(receipt.get("error", -1)) == OK and receipt.get("stage", "") == "complete" and int(receipt.get("serialized_bytes", 0)) > 0, "existing native writer completed"): return emit("mint", {})
	var save_sha: String = FileAccess.get_sha256(path)
	var live_next: Dictionary = await step(tree, current, trace)
	if live_next.is_empty(): return emit("mint", {})
	var continuation_audit: Dictionary = WorldAudit.compare(anchor, WorldAudit.census(Game))
	check(h._audit_error(continuation_audit) == "", "live day54 conservation gates")
	check(FileAccess.get_sha256(input) == START_SHA and FileAccess.get_sha256(path) == save_sha, "both native inputs remain immutable")
	var manifest: Dictionary = {"schema": SCHEMA, "start_input": input, "start_sha256": START_SHA, "start_day": 46,
		"save": ProjectSettings.globalize_path(path), "save_sha256": save_sha, "saved_day": 53, "day53": current,
		"live_next_day": 54, "live_next": live_next, "native_writer_receipt": receipt,
		"mint_audit": audit, "live_continuation_audit": continuation_audit, "treasury_trace": trace}
	var manifest_path: String = "user://economy_short_v094/manifest.json"
	check(failed.is_empty() and h._write_new(manifest_path, manifest), "append-only short manifest")
	return emit("mint", {"start_day": 46, "saved_day": 53, "live_end_day": 54, "input_unchanged": FileAccess.get_sha256(input) == START_SHA,
		"day53_treasury": current["observation"]["towns"]["t23"]["metrics"]["cash"]["treasury"], "mint_job_seen": mint_job_seen, "manifest": ProjectSettings.globalize_path(manifest_path),
		"manifest_sha256": FileAccess.get_sha256(manifest_path), "save_sha256": save_sha})

func reload_check(tree: SceneTree) -> int:
	var path: String = str(opts.get("manifest", ""))
	var expected: String = str(opts.get("manifest-sha", ""))
	if not check(expected.length() == 64 and FileAccess.get_sha256(path) == expected, "exact short manifest input"): return emit("reload", {})
	var manifest: Dictionary = h._read(path)
	if not check(manifest.get("schema", "") == SCHEMA and manifest.get("start_sha256", "") == START_SHA and manifest.get("saved_day", 0) == 53 and manifest.get("live_next_day", 0) == 54, "day53/day54 native boundary contract"): return emit("reload", {})
	if not load_exact(str(manifest["save"]), str(manifest["save_sha256"]), 53.0): return emit("reload", {})
	var loaded: Dictionary = snapshot()
	if not check(M.equal_json(manifest["day53"], loaded), "fresh-process day53 observation, holdings, Item IDs and RNG parity"): return emit("reload", {})
	var anchor: Dictionary = WorldAudit.census(Game)
	var trace: Array = []
	var next: Dictionary = await step(tree, loaded, trace)
	if next.is_empty(): return emit("reload", {})
	check(M.equal_json(manifest["live_next"], next), "native resumed day54 equals live day54 including RNG and physical holdings")
	check(h._audit_error(WorldAudit.compare(anchor, WorldAudit.census(Game))) == "", "reloaded day54 native conservation")
	check(FileAccess.get_sha256(path) == expected and FileAccess.get_sha256(str(manifest["save"])) == manifest["save_sha256"] and FileAccess.get_sha256(str(manifest["start_input"])) == START_SHA, "all acceptance input files remain unchanged")
	return emit("reload", {"saved_day": 53, "end_day": Game.day, "manifest_sha256": expected, "fresh_process_reload": true,
		"saved_endpoint_sha256": M.digest(loaded), "resumed_endpoint_sha256": M.digest(next), "live_endpoint_sha256": M.digest(manifest["live_next"])})

func run(tree: SceneTree) -> int:
	started = Time.get_ticks_msec()
	h._started = started
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--short-"):
			var parts: PackedStringArray = arg.substr(8).split("=", true, 1)
			if parts.size() != 2 or opts.has(parts[0]) or not parts[0] in ["mode", "input", "manifest", "manifest-sha"]: return 1
			opts[parts[0]] = parts[1]
	Game.settings["autosave"] = "off"
	Game.wait_save()
	DirAccess.make_dir_recursive_absolute("user://economy_short_v094")
	Game.SAVE_PATH = "user://economy_short_v094/quit-scratch.json"
	if not check(h._static_contract(), "native094 version/calendar/quality contract"): return emit("invalid", {})
	if opts.get("mode", "") == "mint": return await mint(tree)
	if opts.get("mode", "") == "reload": return await reload_check(tree)
	return 1
