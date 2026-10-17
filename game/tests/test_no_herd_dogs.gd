extends RefCounted
## v0.020: new worlds and loaded campaigns have no dogs in the livestock system.
var fails := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL: ", label)

func exact(a, b) -> bool:
	return JSON.stringify(Game._serialize(a), "", true, true) == JSON.stringify(Game._serialize(b), "", true, true)

func _check_world(label: String) -> void:
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town):
			continue
		var e: Dictionary = town["econ"]
		var valid := true
		for h in Herds.herds(e).values():
			valid = valid and String(h["k"]) != "dogs" and not Herds.kind(String(h["k"])).is_empty()
		check(valid, "%s: valid livestock in %s" % [label, town["id"]])
		check(not Herds.town_heads(e).has("dogs") and not e["hd"]["pr"].has("dogs"), "%s: no dog counts or prices" % label)
		check(not (e["hd"].get("pens", {}) as Dictionary).values().has("dogs"), "%s: no dog pens" % label)

func run(_tree: SceneTree) -> int:
	Game.SAVE_PATH = "user://test_no_herd_dogs_%d.json" % OS.get_process_id()
	check(not Herds.kinds().has("dogs"), "dogs absent from livestock data")
	check(not Herds.A()["diseases"].has("distemper"), "dog-only disease removed")
	for row in Herds.A()["start"].values():
		check(not row.has("dogs"), "culture has no starting dogs")
	WorldGen.gen_size = "normal"
	Game.new_game(2026)
	_check_world("new game")
	CampaignWorld.presim_step(Game, 14)
	_check_world("two weeks")
	var town: Dictionary = Game.world["towns"].values()[0]
	var tid := String(town["id"])
	var e: Dictionary = town["econ"]
	var hd: Dictionary = e["hd"]
	var heads_before := Herds.town_heads(e).duplicate(true)
	var records_before: Dictionary = hd["h"].duplicate(true)
	var offers_before: Array = hd["of"].duplicate(true)
	Game.save_game()
	var control_save := FileAccess.get_file_as_string(Game.SAVE_PATH)
	# A pre-v0.020 save fixture, including references that could outlive the removed record.
	var legacy := Herds.new_herd(e, "dogs", "f", 1, Game.day)
	legacy["g"] = 2; legacy["h0"] = 2
	var hid := int(legacy["id"])
	for key in ["pr", "ofk", "wak", "sok"]:
		hd[key]["dogs"] = 2
	hd["of"].append([hid, "g", 1])
	hd["pens"]["-99"] = "dogs"
	hd["tiles"]["-99"] = hid
	hd["plague"]["distemper"] = 2
	hd["plague"]["cattle plague"] = 4
	var history := [int(Game.day), hid, "dogs", 2, "bought", "old herd record"]
	hd["log"].append(history)
	hd.erase("_thk")
	check(int(Herds.town_heads(e).get("dogs", 0)) == 2, "legacy fixture has two dogs")
	var cleaned: Dictionary = hd.duplicate(true)
	Herds._remove_legacy_dogs(cleaned)
	check(exact(cleaned["h"], records_before), "cleanup preserves other records at full precision")
	check(exact(cleaned["of"], offers_before), "cleanup preserves other offers at full precision")
	Game.save_game()
	var legacy_save := FileAccess.get_file_as_string(Game.SAVE_PATH)
	# Compare with the same normal load without the legacy dogs. The existing save writer rounds floats,
	# and unrelated existing load-time bookkeeping runs in both cases.
	var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	file.store_string(control_save); file.close()
	check(Game.load_game(), "control save loads")
	var coins_before := Barge.holdings(Game)
	records_before = Game.world["towns"][tid]["econ"]["hd"]["h"].duplicate(true)
	file = FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	file.store_string(legacy_save); file.close()
	check(Game.load_game(), "legacy save loads")
	e = Game.world["towns"][tid]["econ"]
	hd = e["hd"]
	_check_world("loaded old save")
	check(exact(Herds.town_heads(e), heads_before), "other livestock counts preserved")
	check(exact(hd["h"], records_before), "other livestock records preserved")
	check(exact(hd["of"], offers_before), "other sale offers preserved")
	check(Barge.holdings(Game) == coins_before, "dog migration makes no change to money")
	check(not hd["tiles"].has("-99") and not hd["pens"].has("-99"), "removed plot references")
	for key in ["pr", "ofk", "wak", "sok"]:
		check(not hd[key].has("dogs"), "removed dog market field " + key)
	check(not hd["plague"].has("distemper") and int(hd["plague"]["cattle plague"]) == 4, "only dog disease state removed")
	check(hd["log"].has(history), "past history preserved")
	var once: Dictionary = hd.duplicate(true)
	Herds._remove_legacy_dogs(hd)
	check(exact(hd, once), "cleanup is idempotent")
	CampaignWorld.presim_step(Game, 14)
	_check_world("loaded save two weeks later")
	Game.save_game()
	check(Game.load_game(), "v0.020 save reloads")
	_check_world("v0.020 reload")
	Game.wait_save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	print("No herd dogs: %d checks, %d failures" % [checks, fails])
	return fails
