# Lead review of the war audit

This report is preserved with its original area limitations below. The lead verified that ui/victory.gd:20 displays wins/losses, and weapon_art.gd/pixel_canvas.gd contain the equipment shading hooks. Those are not missing features. The final_result flee-array overwrite is confirmed; an unconditional union of every earlier round's fleers is not an accepted fix because a unit may return in a later engagement. Preserve true final escape identity. The combined ranking/recommendation is in [README](README.md); no fix, game or test was run here.

# War, battles and dragons — source audit at main 2c7bd93

Area snapshot `run086-095/source-doc-audit-2c7bd93/war`. Pin `2c7bd93d818810e005f7582f5687d38d1aeda5d2`. Live version `game/project.godot:10` is `0.094`. Last packaged Desktop/Android release is 0.085. This pass did not launch Godot, run tests, or treat a source reading as a runtime pass. Accepted receipts override older UNRUN worker reports.

Ordinary battles, musters, raids, sieges, dragon bodies and rider seats already exist. Findings below are breaks, limits and one unresolved measurement inside those systems.

## Findings

### 1. A large-battle fleer loses the kit a small-battle fleer keeps

- Status: confirmed source defect. Runtime unverified in this pass.
- Trigger: the army or the enemy is larger than 100, so `BattleRounds.begin` runs (`game/core/game.gd:298`). Someone's battle state is `fled`. The player wins.
- Player consequence: `Loot.spoils` strips that person's weapon, armor, quiver and carried coin. In a battle of 100 or fewer a side, the same state is skipped and the gear stays.
- Where: `BattleRounds.final_result` (`game/campaign/battle_rounds.gd:232`) copies the last round, then sets `enemy_fled` from a local empty array and `player_fled` to `[]` (`:246-247`). `Game.finish_battle` (`game/core/game.gd:327-329`) calls `Loot.spoils` (`game/core/loot.gd:47`). `spoils` continues past any unit in the fled array (`:58-60`) and never walks that array on its own. One-clash `battle.gd:1076` `build_result` fills `enemy_fled` and is not overwritten.
- Chain: round end → `battle.gd:1000` `_show_round_result` → `after_round` records fate `fled` on the round log only → last **Continue** → `final_result` → `finish_battle` loot. Fought units, including fleers, are appended in `final_result:238-244` and stay in `enemy_units` unless captured.
- Confidence: high.
- Smallest useful 0.095 scope: when building `final_result`, collect units whose round-log fate is `fled` into `enemy_fled` and `player_fled` before `Loot.spoils`. Do not retune loot odds.

### 2. A dragon that cannot fight is sent back in

- Status: confirmed source defect. Runtime unverified in this pass.
- Trigger: a multi-round battle in which a dragon is alive but `HealthReport` would say `cannot fight` (unconscious, no stance, blind, blood collapse, or a severe open wound).
- Player consequence: the dragon is eligible for every later round until it is dead. A soldier in that state sits out. The dragon is also excluded from capture, so it is neither benched nor taken.
- Where: `BattleRounds._can_fight` (`game/campaign/battle_rounds.gd:54-56`) returns `not u.dead` for a dragon unit and uses `HealthReport` only for everyone else. `fit` (`:51`) feeds `_pick_round` (`:59`). Capture skips dragons at `:126`. Human fitness rules are `Healing.fitness_from_report` (`game/sim/healing.gd:378`).
- Chain: `after_round` leaves the same Unit in the pool → `next_round` → `battle.gd:112` deploys `round_side0` → `BattleSim` fights that body again. Home-defence admission does check fitness (`dragon_combat.gd:212`), but only before the battle starts.
- Confidence: high on the branch. Whether a given wyvern wound reaches `cannot fight` depends on `bodies.json` wyvern parts, which this finding does not re-simulate.
- Smallest useful 0.095 scope: let `_can_fight` use the same fitness words for a living dragon, and keep the no-capture rule.

### 3. Small and large adults are not the same kind of army, and the measured gap is still unresolved

