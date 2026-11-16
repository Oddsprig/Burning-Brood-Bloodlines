# v0.100 SALVAGE — targeted acceptance plan

Source candidate on main `0f36e00` (v0.099), written only in `bb-v100-salvage`.
Read-only sources: `bb-v097` older tests/evidence and `bb-v101` spouse-race review.
**Game/engine/GPU runs: 0. Runtime compilation, results, determinism and timing
acceptance are pending with the lead.** Static Python checks below did not launch
an engine, contact Test Bridge or write test results.

Before any work, read CLAUDE.md, AGENTS.md and docs/BUILD_RULES.md and follow them.

run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief.

> (1) one Godot test at a time on this PC, headless only, never open a game window; (2) before any test, check for running Godot or Unity processes from any project, and if any are running, queue and wait; (3) every test run must finish in under 3 minutes, so split anything longer into short runs.

Follow the [shared machine rules](C:/Users/bligh/Documents/Codex/GAME%20TESTING%20RULES.md)
and read-only process detector/shared lane. Test Bridge owns the lease; do not
take a nested lease or stop/control somebody else's editor, player or game.
Prepare imports in a separate authorized bounded headless lane job if the fresh
worktree needs them. This worker performed no import or engine parse.

## Blocks to run

**11 new blocks / 28 distinct test files.** Paths below are under `game/tests/`.
Every block is one headless process; target under 60 s, hard cap 180 s. New
blocks contain 2–3 files; no listed file requires a chain or `--part` invocation.

| Block | Files | Why |
|---|---|---|
| `battle_a` | `test_battle_screen.gd`, `test_battle_result_summary_v014.gd`, `test_gore_render_v016.gd`, `test_gore_text.gd`, `test_sim_armor.gd` | Exact source list: battle screen/results/gore/armour integration. |
| `battle_b` | `test_sim_batch.gd`, `test_sim_determinism.gd`, `test_sim_duel.gd`, `test_horse_regressions_v056.gd` | Exact source list: batch/determinism/duels/horse regressions. |
| `battle_c` | `test_bows_econ.gd`, `test_mounted_rider_art.gd` | Exact source list: bows/economy and mounted presentation. |
| `v100_hiring` | `test_hiring_paired.gd`, `test_hiring_timing_v046.gd` | Paired equality, Academy/name-cache/farm departures and current timing fixtures. |
| `v100_harvest` | `test_harvest_ownership.gd`, `test_harvest_lookup.gd` | Ownership, seasonal reserves and independent full bookkeeping comparisons. |
| `v100_food` | `test_household_food_v046.gd`, `test_harvest_lifecycle.gd` | Current meal rules and harvest lifecycle/payroll/save data. |
| `v100_records` | `test_records_performance.gd`, `test_records_paired.gd` | Idle/active Academy contracts and complete records presentation/native rows. |
| `v100_farms` | `test_farm_retention.gd`, `test_rotation_sizing.gd` | Seasonal retention and explicit race/crop sizing expectations. |
| `v100_anatomy` | `test_health_tissues.gd`, `test_sim_creatures.gd`, `test_combat_journal_v016.gd` | Throat report, sparse creature bodies, anatomy rolls and journal freeze/capture. |
| `v100_land` | `test_land_plots.gd`, `test_herd_totals_v043.gd` | Independent capacity/timing checks and herd ownership/count consistency. |
| `v100_world` | `test_house_onboarding_v019.gd`, `test_release_v099.gd` | Unchanged onboarding sentinel regression and release metadata checks. |

The three battle lists are exactly those in the source
`test-results/v0.100/runs/blocks_v100_a.txt`; they are registered as named blocks
here. Source WRAPUP reports 40/96/86 s for a/b/c. Those are **inherited source
measurements, not salvage passes**; b/c already exceed the target. Keep the
requested lists for initial acceptance, then split b/c if fresh runs exceed
60 s. No cap was enlarged and no timing assertion was relaxed. All other block
times are unmeasured on this candidate; split them too if necessary.

Run from the salvage root, after the lead has checked the shared lane:

```text
python test-results/v0.100/tools/run_blocks.py test-results/v0.100/runs/blocks_v100_salvage.txt --worktree bb-v100-salvage
```

The worktree folder is an argument on both tools (default
`bb-v100-salvage`); `--godot PATH` overrides the source's installed engine path.
The copied source tools depended on an absent `run_one_ref.sh` with bb-v097
paths. The port uses a direct headless `runner.tscn` command through Test Bridge,
with a 178 s whole-job cap and 170 s per-test watchdog. Logs/results stay in the
selected worktree. A pass requires terminal Test Bridge success, a PASS marker
for every requested test, and no FAIL/SCRIPT ERROR text. Queued, interrupted,
cancelled, killed and timed-out jobs are distinct from passes. Failed blocks
are recorded; the driver continues later planned blocks. Fix each failure and
rerun its block. The retired bulk feeder cannot run; `tb_driver.py` requires
`--single-row` and count 1 for a process-wide-argument exception only.

