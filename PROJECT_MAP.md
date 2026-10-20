# Burning Brood: Bloodlines — Project Map

Concise repository index for **Burning Brood: Bloodlines (Claude Edition, Godot 4.7.2)**. Keep startup context small: use this map to jump directly to the owning file instead of scanning the tree.

## 1. Which Docs to Read First

1. `PROJECT_MAP.md` — This file: directory/file sizes, system index, largest files, and split roadmap.
2. `AGENTS.md` (14.4 KB / 194 lines) — Persistent user rules, delivery gates, test time/block budgets, and locked design contracts.
3. `HANDOFF_CLOUD.md` (7.3 KB / 75 lines) — Cloud/Claude Edition v0.035 handoff, branch workflow, test blocks, and DevTools rules.
4. `DEV_NOTES_CLAUDE_EDITION.txt` (21.4 KB / 325 lines) — Claude Edition systems (v0.023–v0.035): breath, raids/sieges, marriage, intrigue, prisoners, migration/sickness, creatures.
5. `HANDOFF.txt` (15.3 KB / 224 lines) & `START_HERE.txt` (8.7 KB / 141 lines) — v0.022 baseline architecture, native identity rules, and player feature summary.
6. `docs/ROADMAP.txt` (22.1 KB / 301 lines) & `docs/DEV_NOTES.txt` (23.1 KB / 322 lines) — Version-by-version scope/acceptance criteria and technical lessons.
7. `docs/FOLDER_PLAN.txt` (2.5 KB / 42 lines) & `docs/specialists/*.txt` (19.7 KB / 5 files) — Folder ownership and specialist helper briefs (`dynasty-economy`, `combat-dragons`, `interface-release`, `population-economy`, `bounded-qa`).

## 2. Where Each System Lives

