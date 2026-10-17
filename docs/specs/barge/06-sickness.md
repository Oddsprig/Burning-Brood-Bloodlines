SICKNESS SPEC (Douglas 00:53: "A SICKNESS TAB FOR DISEASES ETC."). New sim work: real diseases in real people. Feeds the town screen's Sickness tab, the census and life histories. Values marked [ours] are starting defaults; after the 5-year startup sim, show Douglas the numbers (cases, deaths per town per year) and do NOT tune silently.

1. RULE: roll the person. Every case is one register person with a disease, a start day and an end day. Nobody is sick in a summary only. Every death has a cause on the person, the family history and the census.

2. DISEASE ROWS (data; adding one = one row)
Fields: name, how it spreads (contact / foul water / bad food / cold / wound), incubation days, sick days (min-max), bed-ridden share (can't work), death chance per sick day for child / adult / elder, immunity after (life / N years / none), season and climate weights, race multipliers.
Starter rows [ours]:
- The flux: foul water and crowding, worst in summer and hot towns. Kills children and elders. No immunity.
- Marsh fever: hot and wet seasons, river and coast towns. Comes back in bouts. Immunity a few years.
- Winter cough: cold homes (firewood at 0, poor winter clothing), elders and the hungry. Winter only.
- The pox: contact only, never starts by itself, enters a town only with a carrier. Children hit hardest. Lifelong immunity for survivors.
- Camp sickness: armies and crowded camps in the field, poor food. Hits soldiers and the company.
- Wound rot: an open wound left untreated (existing tissue wound record) can go bad. Soldiers, battle survivors, the company.
Races: orcs and goblins resist the flux and camp sickness; elves resist the pox; trolls resist all [ours, per race row].

3. WHO CATCHES IT (risk per person from real state, no flat rates)
- Conditions: people per home (crowding), poorhouse, barracks, homeless, family hunger, firewood days, winter clothing, age, season, climate, river or coast.
- Contact: sick people in his household (strongest), the town's share of people sick, his workplace (business staff, garrison, caravan crew).
- Carriers: a person who is incubating keeps travelling. Caravan crews, armies, refugees, recruits and the player's company carry diseases between towns. A town's first case records where it came from ("came with the wool caravan from Ashford, day 131").
- The pox and other contact-only diseases enter the world only through a carrier from beyond the map edge (rare world event, logged).

4. CADENCE (cheap)
- Per person store disease id, start day, end day, and outcome rolled at infection (recover or die on day X). Rolled in the family turn (weekly per family); the elapsed days are resolved at once from the stamps.
- Town pass reads only counters (sick now per disease, new this week, deaths), updated on each change.
- Forces on the map roll on their own turn the same way.
- Perf gate: sickness adds < 0.5 ms to the worst campaign day at 20 towns x 150 families.

5. EFFECTS (through existing systems)
- A bed-ridden person doesn't work: no wage while sick. The family's income falls, so hardship, debt and the recruit pool react on their own.
- Businesses lose staff (short-handed tag). The garrison loses men on duty (roster shows "sick").
- Deaths: the person is removed by the existing death rules (inheritance, extinct house, property to the state). The census counts deaths by cause.
- Recovery gives immunity per the row.
- Company men in a sick town catch it at that town's real risk. A sick unit can be left in camp. If fielded [ours]: END x0.75, STR x0.85, fatigue gain x1.3, focus -10% (inside the existing focus cap). The unit card shows the disease and days left.

6. HEALERS AND REMEDIES (real goods)
- New business row: herbalist. Workers gather herbs (needs tools, no land) and make remedies. Remedies are a market good (Market tab, Made goods).
- A sick person whose family buys a remedy: sick days x0.7 and death chance x0.5 [ours]. Families buy only if they can afford it after food, so the poor die more. That comes from the economy, not a rule.
- Bandages (if already in supplies) treat open wounds and stop wound rot from starting; untreated wounds roll it.
- The company can buy remedies in town for its own sick.

6b. STARVATION (Douglas 01:27: people starve to death)
- Each person keeps a body-condition meter fed by his family's real food (same idea as the company's belly and mass rules). Each day the family goes short, the meter falls; children, elders, the sick and nursing mothers fall faster [ours]. Fed days refill it.
- Low condition raises every disease's catch and death chance (the hungry die of the flux and winter cough first).
- At zero the person dies of starvation, cause "starved", in his life history, the family log, the census and the Fights/Books logs if a raid or siege caused the shortage.
- Who eats first is the family's choice by culture row (default: workers, then children, then elders [ours]).
- Test: a town cut off from food loses people to starvation and hunger-driven sickness, worst in the poorest families; a fed town loses none to starvation.

7. SICKNESS TAB (town screen)
- Header: sick now, bed-ridden, new this week, deaths this season, share of the town sick. 60-day chart of sick now.
- Disease rows: name, sick now, new this week, deaths this season, rising / falling, where it came from. Tap -> the sick people (name, age, family, day N of M, remedy yes/no; tap -> person page), by age band, by home.
- Homes hit hardest: households with the most sick (tap -> family).
- Remedies: stock, price, herbalists and their staff.
- Deaths list this season: person, age, cause (disease or starved).

8. CENSUS AND OTHER SCREENS
- Census row adds sick and deaths by cause.
- Register member line shows "<disease>, day N" when sick. Overview shows sick now. Roads marks a neighbour town with an outbreak (from caravan word, not omniscient).

9. TESTS (headless, blocking)
- No case without a source: conditions or a contact or a carrier (each case stores its source).
- Contact-only diseases never start in a clean, isolated world.
- A caravan with an incubating crew member seeds a clean town; the first-case origin is recorded.
- Immunity holds for the row's duration.
- A bed-ridden person draws no wage; the family's income drops by exactly that wage.
- A/B worlds: crowded, hungry, cold towns get more cases than comfortable ones.
- Every death carries a cause in the person, the family history and the census.
- Remedies reduce sick days and deaths in an A/B test; remedy stock is conserved (bought and used, never spawned).
- 5-year sim: no negative counts, no NaN. Report cases and deaths per town per year in CHANGES.