## Ports and reviewed scope

| Source | Application to main |
|---|---|
| `fix_land_plots_timing_r1.diff` | All nine game hunks match exactly. CLEAN: `review_argon_fix_land_plots_timing_r1.md`. Live ascending use searches, no persistent index. |
| `fix_land_plots_r2.diff` | Final CLEAN capacity oracle; one hunk exact, two hand-ported around main's original budget/no `_required_plots` helper. CLEAN: `review_argon_fix_land_plots_r2.md`. Rejected r1 is not applied. The 14-day daily timing window and 25 ms gate remain. |
| `fix_sim_perf_r1.diff` | Five hunks exact; hand-port only main's existing `nearest_enemy` from the combined archer hunk. Do not create the absent active/fallen-foe helpers. CLEAN: `review_sim_perf_r1_sol.md`. |
| `fix_sim_perf_r2.diff` | 27 hunks exact; hand-port `decide(sim: BattleSim, ...)` because main lacks the source's preceding fallen-foe helper. CLEAN: `review_sim_perf_r2_sol.md`. |
| `fix_sim_perf_r3.diff` | Ten hunks exact; hand-port entry/context handling and strike-end emission while keeping main's history policy and variant counters. CLEAN: `review_sim_perf_r3_sol.md`. |
| `fix_sim_perf_r5.diff` | 55 hunks exact; hand-port downs dispatch, ready-loop predicates and journal context around main's existing sync signatures. Skip the two absent fallen-foe helper hunks. CLEAN: `review_sim_perf_r5_sol.md`. **No r4 implementation is needed or imported.** |
| Older tests `1d64e6b` → `217011a` | All 67 selected game/test hunks across the eight commits apply exactly. Include the checkpoint data added in `ed97560`; no whole source tree or intervening unrelated test changes. |
| `807a3fd` | Copy CLAUDE.md and HOW TO TEST exactly, plus the three testing pointers. Hand-port fresh salvage docs/plan and make both tools self-contained/configurable. |
| Version metadata | Hand-update project/export versions and filename; main.gd already reads the project setting. Retained release test follows 0.100/code 100. |

Eight older-test commits selected:
`1d64e6b`, `ac8aa8e`, `ea84e46`, `2cae8a0`, `ccd7af4`, `6a0f095`,
`ed97560`, `217011a`. Reviews in bb-v097:
`sol_review_hiring_paired_1d64e6b.md`, the CLEAN review recorded in ac8aa8e,
`sol_review_who_cache.md` (closes the earlier NOT CLEAN cache finding),
`sol_review_health_tissues.md`, `muse_review_harvest_tests.md`,
`muse_review_v046_tests.md`, `muse_v030_checkpoint.md`, and the per-item CLEAN
source verdicts in `sol_review_six_pending_fixes.md`. That last review's
unrelated historical-PNG finding is not imported.

All thirteen repaired older test files in this range are included; none needs
the dropped day-job/perf/weekly-hiring code. Their three GDScript oracles and the
real checkpoint data are included. Tests fixed elsewhere that require excluded
game behavior are excluded, including `test_fixes_v100.gd` (optional fixes),
split-job/continuation/perf probes, weekly-hiring tests and startup-chain parts.
The one-launch-per-test plans/feeders are not carried.

## Small game fixes: include/skip ledger

| Commit/fix | Decision and reason |
|---|---|
| `ac8aa8e`: Academy reassignment | Include. The paired prefix-closure case needs retained named Academy jobs revalidated before the no-change return. |
| `2cae8a0`: hiring order/ranking | Include. The paired oracle needs exact per-worker farm departures and reference candidate ordering. These already apply to main's matcher; no weekly-hiring work is imported. |
| `2cae8a0`: business-name cache | Include. The paired continuation deliberately changes the household head on the same day before observing titles/job histories; CLEAN final review resolves the earlier cache-normalization finding. |
| `ea84e46`: throat report | Include. The repaired health test needs exact artery/airway wording and severity for the actual combined throat layer. No wound/damage resolver change. |
| `e2a26c6`: AI marriages | Skip. No imported fixed test depends on it. |
| `259580f`: unhorsed-rider knockdown | Skip. No imported fixed test depends on it. The unchanged battle regression keeps main's behavior. |
| `e2a26c6`/`a19911e`: fallen-foe archers | Skip. No imported fixed test depends on it. Optimize only the existing archer paths; do not add the optional helper/decision behavior. |
| `e2a26c6`: save_snapshot shrinking-list/key guard | Skip. Outside the selected salvage scope. |

