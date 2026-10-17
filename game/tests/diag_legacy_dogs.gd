extends RefCounted
## Load a real pre-v0.020 history snapshot, migrate dogs, then continue that campaign.
func run(_tree: SceneTree) -> int:
	var path := OS.get_environment("LEGACY_SNAPSHOT")
	if path.is_empty():
		printerr("LEGACY_SNAPSHOT is required")
		return 1
	var source := FileAccess.get_file_as_string(path)
	var tree: Dictionary = JSON.parse_string(source)
	var expected := {}
	var dog_count := 0
	for tid in tree["world"]["towns"]:
		var town: Dictionary = tree["world"]["towns"][tid]
		if not town.has("econ"):
			continue
		var heads := {}
		for h in town["econ"]["hd"]["h"].values():
			var n := Herds.head(h)
			if String(h["k"]) == "dogs":
				dog_count += n
			elif n > 0:
				heads[h["k"]] = int(heads.get(h["k"], 0)) + n
		expected[tid] = heads
	if dog_count <= 0:
		printerr("The legacy snapshot contains no dogs")
		return 1
	Game.SAVE_PATH = "user://legacy_dogs_%d.json" % OS.get_process_id()
	var file := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
	file.store_string(source); file.close()
	tree.clear(); source = ""
	if not Game.load_game():
		return 1
	for tid in expected:
		var e: Dictionary = Game.world["towns"][tid]["econ"]
		if Herds.town_heads(e) != expected[tid]:
			printerr("Non-dog livestock changed in ", tid)
			return 1
	CampaignWorld.presim_step(Game, 14)
	Game.save_game()
	if not Game.load_game():
		return 1
	for town in Game.world["towns"].values():
		if not TownEcon.has_econ(town): continue
		var e: Dictionary = town["econ"]
		for h in Herds.herds(e).values():
			if String(h["k"]) == "dogs" or Herds.kind(String(h["k"])).is_empty():
				printerr("Invalid livestock after the migrated history continued")
				return 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	print("Legacy five-year save: removed %d dogs, preserved other livestock, continued 14 days and reloaded successfully" % dog_count)
	return 0
