extends RefCounted
const RunplanArgs: GDScript = preload("res://tests/fixtures/older_runplan_args_v100.gd")
## Explicit selectors and lossless native checkpoints. Receipts are partial until every part passes.
const Oracle = preload("res://tests/test_econ_town.gd")
var context: Dictionary = {}
var fails: int = 0
var scenario: String = ""
var source: String = ""
var root: String = ""
var oracle: RefCounted = Oracle.new()

static func option(name: String, fallback: String = "") -> String:
	var result: String = fallback
	var seen: bool = false
	for argument: String in RunplanArgs.arguments():
		if argument == name: return ""
		if argument.begins_with(name + "="):
			if seen: return ""
			seen = true
			result = argument.trim_prefix(name + "=")
	return result

static func select(cases: Array) -> String:
	var selected: String = option("--speed-part", "all")
	if selected != "all" and not cases.has(selected):
		printerr("Unknown or duplicate --speed-part: ", selected)
		return ""
	print("OLDER201_PART selected=", selected, " required_count=", cases.size(), "; partial evidence requires every part")
	return selected

static func source_stamp() -> String:
	var paths: Array[String] = ["res://project.godot"]
	var pending: Array[String] = ["res://"]
	while not pending.is_empty():
		var directory: String = pending.pop_back()
		for child: String in DirAccess.get_directories_at(directory):
			if not child.begins_with("."): pending.append(directory.path_join(child))
		for filename: String in DirAccess.get_files_at(directory):
			if filename.get_extension() in ["gd", "tscn", "tres", "json", "cfg", "gdshader"]:
				paths.append(directory.path_join(filename))
	paths.sort()
	var rows: PackedStringArray = PackedStringArray()
	for path: String in paths: rows.append(path + ":" + FileAccess.get_sha256(path))
	return "\n".join(rows).sha256_text()

func _init(name: String) -> void:
	scenario = name
	source = source_stamp()
	root = option("--speed-root")
	if root.is_empty():
		fail("selected chains require an explicit fresh --speed-root=<directory>")
	else:
		root = root.path_join(name)
		if DirAccess.make_dir_recursive_absolute(root) != OK: fail("cannot create evidence directory")

func fail(label: String) -> bool:
	fails += 1
	printerr("OLDER201 ", scenario, ": ", label)
	return false

func path(step: String) -> String:
	return root.path_join(step.replace(":", "_") + ".bin")

func read_record(step: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path(step), FileAccess.READ)
	if file == null: fail("missing record: " + step); return {}
	var value: Variant = file.get_var(false)
	var complete: bool = file.get_error() == OK
	file.close()
	if not complete: fail("invalid record: " + step); return {}
	return _record_value(step, value)

func _record_value(step: String, value: Variant) -> Dictionary:
	if not value is Dictionary: fail("invalid record: " + step); return {}
	if value.get("source") != source or value.get("scenario") != scenario or value.get("step") != step:
		fail("stale source/scenario/step: " + step); return {}
	return value

func write_record(step: String, data: Dictionary, verified_records: Array[Dictionary] = []) -> bool:
	if fails > 0: return false
	if FileAccess.file_exists(path(step)): return fail("fresh append-only evidence required: " + step)
	data["source"] = source; data["scenario"] = scenario; data["step"] = step
	var file: FileAccess = FileAccess.open(path(step), FileAccess.WRITE)
	if file == null: return fail("cannot write " + step)
	# Keep FileAccess.store_var framing, but retain its one intended encoding.
	var encoded: PackedByteArray = var_to_bytes(data)
	file.store_32(encoded.size()); file.store_buffer(encoded); file.flush()
	var complete: bool = file.get_error() == OK
	file.close()
	if not complete: return fail("incomplete record: " + step)
	file = FileAccess.open(path(step), FileAccess.READ)
	if file == null: return fail("cannot read back " + step)
	if file.get_length() != encoded.size() + 4 or file.get_32() != encoded.size():
		file.close()
		return fail("record framing changed: " + step)
	var disk: PackedByteArray = file.get_buffer(encoded.size())
	complete = file.get_error() == OK
	file.close()
	if not complete or disk != encoded: return fail("record bytes changed: " + step)
	# Decode the independent disk bytes, then retain the original round-trip check.
	var decoded: Dictionary = _record_value(step, bytes_to_var(disk))
	disk = PackedByteArray()
	if decoded.is_empty() or var_to_bytes(decoded) != encoded:
		return fail("record native round-trip changed: " + step)
	verified_records.append(decoded)
	return true

