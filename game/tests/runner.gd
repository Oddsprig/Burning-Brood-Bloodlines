extends Node
## Test runner. Autoloads (DB, Game) are only visible to scripts compiled after they
## load, so tests run as a scene rather than with -s:
##   godot --path game res://tests/runner.tscn -- --test=res://tests/<file>.gd
## A test script extends RefCounted and has `func run(tree: SceneTree) -> int` returning the
## number of failures (it may await). Exit code = failures + runtime script errors (capped at 125).
## A runtime script error aborts the function it happens in and the awaited run() still returns 0,
## so every "SCRIPT ERROR" logged during a test is counted as one of its failures.
## Test blocks (user rule 2026-10-17: fewer game restarts): several tests run one after another in ONE process,
##   -- --tests=res://tests/a.gd,res://tests/b.gd     or     -- --block=<name>   (tests/blocks.json lists blocks)
## Between tests the runner frees what the last test added to the scene tree and resets the shared state tests
## change (reset_between), so each test starts as it would in a fresh process apart from the engine start. Each test
## gets its own watchdog (--watchdog=<seconds>, default 180: the test time budget is under 1 minute, 3 at most);
## a test that hangs stops the whole run with 124.

## Counts the errors Godot logs as script errors (runtime errors such as "Invalid access to property
## or key"). Errors can be logged from any thread.
class ScriptErrorCounter extends Logger:
	var count := 0
	var _lock := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			_lock.lock()
			count += 1
			_lock.unlock()

	func total() -> int:
		_lock.lock()
		var n := count
		_lock.unlock()
		return n

const BLOCKS := "res://tests/blocks.json"

var script_errors := ScriptErrorCounter.new()
var current := -1   # the test now running (its watchdog fires only while it still runs)

func _ready() -> void:
	OS.add_logger(script_errors)
	var paths: Array = []
	var watchdog := 180.0
	var block := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			paths.append(a.substr(7))
		elif a.begins_with("--tests="):
			paths.append_array(Array(a.substr(8).split(",", false)))
		elif a.begins_with("--block="):
			block = a.substr(8)
		elif a.begins_with("--watchdog="):
			watchdog = float(a.substr(11))
	if block != "":
		var blocks = JSON.parse_string(FileAccess.get_file_as_string(BLOCKS))
		if not blocks is Dictionary or not (blocks as Dictionary).has(block):
			printerr("runner: no block '%s' in %s" % [block, BLOCKS])
			get_tree().quit(2)
			return
		paths.append_array(blocks[block])
	if paths.is_empty():
		printerr("runner: pass -- --test=res://tests/<file>.gd, --tests=a.gd,b.gd or --block=<name>")
		get_tree().quit(2)
		return
	var keep := get_tree().root.get_children()   # what the runner itself started with (autoloads, this node)
	var total := 0
	var results: Array = []
	for i in paths.size():
		var path := String(paths[i])
		if not path.begins_with("res://"): path = "res://" + path
		if i > 0: await reset_between(keep)
		current = i
		var deadline := get_tree().create_timer(watchdog, true, false, true)
		deadline.timeout.connect(func():
			if current == i:
				printerr("runner: WATCHDOG - %s did not finish in %d s (compile or runtime error?)" % [path, int(watchdog)])
				get_tree().quit(124))
		var started := Time.get_ticks_msec()
		var errors_before := script_errors.total()
		var fails := await _run_one(path)
		var errors := script_errors.total() - errors_before
		if errors > 0:
			printerr("runner: %d runtime script error(s) during %s (see SCRIPT ERROR above); each counts as a failure" % [errors, path])
		var n := (fails if fails >= 0 else 1) + errors
		total += n
		var seconds := float(Time.get_ticks_msec() - started) / 1000.0
		results.append("%s %s (%.0f s)" % [path.get_file(), "PASS" if n == 0 else "FAIL (%d)" % n, seconds])
		print("== %s: %s ==" % [path, "PASS" if n == 0 else "FAIL (%d)" % n])
	current = -1
	if paths.size() > 1:
		print("== block%s: %d tests, %d failing ==\n  %s" % [(" " + block) if block != "" else "", paths.size(),
			results.filter(func(r): return not String(r).contains("PASS")).size(), "\n  ".join(PackedStringArray(results))])
	for p in [Game.SAVE_PATH, Game.SETTINGS_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	get_tree().quit(mini(total, 125))

## Runs one test script; its failure count, or -1 when it could not run.
func _run_one(path: String) -> int:
	# Per-process files: test runs in parallel worktrees share user:// and must not clobber each other.
	Game.SAVE_PATH = "user://test_save_%d.json" % OS.get_process_id()
	Game.SETTINGS_PATH = "user://test_settings_%d.json" % OS.get_process_id()
	Game.load_settings()
	var script = load(path)
	if script == null or not (script is GDScript) or not script.can_instantiate():
		printerr("runner: cannot load or compile ", path)
		return -1
	var t = script.new()
	if t == null or not t.has_method("run"):
		printerr("runner: ", path, " has no run(tree)")
		return -1
	var fails = await t.run(get_tree())
	if typeof(fails) != TYPE_INT:
		printerr("runner: invalid test result from %s (runtime error or missing failure count)" % path)
		return -1
	return int(fails)

## Between two tests of one run: the last test's scenes leave the tree, its save finishes, and the shared state
## tests set is put back (a fresh process would start with these).
func reset_between(keep: Array) -> void:
	Game.wait_save()
	for n in get_tree().root.get_children():
		if not keep.has(n): n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	Engine.time_scale = 1.0
	Game.main = null
	Game.pending_battle = {}
	Game.screen_params = {}
	Sickness.deadliness = 1.0
	Sickness.new_world_deadliness = 1.0
	Sickness.prof_on = false; Sickness.prof_parts = false
	Monsters.new_world_creatures = true
	BattleRounds.round_size = BattleRounds.ROUND
	WorldGen.gen_size = WorldGen.WORLD_SIZE
	CampaignWorld.presim_span_days = CampaignWorld.PRESIM_DEFAULT_DAYS
	var root := get_tree().root
	root.position = Vector2i.ZERO

func _exit_tree() -> void:
	OS.remove_logger(script_errors)
