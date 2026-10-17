BARGE MODEL PART 2 of 4: PRICES, FOOD, HOUSEHOLDS (Douglas 02:36, The Late Barge economy rules; see part 1).

1. GOODS CATEGORIES (data defaults per category; a good may override)
Category: TargetDays / elasticity / ceiling x base / perish days
- Staple: 15 / 0.85 / 14 (floor 0.45) / keeps
- Prepared food (bread, meals): 0.6 / 0.35 / 8 / 2
- Produce (fruit, vegetables): 6 / 0.6 / 8 / 10
- Meat, fish: 2 / 0.5 / 10 / 4
- Condiment 45, drink 40 / 0.5 / 5 / keeps
- Fuel: 20 / 0.7 / 8 / keeps
- Material 60, metal 45 / 0.45, 0.5 / 4, 5 / keeps
- Tool 120, weapon 90 / 0.4, 0.5 / 4, 6 / keeps
- Cloth, household: 90 / 0.45, 0.4 / 4 / keeps
- Medicine: 45 / 0.6 / 10 / keeps
- Default floor 0.35 x base. Salted meat/fish [ours]: keeps 120 days.
Base prices (coins): grain a peck (5 kg): rice 70, wheat 52, millet 42, beans 46, flour 68. Bun 3, inn meal 22. Pork 30 a catty (0.6 kg), fish 16, chicken 70. Salt 40, oil 35, wine 20. Firewood 10, charcoal 40. Planks 14, bricks 6. Iron bar 45, hoe 200, axe 260, sickle 120. Spear 700, sabre 2,000, armour 2,800. Hemp cloth 420, clothes 350, padded jacket 600. Coffin 1,500, rites 400, pig 1,600. [ours] Copper and bronze arms and our other goods priced against these (bronze ~ x1.1 copper per combat notes).

2. PRICE FORMATION (FIX-2: prices follow what people CAN pay)
- Demand = what was bought + unmet demand + 20% of what households wanted but couldn't afford. DemandEma moves 12%/day toward it, SupplyEma 20%/day. Normal stock = DemandEma x TargetDays.
- Scarcity, clamped 0.2-40: keeping goods (TargetDays / days of stock)^elasticity; fresh food (demand / (SupplyEma + 0.35 x stock))^(1.4 x elasticity). So rotting meat with no buyers falls in price.
- Target = base x PL x scarcity. Staples move together: target = sqrt(own target x base x PL x (40 / total staple days)^0.8). Made goods stay >= 1.05 x input cost.
- Price steps toward target 40%/day (prepared, meat, produce) or 22%/day (others), +-0.6% noise, clamped to floor and ceiling x PL.

3. SPOILAGE (FIX-1: rot on real days, not a 365-day clock)
- Each day: stock x min(1, rate / PerishDays) spoils. Rate follows the town's mean temperature today: 0.06 at -6 C, 0.3 at 2 C, 1.0 at 18 C, 1.5 at 30 C (interpolate). Cold north keeps meat, hot south rots it.
- Spoiled food becomes rotten food (2 a catty, pig feed). Families' larders, granaries, armies and caravans all use the same rule.

4. HARVEST
- Harvest factor rolled each year: 12% of years 0.55-0.70, 10% 1.15-1.25, else 0.9-1.1, times real weather. Two grain cuts a year (early grain, autumn grain), vegetables between.

5. HOUSEHOLD WANTS AND SPENDING (named households, every race)
- Households pay price x 1.1 (shop markup).
- Want of a good = q x clamp((P / base)^-elasticity, 0.12, 1.6). Household elasticities: salt 0.15, fuel and condiments 0.35, medicine 0.4, prepared 0.7, produce 0.8, meat 1.0, drink 1.2.
- Order: 1 staple food, 2 fuel, 3 the rest (salt, vegetables, meat, cloth, tools, bedding, light, drink, festival extras, winter clothes, medicine), rising steeply with class.
- Staple: eaters x 0.14 peck a day; under 10 eat 0.6 of that, 10-14 0.8. Jars topped toward 3 (poor), 20 (middling), 50 (rich) days x (1 + 1.5 x town fear), a fifth of the gap a day; rationing caps jars at 4 days. Staples split by share = race taste x (P / 55)^-2.6 (tastes, part 1).
- Fuel: need x (0.14 + 0.035 x members); store 2 / 8 / 25 days (x1.5 winter); the poor gather up to 40% of a day's fuel free. Short of fuel: fire only for meals.
- Budget: essentials <= min(savings, income + 35% of savings). The rest <= min(savings - essentials - rent held back, 0.9 x income - a day's rent + 1.5% of savings (3% rich)) x (1 - 0.5 x coin shortage). Luxuries cut to 30% when hungry.
- Income: every member's pay x age share: under 10: 0, 10-14: 0.2, 62+: 0.15 (answers the build's question: older children and elders DO work, at those shares). Hands under 17 hired at 0.4 of the wage.

6. HUNGER IS PER FAMILY (FIX-3)
- Hunger = 1 - staple eaten / needed (12%/day average). A family's hunger stage = max(its own shortfall stage, town stage - 3 rich, -2 institution, -1 middling). A family with a full larder is Fed whatever the town flag says. Only hungry families flee (part 4).
- A hungry farm family eats its seed last. Starvation deaths per sickness-spec 6b.

7. COPING LADDER (savings < 20, or hungry, or cold), in order
1. Pawn the bedding (winter: only when desperate).
2. Pawn max(150, 15% of possessions) for 40% of value.
3. Strip the house: sell tiles and beams.
4. County loan of 1,500 if a member earns and the treasury holds over 150,000 [ours: scaled to treasury per head]; owners may mortgage min(20,000, 30% of house value). Terms part 4.
- Grain loan: a well-off neighbour lends 6 days' grain, repaid x1.5 in kind at harvest.
- The poorest: lodging house 3 a night, temple/charity gruel [ours: the poorhouse], winter shelter, then sleeping rough, where some freeze.
- Funerals: coffin at 1.1 x price (pawning at 40% to pay), rites if affordable; the town pays a pauper's burial at 0.6 of a coffin.

8. TESTS
- Meat with no buyers falls in price; a town with full larders has no leavers.
- Spoilage in a hot town > a cold town for the same stock.
- A child 10-14 and an elder earn their age share; under 10 earn nothing.
