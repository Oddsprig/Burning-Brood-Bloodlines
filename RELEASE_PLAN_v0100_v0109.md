# Release plan: v0.100 to v0.109

Written 2026-11-07, after the user's review of the store page and the game. The game is not ready to sell yet.
The ten versions below take it there. One goal per version, and every version goes up by 0.001.

## Rules for every version

- **Helpers allowed:** Muse Wonder (full, high), Sol 6.1 max, Argon 4.0, Grok 4.7 high. Never Gemini of any kind, and never Google's Opus 5.5. At most 3 helpers at once. Claude checks the results only.
- **Testing rules:** paste these word for word into every helper task and test brief:
  "run only one Godot game test at a time on the user's PC (several at once crashed it), headless. Before starting any game test, check for other running Godot or Unity processes (from any project or helper); if any are running, queue the test and wait until they have finished before starting it. Every test must finish in under 3 minutes. These rules must be pasted word for word into every helper task and test brief."
- **The user's PC copy:** never touch .work\bb-v059 (it has uncommitted changes). Sol works only in .work\bb-v097.
- **Needs the user's OK first:** deletes, force-pushes, the listing going live, and the name and mascot.
- **Every merge:** normal merge and normal push to origin main. Update PROJECT_MAP.md, docs/DEV_NOTES.txt and CHANGES.txt, add a test-results receipt, then a post-merge docs commit that records the merge hash.
- **Every version is done only when:** the official suite (tests/run_full_suite_headless.ps1 list, plus that version's new test) passes. The only failures allowed are the ones listed as failing the same way on main. Sol 6.1 max red-teams each change before merge.

---

## v0.100: Older tests, autosave and archers (in progress)

- **Goal for the player:** saves never come out half-copied, and archers fight back when an enemy falls beside them.
- **Already done:** branch `v0.100-old-tests` (commit 5b46af9).
  - The autosave copy is safe if the world changes mid-copy.
  - The siege preview no longer writes to the world.
  - An attack waits for the save to finish.
  - Archers draw the sword against a fallen foe beside them.
  - 11 older tests were updated to today's rules, and tests/test_fixes_v100.gd is new.
- **Still to do:**
  - Find why claude_intrigue_v032 (child death and adult census) and the balance_v070 mount bands failed in the v0.100 suite run. Both passed on v0.099; a comparison run on main is under way. If v0.100 caused them, fix it (most likely the archer change for balance).
  - Finish the run of the remaining older tests, about 175 of 312.
  - Write the receipt that lists each older test as fixed, failing the same way on main (with the reason), or a helper script that isn't a test.
- **Files:** core/save_snapshot.gd, campaign/warfare.gd, campaign/marriage.gd, sim/archery.gd, tests/*.
- **Done when:**
  - The official suite passes, with only the known main failures.
  - test_fixes_v100 passes.
  - The receipt covers all 312 older tests.
- **Who:**
  - Grok 4.7 high runs the remaining older tests.
  - Sol 6.1 max red-teams the diff.
  - Claude checks and merges.

## v0.101: Red-team review of v0.098 to v0.100

- **Goal for the player:** nothing from the last three versions breaks a campaign.
- **Work:** Sol 6.1 max reviews v0.098, v0.099 and v0.100. This is the review that was owed but blocked while the PC link was down. Fix every confirmed finding and add a test for each one.
- **Files:** whatever the findings touch, plus tests/test_review_v101.gd.
- **Done when:**
  - Every finding is fixed with a test, or rejected with a written reason.
  - The suite passes.
- **Who:**
  - Sol 6.1 max reviews.
  - Argon 4.0 fixes.
  - Claude checks.

## v0.102: A small house can rise from nothing

- **Goal for the player:** a house that does not rule its town can start with nothing and end with troops and a household army. Every step is possible and clear.
- **Work:**
  - Script and play the whole path for a non-ruling house: earn or borrow coin, hire or raise men, fund and muster a household army, and march.
  - Fix every blocker or dead end found. Known risks:
    - Adults away in the realm's field army leave no one free to ride.
    - The purse is empty at the start.
    - The Army screen explains nothing when muster is refused.
  - Every refusal must say what to do next.
- **Files:** campaign/mobilization.gd, campaign/house_onboarding.gd, ui/muster.gd, the Army screen, campaign/dynasty.gd.
- **Done when:**
  - The new test tests/test_small_house_path_v102.gd plays the path on 3 seeds, from a non-ruling house to a raised household army, in under 3 minutes.
  - Every refusal message names the next step.
- **Who:**
  - Grok 4.7 high writes the path test and finds the blockers.
  - Argon 4.0 fixes.
  - Sol red-teams.

## v0.103: Guided tutorial system

- **Goal for the player:** a tutorial that walks you through step by step, highlights the button to press, and waits until you do it. It replaces "read these pages".
- **Work:** build a tutorial engine.
  - Steps are written as data (data/tutorial.json): which control to highlight, a short line of text, and what counts as done (a screen opened, a button pressed, a state reached).
  - An overlay dims the screen, cuts out the highlighted control, and points at it with an arrow and a small text box.
  - It has Next, Back and Skip tutorial.
  - It works with mouse and touch, and on Windows and Android screen sizes.
  - Progress is saved. Settings has "Replay tutorial".
- **Files:** new ui/tutorial_overlay.gd, new campaign/tutorial.gd, data/tutorial.json, core/game.gd (settings), ui/settings.
- **Done when:** a test drives a 3-step sample tutorial and checks:
  - the highlight sits on the right control at 1280x720, 1920x1080 and a phone landscape size;
  - each step waits for its action;
  - Skip and Replay work;
  - progress survives save and load.
- **Who:**
  - Muse Wonder builds it.
  - Sol red-teams.
  - Claude checks the screenshots.

## v0.104: Tutorial chapter one, from a small house to a household army

- **Goal for the player:** a new player who picks a small house is led step by step through the v0.102 path. They choose the house, read the purse, find men, fund and muster the household army, and march to a nearby town.
- **Work:**
  - Write the chapter in data/tutorial.json, about 10 to 15 steps.
  - Offer it on the first new campaign.
  - Keep the Help pages as a reference, not as the tutorial.
- **Files:** data/tutorial.json, ui/newgame.gd, ui/house_select, Army and map screens (highlight anchors).
- **Done when:**
  - A test plays the whole chapter on a fresh campaign and finishes with a raised household army.
  - Screenshots of every step are in test-results/v0.104/ for the user to look at.
- **Who:**
  - Muse Wonder writes the steps.
  - Grok runs the playthrough test.
  - Claude checks the screenshots.

## v0.105: Clear battles, without the fear-circle clutter

- **Goal for the player:** you can see what is happening in a big fight.
- **Work:**
  - Turn the fear circles off by default, or make them small and short.
  - Cut the floating FEAR and ROUT words to one small marker per man, and fewer when many men break at once.
  - Add a setting: battle markers Full, Light or Off.
- **Files:** battle/readability_fx.gd, the battle screen, the settings screen.
- **Done when:**
  - The 100-on-100 screenshot with a dragon reads clearly: before and after pictures are in test-results/v0.105/.
  - The marker setting works and is saved.
  - Battle frame time is no worse.
- **Who:**
  - Argon 4.0 builds it.
  - Claude checks the pictures.

## v0.106: One new dragon (prototype for the user's OK)

- **Goal for the player:** dragons look like the centre of the game.
- **Work:**
  - Draw one dragon breed in code from smooth, shaded shapes: body, neck, head, two wings, tail and legs. The parts can be drawn as SVG in the Oddsprig 2D Asset Studio or in code.
  - Rig it with Godot bones (Skeleton2D) and give it these animations: standing, walking, wing beat, flying, breathing fire, hurt and death.
  - The saddle and rider hang on the base-of-neck bone, so they can never sit on the wings.
  - Show it side by side with today's sprite in the roost and in battle.
- **Cause of today's saddle problem:** v0.072 added art/rider_fit.gd. Its anchor_px() puts the saddle "just tailward of the higher wing root" instead of using the v0.066 neck-base seat point (seat_px). Battle and the mount preview read that anchor, so the rider moved back onto the wings. The v0.066 seat data itself was never changed.
- **Guard test:** tests/test_saddle_neck_base.gd. For every breed and pose, the saddle point must lie between the neck root and the front edge of the wing root, never behind it. The rider must be drawn in front of the near wing. The test joins the official suite, so any later change that moves the saddle fails it.
- **Reference:** the earlier saddle work in project files v0066/v0066_dragon_seat_closeup.png, v0066/v0066_dragon_before_after_*.png and the v0062 and v0063 spirewing mount images.
- **Files:** new art/dragon_bone_rig.gd, art/dragon parts (SVG or code), battle/dragon_view.gd (behind a switch), art/rider_fit.gd.
- **Done when:**
  - A test checks that the saddle point stays on the neck-base bone in every animation frame.
  - The prototype pictures and a short recording go to the user.
  - **The user OKs the look before v0.107 starts.**
- **Who:**
  - Muse Wonder draws and rigs it.
  - Sol red-teams the rig.
  - Claude checks.

## v0.107: Every dragon breed on the new rig

- **Goal for the player:** every dragon, at every age, looks and moves like the approved prototype, everywhere it appears.
- **Work:**
  - Move every breed and age stage to the bone rig, with each breed's own colours, horns and wing shape.
  - Use it in the roost, the Dragons list, battle, mounted battle, the map token and the mount preview.
  - Remove the old cut-sprite path only after the user OKs it, because removing it is a delete.
- **Files:** art/dragon_bone_rig.gd, art/dragon_art.gd, art/dragon_rig_art.gd, art/sapphire_spirewing_art.gd, battle/dragon_view.gd, ui/dragons screens, art/map_tokens.gd.
- **Done when:**
  - The saddle test passes for every breed.
  - Battle frame time with 2 dragons and 200 men is no worse than v0.106.
  - A contact sheet of every breed is in test-results/v0.107/.
- **Who:**
  - Muse Wonder does the breeds.
  - Argon 4.0 hooks them into every screen.
  - Sol red-teams.

## v0.108: New name, mascot and store pictures (the user decides)

- **Goal for the player:** a name and a key-art mascot the user is proud of, and store screenshots that show the real game.
- **Decision point:** the user picks the name and the mascot. Helpers may draft options, but nothing changes until the user picks.
- **Work after the pick:**
  - Rename the shown name (project, window title, title screen, Windows exe details, Android label). Keep the save folder name so old saves still load.
  - New key art and icons.
  - New screenshots: a fair battle (dragons on both sides, or none), the new dragons, the tutorial, the court and the map.
  - Update the store page.
- **Files:** project.godot, main.gd, ui/title.gd, export_presets.cfg, icon files, the store page design.
- **Done when:**
  - The user OKs the name, the mascot and each screenshot, one by one, as single full-size pictures.
  - The release test checks the new name everywhere.
- **Who:**
  - Muse Wonder makes the art and screenshots.
  - Claude makes the code changes and checks.

## v0.109: Release candidate 2

- **Goal for the player:** a build worth $7.99.
- **Work:**
  - Run the full official suite and the older tests.
  - Make the Windows .exe and the signed Android .apk.
  - Run a smoke test of both, and test on a real Android phone if the user can.
  - Finish the store page with the version number and file sizes.
- **Files:** export_presets.cfg, tools/build_release.sh, the store page.
- **Done when:**
  - The suite passes with only the known main failures.
  - Both builds start a new game and finish the tutorial chapter.
  - The user gives the final OK before the listing goes live.
- **Who:**
  - Grok runs the tests.
  - Claude makes the builds and the store page.
  - Sol does a last red-team pass.

---

## Decision points for the user

1. OK this plan before any building starts.
2. After v0.106: OK the prototype dragon's look.
3. Before v0.107 removes the old dragon art: OK the delete.
4. v0.108: pick the new name and mascot, and OK each store screenshot.
5. v0.109: final OK before the listing goes live.
6. Still open from earlier: the "Claude Edition" decision card (the new name in v0.108 settles it).
