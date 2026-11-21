# v0.108 — Wyrmblood Crowns rename targeted test plan

Source candidate on `main` `74a300f` (branch `v0.108-on-main`).
**Game/engine runs by worker: 0.** Runtime execution, merge and headless exports are owned by the lead.

Before any work, read CLAUDE.md, AGENTS.md and docs/BUILD_RULES.md and follow them.

run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.

> (1) one Godot test at a time on this PC, headless only, never open a game window; (2) before any test, check for running Godot or Unity processes from any project, and if any are running, queue and wait; (3) every test run must finish in under 3 minutes, so split anything longer into short runs.

Follow the [shared game testing rules](C:/Users/bligh/Documents/Codex/GAME%20TESTING%20RULES.md).

## Changed game files in v0.108

- `game/project.godot` — `config/name="Wyrmblood Crowns"`, `config/version="0.108"` (`config/custom_user_dir_name` unchanged).
- `game/main.gd` — window title `"Wyrmblood Crowns (v%s)"`.
- `game/ui/title.gd` — title label `"WYRMBLOOD CROWNS"`, subtitle `"D R A G O N S   ·   D Y N A S T I E S"`, width-fitted font sizes via `UiTheme.px` + `Font.get_string_size` so 16-letter Cinzel display capitals fit desktop, landscape phone and narrow compact viewports.
- `game/export_presets.cfg` — Android `package/name="Wyrmblood Crowns"`, `version/code=108`, `version/name="0.108"`, `export_path="build/android/BurningBrood_Bloodlines_v0108.apk"`; Windows `application/product_name` and `application/file_description` = `"Wyrmblood Crowns"`, `file_version` and `product_version` = `"0.108.0.0"`.
- `game/tests/test_release_v099.gd` — shown-name check expects `"Wyrmblood Crowns"`.

No other player-visible occurrences of `"Nepo"`, `"Burning Brood"` or `"Bloodlines"` exist in `game/ui`, `game/core`, `game/campaign`, `game/data` or `game/main.gd` (comments, save dir, Android `package/unique_name`, build file names and `"bloodlines-dragons"` seed string kept unchanged).

## Blocks to run (`test-results/v0.108/runs/blocks_v108.txt`)

**2 blocks / 4 tests** (one headless Godot launch per block via `game/tests/runner.tscn`, target <60 s, hard cap 180 s):

| Block | Tests (`game/tests/`) | Why it covers v0.108 |
|---|---|---|
| `v100_world` | `test_house_onboarding_v019.gd`, `test_release_v099.gd` | `test_release_v099.gd` (`store_build()`) verifies `application/config/name == "Wyrmblood Crowns"`, unchanged `custom_user_dir_name`, `0.108` version format, `title.gd` and `main.gd` free of `"Claude Edition"`, Android `version/name` (`0.108`), `version/code` (`108`), `_v0108.apk` export path, and Windows `0.108.0.0` `file_version`/`product_version`. |
| `v107_title` | `test_ui_screens.gd`, `test_ui_fit.gd` | `test_ui_screens.gd` instances `res://ui/title.tscn` headless and checks for script/runtime errors; `test_ui_fit.gd` builds `res://ui/title.tscn` across all desktop (`1280x720`–`2560x1440`) and mobile landscape (`2424x1080`, `2400x1080` with `UiTheme` mobile sizing) viewports and verifies no `Control` overflows. |