| System | Primary Code Files (`game/...`) | Data / Config / UI | Notes & Key Entry Points |
| :--- | :--- | :--- | :--- |
| **Economy** | `campaign/barge.gd`, `campaign/town_econ.gd`, `campaign/families.gd`, `campaign/businesses.gd`, `campaign/herds.gd`, `campaign/herds_market.gd`, `campaign/herds_views.gd`, `campaign/plots.gd`, `campaign/arms_trade.gd`, `campaign/arms_salvage.gd`, `campaign/house_upkeep.gd`, `campaign/loans.gd`, `campaign/caravans.gd`, `campaign/salvage.gd` | `data/economy.json`, `ui/town_econ_tab.gd`, `ui/town_market_tab.gd`, `ui/rec_market.gd`, `ui/rec_flows.gd` | `Barge` & `TownEcon` drive weekly/daily town turns; `Families`/`Businesses`/`Herds`/`Plots` own private wealth, land, livestock, and production; `Salvage`, `ArmsTrade` & `ArmsSalvage` handle gear/metal stock, spoils, and redistribution. |
| **Population** | `campaign/persons.gd`, `campaign/people.gd`, `campaign/population.gd`, `campaign/migration.gd`, `campaign/sickness.gd`, `campaign/sickness_groups.gd`, `campaign/census.gd`, `campaign/shelter.gd`, `campaign/town_housing.gd`, `campaign/town_sanitation.gd` | `data/sickness.json`, `ui/population.gd`, `ui/rec_town.gd`, `ui/rec_races.gd` | Tracked families (`Persons`/`People`) + anonymous common-folk cohort pools (`Population`). `Sickness`/`SicknessGroups` run register & cohort illness; `Migration` moves cohorts under famine/war/crowding. |
| **Battles** | `sim/battle_sim.gd`, `sim/battle_damage.gd`, `sim/battle_morale.gd`, `sim/fighter.gd`, `sim/formulas.gd`, `sim/archery.gd`, `sim/natural_attacks.gd`, `sim/combat_journal.gd`, `sim/combat_text.gd`, `sim/healing.gd`, `campaign/battle_rounds.gd`, `campaign/battle_tactics.gd`, `campaign/clash_rounds.gd` | `data/bodies.json`, `data/weapons.json`, `data/armor.json`, `data/materials.json`, `data/combat_text.json`, `battle/battle.gd`, `battle/aftermath.gd`, `battle/combat_log.gd` | `BattleSim` (`BattleDamage`, `BattleMorale`) resolves DF-style tissue/material/wound/blood/morale ticks. `BattleRounds` runs 100v100 multi-round clashes; `CombatJournal` & `CombatLogBrowser` provide full-fight paged logs. |
| **Dragons** | `campaign/dragons.gd`, `campaign/dragon_bond.gd`, `campaign/dragon_combat.gd`, `campaign/dragon_care.gd`, `campaign/dragon_growth.gd`, `campaign/dragon_life.gd`, `campaign/dragon_breeding.gd`, `campaign/dragon_fear.gd`, `sim/dragon_breath.gd` | `data/dragons.json`, `data/dragon_combat.json`, `battle/dragon_view.gd`, `battle/breath_fx.gd`, `art/dragon_art.gd`, `art/dragon_rig_art.gd`, `art/dragon_damage_art.gd`, `ui/dragons.gd`, `ui/dragon_card.gd` | Wyvern records in `Dragons`; 1-to-1 human bonds in `DragonBond`; persistent native `Unit`/`BodyState` combat holders in `DragonCombat`; cone breath in `DragonBreath`; GPU layer/wound rendering in `DragonView`. |
| **UI** | `ui/theme.gd`, `ui/kit.gd`, `ui/house_select.gd`, `ui/house.gd`, `ui/house_laws.gd`, `ui/court.gd`, `ui/muster.gd`, `ui/politics.gd`, `ui/relations.gd`, `ui/town.gd`, `ui/records.gd`, `ui/rec_town.gd`, `ui/rec_world.gd`, `ui/company.gd`, `ui/unit_sheet.gd`, `ui/land_map.gd` | `ui/fonts/` (`Cinzel`, `Alegreya`, `LiberationSans`), `campaign/world_map.gd` | Code-built `Control` trees via `UiKit` & `UiTheme`. `main.gd` switches screens via `Game.goto()`. Records screens use `RecTable`/`RecRow`/`RecCells` for fast paged rendering. |
| **Saves** | `core/game.gd`, `core/save_snapshot.gd`, `campaign/world.gd`, `ui/save_indicator.gd` | `user://save.json`, `user://settings.json` (per-PID in `runner.gd`) | `Game.save_game()` / `Game.load_game()` & `SaveSnapshot` capture consistent slices without mutating simulation state; `CampaignWorld.after_load()` restores indices and UID floors. |
| **World Gen** | `campaign/worldgen.gd`, `campaign/world.gd`, `campaign/world_presim.gd`, `campaign/world_warbands.gd`, `campaign/econ_gen.gd`, `campaign/house_onboarding.gd`, `ui/newgame.gd`, `ui/presim.gd` | `data/factions.json`, `data/backstory.json`, `data/diplomacy.json` | `WorldGen` builds terrain/regions/roads; `CampaignWorld.generate_*` (`WorldPresim`) & `EconGen` populate towns, families, plots, herds, and presim history (`PRESIM_DEFAULT_DAYS = 1`, `WORLD_SIZE = "normal"`). |
| **Tests / Runner / Blocks** | `tests/runner.gd`, `tests/runner.tscn`, `tests/blocks.json`, `tests/claude_*.gd`, `tests/test_*.gd` | `tests/fixtures/*.gd`, `test-results/*.txt` | Run via `godot --path game res://tests/runner.tscn -- --block=headless` (or `--test=res://tests/<file>.gd --watchdog=60`). `runner.gd` counts `SCRIPT ERROR` lines and runs `reset_between()`. |
| **Dev Tools** | `campaign/dev_tools.gd`, `core/perf_tracker.gd`, `core/memory_owners.gd`, `ui/performance_panel.gd`, `ui/debug_ui.gd`, `campaign/debug_map.gd`, `battle/test_battle.gd` | `user://dev_start_world_*.json` | `DevTools.start_world(tree)` loads/caches a 1-day Normal world in seconds and sets up instant test states (`raise_army`, `set_round_size`, famine, siege, etc.). `Perf` tracks frame/job ms. |

## 3. 15 Largest Code & Data Files (Before / After Split)

*(Binary audio/PNG/TTF assets are listed under their folders below: largest binaries are `game/audio/music_map.ogg` 3,452.7 KB, `music_title.ogg` 2.879.5 KB, and 6 dragon source PNGs in `game/art/dragon_source/` at 1,758–2,266 KB each.)*

