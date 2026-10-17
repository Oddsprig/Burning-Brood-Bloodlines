extends Node
## Headless test runner. Autoloads (DB, Game) are only visible to scripts compiled after they
## load, so tests run as a scene rather than with -s:
##   tools/test.sh tests/test_core.gd
## A test script extends RefCounted and has `func run(tree: SceneTree) -> int` returning the
## number of failures (it may await). Exit code = failures (capped at 125).
## A script that fails to compile, or a run that dies on a runtime error, would otherwise leave Godot
## running forever: a watchdog quits with 124 after --watchdog=<seconds> (default 280).

func _ready() -> void:
	# Per-process files: test runs in parallel worktrees share user:// and must not clobber each other.
	Game.SAVE_PATH = "user://test_save_%d.json" % OS.get_process_id()
	Game.SETTINGS_PATH = "user://test_settings_%d.json" % OS.get_process_id()
	Game.load_settings()
	var path := ""
	var watchdog := 280.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--test="):
			path = a.substr(7)
		elif a.begins_with("--watchdog="):
			watchdog = float(a.substr(11))
	get_tree().create_timer(watchdog, true, false, true).timeout.connect(func():
		printerr("runner: WATCHDOG - test did not finish in %d s (compile or runtime error?)" % int(watchdog))
		get_tree().quit(124))
	if path == "":
		printerr("runner: pass -- --test=res://tests/<file>.gd")
		get_tree().quit(2)
		return
	if not path.begins_with("res://"):
		path = "res://" + path
	var script = load(path)
	if script == null or not (script is GDScript) or not script.can_instantiate():
		printerr("runner: cannot load or compile ", path)
		get_tree().quit(3)
		return
	var t = script.new()
	if t == null or not t.has_method("run"):
		printerr("runner: ", path, " has no run(tree)")
		get_tree().quit(3)
		return
	var fails = await t.run(get_tree())
	if typeof(fails) != TYPE_INT:
		printerr("runner: invalid test result (runtime error or missing failure count)")
		get_tree().quit(3)
		return
	print("== %s: %s ==" % [path, "PASS" if int(fails) == 0 else "FAIL (%d)" % int(fails)])
	for p in [Game.SAVE_PATH, Game.SETTINGS_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	get_tree().quit(mini(int(fails), 125))
