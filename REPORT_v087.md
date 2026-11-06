# TASK087 source delivery — UNRUN

Recovery was confined to this writable Library candidate. No engine, import,
build, runtime test, process inspection/control, helper, git operation, version
bump, roadmap edit, installation or delivery was performed. Existing resource
UID files were untouched. Root must integrate accepted 086 before testing 087.

## What remained and what changed

- `game/data/economy.json`: recovered charcoal good, kiln and furnace fuel
  alternatives retained. Added the missing ordinary carpenter recipe:
  one iron bar plus one wood load makes one tool set, gated by existing iron
  know-how. Holds with iron no longer need a copper/tin/bronze supply to make tools.
- `game/campaign/businesses.gd`, `_recipe_choice`: equivalent smelter recipes
  with equal output priority, output quantities and rate now prefer the lower
  actual input bill. This makes cheaper charcoal usable even while wood remains.
  Existing batch payment, conservation, staffing and know-how paths are reused.
  Recovered `generate` kiln placement remains conditional on local forest.
- `game/campaign/worldgen.gd`, `place_holds`: corrected a stale comment claiming
  every mine gets 2–3 ores. Recovered `place_towns` dry/open Eastern placement
  and ordinary mountain hold placement are retained.
- `game/campaign/econ_gen.gd` was reviewed and retained unchanged during this
  recovery: `generate` allocates 45% of ordinary mining-town crop acreage to
  holds; `_deposits` guarantees rich hold iron; `_opening_stocks` seeds charcoal
  only by woods. These are generation conditions, with no recurring transfers.
- Reviewed `migration.gd` (`destination`, `move_households`) and `marriage.gd`
  (`_ai_blocked`, `try_ai_match`, `_ai_wed`): they already use race and native
  political/household rules without a human-culture exclusion. Neither changed.

## Authored checks

`game/tests/test_dwarf_cultures_v087.gd` remains **UNRUN**. It generates one
Normal world with one history day, restores generation options, and uses a
process-specific save path without cleanup.

| Claim | Native authored check |
| --- | --- |
| Mountain holds, rich ore, poor farmland, diplomacy, buildings | `_geography`, `_ore_and_flat_controls`: actual peaks, iron mines, annual grain deficit, road partners, diplomacy records, state building plots; flat-map negative and deterministic ore samples. Existing lifespan, birth intervals and steel knowledge are checked without altering them. |
| Paid production | `_production`: charcoal consumes wood; iron consumes ore and fuel; iron tools consume bars and wood; halls consume 50 stone and 5 wood. Missing inputs, zero producer cash, iron knowledge and cheaper-fuel cases are checked with native ledgers and conserved coin. |
| Metal/tools/arms exports; grain/wood/charcoal imports | `_trade`: ordinary unforced `Caravans.spawn`, real native crew, paid purchases, dry-buyer negative, driven destination/home arrival, duties, payroll and return receipts; counts, coin, population and the exported Item identity are checked. |
| Culture is no wall | `_tracked_move` and `_cohort_move`: all six directed human culture pairs; actual transfers, native register/allegiance, household/person lineage, property, age bins, stores, population and coin; war and human-to-dwarf negatives. |
| Cross-culture marriage | `_marriages`: Middle/Northern, Middle/Eastern and Northern/Eastern; native AI wedding, positive paid dowry, exact bride transfer, local/global spouse links and parents; war and race negatives. |
| Persistence | `_round_trip`: native save/load preserves all market stocks and physical property, cohort residence/age bins, exact migrant/wedding identity state, marriage links and the traded arm UID. |
| Desperation recruits | `_recruit_rules`: the same existing prosperous dwarf household offers nobody; hunger produces recruits bound to its real persons. Fixture fields and bindings are restored. |

Root-only command payload, through the admitted Test Bridge lane, from the
integrated version root:

```text
godot --headless --path game res://tests/runner.tscn -- --test=res://tests/test_dwarf_cultures_v087.gd --watchdog=180
```

Aim: under 60 seconds; hard cap: 180. Duration, compilation and assertions have
not been measured or passed here. Static JSON parsing succeeded, and a textual
declaration review found 0 missing names among 103 call sites backed by the
supplied classes. That is not a Godot syntax/type check. External class contracts
remain root's runtime gate; Barge calls were retained from the supplied draft.

Natural opening acreage and profitable road quotes are observed before trade
fixtures. Trade stock/prices/liquidity, arrival events, social relations, free
adult candidates, equal marriage ages and dowry liquidity are driven fixtures.
They establish causal transaction checks, not mature natural trade equilibrium,
long-term population stability or measured map movement. No later steel,
Academy, art, race/faction duplication or population cap was added.
