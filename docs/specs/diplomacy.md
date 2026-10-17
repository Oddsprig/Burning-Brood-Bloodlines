# Diplomacy spec v1 (Douglas picked "Both layers", 2026-10-04 18:23)
Tags: [BB] Battle Brothers, [MB] Mount & Blade, [ours]. All numbers are tuned defaults [ours], flagged in the change notes. Data lives in faction/race tables so lore stays editable.
Integrator notes: raiding is decided and shipped (v0.004) so the -12 raiding standing hit applies now; fold v0.004's raid reputation hit into this. Prisoner hits stay conditional on Douglas's point-7 pick. This unblocks war contracts from the monsters spec.

## Tick
- One diplomacy step per campaign day, right after the economy/day tick. Weekly war/peace roll every 7th day.
- State: 10 faction pairs (rel int -100..100, state enum, days_past_threshold, war_losses) + 5 player standings (earned int, comp_offset int, short event log). Nothing per battle tick.

## Layer 1: faction to faction
States by relation:
- WAR (< -50): armies target each other and raid each other's towns and caravans.
- HOSTILE (-50..-10): no trade; armies fight on contact.
- NEUTRAL (-10..30): trade, no fighting.
- TRADE_PACT (30..60) [ours]: caravans prefer partner towns; +5% sell price for partner goods.
- ALLIANCE (> 60) [MB]: armies don't fight each other and join each other's fights nearby.
Hysteresis: a state changes only after the relation has been past the threshold for 7 days running. Entering or leaving WAR also needs the weekly roll.
Lore baselines (data table): March-North -30. March-Orc -70. North-Orc -70. Goblin vs everyone -40, never above HOSTILE. Orc-Goblin -15. Elf-March +20. Elf-North 0. Elf-Orc -60. Elf-Goblin -50. World gen starts each pair at baseline +-10.
Daily drift: rel += (baseline - rel) * 0.01.
Event pushes: army destroyed by the other faction -4; caravan raided -3; town attacked/sacked -10/-25. Shared enemy: A and B both at WAR with C -> A-B +0.2/day.
War weariness [MB]: war_losses = men lost in that war (decays 2%/day). Each day at WAR: rel += min(1.0, war_losses / faction_size * 5).
Weekly roll per pair: HOSTILE held 7 days -> declare WAR: p = 0.05 + 0.15 * max(0, my_strength/their_strength - 1), cap 0.4. Strength = sum of army sizes + town militia. WAR with rel >= -50 held 7 days -> peace p = 0.3, state becomes HOSTILE. Every declaration posts a map news line (also peace, pacts, alliances).
Economy hooks: caravans never route between HOSTILE or WAR pairs; at WAR, AI armies may target the enemy's caravans and towns; TRADE_PACT: caravan destination weight x1.5 toward partners; a caravan raided by faction X = grievance -3 against X.

## Layer 2: each faction and the player's company
standing = clamp(earned + comp_offset, -100, 100). earned starts at 0, goblins -15.
Effects: contracts count and pay scale with standing, pay x(1 + standing/200), below -30 no contracts, above +50 a better tier. Market price x(1 - standing/500). Recruits: below -20 the faction's own race recruits halved; below -50 none. <= -50 HOSTILE: towns refuse trade, armies attack on sight. >= +50 FRIENDLY: patrols let you pass and join nearby fights on your side.
Earned moves: contract done +3..+8 by size; failed -5; abandoned -8. Fighting their army -10 (-5 if they attacked first). Raiding their caravan -12. Prisoners (only if point 7 picked): ransom +2, release +2, execute -1 per head (cap -10 per battle), sell to slavers -3 per head with factions that oppose slavery. Taking sides: contract against Y while employer X is at WAR with Y: X +2 extra, Y -2 extra. Daily drift: earned *= 0.995.
Band composition: data table attitude[faction][race] in -1..+1. Defaults: orcs despise elves -1, respect northerners +0.3, goblins 0. Moon elves: orcs -1, goblins -0.8, humans +0.2. March and North: orcs -0.6, goblins -0.8, elves +0.2/0. Own race +0.5. Goblins: everyone -0.3, own +0.5. comp_offset = 20 * weighted mean of attitude over the band's races (1 per unit, 2 per officer), capped +-20, recalculated only when the roster changes.
Who can hire: every faction, orcs and goblins included (their contracts: raids, captives, heads).

## UI
- Relations screen (from the company screen): one row per faction with the standing bar, the faction-to-faction state with you, the comp line separate ("Two orcs among your officers: -8 with the moon elves"), last 5 standing events per faction.
- World tab: 5x5 grid of faction states, colour per state.
- Map news ticker for declarations, short, no animation.

## Tests (headless)
- 1000 simulated days: no relation leaves -100..100; goblins never reach NEUTRAL; at least one war and one peace with default data.
- No caravan route between WAR or HOSTILE pairs.
- comp_offset within +-20 for any roster; officer weight 2.
- Standing <= -50 blocks trade and contracts.
- Diplomacy day step < 0.1 ms (note in perf numbers).

## Later (not in this build)
Envoys, broker-peace, betrayal; per-town standing; sub-factions/civil wars; tribute/vassals; towns changing hands; officers reacting to employers.
