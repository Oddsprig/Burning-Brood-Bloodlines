extends RefCounted
## DIAGNOSTIC (not a regression test): what screen switches cost on a real world (Douglas v0.014 playtest:
## "pretty long loading screen between menus. and map screen to town screen").
##   DIAG_SIZE  (default WorldGen.WORLD_SIZE)   DIAG_DAYS days of the years before (default 120 = one year)
##   DIAG_CACHE=1 keeps the world in user://diag_screen_world.json and reuses it on later runs (fast iteration)
##   DIAG_SAVE_PARTS=1 splits the save: walk, JSON, write, binary for comparison, load walk, per-town-key walk cost
## Prints each switch's ms (the goto call plus one frame for the new screen's _ready), and the save's own ms.
## Run alone: TEST_TIMEOUT=900 tools/test.sh tests/diag_screen_load.gd

const CACHE := "user://diag_screen_world.json"

func _ms(t0: int) -> float:
	return (Time.get_ticks_usec() - t0) / 1000.0

func run(tree: SceneTree) -> int:
	var size := OS.get_environment("DIAG_SIZE") if OS.get_environment("DIAG_SIZE") != "" else WorldGen.WORLD_SIZE
	var days := int(OS.get_environment("DIAG_DAYS")) if OS.get_environment("DIAG_DAYS") != "" else 120
	var cache := OS.get_environment("DIAG_CACHE") != ""
	WorldGen.gen_size = size
	var real_save: String = Game.SAVE_PATH
	if cache and FileAccess.file_exists(CACHE):
		Game.SAVE_PATH = CACHE
		var t0 := Time.get_ticks_usec()
		Game.load_game()
		print("loaded cached world in %.0f ms" % _ms(t0))
		Game.SAVE_PATH = real_save
	else:
		Game.new_game(2026)
		Game.world["presim"] = {"total": days, "done": 0, "from": Game.day}
		var t0 := Time.get_ticks_usec()
		CampaignWorld.presim_step(Game, days)
		CampaignWorld.presim_finish(Game, 0)
		print("world %s, %d days before in %.1f s" % [size, days, _ms(t0) / 1000.0])
		if cache:
			Game.SAVE_PATH = CACHE
			Game.save_game()
			Game.SAVE_PATH = real_save
	print("towns %d" % Game.world["towns"].size())
	var t1 := Time.get_ticks_usec()
	Game.save_game()
	print("save_game %.1f ms (%.1f MB)" % [_ms(t1), FileAccess.open(Game.SAVE_PATH, FileAccess.READ).get_length() / 1048576.0])
	if OS.get_environment("DIAG_SAVE_PARTS") != "":
		t1 = Time.get_ticks_usec()
		var sw = Game._serialize(Game.world)
		print("  _serialize(world) %.1f ms" % _ms(t1))
		t1 = Time.get_ticks_usec()
		var js := JSON.stringify(sw)
		print("  JSON.stringify %.1f ms (%d chars)" % [_ms(t1), js.length()])
		t1 = Time.get_ticks_usec()
		var f := FileAccess.open("user://diag_tmp.json", FileAccess.WRITE)
		f.store_string(js)
		f.close()
		print("  store_string %.1f ms" % _ms(t1))
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://diag_tmp.json"))
		t1 = Time.get_ticks_usec()
		var by := var_to_bytes(sw)
		print("  var_to_bytes %.1f ms (%.1f MB)" % [_ms(t1), by.size() / 1048576.0])
		t1 = Time.get_ticks_usec()
		var zb := by.compress(FileAccess.COMPRESSION_ZSTD)
		print("  zstd %.1f ms (%.1f MB)" % [_ms(t1), zb.size() / 1048576.0])
		t1 = Time.get_ticks_usec()
		var back = bytes_to_var(by)
		print("  bytes_to_var %.1f ms" % _ms(t1))
		t1 = Time.get_ticks_usec()
		var jb = JSON.parse_string(js)
		print("  JSON.parse %.1f ms" % _ms(t1))
		t1 = Time.get_ticks_usec()
		Game._deserialize(jb)
		print("  _deserialize %.1f ms" % _ms(t1))
		t1 = Time.get_ticks_usec()
		var dup = Game.world.duplicate(true)
		print("  world.duplicate(true) %.1f ms" % _ms(t1))
		t1 = Time.get_ticks_usec()
		var hh := Game.world.hash()
		print("  world.hash() %.1f ms" % _ms(t1))
		var per := {}
		for tid in Game.world["towns"]:
			var t: Dictionary = Game.world["towns"][tid]
			for k in t:
				t1 = Time.get_ticks_usec()
				Game._serialize(t[k])
				per[k] = per.get(k, 0.0) + _ms(t1)
			if t.has("econ"):
				for k in t["econ"]:
					t1 = Time.get_ticks_usec()
					Game._serialize(t["econ"][k])
					per["econ." + str(k)] = per.get("econ." + str(k), 0.0) + _ms(t1)
		for k in Game.world.get("tracks", {}):
			var x = Game.world["tracks"][k]
			t1 = Time.get_ticks_usec()
			Game._serialize(x)
			print("    tracks.%s type %d size %d: %.1f ms" % [k, typeof(x), x.size() if x is Dictionary or x is Array else 0, _ms(t1)])
		var cnt := {"dict": 0, "arr": 0, "plain": 0, "other": 0}
		var stack: Array = [Game.world["towns"]]
		while not stack.is_empty():
			var x = stack.pop_back()
			match typeof(x):
				TYPE_DICTIONARY:
					cnt["dict"] += 1
					stack.append_array(x.values())
				TYPE_ARRAY:
					cnt["arr"] += 1
					stack.append_array(x)
				_:
					if typeof(x) <= TYPE_STRING: cnt["plain"] += 1
					else: cnt["other"] += 1
		print("  towns hold: ", cnt)   # the save walk's cost goes with the containers (dict + arr)
		var ks := per.keys()
		ks.sort_custom(func(a, b): return per[a] > per[b])
		for k in ks.slice(0, 25):
			print("    towns.%s %.1f ms" % [k, per[k]])
		for k in Game.world:
			t1 = Time.get_ticks_usec()
			var part = Game._serialize(Game.world[k])
			var ms := _ms(t1)
			if ms > 20.0:
				t1 = Time.get_ticks_usec()
				var n := JSON.stringify(part).length()
				print("  world.%s: serialize %.1f ms, stringify %.1f ms, %.1f MB" % [k, ms, _ms(t1), n / 1048576.0])
	await tree.process_frame
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.create_timer(3.0).timeout   # a player on the title screen (main.gd loads the big screens meanwhile)
	var tid := ""
	for id in Game.world["towns"]:
		if TownEcon.has_econ(Game.world["towns"][id]):
			tid = id
			break
	var steps := [["map", {}], ["town", {"arrive": true}], ["map", {}], ["town", {"arrive": true}], ["company", {"back": "town"}], ["town", {}],
		["res://ui/records.tscn", {"view": "town", "id": tid, "back": "town"}], ["town", {}], ["map", {}],
		["company", {"back": "map"}], ["map", {}], ["title", {}], ["newgame", {}], ["title", {}], ["map", {}],
		["res://ui/records.tscn", {"view": "town", "id": tid, "back": "map"}], ["map", {}],
		["res://ui/records.tscn", {"view": "world", "back": "map"}], ["map", {}]]
	for s in steps:
		if s[0] == "town":
			Game.location = tid
		var path: String = Game.SCREENS.get(s[0], s[0])
		if not ResourceLoader.has_cached(path):
			var tl := Time.get_ticks_usec()
			load(path)
			print("  (first load of %s: %.1f ms)" % [path.get_file(), _ms(tl)])
		var t0 := Time.get_ticks_usec()
		if s[0] == "map" and main.current != null and main.current.has_method("_leave"):
			main.current._leave()   # the town's Leave button (its autosave included)
		else:
			Game.goto(s[0], s[1])
		var ready_ms := _ms(t0)
		await tree.process_frame
		var f1 := _ms(t0)
		await tree.process_frame
		print("goto %-22s %7.1f ms (ready %.1f, first frame %.1f, second frame %.1f)" % [String(s[0]).get_file(), f1,
			ready_ms, f1 - ready_ms, _ms(t0) - f1])
		if s[0] == "town":
			for tab in ["Provisions", "Recruits", "Healer", "Contracts", "Town", "Market"]:
				var t2 := Time.get_ticks_usec()
				main.current.show_tab(tab)
				print("    tab %-12s %7.1f ms" % [tab, _ms(t2)])
		if s[0] == "company":
			for tab in ["Mind", "Skills", "Gear", "Health", "Squad", "Overview"]:
				var t2 := Time.get_ticks_usec()
				main.current.show_tab(tab)
				print("    tab %-12s %7.1f ms" % [tab, _ms(t2)])
		if String(s[0]).ends_with("records.tscn"):
			for tab in load("res://ui/records.gd").TOWN_TABS:
				var t2 := Time.get_ticks_usec()
				main.current.show_tab(tab)
				print("    tab %-12s %7.1f ms" % [tab, _ms(t2)])
		if s[0] == "town":
			Game.location = tid
	main.queue_free()
	await tree.process_frame
	return 0