The requested `fix_house_onboarding_type_r1.diff` guard is **inapplicable on
main**: `CampaignWorld.day_job_pending()`, `CampaignDayJob`,
`Sickness.prepare_frame_head()`, `CampaignTurnJob` and `CampaignRestJob`
are all absent. Its review marks the world hunk demonstrated and the others
defensive, but all require the excluded continuation stack. No world.gd,
sickness.gd or job-class code is imported to recreate those call sites.
The unchanged `test_house_onboarding_v019.gd` still checks its Dictionary work
sentinel against main's original save path.

The married-in spouse race fix stays in bb-v101. The reviewed implementation
adds optional person slot RACE and changes names, binding/remembered records,
fertility, aging, elder mortality, marriage transfer and dynasty identity/heirs.
It exceeds approximately 40 game-code lines across several files. The small-fix
condition is not met; do not cherry-pick just the wedding assignment and leave
the readers inconsistent. The v0.101 test review is also NOT CLEAN overall,
though it describes F5's game behavior as sound.

Explicitly excluded old-v0.100 work: day-job/rest-job/turn-job/herd-week/
sickness-day-job splitting, perf probes, frame gates, raid_save, stack diffs,
weekly-hiring r1–r4, startup chains, sim r4/r6 and the bulk single-test feeder.
No runner.gd or run_full_suite_headless.ps1 edits; no git mutation, signing-key
access, software change, app control, upload, game launch or GPU run.

## Static evidence and limits

- Base confirmed clean at `0f36e00` before edits; only the target is written.
- All 30 changed GDScripts were scanned against main's declaration inventory
  plus the locally declared port helpers: 4,400 resolvable project member
  references and 70 newly introduced bare calls, no unresolved entries.
  New cross-file helpers are `Plots._use_plot_ids`,
  `BattleDamage._cache_parts`, `Formulas.prepare_weighted`,
  `Formulas.roll_weighted_cached`, and `Formulas.edge_resistance_w`; each
  definition is included. Existing BattleSim/Fighter/BodyState/Unit and
  campaign interfaces remain main's; no missing r4 or split-job member is used.
- This is a lexical/source review, not an engine compiler or a proof of all
  dynamic Variant calls. Built-in/inherited Godot APIs retain their existing
  contracts; the lead must still check Godot compilation and exact runtime
  results. No save-schema, numeric-result, RNG or timing pass is inferred.
- Both Python files parse/compile in memory. Offline mocks verified the exact
  11 block arguments/default tree, five invalid folder names, both bulk-feeder
  rejection gates and 12 job outcomes (including queue/pass, script errors,
  incomplete/missing logs, interrupted, timed out, cancelled and refused).
  Engine launches, network requests and test-result writes in these checks: 0.
- All 28 planned paths exist, are distinct, and have no `--part`/chain
  requirement. Exact battle lists match the supplied plan. Existing block
  registrations are retained.
- The real checkpoint matches the source bytes apart from a final LF added by
  the file tool. Target SHA-256:
  `2fe74354af31d6402d24679480a201037997b1ebb8721b827b02fece76780db8`.
  No checkpoint generator or old game was run.
- The three-document gate is updated together; historical version entries stay
  intact. CLAUDE/HOW TO TEST and all three 807a3fd pointers are present.
  Final readback passed: exactly the 44 listed files, clean whitespace, no NUL,
  replacement characters or BOM added, protected sources unchanged, exact
  source instructions/pointers, and 0.100/100/0.100.0.0 metadata. The selected
  older game/test files equal their reviewed 217011a contents. These are static
  checks, not game-test passes.

## Files changed

44 files; paths are relative to the target. One entry per file.

