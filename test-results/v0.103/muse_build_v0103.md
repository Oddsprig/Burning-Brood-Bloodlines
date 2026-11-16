# v0.103 Guided tutorial system — Muse build log

Status: complete (built, statically checked, NOT run — per task)

Note: the scope folder (.work/bb-v103) is read-only for this worker's file
tools, so all files are written in the worker's own work folder with the same
relative paths for the lead to merge. Reads of the real tree were done by
absolute path.

## Checklist
- [x] Read RELEASE_PLAN v0.103 section + 2-3 existing ui/*.gd, game.gd, settings.gd, blocks.json, a recent test
  - Read: RELEASE_PLAN lines 73-91; ui/settings.gd, ui/kit.gd, ui/guide_view.gd; core/game.gd (screens, save/load, settings); core/save_snapshot.gd head; campaign/contracts.gd head; tests/runner.gd, tests/blocks.json, tests/test_touch_ui_v072.gd; campaign/world.gd after_load (empty world returns early, so bare save/load in tests is safe).
  - Real data folder is game/data/ (armor.json, factions.json, ...). No existing Tutorial/TutorialOverlay symbols.
  - Design: progress fields Game.tutorial_step / Game.tutorial_done, written by _save_tree and the async capture finish (both in game.gd, so save_snapshot.gd is untouched), read in load_game with d.get defaults so old saves load.
- [x] game/data/tutorial.json (steps as data)
- [x] game/campaign/tutorial.gd (engine: load, step state, done-when, progress)
- [x] game/ui/tutorial_overlay.gd (dim+cutout, arrow, text box, Next/Back/Skip, mouse+touch)
- [x] game/core/game.gd (tutorial progress fields, optional on load) — delivered as game/core/game_v0103.patch (see Report)
- [x] game/ui/settings.gd (Replay tutorial)
- [x] game/tests/test_tutorial_v103.gd + blocks.json registration
- [x] Static checks (symbols/signatures, no parse risks); NO Godot run per task

## Report

**Place:** the scope folder is read-only for this worker's file tools, so every
file below is in the worker's work folder at the same relative path; the lead
merges them into bb-v103. Nothing was written into bb-v103.

**What was built**
- `game/data/tutorial.json` — steps as data: `{id, anchor, text, done}` with done
  kinds `next` / `button` / `screen` / `state` (done may be a plain string).
  Ships a 3-step sample anchored on the Settings screen (`ReplayTutorial`,
  `Toggle_battle_event_slowmo`) so Replay works today; v0.104 replaces the
  content and adds anchors on campaign screens.
- `game/campaign/tutorial.gd` (`class_name Tutorial`, RefCounted, no UI) —
  `load_steps()` / `validate_steps()`, `setup/start/replay/start_saved`,
  `next_step/back_step/skip`, `notify_button/notify_screen/notify_state`.
  Action steps auto-advance on their action; Next only advances `next` steps.
  Progress mirrors onto the bound game (`bind_game`).
- `game/ui/tutorial_overlay.gd` (`class_name TutorialOverlay`) — the dim is
  four blocker rects around the cut-out (`show_behind_parent` so the drawn
  arrow/border stay visible over the dim), so the highlighted control receives
  real mouse input and touch (touch works through the project's
  `emulate_mouse_from_touch`, confirmed on by test_touch_ui_v072). Text box
  (UiKit panel) with counter, Back, Next/Done, Skip tutorial; box is placed
  below/above the cut-out and clamped to the screen at any size. Anchors
  resolve by node path, control name, or `tutorial_anchor` meta, re-checked
  every 0.12 s so screen changes are followed. Button steps wire the real
  button's `pressed`; screen steps listen to `Game.screen_changed`; state
  steps poll a host `state_of` callable. Public `highlight_rect()`,
  `current_target()`, `blocker_rects()` for tests.
- `game/ui/settings.gd` — full file, original content plus a Tutorial section:
  "Replay tutorial" button (node name `ReplayTutorial`) that loads the steps,
  binds progress to Game, restarts at step 1, and opens the overlay over
  Settings. One overlay at a time.
- `game/core/game_v0103.patch` — game.gd is 1345 lines; a retyped full file
  could corrupt unrelated lines, so the five small hunks are delivered as a
  patch (apply with git apply from the `---` line, or by hand; hunk context is
  verbatim). Adds `tutorial_step` / `tutorial_done`, resets them in
  `new_game_begin`, writes `"tutorial"` in both `_save_tree()` and
  `_finish_capture()` (so `save_snapshot.gd` needs no change), and reads it in
  `load_game()` via `d.get("tutorial", {})` — old saves load with defaults.
  **Merge order matters:** the test and settings screen reference
  `Game.tutorial_step`, so apply this patch before running anything.
- `game/tests/test_tutorial_v103.gd` + block `tutorial_v103` in
  `game/tests/blocks.json` (full file, new block at top after `_note`) —
  3-step sample (button, screen, state) over plain buttons in a resizable
  SubViewport: highlight encloses/centres the right control and no dim rect
  covers it at 1280×720, 1920×1080 and phone landscape 2340×1080; each step
  waits (Next disabled/refused, wrong screen ignored, state not reached);
  Back, Skip, Replay; save/load round-trip plus an old save with the field
  erased; Settings replay opens and Skip closes the overlay. No world is
  generated, so it should run in seconds, far under 3 minutes headless.

**Static checks done (no Godot or test was run, per task)**
- Every referenced symbol verified in the real tree: UiKit (`label, button,
  hbox, vbox, panel, scroll, spacer, clear, wrap, diagnostics_lane,
  apply_safe_area`), UiTheme (`get_theme, WOOD, MOBILE_FONT_SIZE, px,
  is_mobile`), Game (`SETTING_LABELS/CHOICES, setting, set_setting,
  screen_params, screen_changed, goto, save_game, wait_save, load_game,
  _save_tree, _write_save, SAVE_PATH`), settings.tscn path, runner contract
  (`extends RefCounted`, `run(tree) -> int`, per-process SAVE_PATH).
  No pre-existing `Tutorial`/`TutorialOverlay`/`tutorial` symbols.
- Parse-risk pass: tab-only indentation (searched: no leading-space indents);
  no `:=` on Variant values (all are literals/constructors/typed returns);
  no `x as int - y`; no typed-array assignments from untyped sources;
  `String()/int()/bool()` conversions on dictionary reads; loads cast
  `as Script`; settings.gd reproduced from the original with only the marked
  additions.
- Self-found bug fixed during review: the arrow would have been drawn under
  the dim children — blockers now use `show_behind_parent`.

**Not done / for the lead**
- Apply `game_v0103.patch`, copy the other files over, then let Godot import
  once (new `class_name`s) before the test run.
- Run the test (one at a time, headless): "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief." "A test failure stops all further tests. No other test runs until that one failing test is fixed and passes."
  Command: `godot --headless --path game res://tests/runner.tscn -- --block=tutorial_v103`
- Known soft spot to eyeball in screenshots: the shipped sample's second
  anchor sits inside the Settings scroll list, so check the cut-out placement
  there; v0.104's real chapter anchors are out of scope here.
- PROJECT_MAP.md / CHANGES.txt / DEV_NOTES updates were not requested in this
  task and were left to the merge step.
