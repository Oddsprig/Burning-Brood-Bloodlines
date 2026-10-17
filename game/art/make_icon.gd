extends SceneTree
## Writes the game icon PNGs:  godot --headless --path game -s res://art/make_icon.gd
## (tools/make_icon.sh wraps this). Output: res://icon.png (256) + res://art/icons/icon_{32,48,256}.png

func _init() -> void:
	var Icon := load("res://art/icon.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/icons"))
	var err: int = Icon.make_icon_image(256).save_png("res://icon.png")
	for s in [32, 48, 256]:
		err += Icon.make_icon_image(s).save_png("res://art/icons/icon_%d.png" % s)
	print("make_icon: ", "ok" if err == OK else "error %d" % err)
	quit(0 if err == OK else 1)
