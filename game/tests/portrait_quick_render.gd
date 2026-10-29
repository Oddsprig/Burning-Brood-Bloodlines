extends SceneTree
## Headless before/after portrait sheets. Optional race name after -- .

var _ran := false

func _init() -> void:
	print("QUICK_RENDER init")

func _process(_dt: float) -> bool:
	if _ran:
		return true
	_ran = true
	_draw_and_quit()
	return true

func _draw_and_quit() -> void:
	var race_arg := _race_arg()
	var painter = load("res://art/figure_painter.gd")
	painter.set_legacy_v064(false)
	painter.snapshot_v066_bust = false
	var sheet = load("res://tests/test_portraits_v067.gd").new()
	sheet.helper = load("res://tests/test_races_v065.gd").new()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../test-results")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var races: Array[String] = ["moon_elf", "dark_elf"]
	if race_arg != "":
		races = [race_arg]
	for race in races:
		var befores: Array[Image] = []
		var after_row: Array[Image] = []
		var ages: Array = []
		for i in 5:
			var sp: Dictionary = sheet._spec(race, i)
			var before: Image = painter.render_bust_v066(sp)
			var after: Image = painter.render_bust(sp)
			if before == null:
				before = Image.create(96, 96, false, Image.FORMAT_RGBA8)
			if after == null:
				after = Image.create(96, 96, false, Image.FORMAT_RGBA8)
			befores.append(before)
			after_row.append(after)
			ages.append(int(sp["age"]))
		var img: Image = sheet._race_sheet(race, befores, after_row, ages)
		var path := out_dir.path_join("v0067_portrait_%s.png" % race)
		var err: int = img.save_png(path)
		print("SAVED ", path, " ", err)
	quit(0)

func _race_arg() -> String:
	for a in OS.get_cmdline_user_args():
		var token := String(a)
		if token != "" and not token.begins_with("-"):
			return token
	for a2 in OS.get_cmdline_args():
		var token2 := String(a2)
		if token2 == "moon_elf" or token2 == "dark_elf":
			return token2
	return ""
