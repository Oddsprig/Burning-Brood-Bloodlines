extends SceneTree
## v0.072 mobile: Headless generator for Android launcher icons (192x192, 432x432 adaptive
## foreground/background) and boot splash (game/icon_mobile/splash.png).
## Run: godot --headless --path game -s res://tools/make_icon.gd

const PixelCanvasScript := preload("res://art/pixel_canvas.gd")

const OUT_DIR := "res://icon_mobile"
const ICON_192_PATH := "res://icon_mobile/icon_192.png"
const FG_432_PATH := "res://icon_mobile/adaptive_foreground_432.png"
const FG_ALT_PATH := "res://icon_mobile/adaptive_foreground.png"
const BG_432_PATH := "res://icon_mobile/adaptive_background_432.png"
const BG_ALT_PATH := "res://icon_mobile/adaptive_background.png"
const SPLASH_PATH := "res://icon_mobile/splash.png"

func _init() -> void:
	var res := generate_all(OUT_DIR)
	update_export_presets()
	print("make_icon: generated ", res)
	quit(0)

func _process(_delta: float) -> bool:
	return true

static func generate_all(out_dir: String = OUT_DIR) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var icon_192 := make_launcher_192()
	var fg_432 := make_adaptive_foreground_432()
	var bg_432 := make_adaptive_background_432()
	var splash := make_splash_image()
	icon_192.save_png(out_dir.path_join("icon_192.png"))
	fg_432.save_png(out_dir.path_join("adaptive_foreground_432.png"))
	fg_432.save_png(out_dir.path_join("adaptive_foreground.png"))
	bg_432.save_png(out_dir.path_join("adaptive_background_432.png"))
	bg_432.save_png(out_dir.path_join("adaptive_background.png"))
	splash.save_png(out_dir.path_join("splash.png"))
	return {
		"main_192x192": out_dir.path_join("icon_192.png"),
		"adaptive_foreground_432x432": out_dir.path_join("adaptive_foreground_432.png"),
		"adaptive_background_432x432": out_dir.path_join("adaptive_background_432.png"),
		"splash": out_dir.path_join("splash.png"),
	}

## Draws the dragon silhouette and crown on a 32x32 local coordinate frame.
static func _draw_dragon_emblem(cv, origin: Vector2, scale: float, with_shield: bool) -> void:
	cv.set_frame(origin, scale, 0.0)
	var rim := Color("c99846")
	var shield_outer := Color("3d1410")
	var shield_inner := Color("1c0a08")
	var wing_dark := Color("7a1f18")
	var body_red := Color("b33022")
	var highlight := Color("f08a4b")
	var gold := Color("e6bb5e")
	if with_shield:
		cv.begin()
		cv.poly(PackedVector2Array([
			Vector2(3, 1), Vector2(29, 1), Vector2(31, 3),
			Vector2(30, 21), Vector2(16, 31), Vector2(2, 21), Vector2(1, 3)
		]), rim)
		cv.end(Color("0d0504"), 0.14)
		cv.begin()
		cv.poly(PackedVector2Array([
			Vector2(4, 3), Vector2(28, 3), Vector2(28, 20),
			Vector2(16, 29), Vector2(4, 20)
		]), shield_outer)
		cv.end(Color("220907"), 0.08)
		cv.begin()
		cv.poly(PackedVector2Array([
			Vector2(5, 5), Vector2(27, 5), Vector2(26, 19),
			Vector2(16, 27), Vector2(6, 19)
		]), shield_inner)
		cv.end(Color(0, 0, 0, 0), 0.0)
	# Swept dragon wing, coiled body, arched neck, horned head, and tail.
	cv.begin()
	cv.poly(PackedVector2Array([
		Vector2(16, 20), Vector2(5, 7), Vector2(7, 15),
		Vector2(11, 14), Vector2(9, 19), Vector2(14, 18)
	]), wing_dark)
	cv.ellipse(Vector2(17, 21), 6.8, 4.0, body_red)
	cv.capsule(Vector2(19, 19), Vector2(18, 12), 2.5, body_red)
	cv.capsule(Vector2(18, 12), Vector2(22, 10), 1.8, body_red)
	cv.poly(PackedVector2Array([
		Vector2(20, 8), Vector2(23, 7), Vector2(23, 9),
		Vector2(28, 11), Vector2(24, 13), Vector2(21, 12)
	]), body_red)
	cv.poly(PackedVector2Array([
		Vector2(13, 22), Vector2(8, 23), Vector2(7, 19),
		Vector2(5, 17), Vector2(5, 23), Vector2(10, 27), Vector2(18, 24)
	]), body_red)
	cv.end(Color("160605"), 0.16, highlight)
	# Wing ribs, glowing eye, and bloodline crown.
	cv.begin()
	cv.line1(Vector2(8, 10), Vector2(15, 19), highlight)
	cv.line1(Vector2(14, 22), Vector2(20, 22), highlight.darkened(0.15))
	cv.ellipse(Vector2(23, 10), 0.7, 0.7, gold)
	cv.poly(PackedVector2Array([
		Vector2(11, 7), Vector2(10, 3), Vector2(13, 5),
		Vector2(16, 2), Vector2(19, 5), Vector2(22, 3), Vector2(21, 7)
	]), gold)
	cv.end(Color("160605"), 0.08)