1. `game/tests/fixtures/records_v044_baseline.gd` — **188.0 KB / 3,260 lines** — Frozen multi-year town/economy baseline fixture for records regression tests.
2. `game/data/economy.json` — **102.0 KB / 3,896 lines** — Economy tables: goods, recipes, business types, land yields, seasonal curves, town parameters.
3. `game/art/dragon_source/source_catalog_v006.json` — **101.3 KB / 5,670 lines** — Authoritative pixel bounds, anchors, and cut masks for v0.006 dragon forms.
4. `game/campaign/families.gd` — **90.3 KB / 1,917 lines** — Household records (`Families`): weekly family turn, food/heating, births/deaths, inheritance, hiring, land/herd trades.
5. `game/art/orc_art.gd` — **80.3 KB / 1,498 lines** — Orc anatomy, heads/tusks/hair, and racial wardrobe on `FigurePainter` rig (hash-locked in `MODEL_IMPORT_v0.007.json`).
6. `game/tests/fixtures/families_v035_hiring.gd` — **78.5 KB / 1,659 lines** — Historical snapshot fixture for family hiring tests.
7. `game/ui/rec_town.gd` — **75.1 KB / 1,242 lines** — Town records UI (`RecTown`): Overview, People, Economy, Sickness, and Land & Defence tabs.
8. `game/campaign/barge.gd` — **73.0 KB / 1,632 lines** — Barge economy engine (`Barge`): wage/price equilibrium, household stage orchestrator, labour clearing.
9. `game/campaign/town_econ.gd` — **72.8 KB / 1,676 lines** — Town economy (`TownEcon`): market stock/prices, taxes, public works, shops, trade ledger.
10. `game/campaign/businesses.gd` — **72.8 KB / 1,554 lines** — Family-owned businesses (`Businesses`): daily crafting/gathering, hiring, wages, profit/closures.
11. `game/art/figure_painter.gd` — **71.6 KB / 1,750 lines** — Humanoid procedural figure/portrait/wound painter (`FigurePainter`, hash-locked in `MODEL_IMPORT_v0.007.json`).
12. `game/campaign/plots.gd` — **71.3 KB / 1,651 lines** — Town land grid (`Plots`): farms, woods, mines, homes, civic buildings, deeds, clearing.
13. `game/data/dragon_combat.json` — **67.7 KB / 3,100 lines** — Dragon combat body parts, gem hardness, breath cones, and wound tables.
14. `game/sim/battle_damage.gd` — **66.4 KB / 1,479 lines** — Melee/ranged strike delivery, `debug_strike`, armour/weapon wear, tissue layer wounding, body function updates, stuck weapons, and unarmed grapple.
15. `game/sim/battle_sim.gd` — **62.8 KB / 1,490 lines** — Grid combat tick loop, AI targeting, movement, defence contests, events/journal, aftermath; delegates strike/wounds/grapple to `BattleDamage` and morale/rally/rout to `BattleMorale`.
*(Note: `game/sim/battle_sim.gd` was **133.5 KB / 3,272 lines** and is now split into `battle_sim.gd` **62.8 KB / 1,490 lines** + `battle_damage.gd` **66.4 KB / 1,479 lines** + `battle_morale.gd` **14.9 KB / 383 lines**; `game/campaign/herds.gd` was **108.3 KB / 2,528 lines** and is now split into `herds.gd` **49.5 KB / 1,073 lines** + `herds_market.gd` **53.8 KB / 1,181 lines** + `herds_views.gd` **13.4 KB / 355 lines**; `game/campaign/sickness.gd` was **102.3 KB / 2,504 lines** and is now split into `sickness.gd` **61.2 KB / 1,443 lines** + `sickness_groups.gd` **48.2 KB / 1,131 lines**; `game/campaign/world.gd` was **91.0 KB / 1,973 lines** and is now split into `world.gd` **50.8 KB / 986 lines** + `world_warbands.gd` **33.9 KB / 723 lines** + `world_presim.gd` **13.6 KB / 342 lines**; `game/campaign/army.gd` was **70.6 KB / 1,659 lines** and is now split into `army.gd` **51.0 KB / 1,108 lines** + `army_ranks.gd` **23.8 KB / 594 lines**; `game/campaign/arms_trade.gd` was **69.8 KB / 1,637 lines** and is now split into `arms_trade.gd` **47.0 KB / 1,126 lines** + `arms_salvage.gd` **26.3 KB / 543 lines**; next largest is `game/sim/formulas.gd` **61.8 KB / 964 lines**.)*

## 4. Folder & Important File Map

