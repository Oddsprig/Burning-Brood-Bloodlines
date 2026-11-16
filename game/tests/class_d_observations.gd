extends RefCounted
## Persist observed failures, never reference/golden replacements.
static func write(test_id: String, payload: Dictionary) -> bool:
	var path: String = "user://class_d_%s_%d_%d.json" % [test_id, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: cannot preserve class-D observations: ", path, " error ", FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(Game._serialize(payload), "\t", false, true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error != OK:
		printerr("FAIL: class-D observation write failed: ", path, " error ", error)
		return false
	print("CLASS_D_OBSERVATION ", ProjectSettings.globalize_path(path))
	return true
