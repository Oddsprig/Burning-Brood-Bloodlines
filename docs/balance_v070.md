# v0.070 part A: measured balance

Measurements and tuning for the shipped humanoid roster and horses, from
branch `v0.070a` based on `64c633d`.

## Method

`game/tests/balance_v070.gd` uses the production `BattleSim`, `Factory`,
`MountedCombat`, `Item.value()`, and the existing `sim_util.gd` kits. It does
not replace combat with a power formula. Every trial constructs fresh units,
equipment, quivers and horse bodies. Attributes, body sizes, personalities,
native troop loadouts, and native gear quality/material rolls are seeded.
Each matchup is repeated with the same generated armies on opposite sides.

The active races are human, orc, goblin, moon elf and dwarf. The race survey
crosses every race pair in sword, spear and archer roles. The role survey
crosses every role pair within each race. The mount survey compares foot
and horse versions of every race/role and includes mounted mirrors. The
native roster matrix crosses every pair of the 20 faction troop templates.
Mirrors are recorded separately and excluded from cross-match percentages.

Armies have approximately equal replacement-package cost, within 5% of
each other. The harness searches integer army sizes from 1 to 16 around a
32,000-coin target; it reports actual spend, body counts and the discrepancy
for every fight. Rare expensive-quality matchups can retry the same seeded
prefixes with up to 32 troops per army. Cost is native equipment value, native quiver replacement
prices and seven days of ordinary retainer wages. A horse adds the native
herd base price plus seven days of grain and groom/farrier expense. This is
a controlled base-price comparison, not a claim about every town's changing
market price, an inherited soldier's hiring fee, or lifetime training cost.

Win rate counts victories only. Score rate counts draws as half a victory.
Damage is the sum of final native tissue-layer `dmg` fractions on fresh
bodies, including support horses; damage dealt is the opponent's injury sum.
It is an injury index, not hit points or raw weapon energy. Kills come from
native Fighter kill counters. Cost efficiency is replacement-package value
of enemy bodies killed divided by actual package cost fielded. Routed and
unconscious survivors have no killed value. Rider and horse packages are
priced separately to avoid counting a dead horse twice.

Battles use an open 16x8 deployment grid, ordinary morale and gear wear,
6,000 native ticks at most, no rendering, no movement logs and no combat
journal. Tick-capped fights remain draws and are explicitly marked. Survey
shards stop and fail at a 45-second wall budget; partial output is evidence
of an incomplete shard, never a passed survey. Test Bridge imposes a
55-second process limit and the runner receives `--watchdog=60`.

The campaign check uses a Normal world, seed 4242, one-day history and three
coarse native daily turns, draining each work queue in short slices. Its
snapshots record population, town treasuries and settlement food stores,
grouped by each town's faction race. These are short-horizon observations,
not long-term dynasty/economy balance claims.

## Evidence and reproduction

JSON shards live in `test-results/balance_v070/` and include seeds, individual
side results, raw totals, actual costs, completion status and SHA-256 hashes
of the data tables. `summarize_balance_v070.py` is a read-only aggregator.
It rejects incomplete phases, mixed data within a suite, duplicate cross
trials and unequal-cost matches. The first roster pilot repeated eight
reference mirrors; these are identified and excluded from cross estimates.

