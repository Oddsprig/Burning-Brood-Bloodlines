NOT CLEAN
Static review complete: eight findings fixed. Runtime acceptance remains unverified because the task forbids Godot/game tests.
Locations below refer to the final files; initial findings and two requested progress updates were recorded during work.
- HIGH | FIXED | game/campaign/tutorial.gd:83: binding overwrote saved progress; fresh binding now preserves it and start_saved respects completed saves.
- HIGH | FIXED | game/tests/test_tutorial_v103.gd:89: only one target was checked and pressed.emit bypassed input; tests now use viewport mouse/touch with positive/negative controls, all three targets/sizes, and shipped Settings anchors.
- HIGH | FIXED | game/ui/tutorial_overlay.gd:159: inactive/retained-completed overlays blocked screens; they now hide immediately and release input.
- MEDIUM | FIXED | game/ui/tutorial_overlay.gd:217: cut-outs ignored clipping and hidden cached anchors; visible geometry, hidden-anchor resolution, resize refresh and deferred scroll reveal are corrected.
- HIGH | FIXED | game/ui/tutorial_overlay.gd:300: real Game.goto freed the overlay with its host; it now follows the replacement screen, preserving navigating button callbacks.
- MEDIUM | FIXED | game/ui/tutorial_overlay.gd:288: a press impersonated a different done.anchor; notification now reports the highlighted control actually pressed.
- MEDIUM | FIXED | game/ui/tutorial_overlay.gd:193: placement assumed 440px despite larger themed minimums; layout now uses the actual box size and side placement when needed.
- HIGH | FIXED | game/ui/settings.gd:50: saved progress had no UI resume caller; reopening Settings resumes unfinished steps above zero; explicit Replay still resets to step zero.
- MEDIUM | NOT FIXED / NOT RUN | game/tests/test_tutorial_v103.gd:9: Godot compilation, runtime input/layout, screenshots and measured under-180-second duration need the controller's authorized run.
Input hardening also preserves an allowed touch's release across step changes and blocks gestures beginning under the dim; regressions check both GUI presses and raw touch delivery.
Coverage added: Next/Back/Done/Skip/Replay, action gating, saved/new engine resume, skipped save reload, old saves, inactive/retained overlays, clipping, hidden anchors, phone theme/tap sizes and real screen replacement.
Read-only validation: both JSON files parse; tutorial_v103 registers the correct test once; referenced resources exist; four scripts pass tab/delimiter/cast-pattern scans. Manual symbol/signature and type-inference review found no additional defect; this is not a Godot parse pass.
Reviewed unchanged: game/core/game.gd writes tutorial fields through synchronous and sliced-save paths, resets new campaigns and defaults absent old-save fields; game/data/tutorial.json and game/tests/blocks.json remain unchanged.
Runtime budget by design: tiny UI fixtures, finite loops/short waits, empty-world saves, no world generation; actual duration is unmeasured.
Changed files: game/campaign/tutorial.gd; game/ui/tutorial_overlay.gd; game/ui/settings.gd; game/tests/test_tutorial_v103.gd; test-results/v0.103/sol_review_v0103.md.
No Git, Godot, engine/game/GPU tests, downloads, installations, deletions or uploads were performed.
