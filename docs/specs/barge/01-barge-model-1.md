BARGE MODEL PART 1 of 4: PRINCIPLES, RACES, COIN PRICING (Douglas 02:36-02:37: pasted "The Late Barge, Economy Rules v0.18.41": "so u can understand how we wanna build the economy in this world, between different races" and "the pricing of bronze coins"). Full doc: research/late-barge/economy-rules-v0.18.41.md (not readable by the build; parts 1-4 carry what it needs.)

This is the model our economy follows. The barge numbers are used as given. Changes for our world are marked [ours] with the reason. Parts: 1 principles + coins, 2 prices + food + households, 3 labour + businesses, 4 treasury, loans, land, famine, trade, war, movers. Fixes for the 5-year collapse are marked FIX-n with the build's cause number.

0. WHAT STAYS OURS (better or already decided)
- NO LIGHT MODEL (Douglas 02:39: "we want an in-depth econ for all of our towns, cities and factions"). The barge runs its full economy only in Yellow Springs and Heron Weir and a light model (population by walk of life, index coins) everywhere else. We drop the light model: EVERY town, city and faction of every race runs the full model in parts 1-4 with named households, real businesses, a real treasury, granary, loans and land. Barge rules tagged [All towns] are kept only where they add something (famine stages, trade, war) and run on the full model.
- One person, one household; rosters point at persons; every person in the register (Douglas 00:55).
- Coins are single bronze cash coins called "coins"; no strings (Douglas 01:52-01:53). The barge's "string = 1,000" and "index coins" are dropped.
- Our year is 120 days, not 36. Rates the barge gives per day stay per day. "A month" = 30 days in both games, so monthly rates carry over unchanged. Barge dates (tax days, harvest days, festivals) move to the same place in our seasons.
- His named values stay exactly: loot 5%/10% with the 500 cap, 50% of AI loot cash to wages, quiver 50, 0.01% contest floor, 6 qualities, 5-year startup sim.

1. ONE ECONOMY, EVERY RACE
- Every race and faction runs the SAME rules: same price formation, wage formula, household spending, coping ladder, loans, treasury levers, famine stages. All paid in coins (Douglas 01:51).
- Races differ only through real data:
  - Staple tastes (barge: rice 2.2, wheat 1, millet 0.9, flour 0.6, beans 0.45). [ours] Per race: humans by region (Southern rice/millet, Middle and Western wheat, Northern barley/rye and meat); orcs meat 2.2, grain 0.6; goblins mushrooms 2.0, rats 1.0; moon elves fruit 1.6, nuts 1.6, honey 1.0.
  - Climate (spoilage and fuel follow real temperature: cold north keeps meat, hot south rots it, north burns more fuel).
  - Deposits and land (copper, tin, salt, wood decide what a town makes).
  - The ruler's traits roll the town's rules (tax in coin or in kind, tribute share, house tax, duty days), as the barge rolls counties from the magistrate's temper. Orc and goblin chiefs roll from the same table with their own traits.
  - Job tables: one pay table by job (part 3) for every race. An orc warband's ranks map onto the garrison rank pay (part 3).

1b. ASYMMETRIC FROM WORLD GEN (Douglas 02:40)
- World gen rolls every town differently, from real causes: size (hamlet, village, town, city, faction seat); soil and land per head; climate band; deposits (copper, tin, salt, clay, stone, timber); river, coast, road and pass links; race and region tastes; the ruler and his traits (tax in coin or kind, tribute share, house tax, greed or mercy).
- From those it builds the starting economy: business mix only where inputs exist; class mix (share of poor, middling, rich) and landlords; starting cash per family = poor (250 + 250 x sqrt(members)) x k, middling (1,500 + 700 x members) x k, rich (25,000 + 8,000 x members) x k, +1,500 with a business, k rolled 0.5-1.5 per family; treasury, granary and mint (seats and mining towns only).
- The 5-year startup sim then lets them drift apart for real. No town is a copy; no rule forces balance. The world Towns tab asymmetry readout shows the spread.

2. PRICING OF BRONZE COINS (replaces coinage-spec section 3 detail)
- Face value: 1 coin is always 1 coin. What moves is the PRICE LEVEL (PL): every price = base x PL; the day wage scales with PL^0.8.
- Money index = coin in circulation in the faction / the trade's need. Trade's need [ours] = population x 1,000 coins at world start. Index 1 at start.
- PL moves 2.5%/day toward clamp(money index^0.6 / sqrt(trust), 0.5, 3).
- Coin shortage = clamp((0.92 - index) x 3, 0, 0.6). It cuts labour demand by 0.3 x shortage and household spending on non-essentials by 0.5 x shortage. This IS the coin famine in coinage-spec: shown on Treasury.
- Daily drain: 0.072% of coin a day is lost, buried or worn (plus tribute sent away). Coin is conserved otherwise.
- Metal in a coin: a mint's recipe per 1,000 coins: 3.2 copper, 1.4 lead, 0.4 tin, 0.45 charcoal (barge). [ours] If lead isn't a good yet, 4.6 copper + 0.4 tin. Metal value = those inputs at today's town prices.
- Melting pays when the metal in coins is worth over 90% of face: smiths and families melt coin into bars (logged). Forgery pays when the metal is under 34% of face. Between, coins just circulate.
- Mint: 12 x 1,000 coins a day (up to 20 x 1,000 when the treasury is short), real minters (8 at 90 a day) and a master (160). The treasury keeps face minus metal. A mint with no bars casts nothing.
- Trust tends to 1 - 0.7 x debasement - 1.5 x counterfeit share. Debasement (part 4) puts less metal in each coin: trust falls, PL rises.
- Each faction mints its own coins; foreign coin spends at its metal value (coinage-spec). Coin moves between factions only with real people, caravans and loot.

3. SCALE CHECK (Douglas 01:51, 100 coins = a labourer's day)
- Barge prices are already at this scale: grain 42-70 a peck (5 kg), a person eats 0.14 peck a day, so a mouth-day of grain costs about 7, about 12 with everything else. A labourer's 100 feeds about 8 mouth-days. Use the barge base prices (part 2) for every matching good, converted to our units; price new goods against them.

4. TESTS
- World gen: report per town size, deposits, class mix, wage, staple price and treasury; spread between towns visible before and after the 5-year sim.
- Coin conserved every day (cast - melted - drained = all purses, treasuries, caravans, stashes).
- Melting only above 90% metal value; a mint with zero bars casts nothing.
- PL rises when a faction debases or mints past the trade's need; coin shortage shows in a town far from mints.
- Same rules for every race: run the 5-year sim and report, per race, wage, staple price, hunger and coin per head.
