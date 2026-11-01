extends RefCounted
## v0.084: a Normal start save finishes inside a budget, and autosave waits out its interval.
## The director runs this. It does not start a battle and it does not raise two full armies.

const SAVE_BUDGET_MS := 3000
var checks := 0
var fails := 0

func check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		printerr("FAIL save speed: ", why)

func completed() -> int:
	return int(Game.save_stats()["completed"])

func run(tree: SceneTree) -> int:
	await tree.process_frame
	check(Game.SAVE_PATH.begins_with("user://test_"), "runner supplied a private user save path")
	if not Game.SAVE_PATH.begins_with("user://test_"):
		return fails
	Game.wait_save()
	Game.set_process(false)
	check(str(Game.setting("autosave")) == "week" and Game.autosave_interval_days() == 7, "autosave defaults to one in-game week")

	Game.company = []
	Game.stash = []
	Game.squads = {}
	Game.rep = {}
	Game.contract = {}
	Game.world = {"kept": true}
	Game._save_ready = true
	Game._save_pending = false
	Game._active_screen = "map"
	Game.day = 0.0
	Game._autosave_stamp_day = -1.0e9

	var done := completed()
	Game.request_autosave()
	Game.wait_save()
	check(completed() == done + 1, "first autosave on a new world writes once")
	Game.day = 6.9
	Game.request_autosave()
	Game.wait_save()
	check(completed() == done + 1, "autosave does not write again before seven days")
	Game.day = 7.0
	Game.request_autosave()
	Game.wait_save()
	check(completed() == done + 2, "autosave writes again after seven days")

	Game.set_setting("autosave", "season")
	Game._autosave_stamp_day = 10.0
	Game.day = 10.0 + float(Calendar.DAYS_PER_SEASON) - 0.1
	done = completed()
	Game.request_autosave()
	Game.wait_save()
	check(completed() == done, "season autosave waits out the season")
	Game.day = 10.0 + float(Calendar.DAYS_PER_SEASON)
	Game.request_autosave()
	Game.wait_save()
	check(completed() == done + 1, "season autosave writes once the season has elapsed")

	Game.set_setting("autosave", "off")
	Game._autosave_stamp_day = -1.0e9
	Game.day = 0.0
	done = completed()
	Game.request_autosave()
	Game.wait_save()
	check(completed() == done and not Game._save_pending, "off does not autosave")
	Game.save_game()
	Game.wait_save()
	check(completed() == done + 1, "off still writes a manual save")

	Game.set_setting("autosave", "week")
	Game._autosave_stamp_day = -1.0e9
	Game._active_screen = "battle"
	Game._save_pending = false
	done = completed()
	Game.request_autosave()
	check(not Game._save_pending and completed() == done, "a battle does not start or queue an autosave")

	Game.set_setting("autosave", "off")
	Game._active_screen = "map"
	Game.world = {"kept": true}
	Game._save_pending = false
	done = completed()
	Game.save_on_quit()
	check(completed() == done + 1, "quit writes even when autosave is off")

	Game._active_screen = "battle"
	Game._save_pending = false
	done = completed()
	Game.save_on_quit()
	check(completed() == done and not Game._save_pending, "quit during a battle does not start a save")

	Game._active_screen = "map"
	Game.world = {}
	Game._save_pending = false
	done = completed()
	Game.save_on_quit()
	check(completed() == done, "quit on an empty world does not start a save")

	Game.world = {"book": {"crop_work_acres": {"a": 1}, "crop_work_plots": {"a": [0]}, "crop_yields": {}, "crop_names": {}, "_crop_work_plots_valid": true, "crop_year": 3, "own": 7}}
	var tree_data: Dictionary = Game._save_tree()
	var book: Dictionary = tree_data["world"]["book"]
	check(not book.has("crop_work_acres") and not book.has("crop_work_plots") and not book.has("crop_yields") and not book.has("crop_names") and not book.has("_crop_work_plots_valid"), "save leaves out crop indexes load rebuilds")
	check(int(book["own"]) == 7 and int(book["crop_year"]) == 3, "save keeps the plot fields load does not rebuild")

	var old := {"version": 1, "seed": 9, "day": 4.0, "gold": 3, "next_unit_uid": 1, "company": [], "stash": [], "squads": {}, "rep": {}, "world": {}, "contract": {}, "location": ""}
	var wrote: Dictionary = Game._write_save(Game.SAVE_PATH, old)
	check(bool(wrote.get("ok", false)), "a pre-v084 save file can be written")
	check(Game.load_game(), "a pre-v084 save still loads")
	check(Game.seed_value == 9 and is_equal_approx(float(Game.day), 4.0) and Game.gold == 3, "an old save keeps its seed, day and gold")

	Game.set_setting("autosave", "week")
	Game._active_screen = "map"
	var ready: bool = await DevTools.start_world(tree, Game.SAVE_PATH)
	check(ready, "Normal start world loaded")
	if ready:
		var day_before := float(Game.day)
		var seed_before := int(Game.seed_value)
		var gold_before := int(Game.gold)
		var started := Time.get_ticks_usec()
		Game.save_game()
		Game.wait_save()
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var stats: Dictionary = Game.save_stats()
		print("v084 save %.1f ms, snapshot %d us, encode %d us, write %d us, %d bytes" % [elapsed_ms, int(stats["last_snapshot_us"]), int(stats["last_encode_us"]), int(stats["last_write_us"]), int(stats["serialized_bytes"])])
		check(bool(stats["last_ok"]), "Normal start save completed")
		check(elapsed_ms <= float(SAVE_BUDGET_MS), "Normal start save took %.1f ms, budget is %d ms" % [elapsed_ms, SAVE_BUDGET_MS])
		var text := FileAccess.get_file_as_string(Game.SAVE_PATH)
		check(text.begins_with("{") and not text.begins_with("{\n"), "save JSON is compact")
		check(not text.contains("\"crop_work_acres\"") and not text.contains("\"crop_work_plots\""), "Normal start save omits rebuilt crop indexes")
		Game.day = -1.0
		Game.gold = -1
		Game.seed_value = -1
		check(Game.load_game(), "the timed save loads")
		check(is_equal_approx(float(Game.day), day_before) and Game.seed_value == seed_before and Game.gold == gold_before, "the timed save round-trips day, seed and gold")

	Game.set_setting("autosave", "week")
	Game._active_screen = "map"
	Game.set_process(true)
	print("v084 save speed: %d checks, %d fails" % [checks, fails])
	return fails
