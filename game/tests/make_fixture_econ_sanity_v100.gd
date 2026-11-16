extends RefCounted
## Native seed-2026 Large audit in 60 FRESH processes, ten real days per process.
## Required: --fixture-chunk=0..59 in order; no unbounded/default maker entry.
## Each successor requires its predecessor's successful external whole-process receipt.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
const Audit = preload("res://tests/diag_economy_audit.gd")
const Source = preload("res://tests/fixtures/older_speed_parts_v100.gd")
const NativeChecks = preload("res://tests/test_econ_town.gd")
const SCHEMA := "held-native600-v100-r4/1"
const CHUNK_SCHEMA := "held-native600-v100-r4/chunk/1"
const PROCESS_SCHEMA := "held-native600-v100-r4/process/1"
const CHUNK_DAYS := 10
const CHUNK_COUNT := 60
const ENGINE_LIMIT := 165.0
const PROCESS_LIMIT := 175.0

static func fixture_dir() -> String:
	var path := OS.get_environment("HELD_V100_FIXTURE_DIR")
	if path.is_empty(): path = ProjectSettings.globalize_path("res://../test-results/v0.100/held_native600_r4")
	return path.replace("\\", "/").simplify_path()

static func sealer_path() -> String:
	return ProjectSettings.globalize_path("res://../test-results/v0.100/complete_held_native600_r4.ps1")

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

static func _sha(path: String, expected: Variant) -> bool:
	return expected is String and expected.length() == 64 and FileAccess.file_exists(path) and FileAccess.get_sha256(path) == expected

static func _chunk_dir(directory: String, index: int) -> String:
	return directory.path_join("chunk%03d" % index)

static func _rows(directory: String, count: int, source: String) -> Array:
	var rows: Array = []
	var previous_receipt := ""
	var previous_save := ""
	var sealer_sha := FileAccess.get_sha256(sealer_path())
	if source.length() != 64 or sealer_sha.length() != 64: return []
	for index in count:
		var folder := _chunk_dir(directory, index)
		var path := folder.path_join("chunk.json")
		var row := read_json(path)
		var process := read_json(folder.path_join("process.json"))
		if row.get("schema") != CHUNK_SCHEMA or row.get("complete") != true or row.get("producer_exit") != 0: return []
		if row.get("index") != index or row.get("start_day") != index * CHUNK_DAYS or row.get("end_day") != (index + 1) * CHUNK_DAYS: return []
		if row.get("directory") != directory or row.get("source_stamp") != source or row.get("source_sha256") != source or row.get("sealer_sha256") != sealer_sha: return []
		if row.get("engine") != Engine.get_version_info() or row.get("game_version") != ProjectSettings.get_setting("application/config/version", ""): return []
		if row.get("previous_receipt_sha256") != previous_receipt or row.get("previous_save_sha256") != previous_save: return []
		for pair in [["checkpoint-save.json", "save_sha256"], ["harvest-audit.json", "harvest_sha256"], ["expected.bin", "expected_sha256"]]:
			if not _sha(folder.path_join(pair[0]), row.get(pair[1])): return []
		if index == CHUNK_COUNT - 1 and not _sha(folder.path_join("audit.json"), row.get("audit_sha256")): return []
		if process.get("schema") != PROCESS_SCHEMA or process.get("complete") != true or process.get("index") != index: return []
		if process.get("exit_code") != 0 or process.get("script_errors") != 0 or process.get("pid") != row.get("pid"): return []
		if process.get("source_sha256") != source or process.get("native_receipt_sha256") != FileAccess.get_sha256(path): return []
		var wall: Variant = process.get("wall_seconds")
		if not (wall is float or wall is int) or not is_finite(float(wall)) or float(wall) <= 0.0 or float(wall) >= PROCESS_LIMIT: return []
		if process.get("log_path") != folder.path_join("process.log") or not _sha(folder.path_join("process.log"), process.get("log_sha256")): return []
		previous_receipt = FileAccess.get_sha256(path)
		previous_save = row["save_sha256"]
		row["wall_seconds"] = wall
		row["chunk_receipt_sha256"] = previous_receipt
		row["process_receipt_sha256"] = FileAccess.get_sha256(folder.path_join("process.json"))
		rows.append(row)
	return rows

