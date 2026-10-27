extends RefCounted
## v0.067 portrait before/after sheets. Before is the frozen v0.066 bust.

const RACES: Array[String] = ["human", "dwarf", "high_elf", "moon_elf", "dark_elf", "orc", "goblin", "troll"]
const STAGE_AGE := {
	"human": [20, 35, 68],
	"dwarf": [32, 70, 140],
	"high_elf": [55, 150, 340],
	"moon_elf": [55, 150, 340],
	"dark_elf": [55, 150, 340],
	"orc": [15, 24, 42],
	"goblin": [10, 16, 30],
	"troll": [24, 48, 96],
}
const LABELS: Array[String] = ["YOUNG MALE", "ADULT MALE", "ELDER MALE", "YOUNG FEMALE", "ELDER FEMALE"]

var fails := 0
var helper = null

func run(tree: SceneTree) -> int:
	# Quit even if a render stalls, so a headless run cannot sit until the lane timeout.
	var alarm := tree.create_timer(210.0, true, false, true)
	alarm.timeout.connect(func():
		printerr("test_portraits_v067: stalled, quitting")
		tree.quit(124))
	await tree.process_frame
	FigurePainter.set_legacy_v064(false)
	FigurePainter.snapshot_v066_bust = false
	helper = load("res://tests/test_races_v065.gd").new()
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../test-results")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var afters := {}
	for race in RACES:
		var befores: Array[Image] = []
		var after_row: Array[Image] = []
		var ages: Array = []
		for i in 5:
			var sp: Dictionary = _spec(race, i)
			var before: Image = FigurePainter.render_bust_v066(sp)
			var after: Image = FigurePainter.render_bust(sp)
			if before == null or after == null:
				_fail("%s %d null image" % [race, i])
				if before == null:
					before = Image.create(96, 96, false, Image.FORMAT_RGBA8)
				if after == null:
					after = Image.create(96, 96, false, Image.FORMAT_RGBA8)
			befores.append(before)
			after_row.append(after)
			ages.append(int(sp["age"]))
			_check_pair(race, i, before, after)
		afters[race] = after_row
		var sheet := _race_sheet(race, befores, after_row, ages)
		var path := out_dir.path_join("v0067_portrait_%s.png" % race)
		if sheet.save_png(path) != OK:
			_fail("save " + path)
		else:
			print("SAVED ", path)
	var overview := _overview(afters)
	var all_path := out_dir.path_join("v0067_portrait_all_races.png")
	if overview.save_png(all_path) != OK:
		_fail("save " + all_path)
	else:
		print("SAVED ", all_path)
	print("PORTRAIT_V067 fails=%d" % fails)
	return fails

func _spec(race: String, idx: int) -> Dictionary:
	var female := idx >= 3
	var armed := idx == 1 or idx == 4
	var sp: Dictionary = helper._race_preset(race, armed, female)
	sp["helm"] = {}
	var rd: Dictionary = DB.races.get(race, DB.races["human"])
	var skins: Array = rd.get("skin", ["#e8c4a0"])
	var hairs: Array = rd.get("hair", ["#3a2a1a"])
	sp["skin"] = Color(skins[idx % skins.size()])
	sp["hair"] = Color(hairs[idx % hairs.size()])
	var ages: Array = STAGE_AGE[race]
	match idx:
		0:
			sp["sex"] = "male"
			sp["age"] = ages[0]
			sp["beard"] = race == "dwarf"
			sp["beard_style"] = 0
			sp["seed"] = 11
			sp["female_set"] = 0
		1:
			sp["sex"] = "male"
			sp["age"] = ages[1]
			sp["beard"] = race in ["human", "dwarf", "orc", "troll"]
			sp["beard_style"] = 1
			sp["seed"] = 23
			sp["female_set"] = 0
		2:
			sp["sex"] = "male"
			sp["age"] = ages[2]
			sp["beard"] = race in ["human", "dwarf", "orc", "troll", "high_elf", "moon_elf"]
			sp["beard_style"] = 2
			sp["hair"] = Color(hairs[idx % hairs.size()]).lerp(Color("#d8d8dc"), 0.65)
			sp["seed"] = 37
			sp["female_set"] = 0
		3:
			sp["sex"] = "female"
			sp["age"] = ages[0]
			sp["beard"] = false
			sp["seed"] = 61
			sp["female_set"] = 0
		4:
			sp["sex"] = "female"
			sp["age"] = ages[2]
			sp["beard"] = false
			sp["hair"] = Color(hairs[idx % hairs.size()]).lerp(Color("#e4e4ea"), 0.60)
			sp["seed"] = 79
			sp["female_set"] = 1
	return sp

