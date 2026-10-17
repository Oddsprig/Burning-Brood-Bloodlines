extends RefCounted
## Art: portraits and party icons for every faction, and the game icon image.

func _opaque(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n

func run(tree: SceneTree) -> int:
	var fails := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	await tree.process_frame
	var root := Node2D.new()
	tree.root.add_child(root)
	for fid in DB.factions:
		var band: Array = Factory.make_warband(rng, fid, 3)
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
	for s in [32, 48, 256]:
		var icon := GameIcon.make_icon_image(s)
		if icon.get_width() != s or _opaque(icon) < s * s / 3:
			printerr("FAIL icon ", s)
			fails += 1
	return fails
