extends RefCounted
## A balance check, separate from the runtime-only simulation diagnostic.
func run(_tree: SceneTree) -> int:
	var input := OS.get_environment("AUDIT_INPUT")
	if input == "" or not FileAccess.file_exists(input):
		printerr("FAIL: set AUDIT_INPUT to the fixed-seed five-year audit.json")
		return 1
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input))
	var failures := 0
	for town in report["towns"]:
		for issue in town["issues"]:
			failures += 1
			printerr("FAIL: town ", town["town"], ": ", JSON.stringify(issue))
	print("Economy sanity: %d towns; %d remaining rule violations" % [report["towns"].size(), failures])
	return 1 if failures > 0 else 0
