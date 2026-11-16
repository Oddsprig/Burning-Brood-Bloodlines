extends RefCounted
const RunplanArgs: GDScript = preload("res://tests/fixtures/older_runplan_args_v100.gd")
## Optional bounded receipts. A full test requires EVERY listed part; default keeps all original cases.
static func select(cases: Array) -> String:
	var selected: String = "all"
	var seen: bool = false
	for argument: String in RunplanArgs.arguments():
		if argument == "--speed-part":
			printerr("Use --speed-part=<case>; required cases: ", cases)
			return ""
		if not argument.begins_with("--speed-part="): continue
		if seen:
			printerr("Select exactly one --speed-part per invocation")
			return ""
		seen = true
		selected = argument.trim_prefix("--speed-part=")
		if selected != "all" and not selected in cases:
			printerr("Unknown --speed-part=", selected, "; required cases: ", cases)
			return ""
	print("SPEED_PART selected=", selected, " required=", cases, "; partial receipts require the complete case set")
	return selected

static func includes(selected: String, case_name: String) -> bool:
	return selected == "all" or selected == case_name

static func source_stamp() -> String:
	var files: Array[String] = ["res://project.godot"]
	var pending: Array[String] = ["res://"]
	while not pending.is_empty():
		var directory: String = pending.pop_back()
		for child: String in DirAccess.get_directories_at(directory):
			if not child.begins_with("."): pending.append(directory.path_join(child))
		for filename: String in DirAccess.get_files_at(directory):
			var path: String = directory.path_join(filename)
			if filename.ends_with(".gd") or (directory.begins_with("res://data") and filename.ends_with(".json")):
				files.append(path)
	files.sort()
	var stamps: PackedStringArray = PackedStringArray()
	for path: String in files: stamps.append(path + ":" + FileAccess.get_sha256(path))
	return "\n".join(stamps).sha256_text()

static func capture_setup(path: String, source: String, references: Dictionary, cases: Array) -> Dictionary:
	if source.length() != 64 or not _references_current(references) or cases.is_empty(): return {}
	var manifest: Dictionary = {
		"path": path, "capture_id": "%s-%d-%d" % [str(Time.get_unix_time_from_system()), OS.get_process_id(), Time.get_ticks_usec()],
		"source": source, "references": references, "cases": cases,
	}
	if not _write_capture_data(path, manifest): return {}
	return manifest

static func capture_load(path: String, source: String, references: Dictionary, cases: Array) -> Dictionary:
	var manifest: Dictionary = _read_capture_data(path)
	if manifest.get("path") != path or str(manifest.get("capture_id", "")).is_empty(): return {}
	if manifest.get("source") != source or manifest.get("references") != references or manifest.get("cases") != cases: return {}
	if not _capture_current(manifest): return {}
	return manifest

static func begin_image_case(path: String, manifest: Dictionary, case_id: String) -> bool:
	if manifest.is_empty() or not case_id in manifest.get("cases", []): return false
	# Overwrite an earlier marker before this case starts; never delete artifacts.
	return _write_capture_data(path + ".speed_receipt", {"capture_id": manifest["capture_id"], "case_id": case_id, "source": manifest["source"], "references": manifest["references"], "complete": false})

static func complete_image_case(path: String, manifest: Dictionary, case_id: String, outputs: Array) -> bool:
	if not _capture_current(manifest) or not case_id in manifest.get("cases", []): return false
	var hashes: Dictionary = _image_hashes(outputs)
	if hashes.is_empty(): return false
	return _write_capture_data(path + ".speed_receipt", {
		"capture_id": manifest["capture_id"], "case_id": case_id, "source": manifest["source"],
		"references": manifest["references"], "outputs": hashes, "complete": true,
	})

static func image_case_valid(path: String, manifest: Dictionary, case_id: String, outputs: Array) -> bool:
	var receipt: Dictionary = _read_capture_data(path + ".speed_receipt")
	if manifest.is_empty() or receipt.get("complete") != true or not case_id in manifest.get("cases", []): return false
	if receipt.get("capture_id") != manifest["capture_id"] or receipt.get("case_id") != case_id: return false
	if receipt.get("source") != manifest["source"] or receipt.get("references") != manifest["references"]: return false
	var hashes: Dictionary = _image_hashes(outputs)
	return not hashes.is_empty() and receipt.get("outputs") == hashes

static func _capture_current(manifest: Dictionary) -> bool:
	if manifest.is_empty() or not manifest.get("references") is Dictionary: return false
	return _read_capture_data(str(manifest.get("path", ""))) == manifest and source_stamp() == manifest.get("source") and _references_current(manifest["references"])

static func _references_current(references: Dictionary) -> bool:
	if references.is_empty(): return false
	for path: String in references:
		if not FileAccess.file_exists(path) or str(references[path]).length() != 64 or FileAccess.get_sha256(path) != references[path]: return false
	return true

static func _image_hashes(outputs: Array) -> Dictionary:
	var hashes: Dictionary = {}
	for path: String in outputs:
		if not FileAccess.file_exists(path): return {}
		var hash_value: String = FileAccess.get_sha256(path)
		if hash_value.length() != 64: return {}
		hashes[path] = hash_value
	return hashes

static func _write_capture_data(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_var(data)
	file.flush()
	var complete: bool = file.get_error() == OK
	file.close()
	return complete

static func _read_capture_data(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var data: Variant = file.get_var(false)
	var complete: bool = file.get_error() == OK
	file.close()
	if not complete or not data is Dictionary: return {}
	return data
