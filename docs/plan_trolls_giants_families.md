# Plan: Trolls & Giants as Families Inside Orc and Goblin Factions

**Status:** IMPLEMENTED v0.071  

Owner approved this plan for v0.071. Trolls and giants are rare heavyweight families inside orc and goblin towns. They fight on foot only: no horse and no dragon rider. `troll_den` is `minor_only` and is not a sovereign realm. Old saves with no family race stay the town race.
**Target Scope:** `factions.json`, `races.json`, `economy.json`, `EconGen`, `Population`, `Persons`, `Families`, `Recruits`, `People`, `Army`, `WarAI`

---

## 1. Recommendation

**Yes — trolls (and future giants) should be rare heavyweight families inside `orc_horde` and `goblin_warren` settlements rather than standalone world-map factions**, with `troll_den` either retired from default campaign faction generation or kept only as a non-imperial monster lair archetype.

Why this fits Burning Brood's simulation model:
1. **Scale & Rarity:** At `size_mult = 1.48` (`H = 33`), `str = 18`, `con = 18`, and `food_mult = 2.2`, a town of 120–250 trolls (`troll_den` in `economy.json`) creates an army of 25–40 giant shock-troops that distorts both the food economy and battle line balance. Making trolls 1–2 minority families per Orc camp (`orc_horde`) or Goblin warren (`goblin_warren`) turns them into prized heavy bruisers embedded inside greenskin warbands.
2. **Tactical Synergy:** Orcs (medium-heavy infantry) and Goblins (numerous light skirmishers) naturally benefit from 1–3 towering foot-only line-breakers (`troll` / `giant`) without needing a separate diplomatic polity.
3. **Dynasty & Bloodlines:** Because every town resident is a `Person` belonging to a `Family` (`e["fams"]`), modelling trolls and giants as specific families preserves full birth, aging, inheritance, grudge, and recruitment traceability.

---

## 2. What Would Change in Factions & Town Economy

1. **`game/data/factions.json` & `game/campaign/campaign_world.gd`:**
   - Remove `troll_den` from the standard sovereign faction roster (or mark `"minor_only": true`), folding its map territory into `orc_horde` and `goblin_warren`.
   - Add an optional `"minority_families"` array to faction definitions:
     - `orc_horde`: `[{"race": "troll", "families_per_town": [1, 2], "roles": ["hunter", "guard", "laborer"]}, {"race": "giant", "families_per_town": [0, 1], "roles": ["herder", "guard"]}]`
     - `goblin_warren`: `[{"race": "troll", "families_per_town": [1, 1], "roles": ["guard", "miner"]}]`
2. **Per-Family Race Ownership (`game/econ/econ_gen.gd`, `game/econ/families.gd`):**
   - Currently, `EconGen._make_families` and `Population.make_person` read `var race := str(e.get("race", "human"))` at the town level, stamping every family in a town with a single race.
   - Change `EconGen._make_families` to store `"race": fam_race` on each family dictionary (`f["race"]`) and use `Data.races[fam_race]["surnames"]` + `Data.races[fam_race]["names_m" / "names_f"]` when seeding members.
   - Update `Population.make_person(e, rng, fid, ...)` and `Persons.births` so a newborn or generated person inherits `fams[fid].get("race", e.get("race", "human"))` instead of always using `e["race"]`.