Use `run_balance_v070.ps1` through PowerShell. It submits the raw Godot
command to the shared Test Bridge, waits for its actual result, and submits
one job at a time. It never launches Godot directly, claims another lease,
deletes evidence, enables GPU rendering or changes system audio. All jobs
use headless display and the Dummy audio driver. Runner `--keep-test-files`
preserves its temporary save files for these evidence runs.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File game/tests/run_balance_v070.ps1 -Mode Import
powershell -NoProfile -ExecutionPolicy Bypass -File game/tests/run_balance_v070.ps1 -Suite sweep -Phase survey_fresh -Samples 4 -Shards 8 -AllShards
powershell -NoProfile -ExecutionPolicy Bypass -File game/tests/run_balance_v070.ps1 -Suite campaign -Phase survey_fresh -Shards 1
python game/tests/summarize_balance_v070.py --phase survey_fresh
powershell -NoProfile -ExecutionPolicy Bypass -File game/tests/run_balance_v070.ps1 -Mode Regression
```

The regression is registered in `blocks.json` as `balance_v070`. It screens
five races and the three controlled combat roles, using every cross pairing
and both sides with one fixed sample: at least 24 side trials per race and
20 per role. Score must be in [10%, 90%], and draws must not exceed 25%.
These deliberately broad small-sample bands catch a nearly useless or
dominant option; the larger survey guides tuning. A missing category,
incomplete run or failed cost match also fails the test.
Foot and horse packages are screened at 30 side trials apiece with the same
[10%, 90%] score and 25% draw limits.

The fast test additionally selects a fixed, symmetric spread of eight
opponents for each native troop template (16 side trials each), with a
[5%, 95%] score band. It checks all 20 native templates rather than relying
on the three controlled roles alone. All portions share one 45-second
internal wall budget. The fast gate runs 280 battles and omits mirrors,
which are retained by the larger survey. The screening bands are the
explicit defaults for this pass, not confidence intervals or a universal
matchup guarantee.

## Scope limits

High elves, dark elves and trolls are disabled in the shipped faction data.
The harness can survey them with `--balance-disabled`; this pass does not
activate or tune them. Horses are the purchased general-purpose mounts.
Bloodline dragons have no native purchase/replacement price and their
bonded-rider aftermath is a separate campaign integration. A fair equal-coin
dragon valuation is not defined by this pass; dragon balance is not claimed.

## Measurements and changes

The paired comparison uses 2,520 battles per phase: 360 race, 240 role,
240 mount and 1,680 native-roster trials. Each pairing has four seeded
replications on both sides. The 520 mirrors per phase are excluded from
cross-match percentages. Score counts draws as half a victory; the CSV and
raw JSON also retain victory-only win rates, damage, kills and actual costs.

The original phase is `before_full`; the final phase is `after_verified`.
The earlier single-reference roster pilot and rejected tuning phases do
not contribute to these tables. All reported options are within the large
survey's [10%, 90%] viability band. Native templates span 18.42%-78.95%.
The controlled sword kit remains the weakest probe at 15%; these screening
bands do not imply equal 50% performance in every matchup.

### Race probes

96 cross-match side trials per option in each phase.

| Option | Before score % | After score % | Before efficiency | After efficiency |
|---|---:|---:|---:|---:|
| dwarf | 64.58 | 58.33 | 0.475 | 0.435 |
| goblin | 20.83 | 21.88 | 0.229 | 0.252 |
| human | 39.58 | 42.19 | 0.400 | 0.394 |
| moon_elf | 57.29 | 55.21 | 0.481 | 0.473 |
| orc | 67.71 | 72.40 | 0.576 | 0.536 |

### Controlled unit roles

80 cross-match side trials per option in each phase.

| Option | Before score % | After score % | Before efficiency | After efficiency |
|---|---:|---:|---:|---:|
| archer | 86.88 | 71.25 | 0.560 | 0.495 |
| spear | 61.88 | 63.75 | 0.425 | 0.473 |
| sword | 1.25 | 15.00 | 0.075 | 0.188 |

### Mount packages

120 cross-match side trials per option in each phase.

| Option | Before score % | After score % | Before efficiency | After efficiency |
|---|---:|---:|---:|---:|
| foot | 93.33 | 70.00 | 0.283 | 0.347 |
| horse | 6.67 | 30.00 | 0.069 | 0.302 |

### Native troop templates

152 cross-match side trials per option in each phase.

| Option | Before score % | After score % | Before efficiency | After efficiency |
|---|---:|---:|---:|---:|
| dwarf_holds/axedwarf | 23.03 | 18.42 | 0.301 | 0.314 |
| dwarf_holds/hammerdwarf | 26.32 | 22.37 | 0.220 | 0.183 |
| dwarf_holds/hold guard | 22.04 | 20.39 | 0.253 | 0.247 |
| eastern_khanate/keshig | 41.12 | 29.28 | 0.352 | 0.310 |
| eastern_khanate/lancer | 70.07 | 74.01 | 0.469 | 0.491 |
| eastern_khanate/steppe archer | 27.30 | 24.01 | 0.302 | 0.246 |
| goblin_warren/goblin archer | 68.42 | 55.26 | 0.285 | 0.244 |
| goblin_warren/goblin skulker | 81.58 | 71.05 | 0.248 | 0.294 |
| goblin_warren/goblin spear | 100.00 | 78.95 | 0.557 | 0.503 |
| middle_kingdom/March bowman | 38.16 | 34.87 | 0.370 | 0.403 |
| middle_kingdom/man-at-arms | 5.92 | 32.89 | 0.094 | 0.296 |
| middle_kingdom/spearman | 56.25 | 64.47 | 0.411 | 0.470 |
| moon_court/glaive dancer | 44.74 | 63.82 | 0.390 | 0.477 |
| moon_court/moon archer | 24.67 | 30.26 | 0.293 | 0.363 |
| moon_court/moon blade | 42.76 | 63.16 | 0.349 | 0.496 |
| northern_clans/clansman | 68.42 | 72.37 | 0.515 | 0.544 |
| northern_clans/fell hunter | 73.03 | 61.51 | 0.503 | 0.553 |
| northern_clans/huscarl | 58.55 | 54.61 | 0.598 | 0.576 |
| orc_horde/orc brute | 55.92 | 57.89 | 0.420 | 0.460 |
| orc_horde/orc warrior | 71.71 | 70.39 | 0.548 | 0.538 |

The complete numeric comparison is in
[`before_after.csv`](../test-results/balance_v070/before_after.csv).
The JSON shards retain the underlying army sizes, seeds and individual outcomes.

### Coarse campaign observations

Normal world, seed 4242, one-day history, then days 1-4 through three native
turns. Values are grouped by town faction race, not a census of each resident's
race. Delta compares each run's own start and finish. Different factory skill
rolls can change seeded world details, so these are short smoke observations.

| Race | Population delta before / after | Final food stock before / after | Treasury delta before / after |
|---|---:|---:|---:|
| dwarf | 1 / 1 | 10142 / 10237 | 133327 / 228842 |
| goblin | 0 / 1 | 35026 / 34999 | -360056 / -359941 |
| human | -1 / -3 | 26678 / 26889 | 410163 / 435107 |
| moon_elf | 0 / 0 | 8906 / 8896 | 212611 / 314709 |
| orc | 0 / 0 | 11176 / 11027 | 15650 / 6011 |

No town group lost more than a few residents in this sample; food stocks and
town treasuries remained positive. This does not establish multi-year economic
balance, especially after changing equipment quality prices.

### Final data edits

| Data field | Before | After | Reason |
|---|---:|---:|---|
| `weapons.middle.arming_sword.attacks[stab].contact` | 50 | 20 | The controlled sword role scored 1.25%. A narrower native point improves its existing thrust against armour. |
| `weapons.middle.arming_sword.attacks[stab].w` | 3 | 24 | Raises the existing thrust's selection share from 33.3% to 80%; armored probes exposed the cost of spending attacks on broad cuts. |
| `weapons.middle.arming_sword.attacks[stab].penetration` | 2,000 (20 mm) | 6,000 (60 mm) | The larger role survey still gave swords 6.25% after the first edits. Corrects the shallow thrust depth through the existing tissue resolver; remains below the spear's 100 mm. |
| `weapons.middle.arming_sword.attacks[stab].rec` | 3 | 2 | Gives the shorter blade a faster close-range reset. Together with thrust selection, the focused full role sample reached 15% rather than 6.25%. |
| `weapons.goblin.short_spear.attacks[stab].rec` | 3 | 10 | The native goblin spear won 152/152 cross trials. Its light thrust already prepares quickly under the physical timing formula; this extends the live recovery interval. |
| `bows.middle.self_bow.value` | 18 | 30 | The controlled archer role scored 86.88% at equal cost. Adds 240 coins at quality zero; remains below the 34-base-value longbow. |
| `economy.herds.horses.price` | 8,000 | 2,400 | The horse package scored 6.67%. Prices the existing speed/protection benefit while retaining native grain and farrier costs. |
| `economy.item_quality_value_growth` / `Item.value()` exponent base | 1.6 (hardcoded) | 1.25 (data) | Expensive quality kits were overwhelmed by cheap bodies: men-at-arms 5.92%, dwarf infantry about 22-26%, goblin spear 100%. Quality-three price premium becomes 1.953x instead of 4.096x; this edits prices through the existing formula. |
| `factions.middle_kingdom.man-at-arms.skills.sword` | [3, 6] | [6, 9] | Gives the professional unit training to support its costly kit; correcting mace training alone left it near the bottom. |
| `factions.middle_kingdom.man-at-arms.skills.mace` | absent (0) | [6, 9] | Half of its weapon choices were maces with no matching skill. Covers both actual loadout choices at the same professional range. |

`Item.value()` reads the new premium for ordinary gear and bows, including
the existing legendary calculation. Combat quality still uses its native
physics multipliers. This has wider effects on equipment resale, loot and
smith revenue; the coarse campaign check is short, not a multi-year profit
study. No race attributes, body/material definitions or combat algorithms
were tuned.

The discarded spear `prep` edit was ineffective because weapon preparation
comes from physical swing/thrust time. A wider spear point also left the
native outlier undefeated. Both edits were restored; only recovery remains
changed. Earlier small checks and candidate matrices are diagnostics, not
the final paired sample.

## Verification

- Original data: all four combat suites completed, 2,520 primary battles,
  plus the three-turn campaign check. The initial roster shard 6 failed
  after 42 battles because sixteen bodies could not match an expensive
  guard to cheap recruits. That failed attempt is retained and excluded;
  the same shard passed after the bounded 32-body fallback was added.
- Final data: all eight `after_verified` sweep shards passed, 2,520 battles.
  Test Bridge reported exit zero for each; the longest engine process was
  37.18 seconds. Aggregation found no missing shards, duplicate cross trials,
  mixed data hashes or cost discrepancies above 5%.
- Registered `balance_v070` gate: PASS, zero failures, 280 battles in
  23.478 seconds inside the test. Races scored 14.58%-68.75%, roles 20%-70%,
  native templates 12.5%-81.25%, and foot/horse 80%/20%.
- Final related block: PASS, all three scripts, 12.70 seconds for the actual
  engine process. It includes the campaign check (6.004 seconds), native
  simulation determinism, and all 114 horse checks with zero failures.
- Headless import completed without engine/script errors. Static checks
  validate the JSON, PowerShell syntax, Python syntax and whitespace.

Canonical raw evidence, summaries, the numeric CSV and job receipts are
under `test-results/balance_v070/`; final engine logs are in `test-results/`.
Rejected tuning and incomplete attempts remain separate from current passes.
No full campaign suite, rendered performance test, dragon valuation or
multi-year economy claim is included in these results.