static func verify(save: String, candidate: Dictionary = {}) -> Dictionary:
	var directory := save.get_base_dir().replace("\\", "/").simplify_path()
	var receipt := candidate if not candidate.is_empty() else read_json(directory.path_join("receipt.json"))
	if receipt.get("schema") != SCHEMA or receipt.get("complete") != true or receipt.get("producer_exit") != 0: return {}
	if receipt.get("seed") != 2026 or receipt.get("initial_day") != 0 or receipt.get("final_day") != 600 or receipt.get("days_simulated") != 600: return {}
	if receipt.get("world_size") != "large" or receipt.get("history_days") != 600 or receipt.get("fixed_raid_steps") != true: return {}
	if receipt.get("chunk_days") != CHUNK_DAYS or receipt.get("chunk_count") != CHUNK_COUNT: return {}
	if receipt.get("source_stamp") != Source.source_stamp() or receipt.get("game_version") != ProjectSettings.get_setting("application/config/version", ""): return {}
	if receipt.get("engine") != Engine.get_version_info(): return {}
	if save.replace("\\", "/").simplify_path() != directory.path_join("checkpoint-save.json"): return {}
	var rows := _rows(directory, CHUNK_COUNT, receipt["source_stamp"])
	if rows.size() != CHUNK_COUNT or JSON.stringify(receipt.get("chunks"), "", true, true) != JSON.stringify(rows, "", true, true): return {}
	var wall := 0.0
	for row in rows: wall += float(row["wall_seconds"])
	# Each row carries the parent's launch-to-exit stopwatch, not a relabeled inner timer.
	if receipt.get("wall_seconds") != wall or receipt.get("wall_scope") != "sum of externally measured child launch-to-exit seconds; queue excluded": return {}
	for pair in [["checkpoint-save.json", "file_sha256"], ["audit.json", "audit_sha256"], ["harvest-audit.json", "harvest_sha256"]]:
		if not _sha(directory.path_join(pair[0]), receipt.get(pair[1])): return {}
	if receipt["file_sha256"] != rows[-1]["save_sha256"] or receipt["harvest_sha256"] != rows[-1]["harvest_sha256"] or receipt["audit_sha256"] != rows[-1]["audit_sha256"]: return {}
	var report := read_json(directory.path_join("audit.json"))
	var harvest := read_json(directory.path_join("harvest-audit.json"))
	if report.get("seed") != 2026 or report.get("day") != 600 or not report.get("towns") is Array or report["towns"].is_empty(): return {}
	if harvest.get("seed") != 2026 or harvest.get("requested_days") != 600 or harvest.get("final_day") != 600 or harvest.get("advancing") != true: return {}
	if harvest.get("available") != true or harvest.get("passed") != true or harvest.get("skipped_town_observations") != 0 or harvest.get("violation_count") != 0: return {}
	var observed: Variant = harvest.get("sample_days")
	if not observed is Array or observed.size() != 61: return {}
	for i in 61:
		if observed[i] != i * 10: return {}
	return receipt

static func _native_load(save: String, expected_path: String, day: int) -> bool:
	var expected := FileAccess.get_file_as_bytes(expected_path)
	if expected.is_empty(): return false
	var keep: String = Game.SAVE_PATH
	Game.wait_save()
	Game.SAVE_PATH = save
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = keep
	return loaded and Game.day == float(day) and Game.seed_value == 2026 and Game.world.get("seed") == 2026 and Game.world.get("work", []).is_empty() and var_to_bytes([Game._save_tree(), NativeChecks.new()._year_live_shape()]) == expected

static func load_verified(save: String, candidate: Dictionary = {}) -> bool:
	var receipt := verify(save, candidate)
	if receipt.is_empty(): return false
	return _native_load(save, _chunk_dir(save.get_base_dir(), CHUNK_COUNT - 1).path_join("expected.bin"), 600) and FileAccess.get_sha256(save) == receipt["file_sha256"]

static func _write(path: String, bytes: PackedByteArray) -> bool:
	if FileAccess.file_exists(path): return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes); file.flush()
	var error := file.get_error(); file.close()
	return error == OK and FileAccess.get_file_as_bytes(path) == bytes

