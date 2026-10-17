# Burning Brood: Bloodlines (Claude Edition) - cloud handoff

Current version: **v0.034** (in-game label `0.034-claude`, game/project.godot `config/version`).
This repository started as a single snapshot of v0.032; v0.033 and v0.034 were built in the cloud on top of it,
each on its own branch (`claude/v0.033-prisoner-ransom`, `claude/v0.034-migration-housing-illness`, stacked).
The full local history before v0.032 stays on the user's PC.

## Branches
- `main` holds the latest verified version (user rule: fast-forward and push `main` when a version's checks pass).
  Work happens on a branch per version, stacked, then `main` moves up to it.

## Version numbering (follow exactly)
- The roadmap is `docs/ROADMAP.txt`. One feature per version, steps of 0.001 (v0.033, v0.034, ...).
- No 1.x or other labels. Never change a version number or the in-game label unless the user says so.
- When a version is done and its tests pass: commit it and set `config/version` to `0.0NN-claude`.

## What each Claude Edition version added
- v0.023 mounted character: bonded riders fight on their dragons (seated drawing to be confirmed).
- v0.024 breath, v0.025 dragons march with the army (feed from the army purse), v0.026 raid, v0.027 siege.
- v0.028 fear of dragons: dragon battles frighten towns; frightened, disloyal towns defect to the dragon realm.
- v0.029 levies get armour; Refit army action.
- v0.030 dynasty alliances and diplomacy: marriage ties lift standing; alliance, non-aggression pact, break alliance; allies join wars.
- v0.031 army markers (realm-coloured headcount badges, march lines), army card (commander, troops, objective), objectives, travel 35% slower and slower for big armies.
- v0.032 intrigue: assassinate, sway, fabricate claim; AI houses plot against the player.
- v0.033 prisoner ransom and exchange (campaign/prisoners.gd, Court -> Prisoners): ransom, release, pay ransom,
  exchange one for one; battles of every size take prisoners; held prisoners no longer die in the weekly sweep.
  Details and known limits: DEV_NOTES_CLAUDE_EDITION.txt, section V0.033.
- v0.034 population migration, housing and illness: the common folk (cohort rows, most of the population) fall sick
  at the register's per-person rates and buy remedies; their households leave towns under war, famine or crowding
  (campaign/migration.gd); Population screen card; outbreak and migration log lines. Section V0.034 of the dev notes.
- Also built outside the numbered list: court and marriage, interface pass, 100 v 100 battle rounds, armies to 1000, house-only officers and noble call-up, house arms pool, ennoblement, medics and battle aftermath.

## Next, in order (not started)
0. Main checks are inside the test time budget (done 2026-10-17 with DevTools): eleven under a minute, `claude_rounds` 97 s
   (one real 100 v 100 round). New checks start from `DevTools.start_world` and set states up with DevTools.
1. **v0.035 creature review** - next job (creatures are switched off by `Monsters.CAMPAIGN_CREATURES_ENABLED`).
2. v0.036 dragon portrait fangs.

## Running and testing
- **Every test uses the smallest world (Normal) with a one-day world history** (user direction 2026-10-17). These are
  also the game's defaults: `WorldGen.WORLD_SIZE = "normal"`, `CampaignWorld.PRESIM_DEFAULT_DAYS = 1`. Don't spend time
  on bigger worlds or longer histories unless asked.
- Godot **4.7.2** (stable), GL compatibility renderer. The Windows runtime is not in this repo; get Godot 4.7.2 for your platform.
- Import once: `godot --headless --path game --import`
- **Test time budget (user rule): every test run aims for under 1 minute and must finish within 3 minutes**, unless the user asks
  otherwise. Design tests to fit: load saved-game fixtures for later-game states, use small worlds and the fewest days and battles
  that prove the change, and run only the tests the change touches. Never run long multi-test passes. The runner's default
  watchdog is 180 s; do not raise it to make a slow test pass, cut the test down. Start tests with
  `DevTools.start_world` (campaign/dev_tools.gd: the saved small world, made once and loaded in seconds) and set
  later-game states up with DevTools instead of simulating days or fighting big battles.
- Run a test: `godot --path game --rendering-method gl_compatibility res://tests/runner.tscn -- --test=res://tests/<file>.gd`
  (add `--headless` where no display is available; screenshot tests need a display).
- Main checks: `claude_campaign.gd`, `claude_rounds.gd`, `claude_marriage.gd`, `claude_diplomacy_v030.gd`, `claude_markers_v031.gd`, `claude_intrigue_v032.gd`, `claude_prisoners_v033.gd`, `claude_prisoners_ui_v033.gd`, `claude_population_v034.gd`, `claude_population_ui_v034.gd`, `claude_refit.gd`, `claude_dragonfear.gd`.
- Population balance: `tests/diag_population_v034.gd --days=N` prints people, sickness cases/deaths, moves and job timings (a diagnostic, not a pass/fail check; run it only when needed).
- In a Linux cloud container: download the Godot 4.7.2 Linux build and run display tests with `xvfb-run -a -s "-screen 0 1920x1080x24"`
  (main.tscn tests wait for drawn frames and hang under `--headless`). `claude_intrigue_v032.gd`, `claude_prisoners_v033.gd`, `claude_population_v034.gd` run headless.
- `tests/runner.gd` counts every runtime script error (a `SCRIPT ERROR` line in the log) as a failure, so a test that dies on one prints `FAIL (n)` and exits non-zero.
  The aborted `run()` loses its own failure count, so read the log for the cause. (Up to v0.034 the runner printed PASS on script errors and logs were searched by hand.)
- Results for each version go in `test-results/` (v0.033 and v0.034: `test-results/v0.03N_2026-10-17_results.txt`).
- Known older failures that predate this work: `test_econ_army.gd` draft-pool checks, phone-size layout checks in `test_dynasty_ui.gd`.

## Helpers
The BigBridge / LegionaryAI helpers (Sol, Grok, Argon, Muse via `run_agent`) run only on the user's PC. A cloud session will not have `run_agent`; do the work directly.
