extends SceneTree
## Headless phone benchmark launcher (v0.072). Light check of a 20v20 battle (max 20) and the campaign map, 180 frames each:
##   godot --headless --path game --script res://tools/bench_mobile.gd -- [--frames=180] [--size=20] [--mobile-profile]
## Same run as a scene:  godot --headless --path game res://tools/bench_mobile.tscn -- [options]
## Options (all optional): --frames=N (per benchmark, default 180)  --warmup=N (default 30)  --size=N (1..20, default 20; >20 rejected)
##   --speed=1|2|4 (battle)  --map-speed=1|2|4  --only=battle|map  --mobile-profile (phone settings on a PC)
## Autoloads (DB, Game, Perf) are added before _initialize but after this script compiled, so this launcher names
## none of them: it only opens the bench scene, whose script compiles once the autoloads exist.

func _initialize() -> void:
	if root.get_node_or_null("Game") == null:
		printerr("bench_mobile: autoloads are missing; run the scene instead: godot --headless --path game res://tools/bench_mobile.tscn")
		quit(2)
		return
	change_scene_to_file("res://tools/bench_mobile.tscn")
