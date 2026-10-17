extends RefCounted
## Art: every faction's warband units render in every pose (several progress values) without
## errors, produce a non-trivial image, facing/team colour/wounds/severed parts work, and the
## Paperdoll node builds textures headless.

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
	rng.seed = 99
	var units: Array = []
	for fid in DB.factions:
		units.append_array(Factory.make_warband(rng, fid, 4))
	# every race, including the not-yet-enabled ones
	for race in DB.races:
		var u := Unit.create(race, "player")
		Factory.roll_look(rng, u)
		u.equip["main_hand"] = Item.make("glaive", "copper", 5)
		u.equip["helm"] = Item.make("crescent_helm", "tin", 2)
		u.equip["body"] = Item.make("scale_vest", "copper", 1)
		units.append(u)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	for u in units:
		var sp := FigurePainter.spec_for_unit(u, Color.CYAN)
		for pose in FigurePainter.POSES:
			for t in [0.0, 0.5, 1.0]:
				var img := FigurePainter.render(sp, pose, t)
				frames += 1
				var n := _opaque(img)
				if img == null or n < 60:
					printerr("FAIL render %s %s %s t=%.1f opaque=%d" % [u.race, u.title, pose, t, n])
					fails += 1
	print("rendered %d frames in %d ms" % [frames, Time.get_ticks_msec() - t0])
	# every armor / weapon sprite key is drawn and distinct
	var seen := {}
	for tid in DB.weapons.keys() + DB.armor.keys():
		var tm := DB.template(tid)
		var spk: String = tm.get("sprite", "")
		if spk == "" or seen.has(spk):
			continue
		var u := Unit.create("human", "middle_kingdom")
		u.look = {"skin": "#d4a27a", "hair": "#5a3a22", "beard": false, "seed": 1}
		u.equip[Item.make(tid, "copper").slot()] = Item.make(tid, "copper")
		var img := FigurePainter.render(FigurePainter.spec_for_unit(u), "idle", 0.0)
		var key := Marshalls.raw_to_base64(img.get_data()).sha256_text()
		for other in seen:
			if seen[other] == key:
				printerr("FAIL sprite %s looks identical to %s" % [spk, other])
				fails += 1
		seen[spk] = key
	print("distinct sprites: ", seen.size(), " ", seen.keys())
	# material changes the look
	var a := Unit.create("human", "middle_kingdom")
	a.look = {"skin": "#d4a27a", "hair": "#5a3a22", "beard": true, "seed": 2}
	a.equip["body"] = Item.make("mail_shirt", "copper")
	var img_cu := FigurePainter.render(FigurePainter.spec_for_unit(a), "idle", 0.0)
	a.equip["body"] = Item.make("mail_shirt", "tin")
	var img_tin := FigurePainter.render(FigurePainter.spec_for_unit(a), "idle", 0.0)
	if img_cu.get_data() == img_tin.get_data():
		printerr("FAIL copper and tin render identically")
		fails += 1
	# wounds + severed parts change the picture and never crash
	var w: Unit = units[0]
	var before := FigurePainter.render(FigurePainter.spec_for_unit(w), "idle", 0.0)
	for pid in ["hand_r", "arm_lower_l", "leg_lower_r", "head"]:
		w.body.parts[pid]["severed"] = true
	for l in w.body.parts["torso_upper"]["layers"]:
		l["dmg"] = 0.8
		l["bleed"] = 0.3
	w.body.blood = w.body.blood_max * 0.4
	var sp_w := FigurePainter.spec_for_unit(w)
	if not ("head" in sp_w["lost"] and "hand_r" in sp_w["lost"]):
		printerr("FAIL lost parts not in spec")
		fails += 1
	for pose in FigurePainter.POSES:
		FigurePainter.render(sp_w, pose, 0.5)
	var after := FigurePainter.render(sp_w, "idle", 0.0)
	if before.get_data() == after.get_data():
		printerr("FAIL wounds did not change the image")
		fails += 1
	# Paperdoll node path
	await tree.process_frame
	var root := Node2D.new()
	tree.root.add_child(root)
	for i in mini(units.size(), 12):
		var d := Paperdoll.new()
		d.set_unit(units[i])
		d.team_color = Color.RED
		d.facing = -1 if i % 2 else 1
		root.add_child(d)
		for pose in FigurePainter.POSES:
			d.set_pose(pose, 0.3)
			if d._tex == null:
				printerr("FAIL no texture for ", pose)
				fails += 1
		d.refresh()
		var img := d.build_image()
		if img == null or img.get_width() < 32:
			fails += 1
	await tree.process_frame
	await tree.process_frame
	root.queue_free()
	# severed pieces (ground decals) for every part of a unit that has already lost them
	for pid in DB.bodies["humanoid"]["parts"].map(func(pp): return pp["id"]):
		var piece := Paperdoll.make_severed_piece(w, pid)
		var spr := piece as Sprite2D
		if spr == null or spr.texture == null:
			printerr("FAIL severed piece ", pid)
			fails += 1
		elif pid == "head" and _opaque(spr.texture.get_image()) < 30:
			printerr("FAIL severed head too small")
			fails += 1
		piece.free()
	# frame quantisation
	if FigurePainter.frame_index("walk", 0.99) != 7 or FigurePainter.frame_index("strike", 1.0) != 4:
		printerr("FAIL frame index")
		fails += 1
	return fails
