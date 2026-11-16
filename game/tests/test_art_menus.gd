extends RefCounted
const SpeedParts = preload("res://tests/fixtures/older_speed_parts_v100.gd")
## Art: portraits and party icons for every faction, and the game icon image.

func _opaque(img: Image) -> int:
	# RGBA8 alpha > 0.5 is exactly byte >= 128; keep the original path for every other format.
	if img.get_format() == Image.FORMAT_RGBA8 and not img.has_mipmaps():
		var bytes: PackedByteArray = img.get_data()
		var opaque: int = 0
		for offset: int in range(3, bytes.size(), 4):
			if bytes[offset] >= 128: opaque += 1
		return opaque
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n

func run(tree: SceneTree) -> int:
	var speed_part: String = SpeedParts.select(["icons"] + DB.factions.keys())
	if speed_part == "": return 1
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	await tree.process_frame
	var root := Node2D.new()
	tree.root.add_child(root)
	for fid in DB.factions:
		var band: Array = Factory.make_warband(rng, fid, 3)
		# Consume the original RNG sequence even when only one faction paints this receipt.
		if not SpeedParts.includes(speed_part, str(fid)): continue
		for u in band:
			var p := Portrait.new()
			p.size = Vector2(96, 96)
			p.set_unit(u)
			root.add_child(p)
			var img := p.build_image()
			if img == null or _opaque(img) < 300:
				printerr("FAIL portrait ", fid)
				fails += 1
		var col := Color(DB.factions[fid]["colors"]["primary"])
		for n in [1, 5, 20]:
			var pi := PartyIcon.new()
			pi.setup(DB.factions[fid]["race"], col, n, band[0] if n == 20 else null)
			pi.walking = n > 1
			root.add_child(pi)
			for f in 5:
				var img := pi.build_image(f)
				if _opaque(img) < 100:
					printerr("FAIL party icon ", fid, " ", n)
					fails += 1
	if PartyIcon.figures_for(1) != 1 or PartyIcon.figures_for(6) != 1 or PartyIcon.figures_for(30) != 1:   # one figure per force
		fails += 1
	await tree.process_frame
	root.queue_free()
	if SpeedParts.includes(speed_part, "icons"):
		for s in [32, 48, 256]:
			var icon := GameIcon.make_icon_image(s)
			if icon.get_width() != s or _opaque(icon) < s * s / 3:
				printerr("FAIL icon ", s)
				fails += 1
	return fails
