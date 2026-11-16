# v0.100 targeted test list (owner's rule, Nov 15 2026 ~10:55 PM Eastern)

The owner stopped the full 1,156-row run. v0.100 now tests only what it changed; one full run is kept for just before the store launch.
The 412-row and 316-row rerun lists are dropped.
Row numbers are tb_driver rows in runs/driver_list_v100_d.txt.

## Still to pass (fixes in progress)
- 443 test_sim_perf, 444 test_sim_perf_creatures: battle worst-step fix (Sol r6). Outcomes stay identical and the limits stay as they are. Run 443 three times on a quiet PC, then run 444.
- 520, 522, 526 test_weekly_hiring reverse parts: the checks pass but each part is over the 45 s body limit. Fix: weekly speed fix r3, which is in review.
- 446-510 test_startup_slices chain: day parts are over the 45 s body limit. Rerun on the final code in a fresh chain folder.

## Battle code changed in v0.100 (game/sim/*, game/battle/battle.gd): rerun after the battle fix lands
- 19 battle_screen, 27 battle_result_summary_v014, 30 bows_econ, 72 gore_render_v016, 73 gore_text, 96 horse_regressions_v056, 116 mounted_rider_art
- 138 sim_armor, 139 sim_batch, 140 sim_determinism, 141 sim_duel
- 602 campaign_contracts battle part, 609-612 dragon_combat_ui_v022, 834-839 food_battle parts
- 368-441 sim_harness_open chain (fresh speed-root folder)

## Weekly-hiring fixture (r1, r2, r3)
- All 18 parts in rows 519-554 rerun once on the final fixture.

## Already passed and not touched since
Every other row up to 539 passed on this code, and the later fixes don't touch them.

## Count
199 rows of 1,156: 443 and 444 (2), weekly hiring 519-554 (36), startup chain 446-510 (65), sim_harness_open 368-441 (74), and other battle tests (22).
Row 443 runs 3 times, so there are 201 test runs in total.