| File | Change |
|---|---|
| `AGENTS.md` | Copy the HOW TO TEST section from 807a3fd above existing rules. |
| `CLAUDE.md` | Add the exact source HOW TO TEST entry point. |
| `docs/BUILD_RULES.md` | Add 807a3fd's testing pointer; keep the three-document merge gate. |
| `PROJECT_MAP.md` | Record v0.100 owners, scope, exclusions, entry points and pending acceptance. |
| `docs/DEV_NOTES.txt` | Record behavior, required dependencies, static evidence and runtime limits. |
| `CHANGES.txt` | Describe precisely the salvage candidate and dropped work. |
| `game/project.godot` | Set application version to 0.100. |
| `game/export_presets.cfg` | Set Android 0.100/code 100/v0100 filename and Windows 0.100.0.0. |
| `game/campaign/plots.gd` | Apply the CLEAN live-use search timing patch, preserving plot order. |
| `game/campaign/herds_views.gd` | Use the live pasture/home searches without changing assignments. |
| `game/campaign/families.gd` | Import only Academy validation and paired-hiring ordering/ranking repairs. |
| `game/campaign/businesses.gd` | Validate business-name cache against same-day head/name inputs. |
| `game/sim/battle_sim.gd` | Port r1/r2/r3/r5 setup, target, event and dispatch reductions to main. |
| `game/sim/battle_damage.gd` | Port anatomy weights and equivalent damage/function lookup reductions. |
| `game/sim/battle_morale.gd` | Port typed/direct calls, one-source queue handling and equivalent scans. |
| `game/sim/archery.gd` | Optimize main's standing-enemy helper and existing arrow paths only. |
| `game/sim/formulas.gd` | Preserve arithmetic/draw order with cached weights and edge inputs. |
| `game/sim/combat_journal.gd` | Reduce immutable-leaf validation overhead while retaining detachment. |
| `game/sim/natural_attacks.gd` | Cache intact-creature ordered lists and reuse the existing race definition. |
| `game/sim/learning.gd` | Cache immutable attribute-link pairs and avoid empty growth work. |
| `game/sim/health_report.gd` | Restore throat artery/airway wording and critical severity. |
| `game/tests/fixtures/businesses_v035_hiring.gd` | Keep the independent hiring oracle aligned to current funding rules. |
| `game/tests/fixtures/families_v035_hiring.gd` | Keep the independent oracle aligned to Academy/draught/labour rules. |
| `game/tests/fixtures/harvest_claims_v033.gd` | Apply the independently expressed seasonal food-window policy. |
| `game/tests/fixtures/harvest_legacy_v030_save.json` | Supply the real reviewed v0.030 checkpoint required by lifecycle coverage. |
| `game/tests/test_hiring_paired.gd` | Preserve exact town/continuation equality; add Academy/cache/departure cases. |
| `game/tests/test_health_tissues.gd` | Use sparse bodies and actual nerve marks with independent severity controls. |
| `game/tests/test_harvest_ownership.gd` | Correct reserve/payroll expectations and retain landless fallback coverage. |
| `game/tests/test_harvest_lookup.gd` | Compare against the updated independent harvest bookkeeping oracle. |
| `game/tests/test_harvest_lifecycle.gd` | Correct payroll/deferred-cash cases and load the real checkpoint. |
| `game/tests/test_household_food_v046.gd` | Give culture-free meal fixtures their explicit human race. |
| `game/tests/test_hiring_timing_v046.gd` | Build a real one-civilian household; preserve all seeds/checks. |
| `game/tests/test_records_performance.gd` | Distinguish idle honorary Academy heads from active paid posts. |
| `game/tests/test_records_paired.gd` | Use retained v0.043 presentation and still compare every v0.033 row. |
| `game/tests/test_farm_retention.gd` | Check the independent seasonal horizon and retained annual fallback. |
| `game/tests/test_rotation_sizing.gd` | Use native race keys and retain explicit crop/reserve goldens. |
| `game/tests/test_sim_creatures.gd` | Read the sparse anatomy plan without changing combat assertions. |
| `game/tests/test_land_plots.gd` | Hand-port final CLEAN r2 pre-layout capacity and negative controls. |
| `game/tests/test_release_v099.gd` | Keep release checks usable with 0.100/code 100 metadata. |
| `game/tests/blocks.json` | Register the exact battle lists plus eight small targeted blocks. |
| `test-results/v0.100/tools/run_blocks.py` | Read targeted block plans with configurable worktree and Test Bridge jobs. |
| `test-results/v0.100/tools/tb_driver.py` | Provide self-contained bounded submission; retain only explicit single-row mode. |
| `test-results/v0.100/runs/blocks_v100_salvage.txt` | List one NAME<TAB>--block=NAME line per targeted block. |
| `test-results/v0.100/targeted_tests_v100.md` | Own this fresh plan, per-file inventory, port decisions and static evidence. |

## Acceptance result

Acceptance (2026-11-16, PC, Test Bridge, one headless Godot launch per block):
11 blocks / 28 tests PASS: battle_a 5, battle_b 4, battle_c 2, v100_hiring 2,
v100_harvest 2, v100_food 2, v100_records 2, v100_farms 2, v100_anatomy 3,
v100_land 2, v100_world 2. Longest block v100_food ~70 s (harvest_lifecycle 68 s
alone), so it is now split into v100_food + v100_harvest_life. Lead fixes during
acceptance: battle_sim.gd declares capture_history (default on; sim r3 reads it;
results unchanged); test_gore_render_v016 headless oracle and test_gore_text
shield-arrow claim taken from the v0.100 branch; test_gore_text also accepts the
shield-boss line ("it shatters" = the missile). Receipt:
test-results/v0.100_salvage_receipt.txt.