static func _fill_ember_gradient(cv, w: int, h: int, top_col: Color, bot_col: Color, glow_col: Color) -> void:
	var center := Vector2(w * 0.5, h * 0.46)
	var radius := minf(w, h) * 0.52
	for y in h:
		var ty := float(y) / maxf(1.0, float(h - 1))
		var base := top_col.lerp(bot_col, ty)
		for x in w:
			var d := Vector2(x, y).distance_to(center) / radius
			var glow := clampf(1.0 - d, 0.0, 1.0)
			cv.set_px(x, y, base.lerp(glow_col, glow * glow * 0.55))

## 192x192 main launcher icon.
static func make_launcher_192() -> Image:
	var cv = PixelCanvasScript.new(192, 192)
	_fill_ember_gradient(cv, 192, 192, Color("180806"), Color("38110c"), Color("682016"))
	_draw_dragon_emblem(cv, Vector2.ZERO, 6.0, true)
	return cv.to_image()

## 432x432 adaptive foreground: dragon silhouette in safe 66% centre (256x256 inside 285x285 safe zone).
static func make_adaptive_foreground_432() -> Image:
	var cv = PixelCanvasScript.new(432, 432)
	# Safe 66% of 432 is 285.12 px ([74..358]); origin=(88,88) + 32*8.0=256 spans [88..344].
	_draw_dragon_emblem(cv, Vector2(88, 88), 8.0, false)
	return cv.to_image()

## 432x432 adaptive background: dark red / ember gradient.
static func make_adaptive_background_432() -> Image:
	var cv = PixelCanvasScript.new(432, 432)
	_fill_ember_gradient(cv, 432, 432, Color("160705"), Color("4a150f"), Color("7c261b"))
	return cv.to_image()

## Boot splash image (centered emblem on dark background matching boot_splash/bg_color).
static func make_splash_image() -> Image:
	var w := 480
	var h := 270
	var bg := Color("15100d")
	var glow := Color("4c1913")
	var cv = PixelCanvasScript.new(w, h)
	var center := Vector2(w * 0.5, h * 0.5)
	var radius := minf(w, h) * 0.45
	for y in h:
		for x in w:
			var d := Vector2(x, y).distance_to(center) / radius
			var g := clampf(1.0 - d, 0.0, 1.0)
			cv.set_px(x, y, bg.lerp(glow, g * g * 0.45))
	# 32 * 5.0 = 160x160 centered at (240, 135) -> origin (160, 55).
	_draw_dragon_emblem(cv, Vector2(160, 55), 5.0, true)
	return cv.to_image()

static func update_export_presets(path: String = "res://export_presets.cfg") -> bool:
	if not FileAccess.file_exists(path):
		return false
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return false
	var updated := false
	for section in cfg.get_sections():
		if section.ends_with(".options"):
			cfg.set_value(section, "launcher_icons/main_192x192", ICON_192_PATH)
			cfg.set_value(section, "launcher_icons/adaptive_foreground_432x432", FG_432_PATH)
			cfg.set_value(section, "launcher_icons/adaptive_background_432x432", BG_432_PATH)
			updated = true
	if updated:
		cfg.save(path)
	return updated