### `/` (Repo Root — 20 files, 421 KB)
- `AGENTS.md` (14.4 KB / 194L) — Master agent rules, version history, and test/delivery constraints.
- `HANDOFF_CLOUD.md` (7.3 KB / 75L) — Cloud handoff for v0.035 Claude Edition, test blocks, and DevTools guide.
- `HANDOFF.txt` (15.3 KB / 224L) — Local PC handoff for v0.022 baseline, paths, and architecture contract.
- `START_HERE.txt` (8.7 KB / 141L) — Quick-start launcher notes and feature summary through v0.022.
- `DEV_NOTES_CLAUDE_EDITION.txt` (21.4 KB / 325L) — Detailed implementation notes for v0.023–v0.035 Claude Edition passes.
- `HOW_TO_PLAY.txt` (7.3 KB / 138L) & `README_CLAUDE_EDITION.txt` (1.8 KB / 33L) — Player manual and release overview.
- `TEST_RESULTS_CLAUDE_EDITION.txt` (6.6 KB / 111L) — Measured test and benchmark summary for Claude Edition.
- `Launch_Claude_Edition.ps1` (2.6 KB / 34L), `Launch_Bloodlines.ps1` (2.6 KB / 34L), `Install_Desktop.ps1` (5.7 KB / 78L) — Windows launcher and Desktop installer scripts.

### `docs/` (140 files, 3,488 KB total)
- `docs/ROADMAP.txt` (22.1 KB / 301L) — Scoped version roadmap (v0.002–v0.042+) and performance recovery gates.
- `docs/DEV_NOTES.txt` (23.1 KB / 322L) — Active development log, v0.021–v0.022 verification metrics, and design locks.
- `docs/FOLDER_PLAN.txt` (2.5 KB / 42L) — High-level directory ownership rules.
- `docs/ART_ARCHIVE_INDEX.txt` (4.9 KB / 79L) — Index of archived source art and model imports.
- `docs/specialists/` (5 files, 19.7 KB) — Role briefs: `interface-release.txt` (6.0 KB / 81L), `dynasty-economy.txt` (5.0 KB / 69L), `combat-dragons.txt` (5.0 KB / 65L), `bounded-qa.txt` (2.0 KB / 33L), `population-economy.txt` (1.7 KB / 23L).
- `docs/specs/` (41 files, 285.4 KB) — Feature specs: `MODEL_IMPORT_v0.007.json` (8.5 KB / 206L), `PERFORMANCE_RECOVERY_PLAN.txt` (8.1 KB / 116L), `economy-1-town.md` (8.9 KB / 72L), `economy-2-army.md` (4.9 KB / 43L), `food-drink.md` (5.5 KB / 78L), `bows.md` (5.7 KB / 50L), `diplomacy.md` (4.8 KB / 44L), `DRAGON_PHYSICS_v0.005.txt` (4.9 KB / 79L), `DRAGON_CARE_v0.008.txt` (4.3 KB / 66L), and `docs/specs/barge/` (16 files, 70.4 KB: Barge economy & sickness specs 01–13) + `docs/specs/next/` (3 files, 14.0 KB).
- `docs/history/` (18 files, 202.7 KB) — Archived prior roadmaps, dev notes, and pre-v0.011 specialist briefs.
- `docs/handoff/original/` (71 files, 2,921.4 KB) — Immutable Copper Oath v0.046 base archive, benchmarks, and notes.

### `game/` Root & `game/core/` (14 code files, 170.1 KB — Autoloads & Core Entities)
- `game/project.godot` (3.5 KB / 68L) — Godot 4.7.2 config (`config/version="0.035-claude"`, autoloads `DB`, `Game`, `Perf`, `Sound`).
- `game/main.gd` (3.2 KB / 76L) & `game/main.tscn` (0.1 KB / 6L) — Root scene container switching active UI/battle/map screens.
- `game/core/game.gd` (36.6 KB / 832L) — Autoload `Game`: campaign state holder, screen router, battle launch/finish, save/load orchestration.
- `game/core/food.gd` (31.6 KB / 764L) — `Food`: Spoilage, ration lots, belly/thirst states, combat stamina/focus modifiers.
- `game/core/unit.gd` (14.7 KB / 292L) — `Unit`: DF-scale attributes, skills, personality traits, equipment slots, wounds, family/person links.
- `game/core/factory.gd` (13.3 KB / 283L) — `Factory`: Deterministic unit, equipment, and warband builder from faction templates.
- `game/core/db.gd` (13.2 KB / 268L) — Autoload `DB`: Loads and indexes `game/data/*.json` tables.
- `game/core/perf_tracker.gd` (9.3 KB / 175L) & `game/core/memory_owners.gd` (8.3 KB / 146L) — Autoload `Perf` & memory diagnostics.
- `game/core/item.gd` (8.1 KB / 194L) — `Item`: Concrete weapon/armor instance with material, quality, maker's mark, and wear.
- `game/core/body_state.gd` (7.5 KB / 225L) — `BodyState`: Tissue-layer damage, bleeding, severed parts, pain, and consciousness (no HP).
- `game/core/baggage.gd` (6.9 KB / 151L), `game/core/loot.gd` (6.6 KB / 129L), `game/core/creatures.gd` (6.0 KB / 137L), `game/core/sound.gd` (4.0 KB / 96L), `game/core/save_snapshot.gd` (3.7 KB / 101L).

