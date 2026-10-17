# Spec 2: steel know-how and the state research house
(Douglas picked 13:05 2026-10-06. Queued after v0.011. No test runs; the decades-long tuning in C is a starting value, not verified with century runs unless he asks.)

## A. Steel as a material
- Steel is a new metal above iron in the existing material ladder (copper < bronze < iron < steel).
- Step size: recommended SMALLER than bronze-to-iron (iron stays the big jump; steel's edge is hardness and holding an edge). Douglas has not answered this yet; build uses this default and he can overrule it. Units with steel are simply better. No nerfs anywhere.
- Making steel follows Dwarf Fortress: smelt iron, then smelt again with pig iron + flux stone (limestone etc.), burning fuel each step. Steel costs about double the fuel of iron plus flux, and needs real iron ore and flux from real mines. Rarity comes from that cost and from few skilled smiths, not from caps.
- Quality: steel uses the 6 quality levels like everything else. Poor steel is no better than good iron; a masterwork iron sword can beat a poor steel one.

## B. Who can make steel
Each faction holds a steel know-how level, 0 to 100%. It sets the best steel quality its smiths can make (0 = none; low = poor steel only; 100 = all qualities). A smith's own skill still applies on top, as for every craft.
- Dwarves: start at 100%.
- Orcs and goblins: always 0, forever. They get steel only by trade or by battle (loot). They can wear, use and repair steel gear they have; they cannot make new steel.
- Humans (all cultures) and moon elves: start at 0, learn VERY slowly through their research house (C). Elves learn slightly faster than humans: a race learning factor, starting at 1.25x human (build may tune; keep it "slightly faster").
- Know-how belongs to the faction. If a town changes hands later (conquest), what moves is its smiths and buildings, not the faction's know-how.

Steel reaches non-makers through existing systems only: the arms trade between factions at peace, battle loot (existing loot code, AI included), and later conquest.

## C. The research house (state-funded business)
Name: "Assay House" (real-world assay offices tested and refined metals; no magic). Elves may show it as "Elven Assay House"; the rule is the same.
- One per human faction and per elf faction, in that faction's capital. Not for orcs, goblins or dwarves.
- It is a real business in the town's business system: building, log book, real staff. It is owned and funded by the STATE, not a family.
- Funding: each faction turn, the state sets a research budget from its treasury. How much it gives comes from its interest in research, which rises and falls with real conditions: treasury health, the ruler's/leaders' traits, war pressure, and how much steel the faction has met (enemy steel in battle, steel bought in trade). If the treasury is short or interest falls, the budget falls.
- Head: the house is held and run by a LEAD RESEARCHER, a real person like everyone else: family, household, age, wage, traits, skill, home town. Title per race, a name only (no magic): humans "Wizard", elves "Sage". The lead researcher's skill and traits shape the house's output and how well staff learn, and their wage comes from the research budget. If they die, retire, flee or leave, the state appoints a replacement from the best-skilled staff or town people; a weaker successor means lower output, and an empty post stalls it. Their family is a normal household (children can follow the trade).
- Staff: it hires real people at real wages through the normal hiring rules: chemists and apprentices under the lead researcher. Wages come only from the research budget. Budget falls -> staff are laid off or leave -> output drops. No budget -> no staff -> no progress.
- Materials: trials burn real iron, flux and charcoal, bought from the market at market prices. Shortages slow it.
- Output: each working day, each staff member adds research by their skill (apprentices little, the lead researcher most). Staff gain skill by working, like any job; trained chemists who leave take their skill with them.
- Optional extra inputs, all from things the sim really has: studying steel items (bought or looted, used up in study) adds research; a hired dwarf smith on staff adds a lot. Dwarves can be hired like any migrant worker; nothing scripted.
- Research turns into know-how: know-how % rises with accumulated research x race learning factor (elves 1.25x). The curve is steep: early gains are poor steel only; full mastery takes very long. Tune so that steady, average funding takes many decades to reach poor steel for humans ("very slowly"). This is a starting tuning value, not a target or gate; report what century runs actually produce only when Douglas asks for runs.
- Research house buildings also count as state buildings on the map.

## D. Show it
- Faction screen: steel know-how %, research budget, house staff count, recent output.
- Town screen (capital): the Assay House business with staff, wages, materials, log.
- Census/goods screens already show steel counts once it exists as a material.

## E. TO_TEST.txt lines
- Orcs and goblins never gain steel know-how over a long run; still use looted/traded steel.
- Cutting a faction's research budget lays off house staff and drops output.
- Losing the lead researcher (death or leaving) drops output until a successor is appointed.
- Elves gain know-how faster than humans under equal funding.
- Dwarf holds export steel through the arms trade at peace.
- Humans of all cultures migrate and change allegiance across human factions.

## CHANGE (Douglas 13:13): "no dude, its going to be for all research the faction does - we might add other things..."
- The capital research building is the faction's home for ALL research, not steel only. Name: "Academy" (default; he can overrule).
- One state-funded Academy per human and elf capital; same lead researcher (Wizard / Sage), staff, wages, budget and funding rules as above.
- Its research is a LIST of lines (data); steel is the first and only line for now. Budget and staff split across active lines, so adding a line later is just a data row.
- Faction and town screens show the lines (progress, budget share, staff on it).
- TO_TEST: "The Academy lists its research lines; steel is the only one and shows progress."

## CHANGE (Douglas 13:23): "name the research business something fitting for that race and culture"
Same business everywhere; name and lead title are per-culture data. Middle humans: Academy / Master. Northern humans:
Lorehall / Loremaster. Eastern humans: House of Wisdom / Hakim. Moon elves: Athenaeum / Sage. New cultures get a row.

## CHANGE (Douglas 13:23-13:24): every race gets a research house; orcs and goblins just can't make steel
- Every race's capital has one (orcs, goblins, dwarves too). Each line lists the races that can take it; steel is
  closed to orcs and goblins forever and isn't a line for dwarves (already 100%). A house with no line it can take
  keeps its lead and budget idle: no staff, no spending until a line exists.
- Orcs: Blood Forge / Forge-Boss (Douglas 13:27: LOTR orcs crossed with WoW fel orcs, look only). Goblins: The Pit / Pit-Master (Douglas 13:27: LOTR goblins, not tinkerers). Dwarves: Hall of Makers / Maker-Lord.
