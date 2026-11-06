# v093 native engagement pilot — source delivery

Native runtime: **UNRUN by this worker**. The bounded question is whether the declared pilot can execute reproducibly through actual BattleRounds series while preserving bodies, rosters, custody and riders. The source supplies that measurement path; only the controller's exact-source contract, pilot and complete phase can establish that it works. There is no balance verdict, tuning, dragon price or fairness threshold.

## Declared manifest

Two fixed seeds: **93017, 100936**. Physical side 0 and physical side 1 are separate, freshly regenerated whole-battle trials. `manifest()` is deterministic and every checkpoint contains its complete 108-entry manifest and selected IDs.

| Family | Coordinates | Whole battles |
| --- | --- | ---: |
| Race | 7 `B.RACES` × human reference, same sword/spear/archer role × 2 seeds × 2 deployment sides | 84 |
| Dragon | original owned adult Ruby, native small/large profile × human spear prefixes 8/16/32 × 2 seeds × 2 sides | 24 |
| Total | limited two-seed pilot | **108** |

Race order is human, orc, goblin, moon_elf, dwarf, high_elf, dark_elf. Each race occupies 12 indices, in sword/spear/archer order; each role occupies four indices, seed then physical side. Race indices are 0–83. Dragon small indices are 84–95; large indices are 96–107, each in opponent-count/seed/side order. The 12 human mirror trials remain a separate summary, leaving 72 comparative race trials.

Candidate arms use unchanged `B.spec`, `B.candidates` and seeded native factories: participant A seed `trial_seed*3+1`, B seed `trial_seed*3+2`. Costs use unchanged `B.body_cost`: actual equipment, actual quiver at base goods prices, and seven-day ordinary retainer wage benchmark. Search first considers 9–16 prefixes; fallback considers 5–32. It never accepts a spend gap above 5% or an ordinary race army of four or fewer. Missing matches remain explicit, incomplete coverage. There is no fixed fabricated equal-cost replacement.

The dragon is the original actor admitted by `test_dragon_combat_v022.fixture`, not a copied dragon-shaped troop. Its registry size/growth coordinates are small/0 and large/2, followed by native `sync_profile`. Admission uses an actual participation preview and confirmed order. `battle_riders` supplies the registered civilian's actual detached battle body. The rider's initial real gear/quiver values and seven-day retainer wage **BENCHMARK** are recorded separately; the civilian was not hired and no wage payment is claimed. The dragon has no purchase budget. Actual opposing human spend is the only opponent-cost coordinate. Native daily food requirement, seven-day food units, and separate fresh_meat/meat base-price provisioning estimates are recorded; these are not elapsed or paid care.

## Native lifecycle and evidence

Each trial installs an isolated native register fixture and real Unit references, then calls `BattleRounds.begin`. Every engagement uses pending `round_side0`/`enemy`, `BattleScene.battle_opts`, native `battle_riders`, and a real `BattleSim`. `BattleTactics.setup_round` is invoked by native rounds; the driver applies its actual `tactic_mods` with `BattleTactics.apply_sim`. No tactical order is chosen by the survey: physical side 0 retains native default hold; the enemy retains native policy. Native side-dependent medics/commanders also remain in effect. Both fresh deployment directions measure these policies; they do not erase them.

The CPU adapter explicitly preloads `res://battle/battle.gd`, instantiates it outside the scene tree, and overrides only `_banner`. It calls inherited `_aftermath` for all 12 native steps, then native `build_result`, `after_round`, and `next_round` until native `over`. It finally records `battle_summary` and the native-serialized **entire final_result**, including its native round log and last-engagement fields. Combat journaling is explicitly disabled using the existing native CPU option; the actual final journal field is null. Full per-engagement result dictionaries, snapshots and hashes supply the measurement evidence. No campaign rewards, real saves, `Game.finish_battle`, care days or between-engagement re-admission are invoked.

Round size is **4**, restored after the harness. Ordinary pools never exceed 32 per side. Native selected-army opts use the native small 32×18 CPU grid, plains and seeded native dressing; the measured tick bound remains `B.MAX_TICKS=6000`. Units, bodies, equipment, quivers, rider-body dictionary and rider references survive the series. Snapshots include actual selected UIDs, original Unit/BodyState instance labels, body/gear/quiver hashes, fit/dead/captured state, custody, civilian riders, accumulated seats and downs. Assertions check selection eligibility, unchanged references, previous-after to next-before continuity, native log sequence and native seat/down merging. Deltas distinguish ordinary priced losses from unpriced dragon deaths and report rider injury/death separately.

Whole rows include initial actual counts/costs, normalized participant inputs/winner, native winner and termination, all engagement results, native cumulative casualties, final unique state, fit survivors and final settlement. Native casualty counters are reported as native counters; they can count repeat wounds and are not silently substituted for unique casualties. Unit and body instance IDs are strings to avoid JSON's numeric precision limit. Side-swap physical input hashes omit incidental Unit/Item UID and display-name labels. Rider input hashes instead key normalized rider payloads by actual person identity, excluding dynamic dragon Unit dictionary keys.

