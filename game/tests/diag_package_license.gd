extends RefCounted
## Write the bundled runtime's own licensing notices to PACKAGE_OUTPUT (packaging only).
func run(_tree: SceneTree) -> int:
	var output := OS.get_environment("PACKAGE_OUTPUT")
	if output.is_empty():
		printerr("PACKAGE_OUTPUT is required")
		return 1
	var file := FileAccess.open(output.path_join("runtime/GODOT_LICENSE.txt"), FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(Engine.get_license_text())
	file.close()
	file = FileAccess.open(output.path_join("runtime/THIRD_PARTY_NOTICES.json"), FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"copyright": Engine.get_copyright_info(), "licenses": Engine.get_license_info()}, "\t"))
	file.close()
	return 0
