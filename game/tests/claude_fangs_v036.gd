extends RefCounted
## v0.036 dragon portrait fangs: each gem's idle adult portrait is non-empty
## and the jaw-fang pass paints at least one gem-coloured pixel.
## -- --test=res://tests/claude_fangs_v036.gd [--out=dir]
var checks := 0
var fails := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL fangs036: ", what)
	print(("ok   " if ok else "FAIL ") + what)

func _out_dir() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	for a in args:
		if a.begins_with("--out="):
			return a.trim_prefix("--out=").replace("\\", "/").trim_prefix("\"").trim_suffix("\"")
	return ""

func _save_sheet(shots: Array, out: String) -> bool:
	if shots.is_empty(): return false
	var sample: Image = shots[0]
	var cell_w: int = sample.get_width()
	var cell_h: int = sample.get_height()
	if cell_w < 1 or cell_h < 1: return false
	var n: int = shots.size()
	var cols: int = int(ceil(sqrt(float(n))))
	var rows: int = int(ceil(float(n) / float(cols)))
	var sheet: Image = Image.create(cols * cell_w, rows * cell_h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.07, 0.06, 1))
	for i in n:
		var img: Image = shots[i]
		if img == null or img.is_empty(): continue
		if img.get_format() != sheet.get_format():
			img = img.duplicate()
			img.convert(sheet.get_format())
		var dst := Vector2i((i % cols) * cell_w, int(float(i) / float(cols)) * cell_h)
		var rect := Rect2i(Vector2i.ZERO, Vector2i(mini(img.get_width(), cell_w), mini(img.get_height(), cell_h)))
		sheet.blit_rect(img, rect, dst)
	var dir := out
	if dir.begins_with("res://") or dir.begins_with("user://"):
		dir = ProjectSettings.globalize_path(dir)
	elif dir.is_relative_path():
		dir = ProjectSettings.globalize_path("res://".path_join(dir))
	DirAccess.make_dir_recursive_absolute(dir)
	return sheet.save_png(dir.path_join("fangs036_contact.png")) == OK

func run(tree: SceneTree) -> int:
	if tree == null:
		printerr("FAIL fangs036: no scene tree")
		return 1
	var gems: Array = Dragons.catalogs().get("gems", [])
	check(gems.size() > 0, "gem catalog has entries")
	var shots: Array = []
	for gem: Dictionary in gems:
		var gid: String = String(gem.get("id", ""))
		var record: Dictionary = {
			"stage": "adult",
			"gem_id": gid,
			"morph_id": "broadmantle",
			"size_class": "large",
			"appearance_seed": 20,
		}
		var image: Image = DragonArt.portrait_for(record, "idle", 0.0, {})
		var nonempty: bool = image != null and not image.is_empty() and image.get_used_rect().size.x > 0
		check(nonempty, gid + " portrait is non-empty")
		var drawn: int = int(image.get_meta("fang_pixels", 0)) if image != null else 0
		check(drawn > 0, gid + " fang pixels " + str(drawn))
		if image != null: shots.append(image)
	var out := _out_dir()
	if out != "":
		check(_save_sheet(shots, out), "contact sheet saved to " + out)
	print("fangs036: %d checks, %d failures" % [checks, fails])
	return fails
