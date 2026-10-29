extends SceneTree
## Capture before the split, then compare raw RGBA portraits and launcher sheets.
## Run: --headless --path game --script res://tests/verify_elf_portrait_split.gd -- capture|compare

const RACES := ["human", "dwarf", "high_elf", "moon_elf", "dark_elf", "orc", "goblin", "troll"]
const UNCHANGED := [
	"art/portraits/portrait_human.gd", "art/portraits/portrait_dwarf.gd",
	"art/portraits/portrait_orc.gd", "art/portraits/portrait_goblin.gd",
	"art/portraits/portrait_troll.gd", "art/elf_art.gd",
]
const EVIDENCE := "../test-results/v0069_elf_split"

var failures := 0
var lines: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["capture", "compare"]:
		printerr("Usage: -- capture|compare")
		quit(2)
		return
	var capture := args[0] == "capture"
	var root := ProjectSettings.globalize_path("res://")
	var evidence := root.path_join(EVIDENCE).simplify_path()
	var baseline := evidence.path_join("baseline")
	var output := baseline if capture else evidence.path_join("after")
	var manifest_path := baseline.path_join("source_sha256.json")
	if capture and FileAccess.file_exists(manifest_path):
		printerr("Refusing to overwrite captured baseline: ", baseline)
		quit(2)
		return
	if not capture and not FileAccess.file_exists(manifest_path):
		printerr("Capture the baseline before editing the painters.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		printerr("Cannot create evidence directory: ", output)
		quit(1)
		return
	var painter = load("res://art/portrait_bust.gd")
	var fixture = load("res://tests/test_portraits_v067.gd").new()
	fixture.helper = load("res://tests/test_races_v065.gd").new()
	var source_hashes := {}
	if not capture:
		source_hashes = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	for source in UNCHANGED:
		var digest := FileAccess.get_sha256(root.path_join(source))
		if capture:
			source_hashes[source] = digest
		elif digest != source_hashes.get(source, ""):
			_fail("SOURCE CHANGED " + source)
	if capture:
		source_hashes["art/portrait_bust.gd"] = FileAccess.get_sha256(root.path_join("art/portrait_bust.gd"))
		_copy(root.path_join("art/portrait_bust.gd"), baseline.path_join("portrait_bust.gd"))
	for race in RACES:
		var passed := 0
		for variant in 5:
			var spec: Dictionary = fixture._spec(race, variant)
			var image: Image = painter.paint(spec)
			if image == null or image.get_size() != Vector2i(96, 96):
				_fail("Invalid portrait %s variant=%d" % [race, variant])
				continue
			image.convert(Image.FORMAT_RGBA8)
			var name := "%s_%d.png" % [race, variant]
			if image.save_png(output.path_join(name)) != OK:
				_fail("Cannot save " + name)
			if not capture:
				var before := Image.load_from_file(baseline.path_join(name))
				if before == null:
					_fail("Missing baseline " + name)
					continue
				before.convert(Image.FORMAT_RGBA8)
				if image.get_size() != before.get_size() or image.get_data() != before.get_data():
					_fail("PIXEL MISMATCH " + name)
					continue
			passed += 1
		var sheet := "v0068_portrait_%s.png" % race
		_copy(root.path_join("../test-results").path_join(sheet), output.path_join(sheet))
		var sheet_identical := capture or FileAccess.get_file_as_bytes(baseline.path_join(sheet)) == FileAccess.get_file_as_bytes(output.path_join(sheet))
		if not sheet_identical:
			_fail("SHEET BYTES DIFFER " + race)
		_record("%s %s %d/5; sheet=%s" % ["CAPTURED" if capture else "PIXEL_IDENTICAL", race, passed, "captured" if capture else ("byte-identical" if sheet_identical else "different")])
	if capture:
		_write(manifest_path, JSON.stringify(source_hashes, "\t") + "\n")
	else:
		_record("Unchanged source hashes: five other race painters and elf_art.gd checked.")
	_record("ELF_SPLIT %s races=8 variants=40 failures=%d" % [args[0], failures])
	_write(evidence.path_join("%s.txt" % args[0]), "\n".join(lines) + "\n")
	quit(0 if failures == 0 else 1)

func _copy(source: String, destination: String) -> void:
	if DirAccess.copy_absolute(source, destination) != OK:
		_fail("Cannot copy " + source)

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write " + path)
		return
	file.store_string(content)

func _record(line: String) -> void:
	lines.append(line)
	print(line)

func _fail(message: String) -> void:
	failures += 1
	lines.append("FAIL " + message)
	printerr(message)
