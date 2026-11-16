# v0.103: Tutorial test repair

Status: repair complete; static verification complete; Godot/runtime verification NOT RUN.

Created this report first with "in progress", then updated findings and the completed repair. Changes are confined to bb-v103. No Git commands or game tests were run.

## v0.103: Failure evidence and UI pattern

Read the explicitly supplied bb-v097/test-results/v0.100/runs/v103_test_tutorial_v103.log. The first failure is the immediate `tree.root.add_child(viewport)` at original test line 135, invoked synchronously from `runner._ready()` while the root is setting up children. The fixture stays detached: the overlay never builds its controls, `_box` / Next dereferences crash, and `push_input()` rejects the detached viewport. Missing imported music is unrelated and was left alone.

`test_touch_scroll_v083.gd` waits for a process frame before fixture attachment and two more before input. `test_screens_v098.gd` and `test_ui_screens.gd` likewise wait before root attachment / UI use. Other UI tests use `tree.root.add_child.call_deferred(...)` for the runner's initial ready stack.

## v0.103: Completed changes

- `game/tests/test_tutorial_v103.gd`: defer both root SubViewport attachments, await two frames, and require tree membership / readiness before use. Existing overlay waits remain three/four frames; Settings resume waits six. Guard all overlay instances, required controls, navigation button types, text-box geometry, resolved highlight targets, input viewports and the Settings scene load. Guard direct property reads on Next, phone Skip and the resumed tutorial. Use diagnostic lookups for explanatory/replayed/mobile/navigation controls and the replacement screen's NextScreen button. Setup failures release owned fixtures, restore tutorial/theme globals, and return the accumulated failure count.
- `game/ui/tutorial_overlay.gd`: defer host attachment in the shared `open(host: Control, p_tutorial) -> TutorialOverlay` factory. The returned overlay can be configured immediately; its children require readiness. Its own `_ready()` only adds children to itself or newly created containers, never to its parent; those immediate internal additions remain intact.
- `game/ui/settings.gd`: retain the pending overlay reference so repeated Replay actions cannot queue duplicate overlays before deferred attachment completes.

## v0.103: Coordinator checks

Production audit: `Game.goto()` calls `main.show_screen()` and emits `screen_changed`; main attaches its current screen. Settings `_ready()` can resume a tutorial via `_open_tutorial(false)` and the same overlay factory used by the test. The shared factory fix therefore also covers the real game, including Settings resume during startup. Game/main need no screen-switch rewrite. `campaign/tutorial.gd` is RefCounted and performs no node attachment.

Missing prerequisites cannot silently pass: `_in_tree()` explicitly calls `check(false, ...)` for missing/freed/not-ready nodes; `_button()` also fails an absent or wrong-type button. Lookup/layout/input guards therefore record failures before stopping dependent work. Active Settings overlay lookups preserve their exact child paths and explicitly fail if absent. Expected absence after completion/Skip remains an assertion. A nil destination cannot pass by comparing equal to a nil highlighted target.

## v0.103: Static verification results

- Compared the edited test with its captured pre-edit contents without Git: all **74 original assertion sites** and message multiplicities remain; **78 sites** now exist. Four added sites cover diagnostic failures and scene loading. Five existing conditions gained null/type protection; no geometry limits, state/action expectations, input paths or behavioral assertions were removed.
- Source-only scans confirm balanced delimiters / strings, tab indentation, no conflict markers, two deferred root attachments, one `find_child()` site confined to the guarded helper, and no unchecked `get_node()` calls. Failure counting remains `fails += 1`, never reset by a guard.
- Checked helper declarations and argument counts; Tutorial setup/bind/start/replay/resume/notify APIs; overlay geometry APIs; Game save/load/writer/progress APIs; UiTheme override; and the Control/Button/PackedScene casts. Native tree/readiness, lookup and deferred-add APIs match the project's existing usage. Manual review found no introduced GDScript parse hazards or unchecked required-node property accesses.
- No Godot executable, engine parser, GPU job or game test was started. These are static results, **not a runtime pass**. The controller must rerun the originally failing tutorial test before any other game test; the failure hold is not lifted by this report.

Testing rules (verbatim):

> "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."

> "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."

Files changed: game/tests/test_tutorial_v103.gd; game/ui/tutorial_overlay.gd; game/ui/settings.gd; test-results/v0.103/sol_fix_tutorial_test.md.
