# BOWS SPEC (Douglas, 2026-10-04 20:56-21:20; addition 21:21)
Bows are the ONLY ranged weapon: no crossbows, ever. Real objects, real people, every shot simulated; roll the person, physics deterministic. Arrows go through the EXISTING contact/layer/tissue pipeline like a thrust. No scripted special cases, caps or bonuses. [DF] = Dwarf Fortress.
Addition (21:21): arrows (and bows) are part of the economy AND armory supply targets: the town head's armory, militias and every force's kit keep days-of-use targets for arrows like any other stock; shortfall raises orders and prices.

WHO: EVERYONE (company and every AI force), equipped from home-town stock. Races differ at making/using bows ONLY through real stats, training and race limits on those stats. No flat race bonus.

1 BOW (counted good: type x material x quality)
- Stats: DRAW WEIGHT, DRAW LENGTH, EFFICIENCY, MASS. Stored energy ~ 0.5 x draw weight x draw length. Arrow energy = efficiency x energy actually drawn.
- Construction: self bow (wood, eff ~0.70), longbow/war bow (tall self bow, heavy draw, eff ~0.70), composite (wood + horn + sinew + glue from butchery, eff ~0.80, slowest to make). Each race's bowyers make their own styles.
- Quality 1.0-2.0 [DF, +20%/level] raises efficiency and steadies aim. +-5% item variance rolled once at making by bowyer skill.
- MAXIMUM OUTPUT: shot energy from the WEAKER of (how far the archer can pull) and (the bow's tension limit). Extra STR adds nothing to the shot; only faster, steadier, less tiring draw. Later bows have draw weights most can't meet: partial draws. Nothing breaks from overdraw.
- Tuning anchors (not targets): hunting bow ~50 J, war bow ~100-130 J. Hits like a stab.

2 ARCHER
- POWER = draw: STR (plus a little body mass and END) vs draw weight. Weaker = partial draw: less energy, longer draw, shakier hold, faster exertion. Never a hard gate.
- SKILL = mostly ACCURACY: tighter spread, better spot picking, squarer hits, quicker draw. Skill never adds energy.
- Bow skill attributes: AGI + Spatial (A), KIN (B), WIL (C). XP 400+100n [DF]; trains those attributes. Ceilings/talent as built.
- Each draw costs END; holding full draw costs more.

3 ARROW (counted good)
- Shaft ALWAYS wood. Tips: WOOD, COPPER, TIN. Wood tip: light, fine vs flesh/cloth, near useless vs metal. Copper/tin use the metal table; tin soft.
- Tip shape: broadhead (wide edge, big wound, bleeding, poor vs mail) or bodkin (narrow point, small contact, better vs mail and shields).
- WEIGHT real per-arrow from shaft + tip. Heavier: more of the bow's energy, slower, more drop, keeps momentum, less drag loss, penetrates better at range. Lighter: flatter, further, softer.
- Impact: same layer tests as a thrust (energy, keenness, contact, metal values, construction, glance). Small momentum: rare stagger.
- Lodge on any penetration [DF]; broadheads tear more when pulled in the field.

4 FLIGHT, ACCURACY, DEFENCE
- One AIM ERROR roll per shot (an angle); flight deterministic. Spread narrows with Bow skill, AGI, Spatial, KIN, bow quality; widens with pain, exertion, partial draw, fear, target movement, archer movement, target defence saturation.
- Drag slows arrows. Long shots arc over a front rank.
- Arrow hits the first ENEMY silhouette on its path; body part = whatever sits at that point (size-weighted). NO FRIENDLY FIRE, including after pass-through.
- Defences in order: DODGE (AGI, Dodger; worse when busy in melee or tired), SHIELD block (x2 vs projectiles [DF]), then ARMOUR layers. No parrying arrows.
- Shield hit: block roll decides WHERE (boss, body, rim) and how square; layer test vs that spot's material/thickness. Metal boss stops nearly anything; wood tips almost never through. Through = leftover energy into arm/body behind. Stuck = lodges in the shield; lodged arrows make it heavier.
- PASS-THROUGH pure physics: energy spent layer by layer front to back; energy left = exit wound, keeps flying, can hit the next ENEMY behind.

5 TIMING, KITING, MELEE
- Draw/aim/loose/nock in ticks like prepare/recover [DF]; draw time grows with draw weight vs STR; skill shortens aim.
- KITING: archers keep distance and shoot, backing off as enemies approach (edges/units block retreat; legs and armour set speed). Stop kiting and melee when OUT OF ARROWS or an enemy closes in.
- MINIMUM RANGE per bow (~2 tiles, tune). Switch to melee when an enemy is inside it or will reach the archer before the next draw finishes.
- Switch costs ticks: DROP the bow (fast; can be trampled, picked up later) or SLING it (slower). Composure slings; panic or very close enemy drops.
- SIDEARM ALWAYS: every bow user gets one from town stock (dagger, knife, short sword, axe, club by faction); none = fists/kicks. Sidearm skill is its own skill. Enemy gone or pushed past min range + margin = switch back, picking the bow up if dropped and intact.

6 ECONOMY (wood is the backbone)
- New businesses: BOWYER (bows from wood; horn, sinew, glue for composites) and FLETCHER (wood shafts, feathers from poultry/game, tips; copper/tin tips from the smith).
- They buy from the town's real wood stock, competing with firewood, builders, carpenters: scarcity raises prices with reason "short of wood".
- Only part of cut wood is bow-grade; staves season for some months. Shafts need no seasoning.
- QUIVERS hold MAX 50 real arrows, filled from company stock. Spent shots are spent. After a held field some arrows recovered (broken = scrap). Arrows bought from town stock, carried by caravans, lootable.

7 PERF AND LOG
- One projectile per arrow in flight, line test on a coarse grid. Extend the 2 ms 50v50 blocking test with ~15 archers a side.
- Log [DF form]: "Aldric shoots a copper bodkin arrow! It strikes the goblin in the upper body! The arrow has lodged firmly in the wound!"
