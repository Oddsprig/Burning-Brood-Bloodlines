ADDENDUM 1 to the town screen and economy plan (message 13; Douglas 02:57-02:59, after the 12 files). Read with the 12 files; where this says it overrides one, this wins.

OVERRIDES
- 07-land-map.md: the plot card and USE overlay show state buildings (A) and herds (B); "pasture (with herd)" means the herd records in B.
- Town screen Overview: add a "Town buildings" card (A) and a Herds line (B4).
- economy-ideas.md section 7 (livestock) is replaced by B and is DECIDED. The rest of economy-ideas.md is still an unpicked menu.

A. STATE BUILDINGS (Douglas 02:57: hard to tell where the town's own properties are)
- The town's own buildings are real plots held by the state. Each is a record: name, who runs it (a person), staff (persons, wages paid by the treasury), residents (a household), beds or capacity, stock, upkeep a day, condition, history.
- Every town has: the KEEP (seat of the head of town; his household lives there), TOWN HALL (officials and clerks, the chest, loans register, land book), BARRACKS (single soldiers' household, beds), ARMORY (arms stock vs target), GRANARY, THE SHELTER (state house for the homeless: a bed at 3 coins a night, cheap meals, free gruel while the gruel kitchen is open, see barge-model-4; when full, people sleep rough; the ruler's traits set how generous), JAIL. Seats and mining towns also have the MINT. Market square, wells, walls and gates are town land too.
- Every race has the same roles with its own look and names (orc chief's longhall, goblin warren den, elf lodge).
- Map: each state building has its own sprite (tower, scales, crossed swords, shield, granary, bowl, bars) on a slate-blue tile with a gold edge, drawn in EVERY overlay so they are always easy to find. A STATE overlay chip dims everything else and labels each one.
- "Town buildings" card on Overview and Land & Homes: one row per building with what it is doing now (beds 18 / 30, bowls served today, spears vs target) and who runs it (tap). Tap -> its page: staff, residents, stock, upkeep this month, history.
- Test: every town has keep, hall, barracks, armory, granary, shelter and jail as state plots; barracks and shelter residents are register persons; their staff wages show in Treasury accounts.

B. HERDS AND BUTCHERS (Douglas 02:59: "we also need farm animals, who owns the pasture and the animals, and who processes them (butchers etc) for businesses"). Same rules for every race.

B1. ANIMALS ARE COUNTED (NEW SIM)
- Every herd is a record: kind, head count by age (young, grown, old), OWNER (a family, a business or the state), the pasture or pen plots it uses, the herder(s) who tend it (persons).
- Kinds [ours]: cattle and oxen, sheep, goats, pigs, hens. By race: Northern humans more sheep and goats; orcs boars and goats; goblins cave goats and rats; moon elves goats and bees. All are data rows.
- Herds change only through real events: spring births per grown female, old age, sickness (cattle plague and others, as sickness-spec rows), cold, hunger, slaughter, sale, and theft (bandits and armies drive herds off as loot). Each loss is logged with its cause.
- Feed: grazing per head per acre by season. Winter needs stored hay or fodder (barge: fodder takes 0.5 field an ox, 0.1 a pig). Overgrazed pasture yields less next season. Short of fodder, owners sell or slaughter first; then animals starve.
- What live animals give: milk (to the dairy), wool (shearing in summer), eggs, manure (raises field yield), and draft work: oxen plough (8 acres a hand with an ox, 4 without, barge-model-3) and pull wagons.
- Small family stock: a poor family's pig or hens (barge: a pig adds 3 a day, an ox 6).

B2. WHO OWNS WHAT
- Pasture plots are owned like any land: a family, a landlord who rents it to a herder, or the town's common pasture, where any town family may graze a few head for a small fee to the treasury [ours].
- Animals are goods with prices in the market (barge: pig 1,600; [ours] ox 6,000, cow 4,000, sheep 500, goat 400, hen 30), and the price follows supply and demand.
- Drovers (a business) walk herds between towns along roads; they can be raided.

B3. BUSINESSES THAT PROCESS THEM (family-kept, hire real people, real wages)
- Herder: tends its own or other families' herds, hires herdsmen.
- Dairy: milk -> cheese and butter.
- Butcher: a live animal -> meat + hide + tallow + bones. Buys from the herd owner at the market price. The slaughter peaks in autumn before winter fodder runs short. Yields per head [ours]: ox 200 kg meat and 1 hide; pig 70 kg; sheep 20 kg, 1 skin.
- Tanner: hides -> leather. Chandler: tallow -> candles. Salter: meat + salt -> salted meat, which keeps. Wool goes to the weaver.
- Each shows its chain on its page: which herds it bought from, and where its output went.

B4. SCREENS
- Land map: pasture and pen tiles show a herd sprite; the plot card shows each herd on it (kind, count, owner, herder) and how many head the plot can carry this season.
- Overview: a Herds line (cattle, sheep, pigs, goats, hens; fodder days left).
- Market: animals as their own row group in Raw.
- Family page: the animals it owns. Businesses tab: herders, dairy, butchers.
- World Goods: herd counts per town.

B5. TESTS (headless)
- Every animal belongs to exactly one herd with an owner.
- Herd counts change only by births, deaths with a cause, slaughter, sale or theft, and every change is logged.
- Butcher output = animals slaughtered x yield.
- A pasture never carries more than it can feed; when fodder runs out, deaths are logged as starved.
