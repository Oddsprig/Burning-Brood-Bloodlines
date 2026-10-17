# Spec 1: domestic animals, dwarves, Eastern humans
(Douglas picked 13:05 2026-10-06. Builds on the living-herds design already in the game. Queued after v0.011. No test runs; checks go in TO_TEST.txt.)

## A. Domestic species: 8
Use these 8 in the existing herd system (counts per owner+species, age/sex groups, weekly tick, real feed, breeding, disease, dynamic prices). If the build already has some of them, keep its versions and add the rest.

| Species | Products / work | Feed and land |
|---|---|---|
| Cattle | oxen draught, milk, beef, hides | most grass + hay, lowlands |
| Horse | draught, riding, pack | heavy feed, slow breeding, a wealth animal |
| Sheep | wool, mutton, milk | cold-tolerant, needs winter hay |
| Goat | milk, meat, hides | scrub, hills, dry or hot land, poor feed ok |
| Pig | meat, lard, leather | scraps + forest mast, fast breeding, no milk |
| Poultry (chickens + geese as one) | eggs, meat, feathers | scraps and grain; feathers are a good used in arrow fletching |
| Dog | guarding, herding, hunting | no meat; owners with dogs lose fewer animals to wolves and thieves |
| Donkey/mule (one entry) | pack + draught, mountain roads | hardy, poor feed ok |

Starting herd mix per race (shares at world gen only; after that, owners buy/sell/breed by market and land, so mixes drift):
- Middle humans: cattle, pigs, poultry, sheep, horses, dogs.
- Northern humans: sheep and cattle first (wool for cold), horses, dogs, few pigs. Long winters make hay the limit.
- Eastern humans: horses and goats heavy, sheep, poultry, dogs; few pigs and cattle (dry, hot open land).
- Orcs: pigs first, goats, dogs, few cattle.
- Goblins: goats, pigs, poultry; no horses or cattle.
- Moon elves: horses, goats, sheep, poultry; few meat beasts, kept long.
- Dwarves: goats, sheep, pigs, poultry, donkeys/mules; cattle only where a hold has valley land; almost no horses.

Animals stay off the battlefield for now (no mounts, no war dogs in combat).

## B. Dwarves (new race + faction)
- A small, long-lived mountain people. Holds sit in mountains on good ore. Hold count scales with world size the way goblin warrens do (build picks numbers per size; start near goblins' 5 on Large).
- Every dwarf is a real person in a household and town register like every other race (one person, one household).
- Biology through the existing race-biology birth model: long life (DF dwarves live ~150+ years), slow births per married woman, below humans. Natural rate from biology and conditions, not a plugged rate; if numbers explode or collapse, report, don't cap.
- Body: stocky and strong, short limbs (shorter reach). Use the existing anatomy and attribute system; tune by race attribute ranges, no special combat rules.
- Economy: full barge economy like every race. Mountains feed them poorly, so holds import grain, wood and charcoal and export metal, tools and arms. This is a natural trade route, not a scripted one.
- Homes and buildings from stone. State buildings show on the map like other factions'.
- Steel: dwarves start with full steel know-how (Spec 2).
- Diplomacy: standing with every faction at start, like orcs and goblins (not auto-hostile to the player). Trade-minded.
- Recruiting: dwarves enter the normal recruit pool under the same desperation rules (rare because holds are few and dwarves are seldom desperate). Douglas has not answered this; it's the recommended default, and he can overrule it.

## C. Eastern humans (new human culture + faction)
- Placed in the east: dry, hot, open land (steppe and hills). Climate comes from the existing latitude/season rules plus a dry eastern band.
- Uses the Eastern human rank ladder already written in the economy spec.
- Herds: horse and goat heavy (above). Crops suited to dry land through the existing crop/weather system.
- HUMAN CULTURES ARE ONLY FACTIONS AND CULTURE. Humans of any culture (Middle, Northern, Eastern) migrate between human towns, marry across, and change allegiance freely through the existing migration and fleeing rules. Culture sets a person's start (names, homes, herds, ranks), never a wall.