An early native break after one engagement is valid and separately listed. Complete mechanical coverage additionally requires at least two actual measured cases with two or more engagements, plus the separate real native carry-over control. The control is not part of 108: original Ruby plus nine ordinary subjects against nine ordinary enemies, a pre-battle wounded body/corpse fixture, native hold options, and actual two-tick capped engagements through native battle termination. The contract checks original actor/rider references, actual multi-engagement carry-over, native corpse/captive exclusion, honest capped draws and JSON-safe exact values allowing int/float representation changes. It never fabricates survey rows.

All tick-capped engagements are marked. Any whole battle influenced by a cap, or reaching native MAX_ROUNDS=20, is censored even when native rounds chooses a winner. The native decision is retained as evidence and excluded from resolved win/loss frontiers. Wall interruptions preserve an incomplete engagement without aftermath/after_round/final settlement. Trial state is never restarted or healed to hide interruption; the isolated fixture is released only when the invocation returns after writing its diagnostic evidence.

## Controller-only commands

These are the supplied existing runner's raw commands, shown from the **v093 directory**. The controller submits them through PinnedTest.py/TestBridge, which supplies its own engine/headless/Dummy/path prefix and isolated APPDATA/LOCALAPPDATA. This worker runs none of them and claims no test lane. Do not nest a lease or launch another engine. Watchdog is 55 seconds; internal phase budget is 45 seconds. No automatic retries.

```powershell
godot --headless --audio-driver Dummy --path game res://tests/runner.tscn -- --test=res://tests/test_engagement_contract_v093.gd --watchdog=55
godot --headless --audio-driver Dummy --path game res://tests/runner.tscn -- --test=res://tests/balance_engagements_v093.gd --watchdog=55 --engagement-phase=v093_pilot --engagement-shard=0/1 --engagement-trial=race_human_sword_93017_s0
```

Time the single trial before choosing a complete phase partition. The following concrete first-shard command uses the maximum one-trial-per-partition split; after timing, the controller may choose another common N in 1..108. Run **every** index `i=0..N-1` exactly once with the same N, phase and exact source. Physical side swaps belong to distinct indices. Remove the single-trial filter for the complete phase. A sample is not complete declared coverage.

```powershell
godot --headless --audio-driver Dummy --path game res://tests/runner.tscn -- --test=res://tests/balance_engagements_v093.gd --watchdog=55 --engagement-phase=v093_p1 --engagement-shard=0/108
```

Each invocation prints immutable checkpoint paths in task-owned `user://engagements_v093`. Files use phase, partition, time, PID, monotonic timestamp and sequence; existing files are refused. An initial checkpoint precedes combat, then checkpoints follow each engagement and trial/final status. A watchdog can leave the current file incomplete; earlier files are preserved. Supply the explicit final intact chosen checkpoint for each partition to the aggregator. It never searches directories, picks artifacts, repairs evidence or overwrites outputs. A prior phase/timing pilot cannot be blended into a later full phase. If a run is interrupted, diagnose its partial checkpoint and let the controller declare a fresh complete phase/partition; no automatic resume or retry exists.

Checkpoint metadata contains phase, exact manifest, partition/filter/selected IDs, statuses, source and data SHA-256 fingerprints, bounds and elapsed time. Source fingerprints include the explicit scene script and registered native dependency classes plus these test scripts; data fingerprints include B's authored-data hashes, loaded races/goods and dragon catalogs. They reject mixed packets; they are not a complete repository revision attestation. Root must also pin the exact tested source in TestBridge.

Only the following Python command was run by this worker:

```powershell
python game/tests/summarize_engagements_v093.py --self-test
```

It uses synthetic in-memory schema fixtures and has no native combat claims. It checks full/partial mechanical coverage and negative controls for missing/duplicate/mixed artifacts, broken rounds/references/continuity, false assertions, cap/draw mislabelling, side-swap drift and invented dragon pricing.

For actual evidence, replace the quoted paths with explicit printed artifact paths and include all N partition files, once each. The example with one shard applies only if the controller actually selected N=1 and completed that invocation:

```powershell
python game/tests/summarize_engagements_v093.py --phase=v093_p1 --contract "C:/task-results/contract_final.json" "C:/task-results/partition0_final.json"
python game/tests/summarize_engagements_v093.py --phase=v093_pilot --allow-incomplete "C:/task-results/pilot_final.json"
```

Default aggregation rejects missing native contract/coverage, duplicate checkpoints/trials, mixed phase/source/data/N/manifest, skipped rounds, wrong continuity, rebuilt bodies/riders, ineligible picks, native result inconsistencies and inaccurate censor labels. `--allow-incomplete` is an explicit diagnostic mode; missing/incomplete coverage cannot become a passing result. Complete coverage is reported separately from mechanical completeness and from the absence of a balance claim.

Summaries separate each race/role, human mirrors and dragon size. They retain native subject wins while distinguishing usable wins/losses from draws, censorship and incompleteness. Frontiers list actual opponent spend coordinates only. All-win, all-loss, draw/cap/incomplete and overlapping or reversed win/loss spends yield **UNRESOLVED**. An observed interval needs observed subject wins strictly below observed subject losses; it is a two-seed empirical interval, never a dragon shop price or a race fairness verdict. Ordinary packages can vary with seed/prefix matching, so their spend intervals are especially limited.

This pilot covers no exhaustive race pairs, native faction roster matrix, terrain matrix, campaign logistics or elapsed dragon care. No race, physics, production, price, version, roadmap or old standalone v093 draft is changed.
