# FOOD AND DRINK SPEC (Douglas picked "Core + fav drink", 2026-10-04)
All numbers are starting values to tune. Hooks into existing needs, stress, morale, fatigue, mass and encumbrance; don't change those systems' own weights.
Runs without the full economy: fixed prices, every enemy army "well supplied".

## 1. COMPANY STOCK
- Stash holds food (meals), beer (mugs), wine (cups). Integers, each lot with an age in days.
- Spoilage: food spoils at 21 days, beer at 30, wine never. Eat oldest first.
- Bought at town markets: price and stock come from the market. Until the economy build lands, use fixed base prices: meal 1, beer 1, wine 3 (gold).
- Company screen: "Food: N days", "Drink: N days" at current rations. Warn (one banner) when under 3 days or anyone is Hungry. No per-man feeding UI.

## 2. RATIONS (two company-wide settings)
- Food: Short = 1 meal/man/day, Normal = 2 (default), Feast = 3.
- Drink: Dry = 0, Ration = 1 mug/man/day (default), Free = each man's want (sec 5).
- Meals at morning and evening ticks (Short = evening only; Feast = morning, midday, evening). Drink in the evening, plus 1 morning mug under Ration/Free.
- Out of stock: men get what's left, spread evenly; the rest go without.
- Wine counts as 1.5 mugs. With Ration/Free, serve each man his favourite if stocked (sec 6), otherwise whatever there is.

## 3. BELLY METER (per unit, 0-100)
- Each meal adds +35 (cap 100).
- Digestion drain per campaign day, spread across the day's ticks: march 50, rest/town 30. Battle: -10 extra at battle end.
- Belly mass: +0.5 kg per 35 belly (belly/70 kg). Add it to body mass for the momentum, grab and encumbrance math. A stuffed man is about 1.4 kg heavier.
- States:
  - Stuffed 85-100: fatigue gain x1.10, walk ticks/tile x1.05, morale +3
  - Fed 40-85: no penalty, morale +5
  - Hungry 15-40: fatigue gain x1.15, focus -5%, morale -5
  - Starving 0-15: fatigue gain x1.35, END counts x0.75, morale -15, stress +5/day
- "Morale" here = start-of-battle morale modifier. Focus stacks with the needs focus but the total stays inside the existing +-15% cap.
- Body mass loss: each day ending Starving, body mass -1.5% (floor 85% of rolled mass). Each day ending Fed or Stuffed, regain 1% up to the rolled mass. Lower mass feeds torque and grab weight through the existing size math. Sprite scale is unchanged.

## 4. DRINK NEED (the existing "Drink" need)
- Met by any mug or cup that day. Days unmet in a row: 1 = focus -3%, 2 = -6%, 3+ = -10% (inside the +-15% cap), plus stress +3 each day from day 2.
- Races with Appetite median 35 or lower (elves) take x0.5 of these penalties.

## 5. BUZZ METER (per unit, 0-100)
- Each mug adds +12 x (70 / body kg)^0.5. Wine adds 1.5x that.
- Wears off: -4 per campaign hour; during battle -0.1 per tick.
- Want under Free: mugs/day = 1 + Appetite/25, rounded (Appetite 50 = 3, 80 = 4). Trolls and orcs end up Drunk most nights; that's intended.
- States:
  - Tipsy 10-30: morale +5, pain tolerance x1.10
  - Drunk 30-60: morale +10, pain x1.20, KIN and FOC x0.90
  - Hammered 60+: morale +15, pain x1.25, KIN and AGI x0.75, 2% chance per move tick to stumble (lose that move)
- "Pain tolerance" multiplies whatever WIL/END pain threshold already exists.
- Hangover: if buzz reached 30+ in the evening, next day "Hung over" = focus -10%, fatigue gain x1.10. Clears at the next evening tick.
- Battle morning: the morning mug lands right before a battle that day. Ration usually gives Tipsy; Free gives heavy drinkers Drunk.

## 6. FAVOURITE DRINK
- At recruitment each man rolls Beer or Wine. Odds by race: human N 70/30, orc 85/15, goblin 80/20, moon/high/dark elf 25/75, troll 90/10.
- Each day he gets his favourite: morale +3 and stress -1. Never getting it does nothing extra (no penalty).
- Shown on the unit card next to favourite weapon/material.

## 7. TOWN FEAST
- In a town with a tavern: "Feast the company" button. Cost = 3 meals + Free drink per man at town prices.
- Effect: belly to 100, Make merry need met, stress -15, everyone gets the night's buzz (likely Hung over next day).

## 8. ENEMIES AND MONSTERS
- Same states and effects, no daily sim. At battle spawn set each enemy's belly and buzz from its army's supply:
  well supplied: belly 50-80; short: 20-40; starving (besieged, raided): 5-20.
  buzz: orcs 20-50, goblins 10-40, humans 0-25, elves 0-10, trolls 30-70.
- Until the economy build exposes supply levels, use "well supplied" for all.
- Beasts and monsters: belly only (default 20-50, hungry packs), no buzz, no drink need.
- Militia: their town's supply level.

## 9. UI
- Unit card: small belly bar and buzz bar with the state name. Tap = state's effects.
- Company screen: ration toggles, days of food/drink, warnings.
- Battle log lines from real state (data-driven, varied), e.g. "{name} swings drunkenly", "{name}, half-starved, gasps for breath", "{name} roars, too drunk to feel it", "{name} stumbles over his own feet".

## 10. TESTS (headless, blocking)
- Normal rations keep a marching man Fed indefinitely.
- 3 days with no food => Starving, mass drops, floor holds at 85%.
- Ration drink: no drink-need penalty; Dry for 3 days: focus -10% and stress applied.
- Free drink with Appetite 80 => Drunk at the evening tick and Hung over next day.
- The focus total never goes past +-15%.
- Enemy spawn sets belly/buzz in range per supply level and race.
- Recruit vs recruit stays about 50% when both sides are Fed and sober.
- 50v50 worst tick stays under 2 ms.

NEEDS FROM THE ECONOMY BUILD (later): food, beer and wine as market goods (price and stock per town, moved by caravans), and a supply level per AI army or town readable at battle spawn.
