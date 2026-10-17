# Legendary items (Douglas OK'd 2026-10-06 22:31)
- A quality tier above masterful: Legendary. Only a smith at legendary skill can make one, rarely, in an inspired
  moment; the player cannot order one.
- Each is unique and named: "(name), legendary (material) (item)", e.g. "Oathbreaker, legendary copper sword".
- Every legendary piece has a real gem set in it (pommel, crossguard or another fitting spot), shown in BOTH the
  icon/sprite and the description. Gems are real goods (add them if missing; gem deposits go with ore deposits).
- Records entry: maker, carriers, kills. Quality value 3.0 (DF artifact) vs masterwork 2.0, through the same physics.
- Worth a fortune; can be looted or stolen; a town that loses one remembers.
- Current masterwork chance at skill 15: ~45% (Factory.roll_quality: round(N(skill/3-0.6, 0.8)) clamped 0-5).

## CHANGE (Douglas 22:35): the odds, exactly
- Masterwork curve: skill 10 stays ~1.4% per piece (today's value); skill 15 drops to 10% (from ~45%), smooth in
  between; lower qualities shift down naturally. Re-fit Factory.roll_quality.
- Legendary: a skill-15 smith has a 1% chance per piece; EVERY smith can make one on the same curve shape scaled
  down (default: legendary chance = masterwork chance / 10 at every skill, so skill 10 ~0.14%).
- Lifetime cap: each smith (a real person) makes at most 5 legendary pieces in their life.
- Replaces "only legendary-skill smiths". Naming and gem rules stay. Tests: chances at skills 10 and 15; cap of 5.

## CHANGE (Douglas 22:36): "legendaries are never lost in battle. - even ai keep them and equip them if they win a fight."
- Never destroyed, never lost to the loot drop chance: when a carrier falls, the winning side always takes it.
- Same code for the AI: an AI winner keeps it and equips it on its best fitting fighter.
- Every change of hands goes in the item's history. Test: always survives and passes to the winner (player and AI).

## CHANGE (Douglas 22:37): "tune up the mastercraft too - maybe 25% for a skill 15"
- Masterwork anchor: skill 15 = 25% per piece (replaces 10%); skill 10 stays ~1.4%; smooth between.
- Legendary stays 1% at skill 15, so legendary chance = masterwork chance / 25 at every skill (skill 10 ~0.06%).
- Lifetime cap of 5 unchanged. Tests follow these numbers.
- (22:37 "the curve follows from those points too") The whole masterwork curve follows from 1.4% at skill 10 and
  25% at skill 15: the same ratio per skill point (~x1.78), so ~11: 2.5%, 12: 4.4%, 13: 7.9%, 14: 14%, and it keeps
  falling smoothly below 10. Legendary = that curve / 25. Lower qualities follow from the same refit.

## CHANGE (Douglas 23:00): gems come from mining
No gem mines: every ore mine has a small chance per work unit of hitting a gem pocket; the gem kind follows the real
rock (common quartz/amethyst, rarer garnet, sapphire, ruby, emerald). Gems are traded goods, set into legendaries,
bought by the rich. Starting chance logged in DEV_NOTES as tunable.