func _check_pair(race: String, idx: int, before: Image, after: Image) -> void:
	if after.get_width() != 96 or after.get_height() != 96:
		_fail("%s %d size %s" % [race, idx, after.get_size()])
	var opaque := 0
	var bright := 0
	var hot_worst := 0
	for y in after.get_height():
		var hot := 0
		for x in after.get_width():
			var c := after.get_pixel(x, y)
			if c.a > 0.5:
				opaque += 1
			if c.a > 0.5 and c.r > 0.80 and c.g > 0.78 and c.b > 0.74:
				bright += 1
			if race == "dark_elf" and y >= 70 and c.a > 0.5 and c.r > 0.62 and c.g < 0.42 and c.b > 0.25 and c.r > c.g + 0.25:
				hot += 1
		if y >= 70:
			hot_worst = maxi(hot_worst, hot)
	if opaque < 300:
		_fail("%s %d opaque %d" % [race, idx, opaque])
	if bright < 8:
		_fail("%s %d eye whites %d" % [race, idx, bright])
	if race == "dark_elf" and hot_worst >= 8:
		_fail("%s %d hot pink row %d" % [race, idx, hot_worst])
	if _diff(before, after) < 200:
		_fail("%s %d before/after diff too small" % [race, idx])

func _diff(a: Image, b: Image) -> int:
	var da := a.get_data()
	var db := b.get_data()
	var n := 0
	var m := mini(da.size(), db.size())
	for i in range(0, m, 4):
		if absi(int(da[i]) - int(db[i])) > 12:
			n += 1
		elif absi(int(da[i + 1]) - int(db[i + 1])) > 12:
			n += 1
		elif absi(int(da[i + 2]) - int(db[i + 2])) > 12:
			n += 1
		elif absi(int(da[i + 3]) - int(db[i + 3])) > 12:
			n += 1
	return n

func _race_sheet(race: String, befores: Array[Image], afters: Array[Image], ages: Array) -> Image:
	var scale := 3
	var bw := 96 * scale
	var gap := 10
	var margin := 14
	var header := 28
	var label_h := 20
	var row_h := header + bw + label_h
	var width := margin * 2 + 5 * bw + 4 * gap
	var height := margin + row_h + 12 + row_h + margin
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color("#12161e"))
	_half(img, race, "BEFORE v0.066", befores, ages, margin, scale)
	_half(img, race, "AFTER v0.067", afters, ages, margin + row_h + 12, scale)
	return img

func _half(img: Image, race: String, title: String, row: Array, ages: Array, y0: int, scale: int) -> void:
	var bw := 96 * scale
	var gap := 10
	var margin := 14
	helper._draw_text(img, margin, y0, "%s  %s" % [title, race.replace("_", " ")], Color("#f2da94"), 2)
	for i in 5:
		var big: Image = helper._scale_nearest(row[i], scale)
		var x := margin + i * (bw + gap)
		var y := y0 + 28
		img.fill_rect(Rect2i(x - 2, y - 2, bw + 4, bw + 4), Color("#d9a441"))
		img.fill_rect(Rect2i(x, y, bw, bw), Color("#1a120e"))
		helper._blit_alpha(img, big, Vector2i(x, y))
		helper._draw_text(img, x + 4, y + bw + 4, "%s %s" % [LABELS[i], str(ages[i])], Color("#d5e2f2"), 1)

func _overview(afters: Dictionary) -> Image:
	var scale := 2
	var bw := 96 * scale
	var gap := 8
	var margin := 12
	var label_w := 78
	var row_h := bw + 8
	var width := margin + label_w + 5 * bw + 4 * gap + margin
	var height := margin + RACES.size() * row_h + margin
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color("#12161e"))
	for r in RACES.size():
		var race: String = RACES[r]
		var y := margin + r * row_h
		helper._draw_text(img, margin, y + 8, race.replace("_", " "), Color("#f2da94"), 1)
		var row: Array = afters[race]
		for i in 5:
			var big: Image = helper._scale_nearest(row[i], scale)
			var x := margin + label_w + i * (bw + gap)
			img.fill_rect(Rect2i(x, y, bw, bw), Color("#1a120e"))
			helper._blit_alpha(img, big, Vector2i(x, y))
	return img

func _fail(msg: String) -> void:
	printerr("FAIL ", msg)
	fails += 1
