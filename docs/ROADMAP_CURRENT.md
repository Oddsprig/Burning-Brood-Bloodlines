# Burning Brood: Bloodlines — Current Roadmap (`main` @ `9177903`, `v0.085`)

## Delivered (`v0.023` – `v0.085`)

v0.023 - DONE - Mounted character and rider injuries on dragon downing
v0.024 - DONE - Dragon breath elemental cone attacks
v0.025 - DONE - Campaign dragon deployment and army-purse feeding
v0.026 - DONE - Settlement raids
v0.027 - DONE - Settlement sieges and conquest
v0.028 - DONE - Feudal consequences and fear of dragons
v0.029 - DONE - Levy armour issuance and army refits
v0.030 - DONE - Dynasty alliances and diplomacy
v0.031 - DONE - Army map markers, slower travel, and objectives
v0.032 - DONE - Intrigue plots, schemes, and assassinations
v0.033 - DONE - Prisoner ransom, release, and exchange
v0.034 - DONE - Common-folk migration, housing, and illness
v0.035 - DONE - Campaign creatures and lairs world toggle
v0.036 - DONE - Gem-coloured dragon portrait fangs
v0.037 - DONE - Editable house inheritance laws
v0.038 - DONE - Dragon mate pairing, egg clutches, and breeding
v0.039 - DONE - New-game ruler character designer
v0.040 - DONE - Settlement buildings and store-driven famine
v0.041 - DONE - Pre-round tactical battle orders and counters
v0.042 - DONE - Building cost, seasonal harvest, and tactics balance pass
v0.043 - DONE - Wage-band labour market, household spending, and Treasure Room
v0.044 - DONE - Large script splits and PROJECT_MAP.md (committed without version tag)
v0.045 - DONE - Daily batched town land market
v0.046 - DONE - Cached household lookup indices for faster campaign days
v0.047 - DONE - Map trade shortage/surplus badges and caravan markers
v0.048 - DONE - Net-margin caravan routing and 30-day cargo hold
v0.049 - DONE - Ruler and AI town supply orders
v0.050 - DONE - Daily counted dragon provisions and feeding priority
v0.051 - DONE - Multi-month earned rider familiarity bonds
v0.052 - DONE - Heritable dragon growth potential and food-paced stages
v0.053 - DONE - True-scale Dragon Roost view and detail panel
v0.054 - DONE - Deterministic fall wounds and death for downed dragon riders
v0.055 - DONE - Battle terrain patterns, combat cues, and readability legend
v0.056 - DONE - Town horse herds, cavalry mounts, and mounted combat
v0.057 - DONE - Relations world-view screen fit and mobilization test fix
v0.058 - DONE - Net-sales farm wage ceilings over seasonal hands
v0.059 - DONE - Non-mutating household guard record page reads
v0.060 - DONE - Producer wage-bid and migration coin-conservation test fixes
v0.061 - DONE - Code-drawn 6-frame Sapphire Spirewing dragon sprite
v0.062 - DONE - Neck-base saddle sockets, straddling rider pose, and procedural saddle
v0.063 - DONE - 2.5D normal-mapped shaded human body, clothing, armour, and saddle
v0.064 - DONE - 16 dragon gem palettes and 6 code-drawn breed silhouettes
v0.065 - DONE - 2.5D shaded art pipeline for all 7 non-human humanoid races
v0.066 - DONE - Portrait eye placement, idle arms, and dragon forward-merge (folded into v0.065)
v0.067 - DONE - Front-facing 96x96 shaded bust portraits for all 8 races
v0.068 - DONE - Per-race portrait script split and human/dwarf/orc/goblin/troll resculpt
v0.069 - DONE - Elf and goblin portrait redraw and headless frame guard
v0.070 - DONE - Measured combat balance (70a), cross-view identity (70b), and popup cleanup (70c)
v0.071 - DONE - Foot-only troll and giant families in orc and goblin towns
v0.072 - DONE - Android mobile port, touch controls, safe areas, and export preset
v0.073 - DONE - Mount-scaled rider fit merge, land-sale speed fix, UID sidecars, and roadmap sync
v0.074 - DONE - Deterministic whole-world fresh-process save and reload check
v0.075 - DONE - Strict daily and whole-window money, stock, and item conservation audit
v0.076 - DONE - Legacy dragon/army test repairs, 9-realm map palette, and phone HUD bounds
v0.077 - DONE - Daily prisoner food/coin upkeep, AI ransom/exchange, and execute/sell actions
v0.078 - DONE - Conquered town lordship revocation, grants, and captor prisoner custody
v0.079 - DONE - AI cross-realm noble marriages and AI warband marching dragons
v0.080 - DONE - Sovereign High Elf and Dark Elf realms, night bows, and war-mask diplomacy step
v0.081 - DONE - Live BattleSim mounted rider targeting and civilian wound preservation
v0.082 - DONE - 11 OGG music tracks, 8-scene MusicManager autoload, crossfades, and volume slider
v0.083 - DONE - Drag-anywhere phone list touch scrolling and inertial fling
v0.084 - DONE - Weekly default autosaves outside battle and faster save serialization
v0.085 - DONE - Combined v0.072-v0.084 release and verified arm64 Android APK (`9177903`)

