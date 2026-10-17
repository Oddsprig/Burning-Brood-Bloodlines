BARGE MODEL PART 3 of 4: LABOUR, PAY, BUSINESSES (Douglas 02:36, The Late Barge economy rules; see part 1).

1. THE DAY WAGE (FIX-5, FIX-6)
- Labour demand per town = porters (caravans and barges loading) + builders (season x1.2 in warm months, x0.25 deep winter, + wall repair + public works hands) + carters + FARM FIELD HANDS + mines and works short of staff. x (1 - 0.3 x coin shortage).
- Day wage = clamp(100 x (demand / labourers)^0.3, 55, 140) x PL^0.8. Moves daily.
- Each labourer is hired with chance min(1, demand / supply).
- Field hands get 1.15 x the day wage from the farm family, so farms hire FIRST, not last (fixes 38% of land unworked). Planting and harvest hire before anything else in those weeks.
- Land per hand: [ours] keep 8 acres a hand with an ox, 4 without (barge fields are Chinese-garden scale and don't carry over); harvest needs 2x hands for its days, filled by family members at age shares (part 2) and hired hands.

2. PAY TABLE BY JOB (every race; coins a day at start, x PL^0.8 after)
- Shops and works 70-120: grain shop 95, smith 110-115, bowyer 120, physician 110, baker 80-90, greengrocer 70; mine 110, woodcutter 85, fisher and hunter 70, herb gatherer 55. Hands under 17 x0.4.
- Cottage trades float (start): tailor 60, cobbler 55, baskets 45, joiner 70, gardens 55, street food 45.
- At home: spinning 20 (poor) / 10 (middling) x (0.7 + 0.3 x clamp(cloth price / base, 0.5, 1.6)); servants 18-35.
- Self-employed: merchant 115 (260 rich), carter 90, scribe 70, innkeeper 70, other 50; each x prosperity x random 0.6-1.4, prosperity = clamp(employment x (2 - 0.6 x food index), 0.3, 1.4).
- Town posts (paid only while the treasury holds over 3 x the day's bill): deputy 200, registrar 150, sheriff 150, master of the mint 160, clerks 60, granary clerks 70, runners 45, watchmen 60, jailers 60, teachers 80, minters 90.
- Other jobs: homemaker 20, farmer 60, labourer 75, porter 80, carter 85, servant 40, official 260, landlord 280, headman 180, monk 15, beggar 14, miner / charcoal burner / sawyer 80, any other craft 95.

3. SOLDIER PAY (matches Douglas 01:47-01:49 exactly, adopted for every race)
- Rank base a day: recruit 70, soldier 100, sergeant 150, officer 240, deputy 360, commander 500, plus rations.
- PLUS 5 a day per grade of skill with the weapon he serves with, grades 0-10 = our skill ladder up to Legendary. A Legendary footman earns 100 + 50.
- Orc and goblin rank trees (orc span 5) map onto the same six bases, lowest to highest. Same coins.
- Unpaid, hungry men desert when morale falls under 0.38.

4. RECIPES AND LABOUR VALUE
- Staff factor = staff / target (a family shop counts its keeper: (staff + 1) / (target + 1)).
- Output valued at 0.92 x price, inputs at price. A recipe runs fully only if output >= 1.03 x inputs, else at most 20% of capacity.
- Makers aim at today's demand + a tenth of the gap to normal stock, split among all makers.
- A short input is substituted by a good of the same group, value for value.
- Value per hand = (out x 0.92P - in x P) x batches / hands; shown on the business page as COST PER UNIT (town-screen spec part 1).

5. HIRING AND LAYING OFF
- Below target, a business hires if Thriving, or it made over a day's wage yesterday, or its output is scarce and it has cash or profit. It takes a labourer aged 14-55, from its own town first. A real person from the register, never invented.
- Loss days > 20 (> 10 when cash < 0) and staff > 1: the last hand taken on goes, keeper's kin last. He goes back to day labour.
- Cottage trades: members share 95% of net; wage moves 10%/day toward each share. Every 10 days a trade paying under 30 with more than 2 members loses one to day labour; one paying over 75 with scarce output (price > 1.25 x base) gains one.
- At 15 a son takes his father's trade 70% of the time, else the family business or his walk of life. Hands-work jobs retire at 62.

6. BUSINESS BOOKS AND HEALTH (town-screen Businesses tab reads these)
- Margins: shop 0.12, stall 0.30. Households' P x 1.1 is split among open sellers.
- Rent and upkeep a day: own building 4 + 1.5 x staff; let: monthly rent / 30 to the landlord family; no record: 20 + 6 x staff. Sales tax 3% (up to 5%); licences (wine 15% of takings, pawnshop 900 a month x PL).
- Keeper's living: min(wage x 1.1, max(0, cash + 15 days of wages)), x0.4 in debt. Keeper's take: above 60 days of (wages + rent) he draws 8% of the excess a day; debt first: 10% a day of cash above half the buffer.
- Loss day +1 when profit < -0.3 x staff x wage, or the 14-day average < -0.25 x wage; else -1. STRUGGLING above 12 loss days; THRIVING when the 14-day average > 0.4 x staff x wage; else STEADY. 120 days of history kept.
- Selling to stay open: cash < -(30 days' wages) - 3,000: keeper sells a spare house to the town at half value. Nothing to sell: CLOSES, all let go. Also closes when the keeper dies with no heir.
- Reopening: after 25 days closed, only if expected margin > 0.8 x wage + rent. New keeper: the old one, a journeyman, or the labourer with the most savings. Town loan of 30 days' expected margin if the treasury holds twice that. Reopens Struggling with half staff.
- Producers (mines, woodcutters, fishers, hunters, herds) never close for want of cash.

7. TESTS
- Every hire and every staff member resolves to a register person (no invented people).
- Farm hands hired before porters at planting and harvest; land worked >= 90% in a normal year.
- A labourer family of 5 (1 earner at the day wage + spinning) covers staple, fuel and rent at base prices with money left: report the margin per race.
- A Legendary footman earns rank base + 50.
