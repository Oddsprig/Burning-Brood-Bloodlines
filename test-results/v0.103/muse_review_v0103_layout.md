CLEAN

# Red-team review: v0.103 tutorial layout fix (Sol) — Muse, read-only

Scope: `game/ui/tutorial_overlay.gd`, `game/tests/test_tutorial_v103.gd`,
`test-results/v0.103/sol_fix_tutorial_layout.md`, plus callers/hosts
(`game/ui/settings.gd`, `game/ui/settings.tscn`, `game/core/game.gd`,
`game/main.gd`, `game/campaign/tutorial.gd`, `game/ui/kit.gd`,
`game/data/tutorial.json`). No game or test files were edited. No Godot or
game test was run by this review (per brief); the headless PASS is taken from
the controller, and supersedes Sol's own report, which was written as
static-only ("runtime validation pending", sizes labelled static predictions).

## Findings

1. **Diagnosis correct. Severity: none (confirmed).**
   `game/ui/tutorial_overlay.gd:52` replaces the anchors-only call with
   `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`. Godot 4's
   `set_anchors_preset()` (default `keep_offsets`) preserves the control's
   current rect by recomputing offsets against the *parent's current size*:
   for the fresh zero-size overlay, `_ready()` runs only after the deferred
   `host.add_child.call_deferred(overlay)` (`tutorial_overlay.gd:45`) against an
   already-sized host, so offset_right/bottom became -host_w/-host_h and the
   overlay stayed 0x0, thereafter growing only by resize deltas. That poisons
   `_layout()`'s early-out (`:183`) and `_compute_rect()` (`:224-225`), so the
   dim/box were never placed and a top-left Go button click (test `:558-574`)
   never landed; `ScreenDriver.show_screen()` (test `:34-43`) creates
   NextScreen synchronously and `Game.goto()` calls `show_screen` before
   `screen_changed.emit` (`game/core/game.gd:86-87`), so "NextScreen missing"
   was the correct downstream report. Why the many other
   `set_anchors_preset(PRESET_FULL_RECT)` call sites in this codebase do not
   indict the diagnosis: the ones inspected call it *before* `add_child`
   (no parent → zero parent rect → offsets stay 0; e.g. `settings.gd:18,24,27`,
   test `:37,214,556`) or in `_ready` of scene roots whose `.tscn` already
   carries full-rect anchors (see finding 2). The overlay was the only
   zero-size, already-parented case. Decisive corroboration: the controller's
   headless pass follows a single production-line change. One honest caveat:
   the exact pre-fix box rect that ate the Go click was not independently
   captured (Sol labels his numbers predictions); causality rests on the
   one-line-change pass, which is sufficient. No diff.

2. **Fix fills the host in the real game, including after resize. Severity: none (confirmed).**
   Chain: `main.gd:1` extends `Node`, so a screen Control's anchorable rect is
   the root window; `settings.tscn:7-9` gives the real host
   `anchors_preset = 15, anchor_right/bottom = 1.0` (offsets 0), so Settings
   fills and tracks the window regardless of `settings.gd:13`. The overlay,
   now anchors (0,0,1,1) + offsets (0,0,0,0), is re-derived from the host rect
   by the engine on every host resize — no code needs to run for the *size* to
   track — and `resized.connect(_layout)` (`tutorial_overlay.gd:84`) plus the
   recompute at `:185` move the cut-out/box immediately. The fix is also
   timing-robust where the old code was not: if the host is still 0-sized at
   `_ready` (Settings resume path, `settings.gd:51-52`), offsets are 0 anyway
   and the overlay fills as soon as the host is sized. The reparent path
   already used the same call (`tutorial_overlay.gd:313`), and the real
   `main.gd:54-65` `queue_free()`s the old screen and instantiates the new one
   before `screen_changed`, matching `_on_screen_changed`'s assumptions
   (`:306-313`). No diff.

3. **No assertion weakened, skipped, or made vacuous. Severity: none (confirmed, independently counted).**
   This review counted in the current test file: exactly **79** `check(` call
   sites (78 original + the new fill assertion at `:162-163`), exactly **26**
   `_in_tree(` guard call expressions (excluding the definition at `:62`;
   `:149` carries 3, `:155` carries 2), and exactly **9** `_geometry(` calls
   — all matching Sol's claims. Non-vacuity structure: `_in_tree` records a
   `check(false, ...)` *before* any guard returns (`:63-69`), so every early
   `return _finish(...)` still fails the run; looped checks have non-empty
   guards in front (shipped steps `:197`, blocker loop back-stopped by the
   dim-area identity `:173`, fixed 3-button loop `:181`); null-button paths
   double-record via `_button/_control` (`:79-83`) before the short-circuited
   condition at `:184`. Conditions and thresholds in `_layouts`
   (`:162-185`: encloses, centre ≤ 2.0, size distance ≤ 18.0 vs PAD-grown
   √(12²+12²)=17.0, area identity < 2.0) are non-trivial, and the new
   `:162` (`overlay.size == viewport.get_visible_rect().size and
   overlay.position == Vector2.ZERO`) is a direct regression guard for this
   exact bug. Input is still real viewport picking (`push_input`, `:99-126`),
   no `pressed.emit` shortcut. No diff.