func _stats() -> Dictionary:
	return {"job_total": CampaignWorld.job_total, "job_worst": CampaignWorld.job_worst,
		"steps_total": CampaignWorld.steps_total, "step_parts": CampaignWorld.step_parts,
		"daily_total": CampaignWorld.daily_total, "steps_worst": CampaignWorld.steps_worst,
		"daily_worst": CampaignWorld.daily_worst, "daily_parts": CampaignWorld.daily_parts,
		"path_worst": CampaignWorld.path_worst}

func _restore_stats(data: Dictionary) -> void:
	CampaignWorld.job_total = data["job_total"]; CampaignWorld.job_worst = data["job_worst"]
	CampaignWorld.steps_total = int(data["steps_total"]); CampaignWorld.step_parts = data["step_parts"]
	CampaignWorld.daily_total = data["daily_total"]; CampaignWorld.steps_worst = int(data["steps_worst"])
	CampaignWorld.daily_worst = int(data["daily_worst"]); CampaignWorld.daily_parts = data["daily_parts"]
	CampaignWorld.path_worst = int(data["path_worst"])

func save_step(step: int) -> bool:
	if fails > 0: return false
	if not Game.world.get("work", []).is_empty(): return fail("checkpoint requires a drained native day")
	if step == 0:
		context["chain"] = "%s-%d-%d" % [str(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()]
	var record: Dictionary = {"context": context.duplicate(true), "stats": _stats().duplicate(true),
		"shape": oracle._year_live_shape(), "expected": Game._save_tree()}
	var save_path: String = path(str(step)) + ".save.json"
	if FileAccess.file_exists(save_path): return fail("checkpoint save already exists")
	var written: Dictionary = Game._write_save(save_path, record["expected"])
	if not bool(written.get("ok", false)): return fail("native writer refused checkpoint")
	record["save_hash"] = FileAccess.get_sha256(save_path)
	record["previous"] = "" if step == 0 else FileAccess.get_sha256(path(str(step - 1)))
	var verified_records: Array[Dictionary] = []
	if not write_record(str(step), record, verified_records): return false
	# Reuse only the independent disk decode that passed both exact comparisons.
	if not _load_step(step, verified_records[0]): return false
	var proof: Dictionary = {"chain": context["chain"], "previous": "" if step == 0 else FileAccess.get_sha256(path("proof%d" % (step - 1))),
		"record": FileAccess.get_sha256(path(str(step))), "save": record["save_hash"]}
	if not write_record("proof%d" % step, proof): return false
	return true

func load_step(step: int) -> bool:
	var proof: Dictionary = read_record("proof%d" % step)
	if proof.is_empty(): return false
	if proof.get("record") != FileAccess.get_sha256(path(str(step))) or proof.get("save") != FileAccess.get_sha256(path(str(step)) + ".save.json"):
		return fail("predecessor did not retain its exact passing native evidence")
	return _load_step(step)

func _load_step(step: int, verified_record: Dictionary = {}) -> bool:
	var record: Dictionary = read_record(str(step)) if verified_record.is_empty() else verified_record
	var first: Dictionary = record if step == 0 else read_record("0")
	if record.is_empty() or first.is_empty(): return false
	if not record.get("context") is Dictionary or record["context"].get("chain") != first["context"].get("chain"):
		return fail("checkpoint chain identity mismatch")
	if step > 0 and record.get("previous") != FileAccess.get_sha256(path(str(step - 1))):
		return fail("checkpoint predecessor mismatch")
	var save_path: String = path(str(step)) + ".save.json"
	if not FileAccess.file_exists(save_path) or record.get("save_hash") != FileAccess.get_sha256(save_path):
		return fail("checkpoint save hash mismatch")
	var keep: String = Game.SAVE_PATH
	Game.SAVE_PATH = save_path
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = keep
	if not loaded: return fail("native reader refused checkpoint")
	if not oracle._year_same_snapshot(record["expected"], scenario + str(step)): return fail("native snapshot changed")
	if var_to_bytes(record["shape"]) != var_to_bytes(oracle._year_live_shape()): return fail("native types changed")
	if not oracle._year_cursors(Game.world) or not Game.world["work"].is_empty(): return fail("native cursors/work invalid")
	context = record["context"]
	_restore_stats(record["stats"])
	return fails == 0

func verify_chain(last_step: int) -> bool:
	var previous: String = ""
	var chain: String = ""
	for step: int in last_step + 1:
		var proof: Dictionary = read_record("proof%d" % step)
		if proof.is_empty(): return false
		if step == 0: chain = str(proof.get("chain", ""))
		if chain.is_empty() or proof.get("chain") != chain or proof.get("previous") != previous:
			return fail("incomplete or mixed proof chain")
		if proof.get("record") != FileAccess.get_sha256(path(str(step))) or proof.get("save") != FileAccess.get_sha256(path(str(step)) + ".save.json"):
			return fail("retained native evidence changed")
		previous = FileAccess.get_sha256(path("proof%d" % step))
	return true