### `game/sim/` (13 code files, 347.2 KB — Deterministic Physical Combat Engine)
- `game/sim/battle_sim.gd` (62.8 KB / 1,490L) — `BattleSim`: Grid combat tick loop, AI targeting, movement, defence contests, events/journal, aftermath; delegates strike/wounds/grapple to `BattleDamage` and morale/rally/rout to `BattleMorale`.
- `game/sim/battle_damage.gd` (66.4 KB / 1,479L) — `BattleDamage`: Melee/ranged strike delivery, `debug_strike`, armour/weapon wear, tissue layer wounding, body function updates, stuck weapons, and unarmed grapple.
- `game/sim/battle_morale.gd` (14.9 KB / 383L) — `BattleMorale`: Morale init, commander/leader aura, shock, rage, rout, flee step, and officer rally.
- `game/sim/formulas.gd` (61.8 KB / 964L) — `Formulas`: All physical contact, momentum, penetration, tissue stress, and morale math.
- `game/sim/archery.gd` (28.4 KB / 653L) — `Archery`: Bow draw, ballistic flight, scatter, and arrow impact resolution.
- `game/sim/combat_text.gd` (26.7 KB / 536L) & `game/sim/combat_journal.gd` (15.2 KB / 360L) — Lazy text formatter and full-battle outcome journal.
- `game/sim/health_report.gd` (19.1 KB / 519L) & `game/sim/healing.gd` (17.1 KB / 394L) — Read-only DF health descriptions and post-battle wound recovery.
- `game/sim/fighter.gd` (10.1 KB / 151L), `game/sim/natural_attacks.gd` (9.6 KB / 210L), `game/sim/dragon_breath.gd` (9.2 KB / 191L), `game/sim/learning.gd` (5.5 KB / 121L).

