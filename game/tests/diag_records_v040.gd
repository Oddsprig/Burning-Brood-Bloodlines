extends RefCounted
## Bounded diagnostic for a real save changing while opening dashboard details.

func run(tree: SceneTree) -> int:
	await tree.process_frame
	Game.new_game(40040)
	CampaignWorld.presim_step(Game, 1)
	var cache_failures := _herd_cache_reads()
	var tid := String(Game.world["factions"]["middle_kingdom"]["capital"])
	Game.location = tid
	Game.screen_params = {"view": "town", "id": tid, "tab": "Overview"}
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	tree.root.add_child(viewport)
	var screen: Control = load("res://ui/records.tscn").instantiate()
	viewport.add_child(screen)
	await tree.process_frame
	var before := Game._save_tree()
	for section in screen._disclosures(screen.list_box):
		(section.get_child(0) as Button).pressed.emit()
	var paths := []
	diff(before, Game._save_tree(), "save", paths)
	print("RECORDS OVERVIEW CHANGED PATHS ", paths)
	viewport.free()
	return cache_failures + (0 if paths.is_empty() else 1)

func diff(a: Variant, b: Variant, path: String, paths: Array) -> void:
	if paths.size() >= 5 or a == b: return
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): paths.append(path + "." + str(key) + " removed")
			else: diff(a[key], b[key], path + "." + str(key), paths)
		for key in b:
			if not a.has(key): paths.append(path + "." + str(key) + " added")
	elif a is Array and b is Array and a.size() == b.size():
		for i in a.size(): diff(a[i], b[i], path + "[" + str(i) + "]", paths)
	else:
		paths.append(path + " " + str(a).substr(0, 90) + " -> " + str(b).substr(0, 90))

## Exercise actual registered herd owners with cold derived caches. Only fixture
## cache slots are removed/restored; all herd/person/job records remain real.
func _herd_cache_reads() -> int:
	var failures := 0
	var checks := 0
	var selected_e: Dictionary = {}
	var selected_f: Dictionary = {}
	var selected_h: Dictionary = {}
	for town: Dictionary in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		for h: Dictionary in RecData.herd_records(e):
			if String(h["ow"]) != "f": continue
			var f := RecData.fam(e, int(h["oi"]))
			if int(f.get("hands", 0)) <= 0 or not f.has("pp") or not f.has("kp") or (f["pp"] as Array).is_empty(): continue
			selected_e = e
			selected_f = f
			selected_h = h
			break
		if not selected_e.is_empty(): break
	if selected_e.is_empty():
		printerr("FAIL: generated world has an actual working family herd owner for cache-read checks")
		return 1
	var hd: Dictionary = selected_e["hd"]
	var had_labour := hd.has("_labour")
	var had_version := hd.has("_labour_ver")
	var old_labour: Variant = hd.get("_labour")
	var old_version: Variant = hd.get("_labour_ver")
	for route in ["herders", "family_work", "uncached_family_work"]:
		hd.erase("_labour")
		hd.erase("_labour_ver")
		var read_e := selected_e.duplicate()
		read_e["hd"] = hd.duplicate()
		var expected: Variant = Herds.herders(read_e, selected_h) if route == "herders" else Persons.work(read_e, selected_f)
		var before := Game._save_tree()
		var context := RecData.work_context(selected_e) if route == "family_work" else {}
		var actual: Variant = RecData.herders(selected_e, selected_h) if route == "herders" else RecData._family_work(selected_e, selected_f, context)
		checks += 2
		if actual != expected:
			failures += 1
			printerr("FAIL: ", route, " preserves original actual herd-owner names/work")
		var paths := []
		diff(before, Game._save_tree(), "save", paths)
		if not paths.is_empty():
			failures += 1
			printerr("FAIL: ", route, " changed saved state: ", paths)
		if route == "family_work":
			checks += 1
			if not (context.get("herd_read", {}) as Dictionary).get("hd", {}).has("_labour"):
				failures += 1
				printerr("FAIL: actual work context retains its local derived herd-labour lookup")
	if had_labour: hd["_labour"] = old_labour
	else: hd.erase("_labour")
	if had_version: hd["_labour_ver"] = old_version
	else: hd.erase("_labour_ver")
	print("RECORDS HERD CACHE READS checks=", checks, " failures=", failures)
	return failures
