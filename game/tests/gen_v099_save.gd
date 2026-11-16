extends RefCounted
## v0.100: run ONLY on the unmodified public v0.099 source, never the schema-2 checkout.
## Source: 1fcb3fe758ad3a566cbb6b4466b25706fc3cd1d0 (the v0.099 merge on origin/main).
## Test brief: headless runner, one fresh Normal world, one history day, one played day;
## no cached start world, no synthetic save dictionary. Internal budget 160 s; runner 170 s.
## "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."

const OUTPUT := "res://tests/fixtures/legacy_v099_save.json"
const SOURCE_COMMIT := "1fcb3fe758ad3a566cbb6b4466b25706fc3cd1d0"
const BUDGET_MS := 160000
var started := 0

func _fail(why: String) -> int:
	printerr("FAIL gen_v099_save: ", why)
	return 1

func _budget(stage: String) -> bool:
	if Time.get_ticks_msec() - started < BUDGET_MS: return true
	_fail("160 s budget exhausted during " + stage + "; fixture is not accepted")
	return false

func _drain(tree: SceneTree) -> bool:
	while not Game.world.get("work", []).is_empty():
		if not _budget("campaign jobs"): return false
		CampaignWorld.work_slice(Game, 8000)
		await tree.process_frame
	return true

func _generate(tree: SceneTree) -> int:
	if str(ProjectSettings.get_setting("application/config/version", "")) != "0.099":
		return _fail("requires the actual v0.099 checkout; changing a v0.100 save's stamp is not a fixture")
	if FileAccess.file_exists(OUTPUT):
		return _fail("refusing to overwrite " + OUTPUT)
	# The runner already isolates settings. Redirect before any setup can request a save.
	Game.SAVE_PATH = "user://gen_v099_work_%d.json" % OS.get_process_id()
	WorldGen.gen_size = "normal"
	CampaignWorld.presim_span_days = 1
	Monsters.new_world_creatures = false
	var generation: Dictionary = Game.new_game_begin(4242)
	if generation.get("generation_unavailable", false): return _fail("native world generation unavailable")
	while not Game.new_game_slice(generation, 8000):
		if not _budget("world generation"): return 1
		await tree.process_frame
	var history := {}
	while CampaignWorld.presim_left(Game) > 0:
		if not _budget("one-day history"): return 1
		CampaignWorld.presim_slice(Game, history, 8000)
		await tree.process_frame
	CampaignWorld.presim_finish(Game, 0)
	Dynasty.prepare_world(Game)
	Game.new_game_finalize()
	if not await _drain(tree): return 1
	var home: String = DevTools.choose_house(Game)
	if home == "": return _fail("no native ruling household can begin")
	if DevTools.raise_army(Game, home, 4) <= 0:
		return _fail("native funded muster could not raise residents")
	if not await _drain(tree): return 1
	# Advance a real played day and settle its actual jobs, rather than stamping a later day.
	Game.advance_time(1.0, false, 0, 8000)
	if not await _drain(tree): return 1
	if not _budget("save preparation"): return 1
	if Game.day < 2.0 or Game.gold <= 0 or Game.company.is_empty():
		return _fail("played campaign must retain a nonzero purse and a real company on day 2+")
	var families := 0
	var towns: Dictionary = Game.world.get("towns", {})
	for town: Dictionary in towns.values():
		if not TownEcon.has_econ(town): return _fail("generated town lacks its economy")
		families += (town["econ"].get("fams", []) as Array).size()
	var dragons: int = Game.world.get("dragons", {}).get("records", {}).size()
	if towns.is_empty() or families == 0 or dragons == 0:
		return _fail("native towns, families and dragons must all exist")
	# Inspect the real old snapshot, but let v0.099's own save_game/write_save encode the fixture.
	var snapshot: Dictionary = Game._save_tree()
	if int(snapshot.get("version", -1)) != 1 or snapshot.has("raid_state") or snapshot.has("__types"):
		return _fail("writer is not the pre-schema-2 v0.099 writer")
	snapshot = {}
	var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	if made != OK: return _fail("cannot create fixture directory: " + str(made))
	Game.SAVE_PATH = OUTPUT
	Game.save_game() # v0.099 returns void; verify its on-disk output below.
	Game.wait_save()
	if not _budget("native save write"): return 1
	var written = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT))
	if not (written is Dictionary): return _fail("native writer did not produce a JSON object")
	if int(written.get("version", -1)) != 1 or written.has("__types") or written.has("raid_state"):
		return _fail("output is not the original schema-1 format")
	if int(written.get("gold", -1)) != Game.gold or float(written.get("day", -1.0)) != Game.day:
		return _fail("written purse/day differ from the played campaign")
	if (written.get("company", []) as Array).size() != Game.company.size():
		return _fail("written company differs from the native muster")
	print("v0.099 fixture source=%s sha256=%s day=%s gold=%d company=%d towns=%d families=%d dragons=%d elapsed_ms=%d output=%s" % [
		SOURCE_COMMIT, FileAccess.get_sha256(OUTPUT), str(Game.day), Game.gold, Game.company.size(),
		towns.size(), families, dragons, Time.get_ticks_msec() - started, ProjectSettings.globalize_path(OUTPUT)])
	return 0

func run(tree: SceneTree) -> int:
	started = Time.get_ticks_msec()
	# Keep asynchronous autosaves from capturing setup while the sliced native APIs yield.
	Game.wait_save()
	var was_processing: bool = Game.is_processing()
	Game.set_process(false)
	var result: int = await _generate(tree)
	Game.set_process(was_processing)
	return result