### `game/campaign/` (93 code files, 2,146 KB — World, Economy, Dynasty, Population, Armies, Dragons)
- **World & Map**: `world.gd` (50.8 KB / 986L), `world_map.gd` (36.7 KB / 842L), `world_warbands.gd` (33.9 KB / 723L), `map_terrain.gd` (26.8 KB / 625L), `worldgen.gd` (24.4 KB / 563L), `tracks.gd` (20.0 KB / 490L), `settlement.gd` (18.5 KB / 532L), `world_presim.gd` (13.6 KB / 342L), `map_tracks.gd` (6.6 KB / 169L), `calendar.gd` (2.6 KB / 63L).
- **Economy & Land**: `families.gd` (90.3 KB / 1,917L), `barge.gd` (73.0 KB / 1,632L), `town_econ.gd` (72.8 KB / 1,676L), `businesses.gd` (72.8 KB / 1,554L), `plots.gd` (71.3 KB / 1,651L), `herds_market.gd` (53.8 KB / 1,181L), `herds.gd` (49.5 KB / 1,073L), `arms_trade.gd` (47.0 KB / 1,126L), `house_upkeep.gd` (46.8 KB / 1,241L), `caravans.gd` (31.9 KB / 689L), `academy.gd` (28.3 KB / 648L), `arms_salvage.gd` (26.3 KB / 543L), `harvest_claims.gd` (22.5 KB / 492L), `econ_gen.gd` (21.7 KB / 405L), `loans.gd` (20.8 KB / 438L), `bows_econ.gd` (20.1 KB / 458L), `herds_views.gd` (13.4 KB / 355L), `crop_rotation.gd` (12.9 KB / 283L), `economy.gd` (11.2 KB / 246L), `salvage.gd` (8.9 KB / 143L), `economy_rules.gd` (8.1 KB / 164L), `goods.gd` (7.2 KB / 195L), `wage_claims.gd` (6.4 KB / 142L), `metallurgy.gd` (3.5 KB / 71L).
- **Population & Health**: `persons.gd` (61.6 KB / 1,432L), `sickness.gd` (61.2 KB / 1,443L), `sickness_groups.gd` (48.2 KB / 1,131L), `people.gd` (34.6 KB / 781L), `backstory.gd` (27.6 KB / 577L), `recruits.gd` (24.5 KB / 474L), `shelter.gd` (20.1 KB / 431L), `population.gd` (17.2 KB / 354L), `census.gd` (16.9 KB / 383L), `migration.gd` (15.0 KB / 291L), `town_sanitation.gd` (8.1 KB / 148L), `town_housing.gd` (5.0 KB / 99L).
- **Dynasty, Politics & Intrigue**: `dynasty.gd` (51.2 KB / 923L), `diplomacy.gd` (46.7 KB / 1,093L), `feudal.gd` (31.2 KB / 514L), `court_events.gd` (21.3 KB / 409L), `marriage.gd` (20.1 KB / 358L), `legends.gd` (18.9 KB / 442L), `prisoners.gd` (16.1 KB / 301L), `character_design.gd` (15.6 KB / 370L), `intrigue.gd` (14.0 KB / 267L), `house_onboarding.gd` (10.5 KB / 143L), `ennoble.gd` (5.6 KB / 96L), `ambitions.gd` (5.2 KB / 102L).
- **Armies, Warfare & Monsters**: `army.gd` (51.0 KB / 1,108L), `mobilization.gd` (42.3 KB / 722L), `war_ai.gd` (41.0 KB / 898L), `battle_tactics.gd` (25.9 KB / 643L), `army_ranks.gd` (23.8 KB / 594L), `monsters.gd` (22.6 KB / 498L), `troop_upkeep.gd` (19.9 KB / 523L), `contracts.gd` (19.8 KB / 379L), `militia.gd` (19.7 KB / 419L), `battle_rounds.gd` (18.8 KB / 350L), `warfare.gd` (16.0 KB / 286L), `service_identity.gd` (13.0 KB / 263L), `bandits.gd` (10.5 KB / 236L), `monster_contracts.gd` (9.5 KB / 184L), `town_defence.gd` (8.1 KB / 169L), `lairs.gd` (7.4 KB / 205L), `clash_rounds.gd` (7.1 KB / 138L), `supplies.gd` (5.8 KB / 166L), `rank_rules.gd` (5.6 KB / 136L), `arms_pool.gd` (5.0 KB / 100L).
- **Dragons & DevTools**: `dragons.gd` (22.6 KB / 371L), `dragon_combat.gd` (19.2 KB / 315L), `dragon_breeding.gd` (15.1 KB / 326L), `dragon_care.gd` (12.7 KB / 211L), `dragon_bond.gd` (10.3 KB / 165L), `dev_tools.gd` (7.0 KB / 132L), `dragon_life.gd` (6.7 KB / 122L), `dragon_growth.gd` (4.6 KB / 80L), `dragon_fear.gd` (3.5 KB / 75L).

### `game/battle/` (16 files, 156.2 KB — Battle Scene, Actors & Logs)
- `battle.gd` (48.4 KB / 1,212L) & `battle.tscn` — Battle screen controller, camera framing, HUD, pause/speed, round flow.
- `aftermath.gd` (24.5 KB / 439L) & `result_summary.gd` (7.4 KB / 141L) — Post-battle casualty, prisoner, loot, and salvage summary UI.
- `dragon_view.gd` (17.7 KB / 350L) & `unit_view.gd` (6.0 KB / 162L) — Battlefield actor nodes for wyverns (with seated rider) and humanoid fighters.
- `inspector.gd` (12.8 KB / 344L) & `combat_log.gd` (10.8 KB / 225L) — Live unit tissue/equipment inspector and paged combat log browser.
- `gore_layer.gd` (9.2 KB / 241L), `map_view.gd` (9.1 KB / 183L), `test_battle.gd` (3.1 KB / 82L), `breath_fx.gd` (2.4 KB / 63L), `arrow_layer.gd` (2.3 KB / 66L), `fx_layer.gd` (1.6 KB / 52L).

