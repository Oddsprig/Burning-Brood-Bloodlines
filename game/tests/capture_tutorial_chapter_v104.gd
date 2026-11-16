extends RefCounted
## v0.104: separate WINDOWED capture entry point; written for later review, NOT run by implementation.
## --test=res://tests/capture_tutorial_chapter_v104.gd --watchdog=120 --small-house
## v0.104: small-house default captures all 17 chapter steps, plus both customization screens, in test-results/v0.104/.
## Testing rules (verbatim): "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
## "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."
## The later windowed screenshots are the user's explicit exception to the headless brief above.

func run(tree: SceneTree) -> int:
	Game.reset_tutorial_progress() # v0.104: the capture entry point also owns its tutorial-state isolation.
	Game.settings["tutorial_chapter_requested"] = false
	if DisplayServer.get_name() == "headless":
		printerr("v0.104 capture: use the separate windowed run; no screenshots were made")
		return 1
	tree.root.set_flag(Window.FLAG_NO_FOCUS, true)
	var walkthrough = load("res://tests/test_tutorial_chapter_v104.gd").new()
	walkthrough.capture_dir = ProjectSettings.globalize_path("res://../test-results/v0.104")
	var result: int = await walkthrough.run(tree)
	Game.reset_tutorial_progress() # v0.104: preserve the same clean exit for capture success and assertion failures.
	Game.settings["tutorial_chapter_requested"] = false
	return result
