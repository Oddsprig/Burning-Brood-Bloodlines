extends RefCounted
## Lossless, source-pinned native handoffs for long existing tests. No day or assertion is omitted.
const SpeedParts = preload("res://tests/fixtures/older_speed_parts_v100.gd")
const NativeChecks = preload("res://tests/test_econ_town.gd")
var fails: int = 0
var context: Dictionary = {}
var _case: String
var _source: String
var _oracle: RefCounted = NativeChecks.new()

func _init(case_name: String) -> void:
	_case = case_name
	_source = SpeedParts.source_stamp()

func _check(ok: bool, label: String) -> bool:
	if not ok:
		fails += 1
		printerr("SPEED HANDOFF ", _case, ": ", label)
	return ok

func _path(step: int) -> String:
	return "user://older_speed_v100_%s_%s_%d.json" % [ProjectSettings.globalize_path("res://").sha256_text().substr(0, 12), _case, step]

func load_step(step: int) -> bool:
	var path: String = _path(step)
	if not _check(FileAccess.file_exists(path) and FileAccess.file_exists(path + ".expected"), "missing predecessor; run setup and every numbered part in order"): return false
	var file: FileAccess = FileAccess.open(path + ".expected", FileAccess.READ)
	if not _check(file != null, "expected snapshot opens"): return false
	var header: Variant = file.get_var(false)
	var expected: Variant = file.get_var(false)
	var shape: Variant = file.get_var(false)
	var complete: bool = file.get_error() == OK
	file.close()
	if not _check(complete and header is Dictionary and expected is Dictionary and shape is Array, "complete independent native snapshot and type shape"): return false
	if not _check(header.get("case") == _case and header.get("source") == _source and header.get("step") == step and header.get("context") is Dictionary, "exact source, scenario and predecessor step"): return false
	if not _check(header["context"].has("chain_id"), "original chain ID exists"): return false
	if step > 0:
		var first: FileAccess = FileAccess.open(_path(0) + ".expected", FileAccess.READ)
		if not _check(first != null, "setup header opens"): return false
		var beginning: Variant = first.get_var(false)
		first.close()
		if not _check(beginning is Dictionary and beginning.get("source") == _source and beginning.get("context") is Dictionary and beginning["context"].get("chain_id") == header["context"]["chain_id"], "no mixed or stale checkpoint chain"): return false
	var keep: String = Game.SAVE_PATH
	Game.SAVE_PATH = path
	var loaded: bool = Game.load_game()
	Game.SAVE_PATH = keep
	if not _check(loaded, "native save loads"): return false
	if not _check(_oracle._year_same_snapshot(expected, _case + str(step)), "all snapshot values, order, RNG and numeric bits survive"): return false
	if not _check(var_to_bytes(shape) == var_to_bytes(_oracle._year_live_shape()), "native runtime types survive"): return false
	if not _check(_oracle._year_cursors(Game.world) and Game.world["work"].is_empty(), "real cursors and no pending work"): return false
	context = header["context"]
	return fails == 0

func save_step(step: int) -> bool:
	if not _check(Game.world.get("work", []).is_empty(), "only completed native work may be checkpointed"): return false
	if step == 0:
		context["chain_id"] = "%s-%d" % [str(Time.get_unix_time_from_system()), OS.get_process_id()]
	var shape: Array = _oracle._year_live_shape()
	var expected: Dictionary = Game._save_tree()
	var keep: String = Game.SAVE_PATH
	Game.SAVE_PATH = _path(step)
	var written: bool = Game.save_game()
	Game.wait_save()
	Game.SAVE_PATH = keep
	if not _check(written and bool(Game.save_stats()["last_ok"]), "native save completes"): return false
	var file: FileAccess = FileAccess.open(_path(step) + ".expected", FileAccess.WRITE)
	if not _check(file != null, "independent snapshot opens for writing"): return false
	file.store_var({"case": _case, "source": _source, "step": step, "context": context})
	file.store_var(expected)
	file.store_var(shape)
	file.flush()
	var complete: bool = file.get_error() == OK
	file.close()
	if not _check(complete, "independent snapshot writes completely"): return false
	# Each part proves its own round trip, including the final numbered part.
	return load_step(step)
