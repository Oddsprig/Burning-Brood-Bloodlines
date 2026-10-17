# SPEC: militia, contracts, monsters wave 1 (Douglas picked 2026-10-04 18:19)
Tags: [DF] Dwarf Fortress inspired, [ours] our own, tune and flag. Concepts, not numeric targets.

## Build now (wave 1)
### A. Creatures on the existing tissue sim, as data
No HP and no special-case combat. A creature = body plan + tissue layers + natural attacks + tokens + size + rarity.
1. Body-plan data for non-humanoids: quadruped now; format able to hold multi-head and long-neck plans later (hydra, dragon). Parts carry relsize so dumb targeting stays weighted by part size.
2. Hide tissue layers: fur, thick hide (scale later) with their own shear/impact values [DF-style, tuned].
3. Natural attacks: bite, claw, gore, charge (momentum from body mass x speed). Bite-and-hold (latch) reuses the existing grab code, so a latched wolf can drag a man down. Orc/troll bites already exist; reuse.
4. Tokens per creature: NOPAIN, NOSTUN, NOEXERT, NOFEAR, FAST_HEAL (flags, most unused in wave 1).
5. Rarity field on every creature type: common / uncommon / rare / epic / legendary. Drives spawn weight and bounty size. Hydra = epic, dragon = legendary.
6. Morale default [ours, flagged]: ordinary animals use normal morale and can break when maimed. Monsters/megabeasts NOFEAR, never rout (fixed).
7. Combat log lines for natural attacks (bite, latch, gore, charge, shake) in the data-driven template style.
Wave 1 creatures (human ~70,000 cm3 for scale):
- Wolf [DF]: ~40,000 cm3, packs 3-7, fast, bite + claw (edged), latch. Metal stops teeth well; a severed leg cripples one. Common.
- Bear [DF grizzly]: ~200,000 cm3, bite + claw, strong enough to punch through mail. Solitary. Uncommon.
- Wild boar [ours]: ~human-sized or a bit smaller, charge + tusk gore, groups of 2-4. Common.

### B. Bandits and deserters (humanoids, existing sim)
Rule: every non-monster unit on the map belongs to a specific home town and faction.
- Bandits belong to a bandit camp: a small town-like map site of an outlaw faction. It keeps stock from what its bands raid, re-equips from that stock, and can be cleared as a lair. Destroyed when cleared; a new camp can appear elsewhere later.
- Deserters keep their original town and faction, flagged as deserters and hostile to it. Gear is their old faction's.
- Any human region's gear; same outfitting system as other warbands. Loot = existing gear-value gold rule.

### C. Militia [ours, BB-like]
- Every town has a militia, sized by town size and wealth, belonging to that town and faction.
- Equips from its own town's stock (until the economy design lands, use the town's existing smith output/quality).
- Campaign map: a small static sprite (no animation) that patrols near its town.
- Auto-fights bandits, raiders and animals near town (off-screen auto-resolve OK); losses reduce it, it rebuilds over days.
- On "defend the town" contracts it deploys on the player's side as AI allies; pay bonus for fewer militia deaths.

### D. Contract types (reuse board, map, pay formulas)
- Hunt: a wolf pack or boar group plaguing a village; roams near the village.
- Clear the lair: a lair marker on the map (bear den, bandit camp). Battle map uses lair terrain with choke points (impassable/rough tiles).
- Defend the town: incoming raid; fight beside the militia.
- Bandits / deserters: enemies on the road or at their camp.
- Bounty: a named target (pack leader, bear, bandit chief) whose reward grows the longer it lives. Rarity scales it.
- Escort: caravans (built).
- War contracts against other factions WAIT for the diplomacy design.
Pay: humanoid enemies keep the gear-value gold rule. Creatures carry no gear: pay = contract fee + trophies (hide, fangs, heads) that auto-sell as gold in the aftermath.

### E. Spawning on the map [ours]
- Sparse by design: monsters are a sight, not traffic. Density is a share of wild map area.
- Gradual: a campaign starts with animals and bandits only; later waves unlock over campaign time and fights; each new type starts rare. Rarity weights spawns.
- Creatures live in lairs in the wilds (forest, hills, marsh, caves), away from towns. Animals roam near their lair; big ones mostly stay put until a contract points the player at them. A cleared lair stays empty for a while.
- No fixed numbers; expose density and unlock pacing as tunables.

## Later waves (hooks now, content later; do NOT build yet)
Wave 2: troll lair/bounty; giant troll; giant; giant spider (web grab, venom); ogre; ettin; minotaur. Ours: gullet worm, mire grabber, kiln tortoise, tin-gnawer, marrow hounds.
Wave 3 megabeasts, multi-tile bodies: Hydra [DF] EPIC (seven heads, NOFEAR/NOSTUN/NOPAIN/NOEXERT, severed heads stay off, heals fast between fights, bounty rises); Dragon [DF] LEGENDARY (no wings, breathes fire as a natural attack: line/cone, burn damage type, ignites grass, shields block most).

## Tests and notes
- Full headless suite stays green; add tests: wolf latch pulls a man down via the grab code; bear bite can penetrate copper mail; boar charge momentum scales with mass x speed; militia spawns per town with home town/faction set; every non-monster map unit has a home town and faction; bandit camp re-equips from its stock; spawn density scales with wild area.
- Perf: creatures through the 50v50 perf gate.
- Change notes list [ours] tuned values.