func run(_tree: SceneTree) -> int:
	var started := Time.get_ticks_usec()
	var index := -1
	var seen := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--fixture-chunk="):
			var value := argument.trim_prefix("--fixture-chunk=")
			if seen or not value.is_valid_int(): return 1
			seen = true; index = int(value)
	if not seen or index < 0 or index >= CHUNK_COUNT:
		printerr("FAIL: select exactly one --fixture-chunk=0..59; no single-shot maker")
		return 1
	var directory := fixture_dir()
	var allowed := ProjectSettings.globalize_path("res://../test-results/v0.100").replace("\\", "/").simplify_path()
	if not directory.is_absolute_path() or not directory.begins_with(allowed + "/"): return 1
	if index == 0 and DirAccess.dir_exists_absolute(directory):
		printerr("FAIL: chunk 0 requires a NEW fixture directory")
		return 1
	var folder := _chunk_dir(directory, index)
	if DirAccess.dir_exists_absolute(folder) or FileAccess.file_exists(directory.path_join("receipt.json")): return 1
	var source := Source.source_stamp()
	var sealer_sha := FileAccess.get_sha256(sealer_path())
	if source.length() != 64 or sealer_sha.length() != 64: return 1
	var previous_rows := _rows(directory, index, source)
	if previous_rows.size() != index: return 1
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return 1
	var audit := Audit.new()
	audit.harvest_report["available"] = ResourceLoader.exists("res://campaign/harvest_claims.gd")
	audit.harvest_report["seed"] = 2026
	audit.harvest_report["requested_days"] = 600
	audit.harvest_report["tolerance_absolute"] = Audit.ABS_TOL
	audit.harvest_report["tolerance_relative"] = Audit.REL_TOL
	WorldGen.gen_size = "large"
	CampaignWorld.presim_years = 5
	var first_day := index * CHUNK_DAYS
	var last_day := first_day + CHUNK_DAYS
	if index == 0:
		Game.new_game(2026)
		if Game.day != 0.0: return 1
		audit.harvest_sample(0)
	else:
		var previous := _chunk_dir(directory, index - 1)
		if not _native_load(previous.path_join("checkpoint-save.json"), previous.path_join("expected.bin"), first_day): return 1
		if not audit.restore_harvest_report(previous.path_join("harvest-audit.json"), first_day): return 1
		WorldGen.gen_size = "large"
		CampaignWorld.presim_years = 5
	# Identical operations and samples to diag_economy_audit.run(), with no day/cursor edits.
	HerdRaids.benchmark_fixed_steps = true
	for d in range(first_day, last_day):
		if float(Time.get_ticks_usec()) / 1000000.0 >= ENGINE_LIMIT: return 1
		CampaignWorld.presim_step(Game, 1)
		if Game.day != float(d + 1) or not Game.world.get("work", []).is_empty(): return 1
		if (d + 1) % 10 == 0: audit.harvest_sample(d + 1)
		if (d + 1) % 120 == 0: print("AUDIT simulated day ", d + 1)
	audit.harvest_report["final_day"] = int(Game.day)
	audit.harvest_report["advancing"] = true
	audit.harvest_report["passed"] = int(audit.harvest_report["violation_count"]) == 0
	if not audit.harvest_report["available"] or not audit.harvest_report["passed"] or audit.harvest_report["skipped_town_observations"] != 0: return 1
	var complete := index == CHUNK_COUNT - 1
	var htext: String = JSON.stringify(audit.harvest_report, "\t", true, true) if complete else Game.save_text(audit.harvest_report)
	if htext.is_empty() or not _write(folder.path_join("harvest-audit.json"), htext.to_utf8_buffer()): return 1
	if complete:
		var report: Dictionary = EconomyAudit.world_report(Game)
		if report.get("towns", []).is_empty(): return 1
		if not _write(folder.path_join("audit.json"), JSON.stringify(report, "\t", true, true).to_utf8_buffer()): return 1
	# Independent native pre-write snapshot. Native writer + native loader must preserve every byte/type/order/RNG.
	if not _write(folder.path_join("expected.bin"), var_to_bytes([Game._save_tree(), NativeChecks.new()._year_live_shape()])): return 1
	var save := folder.path_join("checkpoint-save.json")
	var keep: String = Game.SAVE_PATH
	Game.wait_save(); Game.SAVE_PATH = save
	var written: bool = Game.save_game()
	Game.wait_save(); Game.SAVE_PATH = keep
	if not written or not bool(Game.save_stats()["last_ok"]) or not _native_load(save, folder.path_join("expected.bin"), last_day): return 1
	if complete:
		for name in ["checkpoint-save.json", "harvest-audit.json", "audit.json"]:
			if not _write(directory.path_join(name), FileAccess.get_file_as_bytes(folder.path_join(name))): return 1
	if Source.source_stamp() != source or FileAccess.get_sha256(sealer_path()) != sealer_sha: return 1
	if float(Time.get_ticks_usec()) / 1000000.0 >= ENGINE_LIMIT: return 1
	var row := {"schema": CHUNK_SCHEMA, "complete": true, "producer_exit": 0, "index": index,
		"directory": directory, "start_day": first_day, "end_day": int(Game.day), "pid": OS.get_process_id(),
		"seed": 2026, "world_size": "large", "history_days": 600, "fixed_raid_steps": true,
		"source_stamp": source, "source_sha256": source, "sealer_sha256": sealer_sha,
		"engine": Engine.get_version_info(), "game_version": ProjectSettings.get_setting("application/config/version", ""),
		"save_sha256": FileAccess.get_sha256(save), "harvest_sha256": FileAccess.get_sha256(folder.path_join("harvest-audit.json")),
		"expected_sha256": FileAccess.get_sha256(folder.path_join("expected.bin")),
		"previous_receipt_sha256": "" if index == 0 else FileAccess.get_sha256(_chunk_dir(directory, index - 1).path_join("chunk.json")),
		"previous_save_sha256": "" if index == 0 else previous_rows[-1]["save_sha256"],
		"maker_wall_seconds": float(Time.get_ticks_usec() - started) / 1000000.0,
		"engine_elapsed_seconds": float(Time.get_ticks_usec()) / 1000000.0,
		"timing_scope": "maker/engine partial timing only; process.json must attest launch-to-exit wall"}
	if complete: row["audit_sha256"] = FileAccess.get_sha256(folder.path_join("audit.json"))
	if not _write(folder.path_join("chunk.json"), JSON.stringify(row, "\t", true, true).to_utf8_buffer()): return 1
	print("HELD_NATIVE600_R4 chunk=%d save_sha256=%s source=%s pid=%d" % [index, row["save_sha256"], source, OS.get_process_id()])
	print("PARTIAL: parent must accept exit/errors/whole-wall and seal process.json; all 60 chunks required")
	return 0
