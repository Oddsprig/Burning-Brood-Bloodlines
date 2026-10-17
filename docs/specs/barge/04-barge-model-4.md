BARGE MODEL PART 4 of 4: TREASURY, LOANS, LAND, FAMINE, TRADE, WAR, MOVERS (Douglas 02:36, The Late Barge economy rules; see part 1).

1. TOWN TREASURY (every race; the ruler's traits pick greedy / steady / merciful)
- Income: sales tax 3% of shop takings (up to 5%); licences; house and land tax each tax day = value x 0.0008 x (1 + surcharge), institutions free, shortfall becomes tax arrears (2% a month, 4 instalments); farm land: tribute share of harvest (in coin or in kind by the ruler's roll: in kind 1/12-1/8, coin 1/30-1/15); duties 3% of caravan cargo in and out, gate toll 2% (up to 5%) of village sales; fines 150 / 600 / 3,000 by class; deed tax 4% (x1.5 greedy); service money monthly 40 / 150 / 1,200 by class x scale (1.0-1.6) x PL, poor excused in bad years, or 2 days' labour a month instead; the mint (part 1).
- Spending: garrison pay if cash > bill + a reserve, else owed and repaid later; salaries if cash > 3 x the bill; garrison rations from the granary; public works each month, more when rich (a great work hires extra day labour); tribute to the faction; relief, poorhouse (14 a person a day), pauper burials, loans.
- Short (cash under its line, garrison unpaid, or tribute overdue): each month gate toll +0.5 pt, stall rent +5, mint +1,000/day, service money +0.1. Full: eased back.
- Surcharge on house tax on tax days: need = half a year's tribute + garrison pay + works + overdue. On when cash < need (x1.6 greedy, x0.75 merciful): a fifth if under half of need, else a tenth. Off above 1.8 x need. Landlords pass half into rents. A fifth with 12%+ of owners unable to pay brings crowds (unrest).
- Crisis: forced loan from the rich (up to 15% of savings, every 30 days at most, repaid when flush); debasement 10% (up to 30%) when cash is near empty and the garrison unpaid 2+ days.
- [ours] Treasury lines (barge YS: start 420,000, short under 250,000, full over 800,000) scale by population: lines = barge value x town people / 8,000.

2. GRANARY (every town)
- Filled by 5% of the town's harvest and tribute grain. Sells when the staple index > 1.3 and it holds stock: daily demand x clamp((index - 1.2) x 0.6, 0.05, 0.5) at the relief price 55 x PL. Buys at index < 0.85 when the treasury is comfortable: 8% of daily demand at 45 x PL.
- Rationing below 9 days of the town's grain (lifted above 15). Gruel kitchen at index > 1.9 or poor hunger > 0.3: 0.07 peck a person. Brewing ban at index > 1.9 (lifted below 1.4).

3. LOANS AND COURTS (rates a 30-day month)
- Small relief loan 3.5%, instalment amount/8 + 3%. Mortgage 2.5%, /24 + 3%. Reopening loan 2.5%, /8 + 3%. Business loan 3%, /3 + 3%, due in 90 days. Tax arrears 2%, a quarter.
- Business loans only if the last 7+ days average a profit and avg x 30 >= amount/3 + 3%. A losing shop lays a hand off before borrowing. Pledge: its building (0.5 of value), tools and stock (0.6), another house (0.5). Refused under 500 or above a third of the treasury.
- Missed = under half paid. Court after 3 misses (families) or 6 (businesses): savings and 35% of possessions seized, then the pledged house (family stays as tenant if it can pay, else evicted). Now and then a clerk takes 15% of an instalment to wait a month (Books).
- Family debt to neighbours or lenders grows 0.2% a day; repaid from money above 5 days' income.

4. HOMES AND LAND
- Plot worth = m2 x (ground + building) by kind (barge land-book table); value moves 10% every 3 days toward base x housing tightness (0.6-2.2, empty homes vs homeless) x prosperity x safety x condition.
- Rent = value x 0.008 a month (x(1 + 0.5 x surcharge)). Behind on rent: 1 landlord in 5 takes it in labour, others wait 2 months (some 4), then evict.
- Pledge of the house (dian): a family with nothing left gets 50% of value (35% in famine) from a rich family who uses the house; they rent a room back at 40% of rent and redeem for the same sum when they hold 1.15 x it.
- Distress sale: value x clamp(0.85 (0.55 famine) / (1 + 0.1 x recent sales), 0.3, 0.95); debts paid first, family rents back.
- Who owns their home, by class: rich 1.0, middling 0.85, farmers 0.8, merchants 0.7, craftsmen 0.6, soldiers 0.35, labourers 0.25. Others rent from the town's rich landlords. A landlord's field is worked by a poor farm family for half the crop.
- Farm harvest order: tribute, neighbours repaid, seed kept, food to next harvest, surplus sold to a broker at 0.75 x P.
- Seized ground is listed at worth, 5% less every 6 days, down to 0.4.

5. FAMINE STAGES (town and family)
- Fed, Short, Want, Famine, Starvation, Collapse. Worse by a stage per 2 days of shortfall; better by a stage per 2 fed days (Short to Fed needs 7 days' store). Deaths a day 0.75% / 3% / 5% (capped 4%), taken as real persons per sickness-spec 6b. Work output x 1 / 0.95 / 0.8 / 0.6 / 0.4 / 0.25. Unrest over 0.62: riots break into the granary.

6. MOVERS (FIX-8: money and people go somewhere real)
- Flight: hungry families only (part 2), 0.4% x (stage - 1) a day. They walk to a real town of their faction or a friendly one, carrying their purse and goods; the coin arrives with them (conserved). Refugees spec handles the road.
- [ours] Moving in: a town with empty homes and a day wage over the region's average draws families each month from towns with low wages or hunger. New households take empty houses (labourers shacks, farmers farmsteads) or lodge with the poor.

7. TRADE AND MERCHANTS
- A merchant moves a good when the price gap beats carrying by 5% of base. Carrying a km, share of worth x bulk: road 2%, pack 2.4%, mountain path 4%, river 0.5%; porters x1.25. Tolls 3% at each town seat entered, 1% a ferry; quarrelling factions add 6% or shut the road. Broker's cut 3%. Merchant family gets a quarter of profit; credit 0.5 x (purse + goods out) - 1.2 x debt. Bust below max(500, 35% of start); prosper above max(15,000, 1.3 x start): buys a wagon 3,500, mules 2,400.

8. WAR AND BANDS (FIX-4, FIX-7)
- Armies are raised only from real people: a drive takes up to 40 men aged 17-30, labourers first. If nobody can be spared, the army is smaller or not raised. Never invent families.
- Call-up pay: 1.5-2.5 days' wage to sign on, a day's wage per fight, a day more if won. Braves leave after 3 unpaid days; militia desert 12% a day unpaid. Hired bands 25 a man a day.
- Army food: 6 days from granaries, buys at home, forages in enemy land (up to 5% of a town's grain) and burns villages.
- Buying off a host at the gates: 15-27% of the defenders' treasury; peace bought before war 8-14%. Ransoms: officers 80-140, men 10-20 (x PL) [ours: ransomed men go home alive, which slows war deaths].
- Bands: road tolls, quarterly tribute up to 2% of grain and 4% of treasury, robbery 20-80% of a load.

9. TESTS
- 5-year sim: population, treasuries, wage, staple price per town per year; land worked %; leavers by destination; no person created outside births.
