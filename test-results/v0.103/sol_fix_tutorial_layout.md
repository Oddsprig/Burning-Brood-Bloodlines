Static fix complete; runtime validation pending with the controller.

v0.103: initial status was "in progress". Diagnosis below was written before implementation edits. Godot and game tests were not run.

Diagnosis recorded before implementation edits (original line numbers)

- Systemic production bug: `game/ui/tutorial_overlay.gd:48-51` creates a zero-size Control and calls only `set_anchors_preset(PRESET_FULL_RECT)` after attachment. That changes anchors while preserving the existing rectangle through offsets. It does not reset offsets to fill the host. Consequently the overlay starts at zero size and later resizes by the host's size delta, rather than matching its full size. `_compute_rect()` returns an empty hole for a zero-size overlay (`:220-224`) and clips against the incorrectly sized overlay (`:228-237`); `_layout()` exits before positioning the dim and text box (`:181-183`). This affects the game as well as the test.
- Test setup already avoids headless DisplayServer resizing: `game/tests/test_tutorial_v103.gd:178-190` attaches an explicitly sized SubViewport before creating the host, and `_layouts()` sets `viewport.size` and waits four process frames plus 0.15 seconds (`:129-140`). Extra frames or a different viewport do not correct persistent offsets.
- The `NextScreen` / pressed-control failures share this path: the unpositioned text box occupies the Go button's top-left area, preventing the real click from reaching it (`game/tests/test_tutorial_v103.gd:530-546`). `ScreenDriver.show_screen()` creates NextScreen synchronously (`:34-43`); `Game.goto()` calls `main.show_screen()` before emitting `screen_changed` (`game/core/game.gd:78-87`). A blocked Go click leaves the old screen active, so NextScreen is correctly reported missing. This is a static causal finding, not a runtime verification.
- The mismatched StepOne/StepTwo fixture also clicks a top-left button (`game/tests/test_tutorial_v103.gd:487-497`) beneath that misplaced text box. The overlay already reports the actual anchor to `Tutorial.notify_button()` (`game/ui/tutorial_overlay.gd:291-294`), and the engine rejects mismatched completion anchors (`game/campaign/tutorial.gd:151-156`).

Pre-edit plan: reset anchors AND offsets in overlay `_ready()`, matching its existing reparent path (`game/ui/tutorial_overlay.gd:312`, original numbering). Preserve every assertion and missing-node failure, and add viewport/target/hole numbers to all geometry failure messages. No timing workaround or runtime test.

Implemented changes (final line numbers)

- `game/ui/tutorial_overlay.gd:51-52`: a `v0.103:` comment and `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` replace the anchors-only call. This is the entire production-code change. Resetting offsets fills the current host immediately and retains correct sizing through subsequent viewport resizes. For a host initially 1280x720, the old code predicts a 0x0 overlay initially and only 640x360 after resizing the host to 1920x1080; those are static predictions, not captured runtime measurements.
- `game/tests/test_tutorial_v103.gd:128-145`: `_geometry(viewport: Viewport, overlay, target) -> String` reports actual visible viewport size, overlay rectangle/position, target rectangle in viewport and overlay coordinates, and hole rectangle. Missing/freed objects are checked before reading their properties, including the old Go button after a successful screen change.
- `_layouts()` (`:148` onward) retains all existing geometry conditions and thresholds. Its expected rectangle now includes the target's canvas transform, matching the overlay's coordinate conversion. All highlight, dim, text-box and navigation geometry failures carry the numeric context; dim failures also carry areas, and blocker/text/navigation failures carry the relevant rectangles. One additional assertion requires the overlay to fill its resized viewport.
- Clipping/hidden-anchor, mismatched-action target, mobile navigation, screen-survival and destination checks also carry numeric context (`:493` onward). No button-signal shortcut, extra delay, skipped assertion, missing-node success, or screen-instantiation workaround was introduced. The deferred-attachment fix remains intact.

Static verification performed

- Compared original and final source in session memory without Git: all 78 original `check()` condition call sites remain unchanged; the final file has 79 with the new fill assertion. All 26 `_in_tree()` prerequisite guard call sites remain. Missing NextScreen/pressed controls still produce FAILs.
- Confirmed the production diff is exactly one replaced call plus its comment.
- Checked balanced delimiters/strings, all `check()` calls having two arguments, and all nine `_geometry()` calls having three arguments. New inferred locals start from concrete String, Rect2 or Vector2 values. Both edited scripts remain without a UTF-8 BOM.
- Reviewed referenced signatures: `highlight_rect() -> Rect2`, `current_target() -> Control`, and `blocker_rects() -> Array` are defined by the overlay; `Game.goto(screen: String, params: Dictionary = {}) -> void` and `Tutorial.notify_button(anchor: String) -> bool` match their unchanged call sites. The one-argument full-layout API is already used by the overlay's reparent path; the zero-argument `Viewport.get_visible_rect()` API is already used by `game/ui/kit.gd:30,37`.
- No Godot process, editor import, engine parser, game test or GPU test was launched. These are static source checks, not a current test pass. No result is marked passed or queued; runtime confirmation of the reported failures remains pending.

Scope and evidence

Used the supplied failure grouping and source inside this worktree. The historical log outside the authorized folder was not read. No files outside this worktree were changed, and no Git, downloads, installs or uploads were used.

Files changed:

- `game/ui/tutorial_overlay.gd`
- `game/tests/test_tutorial_v103.gd`
- `test-results/v0.103/sol_fix_tutorial_layout.md`
