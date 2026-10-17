extends RefCounted
## The land map (ui/land_map.gd): mounts into any Control; every overlay composes; the town's own buildings keep
## their slate-and-gold sprite in every overlay; the strip follows the overlay and a family tap shows only its
## plots; the Town tab opens it; perf: a 1,500-plot town composes once per overlay change and pans at frame rate
## (one texture), tap -> card under 16 ms (headless).

var fails := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		print("FAIL: ", msg)
		fails += 1

func _find_view(n: Node) -> Node:
	if n.get_class() == "Control" and n.has_method("plot_at"):
		return n
	for c in n.get_children():
		var r := _find_view(c)
		if r != null:
			return r
	return null

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for c in n.get_children():
		var r := _find_button(c, text)
		if r != null:
			return r
	return null

## A big town for the perf gate: a copy of a generated town with its land, homes and herds scaled up until it
## lays out to at least 1,500 plots (the world's own towns are left alone).
func _big_town(src: Dictionary) -> Dictionary:
	var t: Dictionary = src.duplicate(true)
	t["id"] = "perf_big"
	var e: Dictionary = t["econ"]
	e.erase("plots")
	for k in 6:
		for f in e["fams"]:
			for c in f["land"]:
				f["land"][c] = int(f["land"][c]) * 2
			for a in f["herd"]:
				f["herd"][a] = int(f["herd"][a]) * 2
		for c in e["land"]:
			e["land"][c] = int(e["land"][c]) * 2
		e["territory"] = int(e["territory"]) * 2
		Plots.layout(Game.world, t)
		if Plots.count(Plots.of(t)) >= 1500:
			break
	return t