### `game/ui/` (97 files, 1,798.4 KB including `fonts/` 824.5 KB)
- **Records & Town**: `rec_town.gd` (75.1 KB / 1,242L), `rec_world.gd` (38.5 KB / 684L), `town_econ_tab.gd` (34.6 KB / 607L), `land_map.gd` (34.3 KB / 838L), `rec_data.gd` (23.0 KB / 559L), `rec_pages.gd` (21.8 KB / 408L), `town.gd` (20.1 KB / 490L), `records.gd` (18.5 KB / 452L), `town_market_tab.gd` (17.0 KB / 397L), `rec_civic.gd` (15.5 KB / 233L), `rec_regions.gd` (14.9 KB / 227L), `rec_market.gd` (14.6 KB / 254L), `rec_flows.gd` (14.2 KB / 230L), `town_research_tab.gd` (11.4 KB / 199L), `town_contracts_tab.gd` (10.4 KB / 217L), `rec_table.gd` (10.1 KB / 256L), `town_provisions_tab.gd` (10.0 KB / 215L), `population.gd` (8.9 KB / 164L), `rec_kit.gd` (8.3 KB / 208L), `rec_races.gd` (8.2 KB / 166L).
- **Dynasty, Dragons & Army**: `dragons.gd` (50.9 KB / 767L), `court.gd` (29.2 KB / 537L), `house_select.gd` (27.5 KB / 491L), `unit_sheet.gd` (23.0 KB / 531L), `company.gd` (22.3 KB / 516L), `politics.gd` (19.7 KB / 342L), `muster.gd` (16.3 KB / 273L), `house.gd` (14.2 KB / 258L), `round_summary.gd` (13.9 KB / 406L), `house_laws.gd` (12.9 KB / 256L), `relations.gd` (12.1 KB / 273L), `dragon_card.gd` (8.1 KB / 172L), `treasure_room.gd` (7.9 KB / 191L).
- **Startup, Theme & Chrome**: `kit.gd` (15.1 KB / 394L), `presim_feed.gd` (13.1 KB / 315L), `presim.gd` (12.2 KB / 314L), `performance_panel.gd` (11.1 KB / 180L), `presim_map.gd` (11.0 KB / 299L), `words.gd` (10.1 KB / 204L), `newgame.gd` (9.5 KB / 212L), `theme.gd` (9.4 KB / 230L), `title.gd` (4.4 KB / 111L), `settings.gd` (4.4 KB / 121L), `guide_view.gd` (4.6 KB / 42L).

### `game/art/`, `game/data/`, `game/audio/`, `game/tests/`, `test-results/`
- `game/art/` (106 files, 13,198 KB) — Procedural humanoid/creature/dragon painters (`orc_art.gd` 80.3 KB, `figure_painter.gd` 71.6 KB, `goblin_art.gd` 54.5 KB, `human_art.gd` 52.1 KB, `elf_art.gd` 51.0 KB, `item_icon_art.gd` 43.3 KB, `dwarf_art.gd` 39.3 KB, `map_tokens.gd` 34.0 KB, `troll_art.gd` 33.1 KB, `dragon_rig_art.gd` 24.7 KB, `dragon_art.gd` 24.6 KB, `paperdoll.gd` 23.5 KB, `dragon_damage_art.gd` 22.4 KB, `creature_painter.gd` 20.2 KB, `mounted_rider_art.gd` 10.0 KB) + `dragon_source/` (13 files, 12,076 KB) + `concepts/` (32 files, 447 KB) + `icons/` (6 files, 6.8 KB).
- `game/data/` (15 JSON files, 357 KB) — `economy.json` (102.0 KB / 3,896L), `dragon_combat.json` (67.7 KB / 3,100L), `bodies.json` (48.9 KB / 244L), `combat_text.json` (34.3 KB / 1,211L), `factions.json` (19.6 KB / 146L), `backstory.json` (18.5 KB / 173L), `creatures.json` (13.0 KB / 112L), `weapons.json` (9.7 KB / 79L), `sickness.json` (9.5 KB / 381L), `armor.json` (9.3 KB / 87L), `materials.json` (7.8 KB / 32L), `dragons.json` (6.5 KB / 47L), `bows.json` (5.4 KB / 51L), `diplomacy.json` (3.6 KB / 45L), `food.json` (1.2 KB / 18L).
- `game/audio/` (39 files, 7,759 KB) — CC0 music (`music_map.ogg` 3.45 MB, `music_title.ogg` 2.88 MB, `music_battle.ogg` 1.22 MB), combat/dragon SFX, and `CREDITS.txt`.
- `game/tests/` (686 files, 3,666 KB) — `runner.gd` (6.0 KB / 143L), `runner.tscn`, `blocks.json` (0.8 KB / 25L: `headless`, `display_a`, `display_b`, `display_c`), 330+ test/diagnostic scripts, and `fixtures/` (22 files, 510 KB).
- `test-results/` (1,651 files, 19,180 KB) — Dated verification reports (`v0.002`–`v0.042`, `claude_edition/`, `economy-pass/`, `test_blocks_logs/`).