Notes on version order and branches:
- `v0.044` was committed across `54c9c0c`..`ede739d` without a `v0.044` commit prefix; `v0.066` was folded into `v0.065` (`b7de852`, `31339d8`).
- Inserting `v0.072` (Android mobile port) shifted the proposed numbers in `roadmap_review_v0071.md` (`v0.072`–`v0.079`) by `+0.001` (`v0.073`–`v0.080`).
- `main` merged out of strict numeric sequence as versions passed tests and QC: `v0.047` before `v0.046`, and `v0.073 -> v0.080 -> v0.083 -> v0.084 -> v0.082 -> v0.081 -> v0.075 -> v0.078 -> v0.074 -> v0.079 -> v0.076 -> v0.077 -> v0.085`.
- Branch `claude/speed-landmove` (`538d630`) remains as an unmerged branch ref, though its payroll land-sale refresh skip was included in `v0.073`.

## Authorized source sequence and current owner priorities

Owner correction (6 November 2026): a battle is a series of smaller engagements,
not one huge clash. Combat balance measurements must follow the native engagement
and between-engagement roster, casualty, rider and outcome transitions. Record
each engagement and the enclosing battle separately. The v0.093 standalone survey
draft is unaccepted and must be re-scoped to this contract before use.

At most TWO helpers. Finish the next versions in order: v0.089 fixes, v0.090,
v0.091 review and v0.092. Do not spend these slots on later work. v0.094 drafts
are preserved and held; v0.095 is explicitly ON HOLD. No 200v200 test has run.
The last packaged release remains v0.085; v0.086-v0.088 below are tested source
merges, not claims of new Desktop or Android deliveries.

v0.086 - SOURCE TESTED/MERGED - Eight domestic herd species; merge `aa6c58e`, domestic 1438/0, herd totals 82/0, strict audit 62/0.
v0.087 - SOURCE TESTED/MERGED - Dwarf ore/grain trade and free inter-human migration/marriage; merge `e0df622`, targeted trade/culture and v0.086 regression block passed. Failed fixture attempts are retained.
v0.088 - SOURCE TESTED/MERGED - Paid pig-iron/steel ladder, matching-iron reserve and cheaper fuel variants; merge `3db1c2d`, 496 steel plus 27 existing metallurgy checks passed.
v0.089 - NOT DONE - State-funded capital Academies, lead researchers, salaried staff, and faction steel know-how progression (`docs/specs/next/02-steel-assay-house.md` §C–D)
v0.090 - NOT DONE - Ore-mine gem pockets, refitted 25% skill-15 masterwork curve, and named gem-set legendary artifacts kept by battle winners (`docs/specs/next/03-legendary-items.md`)
v0.091 - NOT DONE - Code-drawn 2.5D normal-mapped shields, weapons, and bronze/iron/steel specular material ramps (`docs/ROADMAP.txt` deferred `v0.064` art pass; `roadmap_review_v0071.md`)
v0.092 - NOT DONE - Post-peace 60–120 day diplomatic truces and militia 1.25x wall-holding sally threshold (`docs/specs/barge/90-war-picks.md`; `95-resume-notes.md`)
v0.093 - NOT DONE - Seven-race (including High/Dark Elf) and dragon valuation per engagement inside native multi-engagement battles. Preserve real transitions between engagements and report both engagement-level and battle-level outcomes. Existing dragon shadow-value draft is held for this re-scope; no measured balance claim (`docs/balance_v070.md`).
v0.094 - HOLD / NOT DONE - Multi-year campaign economy, worked-land, and smith revenue stability after 1.25x quality pricing. Preserve the early source draft; resume only after the preceding accepted versions and an ordered root dispatch.
v0.095 - OWNER HOLD / NOT DONE - Performance and versioned save-upgrade work is stopped. Battles must remain a series of smaller engagements; the former single 200v200 clash framing is superseded. Resume only on a new owner-authorized dispatch consistent with that battle model.
