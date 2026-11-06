# Economy, towns and people — reviewed source audit

Pinned main: `2c7bd93`, v0.094, 6 November 2026. Argon high produced the area draft; the lead checked its claims against the actual tracked source and merge receipts. No game, engine, build or test was run. The helper's 117 supplied source files remained byte-identical. Source versions v0.086–v0.094 are accepted; the latest packaged release is v0.085.

## Confirmed implementation

- Domestic animals remain real native herd records in `game/campaign/herds.gd` and `game/data/economy.json`. `DomesticAnimals` adds actual dog feeding/guard eligibility and donkey pack custody, without making dogs battle units or free food. `prepare_pack` is at `game/campaign/domestic_animals.gd:113`; `pack_herd` is at line 157. A caravan stores the herd ID in `pack_herd`, not an invented animal dictionary.
- Dwarf geography, rich ore/limited farmland, charcoal/iron tools and retained cross-human-culture migration/marriage were accepted in v0.087. v0.088 extends native steel recipes/know-how through `game/campaign/metallurgy.gd`, `businesses.gd` and `economy.json`.
- v0.089 improves existing funded Academy research, registered staffing, real payroll/material use, armory custody and native audit boundaries. Owners are `game/campaign/academy.gd`, `arms_trade.gd`, `militia.gd`, and `game/ui/town_research_tab.gd`. `Academy.materials` at line 526 converts the older wood data entry to charcoal; current roster reporting is at lines 915–940.
- v0.090 implements ore gem pockets, named gem-set artifact production/lifetime maker limits and winner custody through `game/campaign/legends.gd`, `businesses.gd`, `arms_salvage.gd`, `core/item.gd` and the existing economy tables. It does not add a separate master-forge catalog or fictional `LegendaryForge` class.
- v0.094 plans rounded mint input bills before committing, registers/disposes recruit template Items, books naturally removed kit as real loss, and fixes category bookkeeping in migration/promotion/load paths. Its measurement artifacts use the existing exact-float codec on detached containers. Live purse roundoff is recorded rather than subsidized/clamped. Accepted short evidence is in `docs/economy_v094_results.md`; full campaign stability remains unverified.

## Player-facing findings

| Finding | Actual source and practical limit |
|---|---|
| Temple sickness promise is disconnected | `game/campaign/settlement.gd:386` reduces grievance but searches `world.sickness.cases` for severity. Native disease is in town/family `sk` structures (`game/campaign/sickness.gd:130`, `:164`). That severity loop does not operate on the native cases. No new healing rate is chosen here. |
| Separate reserve can create a hunger flag | `Settlement.update_food`, `game/campaign/settlement.gd:338`, updates synthetic `e.food` and sets `e.famine`. Real Barge grain/famine accounting is separate. `Migration.push` at `migration.gd:43` and `_leavers` at `:127` consume that flag. The risk is a contradictory state feeding real migration, not a measured assertion that every winter town flees. |
| Housing benefit uses inconsistent room reads | `Migration.housing_capacity` (`migration.gd:49`) applies the housing multiplier. Cohort births (`population.gd:313`), sickness crowding (`sickness.gd:249`, `:397`) and room reporting (`migration.gd:290`) use other capacity reads. The advertised benefit is therefore only partly integrated. |
| Two animal tables omit dogs | `game/ui/rec_town.gd:209` omits dogs from `HERD_ORDER`; the by-kind table at line 248 and live-market table at line 292 use only that list. The summary at line 214 appends other native kinds and the detailed herd list iterates actual records, so dogs are not invisible everywhere. |
| Pack animal and research prose is stale | `game/ui/rec_world.gd:284` says no pack animals despite `DomesticAnimals.prepare_pack`. `game/ui/rec_pages.gd:283` says research burns wood; current materials use charcoal. `rec_regions.gd:184` displays a workers count while the Research tab also has registered-roster information. |
| Steel know-how is absent from one overview | `game/ui/town_econ_tab.gd:176`/`:493` exposes bronze and iron labels. Native steel production and Academy research already exist; this is an overview omission, not absent steel research. The first draft's comparison to `rec_town.gd:133` was incorrect. |
| Cohort removal year deserves a controlled case | `Population.promote` uses the family's stored counting year (`population.gd:110`); `kill_slots` uses its day argument and clamps category subtraction (`:353`). Delayed year turns are at `:294`. This is a source risk requiring a bounded native case, not proof of a current P10 day-173 failure or proof that v0.094's accepted category fixes failed. |

The combined [priority list](README.md) ranks campaign entry/saved progress above a new feature. Civic food/benefit integration is the strongest economy-specific candidate after those immediate reliability repairs. Any future repair should connect existing native accounts and conditions rather than add another granary, population or disease ledger.

## Corrections to the initial draft

The first draft's release hashes and several supposed files/functions were unsupported. There is no tracked `game/data/animals.json`, `legendary_items.json`, `campaign/assay.gd`, `legendary_forge.gd` or `ui/fast_travel.gd` in this pin. The real pack entry points and stored field shape are stated above. Its fictitious master-forge/wing-polish/morale-tuning release descriptions are rejected; use root `CHANGES.txt` and `docs/validation_v086-v094.md` for actual per-version changes.

Population is counted per family's `population_year`, not a reported town-level year. The native `turn`/`kill_slots` snippets differed from the draft's claimed snippets. No causal connection to day 173 is accepted without the same-input native replay. No test was run or authorized to resolve that question here.

Documentation ages are reconciled in [the combined report](README.md). The developer notes opened at v0.022; the edition notes have a later v0.077 addendum; the HTML version map stops at v0.035. These are not the v0.044/v0.085/v0.042 cutoffs asserted in the initial draft.
