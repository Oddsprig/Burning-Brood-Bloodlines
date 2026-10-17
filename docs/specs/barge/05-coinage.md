COINAGE SPEC (Douglas 01:49: "redo our economy in cash like the barge, instead of gold? bronze cash coins?"). DECIDED (Douglas 01:51): BRONZE CASH, one system for every race and faction, orcs and goblins included. Replaces abstract "gold" with real metal coins. Every coin is a counted thing made from counted metal.

1. THE COINS
- The coin (Douglas 01:53): called simply COINS in the game; each is a bronze cash coin, the one coin. All prices, wages, purses, loot and treasuries in every faction are counted in it.
- Each coin holds a set weight of bronze [ours: 20 coins per bronze bar]. No strings or bigger units (Douglas 01:52): every sum is shown as plain coins ("14,200 coins").
- Rename everywhere: "gold" -> "coins" in UI, logs and the Books. Every existing money flow keeps working unchanged, just counted in coins.
- Bronze needs copper AND tin, so where tin is scarce, coin is scarce: that is real asymmetry, not a rule.

1b. SCALE (Douglas 01:51: built like Northern Song China; 100 bronze cash is about a full day's labour)
- Every base price and wage in the data rows is set so a common labourer's full day of work earns about 100 coins at world start. Everything else is priced against that day (a meal, a jar, a spear, an acre, a house). After that the market moves wages and prices for real; nothing pins them.
- Today's numbers (wages like 62, prices like 1-3) get rescaled once to this; CHANGES lists the factor.

2. MINTS (real business, state-owned)
- Each faction has mints in some towns (the head's seat, mining towns). Staff are real persons with wages.
- A mint takes real bronze bars plus charcoal and labour, and casts coins into the faction treasury. Output limited by bars in stock, workers, fuel.
- The head's rule sets how much the mint casts a month (cautious: steady; greedy: more when the treasury is short).

3. MONEY IS METAL (exact numbers for coin pricing, price level, coin shortage, melting and the mint: barge-model part 1 section 2, which wins where they differ)
- The world's coin total = everything cast minus everything melted, lost or buried. Conserved.
- Melting: when bronze bars are worth more in the market than the coins they are, smiths and families melt coin into bars (and the reverse makes minting pay). Logged in the Books.
- Coin famine: a town far from mints and tin/copper roads runs short of coin; families and businesses then pay part of wages and rent in kind (grain, cloth) and prices of goods drop. Shown on Treasury.
- Loot: coin taken in fights is real coin moving between purses (existing loot rules: 5% / 10% with the 500 cap, now in coins).

4. RACES (Douglas 01:51)
- Every race and faction uses the same bronze cash, orcs and goblins included. Every soldier of every race is paid in coins (replaces the per-culture pay form in economy spec 2). Food, beer and loot still get bought and shared, but wages are coins.
- Foreign coin spends everywhere at its metal weight.

5. SCREENS
- Treasury tab gains "The money" card (from the reference Purse tab): coin held by the treasury, by families, in caravans; cast this month, melted this month; coin famine yes/no; mint output and its bars.
- World Goods tab: copper, tin and bronze bar prices next to coin in circulation per town.

6. TESTS (headless)
- Coin conserved: cast - melted - lost = sum of every purse, treasury, caravan and stash, every day.
- No coin without bars: a mint with zero bronze bars casts nothing.
- Melting happens only when bar price exceeds coin value; minting stops when bars cost more than the coin they make.
- 5-year sim: report coin per person per town; a town with no tin road shows a coin famine and pays more in kind.
