extends RefCounted
## Used as `const MobilePerf := preload("res://core/mobile_perf.gd")` (no class_name, so a fresh checkout needs no
## editor class-cache rebuild before it runs).
## v0.072 phone performance profile: the one place that decides what a phone turns down. The desktop game is
## unchanged unless its player picks the 30 FPS battery saver. `-- --mobile-profile` applies the phone profile on a
## PC so a tester can measure it (tools/bench_mobile.gd).
##   frame cap: 60 FPS on phones (a 120 Hz panel would otherwise draw every frame twice), 30 FPS with
##     Settings -> Frame rate -> Battery saver (any platform; Game "battery_saver", saved with the settings)
##   low processor mode on menu screens: the engine redraws only when something on screen changes
##   no 2D MSAA, screen-space AA or debanding on the root viewport
##   cheap_fx(): false for 10v10-20v20 battles (full blood droplets/trails and round splats are already cheap at <=40 fighters;
##     players who want less gore have Settings -> Gore: Reduced)
##   the shared battle sprite cache is trimmed when a battle closes (Paperdoll.trim_cache)
## Renderer: gl_compatibility on every platform (project.godot). This is a 2D canvas game; the Compatibility
## renderer has the lowest per-draw cost and no Vulkan pipeline-compile stutters on Android.

const PHONE_FPS := 60
const BATTERY_FPS := 30
## Screens that animate every frame (simulation, travel, presim feed); every other screen is a menu.
const ANIMATED_SCREENS := ["map", "battle", "presim"]
## Sprite frames kept after a battle closes on a phone (the next battle re-rasters what it needs in the background).
const SPRITE_CACHE_IDLE_BYTES := 48 * 1024 * 1024

static var _forced := -1
static var _desktop_max_fps := -1

## True on phones (and with --mobile-profile).
static func active() -> bool:
	if _forced < 0:
		_forced = 1 if "--mobile-profile" in OS.get_cmdline_user_args() else 0
	return _forced == 1 or OS.has_feature("mobile")

## Effect layers keep full droplet counts and shapes on phones: at 10v10-20v20 (<=40 fighters), full GoreLayer effects
## are cheap, and Settings -> Gore already offers Full / Reduced.
static func cheap_fx() -> bool:
	return false

## Engine frame cap for the current platform and battery-saver choice.
static func apply_frame_cap(battery_saver: bool) -> void:
	if _desktop_max_fps < 0:
		_desktop_max_fps = int(ProjectSettings.get_setting("application/run/max_fps", 0))
	if battery_saver: Engine.max_fps = BATTERY_FPS
	elif active(): Engine.max_fps = PHONE_FPS
	else: Engine.max_fps = _desktop_max_fps

## Menus idle in low processor mode on phones; animated screens draw every frame.
static func on_screen(screen: String) -> void:
	if not active(): return
	OS.low_processor_usage_mode = not ANIMATED_SCREENS.has(screen)

## Root viewport quality for phones: no anti-aliasing passes (pixel art is drawn with nearest filtering anyway).
static func apply_viewport(vp: Viewport) -> void:
	if vp == null or not active(): return
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = false
