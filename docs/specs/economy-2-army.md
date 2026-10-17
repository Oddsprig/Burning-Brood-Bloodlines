# ECONOMY SPEC 2/2: ARMY PAY, RANKS, SUCCESSION (Douglas 18:44-18:58, 2026-10-04)
Builds on spec 1. Rank decides two things: which units the officer commands as a figurehead (his branch of the tree) and the wage his family receives. Rank is hierarchy and pay only; skill, experience and weapon specialties stay per unit. In battle rank only feeds the existing officer morale (Leader skill). No new combat stat.

1. NO FREE SOLDIERS (and every person, every race and force, is a real family member - Douglas 20:09)
- Every soldier in every force is paid each day, orcs and goblins included.
- Payer by tier: militia and town guard -> town treasury; a city's standing troops -> city; field armies -> faction treasury (funded by town tax).
- Wage rises with tier (militia < guard < professional) and with rank. Training and gear quality follow the payer's means: militia part-time workers with basic kit, guard full-time, professionals best stock the treasury can buy.
- Pay form from culture row: humans and elves coin; orcs mostly food, beer, loot share; goblins food and loot. Bandit camps pay from stolen stock.
- Pay goes to the soldier's family purse. Unpaid N days -> desertion back to family (bandits scatter). Deaths remove the person from the family.
- Soldiers are drawn from town families; named sergeant-level and up get family records.

2. RANK TABLE (data per culture; names [ours], overrulable)
- Middle March humans. Militia: levyman, levy sergeant. Guard: watchman, watch sergeant, watch captain. Army: spearman, veteran, sergeant, lieutenant, captain, marshal, lord general.
- Northern clans. Militia: fyrdman. Guard: hearthguard, hearth-thane. Army: carl, huskarl, thane, hersir, war-jarl.
- Orcs. Militia: slag. Guard: den-guard. Army: grunt, blooded, boss, big boss, warboss, warlord.
- Goblins. Militia: warren-rat. Guard: tunnel-watch. Army: sneak, shiv, knife-boss, gang-chief, the Biggest.
- Moon elves. Militia: lantern-bearer. Guard: grove warden, elder warden. Army: blade, moonblade, warden-captain, lord-commander, high marshal of the Silvered Court.
- Eastern, Southern, Western humans: later.

3. RANK CAPS FROM SIZE
- Each culture has a span (reports per officer). Orcs span 5: 1 warlord, 5 warbosses, 25 big bosses, 125 bosses; then blooded (grunts who survived a fight, paid a little more) and grunts.
- Example 5,000 orcs: 1 / 5 / 25 / 125, each boss leading ~40.
- The tree grows with the faction's soldier count: fill top-down, only as many levels as the army size supports. Other cultures default span 5 [ours], tunable per row.
- Bottom two ranks are status, not caps: survive a battle -> veteran/blooded equivalent.
- Top army rank is the faction's war leader; for orcs the warlord is also head of state.

4. SUCCESSION (per culture)
- Orcs: a post opens on death or promotion -> the officers who reported to it fight a free-for-all; survivor takes the post. His old post opens -> his reports fight. Cascade down until a blooded fills the last boss slot. Warlord dies -> his 5 warbosses fight; winner = new warlord and head of state. Fights run headless in the real combat sim (tiny map, candidates only, own gear). Real wounds and deaths. Logged to history ("Grukk took the warboss post over Mazg's corpse"). Gate: one fight < 10 ms.
- RANK RULE per faction (culture row field rank_rule): strength (free-for-all in the combat sim), wealth (richest family's candidate gets the post; commissions bought from the treasury), politics (Social awareness + Negotiator + Leader, plus favour with the head), renown (reports vote, weighted by battles won; contested -> duel to yield), cunning (backstab roll; losers may die), lineage (seniority, then bloodline). Defaults [ours]: orcs strength; Middle March wealth; Northern clans renown; goblins cunning; moon elves politics. Adding a rule = one function + data.
- KILL RENOWN counts in every weighted rule: lifetime kill-renown score per unit, one weighted term in every weighted rule's candidate score (except orcs: the fight alone decides; high renown only lets a unit join the free-for-all one level up). Each kill adds the victim's worth: recruit/grunt 1, more per enemy rank, plus a share (e.g. 25%) of the victim's own renown; monsters by rarity tier (wolf 1, bear 5, troll lair 20, EPIC hydra 100, LEGENDARY dragon 300) [ours, tuned]. Renown shows on the unit card with notable kills.

5. PROMOTION
Fill vacancies by the culture rule; otherwise promote when a unit has XP and battles survived above the rank's threshold and a slot under the cap is free.

6. UI
- Force panel: rank tree with names and counts; tap an officer for his record and family.
- Town and faction screens: wage bill per day, days of pay left.

7. TESTS
- No force ever has unpaid soldiers without the desertion timer running.
- Rank counts never exceed caps; caps follow army size.
- Orc cascade: kill a warboss -> one big boss promoted, one boss promoted, one blooded promoted, all by fights; counts stay valid.
- Wage gold leaves treasury and lands in family purses (conserved).