4. **Every symbol exists; no GDScript parse risk. Severity: none (confirmed).**
   `Control.set_anchors_and_offsets_preset(preset)` with one argument and
   unqualified `PRESET_FULL_RECT` inside a `Control` subclass are Godot 4 API
   and were already used in this same file (`:313`). New test code uses only:
   `Viewport.get_visible_rect()` (also `game/ui/kit.gd:30,37`),
   `CanvasItem.get_global_transform_with_canvas()` + `affine_inverse()`,
   `Transform2D * Rect2`, `Rect2.has_area/encloses/intersects`,
   `overlay.highlight_rect()` (`tutorial_overlay.gd:94`). `_geometry`
   (`test :129-145`): 7 format placeholders, 7 arguments; validity is checked
   before any property read (`:136-143`), so its freed-target branch (exercised
   at `:577` with the dead Go button) and missing-overlay branch are safe;
   inferred locals start from concrete `String/Rect2/Vector2`. The controller's
   passing Godot 4.7 run empirically retires parse risk for all exercised
   paths; the unexercised branches above were read statically. No diff.

5. **Same anchors-only idiom remains in the host screen. Severity: Low (latent, pre-existing, not Sol's diff).**
   `game/ui/settings.gd:13` still calls `set_anchors_preset(PRESET_FULL_RECT)`
   in `_ready`. It is harmless today only because `settings.tscn:7-9` already
   makes the root full-rect; if Settings were ever instantiated from a bare
   script (as its own header at `settings.gd:4-5` suggests for overlay use,
   via the `.tscn`, so currently safe) the same trap would arm. Optional
   one-line hardening, no behaviour change today:
   ```diff
   --- a/game/ui/settings.gd
   +++ b/game/ui/settings.gd
   @@
   	theme = UiTheme.get_theme()
   -	set_anchors_preset(PRESET_FULL_RECT)
   +	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
   	mouse_filter = MOUSE_FILTER_STOP
   ```

6. **Geometry oracle now shares the SUT's transform. Severity: Low (test-methodology, compensated).**
   The new `expected` rect (`test :161`) is built with the identical
   canvas-transform formula as the code under test
   (`tutorial_overlay.gd:227-228`), so a common-mode transform error would
   pass `:164-167`. In this harness the SubViewport transform is identity and
   independence is restored end-to-end by real picking: `_press` clicks are
   pushed in viewport coordinates (`test :99-126`), so a misplaced hole would
   still fail the press counts. Optional independent cross-check inside
   `_layouts`, after `:161`:
   ```diff
   	var expected: Rect2 = overlay.get_global_transform_with_canvas().affine_inverse() * (target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size))
   +	var expected_global: Rect2 = target.get_global_rect()
   +	check(rect.get_center().distance_to(expected_global.get_center() - overlay.get_global_rect().position) <= 2.0,
   +		"highlight matches the independent global rect of %s at %s%s" % [target.name, str(sz), geometry])
   ```

7. **Remaining overlay bug the test does not catch: Esc leaves mid-tutorial. Severity: Low (pre-existing, recoverable, not Sol's diff).**
   The dim blocks mouse (`tutorial_overlay.gd:57`) and touch (`:126-143`), but
   not keys: `settings.gd:193-196` turns `ui_cancel` into `_back()` →
   `Game.goto(...)` even while the tutorial is active. The overlay then
   reparents to the new screen (`tutorial_overlay.gd:306-313`), its Settings
   anchors (`data/tutorial.json:7,13,19`) are absent there, and the player is
   met by a full dim + text box over e.g. the title screen. Not a soft-lock —
   all shipped steps are `kind: "next"`, so Next/Done or Skip exits — but it
   is reachable in the real game and no test case drives a key during a step.
   Suggested guard:
   ```diff
   --- a/game/ui/settings.gd
   +++ b/game/ui/settings.gd
   @@
   	if event.is_action_pressed("ui_cancel") and not event.is_echo():
   +		if get_node_or_null("TutorialOverlay") != null:
   +			get_viewport().set_input_as_handled()
   +			return   # the tutorial owns the screen until Next/Skip
   		_back()
   		get_viewport().set_input_as_handled()
   ```
   (Keyboard focus activation of non-highlighted buttons is the same class of
   gap; noted without a diff, as focus policy is a design call.)

8. **`_geometry` trusts its viewport argument. Severity: Info (diagnostics only).**
   `test :145` calls `viewport.get_visible_rect()` unguarded while target and
   overlay are guarded (`:136-143`). All 9 current call sites pass a live
   viewport, so there is no present risk; a future failure-path call with a
   freed viewport would crash the diagnostic instead of reporting. Optional:
   ```diff
   -	return " [viewport_size=%s ..." % [
   -		str(viewport.get_visible_rect().size), ...
   +	var vp_size := viewport.get_visible_rect().size if is_instance_valid(viewport) else Vector2.ZERO
   +	return " [viewport_size=%s ..." % [
   +		str(vp_size), ...
   ```

## Verdict

Sol's diagnosis is right, the one-line production fix is the correct and
complete fix for the 65 geometry/navigation failures in both the test harness
and the real game (window resize included), the test gained diagnostics and
one stronger assertion without losing or hollowing any of the original 78
assertions or 26 guards, and both edited scripts are symbol- and parse-clean.
Findings 5-8 are pre-existing or test-hardening nits, none of them blocks
v0.103. CLEAN.
