NOT CLEAN
Static read-only review of Sol's 8 fixes vs RELEASE_PLAN v0.103 and muse_build_v0103; no Godot/test run (task rule, pasted in test_tutorial_v103.gd:11-12).
Sources read in bb-v103 worktree by absolute path (staged copy was empty; shell sandbox unavailable, so byte-level tab scan not repeated).
MEDIUM | game/ui/settings.gd:50 | Auto-resume also fires when Settings is used as an in-battle overlay (overlay=true, header lines 4-5); a half-finished tutorial then hijacks that overlay. Fix:
```diff
-	if Game.tutorial_step > 0 and not Game.tutorial_done:
+	if not overlay and Game.tutorial_step > 0 and not Game.tutorial_done:
```
LOW | game/ui/tutorial_overlay.gd:193 | get_minimum_size() includes the custom_minimum_size set at line 194, so box width ratchets and never shrinks for shorter later steps (cosmetic; placement still clamped). Fix:
```diff
-	var box_w := minf(maxf(440.0, _box.get_minimum_size().x), maxf(240.0, size.x - 32.0))
-	_box.custom_minimum_size = Vector2(box_w, 0.0)
+	_box.custom_minimum_size.x = 0.0 # measure content, not last layout's forced width
+	var box_w := minf(maxf(440.0, _box.get_minimum_size().x), maxf(240.0, size.x - 32.0))
+	_box.custom_minimum_size.x = box_w
```
NOTE | game/ui/settings.gd:50 | An unfinished run left at step 0 never auto-resumes; unavoidable without a saved "started" flag (step 0/not-done is also the never-started default), so Sol's >0 guard is the right call, not a defect in the fix.
Fix 1 save-resume binding CORRECT: tutorial.gd:83-87 preserves save on fresh bind, 106-114 respects tutorial_done; design (mirror on start/advance/finish) intact.
Fix 2 settings resume CORRECT (except MEDIUM above): settings.gd:122-138 bind then replay()/start_saved(), Replay still resets to step 0 (119-120, tutorial.gd:102-103).
Fix 3 inactive overlay CORRECT: tutorial_overlay.gd:105-108 hide in _process, 159-164 open-before-start invisible, 317-320 hide on completed even when auto_free=false; children hidden with parent take no input.
Fix 4 screen-change survival CORRECT: game.gd:85-87 show_screen (queue_free old, main.gd:54-65) precedes screen_changed, so overlay:302-309 reparents to main.current before the free lands; _show_step deferred (312) lets the navigating button's remaining pressed callbacks (wired later, 285) run first.
Fix 5 phone sizing CORRECT: overlay:193-209 places by actual clamped box size with side fallback; UiKit.button gives 96px targets on mobile (kit.gd:6,74-79), box relayouts on minimum_size_changed (61).
Fix 6 clipped/hidden targets CORRECT: overlay:217-234 canvas-transform rect intersected with every clip_contents ancestor and the viewport; 248-276 skips hidden/queued controls; 237-245 deferred ensure_control_visible reveal; 182 recomputes on resize.
Fix 7 button identity CORRECT: overlay:285 binds the pressed button, 288-291 requires button==_target and reports the step anchor, so a mismatched done.anchor can no longer be impersonated (such data was unusable anyway: a different button sits under the dim).
Fix 8 touch release CORRECT: overlay:36,122-140 records per-index allowance at press; release/drag reuse it across step changes, gestures starting under the dim are marked handled.
Test (2) SOUND: _click (63-86) pushes real viewport mouse+touch in v083 order, no pressed.emit; _layouts (89-112) checks encloses/centre/dim-area/box-on-screen for StepOne/Two/Three (186,210,230), all shipped Settings anchors (333-340) and phone-mobile all three (433-435) at 1280x720, 1920x1080, 2340x1080.
Test (2) SOUND: each step proven waiting (198-202, 223-226, 231-235), Back/Next/Done/Skip/Replay via GUI input (211-279), save/load incl. resume-after-load and old save (281-313), inactive/clipped/hidden (384-409), identity (414-422), real Game.goto survival for screen+button kinds (447-480).
Test (2) NOT VACUOUS: negative controls (187-195) plus positive controls after completion (242-246), and runner.gd:80-88 counts SCRIPT ERRORs and returns fails as exit code; blocks.json:3-5 registers tutorial_v103 once. Only soft spot: screen_changed.emit at 224/227 simulates one hop, but 447-480 covers real goto.
Duration: by design only (~21 layout waits of 0.15s, two 0.35s polls, empty-world saves, no worldgen) far under 180s/watchdog; unmeasured, as Sol states.
Symbols (3) VERIFIED: Game.tutorial_step/done/main/_active_screen (game.gd:54-62), goto/screen_changed (78-87), _save_tree/_write_save/load (1083,1122-1128,1173-1175), UiKit.*, set_mobile_override(null) idiom (runner.gd:140), push_input/DEVICE_ID_EMULATION (test_touch_scroll_v083.gd:17-30), get_global_transform_with_canvas/ensure_control_visible/set_anchors_and_offsets_preset are stock Godot 4 APIs.
Parse risks (3) NONE FOUND in the 4 files: only cast is parenthesised (overlay:305), no typed arrays assigned from untyped sources, every := is on a literal/constructor/typed return (minf/clampf/Rect2/int/get_*), full reads show tab indentation and no leading-space indents.
Unchanged neighbours agree: game.gd writes tutorial in _save_tree and defaults it on load; tutorial.json anchors ReplayTutorial/Toggle_battle_event_slowmo exist in settings.gd:115,186.
Runtime acceptance (Godot parse, input propagation order, measured duration) remains for the controller's single authorized headless run; a failure there stops all further tests.
Files changed by me: only this report, muse_review_v0103_fixes.md in my work folder. No source edits, no Godot, no git.
