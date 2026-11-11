# v0.030 real-save checkpoint script — report (Muse worker)

## What was written and where

Writing into the scope folder was refused (`absolute path is outside the workspace`), so the
script is in my own working folder under the same relative path and must be copied into the
v0.030 game folder before running:

- Script (as written): `C:\Users\bligh\.bridge\stage\muse-muse-14-i7tbxvyu\tools\make_v030_checkpoint.gd`
- Script (where it must live to run): `C:\Users\bligh\Documents\Codex\2026-09-22\referenced-chatgpt-conversation-this-is-an-3\outputs\LegionaryAI\.work\bb-v030-save\game\tools\make_v030_checkpoint.gd` (new `tools\` folder; no v0.030 code changed)
- This report: `C:\Users\bligh\.bridge\stage\muse-muse-14-i7tbxvyu\test-results\v0.100\muse_v030_checkpoint.md`
- Fixture the script will write when run: `<game>\tests\fixtures\harvest_legacy_v030_save.json` (folder created by the script)

Godot was NOT run (as instructed). `.work\bb-v059` untouched.

## Exact command (PowerShell, one line)

```powershell
& "C:/Users/bligh/Android/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "C:/Users/bligh/Documents/Codex/2026-09-22/referenced-chatgpt-conversation-this-is-an-3/outputs/LegionaryAI/.work/bb-v030-save/game" "res://tests/runner.tscn" -- --test=res://tools/make_v030_checkpoint.gd --watchdog=170
```

Exit code 0 = fixture written and verified (the runner exits with the failure count).

Test rules (pasted word for word): run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.
A test failure stops all further tests. No other test runs until that one failing test is fixed and passes.

## Days advanced

- Presim ("the years before"): **120 days** = 1 year (`CampaignWorld.PRESIM_YEARS_MIN`; 4 seasons × `Calendar.DAYS_PER_SEASON` 30), world size `normal`.
- Real company days after presim: **2.05 days** in 0.05-day resting steps, ending just past a midnight.
- Saved `day` ≈ **122.05**. Total game days advanced: **122.05**.

## How it works (all through v0.030's own code, nothing hand-built)

1. Mirrors `ui/newgame.gd _begin()`: sets `WorldGen.gen_size`, `CampaignWorld.presim_years`, calls `Game.new_game(2026)` (fixed seed for a reproducible fixture; only the title screen leaves the seed random).
2. Mirrors `ui/presim.gd`: `CampaignWorld.presim_step(Game, 1)` until `presim_left() == 0`, then `presim_finish(Game, wall_ms)`.
3. `Game.advance_time(0.05, true)` for 2.05 days (wages, food, healing, world sim; `in_town=true` so no off-screen travel or contact fight).
4. `Game.save_game()` (synchronous — same `_save_tree()`/file as the game's async autosave, but the bytes exist before the copy).
5. Copies the save file's exact bytes (`FileAccess.get_file_as_bytes` → `store_buffer`) to `res://tests/fixtures/harvest_legacy_v030_save.json`, then verifies: byte-identical copy, JSON parses, has `world`/`day`/`gold`, day/gold match the live game, saved pending-work count matches the live queue. Any failure returns non-zero through the runner.

## Notes / evidence from the v0.030 source

- Why the runner: `tests/runner.gd` states autoloads (DB, Game) are only visible to scripts compiled after they load, so tests run as a scene (`tests/runner.tscn`), not with `-s`. The script therefore follows the test contract (`extends RefCounted`, `run(tree) -> int`, like `tests/test_core.gd`) but lives at the requested `tools/` path — the runner loads any `res://` path. The runner redirects `Game.SAVE_PATH` to `user://test_save_<pid>.json` and deletes it after `run()` returns, so the copy happens inside `run()`; the player's real save is never touched (script also self-guards if ever run without the runner).
- Why not the game defaults: default new campaign is size `large` + 5 presim years (`WorldGen.WORLD_SIZE`, `CampaignWorld.PRESIM_YEARS`) = 600 days × 249 ms/day (`WorldGen.SIZES` measured `ms_day`) ≈ 150 s plus world-gen and save — not well under 3 minutes. `normal` + 1 year are both real player options on the New Campaign screen: 120 days × 89 ms ≈ 11 s of presim; total run expected well under a minute. `--watchdog=170` keeps even a hung run inside the 3-minute rule (runner default is 280 s).
- Why the extra 2.05 days: presim steps are 1.0-day `on_time` calls, and `on_time` with `days >= 0.25` drains the entire `world.work` queue (`campaign/world.gd`), so a save taken at `presim_finish` would have no pending work. Steps under 0.25 day drain only ~`days × queue` jobs per call, so stopping just after a midnight (when `_daily` queues the day's town/army/monster/sickness/herd jobs) leaves genuine pending work plus 2 days of paid wages and eaten food in the save. The script asserts `world.work` is non-empty and gold has dropped below the 600-coin start, so a drained or untouched state fails loudly instead of producing a dud fixture.
- Not verified by execution (Godot was not run, per instructions; shell was also unavailable in this session). The script's own checks make the first real run self-verifying: exit 0 only if the fixture is a byte-identical copy of a real `save_game()` file with matching day/gold and non-empty pending work.
