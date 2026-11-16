extends RefCounted
## One-time native preparation for DevTools.world_path(true) (seed 4242, Normal, one-day presim with creatures).
## Never fabricates late state; runs the production DevTools.start_world generator if the cache is absent and writes a provenance receipt.
## run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.

const SpeedParts: GDScript = preload("res://tests/fixtures/older_speed_parts_v100.gd")
const SCHEMA: String = "held-campaign-warbands-creatures-v100-r4/1"

func run(tree: SceneTree) -> int:
	var started_usec: int = Time.get_ticks_usec()
	var before_source: String = SpeedParts.source_stamp()
	var keep_save: String = Game.SAVE_PATH
	var had_autosave: bool = Game.settings.has("autosave")
	var keep_autosave: Variant = Game.settings.get("autosave", null)
	Game.settings["autosave"] = "off"
	var cache: String = DevTools.world_path(true)
	var scratch: String = "user://make_fixture_warbands_v100_%d.json" % OS.get_process_id()
	var ok: bool = await DevTools.start_world(tree, scratch, true)
	while ok and not (Game.world.get("work", []) as Array).is_empty():
		Game.advance_time(0.0, false, 0, 1000)
		await tree.process_frame
	Game.SAVE_PATH = keep_save
	if had_autosave:
		Game.settings["autosave"] = keep_autosave
	else:
		Game.settings.erase("autosave")
	if not ok or not FileAccess.file_exists(cache):
		printerr("FAIL: native creatures start world fixture was not created or loaded: " + cache)
		return 1
	if int(Game.world.get("seed", 0)) != DevTools.WORLD_SEED or CampaignWorld.presim_total(Game) != 1 or CampaignWorld.presim_left(Game) != 0:
		printerr("FAIL: native creatures start world did not finish seed 4242 one-day presim")
		return 1
	if not (Game.world.get("player_house", {}) as Dictionary).is_empty() or str(Game.world.get("encounter", "")) != "":
		printerr("FAIL: native creatures start world must remain unselected with no encounter")
		return 1
	if SpeedParts.source_stamp() != before_source:
		printerr("FAIL: source changed during warbands fixture preparation")
		return 1
	var elapsed: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
	var receipt: Dictionary = {
		"schema": SCHEMA,
		"complete": true,
		"producer": "res://tests/make_fixture_campaign_warbands_v100.gd",
		"cache_path": cache,
		"seed": DevTools.WORLD_SEED,
		"world_size": "normal",
		"creatures": true,
		"presim_days": 1,
		"wall_seconds": elapsed,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"engine": Engine.get_version_info(),
		"source_stamp": before_source,
		"file_sha256": FileAccess.get_sha256(cache),
	}
	var receipt_path: String = cache + ".receipt.json"
	var file: FileAccess = FileAccess.open(receipt_path, FileAccess.WRITE)
	if file == null:
		printerr("FAIL: could not open warbands fixture receipt: " + receipt_path)
		return 1
	file.store_string(JSON.stringify(receipt, "\t", true, true))
	file.flush()
	var write_err: Error = file.get_error()
	file.close()
	if write_err != OK:
		printerr("FAIL: could not write warbands fixture receipt: " + receipt_path)
		return 1
	print("FIXTURE PREPARATION COMPLETE (not a test pass): ", receipt_path, " ", JSON.stringify(receipt))
	return 0