func run(tree: SceneTree) -> int:
	Game.new_game(5150)
	var ids: Array = Game.world["towns"].keys()
	ids.sort()
	var town: Dictionary = Game.world["towns"][ids[0]]
	var e: Dictionary = town["econ"]
	var host := Control.new()
	host.size = Vector2(1280, 720)
	tree.root.add_child.call_deferred(host)
	await tree.process_frame
	var root := LandMap.mount(host, town)
	await tree.process_frame
	var view = _find_view(root)
	check(view != null, "the map view is mounted")
	var P := Plots.of(town)
	# every overlay composes; state buildings keep their own sprite in each
	var st: int = P["bld"][0]["p"]
	var at := Vector2i(int(P["x"][st]) * LandMap.TILE + 1, int(P["y"][st]) * LandMap.TILE + 1)
	var spr := LandMap.sprite(LandMap.sprite_key(e, P, st, Game.day)).get_pixel(1, 1)
	check(spr.is_equal_approx(LandMap.GOLD), "state sprite has a gold edge")
	for o in LandMap.OVERLAYS:
		view.set_overlay(o)
		var img: Image = LandMap.compose(town, o)["img"]
		check(img.get_pixelv(at).is_equal_approx(spr), "%s overlay: the keep keeps its slate-and-gold tile" % o)
		check(not LandMap.strip_items(town, o).is_empty(), "%s overlay has a summary strip" % o)
		check(view.strip.get_child_count() > 0, "%s strip shown" % o)
	# OWNER strip: tap a family -> only its plots stay bright
	view.set_overlay("OWNER")
	var fam_item: Dictionary = {}
	for it in LandMap.strip_items(town, "OWNER"):
		if int(it["fid"]) > 0:
			fam_item = it
			break
	check(not fam_item.is_empty(), "OWNER strip names families")
	if not fam_item.is_empty():
		var fid := int(fam_item["fid"])
		var mine := -1; var other := -1
		for i in Plots.count(P):
			if Plots.LAND_USES.has(int(P["use"][i])):
				if int(P["own"][i]) == fid and mine < 0:
					mine = i
				elif int(P["own"][i]) != fid and other < 0:
					other = i
		var plain: Image = LandMap.compose(town, "OWNER")["img"]
		var foc: Image = LandMap.compose(town, "OWNER", fid)["img"]
		var pm := Vector2i(int(P["x"][mine]) * LandMap.TILE + 5, int(P["y"][mine]) * LandMap.TILE + 5)
		var po := Vector2i(int(P["x"][other]) * LandMap.TILE + 5, int(P["y"][other]) * LandMap.TILE + 5)
		check(plain.get_pixelv(pm).is_equal_approx(foc.get_pixelv(pm)), "the family's own plots stay bright")
		check(foc.get_pixelv(po).get_luminance() < plain.get_pixelv(po).get_luminance(), "other plots dim")
		view.set_focus(fid)
		check(view.focus == fid, "strip tap sets the focus")
	# tap -> card, timed, on every kind of plot
	view.set_overlay("USE")
	var kinds := {}
	var worst := 0.0
	var taps := 0
	for i in Plots.count(P):
		var u := int(P["use"][i])
		if kinds.get(u, 0) >= 3:
			continue
		kinds[u] = int(kinds.get(u, 0)) + 1
		var pos: Vector2 = view.off + (Vector2(int(P["x"][i]), int(P["y"][i])) + Vector2(0.5, 0.5)) * LandMap.TILE * view.zoom
		var t0 := Time.get_ticks_usec()
		view.tap(pos)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		taps += 1
		check(view.sel == i, "tap lands on plot %d (got %d)" % [i, view.sel])
		check(view.card_box.get_child_count() >= 2, "plot %d card shown" % i)
	print("tap -> card: worst %.2f ms over %d taps" % [worst, taps])
	check(worst < 16.0, "tap -> card under 16 ms (worst %.2f ms)" % worst)
	view.tap(Vector2(-500, -500))
	check(view.sel == -1, "tap off the map clears the card (town buildings)")
	# ---------------------------------------------------------------- 1,500 plots
	var big := _big_town(town)
	var bp := Plots.of(big)
	print("big town: %d plots on %dx%d" % [Plots.count(bp), int(bp["gw"]), int(bp["gh"])])
	check(Plots.count(bp) >= 1500, "perf town has 1,500 plots (%d)" % Plots.count(bp))
	var host2 := Control.new()
	host2.size = Vector2(1280, 720)
	tree.root.add_child(host2)
	check(view.is_inside_tree(), "the first map is in the scene tree (draws for real)")
	var root2 := LandMap.mount(host2, big)
	await tree.process_frame
	var v2 = _find_view(root2)
	var cworst := 0.0
	for o in LandMap.OVERLAYS:
		v2.set_overlay(o)
		cworst = maxf(cworst, v2.compose_ms)
	print("1,500-plot compose (overlay change): worst %.1f ms" % cworst)
	check(cworst < 120.0, "overlay change on 1,500 plots composes in %.1f ms (< 120)" % cworst)
	# panning and zooming: frames only move one texture
	var fworst := 0.0
	for k in 30:
		var t1 := Time.get_ticks_usec()
		var mm := InputEventMouseMotion.new()
		v2._down = true
		mm.relative = Vector2(7, 3)
		v2._gui_input(mm)
		if k % 5 == 0:
			v2.zoom_at(Vector2(400, 300), 1.05)
		await tree.process_frame
		fworst = maxf(fworst, float(Time.get_ticks_usec() - t1) / 1000.0)
	v2._down = false
	print("pan/zoom frame worst %.2f ms" % fworst)
	check(fworst < 16.7, "pan/zoom frame under 16.7 ms on 1,500 plots (%.2f)" % fworst)
	var bworst := 0.0
	for i in range(0, Plots.count(bp), 97):
		var pos2: Vector2 = v2.off + (Vector2(int(bp["x"][i]), int(bp["y"][i])) + Vector2(0.5, 0.5)) * LandMap.TILE * v2.zoom
		var t2 := Time.get_ticks_usec()
		v2.tap(pos2)
		bworst = maxf(bworst, float(Time.get_ticks_usec() - t2) / 1000.0)
	print("1,500 plots tap -> card worst %.2f ms" % bworst)
	check(bworst < 16.0, "tap -> card under 16 ms on 1,500 plots (%.2f)" % bworst)
	# ---------------------------------------------------------------- the Town tab opens it
	var host3 := Control.new()
	host3.size = Vector2(1280, 720)
	tree.root.add_child(host3)
	var tab := TownEconTab.build(host3, town)
	host3.add_child(tab)
	var b := _find_button(tab, "Land map")
	check(b != null, "Town tab has a Land map button")
	if b != null:
		b.pressed.emit()
		await tree.process_frame
		check(_find_view(host3) != null, "Land map button opens the map")
	host.queue_free(); host2.queue_free(); host3.queue_free()
	await tree.process_frame
	return fails