3. **Marriage & Reproduction (`game/econ/persons.gd`):**
   - In `Persons.marriages`, filter candidate spouses by matching `p["race"] == q["race"]` so troll/giant families marry within their own race (or across neighboring settlements' troll/giant families) rather than producing unintended hybrid race assignments with goblins or orcs.

---

## 3. What Would Change in Recruitment & Muster

1. **Town Mercenary Pool (`game/campaign/recruits.gd` & `game/econ/people.gd`):**
   - `People.sync_recruits(town)` already copies `p["race"]` from the town `Person` onto the `Unit` (`u.race = str(p.get("race", town.get("race", "human")))`).
   - Update `Factory._gen_town_unit` and `Recruits` pricing so units from troll/giant families:
     - Roll attributes and body plan from their own `u.race` (`troll` / `giant`), not `town["race"]`.
     - Carry a higher hiring fee and daily wage reflecting their `food_mult` (`2.2x` for trolls, `3.0x` for giants) and combat power.
     - Spawn with heavy two-handed clubs, mauls, or cleavers (`Factory.roll_gear`) and never roll cavalry titles or mounts (`Horses.can_mount_race(u.race) == false`).
2. **Warband Muster (`game/campaign/army.gd` & `game/campaign/mobilization.gd`):**
   - When an `orc_horde` or `goblin_warren` settlement musters a warband, `Army` drafts eligible fighting-age men/women across town families. Because troll/giant families are 1–2 households out of ~18–30 families, each mustered greenskin warband will organically include 1–3 trolls/giants alongside 20–35 orcs or goblins.
   - Cap heavyweight units (`size_mult >= 1.4`) at a maximum share of a warband (e.g., `<= 15%` of headcount) so a small warband does not muster as all-troll if orc families are depleted.

---

## 4. What Would Change in Campaign & Battle AI

1. **Campaign Provisioning & March Speed (`game/campaign/war_ai.gd`, `game/campaign/supplies.gd`):**
   - `Supplies` must account for per-unit `food_mult` when computing warband daily rations so greenskin warbands fielding trolls/giants carry enough meat/grain before marching.
   - In `Horses.band_day`, AI warband horse-buying already skips `troll` and `giant` (`not Horses.can_mount_race(u.race)`), keeping them strictly on foot.
2. **Succession & Ruler Selection (`game/campaign/dynasty.gd`, `game/data/factions.json`):**
   - `orc_horde` uses `"succession": "strength_duel"`. Because trolls (`str: 18, con: 18`) and giants have much higher base strength than orcs (`str: 14`), raw attribute scoring or 1v1 duel simulation would cause troll minority families to almost always usurp chieftaincy of Orc clans.
   - **Rule change needed:** Restrict faction ruler/chieftain eligibility to the faction's primary `"race"` (`orc` for `orc_horde`, `goblin` for `goblin_warren`), while allowing troll/giant family heads to serve as champion bodyguards or warband lieutenants.
3. **Battle Deployment & Target Priority (`game/sim/battle_sim.gd`):**
   - Deploy troll/giant fighters in the front shock line of orc/goblin formations rather than the flank skirmish or archer slots.

---

## 5. Risks & Mitigations

| Risk | Cause | Mitigation |
| :--- | :--- | :--- |
| **1. Goblin Warren Starvation** | `goblin_warren` towns have small peasant bases (`pop: [140, 260]`) and low food surplus; a large troll family (`food_mult: 2.2`) can drain the granary in winter. | Assign troll families in goblin warrens to food-producing roles (`hunter` / `herder`) or cap troll household size at 2–4 adults in warrens. |
| **2. Extinction of Tiny Minority Pool** | With only 1–2 troll/giant families in a town, endogamy rules (`Persons.marriages` forbidding same-family marriage) will block all marriages if there is only 1 troll family in town. | Allow marriage between minority families across allied/same-faction towns, or seed at least 2 unrelated troll families per settlement that hosts them. |
| **3. Chieftain Usurpation in `orc_horde`** | `strength_duel` succession favors `troll` / `giant` base stats (`str 18+`) over `orc` (`str 14`). | Gate ruler succession to `p["race"] == faction["race"]`; trolls/giants can be clan champions but not warchiefs. |
| **4. Equipment & Armor Slot Mismatch** | Town smithies craft armor for the town's majority race; human/goblin-sized mail or helmets look wrong or over-equip giants. | Restrict `giant` equipment to natural hide/scrap/loincloth and oversized clubs, and keep `TrollArt` using its rounded organic bare/scrap/leather silhouettes. |
| **5. Save/Load & Legacy `troll_den` References** | Existing tests (`test_races_v065.gd`, `test_world_v031.gd`) reference `troll_den` in `factions.json`. | Keep `troll_den` in `factions.json` as an non-spawned/lair entry or update faction count assertions simultaneously when implementing. |
