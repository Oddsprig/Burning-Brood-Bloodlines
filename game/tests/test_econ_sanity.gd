extends RefCounted
## A balance check, separate from the runtime-only simulation diagnostic.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
const Fixture = preload("res://tests/make_fixture_econ_sanity_v100.gd")
func run(_tree: SceneTree) -> int:
	# v0.100 r4: consume the real, source-pinned native 600-day fixture; never generate history here.
	var input := OS.get_environment("AUDIT_INPUT")
	if input == "":
		input = Fixture.fixture_dir().path_join("audit.json")
	if input == "" or not FileAccess.file_exists(input):
		printerr("FAIL: set AUDIT_INPUT to the fixed-seed five-year audit.json")
		return 1
	var save := input.get_base_dir().path_join("checkpoint-save.json")
	var receipt: Dictionary = Fixture.verify(save)
	if receipt.is_empty() or FileAccess.get_sha256(input) != receipt.get("audit_sha256", "") or not Fixture.load_verified(save):
		printerr("FAIL: genuine matching native day-600 save/audit/receipt required")
		return 1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not parsed is Dictionary or not parsed.get("towns") is Array or parsed["towns"].is_empty():
		printerr("FAIL: complete nonempty native audit required")
		return 1
	var report: Dictionary = parsed
	# Recompute after the real load. Preserve exact audit values; no numeric tolerance is introduced.
	var loaded_report: Dictionary = EconomyAudit.world_report(Game)
	if JSON.stringify(loaded_report, "", true, true) != JSON.stringify(report, "", true, true):
		printerr("FAIL: loaded native save does not reproduce the complete original audit")
		return 1
	var failures := 0
	for town in report["towns"]:
		for issue in town["issues"]:
			failures += 1
			printerr("FAIL: town ", town["town"], ": ", JSON.stringify(issue))
	print("Economy sanity: %d towns; %d remaining rule violations" % [report["towns"].size(), failures])
	return 1 if failures > 0 else 0
