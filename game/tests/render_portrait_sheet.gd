extends SceneTree
## CPU-only draw-and-quit sheets. Run with --headless --script, then -- <race|all>.
## The PowerShell launcher supplies a unique --log-file for every invocation.
## Each race job writes only its own PNG; only "all" also writes the overview.

const RACES: Array[String] = ["human", "dwarf", "high_elf", "moon_elf", "dark_elf", "orc", "goblin", "troll"]
const SCALE := 4
const PORTRAIT_SIZE := 96
const MARGIN := 16
const GAP := 12
const HEADER := 28
const LABEL_HEIGHT := 24
const ROW_HEIGHT := HEADER + PORTRAIT_SIZE * SCALE + LABEL_HEIGHT

var _fails := 0
var _verified := 0

func _init() -> void:
	create_timer(45.0).timeout.connect(func():
		printerr("PORTRAIT_V068 timed out")
		quit(124))
	call_deferred("_draw_and_quit")

func _draw_and_quit() -> void:
	var requested := "all"
	var race_given := false
	var verify_all := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--verify-v067":
			verify_all = true
		elif not race_given and (arg == "all" or arg in RACES):
			requested = arg
			race_given = true
		else:
			printerr("Usage: -- <race|all> [--verify-v067]; races: ", RACES)
			quit(2)
			return
	var races: Array[String] = RACES.duplicate()
	if requested != "all":
		races = [requested]
	var painter = load("res://art/portrait_bust.gd")
	if painter == null or not painter.can_instantiate():
		printerr("Cannot load portrait painter; run from the full game project with its class registry.")
		quit(1)
		return
	var fixture_script = load("res://tests/test_portraits_v067.gd")
	var helper_script = load("res://tests/test_races_v065.gd")
	if fixture_script == null or not fixture_script.can_instantiate() or helper_script == null or not helper_script.can_instantiate():
		printerr("Cannot load v0.067 fixtures; the full game project and DB autoload are required.")
		quit(1)
		return
	var fixture = fixture_script.new()
	fixture.helper = helper_script.new()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../test-results")
	var dir_error := DirAccess.make_dir_recursive_absolute(out_dir)
	if dir_error != OK:
		printerr("Cannot create output directory: ", out_dir, " error=", dir_error)
		quit(1)
		return
	var rows := {}
	for race in races:
		var row: Array[Image] = []
		for i in 5:
			var spec: Dictionary = fixture._spec(race, i)
			var portrait: Image = painter.paint(spec)
			if portrait == null or portrait.get_size() != Vector2i(PORTRAIT_SIZE, PORTRAIT_SIZE):
				printerr("Invalid 96x96 portrait: ", race, " variant=", i)
				quit(1)
				return
			row.append(portrait)
		rows[race] = row
		var sheet := _sheet([race], rows, fixture)
		_save(sheet, out_dir.path_join("v0068_portrait_%s.png" % race))
		# Elf checks always run. --verify-v067 also checks the five redo races
		# during prep; omit that flag once their artwork intentionally changes.
		if race.ends_with("_elf") or verify_all:
			_verify_v067(race, row, fixture.helper, out_dir)
	if requested == "all":
		_save(_sheet(races, rows, fixture), out_dir.path_join("v0068_portrait_all_races.png"))
	print("PORTRAIT_V068 races=%d variants=%d v067_identical=%d failures=%d" % [races.size(), races.size() * 5, _verified, _fails])
	quit(0 if _fails == 0 else 1)

func _sheet(races: Array, rows: Dictionary, fixture) -> Image:
	var bw := PORTRAIT_SIZE * SCALE
	var width := MARGIN * 2 + 5 * bw + 4 * GAP
	var height := MARGIN * 2 + races.size() * ROW_HEIGHT + (races.size() - 1) * GAP
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color("#12161e"))
	for r in races.size():
		var race: String = races[r]
		var y0 := MARGIN + r * (ROW_HEIGHT + GAP)
		fixture.helper._draw_text(image, MARGIN, y0, "V0.068  " + race.replace("_", " "), Color("#f2da94"), 2)
		var row: Array = rows[race]
		for i in 5:
			var x := MARGIN + i * (bw + GAP)
			var y := y0 + HEADER
			image.fill_rect(Rect2i(x - 2, y - 2, bw + 4, bw + 4), Color("#d9a441"))
			image.fill_rect(Rect2i(x, y, bw, bw), Color("#1a120e"))
			var big: Image = fixture.helper._scale_nearest(row[i], SCALE)
			fixture.helper._blit_alpha(image, big, Vector2i(x, y))
			var spec: Dictionary = fixture._spec(race, i)
			fixture.helper._draw_text(image, x + 4, y + bw + 6, "%s %d" % [fixture.LABELS[i], int(spec["age"])], Color("#d5e2f2"), 2)
	return image

func _verify_v067(race: String, row: Array[Image], helper, out_dir: String) -> void:
	var path := out_dir.path_join("v0067_portrait_%s.png" % race)
	var baseline := Image.load_from_file(path)
	# v0.067 _race_sheet: margin=14, scale=3, gap=10, row_h=336,
	# second (AFTER) row starts at y=390. Compare portrait tiles, not labels.
	if baseline == null or baseline.get_size() != Vector2i(1508, 712):
		printerr("Missing or unexpected v0.067 baseline: ", path)
		_fails += 1
		return
	baseline.convert(Image.FORMAT_RGBA8)
	var passed := 0
	for i in 5:
		var expected := baseline.get_region(Rect2i(14 + i * 298, 390, 288, 288))
		var actual := Image.create(288, 288, false, Image.FORMAT_RGBA8)
		actual.fill(Color("#1a120e"))
		var big: Image = helper._scale_nearest(row[i], 3)
		helper._blit_alpha(actual, big, Vector2i.ZERO)
		if expected.get_data() != actual.get_data():
			printerr("V0067 PIXEL MISMATCH ", race, " variant=", i)
			_fails += 1
		else:
			passed += 1
			_verified += 1
	print("V0067_PIXEL_IDENTICAL ", race, " ", passed, "/5")

func _save(image: Image, path: String) -> void:
	var error := image.save_png(path)
	if error != OK:
		printerr("Cannot save ", path, " error=", error)
		_fails += 1
	else:
		print("SAVED ", path)
