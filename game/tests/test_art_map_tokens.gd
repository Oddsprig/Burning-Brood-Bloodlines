extends RefCounted
## Map tokens (docs/specs/map-tokens.md): every type builds for every faction, cache hits, types are told apart
## in greyscale, a 16-man company is one token, syncing 40 tokens per frame is cheap, and PNG sheets for review
## land in %TEMP%/copper_tokens/.

var fails := 0
const OUT := "C:/Users/bligh/AppData/Local/Temp/copper_tokens/"

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _opaque(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n

func _factions() -> Array:
	var out := []
	for fid in DB.factions:
		if not DB.factions[fid].get("wild", false):
			out.append(fid)
	return out

## Luminance-times-alpha mask over a white-free field, downsampled to 36x36.
func _mask(img: Image) -> PackedFloat32Array:
	var s := img.duplicate() as Image
	s.resize(36, 36, Image.INTERPOLATE_BILINEAR)
	var out := PackedFloat32Array()
	for y in 36:
		for x in 36:
			var c := s.get_pixel(x, y)
			# greyscale on a mid-grey map: what the eye reads
			var l := c.get_luminance() * c.a + 0.5 * (1.0 - c.a)
			out.append(l)
			out.append(c.a)
	return out

func _diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var d := 0.0
	for i in a.size():
		d += absf(a[i] - b[i])
	return d / a.size()

func run(tree: SceneTree) -> int:
	await tree.process_frame
	DirAccess.make_dir_recursive_absolute(OUT)
	MapTokens.clear_cache()
	var t0 := Time.get_ticks_usec()
	# --- every token type builds for every faction (and every pip count / stance)
	var facs := _factions()
	for fid in facs:
		for ty in ["army", "militia", "caravan", "deserter"]:
			for p in [1, 3, 5]:
				for st in ["hostile", "neutral", "allied"]:
					var tx := MapTokens.texture(ty, fid, p, st)
					check(tx != null and tx.get_width() == MapTokens.SIZE, "%s %s builds" % [ty, fid])
			check(_opaque(MapTokens.image(ty, fid, 2, "neutral")) > 2500, "%s %s has a body" % [ty, fid])
	for cid in MapTokens.MONSTERS:
		check(_opaque(MapTokens.image("monster", cid, 1, "hostile")) > 2500, "monster %s has a body" % cid)
	check(_opaque(MapTokens.image("bandit", "", 1, "hostile")) > 2500, "bandit has a body")
	check(_opaque(MapTokens.image("player")) > 2500, "player has a body")
	var t_build := (Time.get_ticks_usec() - t0) / 1000.0
	print("  built %d bases in %.0f ms (%.1f ms per base, pips composited)" % [MapTokens.paint_count, t_build, t_build / maxf(1, MapTokens.paint_count)])

	# --- cache: same key -> same texture object, no repaint
	var pc := MapTokens.paint_count
	var a := MapTokens.texture("army", "middle_kingdom", 3, "hostile")
	var b := MapTokens.texture("army", "middle_kingdom", 3, "hostile")
	check(is_same(a, b), "cache hit returns the same texture object")
	check(not is_same(a, MapTokens.texture("army", "middle_kingdom", 3, "allied")), "stance is part of the key")
	check(MapTokens.paint_count == pc, "cache hits paint nothing")

	# --- greyscale distinctness between types (shape alone)
	var samples := {"player": MapTokens.image("player"), "army": MapTokens.image("army", "middle_kingdom", 2, "neutral"),
		"militia": MapTokens.image("militia", "middle_kingdom", 2, "neutral"), "caravan": MapTokens.image("caravan", "middle_kingdom", 2, "neutral"),
		"bandit": MapTokens.image("bandit", "", 2, "hostile"), "monster": MapTokens.image("monster", "wolf", 2, "hostile")}
	var masks := {}
	for k in samples:
		masks[k] = _mask(samples[k])
	var ks := samples.keys()
	var worst := 1.0
	for i in ks.size():
		for j in range(i + 1, ks.size()):
			var d := _diff(masks[ks[i]], masks[ks[j]])
			worst = minf(worst, d)
			check(d > 0.08, "greyscale %s vs %s differ (%.3f)" % [ks[i], ks[j], d])
	print("  smallest greyscale type difference %.3f" % worst)
	# monster heads differ from each other too
	var heads := {}
	for cid in MapTokens.MONSTERS:
		# the inner disc only (box 17..47): the spiked ring and pips are shared by design
		heads[cid] = _mask(MapTokens.image("monster", cid, 1, "hostile").get_region(Rect2i(42, 42, 60, 60)))
	for i in MapTokens.MONSTERS.size():
		for j in range(i + 1, MapTokens.MONSTERS.size()):
			var d := _diff(heads[MapTokens.MONSTERS[i]], heads[MapTokens.MONSTERS[j]])
			print("  head %s vs %s %.3f" % [MapTokens.MONSTERS[i], MapTokens.MONSTERS[j], d])
			check(d > 0.025, "monster heads %s vs %s differ (%.3f)" % [MapTokens.MONSTERS[i], MapTokens.MONSTERS[j], d])

	# --- size bands
	check(MapTokens.pips_for(1) == 1 and MapTokens.pips_for(5) == 1 and MapTokens.pips_for(6) == 2 and MapTokens.pips_for(15) == 2
		and MapTokens.pips_for(16) == 3 and MapTokens.pips_for(30) == 3 and MapTokens.pips_for(31) == 4 and MapTokens.pips_for(60) == 4
		and MapTokens.pips_for(61) == 5, "size bands 1-5 / 6-15 / 16-30 / 31-60 / 61+")

	# --- night cap: token layer modulate x map tint never darker than 70%
	for tint in [Color(0.45, 0.5, 0.72), Calendar.tint(0.0), Color(1, 0.82, 0.68), Color.WHITE]:
		var m := MapTokens.night_comp(tint)
		var f := Color(m.r * tint.r, m.g * tint.g, m.b * tint.b)
		check(minf(f.r, minf(f.g, f.b)) >= 0.699, "night tint capped at 30%% (%s -> %s)" % [tint, f])

	# --- a 16-man company is one token; sync + perf on a real world
	Game.new_game(4242)
	var w: Dictionary = Game.world
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for wid in w["warbands"].keys():
		w["warbands"].erase(wid)
	var ppos: Vector2 = w["party"]["pos"]
	var big := CampaignWorld.spawn_warband(Game, "middle_kingdom", ppos + Vector2(60, 0), 16, "patrol", rng, {"staged": true})
	var root := Node2D.new()
	tree.root.add_child(root)
	var tokens := {}
	var player := MapToken.new()
	player.set_texture("player", MapTokens.texture("player"))
	root.add_child(player)
	MapTokens.sync(root, tokens, Game, [big], 1.0, true, player)
	check(tokens.size() == 1 and root.get_child_count() == 2, "a 16-man company yields exactly one token")
	check((tokens[big] as MapToken).key == MapTokens.key("army", "middle_kingdom", 3, "neutral"), "16 men -> army, 3 pips (%s)" % tokens[big].key)
	# tap hit circle r=30 screen px around the token centre
	for z in [0.5, 1.0, 2.0]:
		MapTokens.sync(root, tokens, Game, [big], z, false, player)
		var cpos := MapTokens.center(w["warbands"][big]["pos"], z)
		check(MapTokens.pick(tokens, w["warbands"], cpos + Vector2(29.0 / z, 0), z) == big, "tap inside r30 hits at zoom %s" % z)
		check(MapTokens.pick(tokens, w["warbands"], cpos + Vector2(31.0 / z, 0), z) == "", "tap outside r30 misses at zoom %s" % z)
		check(is_equal_approx(player.scale.x * MapTokens.BOX * z, maxf(52.0 * z, 40.0)), "token size on screen at zoom %s" % z)
	# 40 forces of mixed kinds
	var kinds := [["middle_kingdom", "patrol"], ["orc_horde", "raider"], ["goblin_warren", "raider"], ["moon_court", "patrol"],
		["northern_clans", "caravan"], ["outlaws", "bandit"], ["middle_kingdom", "militia"]]
	var vis := [big]
	for i in 39:
		var kd: Array = kinds[i % kinds.size()]
		var p := ppos + Vector2(rng.randf_range(-300, 300), rng.randf_range(-300, 300))
		# staged (Army.enlist): a scene of 40 forces, more men than the nearby towns could spare (war pick 4)
		vis.append(CampaignWorld.spawn_warband(Game, kd[0], p, rng.randi_range(2, 40), kd[1], rng, {"staged": true}))
	MapTokens.sync(root, tokens, Game, vis, 1.0, true, player)
	check(tokens.size() == 40, "40 tokens (%d)" % tokens.size())
	for i in 30:
		MapTokens.sync(root, tokens, Game, vis, 1.0, false, player)
	var n := 400
	var ts := Time.get_ticks_usec()
	for i in n:
		for wid in vis:
			w["warbands"][wid]["pos"] += Vector2(0.1, 0)
		MapTokens.sync(root, tokens, Game, vis, 1.0, false, player)
	var move_us := Time.get_ticks_usec() - ts
	ts = Time.get_ticks_usec()
	for i in n:
		for wid in vis:
			w["warbands"][wid]["pos"] += Vector2(0.1, 0)
	var base_us := Time.get_ticks_usec() - ts
	var mean_ms := (move_us - base_us) / 1000.0 / n
	print("  sync of 40 tokens: %.4f ms per frame" % mean_ms)
	check(mean_ms < 0.1, "sync of 40 tokens < 0.1 ms per frame (%.4f)" % mean_ms)
	var ts2 := Time.get_ticks_usec()
	for i in 20:
		MapTokens.sync(root, tokens, Game, vis, 1.0, true, player)
	print("  refresh sync of 40 tokens: %.3f ms" % ((Time.get_ticks_usec() - ts2) / 1000.0 / 20))
	# a force leaving sight frees its token
	MapTokens.sync(root, tokens, Game, vis.slice(0, 10), 1.0, false, player)
	check(tokens.size() == 10, "tokens of forces out of sight are removed")
	root.queue_free()

	_sheets()
	return fails

## PNG sheets for review: colour on parchment, greyscale, and at true map size (52 px) on a dark map green.
func _sheets() -> void:
	var rows := []
	for fid in _factions():
		rows.append([["army", fid, 2, "neutral"], ["army", fid, 4, "allied"], ["militia", fid, 3, "neutral"],
			["caravan", fid, 2, "allied"], ["deserter", fid, 1, "hostile"]])
	rows.append([["player", "", 0, ""], ["bandit", "", 1, "hostile"], ["bandit", "", 3, "hostile"], ["army", "orc_horde", 5, "hostile"],
		["army", "goblin_warren", 2, "hostile"]])
	var mons := []
	for cid in MapTokens.MONSTERS:
		mons.append(["monster", cid, 1 + mons.size(), "hostile"])
	rows.append(mons)
	var S := MapTokens.SIZE
	var sheet := Image.create(S * 5, S * rows.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#cdbb8f"))
	var small := Image.create(70 * 5, 70 * rows.size(), false, Image.FORMAT_RGBA8)
	small.fill(Color("#4f6b3a"))
	for r in rows.size():
		for c in (rows[r] as Array).size():
			var e: Array = rows[r][c]
			var img := MapTokens.image(e[0], e[1], e[2], e[3])
			sheet.blend_rect(img, Rect2i(0, 0, S, S), Vector2i(c * S, r * S))
			var sm := img.duplicate() as Image
			var px := int(round(52.0 * 72.0 / 64.0))
			sm.resize(px, px, Image.INTERPOLATE_LANCZOS)
			small.blend_rect(sm, Rect2i(0, 0, px, px), Vector2i(c * 70 + 6, r * 70 + 4))
	sheet.save_png(OUT + "tokens_sheet.png")
	small.save_png(OUT + "tokens_52px.png")
	var grey := sheet.duplicate() as Image
	for y in grey.get_height():
		for x in grey.get_width():
			var l := grey.get_pixel(x, y).get_luminance()
			grey.set_pixel(x, y, Color(l, l, l))
	grey.save_png(OUT + "tokens_grey.png")
	print("  sheets saved to ", OUT)