- Status: confirmed source numbers, plus an accepted measurement this pass did not repeat. Balance unresolved. Not a new pass/fail.
- Trigger: a player fields an adult Ruby at authored size small or large against a short human spear line.
- Player consequence: the accepted v0.093 frontier was 0 wins in 12 small-adult trials and 9 wins in 12 large-adult trials, inside 108 battles and 306 engagements. A small adult is a single body with human-scale strength. There is still no dragon shop price and no fairness verdict.
- Where: `game/data/dragons.json:40-45` sets small mass 350 kg / strength 1000 / linear 1.0 and large mass 5000 kg / strength 1300 / linear 2.4. `DragonGrowth.metrics` (`dragon_growth.gd:47-50`) and `DragonCombat._profile` (`dragon_combat.gd:54-71`) push mass, strength and reach into the native body. `docs/specs/DRAGON_PHYSICS_v0.005.txt:9-10` and `:29` say size changes strength and gem hardness does not add strike force. The 0/12 and 9/12 figures are `_evidence/FINAL-086-094.json` and `docs/validation_v086-v094.md:21`, from the merged 0.093 receipts. The 0.093 area diff changes only the version string.
- Chain: march or home defence → `battle_units` → the same `BattleRounds` pool as soldiers → native strikes use the profile. The measurement driver is not in this snapshot.
- Confidence: high that the table and the receipt say this. Low that any one stat is the whole cause. This pass did not refight the trials.
- Smallest useful 0.095 scope: none until the owner orders a balance pass. If ordered, change authored strength and linear scale only, then remeasure the existing 24 dragon trials. Do not add a price.

### 4. Off-screen wars remove people and can kill an AI dragon without a tissue fight

- Status: shipped behavior. Missing the real-sim clash in `docs/specs/ai-clashes.md:4-6`. The count resolver is the live system, so this is not "war is absent."
- Trigger: two faction warbands meet, or a militia sallies. An AI dragon has `ai_march` on one of those bands.
- Player consequence: the log reports rounds and a retreat, but survivors gain no battle wounds. Dead men are chosen by count and removed. A selected dragon is marked dead, or withdrawn, with no strike and no body log. The player's own `campaign_march` dragon is not in that AI pool.
- Where: `WorldWarbands._warband_clashes` (`world_warbands.gd:573`) calls `ClashRounds.resolve` (`clash_rounds.gd:13`, counts and morale) then `take_clash_loss` (`world_warbands.gd:50-67`). Fatal dragons call `DragonCombat._mark_death` with cause `offscreen army clash`. Militia uses `Militia._fight` (`militia.gd:298`), a power roll, then the same kind of removal. Player battles use `BattleSim` instead (`battle.gd:121`).
- Chain: campaign day → warband contact → numeric round result → random participant → roster erase or dragon death flag → `ArmsTrade.field` on the dead → `BattleRounds.retreat_band` for a surviving people-band.
- Confidence: high for the code path. The 2026-10-04 spec asked for the real sim; later performance work left this resolver in place. Do not treat the spec sentence as proof the owner still wants that rewrite.
- Smallest useful 0.095 scope: leave the count resolver. A future order can put one militia contact through `BattleSim` under the existing short-test cap. Do not convert every map clash in one version.

### 5. The town panel hides why Raid is missing and shows a garrison larger than the fight

- Status: confirmed UI limit.
- Trigger: select another realm's town on the map.
- Player consequence: the line `Garrison: N` counts every living guard and militiaman. The battle fields at most 1.25 times the army, clamped to 12–200 (`Warfare._defenders`, `warfare.gd:32-37`). After a raid, the Raid button disappears for 30 days with no sentence. The panel adds a reason only when **Besiege** is refused (`world_map.gd:873-877`).
- Where: preview refusal is `Warfare.preview` (`warfare.gd:40-54`), including the raid cooldown at `:52-54`. Buttons are built only for `ok` previews. Confirm still calls `preview` again and then `Warfare.start` (`world_map.gd:899-917`).
- Chain: town click → two `preview` calls → body text and buttons. `start` does not run until **Attack**.
- Confidence: high.
- Smallest useful 0.095 scope: print `raid["reason"]` when raid is refused, and show the preview defender count beside the full garrison.

### 6. A victory with no dragon is stored as a loss as well

