# ECONOMY SPEC 1/2: TOWN ECONOMY (Douglas: "Core with families", 2026-10-04 18:55)
Spec 2 = army pay and ranks. Numbers are tuned defaults [ours]; flag in CHANGES.

0. RULE ZERO: the economy is real. Every good is an integer count in a town, family, caravan, force or company stash. It appears only by production, leaves only by use, wear, spoilage, loss or raids. Towns, families and factions hold real gold; every trade moves gold. No spawned stock or gear for town-owned forces. Monsters own nothing.

1. GOODS (data rows: id, base price, weight, spoils days)
- Food: grain, fruit, meat (+fish counts as meat). Drink: beer (from grain), wine (from fruit).
- Variety label rides along: barley->barley ale, wheat->wheat beer, apples->cider, grapes->wine; sheep->mutton, pigs->pork, cattle->beef, deer->venison, boar, wolf. 1-3 varieties per town.
- Raw: flax, wool, hides, wood, stone, copper ore, tin ore.
- Made: linen/wool cloth, leather, clothing, blankets, tools, furniture, copper/tin/bronze bars.
- Arms: weapons and armor keyed (item type, material, quality 1-6: ordinary, well-made, fine, superior, exceptional, masterwork; existing 1.0-2.0 ladder). Sparse dict, only non-zero.
- Food spec base prices: meal 1, beer 1, wine 3.

2. WORLD GEN per town
- Climate from latitude: cold/temperate/hot. Allowed crops, fruit, herds per climate (e.g. rye/apples/sheep north, wheat/grapes south).
- 0-3 ore deposits with richness. Copper common, tin rare and patchy.
- Acreage: total, cultivated by crop; herds by animal.
- 1-2 specialties ("known for its tin/ale/fine armor"): x2 rate, +1 quality tier chance.
- Race culture row (data): household unit, growth, kin tracked, home type + materials + decay, head title, pay form, rank table (spec 2).
  Homes: humans timber+stone (slow decay); orcs hide tents (leather+wood, fast decay); goblins burrows (labor + little wood); moon elves living-wood halls (wood+stone, very slow).
- Political head: named person with family record (lord/reeve, jarl, chieftain, boss, council).
- 50-150 families (cap 150), each owning land, herds, homes, businesses, purse.

3. FAMILY RECORD
members by age/sex/job (counts; people seeded, generated when opened), land by crop, herds, homes, businesses owned, purse, goods (food, drink, clothing, blankets, tools, furniture), debt, history lines.

4. DAILY TOWN PASS (cheap, sums)
- Consumption over town totals: food mix + drink per person; firewood = houses x base x season x climate; clothing/blankets/tools wear; spoilage (faster when hot/summer). One food's shortfall is partly covered by others.
- Businesses produce (rows below), limited by workers, inputs in stock, tools.
- Market clears once: posted family/business buy orders vs stock. Price = base x clamp((need/stock)^0.5, 0.5, 3.0); keep last reason string per good ("food up: farm short-handed", "swords up: smith idle, no bars").
- Supply level per town and force: well supplied / short / starving from days of food+drink (>14 / 3-14 / <3). Food spec reads it at battle spawn; militia use town's.

5. BUSINESSES (family-owned rows: workers, wage, inputs/outputs per worker-day, owner purse)
fields (grain, fruit, flax; harvest season only), herds (meat, wool, hides; year-round, autumn slaughter peak), hunter, fishery (coast/river), woodcutter, quarry, mine, smelter (1 copper + 1 tin -> 2 bronze bars), weaponsmith, armorsmith, carpenter (tool handles, shields, shafts, furniture, wagons), weaver, tailor, tanner, leatherworker (leather armor/gear), brewer, vintner, builder (homes from race materials).
Smiths spend bars; no bars = idle. Every business needs tools; output drops without them. Can't pay wages -> workers leave.

6. FAMILY TURN (1/7 of families per day, weekly each; spread over frames)
pay tax or take/repay loan; move members toward best-paying open job; run owned businesses (hire, buy inputs, sell output); buy/sell land and homes; restock own goods; life events (marry, birth, death, leave) for opened/named families only. Growth gate: population grows only into built homes; decayed homes lose capacity; overcrowded or hungry families leave.