## 5. Oversized Files (>1,500 Lines or >80 KB, Excluding Active Economy-Pass Files)

- **Done this run**:
  - `game/campaign/sickness.gd` (was 102.3 KB / 2,504L) -> split into `sickness.gd` (61.2 KB / 1,443L: core register disease model, risk/catch, daily queue, family/body turns) + `sickness_groups.gd` (48.2 KB / 1,131L: `SicknessGroups` common-folk cohort pools, carriers/caravans/edge, field forces/company, unit hooks, herbalist, UI reads & 5-year reports).
  - `game/sim/battle_sim.gd` (was 133.5 KB / 3,272L) -> split into `battle_sim.gd` (62.8 KB / 1,490L: grid combat tick loop, AI targeting, movement, defence contests, events/journal, aftermath) + `battle_damage.gd` (66.4 KB / 1,479L: `BattleDamage` strike delivery, `debug_strike`, armour/weapon wear, tissue layer wounding, body function updates, stuck weapons, unarmed grapple) + `battle_morale.gd` (14.9 KB / 383L: `BattleMorale` morale init, commander/leader aura, shock, rage, rout, flee step, officer rally).
  - `game/campaign/herds.gd` (was 108.3 KB / 2,528L) -> split into `herds.gd` (49.5 KB / 1,073L: core herd records, worldgen/migration, weekly disease/life/grazing/feeding) + `herds_market.gd` (53.8 KB / 1,181L: `HerdsMarket` fodder loans/stockpiling, home slaughter, livestock offers/buys, prices/products/manure/straw/crop switching/fees, butcher daily, transfers, drovers) + `herds_views.gd` (13.4 KB / 355L: `HerdsViews` grazing tile assignment, home pens, and UI/land-map/ledger reads).
  - `game/campaign/world.gd` (was 91.0 KB / 1,973L) -> split into `world.gd` (50.8 KB / 986L: core strategy layer, A* pathing, party travel, encounters, time/work queue, battle results, after_load) + `world_warbands.gd` (33.9 KB / 723L: `WorldWarbands` warband strength/scouting, spawning, multi-frame muster, movement, AI clashes, road-link/town helpers) + `world_presim.gd` (13.6 KB / 342L: `WorldPresim` world generation slices and pre-history simulation).
  - `game/campaign/army.gd` (was 70.6 KB / 1,659L) -> split into `army.gd` (51.0 KB / 1,108L: core army state, enlisting, daily jobs, pay, desertion, loot chest, worldgen/load) + `army_ranks.gd` (23.8 KB / 594L: `ArmyRanks` command tree math, promotions, noble call-up, orc succession duels, militia trees, and rank-tree views).
  - `game/campaign/arms_trade.gd` (was 69.8 KB / 1,637L) -> split into `arms_trade.gd` (47.0 KB / 1,126L: item classes, maker's marks, troop kit, armory reserve/procurement/orders, re-kit, worldgen/load, caravan picks, contract retirement, views) + `arms_salvage.gd` (26.3 KB / 543L: `ArmsSalvage` battlefield dead gear recovery, spoils sharing, soldier/guard kit return, caravan plunder, 10-day internal supply redistribution).
- **Proposed next splits**:
  - `game/campaign/town_econ.gd` (72.8 KB / 1,676L) & `game/campaign/barge.gd` (73.0 KB / 1,632L) -> extract `campaign/town_econ_views.gd` (ledger/UI read queries) and `campaign/barge_views.gd` (after economy pass).
  - `game/campaign/plots.gd` (71.3 KB / 1,651L) -> extract `campaign/plots_buildings.gd` (plot UI cards, worker reads, and town civic buildings, L1216–1651).
  - `game/art/figure_painter.gd` (71.6 KB / 1,750L) & `game/art/orc_art.gd` (80.3 KB / 1,498L) -> keep intact while SHA256-locked by `docs/specs/MODEL_IMPORT_v0.007.json`; if unlocked later, split `figure_painter_helm_weapons.gd` and `orc_wardrobe_art.gd`.
  - Data/Fixtures (`source_catalog_v006.json` 5,670L, `economy.json` 3,896L, `dragon_combat.json` 3,100L, `records_v044_baseline.gd` 3,260L, `families_v035_hiring.gd` 1,659L) -> keep static data/fixtures intact or split `fixtures/` by town/subsystem only when updating baselines.
