TOWN SCREEN SPEC PART 1 of 3 (Douglas 00:52-00:55, reference "Yellow Springs" screenshots). Reference depth, our style, phone first. RULE: every number shown is read from the real sim. Never invent or pad. A field the sim lacks shows "not tracked"; list gaps in CHANGES. Sickness tab: see 06-sickness.md.

0. DATA MODEL (Douglas 00:55; already relayed for v0.010)
- One person = one record, one family household. Institutions are households too, with members: poorhouse (its inmates), barracks (single soldiers), town hall (head + officials). No temples.
- Rosters POINT at people, never copy them: garrison, militia, business staff, caravan crews, AI armies, the player's company. A soldier is in his family AND on the garrison roster. Tap any name anywhere -> the same person page.
- Test: roster <-> register resolve both ways; Register job/wage = roster post/pay.

1. FRAME (all tabs)
- Top bar 56 px: town, day + season, crest, town switcher, Close.
- Tab bar: chips min 48x96 px, swipe sideways, remembers last tab. Tabs in order: Overview, Market, Businesses, Register, Land & Homes, Census, Treasury, Hardship, Garrison, Roads, Sickness, Books.
- Body: vertical scroll of cards. Phone: no wide tables; row = 2 lines (name + main number, then grey details), whole row tappable, min 64 px. Tap -> full page with Back. SORT EVERY LIST BY ANY COLUMN (Douglas 00:56): register, members, roster, businesses, market, goods, homes, loans, ledger, sick. PC: tap a header to sort, again to reverse, arrow shows it. Phone: Sort chip lists every column; tap again reverses. Plus filters and a shown count. PC: list left, detail right.
- Charts: min / max / now / span. Town keeps 60-day buffers (treasury, population, food days, prices) and every season's census row.

2. OVERVIEW
- The town: people, families, adults working %, day wage, total land acres, treasury, head of town (tap -> person), food price index and staple index (x1.00 = normal), this year's harvest factor (real weather), grain held by farm families outside the walls.
- Families by class (reference Households): poor / middling / rich by real wealth. Row: people, income per person, savings, hunger %, FOOD SHARE (% of income spent on food).
- Days of supply: food, beer, wine, firewood, granary now/target and buying or selling, metal bars (days of smithing). Wood: stock, burned/day (homes + business recipes), cut/day, timber held for building.
- Families by state: comfortable / getting by / indebted / destitute / homeless / poorhouse. Row: count, people, avg purse, hunger %. Tap -> Register filtered to that state.
- Forces: garrison, militia, recruits on offer, caravans today / this week.
- Latest stories: last 10 town events from life histories and the town log; tap to open.

3. MARKET
- 6 category rows: Food, Drink, Raw, Made goods, Metal, Arms & armour. Each: total stock, days of supply, biggest price mover.
- Tap -> goods. Row: good, price, x base, 7-day change % (red up / green down), stock, days, demand/day, supply/day. Line 2: the sim's price reason string.
- Tap good -> price chart, businesses selling it, caravans carrying it.
- Arms items: material x quality grid (rows materials, 6 quality columns), counts and prices, armory stock vs target shown apart from market stock.

4. BUSINESSES (Douglas 01:03: every business is held by a real family member and family)
- Row: name, trade, address, KEPT BY <person> of <family>, HEALTH (Douglas 01:11: thriving / steady / struggling, plus failing; green / white / amber / red, from the real cash trend and margin over 14 days) + state tag (busy / idle / short of inputs / can't pay / short-handed) + WHY line from real causes (input price up, wages up as labour runs short, raided caravan, road cut by war, staff sick, demand fell), staff x/y, cash, profit yesterday.
- Detail: keeper and owner family (tap), cash chart, wage, rent, debt, margin; yesterday's ledger (revenue per product vs costs: stock, wages, materials, owner's living, rent); recipes (input -> output, batches made of max today) with COST PER UNIT = inputs at today's town prices + labour (wage / units per worker-day) + fuel, next to today's sell price, so margin is visible per product; stock on the shelf; staff = persons from any family, with job and wage (tap); HIRING (Douglas 01:03): open posts, wage offered, hired / quit / let go this month and from which family; last 10 events.
- Wages follow the town labour market (labour wanted vs offered -> day wage, Hardship tab); prices follow supply and demand (Market). Both move business costs.
- Falter and fail (Douglas 01:04): out of cash and no loan -> closes, staff let go, stock and tools go through the forced-sale loop, keeper's family takes the loss. Unmet demand -> a family with savings opens one. Closed this year list.

Part 2 (09-town-screen-2.md): Register, Land & Homes, Census, Treasury, Hardship. Part 3 (10-town-screen-3.md): Garrison, Roads, Books, tests.