7. TOWN TURN (weekly)
Head hires tax collectors (paid jobs; fewer = more leakage). Seasonal tax: coin + share of grain in kind to granary + small market tax on sales. Land loop exactly: can't pay -> loan from head; can't repay -> head confiscates land; town offers it for sale to families; only if no buyer, town hires workers and works it. Ruined families -> landless laborers, recruit pool. Trade: read shortages/surpluses, send caravans, buy needs.

8. FACTION TURN (weekly)
Collect tax from town heads; pay armies (spec 2). Feed existing weekly diplomacy roll, not redesigned: low treasury/unpaid armies -> peace more likely; food or metal shortage -> trade pact with supplier or war on weak holder; caravans raided by X -> relation drift down with X.

9. CARAVANS (extend existing road caravans)
Load real counts from origin stock at origin price (gold to origin); cargo only on the wagons; unload at destination, sold at destination price. Load surplus/specialty, go where wanted. Player can raid: takes part of real cargo, rest lost; reputation hit with owner town and faction, bigger if witnesses survive. Battle loot stays gold.

10. MATERIAL ADOPTION (bronze now, iron etc. later = data row)
Brakes: supply (inputs in stock), know-how 0-100 per town per material (grows only while smiths work it, nudged by caravans from towns that know it; scales output and quality), turnover (forces store gear as material mix and replace a small share per day from home stock). Nothing floods.

11. FORCES AND RECRUITS
Every non-monster force has a home town and faction; gear, food and pay come only from home stock/treasury. Recruits come mostly from struggling rows (unpaid, idle, hungry, broke); hard times = more and cheaper recruits. Hiring removes a person from that family. Backstory line from the row's real state ("The fishery hasn't paid in three weeks; his children are hungry."). Recruit gets a family record.

12. TOWN SCREEN
Days of food, beer, wine, firewood; ore/bar counters with days of smithing; wood and stone; arms stock list; businesses with state tag (busy, idle, short of inputs, can't pay wages, short-handed); prices with arrow + reason; treasury, tax, militia wages, population trend; specialties; head. Tap a house or family: seeded description (home, acres, herds, goods, tax, story such as "lost 12 acres of barley to the reeve in the spring of year 2").

13. CAMPAIGN CLOCK: read season from Calendar. Day/night unused here.

14. TESTS (headless, must pass before ship)
conservation of goods and gold; caravan cargo leaves origin and arrives intact; smiths idle with zero bars; no bronze without copper+tin; know-how gates spread (bronze share stays low for a season in a fresh world); land loop order; 1-year sim with no negative stock or NaN prices.
Perf gate: worst campaign day < 5 ms on laptop at 20 towns x 150 families; report numbers in CHANGES.

15. SUPPLY TARGETS (Douglas, 19:53, folded in)
- Every town/city has a supply target per good (days of supply for consumables, a stock level for the armory); "need" in section 4 = this target.
- Below target: demand and willingness to pay rise. Above target: the town wants to sell, price drops, surplus goes to the towns shortest of it (caravans pick the biggest reachable shortfall, weighted by price gap). Producers make more than their target and export.
- Demand comes only from real use: consumption plus own businesses' inputs. No smelter = no ore demand (bars only).
- Jewelry is a goods row; jeweler business turns bars into jewelry, demand from wealthy families.
- Targets live on the actors (Douglas 19:55): each family (food, drink, firewood, clothing...), each business (inputs), the head's granary and armory. Town demand and prices = sum of those orders vs stock; no separate town-level target. Scale example: ~30 days of food.
- Caravan crews (Douglas 20:09): owned by a merchant family/business; drivers, porters and guards are home-town family members paid daily wages into family purses; raid casualties flow back to their families; unpaid crews quit and the caravan stays home.
- Rule (Douglas 20:09): every person in every non-monster force, every race, is a real person from a real family in a real settlement of their race, paid real wages into that family's purse. v0.006: company, caravan crews, militia. v0.007 (spec 2): faction armies, bandits, orc/goblin/elf bands with culture pay forms.
- Hardship ladder (Douglas 21:02-21:05): homeless (lost the house; squatters) and destitute (homeless + broke + landless) states raise hardship; desperate people appear more in the recruit pool and ask less. Backstories generated from the family's real history events (data-driven variants, time-ordered, ending with why he'd sign on). Town-funded shelter (poorhouse): treasury pays, feeds poor food (soup, bone broth) from real stock, people weaken over time there; homeless take casual jobs the economy needs (day labourer, porter, rat catcher, kitchen hand) at low wages ahead of other hires, and can climb back into housing.