- Status: confirmed source defect in the saved counter. No reader in this area.
- Trigger: `Warfare.after_battle` with `winner == 0` and `pending_battle["dragon_units"]` empty. `start_battle` always sets that array (`game.gd:288`); it is empty when no dragon was admitted.
- Player consequence: `world["warfare"]["battles_won"]` and `battles_lost` both increase. A win that included a dragon increments wins and `dragon_victories` only. A loss or draw increments losses only. Nothing in this snapshot displays the numbers. `Ambitions.check` is called (`warfare.gd:219`); `game/campaign/ambitions.gd` is outside the snapshot, so a visible ambition effect is unconfirmed.
- Where: `warfare.gd:211-214`. The `else` belongs to the dragon `if`, not to the win `if`.
- Chain: `finish_battle` → `Warfare.after_battle` → `world["warfare"]`, which is part of the world save.
- Confidence: high on the counter. Medium that a player can see it.
- Smallest useful 0.095 scope: one `else` on the win test. Confirm any ambition reader before calling the fix player-visible.

### 7. A raid's population deaths skip tracked families

- Status: shipped limit. The header in `warfare.gd:6` says the raid kills some residents.
- Trigger: the army wins a raid on a town with an economy.
- Player consequence: about 3% of `econ["pop"]` is removed from anonymous cohort age bins only (`warfare.gd:131-144`). Named household members are left out of that loop. They can still die if they were in the garrison battle. Coin, grain, loyalty and grievance do change for the town.
- Chain: win → `Warfare.resolve` → `_plunder` → `Population.kill_slots` with reason `battle`.
- Confidence: high.
- Smallest useful 0.095 scope: leave it unless the owner wants named residents in that share. Do not add a second population.

### 8. v0.091 metal finish on weapons is outside this area's files

- Status: dependency missing for a full shading claim. The accepted 0.091 receipt stands. This pass did not render.
- Trigger: a figure draws a weapon.
- Player consequence: unknown from this snapshot alone. Shields in `FigurePainter._shield` (`figure_painter.gd:1487`) call `begin_equipment`. `FigurePainter.metal` (`:331`) builds bronze, iron and steel ramps. `_draw_weapon` (`:1565`) returns immediately when `WeaponArt.draw` returns true (`:1566`).
- Where the rest is: `game/art/weapon_art.gd` and `game/art/pixel_canvas.gd` are not in this area snapshot.
- Confidence: high that those two files are required. No defect claimed against the accepted stills.
- Smallest useful 0.095 scope: none for shading unless a later visual pass is ordered. Read those two files first.

## v0.095 candidate

Restore large-battle fleer loot to the one-clash rule. That is finding 1.

Player need: the muster screen raises up to 200 (`muster.gd:74`) and rounds start above 100, so a normal field army hits the broken path. The one-clash path already keeps a fleer's kit (`loot.gd:58-60`). Owner direction in `docs/DEV_NOTES.txt` is mobilized forces of 100–200 real people. `DRAGON_PHYSICS_v0.005.txt` is the authority for a later size pass, and it does not set a win rate or a price. v0.093 left broad balance unresolved on purpose. Do not implement 0.095 in this audit.

## Stale docs

| Doc | Last actual content | Interval |
| :--- | :--- | :--- |
| `docs/DEV_NOTES.txt` | Header date 2026-10-14. Narrative stops at delivered v0.022. | From that stamp to this audit date 2026-11-06 is 23 days. The version gap is 0.023 through 0.094. `DEV_NOTES_CLAUDE_EDITION.txt` covers 0.023–0.035 and is not one of the three required docs. |
| `PROJECT_MAP.md` | Still describes `config/version="0.035-claude"` and pre-0.086 file sizes. | Same pin is now 0.094. No 0.086–0.094 section existed before this audit. |
| `CHANGES.txt` | Before this append, a 0.086–0.094 catch-up header only. | No per-version war entries until this audit. |

No merge calendar for 0.086–0.094 is in the area notes. Those versions are accepted ancestors of this pin (`docs/validation_v086-v094.md`). Packaged players are still on 0.085.

## What this pass could not see

`game/campaign/diplomacy.gd`, `game/campaign/ambitions.gd`, `game/campaign/census.gd`, `game/art/weapon_art.gd`, `game/art/pixel_canvas.gd`, and the v0.093 test harness. Truce behavior at the war call sites is confirmed; the predicate body is not in this folder. No runtime result was produced here.
